## hit_harder.gd - HIT HARDER (docs/INNOVATIONS.md N065). One call on a strike card: Kine changes the BODY of the strike,
## within limits, so the fist (foot, weapon tip) meets the target faster, and says by how much.
##
## WHAT IS MEASURED (on the clip as it PLAYS, Scene.apply: spline, overlap, pins and grounding included):
##   the contact      the moment the striking end passes closest to where it is at the contact card's arrival in the clip as it
##                    was (that point is the hit's place; searched from 0.1 s before to 1.5 frames after at 240 Hz, then refined
##                    between samples). Before any change it is the arrival itself
##   speed_mps        the end's speed at that moment by Dummy.hits' own rule, |p(t) - p(t - 1/60)| x 60: what the target dummy and
##                    the I2 hit physics read as the blow's speed. The end = the weapon's tip; else the fist / toe point I47 caps
##                    (B.E hand_x / ball_x, SpeedEnv's "hand" / "foot" channel), so the cap and the number are the same point
##   impulse_Ns       J = (1 + e) mu v, mu = m_eff M / (m_eff + M): hit_physics.gd's own blow (I2). m_eff = HitPhysics.strike_mass
##                    at the contact pose (a fist 2.9 kg x mass / 75, Walilko 2005; a weapon the bat + arm operational-space mass
##                    along the blow, Khatib 1987; a foot its de Leva mass). M = a 75 kg dummy's head when the end is above the
##                    striker's shoulders, else its trunk (HitPhysics.struck_mass). e = HitPhysics.RESTITUTION. gain_pct is J's gain
##   (In a clip whose contact card is a STOP - it holds, or eases to rest - the end arrives at almost no speed: a push, not a
##   blow. That is a true reading of the clip; the follow-through lever is what changes it.)
## THE LEVERS, tried in this order (LEVERS), each on the result of the ones before. Follow-through goes first: while the end
## still stops on the contact, a faster path INTO it barely shows there (measured on the punch template: wind-up +0.3 % before
## it, nothing kept). The contact card's POSE is never edited (the hit lands where it was aimed: bar END_KEEP). Each lever is
## tried at full size, then halved (LADDER), and kept at the largest size that keeps every rule below and adds MIN_GAIN to J;
## one stopped by an I47 cap is bisected up toward that cap ("capped"). A lever with two forms tries both (follow-through
## "line" / "arc", sequencing "throw" / "strike") and keeps the stronger:
##   hip_shoulder_turn  the wind-up card (the one before contact) coils further: the pelvis turns up to TURN_DEG and each
##                      spine joint up to SPINE_DEG further AWAY from the strike's turn (clamped to data/body_limits.json:
##                      spine twist +-17), the planted feet re-solved onto their spots (legs by damped least squares,
##                      MoveKnobs' solver). The trunk then turns through more angle in the same time (the hip -> trunk links of
##                      I8's chain, Putnam 1993)
##   wind_up            the wind-up card's striking chain (clavicle, shoulder, elbow [, wrist with a weapon]; hip, knee for a
##                      kick) takes up to WIND_K more of its own angle change away from the contact: a longer path, same time
##   weight_transfer    the wind-up card's hips go up to SHIFT_M back, away from the target (the end's floor direction from the
##                      pelvis at contact), the planted feet re-solved: the weight travels toward the target through the strike
##   follow_through     if the card after contact already carries on (its end further along the wind-up -> contact line), it
##                      goes further the way it goes (its chain and spine twist + FT_K of their own change). If it comes BACK (a
##                      recoil), a "follow-through" card is put in after contact (FT_T of the strike's move, taken from the next
##                      card's move, so every later card keeps its time): "line" = the end on along the way it was going, the
##                      arm / leg and spine solved onto it; "arc" = the chain's and spine's angles carry on by FT_K of the
##                      strike's change (not the elbow / knee: a hinge locks out at contact). The contact's hold moves onto it
##                      and the contact becomes a pass-through (hold 0; "flow" outside a spline scene): the end meets the target
##                      still moving instead of stopping on it
##   sequencing         proximal-to-distal timing (I8: the peaks hip -> trunk -> shoulder -> elbow, Putnam 1993). A plain scene's
##                      contact card gets the measured ease preset "throw" (or "strike", ease_presets.gd) if it raises J. A spline
##                      scene already leads each joint level by Scene.LEAD = 15 ms (hips 75 ms before the hands) and does not read a
##                      card's ease, and a flow run is one curve over the levels' NATURAL overlap: there it reports, it does not act
##   quicker_move       only with allow_retime: the strike's move is shortened (to RETIME_MIN of it at most), the time given to
##                      the contact card's hold so later cards keep their times; the contact comes earlier
## THE RULES every kept lever passes (bars stated in the test before the first run):
##   joint limits       every angle of every card inside data/body_limits.json (Body.clamp_ang changes nothing, 1e-3 deg)
##   I47 human caps     no SpeedEnv channel (hand, foot, elbow, shoulder rotation, knee, pelvis turn, trunk turn) peaks over its
##                      cap on the moves around the strike (or over its old peak, if it was already over): capped at the cap,
##                      and said. A strike whose end already peaks at AT_CAP of its cap is "at the human cap": nothing changes
##   balance            every 60 Hz frame of the strike (wind-up move to the move after contact) whose COM was over the feet
##                      (Balance.read margin >= 0) still is
##   contact time       within 1 frame (1 / fps) of where it was, unless allow_retime; the end passes within END_KEEP of its place
##   planted feet       a foot on the floor on an edited card stays on its spot (ankle and ball within FEET_M, grounded)
##   assertions         every saved N002 line (scene "asserts") that passed still passes
## Read-only until serve() writes the plan as ONE undo step; dry: true answers the same report and writes nothing.
class_name HitHarder
extends RefCounted

