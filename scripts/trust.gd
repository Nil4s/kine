## trust.gd - TRUST LABELS (docs/INNOVATIONS.md N020). Every bar a judge grades with, and every number the agent API gives,
## says how far it can be trusted, so a blind agent knows which bars it may argue with:
##   MEASURED    read from an opened source (doi / url / the doc that quotes the table cell): argue with the data, not the bar
##   HEURISTIC   ours: a threshold, a grace band, a fitted time constant or a published convention that is not a body
##               measurement. Often ANCHORED on a measured mean (the source says which); the number itself is a choice
##   UNVERIFIED  no source was opened for it (docs/physics_constants.md's own word): treat it as a guess
## Seeded from docs/physics_constants.md (its status column), docs/physics_constants_i47.md and the cited comments at the
## constants themselves (grep doi / PMC / PMID in scripts/). A row says WHERE the constant lives ("Class.NAME", or
## "Class.NAME.key" for one entry of a table); value() reads the number from the code, so a label never carries a stale
## copy. tests/humanfacts_test.gd greps every name below in its file.
## Serve: `check {trust: true}` and `measure {..., trust: true}` add a "trust" object per finding / per measure;
## without the param the output is byte for byte what it was (refs/agent/serve_transcript.jsonl).
class_name Trust
extends RefCounted

const M := "MEASURED"
const H := "HEURISTIC"
const U := "UNVERIFIED"
const ORDER := {M: 0, H: 1, U: 2}   # weakest wins when a finding rests on several bars

## class -> the file its constants live in
const FILES := {"Rulebook": "res://scripts/rulebook.gd", "AttackTiming": "res://tools/attack_timing.gd",
	"HumanLimits": "res://scripts/human_limits.gd", "Balance": "res://scripts/balance.gd", "Fatigue": "res://scripts/fatigue.gd",
	"GaitBand": "res://scripts/gait_band.gd", "WeaponTorque": "res://scripts/weapon_torque.gd",
	"WeaponRebound": "res://scripts/weapon_rebound.gd", "TimingCoach": "res://scripts/timing_coach.gd",
	"Counter": "res://scripts/counter.gd", "Momentum": "res://scripts/momentum.gd", "Recovery": "res://scripts/recovery.gd",
	"Breakfall": "res://scripts/breakfall.gd", "SpeedEnv": "res://scripts/speed_env.gd", "Feasible": "res://scripts/feasible.gd",
	"HitReaction": "res://scripts/hit_reaction.gd"}

const _ISBS := "https://ojs.ub.uni-konstanz.de/cpa/article/view/6368/5737"
const _SABR := "https://sabr.org/journal/article/baseball-swing-stride-and-head-movement-relationships/"
const _STANLEY := "https://chesterrep.openrepository.com/entities/publication/0acdae9d-e8be-48cf-816e-ed9c667981b3"
const _MR := "res://docs/MOTION_RULES.md"
const _KARUN := "https://arxiv.org/pdf/2310.08580"
const _PBHC := "https://arxiv.org/abs/2506.12851"
const _HL := "res://docs/research/HUMAN_LIMITS.md"
const _PC := "res://docs/physics_constants.md"
const _DELEVA := "https://doi.org/10.1016/0021-9290(95)00178-6"
const _SENSORS := "https://doi.org/10.3390/s25113270"

