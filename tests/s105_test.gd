extends SceneTree
## S105 NICE PICTURE (Friday plan 105): the Export dialog has a "Nice picture" button. Real clicks at 1280 x 720: BUILDING card -> Easy Part
## -> draw a box -> Pull it up -> Export (bar) -> Nice picture. Every bar is measured from the saved PNG re-read from disk.
##   B0 no part: no file, words say draw a shape first
##   B1 the button is in the Export dialog (no new bar / panel row)
##   B2 size 1920 x 1080 and the words name the path (the file exists)
##   B3 no UI pixels: none within 0.05 of the top-bar yellow (Tok accent)
##   B4 the part covers 20-70 % of the frame (its pixel box) and is centred within 10 %
##   B5 shadow: floor right below the part is >= 15 % darker (luminance) than the floor 300 px away on the same row
##   B6 smooth gradient: row-wise high-frequency energy of the empty top band is below a quarter of the grid screenshot's (control > 0)
##   B7 the render takes < 3 s (press to saved words)
##   B8 the app view is unchanged: screenshot before/after differ in < 1 % of pixels outside the dialog
const SHOT := "C:/Temp/claude/s105"
const DIRT := "user://s105_test"
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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func lum(c: Color) -> float:
	return c.get_luminance()


## mean |second difference| of the luminance along the rows of a region (the row-wise high-frequency energy)
func hf_energy(img: Image, r: Rect2i, step_y := 4) -> float:
	var tot := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, step_y):
		var prev2 := lum(img.get_pixel(r.position.x, y))
		var prev1 := lum(img.get_pixel(r.position.x + 1, y))
		for x in range(r.position.x + 2, r.end.x):
			var cur := lum(img.get_pixel(x, y))
			tot += absf(cur - 2.0 * prev1 + prev2)
			n += 1
			prev2 = prev1
			prev1 = cur
	return tot / maxf(n, 1)


