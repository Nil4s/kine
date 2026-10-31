extends SceneTree
## godot --path . --position 4000,4000 -s tests/p054alignchips_test.gd     (P054 ALIGN CHIPS: Easy Part's "Line them up", "Centre on that" and "Same height" for two pieces; scripts/easy_part_stick.gd _align; needs the CAD DLL)
## Bars (real clicks through root.push_input at 1280 x 720, from the start screen: a 3D BUILDING project, Part, Easy; the pieces are made as records):
##   1 LEFT      box A x -40..0 (y -10..10) stays, box B x 30..70 (same height, 40 mm apart) moves: Stick together, click A then B,
##               Line them up: B's left side at x -40 (within 0.05 mm), B's height and depth unchanged, ONE undo step, undo puts B back at x 30
##   2 CENTRE    box C y -20..0 (x -30..-10) moves: Centre on that puts C's middle on A's middle (x -20, y 0, within 0.05 mm), one undo step
##   3 TOP       Same height: C's top at A's top (y 10, within 0.05 mm), one undo step
##   4 ONE       with one piece picked the three align chips stay hidden (no step, no undo step)
##   5 PX        the three chips are inside the 1280 x 720 screen when shown (px)
## Shots: C:/Temp/claude/p054alignchips/ (the align row). Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p054alignchips"
const DIRT := "user://p054alignchips_test"


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


## the built box of body i in mm (from the built faces, never the record's numbers)
func box_mm(faces: Array, i: int) -> AABB:
	var bb := AABB()
	var first := true
	for w in faces[i]:
		bb = AABB(w, Vector3.ZERO) if first else bb.expand(w)
		first = false
	return AABB(bb.position * 1000.0, bb.size * 1000.0)


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


## one box as two records: a front-plane rectangle extruded 10 mm both ways (a new body)
func rect_feats(rect: Array, id0: int) -> Array:
	return [
		{"t": "sketch", "id": "f%d" % id0, "name": "Sketch%d" % id0, "plane": "front", "ents": [{"k": "rect", "a": rect[0], "b": rect[1]}], "dims": []},
		{"t": "extrude", "id": "f%d" % (id0 + 1), "name": "Extrude%d" % id0, "sketch": "f%d" % id0, "dist": 10.0, "both": true, "op": "new"}]


func set_part(feats: Array, nm: String) -> void:
	var pu = m.bld.part
	var rec := Part.make(nm)
	rec["features"] = feats
	rec["seq"] = feats.size()
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	await idle(3)


