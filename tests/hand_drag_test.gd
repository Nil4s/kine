## godot --path . -s tests/hand_drag_test.gd     (GATES M5; needs a window)
## Dragging a hand / foot in the view ("PULLING": the limb follows by IK). The mouse path is scripted through the real
## drag function: out past arm's length and back to where it began. Measured: how far the wrist ends from where the
## mouse put it (the cursor, in the camera's plane), the worst lag on the way, joint limits held, and Ctrl+Z.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var mpp: float = 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / m.get_viewport().get_visible_rect().size.y
	for part in ["hand_r", "hand_l", "foot_r"]:
		m.B.from_dict(m.B.to_dict())   # same pose each time: the body as it started
		m._push_undo()
		m.sel = part
		m.dragging = "joint"
		m._grab = Vector3(NAN, NAN, NAN)   # as a mouse press does
		var start: Vector3 = m.B.P[part]
		var cursor := start   # where the mouse says the wrist should be (the camera's plane)
		var worst := 0.0
		var steps := 60
		var path := []
		# out 0.9 m to the side (past reach for an arm), then straight back: 30 steps out, 30 back
		for k in steps:
			var px := (1.0 if k < steps / 2 else -1.0) * 0.9 / mpp / (steps / 2)
			path.append(Vector2(px, -px * 0.3))
		for rel in path:
			m._drag_joint(rel, false, false, false)
			cursor += m.cam.global_basis.x * rel.x * mpp - m.cam.global_basis.y * rel.y * mpp
			worst = maxf(worst, (m.B.P[part] as Vector3).distance_to(cursor))
		var back: float = (m.B.P[part] as Vector3).distance_to(start)
		var lim := 0
		for j in Body.ORDER:
			var v: Vector3 = m.B.ang[j]
			if m.B.clamp_ang(j, v).distance_to(v) > 0.01:
				lim += 1
		print("     %s: mouse out 0.9 m and back to the start; the %s ends %.0f mm from where the mouse is; worst lag on the way %.0f mm; joints past a limit: %d" % [part, "wrist" if part.begins_with("hand") else "ankle", back * 1000.0, worst * 1000.0, lim])
		ok(back < 0.02, "%s: mouse back at the start -> the %s is back too (%.0f mm off; bar 20)" % [part, "wrist" if part.begins_with("hand") else "ankle", back * 1000.0])
		ok(lim == 0, "  no joint past its limit")
		var p0: Vector3 = start
		m._undo()
		ok((m.B.P[part] as Vector3).distance_to(p0) < 1e-4, "  Ctrl+Z: the %s back where it was" % part)
		m.dragging = ""
	print("HAND DRAG %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
