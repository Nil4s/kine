class_name CarSuspPlan
extends Control
## VEHICLE, STEP 3 SUSPENSION drawing: the front corner in the front view (y across, z up: the arms as lines, the pivots as points, the
## steering axis dashed to the ground, the tyre as a leaning band, the roll centre marker, the mirrored ghost of the other side in grey) and
## the side view (x forward, z up: the wheels, the steering axis and its caster angle). Draws only: the numbers are CarSusp's
## (readouts at the Bounce in set_data). Mouse does nothing here. The left half is the front view, the right half the side view.

const ARM := Color(0.75, 0.85, 0.95)
const STRUT := Color(0.95, 0.75, 0.55)
const AXIS := Color(0.55, 0.9, 0.6)
const TYRE := Color(0.85, 0.85, 0.9, 0.5)
const GHOST := Color(0.5, 0.5, 0.55, 0.45)
const RC_COL := Color(1.0, 0.79, 0.2)
const GROUND := Color(0.5, 0.75, 1.0)
const PAD := 36.0

var p := {}
var c := {}
var s := {}
var bounce := 0.0
var ro := {}         # the readouts at the Bounce (CarSusp.readouts)
var front_view := Rect2()
var side_view := Rect2()


func set_data(p_: Dictionary, c_: Dictionary, s_: Dictionary, bounce_: float) -> void:
	p = p_
	c = c_
	s = CarSusp.norm(s_)
	bounce = bounce_
	ro = CarSusp.readouts(p, c, s, bounce) if not p.is_empty() else {}
	queue_redraw()


func _draw() -> void:
	if p.is_empty() or ro.is_empty():
		return
	var half := size.x * 0.5
	front_view = Rect2(0.0, 0.0, half - 6.0, size.y)
	side_view = Rect2(half + 6.0, 0.0, size.x - half - 6.0, size.y)
	_draw_front()
	_draw_side()


