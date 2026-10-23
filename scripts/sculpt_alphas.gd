class_name SculptAlphas
extends RefCounted
## SCULPT ALPHAS (ROADMAP_400 C08): greyscale pictures a brush stamps through. 0 = no push, 1 = the brush's full push; a
## brush's falloff is multiplied by the alpha read in the brush's tangent frame (scripts/sculpt_alpha_stroke.gd).
## THE PICTURES are computed here (SIZE x SIZE, float, no files, no downloaded art), each from a fixed seed so every run
## makes the same ones. The image covers the stamp's square: pixel (px, py) is the frame point
##   x = (px + 0.5) / SIZE * 2 - 1 (along the frame's tangent t)   y = (py + 0.5) / SIZE * 2 - 1 (along b = t x n),
## so seen from the normal's side the picture lies the right way round (x right, y down). Read bilinearly (sample);
## outside the square it is 0.
##   pores    skin pores: ~170 small soft bumps scattered at random (Ctrl inverts the brush: pits), on fine noise
##   scales   fish scales on a hex lattice (rows offset half a cell): each a dome, highest toward its free edge (+y), a
##            groove on the cell border. Directional: turned 90 deg it is a different picture
##   weave    plain-weave fabric: warp and weft threads, over / under in a checker
##   crater   a raised ring (r 0.6) round a low floor, fading out by the edge
##   rivet    a round dome head (r 0.42) on a thin plate ring
##   disc     a linear gradient disc, 1 at the centre to 0 at the rim (a cone stamp)
##   noise    value noise, 4 octaves (rock, skin breakup)
## USER PNGs: load_png(path) takes any image the engine reads, crops it to its centred square, scales it to SIZE and keeps
##   luminance x alpha; it joins the list under its file name.

const SIZE := 256
const NAMES := ["pores", "scales", "weave", "crater", "rivet", "disc", "noise"]
const SCALE_CELL := 0.25   # scales: the hex lattice spacing in frame units (the square is 2 wide: 8 across)
const WEAVE_P := 0.25      # weave: the thread period in frame units

static var _img := {}      # name -> Image (FORMAT_RF)
static var _dat := {}      # name -> PackedFloat32Array (row-major, SIZE x SIZE)
static var _user: Array = []   # names of the loaded PNGs, in load order
static var _thumbs := {}


## every shipped alpha made now (the sculpt page calls it at startup); returns the time taken in ms
static func make_all() -> float:
	var t0 := Time.get_ticks_usec()
	for nm in NAMES:
		image(nm)
	return (Time.get_ticks_usec() - t0) / 1000.0


static func names() -> Array:
	return NAMES + _user


static func has(nm: String) -> bool:
	return NAMES.has(nm) or _user.has(nm)


## the alpha's picture (FORMAT_RF), made on first ask; null when there is no such alpha
static func image(nm: String) -> Image:
	if _img.has(nm):
		return _img[nm]
	if not NAMES.has(nm):
		return null
	var d := _make(nm)
	_put(nm, d)
	return _img[nm]


static func data(nm: String) -> PackedFloat32Array:
	if image(nm) == null:
		return PackedFloat32Array()
	return _dat[nm]


static func _put(nm: String, d: PackedFloat32Array) -> void:
	_dat[nm] = d
	_img[nm] = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, d.to_byte_array())
	_thumbs.erase(nm)


## the frame point (x, y) of a pixel centre
static func frame_of(px: float, py: float) -> Vector2:
	return Vector2((px + 0.5) / SIZE * 2.0 - 1.0, (py + 0.5) / SIZE * 2.0 - 1.0)


