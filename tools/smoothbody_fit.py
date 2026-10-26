# blender -b --python fit_to_kine.py -- <mannequin.glb> <candidate.gl(b|tf)> <out.glb> [decimate_ratio] [drop_mesh_substr,...]
# Poses the candidate's own armature so every bone head sits on the Kine mannequin's same-named bone head and points
# at its primary child (Stretch To: length matches), bakes that pose into the mesh with dual-quaternion skinning,
# then re-parents the mesh (its vertex groups renamed to the mannequin's bone names) to the mannequin armature.
import bpy, sys, math
argv = sys.argv[sys.argv.index("--") + 1:]
MAN, CAND, OUT = argv[0], argv[1], argv[2]
DEC = float(argv[3]) if len(argv) > 3 else 1.0
DROP = [s for s in (argv[4].split(",") if len(argv) > 4 else []) if s]
SMOOTH = [int(x) for x in argv[5].split(",")] if len(argv) > 5 and argv[5] else []   # [head iterations, body iterations]: the "minimalist" pass
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)

def imp(p, guess=False):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=p, bone_heuristic='TEMPERANCE', guess_original_bind_pose=guess)
    return [o for o in bpy.data.objects if o not in before]

mo = imp(MAN)
Am = [o for o in mo if o.type == 'ARMATURE'][0]
for o in mo:
    if o.type == 'MESH':
        bpy.data.objects.remove(o)
co = imp(CAND, True)   # the candidate's rest from its inverse binds (MPFB's joint nodes sit off them)
Ac = [o for o in co if o.type == 'ARMATURE'][0]
meshes = [o for o in co if o.type == 'MESH' and o.vertex_groups]   # (MPFB's file also holds a stray unskinned Icosphere)
for o in list(meshes):
    if any(s.lower() in o.name.lower() for s in DROP):
        meshes.remove(o); bpy.data.objects.remove(o)
print("DBG Ac", Ac.name, tuple(Ac.matrix_world.translation), "Am", tuple(Am.matrix_world.translation), "Am rot", tuple(Am.matrix_world.to_euler()))
for o in meshes:
    print("DBG mesh", o.name, "parent", o.parent.name if o.parent else None, "ptype", o.parent_type, tuple(o.matrix_world.translation), [m.type + ":" + str(getattr(m, "object", None)) for m in o.modifiers])
mnames = {b.name.lower(): b.name for b in Am.data.bones}
def mname(n):
    return mnames.get(n.lower())

CHILD = {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head",
         "hand_l": "middle_01_l", "hand_r": "middle_01_r"}
def primary_child(arm, b):
    n = b.name.lower()
    if n in CHILD:
        return CHILD[n]
    kids = [c for c in b.children if mname(c.name)]
    return kids[0].name.lower() if len(kids) == 1 else None

# candidate edit bones: tail on the primary child's head (the rest pose of the mesh does not move)
bpy.context.view_layer.objects.active = Ac
bpy.ops.object.mode_set(mode='EDIT')
eb = Ac.data.edit_bones
lk = {b.name.lower(): b for b in eb}
for b in eb:
    c = primary_child(Ac, Ac.data.bones[b.name]) if b.name in Ac.data.bones else None
    if c and c in lk and (lk[c].head - b.head).length > 1e-4:
        b.use_connect = False
        b.tail = lk[c].head.copy()
        lk[c].use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')
miss = []
for pb in Ac.pose.bones:
    pb.bone.inherit_scale = 'NONE'
    for c in list(pb.constraints):
        pb.constraints.remove(c)
    mn = mname(pb.name)
    if not mn:
        miss.append(pb.name); continue
    cl = pb.constraints.new('COPY_LOCATION'); cl.target = Am; cl.subtarget = mn
    ch = primary_child(Ac, pb.bone)
    if pb.name.lower() != "root" and ch and mname(ch) and ch in [x.name.lower() for x in Ac.data.bones]:
        st = pb.constraints.new('STRETCH_TO'); st.target = Am; st.subtarget = mname(ch); st.head_tail = 0.0
        st.volume = 'NO_VOLUME'; st.rest_length = pb.bone.length; st.keep_axis = 'SWING_Y'
print("candidate bones with no mannequin twin:", miss)
# THE SPINE keeps its own spacing: spine_01..03 are not snapped one by one onto the mannequin's (uneven stretches crease
# the chest) but carried along with the candidate's pelvis -> neck line mapped onto the mannequin's (rotate + scale).
def wh(arm, n):
    for b in arm.data.bones:
        if b.name.lower() == n:
            return arm.matrix_world @ b.head_local
    return None
