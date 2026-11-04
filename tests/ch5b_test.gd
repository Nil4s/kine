extends "res://tests/ch5_test.gd"
## CH5b: the wet street at night without the black void (Nick 11-04: "street lights cool, shadows killing the vibe").
## godot --path . -s tests/ch5b_test.gd     (wtest.sh runs it off-screen). Extends tests/ch5_test.gd to reuse its estimators.
## BARS (written and committed BEFORE any number was read):
##   S1 DARK      1280x720, pose x = 0: over the pixels whose camera ray lands on the street (the baked ground patch, z from -13.6 to the camera),
##                the fraction with luminance (0.2126 R + 0.7152 G + 0.0722 B of the 8-bit sRGB values) below 0.02 is under 15 %.
##                CONTROL: the original look (one lamp, near-zero ambient, ws.set_legacy(true)) is >= 15 %.
##   S2 PENUMBRA the shadow of a 0.9 m bollard, cast by lamp 0 on the ground 4.5-5.5 m from the camera, has an edge whose 10 %-90 % transition
##                is wider than 3 px (mean of its two edges, along one scanline of the shadow term, probe render of the real shader).
##                CONTROL: the same scene with a point light (light radius 0, hard shadow) is <= 3 px.
##   S3 LAMPS     at least 3 lamp bulbs or pools: the render has >= 4 lamps lighting the street (ws.lamp_count()).
##   D, F         the parked bars, wording unchanged (tests/ch5_test.gd _look_bars): D streak aspect vs the photo's 2.32 within 30 %,
##                F wet stone-top luminance on the lamp-to-camera line >= 3x dry.
##   A, B         tests/ch5_test.gd (run separately, must keep passing).
const OUT := "C:/Users/Nick/tools/kine_workers/out/ch5b/"


func street_dark(cam: Camera3D, img: Image) -> Array:
	var n := 0
	var dark := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var o := cam.project_ray_origin(Vector2(x, y))
			var d := cam.project_ray_normal(Vector2(x, y))
			if d.y >= -0.001:
				continue
			var g := o + d * (-o.y / d.y)
			if g.x < WetStreet.X0 or g.x > WetStreet.X0 + WetStreet.SPAN_X or g.z < WetStreet.Z0 or g.z > WetStreet.Z0 + WetStreet.SPAN_Z:
				continue
			n += 1
			if ylum(img.get_pixel(x, y)) < 0.02:
				dark += 1
	return [float(dark) / maxf(float(n), 1.0), n]


func frame_dark(img: Image) -> float:
	var n := 0
	var dark := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			n += 1
			if ylum(img.get_pixel(x, y)) < 0.02:
				dark += 1
	return float(dark) / float(n)


func lin(c: Color) -> float:
	return pow(c.r, 2.2)


## 10-90 % transition width (px) of both edges of a dip in a scanline
func edge_width(v: PackedFloat32Array) -> Array:
	var n := v.size()
	var lit := 0.0
	for i in 4:
		lit += v[i] + v[n - 1 - i]
	lit /= 8.0
	var um := 1e9
	var imin := 0
	for i in n:
		if v[i] < um:
			um = v[i]
			imin = i
	if um > 0.5 * lit:
		return [-1.0, -1.0, lit, um]
	var t1 := lit - 0.1 * (lit - um)
	var t9 := lit - 0.9 * (lit - um)
	var res := []
	for side in 2:
		var a := -1e9
		var b := -1e9
		var rng := range(0, imin + 1) if side == 0 else range(n - 1, imin, -1)
		var prev := lit
		var prev_i := 0 if side == 0 else n - 1
		for i in rng:
			if a < -1e8 and v[i] < t1:
				a = float(i) - (prev - t1) / maxf(prev - v[i], 1e-9) * float(i - prev_i)
			if b < -1e8 and v[i] < t9:
				b = float(i) - (prev - t9) / maxf(prev - v[i], 1e-9) * float(i - prev_i)
			prev = v[i]
			prev_i = i
		res.append(absf(b - a) if a > -1e8 and b > -1e8 else -1.0)
	return [res[0], res[1], lit, um]


