## SPEED ENVELOPE (ROADMAP I47): every moving card of a clip against MEASURED human speed maxima. Per card (the move from the previous card's
## leave to this card's arrival) it samples the body at 240 Hz and takes the peak of
##   hand / foot LINEAR speed (world metres, B.E hand_x / ball_x, the same point I38's peak_hand reads),
##   elbow and knee angular speed (the angle of the relative rotation parent -> child, per second),
##   shoulder internal-rotation speed (the upper arm's twist angle, wrapped, per second),
##   pelvis and upper-trunk turning speed (rate of the world rotation about the vertical).
## LIMIT of a channel = the mean + 1 SD of the FASTEST group in the paper (docs/physics_constants_i47.md has the row, quote and population).
## FIX: only the flagged card's move time is lengthened until its worst channel peaks at AIM (0.99) x its limit; every other card is untouched.
## Read only: the body state is put back by the caller (analyse() does it itself).
class_name SpeedEnv
extends RefCounted

const HZ := 240.0
## joint speeds are taken over this many 240 Hz steps (1/60 s): the papers' angles are low-pass filtered mocap, and a one-step difference of a joint-limit
## clamp (a knee reaching 0 deg) would read as a 2000 deg/s spike no body makes. Hand and foot stay one step, the way I38 verified peak_hand.
const ANG_STEPS := 4
const AIM := 0.99
const MAX_ITER := 14
## id, label, kind (lin point | hinge parent,child | twist joint | yaw joint), unit, limit, short cite
const CH := [
	{"id": "hand", "label": "hand", "kind": "lin", "pts": ["hand_l", "hand_r"], "unit": "m/s", "limit": 13.79,
		"cite": "Stanley 2018: lead hook 11.95 +- 1.84 m/s, 15 amateur boxers"},
	{"id": "foot", "label": "foot", "kind": "lin", "pts": ["ball_l", "ball_r"], "unit": "m/s", "limit": 15.84,
		"cite": "Gavagan & Sayers 2017: taekwondo kick foot 14.66 +- 1.18 m/s, 8 black belts"},
	{"id": "elbow", "label": "elbow extension", "kind": "hinge", "pts": [["upperarm_l", "lowerarm_l"], ["upperarm_r", "lowerarm_r"]], "unit": "deg/s", "limit": 2526.0,
		"cite": "Fleisig 2016: pitching elbow extension 2305 +- 221 deg/s, 25 pitchers"},
	{"id": "shoulder", "label": "shoulder internal rotation", "kind": "twist", "pts": ["upperarm_l", "upperarm_r"], "unit": "deg/s", "limit": 7337.0,
		"cite": "Fleisig 2016: pitching shoulder internal rotation 6594 +- 743 deg/s, 25 pitchers"},
	{"id": "knee", "label": "knee extension", "kind": "hinge", "pts": [["thigh_l", "calf_l"], ["thigh_r", "calf_r"]], "unit": "deg/s", "limit": 1041.0,
		"cite": "Gavagan & Sayers 2017: karate roundhouse knee extension 947 +- 94 deg/s, 8 black belts"},
	{"id": "pelvis", "label": "pelvis turn", "kind": "yaw", "pts": ["pelvis"], "unit": "deg/s", "limit": 699.0,
		"cite": "Gavagan & Sayers 2017: Muay Thai roundhouse pelvis rotation 493 +- 206 deg/s, 8 black belts"},
	{"id": "trunk", "label": "upper-trunk turn", "kind": "yaw", "pts": ["spine_03"], "unit": "deg/s", "limit": 1190.0,
		"cite": "Fleisig 2016: pitching upper trunk 1101 +- 89 deg/s, 25 pitchers"},
]


static func _wrap(d: float) -> float:
	return fposmod(d + 180.0, 360.0) - 180.0


## the state of channel c, point k, at the body's current pose
static func _state(B: Body, c: Dictionary, k: int) -> Variant:
	var p = (c["pts"] as Array)[k]
	match String(c["kind"]):
		"lin":
			return B.E[p]
		"hinge":
			var q: Quaternion = (B.G[p[0]] as Quaternion).inverse() * (B.G[p[1]] as Quaternion)
			return q.normalized()
		"twist":
			return float((B.ang[p] as Vector3).z)
		_:
			return (B.G[p] as Quaternion).normalized()


static func _speed(c: Dictionary, a: Variant, b: Variant, dt: float) -> float:
	match String(c["kind"]):
		"lin":
			return ((b as Vector3) - (a as Vector3)).length() / dt
		"hinge":
			var q: Quaternion = (a as Quaternion).inverse() * (b as Quaternion)
			var ang := rad_to_deg(q.get_angle())
			return minf(ang, 360.0 - ang) / dt
		"twist":
			return absf(_wrap(float(b) - float(a))) / dt
		_:
			var r: Quaternion = (b as Quaternion) * (a as Quaternion).inverse()
			var ang := rad_to_deg(r.get_angle())
			ang = minf(ang, 360.0 - ang)
			var ax := r.get_axis()
			return absf(ax.y) * ang / dt


