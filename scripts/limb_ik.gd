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
## SPACES (ROADMAP 63, Maya's space switching / Blender's Child Of on a rig control): a key may carry "space": "chest" |
## "pelvis" | "weapon" | "hand_l" | "hand_r" (absent = "world"). Its target, pole and rot are then stored in THAT frame
## (the space's origin and turn, read from the body as it stands when the limb is solved), so the hand follows the chest /
## the bat / the other hand. A run of keys in one space is one curve in it (PartKeys' monotone spline, held past the ends);
## between keys of different spaces the two runs' curves are put in the world at t and mixed linearly over the span.
## switch_space() converts the target into the new space at t and keys it with a key one frame earlier holding the old
## curve, so the tip does not move at t (no pop). The limbs are solved in dependency order (a hand in the other hand's
## space, or in the weapon's space, after the hand that carries the weapon). No "space" key anywhere: nothing changes.
## Played by Scene.apply AFTER the cards, part keys, layers and breathing (play()). WEIGHT: per joint the angles go
## from the FK angles to the IK angles by w (a convex mix of two legal values stays legal). w = 0 (or no keys) leaves
## the body untouched, byte for byte.
class_name LimbIK
extends RefCounted

const LIMBS := ["hand_l", "hand_r", "foot_l", "foot_r"]
const OFF_FADE := 0.3   # s: an FK offset kept on a release key fades out over this long (smoothstep)
const OFF_MIN := 0.02   # deg: an unmatched joint under this is left to the 0.01-deg card rounding
const SPACES := ["world", "chest", "pelvis", "weapon", "hand_l", "hand_r"]
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
static func solve(B: Body, tip: String, target: Vector3, pole: Vector3, rot = null, stretch := 0.0, volume := false) -> Dictionary:
	if B.has_stretch():   # this limb's own stretch from an earlier solve goes; another limb's stays
		var left := B.stretch.duplicate()
		var left_c := B.stretch_cross.duplicate()
		for j in chain(B, tip):
			left.erase(j)
			left_c.erase(j)
		B.set_stretch(left, left_c)
		B.fk()
	var pole_use := pole
	if stretch > 1.0:
		# a limb that has to stretch is straight: the pole then only picks the roll about the arm, and a roll the shoulder cannot give is
		# clamped and drags the tip off the target. So the roll stays where the FK pose has it (the pole of the pose as it is).
		var cc := chain(B, tip)
		var nat: float = (B.p0[cc[1]] - B.p0[cc[0]]).length() + (B.p0[tip] - B.p0[cc[1]]).length()
		if (target - (B.P[cc[0]] as Vector3)).length() > nat:
			pole_use = pole_from_pose(B, tip)
	var r := _solve_core(B, tip, target, pole_use, rot)
	if stretch > 1.0 and float(r["miss"]) > 1e-6:
		r.merge(_stretch_to(B, tip, target, stretch, volume), true)
	return r


## STRETCHY LIMB (L28): the limb is already as straight as its limits let it and points at the target (the closest pose, _solve_core);
## the upper and lower bone are now both made s times longer, s = (distance to the target) / (the straight limb's reach), up to `max_s`.
## The tip lands on the target unless max_s stops it (the miss is then reported). volume: the cross scale 1/sqrt(s) is recorded
## (Body.stretch_cross) for the bones' drawing, s * c * c = 1. Nothing here runs unless the caller passed a stretch above 1.
static func _stretch_to(B: Body, tip: String, target: Vector3, max_s: float, volume: bool) -> Dictionary:
	var ch := chain(B, tip)
	var reach: float = ((B.P[tip] as Vector3) - (B.P[ch[0]] as Vector3)).length()
	var d: float = (target - (B.P[ch[0]] as Vector3)).length()
	if reach < 1e-6 or d <= reach:
		return {}
	var v: Vector3 = (B.P[tip] as Vector3) - (B.P[ch[0]] as Vector3)
	var w: Vector3 = target - (B.P[ch[0]] as Vector3)
	var sc := minf(maxf(v.dot(w) / v.length_squared(), 1.0), max_s)   # the scale that puts the tip nearest the target (exactly on it when the limb points at it)
	var st := B.stretch.duplicate()
	var cr := B.stretch_cross.duplicate()
	for j in [ch[1], ch[2]]:
		st[j] = sc
		if volume:
			cr[j] = 1.0 / sqrt(sc)
	B.set_stretch(st, cr)
	B.fk()
	return {"miss": ((B.P[tip] - target) as Vector3).length(), "stretch": sc}


