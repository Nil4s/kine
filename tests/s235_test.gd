extends SceneTree
## S235 TEMPLE LOOK, ROUND 3 (Nick: Kine on par with Blender on colour and light). Measured on the Chinese hall at the reference camera, with the
## reference picture's OWN numbers (tools/kine_workers/hall_compare/kine3/measure3.py run on reference.png; the REF lines print them).
## Round 2 (hall_compare/kine2/final_front.png) read: wall shadow/lit quartile ratio 0.576, column hue -14.6 deg sat 0.38 (pink), paving lum 0.836,
## roof sat 0.48 val 0.86 (pale orange). The reference: 0.332, 5.9 deg sat 0.64, 0.645, sat 0.66 val 0.61. The bars below are NEW; the s231 / s232 bars are not touched.
##   L1  light contrast: the red wall pixels in the wall zone (y 520..655 of 1024): mean of the darkest quarter / mean of the lightest quarter <= 0.45
##   L2  the shadowed wall is not black (darkest-quarter luminance > 0.08) and the lit wall is not blown out (lightest quarter < 0.62)
##   L3  control: with the sun off the same ratio is > 0.6 (the contrast is the SHADOW, not the paint)
##   C1  columns read RED, not pink: mean hue within [-6, 16] deg of the red axis and saturation >= 0.55 (reference 5.9 deg, 0.64)
##   C2  paving is not over-bright: mean luminance of the paving box <= 0.74 (reference 0.645, round 2 0.836) and > 0.45 (not dark)
##   C3  roof tile is a deep terracotta, not orange: hue 10..26 deg, saturation >= 0.52, value <= 0.84 (reference 18 deg, 0.66, 0.61)
##   F   frame_width(): a camera framed to 83 % of the picture width puts the part's box at 83 % +- 1.5 % when projected, by numbers
var OUT := "C:/Users/Nick/tools/kine_workers/hall_compare/kine3/test" + (("_" + OS.get_environment("S235_TAG")) if OS.get_environment("S235_TAG") != "" else "")
const REF_POS := Vector3(0, 4.2, 43.0)   # the round-2 front camera (round 3 re-frames it in the driver, by numbers)
const REF_TGT := Vector3(0, 5.4, 0.0)
const REF_FOV := 45.0
var fails := 0
var m: Node
var pu
var W := 1280
var H := 720


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## the hue of c in degrees on the red axis (-180..180): 0 = pure red, negative = toward magenta/pink, positive = toward orange
func red_axis_deg(h: float) -> float:
	var d := h * 360.0
	return d - 360.0 if d > 180.0 else d


func setup() -> bool:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.size = Vector2i(W, H)
	await idle(4)
	var ss: StartScreen = m.start_screen
	pu = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s235"))
	ss.dirs_override = ["user://s235"]
	if not Part.available():
		print("FAIL no DLL")
		return false
	ss.show_screen()
	await idle(3)
	m.build_choose.auto = true
	var card: Control = ss._cards["building"]
	var p := card.get_global_rect().get_center()
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		await process_frame
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	var pb: Button = pu.part_btn
	var q := pb.get_global_rect().get_center()
	for d in [true, false]:
		var e2 := InputEventMouseButton.new()
		e2.button_index = MOUSE_BUTTON_LEFT
		e2.pressed = d
		e2.position = q
		e2.global_position = q
		root.push_input(e2, true)
		await process_frame
	await idle(4)
	if not pu.on:
		pu.set_on(true)
		await idle(4)
	var fx := OS.get_environment("S235_FIXTURE")
	if fx == "":
		fx = ProjectSettings.globalize_path("res://tests/data/s235_hall.json")   # the round-2 hall (220 bodies) with the default look table (no appear overrides)
	var want := 220
	var rec: Variant
	if true:
		var d2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fx))
		rec = Part.from_file(d2["rec"]) if d2.has("rec") else d2
		if d2.has("nature") and not (d2["nature"] as Array).is_empty():
			if m.S.building.is_empty():
				m.S.building = Building.make("Untitled")
			m.S.building["nature"] = d2["nature"]
		if OS.get_environment("S235_BODIES") != "":
			want = int(OS.get_environment("S235_BODIES"))
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	m.bld.sync()
	var tw := Time.get_ticks_msec()
	while int(pu.res.get("bodies", -1)) != want and Time.get_ticks_msec() - tw < 600000:
		await idle(4)
	await idle(10)
	print("hall bodies ", pu.res.get("bodies", -1), " aabb ", pu.res.get("aabb", null))
	pu.browser.visible = false
	pu.tl.visible = false
	if m.grid_node != null:
		m.grid_node.visible = false
	return int(pu.res.get("bodies", -1)) == want


