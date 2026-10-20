"""Two Kine humanoids in MuJoCo: an ATTACKER that plays a real Kine swing (scenes/*.json, read only) with a bat of real mass in
its hand, and the DEFENDER of sim.py (stance PD + XCoM balance + stepping). No point impulse anywhere: where the hit lands,
how hard and for how long come out of the contact between the swinging limb / bat and the body.

CLIPS   tools/physics/dump_clip.gd (headless Godot, Scene.apply like tools/export_bvh.gd) writes each scene as 60 fps joint
        rotations + pelvis path + the weapon's pose in the hand to C:/Users/Nick/.claude/jobs/9afc22db/tmp/clip_<name>.json.
        Here they become hinge angles (kine_mjcf pose_to_hinges, warm-started frame to frame) and a 2 kHz table of
        q, qdot, qddot (cubic spline).
ATTACKER computed-torque tracking of that table on all 53 dofs (free pelvis + 47 hinges):
        tau = qfrc_bias + M (qdd_ref + kp e + kd ed), omega_n = 30 rad/s (a joint follows the clip over ~100 ms but is only
        stiff over that scale; inside a 10-20 ms impact the limb is a body with its real inertia, which is the point).
        Hinge torques clipped at TORQUE_X x the defender's human-scale limits (kine_mjcf TAU_MAX); no ground contact for the
        attacker (it hovers on its own computed torque, the clip is what an athlete's legs do).
        Placement: the barrel point (0.70 L from the knob, ~ the bat's centre of percussion, Brody 1986) at the clip's
        CONTACT / STRIKE card is put over the defender's trunk axis, facing it. Everything after is physics.
WEAPON  rigid child of the right hand: mass, centre of mass and radius of gyration of scripts/body.gd KINDS (bat 32 oz = 0.91 kg
        -> 0.90 kg, L 0.84 m, COM 0.65 L, k 0.25 L; a 1.8 m staff ~1.4 kg is the same builder). Without a weapon the striking
        parts are hand + forearm. Contact filters: striking parts (contype 4) collide ONLY with the defender (conaffinity bit 4);
        attacker non-striking parts collide with nothing; the weapon never touches the floor or the attacker.
CONTACT mixing time of a striking geom against the defender: omega_n = 1/(timeconst*dampratio) = 250 rad/s, zeta 0.5. MuJoCo
        solves contacts in acceleration space, so this timescale is mass-independent: the pulse DURATION and (through it) the
        PEAK force are set by this one parameter (k = m omega^2 = 1.8e5 N/m for the 2.9 kg effective fist mass of Walilko et al.
        2005); the impulse, the speed at impact, the location and the defender's reaction are the physics. measure_swing.py
        reports the sensitivity to it.
"""
import json
import os
import re
import sys

import mujoco
import numpy as np
from scipy.interpolate import CubicSpline
from scipy.spatial.transform import Rotation as R, RotationSpline

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kine_mjcf as KM  # noqa: E402
import sim  # noqa: E402

TMP = r"C:\Users\Nick\.claude\jobs\9afc22db\tmp"
GODOT = r"C:\Users\Nick\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
PHYS_DT = 0.0005            # physics step; defender + attacker control run every CTRL_EVERY steps (500 Hz, as sim.py)
CTRL_EVERY = 4
LEAD = 1.0                  # s: both stand still before the clip starts (the defender settles)
OMEGA_N = 30.0
TORQUE_X = 50.0
TC, DR = 0.008, 0.5         # contact timeconst / dampratio for striking geoms and defender capsules
STRIKERS_FIST = ("hand_r", "lowerarm_r", "hand_l", "lowerarm_l")
BARREL = 0.70               # the barrel point, fraction of the bat length from the knob
YAW = R.from_euler("y", 180, degrees=True)


# ------------------------------------------------------------------ clips
def clip_json(name):
    p = os.path.join(TMP, f"clip_{name}.json")
    if not os.path.exists(p):
        import subprocess
        subprocess.run([GODOT, "--headless", "--path", KM.ROOT, "-s", "tools/physics/dump_clip.gd", "--", f"scenes/{name}.json", p], check=True, capture_output=True)
    return json.load(open(p))


