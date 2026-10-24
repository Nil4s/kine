## rulebook.gd - recorded human numbers a move is graded against (Nick 10-14: "plenty of humans recorded maths and numbers
## about those animations"). Every rule names its source and its bar (docs/MOTION_RULES.md is the human-readable table).
## One pass samples the scene at 60 fps into series (sample()); each rule is a pure function over them, so a test can
## feed it a broken series on purpose. check() = both, a list of findings:
##   {"sev": "FAIL"/"WARN", "t": seconds, "card": index, "rule": "HEAD QUIET", "msg": plain words with the number vs the bar}
## The weapon's own timing rules live in tools/attack_timing.gd (docs/ATTACK_RULES.md): its tables are REUSED here.
class_name Rulebook
extends RefCounted

const AT := preload("res://tools/attack_timing.gd")
const FPS := 60.0

## the sources (docs/MOTION_RULES.md has the links)
const SRC := {
	"SEQUENCE": "pelvis -> trunk -> bat peak in that order in hitting (ISBS 2015, 3 hitters: 389 / 601 / 1953 deg/s)",
	"HIPS TURN": "hitters' pelvis peaks ~389 deg/s (ISBS 2015); warned below a quarter of it",
	"HEAD QUIET": "hitters' heads drop ~9 cm over the whole swing (Inkster et al., via SABR); skilled = steadier (Nakata)",
	"TIP SPEED": "the weapon's real tip cap (docs/ATTACK_RULES.md: pro bat ~37-40 m/s, staff end ~30, knife ~15)",
	"STRIKE FRAMES": "the swing itself <= the weapon's frame budget at 30 fps (docs/ATTACK_RULES.md, Aztez)",
	"FIST SPEED": "boxers' fastest punch (lead hook) 11.95 +- 1.84 m/s (Stanley et al. 2018); straight 9.3 +- 2.1 (Piorkowski 2011)",
	"HITCH": "a point-to-point move has ONE bell-shaped speed peak (Flash & Hogan 1985, J. Neurosci. 5(7))",
	"BALANCE": "centre of mass from the body parts' masses (de Leva 1996, J. Biomech. 29(9)) over the feet on the floor",
	"LOOP SEAM": "a loop must not show where it starts: the last frame meets the first in pose and in speed (our own bars, docs/MOTION_RULES.md)",
	"FOOT SLIDE": "foot skating: a foot under 5 cm off the floor that slides more than 2.5 cm (Karunratanakul et al. 2023, the motion-generation standard; there per frame, here per planted stretch: stricter)",
	"THROUGH A PROP": "a body part or the weapon inside a prop of the set (Props.depth, the capsules against the prop's boxes; resting ON a top is allowed): our own bars, docs/MOTION_RULES.md",
	"FLOATS": "the hips over a seat but not on it while no foot carries the body: our own bars, docs/MOTION_RULES.md",
	"JUMP": "a flight of T seconds is a jump of g T^2 / 8 (Bosco; Asmussen & Bonde-Petersen): a recreational adult's countermovement jump is 0.40 +- 0.11 m (0.57 s); people dip to ~90 deg of knee bend before take-off and land soft on ~117 deg (stiff ~77; DeVita & Skelly 1992)",
	"CARRY FORM": "a load carried in front in both hands is held close at knuckle-to-elbow height: upper arms near the trunk, elbows bent (Anderson et al. 2007, anterior load carriage; Snook 1978), hands near the body (NIOSH lifting equation: H 25 cm ideal, the multiplier 25/H)",
	"GAIT": "a walk against real walkers (round 42, GATES XX8): step length 0.415 +- 0.038 of body height and 1.33 m/s at the preferred speed (Gait Posture 2009, 21 young adults, PMID 19502061); cadence 105.5 +- 5.2 steps/min (PMID 29775941) and 108 +- 7 (PMID 41879248); arm swing about 25-33 deg peak to peak at 4 km/h (PMID 40291287, PMID 23236504), the arms out of phase with each other and 1:1 with the legs at walking speeds (Kubo et al. 2004, PMID 15351887)",
	"LIFT FORM": "reaching the floor with the hands: people who squat bend the knees deep (floor lifts peak at 86-115 deg of knee bend, Saraceni et al. 2021); a stoop (the lifting studies' own definition: knees 0-30 deg, Int J Sports Med 2025) with the trunk past 60 deg of flexion (where the back muscles go quiet and the passive tissues take the load, Shu et al. 2007) loads the spine more than a squat (Bazrgari et al. 2007)",
	"JOINT SPEED": "a joint's turn against the PEAK turn recorded in sport (fast dynamic movements): shoulder internal rotation 6520 deg/s (collegiate pitchers, Fortenbaugh et al. 2009 review), upper trunk 1120 (same review), knee in a kick 1874 (Manolopoulos 2006, via a kick review); the hip is not graded (its 745 is a secondary kick mean); FAIL at 1.32 x the peak (mean + 2 SD with the SD of Campbell's shoulder table): docs/research/HUMAN_LIMITS.md",
	"JOINT TORQUE": "the shoulder's net moment from inverse dynamics (forearm and hand with their rotational inertia from de Leva 1996 radii; a bat shared between the two hands) against the in-sport peak: shoulder internal rotation 67 Nm in pitching (Fleisig 1995, 26 skilled adults; scaled linearly with mass from 75 kg), FAIL at 1.32 x (docs/research/HUMAN_LIMITS.md). Knee not graded (no in-sport moment read)",
	"TIPPING": "the centre of mass past the feet, with no hand or weapon holding it, for longer than a fall from its height takes: t = sqrt(2h/g) (our bar, the free-fall time of the centre of mass; docs/research/HUMAN_LIMITS.md)",
	"FEASIBLE": "PASS / FIX / IMPOSSIBLE for the whole clip: KungfuBot's physics filter (Xie et al. 2025, arXiv:2506.12851: first and last frame stable, no unstable run of 100 frames, stable = centre of mass within 0.1 of the centre of pressure), free fall in the air (g = 9.81), foot slide per contact and self-penetration (docs/research/ROBOT_MOTION.md)",
	"FEASIBLE BALANCE": "KungfuBot's whole-clip rule (Xie et al. 2025, Eq. 1 and Table 3): first and last frames stable, centre of mass within 0.1 m of the support, no unstable run of 100 frames (3.3 s at 30 fps)",
	"FEASIBLE FLIGHT": "with no foot down the centre of mass follows free fall, y = y0 + v t - g t^2/2, g = 9.81, within 8 cm (our bar; docs/research/ROBOT_MOTION.md)",
	"FEASIBLE SLIDE": "a planted foot may creep at most 25 mm per contact (Karunratanakul et al. 2023, arXiv:2310.08580)",
	"FEASIBLE PENETRATION": "body capsules inside each other deeper than 20 mm (our bar, Body.contacts)",
	"COUPLED LIMIT": "two-joint muscles (N028, scripts/coupled_limits.gd): hip flexion with the knee straight against the straight-leg raise (90 deg in healthy adults, Thomas et al. 2022; gymnasts 141, Donti et al. 2020), ankle dorsiflexion with the knee straight (25 vs 39 bent, Baumbach et al. 2014), hip extension with the knee bent (modified Thomas test, Ferber et al. 2010); the curves between the points are interpolated (docs/research/COUPLED_LIMITS.md)",
	"WEIGHT TRANSFER": "each strike starts with the weight where it needs it (N029, scripts/weight_xfer.gd): a cross off the back foot (Evolve MMA: more than half on the rear leg before it; Peloton: from the back foot to the front), a lead hook over the lead side (Boxing News: the weight shifts to the front foot), a kick with the support foot loaded before the kicking leg leaves (statics; Kinoshita & Fujii 2014, ISBS: the support leg drives the phase before toe-off); the share is the lever rule over the feet (N001); the bars are ours (docs/research/WEIGHT_TRANSFER.md)",
	"TRUNK LEAN": "the trunk (pelvis to neck) against vertical, per move (scripts/trunk_lean.gd): a roundhouse's pelvis tilts back through 60 +- 8 deg while the trunk counter-bends 22 +- 7 deg on it (Kim, Yenuga & Kwon 2008, ISBS, 12 black belts); punches and walking keep the trunk near upright; the bars are ours, set from those ranges (docs/research/TRUNK_LEAN.md)",
	"ASSERT": "a check line saved in the scene (N002, scripts/body_assert.gd): the bars are the line's own numbers; touching = within 1 cm (Balance.TOUCH), planted = toe base within 2 cm of its standing height (Body.foot_state) and sliding under 2.5 cm (FOOT SLIDE's bar)",
}
## WHY each rule matters, in a sentence anyone can read (round 11, #78: the CHECK panel shows it under the finding),
## and WHERE the number comes from (the panel's "source" button opens it). The links are docs/MOTION_RULES.md's own
## (tests/why_test.gd checks they agree); a rule whose source is a book or our own table points at that doc
const WHY := {
	"SEQUENCE": "Power travels up the body: hips first, then chest, then the weapon. Out of order, the swing reads as all arms.",
	"HIPS TURN": "A strike starts in the hips. If they barely turn, the swing looks weak however fast the arms go.",
	"HEAD QUIET": "Real fighters keep the head steady through the strike. A bobbing head reads as off balance.",
	"TIP SPEED": "Faster than a real weapon can move: the eye reads it as cartoon, not power.",
	"STRIKE FRAMES": "The hit itself must be quick. Too many frames at speed and it looks like a push, not a strike.",
	"FIST SPEED": "Faster than the best recorded punches: it stops looking human.",
	"HITCH": "A real move speeds up and slows down once. A stop in the middle reads as a glitch.",
	"BALANCE": "With both feet down, the weight must stay over the feet. Past them he would fall: it reads as weightless.",
	"LOOP SEAM": "A loop plays round and round. If the end does not meet the start, every lap jumps at the same place.",
	"FOOT SLIDE": "A planted foot that slides looks like ice skating, the most noticed mistake in animation.",
	"THROUGH A PROP": "A table, a chair, a box are solid. A hand or a weapon passing through one breaks the scene at once.",
	"FLOATS": "Sitting means the seat carries the weight. Hips hovering over it, with nothing else holding him up, read as a ghost.",
	"JUMP": "Air time IS the height: hang too long and he floats like the Moon. And a jump starts in a dip and ends in a squat; straight legs at either end read as a puppet on a string.",
	"CARRY FORM": "Nobody carries a box on straight arms held out in front: it is held against the body, arms down at the sides, elbows bent. Anything else reads as fake at once.",
	"GAIT": "A walk has a stride people know at a glance: steps about 0.4 of the body height, 100-110 a minute, the arms swinging against the legs. Half that cadence is a slow-motion shuffle, double that step is a stride-jump, and arms that swing with the same-side leg read as a march.",
	"LIFT FORM": "Picking something off the floor with straight knees and a bent back is the lift that hurts backs, and it reads as careless. People bend the knees and keep the trunk more upright.",
	"JOINT SPEED": "A joint turning faster than people turn that joint in sport: the eye reads it as a snap, not a body.",
	"JOINT TORQUE": "More force at a joint than people's muscles give: the motion needs a machine, not a person.",
	"TIPPING": "Leaning past the feet with nothing to grab: a real person is on the floor in the time a fall takes.",
	"FEASIBLE": "One answer for the clip: could a body actually do it, as it is keyed? The reasons and the frames are listed.",
	"FEASIBLE BALANCE": "A person has to start and end the clip standing, and cannot hang far outside their feet for long.",
	"FEASIBLE FLIGHT": "In the air nothing pushes: the body follows a parabola. Hovering or swerving mid-jump reads as wires.",
	"FEASIBLE SLIDE": "A planted foot that slides looks like ice skating, and a robot or a rig cannot follow it.",
	"FEASIBLE PENETRATION": "Limbs passing through the body or each other cannot be done by a solid person or a robot.",
	"COUPLED LIMIT": "Some muscles cross two joints: a straight knee keeps the hamstrings long, so a straight-leg kick cannot go as high as a bent-knee one. Past that, only a trained body (a gymnast, a dancer) does it.",
	"WEIGHT TRANSFER": "A strike is thrown from the legs: a cross pushes off the back foot, a kick needs the other foot holding him before it leaves. Started from the wrong foot, it reads as an arm swing, or as a kick that should topple him.",
	"TRUNK LEAN": "The trunk leans off a kick to balance it, but only so far: past what fighters are measured at, the back looks broken or he looks about to fall.",
	"ASSERT": "Someone wrote this down as something the motion must do. It no longer does: an edit broke it, or it never held."
}
const URL := {
	"SEQUENCE": "https://ojs.ub.uni-konstanz.de/cpa/article/view/6368/5737",
	"HIPS TURN": "https://ojs.ub.uni-konstanz.de/cpa/article/view/6368/5737",
	"HEAD QUIET": "https://sabr.org/journal/article/baseball-swing-stride-and-head-movement-relationships/",
	"TIP SPEED": "res://docs/ATTACK_RULES.md",
	"STRIKE FRAMES": "res://docs/ATTACK_RULES.md",
	"FIST SPEED": "https://chesterrep.openrepository.com/entities/publication/0acdae9d-e8be-48cf-816e-ed9c667981b3",
	"HITCH": "res://docs/MOTION_RULES.md",   # Flash & Hogan 1985, J. Neurosci. 5(7): a journal citation, no free link
	"FOOT SLIDE": "https://arxiv.org/pdf/2310.08580",
	"LOOP SEAM": "res://docs/MOTION_RULES.md",
	"BALANCE": "https://doi.org/10.1016/0021-9290(95)00178-6",
	"THROUGH A PROP": "res://docs/MOTION_RULES.md",
	"FLOATS": "res://docs/MOTION_RULES.md",
	"CARRY FORM": "https://stacks.cdc.gov/view/cdc/189155",
	"JUMP": "https://pubmed.ncbi.nlm.nih.gov/1548984/",
	"GAIT": "https://pubmed.ncbi.nlm.nih.gov/19502061/",
	"LIFT FORM": "https://pubmed.ncbi.nlm.nih.gov/17103232/",
	"JOINT SPEED": "res://docs/research/HUMAN_LIMITS.md",
	"JOINT TORQUE": "res://docs/research/HUMAN_LIMITS.md",
	"TIPPING": "res://docs/research/HUMAN_LIMITS.md",
	"FEASIBLE": "res://docs/research/ROBOT_MOTION.md",
	"FEASIBLE BALANCE": "https://arxiv.org/abs/2506.12851",
	"FEASIBLE FLIGHT": "res://docs/research/ROBOT_MOTION.md",
	"FEASIBLE SLIDE": "https://arxiv.org/pdf/2310.08580",
	"FEASIBLE PENETRATION": "res://docs/research/ROBOT_MOTION.md",
	"COUPLED LIMIT": "res://docs/research/COUPLED_LIMITS.md",
	"WEIGHT TRANSFER": "res://docs/research/WEIGHT_TRANSFER.md",
	"TRUNK LEAN": "res://docs/research/TRUNK_LEAN.md",
	"ASSERT": "res://scripts/body_assert.gd",
}
## THE SET (round 38, GATES TT1 / TT4)
const PROP_WARN := 0.005   # m inside a prop: a WARN (Props.REST_SINK: less is resting on it)
const PROP_FAIL := 0.02    # m: a FAIL
const SOLE_SINK := 0.01    # m: a SOLE on a top may be this far in: the floor itself lets the soles dip 6.75 mm mid-move
                           # (the planting pass after grounding; measured round 38 with an arm-raise on the floor)
