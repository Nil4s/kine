## godot --headless --path . -s tests/fixloop_test.gd     (INNOVATIONS N005: fix until it passes, scripts/fix_loop.gd; serve `fix_until`)
## Bars, written before measuring (probe 10-23, dry runs: combo3 23.05 -> 56.42 in 4 kept fixes, 1108 s; dodge_side 33.84 -> 42.36 in
## 2 kept HITCH fixes, 45 s; so dodge_side carries the cheap bars and combo3 runs capped at 2):
##  (1) serve: bar 150 and max_steps 0 are -32602 errors (no scene work)
##  (2) DRY on dodge_side (bar 40): the plan keeps >= 1 fix (it WOULD change the scene), yet afterwards the scene file's bytes, the
##      cards (var_to_str), scene_dict, the body state, markers, asserts, plants, the undo and redo sizes are bit-identical
##  (3) the same call not dry: it stops "bar_reached" at >= 40; its steps equal the dry plan's (rule, card, kept, score before / after);
##      the cards DID change; exactly ONE undo step was added, and `undo` brings everything in (2)'s list back bit-exact
##  (4) the GUARD: a line that passes at the start but that the first fix breaks ("<thing> speed under X m/s all clip", X halfway
##      between the thing's peak before and after that fix, picked from 6 things measured here) is saved. (4a) fix_until never keeps
##      that fix: the line is a Check finding, so the fix's predicted gain counts it (listed in no_gain below 0), and the line still
##      passes at the end. (4b) FAULT INJECTION: every Check fix's prediction is faked to +50, so the loop tries the breaking fix and only
##      the guard's measurement can stop it: at least one step is reverted, the line still passes at the end, no score goes down
##  (5) the cap: dodge_side with max_steps 1 stops "cap" after exactly 1 fix tried
##  (6) an IMPOSSIBLE line ("head at least 5 m from pelvis all clip": head and pelvis are 0.4 m apart) saved on dodge_side: the loop ends
##      within its 10 steps, not "bar_reached", passed false, and still_failing names that line with its miss ('say') and a why
##  (7) combo3 with 3 lines that pass saved, max_steps 2: stops "cap" with 2 tried; the score never goes down (each step's after >=
##      before, kept steps chain, end >= start); no step's failing lines grow; independently BodyAssert.run on the committed scene passes
##      the 3 lines; the live realism score after the commit = the report's end (0.01); one undo step; undo restores it bit-exact
## Every bar in (2)-(7): each step's score after >= before, and each step's failing lines are a subset of its before.
## Time: 237 s alone, 630 s with the PC loaded (every step predicts up to 6 fixes on copies, each a full score): SLOW budget 1500 s.
extends SceneTree

var fails := 0
var m: Node
var T: AgentTools


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func snap() -> String:
	return "\n".join([var_to_str(m.S.cards), JSON.stringify(T.scene_dict()), var_to_str(m.B.state()), var_to_str(m.S.markers),
		var_to_str(m.S.asserts), var_to_str(m.S.plants)])


func open(sn: String) -> void:
	await T.request(1, "open", {"path": "scenes/%s.json" % sn})


func fx(p: Dictionary) -> Dictionary:
	var r: Dictionary = await T.request(2, "fix_until", p)
	if r.has("error"):
		print("     error: ", JSON.stringify(r["error"]))
		return {"ok": false, "steps": [], "stopped": "error", "start": {"score": 0.0}, "end": {"score": 0.0}, "tried": -1, "kept": 0, "still_failing": []}
	return r["result"]


func sig(r: Dictionary) -> Array:
	return r["steps"].map(func(s): return [s["rule"], s["card"], s["kept"], s["before"]["score"], s["after"]["score"]])


## the per-step bars every run must hold
func monotone(r: Dictionary, tag: String) -> void:
	var good := true
	var subset := true
	var prev = null
	for s in r["steps"]:
		if float(s["after"]["score"]) < float(s["before"]["score"]):
			good = false
		if prev != null and absf(float(s["before"]["score"]) - float(prev)) > 0.005:
			good = false
		prev = s["after"]["score"]
		for l in s["after"]["failing"]:
			if not l in s["before"]["failing"]:
				subset = false
	ok(good and float(r["end"]["score"]) >= float(r["start"]["score"]), "%s: the score never goes down (%s)" % [tag, " -> ".join(r["steps"].map(func(s): return "%.2f" % s["after"]["score"]))])
	ok(subset, "%s: no step breaks a line that passed before it" % tag)


func lines_pass(lines: Array) -> bool:
	var ar := BodyAssert.run(m.S, m.B, lines)
	return ar["pass"]


