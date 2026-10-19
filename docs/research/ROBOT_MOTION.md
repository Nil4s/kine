# How Chinese humanoids learned to move like humans, and what Kine can take

Researched 2026-10-19. Conventions: **[read]** = I fetched and read that page or abstract. **[inference]** = my reasoning, no source. Papers whose full text I only saw as abstract are marked "abstract only". Nothing here comes from UBTech, AgiBot, Fourier or EngineAI primary sources. I found none, so I make no claim about their specific training (GMR does list Fourier N1/GR3 and EngineAI PM01 as supported retarget targets [read]).

## 1. The pipeline

Every system I read follows the same four stages.

1. **Human motion source.**
   - Optical or IMU mocap: AMASS (SMPL-X), LAFAN1 (BVH), OptiTrack FBX, Xsens. [read, GMR README]
   - Monocular video, turned into SMPL by GVHMR: "World-Grounded Human Motion Recovery via Gravity-View Coordinates", Shen, Xia, Pi, Cen, Peng, Hu, Bao, Hu, Zhou, SIGGRAPH Asia 2024 (github.com/zju3dv/GVHMR). [read]
   - KungfuBot uses video via GVHMR plus AMASS and LAFAN. [read]
2. **Retargeting to the robot's skeleton.**
   - GMR, "Retargeting Matters: General Motion Retargeting for Humanoid Motion Tracking", Araujo, Ze, Xu, Wu, Liu, arXiv:2510.02252, 2025. [read, abstract]
   - It is IK built on mink and MuJoCo, runs in real time on CPU, has velocity limits on by default, and targets 18 robots. Code is MIT. [read, README]
   - Its finding: foot sliding, self-penetration and infeasible motion left in the reference "significantly reduce policy robustness", especially for dynamic or long clips. GMR beat PHC and ProtoMotions as retargeters and came close to a closed Unitree dataset. [read]
   - Unitree's public LAFAN1 retarget (H1, H1_2, G1) uses Interaction Mesh plus IK. Its own page says it "only models kinematic constraints, not dynamics or actuator limits, so robots can't perfectly execute the trajectories." [read, HF dataset page]
3. **Physics-based tracking by RL in simulation (DeepMimic lineage).**
   - DeepMimic: Peng, Abbeel, Levine, van de Panne, arXiv:1804.02717, 2018. A pose-tracking reward plus a task reward. [read]
   - Typical setup: Isaac Gym or Isaac Lab, PPO, thousands of parallel environments, one policy per clip, or one general policy.
4. **Sim-to-real.**
   - Domain randomization.
   - Teacher-student distillation: a privileged teacher, then a student on deployable sensors (OmniH2O, ExBody2). [read]
   - Learned residual dynamics: ASAP. [read]
   - Sim-to-sim check in MuJoCo before hardware (KungfuBot). [read]

## 2. The specific papers

**KungfuBot / PBHC.**
- "KungfuBot: Physics-Based Humanoid Whole-Body Control for Learning Highly-Dynamic Skills", Xie, Han, Zheng, Li, Liu, Shi, Zhang, Bai, Li; NeurIPS 2025. [read, abstract plus most of the HTML]
- **Data:** 13 motions in easy, medium and hard tiers, 145 to 610 frames each. Sources are GVHMR video, AMASS and LAFAN.
- **Retargeting:** IK via mink.
- **Physics filter:** a frame is stable if the ground-projected distance between centre of mass and centre of pressure is under a threshold. A clip passes if its first and last frames are stable and no unstable run is too long. On a 10-clip test, 4 were rejected and 6 accepted.
- **Tracking reward:** every term except foot contact has the form exp(-x/sigma). An adaptive curriculum tightens sigma based on current tracking error.
- **Weights (Table 6):**
  - Tracking: joint position, joint velocity, body position, max joint position and feet position at 1.0; body rotation, velocity, angular velocity and contact mask at 0.5.
  - Penalties: joint limit -10, velocity limit -5, torque limit -5, slippage -1, feet contact force -0.01, air time -1, stumble -2, torque -1e-6, action rate -0.02, collision -30, termination -200.
- **Training:** IsaacGym, one policy per motion, 27 h on one RTX 4090 each. Baselines took 18 to 30 h.
- **Randomization:**
  - Friction 0.2 to 1.2; PD gain +-10%; mass and inertia +-10%; CoM offset +-5 cm.
  - Control delay 0 to 40 ms; random pushes every 5 to 10 s.
- **PD gains on G1:** hips 100/2, knee 150/4, ankle 40/2, waist 400/5, arms 50 to 100/2.
- **Failures:** rejected motions reached an episode-length ratio of 54% at best. Hard-tier results have high variance (E_g-mpbpe 290 +- 139 mm). The root was fixed for the real Tai Chi test. There is no terrain awareness, and one policy covers only one skill.

