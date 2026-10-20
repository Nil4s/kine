## fight_phrase.gd - FIGHT PHRASE BUILDER (ROADMAP I11). Static, no UI (main.gd owns the preview, the ghost and the undo).
## Give it the attacker's cards and it builds the defender's whole answer: for each STRIKE BEAT of the attacker it picks ONE
## defence (a block or a slip, each checked against the real geometry), writes the defender's cards so the defence is in
## place before the contact, and keeps the pair at fighting range, flagging a beat when no distance makes it possible.
## THE BEATS (read off the attacker alone, the tip-speed code the trail and the speed graph use): the striking point (the bat's
##   point nearest the defender's trunk, else the faster palm) is sampled at 60 Hz; a beat is a peak of its speed above
##   MIN_SPEED, the strongest first, no two closer than MIN_GAP. A boxer's jab/cross peaks at 5 to 12 m/s and a bat swing at
##   20+ m/s (Atha 1984, Walilko 2005), so 2.5 m/s only drops the wind-up and the recovery. The contact is the peak's time.
## WHEN (anticipation): the defender reads the wind-up, not the contact. A visual simple reaction time is about 200 ms
##   (Welford 1980; Woods 2015: 190 to 250 ms), so a defence that STARTS moving REACT_S before the contact is a reaction to the
##   wind-up the fighter saw. It ARRIVES LEAD_FRAMES (2) frames before the contact and is held to HOLD_AFTER after it.
## WHICH: every candidate is built (block: the lead or the rear forearm put across the tip's path by limb IK; slip: the spine
##   leaned sideways until the target part is SLIP_OFF off the path), and kept only when its own test passes:
##   block = the forearm meets the tip's path (distance <= the two radii) BEFORE the tip has reached the trunk;
##   slip  = the target part is >= SLIP_OFF (10 cm) farther from the path than before and clear of it.
##   Then the cost: the joint change from the previous pose (degrees summed over joints: the smallest change fits best)
##   plus REPEAT_COST when it is the same KIND as the beat before; a third of the same kind in a row is not allowed.
## RANGE: at each beat the defender's root is moved along the line of the attack (its pelvis toward the striking point) (a step in or out, written into
##   the card's hips offset) to the smallest move at which the striking point is within REACH_AIM of the trunk (the bar is
##   REACH_TOL, 5 cm) and the bodies (hands, forearms and weapons aside: they are the strike and the guard) do not overlap.
##   No such distance: the beat is FLAGGED with the reason and gets no defence.
class_name FightPhrase

const HZ := 60.0
const MIN_SPEED := 2.5      # m/s
const REL_SPEED := 0.4      # and at least this share of the fastest peak: a bat's wind-up and recovery (7 to 10 m/s) are not strikes beside its 37 m/s swings
const EXT_AFTER := 0.15     # s after the speed peak that the full extension is looked for
const MIN_GAP := 0.25       # s between two beats
const REACT_S := 0.2        # s: the defence starts this long before the contact (visual simple reaction time, Welford 1980)
const LEAD_FRAMES := 2      # the defence is in place this many frames before the contact
const HOLD_AFTER := 0.12    # s held after the contact
const MIN_MOVE := 0.04      # s: the least move into a card
const REACH_TOL := 0.05     # m: the bar, the tip within 5 cm of the zone
const REACH_AIM := 0.02     # m: what the range search aims for (inside the bar, so a rounding never fails it)
const SLIP_OFF := 0.10      # m: a slip moves the target part this far off the path
const REPEAT_COST := 60.0   # degrees-equivalent added to a defence of the kind just used
const MAX_RUN := 2          # no more than this many of one kind in a row
const FIST_R := 0.04
const SCAN := 1.0           # m: the range search goes this far each way


static func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


static func _finger(j: String) -> bool:
	return j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky")


# ------------------------------------------------------------------------------------------------ the attacker's beats

## the striking point at the pose AB now holds: the weapon's point at u (u < 0: the tip), else the palm of `hand`
static func spot(AB: Body, hand: String, u: float) -> Vector3:
	if AB.wep_on:
		return AB.wep_point(AB.wep_len if u < 0.0 else u)
	return AB.palm_point(hand)