const FLOAT_MIN := 0.02    # m: the hips this far over a seat they are over...
const FLOAT_MAX := 0.15    # ...up to this (higher is not "meant to sit")
const FLOAT_RUN := 6       # frames (0.1 s)
## CARRY FORM (round 39, Nick: "we never saw a human holding a box like that"): two-handed front carry, from real people
const CARRY_UP := 35.0     # deg: an upper arm further than this from hanging down is holding the load out, not carrying
const CARRY_FLEX := [50.0, 130.0]   # deg elbow flexion: carried loads ride on bent elbows (knuckle to elbow height)
## JUMP (round 40, GATES VV2, #228): from real jumps (sources in SRC)
const JUMP_HIGH := 0.70    # m: over this the flight is a jump few people can make (CMJ 0.40 +- 0.11; elite ~0.70)
const JUMP_LAND := 45.0    # deg: the deeper knee's most bend in the 0.25 s after touchdown under this = stiff
# LANDING vs HEIGHT (round 41, GATES WW10, #312): the stiff bar rises with the fall (= apex height, level landing).
# Verified points: DeVita & Skelly 1992 (PMID 1548984) 59 cm: stiff 77 / soft 117 deg of knee flexion; Rosen et al. 2015
# (PMID 26665034) 40 cm drop jump, healthy controls: peak knee flexion 82.5 +- 9.0. No paper found gives a clean
# bend-vs-height line, so the bar is MINE: JUMP_LAND at JUMP_FALL0 (0.40 m, the recreational jump, where the old bar
# stood) rising straight to the stiffest measured landing, 77 deg, at 0.59 m, the same line beyond it (extrapolated,
# stated), never past JUMP_LAND_MAX (a soft landing is 117).
const JUMP_FALL0 := 0.40
const JUMP_FALL1 := 0.59
const JUMP_LAND1 := 77.0
const JUMP_LAND_MAX := 110.0
const JUMP_DIP := 30.0     # deg: the deeper knee's most bend in the 0.5 s before take-off under this = no dip
## LIFT FORM (round 41, GATES WW9, #229): hands below the knees, trunk flexed past LIFT_TRUNK with the knees bent under LIFT_KNEE
const LIFT_TRUNK := 60.0   # deg: trunk flexion (hips to neck against vertical); Shu 2007 tested 45 vs 60 deg, the multifidus quiets as it grows
const LIFT_KNEE := 30.0    # deg: the deeper knee's bend; the 2025 lifting study defines a stoop as knees 0-30 deg (squat free / 0-60 / 0-90)
## GAIT (round 42, GATES XX8, #333): a walk = 4 or more alternating foot plants that travel 0.5 m or more with no flight
const GAIT_STEP := [0.30, 0.55]   # step length / body height: people 0.415 +- 0.038 (PMID 19502061); the bar is ~3 SD each way, mine
const GAIT_CAD := [75.0, 135.0]   # steps/min: people 105.5 +- 5.2 and 108 +- 7 (PMID 29775941, 41879248); slow to brisk walks, mine
const GAIT_ARM := [10.0, 60.0]    # deg, peak to peak per arm: people ~25-33 +- 11 (PMID 40291287, 23236504); mine
const GAIT_PHASE := 0.3           # r between an arm's and the SAME-side thigh's angle: people swing them against each other (r < 0)
const GAIT_CROWN := 0.14          # m from the head joint to the top of the head (mine) for the body height
const GAIT_STILL := 0.015         # m per 60 fps frame (0.9 m/s): a planted foot moves less
const GAIT_PLANT := 4             # frames a foot stays down to count as a plant
const GAIT_MOVED := 0.05         # m: a step shorter than this is feet brought together, not a stride
const GAIT_FLIGHT := 6            # frames with both balls off the floor = a run, not a walk
const CARRY_H := 0.40      # m, hands' middle from the ankles' middle, along the floor (NIOSH: 25 ideal; 40 -> 25/H = 0.63)
const PART_WORDS := {"pelvis": "hips", "hips_wide": "hips", "chest_wide": "chest", "spine_01": "lower back",
	"spine_02": "middle back", "spine_03": "chest", "neck_01": "neck", "head": "head", "clavicle": "shoulder",
	"upperarm": "upper arm", "lowerarm": "forearm", "hand": "hand", "thigh": "thigh", "calf": "shin", "foot": "foot",
	"ball": "toes", "bat_handle": "weapon's handle", "bat_barrel": "weapon", "wep2_handle": "second weapon's handle",
	"wep2_blade": "second weapon"}
