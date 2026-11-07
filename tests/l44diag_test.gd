extends SceneTree
## L44 diagnosis (information only, no bars). wtest.sh l44diag
##  A) where a freely sliding block loses speed (floor row) at two cell sizes
##  B) L1 (Lobovsky front speed tau 1..2) for variants: wall law off / on, res 20 / 30
##  C) ch8 (e) mug pour: where does the water that is not "held" go
const G := 9.81

func _front(F: Object, h: float, a: float, x0: float) -> float:
	var xf := 0.0
	for p in F.positions():
		if p.y < h + 0.15 * a:
			xf = maxf(xf, p.x)
	return (xf - x0) / a


func _slide(h: float) -> void:
	var s := 0.01 / h
	var F = Fluid.make()
	F.setup(int(62 * s), int(10 * s), int(8 * s), h, Vector3.ZERO)
	F.set_params(0.0, 0.2, 0.5, 0.005, 300, 1e-7)
	F.set_threads(4)
	F.add_fluid_box(Vector3(h, h, h), Vector3(0.31, 0.01 + 6 * 0.01, 7.0 * 0.01 + h), Vector3(1.0, 0, 0), 1)
	F.advance(0.1)
	var d: PackedFloat64Array = F.particle_data()
	var n := d.size() / 6
	var lowrow := 0.0
	var nl := 0
	var all := 0.0
	for p in n:
		all += d[6 * p + 3]
		if d[6 * p + 1] < 0.01 + h:
			lowrow += d[6 * p + 3]
			nl += 1
	print("DIAG A h %.4f t 0.1: mean u %.4f  bottom band (y < 10 mm + h) %.4f" % [h, all / n, lowrow / maxi(nl, 1)])


func _lob(res: int, law: int) -> void:
	var H := 0.30
	var h := H / res
	var F = Fluid.make()
	var nxr := int(round(0.6 / h))
	var nx := nxr + int(round(1.01 / h)) + 3
	var ny := int(round(0.6 / h)) + 2
	var nz := int(round(0.15 / h)) + 2
	F.setup(nx, ny, nz, h, Vector3.ZERO)
	F.set_params(G, 0.2, 0.5, 0.005, 300, 1e-7)
	F.set_threads(4)
	F.set_wall_law(law, 1e-6)
	F.add_fluid_box(Vector3(h, h, h), Vector3((nxr + 1) * h, (res + 1) * h, (nz - 1) * h), Vector3.ZERO, 1)
	var xg := (nxr + 1) * h
	var top := (res + 1) * h
	var t := 0.0
	var z := []
	for tau in [1.0, 2.0]:
		var tend: float = tau * sqrt(H / G)
		while t < tend - 1e-9:
			var d := minf(0.002, tend - t)
			F.clear_cut()
			var y0 := 3.46 * t
			if y0 < top:
				F.add_cut_box(Vector3(xg, y0, 0.0), Vector3(xg + h, top + h, nz * h))
			F.advance(d)
			t += d
		z.append(_front(F, h, H, xg))
	print("DIAG B L1 res %d law mask %d: Z1 %.3f Z2 %.3f  speed %.4f sqrt(gH)  (band 1.29..1.61)" % [res, law, z[0], z[1], z[1] - z[0]])


func _mug() -> void:
	if not Part.available():
		print("DIAG C no CAD")
		return
	var F = Fluid.make()
	F.set_threads(8)
	var m := FluidScenes.mug(F, 0.003)
	var h: float = m["h"]
	var cx: float = m["cx"]
	var cz: float = m["cz"]
	var rim: float = m["rim"]
	var cap: float = m["cap"]
	var n0 := 0
	var poured := 0.0
	var t := 0.0
	var seed_i := 100
	var pouring := true
	var t_end := 0.0
	var half := 0.014
	var v0 := 0.0
	while true:
		F.advance(0.003)
		t += 0.003
		if pouring:
			var n: int = F.add_fluid_box(Vector3(cx - half, rim + 0.03, cz - half), Vector3(cx + half, rim + 0.03 + h, cz + half), Vector3(0, -1.0, 0), seed_i)
			seed_i += 1
			poured += float(n) / 8.0 * h * h * h
			if poured >= 1.5 * cap:
				pouring = false
				t_end = t + 0.8
		if (not pouring and t >= t_end) or t > 4.0:
			break
	var ps: PackedVector3Array = F.positions()
	var d: PackedFloat64Array = F.particle_data()
	var vol := h * h * h / 8.0
	var held := 0
	var above := 0
	var wallband := 0
	var spilled := 0
	var other := 0
	var vair := 0.0
	var nair := 0
	for i in ps.size():
		var p := ps[i]
		var r := Vector2(p.x - cx, p.z - cz).length()
		if r < m["R_in"] and p.y < rim:
			held += 1
		elif r < m["R_in"]:
			above += 1
			vair += absf(d[6 * i + 4])
			nair += 1
		elif r > m["R_out"] + 2.0 * h and p.y < 4.0 * h + 0.003:
			spilled += 1
		elif r <= m["R_out"] + 2.0 * h:
			wallband += 1
		else:
			other += 1
	var N := ps.size()
	print("DIAG C poured %.3f L (%d particles), cup %.3f L, t %.2f s. held %.3f L (%.0f %% of cap) | above rim in cup column %.3f L (mean |vy| %.2f m/s) | outer wall band %.3f L | on table (spilled) %.3f L | elsewhere outside %.3f L | in-mesh %d" % [poured * 1000.0, N, cap * 1000.0, t, held * vol * 1000.0, 100.0 * held * vol / cap, above * vol * 1000.0, vair / maxi(nair, 1), wallband * vol * 1000.0, spilled * vol * 1000.0, other * vol * 1000.0, F.particles_in_mesh(m["verts"], m["tris"])])
	print("DIAG C volume: seeded %.3f L, particles now %.3f L, smooth-volume ratio vs particles %.4f" % [poured * 1000.0, N * vol * 1000.0, F.volume_smooth()])


func _init() -> void:
	_slide(0.01)
	_slide(0.005)
	for res in [20, 30]:
		for law in [0, 6]:
			_lob(res, law)
	_mug()
	print("l44diag: 0 fail")
	quit(0)
