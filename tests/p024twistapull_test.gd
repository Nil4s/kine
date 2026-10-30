extends SceneTree
## godot --path . --position 4000,4000 -s tests/p024twistapull_test.gd     (P024 Friday item 24: Twist a pulled shape; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from the start screen: the BUILDING card opens a blank Easy Part; a square (Box) is drawn on the floor,
## 80 mm across, and pulled up to 10 cm. The Twist slider shows under How far (the newest pull only); a drag to 45 degrees turns the top of the
## shape a quarter-turn away from its floor (a twisted post). Everything is measured from the built mesh, never from the code's own numbers.
## Bars (the run on the code before the change is recorded in the report):
##   0 CARD    the BUILDING card, one click: page BUILD, Easy Part on, the part is empty
##   1 BODY    Draw shape Box, drag 80 mm, Pull it up, 10 cm slider: one solid, 100 mm tall (within 6 mm); across at the floor 80 mm (within 6 mm)
##   2 ROW     a Twist slider shows under How far (the newest pull)
##   3 TWIST   drag Twist to 45 degrees: the top is turned: its widest point across x is 50 to 62 mm (a square's corner on the axis: 56.6 mm)
##   4 FLOOR   the floor is still square: its widest point across x at 5 mm up is 37 to 43 mm (the twist starts at the floor)
##   5 ONE     the Twist drag is one undo step
##   6 WORDS   no sketch / extrude / fillet / boolean / loft / revolve words on screen
## shots: C:/Temp/claude/p024twistapull/card.png, body.png, twist.png (LOOK at them)
const SHOT := "C:/Temp/claude/p024twistapull"
const DIRT := "user://p024twistapull_test"

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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a real drag of a slider knob to value v (the slider's own units)
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


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func bodies() -> int:
	return int(pu().res.get("bodies", 0))


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func undo_n() -> int:
	return m.undo.size()


## the mesh's triangles in world metres
func world_tris() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi: MeshInstance3D = pu().part_mesh
	if mi == null or mi.mesh == null:
		return out
	var t := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for v in vs:
				out.append(t * v)
		else:
			for i in ix:
				out.append(t * vs[i])
	return out


## the widest point across x (mm, from the middle line) where the mesh crosses the plane y = h (mm above the floor): edge crossings
func width_x_at(h_mm: float) -> float:
	var h := h_mm / 1000.0
	var best := 0.0
	var tris := world_tris()
	for k in range(0, tris.size() - 2, 3):
		for e in [[0, 1], [1, 2], [2, 0]]:
			var a := tris[k + e[0]]
			var b := tris[k + e[1]]
			if absf(a.y - b.y) < 1e-9 or (a.y - h) * (b.y - h) > 0.0:
				continue
			var p := a.lerp(b, (h - a.y) / (b.y - a.y))
			best = maxf(best, absf(p.x))
	return best * 1000.0


func bad_words(texts: Array) -> Array:
	var out := []
	for t in texts:
		var l := String(t).to_lower()
		for w in ["sketch", "extrude", "fillet", "boolean", "loft", "revolve"]:
			if l.find(w) >= 0:
				out.append(String(t))
				break
	return out


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

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var feats: Array = m.S.part.get("features", [])
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and feats.is_empty(),
		"0 BUILDING card, one click: page BUILD, Easy Part on, the part is empty (page %s, steps %d)" % [m.cur_page, feats.size()])
	await shot("card")

	# the camera: the floor from above at an angle
	m.target = Vector3.ZERO
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 1 BODY: Draw shape Box (the default), a drag of an 80 mm square centred on the floor's middle, Pull it up, 10 cm
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.04)), scr(Vector3(0.04, 0.0, 0.04)))
	var u0 := undo_n()
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 10.0)
	await idle(3)
	var bb := bbox()
	var floor_w := width_x_at(5.0)
	ok(bodies() == 1 and absf(bb.size.y - 100.0) <= 6.0 and absf(floor_w - 40.0) <= 3.0,
		"1 BODY one solid, 100 mm tall, 80 mm square at the floor (bodies %d, height %.1f mm, half width at 5 mm %.1f mm)" % [bodies(), bb.size.y, floor_w])
	await shot("body")

	# 2 ROW: the Twist slider shows under How far
	var twist_row = ep().get("twist_row")   # null on the old code (no Twist row)
	ok(twist_row is Dictionary and not (twist_row as Dictionary).is_empty(), "2 ROW a Twist slider shows under How far")

	# 3 TWIST: a beginner drags Twist to 45 degrees; the top is turned a quarter-turn-ish away from the floor
	var u1 := undo_n()
	if twist_row is Dictionary and not (twist_row as Dictionary).is_empty():
		await drag_slider(twist_row["slider"], 45.0)
	await idle(5)
	var top_w := width_x_at(90.0)
	ok(bodies() == 1 and top_w >= 50.0 and top_w <= 62.0,
		"3 TWIST the top is turned: widest across x at 9 cm is %.1f mm (a square turned 45 degrees: 56.6 mm; straight: 40)" % top_w)
	await shot("twist")

	# 4 FLOOR: the twist starts at the floor, which is still square
	var floor_t := width_x_at(5.0)
	ok(absf(floor_t - 40.0) <= 3.0 and absf(floor_t - floor_w) <= 2.0,
		"4 FLOOR the floor is still square: widest across x at 5 mm is %.1f mm (40 straight)" % floor_t)

	# 5 ONE: the Twist drag is one undo step
	ok(undo_n() - u1 == 1, "5 ONE the Twist drag is one undo step (undo %d -> %d)" % [u1, undo_n()])

	# 6 WORDS
	var texts: Array = []
	texts_under(m, texts)
	var bw := bad_words(texts)
	ok(bw.is_empty(), "6 WORDS no sketch / extrude / fillet / boolean / loft / revolve on screen %s" % [bw])

	print("p024twistapull: %d fail" % fails)
	quit(1 if fails > 0 else 0)
