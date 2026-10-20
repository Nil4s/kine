## body_model.gd - THE BODY PAGE'S NUMBERS (docs/PAGES_PLAN.md step 2): a person made from real measurements.
## Sliders are PERCENTILES of the ANSUR II survey (Gordon et al. 2014, NATICK/TR-15/007; 4082 men, 1986 women; the
## numbers: docs/research/PROPORTIONS.md). They map to the scene's "body" dict (Proportions): a stature, a mass and
## per-segment scales. data/skeleton.json is never written; this is the per-scene character, saved with the scene.
##
##   stature  normal. men mean 1756.2 mm SD 68.6 (report p.192: 175.62 / 6.86 cm); women 1628.5 mm SD 64.2 (162.85 / 6.42).
##            Check against the report's own percentiles: men P5 = 1756.2 - 1.645 x 68.6 = 1643 (table 1648),
##            P95 = 1869 (1870); women P5 = 1523 (1525), P95 = 1734 (1740): all inside 0.4 %.
##   mass     log-normal (the survey's mass is right-skewed): median 84.6 kg men / 66.8 women (pp.224-225), log-sigma
##            ln(P95 / P5) / 3.29 = 0.1647 men (64.4 / 110.7), 0.1610 women (51.3 / 87.1). The geometric centre of P5 and
##            P95 (84.4 / 66.8) matches the medians, which is what a log-normal predicts.
##   blend    0 = women, 1 = men: mean, SD, median and log-sigma are mixed linearly (a person between the two samples).
##   arm, leg, trunk, head   a PROPORTION percentile: the segment's length RELATIVE to stature, median = Drillis & Contini
##            1966 (Winter 2009 Fig. 4.1, the same table the presets use). The spread is the coefficient of variation of
##            the RATIO, CV_r^2 = CV_L^2 + CV_H^2 - 2 rho CV_L CV_H, from the survey's P5/P95 (SD ~ (P95 - P5) / 3.29):
##            arm (upper arm + forearm + hand together) CV_L 5.3 %, leg (trochanter height) 5.4 %, stature 3.9 %, and
##            rho = 0.7 ESTIMATED (the raw files would give the exact ratio SDs: stated); trunk and head (ratios of
##            sitting height and head circumference to stature) are estimates at 3.0 %.
## ARM SPAN CALIBRATION: with Drillis' arm fractions (0.186 + 0.146 + 0.108 = 0.440 H each side) and this skeleton's
## shoulder joints (0.206 H apart) the T-pose fingertip-to-fingertip span is 1.086 H, over the 1.00-1.06 band ANSUR II
## gives for span / stature. The page's MEDIAN arm is therefore Drillis x ARM_K, with ARM_K = (1.03 H - 0.2059 H) /
## (1.0858 H - 0.2059 H) = 0.9366, which puts the 50th-percentile span at 1.030 H (the middle of the band). The six
## presets keep Drillis' lengths exactly (Proportions.preset is untouched); only the BODY page's median arm is shorter.
## What is NOT here: shoulder and hip breadth as their own sliders (a segment's scale is uniform: the clavicles ride the
## trunk, the hip width the pelvis; independent breadths need the mesh of step 3) and girth from mass (same reason: mass
## sets the centre of mass and the readouts now, not the skin).
class_name BodyModel
extends RefCounted

const ANSUR := {
	"male": {"n": 4082, "stat": [1756.2, 68.6], "mass": [84.6, 0.1647]},
	"female": {"n": 1986, "stat": [1628.5, 64.2], "mass": [66.8, 0.1610]},
}
const CV := {"arm": 0.038, "leg": 0.039, "trunk": 0.030, "head": 0.030}   # of the ratio to stature (see above)
const GROUPS := {"arm": ["upper_arm", "forearm", "hand"], "leg": ["thigh", "shank"], "trunk": ["trunk"], "head": ["head"]}
const KEYS := ["stat", "mass", "arm", "leg", "trunk", "head"]
const ARM_K := 0.9366
const DEFAULT := {"blend": 1.0, "stat": 50.0, "mass": 50.0, "arm": 50.0, "leg": 50.0, "trunk": 50.0, "head": 50.0}

static var _trunk_k := -1.0   # the trunk's extra scale per metre of stature the preset solve adds (cached)


## standard normal CDF (Abramowitz & Stegun 7.1.26, |error| < 1.5e-7)
static func cdf(z: float) -> float:
	var x := absf(z) / sqrt(2.0)
	var t := 1.0 / (1.0 + 0.3275911 * x)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)
	return 0.5 * (1.0 + y) if z >= 0.0 else 0.5 * (1.0 - y)


## z of a percentile (0..100) by bisection
static func zof(p: float) -> float:
	var q := clampf(p, 0.01, 99.99) / 100.0
	var lo := -6.0
	var hi := 6.0
	for i in 60:
		var m := (lo + hi) * 0.5
		if cdf(m) < q:
			lo = m
		else:
			hi = m
	return (lo + hi) * 0.5


static func pct(z: float) -> float:
	return cdf(z) * 100.0


static func sex_of(blend: float) -> String:
	return "male" if blend >= 0.5 else "female"


