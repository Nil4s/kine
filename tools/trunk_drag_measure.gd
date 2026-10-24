## godot --path . -s tools/trunk_drag_measure.gd     (dev: how much the TRUNK moves when only a limb is dragged, Nick 10-23)
## main's own input path, as tests/drag_any_test.gd drives it (a press, 24 mouse moves, a release into _unhandled_input).
## Cases: the right foot dragged up to kick height (hip height, 45 cm in front), the right hand forward to full reach, each
## with smart drag and keep balance off / on in the four combinations (the app's default is both ON; a test starts both off).
## Printed per case: the trunk's largest change from the press (pitch, roll: pelvis -> neck_01 in the hips' frame), the spine's
## summed bend / side change, the pelvis's own angle change, and which joints outside the dragged limb moved over 1 deg.
extends SceneTree


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
	var limb := {"foot_r": ["thigh_r", "calf_r", "foot_r", "ball_r"], "hand_r": ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]}
	for part in ["foot_r", "hand_r"]:
		for mode in [[false, false], [true, false], [false, true], [true, true]]:
			m.smart_drag = mode[0]
			m.keep_balance = mode[1]
			m.yaw = -90.0   # the right side view: forward and up are in the view plane, the right limbs nearest
			m._cam()
			B.set_state(base)
			B.fk()
			m._refresh()
			await process_frame
			var cam: Camera3D = m.cam
			var start: Vector3 = B.P[part]
			var target: Vector3
			if part == "foot_r":
				target = Vector3(start.x, (B.P["thigh_r"] as Vector3).y, (B.P["pelvis"] as Vector3).z + 0.45)
			else:
				var sh: Vector3 = B.P["upperarm_r"]
				target = Vector3(start.x, sh.y, sh.z + 0.62)
			var cp: Array = B.cap(part)
			var press_at := _find(m, part, cam.unproject_position(((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5))
			m._unhandled_input(_ev_btn(press_at, true))
			if m.sel != part:
				print("%s: the press picked %s" % [part, m.sel])
				m._unhandled_input(_ev_btn(press_at, false))
				continue
			var a0 := TrunkLean.angles(B)
			var ang0: Dictionary = B.ang.duplicate()
			var end_at: Vector2 = press_at + (cam.unproject_position(target) - cam.unproject_position(start))
			var prev := press_at
			var worst := {"pitch": 0.0, "roll": 0.0, "bend": 0.0, "side": 0.0}
			for k in 24:
				var pos := press_at.lerp(end_at, float(k + 1) / 24.0)
				m._unhandled_input(_ev_move(pos, pos - prev))
				prev = pos
				var a := TrunkLean.angles(B)
				for q in worst:
					if absf(a[q] - a0[q]) > absf(worst[q]):
						worst[q] = a[q] - a0[q]
			m._unhandled_input(_ev_btn(end_at, false))
			var moved := []
			for j in Body.ORDER:
				if j in limb[part]:
					continue
				var d: float = ((B.ang[j] as Vector3) - (ang0[j] as Vector3)).length()
				if d > 1.0:
					moved.append("%s %.0f" % [j, d])
			var pel: Vector3 = (B.ang["pelvis"] as Vector3) - (ang0["pelvis"] as Vector3)
			print("%s smart=%s balance=%s: tip %.0f cm from target (at %s, target %s); trunk pitch %+.1f roll %+.1f, spine bend %+.1f side %+.1f, pelvis %s, offset %.1f cm; moved: %s" % [
				part, mode[0], mode[1], ((B.P[part] as Vector3) - target).length() * 100.0, (B.P[part] as Vector3).snapped(Vector3.ONE * 0.01), target.snapped(Vector3.ONE * 0.01), worst["pitch"], worst["roll"], worst["bend"], worst["side"],
				pel.snapped(Vector3.ONE * 0.1), (B.offset - (base["offset"] if base.has("offset") else B.offset)).length() * 100.0, ", ".join(moved)])
			m._undo()
	quit(0)
