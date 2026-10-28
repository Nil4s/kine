extends SceneTree
## godot --headless --path . -s tests/bodydims_test.gd     (C2 BODY-DRIVEN DIMENSIONS: a Part sketch dimension can read a body measure, "=forearm+4" = the forearm's length + 4 mm)
## Bars, written before measuring (headless: the kernel replays the Part record; no window; every number is the solid the record makes):
##   1 PARSE     "=forearm+4" -> forearm, factor 1, +4; "=thigh*0.6" -> factor 0.6; "=forearm*1.2-2 mm" -> 1.2, -2; "12" and "=" are not binds
##   2 MEASURE   the body's forearm = 0.146 x stature (Winter / Drillis & Contini, age 30): 1.80 m body -> 0.2628 m within 0.5 mm;
##               the default body (scene {}) -> the default forearm 0.27264 m exactly
##   3 FOLLOWS   a cylinder of radius "forearm + 4" in a 170 cm and a 180 cm body: the radius grows by the forearm's growth
##               (14.6 mm for 10 cm of height) within 1 mm, and each solid's volume = pi r^2 L (L = 20 mm) within 1e-5 relative
##   4 UNBOUND   the same cylinder with a plain 5 mm radius: identical volume in the 170 and 180 cm bodies (exact)
##   5 MISSING   a bind to a measure the body does not have ("=tail") and a bind replayed with no body: the sketch and its extrude
##               report an error, the record makes NO solid (bodies 0, volume 0): never a default
##   6 NEGATIVE  "=forearm-300": a size of about -37 mm is refused with an error (no solid)
##   7 UNBIND    typing a plain size on a bound dimension drops the bind: the next replay is the plain size, any body
##   8 SAVED     a record with a bound dimension is saved and read back (to_file / from_file): the same volume at 190 cm
## WINDOW (run with :w; real clicks and keys on the BUILD page at 1280 x 720, a 3D BUILDING project):
##   9 TYPED     Part, Front plane, Rectangle 95 x 25 mm, Dimension on the bottom edge, typed =forearm+4: the rectangle is
##               forearm + 4 mm wide (the default body's forearm 272.64 mm: 276.64 within 0.01 mm), the dimension names its source
##  10 BODY      the body becomes 190 cm (proportions_set): the sketch on screen is forearm(190) + 4 mm within 0.01 mm; shots
##  11 SCREEN    the dimension's line shows =forearm+4 and the number of the body now; no bar moves for the Easy page (no dimensions)
## Shots: C:/Temp/claude/bodydims/
const KCad := preload("res://scripts/kcad.gd")
const SHOT := "C:/Temp/claude/bodydims"
const DIRT := "user://bodydims_test"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


