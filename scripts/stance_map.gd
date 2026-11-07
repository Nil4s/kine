## stance_map.gd - N038 STANCE STRENGTH MAP. For each push direction, the impulse THIS stance takes before a step is needed.
## The capture point xi = x_com + v / omega0 (Hof, Gazendam & Sinke 2005, J Biomech 38:1; Recovery.read) leaves the support polygon (Balance.read: the hull of the
## feet on the floor) when v = omega0 * d, d = the distance from the COM floor point to the polygon edge along the push. So J = M omega0 d (N s),
## the speed it gives is J / M, and the "push force" is J over PUSH_T = 0.1 s (taste). Direction 0 = forward, 90 = his left (Recovery.DIRS). A COM already outside
## the feet (one raised leg) gives 0 there: any push needs a step. Same maths as PushLimits.balance_equiv, all the way round.
class_name StanceMap
extends RefCounted

const PUSH_T := 0.1
const STEP_DEG := 15.0


## distance (m) from q along unit d to the convex polygon edge; 0 when q is outside; -1 when there is no polygon
static func edge_dist(poly: PackedVector2Array, q: Vector2, d: Vector2) -> float:
	if poly.size() < 3:
		return -1.0
	if Balance.signed_dist(poly, q) < 0.0:
		return 0.0
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		var den := d.cross(e)
		if absf(den) < 1e-12:
			continue
		var u := (a - q).cross(e) / den   # along d
		var s := (a - q).cross(d) / den   # along the edge
		if u >= -1e-9 and s >= -1e-9 and s <= 1.0 + 1e-9:
			best = minf(best, u)
	return 0.0 if best == INF else best


static func compute(B: Body) -> Dictionary:
	var r := Balance.read(B)
	var down: Array = r["down"]
	if down.is_empty():
		return {"ok": false, "why": "no foot is on the floor: pick a pose card with the fighter standing"}
	var c: Vector3 = r["com"]
	var ay := 0.0
	for sd in down:
		ay += (B.P["foot" + String(sd)] as Vector3).y
	ay /= down.size()
	var w0 := sqrt(9.81 / maxf(c.y - ay, 0.3))
	var mass := HumanLimits.mass_of(B)
	var q := Vector2(c.x, c.z)
	var hd := Recovery.heading(B)
	var dirs := []
	var imp := []
	var edge := []
	var n := int(round(360.0 / STEP_DEG))
	for k in n:
		var dg := float(k) * STEP_DEG
		var h := hd + deg_to_rad(dg)
		var e := edge_dist(r["poly"], q, Vector2(sin(h), cos(h)))
		dirs.append(dg)
		edge.append(e)
		imp.append(mass * w0 * maxf(e, 0.0))
	var spd := imp.map(func(j): return float(j) / mass)
	var frc := imp.map(func(j): return float(j) / PUSH_T)
	return {"ok": true, "why": "", "dirs": dirs, "impulse": imp, "speed": spd, "force": frc, "edge": edge, "mass": mass, "w0": w0, "poly": r["poly"], "com": q,
		"heading": hd, "legs": down.size()}


## the impulse (N s) at a direction in degrees (exact on a multiple of STEP_DEG, else the lower neighbour: the cautious reading)
static func at(mp: Dictionary, deg: float) -> float:
	if not bool(mp.get("ok", false)):
		return 0.0
	var d := fposmod(deg, 360.0)
	var a := int(floor(d / STEP_DEG + 1e-6))
	var b := a if absf(d - float(a) * STEP_DEG) < 1e-3 else a + 1
	var imp: Array = mp["impulse"]
	return minf(float(imp[a % imp.size()]), float(imp[b % imp.size()]))


static func mean(mp: Dictionary) -> float:
	if not bool(mp.get("ok", false)):
		return 0.0
	var s := 0.0
	for v in mp["impulse"]:
		s += float(v)
	return s / (mp["impulse"] as Array).size()


static func lowest(mp: Dictionary) -> float:
	if not bool(mp.get("ok", false)):
		return 0.0
	var lo := INF
	for v in mp["impulse"]:
		lo = minf(lo, float(v))
	return lo


static func highest(mp: Dictionary) -> float:
	var hi := 0.0
	if bool(mp.get("ok", false)):
		for v in mp["impulse"]:
			hi = maxf(hi, float(v))
	return hi
