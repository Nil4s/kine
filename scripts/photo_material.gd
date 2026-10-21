## MATERIAL FROM A PHOTO (ROADMAP_400 E15): a picture -> a tileable PBR material, all in GDScript on Image
## (no external library, no network). Three maps, each from the one picture:
##   ALBEDO  : the photo DE-LIT, then made TILEABLE.
##     de-lit: the luminance is averaged on a GRID x GRID grid (a large blur), the grid is extended one ring outward by
##       linear extrapolation (so a gradient is removed up to the very edge), and every pixel is multiplied by
##       mean_luminance / blurred_luminance(pixel), the blur read bilinearly. A lighting gradient is slow, so it lives in
##       the blur; the brick / grain is fast, so it stays.  Heuristic: it also flattens features as big as a grid cell.
##     tileable: offset-and-blend. R = w * D + (1 - w) * D(x + W/2, y + H/2) (the picture shifted half a tile, wrapped),
##       with w = 0 on the four edges and 1 beyond BAND of the size from them (smoothstep). On an edge R is the shifted
##       picture, which is continuous across the wrap, so the first and last columns are neighbours in the source.
##   ROUGH   : a documented heuristic, not a measurement. Glossy things (paint, glaze, wet stone) are smooth in the photo;
##       porous / mossy / woven things carry fine contrast. So roughness = lerp(ROUGH_MIN, ROUGH_MAX, clamp(sd / SD_FULL)),
##       sd = the standard deviation of luminance in each 8 x 8 block of the tiled albedo, read bilinearly (wrapped, so
##       the map tiles too).
##   NORMAL  : height = luminance of the tiled albedo; Sobel (wrapped) gives the slope; n = normalize(-dh/dx * k,
##       +dh/dy_up * k, 1) with k = strength; stored as n * 0.5 + 0.5 (OpenGL / Godot convention: red = +x right,
##       green = +y up). A raised region has normals with x < 0 on its left edge.
## Files (the only writes of this class): user://materials/<name>/{albedo,rough,normal}.png and material.tres (a
## StandardMaterial3D whose textures are those PNGs); nothing outside user://materials.
class_name PhotoMaterial
extends RefCounted

const DIR := "user://materials"
const MAX_SIZE := 1024      # a bigger picture is scaled down to this (the time stays bounded)
const GRID := 8             # the large blur: the picture's mean luminance on a GRID x GRID grid
const BAND := 0.22          # the tile blend reaches this fraction of the size in from each edge
const BLOCK := 8            # px: the roughness window
const ROUGH_MIN := 0.35
const ROUGH_MAX := 0.95
const SD_FULL := 0.12       # luminance standard deviation at which the surface counts as fully rough
const STRENGTH := 3.0       # the normal strength's default (the slider runs 0.25 .. 12)

static var _cache := {}     # name -> StandardMaterial3D


## the name a folder may have: letters, digits, - and _ (anything else becomes _)
static func clean_name(s: String) -> String:
	var o := ""
	for ch in s.strip_edges():
		o += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_" else "_"
	return o if o != "" else "photo"


## the working size of a picture: scaled to fit MAX_SIZE, then a multiple of 16 (>= 16)
static func work_size(w: int, h: int) -> Vector2i:
	var s := minf(1.0, float(MAX_SIZE) / float(maxi(w, h)))
	return Vector2i(maxi(16, int(floorf(w * s / 16.0)) * 16), maxi(16, int(floorf(h * s / 16.0)) * 16))


