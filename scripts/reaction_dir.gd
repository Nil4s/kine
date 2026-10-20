## reaction_dir.gd - I33 REACTION DIRECTION. For every contact of a two-fighter scene that lands on a body part (a Dummy.fighter_hits row, kind
## hit / struck; a weapon-on-weapon clash or a block is not a hit on the body), the blow's impulse J comes from HitPhysics.measure (I2: contact
## point, relative velocity, effective strike mass, reduced mass; J in the struck body's space) and the struck body's own motion is read from its
## scene over the 0.5 s before and the 0.3 s after the contact, at 60 Hz, on the body (Scene.apply):
##   COM       Balance.com (de Leva masses); SEGMENT = the struck spot (the contact point carried on the struck joint, as HitPhysics.measure does);
##   TRUNK     the orientation of spine_03.
## Velocity change = the mean velocity over the 0.1 s after the contact minus the mean over the 0.1 s before (the animation's own motion up to
## the contact is what the blow changes). The judgement (thresholds are HEURISTICS, not measured cut-offs):
##   (a) DIRECTION  the COM's velocity change within DIR_DEG (45) of J, and the struck segment's within DIR_DEG too; a change under MIN_DV is "no reaction".
##       Real humans (heuristic, no table): a pushed standing body's COM accelerates along the net force on it; the feet's friction adds only
##       a sideways/backward bias of a few tens of degrees, hence 45.
##   (b) ROTATION   the trunk turns about r x J (r = contact point - COM): the trunk's angular-velocity change has a POSITIVE component along
##       r x J. Not judged when the lever is shorter than MIN_LEVER (0.10 m: the blow goes through the COM; no torque to speak of).
##   (c) ONSET      the struck segment's speed must not start to RISE more than one frame before the contact: the onset is found by walking back from
##       the peak speed (in the window) while the speed keeps rising by more than a sample's noise; earlier than the contact by more than a
##       frame, with at least PRE_RISE of the rise already gone and 0.1 m/s of it, is a PRE-FLINCH (the body answers a blow it has not felt).
##   (d) MAGNITUDE  |COM velocity change| against |J| / M (M = the body's mass, the pieces' sum): a ratio inside [MAG_LO, MAG_HI] = [0.5, 2].
## FIXES (one per flagged hit, nothing written): "retime" (only the onset is wrong): the cards of the early reaction are delayed to the contact
## frame (the card before gives the difference as hold; the last hold gives it back if it can); "regenerate" (anything else): the window's
## poses are held at the contact pose and HitReaction.react (the physics reaction of I2's card maker) is baked onto it from the contact, shaped by my usual (I46, hit_habits.gd) when it has one.
class_name ReactionDir
extends RefCounted

const HZ := 60.0
const PRE_S := 0.5
const POST_S := 0.3
const VEL_S := 0.1
const DIR_DEG := 45.0
const MIN_DV := 0.01        # m/s: a change smaller than this is no reaction at all
const MIN_LEVER := 0.10     # m
const MAG_LO := 0.5
const MAG_HI := 2.0
const PRE_RISE := 0.25
const PRE_ABS := 0.1        # m/s
const TRUNK := "spine_03"


static func new_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


static func _angle(a: Vector3, b: Vector3) -> float:
	if a.length() < 1e-9 or b.length() < 1e-9:
		return 180.0
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


## the angular velocity (rad/s, body space) that takes orientation qa to qb in dt
static func _omega(qa: Quaternion, qb: Quaternion, dt: float) -> Vector3:
	var d := qb * qa.inverse()
	if d.w < 0.0:
		d = Quaternion(-d.x, -d.y, -d.z, -d.w)
	var ang := 2.0 * acos(clampf(d.w, -1.0, 1.0))
	var s := sqrt(maxf(1.0 - d.w * d.w, 0.0))
	if s < 1e-8 or ang < 1e-9:
		return Vector3.ZERO
	return Vector3(d.x, d.y, d.z) / s * (ang / dt)


static func total_mass(B: Body) -> float:
	var m := 0.0
	for p in HitReaction.pieces(B):
		m += float(p["m"])
	return m


## the body's motion around the contact: {"h", "k0" (index of the contact), "com": [Vector3], "seg": [Vector3], "q": [Quaternion]}
static func series(S: Scene, B: Body, hit: Dictionary, xf: Transform3D) -> Dictionary:
	var keep := B.state()
	var jh := HitReaction.joint_of(String(hit["on"]))
	var t_c: float = hit["t"]
	S.apply(B, t_c)
	var pv: Vector3 = xf.affine_inverse() * (hit["at"] as Vector3)
	var lp: Vector3 = (B.G[jh] as Quaternion).inverse() * (pv - (B.P[jh] as Vector3))
	var h := 1.0 / HZ
	var n_pre := int(round(PRE_S * HZ))
	var n_post := int(round(POST_S * HZ))
	var com := []
	var seg := []
	var q := []
	var ts := []
	for k in range(-n_pre, n_post + 1):
		var t := maxf(0.0, t_c + float(k) * h)
		S.apply(B, t)
		ts.append(t)
		com.append(Balance.com(B))
		seg.append((B.P[jh] as Vector3) + (B.G[jh] as Quaternion) * lp)
		q.append(B.G[TRUNK])
	S.apply(B, t_c)
	var r0: Vector3 = pv - Balance.com(B)
	B.set_state(keep)
	return {"h": h, "k0": n_pre, "t": ts, "com": com, "seg": seg, "q": q, "r": r0, "pv": pv}


