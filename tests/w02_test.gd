extends SceneTree
## godot --headless --path . -s tests/w02_test.gd     (W02 SKETCH HEALTH: free / fully defined / over-constrained; scripts/build/part_health.gd; needs the CAD DLL)
## Bars, written before measuring (a rectangle of four Lines drawn by real clicks, 4 Coincident, Horizontal bottom+top, Vertical both sides):
##   1 FREE      no dimensions: status says "2 free" (width, height); every line is drawn blue (free)
##   2 PARTWAY   length of the bottom only: "1 free"; length of bottom + right: "fully defined", every line green
##   3 REDUNDANT all 4 lengths set (2 repeat what the shape already says): still "fully defined" (not over-constrained)
##   4 CLASH     a second length on the bottom line (60 vs 100) planted in the record: state over, the text names BOTH
##               "length 100 mm" and "length 60 mm", clash_dims has both, every line red
##   5 UNCHANGED analyze() leaves the sketch untouched (JSON equal) and Part.solve gives the same coordinates before and after (1e-9)
##   6 CONTROL   the old words ("fully defined" for the bare rectangle, or "2 free" for the clashing one) are NOT produced: the bar can fail
##   7 SIZES     the status line carries the health at 1024x600 and 1920x1080; shots in C:/Users/Nick/tools/kine_workers/out/w02/
const SHOT := "C:/Users/Nick/tools/kine_workers/out/w02"
const DIRT := "user://w02_test"
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
	var h: Dictionary = PartHealth.analyze(sk)
	ok(h["state"] == "free" and h["free"] == 2 and h["text"] == "2 free", "1 bare rectangle: '%s'" % h["text"])
	ok(all_color(h, n, PartHealth.FREE_C), "1 every line blue (free)")
	ok(h["text"] != "fully defined", "6 CONTROL the bar can fail: the bare rectangle is not 'fully defined'")
	ok(String(pu._profile_ok).contains("2 free"), "1 the status line says it: '%s'" % pu._profile_ok)
	await shot("w02_free_1280")

	Part.set_dim(sk, 0, "len", 100.0)
	h = PartHealth.analyze(sk)
	ok(h["text"] == "1 free", "2 bottom length only: '%s'" % h["text"])
	Part.set_dim(sk, 1, "len", 60.0)
	Part.solve(sk)
	h = PartHealth.analyze(sk)
	ok(h["state"] == "defined" and h["text"] == "fully defined", "2 bottom + right: '%s'" % h["text"])
	ok(all_color(h, n, PartHealth.DEFINED_C), "2 every line green")
	pu._after_sketch_edit()
	await idle(3)
	ok(String(pu._profile_ok).contains("fully defined"), "2 status line: '%s'" % pu._profile_ok)
	await shot("w02_defined_1280")

	Part.set_dim(sk, 2, "len", 100.0)
	Part.set_dim(sk, 3, "len", 60.0)
	Part.solve(sk)
	h = PartHealth.analyze(sk)
	ok(h["state"] == "defined", "3 all four lengths (two repeat): '%s'" % h["text"])

	# 5 UNCHANGED + 4 CLASH
	var base_ents := snap_ents(sk)
	var a: Dictionary = sk.duplicate(true)
	Part.solve(a)
	var before := snap_ents(sk)
	PartHealth.analyze(sk)
	var b: Dictionary = sk.duplicate(true)
	Part.solve(b)
	ok(snap_ents(sk) == before and snap_ents(sk) == base_ents, "5 analyze left the sketch untouched")
	var worst := 0.0
	for i in 4:
		for key_ in ["a", "b"]:
			for q in 2:
				worst = maxf(worst, absf(float(a["ents"][i][key_][q]) - float(b["ents"][i][key_][q])))
	ok(worst < 1e-9, "5 solver gives the same coordinates before/after analyze: worst %s" % worst)
	var dims: Array = sk["dims"]
	dims.resize(2)   # the clash is planted on the sketch with its two real lengths (100, 60), not the repeats
	dims.append({"id": "dX", "ent": 0, "kind": "len", "mm": 60.0, "name": "length9"})   # planted in the record (the UI refuses it, a loaded file need not)
	h = PartHealth.analyze(sk)
	var cl: Array = h["clash"]
	ok(h["state"] == "over", "4 conflicting length: state %s" % h["state"])
	ok(cl.size() == 2 and String(h["text"]).contains("length 100 mm") and String(h["text"]).contains("length 60 mm"), "4 names both: '%s'" % h["text"])
	ok((h["clash_dims"] as Array).size() == 2 and all_color(h, n, PartHealth.OVER_C), "4 both marked, lines red")
	ok(h["text"] != "2 free", "6 CONTROL the clashing sketch is not '2 free'")
	pu._after_sketch_edit()
	await idle(3)
	ok(String(pu._profile_ok).contains("over-constrained"), "4 status line: '%s'" % pu._profile_ok)
	await shot("w02_over_1280")
	# 7 sizes
	for sz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
		root.size = sz
		root.content_scale_size = sz
		await idle(6)
		ok(String(pu._profile_ok).contains("over-constrained"), "7 %s status still carries the health" % sz)
		await shot("w02_over_%dx%d" % [sz.x, sz.y])
	print("w02: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)


