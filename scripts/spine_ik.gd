## spine_ik.gd - SPLINE IK FOR THE BACK (ROADMAP 61). Ideas from how Blender's Spline IK constraint and Rigify's spine
## work (a curve drives a bone chain, the chain's bones keep their length, twist is spread along the chain: docs/research/
## BLENDER_IK.md, section on long chains); nothing here is Blender code.
##
## THREE CONTROLS draw a curve: HIP (the base of the lumbar spine, spine_01's joint, which rides with the pelvis), MID
## (a world point for the mid back) and CHEST (a world point for the base of the neck). The curve is a Catmull-Rom spline
## through hip, mid, chest (two cubic Hermite pieces, tangent at mid = (chest - hip) / 2, one-sided at the ends), continued
## past the chest in a straight line along its end tangent, so a chain longer than the curve still lies ON it.
##
## THE SOLVE (solve()): the chain is spine_01 -> spine_02 -> spine_03 -> neck_01 (three bones, their rest lengths). The joints
## are placed ON the curve by ARC LENGTH, marching from the hip: the next joint is the first point of the curve that is
## exactly one bone length (straight line) from the last, found on the analytic curve (step then bisection). So every bone
## keeps its rest length, and every joint lies on the curve. Each bone is then TURNED to point along its chord with the
## smallest swing (parallel transport of the pelvis frame down the chain: no twist is made by the bend), and the TWIST is
## laid on top: about the bone, tw_j = hip_twist + (chest_twist - hip_twist) * f_j, f_j = the bone's FAR end along the chain
## (cumulative bone length / chain length), so the twist grows linearly from the hip control to the chest control and the
## chest vertebra carries all of the chest twist. Every joint's angles go through Body.decompose and Body.clamp_ang (the
## body's own limits): a clamp can leave a joint off the curve, and solve() REPORTS it (clamped joints, miss), never hides it.
##
## THE REAL SPINE FOR SCALE: this body's three vertebral joints bend -7..20 each (total flexion 60, extension 21), side +-7
## (21 total), twist +-17 (51 total). People, lumbar spine alone, goniometer, 300 young adults (Apti et al. 2023): flexion
## 69.9, extension 40.0, lateral bend 36, rotation 38 deg; the thoracic spine adds more flexion on top (White & Panjabi 1990,
## Clinical Biomechanics of the Spine: thoracic flexion-extension 4 deg a level in the upper levels up to ~12 at T11-12, order of
## 40-50 deg in all). So spline mode, whose every joint is clamped, can never ask for more than 60 deg of forward bend over
## the three joints, below the lumbar mean alone (tests/spine_ik_test.gd prints and bars this).
##
## KEYS (Scene.ik["spine"]): [{"t", "target": chest point, "pole": mid point, "w": 0..1, "twist": [hip, chest] deg}] sorted by
## time, the LimbIK pattern (put / weight_at / sample / to_file / from_file / mirror_file), so keying, undo, mirror, save and
## load work as for a limb. Chest and mid follow PartKeys' monotone curve between keys, the twists and the weight are linear.
## Played by LimbIK.play BEFORE the limbs (a pinned hand stays pinned over a moving chest). w < 1: the joint angles mix
## from the FK angles to the IK angles by w. Weight 0 or no key leaves the body untouched, byte for byte.
class_name SpineIK
extends RefCounted

const KEY := "spine"
const JOINTS := ["spine_01", "spine_02", "spine_03"]   # the joints that turn; the chain's end is the base of the neck
const END := "neck_01"
const U_STEP := 0.005     # marching step along the curve (curve parameter, 0..2 over the two pieces)
const PARTS := ["spine_01", "spine_02", "spine_03"]   # the picked parts that mean the back


static func is_spine_part(part: String) -> bool:
	return part in PARTS


# ---------------------------------------------------------------------------------------------------- the curve

static func _herm(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3, s: float) -> Vector3:
	var s2 := s * s
	var s3 := s2 * s
	return p0 * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) + p1 * (-2.0 * s3 + 3.0 * s2) + m1 * (s3 - s2)


## the curve through hip h, mid m, chest c at parameter u: 0..1 hip to mid, 1..2 mid to chest, past 2 a straight
## continuation along the end tangent (c - m per unit of u: the curve stays C1 there)
static func point(h: Vector3, m: Vector3, c: Vector3, u: float) -> Vector3:
	if u <= 1.0:
		return _herm(h, m - h, m, (c - h) * 0.5, maxf(u, 0.0))
	if u <= 2.0:
		return _herm(m, (c - h) * 0.5, c, c - m, u - 1.0)
	return c + (c - m) * (u - 2.0)


