extends SceneTree
## godot --headless --path . -s tests/ch1b_test.gd   (CH1b: does a one-floor wood-frame American house stand up? scripts/build/house_check.gd)
## Bars (written and committed before the numbers were read):
##  1 PASSING RANCH   HouseCheck.ranch() (28 x 40 ft, 2x6 rafters 16 in o.c. 6/12, 2x4 studs 16 in o.c., 2x8 ceiling joists, 2-2x10 headers on 6 ft openings):
##                    every line passes, at least 20 lines, one line per member, every line carries an IRC rule cite and a number.
##  2 PLANTED         each alone, on a copy of the ranch, fails EXACTLY the member it names and nothing else:
##                    2x4 rafters at 24 in over the 14 ft run -> the rafters; a 10 ft opening with a 2x6 header -> that header; the 40 ft front wall
##                    with no bracing panel -> that wall line's bracing; studs at 32 in o.c. -> that wall's studs.
##  3 AGREE           on every rafter / joist / header line of the passing ranch the table verdict and the first-principles verdict agree, and so on
##                    the planted failures (a verdict that agrees only on the easy case is no check).
##  4 HAND CALC       one rafter, 2x6 DF-L #2 at 16 in o.c., 6/12, 28 ft wide house, horizontal span 14 ft - half the 1.5 in ridge = 167.25 in:
##                      load  w = (20 live + 10 dead) psf x 16/12 ft = 40 plf = 3.3333 lb/in            (live alone 20 psf -> 2.2222 lb/in)
##                      S = 1.5 x 5.5^2 / 6 = 7.5625 in^3    I = 1.5 x 5.5^3 / 12 = 20.797 in^4
##                      M = w L^2 / 8 = 3.3333 x 167.25^2 / 8 = 11655.2 in-lb      fb = M / S = 1541.2 psi
##                      Fb' = 900 x 1.25 (CD roof live) x 1.3 (CF 2x6) x 1.15 (Cr) = 1681.9 psi      ratio 0.9164
##                      deflection (live) = 5 w L^4 / (384 E I) = 0.6804 in  against L/180 = 0.9292 in   (E = 1.6e6)
##                      shear V = w L / 2 = 278.75 lb   fv = 1.5 V / A = 50.68 psi against Fv' = 180 x 1.25 = 225 psi
##                    the reported numbers match within 0.5 pct.
##  5 TABLES          Table rows ordered the way lumber is (a bigger size or a closer spacing never spans less), SPF #2 never spans more than DF-L #2 in the rafter table.
##  6 PRINTED CELLS   (lead 11-03) every printed IRC 2021 cell stored in house_check.gd (rafters R802.4.1(1), ceiling joists R802.5.1(1), headers R602.7(1); DF-L #2 and SPF #2) is at most
##                    3 pct ABOVE the first-principles NDS span (tables round down: physics may allow more, never less). Cells printed as 'over 26 ft' are lower bounds and skipped.
##                    Cells where physics allows MORE than 3 pct above the printed value are listed, not failed. At least 60 cells. CONTROL: a cell inflated 10 pct is caught.
##  CONTROL           the planted cases of bar 2 ARE the control: a checker that passed everything would fail them. A checker that fails everything fails bar 1.
var fails := 0
const HC := preload("res://scripts/build/house_check.gd")


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func failing(lines: Array) -> Array:
	var o := []
	for l in lines:
		if not l["pass"]:
			o.append(l)
	return o


func kinds(lines: Array) -> Array:
	var o := []
	for l in lines:
		if not o.has(l["kind"]):
			o.append(l["kind"])
	return o


func near(a: float, b: float, pct: float) -> bool:
	return absf(a - b) <= absf(b) * pct / 100.0


