## human_facts.gd - HUMAN FACTS (docs/INNOVATIONS.md N022). "How fast is a real jab? How long does a hook take? How far does a
## man step?" answered from Kine's own cited tables (docs/physics_constants*.md, docs/MOTION_RULES.md, the judges' cited
## constants), each with value, unit, range, population, source and a trust label (scripts/trust.gd), so an agent plans
## with real numbers instead of guessing them.
## MATCHING is words, not a model: the question is lower-cased, cut into words, each word folded to a canonical one
## (SYN: "quickly" / "velocity" -> fast / speed, "bent" / "flexion" -> flex, a plural or -ing stripped). A fact answers when
## every one of its NEED groups has a word in the question (2 points per group) plus its KW bonus words; the best score
## wins, ties go to the earlier fact. A question no fact fully matches gets "no cited number" and the nearest topics,
## never a guess.
## A fact's "code" names the registry rows (Trust.REG) that hold the same number in a judge, so an agent can see which bar
## a fact feeds. Where Kine has no opened source the fact says UNVERIFIED instead of pretending.
class_name HumanFacts
extends RefCounted

const M := Trust.M
const H := Trust.H
const U := Trust.U
const _SENSORS := "https://doi.org/10.3390/s25113270"
const _STANLEY := "https://chesterrep.openrepository.com/entities/publication/0acdae9d-e8be-48cf-816e-ed9c667981b3"
const _ROM := "AAOS 'Joint Motion' / Soucie et al. 2011 healthy-adult means, as cited in scripts/deform_check.gd and held in data/body_limits.json; the table itself was not opened for Kine, so UNVERIFIED"

## word -> canonical word(s) (space-separated: "fastest" is fast AND top)
const SYN := {
	"quick": "fast", "quickly": "fast", "quicker": "fast", "quickest": "fast top", "faster": "fast", "fastest": "fast top",
	"rapid": "fast", "rapidly": "fast", "swift": "fast", "speedy": "fast",
	"velocity": "speed", "velocitie": "speed", "mps": "speed",
	"bend": "flex", "bent": "flex", "flexion": "flex", "flexed": "flex", "fold": "flex", "curl": "flex",
	"maximum": "max", "maximal": "max", "most": "max", "furthest": "max", "farthest": "max", "fullest": "max",
	"limit": "max", "range": "max", "rom": "max",
	"reaction": "react", "reflex": "react", "respond": "react", "response": "react", "reactive": "react",
	"take": "time", "last": "time", "duration": "time", "second": "time", "ms": "time", "millisecond": "time", "frame": "time",
	"far": "far", "distance": "far", "length": "far", "big": "far", "wide": "far", "size": "far",
	"walking": "walk", "stroll": "walk", "gait": "walk",
	"torso": "trunk", "chest": "trunk",
	"weight": "mass", "weigh": "mass", "heavy": "mass",
	"force": "force", "strength": "force", "strong": "force", "torque": "force", "moment": "force", "power": "force", "nm": "force",
	"leap": "jump", "height": "high", "tall": "high",
	"stiffness": "stiff", "rigid": "stiff",
	"restitution": "bounce", "rebound": "bounce", "cor": "bounce", "bouncy": "bounce",
	"fatigued": "fatigue", "tired": "fatigue", "tire": "fatigue", "exhausted": "fatigue", "exhaustion": "fatigue", "gassed": "fatigue",
	"recovery": "recover", "shove": "recover", "push": "recover", "stumble": "recover", "trip": "recover", "balance": "recover",
	"braking": "brake", "stop": "brake", "decelerate": "brake", "deceleration": "brake", "halt": "brake",
	"landing": "land", "roundhouse": "kick",
	"rotate": "turn", "rotation": "turn", "twist": "turn", "spin": "turn",
	"bat": "weapon", "sword": "weapon", "staff": "weapon", "knife": "weapon", "stick": "weapon", "club": "weapon",
	"blade": "weapon", "axe": "weapon", "hammer": "weapon", "spear": "weapon", "tip": "weapon",
	"pitch": "throw", "pitcher": "throw", "pitching": "throw", "throwing": "throw",
	"extension": "extend", "straighten": "extend",
	"minute": "rate", "frequency": "rate", "cadence": "cadence",
	"drop": "move", "bob": "move", "movement": "move", "steady": "move", "still": "move", "travel": "move",
	"hips": "hip", "batter": "hitter", "batting": "hitter", "hitting": "hitter",
	"shank": "calf", "shin": "calf",
	"accelerate": "accel", "acceleration": "accel", "accelerat": "accel", "explode": "accel", "explosive": "accel",
	"sidestep": "cut", "juke": "cut", "sideway": "cut", "sideways": "cut", "lateral": "cut", "takeoff": "accel",
}

