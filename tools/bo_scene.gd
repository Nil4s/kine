extends SceneTree
## FIRST STAFF SCENE (Nick 10-13: "in transitions it can use one hand to swing the bo and get it back in two hands
## for defence, like a real monk ... can you make a scene for us to judge?"). From Nick's own two-hand guard
## (moves/pose_20261013_082602): the left hand lets go to a fist, the right hand loads the staff back to his right,
## sweeps it across the front one-handed (the long end leads), follows through to his left, and the left hand
## catches it back into Nick's guard. Legs = his guard's all the way (the footing stays planted).
##   godot --headless --path . -s tools/bo_scene.gd        -> scenes/bo_sweep.json
const GUARD := "res://moves/pose_20261013_082602.json"

func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var guard: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GUARD))
	var S := Scene.new()
	S.name = "bo_sweep"
	B.from_dict(guard)
	B.capture_second()
	S.cards.append({"name": "guard (Nick)", "pose": B.to_dict(), "move": 0.0, "hold": 0.3})
	var pv: Vector3 = B.P["pelvis"]
	# [name, wrist (from the hips: +x his left, +y up, +z forward), staff direction butt->tip, move s, hold s]
	var keys := [
		["let go + load", Vector3(-0.28, 0.42, 0.02), Vector3(-0.75, 0.25, -0.55), 0.35, 0.05],
		["SWEEP (front)", Vector3(-0.05, 0.40, 0.38), Vector3(0.35, 0.05, 0.95), 0.18, 0.0],
		["follow-through", Vector3(0.18, 0.38, 0.22), Vector3(0.95, 0.05, -0.25), 0.20, 0.1],
	]
	var lane: float = (B.ang["hand_r"] as Vector3).z   # the guard's forearm turn: the one-hand keys keep it (no spin)
	var la := {}
	for j in ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"]:
		la[j] = B.ang[j]
	for k in keys:
		B.grip = false
		# the left hand lets go where it was: the guard's arm, the elbow folded 25 deg more (pulled back off the
		# staff's path), its roll and forearm turn kept (no spin)
		# the free left hand lets go where it was and closes to a fist (no path to travel: going down to the waist
		# took the forearm through the head)
		for j in la:
			B.ang[j] = la[j]
		B.fk()
		B.hand_shape("l", "fist")
		# the forearm's turn travels key to key, at most 40 deg from the key before (the spin rule is 45)
		var r: Array = B.hold_bat(pv + (k[1] as Vector3), (k[2] as Vector3).normalized(), true, true, lane, 40.0)
		lane = (B.ang["hand_r"] as Vector3).z
		print("%-16s wrist miss %.3f m  aim off %.1f deg  contacts %d  forearm turn %.0f" % [k[0], r[0], r[1], B.contacts().size(), lane])
		S.cards.append({"name": k[0], "pose": B.to_dict(), "move": k[3], "hold": k[4]})
	B.from_dict(guard)
	B.capture_second()
	S.cards.append({"name": "catch: guard (Nick)", "pose": B.to_dict(), "move": 0.35, "hold": 0.3})
	var d := S.to_dict(B)
	d["note"] = "first staff scene: Nick's two-hand guard -> one-hand sweep -> caught back in two hands (tools/bo_scene.gd)"
	FileAccess.open("res://scenes/bo_sweep.json", FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("BO SCENE %.2f s, %d keys, spins %s" % [S.length(), S.cards.size(), S.spins()])
	quit()
