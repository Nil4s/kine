## godot --headless --path . -s tests/flip_survey.gd      (GATES L1: the "gimbal flip" complaint, measured)
## Every scene at 60 fps: each joint's turn from one frame to the next (the angle between its rotations A), worst per
## scene. A gimbal flip is a joint spinning round in a frame or two; the fastest joint turn on record is the pitcher's
## shoulder's internal rotation, 4765.7 +- 771.9 deg/s in adult pitchers (Campbell, "Biomechanics of pitching", ISBS,
## Table 2, group III) -> bar mean + 2 SD = 6310 deg/s = 105 deg per frame.
## Control: one joint's twist jumped by 180 deg in one frame must be caught by the same measure.
## Round 21 (GATES BB3, UPGRADES #12): every scene in scenes/, scenes/_wip (the user-made ones) and scenes/_archive, AND
## each one's MIRRORED copy (Scene.mirror_card on every card, as Mirror the scene does): none over the bar, and the
## mirror's worst within 1 deg of its original's (a mirror is a reflection: it cannot turn a joint faster). Fails (exit 1)
## on either.
extends SceneTree

const BAR := (4765.7 + 2.0 * 771.9) / 60.0   # deg per 60 fps frame


func turn(B: Body, j: String, a: Vector3, b: Vector3) -> float:
	return rad_to_deg(B.compose(j, a).angle_to(B.compose(j, b)))


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var files := []
	for d in ["res://scenes/", "res://scenes/_wip/", "res://scenes/_archive/"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"):
				files.append(d + f)
	var over := 0
	var worst_all := 0.0
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var runs := []   # [label, dict]
	for path in files:
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary or not d.has("cards") or d["cards"].size() < 2:
			continue
		runs.append([path.get_file(), d])
		var dm: Dictionary = (d as Dictionary).duplicate(true)
		dm["cards"] = dm["cards"].map(func(c): return Scene.mirror_card(c, M))
		runs.append([path.get_file() + " MIRRORED", dm])
	var orig_worst := {}
	var mirror_bad := []
	for r in runs:
		var path: String = r[0]
		var S := Scene.new()
		S.from_dict(r[1])
		var n := int(S.length() * 60.0)
		var prev := {}
		var worst := 0.0
		var wj := ""
		var wt := 0.0
		for i in n + 1:
			S.apply(B, minf(i / 60.0, S.length()))
			for j in Body.ORDER:
				if prev.has(j):
					var a := turn(B, j, prev[j], B.ang[j])
					if a > worst:
						worst = a
						wj = j
						wt = i / 60.0
				prev[j] = B.ang[j]
		worst_all = maxf(worst_all, worst)
		if worst > BAR:
			over += 1
		if path.ends_with(" MIRRORED"):
			var o: float = orig_worst[path.trim_suffix(" MIRRORED")]
			if absf(worst - o) > 1.0:
				mirror_bad.append("%s: %.1f vs %.1f" % [path, worst, o])
		else:
			orig_worst[path] = worst
		print("%s %-44s worst %5.1f deg/frame (%5.0f deg/s) %-12s at %.2f s" % ["OVER" if worst > BAR else "    ", path.get_file(), worst, worst * 60.0, wj, wt])
	# control
	var v := Vector3(10, 5, 20)
	var c := turn(B, "lowerarm_r", v, v + Vector3(0, 0, 180))
	print("control: a 180 deg twist in one frame reads %.0f deg/frame (bar %.0f): %s" % [c, BAR, "CAUGHT" if c > BAR else "MISSED"])
	print("FLIPS: %d runs (%d scenes + their mirrors), worst %.1f deg/frame = %.0f deg/s; %d over the bar (%.0f deg/frame); mirrors off their original by > 1 deg: %s" % [runs.size(), runs.size() / 2, worst_all, worst_all * 60.0, over, BAR, mirror_bad])
	TestFiles.cleanup()
	quit(1 if over > 0 or not mirror_bad.is_empty() or c <= BAR else 0)
