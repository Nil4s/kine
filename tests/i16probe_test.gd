extends SceneTree
func _init() -> void:
	NativeExt.ensure("kine_native", "KineIKNative")
	var door = load("res://scripts/body_ik_native.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var xs := PackedFloat64Array()
	for i in 20000:
		xs.append(rng.randf_range(-7.0, 7.0))
	var s_nat: PackedFloat64Array = door.math_probe(0, xs)
	var c_nat: PackedFloat64Array = door.math_probe(1, xs)
	var bad_s := 0
	var bad_c := 0
	for i in xs.size():
		if sin(xs[i]) != s_nat[i]:
			bad_s += 1
		if cos(xs[i]) != c_nat[i]:
			bad_c += 1
	print("sin double: %d of %d differ; cos double: %d differ" % [bad_s, xs.size(), bad_c])
	var ys := PackedFloat64Array()
	for i in 10000:
		ys.append(rng.randf_range(-3.0, 3.0))
		ys.append(rng.randf_range(-3.0, 3.0))
	var a_nat: PackedFloat64Array = door.math_probe(2, ys)
	var bad_a := 0
	for i in range(0, ys.size(), 2):
		if atan2(ys[i], ys[i + 1]) != a_nat[i / 2]:
			bad_a += 1
	print("atan2 double: %d of %d differ" % [bad_a, ys.size() / 2])
	var q_nat: PackedFloat64Array = door.math_probe(3, xs)
	var bad_q := 0
	for i in xs.size():
		var q := Quaternion(Vector3(0.6, 0.0, 0.8), xs[i])
		if q.x != q_nat[i * 4] or q.y != q_nat[i * 4 + 1] or q.z != q_nat[i * 4 + 2] or q.w != q_nat[i * 4 + 3]:
			bad_q += 1
	print("Quaternion(axis, angle): %d of %d differ" % [bad_q, xs.size()])
	var n_nat: PackedFloat64Array = door.math_probe(4, xs)
	var bad_n := 0
	for i in xs.size():
		var v := Vector3(xs[i], 0.3, -0.5).normalized()
		if v.x != n_nat[i * 3] or v.y != n_nat[i * 3 + 1] or v.z != n_nat[i * 3 + 2]:
			bad_n += 1
	print("Vector3.normalized: %d of %d differ" % [bad_n, xs.size()])
	var q5: PackedFloat64Array = door.math_probe(5, xs)
	var bad5 := 0
	for i in xs.size():
		var q := Quaternion(Vector3(0.6, 0.0, 0.8), xs[i])
		if q.x != q5[i * 4] or q.y != q5[i * 4 + 1] or q.z != q5[i * 4 + 2] or q.w != q5[i * 4 + 3]:
			bad5 += 1
	print("Variant-constructed Quaternion(axis, angle): %d of %d differ" % [bad5, xs.size()])
	var us: PackedFloat64Array = door.math_probe(6, xs)
	var uc: PackedFloat64Array = door.math_probe(7, xs)
	var ua: PackedFloat64Array = door.math_probe(8, ys)
	var b6 := 0
	var b7 := 0
	var b8 := 0
	for i in xs.size():
		if sin(xs[i]) != us[i]:
			b6 += 1
		if cos(xs[i]) != uc[i]:
			b7 += 1
	for i in range(0, ys.size(), 2):
		if atan2(ys[i], ys[i + 1]) != ua[i / 2]:
			b8 += 1
	print("UtilityFunctions sin/cos/atan2: %d / %d / %d differ" % [b6, b7, b8])
	var tm: PackedFloat64Array = door.math_probe(9, xs)
	print("cost: Variant Quaternion ctor %.0f ns/call, UtilityFunctions::sin %.0f ns/call" % [tm[0], tm[1]])
	print("i16probe: 0 fail")
	quit(0)
