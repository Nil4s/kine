extends SceneTree
## godot --path . --position 4000,4000 -s tests/c15_test.gd     (C15: complaints #206 sketch moved to another plane with a preview, #414 SVG import with a scale check,
## #633 degrees of freedom left per assembly part; scripts/build/sketch_replane.gd, svg_import.gd, assembly_dof.gd, part_c15_ui.gd)
## BARS (written and committed before the first run; every one has a CONTROL that fails on origin, where these files do not exist, or on a planted wrong value):
##  A #206  a 40 x 20 mm rectangle on Front, moved to Top: preview centre (20,10,0) -> (20,0,-10) mm, shift (0,-10,-10) within 0.001; the preview leaves the record
##          byte-identical; the label says "-10.0"; a REAL click on Move sets plane "top" (one undo step: undo brings "front"); the overlay's corners lie inside the
##          1280x720 view and outside the side palette. An offset plane made AFTER the sketch is not offered. CONTROL: a planted shift (0,0,0) must not match.
##  B #414  SVGs: mm file with matching viewBox = 100 x 50 mm, content 80 x 40, NO warning; unitless 400 x 200 = 105.83 x 52.92 mm and a "no unit" warning;
##          100mm x 100mm over viewBox 100 x 50 = a "mismatch" warning; 2in x 1in path = 50.8 x 25.4 mm, 4 lines; typed real width 60 -> content 60.000 +-0.001;
##          a rect's 4 lines lie in 0..80 x 0..40 (y flipped). A real click on Import SVG adds a sketch of 4 lines and the label starts "File says".
##          CONTROL: reading the unitless file as mm (400 x 200) must fail the 105.83 bar.
##  C #633  an untouched part: 6 of 6 free and NO "lock" key. Lock slide Z + turn X,Y (real clicks on the checks): words are exactly
##          "3 of 6 free: slides along X and Y, turns about Z. Locked: slide along Z and turn about X and Y."; typed Z 50 stays, typed X 30 moves; Fix = 0 of 6, "fixed in place";
##          freeing everything erases the key. The panel lies inside 1280x720. CONTROL: a planted "5 of 6" wording must not equal the 3-of-6 words.
## Shots: C:/Users/Nick/tools/kine_workers/out/c15/
var fails := 0
var m: Node
var pu: PartUI
var A: AssemblyUI
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c15"
const DIRT := "user://c15_test"


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func key(code: int, uni := 0) -> void:
	for dn in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni
		e.pressed = dn
		root.push_input(e, true)
		await process_frame


