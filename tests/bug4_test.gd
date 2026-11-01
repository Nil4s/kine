extends SceneTree
## bug4 (Nick 11-01: "I have no access to our library with things yet"): the Parts chip sat at the FOOT of the scrolling side panel (50 x 34 px,
## below the fold at 1280 x 720). Now Easy Part's bar has a big "Library" button, and the 3D BUILDING start card has a "Parts library" button.
## godot --path . --position 4000,4000 -s tests/bug4_test.gd     (real clicks, from the real start screen, at 1280 x 720 and at 1920 x 1080)
## Bars per size: A  start screen -> 3D BUILDING card (click 1) -> Library (click 2): the library page is open, at most 2 clicks;
##   the Library button is fully on screen, >= 40 px tall, reads "Library"; the category chips are on screen (Screws, Boards)
##   B  start screen -> "Parts library" (click 1): Easy Part open with the library page open
##   C  M4 x 10 screw and Arduino Uno R3 box from the library: one solid, ONE undo step each
##   D  Library pressed again shuts the page
## Shots in C:/Temp/claude/bug4/
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/bug4"
const DIRT := "user://bug4_test"


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


func pu() -> PartUI:
	return m.bld.part


func vol() -> float:
	return float(pu().res.get("volume", 0.0))


func chip(nm: String) -> Button:
	return root.find_child("easypart_chip_" + nm, true, false) as Button


func visible_chip(nm: String) -> bool:
	var c := chip(nm)
	return c != null and c.is_visible_in_tree()


func vp_ok(c: Control, w: int, h: int) -> bool:
	return c != null and c.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(w, h)).encloses(c.get_global_rect())


func reveal(c: Control) -> void:
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			(n as ScrollContainer).ensure_control_visible(c)
		n = n.get_parent()
	await idle(3)


func ep() -> EasyPart:
	return m.bld.part.ep


func solid() -> bool:
	return float(pu().res.get("volume", 0.0)) > 0.0 and int(pu().res.get("bodies", 0)) >= 1


func home(w: int, h: int) -> StartScreen:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(w, h)
	root.content_scale_size = Vector2i(w, h)
	await idle(4)
	var ss: StartScreen = m.start_screen
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(4)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	return ss


func enter() -> void:
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)


func run_size(w: int, h: int) -> void:
	var t := "%dx%d" % [w, h]
	if m.bld.part.ep != null:   # a fresh start: the library page is shut (the first size left it open)
		m.bld.part.ep.parts_open = false
		m.bld.part.ep.lib_cat = ""
	# ---- A: card, then Library
	var ss: StartScreen = await home(w, h)
	await click_ctl(ss._easy_btn["building"])   # (Easy is the default of a new user; this click is the card's own Easy button, the first and only click on the card)
	await enter()
	var clicks := 1
	var lb: Button = ep().lib_bar_btn
	await shot(t + "_A1_easypart")
	ok(vp_ok(lb, w, h), "A %s the Library button is fully on screen %s (window %dx%d)" % [t, str(lb.get_global_rect()) if lb != null else "missing", w, h])
	ok(lb != null and lb.size.y >= 40.0, "A %s the Library button is %.0f px tall (>= 40)" % [t, lb.size.y if lb != null else -1.0])
	ok(lb != null and lb.text == "Library", "A %s the button says '%s'" % [t, lb.text if lb != null else ""])
	ok(lb != null and not lb.disabled and not ep().lib_box.is_visible_in_tree(), "A %s the button is enabled and the library page is shut before the click" % t)
	var bar_end := 0.0
	for b in ep().bar.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			bar_end = maxf(bar_end, (b as Button).get_global_rect().end.x)
	print("   restore button on the bar: ", ep().restore_btn.is_visible_in_tree())
	print("   bar: last button ends at x=%.0f of %d" % [bar_end, w])
	ok(bar_end <= float(w), "A %s every bar button is on screen (the bar ends at x=%.0f, window %d)" % [t, bar_end, w])
	await click_ctl(lb)
	clicks += 1
	await idle(8)
	await shot(t + "_A2_library")
	ok(clicks <= 2 and ep().lib_box.is_visible_in_tree() and ep().parts_open, "A %s the library page is open after %d clicks (card, Library)" % [t, clicks])
	var cs := ep().lib_btns["Screws"] as Button
	var cb := ep().lib_btns["Boards"] as Button
	ok(vp_ok(cs, w, h) and vp_ok(cb, w, h), "A %s the category chips Screws %s and Boards %s are on screen" % [t, str(cs.get_global_rect()), str(cb.get_global_rect())])
	ok(ep().lib_bar_btn.button_pressed, "A %s the Library button shows it is open (lit)" % t)
	# ---- C: a screw and a board, from the page, one undo step each
	m.S.part = {}
	await idle(6)
	var sb: Button = ep().screw_btns["4_10"]
	await reveal(sb)
	var u0: int = m.undo.size()
	ok(vp_ok(sb, w, h), "C %s the M4 x 10 chip is on screen %s" % [t, str(sb.get_global_rect())])
	await click_ctl(sb)
	await idle(20)
	ok(solid() and m.undo.size() == u0 + 1, "C %s M4 x 10 screw built (volume %.0f mm3, bodies %d), ONE undo step (%d -> %d)" % [t, float(pu().res.get("volume", 0.0)) * 1e9, int(pu().res.get("bodies", 0)), u0, m.undo.size()])
	await shot(t + "_C1_screw")
	m.S.part = {}
	await idle(6)
	await reveal(cb)
	await click_ctl(cb)
	await idle(6)
	var ub: Button = root.find_child("easypart_bcase_bc_uno", true, false) as Button
	await reveal(ub)
	var u1: int = m.undo.size()
	ok(vp_ok(ub, w, h), "C %s the Arduino Uno R3 chip is on screen %s" % [t, str(ub.get_global_rect())])
	await click_ctl(ub)
	await idle(20)
	ok(solid() and m.undo.size() == u1 + 1, "C %s Arduino Uno R3 box built (volume %.0f mm3, bodies %d), ONE undo step (%d -> %d)" % [t, float(pu().res.get("volume", 0.0)) * 1e9, int(pu().res.get("bodies", 0)), u1, m.undo.size()])
	await shot(t + "_C2_uno")
	# ---- D: Library again shuts the page
	await click_ctl(ep().lib_bar_btn)
	await idle(6)
	ok(not ep().lib_box.is_visible_in_tree() and not ep().parts_open, "D %s Library pressed again shuts the page" % t)
	await click_ctl(ep().lib_bar_btn)
	await idle(6)
	ok(ep().lib_box.is_visible_in_tree(), "D %s and again opens it" % t)
	# ---- B: from the start screen
	ss = await home(w, h)
	var pl: Button = ss.find_child("lib_building", true, false) as Button
	await shot(t + "_B1_start")
	ok(vp_ok(pl, w, h) and pl.text == "Parts library", "B %s the start screen has a '%s' button on the 3D BUILDING card, on screen %s" % [t, pl.text if pl != null else "", str(pl.get_global_rect()) if pl != null else ""])
	await click_ctl(pl)
	await enter()
	await idle(20)
	await shot(t + "_B2_library")
	ok(ep() != null and ep().panel.is_visible_in_tree() and ep().lib_box.is_visible_in_tree() and ep().parts_open and m.S.kind == "building", "B %s one click on Parts library: Easy Part is open with the library page open (kind %s)" % [t, m.S.kind])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		print("bug4: 1 fail")
		quit(1)
		return
	await run_size(1280, 720)
	await run_size(1920, 1080)
	print("bug4: %d fail" % fails)
	quit(0 if fails == 0 else 1)
