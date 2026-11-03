class_name PickCheck
extends RefCounted
## C26 (complaint 790, "you have to click 3 or 4 times to select a body"): a timed pick-hit check. "Help: test body selection"
## aims one probe at the middle of each of the body's main parts (where it is on the screen now), asks the very pick a click
## uses (main._pick) what is under that pixel, and times it. It says how many probes hit the body part they were aimed at on
## the FIRST try and how long a pick takes (median / slowest). Opt-in; it changes nothing (no selection, no undo step).

const PARTS := ["head", "spine_03", "pelvis", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r"]
static var burn_ms := 0.0   # TEST-ONLY: busy-wait added inside each timed pick (a planted slow pick)

var m: Node
var last := {}


func _init(main: Node) -> void:
	m = main


## the topmost visible Control that would take a click at p (a panel over the body), or null. Walks the UI the way the
## engine routes a press: last child first, a hidden node and its children skipped, mouse_filter IGNORE passed through
static func blocker(n: Node, p: Vector2) -> Control:
	for i in range(n.get_child_count() - 1, -1, -1):
		var c := n.get_child(i)
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		var r := blocker(c, p)
		if r != null:
			return r
	if n is Control and (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP and (n as Control).get_global_rect().has_point(p) and not (n is Window):
		return n as Control
	return null


func run() -> Dictionary:
	var cam: Camera3D = m.cam
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	var ts := []
	var hit := 0
	var any := 0
	var n := 0
	var misses := []
	var blocked := []
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
		var bl: Control = null
		for ch in m.ui_root.get_children():   # the UI's own children: ui_root itself spans the window
			if ch is CanvasItem and not (ch as CanvasItem).visible:
				continue
			bl = blocker(ch, p)
			if bl != null:
				break
		if bl != null:
			blocked.append("%s under %s" % [j, bl.name])
		var t0 := Time.get_ticks_usec()
		var got: String = m._pick(p)
		if burn_ms > 0.0:
			var until := Time.get_ticks_usec() + int(burn_ms * 1000.0)
			while Time.get_ticks_usec() < until:
				pass
		ts.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		if got == j and bl == null:
			hit += 1
		elif bl == null:
			misses.append("%s->%s" % [j, got if got != "" else "nothing"])
		if got != "":
			any += 1
	ts.sort()
	last = {"n": n, "first_try": hit, "any": any, "median_ms": float(ts[ts.size() / 2]) if not ts.is_empty() else 0.0,
		"max_ms": float(ts[-1]) if not ts.is_empty() else 0.0, "misses": misses, "blocked": blocked}
	var msg := "selection check: %d of %d probes picked the part they aimed at on the first click (not under a panel) (%d found the body); a pick takes %.2f ms (slowest %.2f ms)" % [hit, n, any, last["median_ms"], last["max_ms"]]
	if not blocked.is_empty():
		msg += "; %d covered by a panel (a click there hits the panel, not the body): %s" % [blocked.size(), ", ".join(blocked.slice(0, 3))]
	if not misses.is_empty():
		msg += "; missed: " + ", ".join(misses.slice(0, 4))
	last["text"] = msg
	m._say_plain(msg)
	return last