## [{"t", "hand" ("" with a weapon), "speed"}] sorted by t
static func strikes(A: Scene, AB: Body) -> Array:
	var n := int(ceil(A.length() * HZ))
	var armed := false
	var series := {"tip": [], "hand_l": [], "hand_r": []}
	var pelv := []
	for k in n + 1:
		A.apply(AB, minf(A.length(), float(k) / HZ))
		pelv.append(AB.P["pelvis"])
		armed = armed or AB.wep_on
		series["tip"].append(AB.wep_point(AB.wep_len) if AB.wep_on else Vector3.INF)
		series["hand_l"].append(AB.palm_point("hand_l"))
		series["hand_r"].append(AB.palm_point("hand_r"))
	var cand := []
	for key in (["tip"] if armed else ["hand_l", "hand_r"]):
		var ps: Array = series[key]
		var sp := []
		for k in ps.size():
			var a: Vector3 = ps[maxi(0, k - 1)]
			var b: Vector3 = ps[k]
			sp.append(a.distance_to(b) * HZ if a.is_finite() and b.is_finite() else 0.0)
		var sm := []
		for k in sp.size():
			sm.append((float(sp[maxi(0, k - 1)]) + float(sp[k]) + float(sp[mini(sp.size() - 1, k + 1)])) / 3.0)
		var w := int(0.12 * HZ)
		for k in sm.size():
			if float(sm[k]) < MIN_SPEED:
				continue
			var top := true
			for j in range(maxi(0, k - w), mini(sm.size(), k + w + 1)):
				if float(sm[j]) > float(sm[k]) or (float(sm[j]) == float(sm[k]) and j < k):
					top = false
					break
			if top:
				# the CONTACT is the stroke's full extension: the frame, from just before the speed peak to EXT_AFTER after it, at which the
				# striking point is farthest (level) from the pelvis. The peak is the middle of the swing, the extension its end
				var kb := k
				var bd := -1.0
				for j in range(maxi(0, k - int(0.03 * HZ)), mini(ps.size(), k + int(EXT_AFTER * HZ) + 1)):
					var q: Vector3 = ps[j]
					var pv: Vector3 = pelv[j]
					var dd := Vector2(q.x - pv.x, q.z - pv.z).length()
					if q.is_finite() and dd > bd:
						bd = dd
						kb = j
				cand.append({"t": snappedf(float(kb) / HZ, 1.0 / A.fps), "hand": "" if key == "tip" else key, "speed": float(sm[k])})
	cand.sort_custom(func(x, y): return float(x["speed"]) > float(y["speed"]))
	if not cand.is_empty():
		var top_v: float = cand[0]["speed"]
		cand = cand.filter(func(c): return float(c["speed"]) >= REL_SPEED * top_v)
	var out := []
	for c in cand:
		var free := true
		for o in out:
			if absf(float(o["t"]) - float(c["t"])) < MIN_GAP:
				free = false
		if free:
			out.append(c)
	out.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	return out


# ------------------------------------------------------------------------------------------------ geometry

static func _trunk(part: String) -> bool:
	return ReactionPicker.region_of(part) in ["head", "torso"] and not Body.is_wep(part) and not _finger(part)


## the trunk/head part nearest to point p (attacker space), the defender at `rel`: {"gap" (m; < 0 inside), "part"}
static func zone_gap(p: Vector3, DB: Body, rel: Transform3D) -> Dictionary:
	var best := {"gap": INF, "part": ""}
	for part in DB.cross_parts():
		if not _trunk(part):
			continue
		var c: Array = DB.cap(part)
		var g := Choreo.point_seg(p, rel * (c[0] as Vector3), rel * (c[1] as Vector3)) - float(DB.rad[part])
		if g < float(best["gap"]):
			best = {"gap": g, "part": part}
	return best


## the bat's u (metres from the knob) whose point is nearest the trunk; -1 for a fist
static func strike_u(AB: Body, DB: Body, rel: Transform3D) -> float:
	if not AB.wep_on:
		return -1.0
	var bu := AB.wep_len
	var bg := INF
	var u := 0.0
	while u <= AB.wep_len + 1e-6:
		var g := float(zone_gap(AB.wep_point(u), DB, rel)["gap"])
		if g < bg:
			bg = g
			bu = u
		u += 0.01
	return bu