static func _solve_core(B: Body, tip: String, target: Vector3, pole: Vector3, rot = null) -> Dictionary:
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


static func space_of(k: Dictionary) -> String:
	return String(k.get("space", "world"))


## the frames a space can name, in the world, as the body stands now: {"chest", "pelvis", "hand_l", "hand_r", "weapon"?}
## (the weapon only while one is on). "world" is the identity and is not listed.
static func frames(B: Body) -> Dictionary:
	var out := {}
	var src := {"chest": "spine_03", "pelvis": "pelvis", "hand_l": "hand_l", "hand_r": "hand_r"}
	for n in src:
		out[n] = Transform3D(Basis((B.G[src[n]] as Quaternion).normalized()), B.P[src[n]] as Vector3)
	if B.wep_on:
		var x := B.wep_xform()
		out["weapon"] = Transform3D(Basis((x[1] as Quaternion).normalized()), x[0] as Vector3)
	return out


static func _frame(fr: Dictionary, space: String) -> Transform3D:
	if space == "world" or not fr.has(space):
		return Transform3D.IDENTITY
	return fr[space]


## a curve value {"target", "pole", "rot"?} through the transform X
static func _conv(c: Dictionary, X: Transform3D) -> Dictionary:
	var o := {"target": X * (c["target"] as Vector3), "pole": X * (c["pole"] as Vector3)}
	if c.has("rot"):
		o["rot"] = (X.basis.get_rotation_quaternion() * (c["rot"] as Quaternion)).normalized()
	return o


## a value in `space` put in the world / a world value taken into `space`
static func to_world(c: Dictionary, fr: Dictionary, space: String) -> Dictionary:
	return _conv(c, _frame(fr, space))


static func to_local(c: Dictionary, fr: Dictionary, space: String) -> Dictionary:
	return _conv(c, _frame(fr, space).affine_inverse())


## the curve of keys `ks` (one space) at t: {"target", "pole", "rot"?}
static func _curve(ks: Array, t: float) -> Dictionary:
	var tk := []
	var pk := []
	for k in ks:
		tk.append({"t": k["t"], "v": k["target"]})
		pk.append({"t": k["t"], "v": k["pole"]})
	var out := {"target": PartKeys.at(tk, t), "pole": PartKeys.at(pk, t)}
	var a = null
	var b = null
	for k in ks:
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


## the keys of the run (consecutive keys in one space) that key i is in
static func _run(keys: Array, i: int) -> Array:
	var sp := space_of(keys[i])
	var lo := i
	var hi := i
	while lo > 0 and space_of(keys[lo - 1]) == sp:
		lo -= 1
	while hi < keys.size() - 1 and space_of(keys[hi + 1]) == sp:
		hi += 1
	return keys.slice(lo, hi + 1)


## the limb's keys at time t IN THE SPACE they govern: {"target", "pole", "w", "rot"?, "space"}. Between keys of two
## different spaces the value is in the world ("space": "world", the two runs mixed linearly over the span)
static func sample_local(keys: Array, t: float, fr := {}) -> Dictionary:
	var ia := -1
	var ib := -1
	for i in keys.size():
		if float(keys[i]["t"]) <= t:
			ia = i
		else:
			ib = i
			break
	var out: Dictionary
	if ia >= 0 and ib >= 0 and space_of(keys[ia]) != space_of(keys[ib]):
		var sa := space_of(keys[ia])
		var sb := space_of(keys[ib])
		var wa := to_world(_curve(_run(keys, ia), t), fr, sa)
		var wb := to_world(_curve(_run(keys, ib), t), fr, sb)
		var u := clampf((t - float(keys[ia]["t"])) / maxf(float(keys[ib]["t"]) - float(keys[ia]["t"]), 1e-9), 0.0, 1.0)
		out = {"target": (wa["target"] as Vector3).lerp(wb["target"], u), "pole": (wa["pole"] as Vector3).lerp(wb["pole"], u), "space": "world"}
		if wa.has("rot") and wb.has("rot"):
			out["rot"] = (wa["rot"] as Quaternion).slerp(wb["rot"], u)
		elif wa.has("rot") or wb.has("rot"):
			out["rot"] = (wa if wa.has("rot") else wb)["rot"]
	else:
		var i := ia if ia >= 0 else ib
		out = _curve(_run(keys, i), t) if i >= 0 else {"target": Vector3.ZERO, "pole": Vector3.ZERO}
		out["space"] = space_of(keys[i]) if i >= 0 else "world"
	out["w"] = weight_at(keys, t)
	return out


