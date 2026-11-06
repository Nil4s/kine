"""INDEPENDENT READER for the skinned USD export (L14, GAP_AUDIT_1106 #10).  Run inside headless Blender (it ships Pixar's pxr):

    blender -b --factory-startup --python tools/usdskin_check.py -- <dir>

<dir>/cases.json = [{"name", "usda", "ref", "shift", "metrics": [...]}]. <dir>/report.json is written, one entry per case.
Nothing here imports Kine code or reads the writer's logic: the .usda is read by pxr (UsdSkel schema classes) and by Blender's
own USD importer (bpy.ops.wm.usd_import, armature + vertex groups + shape keys, evaluated through the depsgraph).
ref.json (written by tests/usdskin_test.gd from Kine's own pose): joints, per-vertex weights BY JOINT NAME, shape offsets, the
deformed mesh per frame (Kine's linear blend skin with the shapes first), the same without shapes, the shape weights per frame.

metrics:  struct   counts of SkelRoot / Skeleton / Mesh / BlendShape, joints, vertices, influences, shapes vs ref["expect"]
          weights  per-vertex weights by joint name (pxr), max abs error vs ref, max |sum - 1|; Blender vertex groups the same
          offsets  BlendShape names and offsets (pointIndices expanded) vs ref, SkelAnimation blendShapeWeights vs ref
          deform   Blender imports, poses frame f + shift: world vertices vs ref["deform"][f] (Y-up); also pxr skinning
          effect   Blender: the shapes' own displacement at frame f (pose held, shape keys zeroed) vs the ref's
"""
import json
import math
import os
import sys
import traceback

from pxr import Gf, Sdf, Usd, UsdGeom, UsdSkel, Vt

HERE = os.path.dirname(os.path.abspath(__file__))


def args_after_dashes():
    a = sys.argv
    return a[a.index("--") + 1:] if "--" in a else []


def leaf(p):
    return str(p).split("/")[-1]


# ---------------------------------------------------------------- pxr (the schema reader)
def pxr_open(path):
    st = Usd.Stage.Open(path)
    if not st:
        raise RuntimeError("pxr cannot open " + path)
    return st


def first(st, tname):
    return [p for p in st.Traverse() if p.GetTypeName() == tname]


def pxr_struct(st, ref):
    roots, skels, meshes, shapes, anims = (first(st, t) for t in ("SkelRoot", "Skeleton", "Mesh", "BlendShape", "SkelAnimation"))
    got = {"skelroots": len(roots), "skeletons": len(skels), "meshes": len(meshes), "blendshape_prims": len(shapes), "anims": len(anims)}
    if skels:
        got["joints"] = len(UsdSkel.Skeleton(skels[0]).GetJointsAttr().Get() or [])
        got["bind"] = len(UsdSkel.Skeleton(skels[0]).GetBindTransformsAttr().Get() or [])
        got["rest"] = len(UsdSkel.Skeleton(skels[0]).GetRestTransformsAttr().Get() or [])
    if anims:
        got["anim_joints"] = len(UsdSkel.Animation(anims[0]).GetJointsAttr().Get() or [])
    if meshes:
        m = meshes[0]
        mesh = UsdGeom.Mesh(m)
        b = UsdSkel.BindingAPI(m)
        pts = mesh.GetPointsAttr().Get() or []
        ji = b.GetJointIndicesPrimvar()
        jw = b.GetJointWeightsPrimvar()
        got["verts"] = len(pts)
        got["faces"] = len(mesh.GetFaceVertexCountsAttr().Get() or [])
        got["k"] = ji.GetElementSize() if ji else 0
        got["kw"] = jw.GetElementSize() if jw else 0
        got["idx_len"] = len(ji.Get() or []) if ji else 0
        got["w_len"] = len(jw.Get() or []) if jw else 0
        got["has_geombind"] = bool(b.GetGeomBindTransformAttr().HasAuthoredValue())
        got["skel_rel"] = len(b.GetSkeletonRel().GetTargets())
        names = list(b.GetBlendShapesAttr().Get() or [])
        got["shapes_mesh"] = len(names)
        got["targets"] = len(b.GetBlendShapeTargetsRel().GetTargets())
    if anims:
        got["shapes_anim"] = len(UsdSkel.Animation(anims[0]).GetBlendShapesAttr().Get() or [])
        ts = UsdSkel.Animation(anims[0]).GetBlendShapeWeightsAttr().GetTimeSamples()
        got["weight_samples"] = len(ts)
        got["weight_len"] = len(UsdSkel.Animation(anims[0]).GetBlendShapeWeightsAttr().Get(ts[0]) or []) if ts else 0
    got["offs_len"] = {p.GetName(): len(UsdSkel.BlendShape(p).GetOffsetsAttr().Get() or []) for p in shapes}
    got["sparse"] = {p.GetName(): len(UsdSkel.BlendShape(p).GetPointIndicesAttr().Get() or []) for p in shapes}
    ex = ref["expect"]
    bad = []
    for k in ("skelroots", "skeletons", "meshes", "blendshape_prims", "joints", "bind", "rest", "anim_joints", "verts", "faces", "k", "kw", "shapes_mesh",
              "targets", "shapes_anim", "weight_len"):
        if got.get(k) != ex[k]:
            bad.append("%s %s != %s" % (k, got.get(k), ex[k]))
    if got.get("idx_len") != ex["verts"] * ex["k"] or got.get("w_len") != ex["verts"] * ex["k"]:
        bad.append("influence arrays %s/%s != %d" % (got.get("idx_len"), got.get("w_len"), ex["verts"] * ex["k"]))
    for n, c in ex["offs_len"].items():
        if got["offs_len"].get(n) != c:
            bad.append("shape %s offsets %s != %s" % (n, got["offs_len"].get(n), c))
    if not got.get("has_geombind") or not got.get("skel_rel"):
        bad.append("geomBindTransform / skel:skeleton missing")
    return {"got": got, "mismatch": bad}


