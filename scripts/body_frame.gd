## body_frame.gd - BODY-FRAME NUMBERS (docs/INNOVATIONS.md N007): an agent never needs world axes. A point is said in the
## body's own words and numbers, and those words are read back into a point:
##     "15 cm in front of the sternum, 3 cm above chin height, 10 cm toward his left"
## WHY: `state` / `measure` give metres on x / y / z, and a blind agent then has to know that +x is HIS left and that the
## fighter may be turned; every agent we watched got a sign wrong somewhere. The body's own frame has no such trap.
##
## THE FRAME (one per fighter, yaw only):
##   up      = the world's up (+y). Heights stay heights, so "above chin height" means higher, whatever the trunk does
##   left    = the hip line (left hip joint - right hip joint) and the shoulder line (left - right upper arm joint), each
##             made unit, added and laid flat: the pelvis AND chest facing, so a 45 deg torso twist reads as half of it
##   forward = left x up  (body.gd: +x his left, +y up, +z his front; x cross y = z)
## A fighter turned 90 deg (by its placement or by its pelvis) gives the SAME words: everything is measured in this frame.
## A body lying flat has no hip-line trouble (the line stays across the body); only a body whose hips AND shoulders are
## both vertical (a cartwheel's top) has no flat left: then the pelvis's own +x is used.
##
## THE LANDMARKS (scripts/say_it.gd's landmark() for the face and trunk, so "at the chin" means what I5 means by it):
##   head top  the head's end point (Body.E["head"])        chin, sternum, navel   SayIt.landmark chin / chest / belly
##   hips      the hip joint centres (thigh_l / thigh_r)     knees  the knee joints (calf_l / calf_r)
##   feet      the ankle joints (foot_l / foot_r)            hands  the wrist joints (hand_l / hand_r): the SAME points
##             `measure` and `state` call hand_r, foot_r, so a number from either agrees with these words
##
## THE WORDS (three clauses, always all three, in this order; numbers in cm to 0.1, ".0" dropped):
##   along   "<n> cm in front of <lm>" | "<n> cm behind <lm>" | "level with <lm>"      lm = the NEAREST landmark (3D)
##   height  "<n> cm above <lm> height" | "<n> cm below <lm> height" | "at <lm> height"   lm = the landmark nearest in height
##   side    "<n> cm toward his left" | "... his right" | "not to either side"          (from the along-landmark)
## The other fighter's landmarks and frame: "the opponent's chin", "toward the opponent's left". Both directions in a
## clause are the frame of the fighter it names (in front of the opponent's chin = toward whoever he faces).
## Read back: the clauses in any order, any may be missing (along missing: no point; height missing: the along
## landmark's height; side missing: 0), "at the opponent's chin" = the landmark itself, his / her / their = the fighter,
## mm / cm / m units, "top of the head", chest, belly, wrist, ankle as aliases.
##
## Rounding: 0.1 cm per axis, so words -> point is within sqrt(3) * 0.05 = 0.087 cm of the point described (bar 0.5 cm).
class_name BodyFrame
extends RefCounted

## landmark keys, in the order a tie is broken (unpaired first, then left before right)
const KEYS := ["sternum", "chin", "head_top", "navel", "hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r", "hand_l", "hand_r"]
const LABEL := {"sternum": "sternum", "chin": "chin", "head_top": "head top", "navel": "navel", "hip_l": "left hip", "hip_r": "right hip",
	"knee_l": "left knee", "knee_r": "right knee", "foot_l": "left foot", "foot_r": "right foot", "hand_l": "left hand", "hand_r": "right hand"}
## words read back -> the landmark (a paired one takes "_l" / "_r" from its side word)
const ALIAS := {"sternum": "sternum", "chest": "sternum", "breastbone": "sternum", "chin": "chin", "head top": "head_top", "crown": "head_top",
	"head": "head_top", "navel": "navel", "belly button": "navel", "belly": "navel", "stomach": "navel", "hip": "hip", "hips": "hip",
	"knee": "knee", "knees": "knee", "foot": "foot", "feet": "foot", "ankle": "foot", "hand": "hand", "hands": "hand", "wrist": "hand",
	"fist": "hand"}
