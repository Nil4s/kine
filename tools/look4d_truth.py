#!/usr/bin/env python3
"""LOOK4D truth generator, packet builder and grader (docs/LOOK4D_DESIGN.md).

  python tools/look4d_truth.py gen        questions.json + truth.json from out/look4d/<scene>/truth_data.json (scene truth only, no rendered format)
  python tools/look4d_truth.py packets    the 7 arms x 3 reps reader packets under out/look4d/packets/, keys under out/look4d/key/
  python tools/look4d_truth.py grade <reader> <answers.json>     e.g. grade C_r1 answers.json
  python tools/look4d_truth.py selfcheck  the oracle answers score 100%, shifted answers score near chance, the projection matches the sampled pixels

Answers are option letters; yes/no questions have A = yes, B = no. No model grades.
"""
import hashlib
import json
import math
import os
import random
import shutil
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "look4d")
SCENES = ["s1_engine", "s2_arm", "s3_walk", "s4_fall", "s5_camera", "s6_null"]
ARMS = ["A", "B", "C", "D", "CD", "Z", "Dscr"]
REPS = 3
W, H = 768, 432
HORIZON_K = 15  # samples are 1/30 s apart: +0.5 s
LOOKUP = {"fastest", "toward", "hidden", "ordering", "touch"}
CELLS = ["top-left", "top-middle", "top-right", "middle-left", "centre", "middle-right", "bottom-left", "bottom-middle", "bottom-right"]
MIN_NONLOOKUP = 0.40


def rng_for(*parts):
    h = hashlib.sha256("|".join(str(p) for p in parts).encode()).hexdigest()
    return random.Random(int(h[:16], 16))


def load(scene):
    with open(os.path.join(ROOT, scene, "truth_data.json")) as f:
        return json.load(f)


# ---------------------------------------------------------------- geometry
def sample(td, k):
    for s in td["samples"]:
        if s["k"] == k:
            return s
    raise KeyError(k)


def project(cam, p):
    f = cam["look_dir"]
    n = math.sqrt(sum(x * x for x in f))
    f = [x / n for x in f]
    d = f[1]  # dot of world up (0,1,0) with f
    u = [-d * f[0], 1.0 - d * f[1], -d * f[2]]
    m = math.sqrt(sum(x * x for x in u))
    u = [x / m for x in u]
    r = [f[1] * u[2] - f[2] * u[1], f[2] * u[0] - f[0] * u[2], f[0] * u[1] - f[1] * u[0]]
    rel = [p[i] - cam["pos"][i] for i in range(3)]
    z = sum(rel[i] * f[i] for i in range(3))
    x = sum(rel[i] * r[i] for i in range(3))
    y = sum(rel[i] * u[i] for i in range(3))
    if z <= 1e-6:
        return None
    foc = (H / 2.0) / math.tan(math.radians(cam["fov"]) / 2.0)
    return (W / 2.0 + foc * x / z, H / 2.0 - foc * y / z, z)


