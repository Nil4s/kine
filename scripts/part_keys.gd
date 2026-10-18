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
## KEY INTERPOLATION (round 42, GATES XX1, UPGRADES_300 #241 #242 #247; Blender's F-curve set). Every field is optional;
## a key without it is exactly round 41's key, so old files sample bit for bit as before:
##   "interp"  how the curve leaves THIS key toward the next: "bezier" (default) | "constant" (holds this value until the
##             next key's time, then steps) | "linear" (a straight line to the next key)
##   "handle"  this key's handle type for bezier: "auto_clamped" (default = the PCHIP curve above, never overshoots) |
##             "auto" (slope = the neighbours' central difference: smooth, MAY overshoot) | "vector" (each handle points at
##             the neighbouring key: a corner) | "aligned" / "free" (explicit "hin"/"hout" = [dt, d_bend, d_side, d_twist]
##             offsets from the key; aligned keeps the two on one slope per angle, free does not)
##   "inf"     on a joint's FIRST key: what the curve does outside its keys: "hold" (default) | "linear" (extrapolate the
##             end slope) | "cycle" (repeat, period = last key time - first key time) | "cycle_offset" (repeat, each lap
##             adds last - first value)
## Segment i uses key i's "interp", key i's out handle and key i+1's in handle. The set is Blender's (Graph Editor F-curve
## interpolation, handle types, extrapolation; names from memory, the manual pages could not be read: unverified).
## In the FILE: "part_keys": {"<joint>": [{"t": 0.42, "v": [bend, side, twist]}, ...]}, written only when there is one
## (a scene without it saves and plays byte for byte as before).
class_name PartKeys
extends RefCounted

const SAME_T := 0.001  # two keys closer than this (s) are the same key: keying there again replaces it (the file keeps 1 ms)
const INTERPS := ["bezier", "constant", "linear"]   # KEY INTERPOLATION (round 42, XX1): see the header
const HANDLES := ["auto_clamped", "auto", "vector", "aligned", "free"]
const INFS := ["hold", "linear", "cycle", "cycle_offset"]


## the angles a joint's keys give at time t (keys: [{"t", "v": Vector3}] sorted by t, at least one)
static func at(keys: Array, t: float) -> Vector3:
	var n := keys.size()
	if n == 1:
		return keys[0]["v"]
	var mode := inf_of(keys)
	if t <= float(keys[0]["t"]):
		if mode == "hold" or t == float(keys[0]["t"]):
			return keys[0]["v"]
		return _outside(keys, t, mode)
	if t >= float(keys[n - 1]["t"]):
		if mode == "hold" or t == float(keys[n - 1]["t"]):
			return keys[n - 1]["v"]
		return _outside(keys, t, mode)
	return _inside(keys, t, mode)


## t strictly inside the keys' span: the segment's own interpolation
static func _inside(keys: Array, t: float, mode: String) -> Vector3:
	var n := keys.size()
	var i := 0
	while i < n - 2 and t >= float(keys[i + 1]["t"]):
		i += 1
	var t0: float = keys[i]["t"]
	var h: float = maxf(1e-6, float(keys[i + 1]["t"]) - t0)
	var a: Vector3 = keys[i]["v"]
	var b: Vector3 = keys[i + 1]["v"]
	var s := clampf((t - t0) / h, 0.0, 1.0)
	var ip := interp_of(keys[i])
	if ip == "constant":
		return a
	if ip == "linear":
		return a + (b - a) * s
	if mode == "hold" and handle_of(keys[i]) == "auto_clamped" and handle_of(keys[i + 1]) == "auto_clamped":
		# round 41's curve, the very same expression (old files sample bit for bit)
		var ma := _slope(keys, i)
		var mb := _slope(keys, i + 1)
		var s2 := s * s
		var s3 := s2 * s
		return (2 * s3 - 3 * s2 + 1) * a + (s3 - 2 * s2 + s) * h * ma + (-2 * s3 + 3 * s2) * b + (s3 - s2) * h * mb
	return _bezier(keys, i, t, mode)


