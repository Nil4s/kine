## godot --headless --path . -s tests/tryn_test.gd     (N019 TRY N WAYS; scripts/try_n.gd)
## BARS, written before measuring:
##   1 RANKED TRUE: `try` sweeps retime card 3 of combo3 at 80 / 90 / 100 / 110 / 120 % (scored). Each variant is then run
##     for REAL from a freshly opened combo3 and read cold (DryRun.cold_score + Check). Bar: try's order is the order the
##     real numbers give under the same rule (TryN.better), and every variant's try score equals its real score within
##     0.1 (N003's dry-vs-real bar), its Check count exactly.
##   2 UNTOUCHED: around a `try` without apply, the scene file's JSON bytes (DryRun._file), var_to_str(B.state()) and the
##     undo / redo sizes are identical, and try says restored. Bar: all identical.
##   3 APPLY: `try` (score false) with apply "best" gives the same scene JSON and B.state() as running that variant's
##     steps directly on a freshly opened combo3; the undo list grew by exactly 1, and ONE undo gives the start's scene
##     JSON back byte for byte. Bar: all three. (Also apply: 2 by number, the same check.) Two variants: mirror + update, and retime card 3 to 70 %.
##   4 FAILED: variants [retime 90], [card=99], [retime 110], [save_scene]: 2 under "failed" each with its reason, the
##     other 2 ranked. Bar: exactly that, and the scene untouched as in 2.
##   5 SERVE + CLI: serve's `try` with no variants answers -32602; `poser_cli try combo3 retime=3-3:{pct} --sweep
##     pct=90,110 --no-score --json` exits 0 with 2 ranked; scenes/combo3.json's md5 is the same at the end.
extends SceneTree

var fails := 0
var m: Node
var T: AgentTools

const SCENE := "scenes/combo3.json"
const PCTS := [80, 90, 100, 110, 120]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fresh() -> void:
	await T.request(1, "open", {"path": SCENE})


func now() -> Dictionary:
	return {"scene": JSON.stringify(DryRun._file(m)), "body": var_to_str(m.B.state()), "undo": m.undo.size(), "redo": m.redo.size()}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	T = AgentTools.new(m)
	var md0 := FileAccess.get_md5("res://" + SCENE)

	# 1 + 2
	await fresh()
	var w0 := now()
	var t0 := Time.get_ticks_msec()
	var tr: Dictionary = await T.request(2, "try", {"base": ["retime=3-3:{pct}"], "sweep": {"param": "pct", "values": PCTS}})
	var ms := Time.get_ticks_msec() - t0
	var w1 := now()
	var r: Dictionary = tr.get("result", {})
	ok(w0 == w1 and bool(r.get("restored", false)), "2 untouched: scene JSON %s, body %s, undo %d->%d, redo %d->%d, restored %s" % [
		w0["scene"] == w1["scene"], w0["body"] == w1["body"], w0["undo"], w1["undo"], w0["redo"], w1["redo"], r.get("restored")])
	for l in TryN.lines(r):
		print("     ", l)
	print("     try took %d ms for %d scored variants" % [ms, PCTS.size()])
	var real := []
	for i in PCTS.size():
		await fresh()
		var st: Dictionary = await T.step("retime=3-3:%d" % PCTS[i])
		var fs := T.findings()
		real.append({"variant": i + 1, "score": DryRun.cold_score(m), "asserts": null, "findings": fs.size(),
			"must_fix": fs.filter(func(f): return f["sev"] == "MUST FIX").size(), "ok": st["ok"]})
	var real_sorted := real.duplicate()
	real_sorted.sort_custom(TryN.better)
	var order_try: Array = r.get("ranked", []).map(func(x): return x["variant"])
	var order_real: Array = real_sorted.map(func(x): return x["variant"])
	var worst := 0.0
	var fmatch := true
	for x in r.get("ranked", []):
		var y: Dictionary = real[int(x["variant"]) - 1]
		worst = maxf(worst, absf(float(x["score"]) - float(y["score"])))
		fmatch = fmatch and int(x["findings"]) == int(y["findings"])
	ok(order_try == order_real and order_try.size() == PCTS.size() and worst <= 0.1 and fmatch, "1 ranked true: try %s, real %s; worst score gap %.3f; Check counts equal %s (real: %s)" % [
		order_try, order_real, worst, fmatch, ", ".join(real.map(func(y): return "%d%%=%.2f/%d" % [PCTS[y["variant"] - 1], float(y["score"]), y["findings"]]))])

	# 3
	for ap in ["best", 2]:
		await fresh()
		var s0 := now()
		var ar: Dictionary = await T.request(3, "try", {"variants": [["retime=3-3:70"], ["card=2", "mirror_the_whole_pose", "update"]], "score": false, "apply": ap})
		var res: Dictionary = ar.get("result", {})
		var applied := now()
		var u_after: int = m.undo.size()
		m._undo()
		var back := now()
		var want: int = int(res.get("best", -1)) if ap is String else int(ap)
		var steps: Array = []
		for x in res.get("ranked", []):
			if int(x["variant"]) == want:
				steps = x["steps"]
		await fresh()
		for s in steps:
			await T.step(s)
		var direct := now()
		ok(res.get("applied", {}).get("ok", false) and applied["scene"] == direct["scene"] and applied["body"] == direct["body"] and u_after == s0["undo"] + 1 and back["scene"] == s0["scene"],
			"3 apply %s (variant %d, %s): same scene as direct %s, same body %s; undo %d -> %d; one undo gives the start scene %s (body %s)" % [
			ap, want, " ".join(steps), applied["scene"] == direct["scene"], applied["body"] == direct["body"], s0["undo"], u_after, back["scene"] == s0["scene"], back["body"] == s0["body"]])

	# 4
	await fresh()
	var w4 := now()
	var br: Dictionary = (await T.request(4, "try", {"variants": [["retime=3-3:90"], ["card=99"], ["retime=3-3:110"], ["save_scene"]], "score": false})).get("result", {})
	var failed: Array = br.get("failed", [])
	ok(failed.map(func(x): return x["variant"]) == [2, 4] and failed.all(func(x): return String(x["error"]) != "") and br.get("ranked", []).size() == 2 and now() == w4,
		"4 failed: %s; ranked %s; untouched %s" % [failed.map(func(x): return "%d: %s" % [x["variant"], String(x["error"]).left(70)]), br.get("ranked", []).map(func(x): return x["variant"]), now() == w4])

	# 5
	var se: Dictionary = await T.request(5, "try", {})
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/poser_cli.gd", "--",
		"try", SCENE, "retime=3-3:{pct}", "--sweep", "pct=90,110", "--no-score", "--json"], out, true)
	var last := ""
	for l in String("".join(out)).split("\n"):
		if l.begins_with("{\"") and l.contains("\"ranked\""):
			last = l
	var cj: Variant = JSON.parse_string(last) if last != "" else null
	var md1 := FileAccess.get_md5("res://" + SCENE)
	ok(se.has("error") and int(se["error"]["code"]) == -32602 and code == 0 and cj is Dictionary and (cj["ranked"] as Array).size() == 2 and md0 == md1,
		"5 serve error %s; CLI exit %d, ranked %s; combo3.json unchanged %s" % [se.get("error", {}).get("code"), code,
		(cj["ranked"] as Array).map(func(x): return x["steps"]) if cj is Dictionary else null, md0 == md1])

	print("TRYN: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)
