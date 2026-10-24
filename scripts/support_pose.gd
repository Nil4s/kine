## support_pose.gd - POSE FROM SUPPORTS (INNOVATIONS N015): say what touches the floor ("kneeling on the right knee, left
## foot flat", "left hand on the floor, both feet", "on both knees", "sitting on the floor", "lunge, back knee 5 cm off the
## floor", "push-up plank") and Kine solves a pose that rests on exactly those contacts, balanced over them, and says how
## the weight is shared. I5 (say_it.gd) and the pose words (pose_words.gd) turn joints; neither knows the floor except
## through the feet. Reached from the same words box: main._pose_words hands a phrase here when claims() says it is ours
## and PoseWords can't parse it, so the AI box and serve `pose {text}` take these phrases too.
##
## PARSE: clauses (split at "," ";" "with" "and"; "hands and knees" stays whole), each naming a PART (foot, toes, knee,
## hand, forearm / elbow, butt / seat, head) with a side (left, right, both, one, front / back in a lunge, a plural =
## both) and whether it is ON the floor (the default) or OFF it ("in the air", "up", "5 cm off the floor" = a height).
## A posture word brings the contacts it implies, each reported as implied: "plank" / "push-up" = both hands + both toes,
## "forearm plank" = both forearms + both toes, "hands and knees" / "all fours" = both hands + both knees, "sitting" =
## the butt + both feet flat (knees up) unless feet are named, "lunge" = the front foot flat + the back foot on its toes
## (front = left unless "right foot forward" / "right lunge"), "kneeling" alone = both knees, one knee and nothing said
## of the other leg = that foot flat (a half-kneel).
##
## WHAT TOUCHES (the app's own floors, so a pose this solves reads the same to Rise.floor_depth and Body.floor_shift):
##   a foot: its sole points over their rest heights (Body.foot_sole_low: heel = the ankle, ball, toe tip). Flat = heel and
##     ball down; on the toes = the toes' front half down (the tip and the toes' middle: on the toes the foot stands near
##     upright and the toe JOINT, whose rest height assumes a flat foot, reads ~1 cm high while the toe pads are down). The
##     foot CAPSULES sit 6.4 cm under the floor at rest (padding round the ankle, not the sole): never the foot's floor.
##   any other part: its underside, the lower of its capsule (lower end minus radius) and the app's own floor reading of
##     that joint (Body.floor_shift: the joint to its end point, minus the radius; the pelvis capsule lies ACROSS the hips,
##     so a sit read by the capsule alone was 1.4 cm into the floor by floor_shift's reading).
##   a knee: the lowest of the thigh capsule's knee end and the calf capsule's knee end (rise._kneel puts the knee one
##     thigh radius, 8.8 cm, up: that is this point on the floor). A kneeling leg's shin and toes may rest on the floor too.
##   a hand: the lowest of the hand and finger parts (palm or knuckles); the wrist end of the forearm may touch.
##   a forearm: the forearm (and its hand). The butt: the hips (hips_wide, the pelvis; the thighs may rest).
## BARS (tests/supports_test.gd): each named part within TOUCH (1 cm, = Balance.TOUCH) of the floor; every part not in a
## named contact's group at least CLEAR (2 cm) above it; nothing more than 1 cm into it (Rise.FLOOR_MM); the COM inside the
## support polygon by MARGIN (2 cm, = Balance.MARGIN_RES, the model's resolution); every joint inside its limits
## (data/body_limits.json, Body.clamp_ang); no capsule pair deeper than Feasible.PEN_FIX (2 cm, feasible.gd's own
## self-penetration bar).
##
## BALANCE OVER ANY CONTACT (Balance.read only knows feet): the support polygon is the convex hull of (a) Balance.footprint
## for every foot in a named contact (the app's own lenient foot shadow, unchanged), and (b) for the other contacts, the
## points along each group part's axis (capsule and joint, as above) whose underside is within TOUCH of the floor, with NO
## disc round them (a knee or a palm presses a patch a few cm wide; leaving it out is the strict side, so a margin read here
## is never flattering).
##
## SOLVE: a seed pose for the family the contacts make (stand, one leg, reach to the floor, half-kneel, tall kneel, hands
## and knees, sit, lunge, plank, forearm plank; the half-kneel is rise._half's shape, mirrored to the side asked), then a
## search over 24 joint angles (pelvis pitch / roll, the trunk shared by the three spine joints, neck, hips, knees, ankles,
## toes, shoulders, elbows, wrists) plus the same angles of both sides at once, each clamped to its limits: coordinate
## steps of 8, 4, 2, 1, 0.5 deg, then 400 seeded random moves of 2-3 angles together (single steps stall where angles must
## move together). A flat foot's ankle and a toes contact's toes are not searched but solved after every trial (Body.flat_foot,
## Body.toes_flat); then the body is lowered or lifted so the lowest named contact touches (y = 0), and scored: named parts
## off the floor, other parts under 3 cm, any part into the floor, the COM less than 3.5 cm inside, a height asked for
## ("5 cm off"), capsule pairs inside each other, and a small pull back to the seed (so the pose stays the family's). Aims
## are a little past the bars so the result clears them. The result is checked against the bars (Body.contacts with the
## skin points for the self-penetration); a miss is refused with the numbers and the body is left as it was. Then the pose
## is turned to the heading the body had and put where its pelvis stood. The floor is y = 0; props are ignored (stated).
## A solve takes 1-5 s headless (tests/supports_test.gd prints each).
##
## WEIGHT SHARE (HEURISTIC: an estimate, not a force plate): only vertical forces, the body still, each contact's load at
## the centre of its floor points. The shares w_i >= 0 must sum to 1 and put their centre at the COM's floor point
## (sum w_i c_i = com): with 3+ contacts that has many answers (statically indeterminate), so the most even one is taken
## (least sum of w_i^2: a minimum-norm split, an active set dropping a contact that would pull). A real body shifts load by
## effort, so these are a plausible static split, not what a force plate would read.
## solve(B, text) -> {"ok": true, "supports": [{"part", "said", "implied", "gap_cm", "share_pct"}], "margin_cm", ...}
##                or {"ok": false, "error": "... why, with the numbers, and what to say instead"}
class_name SupportPose
extends RefCounted

