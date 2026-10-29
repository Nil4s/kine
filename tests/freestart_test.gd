extends SceneTree
## FREESTART (Nick 2026-10-28: "free 3D building, like Fusion 360, nothing forced"): Easy Part's "Change your part" panel offered only
## Sword / Axe / Shield / Chair / Crate, which steers people to weapons. The starters are now neutral and optional: a "Start from" row of
## Box, Cylinder, Sphere, Tube, Plate, a "More examples" button that opens What to build (the weapons are there), and the Empty part is the default.
## godot --path . --position 4000,4000 -s tests/freestart_test.gd     (needs a window and the CAD DLL; real clicks at 1280 x 720 from the real start screen)
## Bars (run on the old code before the change: 1, 2, 3, 4 FAILED):
##   1 ROW      the "Start from" row shows Box, Cylinder, Sphere, Tube, Plate; no weapon chip (Sword, Axe, Shield, Chair, Crate) is shown; "More examples" is shown
##   2 DEFAULT  a blank Easy Part opens EMPTY (no steps, no sword), the Empty chip is lit
##   3 SHAPES   each of Box, Cylinder, Sphere, Tube, Plate (a real click) builds ONE closed solid: volume > 0, one body, no failed step
##   4 EXAMPLES "More examples" (a real click) opens What to build; from there "From a template" lists the weapons, and Sword opens the sword in Easy Part
## Shots in C:/Temp/claude/freestart/ . Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/freestart"
const DIRT := "user://freestart_test"


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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	# a real start: Easy Part opened from the BUILD bar on a blank part (the Part button, then its Easy button)
	m.S.part = {}
	pu().set_on(false)
	await idle(4)
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(30)
	var feats: Array = m.S.part.get("features", [])

	# 2 DEFAULT
	ok(feats.is_empty(), "2a DEFAULT a blank Easy Part opens empty (%d steps)" % feats.size())
	ok(String(m.S.part.get("easy", {}).get("t", "")) == "", "2b DEFAULT no template (no sword) is forced")
	var emp: Button = root.find_child("easypart_chip_empty", true, false) as Button
	ok(emp != null and emp.button_pressed, "2c DEFAULT the Empty chip is lit")

	# 1 ROW
	await shot("row")
	var row_ok := true
	for nm in ["box", "cylinder", "sphere", "tube", "plate"]:
		row_ok = row_ok and visible_chip(nm)
	ok(row_ok, "1a ROW Box, Cylinder, Sphere, Tube, Plate are shown in the Start from row")
	var weapons_shown := []
	for nm in ["sword", "axe", "shield", "chair", "crate"]:
		if visible_chip(nm):
			weapons_shown.append(nm)
	ok(weapons_shown.is_empty(), "1b ROW no weapon chip is shown %s" % str(weapons_shown))
	var more := root.find_child("easypart_more_examples", true, false) as Button
	ok(more != null and more.is_visible_in_tree(), "1c ROW \"More examples\" is shown")

	# 3 SHAPES: a real click on each, then one closed solid
	for nm in ["box", "cylinder", "sphere", "tube", "plate"]:
		var c := chip(nm)
		if c == null or not c.is_visible_in_tree():
			ok(false, "3 SHAPES %s: no chip to click" % nm)
			continue
		await click_ctl(c)
		await idle(20)
		var rec: Dictionary = m.S.part
		var bodies := int(pu().res.get("bodies", 0))
		var errs: int = Part.replay(rec)["errors"].size()
		ok(vol() > 0.0 and bodies == 1 and errs == 0 and String(rec.get("easy", {}).get("t", "")) == nm,
			"3 SHAPES %s: one closed solid (volume %.0f cm3, bodies %d, failed steps %d)" % [nm, vol() * 1.0e6, bodies, errs])
		if nm == "box":
			await shot("box")

	# 4 EXAMPLES: More examples -> What to build -> From a template -> Sword
	if more != null and more.is_visible_in_tree():
		await click_ctl(more)
		await idle(10)
	var bc: BuildChoose = m.build_choose
	ok(bc != null and bc.open, "4a EXAMPLES More examples opens What to build")
	if bc != null and bc.open:
		await click_ctl(bc.btns["template"]["easy"])
		await idle(4)
		var sp = bc._starters
		var idx := -1
		if sp != null:
			for i in sp.item_count:
				if sp.get_item_text(i).contains("Sword"):
					idx = i
		ok(idx >= 0, "4b EXAMPLES the weapons are in What to build (Sword listed)")
		if idx >= 0:
			sp.id_pressed.emit(sp.get_item_id(idx))
			await idle(30)
			ok(String(m.S.part.get("easy", {}).get("t", "")) == "sword" and int(pu().res.get("bodies", 0)) >= 1,
				"4c EXAMPLES Sword opens a sword in Easy Part")
	await shot("examples")
	print("freestart: %d failing" % fails)
	quit(0 if fails == 0 else 1)
