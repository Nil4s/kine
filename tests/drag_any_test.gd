## godot --path . -s tests/drag_any_test.gd     (ROADMAP 41; needs a window)
## A plain left drag on ANY part does the natural thing, with no axis or mode picked. Scripted through main's own input
## path (a press, 24 mouse moves, a release, as events into _unhandled_input) on six part types. BARS (stated before
## measuring):
##   1. the press picks the part (m.sel == the part)
##   2. the dragged handle ends within 2 cm of a REACHABLE target (the target is made by turning the body itself by
##      angles inside its limits, so it is reachable by construction; the mouse is dragged to where that point shows)
##   3. no joint is past its limit afterwards (clamp_ang changes nothing by more than 0.01 deg)
##   4. pelvis drag: both ankles within 1 mm of where they were, and the body really moved (> 2 cm)
##   5. exactly one undo step: Ctrl+Z restores the whole body state, and the undo stack grew by exactly 1
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _ev_btn(pos: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	return e


func _ev_move(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


## a screen point near `at` where a press picks `part` (the middle of a hip is under the thighs; a wrist under the forearm)
func _find(m: Node, part: String, at: Vector2) -> Vector2:
	for r in [0, 6, 12, 18, 24, 32, 40]:
		for k in 16:
			var p: Vector2 = at + Vector2.from_angle(TAU * k / 16.0) * r
			if m._pick(p) == part:
				return p
	return at


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var B: Body = m.B
	var base: Dictionary = B.state()
	# part -> how the reachable target is made (joint -> angle change) ; hand_r is IK: target = a plane move
	var cases := [
		{"part": "head", "turn": {"neck_01": Vector3(0, 6, 0), "head": Vector3(0, 8, 0)}},
		{"part": "spine_02", "turn": {"spine_01": Vector3(8, 0, 0), "spine_02": Vector3(8, 0, 0), "spine_03": Vector3(8, 0, 0)}, "yaw": 90.0},   # a forward bend seen from the side: in the view plane, not along the view depth
		{"part": "upperarm_r", "turn": {"upperarm_r": Vector3(0, 40, 0)}, "swing": 1.0},
		{"part": "calf_r", "turn": {"calf_r": Vector3(22, 0, 0)}, "yaw": 90.0},   # a knee bends in the side view's plane
		{"part": "pelvis", "move": Vector3(0.05, -0.04, 0.0)},
		{"part": "hand_r", "move": Vector3(0.12, 0.05, 0.0)},
	]
	for c in cases:
		var part: String = c["part"]
		m.yaw = 0.0   # the front view...
		if c.has("yaw"):
			m.yaw = float(c["yaw"])   # ...or the side view for a hinge
		m._cam()
		B.set_state(base)
		B.fk()
		m._refresh()
		await process_frame
		var cam: Camera3D = m.cam
		# the handle the press will take: the middle of the part's capsule
		var cp: Array = B.cap(part)
		var press_at := _find(m, part, cam.unproject_position(((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5))
		var stack0: int = m.undo.size()
		var state0: Dictionary = B.state()
		m._unhandled_input(_ev_btn(press_at, true))
		ok(m.sel == part, "%s: the press picks it (picked %s)" % [part, m.sel])
		if m.sel != part:
			m._unhandled_input(_ev_btn(press_at, false))
			continue
		# the target point, made reachable
		var start_h: Vector3
		var target: Vector3
		var track := []   # the screen track the mouse follows (empty = a straight line)
		var ankles := {}
		for f in ["foot_l", "foot_r"]:
			ankles[f] = B.P[f]
		if part == "hand_r":
			start_h = B.P[part]
			target = start_h + (cam.global_basis.x * (c["move"] as Vector3).x + cam.global_basis.y * (c["move"] as Vector3).y)
		elif part == "pelvis":
			start_h = PartDrag.handle(B, m._pd)
			target = start_h + (cam.global_basis.x * (c["move"] as Vector3).x + cam.global_basis.y * (c["move"] as Vector3).y)
		else:
			start_h = PartDrag.handle(B, m._pd)
			var keep: Dictionary = B.state()
			var grab_px: Vector2 = press_at - cam.unproject_position(start_h)   # the mouse took the part off its centre line
			var base_ang := {}
			for j in c["turn"]:
				base_ang[j] = B.ang[j]
			# the track of the handle as the body itself turns into the target pose (what a hand would drag along)
			for k in range(1, 25):
				for j in c["turn"]:
					B.set_ang(j, (base_ang[j] as Vector3) + (c["turn"][j] as Vector3) * (float(k) / 24.0))
				B.fk()
				if part.begins_with("upperarm"):
					B.shoulder_follow(part.right(2))   # the collarbone goes with a raised arm, as it does in the drag
				track.append(cam.unproject_position(PartDrag.handle(B, m._pd)) + grab_px)
			target = PartDrag.handle(B, m._pd)
			B.set_state(keep)
			B.fk()
		print("     %s: start %s target %s t=%.2f ang0 %s" % [part, start_h, target, float(m._pd.get("t", 0.0)), B.ang.get(part)])
		print("     %s: handle %.0f mm from where the mouse is going" % [part, start_h.distance_to(target) * 1000.0])
		# the mouse: press_at -> where the target shows, 24 moves
		var end_at: Vector2 = cam.unproject_position(target)
		if not track.is_empty():
			end_at = track[23]
		if part == "hand_r" or part == "pelvis":
			end_at = press_at + (cam.unproject_position(target) - cam.unproject_position(start_h))
		var prev := press_at
		var worst_foot := 0.0
		for k in 24:
			var pos := press_at.lerp(end_at, float(k + 1) / 24.0) if track.is_empty() else (track[k] as Vector2)
			m._unhandled_input(_ev_move(pos, pos - prev))
			prev = pos
			if part == "pelvis":
				for f in ankles:
					worst_foot = maxf(worst_foot, ((B.P[f] as Vector3) - (ankles[f] as Vector3)).length())
		m._unhandled_input(_ev_btn(end_at, false))
		var got: Vector3 = B.P[part] if part == "hand_r" else PartDrag.handle(B, m._pd)
		var err := got.distance_to(target)
		print("     angles now: ", B.ang[part], "  last stop: ", B.last_stop)
		if part == "pelvis":
			ok(worst_foot < 0.001, "pelvis: feet stayed within 1 mm all the way (worst %.2f mm)" % (worst_foot * 1000.0))
			ok(got.distance_to(start_h) > 0.02, "pelvis: the body really moved (%.0f mm)" % (got.distance_to(start_h) * 1000.0))
		ok(err < 0.02, "%s: ends %.1f mm from its reachable target (bar 20 mm)" % [part, err * 1000.0])
		var past := 0
		for j in Body.ORDER:
			var v: Vector3 = B.ang[j]
			if B.clamp_ang(j, v).distance_to(v) > 0.01:
				past += 1
		ok(past == 0, "%s: joints past a limit: %d" % [part, past])
		ok(m.dragging == "", "%s: the release ends the drag" % part)
		if stack0 >= 0:
			ok(m.undo.size() == stack0 + 1, "%s: one undo step (stack %d -> %d)" % [part, stack0, m.undo.size()])
		m._undo()
		var back := B.state()
		ok(str(back) == str(state0), "%s: Ctrl+Z restores the whole body state" % part)
	print("DRAG ANY %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