def pxr_weights(st, ref):
    sk = UsdSkel.Skeleton(first(st, "Skeleton")[0])
    joints = [leaf(j) for j in sk.GetJointsAttr().Get()]
    m = first(st, "Mesh")[0]
    b = UsdSkel.BindingAPI(m)
    # a mesh may restrict itself to a joint subset (skel:joints); this exporter does not, so the indices address the skeleton's list
    mj = b.GetJointsAttr().Get()
    if mj:
        joints = [leaf(j) for j in mj]
    ji = b.GetJointIndicesPrimvar()
    jw = b.GetJointWeightsPrimvar()
    k = ji.GetElementSize()
    idx = list(ji.Get())
    w = list(jw.Get())
    nv = len(idx) // k
    worst = 0.0
    wsum = 0.0
    for v in range(nv):
        d = {}
        s = 0.0
        for q in range(k):
            x = w[v * k + q]
            s += x
            if x > 0.0:
                i = idx[v * k + q]
                nm = joints[i] if 0 <= i < len(joints) else "OUT_OF_RANGE_%d" % i
                d[nm] = d.get(nm, 0.0) + x
        wsum = max(wsum, abs(s - 1.0))
        r = ref["weights"][v]
        for nm in set(d) | set(r):
            worst = max(worst, abs(d.get(nm, 0.0) - r.get(nm, 0.0)))
    return {"max_err": worst, "max_sum_err": wsum, "verts": nv, "k": k}


def pxr_offsets(st, ref):
    m = first(st, "Mesh")[0]
    b = UsdSkel.BindingAPI(m)
    names = list(b.GetBlendShapesAttr().Get() or [])
    targets = [str(t) for t in b.GetBlendShapeTargetsRel().GetTargets()]
    worst = 0.0
    seen = []
    nv = len(UsdGeom.Mesh(m).GetPointsAttr().Get())
    for nm, tp in zip(names, targets):
        p = st.GetPrimAtPath(tp)
        seen.append(nm)
        if not p or nm not in ref["shapes"]:
            worst = max(worst, 1e9)
            continue
        bs = UsdSkel.BlendShape(p)
        offs = bs.GetOffsetsAttr().Get()
        pi = bs.GetPointIndicesAttr().Get()
        full = [(0.0, 0.0, 0.0)] * nv
        if pi:
            for i, o in zip(pi, offs):
                full[i] = (o[0], o[1], o[2])
        else:
            full = [(o[0], o[1], o[2]) for o in offs]
        want = ref["shapes"][nm]["offsets"]
        if len(full) != len(want):
            worst = max(worst, 1e9)
            continue
        for a, c in zip(full, want):
            worst = max(worst, abs(a[0] - c[0]), abs(a[1] - c[1]), abs(a[2] - c[2]))
    names_ok = sorted(seen) == sorted(ref["shapes"].keys())
    # the animation's weights per frame
    anim = UsdSkel.Animation(first(st, "SkelAnimation")[0])
    an = list(anim.GetBlendShapesAttr().Get() or [])
    wa = anim.GetBlendShapeWeightsAttr()
    werr = 0.0
    for f, want in ref["shape_w"].items():
        got = wa.Get(float(f))
        if got is None or len(got) != len(an):
            werr = max(werr, 1e9)
            continue
        for nm, x in zip(an, got):
            werr = max(werr, abs(x - want.get(nm, 0.0)))
    return {"names_ok": names_ok, "names": names, "max_offset_err": worst, "weights_err": werr, "anim_names": an}


