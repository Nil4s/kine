extends SceneTree
## godot --headless --path . -s tests/units2_test.gd     (ROADMAP_400 P14: unit system cm / m / in everywhere)
## BARS (written before the implementation, never moved after a run):
##  B1  with Units.unit = "in", each length field that matters shows inches with the " in" suffix and
##      value = metres / 0.0254 within 1e-4 (measure tool, CAD dim label, body height text, transform-panel/dummy/hit lengths via Units.len)
##  B2  "12 in" typed into a length entry stores 0.3048 m (Units.parse_m, and LengthParse.parse_length -> mm / 1000), within 1e-9
##  B3  round trip m -> in -> m (and cm, m) exact to 1e-9 over 200 values
##  B4  the number of listed length fields NOT routed through units.gd (source scan of the named sites) is 0
##  B5  cm stays as it was: Units.len(0.5) == "50 cm", mm under 1 cm
##  PLANTED: a fake converter (x39.37 instead of /0.0254) must FAIL B1's check; a fixture source line with a bare "%.2f m"
##  length must be COUNTED as unrouted by the scanner (a scanner that flags nothing proves nothing).
const IN := 0.0254
## [file, anchor text on a line, extra lines after it that may carry the call, what the field is]
const SITES := [
	["scripts/kmesh_measure.gd", "static func fmt_len", 1, "measure tool length"],
	["scripts/length_parse.gd", "static func label", 3, "CAD dimension label"],
	["scripts/proportions.gd", "static func stature_text", 1, "body height text"],
	["scripts/main.gd", "_set_prop(ui_hips[k][1], names[k]", 0, "transform panel: hips offset"],
	["scripts/main.gd", "static func _dummy_head", 1, "dummy distance readout"],
	["scripts/main.gd", "x[\"zone\"], x[\"speed\"]", 0, "hit list: height up the weapon"],
	["scripts/main.gd", "if float(h[\"u\"]) >= 0.0:", 1, "hit tag: height up the weapon"],
	["scripts/main.gd", "ui_arch_list.add_item(", 0, "archetype list: stature"],
	["scripts/main.gd", "ui_prop_preset.add_item(", 1, "proportions dialog: preset stature"],
	["scripts/main.gd", "l.text = \"stature", 0, "proportions dialog: stature field label"],
	["scripts/main.gd", "add.call(\"Body: \" + Proportions.PRESET_NAMES[pk]", 0, "palette: preset stature"],
	["scripts/main.gd", "add.call(\"Body: the mannequin's own proportions\"", 0, "palette: default stature"],
]
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## "12.5 in" -> [12.5, "in"]; NAN when the text is not "<number> <unit>"
func split_num(t: String) -> Array:
	var p := t.strip_edges().split(" ")
	if p.size() != 2 or not p[0].is_valid_float():
		return [NAN, ""]
	return [float(p[0]), String(p[1])]


func shows_inches(txt: String, m: float, conv: Callable) -> bool:
	var s := split_num(txt)
	return s[1] == "in" and absf(float(s[0]) - float(conv.call(m))) < 1e-4


## count of sites whose anchor line (or the few after it) has no Units. call; unfound anchors count too
func unrouted(sites: Array, lines_of: Callable) -> Array:
	var bad := []
	for s in sites:
		var L: PackedStringArray = lines_of.call(String(s[0]))
		var hit := false
		var found := false
		for i in L.size():
			if L[i].contains(String(s[1])):
				found = true
				for j in range(i, mini(L.size(), i + 1 + int(s[2]))):
					if L[j].contains("Units."):
						hit = true
				break
		if not (found and hit):
			bad.append(String(s[3]))
	return bad


