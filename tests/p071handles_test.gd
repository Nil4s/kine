extends SceneTree
## P071 HANDLES (Friday plan 71: drawer pull, knob, D-handle, sized). A beginner from the REAL start screen picks handles from the Parts library
## with real clicks at 1280 x 720, never having read a manual.
##   BUILDING card -> Easy Part (blank) -> Parts -> Handles (library page) -> a size chip: the handle drops on the floor.
## Nine size chips: Drawer pull 96 / 128 / 160 mm (hole spacing), Knob 24 / 32 / 40 mm, D-handle 96 / 128 / 160 mm (width).
## Every size is measured from the built result (the replay's box in mm, the solid's volume in mm3), never from the code's own numbers.
## Bars (run on the old code before the change, see the report; H0 fails there: Handles said "coming soon" and had no chips):
##   H0 Parts -> Handles: nine size chips appear (no "coming soon"), the page names the next step
##   H1 Drawer pull 128 mm: one body, a 156 mm bar (128 mm holes + 14 mm each end), 10 mm thick, two real holes (volume ~18400 mm3, not 18720)
##   H2 Knob 32 mm: one body, 32 mm across, 18 mm tall, a solid cylinder (volume 14476 mm3 +-4 %)
##   H3 D-handle 128 mm: one body, 128 mm wide, a hollow loop (volume 26280 mm3 +-4 %, a block would be 46080)
##   H4 a size chip on a handle already on the floor CHANGES that handle (one body, the same part): the D-handle 128 -> 96 is 96 mm
##      wide; one undo step; the same size again does nothing (no undo step)
##   H5 the pull 128 -> 160 -> 128: 188 mm, then 156 mm again, one body, one undo step per pick, no failed step
##   H6 the status words say mm and no jargon (sketch, extrude, revolve, feature, body, loft, boolean)
## shots: C:/Temp/claude/p071handles/page.png, pull.png, knob.png, dhandle.png
const SHOT := "C:/Temp/claude/p071handles"
const DIRT := "user://p071handles_test"
var fails := 0
var m: Node
const JARGON := ["sketch", "extrude", "revolve", "feature", "body", "loft", "boolean", "op "]


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
	if c == null:   # a missing control is a FAIL line, not a crash
		fails += 1
		print("FAIL missing control (a chip that the page does not show)")
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


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the size chip a beginner presses (Easy Part keeps one per size); a missing chip is a FAIL, not a crash
func chip(ep: Node, kind: String, size: int) -> Button:
	return (ep.handle_btns as Dictionary).get("%s_%d" % [kind, size]) if "handle_btns" in ep else null


func words_of(ep: Node) -> String:   # the line under the sizes (what the beginner reads after a pick) and the solid's line
	return String(ep.hint_l.text) + " " + String(ep.status_l.text)