const SELF_WORDS := ["his ", "her ", "their ", "his own ", "her own ", "their own "]
const OPP_WORDS := ["the opponent's ", "opponent's ", "the other fighter's ", "other fighter's ", "the opponent’s ", "opponent’s "]
const ZERO := 0.0005   # m: under half a millimetre rounds to 0.0 cm, the "level with" / "at" / "not to either side" words


## a fighter: its body and its placement (body space -> the space the caller's points are in)
static func fighter(B: Body, xf := Transform3D.IDENTITY) -> Dictionary:
	var lm := {}
	var loc := {"sternum": SayIt.landmark(B, "chest", "", "_r"), "chin": SayIt.landmark(B, "chin", "", "_r"), "head_top": B.E["head"],
		"navel": SayIt.landmark(B, "belly", "", "_r")}
	for sd in ["_l", "_r"]:
		loc["hip" + sd] = B.P["thigh" + sd]
		loc["knee" + sd] = B.P["calf" + sd]
		loc["foot" + sd] = B.P["foot" + sd]
		loc["hand" + sd] = B.P["hand" + sd]
	for k in KEYS:
		lm[k] = xf * (loc[k] as Vector3)
	var hip := ((xf * (B.P["thigh_l"] as Vector3)) - (xf * (B.P["thigh_r"] as Vector3)))
	var sho := ((xf * (B.P["upperarm_l"] as Vector3)) - (xf * (B.P["upperarm_r"] as Vector3)))
	var left := hip.normalized() + sho.normalized()
	left.y = 0.0
	if left.length() < 1e-4:
		left = xf.basis * ((B.G["pelvis"] as Quaternion) * Vector3(1, 0, 0))
		left.y = 0.0
	left = left.normalized()
	return {"lm": lm, "left": left, "fwd": left.cross(Vector3.UP).normalized()}


## m -> cm to 0.1. Snapped to a micron first: the same point reached through a turned placement differs by ~1e-7 m, and
## 14.5499999 / 14.5500001 must not round apart (measured: 1 of 212 points at 180 deg before this)
static func _cm(v: float) -> float:
	return snappedf(snappedf(v * 100.0, 0.0001), 0.1)


## the point the words (a, h, f / l / u in cm) say
static func _rebuild(F: Dictionary, a: String, h: String, f: float, l: float, u: float) -> Vector3:
	var q: Vector3 = (F["lm"][a] as Vector3) + (F["fwd"] as Vector3) * f * 0.01 + (F["left"] as Vector3) * l * 0.01
	q.y = (F["lm"][h] as Vector3).y + u * 0.01
	return q


## [the along landmark, the height landmark] for a point. Near-ties (within 0.01 mm) go to the landmark nearer in 3D,
## then to KEYS order: the two knees of a standing body are at one height, and a tie broken by list order alone would
## say "left knee height" for a point by his right knee (measured: 80 of 212 mirrored points)
static func _choose(p: Vector3, lm: Dictionary) -> Array:
	var a := ""
	var h := ""
	var bd := INF
	var bh := INF
	for k: String in KEYS:
		var q: Vector3 = lm[k]
		var d := p.distance_to(q)
		if d < bd - 1e-5:
			bd = d
			a = k
		var dh := absf(p.y - q.y)
		if dh < bh - 1e-5 or (dh < bh + 1e-5 and d < p.distance_to(lm[h]) - 1e-9):
			bh = minf(dh, bh)
			h = k
	return [a, h]


static func _num(cm: float) -> String:
	var s := "%.1f" % absf(cm)
	return s.trim_suffix(".0")


## the landmark's words: "the sternum" / "the opponent's left knee"
static func _lm_words(key: String, opp: bool) -> String:
	return ("the opponent's " if opp else "the ") + String(LABEL[key])


## a height's words: "chin height" / "the opponent's chin height"
static func _h_words(key: String, opp: bool) -> String:
	return ("the opponent's " if opp else "") + String(LABEL[key]) + " height"


