extends SceneTree
const KCad := preload("res://scripts/kcad.gd")
## S249n native seat. godot --headless --path . -s tests/s249n_test.gd
##  A the C++ seat (KineSeatNative via PartFast.surface_under) answers what the s237 loop (_surface_under_ref) answers at 40 points on the temple's first 60 steps
##  B CONTROL: points shifted by (3000, 1500) give another answer, so A can fail
##  C PartFast.force_gd = true (the DLL "absent") still equals the reference (the GDScript grid fallback)
##  D CONTROL: a planted 0.01 mm wrong answer fails the 1e-9 comparison used in A
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if is_nan(float(a[i])) != is_nan(float(b[i])) or (not is_nan(float(a[i])) and absf(float(a[i]) - float(b[i])) > 1e-9):
			return false
	return true
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s257_temple.json"))
	var rec: Dictionary = d["part"]
	var small := rec.duplicate(true)
	small["features"] = (rec["features"] as Array).slice(0, 60)
	var ids: Array = Part.replay(small, -1, {"keep": true})["ids"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pts: Array = []
	for i in 40:
		pts.append(Vector3(rng.randf_range(-12000, 12000), 0, rng.randf_range(-12000, 12000)))
	var a: Array = PartOrnament._surface_under_ref(ids, pts, 20000.0, -500.0)
	var nat := ClassDB.class_exists("KineSeatNative") or NativeExt.ensure("kine_native", "KineSeatNative")
	ok(nat, "KineSeatNative loaded")
	PartFast.force_gd = false
	var b: Array = PartFast.surface_under(ids, pts, 20000.0, -500.0)
	var nh := 0
	for x in a:
		if not is_nan(float(x)): nh += 1
	ok(same(a, b) and nh > 3, "A native == reference at %d points, %d hit" % [a.size(), nh])
	var sh: Array = pts.map(func(p): return p + Vector3(3000, 0, 1500))
	ok(not same(a, PartOrnament._surface_under_ref(ids, sh, 20000.0, -500.0)), "B control: shifted points differ")
	PartFast.force_gd = true
	var c: Array = PartFast.surface_under(ids, pts, 20000.0, -500.0)
	PartFast.force_gd = false
	ok(same(a, c), "C GDScript fallback == reference")
	var bad := b.duplicate()
	for i in bad.size():
		if not is_nan(float(bad[i])):
			bad[i] = float(bad[i]) + 0.01
			break
	ok(not same(a, bad), "D control: planted 0.01 mm error is caught")
	# E sewing: a welded mesh takes the direct shell, an unwelded copy takes the sewing; both give the same solid
	var cube_v := PackedVector3Array([Vector3(0,0,0),Vector3(.02,0,0),Vector3(.02,.03,0),Vector3(0,.03,0),Vector3(0,0,.04),Vector3(.02,0,.04),Vector3(.02,.03,.04),Vector3(0,.03,.04)])
	var cube_t := PackedInt32Array([0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4, 3,7,6, 3,6,2, 0,4,7, 0,7,3, 1,2,6, 1,6,5])
	var id1 := KCad.solid_from_mesh(cube_v, cube_t, 1e-6)
	var uv := PackedVector3Array()
	var ut := PackedInt32Array()
	for i in cube_t.size():
		uv.append(cube_v[cube_t[i]])
		ut.append(i)
	var id2 := KCad.solid_from_mesh(uv, ut, 1e-6)
	var want := 0.02 * 0.03 * 0.04
	ok(id1 != 0 and id2 != 0 and absf(KCad.volume(id1) - want) < 1e-6 * want and absf(KCad.volume(id1) - KCad.volume(id2)) < 1e-9 * want, "E welded (direct) and unwelded (sewn) cube both have volume %s (got %s / %s)" % [want, KCad.volume(id1) if id1 != 0 else -1.0, KCad.volume(id2) if id2 != 0 else -1.0])
	var open_t := cube_t.slice(0, cube_t.size() - 3)
	ok(KCad.solid_from_mesh(cube_v, open_t, 1e-6) == 0, "E2 CONTROL: a cube missing a face is refused (not closed), not made into a solid")
	# F the whole temple against the recorded origin
	var base: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s249n_temple_sig.json"))["sig"]
	var t0 := Time.get_ticks_msec()
	var res := Part.replay(rec.duplicate(true), -1, {"keep": true})
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var vols: Array = res["volumes"]
	var worst_v := 0.0
	var worst_b := 0.0
	var same_n := vols.size() == base.size()
	for i in mini(vols.size(), base.size()):
		worst_v = maxf(worst_v, absf(float(vols[i]) - float(base[i][0])) / maxf(absf(float(base[i][0])), 1.0))
		var bx := PartFacts.box_of(PartFacts.tess_mm(int(res["ids"][i]), 0.002, 0.8))
		var bb: Array = base[i][1]
		worst_b = maxf(worst_b, maxf(bx.position.distance_to(Vector3(bb[0], bb[1], bb[2])), bx.end.distance_to(Vector3(bb[3], bb[4], bb[5]))))
	ok(same_n and worst_v < 1e-9 and worst_b < 0.01, "F temple: %d bodies, worst volume rel %s (bar 1e-9), worst box %.5f mm (bar 0.01)" % [vols.size(), worst_v, worst_b])
	ok(worst_b + 0.02 > 0.01, "F2 CONTROL: a box shifted by 0.02 mm would fail the 0.01 bar")
	print("temple replay s ", secs)
	print("s249n: %d fail" % fails)
	quit(1 if fails > 0 else 0)
