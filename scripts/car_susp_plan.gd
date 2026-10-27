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
const FRAME_PAD := 40.0      # mm, the margin round the drawn corner (the arm pivots to the outer tyre edge) and the front wheel
const CAPTION_BAND := 40.0   # px, the caption band at the top of each panel

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


var k := 1.0         # px per mm, ONE scale for both views (fitted to the panel height and width)
var base := 0.0      # px, the ground line, the same in both views
var ext := {"front": [0.0, 0.0], "side": [0.0, 0.0]}   # the drawn geometry's top and bottom in px, per view (set by _draw)
var fx0 := 0.0      # px, the front view x of y = 0 (the centreline; may be off the panel left, the corner is framed)


func _draw() -> void:
	if p.is_empty() or ro.is_empty():
		return
	var half := size.x * 0.5
	front_view = Rect2(0.0, 0.0, half - 6.0, size.y)
	side_view = Rect2(half + 6.0, 0.0, size.x - half - 6.0, size.y)
	_fit()
	_draw_front()
	_draw_side()


## the one scale: the tallest the car gets over the Bounce travel fills the panel height (less a caption band top and a margin bottom),
## and the drawn corner (the arm pivots to the outer tyre edge) and the front wheel (side view) must fit the panel width. Centred vertically.
func _fit() -> void:
	var g := CarSusp.geo(p, c, s)
	var cn: Dictionary = g["front"]
	var r := float(cn["r"])
	var tall := 0.0
	for sb in [-CarSusp.TRAVEL, 0.0, CarSusp.TRAVEL]:
		var po := CarSusp.pose(cn, sb)
		tall = maxf(tall, maxf(maxf((po["T"] as Vector3).z, (po["W"] as Vector3).z + r), maxf((cn["uf"] as Vector3).z, (cn["ur"] as Vector3).z)))
	var ymin := minf(minf((cn["lf"] as Vector3).y, (cn["lr"] as Vector3).y), minf((cn["uf"] as Vector3).y, (cn["ur"] as Vector3).y)) - FRAME_PAD
	var ymax := float(p["track_f"]) * 0.5 + float(cn["tw"]) * 0.5 + FRAME_PAD
	var h := front_view.size.y
	var k_h := (h - 2.0 * CAPTION_BAND) / maxf(tall, 1.0)
	var k_w := (front_view.size.x - 24.0) / maxf(ymax - ymin, 1.0)
	var k_s := (side_view.size.x - 24.0) / (2.0 * (r + FRAME_PAD))
	k = minf(k_h, minf(k_w, k_s))
	base = (h + tall * k) * 0.5
	fx0 = front_view.position.x + (front_view.size.x - (ymax - ymin) * k) * 0.5 - ymin * k


## a view point: the front view has y across (the car's left side, the centreline at fx0) and z up
func _fp(v: Vector3) -> Vector2:
	return _note(Vector2(fx0 + v.y * k, base - v.z * k), "front")


## the side view: x forward, the front axle at the middle of the panel, z up
func _sp(v: Vector3) -> Vector2:
	return _note(Vector2(side_view.position.x + side_view.size.x * 0.5 + v.x * k, base - v.z * k), "side")


## a drawn point counts toward the view's extent
func _note(q: Vector2, which: String) -> Vector2:
	var e: Array = ext[which]
	if e[0] == 0.0 and e[1] == 0.0:
		ext[which] = [q.y, q.y]
	else:
		ext[which] = [minf(float(e[0]), q.y), maxf(float(e[1]), q.y)]
	return q


