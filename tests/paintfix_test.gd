## godot --path . -s tests/paintfix_test.gd     (paint fixes after the expert MODEL walk: the paint panel and the Library button,
## and a press on a low-poly face). Bars, stated before measuring:
##   a at 1280x720 and at 1600x900 (root.content_scale_size pinned, CANVAS_ITEMS), vertex paint on: the Library... button's
##     rect does not intersect the paint panel's rect, and a real click on Library (root.push_input(e, true)) opens the
##     material library. A 1600x900 screenshot with paint on and Library visible is written to the scratchpad.
##   b on a 12-sided cylinder (added with Add primitive, radius 0.3 m, depth 0.5 m), one press at the centre of a side face
##     with the default brush (12 cm, smooth) paints that face's four corners (each one's colour leaves white). Premise
##     checked first: the face's nearest vertex is further from its centre than the brush radius.
##   c GUARD: on the subdivided test cube (0.6 m, 4 a side) a dab still has a falloff: the centre vertex gets the full
##     strength and a vertex at about 0.75 x the radius gets less (0 < w < w_centre), also after a real dab.
## (a) and (b) fail on the code before this round (git show HEAD:<file> in place): the FAIL lines are in the report.
extends SceneTree

const SHOT := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/paint_panels.png"

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	root.push_input(mm, true)
	await idle(2)
	await mouse(p, true)
	await mouse(p, false)
	await idle(3)


