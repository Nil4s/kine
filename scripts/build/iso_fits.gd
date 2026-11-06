extends RefCounted
class_name IsoFits
## G3: ISO 286 limits and fits + tolerance stack-up as a reusable library (moved out of ch13_engine.gd, numbers unchanged; CH13 calls this).
## Units: micrometres for deviations, mm for sizes. Size range 6..180 mm, grades IT5..IT10. Shafts: d e f g h js k m p (lower case); holes: D E F G H JS (upper case).

const RANGES := [[6, 10], [10, 18], [18, 30], [30, 50], [50, 80], [80, 120], [120, 180]]
## ISO 286-1 standard tolerance grades (um) per size range above (over lo, up to and including hi)
const IT := {
	5: [6, 8, 9, 11, 13, 15, 18],
	6: [9, 11, 13, 16, 19, 22, 25],
	7: [15, 18, 21, 25, 30, 35, 40],
	8: [22, 27, 33, 39, 46, 54, 63],
	9: [36, 43, 52, 62, 74, 87, 100],
	10: [58, 70, 84, 100, 120, 140, 160],
}
const IT_K := {5: 7.0, 6: 10.0, 7: 16.0, 8: 25.0, 9: 40.0, 10: 64.0}
## ISO 286-2 fundamental deviations (um): es for d e f g (negative), ei for k p (positive); m = IT7 - IT6; h = 0
const FUND := {
	"d": [-40, -50, -65, -80, -100, -120, -145],
	"e": [-25, -32, -40, -50, -60, -72, -85],
	"f": [-13, -16, -20, -25, -30, -36, -43],
	"g": [-5, -6, -7, -9, -10, -12, -14],
	"k": [1, 1, 2, 2, 2, 3, 3],
	"p": [15, 18, 22, 26, 32, 37, 43],
}
## coefficients of thermal expansion (e-6 /K), docs/CH13_REFERENCE.md section 3

static func range_of(d: float) -> int:
	for i in RANGES.size():
		if d > float(RANGES[i][0]) and d <= float(RANGES[i][1]):
			return i
	push_error("ch13: size %f outside 6..180 mm" % d)
	return -1


static func gm(d: float) -> float:
	var r: Array = RANGES[range_of(d)]
	return sqrt(float(r[0]) * float(r[1]))


static func it(grade: int, d: float) -> float:
	return float((IT[grade] as Array)[range_of(d)])


static func it_table() -> Dictionary:
	return IT


## the ISO formula: IT = k x i, i = 0.45 D^(1/3) + 0.001 D (um), D the geometric mean of the range
static func it_formula(grade: int, d: float) -> float:
	var D := gm(d)
	return float(IT_K[grade]) * (0.45 * pow(D, 1.0 / 3.0) + 0.001 * D)


## the largest |table - formula| over a table of the same shape as IT (um)
static func it_table_maxdiff(tbl: Dictionary) -> float:
	var worst := 0.0
	for g in tbl.keys():
		for ri in RANGES.size():
			var D := sqrt(float(RANGES[ri][0]) * float(RANGES[ri][1]))
			worst = maxf(worst, absf(float((tbl[g] as Array)[ri]) - it_formula(int(g), D)))
	return worst


## fundamental deviation of a shaft letter (um): es for d e f g h, ei for k m p
static func fund(letter: String, d: float) -> float:
	if letter == "h":
		return 0.0
	if letter == "m":
		return it(7, d) - it(6, d)
	return float((FUND[letter] as Array)[range_of(d)])


static func fund_formula(letter: String, d: float) -> float:
	var D := gm(d)
	match letter:
		"g":
			return -2.5 * pow(D, 0.34)
		"f":
			return -5.5 * pow(D, 0.41)
		"e":
			return -11.0 * pow(D, 0.41)
		"d":
			return -16.0 * pow(D, 0.44)
		"k":
			return 0.6 * pow(D, 1.0 / 3.0)
	return NAN


## shaft zone: {"es", "ei"} (um)
static func shaft(letter: String, grade: int, d: float) -> Dictionary:
	var t := it(grade, d)
	if letter == "js":
		var h := t / 2.0
		if grade >= 7 and grade <= 11 and int(t) % 2 == 1:
			h = (t - 1.0) / 2.0
		return {"es": h, "ei": -h}
	var f := fund(letter, d)
	if letter in ["k", "m", "p"]:
		return {"es": f + t, "ei": f}
	return {"es": f, "ei": f - t}


