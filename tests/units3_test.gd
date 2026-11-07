extends SceneTree
## godot --headless --path . -s tests/units3_test.gd     (L118: P14 follow-up, the units the first pass left bare)
## BARS (written before the implementation, never moved after a run):
##  B1  Units.unit = "in": each readout below shows inches with the " in" suffix, value = m / 0.0254 within 1e-4:
##      arena-fit room/over/ring side, floor-plan strike travel + scale bar, focus distance, shot-camera readout,
##      the kmesh E/I typed amount
##  B2  areas in in^2 = m^2 / 0.00064516 and volumes in in^3 = m^3 / 1.6387064e-5, within 1e-6 relative (and m^2, m^3 likewise)
##  B3  cm mode is byte-identical to before: golden strings written from the OLD format strings for a fixed set of values
##  B4  source scan: bare length format strings ("%.Nf m" / "%.Nf cm" / quoted " cm") in the listed files = 0
##  B5  main.tscn boots and the Main node is live
##  PLANTED: a fake converter (x39.37) FAILS B1's check; a fixture line with a bare "%.2f m" IS counted by the scanner.
## New API this suite pins down (units.gd): metres(m, dp), fixed(m, dp), area(m2), vol(m3), shot_readout(mm, fstop, focus_m),
## typed_m(text), typed_text(text).
const IN := 0.0254
const IN2 := 0.00064516
const IN3 := 1.6387064e-5
const SCAN := ["scripts/arena_fit.gd", "scripts/arena_fit_ui.gd", "scripts/floor_plan.gd", "scripts/floor_plan_view.gd",
	"scripts/kmesh_measure.gd", "scripts/kmesh_drag_op.gd"]
## main.gd has many unrelated old lines; only these anchored readouts are scanned there (anchor text, what it is)
const MAIN_SITES := [
	["SHOT CAMERA", "shot-camera readout"],
	["shot camera f/%s at %.0f mm", "f-stop note"],
	["hit_tag.text = ", "hit tag depth"],
	["deep\" % [h[\"t\"]", "hit list depth"],
	["the fist stops", "dummy gap"],
	["fist ends", "dummy gap 2"],
	["out of reach by", "reach miss"],
	["from its handle", "handle miss"],
	["they had moved up to", "stay in place metres"],
]
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## the idx-th "<number> <unit>" pair in the text -> [value, unit]; [NAN, ""] when none
func num_unit(t: String, idx := 0) -> Array:
	var re := RegEx.new()
	re.compile("(-?[0-9]+(?:\\.[0-9]+)?) (in²|in³|in|cm²|cm³|cm|m²|m³|m)(?![A-Za-z/])")
	var all := re.search_all(t)
	if all.size() <= idx:
		return [NAN, ""]
	return [float(all[idx].get_string(1)), all[idx].get_string(2)]


func shows(t: String, m: float, conv: Callable, unit := "in", idx := 0, tol := 1e-4) -> bool:
	var s := num_unit(t, idx)
	return s[1] == unit and absf(float(s[0]) - float(conv.call(m))) < tol


## count of lines with a bare length format string ("%.Nf m" / "%.Nf cm", not m/s, m^2, m^3; a quoted " cm" tail; comments skipped)
func bare_count(lines: PackedStringArray) -> int:
	var re := RegEx.new()
	re.compile("%[0-9]*\\.?[0-9]*f (?:m|cm)(?![A-Za-z/²³])|\" (?:m|cm)\"|[0-9] cm\"")
	var n := 0
	for l in lines:
		var s := l.strip_edges()
		if s.begins_with("#"):
			continue
		if re.search(l) != null:
			n += 1
	return n