class Clip:
    """a scene as hinge angles + root motion + the weapon's pose in the hand (scene frame: Kine's own, +Z forward)"""

    def __init__(self, name, K, hinges):
        c = clip_json(name)
        self.name, self.K = name, K
        fr = c["frames"]
        self.t = np.array([f["t"] for f in fr])
        self.T = float(self.t[-1])
        self.cards = c["cards"]
        # every joint's rotation A[j] (scripts/body.gd compose) as a unit quaternion: the attacker's joints are BALL joints, so the
        # clip is reproduced exactly (a b-a-w hinge chain cannot reach the shoulder's whole swing-twist range: up to 60 deg off)
        self.joints = [j for j in KM.JOINTS if j != "pelvis"]
        self.Rj = {}
        for j in self.joints:
            qs = R.from_quat([K.compose(j, f["ang"][j]).as_quat() for f in fr]) if False else R.from_quat(np.array([K.compose(j, f["ang"][j]).as_quat() for f in fr]))
            self.Rj[j] = qs
        self.p = np.array([f["pelvis"] for f in fr])
        rv = np.array([K.compose("pelvis", f["ang"]["pelvis"]).as_rotvec() for f in fr])
        self.A = R.from_rotvec(rv)
        # the weapon in the hand frame (constant in these scenes; mean over the clip)
        w0 = fr[0]["wep"]
        self.wep = {"kind": w0["kind"], "len": w0["len"], "hand": w0["hand"]}
        lp, lq = [], []
        for f in fr:
            w = f["wep"]
            g = R.from_quat(w["hand_G"])
            lp.append(g.inv().apply(np.array(w["knob"]) - np.array(w["hand_P"])))
            lq.append((g.inv() * R.from_quat(w["rot"])).as_quat())
        self.wep["lpos"] = np.mean(lp, axis=0)
        self.wep["lquat"] = R.from_quat(lq).mean().as_quat()
        self.frames = fr
        self.t_contact = None
        for cd in self.cards:
            if "CONTACT" in cd["name"] or "STRIKE" in cd["name"]:
                self.t_contact = float(cd["t"])
                break

    def point_at(self, t, what="barrel"):
        """scene-frame world point at clip time t: the barrel (bat) or the fist (hand end)"""
        fr = self.frames[min(len(self.frames) - 1, int(round(t * 60)))]
        w = fr["wep"]
        if what == "barrel":
            return np.array(w["knob"]) + R.from_quat(w["rot"]).apply([0, BARREL * w["len"], 0])
        e = self.K.e0["hand_r"] - self.K.p0["hand_r"]
        return np.array(w["hand_P"]) + R.from_quat(w["hand_G"]).apply(e * 0.8)

    def table(self, offset_xz, dt=0.002, tail=1.0):
        """2 kHz reference: world root pose (yawed 180 deg about Y, then shifted by offset_xz), hinge q/qd/qdd"""
        n = int((LEAD + self.T + tail) / dt) + 2
        ts = np.arange(n) * dt
        tc = np.clip(ts - LEAD, 0.0, self.T)
        ps = CubicSpline(self.t, self.p, bc_type="clamped")
        live = (ts >= LEAD) & (ts <= LEAD + self.T)
        mask = live.astype(float)[:, None]
        tab = {"ts": ts}
        p = YAW.apply(ps(tc)) + np.array([offset_xz[0], 0.0, offset_xz[1]])
        tab["p"], tab["v"], tab["a"] = p, YAW.apply(ps(tc, 1)) * mask, YAW.apply(ps(tc, 2)) * mask
        Rw = YAW * RotationSpline(self.t, self.A)(tc)
        tab["quat"] = Rw.as_quat()
        w = (Rw[2:] * Rw[:-2].inv()).as_rotvec() / (2 * dt)
        w = np.vstack([w[:1], w, w[-1:]]) * mask
        tab["w"], tab["al"] = w, np.gradient(w, dt, axis=0) * mask
        # joints: ball-joint reference quaternion (w x y z), angular velocity and acceleration in the CHILD frame (MuJoCo's qvel)
        qj, wj, aj = [], [], []
        for j in self.joints:
            Rr = RotationSpline(self.t, self.Rj[j])(tc)
            wl = (Rr[:-2].inv() * Rr[2:]).as_rotvec() / (2 * dt)
            wl = np.vstack([wl[:1], wl, wl[-1:]]) * mask
            qq = Rr.as_quat()
            qj.append(np.c_[qq[:, 3], qq[:, :3]])
            wj.append(wl)
            aj.append(np.gradient(wl, dt, axis=0) * mask)
        tab["qj"], tab["wj"], tab["aj"] = np.stack(qj, 1), np.stack(wj, 1), np.stack(aj, 1)
        return tab


