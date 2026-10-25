## godot --path . -s tests/cube_views_test.gd     (GATES CC2, UPGRADES #22; a real window, real clicks on the cube)
## VIEWCUBE 3/4 VIEWS: a point X on the cube's surface (cube space, each coordinate in [-1, 1]) is drawn at the cube's own
## projection; a REAL click there must end with the camera looking FROM the sum of the axes on which |X| passes the
## edge band (a face's middle = that face, near an edge = two faces, near a corner = three), within 2 deg. Every move
## (a side face's middle: its key view, 8 deg from above, as before) is sampled each frame: smooth (no frame turns more than 40 % of the move, the middle sample strictly between), done
## within 0.5 s; BACK -> the back/his-right edge goes the short way (never within 90 deg of FRONT). The house mark puts
## yaw, pitch, distance and target back to the start. Keys 1-5 stay instant.
extends SceneTree

var fails := 0
var m: Node
var cube: ViewCube


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click_local(p: Vector2) -> void:
	var g: Vector2 = cube.get_global_transform() * p
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = g
		e.global_position = g
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame


func look() -> Vector3:   # where the camera looks FROM (target + this * dist)
	return m.cam.global_basis.z.normalized()


func want(X: Vector3) -> Vector3:
	var d := Vector3.ZERO
	for k in 3:
		if absf(X[k]) > ViewCube.EDGE:
			d[k] = signf(X[k])
	d = d.normalized()
	if absf(d.y) < 1e-6 and (absf(d.x) > 0.99 or absf(d.z) > 0.99):   # a side face's middle: its key view, 8 deg from above
		d = Vector3(d.x * cos(deg_to_rad(8.0)), sin(deg_to_rad(8.0)), d.z * cos(deg_to_rad(8.0)))
	return d


## a real click at cube point X; follow the move frame by frame. -> [end dir, max step share, mid between, secs, path]
func go(X: Vector3) -> Array:
	var p3: Vector3 = cube._proj(X)
	var a := look()
	var t0 := Time.get_ticks_msec()
	await click_local(Vector2(p3.x, p3.y))
	var path := [a]
	var last := a
	var still := 0
	while Time.get_ticks_msec() - t0 < 1500 and still < 5:
		await process_frame
		var now := look()
		still = still + 1 if now.is_equal_approx(last) else 0
		if not now.is_equal_approx(last):
			path.append(now)
		last = now
	var secs := (Time.get_ticks_msec() - t0) / 1000.0 - 5.0 / 60.0
	var b := look()
	var total := rad_to_deg(a.angle_to(b))
	var step := 0.0
	for i in range(1, path.size()):
		step = maxf(step, rad_to_deg((path[i - 1] as Vector3).angle_to(path[i])))
	var mid: Vector3 = path[path.size() / 2]
	var between := rad_to_deg(a.angle_to(mid)) > 0.5 and rad_to_deg(mid.angle_to(b)) > 0.5
	return [b, step / maxf(total, 1e-6), between, secs, path, total]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	cube = m.ui_cube
	m._view_dir(Vector3(0.5, 0.4, 1.0), false)   # a little off the front, so the front face's middle is a move
	await idle(3)
	# from the front: the front face's middle, an edge, a corner; then from that corner's 3/4 view the top face's edge
	var cases := [["front face, middle", Vector3(0.1, -0.1, 1)], ["front face near its his-RIGHT edge", Vector3(-0.8, 0.0, 1)],
		["front face near the top-his-LEFT corner", Vector3(0.8, 0.8, 1)], ["(from that corner) the top face near its back edge", Vector3(0.1, 1, -0.8)],
		["(from there) the back face's middle", Vector3(0.05, 0.1, -1)]]
	for c in cases:
		var X: Vector3 = c[1]
		var r := await go(X)
		var err := rad_to_deg((r[0] as Vector3).angle_to(want(X)))
		ok(err < 2.0 and r[1] < 0.4 and r[2] and r[3] <= 0.5,
			"%s: looks from %s, wanted %s (off %.2f deg); smooth: %d frames, the largest step %.0f %% of the %.0f deg move, the middle between: %s, done in %.2f s" % [c[0], (r[0] as Vector3).snappedf(0.01), want(X).snappedf(0.01), err, r[4].size(), r[1] * 100.0, r[5], r[2], r[3]])
	# the short way round: from BACK (key 4: instant) to the back/his-right edge
	m._view(4)
	await process_frame
	ok(look().angle_to(Vector3(0, 0, -1)) < deg_to_rad(9.0), "key 4 is instant: the next frame looks from the back (%s)" % look().snappedf(0.01))
	var r2 := await go(Vector3(-0.8, 0.0, -1))
	var closest := 180.0
	for v in r2[4]:
		closest = minf(closest, rad_to_deg((v as Vector3).angle_to(Vector3(0, 0, 1))))
	ok(rad_to_deg((r2[0] as Vector3).angle_to(want(Vector3(-0.8, 0, -1)))) < 2.0 and closest > 90.0,
		"BACK -> back/his-right edge: the short way (%.0f deg move; never nearer the front than %.0f deg)" % [r2[5], closest])
	# home: the view turned, zoomed, panned; the house clicked
	m.dist = 2.0
	m.target = Vector3(0.4, 1.3, 0.2)
	m._cam()
	await idle(2)
	await click_local(ViewCube.HOME_R.get_center())
	for k in 40:
		await process_frame
	ok(is_equal_approx(wrapf(m.yaw, -180, 180), m.HOME["yaw"]) and is_equal_approx(m.pitch, m.HOME["pitch"]) and is_equal_approx(m.dist, m.HOME["dist"]) and m.target.is_equal_approx(m.HOME["target"]),
		"the house mark: back to the start view (yaw %.1f pitch %.1f dist %.2f target %s)" % [m.yaw, m.pitch, m.dist, m.target])
	print("CUBE VIEWS: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
