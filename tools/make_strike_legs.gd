## godot --headless --path . -s tools/make_strike_legs.gd -> res://scenes/strike_legs.json
## Nick's strike (scenes/scene_20261012_220805.json, his arms kept exactly) + legs, hips, back and timing:
## load to his right, step with the left foot and whip the hips -> chest -> arm -> bat to his left.
## Every clip: feet flat (or the back heel up on the toes), then the body dropped so the soles touch the floor.
extends SceneTree

const SRC := "res://scenes/scene_20261012_220805.json"

# per clip: the lower body + trunk (degrees: bend, side, twist; meaning in data/body_limits.json "say")
#   pelvis twist + = hips turn to his left;  spine twist + = chest turns to his left;  bend + = lean forward
const PLAN := [
	{"name": "ready stance", "move": -1.0, "hold": 0.3, "toes_r": false,
	 "set": {"thigh_l": Vector3(4, 5, 0), "thigh_r": Vector3(4, 5, 0), "calf_l": Vector3(8, 0, 0), "calf_r": Vector3(8, 0, 0)}},
	{"name": "bat comes up", "move": 0.55, "hold": 0.05, "toes_r": false,
	 "set": {"thigh_l": Vector3(6, 5, 0), "thigh_r": Vector3(6, 5, 0), "calf_l": Vector3(12, 0, 0), "calf_r": Vector3(12, 0, 0),
		"spine_02": Vector3(-2, 0, 0)}},
	{"name": "load", "move": 0.45, "hold": 0.0, "toes_r": false,
	 "set": {"pelvis": Vector3(0, 0, -8), "spine_01": Vector3(-2, 0, -6), "spine_02": Vector3(-2, 0, -6), "spine_03": Vector3(-2, 0, -6),
		"thigh_l": Vector3(8, 5, 8), "thigh_r": Vector3(10, 4, 8), "calf_l": Vector3(16, 0, 0), "calf_r": Vector3(18, 0, 0)}},
	{"name": "overhead coil", "move": 0.4, "hold": 0.08, "toes_r": false,
	 "set": {"pelvis": Vector3(0, 0, -12), "spine_01": Vector3(-4, 0, -9), "spine_02": Vector3(-4, 0, -9), "spine_03": Vector3(-4, 0, -9),
		"neck_01": Vector3(-6, 0, 10), "thigh_l": Vector3(18, 4, 10), "thigh_r": Vector3(12, 4, 10), "calf_l": Vector3(30, 0, 0), "calf_r": Vector3(22, 0, 0)}},
	{"name": "STRIKE (step)", "move": 0.16, "hold": 0.04, "toes_r": true, "steps": {"_l": [0.04, 0, 0.26]},
	 "set": {"pelvis": Vector3(8, 0, 10), "spine_01": Vector3(5, 0, 7), "spine_02": Vector3(5, 0, 7), "spine_03": Vector3(5, 0, 7),
		"neck_01": Vector3(-10, 0, -6), "thigh_l": Vector3(30, 3, -6), "thigh_r": Vector3(-12, 3, -6), "calf_l": Vector3(30, 0, 0), "calf_r": Vector3(18, 0, 0)}},
	{"name": "follow-through", "move": 0.3, "hold": 0.5, "toes_r": true,
	 "set": {"pelvis": Vector3(12, 0, 15), "spine_01": Vector3(7, 0, 9), "spine_02": Vector3(7, 0, 9), "spine_03": Vector3(7, 0, 9),
		"neck_01": Vector3(-14, 0, -8), "thigh_l": Vector3(34, 2, -8), "thigh_r": Vector3(-18, 2, -8), "calf_l": Vector3(37, 0, 0), "calf_r": Vector3(27, 0, 0)}},
]


func _init() -> void:
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC))
	var S := Scene.new()
	S.name = "strike_legs"
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for i in PLAN.size():
		var plan: Dictionary = PLAN[i]
		B.from_dict(src["cards"][i]["pose"])            # Nick's arms, bat and fingers
		for j in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "thigh_l", "thigh_r", "calf_l", "calf_r",
				"foot_l", "foot_r", "ball_l", "ball_r"]:
			B.ang[j] = Vector3.ZERO
		B.offset = Vector3.ZERO
		B.fk()
		for j in plan["set"]:
			B.set_ang_safe(j, plan["set"][j])
		B.flat_foot("_l")
		B.flat_foot("_r")
		if plan["toes_r"]:
			# back foot of the lunge: the heel lifts 25 deg, the toes stay flat on the floor
			var f: Vector3 = B.ang["foot_r"]
			B.set_ang("foot_r", f + Vector3(-25, 0, 0))
			B.toes_flat("_r")
		B.ground()
		B.apply_grip()
		S.add(plan["name"], B.to_dict())
		S.cards[-1]["move"] = plan["move"]
		S.cards[-1]["hold"] = plan["hold"]
		S.cards[-1]["steps"] = plan.get("steps", {})   # every other foot on the floor stays planted
		print("%-16s hips y %+.3f  feet: L %s  R %s  contacts %s" % [plan["name"], B.offset.y, B.ang["foot_l"], B.ang["foot_r"], B.contacts()])
	for i in S.cards.size():
		var st := S._feet(B, i)
		print("before pin %-16s L %s  R %s" % [S.cards[i]["name"], st["_l"], st["_r"]])
	print("legs re-planted: ", S.pin_cards(B))
	for i in S.cards.size():
		var st := S._feet(B, i)
		print("after  pin %-16s L %s  R %s  contacts %s" % [S.cards[i]["name"], st["_l"], st["_r"], B.contacts()])
	var n := S.clear(B)
	var d := S.to_dict(B)
	var f := FileAccess.open("res://scenes/strike_legs.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	print("strike_legs: %d clips (%d pass-by added), %.2f s, frames with parts inside each other: %d" % [S.cards.size(), n, S.length(), d["bad_frames"].size()])
	if not d["bad_frames"].is_empty():
		print("  e.g. ", d["bad_frames"][0])
	quit()
