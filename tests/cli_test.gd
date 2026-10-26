## godot --headless --path . -s tests/cli_test.gd     (GATES O5)
## tools/poser_cli.gd run as an agent would: a separate Godot process per call, the LAST output line parsed as JSON.
## Each verb answers with "ok"; a run edits what it says it did and writes only its --out file; the refusals refuse
## and write nothing; Nick's combo3.json is byte-identical after all of it.
extends SceneTree

const OUT := "res://scenes/_wip/cli_test.json"

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## run the CLI; returns [the parsed last JSON line (or {}), every output line]
func cli(args: Array) -> Array:
	var out := []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/poser_cli.gd", "--"] + args, out, true)
	var lines := Array("".join(out).split("\n", false))
	var d = null
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with("{"):
			d = JSON.parse_string(lines[i])
			break
	return [d if d is Dictionary else {}, lines]


func _init() -> void:
	var nick := FileAccess.get_md5("res://scenes/combo3.json")
	if FileAccess.file_exists(OUT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT))
	var M = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(M)
	await process_frame
	var ids: Array = (M._commands() as Array).map(func(c): return c["id"])

	var r := cli(["commands"])
	var cs: Array = r[0].get("commands", [])
	ok(r[0].get("ok", false) and cs.map(func(c): return c["id"]) == ids, "commands: ok, the registry's %d ids in order" % cs.size())
	ok(cs.all(func(c): return c.has("desc") and c.has("edits") and c.has("keys")), "commands: each has keys, edits, desc")

	r = cli(["describe", "scenes/combo3.json"])
	var d: Dictionary = r[0]
	M._load_scene("res://scenes/combo3.json")
	var L: float = snappedf(M.S.length(), 0.001)
	ok(d.get("ok", false) and d.get("cards", []).size() == 12 and is_equal_approx(d.get("length_s", 0.0), L), "describe combo3: 12 cards, %.3f s (the poser's own length: %.3f)" % [d.get("length_s", 0.0), L])
	ok(r[1].any(func(l): return l.begins_with("  card 10 Nick STRIKE")), "describe: readable card lines above the JSON")

	r = cli(["check", "scenes/combo3.json", "--json"])
	var c: Dictionary = r[0]
	var plain := (r[1] as Array).filter(func(l): return not l.begins_with("Godot") and not l.begins_with("Vulkan") and l.strip_edges() != "")
	ok(c.get("ok", false) and plain.size() == 1, "check --json: ONLY the JSON line (%d lines)" % plain.size())
	ok(c.get("findings", []).size() == d.get("findings", -1) and c.get("must_fix", -1) == d.get("must_fix", -2), "check agrees with describe: %d findings, %d must fix" % [c.get("findings", []).size(), c.get("must_fix", -1)])
	var f0: Dictionary = c["findings"][0] if c.get("findings", []).size() > 0 else {}
	ok(["n", "sev", "rule", "t", "card", "card_name", "msg", "fix"].all(func(k): return f0.has(k)), "check: a finding has n, sev, rule, t, card, card_name, msg, fix")

	r = cli(["run", "scenes/combo3.json", "card=3", "sel=lowerarm_r", "set=lowerarm_r:90,0,0", "update", "--out", "scenes/_wip/cli_test.json"])
	d = r[0]
	var st: Array = d.get("steps", [])
	ok(d.get("ok", false) and st.size() == 4 and d.get("out", "") == OUT, "run: 4 steps ok, out = %s" % d.get("out", ""))
	ok(st.size() == 4 and st[2]["body_changed"] and not st[2]["cards_changed"] and st[2]["undo_steps"] == 1 and st[3]["cards_changed"], "run: set changed the body (1 undo step), update changed the cards")
	var w = JSON.parse_string(FileAccess.get_file_as_string(OUT)) if FileAccess.file_exists(OUT) else {}
	var bend := float(w["cards"][2]["pose"]["joints"]["lowerarm_r"]["bend"]) if w is Dictionary and w.has("cards") else -1.0
	var bend0 := float(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))["cards"][2]["pose"]["joints"]["lowerarm_r"]["bend"])
	ok(is_equal_approx(bend, 90.0) and not is_equal_approx(bend0, 90.0), "the written file: card 3's right elbow bend %.2f (was %.2f in combo3)" % [bend, bend0])
	ok(w is Dictionary and w.get("cards", []).size() == 12 and String(w.get("scene", "")) == "cli_test", "the written file: 12 cards, named cli_test")

	r = cli(["run", "scenes/combo3.json", "faster_10", "undo", "--json"])
	st = r[0].get("steps", [])
	ok(r[0].get("ok", false) and st.size() == 2 and st[0]["cards_changed"] and st[1]["cards_changed"] and not r[0].has("out"), "run without --out: faster_10 then undo, nothing written")

	for bad in [[["run", "scenes/combo3.json", "faster_10", "--out", "scenes/combo3_cli.json"], "--out into scenes/ (not _wip)", "scenes/combo3_cli.json"],
			[["run", "scenes/combo3.json", "faster_10", "--out", "poses/cli.json"], "--out into poses/", "poses/cli.json"],
			[["run", "scenes/combo3.json", "save_scene"], "save_scene (writes scenes/)", ""],
			[["run", "scenes/combo3.json", "fly_away"], "an unknown step", ""],
			[["run", "scenes/combo3.json", "card=99"], "card=99 (12 cards)", ""],
			[["run", "scenes/combo3.json", "set=lowerarm_r:90"], "a malformed set=", ""],
			[["describe", "scenes/nope.json"], "a missing scene", ""],
			[["dance"], "an unknown verb", ""]]:
		r = cli(bad[0])
		var err := String(r[0].get("error", ""))
		for s in r[0].get("steps", []):
			if s.has("error"):
				err = s["error"]
		ok(r[0].has("ok") and not r[0]["ok"] and err != "" and (bad[2] == "" or not FileAccess.file_exists("res://" + bad[2])), "refused: %s -> \"%s\"" % [bad[1], err])

	r = cli(["run", "scenes/combo3.json", "fix=1", "--json"])
	st = r[0].get("steps", [])
	ok(r[0].get("ok", false) and st.size() == 1 and st[0]["cards_changed"] and st[0]["undo_steps"] == 1, "run fix=1: the first finding's Fix changed the cards, one undo step (%s)" % (st[0]["said"].left(90) if st.size() > 0 else "-"))

	ok(FileAccess.get_md5("res://scenes/combo3.json") == nick, "Nick's combo3.json byte-identical after every call")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT))
	print("CLI TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