def pxr_skin(st, ref, shift):
    """pxr's own UsdSkel skinning (SkinningQuery.ComputeSkinnedPoints) at each ref frame; the shapes are added by hand first"""
    cache = UsdSkel.Cache()
    root = UsdSkel.Root(first(st, "SkelRoot")[0])
    cache.Populate(root, Usd.TraverseInstanceProxies())
    out = {}
    binding = cache.ComputeSkelBindings(root, Usd.TraverseInstanceProxies())[0]
    skq = cache.GetSkelQuery(binding.GetSkeleton())
    sq = binding.GetSkinningTargets()[0]
    m = sq.GetPrim()
    base = list(UsdGeom.Mesh(m).GetPointsAttr().Get())
    b = UsdSkel.BindingAPI(m)
    names = list(b.GetBlendShapesAttr().Get() or [])
    targets = [str(t) for t in b.GetBlendShapeTargetsRel().GetTargets()]
    shp = []
    for nm, tp in zip(names, targets):
        bs = UsdSkel.BlendShape(st.GetPrimAtPath(tp))
        offs = bs.GetOffsetsAttr().Get()
        pi = bs.GetPointIndicesAttr().Get()
        idx = list(pi) if pi else list(range(len(offs)))
        shp.append((nm, idx, list(offs)))
    anim = UsdSkel.Animation(first(st, "SkelAnimation")[0])
    an = list(anim.GetBlendShapesAttr().Get() or [])
    worst = {}
    for f in ref["frames"]:
        t = float(f + shift)
        wv = dict(zip(an, anim.GetBlendShapeWeightsAttr().Get(t) or []))
        pts = [Gf.Vec3f(p) for p in base]
        for nm, idx, offs in shp:
            x = wv.get(nm, 0.0)
            for i, o in zip(idx, offs):
                pts[i] = pts[i] + Gf.Vec3f(o) * x
        vp = Vt.Vec3fArray(pts)
        xf = skq.ComputeSkinningTransforms(t)
        if not sq.ComputeSkinnedPoints(xf, vp, t):
            worst[f] = 1e9
            continue
        want = ref["deform"][str(f)]
        e = 0.0
        for i, p in enumerate(vp):
            e = max(e, abs(p[0] - want[i * 3]), abs(p[1] - want[i * 3 + 1]), abs(p[2] - want[i * 3 + 2]))
        worst[f] = e
    return worst


# ---------------------------------------------------------------- Blender (the importer)
def blender_import(path):
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    r = bpy.ops.wm.usd_import(filepath=path, import_skeletons=True, import_blendshapes=True, import_meshes=True, set_frame_range=True,
                              import_materials=False, import_cameras=False, import_lights=False)
    return r


def find_mesh(nv):
    import bpy
    for o in bpy.data.objects:
        if o.type == "MESH" and len(o.data.vertices) == nv:
            return o
    return None


def zup_to_yup(v):
    # Blender is Z-up; the stage is Y-up (importer rotates the stage root by +90 deg about X): (x, y, z)blender -> (x, z, -y)
    return (v[0], v[2], -v[1])