## the limb's keys at time t, in the WORLD: {"target", "pole", "w", "rot" (or absent), "space": the one governing t}.
## fr: frames(B) (needed only when a key has a space)
static func sample(keys: Array, t: float, fr := {}) -> Dictionary:
	var l := sample_local(keys, t, fr)
	if String(l["space"]) == "world":
		return l
	var w := to_world(l, fr, String(l["space"]))
	w["w"] = l["w"]
	w["space"] = l["space"]
	return w


## the limbs `tip` needs solved first: the hand(s) whose space a key names, the weapon's hand for a weapon space
static func deps(ik: Dictionary, B: Body, tip: String) -> Array:
	var out := []
	for k in ik.get(tip, []):
		var sp := space_of(k)
		if sp == "weapon":
			sp = B.wep_hand if B.wep_on else ""
		if sp in LIMBS and sp != tip and not sp in out:
			out.append(sp)
	return out


## would keying `tip` in `space` make a loop (it needs a limb that needs it, or the weapon its own hand carries)?
static func loops(ik: Dictionary, B: Body, tip: String, space: String) -> bool:
	var first := space
	if space == "weapon":
		first = B.wep_hand
	if not first in LIMBS:
		return false
	var seen := []
	var todo := [first]
	while not todo.is_empty():
		var l: String = todo.pop_back()
		if l == tip:
			return true
		if l in seen:
			continue
		seen.append(l)
		todo.append_array(deps(ik, B, l))
	return false


## the space segments of every limb that has a key in a space, for the timeline lane: [{"tip", "row", "space", "t0", "t1"}],
## one row per such limb (its world stretches included). A segment runs from the first key of its run to the next run's
## first key (the last one to `end`); [] = no space anywhere
static func space_lane(ik: Dictionary, end: float) -> Array:
	var out := []
	var row := 0
	for tip in LIMBS:
		var ks: Array = ik.get(tip, [])
		if not ks.any(func(k): return space_of(k) != "world"):
			continue
		var i := 0
		while i < ks.size():
			var j := i
			while j + 1 < ks.size() and space_of(ks[j + 1]) == space_of(ks[i]):
				j += 1
			var t1 := float(ks[j + 1]["t"]) if j + 1 < ks.size() else maxf(end, float(ks[j]["t"]))
			out.append({"tip": tip, "row": row, "space": space_of(ks[i]), "t0": float(ks[i]["t"]), "t1": t1})
			i = j + 1
		row += 1
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


## the FK offset a release left at or before t, faded: {joint: Vector3 deg} ({} = none, or faded out)
static func off_at(keys: Array, t: float) -> Dictionary:
	var k = null
	for c in keys:
		if float(c["t"]) <= t + SAME_T:
			k = c
		else:
			break
	if k == null or not k.has("off"):
		return {}
	var u := (t - float(k["t"])) / OFF_FADE
	if u >= 1.0:
		return {}
	var f := 1.0 - smoothstep(0.0, 1.0, maxf(u, 0.0))
	var out := {}
	for j in k["off"]:
		out[j] = ((k["off"][j][0] as Vector3) - (k["off"][j][1] as Vector3)) * f
	return out