const HIPS_MIN := 389.0 / 4.0      # deg/s
const HEAD_WARN := 0.15            # m from where it was as the swing began (9 cm recorded + 6 cm grace)
const HEAD_FAIL := 0.30
const FIST_WARN := 11.95           # m/s: the recorded mean of the fastest punch
const FIST_FAIL := 11.95 + 2.0 * 1.84
const HITCH_DIP := 0.3             # a dip below 30% of the speed on BOTH sides, within HITCH_SPAN frames, = a hitch
const HITCH_SPAN := 3
const HITCH_FAST := 1.0            # m/s: both sides at least this fast (a slow drift is not a hitch)
const STRIKE_MIN := 3.0            # m/s: a tip slower than this all scene long = no strike in it
const SWING_LEAD := 0.5            # s before the tip's peak in which the hips and chest must peak
const HEAD_WIN := [0.3, 0.1]       # s before / after the tip's peak the head is watched
const AIR := 0.05                  # m: the lower foot this far above its lowest in the scene = off the ground
## not swings (the swing rules are measured on hitters): attack_timing's list + the get-ups
## scenes with no strike in them (the strike rules skip them): a name, or a name and a copy number ("walk_2": ROADMAP 44's
## templates, scenes/_wip/<template>_N.json). Their hands move fast (a jump's arm swing, a runner's drive) and are no attack
const NOT_SWINGS := ["getup_back", "getup_front", "walk", "run", "jump"]
const FOOT_DOWN := 0.05            # m: the ball of the foot this low = on the floor (Karunratanakul 2023)
const FOOT_SKATE := 0.025          # m: sliding more than this along the floor while down = skating
const BAL_OUT := 0.03             # m: the centre of mass this far past the support polygon...
const BAL_RUN := 6                 # ...for this many 60 fps frames (0.1 s) with both feet down: a fall, not momentum
const LOOP_DEG := 3.0              # deg: a joint's last pose this far off its first = a visible pop at the seam
const LOOP_GAP := 0.02             # m: a point (hand, foot, head...) this far from where it started
const LOOP_JUMP := 0.5             # m/s: a point's velocity changing this much across the seam (a hitch each lap)
const FOOT_STILL := 0.005          # m per 60 fps frame (0.3 m/s): slower than this = meant to stand (landings are faster)


## two rotations' difference in degrees, by how far they carry each axis (float32 acos near 1 floors at ~0.04 deg)
static func ang_deg(q: Quaternion, r: Quaternion) -> float:
	var w := 0.0
	for v in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		w = maxf(w, (q * v - r * v).length())
	return rad_to_deg(2.0 * asin(clampf(w * 0.5, 0.0, 1.0)))


static func dir_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(2.0 * asin(clampf((a.normalized() - b.normalized()).length() * 0.5, 0.0, 1.0)))


## the scene at 60 fps: per-frame speeds (m/s, deg/s) of what the rules read, plus the positions the head rule needs.
## base + [t0, t1] (10-14, the Fix button): frames outside the window are taken from base's raw frames instead of
## re-played (a pose edit on one card cannot move them; tests/fix_test.gd asserts window == full, bit for bit).
## contacts: also count each frame's parts-inside-each-other in the window ("bad", a Fix may not add any).
static func sample(S: Scene, B: Body, base := {}, t0 := INF, t1 := -INF, contacts := false) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was_stepped := S.stepped
	S.stepped = false   # the stepped preview is a view: the rules grade the scene as it really plays
	var reuse: bool = not base.is_empty() and base["_raw"].size() == n
	var raw := []
	var bad := 0
	var mk := func(_i: int, t: float) -> Dictionary:
		FrameMemo.pose(S, B, t)
		var r := {"tip": Overlays.tracked(B), "hips": B.P["pelvis"], "head": B.P["head"], "hand_l": B.E["hand_l"],
			"hand_r": B.E["hand_r"], "gp": B.G["pelvis"], "gt": B.G["spine_03"],
			"wd": (B.wep_point(B.wep_len) - B.wep_point(0.0)) if B.wep_on else (B.E["hand_r"] - B.P["hand_r"]),
			"fy": minf((B.P["foot_l"] as Vector3).y, (B.P["foot_r"] as Vector3).y), "wep": B.wep_on, "kind": B.wep_kind,
			"bl": B.P["ball_l"], "br": B.P["ball_r"], "bal": Balance.read(B), "lf": lift_form(B),
			"ga": [(B.P["lowerarm_l"] as Vector3) - (B.P["upperarm_l"] as Vector3), (B.P["lowerarm_r"] as Vector3) - (B.P["upperarm_r"] as Vector3),
			(B.P["calf_l"] as Vector3) - (B.P["thigh_l"] as Vector3), (B.P["calf_r"] as Vector3) - (B.P["thigh_r"] as Vector3), (B.P["head"] as Vector3).y]}
		if not S.props.is_empty():
			r["pc"] = prop_hits(S.props_at(t, B), B, S.holding(t, B))   # UU2: the set as it is now; holding hands are not through
			r["sg"] = seat_gap(S.props, B)
			r["fo"] = B.foot_state("_l")[2] or B.foot_state("_r")[2]
			r["cf"] = carry_form(S, t, B)
		return r
	if not reuse and not contacts and FrameMemo.on:
		raw = FrameMemo.frames("rb", S, B, n, FPS, mk)   # the realism score: only the frames a fix changed are played again
	else:
		for i in n:
			var t := minf(i / FPS, S.length())
			if reuse and (t < t0 or t > t1):
				raw.append(base["_raw"][i])
				continue
			raw.append(mk.call(i, t))
			if contacts and not B.contacts().is_empty():
				bad += 1
	S.stepped = was_stepped
	var out := {"t": [], "tip": [], "hips": [], "head": [], "hand_l": [], "hand_r": [], "w_pelvis": [], "w_trunk": [],
		"w_weapon": [], "head_pos": [], "foot_y": [], "ball_l": [], "ball_r": [], "armed": false, "kind": "",
		"spline": S.spline, "_raw": raw, "bad": bad, "balance": [], "both_down": [], "lift_form": [], "gait": []}
	for i in n:
		var now: Dictionary = raw[i]
		var prev: Dictionary = raw[maxi(i - 1, 0)]
		if now["wep"]:
			out["armed"] = true
			out["kind"] = now["kind"]
		out["t"].append(i / FPS)
		out["head_pos"].append(now["head"])
		out["foot_y"].append(now["fy"])
		out["ball_l"].append(now["bl"])
		out["ball_r"].append(now["br"])
		out["balance"].append(float(now["bal"]["margin"]))
		out["lift_form"].append(now["lf"])
		out["gait"].append(now["ga"])
		out["both_down"].append(now["bal"]["down"].size() == 2)
		if now.has("pc"):   # the set (TT1, TT4): only a scene with props has these keys
			if not out.has("prop_hits"):
				out["prop_hits"] = []
				out["seat_gap"] = []
				out["feet_on"] = []
			out["prop_hits"].append(now["pc"])
			out["seat_gap"].append(now["sg"])
			out["feet_on"].append(now["fo"])
			if not out.has("carry_form"):
				out["carry_form"] = []
			out["carry_form"].append(now["cf"])
		for k in ["tip", "hips", "head", "hand_l", "hand_r"]:
			out[k].append(((now[k] as Vector3) - prev[k]).length() * FPS if i > 0 else 0.0)
		out["w_pelvis"].append(ang_deg(prev["gp"], now["gp"]) * FPS if i > 0 else 0.0)
		out["w_trunk"].append(ang_deg(prev["gt"], now["gt"]) * FPS if i > 0 else 0.0)
		out["w_weapon"].append(dir_deg(prev["wd"], now["wd"]) * FPS if i > 0 else 0.0)
	for k in ["tip", "hips", "head", "hand_l", "hand_r", "w_pelvis", "w_trunk", "w_weapon"]:
		if out[k].size() > 1:
			out[k][0] = out[k][1]
	return out


