extends SceneTree
## godot --path . -s tests/c33_test.gd     (C33: sketch UI polish from the batch 9 looks)
## Bars, written before any number was read (distance = Euclid in 0..255 RGB of the RENDERED pixels):
##   1 RING   "Show what is free" ON, a rectangle of four lines. The ring pixel (just beside a free line, outside its 2.5 px core, ring only)
##            and the yellow selection pixel (the core of the line the Dimension tool hovers) are at least 120 apart,
##            and the ring is still orange-red (red - blue >= 25, the c21 bar). The ring is also not one solid stripe: along the line
##            the ring pixels alternate (a gap of the plain background shows at least once over 60 px) = a distinct SHAPE as well.
##   2 LABEL  The "Show what is free" label with the mouse ON it: contrast ratio (WCAG) between the text pixel farthest from the
##            box background and that background >= 4.5.  Same for the label un-hovered (>= 4.5, must not regress).
##   3 CONTROL contrast() of grey 119 on white is < 4.5 and of black on white > 20; dist() of the OLD ring colour over the line blue
##            against the yellow selection composited the same way is < 120 (the old pair fails the bar, so the bar can fail).
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c33"
const DIRT := "user://c33_test"
const BAR_DIST := 120.0
const BAR_CONTRAST := 4.5
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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	var i: int = m._more_tools.find(b)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


func key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e, true)
	await idle(2)


func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func shot(nm: String) -> Image:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT, nm])
	return img


func px(img: Image, p: Vector2) -> Color:
	var sx := float(img.get_width()) / float(root.size.x)
	var sy := float(img.get_height()) / float(root.size.y)
	return img.get_pixel(clampi(int(p.x * sx), 0, img.get_width() - 1), clampi(int(p.y * sy), 0, img.get_height() - 1))


func dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() * 255.0


func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func contrast(a: Color, b: Color) -> float:
	var l1 := lum(a)
	var l2 := lum(b)
	return (maxf(l1, l2) + 0.05) / (minf(l1, l2) + 0.05)


