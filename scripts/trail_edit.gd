## trail_edit.gd - EDITABLE MOTION TRAILS (ROADMAP 69). The white key dots on a pinned part's trail (Shift+T, overlays.gd)
## are handles: a press on one takes it, and dragging moves that part's world position AT THAT KEY (the card's moment),
## in the view plane through the dot, so the dot follows the mouse. The trail redraws as it goes (main.gd).
##   A HAND OR FOOT (a limb's tip): its IK. The key at the card gets the dragged point as its target, weight 1; every
##     other card keeps the limb exactly as it was (a key there, the curve sampled at that card).
##   ANY OTHER PART (forearm, head, spine ...): its joints from the part up to three ancestors (never the hips), angles
##     from a damped least-squares solve on the part's end point (Jacobian by finite differences, 0.5 deg steps).
##     Those joints are keyed at EVERY card first (part keys, the values they have now), so the other cards' poses do
##     not change; only the dragged card's angles move.
## A part whose limb is IK-pinned at that card is refused (its hand or foot is the handle to drag there).
## One undo step per drag: main.gd pushes it at the press; the moves write the scene directly; release keeps it.
class_name TrailEdit
extends RefCounted

const HIT_PX := 9.0      # a press this close (px) to a key dot takes it
const FD_DEG := 0.5      # finite-difference step for the Jacobian (deg)
const MAX_STEP := 8.0    # the largest change of one angle in one solver iteration (deg)
const ITERS := 24
const AXIS_NAMES := ["bend", "side", "twist"]   # Body.lim's keys, in Vector3 (bend, side, twist) order
const MAX_CHAIN := 5     # the part's joint and up to this many ancestors (the hips are never driven here)

var drag := {}           # the drag in progress; {} = none
var last := ""           # the last status line the drag wrote (the release repeats it: an out-of-reach gap stays shown)
var _W: Body = null      # the body the solve reads (never the live body)
var _F: Body = null      # a second body for the IK's FK reads


static func _new_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


func _body() -> Body:
	if _W == null:
		_W = _new_body()
	return _W


## the key dots: one per pinned part per card, at the card's moment: [{part, card, t, p}]
func dots(S: Scene, pins: Array) -> Array:
	var out := []
	if S == null or S.cards.size() < 2:
		return out
	var B := _body()
	var ts := S.times()
	for j in pins:
		for i in S.cards.size():
			var t := float(ts[i][1])
			S.apply(B, t)
			out.append({"part": j, "card": i, "t": t, "p": Overlays.part_point(B, j)})
	return out


## the dot under the mouse (the nearest within HIT_PX, in front of the eye), or {}
func hit(cam: Camera3D, S: Scene, pins: Array, mp: Vector2) -> Dictionary:
	var best := {}
	var best_d := HIT_PX
	var fwd := -cam.global_basis.z
	for d in dots(S, pins):
		var p: Vector3 = d["p"]
		if (p - cam.global_position).dot(fwd) <= cam.near:
			continue
		var dist := cam.unproject_position(p).distance_to(mp)
		if dist <= best_d:
			best_d = dist
			best = d
	return best


## the view-plane point under the mouse ray, on the plane through p0 with normal n (null = parallel / behind)
static func plane_hit(o: Vector3, d: Vector3, p0: Vector3, n: Vector3) -> Variant:
	var den := d.dot(n)
	if absf(den) < 1e-6:
		return null
	var s := (p0 - o).dot(n) / den
	return null if s < 0.0 else o + d * s


