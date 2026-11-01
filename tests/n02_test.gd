extends SceneTree
## godot --path . -s tests/n02_test.gd     (native port n02: KineMeshCheckNative, native/src/kine_meshcheck_native.cpp; needs the CAD DLL for the real parts)
## The Export dialog's mesh scans on REAL kernel bodies (MeshExport.bodies_of), GDScript vs native in one process (MeshCheckDoor.force_gd):
##   PrintCheck.scan (thin walls, overhangs, floating pieces: the numbers), MeshExport.check (closed edges), signed_volume, the size box,
##   PartStand's feet hull (tip-over). Tolerance: counts identical; floats within 1e-5 relative (native sums in the same order, so usually bit-equal).
## Parts: 45-hole perforated plate, gear pair, plus the s115 cases (thin slots, T overhang, lifted box, stacked / gapped / pierced / nested pieces).
## Timings: median of 5 (ms), GDScript vs native; app-level: the Export checklist (MeshExport.check_lines, cache cleared) and PartStand.check.
## Without the DLL every native bar says SKIP and the GDScript path is exercised alone.
const REPS := 5
const TOL := 1e-5
var fails := 0
var skips := 0
var table := []


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


static func med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]


func near(a: float, b: float) -> bool:
	if is_inf(a) or is_inf(b):
		return is_inf(a) and is_inf(b)
	return absf(a - b) <= TOL * maxf(1.0, maxf(absf(a), absf(b)))


func box_rec(nm: String, w: float, h: float, d: float, y0 := 0.0) -> Dictionary:
	var rec := Part.make(nm)
	var fs: Array = rec["features"]
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, y0), Vector2(w, y0 + h))]), "extrude", d, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


func add_ex(rec: Dictionary, plane: String, ents: Array, dist: float, op: String) -> void:
	var fs: Array = rec["features"]
	PartTemplates._ex(fs, PartTemplates._sk(fs, plane, ents), "extrude", dist, op)
	rec["seq"] = fs.size()


func slot_rec(nm: String, sx0: float, sx1: float) -> Dictionary:
	var rec := box_rec(nm, 20.0, 10.0, 10.0)
	add_ex(rec, "front", [PartTemplates._rect(Vector2(sx0, 2), Vector2(sx1, 8))], 10.0, "cut")
	return rec


func plate_rec() -> Dictionary:
	var rec := Part.make("Perforated plate")
	add_ex(rec, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(120, 60))], 4.0, "new")
	var holes := []
	for i in 9:
		for j in 5:
			holes.append({"k": "circle", "c": [10.0 + i * 12.5, 8.0 + j * 11.0], "r": 3.0})
	add_ex(rec, "top", holes, 8.0, "cut")
	rec["kept"] = true
	return rec


func gear_rec() -> Dictionary:
	var rec := Part.make("Gear pair")
	rec["features"] = PartTemplates._gear_pair_features({"teeth": 15.0, "ratio": 2.0, "module": 2.0, "thickness": 10.0})
	rec["seq"] = (rec["features"] as Array).size()
	rec["kept"] = true
	return rec


func t_rec() -> Dictionary:
	var rec := Part.make("T shape")
	add_ex(rec, "front", PartTemplates._poly([Vector2(10, 0), Vector2(20, 0), Vector2(20, 20), Vector2(30, 20), Vector2(30, 30), Vector2(0, 30), Vector2(0, 20), Vector2(10, 20)]), 10.0, "new")
	rec["kept"] = true
	return rec


func two_box(nm: String, y0: float, x0 := 5.0, x1 := 15.0, h := 5.0) -> Dictionary:
	var rec := box_rec(nm, 20.0, 5.0, 10.0)
	add_ex(rec, "front", [PartTemplates._rect(Vector2(x0, y0), Vector2(x1, y0 + h))], 10.0, "new")
	return rec


func pierce_rec() -> Dictionary:
	# a tall bar on the bed and a lifted flat bar through it: the second piece's edges cross the first one's faces
	var rec := box_rec("Pierce", 6.0, 30.0, 6.0)
	add_ex(rec, "right", [PartTemplates._rect(Vector2(-10, 10), Vector2(10, 14))], 30.0, "new")
	return rec


func nested_rec() -> Dictionary:
	var rec := box_rec("Nested", 30.0, 30.0, 30.0)
	add_ex(rec, "front", [PartTemplates._rect(Vector2(10, 10), Vector2(20, 20))], 10.0, "new")
	return rec


func report_keys(d: Dictionary) -> String:
	return "walls %d thin %.4f over %.4f float %d low %.4f" % [int(d["walls"]), float(d["thinnest"]), float(d["over_mm2"]), int(d["floating"]), float(d["lowest"])]