## the cubic Bezier through key i and i+1 with their handles (Blender's: x(u) solved for t, then y(u))
static func _bezier(keys: Array, i: int, t: float, mode: String) -> Vector3:
	var t0: float = keys[i]["t"]
	var t1: float = keys[i + 1]["t"]
	var h: float = maxf(1e-6, t1 - t0)
	var a: Vector3 = keys[i]["v"]
	var b: Vector3 = keys[i + 1]["v"]
	var ho: Vector4 = _handles(keys, i, mode)[1]
	var hi: Vector4 = _handles(keys, i + 1, mode)[0]
	# handle lengths in time stay inside the segment (and shrink together when they would cross, as Blender does)
	var dto := clampf(ho.x, 0.0, h)
	var dti := clampf(-hi.x, 0.0, h)
	if dto + dti > h:
		var f := h / (dto + dti)
		dto *= f
		dti *= f
	var so := Vector3(ho.y, ho.z, ho.w) * (dto / ho.x if ho.x > 1e-9 else 0.0)
	var si := Vector3(hi.y, hi.z, hi.w) * (dti / -hi.x if hi.x < -1e-9 else 0.0)
	var x1 := t0 + dto
	var x2 := t1 - dti
	var lo := 0.0
	var hiu := 1.0
	var u := 0.5
	for _k in 60:
		u = 0.5 * (lo + hiu)
		var w := 1.0 - u
		var x := w * w * w * t0 + 3 * w * w * u * x1 + 3 * w * u * u * x2 + u * u * u * t1
		if x < t:
			lo = u
		else:
			hiu = u
	var w2 := 1.0 - u
	return w2 * w2 * w2 * a + 3 * w2 * w2 * u * (a + so) + 3 * w2 * u * u * (b + si) + u * u * u * b


## t outside the keys' span, mode is not hold
static func _outside(keys: Array, t: float, mode: String) -> Vector3:
	var n := keys.size()
	var tf: float = keys[0]["t"]
	var tl: float = keys[n - 1]["t"]
	var vf: Vector3 = keys[0]["v"]
	var vl: Vector3 = keys[n - 1]["v"]
	if mode == "linear":
		if t < tf:
			return vf + _end_slope(keys, 0) * (t - tf)
		return vl + _end_slope(keys, n - 1) * (t - tl)
	var period := tl - tf
	if period < 1e-6:
		return vf if t < tf else vl
	var lap := floorf((t - tf) / period)
	var u := clampf(tf + ((t - tf) - lap * period), tf, tl)
	var r := vl if u >= tl else (vf if u <= tf else _inside(keys, u, mode))
	if mode == "cycle_offset":
		r += lap * (vl - vf)
	return r


## the slope (deg/s per angle) the curve has leaving the span at the first (k = 0) or last key, for linear infinity
static func _end_slope(keys: Array, k: int) -> Vector3:
	var n := keys.size()
	var j := 0 if k == 0 else n - 2
	var ip := interp_of(keys[j])
	if ip == "constant":
		return Vector3.ZERO
	var sec: Vector3 = ((keys[j + 1]["v"] as Vector3) - (keys[j]["v"] as Vector3)) / maxf(1e-6, float(keys[j + 1]["t"]) - float(keys[j]["t"]))
	if ip == "linear":
		return sec
	var hd: Vector4 = _handles(keys, k, "linear")[0 if k == 0 else 1]
	if absf(hd.x) < 1e-9:
		return sec
	return Vector3(hd.y, hd.z, hd.w) / hd.x


