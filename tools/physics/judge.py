"""The physical judge of a Kine clip ("Make it physical", ROADMAP Innovations I1).

  python tools/physics/judge.py clip.json out.json [--progress progress.txt]

clip.json = what tools/physics/dump_clip.gd (or the app's own exporter, MakePhysical.clip_dict) writes: {"fps", "frames":[{"t",
"pelvis":[x,y,z], "ang":{joint:[bend,side,twist] deg}}]}. The 75 kg human-scale body of kine_mjcf.py (de Leva 1996 masses, Kine's
joint limits, per-joint torque limits TAU_MAX) is driven at 500 Hz to TRACK the clip:
  * every hinge: PD toward the clip's joint target (+ its velocity), gravity / Coriolis feed-forward (qfrc_bias), torque clipped at
    1.0 x the human limit. The torque RATIO reported is the UNclipped command over the limit (what the clip would ask of a human).
  * the root is NOT kinematic: a free body on box feet and a floor (friction 1.0). The only help is a bounded RESIDUAL wrench on the
    pelvis (horizontal force <= 0.10 body weight, orientation torque <= 60 N m: residual force control, Yuan and Kitani 2020,
    arXiv 2006.07364) which keeps the heading and the slow drift of a walk; it cannot hold weight (no vertical force).
  * a fall (pelvis under 55 % of its clip height, or the trunk > 55 deg off vertical) is recorded and the body is re-seated on the clip
    pose so one fall does not paint the rest of the clip.
Per frame: tracking error (RMS hinge deg, pelvis cm), foot slide (cm since the foot landed), balance margin (cm, CoM projected on the
convex hull of the feet in contact, >0 inside; Hof 2005 J Biomech 38:1 puts the dynamic limit on the XCoM, reported too), torque ratio,
fell. The CLIP itself is also checked kinematically for flight: both feet off the floor must follow gravity (CoM acceleration -9.81 +- 40 %,
quadratic fit over the run) or it is "airborne" = impossible (a jump needs momentum; a body cannot hover).
Output: per-frame table, red spans with reasons, and the physically-tracked trajectory (the same joint form as the clip) = the physical version.
Never writes outside the two paths it is given."""
import json
import os
import sys

import mujoco
import numpy as np
from scipy.spatial import ConvexHull
from scipy.spatial.transform import Rotation as R

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kine_mjcf as KM  # noqa: E402

G = 9.81
KPJ = {"spine": 700, "neck": 60, "head": 40, "clavicle": 200, "upperarm": 260, "lowerarm": 150, "hand": 30,
       "thigh": 2600, "calf": 2600, "foot": 1600}
# kine_mjcf's TAU_MAX gives every spine hinge 150 N m, but in this body spine_01 alone carries the whole torso (about 150 N m static
# in a ready stance), so a 150 N m cap fails a standing person. Maximal isometric trunk extension of healthy men is of the order of
# 200-300 N m (typical lumbar dynamometry values, not re-fetched here), so the lumbar joints get 250 / 200 / 150 for the judge.
# the ankle: a walk's push-off asks 1.6 N m/kg (Winter 1995; 120 N m for 75 kg) and healthy men's maximal plantarflexion is about 2-3 N m/kg
# (dynamometry, typical values, not re-fetched), so the judge's ankle limit is 190 N m, not the 130 N m of the stance controller.
TAU_FOOT = 190.0
TAU_SPINE = {"spine_01": 250.0, "spine_02": 200.0, "spine_03": 150.0}
ASSIST_FRAC = 0.60     # horizontal residual force cap, x body weight
ASSIST_UP = 0.10       # vertical residual cap, x body weight: a trim, it cannot hold the body up (a hover must fall in the physical version)
ASSIST_TORQUE = 300.0
SOFT = 4.0   # the wrench is MEASURED against its cap but may exceed it up to SOFT x cap, so one saturated moment does not throw the tracker off the clip (the red criterion reads the share of the cap, see spans_of)
KROOT, CROOT = 12000.0, 1500.0   # the residual is a stiff spring on the root so it shows the force the motion needs (a soft one drifts instead)
CONTACT_H = 0.015     # m: a foot corner under this is on the floor
STANCE_H = 0.02       # m: a true stance foot is within 2 cm of the floor ...
STANCE_V = 0.3        # m/s: ... and the clip's own foot moves slower than this
SAT_FRAC = 0.8        # the pelvis residual wrench above this share of its cap ...
SAT_S = 0.1           # ... for longer than this (s) = the motion needs an outside force
TAU_S = 0.05          # a joint over its limit for longer than this (s); a single touch-down step is shorter
FRICTION = 1.0        # shoe-floor friction coefficient the ground force may use
SLIDE_BAR = 2.0       # cm
TAU_BAR = 1.0         # x the human limit
FLIGHT_CLEAR = 0.03   # m: both feet higher than this = flight


