"""FBX reader for tests/fbx_export_test.gd (ROADMAP 78). Run with:  python -I tests/py/fbx_check.py <file.fbx> <file.glb> <expected.json>

A reader of its own for FBX 7.4 ASCII (no code from the exporter): it tokenises the text, parses the node tree, and checks:
  1. the file parses; the global settings say Y up, and one unit is a centimetre (UnitScaleFactor 1.0);
  2. the LimbNode bones are the glb's skin joints: same count, same names, same order, same parent for every bone
     whose parent is a bone in the glb;
  3. every animation curve has one key per frame, and the frame count is the glb's own key count;
  4. for each sample (a bone at a frame): the R curves' Euler angles (FBX eEulerXYZ, degrees) recomposed as
     R = Rz(c) Ry(b) Rx(a) and compared with the body's local rotation written by the test. Bar: 0.01 degrees.
     The pelvis's T curves (centimetres) against the body's pelvis position: bar 0.1 mm.
Prints "ok ..." and "FAIL ..." lines; exits 1 on any FAIL.
"""
import json
import math
import struct
import sys

KTIME = 46186158000.0
ROT_BAR_DEG = 0.01
POS_BAR_M = 0.0001

fails = 0


def check(cond, what):
    global fails
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        fails += 1


# ---- FBX ASCII: tokens and a node tree ---------------------------------------------------------------------------------

def tokenize(src):
    toks = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
        elif c == ";":
            while i < n and src[i] != "\n":
                i += 1
        elif c == '"':
            j = src.index('"', i + 1)
            toks.append(("S", src[i + 1:j]))
            i = j + 1
        elif c in "{}:,*":
            toks.append(("P", c))
            i += 1
        else:
            j = i
            while j < n and src[j] not in " \t\r\n{}:,*\"":
                j += 1
            toks.append(("W", src[i:j]))
            i = j
    return toks


def parse_block(toks, i):
    """nodes until a '}' (or the end): each {'name', 'values', 'children'}; an array '*N { a: ... }' becomes a list value"""
    nodes = []
    while i < len(toks):
        if toks[i] == ("P", "}"):
            return nodes, i + 1
        if toks[i][0] != "W" or i + 1 >= len(toks) or toks[i + 1] != ("P", ":"):
            raise ValueError("expected a node name at token %d: %r" % (i, toks[i]))
        name = toks[i][1]
        i += 2
        values = []
        kinds = []
        children = []
        if toks[i] == ("P", "*"):
            i += 2   # the count
            if toks[i] != ("P", "{"):
                raise ValueError("array %s without a block" % name)
            blk, i = parse_block(toks, i + 1)
            arr = []
            for cn in blk:
                for v in cn["values"]:
                    arr.extend(v if isinstance(v, list) else [v])
            values.append(arr)
        else:
            while True:
                k, v = toks[i]
                is_node_name = k == "W" and i + 1 < len(toks) and toks[i + 1] == ("P", ":")
                if k == "P" or is_node_name:
                    break
                values.append(v)
                kinds.append(k)
                i += 1
                if toks[i] == ("P", ","):
                    i += 1
                    continue
                break
            if i < len(toks) and toks[i] == ("P", "{"):
                children, i = parse_block(toks, i + 1)
        nodes.append({"name": name, "values": values, "kinds": kinds, "children": children})
    return nodes, i


def find(nodes, name):
    return [n for n in nodes if n["name"] == name]


def props(node):
    """Properties70 of a node: {property name: [values after the name and type strings]}"""
    out = {}
    for p in find(node["children"], "Properties70"):
        for q in p["children"]:
            v = q["values"]
            if len(v) >= 4:
                out[v[0]] = v[4:] if len(v) > 4 else v[3:]
            else:
                out[v[0]] = v[1:]
    return out


def num(x):
    return float(x)


def conn_list(top):
    return [c["values"] for c in find(top, "Connections")[0]["children"]]


# ---- glb: the JSON chunk --------------------------------------------------------------------------------------------------

def read_glb(path):
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not a glb")
    clen, ctype = struct.unpack_from("<I4s", data, 12)
    if ctype != b"JSON":
        raise ValueError("first chunk is not JSON")
    return json.loads(data[20:20 + clen].decode("utf-8"))


