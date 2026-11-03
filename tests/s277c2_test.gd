extends SceneTree
## godot --path . -s tests/s277c2_test.gd   (round 2 readers, committed with their control numbers BEFORE any new render)
##   277c BODY   pixels with max channel > 20/255 (not background) and saturation (max-min)/max < 0.25 (grey metal, no RGB spill), mean Rec709 luminance 0..255.
##               Same reader on both. Bar: kine_lit4 frame 0 within 10 pct of Blender's (kine_lit2/sbs_0.png left half) = 96.2 -> 86.6..105.8.
##               Controls (measured before the render): lit3 48.5 and lit2 50.1 fail. Also printed: the s277b bar cloud (chroma 40 rows above the bar, <= 0.078).
##   262d EDGE   per frame, count pixels with max channel > 40 in the top 5 pct rows plus the bottom 5 pct rows (36 each of 720). Bar: 0 of the 348 frames of kine_explode3
##               over 50. CONTROL: kine_explode2 (2c32f1a2) has 348 of 348 over 50 (max 50637).
const K := "C:/Users/Nick/tools/kine_workers/hall_compare/gpu/"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func body(img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			if mx * 255.0 > 20.0 and (mx - mn) / mx < 0.25:
				s += 255.0 * (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
				n += 1
	return s / maxf(n, 1)


func edge(img: Image) -> int:
	var k := int(img.get_height() * 0.05)
	var n := 0
	for y in list_rows(img.get_height(), k):
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) * 255.0 > 40.0:
				n += 1
	return n


func list_rows(h: int, k: int) -> Array:
	var r: Array = []
	for y in k:
		r.append(y)
		r.append(h - 1 - y)
	return r


func _init() -> void:
	var sbs := Image.load_from_file(K + "kine_lit2/sbs_0.png")
	var bl := body(sbs.get_region(Rect2i(0, 0, 1920, 1080)))
	var l3 := body(Image.load_from_file(K + "kine_lit3/frames/0000.png"))
	print("277c blender %.1f lit3 %.1f band %.1f..%.1f" % [bl, l3, bl * 0.9, bl * 1.1])
	ok(l3 < bl * 0.9, "277c CONTROL lit3 %.1f fails" % l3)
	var l4 := Image.load_from_file(K + "kine_lit4/frames/0000.png")
	ok(l4 != null, "277c kine_lit4 frame 0 exists")
	if l4 != null:
		var v := body(l4)
		ok(v >= bl * 0.9 and v <= bl * 1.1, "277c BODY lit4 %.1f within %.1f..%.1f" % [v, bl * 0.9, bl * 1.1])
	var ctl := 0
	for f in 348:
		var im := Image.load_from_file(K + "kine_explode2/frames/%04d.png" % f)
		if im != null and edge(im) > 50:
			ctl += 1
	ok(ctl > 0, "262d CONTROL kine_explode2: %d of 348 frames over 50 edge pixels" % ctl)
	var bad := 0
	var have := 0
	for f in 348:
		var im := Image.load_from_file(K + "kine_explode3/frames/%04d.png" % f)
		if im == null:
			continue
		have += 1
		if edge(im) > 50:
			bad += 1
	ok(have == 348 and bad == 0, "262d EDGE kine_explode3: %d frames present, %d over 50" % [have, bad])
	print("s277c2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
