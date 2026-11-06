extends SceneTree
## L31 WATER SURFACE (11-06): the L5 water render read as crumpled ice next to a photo of a glass of water. This suite measures how smooth the surface reads.
## godot --path . -s tests/water3_test.gd   (needs a window for the render bars: use wtest.sh). W3_ONLY=photo prints the photo numbers and stops.
## Written and committed BEFORE the implementation. No existing bar (liq2, ch8) is edited.
##
## METRIC (fixed before measuring anything): luminance Y = 0.2126 R + 0.7152 G + 0.0722 B of the 8 bit sRGB values / 255 (no linearisation, the same on the
## photo and on our render). BAND-PASS B = G(1.0 px) - G(4.0 px), a difference of Gaussians (kernel radius 3 sigma, clamped edges).
##   ROUGHNESS  Rr = sqrt(mean(B^2)) over the region.
##   STREAKS    Sx = mean((dB/dx)^2) / mean((dB/dy)^2) over the region (central differences). Vertical streaks have a high horizontal gradient and a low
##              vertical one, so a streaky surface reads Sx >> 1; an isotropic one reads about 1.
## REGION: photo  = the clean water band of ref_photo_600.jpg (the reference photo scaled to 600 px high): x 140..389, y 236..269.
##         ours   = the water silhouette (thickness pass covered) eroded by 12 px, so no edge and no glass rim is in it.
## SCENE of the metric: the glass-of-water still of tools/liq2_stills.gd (mug_cut column, 300 steps), 900x600, but in front of a SOFT ISOTROPIC backdrop (a sum of two
##   diagonal sinusoids, period 4 cm, +-0.2 around 0.6) instead of the hard black and cream stripes: sharp stripe edges carry band-pass energy of their own and have
##   a direction, so they would measure the backdrop and not the water. Any band-pass energy or anisotropy here is the water surface refracting a smooth pattern.
## BARS (the photo numbers below were measured by W3_ONLY=photo BEFORE any render was measured; the bars are 1.5 x the photo):
const PHOTO_ROUGH := 0.02790   # MEASURED on the photo (W3_ONLY=photo, 8500 px) before any render of ours was measured
const PHOTO_STREAK := 0.1662   # information: the photo band holds horizontal structure (waterline, reflections), so it reads < 1. NOT used as a bar (see W2)
const BAR_ROUGH_X := 1.5       # bar W1 = 1.5 x 0.02790 = 0.04185
const BAR_STREAK := 1.5        # bar W2, registered before any render was measured: an isotropic surface reads about 1, vertical streaks read >> 1
##   (W1) ROUGHNESS of the new render <= BAR_ROUGH_X x the photo's Rr.   CONTROL: the L5 render (ssf off) of the same scene must exceed it; PLANTED: the new
##        render plus white noise of sigma 0.03 must exceed it.
##   (W2) STREAKS of the new render <= BAR_STREAK (1.5, absolute: the photo's own 0.166 is a waterline band, a bar of 1.5 x that would demand horizontal streaks).  CONTROL: the L5 render must exceed it; PLANTED: the new render plus a random offset per
##        COLUMN (sigma 0.03) must exceed it.
##   (W3) STILL WATER: the smoothing does not erase the water: the low-frequency std (Gaussian 4 px) inside the silhouette is >= 0.5 x the L5 render's (the refracted
##        backdrop pattern is still there), and the silhouette covers >= 0.9 x the L5 area.
##   (W4) VOLUME: WaterSurface.smooth_volume (Taubin + volume restore) keeps the enclosed volume within 1 % on the glass and on the dam break.
##        CONTROL: 60 plain Laplacian steps (lambda only) change the same mesh's volume by more than 1 %.
##   (W5) FRAME COST: ms per frame of the smoothing passes, information only (no bar).
## The L5 bars of liq2 are untouched and keep running in tests/liq2_test.gd.
var fails := 0
const G := 9.81
const SIZE := Vector2i(900, 600)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## ---------------------------------------------------------------- metric
func _lum(img: Image, r: Rect2i) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(r.size.x * r.size.y)
	for y in r.size.y:
		for x in r.size.x:
			var c := img.get_pixel(r.position.x + x, r.position.y + y)
			a[y * r.size.x + x] = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	return a


func _kernel(sigma: float) -> PackedFloat32Array:
	var rad := ceili(3.0 * sigma)
	var k := PackedFloat32Array()
	var s := 0.0
	for i in range(-rad, rad + 1):
		var v := exp(-0.5 * float(i * i) / (sigma * sigma))
		k.append(v)
		s += v
	for i in k.size():
		k[i] /= s
	return k


