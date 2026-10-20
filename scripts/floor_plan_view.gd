## floor_plan_view.gd - I42: the floor plan drawn on a Control (the panel) or in a SubViewport (the PNG). Colours are Tok tokens. The whole plan
## (FloorPlan "bounds") is fitted into the control's rect, so it can not spill out of its panel. plan = FloorPlan.analyze(...)
class_name FloorPlanView
extends Control

var plan: Dictionary = {}
var drawn := Rect2()   # the pixel box of everything drawn last (the grid excluded), for the fit bar of the test


func _px(fx: Dictionary, p: Vector2) -> Vector2:
	return FloorPlan.to_px(fx, plan["bounds"], p)


func _text(p: Vector2, s: String, size: int, col: Color, keep := true) -> void:
	var f := ThemeDB.fallback_font
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	if keep:
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		_pt(p + Vector2(w.x, 2.0))
		_pt(p - Vector2(0.0, w.y))


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
		_text(c + Vector2(r + 2.0, 3.0), "%s %.2f s" % [String(sf["kind"]).to_upper(), float(sf["t"])], 10, col)
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
				_text(q + Vector2(4.0, -4.0), "%.0f s" % tk, 9, Tok.c("text"))
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
			_text(e + Vector2(5.0, 10.0), "%s %.2f s" % [String(st["tip"]).replace("_", " "), float(st["t1"])], 9, Tok.c("text"))
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
			_text(c + Vector2(-3.0, 4.0), "%d" % int(stp["n"]), 11, ink)
			_text(c + Vector2(8.0, 14.0), "%.2f s" % float(stp["t"]), 9, Tok.c("text"))
	var sb := Vector2(14.0, H - 14.0)
	draw_line(sb, sb + Vector2(s, 0.0), ink, 3.0)
	_text(sb + Vector2(s + 4.0, 4.0), "100 cm", 10, Tok.c("text"))