## [text colour, background colour, contrast]: background = the pixel at the right edge inside the rect, text = the pixel farthest from it
func label_read(img: Image, r: Rect2, skip_left: float) -> Array:
	var bg := px(img, Vector2(r.end.x - 3.0, r.position.y + r.size.y * 0.5))
	var best := bg
	var bd := -1.0
	for y in range(int(r.position.y) + 2, int(r.end.y) - 2):
		for x in range(int(r.position.x + skip_left), int(r.end.x) - 3):
			var c := px(img, Vector2(x, y))
			var d := dist(c, bg)
			if d > bd:
				bd = d
				best = c
	return [best, bg, contrast(best, bg)]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
		return
	var wd := Timer.new()   # watchdog: the whole test must end in 240 s
	wd.wait_time = 240.0
	wd.one_shot = true
	wd.timeout.connect(func():
		print("FAIL watchdog: c33 ran past 240 s")
		quit(2))
	root.add_child(wd)
	wd.start()
	ok(contrast(Color8(119, 119, 119), Color.WHITE) < BAR_CONTRAST, "3 CONTROL grey 119 on white fails the contrast bar (%.2f)" % contrast(Color8(119, 119, 119), Color.WHITE))
	ok(contrast(Color.BLACK, Color.WHITE) > 20.0, "3 CONTROL black on white passes (%.1f)" % contrast(Color.BLACK, Color.WHITE))
	var blue := Color("#73BFFF")
	var old_ring := Color(1.0, 0.62, 0.04, 0.6)
	var old_over := blue.lerp(Color(old_ring.r, old_ring.g, old_ring.b), old_ring.a)
	var old_d := dist(old_over, Color("#ffc233"))
	ok(old_d < BAR_DIST, "3 CONTROL the OLD ring over blue vs the yellow selection is %.0f apart, under the bar %.0f" % [old_d, BAR_DIST])
	await run_ui()
	print("c33: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)


func run_ui() -> void:
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	await press_tool(pu, "Line")
	for q in [[0, 0], [100, 0], [100, 60], [0, 60], [0, 0]]:
		await click_at(sp2(q[0], q[1]))
	await key(KEY_ESCAPE)
	var sk: Dictionary = pu._sk()
	for c in [{"k": "coin", "a": 0, "ap": 1, "b": 1, "bp": 0}, {"k": "coin", "a": 1, "ap": 1, "b": 2, "bp": 0}, {"k": "coin", "a": 2, "ap": 1, "b": 3, "bp": 0}, {"k": "coin", "a": 3, "ap": 1, "b": 0, "bp": 0},
			{"k": "h", "a": 0}, {"k": "h", "a": 2}, {"k": "v", "a": 1}, {"k": "v", "a": 3}]:
		Part.con_put(sk, c)
	pu._after_sketch_edit()
	await idle(3)
	var chk: CheckBox = m.find_child("part_show_free", true, false)
	await ev_move(Vector2(5, 5))
	await idle(3)
	var img0 := await shot("c33_label_idle")
	var lu := label_read(img0, chk.get_global_rect(), 28.0)
	print("   label idle text ", lu[0], " bg ", lu[1], " contrast ", lu[2])
	ok(float(lu[2]) >= BAR_CONTRAST, "2 LABEL idle contrast %.2f >= %.1f" % [float(lu[2]), BAR_CONTRAST])
	await ev_move(chk.get_global_rect().get_center())
	await idle(4)
	var img1 := await shot("c33_label_hover")
	var lh := label_read(img1, chk.get_global_rect(), 28.0)
	print("   label hover text ", lh[0], " bg ", lh[1], " contrast ", lh[2])
	ok(float(lh[2]) >= BAR_CONTRAST, "2 LABEL hovered contrast %.2f >= %.1f" % [float(lh[2]), BAR_CONTRAST])
	await click_ctl(chk)
	var img2 := await shot("c33_label_on_hover")
	var lo := label_read(img2, chk.get_global_rect(), 28.0)
	print("   label ON+hover text ", lo[0], " bg ", lo[1], " contrast ", lo[2])
	ok(float(lo[2]) >= BAR_CONTRAST, "2 LABEL ON and hovered contrast %.2f >= %.1f" % [float(lo[2]), BAR_CONTRAST])
	await ev_move(Vector2(5, 5))
	await idle(3)
	var img3 := await shot("c33_label_on_idle")
	var li := label_read(img3, chk.get_global_rect(), 28.0)
	print("   label ON idle text ", li[0], " bg ", li[1], " contrast ", li[2])
	ok(float(li[2]) >= BAR_CONTRAST, "2 LABEL ON idle contrast %.2f >= %.1f" % [float(li[2]), BAR_CONTRAST])
	ok(pu.show_free, "1 the click turned Show what is free on")
	await press_tool(pu, "Dimension")
	var rside := sp2(100, 30)
	await ev_move(rside)
	pu.hover_ent = {"ent": 1}   # the line the Dimension tool hovers (set directly: the pick needs the real ray)
	pu.pov.queue_redraw()
	await idle(4)
	var img := await shot("c33_ring_vs_sel")
	var bottom := sp2(50, 0)
	var sel_p := px(img, rside)
	var ring_p := px(img, bottom + Vector2(0, 3.5))
	var d := dist(ring_p, sel_p)
	print("   ring ", ring_p, " selection ", sel_p, " dist ", d)
	ok(d >= BAR_DIST, "1 ring vs selection pixel distance %.0f >= %.0f" % [d, BAR_DIST])
	ok(ring_p.r - ring_p.b >= 25.0 / 255.0, "1 the ring is still orange-red (red-blue %.0f)" % ((ring_p.r - ring_p.b) * 255.0))
	var plain := px(img, bottom + Vector2(0, 14))
	var gaps := 0
	var hits := 0
	for dx in range(-30, 30):
		var c := px(img, bottom + Vector2(dx, 3.5))
		if dist(c, plain) < 40.0:
			gaps += 1
		elif dist(c, ring_p) < 60.0:
			hits += 1
	ok(gaps >= 4 and hits >= 8, "1 the ring is dashed: %d gap px and %d ring px over 60 px" % [gaps, hits])