## a world point in words and numbers, in fighter F's frame (opp = F is the opponent of whoever the words are for)
static func describe(p: Vector3, F: Dictionary, opp := false) -> Dictionary:
	var lm: Dictionary = F["lm"]
	var ah := _choose(p, lm)
	var a: String = ah[0]
	var h: String = ah[1]
	var dv: Vector3 = p - (lm[a] as Vector3)
	var f := _cm(dv.dot(F["fwd"]))
	var l := _cm(dv.dot(F["left"]))
	var u := _cm(p.y - (lm[h] as Vector3).y)
	# THE WORDS MUST READ BACK TO THEMSELVES: a point within ~0.1 cm of where two landmarks are equally near can round
	# onto the other one's side, and its words then read back as a different phrase (measured: 2 of 212 points around
	# the opponent). Then the nearest 0.1 cm step of the 26 round it that still picks the same landmarks is said
	# instead: at most 0.1 cm more per axis, so the words stay within 0.26 cm of p (bar 0.5)
	if _choose(_rebuild(F, a, h, f, l, u), lm) != ah:
		var best := INF
		var pick := Vector3(f, l, u)
		for df in [-0.1, 0.0, 0.1]:
			for dl in [-0.1, 0.0, 0.1]:
				for du in [-0.1, 0.0, 0.1]:
					var c := Vector3(f + df, l + dl, u + du)
					var q := _rebuild(F, a, h, c.x, c.y, c.z)
					if _choose(q, lm) == ah and q.distance_to(p) < best:
						best = q.distance_to(p)
						pick = c
		f = snappedf(pick.x, 0.1)
		l = snappedf(pick.y, 0.1)
		u = snappedf(pick.z, 0.1)
	var bd: float = p.distance_to(lm[a])
	var who := "the opponent's" if opp else "his"
	var c1 := ("level with " + _lm_words(a, opp)) if f == 0.0 else ("%s cm %s %s" % [_num(f), "in front of" if f > 0.0 else "behind", _lm_words(a, opp)])
	var c2 := ("at " + _h_words(h, opp)) if u == 0.0 else ("%s cm %s %s" % [_num(u), "above" if u > 0.0 else "below", _h_words(h, opp)])
	var c3 := "not to either side" if l == 0.0 else ("%s cm toward %s %s" % [_num(l), who, "left" if l > 0.0 else "right"])
	return {"words": "%s, %s, %s" % [c1, c2, c3], "of": "opponent" if opp else "self", "anchor": a, "height_of": h,
		"forward_cm": f, "above_cm": u, "left_cm": l, "distance_cm": _cm(bd),
		"point": [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]}


## "the opponent's left knee" -> {"opp": bool, "key": "knee_l"} or {"error"}
static func _read_lm(s: String) -> Dictionary:
	s = s.strip_edges()
	var re := RegEx.create_from_string("^(?:the )?top of (.*?)head$")
	var mt := re.search(s)
	if mt != null:
		s = mt.get_string(1) + "head top"
	var opp := false
	for w: String in OPP_WORDS:
		if s.begins_with(w):
			opp = true
			s = s.substr(w.length())
			break
	if not opp:
		for w: String in SELF_WORDS:
			if s.begins_with(w):
				s = s.substr(w.length())
				break
		s = s.trim_prefix("the ")
	var sd := ""
	if s.begins_with("left "):
		sd = "_l"
		s = s.substr(5)
	elif s.begins_with("right "):
		sd = "_r"
		s = s.substr(6)
	s = s.strip_edges()
	if not ALIAS.has(s):
		return {"error": "'%s' is not a landmark: say sternum, chin, head top, navel, or a left / right hip, knee, foot, hand" % s}
	var k: String = ALIAS[s]
	if k in ["hip", "knee", "foot", "hand"]:
		if sd == "":
			return {"error": "which %s: say 'left %s' or 'right %s'" % [k, k, k]}
		k += sd
	elif sd != "":
		return {"error": "the %s has no left or right" % LABEL[k]}
	return {"opp": opp, "key": k}


static func _metres(n: String, unit: String) -> float:
	return float(n) * {"mm": 0.001, "cm": 0.01, "m": 1.0}[unit]