## name -> {s: status, u: unit, src: who measured it / why it is ours, url: doi / url / doc}
const REG := {
	# --- Rulebook (Check's default rules; SRC / URL there, docs/MOTION_RULES.md) ---
	"Rulebook.HIPS_MIN": {"s": H, "u": "deg/s", "src": "a quarter of hitters' pelvis peak 389 deg/s (ISBS 2015, 3 hitters: measured); the quarter is ours", "url": _ISBS},
	"Rulebook.SWING_LEAD": {"s": H, "u": "s", "src": "the window before the tip's peak in which hips and chest must peak: ours (the order pelvis -> trunk -> bat is ISBS 2015's)", "url": _ISBS},
	"Rulebook.HEAD_WARN": {"s": H, "u": "m", "src": "hitters' heads drop ~9 cm over the swing (Inkster et al., via SABR: measured) + 6 cm grace (ours)", "url": _SABR},
	"Rulebook.HEAD_FAIL": {"s": H, "u": "m", "src": "twice the WARN bar: ours", "url": _SABR},
	"Rulebook.FIST_WARN": {"s": M, "u": "m/s", "src": "lead hook peak fist speed 11.95 +- 1.84 m/s, 15 male amateur boxers, 3D mocap (Stanley, Thomson, Smith, Lamb 2018, Int J Perf Anal Sport 18:835)", "url": _STANLEY},
	"Rulebook.FIST_FAIL": {"s": M, "u": "m/s", "src": "the same paper's mean + 2 SD (11.95 + 2 x 1.84)", "url": _STANLEY},
	"Rulebook.HITCH_DIP": {"s": H, "u": "fraction", "src": "one bell-shaped speed peak per reach (Flash & Hogan 1985, J Neurosci 5(7)); the 30 % dip is ours", "url": _MR},
	"Rulebook.HITCH_SPAN": {"s": H, "u": "frames", "src": "ours (docs/MOTION_RULES.md)", "url": _MR},
	"Rulebook.HITCH_FAST": {"s": H, "u": "m/s", "src": "ours: a slow drift is not a hitch", "url": _MR},
	"Rulebook.STRIKE_MIN": {"s": H, "u": "m/s", "src": "ours: a tip slower than this all scene long holds no strike", "url": _MR},
	"Rulebook.FOOT_DOWN": {"s": H, "u": "m", "src": "the foot-skate metric's contact height (Karunratanakul et al. 2023): a published convention, not a body measurement", "url": _KARUN},
	"Rulebook.FOOT_SKATE": {"s": H, "u": "m", "src": "the foot-skate metric's 2.5 cm (Karunratanakul et al. 2023), here per planted stretch", "url": _KARUN},
	"Rulebook.BAL_OUT": {"s": H, "u": "m", "src": "ours: the centre of mass this far past the feet...", "url": _MR},
	"Rulebook.BAL_RUN": {"s": H, "u": "frames", "src": "ours: ...for 0.1 s with both feet down", "url": _MR},
	"Rulebook.LOOP_DEG": {"s": H, "u": "deg", "src": "ours (docs/MOTION_RULES.md, LOOP SEAM)", "url": _MR},
	"Rulebook.LOOP_GAP": {"s": H, "u": "m", "src": "ours (LOOP SEAM)", "url": _MR},
	"Rulebook.LOOP_JUMP": {"s": H, "u": "m/s", "src": "ours (LOOP SEAM)", "url": _MR},
	"Rulebook.PROP_WARN": {"s": H, "u": "m", "src": "ours (THROUGH A PROP; Props.REST_SINK)", "url": _MR},
	"Rulebook.PROP_FAIL": {"s": H, "u": "m", "src": "ours (THROUGH A PROP)", "url": _MR},
	"Rulebook.FLOAT_MIN": {"s": H, "u": "m", "src": "ours (FLOATS: under 2 cm is resting)", "url": _MR},
	"Rulebook.FLOAT_MAX": {"s": H, "u": "m", "src": "ours (FLOATS: over 15 cm is not meant to sit)", "url": _MR},
	"Rulebook.FLOAT_RUN": {"s": H, "u": "frames", "src": "ours (FLOATS)", "url": _MR},
	"Rulebook.CARRY_UP": {"s": H, "u": "deg", "src": "the form is Anderson et al. 2007 / Snook 1978 (loads held close, arms down); the 35 deg bar is ours", "url": "https://stacks.cdc.gov/view/cdc/189155"},
	"Rulebook.CARRY_FLEX": {"s": H, "u": "deg", "src": "carried loads ride on bent elbows (knuckle to elbow height); the 50-130 band is ours", "url": "https://stacks.cdc.gov/view/cdc/189155"},
	"Rulebook.CARRY_H": {"s": H, "u": "m", "src": "NIOSH lifting equation: H 25 cm ideal, multiplier 25/H; 0.40 m (0.63) is our cut", "url": "https://stacks.cdc.gov/view/cdc/189155"},
	"Rulebook.JUMP_HIGH": {"s": H, "u": "m", "src": "recreational CMJ 0.40 +- 0.11 m, elite ~0.70 (Bosco; via docs/MOTION_RULES.md); the bar is ours, set at the elite figure", "url": _MR},
	"Rulebook.JUMP_DIP": {"s": H, "u": "deg", "src": "people dip to ~90 deg of knee bend before take-off; 30 is ours, set well below", "url": _MR},
	"Rulebook.JUMP_LAND": {"s": H, "u": "deg", "src": "ours: the stiff-landing bar at a 0.40 m fall, below DeVita & Skelly's stiff 77", "url": "https://pubmed.ncbi.nlm.nih.gov/1548984/"},
	"Rulebook.JUMP_FALL0": {"s": H, "u": "m", "src": "the recreational jump height where the old bar stood (ours)", "url": _MR},
	"Rulebook.JUMP_FALL1": {"s": M, "u": "m", "src": "DeVita & Skelly 1992's drop height, 59 cm (PMID 1548984)", "url": "https://pubmed.ncbi.nlm.nih.gov/1548984/"},
	"Rulebook.JUMP_LAND1": {"s": M, "u": "deg", "src": "stiff landing knee flexion 77 deg (soft 117) from 59 cm (DeVita & Skelly 1992, PMID 1548984)", "url": "https://pubmed.ncbi.nlm.nih.gov/1548984/"},
	"Rulebook.JUMP_LAND_MAX": {"s": H, "u": "deg", "src": "ours: never past a soft landing's 117 less a margin", "url": _MR},
	"Rulebook.LIFT_TRUNK": {"s": H, "u": "deg", "src": "Shu et al. 2007 tested 45 vs 60 deg trunk flexion (back muscles quiet as it grows); the 60 cut is ours", "url": "https://pubmed.ncbi.nlm.nih.gov/17103232/"},
	"Rulebook.LIFT_KNEE": {"s": H, "u": "deg", "src": "a lifting study's DEFINITION of a stoop, knees 0-30 deg (Int J Sports Med 2025): a convention", "url": "https://pubmed.ncbi.nlm.nih.gov/17103232/"},
	"Rulebook.GAIT_STEP": {"s": H, "u": "x body height", "src": "people 0.415 +- 0.038 of body height at 1.33 m/s (Gait Posture 2009, 21 young adults, PMID 19502061: measured); the ~3 SD band is ours", "url": "https://pubmed.ncbi.nlm.nih.gov/19502061/"},
	"Rulebook.GAIT_CAD": {"s": H, "u": "steps/min", "src": "people 105.5 +- 5.2 and 108 +- 7 steps/min (PMID 29775941, 41879248: measured); the band is ours", "url": "https://pubmed.ncbi.nlm.nih.gov/29775941/"},
	"Rulebook.GAIT_ARM": {"s": H, "u": "deg", "src": "arm swing ~25-33 deg peak to peak at 4 km/h (PMID 40291287, 23236504: measured); the band is ours", "url": "https://pubmed.ncbi.nlm.nih.gov/40291287/"},
	"Rulebook.GAIT_PHASE": {"s": H, "u": "r", "src": "arms out of phase with the same-side leg (Kubo et al. 2004, PMID 15351887); the 0.3 cut is ours", "url": "https://pubmed.ncbi.nlm.nih.gov/15351887/"},
	"Rulebook.AIR": {"s": H, "u": "m", "src": "ours: the lower foot this far over its lowest = off the ground", "url": _MR},
	"Rulebook.FOOT_STILL": {"s": H, "u": "m/frame", "src": "ours: slower than 0.3 m/s = meant to stand", "url": _MR},
	# --- the weapon's timing table (tools/attack_timing.gd, docs/ATTACK_RULES.md) ---
	"AttackTiming.TIP_MAX": {"s": U, "u": "m/s", "src": "a pro bat ~40, a staff end ~30, a knife ~15: no opened source behind them (docs/ATTACK_RULES.md)", "url": "res://docs/ATTACK_RULES.md"},
	"AttackTiming.RULES": {"s": H, "u": "s / frames at 30 fps", "src": "anticipation, strike-frame budget and recovery per weapon: game-feel practice (Aztez), not body measurements", "url": "res://docs/ATTACK_RULES.md"},
	# --- could a human do this? (scripts/human_limits.gd) ---
	"HumanLimits.SPEED.shoulder": {"s": M, "u": "deg/s", "src": "shoulder internal rotation, collegiate fastball 6520 deg/s (Fortenbaugh, Fleisig & Andrews 2009, Sports Health 1(4):314, PMC3445126)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC3445126/"},
	"HumanLimits.SPEED.trunk": {"s": M, "u": "deg/s", "src": "upper trunk rotation, collegiate fastball 1120 deg/s (same review, PMC3445126)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC3445126/"},
	"HumanLimits.SPEED.knee": {"s": M, "u": "deg/s", "src": "knee extension in a soccer kick 1874 +- 155 deg/s, amateur males (Manolopoulos 2006 via JSSM 6:154 Table 4): a group MEAN, a low bar for a peak", "url": _HL},
	"HumanLimits.FAIL_K": {"s": H, "u": "x bar", "src": "mean + 2 SD with the SD of Campbell's shoulder table borrowed for every joint (ours: no source gives the others' SD)", "url": _HL},
	"HumanLimits.SHOULDER_IR_NM": {"s": M, "u": "N m", "src": "shoulder internal rotation torque 67 N m, 26 skilled adult pitchers (Fleisig 1995, AJSM 23:233, abstract)", "url": _HL},
	"HumanLimits.REF_MASS": {"s": H, "u": "kg", "src": "ours: the mass the torque bar is quoted for, scaled linearly", "url": _HL},
	"HumanLimits.BAT_KG": {"s": U, "u": "kg", "src": "a 33-inch adult bat about 0.9 kg: not read from a paper", "url": _HL},
	"HumanLimits.BAT_COM": {"s": U, "u": "fraction", "src": "the bat's centre 0.6 of its length from the knob: not read from a paper", "url": _HL},
	"HumanLimits.GAIT_SPEED": {"s": H, "u": "m/s", "src": "a CoM this fast is carried onto the next step (Winter 1995, Gait & Posture 3:193: the principle); 1.0 m/s is ours", "url": _HL},
	"HumanLimits.GRAV": {"s": M, "u": "m/s^2", "src": "standard gravity", "url": _HL},
	# --- balance (scripts/balance.gd) ---
	"Balance.MASS": {"s": M, "u": "% body mass", "src": "segment masses, male (de Leva 1996, J Biomech 29(9):1223, Table 4)", "url": _DELEVA},
	"Balance.TOUCH": {"s": H, "u": "m", "src": "ours: a capsule this close to the floor is on it", "url": _PC},
	"Balance.MARGIN_RES": {"s": H, "u": "m", "src": "ours: what the foot-shadow polygon can tell (1 cm contact, a 12-gon on a 6 cm capsule)", "url": _PC},
	# --- fatigue (scripts/fatigue.gd, docs/research/FATIGUE.md) ---
	"Fatigue.DECLINE_REF": {"s": M, "u": "fraction", "src": "punch speed -10.7 % straight, -9.9 % swing when fatigued, 21 elite male MMA fighters (Sensors 2025, 25(11):3270); the mean is derived", "url": _SENSORS},
	"Fatigue.FIT_REF": {"s": H, "u": "0..1", "src": "ours: the study's elite fighters are placed at fitness 0.5", "url": "res://docs/research/FATIGUE.md"},
	"Fatigue.TAU_UP": {"s": H, "u": "s", "src": "a modelling choice fitted to a 60 s fight (not a measurement)", "url": "res://docs/research/FATIGUE.md"},
	"Fatigue.TAU_REC": {"s": U, "u": "s", "src": "phosphocreatine resynthesis half-time ~20-30 s: textbook, 're-check before quoting'", "url": "res://docs/research/FATIGUE.md"},
	"Fatigue.REST_HOLD": {"s": H, "u": "s", "src": "ours: a hold this long is rest", "url": "res://docs/research/FATIGUE.md"},
	# --- real walkers' band (scripts/gait_band.gd) ---
	"GaitBand.FILE": {"s": M, "u": "deg", "src": "hip / knee / ankle angle mean and SD of 42 healthy adults per 1 % of the gait cycle (Fukuchi, Fukuchi & Duarte 2018, PeerJ 6:e4640, CC BY 4.0)", "url": "res://tools/make_gait_band.py"},
	"GaitBand.OUT_SD": {"s": H, "u": "SD", "src": "2 SD from the walkers' mean (~95 % of people inside): a statistical convention", "url": "res://tools/make_gait_band.py"},
	"GaitBand.OUT_SHARE": {"s": H, "u": "fraction", "src": "ours ('MINE' in the code): a joint is listed when > 10 % of its cycle is outside", "url": "res://tools/make_gait_band.py"},
	# --- weapon weight (scripts/weapon_torque.gd) ---
	"WeaponTorque.WRIST_MAX": {"s": M, "u": "N m", "src": "radial deviation, concentric peak moment, 20 men, 90 deg/s, Biodex ('Isokinetic Strength Profile of the Wrist Muscles', 2025, Table 1)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC12551099/"},
	"WeaponTorque.SHOULDER_MAX": {"s": M, "u": "N m", "src": "isometric shoulder flexion at 90 deg elevation, 14 healthy men, SD 13.8 (Aronis et al., J Funct Morphol Kinesiol 11(1):20 (2026), Table 1)", "url": _PC},
	"WeaponTorque.SEG": {"s": M, "u": "fractions", "src": "arm segment mass / com / radius of gyration (Winter, Biomechanics and Motor Control of Human Movement, 4th ed. 2009, table 4.1)", "url": "res://scripts/weapon_torque.gd"},
	"WeaponTorque.BODY_KG": {"s": H, "u": "kg", "src": "ours: a typical adult", "url": "res://scripts/weapon_torque.gd"},
	"WeaponTorque.WINDUP_MIN": {"s": H, "u": "fraction", "src": "ours (Thomas & Johnston 1981 give the order, not the number)", "url": "res://scripts/weapon_torque.gd"},
	"WeaponTorque.FOLLOW_MIN": {"s": H, "u": "fraction", "src": "ours (Thomas & Johnston 1981 give the order, not the number)", "url": "res://scripts/weapon_torque.gd"},
	"WeaponTorque.STOP_WIN": {"s": H, "u": "s", "src": "ours", "url": "res://scripts/weapon_torque.gd"},
	"WeaponTorque.ANTIC_BASE": {"s": H, "u": "s", "src": "ours, scaled by (I / I_bat)^0.27 (Cross & Bower 2006)", "url": "res://scripts/weapon_torque.gd"},
	# --- weapon rebound (scripts/weapon_rebound.gd) ---
	"WeaponRebound.K_WRIST": {"s": M, "u": "N m/rad", "src": "maximal voluntary wrist stiffening 0.34 N m/deg (Milner, Cloutier, Leger, Franklin 1995, Exp Brain Res 107:293)", "url": _PC},
	"WeaponRebound.E_STEEL": {"s": M, "u": "-", "src": "steel ball on steel prism, mean of ten (Ciornei & Alaci 2014, Ann Univ Oradea, Table I)", "url": _PC},
	"WeaponRebound.E_ALUMINIUM": {"s": M, "u": "-", "src": "steel ball on aluminium prism, mean of ten (Ciornei & Alaci 2014, Table I)", "url": _PC},
	"WeaponRebound.E_WOOD": {"s": U, "u": "-", "src": "none opened: old heuristic kept", "url": _PC},
	# --- timing coach (scripts/timing_coach.gd) ---
	"TimingCoach.V_PEAK_HI": {"s": M, "u": "m/s", "src": "lead hook peak fist speed 11.95 +- 1.84 (Stanley et al. 2018)", "url": _STANLEY},
	"TimingCoach.V_PEAK_LO": {"s": M, "u": "m/s", "src": "MMA swing punch 7.1 +- 0.5, a MEAN over the last 10 ms before impact, not a peak (Sensors 2025, 25(11):3270, sec. 3.2)", "url": _SENSORS},
	"TimingCoach.PEAK_OVER_MEAN": {"s": H, "u": "x", "src": "the minimum-jerk bell's peak / mean (Flash & Hogan 1985): a model, not a measurement of punches", "url": "res://scripts/timing_coach.gd"},
	"TimingCoach.ANTIC_RATIO": {"s": H, "u": "x", "src": "ours (the animation books give the order, not a number)", "url": "res://scripts/timing_coach.gd"},
	"TimingCoach.SETTLE_RATIO": {"s": H, "u": "x", "src": "ours", "url": "res://scripts/timing_coach.gd"},
	# --- counters (scripts/counter.gd) ---
	"Counter.REACT": {"s": M, "u": "s", "src": "simple visual reaction time, elite karate 292 +- 45 ms, n = 28 (Liu, See, Chang et al. 2018, Arch Budo 14, abstract)", "url": "res://docs/physics_constants.md"},
	"Counter.MV": {"s": U, "u": "s", "src": "the counter's own movement time: no source opened", "url": _PC},
	# --- momentum, recovery, breakfall (gt3 rows of docs/physics_constants.md) ---
	"Momentum.BRACE_BW": {"s": M, "u": "x body weight", "src": "peak horizontal braking GRF 1.60 BW, 27 male players (Dos'Santos et al., table in Harper et al. 2022 Sports Med 52, PMC9474351)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC9474351/"},
	"Momentum.STEP_BW": {"s": M, "u": "x body weight", "src": "the same measured braking-step peak (no larger horizontal value in the review table)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC9474351/"},
	"Momentum.YAW_ARM": {"s": U, "u": "m", "src": "none opened", "url": _PC},
	"Momentum.TILT_ARM": {"s": U, "u": "m", "src": "none opened", "url": _PC},
	"Recovery.STEP_T": {"s": U, "u": "s", "src": "swing duration not reported (Mansfield 2015 gives latency only)", "url": _PC},
	"Recovery.MAX_STEP_LEG": {"s": U, "u": "x leg length", "src": "Kluft 2017 / Bieryla 2015 measure it; numbers not in the open text", "url": _PC},
	"Breakfall.TUCK_MIN": {"s": U, "u": "deg", "src": "none opened", "url": _PC},
	"Breakfall.ELBOW_OK": {"s": U, "u": "deg", "src": "none opened", "url": _PC},
	"Breakfall.SPEED_OK": {"s": U, "u": "m/s", "src": "none opened", "url": _PC},
	# --- speed envelope (scripts/speed_env.gd: limit = mean + 1 SD of the fastest group; docs/physics_constants_i47.md) ---
	"SpeedEnv.CH.hand": {"s": M, "u": "m/s", "src": "lead hook 11.95 + 1.84 (Stanley et al. 2018)", "url": "res://docs/physics_constants_i47.md"},
	"SpeedEnv.CH.foot": {"s": M, "u": "m/s", "src": "taekwondo roundhouse foot 14.66 + 1.18 (Gavagan & Sayers 2017, PLoS ONE 12(8):e0182645, PMC5571909)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5571909/"},
	"SpeedEnv.CH.elbow": {"s": M, "u": "deg/s", "src": "pitching elbow extension 2305 + 221 (Fleisig et al. 2016, Sports Health 9(3):210, PMC5435148)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5435148/"},
	"SpeedEnv.CH.shoulder": {"s": M, "u": "deg/s", "src": "pitching shoulder internal rotation 6594 + 743 (Fleisig et al. 2016, PMC5435148)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5435148/"},
	"SpeedEnv.CH.knee": {"s": M, "u": "deg/s", "src": "karate roundhouse knee extension 947 + 94 (Gavagan & Sayers 2017, PMC5571909)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5571909/"},
	"SpeedEnv.CH.pelvis": {"s": M, "u": "deg/s", "src": "Muay Thai roundhouse pelvis rotation 493 + 206 (Gavagan & Sayers 2017, PMC5571909)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5571909/"},
	"SpeedEnv.CH.trunk": {"s": M, "u": "deg/s", "src": "pitching upper trunk 1101 + 89 (Fleisig et al. 2016, PMC5435148)", "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5435148/"},
	# --- is this clip physically possible? (scripts/feasible.gd) ---
	"Feasible.EPS_STAB": {"s": H, "u": "m", "src": "KungfuBot's physics filter eps_stab = 0.1 (Xie et al. 2025, Table 3): a published filter setting, units assumed", "url": _PBHC},
	"Feasible.EPS_N_FRAMES": {"s": H, "u": "frames at 30 fps", "src": "KungfuBot eps_N = 100 (Table 3), unit assumed", "url": _PBHC},
	"Feasible.BALLISTIC_TOL": {"s": H, "u": "m", "src": "ours ('mine' in the code)", "url": "res://docs/research/ROBOT_MOTION.md"},
	"Feasible.IMPOSSIBLE_TOL": {"s": H, "u": "m", "src": "ours ('mine' in the code)", "url": "res://docs/research/ROBOT_MOTION.md"},
	"Feasible.SLIDE_FIX": {"s": H, "u": "m", "src": "the foot-skate metric's 2.5 cm per contact (Karunratanakul et al. 2023)", "url": _KARUN},
	"Feasible.PEN_FIX": {"s": H, "u": "m", "src": "ours ('mine' in the code)", "url": "res://docs/research/ROBOT_MOTION.md"},
	"Feasible.GRAV": {"s": M, "u": "m/s^2", "src": "standard gravity", "url": "res://docs/research/ROBOT_MOTION.md"},
	# --- hit reaction (docs/physics_constants.md, gt1: UNVERIFIED list) ---
	"HitReaction.WEAPON_KG": {"s": U, "u": "kg", "src": "weapon masses are estimates (no source opened)", "url": _PC},
}

