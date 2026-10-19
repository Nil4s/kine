## godot --path . -s tests/macros_test.gd     (GATES: windowed; it saves the screenshots)
## ROADMAP 81 MACROS through the real S box: four commands recorded on one part and played on another are the same
## scene as the four run by hand there (byte-identical); the play is ONE undo step and one Ctrl+Z takes it all back;
## a step that needs a part (none picked) stops the macro and the message names its step; the macros are rows
## "Macro: <name>" in the box. Screenshots: tmp/macros.png (the list), tmp/macros_rec.png (the REC indicator).
extends SceneTree

const SHOTS := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func stand() -> void:
	m.B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))


## the palette row with this name: a registry command, or a saved macro row
func row(name: String) -> Dictionary:
	for c in m.ui_cmd.commands + m._search_files():
		if c["name"] == name:
			return c
	return {}


## the S box runs a row the way Enter does: close, running signal, the row's run
func run(name: String) -> void:
	m.ui_cmd.shown = [row(name)]
	m.ui_cmd._run(0)


## a "Pose: <words>" row as the box offers it
func run_words(t: String) -> void:
	m.ui_cmd.shown = [{"name": "Pose: " + t, "kind": "command", "keys": "words", "words": true, "run": m._pose_words.bind(t)}]
	m.ui_cmd._run(0)


func scene_json() -> String:
	return JSON.stringify(m._scene_dict()) + "|" + JSON.stringify(m.B.state())


## the four steps: a part edit, a pose phrase, a whole-body edit, a pose phrase
func four_steps() -> void:
	run("Reset the part")
	run_words("turn the head left 20")
	run("Snap to floor")
	run_words("bend the left knee 30")


func shot(file: String) -> void:
	for f in 3:
		await process_frame   # the frame is drawn on the next pass
	m.get_viewport().get_texture().get_image().save_png(SHOTS + file)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	ok(m.macros_file.begins_with("user://macros_test_"), "the macros file is a test's own path (%s)" % m.macros_file)
	m.macros = []

	# S0: the right arm up and the left elbow bent (one undo step)
	stand()
	m._pose_words("raise the right arm 90, bend the left elbow 45")
	var s0: Dictionary = m._snapshot()
	var s0_json := scene_json()

	# BY HAND on the left upper arm (B): the four commands in order
	m._restore(s0)
	m.sel = "upperarm_l"
	four_steps()
	var hand := scene_json()
	ok(hand != s0_json, "by hand on upperarm_l: the four commands change the scene (%d bytes)" % hand.length())
	m._restore(s0)

	# RECORD on the right upper arm (A): the same four commands, from S0
	m.sel = "upperarm_r"
	run("Record macro")
	ok(m.rec_name != "" and m.rec_label.visible, "Record macro: '%s' is recording, the REC label shows (%s)" % [m.rec_name, m.rec_label.text])
	four_steps()
	ok(m.rec_steps.size() == 4, "the four commands are four steps (%d)" % m.rec_steps.size())
	ok(m.rec_steps[0]["part"] == "upperarm_r" and m.rec_steps[0]["needs_part"] and not m.rec_steps[1]["needs_part"],
		"each step keeps the part picked when it ran; the part edit needs a part, the pose phrase does not")
	m.ui_cmd.close()
	await shot("macros_rec.png")
	run("Stop macro recording")
	ok(m.rec_name == "" and not m.rec_label.visible and m.macros.size() == 1 and m.macros[0]["steps"].size() == 4,
		"Stop macro recording saves 'Macro 1' with 4 steps; the REC label is off")
	ok(Macros.load_file(m.macros_file).size() == 1, "the macro is in %s" % m.macros_file)

	# PLAY on the left upper arm (B), from S0: the scene equals the by-hand run, in ONE undo step
	m._restore(s0)
	m.sel = "upperarm_l"
	var pre := scene_json()
	var u0: int = m.undo.size()
	run("Macro: Macro 1")
	ok(scene_json() == hand, "played on upperarm_l: the scene is byte-identical to the four commands by hand there")
	ok(m.undo.size() == u0 + 1, "the play is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	ok(scene_json() == pre, "one Ctrl+Z takes the whole macro back: the scene is as before the play")

	# THE LIST: "Play macro..." opens the box on macro: with the saved macros as rows
	run("Play macro...")
	var names: Array = m.ui_cmd.shown.map(func(c): return c["name"])
	ok(m.ui_cmd.box.text == "macro:" and names == ["Macro: Macro 1"], "Play macro... lists the saved macros: %s" % str(names))
	await shot("macros.png")
	m.ui_cmd.close()

	# A STEP THAT NEEDS A PART: "Front view" (no part), then "Reset the part"; played with no part picked it stops at step 2
	m._restore(s0)
	m.sel = "upperarm_r"
	run("Record macro")
	run("Front view")
	run("Reset the part")
	run("Stop macro recording")
	ok(m.macros.size() == 2 and m.macros[1]["steps"].size() == 2, "'Macro 2' recorded with 2 steps")
	m._restore(s0)
	m.sel = "bat_handle"   # the weapon is picked: not a body part, so the edit step has no part
	var u1: int = m.undo.size()
	var pre2 := scene_json()
	run("Macro: Macro 2")
	var msg: String = m.ui_status.text
	ok(msg.contains("step 2 of 2") and msg.contains("Reset the part") and msg.contains("body part"),
		"a step with no part stops the macro and names its index: '%s'" % msg.left(160))
	ok(m.undo.size() == u1 and scene_json() == pre2, "the stopped macro made no undo step and changed no scene")

	# the file is the test's own; the real user://macros.json is never written
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.macros_file))
	print("MACROS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