## the key's neighbour in direction d (-1 / +1) as {"t","v"}; in the cycle modes the ends see the other end's neighbour a
## period away (so a cycle is smooth where it wraps); {} where there is none
static func _nb(keys: Array, k: int, d: int, mode: String) -> Dictionary:
	var n := keys.size()
	var j := k + d
	if j >= 0 and j < n:
		return {"t": float(keys[j]["t"]), "v": keys[j]["v"]}
	if (mode == "cycle" or mode == "cycle_offset") and n >= 2:
		var tf: float = keys[0]["t"]
		var tl: float = keys[n - 1]["t"]
		var per := tl - tf
		var dv := ((keys[n - 1]["v"] as Vector3) - (keys[0]["v"] as Vector3)) if mode == "cycle_offset" else Vector3.ZERO
		if d < 0:
			return {"t": float(keys[n - 2]["t"]) - per, "v": (keys[n - 2]["v"] as Vector3) - dv}
		return {"t": float(keys[1]["t"]) + per, "v": (keys[1]["v"] as Vector3) + dv}
	return {}


## an AUTO / AUTO-CLAMPED handle's slope at key k (clamped: the PCHIP rule, 0 where the angle turns back; else the
## neighbours' central difference). An end is flat, unless infinity continues the curve (linear: the one secant; cycle: wrapped)
static func _auto_slope(keys: Array, k: int, mode: String, clamped: bool) -> Vector3:
	var p := _nb(keys, k, -1, mode)
	var q := _nb(keys, k, 1, mode)
	var y: Vector3 = keys[k]["v"]
	var t: float = keys[k]["t"]
	if p.is_empty() and q.is_empty():
		return Vector3.ZERO
	if p.is_empty() or q.is_empty():
		if mode != "linear":
			return Vector3.ZERO
		if p.is_empty():
			return ((q["v"] as Vector3) - y) / maxf(1e-6, float(q["t"]) - t)
		return (y - (p["v"] as Vector3)) / maxf(1e-6, t - float(p["t"]))
	var hl: float = maxf(1e-6, t - float(p["t"]))
	var hr: float = maxf(1e-6, float(q["t"]) - t)
	var dl: Vector3 = (y - (p["v"] as Vector3)) / hl
	var dr: Vector3 = ((q["v"] as Vector3) - y) / hr
	if not clamped:
		return ((q["v"] as Vector3) - (p["v"] as Vector3)) / maxf(1e-6, hl + hr)
	var w1 := 2.0 * hr + hl
	var w2 := hr + 2.0 * hl
	var m := Vector3.ZERO
	for c in 3:
		if dl[c] * dr[c] > 0.0:
			m[c] = (w1 + w2) / (w1 / dl[c] + w2 / dr[c])
	return m


## key k's two handles [in, out], each Vector4(dt, d_bend, d_side, d_twist) as an OFFSET from the key (in: dt <= 0)
static func _handles(keys: Array, k: int, mode: String) -> Array:
	var ht := handle_of(keys[k])
	if ht == "aligned" or ht == "free":
		var hin_ = keys[k].get("hin")
		var hout_ = keys[k].get("hout")
		if hin_ is Vector4 and hout_ is Vector4:
			return [hin_, hout_]
		ht = "auto_clamped"
	var p := _nb(keys, k, -1, mode)
	var q := _nb(keys, k, 1, mode)
	var y: Vector3 = keys[k]["v"]
	var t: float = keys[k]["t"]
	var dti := (t - float(p["t"])) / 3.0 if not p.is_empty() else 0.0
	var dto := (float(q["t"]) - t) / 3.0 if not q.is_empty() else 0.0
	var dvi := Vector3.ZERO
	var dvo := Vector3.ZERO
	if ht == "vector":
		if not p.is_empty():
			dvi = ((p["v"] as Vector3) - y) / 3.0
		if not q.is_empty():
			dvo = ((q["v"] as Vector3) - y) / 3.0
	else:
		var sl := _auto_slope(keys, k, mode, ht == "auto_clamped")
		dvi = -sl * dti
		dvo = sl * dto
	return [Vector4(-dti, dvi.x, dvi.y, dvi.z), Vector4(dto, dvo.x, dvo.y, dvo.z)]


## the per-key / per-joint settings (defaults when absent: round 41's curve)
static func interp_of(key: Dictionary) -> String:
	return String(key.get("interp", "bezier"))