## id, topic, q (the question it answers), value, unit, range [lo, hi], pop, source, url, trust, code (Trust.REG rows), note,
## need (groups of canonical words: each must be hit), kw (bonus words)
const FACTS := [
	{"id": "jab_speed", "topic": "jab / straight punch speed", "q": "how fast is a real jab?", "value": 8.4, "unit": "m/s", "range": [7.8, 9.0],
		"pop": "21 elite male MMA fighters, maximal straight punches, fresh", "trust": M, "url": _SENSORS,
		"source": "Sensors 2025, 25(11):3270 (PMC12157019), sec. 3.2: 'mean punch velocities were 8.4 +- 0.6 m/s for straight punches'",
		"note": "a MEAN fist speed over the last 10 ms before impact; boxers' single maximal punch at contact 9.26 +- 2.09 m/s (Piorkowski, Lees, Barton 2011); the PEAK of the fastest punch is the lead hook's 11.95",
		"code": [], "need": [["jab", "straight", "cross", "punch"], ["fast", "speed"]], "kw": {"jab": 2, "straight": 2, "cross": 1}},
	{"id": "hook_speed", "topic": "hook / fastest punch peak speed", "q": "how fast is a hook (the fastest punch)?", "value": 11.95, "unit": "m/s", "range": [10.11, 13.79],
		"pop": "15 male amateur boxers, 3D mocap, bag", "trust": M, "url": _STANLEY,
		"source": "Stanley, Thomson, Smith, Lamb 2018, Int J Perf Anal Sport 18:835: 'lead hook exhibited the greatest peak fist velocity (11.95 +- 1.84 m/s)'",
		"note": "Check's FIST SPEED warns at this and fails at mean + 2 SD (15.6 m/s)",
		"code": ["Rulebook.FIST_WARN", "TimingCoach.V_PEAK_HI"], "need": [["hook", "punch"], ["fast", "speed"]], "kw": {"hook": 3, "top": 2, "peak": 2}},
	{"id": "swing_punch_speed", "topic": "swing (overhand) punch speed", "q": "how fast is a swing punch?", "value": 7.1, "unit": "m/s", "range": [6.6, 7.6],
		"pop": "21 elite male MMA fighters, fresh", "trust": M, "url": _SENSORS,
		"source": "Sensors 2025, 25(11):3270, sec. 3.2: '7.1 +- 0.5 m/s for swing punches'", "note": "a mean over the last 10 ms before impact, not a peak",
		"code": ["TimingCoach.V_PEAK_LO"], "need": [["swing", "overhand", "haymaker"], ["fast", "speed"]], "kw": {"punch": 2}},
	{"id": "punch_duration", "topic": "how long a punch (jab, cross, hook) takes", "q": "how long does a hook take?", "value": null, "unit": "s", "range": null,
		"pop": "derived for a fist travelling 0.6 m", "trust": H, "url": "res://scripts/timing_coach.gd",
		"source": "DERIVED by TimingCoach.peak_range: time = travel / mean speed, mean = peak / 1.875 (minimum-jerk bell, Flash & Hogan 1985), peaks 7.1 (Sensors 2025) to 11.95 m/s (Stanley 2018)",
		"note": "no paper in Kine's tables times a punch directly: the speeds are measured, the bell shape and the 0.6 m travel are the model. Scale with the travel: a 0.4 m jab takes 2/3 as long",
		"code": ["TimingCoach.V_PEAK_HI", "TimingCoach.V_PEAK_LO", "TimingCoach.PEAK_OVER_MEAN"],
		"need": [["jab", "cross", "hook", "punch", "straight", "uppercut", "strike"], ["time", "long"]], "kw": {"time": 1}},
	{"id": "fatigue_decline", "topic": "how much a tired fighter slows", "q": "how much slower are punches when tired?", "value": 10.3, "unit": "% of fresh speed lost", "range": [9.9, 10.7],
		"pop": "21 elite male MMA fighters, fatigued vs fresh", "trust": M, "url": _SENSORS,
		"source": "Sensors 2025, 25(11):3270: straight 8.4 -> 7.5 m/s (-10.7 %), swing 7.1 -> 6.4 (-9.9 %); the mean is derived",
		"note": "punch FORCE fell 4.3 % on average after a 9.5 min circuit (Stewart et al. 2025)", "code": ["Fatigue.DECLINE_REF"],
		"need": [["fatigue"]], "kw": {"punch": 1, "slow": 1, "speed": 1}},
	{"id": "reaction_time", "topic": "reaction time", "q": "what is a fighter's reaction time?", "value": 0.292, "unit": "s", "range": [0.247, 0.337],
		"pop": "elite karate athletes, n = 28, simple visual reaction, button press", "trust": M, "url": "res://docs/physics_constants.md",
		"source": "Liu, See, Chang et al. 2018, Arch Budo 14 (abstract): '292.33 +- 45.4 ms'; novice karateka 306 +- 47, non-athletes 335 +- 73",
		"note": "a CHOICE reaction (which punch is coming) is slower, ~0.4 s in judoka (unverified abstract)", "code": ["Counter.REACT"],
		"need": [["react"]], "kw": {"react": 4, "time": 1}},
	{"id": "counter_move_time", "topic": "time to move a guard / slip into place", "q": "how long does a block take to get into place?", "value": 0.12, "unit": "s", "range": null,
		"pop": "-", "trust": U, "url": "res://docs/physics_constants.md", "source": "Counter.MV: no source opened", "note": "a guess kept from the code; argue with it",
		"code": ["Counter.MV"], "need": [["counter", "block", "guard", "slip", "parry", "dodge", "duck"], ["time", "long", "fast"]], "kw": {}},
	{"id": "step_length", "topic": "walking step length", "q": "how far does a man step?", "value": 0.415, "unit": "x body height", "range": [0.377, 0.453],
		"pop": "21 young adults, preferred walking speed (1.33 m/s)", "trust": M, "url": "https://pubmed.ncbi.nlm.nih.gov/19502061/",
		"source": "Gait Posture 2009 (PMID 19502061): step length 0.415 +- 0.038 of body height", "note": "a 1.80 m man: about 0.75 m per step (1.5 m per stride, both feet)",
		"code": ["Rulebook.GAIT_STEP"], "need": [["step", "stride", "pace"], ["far", "long"]], "kw": {"walk": 1, "far": 1}},
	{"id": "walk_speed", "topic": "walking speed", "q": "how fast does a person walk?", "value": 1.33, "unit": "m/s", "range": null,
		"pop": "21 young adults, preferred speed", "trust": M, "url": "https://pubmed.ncbi.nlm.nih.gov/19502061/",
		"source": "Gait Posture 2009 (PMID 19502061): preferred walking speed 1.33 m/s", "note": "",
		"code": [], "need": [["walk"], ["fast", "speed"]], "kw": {}},
	{"id": "cadence", "topic": "walking cadence (steps per minute)", "q": "how many steps a minute does a person walk?", "value": 105.5, "unit": "steps/min", "range": [100.3, 110.7],
		"pop": "healthy adults walking", "trust": M, "url": "https://pubmed.ncbi.nlm.nih.gov/29775941/",
		"source": "PMID 29775941: 105.5 +- 5.2 steps/min; PMID 41879248: 108 +- 7", "note": "one step every ~0.57 s",
		"code": ["Rulebook.GAIT_CAD"], "need": [["step", "stride", "walk", "cadence"], ["rate", "cadence", "time", "often", "many"]], "kw": {"rate": 2, "cadence": 3, "time": 1}},
	{"id": "arm_swing", "topic": "arm swing while walking", "q": "how far do the arms swing in a walk?", "value": 29.0, "unit": "deg peak to peak", "range": [25.0, 33.0],
		"pop": "adults walking at 4 km/h", "trust": M, "url": "https://pubmed.ncbi.nlm.nih.gov/40291287/",
		"source": "PMID 40291287, 23236504: about 25-33 deg peak to peak per arm", "note": "the value is the middle of the cited range; arms swing against the same-side leg (Kubo et al. 2004)",
		"code": ["Rulebook.GAIT_ARM"], "need": [["arm"], ["swing"]], "kw": {"walk": 2}},
	{"id": "recovery_step_latency", "topic": "time to the first step after a shove", "q": "how fast does a person step to catch their balance?", "value": 0.25, "unit": "s", "range": [0.21, 0.29],
		"pop": "11 young adults, platform translation, backward step (forward: 0.36-0.42 s)", "trust": M, "url": "res://docs/physics_constants.md",
		"source": "Mansfield et al. 2015, Front Aging Neurosci 7:201, Table 3: 'Step latency (s) HY 0.25 +- 0.04'", "note": "onset to foot-off; the swing itself was not reported",
		"code": [], "need": [["recover"], ["step"], ["time", "fast", "long", "latency", "delay", "start"]], "kw": {}},
	{"id": "recovery_step_length", "topic": "length of the first step after a shove", "q": "how far is the first step after a push?", "value": 0.31, "unit": "m", "range": [0.25, 0.37],
		"pop": "11 young adults, leg length 91 cm, backward step at their step threshold (forward 0.27-0.33 m)", "trust": M, "url": "res://docs/physics_constants.md",
		"source": "Mansfield et al. 2015, Table 3: 'Step length (m) HY 0.31 +- 0.06'", "note": "at the threshold, not a maximal step",
		"code": [], "need": [["recover"], ["step"], ["far", "long"]], "kw": {"far": 1}},
	{"id": "jump_height", "topic": "jump height", "q": "how high can a man jump?", "value": 0.40, "unit": "m", "range": [0.29, 0.51],
		"pop": "recreational adults, countermovement jump on a force plate (elite ~0.70)", "trust": U, "url": "res://docs/MOTION_RULES.md",
		"source": "quoted in docs/MOTION_RULES.md (JUMP) without the paper named; height from flight time h = g T^2 / 8 (Bosco)",
		"note": "the flight time of a 0.40 m jump is 0.57 s", "code": ["Rulebook.JUMP_HIGH"], "need": [["jump"], ["high", "far"]], "kw": {}},
	{"id": "landing_knee", "topic": "knee bend on landing", "q": "how much do knees bend when landing a jump?", "value": 117.0, "unit": "deg knee flexion", "range": [77.0, 117.0],
		"pop": "drop landings from 59 cm: soft 117, stiff 77", "trust": M, "url": "https://pubmed.ncbi.nlm.nih.gov/1548984/",
		"source": "DeVita & Skelly 1992 (PMID 1548984); 40 cm drop jump, healthy controls 82.5 +- 9.0 (Rosen et al. 2015, PMID 26665034)", "note": "",
		"code": ["Rulebook.JUMP_LAND1"], "need": [["land"], ["knee", "flex"]], "kw": {"knee": 1}},
	{"id": "elbow_flex_max", "topic": "elbow range of motion", "q": "what is the max elbow flexion?", "value": 145.0, "unit": "deg", "range": [0.0, 145.0],
		"pop": "healthy adults", "trust": U, "url": "res://data/body_limits.json", "source": _ROM, "note": "Kine's elbow joint allows bend 0 to 145 (lowerarm_*)",
		"code": [], "need": [["elbow"], ["flex", "max"]], "kw": {}},
	{"id": "knee_flex_max", "topic": "knee range of motion", "q": "how far can a knee bend?", "value": 145.0, "unit": "deg", "range": [0.0, 145.0],
		"pop": "healthy adults", "trust": U, "url": "res://data/body_limits.json", "source": _ROM, "note": "Kine's knee allows bend 0 to 145 (calf_*)",
		"code": [], "need": [["knee"], ["flex", "max"]], "kw": {}},
	{"id": "hip_flex_max", "topic": "hip range of motion", "q": "what is the max hip flexion?", "value": 120.0, "unit": "deg", "range": [-25.0, 120.0],
		"pop": "healthy adults", "trust": U, "url": "res://data/body_limits.json", "source": _ROM, "note": "Kine's hip allows bend -25 (extension) to 120 (thigh_*)",
		"code": [], "need": [["hip", "thigh"], ["flex", "max"]], "kw": {}},
	{"id": "shoulder_turn_speed", "topic": "fastest shoulder rotation (throwing)", "q": "how fast can a shoulder rotate?", "value": 6520.0, "unit": "deg/s", "range": [6520.0, 7337.0],
		"pop": "collegiate pitchers, fastball (internal rotation)", "trust": M, "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC3445126/",
		"source": "Fortenbaugh, Fleisig & Andrews 2009, Sports Health 1(4):314 (PMC3445126); 25 pitchers 6594 +- 743 (Fleisig et al. 2016, PMC5435148)",
		"note": "the fastest joint motion people make; Check's JOINT SPEED bar", "code": ["HumanLimits.SPEED.shoulder", "SpeedEnv.CH.shoulder"],
		"need": [["shoulder", "throw"], ["fast", "speed", "turn"]], "kw": {"throw": 2, "internal": 2}},
	{"id": "trunk_turn_speed", "topic": "fastest trunk rotation", "q": "how fast can the torso turn?", "value": 1120.0, "unit": "deg/s", "range": [1101.0, 1190.0],
		"pop": "collegiate pitchers, upper trunk, fastball", "trust": M, "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC3445126/",
		"source": "Fortenbaugh 2009 (PMC3445126) 1120; Fleisig et al. 2016 (PMC5435148) 1101 +- 89", "note": "",
		"code": ["HumanLimits.SPEED.trunk", "SpeedEnv.CH.trunk"], "need": [["trunk"], ["fast", "speed", "turn"]], "kw": {"turn": 1}},
	{"id": "knee_extend_speed", "topic": "fastest knee extension (kicking)", "q": "how fast can a knee straighten in a kick?", "value": 1874.0, "unit": "deg/s", "range": [1719.0, 2029.0],
		"pop": "amateur male soccer players, kick (a group mean)", "trust": M, "url": "res://docs/research/HUMAN_LIMITS.md",
		"source": "Manolopoulos 2006 via the soccer-kick review JSSM 6:154, Table 4: 1874 +- 155; martial-arts roundhouse 947 +- 94 (Gavagan & Sayers 2017, PMC5571909)",
		"note": "", "code": ["HumanLimits.SPEED.knee", "SpeedEnv.CH.knee"], "need": [["knee"], ["fast", "speed", "extend"]], "kw": {"kick": 1, "fast": 1, "speed": 1}},
	{"id": "elbow_extend_speed", "topic": "fastest elbow extension", "q": "how fast can an elbow straighten?", "value": 2305.0, "unit": "deg/s", "range": [2084.0, 2526.0],
		"pop": "25 pitchers, 5 oz ball", "trust": M, "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5435148/",
		"source": "Fleisig et al. 2016, Sports Health 9(3):210 (PMC5435148): 'Elbow extension 2305 +- 221'", "note": "",
		"code": ["SpeedEnv.CH.elbow"], "need": [["elbow"], ["fast", "speed", "extend"]], "kw": {"fast": 1, "speed": 1}},
	{"id": "kick_foot_speed", "topic": "kick foot speed", "q": "how fast is a roundhouse kick?", "value": 14.66, "unit": "m/s", "range": [13.48, 15.84],
		"pop": "8 taekwondo black belts (karate 13.66)", "trust": M, "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5571909/",
		"source": "Gavagan & Sayers 2017, PLoS ONE 12(8):e0182645, Table 2: 'Max linear foot velocity 14.66 +- 1.18 m/s'", "note": "",
		"code": ["SpeedEnv.CH.foot"], "need": [["kick"], ["fast", "speed"]], "kw": {"foot": 1}},
	{"id": "hitter_hip_turn", "topic": "hip turn in a bat swing", "q": "how fast do a hitter's hips turn?", "value": 389.0, "unit": "deg/s", "range": null,
		"pop": "3 hitters", "trust": M, "url": "https://ojs.ub.uni-konstanz.de/cpa/article/view/6368/5737",
		"source": "ISBS 2015: pelvis 389, trunk 601, bat 1953 deg/s peaks, in that order", "note": "Check's HIPS TURN warns under a quarter of it",
		"code": ["Rulebook.HIPS_MIN"], "need": [["weapon", "hitter", "hit", "baseball", "swing"], ["hip", "pelvis"]], "kw": {"turn": 1, "fast": 1}},
	{"id": "kick_hip_turn", "topic": "hip (pelvis) turn speed in a kick", "q": "how fast do the hips turn?", "value": 493.0, "unit": "deg/s", "range": [287.0, 699.0],
		"pop": "8 Muay Thai black belts, roundhouse (karate 452 +- 71)", "trust": M, "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC5571909/",
		"source": "Gavagan & Sayers 2017, Table 2: 'Max pelvis axial rotation 493 +- 206 deg/s'", "note": "",
		"code": ["SpeedEnv.CH.pelvis"], "need": [["hip", "pelvis"], ["fast", "speed", "turn"]], "kw": {"kick": 2}},
	{"id": "wrist_torque", "topic": "wrist strength", "q": "how much torque can a wrist give?", "value": 14.9, "unit": "N m", "range": [11.5, 18.3],
		"pop": "20 men, radial deviation, concentric, 90 deg/s (women 8.5)", "trust": M, "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC12551099/",
		"source": "'Isokinetic Strength Profile of the Wrist Muscles' (2025), PMC12551099, Table 1; men flexion 17.0, extension 8.8, ulnar deviation 26.5",
		"note": "the weapon-weight judge's wrist ceiling", "code": ["WeaponTorque.WRIST_MAX"], "need": [["wrist"], ["force"]], "kw": {}},
	{"id": "shoulder_torque", "topic": "shoulder strength (raising the arm)", "q": "how strong is a shoulder?", "value": 77.2, "unit": "N m", "range": [63.4, 91.0],
		"pop": "14 healthy men, isometric flexion at 90 deg, standing (43.2 at 160 deg)", "trust": M, "url": "res://docs/physics_constants.md",
		"source": "Aronis et al., J Funct Morphol Kinesiol 11(1):20 (2026), Table 1: '77.24' (SD 13.81)", "note": "the weapon-weight judge's shoulder ceiling",
		"code": ["WeaponTorque.SHOULDER_MAX"], "need": [["shoulder"], ["force"]], "kw": {"raise": 1, "lift": 1}},
	{"id": "shoulder_throw_torque", "topic": "shoulder torque in a throw", "q": "how much torque does a shoulder make when throwing?", "value": 67.0, "unit": "N m", "range": null,
		"pop": "26 highly skilled adult pitchers, internal rotation, acceleration phase", "trust": M, "url": "res://docs/research/HUMAN_LIMITS.md",
		"source": "Fleisig 1995, AJSM 23:233 (abstract): '67 N-m of shoulder internal rotation torque'", "note": "Check's JOINT TORQUE bar (opt-in)",
		"code": ["HumanLimits.SHOULDER_IR_NM"], "need": [["shoulder"], ["force"], ["throw", "internal", "turn"]], "kw": {}},
	{"id": "braking_force", "topic": "how hard a person can brake", "q": "how much force does a person use to stop?", "value": 1.6, "unit": "x body weight (horizontal)", "range": [1.54, 1.60],
		"pop": "27 male multi-sport players, braking step", "trust": M, "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC9474351/",
		"source": "Dos'Santos et al., table in Harper et al. 2022, Sports Med 52 (PMC9474351): 'PFC peak horizontal GRF (BW): 90 = 1.60, 180 = 1.54'",
		"note": "total (not horizontal) GRF in rapid deceleration is ~4-6 BW", "code": ["Momentum.BRACE_BW"],
		"need": [["brake"], ["force", "ground", "grf", "bodyweight", "hard"]], "kw": {}},
	{"id": "body_accel", "topic": "how hard the whole body can speed up (sprint start)", "q": "how fast can a person accelerate?", "value": 10.0, "unit": "m/s^2", "range": [7.0, 11.0],
		"pop": "666 athletes of 23 sports, men (women 6-9); world-class male sprinters ~11", "trust": M, "url": "https://doi.org/10.1371/journal.pone.0215551",
		"source": "Haugen, Breitschaedel & Seiler 2019, PLoS ONE 14(7):e0215551: sprint F0 'in the range 7-10 N/kg for men'; world-class sprinters ~11 and ~10 N/kg (men / women) as the paper cites them",
		"note": "F0 is the push at zero speed, so the start is the hardest a body accelerates: 0 to 5 m/s takes at least ~0.5 s; 0 to 8 m/s in 0.2 s (40 m/s^2) is no human. Check's BODY ACCEL warns past 10, fails past 11",
		"code": ["BodyCaps.START_WARN", "BodyCaps.START_FAIL"], "need": [["accel"]], "kw": {"start": 2, "sprint": 2, "fast": 1, "forward": 1, "speed": 1}},
	{"id": "body_decel", "topic": "how hard the whole body can slow down (stop)", "q": "how fast can a person stop?", "value": 8.48, "unit": "m/s^2", "range": [4.4, 11.02],
		"pop": "team-sport players: 20 m sprint-to-stop peak 8.48 (average 4.44); youth soccer 505 turn, fast group, peak 11.02", "trust": M, "url": "https://doi.org/10.1007/s40279-022-01693-0",
		"source": "Harper et al. 2022, Sports Med 52:2321 (PMC9474351), Tables 1-2: 'Peak DEC (m/s^2) = -8.48' (Harper et al.), 'fast COD = -11.02' (Kaneko et al.)",
		"note": "people brake harder than they speed up (soccer: -5.7 to -6.3 vs 4.4-4.7 m/s^2, same review). Check's BODY ACCEL warns past 8.48, fails past 11.02",
		"code": ["BodyCaps.STOP_WARN", "BodyCaps.STOP_FAIL"], "need": [["brake"], ["fast", "accel", "time", "speed", "long"]], "kw": {"accel": 1}},
	{"id": "body_cut", "topic": "how hard the whole body can change direction (cut)", "q": "how fast can a person change direction?", "value": 11.5, "unit": "m/s^2", "range": [6.8, 13.1],
		"pop": "10 highly trained / elite American football players, 45 deg cut at max effort from 6.66 m/s", "trust": M, "url": "https://doi.org/10.3389/fspor.2025.1576614",
		"source": "Yamashita, Inaba, Asakura & Ito 2025, Front Sports Act Living 7:1576614, Table 2: execution-step medial impulse 1.75 +- 0.12 Ns/kg over a 0.152 s stance (the next step 1.02 over 0.149 s = 6.8); the m/s^2 are derived (impulse / stance)",
		"note": "a 45 deg cut is spread over 3 steps (15 deg on the plant step). Check's BODY ACCEL warns past 11.5, fails past 13.1 (mean + 2 SD)",
		"code": ["BodyCaps.CUT_WARN", "BodyCaps.CUT_FAIL"], "need": [["cut", "direction", "swerve"], ["fast", "accel", "speed", "hard", "quick", "change"]], "kw": {"cut": 2, "direction": 2}},
	{"id": "jump_push", "topic": "how hard a jump pushes the body up", "q": "how hard does a jump push the body up?", "value": 14.7, "unit": "m/s^2 net upward", "range": [12.6, 19.0],
		"pop": "38 NCAA D1 male basketball / volleyball players, countermovement jump on a force plate (30 women: 22.07 +- 1.3 N/kg)", "trust": M, "url": "https://doi.org/10.3390/sports13090292",
		"source": "Lin, Goldstein & Schroeder 2025, Sports 13(9):292, Table 2: relative concentric peak force 24.51 +- 2.17 N/kg; net of g = 24.51 - 9.81",
		"note": "the force-plate peak, about 2.5 body weights. Check's BODY ACCEL warns past 14.7 net, fails past 19.0",
		"code": ["BodyCaps.RISE_WARN", "BodyCaps.RISE_FAIL"], "need": [["jump"], ["accel", "recover", "force"]], "kw": {"recover": 2, "accel": 2}},
	{"id": "fall_rate", "topic": "how fast a body falls", "q": "how fast does a body fall?", "value": 9.81, "unit": "m/s^2", "range": null,
		"pop": "physics", "trust": M, "url": "res://docs/research/BODY_SPEED_CAPS.md",
		"source": "standard gravity: feet only push, so without a hand pulling down nothing makes the centre of mass drop faster than g",
		"note": "a 1 m drop takes 0.45 s and lands at 4.4 m/s. Check's BODY ACCEL fails a drop past 1.1 g with no hand holding on",
		"code": ["BodyCaps.GRAV"], "need": [["fall", "drop"], ["fast", "accel", "speed", "time", "long"]], "kw": {"fall": 2}},
	{"id": "wrist_stiffness", "topic": "how stiff a wrist can be held", "q": "how stiff is a braced wrist?", "value": 19.5, "unit": "N m/rad", "range": [4.0, 32.0],
		"pop": "10 adults (Milner 1995, experiment 1)", "trust": M, "url": "res://docs/physics_constants.md",
		"source": "Milner, Cloutier, Leger, Franklin 1995, Exp Brain Res 107:293: 0.34 N m/deg maximal voluntary stiffening; passive 0.07 N m/deg, 0.56 at the stability limit",
		"note": "", "code": ["WeaponRebound.K_WRIST"], "need": [["wrist"], ["stiff"]], "kw": {}},
	{"id": "head_move_swing", "topic": "head movement in a swing", "q": "how much does the head move in a swing?", "value": 0.09, "unit": "m", "range": null,
		"pop": "baseball hitters", "trust": M, "url": "https://sabr.org/journal/article/baseball-swing-stride-and-head-movement-relationships/",
		"source": "Inkster et al., reported in a SABR review (the primary paper was not read)", "note": "Check's HEAD QUIET warns at 15 cm (9 + 6 grace)",
		"code": ["Rulebook.HEAD_WARN"], "need": [["head"], ["move"]], "kw": {"swing": 1, "hitter": 1, "weapon": 1}},
	{"id": "segment_mass", "topic": "body part masses", "q": "how heavy is an arm / a leg / the head?", "value": null, "unit": "% of body mass", "range": null,
		"pop": "100 college-age men (de Leva's adjustment of Zatsiorsky-Seluyanov)", "trust": M, "url": "https://doi.org/10.1016/0021-9290(95)00178-6",
		"source": "de Leva 1996, J Biomech 29(9):1223, Table 4 (male)", "note": "a 75 kg man: forearm 1.2 kg, thigh 10.6 kg, head 5.2 kg",
		"code": ["Balance.MASS"], "need": [["mass"], ["head", "trunk", "arm", "forearm", "hand", "thigh", "leg", "foot", "calf", "segment", "part", "limb"]], "kw": {}},
	{"id": "weapon_tip_speed", "topic": "weapon tip speed", "q": "how fast does a bat tip move?", "value": 40.0, "unit": "m/s", "range": [15.0, 40.0],
		"pop": "-", "trust": U, "url": "res://docs/ATTACK_RULES.md",
		"source": "docs/ATTACK_RULES.md: a pro bat ~40, a staff end ~30, a knife ~15 (the hand): no opened source", "note": "the TIP SPEED rule's caps; argue with them",
		"code": ["AttackTiming.TIP_MAX"], "need": [["weapon"], ["fast", "speed"]], "kw": {"weapon": 2}},
	{"id": "steel_bounce", "topic": "how much steel on steel bounces", "q": "what is the coefficient of restitution of steel?", "value": 0.46, "unit": "-", "range": [0.40, 0.53],
		"pop": "steel balls dropped 0.28-1.27 m on a steel prism", "trust": M, "url": "res://docs/physics_constants.md",
		"source": "Ciornei & Alaci 2014, Ann Univ Oradea, Table I (mean of ten); steel on aluminium 0.28", "note": "falls with impact speed",
		"code": ["WeaponRebound.E_STEEL", "WeaponRebound.E_ALUMINIUM"], "need": [["bounce"]], "kw": {"steel": 1}},
]

