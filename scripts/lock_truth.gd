## lock_truth.gd - LOCK TRUTH (INNOVATIONS N041). An armbar, a wristlock or a kimura uses the PARTNER's joint limits. Frame by frame this judges the
## partner's elbow (lowerarm), wrist (hand) and shoulder (upperarm) angles, on the arm(s) the locker touches, against data/body_limits.json (the
## truth the Body loads) and says when the lock reaches his limit and when it goes past it (an injury).
## THE ANGLES JUDGED are the ones the clip ASKS of him: the scene's sampled angles BEFORE Body clamps them to his range (Scene.sample, the raw card
## blend). The body on screen can never go past its limit; the clip's demand can, and that gap is the injury.
##   CONTACT: a capsule of the locker within ThrowTruth.CONTACT_GAP of a capsule of the partner's arm (upperarm, lowerarm, hand; either side).
##            The judged arm = the side(s) touched. Not touching = no lock.
##   MARGIN: over elbow/wrist/shoulder x bend/side/twist of that arm, the distance (deg) from the angle to the nearest end of its range
##            (negative = outside). A locked axis (range 0) is judged as -|angle| when the clip moves it, else skipped.
##   FRAME VERDICT: "no contact" | "lock not on" (margin > NEAR) | "at limit" (0 <= margin <= NEAR = 5 deg) | "past limit: injury" (margin < 0).
##   CLIP VERDICT: the verdict of the KEY FRAME = of the frames where the locker touches the arm, the one with the smallest margin (the latest of
##            equals). If he never touches: "no contact", frame = where he comes closest.
## Reference (recorded in tests/n041_test.gd): AAOS / Norkin & White joint-motion norms; Soucie et al. 2011, Haemophilia 17(3):500-507.
## Not modelled (stated): pain before the limit, ligament laxity, the force of the lock, combined-axis (coupled) limits, the locker's own limits.
class_name LockTruth
extends RefCounted

const NEAR := 5.0   # deg: within this of a limit = "at limit"
const PAST_EPS := 1e-4
const ARM_PARTS := ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]
const JOINTS := [["elbow", "lowerarm"], ["wrist", "hand"], ["shoulder", "upperarm"]]
const AXES := ["bend", "side", "twist"]
const V_NONE := "no contact"
const V_OFF := "lock not on"
const V_AT := "at limit"
const V_PAST := "past limit: injury"


static func new_body(limits_path := "res://data/body_limits.json") -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", limits_path)
	return b


static func classify(margin: float) -> String:
	if margin < -PAST_EPS:
		return V_PAST
	return V_AT if margin <= NEAR else V_OFF


## the tightest margin on one arm: {joint, axis, side, angle, lo, hi, margin}; angs = the raw sample's {joint: Vector3(bend, side, twist)}
static func arm_margin(B: Body, angs: Dictionary, sfx: String) -> Dictionary:
	var best := {"margin": INF}
	for jn in JOINTS:
		var j: String = String(jn[1]) + sfx
		var a: Vector3 = angs.get(j, Vector3.ZERO)
		for k in 3:
			var v: float = [a.x, a.y, a.z][k]
			var r: Vector2 = B.lim[j][AXES[k]]
			var m := INF
			if r.y - r.x < 0.5:
				if absf(v - r.x) < 0.05:
					continue
				m = -absf(v - r.x)
			else:
				m = minf(v - r.x, r.y - v)
			if m < float(best["margin"]):
				best = {"joint": String(jn[0]), "axis": AXES[k], "side": "left" if sfx == "_l" else "right", "angle": v, "lo": r.x, "hi": r.y, "margin": m}
	return best


static func _arm_gap(A: Body, XA: Transform3D, B: Body, XB: Transform3D) -> float:
	var g := INF
	var cb := []
	for q in B.cross_caps(XB):
		if String(q[0]) in ARM_PARTS:
			cb.append(q)
	for p in A.cross_caps(XA):
		for q in cb:
			g = minf(g, Body.seg_seg(p[1], p[2], q[1], q[2]) - float(p[3]) - float(q[3]))
	return g


## S = the hero's scene with its actors; locker = 0 (the hero locks the actor) or 1 (the actor locks the hero)
static func judge(S: Scene, fps := 30, locker := 0, limits_path := "res://data/body_limits.json") -> Dictionary:
	if S.actors.is_empty():
		return {"ok": false, "msg": "a lock needs two bodies: this scene has one fighter", "verdict": V_NONE, "frames": [], "n": 0}
	var bodies := [new_body(limits_path), new_body(limits_path)]
	var scs: Array = [S, S.actors[0]["scene"]]
	var xfs: Array = [Transform3D.IDENTITY, Constraints.actor_xf(S.actors[0]["xf"])]
	var li := locker
	var vi := 1 - locker
	var n := int(ceil(S.length() * fps)) + 1
	var frames := []
	for f in n:
		var t := float(f) / float(fps)
		for k in 2:
			(scs[k] as Scene).apply(bodies[k], t)
			(bodies[k] as Body).fk()
		var cts: Array = ThrowTruth.contacts(bodies[li], xfs[li], bodies[vi], xfs[vi]).filter(func(c): return String(c["b"]) in ARM_PARTS)
		var fr := {"f": f, "t": t, "contact": not cts.is_empty(), "gap": 0.0, "verdict": V_NONE, "points": cts, "joint": "", "axis": "", "side": "",
			"angle_deg": 0.0, "lo_deg": 0.0, "hi_deg": 0.0, "margin_deg": 0.0, "past_deg": 0.0}
		if cts.is_empty():
			fr["gap"] = _arm_gap(bodies[li], xfs[li], bodies[vi], xfs[vi])
		else:
			fr["gap"] = float(cts[0]["gap"])
			var angs: Dictionary = (scs[vi] as Scene).sample(t)["ang"]
			var sides := {}
			for c in cts:
				sides[String(c["b"]).substr(String(c["b"]).length() - 2)] = true
			var best := {"margin": INF}
			for sfx in ["_r", "_l"]:
				if sides.has(sfx):
					var am := arm_margin(bodies[vi], angs, sfx)
					if float(am["margin"]) < float(best["margin"]):
						best = am
			fr["joint"] = best["joint"]
			fr["axis"] = best["axis"]
			fr["side"] = best["side"]
			fr["angle_deg"] = best["angle"]
			fr["lo_deg"] = best["lo"]
			fr["hi_deg"] = best["hi"]
			fr["margin_deg"] = best["margin"]
			fr["past_deg"] = -float(best["margin"]) if float(best["margin"]) < -PAST_EPS else 0.0
			fr["verdict"] = classify(float(best["margin"]))
		frames.append(fr)
	return _summarise(frames, fps, li)