## hole zone: {"ES", "EI"} (um); H, F, G, E, D mirror the shaft letters, JS is symmetric
static func hole(letter: String, grade: int, d: float) -> Dictionary:
	var t := it(grade, d)
	if letter == "H":
		return {"ES": t, "EI": 0.0}
	if letter == "JS":
		var s := shaft("js", grade, d)
		return {"ES": s["es"], "EI": s["ei"]}
	var ei := -fund(letter.to_lower(), d)
	return {"ES": ei + t, "EI": ei}


static func classify(cmin: float, cmax: float) -> String:
	if cmin >= 0.0:
		return "clearance"
	if cmax <= 0.0:
		return "interference"
	return "transition"


static func _split(code: String) -> Array:
	var i := 0
	while i < code.length() and not code[i].is_valid_int():
		i += 1
	return [code.substr(0, i), int(code.substr(i))]


## a fit by names ("H7", "f7") at nominal size d (mm): the zones and the min / max clearance (um; negative = interference)
static func fit(d: float, hole_code: String, shaft_code: String) -> Dictionary:
	var h: Array = _split(hole_code)
	var s: Array = _split(shaft_code)
	var hz := hole(String(h[0]), int(h[1]), d)
	var sz := shaft(String(s[0]), int(s[1]), d)
	var cmin: float = float(hz["EI"]) - float(sz["es"])
	var cmax: float = float(hz["ES"]) - float(sz["ei"])
	return {"d": d, "hole": hz, "shaft": sz, "cmin": cmin, "cmax": cmax, "kind": classify(cmin, cmax), "name": "%s/%s" % [hole_code, shaft_code]}


## the limit diameters (mm) of a zone
static func hole_limits(d: float, hz: Dictionary) -> Array:
	return [d + float(hz["EI"]) / 1000.0, d + float(hz["ES"]) / 1000.0]


static func shaft_limits(d: float, sz: Dictionary) -> Array:
	return [d + float(sz["ei"]) / 1000.0, d + float(sz["es"]) / 1000.0]


static func mid_hole(d: float, hz: Dictionary) -> float:
	return d + (float(hz["ES"]) + float(hz["EI"])) / 2000.0


static func mid_shaft(d: float, sz: Dictionary) -> float:
	return d + (float(sz["es"]) + float(sz["ei"])) / 2000.0



static func link(nm: String, nom: float, grade: int, sign: int) -> Dictionary:
	return {"name": nm, "nom": nom, "tol": it(grade, nom) / 2.0, "sign": sign, "grade": grade}



static func stack(chain: Array) -> Dictionary:
	var nom := 0.0
	var w := 0.0
	var q := 0.0
	for l in chain:
		nom += float(l["sign"]) * float(l["nom"])
		w += float(l["tol"])
		q += float(l["tol"]) * float(l["tol"])
	var r := sqrt(q)
	return {"nominal": nom, "tol_worst": w, "tol_rss": r, "min_worst": nom - w / 1000.0, "max_worst": nom + w / 1000.0, "min_rss": nom - r / 1000.0, "max_rss": nom + r / 1000.0}


## every corner (each link at +tol or -tol): the exact worst case
static func stack_corners(chain: Array) -> Dictionary:
	var n := chain.size()
	var nom := 0.0
	for l in chain:
		nom += float(l["sign"]) * float(l["nom"])
	var lo := 1e18
	var hi := -1e18
	for m in (1 << n):
		var g := nom
		for i in n:
			var s := 1.0 if (m >> i) & 1 else -1.0
			g += float(chain[i]["sign"]) * s * float(chain[i]["tol"]) / 1000.0
		lo = minf(lo, g)
		hi = maxf(hi, g)
	return {"min": lo, "max": hi, "n": 1 << n}




# ------------------------------------------------------------------------------------------------ fit classes on a dimension
const HOLE_LETTERS := ["D", "E", "F", "G", "H", "JS"]
const SHAFT_LETTERS := ["d", "e", "f", "g", "h", "js", "k", "m", "p"]


