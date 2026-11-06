## godot --path . -s tests/render2_test.gd     (L51 RENDER2; gaps of render1: native accumulate + a real denoise)
## BARS WRITTEN AND COMMITTED BEFORE THE IMPLEMENTATION. Numbers are from the lane brief.
##   a NATIVE == GDSCRIPT: FinalHQ.accumulate (native) vs FinalHQ.accumulate_gd on 4 random 96x64 images: max abs diff of the RGBF result <= 1/255.
##   b SPEED: FinalHQ.accumulate of 16 images of 1920x1080 (RGB8) takes <= 150 ms (best of 3; the time is printed).
##   c NOISE: a flat patch (0.5, gaussian noise std 0.06 per channel); FinalHQ.denoise with the clean feature buffer as guide lowers the patch std >= 2x.
##   d EDGE: a hard vertical edge 0.1 | 0.9 with noise; the denoised 10-90% width (row-averaged profile) <= 1.2 x the clean reference's width.
##   e PLANTED: (e1) the identity "denoise" fails c's check; (e2) an unguided filter (guide sigma huge, colour sigma huge = plain blur) fails d's check;
##     (e3) a native result nudged by 3/255 fails a's check.
##   f GDSCRIPT FALLBACK: denoise_gd on the same flat patch also passes c; the preset wires it (PRESET["denoise"] true).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func rgbf(w: int, h: int, f: Callable) -> Image:
	var a := PackedFloat32Array()
	a.resize(w * h * 3)
	for y in h:
		for x in w:
			var c: Color = f.call(x, y)
			var i := (y * w + x) * 3
			a[i] = c.r
			a[i + 1] = c.g
			a[i + 2] = c.b
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBF, a.to_byte_array())


func chan_std(img: Image, r: Rect2i) -> float:
	var s := 0.0
	var s2 := 0.0
	var n := 0.0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var v := img.get_pixel(x, y).g
			s += v
			s2 += v * v
			n += 1.0
	var mu := s / n
	return sqrt(maxf(s2 / n - mu * mu, 0.0))


func edge_w(img: Image, y0: int, y1: int, x0: int, x1: int) -> float:
	var prof := []
	for x in range(x0, x1):
		var t := 0.0
		for y in range(y0, y1):
			t += img.get_pixel(x, y).g
		prof.append(t / float(y1 - y0))
	var lo: float = prof[0]
	var hi: float = prof[prof.size() - 1]
	var c10 := -1.0
	var c90 := -1.0
	for i in range(prof.size() - 1):
		var a: float = (prof[i] - lo) / maxf(hi - lo, 1e-6)
		var b: float = (prof[i + 1] - lo) / maxf(hi - lo, 1e-6)
		if c10 < 0.0 and a < 0.1 and b >= 0.1:
			c10 = float(i) + (0.1 - a) / maxf(b - a, 1e-9)
		if c90 < 0.0 and a < 0.9 and b >= 0.9:
			c90 = float(i) + (0.9 - a) / maxf(b - a, 1e-9)
	return (c90 - c10) if c10 >= 0.0 and c90 >= 0.0 else 99.0


