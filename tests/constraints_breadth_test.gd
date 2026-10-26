## godot --headless --path . -s tests/constraints_breadth_test.gd   (scripts/constraints.gd: plan item A2, constraint breadth)
## Bars, written before measuring (tests/constraints_test.gd keeps the Child Of / Track To / Floor bars):
##   1 COPY LOCATION: the left hand copies the right hand's place over the 2.8 s hold sweep at 240 Hz: <= 1 mm at every
##     step (anti-vacuity: unconstrained the two hands are > 5 cm apart at some step). The hips copy a point: <= 1 mm.
##   2 COPY ROTATION: the left hand takes the right hand's turn: <= 1 deg at every step, and its place stays the
##     unconstrained place within 1 mm (copy rotation does not move a hand).
##   3 DAMPED TRACK: the right hand's knuckle line points at a point 30 cm ahead of it: <= 2 deg at every step
##     (anti-vacuity: > 20 deg unconstrained at some step); its place stays the unconstrained place within 1 mm.
##   4 LIMIT LOCATION: the left hand kept in a 10 cm box round where it stands at t = 0: wherever the unconstrained hand is
##     outside the box, the constrained hand is within 1 mm of the nearest box point; wherever it is inside, the body is
##     bit-identical to no constraint (anti-vacuity: the unconstrained hand leaves the box on some step).
##   5 STACK: Child Of (left hand to the right hand) then Copy Rotation (left hand to the right hand's turn): every joint
##     angle and the pelvis offset posed by hand give the same joints (0 difference, 1e-6); the left hand's turn is the
##     right hand's within 1 deg.
##   6 INFLUENCE 0: each new type muted, or with influence 0, plays bit-identical to no constraint on every 4th frame.
##   7 FILE: the four types save -> load -> save equal; the reloaded stack plays within 0.05 mm of the session; the mirror
##     of the limit box is the x-negated box, exact to 1e-6 m, and the owner is the twin.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func pose(B: Body, angs: Dictionary) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.wep_on = false
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	return B.to_dict()


func trunk(d: Dictionary, bend: float, side: float, twist: float) -> Dictionary:
	var o := d.duplicate()
	for j in ["spine_01", "spine_02", "spine_03"]:
		o[j] = Vector3(bend, side, twist)
	return o


## the same hold sweep as tests/constraints_test.gd: two hands in front, the arms and the trunk moving, 24 fps
func hold_scene(B: Body) -> Scene:
	var S := Scene.new()
	S.fps = 24
	S.add("a", pose(B, {"upperarm_r": Vector3(45, -50, 0), "lowerarm_r": Vector3(70, 0, 0), "upperarm_l": Vector3(45, -50, 0), "lowerarm_l": Vector3(70, 0, 0)}))
	S.add("b", pose(B, trunk({"upperarm_r": Vector3(62, -50, 0), "lowerarm_r": Vector3(52, 0, 0), "upperarm_l": Vector3(55, -45, 0), "lowerarm_l": Vector3(60, 0, 0)}, 5, 0, -14)))
	S.add("c", pose(B, trunk({"upperarm_r": Vector3(32, -52, 0), "lowerarm_r": Vector3(88, 0, 0), "upperarm_l": Vector3(35, -50, 0), "lowerarm_l": Vector3(80, 0, 0)}, 14, -5, 6)))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 0.2
	S.cards[1]["move"] = 1.4
	S.cards[1]["hold"] = 0.0
	S.cards[2]["move"] = 1.4
	S.cards[2]["hold"] = 0.4
	return S


func frames(S: Scene, hz: float) -> Array:
	var out := []
	var n := int(ceilf(S.length() * hz - 1e-6))
	for f in n + 1:
		out.append(minf(float(f) / hz, S.length()))
	return out


func snap(B: Body) -> String:
	return var_to_str(B.ang) + var_to_str(B.offset) + var_to_str(B.wep_xform())


