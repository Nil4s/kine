"""One defender reaction per clip -> Kine BVH (same writer as export.py) + one contact sheet.
  python tools/physics/export_swing.py [out_dir]"""
import os
import sys

import mujoco
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export as EX  # noqa: E402
import swing  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else swing.TMP
CLIPS = ["swing_fore", "swing_back", "strike_legs", "combo3"]


def main():
    os.makedirs(OUT, exist_ok=True)
    _, order = EX.hierarchy()
    rows_img = []
    for c in CLIPS:
        r = swing.run(c, weapon=True)
        h, st = r["h"], r["states"]
        p = r["pulses"][r["dom"]]
        t_hit = p["t0"]
        sel = [s for s in st if s[0] >= t_hit - 0.4]
        rows = []
        for t, q in sel:
            h.d.qpos[:] = q
            mujoco.mj_kinematics(h.m, h.d)
            rows.append(EX.frame_row(h, order))
        path = os.path.join(OUT, f"swing_{c}.bvh")
        EX.write_bvh(path, rows)
        print(f"{path}: {len(rows)} frames, hit {p['body']} {p['impulse_Ns']:.1f} N s, fell={r['fell']}", flush=True)
        ren = mujoco.Renderer(h.m, 360, 480)
        ts = np.array([s[0] for s in st])
        row = []
        for dt in (-0.2, -0.04, 0.0, 0.04, 0.2, 0.7):
            k = int(np.argmin(np.abs(ts - (t_hit + dt))))
            h.d.qpos[:] = st[k][1]
            mujoco.mj_forward(h.m, h.d)
            ren.update_scene(h.d, camera="duel3")
            row.append(ren.render().copy())
        rows_img.append((f"{c}: {p['body']} {p['impulse_Ns']:.0f} N s, peak {p['peak_N']:.0f} N", row))
    W, H = 480, 360
    img = Image.new("RGB", (W * 6, (H + 24) * len(rows_img)), (20, 20, 24))
    dr = ImageDraw.Draw(img)
    for ri, (label, row) in enumerate(rows_img):
        dr.text((6, ri * (H + 24) + 6), label, fill=(255, 255, 255))
        for ci, s in enumerate(row):
            img.paste(Image.fromarray(s), (ci * W, ri * (H + 24) + 24))
            dr.text((ci * W + 400, ri * (H + 24) + 6), ["-0.20 s", "-0.04", "impact", "+0.04", "+0.20", "+0.70"][ci], fill=(200, 200, 120))
    img.save(os.path.join(OUT, "swingmj.png"))
    print("sheet", os.path.join(OUT, "swingmj.png"))


if __name__ == "__main__":
    main()