func max_diff(a: Image, b: Image) -> float:
	var da := a.get_data().to_float32_array()
	var db := b.get_data().to_float32_array()
	var m := 0.0
	for i in da.size():
		m = maxf(m, absf(da[i] - db[i]))
	return m


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	# ---- a
	var imgs := []
	for k in 4:
		var d := PackedByteArray()
		d.resize(96 * 64 * 3)
		for i in d.size():
			d[i] = rng.randi() & 255
		imgs.append(Image.create_from_data(96, 64, false, Image.FORMAT_RGB8, d))
	var nat: Image = FinalHQ.accumulate(imgs)
	var gd: Image = FinalHQ.accumulate_gd(imgs)
	var md := max_diff(nat, gd)
	ok(FinalHQ.native_available(), "a0 the native class is loaded (not the fallback)")
	ok(md <= 1.0 / 255.0, "a native accumulate == GDScript: max abs diff %.6f (<= %.6f)" % [md, 1.0 / 255.0])
	var nudged := nat.get_data().to_float32_array()
	for i in nudged.size():
		nudged[i] += 3.0 / 255.0
	var nimg := Image.create_from_data(96, 64, false, Image.FORMAT_RGBF, nudged.to_byte_array())
	ok(not (max_diff(nimg, gd) <= 1.0 / 255.0), "e3 PLANTED: result nudged by 3/255 is refused by the a check (diff %.4f)" % max_diff(nimg, gd))
	# ---- b
	var big := []
	for k in 16:
		var d := PackedByteArray()
		d.resize(1920 * 1080 * 3)
		for i in range(0, d.size(), 7):
			d[i] = rng.randi() & 255
		big.append(Image.create_from_data(1920, 1080, false, Image.FORMAT_RGB8, d))
	var best := 1e9
	for rep in 3:
		var t0 := Time.get_ticks_usec()
		var o: Image = FinalHQ.accumulate(big)
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
		if o.get_width() != 1920:
			best = 1e9
	print("     1920x1080 x 16 accumulate: best of 3 = %.1f ms" % best)
	ok(best <= 150.0, "b 1920x1080 x 16 accumulate %.1f ms (<= 150)" % best)
	big.clear()
	# ---- c
	var clean_flat := rgbf(96, 96, func(_x, _y): return Color(0.5, 0.5, 0.5))
	var noisy_flat := rgbf(96, 96, func(_x, _y): return Color(0.5 + rng.randfn(0, 0.06), 0.5 + rng.randfn(0, 0.06), 0.5 + rng.randfn(0, 0.06)))
	var patch := Rect2i(24, 24, 48, 48)
	var s0 := chan_std(noisy_flat, patch)
	var den: Image = FinalHQ.denoise(noisy_flat, clean_flat)
	var s1 := chan_std(den, patch)
	ok(s0 / maxf(s1, 1e-9) >= 2.0, "c denoise lowers flat-patch std %.4f -> %.4f (x%.1f, >= 2)" % [s0, s1, s0 / maxf(s1, 1e-9)])
	ok(not (s0 / maxf(chan_std(noisy_flat, patch), 1e-9) >= 2.0), "e1 PLANTED: identity filter is refused by the c check (x1.0)")
	var den_gd: Image = FinalHQ.denoise_gd(noisy_flat, clean_flat)
	var sg := chan_std(den_gd, patch)
	ok(s0 / maxf(sg, 1e-9) >= 2.0, "f GDScript fallback denoise std %.4f (x%.1f)" % [sg, s0 / maxf(sg, 1e-9)])
	# ---- d
	var step := func(x, _y): return Color(0.1, 0.1, 0.1) if x < 64 else (Color(0.5, 0.5, 0.5) if x == 64 else Color(0.9, 0.9, 0.9))
	var clean_edge := rgbf(128, 96, step)
	var noisy_edge := rgbf(128, 96, func(x, y):
		var c: Color = step.call(x, y)
		return Color(c.r + rng.randfn(0, 0.06), c.g + rng.randfn(0, 0.06), c.b + rng.randfn(0, 0.06)))
	var w_clean := edge_w(clean_edge, 8, 88, 44, 84)
	var dn: Image = FinalHQ.denoise(noisy_edge, clean_edge)
	var w_dn := edge_w(dn, 8, 88, 44, 84)
	ok(w_dn <= 1.2 * w_clean, "d denoised edge width %.3f px vs clean %.3f px (x%.2f, <= 1.2)" % [w_dn, w_clean, w_dn / w_clean])
	var blur: Image = FinalHQ.denoise(noisy_edge, clean_edge, 3, 1e6, 1e6)
	var w_bl := edge_w(blur, 8, 88, 44, 84)
	ok(not (w_bl <= 1.2 * w_clean), "e2 PLANTED: unguided plain blur edge %.3f px is refused by the d check (x%.2f)" % [w_bl, w_bl / w_clean])
	var dn_gd: Image = FinalHQ.denoise_gd(noisy_edge, clean_edge)
	var w_gd := edge_w(dn_gd, 8, 88, 44, 84)
	ok(w_gd <= 1.2 * w_clean, "f GDScript fallback edge width %.3f px (x%.2f)" % [w_gd, w_gd / w_clean])
	ok(bool(FinalHQ.PRESET.get("denoise", false)), "f the final_hq PRESET has denoise on")
	print("\nrender2: %s" % ("ALL OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
