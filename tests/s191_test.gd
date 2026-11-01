extends SceneTree
## godot --path . --position 4000,4000 -s tests/s191_test.gd   (EASY PART: Friday 191 "Sketch with sizes (AI)": scripts/easy_part_sketch_ai.gd, the Trace box; needs the CAD DLL)
## NO NETWORK: the model's reply is a recorded file (tests/fixtures/s191_reply_ok.json / _bad.json, the Anthropic message shape) read through
## EasyPartSketchAI.fixture_path; EasyPartSketchAI.sends counts real sends and must stay 0.
## Bars (real clicks at 1280 x 720; numbers measured from the built mesh):
##   a generated sketch PNG (80 x 40 rectangle, a 10 mm circle, written sizes) + the fixture reply: the part is 80.0 x 40.0 mm within 0.5, thickness 10,
##   ONE through hole of 10.0 mm measured from the mesh vertices; the undo steps are Draw shape / Pull it up / Cut a hole (each its own); a step row opens its slider
##   and a slider change edits the part; a malformed reply (step "teleport") builds nothing, adds no undo step, says why; no key = words + the Trace offer
##   (Trace it lit, nothing sent); Trace it still works after; the exact prompt is printed
## Shots: C:/Temp/claude/s191/trace_box.png, built.png, refused.png, nokey.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s191"
const DIRT := "user://s191_test"
var pu: PartUI
var ep


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func nd(n: String) -> Node:
	return root.find_child(n, true, false)




## the built part measured from the mesh (mm): bbox, and the through holes = clusters of vertices strictly inside the outline (the faces' only inner vertices are hole walls)
func geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var all := PackedVector3Array()
	for f in faces:
		for v in (f as PackedVector3Array):
			var p: Vector3 = v * 1000.0
			all.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
	if all.is_empty():
		return {}
	var clusters: Array = []
	for p in all:
		if p.x > lo.x + 0.8 and p.x < hi.x - 0.8 and p.z > lo.z + 0.8 and p.z < hi.z - 0.8:
			var hit := -1
			for i in clusters.size():
				if Vector2(p.x, p.z).distance_to(clusters[i]["c"]) < 12.0:
					hit = i
					break
			if hit < 0:
				clusters.append({"pts": [p], "c": Vector2(p.x, p.z)})
			else:
				(clusters[hit]["pts"] as Array).append(p)
				var s := Vector2.ZERO
				for q in clusters[hit]["pts"]:
					s += Vector2(q.x, q.z)
				clusters[hit]["c"] = s / (clusters[hit]["pts"] as Array).size()
	var out := {"x": hi.x - lo.x, "y": hi.y - lo.y, "z": hi.z - lo.z, "ymin": lo.y, "holes": clusters.size()}
	if clusters.size() >= 1:
		var pts: Array = clusters[0]["pts"]
		var c0: Vector2 = clusters[0]["c"]
		var rs := 0.0
		var y0 := 1e9
		var y1 := -1e9
		for q in pts:
			rs += Vector2(q.x, q.z).distance_to(c0)
			y0 = minf(y0, q.y)
			y1 = maxf(y1, q.y)
		out["hole_d"] = 2.0 * rs / pts.size()
		out["hole_h"] = y1 - y0
	return out


const DIG := {"0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg"}


func seg(im: Image, x0: int, y0: int, s: int, ch: String, col: Color) -> void:
	var r := {"a": Rect2i(x0, y0, s, 3), "d": Rect2i(x0, y0 + 2 * s, s, 3), "g": Rect2i(x0, y0 + s, s, 3),
		"f": Rect2i(x0, y0, 3, s), "b": Rect2i(x0 + s - 3, y0, 3, s), "e": Rect2i(x0, y0 + s, 3, s), "c": Rect2i(x0 + s - 3, y0 + s, 3, s)}
	for k in String(DIG[ch]):
		im.fill_rect(r[k], col)


func text7(im: Image, x: int, y: int, t: String, col: Color) -> void:
	for i in t.length():
		seg(im, x + i * 36, y, 24, t[i], col)


