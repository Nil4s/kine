extends SceneTree
## p096templatesa (Friday plan item 96, Nick: monkey-brain easy): Templates as recipes. Three starters in What to build > Template: a Phone stand
## (a wedge the phone leans on), a Shelf bracket (an L: a shelf leg and an upright) and a Box with lid (a box and its lid lying beside it, 10 mm
## apart). Each is the same record Expert edits: its sliders rewrite only the features it owns, so the part stays fully editable.
## Real clicks at 1280 x 720 from the start screen. Every number is measured from the BUILT result the view shows (the PartUI's res: the replay),
## never from the code's own variables.
##   R0 the Template list (What to build > Template) names all three: Phone stand, Shelf bracket, Box with lid
##   R1 Phone stand (defaults 100 deep, 100 high, 90 wide): one body, box 100 x 100 x 90 mm, volume 450 cm3 (1 pct)
##   R2 its Height slider to 150 mm: box 100 x 150 x 90 mm, volume 675 cm3 (1 pct), still one body, the replay has no failed step
##   R3 the pick is one undo step (the undo list grows by 1 for each recipe pick)
##   R4 Shelf bracket (defaults leg 200, upright 150, thickness 8, width 40): one body, box 200 x 150 x 40 mm, volume 109.4 cm3 (1 pct)
##   R5 its Leg slider to 300 mm: box 300 x 150 x 40 mm, volume 141.4 cm3 (1 pct)
##   R6 Box with lid (defaults 300 wide, 150 high, 200 deep, lid 10 mm): two bodies, box 610 x 150 x 200 mm, volume 9600 cm3 (1 pct)
##   R7 its Lid slider to 20 mm: still two bodies, volume 10200 cm3 (1 pct)
##   R8 the record of each recipe names its template, its owned feature count is the feature count (the recipe owns every step), no failed step
## shots: C:/Temp/claude/p096templatesa/phone.png, shelf.png, lid.png
const SHOT := "C:/Temp/claude/p096templatesa"
const DIRT := "user://p096templatesa_test"
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
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## a real click on the slider's track at value v (the grabber centre sits at v; the track's ends keep half a grabber in)
func slide_to(sl: HSlider, v: float) -> void:
	if sl == null:
		fails += 1
		print("FAIL no slider to move")
		return
	var g := sl.get_theme_icon("grabber")
	var gw := float(g.get_width()) if g != null else 16.0
	var frac := (v - sl.min_value) / maxf(sl.max_value - sl.min_value, 0.0001)
	var lx := gw * 0.5 + frac * (sl.size.x - gw)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_move(p)
	await ev_mouse(p, false)
	await idle(12)


func mm(v: float) -> float:
	return v / Part.MM


## the built result the view shows: bodies, the box's size in mm, the volume in cm3 (from the replayed solids, not the code's numbers)
func built() -> Dictionary:
	var r: Dictionary = m.bld.part.res
	var bb: AABB = r.get("aabb", AABB())
	var vol := 0.0
	for v in r.get("volumes", []):
		vol += float(v)
	return {"bodies": int(r.get("bodies", 0)), "x": mm(bb.size.x), "y": mm(bb.size.y), "z": mm(bb.size.z), "cm3": vol / (Part.MM * Part.MM * Part.MM) / 1000.0}


