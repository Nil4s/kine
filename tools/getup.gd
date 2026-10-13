extends SceneTree
## GET-UPS for the game's ragdoll knockdown (Nick 10-13: the bo sweep drops them, the ragdoll is approved; "those
## scenes don't run on our engine?" -> built here, baked with tools/bake_scene.gd, played by the game's PoserClip).
## A real get-up from the BACK: lie -> sit up (knees bent, the right hand planted behind the hip) -> turn onto the
## right knee (the right hand on the floor, the left hand on the left knee) -> stand. From the FRONT (face down):
## lie -> push up (hands under the shoulders) -> the left foot forward, the right knee down -> stand.
## Each key is joint angles (data/body_limits.json 'say'), then the hands are put on the floor with reach(), then the
## WHOLE body is grounded on its lowest point (Body.ground() reads the soles only; a lying body rests on its back).
## Measured (10-13): the pelvis tipping back by p swings the thighs FORWARD by p (thigh from straight down = bend - pelvis
## bend); forward tips them back. A vertical back thigh under a pelvis tipped p forward = thigh bend +p.
## The pelvis is the root: lying needs its bend to -90 / +90 (body_limits pelvis bend widened to [-100, 100]).
##   godot --headless --path . -s tools/getup.gd   -> scenes/_wip/getup_back.json, scenes/_wip/getup_front.json

var B: Body
var stand: Dictionary


func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## the lowest point of the whole body (each capsule's ends minus its radius) put on the floor
func ground_all() -> void:
	B.fk()
	var low := INF
	for j in Body.ORDER:
		if j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
			continue
		var r: float = float(B.rad.get(j, 0.03))
		low = minf(low, minf((B.P[j] as Vector3).y, (B.E[j] as Vector3).y) - r)
	B.offset.y -= low
	B.fk()


## a key: stand's pose with these joints set (deg: bend, side, twist; "_l"/"_r" mirrored as written), grounded; then
## each hand in `hands` reaches its floor spot (x, z from the pelvis, in the pelvis' facing; y = on the floor)
func key(set: Dictionary, hands := {}) -> Dictionary:
	B.from_dict(stand)
	B.offset = Vector3.ZERO
	for j in set:
		if j.begins_with("_"):
			continue
		B.ang[j] = B.clamp_ang(j, _v3(set[j]))
	ground_all()
	var turn := deg_to_rad((B.ang["pelvis"] as Vector3).z)
	for h in hands:
		var o: Vector2 = hands[h]
		var p: Vector3 = B.P["pelvis"]
		var at := Vector3(p.x, 0.0, p.z) + Basis(Vector3.UP, turn) * Vector3(o.x, 0.0, o.y)
		at.y = 0.06   # the wrist above the floor: the palm on it
		B.reach(h, at)
		ground_all()
	var d := B.to_dict()
	print("  %-14s contacts %d, at limit %s, hips %.2f m up" % [set.get("_name", "?"), B.contacts().size(), _limits(), (B.P["pelvis"] as Vector3).y])
	return d


