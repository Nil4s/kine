## hit_reaction.gd - AUTOMATIC HIT REACTIONS (ROADMAP 14, round 52). When one fighter's weapon or limb hits the other
## (Dummy.fighter_hits: where, when, how fast, along what), the struck fighter reacts: the momentum the blow delivers
## turns its body for 0.3-0.6 s, and the result is baked as editable cards over that window. A PLAUSIBLE PHYSICAL
## RESPONSE, NOT A RAGDOLL: no contact with the floor, no gravity over the window, each joint a damped spring back to
## its own animation. The model, its numbers and their sources: docs/research/HIT_REACTION.md.
##
## The steps (all in the struck fighter's body space; the hero's space is mapped by its xf):
##   1. momentum: J = m_eff x v_rel. m_eff = a weapon's effective mass at the contact (the bat's rod about its grip:
##      I_grip / d^2, d = the contact's distance from the grip) or the striking limb's mass. v_rel = the striking spot's
##      velocity (Dummy's hit "vec") minus the struck spot's own velocity from its animation.
##   2. the struck joint j (the joint its part rides on) takes the angular impulse about its own pivot:
##        Omega_j = (p - P_j) x J / I_j     I_j = sum over the pieces distal to j of m (k L)^2 + m d^2   (de Leva)
##      and each ancestor takes CHAIN x the one below it (the momentum runs down the chain and is damped there). A
##      joint's own (local) rate is its world rate minus its parent's, so the world rates add up and nothing is counted
##      twice.
##   3. the pelvis (the whole body's COM) takes the linear shove: v = J / M.
##   4. every joint in the chain is a damped spring back to the animation's angle (WN, ZETA); the pelvis's shove is a
##      spring back to the animation's offset (WN_P, ZETA_P). Joint limits (Body.clamp_ang) are hard stops (a stop kills
##      the velocity into it).
##   5. the deviation blends out over the last RECOVER_S of the window (the body is back on its own animation at the end).
## The window ends at the scene's next card arrival in [0.3, 0.6] s after the hit (so the cards after it keep their times:
## the other fighter's timeline stays in step). The reaction is reduced to cards the way the video import reduces a dense
## capture: the card maker's even spacing (VideoImport.every_for), then the card frames the PLAYED blend needs to replay
## the simulation within REPLAY_DEG (1 deg), checked against Scene.apply itself (its natural easing staggers each joint).
class_name HitReaction
extends RefCounted

## kg, the whole weapon. ESTIMATES, not measured (docs/research/HIT_REACTION.md): a 33 in baseball bat ~0.9 kg, a 1.8 m
## staff ~1.1 kg, a 1.1 m long hammer ~2.5 kg, a dagger ~0.3 kg, a Dane axe 1-2 kg (1.5 kg used, as body.gd's note says).
const WEAPON_KG := {"metal_bat": 0.9, "staff": 1.1, "long_hammer": 2.5, "dagger": 0.3, "long_axe": 1.5}
const MIN_LEVER := 0.2      # m: a contact nearer the grip than this counts as this far (the hand gives: no infinite mass)
const CHAIN := 0.5          # each joint up the chain takes this share of the angular velocity of the one below it
const WN := TAU * 2.5       # rad/s: the joints' spring back to the animation (2.5 Hz)
const ZETA := 0.5
const WN_P := TAU * 1.5     # rad/s: the pelvis's (the COM's) spring back to the animation (1.5 Hz)
const ZETA_P := 0.7
const SUB := 4              # integration steps per card frame (240 Hz)
const SIM_HZ := 60.0        # the card frames: the dense sample rate the card maker reduces
const RECOVER_S := 0.2      # the last part of the window over which the deviation blends out
const WIN_MIN := 0.3
const WIN_MAX := 0.6
const REPLAY_DEG := 1.0     # the baked cards must replay the simulated angles within this (the card maker's tolerance)


## the joint a body part rides on (Body.cap's rule: a WIDE part rides on its joint)
static func joint_of(part: String) -> String:
	return String(Body.WIDE[part][0]) if Body.WIDE.has(part) else part


## the joint and its ancestors up to the pelvis: [j, parent, ..., pelvis]
static func chain(B: Body, j: String) -> Array:
	var out := [j]
	while String(B.parent[out[-1]]) != "":
		out.append(B.parent[out[-1]])
	return out


