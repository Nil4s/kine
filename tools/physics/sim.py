"""Kine hit-reaction prototype, stage 1: stance PD + XCoM balance + capture-point stepping + impulse hits (MuJoCo 3.x).

Controller (all torque-level, 500 Hz = every physics step):
  1. PD on every hinge toward a pose (a Kine card: scenes/hit_react.json 'ready'), torque-clipped to human-scale limits.
  2. Arm / spine / head joints get gravity compensation (qfrc_bias), the legs do not: the legs carry the body by the
     desired ground-reaction force (virtual model control, tau_leg = -J(p)^T G).
  3. Balance (Hof 2005, J Biomech 38:1-8, "The condition for dynamic stability"): XCoM = x_com + v_com / w0, w0 = sqrt(g/l)
     with l = COM height. The desired centre of pressure is cop = ref + k (XCoM - ref), clipped to the feet, and the
     desired horizontal ground force is M w0^2 (x_com - cop) (linear inverted pendulum). Ankle strategy results because
     cop is realised by loading the foot at that point. Lateral uses the same law through the hip/ankle joints.
  4. Stepping (Hof 2008 / Pratt capture point): when XCoM leaves the base of support by more than `trigger`, the foot on
     the XCoM's side lifts and is placed at XCoM + margin by damped-least-squares IK on the leg joints.
The balance state is delayed by `delay_s` (default 0.1 s, the order of human balance-loop latency, Maurer & Peterka 2005
J Neurophysiol 93:689; the exact figure is not re-fetched here).
"""
import os
import sys

import mujoco
import numpy as np
from scipy.spatial.transform import Rotation as R

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kine_mjcf as KM  # noqa: E402

G = 9.81
POSE_SCENE = os.path.join(KM.ROOT, "scenes", "hit_react.json")


