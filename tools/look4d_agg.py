import json, os, sys, random
WT = "C:/Users/Nick/Desktop/poser/.claude/worktrees/w4-look4d"
sys.path.insert(0, os.path.join(WT, "tools"))
os.chdir(WT)
import look4d_truth as L
R = "C:/Users/Nick/.claude/jobs/789aa9b0/tmp/readers"
ARMS = ["A", "B", "C", "D", "CD", "Z", "Dscr"]
MOTION_SC = ("s1_engine", "s2_arm", "s3_walk", "s4_fall")
MOTION_T = ("fastest", "toward", "collide", "predict")
SPATIAL_T = ("screen_lr", "screen_ud", "out_of_view", "collide", "predict")
qs = json.load(open("out/look4d/questions.json"))
qlist = qs if isinstance(qs, list) else [q for v in qs.values() for q in (v if isinstance(v, list) else [])]
opt = {(q["scene"], q["id"]): q["options"] for q in qlist}

rows = []
missing = {}
for arm in ARMS:
    for k in (1, 2, 3):
        rid = "%s_r%d" % (arm, k)
        p = os.path.join(R, rid, "answers_first.json" if rid == "Dscr_r1" else "answers.json")
        if not os.path.exists(p):
            missing[rid] = "no file"; continue
        rr = L.grade(rid, json.load(open(p)))
        missing[rid] = sum(1 for r in rr if r["answer"] is None)
        rows += rr

def content(r, letter):
    o = opt.get((r["scene"], r["qid"]))
    if o is None or letter is None: return letter
    if isinstance(o, dict): return str(o.get(letter, letter)).strip().lower()
    i = ord(letter) - 65
    return str(o[i]).split(")", 1)[-1].strip().lower() if 0 <= i < len(o) else letter

def sel(arm, f=lambda r: True):
    return [r for r in rows if r["arm"] == arm and f(r)]
def acc(rs): return sum(r["correct"] for r in rs) / len(rs) if rs else float("nan")
def bal(rs):
    by = {}
    for r in rs:
        c = content(r, r["truth"]); by.setdefault(c, []).append(r["correct"])
    return sum(sum(v) / len(v) for v in by.values()) / len(by) if by else float("nan")

motion = lambda r: r["scene"] in MOTION_SC and r["type"] in MOTION_T
spatial = lambda r: r["type"] in SPATIAL_T
null_m = lambda r: r["scene"] == "s6_null"

def boot(a1, a2, f, n=4000, seed=1):
    # cluster bootstrap over questions (scene,qid): diff acc(a1)-acc(a2)
    qids = sorted({(r["scene"], r["qid"]) for r in rows if f(r)})
    m1 = {}; m2 = {}
    for r in rows:
        if not f(r): continue
        key = (r["scene"], r["qid"])
        if r["arm"] == a1: m1.setdefault(key, []).append(r["correct"])
        if r["arm"] == a2: m2.setdefault(key, []).append(r["correct"])
    rng = random.Random(seed); ds = []
    for _ in range(n):
        s = [rng.choice(qids) for _ in qids]
        x = [v for q in s for v in m1.get(q, [])]; y = [v for q in s for v in m2.get(q, [])]
        if x and y: ds.append(sum(x) / len(x) - sum(y) / len(y))
    ds.sort()
    pt = acc(sel(a1, f)) - acc(sel(a2, f))
    return pt, ds[int(0.025 * len(ds))], ds[int(0.975 * len(ds))]

print("missing answers:", missing)
print("\n%-5s %6s %6s %6s %6s %6s %6s %6s" % ("arm", "all", "bal", "motion", "spatl", "lookup", "nonlk", "S6"))
for a in ARMS:
    print("%-5s %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f" % (a, acc(sel(a)), bal(sel(a)), acc(sel(a, motion)), acc(sel(a, spatial)),
          acc(sel(a, lambda r: r["lookup"])), acc(sel(a, lambda r: not r["lookup"])), acc(sel(a, null_m))))
types = sorted({r["type"] for r in rows})
print("\nby type (pooled reps):")
print("%-12s" % "type" + "".join("%7s" % a for a in ARMS))
for t in types:
    print("%-12s" % t + "".join("%7.2f" % acc(sel(a, lambda r, t=t: r["type"] == t)) for a in ARMS) + "  n=%d" % (len(sel("A", lambda r, t=t: r["type"] == t)) // 3))
print("\nper-rep overall acc:")
for a in ARMS:
    print(a, [round(acc([r for r in rows if r["reader"] == "%s_r%d" % (a, k)]), 3) for k in (1, 2, 3)])
print("\nBARS (diff, 95% CI)")
for name, a1, a2, f in [("P1 C-B motion", "C", "B", motion), ("P2 CD-D spatial", "CD", "D", spatial),
                        ("no-harm CD-D all", "CD", "D", lambda r: True), ("null CD-A on S6", "CD", "A", null_m),
                        ("scr Dscr-Z all", "Dscr", "Z", lambda r: True), ("D-Dscr all", "D", "Dscr", lambda r: True),
                        ("ref CD-A motion", "CD", "A", motion), ("C-A motion", "C", "A", motion), ("D-C motion", "D", "C", motion),
                        ("B-A motion", "B", "A", motion)]:
    pt, lo, hi = boot(a1, a2, f)
    print("%-18s %+.3f [%+.3f, %+.3f]" % (name, pt, lo, hi))
print("\nP2 per type CD-D:")
for t in types:
    print("  %-12s %+.2f" % (t, acc(sel("CD", lambda r, t=t: r["type"] == t)) - acc(sel("D", lambda r, t=t: r["type"] == t))))
json.dump(rows, open("C:/Users/Nick/.claude/jobs/789aa9b0/tmp/look4d_rows.json", "w"))
