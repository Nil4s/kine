## constraints.gd - USER CONSTRAINTS (round 51, GATES CN1..CN3; docs/GAP_ANALYSIS.md upgrade #3). How Blender's stack
## works, in words: docs/research/BLENDER_CONSTRAINTS.md. Nothing here is Blender code (Blender is GPL): this is our own
## code written from the behaviour described there.
##
## A CONSTRAINT is a Dictionary in Scene.cons (a LIST: the stack, played top to bottom, each one seeing what the ones
## above it left, as Blender's stack does):
##   "type":   "child_of"  the owner follows a target, keeping the offset it had when the constraint was set
##             "track_to"  the head aims at a target (LookAt's neck + head solve), never past the neck's limits
##             "floor"     a foot never below the floor (+ "height"); it pushes up, it never pulls down
##   "owner":  child_of: "hand_l" "hand_r" "foot_l" "foot_r" (the limb reaches it with LimbIK.solve, so the arm bends
##             instead of the hand detaching) or "pelvis" (the whole body moves: the root); track_to: "head";
##             floor: "foot_l" "foot_r"
##   "target": {"kind": "part", "part": <joint of this body>} | {"kind": "weapon"} | {"kind": "point", "at": Vector3}
##             | {"kind": "prop", "prop": <index in Scene.props>} | {"kind": "actor", "actor": k, "part": <joint>}
##             (k = the fighter's number in the hero's file: 0 = the hero, 1 = the first of "actors")
##   "offset": child_of only: {"pos": Vector3, "rot": Quaternion} = the owner's world transform in the target's frame,
##             taken ONCE when the constraint is made (Blender's "Set Inverse", stored on the constraint). Played:
##             owner = target x offset, so at the moment it was set nothing moves.
##   "w" 0..1 and "wk" [[t, w], ...]: the INFLUENCE, exactly a layer's weight (Scene.layer_weight: the keyed curve,
##             linear between keys, held past the ends, times "w"); "mute": true = off; "height" (floor, m).
##
## EVALUATION ORDER (Scene.apply): cards -> part keys -> layers -> breathing -> IK -> CONSTRAINTS in list order -> joint
## limits. Why: Blender runs a bone's constraints on its FINISHED animated pose (the action, then the stack, top to bottom;
## research doc section 1): a constraint is a post-process of what the animator keyed, not an input to it. IK is ours
## and keyed per limb, so it is part of "the animation" a constraint corrects (a Child Of on a pinned hand wins over the
## pin, the way a later constraint wins in Blender's stack). The joint limits are LAST because every angle a constraint
## writes goes through Body.clamp_ang (LimbIK.solve and LookAt clamp each joint as they set it): a constraint can never
## drag a joint past its range (Blender needs a Limit Rotation put after the others for that; here it is built in).
##
## INFLUENCE BLEND: for a hand / foot / head, per joint the angles go from the animated ones to the constrained ones by
## the influence (as LimbIK.play's weight: a convex mix of two legal angle sets is legal, and it is continuous in the
## influence, so a keyed fade moves the limb smoothly). For the hips: position lerped, rotation slerped in WORLD space
## (Blender's decomposed blend). Influence 0, muted, no constraint: the body is not touched, byte for byte.
## RELEASE without a pop: key the influence down over a few frames (fade), or "release keeping the pose" (release_keep:
## Blender's Apply / visual keying: the constrained pose is written into the card at the playhead, then influence 0).
class_name Constraints
extends RefCounted

const TYPES := ["child_of", "track_to", "floor"]
const CHILD_OWNERS := ["hand_l", "hand_r", "foot_l", "foot_r", "pelvis"]
const KINDS := ["part", "weapon", "point", "prop", "actor"]
const SAME_T := 0.001   # influence keys closer than this are the same key (keying there again replaces it)
const FADE_FRAMES := 6  # the commands' fade length (frames)

## > 0 while another fighter's scene is played to read a target off it: that scene's own actor targets are skipped
## then (two fighters looking at each other would otherwise play each other forever)
static var _depth := 0


## the owner a constraint type takes from a picked part: a hand / foot for a part of that limb, the hips for the pelvis,
## the head for the head or neck; "" = none
static func owner_of(type: String, part: String) -> String:
	match type:
		"child_of":
			if part == "pelvis":
				return "pelvis"
			return LimbIK.limb_of(part)
		"track_to":
			return "head" if part in ["head", "neck_01"] else ""
		"floor":
			var l := LimbIK.limb_of(part)
			return l if l.begins_with("foot") else ""
	return ""


