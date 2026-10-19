## limb_ik.gd - IK / FK WITH POLE TARGETS for the four limbs (docs/GAP_ANALYSIS.md row 13; how Blender and Rigify do
## it, in words: docs/research/BLENDER_IK.md sections b, c, e. Nothing here is Blender code).
##
## A LIMB is three joints: root (upper arm / thigh), mid (forearm / calf, a one-way hinge: side and twist locked), tip
## (hand / foot). Named by its tip: "hand_l", "hand_r", "foot_l", "foot_r". The tip's POSITION (wrist / ankle) is put on
## a TARGET (character = world space, metres) and the elbow / knee is put in the plane through root, target and POLE.
##
## THE SOLVE (closed form, two steps; solve()):
##   1 the hinge sets the root-to-tip DISTANCE. In the root's rest frame the tip is w(th) = u0 + A_mid(th) f0
##     (u0 = rest root->mid, f0 = rest mid->tip, A_mid = a turn by th about the hinge's bend axis k), so
##         |w|^2 = |u0|^2 + |f0|^2 + 2 (P cos th + Q sin th + C),
##         P = u0.f0 - (u0.k)(k.f0),  Q = u0.(k x f0),  C = (u0.k)(k.f0)
##     and th = atan2(Q, P) +- acos(rhs / sqrt(P^2 + Q^2)), rhs = (d^2 - |u0|^2 - |f0|^2) / 2 - C, d = |target - root|.
##     The candidate inside the hinge's limits nearest d wins (the limit ends are candidates too). Out of reach: the
##     acos argument is clamped, so the limb STRAIGHTENS toward the target (the closest pose) and the miss is reported.
##   2 the root turns the whole bent limb rigidly (Blender's pole pre-rotation, section b): frame 1 = (tip direction,
##     the elbow's offset square to it) in the root's rest frame; frame 2 = (target direction, the pole's offset square
##     to it) in the world; G[root] = F2 F1^T, so the tip points at the target and the elbow lies in the root-target-
##     pole plane on the pole's side. A[root] = G[parent]^-1 G[root], split into (bend, side, twist) by Body.decompose.
##   Every angle is clamped to the body's own limits (Body.clamp_ang, as set_ang does). A clamp can leave the tip off
##   the target or the elbow off the plane: solve() reports the miss and the clamped joints, it never hides them.
##   Optional tip ORIENTATION ("rot", the hand's / foot's world rotation G): A[tip] = G[mid]^-1 rot, clamped.
##
## KEYS (Scene.ik): {"hand_l": [{"t", "target": Vector3, "pole": Vector3, "w": 0..1, "rot"?: Quaternion}, ...]} sorted
## by t. Target and pole follow PartKeys' monotone curve through their keys (held past the ends); the weight is
## LINEAR between keys (a fade over a span, Blender's influence); "rot" slerps between the two keys around t that have it.
## Played by Scene.apply AFTER the cards, part keys, layers and breathing (play()). WEIGHT: per joint the angles go
## from the FK angles to the IK angles by w (a convex mix of two legal values stays legal). w = 0 (or no keys) leaves
## the body untouched, byte for byte.
class_name LimbIK
extends RefCounted

const LIMBS := ["hand_l", "hand_r", "foot_l", "foot_r"]
const KEYED := ["hand_l", "hand_r", "foot_l", "foot_r", "spine"]   # the names a scene's "ik" may hold: "spine" is the back's spline IK (spine_ik.gd)
const SAME_T := 0.001   # keys closer than this are the same key (keying there again replaces it), as PartKeys


static func chain(B: Body, tip: String) -> Array:
	var mid: String = B.parent[tip]
	return [B.parent[mid], mid, tip]


static func _perp(v: Vector3, axis: Vector3) -> Vector3:
	return v - axis * v.dot(axis)


