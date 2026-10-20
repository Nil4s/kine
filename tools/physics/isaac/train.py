"""Train + evaluate Kine push recovery with RSL-RL PPO on Isaac Lab.

One command (from the worktree root, any shell):
    D:/isaac-venv/Scripts/python.exe tools/physics/isaac/train.py --num_envs 512 --iters 300
Needs D:/kine-physics/{kine_humanoid/kine_humanoid.usd, stance.npz} (python tools/physics/isaac/import_usd.py and
export_stance.py make them). Vulkan is switched off (it crashes in rtx.scenedb on this box).

Output: D:/kine-physics/runs/<name>/ (model_*.pt, results.json). Prints: steps/s, mean episode length before/after
(training push distribution, repeated pushes), survival vs single-impulse size before/after.
"""
import argparse
import json
import os
import sys
import time

os.environ.setdefault("OMNI_KIT_ACCEPT_EULA", "YES")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import h5py  # noqa: F401,E402  must load BEFORE Kit: the windowed Kit loads its own HDF5 DLL and h5py then fails (DLL load failed _errors)
from isaaclab.app import AppLauncher  # noqa: E402

p = argparse.ArgumentParser()
p.add_argument("--num_envs", type=int, default=256)
p.add_argument("--iters", type=int, default=200)
p.add_argument("--steps", type=int, default=24, help="rollout length per env per iteration")
p.add_argument("--name", type=str, default="push")
p.add_argument("--max_impulse", type=float, default=40.0, help="FINAL training push max, U[0, this] N s (curriculum starts at 15)")
p.add_argument("--eval_envs", type=int, default=0, help="0: same as num_envs")
p.add_argument("--resume", type=str, default="")
p.add_argument("--eval_only", action="store_true", help="load --resume, measure single-push survival at 0.001/30 N s only, exit")
p.add_argument("--skip_baseline", action="store_true")
AppLauncher.add_app_launcher_args(p)
p.add_argument("--show", action="store_true", help="open the Isaac window to watch the training (slower)")
_a = sys.argv[1:] + ["--kit_args=--/app/vulkan=false"]   # Vulkan crashes in rtx.scenedb on this machine: DirectX 12 only
if "--show" not in _a:
    _a.append("--headless")
args = p.parse_args(_a)
app = AppLauncher(args).app

import torch  # noqa: E402
from rsl_rl.runners import OnPolicyRunner  # noqa: E402

from isaaclab_rl.rsl_rl import (RslRlOnPolicyRunnerCfg, RslRlPpoActorCriticCfg, RslRlPpoAlgorithmCfg,  # noqa: E402
                                RslRlVecEnvWrapper)
from push_env import PushEnv, PushEnvCfg  # noqa: E402

OUT = f"D:/kine-physics/runs/{args.name}"
os.makedirs(OUT, exist_ok=True)

cfg = PushEnvCfg()
cfg.scene.num_envs = args.num_envs
cfg.push_max_impulse = args.max_impulse
if "--show" in _a:   # the windowed viewport froze with Fabric on (see play.py): render from USD and frame the grid
    cfg.sim.use_fabric = False
    cfg.scene.clone_in_fabric = False
env = RslRlVecEnvWrapper(PushEnv(cfg))
U = env.unwrapped
M = 75.0

agent = RslRlOnPolicyRunnerCfg(
    num_steps_per_env=args.steps, max_iterations=args.iters, save_interval=50, experiment_name="kine_push",
    policy=RslRlPpoActorCriticCfg(init_noise_std=0.3, actor_obs_normalization=True, critic_obs_normalization=True,
                                  actor_hidden_dims=[256, 128, 64], critic_hidden_dims=[256, 128, 64], activation="elu"),
    algorithm=RslRlPpoAlgorithmCfg(value_loss_coef=1.0, use_clipped_value_loss=True, clip_param=0.2, entropy_coef=0.002,
                                   num_learning_epochs=5, num_mini_batches=4, learning_rate=3e-4, schedule="adaptive",
                                   gamma=0.99, lam=0.95, desired_kl=0.01, max_grad_norm=1.0),
)
runner = OnPolicyRunner(env, agent.to_dict(), log_dir=OUT, device=U.device)
if args.resume:
    runner.load(args.resume)


