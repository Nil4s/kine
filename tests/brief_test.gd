## godot --headless --path . -s tests/brief_test.gd     (INNOVATIONS N011: scene brief, scripts/scene_brief.gd; serve `brief`)
## Bars, written before measuring:
##  (1) every scene in scenes/ (top level; not _wip, not _archive) briefs at 100, 400 and 1000 tokens within its budget (chars / 4),
##      every line a whole sentence (ends with "."), the scene line always there
##  (2) facts match the source: the card count is the file's and the text says it; the length is Scene.length to 0.01 s; every contact
##      time is within 1 frame (1 / the scene's fps) of an independent Dummy.hits at 60 fps on a fresh body, and the counts agree; the
##      score equals the one the registry command "realism_score" (the "Realism score" button) leaves, rounded, and the text says "realism N/100"
##      (the button end to end on combo3; on the others its refresh, the button minus its 40 s gain-predicting panel); on combo3, hit_react
##      and bo_spin also a COLD score (no judge answer, frame or force cache kept) rounds the same
##  (3) deterministic: with the facts cache cleared, a second brief of the same scene is byte-identical at every budget (combo3, hit_react)
##  (4) combo3's brief names its real top finding: PROBLEM 1 carries the score's first reason's rule and card, and its fix step
##      `fix=K` is a finding of serve `check` with that rule and card (after the human-limits step when it is given)
##  (5) nothing is written: every scene file is byte-identical after its brief, and the live cards are unchanged by it
##  (6) serve: `brief {path, tokens}` answers through AgentTools.request; tokens under the minimum is a -32602 error
extends SceneTree

