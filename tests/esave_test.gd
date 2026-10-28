extends SceneTree
## godot --path . --position 4000,4000 -s tests/esave_test.gd     (ESAVE: a mug made in Easy Part, saved (Use in a scene), a new Empty part, the mug reopened from My parts: identical, and its sliders work; needs a window and the CAD DLL)
## Mug by real clicks: a round cup (r 40, Pull to 80 mm) > Cut a hole > Hollow inside. Real clicks / drags at 1280 x 720. The store is user://esave_test/parts.
## BARS (stated before measuring):
##   1 SAVE     Use in a scene: the store has Mug (record and picture), and the saved record equals the part as made (JSON equal)
##   2 EMPTY    the Empty chip: a new part with no steps (features empty)
##   3 REOPEN   the saved Mug from My parts, its prop picked, Change the part: the part is the saved record again (JSON equal), one body, same volume (0.1 pct)
##   4 UNDO     the reopen is one undo step
##   5 EDIT     the Wall slider of the reopened mug (its newest step): dragged 3 -> 10 mm, the volume grows, one body, ONE undo step
##   6 SAVE2    Use in a scene again: still one saved Mug, its record is the edited one
## Shot: C:/Temp/claude/esave/shot.png
const SHOT := "C:/Temp/claude/esave"
const DIRT := "user://esave_test"
const DIRP := "user://esave_test/parts"
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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func norm(x) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(x)))


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


## the round cup: a circle r 40 mm on the floor, pulled up h cm (by clicks)
func round_cup(h: float) -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.0)))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


func tweak_slider() -> HSlider:
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			return r["slider"]
	return null


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
	var sc = load("res://scripts/build/myparts.gd") as GDScript
	sc.dir = DIRP
	wipe(DIRT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRP))
	var ss: StartScreen = m.start_screen
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
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)

	# THE MUG: round r 40, Pull to 80 mm, Cut a hole > Hollow inside
	await round_cup(8.0)
	await click_ctl(ep().make_btns["hole"])
	var chh: Button = root.find_child("easypart_hole_hollow", true, false) as Button
	if chh != null:
		await click_ctl(chh)
	await idle(3)
	m.S.part["name"] = "Mug"
	var rec_mug := norm(m.S.part)
	var vol_mug := vol()

	# 1 SAVE
	await click_ctl(ep().use_scene_btn)
	for i in 180:
		if disk(sc.thumb_of("Mug")):
			break
		await idle(1)
	var saved: Dictionary = sc.load_part("Mug")
	ok(disk(sc.path_of("Mug")) and disk(sc.thumb_of("Mug")) and not saved.is_empty() and norm(saved) == rec_mug,
		"1 SAVE the store has Mug (record %s, picture %s) and the saved record is the part as made" % [disk(sc.path_of("Mug")), disk(sc.thumb_of("Mug"))])

	# 2 EMPTY: a new part with no steps (Use in a scene leaves BUILD for STAGE: back to BUILD, Easy Part again)
	m._page_set("BUILD")
	pu().open_easy()
	await idle(4)
	await click_ctl(ep().empty_chip)
	await idle(4)
	ok((m.S.part.get("features", []) as Array).is_empty(), "2 EMPTY a new empty part (features %d)" % (m.S.part.get("features", []) as Array).size())

	# 3 REOPEN: the saved mug from the library My parts card, then Change the part on its prop
	m._library_toggle()
	await idle(3)
	m._library_toggle()
	await idle(3)
	var lib = m.ui_library
	lib.recent_file = DIRT + "/recent.json"
	lib.clear_recent()
	lib.open()
	await idle(3)
	var side := lib.find_child("cat_my_parts", true, false) as Button
	if side != null:
		await click_ctl(side)
	await idle(2)
	var tile := lib.find_child("tile_mypart_saved_Mug", true, false) as Button
	if tile != null:
		await click_ctl(tile)
	await idle(4)
	var u0: int = m.undo.size()
	var pi := -1
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]).begins_with("part:Mug#"):
			pi = i
	m.sel_prop = pi
	m._props_show()
	await idle(2)
	var eb: Button = root.find_child("build_edit_in_build", true, false) as Button
	if lib.visible:
		lib.hide_panel()   # the library is open over the stage panel: close it (as its own close button does)
	await idle(3)
	if eb != null:
		await click_ctl(eb)
	await idle(6)
	var reopened := norm(m.S.part)
	ok(pi >= 0 and eb != null and reopened == rec_mug and int(pu().res.get("bodies", 0)) == 1 and absf(vol() - vol_mug) <= 0.001 * vol_mug,
		"3 REOPEN the mug is the saved record again (JSON equal %s, bodies %d, volume %.0f vs %.0f mm3)" % [str(reopened == rec_mug), int(pu().res.get("bodies", 0)), vol(), vol_mug])

	# 4 UNDO: the reopen is one undo step
	ok(m.undo.size() - u0 == 1, "4 UNDO the reopen is one undo step (undo %d -> %d)" % [u0, m.undo.size()])

	# 5 EDIT: the Wall slider (the newest step of the reopened mug)
	var sl := tweak_slider()
	var v1 := vol()
	var u1: int = m.undo.size()
	if sl != null:
		await drag_slider(sl, 10.0)
	await idle(4)
	var v2 := vol()
	ok(sl != null and v2 > v1 * 1.02 and m.undo.size() == u1 + 1 and int(pu().res.get("bodies", 0)) == 1,
		"5 EDIT the Wall slider 10 mm: volume %.0f -> %.0f mm3, undo +%d" % [v1, v2, m.undo.size() - u1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT))
	root.get_texture().get_image().save_png(SHOT + "/shot.png")

	# 6 SAVE2: the same name replaces it
	await click_ctl(ep().use_scene_btn)
	await idle(60)
	var n_mugs := 0
	for pt in sc.list():
		if String(pt["name"]) == "Mug":
			n_mugs += 1
	ok(n_mugs == 1 and norm(sc.load_part("Mug")) == norm(m.S.part) and norm(m.S.part) != rec_mug,
		"6 SAVE2 Use in a scene again: one saved Mug, the edited record")

	wipe(DIRT)
	print("esave: %d fail" % fails)
	quit(1 if fails > 0 else 0)
