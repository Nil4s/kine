## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/line_of_action_test.gd   (ROADMAP 23: sketch a line of action -> pose)
## A stroke is cast from the screen onto the plane through the pelvis that faces the camera, fitted, and applied as ONE
## undo step. Built in the test: the strokes are the screen projections of known curves (a C and an S, in the plane
## the view sees), so the screen path (cast, smooth, resample, anchor) is exercised too.
##   1 a C-curve stroke: the joint points spine_01, spine_02, spine_03, neck_01, the head's centre and the support knee
##     lie within 2 cm of the curve (or a joint is at its limit, reported), and the pelvis is on it (the anchor)
##   2 an S-curve gives an S: the lower spine and the upper spine bend opposite ways; the C's two halves bend the same way
##   3 the arms are bit-identical (every arm joint's angles, exactly)
##   4 no joint past its limits (every angle inside Body.lim)
##   5 one stroke = one undo step, and Ctrl+Z (undo) puts the pose back exactly
##   6 Shift (mirror) flips the lean of the C
##   7 the overlay: the current line of action is drawn; a screenshot of the C pose with its line goes to user://
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _arm_joints() -> Array:
	return ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]


func _in_limits(B: Body) -> String:
	for j in Body.ORDER:
		if not B.lim.has(j):
			continue
		var v: Vector3 = B.ang[j]
		for k in 3:
			var r: Vector2 = B.lim[j][["bend", "side", "twist"][k]]
			if v[k] < r.x - 1e-4 or v[k] > r.y + 1e-4:
				return "%s %s %.2f outside %.1f..%.1f" % [j, ["bend", "side", "twist"][k], v[k], r.x, r.y]
	return ""


## the joint points the test checks, read from the body itself, and their distance to the curve
func _dists(B: Body, curve: Array, s: String) -> Dictionary:
	var pts := {"pelvis": B.P["pelvis"], "spine_01": B.P["spine_01"], "spine_02": B.P["spine_02"],
		"spine_03": B.P["spine_03"], "neck_01": B.P["neck_01"], "head": LineOfAction.head_c(B), "knee": B.P["calf" + s]}
	var out := {}
	for k in pts:
		var p: Vector3 = pts[k]
		out[k] = p.distance_to(LineOfAction.closest(curve, p))
	return out


## screen points of a curve given in the view's plane through the pelvis (the plane the stroke is cast onto)
func _screen(cam: Camera3D, world: Array) -> Array:
	var out := []
	for p: Vector3 in world:
		out.append(cam.unproject_position(p))
	return out


