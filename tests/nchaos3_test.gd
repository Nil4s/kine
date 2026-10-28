extends SceneTree
## godot --path . --position 4000,4000 -s tests/nchaos3_test.gd     (NCHAOS3: Easy Part chaos monkey repros, seeds 11..20 of tests/nchaos_test.gd; scripts/easy_part.gd; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from the start screen (Building card, Part, Easy). Each bar is one minimal repro the monkey found.
## Bars (each FAILED on the old code, run before the fix):
##   1 HOLE_UNDO  Cut a hole, Undo, an Expert rectangle takes the hole's sketch id, back on Easy, Undo, then the rows are re-read:
##                no script error (seed 17, step 296: _tweak_value read 'r' of a rectangle sketch; the hole's slider was stale)
##   2 ROWS       after that, the last step's slider is gone (not stale): the rows follow the record
## Bar 1 calls the rows' re-read directly (EasyPart._values_sync): the monkey's trigger was an Undo click on that path.
## Writes nothing but a log line; exit 1 on any FAIL.
const SHOT := "C:/Temp/claude/nchaos3/s1"
const DIRT := "user://nchaos3_test"

class ErrLog extends Logger:
	var errs: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type == 1:   # warnings do not count
			return
		errs.append("%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale])

var fails := 0
var m: Node
var log_errs := ErrLog.new()


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


## a real click on a control: press and release, then two frames
func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## a drag on the floor from world a to world b (metres), real events
func draw_floor(a: Vector3, b: Vector3) -> void:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
	await ev_mouse(pb, false)
	await idle(3)


func fresh_scene() -> void:
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)


## the start screen, Building, Part, Easy: Easy Part open on an empty part
func open_easy() -> bool:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	await fresh_scene()
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await press(pu().part_btn)
	await press(pu().easy_open_btn)
	await idle(4)
	if ep() == null:
		return false
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	return true


func errs_now() -> String:
	return "" if log_errs.errs.is_empty() else str(log_errs.errs[0])


func _init() -> void:
	OS.add_logger(log_errs)
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the nchaos3 bars cannot run")
		quit(1)
		return

	# 1 HOLE_UNDO: a floor box, pulled, cut with a hole; Undo takes the hole back. The Easy hole's slider still names the
	# hole's sketch id; Expert draws a rectangle, which takes that id (the ids come from the record's counter, which Undo
	# rewinds); back on Easy, the stale slider must go, not read the rectangle's radius
	if await open_easy():
		await press(ep().empty_chip)   # the start part comes with steps: an empty part first (one undo step)
		log_errs.errs.clear()
		await press(ep().make_btns["draw"])
		await draw_floor(Vector3(-0.12, 0.0, -0.06), Vector3(-0.08, 0.0, -0.02))
		await press(ep().make_btns["pull"])
		await press(ep().make_btns["hole"])
		await press(ep().undo_btn)
		await press(ep().expert_btn)
		await idle(4)
		var rb: Button = pu().tool_btns["Rectangle"]
		if rb.is_visible_in_tree():
			await press(rb)
		await draw_floor(Vector3(0.04, 0.0, 0.02), Vector3(0.08, 0.0, 0.06))   # the rectangle takes the hole's id
		await draw_floor(Vector3(-0.04, 0.0, -0.02), Vector3(0.0, 0.0, 0.02))  # a second one, after it
		await press(ep().easy_btn)
		await idle(6)
		await press(ep().undo_btn)   # takes the second rectangle back: the first one stays, the slider still names its id
		await idle(6)
		ep()._values_sync()   # the rows are re-read from the record (what a MAKE press or a slider move does; the monkey hit it on an Undo)
		await idle(4)
		ok(errs_now() == "", "1 HOLE_UNDO no script error after Cut a hole, Undo, an Expert rectangle that takes its id, Easy, Undo, a sync (%s)" % errs_now())
		# 2 ROWS: the slider rows still follow the record: none of them reads a value the record does not have
		var rows_ok := true
		for r in ep().rows:
			if r["kind"] == "tweak" and not (ep()._rec().get("features", []) as Array).any(func(f): return String(f.get("id", "")) == String(ep().tweak.get("id", ""))):
				rows_ok = false
		ok(errs_now() == "" and rows_ok, "2 ROWS the slider rows follow the record after that draw (rows %d)" % ep().rows.size())
	else:
		ok(false, "1 HOLE_UNDO could not open Easy Part from the start screen")

	print("nchaos3: %d fail" % fails)
	quit(1 if fails > 0 else 0)