## the peak of every channel over card i's move: {id: {"peak", "side"}}. The body is left posed (the caller restores it).
static func card_peaks(S: Scene, B: Body, i: int) -> Dictionary:
	var ts := S.times()
	var t0 := float(ts[i - 1][2])
	var t1 := float(ts[i][1])
	var dur := maxf(t1 - t0, 1e-4)
	var n := maxi(2, int(ceil(dur * HZ)))
	var dt := dur / float(n)
	var out := {}
	var hist := {}
	for c in CH:
		out[c["id"]] = {"peak": 0.0, "side": 0}
	for s in n + 1:
		S.apply(B, t0 + dur * float(s) / float(n))
		for c in CH:
			var id: String = c["id"]
			for k in (c["pts"] as Array).size():
				var cur: Variant = _state(B, c, k)
				var key := "%s%d" % [id, k]
				var h: Array = hist.get(key, [])
				h.append(cur)
				hist[key] = h
				var w := 1 if String(c["kind"]) == "lin" else mini(ANG_STEPS, n)
				if h.size() > w:
					var v := _speed(c, h[h.size() - 1 - w], cur, dt * float(w))
					if v > float((out[id] as Dictionary)["peak"]):
						out[id] = {"peak": v, "side": k}
	return out


static func _side(c: Dictionary, k: int) -> String:
	if (c["pts"] as Array).size() < 2:
		return ""
	return "left " if k == 0 else "right "


## per moving card, its worst channel: [{"card", "name", "ch" (CH entry), "side", "peak", "limit", "ratio", "all": [{id, peak, ratio}]}]; the flagged ones have ratio > 1
static func analyse(S: Scene, B: Body) -> Array:
	var keep: Dictionary = B.state()
	var out := []
	for i in range(1, S.cards.size()):
		out.append(_row(S, B, i))
	B.set_state(keep)
	return out


static func _row(S: Scene, B: Body, i: int) -> Dictionary:
	var pk := card_peaks(S, B, i)
	var best := {}
	var all := []
	for c in CH:
		var p: Dictionary = pk[c["id"]]
		var r := float(p["peak"]) / float(c["limit"])
		all.append({"id": c["id"], "ch": c, "side": _side(c, int(p["side"])), "peak": p["peak"], "ratio": r})
		if best.is_empty() or r > float(best["ratio"]):
			best = {"card": i, "name": String(S.cards[i].get("name", "")), "ch": c, "side": _side(c, int(p["side"])), "peak": float(p["peak"]),
				"limit": float(c["limit"]), "ratio": r, "dur": S.move_time(i)}
	best["all"] = all
	return best


static func flagged(rows: Array) -> Array:
	var f := []
	for r in rows:
		if float(r["ratio"]) > 1.0:
			f.append(r)
	return f


static func fmt(v: float, unit: String) -> String:
	return ("%.1f m/s" % v) if unit == "m/s" else ("%.0f deg/s" % v)


static func words(r: Dictionary) -> String:
	var c: Dictionary = r["ch"]
	var u := String(c["unit"])
	var also := []
	for a in r["all"]:
		if float(a["ratio"]) > 1.0 and String(a["id"]) != String(c["id"]):
			also.append("%s%s %s (top %s)" % [a["side"], a["ch"]["label"], fmt(float(a["peak"]), String(a["ch"]["unit"])), fmt(float(a["ch"]["limit"]), String(a["ch"]["unit"]))])
	return "card %d %s: %s%s %s, the measured top is %s (%s)%s" % [int(r["card"]) + 1, String(r["name"]), String(r["side"]), String(c["label"]), fmt(float(r["peak"]), u),
		fmt(float(r["limit"]), u), String(c["cite"]), "" if also.is_empty() else "; also " + ", ".join(also)]


## a copy of S where each flagged card's move is lengthened so its worst channel peaks at AIM x limit. Returns {"scene", "changes"}; nothing else moves.
static func plan(S: Scene, B: Body, rows: Array) -> Dictionary:
	var keep: Dictionary = B.state()
	var W := S.clone()
	var changes := []
	for r in flagged(rows):
		var i: int = r["card"]
		var t0 := W.move_time(i)
		var t := t0
		var ratio := float(r["ratio"])
		for it in MAX_ITER:
			t = snappedf(t * ratio / AIM, 0.001)
			W.cards[i]["move"] = t
			var nr := _row(W, B, i)
			ratio = float(nr["ratio"])
			if ratio <= 1.0 and ratio >= AIM - 0.02:
				break
		changes.append({"card": i, "name": r["name"], "from": t0, "to": t, "ch": r["ch"], "side": r["side"], "before": r["peak"],
			"after": ratio * float(r["limit"]), "limit": r["limit"]})
	B.set_state(keep)
	return {"scene": W, "changes": changes}