## the strikes: the tip's speed peaks at least half the scene's fastest, 0.25 s apart (the bigger wins), each with the
## run of frames around it above half its own peak: [{"pk": frame, "a": first, "b": last}]
static func strikes(tip: Array) -> Array:
	var top := 0.0
	for v in tip:
		top = maxf(top, v)
	if top < STRIKE_MIN:
		return []
	var cands := []
	for i in range(1, tip.size() - 1):
		if tip[i] >= tip[i - 1] and tip[i] > tip[i + 1] and tip[i] >= 0.5 * top:
			cands.append(i)
	cands.sort_custom(func(x, y): return tip[x] > tip[y])
	var keep := []
	for c in cands:
		var near := false
		for k in keep:
			if absi(k - c) < int(0.25 * FPS):
				near = true
		if not near:
			keep.append(c)
	keep.sort()
	var out := []
	for pk in keep:
		var a: int = pk
		var b: int = pk
		while a > 0 and tip[a - 1] > 0.5 * tip[pk]:
			a -= 1
		while b < tip.size() - 1 and tip[b + 1] > 0.5 * tip[pk]:
			b += 1
		out.append({"pk": pk, "a": a, "b": b})
	return out


static func _argmax(s: Array, a: int, b: int) -> int:
	var best := a
	for i in range(a, b + 1):
		if s[i] > s[best]:
			best = i
	return best


## a finding; v = the measured number (m/s, m, frames) the Fix button works from
static func _f(sev: String, t: float, rule: String, msg: String, v := 0.0) -> Dictionary:
	return {"sev": sev, "t": t, "card": -1, "rule": rule, "msg": msg, "v": v}


## SEQUENCE + HIPS TURN: in the SWING_LEAD before the tip's peak, the hips peak first, then the chest, then the weapon
static func rule_sequence(sm: Dictionary, st: Dictionary) -> Array:
	var out := []
	var pk: int = st["pk"]
	var a := maxi(0, pk - int(SWING_LEAD * FPS))
	var b := mini(sm["w_weapon"].size() - 1, pk + 2)
	var ip := _argmax(sm["w_pelvis"], a, b)
	var it := _argmax(sm["w_trunk"], a, b)
	var iw := _argmax(sm["w_weapon"], a, b)
	var tol := 1   # one frame at 60 fps: a tie
	var t: float = sm["t"][pk]
	var wp: float = sm["w_pelvis"][ip]
	if wp < HIPS_MIN:
		out.append(_f("WARN", t, "HIPS TURN", "the hips barely turn into this swing: %.0f°/s at most (real hitters ~389°/s, bar %.0f°/s). The arms swing alone." % [wp, HIPS_MIN]))
	elif it + tol < ip or iw + tol < ip:
		out.append(_f("FAIL" if iw + tol < ip else "WARN", t, "SEQUENCE", "the hips turn LATE: their fastest moment is %.0f ms after the %s's. Real swings go hips -> chest -> weapon." % [(ip - mini(it, iw)) * 1000.0 / FPS, "weapon" if iw < it else "chest"]))
	elif iw + tol < it:
		out.append(_f("FAIL", t, "SEQUENCE", "the chest turns after the weapon: %.0f ms late. Real swings go hips -> chest -> weapon." % ((it - iw) * 1000.0 / FPS)))
	return out


## HEAD QUIET: from HEAD_WIN[0] before the tip's peak to HEAD_WIN[1] after, how far the head gets from where it began
static func rule_head(sm: Dictionary, st: Dictionary) -> Array:
	var pk: int = st["pk"]
	var a := maxi(0, pk - int(HEAD_WIN[0] * FPS))
	var b := mini(sm["head_pos"].size() - 1, pk + int(HEAD_WIN[1] * FPS))
	var ground: float = sm["foot_y"].min()
	for i in range(maxi(0, a - int(0.2 * FPS)), mini(sm["foot_y"].size(), b + 1 + int(0.2 * FPS))):   # a jump near the swing too
		if sm["foot_y"][i] > ground + AIR:
			return []   # off the ground: the hitters' numbers are for feet on it
	var far := 0.0
	var at := a
	for i in range(a, b + 1):
		var d: float = ((sm["head_pos"][i] as Vector3) - sm["head_pos"][a]).length()
		if d > far:
			far = d
			at = i
	if far <= HEAD_WARN:
		return []
	return [_f("FAIL" if far > HEAD_FAIL else "WARN", sm["t"][at], "HEAD QUIET", "the head travels %.0f cm during the swing (real hitters ~9 cm; bar %.0f cm). Keep the head still and let the hips and arms do the work." % [far * 100.0, HEAD_WARN * 100.0], far)]


## TIP SPEED + STRIKE FRAMES: attack_timing's tables for this weapon
static func rule_weapon(sm: Dictionary, st: Dictionary) -> Array:
	if not sm["armed"]:
		return []
	var out := []
	var kind: String = sm["kind"]
	var cap: float = AT.TIP_MAX.get(kind, 40.0)
	var budget: int = AT.RULES.get(kind, AT.RULES["metal_bat"])[1]
	var v: float = sm["tip"][st["pk"]]
	var t: float = sm["t"][st["pk"]]
	if v > cap:
		out.append(_f("FAIL", t, "TIP SPEED", "the %s's tip hits %.1f m/s; a real one tops out near %.0f m/s. Give this move more time (the card's 'move')." % [kind.replace("_", " "), v, cap], v))
	var frames30: float = (st["b"] - st["a"] + 1) * 30.0 / FPS
	if frames30 > budget + 0.5:
		out.append(_f("WARN", t, "STRIKE FRAMES", "the swing itself lasts %.0f frames at 30 fps (budget %d frames for a %s): it reads slow. Shorten the strike card's move." % [frames30, budget, kind.replace("_", " ")], frames30))
	return out


## FIST SPEED (unarmed only): either hand's end over the recorded fastest punch
static func rule_fist(sm: Dictionary) -> Array:
	if sm["armed"]:
		return []
	var out := []
	for k in ["hand_l", "hand_r"]:
		var i := _argmax(sm[k], 0, sm[k].size() - 1)
		var v: float = sm[k][i]
		if v > FIST_WARN:
			out.append(_f("FAIL" if v > FIST_FAIL else "WARN", sm["t"][i], "FIST SPEED", "the %s hand moves at %.1f m/s, faster than boxers' fastest punch (12 m/s on average; bar %.1f m/s). It will read as a pop." % ["left" if k == "hand_l" else "right", v, FIST_WARN if v <= FIST_FAIL else FIST_FAIL], v))
	return out


