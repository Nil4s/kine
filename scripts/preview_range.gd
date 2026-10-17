## FRAMES + PREVIEW RANGE (round 41, GATE WW4, UPGRADES #262 / #263). Small and local; main.gd holds the two view
## numbers (pv_in, pv_out) and the frames switch. NONE of it is saved in the scene: the range and the frames switch are
## view settings (like Stepped), and the scene samples exactly as before. Only Scene.fps (which already existed and is
## already saved) is a scene setting.
class_name PreviewRange
extends RefCounted

const FPS_CHOICES := [24, 30, 60]
const EPS := 1e-4   # s: a time this close to a whole frame counts as on it


## "0.74 / 1.72 s", or in frames "44 / 103 f" (rounded to the nearest frame)
static func time_text(t: float, length: float, fps: int, frames: bool) -> String:
	if frames:
		return "%d / %d f" % [roundi(t * fps), roundi(length * fps)]
	return "%.2f / %.2f s" % [t, length]


## how many of the scene's card times (each card's start, arrival and leave) are NOT on a whole frame at this fps.
## A time shared by two cards (one's leave is the next one's start) counts once.
static func off_grid(S: Scene, fps: int) -> int:
	var seen := {}
	var n := 0
	for tr in S.times():
		for t in tr:
			var key := roundi(float(t) * 10000.0)
			if seen.has(key):
				continue
			seen[key] = true
			var f := float(t) * fps
			if absf(f - roundf(f)) > EPS * fps:
				n += 1
	return n


## the range as [a, b] inside 0..length, or [] when none is set / it is empty. A value below 0 means "not set".
static func span(pv_in: float, pv_out: float, length: float) -> Array:
	if pv_in < 0.0 and pv_out < 0.0:
		return []
	var a := clampf(maxf(pv_in, 0.0), 0.0, length)
	var b := clampf(pv_out if pv_out >= 0.0 else length, 0.0, length)
	if b - a < 1.0 / 120.0:
		return []
	return [a, b]


## one play step. Returns {"t": new playhead, "stop": bool}. With no range: the old behaviour (past the end, back to 0).
## With a range: a playhead outside it enters at the in point, then past the out point it wraps to the in point when
## the scene's Loop is on, else it stops AT the out point.
static func tick(t: float, dt: float, length: float, pv_in: float, pv_out: float, loop: bool) -> Dictionary:
	var sp := span(pv_in, pv_out, length)
	if sp.is_empty():
		t += dt
		return {"t": 0.0 if t > length else t, "stop": false}
	if t < sp[0] or t > sp[1]:
		t = sp[0]
	t += dt
	if t > sp[1]:
		if loop:
			return {"t": sp[0], "stop": false}
		return {"t": sp[1], "stop": true}
	return {"t": t, "stop": false}