## the press on dot d: the keys this drag will change are read now. Returns the message ("" = started: see drag)
func begin(S: Scene, cam: Camera3D, mp: Vector2, d: Dictionary) -> String:
	var B := _body()
	var part: String = d["part"]
	var i := int(d["card"])
	var t := float(d["t"])
	var ts := S.times()
	drag = {}
	S.apply(B, t)
	var p0: Vector3 = Overlays.part_point(B, part)
	var n := cam.global_basis.z
	var hp = plane_hit(cam.project_ray_origin(mp), cam.project_ray_normal(mp), p0, n)
	var off: Vector3 = (p0 - hp) if hp != null else Vector3.ZERO
	var limb := LimbIK.limb_of(part)
	if part in LimbIK.LIMBS:
		var keys: Array = S.ik.get(part, [])
		var s := _sample(keys, t)
		var pre := []
		var F := _F if _F != null else _new_body()
		_F = F
		for c in S.cards.size():
			var ct := float(ts[c][1])
			if _has_key(keys, ct):
				continue
			var k := {"t": ct, "w": 0.0}
			if keys.is_empty():   # the limb's own FK there: its tip, and the pole its pose gives
				LimbIK._fk_at(S, F, part, ct)
				k["target"] = F.P[part]
				k["pole"] = LimbIK.pole_from_pose(F, part)
			else:
				var sc := _sample(keys, ct)
				k["target"] = sc["target"]
				k["pole"] = sc["pole"]
				k["w"] = sc["w"]
				if sc.has("rot"):
					k["rot"] = sc["rot"]
			pre.append(k)
		var rot: Quaternion = s["rot"] if s.has("rot") else B.G[part]
		# the key holds the WRIST (the IK's tip); the trail's point is the hand's end: the same offset as now (rot is kept)
		drag = {"route": "ik", "part": part, "t": t, "card": i, "p0": p0, "n": n, "off": off, "moved": false,
			"ik0": S.ik.duplicate(true), "pre": pre, "pole": (s["pole"] if float(s["w"]) > 0.0 else LimbIK.pole_from_pose(B, part)), "rot": rot,
			"tip_off": (B.P[part] as Vector3) - p0}
		return "trail key %d of the %s: drag it; the hand follows the IK target there" % [i + 1, part.replace("_", " ")]
	if limb != "" and LimbIK.weight_at(S.ik.get(limb, []), t) > 0.0:
		return "the %s is IK-pinned at this card: drag the hand or foot's own dot instead" % part.replace("_", " ")
	var chain := []
	var j := part
	while j != "" and j != "pelvis" and chain.size() < MAX_CHAIN:
		chain.append(j)
		j = B.parent[j]
	var pre2 := []
	for c in S.cards.size():
		var ct := float(ts[c][1])
		S.apply(B, ct)
		for jj in chain:
			pre2.append({"j": jj, "t": ct, "v": B.ang[jj]})
	S.apply(B, t)
	drag = {"route": "rot", "part": part, "t": t, "card": i, "p0": p0, "n": n, "off": off, "moved": false,
		"chain": chain, "pk0": S.part_keys.duplicate(true), "pre": pre2, "full0": B.ang.duplicate(true), "off0": B.offset}
	return "trail key %d of the %s: drag it; its joints %s move at that card" % [i + 1, part.replace("_", " "), ", ".join(chain)]


## the limb's keys sampled at t (an empty list is weight 0, not an error)
static func _sample(keys: Array, t: float) -> Dictionary:
	if keys.is_empty():
		return {"target": Vector3.ZERO, "pole": Vector3.ZERO, "w": 0.0}
	return LimbIK.sample(keys, t)


static func _has_key(keys: Array, t: float) -> bool:
	for k in keys:
		if absf(float(k["t"]) - t) < LimbIK.SAME_T:
			return true
	return false


## the mouse moved: the dragged part's point goes to the mouse's point on the drag's plane. Writes the keys; returns a
## status line (the miss when the part cannot get there)
func move(S: Scene, cam: Camera3D, mp: Vector2) -> String:
	if drag.is_empty():
		return ""
	var hp = plane_hit(cam.project_ray_origin(mp), cam.project_ray_normal(mp), drag["p0"], drag["n"])
	if hp == null:
		return ""
	var goal: Vector3 = (hp as Vector3) + (drag["off"] as Vector3)
	if (goal - (drag["p0"] as Vector3)).length() > 1e-6:
		drag["moved"] = true
	var miss := _move_ik(S, goal) if drag["route"] == "ik" else _move_rot(S, goal)
	var part: String = drag["part"]
	var moved := (goal - (drag["p0"] as Vector3)).length()
	last = "MOVING the %s at card %d: %.1f cm%s" % [part.replace("_", " "), int(drag["card"]) + 1, moved * 100.0,
		("   out of reach by %.1f mm: the limits stop it here, drag less" % (miss * 1000.0)) if miss > 0.002 else ""]
	return last


## the IK route: the card's key gets the goal as its target (weight 1); the rest of the IK keys are as they were
func _move_ik(S: Scene, goal: Vector3) -> float:
	var part: String = drag["part"]
	var t: float = drag["t"]
	S.ik = (drag["ik0"] as Dictionary).duplicate(true)
	for k in drag["pre"]:
		LimbIK.put(S.ik, part, (k as Dictionary).duplicate())
	var key := {"t": t, "target": goal + (drag["tip_off"] as Vector3), "pole": drag["pole"], "w": 1.0, "rot": drag["rot"]}
	LimbIK.put(S.ik, part, key)
	var B := _body()
	S.apply(B, t)
	return (goal - Overlays.part_point(B, part)).length()


