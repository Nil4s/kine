## godot --path . -s tests/i12_test.gd     (ROADMAP I12, smart drag; needs a window)
## Dragging one joint moves the rest of the body along the co-variation learned from Nick's poses. BARS (stated before measuring):
##   A  SYNTHETIC LIBRARY (40 poses: the right shoulder pulled back by t * 40 deg always comes with pelvis twist +20 * t deg;
##      three unrelated joints wobble). Model: k components explain >= 85 % of the variance (k reported).
##   1  unit: shoulder at t = 0.8, follow 0.6 -> the pelvis twist moves 20 * 0.8 * 0.6 = 9.6 deg, +-3
##   2  through the mouse (main's own input path): the dragged upper arm turns by d; the pelvis twist moves by
##      20 * follow * (d . U / |U|^2), +-3 deg, and by at least 3 deg (the drag exercised the link)
##   3  follow 0, Alt at the press, smart drag switched off: the final pose is identical to the old drag, string for string
##   4  feet stay within 1 cm of where they were at every mouse move
##   5  no joint is past its limit afterwards
##   6  ONE undo step; Ctrl+Z restores the whole body state exactly
##   7  frame: the smart part of a mouse move (two applies) <= 8 ms, the worst of the drag
##   8  a library with NO link (shoulder and pelvis independent) moves the pelvis < 1.5 deg
##   B  THE REAL LIBRARY (poses/ + scenes/, read only; the model cached in the test's own user:// file): k and the explained
##      share are reported, k's share >= 85 %; the cache is read back the second time (same k); a fist pulled back moves the
##      hips (> 0.5 deg: it is a real model), feet within 1 cm, and the screenshot has the old one-joint result as a ghost
##      drawn where the body is (PLACEMENT: the ghost's spot is the body's pelvis column, inside the view)
extends SceneTree

