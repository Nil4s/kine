"""I2: ONE struck-fighter reaction from a job file, for the app's "React to the hit (physics)" command.
  python tools/physics/react.py <job.json>        (plain python, NOT -I: it imports its neighbours kine_mjcf / sim / export)
job.json: {"pose": a Kine pose dict (Body.to_dict) = the struck fighter's pose at the contact, "body": the MuJoCo body that is hit,
           "J": impulse N s (horizontal part), "J_v": its vertical part (+ up; default 0), "dir_deg": direction of the push in the fighter's own frame (0 = forward +z, 90 = his
           left +x), "secs": length to record, "settle": s of stance before the hit, "out_bvh", "out_report", "scene_path": where
           to write the one-card pose scene sim.Humanoid reads its stance from}
The stance targets are the contact pose's joint angles (sim.Humanoid reads them from a scene card); the root starts with the pelvis's
orientation at the contact (pose["joints"]["pelvis"]["G"]: its yaw and lean), put on the floor at the model's own place (the app
adds the pelvis offset back). The hit is sim.Humanoid.hit(body, J, dir_deg) plus the vertical part: a force (J_h, J_v) / 50 ms on that body. Writes the BVH (export.py's writer: Kine names)
and the report: peak head / trunk rotation (deg) in the first 0.6 s, the head's angular speed peak, steps taken, whether it fell."""
import json
import os
import sys

import mujoco
import numpy as np
from scipy.spatial.transform import Rotation as R

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export as EX  # noqa: E402
import kine_mjcf as KM  # noqa: E402
import sim  # noqa: E402


def rot_deg(q0, q1):
    """angle (deg) of the rotation taking quaternion q0 (w,x,y,z) to q1"""
    a = R.from_quat([q0[1], q0[2], q0[3], q0[0]])
    b = R.from_quat([q1[1], q1[2], q1[3], q1[0]])
    return float(np.degrees((a.inv() * b).magnitude()))


def main(job_path):
    job = json.load(open(job_path))
    card = {"scene": "i2_pose", "fps": 30, "cards": [{"name": "contact", "pose": job["pose"], "move": -1.0, "hold": 1.0}]}
    json.dump(card, open(job["scene_path"], "w"))
    h = sim.Humanoid(scene=job["scene_path"])
    qg = job["pose"]["joints"]["pelvis"]["G"]            # Kine (x, y, z, w) -> MuJoCo (w, x, y, z)
    h.root_q = [float(qg[3]), float(qg[0]), float(qg[1]), float(qg[2])]
    h.reset()
    h.init_refs()
    up0 = R.from_quat([h.root_q[1], h.root_q[2], h.root_q[3], h.root_q[0]]).apply([0, 1, 0])
    fw0 = R.from_quat([h.root_q[1], h.root_q[2], h.root_q[3], h.root_q[0]]).apply([0, 0, 1])
    lean0 = float(np.degrees(np.arccos(np.clip(up0[1], -1, 1))))        # the pelvis's tilt from vertical at the start
    lean_signed0 = float(h.trunk_lean_deg())          # signed, + forward (sim.py's own reading)
    yaw0 = float(np.degrees(np.arctan2(fw0[0], fw0[2])))
    lean_trunk0 = float(np.degrees(np.arccos(np.clip(np.dot(h.d.xpos[h.bid["neck_01"]] - h.d.xpos[h.bid["pelvis"]], [0, 1, 0]) / np.linalg.norm(h.d.xpos[h.bid["neck_01"]] - h.d.xpos[h.bid["pelvis"]]), -1, 1))))
    for _ in range(int(job.get("settle", 0.3) / h.dt)):
        h.step()
    _, order = EX.hierarchy()
    bhead, btorso = h.bid["head"], h.bid["spine_03"]
    q_head0, q_tor0 = h.d.xquat[bhead].copy(), h.d.xquat[btorso].copy()
    p0 = h.d.xpos[h.bid["pelvis"]].copy()
    h.hit(job["body"], float(job["J"]), float(job["dir_deg"]))
    h.hit_f[1] = float(job.get("J_v", 0.0)) / 0.05          # the full 3D impulse: sim.hit has only the floor-plane part
    head_y0 = float(h.d.xipos[bhead][1])          # the head's centre of mass
    head_up = 0.0
    head_dy = []
    n = int(float(job.get("secs", 1.6)) * 60)
    sub = int(round(1 / 60 / h.dt))
    rows, head_rot, tor_rot, head_w = [], [], [], []
    qprev = h.d.xquat[bhead].copy()
    for _ in range(n):
        for _ in range(sub):
            h.step()
        rows.append(EX.frame_row(h, order))
        if len(rows) <= 18:                                  # first 0.3 s
            dy = float(h.d.xipos[bhead][1]) - head_y0
            head_dy.append(dy)
            head_up = max(head_up, dy)
        head_rot.append(rot_deg(q_head0, h.d.xquat[bhead]))
        tor_rot.append(rot_deg(q_tor0, h.d.xquat[btorso]))
        head_w.append(np.radians(rot_deg(qprev, h.d.xquat[bhead])) * 60.0)
        qprev = h.d.xquat[bhead].copy()
    k = 36   # 0.6 s
    EX.write_bvh(job["out_bvh"], rows)
    rep = {"ok": True, "frames": len(rows), "head_rot_deg": float(max(head_rot[:k])), "torso_rot_deg": float(max(tor_rot[:k])),
           "head_w_rad_s": float(max(head_w[:k])), "steps": int(h.step_count), "fell": bool(h.fallen()),
           "pelvis_move_m": float(np.linalg.norm((h.d.xpos[h.bid["pelvis"]] - p0)[[0, 2]])), "p0": [float(p0[0]), float(p0[1]), float(p0[2])],
           "body": job["body"], "J": float(job["J"]), "J_v": float(job.get("J_v", 0.0)), "lean0_deg": lean0, "trunk_lean0_deg": lean_trunk0, "trunk_lean_signed0": lean_signed0, "yaw0_deg": yaw0, "head_up_m": head_up, "head_dy_mean_m": float(np.mean(head_dy)), "head_dy_min_m": float(min(head_dy)), "dir_deg": float(job["dir_deg"])}
    json.dump(rep, open(job["out_report"], "w"))
    print(json.dumps(rep))


if __name__ == "__main__":
    main(sys.argv[1])
