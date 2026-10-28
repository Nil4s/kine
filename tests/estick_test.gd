extends SceneTree
## godot --path . --position 4000,4000 -s tests/estick_test.gd     (ESTICK: Easy Part's Stick together on two pieces made apart; scripts/easy_part.gd _stick / _stick_pick; needs the CAD DLL)
## Bars (real clicks through root.push_input at 1280 x 720, from the start screen: a 3D BUILDING project, Part, Easy; the pieces are made as records):
##   1 TOUCH     two boxes made apart that share a face: Stick together, click each in the view, Join: ONE solid (one piece in the view),
##               volume kept (within 1 %), a combine step, ONE undo step; undo gives two pieces back, redo gives one
##   2 APART     two boxes with a 40 mm gap: Join is refused in plain words that say the pieces do not touch and what to do (move one until it touches),
##               no combine step, no undo step, both pieces still there (the words, not a fake one solid)
##   3 RETRY     after the refusal the picks are cleared and Stick together arms again: one click picks a piece, the words say so
## Shots: C:/Temp/claude/estick/ (the apart refusal). Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/estick"
const DIRT := "user://estick_test"


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


## the Stick together flow with real clicks: the button, then a click on each piece; returns the faces it used
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
		print("FAIL: no KineCAD DLL, Stick together cannot run")
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# 1 TOUCH: two boxes made apart that share the face at x = 0 (x -40..0 and 0..40)
	await set_part(box_feats([[-40.0, -10.0], [0.0, 10.0]], [[0.0, -10.0], [40.0, 10.0]], 1), "Touching pieces")
	var vol0: float = float(pu.res.get("volume", 0.0))
	var ub0: int = m.undo.size()
	await pick_two(0, 1)
	ok(ep.stick_picks.size() == 2 and ep.stick_box.visible, "1 two pieces picked, the three Stick buttons show (picks %s) [%s]" % [str(ep.stick_picks), ep.msg])
	await click_ctl(ep.stick_btns["join"])
	ok(int(pu.res.get("bodies", 0)) == 1 and ep._lumps(pu.res) == 1, "1 Join of touching pieces: one solid, one piece in the view (bodies %d, pieces %d) [%s]" % [int(pu.res.get("bodies", 0)), ep._lumps(pu.res), ep.msg])
	var vol1: float = float(pu.res.get("volume", 0.0))
	ok(vol0 > 0.0 and absf(vol1 - vol0) <= 0.01 * vol0, "1 the volume is kept within 1 %% (%.1f -> %.1f cm3)" % [vol0 * 1e6, vol1 * 1e6])
	ok(count_kind(m.S.part, "combine") == 1 and m.undo.size() == ub0 + 1, "1 a combine step and ONE undo step (%d -> %d)" % [ub0, m.undo.size()])
	m._undo()
	await idle(3)
	ok(int(pu.res.get("bodies", 0)) == 2, "1 undo gives the two pieces back (bodies %d)" % int(pu.res.get("bodies", 0)))
	m._redo()
	await idle(3)
	ok(int(pu.res.get("bodies", 0)) == 1 and ep._lumps(pu.res) == 1, "1 redo gives one solid again")

	# 2 APART: two boxes with a 40 mm gap (x -70..-30 and 30..70): Join must say so and change nothing
	await set_part(box_feats([[-70.0, -10.0], [-30.0, 10.0]], [[30.0, -10.0], [70.0, 10.0]], 1), "Apart pieces")
	var ub1: int = m.undo.size()
	var nb1 := int(pu.res.get("bodies", 0))
	var faces: Array = await pick_two(0, 1)
	ok(ep.stick_picks.size() == 2, "2 two apart pieces picked (picks %s)" % str(ep.stick_picks))
	await click_ctl(ep.stick_btns["join"])
	var words: String = ep.msg
	ok(m.undo.size() == ub1 and count_kind(m.S.part, "combine") == 0 and int(pu.res.get("bodies", 0)) == nb1,
		"2 Join of apart pieces: no undo step, no combine step, both pieces still there (undo %d -> %d, bodies %d -> %d)" % [ub1, m.undo.size(), nb1, int(pu.res.get("bodies", 0))])
	ok(words.contains("do not touch") and words.to_lower().contains("move"), "2 the words say the pieces do not touch and what to do [%s]" % words)
	await shot("apart_refused")

	# 3 RETRY: the picks are cleared and Stick together arms again on the same pieces
	ok(ep.stick_picks.is_empty(), "3 after the refusal the picks are cleared (picks %s)" % str(ep.stick_picks))
	await click_ctl(ep.make_btns["stick"])
	await click_at(inside_pt(faces, 0))
	ok(ep.stick_picks.size() == 1 and ep.msg.contains("Now click the other piece"), "3 Stick together arms again: one click picks a piece (picks %d) [%s]" % [ep.stick_picks.size(), ep.msg])

	print("ESTICK fails=%d" % fails)
	quit(1 if fails > 0 else 0)
