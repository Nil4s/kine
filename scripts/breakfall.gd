## breakfall.gd - I25 BREAKFALL CHECK. Finds the falls and knockdowns of a clip and judges each landing the way a stunt / judo coach does.
## FINDING A FALL: the clip is played at 60 Hz on the scene's own grounding (Scene.apply); a fall is a stretch where the centre of mass
## (Balance.com) drops more than DROP = 40 % of the standing height (the tallest head top of the clip) within WIN = 1 s, and a body part
## other than the feet (feet and toe pads are left out; a knee, a hand, the back all count) comes within TOUCH = 2 cm of the floor (y = 0).
## The first such frame is the IMPACT. The standing height, 40 % and 1 s are the roadmap's definition of a knockdown, not a published standard.
## THE FOUR RULES, judged at the landing. The sources are the practice of judo ukemi (Kodokan: the chin tucked "eyes on the belt", the arm slaps
## the mat at about 30-45 deg from the body with the palm down, the fall spread over arm, shoulder, back or the side of the hip) and stunt
## falling teaching; I did not find a measured standard that gives their numbers, so every threshold below is a HEURISTIC, named, and can be
## changed to taste. Hip impact speed of a sideways fall from standing is ~2 m/s in measurements (van den Kroonenberg, Hayes, McMahon 1995,
## J Biomech Eng 117; quoted from memory, not re-read here), which is where SPEED_OK comes from.
##  (a) HEAD AND CHIN: the head capsule's lowest surface stays above TOUCH for HEAD_WIN = 0.6 s from the impact (else FAIL), and the neck+head
##      flexion (neck_01 + head bend, "+ = chin down") at the impact is at least TUCK_MIN = 25 deg (else WARN). Number: clearance cm, chin deg.
##  (b) STRAIGHT-ARM CATCH: when a hand or forearm is among the first parts to touch, the elbow flexion at the impact must be at least
##      ELBOW_OK = 30 deg (20-30 WARN, under ELBOW_BAD = 20 FAIL: a locked arm sends the load to the wrist and elbow). Number: elbow deg.
##  (c) SPREAD: the parts that touch within SPREAD_WIN = 0.15 s of the impact fall in the regions arm (upper arm, forearm, hand), back
##      (spine, chest, collar bone) and hip side (pelvis with the body rolled over: the thighs' axis steeper than 30 deg from the floor).
##      Two or more of them OK, one WARN, none (knees, or the tailbone, alone) FAIL. Number: the regions.
##  (d) SPEED: the downward speed of the first part, over the 0.1 s before the touch: up to SPEED_OK = 2.5 m/s OK, up to SPEED_BAD = 4 WARN,
##      above FAIL.
## FIXES (each builds a changed COPY of the landing cards; the caller previews and accepts):
##  tuck(): neck_01 and head are flexed to CHIN_NECK + CHIN_HEAD = 26 + 14 = 40 deg (inside their 35 / 25 deg stops) in every landing card.
##  slap(): the catching arm is searched (grid over the upper arm's three angles, the elbow set to SLAP_ELBOW = 55 deg) so the arm lies
##      SLAP_DEG = 45 deg from the trunk and, in a lying card, the forearm is flat on the floor (tilt measured and minimised).
##  roll(): the pelvis is turned ROLL_DEG = 40 deg about the trunk's long axis, the side that scores the best spread (both tried).
class_name Breakfall
extends RefCounted