## the hinge angle (deg, within its limits) that puts the tip `d` from the root; [deg, the distance it gives]
static func _hinge_for(B: Body, mid: String, u0: Vector3, f0: Vector3, d: float, now: float) -> Array:
	var k: Vector3 = B.b_ax[mid]
	var kf := k.dot(f0)
	var ku := k.dot(u0)
	var P := u0.dot(f0) - ku * kf
	var Q := u0.dot(k.cross(f0))
	var C := ku * kf
	var rhs := (d * d - u0.length_squared() - f0.length_squared()) * 0.5 - C
	var rm := sqrt(P * P + Q * Q)
	var phi := atan2(Q, P)
	var ac := acos(clampf(rhs / maxf(rm, 1e-12), -1.0, 1.0))
	var r: Vector2 = B.lim[mid]["bend"]
	var cands := [r.x, r.y]
	for th in [phi + ac, phi - ac, -(phi + ac), -(phi - ac)]:   # both turn senses: the bend axis convention is read, not assumed
		var dg := rad_to_deg(wrapf(th, -PI, PI))
		if dg >= r.x - 1e-9 and dg <= r.y + 1e-9:
			cands.append(clampf(dg, r.x, r.y))
	var best := 0.0
	var best_e := INF
	var best_d := 0.0
	for c in cands:
		var w: Vector3 = u0 + B.compose(mid, Vector3(c, 0, 0)) * f0
		var e := absf(w.length() - d)
		if e < best_e - 1e-9 or (absf(e - best_e) <= 1e-9 and absf(c - now) < absf(best - now)):
			best = c
			best_e = e
			best_d = w.length()
	return [best, best_d]


## put the limb's tip on `target` with its elbow / knee toward `pole` (world points). rot: the tip's world rotation, or
## null to keep its FK angles. Writes B.ang for the chain and runs B.fk(). Returns {"miss": m (tip to target),
## "clamped": [joints a limit changed], "inline": the pole lies on the root-target line (no plane: the elbow kept its side)}
static func solve(B: Body, tip: String, target: Vector3, pole: Vector3, rot = null) -> Dictionary:
	var ch := chain(B, tip)
	var root: String = ch[0]
	var mid: String = ch[1]
	var R: Vector3 = B.P[root]
	var gp: Quaternion = B.G[B.parent[root]]
	var u0: Vector3 = B.p0[mid] - B.p0[root]
	var f0: Vector3 = B.p0[tip] - B.p0[mid]
	var to: Vector3 = target - R
	var hd := _hinge_for(B, mid, u0, f0, to.length(), (B.ang[mid] as Vector3).x)
	var vmid := Vector3(hd[0], 0, 0)
	# frame 1: the bent limb in the root's rest frame
	var w: Vector3 = u0 + B.compose(mid, vmid) * f0
	var x1 := w.normalized()
	var y1 := _perp(u0, x1)
	if y1.length() < 1e-5 * u0.length():
		# straight: the side it WOULD bend to (the elbow's offset once bent 20 deg more), square to the tip line
		var wb: Vector3 = u0 + B.compose(mid, vmid + Vector3(20, 0, 0)) * f0
		y1 = _perp(_perp(u0, wb.normalized()), x1)
	y1 = y1.normalized()
	# frame 2: the target and the pole in the world
	var x2 := to.normalized() if to.length() > 1e-9 else (B.G[root] as Quaternion) * x1
	var y2 := _perp(pole - R, x2)
	var inline := y2.length() < 1e-6
	if inline:
		y2 = _perp(((B.G[root] as Quaternion) * y1), x2)   # no plane: keep the side the elbow is on now
		if y2.length() < 1e-9:
			y2 = _perp(Vector3.FORWARD if absf(x2.dot(Vector3.FORWARD)) < 0.9 else Vector3.UP, x2)
	y2 = y2.normalized()
	var F1 := Basis(x1, y1, x1.cross(y1))
	var F2 := Basis(x2, y2, x2.cross(y2))
	var q := Quaternion((F2 * F1.transposed()).orthonormalized())
	var v := B.decompose(root, (gp.inverse() * q).normalized())
	var old: Vector3 = B.ang[root]
	while v.z - old.z > 180.0:
		v.z -= 360.0
	while v.z - old.z < -180.0:
		v.z += 360.0
	var clamped := []
	var cv := B.clamp_ang(root, v)
	if (cv - v).length() > 1e-4:
		clamped.append(root)
	B.ang[root] = cv
	B.ang[mid] = B.clamp_ang(mid, vmid)
	if rot != null:
		B.fk()
		var vt := B.decompose(tip, ((B.G[mid] as Quaternion).inverse() * (rot as Quaternion)).normalized())
		var ot: Vector3 = B.ang[tip]
		while vt.z - ot.z > 180.0:
			vt.z -= 360.0
		while vt.z - ot.z < -180.0:
			vt.z += 360.0
		var ct := B.clamp_ang(tip, vt)
		if (ct - vt).length() > 1e-4:
			clamped.append(tip)
		B.ang[tip] = ct
	B.fk()
	return {"miss": ((B.P[tip] - target) as Vector3).length(), "clamped": clamped, "inline": inline}


