# tools/physics: Kine hit reaction in MuJoCo (stage 1, no RL)

Python 3.11, mujoco 3.16, scipy, Pillow. No AMASS / LAFAN1 / SMPL: only `data/skeleton.json`, `data/body_limits.json` and `scenes/hit_react.json` (card "ready"), all read only.

| file | what |
|---|---|
| `kine_mjcf.py` | skeleton + limits -> MJCF (75 kg, de Leva 1996 masses, capsules, box feet); `python tools/physics/kine_mjcf.py` prints mass and height |
| `sim.py` | stance PD + XCoM balance (Hof 2005) + capture-point stepping + `hit(body, J, dir)` |
| `measure.py` | the bars and numbers (bars written in its docstring before measuring) |
| `export.py` | records 3 hits, writes `hit_*.bvh` (Kine names, imports exactly) + contact sheet |
| `show.py` | interactive viewer |
| `check_bvh.gd` | headless Godot: does `BvhImport` read the file |

## Look at it (one command)
`python tools/physics/show.py` (from the worktree root). It stands and is hit every 3 s (head, chest, stomach, shoulder; light then hard; the direction rotates). In the viewer: double-click a body to select it, **Ctrl + right-drag** pushes it with a force. The free camera of MuJoCo is Z-up and Kine is Y-up, so the script uses the fixed camera "view" (follows the COM). Space pauses.

## Limits (honest)
- Small and medium hits recover in place. Stepping starts but does NOT recover: from 0.75 x J_hof upward the body falls (see numbers in the report). Cause (best guess): the wide fighting stance (feet 0.38 m apart) cannot unload a foot in time (COM is 0.19 m off each foot), and the stance leg targets after a step are re-centred crudely. Two real attempts (weight-shift-free step, slide step) failed; stopped per the time cap.
- Lateral balance uses the same law through hip/ankle joints; no hip/arm angular-momentum strategy. Hands hold no weapon (the card's bat is ignored). Fingers are lumped into the hand mass.
- De Leva digits typed from memory; Pai & Patton boundary values from the search abstract (normalised to height); Horak & Nashner / Maurer & Peterka only cited qualitatively.

## Stage 2 (not started): RL tracking + random pushes (DeepMimic / KungfuBot style)
Estimates, not measurements:
- Policy: PPO, obs = joint pos/vel + root orientation + target pose of the reference clip (Kine's own scenes as references) + phase; action = PD target offsets. Reward: exp(-err/sigma) on joint pos/vel, body pos, root; penalties on torque, action rate, falls (KungfuBot, NeurIPS 2025, Table 6 weights as a start). Random pushes every 5-10 s, impulse range 0..60 N s, friction 0.2-1.2, mass +-10 %, delay 0-40 ms.
- Envs / steps: 2048-4096 parallel envs, 1-2 billion env steps for one clip family. KungfuBot reports 27 h on one RTX 4090 for one policy; a 3070 8 GB is roughly 2-3x slower and VRAM limits envs to about 2048 in Isaac Lab (MJX is also possible with the same MJCF; this model has 47 hinges, so cost is about a G1's): expect 40-70 h per policy, so train short clips (1-2 s hits) first, 4-8 h each.
- Isaac Lab path: convert this MJCF to USD (Isaac Sim MJCF importer; articulation with the same 47 hinges, PD actuators with the kp/kv/torque limits in `kine_mjcf.py`), use the DirectRL humanoid-AMP / tracking task template, reference clips from Kine's BVH export (`tools/export_bvh.gd`), sim-to-sim check back in MuJoCo with `sim.py`. Isaac Sim needs Windows/Linux + RTX driver, about 30 GB disk.
- Output back into Kine: roll out the policy with random hits, record with `export.py`'s BVH writer, import as cards.