const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _ev_btn(pos: Vector2, down: bool, alt := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	e.alt_pressed = alt
	return e


func _ev_move(pos: Vector2, rel: Vector2, alt := false) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.alt_pressed = alt
	return e


func _find(m: Node, part: String, at: Vector2) -> Vector2:
	for r in [0, 6, 12, 18, 24, 32, 40]:
		for k in 16:
			var p: Vector2 = at + Vector2.from_angle(TAU * k / 16.0) * r
			if m._pick(p) == part:
				return p
	return at


## the synthetic library: shoulder pull t*U comes with pelvis twist +20*t (link = false: the pelvis is independent)
func _synth(B: Body, U: Vector3, link: bool) -> Array:
	var base := NextPose.full_of_body(B)
	var oi := {}
	for i in Body.ORDER.size():
		oi[Body.ORDER[i]] = i
	var out := []
	for i in 40:
		var t := float(i) / 39.0
		var v := base.duplicate()
		var a: int = int(oi["upperarm_r"]) * 3
		for c in 3:
			v[a + c] += t * U[c]
		var pt := float(i * 17 % 40) / 39.0   # the unlinked pelvis twist: another order
		v[int(oi["pelvis"]) * 3 + 2] += 20.0 * (t if link else pt)
		v[int(oi["spine_02"]) * 3] += 4.0 * sin(float(i) * 2.3)
		v[int(oi["neck_01"]) * 3 + 2] += 5.0 * cos(float(i) * 1.1)
		v[int(oi["head"]) * 3 + 1] += 3.0 * sin(float(i) * 0.7 + 1.0)
		out.append(v)
	return out


func _pelvis_twist(B: Body) -> float:
	return (B.ang["pelvis"] as Vector3).z


## a drag by main's input path: press at `from`, 16 moves to `to`, release. Returns the worst smart ms and the worst foot move
func _drag(m: Node, from: Vector2, to: Vector2, alt := false) -> Dictionary:
	var B: Body = m.B
	var feet := {}
	for f in ["foot_l", "foot_r"]:
		feet[f] = B.P[f]
	var worst_ms := 0.0
	var worst_foot := 0.0
	m._unhandled_input(_ev_btn(from, true, alt))
	var prev := from
	for k in 16:
		var pos := from.lerp(to, float(k + 1) / 16.0)
		m._unhandled_input(_ev_move(pos, pos - prev, alt))
		prev = pos
		worst_ms = maxf(worst_ms, m.sd.last_ms * 2.0)
		for f in feet:
			worst_foot = maxf(worst_foot, ((B.P[f] as Vector3) - (feet[f] as Vector3)).length())
	m._unhandled_input(_ev_btn(to, false, alt))
	return {"ms": worst_ms, "foot": worst_foot}


func _past(B: Body) -> int:
	var n := 0
	for j in Body.ORDER:
		var v: Vector3 = B.ang[j]
		if B.clamp_ang(j, v).distance_to(v) > 0.01:
			n += 1
	return n


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var B: Body = m.B
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/lib/guard_bat.json")))   # a stance with the feet apart (the rest pose has its legs touching)
	B.wep_on = false
	B.fk()
	m._refresh()
	var base: Dictionary = B.state()
	var U := Vector3(0, 40, 0)
	var sd: SmartDrag = m.sd
	# ---- A: the synthetic library ----
	var k := sd.fit(_synth(B, U, true))
	print("     synthetic: %d samples, k = %d, explained %.1f %%, fit %.0f ms" % [sd.n, k, sd.explained() * 100.0, sd.last_ms])
	ok(k >= 1 and sd.explained() >= 0.85, "A model: k = %d explains %.1f %% (bar >= 85 %%)" % [k, sd.explained() * 100.0])
	# 1: unit
	B.set_state(base)
	B.fk()
	var st := sd.begin(B, "upperarm_r")
	var t0 := _pelvis_twist(B)
	B.ang["upperarm_r"] = (B.ang["upperarm_r"] as Vector3) + U * 0.8
	B.fk()
	sd.apply(B, st, 0.6)
	var moved := _pelvis_twist(B) - t0
	ok(absf(moved - 9.6) <= 3.0, "1 unit: shoulder pulled 0.8 of its range, follow 0.6 -> pelvis twist %+.2f deg (expect 9.60 +-3)" % moved)
	B.set_state(base)
	B.fk()
	# through the mouse
	m.smart_drag = true
	m.smart_follow = 0.6
	m.yaw = 0.0
	m._cam()
	m._refresh()
	await process_frame
	var cam: Camera3D = m.cam
	var cp: Array = B.cap("upperarm_r")
	var press_at := _find(m, "upperarm_r", cam.unproject_position(((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5))
	m._unhandled_input(_ev_btn(press_at, true))
	var pd: Dictionary = m._pd
	var start_h := PartDrag.handle(B, pd)
	var grab_px: Vector2 = press_at - cam.unproject_position(start_h)
	m._unhandled_input(_ev_btn(press_at, false))
	m._undo()
	B.set_state(base)
	B.fk()
	m._refresh()
	var keep: Dictionary = B.state()
	B.set_ang("upperarm_r", (B.ang["upperarm_r"] as Vector3) + U)
	B.fk()
	B.shoulder_follow("_r")
	var end_at: Vector2 = cam.unproject_position(PartDrag.handle(B, pd)) + grab_px
	B.set_state(keep)
	B.fk()
	m._refresh()
	await process_frame
	var stack0: int = m.undo.size()
	var state0: Dictionary = B.state()
	var r_smart := _drag(m, press_at, end_at)
	var d: Vector3 = (B.ang["upperarm_r"] as Vector3) - (state0["ang"]["upperarm_r"] as Vector3)
	var want := 20.0 * 0.6 * d.dot(U) / U.length_squared()
	var got := _pelvis_twist(B) - (state0["ang"]["pelvis"] as Vector3).z
	print("     mouse drag: upper arm turned %s, pelvis twist moved %+.2f (expect %+.2f), steps %d" % [d, got, want, m.undo.size() - stack0])
	ok(absf(want) >= 3.0, "2 the drag exercised the link (expected hip move %+.1f deg)" % want)
	ok(absf(got - want) <= 3.0, "2 pelvis twist %+.2f vs 20*follow*t = %+.2f (+-3)" % [got, want])
	var after_smart: String = str(B.ang)
	ok(r_smart["foot"] <= 0.01, "4 feet within 1 cm at every move (worst %.2f mm)" % (float(r_smart["foot"]) * 1000.0))
	ok(_past(B) == 0, "5 joints past a limit: %d" % _past(B))
	ok(m.undo.size() == stack0 + 1, "6 one undo step (%d -> %d)" % [stack0, m.undo.size()])
	ok(float(r_smart["ms"]) <= 8.0, "7 smart part of a move: worst %.2f ms (bar 8)" % float(r_smart["ms"]))
	m._undo()
	ok(str(B.state()) == str(state0), "6 Ctrl+Z restores the whole body state exactly")
	# 3: the old drag, three ways
	var olds := {}
	for mode in ["off", "follow0", "alt"]:
		B.set_state(base)
		B.fk()
		m._refresh()
		await process_frame
		m.smart_drag = mode != "off"
		m.smart_follow = 0.0 if mode == "follow0" else 0.6
		_drag(m, press_at, end_at, mode == "alt")
		olds[mode] = str(B.ang)
		m._undo()
	ok(olds["off"] == olds["follow0"], "3 follow 0 == the old drag exactly")
	ok(olds["off"] == olds["alt"], "3 Alt+drag == the old drag exactly")
	ok(olds["off"] != after_smart, "3 (control) the smart drag really differs from the old one")
	# 8: no link
	sd.fit(_synth(B, U, false))
	B.set_state(base)
	B.fk()
	m.smart_drag = true
	m.smart_follow = 0.6
	m._refresh()
	await process_frame
	_drag(m, press_at, end_at)
	var free := _pelvis_twist(B) - (state0["ang"]["pelvis"] as Vector3).z
	ok(absf(free) < 1.5, "8 a library with no link moves the pelvis %+.2f deg (bar < 1.5)" % free)
	m._undo()
	# ---- B: the real library ----
	sd.comps = []
	sd.sig = ""
	var t1 := Time.get_ticks_msec()
	var built := sd.refresh()
	var ms1 := Time.get_ticks_msec() - t1
	var k1 := sd.k()
	print("     REAL library: %d poses+cards, k = %d, explained %.1f %%, built in %d ms (from cache %s)" % [sd.n, k1, sd.explained() * 100.0, ms1, sd.from_cache])
	ok(built and sd.explained() >= 0.85, "B real model: k = %d explains %.1f %% (bar >= 85 %%)" % [k1, sd.explained() * 100.0])
	var sd2 := SmartDrag.new()
	sd2.cache_path = sd.cache_path
	var t2 := Time.get_ticks_msec()
	sd2.refresh()
	print("     second read: k = %d, from cache %s, %d ms" % [sd2.k(), sd2.from_cache, Time.get_ticks_msec() - t2])
	ok(sd2.from_cache and sd2.k() == k1, "B the cache is read back (k %d)" % sd2.k())
	# a fist pulled back, in a stance from the library
	var pose: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://poses/lib/guard_bat.json"))
	B.set_state(base)
	B.from_dict(pose)
	B.wep_on = false
	B.fk()
	m.yaw = 90.0
	m._cam()
	m._refresh()
	await process_frame
	var s_b: Dictionary = B.state()   # (the guard stance again)
	var hp: Vector3 = B.P["hand_r"]
	var hand_px := cam.unproject_position(hp)
	var press2 := _find(m, "hand_r", hand_px)
	var pull := cam.unproject_position(hp + cam.global_basis.x * 0.30 * (1.0 if cam.global_basis.x.z > 0.0 else -1.0))
	var back_dir := (pull - hand_px)
	var end2 := press2 + back_dir
	m.smart_drag = false
	_drag(m, press2, end2)
	var old_body := Body.new()
	old_body.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	old_body.set_state(B.state())
	old_body.fk()
	var old_pelvis := _pelvis_twist(B)
	var old_spine: Vector3 = B.ang["spine_02"]
	m._undo()
	B.set_state(s_b)
	B.fk()
	m._refresh()
	await process_frame
	m.smart_drag = true
	var r2 := _drag(m, press2, end2)
	var dh := absf(_pelvis_twist(B) - old_pelvis)
	var ds := ((B.ang["spine_02"] as Vector3) - old_spine).length()
	print("     fist pulled back: pelvis twist old %+.2f new %+.2f, spine_02 moved %.2f deg, feet worst %.2f mm, smart %.2f ms" % [old_pelvis, _pelvis_twist(B), ds, float(r2["foot"]) * 1000.0, r2["ms"]])
	ok(dh + ds > 0.5, "B the real model moves the body along with the fist (pelvis %.2f + spine %.2f deg more than the old drag)" % [dh, ds])
	ok(float(r2["foot"]) <= 0.01, "B feet within 1 cm (worst %.2f mm)" % (float(r2["foot"]) * 1000.0))
	ok(_past(B) == 0, "B joints past a limit: %d" % _past(B))
	# the ghost of the old result, drawn on the body
	var at: Vector3 = B.P["pelvis"]
	m.ov.sugg_show([{"body": old_body, "col": Color(1.0, 0.65, 0.2), "sel": false, "text": "old one-joint drag"}], at, cam.global_basis.x, 1.0, 0.0, 0.0)
	m._refresh()
	await process_frame
	await process_frame
	var spot: Vector3 = m.ov.sugg_spot(0)
	var sp := cam.unproject_position(spot)
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	ok(spot != Vector3.INF and Vector2(spot.x - at.x, spot.z - at.z).length() < 0.02 and sp.x > 0 and sp.x < vs.x and sp.y > 0 and sp.y < vs.y,
		"B PLACEMENT: the ghost of the old result stands on the body's own column (%.1f cm off), inside the view" % (Vector2(spot.x - at.x, spot.z - at.z).length() * 100.0))
	var img: Image = m.get_viewport().get_texture().get_image()
	img.save_png(TMP + "i12.png")
	print("     screenshot saved: ", TMP + "i12.png")
	m._undo()
	print("I12 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
