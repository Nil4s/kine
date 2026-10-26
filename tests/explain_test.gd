## godot --headless --path . -s tests/explain_test.gd     (INNOVATIONS N091 EXPLAIN THIS MOTION: scripts/explain_motion.gd; serve `explain`)
## THREE CLIPS, on the default body: scenes/combo3.json (a bat combo, 3 strikes), a front kick (built here exactly as
## tests/knobs_test.gd builds it: guard, chamber, FRONT KICK, recover) and scenes/swing_fore.json (a weapon swing).
## HAND LABELS, read by eye off the 60 Hz striking-end speed curves (EventQuery.speed_series: bat tip, right ankle) BEFORE
## scripts/explain_motion.gd was written; sample index = t x 60 (one 30 fps frame = 2 samples):
##   swing_fore      anticipation 19-45, action 46-49, contact 50, follow-through 51-65, recovery 85-118
##   kick            anticipation 16-31, action 32-35, contact 36, follow-through 37-39, recovery 40-60
##   combo3 (whole)  the fastest strike (3.05 s): anticipation 137-178, action 179-182, contact 183, follow-through 184-207,
##                   recovery 228-260
##   combo3 0-1.2 s  the first strike: anticipation 19-45, action 46-49, contact 50, follow-through 51-65, no recovery
##                   (it flows into the second strike's wind-up)
## BARS (written before the first run):
##   1 PHASES: every labelled phase is found, and each of its two ends is within 2 samples (1 frame at 30 fps) of the label;
##     a phase labelled absent is absent
##   2 POWER: the chain is I8's output: on each clip power.chain.order is ForceView.sample's chain peaks sorted by time,
##     in_order is its "ok", every peak time within 1 ms of it; the kick says the arm chain is not judged (limb_matches false)
##   3 READ: each clip slowed 2x (every card retime 200 %) has "slower / heavier" in read.words and its original does not;
##     swing_fore without its wind-up card and the kick without its chamber say "no anticipation" (words and text), their
##     originals do not
##   4 DETERMINISTIC: the same clip explained twice (EventQuery's cache cleared between) is byte-identical JSON
##   5 SCENE UNCHANGED: the scene's cards and the body's state are identical after every explain; through serve the live
##     scene, the live body and the scene file are unchanged
##   6 TEXT: under 250 words on every clip; every sentence lists fields that exist in the JSON; every number in the text
##     (the try's `command` aside, and a citation's year) carries a unit
##   7 SERVE / CLI / UI: serve `explain` on combo3 answers {phases, power, read, try, text}; {card: 99} is -32602; {card: 10}
##     explains the strike of card 10 (contact inside its span); the CHECK panel's Critique has an "Explain" button and the
##     registry command shows the text (its first sentence on a label); explain_motion.gd has no colour literal; on combo3's
##     card 3 the try is `fix=K` and serve `check`'s finding K is that HITCH, with a fix
##   8 TRY: the no-anticipation swing's try steps, run through serve, give it an anticipation (has_antic true)
extends SceneTree

var fails := 0
const LAB := {
	"swing_fore": {"anticipation": [19, 45], "action": [46, 49], "contact": [50, 50], "follow-through": [51, 65], "recovery": [85, 118]},
	"kick": {"anticipation": [16, 31], "action": [32, 35], "contact": [36, 36], "follow-through": [37, 39], "recovery": [40, 60]},
	"combo3": {"anticipation": [137, 178], "action": [179, 182], "contact": [183, 183], "follow-through": [184, 207], "recovery": [228, 260]},
	"combo3_first": {"anticipation": [19, 45], "action": [46, 49], "contact": [50, 50], "follow-through": [51, 65], "recovery": []},
}
const TOL := 2


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


func kick_scene() -> Scene:   # tests/knobs_test.gd's kick, as it is there
	var S := scene("res://templates/punch.json")
	var B := body()
	var g: Dictionary = S.cards[0]["pose"]
	Scene.put(B, Moves._flat(g))
	var cards := [{"name": "guard", "pose": g.duplicate(true), "move": -1.0, "hold": 0.3}]
	for c in [["chamber", 70.0, 100.0, 0.25], ["FRONT KICK", 75.0, 15.0, 0.12]]:
		Scene.put(B, Moves._flat(g))
		B.set_ang("thigh_r", Vector3(c[1], 0, 0))
		B.set_ang("calf_r", Vector3(c[2], 0, 0))
		cards.append({"name": c[0], "pose": B.to_dict(), "move": c[3], "hold": 0.0})
	cards.append({"name": "recover", "pose": g.duplicate(true), "move": 0.35, "hold": 0.3})
	S.cards = cards
	S.name = "kick"
	return S


