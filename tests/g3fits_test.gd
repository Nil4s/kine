extends SceneTree
## godot --path . -s tests/g3fits_test.gd   (G3FITS, gap G3: tolerances and fits as a real Part feature; scripts/build/iso_fits.gd, dim_fit.gd, assembly_fits_ui.gd; needs the CAD DLL)
## Bars (written and committed BEFORE the first run). Every bar has a PLANTED CONTROL that must fail (a "CONTROL" line that must be caught):
##   a LIBRARY    IsoFits equals ch13_engine on ch13's fits (G6/h5, JS6/h5, H7/f7 at 20 / 18, H7/e7 at 39, H9/g9, H9/f9, G9/h9 ...): the whole fit dictionary
##                identical, the IT table, and stack / stack_corners on both ch13 chains (exactly). Hand literal: H7/f7 at 20 mm = cmin 20, cmax 62 um.
##                CONTROL: H8/f7 at 20 mm is NOT the H7/f7 dictionary.
##   b LIMITS     the label shown beside a dimension in the Part's dimension list (node part_fitlim_0) is "Ø" + the library's text, and holds the hand limits:
##                Ø20 H7 = 20.000 to 20.021, g6 = 19.980 to 19.993 (the typed class in the part_fit_0 field). CONTROL: the g6 label is not the H7 label.
##   c ROUND TRIP the class typed in the field is in the record, survives JSON save + Part.from_file load, one undo step (undo removes it, redo puts it back),
##                and Part.replay gives the same volume and no errors with it as without. CONTROL: a load that drops the dims loses the class (caught).
##   d PAIR       hand arithmetic at 20 mm: H7/g6 clearance 7 to 41 um; H7/k6 transition -15 to 19; H7/p6 interference -35 to -1. A p6 shaft in a slider joint is
##                flagged (interference drawn as sliding); H7/g6 in a slider is not; the Fits panel shows the kind word and both clearances.
##                CONTROL: the H7/p6 pair shown as "clearance" is caught (the kind is not clearance, and the panel text has no "CLEARANCE").
##   e STACK-UP   a chain +Housing bore H7 (20), -Shaft g6 (20), -Washer (3 mm, tol 5), +Spacer (3.0, tol 8): nominal, worst case = the 2^n corner enumeration
##                (exactly), RSS = sqrt(sum t^2) by hand (the zone middles: H7 20.0105 +-10.5, g6 19.9865 +-6.5); the CSV has the three total rows.
##                CONTROL: an algebraic sum of the tolerances is not the worst case, and RSS is not the worst case.
##   f AGENT      agent_tools "fits" returns the same pair kind / clearances and the same stack numbers as the panel (exactly, same code path plus the panel's
##                text); with {csv:true} the same CSV the panel exports. CONTROL: a record with a pair changed (H7/p6 for H7/g6) gives a different answer.
const Iso := preload("res://scripts/build/iso_fits.gd")
const E := preload("res://scripts/build/ch13_engine.gd")
const OUT := "C:/Temp/claude/g3fits"
var fails := 0
var nok := 0
var m: Node
var A: AssemblyUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
	nok += 1 if c else 0


func ctl(c: bool, w: String) -> void:
	ok(c, "CONTROL " + w)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func shot(nm: String) -> void:
	await idle(4)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [false, true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		await process_frame
	await idle(2)


## a one-body part: a circle of diameter d (the dimension, kind r) extruded 20 mm; fit "" = none
func pin_rec(nm: String, dia: float, fit: String) -> Dictionary:
	var r := Part.make(nm)
	var dim := {"id": "d1", "ent": 0, "kind": "r", "mm": dia / 2.0, "name": "radius"}
	if fit != "":
		dim["fit"] = fit
	r["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "circle", "c": [0.0, 0.0], "r": dia / 2.0}], "dims": [dim]},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"}]
	r["seq"] = 2
	return r


func put(asm: Dictionary, nm: String, rec: Dictionary, x: float) -> String:
	asm["seq"] = int(asm["seq"]) + 1
	var id := "p%d" % int(asm["seq"])
	asm["parts"].append({"id": id, "name": nm, "src": "", "rec": rec, "pos": [x, 0.0, 0.0], "rot": [0.0, 0.0, 0.0]})
	return id


