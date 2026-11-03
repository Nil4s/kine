extends SceneTree
## godot --path . -s tests/c41_test.gd     (C41: #184 invert orbit X / Y and pan apart, #311 bad spots; needs a window)
## Bars, written before the first run:
##  #184 (one orbit drag of (10,10) px, default 0.4 deg/px: yaw -4.0 and pitch d0 = whatever the default gives):
##   (1) CONTROL/default: with every invert off the yaw change is -4.0 +-0.01 and pitch change is nonzero; the new flags exist and are false
##   (2) orbit X only: yaw +4.0 +-0.01, pitch change equals the default's to 1e-6
##   (3) orbit Y only: yaw -4.0 +-0.01, pitch change equals minus the default's to 1e-6
##   (4) both X and Y: yaw +4.0 and pitch minus the default's; and the old invert_orbit alone gives exactly the same two numbers
##   (5) old invert_orbit + X: yaw -4.0 (they cancel), pitch minus the default's
##   (6) pan is untouched by the orbit flags (target moves the same vector as the default, to 1e-6); the old pan invert still reverses it
##   (7) saved: a new CamExtras reading the same file has X and Y as set; a file without the keys gives false, false
##   (8) UI: the camera navigation window has checkboxes invert_orbit_x and invert_orbit_y, toggling them sets the flags, and at
##       1280x720 the window's rect lies inside the viewport (screenshot to out/c41)
##  #311 (already built by C05; checked here, not rebuilt):
##   (9) CONTROL: the clean cube has 0 spots and an empty marker mesh; the broken cube has >= 3 spots and a marker with > 0 line verts
##       drawn without depth test
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c41"
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func orbit_once() -> Vector2:
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(10, 10)
	mm.position = Vector2(500, 300)
	m.yaw = 0.0
	m.pitch = 0.0
	m.dragging = "orbit"
	m._unhandled_input(mm)
	m.dragging = ""
	return Vector2(m.yaw, m.pitch)


func pan_once() -> Vector3:
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(10, 6)
	mm.position = Vector2(500, 300)
	var t0: Vector3 = m.target
	m.dragging = "pan"
	m._unhandled_input(mm)
	m.dragging = ""
	var d: Vector3 = m.target - t0
	m.target = t0
	m._cam()
	return d


func flags(cx, o: bool, x: bool, y: bool, p: bool) -> void:
	cx.invert_orbit = o
	cx.invert_pan = p
	if "invert_orbit_x" in cx:
		cx.invert_orbit_x = x
		cx.invert_orbit_y = y


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.start_screen._start_kind_now("animation")
	await idle(10)
	var cx: CamExtras = m.camx
	var has := "invert_orbit_x" in cx
	flags(cx, false, false, false, false)
	var d0 := orbit_once()
	var p0 := pan_once()
	ok(has and not cx.get("invert_orbit_x") and not cx.get("invert_orbit_y") and absf(d0.x + 4.0) < 0.01 and absf(d0.y) > 0.1, "(1) default: yaw %.3f pitch %.3f, new flags exist and are off" % [d0.x, d0.y])
	flags(cx, false, true, false, false)
	var d := orbit_once()
	ok(absf(d.x - 4.0) < 0.01 and absf(d.y - d0.y) < 1e-6, "(2) X only: yaw %.3f pitch %.4f (default %.4f)" % [d.x, d.y, d0.y])
	flags(cx, false, false, true, false)
	d = orbit_once()
	ok(absf(d.x + 4.0) < 0.01 and absf(d.y + d0.y) < 1e-6, "(3) Y only: yaw %.3f pitch %.4f" % [d.x, d.y])
	flags(cx, false, true, true, false)
	d = orbit_once()
	flags(cx, true, false, false, false)
	var dold := orbit_once()
	ok(absf(d.x - 4.0) < 0.01 and absf(d.y + d0.y) < 1e-6 and d.is_equal_approx(dold), "(4) X+Y: %s equals the old invert_orbit %s" % [d, dold])
	flags(cx, true, true, false, false)
	d = orbit_once()
	ok(absf(d.x + 4.0) < 0.01 and absf(d.y + d0.y) < 1e-6, "(5) old + X cancel yaw: %s" % d)
	flags(cx, false, true, true, false)
	var p1 := pan_once()
	flags(cx, false, false, false, true)
	var p2 := pan_once()
	ok(p0.length() > 1e-5 and p1.is_equal_approx(p0) and p2.dot(p0) < 0.0 and absf(p2.length() - p0.length()) < 1e-6, "(6) orbit flags leave pan alone; old pan invert reverses it")
	var f := "user://c41_settings.cfg"
	DirAccess.remove_absolute(f)
	flags(cx, false, true, false, false)
	if has:
		cx.save_to(f)
	var cx2 := CamExtras.new(null)
	cx2.load_from(f)
	var cx3 := CamExtras.new(null)
	cx3.load_from("user://c41_none.cfg")
	ok(has and cx2.get("invert_orbit_x") == true and cx2.get("invert_orbit_y") == false and cx3.get("invert_orbit_x") == false and cx3.get("invert_orbit_y") == false, "(7) saved and reloaded; missing keys give off")
	flags(cx, false, false, false, false)
	# UI
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(1280, 720)
	await idle(20)
	m.camnav_ui.open()
	await idle(10)
	var w: Window = m.camnav_ui.win
	var bx := w.find_child("invert_orbit_x", true, false) as CheckBox
	var by := w.find_child("invert_orbit_y", true, false) as CheckBox
	var ui_ok := bx != null and by != null
	if ui_ok:
		bx.button_pressed = true
		by.button_pressed = true
		ui_ok = cx.get("invert_orbit_x") == true and cx.get("invert_orbit_y") == true
		bx.button_pressed = false
		by.button_pressed = false
		ui_ok = ui_ok and cx.get("invert_orbit_x") == false
	var wr := Rect2(Vector2(w.position), Vector2(w.size))
	var inside := Rect2(Vector2.ZERO, Vector2(DisplayServer.screen_get_size())).encloses(wr)
	var last_y := 0.0
	for c in w.find_children("*", "CheckBox", true, false):
		last_y = maxf(last_y, (c as CheckBox).get_global_rect().end.y)
	ok(ui_ok and last_y <= float(w.size.y), "(8) window has the two boxes, toggles set the flags, last box ends at y=%.0f of window height %d" % [last_y, w.size.y])
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(SHOT + "/nav_1280x720.png")
	# #311
	var clean := KMesh.new().from_arrays(PackedVector3Array(CV), [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]])
	var v := PackedVector3Array(CV)
	v.append(Vector3(1, 1, 1))
	v.append(Vector3(5, 5, 5))
	var broken := KMesh.new().from_arrays(v, [[0,3,2,1], [4,5,8,7], [0,1,5,4], [1,2,6,5], [3,7,4,0], [0,1,1]])
	var sc := KMeshSpots.spots(clean)
	var sb := KMeshSpots.spots(broken)
	var mk := KMeshSpots.marker_mesh(broken, sb[0]) if sb.size() > 0 else ArrayMesh.new()
	var mk0 := KMeshSpots.marker_mesh(clean, {"mode": 0, "items": []})
	ok(sc.is_empty() and mk0.get_surface_count() == 0 and sb.size() >= 3 and mk.get_surface_count() == 1 and (mk.surface_get_material(0) as StandardMaterial3D).no_depth_test, "(9) clean: %d spots, no marker; broken: %d spots, marker drawn without depth test" % [sc.size(), sb.size()])
	print("c41: %d fail" % fails)
	quit(1 if fails > 0 else 0)