const LEVERS := ["follow_through", "hip_shoulder_turn", "wind_up", "weight_transfer", "sequencing", "quicker_move"]
const SPEED_FPS := 60.0    # Dummy.hits' frame rate: speed = |p(t) - p(t - 1/60)| x 60
const SEARCH_HZ := 240.0   # the contact moment is searched at SpeedEnv's 240 Hz
const SEARCH_S := 0.1      # +- this around the old arrival
const MIN_GAIN := 0.5      # %: a lever under this is not worth a change (HEURISTIC: below what a viewer or a dummy could tell)
const AT_CAP := 0.99       # SpeedEnv.AIM: the end's peak at 99 % of its cap is "at the human cap"
const LADDER := [1.0, 0.5, 0.25]
const BISECT := 4          # halvings toward a cap (1/16 of the lever's size)
## THE LEVERS' FULL SIZES: HEURISTIC, mine, sized so a lever is a visible change of the move and not a new move. No paper
## gives "how much more coil"; the limits, caps and balance decide how much of it survives
const TURN_DEG := 20.0     # the pelvis (whole-body) coil
const SPINE_DEG := 10.0    # each spine joint's coil (their range is +-17)
const WIND_K := 0.5        # +50 % of the chain's own wind-up -> contact angle change
const SHIFT_M := 0.08      # 8 cm of hips back on the wind-up
const FT_K := 0.35         # the follow-through continues by 35 % of the strike's angle change
const FT_T := 0.35         # an inserted follow-through card's move, as a share of the strike's move (the same speed)
const RETIME_MIN := 0.6
## m: the end passes within 8 cm of its old contact point, so the blow still lands on the same target part (a head is about 15-20
## cm across; HEURISTIC, mine). First set at 2 cm; the probe showed why that is too tight for a SPLINE scene: its joints read
## the curve ahead of the hands (Scene.LEAD, the thigh 30 ms), so ANY change after the contact moves the played contact pose
## (a roundhouse's follow-through: 5-7 cm at every size tried). The miss is always reported (lands_moved_cm)
const END_KEEP := 0.08
const FEET_M := 0.01       # m: a planted foot's ankle and ball stay within 1 cm (move_knobs.gd's bar)
const LEG_W := 10.0        # the foot's place rows weigh 10x (MoveKnobs.KNOB_W); its turn rows MoveKnobs.ROT_W
const VARIANT_TIE := 0.05  # two variants of a lever within 5 % of each other's blow are a tie (HEURISTIC)
const STOP_MPS := 1.0      # m/s: an end slower than this at contact was stopped on the target by the clip (said in "note")
const FT_MIN_NEXT := 0.05  # s: the card after keeps at least this much of its move when the follow-through takes its share

static var _dummy: Body = null


# ---- the strike ----------------------------------------------------------------------------------------------------

static func _dummy_body() -> Body:
	if _dummy == null:
		_dummy = Body.new()
		_dummy.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		_dummy.fk()
	return _dummy


## who strikes on card i: MoveKnobs.roles plus the side, the chain and the end point
static func roles(S: Scene, B: Body, i: int) -> Dictionary:
	var R := MoveKnobs.roles(S, B, i)
	var tip: String = R["limb"]
	var sd := tip.right(2)
	R["sd"] = sd
	match String(R["kind"]):
		"kick":
			R["chain"] = ["thigh" + sd, "calf" + sd]
			R["part"] = "foot" + sd
			R["cap_ch"] = "foot"
		"weapon":
			R["chain"] = ["clavicle" + sd, "upperarm" + sd, "lowerarm" + sd, "hand" + sd]
			R["part"] = "bat_barrel"
			R["cap_ch"] = "hand"
		_:
			R["chain"] = ["clavicle" + sd, "upperarm" + sd, "lowerarm" + sd]
			R["part"] = tip
			R["cap_ch"] = "hand"
	return R


## the striking end: the weapon's tip, else I47's fist / toe point
static func end_of(B: Body, R: Dictionary) -> Vector3:
	if R["kind"] == "weapon" and B.wep_on:
		return B.wep_point(B.wep_len)
	if R["kind"] == "kick":
		return B.E["ball" + String(R["sd"])]
	return B.E["hand" + String(R["sd"])]


static func _end_at(S: Scene, B: Body, R: Dictionary, t: float) -> Vector3:
	S.apply(B, maxf(t, 0.0))
	return end_of(B, R)


