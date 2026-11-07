## floor_plan_view.gd - I42: the floor plan drawn on a Control (the panel) or in a SubViewport (the PNG). Colours are Tok tokens. The whole plan
## (FloorPlan "bounds") is fitted into the control's rect, so it can not spill out of its panel. plan = FloorPlan.analyze(...)
class_name FloorPlanView
extends Control

var plan: Dictionary = {}
var drawn := Rect2()   # the pixel box of everything drawn last (the grid excluded), for the fit bar of the test
var labels: Array = []   # i42b: the rect of every text drawn last [{"text", "rect", "kind"}]; no two overlap (the declutter bar of the test)
var dropped := 0         # i42b: time labels left out because no free spot was near their footprint (the numbers are never dropped)
var _reqs: Array = []


func _px(fx: Dictionary, p: Vector2) -> Vector2:
	return FloorPlan.to_px(fx, plan["bounds"], p)


## a text asked for at p (its baseline start). keep: counts into `drawn` when it is placed. Placed by _resolve at the end of _draw
func _text(p: Vector2, s: String, size: int, col: Color, keep := true) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	_reqs.append({"text": s, "size": size, "col": col, "rect": Rect2(p + Vector2(0.0, -f.get_ascent(size)), Vector2(w.x, f.get_height(size))), "fixed": true, "keep": keep, "kind": "fixed"})


## a movable label: wants to sit at `want` (a rect centre offset from the anchor); prio 0 = a footprint's number (never dropped),
## 1 = strike and safety labels, 2 = footprint times, 3 = the seconds ticks (dropped when no free spot)
func _label(anchor: Vector2, want: Vector2, s: String, size: int, col: Color, prio: int, kind: String) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	_reqs.append({"text": s, "size": size, "col": col, "anchor": anchor, "want": want, "dim": Vector2(w.x, f.get_height(size)), "prio": prio, "fixed": false, "keep": true, "kind": kind})


func _free(r: Rect2, W: float, H: float) -> bool:
	if r.position.x < 1.0 or r.position.y < 1.0 or r.end.x > W - 1.0 or r.end.y > H - 1.0:
		return false
	for l in labels:
		if (l["rect"] as Rect2).grow(1.0).intersects(r):
			return false
	return true


