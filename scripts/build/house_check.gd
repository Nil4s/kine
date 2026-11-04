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
## CH1d: columns 130 and 140 (printed "<= 130" and "< 140") read from up.codes 2021 IRC (Connecticut) ch.6 on 11-03. Above 140 the table ends: R301.2.1.1 sends the design to AWC WFCM / ICC 600 / ASCE 7.
const BRACE_WSP := {110: [2.0, 3.5, 5.0, 6.5, 8.0, 9.5], 115: [2.0, 3.5, 5.5, 7.0, 9.0, 10.5], 120: [2.5, 4.0, 6.0, 8.0, 9.5, 11.5],
	130: [2.5, 5.0, 7.0, 9.0, 11.0, 13.0], 140: [3.0, 5.5, 8.0, 10.5, 13.0, 15.0]}
## Table R602.10.3(2) item 1, one story: exposure B 1.00, C 1.20, D 1.50 (up.codes, read 11-03). The 8 ft wall factor 0.90 is NOT applied (conservative).
const EXPOSURE_BRACE := {"B": 1.0, "C": 1.2, "D": 1.5}
const BRACE_MAX_GAP_FT := 20.0       # R602.10.2.2 distance between adjacent panel edges, not greater than 20 ft (READ 11-03, up.codes ch.6)
const BRACE_END_FT := 10.0           # R602.10.2.2 "a braced wall panel shall begin within 10 feet from each end of a braced wall line" (READ 11-03; the 12.5 ft held here before was wrong)
## IRC 2021 R802.11 Exception 2 (read in FEMA "2021 IRC: A Compilation of Wind Resistant Provisions", Oct 2021, p. 42): rafters / trusses may be attached by Table R602.3(1) (toenails)
## where wind <= 115 mph, exposure B, pitch >= 5:12, roof span <= 32 ft and spacing <= 24 in o.c. Outside that, Table R802.11 applies; its 28 ft cells could NOT be read (only
## 12 ft / 12 in o.c. / 115 mph B: 59 lb under 5:12, 53 lb at 5:12 and up), so the estimate below is UNVERIFIED.
const UPLIFT_LB_PER_FT := 3.7        # UNVERIFIED estimate, lb per ft of span at 24 in o.c.
## CH1d: H2.5A uplift (160 duration) from Simpson Strong-Tie's H2.5A page (strongtie.com, via search summary 11-03): 635 lb DF/SP with 0.131x1.5 in nails, SPF/HF x 0.86; one retailer lists 625 / 540. The LOWER
## pair is used. The toenail figure (NDS withdrawal of 3-8d) stays UNVERIFIED.
const TIES := {"toenail3-8d": 113.0, "H2.5A": 625.0, "none": 0.0}
const TIE_SPF := {"H2.5A": 540.0}
const TIES_UNVERIFIED := ["toenail3-8d"]
## IRC 2021 Table R802.11 roof uplift connection forces, lb per connection, EXPOSURE B, 15 psf roof+ceiling dead load, 33 ft mean roof height; read 11-03 from up.codes 2021 IRC (Connecticut) ch.8.
## rows: rafter spacing -> roof span (ft) -> [110<5:12, 110>=5:12, 115<5:12, 115>=5:12, 120<, 120>=, 130<, 130>=, 140<, 140>=]. Table notes: x0.75 for connections not within 8 ft of building corners (not used here).
const UPLIFT_V := [110, 115, 120, 130, 140]
const UPLIFT := {
	24: {24: [142, 124, 178, 158, 216, 196, 298, 274, 384, 356], 28: [158, 138, 198, 176, 242, 218, 334, 306, 432, 400]},
	16: {24: [94, 82, 118, 105, 144, 130, 198, 182, 255, 237], 28: [105, 92, 132, 117, 161, 145, 222, 203, 287, 266]},
	12: {24: [71, 62, 89, 79, 108, 98, 149, 137, 192, 178], 28: [79, 69, 99, 88, 121, 109, 167, 153, 216, 200]},
}
## IRC 2021 Table R602.7.5 jack studs at each end of a header, exterior walls (up.codes ch.6 11-03). rows: header span 4..18 ft. col A: < 140 mph exp B or < 130 mph exp C; col B: <= 115 mph exp B.
const JACK_SPAN := [4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0]
const JACK_A := [1, 2, 2, 3, 3, 3, 4, 4]
const JACK_B := [1, 1, 1, 2, 2, 2, 2, 2]
const FC_PERP := {"DF-L#2": 625.0, "SPF#2": 425.0}     # NDS 2018 supplement compression perpendicular to grain, psi (from memory of the supplement table: UNVERIFIED)
const WALL_T_IN := 3.5