## a real pick from What to build > Template: the card's Easy button opens the list, the list's item by its text (the same id the menu emits)
func pick(label: String) -> bool:
	var bc: BuildChoose = m.build_choose
	if not bc.open:
		var ob := find_named(m, "build_choose_open") as Control
		if ob != null and ob.is_visible_in_tree():
			await click_ctl(ob)
		else:
			bc.show_chooser()
		await idle(4)
	await click_ctl(bc.btns["template"]["easy"])
	await idle(4)
	var pm: PopupMenu = bc._starters
	if pm == null:
		return false
	for i in pm.item_count:
		if pm.get_item_text(i).begins_with(label):
			pm.id_pressed.emit(pm.get_item_id(i))
			await idle(30)
			return true
	return false


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
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(20)

	var bc: BuildChoose = m.build_choose
	await click_ctl(bc.btns["template"]["easy"])
	await idle(4)
	var pm: PopupMenu = bc._starters
	var names := []
	if pm != null:
		for i in pm.item_count:
			names.append(pm.get_item_text(i))
	var has_all := true
	for lab in ["Part: Phone stand", "Part: Shelf bracket", "Part: Box with lid"]:
		var f := false
		for n in names:
			f = f or String(n).begins_with(lab)
		has_all = has_all and f
	ok(has_all, "R0 What to build > Template names the three recipes: %d items" % names.size())
	if pm != null:
		pm.hide()
	await idle(4)

	# R1 the phone stand: the defaults 100 x 100 x 90 mm, 450 cm3
	var u0: int = m.undo.size()
	var picked := await pick("Part: Phone stand")
	var b1 := built()
	var u1: int = m.undo.size()
	ok(picked and b1["bodies"] == 1 and absf(b1["x"] - 100.0) <= 0.5 and absf(b1["y"] - 100.0) <= 0.5 and absf(b1["z"] - 90.0) <= 0.5 and absf(b1["cm3"] - 450.0) <= 4.5,
		"R1 phone stand built: %d body, box %.1f x %.1f x %.1f mm (want 100 x 100 x 90), volume %.1f cm3 (want 450)" % [b1["bodies"], b1["x"], b1["y"], b1["z"], b1["cm3"]])
	await shot("phone")

	# R2 its Height slider to 150 mm: the box grows taller, still one body, no failed step
	var sl := find_named(m, "easypart_slider_height") as HSlider
	await slide_to(sl, 150.0)
	var b2 := built()
	var rec: Dictionary = m.S.part
	var errs2: int = Part.replay(rec)["errors"].size()
	ok(b2["bodies"] == 1 and absf(b2["y"] - 150.0) <= 0.5 and absf(b2["cm3"] - 675.0) <= 6.75 and errs2 == 0,
		"R2 Height 150: box %.1f x %.1f x %.1f mm (want y 150), volume %.1f cm3 (want 675), failed steps %d" % [b2["x"], b2["y"], b2["z"], b2["cm3"], errs2])

	# R3 one undo step per pick: the phone pick took exactly one step
	ok(u1 - u0 == 1, "R3 the phone pick is one undo step: the undo list %d -> %d" % [u0, u1])

	# R4 the shelf bracket: the defaults 200 x 150 x 40 mm, 109.4 cm3
	var u2: int = m.undo.size()
	picked = await pick("Part: Shelf bracket")
	var b4 := built()
	var u3: int = m.undo.size()
	ok(picked and b4["bodies"] == 1 and absf(b4["x"] - 200.0) <= 0.5 and absf(b4["y"] - 150.0) <= 0.5 and absf(b4["z"] - 40.0) <= 0.5 and absf(b4["cm3"] - 109.44) <= 1.1 and u3 - u2 == 1,
		"R4 shelf bracket built: %d body, box %.1f x %.1f x %.1f mm (want 200 x 150 x 40), volume %.2f cm3 (want 109.44), undo +%d" % [b4["bodies"], b4["x"], b4["y"], b4["z"], b4["cm3"], u3 - u2])
	await shot("shelf")

	# R5 its Leg slider to 300 mm: the shelf leg grows, the upright stays
	await slide_to(find_named(m, "easypart_slider_leg") as HSlider, 300.0)
	var b5 := built()
	ok(b5["bodies"] == 1 and absf(b5["x"] - 300.0) <= 0.5 and absf(b5["y"] - 150.0) <= 0.5 and absf(b5["cm3"] - 141.44) <= 1.5,
		"R5 Leg 300: box %.1f x %.1f x %.1f mm (want 300 x 150 x 40), volume %.2f cm3 (want 141.44)" % [b5["x"], b5["y"], b5["z"], b5["cm3"]])

	# R6 the box with lid: two bodies, the lid lies beside the box with a 10 mm gap
	picked = await pick("Part: Box with lid")
	var b6 := built()
	ok(picked and b6["bodies"] == 2 and absf(b6["x"] - 610.0) <= 0.5 and absf(b6["y"] - 150.0) <= 0.5 and absf(b6["z"] - 200.0) <= 0.5 and absf(b6["cm3"] - 9600.0) <= 96.0,
		"R6 box with lid built: %d bodies (want 2), size %.1f x %.1f x %.1f mm (want 610 x 150 x 200), volume %.1f cm3 (want 9600)" % [b6["bodies"], b6["x"], b6["y"], b6["z"], b6["cm3"]])
	await shot("lid")

	# R7 its Lid slider to 20 mm: the lid is thicker, still two bodies
	await slide_to(find_named(m, "easypart_slider_lid") as HSlider, 20.0)
	var b7 := built()
	ok(b7["bodies"] == 2 and absf(b7["cm3"] - 10200.0) <= 102.0,
		"R7 Lid 20 mm: %d bodies (want 2), volume %.1f cm3 (want 10200)" % [b7["bodies"], b7["cm3"]])

	# R8 the record: each recipe names its template; the template owns every feature (so Expert can edit each step), no failed step
	rec = m.S.part
	var e: Dictionary = rec.get("easy", {})
	var owns := int(e.get("n", -1)) == (rec.get("features", []) as Array).size()
	var errs8: int = Part.replay(rec)["errors"].size()
	ok(String(e.get("t", "")) == "lidbox" and owns and errs8 == 0,
		"R8 the record is the recipe (t %s, owns %d of %d steps, failed steps %d): Expert sees plain steps" % [String(e.get("t", "")), int(e.get("n", -1)), (rec.get("features", []) as Array).size(), errs8])

	print("p096templatesa %d fails" % fails)
	quit(1 if fails > 0 else 0)
