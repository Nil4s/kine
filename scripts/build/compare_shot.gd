class_name CompareShot
extends RefCounted
## G21: render-vs-reference comparison in one place (CH5c, CH13/14/15 each wrote its own side-by-side).
## Images only (no UI): stats() for the numbers, side_by_side() for the picture, write() to save both.


## luminance statistics of an image: {"mean" (0..1), "dark" (fraction below `below`), "w", "h"}
static func stats(img: Image, below := 0.05) -> Dictionary:
	var sum := 0.0
	var dark := 0
	var n := img.get_width() * img.get_height()
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += l
			dark += 1 if l < below else 0
	return {"mean": sum / maxf(float(n), 1.0), "dark": float(dark) / maxf(float(n), 1.0), "w": img.get_width(), "h": img.get_height()}


## both images at the same height, side by side with a dark gap. The left image is the render, the right the reference.
static func side_by_side(a: Image, b: Image, height := 0, gap := 12) -> Image:
	var h := height if height > 0 else maxi(a.get_height(), b.get_height())
	var aw := maxi(1, int(round(a.get_width() * float(h) / a.get_height())))
	var bw := maxi(1, int(round(b.get_width() * float(h) / b.get_height())))
	var ac := a.duplicate() as Image
	var bc := b.duplicate() as Image
	ac.resize(aw, h, Image.INTERPOLATE_LANCZOS)
	bc.resize(bw, h, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(aw + bw + gap, h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.04, 0.04, 0.05))
	out.blit_rect(ac, Rect2i(0, 0, aw, h), Vector2i.ZERO)
	out.blit_rect(bc, Rect2i(0, 0, bw, h), Vector2i(aw + gap, 0))
	return out


## {"render": stats, "reference": stats, "mean_delta", "dark_delta"} (render - reference)
static func compare(render: Image, reference: Image, below := 0.05) -> Dictionary:
	var a := stats(render, below)
	var b := stats(reference, below)
	return {"render": a, "reference": b, "mean_delta": float(a["mean"]) - float(b["mean"]), "dark_delta": float(a["dark"]) - float(b["dark"])}


## write the side-by-side and return its path
static func write(render: Image, reference: Image, path: String, height := 0) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	side_by_side(render, reference, height).save_png(path)
	return path
