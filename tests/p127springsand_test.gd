extends SceneTree
## P127 SPRINGS AND GRAVITY, first step: "Does it fall over?" (Friday plan item 127; Kine's own idea, light physics, no simulation).
## A beginner from the BUILDING card makes a box (12 x 8 cm), Pull it up, and opens Colour: a "Does it fall over?" chip reads whether
## the built solid stands on its feet (its middle of mass lies over the lowest surface) and how far the middle is inside or past them.
## Real clicks and presses at 1280 x 720. Every number is measured from the built result (the mesh's own vertices, in mm), never
## from the code's variables. The test's own expectation is computed from the mesh alone.
##   BUILDING card -> Easy Part (blank) -> Draw shape (box 12 x 8 cm) -> Pull it up -> Colour -> Does it fall over?
##   -> Tilt it 20 degrees -> Does it fall over? -> Undo x2 -> Does it fall over? (no solid)
## Bars (written before the code):
##   S0 after Colour, the "Does it fall over?" chip is on the screen, inside the window
##   S1 a plain box stands: the words say "stands" and the margin is the box's half width on its short side (its own vertices: 40 mm, within 1 mm)
##   S2 a press changes nothing in the Part (same JSON) and makes no undo step
##   S3 the tilted box: the words say "falls over" exactly when the mesh's own feet put the middle outside them, and the mm in the words is the mesh's distance (within 1 mm)
##   S4 with no solid the words say "No solid yet" and name the next step ("Pull it up")
##   S5 no jargon on the chip or the words (sketch, extrude, boolean, feature, body, loft, cylinder, plane, kernel, vertex)
## shots: C:/Temp/claude/p127springsand/plate.png, stand.png
const SHOT := "C:/Temp/claude/p127springsand"
const DIRT := "user://p127springsand_test"
const FOOT := 0.0005   # m: a vertex this close to the lowest height is a foot (the test's own tolerance)
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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


## the built mesh's own vertices (metres, the Part's frame: y up)
func verts_of(s: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = s["mesh"]
	for i in mesh.get_surface_count():
		out.append_array(mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX])
	return out


## the test's own reading of the mesh: the feet = vertices within FOOT of the lowest height; the middle = the mean of all vertices
## (for a box that is its centre). Returns {"feet": [Vector2 xz], "mid": Vector2 xz, "lo": the lowest height
## along the line of the feet when they form a line, else the box's half width in mm}
func mesh_facts(vs: PackedVector3Array) -> Dictionary:
	var lo := INF
	for v in vs:
		lo = minf(lo, v.y)
	var feet := []
	var mid := Vector2.ZERO
	for v in vs:
		mid += Vector2(v.x, v.z)
		if v.y <= lo + FOOT:
			feet.append(Vector2(v.x, v.z))
	mid /= maxf(1.0, float(vs.size()))
	return {"feet": feet, "mid": mid, "lo": lo}


## the words' mm number: "... 40 mm inside ..." or "... 12 mm past ..." -> the number; -999 when there is none
func mm_of(t: String) -> float:
	var rx := RegEx.new()
	rx.compile("(\\d+) mm (inside|past)")
	var mt := rx.search(t)
	if mt == null:
		return -999.0
	var v := float(mt.get_string(1))
	return -v if mt.get_string(2) == "past" else v