## the influence at t (0 when muted)
static func weight(c: Dictionary, t: float) -> float:
	if bool(c.get("mute", false)):
		return 0.0
	return Scene.layer_weight(c, t)


## a fighter's file placement {"pos": [x, z], "yaw": deg} as its body space -> the hero's (main.actor_xf's formula)
static func actor_xf(xf: Dictionary) -> Transform3D:
	var p: Array = xf.get("pos", [0.0, 0.0])
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(xf.get("yaw", 0.0)))), Vector3(float(p[0]), 0.0, float(p[1])))


## each fighter's scene told who the hero is and its own number (actor targets are read through the hero's list).
## Weak: the hero holds the actors, so a strong reference back would never be freed
static func link(hero: Scene) -> void:
	hero.cons_hero = null
	hero.cons_me = 0
	for k in hero.actors.size():
		var sc: Scene = hero.actors[k]["scene"]
		sc.cons_hero = weakref(hero)
		sc.cons_me = k + 1


static func _xf(pos: Vector3, rot: Quaternion) -> Transform3D:
	return Transform3D(Basis(rot.normalized()), pos)


## the owner's world transform now (wrist / ankle / hips: the joint's position and turn; the head: the same)
static func owner_xf(B: Body, owner: String) -> Transform3D:
	return _xf(B.P[owner], B.G[owner])


## why a target cannot drive this owner ("" = it can): a target the owner itself moves would chase itself
static func bad_target(B: Body, owner: String, tg: Dictionary) -> String:
	var kind := String(tg.get("kind", ""))
	if not kind in KINDS:
		return "no such target"
	if kind == "part":
		var p := String(tg.get("part", ""))
		if not B.lim.has(p):
			return "no such part"
		var moved: Array = B.below(owner if owner in ["pelvis", "head"] else LimbIK.chain(B, owner)[0])
		if owner == "head":
			moved = B.below("neck_01")
		if p in moved:
			return "it moves with the owner"
	if kind == "weapon" and owner != "head" and owner != "pelvis" and B.wep_hand == owner:
		return "the weapon is in that hand"
	if kind == "weapon" and owner == "pelvis" and B.wep_hand != "":
		return "the weapon is held: it moves with the hips"
	return ""


## the target's world transform at t in this body's space, or null (no weapon now, no such prop / fighter / part)
static func target_xf(S: Scene, B: Body, tg: Dictionary, t: float):
	match String(tg.get("kind", "")):
		"part":
			var p := String(tg.get("part", ""))
			return _xf(B.P[p], B.G[p]) if B.P.has(p) else null
		"weapon":
			if not B.wep_on:
				return null
			var x := B.wep_xform()
			return _xf(x[0], x[1])
		"point":
			return Transform3D(Basis(), tg["at"])
		"prop":
			var i := int(tg.get("prop", -1))
			return (S.props[i]["xf"] as Transform3D) if i >= 0 and i < S.props.size() else null
		"actor":
			return _actor_target(S, tg, t)
	return null


## another fighter's part, posed from its own scene at t, in this fighter's space: X_me^-1 X_k (P, G)
static func _actor_target(S: Scene, tg: Dictionary, t: float):
	if _depth > 0:
		return null
	var hero: Scene = S
	if S.cons_hero != null:
		hero = (S.cons_hero as WeakRef).get_ref()
		if hero == null:
			return null
	var k := int(tg.get("actor", -1))
	var me := S.cons_me if S.cons_hero != null else 0
	if k == me or k < 0 or k > hero.actors.size():
		return null
	var other: Scene = hero if k == 0 else hero.actors[k - 1]["scene"]
	var Xk := Transform3D.IDENTITY if k == 0 else actor_xf(hero.actors[k - 1]["xf"])
	var Xme := Transform3D.IDENTITY if me == 0 else actor_xf(hero.actors[me - 1]["xf"])
	var ob = S._cons_scratch.get(k)
	if ob == null:
		ob = Body.new()
		ob.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		ob.fk()
		S._cons_scratch[k] = ob
	_depth += 1
	other.apply(ob, t)
	_depth -= 1
	var p := String(tg.get("part", "head"))
	if not (ob as Body).P.has(p):
		return null
	return Xme.affine_inverse() * Xk * _xf((ob as Body).P[p], (ob as Body).G[p])


# ---------------------------------------------------------------- THE PASS (Scene.apply, after IK)