static func _mix(blend: float, key: String, i: int) -> float:
	return lerpf(float(ANSUR["female"][key][i]), float(ANSUR["male"][key][i]), clampf(blend, 0.0, 1.0))


## "50th", "1st", "22nd", "93rd"
static func ordinal(p: float) -> String:
	var n := clampi(roundi(p), 1, 99)
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suf = "st"
			2: suf = "nd"
			3: suf = "rd"
	return "%d%s" % [n, suf]


## the stature (m) and mass (kg) at these percentiles for this blend
static func stature_at(blend: float, p: float) -> float:
	return (_mix(blend, "stat", 0) + zof(p) * _mix(blend, "stat", 1)) / 1000.0


static func mass_at(blend: float, p: float) -> float:
	return _mix(blend, "mass", 0) * exp(zof(p) * _mix(blend, "mass", 1))


## the percentile of a stature / mass for this blend
static func stature_pct(blend: float, st: float) -> float:
	return pct((st * 1000.0 - _mix(blend, "stat", 0)) / _mix(blend, "stat", 1))


static func mass_pct(blend: float, kg: float) -> float:
	return pct(log(maxf(kg, 1.0) / _mix(blend, "mass", 0)) / _mix(blend, "mass", 1))


## the median-proportion scales of a person this tall (Drillis' fractions; the preset solve, any stature)
static func base_scales(st: float) -> Dictionary:
	if _trunk_k < 0.0:
		var p := Proportions.preset("male_50")
		var L := Proportions.default_lengths()
		var st0 := float(p["stature"])
		_trunk_k = (float(p["scale"]["trunk"]) - float(Proportions.DRILLIS["trunk"]) * st0 / float(L["trunk"])) / st0
	var L2 := Proportions.default_lengths()
	var sc := {}
	for s in Proportions.SEGS:
		sc[s] = float(Proportions.DRILLIS[s]) * st / float(L2[s])
	sc["trunk"] = float(sc["trunk"]) + _trunk_k * st
	for s in GROUPS["arm"]:
		sc[s] = float(sc[s]) * ARM_K
	return sc


## sliders -> the scene's body dict (Proportions.clean'd). pr = {blend, stat, mass, arm, leg, trunk, head}
static func body_for(pr: Dictionary) -> Dictionary:
	var bl := float(pr.get("blend", 1.0))
	var st := stature_at(bl, float(pr.get("stat", 50.0)))
	var sc := base_scales(st)
	for g in GROUPS:
		var m := exp(zof(float(pr.get(g, 50.0))) * float(CV[g]))
		for s in GROUPS[g]:
			sc[s] = float(sc[s]) * m
	return Proportions.clean({"stature": st, "scale": sc, "sex": sex_of(bl), "blend": bl, "mass": mass_at(bl, float(pr.get("mass", 50.0)))})


## a body dict -> the sliders that would make it (the default mannequin shows how its own proportions rate)
static func params_for(body: Dictionary, blend_hint := 1.0) -> Dictionary:
	var sex := String(body.get("sex", "male"))
	var bl := blend_hint if sex_of(blend_hint) == sex else (1.0 if sex == "male" else 0.0)
	if body.has("blend"):   # R12: the scene remembers the blend it was made with
		bl = float(body["blend"])
	var st := float(body.get("stature", Proportions.DEFAULT_STATURE))
	var sc: Dictionary = body.get("scale", {})
	var base := base_scales(st)
	var out := {"blend": bl, "stat": stature_pct(bl, st),
		"mass": mass_pct(bl, float(body.get("mass", mass_at(bl, 50.0))))}
	for g in GROUPS:
		var lm := 0.0
		for s in GROUPS[g]:
			lm += log(float(sc.get(s, 1.0)) / float(base[s]))
		out[g] = pct(lm / float(GROUPS[g].size()) / float(CV[g]))
	if body.is_empty():   # the mannequin as shipped: its stature and mass are read, its odd proportions are not (the median person)
		for g in GROUPS:
			out[g] = 50.0
	for k in KEYS:
		out[k] = clampf(float(out[k]), 1.0, 99.0)
	return out


## what the body measures now (rest pose, T): stature, arm span (middle fingertip to fingertip), the shoulder joints'
## and the hip joints' distance, all m. The body is put back as it was.
static func measures(B: Body) -> Dictionary:
	var keep := B.state()
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	var tips := []
	for sd in ["_l", "_r"]:
		var j: String = "middle_03" + sd
		tips.append((B.P[j] as Vector3) + (B.G[j] as Quaternion) * ((B.e0[j] as Vector3) - (B.p0[j] as Vector3)))
	var out := {"stature": Proportions.head_top(B).y - Proportions.heel(B, "_l").y,
		"span": ((tips[0] as Vector3) - (tips[1] as Vector3)).length(),
		"shoulders": ((B.P["upperarm_l"] as Vector3) - (B.P["upperarm_r"] as Vector3)).length(),
		"hips": ((B.P["thigh_l"] as Vector3) - (B.P["thigh_r"] as Vector3)).length()}
	B.set_state(keep)
	return out