func _blur(a: PackedFloat32Array, w: int, h: int, sigma: float) -> PackedFloat32Array:
	var k := _kernel(sigma)
	var rad := (k.size() - 1) / 2
	var t := PackedFloat32Array()
	t.resize(w * h)
	for y in h:
		var row := y * w
		for x in w:
			var s := 0.0
			for i in k.size():
				s += k[i] * a[row + clampi(x + i - rad, 0, w - 1)]
			t[row + x] = s
	var o := PackedFloat32Array()
	o.resize(w * h)
	for y in h:
		for x in w:
			var s := 0.0
			for i in k.size():
				s += k[i] * t[clampi(y + i - rad, 0, h - 1) * w + x]
			o[y * w + x] = s
	return o


## {rough, streak, lf, n}: the band-pass statistics of the pixels where mask is set. The image crop is the bounding box of the mask plus 14 px.
func _measure(img: Image, mask: PackedByteArray, mw: int, mh: int) -> Dictionary:
	var x0 := mw
	var y0 := mh
	var x1 := 0
	var y1 := 0
	for y in mh:
		for x in mw:
			if mask[y * mw + x] != 0:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < x0:
		return {"rough": 0.0, "streak": 0.0, "lf": 0.0, "n": 0}
	var m := 14
	var cx0 := maxi(x0 - m, 0)
	var cy0 := maxi(y0 - m, 0)
	var cx1 := mini(x1 + m, mw - 1)
	var cy1 := mini(y1 + m, mh - 1)
	var r := Rect2i(cx0, cy0, cx1 - cx0 + 1, cy1 - cy0 + 1)
	var lum := _lum(img, r)
	var g1 := _blur(lum, r.size.x, r.size.y, 1.0)
	var g2 := _blur(lum, r.size.x, r.size.y, 4.0)
	var w := r.size.x
	var b := PackedFloat32Array()
	b.resize(lum.size())
	for i in lum.size():
		b[i] = g1[i] - g2[i]
	var e2 := 0.0
	var ex := 0.0
	var ey := 0.0
	var n := 0
	var lfs := 0.0
	var lfq := 0.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if mask[y * mw + x] == 0:
				continue
			var i := (y - cy0) * w + (x - cx0)
			e2 += b[i] * b[i]
			var dx := 0.5 * (b[i + 1] - b[i - 1])
			var dy := 0.5 * (b[i + w] - b[i - w])
			ex += dx * dx
			ey += dy * dy
			lfs += g2[i]
			lfq += g2[i] * g2[i]
			n += 1
	var mean := lfs / n
	return {"rough": sqrt(e2 / n), "streak": ex / maxf(ey, 1e-20), "lf": sqrt(maxf(lfq / n - mean * mean, 0.0)), "n": n}


func _erode(cov: PackedByteArray, w: int, h: int, rad: int) -> PackedByteArray:
	var a := cov.duplicate()
	for pass_i in 2:
		var o := PackedByteArray()
		o.resize(w * h)
		var outer := h if pass_i == 0 else w
		var inner := w if pass_i == 0 else h
		for u in outer:
			var run := 0
			var left := PackedInt32Array()
			left.resize(inner)
			for v in inner:
				var idx := (u * w + v) if pass_i == 0 else (v * w + u)
				run = run + 1 if a[idx] != 0 else 0
				left[v] = run
			run = 0
			for v in range(inner - 1, -1, -1):
				var idx := (u * w + v) if pass_i == 0 else (v * w + u)
				run = run + 1 if a[idx] != 0 else 0
				if mini(left[v], run) > rad:
					o[idx] = 1
		a = o
	return a


func _mask_of(thick: Image) -> PackedByteArray:
	var w := thick.get_width()
	var h := thick.get_height()
	var cov := PackedByteArray()
	cov.resize(w * h)
	for y in h:
		for x in w:
			if thick.get_pixel(x, y).g > 0.5:
				cov[y * w + x] = 1
	return _erode(cov, w, h, 12)


func _photo() -> Dictionary:
	var img := Image.load_from_file("res://docs/liquid2/ref_photo_600.jpg")
	var w := img.get_width()
	var h := img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in range(236, 270):
		for x in range(140, 390):
			mask[y * w + x] = 1
	return _measure(img, mask, w, h)