## the blow at the contact: {"t", "speed_mps", "impulse_Ns", "m_eff", "M", "miss_m", "dir"}. X = the old contact point (null:
## the arrival itself); the moment is where the end passes closest to it
static func blow(S: Scene, B: Body, R: Dictionary, i: int, X: Variant) -> Dictionary:
	var tc: float = S.times()[i][1]
	var t := tc
	var miss := 0.0
	if X != null:
		var best := INF
		# from SEARCH_S before to 1.5 frames after the old arrival: the end on its way IN (a follow-through that comes back
		# passes the spot again later; a contact later than 1 frame breaks the time rule anyway, and retime only makes it earlier)
		var n := int(round(SEARCH_S * SEARCH_HZ))
		var n2 := int(ceil(1.5 / float(S.fps) * SEARCH_HZ))
		for k in range(-n, n2 + 1):
			var tk := tc + float(k) / SEARCH_HZ
			if tk < 0.0:
				continue
			var d := _end_at(S, B, R, tk).distance_to(X)
			if d < best - 1e-9:
				best = d
				t = tk
		# refined between the samples either side (a sword tip at 11 m/s moves 4.6 cm per 1/240 s): ternary search, 12 steps
		var a := maxf(t - 1.0 / SEARCH_HZ, 0.0)
		var b := t + 1.0 / SEARCH_HZ
		for it in 12:
			var m1 := a + (b - a) / 3.0
			var m2 := b - (b - a) / 3.0
			if _end_at(S, B, R, m1).distance_to(X) < _end_at(S, B, R, m2).distance_to(X):
				b = m2
			else:
				a = m1
		var tr := (a + b) * 0.5
		var dr := _end_at(S, B, R, tr).distance_to(X)
		if dr < best:
			best = dr
			t = tr
		miss = best
	var p1 := _end_at(S, B, R, t)
	var p0 := _end_at(S, B, R, t - 1.0 / SPEED_FPS)
	var v := (p1 - p0) * SPEED_FPS
	S.apply(B, t)
	var hit := {"part": R["part"], "u": B.wep_len if R["kind"] == "weapon" else 0.0}
	var m_eff := HitPhysics.strike_mass(hit, B, v)
	var shoulder := maxf((B.P["upperarm_l"] as Vector3).y, (B.P["upperarm_r"] as Vector3).y)
	var M := HitPhysics.struck_mass("head" if p1.y > shoulder else "spine_02", _dummy_body())
	var mu := m_eff * M / (m_eff + M)
	return {"t": t, "tc": tc, "speed_mps": v.length(), "impulse_Ns": (1.0 + HitPhysics.RESTITUTION) * mu * v.length(), "m_eff": m_eff, "M": M,
		"miss_m": miss, "at": p1, "on": "head" if p1.y > shoulder else "trunk"}


# ---- the rules -----------------------------------------------------------------------------------------------------

## the I47 channels' peaks over the moves around the strike: {id: peak}
static func _peaks(S: Scene, B: Body, a: int, b: int) -> Dictionary:
	var out := {}
	for c in SpeedEnv.CH:
		out[c["id"]] = 0.0
	for k in range(maxi(a, 1), mini(b, S.cards.size() - 1) + 1):
		var pk := SpeedEnv.card_peaks(S, B, k)
		for id in pk:
			out[id] = maxf(float(out[id]), float(pk[id]["peak"]))
	return out


static func _cap(id: String) -> Dictionary:
	for c in SpeedEnv.CH:
		if c["id"] == id:
			return c
	return {}


## the worst joint outside its range over every card (deg)
static func _limit_worst(S: Scene, B: Body) -> Array:
	var worst := 0.0
	var who := ""
	for ci in S.cards.size():
		var js: Dictionary = S.cards[ci]["pose"]["joints"]
		for j in js:
			if not B.lim.has(j):
				continue
			var v := Vector3(js[j]["bend"], js[j]["side"], js[j]["twist"])
			var d := (B.clamp_ang(j, v) - v).length()
			if d > worst:
				worst = d
				who = "card %d %s" % [ci + 1, j]
	return [worst, who]


## COM over the feet at 60 Hz from t0 to t1: [[t, margin]]
static func _balance(S: Scene, B: Body, t0: float, t1: float) -> Array:
	var out := []
	var n := maxi(1, int(ceil((t1 - t0) * 60.0)))
	for k in n + 1:
		var t := t0 + (t1 - t0) * float(k) / float(n)
		S.apply(B, t)
		var r := Balance.read(B)
		out.append([t, float(r["margin"]) if (r["down"] as Array).size() > 0 else -INF])
	return out


## the reference the rules compare against: the scene as it was
static func baseline(S: Scene, B: Body, R: Dictionary, i: int) -> Dictionary:
	var ts := S.times()
	var n := S.cards.size()
	var t0: float = ts[maxi(i - 1, 0)][0]
	var t1: float = ts[mini(i + 1, n - 1)][1]
	var bl := blow(S, B, R, i, null)
	var asserts := {}
	if not S.asserts.is_empty():
		for r in BodyAssert.run(S, B, S.asserts)["results"]:
			asserts[String(r["line"])] = bool(r.get("pass", false))
	return {"blow": bl, "X": bl["at"], "tc": float(ts[i][1]), "peaks": _peaks(S, B, i - 1, i + 1), "bal": _balance(S, B, t0, t1), "asserts": asserts,
		"fps": float(S.fps), "n0": n, "len": S.length()}


