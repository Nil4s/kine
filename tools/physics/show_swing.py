"""Interactive viewer: the blue attacker plays Kine's own swings (swing_fore, swing_back, strike_legs) with a 0.9 kg bat; the brown
defender (stance + XCoM balance + stepping) takes the hits. A red sphere flashes at the contact point with the impulse (N s) that
came out of the contact; a hit plays at quarter speed for 0.4 s. A fall lies 2.5 s, then the same clip restarts.
  python tools/physics/show_swing.py        (cameras: 'duel3' default; press [ ] in the viewer to cycle fixed cameras)"""
import os
import sys
import time

import mujoco
import mujoco.viewer
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import swing  # noqa: E402

CLIPS = ["swing_fore", "swing_back", "strike_legs"]
LIE = 2.5
SLOW = 0.4


def _sphere(scn, p, r, rgba):
    if scn.ngeom >= scn.maxgeom:
        return
    g = scn.geoms[scn.ngeom]
    mujoco.mjv_initGeom(g, mujoco.mjtGeom.mjGEOM_SPHERE, np.array([r, 0, 0]), np.array(p, dtype=float), np.eye(3).reshape(-1), np.array(rgba, dtype=np.float32))
    scn.ngeom += 1


def main():
    duels = {}
    ci = 0
    cur = None

    def load(i):
        c = CLIPS[i % len(CLIPS)]
        if c not in duels:
            duels[c] = swing.Duel(c, weapon=True)
        h = duels[c]
        h.reset(); h.init_refs()
        h.rec_on = True
        h.log_c = []
        return h

    h = load(ci)
    mark = None          # (sim time, point, impulse, label)
    acc = None           # running pulse [t_last, J vec, point, body votes]
    fell_at = None
    t_end = h.clip.T + swing.LEAD + 1.0
    with mujoco.viewer.launch_passive(h.m, h.d) as v:
        v.cam.type = mujoco.mjtCamera.mjCAMERA_FIXED
        v.cam.fixedcamid = h.m.camera("duel3").id
        while v.is_running():
            t0 = time.time()
            for _ in range(8):
                h.step()
            # contact bookkeeping: build the running pulse, flash when it closes
            for (t, F, pos, per) in h.log_c:
                n = np.linalg.norm(F)
                if n > 5:
                    if acc is None:
                        acc = [t, np.zeros(3), pos.copy(), {}, t]
                    acc[1] += F * swing.PHYS_DT
                    acc[2] = pos
                    acc[4] = t
                    for b, f in per.items():
                        acc[3][b] = acc[3].get(b, 0.0) + f
                    mark = (h.d.time, pos.copy(), float(np.linalg.norm(acc[1])), h.bname(max(acc[3], key=acc[3].get)))
                elif acc is not None and t - acc[4] > 0.006:
                    print(f"{h.clip.name}: {mark[3]} {mark[2]:.1f} N s", flush=True)
                    acc = None
            h.log_c = []
            if fell_at is None and h.fallen():
                fell_at = h.d.time
            if (fell_at is not None and h.d.time - fell_at > LIE) or h.d.time > t_end + (LIE if fell_at is None else 0):
                ci += 1
                h = load(ci)
                mark, acc, fell_at = None, None, None
                t_end = h.clip.T + swing.LEAD + 1.0
            with v.lock():
                v.user_scn.ngeom = 0
                if mark is not None and h.d.time - mark[0] < 0.8:
                    _sphere(v.user_scn, mark[1], 0.05 + 0.0015 * mark[2], [1, 0.1, 0.1, 0.8])
            try:
                txt = f"{h.clip.name}" + (f"   hit: {mark[3]}  {mark[2]:.1f} N s" if mark is not None else "") + ("   FELL" if fell_at is not None else "")
                v.set_texts([(mujoco.mjtFontScale.mjFONTSCALE_150, mujoco.mjtGridPos.mjGRID_TOPLEFT, txt, "")])
            except Exception:
                pass
            v.sync()
            slow = mark is not None and h.d.time - mark[0] < SLOW
            wait = (1 / 60) * (4.0 if slow else 1.0) - (time.time() - t0)
            if wait > 0:
                time.sleep(wait)


if __name__ == "__main__":
    main()