**BeyondMimic.**
- "BeyondMimic: From Motion Tracking to Versatile Humanoid Control via Guided Diffusion", Liao, Truong, Huang, Gao, Tevet, Sreenath, Liu; arXiv:2508.08241, 2025. [read, abstract only]
- Claims cartwheels, spin-kicks, flip-kicks and sprinting from a single setup with shared hyperparameters, zero-shot to hardware. A latent diffusion layer composes skills.
- I did not read its reward details.

**ASAP.**
- Tairan He et al., RSS 2025, arXiv:2502.01143. [read, abstract]
- Pretrain a tracker in IsaacGym on retargeted human motion. Deploy on the G1 and collect real data. Train a residual "delta action" model for the sim-to-real mismatch. Fine-tune the policy in sim with that model in the loop.
- It reports lower tracking error than SysID, domain randomization and delta-dynamics baselines.

**H2O and OmniH2O.**
- H2O: "Learning Human-to-Humanoid Real-Time Whole-Body Teleoperation", He, Luo, Xiao, Zhang, Kitani, Liu, Shi; arXiv:2403.04436, 2024. [read, abstract]
  - Its "sim-to-data" step uses a privileged imitator to filter out motions that are not physically feasible. It is driven by an RGB camera.
- OmniH2O: He et al., arXiv:2406.08858, 2024. [read, abstract]
  - Teacher-student, large-scale retargeting and augmentation, and the OmniH2O-6 dataset.

**ExBody2.**
- Ji, Peng, Liu, Li, Yang, Cheng, Wang; arXiv:2412.13196, 2024. [read, abstract]
- A teacher "automatically filters out whole-body motions the robot cannot feasibly perform." A student is trained on the refined data.
- Fine-tuning on a few motions improves them but can hurt the rest.

**GMT.**
- "GMT: General Motion Tracking for Humanoid Whole-Body Control", Chen, Ji, Cheng, Peng, Peng, Wang; arXiv:2506.14770, 2025. [read, search summary only]
- One policy for many motions, using adaptive sampling and a motion mixture-of-experts.

**HumanPlus.**
- Fu, Zhao, Wu, Wetzstein, Finn; arXiv:2406.10454, 2024. [read, abstract]
- Sim RL on about 40 h of human motion. Camera shadowing. Behaviour cloning on top.

**PHC.**
- "Perpetual Humanoid Control for Real-time Simulated Avatars", Luo, Cao, Winkler, Kitani, Xu; ICCV 2023, arXiv:2305.06456. [read, abstract]
- A controller that tolerates noisy video pose estimates, recovers from falls, and scales to about 10,000 clips.

**AMP.**
- Peng, Ma, Abbeel, Levine, Kanazawa; arXiv:2104.02180, 2021. [read, abstract]
- An adversarial discriminator trained on motion clips gives a "style" reward.
- Related: "Natural Humanoid Robot Locomotion with Generative Motion Prior", Zhang et al., arXiv:2503.09015, 2025. A frozen CVAE motion generator supervises RL toward natural motion. [read, abstract]

**Unitree's own statements.**
- I could not reach a primary Unitree statement.
- Secondary coverage (interestingengineering.com, heise.de) says training happens in Isaac simulation from mocap and video-derived data, with RL refinement and then sim2real.
- Unitree credits the open LAFAN1 dataset for smoother H1, H1-2 and G1 motion. Heise cautions that firms publish only the clips that worked. [read, search snippets only]

## 3. Why it still reads as "robot"

Only the first point has direct support from what I read.

- **Reference quality limits the result.**
  - Source: GMR abstract and the Unitree dataset note [read].
  - The reference is produced by kinematics-only retargeting. Foot sliding and infeasible poses are left for the policy to fix.
- **Jitter exists.**
  - Source: a search summary of HybridMimic, arXiv:2603.06775, which reports BeyondMimic's sidestep was "more jittery" on hardware [read, snippet only].
  - Author claims about their own motions are not independent.
- **Naturalness gap.**
  - Source: the same search summary says a learned metric, HumanScore, matched human preference 90.83% of the time against 80.49% for MPJPE [snippet only].
  - So joint-error numbers under-measure "looks human".
- **Everything below is [inference]:**
  - Tracking rewards score positions and velocities, so nothing asks for secondary motion such as a floppy belly, flesh or arm lag.
  - High PD gains (waist kp 400 in KungfuBot) give a stiff torso.
  - A fixed root, a roughly 40 ms delay, and a penalty on torque and action rate give a "precise but careful" look.
  - Contact friction and foot-slip penalties give cautious or stamping footfalls.
  - Fewer DOF (G1 waist has 3, no spine chain, no clavicles) means the human spine's wave cannot be expressed.

## 4. What Kine can use, ranked by value over effort

Kine already has joint limits, gait data, a torque and balance check, MediaPipe video and a UE5 skeleton.

**1. The KungfuBot-style physical-feasibility filter. Highest value, low effort, runs in Godot or plain GDScript.**
- A per-frame test of whether the centre of mass projected to the ground lies inside the support polygon, or within a distance of the centre of pressure. The whole-clip rule is: first and last frame stable, no long unstable run.
- This is almost exactly Kine's "could a human do this" balance check, with a published pass criterion to copy.
- Add to it a foot-slide and a self-penetration metric, since GMR identifies those as the artifacts that matter. Show them as a per-clip report.