const TOUCH := 0.01        # m: a named part this close to the floor touches it (= Balance.TOUCH)
const CLEAR := 0.02        # m: every other part at least this far above it (the test's bar)
const MARGIN := 0.02       # m: the COM this far inside the support polygon (= Balance.MARGIN_RES)
const FLOOR_IN := 0.01     # m: no part deeper than this into the floor (Rise.FLOOR_MM, the roadmap's 1 cm)
const AIM_CLEAR := 0.03    # m: what the search aims for (past the bar, so the bar holds after the last step)
const AIM_MARGIN := 0.035
const HEIGHT_TOL := 0.01   # m: a height asked for ("5 cm off the floor") is met within this
const STEPS := [8.0, 4.0, 2.0, 1.0, 0.5]
const PASSES := 6
const RANDOM_STEPS := [4.0, 2.0, 1.0, 0.5]   # deg: the random stage's step per angle
const RANDOM_TRIES := 100
const SPINE := ["spine_01", "spine_02", "spine_03"]
const SIDES := ["_l", "_r"]
const NICE := {"foot": "foot flat", "toes": "toes", "knee": "knee", "hand": "hand", "forearm": "forearm", "butt": "butt", "head": "head"}
const WEIGHT_METHOD := "HEURISTIC: static, vertical loads only; each contact's load at the centre of its floor points; the most even split (least sum of squares) whose centre is the COM's floor point"

## words -> the part they name
const PART_WORDS := {"foot": "foot", "feet": "foot", "sole": "foot", "soles": "foot", "toe": "toes", "toes": "toes",
	"tiptoe": "toes", "tiptoes": "toes", "knee": "knee", "knees": "knee", "hand": "hand", "hands": "hand", "palm": "hand",
	"palms": "hand", "fist": "hand", "fists": "hand", "knuckles": "hand", "forearm": "forearm", "forearms": "forearm",
	"elbow": "forearm", "elbows": "forearm", "butt": "butt", "bottom": "butt", "bum": "butt", "buttocks": "butt",
	"backside": "butt", "seat": "butt", "head": "head"}
const PLURAL := ["feet", "soles", "toes", "tiptoes", "knees", "hands", "palms", "fists", "knuckles", "forearms", "elbows"]
const SIDE_WORDS := {"left": "_l", "right": "_r", "both": "both", "one": "one", "back": "back", "rear": "back",
	"trailing": "back", "trail": "back", "front": "front", "lead": "front", "leading": "front"}
const OFF_WORDS := ["air", "up", "raised", "lifted", "off", "above", "free", "high"]
const FILLER := ["the", "a", "an", "his", "her", "its", "their", "on", "of", "floor", "ground", "is", "are", "in", "at",
	"to", "touching", "touch", "touches", "resting", "rests", "rest", "under", "him", "body", "only", "just", "position",
	"pose", "weight", "flat", "planted", "down", "cm", "centimetres", "centimeters", "centimetre", "centimeter", "while",
	"he", "she", "it", "its", "stays", "kept", "keep", "keeps", "other", "mat", "forward", "forwards", "ahead", "behind",
	"tucked", "under", "solid", "firmly", "firm", "position", "by", "from", "over", "out", "straight"]
## posture words -> the family cue they give
const POSTURE := {"kneeling": "kneel", "kneel": "kneel", "kneels": "kneel", "knelt": "kneel", "sitting": "sit",
	"sit": "sit", "sits": "sit", "seated": "sit", "lunge": "lunge", "lunging": "lunge", "plank": "plank",
	"pushup": "plank", "allfours": "allfours", "crawl": "allfours", "crawling": "allfours", "standing": "stand",
	"stand": "stand", "stands": "stand", "squat": "squat", "squatting": "squat", "crouch": "squat",
	"crouching": "squat", "headstand": "headstand", "balancing": "stand", "balance": "stand"}


## does this text read as a supports phrase? (the words box asks on every keystroke: words only, no solve). A posture
## word (kneeling, sitting, lunge, plank, standing, squat...) is enough; a weaker cue ("on the floor", "on both knees",
## "left foot flat") counts only when every word parses, so "put the right hand on the left knee" stays the pose words'
static func claims(text: String) -> bool:
	var t := _norm(text)
	for w in t.replace(",", " ").split(" ", false):
		if POSTURE.has(w):
			return true
	var weak := false
	for c in ["on the floor", "on the ground", "off the floor", "foot flat", "feet flat", "both feet", "allfours"]:
		weak = weak or t.contains(c)
	var rx := RegEx.create_from_string("\\bon (the |his |her |both |one |)(left |right |)(knee|knees|toes|tiptoes|hands|feet|foot|butt|bottom|head|elbows|forearms)\\b")
	weak = weak or rx.search(t) != null
	return weak and parse(text)["ok"]


static func _norm(text: String) -> String:
	var t := " " + text.to_lower().strip_edges() + " "
	for p in [".", "!", "?", "(", ")", "\"", "'s "]:
		t = t.replace(p, " ")
	t = t.replace(";", ",").replace("push-up", "pushup").replace("push up", "pushup").replace("press-up", "pushup")
	t = t.replace("tip-toes", "tiptoes").replace("tip toes", "tiptoes").replace("all-fours", "allfours").replace("all fours", "allfours")
	t = t.replace("hands and knees", "allfours").replace("head-stand", "headstand").replace("-", " ")
	t = t.replace(" with ", ",").replace(" and ", ",").replace(" plus ", ",")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.strip_edges()


