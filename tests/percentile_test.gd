## godot --path . -s tests/percentile_test.gd     (ROADMAP_400 G16: PERCENTILE READOUT; needs a window, boots main.gd and opens the BODY page)
## Sources: ANSUR II 2012 report, Gordon et al. 2014 (US Army NATICK/TR-15/007). Citation NOT checked against PubMed/DOI:
##   UNVERIFIED (from memory). Normal approximation (percentile = Phi((x - mean) / sd)); stated in the panel text.
## BARS, written before the implementation (scripts/percentile.gd, the panel in scripts/body_panel.gd):
##  1 TABLE   ONE const table Percentile.TABLE (dim -> sex -> [mean mm, sd mm]); every dim has both sexes with mean > 0, sd > 0;
##            Percentile.SOURCE names "ANSUR II", "Gordon" and carries "UNVERIFIED" or a PMID/DOI; the stature rows equal BodyModel.ANSUR
##  2 NORMAL  a body set to exactly the male mean stature reads 50th +-1 (men); mean + 1 SD reads 84th +-1; mean - 1 SD 16th +-1;
##            the same for women with the women's table; the male mean stature read against women reads 97th-98th (z = 1.99)
##  3 MEASURE each readout row's measured value (stature, arm span, shoulder joints, hip joints) equals the test's OWN measurement of
##            the live body (a fresh Body, T pose, head top - heel, joint distances, middle fingertips) within 1 mm
##  4 PANEL   on the BODY page the panel has a node per dimension (pct_stature, pct_span, pct_shoulders, pct_hips) whose real text
##            has the value in cm and both ordinals, and a node percentile_note that says "normal approximation" and "ANSUR II"
##  5 RANGE   a 2.30 m body: stature row flagged for both sexes, its node says "above 99th" and "outside 1st-99th"; a 1.756 m body
##            has no flagged row and no such text; a 1.40 m man says "below 1st" (z = -5.2 against men)
##  6 PLANTED a row whose value is shifted 5 mm from the body must FAIL the 1 mm comparison (the comparison can fail); a stature
##            1 SD high must NOT read 50 +-1 (the 50 check can fail)
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the test's own T-pose measurement of a body dict: a fresh Body, all angles zero, no BodyModel.measures
func own(body: Dictionary) -> Dictionary:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.set_proportions(body)
	for j in Body.ORDER:
		b.ang[j] = Vector3.ZERO
	b.offset = Vector3.ZERO
	b.fk()
	var tips := []
	for sd in ["_l", "_r"]:
		var j: String = "middle_03" + sd
		tips.append((b.P[j] as Vector3) + (b.G[j] as Quaternion) * ((b.e0[j] as Vector3) - (b.p0[j] as Vector3)))
	return {"stature": (Proportions.head_top(b) as Vector3).y - (Proportions.heel(b, "_l") as Vector3).y,
		"span": ((tips[0] as Vector3) - (tips[1] as Vector3)).length(),
		"shoulders": ((b.P["upperarm_l"] as Vector3) - (b.P["upperarm_r"] as Vector3)).length(),
		"hips": ((b.P["thigh_l"] as Vector3) - (b.P["thigh_r"] as Vector3)).length()}


func within_mm(a_m: float, b_m: float) -> bool:
	return absf(a_m - b_m) * 1000.0 <= 1.0


func row_of(rows: Array, dim: String) -> Dictionary:
	for r in rows:
		if r["dim"] == dim:
			return r
	return {}


