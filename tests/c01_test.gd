## godot --path . -s tests/c01_test.gd     (C01: complaints #713 view history, #184 invert orbit / pan, #689 the cube's Top; needs a window)
## BARS (written before the first run):
##  H1 history: 4 held views -> back twice lands on view 2 within 0.5 deg / 2 cm; forward once lands on view 3; 30 notes keep exactly 20;
##     Alt+Left as a real key event steps back; stepping back is not recorded as a new view. CONTROL: view 2 differs from view 3 by > 20 deg,
##     so landing on the wrong one fails the bar; a fresh history cannot go back.
##  I1 invert: one orbit drag of (10, 0) px turns yaw by -4.0 deg by default and +4.0 inverted; a pan drag moves the target the opposite way
##     (dot product < 0); the choice is saved: a new CamExtras read from the settings file has it. CONTROL: default yaw delta is -4.0 (not +4).
##  T1 top: after "Make this face Top" on the FRONT face, that face reads TOP and the old TOP face reads BACK; a middle click on it looks from
##     +Z at pitch 0 (default click gives pitch -8, CONTROL); the scene dict carries cube_top ~ (0,0,1); reading it back gives the same labels;
##     a dict without the key gives the default labels; a right-click on a face opens a menu "Make this face Top" / "Reset Top".
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func settle(m: Node) -> void:
	while m._view_tw != null and m._view_tw.is_valid() and m._view_tw.is_running():
		await process_frame
	await process_frame