## text -> {"ok", "contacts": [{"part", "side", "implied", "said"}], "off": [{"part", "side", "h"}], "family", "front", "notes"}
static func parse(text: String) -> Dictionary:
	var t := _norm(text)
	var cues := {}
	var on := []    # [{"part", "side", "said", "toes"}]
	var off := []   # [{"part", "side", "h", "said"}]
	var front := "_l"
	var notes := []
	for clause in t.split(",", false):
		var c := clause.strip_edges()
		var ws := c.split(" ", false)
		var side := ""
		var parts := []   # [part, side, plural]
		var is_off := false
		var h := NAN
		var toes_kind := false
		for i in ws.size():
			var w: String = ws[i]
			if w.ends_with("cm") and w.trim_suffix("cm").is_valid_float():
				h = float(w.trim_suffix("cm")) / 100.0
				continue
			if w.is_valid_float():
				var unit := ws[i + 1] if i + 1 < ws.size() else "cm"
				h = float(w) / (1.0 if unit in ["m", "metre", "meter", "metres", "meters"] else 100.0)
				continue
			if w in ["m", "metre", "meter", "metres", "meters"]:
				continue
			if POSTURE.has(w):
				cues[POSTURE[w]] = true
				continue
			if SIDE_WORDS.has(w):
				side = SIDE_WORDS[w]
				continue
			if w in OFF_WORDS:
				is_off = true
				continue
			if PART_WORDS.has(w):
				var p: String = PART_WORDS[w]
				if p == "toes" and not parts.is_empty() and parts[-1][0] == "foot":
					toes_kind = true   # "left foot on its toes": the foot, on its toes
					continue
				parts.append([p, side, w in PLURAL])
				side = ""   # a side word belongs to the part after it
				continue
			if w in FILLER:
				continue
			return {"ok": false, "error": "'%s' is not a word I know for what touches the floor. Say the parts on it: %s; e.g. %s" % [w, ", ".join(PART_WORDS.keys()), _examples()]}
		if side != "" and not parts.is_empty() and parts[-1][1] == "":
			parts[-1][1] = side   # "knee right" / "the foot, left" (a side after its part)
		for pr in parts:
			var p: String = pr[0]
			if toes_kind and p == "foot":
				p = "toes"
			var sd: String = pr[1]
			if sd == "" and pr[2]:
				sd = "both"   # "hands", "knees": both
			var e := {"part": p, "side": sd, "said": c}
			if is_off:
				e["h"] = h
				off.append(e)
			else:
				on.append(e)
	if t.contains("right foot forward") or t.contains("right lunge") or t.contains("right leg forward"):
		front = "_r"
	if t.contains("left foot forward") or t.contains("left lunge") or t.contains("left leg forward"):
		front = "_l"
	# the posture words bring their contacts (reported as implied)
	var implied := []
	var named := func(p: String) -> bool:
		return on.any(func(e): return e["part"] == p) or off.any(func(e): return e["part"] == p)
	if cues.has("headstand"):
		on.append({"part": "head", "side": "", "said": "headstand"})
	if cues.has("plank"):
		var arm := "forearm" if named.call("forearm") else "hand"
		if not named.call(arm):
			implied.append({"part": arm, "side": "both", "said": "a plank rests on both %ss" % arm})
		if not named.call("toes") and not named.call("foot"):
			implied.append({"part": "toes", "side": "both", "said": "a plank rests on both feet's toes"})
	if cues.has("allfours"):
		if not named.call("hand"):
			implied.append({"part": "hand", "side": "both", "said": "hands and knees"})
		if not named.call("knee"):
			implied.append({"part": "knee", "side": "both", "said": "hands and knees"})
	if cues.has("sit") and not named.call("butt"):
		implied.append({"part": "butt", "side": "", "said": "sitting rests on the butt"})
	if cues.has("sit") and not named.call("foot") and not named.call("toes"):
		implied.append({"part": "foot", "side": "both", "said": "sitting on the floor: knees up, both feet flat"})
	if cues.has("lunge"):
		if not on.any(func(e): return e["part"] in ["foot", "toes"] and e["side"] == "front"):
			implied.append({"part": "foot", "side": "front", "said": "a lunge's front foot is flat"})
		if not on.any(func(e): return e["part"] in ["foot", "toes", "knee"] and e["side"] == "back"):
			implied.append({"part": "toes", "side": "back", "said": "a lunge's back foot is on its toes"})
	if cues.has("kneel") and not named.call("knee"):
		implied.append({"part": "knee", "side": "both", "said": "kneeling: both knees"})
	if cues.has("squat") and not named.call("foot") and not named.call("toes"):
		implied.append({"part": "foot", "side": "both", "said": "squatting on both feet flat"})
	if (cues.has("stand") or cues.has("squat")) and on.is_empty() and implied.is_empty() and not named.call("head"):
		implied.append({"part": "foot", "side": "both", "said": "standing on both feet"})
	# sides: front / back belong to a lunge, one = the right (said so), "both" = two entries
	var out_on := []
	var out_off := []
	for src in [[on, out_on, false], [implied, out_on, true], [off, out_off, false]]:
		for e in src[0]:
			var sd: String = e["side"]
			if sd in ["front", "back"]:
				if not cues.has("lunge"):
					return {"ok": false, "error": "'%s %s' needs a lunge (front / back are a lunge's legs): say 'left %s' or 'right %s'" % [sd, e["part"], e["part"], e["part"]]}
				sd = front if sd == "front" else ("_r" if front == "_l" else "_l")
			if sd == "one":
				sd = "_r"
				notes.append("'one %s' = the right %s" % [e["part"], e["part"]])
			var sides: Array = [""] if e["part"] in ["butt", "head"] else (SIDES if sd == "both" else [sd])
			for s2 in sides:
				if s2 == "" and not e["part"] in ["butt", "head"]:
					return {"ok": false, "error": "which %s: say 'left %s', 'right %s' or 'both %ss'" % [e["part"], e["part"], e["part"], e["part"]]}
				var x := {"part": e["part"], "side": s2, "implied": src[2], "said": e["said"]}
				if e.has("h"):
					x["h"] = e["h"]
				(src[1] as Array).append(x)
	# one kneeling knee and nothing said of the other leg: its foot flat (a half-kneel)
	var knees := out_on.filter(func(e): return e["part"] == "knee")
	if knees.size() == 1:
		var other := "_l" if knees[0]["side"] == "_r" else "_r"
		if not out_on.any(func(e): return e["side"] == other and e["part"] in ["foot", "toes", "knee"]) and not out_off.any(func(e): return e["side"] == other and e["part"] in ["foot", "toes", "knee"]):
			out_on.append({"part": "foot", "side": other, "implied": true, "said": "kneeling on one knee: the other foot flat"})
	# a part both on and off the floor; the same part twice
	var seen := {}
	var dedup := []
	for e in out_on:
		var k: String = e["part"] + e["side"]
		for o in out_off:
			if o["part"] + o["side"] == k:
				return {"ok": false, "error": "the %s%s can't be on the floor and off it: say one" % [_side_word(e["side"]), e["part"]]}
		if seen.has(k):
			continue
		if e["part"] == "foot" and seen.has("toes" + e["side"]) or e["part"] == "toes" and seen.has("foot" + e["side"]):
			return {"ok": false, "error": "the %sfoot can't be flat and on its toes at once: say one" % _side_word(e["side"])}
		seen[k] = true
		dedup.append(e)
	return {"ok": true, "contacts": dedup, "off": out_off, "cues": cues.keys(), "front": front, "notes": notes}


static func _side_word(sd: String) -> String:
	return "left " if sd == "_l" else "right " if sd == "_r" else ""


static func _examples() -> String:
	return "'kneeling on the right knee, left foot flat', 'left hand on the floor, both feet', 'on both knees', 'sitting on the floor', 'lunge, back knee 5 cm off the floor', 'push-up plank'"


## the contacts -> the family whose seed starts the search ("" = none: refused with why)
static func family(spec: Dictionary) -> String:
	var cs: Array = spec["contacts"]
	var has := func(p: String) -> int:
		return cs.filter(func(e): return e["part"] == p).size()
	var cues: Array = spec["cues"]
	if has.call("head") > 0:
		return "head"
	if has.call("butt") > 0:
		return "sit"
	if has.call("forearm") > 0 and has.call("toes") + has.call("foot") > 0 and has.call("knee") == 0:
		return "forearm_plank"
	if has.call("hand") > 0 and has.call("toes") > 0 and has.call("knee") == 0 and ("plank" in cues or has.call("hand") == 2 and has.call("toes") == 2 and has.call("foot") == 0):
		return "plank"
	if has.call("knee") == 2:
		return "allfours" if has.call("hand") > 0 or has.call("forearm") > 0 else "tallkneel"
	if has.call("knee") == 1:
		return "halfkneel"
	if "lunge" in cues:
		return "lunge"
	var legs: int = has.call("foot") + has.call("toes")
	if legs > 0 and has.call("hand") + has.call("forearm") > 0:
		return "reach"
	if legs == 2:
		return "squat" if "squat" in cues else "stand"
	if legs == 1:
		return "onefoot"
	return ""


