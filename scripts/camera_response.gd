class_name CameraResponse
extends RefCounted
## A single camera response for every CH5 image, calibrated once on the wet pose-0 frame.
##
## Godot's linear-tonemapped, sRGB-encoded output is decoded to linear light. The phone model is
##   output_linear = max(0, exposure_gain * (input_linear - black_level))
## followed by the standard sRGB encoding. This is a sensor black-level subtraction plus exposure,
## not a histogram warp or a per-bar/per-scene adjustment. The two anchors come from ref2 itself:
## its exactly-black fraction sets the black-level quantile, and its median luminance sets mid grey.
## The S1/S1B 0.02 threshold and their acceptance bands are NOT used by this calibration.

const REFERENCE_PHOTO := "C:/Users/Nick/tools/kine_workers/out/ch5/ref/ref2.jpg"

static var calibrated := false
static var black_level := 0.0
static var exposure_gain := 1.0
static var _lut := PackedFloat32Array()


static func _srgb_to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _linear_to_srgb(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return 12.92 * v if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func _quantile(sorted_values: PackedFloat32Array, q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var p := clampf(q, 0.0, 1.0) * float(sorted_values.size() - 1)
	var i := int(p)
	return lerpf(sorted_values[i], sorted_values[mini(i + 1, sorted_values.size() - 1)], p - float(i))


static func calibrate(raw: Image, photo_path: String = REFERENCE_PHOTO) -> void:
	if calibrated:
		return
	var photo := Image.load_from_file(photo_path)
	if photo == null:
		push_error("CAMERA RESPONSE: cannot load " + photo_path)
		return
	var photo_lumas := PackedFloat32Array()
	var photo_black := 0
	for y in range(0, photo.get_height(), 2):
		for x in range(0, photo.get_width(), 2):
			var c := photo.get_pixel(x, y)
			photo_lumas.append(_luma(c))
			if c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
				photo_black += 1
	var raw_lumas := PackedFloat32Array()
	var raw_max_linear := PackedFloat32Array()
	# The central 480 px are the reference photo's field in the 1280 x 720 render.
	for y in range(0, raw.get_height(), 2):
		for x in range(400, mini(880, raw.get_width()), 2):
			var c := raw.get_pixel(x, y)
			raw_lumas.append(_luma(c))
			raw_max_linear.append(maxf(_srgb_to_linear(c.r), maxf(_srgb_to_linear(c.g), _srgb_to_linear(c.b))))
	photo_lumas.sort()
	raw_lumas.sort()
	raw_max_linear.sort()
	var clip_fraction := float(photo_black) / maxf(float(photo_lumas.size()), 1.0)
	var photo_mid := _quantile(photo_lumas, 0.5)
	var raw_mid := _quantile(raw_lumas, 0.5)
	black_level = _quantile(raw_max_linear, clip_fraction)
	exposure_gain = _srgb_to_linear(photo_mid) / maxf(_srgb_to_linear(raw_mid) - black_level, 1e-6)
	_lut.resize(256)
	for i in 256:
		_lut[i] = _linear_to_srgb(maxf(0.0, exposure_gain * (_srgb_to_linear(float(i) / 255.0) - black_level)))
	calibrated = true
	print("     CAMERA RESPONSE: photo exactly-black %.2f %%, median sRGB luminance %.6f; raw median %.6f; derived black_level %.8f linear (%.6f sRGB), exposure_gain %.6f" % [100.0 * clip_fraction, photo_mid, raw_mid, black_level, _linear_to_srgb(black_level), exposure_gain])


static func apply(raw: Image) -> Image:
	if not calibrated:
		push_error("CAMERA RESPONSE: calibrate on the canonical wet pose-0 frame before apply")
		return raw
	var out: Image = raw.duplicate()
	for y in raw.get_height():
		for x in raw.get_width():
			var c := raw.get_pixel(x, y)
			out.set_pixel(x, y, Color(_lut[int(c.r * 255.0 + 0.5)], _lut[int(c.g * 255.0 + 0.5)], _lut[int(c.b * 255.0 + 0.5)], c.a))
	return out