const DROP := 0.4
const WIN := 1.0
const TOUCH := 0.02
const HZ := 60.0
const HEAD_WIN := 0.6
const TUCK_MIN := 25.0
const ELBOW_OK := 30.0
const ELBOW_BAD := 20.0
const SPREAD_WIN := 0.15
const SPEED_OK := 2.5
const SPEED_BAD := 4.0
const CHIN_NECK := 26.0
const CHIN_HEAD := 14.0
const SLAP_ELBOW := 55.0
const SLAP_DEG := 45.0
const ROLL_DEG := 40.0
const PARTS := ["pelvis", "hips_wide", "spine_01", "spine_02", "spine_03", "chest_wide", "neck_01", "head", "clavicle_l", "clavicle_r",
	"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "thigh_l", "thigh_r", "calf_l", "calf_r"]


static func region(p: String) -> String:
	if p.begins_with("upperarm") or p.begins_with("lowerarm") or p.begins_with("hand"):
		return "arm"
	if p.begins_with("spine") or p == "chest_wide" or p.begins_with("clavicle"):
		return "back"
	if p == "pelvis" or p == "hips_wide":
		return "hip"
	if p.begins_with("thigh") or p.begins_with("calf"):
		return "knee"
	return "head"


static func _low(B: Body, p: String) -> float:
	var c: Array = B.cap(p)
	return minf((c[0] as Vector3).y, (c[1] as Vector3).y) - float(B.rad[p])


## the clip at 60 Hz: [{"t", "com", "top", "low": {part: lowest surface y}, "chin", "el": {"_l", "_r"}, "lat"}]
static func frames(S: Scene) -> Array:
	var sc := S.clone()
	sc.baker = null
	var B := DistanceKeeper.new_body()
	var out := []
	var n := int(sc.length() * HZ) + 1
	for k in n:
		var t := k / HZ
		sc.apply(B, t)
		var low := {}
		for p in PARTS:
			low[p] = _low(B, p)
		var hc: Array = B.cap("head")
		var ta: Vector3 = B.P["thigh_l"] - (B.P["thigh_r"] as Vector3)
		out.append({"t": t, "com": Balance.com(B).y, "top": maxf((hc[0] as Vector3).y, (hc[1] as Vector3).y) + float(B.rad["head"]), "low": low,
			"chin": float((B.ang["neck_01"] as Vector3).x + (B.ang["head"] as Vector3).x),
			"el": {"_l": float((B.ang["lowerarm_l"] as Vector3).x), "_r": float((B.ang["lowerarm_r"] as Vector3).x)},
			"lat": absf(ta.y) / maxf(ta.length(), 1e-6)})
	return out


static func _worst(a: String, b: String) -> String:
	return "fail" if a == "fail" or b == "fail" else ("warn" if a == "warn" or b == "warn" else "ok")


## the judged falls of the frames
static func judge(fr: Array) -> Array:
	var falls := []
	var n := fr.size()
	if n < 3:
		return falls
	var hs := 0.0
	for f in fr:
		hs = maxf(hs, float(f["top"]))
	var w := int(WIN * HZ)
	var k := 0
	while k < n:
		var jm := maxi(0, k - w)
		var mx := -INF
		for j in range(jm, k + 1):
			mx = maxf(mx, float(fr[j]["com"]))
		for j in range(jm, k + 1):   # the LAST frame still at the top: where the drop starts
			if float(fr[j]["com"]) >= mx - 0.01:
				jm = j
		if float(fr[jm]["com"]) - float(fr[k]["com"]) <= DROP * hs:
			k += 1
			continue
		var c := -1
		for j in range(jm, mini(n, k + int(0.5 * HZ))):
			if float(fr[jm]["com"]) - float(fr[j]["com"]) < 0.05:
				continue
			for p in PARTS:
				if float(fr[j]["low"][p]) <= TOUCH:
					c = j
					break
			if c >= 0:
				break
		if c < 0:
			k += 1
			continue
		falls.append(_fall(fr, jm, c))
		k = c + int(WIN * HZ)
	return falls


static func _touching(f: Dictionary) -> Array:
	var out := []
	for p in PARTS:
		if float(f["low"][p]) <= TOUCH:
			out.append(p)
	return out


static func _fall(fr: Array, jm: int, c: int) -> Dictionary:
	var n := fr.size()
	var t_c: float = fr[c]["t"]
	var first := _touching(fr[c])
	var lowest := ""
	for p in first:
		if lowest == "" or float(fr[c]["low"][p]) < float(fr[c]["low"][lowest]):
			lowest = p
	# (a) head and chin
	var hc := INF
	for j in range(c, mini(n, c + int(HEAD_WIN * HZ) + 1)):
		hc = minf(hc, float(fr[j]["low"]["head"]))
	var chin: float = fr[c]["chin"]
	var ca := "fail" if hc < TOUCH else ("warn" if chin < TUCK_MIN else "ok")
	# (b) arm
	var side := ""
	for p in first:
		if region(p) == "arm" and (p.begins_with("hand") or p.begins_with("lowerarm")):
			side = p.substr(p.length() - 2)
			break
	var el := -1.0
	var cb := "ok"
	if side != "":
		el = float(fr[c]["el"][side])
		cb = "fail" if el < ELBOW_BAD else ("warn" if el < ELBOW_OK else "ok")
	# (c) spread
	var regs := {}
	for j in range(c, mini(n, c + int(SPREAD_WIN * HZ) + 1)):
		for p in _touching(fr[j]):
			var r := region(p)
			if r == "hip":
				r = "hip side" if float(fr[j]["lat"]) > 0.5 else "tailbone"
			regs[r] = true
	var good := 0
	for r in ["arm", "back", "hip side"]:
		if regs.has(r):
			good += 1
	var cc := "ok" if good >= 2 else ("warn" if good == 1 else "fail")
	# (d) speed
	var c0 := maxi(jm, c - 6)
	var vs := 0.0
	if lowest != "":
		vs = (float(fr[c0]["low"][lowest]) - float(fr[c]["low"][lowest])) / maxf(float(fr[c]["t"]) - float(fr[c0]["t"]), 1e-6)
	var cd := "ok" if vs <= SPEED_OK else ("warn" if vs <= SPEED_BAD else "fail")
	var cls := _worst(_worst(ca, cb), _worst(cc, cd))
	return {"t0": fr[jm]["t"], "t_c": t_c, "t1": t_c + HEAD_WIN, "part": lowest, "first": first, "chin": chin, "head_clear": hc, "side": side, "elbow": el,
		"regions": regs.keys(), "good": good, "speed": vs, "a": ca, "b": cb, "c": cc, "d": cd, "cls": cls}


## all the falls of a scene: {"ok", "msg", "falls", "bad"}
static func analyze(S: Scene) -> Dictionary:
	var fa := judge(frames(S))
	var bad := 0
	for f in fa:
		if f["cls"] != "ok":
			bad += 1
	var msg := "no fall found: the centre of mass never drops %.0f%% of the standing height in %.0f s with a body part on the floor (play a fall or a knockdown, or 'React to the hit (physics)')" % [DROP * 100.0, WIN]
	if not fa.is_empty():
		msg = "%d fall%s: %d to fix" % [fa.size(), "" if fa.size() == 1 else "s", bad] if bad > 0 else "%d fall%s, every landing reads safe" % [fa.size(), "" if fa.size() == 1 else "s"]
	return {"ok": not fa.is_empty(), "msg": msg, "falls": fa, "bad": bad}


## the cards that make the landing of a fall: those arriving from the start of the fall to a little after the head window
static func landing_cards(S: Scene, f: Dictionary) -> Array:
	var ts := S.times()
	var out := []
	for i in S.cards.size():
		var arr: float = ts[i][1]
		if arr > float(f["t0"]) - 0.02 and arr <= float(f["t1"]) + 0.5:
			out.append(i)
	return out


static func _near(rep: Dictionary, f: Dictionary) -> Dictionary:
	var best := {}
	for g in rep["falls"]:
		if absf(float(g["t0"]) - float(f["t0"])) < 0.5 and (best.is_empty() or absf(float(g["t0"]) - float(f["t0"])) < absf(float(best["t0"]) - float(f["t0"]))):
			best = g
	return best


static func _joint(card: Dictionary, j: String) -> Dictionary:
	return (card["pose"] as Dictionary)["joints"][j]


static func _put(card: Dictionary, j: String, v: Vector3) -> void:
	var x: Dictionary = _joint(card, j)
	x["bend"] = snappedf(v.x, 0.01)
	x["side"] = snappedf(v.y, 0.01)
	x["twist"] = snappedf(v.z, 0.01)


static func _done(S: Scene, nS: Scene, f: Dictionary, kind: String, msg: String) -> Dictionary:
	var rep := analyze(nS)
	return {"ok": true, "kind": kind, "scene": nS, "msg": msg, "after": _near(rep, f), "rep": rep}


## fix 1: tuck the chin in every landing card
static func tuck(S: Scene, f: Dictionary) -> Dictionary:
	if String(f["a"]) == "ok":
		return {"ok": false, "why": "the chin is already tucked (%.0f deg) and the head stays clear: nothing to tuck" % float(f["chin"])}
	var nS := S.clone()
	var B := DistanceKeeper.new_body()
	var cs := landing_cards(nS, f)
	if cs.is_empty():
		return {"ok": false, "why": "no card arrives during this landing: add a pose after the fall, then try again"}
	for i in cs:
		var c: Dictionary = nS.cards[i]
		for pr in [["neck_01", CHIN_NECK], ["head", CHIN_HEAD]]:
			var x: Dictionary = _joint(c, pr[0])
			var r: Vector2 = B.lim[pr[0]]["bend"]
			x["bend"] = snappedf(clampf(maxf(float(x["bend"]), float(pr[1])), r.x, r.y), 0.01)
	return _done(S, nS, f, "tuck", "tuck the chin: neck + head flexed to %.0f deg in %d card%s" % [CHIN_NECK + CHIN_HEAD, cs.size(), "" if cs.size() == 1 else "s"])


## the cost of an arm setting: how far the upper arm is from SLAP_DEG off the trunk, plus (a lying card) the forearm's tilt off the floor
static func _arm_cost(B: Body, sd: String) -> float:
	var ua := (B.E["upperarm" + sd] as Vector3) - (B.P["upperarm" + sd] as Vector3)
	var tr := (B.P["pelvis"] as Vector3) - (B.P["neck_01"] as Vector3)
	var a := rad_to_deg(acos(clampf(ua.normalized().dot(tr.normalized()), -1.0, 1.0)))
	var fa := (B.P["hand" + sd] as Vector3) - (B.P["lowerarm" + sd] as Vector3)
	var lying := absf(tr.normalized().y) < 0.5
	var tilt := rad_to_deg(asin(clampf(absf(fa.normalized().y), 0.0, 1.0)))
	return absf(a - SLAP_DEG) + (tilt if lying else 0.0)


## fix 2: the catching arm bent into a slap in every landing card
static func slap(S: Scene, f: Dictionary) -> Dictionary:
	var sd: String = f["side"]
	if sd == "" or String(f["b"]) == "ok":
		return {"ok": false, "why": "no straight-arm catch in this fall (%s): nothing to bend" % ("no hand or forearm lands first" if sd == "" else "the elbow is bent %.0f deg" % float(f["elbow"]))}
	var nS := S.clone()
	var B := DistanceKeeper.new_body()
	var cs := landing_cards(nS, f)
	if cs.is_empty():
		return {"ok": false, "why": "no card arrives during this landing: add a pose after the fall, then try again"}
	var ua := "upperarm" + sd
	var la := "lowerarm" + sd
	var rb: Vector2 = B.lim[ua]["bend"]
	var rs: Vector2 = B.lim[ua]["side"]
	var rt: Vector2 = B.lim[ua]["twist"]
	for i in cs:
		var c: Dictionary = nS.cards[i]
		B.from_dict(c["pose"])
		B.ang[la] = Vector3(maxf(float((B.ang[la] as Vector3).x), SLAP_ELBOW), 0, 0)
		var best := INF
		var bv := B.ang[ua] as Vector3
		for sv in range(-90, -15, 5):
			for tw in range(-70, 71, 10):
				for bd in [-30, -15, 0, 15, 30]:
					B.ang[ua] = Vector3(clampf(bd, rb.x, rb.y), clampf(sv, rs.x, rs.y), clampf(tw, rt.x, rt.y))
					B.fk_sub(ua)
					var cost := _arm_cost(B, sd) + 0.05 * absf(bd)
					if cost < best:
						best = cost
						bv = B.ang[ua]
		_put(c, ua, bv)
		_put(c, la, B.ang[la])
	return _done(S, nS, f, "slap", "bend the catching arm (%s) into a slap: elbow %.0f deg, arm %.0f deg off the body, forearm flat, in %d card%s" % [sd.substr(1).to_upper(), SLAP_ELBOW, SLAP_DEG, cs.size(), "" if cs.size() == 1 else "s"])


## fix 3: roll the trunk so the shoulder / back / hip side lands first
static func roll(S: Scene, f: Dictionary) -> Dictionary:
	if String(f["c"]) == "ok":
		return {"ok": false, "why": "the impact is already spread over %s: nothing to roll" % ", ".join(f["regions"])}
	var cs := landing_cards(S, f)
	if cs.is_empty():
		return {"ok": false, "why": "no card arrives during this landing: add a pose after the fall, then try again"}
	var best := {}
	var bscore := -999
	for sg in [1.0, -1.0]:
		var nS := S.clone()
		var B := DistanceKeeper.new_body()
		for i in cs:
			var c: Dictionary = nS.cards[i]
			B.from_dict(c["pose"])
			var ax := ((B.P["neck_01"] as Vector3) - (B.P["pelvis"] as Vector3)).normalized()
			B.turn_world("pelvis", Quaternion(ax, deg_to_rad(ROLL_DEG * sg)))
			_put(c, "pelvis", B.ang["pelvis"])
		var r := _done(S, nS, f, "roll", "roll the trunk %.0f deg (%s) so the shoulder and back land first, in %d card%s" % [ROLL_DEG, "to his left" if sg > 0.0 else "to his right", cs.size(), "" if cs.size() == 1 else "s"])
		var af: Dictionary = r["after"]
		var sc := -999 if af.is_empty() else int(af["good"]) * 10 - int(["ok", "warn", "fail"].find(String(af["cls"])))
		if sc > bscore:
			bscore = sc
			best = r
	return best
