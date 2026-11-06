extends SceneTree
## godot --path . -s tests/g4dbl_test.gd     (G4DBL: CAD poses in doubles, scripts/build/xform64.gd). Bars committed BEFORE the first run; each has a planted control:
##   a ROUNDTRIP  10^4 random poses (turn about a random axis, move up to 2 m per axis): B' = inverse(A) * (A * B) and A' = (A * B) * inverse(B) equal B and A
##                to 1e-12 (every entry, metres). CONTROL: the same chain in Transform3D is off by >= 1e-7
##   b ENGINE     the CH13 engine's piston pin height (Ch13Parts.points64 through Xform64) equals the closed form R cos th + sqrt(L^2 - R^2 sin^2 th) to 1e-9 mm
##                at 36 angles (0, 10 .. 350 deg); so does the rod's small end (a chain of two poses), and the big end sits on the crank pin to 1e-9 mm.
##                CONTROL: the float32 path (Ch13Parts.points) misses 1e-9 mm
##   c DISPLAY    Xform64.to_t3d gives every one of the 12 entries equal to the double rounded to float32 (10^3 random poses + the 36 engine poses). CONTROL: one entry
##                nudged by 1e-6 (relative) is caught
##   d REPLAY     the 36 engine assemblies saved (JSON) and read back keep every pos / rot double bit-exact, and Assembly.xf64_of of the read-back record is
##                bit-identical (all 12 doubles) to the original's. CONTROL: a pose rounded to float32 is not bit-identical
const P := preload("res://scripts/build/ch13_parts.gd")
var fails := 0
var nok := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
	nok += 1 if c else 0


func f32(d: float) -> float:
	return PackedFloat32Array([d])[0]


func rnd_pose(rng: RandomNumberGenerator) -> PackedFloat64Array:
	var ax := [rng.randfn(), rng.randfn(), rng.randfn()]
	return Xform64.from_axis_angle(ax, rng.randf_range(-PI, PI), [rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0)])


func bars_roundtrip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var worst := 0.0
	var worst32 := 0.0
	for i in 10000:
		var a := rnd_pose(rng)
		var b := rnd_pose(rng)
		var c := Xform64.compose(a, b)
		worst = maxf(worst, Xform64.max_diff(Xform64.compose(Xform64.inverse(a), c), b))
		worst = maxf(worst, Xform64.max_diff(Xform64.compose(c, Xform64.inverse(b)), a))
		var ta := Xform64.to_t3d(a)
		var tb := Xform64.to_t3d(b)
		var tc := ta * tb
		var back := ta.affine_inverse() * tc
		worst32 = maxf(worst32, Xform64.max_diff(Xform64.from_t3d(back), Xform64.from_t3d(tb)))
	ok(worst <= 1e-12, "a 10^4 random poses (up to 2 m): compose / inverse round trip worst %s (bar 1e-12)" % String.num_scientific(worst))
	ok(worst32 >= 1e-7, "a ctl the same chain in Transform3D is off by %s (>= 1e-7)" % String.num_scientific(worst32))


func bars_engine() -> void:
	var R := P.R
	var L := P.L
	var w64 := 0.0
	var w32 := 0.0
	for k in 36:
		var th := 10.0 * k
		var t := deg_to_rad(th)
		var x := R * cos(t) + sqrt(L * L - R * R * sin(t) * sin(t))
		var q := P.points64(th)
		var q32 := P.points(th)
		w64 = maxf(w64, absf(q["pin"][1] - x))
		w64 = maxf(w64, absf(q["rod_small"][1] - x))
		w64 = maxf(w64, absf(q["rod_small"][0]))
		var cp: Array = q["crankpin"]
		var rb: Array = q["rod_big"]
		w64 = maxf(w64, sqrt((cp[0] - rb[0]) * (cp[0] - rb[0]) + (cp[1] - rb[1]) * (cp[1] - rb[1]) + (cp[2] - rb[2]) * (cp[2] - rb[2])))
		w32 = maxf(w32, absf(q32["pin"].y - x))
		w32 = maxf(w32, absf(q32["rod_small"].y - x))
	ok(w64 <= 1e-9, "b engine: pin height = x(theta), small end on it, big end on the crank pin, 36 angles: worst %s mm (bar 1e-9)" % String.num_scientific(w64))
	ok(w32 > 1e-9, "b ctl the float32 path (Ch13Parts.points) misses 1e-9 mm: worst %s mm" % String.num_scientific(w32))


func bars_display() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var poses: Array = []
	for i in 1000:
		poses.append(rnd_pose(rng))
	for k in 36:
		var po := P.pose_of(10.0 * k)
		for nm in po:
			poses.append(Assembly.xf64_of(po[nm]))
	var bad := 0
	for a in poses:
		var d := Xform64.from_t3d(Xform64.to_t3d(a))
		for i in 12:
			if d[i] != f32(a[i]):
				bad += 1
	ok(bad == 0, "c display: %d poses x 12 entries, Transform3D = double rounded to float32 (%d mismatches)" % [poses.size(), bad])
	var n: PackedFloat64Array = (poses[0] as PackedFloat64Array).duplicate()
	n[9] *= 1.000001
	var d2 := Xform64.from_t3d(Xform64.to_t3d(poses[0]))
	ok(d2[9] != f32(n[9]), "c ctl a nudged entry (1e-6 relative) is caught")


func same_bits(a: Array, b: Array) -> bool:
	return PackedFloat64Array(a).to_byte_array() == PackedFloat64Array(b).to_byte_array()


func bars_replay() -> void:
	Assembly.dir = "user://g4dbl_tmp"
	var allsame := true
	var xsame := true
	var n := 0
	var first_pose := PackedFloat64Array()
	for k in 36:
		var asm := P.assembly(10.0 * k + 0.1234567891234)
		asm["name"] = "g4dbl %d" % k
		var path := Assembly.save(asm)
		var back := Assembly.read(path)
		if back.is_empty() or (back["parts"] as Array).size() != (asm["parts"] as Array).size():
			allsame = false
			continue
		for i in (asm["parts"] as Array).size():
			var p: Dictionary = asm["parts"][i]
			var q: Dictionary = back["parts"][i]
			allsame = allsame and same_bits(p["pos"], q["pos"]) and same_bits(p["rot"], q["rot"])
			xsame = xsame and Assembly.xf64_of(p).to_byte_array() == Assembly.xf64_of(q).to_byte_array()
			n += 1
		if k == 7:
			first_pose = Assembly.xf64_of(asm["parts"][2])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ok(allsame and n == 36 * 7, "d replay: %d part poses saved and read back, pos / rot bit-exact" % n)
	ok(xsame, "d replay: Assembly.xf64_of of the read-back record is bit-identical (12 doubles each)")
	var r32 := first_pose.duplicate()
	for i in 12:
		r32[i] = f32(r32[i])
	ok(r32.to_byte_array() != first_pose.to_byte_array(), "d ctl a pose rounded to float32 is not bit-identical")


func _init() -> void:
	bars_roundtrip()
	bars_engine()
	bars_display()
	bars_replay()
	print("g4dbl: %d ok, %d fail" % [nok, fails])
	quit(1 if fails > 0 else 0)
