## godot --headless --path . -s tests/bench_test.gd     (N024 KINE-BENCH: scripts/kine_bench.gd, tools/bench.gd, bench/)
## BARS, written before measuring:
##  (1) bench/tasks holds 20 tasks, none malformed, every kind (strike, kick, weapon, fall, walk, combo, two-fighter) at least
##      twice; every task has >= 2 machine-checkable criteria (assertion lines that BodyAssert reads + judge bars), its start
##      scene and its reference solution (bench/solutions/<id>.json) exist
##  (2) serve `bench {list: true}` lists the 20; `bench {task}` gives brief, start, the rules and no solution path; an unknown
##      task is a -32602 error that says what to send
##  (3) every reference solution, opened and graded through serve `bench {task, score: true}`, scores >= 80
##  (4) every start scene, graded the same way, scores < 30 (the empty move does not pass the task)
##  (5) the runner (tools/bench.gd --agent-log bench/solutions, a SEPARATE Godot process) writes a .md and a .json table whose
##      per-task score, exact score, solved flag and every line's pass are IDENTICAL to (3): the table matches serve, and two
##      runs in two processes grade the same (deterministic); a missing result file is a 0 row, not a skipped task
##  (6) the whole suite runs in under 400 s on this PC
extends SceneTree

const SOL := "res://bench/solutions/"
const START := "res://bench/start/"
const N_TASKS := 20
const MIN_SOLVED := 80
const MAX_START := 30
const BUDGET_S := 400.0

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)

	# (1) the tasks
	var ts := KineBench.tasks(true)
	ok(ts.size() == N_TASKS, "%d tasks in bench/tasks (want %d)" % [ts.size(), N_TASKS])
	var bad := ts.filter(func(t): return t.has("error"))
	ok(bad.is_empty(), "no malformed task (%s)" % str(bad.map(func(t): return "%s: %s" % [t.get("id", "?"), t["error"]])))
	var kinds := {}
	for t in ts:
		if t.has("error"):
			continue
		kinds[t["kind"]] = int(kinds.get(t["kind"], 0)) + 1
		var n := KineBench.criteria(t)
		var st := "res://" + String(t["start"])
		ok(n >= 2 and FileAccess.file_exists(st) and FileAccess.file_exists(SOL + String(t["id"]) + ".json"),
			"%s (%s): %d criteria, start %s, solution %s" % [t["id"], t["kind"], n, "found" if FileAccess.file_exists(st) else "MISSING",
			"found" if FileAccess.file_exists(SOL + String(t["id"]) + ".json") else "MISSING"])
	for k in KineBench.KINDS:
		ok(int(kinds.get(k, 0)) >= 2, "kind %s: %d tasks (2+)" % [k, int(kinds.get(k, 0))])

	# (2) serve
	var r: Dictionary = await T.request(1, "bench", {"list": true})
	ok(r.has("result") and (r["result"]["tasks"] as Array).size() == N_TASKS, "serve bench {list} lists %d tasks" % (r["result"]["tasks"] as Array).size() if r.has("result") else -1)
	r = await T.request(2, "bench", {"task": "strike_cross_chin"})
	var c: Dictionary = r.get("result", {})
	ok(c.get("brief", "") != "" and c.get("start", "") == "bench/start/strike_cross_chin.json" and (c.get("asserts", []) as Array).size() >= 2
		and not JSON.stringify(c).contains("solutions"), "serve bench {task} gives the brief, start, %d asserts, %d bars, no solution path"
		% [(c.get("asserts", []) as Array).size(), (c.get("judges", []) as Array).size()])
	r = await T.request(3, "bench", {"task": "no_such_task"})
	ok(r.has("error") and int(r["error"]["code"]) == -32602 and String(r["error"]["message"]).contains("list"), "an unknown task: %s" % str(r.get("error", r)))

	# (3) + (4) every reference and every start, graded through serve on the opened scene
	var served := {}
	for t in ts:
		if t.has("error"):
			continue
		var id := String(t["id"])
		KineBench.open_scene(m, SOL + id + ".json")
		var g: Dictionary = (await T.request(10, "bench", {"task": id, "score": true})).get("result", {})
		served[id] = g
		ok(int(g.get("score", -1)) >= MIN_SOLVED, "reference %s scores %d (>= %d)%s" % [id, int(g.get("score", -1)), MIN_SOLVED,
			"" if bool(g.get("solved", false)) else ": " + "; ".join((g.get("lines", []) + g.get("bars", [])).filter(func(x): return not x["pass"]).map(func(x): return x["say"]))])
		KineBench.open_scene(m, "res://" + String(t["start"]))
		var g0: Dictionary = (await T.request(11, "bench", {"task": id, "score": true})).get("result", {})
		ok(int(g0.get("score", 99)) < MAX_START, "start %s scores %d (< %d)" % [id, int(g0.get("score", 99)), MAX_START])

	# (5) the runner, a separate process, on the reference folder (plus one task with no result: a folder without it)
	var stem := ProjectSettings.globalize_path("user://bench_test_run")
	var out := []
	var t1 := Time.get_ticks_msec()
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/bench.gd", "--",
		"--agent-log", ProjectSettings.globalize_path(SOL).trim_suffix("/"), "--out", stem, "--title", "reference"], out, true)
	print("   runner: %.1f s; %s" % [(Time.get_ticks_msec() - t1) / 1000.0, String("".join(out)).strip_edges().get_slice("\n", String("".join(out)).strip_edges().get_slice_count("\n") - 1)])
	var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(stem + ".json"))
	ok(js is Dictionary and FileAccess.file_exists(stem + ".md") and int(js.get("tasks", 0)) == N_TASKS, "the runner wrote %s.md and .json, %d rows" % [stem, int(js.get("tasks", 0)) if js is Dictionary else -1])
	var same := 0
	var diffs := []
	if js is Dictionary:
		for row in js["rows"]:
			var g: Dictionary = served.get(row["task"], {})
			var a := [int(row["score"]), float(row["score_exact"]), bool(row["solved"]), (row["lines"] as Array).map(func(l): return bool(l["pass"])),
				(row["bars"] as Array).map(func(b): return bool(b["pass"]))]
			var b := [int(g.get("score", -1)), float(g.get("score_exact", -1.0)), bool(g.get("solved", false)), (g.get("lines", []) as Array).map(func(l): return bool(l["pass"])),
				(g.get("bars", []) as Array).map(func(x): return bool(x["pass"]))]
			if str(a) == str(b):
				same += 1
			else:
				diffs.append("%s runner %s serve %s" % [row["task"], str(a), str(b)])
	ok(same == N_TASKS, "the runner's table matches serve on %d / %d tasks (score, exact score, solved, every line and bar) %s" % [same, N_TASKS, str(diffs)])
	var empty := ProjectSettings.globalize_path("user://bench_test_empty")
	DirAccess.make_dir_recursive_absolute(empty)
	out = []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/bench.gd", "--",
		"--agent-log", empty, "--only", "strike_jab_chin", "--out", empty + "/t"], out, true)
	var je: Variant = JSON.parse_string(FileAccess.get_file_as_string(empty + "/t.json"))
	ok(je is Dictionary and int(je["tasks"]) == 1 and int(je["rows"][0]["score"]) == 0 and String(je["rows"][0]["lines"][0]["say"]).contains("no result"),
		"a missing result file is a 0 row: %s" % (String(je["rows"][0]["lines"][0]["say"]) if je is Dictionary else "no table"))

	# (6) time
	var el := (Time.get_ticks_msec() - t0) / 1000.0
	ok(el < BUDGET_S, "the suite took %.1f s (< %.0f)" % [el, BUDGET_S])
	print("%d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
