extends SceneTree
## godot --path . --position 4000,4000 -s tests/p121jointsinwo_test.gd     (p121 JOINTS IN WORDS: Friday plan item 121, "This turns here" / "This slides here" on two pieces; scripts/easy_part_stick.gd _joint_words; needs the CAD DLL)
## Bars (real clicks through root.push_input at 1280 x 720, from the start screen: a BUILDING project, Part, Easy). Two boxes that touch: a 40 x 10 bar and a 20 x 20 box standing on its top, both 10 mm deep (the T of P035).
## Measured from the built result (Part.body_faces of the saved record), never from the code's own variables:
##   1 CHIPS   Stick together with one piece picked: no joint words; with two pieces picked: "This turns here" and "This slides here" show
##   2 TURN    a click on This turns here: the record gets one joint, kind turn, its place within 0.5 mm of the middle of the two built piece centres; still two bodies; ONE undo step
##   3 SLIDE   pick the two again, This slides here: a second joint, kind slide
##   4 UNDO    one undo takes the slide joint off (one joint left); redo brings it back
##   5 APART   two pieces that do not touch: This turns here is refused in words that say to move one; no joint is added, no undo step
## Shots: C:/Temp/claude/p121jointsinwo/ (the joint words after the two picks). Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p121jointsinwo"
const DIRT := "user://p121jointsinwo_test"


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


func joint_count(kind := "") -> int:
	var n := 0
	for j in m.S.part.get("joints", []):
		if kind == "" or String(j["kind"]) == kind:
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


## the middle of a body's corners (mm), from the built faces
func body_mid_mm(faces: Array, i: int) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for w in faces[i]:
		c += w
		n += 1
	return c / float(maxi(n, 1)) / Part.MM


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


func joint_btn(kind: String) -> Button:
	var ep = m.bld.part.ep
	for jb in ep.joint_btns:
		if String(jb.name).ends_with(kind):
			return jb
	return null


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
		print("FAIL: no KineCAD DLL, the joint words cannot run")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# 1 CHIPS: one piece picked = no joint words; two pieces = both show
	await set_part(box_feats([[-40.0, -10.0], [40.0, 0.0]], [[-10.0, 0.0], [10.0, 20.0]], 1), "Joint T")
	var faces: Array = Part.body_faces(m.S.part, -1)
	await click_ctl(ep.make_btns["stick"])
	await click_at(inside_pt(faces, 0))
	var jt: Button = joint_btn("turn")
	var one_hidden: bool = jt == null or not jt.is_visible_in_tree()
	ok(one_hidden, "1 one piece picked: no joint words show")
	await click_at(inside_pt(faces, 1))
	jt = joint_btn("turn")
	var js: Button = joint_btn("slide")
	var both: bool = jt != null and js != null and jt.is_visible_in_tree() and js.is_visible_in_tree()
	ok(both and String(jt.text) == "This turns here" and String(js.text) == "This slides here",
		"1 two pieces picked: This turns here and This slides here show (%s / %s)" % [String(jt.text) if jt != null else "none", String(js.text) if js != null else "none"])
	await shot("picked")

	# 2 TURN: one undo step, one joint, both pieces still apart, the place is the middle of the two built pieces
	var ub0: int = m.undo.size()
	await click_ctl(jt)
	var ok_turn: bool = joint_count("turn") == 1 and int(pu.res.get("bodies", 0)) == 2
	ok(ok_turn, "2 This turns here: one turn joint saved, both pieces still two bodies (joints %d, bodies %d)" % [joint_count(), int(pu.res.get("bodies", 0))])
	var mid: Vector3 = (body_mid_mm(faces, 0) + body_mid_mm(faces, 1)) * 0.5
	var at_v := Vector3.ZERO
	if joint_count("turn") == 1:
		var a: Array = m.S.part["joints"][0]["at"]
		at_v = Vector3(float(a[0]), float(a[1]), float(a[2]))
	ok(joint_count("turn") == 1 and at_v.distance_to(mid) <= 0.5, "2 the joint sits within 0.5 mm of the middle of the two pieces (at %s, middle %s)" % [str(at_v), str(mid)])
	ok(m.undo.size() == ub0 + 1, "2 one undo step for the turn joint (undo steps %d -> %d)" % [ub0, m.undo.size()])
	await shot("turned")

	# 3 SLIDE: pick the two again and press This slides here
	faces = await pick_two(0, 1)
	js = joint_btn("slide")
	ok(js != null and js.is_visible_in_tree(), "3 the two pieces picked again: This slides here shows")
	if js != null and js.is_visible_in_tree():
		await click_ctl(js)
	ok(joint_count("slide") == 1 and joint_count() == 2, "3 This slides here: a slide joint is second (turn %d, slide %d)" % [joint_count("turn"), joint_count("slide")])

	# 4 UNDO: one undo takes the slide off, redo brings it back
	m._undo()
	await idle(3)
	ok(joint_count() == 1 and joint_count("turn") == 1, "4 one undo takes the slide joint off (joints %d)" % joint_count())
	m._redo()
	await idle(3)
	ok(joint_count() == 2 and joint_count("slide") == 1, "4 redo brings the slide joint back (joints %d)" % joint_count())

	# 5 APART: two pieces that do not touch are refused in words; nothing is saved
	await set_part(box_feats([[-40.0, -10.0], [40.0, 0.0]], [[60.0, 40.0], [80.0, 60.0]], 1), "Apart")
	faces = await pick_two(0, 1)
	var n0 := joint_count()
	var ub1: int = m.undo.size()
	jt = joint_btn("turn")
	if jt != null and jt.is_visible_in_tree():
		await click_ctl(jt)
	ok(joint_count() == n0 and m.undo.size() == ub1 and String(ep.msg).contains("move one"),
		"5 apart pieces: This turns here is refused in words (msg '%s'), no joint, no undo step" % String(ep.msg))
	await shot("apart")

	print("P121JOINTSINWO fails=%d" % fails)
	quit(1 if fails > 0 else 0)