def cell_of(px, py):
    cx = min(2, max(0, int(px // (W / 3.0))))
    cy = min(2, max(0, int(py // (H / 3.0))))
    return cy * 3 + cx


def cell_margin(px, py):
    """pixels from the nearest cell edge (inner edges only)"""
    best = 1e9
    for e in (W / 3.0, 2 * W / 3.0):
        best = min(best, abs(px - e))
    for e in (H / 3.0, 2 * H / 3.0):
        best = min(best, abs(py - e))
    return best


def _pt_box(p, lo, hi):
    d = [max(lo[i] - p[i], 0.0, p[i] - hi[i]) for i in range(3)]
    return math.sqrt(sum(x * x for x in d))


def _box_box(a, b):
    d = [max(a["min"][i] - b["max"][i], 0.0, b["min"][i] - a["max"][i]) for i in range(3)]
    return math.sqrt(sum(x * x for x in d))


def _seg_pts(s, n=21):
    a, b = s["a"], s["b"]
    return [[a[i] + (b[i] - a[i]) * j / (n - 1) for i in range(3)] for j in range(n)]


def gap(sa, sb):
    """analytic / sampled surface gap in metres between two scene shapes (negative = penetrating)"""
    ka, kb = sa["k"], sb["k"]
    if ka == "sphere" and kb == "sphere":
        return math.dist(sa["c"], sb["c"]) - sa["r"] - sb["r"]
    if ka == "sphere" and kb == "aabb":
        return _pt_box(sa["c"], sb["min"], sb["max"]) - sa["r"]
    if ka == "aabb" and kb == "sphere":
        return gap(sb, sa)
    if ka == "capsule" and kb == "aabb":
        return min(_pt_box(p, sb["min"], sb["max"]) for p in _seg_pts(sa)) - sa["r"]
    if ka == "aabb" and kb == "capsule":
        return gap(sb, sa)
    if ka == "capsule" and kb == "sphere":
        return min(math.dist(p, sb["c"]) for p in _seg_pts(sa)) - sa["r"] - sb["r"]
    if ka == "sphere" and kb == "capsule":
        return gap(sb, sa)
    if ka == "capsule" and kb == "capsule":
        return min(math.dist(p, q) for p in _seg_pts(sa, 11) for q in _seg_pts(sb, 11)) - sa["r"] - sb["r"]
    if ka == "aabb" and kb == "aabb":
        return _box_box(sa, sb)
    return 1e9


def gap_at(td, k, a, b):
    o = sample(td, k)["objs"]
    return gap(o[a]["shape"], o[b]["shape"])


def px_at(td, k, i):
    return sample(td, k)["objs"][i]["px"]


def z_rate(td, i):
    za = sample(td, -1)["objs"][i]["z"]
    zb = sample(td, 1)["objs"][i]["z"]
    return (zb - za) / (2.0 / 30.0)


def in_view(td, i):
    return td["meas"][i]["solo_px"] > 0


# ---------------------------------------------------------------- questions
def letters(opts):
    return {chr(65 + j): o for j, o in enumerate(opts)}


def mk(qs, scene, qtype, text, options, answer, extra=None):
    q = {"id": "q%02d" % (len(qs) + 1), "scene": scene, "type": qtype, "lookup": qtype in LOOKUP, "text": text, "options": options, "answer": answer}
    if extra:
        q["truth"] = extra
    qs.append(q)


def yesno(rng, truth_yes):
    return {"A": "yes", "B": "no"}, ("A" if truth_yes else "B")


def mc(rng, correct, wrong):
    opts = [correct] + list(wrong)
    rng.shuffle(opts)
    return letters(opts), chr(65 + opts.index(correct))


def pair_name(a, b):
    return "%s and %s" % (a, b)


def gen_scene(scene, td, spec=None):
    """spec: choices made on the motion scene S1 and replayed on its frozen twin S6 (so the two question sets match)."""
    rng = rng_for("look4d-v1", scene)
    qs = []
    ids = td["ids"]
    null = td["kind"] == "null"
    static = td["kind"] == "static"
    motion = not static
    sp = {i: td["kin"][i]["speed"] for i in ids}
    cam = td["camera"]
    pick = {}
    if spec is None:
        spec = {}

    def chosen(key, default_fn):
        if null and key in spec:
            return spec[key]
        v = default_fn()
        pick[key] = v
        return v

    # fastest
    if motion:
        def fastest():
            order = sorted(ids, key=lambda i: -sp[i])
            if len(order) > 1 and sp[order[0]] >= 1.12 * sp[order[1]]:
                top = order[0]
                rest = [i for i in order[1:] if in_view(td, i)]
                others = rng.sample(rest[: max(3, len(rest))], 3)
                return [top] + others
            return None
        f = chosen("fastest", fastest)
        if f:
            top = f[0]
            opts = list(f)
            rng.shuffle(opts)
            options = letters(opts)
            if null:
                options["E"] = "none of them is moving"
                ans = "E"
            else:
                ans = chr(65 + opts.index(top))
            mk(qs, scene, "fastest", "Which of these parts is moving fastest?", options, ans, {"top": top, "speed": sp[top]})
    # toward
    if motion:
        def toward():
            yes = []
            no = []
            for i in ids:
                if sp[i] < 0.05 or not in_view(td, i):
                    continue
                r = z_rate(td, i)
                if r < -0.3 * sp[i]:
                    yes.append(i)
                elif r > -0.1 * sp[i]:
                    no.append(i)
            rng.shuffle(yes)
            rng.shuffle(no)
            return yes[:2] + no[:2]
        for i in chosen("toward", toward):
            if null:
                options, ans = yesno(rng, False)
                r = 0.0
            else:
                r = z_rate(td, i)
                options, ans = yesno(rng, r < -0.3 * sp[i])
            mk(qs, scene, "toward", "Is the %s moving toward the camera (its distance from the camera shrinking)?" % i, options, ans, {"part": i, "depth_rate": r, "speed": sp[i]})
    # hidden (vis < 0.25 with a silhouette in the picture)
    def hidden():
        yes = [i for i in ids if in_view(td, i) and td["meas"][i]["frac"] < 0.25]
        no = [i for i in ids if in_view(td, i) and td["meas"][i]["frac"] >= 0.6 and td["meas"][i]["solo_px"] > 800]
        rng.shuffle(yes)
        rng.shuffle(no)
        return yes[:1] + no[:1]
    for i in chosen("hidden", hidden):
        fr = td["meas"][i]["frac"]
        options, ans = yesno(rng, fr < 0.25)
        mk(qs, scene, "hidden", "Is the %s mostly hidden behind other parts (less than a quarter of it visible)?" % i, options, ans, {"part": i, "vis": fr})
    # ordering
    def ordering():
        cand = [i for i in ids if in_view(td, i) and td["meas"][i]["solo_px"] > 500]
        pairs = []
        for a in range(len(cand)):
            for b in range(a + 1, len(cand)):
                za, zb = sample(td, 0)["objs"][cand[a]]["z"], sample(td, 0)["objs"][cand[b]]["z"]
                if abs(za - zb) >= 0.15 * min(za, zb):
                    pairs.append([cand[a], cand[b]])
        rng.shuffle(pairs)
        return pairs[:2]
    for a, b in chosen("ordering", ordering):
        za, zb = sample(td, 0)["objs"][a]["z"], sample(td, 0)["objs"][b]["z"]
        opts = [a, b]
        rng.shuffle(opts)
        near = a if za < zb else b
        mk(qs, scene, "ordering", "Which is nearer to the camera, the %s or the %s (distance along the viewing direction, centres)?" % (opts[0], opts[1]), letters(opts), chr(65 + opts.index(near)), {"near": near, "z": {a: za, b: zb}})
    # touch (not on S2: box contacts only)
    if scene != "s2_arm":
        def touch():
            tr = [c for c in td["contacts"] if (c["gap_mm"] <= 0.1 or c["pen_mm3"] > 1.0) and c["a"] in ids and c["b"] in ids]
            if not tr:
                return None
            t = rng.choice(tr)
            touching = {(c["a"], c["b"]) for c in td["contacts"] if c["gap_mm"] <= 0.1 or c["pen_mm3"] > 1.0}
            fl = []
            for a in range(len(ids)):
                for b in range(a + 1, len(ids)):
                    x, y = ids[a], ids[b]
                    if (x, y) in touching or (y, x) in touching:
                        continue
                    g = gap_at(td, 0, x, y)
                    if g >= 0.010:
                        fl.append((g, [x, y]))
            fl.sort(key=lambda e: e[0])
            near = [p for _, p in fl[:12]]
            rng.shuffle(near)
            if len(near) < 3:
                return None
            return [[t["a"], t["b"]]] + near[:3]
        f = chosen("touch", touch)
        if f:
            t = f[0]
            opts = [pair_name(*p) for p in f]
            correct = pair_name(*t)
            rng.shuffle(opts)
            mk(qs, scene, "touch", "Which pair of parts is touching or overlapping (gap under 0.1 mm) right now?", letters(opts), chr(65 + opts.index(correct)), {"pair": t})
    # collide within 0.5 s (non-lookup)
    if motion:
        def collide():
            yes = []
            no = []
            for a in range(len(ids)):
                for b in range(a + 1, len(ids)):
                    x, y = ids[a], ids[b]
                    if sp[x] < 0.05 and sp[y] < 0.05:
                        continue
                    g0 = gap_at(td, 0, x, y)
                    if g0 < 0.030:
                        continue
                    gm = min(gap_at(td, k, x, y) for k in range(0, HORIZON_K + 1))
                    if gm <= 0.0:
                        yes.append([x, y])
                    elif gm >= 0.030:
                        no.append([x, y])
            rng.shuffle(yes)
            rng.shuffle(no)
            return yes[:2] + no[:2]
        if null:
            plist = spec.get("collide", [])
        else:
            plist = collide()
            pick["collide"] = plist
        for x, y in plist:
            if null:
                truth_yes = False
            else:
                truth_yes = min(gap_at(td, k, x, y) for k in range(0, HORIZON_K + 1)) <= 0.0
            options, ans = yesno(rng, truth_yes)
            mk(qs, scene, "collide", "If every part keeps its present velocity, will the %s and the %s touch within the next 0.5 s?" % (x, y), options, ans, {"pair": [x, y], "gap_now_mm": 1000 * gap_at(td, 0, x, y)})
    # screen left/right and above/below (non-lookup)
    def screen():
        cand = [i for i in ids if in_view(td, i) and td["meas"][i]["solo_px"] > 400 and px_at(td, 0, i)[0] is not None]
        lr, ud = [], []
        for a in range(len(cand)):
            for b in range(a + 1, len(cand)):
                pa, pb = px_at(td, 0, cand[a]), px_at(td, 0, cand[b])
                if abs(pa[0] - pb[0]) >= 40:
                    lr.append([cand[a], cand[b]])
                if abs(pa[1] - pb[1]) >= 30:
                    ud.append([cand[a], cand[b]])
        rng.shuffle(lr)
        rng.shuffle(ud)
        return {"lr": lr[:2], "ud": ud[:2]}
    sc = chosen("screen", screen)
    for a, b in sc["lr"]:
        pa, pb = px_at(td, 0, a), px_at(td, 0, b)
        options, ans = yesno(rng, pa[0] < pb[0])
        mk(qs, scene, "screen_lr", "In the picture, is the centre of the %s to the left of the centre of the %s?" % (a, b), options, ans, {"px": {a: pa, b: pb}})
    for a, b in sc["ud"]:
        pa, pb = px_at(td, 0, a), px_at(td, 0, b)
        options, ans = yesno(rng, pa[1] < pb[1])
        mk(qs, scene, "screen_ud", "In the picture, is the centre of the %s above the centre of the %s?" % (a, b), options, ans, {"px": {a: pa, b: pb}})
    # out of view (non-lookup)
    gone = [i for i in ids if not in_view(td, i)]
    if gone:
        inn = [i for i in ids if in_view(td, i) and td["meas"][i]["solo_px"] > 400]
        g = gone[0]
        opts, ans = mc(rng, g, rng.sample(inn, 3))
        mk(qs, scene, "out_of_view", "Which of these parts is completely outside the picture (no part of it is drawn)?", opts, ans, {"part": g})
    # predict the 3x3 cell at +0.5 s (non-lookup)
    if motion or null:
        def predict():
            out = []
            cand = [i for i in ids if in_view(td, i) and (null or sp[i] >= 0.05)]
            rng.shuffle(cand)
            for i in cand:
                p0 = px_at(td, 0, i)
                p1 = px_at(td, HORIZON_K, i)
                if p0[0] is None or p1[0] is None:
                    continue
                if cell_margin(*p1) < 25:
                    continue
                o0 = sample(td, 0)["objs"][i]
                o1 = sample(td, HORIZON_K)["objs"][i]
                # the constant-velocity extrapolation of the world centre must land in the same cell as the true position
                vel = [(sample(td, 1)["objs"][i]["c"][j] - sample(td, -1)["objs"][i]["c"][j]) * 15.0 for j in range(3)]
                c = [o0["c"][j] + vel[j] * 0.5 for j in range(3)]
                pr = project(cam, c)
                if pr is None or cell_of(pr[0], pr[1]) != cell_of(*p1):
                    continue
                out.append(i)
                if len(out) == 3:
                    break
            return out
        for i in chosen("predict", predict):
            p1 = px_at(td, HORIZON_K, i)
            p0 = px_at(td, 0, i)
            truth_cell = cell_of(*p1)
            now = cell_of(*p0)
            others = [c for c in range(9) if c != truth_cell]
            if now != truth_cell:
                wrong = [now] + rng.sample([c for c in others if c != now], 2)
            else:
                wrong = rng.sample(others, 3)
            opts, ans = mc(rng, CELLS[truth_cell], [CELLS[c] for c in wrong])
            mk(qs, scene, "predict", "If the %s keeps its present velocity, in which cell of the 3 x 3 grid over the picture will its centre be 0.5 s from now?" % i, opts, ans, {"cell": CELLS[truth_cell], "now": CELLS[now]})
    return qs, pick


def cmd_gen():
    allq = {}
    truth = {}
    spec = None
    for sc in SCENES:
        td = load(sc)
        if sc == "s6_null":
            qs, _ = gen_scene(sc, td, spec)
        else:
            qs, pick = gen_scene(sc, td)
            if sc == "s1_engine":
                spec = pick
        allq[sc] = [{k: v for k, v in q.items() if k not in ("answer", "truth")} for q in qs]
        truth[sc] = {q["id"]: {"answer": q["answer"], "type": q["type"], "lookup": q["lookup"], "truth": q.get("truth")} for q in qs}
    rows = [t for sc in truth for t in truth[sc].values()]
    nl = sum(1 for r in rows if not r["lookup"])
    share = nl / float(len(rows))
    stats = {"total": len(rows), "by_type": {}, "non_lookup": nl, "non_lookup_share": share, "by_scene": {sc: len(truth[sc]) for sc in SCENES}}
    for r in rows:
        stats["by_type"][r["type"]] = stats["by_type"].get(r["type"], 0) + 1
    motion = [t for sc in ("s1_engine", "s2_arm", "s3_walk", "s4_fall") for t in truth[sc].values() if t["type"] in ("fastest", "toward", "collide", "predict")]
    stats["motion_questions_s1_s4"] = len(motion)
    if share < MIN_NONLOOKUP:
        raise SystemExit("REFUSED: non-lookup share %.2f is under %.2f" % (share, MIN_NONLOOKUP))
    with open(os.path.join(ROOT, "questions.json"), "w") as f:
        json.dump(allq, f, indent=1)
    with open(os.path.join(ROOT, "truth.json"), "w") as f:
        json.dump(truth, f, indent=1)
    with open(os.path.join(ROOT, "question_stats.json"), "w") as f:
        json.dump(stats, f, indent=1)
    print(json.dumps(stats, indent=1))


# ---------------------------------------------------------------- packets
ARM_NAME = {"A": "A", "B": "B", "C": "C", "D": "D", "CD": "C+D", "Z": "Z", "Dscr": "D-scr"}

COMMON = """You will answer multiple-choice questions about {n} short scenes from a 3D simulation (mechanical parts, an arm, a walking figure, falling objects). Each scene is a single moment, called "now". Parts are listed by name at the start of each scene.

Rules: answer from what is given below only. Do not read other files, do not search, do not run tools except to open the image files named in this packet. Each question has lettered options; yes/no questions have A = yes and B = no. If you cannot tell, give your best guess (always answer every question).

Conventions for every question: "the picture" is the 768 x 432 pixel camera image of the scene (x to the right, y down). Left/right/above/below, and the 3 x 3 grid (three equal columns, three equal rows over the whole picture), refer to the picture. "Centre" means the part's 3D centre projected into the picture. Distances and speeds are in metres and seconds in the scene's own world units; the camera looks at the scene from a fixed viewpoint.

Output: when done, write one JSON object and nothing else after it, mapping "<scene label>.<question id>" to one letter, for example {{"scene1.q01": "B", "scene1.q02": "A"}}.
"""

ARM_TEXT = {
    "A": "For each scene you get ONE image: the picture at \"now\".",
    "B": "For each scene you get ONE image made of four small pictures of the same scene, tiled 2 x 2 in time order: top-left is oldest, top-right next, bottom-left next, bottom-right is \"now\". Consecutive tiles are {h} seconds apart (scene-specific, stated per scene). The camera does not move between tiles. The questions refer to the picture at \"now\" (the bottom-right tile, 384 x 216 px here; treat it as the full 768 x 432 picture).",
    "C": "For each scene you get ONE annotated image (768 x 432). The scene picture is the top-left part of it (552 x 311 px, same view as an unannotated picture, scaled); the strip at the right is a list; the text below the picture explains the marks. In the picture: each listed part has a small numbered box; the list at the right gives number, name, view depth in metres, and speed in m/s (with \"toward\" or \"away\" when the part moves along the viewing direction; \"static\" = not moving). A yellow arrow starts at a moving part's centre and ends where the part would be after the stated time at its present velocity. White dots mark the part's three earlier positions. A dashed cyan box marks a part that is mostly hidden behind others. A numbered box can sit next to its part instead of on it. Questions about the grid or left/right/above/below refer to the scene picture region (the top-left 552 x 311 px).",
    "D": "For each scene you get a text data block (JSON) and NO image. It lists, for each named part, world position (x right, y up, z toward the viewer in world axes), velocity, speed, angular velocity, nominal mass, momentum, view depth, visible share, and the part hiding it. Rows with a \"moving\" header have motion columns; \"static\" rows are at rest (velocity 0). \"touching_or_overlapping\" lists part pairs that touch or interpenetrate (gap in mm, overlap in mm^3). The camera position, viewing direction, up vector and vertical field of view (degrees) are given; the image is 768 x 432, pinhole projection with the principal point at the picture centre. Anything about the picture (left/right, above/below, grid cells, out of view) must be worked out from the world data and the camera.",
    "CD": "For each scene you get BOTH an annotated image and a text data block (JSON). Image: ONE annotated picture (768 x 432). The scene picture is the top-left part (552 x 311 px, same view scaled); the strip at the right lists number, name, view depth (m) and speed (m/s, \"toward\"/\"away\", or \"static\") per numbered part; yellow arrow = where a moving part would be after the stated time at its present velocity; white dots = its three earlier positions; dashed cyan box = part mostly hidden; a numbered box can sit next to its part. Grid and left/right/above/below questions refer to the scene picture region (top-left 552 x 311 px). Data: JSON with, for each named part, world position (x right, y up, z toward the viewer), velocity, speed, angular velocity, nominal mass, momentum, view depth, visible share and the part hiding it; \"moving\" rows have motion columns, \"static\" rows are at rest (velocity 0); \"touching_or_overlapping\" lists pairs that touch or overlap; the camera pose and field of view are given (pinhole, picture 768 x 432, principal point at the centre).",
    "Z": "You get NO image and NO data, only the part names and the questions. Answer each question as best you can.",
}
ARM_TEXT["Dscr"] = ARM_TEXT["D"]


def scramble(d, rng):
    """D with each part's value block moved to a different part's id: one relabeling applied to every id string in the digest (rows, occluded_by, contacts)."""
    names = [r[0] for r in d["moving"]] + [r[0] for r in d["static"]]
    perm = names[:]
    while True:
        rng.shuffle(perm)
        if all(perm[i] != names[i] for i in range(len(names))) or len(names) < 2:
            break
    m = dict(zip(names, perm))
    out = json.loads(json.dumps(d))
    for r in out["moving"]:
        r[0] = m[r[0]]
        r[9] = m.get(r[9], r[9])
    for r in out["static"]:
        r[0] = m[r[0]]
        r[5] = m.get(r[5], r[5])
    for c in out["touching_or_overlapping"]:
        c[0], c[1] = m[c[0]], m[c[1]]
    return out


def token_est(txt):
    return int(math.ceil(len(txt.encode("utf-8")) / 4.0))


def cmd_packets():
    qs = json.load(open(os.path.join(ROOT, "questions.json")))
    pdir = os.path.join(ROOT, "packets")
    kdir = os.path.join(ROOT, "key")
    for d in (pdir, kdir):
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
    summary = {"image_tokens_each": int(round(W * H / 750.0)), "d_tokens_by_scene": {}, "packets": {}}
    dtext = {}
    for sc in SCENES:
        dtext[sc] = open(os.path.join(ROOT, sc, "D.json")).read()
        summary["d_tokens_by_scene"][sc] = token_est(dtext[sc])
    toks = sorted(summary["d_tokens_by_scene"].values())
    summary["d_tokens_median_scene"] = (toks[2] + toks[3]) / 2.0
    for arm in ARMS:
        for rep in range(1, REPS + 1):
            rid = "%s_r%d" % (arm, rep)
            rng = rng_for("packet-order", arm, rep)
            order = SCENES[:]
            rng.shuffle(order)
            pk = os.path.join(pdir, rid)
            os.makedirs(os.path.join(pk, "images"))
            lines = ["# Reading task\n", COMMON.format(n=len(SCENES)), "\n## How the scenes are shown\n", ARM_TEXT[arm].replace("{h}", "the stated number of")]
            key = {"reader": rid, "arm": arm, "rep": rep, "scenes": {}}
            img_tokens = 0
            text_tokens = 0
            for pos, sc in enumerate(order, 1):
                label = "scene%d" % pos
                td = load(sc)
                key["scenes"][label] = sc
                lines.append("\n\n## %s\n" % label)
                names = td["ids"]
                lines.append("Parts: " + ", ".join(names) + ".\n")
                if arm in ("A", "B", "C", "CD"):
                    src = {"A": "A", "B": "B", "C": "C", "CD": "C"}[arm]
                    fname = "img_%s.png" % hashlib.sha256((rid + sc).encode()).hexdigest()[:10]
                    shutil.copy(os.path.join(ROOT, sc, src + ".png"), os.path.join(pk, "images", fname))
                    lines.append("Image for %s: images/%s (open it and look at it).\n" % (label, fname))
                    img_tokens += int(round(W * H / 750.0))
                if arm == "B":
                    lines.append("The four tiles of this image are %s seconds apart.\n" % ("%g" % td["h"]))
                if arm == "C" or arm == "CD":
                    lines.append("The yellow arrow in this scene shows %s s of motion at the present velocity; the white dots are %s s apart.\n" % ("%g" % td["arrow_t"], "%g" % td["h"]))
                if arm in ("D", "CD", "Dscr"):
                    d = json.loads(dtext[sc])
                    d.pop("scene", None)
                    if arm == "Dscr":
                        d = scramble(d, rng_for("scramble", rep, sc))
                    txt = json.dumps(d, separators=(",", ":"))
                    text_tokens += token_est(txt)
                    lines.append("Data for %s:\n```json\n%s\n```\n" % (label, txt))
                lines.append("\nQuestions for %s:\n" % label)
                for q in qs[sc]:
                    lines.append("%s.%s  %s" % (label, q["id"], q["text"]))
                    for L in sorted(q["options"]):
                        lines.append("   %s) %s" % (L, q["options"][L]))
                    lines.append("")
            doc = "\n".join(lines)
            text_tokens += token_est(doc)
            open(os.path.join(pk, "PACKET.md"), "w", encoding="utf-8").write(doc)
            json.dump(key, open(os.path.join(kdir, rid + ".json"), "w"), indent=1)
            summary["packets"][rid] = {"scene_order": order, "image_tokens": img_tokens, "text_tokens_est": text_tokens, "files": sorted(os.listdir(pk)) + ["images/" + f for f in sorted(os.listdir(os.path.join(pk, "images")))]}
    json.dump(summary, open(os.path.join(ROOT, "packet_summary.json"), "w"), indent=1)
    print("packets:", len(summary["packets"]))
    print("D tokens per scene vs A (%d):" % summary["image_tokens_each"], summary["d_tokens_by_scene"], "median", summary["d_tokens_median_scene"])


# ---------------------------------------------------------------- grading
def grade(rid, answers):
    key = json.load(open(os.path.join(ROOT, "key", rid + ".json")))
    truth = json.load(open(os.path.join(ROOT, "truth.json")))
    rows = []
    for label, sc in key["scenes"].items():
        for qid, t in truth[sc].items():
            a = answers.get("%s.%s" % (label, qid))
            a = a.strip().upper()[:1] if isinstance(a, str) else None
            rows.append({"reader": rid, "arm": key["arm"], "scene": sc, "qid": qid, "type": t["type"], "lookup": t["lookup"], "answer": a, "truth": t["answer"], "correct": a == t["answer"]})
    return rows


def summarize(rows):
    out = {"n": len(rows), "acc": sum(r["correct"] for r in rows) / float(max(1, len(rows))), "by_type": {}}
    for r in rows:
        b = out["by_type"].setdefault(r["type"], [0, 0])
        b[0] += r["correct"]
        b[1] += 1
    return out


def cmd_grade(rid, path):
    rows = grade(rid, json.load(open(path)))
    print(json.dumps(summarize(rows), indent=1))


def cmd_selfcheck():
    truth = json.load(open(os.path.join(ROOT, "truth.json")))
    bad = 0
    # 1 projection vs sampled pixels
    worst = 0.0
    for sc in SCENES:
        td = load(sc)
        for i in td["ids"]:
            if not in_view(td, i):
                continue
            o = sample(td, 0)["objs"][i]
            pr = project(td["camera"], o["c"])
            if pr and o["px"][0] is not None:
                worst = max(worst, math.hypot(pr[0] - o["px"][0], pr[1] - o["px"][1]))
    print("projection vs sampled pixels, worst %.3f px" % worst)
    bad += worst > 1.0
    for rid in sorted(f[:-5] for f in os.listdir(os.path.join(ROOT, "key"))):
        key = json.load(open(os.path.join(ROOT, "key", rid + ".json")))
        ans = {}
        shifted = {}
        for label, sc in key["scenes"].items():
            for qid, t in truth[sc].items():
                ans["%s.%s" % (label, qid)] = t["answer"]
                nxt = chr(65 + (ord(t["answer"]) - 65 + 1) % 2)
                shifted["%s.%s" % (label, qid)] = nxt if t["answer"] in "AB" else "A" if t["answer"] != "A" else "B"
        o = summarize(grade(rid, ans))["acc"]
        s = summarize(grade(rid, shifted))["acc"]
        if o != 1.0 or s >= 0.9:
            bad += 1
            print("FAIL", rid, o, s)
    print("selfcheck:", "FAIL" if bad else "ok", "(oracle 1.0, wrong-letter answers low on every packet)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "gen":
        cmd_gen()
    elif cmd == "packets":
        cmd_packets()
    elif cmd == "grade":
        cmd_grade(sys.argv[2], sys.argv[3])
    elif cmd == "selfcheck":
        cmd_selfcheck()
    else:
        print(__doc__)
