extends SceneTree
## s217: Metal looks near-black in the Expert Part view. bug3 gave the BUILD view a studio reflection sky; this checks that EVERY view that shows a
## Metal part gets the same reflection source: Expert Part, Easy Part, Nice picture (NiceRender) and STAGE (the part as a prop).
## godot --path . --position -30000,-30000 -s tests/s217_test.gd     (real clicks at 1280 x 720)
## BARS per view (a cube coloured Metal; pixels = its projected box shrunk 15 %):
##  E1 EXPERT mean luminance >= 0.35, E2 p95 >= 0.75   | P1/P2 EASY PART the same | N1/N2 NICE PICTURE the same | T1/T2 STAGE the same
##  W  NO WASH: in Expert, a Grey / Red / Blue part changes < 15 % in mean luminance vs the old environment
##  S  the reflection source is the studio sky in each live view (BUILD page and STAGE page)
## Shots: C:/Temp/claude/s217/
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s217"
const DIRT := "user://s217_test"
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
	var r := Part.make("S217 cube")
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


func rec_of(side: float, preset: String, col: Array) -> Dictionary:
	var h := side * 0.5
	var r := Part.make("S217 cube")
	var look := {"t": "appear", "id": "f3", "name": "Appear1", "body": 0, "preset": preset, "color": col}
	if Part.LOOK_PRESETS.has(preset):
		for k in Part.LOOK_PRESETS[preset]:
			look[k] = Part.LOOK_PRESETS[preset][k]
	r["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [-h, -h], "b": [h, h]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": side, "both": false, "op": "new"}, look]
	r["seq"] = 3
	return r


const STEEL := [0.74, 0.77, 0.82]


## the cube's hull when it is any visible MeshInstance3D that carries a surface material with metallic >= 0.9 (STAGE) or the part mesh
func hull_of(mi: MeshInstance3D, shrink := 0.85) -> PackedVector2Array:
	var bb: AABB = mi.get_aabb()
	var pts := PackedVector2Array()
	var cen := Vector2.ZERO
	for i in 8:
		var p: Vector2 = m.cam.unproject_position(mi.global_transform * bb.get_endpoint(i))
		pts.append(p)
		cen += p / 8.0
	var out := PackedVector2Array()
	for p in Geometry2D.convex_hull(pts):
		out.append(cen + (p - cen) * shrink)
	return out


func stage_prop_mesh() -> MeshInstance3D:
	var best: MeshInstance3D = null
	for n in m.ui_props_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null and (best == null or mi.get_aabb().get_longest_axis_size() > best.get_aabb().get_longest_axis_size()):
			best = mi
	return best


func shot_stats(tag: String, hull: PackedVector2Array) -> Array:
	var img: Image = await grab()
	img.save_png(SHOT + "/" + tag + ".png")
	var st := cube_stats(img, hull)
	print("info %-14s mean %.3f p95 %.3f px %d" % [tag, st[0], st[1], st[2]])
	return st


