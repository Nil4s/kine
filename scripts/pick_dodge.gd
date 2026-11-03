class_name PickDodge
extends RefCounted
## C29 (complaint 790): a panel over the body costs clicks. Given the rect a floating panel wants, move it to the nearest spot
## inside `bounds` where it covers none of the body's main-part pick points (PickCheck.PARTS middles, grown by `pad`).
## Nothing else changes: if no spot is free the wanted position is kept.

static func points(m: Node) -> Array:
	var out := []
	for j in PickCheck.PARTS:
		if not m.B.P.has(j) or m.hidden_parts.has(j):
			continue
		var c: Array = m.B.cap(j)
		var w: Vector3 = (c[0] + c[1]) * 0.5
		if not m.cam.is_position_behind(w):
			out.append(m.cam.unproject_position(w))
	return out


static func covers(r: Rect2, pts: Array, pad: float) -> bool:
	var g := r.grow(pad)
	for p in pts:
		if g.has_point(p):
			return true
	return false


static func place(want: Vector2, size: Vector2, bounds: Rect2, pts: Array, pad := 10.0) -> Vector2:
	if not covers(Rect2(want, size), pts, pad):
		return want
	var best := want
	var bd := INF
	var step := 16.0
	var y := bounds.position.y
	while y + size.y <= bounds.end.y + 0.1:
		var x := bounds.position.x
		while x + size.x <= bounds.end.x + 0.1:
			var q := Vector2(x, y)
			var d := q.distance_squared_to(want)
			if d < bd and not covers(Rect2(q, size), pts, pad):
				bd = d
				best = q
			x += step
		y += step
	return best


## Widen the panel's wrapping button row (330, 520, 700 px) until a spot covering no pick point exists; the first width that has
## one wins. Returns the position (the narrow, original-width answer when none does).
static func fit(panel: Control, want: Vector2, bounds: Rect2, pts: Array, pad := 10.0) -> Vector2:
	var hf := panel.find_children("*", "HFlowContainer", true, false)
	var first := place(want, panel.size, bounds, pts, pad)
	if hf.is_empty() or not covers(Rect2(first, panel.size), pts, pad):
		return first
	var h: HFlowContainer = hf[0]
	for w in [520.0, 700.0, 240.0, 170.0]:
		h.custom_minimum_size.x = w
		panel.reset_size()
		var q := place(want, panel.size, bounds, pts, pad)
		if not covers(Rect2(q, panel.size), pts, pad):
			return q
	h.custom_minimum_size.x = 330.0
	panel.reset_size()
	return first