func type_in(le: LineEdit, text: String) -> void:
	await click_ctl(le)
	le.select_all()
	for ch in text:
		var c := ch.unicode_at(0)
		var kc := KEY_0 + (c - 48) if (c >= 48 and c <= 57) else (KEY_PERIOD if ch == "." else KEY_MINUS)
		await key(kc, c)
	await key(KEY_ENTER)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func svg(w: String, h: String, vb: String, body: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg"%s%s%s>%s</svg>' % [(' width="%s"' % w) if w != "" else "", (' height="%s"' % h) if h != "" else "", (' viewBox="%s"' % vb) if vb != "" else "", body]


func has_warn(rep: Dictionary, word: String) -> bool:
	for w in rep["warnings"]:
		if String(w).contains(word):
			return true
	return false


func engine_bars() -> void:
	var r1 := SvgImport.parse(svg("100mm", "50mm", "0 0 100 50", '<rect x="10" y="5" width="80" height="40"/>'))
	ok(bool(r1["ok"]) and (r1["size_mm"] as Vector2).is_equal_approx(Vector2(100, 50)) and (r1["content_mm"] as Vector2).is_equal_approx(Vector2(80, 40)) and (r1["warnings"] as Array).is_empty(), "B1 mm file with matching viewBox: size %s content %s warnings %s" % [r1["size_mm"], r1["content_mm"], r1["warnings"]])
	var okl := true
	for e in r1["ents"]:
		for k in ["a", "b"]:
			okl = okl and float(e[k][0]) >= -1e-3 and float(e[k][0]) <= 80.001 and float(e[k][1]) >= -1e-3 and float(e[k][1]) <= 40.001
	ok(int(r1["lines"]) == 4 and okl, "B5 a rect is 4 lines inside 0..80 x 0..40 (%d lines)" % int(r1["lines"]))
	var r2 := SvgImport.parse(svg("400", "200", "0 0 400 200", '<rect x="0" y="0" width="400" height="200"/>'))
	var sz2: Vector2 = r2["size_mm"]
	ok(absf(sz2.x - 105.833) < 0.01 and absf(sz2.y - 52.917) < 0.01 and has_warn(r2, "no unit"), "B2 unitless 400 x 200 = %.2f x %.2f mm and a no-unit warning" % [sz2.x, sz2.y])
	ok(not (absf(400.0 - 105.833) < 0.01), "B2 CONTROL: reading it as mm (400) fails the bar")
	var r3 := SvgImport.parse(svg("100mm", "100mm", "0 0 100 50", '<rect x="0" y="0" width="100" height="50"/>'))
	ok(has_warn(r3, "mismatch"), "B3 100 x 100 mm over a 100 x 50 viewBox warns of a mismatch: %s" % [r3["warnings"]])
	var r4 := SvgImport.parse(svg("2in", "1in", "0 0 2 1", '<path d="M0 0 H2 V1 H0 Z"/>'))
	var c4: Vector2 = r4["content_mm"]
	ok(absf(c4.x - 50.8) < 0.001 and absf(c4.y - 25.4) < 0.001 and int(r4["lines"]) == 4, "B4 2in x 1in path = %.3f x %.3f mm, %d lines" % [c4.x, c4.y, int(r4["lines"])])
	var r5 := SvgImport.parse(svg("100mm", "50mm", "0 0 100 50", '<rect x="10" y="5" width="80" height="40"/>'), {"width_mm": 60.0})
	ok(absf((r5["content_mm"] as Vector2).x - 60.0) < 0.001, "B6 typed real width 60: content %.4f" % (r5["content_mm"] as Vector2).x)
	var r6 := SvgImport.parse("hello")
	ok(not bool(r6["ok"]) and String(r6["why"]) != "", "B7 not an SVG says so: %s" % r6["why"])
	var r7 := SvgImport.parse(svg("100mm", "50mm", "0 0 100 50", '<rect x="-80" y="0" width="300" height="50"/>'))
	ok(has_warn(r7, "outside"), "B8 a drawing outside its viewBox warns")
	var rec := Part.make("c15")
	var f := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [40, 20]}], "dims": []})
	rec["features"].append(f)
	var sid := String(f["id"])
	var before := JSON.stringify(rec)
	var pv := SketchReplane.preview(rec, sid, "top")
	var sh: Vector3 = pv["shift_mm"]
	ok(bool(pv["ok"]) and sh.is_equal_approx(Vector3(0, -10, -10)) and (pv["centre_to"] as Vector3).is_equal_approx(Vector3(20, 0, -10)), "A1 Front -> Top: centre %s -> %s, shift %s" % [pv["centre_from"], pv["centre_to"], sh])
	ok(JSON.stringify(rec) == before, "A2 the preview leaves the record byte-identical")
	ok(not sh.is_equal_approx(Vector3.ZERO), "A3 CONTROL: a planted shift (0,0,0) does not match")
	var pl := Part.add_plane(rec, "front", {"mm": 30.0})
	var offered := SketchReplane.targets(rec, sid).map(func(t): return t["name"])
	ok(not offered.has(pl), "A4 a plane made after the sketch is not offered (%s)" % str(offered))


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
	engine_bars()
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	var ss: StartScreen = m.start_screen
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	pu = m.bld.part
	A = m.bld.asm
	# ---- C #633 in the assembly screen
	m.build_choose.show_chooser()
	await idle(4)
	await click_ctl(nd("build_choose_assembly") as Button)
	await idle(4)
	A._add(PartCatalog.make("bracket_l"), "Arm", "")
	A._add(PartCatalog.make("bracket_l"), "Base", "")
	await idle(3)
	var p1: Dictionary = A.asm["parts"][0]
	ok(AssemblyDof.free_count(p1) == 6 and not p1.has("lock") and AssemblyDof.words(p1).begins_with("6 of 6 free"), "C1 an untouched part: 6 of 6 free, no lock key")
	await click_ctl(nd("asm_row_0") as Button)
	for nm in ["asm_lock_pos_2", "asm_lock_rot_0", "asm_lock_rot_1"]:
		await click_ctl(nd(nm) as Button)
	var want := "3 of 6 free: slides along X and Y, turns about Z. Locked: slide along Z and turn about X and Y."
	ok(AssemblyDof.words(p1) == want and (nd("asm_dof") as Label).text == want, "C2 three locks by real clicks: [%s]" % (nd("asm_dof") as Label).text)
	ok(want != "5 of 6 free: slides along X and Y, turns about Z. Locked: slide along Z.", "C3 CONTROL: a planted 5-of-6 wording differs")
	var z0 := float(p1["pos"][2])
	await type_in(nd("asm_pos_z") as LineEdit, "50")
	await type_in(nd("asm_pos_x") as LineEdit, "30")
	ok(float(p1["pos"][2]) == z0 and absf(float(p1["pos"][0]) - 30.0) < 0.001, "C4 typed Z 50 refused (z stays %.2f), typed X 30 moved (x %.2f)" % [float(p1["pos"][2]), float(p1["pos"][0])])
	var rp := AssemblyDof.report(A.asm)
	ok(int(rp["total"]) == 9 and int(rp["of"]) == 12, "C5 report: %d of %d free" % [int(rp["total"]), int(rp["of"])])
	await shot("dof_1280")
	var pr: Rect2 = (nd("asm_panel") as Control).get_global_rect()
	ok(pr.position.x >= 0 and pr.end.x <= 1280.5 and pr.end.y <= 720.5, "C6 the panel lies inside 1280x720: %s" % str(pr))
	await click_ctl(nd("asm_fix") as Button)
	ok(AssemblyDof.free_count(p1) == 0 and AssemblyDof.words(p1) == "0 of 6 free: fixed in place.", "C7 Fix = 0 of 6")
	await click_ctl(nd("asm_fix") as Button)
	ok(AssemblyDof.free_count(p1) == 6 and not p1.has("lock"), "C8 freeing all erases the lock key")
	A.close()
	await idle(4)
	# ---- A #206 and B #414 in the Part workspace
	m.S.part = {}
	pu.set_on(true)
	await idle(4)
	pu.begin_sketch("front")
	pu._sk()["ents"] = [{"k": "rect", "a": [0, 0], "b": [40, 20]}]
	pu.bu.sync()
	await idle(4)
	var c15: PartC15UI = pu.c15
	c15.choose("top")
	await idle(3)
	var lab := (nd("c15_words") as Label).text
	ok(lab.contains("-10.0") and nd("c15_box").is_visible_in_tree(), "A5 the label gives the numbers: [%s]" % lab)
	var pv := c15.preview()
	var inside := true
	var side_r: Rect2 = pu.side.get_global_rect()
	var outside := true
	for w in pv["corners_to"]:
		var sp: Vector2 = m.cam.unproject_position(w)
		inside = inside and Rect2(0, 0, 1280, 720).has_point(sp)
		outside = outside and not side_r.has_point(sp)
	ok(inside, "A6 the preview's corners project inside the 1280x720 view")
	ok(outside, "A7 the preview's corners stay outside the side palette %s" % str(side_r))
	ok(side_r.end.y <= 720.5 and side_r.end.x <= 1280.5, "A8 the palette with the new rows lies inside the window: %s" % str(side_r))
	await shot("move_preview_1280")
	var n_undo: int = m.undo.size()
	await click_ctl(nd("c15_move") as Button)
	ok(String(pu._sk().get("plane", "")) == "top" and m.undo.size() == n_undo + 1, "A9 a real click on Move: plane = %s, one undo step" % String(pu._sk().get("plane", "")))
	m._undo()
	await idle(3)
	ok(String(Part.feature(pu._rec(), pu.sk).get("plane", "")) == "front", "A10 undo puts the sketch back on Front")
	var path := ProjectSettings.globalize_path(DIRT) + "/t.svg"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(svg("100mm", "50mm", "0 0 100 50", '<rect x="10" y="5" width="80" height="40"/>'))
	fa.close()
	(nd("c15_svg_path") as LineEdit).text = path
	await click_ctl(nd("c15_svg_import") as Button)
	var imp := Part.feature(pu._rec(), pu.sk)
	ok((imp.get("ents", []) as Array).size() == 4 and (nd("c15_svg_words") as Label).text.begins_with("File says"), "B9 real click on Import SVG: %d lines, label [%s]" % [(imp.get("ents", []) as Array).size(), (nd("c15_svg_words") as Label).text])
	await shot("svg_import_1280")
	print("c15: %d fail" % fails)
	quit(1 if fails > 0 else 0)
