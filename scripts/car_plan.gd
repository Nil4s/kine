class_name CarPlan
extends Control
## VEHICLE PACKAGE: the engineering layout, drawn from the hard points (CarPackage): a side view (ground line, both wheels at their axles,
## the body's outline, the package box, the seated fighter at the H-point with the seat back angle, the head room) and a top view (the body
## length and width, the four tyres at the tracks). Every dimension is labelled in mm; the angles in degrees.
## Draws only; the numbers are CarPackage.derive's. Set p (the hard points) and call queue_redraw.

const LINE := Color(0.75, 0.85, 0.95)
const DIM := Color(1.0, 0.79, 0.2)
const FIGURE := Color(0.95, 0.75, 0.55)
const GROUND := Color(0.5, 0.75, 1.0)
const M := 46.0           # px margin inside each view
var p := {}
var d := {}
var side_r := Rect2()     # the side view's rectangle (px), for the tests
var top_r := Rect2()


func set_points(hp: Dictionary) -> void:
	p = hp.duplicate()
	d = CarPackage.derive(p)
	queue_redraw()


func _draw() -> void:
	if p.is_empty():
		return
	var h := size.y
	side_r = Rect2(0.0, 0.0, size.x, h * 0.62)
	top_r = Rect2(0.0, h * 0.64, size.x, h * 0.36)
	draw_rect(side_r, Color(0.09, 0.1, 0.13), true)
	draw_rect(top_r, Color(0.09, 0.1, 0.13), true)
	_side(side_r)
	_top(top_r)


