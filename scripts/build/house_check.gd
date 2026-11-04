class_name HouseCheck
extends RefCounted
## CH1b: does a one-floor wood-frame American house stand up? One line per member: its load, the IRC 2021 rule, pass / fail with the number.
##
## Input is a house record (see ranch()): walls with studs, openings + headers, bracing panels; ceiling joists; rafters + ridge; sill on a stem wall or slab;
## footing. Sizes are US nominal lumber ("2x6", headers "2-2x10"). Output of check(): Array of Dictionary
##   {member, kind, load, rule, pass, value, limit, text}   plus, for kind rafter / joist / header, {phys, agree}:
## phys = the SAME member worked from first principles (beam bending stress vs Fb', shear, deflection) and agree = table verdict == phys verdict.
##
## WHAT THE TABLE NUMBERS ARE (read this before trusting a pass): the IRC span tables below were NOT available offline when this was written (no
## network, no book in the repo). The rafter, ceiling joist and header span rows are the span a member of that size and spacing is allowed by the
## NDS-2018-supplement design values the IRC tables are built on (DF-L #2 Fb 900 Fv 180 E 1.6e6, SPF #2 Fb 875 Fv 135 E 1.4e6; CF size factor, Cr 1.15,
## CD 1.25 roof live), rounded down to the inch by a script, NOT copied from the printed cells. So table and first-principles agree mostly because they share
## a basis; the printed IRC cells must be compared row by row before this is used for anything but Kine's own checking (TABLES_SOURCE says so in the report).
## Rules cited (IRC 2021): R802.4 rafter and ceiling joist spans (2018 numbering R802.4 / R802.5), R602.3(5) stud size/height/spacing, R602.7 headers,
## R602.10 braced wall lines, R802.11 uplift, R403.1 footings, R403.1.6 anchor bolts, R802.3 ridge board.

const TABLES_SOURCE := "span rows recomputed from NDS design values and rounded down, NOT copied from the printed IRC cells (verify before relying on them)"

## species -> design values (psi): Fb, Fv, E
const SPECIES := {"DF-L#2": {"Fb": 900.0, "Fv": 180.0, "E": 1.6e6}, "SPF#2": {"Fb": 875.0, "Fv": 135.0, "E": 1.4e6}}
## nominal -> [b, d, CF size factor for Fb]  (actual inches)
const SIZES := {"2x4": [1.5, 3.5, 1.5], "2x6": [1.5, 5.5, 1.3], "2x8": [1.5, 7.25, 1.2], "2x10": [1.5, 9.25, 1.1], "2x12": [1.5, 11.25, 1.0]}