## the peak speed of each thing over the clip (m/s): "speed under 0" fails everywhere and its miss is the peak
const THINGS := ["pelvis", "head", "right fist", "left fist", "right foot", "left foot"]


func peaks() -> Dictionary:
	var out := {}
	var ar := BodyAssert.run(m.S, m.B, THINGS.map(func(t): return "%s speed under 0 m/s all clip" % t))
	for i in THINGS.size():
		var x: Dictionary = ar["results"][i]
		out[THINGS[i]] = float(x["miss"]["value"]) if x.has("miss") and x["miss"]["value"] != null else 0.0
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	T = AgentTools.new(m)
	var t_all := Time.get_ticks_msec()
	# (1)
	var e1: Dictionary = await T.request(9, "fix_until", {"bar": 150})
	var e2: Dictionary = await T.request(9, "fix_until", {"max_steps": 0})
	ok(e1.has("error") and int(e1["error"]["code"]) == -32602 and e2.has("error") and int(e2["error"]["code"]) == -32602, "1 bar 150 / max_steps 0 refused with -32602")
	m.tc_ui.db = MotionMatch.build()
	# (2) dry
	await open("dodge_side")
	var bytes0 := FileAccess.get_file_as_bytes("res://scenes/dodge_side.json")
	var s0 := snap()
	var u0: int = m.undo.size()
	var rd0: int = m.redo.size()
	var t0 := Time.get_ticks_msec()
	var dry := await fx({"dry": true, "bar": 40})
	print("     dry: %s %.2f -> %.2f, %d tried, %d kept, %d ms" % [dry["stopped"], dry["start"]["score"], dry["end"]["score"], dry["tried"], dry["kept"], Time.get_ticks_msec() - t0])
	ok(int(dry["kept"]) >= 1, "2 the dry plan keeps %d fix(es): it would change the scene" % dry["kept"])
	ok(snap() == s0 and m.undo.size() == u0 and m.redo.size() == rd0 and FileAccess.get_file_as_bytes("res://scenes/dodge_side.json") == bytes0,
		"2 dry: cards, scene, body, markers, asserts, plants, undo %d / redo %d, the file: bit-identical" % [m.undo.size(), m.redo.size()])
	monotone(dry, "2 dry")
	# (3) for real
	var real := await fx({"bar": 40})
	ok(real["stopped"] == "bar_reached" and float(real["end"]["score"]) >= 40.0, "3 stops bar_reached: %s at %.2f" % [real["stopped"], real["end"]["score"]])
	ok(sig(real) == sig(dry), "3 its steps are the dry plan's: %s" % JSON.stringify(sig(real)))
	ok(snap() != s0, "3 the cards did change")
	ok(m.undo.size() == u0 + 1, "3 one undo step (%d -> %d)" % [u0, m.undo.size()])
	monotone(real, "3")
	await T.request(3, "run", {"steps": ["undo"]})
	ok(snap() == s0, "3 undo brings the scene back bit-exact")
	# (4) the guard probe: the first fix alone, then back
	var before_pk := peaks()
	var one := await fx({"max_steps": 1})
	var one_pk := peaks()
	await T.request(3, "run", {"steps": ["undo"]})
	ok(snap() == s0, "4 (its undo is bit-exact too)")
	var pick := ""
	var X := 0.0
	for t in THINGS:
		if float(one_pk[t]) > float(before_pk[t]) + 0.05:
			pick = t
			X = snappedf(0.5 * (float(one_pk[t]) + float(before_pk[t])), 0.001)
			break
	ok(pick != "" and int(one["kept"]) == 1, "4 a thing the first fix speeds up: %s %.3f -> %.3f m/s (peaks before %s, after %s)" % [pick, before_pk.get(pick, 0.0), one_pk.get(pick, 0.0), JSON.stringify(before_pk), JSON.stringify(one_pk)])
	if pick != "":
		var line := "%s speed under %s m/s all clip" % [pick, str(X)]
		await T.request(4, "assert", {"lines": [line], "save": true})
		ok(m.S.asserts == [line] and lines_pass([line]), "4 saved and passing at the start: '%s'" % line)
		var g := await fx({"bar": 40})
		var low: Array = g["no_gain"].filter(func(x): return x["predicted_gain"] != null and float(x["predicted_gain"]) < 0.0)
		ok(g["steps"].filter(func(s): return s["kept"] and s["after"]["failing"].has(line)).is_empty() and not low.is_empty(),
			"4a the fix that would break it is not kept: its predicted gain counts the broken line (%s)" % JSON.stringify(low.map(func(x): return [x["judge"], x["predicted_gain"]])))
		ok(lines_pass([line]) and not line in g["end"]["failing"], "4a the line still passes at the end (%s, %.2f)" % [g["stopped"], g["end"]["score"]])
		monotone(g, "4a")
		# 4b fault injection: every Check fix's prediction is set to +50 points, so the loop TRIES the one that breaks the line and only
		# the guard's measurement after it can stop it
		var rs: RealismUI = m.rs_ui
		rs.refresh()
		var inj := 0
		for it in rs.res["items"]:
			if String(it["fix"]["kind"]) == "check" and Fixer.label(rs.inp["findings"][int(it["fix"]["i"])], m.S) != "":
				rs.gains[rs.key + "|" + var_to_str(m.S.asserts) + "|" + String(it["text"])] = 50.0
				inj += 1
		var gb := await fx({"bar": 40})
		var rev: Array = gb["steps"].filter(func(s): return not s["kept"] and String(s.get("reverted", "")) != "")
		ok(inj > 0 and not rev.is_empty() and String(rev[0]["reverted"]).contains("broke a passing assertion"), "4b %d predictions faked; the guard reverts, naming the broken line: %s" % [inj, JSON.stringify(gb["steps"].map(func(s): return [s["rule"], s["predicted_gain"], s["kept"], s.get("reverted", "")]))])
		ok(lines_pass([line]) and not line in gb["end"]["failing"], "4b the line still passes at the end (%s)" % gb["stopped"])
		monotone(gb, "4b")
	# (5) the cap
	await open("dodge_side")
	# bar 100: dodge_side's first fix (BODY ACCEL, 1e74ee6a) now lifts 27.07 -> 77.60, over DEFAULT_BAR 70, so the default bar ends the run
	# "bar_reached" after 1 fix; 100 keeps the bar this line tests (max_steps stops it, not the score)
	var cp := await fx({"max_steps": 1, "dry": true, "bar": 100})
	ok(cp["stopped"] == "cap" and int(cp["tried"]) == 1, "5 max_steps 1: %s after %d tried" % [cp["stopped"], cp["tried"]])
	# (6) impossible
	var imp := "head at least 5 m from pelvis all clip"
	await T.request(5, "assert", {"lines": [imp]})
	m.S.asserts = [imp]
	ok(not lines_pass([imp]), "6 the line fails at the start")
	var ir := await fx({"dry": true})
	var sf: Array = ir["still_failing"].filter(func(x): return x.get("line", "") == imp)
	ok(ir["stopped"] != "bar_reached" and ir["stopped"] != "error" and not ir["passed"] and int(ir["tried"]) <= 10, "6 it ends: %s after %d tried, passed %s" % [ir["stopped"], ir["tried"], ir["passed"]])
	ok(sf.size() == 1 and String(sf[0]["why"]) != "" and String(sf[0]["say"]).contains("FAIL"), "6 still failing, with the reason: %s" % JSON.stringify(sf))
	monotone(ir, "6")
	print("     dodge_side bars: %d ms" % (Time.get_ticks_msec() - t_all))
	# (7) combo3
	await open("combo3")
	var keep := ["left foot planted 0-0.3 s", "head at least 20 cm from pelvis all clip", "right fist speed under 30 m/s all clip"]
	await T.request(6, "assert", {"lines": keep, "save": true})
	ok(m.S.asserts == keep, "7 combo3: 3 passing lines saved")
	var c0 := snap()
	var cu: int = m.undo.size()
	t0 = Time.get_ticks_msec()
	var cr := await fx({"max_steps": 2})
	print("     combo3: %s %.2f -> %.2f, %d tried, %d kept, %d ms" % [cr["stopped"], cr["start"]["score"], cr["end"]["score"], cr["tried"], cr["kept"], Time.get_ticks_msec() - t0])
	ok(cr["stopped"] == "cap" and int(cr["tried"]) == 2, "7 stops at the cap: %s, %d tried" % [cr["stopped"], cr["tried"]])
	monotone(cr, "7")
	ok(lines_pass(keep), "7 the 3 lines pass on the committed scene (BodyAssert.run)")
	m.rs_ui.refresh()
	ok(absf(float(m.rs_ui.res["score"]) - float(cr["end"]["score"])) < 0.01, "7 the live score %.2f = the report's end %.2f" % [m.rs_ui.res["score"], cr["end"]["score"]])
	ok(m.undo.size() == cu + 1 and snap() != c0, "7 one undo step, and the scene changed")
	await T.request(7, "run", {"steps": ["undo"]})
	ok(snap() == c0, "7 undo restores combo3 bit-exact")
	print("     all: %d ms" % (Time.get_ticks_msec() - t_all))
	print("FIXLOOP %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
