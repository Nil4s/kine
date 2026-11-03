extends SceneTree
## godot --path . --position 4000,4000 -s tests/p068hingebycli_test.gd     (p068 Friday 68: Hinge by click on the Easy Part page: pick the door edge, then the frame edge; the hinge is placed and the door can swing; scripts/easy_part.gd edge chip + scripts/easy_part_hinge.gd; needs the CAD DLL and a window)
## A beginner walk with real clicks and real mouse moves at 1280 x 720 from the start screen. Build: Draw shape, Pull it up (the frame), then a second shape apart from the first, Pull it up (the door).
## Then hover the door's edge (the chip shows Hinge), click Hinge; hover the frame's edge (the chip shows Hinge), click Hinge. Everything is measured from the built part (Part.replay, Part.hinge_sweep), never from the code's variables.
## Bars (all FAILED on the code before this item: no Hinge chip existed; the run is in the report):
##   1 BUILT   two separate pieces, no failed step
##   2 DOOR    hovering the door's edge shows a Hinge chip; clicking it names the next step (the frame edge)
##   3 WRONG   a second edge on the door's own piece is refused: nothing is added, the words name the other piece
##   4 PLACED  the frame edge's Hinge click adds ONE hinge step; the replay has no failed step; the pieces are still two
##   5 PIVOT   the hinge's pivot sits on the frame edge's start point (within 0.05 mm) and its axis runs along the frame edge (within 0.5 deg)
##   6 BODY    the hinge turns the door's piece (the body the door edge is on)
##   7 SWING   Part.hinge_sweep on the hinge reports ok with frames, and the door swings about it (the sweep's frames > 0)
##   8 UNDO    the hinge placement is ONE undo step
## Writes C:/Temp/claude/p068hingebycli/hinge.png (the hinged part from the front) when it runs.
const SHOT := "C:/Temp/claude/p068hingebycli"
const DIRT := "user://p068hingebycli_test"
const MM := 0.001

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## a click on a control: a move onto it, then the press and the release (real events)
func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await process_frame
	await process_frame


## a drag on the floor from world a to world b (metres)
func draw_floor(a: Vector3, b: Vector3) -> void:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
	await ev_mouse(pb, false)
	await idle(3)


func fresh() -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)


func nsteps() -> int:
	return (ep()._rec().get("features", []) as Array).size()


## the chip's Hinge button, when it is up and shown (null otherwise)
func hinge_chip() -> Button:
	var b := m.find_child("easypart_edge_hinge", true, false) as Button
	if b == null or not b.is_visible_in_tree():
		return null
	return b


## the edge of body `body` that is longest and in front of the camera (edges from the built part, metres)
func longest_edge(body: int) -> Dictionary:
	var best := {}
	for e in Part.replay(ep()._rec(), -1, {"edges": true})["edges"]:
		if int(e["body"]) != body or bool(e.get("seam", false)):
			continue
		if m.cam.is_position_behind(e["a"]) or m.cam.is_position_behind(e["b"]):
			continue
		if best.is_empty() or float(e["len"]) > float(best["len"]):
			best = e
	return best


## hover the middle of an edge (screen px) and wait a frame for the chip
## a point on the edge that no panel covers (the Tilt / Draft panel sits over the middle of the view after a pull)
func clear_point(e: Dictionary) -> Vector2:
	for t in [0.5, 0.3, 0.7, 0.2, 0.8, 0.1, 0.9]:
		var p := scr((e["a"] as Vector3).lerp(e["b"] as Vector3, t))
		var covered := false
		for c in m.get_tree().root.find_children("*", "Control", true, false):
			var cc := c as Control
			if cc.is_visible_in_tree() and cc.mouse_filter != Control.MOUSE_FILTER_IGNORE and cc.get_global_rect().has_point(p):
				covered = true
		if not covered:
			return p
	return scr(e["c"])