func visible_button(txt: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.text == txt and bt.is_visible_in_tree():
			return bt
	return null


## a fresh app with the model page open and paint mode on, the content pinned to `size`
func fresh_app(size: Vector2i) -> Node:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	# the suite's window keeps its host's size, so the layout size is pinned after start (as easyhome_test does)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = size
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	await idle(2)
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(3)
	m._kmesh_edit_start()
	await idle(4)
	KMeshVPaintUI.of(m).start()
	await idle(6)
	return m


func drop_app(m: Node) -> void:
	root.remove_child(m)
	m.free()
	await idle(4)


# ---------------------------------------------------------------- a

func layout_bar(size: Vector2i, shot: bool) -> void:
	var m := await fresh_app(size)
	var pu := KMeshVPaintUI.of(m)
	var lb := visible_button("Library...")
	var pr := pu.panel.get_global_rect()
	var lr := lb.get_global_rect() if lb != null else Rect2()
	ok(pu.on and lb != null and not lr.intersects(pr),
		"a %dx%d (view %s): paint on, Library... %s does not intersect the paint panel %s" % [size.x, size.y, str(root.get_visible_rect().size), str(lr), str(pr)])
	if shot:
		await idle(4)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(SHOT)
	var lib_before: bool = m.kmed.mat_panel.lib_panel != null and m.kmed.mat_panel.lib_panel.visible
	if lb != null:
		await click(lr.get_center())
	await idle(4)
	var lp: MaterialLibraryPanel = m.kmed.mat_panel.lib_panel
	var opened: bool = lp != null and lp.visible
	ok(opened and not lib_before,
		"a %dx%d: a real click on Library opens the material library (open %s)" % [size.x, size.y, str(opened)])
	await drop_app(m)


# ---------------------------------------------------------------- b

func press_bar() -> void:
	var m := await fresh_app(Vector2i(1600, 900))
	var pu := KMeshVPaintUI.of(m)
	var ui = m.kmed
	var n0: int = ui.mesh.faces.size()
	var added: bool = ui.add_prim("cylinder", {"radius": 0.3, "depth": 0.5, "segments": 12, "height_segments": 1})
	await idle(4)
	var k: KMesh = ui.mesh
	var cam: Camera3D = m.cam
	# the new faces: the 12 side quads come first (the two caps follow)
	var sides := []
	for f in range(n0, n0 + 12):
		if f < k.faces.size() and (k.faces[f] as PackedInt32Array).size() == 4:
			sides.append(f)
	ok(added and sides.size() == 12, "b0 a 12-sided cylinder is added beside the cube (%d side quads)" % sides.size())
	if sides.is_empty():
		await drop_app(m)
		return
	var wc: Vector3 = ui.view.global_transform * k.face_center(sides[0])
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	# the side face that faces the camera most and is in view
	var best := -1
	var best_dot := -INF
	for f in sides:
		var wp: Vector3 = ui.view.global_transform * k.face_center(f)
		if not ui.view.point_visible(cam, wp):
			continue
		var fv: PackedInt32Array = k.faces[f]
		var nl: Vector3 = (k.verts[fv[1]] - k.verts[fv[0]]).cross(k.verts[fv[2]] - k.verts[fv[0]])
		var nrm: Vector3 = (ui.view.global_transform.basis * nl).normalized()
		var dd := nrm.dot((cam.global_position - wp).normalized())
		if dd > best_dot:
			best_dot = dd
			best = f
	var fc: Vector3 = k.face_center(best) if best >= 0 else Vector3.ZERO
	# the premise: the nearest vertex is further from the centre than the brush reaches
	var near_d := INF
	for v in k.verts.size():
		near_d = minf(near_d, k.verts[v].distance_to(fc))
	var r: float = pu.radius
	ok(best >= 0 and near_d > r, "b1 premise: the face's nearest vertex is %.3f m from its centre, past the %.3f m brush" % [near_d, r])
	var corners: PackedInt32Array = k.faces[best] if best >= 0 else PackedInt32Array()
	var before := []
	for v in corners:
		before.append(KMeshVPaint.vert_color(k, v))
	var s: Vector2 = cam.unproject_position(ui.view.global_transform * fc)
	var n_steps: int = ui.undo.steps.size()
	await click(s)
	var after := []
	for v in corners:
		after.append(KMeshVPaint.vert_color(k, v))
	var painted := 0
	for i in corners.size():
		if after[i] != before[i] and after[i].g < 0.9:
			painted += 1
	var one_step: bool = ui.undo.steps.size() == n_steps + 1
	ok(corners.size() == 4 and painted == 4 and one_step,
		"b2 one press at the face centre (brush %d mm) paints its %d corners (%d changed, first corner %s -> %s, one undo step %s)" % [
			roundi(r * 1000.0), corners.size(), painted, str(before[0]) if before.size() > 0 else "-", str(after[0]) if after.size() > 0 else "-", str(one_step)])
	await drop_app(m)


# ---------------------------------------------------------------- c

func falloff_guard() -> void:
	var k := KMeshView.make_cube(0.6, 4)
	KMeshVPaint.ensure(k)
	var vp := KMeshVPaint.new()
	var r := 0.2
	vp.begin(k, {"color": Color(0, 1, 0, 1), "mode": KMeshVPaint.MIX, "radius": r, "strength": 1.0})
	var v0 := 0
	var bd := INF
	for v in k.verts.size():
		var d := k.verts[v].length()
		if d < bd:
			bd = d
			v0 = v
	var hit := k.verts[v0]
	var ws := vp.weights(hit, 1.0)
	var w_centre: float = ws.get(v0, 0.0)
	var mid := -1
	var w_mid := 0.0
	for v in ws:
		var d := k.verts[v].distance_to(hit)
		if absf(d - 0.75 * r) < 0.02 and v != v0:
			mid = v
			w_mid = ws[v]
	ok(absf(w_centre - 1.0) < 1e-6 and mid >= 0 and w_mid > 0.0 and w_mid < w_centre,
		"c1 the test cube's dab: the centre vertex gets %.3f, a vertex at 0.75 x the radius gets %.3f (less: the falloff is still there)" % [w_centre, w_mid])
	vp.dab(hit, 1.0)
	var cc := KMeshVPaint.vert_color(k, v0)
	var cm := KMeshVPaint.vert_color(k, mid) if mid >= 0 else Color.WHITE
	ok(cc.g > 0.999 and cc.r < 0.001 and cm.r > 0.01 and cm.r < 0.99,
		"c2 after a real dab: centre %s (full green), 0.75 x radius %s (partly painted)" % [str(cc), str(cm)])


func _init() -> void:
	await layout_bar(Vector2i(1280, 720), false)
	await layout_bar(Vector2i(1600, 900), true)
	await press_bar()
	falloff_guard()
	print("paintfix: %d failing" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