# ------------------------------------------------------------------ model
def duel_xml(with_bat, lpos, lquat, bat_len, strikers, kind="metal_bat", tc=TC, dr=DR):
    """one MJCF with the defender (names as kine_mjcf) and the attacker (prefix a_)"""
    xml, hinges, info, K = KM.build()
    lines = xml.split("\n")
    fi = next(i for i, l in enumerate(lines) if '<geom name="floor"' in l)
    wb_end = next(i for i, l in enumerate(lines) if l.strip() == "</worldbody>")
    head, body, tail = lines[:fi + 1], lines[fi + 1:wb_end], lines[wb_end:]
    # the actuator block belongs to the defender only
    tail_txt = "\n".join(tail)
    # defender: capsules/feet also collide with the attacker's striking bit (4); capsules get the flesh timescale
    dfn = []
    for l in body:
        if "<geom" in l:
            l = l.replace('conaffinity="1"', 'conaffinity="5"')
            if "_cap" in l:
                l = l.replace("<geom ", f'<geom solref="{tc} {dr}" ', 1)
        dfn.append(l)
    # attacker: copy with prefix, no cameras, striking parts contype 4, everything else 0
    att = []
    seen = set()
    for l in body:
        if "<camera" in l:
            continue
        mj = re.search(r'<joint name="([^"]+)_[baw]" type="hinge"', l)
        if mj:       # one ball joint per Kine joint instead of its hinge chain
            if mj.group(1) in seen:
                continue
            seen.add(mj.group(1))
            att.append(f'{l[:len(l) - len(l.lstrip())]}<joint name="a_{mj.group(1)}" type="ball" damping="1.0" armature="0.02"/>')
            continue
        l = re.sub(r'\b(name|joint)="([^"]+)"', r'\1="a_\2"', l)
        if "<geom" in l:
            gname = re.search(r'name="a_([^"]+)"', l).group(1)
            jn = gname.replace("_cap", "").replace("_box", "")
            strike = jn in strikers
            l = re.sub(r'contype="\d+" conaffinity="\d+"', 'contype="4" conaffinity="0"' if strike else 'contype="0" conaffinity="0"', l)
            if strike:
                l = l.replace("<geom ", f'<geom solref="{tc} {dr}" ', 1)
            l = l.replace("0.8 0.62 0.5 1", "0.45 0.55 0.85 1")
        att.append(l)
    att_txt = "\n".join(att)
    # attacker free joint keeps its name a_root
    if with_bat:
        kd = KINDS[kind]
        m_b, com, k = kd["mass"], kd["com"] * bat_len, kd["k"] * bat_len
        Iperp = m_b * k * k
        Iax = 0.5 * m_b * 0.03 ** 2
        hl = kd["handle"] if kd["handle"] > 0 else bat_len + kd["handle"]
        q = R.from_quat(lquat).as_quat()
        bat = (f'<body name="a_bat" pos="{lpos[0]:.5f} {lpos[1]:.5f} {lpos[2]:.5f}" quat="{q[3]:.6f} {q[0]:.6f} {q[1]:.6f} {q[2]:.6f}">'
               f'<inertial pos="0 {com:.4f} 0" mass="{m_b}" diaginertia="{Iperp:.6g} {Iax:.6g} {Iperp:.6g}"/>'
               f'<geom name="a_bat_handle" type="capsule" fromto="0 0 0 0 {hl:.4f} 0" size="{kd["r_handle"]}" contype="4" conaffinity="0" solref="{tc} {dr}" rgba="0.55 0.35 0.15 1"/>'
               f'<geom name="a_bat_barrel" type="capsule" fromto="0 {hl:.4f} 0 0 {bat_len:.4f} 0" size="{kd["r_barrel"]}" contype="4" conaffinity="0" solref="{tc} {dr}" rgba="0.75 0.75 0.8 1"/>'
               f'</body>')
        mt = re.search(r'(<body name="a_hand_r"[^\n]*\n(?:(?!\s*</body>)[^\n]*\n)*?)(\s*</body>)', att_txt)
        att_txt = att_txt[:mt.end(1)] + bat + "\n" + att_txt[mt.end(1):]
    cams = ""
    for nm, pos, tgt in (("duel", (3.9, 1.05, 0.45), (0, 0.95, 0.45)), ("duel3", (2.9, 1.7, -2.3), (0, 0.95, 0.35)), ("duelf", (-0.1, 1.2, -3.6), (0, 1.0, 0.4))):
        pos, tgt = np.array(pos), np.array(tgt)
        zc = (pos - tgt) / np.linalg.norm(pos - tgt)
        xc = np.cross([0, 1, 0], zc)
        xc /= np.linalg.norm(xc)
        yc = np.cross(zc, xc)
        cams += f'    <camera name="{nm}" mode="fixed" pos="{pos[0]} {pos[1]} {pos[2]}" xyaxes="{xc[0]:.4f} {xc[1]:.4f} {xc[2]:.4f} {yc[0]:.4f} {yc[1]:.4f} {yc[2]:.4f}"/>\n'
    out = "\n".join(head) + "\n" + cams + "\n".join(dfn) + "\n" + att_txt + "\n" + tail_txt
    out = out.replace('timestep="0.002"', f'timestep="{PHYS_DT}"')
    return out, hinges, K