func _side_sum(B: Body, joints: Array) -> float:
	var s := 0.0
	for j in joints:
		s += (B.ang[j] as Vector3).y
	return s


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var B: Body = m.B
	var loa: LineOfAction = m.loa
	m.yaw = 0.0
	m.pitch = 0.0
	m._cam()
	await process_frame
	var cam: Camera3D = m.cam
	var right := cam.global_basis.x
	var pel: Vector3 = B.P["pelvis"]
	var hc := LineOfAction.head_c(B)
	var H := hc - pel
	var arms := {}
	for j in _arm_joints():
		arms[j] = (B.ang[j] as Vector3)
	var s_start: Dictionary = B.state()
	var n0: int = m.undo.size()
	# the C: a lateral bulge of 8 cm from the pelvis to the head, drawn in the view's plane
	# one smooth stroke from the planted ankle up through the pelvis to the head: a C bows it 10 cm, sin(pi s)
	var ank: Vector3 = B.P["foot" + LineOfAction.support(B)]
	var hc_t := LineOfAction.head_c(B)
	var c_world := []
	for i in 61:
		var u := float(i) / 60.0
		c_world.append(ank + (hc_t - ank) * u + right * (0.10 * sin(PI * u)))
	var c_screen := _screen(cam, c_world)
	m._loa_apply(c_screen, false)
	var n1: int = m.undo.size()
	var rep: Dictionary = loa.last
	var curve: Array = loa.last_curve
	ok(not rep.is_empty() and curve.size() == LineOfAction.N_CURVE, "0 the stroke was applied: %d curve points, worst %.1f mm" % [curve.size(), float(rep.get("worst", -1.0)) * 1000.0])
	var side: String = rep["side"]
	var d := _dists(B, curve, side)
	var at: Array = rep.get("limits", [])
	var lines := []
	var inside := true
	var own := {"spine_01": "spine_01", "spine_02": "spine_02", "spine_03": "spine_03", "neck_01": "neck_01",
		"head": "head", "knee": "calf" + side}
	for k in d:
		lines.append("%s %.1f" % [k, float(d[k]) * 1000.0])
		if k == "pelvis" or float(d[k]) <= 0.02:
			continue
		# outside 2 cm: only allowed when that joint's own angle sits on a limit
		var stuck := false
		for a in at:
			if String(a).begins_with(own[k]):
				stuck = true
		if not stuck:
			inside = false
	print("     joint points to the curve (mm): " + ", ".join(lines) + "; at a limit: " + str(at) + "; support " + side + "; foot drift %.2f mm" % (float(rep.get("foot_drift", 0.0)) * 1000.0))
	ok(float(d["pelvis"]) < 0.02, "1a the pelvis is on the curve (the anchor, within 2 cm): %.1f mm" % (float(d["pelvis"]) * 1000.0))
	ok(float(rep.get("foot_drift", 1.0)) < 1e-4, "1c the planted ankle stands where it did: drift %.4f mm" % (float(rep.get("foot_drift", 1.0)) * 1000.0))
	ok(inside, "1b spine_01..03, neck, head, knee within 2 cm of the curve, or their own angle at its limit (reported: %s)" % str(at))
	var lower_c := _side_sum(B, ["spine_01", "spine_02"])
	var upper_c := _side_sum(B, ["neck_01", "head"])
	ok(lower_c * upper_c > 0.0 or absf(lower_c) < 0.5, "2a the C bends one way: lower spine side %.1f, upper %.1f deg" % [lower_c, upper_c])
	var bend_c := _side_sum(B, ["spine_01", "spine_02", "spine_03"])
	ok(absf(bend_c) > 0.5, "2b the C bends the spine (sum of spine side angles %.1f deg)" % bend_c)
	var arm_same := true
	for j in _arm_joints():
		if not ((B.ang[j] as Vector3) == arms[j]):
			arm_same = false
	ok(arm_same, "3 the arms are bit-identical to before the stroke")
	var lim_err := _in_limits(B)
	ok(lim_err == "", "4 no joint past its limits %s" % lim_err)
	ok(n1 - n0 == 1, "5a one stroke = one undo step (undo size %d -> %d)" % [n0, n1])
	var c_ang := {}
	for j in Body.ORDER:
		c_ang[j] = B.ang[j]
	m._undo()
	var back := true
	for j in Body.ORDER:
		if not (B.ang[j] == (s_start["ang"] as Dictionary)[j]):
			back = false
	ok(back, "5b Ctrl+Z puts every joint back exactly as it was before the stroke")
	# 2: the S, the same stroke with one full wave (sin(2 pi (s - 0.75))): the lower spine bows one way, the upper the other
	var s_world := []
	for i in 61:
		var u := float(i) / 60.0
		s_world.append(ank + (hc_t - ank) * u + right * (0.05 * sin(2.0 * PI * (u - 0.75))))
	m._loa_apply(_screen(cam, s_world), false)
	var lower_s := _side_sum(B, ["spine_01", "spine_02"])
	var upper_s := _side_sum(B, ["neck_01", "head"])
	print("     S: lower spine side %.1f deg, upper %.1f deg; worst %.1f mm" % [lower_s, upper_s, float(loa.last.get("worst", -1.0)) * 1000.0])
	ok(lower_s * upper_s < 0.0 and absf(lower_s) > 0.5 and absf(upper_s) > 0.5, "2c the S: the lower spine and the upper spine bend opposite ways (%.1f vs %.1f deg)" % [lower_s, upper_s])
	m._undo()
	# 6: Shift mirrors the lean of the C
	m._loa_apply(c_screen, true)
	var bend_m := _side_sum(B, ["spine_01", "spine_02", "spine_03"])
	ok(bend_c * bend_m < 0.0, "6 Shift mirrors the C's lean: spine side %.1f deg, mirrored %.1f deg" % [bend_c, bend_m])
	var arm_same2 := true
	for j in _arm_joints():
		if not ((B.ang[j] as Vector3) == arms[j]):
			arm_same2 = false
	ok(arm_same2 and _in_limits(B) == "", "3b the mirrored stroke leaves the arms and the limits alone too")
	m._undo()
	# 7: the overlay with the C drawn; the picture
	m._loa_apply(c_screen, false)
	loa.on = true
	m._refresh()
	var cl: Array = LineOfAction.current_line(B)
	ok(cl.size() == 8, "7a the current line of action has 8 points (head, neck, spine, pelvis, knee, ankle)")
	for _k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "user://line_of_action.png"
	var err := img.save_png(path)
	ok(err == OK, "7b screenshot of the C pose with its line saved to %s (%s)" % [ProjectSettings.globalize_path(path), error_string(err)])
	print("RESULT %s fails" % fails)
	quit(fails)