## the curve as a polyline for drawing: n points from the hip to u_end
static func polyline(h: Vector3, m: Vector3, c: Vector3, u_end := 2.0, n := 48) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		out.append(point(h, m, c, u_end * float(i) / n))
	return out


## the bones' rest lengths and rest directions: [[length, rest direction], ...] for spine_01, 02, 03
static func bones(B: Body) -> Array:
	var out := []
	var names: Array = JOINTS + [END]
	for i in 3:
		var d: Vector3 = B.p0[names[i + 1]] - B.p0[names[i]]
		out.append([d.length(), d.normalized()])
	return out


## the joints placed on the curve: [Q0 = hip, Q1, Q2, Q3] with |Q(i+1) - Q(i)| = bone i's length to 1e-6 m and every Q on the
## curve; also "us" (their parameters) and "short" (the chain is longer than the curve: the last joints are on its
## straight continuation past the chest)
static func march(h: Vector3, m: Vector3, c: Vector3, lens: Array) -> Dictionary:
	var pts := [h]
	var us := [0.0]
	var short := false
	var u := 0.0
	var span := maxf((c - m).length(), 1e-3)
	var total := 0.0
	for l in lens:
		total += float(l)
	var u_max := 2.0 + 2.0 * total / span
	for l in lens:
		var L: float = l
		var p: Vector3 = pts[-1]
		var lo := u
		var hi := u
		while hi < u_max:
			lo = hi
			hi = minf(hi + U_STEP, u_max)
			if (point(h, m, c, hi) - p).length() >= L:
				break
		if (point(h, m, c, hi) - p).length() < L:   # the curve (even its continuation) is too short: keep going straight
			hi = u_max
		for _i in 50:
			var mid := 0.5 * (lo + hi)
			if (point(h, m, c, mid) - p).length() < L:
				lo = mid
			else:
				hi = mid
		u = hi
		if u > 2.0 + 1e-9:
			short = true
		pts.append(point(h, m, c, u))
		us.append(u)
	return {"pts": pts, "us": us, "short": short}


## the distance from a point to the curve (u in 0 .. u_end), by a fine scan and a refinement
static func dist_to_curve(h: Vector3, m: Vector3, c: Vector3, p: Vector3, u_end := 4.0) -> float:
	var best := INF
	var bu := 0.0
	var n := 800
	for i in n + 1:
		var u := u_end * float(i) / n
		var d := (point(h, m, c, u) - p).length_squared()
		if d < best:
			best = d
			bu = u
	var step := u_end / n
	var lo := maxf(bu - step, 0.0)
	var hi := bu + step
	for _i in 40:
		var a := lo + (hi - lo) / 3.0
		var b := hi - (hi - lo) / 3.0
		if (point(h, m, c, a) - p).length_squared() < (point(h, m, c, b) - p).length_squared():
			hi = b
		else:
			lo = a
	return (point(h, m, c, 0.5 * (lo + hi)) - p).length()


# ---------------------------------------------------------------------------------------------------- the solve

## the far-end fractions of the three bones along the chain (cumulative length / chain length): the twist weights
static func fractions(B: Body) -> Array:
	var bs := bones(B)
	var total := 0.0
	for b in bs:
		total += float(b[0])
	var out := []
	var acc := 0.0
	for b in bs:
		acc += float(b[0])
		out.append(acc / total)
	return out


## the twist (deg) each bone carries about its own axis, read from the posed body, against the zero-twist frame (the
## pelvis frame carried down the chain by the smallest swings). Independent of how solve() set it
static func twists(B: Body) -> Array:
	var names: Array = JOINTS + [END]
	var bs := bones(B)
	var f: Quaternion = B.G["pelvis"]
	var prev_d: Vector3 = Vector3.ZERO
	var out := []
	for i in 3:
		var dir: Vector3 = ((B.P[names[i + 1]] - B.P[names[i]]) as Vector3).normalized()
		var d0: Vector3 = bs[i][1]
		f = Quaternion(f * d0, dir) * f
		var xf: Vector3 = f * Vector3.RIGHT
		var xg: Vector3 = (B.G[names[i]] as Quaternion) * Vector3.RIGHT
		xf = (xf - dir * xf.dot(dir)).normalized()
		xg = (xg - dir * xg.dot(dir)).normalized()
		out.append(rad_to_deg(atan2(dir.dot(xf.cross(xg)), xf.dot(xg))))
		prev_d = dir
	return out