**2. Retargeting for video capture: copy the GMR recipe, medium effort.**
- Do two-stage IK from the source skeleton's bone orientations to ours, with joint limits and velocity limits on, then clean foot sliding and contacts.
- GMR itself is Python and MIT, but its robot models are robots. For a human-to-human UE5 skeleton, the useful parts are the design, not the code.
- The video-to-3D step (GVHMR) is a separate dependency, with licence caveats in section 5. MediaPipe is already accepted for Kine, so keep it as the default and treat GVHMR as an optional higher-quality path.

**3. A physics tracking pass that makes hand-keyed animation plausible. High value, high effort, needs Python.**
- This is the DeepMimic/PHC idea: a simulated humanoid learns to follow the keyed pose and the sim reveals where balance or momentum fails.
- Training takes about 27 h per clip on a 4090 in KungfuBot (one policy per motion), so it is an offline premium feature, not an interactive one.
- PHC (one general controller, tolerant of noisy input, recovers from falls) is the better fit than per-clip policies, because users need instant results. Treat it as research, not a near-term feature.
- Inside Godot, a cheap version is feasible without RL: a sim-free check with an inverted-pendulum or ZMP-style balance estimate, plus a torque check from inverse dynamics. Kine already has torque and balance, so extend it rather than build RL.

**4. A "does this look human" score. Medium value, unclear effort.**
- AMP-style discriminators need a motion dataset to train on and the licensing issues below. A discriminator trained on our own licensed clips is possible.
- A cheaper proxy: statistical checks against real gait data Kine already holds, such as joint-angle ranges, jerk, foot-contact timing.
- The evidence that learned metrics beat joint-error metrics is only a search snippet, so verify before leaning on it.

**5. Feeding Kine's data into a robot pipeline. Low priority.** It is not what Kine is for.

**Feasible in Godot:** items 1 and the cheap form of 3, plus the retarget IK in item 2.
**Needs Python or Isaac:** RL tracking, discriminator training, GVHMR.

## 5. Licence flags (Kine is commercial)

- **AMASS: non-commercial only.** "Any other use, in particular any use for commercial purposes, is prohibited"; commercial use needs a separate arrangement (ps-license@tue.mpg.de). [read]
- **SMPL / SMPL-X: non-commercial only.** The free licence also prohibits "using the software to train methods, algorithms, or neural networks for commercial use of any kind". Commercial licensing goes through Meshcapade or smpl@max-planck-innovation.de. [read]
  - Every pipeline that outputs SMPL (GVHMR, AMASS-based tracking) is therefore affected.
- **LAFAN1 and Unitree's retarget of it: CC BY-NC-ND 4.0.** Non-commercial, no derivatives. [read]
  - Do not ship it, and do not train a commercial discriminator on it.
- **GMR: MIT.** [read] Fine to use or adapt.
- **GVHMR: code licence not visible to me.** [read: the page did not show it] Check its LICENSE, and note it needs SMPL body model files.
- **Paper code for KungfuBot, BeyondMimic, ASAP, GMT:** I did not check licences. Check before reusing any code.
- For ideas and published thresholds (the CoM/CoP stability rule, reward structure), the concern is code and data licensing, not the ideas themselves. I am not giving legal advice.

## 6. Gaps in this research

- No reward detail for BeyondMimic, ASAP, GMT, ExBody2 or OmniH2O beyond abstracts.
- No primary source from Unitree, UBTech, AgiBot, Fourier or EngineAI.
- Training times are KungfuBot's only (27 h per policy, 4090).
- The "why robot-looking" analysis is mostly my inference, flagged above.

## Sources

- KungfuBot: arxiv.org/abs/2506.12851 and arxiv.org/html/2506.12851
- BeyondMimic: arxiv.org/abs/2508.08241
- ASAP: arxiv.org/abs/2502.01143
- H2O: arxiv.org/abs/2403.04436
- OmniH2O: arxiv.org/abs/2406.08858
- ExBody2: arxiv.org/abs/2412.13196
- HumanPlus: arxiv.org/abs/2406.10454
- GMT: arxiv.org/abs/2506.14770 (search summary)
- GMR: arxiv.org/abs/2510.02252 and github.com/YanjieZe/GMR
- DeepMimic: arxiv.org/abs/1804.02717
- AMP: arxiv.org/abs/2104.02180
- PHC: arxiv.org/abs/2305.06456
- GMP: arxiv.org/abs/2503.09015
- GVHMR: github.com/zju3dv/GVHMR
- AMASS licence: amass.is.tue.mpg.de/license.html
- SMPL licence: smpl.is.tue.mpg.de/modellicense.html
- LAFAN1: github.com/ubisoft/ubisoft-laforge-animation-dataset
- Unitree retarget dataset: huggingface.co/datasets/lvhaidong/LAFAN1_Retargeting_Dataset
- Press: interestingengineering.com and heise.de/-10767023 (search snippets)
