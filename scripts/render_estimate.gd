class_name RenderEstimate
## C25 (complaint 730): a render time estimate BEFORE rendering, naming the costly setting. A job is {w, h, frames, volumetric,
## blur_n (motion blur sub-frames), ssao, sdfgi}. Cost per frame = pixels * rate * (1 + sum of the settings' extra cost); the rate
## is seconds per pixel for a plain frame (DEFAULT_RATE, or calibrate() from one measured render on this machine).
## Extras (relative to a plain frame): volumetric fog +3.0, sdfgi +1.5, ssao +0.3; blur sub-frames multiply the whole frame by blur_n.

## opt-in (default false): Render shots says the estimate first; main._render_estimate() says it on demand
static var show_first := false
const DEFAULT_RATE := 4.0e-9
const EXTRA := {"volumetric": 3.0, "sdfgi": 1.5, "ssao": 0.3}
const NAMES := {"volumetric": "volumetric fog", "sdfgi": "SDFGI", "ssao": "SSAO"}


static func _pixels(j: Dictionary) -> float:
	return float(j.get("w", 1920)) * float(j.get("h", 1080))


static func _mult(j: Dictionary) -> float:
	var f := 1.0
	for k in EXTRA:
		if bool(j.get(k, false)):
			f += float(EXTRA[k])
	return f * float(maxi(1, int(j.get("blur_n", 1))))


## seconds per plain pixel from a measured run of this job (settings included)
static func calibrate(j: Dictionary, measured_secs: float) -> float:
	return measured_secs / maxf(1.0, _pixels(j) * float(j.get("frames", 1)) * _mult(j))


## {secs, costliest ("" when nothing costly is on), text}
static func estimate(j: Dictionary, rate := DEFAULT_RATE) -> Dictionary:
	var frames := int(j.get("frames", 1))
	var secs := _pixels(j) * frames * rate * _mult(j)
	var best := ""
	var gain := 0.0
	for k in EXTRA:
		if bool(j.get(k, false)) and float(EXTRA[k]) > gain:
			gain = float(EXTRA[k])
			best = String(NAMES[k])
	var n := int(j.get("blur_n", 1))
	if n > 1 and float(n - 1) * (1.0 + 0.0) >= maxf(gain, 0.0) and (n - 1) >= gain:
		best = "samples (motion blur sub-frames)"
	var t := "%.0f s" % secs if secs < 90.0 else "%.1f min" % (secs / 60.0)
	var why := "" if best == "" else ". The costly setting: %s" % best
	return {"secs": secs, "costliest": best, "text": "Render estimate: %d frames at %dx%d, about %s%s" % [frames, int(j.get("w", 1920)), int(j.get("h", 1080)), t, why]}
