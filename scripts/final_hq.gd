class_name FinalHQ
## FINAL HQ (L49, GAP_AUDIT_1106 Rendering item 1): the offline "Final HQ" preset on Godot's own pipeline, on top of FinalRender's "final":
## global light bounce (SDFGI), depth of field (CameraAttributesPractical), motion blur by SUB-FRAME ACCUMULATION (the scene is drawn at
## `subframes` times across the shutter and averaged) and a sub-pixel-jittered ACCUMULATION pass (`accum` renders per time, averaged: it
## removes the per-frame noise of GI / shadow filtering by about 1/sqrt(N) and antialiases beyond MSAA). Nothing here is read from other code.

const PRESET := {"gi": true, "dof": true, "subframes": 8, "accum": 2, "shutter": 0.5, "gi_bounce": 0.8, "dof_amount": 0.5, "dof_far_mult": 3.0, "denoise": true, "denoise_iters": 3, "denoise_sigma_c": 0.25, "denoise_sigma_g": 0.08}

static var _force_gd := false   # tests: true = the GDScript twins even when the DLL is there


## SDFGI bounce on / off (the cheap path to global light on Forward+); off restores the plain renderer
static func gi(env: Environment, on: bool, bounce := 0.8) -> void:
	env.sdfgi_enabled = on
	if on:
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = bounce
		env.sdfgi_cascades = 4
		env.sdfgi_energy = 1.0
		env.sdfgi_read_sky_light = true


## depth of field on a camera: sharp at `focus` metres, blurred beyond it (far_trans metres to full blur; default 3 x focus) and in front of it
static func dof(cam: Camera3D, focus: float, far_trans := -1.0, amount := -1.0) -> CameraAttributesPractical:
	var a := CameraAttributesPractical.new()
	focus = maxf(focus, 0.1)
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = focus
	a.dof_blur_far_transition = far_trans if far_trans > 0.0 else focus * float(PRESET["dof_far_mult"])
	a.dof_blur_near_enabled = true
	a.dof_blur_near_distance = focus * 0.8
	a.dof_blur_near_transition = focus * 0.6
	a.dof_blur_amount = amount if amount > 0.0 else float(PRESET["dof_amount"])
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	cam.attributes = a
	return a


## n sample times across the shutter (shutter = fraction of a frame, 0.5 = 180 degrees), centred on t, first and last at the shutter's ends:
## the moving thing's streak is exactly speed x shutter / fps long. n < 2: just [t]
static func motion_times(t: float, fps: int, n: int, shutter: float, lo := -INF, hi := INF) -> Array:
	if n < 2:
		return [clampf(t, lo, hi)]
	var s := shutter / float(fps)
	var out := []
	for i in n:
		out.append(clampf(t - s * 0.5 + s * float(i) / float(n - 1), lo, hi))
	return out


static func native_available() -> bool:
	return not _force_gd and (ClassDB.class_exists("KineRenderNative") or NativeExt.ensure("kine_native", "KineRenderNative"))


## the mean of same-size images, per channel, in floating point (RGBF). The accumulation pass and the sub-frame blur both use it.
## C++ (KineRenderNative.accumulate) when the DLL is there, else accumulate_gd (same result to 1/255)
static func accumulate(imgs: Array) -> Image:
	if not native_available():
		return accumulate_gd(imgs)
	var first: Image = imgs[0]
	var w := first.get_width()
	var h := first.get_height()
	var datas := []
	for im in imgs:
		datas.append(_rgb8(im).get_data())
	var out: PackedFloat32Array = _door().accumulate(datas)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBF, out.to_byte_array())


static func _rgb8(im: Image) -> Image:
	if im.get_format() == Image.FORMAT_RGB8:
		return im
	var c := im.duplicate() as Image
	c.convert(Image.FORMAT_RGB8)
	return c


static var _door_s = null


static func _door():
	if _door_s == null:
		_door_s = load("res://scripts/render_native_door.gd")
	return _door_s


## the GDScript twin of accumulate (the fallback and the test's reference)
static func accumulate_gd(imgs: Array) -> Image:
	var n := imgs.size()
	var first: Image = imgs[0]
	var w := first.get_width()
	var h := first.get_height()
	var acc := PackedInt32Array()
	acc.resize(w * h * 3)
	for im in imgs:
		var d: PackedByteArray = _rgb8(im).get_data()
		for i in acc.size():
			acc[i] += d[i]
	var out := PackedFloat32Array()
	out.resize(acc.size())
	var k := 1.0 / (255.0 * float(n))
	for i in acc.size():
		out[i] = float(acc[i]) * k
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBF, out.to_byte_array())


## the 8-bit picture of an accumulate() result, ready for save_png
static func to_rgb8(img: Image) -> Image:
	var c := img.duplicate() as Image
	c.convert(Image.FORMAT_RGB8)
	return c


## sub-pixel offsets (in pixels, -0.5..0.5) of the k-th of n accumulation passes: a Halton(2, 3) sequence; pass 0 is the centre
static func jitter(k: int, n: int) -> Vector2:
	if n < 2 or k == 0:
		return Vector2.ZERO
	return Vector2(_halton(k, 2) - 0.5, _halton(k, 3) - 0.5)