## ---------------------------------------------------------------- the metrics (the same as measure3.py)
func hsv_of(c: Color) -> Vector3:
	return Vector3(c.h, c.s, c.v)


## {contrast, shadow, lit, n}: the red wall pixels of the wall zone, darkest quarter vs lightest quarter
func wall_contrast(img: Image) -> Dictionary:
	var ls: Array = []
	for y in range(520, 655):
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if (c.h < 0.04 or c.h > 0.95) and c.s > 0.30 and c.v > 0.12:
				ls.append(lum(c))
	ls.sort()
	var n := ls.size()
	if n < 100:
		return {"contrast": 1.0, "shadow": 0.0, "lit": 0.0, "n": n}
	var lo := 0.0
	var hi := 0.0
	for i in n / 4:
		lo += float(ls[i])
		hi += float(ls[n - 1 - i])
	lo /= float(n / 4)
	hi /= float(n / 4)
	return {"contrast": lo / maxf(hi, 0.001), "shadow": lo, "lit": hi, "n": n}


## mean {hue_deg (red axis), sat, val, n} of the red pixels of a box
func red_stats(img: Image, r: Rect2i) -> Dictionary:
	var sx := 0.0
	var cx := 0.0
	var ss := 0.0
	var sv := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			if (c.h < 0.06 or c.h > 0.94) and c.s > 0.3:
				sx += sin(c.h * TAU)
				cx += cos(c.h * TAU)
				ss += c.s
				sv += c.v
				n += 1
	if n == 0:
		return {"hue": 0.0, "sat": 0.0, "val": 0.0, "n": 0}
	var hh := fposmod(atan2(sx, cx) / TAU, 1.0)
	return {"hue": red_axis_deg(hh), "sat": ss / n, "val": sv / n, "n": n}


func mean_lum(img: Image, r: Rect2i) -> float:
	var s := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			s += lum(img.get_pixel(x, y))
			n += 1
	return s / maxf(n, 1)


## roof tile pixels (orange-red, saturated) in the roof zone: {hue_deg, sat, val, n}
func roof_stats(img: Image) -> Dictionary:
	var sx := 0.0
	var cx := 0.0
	var ss := 0.0
	var sv := 0.0
	var n := 0
	for y in range(150, 470):
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.h > 0.01 and c.h < 0.085 and c.s > 0.45 and c.v > 0.3:
				sx += sin(c.h * TAU)
				cx += cos(c.h * TAU)
				ss += c.s
				sv += c.v
				n += 1
	if n == 0:
		return {"hue": 0.0, "sat": 0.0, "val": 0.0, "n": 0}
	return {"hue": fposmod(atan2(sx, cx) / TAU, 1.0) * 360.0, "sat": ss / n, "val": sv / n, "n": n}


func shot(nm: String, sz := 1024) -> Image:
	var r: Dictionary = await TempleLight.final_shot(m, OUT + "/" + nm + ".png", Vector2i(sz, sz))
	if not bool(r.get("ok", false)):
		print("FAIL final shot ", nm, " ", r)
		return null
	return r["image"]


