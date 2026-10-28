extends SceneTree
## godot --path . --position 4000,4000 -s tests/nchaos2_test.gd     (nchaos2: the minimal repros of the Easy Part chaos monkey, seeds 1..10; needs the CAD DLL and a window)
## Each bar is a short list of REAL inputs (clicks through root.push_input at 1280 x 720) from the start screen (Building card, Part, Easy).
## Bars: one "ok"/"FAIL" line per check; exit 1 on any FAIL.
##   1 SENTINEL  Easy Part, Empty chip, Expert Line (a sketch starts), Part page -> Easy: the sketch is taken out and the part record is the
##               empty {} (no part). Nothing is logged while that happens (the monkey's seed 8 reached this state at step 287).
##   2 SLIDER    with that empty record, a slider's pending numbers flush (what a drag does): no error, no part is invented.
##   3 ROUNDS    PartTemplates.fit_rounds on the empty record: no error, returns "".

const DIRT := "user://nchaos2_test"
const SHOT := "C:/Temp/claude/nchaos2"

class ErrLog extends Logger:
	var errs: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type == 1:
			return
		errs.append("%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale])

var fails := 0
var m: Node
var log_errs := ErrLog.new()


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_node(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func cur_ep() -> Node:
	var pu = m.bld.part if m != null and m.bld != null else null
	if pu == null or pu.ep == null or not is_instance_valid(pu.ep) or not pu.ep.is_inside_tree():
		return null
	return pu.ep


func open_easy() -> bool:
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_node(ss._cards["building"] as Control)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	var pu = m.bld.part
	await click_node(pu.part_btn)
	await click_node(pu.easy_open_btn)
	await idle(4)
	return cur_ep() != null


func new_main() -> void:
	if m != null:
		m.queue_free()
		await idle(4)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)


func vis_sliders() -> Array:
	var out := []
	for n in root.find_children("easypart_slider_*", "Range", true, false):
		if (n as Control).is_visible_in_tree():
			out.append(n.name)
	return out


func named(nm: String) -> Control:
	var r := root.find_child(nm, true, false)
	return r as Control


func ev_mouse_dummy() -> void:
	pass


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	OS.add_logger(log_errs)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the Easy Part bars cannot run")
		quit(1)
		return
	await new_main()
	ok(await open_easy(), "s8 open Easy Part from the start screen")
	var ep := cur_ep()
	# 1 SENTINEL: the input path
	await click_node(named("easypart_chip_empty"))
	await click_node(named("easypart_btn_expert"))
	await idle(4)
	if named("part_tool_line") != null:
		await click_node(named("part_tool_line"))
	var pu = m.bld.part
	await click_node(pu.part_btn)
	await click_node(pu.easy_open_btn)
	await idle(4)
	ok(cur_ep() != null and m.S.part.is_empty(), "s8 1 sentinel: Expert's empty sketch is taken out, the part is the empty record {}")
	ok(log_errs.errs.is_empty(), "s8 1 sentinel: nothing logged on the way (%s)" % str(log_errs.errs))
	# 2 SLIDER: a drag's flush with no part
	log_errs.errs.clear()
	ep = cur_ep()
	ep._pending = {"blade_length": 30.0}
	ep._dirty = true
	ep._flush()
	await idle(2)
	ok(log_errs.errs.is_empty(), "s8 2 slider flush with no part: no error (%s)" % str(log_errs.errs))
	ok(m.S.part.is_empty(), "s8 2 slider flush with no part: no part is invented")
	# 3 ROUNDS: the function itself
	log_errs.errs.clear()
	var note: String = PartTemplates.fit_rounds({})
	ok(log_errs.errs.is_empty() and note == "", "s8 3 fit_rounds on the empty record: no error, no note (%s)" % str(log_errs.errs))
	print("nchaos2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