func _init() -> void:
	var B := body()
	var B0 := body()
	var ts := frames(hold_scene(B), 240.0)
	var lim := 0.0

	# ------------------------------------------------ 1 COPY LOCATION
	var S := hold_scene(B)
	var S0 := hold_scene(B)
	S.apply(B, 0.0)
	# a spot (a prop, say) 10 cm short of the left arm's reach at t = 0 (reach 0.55 m); the right hand is out of
	# reach of the left shoulder on this sweep (0.58 m away), so the target is the spot, not the right hand
	var spot: Vector3 = (B.P["hand_l"] as Vector3) + ((B.P["upperarm_l"] as Vector3) - (B.P["hand_l"] as Vector3)).normalized() * 0.10
	var c := Constraints.add_copy(S, B, "copy_location", "hand_l", {"kind": "point", "at": spot}, 0.0)
	ok(not c.is_empty(), "1 copy location added (hand_l -> a spot in reach)")
	var worst := 0.0
	var apart := 0.0
	var clamp_n := 0
	for t in ts:
		S.apply(B, t)
		S0.apply(B0, t)
		worst = maxf(worst, ((B.P["hand_l"] as Vector3) - spot).length())
		apart = maxf(apart, ((B0.P["hand_l"] as Vector3) - spot).length())
		if not (S.cons_last[0]["clamped"] as Array).is_empty():
			clamp_n += 1
	print("   copy location: worst miss to the spot %.3f mm (unconstrained up to %.1f cm off); joint limits hit on %d steps" % [worst * 1000.0, apart * 100.0, clamp_n])
	ok(worst <= 0.001, "1 the left hand is on the spot every step, <= 1 mm (worst %.3f mm)" % (worst * 1000.0))
	ok(apart > 0.05, "1 anti-vacuity: unconstrained the hand is > 5 cm off the spot (max %.1f cm)" % (apart * 100.0))
	ok(clamp_n == 0, "1 no joint limit is hit on the sweep (%d steps)" % clamp_n)

	var SP := hold_scene(B)
	Constraints.add_copy(SP, B, "copy_location", "pelvis", {"kind": "point", "at": Vector3(0.3, 1.0, 0.2)}, 0.0)
	var worst_p := 0.0
	for t in ts:
		SP.apply(B, t)
		worst_p = maxf(worst_p, ((B.P["pelvis"] as Vector3) - Vector3(0.3, 1.0, 0.2)).length())
	print("   copy location on the hips: worst miss to the point %.3f mm" % (worst_p * 1000.0))
	ok(worst_p <= 0.001, "1 the hips copy a point: <= 1 mm every step (worst %.3f mm)" % (worst_p * 1000.0))

	# ------------------------------------------------ 2 COPY ROTATION
	S = hold_scene(B)
	S0 = hold_scene(B)
	S.apply(B, 0.0)
	Constraints.add_copy(S, B, "copy_rotation", "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	var worst_rot := 0.0
	var worst_place := 0.0
	var keep2: Quaternion = S.cons[0]["offset"]["rot"]   # Offset: the turn the left hand had against the right at t = 0
	for t in ts:
		S.apply(B, t)
		S0.apply(B0, t)
		worst_rot = maxf(worst_rot, rad_to_deg((B.G["hand_l"] as Quaternion).angle_to((B.G["hand_r"] as Quaternion) * keep2)))
		worst_place = maxf(worst_place, ((B.P["hand_l"] as Vector3) - (B0.P["hand_l"] as Vector3)).length())
	print("   copy rotation: worst turn gap %.3f deg, worst place gap %.3f mm" % [worst_rot, worst_place * 1000.0])
	ok(worst_rot <= 1.0, "2 the left hand's turn is the right hand's every step, <= 1 deg (worst %.3f deg)" % worst_rot)
	ok(worst_place <= 0.001, "2 its place is the unconstrained place, <= 1 mm (worst %.3f mm)" % (worst_place * 1000.0))

	# ------------------------------------------------ 3 DAMPED TRACK
	S = hold_scene(B)
	S0 = hold_scene(B)
	S.apply(B, 0.0)
	# a spot 30 cm out along the right knuckle line at t = 0 (the hand already points there at the start)
	S.apply(B, 0.0)
	var aim: Vector3 = (B.P["hand_r"] as Vector3) + Constraints._track_dir(B, "hand_r") * 0.3
	Constraints.add_copy(S, B, "damped_track", "hand_r", {"kind": "point", "at": aim}, 0.0)
	var worst_aim := 0.0
	var unc_aim := 0.0
	var worst_dp := 0.0
	var clamp_d := 0
	for t in ts:
		S.apply(B, t)
		S0.apply(B0, t)
		var dir := (aim - (B.P["hand_r"] as Vector3)).normalized()
		var e := rad_to_deg(acos(clampf(Constraints._track_dir(B, "hand_r").dot(dir), -1.0, 1.0)))
		if (S.cons_last[0]["clamped"] as Array).is_empty():
			worst_aim = maxf(worst_aim, e)
		else:
			clamp_d += 1
		var dir0 := (aim - (B0.P["hand_r"] as Vector3)).normalized()
		unc_aim = maxf(unc_aim, rad_to_deg(acos(clampf(Constraints._track_dir(B0, "hand_r").dot(dir0), -1.0, 1.0))))
		worst_dp = maxf(worst_dp, ((B.P["hand_r"] as Vector3) - (B0.P["hand_r"] as Vector3)).length())
	print("   damped track: worst aim error %.3f deg on the %d steps with no joint at a limit (unconstrained up to %.1f deg); worst place gap %.3f mm" % [worst_aim, ts.size() - clamp_d, unc_aim, worst_dp * 1000.0])
	ok(worst_aim <= 2.0, "3 the right hand points at the spot on every step with no joint at a limit, <= 2 deg (worst %.3f deg)" % worst_aim)
	ok(unc_aim > 10.0, "3 anti-vacuity: unconstrained the hand is > 10 deg off (max %.1f deg)" % unc_aim)
	ok(worst_dp <= 0.001, "3 its place is the unconstrained place, <= 1 mm (worst %.3f mm)" % (worst_dp * 1000.0))

	# ------------------------------------------------ 4 LIMIT LOCATION
	S = hold_scene(B)
	S0 = hold_scene(B)
	S.apply(B, 0.0)
	var box := Constraints.add_limit(S, B, "hand_l", 0.0)
	var mn: Vector3 = box["min"]
	var mx: Vector3 = box["max"]
	var out_n := 0
	var worst_box := 0.0
	var inside_same := true
	var inside_n := 0
	for t in ts:
		S.apply(B, t)
		S0.apply(B0, t)
		var pu: Vector3 = B0.P["hand_l"]
		var near := pu.clamp(mn, mx)
		if (near - pu).length() > 1e-9:
			out_n += 1
			worst_box = maxf(worst_box, ((B.P["hand_l"] as Vector3) - near).length())
		else:
			inside_n += 1
			if snap(B) != snap(B0):
				inside_same = false
	print("   limit location: %d steps outside the box, worst miss to the box %.3f mm; %d steps inside" % [out_n, worst_box * 1000.0, inside_n])
	ok(out_n > 0, "4 anti-vacuity: the unconstrained hand leaves the 10 cm box on %d steps" % out_n)
	ok(worst_box <= 0.001, "4 outside the box the hand sits on the nearest box point, <= 1 mm (worst %.3f mm)" % (worst_box * 1000.0))
	ok(inside_same, "4 inside the box the body is bit-identical to no constraint (%d steps)" % inside_n)

	# ------------------------------------------------ 5 STACK: Child Of then Copy Rotation = the manual pose
	S = hold_scene(B)
	S.apply(B, 0.0)
	Constraints.add_child_of(S, B, "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	Constraints.add_copy(S, B, "copy_rotation", "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	var t5 := 0.8
	S.apply(B, t5)
	var M := body()
	for j in Body.ORDER:
		M.ang[j] = B.ang[j]
	M.offset = B.offset
	M.wep_on = false
	M.fk()
	var diff := 0.0
	var diff_p := 0.0
	var diff_g := 0.0
	for j in Body.ORDER:
		diff_p = maxf(diff_p, ((M.P[j] as Vector3) - (B.P[j] as Vector3)).length())
		diff_g = maxf(diff_g, deg_to_rad((M.G[j] as Quaternion).angle_to(B.G[j] as Quaternion)))
	diff = maxf(diff_p, diff_g)
	print("   stack: worst place gap %.9f m, worst turn gap %.9f rad" % [diff_p, diff_g])
	# the turn the left hand keeps against the right (Copy Rotation's Offset, taken at t = 0)
	var keep: Quaternion = S.cons[1]["offset"]["rot"]
	var turn5 := rad_to_deg((B.G["hand_l"] as Quaternion).angle_to((B.G["hand_r"] as Quaternion) * keep))
	print("   stack: manual-pose difference %.9f (metres and radians, worst joint); turn gap to the kept offset %.3f deg" % [diff, turn5])
	ok(diff <= 1e-6, "5 the stack's result is the manual pose: 0 difference (%.9f)" % diff)
	ok(turn5 <= 1.0, "5 the left hand keeps its turn against the right hand, <= 1 deg (%.3f deg)" % turn5)

	# ------------------------------------------------ 6 INFLUENCE 0 / MUTE: bit-identical to no constraint
	var kinds := ["copy_location", "copy_rotation", "damped_track", "limit_location"]
	for ty in kinds:
		var SX := hold_scene(B)
		var SY := hold_scene(B)
		var cx: Dictionary
		if ty == "limit_location":
			SX.apply(B, 0.0)
			cx = Constraints.add_limit(SX, B, "hand_l", 0.0)
		else:
			SX.apply(B, 0.0)
			cx = Constraints.add_copy(SX, B, ty, "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
		cx["mute"] = true
		var same := true
		var i := 0
		for t in ts:
			if i % 4 == 0:
				SX.apply(B, t)
				SY.apply(B0, t)
				if snap(B) != snap(B0):
					same = false
			i += 1
		cx.erase("mute")
		cx["w"] = 0.0
		var same0 := true
		i = 0
		for t in ts:
			if i % 4 == 0:
				SX.apply(B, t)
				SY.apply(B0, t)
				if snap(B) != snap(B0):
					same0 = false
			i += 1
		ok(same and same0, "6 %s muted or at influence 0: bit-identical to no constraint on every 4th frame" % ty)

	# ------------------------------------------------ 7 FILE: round trip, reload plays the same, mirror
	S = hold_scene(B)
	S.apply(B, 0.0)
	Constraints.add_copy(S, B, "copy_location", "hand_l", {"kind": "part", "part": "hand_r"}, 0.0)
	Constraints.add_copy(S, B, "copy_rotation", "hand_r", {"kind": "point", "at": Vector3(0.1, 1.2, 0.4)}, 0.0)
	Constraints.add_copy(S, B, "damped_track", "hand_r", {"kind": "point", "at": Vector3(0.1, 1.2, 0.4)}, 0.0)
	Constraints.add_limit(S, B, "foot_l", 0.0)
	var f1 := Constraints.to_file(S.cons)
	var back := Constraints.from_file(f1)
	var f2 := Constraints.to_file(back)
	ok(var_to_str(f1) == var_to_str(f2), "7 the four types save -> load -> save equal")
	var S2 := hold_scene(B)
	S2.cons = back
	var S3 := hold_scene(B)
	S3.cons = S.cons
	var worst_reload := 0.0
	for t in ts:
		S2.apply(B, t)
		S3.apply(B0, t)
		for j in ["hand_l", "hand_r", "foot_l"]:
			worst_reload = maxf(worst_reload, ((B.P[j] as Vector3) - (B0.P[j] as Vector3)).length())
	print("   reload: worst place gap %.4f mm" % (worst_reload * 1000.0))
	ok(worst_reload <= 0.00005, "7 the reloaded stack plays within 0.05 mm of the session (worst %.4f mm)" % (worst_reload * 1000.0))
	var mir := Constraints.mirror_file(f1)
	var lb := {}
	for d in f1:
		if d["type"] == "limit_location":
			lb = d
	var mb := {}
	for d in mir:
		if d["type"] == "limit_location":
			mb = d
	var exact := absf(float(mb["min"][0]) + float(lb["max"][0])) < 1e-6 and absf(float(mb["max"][0]) + float(lb["min"][0])) < 1e-6
	ok(exact and mb["owner"] == "foot_r", "7 mirror: the box's x runs the other way, owner foot_l -> foot_r (exact to 1e-6 m)")
	quit(fails)
