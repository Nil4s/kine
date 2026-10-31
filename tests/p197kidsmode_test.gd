extends SceneTree
## p197kidsmode (Friday plan item 197: Kids mode, the small version). A beginner from the BUILDING card: Parts opens the library page. Its last
## chip is Kids: one click makes the library's category buttons big and round (taller, bigger words, rounder corners) so a child can press
## them; a second click puts them back. A view setting only: no undo step, nothing in the model changes. Kine's own idea (★): the same chips
## keep their plain words and icons, and the page stays on the 1280 x 720 screen. Every size below is measured from the BUILT screen rects
## and theme overrides, never from the code's own variables.
## Bars (written before the code: on the old code there is no Kids chip, so bars 0 to 5 FAIL there):
##   0 Parts page: a Kids chip, off; the Screws chip is 34 px tall with corner radius 6 px
##   1 one click on Kids: pressed; all 15 category chips 40 px tall (+- 0.5), words 15 px, corner radius 14 px
##   2 Kids on: the library page's bottom edge is still on the 720 px screen (<= 720) and the Kids chip sits inside it
##   3 Kids on, then Screws pressed: the Screws chip is pressed and still 40 px tall (the big size survives a page change)
##   4 second click on Kids: off; every category chip back to 34 px and radius 6 px
##   5 the words: the Kids chip reads "Kids" and its tip has no key name (no "Ctrl", no "Shift")
## shots: C:/Temp/claude/p197kidsmode/shots/
const SHOT := "C:/Temp/claude/p197kidsmode/shots"
const DIRT := "user://p197kidsmode_test"
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


## the library's category chips as they are on screen now: [Button]
func cat_chips() -> Array:
	var out: Array = []
	var lib := root.find_child("easypart_library", true, false)
	if lib == null:
		return out
	for n in lib.find_children("easypart_lib_*", "Button", true, false):
		out.append(n)
	return out


func corner_r(b: Button) -> int:
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.corner_radius_top_left if sb != null else -1


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

	# the BUILDING card, one click: an empty Easy Part; Parts opens the library page
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Control)
	await idle(10)
	var kids := root.find_child("easypart_kids", true, false) as Button
	var scr := root.find_child("easypart_lib_Screws", true, false) as Button

	# 0 the Kids chip is on the page, off; the Screws chip is 34 px tall, radius 6
	var h0 := scr.get_global_rect().size.y if scr != null else -1.0
	ok(kids != null and kids.is_visible_in_tree() and not kids.button_pressed and scr != null and absf(h0 - 34.0) <= 0.5 and corner_r(scr) == 6,
		"0 Parts page: a Kids chip, off; Screws %.1f px tall (want 34), radius %d px (want 6)" % [h0, corner_r(scr) if scr != null else -1])
	await shot("00_kids_off")

	# 1 one click on Kids: pressed; every category chip 40 px tall, words 15 px, radius 14 px
	if kids != null:
		await click_ctl(kids)
	await idle(10)
	var chips := cat_chips()
	var big := chips.size() == 15   # the library's 15 category chips (LIB_CATS), all found on the page
	var hmin := 1e9
	var rmin := 1000
	var fmin := 1000
	for b in chips:
		var bb := b as Button
		hmin = minf(hmin, bb.get_global_rect().size.y)
		rmin = mini(rmin, corner_r(bb))
		fmin = mini(fmin, bb.get_theme_font_size("font_size"))
	big = big and absf(hmin - 40.0) <= 0.5 and rmin == 14 and fmin == 15
	ok(kids != null and kids.button_pressed and big,
		"1 Kids on: %d category chips, the smallest %.1f px tall (want 40), radius %d px (want 14), words %d px (want 15)" % [chips.size(), hmin, rmin, fmin])
	await shot("01_kids_on")

	# 2 the library page stays on the 720 px screen; the Kids chip is inside it
	var lib := root.find_child("easypart_library", true, false) as Control
	var lb := lib.get_global_rect() if lib != null else Rect2()
	var kb := kids.get_global_rect() if kids != null else Rect2()
	ok(lib != null and lib.is_visible_in_tree() and lb.end.y <= 720.0 and lb.position.y >= 0.0 and lb.encloses(kb),
		"2 Kids on: the library page ends at %.1f px (want 720 or less) and the Kids chip sits inside it" % lb.end.y)

	# 3 Kids on, then Screws pressed: Screws pressed, still 40 px tall
	if scr != null:
		await click_ctl(scr)
	await idle(10)
	var h3 := scr.get_global_rect().size.y if scr != null else -1.0
	ok(scr != null and scr.button_pressed and kids.button_pressed and absf(h3 - 40.0) <= 0.5,
		"3 Kids on, Screws pressed: Screws pressed %s, %.1f px tall (want 40)" % [str(scr.button_pressed), h3])

	# 4 second click on Kids: off; every category chip back to 34 px, radius 6 px
	if kids != null:
		await click_ctl(kids)
	await idle(10)
	var hmax := 0.0
	var rmax := 0
	for b in cat_chips():
		var bb := b as Button
		hmax = maxf(hmax, bb.get_global_rect().size.y)
		rmax = maxi(rmax, corner_r(bb))
	ok(kids != null and not kids.button_pressed and absf(hmax - 34.0) <= 0.5 and rmax == 6,
		"4 Kids off: the tallest category chip %.1f px (want 34), radius %d px (want 6)" % [hmax, rmax])
	await shot("02_kids_off_again")

	# 5 the words: "Kids", and the tip names no key
	var tip := kids.tooltip_text if kids != null else ""
	ok(kids != null and kids.text == "Kids" and tip != "" and tip.find("Ctrl") < 0 and tip.find("Shift") < 0,
		"5 the Kids chip reads \"Kids\" and its tip names no key: \"%s\"" % tip)

	print("p197kidsmode: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
