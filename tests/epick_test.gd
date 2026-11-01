extends SceneTree
## godot --path . --position 4000,4000 -s tests/epick_test.gd     (EASY PART, PICK: scripts/easy_part.gd; needs the CAD DLL and a window)
## Bars (real clicks through root.push_input at 1280 x 720, from Easy home: a building project, Part, Easy; no keyboard):
##   1 NEAR      two 3 mm plates (40 x 40 mm). A click 8 px OFF each plate (the ray hits nothing) picks it; the picked plate glows and the words
##               say "Now click the other piece"; a second such click picks the other plate
##   2 FAR       a click 60 px away from everything picks nothing (no pick, no undo step)
##   3 STICK     Stick together with those two picks: Join, ONE undo step, one solid, a combine step
##   4 MIRROR    a box off the middle line, Mirror that: the words say "Push them together with Stick together"; a box centred on the middle
##               line (no gap) gets no such words
## Shots: C:/Temp/claude/epick/shot.png (the two plates, the first one picked: glow + words)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/epick"
const DIRT := "user://epick_test"


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


## a click at a point in the view (no control under it)
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


## a point px outside body i's screen box (right, left, below or above; the first in the window, off the panels, that misses the ray)
func off_by(faces: Array, i: int, px: float) -> Vector2:
	var ep = m.bld.part.ep
	var pu = m.bld.part
	var r := body_box(faces, i)
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for p in [Vector2(r.end.x + px, r.get_center().y), Vector2(r.position.x - px, r.get_center().y), Vector2(r.get_center().x, r.end.y + px), Vector2(r.get_center().x, r.position.y - px)]:
		if vp.has_point(p) and not ep._over_ui(p) and pu._ray_hit(p, faces).is_empty():
			return p
	return Vector2(-1, -1)


