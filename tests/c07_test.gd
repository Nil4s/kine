## godot --path . -s tests/c07_test.gd     (C07: complaints #709 camera orbit about its own position, #686 a visible pivot, #465 rotate about a joint, no flips; needs a window)
## BARS (written before the first run):
##  O1 own-axis: a shot camera keyed and looked through; one REAL right-drag of (120, 40) px on empty view. With "own_cam" on the camera's world
##     position moves < 1 mm and its forward turns >= 20 deg. CONTROL (option off, the old behaviour): the camera moves > 0.3 m. With the option on but NOT
##     looking through a camera, the free orbit is unchanged: target identical to the option-off run (< 1e-4). The option is saved in the settings file.
##  P1 pivot ball: "show_pivot" off: no ball visible mid-drag (CONTROL). On, pivot "target": mid-drag the ball is at m.target (< 1 mm); pivot "selection":
##     at the selection's box centre (< 1 mm), which is > 5 cm from the target (so a ball at the wrong place fails); pivot "cursor": at the point under the
##     press (< 1 mm). 1.0 s after the release the ball is hidden. The ball sits inside the 3D view (its screen position is clear of the left/right panels).
##  J1 joint dot: "joint_dot" off: no dot (CONTROL). On: the dot is visible at B.P[sel] (< 1 mm) and its screen position is in the 3D view.
##  A1 axis keep: with the limits opened, a part turned 2 deg a step about a fixed world axis for 400 deg. With axis_keep the biggest one-step jump of
##     (bend, side) is <= 6 deg; CONTROL: without it the jump is >= 100 deg (the flip of the second spelling), so the bar can fail.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func btn(p: Vector2, idx: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = 1 << (idx - 1)
	Input.parse_input_event(e)