func probe_width(cam: Camera3D) -> Array:
	ws.set_probe(0)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	ws.set_probe(-1)
	var bo: Vector3 = ws.bollard_pos()
	var scan_z := bo.z + 0.8
	var c := cam.unproject_position(Vector3(bo.x, 0.0, scan_z))
	var y := int(c.y)
	var v := PackedFloat32Array()
	for x in range(int(c.x) - 55, int(c.x) + 56):
		v.append(lin(img.get_pixel(x, y)))
	var w := edge_width(v)
	w.append(1.5 - scan_z)
	return w


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var poses := [Vector3(-1.2, WetStreet.EYE, 1.5), Vector3(0.0, WetStreet.EYE, 1.5), Vector3(1.2, WetStreet.EYE, 1.5)]
	ws = WetStreet.new()
	root.add_child(ws)
	ws.build(poses)
	var cam := Camera3D.new()
	cam.fov = WetStreet.FOV
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 80.0
	root.add_child(cam)
	cam.global_position = Vector3(0.0, WetStreet.EYE, 1.5)
	cam.rotation_degrees = Vector3(WetStreet.PITCH_DEG, 0, 0)
	cam.current = true
	for f in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_texture().get_image()
	img.save_png(OUT + "ch5b_night.png")
	# S1
	var s1 := street_dark(cam, img)
	ok(s1[0] < 0.15 and s1[1] > 20000, "S1 DARK: %.1f %% of %d street pixels are below luminance 0.02 (need < 15 %%)" % [100.0 * s1[0], s1[1]])
	ws.set_legacy(true)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var old := root.get_texture().get_image()
	old.save_png(OUT + "ch5b_night_legacy.png")
	var s1c := street_dark(cam, old)
	# REVISION after the first run (disclosed in docs/CH5b_FEEDBACK.md): the old look's GROUND was already above 0.02 (0.1-0.6 % dark), the void
	# Nick saw was the rest of the frame (sky, far field), so a ground-only control cannot fail. S1B adds the whole frame with the same 15 % bar.
	var fd := frame_dark(img)
	var fdc := frame_dark(old)
	ok(fd < 0.15, "S1B DARK FRAME: %.1f %% of ALL frame pixels (sky, walls, street) are below luminance 0.02 (need < 15 %%)" % (100.0 * fd))
	ok(fdc >= 0.15, "S1B CONTROL: the original look has %.1f %% dark frame pixels (>= 15 %%, so the bar can fail); its ground alone %.1f %%" % [100.0 * fdc, 100.0 * s1c[0]])
	ws.set_legacy(false)
	# S2
	var pw := await probe_width(cam)
	var wmean: float = (float(pw[0]) + float(pw[1])) * 0.5
	ok(float(pw[0]) > 0.0 and float(pw[1]) > 0.0 and wmean > 3.0 and float(pw[4]) >= 4.5 and float(pw[4]) <= 5.5, "S2 PENUMBRA: shadow edges %.1f / %.1f px wide (10-90 %%), mean %.1f px, scanline %.1f m from the camera (need > 3 px at 4.5-5.5 m; lit %.3f, umbra %.3f)" % [pw[0], pw[1], wmean, pw[4], pw[2], pw[3]])
	ws.set_light_radius(0.0)
	var hw := await probe_width(cam)
	var hmean: float = (float(hw[0]) + float(hw[1])) * 0.5
	ok(hmean <= 3.0 and hmean >= 0.0, "S2 CONTROL: a point light (radius 0) gives a hard edge, %.1f px (<= 3)" % hmean)
	ws.set_light_radius(WetStreet.BULB_R)
	ok(ws.lamp_count() >= 4, "S3 LAMPS: %d lamps light the street (need >= 4)" % ws.lamp_count())
	await _look_bars(cam)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var wetimg := root.get_texture().get_image()
	wetimg.save_png(OUT + "ch5b_night_final.png")
	print("ch5b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
