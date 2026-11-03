class_name PickCheck
extends RefCounted
## C26 (complaint 790, "you have to click 3 or 4 times to select a body"): a timed pick-hit check. "Help: test body selection"
## aims one probe at the middle of each of the body's main parts (where it is on the screen now), asks the very pick a click
## uses (main._pick) what is under that pixel, and times it. It says how many probes hit the body part they were aimed at on
## the FIRST try and how long a pick takes (median / slowest). Opt-in; it changes nothing (no selection, no undo step).

const PARTS := ["head", "chest", "pelvis", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "shin_l", "shin_r"]
static var burn_ms := 0.0   # TEST-ONLY: busy-wait added inside each timed pick (a planted slow pick)

var m: Node
var last := {}


func _init(main: Node) -> void:
	m = main


func run() -> Dictionary:
	var cam: Camera3D = m.cam
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	var ts := []
	var hit := 0
	var any := 0
	var n := 0
	var misses := []
	for j in PARTS:
		if not m.B.P.has(j) or m.hidden_parts.has(j):
			continue
		var c: Array = m.B.cap(j)
		var w: Vector3 = (c[0] + c[1]) * 0.5
		if cam.is_position_behind(w):
			continue
		var p := cam.unproject_position(w)
		if not vp.has_point(p):
			continue
		n += 1
		var t0 := Time.get_ticks_usec()
		var got: String = m._pick(p)
		if burn_ms > 0.0:
			var until := Time.get_ticks_usec() + int(burn_ms * 1000.0)
			while Time.get_ticks_usec() < until:
				pass
		ts.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		if got == j:
			hit += 1
		else:
			misses.append("%s->%s" % [j, got if got != "" else "nothing"])
		if got != "":
			any += 1
	ts.sort()
	last = {"n": n, "first_try": hit, "any": any, "median_ms": float(ts[ts.size() / 2]) if not ts.is_empty() else 0.0,
		"max_ms": float(ts[-1]) if not ts.is_empty() else 0.0, "misses": misses}
	var msg := "selection check: %d of %d probes picked the part they aimed at on the first click (%d found the body); a pick takes %.2f ms (slowest %.2f ms)" % [hit, n, any, last["median_ms"], last["max_ms"]]
	if not misses.is_empty():
		msg += "; missed: " + ", ".join(misses.slice(0, 4))
	last["text"] = msg
	m._say_plain(msg)
	return last
