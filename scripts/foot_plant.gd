## foot_plant.gd - FOOT PLANTING OVER A TIME RANGE (docs/ROADMAP.md item 8; docs/COMPLAINTS.md: foot sliding is the
## animators' #2 complaint). A PLANT is {"foot": "foot_l" / "foot_r", "t0": s, "t1": s} in Scene.plants (scene file key
## "plants", written only when there is one). Over [t0, t1] the foot's SOLE stays where it was at t0: the ankle's world
## point, the foot's world turn and the ball's (toe joint's) world turn are those of the played pose at t0, held every
## frame. The leg is re-solved with LimbIK.solve (the closed form, the pole taken from the pose at t0, so the knee keeps
## its side); the pelvis is never touched. The pose at t0 is the scene as it plays there with the plants OFF (IK pins
## and cards included), so plants do not read each other.
##
## EDGES: the weight ramps 0 -> 1 (smoothstep) over BLEND frames BEFORE t0 and 1 -> 0 over BLEND frames AFTER t1, at the
## scene's fps. Between the leg's free motion and its planted one the joint angles are mixed by that weight (the same
## mix LimbIK.play uses for IK weight), so nothing pops at a range edge.
##
## ORDER in Scene.apply (write it here and in Scene.apply): the cards, layers, breathing, drivers, the IK pass, THEN the
## plants (after the IK pass: a planted foot holds the place it had at t0, over a pin on the same foot), THEN the
## constraints (which still have the last word on what they drive). The plant reference is read first, from a second
## apply at t0 with the plants off, so the pose at t0 is exactly what plays there.
##
## A LEG THAT CANNOT REACH: the closed form stretches the leg toward the pin and the miss stays on the frame. play()
## reports it per plant (the miss, m); scan() lists the frames over the range whose miss is above MISS_BAR. Never hidden.
class_name FootPlant
extends RefCounted

const BLEND := 3          # frames, at the scene's fps, over which a plant eases on before t0 and off after t1
const MISS_BAR := 0.001   # m: a frame whose ankle is more than this from its pin is reported by scan()
const FEET := ["foot_l", "foot_r"]


## the plant list as read from a file: valid entries only (a known foot, t1 > t0), sorted by t0
static func from_file(d: Variant) -> Array:
	var out := []
	if not d is Array:
		return out
	for p in d:
		if not (p is Dictionary and String(p.get("foot", "")) in FEET and p.has("t0") and p.has("t1")):
			continue
		var t0 := float(p["t0"])
		var t1 := float(p["t1"])
		if t1 > t0:
			out.append({"foot": String(p["foot"]), "t0": t0, "t1": t1})
	out.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
	return out


## the file form: times to 0.1 ms, in the order kept
static func to_file(plants: Array) -> Array:
	return plants.map(func(p): return {"foot": String(p["foot"]), "t0": snappedf(float(p["t0"]), 0.0001), "t1": snappedf(float(p["t1"]), 0.0001)})


## MIRROR (Scene.MIRROR_SCENE "plants"), on the file form: each plant to its twin foot, the times as they were
static func mirror_file(plants: Array) -> Array:
	return plants.map(func(p): return {"foot": "foot_r" if String(p["foot"]) == "foot_l" else "foot_l", "t0": p["t0"], "t1": p["t1"]})


## ADD a plant: a plant of the same foot that overlaps its range is taken off first (one plant per foot at a time)
static func add(plants: Array, p: Dictionary) -> Array:
	var out := []
	for q in plants:
		if String(q["foot"]) == String(p["foot"]) and float(q["t0"]) < float(p["t1"]) and float(q["t1"]) > float(p["t0"]):
			continue
		out.append(q)
	out.append(p)
	out.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
	return out


## the plants of a foot covering t (its range, the blend not counted): the list with them taken off
static func remove_at(plants: Array, foot: String, t: float) -> Array:
	var out := []
	for q in plants:
		if String(q["foot"]) == foot and t >= float(q["t0"]) - 1e-6 and t <= float(q["t1"]) + 1e-6:
			continue
		out.append(q)
	return out


