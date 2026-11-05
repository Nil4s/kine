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
## AMENDED per Nick 11-04 (CH5c; S1/S1B and S2 re-derived, committed before their first run, no other bar touched):
##   S1 / S1B: "< 15 % dark" had no source and the reference photo itself fails it (ref2: 49.6 % of its lane, 31.9 % of its frame below 0.02).
##     The band now comes from the photo, measured IN THIS TEST (photo_dark()) with the same luminance and the same 0.02 threshold:
##     S1  = dark fraction of the LANE (ground x -1.30..1.02, i.e. between ref2's two lane-edge lines, and nearer than 19.75 m = below photo
##           row 1060), counted in the render's photo frame (columns 400-880, the photo's own field: scripts/wet_street.gd FOV note);
##     S1B = dark fraction of the whole photo frame (render columns 400-880, all rows; the photo: all pixels).
##     BAR: render within +-25 % (relative) of the photo's fraction. +-25 % is this lane's photo tolerance (bar H uses the same).
##     CONTROL: the original look (ws.set_legacy(true)) is outside the S1B band.
##   S2: the 10-90 % edge 0.8 m behind the bollard was ~3 px with a sized light AND with a point light (the engine's shadow-filter floor), so
##     it could not tell them apart. New S2: the scanline is 2.5 m behind the bollard, where the geometric penumbra of a light of radius r is
##     w = 2 r (d_receiver - d_occluder) / d_occluder (horizontal distances from the lamp; 0.11 m for r 0.3 at 13.6 m) = about 13 px on screen.
##     BAR: mean 10-90 % edge width >= 0.5 x w (projected, px). CONTROL: the point light (radius 0) gives < 0.5 x w and fails the bar.
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


## AMENDED per Nick 11-04: S1/S1B measured on the photo itself (same luminance, same 0.02); returns [lane fraction, frame fraction]
const PHOTO := "C:/Users/Nick/tools/kine_workers/out/ch5/ref/ref2.jpg"
const LANE_X0 := -1.30          ## ref2's lane edges (tools/ch5c_photo_estimates.py): wall base line (590,1055)-(330,1260), plinth (770,1055)-(1130,1420)
const LANE_X1 := 1.02
const LANE_FAR := 19.75         ## photo row 1060: 1630 x 1.03 / (1060 - 975) m from the camera
const BAND := 0.25


func photo_dark() -> Array:
	var im := Image.load_from_file(PHOTO)
	var ln := 0
	var ld := 0
	var fn := 0
	var fd := 0
	for y in range(0, im.get_height(), 2):
		var lx := 590.0 + (float(y) - 1055.0) * (330.0 - 590.0) / 205.0
		var rx := 770.0 + (float(y) - 1055.0) * (1130.0 - 770.0) / 365.0
		for x in range(0, im.get_width(), 2):
			var dk := ylum(im.get_pixel(x, y)) < 0.02
			fn += 1
			fd += 1 if dk else 0
			if y > 1060 and float(x) > lx and float(x) < rx:
				ln += 1
				ld += 1 if dk else 0
	print("     S1 photo: lane %d px, %.1f %% dark; frame %.1f %% dark (every 2nd pixel)" % [ln, 100.0 * ld / maxf(ln, 1), 100.0 * fd / maxf(fn, 1)])
	return [float(ld) / maxf(float(ln), 1.0), float(fd) / maxf(float(fn), 1.0)]


## the render, same definitions, in its photo frame (columns 400-880)
func render_dark(cam: Camera3D, img: Image) -> Array:
	var ln := 0
	var ld := 0
	var fn := 0
	var fd := 0
	for y in range(0, img.get_height(), 2):
		for x in range(400, 880, 2):
			var dk := ylum(img.get_pixel(x, y)) < 0.02
			fn += 1
			fd += 1 if dk else 0
			var o := cam.project_ray_origin(Vector2(x, y))
			var d := cam.project_ray_normal(Vector2(x, y))
			if d.y >= -0.001:
				continue
			var g := o + d * (-o.y / d.y)
			if g.x > LANE_X0 and g.x < LANE_X1 and g.z < 1.5 and g.z > 1.5 - LANE_FAR:
				ln += 1
				ld += 1 if dk else 0
	return [float(ld) / maxf(float(ln), 1.0), float(fd) / maxf(float(fn), 1.0), ln]


func in_band(v: float, ref: float) -> bool:
	return v >= ref * (1.0 - BAND) and v <= ref * (1.0 + BAND)