## put the back on the curve through the body's hip, `m` and `c`, twist from `twh` (hip) to `twc` (chest) deg. Writes B.ang for
## spine_01..03 and runs B.fk(). Returns {"miss": the farthest a joint is from its place on the curve (m), "clamped": [joints a
## limit changed], "short": the chain is longer than the curve, "reach": the chest's distance from the chain's end (m)}
static func solve(B: Body, c: Vector3, m: Vector3, twh: float, twc: float) -> Dictionary:
	B.fk()
	var bs := bones(B)
	var lens := bs.map(func(b): return b[0])
	var h: Vector3 = B.P[JOINTS[0]]
	var mr := march(h, m, c, lens)
	var q: Array = mr["pts"]
	var fr := fractions(B)
	var f: Quaternion = B.G["pelvis"]
	var clamped := []
	for i in 3:
		var j: String = JOINTS[i]
		var dir: Vector3 = ((q[i + 1] as Vector3) - (q[i] as Vector3)).normalized()
		f = Quaternion(f * (bs[i][1] as Vector3), dir) * f
		var tw: float = lerpf(twh, twc, float(fr[i]))
		var gt := Quaternion(dir, deg_to_rad(tw)) * f
		var gp: Quaternion = B.G[B.parent[j]]
		var v := B.decompose(j, (gp.inverse() * gt).normalized())
		var old: Vector3 = B.ang[j]
		while v.z - old.z > 180.0:
			v.z -= 360.0
		while v.z - old.z < -180.0:
			v.z += 360.0
		var cv := B.clamp_ang(j, v)
		if (cv - v).length() > 1e-3:
			clamped.append(j)
		B.ang[j] = cv
		B.fk()
	var miss := 0.0
	for i in range(1, 4):
		miss = maxf(miss, ((B.P[(JOINTS + [END])[i]] as Vector3) - (q[i] as Vector3)).length())
	return {"miss": miss, "clamped": clamped, "short": mr["short"], "reach": ((B.P[END] as Vector3) - c).length()}


# ---------------------------------------------------------------------------------------------------- keys

## the keys at time t: {"target" (chest), "pole" (mid), "w", "twist": Vector2(hip, chest)}
static func sample(keys: Array, t: float) -> Dictionary:
	var out := LimbIK.sample(keys, t)
	var a = null
	var b = null
	for k in keys:
		if float(k["t"]) <= t:
			a = k
		elif b == null:
			b = k
	var ta := _tw(a) if a != null else (_tw(b) if b != null else Vector2.ZERO)
	if a != null and b != null:
		var u := clampf((t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 1e-9), 0.0, 1.0)
		out["twist"] = ta.lerp(_tw(b), u)
	else:
		out["twist"] = ta
	return out


static func _tw(k: Dictionary) -> Vector2:
	var t = k.get("twist", [0.0, 0.0])
	return Vector2(float(t[0]), float(t[1])) if t is Array else (t as Vector2)


## the angles of the back's joints as the body holds them
static func angles(B: Body) -> Dictionary:
	var d := {}
	for j in JOINTS:
		d[j] = B.ang[j]
	return d


## the scene as it plays at t with the spine IK off (the cards' back), posed on B
static func _fk_at(S: Scene, B: Body, t: float) -> void:
	var keep = S.ik.get(KEY, null)
	S.ik.erase(KEY)
	S.apply(B, t)
	if keep != null:
		S.ik[KEY] = keep


## solve onto a key's controls, mixed with `fk` (the joint angles with the IK off) by the weight w
static func pose(B: Body, k: Dictionary, fk = null) -> Dictionary:
	var tw: Vector2 = k["twist"]
	var r := solve(B, k["target"], k["pole"], tw.x, tw.y)
	var w := float(k["w"])
	if w < 1.0 and fk != null:
		for j in JOINTS:
			B.ang[j] = (fk[j] as Vector3).lerp(B.ang[j], w)
		B.fk()
		r["miss"] = ((B.P[END] as Vector3) - (k["target"] as Vector3)).length()
	return r