## the three maps of a picture: {"albedo", "rough", "normal"} (Images, RGB8 / L8 / RGB8, all the working size)
static func make(src: Image, strength := STRENGTH) -> Dictionary:
	var img := src.duplicate() as Image
	var ws := work_size(img.get_width(), img.get_height())
	if ws.x != img.get_width() or ws.y != img.get_height():
		var s := minf(1.0, float(MAX_SIZE) / float(maxi(img.get_width(), img.get_height())))
		if s < 1.0:
			img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)
		img = img.get_region(Rect2i(0, 0, ws.x, ws.y))
	img.convert(Image.FORMAT_RGBF)
	var w := ws.x
	var h := ws.y
	var px := img.get_data().to_float32_array()
	# --- P1: the large blur (cell means of luminance)
	var cw := w / GRID
	var ch := h / GRID
	var cell := PackedFloat32Array()
	cell.resize(GRID * GRID)
	var total := 0.0
	for y in h:
		var row := y * w * 3
		var cy := y / ch
		for cx in GRID:
			var s := 0.0
			var i := row + cx * cw * 3
			for k in cw:
				s += 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]
				i += 3
			cell[cy * GRID + cx] += s
	for i in cell.size():
		total += cell[i]
		cell[i] /= float(cw * ch)
	var mean := total / float(w * h)
	# the extended grid: GRID + 2 per side, the outer ring linearly extrapolated (never below a tenth of the mean)
	var g2 := GRID + 2
	var ext := PackedFloat32Array()
	ext.resize(g2 * g2)
	for gy in GRID:
		for gx in GRID:
			ext[(gy + 1) * g2 + gx + 1] = cell[gy * GRID + gx]
	var lo := mean * 0.1
	for gy in range(1, GRID + 1):
		ext[gy * g2] = maxf(lo, 2.0 * ext[gy * g2 + 1] - ext[gy * g2 + 2])
		ext[gy * g2 + g2 - 1] = maxf(lo, 2.0 * ext[gy * g2 + g2 - 2] - ext[gy * g2 + g2 - 3])
	for gx in g2:
		ext[gx] = maxf(lo, 2.0 * ext[g2 + gx] - ext[2 * g2 + gx])
		ext[(g2 - 1) * g2 + gx] = maxf(lo, 2.0 * ext[(g2 - 2) * g2 + gx] - ext[(g2 - 3) * g2 + gx])
	for i in ext.size():   # the gain at each node
		ext[i] = mean / maxf(ext[i], lo)
	# --- P2: de-light (gain interpolated bilinearly between the nodes; node (gx, gy) sits at the middle of cell gx-1, gy-1)
	var d := PackedFloat32Array()
	d.resize(w * h * 3)
	var ld := PackedFloat32Array()
	ld.resize(w * h)
	var rowg := PackedFloat32Array()
	rowg.resize(g2)
	for y in h:
		var fy := (y + 0.5) / float(ch) + 0.5   # in node units
		var y0 := clampi(int(floorf(fy)), 0, g2 - 2)
		var ty := fy - y0
		for gx in g2:
			rowg[gx] = ext[y0 * g2 + gx] * (1.0 - ty) + ext[(y0 + 1) * g2 + gx] * ty
		var i := y * w * 3
		var li := y * w
		for gx in range(0, g2 - 1):
			# x range of the segment between node gx and gx + 1: pixels whose node coordinate is in [gx, gx + 1)
			var xa := 0 if gx == 0 else int(ceilf((gx - 0.5) * cw - 0.5))
			var xb := w if gx == g2 - 2 else int(ceilf((gx + 0.5) * cw - 0.5))
			xa = clampi(xa, 0, w)
			xb = clampi(xb, xa, w)
			if xb <= xa:
				continue
			var a := rowg[gx]
			var b := rowg[gx + 1]
			var t0 := ((xa + 0.5) / float(cw) + 0.5) - gx
			var dt := 1.0 / float(cw)
			var gain := a + (b - a) * t0
			var dg := (b - a) * dt
			for x in range(xa, xb):
				var r := minf(1.0, px[i] * gain)
				var g := minf(1.0, px[i + 1] * gain)
				var bl := minf(1.0, px[i + 2] * gain)
				d[i] = r
				d[i + 1] = g
				d[i + 2] = bl
				ld[li] = 0.2126 * r + 0.7152 * g + 0.0722 * bl
				i += 3
				li += 1
				gain += dg
	# --- P3: tileable (offset and blend), only where the blend weight is below 1
	var rr := d.duplicate()
	var lt := ld.duplicate()
	var bx := maxi(1, int(BAND * w))
	var by := maxi(1, int(BAND * h))
	var hw := w / 2
	var hh := h / 2
	var wxs := PackedFloat32Array()
	wxs.resize(w)
	for x in w:
		var e := float(mini(x, w - 1 - x)) / float(bx)
		wxs[x] = 1.0 if e >= 1.0 else e * e * (3.0 - 2.0 * e)
	for y in h:
		var ey := float(mini(y, h - 1 - y)) / float(by)
		var wy := 1.0 if ey >= 1.0 else ey * ey * (3.0 - 2.0 * ey)
		var sy := (y + hh) % h
		var in_band_y := wy < 1.0
		for x in w:
			var wgt := wxs[x] * wy
			if wgt >= 1.0:
				continue
			var sx := (x + hw) % w
			var i := (y * w + x) * 3
			var j := (sy * w + sx) * 3
			var v := 1.0 - wgt
			var r := d[i] * wgt + d[j] * v
			var g := d[i + 1] * wgt + d[j + 1] * v
			var bl := d[i + 2] * wgt + d[j + 2] * v
			rr[i] = r
			rr[i + 1] = g
			rr[i + 2] = bl
			lt[y * w + x] = 0.2126 * r + 0.7152 * g + 0.0722 * bl
	var alb := Image.create_from_data(w, h, false, Image.FORMAT_RGBF, rr.to_byte_array())
	alb.convert(Image.FORMAT_RGB8)
	var rough := _rough_from(lt, w, h)
	var nrm := _normal_from(lt, w, h, strength)
	return {"albedo": alb, "rough": rough, "normal": nrm}