## ---------------------------------------------------------------- scene
func _soft_backdrop(p: Vector3, s: Vector3) -> MeshInstance3D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := TAU * float(x) / n
			var v := TAU * float(y) / n
			var l := 0.6 + 0.2 * sin(u + v) + 0.2 * sin(u - v)
			img.set_pixel(x, y, Color(l, l, l))
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	mi.mesh = b
	mi.position = p
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(25, 25, 25)   # one tile = 4 cm
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.material_override = m
	return mi


## the settled glass of water of tools/liq2_stills.gd
func _glass() -> Dictionary:
	var F2 = Fluid.make()
	F2.set_threads(8)
	var m := FluidScenes.mug_cut(F2, 0.003)
	var flo: float = 1.4 * float(m["h"]) + float(m["floor"])
	var hs := 0.0255
	F2.add_fluid_box(Vector3(m["cx"] - hs, flo + 0.002, m["cz"] - hs), Vector3(m["cx"] + hs, flo + 0.100, m["cz"] + hs), Vector3.ZERO, 7)
	for i in 300:
		F2.advance(0.003)
	var bs := WaterSurface.build(F2, 0.5, 2, 30, m["h"], 1.0, false)
	var mesh := WaterSurface.make_mesh(bs["pos"], bs["idx"], WaterSurface.normals(bs["pos"], bs["idx"]), PackedFloat32Array())
	return {"mesh": mesh, "pos": bs["pos"], "idx": bs["idx"], "mugc": Vector3(m["cx"], flo + 0.035, m["cz"]), "cx": m["cx"], "cz": m["cz"], "volume": bs["volume"]}


func _render_glass(gl: Dictionary, ssf: bool) -> Dictionary:
	var mugc: Vector3 = gl["mugc"]
	var back := _soft_backdrop(Vector3(gl["cx"], mugc.y, float(gl["cz"]) - 0.16), Vector3(0.7, 0.4, 0.01))
	var table := _soft_backdrop(Vector3(gl["cx"], -0.01, gl["cz"]), Vector3(0.7, 0.02, 0.5))
	var gp := {"sky_top": Color(0.45, 0.62, 0.9), "sky_horizon": Color(0.95, 0.96, 1.0), "scatter_col": Color(0.05, 0.30, 0.38), "scatter_k": 14.0, "foam_gain": 0.0}
	return await WaterRender.render(root, {"size": SIZE, "cam_pos": mugc + Vector3(0.0, 0.085, 0.30), "cam_look": mugc, "fov": 22.0, "water": gl["mesh"], "bg": Color(0.88, 0.9, 0.93),
		"props": [back, table], "params": gp, "ssf": ssf})


