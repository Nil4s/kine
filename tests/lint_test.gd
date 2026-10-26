## godot --headless --path . -s tests/lint_test.gd     (docs/INNOVATIONS.md N018: lint any clip; scripts/clip_lint.gd)
## BARS (stated before measuring):
##   1 CLEAN: scenes/idle_bat.json written by Kine's own BvhExport, linted: ok, 22 of 22 main joints mapped by Kine's names,
##     NO must-fix finding.
##   2 BROKEN BVH: the clean clip (the file's own frames, one card each) with the right elbow hyperextended 40 deg on frames
##     10-20 and the body pushed 8 cm along the floor over frames 40-60 while both feet stand (so a planted foot slides 8 cm),
##     written by the same exporter (the elbow's range is widened only while writing, so the file really holds -40 deg).
##     Lint finds BOTH: a JOINT RANGE on lowerarm_r over frames 10-20 (+-1) at 40 deg past the range (+-10 %) as a must-fix,
##     and a foot slide over frames 40-60 (+-1) of 8 cm (+-10 %).
##   3 GLB: the same clean and broken clips through Kine's .glb export (another reader: AnimImport's retarget): clean = no
##     must-fix, broken = the same two findings within the same bars; the mapping says which joints came by name.
##   4 MALFORMED: a cut BVH, a .glb of garbage, an FBX of garbage, a missing file, a .txt: each {"ok": false, "error": ...},
##     no crash; through the CLI (a file outside the project) the last line is that JSON and the exit code is 1.
##   5 TIME: a 10 s clip (idle_bat's frames repeated, 301 frames at 30 fps) is linted in under 10 s (the lint itself, "ms"; the
##     CLI's own start, loading the poser, is not the lint's and is printed apart).
##   6 SERVE: AgentTools.request("lint", {path}) gives the same findings as ClipLint.lint, a missing path is a -32602 error, and
##     the live scene is untouched by a lint.
##   7 CLI on the broken .glb outside the project: one JSON line {ok, file, fps, frames, mapped, findings, score}, both found.
extends SceneTree

var fails := 0
var DIR := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func near(a: float, b: float, rel: float) -> bool:
	return absf(a - b) <= absf(b) * rel


func must(r: Dictionary) -> Array:
	return (r.get("findings", []) as Array).filter(func(f): return f["sev"] == "must fix")


func range_find(r: Dictionary) -> Dictionary:
	for f in r.get("findings", []):
		if f["rule"] == "JOINT RANGE" and f["joint"] == "lowerarm_r" and f["axis"] == "bend":
			return f
	return {}


func slide_find(r: Dictionary) -> Dictionary:
	var best := {}
	for f in r.get("findings", []):
		if (f["rule"] == "FOOT SLIDE" or f["rule"] == "FEASIBLE SLIDE") and (best.is_empty() or float(f["value"]) > float(best["value"])):
			best = f
	return best


func broken_bars(label: String, r: Dictionary) -> void:
	var e := range_find(r)
	ok(not e.is_empty() and absi(int(e["frames"][0]) - 10) <= 1 and absi(int(e["frames"][1]) - 20) <= 1 and near(float(e["value"]), 40.0, 0.1) and e["sev"] == "must fix",
		"%s: elbow found: %s" % [label, "none" if e.is_empty() else "frames %s, %.1f %s (bar %s), %s; %s" % [e["frames"], e["value"], e["unit"], e["bar"], e["sev"], e["msg"]]])
	var s := slide_find(r)
	ok(not s.is_empty() and absi(int(s["frames"][0]) - 40) <= 1 and absi(int(s["frames"][1]) - 60) <= 1 and near(float(s["value"]), 8.0, 0.1),
		"%s: foot slide found: %s" % [label, "none" if s.is_empty() else "%s %s foot, frames %s (planted %s), %.2f %s (bar %s)" % [s["rule"], s["foot"], s["frames"], s["planted"], s["value"], s["unit"], s["bar"]]])
	var other := must(r).filter(func(f): return f != e and f["rule"] != "FEASIBLE" and f["rule"] != "FEASIBLE SLIDE")
	print("     other must-fix: %s" % [other.map(func(f): return "%s %s %s" % [f["rule"], f["frames"], f["msg"].left(90)])])