## words -> a world point. S = the fighter the words are about, O = the other one ({} = none).
## -> {"ok", "point": Vector3, ...} or {"ok": false, "error"}
static func place(text: String, S: Dictionary, O: Dictionary) -> Dictionary:
	var t := text.to_lower().replace("’", "'").strip_edges().trim_suffix(".")
	var num := "(\\d+(?:\\.\\d+)?)\\s*(mm|cm|m)"
	var r_along := RegEx.create_from_string("^" + num + "\\s+(in front of|ahead of|forward of|behind|back of)\\s+(.+)$")
	var r_level := RegEx.create_from_string("^(?:level with|at|on)\\s+(.+)$")
	var r_h := RegEx.create_from_string("^" + num + "\\s+(above|below|over|under)\\s+(.+?)\\s+height$")
	var r_h0 := RegEx.create_from_string("^(?:at|level with)\\s+(.+?)\\s+height$")
	var r_side := RegEx.create_from_string("^" + num + "\\s+(?:toward|towards|to)\\s+(?:the )?(.*?)\\s*(left|right)$")
	var r_side0 := RegEx.create_from_string("^(?:not to either side|centred|centered|in line)$")
	var along := {}
	var height := {}
	var side := {}
	for raw: String in t.split(",", false):
		var c := raw.strip_edges().trim_prefix("and ").strip_edges()
		if c == "":
			continue
		var mt: RegExMatch
		var lm: Dictionary
		mt = r_h.search(c)
		if mt == null:
			mt = r_h0.search(c)
			if mt != null:
				lm = _read_lm(mt.get_string(1))
				if lm.has("error"):
					return {"ok": false, "error": lm["error"]}
				height = {"lm": lm, "d": 0.0}
				continue
		else:
			lm = _read_lm(mt.get_string(4))
			if lm.has("error"):
				return {"ok": false, "error": lm["error"]}
			var d := _metres(mt.get_string(1), mt.get_string(2))
			height = {"lm": lm, "d": d if mt.get_string(3) in ["above", "over"] else -d}
			continue
		mt = r_along.search(c)
		if mt != null:
			lm = _read_lm(mt.get_string(4))
			if lm.has("error"):
				return {"ok": false, "error": lm["error"]}
			var d := _metres(mt.get_string(1), mt.get_string(2))
			along = {"lm": lm, "d": -d if mt.get_string(3) in ["behind", "back of"] else d}
			continue
		mt = r_side.search(c)
		if mt != null:
			var ow := mt.get_string(3).strip_edges()
			var so := ow in ["opponent's", "other fighter's", "opponent’s"]
			if not so and not (ow in ["his", "her", "their", ""]):
				return {"ok": false, "error": "'%s': say toward his left / right, or toward the opponent's left / right" % c}
			var d := _metres(mt.get_string(1), mt.get_string(2))
			side = {"opp": so, "d": d if mt.get_string(4) == "left" else -d}
			continue
		if r_side0.search(c) != null:
			side = {"opp": false, "d": 0.0}
			continue
		mt = r_level.search(c)
		if mt != null:
			lm = _read_lm(mt.get_string(1))
			if lm.has("error"):
				return {"ok": false, "error": lm["error"]}
			along = {"lm": lm, "d": 0.0}
			continue
		return {"ok": false, "error": "'%s' is not understood: say e.g. \"15 cm in front of the sternum, 3 cm above chin height, 10 cm toward his left\"" % c}
	if along.is_empty():
		return {"ok": false, "error": "no landmark to measure from: start with \"<n> cm in front of / behind <landmark>\", \"level with <landmark>\" or \"at <landmark>\""}
	for q: Dictionary in [along, height, side]:
		var o: bool = q["lm"]["opp"] if q.has("lm") else q.get("opp", false)
		if o and O.is_empty():
			return {"ok": false, "error": "there is no opponent: add a second fighter (run [\"Actor: add a second fighter\"]) or turn the dummy on"}
	var A: Dictionary = O if along["lm"]["opp"] else S
	var p: Vector3 = (A["lm"][along["lm"]["key"]] as Vector3) + (A["fwd"] as Vector3) * float(along["d"])
	if not side.is_empty():
		var SF: Dictionary = O if side["opp"] else S
		p += (SF["left"] as Vector3) * float(side["d"])
	if not height.is_empty():
		var HF: Dictionary = O if height["lm"]["opp"] else S
		p.y = (HF["lm"][height["lm"]["key"]] as Vector3).y + float(height["d"])
	return {"ok": true, "point": p}


# ------------------------------------------------------------------------------------------------ the live poser (serve)