func _init() -> void:
	var real := func(m: float): return m / IN
	var fake := func(m: float): return m * 39.37
	Units.unit = "in"
	var vals := [0.0254, 0.3048, 1.0, 1.78, 0.05, 2.5, 0.0123, 7.0]
	var fields := {
		"arena room / over (Units.metres, 2 dp)": func(m): return Units.metres(m, 2),
		"arena ring side (Units.metres, 1 dp)": func(m): return Units.metres(m, 1),
		"floor-plan strike travel (Units.metres)": func(m): return Units.metres(m, 2),
		"floor-plan scale bar / focus distance (Units.len)": func(m): return Units.len(m),
		"fixed-cm readouts (hit depth, gaps, reach), 1 dp": func(m): return Units.fixed(m, 1),
		"fixed-cm readouts, whole": func(m): return Units.fixed(m, 0),
	}
	for k in fields:
		var good := true
		for v in vals:
			var t: String = fields[k].call(v)
			if not shows(t, v, real):
				good = false
				print("   %s(%s) -> '%s'" % [k, v, t])
		ok(good, "B1 unit=in: %s shows inches, value = m/0.0254 within 1e-4" % k)
	var sc := Units.shot_readout(50.0, 2.8, 3.0)
	ok(shows(sc, 3.0, real) and sc.contains("50 mm") and sc.contains("f/2.8"), "B1 shot-camera readout: '%s'" % sc)
	ok(Units.shot_readout(50.0, 2.8, NAN) == "SHOT CAMERA  50 mm  16:9", "B1 shot-camera readout without focus: '%s'" % Units.shot_readout(50.0, 2.8, NAN))
	ok(absf(Units.typed_m("3") - 3.0 * IN) < 1e-9, "B1 E/I typed '3' in inch mode = 3 in = %.6f m" % Units.typed_m("3"))
	ok(shows(Units.typed_text("3"), 3.0 * IN, real) and Units.typed_text("3").begins_with("type 3"), "B1 E/I typed echo '%s'" % Units.typed_text("3"))
	ok(is_nan(Units.typed_m("-")) and is_nan(Units.typed_m("")), "B1 E/I typed '-' / '' is no amount (NAN)")
	ok(not shows(Units.metres(1.78, 2), 1.78, fake), "PLANTED fake converter (x39.37) FAILS the B1 check")
	# B2 areas and volumes
	var worst_a := 0.0
	var worst_v := 0.0
	var good_u := true
	for m2 in [0.0007, 0.05, 0.3, 1.0, 2.5, 12.0]:
		var pa := num_unit(Units.area(m2))
		good_u = good_u and pa[1] == "in²"
		worst_a = maxf(worst_a, absf(float(pa[0]) - m2 / IN2) / (m2 / IN2))
		var m3: float = m2 * 0.01
		var pv := num_unit(Units.vol(m3))
		good_u = good_u and pv[1] == "in³"
		worst_v = maxf(worst_v, absf(float(pv[0]) - m3 / IN3) / (m3 / IN3))
	ok(good_u, "B2 unit=in: area suffix in², volume suffix in³")
	ok(worst_a < 1e-6, "B2 area in² = m²/0.00064516, worst relative error %.8f (bar 1e-6)" % worst_a)
	ok(worst_v < 1e-6, "B2 volume in³ = m³/1.6387064e-5, worst relative error %.8f (bar 1e-6)" % worst_v)
	ok(KMeshMeasure.fmt_area(0.05) == Units.area(0.05) and KMeshMeasure.fmt_vol(0.0005) == Units.vol(0.0005), "B2 KMeshMeasure.fmt_area / fmt_vol go through Units")
	Units.unit = "m"
	var wa := 0.0
	var wv := 0.0
	for m2 in [0.0007, 0.05, 0.3, 2.5]:
		wa = maxf(wa, absf(float(num_unit(Units.area(m2))[0]) - m2) / m2)
		wv = maxf(wv, absf(float(num_unit(Units.vol(m2 * 0.01))[0]) - m2 * 0.01) / (m2 * 0.01))
	ok(num_unit(Units.area(0.05))[1] == "m²" and num_unit(Units.vol(0.0005))[1] == "m³" and wa < 1e-6 and wv < 1e-6, "B2 unit=m: m² / m³ within 1e-6 (%.8f %.8f)" % [wa, wv])
	# B3 cm byte-identical to the old format strings
	Units.unit = "cm"
	var gold := [
		[Units.metres(1.234, 2), "1.23 m"], [Units.metres(0.5, 1), "0.5 m"], [Units.metres(12.0, 1), "12.0 m"],
		[Units.fixed(0.0123, 1), "1.2 cm"], [Units.fixed(0.0123, 0), "1 cm"], [Units.fixed(0.456, 0), "46 cm"],
		[Units.area(0.05), "500.0 cm²"], [Units.area(0.0007), "7.0 cm²"],
		[Units.vol(0.0005), "500 cm³ (0.500 L)"], [Units.vol(0.0123), "12300 cm³ (12.300 L)"],
		[Units.shot_readout(50.0, 2.8, 3.0), "SHOT CAMERA  50 mm  16:9  f/2.8  focus 3.00 m"],
		[Units.shot_readout(35.0, 4.0, NAN), "SHOT CAMERA  35 mm  16:9"],
		[Units.typed_text("0.3"), "type 0.3"], [Units.len(1.0), "100 cm"],
		[KMeshMeasure.fmt_len(0.05), "5.00 cm"], [KMeshMeasure.fmt_len(0.5), "50.0 cm"],
	]
	var bad := []
	for g in gold:
		if g[0] != g[1]:
			bad.append("'%s' != '%s'" % [g[0], g[1]])
	ok(bad.is_empty() and absf(Units.typed_m("0.3") - 0.3) < 1e-12, "B3 cm mode byte-identical to the old format strings %s" % str(bad))
	# B4 source scan
	var total := 0
	for f in SCAN:
		var n := bare_count(FileAccess.get_file_as_string("res://" + f).split("\n"))
		print("   %s: %d" % [f, n])
		total += n
	var ML := FileAccess.get_file_as_string("res://scripts/main.gd").split("\n")
	var nm := 0
	for s in MAIN_SITES:
		var found := false
		for i in ML.size():
			if ML[i].contains(String(s[0])):
				found = true
				nm += bare_count(PackedStringArray([ML[i]]))
				break
		if not found:
			print("   main.gd anchor not found: %s" % s[1])
			nm += 1
	print("   scripts/main.gd (anchored sites): %d" % nm)
	total += nm
	ok(total == 0, "B4 bare length format strings in the listed files = %d (bar 0)" % total)
	var fx := PackedStringArray(["var a = 1", "label.text = \"%.2f m\" % x", "var b = 2"])
	ok(bare_count(fx) == 1, "PLANTED a bare '%.2f m' fixture line is counted")
	ok(bare_count(PackedStringArray(["\"%.1f m/s\" % v", "\"%.1f m²\" % a", "# \"%.2f m\""])) == 0, "CONTROL m/s, m² and comments are not counted")
	# B5 boot main
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	ok(m != null and m.is_inside_tree() and m.get("S") != null and m.has_method("_say"), "B5 main.tscn booted (S and _say present)")
	print("UNITS3 TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