## de Leva parts for segment_mass (Balance.MASS keys, split trunk summed)
const PART_WORD := {"head": ["head", 6.94], "trunk": ["trunk", 43.46], "arm": ["upper arm", 2.71], "forearm": ["forearm", 1.62],
	"hand": ["hand", 0.61], "thigh": ["thigh", 14.16], "leg": ["thigh", 14.16], "calf": ["shank", 4.33], "foot": ["foot", 1.37]}


static func _stem(t: String) -> String:
	if t.length() > 5 and t.ends_with("ing"):
		t = t.left(-3)
		if t.length() > 2 and t.right(1) == t.substr(t.length() - 2, 1) and not t.right(1) in ["s", "l"]:
			t = t.left(-1)
	elif t.length() > 5 and t.ends_with("ed"):   # not "speed" / "need"
		t = t.left(-2)
		if t.length() > 2 and t.right(1) == t.substr(t.length() - 2, 1) and not t.right(1) in ["s", "l"]:
			t = t.left(-1)
	elif t.ends_with("ches") or t.ends_with("shes") or t.ends_with("xes") or t.ends_with("sses"):
		t = t.left(-2)
	elif t.length() > 4 and t.ends_with("ies"):
		t = t.left(-3) + "y"
	elif t.length() > 3 and t.ends_with("s") and not t.ends_with("ss"):
		t = t.left(-1)
	return t