## IRC 2021 Table R602.3(1) fastener schedule rows used here (up.codes ch.6, read 11-03; item numbers differ between mirrors, so rows are cited by description).
## d = penny size, type "box" < "common" (a common nail of the same size is stronger), n = nails per connection, spacing_in = 0 for a per-connection count.
const FASTENERS := {
	"stud_to_plate": {"text": "top or bottom plate to stud: 4-8d box toe nail", "d": 8, "n": 4, "spacing_in": 0, "type": "box"},
	"joist_to_plate": {"text": "ceiling joist to top plate: 4-8d box toe nail", "d": 8, "n": 4, "spacing_in": 0, "type": "box"},
	"rafter_to_plate": {"text": "rafter to plate: 3-16d box (2 toe nails one side, 1 opposite)", "d": 16, "n": 3, "spacing_in": 0, "type": "box"},
	"rafter_to_ridge": {"text": "rafter to ridge: 4-16d box toe nail", "d": 16, "n": 4, "spacing_in": 0, "type": "box"},
	"plate_to_plate": {"text": "top plate to top plate: 16d common face nail at 16 in o.c.", "d": 16, "n": 1, "spacing_in": 16, "type": "common"},
	"plate_lap": {"text": "top plate laps at corners and intersections: 3-10d box face nail", "d": 10, "n": 3, "spacing_in": 0, "type": "box"},
	"stud_to_stud": {"text": "stud to stud (king / jack / nailer): 16d common face nail at 24 in o.c.", "d": 16, "n": 1, "spacing_in": 24, "type": "common"},
	"header_built_up": {"text": "built-up header (2 to 2 with 1/2 in spacer): 16d common at 16 in o.c. each edge", "d": 16, "n": 1, "spacing_in": 16, "type": "common"},
	"header_to_stud": {"text": "header to king stud: 5-8d box toe nail", "d": 8, "n": 5, "spacing_in": 0, "type": "box"},
}
## Sheathing: Table R602.3(1) wood structural panel 3/8 to 1/2 in (7/16 OSB falls here): 6d common or deformed, 6 in o.c. at panel edges, 12 in in the field. The wind-resistance Table R602.3(3) cell
## for 7/16 at high wind was NOT read: that is why the wind clause is marked.
const SHEATH_NAIL := {"d": 6, "edge_in": 6.0, "field_in": 12.0}
## IRC 2021 R403.1.6 anchor bolt embedment: 7 in minimum into concrete (from the section as I know it; the mirror fetch did not return this paragraph: stated, not re-read).
const ANCHOR_EMBED_IN := 7.0
## IRC 2021 R802.7.1 -> R502.8.1: notches at the ENDS of a rafter at most 1/4 of its depth (READ 11-03); R802.6 bearing at least 1.5 in on wood (READ). The 1/3 figure quoted in blogs is NOT in the 2021 text.
const NOTCH_END_FRAC := 0.25
const RAFTER_BEARING_IN := 1.5
## IRC 2021 Table R403.1(1), 20 psf roof live load, one story: slab-on-grade and crawl space 12 x 6 in at every soil value 1500..4000 psf; with basement 16 x 6 at 1500 psf, 12 x 6 from 2000
## (linear interpolation between soil values allowed, no extrapolation). Footnotes: table is for a 32 ft wide building; narrower may reduce but never below 12 x 6 (R403.1.1).
## Source: up.codes 2021 IRC (Connecticut) chapter 4. R403.1.1 projection >= 2 in; R403.1.6 anchor bolts 1/2 in at <= 6 ft, >= 2 per plate, within 12 in and >= 7 diameters of each end.
const FOOTING_BASEMENT := {1500: 16.0, 2000: 12.0}


