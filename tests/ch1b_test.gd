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
	print("ch1b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
