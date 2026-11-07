## sway.gd - N037 REAL SWAY IN HOLDS. A still stance sways a little, sized from published quiet-standing data, instead of the 8 % drift of moving holds.
## SIZE: quiet standing, eyes open, firm floor, young adults: RMS about the mean AP 3.5 mm, ML 2.5 mm (Prieto et al. 1996, IEEE TBME 43:956; Raymakers,
## Samson & Verhaar 2005, Gait Posture 21:48; quoted from memory, UNVERIFIED). Those are centre-of-pressure values; the COM moves a little less, so this is the upper bound.
## BAND: nearly all the power is 0.1-1 Hz (Winter 1995, Gait Posture 3:193). The trace is a sum of NCOMP sines log-spaced across the band, weighted by a bump
## around PEAK_HZ, random phases and a small jitter of each frequency from the seed (deterministic), scaled so the RMS is exactly the target.
## IN THE POSE: the COM sway is made by leaning the upper body on spine_01 (feet and pelvis stay): COM shift = GAIN_M * lean (rad), GAIN_M = 0.155 m: MEASURED on
## the Kine body (a first guess of 0.24 m from the HAT mass fraction 0.68 x 0.36 m gave 64 % of the target COM sway in strength_test S5, so the constant was set from that run). Eased in and out over RAMP s so a hold meets its moves without a pop.
class_name Sway
extends RefCounted

const RMS_AP_MM := 3.5
const RMS_ML_MM := 2.5
const BAND_LO := 0.1
const BAND_HI := 1.0
const PEAK_HZ := 0.3
const NCOMP := 10
const GAIN_M := 0.155
const RAMP := 0.3
static var _memo := {}


## {"f": [Hz], "pa": [rad], "pm": [rad], "wa": [amp AP mm], "wm": [amp ML mm]} for a seed
static func params(seed: int) -> Dictionary:
	if _memo.has(seed):
		return _memo[seed]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sway%d" % seed)
	var f := []
	var w := []
	var sw := 0.0
	for i in NCOMP:
		var u := (float(i) + rng.randf_range(0.15, 0.85)) / NCOMP
		var fr := BAND_LO * pow(BAND_HI / BAND_LO, u)
		f.append(fr)
		var z := log(fr / PEAK_HZ) / log(2.0) / 1.3
		var a := exp(-0.5 * z * z)
		w.append(a)
		sw += a * a * 0.5
	var pa := []
	var pm := []
	var wa := []
	var wm := []
	for i in NCOMP:
		pa.append(rng.randf() * TAU)
		pm.append(rng.randf() * TAU)
		var k := float(w[i]) / sqrt(sw)
		wa.append(k * RMS_AP_MM)
		wm.append(k * RMS_ML_MM)
	var out := {"f": f, "pa": pa, "pm": pm, "wa": wa, "wm": wm}
	_memo[seed] = out
	return out


## (ml_mm, ap_mm) at time t seconds
static func at(seed: int, t: float) -> Vector2:
	var p := params(seed)
	var ml := 0.0
	var ap := 0.0
	for i in NCOMP:
		var a := TAU * float(p["f"][i]) * t
		ap += float(p["wa"][i]) * sin(a + float(p["pa"][i]))
		ml += float(p["wm"][i]) * sin(a + float(p["pm"][i]))
	return Vector2(ml, ap)


static func trace(seed: int, seconds: float, hz: float) -> Array:
	var out := []
	for i in int(seconds * hz):
		out.append(at(seed, float(i) / hz))
	return out


## 0 -> 1 -> 0 over a hold of length len, ramping over RAMP s at each end
static func env(t: float, len: float) -> float:
	var r := minf(RAMP, len * 0.5)
	if r <= 1e-6:
		return 0.0
	var a := clampf(t / r, 0.0, 1.0)
	var b := clampf((len - t) / r, 0.0, 1.0)
	return a * a * (3.0 - 2.0 * a) * b * b * (3.0 - 2.0 * b)


## the lean (degrees) of spine_01 as (bend, side) at time t in a hold of length len (card i of the scene seeds its own sway)
static func lean_deg(seed: int, card: int, t: float, len: float) -> Vector2:
	var s := at(seed + card * 7919, t) * env(t, len)
	var k := rad_to_deg(1.0 / GAIN_M) / 1000.0
	return Vector2(s.y * k, s.x * k)   # (bend from AP, side from ML)