## FOOT SLIDE: a foot that is DOWN (ball under FOOT_DOWN) and SETTLED (moving under FOOT_STILL per frame along the
## floor) but creeps: over each run of such frames, its farthest point from where it settled; over FOOT_SKATE = skating.
## A landing or a take-off is fast near the floor and is not counted (10-14: the first version, which counted every
## frame under 5 cm, called combo3's landing a 10 cm slide; the foot then sits still to the millimetre for 1.1 s).
static func rule_feet(sm: Dictionary) -> Array:
	var out := []
	if not sm.has("ball_l"):
		return out
	for k in ["ball_l", "ball_r"]:
		var s: Array = sm[k]
		var i := 1
		while i < s.size():
			if not _settled(s, i):
				i += 1
				continue
			var a := i
			var far := 0.0
			var p0: Vector3 = s[a]
			while i < s.size() and _settled(s, i):
				var d: Vector3 = (s[i] as Vector3) - p0
				far = maxf(far, Vector2(d.x, d.z).length())
				i += 1
			if far > FOOT_SKATE:
				out.append(_f("WARN", sm["t"][a], "FOOT SLIDE", "the %s foot creeps %.1f cm along the floor while it should stand (%.2f-%.2f s); more than 2.5 cm reads as skating. Plant it on these cards (the Fix), or give it the same place in the cards around it." % ["left" if k == "ball_l" else "right", far * 100.0, sm["t"][a], sm["t"][i - 1]], far))
				out[-1]["foot"] = k.substr(4)   # "_l" / "_r": the Fix plants this foot over [t, t1] (round 10)
				out[-1]["t1"] = sm["t"][i - 1]
	return out


static func _settled(s: Array, i: int) -> bool:
	var p: Vector3 = s[i]
	var d: Vector3 = p - (s[i - 1] as Vector3)
	return p.y < FOOT_DOWN and Vector2(d.x, d.z).length() < FOOT_STILL


## HITCH: on the weapon tip, the hips and the head, a speed dip below HITCH_DIP of BOTH sides within HITCH_SPAN frames.
## A dip inside a card's HOLD is a pose held on purpose (ATTACK_RULES: hold the top of the wind-up), not a hitch.
## One moment = one finding, naming every part that stutters there.
static func rule_hitch(sm: Dictionary, holds: Array) -> Array:
	var names := {"tip": "the weapon tip" if sm["armed"] else "the right hand", "hips": "the hips", "head": "the head"}
	var hits := []   # [frame, part, left, dip, right]
	for k in names:
		var s: Array = sm[k]
		for i in range(HITCH_SPAN, s.size() - HITCH_SPAN):
			var l := 0.0
			var r := 0.0
			for d in range(1, HITCH_SPAN + 1):
				l = maxf(l, s[i - d])
				r = maxf(r, s[i + d])
			if minf(l, r) >= HITCH_FAST and s[i] < HITCH_DIP * minf(l, r) and s[i] <= s[i - 1] and s[i] <= s[i + 1]:
				var t: float = sm["t"][i]
				var held := false
				for h in holds:
					if t >= h[0] - 1.0 / FPS and t <= h[1] + 1.0 / FPS:
						held = true
				if not held:
					hits.append([i, names[k], l, s[i], r])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	var out := []
	var group := []
	for h in hits + [[1 << 30]]:
		if not group.is_empty() and h[0] - group[0][0] > HITCH_SPAN * 2:
			var w: Array = group[0]
			var parts := []
			for g in group:
				if not g[1] in parts:
					parts.append(g[1])
			var fix := "two cards here fight: move one, or delete one" if sm["spline"] else "the body stops dead at a card between two fast moves. Tick 'Smooth (spline)' (or press Polish) so it flows through"
			out.append(_f("WARN", sm["t"][w[0]], "HITCH", "%s: %.1f -> %.1f -> %.1f m/s within %d ms (%s). A real move has one smooth speed peak; %s." % [parts[0].left(1).to_upper() + parts[0].substr(1), w[2], w[3], w[4], int(2 * HITCH_SPAN * 1000 / FPS), ", ".join(parts.slice(1)) if parts.size() > 1 else "alone", fix]))
			group = []
		if h[0] < 1 << 30:
			group.append(h)
	return out


## which card a moment belongs to: the card being moved into or held
## LOOP SEAM (round 16, GATES W2): a loop scene's last frame against its first. The pose: the joint whose rotation (in
## the world, so the body's own turn counts) differs most, and the point that ends farthest from where it started. The
## speed: each point's velocity just before the end against just after the start (one 60 fps frame each side); a
## change over LOOP_JUMP is a jump every lap, even when the poses meet
## a part's plain name (main.gd's, loaded when asked: main uses this class, a preload would be a cycle)
static func _nice(j: String) -> String:
	return load("res://scripts/main.gd").nice(j)


static func rule_loop(S: Scene, B: Body) -> Array:
	if not S.loop or S.cards.size() < 2:
		return []
	var L := S.length()
	var h := 1.0 / FPS
	var keep := B.state()
	var at := {}
	for t in [0.0, h, L - h, L]:
		S.apply_true(B, t)
		at[t] = [B.G.duplicate(), B.P.duplicate()]
	B.set_state(keep)
	var out := []
	var wj := ""
	var wd := 0.0
	for j in at[0.0][0]:
		var d := ang_deg(at[0.0][0][j], at[L][0][j])
		if d > wd:
			wd = d
			wj = j
	var wp := ""
	var wg := 0.0
	var vj := ""
	var vjump := 0.0
	var v_end := Vector3.ZERO
	var v_start := Vector3.ZERO
	for j in at[0.0][1]:
		var g: float = ((at[0.0][1][j] as Vector3) - at[L][1][j]).length()
		if g > wg:
			wg = g
			wp = j
		var ve: Vector3 = ((at[L][1][j] as Vector3) - at[L - h][1][j]) / h
		var vs: Vector3 = ((at[h][1][j] as Vector3) - at[0.0][1][j]) / h
		if (ve - vs).length() > vjump:
			vjump = (ve - vs).length()
			vj = j
			v_end = ve
			v_start = vs
	if wd > LOOP_DEG or wg > LOOP_GAP:
		out.append(_f("WARN", L, "LOOP SEAM", "the loop's end does not meet its start: the %s is %.1f deg off and the %s ends %.1f cm from where it began (over %.0f deg or %.0f cm pops every lap). Make the last card a copy of the first ('Loop: close the seam')." % [
			_nice(wj) if wj != "" else "-", wd, _nice(wp) if wp != "" else "-", wg * 100.0, LOOP_DEG, LOOP_GAP * 100.0], maxf(wd, wg * 100.0)))
		out[-1]["joint"] = wj
	if vjump > LOOP_JUMP:
		out.append(_f("WARN", L, "LOOP SEAM", "across the loop's seam the %s's speed jumps %.2f m/s (%.2f m/s at the end, %.2f m/s at the start; over %.1f m/s is a hitch every lap). End and start the same way: both on a hold, or the same move through the first card." % [
			_nice(vj), vjump, v_end.length(), v_start.length(), LOOP_JUMP], vjump))
		out[-1]["joint"] = vj
	return out


## BALANCE (round 16, GATES W3): with both feet on the floor, the centre of mass's floor point more than BAL_OUT past
## the support polygon for BAL_RUN frames or more. One feet-down stretch = one finding, at its worst
static func rule_balance(sm: Dictionary) -> Array:
	var out := []
	if not sm.has("balance"):
		return out
	var s: Array = sm["balance"]
	var dn: Array = sm["both_down"]
	var i := 0
	while i < s.size():
		if not (dn[i] and s[i] < -BAL_OUT):
			i += 1
			continue
		var a := i
		var worst := 0.0
		var wi := i
		while i < s.size() and dn[i] and s[i] < -BAL_OUT:
			if -s[i] > worst:
				worst = -s[i]
				wi = i
			i += 1
		if i - a >= BAL_RUN:
			out.append(_f("WARN", sm["t"][wi], "BALANCE", "%.2f-%.2f s: with both feet down, his centre of mass is %.1f cm past the edge of his feet (over %.0f cm for %.1f s or more, he would fall). Move the hips back over the feet, or let him take a step." % [
				sm["t"][a], sm["t"][i - 1], worst * 100.0, BAL_OUT * 100.0, BAL_RUN / FPS], worst))
			out[-1]["t1"] = sm["t"][i - 1]
	return out