class Humanoid:
    def __init__(self, delay_s=0.1, stepping=True, pose_card=0, scene=POSE_SCENE):
        import json
        xml, self.hinges, self.info, self.K = KM.build()
        self.m = mujoco.MjModel.from_xml_string(xml)
        self.d = mujoco.MjData(self.m)
        m = self.m
        self.M = float(m.body_mass.sum())
        self.dt = m.opt.timestep
        self.hid = [m.joint(h[0]).id for h in self.hinges]
        self.qadr = np.array([m.jnt_qposadr[i] for i in self.hid])
        self.dadr = np.array([m.jnt_dofadr[i] for i in self.hid])
        self.kp = np.array([h[4] for h in self.hinges], float)
        self.tmax = np.array([h[3] for h in self.hinges], float)
        self.kv = 2 * 0.7 * np.sqrt(self.kp * 0.6) + 2.0
        self.hname = [h[0] for h in self.hinges]
        self.jk = [h[1] for h in self.hinges]
        self.is_leg = np.array([h[1].startswith(("thigh", "calf", "foot")) for h in self.hinges])
        self.bid = {j: m.body(j).id for j in KM.JOINTS}
        self.feet = {"l": m.body("foot_l").id, "r": m.body("foot_r").id}
        self.leg_cols = {s: np.array([i for i, h in enumerate(self.hinges) if h[1].startswith(("thigh", "calf", "foot")) and h[1].endswith("_" + s)]) for s in "lr"}
        self.delay_n = int(round(delay_s / self.dt))
        self.trigger = 0.03
        self.t_swing = 0.30
        self.lift_h = 0.10
        self.swing_load = 0.0
        self.stepping = stepping
        # pose targets from the scene card
        card = json.load(open(scene))["cards"][pose_card]
        self.target = np.zeros(len(self.hinges))
        pj = card["pose"]["joints"]
        by_joint = {}
        for i, (nm, j, k, _, _) in enumerate(self.hinges):
            by_joint.setdefault(j, []).append(i)
        for j, idxs in by_joint.items():
            v = pj[j]
            th = self.K.pose_to_hinges(j, [v["bend"], v["side"], v["twist"]])
            for i in idxs:
                self.target[i] = th["baw".index(self.hinges[i][2])]
        self.target = np.clip(self.target, m.jnt_range[self.hid, 0], m.jnt_range[self.hid, 1])
        self.reset()

    # ---------------------------------------------------------------- state
    def reset(self):
        m, d = self.m, self.d
        mujoco.mj_resetData(m, d)
        d.qpos[self.qadr] = self.target
        d.qpos[0:3] = self.K.p0["pelvis"]
        d.qpos[3:7] = [1, 0, 0, 0]
        mujoco.mj_forward(m, d)
        lowest = min(d.geom_xpos[m.geom(f"foot_{s}_box").id][1] - 0.0 for s in "lr")
        # sole is the box bottom: find the min corner height
        low = min(self._foot_corners(s)[:, 1].min() for s in "lr")
        d.qpos[1] -= low
        mujoco.mj_forward(m, d)
        self.ref_xz = self.com()[[0, 2]].copy()
        self.hist = []
        self.phase = "stand"
        self.swing = None
        self.t_phase = 0.0
        self.step_count = 0
        self.step_target = None
        self.lift_origin = None
        self.xfrc_until = -1.0
        self._hit_on = False
        self.first_step_t = None
        self.stance_pts = None

    def com(self):
        return self.d.subtree_com[1].copy()

    def vcom(self):
        mujoco.mj_subtreeVel(self.m, self.d)
        return self.d.subtree_linvel[1].copy()

    def _foot_corners(self, s):
        m, d = self.m, self.d
        gid = m.geom(f"foot_{s}_box").id
        h = m.geom_size[gid]
        Rm = d.geom_xmat[gid].reshape(3, 3)
        c = d.geom_xpos[gid]
        pts = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    pts.append(c + Rm @ (np.array([sx, sy, sz]) * h))
        return np.array(pts)

    def foot_box(self, s):
        c = self._foot_corners(s)
        return c[:, 0].min(), c[:, 0].max(), c[:, 2].min(), c[:, 2].max()

    def foot_down(self, s):
        return self._foot_corners(s)[:, 1].min() < 0.012

    def support_box(self):
        bs = [self.foot_box(s) for s in "lr" if self.foot_down(s) and s != self.swing]
        if not bs:
            bs = [self.foot_box(s) for s in "lr"]
        return (min(b[0] for b in bs), max(b[1] for b in bs), min(b[2] for b in bs), max(b[3] for b in bs))

    def trunk_lean_deg(self):
        """signed forward lean of the pelvis-to-neck line from vertical (sagittal plane), +forward"""
        v = self.d.xpos[self.bid["neck_01"]] - self.d.xpos[self.bid["pelvis"]]
        return float(np.degrees(np.arctan2(v[2], v[1])))

    def pelvis_lean_side_deg(self):
        v = self.d.xpos[self.bid["neck_01"]] - self.d.xpos[self.bid["pelvis"]]
        return float(np.degrees(np.arctan2(v[0], v[1])))

    # ------------------------------------------------------------- control
    def balance_state(self):
        """delayed COM and velocity (human loop latency)"""
        cur = (self.com(), self.vcom())
        self.hist.append(cur)
        if len(self.hist) > self.delay_n + 1:
            self.hist.pop(0)
        return self.hist[0]

    def xcom_of(self, com, v):
        l = max(0.5, com[1])
        w0 = np.sqrt(G / l)
        return com[[0, 2]] + v[[0, 2]] / w0, w0

    def leg_ik(self, s, pos, Rt, dd, iters, lam=0.01, gain=0.8):
        """6-D damped-least-squares IK of the foot (position + orientation) with the 7 or so leg hinges on scratch data dd.
        Returns the leg hinge angles (clipped to range)."""
        m = self.m
        cols = self.leg_cols[s]
        bid = self.bid["foot_" + s]
        jp = np.zeros((3, m.nv)); jr = np.zeros((3, m.nv))
        lo, hi = m.jnt_range[np.array(self.hid)[cols], 0], m.jnt_range[np.array(self.hid)[cols], 1]
        for _ in range(iters):
            mujoco.mj_kinematics(m, dd)
            mujoco.mj_comPos(m, dd)
            mujoco.mj_jacBody(m, dd, jp, jr, bid)
            Rc = dd.xmat[bid].reshape(3, 3)
            e = np.concatenate([pos - dd.xpos[bid], 0.6 * R.from_matrix(Rt @ Rc.T).as_rotvec()])
            J = np.vstack([jp[:, self.dadr[cols]], jr[:, self.dadr[cols]]])
            dq = J.T @ np.linalg.solve(J @ J.T + lam * np.eye(6), e)
            dd.qpos[self.qadr[cols]] = np.clip(dd.qpos[self.qadr[cols]] + gain * dq, lo, hi)
        return dd.qpos[self.qadr[cols]].copy()

    def plant(self):
        """record where the feet stand (position + rotation) and compute the stance pose that centres the pelvis over them"""
        d, m = self.d, self.m
        self.planted = {z: (d.xpos[self.bid["foot_" + z]].copy(), d.xmat[self.bid["foot_" + z]].reshape(3, 3).copy()) for z in "lr"}
        mid = 0.5 * (self.planted["l"][0] + self.planted["r"][0])
        dd = mujoco.MjData(m)
        dd.qpos[:] = d.qpos
        dd.qpos[self.qadr] = self.target
        # upright pelvis: keep the yaw of the current pelvis, zero tilt
        Rp = R.from_quat([d.qpos[4], d.qpos[5], d.qpos[6], d.qpos[3]])
        yaw = Rp.as_euler("YXZ")[0]
        q = R.from_euler("Y", yaw).as_quat()
        dd.qpos[3:7] = [q[3], q[0], q[1], q[2]]
        dd.qpos[0] = mid[0] + self._pel_off[0]
        dd.qpos[2] = mid[2] + self._pel_off[1]
        dd.qpos[1] = self._pel_h
        goal = {}
        for z in "lr":
            goal[z] = self.leg_ik(z, self.planted[z][0], self.planted[z][1], dd, 30)
            dd.qpos[self.qadr[self.leg_cols[z]]] = goal[z]
        self.goal = goal
        self.q_from = {z: d.qpos[self.qadr[self.leg_cols[z]]].copy() for z in "lr"}
        self.t_plant = d.time

    def control(self):
        m, d = self.m, self.d
        t = d.time
        q = d.qpos[self.qadr]
        qd = d.qvel[self.dadr]
        tgt = self.target.copy()
        com, v = self.balance_state()
        xc, w0 = self.xcom_of(com, v)
        box = self.support_box()
        # ----- stepping state machine
        if self.stepping:
            if self.phase == "stand":
                over = max(box[0] - xc[0], xc[0] - box[1], box[2] - xc[1], xc[1] - box[3])   # >0 outside the BoS
                both = all(self.foot_down(z) for z in "lr")
                if both:
                    self._both_t = getattr(self, "_both_t", t) if getattr(self, "_both_on", False) else t
                    self._both_on = True
                else:
                    self._both_on = False
                if over > -self.trigger and both and t - self._both_t > 0.1 and np.hypot(*(xc - self.ref_xz)) > 0.05:
                    u = (xc - self.ref_xz) / np.linalg.norm(xc - self.ref_xz)
                    fx = {z: d.xpos[self.bid["foot_" + z]][[0, 2]] for z in "lr"}
                    if abs(u[0]) > abs(u[1]):       # mostly sideways: the foot on the push side side-steps
                        s = "l" if u[0] > 0 else "r"
                    else:                            # mostly fore-aft: the trailing foot steps
                        s = min("lr", key=lambda z: fx[z] @ u)
                    self.swing = s
                    self.phase = "swing"
                    self.t_phase = t
                    self.step_count += 1
                    if self.first_step_t is None:
                        self.first_step_t = t
                    self.lift_origin = d.xpos[self.bid["foot_" + s]].copy()
                    self._both_on = False
            if self.phase == "swing":
                s = self.swing
                T = self.t_swing
                u = min(1.0, (t - self.t_phase) / T)
                other = "r" if s == "l" else "l"
                ox = d.xpos[self.bid["foot_" + other]]
                # capture point at touchdown (Pratt 2006; Hof 2008): the LIP stays on the stance foot, xi grows as e^(w0 T)
                xi_pred = ox[[0, 2]] + (xc - ox[[0, 2]]) * np.exp(w0 * T)
                dxz = xi_pred - ox[[0, 2]]
                reach = 0.65
                if np.linalg.norm(dxz) > reach:
                    dxz = dxz / np.linalg.norm(dxz) * reach
                tgt_xz = ox[[0, 2]] + dxz
                if s == "l":
                    tgt_xz[0] = max(tgt_xz[0], ox[0] + 0.12)
                else:
                    tgt_xz[0] = min(tgt_xz[0], ox[0] - 0.12)
                s_u = u * u * (3 - 2 * u)
                p = self.lift_origin.copy()
                p[[0, 2]] = (1 - s_u) * self.lift_origin[[0, 2]] + s_u * tgt_xz
                p[1] = self.lift_origin[1] + self.lift_h * np.sin(np.pi * u)
                dd = mujoco.MjData(self.m)
                dd.qpos[:] = d.qpos
                cols = self.leg_cols[s]
                tgt[cols] = self.leg_ik(s, p, self.planted[s][1] if hasattr(self, "planted") else np.eye(3), dd, 4)
                if u >= 1.0 and self.foot_down(s) and t - self.t_phase > T + 0.05:
                    self.phase = "stand"
                    self.swing = None
                    self.ref_xz = self._new_ref()
                    self.plant()
        # ----- stance legs: blend to the re-centred stance pose
        for z in "lr":
            if z == self.swing or not hasattr(self, "goal"):
                continue
            u = min(1.0, (t - self.t_plant) / 0.5)
            u = u * u * (3 - 2 * u)
            tgt[self.leg_cols[z]] = (1 - u) * self.q_from[z] + u * self.goal[z]
        # ----- PD
        tau = self.kp * (tgt - q) - self.kv * qd
        # ----- gravity compensation for everything except the legs
        grav = d.qfrc_bias[self.dadr]
        tau[~self.is_leg] += grav[~self.is_leg]
        # ----- legs: desired GRF at the desired CoP
        support = list("lr")
        k_cop = 1.0 + 3.2 / (w0 * 1.0)      # Hof 2008: CoP = XCoM-gain (1 + K/w0)
        cop = self.ref_xz + k_cop * (xc - self.ref_xz)
        box = self.support_box()
        cop = np.array([np.clip(cop[0], box[0] + 0.01, box[1] - 0.01), np.clip(cop[1], box[2] + 0.01, box[3] - 0.01)])
        Fh = self.M * w0 ** 2 * (com[[0, 2]] - cop)
        n_sup = len(support)
        # load share by lateral cop position between the two feet
        shares = {s: 1.0 / n_sup for s in support}
        if self.swing:
            shares = {z: (self.swing_load if z == self.swing else 1 - self.swing_load) for z in "lr"}
        elif n_sup == 2:
            xl = d.xpos[self.bid["foot_l"]][0]
            xr = d.xpos[self.bid["foot_r"]][0]
            a = np.clip((cop[0] - xr) / (xl - xr + 1e-9), 0.1, 0.9)
            shares = {"l": a, "r": 1 - a}
        jp = np.zeros((3, m.nv))
        for s in support:
            fb = self.foot_box(s)
            pt = np.array([np.clip(cop[0], fb[0], fb[1]), 0.0, np.clip(cop[1], fb[2], fb[3])])
            mujoco.mj_jac(m, d, jp, None, pt, self.bid["foot_" + s])
            cols = self.leg_cols[s]
            Gf = np.array([Fh[0] * shares[s], self.M * G * shares[s], Fh[1] * shares[s]])
            tau[cols] += -(jp[:, self.dadr[cols]].T @ Gf)
        tau = np.clip(tau, -self.tmax, self.tmax)
        d.ctrl[:] = tau

    def _new_ref(self):
        """after a step the reference point is the middle of the new base of support at the COM's pre-step offset"""
        d = self.d
        xm = np.mean([d.xpos[self.bid["foot_" + z]][[0, 2]] for z in "lr"], axis=0)
        if not hasattr(self, "_ref_off"):
            xm0 = np.mean([self._ankle0[z] for z in "lr"], axis=0)
            self._ref_off = self._ref0 - xm0
        return xm + self._ref_off

    def hit(self, body, J, dir_deg, dur=0.05):
        """linear impulse J (N s) on `body`, direction dir_deg in the horizontal plane (0 = forward +z, 90 = hero's left +x)"""
        a = np.radians(dir_deg)
        f = J / dur * np.array([np.sin(a), 0.0, np.cos(a)])
        self.hit_body = self.bid[body]
        self.hit_f = f
        self.xfrc_until = self.d.time + dur

    def step(self):
        d = self.d
        # the viewer's Ctrl+right-drag perturbation writes xfrc_applied: keep it, only clear our own hit
        if getattr(self, "_hit_on", False):
            d.xfrc_applied[self.hit_body, :3] -= self.hit_f
            self._hit_on = False
        if d.time < self.xfrc_until:
            self._hit_on = True
            d.xfrc_applied[self.hit_body, :3] += self.hit_f
        self.control()
        mujoco.mj_step(self.m, d)

    def init_refs(self):
        d = self.d
        mid0 = 0.5 * (d.xpos[self.bid["foot_l"]] + d.xpos[self.bid["foot_r"]])
        self._pel_off = d.xpos[1][[0, 2]] - mid0[[0, 2]]
        self._pel_h = float(d.xpos[1][1])
        self.plant()
        self.t_plant = -10.0
        self._ref0 = self.ref_xz.copy()
        self._ankle0 = {z: self.d.xpos[self.bid["foot_" + z]][[0, 2]].copy() for z in "lr"}
        if hasattr(self, "_ref_off"):
            del self._ref_off

    def fallen(self):
        return self.d.xpos[self.bid["pelvis"]][1] < 0.55 or self.d.xpos[self.bid["head"]][1] < 1.0


def make(**kw):
    h = Humanoid(**kw)
    h.init_refs()
    return h


def stand_test(secs=5.0, **kw):
    h = make(**kw)
    n = int(secs / h.dt)
    c0 = h.com()
    drift = 0.0
    for i in range(n):
        h.step()
        drift = max(drift, np.linalg.norm(h.com()[[0, 2]] - c0[[0, 2]]))
        if h.fallen():
            return False, h.d.time, drift
    return True, h.d.time, drift, h.com(), h.trunk_lean_deg()


if __name__ == "__main__":
    print(stand_test())
