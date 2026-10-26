## godot --headless --path . -s tests/pose_words_test.gd     (GATES T3)
## WORDS TO A POSE through the real poser: each phrase from the stand pose, the angles the Body actually REACHED; a turn
## past a limit is reported as stopped, with both numbers; bad phrases fail naming the word / what's missing; a phrase
## is ONE undo step, and a bad one is none.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func stand() -> void:
	m.B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))


func a(j: String) -> Vector3:
	return m.B.ang[j]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	# [phrase, [joint, axis, expected reached], ...]
	var cases := [
		["raise the right arm 90", [["upperarm_r", 1, 25.0]]],
		["bend the left elbow 45", [["lowerarm_l", 0, 55.0]]],
		["raise the right arm 90, bend the left elbow 45", [["upperarm_r", 1, 25.0], ["lowerarm_l", 0, 55.0]]],
		["turn the head left 30", [["head", 2, 30.0]]],
		# spine_01's capsule meets the thighs' at 7.4 deg (stand): the 2.6 it can't take goes to spine_02 (the sum is 30)
		["lean the chest forward 30", [["spine_01", 0, 7.4], ["spine_02", 0, 12.6], ["spine_03", 0, 10.0]]],
		["swing the left leg forward 40 and bend the left knee 60", [["thigh_l", 0, 40.0], ["calf_l", 0, 60.0]]],
		["straighten the right elbow", [["lowerarm_r", 0, 0.0]]],
		["raise the right arm to 0", [["upperarm_r", 1, 0.0]]],
		["turn the body right 45; tilt the head left 10", [["pelvis", 2, -45.0], ["head", 1, 10.0]]],
	]
	for c in cases:
		stand()
		var u0: int = m.undo.size()
		var r: Dictionary = m._pose_words(c[0])
		var bad := []
		for e in c[1]:
			if not is_equal_approx(snappedf(a(e[0])[e[1]], 0.01), e[2]):
				bad.append("%s %s = %.2f, wanted %.2f" % [e[0], PoseWords.AXES[e[1]], a(e[0])[e[1]], e[2]])
		ok(r["ok"] and bad.is_empty() and m.undo.size() == u0 + 1, "'%s' -> %s, one undo step %s" % [c[0], c[1].map(func(e): return "%s %s %.0f" % [e[0], PoseWords.AXES[e[1]], e[2]]), bad])
	# a limit: the knee bends 145 at most
	stand()
	var r2: Dictionary = m._pose_words("bend the right knee 200")
	ok(r2["ok"] and is_equal_approx(a("calf_r").x, 145.0) and r2["ops"][0]["stopped"] and r2["ops"][0]["asked"] == 200.0 and String(m.ui_status.text).contains("stopped short"),
		"past a limit: the knee reaches 145 of 200 asked, and says so ('%s')" % String(m.ui_status.text).right(40))
	# undo takes the whole phrase back
	stand()
	var before: String = JSON.stringify(m.B.state())
	m._pose_words("raise the right arm 90, bend the left elbow 45, turn the head left 20")
	m._undo()
	ok(JSON.stringify(m.B.state()) == before, "Ctrl+Z after a 3-part phrase: the body exactly as before")
	# bad phrases: no change, no undo step, the message names what's wrong and what to say
	for c in [["flap the right arm 30", "'flap' is not a word I know"], ["raise the arm 90", "which arm: say 'left arm' or 'right arm'"],
			["raise the right knee 30", "'raise' does not go with the knee: for the knee say bend, straighten"], ["turn the head 30", "needs a direction: left, right"],
			["bend the right elbow", "needs degrees"]]:
		stand()
		var b0: String = JSON.stringify(m.B.state())
		var u0: int = m.undo.size()
		var r: Dictionary = m._pose_words(c[0])
		ok(not r["ok"] and String(r["error"]).contains(c[1]) and JSON.stringify(m.B.state()) == b0 and m.undo.size() == u0, "'%s' fails: %s" % [c[0], String(r["error"]).left(90)])
	# the S search: a phrase is the top hit, Enter runs it (one undo step); a non-phrase offers no pose
	stand()
	m.ui_cmd.open()
	m.ui_cmd.box.text = "bend the left elbow 45"
	m.ui_cmd._filter()
	var top: String = m.ui_cmd.shown[0]["name"]
	var u1: int = m.undo.size()
	m.ui_cmd._run(0)
	ok(top == "Pose: bend the left elbow 45" and is_equal_approx(a("lowerarm_l").x, 55.0) and m.undo.size() == u1 + 1 and not top in m.ui_cmd.recent,
		"search 'bend the left elbow 45': the top hit is '%s', running it bends the elbow to %.0f" % [top, a("lowerarm_l").x])
	m.ui_cmd.open()
	m.ui_cmd.box.text = "mirror"
	m.ui_cmd._filter()
	ok(not String(m.ui_cmd.shown[0]["name"]).begins_with("Pose:"), "search 'mirror': no pose offered (top: %s)" % m.ui_cmd.shown[0]["name"])
	print("POSE WORDS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
