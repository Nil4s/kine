extends SceneTree
## godot --path . --position 4000,4000 -s tests/fsave_test.gd     (FSAVE: a free part made from the BUILDING card, saved, Home, reopened from My parts, changed, Undo/Redo across the reopen, given to the fighter; needs a window and the CAD DLL)
## A beginner who never read a manual, real clicks at 1280 x 720 from the real start screen. The store is user://fsave_test/parts.
## BARS (stated before measuring; each one run on the old code first):
##   1 MAKE     BUILDING card, Draw shape, a drag on the grid, Pull it up, Round the edges: one solid (one body, volume > 0)
##   2 SAVEWORD the button that saves the part reads Save (a beginner looks for Save; the old words were "Use in a scene")
##   3 SAVE     pressing it writes the part to the store (record and picture) and the record equals the part as made (JSON equal)
##   4 HOME     the Home button (Easy bar) goes back to the start screen
##   5 REOPEN   BUILDING card again, the library My parts card, its tile, Change the part: the part is the saved record (JSON equal), one body
##   6 UNDO     Undo takes the reopen back (the part is no longer the saved record); Redo puts it back (JSON equal again)
##   7 EDIT     the Pull height slider of the reopened part: dragged, the volume changes, ONE undo step
##   8 FIGHTER  Give to fighter: the fighter holds the part (wep_on)
## Shots: C:/Temp/claude/fsave/
const SHOT := "C:/Temp/claude/fsave"
const DIRT := "user://fsave_test"
const DIRP := "user://fsave_test/parts"
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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func norm(x) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(x)))


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func wipe(d: String) -> void:
	var a := ProjectSettings.globalize_path(d)
	if not DirAccess.dir_exists_absolute(a):
		return
	for f in DirAccess.get_files_at(a):
		DirAccess.remove_absolute(a + "/" + f)
	for sub in DirAccess.get_directories_at(a):
		wipe(d + "/" + sub)
		DirAccess.remove_absolute(a + "/" + sub)


func disk(p: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(p))


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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	var sc = load("res://scripts/build/myparts.gd") as GDScript
	sc.dir = DIRP
	wipe(DIRT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRP))
	var ss: StartScreen = m.start_screen
	ss.dirs_override = [DIRT]
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)

	# 1 MAKE: BUILDING card, then a shape by clicks
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	await idle(20)
	var corners := [scr(Vector3(-0.5, 0.0, -0.5)), scr(Vector3(0.5, 0.0, -0.5)), scr(Vector3(0.5, 0.0, 0.5)), scr(Vector3(-0.5, 0.0, 0.5))]
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(Vector2(830, 560), Vector2(950, 610))
	await click_ctl(ep().make_btns["pull"])
	await click_ctl(ep().make_btns["round"])
	await shot("01_made")
	ok(int(pu().res.get("bodies", 0)) == 1 and vol() > 0.0,
		"1 MAKE a free part by clicks: one solid, volume %.0f mm3 (corner %s)" % [vol(), corners[0]])
	m.S.part["name"] = "Tower"
	var rec_made := norm(m.S.part)

	# 2 SAVEWORD: the save button's word
	var sbtn: Button = ep().use_scene_btn
	ok(sbtn.text.findn("save") >= 0,
		"2 SAVEWORD the save button reads Save (it says '%s')" % sbtn.text)

	# 3 SAVE
	await click_ctl(sbtn)
	for i in 180:
		if disk(sc.thumb_of("Tower")):
			break
		await idle(1)
	var saved: Dictionary = sc.load_part("Tower")
	ok(disk(sc.path_of("Tower")) and disk(sc.thumb_of("Tower")) and not saved.is_empty() and norm(saved) == rec_made,
		"3 SAVE the store has Tower (record %s, picture %s), record equal to the part as made" % [disk(sc.path_of("Tower")), disk(sc.thumb_of("Tower"))])
	await shot("02_saved")

	# 4 HOME
	var hb: Button = root.find_child("build_stage_home", true, false) as Button   # on STAGE with a part: the part box's Home (the Easy bar's is hidden there)
	if hb == null or not hb.is_visible_in_tree():
		hb = root.find_child("home_btn", true, false) as Button
	if hb != null and hb.is_visible_in_tree():
		await click_ctl(hb)
	await idle(6)
	ok(hb != null and ss.visible, "4 HOME the Home button goes back to the start screen (visible %s)" % str(ss.visible))
	await shot("03_home")

	# 5 REOPEN: the BUILDING card, the library My parts card, its tile, Change the part
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m._library_toggle()
	await idle(3)
	var lib = m.ui_library
	lib.recent_file = DIRT + "/recent.json"
	lib.clear_recent()
	await idle(2)
	var side := lib.find_child("cat_my_parts", true, false) as Button
	if side != null:
		await click_ctl(side)
	await idle(2)
	var tile := lib.find_child("tile_mypart_saved_Tower", true, false) as Button
	if tile != null:
		await click_ctl(tile)
	await idle(4)
	var pi := -1
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]).begins_with("part:Tower#"):
			pi = i
	m.sel_prop = pi
	m._props_show()
	await idle(2)
	if lib.visible:
		lib.hide_panel()
	await idle(3)
	var eb: Button = root.find_child("build_edit_in_build", true, false) as Button
	var u0: int = m.undo.size()
	if eb != null:
		await click_ctl(eb)
	await idle(6)
	await shot("04_reopen")
	var reopened := norm(m.S.part)
	ok(pi >= 0 and eb != null and reopened == rec_made and int(pu().res.get("bodies", 0)) == 1,
		"5 REOPEN Tower from My parts is the saved record (JSON equal %s, one body)" % str(reopened == rec_made))

	# 6 UNDO / REDO across the reopen
	var u1: int = m.undo.size()
	await click_ctl(ep().undo_btn)
	await idle(4)
	var back := norm(m.S.part)
	await click_ctl(ep().redo_btn)
	await idle(4)
	var again := norm(m.S.part)
	ok(u1 > u0 and back != rec_made and again == rec_made,
		"6 UNDO Undo takes the reopen back (%s), Redo puts it back (%s)" % [str(back != rec_made), str(again == rec_made)])

	# 7 EDIT: the Pull height slider of the reopened part, one undo step
	var sl: HSlider = null
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			sl = r["slider"]
	var v1 := vol()
	var u2: int = m.undo.size()
	if sl != null:
		await drag_slider(sl, sl.max_value * 0.5)
	await idle(4)
	var v2 := vol()
	ok(sl != null and absf(v2 - v1) > 0.01 * v1 and m.undo.size() == u2 + 1,
		"7 EDIT the height slider: volume %.0f -> %.0f mm3, undo +%d" % [v1, v2, m.undo.size() - u2])
	await shot("05_edit")

	# 8 FIGHTER
	await click_ctl(ep().give_btn)
	await idle(4)
	ok(m.B.wep_on, "8 FIGHTER Give to fighter: the fighter holds the part (wep_on %s)" % str(m.B.wep_on))
	await shot("06_fighter")

	wipe(DIRT)
	print("fsave: %d fail" % fails)
	quit(1 if fails > 0 else 0)
