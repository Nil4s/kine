## throw_truth.gd - THROW TRUTH (INNOVATIONS N040). A throw works only when (1) the partner's centre of mass is pulled outside his feet (kuzushi)
## and (2) the thrower's own balance holds. Both bodies are judged as a pair, frame by frame, and the verdict names the condition that is missing.
## Builds on balance.gd (COM, support polygon, signed margin), I39 recovery.gd (the capture point / extrapolated COM, Hof 2005) and the
## two-body core (Body.cross_caps, Scene.actors, Constraints.actor_xf).
##   PARTNER: xi = COM(x,z) + v / omega0, omega0 = sqrt(g / COM height), v from the COM's backward difference over the previous frame
##            (0 on the first frame). With v = 0 this is the plain COM. out = how far xi lies outside his support polygon (Balance.signed_dist,
##            floored at 0), and the direction from the nearest polygon point to xi. Reported twice: for the COM alone (com_out) and for xi (out).
##            KUZUSHI <=> out > Balance.MARGIN_RES (2 cm: a lean past the feet by less is not a finding, the model's resolution).
##   THROWER: Balance.read margin of his own COM. HOLDS <=> margin >= -MARGIN_RES. No foot on the floor = does not hold (airborne).
##   CONTACT: any capsule of the thrower within CONTACT_GAP (1 cm) of any capsule of the partner (surface to surface). A contact by a hand or
##            forearm is a GRIP (a hand on a sleeve or lapel); any other part is a body contact (hip, thigh, leg).
##   FRAME VERDICT: "no contact" | "no kuzushi" | "thrower falls" | "throw works" (contact AND kuzushi AND the thrower holds).
##   CLIP VERDICT: the frame verdict at the KEY FRAME = of the frames where the bodies touch, the one where the partner is most off balance
##            (the latest of equals), the moment the throw would be finished. If the bodies never touch: "no contact" (the frame is where they come closest).
## Not modelled (stated): the weight of the partner on the thrower's feet (the thrower's own COM is judged, not the pair's), the reaping leg's
## effect on the partner's base beyond what its pose does, grip strength, cloth. Support polygon is the feet's shadow (lenient: Balance).
class_name ThrowTruth
extends RefCounted

const CONTACT_GAP := 0.01   # m: capsule surfaces this close = touching (a hand on cloth is not exactly zero)
const GRIPPERS := ["hand_l", "hand_r", "lowerarm_l", "lowerarm_r"]
const AIRBORNE_OUT := 9.99  # m: stands in for "no support at all" (both feet off the floor) in out / com_out
const G := 9.81


static func new_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


static func _flat(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y)


## the compass word for a direction in the partner's OWN frame (+z forward, +x his left)
static func own_word(d: Vector2) -> String:
	if d.length() < 1e-6:
		return "none"
	var a := rad_to_deg(atan2(d.x, d.y))   # 0 = forward, 90 = his left, 180 = back, -90 = his right
	var names := ["forward", "forward-left", "left", "back-left", "back", "back-right", "right", "forward-right"]
	var k := int(round(a / 45.0))
	return String(names[posmod(k, 8)])


