class_name HouseCheck
extends RefCounted
## CH1b: does a one-floor wood-frame American house stand up? One line per member: its load, the IRC 2021 rule, pass / fail with the number.
##
## Input is a house record (see ranch()): walls with studs, openings + headers, bracing panels; ceiling joists; rafters + ridge; sill on a stem wall or slab;
## footing. Sizes are US nominal lumber ("2x6", headers "2-2x10"). Output of check(): Array of Dictionary
##   {member, kind, load, rule, pass, value, limit, text}   plus, for kind rafter / joist / header, {phys, agree}:
## phys = the SAME member worked from first principles (beam bending stress vs Fb', shear, deflection) and agree = table verdict == phys verdict.
##
## WHAT THE TABLE NUMBERS ARE: printed cells of the 2021 IRC, read 11-03 from the sources named at each table (the ICC site itself answered 403, so every source
## below is a mirror or a reproduction of the printed table, not the book). A rule whose cells could not be read says UNVERIFIED in its report line.
## Spans are inches; a printed "B" / "Note a" (span over 26 ft) is stored as 312 in (26 ft) and means "at least". The first-principles span (beam(), cells()) is worked from
## the NDS-2018-supplement design values (DF-L #2 Fb 900 Fv 180 E 1.6e6, SPF #2 Fb 875 Fv 135 E 1.4e6, CF size factor, Cr 1.15 for 24 in o.c. or less); the test bar says a
## printed cell is never more than 3 pct above it (tables round down, so physics may allow a little more, never less).
## Rules cited (IRC 2021): R802.4.1(1) rafter spans, R802.5.1(1) ceiling joists, R602.7(1) headers, R602.3(5) studs, R602.10.3(1) bracing, R802.11 uplift,
## R403.1(1) footings, R403.1.6 anchor bolts, R802.3 ridge board.

const TABLES_SOURCE := "span, header, bracing, footing cells are printed 2021 IRC values read from mirrors (ICC site blocked); lines marked UNVERIFIED could not be read"

## species -> design values (psi): Fb, Fv, E
const SPECIES := {"DF-L#2": {"Fb": 900.0, "Fv": 180.0, "E": 1.6e6}, "SPF#2": {"Fb": 875.0, "Fv": 135.0, "E": 1.4e6}}
## nominal -> [b, d, CF size factor for Fb]  (actual inches)
const SIZES := {"2x4": [1.5, 3.5, 1.5], "2x6": [1.5, 5.5, 1.3], "2x8": [1.5, 7.25, 1.2], "2x10": [1.5, 9.25, 1.1], "2x12": [1.5, 11.25, 1.0]}

