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
        "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
ENDS = {"hand_l": ["middle_01_l"], "hand_r": ["middle_01_r"], "ball_l": ["foot_end_l", "ball_leaf_l"],
        "ball_r": ["foot_end_r", "ball_leaf_r"]}
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
# the pelvis's parent node (the "root" bone, the -90 deg X turn from Z-up): a pose's pelvis is written relative to it
rp, rq = world(par[names["pelvis"]])
out["pelvis_parent"] = {"name": N[par[names["pelvis"]]].get("name"), "pos": [round(x, 6) for x in rp],
                        "rot": [round(x, 7) for x in rq]}
json.dump(out, open(DST, "w"), indent=1)
for k, d in out["joints"].items():
    print("%-11s %-11s pos %s" % (k, d["parent"], d["pos"]))