func jargon_in(s: String) -> Array:
	var out := []
	for w in JARGON:
		if s.to_lower().find(w) >= 0:
			out.append(w)
	return out


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
	await click_ctl(ss._cards["building"])   # a beginner clicks the card itself
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)   # the beginner presses the Easy the words named
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(30)

	# H0 the Parts library: Handles opens nine size chips (three kinds, three sizes), not "coming soon"
	await click_ctl(ep.parts_btn)
	await idle(3)
	var hb: Button = ep.lib_btns.get("Handles")   # the library chip (Easy Part keeps one per category)
	if hb != null:
		await click_ctl(hb)
	await idle(5)
	var n_chips := 0
	for kind in ["drawer_pull", "knob", "d_handle"]:
		for sz in [96, 128, 160] if kind != "knob" else [24, 32, 40]:
			var c := chip(ep, kind, sz)
			if c != null and c.is_visible_in_tree():
				n_chips += 1
	var lib_words := String(ep.lib_soon.text) if "lib_soon" in ep and ep.lib_soon != null else ""
	ok(n_chips == 9 and lib_words.find("coming soon") < 0,
		"H0 Parts -> Handles: %d of 9 size chips shown, the page says [%s]" % [n_chips, lib_words])
	await shot("page")

	# H1 Drawer pull 128 mm: a bar of 156 mm, 10 mm thick, two holes
	var ub: int = m.undo.size()
	await click_ctl(chip(ep, "drawer_pull", 128))
	await idle(10)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	var v1 := vol_mm3(s1)
	var lx := bb1.size.x * 1000.0
	var lz := bb1.size.z * 1000.0
	ok(int(s1["bodies"]) == 1 and absf(lx - 156.0) < 1.5 and absf(lz - 10.0) < 0.6 and v1 > 17800.0 and v1 < 18950.0 and (s1["errors"] as Dictionary).is_empty(),
		"H1 drawer pull 128: one body, %.1f x %.1f mm long/thick (want 156 x 10), volume %.0f mm3 (want ~18400: a solid bar is 18720)" % [lx, lz, v1])
	await shot("pull")

	# H2 Knob 32 mm: a cylinder 32 across and 18 tall
	await click_ctl(chip(ep, "knob", 32))
	await idle(10)
	var s2 := solid()
	var bb2: AABB = s2["aabb"]
	var v2 := vol_mm3(s2)
	ok(int(s2["bodies"]) == 1 and absf(bb2.size.x * 1000.0 - 32.0) < 0.6 and absf(bb2.size.y * 1000.0 - 18.0) < 0.6 and absf(v2 - 14476.0) < 0.04 * 14476.0 and (s2["errors"] as Dictionary).is_empty(),
		"H2 knob 32: one body, %.1f mm across, %.1f mm tall (want 32 x 18), volume %.0f mm3 (want 14476 +-4 %%)" % [bb2.size.x * 1000.0, bb2.size.y * 1000.0, v2])
	await shot("knob")

	# H3 D-handle 128 mm: a hollow loop 128 wide
	await click_ctl(chip(ep, "d_handle", 128))
	await idle(10)
	var s3 := solid()
	var bb3: AABB = s3["aabb"]
	var v3 := vol_mm3(s3)
	ok(int(s3["bodies"]) == 1 and absf(bb3.size.x * 1000.0 - 128.0) < 0.6 and absf(v3 - 26280.0) < 0.04 * 26280.0 and (s3["errors"] as Dictionary).is_empty(),
		"H3 D-handle 128: one body, %.1f mm wide (want 128), volume %.0f mm3 (want 26280 +-4 %%, a block is 46080)" % [bb3.size.x * 1000.0, v3])
	await shot("dhandle")

	# H4 a size chip changes the handle on the floor: the D-handle 128 -> 96 (one body, one undo step); the same size again does nothing
	var ub4: int = m.undo.size()
	await click_ctl(chip(ep, "d_handle", 96))
	await idle(10)
	var s4 := solid()
	var bb4: AABB = s4["aabb"]
	var ub4a: int = m.undo.size()
	await click_ctl(chip(ep, "d_handle", 96))
	await idle(10)
	var ub4b: int = m.undo.size()
	ok(int(s4["bodies"]) == 1 and absf(bb4.size.x * 1000.0 - 96.0) < 0.6 and ub4a == ub4 + 1 and ub4b == ub4a,
		"H4 D-handle 128 -> 96: one body, %.1f mm wide (want 96), one undo step (%d -> %d), the same size again adds none (-> %d)" % [bb4.size.x * 1000.0, ub4, ub4a, ub4b])

	# H5 the pull on the floor, 128 -> 160 mm: 188 mm long, still one body, one undo step
	await click_ctl(chip(ep, "drawer_pull", 160))
	await idle(10)
	var bb5w: AABB = solid()["aabb"]
	var ub5: int = m.undo.size()
	await click_ctl(chip(ep, "drawer_pull", 128))
	await idle(10)
	var s5 := solid()
	var bb5: AABB = s5["aabb"]
	ok(int(s5["bodies"]) == 1 and absf(bb5.size.x * 1000.0 - 156.0) < 1.5 and bb5w.size.x * 1000.0 > 185.0 and m.undo.size() == ub5 + 1 and (s5["errors"] as Dictionary).is_empty(),
		"H5 pull 160 (%.1f mm long, want 188) -> 128 (%.1f mm, want 156): one body, one undo step, no failed step" % [bb5w.size.x * 1000.0, bb5.size.x * 1000.0])
	var words := words_of(ep)
	var jg := jargon_in(words)
	ok(jg.is_empty() and words.find("mm") >= 0,
		"H6 the words say mm and no jargon %s: [%s]" % [jg, String(ep.status_l.text)])
	await shot("final")
	print("p071handles: %d fail" % fails)
	quit(1 if fails > 0 else 0)
