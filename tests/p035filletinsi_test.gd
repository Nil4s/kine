extends SceneTree
## godot --path . --position 4000,4000 -s tests/p035filletinsi_test.gd     (P035 FILLET INSIDE: Friday plan item 35, "Smooth the joints": after Stick together joins two pieces, a Smooth the joints chip rounds the inside corners where they meet; scripts/easy_part_stick.gd _smooth_joints; needs the CAD DLL)
## Bars (real clicks through root.push_input at 1280 x 720, from the start screen: a BUILDING project, Part, Easy). A T made of two boxes: a 40 x 10 bar (x -40..40, y -10..0) with a 20 x 20 box standing on its top (x -10..10, y 0..20), both 10 mm deep.
## The joint has two inside corners, 10 mm long each (the built T is 12000 mm3: a 10 mm deep sketch, extruded both ways). A 2 mm round on them adds (1 - pi/4) x 2^2 x 10 x 2 = 17.2 mm3. Measured from the built result (Part's volume), never from the code's own variables:
##   1 JOIN      Stick together, click each piece, Join: ONE solid (the join already works; this bar holds it)
##   2 CHIP      after the Join the Smooth the joints chip shows, with its plain words
##   3 SMOOTH    a click on the chip: one fillet step, ONE solid, the volume grows by 25..45 mm3 (34.3 expected)
##   4 UNDO      one undo step: the fillet step goes and the volume is back to the joined volume; redo brings the round back
##   5 PLAIN     a single box (no joint): the chip does not show
## Shots: C:/Temp/claude/p035filletinsi/ (the smoothed joint). Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p035filletinsi"
const DIRT := "user://p035filletinsi_test"


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
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func count_kind(rec: Dictionary, t: String) -> int:
	var n := 0
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			n += 1
	return n


## the screen box of body i's corners
func body_box(faces: Array, i: int) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for w in faces[i]:
		var q: Vector2 = m.cam.unproject_position(w)
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


## a point inside body i's screen box that the ray hits on body i (not over the Easy panel)
func inside_pt(faces: Array, i: int) -> Vector2:
	var ep = m.bld.part.ep
	var pu = m.bld.part
	var r := body_box(faces, i)
	for f in [Vector2(0.5, 0.5), Vector2(0.35, 0.5), Vector2(0.65, 0.5), Vector2(0.5, 0.35), Vector2(0.5, 0.65)]:
		var p: Vector2 = r.position + r.size * f
		var hit: Dictionary = pu._ray_hit(p, faces)
		if not hit.is_empty() and int(hit["body"]) == i and not ep._over_ui(p):
			return p
	return Vector2(-1, -1)


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


## the Stick together flow with real clicks: the button, then a click on each piece
func pick_two(a: int, b: int) -> Array:
	var pu = m.bld.part
	var ep = pu.ep
	var faces: Array = Part.body_faces(m.S.part, -1)
	if ep.armed != "stick":
		await click_ctl(ep.make_btns["stick"])
	await click_at(inside_pt(faces, a))
	await click_at(inside_pt(faces, b))
	return faces


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
		print("FAIL: no KineCAD DLL, Smooth the joints cannot run")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# the T: a bar and a box standing on its top, touching on the face y = 0 (x -10..10)
	await set_part(box_feats([[-40.0, -10.0], [40.0, 0.0]], [[-10.0, 0.0], [10.0, 20.0]], 1), "Joint T")
	var ub0: int = m.undo.size()
	var faces: Array = await pick_two(0, 1)
	await click_ctl(ep.stick_btns["join"])
	ok(int(pu.res.get("bodies", 0)) == 1 and ep._lumps(pu.res) == 1, "1 Join of the T: one solid, one piece in the view (bodies %d)" % int(pu.res.get("bodies", 0)))
	var vj: float = float(pu.res.get("volume", 0.0))
	var sb = ep.get("smooth_btn")   # the chip: absent until the code adds it
	var shown: bool = sb != null and sb.is_visible_in_tree()
	ok(shown and String(sb.text).contains("Smooth the joints"), "2 the Smooth the joints chip shows after the Join (text '%s')" % (String(sb.text) if sb != null else "none"))
	if sb == null:
		sb = ep.stick_btns["join"]   # keeps the rest of the walk running on the current code
	await shot("joined")
	var ns0 := count_kind(m.S.part, "fillet")
	await click_ctl(sb)
	var vs: float = float(pu.res.get("volume", 0.0))
	var gain_mm3: float = (vs - vj) * 1e9
	ok(int(pu.res.get("bodies", 0)) == 1 and count_kind(m.S.part, "fillet") == ns0 + 1 and gain_mm3 >= 12.0 and gain_mm3 <= 24.0,
		"3 Smooth the joints: one solid, one fillet step, the volume grows 12..24 mm3 (%.1f -> %.1f, +%.1f mm3; 17.2 expected)" % [vj * 1e9, vs * 1e9, gain_mm3])
	await shot("smoothed")
	var ub2: int = m.undo.size()
	m._undo()
	await idle(3)
	var vu: float = float(pu.res.get("volume", 0.0))
	ok(gain_mm3 >= 12.0 and absf(vu - vj) <= 0.01 * vj and count_kind(m.S.part, "fillet") == ns0, "4 one undo: the round goes, the volume is the joined volume again (%.1f mm3)" % (vu * 1e9))
	m._redo()
	await idle(3)
	var vr: float = float(pu.res.get("volume", 0.0))
	ok(gain_mm3 >= 12.0 and absf(vr - vs) <= 0.01 * vs, "4 redo brings the round back (%.1f mm3, was %.1f)" % [vr * 1e9, vs * 1e9])

	# 5 PLAIN: one box alone has no joint, so the chip stays hidden
	await set_part(box_feats([[-40.0, -10.0], [40.0, 10.0]], [[60.0, 60.0], [70.0, 70.0]], 1), "Plain box")
	var sb2 = ep.get("smooth_btn")
	ok(sb2 == null or not sb2.is_visible_in_tree(), "5 a single box shows no Smooth the joints chip")

	print("P035FILLETINSI fails=%d" % fails)
	quit(1 if fails > 0 else 0)
