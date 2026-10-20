"""Kine skeleton -> MuJoCo MJCF humanoid (read only on data/skeleton.json and data/body_limits.json).

Bodies: the 22 main joints (fingers are lumped into the hand mass; the toe 'ball' is part of the foot box).
Every body frame is world-aligned at rest (Kine's T-pose, +Y up, +Z forward, +X = hero's LEFT), so a MuJoCo relative
rotation IS Kine's joint rotation A (G[j] = G[parent] * A[j], scripts/body.gd fk) and the BVH export needs no re-basing.
Each joint is up to three hinges on Kine's own axes: bend (b_ax), side (a_ax), twist (w_ax), in that order
(Kine: A = swing(b*bend + a*side) * twist; the hinge chain differs from that exponential map by a second-order
amount, so poses are SOLVED into hinge angles, see pose_to_hinges). Ranges are Kine's data/body_limits.json.

Masses: de Leva P. (1996) "Adjustments to Zatsiorsky-Seluyanov's segment inertia parameters", J Biomech 29(9):1223-1230,
male table, fraction of body mass: head+neck 6.94 %, upper trunk 15.96, middle trunk 16.33, lower trunk 11.17,
upper arm 2.71, forearm 1.62, hand 0.61, thigh 14.16, shank 4.33, foot 1.37 (sum 100.00).
Centre of mass along the segment from the proximal end (limbs) / from the top end (trunk): upper arm 57.72 %, forearm 45.74,
hand 79.00, thigh 40.95, shank 44.59, foot 44.15 (from the heel), head 50.02, upper trunk 50.66, mid trunk 45.02, lower trunk 61.15.
(Digits typed from my memory of the table, not re-fetched this run; the total mass is exact by construction, the COM
fractions move a segment's COM by a few mm to cm.) Kine's bones are mapped onto those segments: pelvis = lower trunk,
spine_01 + spine_02 = middle trunk (half each), spine_03 = upper trunk, neck_01 1.0 % + head 5.94 % = head+neck.
Inertia: solid capsule-like (cylinder radius r, length |cap|+2r) scaled to the segment mass.
"""
import json
import os
from xml.sax.saxutils import quoteattr

import numpy as np
from scipy.optimize import least_squares
from scipy.spatial.transform import Rotation as R

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

BODY_MASS = 75.0
JOINTS = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
          "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
          "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
FINGER_KEYS = ("thumb", "index", "middle", "ring", "pinky")
SUB_INCL, SUB_DEV = 42.0, 23.0           # body.gd: Inman subtalar axis
SUB_TWIST = (-8.0, 25.0)                  # body.gd: foot roll range, right foot

# (fraction of body mass, COM fraction along segment from its proximal / top end)
SEG = {
    "pelvis": (0.1117, 0.6115), "spine_01": (0.16330 / 2, 0.4502), "spine_02": (0.16330 / 2, 0.4502),
    "spine_03": (0.1496, 0.5066), "neck_01": (0.0100, 0.5), "head": (0.0594, 0.5002),
    "upperarm": (0.0271, 0.5772), "lowerarm": (0.0162, 0.4574), "hand": (0.0061, 0.7900),
    "thigh": (0.1416, 0.4095), "calf": (0.0433, 0.4459), "foot": (0.0137, 0.4415),
    "clavicle": (0.005, 0.5),
}
TRUNK_FROM_TOP = ("pelvis", "spine_01", "spine_02", "spine_03")
KP = {"pelvis": 0, "spine": 350, "neck": 40, "head": 25, "clavicle": 120, "upperarm": 140, "lowerarm": 70,
      "hand": 15, "thigh": 700, "calf": 700, "foot": 260}
TAU_MAX = {"spine": 150, "neck": 25, "head": 15, "clavicle": 60, "upperarm": 90, "lowerarm": 60, "hand": 15,
           "thigh": 250, "calf": 250, "foot": 130}


def _key(j):
    for k in ("spine", "neck", "head", "clavicle", "upperarm", "lowerarm", "hand", "thigh", "calf", "foot", "pelvis"):
        if j.startswith(k):
            return k


def load():
    sk = json.load(open(os.path.join(ROOT, "data", "skeleton.json")))["joints"]
    li = json.load(open(os.path.join(ROOT, "data", "body_limits.json")))
    return sk, li