func _init() -> void:
	# ---- 1 table
	var dims := ["stature", "span", "shoulders", "hips"]
	var good := true
	for d in dims:
		for sx in ["male", "female"]:
			var e: Array = Percentile.TABLE.get(d, {}).get(sx, [])
			if e.size() != 2 or float(e[0]) <= 0.0 or float(e[1]) <= 0.0:
				good = false
	ok(good, "1 TABLE has stature, span, shoulders, hips for both sexes, mean > 0 and sd > 0")
	var src: String = Percentile.SOURCE
	ok(src.contains("ANSUR II") and src.contains("Gordon") and (src.contains("UNVERIFIED") or src.contains("PMID") or src.contains("DOI")), "1 SOURCE line: " + src)
	ok(Percentile.TABLE["stature"]["male"] == BodyModel.ANSUR["male"]["stat"] and Percentile.TABLE["stature"]["female"] == BodyModel.ANSUR["female"]["stat"],
		"1 stature rows equal BodyModel.ANSUR (one set of survey numbers)")
	# ---- 2 normal approximation
	for sx in ["male", "female"]:
		var mu: float = Percentile.TABLE["stature"][sx][0]
		var sd: float = Percentile.TABLE["stature"][sx][1]
		var p0: float = Percentile.of("stature", sx, mu)
		var p1: float = Percentile.of("stature", sx, mu + sd)
		var pm: float = Percentile.of("stature", sx, mu - sd)
		ok(absf(p0 - 50.0) <= 1.0 and absf(p1 - 84.0) <= 1.0 and absf(pm - 16.0) <= 1.0, "2 %s stature: mean %.1f%%, +1 SD %.1f%%, -1 SD %.1f%%" % [sx, p0, p1, pm])
	var cross: float = Percentile.of("stature", "female", float(Percentile.TABLE["stature"]["male"][0]))
	ok(cross >= 97.0 and cross <= 98.5, "2 the male mean stature read against women: %.1f%% (z = 1.99)" % cross)
	# ---- 6 planted controls (pure)
	var mu_m: float = Percentile.TABLE["stature"]["male"][0]
	var sd_m: float = Percentile.TABLE["stature"]["male"][1]
	ok(not (absf(Percentile.of("stature", "male", mu_m + sd_m) - 50.0) <= 1.0), "6 PLANTED: a stature 1 SD high does not read 50 +-1 (the check can fail)")
	ok(not within_mm(1.7562, 1.7562 + 0.005), "6 PLANTED: a value 5 mm off fails the 1 mm comparison (the check can fail)")
	# ---- the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._page_set("BODY", false)
	await idle(4)
	var P: BodyPanel = m.ui_body
	# ---- 2 on a body: exactly the male mean / +1 SD, through the app
	for case in [["mean", mu_m / 1000.0, 50.0], ["+1SD", (mu_m + sd_m) / 1000.0, 84.0]]:
		m.proportions_set(Proportions.clean(BodyFromNumbers.body_for(float(case[1]) * 100.0, 80.0, "male", 30.0, "average")))
		await idle(4)
		var rows: Array = Percentile.rows(BodyModel.measures(m.B))
		var st: Dictionary = row_of(rows, "stature")
		ok(absf(float(st["pct_male"]) - float(case[2])) <= 1.0, "2 body at the male %s stature (%.1f mm measured): men %.1f%% (want %.0f +-1)" % [case[0], float(st["value"]) * 1000.0, st["pct_male"], case[2]])
	# ---- 3 / 4 measured values and panel text on a 188 cm, 90 kg man
	m.proportions_set(Proportions.clean(BodyFromNumbers.body_for(188.0, 90.0, "male", 30.0, "average")))
	await idle(4)
	var mine := own(m.S.body)
	var rows2: Array = Percentile.rows(BodyModel.measures(m.B))
	for d in dims:
		var r := row_of(rows2, d)
		ok(not r.is_empty() and within_mm(float(r["value"]), float(mine[d])), "3 %s: readout %.1f mm, own measurement %.1f mm" % [d, float(r.get("value", 0.0)) * 1000.0, float(mine[d]) * 1000.0])
		var lab: Label = P.find_child("pct_" + d, true, false)
		var t: String = lab.text if lab != null else ""
		var cm := "%.1f cm" % (float(mine[d]) * 100.0)
		ok(lab != null and t.contains(cm) and t.contains("men") and t.contains("women") and (t.contains("th") or t.contains("st") or t.contains("nd") or t.contains("rd")),
			"4 node pct_%s text: '%s'" % [d, t])
	var note: Label = P.find_child("percentile_note", true, false)
	ok(note != null and note.text.contains("normal approximation") and note.text.contains("ANSUR II"), "4 percentile_note: '%s'" % (note.text if note != null else "<missing>"))
	# ---- 6 planted: a row shifted 5 mm fails
	var fake := float(row_of(rows2, "stature")["value"]) + 0.005
	ok(not within_mm(fake, float(mine["stature"])), "6 PLANTED: stature row shifted 5 mm is caught by the 1 mm comparison")
	# ---- 5 range flag
	m.proportions_set(Proportions.clean(BodyFromNumbers.body_for(230.0, 130.0, "male", 30.0, "average")))
	await idle(4)
	var rows3: Array = Percentile.rows(BodyModel.measures(m.B))
	var s3 := row_of(rows3, "stature")
	var l3: Label = P.find_child("pct_stature", true, false)
	ok(bool(s3["flag_male"]) and bool(s3["flag_female"]) and l3 != null and l3.text.contains("above 99th") and l3.text.contains("outside 1st-99th"),
		"5 2.30 m body (measured %.3f m): flagged for both sexes, node '%s'" % [float(s3["value"]), l3.text if l3 != null else "<missing>"])
	m.proportions_set(Proportions.clean(BodyFromNumbers.body_for(175.6, 78.0, "male", 30.0, "average")))
	await idle(4)
	var rows4: Array = Percentile.rows(BodyModel.measures(m.B))
	var l4: Label = P.find_child("pct_stature", true, false)
	ok(not bool(row_of(rows4, "stature")["flag_male"]) and l4 != null and not l4.text.contains("outside"), "5 1.756 m body: not flagged, node '%s'" % (l4.text if l4 != null else "<missing>"))
	m.proportions_set(Proportions.clean(BodyFromNumbers.body_for(140.0, 50.0, "male", 30.0, "average")))
	await idle(4)
	var l5: Label = P.find_child("pct_stature", true, false)
	ok(l5 != null and l5.text.contains("below 1st"), "5 1.40 m man: node '%s'" % (l5.text if l5 != null else "<missing>"))
	print("percentile_test: fails=%d" % fails)
	quit(1 if fails > 0 else 0)
