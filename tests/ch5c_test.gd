extends "res://tests/ch5_test.gd"
## CH5c: the wet cobblestone street on the engine's PBR (scripts/wet_street.gd). New bars only; the reused bars run unchanged in
## tests/ch5_test.gd (A, B, C, D, E, F, G) and tests/ch5b_test.gd (S1, S2, S3).
## godot --path . -s tests/ch5c_test.gd     (wtest.sh ch5c). WRITTEN AND COMMITTED BEFORE ITS FIRST RUN.
## BAR F STAMPING NOTE (not an edit of bar F): bar F samples "stone tops" at the centres of a REGULAR 110 mm grid (cx, cz from PITCH, row parity),
## a layout that stopped existing when CH5b made the setts irregular, and takes a 3x3 pixel mean there. Many samples land in joints or on a stone's flank,
## and a wet sheen lives on the domes' highlights, so the mean of arbitrary points measures the diffuse term (equal wet and dry). F is kept unchanged
## and reported; F2 below measures the thing the spec's words name.
## F2 SHEEN  Pose x = 0. The stones whose ground footprint lies within 0.5 m of the lamp-base-to-camera line, at 0.1..0.7 of the way from the camera,
##           not on asphalt and not in a bowl (n >= 25 real setts, each with >= 20 pixels on screen). For each stone, in EACH image separately, take the
##           brightest 10 % of that stone's own pixels (luminance) and average them: the stone's highlight. The statistic is the mean over stones of that
##           highlight. Wet / dry >= 3. The pixel choice follows the same rule in both images (it is never taken from one image and reused in the other).
##           CONTROL (planted): the wet scene with SSR and the reflection probe switched off (ws.set_reflections(false)) must give a ratio < 3.
## H VEIL   (the pale asphalt) PRE-RUN CHANGE of an unrun bar (lead 11-04): the first draft limit "< 0.10 dry" had no source. Now it comes from ref2.jpg:
##           the only flat, non-sett ground in the photo is the wet flat patch at the left edge of the lane (hand-masked once, assets/ch5c/ref2_flat_patch_mask.png,
##           polygon in photo px (458,1246)..(594,1286), 5047 px). Its mean sRGB luminance (0.2126 R + 0.7152 G + 0.0722 B of the 8-bit values) is 0.302.
##           The photo patch is WET and shows the sky haze, so the comparison is wet render to wet photo. BAR: in the WET render, pose x = 0, the asphalt strip
##           (ground x 1.2..2.6, z -7..-1, outside the bowls) has mean sRGB luminance within +-25 % of 0.302, i.e. in [0.227, 0.378].
##           CONTROL: the parked CH5b shader's wet value 0.1207 (commit 67a12af7 diagnosis) is outside the band and fails. The dry value is printed, not barred.
const OUT := "C:/Users/Nick/tools/kine_workers/out/ch5c/"


func hl_mean(v: Array) -> float:
	var s := v.duplicate()
	s.sort()
	var k := maxi(int(ceil(0.1 * float(s.size()))), 1)
	var acc := 0.0
	for i in k:
		acc += float(s[s.size() - 1 - i])
	return acc / float(k)


func render(cam: Camera3D) -> Image:
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func sheen(img: Image, groups: Dictionary) -> Array:
	var tot := 0.0
	var n := 0
	for key in groups.keys():
		var px: Array = groups[key]
		if px.size() < 20:
			continue
		var v := []
		for q in px:
			v.append(ylum(img.get_pixelv(q)))
		tot += hl_mean(v)
		n += 1
	return [tot / maxf(float(n), 1.0), n]


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
	DirAccess.make_dir_recursive_absolute(OUT)
	var wet := await render(cam)
	wet.save_png(OUT + "ch5c_night.png")
	ws.set_reflections(false)
	var ctrl := await render(cam)
	ctrl.save_png(OUT + "ch5c_night_noreflect.png")
	ws.set_reflections(true)
	ws.set_dry(true)
	var dry := await render(cam)
	dry.save_png(OUT + "ch5c_night_dry.png")
	ws.set_dry(false)
	# stone footprints on the lamp-to-camera line
	var lamp_xz := Vector2(WetStreet.LAMP_POS.x, WetStreet.LAMP_POS.z)
	var groups := {}
	for y in range(300, 720):
		for x in range(250, 1030):
			var o := cam.project_ray_origin(Vector2(x, y))
			var d := cam.project_ray_normal(Vector2(x, y))
			if d.y >= -0.001:
				continue
			var g := o + d * (-o.y / d.y)
			var t := (g.z - 1.5) / (lamp_xz.y - 1.5)
			if t < 0.1 or t > 0.7 or g.x < WetStreet.X0 or ws.is_asphalt(g.x, g.z):
				continue
			if absf(g.x - lerpf(0.0, lamp_xz.x, t)) > 0.5 or ws.bowl_field(g.x, g.z) < -0.003:
				continue
			var c := ws.cobble_cell(g.x, g.z)
			if int(c[0]) == 0:
				continue
			var key := int(c[0]) * 1000003 + int(c[1])
			if not groups.has(key):
				groups[key] = []
			groups[key].append(Vector2i(x, y))
	var sw := sheen(wet, groups)
	var sd := sheen(dry, groups)
	var sc := sheen(ctrl, groups)
	var ratio: float = float(sw[0]) / maxf(float(sd[0]), 1e-6)
	var cratio: float = float(sc[0]) / maxf(float(sd[0]), 1e-6)
	print("     F2: %d stones, mean top-10%% highlight wet %.4f, dry %.4f, no-SSR/no-probe %.4f" % [sw[1], sw[0], sd[0], sc[0]])
	ok(int(sw[1]) >= 25 and ratio >= 3.0, "F2 SHEEN: wet stone highlights are %.1fx the same stones' dry highlights (need >= 3, n=%d stones)" % [ratio, sw[1]])
	ok(not (cratio >= 3.0), "F2 CONTROL: the wet scene with SSR and the reflection probe off gives %.1fx and fails the bar" % cratio)
	# H VEIL
	var hv := 0.0
	var hd := 0.0
	var hn := 0
	for y in range(0, 720, 2):
		for x in range(0, 1280, 2):
			var o2 := cam.project_ray_origin(Vector2(x, y))
			var d2 := cam.project_ray_normal(Vector2(x, y))
			if d2.y >= -0.001:
				continue
			var g2 := o2 + d2 * (-o2.y / d2.y)
			if g2.x < 1.2 or g2.x > 2.6 or g2.z < -7.0 or g2.z > -1.0 or ws.bowl_field(g2.x, g2.z) < -0.01:
				continue
			hv += ylum(wet.get_pixel(x, y))
			hd += ylum(dry.get_pixel(x, y))
			hn += 1
	var hm := hv / maxf(float(hn), 1.0)
	print("     H: dry asphalt mean luminance %.4f (printed, not barred)" % (hd / maxf(float(hn), 1.0)))
	ok(hn > 500 and hm >= 0.227 and hm <= 0.378, "H VEIL: wet asphalt strip mean luminance %.4f vs the photo's flat patch 0.302 (band 0.227-0.378), n=%d" % [hm, hn])
	ok(not (0.1207 >= 0.227 and 0.1207 <= 0.378), "H CONTROL: the parked wet value 0.1207 is outside the band and fails")
	print("ch5c: %d fail" % fails)
	quit(1 if fails > 0 else 0)
