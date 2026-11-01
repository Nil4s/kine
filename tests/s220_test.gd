extends SceneTree
## godot --path . --position 4000,4000 -s tests/s220_test.gd     (item 220 MODELING VIEW WITH MATHS: scripts/part_facts.gd + scripts/part_assert.gd, wired as
## agent_tools part_facts / part_assert, poser_cli part_facts / part_assert, and the AI box's tools when a Part is open; needs the CAD DLL)
## The parts have KNOWN answers (sizes in mm written here, never read back from the code under test); every number is measured from the built solids.
##   1 CUBES    two 20 mm cubes 10 mm apart: volume 8000, box 20, gap 10.000; every grammar kind with a PASS and a planted FAIL whose miss is exact
##   2 OVERLAP  cube A and a cube 5 mm into it: common volume 2000 mm3 exactly; inside / overlaps / clearance (interference) / one solid; a small cube inside a big one
##   3 PEG      a 10 mm peg in a 10.2 mm hole: clearance 0.100 mm (kernel-refined), size lines, axis along z, floor
##   4 AXES     three bars patterned 120 deg apart: axis angles 120.0, a planted 90 fails with miss 29.5
##   5 FINS     a core with five discs fused on: "has 5 fins" passes, "has 6" misses by 1
##   6 ENGINE   the Anzani radial of engine_compare (219 features, 49 bodies): facts + the 10 asserts a screenshot cannot answer
##   7 DOORS    agent_tools part_facts / part_assert on the live part (save keeps lines in the record, survive save+load), the CLI as a child process,
##              the AI box lists the two tools only with a part open, an unread line gets the grammar back
## Shots: C:/Temp/claude/s220/peg.png (the peg part in the Part workspace), C:/Temp/claude/s220/facts.png (the facts text of it, drawn)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s220"
const DIRT := "user://s220_test"
const ENGINE := "res://tests/data/s220_engine_part.json"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func idle(n := 3) -> void:
	for i in n:
		await process_frame


# ------------------------------------------------------------------ building parts (feature records, as the app's own steps)
func add(rec: Dictionary, t: String, f: Dictionary, nm := "") -> String:
	var fields := f.duplicate()
	if nm != "":
		fields["name"] = nm
	var nf := Part.new_feature(rec, t, fields)
	(rec["features"] as Array).append(nf)
	return String(nf["id"])