func clips() -> Dictionary:
	return {"swing_fore": scene("res://scenes/swing_fore.json"), "kick": kick_scene(), "combo3": scene("res://scenes/combo3.json")}


func slowed(S: Scene) -> Scene:
	var c := S.clone()
	c.retime(0, c.cards.size() - 1, 200.0)
	return c


func without(S: Scene, name: String) -> Scene:
	var c := S.clone()
	for i in c.cards.size():
		if c.cards[i]["name"] == name:
			c.cards.remove_at(i)
			break
	return c


## explain, checking bar 5 (scene and body unchanged) on the way
func explain(S: Scene, opt := {}) -> Dictionary:
	var B := body()
	var c0 := var_to_str(S.cards)
	var b0 := JSON.stringify(B.state())
	var r := ExplainMotion.explain(S, B, opt)
	ok(var_to_str(S.cards) == c0 and JSON.stringify(B.state()) == b0, "5 %s %s: scene cards and body state unchanged" % [S.name, JSON.stringify(opt)])
	return r


func field(o: Variant, path: String) -> Variant:
	var cur: Variant = o
	for k in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(k):
			cur = cur[k]
		elif cur is Array and k.is_valid_int() and int(k) < (cur as Array).size():
			cur = cur[int(k)]
		else:
			return null
	return cur


## the numbers in the text without a unit (the `command` and a citation's year left out)
func unitless(text: String) -> Array:
	var t := text
	var rx := RegEx.create_from_string("`[^`]*`")
	t = rx.sub(t, "", true)
	t = RegEx.create_from_string("[A-Z][a-z]+ (&|and) [A-Z][a-z]+ (19|20)\\d\\d").sub(t, "", true)   # Flash & Hogan 1985
	var bad := []
	var num := RegEx.create_from_string("(frames? )?(?<![A-Za-z0-9.])(-?\\d+(\\.\\d+)?)(-(\\d+(\\.\\d+)?))?(%|x\\b| ?(s|ms|m/s|cm|deg/s|deg|kg m/s|frames?|kinks?|samples?|strikes)\\b)?")
	for mt in num.search_all(t):
		var whole := mt.get_string(0)
		if whole.strip_edges() == "" or mt.get_string(2) == "":
			continue
		if mt.get_string(1) == "" and mt.get_string(7) == "":
			bad.append(whole)
	return bad


func check_phases(key: String, r: Dictionary) -> void:
	var lab: Dictionary = LAB[key]
	var got := {}
	for p in r["phases"]:
		got[p["phase"]] = [int(p["i0"]), int(p["i1"])]
	for ph in ExplainMotion.PHASES:
		var want: Array = lab[ph]
		if want.is_empty():
			ok(not got.has(ph), "1 %s %s: labelled absent, found %s" % [key, ph, str(got.get(ph, "none"))])
			continue
		var g: Array = got.get(ph, [])
		var d0 := absi(int(g[0]) - int(want[0])) if not g.is_empty() else 999
		var d1 := absi(int(g[1]) - int(want[1])) if not g.is_empty() else 999
		ok(d0 <= TOL and d1 <= TOL, "1 %s %s: found %s, label %s (ends off by %d, %d samples; bar %d)" % [key, ph, str(g), str(want), d0, d1, TOL])


func check_chain(key: String, S: Scene, r: Dictionary) -> void:
	var B := body()
	var fv := ForceView.sample(S, B)
	var ch: Dictionary = fv["chain"]
	var mine: Dictionary = r["power"]["chain"]
	var order := ForceView.CHAIN.duplicate()
	order.sort_custom(func(x, y): return float(ch["peak"][x]) < float(ch["peak"][y]) or (float(ch["peak"][x]) == float(ch["peak"][y]) and ForceView.CHAIN.find(x) < ForceView.CHAIN.find(y)))
	var worst := 0.0
	for nm in ForceView.CHAIN:
		worst = maxf(worst, absf(float(mine["peak_t"][nm]) - float(ch["peak"][nm])) * 1000.0)
	ok(mine["order"] == order and bool(mine["in_order"]) == bool(ch["ok"]) and worst <= 1.0,
		"2 %s: chain %s in_order %s (I8: %s ok %s), worst peak-time gap %.2f ms (bar 1)" % [key, str(mine["order"]), mine["in_order"], str(order), ch["ok"], worst])