## R802.4 rafters, 20 psf roof live + 10 psf dead, L/180 on live, ceiling joists as ties: max horizontal span in inches, per spacing 12 / 16 / 24 in o.c.
const RAFTER := {
	"DF-L#2": {"2x4": [129, 118, 97], "2x6": [201, 174, 142], "2x8": [255, 221, 180], "2x10": [312, 270, 220], "2x12": [361, 313, 255]},
	"SPF#2": {"2x4": [124, 112, 96], "2x6": [195, 172, 140], "2x8": [251, 218, 178], "2x10": [307, 266, 217], "2x12": [356, 309, 252]},
}
## R802.4 ceiling joists, 10 psf live (attic without storage) + 5 psf dead, L/240 on live
const JOIST := {
	"DF-L#2": {"2x4": [148, 135, 118], "2x6": [233, 212, 180], "2x8": [308, 279, 228], "2x10": [393, 341, 279]},
	"SPF#2": {"2x4": [142, 129, 112], "2x6": [223, 203, 177], "2x8": [294, 267, 225], "2x10": [376, 337, 275]},
}
## R602.7 headers in exterior bearing walls, 20 psf roof live, 10 psf roof dead, 5 dead + 10 live ceiling, 1 ft overhang: max clear span in inches by building width 20 / 28 / 36 ft
const HEADER := {
	"DF-L#2": {
		20: {"2x4": 32, "2x6": 47, "2x8": 59, "2x10": 72, "2x12": 84, "2-2x4": 45, "2-2x6": 66, "2-2x8": 84, "2-2x10": 102, "2-2x12": 119},
		28: {"2x4": 27, "2x6": 40, "2x8": 50, "2x10": 62, "2x12": 71, "2-2x4": 38, "2-2x6": 56, "2-2x8": 71, "2-2x10": 87, "2-2x12": 101},
		36: {"2x4": 22, "2x6": 35, "2x8": 45, "2x10": 55, "2x12": 63, "2-2x4": 34, "2-2x6": 50, "2-2x8": 63, "2-2x10": 77, "2-2x12": 90}},
	"SPF#2": {
		20: {"2x4": 29, "2x6": 46, "2x8": 58, "2x10": 71, "2x12": 83, "2-2x4": 44, "2-2x6": 65, "2-2x8": 83, "2-2x10": 101, "2-2x12": 117},
		28: {"2x4": 21, "2x6": 33, "2x8": 44, "2x10": 56, "2x12": 69, "2-2x4": 38, "2-2x6": 55, "2-2x8": 70, "2-2x10": 86, "2-2x12": 100},
		36: {"2x4": 16, "2x6": 26, "2x8": 34, "2x10": 44, "2x12": 54, "2-2x4": 33, "2-2x6": 49, "2-2x8": 62, "2-2x10": 76, "2-2x12": 88}},
}
## R602.3(5) studs, one story (roof + ceiling only): max spacing in, max unsupported height ft  (bearing 2x4 24 in / 10 ft, 2x6 24 in / 20 ft; non-bearing 2x4 24 in / 14 ft)
const STUD_BEARING := {"2x4": [24, 10.0], "2x6": [24, 20.0], "2x8": [24, 20.0]}
const STUD_NONBEARING := {"2x4": [24, 14.0], "2x6": [24, 20.0], "2x8": [24, 20.0]}
## R602.10.3(1) intermittent WSP bracing, 115 mph, exposure B, one story, 8-10 ft walls: ft of braced panel per 25 ft of braced wall line; seismic A-B adds nothing (R602.10.3(3))
const BRACE_FT_PER_25 := 3.5
const BRACE_MAX_GAP_FT := 20.0       # R602.10.2.2 spacing between panel edges
const BRACE_END_FT := 12.5           # first / last panel starts within 12.5 ft of the line end
## R802.11 uplift at the rafter-to-plate connection, 115 mph B, 24 in o.c.: pounds per ft of roof span (28 ft span -> 104 lb); scaled by spacing / 24
const UPLIFT_LB_PER_FT := 3.7
const TIES := {"toenail3-8d": 113.0, "H2.5A": 535.0, "none": 0.0}    # lb allowable uplift per connection (NDS withdrawal for 3-8d toenails, DF; H2.5A catalogue)
## R403.1 footing width (in) for one story, conventional light frame, by soil bearing psf (1500 and up); thickness >= 6 in (R403.1.1)
const FOOTING_W := {1500: 12.0, 2000: 12.0, 3000: 12.0, 4000: 12.0}


## A code-conforming 28 x 40 ft ranch (the passing record the tests plant failures into). Lengths in ft, spacings and sizes as lumber says them.
static func ranch() -> Dictionary:
	var gable_panels := [{"pos_ft": 0.0, "len_ft": 4.5}, {"pos_ft": 23.5, "len_ft": 4.5}]
	var long_panels := [{"pos_ft": 0.0, "len_ft": 4.0}, {"pos_ft": 18.0, "len_ft": 4.0}, {"pos_ft": 36.0, "len_ft": 4.0}]
	return {
		"species": "DF-L#2", "width_ft": 28.0, "length_ft": 40.0, "wall_h_ft": 8.0,
		"loads": {"roof": "live", "psf": 20.0}, "wind_mph": 115, "exposure": "B", "seismic": "A-B",
		"walls": [
			{"name": "front", "length_ft": 40.0, "stud": "2x4", "spacing_in": 16, "bearing": true,
				"openings": [{"width_ft": 6.0, "header": "2-2x10"}, {"width_ft": 3.0, "header": "2-2x10"}], "bracing": long_panels.duplicate(true)},
			{"name": "rear", "length_ft": 40.0, "stud": "2x4", "spacing_in": 16, "bearing": true,
				"openings": [{"width_ft": 6.0, "header": "2-2x10"}, {"width_ft": 3.0, "header": "2-2x10"}], "bracing": long_panels.duplicate(true)},
			{"name": "left gable", "length_ft": 28.0, "stud": "2x4", "spacing_in": 16, "bearing": false,
				"openings": [{"width_ft": 3.0, "header": "2-2x6"}], "bracing": gable_panels.duplicate(true)},
			{"name": "right gable", "length_ft": 28.0, "stud": "2x4", "spacing_in": 16, "bearing": false,
				"openings": [], "bracing": gable_panels.duplicate(true)},
		],
		"ceiling_joists": {"size": "2x8", "spacing_in": 16, "interior_bearing_wall": true},
		"rafters": {"size": "2x6", "spacing_in": 16, "rise_per_12": 6.0, "ridge": "2x8", "tie": "H2.5A"},
		"sill": {"on": "stem_wall", "lumber": "2x6", "bolt_dia_in": 0.5, "bolt_spacing_in": 72.0, "bolt_from_end_in": 9.0},
		"footing": {"width_in": 12.0, "thickness_in": 8.0, "soil_psf": 1500},
	}


