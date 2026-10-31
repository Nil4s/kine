extends SceneTree
## godot --path . --position 4000,4000 -s tests/p108measuregri_test.gd     (p108measuregri, Friday plan 108: the Easy Part measure grid scales its labels when zooming; scripts/easy_part_layout.gd grid labels + scripts/easy_part.gd _process; needs the CAD DLL and a window)
## A beginner walk with real clicks and real wheel notches at 1280 x 720 from the start screen: Build, Draw shape on the empty grid, then the wheel zooms in and out.
## Everything is measured from the built scene (the Label3D nodes' positions and texts, projected with the camera), never from the code's own variables.
## Bars (all FAILED on the code before this item: the floor grid had no numbers):
##   1 OPEN    the empty Easy Part grid shows its numbers (at least 5 on the X axis)
##   2 SPACE   the numbers sit 60 to 180 px apart on the screen when the grid opens (finest step that fits, measured in px)
##   3 IN      10 wheel notches in: the step gets finer (smaller number) and the numbers are still 60 to 180 px apart
##   4 OUT     6 wheel notches out from there: the step gets coarser and the numbers are still 60 to 180 px apart
##   5 WORDS   every shown number is plain words: "0", or a whole number of "cm" ("-25 cm", "50 cm")
##   6 TRUE    every X-axis number sits at its own value (its text in metres) within 0.1 mm
##   7 NOSTEP  the zooms add no build step and no undo step
##   8 LEAVE   leaving Easy Part hides every number
## Writes C:/Temp/claude/p108measuregri/grid_open.png and grid_in.png when it runs.
const SHOT := "C:/Temp/claude/p108measuregri"
const DIRT := "user://p108measuregri_test"
const MM := 0.001
const WHEEL := Vector2(330.0, 360.0)   # a point on the free view, left of the Easy panel

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_wheel(up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = WHEEL
	e.global_position = WHEEL
	root.push_input(e, true)
	await process_frame


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


## the grid's numbers on screen: the visible Label3D nodes under the camera rig, by name
func numbers() -> Array:
	var out: Array = []
	for c in m.cam.get_parent().get_children():
		if c is Label3D and String(c.name).begins_with("EasyGridLabel") and (c as Label3D).is_visible_in_tree():
			out.append(c)
	return out


## the numbers on the X axis (their Z is the axis offset), sorted by x: [{"x", "text", "node"}]
func x_axis() -> Array:
	var out: Array = []
	for l in numbers():
		var p: Vector3 = (l as Label3D).global_position
		if absf(p.z - 0.03) < 1e-4:
			out.append({"x": p.x, "text": (l as Label3D).text, "node": l})
	out.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	return out


## the screen gaps (px) between neighbouring X-axis numbers
func gaps_px() -> Array:
	var xs := x_axis()
	var out: Array = []
	for i in range(1, xs.size()):
		var a: Vector2 = m.cam.unproject_position((xs[i - 1]["node"] as Label3D).global_position)
		var b: Vector2 = m.cam.unproject_position((xs[i]["node"] as Label3D).global_position)
		out.append(a.distance_to(b))
	return out


## the smallest number on the X axis that is not 0, in metres (the step the grid is labelled with)
func step_m() -> float:
	var best := INF
	for d in x_axis():
		if absf(float(d["x"])) > 1e-6:
			best = minf(best, absf(float(d["x"])))
	return best


func gap_range() -> Vector2:
	var g := gaps_px()
	if g.is_empty():
		return Vector2(0.0, 0.0)
	var lo := INF
	var hi := -INF
	for v in g:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	return Vector2(lo, hi)


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
	await _press(ss._cards["building"])
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
	await _press(pu().part_btn)
	await idle(3)
	await _press(pu().easy_open_btn)
	await idle(60)

	# OPEN: the empty grid, framed by the app; the numbers are on
	var xs0 := x_axis()
	ok(xs0.size() >= 5, "1 OPEN the empty Easy Part grid shows %d numbers on its X axis (at least 5)" % xs0.size())
	var r0 := gap_range()
	ok(r0.x >= 60.0 and r0.y <= 180.0,
		"2 SPACE the numbers are %.0f to %.0f px apart on the screen when the grid opens (60 to 180)" % [r0.x, r0.y])
	var step_open := step_m()
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/grid_open.png" % SHOT)

	# the beginner zooms with the wheel (real wheel notches over the grid)
	var u0: int = m.undo.size()
	var n0 := (ep()._rec().get("features", []) as Array).size()
	for i in 10:
		await ev_wheel(true)
		await idle(2)
	await idle(20)
	var step_in := step_m()
	var r1 := gap_range()
	ok(step_in < step_open and step_in > 0.0 and r1.x >= 60.0 and r1.y <= 180.0,
		"3 IN after 10 notches in the step is %.0f cm (was %.0f cm), the numbers %.0f to %.0f px apart (60 to 180)" % [step_in * 100.0, step_open * 100.0, r1.x, r1.y])
	root.get_texture().get_image().save_png("%s/grid_in.png" % SHOT)

	for i in 6:
		await ev_wheel(false)
		await idle(2)
	await idle(20)
	var step_out := step_m()
	var r2 := gap_range()
	ok(step_out > step_in and r2.x >= 60.0 and r2.y <= 180.0,
		"4 OUT after 6 notches out the step is %.0f cm (was %.0f cm), the numbers %.0f to %.0f px apart (60 to 180)" % [step_out * 100.0, step_in * 100.0, r2.x, r2.y])

	# back in for the checks of the shown text and position
	for i in 10:
		await ev_wheel(true)
		await idle(2)
	await idle(20)
	var words := true
	var rx := RegEx.new()
	rx.compile("^(0|-?[0-9]+ cm)$")
	var bad := ""
	for l in numbers():
		if rx.search((l as Label3D).text) == null:
			words = false
			bad += " '%s'" % (l as Label3D).text
	ok(words and numbers().size() > 0, "5 WORDS every shown number is plain words (0, or whole cm)%s" % bad)
	var worst := 0.0
	var truthful := true
	for d in x_axis():
		var t := String(d["text"]).replace(" cm", "")
		var v := float(t) * 0.01
		worst = maxf(worst, absf(float(d["x"]) - v))
		truthful = truthful and absf(float(d["x"]) - v) < 1e-4
	ok(truthful and x_axis().size() > 0,
		"6 TRUE every X-axis number sits at its own value, worst %.4f mm off" % (worst / MM))

	ok((ep()._rec().get("features", []) as Array).size() == n0 and m.undo.size() == u0,
		"7 NOSTEP the zooms add no build step (%d -> %d) and no undo step (%d -> %d)" % [n0, (ep()._rec().get("features", []) as Array).size(), u0, m.undo.size()])

	pu().set_on(false)
	await idle(10)
	ok(numbers().is_empty(), "8 LEAVE leaving Easy Part hides every number (%d still shown)" % numbers().size())

	print("p108measuregri: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## a click on a control: a move onto it, then the press and the release (real events)
func _press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		await process_frame
	await idle(2)