func check_text(key: String, r: Dictionary) -> void:
	ok(int(r["words"]) < ExplainMotion.MAX_WORDS, "6 %s: %d words (bar < 250)" % [key, int(r["words"])])
	var missing := []
	for s in r["sentences"]:
		if (s["fields"] as Array).is_empty():
			missing.append(s["s"].left(40))
		for f in s["fields"]:
			if field(r, f) == null:
				missing.append(f)
	ok(missing.is_empty(), "6 %s: every sentence maps to fields of the JSON (missing: %s)" % [key, str(missing)])
	var bad := unitless(String(r["text"]))
	ok(bad.is_empty(), "6 %s: every number has a unit (unitless: %s)" % [key, str(bad)])


func _init() -> void:
	var t_all := Time.get_ticks_msec()
	var cs := clips()
	var res := {}
	for key in ["swing_fore", "kick", "combo3"]:
		var S: Scene = cs[key]
		var t0 := Time.get_ticks_msec()
		var r := explain(S, {"scene_path": "scenes/%s.json" % key})
		print("     %s: %d ms; %s" % [key, Time.get_ticks_msec() - t0, r.get("text", r.get("error", ""))])
		res[key] = r
		ok(r["ok"] and r.has("phases") and r.has("power") and r.has("read") and r.has("try") and r.has("text"), "7 %s: {phases, power, read, try, text}" % key)
		check_phases(key, r)
		check_chain(key, S, r)
		check_text(key, r)
	var r1 := explain(cs["combo3"], {"t0": 0.0, "t1": 1.2})
	check_phases("combo3_first", r1)
	check_text("combo3_first", r1)
	ok(not bool(res["kick"]["power"]["chain"]["limb_matches"]) and String(res["kick"]["text"]).contains("not judged"), "2 kick: the arm chain is not judged (limb_matches false, the text says so)")
	# 3 READ
	for key in ["swing_fore", "kick", "combo3"]:
		var w0: Array = res[key]["read"]["words"]
		var rs := explain(slowed(cs[key]))
		var w2: Array = rs["read"]["words"]
		ok(w2.has("slower / heavier") and not w0.has("slower / heavier"), "3 %s slowed 2x: %s (action %.3f s); original: %s (action %.3f s)" % [key, str(w2), rs["read"]["action_s"], str(w0), res[key]["read"]["action_s"]])
	for kv in [["swing_fore", "wind-up"], ["kick", "chamber"]]:
		var rn := explain(without(cs[kv[0]], kv[1]))
		var w0: Array = res[kv[0]]["read"]["words"]
		ok((rn["read"]["words"] as Array).has("no anticipation") and String(rn["text"]).to_lower().contains("no anticipation") and not w0.has("no anticipation"),
			"3 %s without '%s': %s; try %s; original: %s" % [kv[0], kv[1], str(rn["read"]["words"]), str(rn["try"].get("steps", [])), str(w0)])
		if kv[0] == "swing_fore":
			res["noantic"] = rn
	# 4 DETERMINISTIC
	for key in ["swing_fore", "combo3"]:
		EventQuery.clear_cache()
		var a := JSON.stringify(explain(cs[key], {"scene_path": "scenes/%s.json" % key}))
		ok(a == JSON.stringify(res[key]), "4 %s: a second explain is byte-identical (%d chars)" % [key, a.length()])
	# 7 / 5 / 8 the live app
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var T := AgentTools.new(m)
	var bytes0 := FileAccess.get_file_as_bytes("res://scenes/combo3.json")
	await T.request(1, "open", {"path": "scenes/combo3.json"})
	var cards0 := JSON.stringify(m.S.cards)
	var body0 := JSON.stringify(m.B.state())
	var sv: Dictionary = await T.request(2, "explain", {})
	var sr: Dictionary = sv.get("result", {})
	ok(sr.has("phases") and sr.has("power") and sr.has("read") and sr.has("try") and sr.has("text") and int(sr.get("words", 999)) < 250,
		"7 serve explain on combo3: %s" % String(sr.get("text", JSON.stringify(sv))).left(160))
	var bad: Dictionary = await T.request(3, "explain", {"card": 99})
	ok(bad.has("error") and int(bad["error"]["code"]) == -32602, "7 explain {card: 99}: %s" % JSON.stringify(bad.get("error", {})))
	var c10: Dictionary = (await T.request(4, "explain", {"card": 10})).get("result", {})
	var ts: Array = m.S.times()
	var ct := -1.0
	for p in c10.get("phases", []):
		if p["phase"] == "contact":
			ct = float(p["t0"])
	ok(ct >= float(ts[9][0]) - 1e-3 and ct <= float(ts[9][2]) + 1e-3, "7 explain {card: 10}: contact %.3f s inside card 10's span %.3f-%.3f s" % [ct, ts[9][0], ts[9][2]])
	var c3: Dictionary = (await T.request(8, "explain", {"card": 3})).get("result", {})
	var st3: Array = c3.get("try", {}).get("steps", [])
	var chk: Dictionary = (await T.request(9, "check", {})).get("result", {})
	var fk := int(String(st3[0]).substr(4)) if not st3.is_empty() and String(st3[0]).begins_with("fix=") else -1
	var fnd: Dictionary = (chk.get("findings", []) as Array)[fk - 1] if fk >= 1 and fk <= (chk.get("findings", []) as Array).size() else {}
	ok(fnd.get("rule", "") == "HITCH" and String(fnd.get("fix", "")) != "", "7 combo3 card 3: try %s = check finding %s" % [str(st3), JSON.stringify(fnd).left(160)])
	ok(JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.B.state()) == body0 and FileAccess.get_file_as_bytes("res://scenes/combo3.json") == bytes0,
		"5 serve: live cards, live body and the scene file unchanged")
	# the UI: Critique's panel has the Explain button; the registry command shows the text
	m._critique()
	var btn: Button = null
	for b in m.ui_find_list.find_children("*", "Button", true, false):
		if (b as Button).text == "Explain":
			btn = b
	ok(btn != null, "7 the Critique panel has an Explain button")
	var cmd: Dictionary = {}
	for c in m._commands():
		if c["id"] == "check_explain_this_motion":
			cmd = c
	ok(not cmd.is_empty(), "7 the registry has check_explain_this_motion")
	if btn != null:
		btn.pressed.emit()
	var first := String((sr.get("sentences", [{"s": "?"}]) as Array)[0]["s"])
	var shown := false
	for l in m.ui_find_list.find_children("*", "Label", true, false):
		if (l as Label).text == first:
			shown = true
	ok(m.ui_find.visible and shown, "7 Explain shows the text in the CHECK panel (first sentence on a label: %s)" % shown)
	var src := FileAccess.get_file_as_string("res://scripts/explain_motion.gd")
	ok(not src.contains("Color(") and not src.contains("add_theme_color_override"), "7 explain_motion.gd: no colour literal (theme tokens via _label)")
	# 8 the no-anticipation tries, run through serve
	for kv in [["kick", "chamber"], ["swing_fore", "wind-up"]]:
		var nS := without(cs[kv[0]], kv[1])
		var na := explain(nS)
		var tmp := ProjectSettings.globalize_path("user://explain_noantic_%s.json" % kv[0])
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		f.store_string(JSON.stringify(nS.to_dict(body())))
		f.close()
		await T.request(5, "open", {"path": tmp})
		var run: Dictionary = await T.request(6, "run", {"steps": na["try"]["steps"]})
		var after: Dictionary = (await T.request(7, "explain", {})).get("result", {})
		ok(not run.has("error") and bool(after.get("read", {}).get("has_antic", false)),
			"8 %s without '%s': try %s run through serve: has_antic %s, anticipation %.2f s (%s)" % [kv[0], kv[1], str(na["try"]["steps"]), after.get("read", {}).get("has_antic", false),
			float(after.get("read", {}).get("antic_s", 0.0)), JSON.stringify(run.get("error", "")).left(120)])
		print("     after: %s" % String(after.get("text", "")).left(400))
		DirAccess.remove_absolute(tmp)
	print("%s explain: %d failures (%.1f s)" % ["PASS" if fails == 0 else "FAIL", fails, (Time.get_ticks_msec() - t_all) / 1000.0])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