## Check's rules -> the bars a finding of that rule is graded against (first = the deciding bar)
const RULES := {
	"SEQUENCE": ["Rulebook.SWING_LEAD"],
	"HIPS TURN": ["Rulebook.HIPS_MIN"],
	"HEAD QUIET": ["Rulebook.HEAD_WARN", "Rulebook.HEAD_FAIL"],
	"TIP SPEED": ["AttackTiming.TIP_MAX"],
	"STRIKE FRAMES": ["AttackTiming.RULES"],
	"FIST SPEED": ["Rulebook.FIST_WARN", "Rulebook.FIST_FAIL"],
	"HITCH": ["Rulebook.HITCH_DIP", "Rulebook.HITCH_SPAN", "Rulebook.HITCH_FAST"],
	"BALANCE": ["Rulebook.BAL_OUT", "Rulebook.BAL_RUN", "Balance.MASS"],
	"LOOP SEAM": ["Rulebook.LOOP_DEG", "Rulebook.LOOP_GAP", "Rulebook.LOOP_JUMP"],
	"FOOT SLIDE": ["Rulebook.FOOT_SKATE", "Rulebook.FOOT_DOWN"],
	"ASSERT": ["Rulebook.FOOT_SKATE"],   # N002: the line's own numbers are the author's; the only Kine bar under it is "planted" (BodyAssert.SLIDE = FOOT_SKATE)
	"THROUGH A PROP": ["Rulebook.PROP_WARN", "Rulebook.PROP_FAIL"],
	"FLOATS": ["Rulebook.FLOAT_MIN", "Rulebook.FLOAT_MAX", "Rulebook.FLOAT_RUN"],
	"JUMP": ["Rulebook.JUMP_HIGH", "Rulebook.JUMP_DIP", "Rulebook.JUMP_LAND", "Rulebook.JUMP_FALL0", "Rulebook.JUMP_FALL1",
		"Rulebook.JUMP_LAND1", "Rulebook.JUMP_LAND_MAX"],
	"CARRY FORM": ["Rulebook.CARRY_UP", "Rulebook.CARRY_FLEX", "Rulebook.CARRY_H"],
	"GAIT": ["Rulebook.GAIT_STEP", "Rulebook.GAIT_CAD", "Rulebook.GAIT_ARM", "Rulebook.GAIT_PHASE"],
	"LIFT FORM": ["Rulebook.LIFT_TRUNK", "Rulebook.LIFT_KNEE"],
	"JOINT SPEED": ["HumanLimits.SPEED.shoulder", "HumanLimits.SPEED.trunk", "HumanLimits.SPEED.knee", "HumanLimits.FAIL_K"],
	"JOINT TORQUE": ["HumanLimits.SHOULDER_IR_NM", "HumanLimits.REF_MASS", "HumanLimits.FAIL_K"],
	"TIPPING": ["HumanLimits.GRAV", "Balance.MARGIN_RES", "HumanLimits.GAIT_SPEED"],
	"FEASIBLE": ["Feasible.EPS_STAB", "Feasible.EPS_N_FRAMES", "Feasible.BALLISTIC_TOL", "Feasible.IMPOSSIBLE_TOL",
		"Feasible.SLIDE_FIX", "Feasible.PEN_FIX"],
	"FEASIBLE BALANCE": ["Feasible.EPS_STAB", "Feasible.EPS_N_FRAMES"],
	"FEASIBLE FLIGHT": ["Feasible.GRAV", "Feasible.BALLISTIC_TOL", "Feasible.IMPOSSIBLE_TOL"],
	"FEASIBLE SLIDE": ["Feasible.SLIDE_FIX"],
	"FEASIBLE PENETRATION": ["Feasible.PEN_FIX"],
}