## "" = the changed scene W keeps every rule; else the first one it breaks, in words. shift = how much later than before
## the frames after the contact play (an inserted card's time), ins = an inserted card's index (or -1)
static func judge(W: Scene, B: Body, R: Dictionary, i: int, ref: Dictionary, allow_retime: bool, edited: Array, feet0: Dictionary, min_J := -INF) -> Dictionary:
	var lw := _limit_worst(W, B)
	if float(lw[0]) > 1e-3:
		return {"why": "a joint past its limit: %s by %.2f deg" % [lw[1], lw[0]], "rule": "limits"}
	var bl := blow(W, B, R, i, ref["X"])
	if float(bl["impulse_Ns"]) < min_J:
		# no gain: the slow rules below are not read (they could only reject it too)
		return {"why": "it does not raise the blow (%.2f N s, now %.2f N s)" % [float(bl["impulse_Ns"]), min_J], "rule": "gain", "blow": bl}
	if float(bl["miss_m"]) > END_KEEP:
		return {"why": "the end no longer passes its contact point: %.1f cm off (bar %.0f cm)" % [float(bl["miss_m"]) * 100.0, END_KEEP * 100.0], "rule": "contact", "blow": bl}
	var dt_f := absf(float(bl["t"]) - float(ref["tc"])) * float(ref["fps"])
	if not allow_retime and dt_f > 1.0 + 1e-6:
		return {"why": "the contact moves %.1f frames (bar 1 frame; allow_retime lifts it)" % dt_f, "rule": "time", "blow": bl}
	var extra: int = W.cards.size() - int(ref["n0"])   # an inserted follow-through card
	var pk := _peaks(W, B, i - 1, i + 1 + extra)
	for id in pk:
		var c := _cap(id)
		var top := maxf(float(c["limit"]), float(ref["peaks"][id]))
		if float(pk[id]) > top + 1e-6:
			return {"why": "%s would peak at %s, over the human cap %s (I47: %s)" % [c["label"], SpeedEnv.fmt(float(pk[id]), String(c["unit"])),
				SpeedEnv.fmt(float(c["limit"]), String(c["unit"])), c["cite"]], "rule": "cap", "cap": id, "blow": bl}
	# balance: every frame that was over the feet still is. The frames after an inserted card's time play `shift` later when
	# the card after could not give it the time (else shift = 0: every later card kept its time)
	var shift: float = W.length() - float(ref["len"])
	var tc: float = ref["tc"]
	for row in ref["bal"]:
		if float(row[1]) < 0.0:
			continue
		var t: float = row[0]
		if t > tc + shift + 1e-6:
			t += shift
		W.apply(B, t)
		var r := Balance.read(B)
		var mg: float = float(r["margin"]) if (r["down"] as Array).size() > 0 else -INF
		if mg < 0.0:
			return {"why": "balance lost at %.2f s: the COM %.1f cm outside the feet (it was %.1f cm inside)" % [t, -mg * 100.0, float(row[1]) * 100.0], "rule": "balance", "blow": bl}
	# planted feet on the edited cards
	for k in edited:
		if not feet0.has(k):
			continue
		var Bk := MoveKnobs.scratch(W)
		MoveKnobs.put(Bk, W.cards[k])
		var mv := MoveKnobs._feet_moved(feet0[k], MoveKnobs._feet(Bk), "")
		if mv > FEET_M:
			return {"why": "a planted foot on card %d would move %.1f cm (bar %.0f cm)" % [k + 1, mv * 100.0, FEET_M * 100.0], "rule": "feet", "blow": bl}
	if not (ref["asserts"] as Dictionary).is_empty():
		for r in BodyAssert.run(W, B, W.asserts)["results"]:
			var ln := String(r["line"])
			if bool(ref["asserts"].get(ln, false)) and not bool(r.get("pass", false)):
				return {"why": "the saved assertion '%s' would fail (%s)" % [ln, r.get("say", "")], "rule": "assert", "blow": bl}
	return {"why": "", "rule": "", "blow": bl}


# ---- the levers ----------------------------------------------------------------------------------------------------

static func _feet_on(B: Body) -> Dictionary:
	var f := {}
	for sd in ["_l", "_r"]:
		if MoveKnobs.down(B, sd):
			f[sd] = [B.P["foot" + sd], B.G["foot" + sd]]
	return f


## the planted feet back on their spots (leg = hip 3 axes + knee + ankle; MoveKnobs' damped least squares)
static func _keep_feet(B: Body, f: Dictionary) -> void:
	for sd in f:
		var fj: String = "foot" + sd
		var T: Vector3 = f[sd][0]
		var g0: Quaternion = f[sd][1]
		MoveKnobs._dls(B, MoveKnobs._vars(B, ["thigh" + sd, "calf" + sd, fj]), func() -> PackedFloat64Array:
			var e: Vector3 = T - (B.P[fj] as Vector3)
			return PackedFloat64Array([LEG_W * e.x, LEG_W * e.y, LEG_W * e.z] + MoveKnobs._turn_rows(B, fj, g0, MoveKnobs.ROT_W)))


static func _write(W: Scene, k: int, B: Body) -> void:
	B.apply_grip()
	var pose: Dictionary = (W.cards[k]["pose"] as Dictionary).duplicate(true)
	var td := B.to_dict()
	for key in ["joints", "weapon", "contacts", "offset"]:
		pose[key] = td[key]
	W.cards[k]["pose"] = pose


static func _ang(card: Dictionary, j: String) -> Vector3:
	var x: Dictionary = card["pose"]["joints"].get(j, {"bend": 0.0, "side": 0.0, "twist": 0.0})
	return Vector3(x["bend"], x["side"], x["twist"])


