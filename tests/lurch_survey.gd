## godot --headless --path . -s tests/lurch_survey.gd      (GATES I4: where does a LURCH bar go?)
## Every scene at 60 fps: the hips' and the head's acceleration |dv|/dt (m/s^2) per frame. Prints each scene's top
## three with times, so the bar is set from the data's own gap, not guessed.
extends SceneTree


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var files := []
	for d in ["res://scenes", "res://scenes/_wip"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"):
				files.append(d + "/" + f)
	var fps := 60.0
	for f in files:
		var S := Scene.new()
		var d = JSON.parse_string(FileAccess.get_file_as_string(f))
		if not d is Dictionary or not d.has("cards"):
			continue
		S.from_dict(d)
		var n := int(ceil(S.length() * fps)) + 1
		var pos := {"hips": [], "head": []}
		for i in n:
			S.apply(B, minf(i / fps, S.length()))
			pos["hips"].append(B.P["pelvis"])
			pos["head"].append(B.P["head"])
		var line := "%-32s" % f.get_file()
		for k in ["hips", "head"]:
			var p: Array = pos[k]
			var acc := []
			for i in range(1, p.size() - 1):
				var a: float = (((p[i + 1] as Vector3) - p[i]) - ((p[i] as Vector3) - p[i - 1])).length() * fps * fps
				acc.append([a, i / fps])
			acc.sort_custom(func(x, y): return x[0] > y[0])
			var top := ""
			var used := []
			for e in acc:
				var near := false
				for u in used:
					if absf(u - e[1]) < 0.1:
						near = true
				if near:
					continue
				used.append(e[1])
				top += " %5.0f@%.2f" % [e[0], e[1]]
				if used.size() == 3:
					break
			line += "  %s:%s" % [k, top]
		print(line)
	quit()
