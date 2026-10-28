extends SceneTree
## godot --path . --position 4000,4000 -s tests/eface_test.gd     (EFACE: Easy Part DRAW ON A FACE: scripts/easy_part.gd; needs the CAD DLL and a window)
## A press with Draw shape on a flat face of a solid (normal within 5 deg of +-X, +-Y, +-Z) puts the sketch on that face:
## one Part "plane" feature + the sketch, one undo step; Pull it up pulls OUTWARD from the face and joins. A press on empty grid draws on the floor (top plane).
## Real clicks and drags at 1280 x 720. The top is a record (a 100 x 100 x 20 mm slab on the Top plane, its bottom face at y = 0); the rest is clicks.
## Bars (bar 1 FAILED on the old code: the press on the bottom face drew on the front plane, so no piece went below the top):
##   1 UNDER   a 20 x 20 mm square drawn ON THE BOTTOM face, pulled 60 mm: one body, the new piece is below the top (box min y 60 mm lower),
##             volume adds 24 000 mm3 within 1 pct
##   2 SIDE    a 10 x 10 mm square drawn on the +X side face pulls 40 mm sideways (box max x 40 mm larger), volume adds within 1 pct
##   3 GRID    a press on empty grid draws on the FLOOR (top plane, y = 0; no plane feature) (bar redefined 23c8a916: empty-space sketches go on the floor, Nick monkey-brain direction)
##   4 UNDO    the draw is one undo step, the pull another; two undos take the plane and the pull away, two redos bring them back
##   5 FILE    save and reopen keeps the plane and the same volume
## Shots: C:/Temp/claude/eface/shot.png (a table top with one leg under it), C:/Temp/claude/eface/draw_face.png (the outline on the face)
const SHOT := "C:/Temp/claude/eface"
const DIRT := "user://eface_test"

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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## a real drag: press at a, move in steps to b (held), release
func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a real drag of the slider knob to value v (held with the left button, 24 mouse steps)
func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the replay volume in mm3
func vol() -> float:
	var pu: PartUI = m.bld.part
	return float(pu.res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func planes() -> int:
	return Part.count_of(m.S.part, "plane")


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
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	# the top: a 100 x 100 x 20 mm slab on the Top plane (+Y up), its bottom face at y = 0
	var tp := Part.make("Top")
	tp["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "top", "ents": [{"k": "rect", "a": [-50.0, -50.0], "b": [50.0, 50.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"}]
	tp["seq"] = 2
	m.S.part = tp
	pu.upto = -1
	pu.sync()
	await idle(3)
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0   # from below: the bottom face is in view
	m.yaw = 0.0
	m._cam()
	await idle(60)   # the Easy camera eases to its view: the screen points below are taken after it settles
	var v0 := vol()
	var bb0: AABB = pu.res.get("aabb", AABB())
	print("top: volume %.0f mm3, min y %.1f mm, bodies %d" % [v0, bb0.position.y / Part.MM, int(pu.res.get("bodies", 0))])

	# 1 UNDER: draw on the bottom face (normal -Y)
	var u0: int = m.undo.size()
	await click_ctl(ep.make_btns["draw"])
	var p0 := scr(Vector3(0.01, 0.0, 0.01))
	var p1 := scr(Vector3(0.03, 0.0, 0.03))
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	await idle(2)
	var said: String = ep.hint_l.text
	for i in range(1, 13):
		await ev_move(p0.lerp(p1, i / 12.0))
	await shot("draw_face")
	await ev_mouse(p1, false)
	await idle(3)
	var rec: Dictionary = m.S.part
	var pl_id := ""
	var sk: Dictionary = {}
	for f in rec["features"]:
		if String(f["t"]) == "plane":
			pl_id = String(f["id"])
		if String(f["t"]) == "sketch" and String(f["plane"]) == pl_id and pl_id != "":
			sk = f
	var pf := Part.feature(rec, pl_id)
	ok(said.contains("Drawing on that face"), "1a UNDER the press on the bottom face says Drawing on that face [%s]" % said)
	ok(pl_id != "" and not sk.is_empty() and String(pf.get("from", "")) == "top" and absf(float(pf.get("mm", 9.0))) < 0.05 and int(pf.get("out", 0)) == -1,
		"1b UNDER one plane feature (from top, mm 0, out -1) with the sketch on it %s" % str(pf))
	ok(m.undo.size() == u0 + 1, "1c UNDER the draw is one undo step (%d -> %d)" % [u0, m.undo.size()])

	# the pull: 2 cm by default, dragged to 6 cm (outward = -Y)
	await click_ctl(ep.make_btns["pull"])
	ok(m.undo.size() == u0 + 2, "1h UNDER the pull is one more undo step (%d -> %d)" % [u0 + 1, m.undo.size()])
	var tw: HSlider = null
	for r in ep.rows:
		if String(r["kind"]) == "tweak":
			tw = r["slider"]
	if tw != null:
		await drag_slider(tw, 6.0)
	await idle(3)
	var bb1: AABB = pu.res.get("aabb", AABB())
	var v1 := vol()
	var said2: String = ep.hint_l.text
	ok(said2.contains("Pulled out of the face"), "1d UNDER after Pull the words say Pulled out of the face [%s]" % said2)
	ok(int(pu.res.get("bodies", 0)) == 1, "1e UNDER one body after the pull (%d)" % int(pu.res.get("bodies", 0)))
	var dy := (bb0.position.y - bb1.position.y) / Part.MM
	ok(absf(dy - 60.0) < 0.5, "1f UNDER the new piece is below the top: box min y is %.1f mm lower (want 60)" % dy)
	ok(absf((v1 - v0) - 24000.0) <= 240.0, "1g UNDER volume adds 24000 mm3 within 1 pct: %.0f -> %.0f (+%.0f)" % [v0, v1, v1 - v0])
	m.target = Vector3(0.0, -0.03, 0.0)
	m.pitch = 25.0
	m.yaw = 30.0
	m._cam()
	await shot("shot")   # the table top with one leg under it

	# 4 UNDO: three undos take the slider, the pull and the draw (plane and sketch) away; three redos bring them back
	m._undo()
	await idle(3)
	m._undo()
	await idle(3)
	m._undo()
	await idle(3)
	ok(planes() == 0 and absf(vol() - v0) < 1.0 and Part.count_of(m.S.part, "sketch") == 1,
		"4a UNDO three undos: the plane and the sketch are gone, volume back to %.0f (planes %d, sketches %d)" % [vol(), planes(), Part.count_of(m.S.part, "sketch")])
	m._redo()
	await idle(3)
	m._redo()
	await idle(3)
	m._redo()
	await idle(3)
	ok(planes() == 1 and absf(vol() - v1) < 1.0, "4b UNDO three redos: the plane is back and the pull too (volume %.0f, want %.0f)" % [vol(), v1])

	# 2 SIDE: a square on the +X side face, pulled 40 mm sideways (camera on the +X side)
	m.yaw = 40.0
	m._cam()
	await idle(60)   # the Easy camera eases to its view: the screen points below are taken after it settles
	var bb2: AABB = pu.res.get("aabb", AABB())
	var v2 := vol()
	await click_ctl(ep.make_btns["draw"])
	var s0 := scr(Vector3(0.05, 0.005, -0.005))
	var s1 := scr(Vector3(0.05, 0.015, -0.015))
	await drag_screen(s0, s1)
	var pl_n := planes()
	await click_ctl(ep.make_btns["pull"])
	var tw2: HSlider = null
	for r in ep.rows:
		if String(r["kind"]) == "tweak":
			tw2 = r["slider"]
	if tw2 != null:
		await drag_slider(tw2, 4.0)
	await idle(3)
	var bb3: AABB = pu.res.get("aabb", AABB())
	var v3 := vol()
	var last_pl: Dictionary = {}
	for f in m.S.part["features"]:
		if String(f["t"]) == "plane":
			last_pl = f
	ok(pl_n == 2 and String(last_pl.get("from", "")) == "right" and int(last_pl.get("out", 0)) == 1,
		"2a SIDE a plane from the right side, out +1 (%s)" % str(last_pl))
	ok(absf((bb3.end.x - bb2.end.x) / Part.MM - 40.0) < 0.5, "2b SIDE the piece is pulled 40 mm out to +X (max x %.1f -> %.1f mm)" % [bb2.end.x / Part.MM, bb3.end.x / Part.MM])
	ok(absf((v3 - v2) - 4000.0) <= 40.0, "2c SIDE volume adds 4000 mm3 within 1 pct (+%.0f)" % (v3 - v2))

	# 3 GRID: a press on empty grid draws on the floor (top plane, y = 0), no plane feature (bar redefined 23c8a916: empty-space sketches go on the floor, Nick monkey-brain direction)
	m.yaw = 0.0
	m._cam()
	await idle(60)   # the Easy camera eases to its view: the screen points below are taken after it settles
	var pl_before := planes()
	await click_ctl(ep.make_btns["draw"])
	var g0 := scr(Vector3(0.4, 0.0, 0.4))
	var g1 := scr(Vector3(0.45, 0.0, 0.45))
	await drag_screen(g0, g1)
	var last_sk: Dictionary = m.S.part["features"].back()
	ok(String(last_sk["t"]) == "sketch" and String(last_sk["plane"]) == "top" and planes() == pl_before,
		"3 GRID an empty-grid press draws on the floor (sketch plane %s, planes %d -> %d)" % [str(last_sk.get("plane", "")), pl_before, planes()])

	# 5 FILE: save, reopen, the plane and the volume are still there
	var nf := Part.count_of(m.S.part, "plane")
	var vf := vol()
	var path := DIRT + "/eface.json"
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	fh.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(2)
	m._load_scene(path)
	await idle(6)
	await idle(3)
	ok(Part.count_of(m.S.part, "plane") == nf and absf(vol() - vf) < 1.0 and vf > v0,
		"5 FILE saved and reopened: %d plane(s), volume %.0f (before %.0f)" % [Part.count_of(m.S.part, "plane"), vol(), vf])

	print("eface: %d fail" % fails)
	quit(1 if fails > 0 else 0)
