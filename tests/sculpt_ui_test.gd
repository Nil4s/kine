## godot --path . -s tests/sculpt_ui_test.gd     (ROADMAP_400 C01 + C02; needs a window: real mouse / key events, pixels read back)
## "Sculpt: a test sphere (preview)": a sphere (3 458 verts, r = 0.3 m) on the stage, seen from the front, 1.6 m away. Bars:
##   1 the command opens it (3 458 verts, closed); the greyed SCULPT page now lists it as working
##   2 DRAW STROKE: a 60 px left drag across the front of the sphere moves verts, every moved vert farther from the centre
##     (draw pushes out), and is ONE undo step; Ctrl+Z puts every vert back exactly
##   3 GRAB: G, then a 40 px drag up from the front centre lifts the vert under the press (world y up by > 1 cm) and moves no
##     vert of the back half
##   4 PLACEMENT (shot -> /tmp/claude-0/sp/sculpt.png): the view sits at (1.0, 0.3, 0) within 1 mm, rests on the floor (lowest
##     vert y = 0 within 1 mm), its projected outline is inside the frame, the pixel at its projected centre differs from the
##     same pixel with the sphere hidden (> 0.1), the brush ring is drawn (a ring pixel differs from the same pixel with
##     the overlay hidden)
##   5 Esc leaves: the view is gone, the command opens it again
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshSculptUI


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
	root.push_input(e)
	await process_frame


func move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func drag(a: Vector2, b: Vector2, steps := 8) -> void:
	await mouse(a, true)
	for k in steps:
		await move(a.lerp(b, (k + 1) / float(steps)))
	await mouse(b, false)
	await idle(2)


func key(k: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._sculpt_start()
	await idle(3)
	ui = m.ksc
	var why := ""
	for b in m.ui_ribbon["SCULPT"].get_children():
		if b is Button:   # the row's group separators are not buttons
			why += String(b.text) + ", "
	ok(ui.on and ui.mesh.vert_count() == 3458 and ui.mesh.is_closed() and why.contains("Test sphere"),
		"(1) the command opens the sphere: %d verts, closed %s; the SCULPT ribbon has: %s" % [ui.mesh.vert_count(), ui.mesh.is_closed(), why.left(200)])
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cam: Camera3D = m.cam
	var cs := cam.unproject_position(wc)
	var front := cam.global_position - wc
	# 2 draw stroke
	var v0 := ui.mesh.verts.duplicate()
	await drag(cs + Vector2(-30, 0), cs + Vector2(30, 0))
	var moved := 0
	var outward := true
	for v in v0.size():
		if ui.mesh.verts[v] != v0[v]:
			moved += 1
			outward = outward and ui.mesh.verts[v].length() > v0[v].length() - 1e-7
	var steps: int = ui.undo.steps.size()
	await key(KEY_Z, true)
	ok(moved > 10 and outward and steps == 1 and ui.mesh.verts == v0,
		"(2) draw stroke: %d verts moved, all outward %s, %d dabs = %d undo step; Ctrl+Z exact %s" % [moved, outward, ui.sculpt.dabs, steps, ui.mesh.verts == v0])
	# 3 grab
	await key(KEY_G)
	var hit: Dictionary = ui.surface_at(cam, cs)
	var gv := -1
	var bd := INF
	for v in ui.mesh.verts.size():
		var d: float = (ui.view.global_transform * ui.mesh.verts[v]).distance_to(hit["point"])
		if d < bd:
			bd = d
			gv = v
	var g0 := ui.mesh.verts.duplicate()
	await drag(cs, cs + Vector2(0, -40))
	var lift: float = ui.mesh.verts[gv].y - g0[gv].y
	var back_still := true
	for v in g0.size():
		if (ui.view.global_transform * g0[v] - wc).dot(front) < 0.0 and ui.mesh.verts[v] != g0[v]:
			back_still = false
	ok(lift > 0.01 and back_still and ui.undo.steps.size() == 1, "(3) grab: the vert under the press rose %.4f m, back half still %s, %d undo step" % [lift, back_still, ui.undo.steps.size()])
	# 4 placement
	var lo := INF
	for v in ui.mesh.verts.size():
		lo = minf(lo, (ui.view.global_transform * ui.mesh.verts[v]).y)
	var vp := root.get_visible_rect().size
	var inside := true
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN]:
		var sp := cam.unproject_position(wc + dir * KMeshSculptUI.R)
		inside = inside and Rect2(Vector2.ZERO, vp).has_point(sp)
	m.ui_root.visible = false
	await move(cs + Vector2(0, 10), false)
	ui._ov.visible = true
	ui._ov.reparent(root)   # the ring overlay stays on while the rest of the UI is hidden for the shot
	var img := await shot()
	img.save_png("/tmp/claude-0/sp/sculpt.png")
	var ring: Vector2 = Vector2.ZERO
	if not ui._hover.is_empty():
		var hp: Vector3 = ui._hover["point"]
		var c2 := cam.unproject_position(hp)
		ring = c2 + Vector2(c2.distance_to(cam.unproject_position(hp + cam.global_transform.basis.x * ui.radius)), 0)
	var ring_px := Vector2i(ring.round())
	var px_with := img.get_pixelv(Vector2i(cs + Vector2(0, 40)))
	var ring_with := img.get_pixelv(ring_px)
	ui._ov.visible = false
	var img_no_ring := await shot()
	ui.view.visible = false
	var img_none := await shot()
	ui.view.visible = true
	ui._ov.visible = true
	var d_sph := dist(px_with, img_none.get_pixelv(Vector2i(cs + Vector2(0, 40))))
	var d_ring := maxf(dist(ring_with, img_no_ring.get_pixelv(ring_px)), maxf(dist(img.get_pixelv(ring_px + Vector2i(-1, 0)), img_no_ring.get_pixelv(ring_px + Vector2i(-1, 0))), dist(img.get_pixelv(ring_px + Vector2i(1, 0)), img_no_ring.get_pixelv(ring_px + Vector2i(1, 0)))))
	ok(ui.view.global_position.distance_to(KMeshSculptUI.AT) < 0.001 and absf(lo) < 0.001 and inside and d_sph > 0.1 and d_ring > 0.1,
		"(4) placement: at %s, lowest y %.4f m, outline inside %s, sphere pixel differs %.2f, ring pixel differs %.2f (shot /tmp/claude-0/sp/sculpt.png)" % [ui.view.global_position, lo, inside, d_sph, d_ring])
	m.ui_root.visible = true
	ui._ov.reparent(m.ui_root)
	# 5 Esc
	await key(KEY_ESCAPE)
	await idle(3)
	var gone := not ui.on and m.find_child("sculpt_view", true, false) == null
	m._sculpt_start()
	await idle(3)
	ok(gone and ui.on, "(5) Esc leaves (view gone %s), the command opens it again %s" % [gone, ui.on])
	print("SCULPT UI ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