func cdist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


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
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)
	# the grid control: the empty app view, a region of grid floor
	await shot("grid")
	var gimg: Image = Image.load_from_file(SHOT + "/grid.png")
	var g_e := hf_energy(gimg, Rect2i(380, 330, 500, 330), 2)
	print("grid control: row energy %.5f" % g_e)

	# the part: a chunky box on the grid, pulled up
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.05, 0.0, -0.05)), scr(Vector3(0.05, 0.0, 0.05))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var vol1 := vol_mm3(solid())
	var nund: int = m.undo.size()
	print("part volume %.0f mm3, box mm %s" % [vol1, (solid()["aabb"] as AABB).size / Part.MM])

	# open the Export dialog with a real click on the bar's Export button
	await click_ctl(ep.export_btn)
	await idle(10)
	var ed: ExportDialog = m.export_ui
	var dlg: Window = ed.dlg
	ok(ed.nice_btn != null and ed.nice_btn.is_visible_in_tree() and dlg.is_ancestor_of(ed.nice_btn) and ed.nice_btn.get_global_rect().end.y < 720.0 and ed.nice_btn.text == "Nice picture",
		"B1 the Export dialog has a visible Nice picture button")
	await shot("dialog")
	var before: Image = root.get_texture().get_image()
	var drect_a := Rect2(dlg.position, dlg.size)

	# B7 timed press: real click, until the words name the file
	var t0 := Time.get_ticks_msec()
	ed.nice_btn.pressed.emit()   # an embedded dialog does not take pushed mouse events here (s119 does the same); the button's own signal
	var guard := 0
	while not String(ed.nice_say.text).begins_with("Nice picture saved") and guard < 600:
		await process_frame
		guard += 1
	var ms := Time.get_ticks_msec() - t0
	var words := String(ed.nice_say.text)
	ok(ms < 3000, "B7 the render takes %d ms (under 3000)" % ms)
	var path := words.substr(words.find("saved: ") + 7).replace(" (1920 x 1080)", "").strip_edges() if words.find("saved: ") >= 0 else ""
	ok(path != "" and FileAccess.file_exists(path), "B2 the words name a file that exists: [%s]" % words)
	var img: Image = Image.load_from_file(path) if path != "" else null
	if img == null:
		print("s105: %d fail" % (fails + 1))
		quit(1)
		return
	img.save_png(SHOT + "/nice.png")
	ok(img.get_width() == 1920 and img.get_height() == 1080, "B2 size read back from disk: %s" % img.get_size())
	await idle(5)
	await shot("after")
	var after: Image = root.get_texture().get_image()

	# B3 no UI pixels
	var acc := Tok.c("accent")
	var ui_px := 0
	var W := img.get_width()
	var H := img.get_height()
	for y in range(0, H, 2):
		for x in range(0, W, 2):
			if cdist(img.get_pixel(x, y), acc) < 0.05:
				ui_px += 1
	ok(ui_px == 0, "B3 no UI pixels: %d pixels near the Easy yellow (%s)" % [ui_px, acc])

	# B4 the part box: pixels far from the known empty background
	var bg: Image = NiceRender.background(img.get_size())
	var lo := Vector2i(W, H)
	var hi := Vector2i(-1, -1)
	var thr := 0.55
	# the part's own pixel box: the same picture drawn with no shadow and no reflection (the camera is fitted to the part, so it is the same view),
	# every pixel that differs from the empty gradient by more than 0.08 is the part
	NiceRender.part_only = true
	var po: Image = await NiceRender.draw(m, m.S.part)
	NiceRender.part_only = false
	for y in range(0, H, 3):
		for x in range(0, W, 3):
			if cdist(po.get_pixel(x, y), bg.get_pixel(x, y)) > 0.08:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	var cover := float((hi.x - lo.x) * (hi.y - lo.y)) / float(W * H)
	var cx := (lo.x + hi.x) * 0.5 / W
	var cy := (lo.y + hi.y) * 0.5 / H
	print("part box px: %s..%s cover %.1f %% centre %.3f,%.3f" % [lo, hi, cover * 100.0, cx, cy])
	ok(cover >= 0.20 and cover <= 0.70, "B4 the part covers %.1f %% of the frame (20-70)" % (cover * 100.0))
	ok(absf(cx - 0.5) <= 0.10 and absf(cy - 0.5) <= 0.10, "B4 centred: (%.3f, %.3f) within 0.10 of the middle" % [cx, cy])

	# B5 shadow: the floor right below the part's lowest point vs 300 px to the side, same row
	var low_x := lo.x
	var low_y := -1
	for x in range(lo.x, hi.x + 1, 3):
		for y in range(hi.y + 4, hi.y - 60, -1):
			if y < H and cdist(po.get_pixel(x, y), bg.get_pixel(x, y)) > 0.08:
				if y > low_y:
					low_y = y
					low_x = x
				break
	var ry := mini(low_y + 14, H - 1)
	var side_x := hi.x + 300 if hi.x + 300 < W else lo.x - 300
	var l_below := lum(img.get_pixel(low_x, ry))
	var l_far := lum(img.get_pixel(clampi(side_x, 0, W - 1), ry))
	var drop := (l_far - l_below) / maxf(l_far, 0.001)
	ok(drop >= 0.15, "B5 shadow: floor below the part lum %.3f vs 300 px away %.3f, %.1f %% darker (at least 15)" % [l_below, l_far, drop * 100.0])

	# B6 smooth gradient: the empty top band
	var n_e := hf_energy(img, Rect2i(0, 0, W, int(H * 0.12)), 4)
	ok(g_e > 0.0005 and n_e < g_e * 0.25, "B6 gradient: row energy %.6f vs the grid control %.6f (limit a quarter = %.6f)" % [n_e, g_e, g_e * 0.25])

	# B8 the app view is unchanged outside the dialog
	var drect_b := Rect2(dlg.position, dlg.size)
	# the dialog's rectangle is in the 1280 x 720 layout units, the screenshots are in window pixels: bring it into pixels first
	var sc := float(before.get_width()) / float(root.content_scale_size.x)
	var dm := drect_a.merge(drect_b).grow(4.0)
	var skip := Rect2(dm.position * sc, dm.size * sc)
	print("B8 screenshot %s, scale %.3f, dialog rect in pixels %s" % [before.get_size(), sc, skip])
	var diff := 0
	var tot := 0
	var dlo := Vector2i(99999, 99999)
	var dhi := Vector2i(-1, -1)
	for y in range(0, before.get_height(), 2):
		for x in range(0, before.get_width(), 2):
			if skip.has_point(Vector2(x, y)):
				continue
			tot += 1
			if cdist(before.get_pixel(x, y), after.get_pixel(x, y)) > 0.06:
				diff += 1
				dlo = Vector2i(mini(dlo.x, x), mini(dlo.y, y))
				dhi = Vector2i(maxi(dhi.x, x), maxi(dhi.y, y))
	print("B8 differing pixels lie in %s..%s" % [dlo, dhi])
	ok(float(diff) / maxf(tot, 1) < 0.01, "B8 app view unchanged: %.3f %% of the pixels outside the dialog differ (%d of %d)" % [100.0 * diff / maxf(tot, 1), diff, tot])
	ok(m.undo.size() == nund and absf(vol_mm3(solid()) - vol1) < 0.001 * vol1, "B8 the part did not change: undo %d -> %d" % [nund, m.undo.size()])

	# B0 with no part: no file and the words say what to do (last, it clears the part)
	m.S.part = {}
	var none: String = await ed.nice_picture()
	ok(none == "" and ed.nice_say.text.to_lower().find("draw") >= 0, "B0 no part: no file, the words say: [%s]" % ed.nice_say.text)
	print("s105: %d fail" % fails)
	quit(1 if fails > 0 else 0)