## measure's kinds: geometry of THIS scene is exact (no human data in it); the body models behind com / balance /
## clearance are where the trust question lives
const MEASURES := {
	"distance": {"s": M, "src": "measured on this scene: the joints' own positions (docs/AGENT_MATH.md); no human data involved", "url": "res://docs/AGENT_MATH.md", "bars": []},
	"angle": {"s": M, "src": "measured on this scene: the angle at the middle joint (docs/AGENT_MATH.md)", "url": "res://docs/AGENT_MATH.md", "bars": []},
	"height": {"s": M, "src": "measured on this scene: the part's y over the floor (y = 0)", "url": "res://docs/AGENT_MATH.md", "bars": []},
	"speed": {"s": M, "src": "measured on this scene: central difference over +-1 frame (docs/AGENT_MATH.md)", "url": "res://docs/AGENT_MATH.md", "bars": []},
	"com": {"s": M, "src": "de Leva 1996 segment masses (measured); each part's centre at the middle of its capsule is the model's simplification", "url": _DELEVA, "bars": ["Balance.MASS"]},
	"balance": {"s": H, "src": "the support polygon is the foot capsules' shadow on the floor (wider than a real foot: lenient) and its resolution is ours", "url": "res://scripts/balance.gd", "bars": ["Balance.MASS", "Balance.TOUCH", "Balance.MARGIN_RES"]},
	"clearance": {"s": H, "src": "gap between capsules standing in for the weapon and the dummy's parts: an approximation of their surfaces", "url": "res://docs/AGENT_MATH.md", "bars": []},
}

