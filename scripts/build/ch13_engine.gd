extends RefCounted
## CH13: the maths of a single-cylinder engine (Honda C50 class): ISO 286 limits and fits, thermal clearance, tolerance stack-up, slider-crank torque from a pressure curve, FDM print compensation.
## Sources and every assumption: docs/CH13_REFERENCE.md. Units: micrometres for deviations, mm for sizes, SI (m, Pa, N, kg, s) in the cycle. GDScript on purpose: ~3000 samples of closed-form trig.

# ------------------------------------------------------------------------------------------------ ISO 286
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
const ALPHA := {"4032": 19.4, "iron": 10.5, "steel": 11.7}
const T_REF := 20.0
const T_SKIRT := 120.0
const T_BORE := 100.0
const T_BOSS := 150.0
const T_PIN := 130.0
const HOT_MIN_UM := 5.0
const HHE := 0.13    # Grgic 2023, hole horizontal expansion per side (mm)


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


# ------------------------------------------------------------------------------------------------ thermal
## clearance at temperature: each part grows alpha (T - 20) d. alphas in e-6 /K, d in mm, results in um
static func hot_clearance(d: float, cmin: float, cmax: float, a_hole: float, t_hole: float, a_shaft: float, t_shaft: float) -> Dictionary:
	var gh := a_hole * 1e-6 * (t_hole - T_REF) * d * 1000.0
	var gs := a_shaft * 1e-6 * (t_shaft - T_REF) * d * 1000.0
	var delta := gh - gs
	return {"grow_hole": gh, "grow_shaft": gs, "delta": delta, "cmin_hot": cmin + delta, "cmax_hot": cmax + delta, "seizes": cmin + delta < 0.0}


## the tightest candidate ("H7/e7", tightest first) whose hot minimum clearance stays >= HOT_MIN_UM; aluminium piston in an iron bore
static func select_piston_fit(d: float, cands: Array) -> Dictionary:
	for c in cands:
		var parts: PackedStringArray = String(c).split("/")
		var f := fit(d, parts[0], parts[1])
		var h := hot_clearance(d, f["cmin"], f["cmax"], ALPHA["iron"], T_BORE, ALPHA["4032"], T_SKIRT)
		if float(h["cmin_hot"]) >= HOT_MIN_UM:
			return {"fit": String(c), "cold": f, "hot": h}
	return {"fit": "", "cold": {}, "hot": {}}


# ------------------------------------------------------------------------------------------------ stack-up
static func _link(nm: String, nom: float, grade: int, sign: int) -> Dictionary:
	return {"name": nm, "nom": nom, "tol": it(grade, nom) / 2.0, "sign": sign, "grade": grade}


## crank end-float = case span - (left collar+web) - (web pair + pin) - (right collar+web); tolerances +-IT/2
static func endfloat_chain() -> Array:
	return [_link("case span", 58.30, 10, 1), _link("left collar + web", 17.0, 8, -1), _link("web pair + crank pin", 24.0, 8, -1), _link("right collar + web", 17.0, 8, -1)]


## deck clearance at TDC = crank axis to deck - stroke radius - rod length - crown to pin axis
static func deck_chain() -> Array:
	return [_link("crank axis to deck", 111.2, 10, 1), _link("crank radius", 20.7, 8, -1), _link("rod centres", 80.0, 7, -1), _link("crown to pin axis", 10.0, 9, -1)]


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


# ------------------------------------------------------------------------------------------------ slider-crank
static func piston_x(th: float, r: float, L: float) -> float:
	return r * cos(th) + sqrt(L * L - r * r * sin(th) * sin(th))


## crank torque per unit piston force toward the crank, -dx/dtheta (same unit as r)
static func torque_per_force(th: float, r: float, L: float) -> float:
	return r * sin(th) * (1.0 + r * cos(th) / sqrt(L * L - r * r * sin(th) * sin(th)))


static func params(rpm: float, tau: float, m_rec: float) -> Dictionary:
	var A := PI / 4.0 * 0.039 * 0.039
	var r := 0.0207
	var Vd := A * 2.0 * r
	return {"rpm": rpm, "tau": tau, "m_rec": m_rec, "r": r, "L": 0.080, "bore": 0.039, "A": A, "Vd": Vd, "rc": 10.0, "Vc": Vd / 9.0, "n": 1.30,
		"p1": 0.85e5, "p_exh": 1.05e5, "p_cc": 1.01325e5, "burn_start": 340.0, "burn_dur": 50.0, "wiebe_a": 5.0, "wiebe_m": 2.0}


static func volume(th: float, pr: Dictionary) -> float:
	return float(pr["Vc"]) + float(pr["A"]) * (float(pr["r"]) + float(pr["L"]) - piston_x(th, pr["r"], pr["L"]))


static func burn_fraction(th_deg: float, pr: Dictionary) -> float:
	var x := (th_deg - float(pr["burn_start"])) / float(pr["burn_dur"])
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	var a: float = pr["wiebe_a"]
	return (1.0 - exp(-a * pow(x, float(pr["wiebe_m"]) + 1.0))) / (1.0 - exp(-a))