## the rotation route: the joints of the part's chain are solved from the press pose, then keyed at this card
func _move_rot(S: Scene, goal: Vector3) -> float:
	var part: String = drag["part"]
	var t: float = drag["t"]
	S.part_keys = (drag["pk0"] as Dictionary).duplicate(true)
	for k in drag["pre"]:
		PartKeys.put(S.part_keys, k["j"], k["t"], k["v"])
	var B := _body()
	B.ang = (drag["full0"] as Dictionary).duplicate(true)
	B.offset = drag["off0"]
	B.fk()
	# solve, key the chain at this card, then read what the scene gives there (its grounding and other passes run after
	# the keys) and solve again from that pose. The best pass is what stays keyed (a clamped joint can make a later pass worse)
	var best := INF
	var best_ang := {}
	for pass_i in 3:
		solve_rot(B, part, drag["chain"], goal)
		for j in drag["chain"]:
			PartKeys.put(S.part_keys, j, t, B.ang[j])
		S.apply(B, t)
		var miss := (goal - Overlays.part_point(B, part)).length()
		if miss < best:
			best = miss
			best_ang = {}
			for j in drag["chain"]:
				best_ang[j] = B.ang[j]
		if miss < 2e-4:
			break
	for j in best_ang:
		PartKeys.put(S.part_keys, j, t, best_ang[j])
	return best


## moves part's end point to goal by turning the joints of chain (B is posed; its angles change in place and are clamped
## to the body's limits). Damped least squares, the 3x3 solved by its adjugate. Returns the miss in metres
static func solve_rot(B: Body, part: String, chain: Array, goal: Vector3) -> float:
	for it in ITERS:
		B.fk()
		var e0: Vector3 = Overlays.part_point(B, part)
		var err := goal - e0
		if err.length() < 1e-6:
			break
		var cols := []   # per angle: how far the end point moves per degree (m/deg)
		var which := []  # [joint, axis] per column
		for j in chain:
			for ax in 3:
				var v: Vector3 = B.ang[j]
				v[ax] += FD_DEG
				B.ang[j] = v
				B.fk()
				cols.append((Overlays.part_point(B, part) - e0) / FD_DEG)
				which.append([j, ax])
				v[ax] -= FD_DEG
				B.ang[j] = v
		# an angle at its limit that the error wants pushed further is frozen (its column zeroed): the others carry the move
		for k in cols.size():
			var j: String = which[k][0]
			var ax: int = which[k][1]
			var r: Vector2 = B.lim[j][AXIS_NAMES[ax]]
			var val: float = B.ang[j][ax]
			var helps: float = (cols[k] as Vector3).dot(err)
			if (helps > 0.0 and val >= r.y - 1e-4) or (helps < 0.0 and val <= r.x + 1e-4):
				cols[k] = Vector3.ZERO
		var A := [[1e-9, 0.0, 0.0], [0.0, 1e-9, 0.0], [0.0, 0.0, 1e-9]]   # J J^T + lambda I
		for c in cols:
			for r in 3:
				for q in 3:
					A[r][q] += c[r] * c[q]
		var y := _solve3(A, err)
		var dth := []
		var mx := 0.0
		for c in cols:
			var dv: float = (c as Vector3).dot(y)
			dth.append(dv)
			mx = maxf(mx, absf(dv))
		var s := minf(1.0, MAX_STEP / maxf(mx, 1e-12))
		for k in which.size():
			var v: Vector3 = B.ang[which[k][0]]
			v[which[k][1]] += dth[k] * s
			B.ang[which[k][0]] = B.clamp_ang(which[k][0], v)   # inside the limits every step, not only at the end
	for j in chain:
		B.ang[j] = B.clamp_ang(j, B.ang[j])
	B.fk()
	return (goal - Overlays.part_point(B, part)).length()


## x of A x = b for a 3x3 A (adjugate); zero when A is singular
static func _solve3(A: Array, b: Vector3) -> Vector3:
	var a: float = A[0][0]
	var bb: float = A[0][1]
	var c: float = A[0][2]
	var d: float = A[1][0]
	var e: float = A[1][1]
	var f: float = A[1][2]
	var g: float = A[2][0]
	var h: float = A[2][1]
	var i: float = A[2][2]
	var det := a * (e * i - f * h) - bb * (d * i - f * g) + c * (d * h - e * g)
	if absf(det) < 1e-300:
		return Vector3.ZERO
	var inv := [
		[e * i - f * h, -(bb * i - c * h), bb * f - c * e],
		[-(d * i - f * g), a * i - c * g, -(a * f - c * d)],
		[d * h - e * g, -(a * h - bb * g), a * e - bb * d]]
	var x := []
	for r in 3:
		x.append((inv[r][0] * b.x + inv[r][1] * b.y + inv[r][2] * b.z) / det)
	return Vector3(x[0], x[1], x[2])


## release: the keys were written as the mouse moved. Returns true when the drag moved anything (the caller keeps its
## one undo step; false = drop it)
func end() -> bool:
	var moved: bool = drag.get("moved", false)
	drag = {}
	return moved