## IRC 2021 Table R802.4.1(1) "Rafter spans", 20 psf live load, 10 psf dead load, ceiling NOT attached to rafters, L/180, Douglas Fir-Larch #2 and Spruce-Pine-Fir #2.
## Source: Code Check "Additional Rafter Span Tables" (codecheck.com/wp-content/uploads/2023/09/Additional-Rafter-Span-Tables.pdf, Table 45 = T802.4.1(1)); the 2x6 DF-L #2 row
## 16-10 / 14-7 / 13-3 / 11-11 (12 / 16 / 19.2 / 24 in) also appears in the Humboldt County NV and Greene County GA handouts. Columns here: 12, 16, 24 in o.c. (19.2 not stored).
const RAFTER := {
	"DF-L#2": {"2x4": [130, 118, 98], "2x6": [202, 175, 143], "2x8": [256, 221, 181], "2x10": [312, 270, 221], "2x12": [312, 312, 256]},
	"SPF#2": {"2x4": [124, 113, 96], "2x6": [195, 172, 141], "2x8": [252, 218, 178], "2x10": [308, 267, 218], "2x12": [312, 309, 252]},
}
## IRC 2021 Table R802.5.1(1) "Ceiling joist spans for common lumber species", uninhabitable attics without storage, 10 psf live, 5 psf dead, L/240.
## Source: up.codes 2021 IRC (Connecticut edition) chapter 8, up.codes/viewer/connecticut/irc-2021/chapter/8/roof-ceiling-construction; the DF-L #2 2x4/2x6/2x8 cells
## 12-5 / 19-6 / 25-8 (12 in), 11-3 / 17-8 / 23-4 (16 in), 9-10 / 15-0 / 19-1 (24 in) agree with the Sacramento CDD-0277 sheet (2022 CRC R802.5.1(1)). 2x10 at 12 and 16 in is "Note a" (over 26 ft).
const JOIST := {
	"DF-L#2": {"2x4": [149, 135, 118], "2x6": [234, 212, 180], "2x8": [308, 280, 229], "2x10": [312, 312, 279]},
	"SPF#2": {"2x4": [142, 129, 113], "2x6": [224, 203, 177], "2x8": [295, 268, 225], "2x10": [312, 312, 275]},
}
## IRC 2021 Table R602.7(1) "Girder and header spans for exterior bearing walls", roof and ceiling only, 30 psf ground snow, No. 2 grade (the table is species-independent),
## building width 12 / 24 / 36 ft (interpolation between widths is permitted by the table's note). Max clear span in inches. Built-up members only: a single 2x6 is not in the table.
## Sources: reuven.tools/reference/header-spans/ and up.codes 2021 IRC (Connecticut) chapter 6 agree cell for cell (2-ply 2x4..2x12, 3-ply 2x8..2x12).
const HEADER_W := [12.0, 24.0, 36.0]
const HEADER := {
	"2-2x4": [48, 37, 31], "2-2x6": [72, 55, 46], "2-2x8": [91, 69, 58], "2-2x10": [108, 82, 69], "2-2x12": [127, 97, 82],
	"3-2x8": [113, 87, 73], "3-2x10": [135, 103, 87], "3-2x12": [158, 121, 102],
}
## IRC 2021 Table R602.3(5), bearing walls supporting roof-ceiling only, one story: 2x4 and 2x6 at most 24 in o.c., unsupported height at most 10 ft.
## Source: up.codes 2021 IRC (Connecticut) chapter 6; the extraction of the column headings was garbled, so 10 ft is applied to 2x6 as well (the stricter reading).
## The non-bearing rows were not read: non-bearing walls are held to the bearing row too (stricter).
const STUD_BEARING := {"2x4": [24, 10.0], "2x6": [24, 10.0]}
const STUD_NONBEARING := {"2x4": [24, 10.0], "2x6": [24, 10.0]}
## IRC 2021 Table R602.10.3(1), method WSP, minimum total length (ft) of braced wall panel per braced wall line by spacing between braced wall lines (10..60 ft).
## Source: up.codes 2021 IRC (Connecticut) chapter 6, first block of the table (the story label is an image in the extraction: read as one story / top story, base 10 ft wall,
## 30 ft mean roof height, exposure B, two lines). Table R602.10.3(2) adjustments (8 ft wall: lower) are NOT applied, which is conservative. Seismic A-B (R602.10.3(3)) was not read: UNVERIFIED.
const BRACE_SPACING := [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
const BRACE_WSP := {110: [2.0, 3.5, 5.0, 6.5, 8.0, 9.5], 115: [2.0, 3.5, 5.5, 7.0, 9.0, 10.5], 120: [2.5, 4.0, 6.0, 8.0, 9.5, 11.5]}
const BRACE_MAX_GAP_FT := 20.0       # R602.10.2.2 distance between panel edges (from memory, not re-read online)
const BRACE_END_FT := 12.5           # R602.10.2.2 first / last panel starts within 12.5 ft of the line end (from memory, not re-read online)
## IRC 2021 R802.11 Exception 2 (read in FEMA "2021 IRC: A Compilation of Wind Resistant Provisions", Oct 2021, p. 42): rafters / trusses may be attached by Table R602.3(1) (toenails)
## where wind <= 115 mph, exposure B, pitch >= 5:12, roof span <= 32 ft and spacing <= 24 in o.c. Outside that, Table R802.11 applies; its 28 ft cells could NOT be read (only
## 12 ft / 12 in o.c. / 115 mph B: 59 lb under 5:12, 53 lb at 5:12 and up), so the estimate below is UNVERIFIED.
const UPLIFT_LB_PER_FT := 3.7        # UNVERIFIED estimate, lb per ft of span at 24 in o.c.
const TIES := {"toenail3-8d": 113.0, "H2.5A": 535.0, "none": 0.0}    # lb per connection (NDS withdrawal for 3-8d toenails; H2.5A catalogue): UNVERIFIED
## IRC 2021 Table R403.1(1), 20 psf roof live load, one story: slab-on-grade and crawl space 12 x 6 in at every soil value 1500..4000 psf; with basement 16 x 6 at 1500 psf, 12 x 6 from 2000
## (linear interpolation between soil values allowed, no extrapolation). Footnotes: table is for a 32 ft wide building; narrower may reduce but never below 12 x 6 (R403.1.1).
## Source: up.codes 2021 IRC (Connecticut) chapter 4. R403.1.1 projection >= 2 in; R403.1.6 anchor bolts 1/2 in at <= 6 ft, >= 2 per plate, within 12 in and >= 7 diameters of each end.
const FOOTING_BASEMENT := {1500: 16.0, 2000: 12.0}


## A code-conforming 28 x 40 ft ranch (the passing record the tests plant failures into). Lengths in ft, spacings and sizes as lumber says them.
static func ranch() -> Dictionary:
	var gable_panels := [{"pos_ft": 0.0, "len_ft": 4.5}, {"pos_ft": 23.5, "len_ft": 4.5}]
	var long_panels := [{"pos_ft": 0.0, "len_ft": 4.0}, {"pos_ft": 18.0, "len_ft": 4.0}, {"pos_ft": 36.0, "len_ft": 4.0}]
	return {
		"species": "DF-L#2", "width_ft": 28.0, "length_ft": 40.0, "wall_h_ft": 8.0,
		"loads": {"roof": "live", "psf": 20.0}, "wind_mph": 115, "exposure": "B", "seismic": "A-B",
		"walls": [
			{"name": "front", "length_ft": 40.0, "line_spacing_ft": 28.0, "stud": "2x4", "spacing_in": 16, "bearing": true,
				"openings": [{"width_ft": 6.0, "header": "2-2x10"}, {"width_ft": 3.0, "header": "2-2x10"}], "bracing": long_panels.duplicate(true)},
			{"name": "rear", "length_ft": 40.0, "line_spacing_ft": 28.0, "stud": "2x4", "spacing_in": 16, "bearing": true,
				"openings": [{"width_ft": 6.0, "header": "2-2x10"}, {"width_ft": 3.0, "header": "2-2x10"}], "bracing": long_panels.duplicate(true)},
			{"name": "left gable", "length_ft": 28.0, "line_spacing_ft": 40.0, "stud": "2x4", "spacing_in": 16, "bearing": false,
				"openings": [{"width_ft": 3.0, "header": "2-2x6"}], "bracing": gable_panels.duplicate(true)},
			{"name": "right gable", "length_ft": 28.0, "line_spacing_ft": 40.0, "stud": "2x4", "spacing_in": 16, "bearing": false,
				"openings": [], "bracing": gable_panels.duplicate(true)},
		],
		"ceiling_joists": {"size": "2x8", "spacing_in": 16, "interior_bearing_wall": true},
		"rafters": {"size": "2x6", "spacing_in": 16, "rise_per_12": 6.0, "ridge": "2x8", "tie": "H2.5A"},
		"sill": {"on": "stem_wall", "lumber": "2x6", "bolt_dia_in": 0.5, "bolt_spacing_in": 72.0, "bolt_from_end_in": 9.0},
		"footing": {"type": "crawl", "width_in": 12.0, "thickness_in": 8.0, "wall_in": 8.0, "soil_psf": 1500},
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
	if snow:
		rtab = -1.0      # only Table R802.4.1(1) (20 psf roof live) is loaded; the snow tables (3)-(8) are not, so a snow house gets the physics only
	var rok_tab := rtab > 0 and rspan <= rtab and absf(live_psf - 20.0) < 0.01
	var rphys := beam(rdim[0], rdim[1], rdim[2], rspan, (live_psf + rd) * rsp / 144.0, live_psf * rsp / 144.0, cd_roof, 1.15 if rsp <= 24.0 else 1.0, 180.0, sp)
	var ragree: bool = rok_tab == rphys["pass"]
	var rl := _line("rafters %s @%d in" % [rs, int(rsp)], "rafter", "%.0f psf %s + %.0f psf dead on the %s horizontal span" % [live_psf, "snow" if snow else "roof live", rd, fi(rspan)],
		"IRC 2021 R802.4 rafter spans, %s, L/180" % sp_name, rok_tab, rspan, rtab,
		"span %s against table %s" % [fi(rspan), fi(rtab) if rtab > 0 else "none (outside the table: UNVERIFIED for this load)"] + _physwords(rphys, ragree))
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
	var exc2: bool = int(h.get("wind_mph", 115)) <= 115 and h.get("exposure", "B") == "B" and rise >= 5.0 and W <= 32.0 and rsp <= 24.0
	var demand := UPLIFT_LB_PER_FT * W * rsp / 24.0
	var cap: float = TIES.get(tie, 0.0)
	var loadw := "%d mph, exposure %s, %g/12 pitch, %g ft roof span, rafters %d in o.c." % [int(h.get("wind_mph", 115)), h.get("exposure", "B"), rise, W, int(rsp)]
	if exc2:
		out.append(_line("roof to wall ties (%s)" % tie, "uplift", loadw, "IRC 2021 R802.11 Exception 2 (wind <= 115 mph, exposure B, pitch >= 5:12, span <= 32 ft, <= 24 in o.c.): attach by Table R602.3(1)",
			tie != "none", 0.0, 0.0, "no uplift calculation needed; ties present: %s" % tie))
	else:
		out.append(_line("roof to wall ties (%s)" % tie, "uplift", loadw, "IRC 2021 Table R802.11 (UNVERIFIED: this span's cells could not be read, estimate used)",
			cap >= demand, demand, cap, "UNVERIFIED estimate: uplift %.0f lb per rafter against the connector's %.0f lb" % [demand, cap]))
	# ---- sill and footing (R403.1)
	var S: Dictionary = h["sill"]
	var bd: float = S.get("bolt_dia_in", 0.5)
	var bs: float = S.get("bolt_spacing_in", 72.0)
	var be: float = S.get("bolt_from_end_in", 9.0)
	var sill_ok: bool = bd >= 0.5 and bs <= 72.0 and be <= 12.0 and be >= 7.0 * bd
	out.append(_line("sill plate on %s" % str(S.get("on", "slab")).replace("_", " "), "sill", "anchor bolts %.3g in dia at %d in, %d in from each plate end" % [bd, int(bs), int(be)],
		"IRC 2021 R403.1.6 anchor bolts (1/2 in, 6 ft o.c., within 12 in and 7 diameters of each end)", sill_ok, bs, 72.0, "spacing %d in against max 72 in, end distance %d in within %.1f to 12 in" % [int(bs), int(be), 7.0 * bd]))
	var F: Dictionary = h["footing"]
	var soil := float(F.get("soil_psf", 1500))
	var ftype: String = F.get("type", "crawl")
	var need := 12.0
	if ftype == "basement":
		need = _interp([1500.0, 2000.0], [16.0, 12.0], soil)
	if soil < 1500.0:
		need = -1.0
	var fw: float = F.get("width_in", 0.0)
	var ft: float = F.get("thickness_in", 0.0)
	var proj := (fw - float(F.get("wall_in", 8.0))) / 2.0
	out.append(_line("footing (%s)" % ftype, "footing", "one story, 20 psf roof live, %d psf soil" % int(soil), "IRC 2021 Table R403.1(1) width, R403.1.1 thickness 6 in and projection 2 in",
		need > 0 and fw >= need and ft >= 6.0 and proj >= 2.0, fw, need,
		"width %g in against %s, thickness %g in against 6 in, projection %.1f in against 2 in" % [fw, ("%g in" % need) if need > 0 else "none (soil under 1500 psf needs an engineer)", ft, proj]))
	return out


## Table R602.7(1) max clear span (in) for a built-up header at building width W (ft), interpolated between the 12 / 24 / 36 ft columns as the table's note allows. -1 = not tabulated / outside 12..36.
static func header_table(hs: String, W: float) -> float:
	if not HEADER.has(hs) or W < 12.0 or W > 36.0:
		return -1.0
	var v: Array = HEADER[hs]
	var k := 0 if W <= 24.0 else 1
	var t: float = (W - HEADER_W[k]) / (HEADER_W[k + 1] - HEADER_W[k])
	return floor(float(v[k]) + (float(v[k + 1]) - float(v[k])) * t)


## Header load on the basis of Table R602.7(1): 30 psf ground snow = 21 psf roof snow, 10 psf roof dead over W/2 + 2 ft overhang, ceiling 10 live + 5 dead over W/2. lb per inch: [total, live].
static func header_load(W: float) -> Array:
	return [((21.0 + 10.0) * (W / 2.0 + 2.0) + 15.0 * (W / 2.0)) / 12.0, (21.0 * (W / 2.0 + 2.0) + 10.0 * (W / 2.0)) / 12.0]


static func _header_line(wall: String, k: int, op: Dictionary, bearing: bool, W: float, sp_name: String, sp: Dictionary, cd: float) -> Dictionary:
	var hs: String = op["header"]
	var span: float = op["width_ft"] * 12.0
	var dm := _dims(hs)
	var tab := header_table(hs, W)
	var tok := tab > 0 and span <= tab
	var ld := header_load(W)
	var ph := {"pass": false, "fb": 0.0, "Fb_allow": 0.0, "fv": 0.0, "Fv_allow": 0.0, "defl": 0.0, "defl_lim": 1.0}
	if not dm.is_empty():
		ph = beam(dm[0], dm[1], dm[2], span, ld[0], ld[1], 1.15, 1.0, 240.0, sp)
	var ag: bool = tok == ph["pass"]
	var loadwords := "30 psf ground snow: roof 31 psf over %g ft + ceiling 15 psf over %g ft = %.0f plf%s" % [W / 2.0 + 2.0, W / 2.0, ld[0] * 12.0, "" if bearing else " (non-bearing wall held to the bearing table)"]
	var ln := _line("%s wall opening %d header %s over %g ft" % [wall, k, hs, op["width_ft"]], "header", loadwords, "IRC 2021 R602.7(1) headers in exterior bearing walls, roof and ceiling, 30 psf ground snow", tok, span, tab,
		"span %s against table %s" % [fi(span), fi(tab) if tab > 0 else "none (not a tabulated built-up header, or width outside 12-36 ft)"] + _physwords(ph, ag))
	ln["phys"] = ph
	ln["agree"] = ag
	return ln


static func _bracing_line(nm: String, wl: Dictionary, wall_h: float, h: Dictionary) -> Dictionary:
	var length: float = wl["length_ft"]
	var panels: Array = (wl.get("bracing", []) as Array).duplicate(true)
	panels.sort_custom(func(a, b): return float(a["pos_ft"]) < float(b["pos_ft"]))
	var spacing: float = wl.get("line_spacing_ft", 28.0)
	var wind := 110 if int(h.get("wind_mph", 115)) <= 110 else (115 if int(h.get("wind_mph", 115)) <= 115 else 120)
	var need := _interp(BRACE_SPACING, BRACE_WSP[wind], spacing)
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
	return _line("%s wall bracing line" % nm, "bracing", "%d mph, exposure %s, %g ft line, %g ft to the next braced wall line, seismic %s not read (UNVERIFIED)" % [int(h.get("wind_mph", 115)), h.get("exposure", "B"), length, spacing, h.get("seismic", "A-B")],
		"IRC 2021 Table R602.10.3(1) method WSP, panel spacing and end rules R602.10.2.2 (not re-read online)", problems.is_empty(), total, need,
		"%.1f ft of braced panel against %.1f ft needed%s" % [total, need, "" if problems.is_empty() else " (" + "; ".join(PackedStringArray(problems)) + ")"])


## First-principles max span (in) of a member: the least of bending, shear and live-load deflection.
static func phys_span(b: float, d: float, cf: float, w_tot: float, w_live: float, cd: float, cr: float, lim: float, sp: Dictionary) -> float:
	var S := b * d * d / 6.0
	var I := b * d * d * d / 12.0
	var lb := sqrt(8.0 * float(sp["Fb"]) * cd * cf * cr * S / w_tot)
	var ls := 2.0 * float(sp["Fv"]) * cd * (b * d) / (1.5 * w_tot)
	var ld := pow(384.0 * float(sp["E"]) * I / (5.0 * w_live * lim), 1.0 / 3.0)
	return minf(lb, minf(ls, ld))


## Every printed cell against its first-principles span: [{name, printed, phys, ratio, capped}] (capped = the printed cell is "over 26 ft", stored as 312, so only a lower bound).
static func cells() -> Array:
	var o: Array = []
	for spn in ["DF-L#2", "SPF#2"]:
		var sp: Dictionary = SPECIES[spn]
		for kind in ["rafter", "joist"]:
			var T: Dictionary = RAFTER if kind == "rafter" else JOIST
			for sz in T[spn]:
				var dm: Array = SIZES[sz]
				for i in 3:
					var s_in: float = [12.0, 16.0, 24.0][i]
					var ph: float
					if kind == "rafter":
						ph = phys_span(dm[0], dm[1], dm[2], 30.0 * s_in / 144.0, 20.0 * s_in / 144.0, 1.25, 1.15, 180.0, sp)
					else:
						ph = phys_span(dm[0], dm[1], dm[2], 15.0 * s_in / 144.0, 10.0 * s_in / 144.0, 1.0, 1.15, 240.0, sp)
					var pr: float = float(T[spn][sz][i])
					o.append({"name": "%s %s %s @%d" % [kind, spn, sz, int(s_in)], "printed": pr, "phys": ph, "ratio": pr / ph, "capped": pr >= 312.0})
	var sp0: Dictionary = SPECIES["DF-L#2"]
	for hs in HEADER:
		var pl := int(str(hs).substr(0, 1))
		var dm2: Array = SIZES[str(hs).substr(2)]
		for i in 3:
			var ld := header_load(HEADER_W[i])
			var ph2 := phys_span(dm2[0] * pl, dm2[1], dm2[2], ld[0], ld[1], 1.15, 1.0, 240.0, sp0)
			var pr2: float = float(HEADER[hs][i])
			o.append({"name": "header %s @%d ft wide" % [hs, int(HEADER_W[i])], "printed": pr2, "phys": ph2, "ratio": pr2 / ph2, "capped": false})
	return o


static func _interp(xs: Array, ys: Array, x: float) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			return ys[i - 1] + (ys[i] - ys[i - 1]) * (x - xs[i - 1]) / (xs[i] - xs[i - 1])
	return ys[ys.size() - 1]



static func report(h: Dictionary) -> PackedStringArray:
	var o := PackedStringArray()
	for l in check(h):
		o.append(l["text"])
	o.append("tables: " + TABLES_SOURCE)
	return o


## Not checked by Kine: floor framing and second storeys, the load path below the sill (hold-downs, shear transfer), trusses and engineered lumber, snow other than 20 psf,
## notching and drilling, bearing under headers, seismic categories above B, a stamped design.
const NOT_CHECKED := ["floor framing and second storeys", "load path below the sill (hold-downs, shear transfer)", "trusses and engineered lumber", "snow loads other than 20 psf", "notching and drilling", "bearing under headers", "seismic design categories above B", "a stamped design"]