## every constraint with influence > 0, in list order. Returns a report per constraint that ran: {"i", "type", "owner",
## "w", "miss" (m: the owner off its constrained place; floor: how far below it still is), "rot_miss" (deg), "clamped"}
static func play(S: Scene, B: Body, t: float) -> Array:
	var out := []
	var was_fast := B.fast
	B.fast = true   # angles through the limits only (playback): no contact bisection inside a solve
	var limb_moved := false
	var owned := {}
	for i in S.cons.size():
		var c: Dictionary = S.cons[i]
		var w := weight(c, t)
		if w <= 0.0:
			continue
		var r := {}
		match String(c.get("type", "")):
			"child_of":
				r = _child_of(S, B, c, w, t)
				if not r.is_empty() and c["owner"] != "pelvis":
					limb_moved = true
					owned[c["owner"]] = true
				elif not r.is_empty():
					limb_moved = true
			"track_to":
				r = _track_to(S, B, c, w, t)
			"floor":
				r = _floor(B, c, w)
		if r.is_empty():
			continue
		r["i"] = i
		r["type"] = c["type"]
		r["owner"] = c["owner"]
		r["w"] = w
		out.append(r)
	if limb_moved and B.wep_on and B.grip and B.wep_hand != "" and not owned.has("hand_l" if B.wep_hand == "hand_r" else "hand_r"):
		B.apply_grip()   # the weapon hand moved: the other hand follows it onto the bat (unless it is constrained itself)
	B.fast = was_fast
	return out


static func _chain_of(B: Body, owner: String) -> Array:
	if owner == "head":
		return ["neck_01", "head"]
	if owner == "pelvis":
		return ["pelvis"]
	return LimbIK.chain(B, owner)


## the joints mixed from the animated angles `was` to the solved ones by w (a convex mix of legal angles stays legal)
static func _mix(B: Body, was: Dictionary, w: float) -> void:
	if w >= 1.0:
		return
	for j in was:
		B.ang[j] = (was[j] as Vector3).lerp(B.ang[j], w)
	B.fk()


static func _child_of(S: Scene, B: Body, c: Dictionary, w: float, t: float) -> Dictionary:
	var owner: String = c["owner"]
	var tg: Dictionary = c.get("target", {})
	if bad_target(B, owner, tg) != "":
		return {}
	var T = target_xf(S, B, tg, t)
	if T == null:
		return {}
	var off: Dictionary = c.get("offset", {})
	var C: Transform3D = (T as Transform3D) * _xf(off.get("pos", Vector3.ZERO), off.get("rot", Quaternion.IDENTITY))
	var cq := C.basis.get_rotation_quaternion()
	if owner == "pelvis":
		var p0: Vector3 = B.P["pelvis"]
		var q0: Quaternion = B.G["pelvis"]
		var pos := p0.lerp(C.origin, w) if w < 1.0 else C.origin
		var q := q0.slerp(cq, w) if w < 1.0 else cq
		var v := B.decompose("pelvis", q.normalized())
		var old: Vector3 = B.ang["pelvis"]
		while v.z - old.z > 180.0:
			v.z -= 360.0
		while v.z - old.z < -180.0:
			v.z += 360.0
		var cv := B.clamp_ang("pelvis", v)
		B.ang["pelvis"] = cv
		B.offset = pos - (B.p0["pelvis"] as Vector3)
		B.fk()
		return {"miss": ((B.P["pelvis"] as Vector3) - pos).length(), "rot_miss": rad_to_deg((B.G["pelvis"] as Quaternion).angle_to(q)),
			"clamped": ["pelvis"] if (cv - v).length() > 1e-4 else []}
	var ch := _chain_of(B, owner)
	var was := {}
	for j in ch:
		was[j] = B.ang[j]
	var pole := LimbIK.pole_from_pose(B, owner)
	var r := LimbIK.solve(B, owner, C.origin, pole, cq)
	_mix(B, was, w)
	return {"miss": ((B.P[owner] as Vector3) - C.origin).length(), "rot_miss": rad_to_deg((B.G[owner] as Quaternion).angle_to(cq)),
		"clamped": r["clamped"]}


static func _track_to(S: Scene, B: Body, c: Dictionary, w: float, t: float) -> Dictionary:
	var tg: Dictionary = c.get("target", {})
	if bad_target(B, "head", tg) != "":
		return {}
	var T = target_xf(S, B, tg, t)
	if T == null:
		return {}
	var at: Vector3 = (T as Transform3D).origin
	var was := {"neck_01": B.ang["neck_01"], "head": B.ang["head"]}
	var r := LookAt.solve(B, at)
	if float(r["error"]) > 0.2:
		r["error"] = _aim_refine(B, at)
	_mix(B, was, w)
	var clamped := []
	for j in was:
		if not B.at_limit(j).is_empty():
			clamped.append(j)
	return {"miss": 0.0, "rot_miss": float(r["error"]), "clamped": clamped, "target": at}