static var _maps := {}


## the constant's value as the code holds it (null: not found). "Class.NAME.key" indexes a table: a Dictionary by key, an
## Array of rows by their "id" (its "limit")
static func value(name: String) -> Variant:
	var p := name.split(".")
	if p.size() < 2 or not FILES.has(p[0]):
		return null
	if not _maps.has(p[0]):
		var sc: Script = load(FILES[p[0]])
		_maps[p[0]] = sc.get_script_constant_map() if sc != null else {}
	var cm: Dictionary = _maps[p[0]]
	if not cm.has(p[1]):
		return null
	var v: Variant = cm[p[1]]
	if p.size() == 2:
		return v
	if v is Dictionary:
		return v.get(p[2])
	if v is Array:
		for row in v:
			if row is Dictionary and String(row.get("id", "")) == p[2]:
				return row.get("limit")
	return null


## one registry row as the agent sees it
static func row(name: String) -> Dictionary:
	if not REG.has(name):
		return {"name": name, "status": U, "source": "not in the trust registry (scripts/trust.gd)", "url": ""}
	var r: Dictionary = REG[name]
	return {"name": name, "value": value(name), "unit": r["u"], "status": r["s"], "source": r["src"], "url": r["url"]}


static func weakest(rows: Array) -> String:
	var w := M
	for r in rows:
		if ORDER[r["status"]] > ORDER[w]:
			w = r["status"]
	return w