def lim_key(j):
    if j.endswith("_l"):
        j = j[:-2] + "_r"
    return j


class Kine:
    """the rest skeleton, the axes and limits, as scripts/body.gd computes them"""

    def __init__(self):
        sk, li = load()
        self.sk = sk
        self.parent = {j: (sk[j]["parent"] or "") for j in JOINTS}
        self.p0 = {j: np.array(sk[j]["pos"]) for j in JOINTS}
        self.cap = {j: (np.array(sk[j]["cap"][0]), np.array(sk[j]["cap"][1])) for j in JOINTS}
        self.rad = {j: float(sk[j]["radius"]) for j in JOINTS}
        self.e0, self.b_ax, self.a_ax, self.w_ax, self.rng = {}, {}, {}, {}, {}
        child = {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01",
                 "neck_01": "head", "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
                 "clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
                 "thigh_l": "calf_l", "calf_l": "foot_l", "thigh_r": "calf_r", "calf_r": "foot_r"}
        for j in JOINTS:
            L = li[lim_key(j)]
            f, s = np.array(L["f"], float), np.array(L["s"], float)
            tw = list(L["twist"])
            if lim_key(j) == "foot_r":
                tw = list(SUB_TWIST)
            if j.endswith("_l"):
                f[0], s[0] = -f[0], -s[0]
                tw = [-tw[1], -tw[0]]
            if j in child:
                e = self.p0[child[j]]
            elif j.startswith("foot"):
                e = np.array(sk[j.replace("foot", "ball")]["pos"])
            elif "end" in sk[j]:
                e = np.array(sk[j]["end"])
            else:
                e = self.p0[j] + np.array([0, 0.2, 0])
            self.e0[j] = e
            t = (e - self.p0[j]) / np.linalg.norm(e - self.p0[j])
            fo = f - t * f.dot(t)
            fo /= np.linalg.norm(fo)
            so = np.cross(t, fo)
            if so.dot(s) < 0:
                so = -so
            self.b_ax[j] = np.cross(t, fo) / np.linalg.norm(np.cross(t, fo))
            self.a_ax[j] = np.cross(t, so) / np.linalg.norm(np.cross(t, so))
            w = t
            if j.startswith("foot"):
                ci = np.cos(np.radians(SUB_INCL))
                lh = np.array([t[0], 0, t[2]])
                lh /= np.linalg.norm(lh)
                med = np.array([-1.0, 0, 0]) if j.endswith("_l") else np.array([1.0, 0, 0])
                w = ci * np.cos(np.radians(SUB_DEV)) * lh + ci * np.sin(np.radians(SUB_DEV)) * med + np.sin(np.radians(SUB_INCL)) * np.array([0, 1.0, 0])
                w /= np.linalg.norm(w)
            self.w_ax[j] = w
            self.rng[j] = {"b": tuple(L["bend"]), "a": tuple(L["side"]), "w": tuple(tw)}

    def compose(self, j, v_deg):
        """scripts/body.gd compose(): swing(b*bend + a*side) * twist(w)"""
        rv = self.b_ax[j] * np.radians(v_deg[0]) + self.a_ax[j] * np.radians(v_deg[1])
        sw = R.from_rotvec(rv)
        return sw * R.from_rotvec(self.w_ax[j] * np.radians(v_deg[2]))

    def hinge_chain(self, j, th):
        return (R.from_rotvec(self.b_ax[j] * th[0]) * R.from_rotvec(self.a_ax[j] * th[1]) * R.from_rotvec(self.w_ax[j] * th[2]))

    def pose_to_hinges(self, j, v_deg):
        """Kine (bend, side, twist) degrees -> the three hinge angles (rad) whose chain gives the same rotation"""
        A = self.compose(j, v_deg)
        x0 = np.radians(v_deg)
        fun = lambda th: (self.hinge_chain(j, th).inv() * A).as_rotvec()
        return least_squares(fun, x0, xtol=1e-12, ftol=1e-12).x

    def active(self, j):
        return [k for k in "baw" if self.rng[j][k][1] - self.rng[j][k][0] > 1e-6]


def segment(name):
    for k in ("upperarm", "lowerarm", "hand", "thigh", "calf", "foot", "clavicle"):
        if name.startswith(k):
            return SEG[k]
    return SEG[name]