func _noisy(img: Image, mode: String) -> Image:
	var o := img.duplicate() as Image
	o.convert(Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var colv := PackedFloat32Array()
	for x in o.get_width():
		colv.append(rng.randfn(0.0, 0.03))
	for y in o.get_height():
		for x in o.get_width():
			var d := rng.randfn(0.0, 0.03) if mode == "noise" else colv[x]
			var c := o.get_pixel(x, y)
			o.set_pixel(x, y, Color(clampf(c.r + d, 0, 1), clampf(c.g + d, 0, 1), clampf(c.b + d, 0, 1)))
	return o


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	await process_frame
	var ph := _photo()
	print("      PHOTO region %d px: roughness Rr %.5f, streak ratio Sx %.4f" % [ph["n"], ph["rough"], ph["streak"]])
	if OS.get_environment("W3_ONLY") == "photo":
		quit(0)
		return
	ok(PHOTO_ROUGH > 0.0 and PHOTO_STREAK > 0.0, "the photo numbers are registered (Rr %.5f, Sx %.4f)" % [PHOTO_ROUGH, PHOTO_STREAK])
	ok(absf(ph["rough"] - PHOTO_ROUGH) < 1e-4 and absf(ph["streak"] - PHOTO_STREAK) < 1e-3, "the photo still measures what was registered")
	var bar_r := BAR_ROUGH_X * PHOTO_ROUGH
	var bar_s := BAR_STREAK
	ok(Fluid.native(), "KineFluidNative is registered (build native/ first)")
	var gl := _glass()
	var rn: Dictionary = await _render_glass(gl, true)
	var rl: Dictionary = await _render_glass(gl, false)
	rn["color"].save_png("C:/Temp/claude/l31/w3_new.png")
	rl["color"].save_png("C:/Temp/claude/l31/w3_l5.png")
	var mn := _mask_of(rn["thick"])
	var ml := _mask_of(rl["thick"])
	var an := _measure(rn["color"], mn, SIZE.x, SIZE.y)
	var al := _measure(rl["color"], ml, SIZE.x, SIZE.y)
	var pn := _measure(_noisy(rn["color"], "noise"), mn, SIZE.x, SIZE.y)
	var ps := _measure(_noisy(rn["color"], "col"), mn, SIZE.x, SIZE.y)
	print("      NEW  Rr %.5f Sx %.3f LF %.4f (%d px) | L5 Rr %.5f Sx %.3f LF %.4f (%d px) | planted noise Rr %.5f, planted columns Sx %.3f | bars Rr %.5f Sx %.3f" % [an["rough"], an["streak"], an["lf"], an["n"], al["rough"], al["streak"], al["lf"], al["n"], pn["rough"], ps["streak"], bar_r, bar_s])
	ok(an["rough"] <= bar_r, "(W1) roughness of the new render %.5f <= %.5f (1.5 x photo %.5f)" % [an["rough"], bar_r, PHOTO_ROUGH])
	ok(al["rough"] > bar_r, "(g) CONTROL (W1) the L5 render reads %.5f and fails the roughness bar %.5f" % [al["rough"], bar_r])
	ok(pn["rough"] > bar_r, "(g) CONTROL (W1) planted noise on the new render reads %.5f and fails the bar" % pn["rough"])
	ok(an["streak"] <= bar_s, "(W2) streak ratio of the new render %.3f <= %.3f (registered absolute bar; photo reads %.3f)" % [an["streak"], bar_s, PHOTO_STREAK])
	ok(al["streak"] > bar_s, "(g) CONTROL (W2) the L5 render reads %.3f and fails the streak bar %.3f" % [al["streak"], bar_s])
	ok(ps["streak"] > bar_s, "(g) CONTROL (W2) planted column offsets on the new render read %.3f and fail the bar" % ps["streak"])
	ok(an["lf"] >= 0.5 * al["lf"] and float(an["n"]) >= 0.9 * float(al["n"]), "(W3) the water is still there: LF std %.4f vs L5 %.4f (>= 0.5 x), area %d vs %d px (>= 0.9 x)" % [an["lf"], al["lf"], an["n"], al["n"]])
	# ---- W4 volume
	var F = Fluid.make()
	F.set_threads(8)
	var sc := FluidScenes.dam_break(F, 20)
	F.advance(2.0 * sqrt(sc["a"] / (2.0 * G)))
	var bd := WaterSurface.build(F, 0.5, 4, 4, sc["h"], 1.0, false)
	for item in [["glass", gl["pos"], gl["idx"]], ["dam", bd["pos"], bd["idx"]]]:
		var v0 := absf(WaterSurface.signed_volume(item[1], item[2]))
		var sm: PackedVector3Array = WaterSurface.smooth_volume(item[1], item[2], 40)
		var v1 := absf(WaterSurface.signed_volume(sm, item[2]))
		var lap: PackedVector3Array = WaterSurface.taubin(item[1], item[2], 60, 0.5, 0.0)   # mu = 0: a plain Laplacian, it shrinks
		var v2 := absf(WaterSurface.signed_volume(lap, item[2]))
		print("      W4 %s: volume %.6e -> smooth_volume %.6e (%.3f %%), plain Laplacian %.6e (%.2f %%)" % [item[0], v0, v1, (v1 / v0 - 1.0) * 100.0, v2, (v2 / v0 - 1.0) * 100.0])
		ok(absf(v1 / v0 - 1.0) <= 0.01, "(W4) %s: smooth_volume keeps the volume within 1 %% (%.3f %%)" % [item[0], (v1 / v0 - 1.0) * 100.0])
		ok(absf(v2 / v0 - 1.0) > 0.01, "(g) CONTROL (W4) %s: plain Laplacian smoothing changes the volume by %.2f %% and fails" % [item[0], (v2 / v0 - 1.0) * 100.0])
	# ---- W5 frame cost (information)
	var out := []
	for ssf in [false, true]:
		var t: float = await WaterRender.time_frames(root, {"size": SIZE, "cam_pos": Vector3(gl["cx"], 0.12, float(gl["cz"]) + 0.3), "cam_look": gl["mugc"], "fov": 22.0, "water": gl["mesh"], "ssf": ssf}, 60)
		out.append("%s %.2f ms/frame" % ["smoothing passes on" if ssf else "L5 (off)", t])
	print("      W5 FRAME COST (information, no bar): ", " | ".join(out))
	print("water3: %d fail  (%.0f s)" % [fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if fails > 0 else 0)