## true when the bodies overlap now (AB, DB posed; DB at rel). The strike and the guard are left out: weapons, hands, forearms
static func overlap(AB: Body, DB: Body, rel: Transform3D) -> bool:
	for r in AB.cross_contacts(DB, rel):
		var p := String(r[0])
		var q := String(r[1])
		if Body.is_wep(p) or Body.is_wep(q) or p in Body.CROSS_ARM_END or q in Body.CROSS_ARM_END:
			continue
		if float(r[2]) > Body.CROSS_MIN:
			return true
	return false


## the striking point's positions at 120 Hz over [t0, t1]: [[t, p], ...] (the attacker posed by A)
static func path(A: Scene, AB: Body, hand: String, u: float, t0: float, t1: float) -> Array:
	var out := []
	var n := int(ceil((t1 - t0) * 120.0))
	for k in n + 1:
		var t := minf(t1, t0 + float(k) / 120.0)
		A.apply(AB, maxf(0.0, t))
		out.append([t, spot(AB, hand, u)])
	return out


static func _tip_r(AB: Body) -> float:
	return float(AB.rad["bat_barrel"]) if AB.wep_on else FIST_R


static func _dist_to_part(pth: Array, DB: Body, rel: Transform3D, part: String) -> float:
	var c: Array = DB.cap(part)
	var a: Vector3 = rel * (c[0] as Vector3)
	var b: Vector3 = rel * (c[1] as Vector3)
	var best := INF
	for pt in pth:
		best = minf(best, Choreo.point_seg(pt[1], a, b))
	return best - float(DB.rad[part])


static func _change(a: Dictionary, b: Dictionary) -> float:
	var s := 0.0
	for j in a:
		if _finger(String(j)):
			continue
		var d: Vector3 = ((a[j] as Vector3) - (b[j] as Vector3)).abs()
		s += d.x + d.y + d.z
	return s


# ------------------------------------------------------------------------------------------------ one defence

## every candidate defence for one beat, tested: [{"kind", "label", "pose" (a Body.to_dict), "cost" (joint change)}].
## DB is posed by pp (the previous pose) and left posed by the last candidate. pth = the tip's path from the arrival on.
static func candidates(AB: Body, DB: Body, rel: Transform3D, pp: Dictionary, pth: Array, target: String, tip_r: float, lat := Vector3.ZERO) -> Array:
	var out := []
	DB.from_dict(pp)
	var ang0: Dictionary = DB.ang.duplicate()
	var d0 := _dist_to_part(pth, DB, rel, target)
	var inv := rel.affine_inverse()
	var first: Vector3 = (pth[0][1] as Vector3)
	var mid: Vector3 = (pth[maxi(0, pth.size() / 2)][1] as Vector3)
	var toward := (inv.basis * (AB.P["pelvis"] as Vector3 - rel * (DB.P["pelvis"] as Vector3))).normalized()   # toward the attacker, defender space
	# 1 BLOCKS: a forearm across the path
	for hand in ["hand_r", "hand_l"]:
		var sd: String = String(hand).right(1)
		var up_: String = "upperarm_" + sd
		for X in [mid, first]:
			var Xd: Vector3 = inv * X
			for off in [Vector3.ZERO, Vector3.UP * 0.09, Vector3.DOWN * 0.09, Vector3.LEFT * 0.09, Vector3.RIGHT * 0.09, Vector3.FORWARD * 0.09, Vector3.BACK * 0.09]:
				DB.from_dict(pp)
				var R: Vector3 = ((DB.P["upperarm_r"] as Vector3) - (DB.P["upperarm_l"] as Vector3)).normalized()
				var outv := R if sd == "r" else -R
				var pole: Vector3 = (DB.P[up_] as Vector3) + outv * 0.25 + Vector3.DOWN * 0.25 + toward * 0.15
				var res := LimbIK.solve(DB, hand, Xd + off, pole)
				if float(res["miss"]) > 0.02:
					continue
				DB.fk()
				var fa: String = "lowerarm_" + sd
				var c: Array = DB.cap(fa)
				var a: Vector3 = rel * (c[0] as Vector3)
				var b: Vector3 = rel * (c[1] as Vector3)
				var rr := float(DB.rad[fa]) + tip_r
				var hit := -1
				for i in pth.size():
					if Choreo.point_seg(pth[i][1], a, b) - rr <= 0.0:
						hit = i
						break
				if hit < 0:
					continue
				if float(zone_gap(pth[hit][1], DB, rel)["gap"]) < -0.005:   # the tip is already in the trunk: the forearm is not in front of it
					continue
				if overlap(AB, DB, rel):
					continue
				out.append({"kind": "block", "label": "BLOCK (%s)" % ("R" if sd == "r" else "L"), "pose": DB.to_dict(), "cost": _change(ang0, DB.ang)})
	# 2 SLIPS: the spine leaned to a side until the target part is SLIP_OFF off the path
	for sgn in [1.0, -1.0]:
		var m := 6.0
		while m <= 44.0:
			DB.from_dict(pp)
			for j in ["spine_01", "spine_02", "spine_03"]:
				var a2: Vector3 = DB.ang[j]
				DB.ang[j] = DB.clamp_ang(j, Vector3(a2.x, a2.y + sgn * m / 3.0, a2.z))
			DB.fk()
			var d1 := _dist_to_part(pth, DB, rel, target)
			if d1 - d0 >= SLIP_OFF and d1 >= 0.02:
				if not overlap(AB, DB, rel):
					out.append({"kind": "slip", "label": "SLIP (%s)" % ("R" if sgn > 0.0 else "L"), "pose": DB.to_dict(), "cost": _change(ang0, DB.ang)})
				break
			m += 2.0
	# 3 DODGES: a slip that also takes a sidestep (the hips go sideways, perpendicular to the attack) for the strikes a lean cannot clear
	if out.is_empty():
		for sgn in [1.0, -1.0]:
			var w := 0.10
			while w <= 0.45:
				var rl := Transform3D(rel.basis, rel.origin + lat * (sgn * w))
				DB.from_dict(pp)
				for j in ["spine_01", "spine_02", "spine_03"]:
					var a3: Vector3 = DB.ang[j]
					DB.ang[j] = DB.clamp_ang(j, Vector3(a3.x, a3.y + sgn * 8.0, a3.z))
				DB.fk()
				var d2 := _dist_to_part(pth, DB, rl, target)
				if d2 - d0 >= SLIP_OFF and d2 >= 0.02 and not overlap(AB, DB, rl):
					out.append({"kind": "slip", "label": "DODGE (%s)" % ("R" if sgn > 0.0 else "L"), "pose": DB.to_dict(), "cost": _change(ang0, DB.ang) + w * 200.0, "dshift": lat * (sgn * w)})
					break
				w += 0.02
	return out