func _limits() -> Array:
	var out := []
	for j in ["pelvis", "spine_01", "spine_02", "spine_03", "thigh_l", "thigh_r", "calf_l", "calf_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]:
		if not B.at_limit(j).is_empty():
			out.append(j)
	return out


func scene(nm: String, keys: Array) -> void:
	var S := Scene.new()
	S.name = nm
	for k in keys:
		S.cards.append(k)
	S.cards.append({"name": "stand", "pose": stand, "move": 0.55, "hold": 0.2})
	var d := S.to_dict(B)
	d["note"] = "Get-up (tools/getup.gd) for the game's ragdoll knockdown: baked with tools/bake_scene.gd"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/_wip"))
	FileAccess.open("res://scenes/_wip/%s.json" % nm, FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("%s: %.2f s, %d cards, spins %s, bad frames %d" % [nm, S.length(), S.cards.size(), S.spins(), d["bad_frames"].size()])


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	stand = JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json"))
	print("FROM THE BACK")
	var lie := key({"_name": "lie (back)", "pelvis": [-90, 0, 0], "neck_01": [10, 0, 0],
		"thigh_l": [2, 6, 0], "thigh_r": [2, 6, 0], "calf_l": [6, 0, 0], "calf_r": [4, 0, 0], "foot_l": [-25, 8, 0], "foot_r": [-25, 8, 0],
		"upperarm_l": [-8, -72, 0], "upperarm_r": [-8, -72, 0], "lowerarm_l": [10, 0, 0], "lowerarm_r": [10, 0, 0]})
	var sit := key({"_name": "sit up", "pelvis": [-30, 0, 8], "spine_01": [18, 0, 0], "spine_02": [16, 0, 0], "spine_03": [12, 0, 0], "neck_01": [8, 0, 0],
		"thigh_l": [105, 6, 0], "thigh_r": [60, 8, 0], "calf_l": [90, 0, 0], "calf_r": [5, 0, 0], "foot_l": [-10, 0, 0], "foot_r": [-25, 5, 0],
		"upperarm_l": [55, -45, 0], "lowerarm_l": [35, 0, 0], "upperarm_r": [-30, -60, 0], "lowerarm_r": [8, 0, 0]},
		{"hand_r": Vector2(-0.34, -0.20)})
	var kneel := key({"_name": "on one knee", "pelvis": [12, 0, -15], "spine_01": [10, 0, 0], "spine_02": [8, 0, 0], "neck_01": [5, 0, 0],
		"thigh_l": [102, 5, 0], "calf_l": [90, 0, 0], "foot_l": [-10, 0, 0],
		"thigh_r": [12, 5, 0], "calf_r": [90, 0, 0], "foot_r": [-40, 0, 0],
		"upperarm_l": [40, -55, 0], "lowerarm_l": [45, 0, 0], "upperarm_r": [30, -70, 0], "lowerarm_r": [10, 0, 0]},
		{"hand_r": Vector2(-0.42, 0.22)})
	scene("getup_back", [{"name": "lie (back)", "pose": lie, "move": 0.0, "hold": 0.1},
		{"name": "sit up", "pose": sit, "move": 0.5, "hold": 0.05},
		{"name": "on one knee", "pose": kneel, "move": 0.45, "hold": 0.05}])
	print("FROM THE FRONT")
	var prone := key({"_name": "lie (front)", "pelvis": [90, 0, 0], "neck_01": [-15, 0, 10],
		"thigh_l": [0, 6, 0], "thigh_r": [0, 6, 0], "calf_l": [8, 0, 0], "calf_r": [8, 0, 0], "foot_l": [-40, 0, 0], "foot_r": [-40, 0, 0],
		"upperarm_l": [-20, -70, 0], "upperarm_r": [-20, -70, 0], "lowerarm_l": [15, 0, 0], "lowerarm_r": [15, 0, 0]})
	var push := key({"_name": "push up", "pelvis": [62, 0, 0], "spine_01": [-7, 0, 0], "spine_02": [-7, 0, 0], "spine_03": [-6, 0, 0], "neck_01": [-15, 0, 0],
		"thigh_l": [20, 6, 0], "thigh_r": [20, 6, 0], "calf_l": [70, 0, 0], "calf_r": [70, 0, 0], "foot_l": [-40, 0, 0], "foot_r": [-40, 0, 0],
		"upperarm_l": [70, -45, 0], "upperarm_r": [70, -45, 0], "lowerarm_l": [10, 0, 0], "lowerarm_r": [10, 0, 0]},
		{"hand_l": Vector2(0.24, 0.35), "hand_r": Vector2(-0.24, 0.35)})
	var kneel2 := key({"_name": "foot forward", "pelvis": [30, 0, 0], "spine_01": [15, 0, 0], "spine_02": [10, 0, 0],
		"thigh_l": [118, 8, 0], "calf_l": [90, 0, 0], "foot_l": [-25, 0, 0],
		"thigh_r": [30, 5, 0], "calf_r": [90, 0, 0], "foot_r": [-40, 0, 0],
		"upperarm_l": [40, -60, 0], "lowerarm_l": [40, 0, 0], "upperarm_r": [45, -60, 0], "lowerarm_r": [10, 0, 0]},
		{"hand_r": Vector2(-0.22, 0.40)})
	scene("getup_front", [{"name": "lie (front)", "pose": prone, "move": 0.0, "hold": 0.1},
		{"name": "push up", "pose": push, "move": 0.45, "hold": 0.05},
		{"name": "foot forward", "pose": kneel2, "move": 0.4, "hold": 0.05}])
	quit()
