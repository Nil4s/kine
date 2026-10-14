## godot --headless --path . -s tools/rules_check.gd -- [scenes/a.json ...]    (no args: every scene in scenes/ and _wip)
## The rulebook (scripts/rulebook.gd, docs/MOTION_RULES.md) over scenes: each finding with its time and card.
extends SceneTree


func _init() -> void:
	var files := Array(OS.get_cmdline_user_args())
	if files.is_empty():
		for d in ["res://scenes", "res://scenes/_wip"]:
			for f in DirAccess.get_files_at(d):
				if f.ends_with(".json"):
					files.append(d + "/" + f)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var total := {"FAIL": 0, "WARN": 0}
	for f in files:
		var d = JSON.parse_string(FileAccess.get_file_as_string(f))
		if not d is Dictionary or not d.has("cards"):
			continue
		var S := Scene.new()
		S.from_dict(d)
		if S.name == "" or S.name == "scene":
			S.name = String(f).get_file().get_basename()
		var fs := Rulebook.check(S, B)
		print("%s: %s" % [String(f).get_file(), "clean" if fs.is_empty() else "%d finding(s)" % fs.size()])
		for x in fs:
			total[x["sev"]] += 1
			print("  %s %5.2f s  card %2d '%s'  %-13s %s" % [x["sev"], x["t"], x["card"] + 1, S.cards[x["card"]]["name"], x["rule"], x["msg"]])
	print("RULES: %d FAIL, %d WARN" % [total["FAIL"], total["WARN"]])
	quit()