## the question's canonical words
static func words(q: String) -> Array:
	var s := q.to_lower().replace("m/s", " mps ").replace("n m", " nm ").replace("n-m", " nm ")
	var clean := ""
	for ch in s:
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else " "
	var out := []
	for t: String in clean.split(" ", false):
		var c: String = SYN.get(t, "")
		if c == "":
			var st := _stem(t)
			c = SYN.get(st, st)
		for w in c.split(" ", false):
			if not w in out:
				out.append(w)
	return out


## [score, every NEED group hit, the words that counted]
static func score(f: Dictionary, ws: Array) -> Array:
	var sc := 0
	var all := true
	var hit := []
	for g: Array in f["need"]:
		var any := false
		for w in g:
			if w in ws:
				any = true
				if not w in hit:
					hit.append(w)
		if any:
			sc += 2
		else:
			all = false
	for w in f["kw"]:
		if w in ws:
			sc += int(f["kw"][w])
			if not w in hit:
				hit.append(w)
	return [sc, all, hit]


## a fact as served (computed fields filled)
static func card(f: Dictionary, ws := []) -> Dictionary:
	var d := f.duplicate(true)
	d.erase("need")
	d.erase("kw")
	if d["id"] == "punch_duration":
		var r: Array = TimingCoach.peak_range(0.6)
		d["range"] = [snappedf(r[0], 0.001), snappedf(r[1], 0.001)]
		d["value"] = snappedf((r[0] + r[1]) * 0.5, 0.001)
		d["note"] = String(d["note"]) + "; the value is the middle of the range"
	elif d["id"] == "segment_mass":
		var table := {}
		for k in Balance.MASS:
			table[k] = Balance.MASS[k]
		d["table"] = table
		for w in ws:
			if PART_WORD.has(w):
				d["value"] = PART_WORD[w][1]
				d["topic"] = "%s mass" % PART_WORD[w][0]
				break
	d["code"] = f["code"].map(func(n): return {"name": n, "value": Trust.value(n), "status": Trust.REG.get(n, {}).get("s", U)})
	var rg := "" if d["range"] == null else " (range %s to %s)" % [d["range"][0], d["range"][1]]
	var v := "see table" if d["value"] == null else str(d["value"])
	d["answer"] = "%s: %s %s%s. %s [%s]" % [d["topic"], v, d["unit"], rg, d["source"], d["trust"]]
	return d


