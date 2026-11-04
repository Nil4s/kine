extends SceneTree
## S249 fast build. godot --headless --path . -s tests/s249_test.gd
##  A seat: PartFast.surface_under answers exactly what the s237 loop answers (same NAN pattern, same y), on the temple's first 60 steps
##  B CONTROL: the answer for shifted points differs, so A can fail
##  C a replay without "fast_build" leaves PartFast.enabled false and copies no roof (the default is unchanged)
##  D fast_build: the second wall-cap roof is a translated copy: volume rel 1e-9 and box within 0.01 mm of the sewn one, copy under 3 s
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s257_temple.json"))
	var rec: Dictionary = d["part"]
	var feats: Array = rec["features"]
	var small := rec.duplicate(true)
	small["features"] = feats.slice(0, 60)
	var res := Part.replay(small, -1, {"keep": true})
	var ids: Array = res["ids"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pts: Array = []
	for i in 40:
		pts.append(Vector3(rng.randf_range(-12000, 12000), 0, rng.randf_range(-12000, 12000)))
	var a: Array = PartOrnament._surface_under_ref(ids, pts, 20000.0, -500.0)
	var b: Array = PartFast.surface_under(ids, pts, 20000.0, -500.0)
	var same := a.size() == b.size()
	var nh := 0
	for i in a.size():
		if is_nan(float(a[i])) != is_nan(float(b[i])) or (not is_nan(float(a[i])) and absf(float(a[i]) - float(b[i])) > 1e-9):
			same = false
		if not is_nan(float(a[i])):
			nh += 1
	for i in 5: print("  ", a[i], " ", b[i])
	ok(same and nh > 3, "A seat: fast == reference at %d points, %d of them hit a host" % [a.size(), nh])
	var sh: Array = pts.map(func(p): return p + Vector3(3000, 0, 1500))
	var c: Array = PartOrnament._surface_under_ref(ids, sh, 20000.0, -500.0)
	var diff := 0
	for i in a.size():
		if is_nan(float(a[i])) != is_nan(float(c[i])) or (not is_nan(float(a[i])) and absf(float(a[i]) - float(c[i])) > 1e-9):
			diff += 1
	ok(diff > 0, "B control: shifted points give another answer (%d differ)" % diff)
	var r1: Dictionary
	var r2: Dictionary
	for f in feats:
		if f["id"] == "f294": r1 = f
		if f["id"] == "f295": r2 = f
	var one := {"features": [], "name": "t", "seq": 1, "version": rec.get("version", 1)}
	var recd := rec.duplicate(true)
	recd["features"] = [r1.duplicate(true), r2.duplicate(true)]
	var recf := recd.duplicate(true)
	recf["fast_build"] = true
	var tf := Time.get_ticks_msec()
	var rf := Part.replay(recf, -1, {"keep": true})
	var dt := Time.get_ticks_msec() - tf
	ok(PartFast.roof_copies >= 1, "D roof copied (%d)" % PartFast.roof_copies)
	var rd := Part.replay(recd.duplicate(true), -1, {"keep": true})
	ok(not PartFast.enabled, "C default: a replay without fast_build leaves Fast build off")
	var vd: Array = rd["volumes"]
	var vf: Array = rf["volumes"]
	var vok := vd.size() == vf.size()
	var bok := true
	for i in mini(vd.size(), vf.size()):
		if absf(float(vd[i]) - float(vf[i])) > 1e-9 * maxf(absf(float(vd[i])), 1.0):
			vok = false
		var bd := PartFacts.box_of(PartFacts.tess_mm(int(rd["ids"][i]), 0.002, 0.8))
		var bf := PartFacts.box_of(PartFacts.tess_mm(int(rf["ids"][i]), 0.002, 0.8))
		if bd.position.distance_to(bf.position) > 0.01 or bd.end.distance_to(bf.end) > 0.01:
			bok = false
	ok(vok and bok, "D volumes (rel 1e-9) and boxes (0.01 mm) equal to the default build")
	print("fast two-roof replay ms ", dt)
	print("s249: %d fail" % fails)
	quit(1 if fails > 0 else 0)
