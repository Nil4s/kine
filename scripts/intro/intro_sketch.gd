## INTRO C, LINE OF ACTION (scripts/intro/intro.gd): where an animator starts. A pen (its nib a small gold diamond) sweeps
## one gesture curve, a "(" of a line of action, hops over and flicks down the stem stroke. Then the sketch is made
## exact: the curve snaps to two straight 45 deg lines (it bows a little further first, and the corner overshoots), 45 deg
## guides flash through the corner, the lines thicken into the stencil limbs and the ends are cut flat at the guides,
## the lower limb turns blue, and the nib lands on the corner and opens into the diamond.
## A stroke is a sampled centre line with a width per sample, drawn as quads; the limbs are two strokes that meet at the
## corner with butt ends, exactly as the brand's own SVG strokes them, so the finished frame is the mark itself.
class_name IntroSketch
extends RefCounted

const A := preload("res://scripts/intro/intro_art.gd")
const N := 40   # samples per half stroke

# the gesture (cubic Bezier) and where each point goes: the chevron's centre line, extended past the cut at y 12 / 52
const G := [Vector2(59, 1), Vector2(16, 7), Vector2(17, 57), Vector2(59, 63)]
const TOP := Vector2(57, 6)
const BOT := Vector2(57, 58)
const S_G := [Vector2(18, 7), Vector2(11, 22), Vector2(17, 40), Vector2(12, 56)]
const S_TOP := Vector2(14.5, 12)
const S_BOT := Vector2(14.5, 52)


func mark_at() -> float:
	return 1.98


static func bez(c: Array, s: float) -> Vector2:
	var m := 1.0 - s
	return c[0] * m * m * m + c[1] * 3.0 * m * m * s + c[2] * 3.0 * m * s * s + c[3] * s * s * s


## pen pressure: thin at both ends of a quick stroke
static func pressure(s: float) -> float:
	return 0.35 + 0.65 * pow(sin(PI * clampf(s, 0.0, 1.0)), 0.7)


func paint(ci: CanvasItem, t: float, L: Dictionary) -> void:
	var u: float = L["u"]
	var o: Vector2 = L["hero"]
	var draw1 := A.in_out_sine(A.k(t, 0.04, 0.5))
	var draw2 := A.in_out_sine(A.k(t, 0.58, 0.8))
	var snap := A.in_out_back(A.k(t, 0.84, 1.24), 1.5)
	var thick := A.out_back(A.k(t, 1.12, 1.48), 1.6)
	var cut := A.in_out_cubic(A.k(t, 1.3, 1.54))
	var blue := A.in_out_cubic(A.k(t, 1.18, 1.46))
	var clip := Rect2(-400, lerpf(-400, 12, cut), 900, lerpf(864, 40, cut))   # the cut tightens to y 12 .. 52
	# the 45 deg guides and the cut lines, faint, while it is being made exact
	var ga := 0.32 * A.out_cubic(A.k(t, 0.92, 1.1)) * (1.0 - A.in_out_cubic(A.k(t, 1.42, 1.7)))
	if ga > 0.0:
		_dashed(ci, o + (A.APEX + Vector2(-14, 14)) * u, o + (A.APEX + Vector2(32, -32)) * u, Color(A.BONE, ga), u)
		_dashed(ci, o + (A.APEX + Vector2(-14, -14)) * u, o + (A.APEX + Vector2(32, 32)) * u, Color(A.BONE, ga), u)
	var ca := 0.45 * A.out_cubic(A.k(t, 1.26, 1.36)) * (1.0 - A.in_out_cubic(A.k(t, 1.5, 1.72)))
	if ca > 0.0:
		for y in [12.0, 52.0]:
			_dashed(ci, o + Vector2(4, y) * u, o + Vector2(64, y) * u, Color(A.GOLD, ca), u)
	# the stem stroke
	if draw2 > 0.0:
		var c := []
		var w := []
		for i in N + 1:
			var s := float(i) / N * draw2
			c.append(bez(S_G, s).lerp(S_TOP.lerp(S_BOT, s), snap))
			w.append(lerpf(2.3 * pressure(s / maxf(draw2, 0.001) if draw2 < 1.0 else s), 9.0, thick))
		_stroke(ci, c, w, A.BONE, Rect2(-400, -400, 900, 900), o, u)
	# the chevron: the curve's two halves become the two limbs
	if draw1 > 0.0:
		for half in 2:
			var c := []
			var w := []
			for i in N + 1:
				var f := float(i) / N
				var s := (f * 0.5 if half == 0 else 0.5 + f * 0.5)
				if s > draw1:
					break
				var straight := (TOP.lerp(A.APEX, s / 0.5) if s <= 0.5 else A.APEX.lerp(BOT, (s - 0.5) / 0.5))
				c.append(bez(G, s).lerp(straight, snap))
				w.append(lerpf(2.3 * pressure(s / maxf(draw1, 0.001) if draw1 < 1.0 else s), 9.5, thick))
			if c.size() < 2:
				continue
			if half == 0:
				c.reverse()   # both limbs run out of the corner, as the SVG strokes them
				w.reverse()
			var col := A.BONE if half == 0 else A.BONE.lerp(A.BLUE, blue)
			_stroke(ci, c, w, col, clip, o, u)
	# the nib: draws, hops to the stem, flicks it, flies to the corner, opens into the diamond
	var nib := _nib(t)
	var hd := lerpf(2.0, 8.0, A.out_back(A.k(t, 1.5, 1.8), 2.8)) * A.out_back(A.k(t, 0.0, 0.14), 2.0)
	A.fill(ci, A.tx([nib + Vector2(0, -hd), nib + Vector2(hd, 0), nib + Vector2(0, hd), nib + Vector2(-hd, 0)], o, u), A.GOLD)