# scripts/body.gd KINDS (mass kg, COM fraction of length from the butt, radius of gyration fraction of length)
KINDS = {
    "metal_bat": {"len": 0.84, "handle": 0.40, "r_handle": 0.016, "r_barrel": 0.033, "mass": 0.90, "com": 0.65, "k": 0.25},
    "staff": {"len": 1.80, "handle": 0.90, "r_handle": 0.016, "r_barrel": 0.016, "mass": 1.40, "com": 0.50, "k": 0.289},
}


class Duel(sim.Humanoid):
    def __init__(self, clip_name="swing_fore", weapon=True, offset=(0.0, 0.0), tc=TC, dr=DR, omega=OMEGA_N):
        self.att = False
        K0 = KM.Kine()
        hn = KM.build(K0)[1]
        self.clip = Clip(clip_name, K0, hn)
        self.weapon = weapon
        self.tc, self.dr = tc, dr
        w = self.clip.wep
        strikers = ("bat_handle", "bat_barrel") if weapon else STRIKERS_FIST
        xml, hinges, K = duel_xml(weapon, w["lpos"], w["lquat"], w["len"], strikers, w["kind"], tc, dr)
        super().__init__(stepping=True, xml=xml)
        self.dt_ctrl = PHYS_DT * CTRL_EVERY
        self.delay_n = int(round(0.1 / self.dt_ctrl))
        m = self.m
        self.kp_a = omega ** 2
        self.kd_a = 2 * omega
        # attacker indices
        jr = m.joint("a_root")
        self.ra, self.rd = int(jr.qposadr[0]), int(jr.dofadr[0])
        self.jlist = [j for j in KM.JOINTS if j != "pelvis"]
        self.a_q = np.array([m.jnt_qposadr[m.joint("a_" + j).id] for j in self.jlist])
        self.a_d = np.array([m.jnt_dofadr[m.joint("a_" + j).id] for j in self.jlist])
        assert np.all(self.a_d == self.rd + 6 + 3 * np.arange(len(self.jlist)))
        self.a_sl = slice(self.rd, self.rd + 6 + 3 * len(self.jlist))
        tm = dict(zip([h[1] for h in self.hinges][::1], [h[3] for h in self.hinges]))
        self.a_tmax = np.repeat([tm[j] for j in self.jlist], 3) * TORQUE_X
        self.a_body = {j: m.body("a_" + j).id for j in KM.JOINTS}
        self.bat = m.body("a_bat").id if weapon else None
        self.def_bodies = set(range(1, m.body("a_pelvis").id))
        self.striker_geoms = set(i for i in range(m.ngeom) if m.geom_contype[i] == 4)
        self.sg_list = sorted(self.striker_geoms)
        self.def_geoms = set(i for i in range(m.ngeom) if m.geom_bodyid[i] in self.def_bodies and m.geom_conaffinity[i] == 5)
        self.m_att = float(m.body_subtreemass[m.body("a_pelvis").id])
        self.fm = np.zeros((m.nv, m.nv))
        self.set_offset(offset)
        self.att = True
        self.reset()
        self.init_refs()

    # ---- placement: barrel (or fist) point at the contact card over the defender's trunk axis
    def set_offset(self, offset):
        c = self.clip
        what = "barrel" if self.weapon else "fist"
        tcon = c.t_contact if c.t_contact is not None else c.T * 0.5
        pc = YAW.apply(c.point_at(tcon, what))
        aim = np.array([0.0, 0.0])
        mujoco.mj_forward(self.m, self.d)
        aim = self.d.xpos[self.bid["spine_03"]][[0, 2]].copy()
        self.offset_xz = aim + np.array(offset) - pc[[0, 2]]
        self.tab = c.table(self.offset_xz)

    def reset(self):
        super().reset()
        if getattr(self, "att", False):
            self._gate_on = True
            self.m.geom_contype[self.sg_list] = 0
            self._gate_on = False
            d, m = self.d, self.m
            tb = self.tab
            for i, qa in enumerate(self.a_q):
                d.qpos[qa:qa + 4] = tb["qj"][0, i]
            d.qpos[self.ra:self.ra + 3] = tb["p"][0]
            qq = tb["quat"][0]
            d.qpos[self.ra + 3:self.ra + 7] = [qq[3], qq[0], qq[1], qq[2]]
            mujoco.mj_forward(m, d)

    # ---- attacker computed torque
    def att_control(self):
        d, m, tb = self.d, self.m, self.tab
        k = min(int(d.time / 0.002 + 0.5), len(tb["ts"]) - 1)
        nq = len(self.jlist)
        qc = np.stack([d.qpos[qa:qa + 4] for qa in self.a_q])
        Rc_j = R.from_quat(np.c_[qc[:, 1:], qc[:, 0]])
        Rr_j = R.from_quat(np.c_[tb["qj"][k][:, 1:], tb["qj"][k][:, 0]])
        e_j = (Rc_j.inv() * Rr_j).as_rotvec()                       # child frame
        wc = d.qvel[self.rd + 6:self.rd + 6 + 3 * nq].reshape(nq, 3)
        acc_h = (tb["aj"][k] + self.kp_a * e_j + self.kd_a * (tb["wj"][k] - wc)).reshape(-1)
        p, v = d.qpos[self.ra:self.ra + 3], d.qvel[self.rd:self.rd + 3]
        acc_p = tb["a"][k] + self.kp_a * (tb["p"][k] - p) + self.kd_a * (tb["v"][k] - v)
        qq = d.qpos[self.ra + 3:self.ra + 7]
        Rc = R.from_quat([qq[1], qq[2], qq[3], qq[0]])
        Rm = Rc.as_matrix()
        Rr = R.from_quat(tb["quat"][k])
        e_w = (Rr * Rc.inv()).as_rotvec()
        w_w = Rm @ d.qvel[self.rd + 3:self.rd + 6]
        acc_r = Rm.T @ (tb["al"][k] + self.kp_a * e_w + self.kd_a * (tb["w"][k] - w_w))
        acc = np.concatenate([acc_p, acc_r, acc_h])
        mujoco.mj_fullM(m, d, self.fm)
        sl = self.a_sl
        tau = d.qfrc_bias[sl] + self.fm[sl, sl] @ acc
        tau[6:] = np.clip(tau[6:], -self.a_tmax, self.a_tmax)
        d.qfrc_applied[sl] = tau

    def step(self):
        """one control tick = CTRL_EVERY physics steps; contacts are scanned every physics step"""
        d = self.d
        self.control()
        if self.att:
            self.att_control()
            self.gate()
        for _ in range(CTRL_EVERY):
            mujoco.mj_step(self.m, d)
            self.scan()

    def gate(self):
        """the attacker's striking parts touch the defender only from 0.30 s before the clip's CONTACT/STRIKE card on: the wind-up
        and coil of a swing are drawn for the air around the target (a fighter at the right distance does not shove his
        opponent with the coil); without this gate the placement's slow pushes (0.5-3 m/s) dominate the record"""
        ct = self.d.time - LEAD
        c = self.clip
        on = ct >= (c.t_contact - 0.30 if c.t_contact is not None else 0.0)
        if on != self._gate_on:
            self._gate_on = on
            self.m.geom_contype[self.sg_list] = 4 if on else 0

    _gate_on = True

    # ---- contact recording (striking geom vs defender geom)
    def scan(self):
        d, m = self.d, self.m
        if not self.rec_on:
            return
        F = np.zeros(3)
        pos = np.zeros(3)
        wsum = 0.0
        per = {}
        f6 = np.zeros(6)
        for i in range(d.ncon):
            c = d.contact[i]
            g1, g2 = int(c.geom1), int(c.geom2)
            if g1 in self.striker_geoms and g2 in self.def_geoms:
                sgn, dg, sg = 1.0, g2, g1
            elif g2 in self.striker_geoms and g1 in self.def_geoms:
                sgn, dg, sg = -1.0, g1, g2
            else:
                continue
            mujoco.mj_contactForce(m, d, i, f6)
            fw = np.asarray(c.frame).reshape(3, 3).T @ f6[:3] * sgn      # force on the defender (frame rows: normal first, geom1 -> geom2)
            F += fw
            n = np.linalg.norm(fw)
            pos += n * c.pos
            wsum += n
            b = int(m.geom_bodyid[dg])
            per[b] = per.get(b, 0.0) + n
        if wsum > 0:
            self.log_c.append((d.time, F.copy(), pos / wsum, per))
        else:
            self.log_c.append((d.time, F, d.xpos[1], per))

    rec_on = False

    def vel_of(self, body, point):
        res = np.zeros(6)
        mujoco.mj_objectVelocity(self.m, self.d, mujoco.mjtObj.mjOBJ_BODY, body, res, 0)
        return res[3:] + np.cross(res[:3], point - self.d.xipos[body])

    def striker_point_speed(self):
        """speed of the barrel point of the bat (or the hand end of the right hand) now, m/s"""
        if self.weapon:
            Rb = self.d.xmat[self.bat].reshape(3, 3)
            pt = self.d.xpos[self.bat] + Rb @ np.array([0, BARREL * self.clip.wep["len"], 0])
            return float(np.linalg.norm(self.vel_of(self.bat, pt))), pt
        b = self.a_body["hand_r"]
        return float(np.linalg.norm(self.vel_of(b, self.d.xpos[b]))), self.d.xpos[b].copy()

    # ---- defender state readouts
    def head_w(self):
        return float(np.linalg.norm(self.d.cvel[self.bid["head"]][:3]))

    def neck_angle_deg(self):
        Rh = self.d.xmat[self.bid["head"]].reshape(3, 3)
        Rs = self.d.xmat[self.bid["spine_03"]].reshape(3, 3)
        return float(np.degrees(np.arccos(np.clip(Rh[:, 1] @ Rs[:, 1], -1, 1))))

    def fallen(self):
        return self.d.xpos[self.bid["pelvis"]][1] < 0.55 or self.d.xpos[self.bid["head"]][1] < 1.0

    def bname(self, b):
        return mujoco.mj_id2name(self.m, mujoco.mjtObj.mjOBJ_BODY, b)