## Proportions.masses in kg: its fractions of the body (x REF_MASS for the default body, which has no mass set)
static func masses_kg(B: Body) -> Dictionary:
	var mm := Proportions.masses(B)
	if not B.body.has("mass"):
		for s in mm.keys():
			mm[s] = float(mm[s]) * HumanLimits.REF_MASS
	return mm


## the body as rigid pieces at the pose it is in: [{"j", "seg", "m" (kg), "c" (COM, body space), "kl" (radius ACROSS the bone, m), "kL" (radius ALONG it, m),
## "u" (unit, proximal -> distal end), "len" (m)}]. Masses, COM fractions and radii are Proportions.DE_LEVA (de Leva 1996 Table 4, one table for
## the whole app). Segment ends are the ones the table's row names: head = vertex -> cervicale, forearm = elbow -> wrist, hand = wrist -> 3rd
## metacarpale, foot = heel -> toe tip. The trunk (cervicale -> mid hip in the table) is five pieces (pelvis, 3 spine joints, neck) of equal mass
## whose own radii are chosen so that the five add up to de Leva's whole-trunk transverse radius about the trunk COM (see _trunk_radii) and
## whose along-axis radius is the whole trunk's longitudinal radius x the trunk's summed length. NOTE: the slices span pelvis -> head joint (not cervicale -> mid hip),
## so their mean centre is 0.007 H above de Leva's trunk COM (Proportions.com); shifting them rigidly broke the root-continuity bar of I8, so it is left (reported).
static func pieces(B: Body) -> Array:
	var mm := masses_kg(B)
	var sex := String(B.body.get("sex", "male"))
	var t: Dictionary = Proportions.DE_LEVA[sex]
	var out := []
	for j in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01"]:
		out.append(_piece(B, j, "trunk", Body.CHILD[j], float(mm["trunk"]) / 5.0, 0.5, null))
	_trunk_radii(out, sex)
	out.append(_piece(B, "head", "head", "", float(mm["head"]), float(t["head"][1]), null, Proportions.head_top(B), Proportions.cervicale(B)))
	for sd in ["_l", "_r"]:
		out.append(_piece(B, "upperarm" + sd, "upper_arm", "lowerarm" + sd, float(mm["upper_arm"]) / 2.0, float(t["upper_arm"][1]), null))
		out.append(_piece(B, "lowerarm" + sd, "forearm", "hand" + sd, float(mm["forearm"]) / 2.0, float(t["forearm"][1]), null))
		out.append(_piece(B, "hand" + sd, "hand", "", float(mm["hand"]) / 2.0, float(t["hand"][1]), B.E["hand" + sd]))
		out.append(_piece(B, "thigh" + sd, "thigh", "calf" + sd, float(mm["thigh"]) / 2.0, float(t["thigh"][1]), null))
		out.append(_piece(B, "calf" + sd, "shank", "foot" + sd, float(mm["shank"]) / 2.0, float(t["shank"][1]), null))
		out.append(_piece(B, "foot" + sd, "foot", "", float(mm["foot"]) / 2.0, float(t["foot"][1]), null, Proportions.heel(B, sd), Proportions.toe(B, sd)))
	return out


## one piece of table segment `seg`: from joint j to its child (or to `end`, or from `a0` to `b0` when both are given), its COM at `frac` along it
static func _piece(B: Body, j: String, seg: String, child: String, m: float, frac: float, end: Variant, a0 = null, b0 = null) -> Dictionary:
	var a: Vector3 = a0 if a0 is Vector3 else (B.P[j] as Vector3)
	var b: Vector3 = b0 if b0 is Vector3 else (end if end is Vector3 else (B.P[child] as Vector3))
	var sex := String(B.body.get("sex", "male"))
	var L := a.distance_to(b)
	return {"j": j, "seg": seg, "m": m, "c": a.lerp(b, frac), "kl": Proportions.kperp(sex, seg) * L, "kL": Proportions.klong(sex, seg) * L,
		"u": (b - a).normalized() if L > 1e-9 else Vector3.UP, "len": L}


