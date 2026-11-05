extends SceneTree
## CH1e diagnostic (not a bar): the first 5 modes of the CH10 house model, code house and the e3 planted house (lines L and R unbraced).
## Per mode: period, effective modal mass fraction in x and z, and the members with the largest modal displacement.
## CH10's own "period" (sway_period) is 3 inverse iterations from the static sway shape, NOT the first mode; this lists the actual modes so the two can be compared.
## Method: deflated inverse iteration on the model's own solver (FR.solve modal, 1 iteration per call), deflating against the earlier modes with the LUMPED mass
## (extras + half of each beam's rho A L at its end nodes). The fraction is the lumped estimate too, translations only. JSON = $CH1E_JSON (default res://out/ch1/members.json).
const FR := preload("res://scripts/build/ch10_frame.gd")
const HO := preload("res://scripts/build/ch10_house.gd")
const TAU := 6.283185307179586


func lumped(model: Dictionary, n: int) -> PackedFloat64Array:
	var ml := PackedFloat64Array()
	ml.resize(n)
	var am: PackedFloat64Array = model["mass"]
	for i in n:
		ml[i] = am[i]
	var xyz: PackedFloat64Array = model["xyz"]
	var bm: PackedFloat64Array = model["beams"]
	for b in range(0, bm.size(), 12):
		var n1 := int(bm[b])
		var n2 := int(bm[b + 1])
		var L := Vector3(xyz[n1 * 3], xyz[n1 * 3 + 1], xyz[n1 * 3 + 2]).distance_to(Vector3(xyz[n2 * 3], xyz[n2 * 3 + 1], xyz[n2 * 3 + 2]))
		var m: float = bm[b + 8] * bm[b + 2] * L
		ml[n1] += 0.5 * m
		ml[n2] += 0.5 * m
	return ml


func dot_m(ml: PackedFloat64Array, a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var s := 0.0
	for i in ml.size():
		if ml[i] > 0.0:
			s += ml[i] * (a[i * 6] * b[i * 6] + a[i * 6 + 1] * b[i * 6 + 1] + a[i * 6 + 2] * b[i * 6 + 2])
	return s


func analyze(mj: Dictionary, opts: Dictionary, label: String) -> void:
	var t0 := Time.get_ticks_msec()
	var bld := HO.build(mj, opts)
	var mm := HO.to_model(bld)
	var ms := HO.masses(bld)
	var model: Dictionary = mm["model"]
	model["mass"] = ms["mass"]
	var n: int = bld["nodes"].size()
	var ml := lumped(model, n)
	var tot := 0.0
	for v in ml:
		tot += v
	print("== %s: %d nodes, lumped mass %.0f kg (extras %.0f), build %d ms" % [label, n, tot, ms["total_kg"], Time.get_ticks_msec() - t0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var modes: Array = []
	for k in 5:
		var x := PackedFloat64Array()
		x.resize(n * 6)
		for i in n:
			for d in 3:
				x[i * 6 + d] = rng.randf_range(-1.0, 1.0)
		var rq_prev := 0.0
		var rq := 0.0
		var its := 0
		for it in 50:
			for q in modes:
				var ph: PackedFloat64Array = q
				var c := dot_m(ml, ph, x) / dot_m(ml, ph, ph)
				for i in x.size():
					x[i] -= c * ph[i]
			var r := FR.solve(model, {"type": "modal", "start": x, "iters": 1})
			if r.has("error"):
				print("   solve error ", r["error"])
				return
			x = r["phi"]
			var rqa: PackedFloat64Array = r["rq"]
			rq = rqa[rqa.size() - 1]
			its = it + 1
			if it > 3 and absf(rq - rq_prev) < 1e-7 * rq:
				break
			rq_prev = rq
		modes.append(x.duplicate())
		var om := sqrt(rq)
		var gx := 0.0
		var gz := 0.0
		var den := 0.0
		var big := 0.0
		for i in n:
			if ml[i] > 0.0:
				gx += ml[i] * x[i * 6]
				gz += ml[i] * x[i * 6 + 2]
				den += ml[i] * (x[i * 6] * x[i * 6] + x[i * 6 + 1] * x[i * 6 + 1] + x[i * 6 + 2] * x[i * 6 + 2])
			big = maxf(big, Vector3(x[i * 6], x[i * 6 + 1], x[i * 6 + 2]).length())
		# members by largest end displacement
		var best := {}
		for e in bld["elems"]:
			if e.get("beam", -1) < 0:
				continue
			var nm: String = bld["beams"][e["beam"]]["name"]
			var d := 0.0
			for nd in [e["n1"], e["n2"]]:
				d = maxf(d, Vector3(x[nd * 6], x[nd * 6 + 1], x[nd * 6 + 2]).length() / big)
			best[nm] = maxf(best.get(nm, 0.0), d)
		var names := best.keys()
		names.sort_custom(func(a, b): return best[a] > best[b])
		var top := []
		for j in 5:
			top.append("%s %.2f" % [names[j], best[names[j]]])
		print("   mode %d: T %.4f s (f %.2f Hz, %d its)  eff mass x %.3f z %.3f   largest: %s" % [k + 1, TAU / om, om / TAU, its, gx * gx / den / tot, gz * gz / den / tot, ", ".join(top)])
	print("   (%d ms)" % (Time.get_ticks_msec() - t0))


func _init() -> void:
	var path := OS.get_environment("CH1E_JSON")
	if path == "":
		path = "res://out/ch1/members.json"
	print("members file: ", path)
	var mj = JSON.parse_string(FileAccess.get_file_as_string(path))
	print("members: ", mj["members"].size())
	var base := {"unsnap_layout": true} if OS.get_environment("CH1E_UNSNAP") == "1" else {}
	var o1 := base.duplicate()
	var o2 := base.duplicate()
	o2["remove_lines"] = ["L", "R"]
	analyze(mj, o1, "code house")
	analyze(mj, o2, "e3 planted (L and R unbraced)")
	print("ch1e_modes: 0 fail")
	quit(0)
