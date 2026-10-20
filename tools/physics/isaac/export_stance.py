"""Export the 'ready' stance (target hinge angles, gains, limits, rest pelvis height) from the MuJoCo Kine model to
D:/kine-physics/stance.npz so the Isaac env needs no scenes/ access. Read only on scenes/hit_react.json."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import sim  # noqa: E402

h = sim.Humanoid()
d = h.d
np.savez("D:/kine-physics/stance.npz", names=np.array(h.hname), target=h.target, kp=h.kp, kv=h.kv, tmax=h.tmax,
         lo=h.m.jnt_range[h.hid, 0], hi=h.m.jnt_range[h.hid, 1], pelvis_y=float(d.qpos[1]), mass=h.M,
         com_h=float(h.com()[1]), head_y=float(d.xpos[h.bid["head"]][1]))
print("saved", len(h.hname), "hinges; pelvis y", d.qpos[1], "head y", d.xpos[h.bid["head"]][1], "COM h", h.com()[1])
print("kv range", h.kv.min(), h.kv.max())