def hull_margin(pts, p):
    """signed distance (m) of p from the convex hull of pts (xz); > 0 inside"""
    pts = np.asarray(pts)
    if len(pts) < 3:
        return -float(np.min(np.linalg.norm(pts - p, axis=1)))
    try:
        hl = ConvexHull(pts)
    except Exception:
        return -float(np.min(np.linalg.norm(pts - p, axis=1)))
    eq = hl.equations   # n.x + c <= 0 inside
    return float(-np.max(eq[:, :2] @ p + eq[:, 2]))



def clamp_hull(pts, p):
    """the point of the convex hull of pts (xz) nearest to p"""
    pts = np.asarray(pts)
    if len(pts) < 3:
        return pts[np.argmin(np.linalg.norm(pts - p, axis=1))]
    try:
        hl = ConvexHull(pts)
    except Exception:
        return pts[np.argmin(np.linalg.norm(pts - p, axis=1))]
    if np.all(hl.equations[:, :2] @ p + hl.equations[:, 2] <= 0):
        return p
    best, bd = p, 1e9
    v = pts[hl.vertices]
    for i in range(len(v)):
        a, b = v[i], v[(i + 1) % len(v)]
        t = np.clip(np.dot(p - a, b - a) / max(np.dot(b - a, b - a), 1e-12), 0, 1)
        q = a + t * (b - a)
        dd = np.linalg.norm(q - p)
        if dd < bd:
            best, bd = q, dd
    return best


def newton_rot(fun, x0, iters=6, h=1e-4):
    """solve fun(x) = 0 for a 3-vector residual (a rotation vector) by Gauss-Newton with a numerical Jacobian (scipy's
    least_squares costs 20 ms a call; this is 1-2 ms and converges in 2-3 steps from the starts used here)"""
    x = np.array(x0, float)
    for _ in range(iters):
        r = fun(x)
        if np.dot(r, r) < 1e-16:
            break
        J = np.empty((3, 3))
        for i in range(3):
            xi = x.copy()
            xi[i] += h
            J[:, i] = (fun(xi) - r) / h
        try:
            x = x - np.linalg.solve(J, r)
        except np.linalg.LinAlgError:
            break
    return x


