## godot --headless --path . -s tests/decompose_test.gd     (round 42, lead: a round-41 finding fixed)
## Body.decompose read the swing angle as 2 acos(w). Near w = 1 that is ill-conditioned: a 0.01 deg swing changes w by
## ~4e-9, under a float32's step, so small swings came back as 0 (WW7 found it and carried its own atan2 copy).
## 2 atan2(|v|, w) reads the angle from the vector part, which keeps it. Bars: tiny swings round-trip, big ones unchanged.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	# 1. tiny swings on every joint and axis come back (bar: 2 % of the angle, or 1e-4 deg)
	var worst := 0.0
	var at := ""
	for j in B.t_ax.keys():
		for a in [0.001, 0.01, 0.05, -0.02]:
			for v in [Vector3(a, 0, 0), Vector3(0, a, 0), Vector3(a, a, 0)]:
				var back: Vector3 = B.decompose(j, B.compose(j, v))
				var e: float = (back - v).length() / maxf(v.length(), 1e-9)
				if e > worst:
					worst = e
					at = "%s %s -> %s" % [j, v, back]
	ok(worst < 0.02, "tiny swings (0.001..0.05 deg) round-trip: worst relative error %.4f (bar < 0.02) at %s" % [worst, at])
	# 2. ordinary angles agree with the bvh importer's atan2 copy (the reference of round 41) to 1e-4 deg
	var w2 := 0.0
	for j in B.t_ax.keys():
		for v in [Vector3(30, 10, 20), Vector3(-45, 0, 5), Vector3(90, -20, -30), Vector3(5, 5, 0)]:
			var q: Quaternion = B.compose(j, v)
			w2 = maxf(w2, (B.decompose(j, q) - BvhImport.decompose(B, j, q)).length())
	ok(w2 < 1e-4, "ordinary angles: Body.decompose = BvhImport.decompose within %.6f deg (bar 1e-4)" % w2)
	# 3. zero stays exactly zero
	var z := 0.0
	for j in B.t_ax.keys():
		z = maxf(z, B.decompose(j, Quaternion.IDENTITY).length())
	ok(z == 0.0, "identity decomposes to exactly 0 on every joint (%.9f)" % z)
	print("DECOMPOSE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