static func fi(inches: float) -> String:
	var t := int(floor(inches + 0.5))
	return "%d'-%d\"" % [t / 12, t % 12]


static func _dims(size: String) -> Array:
	var plies := 1
	var s := size
	if size.begins_with("2-"):
		plies = 2
		s = size.substr(2)
	var d: Array = SIZES.get(s, [])
	if d.is_empty():
		return []
	return [d[0] * plies, d[1], d[2], plies, s]


static func _spacing_index(sp: float) -> int:
	if sp <= 12.0:
		return 0
	if sp <= 16.0:
		return 1
	if sp <= 24.0:
		return 2
	return -1


## Table max span (inches) for a rafter / joist: the row for the closest listed spacing that is not narrower than the member's. -1 = outside the table.
static func table_span(kind: String, size: String, spacing_in: float, species: String) -> float:
	var T: Dictionary = RAFTER if kind == "rafter" else JOIST
	var i := _spacing_index(spacing_in)
	if i < 0 or not T.has(species) or not T[species].has(size):
		return -1.0
	return float(T[species][size][i])


## First principles for a simple span: bending stress vs Fb', shear vs Fv', deflection of the live part vs L/lim. Units: in, lb, psi.
## w_tot / w_live in lb per inch; cd load-duration factor, cr repetitive factor.
static func beam(b: float, d: float, cf: float, span: float, w_tot: float, w_live: float, cd: float, cr: float, lim: float, sp: Dictionary) -> Dictionary:
	var S := b * d * d / 6.0
	var I := b * d * d * d / 12.0
	var M := w_tot * span * span / 8.0
	var fb := M / S
	var Fb_allow := float(sp["Fb"]) * cd * cf * cr
	var V := w_tot * span / 2.0
	var fv := 1.5 * V / (b * d)
	var Fv_allow := float(sp["Fv"]) * cd
	var defl := 5.0 * w_live * pow(span, 4) / (384.0 * float(sp["E"]) * I)
	var dl := span / lim
	return {"fb": fb, "Fb_allow": Fb_allow, "fv": fv, "Fv_allow": Fv_allow, "defl": defl, "defl_lim": dl, "M": M, "S": S, "I": I,
		"pass": fb <= Fb_allow and fv <= Fv_allow and defl <= dl}


static func _line(member: String, kind: String, load_s: String, rule: String, passed: bool, value: float, limit: float, words: String) -> Dictionary:
	return {"member": member, "kind": kind, "load": load_s, "rule": rule, "pass": passed, "value": value, "limit": limit,
		"text": "%s  %s | load %s | %s | %s" % ["PASS" if passed else "FAIL", member, load_s, rule, words]}


static func _physwords(p: Dictionary, agree: bool) -> String:
	return " | first principles: fb %.0f of %.0f psi, shear %.0f of %.0f psi, deflection %.2f of %.2f in -> %s (%s)" % [p["fb"], p["Fb_allow"], p["fv"], p["Fv_allow"], p["defl"], p["defl_lim"], "ok" if p["pass"] else "OVER", "agrees with the table" if agree else "DISAGREES with the table"]