func mot(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(e)


## a right-drag in 4 steps; mid() runs after the last move, before the release
func drag(from: Vector2, total: Vector2, mid: Callable = Callable()) -> void:
	btn(from, MOUSE_BUTTON_RIGHT, true)
	await frames(2)
	var p := from
	for i in 4:
		p += total / 4.0
		mot(p, total / 4.0)
		await frames(2)
	if mid.is_valid():
		await mid.call()
	btn(p, MOUSE_BUTTON_RIGHT, false)
	await frames(2)


func in_view(m: Node, wp: Vector3) -> bool:
	var s: Vector2 = m.cam.unproject_position(wp)
	return s.x > m.lw() + 4 and s.x < m.get_viewport().get_visible_rect().size.x - m.rw() - 4 and s.y > 40 and s.y < m.get_viewport().get_visible_rect().size.y - 40


func shot(m: Node, nm: String) -> void:
	DirAccess.make_dir_recursive_absolute("C:/Users/Nick/tools/kine_workers/out/c07")
	m.get_viewport().get_texture().get_image().save_png("C:/Users/Nick/tools/kine_workers/out/c07/%s.png" % nm)


func shot_later(m: Node, nm: String) -> void:
	await frames(2)
	shot(m, nm)


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await frames(4)
	var cp: CamPivot = m.campiv
	ok(cp != null and not cp.own_cam and not cp.show_pivot and not cp.joint_dot, "all three are off by default")
	if cp == null:
		print("c07: %d fail" % fails)
		quit(1)
		return
	var start := Vector2(0.62 * 1280.0, 150.0)
	# ---- O1: free orbit with the option on equals the option off
	m._view(1, false)
	m.target = Vector3(0, 0.95, 0)
	m._cam()
	var y0: float = m.yaw
	var p0: float = m.pitch
	cp.own_cam = false
	await drag(start, Vector2(120, 40))
	var t_off: Vector3 = m.target
	m.yaw = y0
	m.pitch = p0
	m.target = Vector3(0, 0.95, 0)
	m._cam()
	cp.own_cam = true
	await drag(start, Vector2(120, 40))
	ok(m.target.distance_to(t_off) < 1e-4, "O1 free orbit with own_cam on is unchanged (%.6f)" % m.target.distance_to(t_off))
	# ---- O1: the shot camera
	m._view(1, false)
	m.target = Vector3(0, 0.95, 0)
	m._cam()
	m._card_add()
	await frames(2)
	m._shot_key_view()
	await frames(2)
	var runs := {}
	for on in [true, false]:
		cp.own_cam = on
		m.shot_through = false
		m._shot_toggle()
		await frames(3)
		ok(m.shot_through, "O1 looking through the shot camera (own_cam %s)" % on)
		var p_a: Vector3 = m.cam.global_position
		var f_a: Vector3 = -m.cam.global_basis.z
		await drag(start, Vector2(120, 40))
		var p_b: Vector3 = m.cam.global_position
		var f_b: Vector3 = -m.cam.global_basis.z
		runs[on] = {"move": p_a.distance_to(p_b), "turn": rad_to_deg(f_a.angle_to(f_b))}
		print("c07 O1 own_cam=%s moved %.4f m turned %.1f deg" % [on, runs[on]["move"], runs[on]["turn"]])
		if m.shot_through:
			m._shot_toggle()
	ok(runs[true]["move"] < 0.001 and runs[true]["turn"] >= 20.0, "O1 own axis: camera stays put (%.5f m) and turns (%.1f deg)" % [runs[true]["move"], runs[true]["turn"]])
	ok(runs[false]["move"] > 0.3, "O1 control: the old orbit moves the camera (%.3f m)" % runs[false]["move"])
	cp.own_cam = true
	cp.show_pivot = true
	cp.joint_dot = true
	cp.save_to(m.settings)
	var cp2 := CamPivot.new(m)
	ok(cp2.own_cam and cp2.show_pivot and cp2.joint_dot, "O1 the three choices are saved in the settings file")
	cp.own_cam = false
	cp.show_pivot = false
	cp.joint_dot = false
	# ---- P1: pivot ball
	m.shot_through = false
	m._view(1, false)
	m.target = Vector3(0, 0.95, 0)
	m._cam()
	m.sel = "hand_r"
	await frames(2)
	var cn: CamNav = m.camnav
	cn.pivot = "cursor"   # any non-default makes the nav code run the press
	var seen := {}
	var chk := func(label: String, want: Variant) -> void:
		var ball: MeshInstance3D = cp.pv_node
		seen[label] = ball != null and ball.visible
		if want != null and ball != null and ball.visible:
			seen[label + "_d"] = ball.global_position.distance_to(want as Vector3)
	# control: off
	await drag(start, Vector2(60, 0), func(): await chk.call("off", null))
	ok(not seen["off"], "P1 control: show_pivot off, no ball mid-drag")
	cp.show_pivot = true
	for opt in ["target", "selection", "cursor"]:
		cn.pivot = opt
		m.target = Vector3(0, 0.95, 0)
		m._cam()
		var want: Vector3
		if opt == "target":
			want = m.target
		elif opt == "selection":
			want = (m.vx.sel_aabb() as AABB).get_center()
		else:
			want = cn.point_under(start)
		await drag(start, Vector2(60, 0), func(): await chk.call(opt, cp.pivot_point()))
		ok(seen[opt] and seen[opt + "_d"] < 0.001, "P1 pivot '%s': ball mid-drag at the pivot (%.5f m)" % [opt, seen.get(opt + "_d", -1.0)])
		if opt == "selection":
			ok(want.distance_to(Vector3(0, 0.95, 0)) > 0.05, "P1 control: the selection's centre is > 5 cm from the view centre (%.3f)" % want.distance_to(Vector3(0, 0.95, 0)))
			if cp.pv_node != null:
				ok(in_view(m, cp.pv_node.global_position), "P1 the selection ball is inside the 3D view")
		await shot_later(m, "pivot_" + opt)
	cn.pivot = "target"
	await create_timer(1.0).timeout
	await frames(2)
	ok(not cp.pv_node.visible, "P1 1.0 s after the release the ball is hidden")
	# ---- J1: joint dot
	cp.show_pivot = false
	m.sel = "upperarm_r"
	await frames(3)
	ok(cp.jd_node == null or not cp.jd_node.visible, "J1 control: joint_dot off, no dot")
	cp.joint_dot = true
	await frames(3)
	ok(cp.jd_node != null and cp.jd_node.visible and cp.jd_node.global_position.distance_to(m.B.P["upperarm_r"]) < 0.001, "J1 the dot is on the joint")
	ok(in_view(m, m.B.P["upperarm_r"]), "J1 the dot is inside the 3D view")
	await shot_later(m, "joint_dot")
	# ---- A1: axis keep
	var jmax := {}
	for keep in [true, false]:
		cp.joint_dot = keep
		await frames(2)
		var B = m.B
		var j := "upperarm_r"
		var saved_lim = B.lim[j].duplicate(true)
		var saved_ang: Vector3 = B.ang[j]
		B.lim[j]["bend"] = Vector2(-720, 720)
		B.lim[j]["side"] = Vector2(-720, 720)
		var was_cc: int = B.coupled_clamp
		B.coupled_clamp = 0
		B.fast = true
		B.axis_keep = keep
		B.set_ang(j, Vector3.ZERO)
		var worst := 0.0
		var ax := Vector3(0.3, 0.2, -1.0).normalized()
		for i in 200:
			var o: Vector3 = B.ang[j]
			B.turn_world(j, Quaternion(ax, deg_to_rad(2.0)))
			var a: Vector3 = B.ang[j]
			worst = maxf(worst, Vector2(a.x - o.x, a.y - o.y).length())
		jmax[keep] = worst
		B.fast = false
		B.coupled_clamp = was_cc
		B.lim[j] = saved_lim
		B.set_ang(j, saved_ang)
	print("c07 A1 biggest one-step jump: keep %.2f deg, plain %.2f deg" % [jmax[true], jmax[false]])
	ok(jmax[true] <= 6.0, "A1 axis keep: biggest one-step jump %.2f deg <= 6" % jmax[true])
	ok(jmax[false] >= 100.0, "A1 control: without it the readout flips (%.2f deg >= 100)" % jmax[false])
	print("c07: %d fail" % fails)
	quit(1 if fails > 0 else 0)
