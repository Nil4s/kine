## godot --headless --path . -s tools/make_presets.gd  -> res://poses/*.json (the starter poses, built by the same math)
extends SceneTree


func _pose(sets: Dictionary, reaches := []) -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for j in sets:
		B.set_ang_safe(j, sets[j])
	for r in reaches:
		var head: Vector3 = B.P["head"]
		var err := B.reach(r[0], r[1].call(B))
		print("  reach %s err %.3f m" % [r[0], err])
	return B


func _save(B: Body, name: String) -> void:
	var d := B.to_dict()
	d["note"] = "starter pose (tools/make_presets.gd). Angles in degrees from rest, A/G quaternions, positions in metres. MATH.md"
	var f := FileAccess.open("res://poses/%s.json" % name, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	print("%s: contacts %s" % [name, B.contacts()])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://poses"))
	_save(_pose({}), "t_pose")
	var down := {"upperarm_r": Vector3(0, -88, 0), "upperarm_l": Vector3(0, -88, 0), "lowerarm_r": Vector3(8, 0, 0), "lowerarm_l": Vector3(8, 0, 0)}
	_save(_pose(down), "stand")
	# military salute: fingertips at the right brow corner (head joint + (-0.045, 0.11, 0.085)), so the wrist sits a hand
	# below-out-front of it; elbow out to the side near shoulder height; left arm straight down; chin level
	var sal := down.duplicate()
	sal["upperarm_r"] = Vector3(30, 0, 0)
	_save(_pose(sal, [["hand_r", func(B): return (B.P["head"] as Vector3) + Vector3(-0.165, 0.04, 0.115)]]), "salute")
	# a commander's order: right arm points forward and a little up, straight; left fist on the hip, elbow out;
	# chest square, chin up, weight a little forward
	var cmd := {"upperarm_r": Vector3(80, -15, 0), "lowerarm_r": Vector3(5, 0, 0), "upperarm_l": Vector3(0, -60, 0),
		"spine_03": Vector3(-4, 0, 0), "neck_01": Vector3(-8, 0, 0), "thigh_r": Vector3(12, 4, 0), "calf_r": Vector3(8, 0, 0)}
	_save(_pose(cmd, [["hand_l", func(B): return (B.P["thigh_l"] as Vector3) + Vector3(0.12, 0.1, -0.02)]]), "command_point")
	quit()