## the five trunk pieces: r_T^2 L^2 (the whole trunk's transverse radius, rms of sagittal and transverse, x the summed length) = mean over
## the pieces of (k^2 + d^2), d = the piece's centre from the trunk's centre; so k^2 = r_T^2 L^2 - mean d^2 (floored at 5 % of r_T^2 L^2),
## and kL = the trunk's longitudinal radius x L (about the long axis a slice is as round as the whole)
static func _trunk_radii(out: Array, sex: String) -> void:
	var L := 0.0
	var C := Vector3.ZERO
	for p in out:
		L += float(p["len"])
		C += (p["c"] as Vector3) / out.size()
	var rt: float = Proportions.kperp(sex, "trunk") * L
	var d2 := 0.0
	for p in out:
		d2 += ((p["c"] as Vector3) - C).length_squared() / out.size()
	var k := sqrt(maxf(rt * rt - d2, 0.05 * rt * rt))
	for p in out:
		p["kl"] = k
		p["kL"] = Proportions.klong(sex, "trunk") * L


## the angular momentum of one piece spinning at world rate w about its own COM: m (kp^2 w + (kL^2 - kp^2)(u . w) u)
static func spin_h(p: Dictionary, w: Vector3) -> Vector3:
	var kp2: float = float(p["kl"]) * float(p["kl"])
	var kl2: float = float(p["kL"]) * float(p["kL"])
	var u: Vector3 = p["u"]
	return float(p["m"]) * (w * kp2 + (kl2 - kp2) * u.dot(w) * u)


## the moment of inertia about joint j's pivot of every piece distal to it (its own chain includes j), scalar
static func inertia(B: Body, pcs: Array, j: String) -> float:
	var I := 0.0
	var P: Vector3 = B.P[j]
	for p in pcs:
		if chain(B, String(p["j"])).has(j):
			var kl: float = p["kl"]
			I += float(p["m"]) * (kl * kl + ((p["c"] as Vector3) - P).length_squared())
	return I


## the world axes of joint j's bend, side and twist (its parent's world rotation applied to the rest axes)
static func axes(B: Body, j: String) -> Array:
	var pj: String = B.parent[j]
	var gp: Quaternion = B.G[pj] if pj != "" else Quaternion.IDENTITY
	return [gp * (B.b_ax[j] as Vector3), gp * (B.a_ax[j] as Vector3), gp * (B.t_ax[j] as Vector3)]


## a world angular velocity (rad/s) as the joint's (bend, side, twist) rates (deg/s)
static func to_local(ax: Array, w: Vector3) -> Vector3:
	var M := Basis(ax[0] as Vector3, ax[1] as Vector3, ax[2] as Vector3)
	if absf(M.determinant()) < 1e-9:
		return Vector3.ZERO
	return (M.inverse() * w) * (180.0 / PI)


## the striking weapon's effective mass at the contact (kg): the rod about its grip, I_grip / d^2 (d = the contact's
## distance from the grip, at least MIN_LEVER). Bat: the grip is hold_u (from the knob); the off-hand weapon: its handle.
## A limb or the body strikes with the mass of the pieces it moves (one side for a limb).
static func strike_mass(hit: Dictionary, Bs: Body) -> float:
	var part: String = hit["part"]
	if Body.is_wep(part):
		var is2 := Body.WEAPON2.has(part)
		var kind: String = Bs.wep2_kind if is2 else Bs.wep_kind
		var L: float = Bs.wep2_len() if is2 else Bs.wep_len
		var g: float = float(Body.KINDS[kind]["handle"]) if is2 else Bs.hold_u()
		var m: float = float(WEAPON_KG.get(kind, 0.9))
		var Ig := m * (L * L / 12.0 + pow(L * 0.5 - g, 2.0))
		var d := maxf(absf(float(hit["u"]) - g), MIN_LEVER)
		return Ig / (d * d)
	var mm := masses_kg(Bs)
	var segs := ["head", "trunk"]
	var sided := false
	if part.begins_with("upperarm"):
		segs = ["upper_arm", "forearm", "hand"]
		sided = true
	elif part.begins_with("lowerarm"):
		segs = ["forearm", "hand"]
		sided = true
	elif part.begins_with("hand"):
		segs = ["hand"]
		sided = true
	elif part.begins_with("thigh"):
		segs = ["thigh", "shank", "foot"]
		sided = true
	elif part.begins_with("calf"):
		segs = ["shank", "foot"]
		sided = true
	elif part.begins_with("foot"):
		segs = ["foot"]
		sided = true
	var m_all := 0.0
	for s in segs:
		m_all += float(mm[s])
	return m_all / 2.0 if sided else m_all


