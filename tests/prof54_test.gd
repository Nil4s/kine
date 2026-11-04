extends SceneTree
const FPS := 30
const NF := 61
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



func _init():
	create_timer(300.0).timeout.connect(func(): quit(2))
	var fx = fixture()
	var off = bake(fx, false)
	var f = Cloth.faces()
	for k in [0, 30, 44, 53]:
		var fr: PackedVector3Array = off["frames"][k]
		var t0 = Time.get_ticks_usec()
		var cs = ClothSelf.new(f, 0.006)
		var tinit = (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		var np = 0
		for r in 20: np = cs.begin(fr)
		var tb = (Time.get_ticks_usec() - t0) / 1000.0 / 20
		var pinned = PackedByteArray(); pinned.resize(192)
		var pp = fr.duplicate()
		t0 = Time.get_ticks_usec()
		for r in 10: cs.solve(pp, pinned, true)
		var tf = (Time.get_ticks_usec() - t0) / 1000.0 / 10
		t0 = Time.get_ticks_usec()
		for r in 10: cs.solve(pp, pinned)
		var ta = (Time.get_ticks_usec() - t0) / 1000.0 / 10
		print("frame %d: init %.2f ms, begin %.2f ms (%d pairs), full solve %.2f ms, active solve %.2f ms (%d active)" % [k, tinit, tb, np, tf, ta, cs.active.size()])
	quit()
