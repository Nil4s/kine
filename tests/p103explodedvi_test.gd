extends SceneTree
## godot --path . --position 4000,4000 -s tests/p103explodedvi_test.gd     (P103 EXPLODED VIEW: Easy Part's Pull apart slider; scripts/build/part_ui.gd _exploded, scripts/easy_part_stick.gd _explode_box; needs the CAD DLL)
## Bars (real clicks through root.push_input at 1280 x 720, from the start screen: a 3D BUILDING project, Part, Easy; the pieces are made as records):
##   1 SHOWN     two boxes made apart (a 40 mm gap): the Pull apart slider shows; one box alone: it stays hidden
##   2 PULL      one real drag of the knob to 30 % of the slider: the two pieces move apart along the line between them, the gap between their middles
##               (measured from the built mesh, one surface per piece) grows by 2 x the slider's mm (within 0.5 mm), no sideways drift (within 0.5 mm)
##   3 WORDS     the slider's label says the mm in plain words
##   4 NO STEP   the record and the undo count do not change while the slider moves (a view only, no combine, no undo step)
##   5 TOGETHER  a drag back to the left end puts the pieces back: the gap is the first 100 mm again, the label says together
##   6 APART     a drag to the right end pulls them to 100 mm each: the gap is 300 mm within 0.5 mm
## Shots: C:/Temp/claude/p103explodedvi/ (the pulled-apart view at 30 mm). Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p103explodedvi"
const DIRT := "user://p103explodedvi_test"


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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## a box as records: a front-plane rectangle extruded 10 mm both ways (a new body each)
func box_feats(rect_a: Array, rect_b: Array, id0: int) -> Array:
	return [
		{"t": "sketch", "id": "f%d" % id0, "name": "Sketch%d" % id0, "plane": "front", "ents": [{"k": "rect", "a": rect_a[0], "b": rect_a[1]}], "dims": []},
		{"t": "extrude", "id": "f%d" % (id0 + 1), "name": "Extrude%d" % id0, "sketch": "f%d" % id0, "dist": 10.0, "both": true, "op": "new"},
		{"t": "sketch", "id": "f%d" % (id0 + 2), "name": "Sketch%d" % (id0 + 2), "plane": "front", "ents": [{"k": "rect", "a": rect_b[0], "b": rect_b[1]}], "dims": []},
		{"t": "extrude", "id": "f%d" % (id0 + 3), "name": "Extrude%d" % (id0 + 2), "sketch": "f%d" % (id0 + 2), "dist": 10.0, "both": true, "op": "new"}]


func set_part(feats: Array, nm: String) -> void:
	var pu = m.bld.part
	var rec := Part.make(nm)
	rec["features"] = feats
	rec["seq"] = feats.size()
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	await idle(3)


## the middle of each piece as the built mesh shows it now (metres; one surface per piece)
func piece_middles() -> Array:
	var pu = m.bld.part
	var out: Array = []
	var mesh: ArrayMesh = pu.part_mesh.mesh
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		var vs: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var box := AABB(vs[0], Vector3.ZERO)
		for v in vs:
			box = box.expand(v)
		out.append(box.get_center())
	return out


## the gap between the first two pieces' middles (mm) and its sideways part (the two other axes, mm)
func gap_mm() -> Array:
	var mids := piece_middles()
	if mids.size() < 2:
		return [-1.0, 99.0]
	var d: Vector3 = (mids[1] - mids[0]) / Part.MM
	return [d.length(), Vector2(d.y, d.z).length()]


## a real drag of the slider's knob to a fraction of its track (0 = the left end, 1 = the right end): held with the left button, in 8 steps
func drag_to(frac: float) -> void:
	var s: HSlider = m.bld.part.ep.explode_slider
	var y := s.get_global_rect().get_center().y
	var p0 := Vector2(knob_x(s, s.value), y)
	var x1 := knob_x(s, frac * s.max_value)
	if frac <= 0.0:
		x1 = s.get_global_rect().position.x - 30.0   # past the left end: the value stops at 0
	elif frac >= 1.0:
		x1 = s.get_global_rect().end.x + 30.0   # past the right end: the value stops at the top
	await ev_move(p0, false)
	var hv = root.get_viewport().gui_get_hovered_control()
	await ev_mouse(p0, true)
	for i in range(1, 9):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 8.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


