## godot --path . -s tests/view_cube_test.gd     (GATES N2; needs a window)
## The ViewCube against the REAL camera, not against its own math: at 40 random orientations each face the cube shows
## must point, on the cube, the way the 3D camera projects that side of the body (target + side) on the screen; the
## faces it hides must be the ones facing away. Then a click on each face (as a mouse event) gives that view, a click
## off the cube does nothing, and in big view the cube moves to the screen's corner.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func click(cube: ViewCube, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	cube._gui_input(e)


func centre(cube: ViewCube, i: int) -> Vector2:
	var q := cube._quad(i)
	return (q[0] + q[1] + q[2] + q[3]) * 0.25


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var cube: ViewCube = m.ui_cube
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var worst_flip := 0.0   # CONTROL: the same comparison against a cube flipped left-right must fail
	var worst_off := 0.0   # the same, as the user's shifted lens shows it (perspective off the axis: reported, not barred)
	var wrong_vis := 0
	var faces_seen := 0
	for k in 40:
		m.yaw = rng.randf_range(-180.0, 180.0)
		m.pitch = rng.randf_range(-85.0, 85.0)
		m._cam()
		await process_frame
		var vis: Array = cube._visible()
		# the lens's own centre: no h/v offset, the target on the axis, a 1 cm step -> perspective adds nothing there
		var ho: float = m.cam.h_offset
		var vo: float = m.cam.v_offset
		m.cam.h_offset = 0.0
		m.cam.v_offset = 0.0
		var o: Vector2 = m.cam.unproject_position(m.target)
		var dirs := {}
		for i in ViewCube.FACES.size():
			dirs[i] = m.cam.unproject_position(m.target + ViewCube.FACES[i][0] * 0.01) - o
		m.cam.h_offset = ho
		m.cam.v_offset = vo
		var o2: Vector2 = m.cam.unproject_position(m.target)
		for i in ViewCube.FACES.size():
			var n: Vector3 = ViewCube.FACES[i][0]
			var toward: bool = (m.cam.global_position - m.target).dot(n) > 0.0   # that side of the body faces the camera
			if toward != (i in vis) and absf((m.cam.global_position - m.target).normalized().dot(n)) > 0.06:
				wrong_vis += 1
			if not i in vis:
				continue
			var on_screen: Vector2 = dirs[i]
			var on_cube := centre(cube, i) - Vector2(ViewCube.SIZE, ViewCube.SIZE) * 0.5
			if on_screen.length() > 0.15 and on_cube.length() > 4.0:   # a face seen dead-on has no direction to compare
				worst = maxf(worst, rad_to_deg(absf(on_screen.angle_to(on_cube))))
				worst_flip = maxf(worst_flip, rad_to_deg(absf(on_screen.angle_to(Vector2(-on_cube.x, on_cube.y)))))
				worst_off = maxf(worst_off, rad_to_deg(absf((m.cam.unproject_position(m.target + n * 0.3) - o2).angle_to(on_cube))))
				faces_seen += 1
	print("     40 orientations, %d visible faces with a direction: worst angle between the cube's face and the camera's projection of that side %.2f deg at the lens centre; %.1f deg as the shifted lens draws a 30 cm arm (perspective, off-axis)" % [faces_seen, worst, worst_off])
	ok(worst < 2.0 and faces_seen > 60, "every face shown points where the camera shows that side (worst %.2f deg; bar 2)" % worst)
	ok(worst_flip > 30.0, "  control: a cube flipped left-right misses by %.0f deg, so the check can fail" % worst_flip)
	ok(wrong_vis == 0, "the faces shown are exactly the sides facing the camera (%d wrong)" % wrong_vis)

	# a click on each face
	var want := {1: [0.0, -8.0], 2: [-90.0, -8.0], 3: [0.0, -89.0], 4: [180.0, -8.0], 5: [90.0, -8.0], 6: [0.0, 89.0]}
	for i in ViewCube.FACES.size():
		var n: Vector3 = ViewCube.FACES[i][0]
		# look from between this side and the front-ish so the face is clearly on show, then click its middle
		m.yaw = 25.0 if n.z >= 0.0 else 205.0
		m.yaw += -60.0 if n.x < 0.0 else (60.0 if n.x > 0.0 else 0.0)
		m.pitch = -30.0 if n.y >= 0.0 else 40.0
		m._cam()
		await process_frame
		var v: int = ViewCube.FACES[i][2]
		var p := centre(cube, i)
		ok(cube.face_at(p) == i, "  %s: its middle is on it (yaw %.0f pitch %.0f)" % [ViewCube.FACES[i][1], m.yaw, m.pitch])
		click(cube, p)
		ok(is_equal_approx(m.yaw, want[v][0]) and is_equal_approx(m.pitch, want[v][1]), "  click %s -> yaw %.0f pitch %.0f" % [ViewCube.FACES[i][1], m.yaw, m.pitch])
	var y0: float = m.yaw
	click(cube, Vector2(3, 3))
	ok(m.yaw == y0, "a click in the cube's corner, off the cube: nothing")
	var r0 := cube.get_global_rect()
	m._big_view()
	await process_frame
	var r1 := cube.get_global_rect()
	var w: float = m.get_viewport().get_visible_rect().size.x
	ok(r0.end.x <= w - m.RIGHT_W and absf(r1.end.x - (w - 10.0)) < 1.0, "beside the right panel (right edge %.0f), in big view in the corner (%.0f of %.0f)" % [r0.end.x, r1.end.x, w])
	m._big_view()
	print("VIEW CUBE %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