func cli(args: Array) -> Array:
	var out := []
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/poser_cli.gd", "--"] + args, out, true)
	var last := {}
	for l in String("".join(out)).split("\n"):
		if l.strip_edges().begins_with("{"):
			var j = JSON.parse_string(l.strip_edges())
			if j is Dictionary:
				last = j
	return [code, last, Time.get_ticks_msec() - t0]


func _init() -> void:
	DIR = OS.get_user_data_dir().path_join("zz_lint")   # outside the project
	DirAccess.make_dir_recursive_absolute(DIR)
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	m._load_scene("res://scenes/idle_bat.json")
	m._rebuild_cards()
	var clean := DIR.path_join("clean.bvh")
	BvhExport.write(m.S, B, clean)
	# 1
	var r1 := ClipLint.lint(m, clean)
	for l in ClipLint.lines(r1):
		print("     " + l)
	ok(r1["ok"] and r1["mapped"]["main"] == 22 and r1["mapped"]["quality"] == "exact", "1 clean bvh read: %s frames at %s fps, %s/22 main joints (%s)" % [r1.get("frames"), r1.get("fps"), r1.get("mapped", {}).get("main"), r1.get("mapped", {}).get("quality")])
	ok(r1["ok"] and must(r1).is_empty(), "1 clean bvh: no must-fix (%d findings, score %s)" % [(r1.get("findings", []) as Array).size(), r1.get("score")])
	# 2 the broken copy, from the file's own frames
	var D: Scene = BvhImport.to_scene(BvhImport.load_file(clean), B, 1, 1.0, "idle_broken")["scene"]
	for f in D.cards.size():
		var ps: Dictionary = D.cards[f]["pose"]
		if f >= 10 and f <= 20:
			ps["joints"]["lowerarm_r"] = {"bend": -40.0, "side": 0.0, "twist": 0.0}
		var o: Array = ps["offset"]
		ps["offset"] = [float(o[0]) + 0.08 * clampf((f - 40) / 20.0, 0.0, 1.0), o[1], o[2]]
	var keep_lim: Vector2 = B.lim["lowerarm_r"]["bend"]
	B.lim["lowerarm_r"]["bend"] = Vector2(-60.0, keep_lim.y)   # only while writing: the FILE holds the hyperextension
	var broken := DIR.path_join("broken.bvh")
	var broken_glb := DIR.path_join("broken.glb")
	BvhExport.write(D, B, broken)
	var ge := GltfExport.write(D, B, broken_glb)
	B.lim["lowerarm_r"]["bend"] = keep_lim
	var clean_glb := DIR.path_join("clean.glb")
	m._load_scene("res://scenes/idle_bat.json")
	m._rebuild_cards()
	var ge2 := GltfExport.write(m.S, B, clean_glb)
	ok(ge == OK and ge2 == OK, "2 the broken copies written (bvh, glb %s, clean glb %s)" % [error_string(ge), error_string(ge2)])
	var r2 := ClipLint.lint(m, broken)
	for l in ClipLint.lines(r2):
		print("     " + l)
	broken_bars("2 broken bvh", r2)
	# 3
	var r3c := ClipLint.lint(m, clean_glb)
	ok(r3c["ok"] and must(r3c).is_empty(), "3 clean glb: no must-fix (%d findings, score %s; mapping %s, %s/22, by name %d, guessed %s)" % [(r3c.get("findings", []) as Array).size(),
		r3c.get("score"), r3c.get("mapped", {}).get("quality"), r3c.get("mapped", {}).get("main"), (r3c.get("mapped", {}).get("by_name", []) as Array).size(), r3c.get("mapped", {}).get("guessed")])
	if not must(r3c).is_empty():
		for l in ClipLint.lines(r3c):
			print("     " + l)
	var r3 := ClipLint.lint(m, broken_glb)
	for l in ClipLint.lines(r3):
		print("     " + l)
	ok(r3["ok"] and r3["format"] == "glb" and r3["how"] == "retarget", "3 broken glb read through the retarget: %s" % r3.get("mapped", {}).get("how", r3.get("error", "")))
	broken_bars("3 broken glb", r3)
	# 5 a 10 s clip
	var D10: Scene = BvhImport.to_scene(BvhImport.load_file(clean), B, 1, 1.0, "idle10")["scene"]
	var base: Array = D10.cards.duplicate(true)
	while D10.cards.size() < 301:
		var c: Dictionary = base[(D10.cards.size()) % base.size()].duplicate(true)
		c["name"] = "f%d" % D10.cards.size()
		c["move"] = 1.0 / D10.fps
		D10.cards.append(c)
	var ten := DIR.path_join("ten.bvh")
	BvhExport.write(D10, B, ten)
	var r5 := ClipLint.lint(m, ten)
	ok(r5["ok"] and absf(float(r5["length_s"]) - 10.0) < 0.05 and int(r5["ms"]) < 10000, "5 a %s s clip (%s frames) linted in %s ms (bar 10000; %d findings, score %s)" % [r5.get("length_s"), r5.get("frames"), r5.get("ms"), (r5.get("findings", []) as Array).size(), r5.get("score")])
	# 4
	var bad := {"cut.bvh": "HIERARCHY\nROOT pelvis\n{\n\tOFFSET 0 0", "junk.glb": "glTF" + "x".repeat(300), "junk.fbx": "Kaydara FBX Binary  0001" + "y".repeat(300),
		"notes.txt": "hello", "empty.bvh": ""}
	for f in bad:
		var fa := FileAccess.open(DIR.path_join(f), FileAccess.WRITE)
		fa.store_string(bad[f])
		fa.close()
	var errs := []
	var all_clean := true
	for f in bad.keys() + ["nope.bvh"]:
		var r := ClipLint.lint(m, DIR.path_join(f))
		all_clean = all_clean and not r["ok"] and String(r.get("error", "")) != "" and r.has("file")
		errs.append("%s: %s" % [f, r.get("error", "NO ERROR")])
	ok(all_clean, "4 malformed files give an error, no crash:\n       " + "\n       ".join(PackedStringArray(errs)))
	# the two CLI runs (each starts a whole poser, ~20 s) run in threads while the rest goes on; joined below
	var th4 := Thread.new()
	th4.start(cli.bind(["lint", DIR.path_join("junk.glb"), "--json"]))
	var th7 := Thread.new()
	th7.start(cli.bind(["lint", broken_glb, "--json"]))
	# 6
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var cards0 := JSON.stringify(m.S.cards)
	var name0: String = m.S.name
	var A := AgentTools.new(m)
	var q: Dictionary = await A.request(7, "lint", {"path": broken})
	var same: bool = q.has("result") and JSON.stringify(q["result"]["findings"]) == JSON.stringify(r2["findings"])
	var qe: Dictionary = await A.request(8, "lint", {})
	ok(same and qe.has("error") and int(qe["error"]["code"]) == -32602 and JSON.stringify(m.S.cards) == cards0 and m.S.name == name0,
		"6 serve lint: same findings %s, no path -> %s, live scene untouched (%s)" % [same, JSON.stringify(qe.get("error", {})).left(140), m.S.name])
	var c4: Array = th4.wait_to_finish()
	ok(c4[0] == 1 and c4[1].get("ok") == false and String(c4[1].get("error", "")) != "", "4 CLI on a malformed .glb outside the project: exit %d, %s (%d ms with the poser's start)" % [c4[0], JSON.stringify(c4[1]), c4[2]])
	# 7
	var c7: Array = th7.wait_to_finish()
	var j7: Dictionary = c7[1]
	var keys := ["ok", "file", "fps", "frames", "mapped", "findings", "score"]
	ok(c7[0] == 0 and keys.all(func(k): return j7.has(k)) and j7.get("ok") == true, "7 CLI JSON line has %s (exit %d, %d ms with the poser's start, lint %s ms)" % [keys, c7[0], c7[2], j7.get("ms")])
	if j7.get("ok", false):
		broken_bars("7 CLI broken glb", j7)
	for f in ["clean.bvh", "broken.bvh", "broken.glb", "clean.glb", "ten.bvh", "nope.bvh"] + bad.keys():
		DirAccess.remove_absolute(DIR.path_join(f))
	print("LINT %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)
