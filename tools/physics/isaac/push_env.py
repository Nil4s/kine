"""Kine push-recovery environment for Isaac Lab (DirectRLEnv). Stage 2 groundwork, see tools/physics/README.md.

N Kine humanoids (the MuJoCo model of kine_mjcf.py, imported to USD by import_usd.py) hold the "ready" stance
(D:/kine-physics/stance.npz, exported from the MuJoCo sim). Every 1.5-3 s each env gets an impulse J (N s) on the head,
chest (spine_03), stomach (spine_01) or a shoulder (upperarm), horizontal, random direction, spread over 0.05 s exactly as
`sim.Humanoid.hit` does. Action = offset of the PD target around the stance (rad, scaled), implicit PD with the gains and
torque limits of kine_mjcf.py.
Reward = pose tracking exp(-|q - q_ref|^2 / s) + upright + alive - small action-rate and torque terms; terminate when the
pelvis is below 0.55 m or the head below 1.0 m (the MuJoCo `fallen()` test).
The MJCF is Y-up, Isaac is Z-up: the robot spawns rotated +90 deg about X (y -> z).
"""
from __future__ import annotations

import numpy as np
import torch

import isaaclab.sim as sim_utils
from isaaclab.actuators import ImplicitActuatorCfg
from isaaclab.assets import Articulation, ArticulationCfg
from isaaclab.envs import DirectRLEnv, DirectRLEnvCfg, ViewerCfg
from isaaclab.scene import InteractiveSceneCfg
from isaaclab.sim import SimulationCfg
from isaaclab.terrains import TerrainImporterCfg
from isaaclab.utils import configclass
from isaaclab.utils.math import quat_apply_inverse

KINE_DIR = "D:/kine-physics"
USD_PATH = f"{KINE_DIR}/kine_humanoid/kine_humanoid.usd"
ST = np.load(f"{KINE_DIR}/stance.npz")
NAMES = [str(n) for n in ST["names"]]
S2 = 0.5 ** 0.5
GAIN_LEG, GAIN_ARM = 8.0, 3.0


def _robot_cfg() -> ArticulationCfg:
    acts = {}
    for i, n in enumerate(NAMES):
        # MuJoCo's controller carried the body with a ground-force law (virtual model control) on top of the PD; here the
        # PD alone must hold 75 kg, so the leg / spine gains are x GAIN_LEG (torque limits unchanged), damping x sqrt.
        g = GAIN_LEG if n.startswith(("thigh", "calf", "foot", "spine")) else GAIN_ARM
        acts[n] = ImplicitActuatorCfg(joint_names_expr=[n], effort_limit_sim=float(ST["tmax"][i]),
                                      stiffness=float(ST["kp"][i]) * g, damping=float(ST["kv"][i]) * g ** 0.5)
    return ArticulationCfg(
        prim_path="/World/envs/env_.*/Robot",
        spawn=sim_utils.UsdFileCfg(
            usd_path=USD_PATH,
            rigid_props=sim_utils.RigidBodyPropertiesCfg(disable_gravity=False, max_depenetration_velocity=10.0),
            articulation_props=sim_utils.ArticulationRootPropertiesCfg(enabled_self_collisions=False,
                                                                       solver_position_iteration_count=8,
                                                                       solver_velocity_iteration_count=2),
        ),
        init_state=ArticulationCfg.InitialStateCfg(
            pos=(0.0, 0.0, float(ST["pelvis_y"]) + 0.01), rot=(S2, S2, 0.0, 0.0),
            joint_pos={n: float(ST["target"][i]) for i, n in enumerate(NAMES)}, joint_vel={".*": 0.0}),
        actuators=acts,
    )


@configclass
class PushEnvCfg(DirectRLEnvCfg):
    episode_length_s = 10.0
    decimation = 2
    action_scale = 0.15           # rad of RESIDUAL PD-target offset (around the stance) for action = 1
    action_space = len(NAMES)
    observation_space = 3 + 3 + 3 + 1 + 3 * len(NAMES)
    state_space = 0
    sim: SimulationCfg = SimulationCfg(dt=1 / 120, render_interval=decimation)
    terrain = TerrainImporterCfg(
        prim_path="/World/ground", terrain_type="plane", collision_group=-1,
        physics_material=sim_utils.RigidBodyMaterialCfg(friction_combine_mode="average", static_friction=1.0,
                                                        dynamic_friction=1.0, restitution=0.0))
    scene: InteractiveSceneCfg = InteractiveSceneCfg(num_envs=256, env_spacing=3.0, replicate_physics=True,
                                                     clone_in_fabric=True)
    robot: ArticulationCfg = _robot_cfg()
    viewer = ViewerCfg(eye=(11.0, -5.0, 5.5), lookat=(4.0, 3.0, 0.9))   # a few characters in frame (grid starts at 0,0)

    # pushes
    push_interval_s = (1.5, 3.0)
    push_duration_s = 0.05
    push_max_impulse = 40.0       # N s, FINAL upper end of the uniform draw
    curriculum = True             # push max starts at cur_start and grows with the survival rate
    cur_start, cur_step, cur_window = 15.0, 5.0, 1500   # N s; N s; resets per decision
    cur_up, cur_down = 0.8, 0.5   # survival fraction (timeouts / resets) to raise / lower
    push_min_impulse = 0.0
    fixed_impulse = -1.0          # >0: every push has exactly this size (evaluation)
    push_bodies = ("head", "spine_03", "spine_01", "upperarm_l", "upperarm_r")   # head, chest, stomach, shoulders
    first_push_delay_s = (0.5, 1.5)

    # rewards / terminations
    w_track, track_sigma = 1.0, 0.25
    w_up, w_alive = 1.0, 1.0
    w_term = 20.0                 # one-off penalty on falling (early termination)
    w_action_rate, w_torque = -0.02, -2e-6
    pelvis_min_z, head_min_z = 0.55, 1.0


