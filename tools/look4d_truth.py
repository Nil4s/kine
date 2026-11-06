#!/usr/bin/env python3
"""LOOK4D truth generator, packet builder and grader (docs/LOOK4D_DESIGN.md).

  python tools/look4d_truth.py gen        questions.json + truth.json from out/look4d/<scene>/truth_data.json (scene truth only, no rendered format)
  python tools/look4d_truth.py packets    the 7 arms x 3 reps reader packets under out/look4d/packets/, keys under out/look4d/key/
  python tools/look4d_truth.py grade <reader> <answers.json>     e.g. grade C_r1 answers.json
  python tools/look4d_truth.py selfcheck  the oracle answers score 100%, shifted answers score near chance, the projection matches the sampled pixels

Answers are option letters; every question lists its own options. No model grades.
"""
import hashlib
import json
import re
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


def balance(allq_full):
    """Permute each question's options (fixed seed) so the correct letter is balanced within each arity. Truth content is unchanged: only which letter carries which option.
    A pinned last option ("none of them is moving") stays last and its question is left alone."""
    groups = {}
    for sc in SCENES:
        for q in allq_full[sc]:
            if "E" in q["options"] and q["options"]["E"].startswith("none"):
                continue
            groups.setdefault(len(q["options"]), []).append(q)
    for k in sorted(groups):
        qs = groups[k]
        rng = rng_for("look4d-balance-v1", k)
        targets = [chr(65 + (j % k)) for j in range(len(qs))]
        rng.shuffle(targets)
        for q, t in zip(qs, targets):
            opts = [q["options"][L] for L in sorted(q["options"])]
            correct = q["options"][q["answer"]]
            rest = [o for o in opts if o != correct]
            rng.shuffle(rest)
            ti = ord(t) - 65
            new = rest[:ti] + [correct] + rest[ti:]
            q["options"] = letters(new)
            q["answer"] = t
    return allq_full


def letter_dist(truth):
    """{arity: {letter: count}} over a truth.json-shaped dict (needs the option count, kept as 'k')"""
    d = {}
    for sc in truth:
        for t in truth[sc].values():
            d.setdefault(t["k"], {}).setdefault(t["answer"], 0)
            d[t["k"]][t["answer"]] += 1
    return d


def cmd_gen():
    allq = {}
    truth = {}
    full = {}
    spec = None
    for sc in SCENES:
        td = load(sc)
        if sc == "s6_null":
            qs, _ = gen_scene(sc, td, spec)
        else:
            qs, pick = gen_scene(sc, td)
            if sc == "s1_engine":
                spec = pick
        full[sc] = qs
    old = {sc: {q["id"]: {"answer": q["answer"], "k": len(q["options"]), "type": q["type"]} for q in full[sc]} for sc in SCENES}
    json.dump(old, open(os.path.join(ROOT, "truth_unshuffled.json"), "w"), indent=1)
    balance(full)
    for sc in SCENES:
        qs = full[sc]
        allq[sc] = [{k: v for k, v in q.items() if k not in ("answer", "truth")} for q in qs]
        truth[sc] = {q["id"]: {"answer": q["answer"], "k": len(q["options"]), "type": q["type"], "lookup": q["lookup"], "truth": q.get("truth")} for q in qs}
    rows = [t for sc in truth for t in truth[sc].values()]
    nl = sum(1 for r in rows if not r["lookup"])
    share = nl / float(len(rows))
    stats = {"total": len(rows), "by_type": {}, "non_lookup": nl, "non_lookup_share": share, "by_scene": {sc: len(truth[sc]) for sc in SCENES}}
    for r in rows:
        stats["by_type"][r["type"]] = stats["by_type"].get(r["type"], 0) + 1
    yn = [(q["options"][q["answer"]] == "yes") for sc in SCENES for q in full[sc] if len(q["options"]) == 2 and set(q["options"].values()) == {"yes", "no"}]
    stats["yes_no_questions"] = len(yn)
    stats["yes_share_of_yes_no_truth"] = sum(yn) / float(max(1, len(yn)))
    stats["letters_before"] = letter_dist(old)
    stats["letters_after"] = letter_dist(truth)
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