## the window's end for a hit at t_hit: the first card arrival in [t_hit + WIN_MIN, t_hit + WIN_MAX] (the cards after it
## keep their times), else t_hit + WIN_MAX (the window ends in the middle of a long card move) or t_hit + WIN_MIN past the end
static func window_end(S: Scene, t_hit: float) -> float:
	var ts := S.times()
	for i in S.cards.size():
		var a: float = ts[i][1]
		if a >= t_hit + WIN_MIN - 1e-9:
			return minf(a, t_hit + WIN_MAX)
	return t_hit + WIN_MIN


## the recovery weight at time t: 1 until the last RECOVER_S of the window, then smoothstep to 0 at t_end
static func _recover(t: float, t_end: float) -> float:
	var t_b := t_end - RECOVER_S
	if t <= t_b:
		return 1.0
	var s := clampf((t - t_b) / RECOVER_S, 0.0, 1.0)
	return 1.0 - s * s * (3.0 - 2.0 * s)


## THE REACTION. S = the struck fighter's scene, B its body (posed by its scene at any time), xf its space -> the hero's,
## hit = a Dummy.fighter_hits row (t, at, vec, part (the striker's part), on (the struck part), u, kind), Bs = the striker's
## body (its weapon's data). Nothing is written: returns {"ok", "why", "cards" (the scene's new card list), "t0", "t1",
## "J" (kg m/s, body space), "m_eff", "v_rel" (m/s), "peak" (rad/s, the struck joint's world angular speed), "shove" (m/s,
## the pelvis's start), "M" (kg), "joints" (the chain), "dense" ([{"ang", "off"}] per card frame, the sim's values),
## "base" ([{"ang", "off"}] the animation's per card frame), "fine" (the 240 Hz sim, same keys)}. B's pose is put back.
static func react(S: Scene, B: Body, xf: Transform3D, hit: Dictionary, Bs: Body) -> Dictionary:
	var fail := {"ok": false, "why": ""}
	var keep := B.state()
	var t_hit: float = hit["t"]
	var on: String = hit["on"]
	if Body.is_wep(on) or not B.parent.has(joint_of(on)):
		fail["why"] = "the struck part %s is not a body part" % on
		B.set_state(keep)
		return fail
	var jh := joint_of(on)
	# 1. the contact in the body's space, and the struck spot's velocity from the animation (one card frame apart)
	S.apply(B, t_hit)
	var P0: Dictionary = B.P.duplicate()
	var G0: Dictionary = B.G.duplicate()
	var pv: Vector3 = xf.affine_inverse() * (hit["at"] as Vector3)
	var lp: Vector3 = G0[jh].inverse() * (pv - (P0[jh] as Vector3))
	var h1 := 1.0 / SIM_HZ
	S.apply(B, maxf(0.0, t_hit - h1))
	var spot_before: Vector3 = (B.P[jh] as Vector3) + (B.G[jh] as Quaternion) * lp
	S.apply(B, t_hit)
	var spot_now: Vector3 = (P0[jh] as Vector3) + (G0[jh] as Quaternion) * lp
	var v_struck_body: Vector3 = (spot_now - spot_before) / h1
	var vrel_hero: Vector3 = (hit["vec"] as Vector3) - xf.basis * v_struck_body
	var m_eff := strike_mass(hit, Bs)
	var J_hero := vrel_hero * m_eff
	var J: Vector3 = xf.basis.inverse() * J_hero
	# 2. the pieces, the chain and the impulse on it
	var pcs := pieces(B)
	var M := 0.0
	for p in pcs:
		M += float(p["m"])
	var path := chain(B, jh)
	var n_path := path.size()
	var Om: Array = []   # world angular velocity (rad/s) of each joint on the chain
	var I0 := inertia(B, pcs, jh)
	var w0: Vector3 = (pv - (P0[jh] as Vector3)).cross(J) / maxf(I0, 1e-9)
	for i in n_path:
		Om.append(w0 * pow(CHAIN, i))
	var ax := {}
	var v0 := {}
	for i in n_path:
		var j: String = path[i]
		ax[j] = axes(B, j)
		var above := Vector3.ZERO   # the pelvis's parent is the root: nothing above it
		if i + 1 < n_path:
			above = Om[i + 1]
		v0[j] = to_local(ax[j], (Om[i] as Vector3) - above)   # deg/s
	var shove0: Vector3 = J / maxf(M, 1e-9)
	# the animation per card frame (the base the deviation rides on)
	var T := window_end(S, t_hit) - t_hit
	var t_end := t_hit + T
	var n := maxi(1, int(round(T * SIM_HZ)))
	var h := T / float(n)
	var dts := h / float(SUB)
	var base_ang: Array = []
	var base_off: Array = []
	for k in n + 1:
		S.apply(B, t_hit + h * float(k) if k < n else t_end)
		base_ang.append(B.ang.duplicate())
		base_off.append(B.offset)
	# 3. the sim (the deviation d from the animation, in deg; x = the pelvis's shove, m)
	var d := {}
	var vel := {}
	for j in path:
		d[j] = Vector3.ZERO
		vel[j] = v0[j]
	var x := Vector3.ZERO
	var xv := shove0
	var peak_w := 0.0
	var W0 := Vector3.ZERO
	for i in n_path:
		W0 += _world_rate(ax[path[i]], vel[path[i]])
	peak_w = W0.length()
	var dense: Array = [{"ang": {}, "off": base_off[0]}]
	for j in path:
		(dense[0]["ang"] as Dictionary)[j] = base_ang[0][j]
	var fine: Array = []
	for k in n:
		for s in SUB:
			var f := float(s + 1) / float(SUB)
			var tt := t_hit + h * float(k) + dts * float(s + 1)
			var base_now := {}
			for j in path:
				base_now[j] = (base_ang[k][j] as Vector3).lerp(base_ang[k + 1][j] as Vector3, f)
			var off_now: Vector3 = (base_off[k] as Vector3).lerp(base_off[k + 1] as Vector3, f)
			for j in path:
				var dj: Vector3 = d[j]
				var vj: Vector3 = vel[j]
				vj += (-WN * WN * dj - 2.0 * ZETA * WN * vj) * dts
				dj += vj * dts
				var th: Vector3 = (base_now[j] as Vector3) + dj
				var cl: Vector3 = B.clamp_ang(j, th)
				var over := th - cl
				if over != Vector3.ZERO:   # a joint stop: the deviation comes back to the stop, the velocity into it dies
					dj -= over
					vj = Vector3(0.0 if over.x != 0.0 else vj.x, 0.0 if over.y != 0.0 else vj.y, 0.0 if over.z != 0.0 else vj.z)
				d[j] = dj
				vel[j] = vj
			xv += (-WN_P * WN_P * x - 2.0 * ZETA_P * WN_P * xv) * dts
			x += xv * dts
			var W := Vector3.ZERO
			for i in n_path:
				W += _world_rate(ax[path[i]], vel[path[i]])
			peak_w = maxf(peak_w, W.length())
			var wt := _recover(tt, t_end)
			var ang_out := {}
			for j in path:
				ang_out[j] = (base_now[j] as Vector3) + wt * (d[j] as Vector3)
			var off_out: Vector3 = off_now + wt * x
			fine.append({"t": tt, "ang": ang_out, "off": off_out})
			if s + 1 == SUB:
				dense.append({"ang": ang_out, "off": off_out})
	# 4. the card frames: the sim's pose at each, written onto the body and read as a card pose
	var dense_cards: Array = []
	for k in n + 1:
		B.ang = (base_ang[k] as Dictionary).duplicate()
		var da: Dictionary = dense[k]["ang"]
		for j in path:
			B.ang[j] = da[j]
		B.offset = dense[k]["off"]
		B.fk()
		dense_cards.append({"name": "hit %d" % k, "pose": B.to_dict(), "move": h if k > 0 else -1.0, "hold": 0.0,
			"ease": "linear"})
	var base_out: Array = []
	for k in n + 1:
		base_out.append({"ang": base_ang[k], "off": base_off[k]})
	# 5. the keys: the card maker's even spacing, then every card frame the PLAYED blend (Scene.apply: natural easing, each
	# joint's own lag) misses the simulated pose by more than REPLAY_DEG at, the worst 240 Hz step first
	var keys := _keys(dense_cards, h, B, path, fine, t_hit, S.fps)
	var cand := _cand(dense_cards, keys, h)
	# 6. the splice: the cards before the hit (the last one's hold ends where the anchor's move starts), the anchor at the
	# hit (the animation's pose there), the keys, then the cards after the window with their own times (the card at the
	# window's end is replaced by the last key, which is the animation's pose there)
	var ts := S.times()
	var before: Array = []
	var after: Array = []
	for i in S.cards.size():
		var a: float = ts[i][1]
		var c: Dictionary = S.cards[i].duplicate(true)
		if a <= t_hit + 1e-9:
			before.append(c)
		elif a > t_end + 1e-9:
			after.append(c)
	var anchor_move := clampf(t_hit - float(ts[before.size() - 1][1]), 0.001, 0.1)
	var last: Dictionary = before[-1]
	last["hold"] = maxf(0.0, t_hit - anchor_move - float(ts[before.size() - 1][1]))
	var anchor: Dictionary = (cand[0] as Dictionary).duplicate(true)
	anchor["move"] = anchor_move
	anchor["name"] = "hit at"
	var out: Array = before.duplicate()
	out.append(anchor)
	for k in range(1, cand.size()):
		out.append((cand[k] as Dictionary).duplicate(true))
	out.append_array(after)
	if after.is_empty():
		(out[-1] as Dictionary)["hold"] = 0.3
	B.set_state(keep)
	return {"ok": true, "why": "", "cards": out, "t0": t_hit, "t1": t_end, "J": J, "m_eff": m_eff,
		"v_rel": vrel_hero.length(), "peak": peak_w, "shove": shove0.length(), "M": M, "joints": path,
		"dense": dense, "base": base_out, "fine": fine, "x_end": x, "keys": keys}


