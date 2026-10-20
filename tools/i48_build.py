"""ROADMAP I48 builder step 2: reduce the per-frame angle CSV (tools/i48_dump.gd, made from CMU mocap retargeted onto Kine) to the small
shipped statistic data_gen/mocap_stat.json. Raw frames are NOT written. usage: python i48_build.py frames.csv out.json [holdout_every]
Groups/features must match scripts/mocap_check.gd feats()."""
import sys, csv, json, math, collections
import numpy as np
BIN = 20.0
HEAD = open(sys.argv[1]).readline().strip().split(",")
rows = list(csv.reader(open(sys.argv[1])))[1:]
files = [r[0] for r in rows]
X = np.array([[float(x) for x in r[1:]] for r in rows], dtype=np.float32)
J = [h[:-2] for h in HEAD[1::3]]
col = {j: i for i, j in enumerate(J)}
def A(j): return X[:, 3*col[j]:3*col[j]+3]
def feats(group, side):
    if group == "spine":
        sb = sum(A(j)[:, 0] for j in ["spine_01", "spine_02", "spine_03"]); ss = sum(A(j)[:, 1] for j in ["spine_01", "spine_02", "spine_03"])
        st = sum(A(j)[:, 2] for j in ["spine_01", "spine_02", "spine_03"])
        return np.stack([sb, ss, st, A("neck_01")[:, 0] + A("head")[:, 0]], 1)
    top, low = ("upperarm", "lowerarm") if group == "arm" else ("thigh", "calf")
    a = A(top + side); b = A(low + side); sg = -1.0 if side == "_r" else 1.0
    return np.stack([a[:, 0], a[:, 1], a[:, 2] * sg, b[:, 0]], 1)
def cells(F): return np.floor(F / BIN).astype(int)
offs = [(i, j, k, l) for i in (-1, 0, 1) for j in (-1, 0, 1) for k in (-1, 0, 1) for l in (-1, 0, 1)]
def build(mask):
    out = {}
    for g in ["arm", "leg", "spine"]:
        sides = ["_l", "_r"] if g != "spine" else [""]
        cnt = collections.Counter()
        for s in sides:
            for c in map(tuple, cells(feats(g, s)[mask])): cnt[c] += 1
        blur = collections.defaultdict(float)
        for c, n in cnt.items():
            for o in offs:
                blur[(c[0]+o[0], c[1]+o[1], c[2]+o[2], c[3]+o[3])] += n * 0.5 ** sum(abs(x) for x in o)
        out[g] = (cnt, blur)
    return out
def dens(tab, F):
    return np.array([tab.get(tuple(c), 0.0) for c in cells(F)])
def quant(tabs, mask):
    res = {}
    for g in tabs:
        sides = ["_l", "_r"] if g != "spine" else [""]
        d = np.concatenate([dens(tabs[g][1], feats(g, s)[mask]) for s in sides])
        res[g] = np.sort(d)
    return res
hold_every = int(sys.argv[3]) if len(sys.argv) > 3 else 7
ufiles = sorted(set(files))
hold = set(ufiles[::hold_every])
fa = np.array(files)
is_hold = np.isin(fa, list(hold))
# held-out check: statistic from the other clips, scored on the held-out clips' frames
tr = build(~is_hold)
qs = {g: np.sort(np.concatenate([dens(tr[g][1], feats(g, s)[~is_hold]) for s in (["_l", "_r"] if g != "spine" else [""])])) for g in tr}
def pct(q, d): return 0.0 if d <= 0 else 100.0 * np.searchsorted(q, d, side="right") / len(q)
for thr in (1.0, 2.0, 5.0):
    flagged = 0
    for i in np.where(is_hold)[0]:
        m = np.zeros(len(X), bool); m[i] = True
        worst = 100.0
        for g in tr:
            for s in (["_l", "_r"] if g != "spine" else [""]):
                worst = min(worst, pct(qs[g], dens(tr[g][1], feats(g, s)[m])[0]))
        flagged += worst < thr
    print("held-out clips %s: frames %d, flagged below %.0f%%: %d = %.1f%%" % (sorted(hold), is_hold.sum(), thr, flagged, 100.0 * flagged / is_hold.sum()), flush=True)
# final statistic from every clip
allm = np.ones(len(X), bool)
tabs = build(allm)
qq = quant(tabs, allm)
groups = {}
for g in tabs:
    q = qq[g]
    ql = [float(q[min(len(q) - 1, int(i * len(q) / 200))]) for i in range(200)]
    cells_out = {"%d,%d,%d,%d" % c: round(v, 2) for c, v in tabs[g][1].items() if v >= 0.5}
    groups[g] = {"cells": cells_out, "q": [round(v, 2) for v in ql]}
# representative real poses: k-means medoids on the 21 joints (pelvis left out), angles rounded to 2 deg
pj = [j for j in J if j != "pelvis"]
V = np.concatenate([A(j) for j in pj], 1)
rng = np.random.default_rng(48)
sub = V[rng.choice(len(V), min(len(V), 6000), replace=False)]
K = 300
C = sub[rng.choice(len(sub), K, replace=False)]
for it in range(12):
    d = ((sub[:, None, :] - C[None, :, :]) ** 2).sum(2)
    lab = d.argmin(1)
    for k in range(K):
        if (lab == k).any(): C[k] = sub[lab == k].mean(0)
d = ((V[:, None, :] - C[None, :, :]) ** 2).sum(2) if len(V) < 20000 else None
med = []
for k in range(K):
    dk = ((V - C[k]) ** 2).sum(1)
    med.append(int(dk.argmin()))
med = sorted(set(med))
poses = [[int(round(x / 2.0)) for x in V[i]] for i in med]
out = {"source": "CMU Graphics Lab Motion Capture Database, mocap.cs.cmu.edu (free for all uses; see data_gen/README.md)", "bin": BIN,
       "frames": int(len(X)), "clips": len(ufiles), "joints": pj,
       "groups": groups, "poses": {"step": 2.0, "joints": pj, "rows": poses}}
json.dump(out, open(sys.argv[2], "w"), separators=(",", ":"))
print("frames", len(X), "clips", len(ufiles), "poses", len(poses), {g: len(groups[g]["cells"]) for g in groups})