func apply_env_knobs() -> void:
	# S235_SET="time=15.5,sun_gain=1.2,..." : tuning only (the values that were chosen are the defaults in the code)
	var s := OS.get_environment("S235_SET")
	if s == "":
		return
	for kv in s.split(","):
		var p := kv.split("=")
		if p.size() != 2:
			continue
		match p[0]:
			"time": TempleLight.time_h = float(p[1])
			"az": TempleLight.sun_az = float(p[1])
			"exposure": TempleLight.exposure = float(p[1])
			"clouds": TempleLight.clouds = float(p[1])
			"haze": TempleLight.haze = float(p[1])
			"sun_gain": TempleLight.sun_gain = float(p[1])
			"ambient": TempleLight.ambient = float(p[1])
			"contrast": TempleLight.contrast = float(p[1])
			"saturation": TempleLight.saturation = float(p[1])
			"sun_size": TempleLight.sun_size = float(p[1])
			"cam_x": pass
			_: print("unknown knob ", p[0])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if not await setup():
		quit(1)
		return
	apply_env_knobs()
	var cam_pos := REF_POS
	var cam_tgt := REF_TGT
	var cs := OS.get_environment("S235_CAM")   # "x,y,z,tx,ty,tz"
	if cs != "":
		var v := cs.split(",")
		cam_pos = Vector3(float(v[0]), float(v[1]), float(v[2]))
		cam_tgt = Vector3(float(v[3]), float(v[4]), float(v[5]))
	TempleLight.set_camera(m, cam_pos, cam_tgt, REF_FOV, 0.5, 3000.0)
	if TempleLight.on:
		TempleLight.set_live(m, false)
	TempleLight.set_live(m, true)
	await idle(20)
	var im := await shot("final_front")
	if im == null:
		quit(1)
		return
	var wc := wall_contrast(im)
	var col := red_stats(im, Rect2i(int(OS.get_environment("S235_COLX")) if OS.get_environment("S235_COLX") != "" else 224, int(OS.get_environment("S235_COLY")) if OS.get_environment("S235_COLY") != "" else 520, 14, 90))
	var pav := mean_lum(im, Rect2i(300, 800, 420, 200))
	var rf := roof_stats(im)
	print("REF (reference.png): wall contrast 0.332 (shadow 0.128 / lit 0.386); column hue 5.9 deg sat 0.644 val 0.594; paving lum 0.645; roof hue 18.3 deg sat 0.657 val 0.607")
	print("KINE: wall contrast %.3f (shadow %.3f / lit %.3f, %d px); column hue %.1f deg sat %.3f val %.3f (%d px); paving lum %.3f; roof hue %.1f deg sat %.3f val %.3f (%d px)" % [
		wc["contrast"], wc["shadow"], wc["lit"], wc["n"], col["hue"], col["sat"], col["val"], col["n"], pav, rf["hue"], rf["sat"], rf["val"], rf["n"]])
	ok(float(wc["contrast"]) <= 0.45, "L1 light contrast: shadowed wall / lit wall quartile ratio %.3f <= 0.45 (reference 0.332, round 2 0.576)" % wc["contrast"])
	ok(float(wc["shadow"]) > 0.08 and float(wc["lit"]) < 0.62, "L2 shadow not black (%.3f > 0.08), lit wall not blown out (%.3f < 0.62)" % [wc["shadow"], wc["lit"]])
	TempleLight.sun_mult = 0.0
	var im_s := await shot("control_sun_off")
	TempleLight.sun_mult = 1.0
	var wcs := wall_contrast(im_s)
	ok(float(wcs["contrast"]) > 0.6, "L3 control: with the sun off the same measure gives %.3f (> 0.6): the contrast is the shadow, not the paint" % wcs["contrast"])
	ok(int(col["n"]) > 50 and float(col["hue"]) >= -6.0 and float(col["hue"]) <= 16.0 and float(col["sat"]) >= 0.55, "C1 columns red not pink: hue %.1f deg in [-6, 16], saturation %.3f >= 0.55 (reference 5.9 deg, 0.644; round 2 -14.6 deg, 0.384)" % [col["hue"], col["sat"]])
	ok(pav <= 0.74 and pav > 0.45, "C2 paving luminance %.3f in (0.45, 0.74] (reference 0.645, round 2 0.836)" % pav)
	ok(int(rf["n"]) > 300 and float(rf["hue"]) >= 10.0 and float(rf["hue"]) <= 26.0 and float(rf["sat"]) >= 0.52 and float(rf["val"]) <= 0.84, "C3 roof tile deep terracotta: hue %.1f deg in [10, 26], saturation %.3f >= 0.52, value %.3f <= 0.84 (reference 18.3, 0.657, 0.607)" % [rf["hue"], rf["sat"], rf["val"]])
	# F: frame_width by numbers
	var box: AABB = pu.res.get("aabb", AABB())
	var fr: Dictionary = TempleLight.frame_width(m, Rect2(Vector2(-11.8, 0), Vector2(23.6, 14.0)), 0.83, REF_FOV, 4.5, 6.3, 1024.0)
	var pos: Vector3 = fr["pos"]
	var tg: Vector3 = fr["target"]
	var bas := Basis.looking_at((tg - pos).normalized(), Vector3.UP)
	var f := 512.0 / tan(deg_to_rad(REF_FOV) * 0.5)
	var lo := INF
	var hi := -INF
	for sx in [-11.8, 11.8]:
		var q: Vector3 = bas.inverse() * (Vector3(sx, 0, 0) - pos)
		var px := 512.0 + f * q.x / -q.z
		lo = minf(lo, px)
		hi = maxf(hi, px)
	var wp := (hi - lo) / 1024.0
	ok(absf(wp - 0.83) < 0.015, "F frame_width(23.6 m wide box, 83 %%): camera at z %.2f projects it to %.1f %% of the width (want 83 +- 1.5)" % [pos.z, wp * 100.0])
	print("s235: %d fail" % fails)
	quit(1 if fails > 0 else 0)