## a pole point that reproduces the limb's CURRENT bend (Rigify's snap, section e): the middle of the root-tip chord,
## pushed out along the elbow's offset square to it by the limb's length. A straight limb: the side it would bend to.
static func pole_from_pose(B: Body, tip: String) -> Vector3:
	var ch := chain(B, tip)
	var R: Vector3 = B.P[ch[0]]
	var M: Vector3 = B.P[ch[1]]
	var W: Vector3 = B.P[tip]
	var L: float = (B.p0[ch[1]] - B.p0[ch[0]]).length() + (B.p0[tip] - B.p0[ch[1]]).length()
	var ax := (W - R).normalized()
	var off := _perp(M - R, ax)
	if off.length() < 1e-4:
		var mid: String = ch[1]
		var gm: Quaternion = B.G[ch[0]]
		var f0: Vector3 = B.p0[tip] - B.p0[mid]
		var wb: Vector3 = (B.p0[mid] - B.p0[ch[0]]) + B.compose(mid, (B.ang[mid] as Vector3) + Vector3(20, 0, 0)) * f0
		off = _perp(gm * _perp(B.p0[mid] - B.p0[ch[0]], wb.normalized()), ax)
	return R + (W - R) * 0.5 + off.normalized() * L


## the limb's keys at time t: {"target", "pole", "w", "rot" (or absent)}
static func sample(keys: Array, t: float) -> Dictionary:
	var tk := []
	var pk := []
	for k in keys:
		tk.append({"t": k["t"], "v": k["target"]})
		pk.append({"t": k["t"], "v": k["pole"]})
	var out := {"target": PartKeys.at(tk, t), "pole": PartKeys.at(pk, t), "w": weight_at(keys, t)}
	var a = null
	var b = null
	for k in keys:
		if not k.has("rot"):
			continue
		if float(k["t"]) <= t:
			a = k
		elif b == null:
			b = k
	if a != null and b != null:
		var u := (t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 1e-9)
		out["rot"] = (a["rot"] as Quaternion).slerp(b["rot"], clampf(u, 0.0, 1.0))
	elif a != null or b != null:
		out["rot"] = (a if a != null else b)["rot"]
	return out


## the weight at t: linear between keys, held past the ends, 0..1
static func weight_at(keys: Array, t: float) -> float:
	if keys.is_empty():
		return 0.0
	if t <= float(keys[0]["t"]):
		return clampf(float(keys[0]["w"]), 0.0, 1.0)
	for i in range(1, keys.size()):
		if t <= float(keys[i]["t"]):
			var a: Dictionary = keys[i - 1]
			var b: Dictionary = keys[i]
			var u := (t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 1e-9)
			return clampf(lerpf(float(a["w"]), float(b["w"]), u), 0.0, 1.0)
	return clampf(float(keys[-1]["w"]), 0.0, 1.0)


## THE IK PASS (Scene.apply, last): every keyed limb with weight > 0 solved, then mixed with its FK angles by the
## weight. Returns {tip: solve()'s report + "w"} for the limbs that ran ({} = the body was not touched)
static func play(ik: Dictionary, B: Body, t: float) -> Dictionary:
	var out := {}
	if ik.is_empty():
		return out
	if ik.has(SpineIK.KEY):   # the back first: a pinned hand stays pinned over a moving chest
		var sr := SpineIK.play(ik[SpineIK.KEY], B, t)
		if not sr.is_empty():
			out[SpineIK.KEY] = sr
	for tip in LIMBS:
		var keys: Array = ik.get(tip, [])
		if keys.is_empty():
			continue
		var k := sample(keys, t)
		var w: float = k["w"]
		if w <= 0.0:
			continue
		var ch := chain(B, tip)
		var was := {}
		for j in ch:
			was[j] = B.ang[j]
		var r := solve(B, tip, k["target"], k["pole"], k.get("rot", null))
		if w < 1.0:
			for j in ch:
				B.ang[j] = (was[j] as Vector3).lerp(B.ang[j], w)
			B.fk()
			r["miss"] = ((B.P[tip] - (k["target"] as Vector3)) as Vector3).length()
		r["w"] = w
		out[tip] = r
	return out


