extends SceneTree
## bug3 (Nick 11-01): "when you choose metal colours the blocks turn dark for lack of lights". A metallic material shows only reflections and the
## build view had no reflection source (the flat world colour). The fix: a studio sky used for reflections only (Shading.studio_sky; background stays the flat colour).
## godot --path . --position -30000,-30000 -s tests/bug3_test.gd     (real clicks at 1280 x 720: BUILDING card -> Easy Part -> a 4 cm cube -> Colour chips)
## BARS, measured from screenshots of the 4 cm cube (its pixels = the projected box, shrunk 15 %). "before" = the same session with the old environment put back
## (no sky, reflections from the background colour), "after" = the shipped environment:
##  A1 METAL     mean luminance of the cube >= 0.35 after (before is reported)
##  A2 HIGHLIGHT the 95th-percentile luminance of the Metal cube >= 0.75 after
##  A3 NO WASH   Grey, Red, Blue (and Wood): the cube's mean luminance changes by < 15 % vs before
##  A4 FLOOR     the floor/grid around the cube: < 3 % of its pixels differ (any channel by > 0.02) vs before
##  A5 FRAME     the median frame time with the fix is within 2 ms of the old environment
##  A6 BACKGROUND the background is still the flat colour (not drawn as a sky)
## Shots: C:/Temp/claude/bug3/ (compare.png: Metal, Wood, Red, before | after)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/bug3"
const DIRT := "user://bug3_test"
var pu: PartUI
var ep


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
	await idle(3)


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func cube_rec() -> Dictionary:
	var r := Part.make("Bug3 cube")
	r["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [-20.0, -20.0], "b": [20.0, 20.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 40.0, "both": false, "op": "new"}]
	r["seq"] = 2
	return r


## the old environment: no sky, the reflections come from the flat background colour
func env_old() -> void:
	var e: Environment = m.world_env
	e.sky = null
	e.reflected_light_source = Environment.REFLECTION_SOURCE_BG


## the shipped environment: the app's own function decides
func env_new() -> void:
	m.shading.apply_light_source(m)


## the cube's pixels: the box's 8 corners projected, their hull shrunk 15 % about the centre (screen coordinates of the 1280 x 720 canvas)
func cube_hull() -> PackedVector2Array:
	var mi: MeshInstance3D = pu.part_mesh
	var bb: AABB = mi.get_aabb()
	var pts := PackedVector2Array()
	var cen := Vector2.ZERO
	for i in 8:
		var p: Vector2 = m.cam.unproject_position(mi.global_transform * bb.get_endpoint(i))
		pts.append(p)
		cen += p / 8.0
	var hull := Geometry2D.convex_hull(pts)
	var out := PackedVector2Array()
	for p in hull:
		out.append(cen + (p - cen) * 0.85)
	return out


func grab() -> Image:
	await idle(4)
	return root.get_texture().get_image()


func box_of(hull: PackedVector2Array) -> Rect2:
	var r := Rect2(hull[0], Vector2.ZERO)
	for p in hull:
		r = r.expand(p)
	return r


## [mean luminance, 95th percentile, pixel count] of the cube's pixels in img
func cube_stats(img: Image, hull: PackedVector2Array) -> Array:
	var k := float(img.get_width()) / root.get_visible_rect().size.x
	var r := box_of(hull)
	var vals: Array = []
	for y in range(int(r.position.y * k), int(r.end.y * k) + 1):
		for x in range(int(r.position.x * k), int(r.end.x * k) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if Geometry2D.is_point_in_polygon(Vector2(x, y) / k, hull):
				vals.append(lum(img.get_pixel(x, y)))
	vals.sort()
	if vals.is_empty():
		return [0.0, 0.0, 0]
	var s := 0.0
	for v in vals:
		s += v
	return [s / vals.size(), vals[int(vals.size() * 0.95)], vals.size()]


## the floor around the cube: the hull's box grown 130 px, minus the box grown 25 px
func floor_rect(hull: PackedVector2Array) -> Array:
	var r := box_of(hull)
	return [r.grow(130.0), r.grow(25.0)]


func floor_diff(a: Image, b: Image, fr: Array) -> float:
	var k := float(a.get_width()) / root.get_visible_rect().size.x
	var outer: Rect2 = fr[0]
	var inner: Rect2 = fr[1]
	var n := 0
	var d := 0
	for y in range(maxi(int(outer.position.y * k), 0), mini(int(outer.end.y * k), a.get_height())):
		for x in range(maxi(int(outer.position.x * k), 0), mini(int(outer.end.x * k), a.get_width())):
			if inner.has_point(Vector2(x, y) / k):
				continue
			n += 1
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r - pb.r) > 0.02 or absf(pa.g - pb.g) > 0.02 or absf(pa.b - pb.b) > 0.02:
				d += 1
	return float(d) / maxf(n, 1)


func crop(img: Image, hull: PackedVector2Array, cell: int) -> Image:
	var k := float(img.get_width()) / root.get_visible_rect().size.x
	var r := box_of(hull)
	var c := r.get_center() * k
	var half := maxf(r.size.x, r.size.y) * k * 0.9
	var sq := Rect2i(int(c.x - half), int(c.y - half), int(half * 2), int(half * 2)).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var o := img.get_region(sq)
	o.convert(Image.FORMAT_RGBA8)
	o.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
	return o


func median_ms(n: int) -> float:
	var ts: Array = []
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
		var t1 := Time.get_ticks_usec()
		ts.append((t1 - t0) / 1000.0)
		t0 = t1
	ts.sort()
	return ts[n / 2]


func paint(key: String) -> void:
	m.S.part = cube_rec()
	pu.upto = -1
	pu.sync()
	await idle(25)
	await click_ctl(ep.make_btns["colour"])
	var chip: Control = ep.colour_box.find_child("easypart_colour_" + key, true, false)
	await click_ctl(chip)
	await idle(25)


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
	DirAccess.make_dir_recursive_absolute(SHOT)
	var ss: StartScreen = m.start_screen
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		ok(false, "A0 the CAD DLL loads")
		print("bug3: %d fail" % fails)
		quit(1)
		return
	pu = m.bld.part
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var e: Environment = m.world_env
	ok(e.background_mode == Environment.BG_COLOR, "A6 the background is still the flat colour (mode %d)" % e.background_mode)
	ok(e.reflected_light_source == Environment.REFLECTION_SOURCE_SKY and e.sky != null, "A6 the build view reflects a studio sky (source %d, sky %s)" % [e.reflected_light_source, str(e.sky)])
	var rows := {}   # key -> [before stats, after stats, before img, after img, hull]
	var fl := {}
	for key in ["metal", "wood", "red", "grey", "blue"]:
		await paint(key)
		var hull := cube_hull()
		env_old()
		var ib: Image = await grab()
		env_new()
		var ia: Image = await grab()
		rows[key] = [cube_stats(ib, hull), cube_stats(ia, hull), ib, ia, hull]
		fl[key] = floor_diff(ib, ia, floor_rect(hull))
		print("info %-6s before mean %.3f p95 %.3f | after mean %.3f p95 %.3f | px %d | floor diff %.4f" % [key, rows[key][0][0], rows[key][0][1], rows[key][1][0], rows[key][1][1], rows[key][1][2], fl[key]])
		if key == "metal":
			ia.save_png(SHOT + "/metal_after.png")
			ib.save_png(SHOT + "/metal_before.png")
	var mt: Array = rows["metal"]
	ok(mt[1][2] > 500 and mt[1][0] >= 0.35, "A1 Metal: the cube's mean luminance %.3f after (>= 0.35); before %.3f" % [mt[1][0], mt[0][0]])
	ok(mt[1][1] >= 0.75, "A2 Metal: the brightest 5 %% (95th percentile) %.3f after (>= 0.75); before %.3f" % [mt[1][1], mt[0][1]])
	for key in ["grey", "red", "blue", "wood"]:
		var b: float = rows[key][0][0]
		var a: float = rows[key][1][0]
		var ch := absf(a - b) / maxf(b, 0.001)
		ok(b > 0.05 and ch < 0.15, "A3 %s: mean luminance %.3f -> %.3f (%.1f %% change, < 15 %%)" % [key, b, a, ch * 100.0])
	var worst := 0.0
	for key in fl:
		worst = maxf(worst, fl[key])
	ok(worst < 0.03, "A4 the floor/grid around the cube: worst %.2f %% of pixels differ (< 3 %%)" % (worst * 100.0))
	# A5 frame time, with the cube on screen (Metal), the shipped environment against the old one, interleaved twice
	await paint("metal")
	var tn: Array = []
	var to: Array = []
	for rep in 2:
		env_new()
		await idle(10)
		tn.append(await median_ms(90))
		env_old()
		await idle(10)
		to.append(await median_ms(90))
	env_new()
	ok(absf(tn[0] - to[0]) <= 2.0 and absf(tn[1] - to[1]) <= 2.0, "A5 median frame time: fix %s ms, old %s ms (within 2 ms)" % [str(tn), str(to)])
	# compare.png: Metal, Wood, Red; before | after
	var cell := 360
	var sheet := Image.create(cell * 2 + 30, cell * 3 + 40, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	var ri := 0
	for key in ["metal", "wood", "red"]:
		var rr: Array = rows[key]
		sheet.blit_rect(crop(rr[2], rr[4], cell), Rect2i(0, 0, cell, cell), Vector2i(10, 10 + ri * (cell + 10)))
		sheet.blit_rect(crop(rr[3], rr[4], cell), Rect2i(0, 0, cell, cell), Vector2i(20 + cell, 10 + ri * (cell + 10)))
		ri += 1
	sheet.save_png(SHOT + "/compare.png")
	print("bug3: %d fail" % fails)
	quit(1 if fails > 0 else 0)
