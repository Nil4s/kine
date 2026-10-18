## gait_band.gd - REAL WALKERS' BAND (round 43, GATES YY7, docs/ANIM_RESEARCH.md idea 3).
## The hip / knee / ankle angle of 42 healthy adults over one gait cycle (refs/gait_band.json, made by
## tools/make_gait_band.py from Fukuchi, Fukuchi & Duarte 2018, PeerJ 6:e4640, CC BY 4.0: overground, comfortable speed),
## mean and SD at every 1 % of the cycle. This file measures the SAME three angles on the body while a scene plays, over
## one cycle of that leg (landing to its next landing, from Rulebook.gait), so the curve editor can draw the people's
## band behind the body's own line, and list the joints that leave it.
## Angles (deg, 0 = standing straight, as the people's are): hip + = thigh forward of the pelvis; knee + = bent;
## ankle + = toes up (dorsiflexion). Each is the turn of the segment inside its parent's frame, from rest, in the side
## view (the body's x is its left-right axis).
## A landing here is the BALL coming down (Rulebook.gait's plant), the people's 0 % is the HEEL strike: the body's
## cycle starts at foot flat, a few % later (people's foot flat is in the loading response, 0-10 %); not corrected.
class_name GaitBand
extends RefCounted

const FILE := "res://refs/gait_band.json"
const OUT_SD := 2.0       # a point is outside the people when it is more than 2 SD from their mean (~95 % of people inside)
const OUT_SHARE := 0.10   # a joint is LISTED when more than 10 % of its cycle is outside (MINE)
const SEG := {"hip": ["pelvis", "thigh", "calf"], "knee": ["thigh", "calf", "foot"], "ankle": ["calf", "foot", "ball"]}

static var _table := {}
static var _rest := {}
static var _scratch: Body = null


static func table() -> Dictionary:
	if _table.is_empty():
		_table = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	return _table


## which band a body part shows: thigh -> hip, calf -> knee, foot / ball -> ankle; "" for the rest
static func joint_of(part: String) -> String:
	for j in SEG:
		if part == SEG[j][1] + "_r" or part == SEG[j][1] + "_l":
			return j
	if part == "ball_r" or part == "ball_l":
		return "ankle"
	return ""


## the segment's direction inside its parent's frame (G is the turn from rest, so this is the rest-world direction)
static func _dir(B: Body, j: String, sd: String) -> Vector3:
	var s: Array = SEG[j]
	var parent: String = s[0] if s[0] == "pelvis" else s[0] + sd   # the pelvis has no side
	return (B.G[parent] as Quaternion).inverse() * ((B.P[s[2] + sd] as Vector3) - (B.P[s[1] + sd] as Vector3))


## the side-view angle of a direction: limbs that hang down (hip, knee) from straight down toward +z; the foot from +z
static func _side(j: String, d: Vector3) -> float:
	return rad_to_deg(atan2(d.y, d.z)) if j == "ankle" else rad_to_deg(atan2(d.z, -d.y))


## hip / knee / ankle angle of side sd ("_r" / "_l") as the people's are measured: Vector3(hip, knee, ankle)
static func flex(B: Body, sd: String) -> Vector3:
	if _rest.is_empty():
		var R := Body.new()
		R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		R.fk()
		for s in ["_r", "_l"]:
			for j in SEG:
				_rest[j + s] = _side(j, _dir(R, j, s))
	var out := Vector3.ZERO
	var i := 0
	for j in SEG:
		var a := _side(j, _dir(B, j, sd)) - float(_rest[j + sd])
		a = wrapf(a, -180.0, 180.0)
		out[i] = -a if j == "knee" else a   # the shank swings BACK when the knee bends
		i += 1
	return out