func ang(m: Node, y: float, p: float) -> float:
	return maxf(absf(wrapf(m.yaw - y, -180.0, 180.0)), absf(m.pitch - p))


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await frames(3)
	var cx: CamExtras = m.camx
	ok(cx != null, "main owns a CamExtras")
	if cx == null:
		print("c01: %d fail" % fails)
		quit(1)
		return
	cx.hist.clear()
	cx.at = -1
	ok(not cx.can_back() and not cx.back(), "H1 control: a fresh history cannot go back")
	# H1
	var views := []
	for k in [1, 2, 4, 5]:
		m._view(k, false)
		m.target = Vector3(0, 0.95, 0)
		m._cam()
		views.append(cx.view_now())
		cx.note()
	ok(cx.hist.size() == 4, "H1 four held views noted (%d)" % cx.hist.size())
	ok(absf(wrapf(views[1]["yaw"] - views[2]["yaw"], -180.0, 180.0)) > 20.0, "H1 control: view 2 and view 3 differ by more than 20 deg")
	cx.back()
	await settle(m)
	cx.back()
	await settle(m)
	ok(ang(m, views[1]["yaw"], views[1]["pitch"]) < 0.5 and (m.target - views[1]["target"]).length() < 0.02, "H1 back twice lands on view 2 (yaw %.2f want %.2f)" % [m.yaw, views[1]["yaw"]])
	ok(cx.hist.size() == 4 and cx.at == 1, "H1 stepping back is not a new entry (size %d at %d)" % [cx.hist.size(), cx.at])
	cx.forward()
	await settle(m)
	ok(ang(m, views[2]["yaw"], views[2]["pitch"]) < 0.5, "H1 forward lands on view 3 (yaw %.2f want %.2f)" % [m.yaw, views[2]["yaw"]])
	var ek := InputEventKey.new()
	ek.keycode = KEY_LEFT
	ek.alt_pressed = true
	ek.pressed = true
	Input.parse_input_event(ek)
	await frames(2)
	await settle(m)
	ok(ang(m, views[1]["yaw"], views[1]["pitch"]) < 0.5, "H1 Alt+Left as a key event steps back (yaw %.2f)" % m.yaw)
	cx.hist.clear()
	cx.at = -1
	for i in 30:
		m.yaw = float(i) * 7.0
		m._cam()
		cx.note()
	ok(cx.hist.size() == 20, "H1 30 views keep exactly 20 (%d)" % cx.hist.size())
	# I1
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(10, 0)
	mm.position = Vector2(500, 300)
	m.yaw = 0.0
	m.dragging = "orbit"
	m._unhandled_input(mm)
	var d_def: float = m.yaw
	ok(absf(d_def - (-4.0)) < 0.01, "I1 control: default orbit drag of 10 px turns yaw by -4.0 (%.3f)" % d_def)
	cx.set_invert(true, false)
	m.yaw = 0.0
	m.dragging = "orbit"
	m._unhandled_input(mm)
	ok(absf(m.yaw - 4.0) < 0.01, "I1 inverted orbit turns yaw by +4.0 (%.3f)" % m.yaw)
	m.dragging = "pan"
	cx.set_invert(false, false)
	var t0: Vector3 = m.target
	m._unhandled_input(mm)
	var dp0: Vector3 = m.target - t0
	cx.set_invert(false, true)
	m.target = t0
	m._unhandled_input(mm)
	var dp1: Vector3 = m.target - t0
	ok(dp0.length() > 1e-5 and dp0.dot(dp1) < 0.0 and absf(dp0.length() - dp1.length()) < 1e-5, "I1 inverted pan moves the target the opposite way (%.5f vs %.5f)" % [dp0.length(), dp1.length()])
	var cx2 := CamExtras.new(m)
	ok(cx2.invert_pan and not cx2.invert_orbit, "I1 the choice is saved in the settings file")
	cx.set_invert(false, false)
	m.dragging = ""
	# T1
	var cube: ViewCube = m.ui_cube
	m._view(1, false)
	await frames(3)   # the cube draws from the camera of the last frame
	var c0 := cube._quad(0)
	var cen0 := (c0[0] + c0[1] + c0[2] + c0[3]) * 0.25
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = cen0
	cube._gui_input(e)
	await settle(m)
	ok(absf(m.pitch - (-8.0)) < 0.5, "T1 control: default middle click on FRONT gives pitch -8 (%.2f)" % m.pitch)
	ok(cube.label_of(0) == "FRONT" and cube.label_of(2) == "TOP", "T1 default labels")
	# the right-click menu
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_RIGHT
	r.pressed = true
	r.position = cen0
	cube._gui_input(r)
	ok(cx.menu != null and cx.menu.item_count == 2 and cx.menu.get_item_text(0) == "Make this face Top", "T1 right-click on a face opens the menu")
	var shown_face := cube.face_at(cen0)
	ok(shown_face == 0, "T1 the face under the click is FRONT (%d)" % shown_face)
	cx.menu.id_pressed.emit(1)
	await frames(2)
	ok(cx.cube_top.is_equal_approx(Vector3(0, 0, 1)), "T1 Make this face Top stores +Z (%s)" % str(cx.cube_top))
	ok(cube.label_of(0) == "TOP" and cube.label_of(2) == "BACK", "T1 FRONT face reads TOP, old TOP reads BACK (%s, %s)" % [cube.label_of(0), cube.label_of(2)])
	cube._gui_input(e)
	await settle(m)
	ok(absf(m.pitch) < 0.5 and absf(m.yaw) < 0.5, "T1 middle click on the new TOP looks from +Z at pitch 0 (%.2f, %.2f)" % [m.yaw, m.pitch])
	var d: Dictionary = m._scene_dict()
	var a: Array = d.get("cube_top", [])
	ok(a.size() == 3 and absf(float(a[2]) - 1.0) < 0.01 and absf(float(a[1])) < 0.01, "T1 the scene dict carries cube_top (%s)" % str(a))
	cx.set_top(Vector3.ZERO)
	ok(cube.label_of(0) == "FRONT" and not m._scene_dict().has("cube_top"), "T1 reset: default labels, no key written")
	cx.from_scene(d)
	ok(cube.label_of(0) == "TOP" and cube.label_of(2) == "BACK", "T1 reading the scene back restores the Top")
	cx.from_scene({})
	ok(cube.label_of(0) == "FRONT", "T1 a scene without the key shows the default cube")
	# screenshot at 1280x720: history buttons + a turned cube
	cx.set_top(Vector3(1, 0, 0))
	m._view(5, false)
	cx.note()
	m._view(1, false)
	cx.note()
	await frames(6)
	DirAccess.make_dir_recursive_absolute("C:/Users/Nick/tools/kine_workers/out/c01")
	var img := root.get_texture().get_image()
	img.save_png("C:/Users/Nick/tools/kine_workers/out/c01/shot_1280x720.png")
	print("shot size ", img.get_size())
	print("c01: %d fail" % fails)
	quit(1 if fails > 0 else 0)