static func handle_of(key: Dictionary) -> String:
	return String(key.get("handle", "auto_clamped"))


## infinity lives on the joint's first key
static func inf_of(keys: Array) -> String:
	return String((keys[0] as Dictionary).get("inf", "hold"))


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
	var nk := {"t": t, "v": v}
	if i == 0 and not keys.is_empty() and (keys[0] as Dictionary).has("inf"):
		nk["inf"] = (keys[0] as Dictionary)["inf"]   # infinity lives on the first key: it moves to the new first
		(keys[0] as Dictionary).erase("inf")
	keys.insert(i, nk)
	pk[j] = keys


## the index of the key within tol seconds of t (the nearest), or -1
static func key_near(keys: Array, t: float, tol: float = 0.05) -> int:
	var best := -1
	var bd := tol
	for i in keys.size():
		var d := absf(float(keys[i]["t"]) - t)
		if d <= bd:
			bd = d
			best = i
	return best


## set a joint's infinity (hold / linear / cycle / cycle_offset); hold is the default so it is not stored
static func set_inf(pk: Dictionary, j: String, mode: String) -> bool:
	if not pk.has(j) or (pk[j] as Array).is_empty() or not mode in INFS:
		return false
	if mode == "hold":
		(pk[j][0] as Dictionary).erase("inf")
	else:
		pk[j][0]["inf"] = mode
	return true


## set key idx's interpolation toward the next key (bezier / constant / linear); bezier is the default so it is not stored
static func set_interp(pk: Dictionary, j: String, idx: int, mode: String) -> bool:
	if not pk.has(j) or idx < 0 or idx >= (pk[j] as Array).size() or not mode in INTERPS:
		return false
	if mode == "bezier":
		(pk[j][idx] as Dictionary).erase("interp")
	else:
		pk[j][idx]["interp"] = mode
	return true


## set key idx's handle type. Moving to free / aligned freezes the handles it has now (the curve does not jump); any other
## type drops the stored handles. auto_clamped is the default so it is not stored
static func set_handle_type(pk: Dictionary, j: String, idx: int, ht: String) -> bool:
	if not pk.has(j) or idx < 0 or idx >= (pk[j] as Array).size() or not ht in HANDLES:
		return false
	var keys: Array = pk[j]
	var key: Dictionary = keys[idx]
	if ht == "free" or ht == "aligned":
		var hs := _handles(keys, idx, inf_of(keys))
		key["hin"] = hs[0]
		key["hout"] = hs[1]
	else:
		key.erase("hin")
		key.erase("hout")
	if ht == "auto_clamped":
		key.erase("handle")
	else:
		key["handle"] = ht
	return true


## move one handle of key idx (side "in" or "out") to Vector4(dt, d_bend, d_side, d_twist). A key on auto / vector turns
## ALIGNED when its handle is moved (as in Blender); an aligned key's other handle keeps its length and turns to the same
## slope per angle
static func set_handle(pk: Dictionary, j: String, idx: int, side: String, hv: Vector4) -> bool:
	if not pk.has(j) or idx < 0 or idx >= (pk[j] as Array).size() or not side in ["in", "out"]:
		return false
	var key: Dictionary = pk[j][idx]
	var ht := handle_of(key)
	if ht != "free" and ht != "aligned":
		set_handle_type(pk, j, idx, "aligned")
		ht = "aligned"
	var me := "hin" if side == "in" else "hout"
	var other := "hout" if side == "in" else "hin"
	key[me] = hv
	if ht == "aligned" and absf(hv.x) > 1e-9:
		var o: Vector4 = key[other]
		var sl := Vector3(hv.y, hv.z, hv.w) / hv.x
		var dv := sl * o.x
		key[other] = Vector4(o.x, dv.x, dv.y, dv.z)
	return true


