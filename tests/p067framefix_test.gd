extends SceneTree
## p067framefix: the Hinge chip frames the hinge it builds, and a butt hinge shows its two leaves and a knuckle.
## A beginner from the BUILDING card (empty Easy Part) with real mouse clicks and drags only: Parts > Hinges > Hinge (a Butt hinge), then
## the Kind slider to Piano (2). The view is the template's own corner view (VIEW in scripts/build/part_templates.gd).
## Bars:
##   0 PIANO   after Hinge and Piano, the solid's screen box is at least 30 % of the clear view's height (measured from the camera
##             projection of the solid's eight AABB corners, mm box of the built mesh, in the part's own frame)
##   1 BUTT    the Butt hinge is one solid (bodies == 1), box 60 x 100 mm. NOTE: this does not check a knuckle; the two-leaf knuckle
##             geometry is NOT built yet (see the commit message)
## Shots: C:/Temp/claude/p067framefix/ (00_butt.png, 01_piano.png)
const SHOT := "C:/Temp/claude/p067framefix"
const DIRT := "user://p067framefix_test"
const SHARE_MIN := 0.30
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
	return true


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a slider knob position (screen px) for a value: the track runs between the centres of the two end grabbers
func knob_x(s: HSlider, v: float) -> Vector2:
	var r := s.get_global_rect()
	var t := (v - s.min_value) / maxf(s.max_value - s.min_value, 1e-6)
	return Vector2(r.position.x + 12.0 + t * (r.size.x - 24.0), r.get_center().y)


func slide_to(s: HSlider, v: float) -> void:
	var a := knob_x(s, s.value)
	await drag_screen(a, knob_x(s, v))


func row_of(ep, key: String) -> Dictionary:
	for r in ep.rows:
		if String(r.get("key", "")) == key:
			return r
	return {}


func pu():
	return m.bld.part


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## the solid's screen box as a share of the clear view's height: the eight AABB corners of the built mesh (part frame), projected by the camera
func screen_share() -> float:
	var mesh: ArrayMesh = pu().res.get("mesh")
	if mesh == null or m.cam == null:
		return 0.0
	var bb := mesh.get_aabb()
	var lo := INF
	var hi := -INF
	for i in 8:
		var c := bb.get_endpoint(i)
		var sp: Vector2 = m.cam.unproject_position(pu().part_mesh.global_transform * c)
		lo = minf(lo, sp.y)
		hi = maxf(hi, sp.y)
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	return (hi - lo) / vs.y


func box_mm() -> Array:
	var mesh: ArrayMesh = pu().res.get("mesh")
	if mesh == null:
		return []
	var sz := mesh.get_aabb().size * 1000.0
	return [sz.x, sz.y, sz.z]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# the BUILDING card, one click: an empty Easy Part
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var ep = pu().ep

	# Parts > Hinges > Hinge: one click builds the Butt hinge, and the view frames it
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Control)
	await click_ctl(root.find_child("easypart_lib_Hinges", true, false) as Control)
	var hinge_chip := root.find_child("easypart_hinge_pick", true, false) as Button
	await click_ctl(hinge_chip)
	await idle(10)
	var bodies := int(pu().res.get("bodies", 0))
	var bx := box_mm()
	ok(bodies == 1 and bx.size() == 3 and absf(float(bx[0]) - 60.0) < 0.5 and absf(float(bx[1]) - 100.0) < 0.5,
		"1 BUTT: one solid (%d bodies), box %s mm (want 60 x 100; no knuckle check yet)" % [bodies, str(bx)])
	await shot("00_butt")

	# Kind to Piano (2): the strip, 240 cm tall, is framed in the clear view
	var sk: HSlider = row_of(ep, "kind").get("slider")
	if sk != null:
		await slide_to(sk, 2.0)
	await idle(10)
	await shot("01_piano")
	var kd := int(pu()._rec().get("easy", {}).get("p", {}).get("kind", 0))
	var share := screen_share()
	ok(kd == 2 and share >= SHARE_MIN,
		"0 PIANO: kind %d, the solid's screen box is %.1f %% of the clear view's height (want at least %d %%)" % [kd, share * 100.0, int(SHARE_MIN * 100.0)])
	print("p067framefix: %d fail(s)" % fails)
	quit(0 if fails == 0 else 1)
