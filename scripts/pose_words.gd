## pose_words.gd - words to a pose (round 13, GATES T3): "raise the right arm 90, bend the left elbow 45".
## A phrase is clauses (split at "," ";" "and" "then"); a clause is  VERB [the] [SIDE] PART [DIRECTION] [to] NUMBER.
## The meanings are the joints' own (data/body_limits.json "say"): raising an arm is its SIDE angle going up, bending a
## knee is the calf's BEND, turning the head left is its TWIST going + (his left). A number turns BY that much from where
## the joint is; "to N" sets the angle itself (the raw bend / side / twist, as `describe` and the panel show it).
## The chest is three spine joints: a lean is shared between them. Body clamps every angle to its limit, so the caller
## reports what was REACHED next to what was asked (main._pose_words).
## parse() -> {"ok": true, "ops": [{"joint", "axis": 0 bend / 1 side / 2 twist, "mode": "by"/"to", "deg"}]}
##         or {"ok": false, "error": "... what to type instead"}
class_name PoseWords
extends RefCounted

const AXES := ["bend", "side", "twist"]
## a word -> the joint stem ("*" = a side is needed: _l / _r is added); "spine" = the three spine joints
const PARTS := {"arm": "upperarm*", "upperarm": "upperarm*", "elbow": "lowerarm*", "forearm": "lowerarm*", "wrist": "hand*",
	"hand": "hand*", "shoulder": "clavicle*", "leg": "thigh*", "thigh": "thigh*", "hip": "thigh*", "knee": "calf*",
	"ankle": "foot*", "foot": "foot*", "toes": "ball*", "head": "head", "neck": "neck_01", "chest": "spine", "spine": "spine",
	"torso": "spine", "body": "pelvis", "hips": "pelvis", "pelvis": "pelvis"}
## [verb, joint stem, direction ("" = the verb alone), axis, sign]; sign 0 = "to 0" (straighten: no number needed).
## ("back" is a direction, never a part: "lean the chest back 20")
const MOVES := [
	["raise", "upperarm", "", 1, 1], ["lower", "upperarm", "", 1, -1], ["raise", "upperarm", "forward", 0, 1],
	["swing", "upperarm", "forward", 0, 1], ["swing", "upperarm", "back", 0, -1], ["roll", "upperarm", "", 2, 1], ["twist", "upperarm", "", 2, 1],
	["bend", "lowerarm", "", 0, 1], ["straighten", "lowerarm", "", 0, 0],
	["bend", "hand", "", 0, 1], ["curl", "hand", "", 0, 1], ["extend", "hand", "", 0, -1], ["roll", "hand", "", 2, 1], ["twist", "hand", "", 2, 1],
	["shrug", "clavicle", "", 0, 1], ["drop", "clavicle", "", 0, -1],
	["raise", "thigh", "", 0, 1], ["lower", "thigh", "", 0, -1], ["kick", "thigh", "", 0, 1], ["swing", "thigh", "forward", 0, 1],
	["swing", "thigh", "back", 0, -1], ["swing", "thigh", "out", 1, 1], ["swing", "thigh", "in", 1, -1], ["spread", "thigh", "", 1, 1],
	["roll", "thigh", "", 2, 1], ["twist", "thigh", "", 2, 1],
	["bend", "calf", "", 0, 1], ["straighten", "calf", "", 0, 0],
	["point", "foot", "", 0, -1], ["flex", "foot", "", 0, 1], ["raise", "foot", "", 0, 1], ["turn", "foot", "out", 1, 1], ["turn", "foot", "in", 1, -1],
	["bend", "ball", "", 0, 1], ["raise", "ball", "", 0, 1],
	["nod", "head", "", 0, 1], ["lower", "head", "", 0, 1], ["raise", "head", "", 0, -1], ["turn", "head", "left", 2, 1], ["turn", "head", "right", 2, -1],
	["tilt", "head", "left", 1, 1], ["tilt", "head", "right", 1, -1],
	["turn", "neck_01", "left", 2, 1], ["turn", "neck_01", "right", 2, -1], ["tilt", "neck_01", "left", 1, 1], ["tilt", "neck_01", "right", 1, -1],
	["bend", "neck_01", "", 0, 1],
	["lean", "spine", "forward", 0, 1], ["lean", "spine", "back", 0, -1], ["lean", "spine", "left", 1, 1], ["lean", "spine", "right", 1, -1],
	["bend", "spine", "", 0, 1], ["turn", "spine", "left", 2, 1], ["turn", "spine", "right", 2, -1], ["twist", "spine", "left", 2, 1], ["twist", "spine", "right", 2, -1],
	["lean", "pelvis", "forward", 0, 1], ["lean", "pelvis", "back", 0, -1], ["lean", "pelvis", "left", 1, 1], ["lean", "pelvis", "right", 1, -1],
	["turn", "pelvis", "left", 2, 1], ["turn", "pelvis", "right", 2, -1],
]
const SKIP := ["the", "his", "her", "their", "its", "a", "by", "degrees", "degree", "deg", "please", "up", "down"]
const DIRS := ["forward", "forwards", "back", "backward", "backwards", "left", "right", "out", "outward", "in", "inward"]
const DIR_IS := {"forwards": "forward", "backward": "back", "backwards": "back", "outward": "out", "inward": "in"}


