## throw.gd - THROWN PROPS (round 41, GATES WW8, UPGRADES_300 #308). A prop let go by a MOVING hand leaves with the
## hand's velocity and flies the ballistic parabola  p(t) = p0 + v0 t + g t^2 / 2  (g = (0, -9.81, 0)) until it meets a
## top or the floor under its CURRENT xz (the same support lookup the plain drop uses, evaluated along the path), then
## BOUNCES: the vertical speed is e times what it hit with, reversed; the horizontal velocity is kept (friction-free
## sliding). THE STOP RULE (ours): the first bounce whose rebound apex v'^2 / 2g is under REST_APEX = 2 cm does not
## happen; the prop stops dead at that contact point (it is at rest ON the top, y = the support's height). Bounce
## apexes are e^2 times the one before (v' = e v, apex ~ v^2). A throw is only for a moving hand: a still hand
## (v0 = 0) keeps round 39's straight fall with no bounce (scene.gd), so old scenes read exactly as before.
## RESTITUTION E = 0.3 is MINE (unverified): not a measured cardboard box or crate. Real values are a spread (a
## wooden crate on a concrete floor is a dull thud, roughly 0.2-0.5 by material and drop height); a prop may carry its
## own "e" in the set dictionary (read, not saved to the file).
## The path is built once as a list of parabola SEGMENTS ({t0, p, v}, t0 from the let-go): contact is found by
## stepping STEP = 1 ms along the parabola and solving the quadratic exactly inside the step that crossed the top.
class_name Throw
extends RefCounted

const G := 9.81
const E := 0.3             # restitution (mine; unverified, see above)
const REST_APEX := 0.02    # m: a rebound lower than this is not made; the prop stops
const STEP := 0.001
const MAX_BOUNCES := 40
const MAX_FLIGHT := 30.0   # s, one parabola


## the height of the highest top at or below y (+1 mm) that the point is over (0 = the floor)
static func land_under(floor_props: Array, pt: Vector3, y: float) -> float:
	var land := 0.0
	for q in floor_props:
		for sup in Props.supports(q):
			if Props._over(sup, pt) and float(sup["y"]) <= y + 0.001:
				land = maxf(land, float(sup["y"]))
	return land


## {"segs": [{"t0", "p", "v"}...], "rest": Vector3, "t_rest": s from the let-go, "bounces": n, "hits": [[t, vy_in]...]}
static func trajectory(p0: Vector3, v0: Vector3, floor_props: Array, e := E) -> Dictionary:
	var segs := []
	var hits := []
	var t0 := 0.0
	var p := p0
	var v := v0
	var n := 0
	while true:
		segs.append({"t0": t0, "p": p, "v": v})
		var s := 0.0
		var tc := -1.0
		var pc := p
		var vy_in := 0.0
		while s < MAX_FLIGHT:
			var s1 := s + STEP
			var q := at_seg(p, v, s1)
			var y_old := at_seg(p, v, s).y
			var L := land_under(floor_props, q, y_old)
			if q.y <= L:
				var disc := maxf(0.0, v.y * v.y + 2.0 * G * (p.y - L))
				var sg := clampf((v.y + sqrt(disc)) / G, s, s1)
				tc = sg
				pc = at_seg(p, v, sg)
				pc.y = L
				vy_in = v.y - G * sg
				break
			s = s1
		if tc < 0.0:   # never came down (cap): rests where it is
			return {"segs": segs, "rest": at_seg(p, v, MAX_FLIGHT), "t_rest": t0 + MAX_FLIGHT, "bounces": n, "hits": hits}
		hits.append([t0 + tc, vy_in])
		var vy_out := -e * vy_in
		n += 1
		if vy_out * vy_out / (2.0 * G) < REST_APEX or n > MAX_BOUNCES:
			return {"segs": segs, "rest": pc, "t_rest": t0 + tc, "bounces": n, "hits": hits}
		t0 += tc
		p = pc
		v = Vector3(v.x, vy_out, v.z)
	return {}


static func at_seg(p: Vector3, v: Vector3, s: float) -> Vector3:
	return Vector3(p.x + v.x * s, p.y + v.y * s - G * s * s / 2.0, p.z + v.z * s)


## where the prop is tau seconds after the let-go
static func pos_at(tr: Dictionary, tau: float) -> Vector3:
	if tau >= float(tr["t_rest"]):
		return tr["rest"]
	var segs: Array = tr["segs"]
	var k := segs.size() - 1
	while k > 0 and tau < float(segs[k]["t0"]):
		k -= 1
	var sg: Dictionary = segs[k]
	return at_seg(sg["p"], sg["v"], tau - float(sg["t0"]))