## CH1d: SITE RECORDS. Two sample sites, STORED (no live call). lat/lon/zip and exposure/soil are the record's inputs; the load values say where they came from and how well:
##  wind_mph = ultimate design wind speed Vult, ASCE 7-16 Risk Category II (the IRC 2021 tables are keyed to Vult; R301.2.1)
##  ground_snow_psf = Pg     sdc = seismic design category     soil_class = ASCE 7 site class (D is the ASCE 7 default when no geotechnical report exists)
## lookup_status says per value: "read" (a document was opened this session) or "memory" (the ASCE Hazard Tool is a script-only page and the NYS PDF came back unreadable; the value is what I know, and
## it stays UNVERIFIED SITE until Nick or a PE pastes the tool's report).
const SITES := {
	"levittown_ny": {"name": "Levittown, Nassau County, NY", "lat": 40.7259, "lon": -73.5143, "zip": "11756", "exposure": "B", "soil_class": "D", "soil_bearing_psf": 1500,
		"wind_mph": 130, "ground_snow_psf": 25.0, "sdc": "B", "risk": "II",
		"edition": "IRC 2021 (ICC). New York State adopts it as the NYS Residential Code (the 2025 edition is 2021-IRC based, per the Town of Ithaca R301.2 file name); Town of Hempstead amendments NOT read",
		"source": "wind 130 mph = ASCE 7-16 RC II for Nassau County, from memory (UNVERIFIED SITE); snow 25 psf = NYS ground-snow map, from memory (UNVERIFIED SITE); SDC B from low Ss and default class D (UNVERIFIED SITE); soil 1500 psf = IRC R401.4.1 presumptive value, assumed",
		"lookup_status": {"wind_mph": "memory", "ground_snow_psf": "memory", "sdc": "memory", "soil_class": "ASCE 7 default D", "exposure": "chosen: suburban, B"}},
	"miami_fl": {"name": "Miami, Miami-Dade County, FL (HVHZ)", "lat": 25.7617, "lon": -80.1918, "zip": "33130", "exposure": "C", "soil_class": "D", "soil_bearing_psf": 2000,
		"wind_mph": 175, "ground_snow_psf": 0.0, "sdc": "A", "risk": "II",
		"edition": "Florida Building Code, Residential, 8th ed. (2023) on the IRC 2021. Miami-Dade is the High-Velocity Hurricane Zone: the prescriptive IRC tables do not reach it, a stamped design does",
		"source": "wind 175 mph = Miami-Dade RC II as reported by Wikipedia's Florida Building Code table and a NACHI HVHZ thread (secondary; FIU's table says 170; the ASCE edition behind it not confirmed); exposure C = Miami-Dade per an FBC overview; snow 0; SDC A from low Ss (memory, UNVERIFIED SITE); soil 2000 psf assumed",
		"lookup_status": {"wind_mph": "read, secondary (175; one source 170)", "ground_snow_psf": "none in Florida", "sdc": "memory", "soil_class": "ASCE 7 default D", "exposure": "read: Miami-Dade is exposure C"}},
}


## a copy of record h with the site's loads in it: every rule reads these (wind -> bracing, ties, anchorage, site range; snow -> roof load and header table; exposure -> bracing and ties; soil -> footing; SDC -> seismic line)
static func with_site(h: Dictionary, site_id: String) -> Dictionary:
	var o: Dictionary = h.duplicate(true)
	var st: Dictionary = SITES[site_id]
	o["site"] = st.duplicate(true)
	o["site"]["id"] = site_id
	o["wind_mph"] = st["wind_mph"]
	o["exposure"] = st["exposure"]
	o["seismic"] = st["sdc"]
	if o.has("footing"):
		o["footing"]["soil_psf"] = st["soil_bearing_psf"]
	return o


