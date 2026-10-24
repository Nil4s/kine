## godot --headless --path . -s tests/spec_test.gd     (N004 SPEC TO MOTION, scripts/spec_motion.gd)
## A structured spec in, a clip out that passes every assertion or lists what it could not meet. Bars, stated before measuring:
##   1 SIX SPECS against the dummy (jab left at 0.85 m, cross right 0.85, hook left 0.7, front kick right 1.1, roundhouse
##     right 1.1, bat swing right 1.3; each with its contacts and "COM inside the feet all clip"): at least 5 of 6 come back
##     ok, and for each that does (a) BodyAssert.run, called HERE on the returned clip, passes every line of the spec
##     (contacts as "<side> foot planted all clip" + the spec's assertions), and (b) the strike end (SpecMotion.end_point:
##     knuckle face / ball / instep / tip), measured HERE on the clip as it plays (Scene.apply_true), is within 3 cm of the
##     target point at the nearest frame of contact_t +-1 frame.
##   2 IMPOSSIBLE: a jab at a point 3 m out, both feet planted -> ok false, an unmet entry whose why names "reach", and its
##     closest (cm) within 2 cm of the true shortfall measured HERE at the contact frame: |target - shoulder| minus the arm's
##     length (shoulder -> elbow -> wrist -> knuckle face, the arm's own segment lengths).
##   3 APPLY + ONE UNDO: on combo3, `spec {apply: true}` adds cards_added cards (the scene grows by exactly that, in one undo
##     step); one undo puts the scene back BIT-EXACT (the scene as its file would be, JSON text).
##   4 DRY PLAN: `spec` without apply leaves the scene (JSON text), its card count and the undo stack unchanged; the result
##     carries ok / cards_added / assertions / unmet. A spec with an unknown kind is -32602.
##   5 TIME: every plan in 1 answers in under 40 s (a weapon spec includes text-to-blocking's own retrieval).
##   6 STEP FOR REACH: a jab at 1.15 m with no planted contact comes back ok with a repair that names a step.
extends SceneTree

var fails := 0
var m: Node
var T: AgentTools


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func snap() -> String:
	return JSON.stringify(T.scene_dict())