# ------------------------------------------------------------------------------------------------ the whole phrase

## THE PLAN. A = the attacker's scene, D = the defender's; rel = the defender's space -> the attacker's. Returns {"ok", "why",
## "beats": [{"t", "arrive", "start", "kind", "label", "zone", "gap", "step", "flag", "why", "pose"}], "cards" (the defender's new
## cards), "keep" (how many of its old cards stand), "markers", "text"}; nothing of A or D is touched.
static func plan(A: Scene, D: Scene, rel: Transform3D) -> Dictionary:
	var AB := _body()
	var DB := _body()
	var bs := strikes(A, AB)
	if bs.is_empty():
		return {"ok": false, "why": "no strike in the attacker's cards (no hand or weapon tip passes %.1f m/s): pick the fighter who swings or punches" % MIN_SPEED}
	var fps: int = maxi(1, D.fps)
	var fr := 1.0 / float(fps)
	var t_first := maxf(0.0, float(bs[0]["t"]) - REACT_S)
	D.apply(DB, t_first)
	var stance: Dictionary = DB.to_dict()
	var base_off: Array = stance["offset"]
	var pp: Dictionary = stance
	var shift := Vector3.ZERO     # attacker space, horizontal: the defender's root moved so far
	var beats := []
	var kinds := []
	for i in bs.size():
		var b: Dictionary = bs[i]
		var tc: float = b["t"]
		var arrive: float = tc - LEAD_FRAMES * fr
		var res := {"t": tc, "arrive": arrive, "start": maxf(0.0, tc - REACT_S), "kind": "", "label": "", "zone": "", "gap": 0.0, "step": 0.0, "flag": false, "why": "", "pose": {}}
		A.apply(AB, tc)
		var relx := Transform3D(rel.basis, rel.origin + shift)
		DB.from_dict(pp)
		var u := strike_u(AB, DB, relx)
		var sp := spot(AB, String(b["hand"]), u)
		# RANGE: the smallest step along the line of the pelvises
		var line: Vector3 = sp - relx * (DB.P["pelvis"] as Vector3)   # the line of the attack: from the defender's centre toward where the strike lands
		line.y = 0.0
		line = line.normalized() if line.length() > 1e-6 else Vector3.FORWARD
		var found := false
		var step := 0.0
		var best_gap := INF
		var tol := REACH_AIM
		for pass_i in 2:
			for k in int(SCAN / 0.01) + 1:
				for sg in ([1.0, -1.0] if k > 0 else [1.0]):
					var s: float = sg * k * 0.01
					var rs := Transform3D(rel.basis, relx.origin + line * s)
					var z := zone_gap(sp, DB, rs)
					best_gap = minf(best_gap, absf(float(z["gap"])))
					if absf(float(z["gap"])) > tol:
						continue
					if overlap(AB, DB, rs):
						continue
					found = true
					step = s
					break
				if found:
					break
			if found:
				break
			tol = REACH_TOL
		if not found:
			res["flag"] = true
			res["cum"] = shift
			res["why"] = "no step of up to %.0f m puts the striking point within 5 cm of the trunk with the bodies apart (closest %.0f cm)" % [SCAN, best_gap * 100.0]
			beats.append(res)
			kinds.append("")
			continue
		shift += line * step
		relx = Transform3D(rel.basis, rel.origin + shift)
		res["step"] = step
		res["cum"] = shift
		res["pre"] = shift
		res["pre"] = shift
		var z2 := zone_gap(sp, DB, relx)
		res["gap"] = float(z2["gap"])
		res["zone"] = Body.cross_zone(String(z2["part"]))
		res["part"] = String(z2["part"])
		var pth := path(A, AB, String(b["hand"]), u, arrive, tc + 0.02)
		A.apply(AB, tc)
		var cs := candidates(AB, DB, relx, pp, pth, String(z2["part"]), _tip_r(AB), Vector3(-line.z, 0.0, line.x))
		var last_kind: String = kinds[-1] if not kinds.is_empty() else ""
		var run := 0
		for k in range(kinds.size() - 1, -1, -1):
			if last_kind != "" and kinds[k] == last_kind:
				run += 1
			else:
				break
		var pick := {}
		var pc := INF
		for c in cs:
			var cost: float = c["cost"]
			if c["kind"] == last_kind:
				if run >= MAX_RUN:
					continue
				cost += REPEAT_COST
			if cost < pc:
				pc = cost
				pick = c
		if pick.is_empty():
			res["flag"] = true
			res["cum"] = shift
			res["why"] = "in range, but no block or slip is possible here (the %s cannot get 10 cm off the path or a forearm across it)" % [res["zone"].to_lower()]
			beats.append(res)
			kinds.append("")
			continue
		res["kind"] = pick["kind"]
		res["label"] = pick["label"]
		if pick.has("dshift"):
			shift += pick["dshift"] as Vector3
			res["cum"] = shift
			res["side"] = (pick["dshift"] as Vector3).length()
		res["pose"] = pick["pose"]
		(res["pose"] as Dictionary)["offset"] = base_off.duplicate()
		pp = res["pose"]
		kinds.append(pick["kind"])
		beats.append(res)
	return _write(D, beats, stance, base_off, rel, t_first, fr)