## roof uplift per connection (lb) from Table R802.11 for wind v (mph), exposure, pitch rise/12, roof span W (ft), rafter spacing: [lb, notes]. The notes list every way the number leaves the printed cells.
static func uplift_demand(v: float, exposure: String, rise: float, W: float, rsp: float) -> Array:
	var note: Array = []
	if rsp > 24.0:
		return [-1.0, ["spacing over 24 in is outside the table"]]
	var sp := 24 if rsp > 16.0 else (16 if rsp > 12.0 else 12)
	var col := 0
	var vv := clampf(v, 110.0, 140.0)
	for i in UPLIFT_V.size():
		if vv <= float(UPLIFT_V[i]) + 1e-6:
			col = i
			break
	var idx := col * 2 + (1 if rise >= 5.0 else 0)
	var r24: float = UPLIFT[sp][24][idx]
	var r28: float = UPLIFT[sp][28][idx]
	var base := r24
	if W > 24.0:
		base = r24 + (r28 - r24) * minf(W - 24.0, 4.0) / 4.0
	if W > 28.0:
		base = r28 * W / 28.0
		note.append("span %s ft is past the stored 28 ft row, scaled by W/28 (estimate)" % g(W))
	if v > 140.0:
		base = base * pow(v / 140.0, 2.0)
		note.append("EXTRAPOLATED past the 140 mph column by (V/140)^2 = %.2f: Table R802.11 ends at 140 mph" % pow(v / 140.0, 2.0))
	if exposure != "B":
		var f: float = EXPOSURE_BRACE.get(exposure, 1.5)
		base *= f
		note.append("exposure %s: the exposure B cells x %s (the R602.10.3(2) factor; the exposure C columns of R802.11 were not read) (estimate)" % [exposure, g(f)])
	return [base, note]


static func tie_capacity(tie: String, species: String) -> float:
	if species == "SPF#2" and TIE_SPF.has(tie):
		return TIE_SPF[tie]
	return TIES.get(tie, 0.0)


## ASD tension capacity (lb) of one cast-in anchor bolt: least of A307 steel and ACI 318 concrete breakout (f'c 2500, phi 0.65, ASD /1.6, edge and group effect lumped as 0.5). A hand calc, UNVERIFIED.
static func anchor_capacity(dia: float, embed: float) -> float:
	var dd := dia - 0.9743 / 8.0
	var ase := 0.7854 * dd * dd      # threaded area, 8 threads per in
	var steel := 0.75 * 60000.0 * ase * 0.75 / 1.6
	var nb := 24.0 * sqrt(2500.0) * pow(embed, 1.5)
	var conc := nb * 0.5 * 0.65 / 1.6
	return minf(steel, conc)


## the connection types (keys of FASTENERS) a member list has, from the member kinds present
static func connections_of(kinds: Array) -> Array:
	var o: Array = []
	var has := func(k): return kinds.has(k)
	if ["stud", "king", "jack", "cripple", "corner", "gable_stud", "end"].any(has):
		o.append("stud_to_plate")
	if kinds.has("joist"):
		o.append("joist_to_plate")
	if ["rafter", "rafter_pair"].any(has):
		o.append("rafter_to_plate")
	if kinds.has("ridge"):
		o.append("rafter_to_ridge")
	if kinds.has("top_plate2"):
		o.append("plate_to_plate")
		o.append("plate_lap")
	if ["king", "jack", "nailer"].any(has):
		o.append("stud_to_stud")
	if kinds.has("header"):
		o.append("header_built_up")
		o.append("header_to_stud")
	return o


static func _pen_ok(have: Dictionary, need: Dictionary) -> bool:
	var rank := {"box": 0, "common": 1}
	if int(have.get("d", 0)) < int(need["d"]) or int(have.get("n", 0)) < int(need["n"]):
		return false
	if int(rank.get(have.get("type", "box"), 0)) < int(rank[need["type"]]):
		return false
	return float(need["spacing_in"]) <= 0.0 or float(have.get("spacing_in", 999.0)) <= float(need["spacing_in"]) + 1e-6


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


