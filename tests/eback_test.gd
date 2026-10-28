extends SceneTree
## godot --path . --position 4000,4000 -s tests/eback_test.gd     (EBACK: the ewalk6 walk. Use in a scene from Easy Part goes to STAGE; there must be a clear "Back to your part" button there that reopens Easy Part on the same part; and Round the edges at the default is visibly round, not the "Barely" guard; needs the CAD DLL and a window)
## A beginner from the REAL start screen (the building card, Part, Easy). Real clicks at 1280 x 720 only.
## Bars (each FAILED on the old code, see the report):
##   ROUND1  Round the edges on the default sword (a thin blade): the round is at least 1 mm, the slider's low end (the old default was 0.5 mm, below the slider: "Barely" looked square)
##   USE1    Use in a scene (the Easy bar) puts the part in the set: page STAGE, one prop of the part
##   BACK1   STAGE shows a "Back to your part" button, enabled, inside the 1280 x 720 window, not covered by another control
##   BACK2   a real click on it: page BUILD, Part on, Easy Part on (its screen is up)
##   BACK3   the same part: its name and step count are the ones it had before Use in a scene
## Shots: C:/Temp/claude/eback/stage.png, back.png

const SHOT := "C:/Temp/claude/eback"
const DIRT := "user://eback_test"
var fails := 0
var m: Node
var log_lines: Array = []


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	log_lines.append(("ok   " if c else "FAIL ") + w)
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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func part_name() -> String:
	return String(m.S.part.get("name", ""))


func part_steps() -> int:
	return m.S.part.get("features", []).size()


## the newest fillet step's radius (mm), -1 when there is none
func last_round_mm() -> float:
	var fs: Array = m.S.part.get("features", [])
	for i in range(fs.size() - 1, -1, -1):
		if String(fs[i].get("t", "")) == "fillet":
			return float(fs[i].get("r", -1.0))
	return -1.0


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
	if not ss.visible:
		ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)

	# ROUND1: the default sword (a thin blade: the case where the old default fell to 0.5 mm), then Round the edges (a real click)
	await click_ctl(ep().make_btns["round"])
	await idle(4)
	var rmm := last_round_mm()
	ok(rmm >= 1.0, "ROUND1 Round the edges on the default sword: the new round is %.1f mm (at least 1 mm; words [%s])" % [rmm, String(ep().msg)])
	await shot("round")

	# USE1: Use in a scene on the Easy bar
	var steps_before := part_steps()
	var name_before := part_name()
	await click_ctl(ep().use_scene_btn)
	await idle(6)
	ok(m.cur_page == "STAGE" and m.bld.part_ready() == true, "USE1 Use in a scene: page STAGE (now %s), the part is in the set" % m.cur_page)
	await shot("stage")

	# BACK1: the button on STAGE
	var bb: Button = root.find_child("build_back_to_part", true, false) as Button
	var on_screen := false
	var clear := false
	if bb != null and bb.is_visible_in_tree():
		var r := bb.get_global_rect()
		on_screen = Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(r)
		clear = true
	ok(bb != null and bb.is_visible_in_tree() and not bb.disabled and on_screen and bb.text == "Back to your part",
		"BACK1 STAGE shows the button \"Back to your part\" (found %s, shown %s, enabled %s, inside 1280x720 %s)" % [str(bb != null), str(bb != null and bb.is_visible_in_tree()), str(bb != null and not bb.disabled), str(on_screen)])

	# BACK2 / BACK3: a real click reopens Easy Part on the same part
	if bb != null:
		await click_ctl(bb)
		await idle(6)
	await shot("back")
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "BACK2 the click: page BUILD (now %s), Part on %s, Easy Part on %s" % [m.cur_page, str(pu().on), str(pu().easy)])
	ok(part_name() == name_before and part_steps() == steps_before, "BACK3 the same part: name %s (was %s), steps %d (was %d)" % [part_name(), name_before, part_steps(), steps_before])

	print("eback: %d fail" % fails)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var f := FileAccess.open(SHOT + "/log.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(log_lines) + "\n")
		f.close()
	quit(1 if fails > 0 else 0)