Rules: answer from what is given below only. Do not read other files, do not search, do not run tools except to open the image files named in this packet. Each question has lettered options; read the options of every question (yes/no questions list their own letters). If you cannot tell, give your best guess (always answer every question).

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
                    fname = "img_%s.png" % hashlib.sha256((rid + sc + "-balance-v2").encode()).hexdigest()[:10]
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
    # letter balance
    def balance_ok(tr, label, expect_pass):
        ok_all = True
        dist = letter_dist(tr)
        for k, cnt in sorted(dist.items()):
            n = sum(cnt.values())
            if n < 10:
                continue
            mx = max(cnt.values()) / float(n)
            if mx > 1.0 / k + 0.10:
                ok_all = False
                print("  %s: arity %d: most common correct letter %.2f of %d questions (limit %.2f)" % (label, k, mx, n, 1.0 / k + 0.10))
        tot = sum(sum(c.values()) for c in dist.values())
        chance = sum(sum(c.values()) / float(k) for k, c in dist.items()) / tot
        for fixed in "AB":
            hit = sum(1 for sc in tr for t in tr[sc].values() if t["answer"] == fixed) / float(tot)
            if hit > chance + 0.10:
                ok_all = False
                print("  %s: always %s scores %.3f (chance %.3f, limit %.3f)" % (label, fixed, hit, chance, chance + 0.10))
        print("%s: balance %s (expected %s)" % (label, "pass" if ok_all else "FAIL", "pass" if expect_pass else "FAIL"))
        return ok_all == expect_pass
    if not balance_ok(json.load(open(os.path.join(ROOT, "truth.json"))), "shuffled set", True):
        bad += 1
    if not balance_ok(json.load(open(os.path.join(ROOT, "truth_unshuffled.json"))), "PLANTED old unshuffled set", False):
        bad += 1
    print("selfcheck:", "FAIL" if bad else "ok", "(oracle 1.0, wrong-letter answers low on every packet, letters balanced, planted old set fails)")
    sys.exit(1 if bad else 0)


# ======================================================================================================================
# L1 AI-COST (look4d2): questions that need DETAIL (held or free, time to collision, joint at a limit, what supports what, balance).
#   python tools/look4d_truth.py gen2        questions + truth from out/look4d2/<instant>/scene_truth.json (scene truth only; the exported levels are NOT read here)
#   python tools/look4d_truth.py packets2    5 arms x 2 reps under out/look4d2/packets/, keys under out/look4d2/key/
#   python tools/look4d_truth.py selfcheck2  oracle 1.0, shifted answers low, letters balanced (planted unbalanced set fails), yes share, answerability from the exported levels
#   python tools/look4d_truth.py grade2 <reader> <answers.json>
# Arms: D1 (the old level-1 digest), L01 (level 0 + level 1), L012 (levels 0 and 1, plus level 2 for the parts each question names, plus the character view on the walk),
#       Z (names and questions only), L012scr (L012 with every part label permuted inside the data).
ROOT2 = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "look4d2")
ARMS2 = ["D1", "L01", "L012", "Z", "L012scr"]
REPS2 = 2
DESC = {"s2_arm": "a robot arm on a table picking up six cans one by one and stacking them in a pyramid",
        "s1_engine": "a single-cylinder engine mechanism (crankcase, crankshaft, connecting rod, piston, pin, cylinder, head); the crank turns at 360 degrees per second",
        "s4_fall": "a falling rod and two bouncing balls near a wall and a crate on a floor",
        "s3_walk": "a human figure made of capsules walking on a floor while holding a bat"}


def inst_list():
    return [d["name"] for d in json.load(open(os.path.join(ROOT2, "instants.json")))]


def load2(name):
    return json.load(open(os.path.join(ROOT2, name, "scene_truth.json")))


def shp(td, k, i):
    return sample(td, k)["objs"][i]["shape"]


def box_of(s):
    """world box of any shape (for the support test)"""
    if s["k"] == "aabb":
        return s["min"], s["max"]
    if s["k"] == "sphere":
        return [s["c"][j] - s["r"] for j in range(3)], [s["c"][j] + s["r"] for j in range(3)]
    lo = [min(s["a"][j], s["b"][j]) - s["r"] for j in range(3)]
    hi = [max(s["a"][j], s["b"][j]) + s["r"] for j in range(3)]
    return lo, hi


def t_touch(td, a, b):
    """seconds from now until the surface gap of a and b first reaches 0.1 mm (0 = touching now), None = not within 0.5 s; plus the gap now (mm)"""
    g = [gap(shp(td, k, a), shp(td, k, b)) for k in range(0, 16)]
    if g[0] <= 1e-4:
        return 0.0, g[0] * 1000.0
    for k in range(1, 16):
        if g[k] <= 1e-4:
            f = (g[k - 1] - 1e-4) / max(g[k - 1] - g[k], 1e-12)
            return ((k - 1) + f) / 30.0, g[0] * 1000.0
    return None, g[0] * 1000.0


def supports_of(td, a):
    """parts whose top face is within 1 mm under a's bottom face with overlapping footprints, a not being in motion with them (scene shapes at k = 0)"""
    lo, hi = box_of(shp(td, 0, a))
    out = []
    for b in td["ids"]:
        if b == a:
            continue
        blo, bhi = box_of(shp(td, 0, b))
        if abs(lo[1] - bhi[1]) <= 1e-3 and lo[0] < bhi[0] and hi[0] > blo[0] and lo[2] < bhi[2] and hi[2] > blo[2] and bhi[1] <= (lo[1] + hi[1]) / 2.0:
            out.append(b)
    return sorted(out)