## the walk back from the peak speed: the index where the rise began
static func onset_index(speed: Array, k_lo: int, k_hi: int) -> Dictionary:
	var pk := k_lo
	for k in range(k_lo, k_hi + 1):
		if float(speed[k]) > float(speed[pk]):
			pk = k
	var eps := maxf(0.01, 0.02 * float(speed[pk]))
	var i := pk
	while i > 1 and float(speed[i]) - float(speed[i - 1]) > eps:
		i -= 1
	return {"on": i, "peak": pk}


## THE JUDGEMENT of one contact row. S, B = the struck fighter's scene and body, xf its place in the hero's space, hit a fighter_hits row,
## Bs the striker's body (Ss its scene, for a weapon's arm). {"ok", "why", plus the numbers (see below), "flags": ["direction", "rotation",
## "pre-flinch", "magnitude"], "bad"}.
static func judge(S: Scene, B: Body, xf: Transform3D, hit: Dictionary, Bs: Body, Ss: Scene = null) -> Dictionary:
	var blow := HitPhysics.measure(S, B, xf, hit, Bs, Ss)
	if not blow["ok"]:
		return {"ok": false, "why": String(blow["why"]), "flags": [], "bad": false}
	var J: Vector3 = blow["J"]
	var sr := series(S, B, hit, xf)
	var h: float = sr["h"]
	var k0: int = sr["k0"]
	var kv := int(round(VEL_S * HZ))
	var com: Array = sr["com"]
	var seg: Array = sr["seg"]
	var q: Array = sr["q"]
	var v_com := ((com[k0 + kv] as Vector3) - (com[k0] as Vector3)) / (h * kv) - ((com[k0] as Vector3) - (com[k0 - kv] as Vector3)) / (h * kv)
	var v_seg := ((seg[k0 + kv] as Vector3) - (seg[k0] as Vector3)) / (h * kv) - ((seg[k0] as Vector3) - (seg[k0 - kv] as Vector3)) / (h * kv)
	var w_tr := _omega(q[k0] as Quaternion, q[k0 + kv] as Quaternion, h * kv) - _omega(q[k0 - kv] as Quaternion, q[k0] as Quaternion, h * kv)
	var M := total_mass(B)
	var flags := []
	# (a) direction
	var none := v_com.length() < MIN_DV
	var a_com := 180.0 if none else _angle(v_com, J)
	var a_seg := 180.0 if v_seg.length() < MIN_DV else _angle(v_seg, J)
	if a_com > DIR_DEG:   # (the segment's angle is reported: a struck head spins, its spot's change need not follow the COM's)
		flags.append("direction")
	# (b) rotation
	var tau: Vector3 = (sr["r"] as Vector3).cross(J)
	var lever := tau.length() / maxf(J.length(), 1e-9)
	var judged := lever >= MIN_LEVER
	var turn := w_tr.dot(tau.normalized()) if tau.length() > 1e-9 else 0.0   # rad/s along r x J
	var turn_ok := (not judged) or turn > 0.0
	if not turn_ok:
		flags.append("rotation")
	# (c) onset
	var speed := []
	speed.append(0.0)
	for k in range(1, seg.size()):
		speed.append(((seg[k] as Vector3) - (seg[k - 1] as Vector3)).length() / h)
	var on := onset_index(speed, 1, seg.size() - 1)
	var i_on: int = on["on"]
	var pk: int = on["peak"]
	var rise_all := float(speed[pk]) - float(speed[i_on])
	var pk_pre := float(speed[i_on])
	for k in range(i_on, k0 + 1):
		pk_pre = maxf(pk_pre, float(speed[k]))
	var rise_pre := pk_pre - float(speed[i_on]) if i_on < k0 else 0.0
	if float(speed[pk]) < 0.05:   # the spot never moves: there is no onset to judge
		i_on = k0
		rise_pre = 0.0
	var frame := 1.0 / float(maxi(1, S.fps))
	var onset_ms := float(i_on - k0) * h * 1000.0
	var pre := i_on < k0 and float(k0 - i_on) * h > frame + 1e-6 and rise_pre >= PRE_ABS and rise_pre >= PRE_RISE * rise_all
	if pre:
		flags.append("pre-flinch")
	# (d) magnitude
	var expect := J.length() / maxf(M, 1e-9)
	var ratio := v_com.length() / maxf(expect, 1e-9)
	if ratio < MAG_LO or ratio > MAG_HI:
		flags.append("magnitude")
	var hero_b := xf.basis
	return {"ok": true, "why": "", "t": float(hit["t"]), "on": String(hit["on"]), "J": J, "Jn": J.length(), "M": M, "angle": a_com, "seg_angle": a_seg,
		"none": none, "turn": turn, "judged_turn": judged, "lever": lever, "turn_ok": turn_ok, "onset_ms": onset_ms, "pre": pre, "ratio": ratio,
		"dv": v_com.length(), "flags": flags, "bad": not flags.is_empty(), "at": hit["at"], "J_h": hero_b * J, "p_h": hero_b * (v_com * M),
		"onset_t": float((sr["t"] as Array)[i_on])}