func spec(kind: String, side: String, target: Variant, ct: float, a: float, r: float, contacts: Array, extra := {}) -> Dictionary:
	var s := {"kind": kind, "side": side, "target": target, "contact_t": ct, "timing": {"anticipation": a, "recovery": r},
		"contacts": contacts, "assertions": ["COM inside the feet all clip"]}
	s.merge(extra, true)
	return s


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	T = AgentTools.new(m)
	m.S = Scene.new()
	m._rebuild_cards()

	# 1 SIX SPECS (+ 5 TIME)
	var rows := [
		[0.85, spec("jab", "left", "opponent's chin", 0.35, 0.12, 0.3, ["both feet planted"])],
		[0.85, spec("cross", "right", "opponent's chin", 0.4, 0.15, 0.35, ["both feet planted"])],
		[0.7, spec("hook", "left", "opponent's chin", 0.4, 0.15, 0.35, ["both feet planted"])],
		[1.1, spec("front kick", "right", "opponent's navel", 0.5, 0.25, 0.4, ["left foot planted"])],
		[1.1, spec("roundhouse", "right", "opponent's navel", 0.55, 0.3, 0.4, ["left foot planted"])],
		[1.3, spec("swing", "right", "opponent's head", 0.6, 0.3, 0.4, ["both feet planted"], {"weapon": "bat"})],
	]
	var good := 0
	for row in rows:
		m.T.place(row[0])
		var sp: Dictionary = row[1]
		var t0 := Time.get_ticks_msec()
		var r := SpecMotion.plan(m, sp)
		var ms := Time.get_ticks_msec() - t0
		var name := "%s %s" % [sp.get("weapon", ""), sp["kind"]]
		ok(ms < 40000, "5 %s planned in %d ms (bar 40000)" % [name, ms])
		if not r.has("scene"):
			ok(false, "1 %s: no clip (%s)" % [name, r.get("error", "")])
			continue
		var S: Scene = r["scene"]
		var B := SpecMotion._body(m.S.body)
		# (a) the spec's lines, run here
		var lines := []
		for c in sp["contacts"]:
			for sd in SpecMotion.PLANT_WORDS[c]:
				lines.append("%s foot planted all clip" % ("left" if sd == "_l" else "right"))
		lines += sp["assertions"]
		var res: Array = BodyAssert.run(S, B, lines.map(func(l): return SpecMotion.opp_line(String(l))))["results"]
		var all_pass := true
		var say := []
		for x in res:
			all_pass = all_pass and bool(x.get("pass", false))
			if not bool(x.get("pass", false)):
				say.append(String(x.get("say", x.get("error", ""))).left(120))
		# (b) the end at contact_t +-1 frame, measured here
		var tp := PackedFloat64Array(r["target"]["point"])
		var tgt := Vector3(tp[0], tp[1], tp[2])
		var fps := float(S.fps)
		var c0 := roundi(float(sp["contact_t"]) * fps)
		var near := INF
		var endd: Dictionary = _end_of(r, sp)
		for f in [c0 - 1, c0, c0 + 1]:
			S.apply_true(B, f / fps)
			near = minf(near, SpecMotion.end_point(B, endd).distance_to(tgt) * 100.0)
		var passed: bool = bool(r["ok"]) and all_pass and near <= 3.0
		if passed:
			good += 1
		print("     %s: ok %s, lines here %s, end %.2f cm from the target near contact, cards %d, repairs %s%s" % [name, r["ok"], "all pass" if all_pass else "FAIL " + "; ".join(say), near, r["cards_added"], r["repairs"], "" if r["ok"] else ", unmet " + str((r["unmet"] as Array).map(func(u): return String(u["why"]).left(140)))])
	ok(good >= 5, "1 %d of 6 specs pass every line with the end within 3 cm at contact_t +-1 f (bar 5)" % good)

	# 2 IMPOSSIBLE
	m.T.place(0.85)
	var imp := spec("jab", "left", [0.0, 1.45, 3.0], 0.35, 0.12, 0.3, ["both feet planted"])
	imp["assertions"] = []
	var ri := SpecMotion.plan(m, imp)
	var reach_u: Dictionary = {}
	for u in ri.get("unmet", []):
		if String(u["why"]).begins_with("reach"):
			reach_u = u
	var Si: Scene = ri["scene"]
	var Bi := SpecMotion._body(m.S.body)
	Si.apply_true(Bi, roundi(0.35 * float(Si.fps)) / float(Si.fps))
	var sh: Vector3 = Bi.P["upperarm_l"]
	var arm: float = sh.distance_to(Bi.P["lowerarm_l"]) + (Bi.P["lowerarm_l"] as Vector3).distance_to(Bi.P["hand_l"]) \
		+ (Bi.P["hand_l"] as Vector3).distance_to(SpecMotion.end_point(Bi, {"kind": "fist", "sd": "_l"}))
	var true_short := (sh.distance_to(Vector3(0.0, 1.45, 3.0)) - arm) * 100.0
	var closest: float = float(reach_u["closest"]["value"]) if not reach_u.is_empty() else INF
	ok(not bool(ri["ok"]) and not reach_u.is_empty() and absf(closest - true_short) <= 2.0,
		"2 impossible: ok %s, unmet '%s', closest %.2f cm vs the true shortfall %.2f cm (bar 2)" % [ri["ok"], String(reach_u.get("why", "none")).left(90), closest, true_short])

	# 3 APPLY + ONE UNDO, 4 DRY PLAN
	await T.request(1, "open", {"path": "scenes/combo3.json"})
	m.T.place(0.85)
	var jab: Dictionary = rows[0][1]
	var before := snap()
	var n0: int = m.S.cards.size()
	var u0: int = m.undo.size()
	var dry: Dictionary = await T.request(2, "spec", {"spec": jab})
	var dr: Dictionary = dry.get("result", {})
	ok(snap() == before and m.S.cards.size() == n0 and m.undo.size() == u0 and dr.has("ok") and dr.has("cards_added") and dr.has("assertions") and dr.has("unmet") and not bool(dr.get("applied", true)),
		"4 dry plan: the scene, its %d cards and the undo stack (%d) unchanged; result keys %s" % [n0, u0, dr.keys()])
	var bad: Dictionary = await T.request(3, "spec", {"spec": {"kind": "flying teacup", "side": "left", "target": "opponent's chin"}})
	ok(bad.has("error") and int(bad["error"]["code"]) == -32602, "4 an unknown kind is -32602: %s" % str(bad.get("error", {})).left(160))
	var ap: Dictionary = await T.request(4, "spec", {"spec": jab, "apply": true})
	var ar: Dictionary = ap.get("result", {})
	var added := int(ar.get("cards_added", -1))
	ok(m.S.cards.size() == n0 + added and added > 0 and m.undo.size() == u0 + 1,
		"3 apply: %d cards -> %d (cards_added %d), undo %d -> %d" % [n0, m.S.cards.size(), added, u0, m.undo.size()])
	m._undo()
	ok(snap() == before and m.S.cards.size() == n0, "3 one undo puts the scene back bit-exact (%d cards)" % m.S.cards.size())

	# 6 STEP FOR REACH
	m.S = Scene.new()
	m._rebuild_cards()
	m.T.place(1.15)
	var st := SpecMotion.plan(m, spec("jab", "left", "opponent's chin", 0.4, 0.15, 0.3, []))
	var named := false
	for x in st.get("repairs", []):
		named = named or String(x).contains("step")
	ok(bool(st.get("ok", false)) and named, "6 a jab at 1.15 m, no planted contact: ok %s, repairs %s, unmet %s" % [st.get("ok"), st.get("repairs"), (st.get("unmet", []) as Array).map(func(u): return String(u["why"]).left(100))])

	print("spec_test: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)


## the strike end the plan used, read back from its own words ("left fist" ...) through the kind table
func _end_of(r: Dictionary, sp: Dictionary) -> Dictionary:
	var words := String(r.get("end", ""))
	var sd := "_l" if words.contains("left") else "_r"
	if words.contains("tip"):
		return {"kind": "tip", "sd": sd}
	if words.contains("instep"):
		return {"kind": "instep", "sd": sd}
	if words.contains("ball"):
		return {"kind": "ball", "sd": sd}
	return {"kind": "fist", "sd": sd}