## Stick together with real clicks: the button, then a click on each piece (the first stays, the second is the one that moves)
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
		print("FAIL: no KineCAD DLL, the align chips cannot run")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# 1 LEFT: A x -40..0 (y -10..10) stays, B x 30..70 (same height, 40 mm apart) moves to line up its left side with A's
	await set_part(rect_feats([[-40.0, -10.0], [0.0, 10.0]], 1) + rect_feats([[30.0, -10.0], [70.0, 10.0]], 3), "Line up")
	var ub0: int = m.undo.size()
	await pick_two(0, 1)
	ok(ep.stick_picks.size() == 2 and ep.stick_box.visible, "1 two pieces picked, the stick box shows (picks %s) [%s]" % [str(ep.stick_picks), ep.msg])
	await click_ctl(ep.align_btns["left"])
	var fb: Array = Part.body_faces(m.S.part, -1)
	var bb1 := box_mm(fb, 1)
	ok(absf(bb1.position.x - (-40.0)) < 0.05, "1 Line them up: B's left side at x %.2f mm (want -40.00)" % bb1.position.x)
	ok(absf(bb1.size.y - 20.0) < 0.05 and absf(bb1.position.y + 10.0) < 0.05 and absf(bb1.size.x - 40.0) < 0.05, "1 B keeps its size and height (%.2f x %.2f mm, y %.2f)" % [bb1.size.x, bb1.size.y, bb1.position.y])
	ok(count_kind(m.S.part, "align") == 1 and m.undo.size() == ub0 + 1, "1 an align step and ONE undo step (%d -> %d)" % [ub0, m.undo.size()])
	m._undo()
	await idle(3)
	var bb1u := box_mm(Part.body_faces(m.S.part, -1), 1)
	ok(absf(bb1u.position.x - 30.0) < 0.05, "1 undo puts B back at x %.2f mm (want 30.00)" % bb1u.position.x)

	# 2 CENTRE: C (x -30..-10, y -20..0) moves so its middle sits on A's middle (x -20, y -10)
	await set_part(rect_feats([[-40.0, -10.0], [0.0, 10.0]], 1) + rect_feats([[30.0, -10.0], [70.0, 10.0]], 3) + rect_feats([[-30.0, -20.0], [-10.0, 0.0]], 5), "Centre")
	var ub2: int = m.undo.size()
	await pick_two(0, 2)
	await click_ctl(ep.align_btns["centre"])
	var bc := box_mm(Part.body_faces(m.S.part, -1), 2)
	var cc := bc.get_center()
	ok(absf(cc.x - (-20.0)) < 0.05 and absf(cc.y - 0.0) < 0.05, "2 Centre on that: C's middle at x %.2f y %.2f mm (want -20, 0)" % [cc.x, cc.y])
	ok(m.undo.size() == ub2 + 1 and count_kind(m.S.part, "align") == 1, "2 one align step and ONE undo step (%d -> %d)" % [ub2, m.undo.size()])

	# 3 TOP: Same height puts C's top at A's top (y 10 mm)
	await set_part(rect_feats([[-40.0, -10.0], [0.0, 10.0]], 1) + rect_feats([[30.0, -10.0], [70.0, 10.0]], 3) + rect_feats([[-30.0, -20.0], [-10.0, 0.0]], 5), "Same height")
	var ub3: int = m.undo.size()
	await pick_two(0, 2)
	await click_ctl(ep.align_btns["top"])
	var bt := box_mm(Part.body_faces(m.S.part, -1), 2)
	ok(absf(bt.end.y - 10.0) < 0.05, "3 Same height: C's top at y %.2f mm (want 10.00)" % bt.end.y)
	ok(m.undo.size() == ub3 + 1 and count_kind(m.S.part, "align") == 1, "3 one align step and ONE undo step (%d -> %d)" % [ub3, m.undo.size()])

	# 4 ONE: with one piece picked the align chips stay hidden
	await set_part(rect_feats([[-40.0, -10.0], [0.0, 10.0]], 1) + rect_feats([[30.0, -10.0], [70.0, 10.0]], 3), "One")
	var ub4: int = m.undo.size()
	if ep.armed != "stick":
		await click_ctl(ep.make_btns["stick"])
	await click_at(inside_pt(Part.body_faces(m.S.part, -1), 0))
	var hidden: bool = not ep.align_row.visible
	ok(ep.stick_picks.size() == 1 and hidden, "4 one piece picked: the align chips stay hidden (picks %s)" % str(ep.stick_picks))
	ok(m.undo.size() == ub4 and count_kind(m.S.part, "align") == 0, "4 no step and no undo step for one piece")

	# 5 PX: with two pieces picked the three chips sit inside the 1280 x 720 screen
	await click_at(inside_pt(Part.body_faces(m.S.part, -1), 1))
	var inside := true
	for al in ["left", "centre", "top"]:
		var r: Rect2 = ep.align_btns[al].get_global_rect()
		inside = inside and r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= 1280.0 and r.end.y <= 720.0
	ok(ep.align_row.visible and inside, "5 the three align chips show inside 1280 x 720 px (row visible %s)" % str(ep.align_row.visible))
	await shot("align_row")

	print("p054alignchips: %d fail(s)" % fails)
	quit(fails)