# ---------------------------------------------------------------- measures

## every capsule now, once per trial: part -> [end a, end b, radius, middle, half length, underside] (the weapons left out).
## The underside is the lower of two readings: the capsule's (its lower end minus its radius) and the app's own floor
## reading of a joint's part (Body.floor_shift / ground_body: the joint to its end point, minus the radius). They differ
## where the capsule is not along the bone (the pelvis capsule lies across the hips): a sit measured by the capsule alone
## had the pelvis 1.4 cm into the floor by Body.floor_shift's reading, so the snap-to-floor would have lifted it
static func _caps(B: Body) -> Dictionary:
	var out := {}
	for p in B.rad:
		if Body.is_wep(p):
			continue
		var c: Array = B.cap(p)
		var a: Vector3 = c[0]
		var b: Vector3 = c[1]
		var r := float(B.rad[p])
		var low := minf(a.y, b.y) - r
		var seg := []
		if B.P.has(p) and B.E.has(p):
			low = minf(low, minf((B.P[p] as Vector3).y, (B.E[p] as Vector3).y) - r)
			seg = [B.P[p], B.E[p]]
		out[p] = [a, b, r, (a + b) * 0.5, a.distance_to(b) * 0.5, low, seg]
	return out


## a part's underside height (m, see _caps)
static func _bot(cp: Dictionary, part: String) -> float:
	return float(cp[part][5])