func rect_body(rec: Dictionary, x0: float, y0: float, x1: float, y1: float, dist: float, nm: String, op := "new", plane := "front") -> void:
	var sk := add(rec, "sketch", {"plane": plane, "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []}, nm + " sketch")
	add(rec, "extrude", {"sketch": sk, "dist": dist, "both": false, "op": op}, nm)


func disc_body(rec: Dictionary, cx: float, cy: float, r: float, dist: float, nm: String, op := "new", plane := "front") -> void:
	var sk := add(rec, "sketch", {"plane": plane, "ents": [{"k": "circle", "c": [cx, cy], "r": r}], "dims": []}, nm + " sketch")
	add(rec, "extrude", {"sketch": sk, "dist": dist, "both": false, "op": op}, nm)


func two_cubes(gap_x: float) -> Dictionary:
	var rec := Part.make("two cubes")
	rect_body(rec, 0, 0, 20, 20, 20, "Cube A")
	rect_body(rec, 20.0 + gap_x, 0, 40.0 + gap_x, 20, 20, "Cube B")
	return rec


func overlap_cubes() -> Dictionary:
	var rec := Part.make("overlap")
	rect_body(rec, 0, 0, 20, 20, 20, "Cube A")
	rect_body(rec, 15, 0, 35, 20, 20, "Cube B")   # 5 mm into A: 5 x 20 x 20 = 2000 mm3 common
	rect_body(rec, 5, 5, 10, 10, 5, "Tiny")       # a 5 mm cube wholly inside A (z 0..5)
	return rec


func peg_part() -> Dictionary:
	var rec := Part.make("peg")
	rect_body(rec, 0, 0, 40, 40, 20, "Block")
	disc_body(rec, 20, 20, 5.1, 30, "Hole", "cut")
	disc_body(rec, 20, 20, 5.0, 30, "Peg")
	return rec


func bars_part() -> Dictionary:
	var rec := Part.make("bars")
	rect_body(rec, 10, -2, 50, 2, 4, "Bar")   # 40 x 4 x 4, its long axis along x, its middle 30 mm from the centre
	add(rec, "pattern", {"body": 0, "kind": "circular", "count": 3, "axis": "z", "deg": 360.0, "op": "new"}, "Ring of bars")
	return rec


func fins_part() -> Dictionary:
	var rec := Part.make("fins")
	disc_body(rec, 0, 0, 5, 17, "Core")
	for k in 5:
		var pl := add(rec, "plane", {"from": "front", "mm": 1.0 + 3.0 * k}, "plane %d" % k)
		disc_body(rec, 0, 0, 10, 1.0, "Fin %d" % (k + 1), "join", pl)
	return rec


## a line's result in a run: {"pass", "miss" mm / deg / mm3, "say"}
func line_res(rec: Dictionary, lines: Array) -> Array:
	var r := PartAssert.run(rec, lines)
	return r["results"]


func miss_of(x: Dictionary) -> float:
	return float((x.get("miss", {}) as Dictionary).get("value", 0.0)) if x.has("miss") and x["miss"]["value"] != null else 0.0


func expect(rec: Dictionary, line: String, want_pass: bool, want_miss: float, tol: float, tag: String) -> void:
	var x: Dictionary = line_res(rec, [line])[0]
	var good: bool = bool(x.get("ok", false)) and bool(x["pass"]) == want_pass and (want_pass or near(miss_of(x), want_miss, tol))
	ok(good, "%s  '%s' -> %s, miss %s (wanted %s%s)  %s" % [tag, line, "PASS" if x.get("pass", false) else "FAIL", str(miss_of(x)), "pass" if want_pass else "fail by %s +-%s" % [want_miss, tol], "", x.get("say", x.get("error", ""))])


func facts_line(f: Dictionary, n: int) -> String:
	return String(f["lines"][n])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the parts cannot be built")
		quit(1)
		return
	# ------------------------------------------------------------------ 1 CUBES
	var rc := two_cubes(10.0)
	var fc := PartFacts.facts(rc)
	ok(bool(fc["ok"]) and int(fc["bodies"]) == 2 and near(float(fc["data"][0]["volume_mm3"]), 8000.0, 0.01) and near(float(fc["data"][1]["volume_mm3"]), 8000.0, 0.01),
		"1 two cubes: 2 bodies, volumes %s / %s mm3 (wanted 8000)" % [str(fc["data"][0]["volume_mm3"]), str(fc["data"][1]["volume_mm3"])])
	var d0: Dictionary = fc["data"][0]
	var sz := Vector3(d0["box_max"]) - Vector3(d0["box_min"])
	ok(near(sz.x, 20.0, 0.001) and near(sz.y, 20.0, 0.001) and near(sz.z, 20.0, 0.001), "1 cube A box %s mm (wanted 20 x 20 x 20)" % str(sz))
	var gp: Array = d0["near"]
	ok(gp.size() == 1 and int(gp[0]["body"]) == 2 and near(float(gp[0]["gap_mm"]), 10.0, 0.001), "1 the contact graph: cube A is NEAR body 2 by %s mm (wanted 10.000)" % str(gp))
	ok(String(fc["data"][0]["kind"]) == "cubic" and String(fc["lines"][1]).contains("cubic"), "1 a cube has no revolve axis: '%s'" % facts_line(fc, 1).left(120))
	var xg: Dictionary = line_res(rc, ["body 1 touches body 2"])[0]
	ok(xg["pass"] == false and near(float(xg.get("gap_mm", -1)), 10.0, 0.001), "1 exact gap, kernel-read: %s mm (wanted 10.000)" % str(xg.get("gap_mm")))
	expect(rc, "body 1 at least 10 mm from body 2", true, 0.0, 0.0, "1")
	expect(rc, "body 1 at least 10.5 mm from body 2", false, 0.5, 0.002, "1")
	expect(rc, "body 1 at most 9 mm from body 2", false, 1.0, 0.002, "1")
	expect(rc, "body 1 touches body 2", false, 10.0, 0.002, "1")
	expect(rc, "body 1 touches body 2 clearance 9.9-10.1 mm", true, 0.0, 0.0, "1")
	expect(rc, "body 1 touches body 2 clearance 0-5 mm", false, 5.0, 0.002, "1")
	expect(rc, "cube a touches cube b clearance at least 12 mm", false, 2.0, 0.002, "1 (by name)")
	expect(rc, "count bodies like cube = 2", true, 0.0, 0.0, "1")
	expect(rc, "count bodies like cube = 3", false, 1.0, 0.0, "1")
	expect(rc, "count bodies like cube >= 1", true, 0.0, 0.0, "1")
	expect(rc, "one solid", false, 1.0, 0.0, "1")
	expect(rc, "all bodies above the floor", true, 0.0, 0.0, "1")
	expect(rc, "no overlaps", true, 0.0, 0.0, "1")
	var rfl := two_cubes(10.0)
	rect_body(rfl, 0, -3, 20, 0, 20, "Sunk")   # reaches 3 mm under the floor (y -3 .. 0)
	expect(rfl, "all bodies above the floor", false, 3.0, 0.002, "1")
	expect(rfl, "cube a above the floor", true, 0.0, 0.0, "1")
	# ------------------------------------------------------------------ 2 OVERLAP
	var ro := overlap_cubes()
	var fo := PartFacts.facts(ro)
	var ovs: Array = fo["overlaps"]
	var o12 := 0.0
	var o13 := 0.0
	for o in ovs:
		if int(o["a"]) == 1 and int(o["b"]) == 2:
			o12 = float(o["mm3"])
		if int(o["a"]) == 1 and int(o["b"]) == 3:
			o13 = float(o["mm3"])
	ok(near(o12, 2000.0, 0.5) and near(o13, 125.0, 0.5), "2 overlap volumes from the kernel: A x B %s mm3 (wanted 2000), A x Tiny %s mm3 (wanted 125)" % [str(o12), str(o13)])
	expect(ro, "no overlaps", false, 2000.0, 0.5, "2")
	expect(ro, "no overlaps except cube a/cube b", false, 125.0, 0.5, "2")
	expect(ro, "no overlaps except cube a/cube b, cube a/tiny", true, 0.0, 0.0, "2")
	expect(ro, "body 1 touches body 2 clearance 0.0-0.2 mm", false, 2000.0, 0.5, "2 (interference)")
	expect(ro, "body 1 touches body 2", true, 0.0, 0.0, "2")
	expect(ro, "body 3 inside body 1", true, 0.0, 0.0, "2")
	expect(ro, "body 2 inside body 1", false, 6000.0, 0.5, "2")
	expect(ro, "tiny inside cube a", true, 0.0, 0.0, "2 (by name)")
	expect(ro, "one solid", true, 0.0, 0.0, "2")
	# ------------------------------------------------------------------ 3 PEG
	var rp := peg_part()
	var fp := PartFacts.facts(rp)
	ok(int(fp["bodies"]) == 2 and String(fp["data"][1]["name"]) == "Peg" and String(fp["data"][0]["name"]) == "Block", "3 peg part: 2 bodies named from their features: %s, %s" % [fp["data"][0]["name"], fp["data"][1]["name"]])
	var pd: Dictionary = fp["data"][1]
	ok(String(pd["kind"]) == "round" and near(float(pd["radius_mm"]), 5.0, 0.01) and near(float(pd["len_mm"]), 30.0, 0.01) and near(absf(Vector3(pd["axis"]).z), 1.0, 1e-6),
		"3 peg is a body of revolution: axis %s, radius %s (wanted 5), length %s (wanted 30)" % [str(pd["axis"]), str(pd["radius_mm"]), str(pd["len_mm"])])
	var xp: Dictionary = line_res(rp, ["peg touches block clearance 0.0-0.2 mm"])[0]
	ok(bool(xp["pass"]) and near(float(xp.get("gap_mm", -1)), 0.1, 0.0005), "3 peg-in-hole clearance %s mm (wanted 0.100), line %s" % [str(xp.get("gap_mm")), xp["say"]])
	expect(rp, "peg touches block clearance 0.15-0.2 mm", false, 0.05, 0.001, "3")
	expect(rp, "peg touches block clearance 0.0-0.05 mm", false, 0.05, 0.001, "3")
	expect(rp, "peg touches block", false, 0.1, 0.001, "3")
	expect(rp, "peg inside block", false, PI * 25.0 * 30.0, 3.0, "3 (the peg sits in the hole, which is air: all 2356 mm3 of it is outside the block material)")
	expect(rp, "peg diameter = 10 +-0.05", true, 0.0, 0.0, "3")
	expect(rp, "peg diameter = 10.5 +-0.05", false, 0.45, 0.01, "3")
	expect(rp, "peg length = 30 +-0.05", true, 0.0, 0.0, "3")
	expect(rp, "peg radius = 5 +-0.01", true, 0.0, 0.0, "3")
	expect(rp, "block volume = %s +-1" % str(snappedf(40.0 * 40.0 * 20.0 - PI * 5.1 * 5.1 * 20.0, 0.01)), true, 0.0, 0.0, "3")
	expect(rp, "axis of peg along z +-0.1", true, 0.0, 0.0, "3")
	expect(rp, "axis of peg along x +-0.1", false, 89.9, 0.01, "3")
	expect(rp, "peg ends at block within 0.2 mm", true, 0.0, 0.0, "3")
	expect(rp, "one solid", false, 1.0, 0.0, "3 (the peg floats in the hole: 0.1 mm of air all round)")
	# ------------------------------------------------------------------ 4 AXES
	var rb := bars_part()
	var fb := PartFacts.facts(rb)
	ok(int(fb["bodies"]) == 3 and String(fb["data"][0]["name"]) == "Bar" and String(fb["data"][1]["name"]) == "Bar 2" and String(fb["data"][2]["name"]) == "Bar 3" and fb["repeats"].size() == 1 and fb["repeats"][0].size() == 3,
		"4 three patterned bars: names %s / %s / %s, one repeat group %s" % [fb["data"][0]["name"], fb["data"][1]["name"], fb["data"][2]["name"], str(fb["repeats"])])
	var a1 := Vector3(fb["data"][0]["axis"])
	var a2 := Vector3(fb["data"][1]["axis"])
	ok(near(rad_to_deg(a1.angle_to(a2)), 120.0, 0.01), "4 directed axes of bar 1 and 2: %s and %s, %.4f deg apart (wanted 120)" % [str(a1), str(a2), rad_to_deg(a1.angle_to(a2))])
	expect(rb, "axis of body 1 at 120 deg to axis of body 2 +-0.5", true, 0.0, 0.0, "4")
	expect(rb, "axis of body 2 at 120 deg to axis of body 3 +-0.5", true, 0.0, 0.0, "4")
	expect(rb, "axis of body 3 at 120 deg to axis of body 1", true, 0.0, 0.0, "4")
	expect(rb, "axis of body 1 at 90 deg to axis of body 2 +-0.5", false, 29.5, 0.01, "4")
	expect(rb, "axis of body 1 at 119 deg to axis of body 2 +-0.5", false, 0.5, 0.01, "4")
	expect(rb, "axis of bar 1 along x +-0.5", true, 0.0, 0.0, "4")
	expect(rb, "count bodies like bar = 3", true, 0.0, 0.0, "4")
	# ------------------------------------------------------------------ 5 FINS
	var rf := fins_part()
	var fbd := PartFacts.facts(rf)
	ok(int(fbd["bodies"]) == 1, "5 core with five discs fused: %d body" % int(fbd["bodies"]))
	expect(rf, "body 1 has 5 fins", true, 0.0, 0.0, "5")
	expect(rf, "body 1 has 6 fins", false, 1.0, 0.0, "5")
	# ------------------------------------------------------------------ 6 ENGINE
	var ed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENGINE))
	var re := Part.from_file(ed)
	var t0 := Time.get_ticks_msec()
	var M := PartFacts.build(re)
	ok(M.ok and M.n == 49 and (re["features"] as Array).size() == 219, "6 engine: %d features replay to %d bodies (wanted 219 / 49) in %d ms" % [(re["features"] as Array).size(), M.n, Time.get_ticks_msec() - t0])
	if M.ok:
		var names: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s220_engine_names.json"))
		var same := 0
		for i in M.n:
			if names[i] == M.labels[i]:
				same += 1
		ok(same >= 28 and String(M.labels[0]) == "Crankcase" and String(M.labels[5]) == "Barrel" and String(M.labels[6]) == "Barrel 2" and String(M.labels[32]) == "Piston", "6 body names follow the timeline: %d of 49 equal the driver's own names, #6 %s, #7 %s, #33 %s (the rest are named by the feature that made them)" % [same, M.labels[5], M.labels[6], M.labels[32]])
		t0 = Time.get_ticks_msec()
		var fe := PartFacts.facts_of(M)
		var ft := FileAccess.open(SHOT + "/engine_facts.txt", FileAccess.WRITE)
		ft.store_string("\n".join(fe["lines"]) + "\n")
		ft.close()
		ok(int(fe["bodies"]) == 49 and fe["lines"].size() >= 51, "6 engine facts: %d lines in %d ms (saved to %s/engine_facts.txt)" % [fe["lines"].size(), Time.get_ticks_msec() - t0, SHOT])
		var rep_ok := false
		for g in fe["repeats"]:
			if g.size() == 3 and (g as Array).has(6) and (g as Array).has(7) and (g as Array).has(8):
				rep_ok = true
		ok(rep_ok, "6 repeats found: the three barrels (#6 #7 #8) are one identical group: %s" % str(fe["repeats"].slice(0, 6)))
		t0 = Time.get_ticks_msec()
		var lines := ["piston touches barrel clearance 0.0-0.2 mm", "pushrod reaches crankcase", "pushrod touches crankcase", "count bodies like cooling fins = 3", "cooling fins 1 has 12 fins",
			"axis of barrel 1 at 120 deg to axis of barrel 2 +-0.5", "axis of barrel 2 at 120 deg to axis of barrel 3 +-0.5", "axis of barrel 3 at 120 deg to axis of barrel 1 +-0.5",
			"no overlaps except pistons/barrels", "one solid", "piston diameter = 105 +-0.1", "exhaust pipe sweep 3 at most 1 mm from cylinder head 3", "all bodies above the floor"]
		var er := PartAssert.run_on(M, lines)
		var ft2 := FileAccess.open(SHOT + "/engine_asserts.txt", FileAccess.WRITE)
		for x in er["results"]:
			print("     ", x.get("say", x.get("error", "")))
			ft2.store_line(String(x.get("say", x.get("error", ""))))
		ft2.close()
		print("     engine asserts: %d ms" % (Time.get_ticks_msec() - t0))
		var rs: Array = er["results"]
		ok(er["unread"] == 0 and rs.size() == 13, "6 all 13 engine lines read (%d unread)" % er["unread"])
		ok(bool(rs[0]["pass"]) and near(float(rs[0].get("gap_mm", -1)), 0.0, 0.01), "6 piston in bore: clearance %s mm, inside 0.0-0.2: %s" % [str(rs[0].get("gap_mm")), rs[0]["say"]])
		ok(not bool(rs[1]["pass"]) and near(miss_of(rs[1]) + 0.05, 5.0, 0.1), "6 the pushrod stops 5 mm short of the case along its own axis: FAIL, %s mm (wanted 5.0 +-0.05): %s" % [str(miss_of(rs[1])), rs[1]["say"]])
		ok(not bool(rs[2]["pass"]) and miss_of(rs[2]) > 0.1 and miss_of(rs[2]) < 0.6, "6 ...but its edge is only %s mm from the drum's curve (the shortest distance, any direction): a screenshot shows 5 mm, the nearest surface says %s" % [str(miss_of(rs[2])), rs[2]["say"]])
		ok(bool(rs[3]["pass"]), "6 three cooling-fin bodies counted: %s" % rs[3]["say"])
		ok(bool(rs[4]["pass"]), "6 twelve fins in a cooling-fin body: %s" % rs[4]["say"])
		ok(bool(rs[5]["pass"]) and bool(rs[6]["pass"]) and bool(rs[7]["pass"]), "6 the three barrel axes are 120 deg apart: %s | %s | %s" % [rs[5]["say"], rs[6]["say"], rs[7]["say"]])
		ok(not bool(rs[8]["pass"]) and rs[8].get("overlaps", []).size() >= 10, "6 the overlap list (none of it pistons/barrels): %d interferences, worst %s mm3" % [rs[8].get("overlaps", []).size(), str(miss_of(rs[8]))])
		ok(bool(rs[9]["pass"]), "6 %s" % rs[9]["say"])
		ok(bool(rs[10]["pass"]), "6 piston diameter: %s" % rs[10]["say"])
		ok(bool(rs[11]["pass"]), "6 the pipe reaches the head: %s" % rs[11]["say"])
		ok(not bool(rs[12]["pass"]) and near(miss_of(rs[12]), 305.933, 0.05), "6 the engine hangs %s mm under the floor (rocker arm 3): %s" % [str(miss_of(rs[12])), rs[12]["say"]])
		M.release()
	# ------------------------------------------------------------------ 7 DOORS
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var T := AgentTools.new(m)
	var specs0 := AiBox.tool_specs()
	var specs1 := AiBox.tool_specs(true)
	var n1 := specs1.map(func(x): return x["name"])
	ok(specs0.size() == 7 and specs1.size() == 9 and "part_facts" in n1 and "part_assert" in n1 and not ("part_facts" in specs0.map(func(x): return x["name"])), "7 the AI box has 7 tools, and part_facts + part_assert once a part is open (%s)" % str(n1))
	m.S.part = peg_part()
	var q1: Dictionary = await T.request(1, "part_facts", {})
	var r1: Dictionary = q1.get("result", {})
	ok(q1.has("result") and int(r1.get("bodies", 0)) == 2 and String(r1["lines"][1]).begins_with("#1 Block"), "7 agent_tools part_facts on the live part: %d bodies, first line '%s'" % [int(r1.get("bodies", 0)), String(r1.get("lines", [""])[1]).left(90)])
	var u0: int = m.undo.size()
	var q2: Dictionary = await T.request(2, "part_assert", {"lines": ["peg touches block clearance 0.0-0.2 mm", "body 1 above the floor", "this is not a line"], "save": true})
	var r2: Dictionary = q2.get("result", {})
	var saved: Array = m.S.part.get("asserts", [])
	ok(q2.has("result") and r2["passed"] == 2 and r2["unread"] == 1 and r2.has("grammar") and saved.size() == 2 and m.undo.size() == u0 + 1, "7 part_assert on the live part: 2 pass, 1 unread (grammar returned), the 2 that read are saved in the record (%d), one undo step" % saved.size())
	var back := Part.from_file(Part.to_file(m.S.part))
	ok((back.get("asserts", []) as Array) == saved, "7 saved asserts survive Part.to_file / from_file: %s" % str(back.get("asserts")))
	var q3: Dictionary = await T.request(3, "part_assert", {})
	ok(q3.has("result") and q3["result"]["passed"] == 2 and q3["result"]["results"].size() == 2, "7 part_assert with no lines re-runs the saved ones: %s" % str(q3.get("result", {}).get("passed")))
	var q4: Dictionary = await T.request(4, "part_assert", {"lines": ["piston"]})
	ok(q4.has("result") and q4["result"]["unread"] == 1 and (q4["result"]["grammar"] as Array).size() > 8, "7 an unread line returns the grammar (%d lines)" % (q4["result"]["grammar"] as Array).size())
	# the CLI as a child process, on a saved part file
	var pf := ProjectSettings.globalize_path(DIRT) + "/cubes.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	var fw := FileAccess.open(pf, FileAccess.WRITE)
	fw.store_string(JSON.stringify(Part.to_file(two_cubes(10.0))))
	fw.close()
	var out := []
	var proj := ProjectSettings.globalize_path("res://")
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", proj, "-s", "tools/poser_cli.gd", "--", "part_assert", pf, "body 1 at least 10 mm from body 2", "body 1 touches body 2"], out, true)
	var txt := "\n".join(out)
	ok(code == 1 and txt.contains("PASS  body 1 at least 10 mm from body 2") and txt.contains("FAIL  body 1 touches body 2") and txt.contains("misses by 10.000 mm"), "7 poser_cli part_assert as a child process: exit %d (1 = a line failed), the verdicts are printed: %s" % [code, txt.substr(txt.find("PASS"), 200).replace("\n", " | ")])
	out = []
	code = OS.execute(OS.get_executable_path(), ["--headless", "--path", proj, "-s", "tools/poser_cli.gd", "--", "part_facts", pf], out, true)
	txt = "\n".join(out)
	ok(code == 0 and txt.contains("#1 Cube A  V 8000 mm3") and txt.contains("near 2 (10.00 mm)"), "7 poser_cli part_facts: exit %d, lines: %s" % [code, txt.substr(maxi(0, txt.find("PART")), 220).replace("\n", " | ")])
	# ------------------------------------------------------------------ shots: the part in the Part workspace, and its facts as text
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	var card: Control = ss._cards["building"]
	var cp := card.get_global_rect().get_center()
	for dn in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = dn
		e.position = cp
		e.global_position = cp
		root.push_input(e, true)
		await process_frame
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)
	var pu: PartUI = m.bld.part
	pu.set_on(false)
	m.S.part = {}
	await idle(4)
	var pb: Button = pu.part_btn
	var pq := pb.get_global_rect().get_center()
	for dn2 in [true, false]:
		var e2 := InputEventMouseButton.new()
		e2.button_index = MOUSE_BUTTON_LEFT
		e2.pressed = dn2
		e2.position = pq
		e2.global_position = pq
		root.push_input(e2, true)
		await process_frame
	await idle(4)
	if not pu.on:
		pu.set_on(true)
		await idle(4)
	m.S.part = peg_part()
	m.bld.sync()
	await idle(20)
	m.dist = m.dist * 0.3   # close in on the 40 mm block so the peg in its hole is visible
	m._cam()
	await idle(10)
	root.get_texture().get_image().save_png(SHOT + "/peg.png")
	var lab := RichTextLabel.new()
	lab.size = Vector2(1280, 720)
	lab.bbcode_enabled = false
	lab.add_theme_font_size_override("normal_font_size", 14)
	var shown := PartFacts.facts(peg_part())
	var ar := PartAssert.run(peg_part(), ["peg touches block clearance 0.0-0.2 mm", "peg touches block clearance 0.15-0.2 mm", "peg diameter = 10 +-0.05", "axis of peg along z +-0.1", "one solid"])
	var tx := "part_facts\n" + "\n".join(shown["lines"]) + "\n\npart_assert\n" + "\n".join(ar["results"].map(func(x): return String(x["say"])))
	lab.text = tx
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12)
	bg.size = Vector2(1280, 720)
	var cl := CanvasLayer.new()
	cl.layer = 100
	root.add_child(cl)
	cl.add_child(bg)
	cl.add_child(lab)
	await idle(6)
	root.get_texture().get_image().save_png(SHOT + "/facts.png")
	print("s220: %d fail" % fails)
	quit(1 if fails > 0 else 0)
