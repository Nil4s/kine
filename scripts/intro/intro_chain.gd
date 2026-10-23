## INTRO B, JOINT CHAIN (scripts/intro/intro.gd): a two-bone leg (hip, knee, foot) grows down from its hip and hangs; it
## chambers slowly (anticipation), then strikes: the thigh drives the knee across with an overshoot and the blue shin
## whips out behind it (drag, then follow-through). Its onion trails freeze in place, then fold into the final pose as
## the bones snap into the chevron's flat-cut limbs; the spine grows up beside it into the stem, and the small gold
## centre of mass that rode the motion lands on the knee and opens into the diamond.
## Each bone carries a 6-point outline in its own frame (along, across), so the kite-shaped bone and the stencil limb
## are the same polygon in any pose: the morph is a blend of two local shapes.
class_name IntroChain
extends RefCounted

const A := preload("res://scripts/intro/intro_art.gd")
const HIP := Vector2(51, 12)
const L1 := 28.284271   # hip -> knee -> foot, both the chevron's centre line
const L2 := 28.284271
const FREEZE := 1.2
const GHOSTS := 9
const GHOST_DT := 0.028
const STEM_BASE := Vector2(14.5, 52)
const STEM_TIP := Vector2(14.5, 12)

var _fin := {}   # bone -> its final 6-point local outline


func mark_at() -> float:
	return 1.96


func _init() -> void:
	_fin["thigh"] = _local_of(A.UPPER, HIP, A.APEX)
	_fin["shin"] = _local_of(A.LOWER, A.APEX, Vector2(51, 52))
	_fin["stem"] = _local_of(A.STEM, STEM_BASE, STEM_TIP)


## a 4-point outline (mark units) seen from the bone a -> b: the 6 local points [root -, near -, tip -, tip +, near +, root +]
static func _local_of(poly: Array, a: Vector2, b: Vector2) -> Array:
	var ax := (b - a).normalized()
	var ay := Vector2(-ax.y, ax.x)
	var loc := []
	for v in poly:
		var d: Vector2 = v - a
		loc.append(Vector2(d.dot(ax), d.dot(ay)))
	loc.sort_custom(func(p, q): return p.x < q.x)
	var root := [loc[0], loc[1]]
	var tip := [loc[2], loc[3]]
	root.sort_custom(func(p, q): return p.y < q.y)
	tip.sort_custom(func(p, q): return p.y < q.y)
	return [root[0], root[0].lerp(tip[0], 0.2), tip[0], tip[1], root[1].lerp(tip[1], 0.2), root[1]]


static func _kite(l: float) -> Array:
	var w := 0.15 * l
	return [Vector2(0, -0.6), Vector2(0.2 * l, -w), Vector2(l, -0.4), Vector2(l, 0.4), Vector2(0.2 * l, w), Vector2(0, 0.6)]


## absolute bone angles (deg, y down: 90 = straight down) at time t
static func angles(t: float) -> Vector2:
	var hang := Vector2(93.0 + 3.0 * sin(t * 7.0) * (1.0 - A.k(t, 0.3, 0.5)), 97.0)
	var chamber := Vector2(36.0, 158.0)
	var fin := Vector2(135.0, 45.0)
	var c := A.in_out_sine(A.k(t, 0.46, 0.86))   # slow into the chamber
	var p := hang.lerp(chamber, c)
	var th := lerpf(p.x, fin.x, A.out_back(A.k(t, 0.86, 1.2), 1.9))   # the strike: fast, overshoots
	var sh := lerpf(p.y, fin.y, A.out_back(A.k(t, 0.93, 1.34), 2.6))   # the shin drags, then whips past
	return Vector2(th, sh)


static func joints(t: float) -> Array:
	var an := angles(t)
	var grow1 := A.out_back(A.k(t, 0.06, 0.34), 1.6)
	var grow2 := A.out_back(A.k(t, 0.18, 0.46), 1.6)
	var knee := HIP + Vector2.from_angle(deg_to_rad(an.x)) * L1 * grow1
	var foot := knee + Vector2.from_angle(deg_to_rad(an.y)) * L2 * grow2
	return [HIP, knee, foot]


static func _place(loc: Array, a: Vector2, b: Vector2) -> Array:
	var d := b - a
	var l := d.length()
	var ax := d / l if l > 1e-5 else Vector2.DOWN
	var ay := Vector2(-ax.y, ax.x)
	var out := []
	for p in loc:
		out.append(a + ax * p.x + ay * p.y)
	return out


static func _blend(a: Array, b: Array, x: float) -> Array:
	var out := []
	for i in a.size():
		out.append((a[i] as Vector2).lerp(b[i], x))
	return out