## the body and the weapon inside the props, this frame: [[part, prop index, depth m], ...] deeper than PROP_WARN (a
## sole: SOLE_SINK). Less is RESTING on a top (a foot on a box, the hips on a seat, a hand flat on a table)
static func prop_hits(props: Array, B: Body, held := {}) -> Array:
	var parts := []
	for part in B.cap0:
		if not (part.begins_with("thumb") or part.begins_with("index") or part.begins_with("middle") or part.begins_with("ring") or part.begins_with("pinky")):
			parts.append(part)
	if B.wep_on:
		parts += ["bat_handle", "bat_barrel"]
	if B.wep2_on:
		parts += ["wep2_handle", "wep2_blade"]
	var out := []
	for pi in props.size():
		var p: Dictionary = props[pi]
		var ball := _ball(p)
		for part in parts:
			if part in held.get(pi, []):
				continue
			var c := B.cap(part)
			var r: float = sole_rad(B, part)
			if Body.seg_seg(c[0], c[1], ball[0], ball[0]) > float(ball[1]) + r:
				continue   # nowhere near this prop
			var d := Props.depth(p, c[0], c[1], r)
			var bar := PROP_WARN if r == float(B.rad[part]) else SOLE_SINK   # a thinned part is a sole
			if d > bar:   # under the bar IS resting (Props.rests allows under REST_SINK = PROP_WARN)
				out.append([part, pi, d])
	return out


## a part's radius for the set: the foot and toe capsules are fitted to the foot's VOLUME and reach 6 cm under the
## floor at rest, so a part whose rest capsule dips under the floor is thinned until it does not (the sole line that
## grounding stands on). A foot kicked sideways into a box therefore reads "through" only past that line
static func sole_rad(B: Body, part: String) -> float:
	var r: float = B.rad[part]
	if B.cap0.has(part):
		r = minf(r, maxf(0.0, minf((B.cap0[part][0] as Vector3).y, (B.cap0[part][1] as Vector3).y)))
	return r


## a sphere round the prop's boxes: [centre, radius] (a quick "nowhere near")
static func _ball(p: Dictionary) -> Array:
	var pts := []
	for sw in Props.solids(p):
		var h: Vector3 = sw["half"]
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					pts.append((sw["xf"] as Transform3D) * Vector3(h.x * sx, h.y * sy, h.z * sz))
	var c := Vector3.ZERO
	for q in pts:
		c += q
	c /= maxf(1.0, pts.size())
	var rr := 0.0
	for q in pts:
		rr = maxf(rr, c.distance_to(q))
	return [c, rr]


## how far the hips' lowest surface is above a seat they are over (INF: over none, or below its top)
static func seat_gap(props: Array, B: Body) -> float:
	var c := B.cap("hips_wide")
	var r: float = B.rad["hips_wide"]
	var lo := minf((c[0] as Vector3).y, (c[1] as Vector3).y) - r
	var mid := ((c[0] as Vector3) + (c[1] as Vector3)) / 2.0
	var best := INF
	for p in props:
		for s in Props.supports(p):
			if Props._over(s, mid) and lo >= float(s["y"]) - Props.REST_SINK:
				best = minf(best, lo - float(s["y"]))
	return best


static func part_words(part: String) -> String:
	var side := ""
	var base := part
	if part.ends_with("_l") or part.ends_with("_r"):
		side = "left " if part.ends_with("_l") else "right "
		base = part.left(-2)
	return side + String(PART_WORDS.get(base, base.replace("_", " ")))


## THROUGH A PROP: one finding per run of frames per part and prop; FAIL from PROP_FAIL deep
static func rule_props(S: Scene, sm: Dictionary) -> Array:
	var out := []
	if not sm.has("prop_hits"):
		return out
	var hits: Array = sm["prop_hits"]
	var runs := {}   # "part|prop" -> [first frame, last frame, deepest, its frame]
	var done := []
	for i in hits.size():
		var now := {}
		for h in hits[i]:
			var k := "%s|%d" % [h[0], h[1]]
			now[k] = true
			if runs.has(k) and runs[k][1] == i - 1:
				runs[k][1] = i
				if h[2] > runs[k][2]:
					runs[k][2] = h[2]
					runs[k][3] = i
			else:
				if runs.has(k):
					done.append([k, runs[k]])
				runs[k] = [i, i, h[2], i]
	for k in runs:
		done.append([k, runs[k]])
	for e in done:
		var part: String = e[0].get_slice("|", 0)
		var pi := int(e[0].get_slice("|", 1))
		var rn: Array = e[1]
		var what := String(S.props[pi]["kind"]).replace("_", " ") if pi < S.props.size() else "prop"
		var t0: float = sm["t"][rn[0]]
		var t1: float = sm["t"][rn[1]]
		out.append(_f("FAIL" if rn[2] >= PROP_FAIL else "WARN", sm["t"][rn[3]], "THROUGH A PROP",
			"%.2f-%.2f s (frames %d-%d): the %s goes %.1f cm into the %s. Move it out, or move the %s: a body cannot pass through it." % [
			t0, t1, int(round(t0 * 30.0)), int(round(t1 * 30.0)), part_words(part), rn[2] * 100.0, what, what], rn[2]))
		out[-1]["t1"] = t1
	return out


## FLOATS: the hips 2-15 cm over a seat they are over, for FLOAT_RUN frames or more, while no foot is on the ground
static func rule_floats(sm: Dictionary) -> Array:
	var out := []
	if not sm.has("seat_gap"):
		return out
	var g: Array = sm["seat_gap"]
	var fo: Array = sm["feet_on"]
	var i := 0
	while i < g.size():
		var bad := func(k: int) -> bool: return not fo[k] and float(g[k]) >= FLOAT_MIN and float(g[k]) <= FLOAT_MAX
		if not bad.call(i):
			i += 1
			continue
		var a := i
		var top := 0.0
		while i < g.size() and bad.call(i):
			top = maxf(top, float(g[i]))
			i += 1
		if i - a >= FLOAT_RUN:
			out.append(_f("WARN", sm["t"][a], "FLOATS", "%.2f-%.2f s: the hips hover %.1f cm over the seat with no foot on the ground. Lower them onto it (or put the feet down)." % [
				sm["t"][a], sm["t"][i - 1], top * 100.0], top))
			out[-1]["t1"] = sm["t"][i - 1]
	return out


## the two-handed carry's form this frame ({} = nothing carried in both hands): "up" the larger upper arm angle from
## hanging straight down, "flex" both elbows' bend (0 = straight), "h" the hands' middle from the ankles' middle along
## the floor (NIOSH H)
static func carry_form(S: Scene, t: float, B: Body) -> Dictionary:
	var two := false
	for pi in S.holding(t, B):
		for c in S.carries():
			if int(c["prop"]) == int(pi) and (c["hands"] as Array).size() == 2:
				two = true
	if not two:
		return {}
	var up := 0.0
	var flex := []
	for sd in ["_l", "_r"]:
		var u: Vector3 = (B.P["lowerarm" + sd] as Vector3) - (B.P["upperarm" + sd] as Vector3)
		var f: Vector3 = (B.P["hand" + sd] as Vector3) - (B.P["lowerarm" + sd] as Vector3)
		up = maxf(up, rad_to_deg(u.angle_to(Vector3.DOWN)))
		flex.append(rad_to_deg(u.angle_to(f)))
	var hands := ((B.cap("hand_l")[0] as Vector3) + (B.cap("hand_l")[1] as Vector3) + (B.cap("hand_r")[0] as Vector3) + (B.cap("hand_r")[1] as Vector3)) / 4.0
	var ankles := ((B.P["foot_l"] as Vector3) + (B.P["foot_r"] as Vector3)) / 2.0
	return {"up": up, "flex": flex, "h": Vector2(hands.x - ankles.x, hands.z - ankles.z).length()}


## CARRY FORM: a two-handed carry held unlike a person (arms out, elbows straight or folded, the load far from the
## body) for FLOAT_RUN frames or more: one WARN per run, naming what is off and what real carriers do
static func rule_carry_form(sm: Dictionary) -> Array:
	var out := []
	if not sm.has("carry_form"):
		return out
	var cf: Array = sm["carry_form"]
	var whats := func(d: Dictionary) -> Array:
		var w := []
		if d.is_empty():
			return w
		if float(d["up"]) > CARRY_UP:
			w.append("the upper arms are %.0f° out from the sides (people carry with them down, under %.0f°)" % [d["up"], CARRY_UP])
		var fl: Array = d["flex"]
		if minf(fl[0], fl[1]) < CARRY_FLEX[0] or maxf(fl[0], fl[1]) > CARRY_FLEX[1]:
			w.append("the elbows bend %.0f° / %.0f° (people carry on bent elbows, %.0f-%.0f°)" % [fl[0], fl[1], CARRY_FLEX[0], CARRY_FLEX[1]])
		if float(d["h"]) > CARRY_H:
			w.append("the hands are %.0f cm in front of the ankles (people hold a load against the body: NIOSH 25 cm ideal, over %.0f cm is far)" % [float(d["h"]) * 100.0, CARRY_H * 100.0])
		return w
	var i := 0
	while i < cf.size():
		if whats.call(cf[i]).is_empty():
			i += 1
			continue
		var a := i
		var worst: Array = whats.call(cf[i])
		while i < cf.size() and not whats.call(cf[i]).is_empty():
			if whats.call(cf[i]).size() > worst.size():
				worst = whats.call(cf[i])
			i += 1
		if i - a >= FLOAT_RUN:
			out.append(_f("WARN", sm["t"][a], "CARRY FORM", "%.2f-%.2f s: carried in both hands, but %s. Hold it against the belly: upper arms down, elbows bent about 90 deg." % [
				sm["t"][a], sm["t"][i - 1], "; ".join(worst)], float(worst.size())))
			out[-1]["t1"] = sm["t"][i - 1]
	return out