## key the limb at t (replacing a key within SAME_T); keeps the list sorted. Returns the key's index
static func put(ik: Dictionary, tip: String, key: Dictionary) -> int:
	var ks: Array = ik.get(tip, [])
	var t := float(key["t"])
	for i in ks.size():
		if absf(float(ks[i]["t"]) - t) < SAME_T:
			ks[i] = key
			ik[tip] = ks
			return i
	ks.append(key)
	ks.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	ik[tip] = ks
	return ks.find(key)


# ---------------------------------------------------------------- the animator's four commands (main.gd wraps them)

## the limb a picked part belongs to ("hand_l" for the left upper arm, forearm, hand or a finger; "foot_r" for the right
## thigh, calf, foot or ball); "" for the trunk, the head and the collarbones
static func limb_of(part: String) -> String:
	var sd := part.right(2)
	if not sd in ["_l", "_r"]:
		return ""
	for p in ["upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky"]:
		if part.begins_with(p):
			return "hand" + sd
	for p in ["thigh", "calf", "foot", "ball"]:
		if part.begins_with(p):
			return "foot" + sd
	return ""


## the card whose arrival or hold contains t (within 1 ms), or -1
static func card_at(S: Scene, t: float) -> int:
	var ts := S.times()
	for i in ts.size():
		if t >= float(ts[i][1]) - 0.001 and t <= float(ts[i][2]) + 0.001:
			return i
	return -1


## the scene as it plays at t with this limb's IK off (its FK), posed on B
static func _fk_at(S: Scene, B: Body, tip: String, t: float) -> void:
	var keep = S.ik.get(tip, null)
	S.ik.erase(tip)
	S.apply(B, t)
	if keep != null:
		S.ik[tip] = keep


## a key at t - 1 frame holding the OLD curve there (target, pole, rot, weight as they played), unless a key is already
## within that frame: so a change keyed at t happens over the last frame, not over the whole span from the key before
static func _hold_before(S: Scene, tip: String, t: float, fps: float, fallback: Dictionary) -> bool:
	var dt := 1.0 / maxf(fps, 1.0)
	if t - dt < -1e-9:
		return false
	var ks: Array = S.ik.get(tip, [])
	for k in ks:
		if float(k["t"]) > t - dt - SAME_T and float(k["t"]) < t - SAME_T:
			return false
	var key := fallback.duplicate()
	key["t"] = t - dt
	key["w"] = 0.0
	if not ks.is_empty():
		var s := sample(ks, t - dt)
		key["target"] = s["target"]
		key["pole"] = s["pole"]
		key["w"] = s["w"]
		if s.has("rot"):
			key["rot"] = s["rot"]
	put(S.ik, tip, key)
	return true


## PIN (Rigify's IK-to-FK snap, then IK on): the limb keyed at t from where it is ON THE BODY NOW (B): target = the
## wrist / ankle, pole = from the elbow / knee (pole_from_pose), rot = the hand's / foot's world turn, weight 1. At t the
## IK reproduces that pose exactly, so nothing moves; afterwards the hand stays there whatever the trunk does. The curve
## before t is kept (a key one frame earlier holds it). Returns {"target", "pole", "pre": a hold key was added}
static func pin(S: Scene, B: Body, tip: String, t: float) -> Dictionary:
	var key := {"t": t, "target": B.P[tip], "pole": pole_from_pose(B, tip), "w": 1.0, "rot": B.G[tip]}
	var pre := _hold_before(S, tip, t, S.fps, key)
	put(S.ik, tip, key)
	return {"target": key["target"], "pole": key["pole"], "pre": pre}


