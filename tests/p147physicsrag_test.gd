extends SceneTree
## godot --headless -s tests/p147physicsrag_test.gd     (Friday plan 147: PHYSICS RAGDOLL ON HIT, BLEND BACK TO ANIMATION)
## The body at the playhead is hit (a push on every free part), falls limp on the floor (scripts/ragdoll.gd), and blends back onto
## its own pose. The command is the registry entry "Ragdoll: hit, fall, get back up" (main._commands()): the same callable the
## command search runs on Enter, so a beginner's pick of it is what runs (the test does not move the mouse over the search box).
## Bars written before the code. Every measure is read from the built cards (the scene the command opened), never from the code's variables.
##   H1 the command is in the registry under its id, with no key, and its name says hit
##   H2 running it opens a NEW scene (its name carries _hit, not the old scene's name) with at least 90 cards (3 s at 30 fps)
##   H3 the first card is the pose at the playhead: every joint within 0.5 deg of the pose before the command, pelvis within 1 mm
##   H4 the hit pushes the body: the pelvis moves at least 100 mm sideways by 0.5 s (card 15)
##   H5 the fall: at 2.0 s (card 60) the pelvis is at least 300 mm lower than at the start, and a joint is at least 20 deg off its start
##   H6 the blend back: the last card is back on the animation: every joint within 0.5 deg of the start pose, pelvis within 1 mm
##   H7 the blend is gradual: the joints' deviation from the start is smaller at 2.5 s than at 2.0 s, and at 3.0 s smaller than at 2.5 s
const SHOT := "C:/Temp/claude/p147physicsrag"
const CMD := "ragdoll_hit_fall_get_back_up"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the joints' largest difference (deg, bend / side / twist) between two card poses, and the pelvis offset difference (m)
func dev(a: Dictionary, b: Dictionary) -> Array:
	var worst := 0.0
	var ja: Dictionary = a["joints"]
	var jb: Dictionary = b["joints"]
	for j in ja.keys():
		for k in ["bend", "side", "twist"]:
			worst = maxf(worst, absf(float(ja[j][k]) - float(jb[j][k])))
	var oa: Array = a["offset"]
	var ob: Array = b["offset"]
	return [worst, Vector2(float(oa[0]) - float(ob[0]), float(oa[2]) - float(ob[2])).length(), float(ob[1]) - float(oa[1])]


func _init() -> void:
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT))

	# H1: the registry entry
	var cmd := {}
	for c in m._commands():
		if String(c["id"]) == CMD:
			cmd = c
	ok(not cmd.is_empty() and String(cmd.get("keys", "x")) == "" and "hit" in String(cmd.get("name", "")).to_lower(),
		"H1 the command %s is in the registry, with no key, named with 'hit'" % CMD)
	if cmd.is_empty():
		print("FAILS %d" % (fails + 1))
		quit(1)
		return

	# the pose at the playhead, read from the built body before the command
	var old_name: String = m.S.name
	var before: Dictionary = m.B.to_dict()

	# a beginner's pick: the command runs
	(cmd["run"] as Callable).call()
	await idle(10)

	var cards: Array = m.S.cards
	var new_name: String = m.S.name
	ok(new_name != old_name and "_hit" in new_name and cards.size() >= 90,
		"H2 a NEW scene opened (%s), %d cards (3 s at 30 fps is 90)" % [new_name, cards.size()])
	if cards.size() < 90:
		print("FAILS %d" % fails)
		quit(1)
		return

	var p0: Dictionary = cards[0]["pose"]
	var d0 := dev(before, p0)
	ok(float(d0[0]) <= 0.5 and float(d0[1]) <= 0.001,
		"H3 the first card is the playhead pose: worst joint %.3f deg, pelvis %.2f mm" % [float(d0[0]), float(d0[1]) * 1000.0])

	var pose15: Dictionary = cards[15]["pose"]
	var d15 := dev(p0, pose15)
	ok(float(d15[1]) >= 0.1, "H4 the hit pushes the pelvis: %.0f mm sideways by 0.5 s" % (float(d15[1]) * 1000.0))

	var pose60: Dictionary = cards[60]["pose"]
	var d60 := dev(p0, pose60)
	ok(-float(d60[2]) >= 0.3 and float(d60[0]) >= 20.0,
		"H5 the fall: pelvis %.0f mm lower at 2.0 s, worst joint %.1f deg off the start" % [-float(d60[2]) * 1000.0, float(d60[0])])

	var last: Dictionary = cards[cards.size() - 1]["pose"]
	var dl := dev(p0, last)
	ok(float(dl[0]) <= 0.5 and float(dl[1]) <= 0.001,
		"H6 the last card is back on the animation: worst joint %.3f deg, pelvis %.2f mm" % [float(dl[0]), float(dl[1]) * 1000.0])

	var pose75: Dictionary = cards[75]["pose"]
	var pose90: Dictionary = cards[90]["pose"]
	var d75 := float(dev(p0, pose75)[0])
	var d90 := float(dev(p0, pose90)[0])
	ok(d75 < float(d60[0]) and d90 < d75,
		"H7 the blend is gradual: worst joint %.1f deg at 2.0 s, %.1f at 2.5 s, %.1f at 3.0 s" % [float(d60[0]), d75, d90])

	await idle(3)
	root.get_texture().get_image().save_png("%s/p147_hit_open.png" % SHOT)
	print("FAILS %d" % fails)
	quit(1 if fails > 0 else 0)
