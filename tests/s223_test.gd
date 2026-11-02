extends SceneTree
## godot --path . --position 4000,4000 -s tests/s223_test.gd     (LOOKS, Friday plan 223: the material library made in code, material words, a Part wearing materials; needs the CAD DLL)
## Bars (numbers measured from the result; real clicks at 1280 x 720 for the Part; maps, rendered pixels and a re-read record for the rest)
##  1 MAPS      every library material makes an albedo, a roughness and a normal map of 512 x 512 (byte counts), not flat (albedo luminance spread > 4 / 255)
##  2 SAME SEED the same spec twice gives the same bytes in all three maps; another seed gives different bytes (128 px)
##  3 TILEABLE  the seam (right edge to left edge, bottom to top) is no worse than the other pixel pairs: its mean |difference| is within 3 % of the
##              inner pairs' mean, OR within 3 spreads of the inner pairs (a pattern with hard edges, like brick, has pairs that vary a lot).
##              A planted albedo with a brightness ramp (a seam you can see) FAILS the same rule
##  4 WORDS     "dark oak", "orange glazed tile", "brushed steel, rougher", "red lacquer, a bit worn", "white marble with grey veins", "#ff8800",
##              "lighter/darker/warmer" give the expected material and numbers; an unknown word is listed, never guessed; the 140 colour names all read
##  5 GRAIN     a Part cube made "dark oak" (Colour > Materials > words box): the rendered face's luminance spread is above a bar derived from the SAME
##              cube painted flat (the Wood paint chip), and the flat cube FAILS that bar
##  6 TRIPLANAR the grain is the same size in mm on a 10 mm cube and on a 100 mm cube (+-10 %), and equals the scale the spec asked for
##  7 SAVE      the Part record written as JSON and read back keeps all three materials (spec, replayed look, and the maps drawn from it)
##  8 CHIPS     the swatch chips are real buttons with a picture, on the 1280 x 720 screen, not over the Colour chips
## Shots: C:/Temp/claude/s223/part3.png (three materials on a Part), sheet.png (every material on a sphere and a cube), colour_page.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s223"
const DIRT := "user://s223_test"


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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> Image:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var im := root.get_texture().get_image()
	im.save_png("%s/%s.png" % [SHOT, nm])
	return im


func pu() -> PartUI:
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func sd_of(a: PackedByteArray, step: int, off: int) -> float:
	var s := 0.0
	var s2 := 0.0
	var k := 0
	for i in range(off, a.size(), step):
		var v := float(a[i])
		s += v
		s2 += v * v
		k += 1
	var mean := s / maxf(k, 1)
	return sqrt(maxf(s2 / maxf(k, 1) - mean * mean, 0.0))


# ---------------------------------------------------------------- the rendered face

## the largest triangle of the part's top (normal up) that the camera sees, as a screen polygon shrunk 50 % toward its middle: a patch of ONE flat face
func face_polygon(img: Image) -> PackedVector2Array:
	var sz := Vector2(img.get_size()) / Vector2(root.get_visible_rect().size)
	var cam_pos: Vector3 = m.cam.global_position
	var best := PackedVector2Array()
	var best_a := 0.0
	for f in Part.body_faces(m.S.part):
		var arr: PackedVector3Array = f
		for t in range(0, arr.size() - 2, 3):
			var nrm := (arr[t + 1] - arr[t]).cross(arr[t + 2] - arr[t])
			var ar := nrm.length() * 0.5
			if ar <= 0.0:
				continue
			nrm = nrm.normalized()
			if absf(nrm.y) < 0.95 or nrm.dot(cam_pos - arr[t]) <= 0.0:
				continue
			if ar > best_a:
				best_a = ar
				best = PackedVector2Array([scr(arr[t]) * sz, scr(arr[t + 1]) * sz, scr(arr[t + 2]) * sz])
	if best.size() < 3:
		return PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var mid := (best[0] + best[1] + best[2]) / 3.0
	for k in 3:
		best[k] = mid + (best[k] - mid) * 0.5
	return best