## a point with no piece within px of it (the ray misses and no piece box is near)
func far_from(faces: Array, px: float) -> Vector2:
	var ep = m.bld.part.ep
	var pu = m.bld.part
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for y in range(80, 700, 20):
		for x in range(60, 1220, 20):
			var p := Vector2(x, y)
			if ep._over_ui(p) or not vp.has_point(p):
				continue
			if not pu._ray_hit(p, faces).is_empty():
				continue
			var near := false
			for i in faces.size():
				if body_box(faces, i).grow(px).has_point(p):
					near = true
			if not near:
				return p
	return Vector2(-1, -1)


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
		print("FAIL: no KineCAD DLL, the pick cannot run")
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
	# design changed in acd9cc1b estick: Stick together Join refuses pieces that do not touch; bar rewritten 11-01 per Nick:
	# the two plates now SHARE a face (plate 2 starts at x = 20, where plate 1 ends) so the Join of two picked pieces can succeed
	# 1 NEAR: two 3 mm plates, 40 x 40 mm, touching along x = 20 (a sketch and a 3 mm both-sides extrude each)
	var pl := Part.make("Two plates")
	pl["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [-20.0, -20.0], "b": [20.0, 20.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 3.0, "both": true, "op": "new"},
		{"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [20.0, -20.0], "b": [60.0, 20.0]}], "dims": []},
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 3.0, "both": true, "op": "new"}]
	pl["seq"] = 4
	m.S.part = pl
	pu.upto = -1
	pu.sync()
	await idle(3)
	var faces: Array = Part.body_faces(m.S.part, -1)
	ok(faces.size() == 2, "1 two plates in the part (%d bodies)" % faces.size())
	await click_ctl(ep.make_btns["stick"])
	var far := far_from(faces, 60.0)
	var ub0: int = m.undo.size()
	await click_at(far)
	ok(ep.stick_picks.is_empty() and m.undo.size() == ub0, "2 a click 60 px from everything picks nothing (%s, picks %s)" % [str(far), str(ep.stick_picks)])
	var p0 := off_by(faces, 0, 8.0)
	ok(p0.x >= 0, "1 a point 8 px off plate 1 misses the ray (%s)" % str(p0))
	await click_at(p0)
	ok(ep.stick_picks.size() == 1 and ep.stick_picks[0] == 0, "1 a click 8 px off the first plate picks it (picks %s)" % str(ep.stick_picks))
	ok(ep.hint_l.text.contains("Now click the other piece"), "1 the words say Now click the other piece [%s]" % ep.hint_l.text)
	await shot("shot")
	var p1 := off_by(faces, 1, 8.0)
	ok(p1.x >= 0, "1 a point 8 px off plate 2 misses the ray (%s)" % str(p1))
	await click_at(p1)
	ok(ep.stick_picks.size() == 2 and ep.stick_box.visible, "1 a click 8 px off the second plate picks it, the three buttons show [%s]" % ep.hint_l.text)
	# 3 STICK: Join with the two picks, one undo step
	var ub1: int = m.undo.size()
	await click_ctl(ep.stick_btns["join"])
	var cb := {}
	for f in m.S.part.get("features", []):
		if String(f["t"]) == "combine":
			cb = f
	ok(not cb.is_empty() and String(cb.get("op", "")) == "join" and int(pu.res.get("bodies", 0)) == 1 and m.undo.size() == ub1 + 1,
		"3 Stick together Join: one solid, a combine step, ONE undo step (%d -> %d) [%s]" % [ub1, m.undo.size(), ep.hint_l.text])
	# 4 MIRROR: a box 20 mm wide off the middle line, one centred on it, and one piece with a REAL gap
	# design changed in 7c6bcd55 EMIRROR: Easy Part Mirror on a piece off the middle line goes across the middle of the part; bar rewritten 11-01 per Nick:
	# an off-line box now mirrors across ITS OWN middle (no gap, words "across the middle of the part", the box keeps its place);
	# the "Push them together" words are reached by a part that already has two pieces apart (a join of two boxes with a gap)
	for kind in ["off", "centred", "gap"]:
		var a := -10.0 if kind == "centred" else 30.0
		var bx := Part.make("Box")
		bx["features"] = [
			{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [a, -10.0], "b": [a + 20.0, 10.0]}], "dims": []},
			{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"}]
		bx["seq"] = 2
		if kind == "gap":
			bx["features"].append({"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [70.0, -10.0], "b": [90.0, 10.0]}], "dims": []})
			bx["features"].append({"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 20.0, "both": false, "op": "join"})
			bx["seq"] = 4
		m.S.part = bx
		pu.upto = -1
		pu.sync()
		await idle(2)
		var before: Dictionary = Part.replay(m.S.part)
		await click_ctl(ep.make_btns["mirror"])
		var words: String = ep.hint_l.text
		var after: Dictionary = Part.replay(m.S.part)
		var bb0: AABB = before["aabb"]
		var bb1: AABB = after["aabb"]
		if kind == "centred":
			ok(not words.contains("Push them together") and count_kind(m.S.part, "mirror") == 1, "4 a box centred on the middle line: mirrored, no gap words [%s]" % words)
		elif kind == "off":
			ok(words.contains("across the middle of the part") and not words.contains("Push them together") and count_kind(m.S.part, "mirror") == 1
				and int(after["bodies"]) == 1 and absf(bb1.position.x - bb0.position.x) < 0.5 and absf(bb1.end.x - bb0.end.x) < 0.5,
				"4 Mirror that off the middle line: mirrored across the middle of the part, no gap, the box keeps its place (x %.1f..%.1f -> %.1f..%.1f) [%s]" % [bb0.position.x, bb0.end.x, bb1.position.x, bb1.end.x, words])
		else:
			ok(words.contains("Push them together with Stick together") and count_kind(m.S.part, "mirror") == 1 and int(after["bodies"]) == 1,
				"4 Mirror that on two pieces with a gap: the words say Push them together with Stick together [%s]" % words)
	print("epick: %d fail" % fails)
	quit(1 if fails > 0 else 0)
