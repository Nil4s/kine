## godot --headless --path . -s tests/diff_test.gd     (GATES T2)
## DIFF: a scene against itself is the same; ONE joint moved 12 deg on ONE card is exactly that one difference, with the
## number; a hold change and a deleted card are named (and the cards after the deleted one are NOT reported); a rename
## is a rename; a mirrored scene differs on both sides' joints.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var a: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	var d := SceneDiff.diff(a, a.duplicate(true))
	ok(d["same"] and SceneDiff.lines(d)[0].begins_with("SAME"), "combo3 against itself: the same")
	var b := a.duplicate(true)
	b["cards"][3]["pose"]["joints"]["lowerarm_r"]["bend"] = float(b["cards"][3]["pose"]["joints"]["lowerarm_r"]["bend"]) + 12.0
	d = SceneDiff.diff(a, b)
	ok(not d["same"] and d["cards"].size() == 1 and d["cards"][0]["b"] == 4 and d["cards"][0]["joints"].size() == 1
		and d["cards"][0]["joints"][0]["joint"] == "lowerarm_r" and is_equal_approx(d["cards"][0]["joints"][0]["d"][0], 12.0)
		and d["settings"].is_empty() and d["added"].is_empty() and d["removed"].is_empty(),
		"one joint +12 deg on card 4: exactly that: %s" % [SceneDiff.lines(d)])
	b = a.duplicate(true)
	b["cards"][1]["hold"] = 0.55
	b["cards"].remove_at(2)
	d = SceneDiff.diff(a, b)
	var removed_name: String = a["cards"][2]["name"]
	ok(d["removed"].size() == 1 and d["removed"][0]["name"] == removed_name and d["cards"].size() == 1 and d["cards"][0].has("timing")
		and d["cards"][0]["timing"].keys() == ["hold"] and d["added"].is_empty(),
		"hold changed on card 2 + card 3 deleted: both named, nothing after it reported: %s" % [SceneDiff.lines(d)])
	b = a.duplicate(true)
	b["cards"][0]["name"] = "ready, renamed"
	b["fps"] = 60
	d = SceneDiff.diff(a, b)
	ok(d["renamed"].size() == 1 and d["renamed"][0]["to"] == "ready, renamed" and d["removed"].is_empty() and d["added"].is_empty()
		and d["settings"].size() == 1 and d["settings"][0]["key"] == "fps", "a rename and an fps change: %s" % [SceneDiff.lines(d)])
	# mirrored: every _l joint's values go to _r and back (side and twist flip sign)
	b = a.duplicate(true)
	for c in b["cards"]:
		var J: Dictionary = c["pose"]["joints"]
		var M := {}
		for j: String in J:
			var o := j.substr(0, j.length() - 2) + ("_r" if j.ends_with("_l") else "_l") if (j.ends_with("_l") or j.ends_with("_r")) else j
			M[o] = {"bend": J[j]["bend"], "side": -float(J[j]["side"]), "twist": -float(J[j]["twist"])}
		c["pose"]["joints"] = M
	d = SceneDiff.diff(a, b)
	var sides := {}
	for c in d["cards"]:
		for jd in c.get("joints", []):
			sides[jd["joint"].right(2)] = true
	ok(d["cards"].size() >= a["cards"].size() - 1 and sides.has("_l") and sides.has("_r"), "mirrored: %d of %d cards differ, on both sides' joints" % [d["cards"].size(), a["cards"].size()])
	print("DIFF TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
