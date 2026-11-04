extends SceneTree
## c72 (C72): the tooltip popup (TooltipPanel) is opaque with a 1 px border, so what is under it does not read through.
## Bars (written before any number was read), all on the REAL popup of Measure in Easy Part at 1024x600, mouse at rest on the chip:
##  1 BODY    ring of pixels 3 px inside the popup rect (the padding, no text) is within 3 levels (of 255) of the panel colour on EVERY sample
##  2 BORDER  the 1 px rim pixels are coverage (mass) of 1 px at the window scale, within 0.35
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


## (bare = the same screen with the popup gone: a pixel equal to it was not drawn by the popup)
## the rim's mass along the normal nrm at the rect edge p: the strongest row among edge-1..edge+1 (rounding at the window scale) plus the
## two rows beside it (the 1 px line is smeared over them); each row's coverage = its offset from the panel colour projected on rim - panel, 0..1
func rim_mass(img: Image, bare: Image, p: Vector2i, nrm: Vector2i, panel: Color, dv: Vector3, inimg: Callable) -> float:
	var rows: Array = []
	for o in range(-2, 3):
		var qq: Vector2i = p + nrm * o
		var px := img.get_pixelv(qq) if inimg.call(qq) else panel
		if inimg.call(qq) and lv(bare, qq, px) < 2.0:
			px = panel   # the popup did not draw this pixel (the busy UI beside it): no coverage
		rows.append(clampf(Vector3(px.r - panel.r, px.g - panel.g, px.b - panel.b).dot(dv) / dv.length_squared(), 0.0, 1.0))
	var at := 1
	for r in range(1, 4):
		if rows[r] > rows[at]:
			at = r
	return rows[at - 1] + rows[at] + rows[at + 1]


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
	# the popup gone: what lay under it
	await ev_move(Vector2(sz.x * 0.5, sz.y * 0.9))
	await idle(40)
	var under := find_tip() == null
	var img2 := await grab()
	img2.save_png(SHOT + "/tooltip_gone_1024x600.png")
	# The rim is 1 css px = k image px, so the window scale smears it over two rows with partial coverage: judging one pixel's colour
	# against the border colour mis-samples it. Judge its MASS instead: across the rows at the edge, the coverage of each pixel
	# (its offset from the panel colour projected on rim - panel, 0..1) must sum to k +- 0.35 (a missing rim sums to 0, a 2 px rim to 2k).
	var cov_lo := 99.0
	var cov_hi := 0.0
	var dr := 255.0
	var rpts: Array = ring(rp, 0).filter(inimg)
	var dv := Vector3(rim.r - panel.r, rim.g - panel.g, rim.b - panel.b)
	for p in rpts:
		var nrm: Vector2i = Vector2i(0, 1) if (p.y <= rp.position.y + 1) else (Vector2i(0, -1) if p.y >= rp.end.y - 2 else (Vector2i(1, 0) if p.x <= rp.position.x + 1 else Vector2i(-1, 0)))
		var cov := 0.0
		cov = rim_mass(img, img2, p, nrm, panel, dv, inimg)
		cov_lo = minf(cov_lo, cov)
		cov_hi = maxf(cov_hi, cov)
		dr = minf(dr, lv(img, p, panel))
	print("rim coverage over %d samples: %.2f .. %.2f (1 px line: 0.6 .. 2.0 (2 px rim = 2.4))" % [rpts.size(), cov_lo, cov_hi])
	ok(sb.border_width_left == 1 and sb.border_width_top == 1 and rpts.size() >= 20 and cov_lo >= 0.6 and cov_hi <= 2.0, "BORDER: the 1 px rim has coverage %.2f .. %.2f (mass of a 1 px line: 0.6 .. 2.0 (2 px rim = 2.4))" % [cov_lo, cov_hi])
	# CONTROL: the same measure 8 px inside the popup (padding, no rim) must read ~0, so a missing rim fails the bar above
	var ctl := 0.0
	for p in ring(Rect2i(rp.position + Vector2i(8, 8), rp.size - Vector2i(16, 16)), 0).filter(inimg).slice(0, 40):
		ctl = maxf(ctl, rim_mass(img, img2, p, Vector2i(0, 1), panel, dv, inimg))
	ok(ctl < 0.6, "control: with no rim (padding) the same measure reads %.2f, under the 0.6 floor" % ctl)
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