func stand_chip(ep) -> Button:
	return ep.colour_box.find_child("easypart_stand_check", true, false) as Button


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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# the plate: a box on the grid (12 cm x 8 cm), Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.06, 0.0, -0.04)), scr(Vector3(0.06, 0.0, 0.04))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	ok(int(s1["bodies"]) == 1, "plate: one body, volume %.1f cm3" % (float(s1["volume"]) * 1.0e6))

	# S0 + S1 Colour shows the chip; the box stands
	await click_ctl(ep.make_btns["colour"])
	await idle(10)
	await shot("plate")
	var window := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var b := stand_chip(ep)
	ok(ep.colour_box.visible and b != null and b.is_visible_in_tree() and window.encloses(b.get_global_rect()),
		"S0 after Colour: the 'Does it fall over?' chip is on the screen")
	var f1 := mesh_facts(verts_of(solid()))
	var hx := 0.0
	var hz := 0.0
	for v in verts_of(solid()):
		hx = maxf(hx, absf(v.x))
		hz = maxf(hz, absf(v.z))
	var half_mm := minf(hx, hz) * 1000.0   # the box's own half width on its short side, from its vertices
	await click_ctl(b)
	await idle(5)
	var words1 := String(ep.msg)
	var mm1 := mm_of(words1)
	ok(words1.find("stands") >= 0 and absf(mm1 - half_mm) < 1.0,
		"S1 a plain box stands: the words say so, margin %.1f mm vs the mesh's %.1f mm: %s" % [mm1, half_mm, words1])

	# S2 a press changes nothing and makes no undo step
	var before := JSON.stringify(m.S.part)
	var n0: int = m.undo.size()
	await click_ctl(b)
	await idle(3)
	ok(JSON.stringify(m.S.part) == before and m.undo.size() == n0,
		"S2 the press changes nothing (undo count %d -> %d)" % [n0, m.undo.size()])

	# S3 tilt 20 degrees (the Colour page is shut first: the tilt panel shows only with no tool armed), then Colour, then the chip
	await click_ctl(ep.make_btns["colour"])
	await idle(5)
	var untilted := JSON.stringify(m.S.part)
	await click_ctl(ep.tilt_btn)
	await idle(10)
	var tilted := JSON.stringify(m.S.part) != untilted
	await click_ctl(ep.make_btns["colour"])
	await idle(10)
	await click_ctl(stand_chip(ep))
	await idle(5)
	var vt := verts_of(solid())
	var ft := mesh_facts(vt)
	var expect_falls := false
	var dist_mm := 0.0
	var feet: Array = ft["feet"]
	if feet.size() >= 1:
		# the feet are a line (a tilted box rests on an edge) or a face: the middle is inside only when it is over the feet's hull
		var fa: Vector2 = feet[0]
		var collinear := false
		var fmin := Vector2(INF, INF)
		var fmax := Vector2(-INF, -INF)
		for p in feet:
			fmin = fmin.min(p)
			fmax = fmax.max(p)
		var span := fmax - fmin
		var mid: Vector2 = ft["mid"]
		# the middle over the feet's rectangle (a box's feet): inside by the nearest side, else outside by the distance to the feet
		var inside_x := mid.x >= fmin.x - 1e-9 and mid.x <= fmax.x + 1e-9
		var inside_z := mid.y >= fmin.y - 1e-9 and mid.y <= fmax.y + 1e-9
		collinear = span.x < 1e-6 or span.y < 1e-6
		if collinear:
			var d := 0.0
			if span.x < 1e-6:
				d = absf(mid.x - fa.x)
			else:
				d = absf(mid.y - fa.y)
			dist_mm = d * 1000.0
			expect_falls = d > 1e-6
		else:
			var inside := inside_x and inside_z
			var side := minf(minf(mid.x - fmin.x, fmax.x - mid.x), minf(mid.y - fmin.y, fmax.y - mid.y))
			dist_mm = (side if inside else -maxf(0.0, -side)) * 1000.0
			expect_falls = not inside
	var words3 := String(ep.msg)
	var mm3 := mm_of(words3)
	var said_falls := words3.find("falls over") >= 0
	var ok3 := said_falls == expect_falls and (absf(absf(mm3) - absf(dist_mm)) < 1.0 or not expect_falls)
	ok(tilted and ok3, "S3 tilted box (the tilt changed the Part: %s): falls=%s (mesh says %s), mesh distance %.1f mm, words: %s" % [str(tilted), str(said_falls), str(expect_falls), dist_mm, words3])
	await shot("stand")

	# S4 no solid: Undo the tilt and the pull; the chip names the next step
	await click_ctl(ep.undo_btn)
	await idle(10)
	await click_ctl(ep.undo_btn)
	await idle(10)
	if not ep.colour_box.visible:
		await click_ctl(ep.make_btns["colour"])
		await idle(5)
	await click_ctl(stand_chip(ep))
	await idle(5)
	var words4 := String(ep.msg)
	ok(words4.find("No solid yet") >= 0 and words4.find("Pull it up") >= 0, "S4 no solid: the words say so and name the next step: %s" % words4)

	# S5 no jargon on the chip or the words
	var lab := []
	labels(ep.colour_box, lab)
	lab.append(stand_chip(ep).text)
	var said := " ".join(lab) + " " + words1 + " " + words3 + " " + words4
	var jargon := []
	for w in ["sketch", "extrude", "boolean", "feature", "body", "loft", "cylinder", "plane", "kernel", "vertex"]:
		if said.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty(), "S5 no jargon %s on the chip and the words" % [jargon])
	print("p127springsand: %d fail" % fails)
	quit(1 if fails > 0 else 0)