## LookAt's alternating swings stop where ONE joint meets a stop; near the edge of the range another split of the turn
## between neck and head can still aim closer. A pattern search on the six neck + head angles (each kept inside its
## limits), steps 2 -> 0.05 deg, from LookAt's answer: never worse than it. Returns the aim error left (deg)
static func _aim_refine(B: Body, at: Vector3) -> float:
	var js := ["neck_01", "head"]
	var best := LookAt.amplitude(B, at)
	var step := 2.0
	var evals := 0
	while step >= 0.05 and best > 0.02 and evals < 400:
		var moved := true
		while moved and evals < 400:
			moved = false
			for k in 6:
				var j: String = js[k / 3]
				for sg in [-1.0, 1.0]:
					var old: Vector3 = B.ang[j]
					var v := old
					v[k % 3] += sg * step
					v = B.clamp_ang(j, v)
					if v == old:
						continue
					B.ang[j] = v
					B.fk_sub("neck_01")
					evals += 1
					var e := LookAt.amplitude(B, at)
					if e < best - 1e-6:
						best = e
						moved = true
					else:
						B.ang[j] = old
						B.fk_sub("neck_01")
		step *= 0.5
	return best


## the foot's lowest sole point above the floor (Body.foot_sole_low: the heel, the ball and the toe tip, as the floor
## grounding measures them); below "height": the leg re-solved (LimbIK) with the ankle lifted by the gap and the foot's
## turn kept, so every sole point rises by exactly the gap. Above it: nothing is touched
static func _floor(B: Body, c: Dictionary, w: float) -> Dictionary:
	var owner: String = c["owner"]
	var sd := owner.right(2)
	var h := float(c.get("height", 0.0))
	var low := B.foot_sole_low(sd)
	if low >= h:
		return {}
	var ch := _chain_of(B, owner)
	var was := {}
	for j in ch:
		was[j] = B.ang[j]
	var to: Vector3 = (B.P[owner] as Vector3) + Vector3(0.0, h - low, 0.0)
	var r := LimbIK.solve(B, owner, to, LimbIK.pole_from_pose(B, owner), B.G[owner])
	_mix(B, was, w)
	return {"miss": maxf(0.0, h - B.foot_sole_low(sd)), "rot_miss": 0.0, "clamped": r["clamped"]}


# ---------------------------------------------------------------- making and keying them (main.gd's commands)

## CHILD OF from the body as it is NOW (B, posed at t): offset = target^-1 x owner, so at t nothing moves. Influence
## keyed 0 one frame before t and 1 at t (on from the playhead; before it the owner plays its own animation: Blender's
## grab recipe, research doc section 2). At t = 0: always on. Appended to the stack; returns it ({} = refused, see why)
static func add_child_of(S: Scene, B: Body, owner: String, tg: Dictionary, t: float) -> Dictionary:
	if not owner in CHILD_OWNERS or bad_target(B, owner, tg) != "":
		return {}
	var T = target_xf(S, B, tg, t)
	if T == null:
		return {}
	var O: Transform3D = (T as Transform3D).affine_inverse() * owner_xf(B, owner)
	var c := {"type": "child_of", "owner": owner, "target": tg.duplicate(true),
		"offset": {"pos": O.origin, "rot": O.basis.get_rotation_quaternion().normalized()}, "w": 1.0, "wk": []}
	var dt := 1.0 / maxf(float(S.fps), 1.0)
	if t - dt > -1e-9:
		c["wk"] = [[t - dt, 0.0], [t, 1.0]]
	S.cons.append(c)
	return c


## TRACK TO for the head: faded in over FADE_FRAMES from t (a head that turned at once would pop)
static func add_track_to(S: Scene, B: Body, tg: Dictionary, t: float) -> Dictionary:
	if bad_target(B, "head", tg) != "" or target_xf(S, B, tg, t) == null:
		return {}
	var c := {"type": "track_to", "owner": "head", "target": tg.duplicate(true), "w": 1.0,
		"wk": [[t, 0.0], [t + float(FADE_FRAMES) / maxf(float(S.fps), 1.0), 1.0]]}
	S.cons.append(c)
	return c