def world_points(obj):
    import bpy
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ev.matrix_world
    pts = [zup_to_yup(mw @ v.co) for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def blender_deform(path, ref, shift, want_effect):
    import bpy
    blender_import(path)
    nv = ref["expect"]["verts"]
    obj = find_mesh(nv)
    if obj is None:
        return {"error": "no mesh with %d vertices after import (%s)" % (nv, [o.name for o in bpy.data.objects])}
    info = {"fps": bpy.context.scene.render.fps, "frame_start": bpy.context.scene.frame_start, "frame_end": bpy.context.scene.frame_end,
            "objects": [(o.name, o.type) for o in bpy.data.objects], "armature_modifier": [m.type for m in obj.modifiers],
            "shape_keys": [k.name for k in obj.data.shape_keys.key_blocks] if obj.data.shape_keys else []}
    out = {"info": info, "deform": {}, "effect": {}, "shape_value": {}}
    # Blender's vertex groups by name (the importer's reading of the weights)
    vg = {g.index: g.name for g in obj.vertex_groups}
    wv = 0.0
    wsum = 0.0
    for v in obj.data.vertices:
        d = {}
        for g in v.groups:
            if g.weight > 0.0:
                d[vg[g.group]] = d.get(vg[g.group], 0.0) + g.weight
        wsum = max(wsum, abs(sum(d.values()) - 1.0)) if d else wsum
        r = ref["weights"][v.index]
        for nm in set(d) | set(r):
            wv = max(wv, abs(d.get(nm, 0.0) - r.get(nm, 0.0)))
    out["groups_err"] = wv
    out["groups_sum_err"] = wsum
    for f in ref["frames"]:
        bpy.context.scene.frame_set(int(f + shift))
        pts = world_points(obj)
        want = ref["deform"][str(f)]
        e = 0.0
        for i, p in enumerate(pts):
            e = max(e, abs(p[0] - want[i * 3]), abs(p[1] - want[i * 3 + 1]), abs(p[2] - want[i * 3 + 2]))
        out["deform"][f] = e
        if obj.data.shape_keys:
            kv = {k.name: k.value for k in obj.data.shape_keys.key_blocks}
            sw = ref["shape_w"][str(f)]
            out["shape_value"][f] = max([abs(kv.get(n, 0.0) - x) for n, x in sw.items()] or [0.0])
        if want_effect and obj.data.shape_keys:
            keep = {k.name: k.value for k in obj.data.shape_keys.key_blocks}
            for k in obj.data.shape_keys.key_blocks:
                if k.name != obj.data.shape_keys.reference_key.name:
                    k.value = 0.0
            bpy.context.view_layer.update()
            p0 = world_points(obj)
            for k in obj.data.shape_keys.key_blocks:
                if k.name in keep:
                    k.value = keep[k.name]
            bpy.context.view_layer.update()
            wn = ref["deform_noshape"][str(f)]
            e2 = 0.0
            moved = 0.0
            for i in range(nv):
                for a in range(3):
                    dgot = pts[i][a] - p0[i][a]
                    dwant = want[i * 3 + a] - wn[i * 3 + a]
                    e2 = max(e2, abs(dgot - dwant))
                    moved = max(moved, abs(dwant))
            out["effect"][f] = {"err": e2, "expected_move": moved}
    return out


def run_case(c):
    ref = json.load(open(c["ref"]))
    path = c["usda"]
    shift = int(c.get("shift", 0))
    res = {"name": c["name"]}
    st = None
    for m in c["metrics"]:
        try:
            if m == "struct":
                st = st or pxr_open(path)
                res["struct"] = pxr_struct(st, ref)
            elif m == "weights":
                st = st or pxr_open(path)
                res["weights"] = pxr_weights(st, ref)
            elif m == "offsets":
                st = st or pxr_open(path)
                res["offsets"] = pxr_offsets(st, ref)
            elif m == "pxrskin":
                st = st or pxr_open(path)
                res["pxrskin"] = pxr_skin(st, ref, shift)
            elif m in ("deform", "effect"):
                if "blender" not in res:
                    res["blender"] = blender_deform(path, ref, shift, "effect" in c["metrics"])
        except Exception as e:   # a broken control file may not even open: that is a catch, reported, not a crash
            res[m + "_error"] = "%s: %s" % (type(e).__name__, e)
            res[m + "_trace"] = traceback.format_exc()[-600:]
    return res


def main():
    a = args_after_dashes()
    d = a[0]
    cases = json.load(open(os.path.join(d, "cases.json")))
    rep = {}
    for c in cases:
        rep[c["name"]] = run_case(c)
        json.dump(rep, open(os.path.join(d, "report.json"), "w"), indent=1, default=str)
    print("USDSKIN_CHECK_DONE", len(cases))


main()