static func verbs() -> Array:
	var v := {}
	for m in MOVES:
		v[m[0]] = true
	return v.keys()


static func parse(text: String) -> Dictionary:
	var t := text.to_lower().replace(";", ",").replace(" and ", ",").replace(" then ", ",").replace("°", " ")
	var ops := []
	for clause in t.split(",", false):
		var r := _clause(clause.strip_edges())
		if not r["ok"]:
			return r
		ops.append_array(r["ops"])
	if ops.is_empty():
		return {"ok": false, "error": "nothing to do: say e.g. 'raise the right arm 90, bend the left elbow 45'"}
	return {"ok": true, "ops": ops}


static func _clause(c: String) -> Dictionary:
	var verb := ""
	var part := ""
	var side := ""
	var dir := ""
	var to := false
	var num := NAN
	for w: String in c.split(" ", false):
		w = w.strip_edges()
		if w in SKIP:
			continue
		if w.is_valid_float():
			num = float(w)
		elif w.ends_with("deg") and w.trim_suffix("deg").is_valid_float():
			num = float(w.trim_suffix("deg"))
		elif w == "to":
			to = true
		elif w in ["left", "right"] and part == "" and verb != "" and side == "":
			side = "_l" if w == "left" else "_r"   # before the part: whose part
		elif w in DIRS:
			dir = DIR_IS.get(w, w)
		elif w in verbs() and verb == "":
			verb = w
		elif PARTS.has(w.trim_suffix("s")) or PARTS.has(w):
			part = w if PARTS.has(w) else w.trim_suffix("s")
		else:
			return {"ok": false, "error": "'%s' is not a word I know. Verbs: %s. Parts: %s. Then left/right, a direction (forward, back, left, right, out, in), and degrees ('to 30' sets the angle)" % [w, ", ".join(verbs()), ", ".join(PARTS.keys())]}
	if verb == "":
		return {"ok": false, "error": "'%s' has no verb: start with one of %s" % [c, ", ".join(verbs())]}
	if part == "":
		return {"ok": false, "error": "'%s' has no body part: name one of %s" % [c, ", ".join(PARTS.keys())]}
	var stem: String = PARTS[part]
	var sided := stem.ends_with("*")
	stem = stem.trim_suffix("*")
	if sided and side == "":
		return {"ok": false, "error": "which %s: say 'left %s' or 'right %s'" % [part, part, part]}
	# "turn the head left": left/right AFTER the part is a direction, not a side. The row must match the direction
	# exactly (none given = the row without one)
	var row: Array = []
	var ok_verbs := {}
	var dirs := []
	for m in MOVES:
		if m[1] != stem:
			continue
		ok_verbs[m[0]] = true
		if m[0] == verb:
			dirs.append(m[2])
			if m[2] == dir:
				row = m
	if row.is_empty():
		if dirs.is_empty():
			return {"ok": false, "error": "'%s' does not go with the %s: for the %s say %s" % [verb, part, part, ", ".join(ok_verbs.keys())]}
		var named := dirs.filter(func(d): return d != "")
		return {"ok": false, "error": "'%s the %s' %s: %s%s" % [verb, part, "needs a direction" if dir == "" else "does not go '%s'" % dir,
			", ".join(named), " (or none)" if "" in dirs else ""]}
	var sign: int = row[4]
	if sign == 0:   # straighten: to 0, no number needed
		to = true
		num = 0.0
	if is_nan(num):
		return {"ok": false, "error": "'%s' needs degrees: e.g. '%s 30' (by 30) or '%s to 30' (the angle itself)" % [c, c, c]}
	var joints: Array = ["spine_01", "spine_02", "spine_03"] if stem == "spine" else [stem + side]
	var ops := []
	for j in joints:
		var deg := (num if to else sign * num) / joints.size()   # the chest: shared by its three joints
		ops.append({"joint": j, "axis": row[3], "mode": "to" if to else "by", "deg": deg})
	return {"ok": true, "ops": ops}