func _init() -> void:
	var real_conv := func(m: float): return m / IN
	var fake_conv := func(m: float): return m * 39.37
	Units.unit = "in"
	var vals := [0.0254, 0.3048, 1.0, 1.78, 0.05, 2.5, 0.0123, 0.9144]
	var fields := {
		"measure": func(m): return KMeshMeasure.fmt_len(m),
		"cad dim": func(m): return LengthParse.label(m * 1000.0, "in", false),
		"body height": func(m): return Proportions.stature_text(m),
		"transform/dummy/hit (Units.len)": func(m): return Units.len(m),
	}
	for k in fields:
		var good := true
		for v in vals:
			var t: String = fields[k].call(v)
			if not shows_inches(t, v, real_conv):
				good = false
				print("   %s(%s) -> '%s'" % [k, v, t])
		ok(good, "B1 unit=in: %s shows inches, value = m/0.0254 within 1e-4" % k)
	# planted: the fake converter must be caught
	ok(not shows_inches(Units.len(1.78), 1.78, fake_conv), "PLANTED fake converter (x39.37) FAILS the B1 check")
	# B2
	ok(absf(Units.parse_m("12 in") - 0.3048) < 1e-9, "B2 '12 in' -> 0.3048 m (Units.parse_m: %s)" % str(Units.parse_m("12 in")))
	ok(absf(Units.parse_m("12\"") - 0.3048) < 1e-9, "B2 '12\"' -> 0.3048 m")
	ok(absf(Units.parse_m("30,48 cm") - 0.3048) < 1e-9, "B2 '30,48 cm' -> 0.3048 m")
	ok(absf(float(LengthParse.parse_length("12 in", "mm")["mm"]) / 1000.0 - 0.3048) < 1e-9, "B2 CAD entry '12 in' -> 0.3048 m")
	Units.unit = "in"
	ok(absf(Units.parse_m("12") - 0.3048) < 1e-9, "B2 bare '12' in an inch project -> 0.3048 m")
	Units.unit = "cm"
	ok(absf(Units.parse_m("12") - 0.12) < 1e-9, "B2 bare '12' in a cm project -> 0.12 m")
	ok(is_nan(Units.parse_m("twelve")), "B2 'twelve' is refused (NAN)")
	# B3
	var worst := 0.0
	for u in ["in", "cm", "m"]:
		for i in 200:
			var m := (i + 1) * 0.0137
			worst = maxf(worst, absf(Units.from_unit(Units.to_unit(m, u), u) - m))
	ok(worst < 1e-9, "B3 round trip m -> unit -> m worst error %.3e (bar 1e-9)" % worst)
	# B5
	Units.unit = "cm"
	ok(Units.len(0.5) == "50 cm" and Units.len(0.004) == "4 mm" and Units.len(0.085) == "8.5 cm", "B5 cm mode unchanged: %s %s %s" % [Units.len(0.5), Units.len(0.004), Units.len(0.085)])
	Units.unit = "m"
	ok(shows_inches_like(Units.len(1.78), "m", 1.78), "B5b m mode: '%s'" % Units.len(1.78))
	Units.unit = "cm"
	# B4
	var cache := {}
	var lines_of := func(f: String) -> PackedStringArray:
		if not cache.has(f):
			cache[f] = FileAccess.get_file_as_string("res://" + f).split("\n")
		return cache[f]
	var bad := unrouted(SITES, lines_of)
	print("   fields NOT routed through units.gd: %d of %d %s" % [bad.size(), SITES.size(), str(bad)])
	ok(bad.size() == 0, "B4 length fields not routed through units.gd = %d (bar 0)" % bad.size())
	# planted scanner control
	var fx := func(_f: String): return PackedStringArray(["var a = 1", "label.text = \"%.2f m\" % x", "var b = 2"])
	var fb := unrouted([["fx", "label.text", 0, "fixture"]], fx)
	ok(fb.size() == 1, "PLANTED a bare '%.2f m' fixture line is counted as unrouted")
	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func shows_inches_like(t: String, u: String, m: float) -> bool:
	var s := split_num(t)
	return s[1] == u and absf(float(s[0]) - m) < 1e-4