class Judge:
    def __init__(self, clip):
        self.clip = clip
        self.fps = float(clip["fps"])
        self.fr = clip["frames"]
        xml, self.hinges, self.info, self.K = KM.build()
        self.m = mujoco.MjModel.from_xml_string(xml)
        self.d = mujoco.MjData(self.m)
        m = self.m
        self.dt = m.opt.timestep
        self.hid = [m.joint(h[0]).id for h in self.hinges]
        self.qadr = np.array([m.jnt_qposadr[i] for i in self.hid])
        self.dadr = np.array([m.jnt_dofadr[i] for i in self.hid])
        self.madr = np.array([m.dof_Madr[i] for i in self.dadr])
        self.kp = np.array([KPJ[KM._key(h[1])] for h in self.hinges], float)
        self.tmax = np.array([TAU_SPINE.get(h[1], TAU_FOOT if h[1].startswith('foot') else h[3]) for h in self.hinges], float)
        m.actuator_ctrlrange[:, 0] = -self.tmax
        m.actuator_ctrlrange[:, 1] = self.tmax
        self.lo = m.jnt_range[self.hid, 0]
        self.hi = m.jnt_range[self.hid, 1]
        self.bid = {j: m.body(j).id for j in KM.JOINTS}
        self.pel = self.bid["pelvis"]
        self.M = float(m.body_subtreemass[1])
        self.by_joint = {}
        for i, h in enumerate(self.hinges):
            self.by_joint.setdefault(h[1], []).append(i)
        self._cache = {}
        self._dense = np.zeros((m.nv, m.nv))
        self.tg = self._targets()

    # ------------------------------------------------------------ clip -> targets
    def _hinge_target(self, j, v):
        key = (j,) + tuple(round(float(x), 4) for x in v)
        if key not in self._cache:
            K = self.K
            A = K.compose(j, list(v))
            self._cache[key] = newton_rot(lambda th: (K.hinge_chain(j, th).inv() * A).as_rotvec(), np.radians(v))
        return self._cache[key]

    def _targets(self):
        """per frame: hinge targets (rad), root position, root quaternion (wxyz)"""
        out = []
        for f in self.fr:
            th = np.zeros(len(self.hinges))
            for j, idxs in self.by_joint.items():
                v = f["ang"].get(j, [0, 0, 0])
                h3 = self._hinge_target(j, v)
                for i in idxs:
                    th[i] = h3["baw".index(self.hinges[i][2])]
            th = np.clip(th, self.lo, self.hi)
            A = self.K.compose("pelvis", f["ang"].get("pelvis", [0, 0, 0]))
            q = A.as_quat()
            out.append((th, np.array(f["pelvis"], float), np.array([q[3], q[0], q[1], q[2]])))
        return out

    # ------------------------------------------------------------ sim helpers
    def corners(self, s):
        m, d = self.m, self.d
        gid = m.geom(f"foot_{s}_box").id
        h = m.geom_size[gid]
        Rm = d.geom_xmat[gid].reshape(3, 3)
        c = d.geom_xpos[gid]
        return np.array([c + Rm @ (np.array([sx, sy, sz]) * h) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])

    def feet_state(self):
        """contact flags, lowest height, and the xz points of the feet in contact"""
        res = {}
        for s in "lr":
            c = self.corners(s)
            res[s] = (float(c[:, 1].min()), c)
        return res

    def seat(self, k, drop_to_floor=True):
        d, m = self.d, self.m
        th, p, q = self.tg[k]
        d.qvel[:] = 0
        d.qpos[self.qadr] = th
        d.qpos[0:3] = p
        d.qpos[3:7] = q
        mujoco.mj_forward(m, d)
        if drop_to_floor:
            low = min(self.corners(s)[:, 1].min() for s in "lr")
            d.qpos[1] -= low
            mujoco.mj_forward(m, d)

    def clip_kin(self):
        """FK of every clip frame as posed: foot clearance (m, lowest corner of the higher foot) and CoM height"""
        clear, comy, comxz = [], [], []
        d, m = self.d, self.m
        for k in range(len(self.fr)):
            th, p, q = self.tg[k]
            d.qpos[self.qadr] = th
            d.qpos[0:3] = p
            d.qpos[3:7] = q
            mujoco.mj_forward(m, d)
            lo_l = self.corners("l")[:, 1].min()
            lo_r = self.corners("r")[:, 1].min()
            clear.append((lo_l, lo_r))
            c = d.subtree_com[1].copy()
            comy.append(c[1])
            comxz.append(c[[0, 2]])
        return np.array(clear), np.array(comy), np.array(comxz)

    def clip_slide(self):
        """the CLIP's own feet: per frame and foot the stance flag (lowest corner within STANCE_H of the clip floor AND the foot origin
        moving slower than STANCE_V m/s) and the horizontal travel (cm) of that foot since its stance began = the AUTHORED slide (skate)
        the clip carries by itself. Returns (stance[n][2] bool, travel[n][2] cm)"""
        d, m = self.d, self.m
        n = len(self.fr)
        fl = self.floor0
        low, pos = np.zeros((n, 2)), np.zeros((n, 2, 2))
        for k in range(n):
            th, p, q = self.tg[k]
            d.qpos[self.qadr] = th
            d.qpos[0:3] = p
            d.qpos[3:7] = q
            mujoco.mj_forward(m, d)
            for i, s_ in enumerate("lr"):
                low[k, i] = self.corners(s_)[:, 1].min() - fl
                pos[k, i] = d.xpos[self.bid["foot_" + s_]][[0, 2]]
        spd = np.zeros((n, 2))
        for k in range(n):
            a, b = max(k - 1, 0), min(k + 1, n - 1)
            spd[k] = np.linalg.norm(pos[b] - pos[a], axis=1) * self.fps / max(b - a, 1)
        stance = (low < STANCE_H) & (spd < STANCE_V)
        trav = np.zeros((n, 2))
        for i in range(2):
            st = None
            for k in range(n):
                if stance[k, i]:
                    if st is None:
                        st = pos[k, i].copy()
                    trav[k, i] = 100.0 * float(np.linalg.norm(pos[k, i] - st))
                else:
                    st = None
        return stance, trav

    def flights(self):
        """runs of frames with both feet off the floor whose CoM does not fall like a free body -> impossible"""
        clear, comy, _ = self.clip_kin()
        # the floor of the clip: the lowest foot corner it ever reaches while standing (frame 0) - clearance is relative to it
        floor = min(clear[0])
        self.floor0 = floor
        up = (clear.min(axis=1) - floor) > FLIGHT_CLEAR
        runs, i, n = [], 0, len(up)
        while i < n:
            if up[i]:
                j = i
                while j + 1 < n and up[j + 1]:
                    j += 1
                runs.append((i, j))
                i = j + 1
            else:
                i += 1
        bad = []
        dt = 1.0 / self.fps
        for a, b in runs:
            if b - a + 1 < 3:
                continue
            # extend one frame each side: the take-off and landing frames carry the push
            t = np.arange(a, b + 1) * dt
            c2 = np.polyfit(t - t.mean(), comy[a:b + 1], 2)[0]
            acc = 2 * c2
            if not (-1.4 * G <= acc <= -0.6 * G):
                bad.append((a, b, float(acc)))
        return bad, floor

    def inverse(self):
        """INVERSE DYNAMICS of the clip itself (no tracker, so no tracker error). Per frame: qpos from the clip (floor at y = 0),
        qvel / qacc from smoothed finite differences (mj_differentiatePos), contacts switched off. (1) mj_inverse with nothing applied
        gives the total outside wrench the motion needs (root generalised force). (2) the floor supplies what it can: that force is put
        at the centre of pressure solved from the moment balance, the CoP is CLAMPED to the support polygon (feet within CONTACT_H)
        and the horizontal part to the friction cone (mu = 1). (3) mj_inverse again with that ground force applied through the feet:
        the hinge entries are the joint torques, the root entries are what the floor could NOT give = the outside force / torque
        (the 'pelvis residual wrench'). A flight that does not fall like a free body leaves the body weight there.
        Returns (ratio[n], joint[n], force_frac[n], torque_frac[n]) (fractions of the caps)."""
        m, d = self.m, self.d
        n = len(self.fr)
        dt = 1.0 / self.fps
        shift = -self.floor0
        Q = np.zeros((n, m.nq))
        for k in range(n):
            th, p, q = self.tg[k]
            Q[k, self.qadr] = th
            Q[k, 0:3] = p + np.array([0, shift, 0])
            Q[k, 3:7] = q
        V = np.zeros((n, m.nv))
        for k in range(n):
            a, b = max(k - 1, 0), min(k + 1, n - 1)
            if b > a:
                mujoco.mj_differentiatePos(m, V[k], (b - a) * dt, Q[a], Q[b])
        box = lambda X: np.array([np.pad(X, ((2, 2), (0, 0)), mode="edge")[i:i + 5].mean(axis=0) for i in range(n)])
        Vs = box(V)
        A = np.zeros_like(Vs)
        for k in range(n):
            a, b = max(k - 1, 0), min(k + 1, n - 1)
            if b > a:
                A[k] = (Vs[b] - Vs[a]) / ((b - a) * dt)
        A = box(A)
        names = [h[0] for h in self.hinges]
        ratio, joint, ff, tf, fr = np.zeros(n), [""] * n, np.zeros(n), np.zeros(n), np.zeros(n)
        capf = ASSIST_FRAC * self.M * G
        W = self.M * G
        old = m.opt.disableflags
        m.opt.disableflags = old | int(mujoco.mjtDisableBit.mjDSBL_CONTACT)
        foot_bid = {s_: self.bid["foot_" + s_] for s_ in "lr"}
        try:
            for k in range(n):
                d.qpos[:] = Q[k]
                d.qvel[:] = Vs[k]
                d.qacc[:] = A[k]
                d.xfrc_applied[:] = 0
                d.qfrc_applied[:] = 0
                mujoco.mj_inverse(m, d)
                w0 = d.qfrc_inverse[0:6].copy()
                F = w0[0:3].copy()
                P = d.qpos[0:3].copy()
                Mom = d.xmat[self.pel].reshape(3, 3) @ w0[3:6]   # moment of the outside force about the pelvis origin, world frame
                polys = {}
                for s_ in "lr":
                    c = self.corners(s_)
                    low = c[:, 1].min()
                    if low < CONTACT_H:
                        polys[s_] = c[c[:, 1] < CONTACT_H + 0.02][:, [0, 2]]
                if polys and F[1] > 0.1 * W:
                    ry = 0.0 - P[1]
                    cz = P[2] + (ry * F[2] - Mom[0]) / F[1]
                    cx = P[0] + (Mom[2] + ry * F[0]) / F[1]
                    cop = np.array([cx, cz])
                    fh = np.array([F[0], F[2]])
                    nh = float(np.linalg.norm(fh))
                    fr[k] = nh / F[1]
                    if nh > FRICTION * F[1]:
                        fh *= FRICTION * F[1] / nh
                    Fg = np.array([fh[0], F[1], fh[1]])
                    cents = {s_: polys[s_].mean(axis=0) for s_ in polys}
                    if len(polys) == 2:
                        dl = np.linalg.norm(cop - cents["l"])
                        dr = np.linalg.norm(cop - cents["r"])
                        wt = {"l": dr / max(dl + dr, 1e-6), "r": dl / max(dl + dr, 1e-6)}
                    else:
                        wt = {s_: 1.0 for s_ in polys}
                    for s_, pts in polys.items():
                        cc = clamp_hull(pts, cop)
                        pnt = np.array([cc[0], 0.0, cc[1]])
                        tmp = np.zeros(m.nv)
                        mujoco.mj_applyFT(m, d, Fg * wt[s_], np.zeros(3), pnt, foot_bid[s_], tmp)
                        d.qfrc_applied[:] += tmp
                net = d.qfrc_inverse - d.qfrc_applied   # qfrc_inverse is the TOTAL external generalised force; the ground force is part of it
                tau = net[self.dadr]
                rr = np.abs(tau) / self.tmax
                i = int(np.argmax(rr))
                ratio[k], joint[k] = float(rr[i]), names[i]
                w = net[0:6]
                ff[k] = float(np.linalg.norm(w[0:3]) / capf)
                tf[k] = float(np.linalg.norm(w[3:6]) / ASSIST_TORQUE)
        finally:
            m.opt.disableflags = old
            d.qfrc_applied[:] = 0
        return ratio, joint, ff, tf, fr

    # ------------------------------------------------------------ the run
    def run(self, progress=None):
        m, d = self.m, self.d
        n = len(self.fr)
        dt = self.dt
        sub = max(1, int(round(1.0 / self.fps / dt)))
        bad_flights, floor = self.flights()
        stance, ktrav = self.clip_slide()
        self.id_ratio, self.id_joint, self.id_ff, self.id_tf, self.id_fr = self.inverse()
        air = np.zeros(n, bool)
        air_acc = {}
        for a, b, acc in bad_flights:
            air[a:b + 1] = True
            for k in range(a, b + 1):
                air_acc[k] = (acc, (b - a + 1) / self.fps)
        self.seat(0)
        h0 = float(d.qpos[1])
        # settle on frame-0's pose
        th0 = self.tg[0][0]
        self.refresh_gains()
        for i in range(int(0.4 / dt)):
            if i % 16 == 0:
                self.refresh_gains()
            self._substep(th0, np.zeros_like(th0), self.tg[0][1], self.tg[0][2], False)
        rows, phys = [], []
        ratio_raw, prev_contact, slide0 = [], {"l": None, "r": None}, {"l": 0.0, "r": 0.0}
        fell_count = 0
        names = [h[0] for h in self.hinges]
        for k in range(n):
            tgt, p_t, q_t = self.tg[k]
            nxt = self.tg[min(k + 1, n - 1)]
            vt = (nxt[0] - tgt) * self.fps
            rat_acc, rat_max, rat_j = 0.0, 0.0, ""
            self.refresh_gains()
            asum = 0.0
            for s in range(sub):
                frac = s / sub
                tg = tgt + (nxt[0] - tgt) * frac
                pt = p_t + (nxt[1] - p_t) * frac
                qt = q_t
                r, aF = self._substep(tg, vt, pt, qt, True)
                ratio_raw_s, jmax = r
                rat_acc += ratio_raw_s
                asum += aF
                if ratio_raw_s > rat_max:
                    rat_max, rat_j = ratio_raw_s, names[jmax]
            ratio = rat_acc / sub
            # measurements at the frame boundary
            fs = self.feet_state()
            con = {s: fs[s][0] < CONTACT_H for s in "lr"}
            com = d.subtree_com[1].copy()
            mujoco.mj_subtreeVel(m, d)
            vcom = d.subtree_linvel[1].copy()
            pts = []
            for s in "lr":
                if con[s]:
                    pts.extend(fs[s][1][:, [0, 2]].tolist())
            if pts:
                marg = hull_margin(pts, com[[0, 2]])
                w0 = np.sqrt(G / max(com[1], 0.5))
                xcom = com[[0, 2]] + vcom[[0, 2]] / w0
                xmarg = hull_margin(pts, xcom)
            else:
                marg = xmarg = None
            # slide: per foot, horizontal travel since it landed
            # (red = the SIMULATED foot travels more than the clip's own foot did over the same true stance; the clip's own travel is
            # the separate yellow "authored slide")
            slide = 0.0
            for i, s in enumerate("lr"):
                pos = d.xpos[self.bid["foot_" + s]][[0, 2]].copy()
                if con[s] and stance[k, i]:
                    if prev_contact[s] is None:
                        prev_contact[s] = pos
                    slide = max(slide, 100.0 * float(np.linalg.norm(pos - prev_contact[s])) - ktrav[k, i])
                else:
                    prev_contact[s] = None
            err_deg = float(np.degrees(np.sqrt(np.mean((d.qpos[self.qadr] - tgt) ** 2))))
            err_root = 100.0 * float(np.linalg.norm(d.qpos[0:3] - p_t))
            up = (d.xmat[self.pel].reshape(3, 3) @ np.array([0, 1.0, 0]))
            neck = d.xpos[self.bid["neck_01"]] - d.xpos[self.pel]
            tilt = float(np.degrees(np.arccos(np.clip(neck[1] / max(np.linalg.norm(neck), 1e-6), -1, 1))))
            fell = bool(d.qpos[1] < 0.55 * p_t[1] or tilt > 55.0)
            rows.append({"t": float(self.fr[k]["t"]), "err_deg": err_deg, "err_root_cm": err_root, "slide_cm": max(slide, 0.0), "authored_slide_cm": float(ktrav[k].max()), "sim_slide_cm": slide,
                         "margin_cm": None if marg is None else 100.0 * marg, "xmargin_cm": None if xmarg is None else 100.0 * xmarg,
                         "ratio": float(self.id_ratio[k]), "ratio_pd": ratio, "ratio_peak": rat_max, "ratio_joint": self.id_joint[k], "assist_frac": float(max(self.id_ff[k], self.id_tf[k])), "assist_force": float(self.id_ff[k]), "assist_torque": float(self.id_tf[k]), "assist_sim": asum / sub, "friction": float(self.id_fr[k]), "fell": fell,
                         "airborne": bool(air[k]), "contact": [int(con["l"]), int(con["r"])], "tilt": tilt})
            ratio_raw.append(ratio)
            phys.append(self.read_physical())
            if fell:
                fell_count += 1
                self.seat(min(k + 1, n - 1))
                prev_contact = {"l": None, "r": None}
            if progress and (k % 4 == 0 or k == n - 1):
                progress((k + 1) / n)
        for k, r in enumerate(rows):
            r["ratio_s"] = r["ratio"]
        return rows, phys, air_acc

    def _substep(self, tg, vt, pt, qt, want_ratio):
        m, d = self.m, self.d
        q = d.qpos[self.qadr]
        dq = d.qvel[self.dadr]
        tau = self.kp * (tg - q) + self.kv * vt + d.qfrc_bias[self.dadr]   # the -kv*dq half is the joint's own damping (implicit, stable)
        ratio = 0.0
        jmax = 0
        if want_ratio:
            rr = np.abs(tau) / self.tmax
            jmax = int(np.argmax(rr))
            ratio = float(rr[jmax])
        d.ctrl[:] = np.clip(tau, -self.tmax, self.tmax)
        # residual wrench on the pelvis: horizontal force + orientation torque, both capped
        p = d.qpos[0:3]
        v = d.qvel[0:3]
        fx = KROOT * (pt[0] - p[0]) - CROOT * v[0]
        fz = KROOT * (pt[2] - p[2]) - CROOT * v[2]
        fy = KROOT * (pt[1] - p[1]) - CROOT * v[1]
        nf = (fx * fx + fz * fz) ** 0.5
        cap = ASSIST_FRAC * self.M * G
        if nf > cap * SOFT:
            fx *= cap * SOFT / nf
            fz *= cap * SOFT / nf
        capy = max(ASSIST_UP * self.M * G, 1e-9)
        fy_c = max(-capy * SOFT, min(capy * SOFT, fy))
        nfh = nf / cap
        nfv = abs(fy) / capy
        # orientation error as a rotation vector (world frame): qe = qd * conj(qc)
        w1, x1, y1, z1 = qt
        w2, x2, y2, z2 = d.qpos[3], -d.qpos[4], -d.qpos[5], -d.qpos[6]
        ew = w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2
        ev = np.array([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2, w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2])
        if ew < 0:
            ev, ew = -ev, -ew
        sn = float(np.linalg.norm(ev))
        rv = ev * (2.0 * np.arctan2(sn, ew) / sn) if sn > 1e-9 else ev * 2.0
        # the free joint's angular velocity is in the body frame: rotate to world
        Rm = d.xmat[self.pel].reshape(3, 3)
        wv = Rm @ d.qvel[3:6]
        Tq = 3000.0 * rv - 200.0 * wv
        nt = float(np.linalg.norm(Tq))
        nft = nt / ASSIST_TORQUE
        if nt > ASSIST_TORQUE * SOFT:
            Tq *= ASSIST_TORQUE * SOFT / nt
        d.xfrc_applied[self.pel, 0] = fx
        d.xfrc_applied[self.pel, 1] = fy_c
        d.xfrc_applied[self.pel, 2] = fz
        d.xfrc_applied[self.pel, 3:] = Tq
        mujoco.mj_step(m, d)
        return (ratio, jmax), max(nfh, nfv, nft)   # the share of the residual wrench cap in use; >= 1 = saturated

    def refresh_gains(self):
        mujoco.mj_fullM(self.m, self.d, self._dense)
        Md = np.maximum(self._dense[self.dadr, self.dadr], 0.02)
        self.kv = 2 * 0.8 * np.sqrt(self.kp * Md)
        self.m.dof_damping[self.dadr] = self.kv

    def read_physical(self):
        """the body as Kine joint angles (bend, side, twist deg) + the pelvis position, from the MuJoCo world rotations"""
        d = self.d
        wq = {}
        for j in KM.JOINTS:
            q = d.xquat[self.bid[j]]
            wq[j] = R.from_quat([q[1], q[2], q[3], q[0]])
        ang = {}
        for j in KM.JOINTS:
            par = self.K.parent[j]
            A = wq[j] if not par else wq[par].inv() * wq[j]
            ang[j] = self.decompose(j, A)
        p = d.xpos[self.pel]
        return {"pelvis": [float(p[0]), float(p[1]), float(p[2])], "ang": ang}

    def decompose(self, j, A):
        """A -> (bend, side, twist) deg, the inverse of Kine.compose, started from the analytic swing-twist"""
        K = self.K
        w = K.w_ax[j]
        rv = A.as_rotvec()
        tw = float(np.dot(rv, w))
        sw = (A * R.from_rotvec(-w * tw)).as_rotvec()
        x0 = np.array([np.dot(sw, K.b_ax[j]), np.dot(sw, K.a_ax[j]), tw])
        fun = lambda v: (K.compose(j, np.degrees(v)).inv() * A).as_rotvec()
        x = newton_rot(fun, x0)
        return [float(np.degrees(v)) for v in x]


