"""Open the interactive MuJoCo viewer on the Kine humanoid: it stands in its fighting stance and gets hit every 3.5 s.
The hits get harder in a cycle (20, 30, 40, 55 N s) and rotate over head, chest, stomach and shoulder, so you see it
absorb a light one, lean hard, start a step, and fall. A red arrow shows where and which way each hit lands; the second
after each hit plays at half speed. A fall lies on the floor for 2.5 s before it stands up again.
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
STRENGTH = [20.0, 30.0, 40.0, 55.0]   # N s: absorbed in place, big lean, a step starts (~34), a fall
EVERY = 3.5
SLOW = 1.0                            # s of half speed after each hit
LIE = 2.5                             # s a fall stays on the floor


def _arrow(scn, p_from, p_to, rgba):
    """One red arrow in the viewer's user scene (cleared every frame)."""
    if scn.ngeom >= scn.maxgeom:
        return
    g = scn.geoms[scn.ngeom]
    mujoco.mjv_initGeom(g, mujoco.mjtGeom.mjGEOM_ARROW, np.zeros(3), np.zeros(3), np.zeros(9), np.array(rgba, dtype=np.float32))
    mujoco.mjv_connector(g, mujoco.mjtGeom.mjGEOM_ARROW, 0.03, np.array(p_from), np.array(p_to))
    scn.ngeom += 1


def main():
    h = sim.make(stepping=True)
    hits = 0
    last = None          # (time, body id, direction unit vector, label)
    fell_at = None
    with mujoco.viewer.launch_passive(h.m, h.d) as v:
        v.cam.type = mujoco.mjtCamera.mjCAMERA_FIXED   # the free camera is Z-up, Kine is Y-up; fixed camera 'view' follows the COM
        v.cam.fixedcamid = h.m.camera('view').id
        next_hit = 2.0
        while v.is_running():
            t0 = time.time()
            for _ in range(int(1 / 60 / h.dt)):
                h.step()
            if fell_at is None and h.d.time >= next_hit:
                k = hits % 4
                J = STRENGTH[hits % len(STRENGTH)]
                dr = (hits * 70) % 360
                h.hit(BODIES[k], J, dr)
                f = np.array(h.hit_f, dtype=float)
                u = f / (np.linalg.norm(f) + 1e-9)
                last = (h.d.time, h.hit_body, u, f"hit {hits + 1}: {NAMES[k]} {J:.0f} N s")
                print(last[3], f"direction {dr} deg", flush=True)
                hits += 1
                next_hit += EVERY
            if fell_at is None and h.fallen():
                fell_at = h.d.time
                print("  fell", flush=True)
            if fell_at is not None and h.d.time - fell_at > LIE:
                h.reset(); h.init_refs()
                fell_at, last = None, None
                next_hit = h.d.time + 2.0
            with v.lock():
                v.user_scn.ngeom = 0
                if last is not None and h.d.time - last[0] < 0.8:
                    p = h.d.xpos[last[1]]
                    _arrow(v.user_scn, p - 0.45 * last[2], p - 0.05 * last[2], [1, 0.1, 0.1, 1])
            try:
                txt = last[3] if last is not None else "standing"
                v.set_texts([(mujoco.mjtFontScale.mjFONTSCALE_150, mujoco.mjtGridPos.mjGRID_TOPLEFT,
                              txt + ("   FELL" if fell_at is not None else ""), "Ctrl + right-drag to push it yourself")])
            except Exception:
                pass    # older viewers have no text overlay
            v.sync()
            slow = last is not None and h.d.time - last[0] < SLOW
            wait = (1 / 60) * (2.0 if slow else 1.0) - (time.time() - t0)
            if wait > 0:
                time.sleep(wait)


if __name__ == "__main__":
    main()
