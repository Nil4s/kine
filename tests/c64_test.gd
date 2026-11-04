## godot --path . -s tests/c64_test.gd   (C64: KineSolveNative.cg, the heat-weights conjugate gradient of KMeshAutoWeights)
## Bars, stated before measuring:
##   1 EQUAL: KMeshAutoWeights.compute with the C++ solver gives ids exactly equal and weights within 1e-6 of the GDScript solver
##   2 ITERATIONS equal (cg_iters, solves) between the two
##   3 SPEED: the solve part (ms_parts.solve) is at least 5x faster native (median of 3)
##   4 FALLBACK: force_gd = true runs the GDScript path (result equal to the first GDScript run), so a missing class still works
##   5 CONTROL: a planted wrong weight (+1e-3) fails bar 1's comparison (the bar can fail)
## Skipped (printed, not failed) when the DLL has no KineSolveNative.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func sphere_mesh(seg: int, rings: int, r: float) -> KMesh:
	var prof := [[0.0, -r]]
	for k in range(1, rings):
		var a := -PI / 2.0 + PI * float(k) / rings
		prof.append([r * cos(a), r * sin(a)])
	prof.append([0.0, r])
	return KMeshPrims._lathe(seg, prof)


func med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return s[1]


func maxdiff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, absf(a[i] - b[i]))
	return m


func _init() -> void:
	if not NativeExt.ensure("kine_native", "KineSolveNative"):
		print("SKIP KineSolveNative is not in the DLL")
		print("C64 SKIP")
		quit(0)
		return
	var m := sphere_mesh(48, 40, 0.3)
	var bones := KMeshAutoWeights.chain(PackedVector3Array([Vector3(0, -0.28, 0), Vector3(0, -0.1, 0), Vector3(0, 0.1, 0), Vector3(0, 0.28, 0)]))
	KMeshAutoWeights.force_gd = true
	var gd := []
	var g0: Dictionary
	for i in 3:
		g0 = KMeshAutoWeights.compute(m, bones)
		gd.append(float(g0["ms_parts"]["solve"]))
	KMeshAutoWeights.force_gd = false
	var nt := []
	var n0: Dictionary
	for i in 3:
		n0 = KMeshAutoWeights.compute(m, bones)
		nt.append(float(n0["ms_parts"]["solve"]))
	var ids_eq: bool = (g0["ids"] as PackedInt32Array) == (n0["ids"] as PackedInt32Array)
	var d := maxdiff(g0["w"], n0["w"])
	ok(ids_eq and d <= 1e-6, "1 equal: ids identical %s, max weight diff %.3g (<= 1e-6)" % [ids_eq, d])
	ok(g0["cg_iters"] == n0["cg_iters"] and g0["solves"] == n0["solves"], "2 iterations equal: %d vs %d over %d solves" % [g0["cg_iters"], n0["cg_iters"], n0["solves"]])
	var sp := med(gd) / maxf(0.001, med(nt))
	print("PROF solve gdscript %.2f ms native %.2f ms  (whole compute %.1f vs %.1f ms)" % [med(gd), med(nt), g0["ms"], n0["ms"]])
	ok(sp >= 5.0, "3 speed: solve %.1fx faster native (>= 5x)" % sp)
	KMeshAutoWeights.force_gd = true
	var g1 := KMeshAutoWeights.compute(m, bones)
	KMeshAutoWeights.force_gd = false
	ok((g1["w"] as PackedFloat32Array) == (g0["w"] as PackedFloat32Array), "4 fallback: the GDScript path reproduces itself with force_gd")
	var bad: PackedFloat32Array = (n0["w"] as PackedFloat32Array).duplicate()
	bad[10] += 1e-3
	ok(not (maxdiff(g0["w"], bad) <= 1e-6), "5 control: a planted +1e-3 weight fails the equality bar")
	print("C64 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