## a short line of the numbers
static func line(r: Dictionary) -> String:
	if not r["ok"]:
		return String(r["why"])
	return "%.2f s  %s  J %.1f N s  direction %s  rotation %s  onset %+.0f ms  magnitude x%.2f" % [
		float(r["t"]), String(r["on"]).replace("_", " "), float(r["Jn"]),
		"none" if r["none"] else "%.0f deg (seg %.0f)" % [float(r["angle"]), float(r["seg_angle"])],
		("%+.2f rad/s" % float(r["turn"])) if r["judged_turn"] else "n/a (lever %.0f cm)" % (float(r["lever"]) * 100.0),
		float(r["onset_ms"]), float(r["ratio"])]


# ------------------------------------------------------------------------------------------------ the fixes

## the fix of one judged contact: {"ok", "why", "scene" (a clone with the new cards), "kind": "retime" / "regenerate", "msg", "after" (the judgement
## of the new scene)}. Nothing of S is written.
static func fix(S: Scene, B: Body, xf: Transform3D, hit: Dictionary, Bs: Body, res: Dictionary, Ss: Scene = null, hab: Variant = null) -> Dictionary:
	if not res["ok"] or not res["bad"]:
		return {"ok": false, "why": "this hit's reaction is fine: nothing to fix (pick a flagged hit)"}
	var sc: Scene = S.clone()
	var t_c: float = hit["t"]
	var msg := ""
	var kind := ""
	var cur := res
	if "pre-flinch" in res["flags"]:   # first the early start is moved to the contact frame
		var d: float = t_c - float(res["onset_t"])
		var ts := sc.times()
		var ci := -1
		for i in sc.cards.size():
			if float(ts[i][1]) >= float(res["onset_t"]) - 1.5 / float(sc.fps):
				ci = i
				break
		if ci < 1:
			return {"ok": false, "why": "the early reaction has no card before it to delay: put a key before the hit, then try again"}
		(sc.cards[ci - 1] as Dictionary)["hold"] = snappedf(float(sc.cards[ci - 1]["hold"]) + d, 0.0001)
		var last: Dictionary = sc.cards[-1]
		if float(last["hold"]) >= d + 0.2:
			last["hold"] = snappedf(float(last["hold"]) - d, 0.0001)
		kind = "retime"
		msg = "the reaction starts %.0f ms later, at the contact frame (%s)" % [d * 1000.0, Units.time(t_c, sc.fps)]
		cur = judge(sc, B, xf, hit, Bs, Ss)
	if not kind.is_empty() and not cur["bad"]:
		return {"ok": true, "why": "", "scene": sc, "kind": kind, "msg": msg, "after": cur}
	if cur["ok"] and cur["bad"]:
		var keep := B.state()
		sc.apply(B, t_c)
		var held: Dictionary = B.to_dict()
		B.set_state(keep)
		var t_end := HitReaction.window_end(sc, t_c)
		var ts2 := sc.times()
		for i in sc.cards.size():
			var a: float = ts2[i][1]
			if a > t_c + 1e-9 and a <= t_end + 1e-9:
				(sc.cards[i] as Dictionary)["pose"] = held.duplicate(true)
		var r := HitReaction.react(sc, B, xf, hit, Bs, hab)
		if not r["ok"]:
			return {"ok": false, "why": "no reaction could be made: %s" % r["why"]}
		# the card maker's impulse (its strike mass x relative speed) is scaled to the hit physics' J (HitPhysics.measure), so both name one blow
		var jr: float = (r["J"] as Vector3).length()
		if jr > 1e-6 and res["Jn"] > 1e-6 and absf(float(res["Jn"]) / jr - 1.0) > 0.02:
			var vrel_h: Vector3 = xf.basis * (r["J"] as Vector3) / maxf(float(r["m_eff"]), 1e-9)
			var h2 := hit.duplicate()
			h2["vec"] = (hit["vec"] as Vector3) - vrel_h + vrel_h * (float(res["Jn"]) / jr)
			r = HitReaction.react(sc, B, xf, h2, Bs, hab)
			if not r["ok"]:
				return {"ok": false, "why": "no reaction could be made: %s" % r["why"]}
		sc.cards = r["cards"]
		msg += ("; then " if not kind.is_empty() else "") + "the reaction is made again from the blow (J %.1f kg m/s) from the contact at %s: the body goes along it and turns about r x J" % [(r["J"] as Vector3).length(), Units.time(t_c, sc.fps)]
		kind = "retime + regenerate" if not kind.is_empty() else "regenerate"
	var after := judge(sc, B, xf, hit, Bs, Ss)
	return {"ok": true, "why": "", "scene": sc, "kind": kind, "msg": msg, "after": after}