def pulses(log, gap=0.006, thr=5.0):
    """split the contact log into pulses: lists of (t, F vec, pos, per-body)"""
    out, cur, last = [], [], -9
    for rec in log:
        if np.linalg.norm(rec[1]) > thr:
            if cur and rec[0] - last > gap:
                out.append(cur)
                cur = []
            cur.append(rec)
            last = rec[0]
    if cur:
        out.append(cur)
    return out


def pulse_stats(h, P):
    t = np.array([r[0] for r in P])
    F = np.array([r[1] for r in P])
    Fm = np.linalg.norm(F, axis=1)
    dt = PHYS_DT
    J = F.sum(0) * dt
    Jmag = float(np.linalg.norm(J))
    pk = float(Fm.max())
    half = t[Fm >= 0.5 * pk]
    ext = t[Fm >= 0.05 * pk]
    per = {}
    for r in P:
        for b, n in r[3].items():
            per[b] = per.get(b, 0.0) + n * dt
    top = max(per, key=per.get)
    w = np.array([np.linalg.norm(r[1]) for r in P])
    pos = (np.array([r[2] for r in P]) * w[:, None]).sum(0) / w.sum()
    return dict(t0=float(t[0]), peak_N=pk, impulse_Ns=Jmag, impulse_vec=J, fwhm_ms=1000 * float(half[-1] - half[0] + dt),
                base_ms=1000 * float(ext[-1] - ext[0] + dt), body=h.bname(top), share={h.bname(b): v / sum(per.values()) for b, v in per.items()},
                point=pos, dir=J / (Jmag + 1e-9))


