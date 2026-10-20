"""Record hit reactions -> Kine-named BVH (BvhImport reads it exactly) + a contact sheet PNG.
  python tools/physics/export.py [out_dir]
BVH form = scripts/bvh_export.gd: Kine's joint names and rest offsets, channels Zrotation Xrotation Yrotation (M = Rz Rx Ry),
the root with 6 channels (metres), per joint rotation A with G[j] = G[parent] A[j] in rest character axes. MuJoCo bodies are
world-aligned at rest, so A = R_parent^-1 R_child straight from d.xquat. Fingers and the toe 'ball' have no MuJoCo body: zero rotation."""
import json
import os
import sys

import mujoco
import numpy as np
from scipy.spatial.transform import Rotation as R

import kine_mjcf as KM
import sim

OUT = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\Nick\.claude\jobs\9afc22db\tmp"
SK = json.load(open(os.path.join(KM.ROOT, "data", "skeleton.json")))["joints"]
ORDER = list(SK.keys())


def hierarchy():
    kids = {j: [] for j in ORDER}
    for j in ORDER:
        if SK[j]["parent"]:
            kids[SK[j]["parent"]].append(j)
    lines, order = ["HIERARCHY"], []

    def w(j, depth):
        pad = "\t" * depth
        p = np.array(SK[j]["pos"]) - (np.array(SK[SK[j]["parent"]]["pos"]) if SK[j]["parent"] else 0)
        lines.append(f"{pad}{'ROOT' if depth == 0 else 'JOINT'} {j}")
        lines.append(pad + "{")
        lines.append(f"{pad}\tOFFSET {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}" if depth else f"{pad}\tOFFSET 0.000000 0.000000 0.000000")
        lines.append(pad + "\tCHANNELS " + ("6 Xposition Yposition Zposition " if depth == 0 else "3 ") + "Zrotation Xrotation Yrotation")
        order.append(j)
        if not kids[j]:
            e = np.array(SK[j]["end"]) - np.array(SK[j]["pos"]) if "end" in SK[j] else np.array([0, 0.05, 0])
            lines.extend([pad + "\tEnd Site", pad + "\t{", f"{pad}\t\tOFFSET {e[0]:.6f} {e[1]:.6f} {e[2]:.6f}", pad + "\t}"])
        for k in kids[j]:
            w(k, depth + 1)
        lines.append(pad + "}")

    w("pelvis", 0)
    return lines, order


def frame_row(h, order):
    d, m = h.d, h.m
    row = []
    wq = {}
    for j in KM.JOINTS:
        q = d.xquat[h.bid[j]]
        wq[j] = R.from_quat([q[1], q[2], q[3], q[0]])
    for j in order:
        if j == "pelvis":
            p = d.xpos[h.bid["pelvis"]]
            row += [p[0], p[1], p[2]]
        if j in wq:
            par = SK[j]["parent"]
            A = wq[j] if not par else wq[par].inv() * wq[j]
        else:
            A = R.identity()
        z, x, y = A.as_euler("ZXY", degrees=True)
        row += [z, x, y]
    return row


def record(body, J, dr, secs=2.0, settle=1.0, stepping=True):
    h = sim.make(stepping=stepping)
    for _ in range(int(settle / h.dt)):
        h.step()
    _, order = hierarchy()
    rows, snaps = [], []
    h.hit(body, J, dr)
    n = int(secs * 60)
    sub = int(round(1 / 60 / h.dt))
    r = mujoco.Renderer(h.m, 360, 480)
    cam = mujoco.MjvCamera()
    cam.azimuth, cam.elevation, cam.distance = 135, -8, 4.0
    for i in range(n):
        for _ in range(sub):
            h.step()
        rows.append(frame_row(h, order))
        if i in (0, 8, 18, 36, 70, 110):
            cam.lookat[:] = [h.d.xpos[1][0], 0.95, h.d.xpos[1][2]]
            r.update_scene(h.d, camera='view')
            snaps.append(r.render().copy())
    return rows, snaps, h


def write_bvh(path, rows):
    lines, _ = hierarchy()
    lines += ["MOTION", f"Frames: {len(rows)}", "Frame Time: 0.016666667"]
    lines += [" ".join(f"{v:.5f}" for v in r) for r in rows]
    open(path, "w").write("\n".join(lines) + "\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    from PIL import Image, ImageDraw
    hits = [("chest", "spine_03", 24.0, 0, "chest 24 N s from behind"),
            ("head", "head", 14.0, 90, "head 14 N s from the right"),
            ("stomach", "spine_01", 11.0, 180, "stomach 11 N s from the front"),
            ("fall", "spine_03", 40.0, 0, "chest 40 N s from behind: steps twice, then falls")]
    sheet = []
    for name, body, J, dr, label in hits:
        rows, snaps, h = record(body, J, dr)
        p = os.path.join(OUT, f"hit_{name}.bvh")
        write_bvh(p, rows)
        print(f"{p}: {len(rows)} frames, steps={h.step_count}, fell={h.fallen()}")
        sheet.append((label, snaps))
    W, H = 480, 360
    img = Image.new("RGB", (W * 6, (H + 24) * len(hits)), (20, 20, 24))
    dr = ImageDraw.Draw(img)
    times = ["t=0", "0.13 s", "0.30 s", "0.60 s", "1.17 s", "1.83 s"]
    for ri, (label, snaps) in enumerate(sheet):
        for ci, s in enumerate(snaps):
            img.paste(Image.fromarray(s), (ci * W, ri * (H + 24) + 24))
        dr.text((6, ri * (H + 24) + 6), label, fill=(255, 255, 255))
        for ci, t in enumerate(times):
            dr.text((ci * W + 6 + 300, ri * (H + 24) + 6), t, fill=(200, 200, 120))
    img.save(os.path.join(OUT, "hitmj.png"))
    print("sheet", os.path.join(OUT, "hitmj.png"))


if __name__ == "__main__":
    main()
