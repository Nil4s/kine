## WHAT WOULD THIS ANGLE DO (round 2, R10): the maths a blind agent needs BEFORE it moves a joint, as plain text + JSON.
##   ask "joint=elbow_r axis=flex value=90"            (several changes: separate them with ; or ,)
##   describe joint elbow_r                            (the joint's frame in words + its limits)
## A query runs the SAME code the app runs for a typed angle (Body.set_ang_safe: the joint's limits, and the move stops
## where parts meet) on the live body, reads the numbers, and puts the body back exactly (B.state / B.set_state): the scene,
## the cards, the undo stack, the picked part and the playhead are untouched. Formulas: stated here.
## Reach % = how far the hand (wrist) / foot (ankle) is from the limb's root (shoulder / hip joint), over the limb's full
## stretch (upper segment + lower segment, joint to joint): 100 % = the limb straight.
## Balance is Balance.read (de Leva COM over the support polygon, scripts/balance.gd) and the TIPPING verdict is Check's own
## test (HumanLimits._tipping: margin past MARGIN_RES, a foot down, nothing in the hands holding).
class_name WhatIf
extends RefCounted

const ALIAS := {"shoulder": "upperarm", "elbow": "lowerarm", "forearm": "lowerarm", "wrist": "hand", "hip": "thigh", "knee": "calf",
	"shin": "calf", "shank": "calf", "ankle": "foot", "toe": "ball", "toes": "ball", "neck": "neck_01", "waist": "spine_01",
	"back": "spine_02", "chest": "spine_03", "upper_arm": "upperarm", "lower_arm": "lowerarm"}
const AXES := {"bend": "bend", "flex": "bend", "flexion": "bend", "extend": "bend", "side": "side", "abduct": "side", "abduction": "side",
	"lateral": "side", "twist": "twist", "roll": "twist", "rotate": "twist", "rotation": "twist"}
const AXI := {"bend": 0, "side": 1, "twist": 2}
## [end, root, mid] of the four limbs whose reach is asked (the end is the wrist / ankle joint)
const LIMBS := {"hand_r": ["upperarm_r", "lowerarm_r"], "hand_l": ["upperarm_l", "lowerarm_l"],
	"foot_r": ["thigh_r", "calf_r"], "foot_l": ["thigh_l", "calf_l"]}
const HINGE := {"lowerarm": "flex closes the elbow: the forearm bends toward the upper arm (the hand comes toward the shoulder); 0 is straight",
	"calf": "flex closes the knee: the shank bends back toward the thigh (the heel comes toward the buttock); 0 is straight"}


## "elbow_r" / "right elbow" / "lowerarm_r" -> "lowerarm_r"; "" if it is no joint
static func joint_name(raw: String) -> String:
	var s := raw.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	var side := ""
	for pre in [["right_", "_r"], ["left_", "_l"]]:
		if s.begins_with(pre[0]):
			s = s.substr(pre[0].length())
			side = pre[1]
	for suf in [["_right", "_r"], ["_left", "_l"], ["_r", "_r"], ["_l", "_l"]]:
		if s.ends_with(suf[0]):
			s = s.left(s.length() - suf[0].length())
			side = suf[1]
			break
	s = ALIAS.get(s, s)
	if s + side in Body.BODY:
		return s + side
	if s in Body.BODY:
		return s
	return ""


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


## "joint=elbow_r axis=flex value=90; joint=head axis=twist value=-20" -> {"ok", "changes": [{joint, axis, value}]}
static func parse(text: String) -> Dictionary:
	var out := []
	for grp in text.replace(",", ";").split(";", false):
		var kv := {}
		for tok in grp.strip_edges().split(" ", false):
			var e := tok.find("=")
			if e > 0:
				kv[tok.left(e).to_lower()] = tok.substr(e + 1)
		if grp.strip_edges() == "":
			continue
		if not (kv.has("joint") and kv.has("axis") and kv.has("value")):
			return _err("each change needs joint, axis and value, e.g. \"joint=elbow_r axis=flex value=90\" (got '%s')" % grp.strip_edges())
		var j := joint_name(kv["joint"])
		if j == "":
			return _err("no joint '%s': say a part like elbow_r, knee_l, upperarm_r, head (describe lists them); a side needs _l or _r" % kv["joint"])
		var ax: String = AXES.get(String(kv["axis"]).to_lower(), "")
		if ax == "":
			return _err("no axis '%s': say flex (bend), side or twist" % kv["axis"])
		if not String(kv["value"]).is_valid_float():
			return _err("value must be degrees, e.g. value=90 (got '%s')" % kv["value"])
		out.append({"joint": j, "axis": ax, "value": float(kv["value"])})
	if out.is_empty():
		return _err("say what to turn: \"joint=elbow_r axis=flex value=90\" (more than one: separate them with ;)")
	return {"ok": true, "changes": out}