## fixed texts first (the grid numbers, the scale), then the movable ones by priority: each tries its wish, then rings of
## 12..80 px around its anchor in 12 directions; the first free spot wins and gets a leader line when it is off the wish by more than
## 14 px. A priority 0 label that finds nothing takes its wish anyway (a number is never dropped), the others are dropped
func _resolve(W: float, H: float) -> void:
	labels = []
	dropped = 0
	var f := ThemeDB.fallback_font
	for q in _reqs:
		if q["fixed"]:
			labels.append({"text": q["text"], "rect": q["rect"], "kind": "fixed"})
			draw_string(f, (q["rect"] as Rect2).position + Vector2(0.0, f.get_ascent(int(q["size"]))), q["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(q["size"]), q["col"])
			if q["keep"]:
				_pt((q["rect"] as Rect2).position)
				_pt((q["rect"] as Rect2).end)
	var mov := _reqs.filter(func(q): return not q["fixed"])
	mov.sort_custom(func(a, b): return int(a["prio"]) < int(b["prio"]))   # sort_custom is not stable, but equal priorities do not matter
	for q in mov:
		var dim: Vector2 = q["dim"]
		var want: Vector2 = q["anchor"] + q["want"]
		var spot := Vector2.INF
		var cands := [want]
		for r in [12.0, 22.0, 34.0, 48.0, 64.0, 80.0]:
			for k in 12:
				var a := TAU * float(k) / 12.0
				cands.append(q["anchor"] + Vector2(cos(a), sin(a)) * (r + dim.x * 0.5 * absf(cos(a))) )
		for c in cands:
			if _free(Rect2(c - dim * 0.5, dim), W, H):
				spot = c
				break
		if spot == Vector2.INF:
			if int(q["prio"]) >= 2:
				dropped += 1
				continue
			spot = want
			spot = Vector2(clampf(spot.x, dim.x * 0.5 + 1.0, W - dim.x * 0.5 - 1.0), clampf(spot.y, dim.y * 0.5 + 1.0, H - dim.y * 0.5 - 1.0))
		var rect := Rect2(spot - dim * 0.5, dim)
		labels.append({"text": q["text"], "rect": rect, "kind": q["kind"]})
		if spot.distance_to(want) > 14.0:
			var edge := Vector2(clampf(q["anchor"].x, rect.position.x, rect.end.x), clampf(q["anchor"].y, rect.position.y, rect.end.y))
			draw_line(q["anchor"], edge, Color(q["col"], 0.8), 1.0)
		draw_string(f, rect.position + Vector2(0.0, f.get_ascent(int(q["size"]))), q["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(q["size"]), q["col"])
		_pt(rect.position)
		_pt(rect.end)
		_pt(q["anchor"])


func _pt(p: Vector2) -> void:
	if drawn.size == Vector2.ZERO and drawn.position == Vector2.ZERO:
		drawn = Rect2(p, Vector2.ZERO)
	else:
		drawn = drawn.expand(p)


func _draw() -> void:
	var W := size.x
	var H := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Tok.c("floor"))
	drawn = Rect2()
	_reqs = []
	labels = []
	if plan.is_empty():
		return
	var b: Rect2 = plan["bounds"]
	var fx := FloorPlan.fit(b, W, H, 6.0)
	var s: float = fx["s"]
	var ink := Tok.c("ink")
	var x0: float = ceil(b.position.x)
	while x0 <= b.end.x:
		var p := _px(fx, Vector2(x0, b.position.y))
		var q := _px(fx, Vector2(x0, b.end.y))
		draw_line(p, q, Tok.c("grid_major" if int(x0) % 5 == 0 else "grid"), 1.0)
		_text(p + Vector2(2.0, 11.0), Units.len(x0), 10, Tok.c("text"), false)
		x0 += 1.0
	var z0: float = ceil(b.position.y)
	while z0 <= b.end.y:
		var p := _px(fx, Vector2(b.position.x, z0))
		var q := _px(fx, Vector2(b.end.x, z0))
		draw_line(p, q, Tok.c("grid_major" if int(z0) % 5 == 0 else "grid"), 1.0)
		_text(p + Vector2(2.0, -2.0), Units.len(z0), 10, Tok.c("text"), false)
		z0 += 1.0
	for sf in plan["safety"]:
		var c := _px(fx, sf["at"])
		var col := Tok.c("fail" if sf["sev"] == "red" else "warn")
		var r := maxf(float(sf["r"]) * s, 4.0)
		draw_circle(c, r, Color(col, 0.18))
		draw_arc(c, r, 0.0, TAU, 32, col, 1.5)
		if float(sf["r_in"]) > 0.0:
			draw_arc(c, float(sf["r_in"]) * s, 0.0, TAU, 24, col, 1.0)
		_pt(c - Vector2(r, r))
		_pt(c + Vector2(r, r))
		_label(c, Vector2(r + 36.0, 0.0), "%s %.2f s" % [String(sf["kind"]).to_upper(), float(sf["t"])], 10, col, 1, "safety")
	for f in plan["fighters"]:
		var col := Tok.c(String(f["color"]))
		var pl := PackedVector2Array()
		for p in f["com"]:
			pl.append(_px(fx, p))
			_pt(pl[pl.size() - 1])
		if pl.size() >= 2:
			draw_polyline(pl, Color(col, 0.85), 2.5, true)
			var e := pl[pl.size() - 1]
			var d := (e - pl[maxi(0, pl.size() - 4)]).normalized()
			if d.length() > 0.0:
				var n := Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([e + d * 7.0, e - d * 5.0 + n * 5.0, e - d * 5.0 - n * 5.0]), col)
		var tk := 1.0
		var ct: PackedFloat32Array = f["com_t"]
		for i in ct.size():
			if float(ct[i]) + 1e-4 >= tk:
				var q := pl[i]
				draw_circle(q, 3.0, col)
				_label(q, Vector2(11.0, -8.0), "%.0f s" % tk, 9, Tok.c("text"), 3, "tick")
				tk += 1.0
		for st in f["strikes"]:
			var a := _px(fx, st["from"])
			var e := _px(fx, st["to"])
			var d := (e - a).normalized()
			var n := Vector2(-d.y, d.x)
			draw_dashed_line(a, e, col, 2.0, 6.0)
			draw_colored_polygon(PackedVector2Array([e, e - d * 9.0 + n * 4.5, e - d * 9.0 - n * 4.5]), col)
			_pt(a)
			_pt(e)
			var sl := "%s %.2f s" % [String(st["tip"]).replace("_", " "), float(st["t1"])]
			_label(e, Vector2(5.0 + ThemeDB.fallback_font.get_string_size(sl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x * 0.5, 10.0), sl, 9, Tok.c("text"), 1, "strike")
		for stp in f["steps"]:
			var poly := FloorPlan.foot_poly(stp["heel"], stp["toe"])
			var pp := PackedVector2Array()
			for v in poly:
				pp.append(_px(fx, v))
				_pt(pp[pp.size() - 1])
			draw_colored_polygon(pp, Color(col, 0.6))
			var cl := pp.duplicate()
			cl.append(pp[0])
			draw_polyline(cl, ink, 1.2)
			var c := _px(fx, stp["pos"])
			_label(c, Vector2.ZERO, "%d" % int(stp["n"]), 11, ink, 0, "number")
			_label(c, Vector2(24.0, 12.0), "%.2f s" % float(stp["t"]), 9, Tok.c("text"), 2, "time")
	var sb := Vector2(14.0, H - 14.0)
	draw_line(sb, sb + Vector2(s, 0.0), ink, 3.0)
	_text(sb + Vector2(s + 4.0, 4.0), Units.len(1.0), 10, Tok.c("text"))
	_resolve(W, H)