## the roughness map (L8) from a luminance array: block standard deviation, read bilinearly with wrap
static func _rough_from(lt: PackedFloat32Array, w: int, h: int) -> Image:
	var gw := w / BLOCK
	var gh := h / BLOCK
	var s1 := PackedFloat32Array()
	var s2 := PackedFloat32Array()
	s1.resize(gw * gh)
	s2.resize(gw * gh)
	for y in gh * BLOCK:
		var row := y * w
		var by := (y / BLOCK) * gw
		for bx in gw:
			var a := 0.0
			var q := 0.0
			var i := row + bx * BLOCK
			for k in BLOCK:
				var v := lt[i + k]
				a += v
				q += v * v
			s1[by + bx] += a
			s2[by + bx] += q
	var n := float(BLOCK * BLOCK)
	var pw := gw + 2
	var ph := gh + 2
	var pad := PackedByteArray()
	pad.resize(pw * ph)
	for py in ph:
		var sy := (py - 1 + gh) % gh
		for pxx in pw:
			var sx := (pxx - 1 + gw) % gw
			var m := s1[sy * gw + sx] / n
			var sd := sqrt(maxf(0.0, s2[sy * gw + sx] / n - m * m))
			pad[py * pw + pxx] = int(clampf(lerpf(ROUGH_MIN, ROUGH_MAX, clampf(sd / SD_FULL, 0.0, 1.0)), 0.0, 1.0) * 255.0 + 0.5)
	var im := Image.create_from_data(pw, ph, false, Image.FORMAT_L8, pad)
	im.resize(pw * BLOCK, ph * BLOCK, Image.INTERPOLATE_BILINEAR)
	return im.get_region(Rect2i(BLOCK, BLOCK, w, h))   # w, h are multiples of 16


## the normal map (RGB8) of a luminance array: Sobel with wrap
static func _normal_from(l: PackedFloat32Array, w: int, h: int, strength: float) -> Image:
	var out := PackedFloat32Array()
	out.resize(w * h * 3)
	var xl := PackedInt32Array()
	var xr := PackedInt32Array()
	xl.resize(w)
	xr.resize(w)
	for x in w:
		xl[x] = (x - 1 + w) % w
		xr[x] = (x + 1) % w
	var k := strength * 0.125
	for y in h:
		var ru := ((y - 1 + h) % h) * w
		var rm := y * w
		var rd := ((y + 1) % h) * w
		var o := y * w * 3
		for x in w:
			var a := xl[x]
			var c := xr[x]
			var tl := l[ru + a]
			var tm := l[ru + x]
			var tr := l[ru + c]
			var ml := l[rm + a]
			var mr := l[rm + c]
			var bl := l[rd + a]
			var bm := l[rd + x]
			var br := l[rd + c]
			var dx := (tr + 2.0 * mr + br - tl - 2.0 * ml - bl) * k
			var dy := (bl + 2.0 * bm + br - tl - 2.0 * tm - tr) * k   # image y runs down: this is the slope toward -y_up
			var inv := 0.5 / sqrt(dx * dx + dy * dy + 1.0)
			out[o] = 0.5 - dx * inv
			out[o + 1] = 0.5 + dy * inv   # n.y = -dh/dy_up = +dh/dy_img
			out[o + 2] = 0.5 + inv
			o += 3
	var im := Image.create_from_data(w, h, false, Image.FORMAT_RGBF, out.to_byte_array())
	im.convert(Image.FORMAT_RGB8)
	return im


