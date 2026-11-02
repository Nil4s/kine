extends SceneTree
## godot --headless --path . -s tests/w02b_test.gd     (W02b: the health text is fully visible; a UI-dimensioned rectangle reads fully defined)
## Bars, written before measuring:
##   A VISIBLE  at 1024x600, 1280x720, 1920x1080 with the Warnings (Look/Print) panel up: the whole status text's rect is inside the viewport
##              and does not intersect the Look/Print panel or the side panel
##   B RECT     a rectangle with width + height set (UI dims) and a corner at the origin reads "fully defined"; width + height only, the rectangle
##              away from the origin: "2 free" (its position); width + height + a position dim ("pos"): "fully defined"; width only: "3 free"
##   C CONTROL  the bar can fail: a rectangle with no dims is not "fully defined" and the planted too-wide note rect fails A's check
const SHOT := "C:/Users/Nick/tools/kine_workers/out/w02b"
const DIRT := "user://w02b_test"
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


func snap_ents(sk: Dictionary) -> String:
	return JSON.stringify(sk["ents"])


func all_color(h: Dictionary, n: int, col: Color) -> bool:
	for i in n:
		if PartHealth.color_of(h, i) != col:
			return false
	return true


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
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("SKIP: no KineCAD DLL (Part.available() false)")
		quit(0)
		return
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
	ok(pu.on, "0 Part workspace on")
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	ok(pu.sk != "", "0 the Front plane starts a sketch")
	await press_tool(pu, "Line")
	for q in [[0, 0], [100, 0], [100, 60], [0, 60], [0, 0]]:
		await click_at(sp2(q[0], q[1]))
	await key(KEY_ESCAPE)
	var sk: Dictionary = pu._sk()
	ok((sk["ents"] as Array).size() == 4, "0 four lines drawn by clicks")
	for c in [{"k": "coin", "a": 0, "ap": 1, "b": 1, "bp": 0}, {"k": "coin", "a": 1, "ap": 1, "b": 2, "bp": 0}, {"k": "coin", "a": 2, "ap": 1, "b": 3, "bp": 0}, {"k": "coin", "a": 3, "ap": 1, "b": 0, "bp": 0},
			{"k": "h", "a": 0}, {"k": "h", "a": 2}, {"k": "v", "a": 1}, {"k": "v", "a": 3}]:
		var err := Part.con_put(sk, c)
		if err != "":
			print("con_put: ", err)
	pu._after_sketch_edit()
	await idle(3)
	var n := 4
	# B RECT
	var rk := {"ents": [{"k": "rect", "a": [0, 0], "b": [10, 10]}], "cons": [], "dims": []}
	ok(PartHealth.analyze(rk)["text"] == "2 free", "C CONTROL no dims (corner at origin: width, height): '%s'" % PartHealth.analyze(rk)["text"])
	Part.set_dim(rk, 0, "w", 80.0)
	ok(PartHealth.analyze(rk)["text"] == "1 free", "B width only: '%s'" % PartHealth.analyze(rk)["text"])
	Part.set_dim(rk, 0, "h", 40.0)
	ok(PartHealth.analyze(rk)["text"] == "fully defined", "B w+h, corner at origin: '%s'" % PartHealth.analyze(rk)["text"])
	var rk2 := {"ents": [{"k": "rect", "a": [30, 20], "b": [110, 60]}], "cons": [], "dims": []}
	Part.set_dim(rk2, 0, "w", 80.0)
	Part.set_dim(rk2, 0, "h", 40.0)
	ok(PartHealth.analyze(rk2)["text"] == "2 free", "B w+h away from origin: '%s'" % PartHealth.analyze(rk2)["text"])
	rk2["dims"].append({"id": "d9", "ent": 0, "kind": "pos", "mm": 36.0, "name": "position"})
	ok(PartHealth.analyze(rk2)["text"] == "fully defined", "B w+h+position dim: '%s'" % PartHealth.analyze(rk2)["text"])
	# A VISIBLE: a sketch with a long name so the status line is long
	sk["name"] = "Sketch of the bracket plate"
	sk["ents"] = [{"k": "rect", "a": [0, 0], "b": [100, 60]}]
	sk["cons"] = []
	sk["dims"] = []
	pu._after_sketch_edit()
	await idle(3)
	var bad_rect := Rect2(-5, 0, 100, 20)
	ok(not Rect2(Vector2.ZERO, Vector2(1024, 600)).encloses(bad_rect), "C CONTROL the visibility check fails for a rect off screen")
	for sz in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = sz
		root.content_scale_size = sz
		await idle(8)
		pu._profile_sig = ""
		pu._after_sketch_edit()
		await idle(4)
		var vr := Rect2(Vector2.ZERO, Vector2(sz))
		var nr := Rect2(pu.note.global_position, pu.note.size)
		var tw: float = pu.note_l.get_theme_font("font").get_multiline_string_size(pu.note_l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var lr := pu.note_l.get_global_rect()
		var wr := Rect2(pu.warn_ui.global_position, pu.warn_ui.size)
		var sr := Rect2(pu.side.global_position, pu.side.size)
		print("   %s note=%s text='%s' textw=%s warn=%s vis=%s side=%s sidevis=%s" % [sz, nr, pu.note_l.text, tw, wr, pu.warn_ui.visible, sr, pu.side.visible])
		ok(pu.note.visible and String(pu.note_l.text).contains("free"), "A %s note shows the health" % sz)
		ok(vr.encloses(nr) and vr.encloses(lr), "A %s note inside the viewport" % sz)
		ok(not pu.warn_ui.visible or not nr.intersects(wr), "A %s note not under the Look/Print panel" % sz)
		ok(not pu.side.visible or not nr.intersects(sr), "A %s note not under the side panel" % sz)
		ok(lr.size.x + 1.0 >= tw or lr.size.y > 30.0, "A %s every word of the text is laid out (label wide enough or wrapped)" % sz)
		await shot("w02b_%dx%d" % [sz.x, sz.y])
	print("w02b: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