func bars(prefix: String, view: String, st: Array) -> void:
	ok(st[2] > 500 and st[0] >= 0.35, "%s1 %s Metal: mean luminance %.3f (>= 0.35, %d px)" % [prefix, view, st[0], st[2]])
	ok(st[1] >= 0.75, "%s2 %s Metal: brightest 5 %% (p95) %.3f (>= 0.75)" % [prefix, view, st[1]])


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
		print("s217: %d fail" % fails)
		quit(1)
		return
	pu = m.bld.part
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	var e: Environment = m.world_env
	# ---- EXPERT: the Part workspace (Part button), a Metal cube, no Easy Part panel
	await click_ctl(pu.part_btn)
	print("info part_btn clicked: on=%s" % str(pu.on))
	m.S.part = rec_of(40.0, "Metal", STEEL)
	pu.upto = -1
	pu.sync()
	await idle(30)
	ok(pu.part_mesh.visible and pu.part_mesh.mesh != null, "E0 Expert shows the part mesh")
	ok(e.reflected_light_source == Environment.REFLECTION_SOURCE_SKY and e.sky != null, "S1 Expert reflects a studio sky (source %d, sky %s)" % [e.reflected_light_source, str(e.sky)])
	var hull := hull_of(pu.part_mesh)
	var view_yaw: float = m.yaw
	var view_pitch: float = m.pitch
	print("info expert camera yaw %.1f pitch %.1f" % [view_yaw, view_pitch])
	var ex: Array = await shot_stats("expert_metal", hull)
	bars("E", "Expert", ex)
	# NO WASH in Expert: the same part in Grey / Red / Blue, old environment against the shipped one
	for nm in [["Grey", [0.55, 0.55, 0.55]], ["Red", [0.8, 0.15, 0.12]], ["Blue", [0.15, 0.3, 0.8]]]:
		m.S.part = rec_of(40.0, "Paint", nm[1])
		pu.upto = -1
		pu.sync()
		await idle(25)
		var h2 := hull_of(pu.part_mesh)
		env_old()
		var sb := cube_stats(await grab(), h2)
		env_new()
		var sa := cube_stats(await grab(), h2)
		var ch := absf(sa[0] - sb[0]) / maxf(sb[0], 0.001)
		ok(sb[0] > 0.05 and ch < 0.15, "W %s in Expert: mean luminance %.3f -> %.3f (%.1f %%, < 15 %%)" % [nm[0], sb[0], sa[0], ch * 100.0])
	# ---- EASY PART: the chip, as bug3
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	m.S.part = rec_of(40.0, "Paint", STEEL)
	pu.upto = -1
	pu.sync()
	await idle(25)
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(ep.colour_box.find_child("easypart_colour_metal", true, false))
	await idle(25)
	ok(e.reflected_light_source == Environment.REFLECTION_SOURCE_SKY and e.sky != null, "S2 Easy Part reflects a studio sky")
	var ez: Array = await shot_stats("easy_metal", hull_of(pu.part_mesh))
	bars("P", "Easy Part", ez)
	# ---- NICE PICTURE: NiceRender.draw of the Metal record
	var nimg: Image = await NiceRender.draw(m, rec_of(40.0, "Metal", STEEL))
	var nst := [0.0, 0.0, 0]
	if nimg != null:
		nimg.save_png(SHOT + "/nice_metal.png")
		# the part sits mid-picture: its pixels are the opaque ones inside the central 60 %
		var vals: Array = []
		var W := nimg.get_width()
		var H := nimg.get_height()
		for y in range(int(H * 0.2), int(H * 0.8), 2):
			for x in range(int(W * 0.2), int(W * 0.8), 2):
				var c := nimg.get_pixel(x, y)
				if c.a > 0.95 and lum(c) > 0.02:
					vals.append(lum(c))
		vals.sort()
		if not vals.is_empty():
			var sm := 0.0
			for v in vals:
				sm += v
			nst = [sm / vals.size(), vals[int(vals.size() * 0.95)], vals.size()]
	print("info nice_metal      mean %.3f p95 %.3f px %d" % [nst[0], nst[1], nst[2]])
	bars("N", "Nice picture", nst)
	# ---- STAGE: Save and use in a scene (a 500 mm Metal cube as a prop)
	m.S.part = rec_of(500.0, "Metal", STEEL)
	pu.upto = -1
	pu.sync()
	await idle(10)
	await click_ctl(ep.use_scene_btn)
	await idle(40)
	m.S.props[m.S.props.size() - 1]["xf"] = Transform3D(Basis.IDENTITY, Vector3(4.0, 0.0, 0.0))   # far from the character: nothing stands in front of the cube
	m._props_show()
	await idle(10)
	var pm := stage_prop_mesh()
	print("info prop at %s aabb %s props %d xf %s" % [str(pm.global_position), str(pm.get_aabb()), m.S.props.size(), str(m.S.props[m.S.props.size() - 1]["xf"])])
	ok(pm != null, "T0 STAGE has a Metal prop mesh")
	ok(e.reflected_light_source == Environment.REFLECTION_SOURCE_SKY and e.sky != null, "S3 STAGE reflects a studio sky (source %d, sky %s)" % [e.reflected_light_source, str(e.sky)])
	if pm != null:
		var pts: Array = []
		for i in 8:
			pts.append(pm.global_transform * pm.get_aabb().get_endpoint(i))
		m._turn_to(view_yaw, view_pitch, 2.6, pm.global_transform * pm.get_aabb().get_center() + Vector3(0, 0.45, 0), false)   # the cube fills the middle of the view, no easing
		await idle(20)
		var tst: Array = await shot_stats("stage_metal", hull_of(pm, 0.85))
		bars("T", "STAGE", tst)
	print("s217: %d fail" % fails)
	quit(1 if fails > 0 else 0)
