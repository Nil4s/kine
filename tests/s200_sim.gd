extends SceneTree
## Run by tests/s200_test.gd inside the EXPORTED game folder:  godot --headless --path <game> --script s200_sim.gd
## Loads the game's main scene, lets the hero settle, holds "move_forward" for 2 s of physics time, then Space.
## Prints two lines:  SIM start=.. end=..   and   SIM miny=.. jump=.. cam=..
var scn: Node
var frames := 0
var start := Vector3.ZERO
var miny := 1e9
var jump_base := 0.0
var maxy := -1e9
var phase := 0


func _init() -> void:
	scn = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scn)
	physics_frame.connect(_tick)


func _tick() -> void:
	var p: CharacterBody3D = scn.get_node("Player")
	frames += 1
	miny = minf(miny, p.global_position.y)
	if phase == 0 and frames == 60:
		start = p.global_position
		Input.action_press("move_forward")
		phase = 1
	elif phase == 1 and frames == 60 + 120:
		print("SIM start=%s end=%s" % [start, p.global_position])
		Input.action_release("move_forward")
		phase = 2
	elif phase == 2 and frames == 60 + 120 + 30:
		jump_base = p.global_position.y
		Input.action_press("jump")
		phase = 3
	elif phase == 3:
		maxy = maxf(maxy, p.global_position.y)
		if frames == 60 + 120 + 30 + 2:
			Input.action_release("jump")
		if frames == 60 + 120 + 30 + 60:
			print("SIM miny=%s jump=%s cam=%s" % [miny, maxy - jump_base, (p.get_node("Camera3D") as Camera3D).global_position])
			quit()
