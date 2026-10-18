"""Build refs/gait_band.json: the real-human band for the curve editor (round 43, GATES YY7).

Source: Fukuchi CA, Fukuchi RK, Duarte M (2018) "A public data set of overground and treadmill walking kinematics and
kinetics in healthy individuals", PeerJ 6:e4640, data DOI 10.6084/m9.figshare.5722711 (CC BY 4.0). 42 healthy adults,
overground at their COMFORTABLE speed (files WBDS??walkOCang.txt in WBDSascii.zip), joint angles time-normalised to 101
points of the gait cycle (0 = right heel strike). The sagittal angle is the Z column for hip, knee and ankle (picked as
the axis with the largest swing; its mean shape is the classic one: hip +31 at heel strike, knee peak 63 at 73 %,
ankle +12.5 at 40 %). Right side. Positive = hip flexion, knee flexion, ankle dorsiflexion.

    python tools/make_gait_band.py <folder with the WBDS??walkOCang.txt files>

Only the 42 *walkOCang.txt files are needed (tools: read them out of the zip by HTTP range requests; ~1.5 MB of 687).
"""
import glob
import json
import os
import statistics as st
import sys

JOINTS = {"hip": "RHipAngleZ", "knee": "RKneeAngleZ", "ankle": "RAnkleAngleZ"}


def main(folder: str) -> None:
    files = sorted(glob.glob(os.path.join(folder, "WBDS*walkOCang.txt")))
    rows_of = []
    for f in files:
        lines = open(f).read().strip().split("\n")
        head = lines[0].split("\t")
        rows = [list(map(float, ln.split("\t"))) for ln in lines[1:]]
        assert len(rows) == 101, (f, len(rows))
        rows_of.append((head, rows))
    out = {
        "source": "Fukuchi, Fukuchi & Duarte 2018, PeerJ 6:e4640; data doi:10.6084/m9.figshare.5722711 (CC BY 4.0)",
        "what": "sagittal joint angle (deg) over one gait cycle, 101 points (0 = heel strike), overground, comfortable speed, right side; + = hip flexion / knee flexion / ankle dorsiflexion",
        "n": len(files),
        "subjects": [os.path.basename(f)[:6] for f in files],
        "joints": {},
    }
    for j, col in JOINTS.items():
        mean, sd = [], []
        for k in range(101):
            v = [rows[k][head.index(col)] for head, rows in rows_of]
            mean.append(round(st.mean(v), 3))
            sd.append(round(st.stdev(v), 3))
        out["joints"][j] = {"mean": mean, "sd": sd}
    here = os.path.dirname(os.path.abspath(__file__))
    dst = os.path.join(here, "..", "refs", "gait_band.json")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1)
    for j in out["joints"]:
        m = out["joints"][j]["mean"]
        print(j, "min %.1f at %d, max %.1f at %d" % (min(m), m.index(min(m)), max(m), m.index(max(m))))
    print("wrote", os.path.normpath(dst), "n =", out["n"])


if __name__ == "__main__":
    main(sys.argv[1])
