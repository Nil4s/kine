class_name CarPlan
extends Control
## VEHICLE PACKAGE: the engineering layout, drawn from the hard points (CarPackage): a side view (ground line, both wheels at their axles,
## the body's outline, the floor, the package box, the seated fighter at the H-point with the seat back angle, the head room) and a top view
## (the body, the four tyres at the tracks). Dimensions are drawn as engineering dimension lines with arrowheads, OUTSIDE the outline; each
## label is placed by a checker: it goes where it fits (inside its panel, clear of the outline, the dimension lines and the other labels),
## trying the sides in order. Labels are kept in labels (for the tests); the outline polylines and the body polygons are kept too.
## Draws only; the numbers are CarPackage.derive's. Set p (the hard points) and call queue_redraw.
## One scale (px per mm) for both views, the largest that fits the panel: the side and top views share the nose x, and the two
## panels split the height in proportion to what each needs (so both fill it). See layout().

const LINE := Color(0.75, 0.85, 0.95)
const DIM := Color(1.0, 0.79, 0.2)
const FIGURE := Color(0.95, 0.75, 0.55)
const GROUND := Color(0.5, 0.75, 1.0)
const M := 46.0           # px margin inside each view (sideways)
const GAP := 6.0          # px between a dimension line and its label
const LM := 200.0         # px left of the nose in both views (the H-point, head room and clearance labels sit there)
const RM := 220.0         # px right of the tail in both views (the height and width dimensions and their labels)
const TITLE_SZ := 14
const LABEL_SZ := 12
var p := {}
var d := {}
var side_r := Rect2()     # the side view's rectangle (px), for the tests
var top_r := Rect2()
var labels := []          # the placed labels: {rect (px, the plan's), panel (0 side, 1 top), text, fits}
var outline := [[], []]   # per panel: polylines the labels keep off (the body edges, wheels, box, floor, fighter, dimension lines)
var mm_px := 0.0          # the one scale of both views (px per mm), for the tests
var solids := [[], []]    # per panel: closed body polygons a dimension label keeps out of (the labels in the body: annotations only)
var ch := {}              # the chassis record (carchassis): its members are drawn over both views when set
const CH_WORD := {"sills": "sills", "rails": "rails", "cross": "crossmembers"}


func set_points(hp: Dictionary) -> void:
	p = hp.duplicate()
	d = CarPackage.derive(p)
	queue_redraw()


## the chassis to draw over the package ({} = none: the package layout alone)
func set_chassis(c: Dictionary) -> void:
	ch = c.duplicate(true)
	queue_redraw()


## true when the segment a-b touches the rectangle r (an end inside, or a crossing of an edge)
static func seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false


## true when the polyline (open, or closed by its own last point) touches the rectangle
static func line_hits(r: Rect2, poly: PackedVector2Array) -> bool:
	for i in range(poly.size() - 1):
		if seg_hits_rect(poly[i], poly[i + 1], r):
			return true
	return false


## true when the rectangle touches or lies in a closed polygon (its edges or any corner inside)
static func solid_hits(r: Rect2, poly: PackedVector2Array) -> bool:
	if line_hits(r, poly):
		return true
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		if Geometry2D.is_point_in_polygon(c, poly):
			return true
	return false


## the layout of both views in a w x h box: the shared px per mm s (the largest that fits the width and the two heights) and the two
## panel rectangles (the side view's panel and the top view's, stacked, 4 px apart, filling h)
static func layout(d: Dictionary, w: float, h: float) -> Dictionary:
	var L := float(d["length"])
	var H := float(d["height"])
	var W := float(d["width"])
	var avail := h - 4.0
	var s := maxf(minf((w - LM - RM) / L, (avail - 188.0) / (H + W)), 0.001)
	var hs := H * s + 92.0    # 52 px above the roof, 40 px under the ground line
	var ts := W * s + 96.0    # 48 px above and below the body
	var side_r := Rect2(0.0, 0.0, w, avail * hs / (hs + ts))
	var top_r := Rect2(0.0, side_r.end.y + 4.0, w, avail * ts / (hs + ts))
	return {"s": s, "side_r": side_r, "top_r": top_r, "x0": LM, "side_len": L * s, "top_len": L * s}


func _panel(pi: int) -> Rect2:
	return side_r if pi == 0 else top_r