## the strike's turn: + = toward his left (a right-hand / right-leg strike turns that way when it does not say)
static func _turn_sign(S: Scene, R: Dictionary, i: int) -> float:
	var d := wrapf(_ang(S.cards[i], "pelvis").z - _ang(S.cards[i - 1], "pelvis").z, -180.0, 180.0)
	for j in ["spine_01", "spine_02", "spine_03"]:
		d += _ang(S.cards[i], j).z - _ang(S.cards[i - 1], j).z
	if absf(d) < 2.0:
		return 1.0 if R["sd"] == "_r" else -1.0
	return signf(d)


## the striking end onto T: the chain (and the spine, which carries a punch past a straight elbow) by damped least squares,
## the hand / foot keeping its world turn (a fist keeps its line, a weapon its direction)
static func _reach(B: Body, R: Dictionary, T: Vector3) -> void:
	var tip: String = R["limb"]
	var g0: Quaternion = B.G[tip]
	var js: Array = (R["chain"] as Array).duplicate()
	if not js.has(tip):
		js.append(tip)
	if R["kind"] != "kick":
		js += ["spine_01", "spine_02", "spine_03"]
	MoveKnobs._dls(B, MoveKnobs._vars(B, js), func() -> PackedFloat64Array:
		var e: Vector3 = T - end_of(B, R)
		return PackedFloat64Array([LEG_W * e.x, LEG_W * e.y, LEG_W * e.z] + MoveKnobs._turn_rows(B, tip, g0, MoveKnobs.ROT_W)))