## the fighters on the live poser, in the space `state` and `measure` give points in (the ACTIVE fighter's body space):
## [{"name", "F"}]; fighter 1 = the hero. One fighter + the dummy on: the dummy is fighter 2 (it stands where Dummy.xf says)
static func fighters(m: Node) -> Array:
	var out := []
	m._actors_sync()
	if m.actors_rt.size() >= 2:
		m._pose_others()
		var xa: Transform3D = (m.actors_rt[m.actor_on]["xf"] as Transform3D).affine_inverse()
		for k in m.actors_rt.size():
			var a: Dictionary = m.actors_rt[k]
			out.append({"name": "the hero" if k == 0 else String(a["name"]), "B": a["B"], "F": fighter(a["B"], xa * (a["xf"] as Transform3D))})
		return out
	out.append({"name": "the hero", "B": m.B, "F": fighter(m.B)})
	if m.dummy_on:
		out.append({"name": "the dummy", "B": m.T.D, "F": fighter(m.T.D, m.T.xf)})
	return out


## serve's where / place: {"ok", ...} or {"ok": false, "error"}
##   where {point: [x,y,z] | joint: "hand_r", who: 1|2 (default the active fighter), of: "self" | "opponent"}
##   place {text, who}
static func serve(m: Node, method: String, p: Dictionary) -> Dictionary:
	var fs := fighters(m)
	var who := int(p.get("who", int(m.actor_on) + 1 if m.actors_rt.size() >= 2 else 1))
	if who < 1 or who > fs.size():
		return {"ok": false, "error": "who must be 1..%d (1 = the hero; %s)" % [fs.size(), ", ".join(fs.map(func(f): return f["name"]))]}
	var S: Dictionary = fs[who - 1]["F"]
	var O: Dictionary = fs[2 - who]["F"] if fs.size() == 2 else {}
	if method == "place":
		var text := String(p.get("text", ""))
		if text == "":
			return {"ok": false, "error": "place needs {\"text\": \"15 cm in front of the sternum, 3 cm above chin height, 10 cm toward his left\"}"}
		var r := place(text, S, O)
		if not r["ok"]:
			return r
		var q: Vector3 = r["point"]
		return {"ok": true, "point": [snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001)], "unit": "m", "who": who,
			"words": describe(q, S)["words"], "note": "the point in the active fighter's space (as state / measure give points)"}
	var of := String(p.get("of", "self"))
	if not (of in ["self", "opponent"]):
		return {"ok": false, "error": "of is \"self\" (the fighter's own landmarks) or \"opponent\" (the other fighter's)"}
	if of == "opponent" and O.is_empty():
		return {"ok": false, "error": "there is no opponent: add a second fighter or turn the dummy on"}
	var pt: Vector3
	if p.has("joint"):
		var j := String(p["joint"])
		var B: Body = fs[who - 1]["B"]
		if not B.P.has(j):
			return {"ok": false, "error": "'%s' is not a joint (hand_r, foot_l, head, ... : describe lists them)" % j}
		var xf := Transform3D.IDENTITY
		if m.actors_rt.size() >= 2:
			xf = (m.actors_rt[m.actor_on]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[who - 1]["xf"] as Transform3D)
		elif who == 2:
			xf = m.T.xf
		pt = xf * (B.P[j] as Vector3)
	else:
		var a: Variant = p.get("point")
		if not (a is Array) or a.size() != 3 or not a.all(func(v): return v is float or v is int):
			return {"ok": false, "error": "where needs {\"point\": [x, y, z]} (m, as state gives points) or {\"joint\": \"hand_r\"}; optional who (1 / 2), of (\"self\" / \"opponent\")"}
		pt = Vector3(float(a[0]), float(a[1]), float(a[2]))
	var d := describe(pt, O if of == "opponent" else S, of == "opponent")
	d["ok"] = true
	d["who"] = who
	return d


## measure's frame:"body": each part a measure names (and the centre of mass) said in words, in the active fighter's frame
static func annotate(m: Node, out: Array) -> void:
	var F := fighter(m.B)
	for e: Dictionary in out:
		var a := String(e["what"]).split(" ", false)
		var bw := []
		if a[0] == "com":
			bw.append(describe(Balance.com(m.B), F))
		elif a[0] in ["distance", "angle", "height", "speed"]:
			for k in range(1, a.size()):
				var q: Variant = m.B.P.get(a[k])
				if a[k] == "weapon_tip" or a[k] == "weapon_knob":
					q = m.B.wep_point(m.B.wep_len if a[k] == "weapon_tip" else 0.0) if m.B.wep_on else null
				if q != null:
					var dd := describe(q, F)
					dd["part"] = a[k]
					bw.append(dd)
		if not bw.is_empty():
			e["body"] = bw
