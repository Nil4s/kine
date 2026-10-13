"""export_skeleton.py: one hero glb -> data/skeleton.json, the only thing the poser takes from the game.

    python tools/export_skeleton.py <hero.glb> data/skeleton.json

For each body joint: its parent, its REST position and rotation in CHARACTER SPACE (metres, after the hero's own
scale; glTF axes: +Y up, +Z forward = where the hero faces, +X = the hero's LEFT), and its local rest rotation (the
glTF node's own, so a pose can be written back into the game clip byte for byte). Fingers, twist and IK bones are left
out; each hand gets an "end" point (the middle finger's base) so it has a length.
"""
import sys, json, struct, math

SRC, DST = sys.argv[1], sys.argv[2]
raw = open(SRC, "rb").read()
jl = struct.unpack_from("<I", raw, 12)[0]
j = json.loads(raw[20:20 + jl])
N = j["nodes"]
par = {c: i for i, n in enumerate(N) for c in n.get("children", [])}
names = {n.get("name"): i for i, n in enumerate(N)}


def qmul(p, q):
    px, py, pz, pw = p; qx, qy, qz, qw = q
    return (pw * qx + px * qw + py * qz - pz * qy, pw * qy - px * qz + py * qw + pz * qx,
            pw * qz + px * qy - py * qx + pz * qw, pw * qw - px * qx - py * qy - pz * qz)


def qrot(q, v):
    r = qmul(qmul(q, (v[0], v[1], v[2], 0.0)), (-q[0], -q[1], -q[2], q[3])); return r[:3]


def world(i):
    """the node's world (position, rotation, uniform scale) from the scene root down"""
    chain = []
    while True:
        chain.append(i)
        if i not in par:
            break
        i = par[i]
    p, q, s = (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), 1.0
    for k in reversed(chain):
        n = N[k]
        t = n.get("translation", [0, 0, 0]); r = n.get("rotation", [0, 0, 0, 1]); sc = n.get("scale", [1, 1, 1])[0]
        tp = qrot(q, t)
        p = (p[0] + tp[0] * s, p[1] + tp[1] * s, p[2] + tp[2] * s)
        q = qmul(q, r); s *= sc
    return p, q


BODY = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
        "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
        "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"] +        [f"{f}_0{k}_{sd}" for sd in "lr" for f in ("thumb", "index", "middle", "ring", "pinky") for k in (1, 2, 3)]
ENDS = {"hand_l": ["middle_01_l"], "hand_r": ["middle_01_r"], "ball_l": ["foot_end_l", "ball_leaf_l"],
        "ball_r": ["foot_end_r", "ball_leaf_r"]}
for _sd in "lr":
    for _f in ("thumb", "index", "middle", "ring", "pinky"):
        ENDS[f"{_f}_03_{_sd}"] = [f"{_f}_04_leaf_{_sd}", f"{_f}_04_{_sd}"]
out = {"source": SRC.replace("\\", "/"), "axes": "+Y up, +Z forward (the hero faces +Z), +X = hero's LEFT; metres",
       "joints": {}}
for nm in BODY:
    i = names[nm]
    p, q = world(i)
    pn = N[par[i]].get("name")
    d = {"parent": pn if pn in BODY else None, "pos": [round(x, 5) for x in p], "rot": [round(x, 6) for x in q],
         "local_rot": N[i].get("rotation", [0, 0, 0, 1])}
    for en in ENDS.get(nm, []):
        if en in names:
            d["end"] = [round(x, 5) for x in world(names[en])[0]]
            break
    out["joints"]["head" if nm == "Head" else nm] = d
for d in out["joints"].values():
    if d["parent"] == "Head":
        d["parent"] = "head"
# each part's thickness, measured on the hero's own mesh: the vertices mostly bound to that bone, their distance to the
# bone's segment (joint -> end) at rest, the 80th percentile = the capsule radius (step 2: self-collision)
CHILD = {"pelvis": None, "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head",
         "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "clavicle_r": "upperarm_r",
         "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l",
         "thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r"}
for _sd in "lr":
    for _f in ("thumb", "index", "middle", "ring", "pinky"):
        CHILD[f"{_f}_01_{_sd}"] = f"{_f}_02_{_sd}"; CHILD[f"{_f}_02_{_sd}"] = f"{_f}_03_{_sd}"
JJ = out["joints"]
skin = j["skins"][0]
mesh_node = next(i for i, n in enumerate(N) if "mesh" in n and n.get("skin") is not None)
prim = j["meshes"][N[mesh_node]["mesh"]]["primitives"][0]
b0 = 20 + jl + 8