## {found, ...}: the best fact, or "no cited number" and the nearest topics
static func ask(q: String) -> Dictionary:
	var ws := words(q)
	var best := -1
	var best_sc := -1
	var also := []
	var near := []
	for i in FACTS.size():
		var s := score(FACTS[i], ws)
		if s[1]:
			also.append(FACTS[i]["id"])
			if s[0] > best_sc:
				best_sc = s[0]
				best = i
		elif s[0] > 0:
			near.append([s[0], i])
	if best >= 0:
		var d := card(FACTS[best], ws)
		d["found"] = true
		d["question"] = q
		d["matched"] = score(FACTS[best], ws)[2]
		also.erase(d["id"])
		d["also"] = also
		return d
	near.sort_custom(func(a, b): return a[0] > b[0])
	var nt := []
	for n in near.slice(0, 3):
		nt.append({"id": FACTS[n[1]]["id"], "topic": FACTS[n[1]]["topic"], "ask": FACTS[n[1]]["q"]})
	if nt.is_empty():
		for f in FACTS.slice(0, 5):
			nt.append({"id": f["id"], "topic": f["topic"], "ask": f["q"]})
	return {"found": false, "question": q, "answer": "no cited number", "nearest": nt,
		"note": "Kine has no cited number for this; it will not guess. `facts {list: true}` lists every topic."}


static func list() -> Array:
	return FACTS.map(func(f): return {"id": f["id"], "topic": f["topic"], "ask": f["q"], "trust": f["trust"], "unit": f["unit"]})


## serve's facts {q} | {list: true} | {registry: true}
static func serve(p: Dictionary) -> Dictionary:
	if p.get("list", false):
		return {"facts": list(), "count": FACTS.size()}
	if p.get("registry", false):
		return {"registry": Trust.registry()}
	var q := String(p.get("q", "")).strip_edges()
	if q == "":
		return {}
	return ask(q)