## SNAP FK TO IK (Blender's visual keying, docs/research/BLENDER_CONSTRAINTS.md section 4): the limb's FK at t is made
## what the IK shows there. FK at t is the card the playhead is on (its pose), plus whatever plays over it (part keys,
## layers), so each joint's card angle moves by (IK - FK as played): a joint with part keys gets a part key at t instead.
## Needs the playhead on a card. B ends posed at t as the scene now plays. Returns {"ok", "card", "residual": the
## largest angle (deg) the FK at t still differs from the IK, read back with the IK off}. fk_at (round 51): what "the
## limb's FK at t" is, posed on B (default: the scene with this limb's IK off; Constraints.release_keep: one constraint off)
static func snap_fk(S: Scene, B: Body, tip: String, t: float, fk_at := Callable()) -> Dictionary:
	var i := card_at(S, t)
	if i < 0:
		return {"ok": false, "card": -1, "residual": INF}
	# an AUTO move time is read from the poses: the edit below would move every later card in time (and the IK keys
	# with them). Pin the two moves next to this card to the times they have now, so the timeline does not shift
	for k in [i, i + 1]:
		if k > 0 and k < S.cards.size() and float(S.cards[k]["move"]) <= 0.0:
			S.cards[k]["move"] = S.move_time(k)
	var ch := chain(B, tip)
	S.apply(B, t)
	var want := {}
	for j in ch:
		want[j] = B.ang[j]
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var res := INF
	# a fixed point: what plays at t is not always the card's own number (a spline scene's upper arm reads its curve a
	# little ahead, a layer adds to it), so the card moves by the difference until the played FK meets the IK (4 at most)
	for it in 4:
		if fk_at.is_valid():
			fk_at.call()
		else:
			_fk_at(S, B, tip, t)
		res = 0.0
		for j in ch:
			var dv: Vector3 = ((B.ang[j] as Vector3) - (want[j] as Vector3)).abs()
			res = maxf(res, dv[dv.max_axis_index()])
		if res < 0.005:
			break
		var pose: Dictionary = (S.cards[i]["pose"] as Dictionary).duplicate(true)
		M.from_dict(pose)
		for j in ch:
			var d: Vector3 = (want[j] as Vector3) - (B.ang[j] as Vector3)
			if S.part_keys.has(j) and not (S.part_keys[j] as Array).is_empty():
				PartKeys.put(S.part_keys, j, t, B.clamp_ang(j, PartKeys.at(S.part_keys[j], t) + d))
			else:
				M.ang[j] = M.clamp_ang(j, (M.ang[j] as Vector3) + d)
		M.fk()
		var fresh := M.to_dict()
		for j in Body.ORDER:
			if ch.any(func(c): return j in M.below(c)):
				pose["joints"][j] = fresh["joints"][j]   # the chain and what hangs off it: angles, and the positions they make
		S.cards[i]["pose"] = pose
	if fk_at.is_valid():
		fk_at.call()
	else:
		_fk_at(S, B, tip, t)
	res = 0.0
	for j in ch:
		var dv: Vector3 = ((B.ang[j] as Vector3) - (want[j] as Vector3)).abs()
		res = maxf(res, dv[dv.max_axis_index()])
	S.apply(B, t)
	return {"ok": true, "card": i, "residual": res}


## RELEASE: snap FK to IK at t, then the weight keyed 0 at t (after a key one frame earlier that holds the IK as it
## was), so the limb hands over to the cards at t without a jump. Needs the playhead on a card and the limb in IK there.
## Returns snap_fk's report + "pre"
static func release(S: Scene, B: Body, tip: String, t: float) -> Dictionary:
	var ks: Array = S.ik.get(tip, [])
	if ks.is_empty() or weight_at(ks, t) <= 0.0:
		return {"ok": false, "card": card_at(S, t), "residual": INF, "why": "not_ik"}
	var r := snap_fk(S, B, tip, t)
	if not r["ok"]:
		r["why"] = "no_card"
		return r
	_fk_at(S, B, tip, t)   # the FK now = the IK at t
	var key := {"t": t, "target": B.P[tip], "pole": pole_from_pose(B, tip), "w": 0.0, "rot": B.G[tip]}
	r["pre"] = _hold_before(S, tip, t, S.fps, key)
	put(S.ik, tip, key)
	S.apply(B, t)
	return r