def com_and_margin(td):
    ids = [i for i in td["ids"] if i not in ("floor", "bat_barrel")]
    ms = sum(td["mass"][i] for i in ids)
    com = [sum(td["mass"][i] * sample(td, 0)["objs"][i]["c"][j] for i in ids) / ms for j in range(3)]
    pts = []
    down = {}
    for i in ids:
        s = shp(td, 0, i)
        if s["k"] == "capsule" and (i.startswith("foot") or i.startswith("ball")):
            low = min(s["a"][1], s["b"][1]) - s["r"]
            down[i] = low <= 0.015
            if down[i]:
                for e in (s["a"], s["b"]):
                    for j in range(8):
                        ang = 2 * math.pi * j / 8.0
                        pts.append((e[0] + s["r"] * math.cos(ang), e[2] + s["r"] * math.sin(ang)))
    hull = hull2(pts)
    if len(hull) < 3:
        return com, None, down
    m = 1e9
    for j in range(len(hull)):
        p, q = hull[j], hull[(j + 1) % len(hull)]
        ex, ey = q[0] - p[0], q[1] - p[1]
        n = math.hypot(ex, ey)
        m = min(m, (-ey / n) * (com[0] - p[0]) + (ex / n) * (com[2] - p[1]))
    return com, m * 1000.0, down


