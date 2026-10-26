## godot --path . -s tests/camera_gizmo_test.gd   (needs a window)
## THE SHOT CAMERA's gizmo in the 3D view (scripts/shot_gizmo.gd) and its keys on the timeline (timeline.gd cam_times).
## A 2-card scene with 3 camera keys (0 s, mid, the end). Nothing is written outside the process.
##   1 the gizmo sits at shot_at(playhead).pos within 1 mm at 3 times (a key, between two keys, the end)
##   2 hidden while looking through and in a clean render; shown again in the free view
##   3 one timeline diamond per camera key, at its time; a click on it puts the playhead there
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pose(thigh: float, arm: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.set_ang("upperarm_r", Vector3(0, 0, arm))
	R.fk()
	return R.to_dict()


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_camera_gizmo"
	S.fps = 24
	S.add("c0", pose(0, 0))
	S.add("c1", pose(70, 80))
	for i in 2:
		S.cards[i]["move"] = 0.4
		S.cards[i]["hold"] = 0.1 if i == 0 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	await idle(3)
	var L := S.length()
	S.shots = [{"t": 0.0, "name": "Shot 1", "keys": []}]   # one shot: its camera is the three keys below
	ShotCam.put(S.shots[0]["keys"], {"t": 0.0, "pos": Vector3(2.8, 1.3, -1.2), "aim": Vector3(0, 1.0, 0), "f": 50.0})
	ShotCam.put(S.shots[0]["keys"], {"t": 0.2, "pos": Vector3(3.0, 1.1, 0.6), "aim": Vector3(0.1, 0.9, 0.05), "f": 35.0})
	ShotCam.put(S.shots[0]["keys"], {"t": L, "pos": Vector3(-2.6, 1.6, -1.5), "aim": Vector3(0, 1.2, -0.1), "f": 85.0})
	m._refresh()
	await idle(3)

	var g = m.get_node_or_null("shot_gizmo")
	ok(g != null, "the gizmo is attached under the main node")
	if g == null:
		print("CAMERA GIZMO TEST FAIL (no gizmo)")
		TestFiles.cleanup()
		quit(1)
		return

	# 1 at the playhead
	for t in [0.0, 0.35, L]:
		m.playhead = t
		m._refresh()
		await idle(1)
		var want: Vector3 = m.shot_at(t)["pos"]
		ok(g.visible and g.global_position.distance_to(want) < 0.001,
			"  at %.2f s the gizmo is at the shot camera (%.4f mm off, visible %s)" % [t, g.global_position.distance_to(want) * 1000.0, g.visible])

	# 2 hidden while looking through and in a clean render
	m.playhead = 0.35
	m._refresh()
	m._shot_toggle()
	await idle(2)
	ok(m.shot_through and not g.visible, "2 looking through: the gizmo is hidden")
	m._shot_toggle()
	await idle(2)
	ok(not m.shot_through and g.visible, "  back to the free view: the gizmo is shown")
	m.clean = true
	await idle(2)
	ok(not g.visible, "  a clean render: the gizmo is hidden")
	m.clean = false
	await idle(2)
	ok(g.visible, "  the free view again: shown")

	# 3 timeline diamonds
	var tl: Timeline = m.ui_timeline
	ok(tl.cam_times().size() == S.shots[0]["keys"].size(), "3 one timeline diamond per camera key: %d of %d" % [tl.cam_times().size(), S.shots[0]["keys"].size()])
	for k in S.shots[0]["keys"]:
		var t := float(k["t"])
		var at := Vector2(tl.x_of(t), tl._cam_y())
		ok(absf(tl.cam_key_at(at) - t) < 1e-6, "  the diamond at %.2f s is clickable" % t)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = at
		m.playhead = L * 0.5
		tl._gui_input(ev)
		ok(absf(m.playhead - t) < 1e-6, "  a click on it puts the playhead at %.2f s (now %.2f)" % [t, m.playhead])

	print("CAMERA GIZMO TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