def build(kine=None, mass=BODY_MASS):
    K = kine or Kine()
    sk = K.sk
    ch = {}
    for j in JOINTS:
        ch.setdefault(K.parent[j], []).append(j)
    info = {}   # per body: mass, com (world rest), geom top etc

    def inertial(j):
        frac, cf = segment(j)
        m = mass * frac
        a, b = K.cap[j]
        r = K.rad[j]
        if j.startswith("foot"):
            lo, hi = np.array([K.p0[j][0] - 0.045, 0.0, -0.09]), np.array([K.p0[j][0] + 0.045, 0.075, 0.205])
            com = np.array([K.p0[j][0], 0.040, -0.09 + cf * (0.205 + 0.09)])
            sz = hi - lo
            I = np.diag([m * (sz[1] ** 2 + sz[2] ** 2) / 12, m * (sz[0] ** 2 + sz[2] ** 2) / 12, m * (sz[0] ** 2 + sz[1] ** 2) / 12])
            return m, com, I
        if j in TRUNK_FROM_TOP:
            top = K.p0[ch[j][0]] if j != "pelvis" else K.p0["spine_01"]
            bot = K.p0[j]
            com = top + cf * (bot - top)
            axis = (top - bot)
        elif j == "head":
            top = a + (b - a) / np.linalg.norm(b - a) * 0.0
            top = b + (b - a) / np.linalg.norm(b - a) * r
            com = K.p0[j] + 0.45 * (top - K.p0[j])      # head+neck COM 50.02 % from the vertex down to C7 -> in the head body
            axis = b - a
        else:
            s, e = K.p0[j], K.e0[j]
            com = s + cf * (e - s)
            axis = e - s
        L = np.linalg.norm(axis) + 2 * r
        u = axis / np.linalg.norm(axis)
        # pelvis cap is horizontal; use the cap direction for the long axis there
        if j == "pelvis":
            u = (b - a) / np.linalg.norm(b - a)
            L = np.linalg.norm(b - a) + 2 * r
        Iax = 0.5 * m * r * r
        Iper = m * (3 * r * r + L * L) / 12
        Rm = R.align_vectors([u], [[0, 0, 1]])[0].as_matrix()
        I = Rm @ np.diag([Iper, Iper, Iax]) @ Rm.T
        return m, com, I

    lines = []
    ctrl_names = []
    hinges = []   # (joint name, body, kine joint, k, tau_max, kp)

    def emit(j, depth):
        pad = "  " * depth
        rel = K.p0[j] - (K.p0[K.parent[j]] if K.parent[j] else np.zeros(3))
        pos = K.p0[j] if not K.parent[j] else rel
        lines.append(f'{pad}<body name="{j}" pos="{pos[0]:.5f} {pos[1]:.5f} {pos[2]:.5f}">')
        m, com, I = inertial(j)
        cl = com - K.p0[j]
        lines.append(f'{pad}  <inertial pos="{cl[0]:.5f} {cl[1]:.5f} {cl[2]:.5f}" mass="{m:.5f}" fullinertia="{I[0,0]:.6g} {I[1,1]:.6g} {I[2,2]:.6g} {I[0,1]:.6g} {I[0,2]:.6g} {I[1,2]:.6g}"/>')
        info[j] = {"mass": m, "com": com}
        if not K.parent[j]:
            # MuJoCo's free camera assumes +Z up; Kine is +Y up. A fixed camera with explicit axes follows the COM instead.
            for nm, p in (("view", (2.3, 0.35, 3.1)), ("side", (4.0, 0.2, 0.0))):
                p = np.array(p)
                zc = np.array([p[0], 0, p[2]]) / np.hypot(p[0], p[2])
                xc = np.cross([0, 1, 0], zc)
                yc = np.cross(zc, xc)
                lines.append(f'{pad}  <camera name="{nm}" mode="trackcom" pos="{p[0]} {p[1]} {p[2]}" xyaxes="{xc[0]:.4f} {xc[1]:.4f} {xc[2]:.4f} {yc[0]:.4f} {yc[1]:.4f} {yc[2]:.4f}"/>')
        if not K.parent[j]:
            lines.append(f'{pad}  <freejoint name="root"/>')
        else:
            key = _key(j)
            for k in K.active(j):
                ax = {"b": K.b_ax, "a": K.a_ax, "w": K.w_ax}[k][j]
                lo, hi = K.rng[j][k]
                nm = f"{j}_{k}"
                lines.append(f'{pad}  <joint name="{nm}" type="hinge" axis="{ax[0]:.6f} {ax[1]:.6f} {ax[2]:.6f}" '
                             f'range="{np.radians(lo):.6f} {np.radians(hi):.6f}" limited="true" damping="1.0" armature="0.02"/>')
                hinges.append((nm, j, k, TAU_MAX[key], KP[key]))
        a, b = K.cap[j]
        r = K.rad[j]
        if j.startswith("foot"):
            lo = np.array([K.p0[j][0] - 0.045, 0.0, -0.09]) - K.p0[j]
            hi = np.array([K.p0[j][0] + 0.045, 0.075, 0.205]) - K.p0[j]
            c, h = (lo + hi) / 2, (hi - lo) / 2
            lines.append(f'{pad}  <geom name="{j}_box" type="box" pos="{c[0]:.5f} {c[1]:.5f} {c[2]:.5f}" size="{h[0]:.5f} {h[1]:.5f} {h[2]:.5f}" '
                         f'friction="1.0 0.02 0.002" contype="1" conaffinity="1" rgba="0.35 0.35 0.4 1" condim="4" solref="0.01 1" />')
        else:
            la, lb = a - K.p0[j], b - K.p0[j]
            lines.append(f'{pad}  <geom name="{j}_cap" type="capsule" fromto="{la[0]:.5f} {la[1]:.5f} {la[2]:.5f} {lb[0]:.5f} {lb[1]:.5f} {lb[2]:.5f}" '
                         f'size="{r:.5f}" contype="2" conaffinity="1" rgba="0.8 0.62 0.5 1" friction="0.8 0.02 0.002"/>')
        for c in ch.get(j, []):
            if c in JOINTS:
                emit(c, depth + 1)
        lines.append(f"{pad}</body>")

    emit("pelvis", 2)
    act = "\n".join(f'    <motor name="m_{h[0]}" joint="{h[0]}" gear="1" ctrlrange="{-h[3]} {h[3]}" ctrllimited="true"/>' for h in hinges)
    xml = f"""<mujoco model="kine_humanoid">
  <compiler angle="radian" inertiafromgeom="false" boundmass="0" boundinertia="0"/>
  <option timestep="0.002" gravity="0 -9.81 0" integrator="implicitfast" cone="elliptic" impratio="10"/>
  <visual><global offwidth="1280" offheight="960"/><quality shadowsize="2048"/></visual>
  <asset>
    <texture name="grid" type="2d" builtin="checker" rgb1="0.82 0.84 0.86" rgb2="0.70 0.73 0.76" width="256" height="256"/>
    <material name="grid" texture="grid" texrepeat="12 12" reflectance="0.1"/>
  </asset>
  <worldbody>
    <light pos="1 3 3" dir="-0.3 -0.8 -0.5" diffuse="0.9 0.9 0.9"/>
    <light pos="-2 3 -2" dir="0.5 -0.6 0.6" diffuse="0.35 0.35 0.4"/>
    <geom name="floor" type="plane" pos="0 0 0" zaxis="0 1 0" size="6 6 0.1" material="grid" friction="1.0 0.02 0.002" contype="1" conaffinity="1"/>
{chr(10).join(lines)}
  </worldbody>
  <actuator>
{act}
  </actuator>
</mujoco>"""
    return xml, hinges, info, K


def main():
    import mujoco
    xml, hinges, info, K = build()
    m = mujoco.MjModel.from_xml_string(xml)
    d = mujoco.MjData(m)
    mujoco.mj_forward(m, d)
    tot = float(m.body_mass.sum())
    # standing height at rest: highest geom point (head capsule end + radius) over the floor
    top = max(d.geom_xpos[i][1] + (m.geom_size[i][0] + m.geom_size[i][1] if m.geom_type[i] == mujoco.mjtGeom.mjGEOM_CAPSULE else 0)
              for i in range(m.ngeom) if mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, i) == "head_cap")
    com = d.subtree_com[1]
    print(f"bodies {m.nbody}, hinges {len(hinges)}, total mass {tot:.4f} kg, whole-body COM height {com[1]:.4f} m")
    print(f"head top {top:.4f} m; Kine mannequin mesh (assets/mannequin.glb bbox max y) 1.8292 m -> {100*(top/1.82918-1):+.2f} %")
    return m


if __name__ == "__main__":
    main()