func _init() -> void:
	var h: Dictionary = HC.ranch()
	var L: Array = HC.check(h)
	# 1 passing ranch
	ok(L.size() >= 20, "1 ranch gives %d lines (>= 20)" % L.size())
	var f := failing(L)
	ok(f.is_empty(), "1 ranch passes every rule (%d failing: %s)" % [f.size(), str(f.map(func(x): return x["member"] + " " + x["text"]))])
	var cited := true
	for l in L:
		if not (str(l["rule"]).contains("R") and str(l["text"]).length() > 20 and l.has("value") and l.has("limit")):
			cited = false
	ok(cited, "1 every line has a rule cite, a value, a limit and words")
	for k in ["rafter", "joist", "header", "stud", "bracing", "uplift", "ridge", "sill", "footing"]:
		ok(kinds(L).has(k), "1 the report has %s lines" % k)
	# 2 planted, each alone
	var cases := {}
	var h1: Dictionary = h.duplicate(true)
	h1["rafters"]["size"] = "2x4"
	h1["rafters"]["spacing_in"] = 24
	cases["rafter"] = [h1, "rafter"]
	var h2: Dictionary = h.duplicate(true)
	h2["walls"][0]["openings"] = [{"width_ft": 10.0, "header": "2x6"}]
	cases["header"] = [h2, "header"]
	var h3: Dictionary = h.duplicate(true)
	h3["walls"][0]["bracing"] = []
	cases["bracing"] = [h3, "bracing"]
	var h4: Dictionary = h.duplicate(true)
	h4["walls"][0]["spacing_in"] = 32
	cases["stud"] = [h4, "stud"]
	for name in cases:
		var Lp: Array = HC.check(cases[name][0])
		var fp := failing(Lp)
		var kk := kinds(fp)
		ok(fp.size() >= 1 and kk == [cases[name][1]], "2 planted %s: fails only kind %s (got %s: %s)" % [name, cases[name][1], str(kk), str(fp.map(func(x): return x["member"]))])
		if name == "header":
			ok(fp.size() == 1, "2 planted header: exactly one member fails (%d)" % fp.size())
		if name == "bracing":
			ok(fp.size() == 1 and str(fp[0]["member"]).contains("front"), "2 planted bracing: the front wall line only")
		if name == "stud":
			ok(fp.size() == 1 and str(fp[0]["member"]).contains("front"), "2 planted stud: the front wall studs only")
	# 3 agreement
	var agree_n := 0
	var all_agree := true
	for l in L:
		if ["rafter", "joist", "header"].has(l["kind"]):
			agree_n += 1
			if not (l.has("phys") and l["agree"]):
				all_agree = false
	ok(agree_n >= 3 and all_agree, "3 ranch: table and first principles agree on all %d rafter/joist/header lines" % agree_n)
	var pa := true
	for name in cases:
		for l in HC.check(cases[name][0]):
			if ["rafter", "joist", "header"].has(l["kind"]) and not l["agree"]:
				pa = false
	ok(pa, "3 planted: table and first principles agree there too")
	# 4 hand calc
	var raf = null
	for l in L:
		if l["kind"] == "rafter":
			raf = l
	ok(raf != null, "4 a rafter line exists")
	if raf != null:
		var p: Dictionary = raf["phys"]
		ok(near(raf["value"], 167.25, 0.01), "4 span 167.25 in (%.3f)" % raf["value"])
		ok(near(p["fb"], 1541.19, 0.5), "4 fb 1541.2 psi (%.1f)" % p["fb"])
		ok(near(p["Fb_allow"], 1681.87, 0.5), "4 Fb' 1681.9 psi (%.1f)" % p["Fb_allow"])
		ok(near(p["defl"], 0.6804, 0.5), "4 deflection 0.6804 in (%.4f)" % p["defl"])
		ok(near(p["defl_lim"], 0.92917, 0.5), "4 limit L/180 0.9292 in (%.4f)" % p["defl_lim"])
		ok(near(p["fv"], 50.68, 0.5), "4 shear fv 50.68 psi (%.2f)" % p["fv"])
	# 5 table order
	var ord_ok := true
	for kind in ["rafter", "joist"]:
		for sp in [12, 16, 24]:
			var prev := 0.0
			for sz in ["2x4", "2x6", "2x8", "2x10"]:
				var v: float = HC.table_span(kind, sz, sp, "DF-L#2")
				if v < prev:
					ord_ok = false
				prev = v
		for sz in ["2x4", "2x6", "2x8", "2x10"]:
			if not (HC.table_span(kind, sz, 12, "DF-L#2") >= HC.table_span(kind, sz, 16, "DF-L#2") and HC.table_span(kind, sz, 16, "DF-L#2") >= HC.table_span(kind, sz, 24, "DF-L#2")):
				ord_ok = false
	ok(ord_ok, "5 tables ordered by size and spacing")
	var spf_ok := true
	for sz in ["2x4", "2x6", "2x8", "2x10"]:
		for sp in [12, 16, 24]:
			if HC.table_span("rafter", sz, sp, "SPF#2") > HC.table_span("rafter", sz, sp, "DF-L#2"):
				spf_ok = false
	ok(spf_ok, "5 SPF #2 rafters never out-span DF-L #2")
	# 6 printed cells vs first principles
	var cells: Array = HC.cells()
	ok(cells.size() >= 60, "6 %d printed cells compared" % cells.size())
	var over := []
	var under := []
	for c in cells:
		if c["capped"]:
			continue
		if c["printed"] > c["phys"] * 1.03:
			over.append(c)
		elif c["phys"] > c["printed"] * 1.03:
			under.append(c)
	ok(over.is_empty(), "6 no printed cell is more than 3 pct above physics (%d over: %s)" % [over.size(), str(over.map(func(x): return "%s %.0f vs %.1f" % [x["name"], x["printed"], x["phys"]]))])
	print("info 6 cells where physics allows >3 pct more than printed: %d of %d" % [under.size(), cells.size()])
	for c in under:
		print("info   %s printed %.0f in phys %.1f in (%.1f pct more)" % [c["name"], c["printed"], c["phys"], (c["phys"] / c["printed"] - 1.0) * 100.0])
	for c in cells:
		print("cell %s printed %.0f phys %.1f ratio %.3f" % [c["name"], c["printed"], c["phys"], c["ratio"]])
	var inflated: bool = false
	for c in cells:
		if not c["capped"] and c["printed"] * 1.10 > c["phys"] * 1.03:
			inflated = true
	ok(inflated, "6 control: a printed cell inflated 10 pct trips the bar")
	# ---- CH1d (bars written before the Miami / NY numbers were run through them; see the commit order) ----
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var ny := Ch1House.from_members(mj, "levittown_ny")
	var mia := Ch1House.from_members(mj, "miami_fl")
	var Lny: Array = HC.check(ny)
	var Lmi: Array = HC.check(mia)
	# D1 NY passes every line, with at least 45 lines
	ok(Lny.size() >= 45 and failing(Lny).is_empty(), "D1 NY house: %d lines, %d failing" % [Lny.size(), failing(Lny).size()])
	# D2 Miami fails a wind rule with the number: the roof-tie line, against an independent hand calc: 396 lb (140 mph <5:12, 24 in o.c., 25 ft: 384 + 48/4) x (175/140)^2 x 1.2 (exposure C)
	var up = null
	for l in Lmi:
		if l["kind"] == "uplift":
			up = l
	ok(up != null and not up["pass"] and near(up["value"], 396.0 * 1.5625 * 1.2, 1.0) and up["limit"] == 625.0, "D2 Miami roof ties FAIL with %.0f lb against 625 lb (hand calc %.0f)" % [up["value"] if up != null else -1.0, 396.0 * 1.5625 * 1.2])
	var upn = null
	for l in Lny:
		if l["kind"] == "uplift":
			upn = l
	ok(upn != null and upn["pass"] and near(upn["value"], 298.0 + 36.0 / 4.0, 0.5), "D2 NY roof ties pass with %.1f lb (hand calc 307.0: 298 + (334-298)/4 at 130 mph <5:12 24 in o.c.)" % upn["value"])
	var site_fail := failing(Lmi).filter(func(x): return x["kind"] == "site")
	ok(site_fail.size() == 1 and failing(Lmi).filter(func(x): return x["kind"] == "bracing").size() >= 1, "D2 Miami also fails the site wind range and the bracing lines (175 mph is off the tables)")
	ok(not failing(Lmi).is_empty() and failing(Lny).is_empty(), "D2 the same house passes in NY and fails in Miami: only the site record changed")
	# D3 each new rule, planted alone on the NY record, fails exactly its own kind
	var plants := {}
	var p1: Dictionary = ny.duplicate(true)
	for c in p1["connections"]:
		if c["key"] == "rafter_to_plate":
			c["fastener"] = {}      # the drawing calls out no nails for this connection
	plants["fastener (rafter to plate has no nails)"] = [p1, "fastener"]
	var p2: Dictionary = ny.duplicate(true)
	for c in p2["connections"]:
		if c["key"] == "plate_to_plate":
			c["fastener"]["spacing_in"] = 24
	plants["fastener (plate to plate at 24 in)"] = [p2, "fastener"]
	var p3: Dictionary = ny.duplicate(true)
	p3["sheathing_nailing"]["wall"]["edge_in"] = 12.0
	plants["sheathing nailing"] = [p3, "sheathing_nail"]
	var p4: Dictionary = ny.duplicate(true)
	p4["walls"][0]["openings"][0]["jacks"] = 0
	plants["header bearing"] = [p4, "header_bearing"]
	var p5: Dictionary = ny.duplicate(true)
	p5["rafters"]["birdsmouth_in"] = 3.0
	plants["birdsmouth"] = [p5, "birdsmouth"]
	var p6: Dictionary = ny.duplicate(true)
	p6["sill"]["embed_in"] = 3.0
	plants["anchorage"] = [p6, "anchorage"]
	var p7: Dictionary = ny.duplicate(true)
	p7["site"]["sdc"] = "D1"
	plants["seismic SDC D1"] = [p7, "seismic"]
	for nm in plants:
		var fp2 := failing(HC.check(plants[nm][0]))
		ok(kinds(fp2) == [plants[nm][1]], "D3 planted %s: fails only %s (got %s)" % [nm, plants[nm][1], str(kinds(fp2))])
	# D4 every connection type the member list has gets a fastener line
	var mk := []
	for m in mj["members"]:
		if not mk.has(m["kind"]):
			mk.append(m["kind"])
	var need_keys: Array = HC.connections_of(mk)
	var have_keys := []
	for l in Lny:
		if l["kind"] == "fastener":
			have_keys.append(String(l["member"]).substr(9).split(" (")[0].replace(" ", "_"))
	ok(need_keys.size() >= 9 and have_keys.size() == need_keys.size() and need_keys.all(func(k): return have_keys.has(k)), "D4 %d connection types in the member list, %d fastener lines" % [need_keys.size(), have_keys.size()])
	# D5 the corrected panel rule: first panel must begin within 10 ft of the line end (the 12.5 ft held before was wrong); a panel starting 11 ft in fails alone
	var h5: Dictionary = h.duplicate(true)
	h5["walls"][0]["bracing"] = [{"pos_ft": 11.0, "len_ft": 4.0}, {"pos_ft": 18.0, "len_ft": 4.0}, {"pos_ft": 36.0, "len_ft": 4.0}]
	var f5 := failing(HC.check(h5))
	ok(kinds(f5) == ["bracing"] and f5.size() == 1, "D5 first panel 11 ft from the end fails (R602.10.2.2, 10 ft): %s" % str(kinds(f5)))
	# D6 uplift table sanity: never lower with wind, span or closer spacing wider
	var mono := true
	for sp in [12.0, 16.0, 24.0]:
		for rise in [4.0, 6.0]:
			var pv := 0.0
			for v in [110.0, 115.0, 120.0, 130.0, 140.0]:
				var q: float = HC.uplift_demand(v, "B", rise, 24.0, sp)[0]
				if q < pv:
					mono = false
				pv = q
		for v in [110.0, 130.0, 140.0]:
			if HC.uplift_demand(v, "B", 4.0, 28.0, sp)[0] < HC.uplift_demand(v, "B", 4.0, 24.0, sp)[0] or HC.uplift_demand(v, "B", 4.0, 24.0, 24.0)[0] < HC.uplift_demand(v, "B", 4.0, 24.0, 16.0)[0]:
				mono = false
	ok(mono, "D6 Table R802.11 cells ordered by wind, span and spacing")
	# D7 the sites are records: lat/lon/zip/exposure/soil and a source for every load
	var rec_ok := true
	for sid in HC.SITES:
		var st: Dictionary = HC.SITES[sid]
		for key in ["lat", "lon", "zip", "exposure", "soil_class", "wind_mph", "ground_snow_psf", "sdc", "source", "edition", "lookup_status"]:
			if not st.has(key):
				rec_ok = false
	ok(rec_ok and HC.SITES.size() == 2, "D7 two stored site records with every field and a source")
	print("ch1b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