## THE IK PASS (Scene.apply, last): every keyed limb with weight > 0 solved, then mixed with its FK angles by the
## weight. Returns {tip: solve()'s report + "w"} for the limbs that ran ({} = the body was not touched)
static func play(ik: Dictionary, B: Body, t: float) -> Dictionary:
	var out := {}
	if B.has_stretch():
		B.set_stretch({}, {})   # a stretch from the last frame is not kept: it is solved again below, or it is gone
		B.fk()
	if ik.is_empty():
		return out
	if ik.has(SpineIK.KEY):   # the back first: a pinned hand stays pinned over a moving chest
		var sr := SpineIK.play(ik[SpineIK.KEY], B, t)
		if not sr.is_empty():
			out[SpineIK.KEY] = sr
	var todo := LIMBS.filter(func(l): return not (ik.get(l, []) as Array).is_empty())
	var order := []
	while not todo.is_empty():   # a limb after the limbs its spaces need (a loop is refused by the commands; here the first goes)
		var pick: String = todo[0]
		for l in todo:
			if deps(ik, B, l).all(func(d): return not d in todo):
				pick = l
				break
		todo.erase(pick)
		order.append(pick)
	for tip in order:
		var keys: Array = ik[tip]
		var ch := chain(B, tip)
		var fo := off_at(keys, t)   # a release's leftover: IK minus FK at the switch, fading out; on the FK angles, under the mix
		if not fo.is_empty():
			for j in fo:
				B.ang[j] = B.clamp_ang(j, (B.ang[j] as Vector3) + (fo[j] as Vector3))
			B.fk()
		var fr := frames(B) if keys.any(func(k): return k.has("space")) else {}
		var k := sample(keys, t, fr)
		var w: float = k["w"]
		if w <= 0.0:
			continue
		var was := {}
		for j in ch:
			was[j] = B.ang[j]
		var sf := stretch_at(keys, t)
		var r := solve(B, tip, k["target"], k["pole"], k.get("rot", null), float(sf["stretch"]), bool(sf["vol"]))
		if w < 1.0:
			for j in ch:
				B.ang[j] = (was[j] as Vector3).lerp(B.ang[j], w)
			if r.has("stretch"):   # a faded limb stretches only by the same fade
				var s2 := 1.0 + (float(r["stretch"]) - 1.0) * w
				var st := B.stretch.duplicate()
				var cr := B.stretch_cross.duplicate()
				for j in [ch[1], ch[2]]:
					st[j] = s2
					if cr.has(j):
						cr[j] = 1.0 / sqrt(s2)
				B.set_stretch(st, cr)
			B.fk()
			r["miss"] = ((B.P[tip] - (k["target"] as Vector3)) as Vector3).length()
		r["w"] = w
		out[tip] = r
	return out


## STRETCH (L28, opt-in): a key may carry "stretch": the largest length factor (> 1) the limb may grow to reach its target, and "vol": true
## to keep the volume (cross scale 1/sqrt(s)). The key at or before t decides (the first key before any); no key with "stretch" = off.
static func stretch_at(keys: Array, t: float) -> Dictionary:
	var k: Dictionary = keys[0]
	for kk in keys:
		if float(kk["t"]) <= t:
			k = kk
	return {"stretch": float(k.get("stretch", 0.0)), "vol": bool(k.get("vol", false))}


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
static func _hold_before(S: Scene, tip: String, t: float, fps: float, fallback: Dictionary, fr := {}) -> bool:
	var dt := 1.0 / maxf(fps, 1.0)
	if t - dt < -1e-9:
		return false
	var ks: Array = S.ik.get(tip, [])
	for k in ks:
		if float(k["t"]) > t - dt - SAME_T and float(k["t"]) < t - SAME_T:
			return false
	var key := fallback.duplicate()
	key.erase("space")
	key["t"] = t - dt
	key["w"] = 0.0
	if not ks.is_empty():
		var s := sample_local(ks, t - dt, fr)   # the old curve in the space it was in: a hold keeps the space
		key["target"] = s["target"]
		key["pole"] = s["pole"]
		key["w"] = s["w"]
		if s.has("rot"):
			key["rot"] = s["rot"]
		if s["space"] != "world":
			key["space"] = s["space"]
	put(S.ik, tip, key)
	return true