## a foot's sole points over their rest heights (Body.foot_sole_low's three): [heel, ball, toe tip]
static func _soles(B: Body, sd: String) -> Array:
	return [(B.P["foot" + sd] as Vector3).y - (B.p0["foot" + sd] as Vector3).y,
		(B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y,
		(B.E["ball" + sd] as Vector3).y - (B.e0["ball" + sd] as Vector3).y]


static func _knee(cp: Dictionary, sd: String) -> float:
	var t: Array = cp["thigh" + sd]
	var c: Array = cp["calf" + sd]
	return minf((t[1] as Vector3).y - float(t[2]), (c[0] as Vector3).y - float(c[2]))


static func _hand_parts(sd: String) -> Array:
	var out := ["hand" + sd]
	for f in Body.FINGERS:
		if (f as String).ends_with(sd):
			out.append(f)
	return out


static func _low(cp: Dictionary, parts: Array) -> float:
	var m := INF
	for p in parts:
		m = minf(m, _bot(cp, p))
	return m


## one contact's [lowest point, the points that must touch] (m over the floor)
static func _contact_pts(B: Body, cp: Dictionary, e: Dictionary) -> Array:
	var sd: String = e["side"]
	match String(e["part"]):
		"foot":
			var s := _soles(B, sd)
			return [minf(s[0], s[1]), [s[0], s[1]]]
		"toes":
			var s2 := _soles(B, sd)
			# the toes' front half down: the tip and the middle of the toes (on the toes the foot stands near upright, so the toe
			# JOINT, whose rest height assumes a flat foot, sits ~1 cm over it while the toe pads are on the floor)
			return [minf(s2[1], s2[2]), [s2[2], (s2[1] + s2[2]) * 0.5]]
		"knee":
			var k := _knee(cp, sd)
			return [k, [k]]
		"hand":
			var lh := _low(cp, _hand_parts(sd))
			return [lh, [lh]]
		"forearm":
			var lf := _bot(cp, "lowerarm" + sd)
			return [lf, [lf]]
		"butt":
			var lb := minf(_bot(cp, "hips_wide"), _bot(cp, "pelvis"))
			return [lb, [lb]]
		"head":
			var hd := _bot(cp, "head")
			return [hd, [hd]]
	return [INF, []]


## the capsules a contact's group may rest on the floor with (exempt from the 2 cm bar); "sole_l" = that foot's soles
static func _group(e: Dictionary) -> Array:
	var sd: String = e["side"]
	match String(e["part"]):
		"foot", "toes":
			return ["sole" + sd]
		"knee":
			return ["thigh" + sd, "calf" + sd, "sole" + sd]
		"hand", "forearm":
			var g := _hand_parts(sd)
			g.append("lowerarm" + sd)
			return g
		"butt":
			return ["pelvis", "hips_wide", "thigh_l", "thigh_r"]
		"head":
			return ["head", "neck_01"]
	return []


static func _exempt(spec: Dictionary) -> Dictionary:
	var ex := {}
	for e in spec["contacts"]:
		for g in _group(e):
			ex[g] = true
	return ex


## every part the floor bars look at: [name, clearance (m)]; the feet by their sole points, the rest by their capsules
static func _parts(B: Body, cp: Dictionary) -> Array:
	var out := []
	for p in cp:
		var n: String = p
		if n.begins_with("foot") or n.begins_with("ball"):
			continue
		out.append([n, _bot(cp, n)])
	for sd in SIDES:
		var s := _soles(B, sd)
		out.append(["sole" + sd, minf(s[0], minf(s[1], s[2]))])
	return out


## a foot's floor points: Balance.footprint (exact = true), or the same hull from only the first and last touching
## sample of each capsule (the touching samples along a straight axis are one run, so their discs' hull is the end discs')
static func _foot_pts(B: Body, sd: String, exact: bool) -> PackedVector2Array:
	if exact:
		return Balance.footprint(B, sd)
	var out := PackedVector2Array()
	for part in Balance.FEET[sd]:
		var c: Array = B.cap(part)
		var r: float = B.rad[part]
		var first := -1
		var last := -1
		for k in 9:
			var p: Vector3 = (c[0] as Vector3).lerp(c[1], k / 8.0)
			if p.y - r <= Balance.TOUCH:
				if first < 0:
					first = k
				last = k
		if first < 0:
			continue
		for k in ([first] if first == last else [first, last]):
			var p2: Vector3 = (c[0] as Vector3).lerp(c[1], k / 8.0)
			for a in Balance.RING:
				var th := TAU * a / Balance.RING
				out.append(Vector2(p2.x + r * cos(th), p2.z + r * sin(th)))
	return out


## the floor points a contact carries weight on (x, z): see BALANCE OVER ANY CONTACT in the header
static func _floor_pts(B: Body, cp: Dictionary, e: Dictionary, exact: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for g in _group(e):
		var n: String = g
		if n.begins_with("sole"):
			out.append_array(_foot_pts(B, n.right(2), exact))
			continue
		var c: Array = cp[n]
		var r: float = c[2]
		for ends in ([[c[0], c[1]]] + ([c[6]] if not (c[6] as Array).is_empty() else [])):   # the capsule, and the joint's part (see _caps)
			for k in 9:
				var q: Vector3 = (ends[0] as Vector3).lerp(ends[1], k / 8.0)
				if q.y - r < TOUCH:
					out.append(Vector2(q.x, q.z))
	return out


## everything the bars read, in one pass: {"gaps": [m per contact], "free_low": [name, m], "deep": m into the floor,
## "margin": m, "heights": [[e, m]], "pen": [deepest pair m, "a/b"] (full only: Body.contacts, the skin points too)}
static func measure(B: Body, spec: Dictionary, full := true) -> Dictionary:
	var cp := _caps(B)
	var exempt := _exempt(spec)
	var gaps := []
	var pts := PackedVector2Array()
	var per := []
	for e in spec["contacts"]:
		var cpt := _contact_pts(B, cp, e)
		var gap := 0.0
		for v in cpt[1]:
			gap = maxf(gap, absf(float(v)))
		gaps.append(gap)
		var fp := _floor_pts(B, cp, e, full)
		per.append(fp)
		pts.append_array(fp)
	var free_low := ["", INF]
	var deep := 0.0
	var deep_at := ""
	var parts := _parts(B, cp)
	for pc in parts:
		var v: float = pc[1]
		if -v > deep:
			deep = -v
			deep_at = pc[0]
		if not exempt.has(pc[0]) and v < float(free_low[1]):
			free_low = [pc[0], v]
	var heights := []
	for o in spec["off"]:
		heights.append([o, float(_contact_pts(B, cp, o)[0])])
	var c := Balance.com(B)
	var poly := Balance.hull(pts)
	var margin := Balance.signed_dist(poly, Vector2(c.x, c.z)) if pts.size() > 0 else -INF
	var out := {"gaps": gaps, "free_low": free_low, "deep": deep, "deep_at": deep_at, "margin": margin, "heights": heights,
		"com": c, "per": per, "poly": poly, "parts": parts, "exempt": exempt}
	if full:
		var pd := 0.0
		var pp := ""
		for ct in B.contacts():
			if float(ct[2]) > pd:
				pd = float(ct[2])
				pp = "%s/%s" % [ct[0], ct[1]]
		out["pen"] = [pd, pp]
	else:
		out["pen_sum"] = _pairs_pen(cp, spec["_pairs"])
	return out


# ---------------------------------------------------------------- the search

## the joint angles searched: [joint, axis]; "trunk" = the three spine joints' bend shared equally
const DOFS := [["pelvis", 0], ["pelvis", 1], ["trunk", 0], ["neck_01", 0],
	["thigh_l", 0], ["thigh_l", 1], ["thigh_r", 0], ["thigh_r", 1], ["calf_l", 0], ["calf_r", 0],
	["foot_l", 0], ["foot_r", 0], ["ball_l", 0], ["ball_r", 0],
	["upperarm_l", 0], ["upperarm_l", 1], ["upperarm_l", 2], ["lowerarm_l", 0], ["hand_l", 0],
	["upperarm_r", 0], ["upperarm_r", 1], ["upperarm_r", 2], ["lowerarm_r", 0], ["hand_r", 0]]
## both sides at once: a symmetric pose (a plank, a sit) whose two contacts must move together, which one side's step can't do
const SYM := [["both", "thigh", 0], ["both", "calf", 0], ["both", "foot", 0], ["both", "ball", 0], ["both", "upperarm", 0],
	["both", "lowerarm", 0], ["both", "hand", 0]]


static func _dof_get(B: Body, d: Array) -> float:
	if d.size() > 2:   # ["both", stem, axis]: the left one stands for the pair
		return (B.ang[d[1] + "_l"] as Vector3)[d[2]]
	if d[0] == "trunk":
		var s := 0.0
		for j in SPINE:
			s += (B.ang[j] as Vector3).x
		return s
	return (B.ang[d[0]] as Vector3)[d[1]]


static func _dof_set(B: Body, d: Array, v: float) -> void:
	if d.size() > 2:   # both sides by the same change (a twist or side turn mirrored: the pair stays symmetric if it was)
		var dl: float = v - (B.ang[d[1] + "_l"] as Vector3)[d[2]]
		for sd in SIDES:
			var w: Vector3 = B.ang[d[1] + sd]
			w[d[2]] += dl
			B.ang[d[1] + sd] = B.clamp_ang(d[1] + sd, w)
		return
	if d[0] == "trunk":
		for j in SPINE:
			var a: Vector3 = B.ang[j]
			a.x = v / 3.0
			B.ang[j] = B.clamp_ang(j, a)
		return
	var b: Vector3 = B.ang[d[0]]
	b[d[1]] = v
	B.ang[d[0]] = B.clamp_ang(d[0], b)


## lower / lift the body so its lowest named contact touches the floor
static func _ground(B: Body, spec: Dictionary) -> void:
	B.fk()
	for e in spec["contacts"]:   # a flat foot's ankle and a toes contact's toe joint are solved, not searched (Body's own)
		if e["part"] == "foot":
			B.flat_foot(e["side"])
		elif e["part"] == "toes":
			B.toes_flat(e["side"])
	var cp := _caps(B)
	var low := INF
	for e in spec["contacts"]:
		low = minf(low, float(_contact_pts(B, cp, e)[0]))
	if low < INF:
		B.offset.y -= low
		B.fk()


## the pairs the search checks: Body.pairs without the weapons, with each pair's allowance (how deep it sits at rest)
static func _pair_list(B: Body) -> Array:
	var out := []
	for pr in B.pairs:
		if Body.is_wep(pr[0]) or Body.is_wep(pr[1]):
			continue
		out.append([pr[0], pr[1], float(B.allow.get(pr[0] + "|" + pr[1], 0.0))])
	return out


## the capsule pairs' depth past their allowance (Body.contacts without the skin points: the search's cheap version), cm
## summed over the pairs deeper than 3 mm; far pairs are skipped by their bounding spheres
static func _pairs_pen(cp: Dictionary, pl: Array) -> float:
	var t := 0.0
	for pr in pl:
		var x: Array = cp[pr[0]]
		var y: Array = cp[pr[1]]
		var rr: float = float(x[2]) + float(y[2])
		if (x[3] as Vector3).distance_to(y[3]) > float(x[4]) + float(y[4]) + rr:
			continue
		var d: float = rr - Body.seg_seg(x[0], x[1], y[0], y[1]) - float(pr[2])
		if d > 0.003:
			t += (d - 0.003) * 100.0
	return t


static func _cost(B: Body, spec: Dictionary, seed: Dictionary) -> float:
	_ground(B, spec)
	var m := measure(B, spec, false)
	var c := 0.0
	for g in m["gaps"]:
		c += 10.0 * pow(float(g) * 100.0, 2)
	var exempt: Dictionary = m["exempt"]
	for pc in m["parts"]:
		var v: float = float(pc[1]) * 100.0
		if exempt.has(pc[0]):
			if v < -0.3:
				c += 10.0 * pow(-0.3 - v, 2)
		elif v < AIM_CLEAR * 100.0:
			c += 5.0 * pow(AIM_CLEAR * 100.0 - v, 2)
	var mg: float = maxf(float(m["margin"]), -0.5) * 100.0
	if mg < AIM_MARGIN * 100.0:
		c += 5.0 * pow(AIM_MARGIN * 100.0 - mg, 2)
	for h in m["heights"]:
		var want: float = h[0].get("h", NAN)
		var got: float = float(h[1]) * 100.0
		if is_nan(want):
			if got < AIM_CLEAR * 100.0:
				c += 5.0 * pow(AIM_CLEAR * 100.0 - got, 2)
		else:
			c += 10.0 * pow(got - want * 100.0, 2)
	var pen: float = m["pen_sum"]
	c += 5.0 * pen * pen
	for j in seed:
		var dv: Vector3 = (B.ang[j] as Vector3) - (seed[j] as Vector3)
		c += 0.0005 * dv.length_squared()
	return c


## the angles this search moves: DOFS + SYM, less the ones _ground solves (a flat foot's ankle, a toes contact's toes)
static func _dofs(spec: Dictionary) -> Array:
	var auto := {}
	for e in spec["contacts"]:
		if e["part"] == "foot":
			auto["foot" + e["side"]] = true
		elif e["part"] == "toes":
			auto["ball" + e["side"]] = true
	var out := []
	for d in DOFS:
		if not auto.has(d[0]):
			out.append(d)
	for d in SYM:
		if not auto.has(d[1] + "_l") and not auto.has(d[1] + "_r"):
			out.append(d)
	return out


static func _search(B: Body, spec: Dictionary, seed: Dictionary) -> float:
	var dofs := _dofs(spec)
	var best := _cost(B, spec, seed)
	for st in STEPS:
		for pass_i in PASSES:
			var better := false
			for d in dofs:
				var old := _dof_get(B, d)
				for sg in [1.0, -1.0]:
					_dof_set(B, d, old + sg * st)
					if is_equal_approx(_dof_get(B, d), old):
						continue
					var c := _cost(B, spec, seed)
					if c < best - 1e-6:
						best = c
						better = true
						old = _dof_get(B, d)
						break
					_dof_set(B, d, old)
			if not better:
				break
	# then moves of two or three angles at once, chosen at random (seeded: the same words give the same pose). Single
	# steps stall where angles must move together (a sit's thighs can drop only if the knees and the pelvis follow)
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	for st in RANDOM_STEPS:
		for it in RANDOM_TRIES:
			var pick := []
			for k in rng.randi_range(2, 3):
				pick.append(dofs[rng.randi_range(0, dofs.size() - 1)])
			var keep := B.ang.duplicate()
			for d in pick:
				_dof_set(B, d, _dof_get(B, d) + (st if rng.randf() < 0.5 else -st))
			var c := _cost(B, spec, seed)
			if c < best - 1e-6:
				best = c
				continue
			B.ang = keep
	B.fk()
	_cost(B, spec, seed)
	return best


# ---------------------------------------------------------------- seeds (canonical: facing +z, pelvis over x = z = 0)

static func _seed(B: Body, fam: String, spec: Dictionary) -> void:
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	var a := func(j: String, v: Vector3) -> void:
		B.ang[j] = B.clamp_ang(j, v)
	var cs: Array = spec["contacts"]
	var on := func(p: String, sd: String) -> bool:
		return cs.any(func(e): return e["part"] == p and e["side"] == sd)
	match fam:
		"onefoot":
			var up := "_l" if on.call("foot", "_r") or on.call("toes", "_r") else "_r"
			a.call("thigh" + up, Vector3(40, 0, 0))
			a.call("calf" + up, Vector3(70, 0, 0))
		"squat":
			for sd in SIDES:
				a.call("thigh" + sd, Vector3(95, 10, 0))
				a.call("calf" + sd, Vector3(115, 0, 0))
				a.call("foot" + sd, Vector3(22, 0, 0))
			for j in SPINE:
				a.call(j, Vector3(12, 0, 0))
		"reach":   # bent over from the hips, knees bent: the trunk pitched past the thighs, not folded into them
			a.call("pelvis", Vector3(60, 0, 0))
			for sd in SIDES:
				a.call("thigh" + sd, Vector3(80, 5, 0))
				a.call("calf" + sd, Vector3(60, 0, 0))
				a.call("foot" + sd, Vector3(20, 0, 0))
				if on.call("hand", sd) or on.call("forearm", sd):
					a.call("upperarm" + sd, Vector3(70, -15, 0))
					a.call("lowerarm" + sd, Vector3(5, 0, 0))
			for j in SPINE:
				a.call(j, Vector3(10, 0, 0))
		"halfkneel", "lunge":
			var kn := "_r"
			for e in cs:
				if e["part"] == "knee" or e["part"] == "toes":
					kn = e["side"]
			if fam == "lunge":
				kn = "_r" if spec["front"] == "_l" else "_l"
			var fr := "_l" if kn == "_r" else "_r"
			a.call("thigh" + kn, Vector3(-15, 0, 0))
			a.call("calf" + kn, Vector3(80, 0, 0))
			a.call("ball" + kn, Vector3(40, 0, 0))
			a.call("thigh" + fr, Vector3(92, 0, 0))
			a.call("calf" + fr, Vector3(88, 0, 0))
		"tallkneel", "allfours":
			for sd in SIDES:
				a.call("thigh" + sd, Vector3(0 if fam == "tallkneel" else 90, 5, 0))
				a.call("calf" + sd, Vector3(100 if fam == "tallkneel" else 90, 0, 0))
				a.call("foot" + sd, Vector3(-20, 0, 0))
				a.call("ball" + sd, Vector3(50, 0, 0))
			if fam == "allfours":
				a.call("pelvis", Vector3(90, 0, 0))
				for sd in SIDES:
					a.call("upperarm" + sd, Vector3(90, -10, 0))
					a.call("lowerarm" + sd, Vector3(0, 0, 0))
					a.call("hand" + sd, Vector3(-40, 0, 0))
		"sit":   # knees up. Feet flat need the thigh 46+ deg over level (the ankle points 45 at most), and a hip flexed past
			# ~100 sinks the thigh into the belly: so the pelvis tips back 40 and the spine (60 at most) brings the chest up
			a.call("pelvis", Vector3(-40, 0, 0))
			for sd in SIDES:
				a.call("thigh" + sd, Vector3(100, 20, 0))   # knees a little apart
				a.call("calf" + sd, Vector3(98, 0, 0))
				a.call("upperarm" + sd, Vector3(60, -10, 0))
				a.call("lowerarm" + sd, Vector3(30, 0, 0))
			for j in SPINE:
				a.call(j, Vector3(20, 0, 0))
		"plank", "forearm_plank":
			a.call("pelvis", Vector3(78 if fam == "plank" else 85, 0, 0))
			for sd in SIDES:
				a.call("thigh" + sd, Vector3(0, 3, 0))
				a.call("calf" + sd, Vector3(0, 0, 0))
				a.call("foot" + sd, Vector3(0, 0, 0))
				a.call("ball" + sd, Vector3(50, 0, 0))
				a.call("upperarm" + sd, Vector3(80, -15, 0))
				a.call("lowerarm" + sd, Vector3(0 if fam == "plank" else 90, 0, 0))
				a.call("hand" + sd, Vector3(-40, 0, 0))
			a.call("neck_01", Vector3(-20, 0, 0))
	for sd in SIDES:   # a hand on the floor: the fingers nearly straight, a little spread (rise._kneel's flat hand)
		if on.call("hand", sd):
			B.hand_curl(sd.right(1), 0.05, 0.2)
	B.offset = Vector3.ZERO
	var p: Vector3 = B.p0["pelvis"]
	B.offset = Vector3(-p.x, 0.0, -p.z)
	B.fk()


# ---------------------------------------------------------------- weight shares

## the most even non-negative split whose centre is q (see WEIGHT SHARE in the header). cs = each contact's centre;
## a contact with no floor points gets 0. Returns the shares (sum 1).
static func shares(cs: Array, q: Vector2) -> Array:
	var act := []
	for i in cs.size():
		if cs[i] != null:
			act.append(i)
	var w := []
	w.resize(cs.size())
	w.fill(0.0)
	while not act.is_empty():
		var n := act.size()
		# least squares with the centre and the sum as heavy rows: (K A^T A + I) w = K A^T b, A = [x; z; 1], b = [qx; qz; 1]
		var K := 1e6
		var M := []
		var r := []
		for i in n:
			var ci: Vector2 = cs[act[i]]
			var row := []
			for j in n:
				var cj: Vector2 = cs[act[j]]
				row.append(K * (ci.x * cj.x + ci.y * cj.y + 1.0) + (1.0 if i == j else 0.0))
			M.append(row)
			r.append(K * (ci.x * q.x + ci.y * q.y + 1.0))
		var x := _gauss(M, r)
		var worst := -1
		for i in n:
			if float(x[i]) < -1e-9 and (worst < 0 or float(x[i]) < float(x[worst])):
				worst = i
		if worst >= 0:
			act.remove_at(worst)   # it would have to pull: it carries nothing
			continue
		var s := 0.0
		for i in n:
			s += maxf(float(x[i]), 0.0)
		for i in n:
			w[act[i]] = maxf(float(x[i]), 0.0) / s if s > 0.0 else 1.0 / n
		break
	return w


static func _gauss(M: Array, r: Array) -> Array:
	var n := r.size()
	var a := []
	for i in n:
		var row: Array = (M[i] as Array).duplicate()
		row.append(r[i])
		a.append(row)
	for c in n:
		var piv := c
		for i in range(c + 1, n):
			if absf(a[i][c]) > absf(a[piv][c]):
				piv = i
		var tmp = a[c]
		a[c] = a[piv]
		a[piv] = tmp
		if absf(a[c][c]) < 1e-12:
			continue
		for i in range(c + 1, n):
			var f: float = a[i][c] / a[c][c]
			for k in range(c, n + 1):
				a[i][k] -= f * a[c][k]
	var x := []
	x.resize(n)
	x.fill(0.0)
	for i in range(n - 1, -1, -1):
		var s: float = a[i][n]
		for k in range(i + 1, n):
			s -= a[i][k] * x[k]
		x[i] = s / a[i][i] if absf(a[i][i]) > 1e-12 else 0.0
	return x


# ---------------------------------------------------------------- solve

static func _label(e: Dictionary) -> String:
	var p: String = e["part"]
	if p == "butt" or p == "head":
		return p
	return "%s%s" % [_side_word(e["side"]), "foot (flat)" if p == "foot" else "foot (toes)" if p == "toes" else p]


## the bars on the body as it stands now: [] = all pass, else the misses in words
static func bars(B: Body, spec: Dictionary, m: Dictionary) -> Array:
	var miss := []
	var cs: Array = spec["contacts"]
	for i in cs.size():
		if float(m["gaps"][i]) > TOUCH:
			miss.append("the %s is %.1f cm off the floor (bar 1 cm)" % [_label(cs[i]), float(m["gaps"][i]) * 100.0])
	if float(m["free_low"][1]) < CLEAR:
		miss.append("the %s is %.1f cm over the floor and was not named (bar 2 cm)" % [m["free_low"][0], float(m["free_low"][1]) * 100.0])
	if float(m["deep"]) > FLOOR_IN:
		miss.append("the %s is %.1f cm into the floor (bar 1 cm)" % [m["deep_at"], float(m["deep"]) * 100.0])
	if float(m["margin"]) < MARGIN:
		miss.append("the COM is %s the support (bar 2 cm inside)" % ("%.1f cm inside" % (float(m["margin"]) * 100.0) if float(m["margin"]) >= 0.0 else "%.1f cm outside" % (-float(m["margin"]) * 100.0) if float(m["margin"]) > -INF else "over no support at all"))
	for h in m["heights"]:
		var o: Dictionary = h[0]
		var want: float = o.get("h", NAN)
		if is_nan(want):
			if float(h[1]) < CLEAR:
				miss.append("the %s should be off the floor but is %.1f cm over it" % [_label(o), float(h[1]) * 100.0])
		elif absf(float(h[1]) - want) > HEIGHT_TOL:
			miss.append("the %s is %.1f cm off the floor, %.0f cm was asked (bar 1 cm)" % [_label(o), float(h[1]) * 100.0, want * 100.0])
	if m.has("pen") and float(m["pen"][0]) >= Feasible.PEN_FIX:
		miss.append("%s pass %.1f cm into each other (bar %.0f cm)" % [m["pen"][1], float(m["pen"][0]) * 100.0, Feasible.PEN_FIX * 100.0])
	var lim := limits_off(B)
	if not lim.is_empty():
		miss.append("past a limit: " + ", ".join(lim))
	return miss


## joints outside their limits (data/body_limits.json): ["thigh_l bend 130.0 (-25..120)"]
static func limits_off(B: Body) -> Array:
	var out := []
	for j in Body.BODY:
		var v: Vector3 = B.ang[j]
		var cl := B.clamp_ang(j, v)
		if not v.is_equal_approx(cl):
			out.append("%s %s" % [j, v])
	return out


## solve the pose the text describes ON B (the floor is y = 0; props are set aside while solving). On a refusal B is
## left exactly as it was.
static func solve(B: Body, text: String) -> Dictionary:
	var spec := parse(text)
	if not spec["ok"]:
		return spec
	if (spec["contacts"] as Array).is_empty():
		return {"ok": false, "error": "nothing is on the floor: say what touches it, e.g. " + _examples()}
	var fam := family(spec)
	if fam == "head":
		var hands_up: bool = (spec["off"] as Array).any(func(o): return o["part"] in ["hand", "forearm"])
		var arms_down: bool = (spec["contacts"] as Array).any(func(o): return o["part"] in ["hand", "forearm"])
		return {"ok": false, "error": "can't stand on the head%s: this solver keeps the head above the hips (an upside-down body is not one it poses), and %s. Nothing was changed. Say e.g. %s" % [
			" with the hands in the air" if hands_up else "",
			"with %s the head would be the ONLY support, the whole body's weight through the neck" % ("both hands in the air" if hands_up else "no hands or forearms on the floor") if not arms_down else "a headstand is not in its vocabulary",
			_examples()]}
	if fam == "":
		return {"ok": false, "error": "I have no pose that rests on %s alone. Kine solves standing, one leg, tiptoes, squatting or reaching to the floor, kneeling on one or both knees, hands and knees, sitting, lunges and planks. Nothing was changed" % ", ".join((spec["contacts"] as Array).map(func(e): return _label(e)))}
	var keep := B.state()
	var props := B.props
	var yaw := _heading(B)
	var pelvis_xz := Vector2((B.P["pelvis"] as Vector3).x, (B.P["pelvis"] as Vector3).z)
	B.props = []
	spec["_pairs"] = _pair_list(B)
	_seed(B, fam, spec)
	var seed := {}
	for j in Body.BODY:
		seed[j] = B.ang[j]
	_search(B, spec, seed)
	# face where the body faced, the pelvis where it stood (a turn about the vertical through the pelvis)
	if absf(yaw) > 1e-4:
		var before := measure(B, spec, false)
		var snap := [B.ang.duplicate(), B.offset]
		B.turn_world("pelvis", Quaternion(Vector3.UP, yaw))
		_ground(B, spec)
		var after := measure(B, spec, false)
		if absf(float(after["margin"]) - float(before["margin"])) > 0.001 or absf(float(after["free_low"][1]) - float(before["free_low"][1])) > 0.001:
			B.ang = snap[0]
			B.offset = snap[1]
			B.fk()
	var pz: Vector3 = B.P["pelvis"]
	B.offset.x += pelvis_xz.x - pz.x
	B.offset.z += pelvis_xz.y - pz.z
	B.fk()
	var m := measure(B, spec, true)
	var miss := bars(B, spec, m)
	B.props = props
	if not miss.is_empty():
		B.set_state(keep)
		return {"ok": false, "error": "can't rest on %s: the best pose found misses %s. Nothing was changed" % [
			", ".join((spec["contacts"] as Array).map(func(e): return _label(e))), "; ".join(miss)]}
	return report(B, spec, m, fam)


## the body's heading now (rad about +y, 0 = facing +z): its facing on the floor, or for a face-down body where its head points
static func _heading(B: Body) -> float:
	var g: Quaternion = B.G["pelvis"]
	var f: Vector3 = g * Vector3(0, 0, 1)
	f.y = 0.0
	if f.length() < 0.3:
		f = g * Vector3(0, 1, 0)
		f.y = 0.0
	if f.length() < 1e-4:
		return 0.0
	return atan2(f.x, f.z)


static func report(B: Body, spec: Dictionary, m: Dictionary, fam: String) -> Dictionary:
	var cs: Array = spec["contacts"]
	var cen := []
	for fp in m["per"]:
		var pts: PackedVector2Array = fp
		if pts.is_empty():
			cen.append(null)
			continue
		var s := Vector2.ZERO
		for q in pts:
			s += q
		cen.append(s / pts.size())
	var com: Vector3 = m["com"]
	var w := shares(cen, Vector2(com.x, com.z))
	var sup := []
	var total := 0.0
	for i in cs.size():
		var pct := snappedf(float(w[i]) * 100.0, 0.1)
		total += float(w[i]) * 100.0
		sup.append({"part": _label(cs[i]), "said": cs[i]["said"], "implied": cs[i]["implied"],
			"gap_cm": snappedf(float(m["gaps"][i]) * 100.0, 0.01), "share_pct": pct})
	var hs := []
	for h in m["heights"]:
		hs.append({"part": _label(h[0]), "cm": snappedf(float(h[1]) * 100.0, 0.1), "asked_cm": snappedf(float(h[0].get("h", NAN)) * 100.0, 0.1) if not is_nan(float(h[0].get("h", NAN))) else null})
	return {"ok": true, "family": fam, "supports": sup, "share_total_pct": snappedf(total, 0.01),
		"margin_cm": snappedf(float(m["margin"]) * 100.0, 0.1), "lowest_free": {"part": m["free_low"][0], "cm": snappedf(float(m["free_low"][1]) * 100.0, 0.1)},
		"into_floor_cm": snappedf(float(m["deep"]) * 100.0, 0.01), "self_pen_cm": snappedf(float(m["pen"][0]) * 100.0, 0.01),
		"heights": hs, "notes": spec["notes"], "weight_method": WEIGHT_METHOD,
		"trust": {"contacts": "MEASURED on this body (capsules, sole points; see support_pose.gd)", "margin": "HEURISTIC (Balance's foot shadow + the other contacts' capsule axes, no disc)", "shares": "HEURISTIC"}}


## the words box's run (main._pose_words hands it here): solve, then ONE undo step with the result; a refusal changes
## nothing. Says the shares in the status line.
static func run(m: Node, text: String) -> Dictionary:
	var B: Body = m.B
	var before := B.state()
	var r := solve(B, text)
	if not r["ok"]:
		m._say(r["error"])
		return r
	var after := B.state()
	B.set_state(before)
	m._do(func(): B.set_state(after))
	var parts := (r["supports"] as Array).map(func(s): return "%s %.0f%%" % [s["part"], s["share_pct"]])
	m._say("posed on %s (COM %.1f cm inside; weight, an estimate: %s); Ctrl+Z takes it back" % [", ".join((r["supports"] as Array).map(func(s): return s["part"])), r["margin_cm"], ", ".join(parts)])
	return r
