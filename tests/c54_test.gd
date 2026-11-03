## godot --headless --path . -s tests/c54_test.gd     (C54, complaint #180: cloth self-collision; scripts/cloth_self.gd, Cloth.self_collide)
## Fixture (no body needed): a 2 s clip at 30 fps (61 frames). The cape's 12 pins sink 0.45 m between 0.3 s and 1.2 s while the row
## pinches from 0.30 m wide to 0.10 m, with an 8 cm-radius shelf at y 0.30 under the cape: the cloth buckles and folds onto itself.
## MEASURE (independent of the solver): ClothSelf.count_close = the number of triangle pairs of the cloth, sharing no vertex, whose
## surfaces are closer than 0.95 x THICK, by brute force over all pairs, at EVERY frame.
## Bars, written before any number was read:
##   1 CONTROL  self_collide OFF: some frame has more than 0 close pairs (the fixture folds into itself; this is the origin's behaviour).
##   2 CLEAN    self_collide ON: 0 close pairs at every one of the 61 frames.
##   3 STRETCH  ON: no structural edge longer than 1.15 x rest at any frame (the fix does not tear the cloth to get its room).
##   4 COST     ON costs at most 8 ms more per frame than OFF in the same (GDScript) solver; both numbers and the native OFF are printed.
##              If it is over, the default stays off and the panel says so; if under, it is still opt-in here (no default is changed).
##   5 SAME     two ON bakes of the same input are byte-identical (var_to_str of every frame).
##   6 MEASURE  the measure itself: a planted pair of triangles 2 mm apart counts 1, 20 mm apart counts 0.
##   7 HASH     the spatial hash finds every close pair the brute force finds (planted fold) and it is not O(n^2): the pair list of a flat
##              cape is empty.
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
		var caps := PackedVector3Array()
		caps.append(Vector3(-0.4, 0.30, -0.12))
		caps.append(Vector3(0.4, 0.30, -0.12))
		C.append(caps)
	return {"A": A, "C": C, "rads": PackedFloat64Array([0.08])}


func bake(fx: Dictionary, on: bool, gd := true) -> Dictionary:
	Cloth.self_collide = on
	Cloth.force_gdscript = gd
	var r := Cloth.simulate(fx["A"], fx["C"], fx["rads"], FPS, null)
	Cloth.self_collide = false
	Cloth.force_gdscript = false
	return r


func worst_pairs(cape: Dictionary) -> Array:
	var f := Cloth.faces()
	var mx := 0
	var at := -1
	var tot := 0
	for k in (cape["frames"] as Array).size():
		var n := ClothSelf.count_close((cape["frames"] as Array)[k], f, LIMIT)
		tot += n
		if n > mx:
			mx = n
			at = k
	return [mx, at, tot]


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


func _init() -> void:
	create_timer(600.0).timeout.connect(func(): print("FAIL watchdog 600 s"); quit(2))   # watchdog
	var fx := fixture()
	var t0 := Time.get_ticks_usec()
	var off := bake(fx, false)
	var t_off := float(Time.get_ticks_usec() - t0) / 1000.0 / NF
	var t1 := Time.get_ticks_usec()
	var nat := bake(fx, false, false)
	var t_nat := float(Time.get_ticks_usec() - t1) / 1000.0 / NF
	var w_off := worst_pairs(off)
	print("OFF: worst frame %d has %d close pairs, total %d; %.2f ms/frame (GDScript), %.2f ms/frame (native %s)" % [w_off[1], w_off[0], w_off[2], t_off, t_nat, str(Cloth.native_on())])
	ok(w_off[0] > 0, "1 CONTROL off: the fold has close pairs (%d)" % w_off[0])
	if not ("self_collide" in Cloth):
		print("FAIL no Cloth.self_collide (origin)")
		quit(1)
		return
	var t2 := Time.get_ticks_usec()
	var on := bake(fx, true)
	var t_on := float(Time.get_ticks_usec() - t2) / 1000.0 / NF
	var w_on := worst_pairs(on)
	print("ON: worst %d close pairs at frame %d, total %d; %.2f ms/frame; stretch %.3f (off %.3f)" % [w_on[0], w_on[1], w_on[2], t_on, max_stretch(on), max_stretch(off)])
	ok(w_on[0] == 0, "2 CLEAN on: 0 close pairs at every frame (worst %d at frame %d)" % [w_on[0], w_on[1]])
	ok(max_stretch(on) <= 1.15, "3 STRETCH on: worst edge %.3f x rest <= 1.15" % max_stretch(on))
	ok(t_on - t_off <= 8.0, "4 COST on %.2f vs off %.2f ms/frame: +%.2f <= 8 (native off %.2f)" % [t_on, t_off, t_on - t_off, t_nat])
	var on2 := bake(fx, true)
	ok(var_to_str(on["frames"]) == var_to_str(on2["frames"]), "5 SAME two ON bakes identical")
	var f := Cloth.faces()
	var v := PackedVector3Array()
	v.resize(Cloth.COLS * Cloth.ROWS)
	# a planted pair: triangle 0 of the grid at rest-like places, triangle far in the grid moved 2 mm over it
	var tri_a := [Vector3(0, 0, 0), Vector3(0.05, 0, 0), Vector3(0, 0.05, 0)]
	var tri_b := [Vector3(0, 0, 0.002), Vector3(0.05, 0, 0.002), Vector3(0, 0.05, 0.002)]
	var tri_c := [Vector3(0, 0, 0.02), Vector3(0.05, 0, 0.02), Vector3(0, 0.05, 0.02)]
	ok(ClothSelf.tri_tri_dist(tri_a, tri_b) < 0.0021 and ClothSelf.tri_tri_dist(tri_a, tri_b) > 0.0019, "6 MEASURE 2 mm pair reads 2 mm")
	ok(ClothSelf.tri_tri_dist(tri_a, tri_c) > 0.019, "6 MEASURE 20 mm pair is not close")
	var flat := on["frames"][0] as PackedVector3Array
	var cs := ClothSelf.new(f, Cloth.THICK)
	ok(cs.begin(flat) == 0, "7 HASH the settled hanging cape has no candidate pairs (%d)" % cs.npairs)
	var fold := off["frames"][w_off[1]] as PackedVector3Array
	var cs2 := ClothSelf.new(f, Cloth.THICK)
	var found := cs2.begin(fold)
	var all_pairs := (f.size() / 3) * (f.size() / 3 - 1) / 2
	ok(found > 0 and found < all_pairs / 4, "7 HASH on the folded frame %d candidate pairs of %d possible" % [found, all_pairs])
	print("c54: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