func run_part(label: String, rec: Dictionary, timing: bool) -> void:
	var bo := MeshExport.bodies_of(rec)
	var bodies: Array = bo["bodies"]
	if bodies.is_empty():
		ok(false, label + ": no bodies (" + String(bo["why"]) + ")")
		return
	var tris := 0
	for b in bodies:
		tris += (b["t"] as PackedInt32Array).size() / 3
	MeshCheckDoor.force_gd = true
	var g := PrintCheck.scan(bodies)
	MeshCheckDoor.force_gd = false
	if not MeshCheckDoor.native_on():
		print("SKIP %s native bars (no KineMeshCheckNative); GDScript: %s" % [label, report_keys(g)])
		skips += 1
		return
	var n := PrintCheck.scan(bodies)
	ok(int(g["walls"]) == int(n["walls"]) and int(g["floating"]) == int(n["floating"]) and near(float(g["thinnest"]), float(n["thinnest"])) and near(float(g["over_mm2"]), float(n["over_mm2"])) and near(float(g["lowest"]), float(n["lowest"])),
		"%s (%d tris, %d bodies) scan equal: GD [%s] native [%s]" % [label, tris, bodies.size(), report_keys(g), report_keys(n)])
	# the closed-edge count, volume and box, per body
	var all_eq := true
	for b in bodies:
		MeshCheckDoor.force_gd = true
		var cg := MeshExport.check(b)
		var vg := MeshExport.signed_volume(b)
		MeshCheckDoor.force_gd = false
		var cn := MeshExport.check(b)
		var vn := MeshExport.signed_volume(b)
		if int(cg["open"]) != int(cn["open"]) or int(cg["bad"]) != int(cn["bad"]) or int(cg["tris"]) != int(cn["tris"]) or bool(cg["closed"]) != bool(cn["closed"]) or not near(vg, vn):
			all_eq = false
			print("  mismatch: GD %s %.4f native %s %.4f" % [str(cg), vg, str(cn), vn])
	MeshCheckDoor.force_gd = true
	var rg := MeshExport.report(bodies)
	MeshCheckDoor.force_gd = false
	var rn := MeshExport.report(bodies)
	ok(all_eq and (rg["lines"] as Array) == (rn["lines"] as Array) and int(rg["open"]) == int(rn["open"]) and (rg["size"] as Vector3).is_equal_approx(rn["size"]),
		"%s check / signed_volume / report equal (open %d bad %d, size %s)" % [label, int(rn["open"]), int(rn["bad"]), str(rn["size"])])
	# the words, end to end (cache cleared)
	PrintCheck._cache = {}
	MeshCheckDoor.force_gd = true
	var wg := PrintCheck.analyse(bodies)
	MeshCheckDoor.force_gd = false
	var wn := PrintCheck.analyse(bodies)
	ok((wg["lines"] as Array) == (wn["lines"] as Array), "%s Ready-to-print words identical (%s)" % [label, String((wn["lines"] as Array)[0]).left(50)])
	if not timing:
		return
	var tg := []
	var tn := []
	for r in REPS:
		MeshCheckDoor.force_gd = true
		var t0 := Time.get_ticks_usec()
		PrintCheck.scan(bodies)
		tg.append((Time.get_ticks_usec() - t0) / 1000.0)
		MeshCheckDoor.force_gd = false
		t0 = Time.get_ticks_usec()
		PrintCheck.scan(bodies)
		tn.append((Time.get_ticks_usec() - t0) / 1000.0)
	table.append(["PrintCheck.scan " + label, med(tg), med(tn)])
	tg = []
	tn = []
	for r in REPS:
		MeshCheckDoor.force_gd = true
		var t0 := Time.get_ticks_usec()
		MeshExport.report(bodies)
		for b in bodies:
			MeshExport.signed_volume(b)
		tg.append((Time.get_ticks_usec() - t0) / 1000.0)
		MeshCheckDoor.force_gd = false
		t0 = Time.get_ticks_usec()
		MeshExport.report(bodies)
		for b in bodies:
			MeshExport.signed_volume(b)
		tn.append((Time.get_ticks_usec() - t0) / 1000.0)
	table.append(["report+signed_volume " + label, med(tg), med(tn)])
	# app level: the Export dialog's checklist = bodies_of (kernel + weld) + report + Ready to print
	var ag := []
	var an := []
	var bg := []
	for r in REPS:
		PrintCheck._cache = {}
		MeshCheckDoor.force_gd = true
		var t0 := Time.get_ticks_usec()
		var bo1 := MeshExport.bodies_of(rec)
		var t1 := Time.get_ticks_usec()
		MeshExport.report(bo1["bodies"])
		PrintCheck.analyse(bo1["bodies"])
		ag.append((Time.get_ticks_usec() - t0) / 1000.0)
		bg.append((Time.get_ticks_usec() - t1) / 1000.0)
		PrintCheck._cache = {}
		MeshCheckDoor.force_gd = false
		t0 = Time.get_ticks_usec()
		var bo2 := MeshExport.bodies_of(rec)
		MeshExport.report(bo2["bodies"])
		PrintCheck.analyse(bo2["bodies"])
		an.append((Time.get_ticks_usec() - t0) / 1000.0)
	table.append(["APP Export checklist (bodies_of+checks) " + label, med(ag), med(an)])
	table.append(["  of which the checks alone (GDScript side) " + label, med(bg), med(an) - (med(ag) - med(bg))])
	MeshCheckDoor.force_gd = false


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL, the real parts cannot be built")
		print("n02: 1 fail")
		quit(1)
		return
	print("native on: %s" % str(MeshCheckDoor.native_on()))
	run_part("45-hole plate", plate_rec(), true)
	run_part("gear pair", gear_rec(), true)
	run_part("T shape", t_rec(), false)
	run_part("plain box", box_rec("Plain", 20.0, 5.0, 10.0), false)
	run_part("thin slot 0.5", slot_rec("Thin one", 0.5, 17.0), false)
	run_part("thin slots x2", slot_rec("Thin two", 0.5, 19.5), false)
	run_part("walls 1.0", slot_rec("Wall 1", 1.0, 19.0), false)
	run_part("lifted box", box_rec("Lifted", 20.0, 5.0, 10.0, 5.0), false)
	run_part("stacked pieces", two_box("Stack", 5.0), false)
	run_part("gap pieces", two_box("Gap", 8.0), false)
	run_part("pierce", pierce_rec(), false)
	run_part("nested", nested_rec(), false)

	# the tip-over feet hull on the display meshes of both big parts, then PartStand.check both ways
	for pr in [["45-hole plate", plate_rec()], ["gear pair", gear_rec()], ["T shape", t_rec()]]:
		var res := Part.replay(pr[1], -1, {"props": true})
		var mesh: ArrayMesh = res["mesh"]
		var verts := PackedVector3Array()
		for s in mesh.get_surface_count():
			verts.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
		MeshCheckDoor.force_gd = true
		var hg := PartStand._feet_hull(verts)
		var sg := PartStand.check(pr[1])
		MeshCheckDoor.force_gd = false
		if not MeshCheckDoor.native_on():
			skips += 1
			print("SKIP %s hull native" % pr[0])
			continue
		var hn := PartStand._feet_hull(verts)
		var same := hg.size() == hn.size()
		if same:
			for i in hg.size():
				if not (hg[i] as Vector2).is_equal_approx(hn[i]):
					same = false
		var sn := PartStand.check(pr[1])
		ok(same and near(float(sg["margin_mm"]), float(sn["margin_mm"])) and String(sg["say"]) == String(sn["say"]),
			"%s feet hull equal (%d verts, %d hull points), tip-over margin %.4f vs %.4f mm" % [pr[0], verts.size(), hn.size(), float(sg["margin_mm"]), float(sn["margin_mm"])])
		var tg := []
		var tn := []
		for r in REPS:
			MeshCheckDoor.force_gd = true
			var t0 := Time.get_ticks_usec()
			PartStand._feet_hull(verts)
			tg.append((Time.get_ticks_usec() - t0) / 1000.0)
			MeshCheckDoor.force_gd = false
			t0 = Time.get_ticks_usec()
			PartStand._feet_hull(verts)
			tn.append((Time.get_ticks_usec() - t0) / 1000.0)
		table.append(["PartStand feet hull " + str(pr[0]) + " (%d verts)" % verts.size(), med(tg), med(tn)])
		var ug := []
		var un := []
		for r in REPS:
			MeshCheckDoor.force_gd = true
			var t0 := Time.get_ticks_usec()
			PartStand.check(pr[1])
			ug.append((Time.get_ticks_usec() - t0) / 1000.0)
			MeshCheckDoor.force_gd = false
			t0 = Time.get_ticks_usec()
			PartStand.check(pr[1])
			un.append((Time.get_ticks_usec() - t0) / 1000.0)
		table.append(["APP PartStand.check (the 300 ms COM reading) " + str(pr[0]), med(ug), med(un)])

	print("---- timings (median of %d, ms)" % REPS)
	print("%-70s %10s %10s %8s" % ["what", "GDScript", "native", "factor"])
	for r in table:
		print("%-70s %10.2f %10.2f %7.1fx" % [r[0], r[1], r[2], r[1] / maxf(r[2], 0.001)])
	print("n02: %d fail%s" % [fails, " (%d skipped, no DLL)" % skips if skips > 0 else ""])
	quit(1 if fails > 0 else 0)