## the screen x of the knob's centre at value v (the knob is 24 px wide, as Easy Part's sliders draw it)
func knob_x(s: HSlider, v: float) -> float:
	var r := s.get_global_rect()
	return r.position.x + 12.0 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - 24.0)


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the Pull apart slider cannot run")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# 1 SHOWN: two boxes made apart, x -70..-30 and 30..70 (middles 100 mm apart); then one box alone
	await set_part(box_feats([[-70.0, -10.0], [-30.0, 10.0]], [[30.0, -10.0], [70.0, 10.0]], 1), "Apart pieces")
	ok(int(pu.res.get("bodies", 0)) == 2 and ep.explode_box.visible, "1 two pieces: the Pull apart slider shows (bodies %d) [%s]" % [int(pu.res.get("bodies", 0)), ep.msg])
	var g0 := gap_mm()
	ok(absf(float(g0[0]) - 100.0) <= 0.5 and float(g0[1]) <= 0.5, "1 together at the start: the middles are 100 mm apart (gap %.2f mm)" % float(g0[0]))
	await set_part(box_feats([[-70.0, -10.0], [-30.0, 10.0]], [[30.0, -10.0], [70.0, 10.0]], 1).slice(0, 2), "One piece")
	ok(int(pu.res.get("bodies", 0)) == 1 and not ep.explode_box.visible, "1 one piece alone: the slider stays hidden (bodies %d)" % int(pu.res.get("bodies", 0)))
	await set_part(box_feats([[-70.0, -10.0], [-30.0, 10.0]], [[30.0, -10.0], [70.0, 10.0]], 1), "Apart pieces")

	# 2 PULL + 3 WORDS + 4 NO STEP: a real drag of the knob to 30 % of the track
	var ub: int = m.undo.size()
	var nf: int = (m.S.part["features"] as Array).size()
	await drag_to(0.3)
	var v: float = ep.explode_slider.value
	var g1 := gap_mm()
	ok(v >= 20.0 and v <= 40.0, "2 the drag to 30 %% sets the slider to about 30 mm (value %.1f)" % v)
	ok(absf(float(g1[0]) - (100.0 + 2.0 * v)) <= 0.5, "2 the middles grow by 2 x the slider: gap %.2f mm, want %.2f mm" % [float(g1[0]), 100.0 + 2.0 * v])
	ok(float(g1[1]) <= 0.5, "2 the pieces move along the joint line, no sideways drift (%.2f mm)" % float(g1[1]))
	ok(ep.explode_label.text.contains("mm") and ep.explode_label.text.contains(str(int(v))), "3 the label names the mm in words [%s]" % ep.explode_label.text)
	ok((m.S.part["features"] as Array).size() == nf and m.undo.size() == ub, "4 no step: features %d -> %d, undo %d -> %d" % [nf, (m.S.part["features"] as Array).size(), ub, m.undo.size()])
	await shot("pulled_apart")

	# 5 TOGETHER: back to the left end
	await drag_to(0.0)
	var g2 := gap_mm()
	ok(ep.explode_slider.value == 0.0 and absf(float(g2[0]) - 100.0) <= 0.5, "5 the left end puts them together: gap %.2f mm (value %.1f)" % [float(g2[0]), ep.explode_slider.value])
	ok(ep.explode_label.text.contains("together"), "5 the label says together [%s]" % ep.explode_label.text)

	# 6 APART: to the right end, 100 mm each
	await drag_to(1.0)
	var g3 := gap_mm()
	ok(absf(float(g3[0]) - 300.0) <= 0.5, "6 the right end pulls each piece 100 mm: gap %.2f mm, want 300" % float(g3[0]))

	print("P103EXPLODEDVI fails=%d" % fails)
	quit(1 if fails > 0 else 0)