## PIN (Rigify's IK-to-FK snap, then IK on): the limb keyed at t from where it is ON THE BODY NOW (B): target = the
## wrist / ankle, pole = from the elbow / knee (pole_from_pose), rot = the hand's / foot's world turn, weight 1. At t the
## IK reproduces that pose exactly, so nothing moves; afterwards the hand stays there whatever the trunk does. The curve
## before t is kept (a key one frame earlier holds it). Returns {"target", "pole", "pre": a hold key was added}
static func pin(S: Scene, B: Body, tip: String, t: float) -> Dictionary:
	var key := {"t": t, "target": B.P[tip], "pole": pole_from_pose(B, tip), "w": 1.0, "rot": B.G[tip]}
	var pre := _hold_before(S, tip, t, S.fps, key, frames(B))
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
	var best_res := INF
	var best_pose: Dictionary = (S.cards[i]["pose"] as Dictionary).duplicate(true)
	# a fixed point: what plays at t is not always the card's own number (a spline scene's upper arm reads its curve a
	# little ahead, a layer adds to it), so the card moves by the difference until the played FK meets the IK (4 at most)
	for it in 8:
		if fk_at.is_valid():
			fk_at.call()
		else:
			_fk_at(S, B, tip, t)
		res = 0.0
		for j in ch:
			var dv: Vector3 = ((B.ang[j] as Vector3) - (want[j] as Vector3)).abs()
			res = maxf(res, dv[dv.max_axis_index()])
		if res < best_res:
			best_res = res
			best_pose = (S.cards[i]["pose"] as Dictionary).duplicate(true)
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
	if res > best_res + 1e-6:
		# the last edit was not the best one (a joint the scene solves itself, e.g. a planted foot's leg, does not follow
		# its card, and the edits then wander): keep the card that came closest
		S.cards[i]["pose"] = best_pose
		if fk_at.is_valid():
			fk_at.call()
		else:
			_fk_at(S, B, tip, t)
		res = 0.0
		for j in ch:
			var dv2: Vector3 = ((B.ang[j] as Vector3) - (want[j] as Vector3)).abs()
			res = maxf(res, dv2[dv2.max_axis_index()])
	var left := {}   # per joint: IK minus the FK that plays now (what the card could not take)
	for j in ch:
		left[j] = (want[j] as Vector3) - (B.ang[j] as Vector3)
	S.apply(B, t)
	return {"ok": true, "card": i, "residual": res, "left": left, "want": want}


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
	# what the card could not take (a planted foot's leg is solved by the scene, not read from its card) rides on the key
	# as an offset that fades out over OFF_FADE: the limb is on the IK pose at t and eases onto the cards after it
	var off := {}
	for j in (r["left"] as Dictionary):
		var d: Vector3 = r["left"][j]
		if d.abs()[d.abs().max_axis_index()] > OFF_MIN:
			off[j] = [r["want"][j], B.ang[j]]   # [the IK angles at t, the FK angles that play there]
	if not off.is_empty():
		key["off"] = off
	r["pre"] = _hold_before(S, tip, t, S.fps, key, frames(B))
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
	_hold_before(S, tip, t, S.fps, key, frames(B))
	put(S.ik, tip, key)
	S.apply(B, t)
	return {"w": w}


## IK -> FK, MATCH AT THIS FRAME (ROADMAP 62): the limb leaves IK at t with no pop. The IK pose at t is baked into the
## card under the playhead (snap_fk) and the blend keyed 0 there, after a key one frame earlier holding the IK as it was,
## so the limb's world pose is the same just before and just after the switch. Needs the playhead on a card and the limb in IK
static func to_fk(S: Scene, B: Body, tip: String, t: float) -> Dictionary:
	return release(S, B, tip, t)


## FK -> IK, MATCH AT THIS FRAME (ROADMAP 62): the limb enters IK at t with no pop. Target, pole and tip turn keyed where
## the FK hand / foot and elbow / knee are NOW (what the cards, part keys and layers play, the limb's own IK off), the blend
## keyed 1 there; a key one frame earlier holds the old curve (blend 0 on an FK limb), so the blend rises over that frame
## while the IK pose already equals the FK pose. Works on any frame (no card needed). Returns {"w": the blend before, "pre"}
static func to_ik(S: Scene, B: Body, tip: String, t: float) -> Dictionary:
	var ks: Array = S.ik.get(tip, [])
	var was := weight_at(ks, t) if not ks.is_empty() else 0.0
	_fk_at(S, B, tip, t)
	var key := {"t": t, "target": B.P[tip], "pole": pole_from_pose(B, tip), "w": 1.0, "rot": B.G[tip]}
	var pre := _hold_before(S, tip, t, S.fps, key)
	put(S.ik, tip, key)
	S.apply(B, t)
	return {"w": was, "pre": pre}


