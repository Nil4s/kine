extends SceneTree
## P205 SNAP-FIT CLIP (Friday plan item 205, Kine's own idea): a beginner from the BUILDING card opens Easy Part (blank), presses Parts,
## the "Clips and feet" category, and then the fourth chip, "Snap-fit clip". Real clicks at 1280 x 720.
##   Snap-fit clip = a plate 26 x 19.6 x 3 mm with a U-shaped 0.8 mm gap cut round a 16 mm tongue (the cantilever arm, 10 mm wide),
##   and a 3 x 1.5 mm hook on the tongue's tip. The gap is the matching slot. One solid.
## Every measure is taken from the built result (Part.replay: aabb, volume, body count, undo count), never from the code's variables.
## Bars (written from the design before the code; no run on the old code, the chip is new):
##   S0 the Clips and feet category shows four chips, the new one has an icon and a visible size
##   S1 one click on Snap-fit clip: one body, 26 x 19.6 x 4.5 mm (X, Z, Y) within 0.5 / 0.5 / 0.3 mm
##   S2 its volume is the plate minus the U gap plus the hook: 1469.2 mm3, within 3 pct (the gap alone is 105 mm3, so the gap is measured)
##   S3 one undo step (Ctrl+Z count +1) for the one click
##   S4 the words name the size of the clip in mm, and no jargon (sketch, extrude, boolean, feature, body, loft, cylinder) is on the screen
## shots: C:/Temp/claude/p205snapfitcli/snap.png
const SHOT := "C:/Temp/claude/p205snapfitcli"
const DIRT := "user://p205snapfitcli_test"
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

	# S0 Parts, then Clips and feet: four chips, the new one with an icon and on the screen
	await click_ctl(ep.parts_btn)
	await idle(5)
	var cat: Button = ep.lib_btns.get("Clips and feet", null)
	if cat != null:
		await click_ctl(cat)
	await idle(10)
	var snap_btn: Button = ep.clip_btns.get("snap", null)
	var s0_on: bool = snap_btn != null and snap_btn.is_visible_in_tree() and snap_btn.size.x > 20.0 and snap_btn.icon != null
	ok(s0_on, "S0 Clips and feet shows the Snap-fit clip chip on the screen, with an icon")
	if not s0_on:
		print("FAIL: the Snap-fit clip chip is missing, the walk stops here")
		quit(1)
		return

	# S1 + S2 + S3: one click, one body, the measured size and volume, one undo step
	var n0: int = m.undo.size()
	await click_ctl(snap_btn)
	await idle(10)
	var s1 := solid()
	var sz := size_mm(s1)
	var v := vol_mm3(s1)
	var want := 1469.2
	ok(int(s1["bodies"]) == 1 and absf(sz.x - 26.0) < 0.5 and absf(sz.z - 19.6) < 0.5 and absf(sz.y - 4.5) < 0.3,
		"S1 snap-fit clip: one body, %.2f x %.2f x %.2f mm (want 26 x 19.6 x 4.5)" % [sz.x, sz.z, sz.y])
	ok(absf(v - want) < 0.03 * want,
		"S2 volume %.1f mm3 (plate minus the U gap plus the hook = %.1f mm3, within 3 pct)" % [v, want])
	var n1: int = m.undo.size()
	ok(n1 - n0 == 1, "S3 one click is one undo step (undo count +%d)" % (n1 - n0))
	await shot("snap")

	# S4 the words name the size in mm; no jargon on the screen
	var lab := []
	labels(ep.status, lab)
	var words := " ".join(lab) + " " + String(ep.msg) + " " + String(ep.hint_l.text)
	var jargon := []
	for w in ["sketch", "extrude", "boolean", "feature", "body", "loft", "cylinder"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty() and String(ep.msg).find("mm") >= 0,
		"S4 the words name the size in mm, no jargon: [%s] %s" % [String(ep.msg), jargon])

	print("p205snapfitcli: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