func _nib(t: float) -> Vector2:
	if t < 0.5:
		return bez(G, A.in_out_sine(A.k(t, 0.04, 0.5)))
	if t < 0.58:   # the hop: up and over to the stem's start
		var x := A.in_out_cubic(A.k(t, 0.5, 0.58))
		return bez(G, 1.0).lerp(S_G[0], x) + Vector2(0, -10.0 * sin(PI * x))
	if t < 0.84:
		return bez(S_G, A.in_out_sine(A.k(t, 0.58, 0.8)))
	# then to the corner, arriving with the snap
	var x := A.in_out_back(A.k(t, 0.9, 1.4), 1.2)
	return bez(S_G, 1.0).lerp(A.APEX, x) + Vector2(0, -12.0 * sin(PI * A.k(t, 0.9, 1.4)))


## a centre line with a width per point, as quads (butt ends), each clipped to `clip` (mark units)
func _stroke(ci: CanvasItem, c: Array, w: Array, col: Color, clip: Rect2, o: Vector2, u: float) -> void:
	var n := c.size()
	var left := []
	var right := []
	for i in n:
		var a: Vector2 = c[maxi(i - 1, 0)]
		var b: Vector2 = c[mini(i + 1, n - 1)]
		var d := (b - a)
		d = d.normalized() if d.length() > 1e-5 else Vector2.RIGHT
		var nn := Vector2(-d.y, d.x) * (w[i] as float) * 0.5
		left.append(c[i] + nn)
		right.append(c[i] - nn)
	var box := A.pts([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)])
	for i in n - 1:
		var q := A.pts([left[i], left[i + 1], right[i + 1], right[i]])
		for piece in Geometry2D.intersect_polygons(q, box):
			A.fill(ci, A.tx(Array(piece), o, u), col)


func _dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, u: float) -> void:
	var l := a.distance_to(b)
	var step := 2.2 * u
	var d := (b - a) / l
	var s := 0.0
	while s < l:
		ci.draw_line(a + d * s, a + d * minf(s + step * 0.55, l), col, maxf(1.0, u * 0.18), true)
		s += step