def quat_from_euler(a, b, c):
    """q = qz(c) * qy(b) * qx(a) in (x, y, z, w): the matrix Rz(c) Ry(b) Rx(a) (FBX eEulerXYZ), angles in radians"""
    def qx(t):
        return (math.sin(t / 2), 0.0, 0.0, math.cos(t / 2))

    def qy(t):
        return (0.0, math.sin(t / 2), 0.0, math.cos(t / 2))

    def qz(t):
        return (0.0, 0.0, math.sin(t / 2), math.cos(t / 2))

    def mul(p, q):
        x1, y1, z1, w1 = p
        x2, y2, z2, w2 = q
        return (w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
                w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2)
    return mul(mul(qz(c), qy(b)), qx(a))


def angle_deg(p, q):
    np_ = math.sqrt(sum(x * x for x in p))
    nq = math.sqrt(sum(x * x for x in q))
    d = abs(sum(a * b for a, b in zip(p, q)) / (np_ * nq))
    return math.degrees(2.0 * math.acos(min(1.0, d)))


def main():
    fbx_path, glb_path, exp_path = sys.argv[1], sys.argv[2], sys.argv[3]
    exp = json.load(open(exp_path, encoding="utf-8"))
    fps = float(exp["fps"])
    frames = int(exp["frames"])
    text = open(fbx_path, encoding="utf-8").read()
    toks = tokenize(text)
    top, _ = parse_block(toks, 0)
    names_top = [n["name"] for n in top]
    for want in ["FBXHeaderExtension", "GlobalSettings", "Documents", "Definitions", "Objects", "Connections"]:
        check(want in names_top, "the file has a %s section" % want)
    check(find(top, "FBXHeaderExtension") and find(find(top, "FBXHeaderExtension")[0]["children"], "FBXVersion")[0]["values"] == ["7400"],
          "the FBX version is 7.4 (7400)")

    gs = props(find(top, "GlobalSettings")[0])
    check(gs.get("UpAxis", ["?"])[0] == "1" and gs.get("UpAxisSign", ["?"])[0] == "1", "up axis is +Y (UpAxis 1, sign 1)")
    check(num(gs["UnitScaleFactor"][0]) == 1.0, "one unit is a centimetre (UnitScaleFactor 1.0; FBX's 100 would be a metre)")

    objs = find(top, "Objects")[0]["children"]
    models = {}
    for m in find(objs, "Model"):
        mid = int(m["values"][0])
        nm = m["values"][1].split("::", 1)[1]
        models[mid] = {"name": nm, "kind": m["values"][2], "node": m}
    limbs = {mid: v for mid, v in models.items() if v["kind"] == "LimbNode"}
    bone_names = [models[int(m["values"][0])]["name"] for m in find(objs, "Model") if m["values"][2] == "LimbNode"]

    # ---- the glb's skeleton ----------------------------------------------------------------------------------------------
    g = read_glb(glb_path)
    gnodes = g["nodes"]
    joints = g["skins"][0]["joints"]
    glb_bones = [gnodes[j]["name"] for j in joints]
    check(len(bone_names) == len(glb_bones), "bone count: %d bones in the FBX, %d joints in the glb" % (len(bone_names), len(glb_bones)))
    check(bone_names == glb_bones, "bone names and order match the glb's skin joints (%d names)" % len(glb_bones))
    check(len(set(bone_names)) == len(bone_names), "every bone name is unique in the FBX")
    check("head" in bone_names and "Head" not in bone_names, "the head bone is named \"head\" (UE5), as in the glb")

    gpar = {}
    for i, nd in enumerate(gnodes):
        for c in nd.get("children", []):
            gpar[gnodes[c]["name"]] = nd["name"]
    conns = conn_list(top)
    fpar = {}
    for c in conns:
        if len(c) >= 3 and c[0] == "OO":
            ch, pa = int(c[1]), int(c[2])
            if ch in limbs and pa in limbs:
                fpar[limbs[ch]["name"]] = models[pa]["name"]
    bad_par = []
    checked_par = 0
    for nm in glb_bones:
        gp = gpar.get(nm)
        if gp in glb_bones:
            checked_par += 1
            if fpar.get(nm) != gp:
                bad_par.append("%s: glb parent %s, fbx parent %s" % (nm, gp, fpar.get(nm)))
    check(not bad_par and checked_par > 0, "the bone hierarchy matches the glb for %d bones with a bone parent %s" % (checked_par, bad_par[:3]))

    # ---- the animation: curve nodes, curves, keys --------------------------------------------------------------------------
    cnodes = {}   # curve node id -> {"name": "R"/"T", "model": id, "prop": "Lcl Rotation"/..., "curves": {"X": id}}
    for o in objs:
        if o["name"] == "AnimationCurveNode":
            cnodes[int(o["values"][0])] = {"name": o["values"][1].split("::", 1)[1], "model": None, "prop": None, "curves": {}}
    curves = {}   # curve id -> (curve node id, axis, the curve's node)
    for o in objs:
        if o["name"] == "AnimationCurve":
            curves[int(o["values"][0])] = o
    for c in conns:
        if len(c) >= 4 and c[0] == "OP":
            a, b, prop = int(c[1]), int(c[2]), c[3]
            if a in cnodes and b in models:
                cnodes[a]["model"] = b
                cnodes[a]["prop"] = prop
            elif a in curves and b in cnodes:
                cnodes[b]["curves"][prop.replace("d|", "")] = a
    nkeys_bad = []
    ncurves = 0
    for cid, o in curves.items():
        ncurves += 1
        kt = find(o["children"], "KeyTime")[0]["values"][0]
        kv = find(o["children"], "KeyValueFloat")[0]["values"][0]
        if len(kt) != frames or len(kv) != frames:
            nkeys_bad.append("curve %d: %d keys (times) %d (values)" % (cid, len(kt), len(kv)))
    check(ncurves > 0 and not nkeys_bad, "%d animation curves, each with %d keys (one per frame) %s" % (ncurves, frames, nkeys_bad[:3]))
    gframes = set()
    for an in g.get("animations", []):
        for s in an["samplers"]:
            gframes.add(g["accessors"][s["input"]]["count"])
    check(gframes == {frames}, "the glb's own key count per sampler is the same %d frames (%s)" % (frames, sorted(gframes)))

    worst_r = 0.0
    worst_p = 0.0
    lines = []
    bym = {}
    for cid, cn in cnodes.items():
        if cn["model"] is not None:
            bym.setdefault(models[cn["model"]]["name"], {})[cn["name"]] = cn
    for s in exp["samples"]:
        bone, k = s["bone"], int(s["frame"])
        t = float(s["t"])
        want_tick = round(t * KTIME)
        cn = bym.get(bone, {}).get("R")
        if cn is None or len(cn["curves"]) != 3:
            lines.append("no R curves for %s" % bone)
            worst_r = 1e9
            continue
        ang = []
        for ax in ["X", "Y", "Z"]:
            cv = curves[cn["curves"][ax]]
            kt = [int(x) for x in find(cv["children"], "KeyTime")[0]["values"][0]]
            kv = [float(x) for x in find(cv["children"], "KeyValueFloat")[0]["values"][0]]
            if abs(kt[k] - want_tick) > 1:
                lines.append("%s key %d at tick %d, want %d" % (bone, k, kt[k], want_tick))
                worst_r = 1e9
            ang.append(kv[k])
        q_fbx = quat_from_euler(math.radians(ang[0]), math.radians(ang[1]), math.radians(ang[2]))
        q_want = tuple(s["q"])
        d = angle_deg(q_fbx, q_want)
        worst_r = max(worst_r, d)
        if s.get("p") is not None:
            pn = bym.get(bone, {}).get("T")
            if pn is None:
                lines.append("no T curves for %s" % bone)
                worst_p = 1e9
            else:
                pvals = []
                for ax in ["X", "Y", "Z"]:
                    cv = curves[pn["curves"][ax]]
                    kv = [float(x) for x in find(cv["children"], "KeyValueFloat")[0]["values"][0]]
                    pvals.append(kv[k] / 100.0)
                dp = max(abs(a - b) for a, b in zip(pvals, s["p"]))
                worst_p = max(worst_p, dp)
    check(not lines and worst_r < ROT_BAR_DEG,
          "rotation: %d samples (%s) read back from the FBX curves match the body's local rotation, worst %.6f deg (bar %.2f) %s"
          % (len(exp["samples"]), ", ".join("%s@%d" % (s["bone"], s["frame"]) for s in exp["samples"]), worst_r, ROT_BAR_DEG, lines[:3]))
    has_p = any(s.get("p") is not None for s in exp["samples"])
    if has_p:
        check(worst_p < POS_BAR_M, "pelvis position (cm curves / 100) matches the body's pelvis, worst %.7f m (bar %.4f m)" % (worst_p, POS_BAR_M))

    print("FBX CHECK: %d failed" % fails)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