## bilinear read of an alpha's data at frame point (x, y) in [-1, 1]^2; 0 outside the square
static func sample(d: PackedFloat32Array, x: float, y: float) -> float:
	if x < -1.0 or x > 1.0 or y < -1.0 or y > 1.0 or d.is_empty():
		return 0.0
	var u := (x + 1.0) * 0.5 * SIZE - 0.5
	var v := (y + 1.0) * 0.5 * SIZE - 0.5
	var i0 := clampi(floori(u), 0, SIZE - 1)
	var j0 := clampi(floori(v), 0, SIZE - 1)
	var i1 := mini(i0 + 1, SIZE - 1)
	var j1 := mini(j0 + 1, SIZE - 1)
	var fu := clampf(u - floorf(u), 0.0, 1.0) if u >= 0.0 and u <= SIZE - 1 else 0.0
	var fv := clampf(v - floorf(v), 0.0, 1.0) if v >= 0.0 and v <= SIZE - 1 else 0.0
	var a := lerpf(d[j0 * SIZE + i0], d[j0 * SIZE + i1], fu)
	var b := lerpf(d[j1 * SIZE + i0], d[j1 * SIZE + i1], fu)
	return lerpf(a, b, fv)


## a small greyscale picture for the strip
static func thumb(nm: String, px := 28) -> Texture2D:
	var k := "%s@%d" % [nm, px]
	if _thumbs.has(k):
		return _thumbs[k]
	var im := image(nm)
	if im == null:
		return null
	var c := im.duplicate() as Image
	c.convert(Image.FORMAT_L8)
	c.resize(px, px, Image.INTERPOLATE_BILINEAR)
	_thumbs[k] = ImageTexture.create_from_image(c)
	return _thumbs[k]