## what the lifting rule reads, one frame: the hands' lowest point and the knees' height (m), the trunk's flexion from
## vertical (hips to neck, deg) and the deeper knee's bend (0 = straight)
static func lift_form(B: Body) -> Dictionary:
	var hand := minf(minf((B.cap("hand_l")[0] as Vector3).y, (B.cap("hand_l")[1] as Vector3).y),
		minf((B.cap("hand_r")[0] as Vector3).y, (B.cap("hand_r")[1] as Vector3).y))
	var knee := 0.0
	var bend := 0.0
	for sd in ["_l", "_r"]:
		var th: Vector3 = (B.P["calf" + sd] as Vector3) - (B.P["thigh" + sd] as Vector3)
		var sh: Vector3 = (B.P["foot" + sd] as Vector3) - (B.P["calf" + sd] as Vector3)
		bend = maxf(bend, rad_to_deg(th.angle_to(sh)))
		knee += (B.P["calf" + sd] as Vector3).y / 2.0
	var trunk := rad_to_deg(((B.P["neck_01"] as Vector3) - (B.P["pelvis"] as Vector3)).angle_to(Vector3.UP))
	return {"hand": hand, "knee": knee, "trunk": trunk, "bend": bend}


## LIFT FORM: the hands below the knees while the trunk is flexed past LIFT_TRUNK and the knees bend under LIFT_KNEE
## (a stoop to the floor) for FLOAT_RUN frames or more: one WARN per run, naming both angles and what people do
static func rule_lift_form(sm: Dictionary) -> Array:
	var out := []
	var lf: Array = sm.get("lift_form", [])
	var bad := func(d: Dictionary) -> bool:
		return float(d["hand"]) < float(d["knee"]) and float(d["trunk"]) > LIFT_TRUNK and float(d["bend"]) < LIFT_KNEE
	var i := 0
	while i < lf.size():
		if not bad.call(lf[i]):
			i += 1
			continue
		var a := i
		var worst: Dictionary = lf[i]
		while i < lf.size() and bad.call(lf[i]):
			if float(lf[i]["trunk"]) - float(lf[i]["bend"]) > float(worst["trunk"]) - float(worst["bend"]):
				worst = lf[i]
			i += 1
		if i - a >= FLOAT_RUN:
			out.append(_f("WARN", sm["t"][a], "LIFT FORM", "%.2f-%.2f s: hands below the knees with the back bent %.0f° and the knees only %.0f°: lift with the legs (people squatting to the floor bend the knees 86-115°; a stoop is knees under %.0f° with the back past %.0f°)." % [
				sm["t"][a], sm["t"][i - 1], worst["trunk"], worst["bend"], LIFT_KNEE, LIFT_TRUNK], float(worst["trunk"])))
			out[-1]["t1"] = sm["t"][i - 1]
	return out


## the swing angle of a limb vector about the walking direction (deg, forward positive, 0 = hanging down)
static func _swing(v: Vector3, fwd: Vector3) -> float:
	return rad_to_deg(atan2(v.dot(fwd), -v.y))


static func _corr(a: Array, b: Array) -> float:
	var n := a.size()
	if n < 3:
		return 0.0
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += float(a[i])
		mb += float(b[i])
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (float(a[i]) - ma) * (float(b[i]) - mb)
		saa += (float(a[i]) - ma) * (float(a[i]) - ma)
		sbb += (float(b[i]) - mb) * (float(b[i]) - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-12))


## GAIT, measured: {"walk": false, "why"} or {"walk": true, "t0", "t1", "step" (x body height), "step_m", "cad" (steps/min),
## "arm" (deg peak to peak, mean of both), "phase" (r, arm vs same-side thigh; people < 0), "steps", "height"}.
## Plants are runs of a ball under FOOT_DOWN that moves under GAIT_STILL per frame for GAIT_PLANT frames; steps are
## the alternating plants' distances along the walking direction (first plant to last)
static func gait(sm: Dictionary) -> Dictionary:
	if not sm.has("gait") or not sm.has("ball_l") or (sm["gait"] as Array).is_empty():
		return {"walk": false, "why": "no gait series"}
	var plants := []   # [frame, foot 0/1, position]
	for f in 2:
		var s: Array = sm["ball_l" if f == 0 else "ball_r"]
		var i := 1
		while i < s.size():
			if not _planted(s, i):
				i += 1
				continue
			var a := i
			while i < s.size() and _planted(s, i):
				i += 1
			if i - a >= GAIT_PLANT:
				plants.append([a, f, s[(a + i - 1) / 2]])   # the landing frame, and where the foot stood (the run's middle)
	plants.sort_custom(func(x, y): return x[0] < y[0])
	# a plant already down at the first frame has no known landing: it only serves as the reference of the first step
	var real := []
	var first := []
	for p in plants:
		if int(p[0]) <= 1:
			first.append(p)
		else:
			real.append(p)
	var seq := []
	for p in real:
		if seq.is_empty() or seq[-1][1] != p[1]:
			seq.append(p)
	for p in first:
		if not seq.is_empty() and p[1] != seq[0][1]:
			seq.push_front(p)
			break
	if seq.size() < 4:
		return {"walk": false, "why": "%d alternating plants (a walk needs 4 plants)" % seq.size()}
	# the walking direction from plants of the SAME foot (two apart), so the width between the feet cancels
	var d: Vector3 = ((seq[-1][2] as Vector3) - (seq[1][2] as Vector3)) + ((seq[-2][2] as Vector3) - (seq[0][2] as Vector3))
	d.y = 0.0
	if d.length() < 1.0:
		return {"walk": false, "why": "travels %s (a walk needs 50 cm)" % Units.len(d.length() / 2.0)}
	var fwd := d.normalized()
	var i0: int = seq[0][0]
	var i1: int = seq[-1][0]
	while seq.size() > 4 and absf(((seq[-1][2] as Vector3) - (seq[-2][2] as Vector3)).dot(fwd)) < GAIT_MOVED:
		seq.pop_back()   # the closing step that brings the feet together is not a stride
	i1 = seq[-1][0]
	var run := 0
	for i in range(i0, i1 + 1):
		var up: bool = (sm["ball_l"][i] as Vector3).y >= FOOT_DOWN and (sm["ball_r"][i] as Vector3).y >= FOOT_DOWN
		run = run + 1 if up else 0
		if run >= GAIT_FLIGHT:
			return {"walk": false, "why": "both feet off the floor for %d frames: a run" % run}
	var tot := 0.0
	for k in range(1, seq.size()):
		tot += absf(((seq[k][2] as Vector3) - (seq[k - 1][2] as Vector3)).dot(fwd))
	var step_m := tot / (seq.size() - 1)
	var dur := float(sm["t"][i1]) - float(sm["t"][seq[1][0]])   # the landings, first to last
	var top := 0.0
	for g in sm["gait"]:
		top = maxf(top, float(g[4]))
	var height := top + GAIT_CROWN
	var al := []
	var ar := []
	var tl := []
	var tr := []
	for i in range(i0, i1 + 1):
		var g: Array = sm["gait"][i]
		al.append(_swing(g[0], fwd))
		ar.append(_swing(g[1], fwd))
		tl.append(_swing(g[2], fwd))
		tr.append(_swing(g[3], fwd))
	var span := func(a: Array) -> float: return float(a.max()) - float(a.min())
	return {"walk": true, "t0": sm["t"][i0], "t1": sm["t"][i1], "step_m": step_m, "step": step_m / height,
		"height": height, "cad": (seq.size() - 2) / dur * 60.0, "steps": seq.size() - 1, "seq": seq,
		"arm": (span.call(al) + span.call(ar)) / 2.0, "phase": (_corr(al, tl) + _corr(ar, tr)) / 2.0}


## a ball on the floor and not moving along it
static func _planted(s: Array, i: int) -> bool:
	var p: Vector3 = s[i]
	var q: Vector3 = s[i - 1]
	return p.y < FOOT_DOWN and Vector2(p.x - q.x, p.z - q.z).length() < GAIT_STILL