class PushEnv(DirectRLEnv):
    cfg: PushEnvCfg

    def __init__(self, cfg: PushEnvCfg, render_mode: str | None = None, **kwargs):
        super().__init__(cfg, render_mode, **kwargs)
        dev = self.device
        self.jidx, _ = self.robot.find_joints(NAMES, preserve_order=True)
        self.q_ref = torch.tensor(ST["target"], dtype=torch.float32, device=dev)
        self.q_lo = torch.tensor(ST["lo"], dtype=torch.float32, device=dev)
        self.q_hi = torch.tensor(ST["hi"], dtype=torch.float32, device=dev)
        self.tmax = torch.tensor(ST["tmax"], dtype=torch.float32, device=dev)
        self.pelvis_id = self.robot.find_bodies("pelvis")[0][0]
        self.head_id = self.robot.find_bodies("head")[0][0]
        self.push_ids = torch.tensor([self.robot.find_bodies(b)[0][0] for b in self.cfg.push_bodies], device=dev)
        self.nbody = self.robot.num_bodies
        n = self.num_envs
        self.actions = torch.zeros(n, len(NAMES), device=dev)
        self.prev_actions = torch.zeros_like(self.actions)
        self.t_next_push = torch.zeros(n, device=dev)
        self.push_left = torch.zeros(n, dtype=torch.long, device=dev)
        self.push_force = torch.zeros(n, 3, device=dev)
        self.push_body = torch.zeros(n, dtype=torch.long, device=dev)
        self.up_vec = torch.tensor([0.0, 0.0, 1.0], device=dev).repeat(n, 1)
        self.grav_vec = torch.tensor([0.0, 0.0, -1.0], device=dev).repeat(n, 1)
        self.push_steps = max(1, round(self.cfg.push_duration_s / (self.cfg.sim.dt * self.cfg.decimation)))
        self.forces = torch.zeros(n, self.nbody, 3, device=dev)
        self.torques = torch.zeros(n, self.nbody, 3, device=dev)
        self.last_torque = torch.zeros(n, len(NAMES), device=dev)
        self.n_pushes = torch.zeros(n, device=dev)
        self.cur_max = self.cfg.cur_start if self.cfg.curriculum else self.cfg.push_max_impulse
        self.eval_mode = False
        self._cur_n = 0
        self._cur_ok = 0

    # ------------------------------------------------------------------ scene
    def _setup_scene(self):
        self.robot = Articulation(self.cfg.robot)
        self.cfg.terrain.num_envs = self.scene.cfg.num_envs
        self.cfg.terrain.env_spacing = self.scene.cfg.env_spacing
        self.terrain = self.cfg.terrain.class_type(self.cfg.terrain)
        self.scene.clone_environments(copy_from_source=False)
        self.scene.articulations["robot"] = self.robot
        light_cfg = sim_utils.DomeLightCfg(intensity=2000.0, color=(0.75, 0.75, 0.75))
        light_cfg.func("/World/Light", light_cfg)

    # ------------------------------------------------------------------ step
    def _pre_physics_step(self, actions: torch.Tensor):
        self.prev_actions = self.actions
        self.actions = actions.clamp(-1.0, 1.0)
        self._hit_source()
        self.robot.permanent_wrench_composer.set_forces_and_torques(forces=self.forces, torques=self.torques, is_global=True)

    def _apply_action(self):
        tgt = (self.q_ref + self.cfg.action_scale * self.actions).clamp(self.q_lo, self.q_hi)
        self.robot.set_joint_position_target(tgt, joint_ids=self.jidx)

    def _push_max(self):
        return self.cfg.push_max_impulse if (self.eval_mode or not self.cfg.curriculum) else min(self.cur_max, self.cfg.push_max_impulse)

    def _hit_source(self):
        """THE hit source: fills self.forces (num_envs, num_bodies, 3), world frame, N, for this control step.
        Here: random point impulses. To replace by an attacker's swing, spawn a second Articulation (attacker + weapon
        body) per env, drive it from a Kine strike clip, and return the contact forces on the defender (ContactSensor
        on the defender bodies with filter_prim_paths_expr = the weapon / attacker bodies, net_forces_w_history).
        Nothing else in this class needs to change."""
        c = self.cfg
        dt = c.sim.dt * c.decimation
        t = self.episode_length_buf.float() * dt
        start = (t >= self.t_next_push) & (self.push_left == 0)
        ids = start.nonzero(as_tuple=False).squeeze(-1)
        if len(ids) > 0:
            k = len(ids)
            if c.fixed_impulse > 0:
                J = torch.full((k,), c.fixed_impulse, device=self.device)
            else:
                J = c.push_min_impulse + (self._push_max() - c.push_min_impulse) * torch.rand(k, device=self.device)
            ang = torch.rand(k, device=self.device) * 2 * torch.pi
            f = J / c.push_duration_s
            self.push_force[ids] = torch.stack([f * torch.cos(ang), f * torch.sin(ang), torch.zeros_like(f)], dim=-1)
            self.push_body[ids] = self.push_ids[torch.randint(0, len(self.push_ids), (k,), device=self.device)]
            self.push_left[ids] = self.push_steps
            lo, hi = c.push_interval_s
            self.t_next_push[ids] = t[ids] + lo + (hi - lo) * torch.rand(k, device=self.device)
            self.n_pushes[ids] += 1
        act = self.push_left > 0
        self.forces.zero_()
        ar = act.nonzero(as_tuple=False).squeeze(-1)
        if len(ar) > 0:
            self.forces[ar, self.push_body[ar]] = self.push_force[ar]
        self.push_left = (self.push_left - 1).clamp(min=0)

    # ------------------------------------------------------------------ obs / reward / done
    def _get_observations(self) -> dict:
        d = self.robot.data
        q = d.joint_pos[:, self.jidx]
        qd = d.joint_vel[:, self.jidx]
        quat = d.root_quat_w
        pg = quat_apply_inverse(quat, self.grav_vec)
        obs = torch.cat([
            pg,
            quat_apply_inverse(quat, d.root_lin_vel_w),
            quat_apply_inverse(quat, d.root_ang_vel_w) * 0.25,
            d.root_pos_w[:, 2:3] - self.scene.env_origins[:, 2:3],
            q - self.q_ref, qd * 0.1, self.actions], dim=-1)
        return {"policy": obs}

    def _get_rewards(self) -> torch.Tensor:
        c = self.cfg
        d = self.robot.data
        q = d.joint_pos[:, self.jidx]
        err = ((q - self.q_ref) ** 2).sum(-1)
        track = torch.exp(-err / c.track_sigma)
        up = quat_apply_inverse(d.root_quat_w, self.grav_vec)[:, 2]   # -1 when upright (gravity points -z in body frame)
        upright = (-up).clamp(min=0.0)
        tq = d.applied_torque[:, self.jidx]
        r = (c.w_track * track + c.w_up * upright + c.w_alive
             + c.w_action_rate * ((self.actions - self.prev_actions) ** 2).sum(-1)
             + c.w_torque * (tq ** 2).sum(-1)
             - c.w_term * self.reset_terminated.float())
        return r

    def _get_dones(self):
        d = self.robot.data
        z0 = self.scene.env_origins[:, 2]
        fell = (d.body_pos_w[:, self.pelvis_id, 2] - z0 < self.cfg.pelvis_min_z) | (d.body_pos_w[:, self.head_id, 2] - z0 < self.cfg.head_min_z)
        time_out = self.episode_length_buf >= self.max_episode_length - 1
        return fell, time_out

    def _reset_idx(self, env_ids):
        if env_ids is None or len(env_ids) == self.num_envs:
            env_ids = self.robot._ALL_INDICES
        if self.cfg.curriculum and not self.eval_mode and len(env_ids) < self.num_envs:
            self._cur_n += len(env_ids)
            self._cur_ok += int(self.reset_time_outs[env_ids].sum())
            if self._cur_n >= self.cfg.cur_window:
                fr = self._cur_ok / self._cur_n
                if fr > self.cfg.cur_up:
                    self.cur_max = min(self.cfg.push_max_impulse, self.cur_max + self.cfg.cur_step)
                elif fr < self.cfg.cur_down:
                    self.cur_max = max(self.cfg.cur_start, self.cur_max - self.cfg.cur_step)
                print(f"CURRICULUM survival {fr:.2f} -> push max {self.cur_max:.0f} N s", flush=True)
                self._cur_n = self._cur_ok = 0
        self.robot.reset(env_ids)
        super()._reset_idx(env_ids)
        q = self.robot.data.default_joint_pos[env_ids].clone()
        qd = torch.zeros_like(q)
        root = self.robot.data.default_root_state[env_ids].clone()
        root[:, :3] += self.scene.env_origins[env_ids]
        self.robot.write_root_pose_to_sim(root[:, :7], env_ids)
        self.robot.write_root_velocity_to_sim(root[:, 7:], env_ids)
        self.robot.write_joint_state_to_sim(q, qd, None, env_ids)
        lo, hi = self.cfg.first_push_delay_s
        self.t_next_push[env_ids] = lo + (hi - lo) * torch.rand(len(env_ids), device=self.device)
        self.push_left[env_ids] = 0
        self.actions[env_ids] = 0.0
        self.prev_actions[env_ids] = 0.0
        self.n_pushes[env_ids] = 0.0