## the beats -> the defender's new cards and the timeline markers (see the header for the timing)
static func _write(D: Scene, beats: Array, stance: Dictionary, base_off: Array, rel: Transform3D, t_first: float, fr: float) -> Dictionary:
	var ts := D.times()
	var keep := 0
	for i in D.cards.size():
		if float(ts[i][1]) <= t_first - MIN_MOVE + 1e-9:
			keep = i + 1
		else:
			break
	var cards := []
	for i in keep:
		cards.append((D.cards[i] as Dictionary).duplicate(true))
	var end := 0.0
	if keep > 0:
		var k0: Dictionary = cards[keep - 1]
		k0["hold"] = snappedf(maxf(0.0, minf(float(k0["hold"]), t_first - MIN_MOVE - float(ts[keep - 1][1]))), 0.0001)
		end = float(ts[keep - 1][1]) + float(k0["hold"])
	var inv := rel.basis.inverse()
	var off_of := func(cum: Vector3) -> Array:
		var l: Vector3 = inv * cum
		return [snappedf(float(base_off[0]) + l.x, 0.0001), float(base_off[1]), snappedf(float(base_off[2]) + l.z, 0.0001)]
	var sp: Dictionary = stance.duplicate(true)
	sp["offset"] = base_off.duplicate()
	if keep == 0:
		cards.append({"name": "guard", "pose": sp, "move": -1.0, "hold": snappedf(t_first, 0.0001)})
		end = t_first
	else:
		cards.append({"name": "guard", "pose": sp, "move": snappedf(maxf(MIN_MOVE, t_first - end), 0.0001), "hold": 0.0})
		end = maxf(end + MIN_MOVE, t_first)
	var live := []
	for r in beats:
		if not r["flag"]:
			live.append(r)
	var cum := Vector3.ZERO
	var marks := []
	for j in live.size():
		var r: Dictionary = live[j]
		var pose0: Dictionary = (cards[-1]["pose"] as Dictionary)
		var pre: Vector3 = r.get("pre", r["cum"])
		if (pre - cum).length() > 0.005:   # the walk to the range comes first, in its own card, arriving as the reaction starts
			var stepc: Dictionary = pose0.duplicate(true)
			stepc["offset"] = off_of.call(pre)
			if cards.size() == 1 + keep and float(cards[-1]["hold"]) > 0.0 and keep == 0:
				cards[-1]["hold"] = 0.0   # the walk starts at once
				end = 0.0
			var stp_at := maxf(float(r["start"]), end + MIN_MOVE)
			cards.append({"name": "step %s" % ("in" if float(r["step"]) >= 0.0 else "out"), "pose": stepc, "move": snappedf(stp_at - end, 0.0001), "hold": 0.0})
			end = stp_at
		var arrive := maxf(float(r["arrive"]), end + MIN_MOVE)
		r["arrive_at"] = arrive
		if arrive > float(r["arrive"]) + 1e-6:
			r["late"] = true
		var pose: Dictionary = (r["pose"] as Dictionary).duplicate(true)
		pose["offset"] = off_of.call(r["cum"])
		var nxt: float = float(live[j + 1]["start"]) if j + 1 < live.size() else INF
		var hold := maxf(0.0, (nxt if nxt < INF else float(r["t"]) + HOLD_AFTER) - arrive)   # the guard is held until the next wind-up is seen
		cards.append({"name": "%s %d" % [r["label"], beats.find(r) + 1], "pose": pose, "move": snappedf(arrive - end, 0.0001), "hold": snappedf(hold, 0.0001)})
		end = arrive + snappedf(hold, 0.0001)
		cum = r["cum"]
	var rec: Dictionary = stance.duplicate(true)
	rec["offset"] = off_of.call(cum)
	cards.append({"name": "guard up", "pose": rec, "move": 0.3, "hold": 0.3})
	var lines := []
	for i in beats.size():
		var r: Dictionary = beats[i]
		var step_txt := ""
		if absf(float(r["step"])) >= 0.005:
			step_txt = "  step %s %.0f cm" % ["in" if float(r["step"]) > 0.0 else "out", absf(float(r["step"])) * 100.0]
		if r["flag"]:
			marks.append({"t": snappedf(float(r["t"]), 0.001), "name": "FP %d FLAG" % (i + 1), "kind": "note", "color": "red", "note": String(r["why"])})
			lines.append("beat %d at %.2f s FLAGGED: %s" % [i + 1, float(r["t"]), r["why"]])
		else:
			marks.append({"t": snappedf(float(r["t"]), 0.001), "name": "FP %d %s" % [i + 1, r["label"]], "kind": "hit", "color": "blue",
				"note": "%s: starts %.2f s, in place %.2f s, contact %.2f s%s" % [r["label"], float(r["start"]), float(r.get("arrive_at", r["arrive"])), float(r["t"]), step_txt]})
			lines.append("beat %d at %.2f s: %s (%s %+.1f cm from the strike)%s" % [i + 1, float(r["t"]), r["label"], String(r["zone"]).to_lower(), float(r["gap"]) * 100.0, step_txt])
	return {"ok": true, "why": "", "beats": beats, "cards": cards, "keep": keep, "markers": marks, "text": "
".join(lines)}


## write the plan onto the defender's scene (cards and the "FP" markers; everything else of it stays)
static func apply_plan(D: Scene, pl: Dictionary) -> void:
	D.cards = (pl["cards"] as Array).duplicate(true)
	var ms := []
	for m in D.markers:
		if not String(m["name"]).begins_with("FP "):
			ms.append(m)
	for m in pl["markers"]:
		ms.append(Markers.clean(m))
	D.markers = Markers.sorted(ms)