## a photo of a pencil sketch: grey paper, an 80 x 40 rectangle (10 px per mm), a 10 mm circle, the sizes written beside them
func sketch_png() -> String:
	var im := Image.create(1000, 600, false, Image.FORMAT_RGB8)
	im.fill(Color(0.87, 0.86, 0.82))
	var ink := Color(0.12, 0.12, 0.16)
	var cx := 500
	var cy := 300
	for t in 3:
		im.fill_rect(Rect2i(cx - 400, cy - 200 + t, 800, 1), ink)
		im.fill_rect(Rect2i(cx - 400, cy + 200 - t, 800, 1), ink)
		im.fill_rect(Rect2i(cx - 400 + t, cy - 200, 1, 400), ink)
		im.fill_rect(Rect2i(cx + 400 - t, cy - 200, 1, 400), ink)
	for a in 360:
		var p := Vector2(cx, cy) + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * 50.0
		im.fill_rect(Rect2i(int(p.x), int(p.y), 3, 3), ink)
	text7(im, cx - 36, 20, "80", ink)
	text7(im, cx + 430, cy - 20, "40", ink)
	text7(im, cx + 60, cy + 70, "10", ink)
	var d := ProjectSettings.globalize_path(DIRT)
	DirAccess.make_dir_recursive_absolute(d)
	var p := d + "/sketch_80x40.png"
	im.save_png(p)
	return p


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
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
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	EasyPartSketchAI.fixture_path = ""
	var ok_fx := ProjectSettings.globalize_path("res://tests/fixtures/s191_reply_ok.json")
	var bad_fx := ProjectSettings.globalize_path("res://tests/fixtures/s191_reply_bad.json")
	var png := sketch_png()
	print("PROMPT AS SENT:\n", EasyPartSketchAI.prompt_text(), "\n--- end of prompt")

	await click_ctl(nd("easypart_make_draw") as Button)
	var tb := nd("easypart_shape_trace") as Button
	await click_ctl(tb)
	var fd := nd("easypart_trace_dialog")
	if fd != null:
		fd.queue_free()
	await idle(2)
	ep.tracer.chosen(png)
	await idle(3)
	(nd("easypart_trace_width") as SpinBox).value = 80.0
	await idle(3)
	var ab := nd("easypart_sketch_ai") as Button
	ok(ab != null and ab.is_visible_in_tree() and vp.encloses(ab.get_global_rect()) and ab.text == "Sketch with sizes (AI)", "191 the 'Sketch with sizes (AI)' option is in the Trace box, on screen")
	var tbox := (nd("easypart_trace") as Control).get_global_rect()
	ok(vp.encloses(tbox) and not tbox.intersects((nd("easypart_panel") as Control).get_global_rect()) and not tbox.intersects((nd("easypart_make") as Control).get_global_rect()), "191 the Trace box %s is clear of the Easy panel and the make row" % str(tbox))
	await shot("trace_box")

	# ---- no key: Anthropic selected in the Ask AI box, key row empty, no fixture
	m._ai_toggle()
	await idle(2)
	var box: AiBox = m.ui_ai
	box.ui_backend.select(LlmClient.BACKENDS.find("anthropic"))
	box.ui_key.text = ""
	m._ai_toggle()
	await idle(2)
	var u0: int = m.undo.size()
	var s0 := EasyPartSketchAI.sends
	await click_ctl(ab)
	await idle(3)
	var info := (nd("easypart_trace_info") as Label).text
	print("no-key words: ", info)
	ok(info.contains("no AI key") and info.contains("Trace it") and info.contains("did not run"), "191 no key: the words say so and offer the local Trace")
	ok(EasyPartSketchAI.sends == s0 and m.undo.size() == u0 and (m.S.part.get("features", []) as Array).is_empty(), "191 no key: nothing sent (%d sends), nothing built, no undo step" % (EasyPartSketchAI.sends - s0))
	var gbtn := nd("easypart_trace_go") as Button
	ok(gbtn.modulate != Color.WHITE and not gbtn.disabled, "191 no key: the Trace it button is lit as the offer")
	await shot("nokey")

	# ---- the malformed reply: step "teleport"
	EasyPartSketchAI.fixture_path = bad_fx
	await click_ctl(ab)
	await idle(3)
	info = (nd("easypart_trace_info") as Label).text
	print("refused words: ", info)
	ok(info.contains("teleport") and info.contains("not an Easy step") and info.to_lower().contains("nothing was built"), "191 an unknown step 'teleport' is refused in words")
	ok(m.undo.size() == u0 and (m.S.part.get("features", []) as Array).is_empty(), "191 the refused reply built nothing and added no undo step (%d -> %d, %d features)" % [u0, m.undo.size(), (m.S.part.get("features", []) as Array).size()])
	await shot("refused")
	var vv := EasyPartSketchAI.validate('{"steps":[{"step":"Pull it up","mm":5}]}')
	ok(not vv["ok"] and String(vv["why"]).contains("before any Draw shape"), "191 schema: Pull it up before Draw shape refused: " + String(vv["why"]))
	vv = EasyPartSketchAI.validate('{"steps":[{"step":"Draw shape","shape":"rect","width":80,"height":40},{"step":"Pull it up","mm":10},{"step":"Cut a hole","diameter":50,"x":0,"y":0}]}')
	ok(not vv["ok"] and String(vv["why"]).contains("does not fit"), "191 schema: a hole bigger than the part refused: " + String(vv["why"]))
	vv = EasyPartSketchAI.validate("sorry, I cannot read it")
	ok(not vv["ok"], "191 schema: prose with no JSON refused: " + String(vv["why"]))

	# ---- the good reply
	EasyPartSketchAI.fixture_path = ok_fx
	await click_ctl(ab)
	await idle(6)
	info = (nd("easypart_trace_info") as Label).text
	print("built words: ", info)
	ok(EasyPartSketchAI.sends == s0, "191 the fixture path made no network send (%d)" % (EasyPartSketchAI.sends - s0))
	var g := geom()
	ok(not g.is_empty() and absf(float(g["x"]) - 80.0) <= 0.5 and absf(float(g["z"]) - 40.0) <= 0.5, "191 the built part is %.2f x %.2f mm (bar 80.0 x 40.0 within 0.5)" % [float(g.get("x", 0)), float(g.get("z", 0))])
	ok(not g.is_empty() and absf(float(g["y"]) - 10.0) <= 0.2 and absf(float(g["ymin"])) <= 0.1, "191 and %.2f mm thick, on the floor (ymin %.2f)" % [float(g.get("y", 0)), float(g.get("ymin", 0))])
	ok(int(g.get("holes", 0)) == 1, "191 exactly %d through hole in the mesh (bar 1)" % int(g.get("holes", 0)))
	ok(absf(float(g.get("hole_d", 0)) - 10.0) <= 0.2 and absf(float(g.get("hole_h", 0)) - 10.0) <= 0.2, "191 the hole measures %.2f mm across, %.2f mm of wall (bar 10.0 within 0.2, through the 10 mm part)" % [float(g.get("hole_d", 0)), float(g.get("hole_h", 0))])
	var vol := float(pu.res.get("volume", 0.0)) * 1e9
	var want := (80.0 * 40.0 - PI * 25.0) * 10.0
	ok(absf(vol - want) <= 0.02 * want and int(pu.res.get("bodies", 0)) == 1, "191 volume %.0f mm3 (bar %.0f within 2 pct), one solid" % [vol, want])
	var hints: Array = []
	for i in range(u0, m.undo.size()):
		hints.append(String(m.undo[i].get("hint", "")))
	print("undo hints: ", hints)
	ok(m.undo.size() == u0 + 3 and hints.size() == 3 and hints[0] == "Draw shape" and hints[1] == "Pull it up" and hints[2] == "Cut a hole", "191 three undo steps, each its own: %s" % str(hints))
	var rows: Array = []
	for c in (nd("easypart_steps_list") as Control).get_children():
		rows.append((c as Button).text)
	print("steps list: ", rows)
	ok(rows.size() == 4 and rows[0] == "Drew a shape" and String(rows[1]).begins_with("Pulled up") and rows[2] == "Drew a shape" and String(rows[3]).begins_with("Cut a"), "191 Your steps lists the outline, the pull, and the hole (its circle + its cut, as the Cut a hole button makes it): %s" % str(rows))
	ok(info.contains("Draw shape, Pull it up, Cut a hole"), "191 the words name the three steps")
	await shot("built")
	var pull_id := ""
	for f in m.S.part["features"]:
		if String(f["t"]) == "extrude" and String(f.get("op", "")) != "cut":
			pull_id = String(f["id"])
	await click_ctl(nd("easypart_step_" + pull_id) as Button)
	var sl: HSlider = null
	for c in nd("easypart_panel").find_children("easypart_slider_*", "HSlider", true, false):
		if (c as Control).is_visible_in_tree():
			sl = c
	ok(sl != null, "191 clicking the Pulled up row brings its slider back")
	var u1: int = m.undo.size()
	if sl != null:
		print("slider ", sl.name, " range ", sl.min_value, "..", sl.max_value, " now ", sl.value)
		sl.value = 2.0
	await idle(6)
	var g2 := geom()
	print("after slider: ", g2)
	ok(not g2.is_empty() and absf(float(g2["y"]) - 20.0) <= 0.3 and int(g2.get("holes", 0)) == 1 and absf(float(g2["hole_d"]) - 10.0) <= 0.2 and absf(float(g2["x"]) - 80.0) <= 0.5, "191 the slider made it %.2f mm thick, still 80 wide with the %.2f mm hole (the hole step replays)" % [float(g2.get("y", 0)), float(g2.get("hole_d", 0))])
	ok(m.undo.size() == u1 + 1, "191 the slider change is its own undo step (%d -> %d)" % [u1, m.undo.size()])
	m._undo()
	await idle(4)
	m._undo()
	await idle(4)
	var nf: int = (m.S.part.get("features", []) as Array).size()
	ok(nf == 2, "191 two Undos after the slider take back the slider and the hole: %d features left (bar 2: sketch, pull)" % nf)
	while m.undo.size() > u0:
		m._undo()
		await idle(3)
	ok((m.S.part.get("features", []) as Array).is_empty(), "191 undoing all of it leaves an empty part")
	gbtn.modulate = Color.WHITE
	await click_ctl(nd("easypart_trace_go") as Button)
	await idle(4)
	var tg := geom()
	var pim := Image.load_from_file(png)
	var xlo := 1e9
	var xhi := -1.0
	for yy in pim.get_height():
		for xx in pim.get_width():
			if pim.get_pixel(xx, yy).v < 0.5:
				xlo = minf(xlo, xx)
				xhi = maxf(xhi, xx)
	var ink_mm := (xhi - xlo + 1.0) * 80.0 / 1000.0   # the local Trace takes all the ink, the written sizes too
	ok(not tg.is_empty() and absf(float(tg["x"]) - ink_mm) <= 1.0, "191 the local Trace still works on the same photo (%.1f mm wide, bar %.1f: the ink span at width 80, written sizes included)" % [float(tg.get("x", 0)), ink_mm])
	print("s191: %d fail" % fails)
	quit()
