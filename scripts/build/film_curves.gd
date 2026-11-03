class_name FilmCurves
extends Control
## s269c: the picked body's SPIN and MOVE keys drawn as curves against film time, under the timeline: the spin angle (orange, degrees) and the move
## offset on X / Y / Z (red / green / blue, mm), each fitted to its own range, a dot at every key and a line at the playhead.
## The line is Film.spin_deg / Film.offset_at sampled, so the curve drawn is the motion played. A channel with no keys (or no change) is not drawn.
## Read-only: the keys are edited with the buttons beside it.

var rec_fn: Callable = Callable()   # () -> Dictionary, the part record
var body := 0
var playhead := 0.0
const PAD := 6.0
const SAMPLES := 96
const COLS := [Color(1.0, 0.65, 0.2), Color(1.0, 0.3, 0.3), Color(0.35, 0.9, 0.4), Color(0.4, 0.6, 1.0)]
const BG := Color(0.05, 0.05, 0.07)


func _init() -> void:
	name = "film_curves"
	custom_minimum_size.y = 64
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func rec() -> Dictionary:
	return rec_fn.call() if rec_fn.is_valid() else {}


func span() -> float:
	return maxf(Film.duration(rec()), 0.001)


func t_to_x(t: float) -> float:
	return PAD + t / span() * (size.x - 2.0 * PAD)


## the keys of channel c (0 spin, 1..3 move x/y/z) as [[t, value], ...]
func chan_keys(c: int) -> Array:
	var d := Film.data(rec())
	var out: Array = []
	if c == 0:
		for e in d.get("spins", []):
			if int(e["body"]) == body:
				for k in e.get("track", []):
					out.append([float(k[0]), float(k[1])])
	else:
		for e in d.get("moves", []):
			if int(e["body"]) == body:
				for k in e.get("track", []):
					out.append([float(k[0]), float((k[1] as Array)[c - 1])])
	return out


func value_at(c: int, t: float) -> float:
	if c == 0:
		return Film.spin_deg(rec(), body, t)
	return Film.offset_at(rec(), body, t)[c - 1] / Film.MM


## [lo, hi] of channel c over the film (sampled); hi - lo < 1e-6 = the channel does not change and is not drawn
func chan_range(c: int) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in SAMPLES + 1:
		var v := value_at(c, span() * float(i) / float(SAMPLES))
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return Vector2(lo, hi)


func drawn(c: int) -> bool:
	if chan_keys(c).is_empty():
		return false
	var r := chan_range(c)
	return r.y - r.x > 1e-6


func v_to_y(c: int, v: float) -> float:
	var r := chan_range(c)
	var u := (v - r.x) / maxf(r.y - r.x, 1e-9)
	return size.y - PAD - u * (size.y - 2.0 * PAD)


## every dot drawn: [{"ch", "t", "pos"}] in this control's coordinates
func dots() -> Array:
	var out: Array = []
	for c in 4:
		if not drawn(c):
			continue
		for k in chan_keys(c):
			out.append({"ch": c, "t": k[0], "pos": Vector2(t_to_x(k[0]), v_to_y(c, k[1]))})
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for c in 4:
		if not drawn(c):
			continue
		var pts := PackedVector2Array()
		for i in SAMPLES + 1:
			var t := span() * float(i) / float(SAMPLES)
			pts.append(Vector2(t_to_x(t), v_to_y(c, value_at(c, t))))
		draw_polyline(pts, COLS[c], 1.5)
	for d in dots():
		draw_circle(d["pos"], 3.5, COLS[d["ch"]])
	var x := t_to_x(clampf(playhead, 0.0, span()))
	draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.7), 1.0)