## the plant's weight at t, 0..1: 1 over [t0, t1], smoothstep over BLEND frames either side, 0 further out
static func weight(p: Dictionary, t: float, fps: int) -> float:
	var b := float(BLEND) / float(maxi(fps, 1))
	var t0 := float(p["t0"])
	var t1 := float(p["t1"])
	if t < t0 - b or t > t1 + b:
		return 0.0
	var u := 1.0
	if t < t0:
		u = clampf((t - (t0 - b)) / b, 0.0, 1.0)
	elif t > t1:
		u = clampf(((t1 + b) - t) / b, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## THE REFERENCE of each plant live at t (weight > 0): the sole as it plays at the plant's t0, read by Scene.apply with the
## plants off. Returns {index: {"P": ankle, "G": foot turn, "Gb": ball turn, "pole": the knee's pole}}. B is left posed
## at the last reference; the caller poses it at t afterwards (Scene.apply does)
static func refs(S: Scene, B: Body, t: float) -> Dictionary:
	var out := {}
	for i in S.plants.size():
		var p: Dictionary = S.plants[i]
		if weight(p, t, S.fps) <= 0.0:
			continue
		var foot := String(p["foot"])
		var ball := "ball" + foot.right(2)
		S._plants_off = true
		S.apply(B, float(p["t0"]))
		S._plants_off = false
		out[i] = {"P": B.P[foot], "G": B.G[foot], "Gb": B.G[ball], "pole": LimbIK.pole_from_pose(B, foot)}
	return out


## THE PLANT PASS (Scene.apply, after the IK pass): each live plant's leg solved onto its reference, mixed with the
## played angles by its weight. Returns {index: {"foot", "w", "miss" (m: the ankle to its pin), "ball_turn" (deg: the
## ball's turn off its pin), "clamped": joints a limit changed, "inline"}}. B.offset is never written
static func play(B: Body, plants: Array, refs_: Dictionary, t: float, fps: int) -> Dictionary:
	var out := {}
	for i in refs_:
		var p: Dictionary = plants[i]
		var w := weight(p, t, fps)
		var foot := String(p["foot"])
		var ball := "ball" + foot.right(2)
		var ref: Dictionary = refs_[i]
		var joints := LimbIK.chain(B, foot)
		joints.append(ball)
		var was := {}
		for j in joints:
			was[j] = B.ang[j]
		var r := LimbIK.solve(B, foot, ref["P"], ref["pole"], ref["G"])
		# the ball (toe joint) keeps its world turn: the sole stays flat where it was at t0
		var gf: Quaternion = B.G[foot]
		var vb := B.decompose(ball, (gf.inverse() * (ref["Gb"] as Quaternion)).normalized())
		if (B.clamp_ang(ball, vb) - vb).length() > 1e-4:
			r["clamped"].append(ball)
		B.ang[ball] = B.clamp_ang(ball, vb)
		B.fk()
		if w < 1.0:
			for j in joints:
				B.ang[j] = (was[j] as Vector3).lerp(B.ang[j], w)
			B.fk()
		var turn := rad_to_deg(((B.G[ball] as Quaternion).inverse() * (ref["Gb"] as Quaternion)).normalized().get_angle())
		out[i] = {"foot": foot, "w": w, "miss": ((B.P[foot] as Vector3) - (ref["P"] as Vector3)).length(),
			"ball_turn": turn, "clamped": r["clamped"], "inline": r["inline"]}
	return out


## the sole's floor outline under a planted foot posed on B (heel, ball, toe tip, floor y = 0): a small footprint. [] when
## the foot is not planted at t (weight 0). Used by main.gd to draw it
static func footprint(B: Body, plants: Array, t: float, fps: int) -> Array:
	var out := []
	for p in plants:
		if weight(p, t, fps) <= 0.0:
			continue
		var foot := String(p["foot"])
		var sd := foot.right(2)
		var ball := "ball" + sd
		var pts := [FootRoll.heel_point(B, sd), B.P[ball], B.E[ball]]
		var line := []
		for q in pts:
			line.append(Vector3(q.x, 0.002, q.z))
		out.append({"foot": foot, "w": weight(p, t, fps), "pts": line})
	return out


## THE CHECK over a plant's range [t0, t1] at the scene's fps (B is left posed at the last frame; the caller re-poses):
## {"frames": n, "bad": [[t, miss_m], ...] the frames whose ankle is more than MISS_BAR off its pin, "worst": the largest
## miss (m), "turn_worst": the largest ball turn off its pin (deg)}
static func scan(S: Scene, B: Body, p: Dictionary, step := 0.0) -> Dictionary:
	var dt := step if step > 0.0 else 1.0 / float(maxi(S.fps, 1))
	var idx := S.plants.find(p)
	var t0 := float(p["t0"])
	var t1 := float(p["t1"])
	var n := int(floor((t1 - t0) / dt + 1e-6)) + 1
	var bad := []
	var worst := 0.0
	var turn_worst := 0.0
	for k in n:
		var t := minf(t0 + k * dt, t1)
		S.apply(B, t)
		var r: Dictionary = S.plant_last.get(idx, {})
		if r.is_empty():
			continue
		worst = maxf(worst, float(r["miss"]))
		turn_worst = maxf(turn_worst, float(r["ball_turn"]))
		if float(r["miss"]) > MISS_BAR:
			bad.append([t, float(r["miss"])])
	return {"frames": n, "bad": bad, "worst": worst, "turn_worst": turn_worst}