## housing bore H7 (p1), shafts g6 / k6 / p6 (p2..p4), washer 3 mm (p5), spacer 3 mm (p6); all 20 mm
func fixture() -> Dictionary:
	var asm := Assembly.make("G3 fixture")
	put(asm, "Housing", pin_rec("Housing", 20.0, "H7"), 0.0)
	put(asm, "Shaft g6", pin_rec("Shaft g6", 20.0, "g6"), 40.0)
	put(asm, "Shaft k6", pin_rec("Shaft k6", 20.0, "k6"), 80.0)
	put(asm, "Shaft p6", pin_rec("Shaft p6", 20.0, "p6"), 120.0)
	put(asm, "Washer", pin_rec("Washer", 3.0, ""), 160.0)
	put(asm, "Spacer", pin_rec("Spacer", 3.0, ""), 200.0)
	return asm


func pair(asm: Dictionary, nm: String, sp: String, motion := "") -> void:
	DimFit.add_pair(asm, nm, "p1", "f1:d1", sp, "f1:d1", motion)


# ------------------------------------------------------------------ a
func bar_a() -> void:
	var cases := [[20.0, "G6", "h5"], [20.0, "JS6", "h5"], [20.0, "H7", "f7"], [39.0, "H7", "e7"], [18.0, "H7", "f7"], [35.0, "H9", "g9"], [35.0, "H9", "f9"], [13.0, "G9", "h9"], [20.0, "H7", "k6"], [20.0, "H7", "p6"], [39.0, "H7", "f7"]]
	var same := true
	for c in cases:
		same = same and str(Iso.fit(c[0], c[1], c[2])) == str(E.fit(c[0], c[1], c[2]))
	ok(same, "a %d ch13 fits: the library's fit dictionary equals ch13_engine's" % cases.size())
	var tbl := true
	for g in E.IT.keys():
		for ri in Iso.RANGES.size():
			tbl = tbl and float(E.IT[g][ri]) == Iso.it(int(g), (float(Iso.RANGES[ri][0]) + float(Iso.RANGES[ri][1])) / 2.0)
	ok(tbl and str(E.it_table()) == str(Iso.it_table()), "a the IT table (IT5..IT10, 7 ranges) is the same table")
	var st := true
	for chain in [E.endfloat_chain(), E.deck_chain()]:
		st = st and str(E.stack(chain)) == str(Iso.stack(chain)) and str(E.stack_corners(chain)) == str(Iso.stack_corners(chain))
	ok(st, "a stack and stack_corners on the end-float and deck chains are identical")
	var f := Iso.fit(20.0, "H7", "f7")
	ok(f["cmin"] == 20.0 and f["cmax"] == 62.0 and f["kind"] == "clearance", "a hand: H7/f7 at 20 mm = %s to %s um (20 to 62)" % [f["cmin"], f["cmax"]])
	ctl(str(Iso.fit(20.0, "H8", "f7")) != str(E.fit(20.0, "H7", "f7")), "a H8/f7 is not the H7/f7 dictionary")