## FLOOR for a foot: always on (a floor has no reason to come and go), at `height` m
static func add_floor(S: Scene, owner: String, height := 0.0) -> Dictionary:
	if not owner in ["foot_l", "foot_r"]:
		return {}
	var c := {"type": "floor", "owner": owner, "height": height, "w": 1.0, "wk": []}
	S.cons.append(c)
	return c


## the last constraint in the stack on this owner (-1 = none)
static func last_on(S: Scene, owner: String) -> int:
	for i in range(S.cons.size() - 1, -1, -1):
		if S.cons[i].get("owner", "") == owner:
			return i
	return -1


## an influence key at t (replacing one within SAME_T); "wk" kept in time order
static func put_key(c: Dictionary, t: float, w: float) -> void:
	var wk: Array = c.get("wk", [])
	for k in wk:
		if absf(float(k[0]) - t) < SAME_T:
			k[1] = clampf(w, 0.0, 1.0)
			c["wk"] = wk
			return
	wk.append([t, clampf(w, 0.0, 1.0)])
	wk.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	c["wk"] = wk


## FADE: the influence keyed as it plays at t, then `to` FADE_FRAMES later (the keys in between dropped): the owner
## moves from one to the other over those frames, no pop. "w" (the dial) is folded into the keys first
static func fade(S: Scene, i: int, t: float, to: float, frames := FADE_FRAMES) -> void:
	var c: Dictionary = S.cons[i]
	var now := weight(c, t)
	var t2 := t + float(frames) / maxf(float(S.fps), 1.0)
	var wk: Array = (c.get("wk", []) as Array).duplicate(true)
	var dial := clampf(float(c.get("w", 1.0)), 0.0, 1.0)
	if wk.is_empty():
		wk = [[0.0, 1.0]]
	for k in wk:
		k[1] = float(k[1]) * dial
	c["w"] = 1.0
	c["wk"] = wk.filter(func(k): return float(k[0]) < t - SAME_T or float(k[0]) > t2 + SAME_T)
	put_key(c, t, now)
	put_key(c, t2, to)


## the scene as it plays at t with constraint i off, posed on B
static func _off(S: Scene, B: Body, i: int, t: float) -> void:
	var c: Dictionary = S.cons[i]
	var had := c.has("mute")
	var m = c.get("mute", false)
	c["mute"] = true
	S.apply(B, t)
	if had:
		c["mute"] = m
	else:
		c.erase("mute")


## RELEASE KEEPING THE POSE (Blender's Apply / "Disable and Keep Transform", research doc section 4): a hand / foot's
## constrained pose at t is written into the card at the playhead (LimbIK.snap_fk's fixed point, with this constraint
## off instead of the IK), then the influence is keyed: held as it was one frame before t, 0 at t. The limb hands over
## to the cards at t without a jump. Needs the playhead on a card. Returns snap_fk's report (+ "why" when refused)
static func release_keep(S: Scene, B: Body, i: int, t: float) -> Dictionary:
	var c: Dictionary = S.cons[i]
	var owner := String(c.get("owner", ""))
	if not owner in LimbIK.LIMBS:
		return {"ok": false, "why": "not_limb"}
	if weight(c, t) <= 0.0:
		return {"ok": false, "why": "off"}
	if LimbIK.card_at(S, t) < 0:
		return {"ok": false, "why": "no_card"}
	var dt := 1.0 / maxf(float(S.fps), 1.0)
	var before := weight(c, t - dt) if t - dt > -1e-9 else -1.0
	var r := LimbIK.snap_fk(S, B, owner, t, func(): _off(S, B, i, t))
	if not r["ok"]:
		r["why"] = "no_card"
		return r
	if before >= 0.0:
		var dial := clampf(float(c.get("w", 1.0)), 0.0, 1.0)
		if (c.get("wk", []) as Array).is_empty():
			c["wk"] = [[0.0, 1.0]]
		for k in c["wk"]:
			k[1] = float(k[1]) * dial
		c["w"] = 1.0
		c["wk"] = (c["wk"] as Array).filter(func(k): return float(k[0]) <= t - dt + SAME_T or float(k[0]) > t + SAME_T)
		put_key(c, t - dt, before)
	put_key(c, t, 0.0)
	S.apply(B, t)
	return r


# ---------------------------------------------------------------- the file