## "H7" -> {"ok", "role": "hole"|"shaft", "letter", "grade"}; ok false (with "why") for anything the tables do not cover
static func parse_code(code: String) -> Dictionary:
	var c := code.strip_edges()
	var sp := _split(c)
	var letter := String(sp[0])
	var grade := int(sp[1])
	var role := "hole" if letter.to_upper() == letter else "shaft"
	var okl: bool = (letter in HOLE_LETTERS) if role == "hole" else (letter in SHAFT_LETTERS)
	if letter == "" or not okl or not IT.has(grade) or c != "%s%d" % [letter, grade]:
		return {"ok": false, "why": "'%s' is not a fit class (hole D E F G H JS, shaft d e f g h js k m p, grade 5..10, e.g. H7 or g6)" % c}
	return {"ok": true, "role": role, "letter": letter, "grade": grade}


## a class on a diameter d (mm): the zone and the limit diameters. {"ok", "role", "es", "ei" (um, upper / lower), "lo", "hi" (mm), "text"}
static func limits_of(d: float, code: String) -> Dictionary:
	var p := parse_code(code)
	if not bool(p["ok"]):
		return p
	if d <= 6.0 or d > 180.0:
		return {"ok": false, "why": "ISO 286 tables here cover 6 to 180 mm; this is %s mm" % String.num(d, 3)}
	var up := 0.0
	var lo_ := 0.0
	if String(p["role"]) == "hole":
		var z := hole(String(p["letter"]), int(p["grade"]), d)
		up = float(z["ES"])
		lo_ = float(z["EI"])
	else:
		var z := shaft(String(p["letter"]), int(p["grade"]), d)
		up = float(z["es"])
		lo_ = float(z["ei"])
	return {"ok": true, "role": p["role"], "code": code.strip_edges(), "d": d, "es": up, "ei": lo_, "lo": d + lo_ / 1000.0, "hi": d + up / 1000.0, "text": limits_text(d, code.strip_edges(), up, lo_)}


static func _signed_um(v: float) -> String:
	return ("+" if v > 0.0 else "") + String.num(v, 0)


## a size without trailing zeros: 20 not 20.0
static func fmt(v: float) -> String:
	var t := "%.4f" % v
	return t.rstrip("0").rstrip(".")


static func limits_text(d: float, code: String, es: float, ei: float) -> String:
	return "%s %s %s/%s um  (%.3f to %.3f)" % [fmt(d), code, _signed_um(es), _signed_um(ei), d + ei / 1000.0, d + es / 1000.0]


## the limits of a pair as data: hole class and shaft class at the same nominal d. Same numbers as fit().
static func mate(d: float, hole_code: String, shaft_code: String) -> Dictionary:
	var hp := parse_code(hole_code)
	var sp := parse_code(shaft_code)
	if not bool(hp["ok"]) or String(hp["role"]) != "hole":
		return {"ok": false, "why": "'%s' is not a hole class (upper case, e.g. H7)" % hole_code}
	if not bool(sp["ok"]) or String(sp["role"]) != "shaft":
		return {"ok": false, "why": "'%s' is not a shaft class (lower case, e.g. g6)" % shaft_code}
	var f := fit(d, hole_code, shaft_code)
	f["ok"] = true
	return f


## a stack-up from signed links {"name","nom","tol" (um, +-),"sign"}: nominal, worst case, RSS, and the corner-enumerated worst case
static func stack_report(chain: Array) -> Dictionary:
	var s := stack(chain)
	var c := stack_corners(chain)
	s["corner_min"] = c["min"]
	s["corner_max"] = c["max"]
	s["n"] = chain.size()
	return s


## CSV of a chain and its totals (header row, one row per link, then NOMINAL / WORST / RSS rows)
static func stack_csv(chain: Array) -> String:
	var s := stack(chain)
	var out := "name,sign,nominal_mm,tol_um,grade\n"
	for l in chain:
		out += "%s,%d,%s,%s,%s\n" % [String(l["name"]).replace(",", ";"), int(l["sign"]), String.num(float(l["nom"]), 6), String.num(float(l["tol"]), 6), str(l.get("grade", ""))]
	out += "NOMINAL,,%s,,\n" % String.num(float(s["nominal"]), 6)
	out += "WORST,,%s,%s,min %s max %s\n" % [String.num(float(s["nominal"]), 6), String.num(float(s["tol_worst"]), 6), String.num(float(s["min_worst"]), 6), String.num(float(s["max_worst"]), 6)]
	out += "RSS,,%s,%s,min %s max %s\n" % [String.num(float(s["nominal"]), 6), String.num(float(s["tol_rss"]), 6), String.num(float(s["min_rss"]), 6), String.num(float(s["max_rss"]), 6)]
	return out