## one cycle of side sd in scene S: {"ok": true, "t0", "t1"} (two landings of that foot in a row) or {"ok": false, "why"}
static func cycle(S: Scene, B: Body, sd: String) -> Dictionary:
	var g := Rulebook.gait(Rulebook.sample(S, B))
	if not g["walk"]:
		return {"ok": false, "why": "not a walk (%s)" % g["why"]}
	var f := 1 if sd == "_r" else 0
	var lands := []
	for p in g["seq"]:
		if int(p[1]) == f and int(p[0]) > 1:
			lands.append(int(p[0]))
	if lands.size() < 2:
		return {"ok": false, "why": "the %s foot lands %d time%s (a cycle needs 2)" % ["right" if f == 1 else "left", lands.size(), "" if lands.size() == 1 else "s"]}
	return {"ok": true, "t0": initial_contact(S, B, sd, lands[0] / Rulebook.FPS), "t1": initial_contact(S, B, sd, lands[1] / Rulebook.FPS)}


## INITIAL CONTACT (round 44, ZZ1): people's 0 % is the HEEL touching down; Rulebook.gait times a landing by the BALL
## (foot flat). From that landing, back in 1/120 s steps while the heel (the point under the ankle, Body.sole_low) is
## within HEEL_DOWN of the floor, at most HEEL_BACK s: a flat landing moves 0-1 step, a heel strike back to the heel.
const HEEL_DOWN := 0.01
const HEEL_BACK := 0.3


static func initial_contact(S: Scene, B: Body, sd: String, t: float) -> float:
	var f := "foot" + sd
	var up: float = (B.p0[f] as Vector3).y
	var t0 := t
	while t - t0 < HEEL_BACK and t0 > 0.0:
		S.apply(B, t0 - 1.0 / 120.0)
		if (B.P[f] as Vector3).y - up > HEEL_DOWN:
			break
		t0 -= 1.0 / 120.0
	return t0


## the band for one body part of scene S: {"ok", "joint", "side", "t0", "t1", "mean", "sd", "you" (101 each),
## "out" (share of the cycle outside OUT_SD), "listed"} or {"ok": false, "why"}. Plays the scene on a scratch body.
static func for_part(S: Scene, part: String) -> Dictionary:
	var j := joint_of(part)
	if j == "":
		return {"ok": false, "why": "the people's band is for the hip, knee and ankle: pick a thigh, calf or foot"}
	var sd := part.right(2)
	if _scratch == null:
		_scratch = Body.new()
		_scratch.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var c := cycle(S, _scratch, sd)
	if not c["ok"]:
		return c
	var k := ["hip", "knee", "ankle"].find(j)
	var you := []
	for i in 101:
		S.apply(_scratch, lerpf(c["t0"], c["t1"], i / 100.0))
		you.append(flex(_scratch, sd)[k])
	var m: Array = table()["joints"][j]["mean"]
	var s: Array = table()["joints"][j]["sd"]
	return judge({"ok": true, "joint": j, "side": sd, "t0": c["t0"], "t1": c["t1"], "mean": m, "sd": s, "you": you})


## fills "out" (share of the 101 points more than OUT_SD from the mean) and "listed" (out > OUT_SHARE)
static func judge(b: Dictionary) -> Dictionary:
	var n := 0
	for i in 101:
		if absf(float(b["you"][i]) - float(b["mean"][i])) > OUT_SD * float(b["sd"][i]):
			n += 1
	b["out"] = n / 101.0
	b["listed"] = b["out"] > OUT_SHARE
	return b


## every leg joint of a walk against the people: [{"part", "joint", "out"}] for the LISTED ones, plus "why" when no walk
static func report(S: Scene) -> Dictionary:
	var listed := []
	var all := []
	for part in ["thigh_r", "calf_r", "foot_r", "thigh_l", "calf_l", "foot_l"]:
		var b := for_part(S, part)
		if not b["ok"]:
			return {"ok": false, "why": b["why"]}
		all.append({"part": part, "joint": b["joint"], "out": b["out"]})
		if b["listed"]:
			listed.append(all[-1])
	return {"ok": true, "listed": listed, "all": all}