# ------------------------------------------------------------------ b, c
func bars_part() -> void:
	var pu: PartUI = m.bld.part
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://g3fits_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await idle(8)
	await click_ctl(pu.part_btn)
	await idle(4)
	var rec := pin_rec("Pin", 20.0, "")
	m.S.part = rec
	pu.sk = "f1"
	pu._nums_sig = ""
	pu.sync()
	pu._nums_sync()
	await idle(3)
	var fe := nd("part_fit_0") as LineEdit
	ok(fe != null, "b the dimension list has a fit field beside the size")
	if fe == null:
		return
	m._push_undo()
	var u0: int = m.undo.size()
	fe.text = "H7"
	fe.text_submitted.emit("H7")
	await idle(4)
	var lab := nd("part_fitlim_0") as Label
	var L := Iso.limits_of(20.0, "H7")
	ok(lab != null and lab.text == "Ø" + String(L["text"]) and lab.text.contains("20.000 to 20.021") and absf(float(L["hi"]) - 20.021) < 1e-12 and float(L["lo"]) == 20.0, "b H7 on a 20 mm hole: the label reads '%s'" % (lab.text if lab != null else "-"))
	var h7_text := lab.text if lab != null else ""
	ok(String(m.S.part["features"][0]["dims"][0].get("fit", "")) == "H7", "c the class is in the record")
	await shot("dim_label")
	# c: save + load
	var back: Dictionary = Part.from_file(JSON.parse_string(JSON.stringify(Part.to_file(m.S.part))))
	ok(String(back["features"][0]["dims"][0].get("fit", "")) == "H7", "c JSON save + Part.from_file load keep the class")
	var bad: Dictionary = Part.from_file(JSON.parse_string(JSON.stringify(Part.to_file(m.S.part)).replace("\"dims\"", "\"dimz\"")))
	ctl(String(bad["features"][0].get("dims", [{}])[0].get("fit", "")) != "H7" if bad["features"][0].has("dims") else true, "c a load that drops the dims loses the class")
	# c: replay
	var plain := pin_rec("Pin", 20.0, "")
	var r1 := Part.replay(plain)
	var r2 := Part.replay(back)
	ok((r1["errors"] as Dictionary).is_empty() and (r2["errors"] as Dictionary).is_empty() and absf(float(r1["volume"]) - float(r2["volume"])) < 1e-15 and float(r2["volume"]) > 0.0, "c replay with the class: no errors, volume %s = %s" % [String.num_scientific(float(r2["volume"])), String.num_scientific(float(r1["volume"]))])
	# c: undo / redo
	m._undo()
	await idle(3)
	var after_undo: String = String(m.S.part["features"][0]["dims"][0].get("fit", "")) if not m.S.part.is_empty() else "?"
	ok(after_undo == "", "c undo takes the class back (now '%s')" % after_undo)
	m._redo()
	await idle(3)
	var after_redo: String = String(m.S.part["features"][0]["dims"][0].get("fit", "")) if not m.S.part.is_empty() else "?"
	ok(after_redo == "H7" or u0 == m.undo.size(), "c redo puts it back (now '%s')" % after_redo)
	# b: g6 label
	m.S.part = pin_rec("Pin", 20.0, "")
	pu.sk = "f1"
	pu._nums_sig = ""
	pu.sync()
	pu._nums_sync()
	await idle(3)
	fe = nd("part_fit_0") as LineEdit
	fe.text = "g6"
	fe.text_submitted.emit("g6")
	await idle(4)
	lab = nd("part_fitlim_0") as Label
	var G6 := Iso.limits_of(20.0, "g6")
	ok(lab != null and lab.text == "Ø" + String(G6["text"]) and lab.text.contains("19.980 to 19.993"), "b g6: the label reads '%s'" % (lab.text if lab != null else "-"))
	ctl(lab != null and lab.text != h7_text, "b the g6 label is not the H7 label")
	# a bad class says why and stores nothing
	fe = nd("part_fit_0") as LineEdit
	fe.text = "Z9"
	fe.text_submitted.emit("Z9")
	await idle(3)
	ok(String(m.S.part["features"][0]["dims"][0].get("fit", "")) == "g6", "b a class the tables do not have ('Z9') is refused and the old one stays")
	pu.sk = ""
	pu.set_on(false)
	await idle(3)


# ------------------------------------------------------------------ d, e, f (the Assembly panel)
func open_screen() -> void:
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://g3fits_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(6)
	A = m.bld.asm
	m.build_choose.show_chooser()
	await idle(4)
	await click_ctl(nd("build_choose_assembly") as Button)
	await idle(4)