func paint(ci: CanvasItem, t: float, L: Dictionary) -> void:
	var u: float = L["u"]
	var o: Vector2 = L["hero"]
	var morph := A.in_out_cubic(A.k(t, 1.34, 1.66))
	var j: Array = joints(t)
	# the trails: onion ghosts of the last few instants, frozen at FREEZE, then folded into the final pose
	if t > 0.84:
		var fold := A.in_out_cubic(A.k(t, 1.28, 1.56))
		var now := minf(t, FREEZE)
		var flash := 1.0 + 0.8 * exp(-max(0.0, t - FREEZE) * 14.0) * (1.0 if t >= FREEZE else 0.0)
		var fin_j := joints(2.0)
		for g in range(GHOSTS, 0, -1):
			var tg := now - g * GHOST_DT
			if tg < 0.84:
				continue
			var gj: Array = joints(tg)
			for q in 3:
				gj[q] = (gj[q] as Vector2).lerp(fin_j[q], fold)
			var a := (1.0 - float(g) / (GHOSTS + 1)) * 0.38 * flash * (1.0 - fold)
			ci.draw_polyline(A.tx(gj, o, u), Color(A.BLUE, a), maxf(1.0, 0.55 * u), true)
		# the foot's arc: a tapering ribbon behind it
		var arc := []
		var t0 := maxf(0.86, now - 0.3)
		for s in 24:
			var ts := lerpf(t0, now, float(s) / 23.0)
			arc.append((joints(ts)[2] as Vector2).lerp(fin_j[2], fold))
		var aa := 0.5 * flash * (1.0 - fold)
		for s in range(1, arc.size()):
			var w := lerpf(0.2, 2.4, float(s) / arc.size()) * u * 0.5
			ci.draw_line(o + arc[s - 1] * u, o + arc[s] * u, Color(A.BLUE, aa * float(s) / arc.size()), w, true)
	# the spine grows up beside it and becomes the stem
	var sg := A.out_back(A.k(t, 1.1, 1.42), 1.8)
	if sg > 0.0:
		var tip := STEM_BASE.lerp(STEM_TIP, sg)
		var shape := _blend(_kite(40.0 * sg), _fin["stem"], morph)
		A.fill(ci, A.tx(_place(shape, STEM_BASE, tip), o, u), A.BONE)
		_dot(ci, o + STEM_BASE * u, u, 1.0 - morph)
	# the leg
	var kite1 := _kite((j[1] - j[0]).length())
	var kite2 := _kite((j[2] - j[1]).length())
	var th := _place(_blend(kite1, _fin["thigh"], morph), j[0], j[1])
	var sh := _place(_blend(kite2, _fin["shin"], morph), j[1], j[2])
	A.fill(ci, A.tx(th, o, u), A.BONE)
	A.fill(ci, A.tx(sh, o, u), A.BLUE)
	var dots_a := 1.0 - A.in_out_cubic(A.k(t, 1.3, 1.52))
	_dot(ci, o + j[0] * u, u, dots_a * A.out_back(A.k(t, 0.0, 0.2), 2.0))
	_dot(ci, o + j[2] * u, u, dots_a * A.out_back(A.k(t, 0.2, 0.42), 2.0))
	_dot(ci, o + j[1] * u, u, (1.0 - A.k(t, 1.5, 1.6)) * A.out_back(A.k(t, 0.08, 0.3), 2.0))
	# the centre of mass: rides the motion, flies to the knee, opens into the diamond
	var com: Vector2 = ((j[0] + j[1]) * 0.5 + (j[1] + j[2]) * 0.5) * 0.5
	var land := A.in_out_back(A.k(t, 1.3, 1.58), 1.2)
	var p: Vector2 = com.lerp(A.APEX, land) + Vector2(0, -7.0 * sin(PI * A.k(t, 1.3, 1.58)))
	var size := lerpf(2.2, 8.0, A.out_back(A.k(t, 1.52, 1.82), 2.8)) * A.out_back(A.k(t, 0.3, 0.5), 2.0)
	A.fill(ci, A.tx([p + Vector2(0, -size), p + Vector2(size, 0), p + Vector2(0, size), p + Vector2(-size, 0)], o, u), A.GOLD)


## a joint: a bone-white ring with the background inside
func _dot(ci: CanvasItem, c: Vector2, u: float, s: float) -> void:
	if s <= 0.01:
		return
	var r := 2.4 * u * s
	ci.draw_circle(c, r, A.BONE, true, -1.0, true)
	ci.draw_circle(c, r * 0.5, A.BG, true, -1.0, true)