static func check(h: Dictionary) -> Array:
	var out: Array = []
	var sp_name: String = h.get("species", "DF-L#2")
	var sp: Dictionary = SPECIES.get(sp_name, SPECIES["DF-L#2"])
	var W: float = h["width_ft"]
	var loads: Dictionary = h.get("loads", {})
	var snow: bool = loads.get("roof", "live") == "snow"
	var cd_roof := 1.15 if snow else 1.25
	var live_psf: float = loads.get("psf", 20.0)
	var rd := 10.0
	# ---- rafters (R802.4)
	var R: Dictionary = h["rafters"]
	var rs: String = R["size"]
	var rdim := _dims(rs)
	var rsp: float = R["spacing_in"]
	var ridge_t := 1.5
	var rspan := W * 12.0 / 2.0 - ridge_t / 2.0
	var rtab := table_span("rafter", rs, rsp, sp_name)
	if snow and rtab > 0:
		rtab = floor(rtab * sqrt(1.15 / 1.25))      # snow CD 1.15 against the 1.25 the rows use: bending-governed scaling
	var rok_tab := rtab > 0 and rspan <= rtab and absf(live_psf - 20.0) < 0.01
	var rphys := beam(rdim[0], rdim[1], rdim[2], rspan, (live_psf + rd) * rsp / 144.0, live_psf * rsp / 144.0, cd_roof, 1.15 if rsp <= 24.0 else 1.0, 180.0, sp)
	var ragree: bool = rok_tab == rphys["pass"]
	var rl := _line("rafters %s @%d in" % [rs, int(rsp)], "rafter", "%.0f psf %s + %.0f psf dead on the %s horizontal span" % [live_psf, "snow" if snow else "roof live", rd, fi(rspan)],
		"IRC 2021 R802.4 rafter spans, %s, L/180" % sp_name, rok_tab, rspan, rtab,
		"span %s against table %s" % [fi(rspan), fi(rtab) if rtab > 0 else "none (outside the table)"] + _physwords(rphys, ragree))
	rl["phys"] = rphys
	rl["agree"] = ragree
	out.append(rl)
	# ridge board (R802.3): at least as deep as the plumb cut of the rafter
	var rise: float = R.get("rise_per_12", 6.0)
	var cut := float(rdim[1]) * sqrt(rise * rise + 144.0) / 12.0
	var rg := _dims(str(R.get("ridge", "2x8")))
	var rg_d: float = rg[1] if not rg.is_empty() else 0.0
	out.append(_line("ridge board", "ridge", "rafter plumb cut %.2f in deep at %g/12" % [cut, rise], "IRC 2021 R802.3 ridge board at least as deep as the rafter cut", rg_d >= cut, rg_d, cut,
		"ridge %s is %.2f in deep, the rafter cut is %.2f in" % [R.get("ridge", "?"), rg_d, cut]))
	# rafter ties: ceiling joists parallel to the rafters keep the walls from spreading (R802.3.1)
	var has_cj: bool = h.has("ceiling_joists") and not (h["ceiling_joists"] as Dictionary).is_empty()
	out.append(_line("rafter ties", "tie", "outward thrust of a %g/12 roof at the plate" % rise, "IRC 2021 R802.3.1 ceiling joists as rafter ties, lower third of the rafter", has_cj, 1.0 if has_cj else 0.0, 1.0,
		"ceiling joists %s act as ties" % ("present" if has_cj else "missing")))
	# ---- ceiling joists (R802.4)
	if has_cj:
		var C: Dictionary = h["ceiling_joists"]
		var cs: String = C["size"]
		var cdim := _dims(cs)
		var csp: float = C["spacing_in"]
		var cspan := (W * 12.0 / 2.0 if C.get("interior_bearing_wall", false) else W * 12.0) - 1.5
		var ctab := table_span("joist", cs, csp, sp_name)
		var cok := ctab > 0 and cspan <= ctab
		var cphys := beam(cdim[0], cdim[1], cdim[2], cspan, 15.0 * csp / 144.0, 10.0 * csp / 144.0, 1.0, 1.15 if csp <= 24.0 else 1.0, 240.0, sp)
		var cagree: bool = cok == cphys["pass"]
		var cl := _line("ceiling joists %s @%d in" % [cs, int(csp)], "joist", "10 psf live + 5 psf dead (attic without storage) on the %s span" % fi(cspan),
			"IRC 2021 R802.4 ceiling joist spans, %s, L/240" % sp_name, cok, cspan, ctab, "span %s against table %s" % [fi(cspan), fi(ctab) if ctab > 0 else "none (outside the table)"] + _physwords(cphys, cagree))
		cl["phys"] = cphys
		cl["agree"] = cagree
		out.append(cl)
	# ---- walls: studs, headers, bracing
	var wall_h: float = h.get("wall_h_ft", 8.0)
	for wl in h["walls"]:
		var nm: String = wl["name"]
		var bearing: bool = wl.get("bearing", true)
		var ss: String = wl["stud"]
		var tbl: Dictionary = STUD_BEARING if bearing else STUD_NONBEARING
		var row: Array = tbl.get(ss, [0, 0.0])
		var sps: float = wl["spacing_in"]
		var sok: bool = sps <= float(row[0]) and wall_h <= float(row[1])
		out.append(_line("%s wall studs %s @%d in" % [nm, ss, int(sps)], "stud", "%s wall, %g ft high, roof + ceiling only (one story)" % ["bearing" if bearing else "non-bearing", wall_h],
			"IRC 2021 R602.3(5) stud size, height, spacing", sok, sps, float(row[0]), "spacing %d in against max %d in, height %g ft against max %g ft" % [int(sps), int(row[0]), wall_h, float(row[1])]))
		var k := 0
		for op in wl.get("openings", []):
			k += 1
			out.append(_header_line(nm, k, op, bearing, W, sp_name, sp, cd_roof))
		out.append(_bracing_line(nm, wl, wall_h, h))
	# ---- uplift (R802.11)
	var tie: String = R.get("tie", "none")
	var demand := UPLIFT_LB_PER_FT * W * rsp / 24.0
	var cap: float = TIES.get(tie, 0.0)
	out.append(_line("roof to wall ties (%s)" % tie, "uplift", "%d mph, exposure %s, %g ft roof span, rafters %d in o.c." % [int(h.get("wind_mph", 115)), h.get("exposure", "B"), W, int(rsp)],
		"IRC 2021 R802.11 uplift connection", cap >= demand, demand, cap, "uplift %.0f lb per rafter against the connector's %.0f lb" % [demand, cap]))
	# ---- sill and footing (R403.1)
	var S: Dictionary = h["sill"]
	var bd: float = S.get("bolt_dia_in", 0.5)
	var bs: float = S.get("bolt_spacing_in", 72.0)
	var be: float = S.get("bolt_from_end_in", 9.0)
	var sill_ok: bool = bd >= 0.5 and bs <= 72.0 and be <= 12.0 and be >= 7.0 * bd
	out.append(_line("sill plate on %s" % str(S.get("on", "slab")).replace("_", " "), "sill", "anchor bolts %.3g in dia at %d in, %d in from each plate end" % [bd, int(bs), int(be)],
		"IRC 2021 R403.1.6 anchor bolts (1/2 in, 6 ft o.c., within 12 in and 7 diameters of each end)", sill_ok, bs, 72.0, "spacing %d in against max 72 in, end distance %d in within %.1f to 12 in" % [int(bs), int(be), 7.0 * bd]))
	var F: Dictionary = h["footing"]
	var soil := int(F.get("soil_psf", 1500))
	var need := -1.0
	for key in FOOTING_W:
		if soil >= int(key):
			need = FOOTING_W[key]
	var fw: float = F.get("width_in", 0.0)
	var ft: float = F.get("thickness_in", 0.0)
	out.append(_line("footing", "footing", "one story on %d psf soil" % soil, "IRC 2021 R403.1 Table R403.1(1) width, R403.1.1 thickness 6 in", need > 0 and fw >= need and ft >= 6.0, fw, need,
		"width %g in against %s, thickness %g in against 6 in" % [fw, ("%g in" % need) if need > 0 else "none (soil under 1500 psf needs an engineer)", ft]))
	return out


