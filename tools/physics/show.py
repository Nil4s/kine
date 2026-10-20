"""Open the interactive MuJoCo viewer on the Kine humanoid: it stands, and gets hit every 3 s
(head, chest, stomach, shoulder in turn; light / hard alternating; direction rotates). Reset if it falls.
  python tools/physics/show.py          (one command to open it again)
In the viewer: double-click a body to select it, Ctrl + right-drag pushes it with a force; Tab/F1 help; Space pauses."""
import os
import sys
import time

import mujoco
import mujoco.viewer
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sim  # noqa: E402

BODIES = ["head", "spine_03", "spine_01", "clavicle_r"]
NAMES = ["head", "chest", "stomach", "shoulder"]
LIGHT, HARD = 12.0, 38.0     # N s


def main():
    h = sim.make(stepping=True)
    hits = 0
    with mujoco.viewer.launch_passive(h.m, h.d) as v:
        v.cam.type = mujoco.mjtCamera.mjCAMERA_FIXED   # the free camera is Z-up, Kine is Y-up; fixed camera 'view' follows the COM
        v.cam.fixedcamid = h.m.camera('view').id
        next_hit = 2.0
        t_wall = time.time()
        while v.is_running():
            for _ in range(int(1 / 60 / h.dt)):
                h.step()
                # Ctrl+right-drag in the viewer writes d.xfrc_applied; keep it (sim.step clears it each step unless we re-add)
            if h.d.time >= next_hit:
                k = hits % 4
                J = LIGHT if (hits // 4) % 2 == 0 else HARD
                dr = (hits * 70) % 360
                h.hit(BODIES[k], J, dr)
                print(f"hit {hits}: {NAMES[k]}, {J:.0f} N s, direction {dr} deg")
                hits += 1
                next_hit += 3.0
            if h.fallen():
                h.reset(); h.init_refs(); next_hit = h.d.time + 2.0
            v.sync()
            dt = h.dt * int(1 / 60 / h.dt) - (time.time() - t_wall)
            t_wall = time.time()
            if dt > 0:
                time.sleep(dt)


if __name__ == "__main__":
    main()