def acc(ix):
    ac = j["accessors"][ix]; bv = j["bufferViews"][ac["bufferView"]]
    n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[ac["type"]]
    fmt = {5126: "f", 5121: "B", 5123: "H"}[ac["componentType"]]
    sz = struct.calcsize(fmt) * n
    off = b0 + bv.get("byteOffset", 0) + ac.get("byteOffset", 0); st = bv.get("byteStride", sz)
    return [struct.unpack_from("<%d%s" % (n, fmt), raw, off + k * st) for k in range(ac["count"])]


pos = acc(prim["attributes"]["POSITION"]); jnt = acc(prim["attributes"]["JOINTS_0"]); wts = acc(prim["attributes"]["WEIGHTS_0"])
mp, mq = world(mesh_node)
jname = {k: N[ix].get("name") for k, ix in enumerate(skin["joints"])}
head_top = None
groups = {}
for v, jj, ww in zip(pos, jnt, wts):
    k = max(range(4), key=lambda q: ww[q])
    nm = jname[jj[k]]
    nm = "head" if nm == "Head" else nm
    w = qrot(mq, v); w = (w[0] + mp[0], w[1] + mp[1], w[2] + mp[2])
    groups.setdefault(nm, []).append(w)
    if nm == "head" and (head_top is None or w[1] > head_top):
        head_top = w[1]


def seg_d(p, a, b):
    ab = [b[i] - a[i] for i in range(3)]; ap = [p[i] - a[i] for i in range(3)]
    L = sum(x * x for x in ab)
    t = 0.0 if L < 1e-12 else max(0.0, min(1.0, sum(ab[i] * ap[i] for i in range(3)) / L))
    return math.dist(p, [a[i] + ab[i] * t for i in range(3)])


for nm, d in JJ.items():
    a = d["pos"]
    if nm == "pelvis":
        a, b = JJ["thigh_r"]["pos"], JJ["thigh_l"]["pos"]
    elif nm == "head":
        b = [a[0], head_top - 0.09, a[2]]; d["end"] = [round(x, 5) for x in b]
    elif CHILD.get(nm):
        b = JJ[CHILD[nm]]["pos"]
    else:
        b = d.get("end", a)
    g = groups.get(nm, [])
    if nm in ("pelvis", "spine_01", "spine_02", "spine_03"):
        # the trunk is wide, not deep: a capsule running left-right, fitted to a horizontal slice of the WHOLE mesh
        # between this joint's height and the next one's (the low-poly trunk has too few verts bound per bone),
        # arms left out (|x| < 0.17). Radius = half the depth (5th..95th percentile), width = the slice's.
        y0 = JJ["pelvis"]["pos"][1] - 0.08 if nm == "pelvis" else d["pos"][1]
        y1 = JJ["spine_01"]["pos"][1] if nm == "pelvis" else JJ[CHILD[nm]]["pos"][1]
        sl = [p for gg in groups.values() for p in gg if y0 <= p[1] <= y1 and abs(p[0]) < 0.17]
        zs = sorted(p[2] for p in sl); xs = sorted(abs(p[0]) for p in sl)
        zlo, zhi = zs[int(0.05 * (len(zs) - 1))], zs[int(0.95 * (len(zs) - 1))]
        r = (zhi - zlo) / 2
        cz = (zhi + zlo) / 2; cy = (y0 + y1) / 2
        w = max(0.0, xs[int(0.95 * (len(xs) - 1))] - r)
        a, b = [-w, cy, cz], [w, cy, cz]
        g = sl
    else:
        ds = sorted(seg_d(p, a, b) for p in g)
        r = ds[int(0.8 * (len(ds) - 1))] if ds else 0.04
    if any(nm.startswith(x) for x in ("thumb", "index", "middle", "ring", "pinky")):
        r = min(max(r, 0.008), 0.013)
    if nm.startswith("neck"):
        r = min(r, 0.06)   # the fit takes in the trapezius (24 cm "neck")
    if nm.startswith("clavicle"):
        r = min(r, 0.06)   # the fit takes in the deltoid and sticks out in front of the chest (10-12: stopped a folded arm 8 cm out)
    d["radius"] = round(r, 4)
    d["cap"] = [[round(x, 5) for x in a], [round(x, 5) for x in b]]
    d["verts"] = len(g)

# the pelvis's parent node (the "root" bone, the -90 deg X turn from Z-up): a pose's pelvis is written relative to it
rp, rq = world(par[names["pelvis"]])
out["pelvis_parent"] = {"name": N[par[names["pelvis"]]].get("name"), "pos": [round(x, 6) for x in rp],
                        "rot": [round(x, 7) for x in rq]}
json.dump(out, open(DST, "w"), indent=1)
for k, d in out["joints"].items():
    print("%-11s r %.3f cap %s (%d verts)" % (k, d.get("radius", 0), d.get("cap"), d.get("verts", 0)))
