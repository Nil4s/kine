extends SceneTree
## s227b (lay1 fix): the Easy Part library page must fit the panel scroll area at 1280 x 720, so the next category chip that adds a row fails HERE, loudly.
## A page taller than the scroll area needs a scroll, and a scroll that moves while a real click is on its way sends that click to the wrong place (lay1).
##  1 FITS    Parts open (Screws page, nothing scrolled): the library page's height <= the panel scroll area's height (both printed)
##  2 SIZES   the M4 x 16 chip's middle lies inside the scroll area after the app's own one scroll to the grid (the panel scroll, printed)
##  3 WORDS   the Ornaments, Roofs, Favourites, Type it and Nature chips show their readable name, with an icon and a tooltip
##            (239, a28b6389: was 'icon-only'; the stopgap is retired, the grouped library page has room for every word; Nick authorised the rewrite)
const SHOT := "C:/Temp/claude/s227b"
const DIRT := "user://s227b_test"
var fails := 0
var m: Node
var pu: PartUI
var ep


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


## a real click on a visible control; a missing control is reported by the bar that needs it (no crash)
func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
	return true


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the library cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))

	await click_ctl(root.find_child("easypart_chip_parts", true, false))
	await idle(30)
	var sc := root.find_child("easypart_panel_scroll", true, false) as ScrollContainer
	var lb := root.find_child("easypart_library", true, false) as Control
	var chip := root.find_child("easypart_screw_M4_16", true, false) as Control
	print("     LIBRARY page height %.0f px, panel scroll area %.0f px high (%s), scroll at %d, content %.0f" % [lb.size.y, sc.size.y, str(sc.get_global_rect()), sc.scroll_vertical, sc.get_v_scroll_bar().max_value])
	ok(lb != null and sc != null and lb.size.y <= sc.size.y, "1 the library page (%.0f px) fits the panel scroll area (%.0f px) at 1280 x 720" % [lb.size.y, sc.size.y])
	var inside := chip != null and sc.get_global_rect().has_point(chip.get_global_rect().get_center())
	ok(inside, "2 the M4 x 16 chip's middle %s is inside the scroll area %s with the panel scroll at %d" % [str(chip.get_global_rect().get_center()) if chip else "-", str(sc.get_global_rect()), sc.scroll_vertical])
	var bad := []
	for nm in ["easypart_lib_Ornaments", "easypart_lib_Roofs", "easypart_lib_Favourites", "easypart_lib_Type it", "easypart_nature_chip"]:
		var b := root.find_child(nm, true, false) as Button
		if b == null or b.text.strip_edges() == "" or b.icon == null or b.tooltip_text == "":
			bad.append(nm)
	ok(bad.is_empty(), "3 the Ornaments, Roofs, Favourites, Type it and Nature chips show their name, with an icon and a tooltip (wrong: %s)" % str(bad))
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(SHOT + "/page.png")
	print("s227b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