## lever k-size on a CLONE: {"S": the scene, "edited": [cards], "na": why it does not apply ("" = it does), "note"}
static func lever(name: String, S: Scene, B: Body, R: Dictionary, i: int, k: float, variant := "") -> Dictionary:
	var W := S.clone()
	var w := i - 1
	var out := {"S": W, "edited": [], "na": "", "note": "", "ins": -1}
	match name:
		"hip_shoulder_turn":
			var s := _turn_sign(S, R, i)
			MoveKnobs.put(B, W.cards[w])
			var f := _feet_on(B)
			var p: Vector3 = B.ang["pelvis"]
			B.set_ang("pelvis", Vector3(p.x, p.y, wrapf(p.z - s * k * TURN_DEG, -180.0, 180.0)))
			for j in ["spine_01", "spine_02", "spine_03"]:
				var a: Vector3 = B.ang[j]
				B.set_ang(j, Vector3(a.x, a.y, a.z - s * k * SPINE_DEG))
			_keep_feet(B, f)
			_write(W, w, B)
			out["edited"] = [w]
			out["note"] = "wind-up card %d: pelvis %+.1f deg, spine %+.1f deg each, turned away from the strike" % [w + 1, -s * k * TURN_DEG, -s * k * SPINE_DEG]
		"wind_up":
			MoveKnobs.put(B, W.cards[w])
			if R["kind"] == "kick" and MoveKnobs.down(B, String(R["sd"])):
				out["na"] = "the kicking foot is on the floor on the wind-up card %d: a longer path there would lift a planted foot" % (w + 1)
				return out
			var f := _feet_on(B)
			for j in R["chain"]:
				var ac := _ang(W.cards[i], j)
				var aw: Vector3 = B.ang[j]
				B.set_ang(j, ac + (aw - ac) * (1.0 + k * WIND_K))
			_keep_feet(B, f)
			_write(W, w, B)
			out["edited"] = [w]
			out["note"] = "wind-up card %d: the %s chain %+.0f %% further back" % [w + 1, R["limb"], k * WIND_K * 100.0]
		"weight_transfer":
			MoveKnobs.put(B, W.cards[i])
			var dir: Vector3 = end_of(B, R) - (B.P["pelvis"] as Vector3)
			dir.y = 0.0
			if dir.length() < 1e-3:
				out["na"] = "the end is straight over the hips at contact: no direction to the target"
				return out
			dir = dir.normalized()
			MoveKnobs.put(B, W.cards[w])
			var f := _feet_on(B)
			if f.is_empty():
				out["na"] = "no foot on the floor on the wind-up card %d: no weight to move" % (w + 1)
				return out
			B.offset = B.offset - dir * (k * SHIFT_M)
			B.fk()
			_keep_feet(B, f)
			_write(W, w, B)
			out["edited"] = [w]
			out["note"] = "wind-up card %d: hips %.1f cm back from the target, so the weight travels into it" % [w + 1, k * SHIFT_M * 100.0]
		"follow_through":
			var n := W.cards.size()
			MoveKnobs.put(B, W.cards[w])
			var e_w := end_of(B, R)
			MoveKnobs.put(B, W.cards[i])
			var e_c := end_of(B, R)
			# the way the end is going as it meets the target, in the clip as it plays
			var tc: float = S.times()[i][1]
			var dir := (_end_at(S, B, R, tc) - _end_at(S, B, R, tc - 1.0 / SPEED_FPS)).normalized()
			if dir.length() < 0.5:
				dir = (e_c - e_w).normalized()
			var reach := k * FT_K * e_c.distance_to(e_w)
			var cont := false
			if i + 1 < n:
				MoveKnobs.put(B, W.cards[i + 1])
				cont = (end_of(B, R) - e_c).dot(e_c - e_w) > 0.0   # along the strike's own line (wind-up -> contact): a recoil comes back
			var h: float = float(W.cards[i]["hold"])
			if cont and variant == "arc":
				out["na"] = "the card after already follows through: one way to extend it (tried as 'line')"
				return out
			if cont:
				# the card after already goes on: it goes further the way it already goes (its chain and spine twist carry
				# on past it by FT_K of their own contact -> follow-through change), so the path keeps its shape
				MoveKnobs.put(B, W.cards[i + 1])
				var e_n0 := end_of(B, R)
				var f := _feet_on(B)
				for j in (R["chain"] as Array) + ["spine_01", "spine_02", "spine_03"]:
					var d := _ang(W.cards[i + 1], j) - _ang(W.cards[i], j)
					if j.begins_with("spine"):
						d = Vector3(0, 0, d.z)
					B.set_ang(j, (B.ang[j] as Vector3) + d * (k * FT_K))
				_keep_feet(B, f)
				_write(W, i + 1, B)
				W.cards[i + 1]["hold"] = float(W.cards[i + 1]["hold"]) + h
				out["note"] = "card %d '%s' follows through further: its end %.1f cm on" % [i + 2, W.cards[i + 1]["name"], end_of(B, R).distance_to(e_n0) * 100.0]
			else:
				# a recoil after the contact: a follow-through card in between, the end on past the contact the way it was going
				MoveKnobs.put(B, W.cards[i])
				var f := _feet_on(B)
				if variant == "arc":
					# the angles carry on: the chain and spine twist past the contact by FT_K of their wind-up -> contact change
					# (an arc stays an arc: a roundhouse's leg, a swing). Not the elbow / knee: a hinge's extension ends at the
					# contact (it locks out); carrying on past it is the shoulder's / hip's and the trunk's job (measured: the
					# roundhouse's last 10 deg of knee in the follow-through's 0.05 s put knee extension over its I47 cap)
					for j in (R["chain"] as Array) + ["spine_01", "spine_02", "spine_03"]:
						if j.begins_with("lowerarm") or j.begins_with("calf"):
							continue
						var d := _ang(W.cards[i], j) - _ang(W.cards[w], j)
						if j.begins_with("spine"):
							d = Vector3(0, 0, d.z)
						B.set_ang(j, (B.ang[j] as Vector3) + d * (k * FT_K))
				else:
					# the end carries on the way it was going (a punch's line), the arm and spine solved onto it
					_reach(B, R, e_c + dir * reach)
				_keep_feet(B, f)
				var mv := maxf(S.move_time(i) * FT_T, 1.0 / SPEED_FPS)
				var card := {"name": "follow-through", "pose": {}, "move": snappedf(mv, 0.0001), "hold": h}
				W.cards.insert(i + 1, card)
				_write(W, i + 1, B)
				var said := ""
				if i + 2 < W.cards.size():
					var nm := S.move_time(i + 1)
					if nm - mv >= FT_MIN_NEXT:
						W.cards[i + 2]["move"] = snappedf(nm - mv, 0.0001)
						said = "; the next card's move gives it the time, so every later card keeps its time"
					else:
						said = "; the cards after it come %.3f s later (the next move is too short to give the time)" % mv
				out["ins"] = i + 1
				out["note"] = "a follow-through card after the contact (%s): the end %.1f cm on past it in %.3f s%s" % ["the angles carry on" if variant == "arc" else "on along its line",
					end_of(B, R).distance_to(e_c) * 100.0, mv, said]
			W.cards[i]["hold"] = 0.0
			if not W.spline:
				W.cards[i]["flow"] = true
			out["edited"] = [i + 1]
		"sequencing":
			if S.spline:
				out["na"] = "a spline scene: every joint level already reads the curve Scene.LEAD = 15 ms ahead of the next (hips 75 ms before the hands), and a card's ease is not read"
				return out
			if S._flow(i):
				out["na"] = "the contact is a pass-through (flow run): one curve from the wind-up through the follow-through over NATURAL's level overlap (hips first, hands last); a card's ease is not read there"
				return out
			if String(S.cards[i].get("ease", "")) == variant:
				out["na"] = "the contact card already eases '%s'" % variant
				return out
			W.cards[i]["ease"] = variant
			out["note"] = "the contact card eases '%s' (ease_presets.gd: %s)" % [variant, "proximal joints peak first, each level later" if variant == "throw" else "the speed peaks late"]
		"quicker_move":
			var m0 := S.move_time(i)
			var x := k * (1.0 - RETIME_MIN)
			W.cards[i]["move"] = snappedf(m0 * (1.0 - x), 0.0001)
			W.cards[i]["hold"] = float(W.cards[i]["hold"]) + (m0 - float(W.cards[i]["move"]))
			out["note"] = "the strike's move %.3f -> %.3f s (the contact %.3f s earlier; later cards keep their times)" % [m0, float(W.cards[i]["move"]), m0 - float(W.cards[i]["move"])]
	return out


# ---- the plan ------------------------------------------------------------------------------------------------------

## "" = card i (0-based) can be made to hit harder; else why not
static func not_strike(S: Scene, i: int) -> String:
	if S.cards.size() < 2:
		return "hit harder needs a scene of 2+ cards with a strike: open one"
	var why := MoveKnobs.not_strike(S, i)
	if why != "":
		return why
	if i < 1:
		return "card 1 has no wind-up card before it"
	return ""


