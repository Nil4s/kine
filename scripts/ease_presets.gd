## ease_presets.gd - EASE PRESETS FROM REAL MOTION (ROADMAP item 17). Formulas and sources: docs/research/EASE_PRESETS.md.
##
## A card's "ease" (scene.gd EASES, ALL_EASES) shapes the move INTO it. These four presets are progress curves e(x) on
## x in [0, 1] (x = the joint's own progress, with scene.gd's NATURAL overlap), with e(0) = 0 and e(1) = 1:
##   "reach":  minimum-jerk (Flash & Hogan 1985): e = 10x^3 - 15x^4 + 6x^5. Speed bell-shaped, peak at x = 0.5,
##             peak / mean = 1.875. (This is also the curve the default "smooth" uses under NATURAL: same numbers.)
##   "strike": the speed profile v(x) ~ x^a (1-x)^b with a = K p, b = K (1 - p), K = 4, p = STRIKE_PEAK: the speed
##             peaks at fraction p of the move (late peak = a punch that is still accelerating late). K = 4 with p = 0.5
##             is exactly minimum-jerk's speed, so REACH is the p = 0.5 member of this family.
##   "throw":  the same family, peak fraction p(level) = THROW_P0 + THROW_STEP * level: a proximal joint peaks before a
##             distal one (pelvis -> trunk -> arm -> hand), on top of the NATURAL overlap, which already delays each level.
##   "settle": a damped spring's step response (zeta = SETTLE_ZETA, wn = SETTLE_WN), renormalised so e(0) = 0 and
##             e(1) = 1 exactly: it overshoots a few per cent and rings back onto the card.
## Pure functions: no state a scene saves. A scene without a preset never calls this file (scene.gd _ease).
class_name EasePresets
extends RefCounted

const KINDS := ["reach", "strike", "throw", "settle"]
const STRIKE_PEAK := 0.60     # fraction of the move at which a strike's speed peaks (ours; see docs/research/EASE_PRESETS.md)
const THROW_P0 := 0.30        # the pelvis (level 0) peaks at this fraction of its own progress
const THROW_STEP := 0.08      # each joint level peaks this much later (level 6 = fingers at 0.78)
const SETTLE_ZETA := 0.7      # damping ratio (ours; no measured landing / sway value found, see the doc)
const SETTLE_WN := 8.0        # natural frequency in move-lengths: rad per move

## the speed-profile exponent K of the skewed family
const K := 4.0
const TABLE_N := 1000
static var _mu := Mutex.new()
static var _tables := {}      # peak fraction (rounded to 1e-6) -> PackedFloat64Array of e at x = i / TABLE_N


static func has_kind(kind: String) -> bool:
	return kind in KINDS


## the progress e in [0, 1] for progress x in [0, 1]; lv = the joint's level (scene.gd Scene.level), used by "throw"
static func progress(kind: String, x: float, lv := 0) -> float:
	x = clampf(x, 0.0, 1.0)
	match kind:
		"reach":
			return x * x * x * (x * (6.0 * x - 15.0) + 10.0)
		"strike":
			return _skew(x, STRIKE_PEAK)
		"throw":
			return _skew(x, THROW_P0 + THROW_STEP * float(clampi(lv, 0, 6)))
		"settle":
			return _settle(x)
	return x


## the skewed bell: speed v(s) = s^a (1 - s)^b, a = K p, b = K (1 - p), so the speed peaks at s = p. e is its integral,
## normalised to 1 at s = 1. Tabulated once per p (Simpson's rule), read back by linear interpolation: deterministic.
static func _skew(x: float, p: float) -> float:
	var key := snappedf(p, 0.000001)
	_mu.lock()   # ROADMAP 99: the pose bake (a worker thread) and the main thread both fill this cache
	if not _tables.has(key):
		_tables[key] = _table(key)
	var tab: PackedFloat64Array = _tables[key]
	_mu.unlock()
	var f := x * TABLE_N
	var i := mini(int(f), TABLE_N - 1)
	var w := f - float(i)
	return tab[i] + (tab[i + 1] - tab[i]) * w


static func _table(p: float) -> PackedFloat64Array:
	var a := K * p
	var b := K * (1.0 - p)
	var v := func(s: float) -> float: return pow(s, a) * pow(1.0 - s, b)
	var tab := PackedFloat64Array()
	tab.resize(TABLE_N + 1)
	var acc := 0.0
	tab[0] = 0.0
	var h := 1.0 / float(TABLE_N)
	for i in TABLE_N:
		var s0 := float(i) * h
		# Simpson over one cell (the power terms are finite at the ends for a, b > 0)
		var f0: float = v.call(s0)
		var fm: float = v.call(s0 + 0.5 * h)
		var f1: float = v.call(s0 + h)
		acc += h / 6.0 * (f0 + 4.0 * fm + f1)
		tab[i + 1] = acc
	var total := tab[TABLE_N]
	for i in TABLE_N + 1:
		tab[i] /= total
	return tab


## damped spring step response, normalised: s(x) / s(1)
static func _settle(x: float) -> float:
	var z := SETTLE_ZETA
	var wd := SETTLE_WN * sqrt(1.0 - z * z)
	var s := func(t: float) -> float:
		return 1.0 - exp(-z * SETTLE_WN * t) * (cos(wd * t) + z / sqrt(1.0 - z * z) * sin(wd * t))
	var s1: float = s.call(1.0)
	var sx: float = s.call(x)
	return 0.0 if x <= 0.0 else (1.0 if x >= 1.0 else sx / s1)