## a Check rule's trust: the weakest of its bars (a finding is only as firm as the softest number it rests on)
static func for_rule(rule: String) -> Dictionary:
	if not RULES.has(rule):
		return {"status": U, "source": "no registry row for the rule '%s' (scripts/trust.gd RULES)" % rule, "url": "", "bars": []}
	var bars: Array = RULES[rule].map(func(n): return row(n))
	return {"status": weakest(bars), "source": String(Rulebook.SRC.get(rule, "")), "url": String(Rulebook.URL.get(rule, "")), "bars": bars}


static func for_measure(kind: String) -> Dictionary:
	if not MEASURES.has(kind):
		return {"status": U, "source": "no trust row for the measure '%s'" % kind, "url": "", "bars": []}
	var d: Dictionary = MEASURES[kind]
	return {"status": d["s"], "source": d["src"], "url": d["url"], "bars": d["bars"].map(func(n): return row(n))}


## serve's check / measure responses, labelled in place (only when the request said trust: true)
static func label(method: String, resp: Dictionary) -> Dictionary:
	if not resp.has("result") or not (resp["result"] is Dictionary):
		return resp
	var r: Dictionary = resp["result"]
	if method == "check":
		for f in r.get("findings", []):
			f["trust"] = for_rule(String(f["rule"]))
	elif method == "measure":
		for x in r.get("measures", []):
			x["trust"] = for_measure(String(x["what"]).split(" ", false)[0])
	return resp


## the whole registry (facts {registry: true})
static func registry() -> Array:
	var out := []
	for n in REG:
		out.append(row(n))
	return out