## a flight phase: the scene has "air" cards (Scene.flights: both feet off the floor, the body on a parabola). Running has one,
## walking never does (Novacheck 1998, Gait Posture 7:77), so the walking bars (step, cadence, arm swing) do not judge a run
static func has_flight(S: Scene) -> bool:
	return not S.flights().is_empty()


## GAIT: a walk against real walkers; one WARN naming each measure outside the real range, with both numbers.
## Arms are judged only with nothing in the hands (a weapon holds them still)
static func rule_gait(sm: Dictionary, S: Scene = null) -> Array:
	var g := gait(sm)
	if not g["walk"] or (S != null and has_flight(S)):
		return []   # a run: the walking bars do not apply
	var w := []
	var st: float = g["step"]
	if st < GAIT_STEP[0] or st > GAIT_STEP[1]:
		w.append("steps %.0f%% of the body height (%s a step; people walk 41.5%% +- 3.8%%, bar %.0f-%.0f%%)" % [st * 100.0, Units.len(float(g["step_m"])), GAIT_STEP[0] * 100.0, GAIT_STEP[1] * 100.0])
	var cad: float = g["cad"]
	if cad < GAIT_CAD[0] or cad > GAIT_CAD[1]:
		w.append("cadence %.0f steps/min (people 105-108 steps/min, bar %.0f-%.0f steps/min)" % [cad, GAIT_CAD[0], GAIT_CAD[1]])
	if not sm.get("armed", false):
		var arm: float = g["arm"]
		if arm < GAIT_ARM[0] or arm > GAIT_ARM[1]:
			w.append("arm swing %.0f° (people about 25-33°, bar %.0f-%.0f°)" % [arm, GAIT_ARM[0], GAIT_ARM[1]])
		elif float(g["phase"]) > GAIT_PHASE:
			w.append("each arm swings WITH its own leg (r %.2f; people swing it against the leg: a negative r)" % g["phase"])
	if w.is_empty():
		return []
	var out := [_f("WARN", g["t0"], "GAIT", "%.2f-%.2f s walk: %s." % [g["t0"], g["t1"], "; ".join(w)], float(w.size()))]
	out[-1]["t1"] = g["t1"]
	return out


## the deeper knee's bend at time t (0 = straight): the angle between the thigh and the shin
static func knee_bend(S: Scene, B: Body, t: float) -> float:
	S.apply_true(B, t)
	var k := 0.0
	for sd in ["_l", "_r"]:
		var th: Vector3 = (B.P["calf" + sd] as Vector3) - (B.P["thigh" + sd] as Vector3)
		var sh: Vector3 = (B.P["foot" + sd] as Vector3) - (B.P["calf" + sd] as Vector3)
		k = maxf(k, rad_to_deg(th.angle_to(sh)))
	return k


## the most knee bend over [a, b] at 60 frames a second
static func knee_most(S: Scene, B: Body, a: float, b: float) -> float:
	var k := 0.0
	var n := maxi(1, int(ceil((b - a) * 60.0)))
	for i in n + 1:
		k = maxf(k, knee_bend(S, B, lerpf(a, b, float(i) / n)))
	return k


## JUMP: each flight (Scene.flights) against real jumps: too high for its hang time, no dip before, stiff landing.
## {"T", "h", "dip", "land"} per flight, for the test and the panel
static func jumps(S: Scene, B: Body) -> Array:
	var out := []
	var end: float = S.times()[-1][2]
	for f in S.flights():
		var t0: float = f["t0"]
		var t1: float = f["t1"]
		var T := t1 - t0
		out.append({"t0": t0, "t1": t1, "T": T, "h": Scene.G * T * T / 8.0,
			"dip": knee_most(S, B, maxf(0.0, t0 - 0.5), t0), "land": knee_most(S, B, t1, minf(end, t1 + 0.25))})
	return out


## the least knee bend a landing from a fall of h metres should show: JUMP_LAND up to 0.40 m, then the line to 77 at 0.59 m
static func land_bar(h: float) -> float:
	var k := (JUMP_LAND1 - JUMP_LAND) / (JUMP_FALL1 - JUMP_FALL0)
	return clampf(JUMP_LAND + k * (h - JUMP_FALL0), JUMP_LAND, JUMP_LAND_MAX)


static func rule_jump(S: Scene, B: Body) -> Array:
	var out := []
	for j in jumps(S, B):
		var w := []
		if float(j["h"]) > JUMP_HIGH:
			w.append("%.2f s in the air means a %s jump (people: 40 cm = 0.57 s; over %s is a rare athlete)" % [j["T"], Units.len(float(j["h"])), Units.len(JUMP_HIGH)])
		if float(j["dip"]) < JUMP_DIP:
			w.append("no dip before take-off: the knees bend only %.0f° (people dip to ~90°)" % j["dip"])
		var bar := land_bar(float(j["h"]))
		if float(j["land"]) < bar:
			w.append("a stiff landing from %s: the knees bend only %.0f° after touchdown (a fall this high needs ~%.0f°; people land soft on ~117°, stiff is ~77° from 59 cm)" % [Units.len(float(j["h"])), j["land"], bar])
		if not w.is_empty():
			out.append(_f("WARN", j["t0"], "JUMP", "%.2f-%.2f s: %s." % [j["t0"], j["t1"], "; ".join(w)], float(w.size())))
			out[-1]["t1"] = j["t1"]
	return out


static func card_at(S: Scene, t: float) -> int:
	var ts := S.times()
	for i in ts.size():
		if t <= float(ts[i][2]) + 1e-4:
			return i
	return ts.size() - 1


## every rule over a scene; sorted by time
## sm: a sample already taken of this scene (the Fix button re-samples only a window)
static func check(S: Scene, B: Body, sm := {}) -> Array:
	if S.cards.size() < 2:
		return []
	var tk := Time.get_ticks_usec()
	if sm.is_empty():
		sm = sample(S, B)
		FrameMemo.tick("rb sample total", tk)
	tk = Time.get_ticks_usec()
	var out := []
	var base_name := S.name
	var cut := base_name.rfind("_")
	if cut > 0 and base_name.substr(cut + 1).is_valid_int():
		base_name = base_name.substr(0, cut)   # "jump_2" is the jump template's second copy
	var attack := not S.name in AT.NOT_ATTACKS and not S.name in NOT_SWINGS and not base_name in NOT_SWINGS
	if attack:
		for st in strikes(sm["tip"]):
			out += rule_sequence(sm, st)
			out += rule_head(sm, st)
			out += rule_weapon(sm, st)
	FrameMemo.tick("rules strike", tk)
	tk = Time.get_ticks_usec()
	out += rule_fist(sm)
	out += rule_feet(sm)
	var holds := []
	for ts in S.times():
		if float(ts[2]) - float(ts[1]) > 1e-4:
			holds.append([float(ts[1]), float(ts[2])])
	out += rule_hitch(sm, holds)
	FrameMemo.tick("rules fist/feet/hitch", tk)
	tk = Time.get_ticks_usec()
	out += rule_loop(S, B)
	FrameMemo.tick("rules loop", tk)
	tk = Time.get_ticks_usec()
	out += rule_balance(sm)
	out += rule_props(S, sm)
	out += rule_floats(sm)
	out += rule_carry_form(sm)
	out += rule_lift_form(sm)
	out += rule_gait(sm, S)
	out += rule_jump(S, B)
	FrameMemo.tick("rules rest", tk)
	tk = Time.get_ticks_usec()
	if HumanLimits.on:
		out += HumanLimits.findings(S, B)   # ROADMAP 10: only when asked ("Check: could a human do this?"): the bars are
		# not yet checked against the papers (a real bat swing read trunk 1087 deg/s vs a 601 bar; elite hitters reach ~900+)
	FrameMemo.tick("human limits total", tk)
	tk = Time.get_ticks_usec()
	if HumanLimits.on:   # "Is this clip physically possible?": the verdict (first) and its reasons, with their frames
		var fz := Feasible.check(S, B)
		out += Feasible.verdict_finding(S, fz) + fz["findings"].filter(func(f): return f["rule"] != "COUPLED LIMIT")   # N028: listed once, by HumanLimits
	FrameMemo.tick("feasible total", tk)
	if attack:
		out += WeightXfer.findings(S, B, sm)   # N029: each strike starts with the weight on the foot it needs (scripts/weight_xfer.gd)
	out += TrunkLean.findings(S, B)   # Nick 10-23: the trunk leaning past what people do in that move (scripts/trunk_lean.gd)
	out += BodyAssert.findings(S, B)   # N002: the scene's saved assertions, re-checked on every Check
	for f in out:
		f["card"] = card_at(S, f["t"])
	out.sort_custom(func(x, y): return x["t"] < y["t"])
	return out