## IN THE FILE: "constraints": [{"type", "owner", "target"?: {"kind", "part" | "at" | "prop" | "actor"}, "offset"?:
## {"pos", "rot"}, "w", "wk"?, "mute"?, "height"?}], written only when there is one (a scene without one saves byte for
## byte as before). Offsets to 0.01 mm / 1e-6 so a reload plays where the session did
static func to_file(cons: Array) -> Array:
	return cons.map(func(c):
		var d := {"type": c["type"], "owner": c["owner"]}
		if c.has("target") and not (c["target"] as Dictionary).is_empty():
			d["target"] = _tg_file(c["target"])
		if c.has("offset"):
			var p: Vector3 = c["offset"]["pos"]
			var q: Quaternion = c["offset"]["rot"]
			d["offset"] = {"pos": [snappedf(p.x, 0.00001), snappedf(p.y, 0.00001), snappedf(p.z, 0.00001)],
				"rot": [snappedf(q.x, 0.000001), snappedf(q.y, 0.000001), snappedf(q.z, 0.000001), snappedf(q.w, 0.000001)]}
		if c["type"] == "floor":
			d["height"] = snappedf(float(c.get("height", 0.0)), 0.0001)
		d["w"] = snappedf(clampf(float(c.get("w", 1.0)), 0.0, 1.0), 0.0001)
		if not (c.get("wk", []) as Array).is_empty():
			d["wk"] = (c["wk"] as Array).map(func(k): return [snappedf(float(k[0]), 0.0001), snappedf(clampf(float(k[1]), 0.0, 1.0), 0.0001)])
		if bool(c.get("mute", false)):
			d["mute"] = true
		return d)


static func _tg_file(tg: Dictionary) -> Dictionary:
	var d := {"kind": tg["kind"]}
	match String(tg["kind"]):
		"part":
			d["part"] = tg["part"]
		"point":
			d["at"] = Body._p(tg["at"])
		"prop":
			d["prop"] = int(tg["prop"])
		"actor":
			d["actor"] = int(tg["actor"])
			d["part"] = tg.get("part", "head")
	return d


static func from_file(a: Variant) -> Array:
	var out := []
	if not a is Array:
		return out
	for d in a:
		if not (d is Dictionary and String(d.get("type", "")) in TYPES and d.has("owner")):
			continue
		var c := {"type": String(d["type"]), "owner": String(d["owner"]), "w": clampf(float(d.get("w", 1.0)), 0.0, 1.0), "wk": []}
		if d.get("target") is Dictionary:
			var t: Dictionary = d["target"]
			var tg := {"kind": String(t.get("kind", ""))}
			if t.has("part"):
				tg["part"] = String(t["part"])
			if t.has("at"):
				tg["at"] = Body._v(t["at"])
			if t.has("prop"):
				tg["prop"] = int(t["prop"])
			if t.has("actor"):
				tg["actor"] = int(t["actor"])
			c["target"] = tg
		if d.get("offset") is Dictionary:
			var r: Array = d["offset"].get("rot", [0, 0, 0, 1])
			c["offset"] = {"pos": Body._v(d["offset"].get("pos", [0, 0, 0])),
				"rot": Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized()}
		if c["type"] == "floor":
			c["height"] = float(d.get("height", 0.0))
		for k in d.get("wk", []):
			c["wk"].append([float(k[0]), clampf(float(k[1]), 0.0, 1.0)])
		c["wk"].sort_custom(func(x, y): return x[0] < y[0])
		if bool(d.get("mute", false)):
			c["mute"] = true
		out.append(c)
	return out


## MIRRORED (Scene.MIRROR_SCENE "constraints"), on the FILE form: owner and part targets to their twins, a point's x
## negated, the stored offset reflected as a world transform is (position x negated, turn (q.x, -q.y, -q.z, q.w), as
## LimbIK.mirror_file reflects a hand's turn); props, the weapon and fighters keep their index; times / influence as they were
static func mirror_file(a: Array) -> Array:
	return a.map(func(d):
		var m: Dictionary = (d as Dictionary).duplicate(true)
		m["owner"] = Body.twin(String(d["owner"]))
		if m.has("target"):
			if m["target"].has("part"):
				m["target"]["part"] = Body.twin(String(m["target"]["part"]))
			if m["target"].has("at"):
				var p: Array = m["target"]["at"]
				m["target"]["at"] = [-float(p[0]), float(p[1]), float(p[2])]
		if m.has("offset"):
			var p: Array = m["offset"]["pos"]
			var q: Array = m["offset"]["rot"]
			m["offset"] = {"pos": [-float(p[0]), float(p[1]), float(p[2])], "rot": [float(q[0]), -float(q[1]), -float(q[2]), float(q[3])]}
		return m)