static func _r(b: Dictionary) -> Dictionary:
	return {"speed_mps": snappedf(float(b["speed_mps"]), 0.01), "impulse_Ns": snappedf(float(b["impulse_Ns"]), 0.01)}


static func _pct(a: float, b: float) -> float:
	return snappedf((b / a - 1.0) * 100.0, 0.1) if a > 1e-9 else (0.0 if b <= 1e-9 else 999.9)


## THE PLAN for card i: {"ok", "card", "name", "kind", "before", "after", "gain_pct", "speed_gain_pct", "levers": [...],
## "at_cap", "cards" (the new card list, or null when nothing changed), "contact_t", "said"} or {"ok": false, "error"}
static func plan(S: Scene, i: int, allow_retime := false) -> Dictionary:
	var why := not_strike(S, i)
	if why != "":
		return {"ok": false, "error": why}
	var B := MoveKnobs.scratch(S)
	var keep := B.state()
	var R := roles(S, B, i)
	var ref := baseline(S, B, R, i)
	var b0: Dictionary = ref["blow"]
	var out := {"ok": true, "card": i + 1, "name": String(S.cards[i]["name"]), "kind": R["kind"], "striker": "weapon tip (%s)" % R["limb"] if R["kind"] == "weapon" else String(R["limb"]),
		"before": _r(b0), "levers": [], "at_cap": false, "cards": null, "allow_retime": allow_retime,
		"m_eff_kg": snappedf(float(b0["m_eff"]), 0.01), "target": "a 75 kg dummy's %s (%.1f kg)" % [b0["on"], float(b0["M"])]}
	# at the human cap already?
	var cc := _cap(String(R["cap_ch"]))
	var endpk := float(SpeedEnv.card_peaks(S, B, i)[R["cap_ch"]]["peak"])
	out["cap"] = {"channel": cc["label"], "peak": snappedf(endpk, 0.01), "limit": cc["limit"], "unit": cc["unit"], "cite": cc["cite"]}
	if endpk >= AT_CAP * float(cc["limit"]):
		out["at_cap"] = true
		for nm in LEVERS:
			out["levers"].append({"name": nm, "gain": 0.0, "applied": false, "why_not": "at the human cap: the %s already peaks at %s, the I47 cap is %s (%s)" % [cc["label"],
				SpeedEnv.fmt(endpk, String(cc["unit"])), SpeedEnv.fmt(float(cc["limit"]), String(cc["unit"])), cc["cite"]]})
		out["after"] = out["before"]
		out["gain_pct"] = 0.0
		out["speed_gain_pct"] = 0.0
		out["contact_t"] = snappedf(float(b0["t"]), 0.0001)
		out["said"] = "card %d '%s': at the human cap (%s peaks at %s, the cap is %s): 0 %% gain, nothing changed" % [i + 1, out["name"], cc["label"], SpeedEnv.fmt(endpk, String(cc["unit"])), SpeedEnv.fmt(float(cc["limit"]), String(cc["unit"]))]
		B.set_state(keep)
		return out
	var cur := S
	var curJ := float(b0["impulse_Ns"])
	var cur_blow := b0
	var feet0 := {}
	for k in S.cards.size():
		MoveKnobs.put(B, S.cards[k])
		feet0[k] = MoveKnobs._feet(B)
	for nm in LEVERS:
		var row := {"name": nm, "gain": 0.0, "applied": false, "why_not": ""}
		if nm == "quicker_move" and not allow_retime:
			row["why_not"] = "moves the contact earlier: only with allow_retime"
			out["levers"].append(row)
			continue
		var variants: Array = ["throw", "strike"] if nm == "sequencing" else (["line", "arc"] if nm == "follow_through" else [""])
		var best := {}
		var first_fail := ""
		var cap_fail := {}
		for v in variants:
			var sizes: Array = [1.0] if nm == "sequencing" else LADDER
			var ok_k := -1.0
			for k in sizes:
				var L := lever(nm, cur, B, R, i, k, v)
				if L["na"] != "":
					first_fail = L["na"]
					break
				var jd := judge(L["S"], B, R, i, ref, allow_retime, L["edited"], feet0 if L["ins"] < 0 else _shift_feet(feet0, int(L["ins"])), curJ * (1.0 + MIN_GAIN / 100.0))
				if jd["why"] != "":
					if first_fail == "":
						first_fail = jd["why"]
					if jd["rule"] == "cap" and cap_fail.is_empty():
						cap_fail = {"k": k, "why": jd["why"]}
					if jd["rule"] == "gain":
						break   # a smaller size of it moves the end less: no gain either
					continue
				var J := float(jd["blow"]["impulse_Ns"])
				# a variant wins on the blow; within VARIANT_TIE of it, the one that lands nearer its old spot (it leaves the
				# levers after it more room under END_KEEP)
				var better := best.is_empty() or J > float(best["J"]) * (1.0 + VARIANT_TIE)
				if not better and J >= float(best["J"]) * (1.0 - VARIANT_TIE):
					better = float(jd["blow"]["miss_m"]) < float(best["blow"]["miss_m"])
				if better:
					best = {"J": J, "L": L, "k": k, "blow": jd["blow"], "v": v}
				ok_k = k
				break   # the largest size that keeps every rule (a smaller one moves less)
			# stopped by a cap at a bigger size: bisect up toward it
			if ok_k > 0.0 and not cap_fail.is_empty() and float(cap_fail["k"]) > ok_k:
				var lo := ok_k
				var hi: float = cap_fail["k"]
				for it in BISECT:
					var mid := (lo + hi) * 0.5
					var L2 := lever(nm, cur, B, R, i, mid, v)
					var jd2 := judge(L2["S"], B, R, i, ref, allow_retime, L2["edited"], feet0 if L2["ins"] < 0 else _shift_feet(feet0, int(L2["ins"])), curJ * (1.0 + MIN_GAIN / 100.0))
					if jd2["why"] == "":
						lo = mid
						if float(jd2["blow"]["impulse_Ns"]) > float(best["J"]):
							best = {"J": float(jd2["blow"]["impulse_Ns"]), "L": L2, "k": mid, "blow": jd2["blow"], "v": v}
					else:
						hi = mid
				best["capped"] = cap_fail["why"]
		if best.is_empty():
			row["why_not"] = first_fail if first_fail != "" else "no size of it keeps the rules"
			out["levers"].append(row)
			continue
		var g := _pct(curJ, float(best["J"]))
		if g < MIN_GAIN:
			row["gain"] = g
			row["why_not"] = "it does not raise the blow: %+.1f %% (a lever must add %.1f %%)" % [g, MIN_GAIN]
			out["levers"].append(row)
			continue
		row["gain"] = g
		row["applied"] = true
		row["size"] = snappedf(float(best["k"]), 0.001)
		row["did"] = String(best["L"]["note"])
		if best.has("capped"):
			row["capped"] = "capped at the human cap: at full size " + String(best["capped"])
		elif float(best["k"]) < 1.0 and first_fail != "":
			row["limited"] = "at full size: " + first_fail
		out["levers"].append(row)
		cur = best["L"]["S"]
		curJ = float(best["J"])
		cur_blow = best["blow"]
		if int(best["L"]["ins"]) >= 0:
			feet0 = _shift_feet(feet0, int(best["L"]["ins"]))
	out["after"] = _r(cur_blow)
	out["gain_pct"] = _pct(float(b0["impulse_Ns"]), float(cur_blow["impulse_Ns"]))
	out["speed_gain_pct"] = _pct(float(b0["speed_mps"]), float(cur_blow["speed_mps"]))
	out["contact_t"] = snappedf(float(cur_blow["t"]), 0.0001)
	out["contact_moved_frames"] = snappedf((float(cur_blow["t"]) - float(b0["t"])) * float(S.fps), 0.01)
	out["lands_moved_cm"] = snappedf(float(cur_blow["miss_m"]) * 100.0, 0.1)
	if float(b0["speed_mps"]) < STOP_MPS:
		out["note"] = "before, the end arrived at %.2f m/s: the clip stopped it ON the target (the card holds or eases to rest), a push rather than a blow, so the gain is large" % float(b0["speed_mps"])
	if cur != S:
		out["cards"] = cur.cards
	var applied: Array = out["levers"].filter(func(x): return x["applied"])
	out["said"] = "card %d '%s': %s %.2f -> %.2f m/s, %.2f -> %.2f N s (%+.1f %%)%s" % [i + 1, out["name"], out["striker"], float(b0["speed_mps"]), float(cur_blow["speed_mps"]),
		float(b0["impulse_Ns"]), float(cur_blow["impulse_Ns"]), out["gain_pct"],
		(": " + ", ".join(applied.map(func(x): return "%s %+.1f %%" % [x["name"], x["gain"]]))) if not applied.is_empty() else ": no lever keeps the rules and adds to the blow"]
	B.set_state(keep)
	return out