## the file's form: {"<joint>": [{"t", "v": [b, s, t]}]} (angles to 0.01 deg, times to 1 ms, as cards are written)
static func to_file(pk: Dictionary) -> Dictionary:
	var out := {}
	for j in pk:
		var ks := []
		for k in pk[j]:
			var v: Vector3 = k["v"]
			var e := {"t": snappedf(float(k["t"]), 0.001), "v": [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]}
			_extras_to_file(k, e)
			ks.append(e)
		if not ks.is_empty():
			out[j] = ks
	return out


## XX1: the interpolation fields, written only when not the default
static func _extras_to_file(k: Dictionary, e: Dictionary) -> void:
	if interp_of(k) != "bezier":
		e["interp"] = interp_of(k)
	var ht := handle_of(k)
	if ht != "auto_clamped":
		e["handle"] = ht
		if (ht == "aligned" or ht == "free") and k.get("hin") is Vector4 and k.get("hout") is Vector4:
			for side in ["hin", "hout"]:
				var h: Vector4 = k[side]
				e[side] = [snappedf(h.x, 0.001), snappedf(h.y, 0.01), snappedf(h.z, 0.01), snappedf(h.w, 0.01)]
	if String(k.get("inf", "hold")) != "hold":
		e["inf"] = k["inf"]


## XX1: read them back (an unknown word is the default; handles are kept only for aligned / free)
static func _extras_from_file(src: Dictionary, k: Dictionary) -> void:
	if String(src.get("interp", "")) in INTERPS and src["interp"] != "bezier":
		k["interp"] = String(src["interp"])
	var ht := String(src.get("handle", ""))
	if ht in HANDLES and ht != "auto_clamped":
		var hin_ = src.get("hin")
		var hout_ = src.get("hout")
		var has_h: bool = hin_ is Array and (hin_ as Array).size() == 4 and hout_ is Array and (hout_ as Array).size() == 4
		if (ht == "aligned" or ht == "free") and not has_h:
			ht = "auto_clamped"   # explicit handles missing: the default
		if ht != "auto_clamped":
			k["handle"] = ht
			if has_h:
				k["hin"] = Vector4(float(hin_[0]), float(hin_[1]), float(hin_[2]), float(hin_[3]))
				k["hout"] = Vector4(float(hout_[0]), float(hout_[1]), float(hout_[2]), float(hout_[3]))
	if String(src.get("inf", "")) in INFS and src["inf"] != "hold":
		k["inf"] = String(src["inf"])


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
				var nk := {"t": float(k["t"]), "v": Vector3(float(a[0]), float(a[1]), float(a[2]))}
				_extras_from_file(k, nk)
				ks.append(nk)
		ks.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
		if not ks.is_empty():
			if ks.size() > 0:
				_fix_inf(ks)
			out[String(j)] = ks
	return out


## "inf" belongs to the first key: if the sort moved another key first, carry it there (a file with it elsewhere)
static func _fix_inf(ks: Array) -> void:
	var m := ""
	for k in ks:
		if (k as Dictionary).has("inf"):
			if m == "":
				m = k["inf"]
			if k != ks[0]:
				(k as Dictionary).erase("inf")
	if m != "":
		ks[0]["inf"] = m


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
			var e := {"t": k["t"], "v": [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]}
			for f in ["interp", "handle", "inf"]:   # XX1: the interpolation fields go with the key
				if k.has(f):
					e[f] = k[f]
			for side in ["hin", "hout"]:   # a handle end is mirrored as a point (key + offset), then taken from the key (first order)
				if k.get(side) is Array and (k[side] as Array).size() == 4:
					var hh: Array = k[side]
					var qe := M.compose(String(j), Vector3(float(a[0]) + float(hh[1]), float(a[1]) + float(hh[2]), float(a[2]) + float(hh[3])))
					var ve := M.clamp_ang(o, M.decompose(o, Quaternion(qe.x, -qe.y, -qe.z, qe.w)))
					e[side] = [hh[0], snappedf(ve.x - v.x, 0.01), snappedf(ve.y - v.y, 0.01), snappedf(ve.z - v.z, 0.01)]
			ks.append(e)
		out[o] = ks
	return out