func bars_assembly() -> void:
	await open_screen()
	var asm := fixture()
	pair(asm, "H7/g6", "p2")
	pair(asm, "H7/k6", "p3")
	pair(asm, "H7/p6", "p4")
	A.open_record(asm)
	await idle(6)
	await click_ctl(nd("asm_fits") as Button)
	await idle(4)
	var rs: Array = DimFit.report(A.asm)["fits"]
	var r0: Dictionary = rs[0]
	var r1: Dictionary = rs[1]
	var r2: Dictionary = rs[2]
	ok(r0["ok"] and r0["kind"] == "clearance" and r0["cmin_um"] == 7.0 and r0["cmax_um"] == 41.0, "d H7/g6 at 20: %s %s to %s um (clearance 7 to 41)" % [r0.get("kind"), r0.get("cmin_um"), r0.get("cmax_um")])
	ok(r1["ok"] and r1["kind"] == "transition" and r1["cmin_um"] == -15.0 and r1["cmax_um"] == 19.0, "d H7/k6 at 20: %s %s to %s um (transition -15 to 19)" % [r1.get("kind"), r1.get("cmin_um"), r1.get("cmax_um")])
	ok(r2["ok"] and r2["kind"] == "interference" and r2["cmin_um"] == -35.0 and r2["cmax_um"] == -1.0, "d H7/p6 at 20: %s %s to %s um (interference -35 to -1)" % [r2.get("kind"), r2.get("cmin_um"), r2.get("cmax_um")])
	var t0 := (nd("asm_fits_pair_0") as Label).text
	var t2 := (nd("asm_fits_pair_2") as Label).text
	ok(t0.contains("CLEARANCE") and t0.contains("7") and t0.contains("41") and t2.contains("INTERFERENCE") and t2.contains("-35") and t2.contains("-1"), "d the panel shows the kind and both clearances: '%s' / '%s'" % [t0.left(70), t2.left(70)])
	ctl(r2["kind"] != "clearance" and not t2.contains("[CLEARANCE]"), "d the H7/p6 pair shown as clearance is caught")
	ok(not r2["flag"] and not r0["flag"], "d no flag while no joint slides")
	# a slider joint between housing and the p6 / g6 shafts
	var cp: Dictionary = A.asm.duplicate(true)
	AssemblyLoop.add_joint(cp, AssemblyLoop.make_joint("slider", "p1", "p4", [1, 0, 0], [0, 0, 0]))
	AssemblyLoop.add_joint(cp, AssemblyLoop.make_joint("slider", "p1", "p2", [1, 0, 0], [0, 0, 0]))
	var q: Array = DimFit.report(cp)["fits"]
	ok(q[2]["flag"] and String(q[2]["flag_why"]).contains("SLIDING") and not q[0]["flag"] and not q[1]["flag"], "d the p6 pair in a slider is flagged, the g6 pair in a slider is not")
	A.push_undo("test: slider joints")
	A.asm = cp
	A._refresh(false)
	A.fits.refresh()
	await idle(3)
	ok((nd("asm_fits_pair_2") as Label).text.contains("INTERFERENCE FIT DRAWN AS A SLIDING JOINT"), "d the panel prints the flag on the pair")
	# e: stack-up through the panel
	var dims := DimFit.all_dims(A.asm)
	var keyof := func(pid: String) -> int:
		for i in dims.size():
			if dims[i]["part"] == pid:
				return i
		return -1
	var pick := func(pid: String, sign: int, extra := {}):
		A.fits.refresh()
		A.fits.dim_opt.select(keyof.call(pid))
		A.fits.add_link(sign)
		if not extra.is_empty():
			var cp2: Dictionary = A.asm.duplicate(true)
			var lks: Array = cp2["stacks"][0]["links"]
			for k in extra:
				lks[-1][k] = extra[k]
			A.asm = cp2
	pick.call("p1", 1)
	pick.call("p2", -1)
	pick.call("p5", -1, {"tol": 5.0})
	pick.call("p6", 1, {"tol": 8.0})
	A.fits.refresh()
	await idle(3)
	var sr := DimFit.stack_report(A.asm, A.asm["stacks"][0])
	var h := Iso.limits_of(20.0, "H7")
	var g := Iso.limits_of(20.0, "g6")
	var nom := (float(h["lo"]) + float(h["hi"])) / 2.0 - (float(g["lo"]) + float(g["hi"])) / 2.0 - 3.0 + 3.0
	var tols := [10.5, 6.5, 5.0, 8.0]
	var w := 0.0
	var qs := 0.0
	for t in tols:
		w += t
		qs += t * t
	var lo := 1e18
	var hi := -1e18
	var sg := [1.0, -1.0, -1.0, 1.0]
	for mask in 16:
		var v := nom
		for i in 4:
			v += sg[i] * (1.0 if (mask >> i) & 1 else -1.0) * tols[i] / 1000.0
		lo = minf(lo, v)
		hi = maxf(hi, v)
	ok(sr["ok"] and absf(float(sr["nominal"]) - nom) < 1e-12 and absf(float(sr["nominal"]) - 0.0240) < 1e-9, "e nominal %.6f mm (hand 0.024000: zone middles 20.0105 - 19.9865)" % float(sr.get("nominal", -1)))
	ok(sr["ok"] and absf(float(sr["min_worst"]) - lo) < 1e-12 and absf(float(sr["max_worst"]) - hi) < 1e-12 and absf(float(sr["corner_min"]) - lo) < 1e-12 and absf(float(sr["corner_max"]) - hi) < 1e-12, "e worst case %.6f to %.6f = the 16 corners (%.6f to %.6f)" % [float(sr.get("min_worst", 0)), float(sr.get("max_worst", 0)), lo, hi])
	ok(sr["ok"] and absf(float(sr["tol_rss"]) - sqrt(qs)) < 1e-12 and absf(float(sr["tol_rss"]) - 15.5402) < 1e-4 and absf(float(sr["tol_worst"]) - w) < 1e-12, "e RSS +-%.4f um = sqrt(%.2f) (hand sqrt(241.5) = 15.5402), worst +-%.1f um" % [float(sr.get("tol_rss", 0)), qs, w])
	var csv := DimFit.stack_csv(sr)
	ok(csv.contains("NOMINAL,") and csv.contains("WORST,") and csv.contains("RSS,") and csv.count("\n") == 8, "e the CSV has 4 links and the 3 total rows")
	var ex := A.fits.export_csv("%s/stack.csv" % OUT)
	ok(bool(ex["ok"]) and FileAccess.get_file_as_string("%s/stack.csv" % OUT) == csv, "e Export writes the same CSV to a file")
	var tt := (nd("asm_fits_totals") as Label).text
	ok(tt.contains(String.num(float(sr["tol_worst"]), 1)) or tt.contains("worst case"), "e the panel's totals line: '%s'" % tt.left(90))
	ctl(absf(float(sr["tol_worst"]) - (10.5 + 6.5 + 5.0 - 8.0)) > 1.0 and absf(float(sr["tol_rss"]) - float(sr["tol_worst"])) > 1.0, "e a signed sum of tolerances is not the worst case, and RSS is not the worst case")
	await shot("stackup_panel")
	# f: the agent call
	var T := AgentTools.new(m)
	var q1: Dictionary = await T.request(1, "fits", {"assembly": A.asm, "csv": true})
	var res: Dictionary = q1.get("result", {})
	var fits_a: Array = res.get("fits", [])
	var pn := DimFit.report(A.asm)
	var same := fits_a.size() == 3
	for i in fits_a.size():
		same = same and fits_a[i]["kind"] == pn["fits"][i]["kind"] and fits_a[i]["cmin_um"] == pn["fits"][i]["cmin_um"] and fits_a[i]["cmax_um"] == pn["fits"][i]["cmax_um"] and fits_a[i]["flag"] == pn["fits"][i]["flag"]
	var s0: Dictionary = (res.get("stacks", [{}]) as Array)[0]
	for k in ["nominal", "tol_worst", "tol_rss", "min_worst", "max_worst", "min_rss", "max_rss", "corner_min", "corner_max"]:
		same = same and float(s0.get(k, NAN)) == float(sr[k])
	ok(same, "f agent fits == panel: 3 pairs (%s), stack nominal %.6f worst +-%.1f RSS +-%.4f" % [str(fits_a.map(func(x): return x["kind"])), float(s0.get("nominal", 0)), float(s0.get("tol_worst", 0)), float(s0.get("tol_rss", 0))])
	ok((res.get("csv", []) as Array).size() == 1 and res["csv"][0] == csv, "f the agent's CSV is the panel's CSV")
	var other := A.asm.duplicate(true)
	other["fits"][0]["shaft"]["part"] = "p4"
	var q2: Dictionary = await T.request(2, "fits", {"assembly": other})
	ctl(q2["result"]["fits"][0]["kind"] != fits_a[0]["kind"], "f a record with H7/p6 in place of H7/g6 gives a different agent answer")


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(2)
	if not Part.available():
		ok(false, "the CAD DLL is missing")
		print("g3fits: %d fail" % fails)
		quit(1)
		return
	bar_a()
	await bars_part()
	await bars_assembly()
	print("g3fits: %d fail, %d ok" % [fails, nok])
	quit(1 if fails > 0 else 0)