func _fits(pi: int, r: Rect2, inside: bool) -> bool:
	if not _panel(pi).grow(-2.0).encloses(r):
		return false
	for l in labels:
		if int(l["panel"]) == pi and (l["rect"] as Rect2).grow(2.0).intersects(r):
			return false
	for pl in outline[pi]:
		if line_hits(r, pl):
			return false
	if not inside:
		for so in solids[pi]:
			if solid_hits(r, so):
				return false
	return true


func _put(pi: int, t: String, r: Rect2, sz: int, col: Color, fits: bool) -> void:
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(r.position.x, r.position.y + f.get_ascent(sz)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	labels.append({"rect": r, "panel": pi, "text": t, "fits": fits})


## one label next to the anchor a: the first of the sides in order that fits; the anchor is the dimension line's midpoint or a point
func _label(pi: int, t: String, a: Vector2, sz: int, col: Color, order: Array, inside := false) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var h := f.get_height(sz)
	var found := false
	var r := Rect2(a.x - w * 0.5, a.y - h * 0.5, w, h)
	for o in order:
		# the side first, then the same side slid along it (up or down / sideways) when the first spot is taken
		var shifts := [0.0, -12.0, 12.0, -24.0, 24.0]
		for sh in shifts:
			var c := Rect2()
			match o:
				"above":
					c = Rect2(a.x - w * 0.5 + sh, a.y - GAP - h, w, h)
				"below":
					c = Rect2(a.x - w * 0.5 + sh, a.y + GAP, w, h)
				"left":
					c = Rect2(a.x - GAP - w, a.y - h * 0.5 + sh, w, h)
				"right":
					c = Rect2(a.x + GAP, a.y - h * 0.5 + sh, w, h)
			if _fits(pi, c, inside):
				r = c
				found = true
				break
		if found:
			break
	_put(pi, t, r, sz, col, found)


## a dimension line from a to b with arrowheads at both ends, its label beside it (outside the outline)
func _dim(pi: int, a: Vector2, b: Vector2, t: String, order: Array, at := 0.5) -> void:
	draw_line(a, b, DIM, 1.0)
	var u := (b - a).normalized()
	var n := Vector2(-u.y, u.x) * 3.5
	draw_colored_polygon(PackedVector2Array([a, a + u * 8.0 + n, a + u * 8.0 - n]), DIM)
	draw_colored_polygon(PackedVector2Array([b, b - u * 8.0 + n, b - u * 8.0 - n]), DIM)
	outline[pi].append(PackedVector2Array([a, b]))
	_label(pi, t, a.lerp(b, at), LABEL_SZ, DIM, order)


func _ring(c: Vector2, rad: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 25:
		out.append(c + Vector2(cos(TAU * i / 24.0), sin(TAU * i / 24.0)) * rad)
	return out


func _draw() -> void:
	if p.is_empty():
		return
	labels = []
	outline = [[], []]
	solids = [[], []]
	var lay := layout(d, size.x, size.y)
	side_r = lay["side_r"]
	top_r = lay["top_r"]
	mm_px = float(lay["s"])
	draw_rect(side_r, Color(0.09, 0.1, 0.13), true)
	draw_rect(top_r, Color(0.09, 0.1, 0.13), true)
	_side(0, side_r, mm_px)
	_top(1, top_r, mm_px)
	if not ch.is_empty():
		_chassis()


## the chassis members (carchassis) over both views: each group its own colour, the sizes labelled once per group (the left sill, the
## front rail, the first crossmember). Same scale and origins as _side and _top
func _chassis() -> void:
	var sx0 := side_r.position.x + LM
	var sy0 := side_r.position.y + side_r.size.y - 40.0
	var tx0 := top_r.position.x + LM
	var tcy := top_r.position.y + top_r.size.y * 0.5
	var done := {}
	for m in CarChassis.members(p, ch):
		var lo: Vector3 = m["lo"]
		var hi: Vector3 = m["hi"]
		var g := String(m["group"])
		var col: Color = CarChassis.GROUP_COL[g]
		var sr := _min_px(Rect2(sx0 + lo.z * mm_px, sy0 - hi.y * mm_px, (hi.z - lo.z) * mm_px, (hi.y - lo.y) * mm_px))
		var tr := _min_px(Rect2(tx0 + lo.z * mm_px, tcy + lo.x * mm_px, (hi.z - lo.z) * mm_px, (hi.x - lo.x) * mm_px))
		draw_rect(sr, Color(col.r, col.g, col.b, 0.55), true)
		draw_rect(sr, col, false, 1.0)
		draw_rect(tr, Color(col.r, col.g, col.b, 0.55), true)
		draw_rect(tr, col, false, 1.0)
		if not done.has(g):
			done[g] = true
			var word: String = CH_WORD[g]
			var t := "%s %d x %d x %s" % [word, int(m["w"]), int(m["h"]), str(snappedf(float(m["t"]), 0.1))]
			_label(1, t, tr.get_center(), LABEL_SZ, col, ["above", "below", "left", "right"], true)


static func _min_px(r: Rect2) -> Rect2:
	return Rect2(r.position, Vector2(maxf(r.size.x, 1.0), maxf(r.size.y, 1.0)))


func _side(pi: int, r: Rect2, s: float) -> void:
	var L := float(d["length"])
	var H := float(d["height"])
	var x0 := r.position.x + LM
	var y0 := r.position.y + r.size.y - 40.0          # the ground line: 40 px left under it for the bottom dimensions
	var X := func(mm: float) -> float:
		return x0 + mm * s
	var Y := func(mm: float) -> float:
		return y0 - mm * s
	var wb := float(p["wheelbase"])
	var foh := float(p["front_oh"])
	var roh := float(p["rear_oh"])
	var clr := float(p["clearance"])
	var rr := float(d["r"])
	var fl := clr + CarPackage.FLOOR
	var hg := float(d["hpt_ground"])
	# the ground line
	draw_line(Vector2(r.position.x + 6.0, y0), Vector2(r.end.x - 6.0, y0), GROUND, 2.0)
	outline[pi].append(PackedVector2Array([Vector2(r.position.x + 6.0, y0), Vector2(r.end.x - 6.0, y0)]))
	# the package box (dashed: length x height)
	var box := PackedVector2Array([Vector2(X.call(0.0), Y.call(0.0)), Vector2(X.call(L), Y.call(0.0)), Vector2(X.call(L), Y.call(H)), Vector2(X.call(0.0), Y.call(H)), Vector2(X.call(0.0), Y.call(0.0))])
	for i in 4:
		_dash(box[i], box[i + 1])
	outline[pi].append(box)
	# the body: nose, bonnet, windscreen, roof, tail (from the clearance up to the roof)
	var roof_y := H
	var body := PackedVector2Array([
		Vector2(X.call(0.0), Y.call(clr + 60.0)), Vector2(X.call(0.0), Y.call(clr)), Vector2(X.call(L), Y.call(clr)),
		Vector2(X.call(L), Y.call(clr + (H - clr) * 0.55)), Vector2(X.call(L - (L - foh - wb) * 0.2), Y.call(roof_y - 80.0)),
		Vector2(X.call(foh + wb * 0.42), Y.call(roof_y)), Vector2(X.call(foh + wb * 0.12), Y.call(clr + (H - clr) * 0.55)),
		Vector2(X.call(0.0), Y.call(clr + 130.0))])
	draw_polyline(body, LINE, 2.0)
	draw_line(body[body.size() - 1], body[0], LINE, 2.0)
	var closed := body.duplicate()
	closed.append(body[0])
	outline[pi].append(closed)
	solids[pi].append(closed)
	# the floor (the seat base sits on it: clearance + floor thickness)
	draw_line(Vector2(X.call(0.0), Y.call(fl)), Vector2(X.call(L), Y.call(fl)), Color(1, 1, 1, 0.25), 1.0)
	outline[pi].append(PackedVector2Array([Vector2(X.call(0.0), Y.call(fl)), Vector2(X.call(L), Y.call(fl))]))
	# the wheels on their axles
	for ax in [foh, foh + wb]:
		var ring := _ring(Vector2(X.call(ax), Y.call(rr)), rr * s)
		draw_arc(Vector2(X.call(ax), Y.call(rr)), rr * s, 0.0, TAU, 40, LINE, 2.0)
		draw_arc(Vector2(X.call(ax), Y.call(rr)), rr * s * 0.45, 0.0, TAU, 20, LINE, 1.0)
		outline[pi].append(ring)
	# the seated fighter: H-point, seat back, thigh, shin, head
	var hx := foh + float(p["hpt_x"])   # the H-point: back from the front axle (its side offset shows in the top view and the title)
	var a := deg_to_rad(float(p["seat_a"]))
	var back := Vector2(sin(a), cos(a))
	var hp := Vector2(X.call(hx), Y.call(hg))
	var hyy := hg - fl                   # the seat height above the floor
	var nk := Vector2(X.call(hx + back.x * CarPackage.TORSO), Y.call(hg + back.y * CarPackage.TORSO))
	var nk2 := Vector2(X.call(hx + back.x * (CarPackage.TORSO + CarPackage.NECK)), Y.call(hg + back.y * (CarPackage.TORSO + CarPackage.NECK)))
	var hc := Vector2(X.call(hx + back.x * (CarPackage.TORSO + CarPackage.NECK + CarPackage.HEAD * 0.5)), Y.call(hg + back.y * (CarPackage.TORSO + CarPackage.NECK + CarPackage.HEAD * 0.5)))
	var knee_mm := hx - CarPackage.THIGH
	var knee := Vector2(X.call(knee_mm), Y.call(hg))
	var dy := hyy - CarPackage.PEDAL_H
	var foot_mm := knee_mm - sqrt(maxf(0.0, pow(CarPackage.SHIN, 2.0) - pow(dy, 2.0)))
	var foot := Vector2(X.call(foot_mm), Y.call(fl + CarPackage.PEDAL_H))
	draw_line(hp, nk, FIGURE, 4.0)
	draw_line(nk, nk2, FIGURE, 2.0)
	draw_line(hp, knee, FIGURE, 4.0)
	draw_line(knee, foot, FIGURE, 3.0)
	draw_circle(hc, CarPackage.HEAD * 0.5 * s, FIGURE)
	draw_circle(hp, 3.0, DIM)
	outline[pi].append(PackedVector2Array([hp, nk, nk2]))
	outline[pi].append(PackedVector2Array([hp, knee, foot]))
	outline[pi].append(_ring(hc, CarPackage.HEAD * 0.5 * s))
	var la := Vector2(X.call(0.0) - 40.0, hp.y)   # the H-point's label: left of the nose, on a leader (the cabin has no free side)
	_label(pi, "H-point %d above ground" % int(hg), la, LABEL_SZ, DIM, ["left"], true)
	draw_line(hp, la, DIM, 1.0)
	outline[pi].append(PackedVector2Array([hp, la]))
	# head room: head top to the roof
	var head_top_y := hc.y - CarPackage.HEAD * 0.5 * s
	var hx_top := Vector2(hc.x, Y.call(roof_y))
	draw_line(Vector2(hc.x, head_top_y), hx_top, DIM, 1.0)
	outline[pi].append(PackedVector2Array([Vector2(hc.x, head_top_y), hx_top]))
	var hm := Vector2(hc.x, (head_top_y + hx_top.y) * 0.5)
	var lb := Vector2(X.call(0.0) - 40.0, hm.y)   # its label to the left of the nose too, on a leader
	_label(pi, "head room %d" % int(d["head"]), lb, LABEL_SZ, DIM, ["left"], true)
	draw_line(hm, lb, DIM, 1.0)
	outline[pi].append(PackedVector2Array([hm, lb]))
	# dimensions: length above the roof, height at the tail, clearance at the nose; nose, wheelbase and tail below the ground
	_dim(pi, Vector2(X.call(0.0), Y.call(roof_y) - 14.0), Vector2(X.call(L), Y.call(roof_y) - 14.0), "length %d" % int(d["length"]), ["above", "below"])
	_dim(pi, Vector2(X.call(L) + 22.0, Y.call(0.0)), Vector2(X.call(L) + 22.0, Y.call(H)), "height %d" % int(H), ["right", "left"])
	_dim(pi, Vector2(X.call(0.0) - 22.0, Y.call(clr)), Vector2(X.call(0.0) - 22.0, Y.call(0.0)), "clearance %d" % int(clr), ["left", "right"])
	var by := y0 + 12.0
	_dim(pi, Vector2(X.call(0.0), by), Vector2(X.call(foh), by), "nose %d" % int(foh), ["below"])
	_dim(pi, Vector2(X.call(foh), by), Vector2(X.call(foh + wb), by), "wheelbase %d" % int(wb), ["below"])
	_dim(pi, Vector2(X.call(foh + wb), by), Vector2(X.call(L), by), "tail %d" % int(roh), ["below"])
	_title(pi, r, "Side view (mm)")


func _dash(a: Vector2, b: Vector2) -> void:
	var n := int(a.distance_to(b) / 10.0)
	for i in range(0, n, 2):
		draw_line(a.lerp(b, float(i) / float(n)), a.lerp(b, minf(1.0, float(i + 1) / float(n))), Color(1, 1, 1, 0.3), 1.0)


func _title(pi: int, r: Rect2, t: String) -> void:
	var f := ThemeDB.fallback_font
	var rect := Rect2(r.position + Vector2(8.0, 4.0), f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SZ))
	rect.size.y = f.get_height(TITLE_SZ)
	_put(pi, t, rect, TITLE_SZ, LINE, _fits(pi, rect, false))


func _top(pi: int, r: Rect2, s: float) -> void:
	var L := float(d["length"])
	var W := float(d["width"])
	var cy := r.position.y + r.size.y * 0.5
	var x0 := r.position.x + LM
	var X := func(mm: float) -> float:
		return x0 + mm * s
	var Yc := func(mm: float) -> float:
		return cy + mm * s
	var body := PackedVector2Array([Vector2(X.call(0.0), Yc.call(-W * 0.5)), Vector2(X.call(L), Yc.call(-W * 0.5)),
		Vector2(X.call(L), Yc.call(W * 0.5)), Vector2(X.call(0.0), Yc.call(W * 0.5)), Vector2(X.call(0.0), Yc.call(-W * 0.5))])
	draw_polyline(body, LINE, 2.0)
	outline[pi].append(body)
	solids[pi].append(body)
	var foh := float(p["front_oh"])
	var wb := float(p["wheelbase"])
	var td := float(d["tyre_d"])
	var tw := float(d["tyre_w"])
	for ax in [foh, foh + wb]:
		for sd in [-1.0, 1.0]:
			var tr := float(p["track_f"]) if ax == foh else float(p["track_r"])
			var c: Vector2 = Vector2(X.call(ax), Yc.call(sd * tr * 0.5))
			var wr := Rect2(c - Vector2(td * 0.5 * s, tw * 0.5 * s), Vector2(td * s, tw * s))
			draw_rect(wr, LINE, true)
			outline[pi].append(PackedVector2Array([wr.position, Vector2(wr.end.x, wr.position.y), wr.end, Vector2(wr.position.x, wr.end.y), wr.position]))
	# the seated driver's footprint: 500 mm wide, centred on the H-point's side offset, from the heel-side knee to the back
	var hx := foh + float(p["hpt_x"])
	var hy := float(d["hip_y"])
	var reach := float(d["reach"])
	var fp := PackedVector2Array([Vector2(X.call(hx - reach), Yc.call(hy - CarPackage.SEAT_HALF)), Vector2(X.call(hx + 100.0), Yc.call(hy - CarPackage.SEAT_HALF)),
		Vector2(X.call(hx + 100.0), Yc.call(hy + CarPackage.SEAT_HALF)), Vector2(X.call(hx - reach), Yc.call(hy + CarPackage.SEAT_HALF)),
		Vector2(X.call(hx - reach), Yc.call(hy - CarPackage.SEAT_HALF))])
	draw_polyline(fp, FIGURE, 1.5)
	draw_circle(Vector2(X.call(hx), Yc.call(hy)), 3.0, DIM)
	outline[pi].append(fp)
	# dimensions: wheelbase above the body (between the axles), front track on the nose side, rear track on the tail side, width outside both
	var wy: float = Yc.call(-W * 0.5) - 12.0
	_dim(pi, Vector2(X.call(foh), wy), Vector2(X.call(foh + wb), wy), "wheelbase %d" % int(wb), ["above", "below"])
	var fx: float = X.call(0.0) - 14.0
	_dim(pi, Vector2(fx, Yc.call(-float(p["track_f"]) * 0.5)), Vector2(fx, Yc.call(float(p["track_f"]) * 0.5)), "front track %d" % int(p["track_f"]), ["left", "right"])
	var rx: float = X.call(L) + 14.0
	_dim(pi, Vector2(rx, Yc.call(-float(p["track_r"]) * 0.5)), Vector2(rx, Yc.call(float(p["track_r"]) * 0.5)), "rear track %d" % int(p["track_r"]), ["right", "left"])
	var wx: float = X.call(L) + 140.0
	_dim(pi, Vector2(wx, Yc.call(-W * 0.5)), Vector2(wx, Yc.call(W * 0.5)), "width %d" % int(W), ["right", "left"])
	_title(pi, r, "Top view (mm)")
	# the driver's side, in the panel's bottom-left corner (clear of the title and the dimensions)
	var side_word := "left" if float(d["hip_y"]) > 0.0 else "right"
	var note := "driver %d mm %s of centre" % [int(absf(float(d["hip_y"]))), side_word]
	var nr := Rect2(r.position + Vector2(8.0, r.size.y - 22.0), ThemeDB.fallback_font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SZ))
	nr.size.y = ThemeDB.fallback_font.get_height(LABEL_SZ)
	_put(pi, note, nr, LABEL_SZ, FIGURE, _fits(pi, nr, false))