## feet records by card after a card is inserted at `ins` (the new card has none: it is checked through the rules' balance)
static func _shift_feet(f: Dictionary, ins: int) -> Dictionary:
	var o := {}
	for k in f:
		o[k if int(k) < ins else int(k) + 1] = f[k]
	return o


# ---- the agent's call ----------------------------------------------------------------------------------------------

## serve's `hit_harder` on the live poser m: {card (1-based; default the picked card), dry?, allow_retime?}. Not dry: the
## plan is written as ONE undo step
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var S: Scene = m.S
	var i := int(p.get("card", m.sel_card + 1)) - 1
	var pl := plan(S, i, bool(p.get("allow_retime", false)))
	if not pl["ok"]:
		return pl
	var cards: Variant = pl["cards"]
	pl.erase("cards")
	pl["dry"] = bool(p.get("dry", false))
	pl["undo_steps"] = 0
	pl["changed"] = cards != null
	if cards != null and not pl["dry"]:
		m._step_hint = "Hit harder: card %d %+.1f %%" % [i + 1, float(pl["gain_pct"])]
		var u0: int = m.undo.size()
		m._push_undo()
		m.S.cards = (cards as Array).duplicate(true)
		m._rebuild_cards()
		if m.sel_card >= 0 and m.sel_card < m.S.cards.size():
			Scene.put(m.B, Moves._flat(m.S.cards[m.sel_card]["pose"]))
			m.B.apply_grip()
		m._refresh()
		pl["undo_steps"] = m.undo.size() - u0
	return pl
