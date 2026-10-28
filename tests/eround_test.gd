extends SceneTree
## godot --path . --position 4000,4000 -s tests/eround_test.gd     (EROUND: Easy Part Round the edges is bounded: a part of 25+ steps built by real clicks (the eperf cycle), then one Round press; scripts/easy_part.gd _round; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from the start screen. Build: Draw shape, Pull it up, Cut a hole, Mirror that, Repeat it, then Draw, Pull, Hole again until the record has 25 steps (or more). Then Round the edges (timed from the release, to two frames after).
## Bars (1 and later FAILED on the old code: the Round press took many seconds at this size; the old run is in the report):
##   1 BUILT   the part has 25 or more steps and no failed step
##   2 PRESS   the Round press takes less than 2 s
##   3 REPLAY  the part, replayed after the press, has no failed step; the round is one new fillet step
##   4 UNDO    the press is ONE undo step
## Writes C:/Temp/claude/eround/round.png (the rounded part from the front) when it runs.
const SHOT := "C:/Temp/claude/eround"
const DIRT := "user://eround_test"
const MIN_STEPS := 25
const BUDGET_MS := 2000.0

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


## a click on a control: the press and the release are real events; the commit is the release, timed
## returns the usec from the release to two frames after it
func press(c: Control) -> int:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	var t0 := Time.get_ticks_usec()
	await ev_mouse(p, false)
	await process_frame
	await process_frame
	return Time.get_ticks_usec() - t0


## a drag on the floor from world a to world b (metres); not timed
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
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	await fresh()

	# BUILD: the eperf cycle (draw, pull, hole; mirror and repeat once) to 25 steps
	var cyc := 0
	var guard := 0
	await press(ep().make_btns["draw"])
	await draw_floor(Vector3(-0.12, 0.0, -0.06), Vector3(-0.08, 0.0, -0.02))
	await press(ep().make_btns["pull"])
	await press(ep().make_btns["hole"])
	await press(ep().make_btns["mirror"])
	await press(ep().make_btns["repeat"])
	while nsteps() < MIN_STEPS and guard < 20:
		guard += 1
		var x := -0.12 + 0.06 * float(cyc % 5)
		var z := -0.06 + 0.08 * float(cyc % 3)
		cyc += 1
		await press(ep().make_btns["draw"])
		await draw_floor(Vector3(x, 0.0, z), Vector3(x + 0.04, 0.0, z + 0.04))
		await press(ep().make_btns["pull"])
		await press(ep().make_btns["hole"])
	var rec: Dictionary = ep()._rec()
	var built := Part.replay(rec)
	ok(nsteps() >= MIN_STEPS and (built["errors"] as Dictionary).is_empty(), "1 BUILT %d steps, %d failed" % [nsteps(), (built["errors"] as Dictionary).size()])
	print("built: %d steps, %d bodies, %d edges" % [nsteps(), built["bodies"], (Part.replay(rec, -1, {"edges": true})["edges"] as Array).size()])

	# ROUND: one press, timed
	var n0 := nsteps()
	var u0: int = m.undo.size()
	var us := await press(ep().make_btns["round"])
	await idle(3)
	var ms := us / 1000.0
	print("round press ms %.1f  steps %d -> %d" % [ms, n0, nsteps()])
	ok(ms < BUDGET_MS, "2 PRESS the Round press took %.0f ms (under %.0f)" % [ms, BUDGET_MS])
	var after := Part.replay(ep()._rec())
	var newest := String((ep()._rec()["features"] as Array).back()["t"]) if nsteps() > 0 else ""
	ok((after["errors"] as Dictionary).is_empty() and nsteps() == n0 + 1 and newest == "fillet",
		"3 REPLAY no failed step (%d errors), the round is one fillet step (%d -> %d, newest %s)" % [(after["errors"] as Dictionary).size(), n0, nsteps(), newest])
	ok(m.undo.size() == u0 + 1, "4 UNDO the press is one undo step (%d -> %d)" % [u0, m.undo.size()])
	DirAccess.make_dir_recursive_absolute(SHOT)
	m.pitch = -25.0
	m._cam()
	await idle(30)
	root.get_texture().get_image().save_png("%s/round.png" % SHOT)
	print("eround: %d fail" % fails)
	quit(1 if fails > 0 else 0)