## one sketch (a circle of radius r_mm on the Front plane) and its 20 mm extrude, as a Part record
func cylinder(bind: Dictionary, r_mm: float, measures: Variant) -> Dictionary:
	var rec := Part.make("Cylinder")
	var sk := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": Part.arr2(Vector2.ZERO), "r": 5.0}], "dims": []})
	if not bind.is_empty():
		var r := Part.bound_mm(bind, measures)
		Part.set_dim(sk, 0, "r", float(r["mm"]), bind)
	else:
		Part.set_dim(sk, 0, "r", r_mm)
	rec["features"].append(sk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": 20.0, "both": false, "op": "join"}))
	return rec


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
	await idle(2)


## a Part tool: on the row, or under its caption's dropdown (1c0e86b4: Dimension moved under SKETCH at 1280 x 720)
func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	for pair in m.ui_caps.get("BUILD", []):
		if (pair[1] as Array).has(b):
			await click_ctl(pair[0])
			(pair[0] as MenuButton).get_popup().hide()
			m._run_tool(b, pair[0])
			await idle(2)
			return
	ok(false, "%s is on the row or under its caption" % t)


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func key_char(ch: String) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_NONE
	e.unicode = ch.unicode_at(0)
	e.pressed = true
	root.push_input(e, true)
	await process_frame


## the text typed into a LineEdit by real key events (the text is replaced)
func type_in(le: LineEdit, txt: String) -> void:
	await click_ctl(le)
	le.select_all()   # the field's own text is selected (as on focus); the keys below replace it
	for ch in txt:
		await key_char(ch)
	var e := InputEventKey.new()
	e.keycode = KEY_ENTER
	e.physical_keycode = KEY_ENTER
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## the screen point of a sketch point (mm) on the Front plane
func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func drag2(x0: float, y0: float, x1: float, y1: float) -> void:
	await ev_move(sp2(x0, y0), false)
	await ev_mouse(sp2(x0, y0), true)
	await ev_move(sp2((x0 + x1) * 0.5, (y0 + y1) * 0.5))
	await ev_move(sp2(x1, y1))
	await ev_mouse(sp2(x1, y1), false)
	await idle(2)


## the BUILD page, a 3D building, Part on, the Front plane, a 95 x 25 mm rectangle, a bottom-edge dimension typed =forearm+4
func ui_part() -> void:
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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	# 5c735d53 (Nick 2026-10-28, freebuild): the BUILDING card opens an Easy Part when the card's Easy button is on.
	# This suite drives the Expert Part tools, so the card's Easy button is turned off first (navigation only).
	if ss._easy_btn["building"].button_pressed:
		await click_ctl(ss._easy_btn["building"])
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not pu.on:   # the card turns Part on (5c735d53)
		await click_ctl(pu.part_btn)
	await idle(3)
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	await click_ctl(pu.tool_btns["Rectangle"])
	await drag2(0, 0, 95, 25)
	await press_tool(pu, "Dimension")
	await click_ctl_at(sp2(47.5, 0))
	ok(pu.dim_edit.visible, "9 TYPED Dimension on the bottom edge opens the type box")
	await type_in(pu.dim_edit, "=forearm+4")
	var sk: Dictionary = pu._sk()
	var ent: Array = sk["ents"]
	var w0 := Part.v2(ent[0]["b"]).x
	var fa0 := float(Proportions.measures_of(m.S.body)["forearm"]) * 1000.0 + 4.0
	ok(absf(w0 - fa0) < 0.01 and sk["dims"].size() == 1 and (sk["dims"][0] as Dictionary).has("bind"),
		"9 TYPED width %.3f mm = forearm + 4 = %.3f mm (dimensions %s)" % [w0, fa0, sk["dims"]])
	var lbl := false
	for c in pu.nums_vb.get_children():
		for k in c.get_children():
			lbl = lbl or (k is Label and (k as Label).text.contains("=forearm+4"))
	ok(lbl, "9 TYPED the dimension list names its source =forearm+4")
	await shot("bodydims_bound_default")

	# 10 BODY: 190 cm, through the Body page's own door
	m.proportions_set(BodyFromNumbers.body_for(190.0, 75.0, "male", 30.0, "average"))
	await idle(6)
	var fa190 := float(Proportions.measures_of(m.S.body)["forearm"]) * 1000.0 + 4.0
	var w190 := Part.v2(pu._sk()["ents"][0]["b"]).x
	ok(absf(w190 - fa190) < 0.01 and absf(fa190 - w0) > 1.0, "10 BODY 190 cm: the width follows to %.3f mm (forearm + 4 of the new body; was %.3f)" % [w190, w0])
	await shot("bodydims_bound_190")


func _init() -> void:
	if not Part.available():
		print("SKIP: no KineCAD DLL (Part.available() false)")
		quit(0)
		return
	# 1 PARSE
	var b := Part.parse_bind("=forearm+4")
	ok(String(b.get("m", "")) == "forearm" and is_equal_approx(float(b.get("k", 0.0)), 1.0) and is_equal_approx(float(b.get("add", 0.0)), 4.0), "PARSE =forearm+4 -> %s" % [b])
	b = Part.parse_bind("=thigh*0.6")
	ok(String(b.get("m", "")) == "thigh" and is_equal_approx(float(b.get("k", 0.0)), 0.6) and is_equal_approx(float(b.get("add", 1.0)), 0.0), "PARSE =thigh*0.6 -> %s" % [b])
	b = Part.parse_bind("=forearm*1.2-2 mm")
	ok(is_equal_approx(float(b.get("k", 0.0)), 1.2) and is_equal_approx(float(b.get("add", 0.0)), -2.0), "PARSE =forearm*1.2-2 mm -> %s" % [b])
	ok(Part.parse_bind("12").is_empty() and Part.parse_bind("=").is_empty(), "PARSE '12' and '=' are not binds")
	ok(Part.bind_text(Part.parse_bind("=forearm+4")) == "=forearm+4" and Part.bind_text(Part.parse_bind("=thigh*0.6-2")) == "=thigh*0.6-2", "PARSE the text a bind shows reads back as typed (=forearm+4, =thigh*0.6-2)")

	# 2 MEASURE
	var tall := BodyFromNumbers.body_for(180.0, 75.0, "male", 30.0, "average")
	var m180 := Proportions.measures_of(tall)
	var fa180 := float(m180["forearm"])
	ok(absf(fa180 - 0.146 * 1.80) < 0.0005, "MEASURE forearm of a 180 cm body = %.4f m (0.146 H = %.4f)" % [fa180, 0.146 * 1.80])
	var fa_def := float(Proportions.measures_of({})["forearm"])
	ok(is_equal_approx(fa_def, 0.27264), "MEASURE the default body's forearm = %.5f m (0.27264)" % fa_def)

	# 3 FOLLOWS
	var m170 := Proportions.measures_of(BodyFromNumbers.body_for(170.0, 75.0, "male", 30.0, "average"))
	var bind := Part.parse_bind("=forearm+4")
	var r170 := float(Part.bound_mm(bind, m170)["mm"])
	var r180 := float(Part.bound_mm(bind, m180)["mm"])
	var grow_fa := (float(m180["forearm"]) - float(m170["forearm"])) * 1000.0
	var grow_r := r180 - r170
	ok(absf(grow_r - grow_fa) < 1.0 and absf(grow_fa - 14.6) < 0.3, "FOLLOWS radius grows %.2f mm, forearm %.2f mm (within 1 mm; 0.146 x 100 mm = 14.6)" % [grow_r, grow_fa])
	var res170: Dictionary = Part.replay(cylinder(bind, 0.0, m170), -1, {"body": m170})
	var res180: Dictionary = Part.replay(cylinder(bind, 0.0, m180), -1, {"body": m180})
	var v170 := float(res170["volume"])
	var v180 := float(res180["volume"])
	var want170 := PI * pow(r170 * 0.001, 2) * 0.02
	var want180 := PI * pow(r180 * 0.001, 2) * 0.02
	ok(res170["bodies"] == 1 and res180["bodies"] == 1, "FOLLOWS each body makes one solid (errors %s / %s)" % [res170["errors"], res180["errors"]])
	ok(absf(v170 - want170) < 1e-5 * want170 and absf(v180 - want180) < 1e-5 * want180, "FOLLOWS volume 170 cm %s m3 (pi r^2 L %s), 180 cm %s m3 (%s)" % [v170, want170, v180, want180])
	ok(v180 > v170 * 1.05, "FOLLOWS the 180 cm solid is %.1f %% bigger (the bound radius changed the part)" % ((v180 / v170 - 1.0) * 100.0))

	# 4 UNBOUND
	var u170: float = Part.replay(cylinder({}, 5.0, null), -1, {"body": m170})["volume"]
	var u180: float = Part.replay(cylinder({}, 5.0, null), -1, {"body": m180})["volume"]
	ok(u170 > 0.0 and u170 == u180, "UNBOUND a plain 5 mm radius: volume %s in both bodies (identical)" % u170)

	# 5 MISSING
	var miss := Part.replay(cylinder(Part.parse_bind("=tail+4"), 0.0, m180), -1, {"body": m180})
	var miss_s: String = String(miss["errors"].values()[0]) if not miss["errors"].is_empty() else ""
	ok(int(miss["bodies"]) == 0 and float(miss["volume"]) == 0.0 and miss_s.contains("no measure called tail"), "MISSING =tail+4 -> no solid, error '%s'" % miss_s)
	var none := Part.replay(cylinder(bind, 0.0, null), -1, {})
	var none_s: String = String(none["errors"].values()[0]) if not none["errors"].is_empty() else ""
	ok(int(none["bodies"]) == 0 and float(none["volume"]) == 0.0 and none_s.contains("no body"), "MISSING no body given -> no solid, error '%s'" % none_s)

	# 6 NEGATIVE
	var neg := Part.replay(cylinder(Part.parse_bind("=forearm-300"), 0.0, m180), -1, {"body": m180})
	var neg_s: String = String(neg["errors"].values()[0]) if not neg["errors"].is_empty() else ""
	ok(int(neg["bodies"]) == 0 and neg_s.contains("not a size"), "NEGATIVE =forearm-300 (%.1f mm) -> no solid, error '%s'" % [float(m180["forearm"]) * 1000.0 - 300.0, neg_s])

	# 7 UNBIND
	var rec7 := cylinder(bind, 0.0, m180)
	var sk7: Dictionary = rec7["features"][0]
	Part.set_dim(sk7, 0, "r", 5.0)
	ok(not (sk7["dims"][0] as Dictionary).has("bind"), "UNBIND a plain size drops the bind from the record")
	var v7a := float(Part.replay(rec7, -1, {"body": m170})["volume"])
	var v7b := float(Part.replay(rec7, -1, {"body": m180})["volume"])
	ok(v7a == v7b and absf(v7a - PI * pow(5.0 * 0.001, 2) * 0.02) < 1e-5 * v7a, "UNBIND the 5 mm cylinder again, both bodies: %s m3" % v7a)

	# 8 SAVED
	var rec8 := Part.from_file(Part.to_file(cylinder(bind, 0.0, m180)))
	var v8 := float(Part.replay(rec8, -1, {"body": m180})["volume"])
	ok(absf(v8 - v180) < 1e-12, "SAVED a bound record read back: volume %s m3, the same as before saving (%s)" % [v8, v180])

	await ui_part()
	print("bodydims: %d FAIL" % fails if fails > 0 else "bodydims: all ok")
	quit(fails)
