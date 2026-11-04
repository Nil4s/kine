extends RefCounted
## CH14 the build sequence: keyframes of the whole job (6 cans from the pickup stand to the pyramid), the state of every axis at any time t (task-space moves,
## inverse kinematics each sample), the slave strokes and the master plunger travel they imply, and a swept-clearance check (arm links, gripper and the held
## can against the cans already placed). Plan frame: yaw 0 = radial +x; the arm's radial direction at yaw psi is (cos psi, 0, -sin psi); height is +y.
const A := preload("res://scripts/build/ch14_arm.gd")

const CLEAR := 40.0      # mm between the underside of a carried can and the top of the highest placed can in transit
const HOVER := 25.0
const ARM_HALF := 15.0   # half width of the boom
const SPEED_YAW := 55.0  # deg/s
const SPEED_LIN := 90.0  # mm/s
const T_GRIP := 1.2
const RISE := 80.0       # mm the open gripper rises over the can it just set down before the base turns (the jaw bottoms are 15 mm below the can centre, the top 61 above)


## stack heights: the top of the highest can of the first k placed (mm)
static func top_after(k: int) -> float:
	if k <= 0:
		return 0.0
	if k <= 3:
		return A.CAN_H
	if k <= 5:
		return 2.0 * A.CAN_H
	return 3.0 * A.CAN_H


## the waypoints: [{"yaw","r","z","g" (grip stroke 0 open .. 8 closed),"held" (can index or -1),"t" (arrival time s),"label"}]
static func waypoints(d: Dictionary, transit_clear := CLEAR) -> Array:
	var ps := A.poses(d)
	var pick: Dictionary = ps[0]
	var zc := A.CAN_H / 2.0
	var out := []
	var S := {"t": 0.0, "cur": {"yaw": -90.0, "r": float(pick["r"]), "z": zc + 120.0, "g": 0.0, "held": -1, "t": 0.0, "label": "home"}}
	out.append((S["cur"] as Dictionary).duplicate())
	var add := func(yaw: float, r: float, z: float, g: float, held: int, label: String, min_t := 0.0) -> void:
		var cur: Dictionary = S["cur"]
		var dist := Vector2(r - float(cur["r"]), z - float(cur["z"])).length()
		var dt := maxf(maxf(dist / SPEED_LIN, absf(yaw - float(cur["yaw"])) / SPEED_YAW), min_t)
		dt = maxf(dt, 0.4)
		S["t"] = float(S["t"]) + dt
		S["cur"] = {"yaw": yaw, "r": r, "z": z, "g": g, "held": held, "t": S["t"], "label": label}
		out.append((S["cur"] as Dictionary).duplicate())
	for k in 6:
		var tgt: Dictionary = ps[k + 1]
		add.call(-90.0, pick["r"], zc + HOVER, 0.0, -1, "can %d: over the pickup" % (k + 1))
		add.call(-90.0, pick["r"], zc, 0.0, -1, "can %d: down to the can" % (k + 1))
		add.call(-90.0, pick["r"], zc, 8.0, k, "can %d: grip closes" % (k + 1), T_GRIP)
		add.call(-90.0, pick["r"], zc + HOVER + transit_clear, 8.0, k, "can %d: lift" % (k + 1))
		add.call(90.0, tgt["r"], float(tgt["z"]) + HOVER, 8.0, k, "can %d: base turns 180 deg" % (k + 1), 5.5)
		add.call(90.0, tgt["r"], tgt["z"], 8.0, k, "can %d: down onto the stack" % (k + 1))
		add.call(90.0, tgt["r"], tgt["z"], 0.0, -1, "can %d: released" % (k + 1), T_GRIP)
		var r_up: float = float(tgt["r"]) + (40.0 if k == 5 else 0.0)     # the top can has nothing beside it: the gripper also slides out 40 mm so the shoulder stays inside its limit
		add.call(90.0, r_up, float(tgt["z"]) + RISE, 0.0, -1, "can %d: up clear of the can" % (k + 1))
		add.call(55.0, r_up, float(tgt["z"]) + RISE, 0.0, -1, "can %d: base turns back (high)" % (k + 1), 2.5)
		add.call(-90.0, pick["r"], zc + 120.0, 0.0, -1, "can %d: base turns back" % (k + 1), 3.5)
	return out


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## the state at time t: yaw, r, z, g, the held can index, joint angles
static func state(d: Dictionary, wp: Array, t: float) -> Dictionary:
	var n := wp.size()
	var i := 0
	while i < n - 2 and float(wp[i + 1]["t"]) < t:
		i += 1
	var a: Dictionary = wp[i]
	var b: Dictionary = wp[mini(i + 1, n - 1)]
	var span := maxf(float(b["t"]) - float(a["t"]), 1e-9)
	var u := clampf((t - float(a["t"])) / span, 0.0, 1.0)
	var e := _ease(u)
	var st := {
		"yaw": lerpf(float(a["yaw"]), float(b["yaw"]), e), "r": lerpf(float(a["r"]), float(b["r"]), e),
		"z": lerpf(float(a["z"]), float(b["z"]), e), "g": lerpf(float(a["g"]), float(b["g"]), e),
		"label": String(b["label"]) if u > 0.0 else String(a["label"]), "idx": i}
	# the can is in the jaws from the moment the grip passes 7.5 mm closing until it opens below 7.5 again
	var hk: int = int(b["held"]) if int(b["held"]) >= 0 else int(a["held"])
	st["held"] = hk if float(st["g"]) >= 7.5 else -1
	var q := A.ik(d, st["r"], st["z"])
	st["ik"] = q
	if q.has("th1"):
		st["th1"] = q["th1"]
		st["th2"] = q["th2"]
		st["psi"] = q["psi"]
	return st


