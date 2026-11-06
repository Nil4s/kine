extends SceneTree
## L44 diagnosis (information only, no bars): where does a freely sliding block lose speed? Prints mean u by region and time. wtest.sh l44diag
func _init() -> void:
	var h := 0.01
	for rows in [3, 6]:
		var F = Fluid.make()
		F.setup(62, 10, 8, h, Vector3.ZERO)
		F.set_params(0.0, 0.2, 0.5, 0.005, 300, 1e-7)
		F.set_threads(1)
		F.add_fluid_box(Vector3(h, h, h), Vector3(0.31, (1 + rows) * h, 7.0 * h), Vector3(1.0, 0, 0), 1)
		var t := 0.0
		for T in [0.05, 0.1, 0.25]:
			F.advance(T - t)
			t = T
			var d: PackedFloat64Array = F.particle_data()
			var n := d.size() / 6
			var xmin := 1e9
			var xmax := -1e9
			for p in n:
				xmin = minf(xmin, d[6 * p])
				xmax = maxf(xmax, d[6 * p])
			var mid := 0.0
			var nm := 0
			var lowrow := 0.0
			var nl := 0
			var all := 0.0
			for p in n:
				all += d[6 * p + 3]
				if d[6 * p] > xmin + 0.35 * (xmax - xmin) and d[6 * p] < xmax - 0.35 * (xmax - xmin):
					mid += d[6 * p + 3]
					nm += 1
				if d[6 * p + 1] < 2.0 * h:
					lowrow += d[6 * p + 3]
					nl += 1
			print("DIAG rows %d t %.2f: mean u all %.4f  middle %.4f  bottom row %.4f   x range %.3f..%.3f" % [rows, t, all / n, mid / maxi(nm, 1), lowrow / maxi(nl, 1), xmin, xmax])
	print("l44diag: 0 fail")
	quit(0)
