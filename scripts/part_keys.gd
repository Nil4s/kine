## part_keys.gd - PART KEYS (round 41, GATES WW1, UPGRADES #238 + #239; the data model DECIDED in UPGRADES_300 M).
##
## Cards stay the main key: a whole-body pose. On top of them a scene may hold PART KEYS, one joint at a time:
##   Scene.part_keys = {"<joint>": [{"t": seconds, "v": Vector3(bend, side, twist) degrees}, ...]}   sorted by t
## Where a joint has part keys, its angles at time t come from ITS keys, not from the card blend; every other joint
## (and the hips' offset, the weapon) is the card blend exactly as before. Scene.sample() applies this last, so the
## floor, the pins, the flights, Check and every export see it.
##
## THE CURVE, per angle: a cubic Hermite through the keys (as the SPLINE scene uses between cards, scene.gd).
##   - before the first key the angle IS the first key's value, after the last key the last key's (clamped);
##   - at the first and last key the speed is 0 (it eases out of and into the clamped ends: no kink there);
##   - at a key in between the speed is the weighted harmonic mean of the two secants (Fritsch-Butland / Brodlie, the
##     PCHIP rule: w1 = 2 h_right + h_left, w2 = h_right + 2 h_left), and 0 where the angle turns back.
##   That is Blender's AUTO-CLAMPED handle in effect: the curve is MONOTONE between every two keys, so it never
##   overshoots them (each angle stays between its two keys' values; the limits hold if the keys are legal).
## A key time with one key = that value for the whole scene. The hips' whole-body turn (pelvis twist) is NOT wrapped
## the short way here: a part key is the number typed, as a curve editor shows it.
## In the FILE: "part_keys": {"<joint>": [{"t": 0.42, "v": [bend, side, twist]}, ...]}, written only when there is one
## (a scene without it saves and plays byte for byte as before).
class_name PartKeys
extends RefCounted

const SAME_T := 0.001  # two keys closer than this (s) are the same key: keying there again replaces it (the file keeps 1 ms)


## the angles a joint's keys give at time t (keys: [{"t", "v": Vector3}] sorted by t, at least one)
static func at(keys: Array, t: float) -> Vector3:
	var n := keys.size()
	if t <= float(keys[0]["t"]) or n == 1:
		return keys[0]["v"]
	if t >= float(keys[n - 1]["t"]):
		return keys[n - 1]["v"]
	var i := 0
	while i < n - 2 and t >= float(keys[i + 1]["t"]):
		i += 1
	var t0: float = keys[i]["t"]
	var h: float = maxf(1e-6, float(keys[i + 1]["t"]) - t0)
	var a: Vector3 = keys[i]["v"]
	var b: Vector3 = keys[i + 1]["v"]
	var ma := _slope(keys, i)
	var mb := _slope(keys, i + 1)
	var s := clampf((t - t0) / h, 0.0, 1.0)
	var s2 := s * s
	var s3 := s2 * s
	return (2 * s3 - 3 * s2 + 1) * a + (s3 - 2 * s2 + s) * h * ma + (-2 * s3 + 3 * s2) * b + (s3 - s2) * h * mb


## the speed (deg/s) per angle at key k: 0 at the first and last key and where the angle turns back, else Brodlie's
## weighted harmonic mean of the two secants (never more than 3x the smaller: monotone, no overshoot)
static func _slope(keys: Array, k: int) -> Vector3:
	if k <= 0 or k >= keys.size() - 1:
		return Vector3.ZERO
	var hl: float = maxf(1e-6, float(keys[k]["t"]) - float(keys[k - 1]["t"]))
	var hr: float = maxf(1e-6, float(keys[k + 1]["t"]) - float(keys[k]["t"]))
	var y: Vector3 = keys[k]["v"]
	var dl: Vector3 = (y - (keys[k - 1]["v"] as Vector3)) / hl
	var dr: Vector3 = ((keys[k + 1]["v"] as Vector3) - y) / hr
	var w1 := 2.0 * hr + hl
	var w2 := hr + 2.0 * hl
	var m := Vector3.ZERO
	for c in 3:
		if dl[c] * dr[c] > 0.0:
			m[c] = (w1 + w2) / (w1 / dl[c] + w2 / dr[c])
	return m


## a sampled pose {"offset", "ang", "weapon"...} with the keyed joints' angles from their keys (a new dict; the input
## is not written into)
static func over(s: Dictionary, pk: Dictionary, t: float) -> Dictionary:
	var out := s.duplicate()
	var ang: Dictionary = (s["ang"] as Dictionary).duplicate()
	for j in pk:
		if not (pk[j] as Array).is_empty():
			ang[j] = at(pk[j], t)
	out["ang"] = ang
	return out


## key joint j at time t with angles v: a key already within SAME_T of t is replaced, else one is added in time order
static func put(pk: Dictionary, j: String, t: float, v: Vector3) -> void:
	var keys: Array = pk.get(j, [])
	for k in keys:
		if absf(float(k["t"]) - t) < SAME_T:
			k["v"] = v
			pk[j] = keys
			return
	var i := 0
	while i < keys.size() and float(keys[i]["t"]) < t:
		i += 1
	keys.insert(i, {"t": t, "v": v})
	pk[j] = keys


## the file's form: {"<joint>": [{"t", "v": [b, s, t]}]} (angles to 0.01 deg, times to 1 ms, as cards are written)
static func to_file(pk: Dictionary) -> Dictionary:
	var out := {}
	for j in pk:
		var ks := []
		for k in pk[j]:
			var v: Vector3 = k["v"]
			ks.append({"t": snappedf(float(k["t"]), 0.001), "v": [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]})
		if not ks.is_empty():
			out[j] = ks
	return out


## read the file's form back (unknown joints and malformed keys are dropped; sorted by t)
static func from_file(d: Variant) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		return out
	for j in d:
		if not String(j) in Body.ORDER or not d[j] is Array:
			continue
		var ks := []
		for k in d[j]:
			if k is Dictionary and k.has("t") and k.get("v") is Array and (k["v"] as Array).size() == 3:
				var a: Array = k["v"]
				ks.append({"t": float(k["t"]), "v": Vector3(float(a[0]), float(a[1]), float(a[2]))})
		ks.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
		if not ks.is_empty():
			out[String(j)] = ks
	return out


## MIRRORED (Scene.MIRROR_SCENE "part_keys"): each joint's keys go to its twin (hand_l -> hand_r; a middle joint is its
## own twin), each value reflected the way Body.mirror_pose reflects a card's angles: A' = M A M on the joint's twin,
## i.e. compose, (x, y, z, w) -> (x, -y, -z, w), decompose, clamp. Works on the file's form (M: any loaded Body)
static func mirror_file(d: Dictionary, M: Body) -> Dictionary:
	var out := {}
	for j in d:
		var o := Body.twin(String(j))
		var ks := []
		for k in d[j]:
			var a: Array = k["v"]
			var q := M.compose(String(j), Vector3(float(a[0]), float(a[1]), float(a[2])))
			var v := M.clamp_ang(o, M.decompose(o, Quaternion(q.x, -q.y, -q.z, q.w)))
			ks.append({"t": k["t"], "v": [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]})
		out[o] = ks
	return out