func hover_edge(e: Dictionary) -> void:
	var at := clear_point(e)
	var from := at + Vector2(0.0, 40.0)   # the pointer comes up to the edge from below, a few moves, as a hand does
	for i in range(1, 7):
		await ev_move(from.lerp(at, i / 6.0), false)
	await idle(3)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["building"])
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	ep().one_side = true   # P153 (a4512f9c): symmetry is on by default; this walk draws two single pieces, so it uses One side only
	ep().one_side_btn.set_pressed_no_signal(true)
	await fresh()

	# BUILD: the frame (a box on the floor, pulled up), then the door: a second piece apart from the frame, pulled up
	await press(ep().make_btns["draw"])
	await draw_floor(Vector3(-0.10, 0.0, -0.05), Vector3(0.0, 0.0, 0.05))
	await press(ep().make_btns["pull"])
	await press(ep().make_btns["draw"])
	await draw_floor(Vector3(0.05, 0.0, -0.05), Vector3(0.09, 0.0, 0.05))
	await press(ep().make_btns["pull"])
	var built := Part.replay(ep()._rec())
	ok(int(built["bodies"]) == 2 and (built["errors"] as Dictionary).is_empty(),
		"1 BUILT two separate pieces (%d bodies), %d failed steps" % [int(built["bodies"]), (built["errors"] as Dictionary).size()])
	if int(built["bodies"]) != 2:
		print("p068hingebycli: %d fail" % (fails + 1))
		quit(1)
		return

	# the door is the body whose edge is nearest the camera's right side; the frame is the other body (both from the built part)
	var door_e := longest_edge(1)
	var frame_e := longest_edge(0)
	var door_body := int(door_e["body"]) if not door_e.is_empty() else -1
	var n0 := nsteps()
	var u0: int = m.undo.size()

	# DOOR: hover the door's edge; the Hinge chip shows; the click names the next step
	await idle(120)   # navigation: let the camera finish easing after the last pull before edge points are read from it
	await hover_edge(door_e)
	var hc := hinge_chip()
	ok(hc != null, "2 DOOR the door's edge shows a Hinge chip (edge chip up: %s)" % str(hc != null))
	if hc != null:
		await press(hc)
		await idle(2)
	var say_door := String(ep().msg)
	ok(say_door.to_lower().find("frame") >= 0, "2 DOOR the door edge is picked, the words name the frame edge next: '%s'" % say_door)

	# WRONG: the door's own piece refused (a second edge of the same body)
	var door2 := longest_edge(door_body)
	var same_n := nsteps()
	await hover_edge(door2)
	var hc2 := hinge_chip()
	if hc2 != null:
		await press(hc2)
		await idle(2)
	ok(nsteps() == same_n and String(ep().msg).to_lower().find("other") >= 0,
		"3 WRONG the door's own piece is refused, nothing added (%d -> %d): '%s'" % [same_n, nsteps(), String(ep().msg)])

	# PLACED: the frame edge
	await hover_edge(frame_e)
	var hc3 := hinge_chip()
	if hc3 != null:
		await press(hc3)
		await idle(3)
	var after := Part.replay(ep()._rec())
	var newest: Dictionary = (ep()._rec()["features"] as Array).back() if nsteps() > 0 else {}
	var hid := String(newest.get("id", ""))
	ok(nsteps() == n0 + 1 and String(newest.get("t", "")) == "hinge" and (after["errors"] as Dictionary).is_empty() and int(after["bodies"]) == 2,
		"4 PLACED one hinge step (%d -> %d, newest %s), %d failed steps, %d pieces, chip up %s: '%s'" % [n0, nsteps(), String(newest.get("t", "")), (after["errors"] as Dictionary).size(), int(after["bodies"]), str(hc3 != null), String(ep().msg)])

	# PIVOT and AXIS: from the frame edge of the built part (its start point and direction), not from the hinge's own numbers
	var is_hinge := String(newest.get("t", "")) == "hinge"
	if not is_hinge:   # no hinge step yet: the bars below fail (never a script error)
		newest = {"o": [0.0, 0.0, 0.0], "axis": [0.0, 0.0, 0.0], "body": -1, "id": ""}
	var fa: Vector3 = frame_e["a"]
	var fdir: Vector3 = (frame_e["b"] as Vector3) - fa
	fdir = fdir.normalized()
	var o := Vector3(float(newest["o"][0]), float(newest["o"][1]), float(newest["o"][2])) * MM
	var ax := Vector3(float(newest["axis"][0]), float(newest["axis"][1]), float(newest["axis"][2])).normalized()
	var gap_mm := (o - fa).length() / MM
	var ang := rad_to_deg(acos(clampf(absf(ax.dot(fdir)), 0.0, 1.0)))
	ok(gap_mm < 0.05 and ang < 0.5, "5 PIVOT the pivot is %.3f mm from the frame edge's start (under 0.05), the axis is %.3f deg off the frame edge (under 0.5)" % [gap_mm, ang])

	# BODY: the hinge turns the door's piece
	ok(int(newest.get("body", -1)) == door_body and door_body >= 0,
		"6 BODY the hinge turns the door's piece (body %s, the door's body %d)" % [str(newest.get("body", -1)), door_body])

	# SWING: the door swings: Part.hinge_sweep walks the curve and reports frames
	var sw := Part.hinge_sweep(ep()._rec(), hid) if is_hinge else {"ok": false, "why": "no hinge step"}
	ok(bool(sw.get("ok", false)) and int(sw.get("frames", 0)) > 0,
		"7 SWING the door swings: hinge_sweep ok %s, %d frames (%s)" % [str(sw.get("ok", false)), int(sw.get("frames", 0)), str(sw.get("why", ""))])

	# UNDO: the placement is one undo step
	ok(m.undo.size() == u0 + 1,
		"8 UNDO the hinge placement is one undo step (undo stack %d -> %d)" % [u0, m.undo.size()])
	DirAccess.make_dir_recursive_absolute(SHOT)
	m.pitch = -25.0
	m._cam()
	await idle(30)
	root.get_texture().get_image().save_png("%s/hinge.png" % SHOT)
	print("p068hingebycli: %d fail" % fails)
	quit(1 if fails > 0 else 0)