## SWITCH SPACE (ROADMAP 63): from t on the limb's target / pole / tip turn live in `space` (SPACES). The curve as it plays
## at t is converted into the new frame and keyed there, after a key one frame earlier holding the old curve in the old
## space, so the tip is where it was at t (and just before it), and from t it follows the new space. A limb not in IK at t
## is pinned where it is first. Returns {"ok", "why", "moved": the tip's move at t (m), "pinned": it was pinned first,
## "from": the space it left}. B ends posed at t
static func switch_space(S: Scene, B: Body, tip: String, t: float, space: String) -> Dictionary:
	if not space in SPACES:
		return {"ok": false, "why": "no_space"}
	if space == tip:
		return {"ok": false, "why": "self"}
	S.apply(B, t)
	if space == "weapon" and not B.wep_on:
		return {"ok": false, "why": "no_weapon"}
	if loops(S.ik, B, tip, space):
		return {"ok": false, "why": "loop"}
	var pinned := false
	var ks: Array = S.ik.get(tip, [])
	if ks.is_empty() or weight_at(ks, t) <= 0.0:
		pin(S, B, tip, t)
		S.apply(B, t)
		pinned = true
		ks = S.ik[tip]
	var fr := frames(B)
	var cur := sample(ks, t, fr)   # world, as it plays
	var from := String(sample_local(ks, t, fr)["space"])
	if from == space and not pinned:
		return {"ok": true, "why": "same", "moved": 0.0, "pinned": false, "from": from}
	var before: Vector3 = B.P[tip]
	var world := {"target": cur["target"], "pole": cur["pole"], "rot": cur.get("rot", B.G[tip])}
	var fb := {"target": world["target"], "pole": world["pole"], "w": cur["w"], "rot": world["rot"]}
	_hold_before(S, tip, t, S.fps, fb, fr)
	var loc := to_local(world, fr, space)
	var key := {"t": t, "target": loc["target"], "pole": loc["pole"], "w": cur["w"], "rot": loc["rot"]}
	if space != "world":
		key["space"] = space
	put(S.ik, tip, key)
	S.apply(B, t)
	return {"ok": true, "why": "", "moved": ((B.P[tip] as Vector3) - before).length(), "pinned": pinned, "from": from}


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
			if k.has("off"):
				d["off"] = {}
				for j in k["off"]:
					d["off"][j] = [Body._p(k["off"][j][0]), Body._p(k["off"][j][1])]
			if space_of(k) != "world":
				d["space"] = space_of(k)
			if k.has("twist"):
				var tw := SpineIK._tw(k)
				d["twist"] = [snappedf(tw.x, 0.0001), snappedf(tw.y, 0.0001)]
			if float(k.get("stretch", 0.0)) > 1.0:
				d["stretch"] = snappedf(float(k["stretch"]), 0.0001)   # stretchy limb: the largest length factor; only when on
				if bool(k.get("vol", false)):
					d["vol"] = true
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
			if k.has("off") and k["off"] is Dictionary:
				key["off"] = {}
				for j in k["off"]:
					key["off"][String(j)] = [Body._v(k["off"][j][0]), Body._v(k["off"][j][1])]
			var sp := String(k.get("space", "world"))
			if sp in SPACES and sp != "world":
				key["space"] = sp
			if k.has("twist") and k["twist"] is Array and (k["twist"] as Array).size() == 2:
				key["twist"] = [float(k["twist"][0]), float(k["twist"][1])]   # the back's hip / chest twist (spine_ik.gd)
			if float(k.get("stretch", 0.0)) > 1.0:
				key["stretch"] = float(k["stretch"])
				if bool(k.get("vol", false)):
					key["vol"] = true
			ks.append(key)
		ks.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
		if not ks.is_empty():
			out[String(tip)] = ks
	return out


## MIRRORED (Scene.MIRROR_SCENE "ik"), on the FILE form: each limb's keys to its twin (hand_l <-> hand_r), every point's
## x negated (the body's mirror plane is x = 0), the tip rotation reflected as Body.mirror_pose reflects a turn
## (q.x, -q.y, -q.z, q.w); times and weights as they were
static func mirror_file(d: Dictionary, M: Body = null) -> Dictionary:
	var out := {}
	for tip in d:
		var o := Body.twin(String(tip))
		out[o] = (d[tip] as Array).map(func(k):
			var m: Dictionary = (k as Dictionary).duplicate(true)
			for f in ["target", "pole"]:
				m[f] = [-float(k[f][0]), float(k[f][1]), float(k[f][2])]
			if k.has("rot"):
				m["rot"] = [float(k["rot"][0]), -float(k["rot"][1]), -float(k["rot"][2]), float(k["rot"][3])]
			if k.has("off"):   # the kept joint angles (IK, FK) to the twin joint, reflected as Body.mirror_pose reflects a turn
				m["off"] = {}
				for j in k["off"]:
					var pair := []
					for a in k["off"][j]:
						var v := Body._v(a)
						if M != null:
							var q := M.compose(String(j), v)
							v = M.decompose(Body.twin(String(j)), Quaternion(q.x, -q.y, -q.z, q.w))
						pair.append(Body._p(v))
					m["off"][Body.twin(String(j))] = pair
			if m.has("space"):
				m["space"] = Body.twin(String(m["space"]))   # hand_l <-> hand_r; chest, pelvis, weapon are their own twins
			if k.has("twist"):
				m["twist"] = [-float(k["twist"][0]), -float(k["twist"][1])]   # a turn about the vertical reverses in the mirror
			return m)
	return out
