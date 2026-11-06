class_name FinalHQ
## FINAL HQ (L49, GAP_AUDIT_1106 Rendering item 1): the offline "Final HQ" preset on Godot's own pipeline, on top of FinalRender's "final":
## global light bounce (SDFGI), depth of field (CameraAttributesPractical), motion blur by SUB-FRAME ACCUMULATION (the scene is drawn at
## `subframes` times across the shutter and averaged) and a sub-pixel-jittered ACCUMULATION pass (`accum` renders per time, averaged: it
## removes the per-frame noise of GI / shadow filtering by about 1/sqrt(N) and antialiases beyond MSAA). Nothing here is read from other code.

const PRESET := {"gi": true, "dof": true, "subframes": 8, "accum": 2, "shutter": 0.5, "gi_bounce": 0.8, "dof_amount": 0.5, "dof_far_mult": 3.0}


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


## the mean of same-size images, per channel, in floating point (RGBF). The accumulation pass and the sub-frame blur both use it
static func accumulate(imgs: Array) -> Image:
	var n := imgs.size()
	var first: Image = imgs[0]
	var w := first.get_width()
	var h := first.get_height()
	var acc := PackedInt32Array()
	acc.resize(w * h * 3)
	for im in imgs:
		var c := (im as Image).duplicate() as Image
		c.convert(Image.FORMAT_RGB8)
		var d: PackedByteArray = c.get_data()
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