## AMENDED per Nick 11-04: new S2 scanline 2.5 m behind the bollard; returns [left, right, lit, umbra, predicted width px, scan distance]
func probe_width2(cam: Camera3D) -> Array:
	ws.set_probe(0)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	ws.set_probe(-1)
	var bo: Vector3 = ws.bollard_pos()
	var lp := WetStreet.LAMP_POS
	var dirv := Vector2(bo.x - lp.x, bo.z - lp.z)
	var d_occ := dirv.length()
	var s := Vector2(bo.x, bo.z) + dirv.normalized() * 2.5
	var d_rcv := d_occ + 2.5
	var w := 2.0 * WetStreet.BULB_R * (d_rcv - d_occ) / d_occ
	var c := cam.unproject_position(Vector3(s.x, 0.0, s.y))
	var wpx := cam.unproject_position(Vector3(s.x + 0.5 * w, 0.0, s.y)).x - cam.unproject_position(Vector3(s.x - 0.5 * w, 0.0, s.y)).x
	var y := int(c.y)
	var v := PackedFloat32Array()
	for x in range(int(c.x) - 90, int(c.x) + 91):
		v.append(lin(img.get_pixel(x, y)))
	var e := edge_width(v)
	e.append(absf(wpx))
	e.append(1.5 - s.y)
	return e


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
	var poses := [Vector3(-1.2, WetStreet.EYE, 1.5), Vector3(0.0, WetStreet.EYE, 1.5), Vector3(0.7, WetStreet.EYE, 1.5)]   ## AMENDED per Nick 11-04: pose 2 was x = 1.2, over the plinth of the photo's 2.3 m lane (x -1.30..1.02); x 0.7 puts its puddle (x 0.49) on the stones
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
	# S1 (AMENDED per Nick 11-04: the band is the photo's own dark fraction +-25 %)
	var ph := photo_dark()
	var rd := render_dark(cam, img)
	ok(int(rd[2]) > 5000 and in_band(float(rd[0]), float(ph[0])), "S1 DARK: %.1f %% of %d lane pixels below 0.02 vs the photo's lane %.1f %% (band %.1f-%.1f %%)" % [100.0 * float(rd[0]), rd[2], 100.0 * float(ph[0]), 100.0 * float(ph[0]) * (1.0 - BAND), 100.0 * float(ph[0]) * (1.0 + BAND)])
	ws.set_legacy(true)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var old := root.get_texture().get_image()
	old.save_png(OUT + "ch5b_night_legacy.png")
	var s1c := street_dark(cam, old)
	# REVISION after the first run (disclosed in docs/CH5b_FEEDBACK.md): the old look's GROUND was already above 0.02 (0.1-0.6 % dark), the void
	# Nick saw was the rest of the frame (sky, far field), so a ground-only control cannot fail. S1B adds the whole frame with the same 15 % bar.
	var rdc := render_dark(cam, old)
	ok(in_band(float(rd[1]), float(ph[1])), "S1B DARK FRAME: %.1f %% of the photo-frame pixels below 0.02 vs the photo's %.1f %% (band %.1f-%.1f %%)" % [100.0 * float(rd[1]), 100.0 * float(ph[1]), 100.0 * float(ph[1]) * (1.0 - BAND), 100.0 * float(ph[1]) * (1.0 + BAND)])
	ok(not in_band(float(rdc[1]), float(ph[1])), "S1B CONTROL: the original look has %.1f %% dark photo-frame pixels, outside the band (lane %.1f %%, old street %.1f %%)" % [100.0 * float(rdc[1]), 100.0 * float(rdc[0]), 100.0 * s1c[0]])
	ws.set_legacy(false)
	# S2
	# S2 (AMENDED per Nick 11-04: scanline 2.5 m behind the bollard, bar from the geometric penumbra)
	var pw := await probe_width2(cam)
	var wmean: float = (float(pw[0]) + float(pw[1])) * 0.5
	var need: float = 0.5 * float(pw[4])
	ok(float(pw[0]) > 0.0 and float(pw[1]) > 0.0 and wmean >= need, "S2 PENUMBRA: shadow edges %.1f / %.1f px (10-90 %%), mean %.1f px; geometric penumbra %.1f px, need >= %.1f (scanline %.1f m from the camera; lit %.3f, umbra %.3f)" % [pw[0], pw[1], wmean, pw[4], need, pw[5], pw[2], pw[3]])
	ws.set_light_radius(0.0)
	var hw := await probe_width2(cam)
	var hmean: float = (float(hw[0]) + float(hw[1])) * 0.5
	ok(hmean >= 0.0 and hmean < need, "S2 CONTROL: a point light (radius 0) gives %.1f px (< %.1f, so it fails the bar)" % [hmean, need])
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
