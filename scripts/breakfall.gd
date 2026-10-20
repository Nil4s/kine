## breakfall.gd - I25 BREAKFALL CHECK. Finds the falls and knockdowns of a clip and judges each landing the way a stunt / judo coach does.
## FINDING A FALL: the clip is played at 60 Hz on the scene's own grounding (Scene.apply); a fall is a stretch where the centre of mass
## (Balance.com) drops more than DROP = 40 % of the standing height (the tallest head top of the clip) within WIN = 1 s, and a body part
## other than the feet (feet, calves and toe pads are left out; a knee, a hand, the back all count) comes within TOUCH = 2 cm of the floor (y = 0).
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
const SLAP_SMOOTH := 0.05    # cost per degree the upper arm turns away from the arm of the card before (keeps the slap from swinging the hand through the landing)
const TURN_MIN := 45.0      # forward fall: the head counts as turned aside from this much neck + head rotation (mae ukemi: head to one side, ~60-90 deg of neck rotation)
const TURN_SIDE := 30.0     # side fall: head turned away from the floor side
const HEAD_V := 2.0         # m/s: cheek-side contact of a turned head under this is read as a safe landing
const CLEAR := 0.05         # head clear of the floor: 5 cm
const TURN_NECK := 40.0     # the fix: neck twist stop is 40 deg, head 35 deg -> 75 deg in all
const TURN_HEAD := 35.0
const EXT_NECK := -12.0     # forward fall: slight neck extension to lift the face (stops: neck -30, head -25)
const EXT_HEAD := -8.0
const ELB0 := 30.0          # the absorbing arm: elbow at contact, then ELB1 after ELB_T seconds
const ELB1 := 90.0
const ELB_T := 0.15
const PARTS := ["pelvis", "hips_wide", "spine_01", "spine_02", "spine_03", "chest_wide", "neck_01", "head", "clavicle_l", "clavicle_r",
	"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "thigh_l", "thigh_r"]   # the calves are left out like the feet: they are the support, always within centimetres of the floor, and on a body that tips about its feet they are the lowest part and would read as the "first touch"


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
			"turn": float((B.ang["neck_01"] as Vector3).z + (B.ang["head"] as Vector3).z),
			"tr": (B.P["neck_01"] as Vector3) - (B.P["pelvis"] as Vector3), "lf": ta, "com3": Balance.com(B),
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
	# direction of the fall: the trunk's lean at the impact against the facing and left axes at the start of the fall (left x up = forward)
	var tr0: Vector3 = fr[jm]["tr"]
	var fc := (fr[jm]["lf"] as Vector3).cross(tr0)
	fc = Vector3(fc.x, 0, fc.z).normalized()
	var lt := Vector3(fc.z * -1.0, 0, fc.x)   # fc rotated: left of the facing is +90 deg about Y (X-forward-left basis of the hero: forward Z, left X)
	lt = Vector3.UP.cross(fc) * -1.0
	var lean: Vector3 = fr[c]["tr"]
	lean = Vector3(lean.x, 0, lean.z)
	if lean.length() < 0.15 * (fr[c]["tr"] as Vector3).length():
		lean = (fr[c]["com3"] as Vector3) - (fr[jm]["com3"] as Vector3)
		lean = Vector3(lean.x, 0, lean.z)
	var dang := rad_to_deg(atan2(lean.dot(lt), lean.dot(fc)))
	var dir := "forward" if absf(dang) <= 45.0 else ("backward" if absf(dang) >= 135.0 else "side")
	var floor_side := "" if dir != "side" else ("_l" if dang > 0.0 else "_r")
	# (a) head: forward = clear by 5 cm or turned aside with a slow cheek contact; backward = chin tucked; side = turned away from the floor side
	var hc := INF
	var tj := -1
	for j in range(c, mini(n, c + int(HEAD_WIN * HZ) + 1)):
		hc = minf(hc, float(fr[j]["low"]["head"]))
		if tj < 0 and float(fr[j]["low"]["head"]) <= TOUCH:
			tj = j
	var chin: float = fr[c]["chin"]
	var turn := absf(float(fr[c]["turn"]))
	var hv := 0.0
	if tj >= 0:
		var j0 := maxi(jm, tj - 6)
		hv = (float(fr[j0]["low"]["head"]) - float(fr[tj]["low"]["head"])) / maxf(float(fr[tj]["t"]) - float(fr[j0]["t"]), 1e-6)
	var ca := "ok"
	var how := ""
	if dir == "forward":
		if hc >= CLEAR:
			how = "clear: the head stays %.0f cm above the floor" % (hc * 100.0)
		elif turn >= TURN_MIN and (tj < 0 or hv < HEAD_V):
			how = "turned aside %.0f deg%s" % [turn, "" if tj < 0 else ", cheek contact %.1f m/s" % hv]
		else:
			ca = "fail" if hc < TOUCH else "warn"
			how = "head %.0f cm up, turned %.0f deg%s" % [hc * 100.0, turn, "" if tj < 0 else ", contact %.1f m/s" % hv]
	elif dir == "backward":
		ca = "fail" if hc < TOUCH else ("warn" if chin < TUCK_MIN else "ok")
		how = "chin %.0f deg, head %.0f cm up" % [chin, hc * 100.0]
	else:
		ca = "fail" if hc < TOUCH else ("ok" if (hc >= CLEAR or turn >= TURN_SIDE) else "warn")
		how = "head %.0f cm up, turned %.0f deg" % [hc * 100.0, turn]
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
	return {"t0": fr[jm]["t"], "t_c": t_c, "t1": t_c + HEAD_WIN, "part": lowest, "first": first, "chin": chin, "head_clear": hc, "dir": dir, "floor_side": floor_side, "turn": turn, "head_v": hv, "head_how": how, "dang": dang, "side": side, "elbow": el,
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
## prev = true also takes the card BEFORE them: a neck that starts its flexion on that card has already bent when the landing card arrives (the
## tuck starts before the fall's last pose, so the impact frame reaches the bar instead of being half way there)
static func landing_cards(S: Scene, f: Dictionary, prev := false) -> Array:
	var ts := S.times()
	var out := []
	for i in S.cards.size():
		var arr: float = ts[i][1]
		if arr > float(f["t0"]) - 0.02 and arr <= float(f["t1"]) + 0.5:
			out.append(i)
	if prev and not out.is_empty() and int(out[0]) > 0:
		out.push_front(int(out[0]) - 1)
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


## fix 1: protect the head, by the direction of the fall (judo ukemi). FORWARD (face-down, mae ukemi): the head is TURNED to one side (neck 40 + head
## 35 deg of twist, the stops) and lifted a little by neck extension; a chin tuck there drives the face into the floor. BACKWARD (ushiro ukemi): the
## chin tucked, neck + head flexed to 40 deg. SIDE: the head turned away from the floor side. Both turn directions are built and the better kept.
static func tuck(S: Scene, f: Dictionary) -> Dictionary:
	if String(f["a"]) == "ok":
		return {"ok": false, "why": "the head is already safe (%s): nothing to change" % String(f["head_how"])}
	var dir := String(f["dir"])
	var best := {}
	var bscore := -999.0
	for sg in ([1.0, -1.0] if dir != "backward" else [1.0]):
		var nS := S.clone()
		var B := DistanceKeeper.new_body()
		var cs := landing_cards(nS, f, true)
		if cs.is_empty():
			return {"ok": false, "why": "no card arrives during this landing: add a pose after the fall, then try again"}
		for i in cs:
			var c: Dictionary = nS.cards[i]
			var pairs := []
			if dir == "backward":
				pairs = [["neck_01", "bend", CHIN_NECK, true], ["head", "bend", CHIN_HEAD, true]]
			else:
				pairs = [["neck_01", "twist", sg * TURN_NECK, false], ["head", "twist", sg * TURN_HEAD, false]]
				if dir == "forward":
					pairs += [["neck_01", "bend", EXT_NECK, false], ["head", "bend", EXT_HEAD, false]]
			for pr in pairs:
				var x: Dictionary = _joint(c, pr[0])
				var r: Vector2 = B.lim[pr[0]][pr[1]]
				var v := float(pr[2])
				if bool(pr[3]):
					v = maxf(float(x[pr[1]]), v)
				elif pr[1] == "bend":
					v = minf(float(x[pr[1]]), v)
				x[pr[1]] = snappedf(clampf(v, r.x, r.y), 0.01)
		var msg := "tuck the chin (backward fall): neck + head flexed to %.0f deg" % (CHIN_NECK + CHIN_HEAD)
		if dir == "forward":
			msg = "forward fall: turn the head aside %.0f deg (not a tuck) and lift it a little (neck extension)" % (TURN_NECK + TURN_HEAD)
		elif dir == "side":
			msg = "side fall: turn the head %.0f deg, away from the floor side" % (TURN_NECK + TURN_HEAD)
		var r2 := _done(S, nS, f, "tuck", msg + " in %d card%s" % [cs.size(), "" if cs.size() == 1 else "s"])
		var af: Dictionary = r2["after"]
		var sc := -999.0 if af.is_empty() else float(af["head_clear"]) - 10.0 * float(["ok", "warn", "fail"].find(String(af["a"])))
		if sc > bscore:
			bscore = sc
			best = r2
	return best


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
	var ts := nS.times()
	if cs.is_empty():
		return {"ok": false, "why": "no card arrives during this landing: add a pose after the fall, then try again"}
	# both arms: a fall is caught by whichever hand is lower a frame later, so bending one arm only hands the straight-arm landing to the other
	for s2: String in [sd, "_r" if sd == "_l" else "_l"]:
		var ua := "upperarm" + s2
		var la := "lowerarm" + s2
		var rb: Vector2 = B.lim[ua]["bend"]
		var rs: Vector2 = B.lim[ua]["side"]
		var rt: Vector2 = B.lim[ua]["twist"]
		var prev_a := Vector3.INF   # the arm of the card before: the search stays near it (an arm that swings 140 deg in one card is the fastest part of the landing)
		if int(cs[0]) > 0:
			B.from_dict(nS.cards[int(cs[0]) - 1]["pose"])
			prev_a = B.ang[ua] as Vector3
		for i in cs:
			var c: Dictionary = nS.cards[i]
			B.from_dict(c["pose"])
			# the elbow absorbs: ELB0 deg at the contact, ELB1 deg ELB_T s later (cards before the contact keep ELB0 or more)
			var arr: float = ts[i][1]
			var el := ELB0 + (ELB1 - ELB0) * clampf((arr - float(f["t_c"])) / ELB_T, 0.0, 1.0)
			if arr <= float(f["t_c"]) + 1e-4:
				el = maxf(el, minf(float((B.ang[la] as Vector3).x), 60.0))
			B.ang[la] = Vector3(el, 0, 0)
			var best := INF
			var bv := B.ang[ua] as Vector3
			for sv in range(-90, -15, 5):
				for tw in range(-70, 71, 10):
					for bd in [-30, -15, 0, 15, 30]:
						B.ang[ua] = Vector3(clampf(bd, rb.x, rb.y), clampf(sv, rs.x, rs.y), clampf(tw, rt.x, rt.y))
						B.fk_sub(ua)
						var cost := _arm_cost(B, s2) + 0.05 * absf(bd)
						if prev_a.x < 1e8:
							var dv := (B.ang[ua] as Vector3) - prev_a
							cost += SLAP_SMOOTH * (absf(dv.x) + absf(dv.y) + absf(dv.z))
						if cost < best:
							best = cost
							bv = B.ang[ua]
			prev_a = bv
			_put(c, ua, bv)
			_put(c, la, B.ang[la])
	return _done(S, nS, f, "slap", "bend the catching arms (both) into a slap: elbow %.0f deg at the contact rising to %.0f deg %.2f s later (the arm absorbs), arm %.0f deg off the body, forearm flat, in %d card%s" % [ELB0, ELB1, ELB_T, SLAP_DEG, cs.size(), "" if cs.size() == 1 else "s"])


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


## fix 4: SLOW THE LANDING. The speed verdict cannot be mended by a pose: the hands land when the body has toppled far enough, so a bent slap arm
## only lands later in the same fixed-speed topple. The timing has to change. Two moves, the way ukemi is taught (lower first, fall from low):
##  (1) LOWER FIRST: a card is added before the topple in which the knees and hips bend (LOW_THIGH / LOW_CALF, "sit back") and the body is lowered
##      over LOW_T; the bend then unwinds across the topple cards (linearly to the original legs at the last card), so the trunk tips from a
##      lower centre of mass and the free-fall height to the floor is shorter.
##  (2) SLOW THE LAST CARDS: the cards that bring the body to the floor (arriving in the LAST_WIN s before the impact) are stretched, by STRETCH
##      steps, until the first part lands at SLOW_TARGET (under SPEED_OK) or the fall would last past FALL_CAP.
## WHY FALL_CAP = 1.0 s from the start of the lowering to the impact (and about 1.5 s with the HEAD_WIN + slap that follows): a knockdown IS a
## drop of 40 % of the standing height within WIN = 1 s (the definition this tool uses), a longer fall reads as a sit or a kneel and the checker
## would stop finding it; and a trained faller takes about 1 s from the start of a forward drop to the mat (judo ukemi video measurements are not
## in this repo; the number is a heuristic). Source for the target speed: van den Kroonenberg, Hayes & McMahon 1995 (J Biomech Eng 117): hip
## impact speed of a SIDEWAYS fall from standing is ~2 m/s untrained; Groen, Weerdesteyn & Duysens 2007 (J Biomech 40) found judo-trained
## fallers land with a lower impact velocity than untrained ones. Both quoted from memory, not re-read here, so SPEED_OK stays a heuristic.
const LOW_THIGH := 80.0
const LOW_CALF := 100.0
const LOW_T := 0.2
const LAST_WIN := 0.4
const STRETCH := 1.2
const SLOW_TARGET := 2.3
const FALL_CAP := 1.0


static func _legs(card: Dictionary, th: float, ca: float) -> void:
	for sd in ["_l", "_r"]:
		_joint(card, "thigh" + sd)["bend"] = snappedf(th, 0.01)
		_joint(card, "calf" + sd)["bend"] = snappedf(ca, 0.01)


static func lower(S: Scene, f: Dictionary) -> Dictionary:
	if float(f["speed"]) <= SPEED_OK:
		return {"ok": false, "why": "the landing speed is already %.1f m/s (under %.1f): nothing to slow" % [float(f["speed"]), SPEED_OK]}
	var cs := landing_cards(S, f)
	if cs.is_empty() or int(cs[0]) == 0:
		return {"ok": false, "why": "no card arrives before this fall to lower from: add a standing pose before the fall, then try again"}
	var best := {}
	var bsp := INF
	for crouch in [true, false]:
		var nS := S.clone()
		var cs2 := landing_cards(nS, f)
		var first: int = cs2[0]
		var last: int = cs2[cs2.size() - 1]
		if crouch:
			var nc := {"name": "lower", "pose": (nS.cards[first - 1]["pose"] as Dictionary).duplicate(true), "move": LOW_T, "hold": 0.0}
			_legs(nc, LOW_THIGH, LOW_CALF)
			for k in cs2.size():
				var c: Dictionary = nS.cards[cs2[k]]
				var w := 1.0 - float(k + 1) / float(cs2.size())
				var th := maxf(float(_joint(c, "thigh_l")["bend"]), LOW_THIGH * w)
				var ca := maxf(float(_joint(c, "calf_l")["bend"]), LOW_CALF * w)
				_legs(c, th, ca)
			nS.cards.insert(first, nc)
			cs2 = landing_cards(nS, f)
		var rounds := 0
		var rep := {}
		var g := {}
		while rounds < 14:
			rep = analyze(nS)
			g = _near(rep, f)
			if g.is_empty() or float(g["speed"]) <= SLOW_TARGET:
				break
			var ts := nS.times()
			var tc: float = g["t_c"]
			var any := false
			if tc - float(g["t0"]) > FALL_CAP:   # no room left: the early cards (the drop before the last LAST_WIN s) are shortened to pay for the slow ones
				for i in nS.cards.size():
					if float(ts[i][1]) <= tc - LAST_WIN and float(ts[i][0]) >= float(g["t0"]) - 0.02 and i > 0 and float(nS.cards[i]["move"]) > 0.08:
						nS.cards[i]["move"] = snappedf(maxf(0.06, float(nS.cards[i]["move"]) * 0.8), 0.001)
						any = true
			for i in nS.cards.size():
				if float(ts[i][1]) > tc - LAST_WIN and float(ts[i][0]) < tc + 1e-4 and i > 0:
					nS.cards[i]["move"] = snappedf(float(nS.cards[i]["move"]) * STRETCH, 0.001)
					any = true
			if not any:
				break
			rounds += 1
		if g.is_empty():
			continue
		# the lowering is preferred (it is the taught way) when it reaches the target with the head, arm and spread verdicts kept; else the lowest speed wins
		var sc := float(g["speed"]) + (0.0 if tc_ok(g) else 10.0)
		if crouch and sc <= SLOW_TARGET and String(g["a"]) == "ok" and String(g["b"]) == "ok" and String(g["c"]) != "fail":
			sc -= 100.0
		if sc < bsp:
			bsp = sc
			best = {"scene": nS, "rep": rep, "after": g, "crouch": crouch, "rounds": rounds}
	if best.is_empty():
		return {"ok": false, "why": "the fall is lost when retimed: check the cards around the landing"}
	var g2: Dictionary = best["after"]
	return {"ok": true, "kind": "lower", "scene": best["scene"], "rep": best["rep"], "after": g2, "msg": "slow the landing: %s the last cards stretched %d times by %.0f%%: first contact %.1f m/s (was %.1f), the fall lasts %.2f s from its start to the impact" % [
		"knees bend first (%.0f deg hips, %.0f deg knees, %.2f s) and unwind as the trunk tips;" % [LOW_THIGH, LOW_CALF, LOW_T] if bool(best["crouch"]) else "", int(best["rounds"]), (STRETCH - 1.0) * 100.0, float(g2["speed"]), float(f["speed"]), float(g2["t_c"]) - float(g2["t0"])]}


static func tc_ok(g: Dictionary) -> bool:
	return float(g["t_c"]) - float(g["t0"]) <= FALL_CAP + 0.05