var fails := 0
var m: Node
var T: AgentTools


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a score from nothing cached (as tests/i16_test.gd's): the judges asked again, the frame memo and the force cache empty
const COLD := ["combo3", "hit_react", "bo_spin"]


func _cold_score() -> float:
	var rs: RealismUI = m.rs_ui
	var keep_memo = rs._memo
	var keep_force = m.force_cache
	rs._memo = {}
	rs.jcache = {}
	m.force_cache = {}
	var sv := FrameMemo._mem
	FrameMemo._mem = {}
	FrameMemo.probe = true
	var g := rs.gather(m.tc_ui.db)
	FrameMemo.probe = false
	FrameMemo._mem = sv
	rs._memo = keep_memo
	m.force_cache = keep_force
	return float(RealismScore.shown(float(RealismScore.compute(m.S, g)["raw"])))


func _scenes() -> Array:
	var out := []
	for fn in DirAccess.get_files_at("res://scenes/"):
		if fn.ends_with(".json"):
			out.append(fn.get_basename())
	out.sort()
	return out


func _whole(text: String) -> bool:
	for l in text.split("\n"):
		if not l.ends_with("."):
			return false
	return true


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	T = AgentTools.new(m)
	var t_all := Time.get_ticks_msec()
	# (6) the error first (no scene work)
	var bad: Dictionary = await T.request(9, "brief", {"tokens": 10})
	ok(bad.has("error") and int(bad["error"]["code"]) == -32602, "6 tokens 10 refused with -32602: %s" % JSON.stringify(bad.get("error", {})).left(160))
	for sn in _scenes():
		var path := "scenes/%s.json" % sn
		var bytes0 := FileAccess.get_file_as_bytes("res://" + path)
		var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + path))
		var t0 := Time.get_ticks_msec()
		var r0: Dictionary = await T.request(1, "brief", {"path": path, "tokens": 400, "facts": true})
		if r0.has("error"):
			ok(false, "%s: brief error %s" % [sn, JSON.stringify(r0["error"])])
			continue
		var res0: Dictionary = r0["result"]
		var f: Dictionary = res0["facts"]
		var cards0 := var_to_str(m.S.cards)
		var texts := {}
		for tk in [100, 400, 1000]:
			var q: Dictionary = (await T.request(2, "brief", {"tokens": tk}))["result"]
			texts[tk] = q["text"]
			var n := SceneBrief.est_tokens(q["text"])
			ok(n <= tk and q["text"].begins_with("SCENE ") and _whole(q["text"]),
				"1 %s @%d: %d tokens, %d lines, kept %s" % [sn, tk, n, q["text"].split("\n").size(), ",".join(q["kept"])])
		# (2) facts
		var nc: int = (file["cards"] as Array).size()
		ok(int((f["cards"] as Array).size()) == nc and texts[100].contains("%d cards" % nc), "2 %s: %d cards (file %d), the text says it" % [sn, (f["cards"] as Array).size(), nc])
		ok(absf(float(f["length_s"]) - m.S.length()) < 0.01, "2 %s: length %.3f s = Scene.length %.3f" % [sn, float(f["length_s"]), m.S.length()])
		var D := Dummy.new()
		D.place(m.T.dist, m.T.yaw)
		var HB := Body.new()
		HB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var ref: Array = D.hits(m.S.clone(), HB, 60) if m.dummy_on else []
		var ct: Array = f["contacts"]
		var near := ct.size() == ref.size()
		for c in ct:
			var best := INF
			for h in ref:
				best = minf(best, absf(float(h["t"]) - float(c["t"])))
			near = near and best <= 1.0 / float(m.S.fps) + 1e-6 and c["J"] != null and float(c["J"]) > 0.0
			ok(texts[1000].contains("%.2f s (frame %d)" % [float(c["t"]), int(c["frame"])]), "2 %s: contact %.2f s on %s, %.1f N s is in the 1000-token text" % [sn, float(c["t"]), c["on"], float(c["J"])])
		ok(near, "2 %s: %d contacts, %d at 60 fps independently, each within 1 frame, impulse > 0" % [sn, ct.size(), ref.size()])
		var sc: Variant = f["realism"]["score"]
		var said := "its refresh"
		if sn == "combo3":   # the button end to end (its panel predicts each fix's gain: 40 s on a long scene, so once)
			var st: Dictionary = await T.step("realism_score")
			said = st["said"].left(60) if st["ok"] else "FAILED"
		else:
			m.rs_ui.refresh()   # what the command computes before it draws its panel (RealismUI.show)
		var cmd := roundi(float(m.rs_ui.res["score"]))
		var cold := roundi(_cold_score()) if sn in COLD else cmd
		ok(sc != null and int(sc) == cmd and cold == cmd and texts[100].contains("realism %d/100" % cmd), "2 %s: score %s = the command's %d (%s)%s" % [sn, str(sc), cmd, said, (", cold %d" % cold) if sn in COLD else ""])
		# (5)
		ok(FileAccess.get_file_as_bytes("res://" + path) == bytes0 and var_to_str(m.S.cards) == cards0, "5 %s: file and cards untouched" % sn)
		# (3)
		if sn == "combo3" or sn == "hit_react":
			SceneBrief._cache.clear()
			var same := true
			for tk in [100, 400, 1000]:
				var q2: Dictionary = (await T.request(3, "brief", {"tokens": tk}))["result"]
				same = same and q2["text"] == texts[tk]
			ok(same, "3 %s: a cold second brief is byte-identical at 100 / 400 / 1000" % sn)
		# (4)
		if sn == "combo3":
			var rs: Array = f["realism"]["reasons"]
			var top: Dictionary = m.rs_ui.res["reasons"][0]
			var line := ""
			for l in texts[400].split("\n"):
				if l.begins_with("PROBLEM 1"):
					line = l
			var fd: Dictionary = m.rs_ui.inp["findings"][int(top["fix"]["i"])] if top["fix"]["kind"] == "check" else {}
			var rule := String(fd.get("rule", top["judge"]))
			ok(not rs.is_empty() and line.contains(rule) and line.contains("card %d" % int(rs[0]["card"])), "4 combo3: PROBLEM 1 names %s at card %d: %s" % [rule, int(rs[0]["card"]) if not rs.is_empty() else 0, line.left(200)])
			var steps: Array = rs[0]["steps"] if not rs.is_empty() else []
			var good := false
			if not steps.is_empty():
				var keep: bool = HumanLimits.on
				HumanLimits.on = steps[0] == SceneBrief.FEASIBLE_STEP or keep
				var fs := T.findings()
				HumanLimits.on = keep
				m._check()
				var K := int(String(steps[-1]).trim_prefix("fix="))
				good = K >= 1 and K <= fs.size() and fs[K - 1]["rule"] == rule and int(fs[K - 1]["card"]) == int(rs[0]["card"])
			ok(good, "4 combo3: its fix steps %s are that finding in serve check" % JSON.stringify(steps))
		print("     %s: %d ms" % [sn, Time.get_ticks_msec() - t0])
	print("     all: %d ms" % (Time.get_ticks_msec() - t_all))
	print("BRIEF: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