static func _halton(i: int, b: int) -> float:
	var f := 1.0
	var r := 0.0
	var x := i
	while x > 0:
		f /= float(b)
		r += f * float(x % b)
		x /= b
	return r


## the camera moved by a sub-pixel offset in its own right / up axes (px = world size of one pixel at the focus distance)
static func jitter_xf(xf: Transform3D, off: Vector2, fov_v_deg: float, focus: float, height_px: int) -> Transform3D:
	var px := 2.0 * tan(deg_to_rad(fov_v_deg) * 0.5) * maxf(focus, 0.5) / float(maxi(height_px, 1))
	var o := xf
	o.origin += xf.basis.x * off.x * px + xf.basis.y * off.y * px
	return o


## EDGE-AWARE DENOISE (a-trous wavelet, written from Dammertz et al. 2010): `img` is filtered, `guide` (an RGBF feature buffer: albedo / normal / depth
## written as colour; null = the image itself) says where the true edges are. Each of `iters` passes spreads over a 5x5 B3-spline kernel with holes
## (step 1, 2, 4), every tap weighted by exp(-|d colour|^2 / (sigma_c / 2^pass)^2) * exp(-|d guide|^2 / sigma_g^2). Returns RGBF.
static func denoise(img: Image, guide: Image = null, iters := -1, sigma_c := -1.0, sigma_g := -1.0) -> Image:
	if not native_available():
		return denoise_gd(img, guide, iters, sigma_c, sigma_g)
	var a := _dn_args(img, guide, iters, sigma_c, sigma_g)
	var out: PackedFloat32Array = _door().denoise(a[0], a[1], a[2], a[3], a[4], a[5], a[6])
	return Image.create_from_data(a[2], a[3], false, Image.FORMAT_RGBF, out.to_byte_array())


static func _dn_args(img: Image, guide: Image, iters: int, sc: float, sg: float) -> Array:
	var c := img.duplicate() as Image
	c.convert(Image.FORMAT_RGBF)
	var g := c
	if guide != null:
		g = guide.duplicate() as Image
		g.convert(Image.FORMAT_RGBF)
	return [c.get_data().to_float32_array(), g.get_data().to_float32_array(), c.get_width(), c.get_height(),
		iters if iters >= 0 else int(PRESET["denoise_iters"]), sc if sc > 0.0 else float(PRESET["denoise_sigma_c"]), sg if sg > 0.0 else float(PRESET["denoise_sigma_g"])]


## the GDScript twin of denoise (the fallback and the test's reference); same arithmetic, slow
static func denoise_gd(img: Image, guide: Image = null, iters := -1, sigma_c := -1.0, sigma_g := -1.0) -> Image:
	var A := _dn_args(img, guide, iters, sigma_c, sigma_g)
	var a: PackedFloat32Array = A[0]
	var g: PackedFloat32Array = A[1]
	var w: int = A[2]
	var h: int = A[3]
	var inv_g := 1.0 / maxf(float(A[6]) * float(A[6]), 1e-12)
	var hk := [1.0 / 16.0, 0.25, 0.375, 0.25, 1.0 / 16.0]
	for it in int(A[4]):
		var step := 1 << it
		var sc := float(A[5]) / float(1 << it)
		var inv_c := 1.0 / maxf(sc * sc, 1e-12)
		var b := PackedFloat32Array()
		b.resize(a.size())
		for y in h:
			for x in w:
				var ci := (y * w + x) * 3
				var s0 := 0.0
				var s1 := 0.0
				var s2 := 0.0
				var ws := 0.0
				for dy in range(-2, 3):
					var yy := y + dy * step
					if yy < 0 or yy >= h:
						continue
					for dx in range(-2, 3):
						var xx := x + dx * step
						if xx < 0 or xx >= w:
							continue
						var qi := (yy * w + xx) * 3
						var u0 := a[ci] - a[qi]
						var u1 := a[ci + 1] - a[qi + 1]
						var u2 := a[ci + 2] - a[qi + 2]
						var v0 := g[ci] - g[qi]
						var v1 := g[ci + 1] - g[qi + 1]
						var v2 := g[ci + 2] - g[qi + 2]
						var wt: float = hk[dx + 2] * hk[dy + 2] * exp(-(u0 * u0 + u1 * u1 + u2 * u2) * inv_c - (v0 * v0 + v1 * v1 + v2 * v2) * inv_g)
						ws += wt
						s0 += wt * a[qi]
						s1 += wt * a[qi + 1]
						s2 += wt * a[qi + 2]
				if ws > 0.0:
					b[ci] = s0 / ws
					b[ci + 1] = s1 / ws
					b[ci + 2] = s2 / ws
				else:
					b[ci] = a[ci]
					b[ci + 1] = a[ci + 1]
					b[ci + 2] = a[ci + 2]
		a = b
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBF, a.to_byte_array())