## a user picture as an alpha: its name ("" when it cannot be read)
static func load_png(path: String) -> String:
	var im := Image.load_from_file(path)
	if im == null or im.is_empty():
		return ""
	im.convert(Image.FORMAT_RGBA8)
	var s := mini(im.get_width(), im.get_height())
	im = im.get_region(Rect2i((im.get_width() - s) / 2, (im.get_height() - s) / 2, s, s))
	if s != SIZE:
		im.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	var d := PackedFloat32Array()
	d.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var c := im.get_pixel(x, y)
			d[y * SIZE + x] = clampf((0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * c.a, 0.0, 1.0)
	var nm := path.get_file().get_basename()
	if nm == "" or NAMES.has(nm):
		nm = "user " + nm
	_put(nm, d)
	if not _user.has(nm):
		_user.append(nm)
	return nm


# ---------------------------------------------------------------- the procedural pictures

static func _make(nm: String) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(SIZE * SIZE)
	match nm:
		"pores":
			_pores(d)
			return d
		"noise":
			var nz := _noise(11, 4, 6.0)
			for i in d.size():
				d[i] = nz[i]
			return d
	for py in SIZE:
		for px in SIZE:
			var q := frame_of(px, py)
			d[py * SIZE + px] = clampf(_at(nm, q), 0.0, 1.0)
	return d


static func _smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _at(nm: String, q: Vector2) -> float:
	var r := q.length()
	match nm:
		"scales":
			return _scale(q)
		"weave":
			return _weave(q)
		"crater":
			var ring := exp(-pow((r - 0.6) / 0.14, 2.0))
			var floor_ := 0.18 * (1.0 - _smoothstep(0.0, 0.6, r))
			return (ring + floor_) * (1.0 - _smoothstep(0.85, 1.0, r))
		"rivet":
			if r < 0.42:
				return sqrt(1.0 - pow(r / 0.42, 2.0))
			return 0.15 * (1.0 - _smoothstep(0.55, 0.62, r))
		"disc":
			return 1.0 - r
	return 0.0


## fish scales: the nearest centre of a hex lattice (rows SCALE_CELL * sqrt(3)/2 apart, odd rows offset half a cell)
static func _scale(q: Vector2) -> float:
	var s := SCALE_CELL
	var rh := s * sqrt(3.0) * 0.5
	var j0 := roundi(q.y / rh)
	var best := Vector2(INF, INF)
	for j in range(j0 - 1, j0 + 2):
		var ox := s * 0.5 if posmod(j, 2) == 1 else 0.0
		var i0 := roundi((q.x - ox) / s)
		for i in range(i0 - 1, i0 + 2):
			var c := Vector2(i * s + ox, j * rh)
			if (q - c).length_squared() < best.length_squared():
				best = q - c
	# hex distance: 1 on the cell border (the borders face the 6 neighbours, at 0, 60, 120 deg)
	var hd := 0.0
	for a in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
		hd = maxf(hd, absf(best.dot(Vector2(cos(a), sin(a)))) / (s * 0.5))
	var dome := 1.0 - pow(minf(hd, 1.0), 3.0)
	var lip := clampf(0.5 + best.y / s, 0.0, 1.0)   # rises toward the scale's free edge (+y)
	return dome * (0.35 + 0.65 * lip)


## plain weave: warp threads run along y, weft along x; in cell (i, j) the warp is on top when i + j is even
static func _weave(q: Vector2) -> float:
	var u := (q.x + 1.0) / WEAVE_P
	var v := (q.y + 1.0) / WEAVE_P
	var fu := u - floorf(u) - 0.5
	var fv := v - floorf(v) - 0.5
	var warp := sqrt(maxf(0.0, 1.0 - pow(fu / 0.42, 2.0)))   # the thread's round cross-section
	var weft := sqrt(maxf(0.0, 1.0 - pow(fv / 0.42, 2.0)))
	var warp_top := posmod(floori(u) + floori(v), 2) == 0
	var a := (0.45 + 0.55 * warp) * warp if warp_top else 0.45 * warp
	var b := 0.45 * weft if warp_top else (0.45 + 0.55 * weft) * weft
	return maxf(a, b)


static func _pores(d: PackedFloat32Array) -> void:
	var nz := _noise(5, 3, 24.0)
	for i in d.size():
		d[i] = 0.12 * nz[i]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 170:
		var c := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var rr := rng.randf_range(0.025, 0.05)
		var depth := rng.randf_range(0.65, 1.0)
		var lo := Vector2i(((c - Vector2(rr, rr)) + Vector2.ONE) * 0.5 * SIZE).clamp(Vector2i.ZERO, Vector2i(SIZE - 1, SIZE - 1))
		var hi := Vector2i(((c + Vector2(rr, rr)) + Vector2.ONE) * 0.5 * SIZE).clamp(Vector2i.ZERO, Vector2i(SIZE - 1, SIZE - 1))
		for py in range(lo.y, hi.y + 1):
			for px in range(lo.x, hi.x + 1):
				var t := (frame_of(px, py) - c).length() / rr
				if t < 1.0:
					var i := py * SIZE + px
					d[i] = maxf(d[i], depth * pow(1.0 - t * t, 2.0))


## value noise in 0..1 over the square: `oct` octaves from a lattice of `base` cells, each octave twice as fine, half as strong
static func _noise(seed_: int, oct: int, base: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := PackedFloat32Array()
	out.resize(SIZE * SIZE)
	var amp := 1.0
	var tot := 0.0
	var cells := base
	for o in oct:
		var n := int(cells) + 2
		var lat := PackedFloat32Array()
		lat.resize(n * n)
		for i in lat.size():
			lat[i] = rng.randf()
		for py in SIZE:
			for px in SIZE:
				var u := (px + 0.5) / SIZE * cells
				var v := (py + 0.5) / SIZE * cells
				var i0 := floori(u)
				var j0 := floori(v)
				var fu := _smoothstep(0.0, 1.0, u - i0)
				var fv := _smoothstep(0.0, 1.0, v - j0)
				var a := lerpf(lat[j0 * n + i0], lat[j0 * n + i0 + 1], fu)
				var b := lerpf(lat[(j0 + 1) * n + i0], lat[(j0 + 1) * n + i0 + 1], fu)
				out[py * SIZE + px] += amp * lerpf(a, b, fv)
		tot += amp
		amp *= 0.5
		cells *= 2.0
	var lo := INF
	var hi := -INF
	for i in out.size():
		lo = minf(lo, out[i])
		hi = maxf(hi, out[i])
	for i in out.size():
		out[i] = (out[i] - lo) / maxf(hi - lo, 1e-6)
	return out