static func _r(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


## everything one pose says, read off the body as it stands
static func read(B: Body) -> Dictionary:
	var d := {"limbs": {}}
	for e in LIMBS:
		var rt: Vector3 = B.P[LIMBS[e][0]]
		var md: Vector3 = B.P[LIMBS[e][1]]
		var en: Vector3 = B.P[e]
		var mx := rt.distance_to(md) + md.distance_to(en)
		d["limbs"][e] = {"pos": en, "reach_m": rt.distance_to(en), "max_m": mx, "reach_pct": 100.0 * rt.distance_to(en) / mx}
	d["tip"] = B.wep_point(B.wep_len) if B.wep_on else null
	# the nearest gap between two parts, beyond what each pair already sits in at rest (the app's own allowance)
	var best := INF
	var at := ["", ""]
	for pr in B.pairs:
		if not B.wep_on and (pr[0] in Body.WEAPON or pr[1] in Body.WEAPON):
			continue
		if not B.wep2_on and (pr[0] in Body.WEAPON2 or pr[1] in Body.WEAPON2):
			continue
		if B.wep_on and B.grip and pr[0].begins_with("hand") and pr[1].begins_with("hand"):
			continue
		var gap := -(B.depth(pr[0], pr[1]) - float(B.allow.get(pr[0] + "|" + pr[1], 0.0)))
		if gap < best:
			best = gap
			at = [pr[0], pr[1]]
	d["gap_m"] = best
	d["gap_parts"] = at
	d["contacts"] = B.contacts()
	var bal := Balance.read(B)
	var down: Array = bal["down"]
	var sm := {"margin": [bal["margin"]], "down": [down.size() > 0], "sup": [HumanLimits.supported(B)]}
	d["balance"] = {"com": bal["com"], "margin_m": bal["margin"], "down": down, "inside": float(bal["margin"]) >= 0.0 and down.size() > 0,
		"supported": sm["sup"][0], "tipping": HumanLimits._tipping(sm, 0),
		"balance_rule": down.size() == 2 and float(bal["margin"]) < -Rulebook.BAL_OUT}
	return d


static func _bal_words(b: Dictionary) -> String:
	if b["down"].is_empty():
		return "no foot on the floor (the body is %s)" % ("held up by a hand or the weapon" if b["supported"] else "in the air")
	var cm := absf(float(b["margin_m"])) * 100.0
	var s := "centre of mass %.1f cm %s the feet's support area (feet down: %s)" % [cm, "inside" if b["inside"] else "OUTSIDE", ", ".join(b["down"].map(func(x): return "left" if x == "_l" else "right"))]
	if b["balance_rule"]:
		s += "; Check's BALANCE rule fires if it is held (both feet down, past them by more than %.0f cm)" % (Rulebook.BAL_OUT * 100.0)
	if b["tipping"]:
		s += "; the human-limits TIPPING rule fires if it is held (past the feet by more than %.0f cm with nothing holding; on after \"could a human do this\")" % (Balance.MARGIN_RES * 100.0)
	return s


## the query. m = the main node. Returns {"ok", "text": [lines], ...numbers}; the body and everything else is put back
static func ask(m: Node, text: String) -> Dictionary:
	var pr := parse(text)
	if not pr["ok"]:
		return pr
	var B: Body = m.B
	var keep: Dictionary = B.state()
	var keep_stop: Dictionary = B.last_stop.duplicate(true)
	var before := read(B)
	var rows := []
	for c in pr["changes"]:
		var j: String = c["joint"]
		var L: Vector2 = B.lim[j][c["axis"]]
		var cur: Vector3 = B.ang[j]
		var v := cur
		v[AXI[c["axis"]]] = c["value"]
		B.last_stop = {}
		B.set_ang_safe(j, v)
		var got: float = B.ang[j][AXI[c["axis"]]]
		var row := {"joint": j, "axis": c["axis"], "asked": c["value"], "got": snappedf(got, 0.01), "lo": L.x, "hi": L.y,
			"margin_deg": snappedf(minf(got - L.x, L.y - got), 0.01), "locked": L.y - L.x <= 0.5}
		if not B.last_stop.is_empty():
			row["stopped_by"] = B.last_stop.duplicate(true)
		rows.append(row)
	var after := read(B)
	B.set_state(keep)
	B.last_stop = keep_stop
	var lines := []
	var moved := {}
	for e in LIMBS:
		var a: Dictionary = after["limbs"][e]
		var b: Dictionary = before["limbs"][e]
		var mv: float = (a["pos"] as Vector3).distance_to(b["pos"])
		if mv > 0.0005:
			moved[e] = {"before": _r(b["pos"]), "after": _r(a["pos"]), "moved_m": snappedf(mv, 0.0001), "reach_pct_before": snappedf(b["reach_pct"], 0.1),
				"reach_pct": snappedf(a["reach_pct"], 0.1), "max_reach_m": snappedf(a["max_m"], 0.0001)}
	for r in rows:
		var w := "%s %s: asked %.1f deg" % [r["joint"], r["axis"], r["asked"]]
		if r["locked"]:
			w += " -> LOCKED axis, stays %.1f" % r["got"]
		elif absf(r["got"] - r["asked"]) > 0.5:
			var st: Dictionary = r.get("stopped_by", {})
			w += " -> stops at %.1f (%s)" % [r["got"], ("the joint's limit %.0f..%.0f" % [r["lo"], r["hi"]]) if st.get("kind", "") == "limit" else ("parts meet: %s" % str(st.get("pairs", []).slice(0, 2)))]
		else:
			w += " -> reached; %.1f deg from the nearest limit (%.0f..%.0f)" % [r["margin_deg"], r["lo"], r["hi"]]
		lines.append(w)
	if moved.is_empty():
		lines.append("no hand or foot moves more than 0.5 mm")
	for e in moved:
		var mv: Dictionary = moved[e]
		lines.append("%s moves %.1f cm: (%.1f, %.1f, %.1f) cm -> (%.1f, %.1f, %.1f) cm world; reach %.0f%% -> %.0f%% of the max %.1f cm" % [e, mv["moved_m"] * 100.0,
			mv["before"][0] * 100.0, mv["before"][1] * 100.0, mv["before"][2] * 100.0, mv["after"][0] * 100.0, mv["after"][1] * 100.0, mv["after"][2] * 100.0, mv["reach_pct_before"], mv["reach_pct"], mv["max_reach_m"] * 100.0])
	var tip = null
	if after["tip"] != null:
		tip = {"before": _r(before["tip"]), "after": _r(after["tip"])}
		lines.append("weapon tip: (%.1f, %.1f, %.1f) cm -> (%.1f, %.1f, %.1f) cm world" % [tip["before"][0] * 100.0, tip["before"][1] * 100.0, tip["before"][2] * 100.0, tip["after"][0] * 100.0, tip["after"][1] * 100.0, tip["after"][2] * 100.0])
	var gp: Array = after["gap_parts"]
	lines.append("nearest parts: %s and %s, %.1f cm apart%s" % [gp[0], gp[1], float(after["gap_m"]) * 100.0, " (INSIDE each other)" if float(after["gap_m"]) < 0.0 else ""])
	if not (after["contacts"] as Array).is_empty():
		lines.append("in contact: " + ", ".join((after["contacts"] as Array).map(func(c): return "%s/%s %.1f cm deep" % [c[0], c[1], float(c[2]) * 100.0])))
	lines.append("balance: " + _bal_words(after["balance"]))
	var ab: Dictionary = after["balance"]
	return {"ok": true, "text": lines, "changes": rows, "moved": moved, "weapon_tip": tip,
		"nearest": {"gap_m": snappedf(after["gap_m"], 0.0001), "parts": gp, "in_contact": (after["contacts"] as Array).map(func(c): return [c[0], c[1], snappedf(c[2], 0.0001)])},
		"balance": {"inside": ab["inside"], "margin_cm": snappedf(float(ab["margin_m"]) * 100.0, 0.1), "feet_down": ab["down"], "tipping": ab["tipping"], "balance_rule": ab["balance_rule"], "supported": ab["supported"],
			"before_inside": before["balance"]["inside"], "before_margin_cm": snappedf(float(before["balance"]["margin_m"]) * 100.0, 0.1)},
		"scene_changed": false, "note": "a query: the scene is untouched (apply it with run set=<joint>:bend,side,twist)"}


## a direction in words: the strongest world axes, "forward and up"
static func dir_words(d: Vector3) -> String:
	var names := [["his left", "his right", d.x], ["up", "down", d.y], ["forward", "back", d.z]]
	var parts := []
	var ord := [0, 1, 2]
	ord.sort_custom(func(a, b): return absf(names[a][2]) > absf(names[b][2]))
	for k in ord:
		var x: float = names[k][2]
		if absf(x) >= 0.35 * absf(names[ord[0]][2]) and absf(x) > 0.15:
			parts.append(names[k][0] if x > 0.0 else names[k][1])
	return " and ".join(parts) if not parts.is_empty() else "nowhere"


## DESCRIBE JOINT: the frame in words and the limits, from the live body's loaded data (data/skeleton.json frames,
## data/body_limits.json ranges; left = mirror of right). Reads only; the body is not touched
static func describe_joint(m: Node, raw: String) -> Dictionary:
	var j := joint_name(raw)
	if j == "":
		return _err("no joint '%s': say a part like elbow_r, knee_l, upperarm_r, head; `describe` lists them" % raw)
	var B: Body = m.B
	var t: Vector3 = B.t_ax[j]
	var lines := ["%s (parent %s, child %s); bone %.3f m long, rest point (%.3f, %.3f, %.3f) m" % [j, B.parent[j] if B.parent[j] != "" else "none",
		B.CHILD.get(j, "none"), (B.e0[j] - B.p0[j]).length(), B.p0[j].x, B.p0[j].y, B.p0[j].z]]
	lines.append("twist axis runs along the bone, at rest toward %s" % dir_words(t))
	var ax := {}
	var key := j.left(j.length() - 2) + "_r" if j.ends_with("_l") else j
	var say: Dictionary = B.lim[j].get("say", {})
	for a in ["bend", "side", "twist"]:
		var L: Vector2 = B.lim[j][a]
		var row := {"lo": L.x, "hi": L.y, "locked": L.y - L.x <= 0.5, "rule": say.get(a, "")}
		var w := "%s: %.0f to %.0f deg" % [a, L.x, L.y]
		if row["locked"]:
			w += " (locked)"
		elif a != "twist":
			# the end's swing for a positive turn at rest: d(R v) = axis x v
			var axv: Vector3 = B.b_ax[j] if a == "bend" else B.a_ax[j]
			row["end_swings"] = dir_words(axv.cross(t))
			w += "; + swings the end %s from rest" % row["end_swings"]
		if row["rule"] != "":
			w += " [" + row["rule"] + "]"
		if a == "bend" and HINGE.has(j.get_slice("_", 0)):
			w += "; " + HINGE[j.get_slice("_", 0)]
			row["words"] = HINGE[j.get_slice("_", 0)]
		lines.append(w)
		ax[a] = row
	return {"ok": true, "joint": j, "key": key, "parent": B.parent[j], "child": B.CHILD.get(j, ""), "length_m": snappedf((B.e0[j] - B.p0[j]).length(), 0.0001),
		"rest_pos": _r(B.p0[j]), "twist_axis": _r(t), "axes": ax, "text": lines, "source": "data/skeleton.json frames + data/body_limits.json ranges (read only)"}
