## KINE-BENCH RUNNER (docs/INNOVATIONS.md N024; the grader: scripts/kine_bench.gd, the tasks: bench/tasks/*.json)
##   godot --headless --path . -s tools/bench.gd -- --list
##       prints every task: id, kind, the number of machine-checkable criteria, the brief
##   godot --headless --path . -s tools/bench.gd -- --agent-log <dir> [--only id,id] [--out <file stem>] [--title text]
##       scores a folder of result scenes named by task id (<dir>/<id>.json, e.g. what an agent saved after each task, or
##       bench/solutions for the reference) and writes the run's table as markdown and JSON: <stem>.md and <stem>.json
##       (default stem <dir>/kine_bench). A task with no result file scores 0 ("no result"), it is not skipped.
## Each scene is opened on the app's own body (KineBench.open_scene: what serve `open` does, without the schema check, so a
## scene with a jump's "air" card is graded) and graded by KineBench.grade, the same call serve `bench {task, score: true}` makes,
## so this table and the serve scores are the same numbers (tests/bench_test.gd checks it). Exit 0 when it ran, 2 on bad args.
extends SceneTree


func _init() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var arg := func(k: String, d: String) -> String:
		var i := a.find(k)
		return String(a[i + 1]) if i >= 0 and i + 1 < a.size() else d
	var ts := KineBench.tasks(true)
	if "--list" in a:
		for t in ts:
			if t.has("error"):
				print("%-24s MALFORMED: %s" % [t.get("id", "?"), t["error"]])
				continue
			print("%-24s %-12s %2d criteria  %s" % [t["id"], t["kind"], KineBench.criteria(t), t["brief"]])
		print("%d tasks" % ts.size())
		quit(0)
		return
	var dir: String = arg.call("--agent-log", "")
	if dir == "":
		print("usage: -s tools/bench.gd -- --list | --agent-log <dir of <task id>.json scenes> [--only id,id] [--out <stem>] [--title text]")
		quit(2)
		return
	dir = dir.trim_suffix("/").trim_suffix("\\")
	var only: Array = []
	var o: String = arg.call("--only", "")
	if o != "":
		only = o.split(",")
	var stem: String = arg.call("--out", dir + "/kine_bench")
	var title: String = arg.call("--title", dir.get_file())
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var rows := []
	var t0 := Time.get_ticks_msec()
	for t in ts:
		if t.has("error") or (not only.is_empty() and not String(t["id"]) in only):
			continue
		var path := "%s/%s.json" % [dir, t["id"]]
		var row: Dictionary
		if not FileAccess.file_exists(path):
			row = KineBench.missing(t, "no result (%s.json is not in %s)" % [t["id"], dir])
		elif not KineBench.open_scene(m, path):
			row = KineBench.missing(t, "%s is not a scene file" % path.get_file())
		else:
			row = KineBench.grade(m, T, t)
		rows.append(row)
		print("%-24s %3d  %s" % [row["task"], int(row["score"]), "solved" if row["solved"] else ""])
	var md := KineBench.table_md(rows, title)
	var js := KineBench.table_json(rows, title)
	var f := FileAccess.open(stem + ".md", FileAccess.WRITE)
	if f != null:
		f.store_string(md)
		f.close()
	f = FileAccess.open(stem + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(js, " "))
		f.close()
	print("BENCH %d tasks, mean %.1f, %d solved, %.1f s -> %s.md / .json" % [rows.size(), float(js["mean"]), int(js["solved"]),
		(Time.get_ticks_msec() - t0) / 1000.0, stem])
	quit(0)