func _draw_front() -> void:
	var g := CarSusp.geo(p, c, s)
	var cn: Dictionary = g["front"]
	var po := CarSusp.pose(cn, bounce)
	var tf := float(p["track_f"])
	var ext := tf * 0.5 + 400.0
	var k := minf((front_view.size.x * 0.5 - 8.0) / ext, (front_view.size.y - PAD - 40.0) / 900.0)
	var cx := front_view.position.x + front_view.size.x * 0.5
	var base := front_view.position.y + front_view.size.y - PAD
	var font := get_theme_default_font()
	draw_line(Vector2(front_view.position.x + 6.0, base), Vector2(front_view.end.x - 6.0, base), GROUND, 2.0)
	draw_string(font, Vector2(front_view.position.x + 8.0, front_view.position.y + 16.0), "Front view: wheel tilt %s deg, steering tilt %s deg, scrub %s mm" % [
		str(snappedf(float(ro["camber"]), 0.1)), str(snappedf(float(ro["kpi"]), 0.1)), str(int(round(float(ro["scrub"]))))],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1, 1, 1, 0.85))
	var rc: float = ro["rc"]
	for sd in [-1.0, 1.0]:
		var col := ARM if sd > 0.0 else GHOST
		var at := func(v: Vector3) -> Vector2:
			return Vector2(cx + sd * v.y * k, base - v.z * k)
		var W: Vector3 = po["W"]
		var C: Vector3 = po["C"]
		var top := W + (W - C)
		var tw := float(cn["tw"])
		var hw := Vector3(0.0, tw * 0.5, 0.0)
		var poly := PackedVector2Array([at.call(C - hw), at.call(C + hw), at.call(top + hw), at.call(top - hw)])
		draw_colored_polygon(poly, TYRE if sd > 0.0 else GHOST)
		var L: Vector3 = po["L"]
		var T: Vector3 = po["T"]
		var lo_mid: Vector3 = ((cn["lf"] as Vector3) + (cn["lr"] as Vector3)) * 0.5
		draw_line(at.call(lo_mid), at.call(L), col, 3.0 if sd > 0.0 else 1.5)
		if String(cn["kind"]) == "strut":
			draw_line(at.call(L), at.call(T), STRUT if sd > 0.0 else GHOST, 6.0 if sd > 0.0 else 2.0)
		else:
			var up_mid: Vector3 = ((cn["uf"] as Vector3) + (cn["ur"] as Vector3)) * 0.5
			draw_line(at.call(up_mid), at.call(T), col, 3.0 if sd > 0.0 else 1.5)
			draw_circle(at.call(cn["uf"]), 3.0, col)
			draw_circle(at.call(cn["ur"]), 3.0, col)
		# the steering axis, dashed to the ground
		var t := -L.z / (T.z - L.z)
		var G := L + (T - L) * t
		if sd > 0.0:
			_dashed(at.call(G), at.call(T), AXIS)
		draw_circle(at.call(lo_mid), 3.0, col)
		draw_circle(at.call(cn["lf"]), 3.0, col)
		draw_circle(at.call(cn["lr"]), 3.0, col)
		draw_circle(at.call(L), 4.0, col)
		draw_circle(at.call(T), 4.0, col)
		if sd > 0.0:
			draw_circle(at.call(C), 3.0, Color(1, 1, 1))
	if not is_nan(rc):
		var rp := Vector2(cx, base - rc * k)
		draw_line(Vector2(cx, base), rp, RC_COL, 1.0)
		draw_rect(Rect2(rp - Vector2(4, 4), Vector2(8, 8)), RC_COL, false, 2.0)
		draw_string(font, rp + Vector2(8.0, -4.0), "roll centre %d mm" % int(round(rc)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, RC_COL)


func _draw_side() -> void:
	var g := CarSusp.geo(p, c, s)
	var wb := float(p["wheelbase"])
	var xmin := -wb - 300.0
	var xmax := 350.0
	var k := minf((side_view.size.x - 16.0) / (xmax - xmin), (side_view.size.y - PAD - 40.0) / 900.0)
	var base := side_view.position.y + side_view.size.y - PAD
	var font := get_theme_default_font()
	var at := func(v: Vector3) -> Vector2:
		return Vector2(side_view.position.x + 8.0 + (v.x - xmin) * k, base - v.z * k)
	draw_line(Vector2(side_view.position.x + 6.0, base), Vector2(side_view.end.x - 6.0, base), GROUND, 2.0)
	var fr: Dictionary = g["front"]
	var rr: Dictionary = g["rear"]
	for cn in [fr, rr]:
		var po := CarSusp.pose(cn, bounce)
		var W: Vector3 = po["W"]
		draw_arc(at.call(W), float(cn["r"]) * k, 0.0, TAU, 40, TYRE, 3.0)
		var L: Vector3 = po["L"]
		var lo_mid: Vector3 = ((cn["lf"] as Vector3) + (cn["lr"] as Vector3)) * 0.5
		draw_line(at.call(lo_mid), at.call(L), ARM, 2.0)
		draw_line(at.call(L), at.call(W), ARM, 1.5)
	var po_f := CarSusp.pose(fr, bounce)
	var L2: Vector3 = po_f["L"]
	var T2: Vector3 = po_f["T"]
	var t := -L2.z / (T2.z - L2.z)
	var G2 := L2 + (T2 - L2) * t
	_dashed(at.call(G2), at.call(T2), AXIS)
	draw_line(at.call(L2), at.call(T2), STRUT, 3.0)
	draw_line(Vector2(at.call(G2).x, base), Vector2(at.call(G2).x, base - 6.0), AXIS, 1.0)
	var cap := "caster %s deg" % str(snappedf(float(ro["caster"]), 0.1))
	var cp: Vector2 = at.call(T2)
	draw_string(font, cp + Vector2(-(font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x + 8.0), -4.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, AXIS)
	draw_string(font, Vector2(side_view.position.x + 8.0, side_view.position.y + 16.0), "Side view: caster and trail (mechanical %s mm)" % str(int(round(float(ro["trail"])))),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1, 1, 1, 0.85))


## a dashed line from a to b (px)
func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(a.distance_to(b) / 10.0)
	for i in range(0, n, 2):
		var t0 := float(i) / float(maxi(n, 1))
		var t1 := float(mini(i + 1, n)) / float(maxi(n, 1))
		draw_line(a.lerp(b, t0), a.lerp(b, t1), col, 1.5)