## SNAP IK TO FK (Rigify's FK-to-IK snap): the limb's target, pole and rot keyed at t where the cards (FK) put it; the
## weight keeps its value at t. B ends posed at t as the scene now plays. Returns {"w": that weight}
static func snap_ik(S: Scene, B: Body, tip: String, t: float) -> Dictionary:
	var ks: Array = S.ik.get(tip, [])
	var w := weight_at(ks, t) if not ks.is_empty() else 0.0
	_fk_at(S, B, tip, t)
	var key := {"t": t, "target": B.P[tip], "pole": pole_from_pose(B, tip), "w": w, "rot": B.G[tip]}
	_hold_before(S, tip, t, S.fps, key)
	put(S.ik, tip, key)
	S.apply(B, t)
	return {"w": w}


## IN THE FILE: "ik": {"hand_l": [{"t", "target": [x, y, z], "pole": [x, y, z], "w", "rot"?: [x, y, z, w]}]}, written
## only when there is a key (a scene without one saves byte for byte as before). t and w to 0.0001, points to 0.1 mm
static func to_file(ik: Dictionary) -> Dictionary:
	var out := {}
	for tip in KEYED:
		if not ik.has(tip) or (ik[tip] as Array).is_empty():
			continue
		out[tip] = (ik[tip] as Array).map(func(k):
			var d := {"t": snappedf(float(k["t"]), 0.0001), "target": Body._p(k["target"]), "pole": Body._p(k["pole"]),
				"w": snappedf(clampf(float(k["w"]), 0.0, 1.0), 0.0001)}
			if k.has("rot"):
				d["rot"] = Body._q(k["rot"])
			if k.has("twist"):
				var tw := SpineIK._tw(k)
				d["twist"] = [snappedf(tw.x, 0.0001), snappedf(tw.y, 0.0001)]
			return d)
	return out


static func from_file(d: Variant) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		return out
	for tip in d:
		if not String(tip) in KEYED or not d[tip] is Array:
			continue
		var ks := []
		for k in d[tip]:
			if not (k is Dictionary and k.has("t") and k.has("target") and k.has("pole")):
				continue
			var key := {"t": float(k["t"]), "target": Body._v(k["target"]), "pole": Body._v(k["pole"]),
				"w": clampf(float(k.get("w", 1.0)), 0.0, 1.0)}
			if k.has("rot") and k["rot"] is Array and (k["rot"] as Array).size() == 4:
				var r: Array = k["rot"]
				key["rot"] = Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized()
			if k.has("twist") and k["twist"] is Array and (k["twist"] as Array).size() == 2:
				key["twist"] = [float(k["twist"][0]), float(k["twist"][1])]   # the back's hip / chest twist (spine_ik.gd)
			ks.append(key)
		ks.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
		if not ks.is_empty():
			out[String(tip)] = ks
	return out


## MIRRORED (Scene.MIRROR_SCENE "ik"), on the FILE form: each limb's keys to its twin (hand_l <-> hand_r), every point's
## x negated (the body's mirror plane is x = 0), the tip rotation reflected as Body.mirror_pose reflects a turn
## (q.x, -q.y, -q.z, q.w); times and weights as they were
static func mirror_file(d: Dictionary) -> Dictionary:
	var out := {}
	for tip in d:
		var o := Body.twin(String(tip))
		out[o] = (d[tip] as Array).map(func(k):
			var m: Dictionary = (k as Dictionary).duplicate(true)
			for f in ["target", "pole"]:
				m[f] = [-float(k[f][0]), float(k[f][1]), float(k[f][2])]
			if k.has("rot"):
				m["rot"] = [float(k["rot"][0]), -float(k["rot"][1]), -float(k["rot"][2]), float(k["rot"][3])]
			if k.has("twist"):
				m["twist"] = [-float(k["twist"][0]), -float(k["twist"][1])]   # a turn about the vertical reverses in the mirror
			return m)
	return out