## the luminance spread over the pixels inside the polygon (0..1 scale), how many pixels that was, and their mean
func face_std(img: Image, poly: PackedVector2Array) -> Array:
	var lo := poly[0]
	var hi := poly[0]
	for q in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	var s := 0.0
	var s2 := 0.0
	var k := 0
	for y in range(maxi(int(floorf(lo.y)), 0), mini(int(ceilf(hi.y)), img.get_height())):
		for x in range(maxi(int(floorf(lo.x)), 0), mini(int(ceilf(hi.x)), img.get_width())):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				var l := lum(img.get_pixel(x, y))
				s += l
				s2 += l * l
				k += 1
	var mean := s / maxf(k, 1)
	return [sqrt(maxf(s2 / maxf(k, 1) - mean * mean, 0.0)), k, mean]


# ---------------------------------------------------------------- a small world to render materials in

func make_world(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	root.add_child(vp)
	return vp


## the period (px) of a sawtooth grain along one axis of the picture: the mean spacing of the sudden brightening jumps in the row-averaged profile
func jump_period(img: Image, rect: Rect2i, along_x: bool) -> Array:
	var len := rect.size.x if along_x else rect.size.y
	var cross := rect.size.y if along_x else rect.size.x
	var prof := PackedFloat32Array()
	prof.resize(len)
	for i in len:
		var s := 0.0
		for j in cross:
			var p := img.get_pixel(rect.position.x + (i if along_x else j), rect.position.y + (j if along_x else i))
			s += lum(p)
		prof[i] = s / float(cross)
	var d := PackedFloat32Array()
	d.resize(len - 1)
	var mx := 0.0
	for i in len - 1:
		d[i] = prof[i + 1] - prof[i]
		mx = maxf(mx, absf(d[i]))
	var jumps := []
	var i := 0
	while i < len - 1:
		if d[i] > mx * 0.5:
			var sw := 0.0
			var sx := 0.0
			while i < len - 1 and d[i] > mx * 0.35:
				sw += d[i]
				sx += d[i] * float(i)
				i += 1
			jumps.append(sx / sw)
		else:
			i += 1
	var per := -1.0
	if jumps.size() >= 3:
		var gaps := []
		for k in range(1, jumps.size()):
			gaps.append(float(jumps[k]) - float(jumps[k - 1]))
		gaps.sort()
		per = float(gaps[gaps.size() / 2])   # the median gap: a jump the blur hid makes one double gap, not a wrong mean
	return [per, jumps.size(), mx]


# ---------------------------------------------------------------- 1-4 the library and the words (no window needed)

func library_bars() -> void:
	var ids := MaterialMaker.library_ids()
	ok(ids.size() >= 22, "1 the library has %d materials (oak pine plywood steel iron copper brass lacquer tile terracotta granite marble concrete brick plaster grass gravel fabric leather rubber glass plastic)" % ids.size())
	var bad_size := []
	var flat := []
	var nondet := []
	var same_seed := []
	var bad_seam := []
	var worst := {"z": -1e9, "id": "", "ratio": 0.0}
	var t0 := Time.get_ticks_msec()
	for id in ids:
		var sp := MaterialMaker.library_spec(id)
		var a := MaterialMaker.make(sp, 512)
		var al: Image = a["albedo"]
		var ro: Image = a["rough"]
		var no: Image = a["normal"]
		if al.get_width() != 512 or al.get_height() != 512 or al.get_data().size() != 512 * 512 * 3 or ro.get_data().size() != 512 * 512 or no.get_data().size() != 512 * 512 * 3 or no.get_width() != 512:
			bad_size.append(id)
		var sdv := sd_of(al.get_data(), 3, 0) + sd_of(al.get_data(), 3, 1) + sd_of(al.get_data(), 3, 2)
		var sdn := sd_of(no.get_data(), 3, 0) + sd_of(no.get_data(), 3, 1)
		if sdv / 3.0 < 4.0 and id not in ["glass", "plastic", "plastic_matte"]:
			flat.append("%s %.1f" % [id, sdv / 3.0])
		if sdn < 0.3 and id not in ["glass", "plastic", "plastic_matte"]:
			flat.append("%s normal %.1f" % [id, sdn])
		# 2 same seed -> same bytes
		var b := MaterialMaker.make(sp, 512)
		if al.get_data() != (b["albedo"] as Image).get_data() or ro.get_data() != (b["rough"] as Image).get_data() or no.get_data() != (b["normal"] as Image).get_data():
			nondet.append(id)
		var s2 := sp.duplicate()
		s2["seed"] = 2
		var c1 := MaterialMaker.make(sp, 128)
		var c2 := MaterialMaker.make(s2, 128)
		if (c1["albedo"] as Image).get_data() == (c2["albedo"] as Image).get_data():
			same_seed.append(id)
		# 3 tileable
		var pf := MaterialMaker.seam_profile(al)
		for ax in ["cols", "rows"]:
			var st := MaterialMaker.seam_stat(pf[ax])
			var pass_ := float(st["ratio"]) <= 1.03 or float(st["z"]) <= 3.0
			if not pass_:
				bad_seam.append("%s %s ratio %.2f z %.1f" % [id, ax, st["ratio"], st["z"]])
			if float(st["z"]) > float(worst["z"]):
				worst = {"z": st["z"], "id": id + " " + ax, "ratio": st["ratio"]}
		if id == "oak":   # the planted seam: the same picture with a brightness ramp across it
			var pl := al.duplicate() as Image
			for y in 512:
				for x in 512:
					var c := pl.get_pixel(x, y)
					var k := float(x) / 512.0 * 0.3
					pl.set_pixel(x, y, Color(minf(c.r + k, 1.0), minf(c.g + k, 1.0), minf(c.b + k, 1.0)))
			var ps := MaterialMaker.seam_stat(MaterialMaker.seam_profile(pl)["cols"])
			var pl_pass := float(ps["ratio"]) <= 1.03 or float(ps["z"]) <= 3.0
			ok(not pl_pass, "3 the planted seam (a brightness ramp across the tile) FAILS the rule (ratio %.2f, z %.1f)" % [ps["ratio"], ps["z"]])
	print("     (1-3 over %d materials took %d s)" % [ids.size(), (Time.get_ticks_msec() - t0) / 1000])
	ok(bad_size.is_empty(), "1 every material: albedo 512x512 RGB, roughness 512x512, normal 512x512 RGB %s" % str(bad_size))
	ok(flat.is_empty(), "1 no map is flat (the colour materials spread > 4/255, the normals are not all straight up) %s" % str(flat))
	ok(nondet.is_empty(), "2 the same spec twice gives the same bytes in all three maps %s" % str(nondet))
	ok(same_seed.is_empty(), "2 another seed gives different bytes %s" % str(same_seed))
	ok(bad_seam.is_empty(), "3 the seam is no worse than the other pixel pairs, albedo of every material, both axes (worst: %s, ratio %.2f, z %.1f) %s" % [worst["id"], worst["ratio"], worst["z"], str(bad_seam)])


func hexl(h: String) -> float:
	return lum(Color(h))


func words_bars() -> void:
	var names := MaterialWords.colour_names()
	var bad := []
	for nm in names:
		var h := MaterialWords.colour_of(nm)
		if h == "" or not Color.html_is_valid(h):
			bad.append(nm)
	var spot := {"red": "#ff0000", "gray": "#808080", "green": "#008000", "maroon": "#800000", "navy": "#000080", "purple": "#800080", "orange": "#ffa500", "lightgoldenrodyellow": "#fafad2", "yellowgreen": "#9acd32", "white": "#ffffff", "black": "#000000"}
	for k in spot:
		if MaterialWords.colour_of(k) != spot[k]:
			bad.append("%s is %s, not %s" % [k, MaterialWords.colour_of(k), spot[k]])
	ok(names.size() == 140 and bad.is_empty(), "4 the colour table has %d names (140), each reads as a valid colour, and %d known HTML values match %s" % [names.size(), spot.size(), str(bad)])
	ok(MaterialWords.colour_of("grey") == MaterialWords.colour_of("gray") and MaterialWords.colour_of("grey") == "#808080", "4 grey and gray are the same colour")
	var oak := MaterialMaker.library_spec("oak")
	var r := MaterialWords.parse("dark oak")
	var sp: Dictionary = r["spec"]
	ok(r["ok"] and sp["kind"] == "oak" and hexl(sp["color"]) < hexl(oak["color"]) * 0.85 and r["unknown"].is_empty(), "4 'dark oak': oak, luminance %.3f vs plain oak %.3f (< 85 %%), nothing unknown" % [hexl(sp.get("color", "#000000")), hexl(oak["color"])])
	r = MaterialWords.parse("orange glazed tile")
	sp = r["spec"]
	ok(r["ok"] and sp["kind"] == "tile" and sp["color"] == "#ffa500" and float(sp["gloss"]) >= 0.85, "4 'orange glazed tile': tile, colour %s (orange), gloss %.2f" % [sp.get("color"), float(sp.get("gloss", 0))])
	r = MaterialWords.parse("brushed steel, rougher")
	sp = r["spec"]
	var st0 := MaterialMaker.library_spec("steel")
	ok(r["ok"] and sp["kind"] == "steel" and int(sp["brushed"]) == 1 and float(sp["gloss"]) < float(st0["gloss"]) - 0.3, "4 'brushed steel, rougher': steel, brushed %s, gloss %.2f vs %.2f" % [sp.get("brushed"), float(sp.get("gloss", 0)), float(st0["gloss"])])
	var rA := MaterialWords.parse("red lacquer, a bit worn")
	var rB := MaterialWords.parse("red lacquer, very worn")
	var rC := MaterialWords.parse("red lacquer, worn")
	sp = rA["spec"]
	ok(rA["ok"] and sp["kind"] == "lacquer" and sp["color"] == "#ff0000" and float(sp["wear"]) > 0.15 and float(sp["wear"]) < 0.4 and float(rC["spec"]["wear"]) > float(sp["wear"]) and float(rB["spec"]["wear"]) > float(rC["spec"]["wear"]),
		"4 'red lacquer, a bit worn': lacquer, red %s, wear %.2f < worn %.2f < very worn %.2f" % [sp.get("color"), float(sp.get("wear", 0)), float(rC["spec"]["wear"]), float(rB["spec"]["wear"])])
	r = MaterialWords.parse("white marble with grey veins")
	sp = r["spec"]
	ok(r["ok"] and sp["kind"] == "marble" and sp["color"] == "#ffffff" and sp["vein"] == "#808080", "4 'white marble with grey veins': marble %s, veins %s" % [sp.get("color"), sp.get("vein")])
	r = MaterialWords.parse("#ff8800")
	ok(r["ok"] and r["spec"]["color"] == "#ff8800", "4 '#ff8800': a material of that colour (%s, %s)" % [r["spec"].get("kind"), r["spec"].get("color")])
	var base: Dictionary = MaterialWords.parse("red lacquer")["spec"]
	var lt := MaterialWords.parse("lighter", base)
	var dk := MaterialWords.parse("darker", base)
	var wm := MaterialWords.parse("warmer", MaterialWords.parse("steel")["spec"])
	var wc := MaterialWords.colour_of("blue")
	ok(lt["ok"] and dk["ok"] and hexl(lt["spec"]["color"]) > hexl(base["color"]) and hexl(dk["spec"]["color"]) < hexl(base["color"]) and lt["spec"]["kind"] == "lacquer",
		"4 'lighter' / 'darker' edit the material they are given: %.3f < %.3f < %.3f" % [hexl(dk["spec"]["color"]), hexl(base["color"]), hexl(lt["spec"]["color"])])
	var sb := Color(MaterialMaker.library_spec("steel")["color"])
	var sw := Color(wm["spec"]["color"])
	ok(wm["ok"] and sw.r > sb.r and sw.b < sb.b, "4 'warmer': more red, less blue (%s -> %s)" % [sb.to_html(false), sw.to_html(false)])
	r = MaterialWords.parse("dark oak sparkly wobbly")
	ok(r["ok"] and r["spec"]["kind"] == "oak" and r["unknown"] == ["sparkly", "wobbly"], "4 unknown words are listed, not guessed: %s, and the oak still came out" % str(r["unknown"]))
	r = MaterialWords.parse("zorgle blarp")
	ok(not r["ok"] and r["spec"].is_empty() and r["unknown"] == ["zorgle", "blarp"], "4 a line with no material and no colour is not a material (unknown %s)" % str(r["unknown"]))
	r = MaterialWords.parse("dark red")
	ok(r["ok"] and r["spec"]["color"] == "#8b0000", "4 'dark red' reads as the table's darkred (%s)" % r["spec"].get("color"))


# ---------------------------------------------------------------- 6 triplanar

func cube_grain_mm(cube_mm: float) -> Array:
	var spec := {"kind": "oak", "warp": 0.0, "scale": 16.0, "seed": 3}
	var vp := make_world(Vector2i(800, 800))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cube_mm * 0.001
	cam.position = Vector3(0, 1, 0)
	vp.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * cube_mm * 0.001
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = MaterialMaker.standard(spec)
	vp.add_child(mi)
	await idle(6)
	var img := vp.get_texture().get_image()
	vp.queue_free()
	var rect := Rect2i(80, 80, 640, 640)
	var px := jump_period(img, rect, true)
	var py := jump_period(img, rect, false)
	var use: Array = px if float(px[2]) >= float(py[2]) else py
	var per_mm := -1.0
	if float(use[0]) > 0.0:
		per_mm = float(use[0]) * cube_mm / 800.0
	return [per_mm, use[1], img]


# ---------------------------------------------------------------- the sheet of all materials

func sheet() -> void:
	var ids := MaterialMaker.library_ids()
	var cols := 6
	var vp := make_world(Vector2i(1560, 1170))
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0.0, 0.0, 3.5)
	cam.fov = 38.0
	for k in ids.size():
		var cx := (float(k % cols) - (cols - 1) * 0.5) * 0.45
		var cy := (1.5 - float(k / cols)) * 0.5
		var mat := MaterialMaker.standard(MaterialMaker.library_spec(ids[k]))
		var sp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 64
		sm.rings = 32
		sp.mesh = sm
		sp.material_override = mat
		sp.position = Vector3(cx - 0.07, cy + 0.03, 0)
		vp.add_child(sp)
		var cu := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.15
		cu.mesh = bm
		cu.material_override = mat
		cu.position = Vector3(cx + 0.11, cy - 0.05, 0.05)
		cu.rotation_degrees = Vector3(25, 35, 0)
		vp.add_child(cu)
	await idle(10)
	DirAccess.make_dir_recursive_absolute(SHOT)
	vp.get_texture().get_image().save_png(SHOT + "/sheet.png")
	vp.queue_free()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	library_bars()
	words_bars()
	await sheet()
	# 6 TRIPLANAR
	var small: Array = await cube_grain_mm(10.0)
	var big: Array = await cube_grain_mm(100.0)
	(small[2] as Image).save_png(SHOT + "/cube10.png")
	(big[2] as Image).save_png(SHOT + "/cube100.png")
	var nominal := 16.0 / 9.0
	var s_mm: float = small[0]
	var b_mm: float = big[0]
	ok(s_mm > 0.0 and b_mm > 0.0 and absf(s_mm / b_mm - 1.0) <= 0.10, "6 grain on a 10 mm cube %.3f mm per stripe (%d jumps), on a 100 mm cube %.3f mm (%d jumps): equal within 10 %% (ratio %.3f)" % [s_mm, small[1], b_mm, big[1], s_mm / maxf(b_mm, 1e-6)])
	ok(b_mm > 0.0 and absf(b_mm / nominal - 1.0) <= 0.10, "6 and it is the size the spec asked for: 16 mm tile / 9 rings = %.3f mm; measured %.3f mm on the 100 mm cube" % [nominal, b_mm])

	# the Part: three bodies, three materials
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the Part cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "0 BUILDING card, one click -> Easy Part on")
	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var ep = pu().ep
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(scr(Vector3(-0.3, 0.0, -0.1)), scr(Vector3(-0.1, 0.0, 0.1)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	ok(int(pu().res.get("bodies", 0)) == 1, "5 one cube on the floor (bodies %d)" % int(pu().res.get("bodies", 0)))
	await click_ctl(m.find_child("easypart_view_top", true, false))
	await click_ctl(m.find_child("easypart_view_fit", true, false))
	await idle(20)
	# the flat reference: the same cube painted with the flat Wood paint chip
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(m.find_child("easypart_colour_wood", true, false))
	await idle(8)
	var img_flat := await shot("cube_flat")
	var poly := face_polygon(img_flat)
	var fl := face_std(img_flat, poly)
	# the cube made dark oak: Colour > Materials > the words box
	var mat_chip := m.find_child("easypart_colour_materials", true, false) as Button
	await click_ctl(mat_chip)
	await idle(4)
	var words := m.find_child("easypart_mat_words", true, false) as LineEdit
	var ub0: int = m.undo.size()
	words.text = "dark oak"
	words.text_submitted.emit("dark oak")
	await idle(30)
	var img_oak := await shot("cube_oak")
	var oa := face_std(img_oak, poly)
	var look: Dictionary = Part.look_at(pu().res.get("body_looks", []), 0)
	var bar := maxf(float(fl[0]) * 2.5, float(fl[0]) + 0.01)
	ok(String((look.get("mat", {}) as Dictionary).get("kind", "")) == "oak" and m.undo.size() == ub0 + 1, "5 dark oak words: the Part's look is the oak spec, ONE undo step (%d -> %d)" % [ub0, m.undo.size()])
	ok(int(fl[1]) > 800 and int(oa[1]) > 800, "5 the measured face has %d / %d pixels (not a sliver)" % [fl[1], oa[1]])
	ok(float(oa[0]) > bar, "5 the dark oak face's luminance spread %.4f is above the bar %.4f (2.5 x the flat cube's %.4f, at least +0.01)" % [oa[0], bar, fl[0]])
	ok(not (float(fl[0]) > bar), "5 the planted flat cube (Wood paint) FAILS that bar: spread %.4f <= %.4f" % [fl[0], bar])
	# the second and third piece: swatch chips, real clicks
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(scr(Vector3(0.7, 0.0, -0.06)), scr(Vector3(0.82, 0.0, 0.06)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await click_ctl(ep.make_btns["colour"])
	if not (m.find_child("easypart_materials", true, false) as Control).visible:
		await click_ctl(m.find_child("easypart_colour_materials", true, false))
	var vpr := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var chip_m := m.find_child("easypart_mat_marble", true, false) as Button
	var inside := chip_m != null and vpr.encloses(chip_m.get_global_rect()) and chip_m.is_visible_in_tree()
	await shot("colour_page")
	# chips
	var missing := []
	var no_pic := []
	for id in MaterialMaker.library_ids():
		var b := m.find_child("easypart_mat_" + String(id), true, false) as Button
		if b == null or not b.is_visible_in_tree() or not vpr.encloses(b.get_global_rect()):
			missing.append(id)
		elif b.icon == null:
			no_pic.append(id)
	ok(inside and missing.is_empty() and no_pic.is_empty(), "8 every swatch chip is a button with a picture, on the 1280 x 720 screen %s %s" % [str(missing), str(no_pic)])
	var cb := (m.find_child("easypart_colour", true, false) as Control).get_global_rect()
	var mb := (m.find_child("easypart_materials", true, false) as Control).get_global_rect()
	var ub1: int = m.undo.size()
	await click_ctl(chip_m)
	var bodies2 := int(pu().res.get("bodies", 0))
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(scr(Vector3(-0.7, 0.0, -0.06)), scr(Vector3(-0.58, 0.0, 0.06)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await click_ctl(ep.make_btns["colour"])
	if not (m.find_child("easypart_materials", true, false) as Control).visible:
		await click_ctl(m.find_child("easypart_colour_materials", true, false))
	var ub2: int = m.undo.size()
	await click_ctl(m.find_child("easypart_mat_tile", true, false))
	await click_ctl(m.find_child("easypart_view_fit", true, false))
	await idle(20)
	await shot("part3")
	var ls: Array = pu().res.get("body_looks", [])
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) == "appear":
			print("     appear body %s preset %s mat %s" % [f.get("body"), f.get("preset"), (f.get("mat", {}) as Dictionary).get("kind", "-")])
	var kinds := []
	for i in ls.size():
		kinds.append(String((Part.look_at(ls, i).get("mat", {}) as Dictionary).get("kind", "")))
	ok(int(pu().res.get("bodies", 0)) == 3 and kinds.has("oak") and kinds.has("marble") and kinds.has("tile") and kinds.size() == 3, "5 three bodies, three materials, each by its own click: %s (bodies %d, one undo step each %d, %d)" % [str(kinds), int(pu().res.get("bodies", 0)), m.undo.size() - ub1 - 1 - 1, m.undo.size() - ub2])
	ok(not cb.intersects(mb), "8 the Materials page does not cover the Colour chips (%s vs %s)" % [str(cb), str(mb)])
	# 7 SAVE: the record as JSON text, read back, replayed
	var rec: Dictionary = m.S.part
	var txt := JSON.stringify(rec)
	var back: Variant = JSON.parse_string(txt)
	var res2 := Part.replay(back as Dictionary)
	var l2: Array = res2.get("body_looks", [])
	var kinds2 := []
	var same_maps := true
	for i in l2.size():
		var mt: Dictionary = Part.look_at(l2, i).get("mat", {})
		kinds2.append(String(mt.get("kind", "")))
		var orig: Dictionary = Part.look_at(ls, i).get("mat", {})
		var ma := MaterialMaker.make(orig, 64)
		var mb2 := MaterialMaker.make(mt, 64)
		if (ma["albedo"] as Image).get_data() != (mb2["albedo"] as Image).get_data() or (ma["normal"] as Image).get_data() != (mb2["normal"] as Image).get_data():
			same_maps = false
	var oak_back: Dictionary = Part.look_at(l2, 0).get("mat", {})
	var oak_want: Dictionary = MaterialWords.parse("dark oak")["spec"]
	ok(kinds2 == kinds and same_maps and JSON.stringify(MaterialMaker.norm(Part.look_at(l2, kinds.find("oak")).get("mat", {})), "", true) == JSON.stringify(oak_want, "", true), "7 saved as JSON and replayed: %s, the oak spec is the one 'dark oak' made, the maps drawn from it are the same bytes (%s)" % [str(kinds2), str(same_maps)])
	print("s223: %d fail" % fails)
	quit(1 if fails > 0 else 0)
