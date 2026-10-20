"""Watch the Kine push-recovery policy live in the Isaac window (inference only, real time).

    D:/isaac-venv/Scripts/python.exe tools/physics/isaac/play.py --run D:/kine-physics/runs/run3
Reloads the newest model_*.pt of --run every --reload_s seconds, so you see the policy improve while a headless
train.py writes checkpoints there. Red bars = pushes (bar points along the force, tip on the pushed body).
"""
import argparse
import glob
import os
import sys
import time

os.environ.setdefault("OMNI_KIT_ACCEPT_EULA", "YES")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import h5py  # noqa: F401,E402  (before Kit, see train.py)
from isaaclab.app import AppLauncher  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument("--run", type=str, default="D:/kine-physics/runs/run3")
p.add_argument("--fallback", type=str, default="D:/kine-physics/runs/watch2", help="used until --run has a checkpoint")
p.add_argument("--checkpoint", type=str, default="", help="fixed file instead of newest in --run")
p.add_argument("--num_envs", type=int, default=16)
p.add_argument("--reload_s", type=float, default=120.0)
p.add_argument("--max_impulse", type=float, default=40.0)
p.add_argument("--speed", type=float, default=1.0, help="1.0 = real time")
p.add_argument("--fabric", action="store_true", help="keep Fabric on (default off: Fabric made the viewport stale)")
AppLauncher.add_app_launcher_args(p)
_a = sys.argv[1:] + ["--kit_args=--/app/vulkan=false"]
args = p.parse_args(_a)
args.headless = False
app = AppLauncher(args).app

import torch  # noqa: E402
from rsl_rl.runners import OnPolicyRunner  # noqa: E402
import isaaclab.sim as sim_utils  # noqa: E402
from isaaclab.markers import VisualizationMarkers, VisualizationMarkersCfg  # noqa: E402
from isaaclab_rl.rsl_rl import (RslRlOnPolicyRunnerCfg, RslRlPpoActorCriticCfg, RslRlPpoAlgorithmCfg,  # noqa: E402
                                RslRlVecEnvWrapper)
from push_env import PushEnv, PushEnvCfg  # noqa: E402

cfg = PushEnvCfg()
cfg.scene.num_envs = args.num_envs
cfg.push_max_impulse = args.max_impulse
cfg.curriculum = False
cfg.sim.use_fabric = args.fabric
cfg.scene.clone_in_fabric = args.fabric
env = RslRlVecEnvWrapper(PushEnv(cfg))
U = env.unwrapped
dt = U.cfg.sim.dt * U.cfg.decimation

agent = RslRlOnPolicyRunnerCfg(
    num_steps_per_env=24, max_iterations=1, save_interval=10**9, experiment_name="kine_push",
    policy=RslRlPpoActorCriticCfg(init_noise_std=0.3, actor_obs_normalization=True, critic_obs_normalization=True,
                                  actor_hidden_dims=[256, 128, 64], critic_hidden_dims=[256, 128, 64], activation="elu"),
    algorithm=RslRlPpoAlgorithmCfg(value_loss_coef=1.0, use_clipped_value_loss=True, clip_param=0.2, entropy_coef=0.002,
                                   num_learning_epochs=5, num_mini_batches=4, learning_rate=3e-4, schedule="adaptive",
                                   gamma=0.99, lam=0.95, desired_kl=0.01, max_grad_norm=1.0),
)
runner = OnPolicyRunner(env, agent.to_dict(), log_dir=None, device=U.device)


def newest():
    if args.checkpoint:
        return args.checkpoint
    fs = glob.glob(os.path.join(args.run, "model_*.pt")) or glob.glob(os.path.join(args.fallback, "model_*.pt"))
    return max(fs, key=os.path.getmtime) if fs else ""


loaded = ""


def reload():
    global loaded
    f = newest()
    if f and f != loaded:
        for _ in range(3):
            try:
                runner.load(f)
                loaded = f
                print(f"PLAY loaded {f}", flush=True)
                break
            except Exception as e:  # file may be mid-write
                print("PLAY load retry", e, flush=True)
                time.sleep(1.0)


reload()
policy = runner.get_inference_policy(device=U.device)

# camera: frame the whole grid (envs sit on a grid from (0,0), spacing 3 m)
side = int(round(args.num_envs ** 0.5))
cx = cy = (side - 1) * U.cfg.scene.env_spacing / 2
span = side * U.cfg.scene.env_spacing
eye = (cx, cy - 1.7 * span, 0.7 * span + 1.5)
look = (cx, cy, 0.9)


def set_cam():
    try:
        from isaacsim.core.utils.viewports import set_camera_view
        set_camera_view(eye=list(eye), target=list(look), camera_prim_path="/OmniverseKit_Persp")
    except Exception as e:
        print("PLAY set_camera_view failed", e, flush=True)
        U.sim.set_camera_view(eye, look)


set_cam()

bars = VisualizationMarkers(VisualizationMarkersCfg(prim_path="/Visuals/push", markers={"bar": sim_utils.CuboidCfg(
    size=(1.0, 0.05, 0.05), visual_material=sim_utils.PreviewSurfaceCfg(diffuse_color=(1.0, 0.05, 0.05)))}))
n = U.num_envs
shown_until = torch.zeros(n, device=U.device)
seen = U.n_pushes.clone()
pos = torch.zeros(n, 3, device=U.device)
quat = torch.zeros(n, 4, device=U.device)
quat[:, 0] = 1.0

obs = env.get_observations()
t_wall = time.time()
t_reload = time.time()
sim_t = 0.0
step = 0
with torch.inference_mode():
    while app.is_running():
        obs = env.step(policy(obs))[0]
        sim_t += dt
        step += 1
        new = U.n_pushes > seen
        if bool(new.any()):
            ids = new.nonzero(as_tuple=False).squeeze(-1)
            f = U.push_force[ids]
            d = f / f.norm(dim=-1, keepdim=True).clamp(min=1e-6)
            bpos = U.robot.data.body_pos_w[ids, U.push_body[ids]]
            pos[ids] = bpos - d * 0.55
            yaw = torch.atan2(d[:, 1], d[:, 0])
            quat[ids] = torch.stack([torch.cos(yaw / 2), torch.zeros_like(yaw), torch.zeros_like(yaw), torch.sin(yaw / 2)], -1)
            shown_until[ids] = sim_t + 0.6
            seen = U.n_pushes.clone()
        seen = torch.minimum(seen, U.n_pushes)   # episode reset zeroes the counter
        vis = shown_until > sim_t
        hidden = torch.tensor([0.0, 0.0, -50.0], device=U.device)
        bars.visualize(translations=torch.where(vis[:, None], pos, hidden), orientations=quat)
        if time.time() - t_reload > args.reload_s:
            t_reload = time.time()
            reload()
        if step % 600 == 0:
            set_cam()   # keep the framing if the user nudged nothing important
        lag = (t_wall + sim_t / args.speed) - time.time()
        if lag > 0:
            time.sleep(lag)
env.close()
app.close()