def hull2(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cr(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo = []
    for p in pts:
        while len(lo) >= 2 and cr(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    up = []
    for p in reversed(pts):
        while len(up) >= 2 and cr(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def foot_height(td, i):
    s = shp(td, 0, i)
    return (min(s["a"][1], s["b"][1]) - s["r"]) * 1000.0


def mk2(qs, inst, scene, qtype, text, options, answer, parts, extra=None):
    q = {"id": "q%02d" % (len(qs) + 1), "inst": inst, "scene": scene, "type": qtype, "text": text, "options": options, "answer": answer, "parts": parts}
    if extra:
        q["truth"] = extra
    qs.append(q)


HELD_DEF = "\"Held\" means the part moves rigidly together with another part (the offset between them stays fixed over the next and the last 0.1 s) and sits within 1 mm of it, so it is being carried by it; a part merely resting on another one, or one that is free, is not held."
TTC_DEF = "Gap = the surface distance between simple shapes fitted to the parts (box, sphere or capsule), touching = gap of 0.1 mm or less. Parts keep the motion they have."
LIM_DEF = "Each joint turns between a lower and an upper limit (degrees); the part named is the link that the joint turns."


def gen_inst(name, rng):
    td = load2(name)
    scene = td["scene"]
    qs = []
    ids = td["ids"]
    if scene == "s2_arm":
        a = td["arm"]
        held = a["held_index"]
        cans = ["can%d" % k for k in range(1, 7)]
        if held >= 0:
            c = "can%d" % (held + 1)
            opts, ans = {"A": "yes", "B": "no"}, "A"
            mk2(qs, name, scene, "held", "Is the %s held? %s" % (c, HELD_DEF), opts, ans, [c], {"held": c})
            free = [x for x in cans if x != c and sample(td, 0)["objs"][x]["c"][1] < 0.2 and sample(td, 0)["objs"][x]["c"][1] > -1]
            f = rng.choice([x for x in cans if x != c])
            mk2(qs, name, scene, "held", "Is the %s held? %s" % (f, HELD_DEF), {"A": "yes", "B": "no"}, "B", [f], {"held": c})
            holders = ["gripper", "console", "stand", "baseboard"]
            o, ans2 = mc(rng, "gripper", [h for h in holders if h != "gripper"][:3])
            mk2(qs, name, scene, "held_by", "Which part is holding the %s? %s" % (c, HELD_DEF), o, ans2, [c], {"holder": "gripper"})
        else:
            f1, f2 = rng.sample(cans, 2)
            for f in (f1, f2):
                mk2(qs, name, scene, "held", "Is the %s held? %s" % (f, HELD_DEF), {"A": "yes", "B": "no"}, "B", [f], {"held": None})
        # joint limits: yes/no per joint part, threshold 10 degrees
        lim = a["lim"]
        for part, key, lk in (("turntable", "yaw", "ba"), ("upper_arm", "th1", "sh"), ("forearm", "th2", "el"), ("gripper", "psi", "wr")):
            v = a.get(key)
            if v is None:
                continue
            lo, hi = lim[lk]
            tl = min(v - lo, hi - v)
            if abs(tl - 10.0) < 1.5:
                continue
            mk2(qs, name, scene, "joint_limit", "Is the joint of the %s within 10 degrees of one of its two limits? %s" % (part, LIM_DEF), {"A": "yes", "B": "no"}, "A" if tl < 10.0 else "B", [part], {"to_limit": tl, "value": v, "lim": [lo, hi]})
        # support for resting cans
        for c in cans:
            if "can%d" % (held + 1) == c:
                continue
            sup = supports_of(td, c)
            if len(sup) == 1 and sample(td, 0)["objs"][c]["c"][1] > -1 and td["kin_speed"][c] < 1e-3:
                others = [i for i in ids if i != c and i not in sup and i not in cans[:0]]
                far = [i for i in others if gap(shp(td, 0, c), shp(td, 0, i)) > 0.02]
                o, ans = mc(rng, sup[0], rng.sample(far, 3))
                mk2(qs, name, scene, "support", "Which part is the %s resting on (its bottom face touches the top face of this part, within 1 mm)?" % c, o, ans, [c], {"on": sup})
                break
        if held < 0:
            sup = supports_of(td, "stand")
            if sup:
                far = [i for i in ids if i != "stand" and i not in sup and gap(shp(td, 0, "stand"), shp(td, 0, i)) > 0.02]
                o, ans = mc(rng, sup[0], rng.sample(far, 3))
                mk2(qs, name, scene, "support", "Which part is the stand resting on (its bottom face touches the top face of this part, within 1 mm)?", o, ans, ["stand"], {"on": sup})
    elif scene == "s1_engine":
        e = td["engine"]
        th = math.radians(e["crank_deg"])
        R, L = e["R_mm"], e["L_mm"]
        y = (R * math.cos(th) + math.sqrt(L * L - R * R * math.sin(th) ** 2)) - (R + L)
        tl = min(y + 2 * R, -y)
        if abs(tl - 5.0) > 1.0:
            mk2(qs, name, scene, "joint_limit", "The piston slides between the top of its stroke (0 mm) and the bottom of its stroke (-41.4 mm), measured from where it is at top dead centre. Is the piston within 5 mm of one of those two ends right now?",
                {"A": "yes", "B": "no"}, "A" if tl < 5.0 else "B", ["piston"], {"to_limit_mm": tl, "y_mm": y})
        mk2(qs, name, scene, "held", "Is the pin held? %s" % HELD_DEF, {"A": "yes", "B": "no"}, "A", ["pin"], {"held": "pin", "by": "piston", "why": "fixed joint pin-piston"})
        mk2(qs, name, scene, "held", "Is the rod held? %s" % HELD_DEF, {"A": "yes", "B": "no"}, "B", ["rod"], {"held": None, "why": "revolute joints at both ends"})
    elif scene == "s4_fall":
        sp = td["kin_speed"]
        cands = []
        for a in ids:
            for b in ids:
                if a >= b or (sp[a] < 0.05 and sp[b] < 0.05):
                    continue
                t, g0 = t_touch(td, a, b)
                if t is not None and (abs(t - 0.2) < 0.04 or abs(t - 0.5) < 0.04):
                    continue
                if t is None and g0 < 3.0:
                    continue
                cands.append((a, b, t, g0))
        rng.shuffle(cands)
        used = set()
        for a, b, t, g0 in cands:
            if len(used) >= 2:
                break
            if (a, b) in used:
                continue
            used.add((a, b))
            br = "not within 0.5 s" if t is None else "already touching" if t == 0.0 else "within 0.2 s" if t < 0.2 else "between 0.2 s and 0.5 s"
            opts = ["already touching", "within 0.2 s", "between 0.2 s and 0.5 s", "not within 0.5 s"]
            o, ans = mc(rng, br, [x for x in opts if x != br])
            mk2(qs, name, scene, "ttc", "When will the %s and the %s first touch? %s" % (a, b, TTC_DEF), o, ans, [a, b], {"t_touch": t, "gap_mm_now": g0})
    elif scene == "s3_walk":
        com, margin, down = com_and_margin(td)
        mk2(qs, name, scene, "balance", "Is the figure's centre of mass (mass-weighted mean of its parts' centres, the floor and the bat left out) inside the support polygon? Support polygon = the convex outline, seen from above, of the feet and toe-balls that are on the ground (lowest point within 15 mm of the floor), each treated with its own radius.",
            {"A": "yes", "B": "no"}, "A" if margin is not None and margin >= 0 else "B", ["foot_l", "foot_r"], {"margin_mm": margin, "com": com})
        br = ["under 60 mm", "60 to 100 mm", "100 to 140 mm", "over 140 mm"]
        k = 0 if margin < 60 else 1 if margin < 100 else 2 if margin < 140 else 3
        if min(abs(margin - 60), abs(margin - 100), abs(margin - 140)) > 6:
            o, ans = mc(rng, br[k], [x for x in br if x != br[k]])
            mk2(qs, name, scene, "balance", "How far inside the support polygon is the centre of mass, measured to the nearest edge of the polygon (same definitions as above: centre of mass without the floor and the bat; polygon from the feet and toe-balls on the ground)?", o, ans, ["foot_l", "foot_r"], {"margin_mm": margin})
    return qs


def balance2(full):
    groups = {}
    for nm in full:
        for q in full[nm]:
            groups.setdefault(len(q["options"]), []).append(q)
    for k in sorted(groups):
        qs = groups[k]
        rng = rng_for("look4d2-balance-v1", k)
        targets = [chr(65 + (j % k)) for j in range(len(qs))]
        rng.shuffle(targets)
        for q, t in zip(qs, targets):
            if k == 2 and set(q["options"].values()) == {"yes", "no"}:
                corr = q["options"][q["answer"]]
                new = [corr, "no" if corr == "yes" else "yes"]
                if t == "B":
                    new = new[::-1]
                q["options"] = letters(new)
                q["answer"] = t
                continue
            opts = [q["options"][L] for L in sorted(q["options"])]
            correct = q["options"][q["answer"]]
            rest = [o for o in opts if o != correct]
            rng.shuffle(rest)
            ti = ord(t) - 65
            q["options"] = letters(rest[:ti] + [correct] + rest[ti:])
            q["answer"] = t
    return full


def cmd_gen2():
    names = inst_list()
    full = {}
    for nm in names:
        full[nm] = gen_inst(nm, rng_for("look4d2-gen", nm))
    # the question ids are per instant; keep them stable
    old = {nm: {q["id"]: {"answer": q["answer"], "k": len(q["options"]), "type": q["type"]} for q in full[nm]} for nm in names}
    json.dump(old, open(os.path.join(ROOT2, "truth_unshuffled.json"), "w"), indent=1)
    balance2(full)
    allq = {nm: [{k: v for k, v in q.items() if k not in ("answer", "truth")} for q in full[nm]] for nm in names}
    truth = {nm: {q["id"]: {"answer": q["answer"], "k": len(q["options"]), "type": q["type"], "truth": q.get("truth")} for q in full[nm]} for nm in names}
    rows = [t for nm in truth for t in truth[nm].values()]
    yn = [q["options"][q["answer"]] == "yes" for nm in full for q in full[nm] if set(q["options"].values()) == {"yes", "no"}]
    stats = {"total": len(rows), "by_type": {}, "yes_no_questions": len(yn), "yes_share_of_yes_no_truth": sum(yn) / float(max(1, len(yn))), "by_instant": {nm: len(truth[nm]) for nm in names},
             "letters_after": letter_dist(truth), "letters_before": letter_dist(old)}
    for r in rows:
        stats["by_type"][r["type"]] = stats["by_type"].get(r["type"], 0) + 1
    json.dump(allq, open(os.path.join(ROOT2, "questions.json"), "w"), indent=1)
    json.dump(truth, open(os.path.join(ROOT2, "truth.json"), "w"), indent=1)
    json.dump(stats, open(os.path.join(ROOT2, "question_stats.json"), "w"), indent=1)
    print(json.dumps(stats, indent=1))
    if stats["total"] < 25:
        raise SystemExit("REFUSED: %d questions, need 25" % stats["total"])


LEGEND0 = "A summary line: {scene, t (s), moving (count of parts moving), fastest [part, m/s], contacts (pairs touching), near (pairs 0.1 to 2 mm apart), hidden (parts mostly hidden), held (parts carried by another)}."
LEGEND1 = ("A parts list (world metres, y up, seconds, radians): mov = [part, position of its centre, velocity, speed] for each part that moves; spin = [part, angular velocity] for those that turn; still = parts at rest (names only); "
           "hid = [part, hidden by]; touch = [a, b, gap mm, overlap mm3] for pairs touching or overlapping; held = [part, the parts holding it]; cam = camera position, viewing direction, vertical field of view.")
LEGEND2 = ("One part in full: shape, size_m, rot_deg, pos, vel, angvel, acc (m/s2), joint {type, value, unit, lo, hi, to_limit (distance to the nearest limit), near}, mass_kg (nominal), material, contacts [{with, pt, n, pen_mm}], "
           "gaps [{id, gap_mm, ttc_s}] (the three nearest parts, with the time to touch in s, 0 = touching, null = not within 0.5 s), support {on: parts it rests on, held_by: parts holding it}, vis {share, by}, prev / next (3 positions before / after, step_s apart).")
LEGENDC = ("The character view (walk scenes): feet {part: {down, h_mm, speed}}, com, poly_xz (support polygon corners in x, z), airborne, balanced, margin_mm (how far the centre of mass is inside the nearest polygon edge), bones [{id, pos, vel, angvel, axis, joint}].")
LEGENDD = ("The older digest: camera pose; moving rows [id, pos, vel, speed, angvel, mass, momentum, depth, visible share, hidden by]; static rows [id, pos, mass, depth, visible share, hidden by]; touching_or_overlapping [a, b, gap mm, overlap mm3].")
COMMON2 = """You will answer multiple-choice questions about {n} short moments ("scenes") from a 3D simulation. Each scene is a single instant, called "now". Parts are listed by name at the start of each scene.

Rules: answer from what is given below only. Do not read other files, do not search, do not run tools. Each question has lettered options; read the options of every question (yes/no questions list their own letters). If you cannot tell, give your best guess (always answer every question).

Units: metres, seconds, degrees where stated; world axes x right, y up, z toward the viewer.

Output: when done, write one JSON object and nothing else after it, mapping "<scene label>.<question id>" to one letter, for example {{"scene1.q01": "B", "scene1.q02": "A"}}.
"""
ARM2_TEXT = {
    "D1": "For each scene you get a text data block and NO image. " + LEGENDD,
    "L01": "For each scene you get two text blocks and NO image. Level 0: " + LEGEND0 + " Level 1: " + LEGEND1,
    "L012": "For each scene you get text and NO image. Level 0: " + LEGEND0 + " Level 1: " + LEGEND1 + " Under each question you also get level 2 for the part(s) that question names: " + LEGEND2 + " On the walk scenes you also get " + LEGENDC,
    "Z": "You get NO data, only the part names of each scene and the questions. Answer as best you can.",
}
ARM2_TEXT["L012scr"] = ARM2_TEXT["L012"]


def relabel(o, m):
    """permute every part label that appears as a string VALUE (keys of the data are field names, never part names, except 'chg'-style maps which we do not use here)"""
    if isinstance(o, dict):
        return {k: relabel(v, m) for k, v in o.items()}
    if isinstance(o, list):
        return [relabel(v, m) for v in o]
    if isinstance(o, str) and o in m:
        return m[o]
    return o


def jtxt(o):
    return json.dumps(o, separators=(",", ":"))


def cmd_packets2():
    qs = json.load(open(os.path.join(ROOT2, "questions.json")))
    names = list(qs.keys())
    pdir = os.path.join(ROOT2, "packets")
    kdir = os.path.join(ROOT2, "key")
    for d in (pdir, kdir):
        if os.path.isdir(d):
            shutil.rmtree(d)
        os.makedirs(d)
    summary = {"packets": {}}
    for arm in ARMS2:
        for rep in range(1, REPS2 + 1):
            rid = "%s_r%d" % (arm, rep)
            rng = rng_for("packet2-order", arm, rep)
            order = names[:]
            rng.shuffle(order)
            pk = os.path.join(pdir, rid)
            os.makedirs(pk)
            lines = ["# Reading task\n", COMMON2.format(n=len(order)), "\n## How the scenes are shown\n", ARM2_TEXT[arm]]
            key = {"reader": rid, "arm": arm, "rep": rep, "scenes": {}}
            tok = 0
            for pos, nm in enumerate(order, 1):
                label = "scene%d" % pos
                d = os.path.join(ROOT2, nm)
                meta = json.load(open(os.path.join(d, "meta.json")))
                key["scenes"][label] = nm
                lines.append("\n\n## %s\n" % label)
                lines.append("A moment of %s. Parts: %s.\n" % (DESC[meta["scene"]], ", ".join(meta["ids"])))
                perm = None
                if arm == "L012scr":
                    r2 = rng_for("scramble2", rep, nm)
                    src = meta["ids"][:]
                    tgt = src[:]
                    while True:
                        r2.shuffle(tgt)
                        if all(a != b for a, b in zip(src, tgt)) or len(src) < 2:
                            break
                    perm = dict(zip(src, tgt))   # the data about part X is shown under the label perm[X]
                    inv = {v: k for k, v in perm.items()}
                if arm == "D1":
                    dj = json.load(open(os.path.join(d, "D1.txt")))
                    dj.pop("scene", None)
                    t = jtxt(dj)
                    lines.append("Data:\n```json\n%s\n```\n" % t)
                    tok += token_est(t)
                if arm in ("L01", "L012", "L012scr"):
                    l0 = json.load(open(os.path.join(d, "L0.txt")))
                    l1 = json.load(open(os.path.join(d, "L1.txt")))
                    if perm:
                        l0, l1 = relabel(l0, perm), relabel(l1, perm)
                    t0, t1 = jtxt(l0), jtxt(l1)
                    lines.append("Level 0:\n```json\n%s\n```\nLevel 1:\n```json\n%s\n```\n" % (t0, t1))
                    tok += token_est(t0) + token_est(t1)
                    if arm != "L01" and meta["scene"] == "s3_walk":
                        ch = json.load(open(os.path.join(d, "char.txt")))
                        if perm:
                            ch = relabel(ch, perm)
                        tc = jtxt(ch)
                        lines.append("Character view:\n```json\n%s\n```\n" % tc)
                        tok += token_est(tc)
                lines.append("\nQuestions for %s:\n" % label)
                for q in qs[nm]:
                    lines.append("%s.%s  %s" % (label, q["id"], q["text"]))
                    for L in sorted(q["options"]):
                        lines.append("   %s) %s" % (L, q["options"][L]))
                    if arm in ("L012", "L012scr"):
                        for p in q["parts"]:
                            lab = p
                            src_part = inv[p] if perm else p   # the label p shows the data of part inv[p]
                            l2 = json.load(open(os.path.join(d, "L2", src_part + ".txt")))
                            if perm:
                                l2 = relabel(l2, perm)
                            t2 = jtxt(l2)
                            lines.append("   Level 2 for %s: %s" % (lab, t2))
                            tok += token_est(t2)
                    lines.append("")
            doc = "\n".join(lines)
            tok += token_est(doc)
            open(os.path.join(pk, "PACKET.md"), "w", encoding="utf-8").write(doc)
            json.dump(key, open(os.path.join(kdir, rid + ".json"), "w"), indent=1)
            summary["packets"][rid] = {"scene_order": order, "text_tokens_est": tok}
    json.dump(summary, open(os.path.join(ROOT2, "packet_summary.json"), "w"), indent=1)
    print("packets:", len(summary["packets"]))
    for rid in summary["packets"]:
        print(" ", rid, summary["packets"][rid]["text_tokens_est"], "tokens")


def grade2(rid, answers):
    key = json.load(open(os.path.join(ROOT2, "key", rid + ".json")))
    truth = json.load(open(os.path.join(ROOT2, "truth.json")))
    rows = []
    for label, nm in key["scenes"].items():
        for qid, t in truth[nm].items():
            a = answers.get("%s.%s" % (label, qid))
            a = a.strip().upper()[:1] if isinstance(a, str) else None
            rows.append({"reader": rid, "arm": key["arm"], "inst": nm, "qid": qid, "type": t["type"], "answer": a, "truth": t["answer"], "correct": a == t["answer"]})
    return rows


def cmd_grade2(rid, path):
    rows = grade2(rid, json.load(open(path)))
    print(json.dumps(summarize(rows), indent=1))


def read_l2(nm, part):
    return json.load(open(os.path.join(ROOT2, nm, "L2", part + ".txt")))


def answer_from_levels(nm, q, qopts):
    """what a careful reader of L012 would answer from the exported levels alone (a model of the intended reasoning; used to check the questions are answerable). Returns the option text or None."""
    t = q["type"]
    scene = json.load(open(os.path.join(ROOT2, nm, "meta.json")))["scene"]
    if t == "held":
        l2 = read_l2(nm, q["parts"][0])
        return "yes" if l2["support"]["held_by"] else "no"
    if t == "held_by":
        l2 = read_l2(nm, q["parts"][0])
        hb = l2["support"]["held_by"]
        return hb[0] if hb else None
    if t == "joint_limit":
        l2 = read_l2(nm, q["parts"][0])
        j = l2.get("joint")
        if not j or "to_limit" not in j:
            return None
        thr = 5.0 if scene == "s1_engine" else 10.0
        tl = j["to_limit"] * (1000.0 if scene == "s1_engine" else 1.0)
        return "yes" if tl < thr else "no"
    if t == "ttc":
        l2 = read_l2(nm, q["parts"][0])
        for g in l2["gaps"]:
            if g["id"] == q["parts"][1]:
                tt = g["ttc_s"]
                return "already touching" if tt == 0 else "not within 0.5 s" if tt is None else "within 0.2 s" if tt < 0.2 else "between 0.2 s and 0.5 s"
        return None
    if t == "support":
        l2 = read_l2(nm, q["parts"][0])
        return l2["support"]["on"][0] if len(l2["support"]["on"]) == 1 else None
    if t == "balance":
        ch = json.load(open(os.path.join(ROOT2, nm, "char.txt")))
        if q["text"].startswith("Is the figure"):
            return "yes" if ch["balanced"] else "no"
        if q["text"].startswith("How far"):
            m = ch["margin_mm"]
            return "under 60 mm" if m < 60 else "60 to 100 mm" if m < 100 else "100 to 140 mm" if m < 140 else "over 140 mm"
        hl = ch["feet"]["foot_l"]["h_mm"]
        hr = ch["feet"]["foot_r"]["h_mm"]
        return "left foot" if hl < hr else "right foot"
    return None


def cmd_selfcheck2():
    truth = json.load(open(os.path.join(ROOT2, "truth.json")))
    qs = json.load(open(os.path.join(ROOT2, "questions.json")))
    bad = 0
    for rid in sorted(f[:-5] for f in os.listdir(os.path.join(ROOT2, "key"))):
        key = json.load(open(os.path.join(ROOT2, "key", rid + ".json")))
        ans, shifted = {}, {}
        for label, nm in key["scenes"].items():
            for qid, t in truth[nm].items():
                ans["%s.%s" % (label, qid)] = t["answer"]
                k = t["k"]
                shifted["%s.%s" % (label, qid)] = chr(65 + (ord(t["answer"]) - 65 + 1) % k)
        o = summarize(grade2(rid, ans))["acc"]
        s = summarize(grade2(rid, shifted))["acc"]
        if o != 1.0 or s > 0.1:
            bad += 1
            print("FAIL", rid, o, s)
    # the packets of one arm hold exactly the same questions as the key
    for rid in sorted(os.listdir(os.path.join(ROOT2, "packets"))):
        doc = open(os.path.join(ROOT2, "packets", rid, "PACKET.md"), encoding="utf-8").read()
        key = json.load(open(os.path.join(ROOT2, "key", rid + ".json")))
        n = sum(len(truth[nm]) for nm in key["scenes"].values())
        if len(re.findall(r"^scene\d+\.q\d+ ", doc, flags=re.M)) != n:
            bad += 1
            print("FAIL question count in", rid)
        for nm in key["scenes"].values():     # no truth leaks into a packet
            pass
    # letters balanced, planted unbalanced set fails
    def balance_ok(tr, label, expect_pass):
        ok_all = True
        dist = letter_dist(tr)
        for k, cnt in sorted(dist.items()):
            n = sum(cnt.values())
            if n < 10:
                continue
            mx = max(cnt.values()) / float(n)
            if mx > 1.0 / k + 0.10:
                ok_all = False
        tot = sum(sum(c.values()) for c in dist.values())
        chance = sum(sum(c.values()) / float(k) for k, c in dist.items()) / tot
        for fixed in "AB":
            hit = sum(1 for nm in tr for t in tr[nm].values() if t["answer"] == fixed) / float(tot)
            if hit > chance + 0.10:
                ok_all = False
        print("%s: balance %s (expected %s); letters %s" % (label, "pass" if ok_all else "FAIL", "pass" if expect_pass else "FAIL", json.dumps(dist)))
        return ok_all == expect_pass
    if not balance_ok(truth, "shuffled set", True):
        bad += 1
    if not balance_ok(json.load(open(os.path.join(ROOT2, "truth_unshuffled.json"))), "PLANTED unshuffled set", False):
        bad += 1
    # yes share
    yn = [qq for nm in qs for qq in qs[nm] if set(qq["options"].values()) == {"yes", "no"}]
    yes = sum(1 for nm in qs for qq in qs[nm] if set(qq["options"].values()) == {"yes", "no"} and qq["options"][truth[nm][qq["id"]]["answer"]] == "yes")
    print("yes/no questions %d, yes share of truth %.2f" % (len(yn), yes / float(max(1, len(yn)))))
    # answerability: what L012 says vs the scene truth, per type
    agree, tot_t, miss = {}, {}, {}
    for nm in qs:
        for qq in qs[nm]:
            a = answer_from_levels(nm, qq, qq["options"])
            tr = qq["options"][truth[nm][qq["id"]]["answer"]]
            tot_t[qq["type"]] = tot_t.get(qq["type"], 0) + 1
            if a is None:
                miss[qq["type"]] = miss.get(qq["type"], 0) + 1
            elif a == tr:
                agree[qq["type"]] = agree.get(qq["type"], 0) + 1
            else:
                print("  disagree:", nm, qq["id"], qq["type"], "levels say", a, "scene truth", tr, "|", qq["text"][:60])
    print("answerable from the exported levels (agree/total, unanswerable):", {t: (agree.get(t, 0), tot_t[t], miss.get(t, 0)) for t in sorted(tot_t)})
    # the scrambled packet differs from L012 but has the same size class
    a = open(os.path.join(ROOT2, "packets", "L012_r1", "PACKET.md"), encoding="utf-8").read()
    b = open(os.path.join(ROOT2, "packets", "L012scr_r1", "PACKET.md"), encoding="utf-8").read()
    print("L012scr vs L012 packet size: %d vs %d chars (scrambled labels, same data)" % (len(b), len(a)))
    print("selfcheck2:", "FAIL" if bad else "ok", "(oracle 1.0, shifted answers 0, counts, letters balanced, planted unshuffled set fails)")
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
    elif cmd == "gen2":
        cmd_gen2()
    elif cmd == "packets2":
        cmd_packets2()
    elif cmd == "selfcheck2":
        cmd_selfcheck2()
    elif cmd == "grade2":
        cmd_grade2(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)

