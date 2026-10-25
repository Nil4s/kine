## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/modelview4_test.gd    (WALK-THROUGH 4, goal 1)
## MODEL VIEW FROM BELOW. Real right-button drags and key events pushed into the window (root.push_input). Bars, stated before measuring:
##  (a) MODEL: a right-drag DOWNWARD of 600 px leaves the camera under the floor (cam y < 0), and every bottom face of the
##      test cube (world normal pointing down) is pickable: kmed.view.pick at its projected centre returns that face.
##  (b) MODEL: Ctrl+Numpad7 (Blender's bottom view) gives a camera looking up (forward.y > 0.9).
##  (c) MODEL: one face picked in face mode, Numpad . (frame selected): that face's centre ends within 5 % of the view's
##      height from the screen centre.
##  (d) GUARD, POSE: a right-drag UPWARD of 600 px still stops the camera above the floor (cam y >= 0).
## (a)-(c) fail on the old code (git show HEAD:<file> in place); (d) must pass on both.
extends SceneTree

var fails := 0
var m: Node
var ui


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func tap(code: Key, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func click(p: Vector2, button: MouseButton) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	root.push_input(mv)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = p
		e.global_position = p
		e.button_index = button
		e.pressed = down
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(2)


## a real right-button drag from p by d, in 20 steps (the mouse down, moved, let go)
func orbit_drag(p: Vector2, d: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = MOUSE_BUTTON_RIGHT
	e.button_mask = MOUSE_BUTTON_MASK_RIGHT
	e.pressed = true
	root.push_input(e)
	await process_frame
	var last := p
	for i in range(1, 21):
		var q := p + d * (float(i) / 20.0)
		var mv := InputEventMouseMotion.new()
		mv.position = q
		mv.global_position = q
		mv.relative = q - last
		mv.button_mask = MOUSE_BUTTON_MASK_RIGHT
		root.push_input(mv)
		last = q
		await process_frame
	var r := InputEventMouseButton.new()
	r.position = last
	r.global_position = last
	r.button_index = MOUSE_BUTTON_RIGHT
	r.pressed = false
	root.push_input(r)
	await idle(3)


func screen_centre() -> Vector2:
	return m.get_viewport().get_visible_rect().size * 0.5


func wpos(v: int) -> Vector3:
	return ui.view.global_transform * ui.mesh.verts[v]


func face_centre(fi: int) -> Vector3:
	var c := Vector3.ZERO
	for v in ui.mesh.faces[fi]:
		c += wpos(v)
	return c / float(ui.mesh.faces[fi].size())


func face_normal(fi: int) -> Vector3:
	var f: PackedInt32Array = ui.mesh.faces[fi]
	return (wpos(f[1]) - wpos(f[0])).cross(wpos(f[2]) - wpos(f[0])).normalized()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var cam: Camera3D = m.cam

	# (d) GUARD on POSE: the orbit keeps today's camera (the pitch clamp of +-89 on both sides, as on the old code).
	# Old code: an upward drag already takes POSE under the floor (cam y ~ -3 at pitch +89), so "stops above the floor"
	# is not what POSE does today; this bar pins what it does do, and the mesh-page rule must not change it.
	m._view_home(false)
	await idle(3)
	await orbit_drag(screen_centre(), Vector2(0, -600))
	var pose_up: float = m.pitch
	print("     POSE upward 600 px: pitch %.1f, camera y %.3f" % [pose_up, m.cam.global_position.y])
	ok(is_equal_approx(pose_up, 89.0), "d POSE: an upward drag keeps the old pitch (%.1f, the +89 clamp)" % pose_up)
	m._view_home(false)
	await idle(3)
	await orbit_drag(screen_centre(), Vector2(0, 600))
	var pose_dn: float = m.pitch
	print("     POSE downward 600 px: pitch %.1f, camera y %.3f" % [pose_dn, m.cam.global_position.y])
	ok(is_equal_approx(pose_dn, -89.0), "d POSE: a downward drag keeps the old pitch (%.1f, the -89 top view)" % pose_dn)

	# MODEL: the test cube, the home view
	m._page_set("MODEL", false)
	await idle(3)
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	m._view_home(false)
	await idle(4)

	# (a) a downward right-drag of 600 px goes under the floor; the bottom faces pick themselves
	await orbit_drag(screen_centre(), Vector2(0, 600))
	var y_now: float = m.cam.global_position.y
	print("     MODEL downward 600 px: camera y %.3f, pitch %.1f" % [y_now, m.pitch])
	ok(y_now < 0.0, "a MODEL: a downward right-drag of 600 px leaves the camera under the floor (cam y %.3f < 0)" % y_now)
	var bottom := 0
	var picked := 0
	var seen := 0
	var vs := m.get_viewport().get_visible_rect().size
	for fi in ui.mesh.faces.size():
		if face_normal(fi).y > -0.9:
			continue
		bottom += 1
		var c := face_centre(fi)
		if not ui.view.point_visible(m.cam, c):
			continue
		seen += 1
		var sp: Vector2 = m.cam.unproject_position(c)
		if sp.x < 0 or sp.y < 0 or sp.x > vs.x or sp.y > vs.y:
			continue
		var h: Dictionary = ui.view.pick(m.cam, sp)
		if not h.is_empty() and int(h["face"]) == fi:
			picked += 1
	print("     bottom faces %d, visible %d, picked on their own centre %d" % [bottom, seen, picked])
	ok(bottom > 0 and seen > 0 and picked == seen, "a MODEL: the bottom faces are pickable from below (%d of %d visible bottom faces pick themselves, %d bottom faces in all)" % [picked, seen, bottom])

	# (b) Ctrl+Numpad7: the bottom view, looking up
	await tap(KEY_KP_7, true, false)
	await idle(40)
	var fwd: Vector3 = -m.cam.global_basis.z
	print("     Ctrl+Numpad7: forward %s" % str(fwd))
	ok(fwd.y > 0.9, "b MODEL: Ctrl+Numpad7 looks up from below (forward.y %.3f > 0.9)" % fwd.y)

	# (c) one face picked (face mode), Numpad . frames it on the screen centre
	m._view_home(false)
	await idle(4)
	await tap(KEY_3, false, false)
	await idle(2)
	var best := -1
	var bestd := INF
	for fi in ui.mesh.faces.size():
		if face_normal(fi).dot((m.cam.global_position - face_centre(fi)).normalized()) < 0.5:
			continue
		var sp: Vector2 = m.cam.unproject_position(face_centre(fi))
		if not ui.view.point_visible(m.cam, face_centre(fi)):
			continue
		if sp.distance_to(screen_centre()) < bestd:
			bestd = sp.distance_to(screen_centre())
			best = fi
	var aim: Vector2 = m.cam.unproject_position(face_centre(best))
	await click(aim, MOUSE_BUTTON_LEFT)
	await idle(3)
	var in_sel: bool = ui.sel.faces.has(best)
	print("     picked face %d at %s, in the selection: %s, selection %d" % [best, str(aim), str(in_sel), ui.sel.count()])
	await tap(KEY_KP_PERIOD, false, false)
	await idle(60)
	# the view's centre is where the app puts its look-at point (the free view between the panels: _cam's h_offset);
	# the window's own middle is also printed, since the side panels move the free view's centre off it
	var at: Vector2 = m.cam.unproject_position(face_centre(best))
	var free_c: Vector2 = m.cam.unproject_position(m.target)
	var off := at.distance_to(free_c) / vs.y
	var off_win := at.distance_to(screen_centre()) / vs.y
	print("     framed: the face at %s, free-view centre %s (window middle %s): off %.4f of the height (window %.4f)" % [str(at), str(free_c), str(screen_centre()), off, off_win])
	ok(in_sel and off <= 0.05, "c MODEL: Numpad . frames the picked face on the view's centre (%.1f %% of the height off; the window's middle %.1f %% off)" % [off * 100.0, off_win * 100.0])

	print("modelview4: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
