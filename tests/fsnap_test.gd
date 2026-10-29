extends SceneTree
## FSNAP (Nick 2026-10-28, Fusion 360 style): Draw shape's corners snap to the 1 cm grid by default, so a box's sides are round
## numbers of cm; holding Alt turns the snap off; the words say it once (the first drawn shape), not on every shape.
## Real clicks at 1280x720 from the BUILDING card (Easy Part, empty). Bars (run on the old code before the change: 1, 2, 3, 4 FAILED):
##   0 the BUILDING card, one click: Easy Part on
##   1 a plain drag on the grid: both sides of the box are whole cm (10 mm steps) in mm
##   2 the first shape's words name the 1 cm snap and Alt ("Hold Alt" for a free size)
##   3 a drag with Alt held: a box side is NOT on the 5 mm grid (free size; the old 5 mm snap is what fails it)
##   4 the second shape's words do not repeat the 1 cm snap (said once)
## shots: C:/Temp/claude/fsnap/01_open.png, 02_snap.png (the 1 cm box), 03_free.png (the Alt box)
const SHOT := "C:/Temp/claude/fsnap"
const DIRT := "user://fsnap_test"

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, alt := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.alt_pressed = alt
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true, alt := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.alt_pressed = alt
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


func drag_screen(a: Vector2, b: Vector2, alt := false) -> void:
	await ev_move(a, false, alt)
	await ev_mouse(a, true, alt)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0), true, alt)
	await ev_mouse(b, false, alt)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


## the sides (mm) of the newest box sketch drawn: [x, y] or [] when there is none
func last_box_sides() -> Array:
	var fs: Array = m.S.part.get("features", [])
	for i in range(fs.size() - 1, -1, -1):
		var f: Dictionary = fs[i]
		if String(f.get("t", "")) == "sketch" and not (f.get("ents", []) as Array).is_empty():
			var e: Dictionary = f["ents"][0]
			if String(e.get("k", "")) == "rect":
				var a: Array = e["a"]
				var b: Array = e["b"]
				return [absf(float(b[0]) - float(a[0])), absf(float(b[1]) - float(a[1]))]
			return []
	return []


## true when v (mm) is a whole number of 10 mm steps (1 cm), within 0.05 mm
func on_cm(v: float) -> bool:
	return absf(v - 10.0 * roundf(v / 10.0)) < 0.05


## true when v (mm) is NOT on the 5 mm grid (more than 0.2 mm off every 5 mm line; a free side lands on one by chance ~8% of the time, the snapped one on it exactly)
func off_5mm(v: float) -> bool:
	return absf(v - 5.0 * roundf(v / 5.0)) > 0.2


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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	await idle(20)
	await shot("01_open")
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy,
		"0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)

	# 1 a plain drag on the grid: the box's sides are whole cm
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(Vector2(830, 560), Vector2(948, 597))
	await shot("02_snap")
	var s1 := last_box_sides()
	var w1: String = pu().ep.msg
	print("     plain drag sides mm %s, words '%s'" % [s1, w1])
	ok(s1.size() == 2 and on_cm(s1[0]) and on_cm(s1[1]),
		"1 a plain drag: both sides are whole cm on the grid (sides %s mm)" % [s1])

	# 2 the first shape's words name the 1 cm snap and Alt, once
	ok(w1.find("1 cm") >= 0 and w1.find("Alt") >= 0,
		"2 the first shape says it snaps to 1 cm and that Alt frees it ('%s')" % w1)

	# 3 Alt held: the box's sides are free (not on the 5 mm grid)
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(Vector2(830, 470), Vector2(948, 521), true)
	await shot("03_free")
	var s3 := last_box_sides()
	var w3: String = pu().ep.msg
	print("     Alt drag sides mm %s, words '%s'" % [s3, w3])
	ok(s3.size() == 2 and (off_5mm(s3[0]) or off_5mm(s3[1])),
		"3 a drag with Alt held: a side is free, off the 5 mm grid (sides %s mm)" % [s3])

	# 4 the second shape does not repeat the snap words
	ok(w3.find("1 cm") < 0, "4 the second shape does not repeat the 1 cm words ('%s')" % w3)

	print("fsnap: %d fail" % fails)
	quit(1 if fails > 0 else 0)
