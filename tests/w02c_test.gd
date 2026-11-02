extends SceneTree
## godot --headless --path . -s tests/w02c_test.gd     (W02c: x / y position dimensions from the UI)
## Bars, written before measuring:
##   A CONTROL  a rectangle drawn away from the origin with width + height (typed by the Dimension tool) reads "2 free"
##   B DEFINED  + x and y by clicking its corner (x typed "3 cm", y typed "20") reads "fully defined"; the rect's first corner is (30, 20)
##   C MOVES    changing x in the dimension list to 50 moves the rectangle: a.x == 50, size unchanged, still "fully defined"
##   D REFUSE   text that is no length ("abc") leaves the x dim unchanged
##   E PALETTE  no new button: the palette is untouched (checked by partws)
const SHOT := "C:/Users/Nick/tools/kine_workers/out/w02c"
const DIRT := "user://w02c_test"
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


func key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e, true)
	await idle(2)


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## a Part tool as a user reaches it: its own ribbon button (the rule row shows while Constrain is open)
func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	for pair in m.ui_caps.get("BUILD", []):   # Constrain (like Dimension) lives under its SKETCH caption
		if (pair[1] as Array).has(b):
			await click_ctl(pair[0])
			(pair[0] as MenuButton).get_popup().hide()
			m._run_tool(b, pair[0])
			await idle(2)
			return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	var i: int = m._more_tools.find(b)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


func type_in(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	var sa := InputEventKey.new()   # select all, then type over it
	sa.keycode = KEY_A
	sa.physical_keycode = KEY_A
	sa.ctrl_pressed = true
	sa.pressed = true
	root.push_input(sa, true)
	await process_frame
	for ch in txt:
		var e := InputEventKey.new()
		e.keycode = KEY_0 + int(ch)
		e.physical_keycode = KEY_0 + int(ch)
		e.unicode = ch.unicode_at(0)
		e.pressed = true
		root.push_input(e, true)
		await process_frame
	await key(KEY_ENTER)


## the screen point of a sketch point (mm) on the Front plane
func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func ps() -> String:
	return JSON.stringify(m.S.part) if not m.S.part.is_empty() else "{}"


## the angle between two lines (deg, 0..180) from the sketch's ends
func angle_of(ents: Array, a: int, b: int) -> float:
	var da := Part.v2(ents[a]["b"]) - Part.v2(ents[a]["a"])
	var db := Part.v2(ents[b]["b"]) - Part.v2(ents[b]["a"])
	return rad_to_deg(acos(clampf(da.normalized().dot(db.normalized()), -1.0, 1.0)))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image() if root.get_texture() != null else null
	if img != null:
		img.save_png("%s/%s.png" % [SHOT, nm])


func edit_text(t: String) -> void:
	m.bld.part.dim_edit.text = t
	await key(KEY_ENTER)


func health() -> String:
	return String(PartHealth.analyze(m.bld.part._sk())["text"])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
		return
	for sz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.size = sz
		root.content_scale_size = sz
		await idle(6)
		ss.show_screen()
		await idle(3)
		await click_ctl(ss._cards["building"])
		if m.ui_save_ask != null and m.ui_save_ask.visible:
			m._save_ask_choose("discard")
		await idle(6)
		pu.set_on(false)
		pu.m.S.part = {}
		await process_frame
		await click_ctl(pu.part_btn)
		await idle(3)
		await click_ctl(pu.browser.find_child("part_plane_front", true, false))
		ok(pu.sk != "", "%s Front plane sketch" % sz)
		await press_tool(pu, "Rectangle")
		await ev_move(sp2(30, 20), false)
		await ev_mouse(sp2(30, 20), true)
		await ev_move(sp2(110, 60))
		await ev_mouse(sp2(110, 60), false)
		await key(KEY_ESCAPE)
		var sk: Dictionary = pu._sk()
		ok((sk["ents"] as Array).size() == 1 and sk["ents"][0]["k"] == "rect", "%s one rectangle drawn" % sz)
		var r0: Dictionary = sk["ents"][0]
		var a0 := Part.v2(r0["a"])
		var b0 := Part.v2(r0["b"])
		print("   rect ", a0, b0)
		ok(a0.length() > 5.0 and b0.length() > 5.0, "%s rectangle is away from the origin" % sz)
		await press_tool(pu, "Dimension")
		var wa := Vector2(minf(a0.x, b0.x), a0.y)
		var wb := Vector2(maxf(a0.x, b0.x), a0.y)
		await click_at(sp2((wa.x + wb.x) * 0.5, a0.y))   # width: the middle of the edge
		await edit_text("80")
		var ha := Vector2(a0.x, (a0.y + b0.y) * 0.5)
		await click_at(sp2(a0.x, ha.y))   # height: the middle of the side
		await edit_text("40")
		sk = pu._sk()
		ok(health() == "2 free", "A CONTROL width + height only, away from origin: '%s'" % health())
		await shot("a_%dx%d" % [sz.x, sz.y])
		var a1 := Part.v2(sk["ents"][0]["a"])
		await click_at(sp2(a1.x, a1.y))   # a corner
		ok(pu.dim_edit.visible and pu.dim_target.get("kind", "") == "x", "%s corner click asks for x" % sz)
		await edit_text("3 cm")
		ok(pu.dim_edit.visible and pu.dim_target.get("kind", "") == "y", "%s then asks for y" % sz)
		await edit_text("20")
		sk = pu._sk()
		print("   dims ", JSON.stringify(sk["dims"]))
		var ra: Vector2 = Part.v2(sk["ents"][0]["a"])
		ok(is_equal_approx(ra.x, 30.0) and is_equal_approx(ra.y, 20.0), "B corner at (30, 20) mm: %s" % ra)
		ok(health() == "fully defined", "B width, height, x, y: '%s'" % health())
		await shot("b_%dx%d" % [sz.x, sz.y])
		# C: change x from the list
		var xi := -1
		for i in sk["dims"].size():
			if sk["dims"][i]["kind"] == "x":
				xi = i
		var le: LineEdit = pu.nums_vb.find_child("part_dim_%d" % xi, true, false)
		ok(le != null, "C the x row is in the dimension list")
		if le != null:
			le.text = "50"
			le.text_submitted.emit("50")
			await idle(4)
		sk = pu._sk()
		var rb: Dictionary = sk["ents"][0]
		var wd := absf(Part.v2(rb["b"]).x - Part.v2(rb["a"]).x)
		ok(is_equal_approx(Part.v2(rb["a"]).x, 50.0) and is_equal_approx(wd, 80.0), "C x=50 moves it, width still 80: a=%s w=%s" % [rb["a"], wd])
		ok(health() == "fully defined", "C still fully defined: '%s'" % health())
		# D: junk is refused
		var dm0 := JSON.stringify(sk["dims"])
		var er: String = pu._set_dim_text(0, "x", "abc")
		ok(er != "" and JSON.stringify(pu._sk()["dims"]) == dm0, "D 'abc' refused: '%s'" % er)
		await shot("c_%dx%d" % [sz.x, sz.y])
	print("w02c: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
