## godot --headless --path . -s tools/make_demo_scene.gd  -> res://scenes/_archive/bat_demo.json
## A demo scene from Nick's bat_ready pose: bat down -> ready (Nick's) -> strike -> follow-through -> bat down.
extends SceneTree


func _base() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return B


func _init() -> void:
	var S := Scene.new()
	S.name = "bat_demo"
	# 1 bat down: relaxed stand, the bat in the right hand with the standard grip
	var B := _base()
	for sd in ["_r", "_l"]:
		B.set_ang("upperarm" + sd, Vector3(0, -65, 0))
		B.set_ang("lowerarm" + sd, Vector3(10, 0, 0))
	B.weapon_to_hand("hand_r")
	B.set_ang_safe("hand_r", Vector3(-20, 0, 60))
	var down := B.to_dict()
	S.add("bat down", down)
	# 2 ready: Nick's pose
	var ready: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://poses/bat_ready_nick.json"))
	S.add("ready (Nick)", ready)
	# 3 strike: chest turns to his left, the arm comes forward and down, elbow nearly straight
	B = _base()
	B.from_dict(ready)
	for j in ["spine_01", "spine_02", "spine_03"]:
		B.set_ang_safe(j, Vector3(6, -3, 15))
	B.set_ang_safe("upperarm_r", Vector3(75, -40, 55))
	B.set_ang_safe("lowerarm_r", Vector3(8, 0, 0))
	B.set_ang_safe("head", Vector3(8, 0, -15))
	var strike := B.to_dict()
	S.add("strike", strike)
	S.cards[-1]["move"] = 0.22    # a hit is fast
	S.cards[-1]["hold"] = 0.05
	# 4 follow-through: the arm carries on across and down
	B.set_ang_safe("upperarm_r", Vector3(55, -70, 40))
	B.set_ang_safe("lowerarm_r", Vector3(25, 0, 0))
	for j in ["spine_01", "spine_02", "spine_03"]:
		B.set_ang_safe(j, Vector3(10, -4, 17))
	S.add("follow-through", B.to_dict())
	S.cards[-1]["move"] = 0.25
	S.cards[-1]["hold"] = 0.25
	# 5 back to bat down
	S.add("bat down again", down)
	S.cards[-1]["hold"] = 0.5
	var chk := _base()
	var n := S.clear(chk)
	var d := S.to_dict(chk)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes"))
	var f := FileAccess.open("res://scenes/_archive/bat_demo.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	print("bat_demo: %d clips (%d pass-by), %.2f s, bad frames %d" % [S.cards.size(), n, S.length(), d["bad_frames"].size()])
	for c in d["cards"]:
		print("  %-16s arrive %.2f  leave %.2f  contacts %s" % [c["name"], c["arrive_s"], c["leave_s"], c["pose"]["contacts"]])
	if not d["bad_frames"].is_empty():
		print("  first bad: ", d["bad_frames"][0])
	quit()
