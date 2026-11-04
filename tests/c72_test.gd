extends SceneTree
## c72 (C72): the tooltip popup (TooltipPanel) is opaque with a 1 px border, so what is under it does not read through.
## Bars (written before any number was read), all on the REAL popup of Measure in Easy Part at 1024x600, mouse at rest on the chip:
##  1 BODY    ring of pixels 3 px inside the popup rect (the padding, no text) is within 3 levels (of 255) of the panel colour on EVERY sample
##  2 BORDER  the 1 px rim pixels are within 20 levels of the border colour (blended by the window scale)
##  3 BUSY    the same ring with the popup gone varies by >= 12 levels, so the UI under the popup was busy (else bar 1 proves nothing)
##  CONTROL   a translucent planted panel (the old 0.94 alpha) over the same pixels fails bar 1 by the same checker
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c72"
const DIRT := "user://c72_test"
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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	if c == null:
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0), true)
	await ev_mouse(b, false)
	await idle(3)


func grab() -> Image:
	await idle(3)
	return root.get_texture().get_image()


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func find_tip() -> Window:
	for c in root.get_embedded_subwindows():
		if c.visible and not (c is PopupMenu):
			return c
	return null


func enter(kind: String) -> void:
	var ss: StartScreen = m.start_screen
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn[kind])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)


## ring sample points: along the four sides of rc, `inset` px inside, every 4 px, skipping the 12 px at each corner
func ring(rc: Rect2i, inset: int) -> Array:
	var pts: Array = []
	var x0 := rc.position.x + inset
	var x1 := rc.position.x + rc.size.x - 1 - inset
	var y0 := rc.position.y + inset
	var y1 := rc.position.y + rc.size.y - 1 - inset
	for x in range(x0 + 12, x1 - 11, 4):
		pts.append(Vector2i(x, y0))
		pts.append(Vector2i(x, y1))
	for y in range(y0 + 12, y1 - 11, 4):
		pts.append(Vector2i(x0, y))
		pts.append(Vector2i(x1, y))
	return pts


## the biggest per-channel distance, in 0..255 levels, between pixel p of img and colour c
func lv(img: Image, p: Vector2i, c: Color) -> float:
	var q := img.get_pixelv(p)
	return maxf(absf(q.r - c.r), maxf(absf(q.g - c.g), absf(q.b - c.b))) * 255.0


func worst(img: Image, pts: Array, c: Color) -> float:
	var w := 0.0
	for p in pts:
		w = maxf(w, lv(img, p, c))
	return w


func spread(img: Image, pts: Array) -> float:
	var lo := 1.0
	var hi := 0.0
	for p in pts:
		var l := img.get_pixelv(p).get_luminance()
		lo = minf(lo, l)
		hi = maxf(hi, l)
	return (hi - lo) * 255.0


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
	await enter("building")
	m.target = Vector3.ZERO
	await idle(30)
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	var sz := Vector2i(1024, 600)
	root.size = sz
	root.content_scale_size = sz
	await idle(30)
	var chip: Control = m.find_child("easypart_view_measure", true, false)
	if chip != null and chip.toggle_mode and (chip as Button).button_pressed:
		(chip as Button).button_pressed = false
	await ev_move(Vector2(sz.x * 0.5, sz.y * 0.9))
	await idle(10)
	await ev_move(chip.get_global_rect().get_center())
	var found: Window = null
	for i in 12:
		await idle(30)
		found = find_tip()
		if found != null:
			break
	ok(found != null, "the real tooltip popup for Measure is shown at %s" % sz)
	if found == null:
		print("c72: %d fail" % fails)
		quit(1)
		return
	var rc := Rect2i(found.position, found.size)
	var sb: StyleBoxFlat = chip.get_theme_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	var panel := Color(sb.bg_color, 1.0)
	var rim: Color = sb.border_color
	var img := await grab()
	DirAccess.make_dir_recursive_absolute(SHOT)
	img.save_png(SHOT + "/tooltip_with_1024x600.png")
	# the window is shown at a scale (canvas items): sample in the screenshot's own pixels, only where the popup is inside the image
	var k := float(img.get_width()) / float(root.get_visible_rect().size.x)
	var rp := Rect2i(Vector2i(Vector2(rc.position) * k), Vector2i(Vector2(rc.size) * k))
	print("image %s, scale %.3f, popup in pixels %s" % [img.get_size(), k, rp])
	var inimg := func(p: Vector2i) -> bool: return p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height()
	var pts: Array = ring(rp, 4).filter(inimg)
	var wb := worst(img, pts, panel)
	print("popup rect %s, %d samples, panel %s, worst body distance %.1f levels" % [rc, pts.size(), panel, wb])
	ok(pts.size() >= 20 and wb < 3.0, "BODY: every padding sample is within 3 levels of the panel colour (worst %.1f of %d)" % [wb, pts.size()])
	var wr := 0.0   # the rim is 1 css px = k image px, blended: per sample the nearer of the two outer rows (columns)
	var dr := 255.0
	var rpts: Array = ring(rp, 0).filter(inimg)
	for p in rpts:
		var nrm: Vector2i = Vector2i(0, 1) if (p.y <= rp.position.y + 1) else (Vector2i(0, -1) if p.y >= rp.end.y - 2 else (Vector2i(1, 0) if p.x <= rp.position.x + 1 else Vector2i(-1, 0)))
		var best := 255.0
		for o in range(-3, 4):
			var qq: Vector2i = p + nrm * o
			if inimg.call(qq):
				best = minf(best, lv(img, qq, rim))
		wr = maxf(wr, best)
		dr = minf(dr, lv(img, p, panel))
	print("rim: worst distance to border colour %s %.1f, nearest to panel colour %.1f" % [rim, wr, dr])
	ok(sb.border_width_left == 1 and sb.border_width_top == 1 and wr < 20.0 and rpts.size() >= 20, "BORDER: 1 px rim in the border colour, rim worst %.1f levels off (nearest to panel %.1f)" % [wr, dr])
	# the popup gone: what lay under it
	await ev_move(Vector2(sz.x * 0.5, sz.y * 0.9))
	await idle(40)
	var under := find_tip() == null
	var img2 := await grab()
	img2.save_png(SHOT + "/tooltip_gone_1024x600.png")
	var sp := spread(img2, pts)
	print("under the popup: popup gone %s, luminance spread %.1f levels" % [str(under), sp])
	ok(under and sp >= 12.0, "BUSY: the ring pixels vary by %.1f levels without the popup (>= 12)" % sp)
	# CONTROL: the old translucent panel (alpha 0.94) laid over the SAME underlying pixels
	var wc := 0.0
	for p in pts:
		var u := img2.get_pixelv(p)
		var bl := Color(panel.r * 0.94 + u.r * 0.06, panel.g * 0.94 + u.g * 0.06, panel.b * 0.94 + u.b * 0.06)
		wc = maxf(wc, maxf(absf(bl.r - panel.r), maxf(absf(bl.g - panel.g), absf(bl.b - panel.b))) * 255.0)
	ok(wc >= 3.0, "control: a 0.94-alpha panel over these pixels is %.1f levels off, so the checker can fail" % wc)
	print("c72: %d fail" % fails)
	quit(1 if fails > 0 else 0)