## cylinder pressure (Pa) at cycle angle th_deg (0..720; 0 = TDC at the start of intake, 360 = firing TDC). THE INPUT: polytropic compression / expansion with a Wiebe heat-release scaling.
static func pressure(th_deg: float, pr: Dictionary) -> float:
	var th := fposmod(th_deg, 720.0)
	if th < 180.0:
		return pr["p1"]
	if th >= 540.0:
		return pr["p_exh"]
	var V1: float = float(pr["Vc"]) + float(pr["Vd"])
	var pm: float = float(pr["p1"]) * pow(V1 / volume(deg_to_rad(th), pr), pr["n"])
	return pm * (1.0 + (float(pr["tau"]) - 1.0) * burn_fraction(th, pr))


## the ideal Otto cycle pressure (heat added instantly at firing TDC) for the closed-form check
static func otto_pressure(th_deg: float, pr: Dictionary) -> float:
	var th := fposmod(th_deg, 720.0)
	var V1: float = float(pr["Vc"]) + float(pr["Vd"])
	var pm: float = float(pr["p1"]) * pow(V1 / volume(deg_to_rad(th), pr), pr["n"])
	return pm * (float(pr["tau"]) if th >= 360.0 else 1.0)


## work (J) of the Otto cycle from the slider-crank torque, BDC to BDC (180..540 deg), midpoint rule at 0.05 deg
static func otto_work_numeric(pr: Dictionary) -> float:
	var dth := 0.05
	var n := int(360.0 / dth)
	var w := 0.0
	for i in n:
		var d := 180.0 + (i + 0.5) * dth
		var t := deg_to_rad(d)
		w += (otto_pressure(d, pr) - float(pr["p_cc"])) * float(pr["A"]) * torque_per_force(t, pr["r"], pr["L"]) * deg_to_rad(dth)
	return w


## inertia force of the reciprocating mass on the piston, positive toward the crank: -m r w^2 (cos th + lambda cos 2 th)
static func inertia_force(th_rad: float, pr: Dictionary) -> float:
	var w: float = float(pr["rpm"]) * TAU / 60.0
	var lam: float = float(pr["r"]) / float(pr["L"])
	return -float(pr["m_rec"]) * float(pr["r"]) * w * w * (cos(th_rad) + lam * cos(2.0 * th_rad))


## one 720 deg cycle at pr["rpm"]: torque samples and the means. Friction: Chen-Flynn FMEP.
static func run_cycle(pr: Dictionary, dth := 0.5) -> Dictionary:
	var n := int(720.0 / dth)
	var A: float = pr["A"]
	var sg := 0.0
	var si := 0.0
	var ip := 0.0
	var pmax := 0.0
	var thp := 0.0
	var peak_i := 0.0
	var T_series := PackedFloat64Array()
	var V0 := volume(0.0, pr)
	var Vprev := V0
	for i in n:
		var d := (i + 0.5) * dth
		var t := deg_to_rad(d)
		var p := pressure(d, pr)
		var tpf := torque_per_force(t, pr["r"], pr["L"])
		var tg := (p - float(pr["p_cc"])) * A * tpf
		var ti := inertia_force(t, pr) * tpf
		sg += tg
		si += ti
		peak_i = maxf(peak_i, absf(ti))
		var Vn := volume(deg_to_rad((i + 1) * dth), pr)
		ip += p * (Vn - Vprev)
		Vprev = Vn
		if p > pmax:
			pmax = p
			thp = d
		T_series.append(tg + ti)
	var mean_g := sg / n
	var mean_i := si / n
	var Vd: float = pr["Vd"]
	var w: float = float(pr["rpm"]) * TAU / 60.0
	var imep_T := mean_g * 4.0 * PI / Vd
	var cm: float = 2.0 * 0.0414 * float(pr["rpm"]) / 60.0
	var fmep_bar := 0.4 + 0.005 * pmax / 1e5 + 0.09 * cm + 0.0009 * cm * cm
	var fmep := fmep_bar * 1e5
	var bmep := imep_T - fmep
	var tb := bmep * Vd / (4.0 * PI)
	return {"mean_T_gas": mean_g, "mean_T_inertia": mean_i, "peak_T_inertia": peak_i, "imep_T": imep_T, "imep_pdv": ip / Vd, "imep_net": imep_T, "pmax": pmax, "th_pmax": thp,
		"fmep": fmep, "bmep": bmep, "T_brake": tb, "P_brake": tb * w, "cm": cm, "T": T_series, "w": w}


# ------------------------------------------------------------------------------------------------ FDM compensation (Grgic et al. 2023)
## a prototype pair: drawn at the mid-zone of the limits. Zones finer than IT9 were not demonstrated: the prototype uses IT9 with the same letters.
static func print_plan(d: float, hole_letter: String, shaft_letter: String, hole_grade: int, shaft_grade: int) -> Dictionary:
	var demonstrated := hole_grade >= 9 and shaft_grade >= 9
	var g := maxi(9, maxi(hole_grade, shaft_grade))
	var hz := hole(hole_letter, g, d)
	var sz := shaft(shaft_letter, g, d)
	var hc := mid_hole(d, hz)
	return {"grade": g, "demonstrated": demonstrated, "hole_zone": hz, "shaft_zone": sz, "hole_cad": hc, "shaft_cad": mid_shaft(d, sz), "hole_slicer0": hc + 2.0 * HHE, "hhe": HHE,
		"hole_limits": hole_limits(d, hz), "shaft_limits": shaft_limits(d, sz)}


## printer model from the study: with Hole Horizontal Expansion 0 a hole prints 2 x 0.13 mm (diameter) small; HHE per side puts it back
static func printed_hole(cad: float, hhe: float) -> float:
	return cad - 2.0 * HHE + 2.0 * hhe