static func _summarise(frames: Array, fps: int, li: int) -> Dictionary:
	var at := -1
	var best := INF
	for fr in frames:
		if fr["contact"] and float(fr["margin_deg"]) <= best:
			best = float(fr["margin_deg"])
			at = int(fr["f"])
	if at < 0:
		var mg := INF
		for fr in frames:
			if float(fr["gap"]) < mg:
				mg = float(fr["gap"])
				at = int(fr["f"])
	var k: Dictionary = frames[at]
	var d := {"ok": true, "msg": "", "fps": fps, "n": frames.size(), "locker": li, "frames": frames, "frame": at, "verdict": k["verdict"],
		"min_gap": k["gap"], "joint": k["joint"], "axis": k["axis"], "side": k["side"], "angle_deg": k["angle_deg"], "lo_deg": k["lo_deg"],
		"hi_deg": k["hi_deg"], "margin_deg": k["margin_deg"], "past_deg": k["past_deg"]}
	d["text"] = words_of(d)
	d["msg"] = d["text"]
	return d


static func words_of(r: Dictionary) -> String:
	var v: String = r["verdict"]
	var at: int = r["frame"]
	if at < 0:
		return "NO CONTACT: no frames"
	var when := "at f %d (%.2f s)" % [at, float(at) / float(r["fps"])]
	if v == V_NONE:
		return "NO CONTACT: the locker never touches the partner's arm; the closest he comes is %.1f cm (%s)." % [float(r["min_gap"]) * 100.0, when]
	var what := "his %s %s %s" % [r["side"], r["joint"], r["axis"]]
	var ang := "the clip asks %.1f deg, his range is %.1f to %.1f" % [float(r["angle_deg"]), float(r["lo_deg"]), float(r["hi_deg"])]
	match v:
		V_PAST:
			return "PAST LIMIT: INJURY %s: %s is %.1f deg past his limit (%s)." % [when, what, float(r["past_deg"]), ang]
		V_AT:
			return "AT LIMIT %s: %s is %.1f deg inside his limit (%s)." % [when, what, float(r["margin_deg"]), ang]
	return "LOCK NOT ON %s: the locker touches the arm but the nearest limit, %s, is %.1f deg away (%s)." % [when, what, float(r["margin_deg"]), ang]


static func words(r: Dictionary) -> String:
	return String(r.get("text", r.get("msg", "")))


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


## JSON-safe: Vectors as arrays, angles rounded to 0.001 deg
static func to_json(r: Dictionary) -> Dictionary:
	var out := {"ok": r.get("ok", false), "verdict": r.get("verdict", ""), "frame": r.get("frame", -1), "fps": r.get("fps", 0), "n": r.get("n", 0),
		"locker": r.get("locker", 0), "joint": r.get("joint", ""), "axis": r.get("axis", ""), "side": r.get("side", ""),
		"angle_deg": snappedf(float(r.get("angle_deg", 0.0)), 0.001), "lo_deg": snappedf(float(r.get("lo_deg", 0.0)), 0.001), "hi_deg": snappedf(float(r.get("hi_deg", 0.0)), 0.001),
		"margin_deg": snappedf(float(r.get("margin_deg", 0.0)), 0.001), "past_deg": snappedf(float(r.get("past_deg", 0.0)), 0.001),
		"text": r.get("text", r.get("msg", "")), "min_gap": snappedf(minf(float(r.get("min_gap", 99.0)), 99.0), 0.0001), "frames": []}
	for fr in r.get("frames", []):
		var pts := []
		for c in fr["points"]:
			pts.append({"locker_part": c["a"], "partner_part": c["b"], "at": _v3(c["at"]), "gap_m": snappedf(c["gap"], 0.0001)})
		(out["frames"] as Array).append({"f": fr["f"], "t": snappedf(fr["t"], 0.0001), "verdict": fr["verdict"], "contact": fr["contact"], "points": pts,
			"joint": fr["joint"], "axis": fr["axis"], "side": fr["side"], "angle_deg": snappedf(float(fr["angle_deg"]), 0.001),
			"margin_deg": snappedf(float(fr["margin_deg"]), 0.001), "past_deg": snappedf(float(fr["past_deg"]), 0.001)})
	return out