## the candidate reduced scene's cards: the keys (sorted card frame indices) with their moves in card-frame time
static func _cand(dense: Array, keys: Array, h: float) -> Array:
	var out := []
	var prev := 0
	for i in keys:
		var c: Dictionary = (dense[i] as Dictionary).duplicate(true)
		c["move"] = -1.0 if i == 0 else float(i - prev) * h
		c["hold"] = 0.0
		out.append(c)
		prev = i
	return out


## the keys: the card maker's even spacing (every_for at SIM_HZ) and the first card frame, then the card frame nearest the
## worst miss of the played blend, again and again until every fine step replays within REPLAY_DEG (or every frame is a key)
static func _keys(dense: Array, h: float, B: Body, path: Array, fine: Array, t_hit: float, fps: int) -> Array:
	var n := dense.size() - 1
	var every := VideoImport.every_for(SIM_HZ)
	var on := {0: true, n: true}
	for i in n + 1:
		if i % every == 0:
			on[i] = true
	while true:
		var ks: Array = on.keys()
		ks.sort()
		var S2 := Scene.new()
		S2.fps = fps
		S2.cards = _cand(dense, ks, h)
		var worst := 0.0
		var at := 0.0
		for row in fine:
			var rel := float(row["t"]) - t_hit
			S2.apply(B, rel)
			var e := 0.0
			for j in path:
				var a: Vector3 = (row["ang"] as Dictionary)[j]
				var g: Vector3 = B.ang[j]
				e = maxf(e, maxf(absf(a.x - g.x), maxf(absf(a.y - g.y), absf(a.z - g.z))))
			if e > worst:
				worst = e
				at = rel
		if worst <= REPLAY_DEG:
			break
		var k0 := clampi(int(round(at / h)), 0, n)
		var found := -1
		for dd in n + 1:
			for cnd in [k0 - dd, k0 + dd]:
				if found < 0 and cnd >= 0 and cnd <= n and not on.has(cnd):
					found = cnd
			if found >= 0:
				break
		if found < 0:
			break
		on[found] = true
	var out: Array = on.keys()
	out.sort()
	return out


## the world angular velocity (rad/s) of a joint's rate vector (deg/s, bend/side/twist) on its axes
static func _world_rate(ax: Array, rate: Vector3) -> Vector3:
	var r := rate * (PI / 180.0)
	return (ax[0] as Vector3) * r.x + (ax[1] as Vector3) * r.y + (ax[2] as Vector3) * r.z
