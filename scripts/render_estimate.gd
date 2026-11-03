class_name RenderEstimate
## C25 (complaint 730): a render time estimate BEFORE rendering, naming the costly setting. A job is {w, h, frames, ssao, sdfgi,
## volumetric, blur_n (motion blur sub-frames)}. A calibration cal = {over (secs per frame), rate (secs per pixel), extra {setting: extra}}:
## per frame = (over + rate * pixels) * (1 + sum of the extras of settings that are ON and were MEASURED), times blur_n.
## A setting with no measured extra (the default; or measured under MIN_EXTRA on this machine, e.g. volumetric fog ~1.0x) is NOT guessed
## and never named. fit() sets over and rate from two plain timings, learn() keeps a setting's measured extra.

const MIN_EXTRA := 0.3
const DEFAULT_RATE := 4.0e-9
const NAMES := {"volumetric": "volumetric fog", "sdfgi": "SDFGI", "ssao": "SSAO"}
## opt-in (default false): Render shots says the estimate first
static var show_first := false
## the calibration the app uses (a measured one replaces it)
static var app_cal := {"over": 0.0, "rate": DEFAULT_RATE, "extra": {}}


## two plain per-frame timings at two sizes -> over and rate
static func fit(w1: int, h1: int, t1: float, w2: int, h2: int, t2: float) -> Dictionary:
	var p1 := float(w1 * h1)
	var p2 := float(w2 * h2)
	var rate := maxf((t2 - t1) / maxf(p2 - p1, 1.0), 1e-12)
	return {"over": maxf(t1 - rate * p1, 0.0), "rate": rate, "extra": {}}


## keep setting key's extra when its per-frame time t_on at w x h shows >= MIN_EXTRA over a plain frame; otherwise it is dropped
static func learn(cal: Dictionary, key: String, w: int, h: int, t_on: float) -> Dictionary:
	var out := cal.duplicate(true)
	var x := t_on / maxf(float(cal["over"]) + float(cal["rate"]) * w * h, 1e-12) - 1.0   # the setting's extra as a share of a PLAIN frame
	(out["extra"] as Dictionary).erase(key)
	if x >= MIN_EXTRA:
		out["extra"][key] = x
	return out


## {secs, costliest ("" when nothing measured-costly is on), text}
static func estimate(j: Dictionary, cal := {}) -> Dictionary:
	if cal.is_empty():
		cal = {"over": 0.0, "rate": DEFAULT_RATE, "extra": {}}
	var ex: Dictionary = cal["extra"]
	var f := 1.0
	var best := ""
	var gain := 0.0
	for k in ex:
		if bool(j.get(k, false)):
			f += float(ex[k])
			if float(ex[k]) > gain:
				gain = float(ex[k])
				best = String(NAMES.get(k, k))
	var n := maxi(1, int(j.get("blur_n", 1)))
	if n > 1 and float(n - 1) >= gain:
		best = "samples (motion blur sub-frames)"
	var frames := int(j.get("frames", 1))
	var secs := (float(cal["over"]) + float(cal["rate"]) * float(j.get("w", 1920)) * float(j.get("h", 1080))) * f * n * frames
	var t := "%.0f s" % secs if secs < 90.0 else "%.1f min" % (secs / 60.0)
	var why := "" if best == "" else ". The costly setting: %s" % best
	return {"secs": secs, "costliest": best, "text": "Render estimate: %d frames at %dx%d, about %s%s" % [frames, int(j.get("w", 1920)), int(j.get("h", 1080)), t, why]}