## THE IK PASS for the back (LimbIK.play calls it first). Returns solve()'s report + "w", or {} when it did not run
static func play(keys: Array, B: Body, t: float) -> Dictionary:
	if keys.is_empty():
		return {}
	var k := sample(keys, t)
	var w: float = k["w"]
	if w <= 0.0:
		return {}
	var was := angles(B)
	var r := pose(B, k, was)
	r["w"] = w
	return r


## controls that reproduce the back as it stands now: chest = the neck's base, mid = a point that makes the curve pass through the
## spine_02 / spine_03 joints (a few corrections of its first guess, the joint itself), twists read from the body
static func controls_from_pose(B: Body) -> Dictionary:
	B.fk()
	var was := angles(B)
	var c: Vector3 = B.P[END]
	var o2: Vector3 = B.P["spine_02"]
	var o3: Vector3 = B.P["spine_03"]
	var tws := twists(B)
	var fr := fractions(B)
	var slope := (float(tws[2]) - float(tws[0])) / maxf(float(fr[2]) - float(fr[0]), 1e-6)
	var twh: float = float(tws[0]) - slope * float(fr[0])
	var twc: float = float(tws[2])
	var m := o2
	var best := m
	var best_e := INF
	for _i in 8:
		solve(B, c, m, twh, twc)
		var e: Vector3 = (o2 - (B.P["spine_02"] as Vector3)) + (o3 - (B.P["spine_03"] as Vector3)) * 0.5
		var err := maxf(((o2 - (B.P["spine_02"] as Vector3))).length(), (o3 - (B.P["spine_03"] as Vector3)).length())
		if err < best_e:
			best_e = err
			best = m
		m += e
	for j in JOINTS:
		B.ang[j] = was[j]
	B.fk()
	return {"target": c, "pole": best, "twist": Vector2(twh, twc), "err": best_e}


## key the back at t (LimbIK.put replaces a key within SAME_T)
static func put(ik: Dictionary, key: Dictionary) -> int:
	var k := key.duplicate()
	if k.has("twist") and k["twist"] is Vector2:
		k["twist"] = [(k["twist"] as Vector2).x, (k["twist"] as Vector2).y]
	return LimbIK.put(ik, KEY, k)


## a key at t - 1 frame holding the old curve there, unless a key is already within that frame (a change at t happens over the
## last frame, not over the span from the key before)
static func _hold_before(S: Scene, t: float, fallback: Dictionary) -> bool:
	var dt := 1.0 / maxf(S.fps, 1.0)
	if t - dt < -1e-9:
		return false
	var ks: Array = S.ik.get(KEY, [])
	for k in ks:
		if float(k["t"]) > t - dt - LimbIK.SAME_T and float(k["t"]) < t - LimbIK.SAME_T:
			return false
	var key := fallback.duplicate()
	key["t"] = t - dt
	key["w"] = 0.0
	if not ks.is_empty():
		var s := sample(ks, t - dt)
		key["target"] = s["target"]
		key["pole"] = s["pole"]
		key["w"] = s["w"]
		key["twist"] = s["twist"]
	put(S.ik, key)
	return true


## PIN (the back as it is on B now, spline mode on): keyed at t with weight 1. At t the spline reproduces the pose to within
## "err" metres (the curve is three controls, the pose has four joints); afterwards the chest and mid point stay in the world
static func pin(S: Scene, B: Body, t: float) -> Dictionary:
	var cp := controls_from_pose(B)
	var key := {"t": t, "target": cp["target"], "pole": cp["pole"], "w": 1.0, "twist": cp["twist"]}
	var pre := _hold_before(S, t, key)
	put(S.ik, key)
	return {"target": cp["target"], "pole": cp["pole"], "err": cp["err"], "pre": pre}


## OFF at t: weight 0 keyed at t (after a key one frame earlier that holds the spline as it was). The back goes back to the
## cards over that frame. Needs a key. Returns {"ok", "pre"}
static func off(S: Scene, t: float) -> Dictionary:
	var ks: Array = S.ik.get(KEY, [])
	if ks.is_empty() or LimbIK.weight_at(ks, t) <= 0.0:
		return {"ok": false, "pre": false}
	var s := sample(ks, t)
	var key := {"t": t, "target": s["target"], "pole": s["pole"], "w": 0.0, "twist": s["twist"]}
	var pre := _hold_before(S, t, key)
	put(S.ik, key)
	return {"ok": true, "pre": pre}