@torch.inference_mode()
def evaluate(policy, steps, impulse=None, once=False):
    """one episode per env from reset. impulse: fixed J (N s) for every push, else the training distribution.
    once: a single push per episode (first at 0.5-1.5 s). Returns (mean episode length s, survival fraction)."""
    c = U.cfg
    saved = (c.fixed_impulse, c.push_interval_s)
    U.eval_mode = True
    c.fixed_impulse = impulse if impulse is not None else -1.0
    c.push_interval_s = (1e6, 1e6) if once else saved[1]
    obs, _ = env.reset()
    n = U.num_envs
    done_at = torch.full((n,), float(steps), device=U.device)
    fell = torch.zeros(n, dtype=torch.bool, device=U.device)
    finished = torch.zeros(n, dtype=torch.bool, device=U.device)
    for t in range(steps):
        a = policy(obs) if policy is not None else torch.zeros(n, U.cfg.action_space, device=U.device)
        obs, _, dones, _ = env.step(a)
        newly = dones.bool() & ~finished
        done_at[newly] = t + 1
        fell |= newly & U.reset_terminated
        finished |= newly
        if bool(finished.all()):
            break
    c.fixed_impulse, c.push_interval_s = saved
    U.eval_mode = False
    dt = U.cfg.sim.dt * U.cfg.decimation
    return float(done_at.mean() * dt), float(1.0 - fell.float().mean())


JS = [0.001, 10, 20, 30, 40, 50, 60, 80]
EP_STEPS = int(U.cfg.episode_length_s / (U.cfg.sim.dt * U.cfg.decimation))
SINGLE_STEPS = int(6.0 / (U.cfg.sim.dt * U.cfg.decimation))


def full_eval(policy, tag):
    out = {"tag": tag}
    out["ep_len_train_pushes_s"], out["survive_train_pushes"] = evaluate(policy, EP_STEPS)
    out["single_push_survival"] = {j: evaluate(policy, SINGLE_STEPS, impulse=float(j), once=True) for j in JS}
    print("EVAL", json.dumps(out), flush=True)
    return out


if args.eval_only:
    pol = runner.get_inference_policy(device=U.device)
    print("QUICK", {j: evaluate(pol, SINGLE_STEPS, impulse=float(j), once=True) for j in (0.001, 30)}, flush=True)
    env.close(); app.close(); sys.exit(0)

res = {"num_envs": args.num_envs, "iters": args.iters, "steps_per_iter": args.steps, "max_impulse": args.max_impulse}
if not args.skip_baseline:
    res["before_zero_action_PD_hold"] = full_eval(None, "PD hold (action 0)")
    res["before_random_init_policy"] = full_eval(runner.get_inference_policy(device=U.device), "untrained policy")

t0 = time.time()
runner.learn(num_learning_iterations=args.iters, init_at_random_ep_len=True)
dt = time.time() - t0
sps = args.iters * args.steps * args.num_envs / dt
res["train_seconds"] = dt
res["env_steps_per_s"] = sps
print(f"TRAIN {args.iters} iters, {args.num_envs} envs: {dt:.0f} s, {sps:.0f} env steps/s ({sps*U.cfg.decimation*U.cfg.sim.dt:.0f} sim s/s)", flush=True)
runner.save(os.path.join(OUT, "model_final.pt"))
res["after"] = full_eval(runner.get_inference_policy(device=U.device), "trained policy")
res["J_hof_note"] = "MuJoCo controller fell from 33.7 N s up (tools/physics README)"
json.dump(res, open(os.path.join(OUT, "results.json"), "w"), indent=1)
env.close()
app.close()
