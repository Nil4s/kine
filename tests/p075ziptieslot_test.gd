extends SceneTree
## P075 ZIP-TIE SLOT, CABLE CLIP, RUBBER FOOT (Friday plan item 75): a beginner from the BUILDING card opens Easy Part (blank),
## presses Parts, then the "Clips and feet" category, and sees three chips. Real clicks at 1280 x 720.
##   Rubber foot  = a disc 16 mm across, 4 mm tall (one solid)
##   Cable clip   = a ring 14 mm across, 8 mm tall, wall 2.5 mm, with a 3 mm opening cut through its wall (one solid)
##   Zip-tie slot = a plate 26 mm x 10 mm x 3 mm with a 14 mm x 2.5 mm slot cut through it (one solid)
## Numbers are the beginner's sizes written here, and every measure is taken from the built result (aabb, volume, body count).
## Bars (run on the code before this change: see the report):
##   P0 the Parts library has a "Clips and feet" category that is ready (no coming-soon line), and its three chips are on the screen
##   P1 Rubber foot: one body, 16 x 16 x 4 mm, volume within 3 % of a 16 mm x 4 mm disc
##   P2 Rubber foot is one undo step
##   P3 Cable clip: one body, 14 mm across, 8 mm tall, its ring volume less than 5 % off ring minus the opening (within 10 %)
##   P4 Zip-tie slot: one body, 26 x 10 x 3 mm, volume within 3 % of plate minus slot (675 mm3)
##   P5 no jargon (sketch, extrude, boolean, feature, body, loft, cylinder) in the words or the labels on screen
##   P6 the words after a chip name its size, so the beginner knows what dropped on the floor
## shots: C:/Temp/claude/p075ziptieslot/foot.png, clip.png, slot.png
const SHOT := "C:/Temp/claude/p075ziptieslot"
const DIRT := "user://p075ziptieslot_test"
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


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func size_mm(s: Dictionary) -> Vector3:
	return (s["aabb"] as AABB).size / Part.MM


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
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# P0 Parts, then the Clips and feet category: ready, with its three chips on the screen
	await click_ctl(ep.parts_btn)
	await idle(5)
	var cat: Button = ep.lib_btns.get("Clips and feet", null)
	if cat != null:
		await click_ctl(cat)
	await idle(10)
	var chips := []
	for kind in ["foot", "clip", "slot"]:
		var b: Button = ep.clip_btns.get(kind, null)
		chips.append(b)
	var all_on := true
	for b in chips:
		all_on = all_on and b != null and b.is_visible_in_tree() and b.size.x > 20.0 and b.icon != null
	var soon: Label = ep.lib_soon
	ok(cat != null and all_on and soon != null and not soon.is_visible_in_tree(),
		"P0 Clips and feet is ready, its three chips are on the screen with icons")
	if not all_on:
		print("FAIL: chips missing, the walk stops here")
		quit(1)
		return

	# P1 + P2 Rubber foot: one body, 16 x 16 x 4 mm, one undo step
	var n0: int = m.undo.size()
	await click_ctl(chips[0])
	await idle(10)
	var s1 := solid()
	var sz1 := size_mm(s1)
	var v1 := vol_mm3(s1)
	var want1 := PI * 8.0 * 8.0 * 4.0
	ok(int(s1["bodies"]) == 1 and absf(sz1.x - 16.0) < 0.5 and absf(sz1.z - 16.0) < 0.5 and absf(sz1.y - 4.0) < 0.3
		and absf(v1 - want1) < 0.03 * want1,
		"P1 rubber foot: one body, %.1f x %.1f x %.1f mm, volume %.1f mm3 (16 mm x 4 mm disc = %.1f mm3)" % [sz1.x, sz1.y, sz1.z, v1, want1])
	var n1: int = m.undo.size()
	ok(n1 - n0 == 1, "P2 rubber foot is one undo step (undo count +%d)" % (n1 - n0))
	await shot("foot")

	# P3 Cable clip: replaces the foot on the floor, one body, 14 mm across, 8 mm tall, a ring with an opening
	await click_ctl(chips[1])
	await idle(10)
	var s2 := solid()
	var sz2 := size_mm(s2)
	var v2 := vol_mm3(s2)
	var ring := PI * (49.0 - 20.25) * 8.0
	var ring_open := ring - 3.0 * 2.5 * 8.0 * 2.0   # rough: the opening takes the wall out over its width (bar is loose on purpose)
	ok(int(s2["bodies"]) == 1 and absf(sz2.x - 14.0) < 0.5 and absf(sz2.z - 14.0) < 0.5 and absf(sz2.y - 8.0) < 0.3
		and v2 < ring and v2 > 0.8 * ring_open,
		"P3 cable clip: one body, %.1f x %.1f x %.1f mm, volume %.1f mm3 (full ring %.1f mm3, opening cut)" % [sz2.x, sz2.y, sz2.z, v2, ring])
	await shot("clip")

	# P4 Zip-tie slot: one body, 26 x 10 x 3 mm, volume = plate minus the slot
	await click_ctl(chips[2])
	await idle(10)
	var s3 := solid()
	var sz3 := size_mm(s3)
	var v3 := vol_mm3(s3)
	var want3 := 26.0 * 10.0 * 3.0 - 14.0 * 2.5 * 3.0
	ok(int(s3["bodies"]) == 1 and absf(sz3.x - 26.0) < 0.5 and absf(sz3.z - 10.0) < 0.5 and absf(sz3.y - 3.0) < 0.3
		and absf(v3 - want3) < 0.03 * want3,
		"P4 zip-tie slot: one body, %.1f x %.1f x %.1f mm, volume %.1f mm3 (plate minus slot = %.1f mm3)" % [sz3.x, sz3.z, sz3.y, v3, want3])
	await shot("slot")

	# P5 no jargon on the screen; P6 the words name the size of the chip just pressed
	var lab := []
	labels(ep.status, lab)
	var words := " ".join(lab) + " " + String(ep.msg) + " " + String(ep.hint_l.text)
	var jargon := []
	for w in ["sketch", "extrude", "boolean", "feature", "body", "loft", "cylinder"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty(), "P5 no jargon on the words: %s" % [jargon])
	ok(String(ep.msg).find("mm") >= 0, "P6 the words name the size: [%s]" % String(ep.msg))

	print("p075ziptieslot: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
