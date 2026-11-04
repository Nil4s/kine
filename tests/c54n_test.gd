## godot --headless --path . -s tests/c54n_test.gd     (C54n: the C++ pair list + pair solve of ClothSelf, class KineClothSelfNative)
## Same fixture as c54. Bars, written before any number was read (all need the DLL; without it the test prints SKIP and passes,
## c54 itself then covers bars 2/3/7 on the GDScript path):
##   N1 SAME   ON baked with the C++ path vs the GDScript path: every vertex of the first 10 frames from frame 30 on (the fold) within 1e-5 m.
##   N2 CLEAN  C++ ON: 0 close pairs (brute force measure) at every one of the 61 frames        (c54 bar 2)
##   N3 STRETCH C++ ON: no structural edge over 1.15 x rest                                      (c54 bar 3)
##   N4 COST   C++ ON minus OFF (GDScript sim, same as c54 bar 4) <= 8 ms/frame, 3 repeats, all printed
##   N5 HASH   C++ pair list == GDScript pair list on the flat cape (empty) and on the folded frame (same pairs, same order)
##   N6 CONTROL the bars can fail: OFF has close pairs; a planted wrong C++ result (positions shifted 1 mm) fails N1's test
extends SceneTree

var fails := 0
const FPS := 30
const NF := 61
const LIMIT := 0.95 * 0.006


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func fixture() -> Dictionary:
	var A: Array = []
	var C: Array = []
	for k in NF:
		var t := float(k) / float(FPS)
		var s := smoothstep(0.3, 1.2, t)
		var pins := PackedVector3Array()
		for c in Cloth.COLS:
			var u := float(c) / float(Cloth.COLS - 1) * 2.0 - 1.0
			var hw := lerpf(0.15, 0.05, s)
			pins.append(Vector3(u * hw, Cloth.TOP_Y - 0.45 * s, -0.17 + (0.008 if c % 2 == 0 else -0.008) * s))
		A.append(pins)
		C.append(PackedVector3Array([Vector3(-0.4, 0.30, -0.12), Vector3(0.4, 0.30, -0.12)]))
	return {"A": A, "C": C, "rads": PackedFloat64Array([0.08])}


func bake(fx: Dictionary, on: bool, native: bool) -> Dictionary:
	Cloth.self_collide = on
	Cloth.force_gdscript = true   # the cape sim itself stays GDScript in every arm; only ClothSelf differs
	ClothSelf.force_gdscript = not native
	var r := Cloth.simulate(fx["A"], fx["C"], fx["rads"], FPS, null)
	Cloth.self_collide = false
	Cloth.force_gdscript = false
	ClothSelf.force_gdscript = false
	return r


func worst_pairs(cape: Dictionary) -> int:
	var f := Cloth.faces()
	var mx := 0
	for fr in cape["frames"]:
		mx = maxi(mx, ClothSelf.count_close(fr, f, LIMIT))
	return mx


func max_stretch(cape: Dictionary) -> float:
	var E := Cloth.topology()["edges"] as PackedInt32Array
	var dy := Cloth.LEN / float(Cloth.ROWS - 1)
	var worst := 0.0
	for fr in cape["frames"]:
		for k in E.size() / 2:
			var a := E[2 * k]
			var b := E[2 * k + 1]
			var rest := dy if absi(a - b) == Cloth.COLS else 0.30 / float(Cloth.COLS - 1)
			worst = maxf(worst, (fr[a] as Vector3).distance_to(fr[b]) / rest)
	return worst


func max_diff(a: Dictionary, b: Dictionary, k0: int, k1: int, shift := 0.0) -> float:
	var worst := 0.0
	for k in range(k0, k1):
		var fa: PackedVector3Array = a["frames"][k]
		var fb: PackedVector3Array = b["frames"][k]
		for i in fa.size():
			worst = maxf(worst, (fa[i] + Vector3(shift, 0, 0)).distance_to(fb[i]))
	return worst


func _init() -> void:
	create_timer(900.0).timeout.connect(func(): print("FAIL watchdog 900 s"); quit(2))
	if not NativeExt.ensure("kine_native", "KineClothSelfNative"):
		print("SKIP c54n: no KineClothSelfNative (DLL not built); the GDScript path is covered by c54")
		quit(0)
		return
	var fx := fixture()
	var off := bake(fx, false, false)
	ok(worst_pairs(off) > 0, "N6 CONTROL off has close pairs")
	var gd := bake(fx, true, false)
	var nat := bake(fx, true, true)
	var d := max_diff(gd, nat, 30, 40)
	print("max |C++ - GDScript| frames 30..39: %.3e m (all frames: %.3e)" % [d, max_diff(gd, nat, 0, NF)])
	ok(d <= 1e-5, "N1 SAME frames 30..39 within 1e-5 m (%.3e)" % d)
	ok(max_diff(gd, nat, 30, 40, 0.001) > 1e-5, "N6 CONTROL a 1 mm planted shift fails N1's test")
	var w := worst_pairs(nat)
	ok(w == 0, "N2 CLEAN C++ ON: 0 close pairs at every frame (worst %d)" % w)
	ok(max_stretch(nat) <= 1.15, "N3 STRETCH %.3f <= 1.15" % max_stretch(nat))
	var f := Cloth.faces()
	var flat := nat["frames"][0] as PackedVector3Array
	var fold := off["frames"][44] as PackedVector3Array
	ClothSelf.force_gdscript = true
	var g1 := ClothSelf.new(f, Cloth.THICK)
	var g2 := ClothSelf.new(f, Cloth.THICK)
	ClothSelf.force_gdscript = false
	var n1 := ClothSelf.new(f, Cloth.THICK)
	var n2 := ClothSelf.new(f, Cloth.THICK)
	ok(n1.nat != null and g1.nat == null, "N5 the two arms really are native / GDScript")
	ok(n1.begin(flat) == 0 and g1.begin(flat) == 0, "N5 flat cape: both pair lists empty")
	var cg := g2.begin(fold)
	var cn := n2.begin(fold)
	ok(cg > 0 and cg == cn and g2.pairs == n2.nat.get_pairs(), "N5 folded frame: same pair list (%d vs %d)" % [cg, cn])
	# cost: OFF (GDScript sim) vs C++ ON, 3 repeats, load noted
	var worst_cost := -1e9
	for rep in 3:
		var t0 := Time.get_ticks_usec()
		bake(fx, false, false)
		var t_off := float(Time.get_ticks_usec() - t0) / 1000.0 / NF
		t0 = Time.get_ticks_usec()
		bake(fx, true, true)
		var t_on := float(Time.get_ticks_usec() - t0) / 1000.0 / NF
		print("N4 repeat %d: off %.2f on %.2f ms/frame, +%.2f  (cpu load %s)" % [rep + 1, t_off, t_on, t_on - t_off, str(OS.get_environment("NUMBER_OF_PROCESSORS"))])
		worst_cost = maxf(worst_cost, t_on - t_off)
	ok(worst_cost <= 8.0, "N4 COST worst of 3 repeats +%.2f ms/frame <= 8" % worst_cost)
	print("c54n: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