## which cans are standing on the pyramid at time t (placed: released with the grip fully open at the target)
static func placed_at(d: Dictionary, wp: Array, t: float) -> Array:
	var out := []
	var k := 0
	for w in wp:
		if String(w["label"]).ends_with("released") and float(w["t"]) <= t:
			k += 1
	for q in k:
		out.append(q)
	return out


# ---------------------------------------------------------------- 3D clearance

static func _seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var tt := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		tt = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			if den > 1e-12:
				s = clampf((b * f - c * e) / den, 0.0, 1.0)
			tt = (b * s + f) / e
			if tt < 0.0:
				tt = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif tt > 1.0:
				tt = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * tt)).length()


static func rad_dir(yaw: float) -> Vector3:
	return Vector3(cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw)))


## world positions (mm) of the shoulder, elbow, wrist, can centre for a state
static func joints(d: Dictionary, st: Dictionary) -> Dictionary:
	var f := A.fk(d, st["th1"], st["th2"])
	var u := rad_dir(st["yaw"])
	var pt := func(v: Vector2) -> Vector3:
		return u * v.x + Vector3(0, v.y, 0)
	return {"s": pt.call(Vector2(0, d["hs"])), "e": pt.call(f["e"]), "w": pt.call(f["w"]), "c": pt.call(f["c"])}


## minimum clearance (mm, negative = collision) between the moving arm + held can and the cans in `placed` (indices of the building order) at a state
static func clearance(d: Dictionary, st: Dictionary, placed: Array) -> float:
	if not st.has("th1"):
		return -1e9
	var j := joints(d, st)
	var ps := A.poses(d)
	var best := 1e9
	var u := rad_dir(90.0)
	for k in placed:
		var tp: Dictionary = ps[int(k) + 1]
		var base: Vector3 = u * float(tp["r"])
		var gx: Vector3 = (j["w"] as Vector3)
		if Vector2(gx.x - base.x, gx.z - base.z).length() < 8.0:
			continue      # the gripper's own can: it moves straight up and down on it
		var c0 := Vector3(base.x, float(tp["z"]) - A.CAN_H / 2.0, base.z)
		var c1 := Vector3(base.x, float(tp["z"]) + A.CAN_H / 2.0, base.z)
		var r_can := A.CAN_D / 2.0
		# upper arm, forearm: capsules
		best = minf(best, _seg_seg(j["s"], j["e"], c0, c1) - r_can - ARM_HALF)
		best = minf(best, _seg_seg(j["e"], j["w"], c0, c1) - r_can - ARM_HALF)
		# gripper housing and jaws as boxes in the plan (radial x tangent) against the can's circle, where their heights overlap the can's
		var wp3: Vector3 = j["w"]
		var rd := rad_dir(st["yaw"])
		var tg := Vector3(-rd.z, 0.0, rd.x)     # tangent, perpendicular to the radial direction in the plan
		var cx := Vector2(base.x - wp3.x, base.z - wp3.z)
		var cr := cx.dot(Vector2(rd.x, rd.z))
		var ct := cx.dot(Vector2(tg.x, tg.z))
		var can_lo: float = float(tp["z"]) - A.CAN_H / 2.0 + 2.0
		var can_hi: float = float(tp["z"]) + A.CAN_H / 2.0 - 2.0
		var boxes := [[-25.0, 25.0, -60.0, 60.0, wp3.y - 4.0, wp3.y + 24.0]]                  # housing
		var inner := 41.1 - float(st["g"])
		boxes.append([-14.0, 14.0, inner, inner + 6.0, wp3.y - float(d["dg"]) - 15.0, wp3.y - 4.0])         # jaw +
		boxes.append([-14.0, 14.0, -inner - 6.0, -inner, wp3.y - float(d["dg"]) - 15.0, wp3.y - 4.0])        # jaw -
		for bx in boxes:
			if float(bx[5]) < can_lo or float(bx[4]) > can_hi:
				continue
			var dx := maxf(maxf(float(bx[0]) - cr, cr - float(bx[1])), 0.0)
			var dy := maxf(maxf(float(bx[2]) - ct, ct - float(bx[3])), 0.0)
			best = minf(best, sqrt(dx * dx + dy * dy) - r_can)
	return best


## sweep the whole job at dt; returns {"min": smallest clearance, "at": label, "lost_ik": states without a solution, "t_end"}
static func sweep(d: Dictionary, wp: Array, dt := 0.1) -> Dictionary:
	var t_end: float = wp[wp.size() - 1]["t"]
	var best := 1e9
	var at := ""
	var lost := 0
	var t := 0.0
	while t <= t_end:
		var st := state(d, wp, t)
		if not (st["ik"] as Dictionary)["ok"]:
			lost += 1
		var pl := placed_at(d, wp, t)
		var c := clearance(d, st, pl)
		if c < best:
			best = c
			at = "%s at t %.1f s" % [st["label"], t]
		t += dt
	return {"min": best, "at": at, "lost_ik": lost, "t_end": t_end}


# ---------------------------------------------------------------- the strokes the state implies

static func strokes(d: Dictionary, st: Dictionary) -> Dictionary:
	var out := A.strokes(d, st["yaw"], st["th1"], st["th2"])
	out["gr"] = st["g"]
	# master plunger distance from fully pushed in (mm): what is still to be pushed = (swept volume - slave volume so far) / master area
	var m := {}
	for j in ["ba", "sh", "el", "wr", "gr"]:
		var sm: int = d["cyl"][j][0]
		var ss: int = d["cyl"][j][1]
		var full: float = (PI * float(d["rp_pinion"]) if j == "ba" else (8.0 if j == "gr" else float(A.chain(d, j)["stroke"])))
		m[j] = (full - float(out[j])) * A.area(ss) / A.area(sm)
	out["master_out"] = m
	return out