def run(clip="swing_fore", weapon=True, offset=(0, 0), secs=None, tc=TC, dr=DR, omega=OMEGA_N, keep_states=True, duel=None):
    """play the whole clip against the defender; returns metrics of the first contact pulse and the defender's reaction"""
    h = duel or Duel(clip, weapon, offset, tc, dr, omega)
    if duel is not None:
        h.reset(); h.init_refs()
    h.log_c = []
    h.rec_on = True
    T = h.clip.T + LEAD + (secs if secs is not None else 1.5)
    n_ctrl = int(T / h.dt_ctrl)
    sub = int(round(1 / 60 / h.dt_ctrl))
    states = []
    sig = dict(t=[], head_w=[], lean=[], neck=[], tipv=[], pel=[], hcom=[])
    for i in range(n_ctrl):
        h.step()
        if i % sub == 0:
            if keep_states:
                states.append((h.d.time, h.d.qpos.copy()))
            sp, _ = h.striker_point_speed()
            sig["t"].append(h.d.time)
            sig["head_w"].append(h.head_w())
            sig["lean"].append(h.trunk_lean_deg())
            sig["neck"].append(h.neck_angle_deg())
            sig["tipv"].append(sp)
            sig["pel"].append(h.d.xpos[h.bid["pelvis"]].copy())
            sig["hcom"].append(h.d.xipos[h.bid["head"]].copy())
    P = pulses(h.log_c)
    out = dict(clip=clip, weapon=weapon, offset=offset, h=h, states=states, sig={k: np.array(v) for k, v in sig.items()}, pulses=[pulse_stats(h, p) for p in P], n_pulses=len(P))
    s = out["sig"]
    if P:
        for p in out["pulses"]:      # striker speed over the 17 ms before each pulse starts
            w_ = (s["t"] >= p["t0"] - 0.017) & (s["t"] <= p["t0"] + 0.001)
            p["v_in"] = float(s["tipv"][w_].max()) if w_.any() else 0.0
        di = int(np.argmax([p["v_in"] for p in out["pulses"]]))     # the impact = the pulse the striker arrives at fastest (slow ones are pushes)
        out["dom"] = di
        p0 = out["pulses"][di]
        tt = p0["t0"]
        i0 = int(np.searchsorted(s["t"], tt))
        a = max(0, i0 - 3)
        win = (s["t"] >= tt - 0.05) & (s["t"] <= tt + 0.6)
        base = max(0, int(np.searchsorted(s["t"], tt - 0.05)) - 1)
        out["head_w_peak"] = float(s["head_w"][win].max())
        out["neck_peak_deg"] = float(s["neck"][win].max() - s["neck"][base])
        out["lean_peak_deg"] = float(np.abs(s["lean"][win] - s["lean"][base]).max())
        out["lean_signed"] = float((s["lean"][win] - s["lean"][base])[np.argmax(np.abs(s["lean"][win] - s["lean"][base]))])
        v = np.gradient(s["hcom"], 1 / 60, axis=0)
        acc = np.gradient(v, 1 / 60, axis=0)
        out["head_acc_g"] = float(np.linalg.norm(acc[win], axis=1).max() / 9.81)
        # speed of the striker just before the pulse (sim)
        out["speed_at_hit"] = p0["v_in"]
        out["pelvis_move"] = float(np.linalg.norm((s["pel"][win][-1] - s["pel"][win][0])[[0, 2]]))
    out["fell"] = h.fallen()
    return out


if __name__ == "__main__":
    import time
    t0 = time.time()
    r = run(sys.argv[1] if len(sys.argv) > 1 else "swing_fore", weapon=(len(sys.argv) < 3 or sys.argv[2] != "fist"), keep_states=False)
    for p in r["pulses"]:
        print({k: (np.round(v, 3) if not isinstance(v, (str, dict)) else v) for k, v in p.items() if k != "share"})
    print({k: v for k, v in r.items() if k in ("head_w_peak", "neck_peak_deg", "lean_peak_deg", "head_acc_g", "speed_at_hit", "fell", "n_pulses")}, f"{time.time()-t0:.1f}s")