static func _header_line(wall: String, k: int, op: Dictionary, bearing: bool, W: float, sp_name: String, sp: Dictionary, cd: float) -> Dictionary:
	var hs: String = op["header"]
	var span: float = op["width_ft"] * 12.0
	var dm := _dims(hs)
	var wk := 20 if W <= 20.0 else (28 if W <= 28.0 else (36 if W <= 36.0 else 0))
	var tab := -1.0
	if not dm.is_empty() and wk > 0:
		tab = float(HEADER[sp_name][wk].get(hs, -1))
	var tok := tab > 0 and span <= tab
	var wt: float
	var wlv: float
	var loadwords: String
	if bearing:
		wt = (30.0 * (W / 2.0 + 1.0) + 15.0 * (W / 2.0)) / 12.0
		wlv = (20.0 * (W / 2.0 + 1.0) + 10.0 * (W / 2.0)) / 12.0
		loadwords = "roof 30 psf over %g ft + ceiling 15 psf over %g ft = %.0f plf" % [W / 2.0 + 1.0, W / 2.0, wt * 12.0]
	else:
		wt = 80.0 / 12.0
		wlv = 0.0
		loadwords = "non-bearing, 80 plf of wall and gable above"
		tab = float(HEADER[sp_name][20].get(hs, -1)) if not dm.is_empty() else -1.0
		tok = tab > 0 and span <= tab
	var ph := {"pass": false, "fb": 0.0, "Fb_allow": 0.0, "fv": 0.0, "Fv_allow": 0.0, "defl": 0.0, "defl_lim": 1.0}
	if not dm.is_empty():
		ph = beam(dm[0], dm[1], dm[2], span, wt, wlv, cd, 1.0, 240.0, sp)
	var ag: bool = tok == ph["pass"]
	var ln := _line("%s wall opening %d header %s over %g ft" % [wall, k, hs, op["width_ft"]], "header", loadwords, "IRC 2021 R602.7 headers in exterior walls, %s" % sp_name, tok, span, tab,
		"span %s against table %s" % [fi(span), fi(tab) if tab > 0 else "none (outside the table)"] + _physwords(ph, ag))
	ln["phys"] = ph
	ln["agree"] = ag
	return ln