func _txt(at: Vector2, t: String, col := DIM, sz := 13, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(t, align, -1, sz).x
	var x := at.x - w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else at.x
	draw_string(f, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## a dimension line between two points with its label (mm)
func _dim(a: Vector2, b: Vector2, t: String) -> void:
	draw_line(a, b, DIM, 1.0)
	var u := (b - a).normalized()
	var n := Vector2(-u.y, u.x) * 5.0
	draw_line(a - n, a + n, DIM, 1.0)
	draw_line(b - n, b + n, DIM, 1.0)
	_txt((a + b) * 0.5 + Vector2(0.0, -6.0), t)


func _side(r: Rect2) -> void:
	var L := float(d["length"])
	var H := float(d["height"])
	var s := minf((r.size.x - 2.0 * M) / L, (r.size.y - 2.0 * M) / (H + 120.0))
	var x0 := r.position.x + (r.size.x - L * s) * 0.5
	var y0 := r.position.y + r.size.y - M * 0.6          # the ground line
	var X := func(mm: float) -> float:
		return x0 + mm * s
	var Y := func(mm: float) -> float:
		return y0 - mm * s
	var wb := float(p["wheelbase"])
	var foh := float(p["front_oh"])
	var clr := float(p["clearance"])
	var rr := float(d["r"])
	# ground line
	draw_line(Vector2(r.position.x + 6.0, y0), Vector2(r.end.x - 6.0, y0), GROUND, 2.0)
	# the package box (dashed, outline of length x height)
	var box := PackedVector2Array([Vector2(X.call(0.0), Y.call(0.0)), Vector2(X.call(L), Y.call(0.0)), Vector2(X.call(L), Y.call(H)), Vector2(X.call(0.0), Y.call(H))])
	for i in 4:
		_dash(box[i], box[(i + 1) % 4])
	# the body: nose, bonnet, windscreen, roof, tail (from the clearance up to the roof)
	var roof_y := H
	var body := PackedVector2Array([
		Vector2(X.call(0.0), Y.call(clr + 60.0)), Vector2(X.call(0.0), Y.call(clr)), Vector2(X.call(L), Y.call(clr)),
		Vector2(X.call(L), Y.call(clr + (H - clr) * 0.55)), Vector2(X.call(L - (L - foh - wb) * 0.2), Y.call(roof_y - 80.0)),
		Vector2(X.call(foh + wb * 0.42), Y.call(roof_y)), Vector2(X.call(foh + wb * 0.12), Y.call(clr + (H - clr) * 0.55)),
		Vector2(X.call(0.0), Y.call(clr + 130.0))])
	draw_polyline(body, LINE, 2.0)
	draw_line(body[body.size() - 1], body[0], LINE, 2.0)
	# the wheels on their axles
	for ax in [foh, foh + wb]:
		draw_arc(Vector2(X.call(ax), Y.call(rr)), rr * s, 0.0, TAU, 40, LINE, 2.0)
		draw_arc(Vector2(X.call(ax), Y.call(rr)), rr * s * 0.45, 0.0, TAU, 20, LINE, 1.0)
	# the seated fighter: H-point, seat back, thigh, shin, head
	var hx := foh + float(p["hpt_x"])   # the H-point: back from the front axle
	var hy := float(p["hpt_h"])
	var a := deg_to_rad(float(p["seat_a"]))
	var back := Vector2(sin(a), cos(a))
	var hp := Vector2(X.call(hx), Y.call(hy))
	var nk := Vector2(X.call(hx + back.x * CarPackage.TORSO), Y.call(hy + back.y * CarPackage.TORSO))
	var nk2 := Vector2(X.call(hx + back.x * (CarPackage.TORSO + CarPackage.NECK)), Y.call(hy + back.y * (CarPackage.TORSO + CarPackage.NECK)))
	var hc := Vector2(X.call(hx + back.x * (CarPackage.TORSO + CarPackage.NECK + CarPackage.HEAD * 0.5)), Y.call(hy + back.y * (CarPackage.TORSO + CarPackage.NECK + CarPackage.HEAD * 0.5)))
	var knee_mm := hx - CarPackage.THIGH
	var knee := Vector2(X.call(knee_mm), Y.call(hy))
	var dy := hy - CarPackage.PEDAL_H
	var foot_mm := knee_mm - sqrt(maxf(0.0, pow(CarPackage.SHIN, 2.0) - pow(dy, 2.0)))
	var foot := Vector2(X.call(foot_mm), Y.call(CarPackage.PEDAL_H))
	draw_line(hp, nk, FIGURE, 4.0)
	draw_line(nk, nk2, FIGURE, 2.0)
	draw_line(hp, knee, FIGURE, 4.0)
	draw_line(knee, foot, FIGURE, 3.0)
	draw_circle(hc, CarPackage.HEAD * 0.5 * s, FIGURE)
	draw_circle(hp, 3.0, DIM)
	draw_line(Vector2(X.call(0.0), Y.call(hy)), Vector2(X.call(hx), Y.call(hy)), Color(1, 1, 1, 0.15), 1.0)
	_txt(hp + Vector2(0.0, 18.0), "H-point %d" % int(hy), DIM, 12)
	# head room: head top to the roof
	var head_top_y := hc.y - CarPackage.HEAD * 0.5 * s
	var hx_top := Vector2(hc.x, Y.call(roof_y))
	draw_line(Vector2(hc.x, head_top_y), hx_top, DIM, 1.0)
	_txt(Vector2(hc.x + 8.0, (head_top_y + hx_top.y) * 0.5), "head room %d" % int(d["head"]), DIM, 12, HORIZONTAL_ALIGNMENT_LEFT)
	# dimensions: wheelbase above, length above that, clearance and nose at the front, roof at the front
	var dim_y: float = Y.call(roof_y + 170.0)
	_dim(Vector2(X.call(foh), dim_y), Vector2(X.call(foh + wb), dim_y), "wheelbase %d" % int(wb))
	_dim(Vector2(X.call(0.0), Y.call(roof_y + 420.0)), Vector2(X.call(L), Y.call(roof_y + 420.0)), "length %d" % int(d["length"]))
	_dim(Vector2(X.call(L + 40.0), Y.call(0.0)), Vector2(X.call(L + 40.0), Y.call(H)), "height %d" % int(H))
	_dim(Vector2(X.call(0.0) - 26.0, Y.call(clr)), Vector2(X.call(0.0) - 26.0, Y.call(0.0)), "%d" % int(clr))
	_txt(Vector2(X.call(foh * 0.5), Y.call(clr) - 14.0), "nose %d" % int(foh), DIM, 12)
	_txt(Vector2(X.call(L - float(p["rear_oh"]) * 0.5), Y.call(clr) - 14.0), "tail %d" % int(p["rear_oh"]), DIM, 12)
	_txt(Vector2(r.position.x + 8.0, r.position.y + 14.0), "Side view (mm)", LINE, 14, HORIZONTAL_ALIGNMENT_LEFT)


func _dash(a: Vector2, b: Vector2) -> void:
	var n := int(a.distance_to(b) / 10.0)
	for i in range(0, n, 2):
		draw_line(a.lerp(b, float(i) / float(n)), a.lerp(b, minf(1.0, float(i + 1) / float(n))), Color(1, 1, 1, 0.3), 1.0)


func _top(r: Rect2) -> void:
	var L := float(d["length"])
	var W := float(d["width"])
	var s := minf((r.size.x - 2.0 * M) / L, (r.size.y - 26.0) / (W + 60.0))
	var cx := r.position.x + r.size.x * 0.5
	var cy := r.position.y + r.size.y * 0.5 + 6.0
	var x0 := cx - L * s * 0.5
	var X := func(mm: float) -> float:
		return x0 + mm * s
	var Yc := func(mm: float) -> float:
		return cy + mm * s
	draw_rect(Rect2(X.call(0.0), Yc.call(-W * 0.5), L * s, W * s), LINE, false, 2.0)
	var foh := float(p["front_oh"])
	var wb := float(p["wheelbase"])
	var td := float(d["tyre_d"])
	var tw := float(d["tyre_w"])
	for ax in [foh, foh + wb]:
		for sd in [-1.0, 1.0]:
			var tr := float(p["track_f"]) if ax == foh else float(p["track_r"])
			var c: Vector2 = Vector2(X.call(ax), Yc.call(sd * tr * 0.5))
			draw_rect(Rect2(c - Vector2(td * 0.5 * s, tw * 0.5 * s), Vector2(td * s, tw * s)), LINE, true)
	var dy: float = Yc.call(-W * 0.5 - 30.0)
	_dim(Vector2(X.call(foh), dy), Vector2(X.call(foh + wb), dy), "wheelbase %d" % int(wb))
	var dx: float = X.call(L + 40.0)
	_dim(Vector2(dx, Yc.call(-float(p["track_f"]) * 0.5)), Vector2(dx, Yc.call(float(p["track_f"]) * 0.5)), "front track %d" % int(p["track_f"]))
	_txt(Vector2(r.position.x + 8.0, r.position.y + 14.0), "Top view (mm)", LINE, 14, HORIZONTAL_ALIGNMENT_LEFT)
	_txt(Vector2(cx, Yc.call(0.0) - 6.0), "width %d" % int(W), DIM, 12)
	_txt(Vector2(cx, Yc.call(W * 0.5) + 16.0), "rear track %d" % int(p["track_r"]), DIM, 12)