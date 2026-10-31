extends SceneTree
## p045lineshow: the Line drawn with a typed length STAYS ON THE GRID after the button is let go (the picture shows it).
## A beginner from the REAL start screen, real clicks, drags and keys at 1280 x 720 (Easy Part, Draw shape with the Line chip):
## press, drag, type 40 while the button is held, Enter, drag on, release. Then the picture of the screen is read.
## Bar (measured from the RENDERED picture, never from variables of the code):
##   0 SHOWN the grid picture gets at least 60 new pixels of the accent colour (Tok accent, the 3 px line and its 40 mm label
##     sit on the clear view) that the picture before the drag did not have
## shots: C:/Temp/claude/p045lineshow/
const SHOT := "C:/Temp/claude/p045lineshow"
const DIRT := "user://p045lineshow_test"
const MIN_NEW_PX := 60      # the 3 px line of a 40 mm stretch and the drag before it, seen on the screen
const COL_TOL := 0.08       # per channel, so the antialiased edges of the 3 px line count too

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


func key(k: Key, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		root.push_input(e, true)
		await process_frame


## one typed character as the key it is: digits and "."
func type_chars(s: String) -> void:
	for ch in s:
		var k: Key = KEY_PERIOD if ch == "." else (KEY_0 + int(ch))
		await key(k, ch.unicode_at(0))
	await idle(2)


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## the pointer walks in steps from a to b while the button is held
func walk(a: Vector2, b: Vector2) -> void:
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))


func dot_near(p: Vector2) -> bool:
	var ep = m.bld.part.ep
	for d in ep._dot_list():
		if (d["scr"] as Vector2).distance_to(p) <= 30.0:
			return true
	return false


## a point in the clear view at fractions (fx, fy), moved down until no amber dot or Easy panel is under it
func free_at(fx: float, fy: float) -> Vector2:
	var ep = m.bld.part.ep
	var cl: Rect2 = m.nav_clear_rect()
	var p := Vector2(cl.position.x + cl.size.x * fx, cl.position.y + cl.size.y * fy)
	for i in 40:
		if not dot_near(p) and not ep._over_ui(p):
			return p
		p += Vector2(0, 14)
	return p


## the picture of the whole window, after the frames have drawn
func picture() -> Image:
	await idle(3)
	return root.get_texture().get_image()


## the pixels of the clear view that are the accent colour in img and were not in before (same size pictures)
func new_accent_px(before: Image, img: Image, rect: Rect2i, col: Color) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if _is_col(img.get_pixel(x, y), col) and not _is_col(before.get_pixel(x, y), col):
				n += 1
	return n


func _is_col(c: Color, want: Color) -> bool:
	return absf(c.r - want.r) <= COL_TOL and absf(c.g - want.g) <= COL_TOL and absf(c.b - want.b) <= COL_TOL


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
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
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["line"])
	var clear_px := Rect2i(m.nav_clear_rect())
	var before := await picture()
	var c0 := free_at(0.2, 0.3)
	await ev_move(c0, false)
	await ev_mouse(c0, true)
	await walk(c0, c0 + Vector2(120, 0))
	await type_chars("40")
	await key(KEY_ENTER)
	await idle(2)
	await walk(c0 + Vector2(120, 0), c0 + Vector2(120, 60))
	await ev_mouse(c0 + Vector2(120, 60), false)
	var img := await picture()
	DirAccess.make_dir_recursive_absolute(SHOT)
	img.save_png("%s/typed_easy_40.png" % SHOT)

	var rect := clear_px.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var n := new_accent_px(before, img, rect, Tok.c("accent"))
	ok(n >= MIN_NEW_PX, "0 SHOWN the typed 40 line is on the grid after release: %d new accent pixels in the clear view (bar %d)" % [n, MIN_NEW_PX])

	print("p045lineshow: %d fail" % fails)
	m.queue_free()
	quit(1 if fails > 0 else 0)