Pc, Nc, Pm, Nm = wh(Ac, "pelvis"), wh(Ac, "neck_01"), wh(Am, "pelvis"), wh(Am, "neck_01")
SPINE = ["spine_01", "spine_02", "spine_03"]
if None not in (Pc, Nc, Pm, Nm):
    q = (Nc - Pc).rotation_difference(Nm - Pm)
    k = (Nm - Pm).length / (Nc - Pc).length
    emp = {}
    for n in SPINE:
        c = wh(Ac, n)
        if c is None:
            continue
        e = bpy.data.objects.new("tgt_" + n, None)
        bpy.context.scene.collection.objects.link(e)
        e.location = Pm + (q @ (c - Pc)) * k
        emp[n] = e
    for pb in Ac.pose.bones:
        n = pb.name.lower()
        for c in pb.constraints:
            if c.type == 'COPY_LOCATION' and n in emp:
                c.target = emp[n]; c.subtarget = ""
            if c.type == 'STRETCH_TO' and c.subtarget.lower() in emp:
                c.target = emp[c.subtarget.lower()]; c.subtarget = ""
    print("spine targets", {n: tuple(round(x, 3) for x in emp[n].location) for n in emp})
bpy.context.view_layer.update()
for pb in Ac.pose.bones:
    mn = mname(pb.name)
    h = Ac.matrix_world @ pb.head
    t = (Am.matrix_world @ Am.pose.bones[mn].head) if mn else h
    sc = (Ac.matrix_world @ pb.matrix).to_scale()
    if (h - t).length > 0.002 or max(sc) > 1.6 or min(sc) < 0.6:
        print("BADBONE", pb.name, "gap %.3f" % (h - t).length, "scale", tuple(round(x, 2) for x in sc))
# bake the pose into the mesh (dual quaternion: no candy-wrapper at the shoulder)
for o in meshes:
    zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
    print("DBG src z range", min(zs), max(zs))
    bpy.context.view_layer.objects.active = o
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    mod = [m for m in o.modifiers if m.type == 'ARMATURE']
    if not mod:
        mod = [o.modifiers.new("Armature", 'ARMATURE')]
    mod[0].object = Ac
    mod[0].use_deform_preserve_volume = True
    for m in list(o.modifiers):
        if m.type == 'ARMATURE':
            bpy.ops.object.modifier_apply(modifier=m.name)
    zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
    print("DBG baked z range", min(zs), max(zs))
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for vg in o.vertex_groups:
        mn = mname(vg.name)
        if mn:
            vg.name = mn
    if SMOOTH:
        # glTF splits vertices along UV / normal seams: weld them first or the smoothing tears the islands apart
        bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=1e-5); bpy.ops.object.mode_set(mode='OBJECT')
        # face and muscle detail softened: Laplacian smoothing (volume kept), strong on the head's vertex group, light everywhere
        hv = o.vertex_groups.get("Head") or o.vertex_groups.get("head")
        nk = o.vertex_groups.get("neck_01")
        if hv and SMOOTH[0] > 0:
            g = o.vertex_groups.new(name="_smooth_head")
            for v in o.data.vertices:
                w = 0.0
                for ge in v.groups:
                    if ge.group == hv.index:
                        w += ge.weight
                    elif nk and ge.group == nk.index:
                        w += 0.5 * ge.weight
                if w > 0:
                    g.add([v.index], min(1.0, w), 'REPLACE')
            ls = o.modifiers.new("LsHead", 'LAPLACIANSMOOTH'); ls.iterations = SMOOTH[0]; ls.lambda_factor = 1.0
            ls.vertex_group = g.name; ls.use_volume_preserve = True; ls.use_normalized = True
            bpy.ops.object.modifier_apply(modifier=ls.name)
            o.vertex_groups.remove(o.vertex_groups["_smooth_head"])
        if len(SMOOTH) > 1 and SMOOTH[1] > 0:
            ls = o.modifiers.new("LsBody", 'LAPLACIANSMOOTH'); ls.iterations = SMOOTH[1]; ls.lambda_factor = 0.6
            ls.use_volume_preserve = True; ls.use_normalized = True
            bpy.ops.object.modifier_apply(modifier=ls.name)
    if DEC < 1.0:
        d = o.modifiers.new("Dec", 'DECIMATE'); d.ratio = DEC; d.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=d.name)
    a = o.modifiers.new("Armature", 'ARMATURE'); a.object = Am
    o.parent = Am
    o.matrix_parent_inverse = Am.matrix_world.inverted()
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("MESH", o.name, "verts", len(o.data.vertices), "tris", tris)
bpy.data.objects.remove(Ac)
bpy.ops.object.select_all(action='DESELECT')
Am.select_set(True)
for o in meshes:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=False, export_morph=False, export_skins=True, export_materials='NONE', export_yup=True)
print("WROTE", OUT)