static func _closest_on_poly(poly: PackedVector2Array, q: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var bd := INF
	if poly.size() == 1:
		return poly[0]
	for i in poly.size():
		var c := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(c) < bd:
			bd = q.distance_to(c)
			best = c
	return best


## one body's balance read in ITS OWN space, extrapolated by its COM velocity v (Vector3, own space):
## {com, v, xi (Vector2), poly, margin_com, margin_xi, out, com_out, dir (own space, unit), airborne}
static func balance_of(B: Body, v: Vector3) -> Dictionary:
	var r := Balance.read(B)
	var c: Vector3 = r["com"]
	var poly: PackedVector2Array = r["poly"]
	var w0 := sqrt(G / maxf(c.y, 0.3))
	var xi := Vector2(c.x + v.x / w0, c.z + v.z / w0)
	var airborne: bool = (r["down"] as Array).is_empty()
	var m_com: float = r["margin"]
	var m_xi := Balance.signed_dist(poly, xi)
	var d := Vector2.ZERO
	if not airborne and m_xi < 0.0:
		d = xi - _closest_on_poly(poly, xi)
		d = d.normalized() if d.length() > 1e-9 else Vector2.ZERO
	return {"com": c, "v": v, "xi": xi, "poly": poly, "margin_com": m_com, "margin_xi": m_xi, "airborne": airborne, "dir": d,
		"out": AIRBORNE_OUT if airborne else maxf(0.0, -m_xi), "com_out": AIRBORNE_OUT if airborne else maxf(0.0, -m_com)}


## contact points between thrower (body A in common space by XA) and partner (B by XB): [{a, b, at (common space), gap, grip}], nearest first
static func contacts(A: Body, XA: Transform3D, B: Body, XB: Transform3D) -> Array:
	var out := []
	var ca := A.cross_caps(XA)
	var cb := B.cross_caps(XB)
	for p in ca:
		for q in cb:
			var rs: float = float(p[5]) + float(q[5]) + CONTACT_GAP
			if (p[4] as Vector3).distance_squared_to(q[4]) > rs * rs:
				continue
			var gap: float = Body.seg_seg(p[1], p[2], q[1], q[2]) - float(p[3]) - float(q[3])
			if gap > CONTACT_GAP:
				continue
			var pts: PackedVector3Array = Geometry3D.get_closest_points_between_segments(p[1], p[2], q[1], q[2])
			var n: Vector3 = pts[1] - pts[0]
			n = n.normalized() if n.length() > 1e-9 else Vector3.UP
			var at: Vector3 = ((pts[0] + n * float(p[3])) + (pts[1] - n * float(q[3]))) * 0.5
			out.append({"a": String(p[0]), "b": String(q[0]), "at": at, "gap": gap, "grip": String(p[0]) in GRIPPERS})
	out.sort_custom(func(x, y): return float(x["gap"]) < float(y["gap"]))
	return out


## judge a two-body scene. S = the hero's scene with its actors; `thrower` = 0 (the hero) or 1 (actor 1, S.actors[0]).
## {"ok", "msg", "fps", "n", "thrower", "frames": [...], "verdict", "frame", "missing": [..], "text"}
static func judge(S: Scene, fps := 30, thrower := 0) -> Dictionary:
	if S.actors.is_empty():
		return {"ok": false, "msg": "a throw needs two bodies: this scene has one fighter", "verdict": "no contact", "frames": [], "n": 0}
	var bodies := [new_body(), new_body()]
	var scs: Array = [S, S.actors[0]["scene"]]
	var xfs: Array = [Transform3D.IDENTITY, Constraints.actor_xf(S.actors[0]["xf"])]
	var ti := thrower
	var pi := 1 - thrower
	var n := int(ceil(S.length() * fps)) + 1
	var frames := []
	var prev_com := Vector3.ZERO
	for f in n:
		var t := float(f) / float(fps)
		for k in 2:
			(scs[k] as Scene).apply(bodies[k], t)
			(bodies[k] as Body).fk()
		var bp: Body = bodies[pi]
		var cpre := Balance.com(bp)
		var v := Vector3.ZERO if f == 0 else (cpre - prev_com) * float(fps)
		prev_com = cpre
		var P := balance_of(bp, v)
		var T := balance_of(bodies[ti], Vector3.ZERO)
		var cts := contacts(bodies[ti], xfs[ti], bp, xfs[pi])
		var gap := INF
		if cts.is_empty():
			gap = _min_gap(bodies[ti], xfs[ti], bp, xfs[pi])
		else:
			gap = float(cts[0]["gap"])
		var kuzushi: bool = float(P["out"]) > Balance.MARGIN_RES
		var holds: bool = (not bool(T["airborne"])) and float(T["margin_com"]) >= -Balance.MARGIN_RES
		var verdict := "no contact"
		if not cts.is_empty():
			verdict = "throw works" if (kuzushi and holds) else ("no kuzushi" if not kuzushi else "thrower falls")
		var dwo: Vector2 = P["dir"]
		var dw3: Vector3 = (xfs[pi] as Transform3D).basis * _flat(dwo)
		frames.append({"f": f, "t": t, "contact": not cts.is_empty(), "gap": gap, "points": cts,
			"grips": cts.filter(func(c): return c["grip"]).size(), "kuzushi": kuzushi, "holds": holds, "verdict": verdict,
			"partner": {"com": (xfs[pi] as Transform3D) * (P["com"] as Vector3), "v": v, "out": P["out"], "com_out": P["com_out"],
				"margin_xi": P["margin_xi"], "margin_com": P["margin_com"], "airborne": P["airborne"], "dir_world": Vector2(dw3.x, dw3.z),
				"dir_own": own_word(dwo)},
			"thrower": {"com": (xfs[ti] as Transform3D) * (T["com"] as Vector3), "margin": T["margin_com"], "airborne": T["airborne"]}})
	return _summarise(frames, fps, ti, bodies, xfs, pi)


static func _min_gap(A: Body, XA: Transform3D, B: Body, XB: Transform3D) -> float:
	var g := INF
	for p in A.cross_caps(XA):
		for q in B.cross_caps(XB):
			g = minf(g, Body.seg_seg(p[1], p[2], q[1], q[2]) - float(p[3]) - float(q[3]))
	return g


static func _summarise(frames: Array, fps: int, ti: int, bodies: Array, xfs: Array, pi: int) -> Dictionary:
	# THE KEY FRAME: of the frames where the bodies touch, the one where the partner is most off balance (the latest of equals): the moment
	# the throw would be finished. The verdict is the frame verdict there. No touching frame: the frame where the bodies come closest.
	var at := -1
	var best_out := -1.0
	for fr in frames:
		if fr["contact"] and float(fr["partner"]["out"]) >= best_out:
			best_out = float(fr["partner"]["out"])
			at = int(fr["f"])
	var verdict := "no contact"
	if at >= 0:
		verdict = String(frames[at]["verdict"])
	else:
		var mg := INF
		for fr in frames:
			if float(fr["gap"]) < mg:
				mg = float(fr["gap"])
				at = int(fr["f"])
	var d := {"ok": true, "msg": "", "fps": fps, "n": frames.size(), "thrower": ti, "frames": frames, "verdict": verdict, "frame": at,
		"min_gap": (frames[at]["gap"] if at >= 0 else INF)}
	var fr: Dictionary = frames[at] if at >= 0 else {}
	var missing := []
	if verdict == "no kuzushi":
		missing.append("kuzushi")
	if verdict != "no contact" and verdict != "throw works" and not bool(fr.get("holds", true)):
		missing.append("thrower balance")
	d["missing"] = missing
	d["text"] = words_of(d)
	d["msg"] = d["text"]
	return d


static func _cm(x: float) -> String:
	return "%.1f cm" % (x * 100.0)


static func words_of(r: Dictionary) -> String:
	var v: String = r["verdict"]
	var at: int = r["frame"]
	var fps: int = r["fps"]
	if at < 0:
		return "NO CONTACT: no frames"
	var fr: Dictionary = r["frames"][at]
	var P: Dictionary = fr["partner"]
	var T: Dictionary = fr["thrower"]
	var when := "at f %d (%.2f s)" % [at, float(at) / float(fps)]
	var pts: Array = fr["points"]
	var grips: Array = pts.filter(func(c): return c["grip"])
	var bodyc: Array = pts.filter(func(c): return not c["grip"])
	var tc := "%d grip%s, %d body contact%s" % [grips.size(), "" if grips.size() == 1 else "s", bodyc.size(), "" if bodyc.size() == 1 else "s"]
	var pp := ("his feet are off the floor" if bool(P["airborne"]) else
		("his extrapolated centre of mass is %s outside his feet, %s" % [_cm(float(P["out"])), P["dir_own"]]) if float(P["out"]) > 0.0 else
		("his extrapolated centre of mass is still %s inside his feet" % _cm(float(P["margin_xi"]))))
	var tt := ("the thrower's feet are off the floor" if bool(T["airborne"]) else
		("the thrower's centre of mass is %s %s his own feet" % [_cm(absf(float(T["margin"]))), "inside" if float(T["margin"]) >= 0.0 else "outside"]))
	match v:
		"throw works":
			return "THROW WORKS %s: the partner is off balance (%s) and the thrower holds (%s); %s." % [when, pp, tt, tc]
		"no kuzushi":
			var extra := "" if bool(fr["holds"]) else " The thrower's balance is also gone (%s)." % tt
			return "NO KUZUSHI %s: the bodies touch (%s) but the partner is not pulled off his feet: %s (needs more than %s outside).%s" % [when, tc, pp, _cm(Balance.MARGIN_RES), extra]
		"thrower falls":
			return "THROWER FALLS %s: the partner is off balance (%s) but the thrower's own balance is gone: %s; %s." % [when, pp, tt, tc]
	return "NO CONTACT: the bodies never touch; the closest they come is %s apart (%s)." % [_cm(float(r["min_gap"])), when]


static func words(r: Dictionary) -> String:
	return String(r.get("text", r.get("msg", "")))


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


## JSON-safe: Vectors as arrays, numbers rounded to 0.1 mm; `frames` kept (one dict per frame)
static func to_json(r: Dictionary) -> Dictionary:
	var out := {"ok": r.get("ok", false), "verdict": r.get("verdict", ""), "frame": r.get("frame", -1), "fps": r.get("fps", 0), "n": r.get("n", 0),
		"missing": r.get("missing", []), "text": r.get("text", r.get("msg", "")), "min_gap": snappedf(minf(float(r.get("min_gap", 99.0)), 99.0), 0.0001), "frames": []}
	for fr in r.get("frames", []):
		var P: Dictionary = fr["partner"]
		var T: Dictionary = fr["thrower"]
		var pts := []
		for c in fr["points"]:
			pts.append({"thrower_part": c["a"], "partner_part": c["b"], "at": _v3(c["at"]), "gap_m": snappedf(c["gap"], 0.0001), "grip": c["grip"]})
		(out["frames"] as Array).append({"f": fr["f"], "t": snappedf(fr["t"], 0.0001), "verdict": fr["verdict"], "contact": fr["contact"],
			"grips": fr["grips"], "points": pts,
			"partner": {"com": _v3(P["com"]), "out_m": snappedf(P["out"], 0.0001), "com_out_m": snappedf(P["com_out"], 0.0001),
				"direction": P["dir_own"], "direction_world_xz": [snappedf(P["dir_world"].x, 0.001), snappedf(P["dir_world"].y, 0.001)],
				"speed_xz_ms": snappedf(Vector2(P["v"].x, P["v"].z).length(), 0.001), "airborne": P["airborne"]},
			"thrower": {"com": _v3(T["com"]), "margin_m": snappedf(T["margin"], 0.0001), "airborne": T["airborne"]}})
	return out