## the normal map of any picture taken as a height map (its luminance), strength k; wrap at the edges
static func normal_map(src: Image, strength := STRENGTH) -> Image:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBF)
	var w := img.get_width()
	var h := img.get_height()
	var px := img.get_data().to_float32_array()
	var l := PackedFloat32Array()
	l.resize(w * h)
	for i in w * h:
		l[i] = 0.2126 * px[i * 3] + 0.7152 * px[i * 3 + 1] + 0.0722 * px[i * 3 + 2]
	return _normal_from(l, w, h, strength)


## the mean luminance of a rectangle of an image
static func mean_lum(img: Image, r: Rect2i) -> float:
	var s := 0.0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	return s / float(r.size.x * r.size.y)


## the mean absolute difference between the last column and the first (RGB, 0..1)
static func seam_diff(img: Image) -> float:
	var w := img.get_width()
	var s := 0.0
	for y in img.get_height():
		var a := img.get_pixel(w - 1, y)
		var b := img.get_pixel(0, y)
		s += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
	return s / float(img.get_height())


## the material of the maps: the textures, triplanar (the meshes of a prop or a body part may have no UVs), 1 tile per metre
static func build_material(alb: Image, rough: Image, nrm: Image) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(alb)
	m.roughness = 1.0
	m.roughness_texture = ImageTexture.create_from_image(rough)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(nrm)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE
	m.texture_repeat = true
	return m


## writes the folder; returns the folder path ("" when it cannot)
static func save(name: String, maps: Dictionary) -> String:
	var dir := "%s/%s" % [DIR, clean_name(name)]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return ""
	for k in ["albedo", "rough", "normal"]:
		if (maps[k] as Image).save_png("%s/%s.png" % [dir, k]) != OK:
			return ""
	var t := FileAccess.open(dir + "/material.tres", FileAccess.WRITE)
	if t == null:
		return ""
	t.store_string("[gd_resource type=\"StandardMaterial3D\" load_steps=4 format=3]\n\n" +
		"[ext_resource type=\"Texture2D\" path=\"%s/albedo.png\" id=\"1\"]\n[ext_resource type=\"Texture2D\" path=\"%s/rough.png\" id=\"2\"]\n[ext_resource type=\"Texture2D\" path=\"%s/normal.png\" id=\"3\"]\n\n" % [dir, dir, dir] +
		"[resource]\nalbedo_texture = ExtResource(\"1\")\nroughness_texture = ExtResource(\"2\")\nroughness_texture_channel = 0\nnormal_enabled = true\nnormal_texture = ExtResource(\"3\")\nuv1_triplanar = true\ntexture_repeat = true\n")
	t.close()
	_cache.erase(clean_name(name))
	return dir


## the saved material of a name (cached); null when the folder is gone
static func load_material(name: String) -> StandardMaterial3D:
	var n := clean_name(name)
	if _cache.has(n):
		return _cache[n]
	var dir := "%s/%s" % [DIR, n]
	var a := Image.load_from_file(dir + "/albedo.png")
	var r := Image.load_from_file(dir + "/rough.png")
	var nm := Image.load_from_file(dir + "/normal.png")
	if a == null or r == null or nm == null or a.is_empty():
		return null
	_cache[n] = build_material(a, r, nm)
	return _cache[n]
