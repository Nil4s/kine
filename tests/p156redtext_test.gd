extends SceneTree
## p156redtext (the bug on the #138 contact sheet): on the Sculpt page a huge red "is left" was drawn over the bottom-left of the view,
## letters about 120 px tall, clipped by the window edge. It is the floor's X axis name, "X  his left" (main.gd, the axis_tags Label3D):
## a world-sized label grows as the camera comes close. Every on-screen text here must be a normal size (under 40 px tall).
## The walk is p156solidmesht's: a box, Pull it up, "Sculpt details?" -> the Sculpt page.
##   R0 the box: one body, 12 mm or more square (BUILDING card, Easy, Pull it up)
##   R1 one click on "Sculpt details?": the Sculpt page is open with the sculpt on
##   R2 default view: no visible Label or Label3D on screen with text taller than 40 px (lists the offenders)
##   R3 close view (the camera as the stroke test has it): the same bar
##   R4 the axis names are shown at a normal size on the Sculpt page (the X name "X  his left" is on screen, under 40 px)
## shots: C:/Temp/claude/p156redtext/*.png
const SHOT := "C:/Temp/claude/p156redtext"
const DIRT := "user://p156redtext_test"
const BIG := 40.0
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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func mm(v: float) -> float:
	return v / Part.MM


func all_nodes(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		all_nodes(c, out)
	return out


## the text heights on screen that are over BIG px: a Label3D (its font pixel is pixel_size * viewport height / (2 tan(fov/2)), divided by
## the distance unless fixed_size) or a Label (its font size, in view pixels). Returns "name h" strings
func big_text() -> Array:
	var out: Array = []
	var vp: Vector2 = root.get_visible_rect().size
	var cam: Camera3D = m.cam
	var k := vp.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	for n in all_nodes(root, []):
		if n is Label3D:
			var l := n as Label3D
			if not l.is_visible_in_tree() or cam.is_position_behind(l.global_position):
				continue
			if not Rect2(Vector2.ZERO, vp).has_point(cam.unproject_position(l.global_position)):
				continue
			var h := float(l.font_size) * l.pixel_size * k
			if not l.fixed_size:
				h /= maxf(cam.global_position.distance_to(l.global_position), 0.0001)
			if h > BIG:
				out.append("%s %s %.0f px" % [l.get_path(), l.text.left(24), h])
		elif n is Label:
			var c := n as Label
			if not c.is_visible_in_tree() or c.text == "":
				continue
			var r := c.get_global_rect()
			if not Rect2(Vector2.ZERO, vp).intersects(r):
				continue
			var fs := float(c.get_theme_font_size("font_size"))
			if fs > BIG:
				out.append("%s %s %.0f px" % [c.get_path(), c.text.left(24), fs])
	return out


func axis_on_screen() -> String:
	var vp: Vector2 = root.get_visible_rect().size
	var cam: Camera3D = m.cam
	var found := ""
	for l in m.axis_tags:
		var t := l as Label3D
		if t == null or not t.is_visible_in_tree() or cam.is_position_behind(t.global_position):
			continue
		if Rect2(Vector2.ZERO, vp).has_point(cam.unproject_position(t.global_position)):
			found = t.text
	return found


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
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# R0 the box, as p156solidmesht S0
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	var a: Vector2 = m.cam.unproject_position(Vector3(-0.02, 0.0, -0.02))
	var b: Vector2 = m.cam.unproject_position(Vector3(0.02, 0.0, 0.02))
	await drag_pts([a, b])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s0: Dictionary = Part.replay(m.S.part, -1, {"faces": true, "props": true})
	var bb0: AABB = s0["aabb"]
	ok(int(s0["bodies"]) == 1 and mm(bb0.size.y) >= 12.0 and mm(bb0.size.x) >= 12.0,
		"R0 the box: one body, %.1f x %.1f x %.1f mm" % [mm(bb0.size.x), mm(bb0.size.y), mm(bb0.size.z)])

	# R1 "Sculpt details?" opens the Sculpt page
	var sbtn: Button = ep.suggest_row.find_child("easypart_suggest_sculpt", true, false) as Button
	if sbtn != null and sbtn.is_visible_in_tree():
		await click_ctl(sbtn)
	await idle(20)
	var ksc = m.ksc
	var sculpt_on: bool = ksc != null and ksc.on
	ok(sculpt_on and m.cur_page == "SCULPT", "R1 Sculpt details? opens the Sculpt page with the sculpt on (page %s)" % m.cur_page)

	# R2 the default view
	await shot("after")
	var bad := big_text()
	ok(bad.is_empty(), "R2 default view: no text over %d px on screen (%s)" % [int(BIG), "; ".join(bad).left(300) if not bad.is_empty() else "none"])

	# R3 the close view, as the stroke test has it
	var c_w := Vector3(0.0, 0.0, 0.0)
	if sculpt_on:
		c_w = ksc.mesh.verts[0] if ksc.mesh.verts.size() > 0 else c_w
	m.target = c_w + Vector3(1.0, 0.0, 0.0)
	m.dist = 0.35
	m._cam()
	await idle(20)
	await shot("close")
	var bad3 := big_text()
	ok(bad3.is_empty(), "R3 close view: no text over %d px on screen (%s)" % [int(BIG), "; ".join(bad3).left(300) if not bad3.is_empty() else "none"])

	# R4 the axis names are on screen at a normal size: the X name is a Label3D and is not clipped to a giant
	var ax := axis_on_screen()
	ok(sculpt_on and ax != "", "R4 an axis name is on screen on the Sculpt page (%s)" % ax)

	print("P156REDTEXT %d fails" % fails)
	quit(1 if fails > 0 else 0)