def run_flags(flag, fps, min_s):
    """True where the flag holds for a run longer than min_s seconds (a shorter blip is a touch-down transient, not a demand)"""
    n = len(flag)
    out = [False] * n
    k = 0
    while k < n:
        if flag[k]:
            j = k
            while j + 1 < n and flag[j + 1]:
                j += 1
            if (j - k + 1) / fps > min_s:
                for q in range(k, j + 1):
                    out[q] = True
            k = j + 1
        else:
            k += 1
    return out


def merge(mask, why, rows, fps, order, gap=1):
    n = len(mask)
    spans, k = [], 0
    while k < n:
        if mask[k]:
            j = k
            while j + 1 < n and (mask[j + 1] or (j + 1 + gap < n and any(mask[j + 1:j + 2 + gap]))):
                j += 1
            kinds = {}
            for q in range(k, j + 1):
                for kind, txt in why[q]:
                    kinds.setdefault(kind, []).append(txt)
            kind = next(c for c in order if c in kinds)
            txt = kinds[kind][len(kinds[kind]) // 2]
            others = [c for c in order if c in kinds and c != kind]
            spans.append({"f0": k, "f1": j, "t0": rows[k]["t"], "t1": rows[j]["t"] + 1.0 / fps, "kind": kind,
                          "reason": txt + ("  (also: %s)" % ", ".join(others) if others else "")})
            k = j + 1
        else:
            k += 1
    return spans


def spans_of(rows, air_acc, fps, tau_bar=TAU_BAR, slide_bar=SLIDE_BAR):
    """red frames -> merged spans with the reason. RED = what a human body cannot do: (airborne) both feet off the floor without
    falling like a free body; (fell) the tracked body falls; (force) the pelvis residual wrench (the outside force the tracking
    needs) above SAT_FRAC of its cap for SAT_S; (torque) a joint above tau_bar x its limit for TAU_S; (slide) a TRUE stance foot slides
    more than slide_bar cm beyond what the clip itself does. The CoM outside the stance foot is NOT red (normal gait has it 12-17 cm
    outside, Winter 1995). The clip's own foot skate is a yellow note ('authored slide'), not red."""
    n = len(rows)
    why = [[] for _ in range(n)]
    sat = run_flags([r["assist_frac"] > SAT_FRAC for r in rows], fps, SAT_S)
    tau = run_flags([r["ratio_s"] > tau_bar for r in rows], fps, TAU_S)
    sld = run_flags([r["friction"] > FRICTION and r["contact"] != [0, 0] for r in rows], fps, TAU_S)
    for k, r in enumerate(rows):
        if r["airborne"]:
            acc, dur = air_acc[k]
            why[k].append(("airborne", "airborne: both feet off the floor for %.2f s but the body does not fall like a free body (CoM accel %.1f m/s2, gravity is -9.8): a jump needs momentum" % (dur, acc)))
        if r["fell"]:
            why[k].append(("balance", "balance: the body falls (trunk %.0f deg off vertical, pelvis %.0f cm from the clip)" % (r["tilt"], r["err_root_cm"])))
        if sat[k]:
            why[k].append(("force", "outside force: the pelvis needs %.0f %% of the push a helper may give, so the motion needs an outside force" % (100 * r["assist_frac"])))
        if tau[k]:
            why[k].append(("torque", "torque: %s needs %.1fx the human limit" % (r["ratio_joint"].replace("_", " "), r["ratio_s"])))
        if sld[k]:
            why[k].append(("slide", "foot slide: the planted foot would slip (it needs %.0f %% of the horizontal force the floor can give)" % (100 * r["friction"] / FRICTION)))
    red = [bool(w) for w in why]
    order = ["airborne", "balance", "force", "torque", "slide"]
    spans = merge(red, why, rows, fps, order)
    yw = [[("authored_slide", "authored slide: the clip's own planted foot skates %.1f cm" % r["authored_slide_cm"])] if r["authored_slide_cm"] > slide_bar else [] for r in rows]
    notes = merge([bool(w) for w in yw], yw, rows, fps, ["authored_slide"])
    return spans, red, notes


def judge(clip, progress=None):
    J = Judge(clip)
    rows, phys, air_acc = J.run(progress)
    spans, red, notes = spans_of(rows, air_acc, J.fps)
    n = len(rows)
    summary = {"frames": n, "red_frames": int(sum(red)), "red_pct": 100.0 * sum(red) / max(n, 1), "falls": int(sum(r["fell"] for r in rows)),
               "mean_err_deg": float(np.mean([r["err_deg"] for r in rows])), "max_slide_cm": float(max(r["slide_cm"] for r in rows)), "max_friction": float(max(r["friction"] for r in rows)), "authored_slide_cm": float(max(r["authored_slide_cm"] for r in rows)), "max_assist": float(max(r["assist_frac"] for r in rows)),
               "max_ratio": float(max(r["ratio_s"] for r in rows)), "min_margin_cm": float(min([r["margin_cm"] for r in rows if r["margin_cm"] is not None] or [0.0]))}
    return {"fps": J.fps, "frames": rows, "red": red, "spans": spans, "notes": notes, "summary": summary, "physical": phys}


def main():
    a = sys.argv[1:]
    prog = None
    if "--progress" in a:
        i = a.index("--progress")
        prog = a[i + 1]
        del a[i:i + 2]
    clip = json.load(open(a[0]))

    def progress(x):
        if prog:
            with open(prog, "w") as f:
                f.write("%.3f" % x)

    out = judge(clip, progress)
    with open(a[1], "w") as f:
        json.dump(out, f)
    s = out["summary"]
    print("judged %d frames: red %.1f %% (%d spans), falls %d, mean err %.1f deg, max slide %.1f cm, max torque %.2fx, min margin %.1f cm"
          % (s["frames"], s["red_pct"], len(out["spans"]), s["falls"], s["mean_err_deg"], s["max_slide_cm"], s["max_ratio"], s["min_margin_cm"]))
    for sp in out["spans"]:
        print("  %.2f-%.2f s  %s" % (sp["t0"], sp["t1"], sp["reason"]))


if __name__ == "__main__":
    main()
