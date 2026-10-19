## balance.gd - the centre of mass and what holds it up (round 16, GATES W3, UPGRADES #63).
## COM: each body part's share of the mass (de Leva 1996, adjusting Zatsiorsky-Seluyanov; male, % of body mass) at the
## middle of its capsule. Head 6.94 (with the neck), trunk 43.46 split as lower (pelvis) 11.17 / middle (spine_01,
## spine_02) 16.33 / upper (spine_03) 15.96, upper arm 2.71, forearm 1.62, hand 0.61, thigh 14.16, shank 4.33, foot
## 1.37: 100 in all. (de Leva puts each part's COM at a measured fraction along it; the middle is this model's
## simplification, stated.)
## SUPPORT: the foot capsules' shadow where they are on the floor: along each axis, where the capsule's underside is
## within TOUCH of the floor (y - r < TOUCH), a disc of the capsule's radius around that point (on x, z). The polygon
## is the convex hull of those discs. A raised heel drops out, so standing on the toes shrinks it. (A first version
## used the sphere's true circle on the floor, sqrt(r^2 - y^2): the mannequin's ankle end never touches, so it had
## no heel and the rest pose sat 8 mm from the back edge. The shadow is wider than a real foot: lenient, stated.)
## margin(): the COM's floor point to the polygon's edge, m: + inside, - outside (how far past the feet he leans).
class_name Balance
extends RefCounted

const MASS := {"head": 6.94, "pelvis": 11.17, "spine_01": 8.165, "spine_02": 8.165, "spine_03": 15.96,
	"upperarm_l": 2.71, "lowerarm_l": 1.62, "hand_l": 0.61, "upperarm_r": 2.71, "lowerarm_r": 1.62, "hand_r": 0.61,
	"thigh_l": 14.16, "calf_l": 4.33, "foot_l": 1.37, "thigh_r": 14.16, "calf_r": 4.33, "foot_r": 1.37}
const FEET := {"_l": ["foot_l", "ball_l"], "_r": ["foot_r", "ball_r"]}
const TOUCH := 0.01   # m: a capsule this close to the floor counts as on it (the floor is y = 0)
const RING := 12      # points around each footprint circle
## the polygon's resolution: a margin smaller than this is inside what the model can tell. A foot counts as down within TOUCH (1 cm)
## of the floor, so the heel/toe edge is uncertain by that much, and a 12-gon on a 6 cm capsule is 2 mm inside its circle;
## 2 cm is also BalanceView's amber band. A lean past the feet by less than this is not a finding (human_limits TIPPING)
const MARGIN_RES := 0.02


static func com(B: Body) -> Vector3:
	if not B.body.is_empty():
		return Proportions.com(B)   # PR2: a body with proportions: de Leva's table for its sex, scaled (proportions.gd)
	var s := Vector3.ZERO
	var w := 0.0
	for j in MASS:
		var c: Array = B.cap(j)
		s += ((c[0] as Vector3) + c[1]) * 0.5 * MASS[j]
		w += MASS[j]
	return s / w


## the floor points of one foot ("_l" / "_r"); empty = that foot is off the floor
static func footprint(B: Body, side: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for part in FEET[side]:
		var c: Array = B.cap(part)
		var r: float = B.rad[part]
		for k in 9:
			var p: Vector3 = (c[0] as Vector3).lerp(c[1], k / 8.0)
			if p.y - r - (0.0 if B.props.is_empty() else B.surface_at(p, r)) > TOUCH:   # TT2: the top it stands on
				continue
			var rf := r
			for a in RING:
				var th := TAU * a / RING
				out.append(Vector2(p.x + rf * cos(th), p.z + rf * sin(th)))
	return out


## convex hull, counter-clockwise (Andrew's monotone chain)
static func hull(pts: PackedVector2Array) -> PackedVector2Array:
	var p := Array(pts)
	p.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	if p.size() < 3:
		return PackedVector2Array(p)
	var lo := []
	for q in p:
		while lo.size() >= 2 and (lo[-1] - lo[-2]).cross(q - lo[-2]) <= 0.0:
			lo.pop_back()
		lo.append(q)
	var up := []
	for i in range(p.size() - 1, -1, -1):
		var q: Vector2 = p[i]
		while up.size() >= 2 and (up[-1] - up[-2]).cross(q - up[-2]) <= 0.0:
			up.pop_back()
		up.append(q)
	lo.pop_back()
	up.pop_back()
	return PackedVector2Array(lo + up)


## signed distance from q to a convex ccw polygon's edge: + inside, - outside
static func signed_dist(poly: PackedVector2Array, q: Vector2) -> float:
	if poly.size() == 0:
		return -INF
	if poly.size() < 3:
		var d := INF
		for v in poly:
			d = minf(d, q.distance_to(v))
		return -d
	var inside := true
	var d := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if (b - a).cross(q - a) < 0.0:
			inside = false
		d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return d if inside else -d


## {"com": Vector3, "margin": m (+ inside), "down": ["_l", "_r"] the feet on the floor, "poly": the support polygon}
static func read(B: Body) -> Dictionary:
	var c := com(B)
	var pts := PackedVector2Array()
	var down := []
	for side in ["_l", "_r"]:
		var f := footprint(B, side)
		if f.size() > 0:
			down.append(side)
			pts.append_array(f)
	var poly := hull(pts)
	return {"com": c, "margin": signed_dist(poly, Vector2(c.x, c.z)), "down": down, "poly": poly}