static func _bracing_line(nm: String, wl: Dictionary, wall_h: float, h: Dictionary) -> Dictionary:
	var length: float = wl["length_ft"]
	var panels: Array = (wl.get("bracing", []) as Array).duplicate(true)
	panels.sort_custom(func(a, b): return float(a["pos_ft"]) < float(b["pos_ft"]))
	var need := BRACE_FT_PER_25 * length / 25.0
	var min_len := 4.0 if wall_h <= 9.0 else 53.0 / 12.0
	var total := 0.0
	var problems: Array = []
	var prev_end := 0.0
	var first := true
	for p in panels:
		var pl: float = p["len_ft"]
		if pl + 1e-6 < min_len:
			problems.append("panel %g ft is under the %.2f ft minimum" % [pl, min_len])
		total += pl
		var gap: float = float(p["pos_ft"]) - prev_end
		if first and gap > BRACE_END_FT + 1e-6:
			problems.append("first panel starts %.1f ft from the line end (max %.1f)" % [gap, BRACE_END_FT])
		elif not first and gap > BRACE_MAX_GAP_FT + 1e-6:
			problems.append("%.1f ft between panels (max %.0f)" % [gap, BRACE_MAX_GAP_FT])
		first = false
		prev_end = float(p["pos_ft"]) + pl
	if panels.is_empty():
		problems.append("no braced wall panel")
	elif length - prev_end > BRACE_END_FT + 1e-6:
		problems.append("last panel ends %.1f ft from the line end (max %.1f)" % [length - prev_end, BRACE_END_FT])
	if total + 1e-6 < need:
		problems.append("%.1f ft of panel is under the %.1f ft needed" % [total, need])
	return _line("%s wall bracing line" % nm, "bracing", "%d mph, exposure %s, seismic %s (wind governs), %g ft line" % [int(h.get("wind_mph", 115)), h.get("exposure", "B"), h.get("seismic", "A-B"), length],
		"IRC 2021 R602.10.3 intermittent WSP bracing, Table R602.10.3(1)", problems.is_empty(), total, need,
		"%.1f ft of braced panel against %.1f ft needed%s" % [total, need, "" if problems.is_empty() else " (" + "; ".join(PackedStringArray(problems)) + ")"])


static func report(h: Dictionary) -> PackedStringArray:
	var o := PackedStringArray()
	for l in check(h):
		o.append(l["text"])
	o.append("tables: " + TABLES_SOURCE)
	return o


## Not checked by Kine: floor framing and second storeys, the load path below the sill (hold-downs, shear transfer), trusses and engineered lumber, snow other than 20 psf,
## notching and drilling, bearing under headers, seismic categories above B, a stamped design.
const NOT_CHECKED := ["floor framing and second storeys", "load path below the sill (hold-downs, shear transfer)", "trusses and engineered lumber", "snow loads other than 20 psf", "notching and drilling", "bearing under headers", "seismic design categories above B", "a stamped design"]