func _draw_front() -> void:
	var g := CarSusp.geo(p, c, s)
	var cn: Dictionary = g["front"]
	var po := CarSusp.pose(cn, bounce)
	var font := get_theme_default_font()
	ext["front"] = [0.0, 0.0]
	draw_line(Vector2(front_view.position.x + 6.0, base), Vector2(front_view.end.x - 6.0, base), GROUND, 2.0)
	draw_string(font, Vector2(front_view.position.x + 8.0, front_view.position.y + 16.0), "Front view: wheel tilt %s deg, steering tilt %s deg, scrub %s mm" % [
		str(snappedf(float(ro["camber"]), 0.1)), str(snappedf(float(ro["kpi"]), 0.1)), str(int(round(float(ro["scrub"]))))],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1, 1, 1, 0.85))
	var col := ARM
	var W: Vector3 = po["W"]
	var C: Vector3 = po["C"]
	var top := W + (W - C)
	var tw := float(cn["tw"])
	var hw := Vector3(0.0, tw * 0.5, 0.0)
	var poly := PackedVector2Array([_fp(C - hw), _fp(C + hw), _fp(top + hw), _fp(top - hw)])
	draw_colored_polygon(poly, TYRE)
	var L: Vector3 = po["L"]
	var T: Vector3 = po["T"]
	var lo_mid: Vector3 = ((cn["lf"] as Vector3) + (cn["lr"] as Vector3)) * 0.5
	draw_line(_fp(lo_mid), _fp(L), col, 3.0)
	if String(cn["kind"]) == "strut":
		draw_line(_fp(L), _fp(T), STRUT, 6.0)
	else:
		var up_mid: Vector3 = ((cn["uf"] as Vector3) + (cn["ur"] as Vector3)) * 0.5
		draw_line(_fp(up_mid), _fp(T), col, 3.0)
		draw_circle(_fp(cn["uf"]), 3.0, col)
		draw_circle(_fp(cn["ur"]), 3.0, col)
	# the steering axis, dashed to the ground
	var t := -L.z / (T.z - L.z)
	var G := L + (T - L) * t
	_dashed(_fp(G), _fp(T), AXIS)
	draw_circle(_fp(lo_mid), 3.0, col)
	draw_circle(_fp(cn["lf"]), 3.0, col)
	draw_circle(_fp(cn["lr"]), 3.0, col)
	draw_circle(_fp(L), 4.0, col)
	draw_circle(_fp(T), 4.0, col)
	draw_circle(_fp(C), 3.0, Color(1, 1, 1))
	var rc: float = ro["rc"]
	if not is_nan(rc):
		# the roll centre is on the centreline (y = 0), which lies off the framed corner: its marker sits at the panel's left edge, height kept
		var rx := maxf(fx0, front_view.position.x + 14.0)
		var rp := Vector2(rx, base - rc * k)
		draw_line(Vector2(rx, base), rp, RC_COL, 1.0)
		draw_rect(Rect2(rp - Vector2(4, 4), Vector2(8, 8)), RC_COL, false, 2.0)
		draw_string(font, rp + Vector2(8.0, -4.0), "roll centre %d mm" % int(round(rc)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, RC_COL)
		_note(rp, "front")
	draw_string(font, Vector2(front_view.position.x + 8.0, front_view.end.y - 10.0), ("Front corner, left side. Roll centre on the centreline" + (" (off this view, left)" if fx0 < front_view.position.x + 14.0 else "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1, 1, 1, 0.5))


func _draw_side() -> void:
	var g := CarSusp.geo(p, c, s)
	var font := get_theme_default_font()
	ext["side"] = [0.0, 0.0]
	draw_line(Vector2(side_view.position.x + 6.0, base), Vector2(side_view.end.x - 6.0, base), GROUND, 2.0)
	var cn: Dictionary = g["front"]
	var po := CarSusp.pose(cn, bounce)
	var W: Vector3 = po["W"]
	var r := float(cn["r"])
	var ctr := _sp(W)
	draw_arc(ctr, r * k, 0.0, TAU, 40, TYRE, 3.0)
	_note(ctr + Vector2(0.0, -r * k), "side")
	_note(ctr + Vector2(0.0, r * k), "side")
	var L: Vector3 = po["L"]
	var lo_mid: Vector3 = ((cn["lf"] as Vector3) + (cn["lr"] as Vector3)) * 0.5
	draw_line(_sp(lo_mid), _sp(L), ARM, 2.0)
	draw_line(_sp(L), _sp(W), ARM, 1.5)
	var T2: Vector3 = po["T"]
	var t := -L.z / (T2.z - L.z)
	var G2 := L + (T2 - L) * t
	_dashed(_sp(G2), _sp(T2), AXIS)
	draw_line(_sp(L), _sp(T2), STRUT, 3.0)
	draw_line(Vector2(_sp(G2).x, base), Vector2(_sp(G2).x, base - 6.0), AXIS, 1.0)
	var cap := "caster %s deg" % str(snappedf(float(ro["caster"]), 0.1))
	var cp: Vector2 = _sp(T2)
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
