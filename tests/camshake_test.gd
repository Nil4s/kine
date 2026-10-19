## godot --path . -s tests/camshake_test.gd   (needs a window: look-through and its depth of field are drawn)
## ROADMAP 76: CAMERA SHAKE and RACK FOCUS on the shot camera (scripts/shot_fx.gd; main.gd shot_view_at, _shot_dof_set).
## A 2-card scene with 3 camera keys (as camera_gizmo_test). Nothing is written outside the process, except the
## screenshot when POSER_CAMSHAKE_PNG names a file.
##   1 the shake is deterministic: two evaluations at 50 times are identical
##   2 outside every shake the camera is byte-identical to no shake (shot_view_at's xf = ShotCam.xf(pos, aim)); inside, it is not
##   3 each channel's peak is its set amplitude within 5 %: 2 cm, 3 cm (position), 1 deg (pitch), sampled at 1/240 s
##   4 each channel is below 10 % of its peak by the end of the event (at 0.99 of its duration)
##   5 a focus-on-part key: the focus is the camera-to-part distance within 1 cm at 3 times (the key, between, the end)
##   6 each command is one undo step: the shake, the focus key; undo takes it back
##   7 look-through with focus keys puts a depth of field on the camera, sharp at the focus; the free view has none
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
	S.name = "zz_camshake"
	S.fps = 24
	S.shots = [{"t": 0.0, "name": "Shot 1", "keys": [], "fx": {}}]   # one shot: the camera, its shake and focus (ROADMAP 75 + 76)
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
	ShotCam.put(S.shots[0]["keys"], {"t": 0.0, "pos": Vector3(2.8, 1.3, -1.2), "aim": Vector3(0, 1.0, 0), "f": 50.0})
	ShotCam.put(S.shots[0]["keys"], {"t": 0.2, "pos": Vector3(3.0, 1.1, 0.6), "aim": Vector3(0.1, 0.9, 0.05), "f": 35.0})
	ShotCam.put(S.shots[0]["keys"], {"t": L, "pos": Vector3(-2.6, 1.6, -1.5), "aim": Vector3(0, 1.2, -0.1), "f": 85.0})
	m._refresh()
	await idle(3)

	# 1 and 3, 4: the shake itself (no scene needed beyond the events)
	var ev := ShotFx.impact(0.5, 1)
	ev["cm"] = Vector3(2.0, 3.0, 1.0)
	ev["deg"] = Vector3(1.0, 0.6, 1.5)
	var evs := [ev]
	var same := true
	for i in 50:
		var t := 0.4 + i * 0.01
		if var_to_str(ShotFx.shake_at(evs, t)) != var_to_str(ShotFx.shake_at(evs, t)):
			same = false
	ok(same, "1 the shake is deterministic: two evaluations at 50 times are identical")
	var dt := 1.0 / 240.0
	var peak := [0.0, 0.0, 0.0, 0.0]   # pos.x, pos.y, pos.z (m), rot.x (rad)
	var s := 0.0
	while s < float(ev["dur"]):
		var off := ShotFx.shake_at(evs, 0.5 + s)
		peak[0] = maxf(peak[0], absf(off["pos"].x))
		peak[1] = maxf(peak[1], absf(off["pos"].y))
		peak[2] = maxf(peak[2], absf(off["pos"].z))
		peak[3] = maxf(peak[3], absf(off["rot"].x))
		s += dt
	var want := [0.02, 0.03, 0.01, deg_to_rad(1.0)]
	var names := ["pos x", "pos y", "pos z", "rot pitch"]
	for c in 4:
		var rel: float = absf(peak[c] - want[c]) / want[c]
		ok(rel < 0.05, "3 %s peak %.5f against its set %.5f (%.2f %% off)" % [names[c], peak[c], want[c], rel * 100.0])
	var end: Dictionary = ShotFx.shake_at(evs, 0.5 + 0.99 * float(ev["dur"]))
	var endr: float = absf(end["pos"].y) / 0.03
	ok(endr < 0.10, "4 the shake decays: at 0.99 of its duration pos y is %.2f %% of its peak (under 10 %%)" % (endr * 100.0))
	ok(ShotFx.shake_at(evs, 0.4).is_empty() and ShotFx.shake_at(evs, 1.2).is_empty(), "  and it is absent before its start and after its end")

	# 2: the shot camera's view outside every shake is the keyed camera, byte for byte; inside it is shaken
	S.shots[0]["fx"] = {"shake": evs, "focus": []}
	var outside_ok := true
	var inside_differs := false
	for t in [0.0, 0.3, 0.45, 1.2, L + 2.0]:   # the scene ends at L (0.5 s), the shake starts there: its own start is not outside
		var k: Dictionary = m.shot_at(t)
		var v: Dictionary = m.shot_view_at(t)
		if var_to_str(v["xf"]) != var_to_str(ShotCam.xf(k["pos"], k["aim"])):
			outside_ok = false
	for t in [0.6, 0.7]:
		var k2: Dictionary = m.shot_at(t)
		if var_to_str(m.shot_view_at(t)["xf"]) != var_to_str(ShotCam.xf(k2["pos"], k2["aim"])):
			inside_differs = true
	ok(outside_ok, "2 outside every shake the shot view is byte-identical to the keyed camera (0 s, 0.3, 0.45, 1.2, 2.5 s)")
	ok(inside_differs, "  inside the shake (0.6 s, 0.7 s) the view moves")
	S.shots[0]["fx"] = {}

	# 5: a focus-on-part key tracks the part: the focus is the camera-to-part distance within 1 cm at 3 times
	m.sel = "upperarm_r"
	S.shots[0]["fx"] = {"shake": [], "focus": [{"t": 0.0, "part": "upperarm_r"}]}
	var worst := 0.0
	for t in [0.0, 0.35, L]:
		var keyed: Vector3 = ShotCam.sample(S.shots[0]["keys"], t)["pos"]
		var part: Vector3 = ShotFx.part_at(S, "upperarm_r", t)
		var truth := keyed.distance_to(part)
		var got: float = m.shot_view_at(t)["focus"]
		worst = maxf(worst, absf(got - truth))
		ok(absf(got - truth) < 0.01, "5 at %.2f s the focus %.4f m, the camera-to-part distance %.4f m (%.2f mm off)" % [t, got, truth, absf(got - truth) * 1000.0])
	print("  worst focus error %.2f mm" % (worst * 1000.0))

	# 6: one undo step per command
	S.shots[0]["fx"] = {}
	m.playhead = 0.2
	m._refresh()
	var n0: int = m.undo.size()
	m._shot_shake_here()
	var n1: int = m.undo.size()
	ok(n1 == n0 + 1 and (S.shots[0]["fx"].get("shake", []) as Array).size() == 1, "6 the impact shake is one undo step (%d -> %d steps, %d shake)" % [n0, n1, (S.shots[0]["fx"].get("shake", []) as Array).size()])
	m._undo()
	ok((S.shots[0]["fx"].get("shake", []) as Array).is_empty(), "  undo takes the shake back")
	m.playhead = 0.35
	m._refresh()
	n0 = m.undo.size()
	m._shot_focus_part()
	n1 = m.undo.size()
	ok(n1 == n0 + 1 and (S.shots[0]["fx"].get("focus", []) as Array).size() == 1, "6 the focus-on-part key is one undo step (%d -> %d steps)" % [n0, n1])
	m._undo()
	ok((S.shots[0]["fx"].get("focus", []) as Array).is_empty(), "  undo takes the focus key back")

	# 7: look-through puts the depth of field on the camera at the focus distance; the free view has none
	S.shots[0]["fx"] = {"shake": [], "focus": [{"t": 0.0, "dist": 2.0}, {"t": L, "part": "upperarm_r"}]}
	m.playhead = 0.1
	m._refresh()
	m._shot_toggle()
	await idle(3)
	var at = m.cam.attributes
	var d_want: float = m.shot_view_at(0.1)["focus"]
	ok(m.shot_through and at is CameraAttributesPractical, "7 looking through: the camera carries a depth of field")
	if at is CameraAttributesPractical:
		ok(absf(float(at.dof_blur_far_distance) - d_want) < 0.001 and absf(float(at.dof_blur_near_distance) - d_want) < 0.001,
			"  its sharp distance is the focus (%.3f m)" % d_want)
	var png := OS.get_environment("POSER_CAMSHAKE_PNG")
	if png != "":
		m.playhead = 0.1
		m._refresh()
		await idle(4)
		get_root().get_texture().get_image().save_png(png)
		print("  screenshot %s" % png)
	m._shot_toggle()
	await idle(2)
	ok(not m.shot_through and m.cam.attributes == null, "  the free view has no depth of field")

	if fails == 0:
		print("CAMSHAKE TEST PASS")
	else:
		print("CAMSHAKE TEST FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