## like C printf %g (GDScript's % has no g): at most 3 decimals, no trailing zeros
static func g(x: float) -> String:
	var t := "%.3f" % x
	while t.contains(".") and (t.ends_with("0") or t.ends_with(".")):
		t = t.left(t.length() - 1)
	return t


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
	var live_psf: float = loads.get("psf", 20.0)
	var site: Dictionary = h.get("site", {})
	var gsnow: float = float(site.get("ground_snow_psf", 0.0))
	if 0.7 * gsnow > live_psf:       # flat-roof snow 0.7 Pg (ASCE 7 Ce = Ct = I = 1) beats the 20 psf roof live load
		snow = true
		live_psf = 0.7 * gsnow
	var cd_roof := 1.15 if snow else 1.25
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
	out.append(_line("ridge board", "ridge", "rafter plumb cut %.2f in deep at %s/12" % [cut, g(rise)], "IRC 2021 R802.3 ridge board at least as deep as the rafter cut", rg_d >= cut, rg_d, cut,
		"ridge %s is %.2f in deep, the rafter cut is %.2f in" % [R.get("ridge", "?"), rg_d, cut]))
	# rafter ties: ceiling joists parallel to the rafters keep the walls from spreading (R802.3.1)
	var has_cj: bool = h.has("ceiling_joists") and not (h["ceiling_joists"] as Dictionary).is_empty()
	out.append(_line("rafter ties", "tie", "outward thrust of a %s/12 roof at the plate" % g(rise), "IRC 2021 R802.3.1 ceiling joists as rafter ties, lower third of the rafter", has_cj, 1.0 if has_cj else 0.0, 1.0,
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
		out.append(_line("%s wall studs %s @%d in" % [nm, ss, int(sps)], "stud", "%s wall, %s ft high, roof + ceiling only (one story)" % ["bearing" if bearing else "non-bearing", g(wall_h)],
			"IRC 2021 R602.3(5) stud size, height, spacing", sok, sps, float(row[0]), "spacing %d in against max %d in, height %s ft against max %s ft" % [int(sps), int(row[0]), g(wall_h), g(float(row[1]))]))
		var k := 0
		for op in wl.get("openings", []):
			k += 1
			out.append(_header_line(nm, k, op, bearing, W, sp_name, sp, cd_roof, gsnow))
			if op.has("jacks"):
				out.append(_jack_line(nm, k, op, W, sp_name, h))
		if wl.get("braced", true):
			out.append(_bracing_line(nm, wl, wall_h, h))
	# ---- uplift (R802.11)
	var tie: String = R.get("tie", "none")
	var wmph := float(h.get("wind_mph", 115))
	var expo: String = h.get("exposure", "B")
	var exc2: bool = wmph <= 115.0 and expo == "B" and rise >= 5.0 and W <= 32.0 and rsp <= 24.0
	var cap: float = tie_capacity(tie, sp_name)
	var loadw := "%d mph, exposure %s, %s/12 pitch, %s ft roof span, rafters %d in o.c." % [int(wmph), expo, g(rise), g(W), int(rsp)]
	var upd := uplift_demand(wmph, expo, rise, W, rsp)
	var demand: float = upd[0]
	var unotes: Array = upd[1]
	var tag := "ESTIMATE past the printed cells: " if unotes.size() > 0 else ""
	if exc2:
		out.append(_line("roof to wall ties (%s)" % tie, "uplift", loadw, "IRC 2021 R802.11 Exception 2 (wind <= 115 mph, exposure B, pitch >= 5:12, span <= 32 ft, <= 24 in o.c.): attach by Table R602.3(1)",
			tie != "none", 0.0, 0.0, "no uplift calculation needed; ties present: %s" % tie))
	else:
		var extra := "; ".join(PackedStringArray(unotes))
		out.append(_line("roof to wall ties (%s)" % tie, "uplift", loadw, "IRC 2021 Table R802.11 uplift connection force against the connector (rated %.0f lb)" % cap,
			demand >= 0.0 and cap >= demand, demand, cap, "%suplift %.0f lb per rafter against the connector's %.0f lb%s%s" % [tag, demand, cap, ("; " + extra) if extra != "" else "",
			"; the toenail capacity is UNVERIFIED" if TIES_UNVERIFIED.has(tie) else ""]))
	# ---- sill and footing (R403.1)
	var S: Dictionary = h["sill"]
	var bd: float = S.get("bolt_dia_in", 0.5)
	var bs: float = S.get("bolt_spacing_in", 72.0)
	var be: float = S.get("bolt_from_end_in", 9.0)
	var sill_ok: bool = bd >= 0.5 and bs <= 72.0 and be <= 12.0 and be >= 7.0 * bd
	out.append(_line("sill plate on %s" % str(S.get("on", "slab")).replace("_", " "), "sill", "anchor bolts %s in dia at %d in, %d in from each plate end" % [g(bd), int(bs), int(be)],
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
		"width %s in against %s, thickness %s in against 6 in, projection %.1f in against 2 in" % [g(fw), (g(need) + " in") if need > 0 else "none (soil under 1500 psf needs an engineer)", g(ft), proj]))
	_new_rules(h, out, sp_name, rdim, rise, demand, wmph, expo)
	return out


## CH1d rules: site range, seismic, fastener schedule, sheathing nailing, birdsmouth, anchorage below the sill. Each only when the record carries its input.
static func _new_rules(h: Dictionary, out: Array, sp_name: String, rdim: Array, rise: float, uplift_lb: float, wmph: float, expo: String) -> void:
	var site: Dictionary = h.get("site", {})
	if not site.is_empty():
		var vmax := 140.0 if expo == "B" else 130.0
		var loadw := "Vult %d mph exposure %s, soil class %s, ground snow %s psf, SDC %s (lat %.4f lon %.4f)" % [int(wmph), expo, site.get("soil_class", "?"), g(float(site.get("ground_snow_psf", 0.0))), site.get("sdc", "?"), float(site.get("lat", 0.0)), float(site.get("lon", 0.0))]
		out.append(_line("site wind range (%s)" % site.get("name", "?"), "site", loadw,
			"IRC 2021 R301.2.1 with Tables R602.10.3(1), R802.11, R602.7.5: the prescriptive wind columns end below 140 mph (exposure B) / 130 mph (exposure C); beyond that R301.2.1.1 sends the design to AWC WFCM, ICC 600 or ASCE 7",
			wmph < vmax, wmph, vmax, "Vult %d mph against the prescriptive limit %d mph%s | edition: %s | site values: %s" % [int(wmph), int(vmax), "" if wmph < vmax else " -> NEEDS A STAMPED DESIGN, the tables do not cover this site", site.get("edition", ""), site.get("source", "")]))
		var sdc: String = site.get("sdc", "B")
		var seis_ok: bool = sdc in ["A", "B"]
		out.append(_line("seismic bracing (SDC %s)" % sdc, "seismic", "SDC %s, one story, wood frame" % sdc,
			"IRC 2021 R602.10.3(3): the seismic bracing table covers SDC C (townhouses only) and D0-D2; in SDC A and B the wind table R602.10.3(1) governs",
			seis_ok, 0.0 if seis_ok else 1.0, 0.0, ("SDC %s is outside R602.10.3(3), wind governs the bracing" % sdc) if seis_ok else "SDC %s needs R602.10.3(3), whose cells Kine has not read: UNVERIFIED, an engineer is needed" % sdc))
	# fastener schedule: every connection type in the member list gets its nails
	if h.has("connections"):
		for cn in h["connections"]:
			var key: String = cn["key"]
			var need: Dictionary = FASTENERS.get(key, {})
			var have: Dictionary = cn.get("fastener", {})
			var okc: bool = not need.is_empty() and not have.is_empty() and _pen_ok(have, need)
			var wh := "none specified"
			if not have.is_empty():
				wh = "%d-%dd %s" % [int(have.get("n", 0)), int(have.get("d", 0)), have.get("type", "box")]
				if float(have.get("spacing_in", 0)) > 0:
					wh += " at %d in" % int(have.get("spacing_in", 0))
			out.append(_line("nailing: %s (%d connections)" % [key.replace("_", " "), int(cn.get("count", 0))], "fastener", "connection %s" % key.replace("_", " "), "IRC 2021 Table R602.3(1): " + str(need.get("text", "no row")), okc,
				float(have.get("n", 0)), float(need.get("n", 0)), "drawing says %s against the table's %s" % [wh, need.get("text", "?")]))
	if h.has("sheathing_nailing"):
		for part in h["sheathing_nailing"]:
			var sn: Dictionary = h["sheathing_nailing"][part]
			var eok: bool = float(sn.get("edge_in", 99.0)) <= SHEATH_NAIL["edge_in"] and float(sn.get("field_in", 99.0)) <= SHEATH_NAIL["field_in"] and int(sn.get("d", 0)) >= SHEATH_NAIL["d"]
			out.append(_line("%s sheathing nailing" % part, "sheathing_nail", "7/16 OSB, %s nails" % sn.get("nail", "?"), "IRC 2021 Table R602.3(1) wood structural panel 3/8-1/2 in: 6d common or deformed, 6 in at edges, 12 in in the field (Table R602.3(3) wind cell for 7/16 not read)",
				eok, float(sn.get("edge_in", 99.0)), SHEATH_NAIL["edge_in"], "%dd at %s in edges / %s in field against 6d at 6 / 12" % [int(sn.get("d", 0)), g(float(sn.get("edge_in", 99.0))), g(float(sn.get("field_in", 99.0)))]))
	# birdsmouth
	var R: Dictionary = h["rafters"]
	if R.has("birdsmouth_in"):
		var bm: float = R["birdsmouth_in"]
		var dep: float = rdim[1]
		var seat: float = R.get("seat_in", 3.5)
		out.append(_line("rafter birdsmouth %s" % R["size"], "birdsmouth", "seat cut %s in deep in a %s in rafter, %s in seat on the plate" % [g(bm), g(dep), g(seat)],
			"IRC 2021 R802.7.1 -> R502.8.1: a notch at the end of a rafter is at most 1/4 of its depth; R802.6: at least 1.5 in of bearing", bm <= dep * NOTCH_END_FRAC + 1e-6 and seat >= RAFTER_BEARING_IN, bm, dep * NOTCH_END_FRAC,
			"seat cut %.2f in against 1/4 depth = %.2f in; bearing %s in against 1.5 in (the 1/3 figure quoted in blogs is not in the 2021 text)" % [bm, dep * NOTCH_END_FRAC, g(seat)]))
	# anchorage below the sill
	var S: Dictionary = h["sill"]
	if S.has("embed_in"):
		var emb: float = S["embed_in"]
		var bd: float = S.get("bolt_dia_in", 0.5)
		var bs: float = S.get("bolt_spacing_in", 72.0)
		var rsp: float = R["spacing_in"]
		var per_ft := (maxf(uplift_lb, 0.0) / rsp) * 12.0
		var dem := per_ft * bs / 12.0
		var capb := anchor_capacity(bd, emb)
		out.append(_line("anchorage below the sill", "anchorage", "uplift %.0f lb/ft along the wall (roof ties) x bolt spacing %d in = %.0f lb per %s in bolt embedded %s in; no dead-load credit" % [per_ft, int(bs), dem, g(bd), g(emb)],
			"IRC 2021 R403.1.6 anchor bolts embedded >= 7 in; load path R301.1 tie -> plate -> anchor bolt (capacity UNVERIFIED: ACI 318 breakout and A307 steel by hand, f'c 2500 assumed)",
			emb >= ANCHOR_EMBED_IN and dem <= capb, emb, ANCHOR_EMBED_IN, "UNVERIFIED capacity: embed %s in against 7 in; demand %.0f lb against %.0f lb ASD tension" % [g(emb), dem, capb]))


static func _jack_line(wall: String, k: int, op: Dictionary, W: float, sp_name: String, h: Dictionary) -> Dictionary:
	var span_ft: float = op["width_ft"]
	var v := float(h.get("wind_mph", 115))
	var expo: String = h.get("exposure", "B")
	var colB: bool = expo == "B" and v <= 115.0
	var colA: bool = (expo == "B" and v < 140.0) or (expo == "C" and v < 130.0)
	var jacks: int = op["jacks"]
	var need := -1
	if colB or colA:
		for i in JACK_SPAN.size():
			if span_ft <= JACK_SPAN[i] + 1e-6:
				need = JACK_B[i] if colB else JACK_A[i]
				break
	var ld := header_load(W)
	var reaction: float = ld[0] * span_ft * 12.0 / 2.0
	var area: float = 1.5 * WALL_T_IN * float(maxi(jacks, 0))
	var fcp: float = FC_PERP.get(sp_name, 425.0)
	var stress: float = reaction / area if area > 0.0 else 9e9
	var okj: bool = need > 0 and jacks >= need and stress <= fcp
	return _line("%s wall opening %d header bearing" % [wall, k], "header_bearing", "header reaction %.0f lb on %d jack stud(s) at each end, %s ft clear span" % [reaction, jacks, g(span_ft)],
		"IRC 2021 R602.7.5 and Table R602.7.5, jack studs at each header end; Fc-perp %.0f psi (NDS value from memory, UNVERIFIED)" % fcp, okj, float(jacks), float(need),
		"%d jack(s) against %s; bearing stress %.0f psi against %.0f psi" % [jacks, str(need) if need > 0 else "none (wind outside the table)", stress, fcp])



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


static func _header_line(wall: String, k: int, op: Dictionary, bearing: bool, W: float, sp_name: String, sp: Dictionary, cd: float, gsnow := 0.0) -> Dictionary:
	var hs: String = op["header"]
	var span: float = op["width_ft"] * 12.0
	var dm := _dims(hs)
	var tab := header_table(hs, W)
	var tok := tab > 0 and span <= tab and gsnow <= 30.0
	var ld := header_load(W)
	var ph := {"pass": false, "fb": 0.0, "Fb_allow": 0.0, "fv": 0.0, "Fv_allow": 0.0, "defl": 0.0, "defl_lim": 1.0}
	if not dm.is_empty():
		ph = beam(dm[0], dm[1], dm[2], span, ld[0], ld[1], 1.15, 1.0, 240.0, sp)
	var ag: bool = tok == ph["pass"]
	var loadwords := "30 psf ground snow: roof 31 psf over %s ft + ceiling 15 psf over %s ft = %.0f plf%s" % [g(W / 2.0 + 2.0), g(W / 2.0), ld[0] * 12.0, "" if bearing else " (non-bearing wall held to the bearing table)"]
	var ln := _line("%s wall opening %d header %s over %s ft" % [wall, k, hs, g(op["width_ft"])], "header", loadwords, "IRC 2021 R602.7(1) headers in exterior bearing walls, roof and ceiling, 30 psf ground snow", tok, span, tab,
		"span %s against table %s%s" % [fi(span), fi(tab) if tab > 0 else "none (not a tabulated built-up header, or width outside 12-36 ft)", "" if gsnow <= 30.0 else "; ground snow %s psf is over the table 30 psf" % g(gsnow)] + _physwords(ph, ag))
	ln["phys"] = ph
	ln["agree"] = ag
	return ln


static func _bracing_line(nm: String, wl: Dictionary, wall_h: float, h: Dictionary) -> Dictionary:
	var length: float = wl["length_ft"]
	var panels: Array = (wl.get("bracing", []) as Array).duplicate(true)
	panels.sort_custom(func(a, b): return float(a["pos_ft"]) < float(b["pos_ft"]))
	var spacing: float = wl.get("line_spacing_ft", 28.0)
	var wv := int(h.get("wind_mph", 115))
	var wind := 110 if wv <= 110 else (115 if wv <= 115 else (120 if wv <= 120 else (130 if wv <= 130 else 140)))
	var beyond: bool = wv >= 140
	var efac: float = EXPOSURE_BRACE.get(h.get("exposure", "B"), 1.5)
	var need := _interp(BRACE_SPACING, BRACE_WSP[wind], spacing) * efac
	var min_len := 4.0 if wall_h <= 9.0 else 53.0 / 12.0
	var total := 0.0
	var problems: Array = []
	var prev_end := 0.0
	var first := true
	for p in panels:
		var pl: float = p["len_ft"]
		if pl + 1e-6 < min_len:
			problems.append("panel %s ft is under the %.2f ft minimum" % [g(pl), min_len])
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
	if beyond:
		problems.append("%d mph is past the last column of the table (< 140 mph): stamped design" % wv)
	if total + 1e-6 < need:
		problems.append("%.1f ft of panel is under the %.1f ft needed" % [total, need])
	return _line("%s wall bracing line" % nm, "bracing", "%d mph, exposure %s, %s ft line, %s ft to the next braced wall line, seismic %s (R602.10.3(3) does not apply in SDC A-B)" % [int(h.get("wind_mph", 115)), h.get("exposure", "B"), g(length), g(spacing), h.get("seismic", "A-B")],
		"IRC 2021 Table R602.10.3(1) method WSP x exposure factor R602.10.3(2) %s; panel rules R602.10.2.2 (within 10 ft of each end, 20 ft between panels)" % g(efac), problems.is_empty(), total, need,
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
const NOT_CHECKED := ["floor framing and second storeys", "shear transfer and hold-downs below the sill (only the anchor bolt uplift is checked, by hand calc)", "trusses and engineered lumber", "snow loads other than 20 psf", "notching and drilling", "seismic design categories above B", "a stamped design"]
