## godot --path . -s tests/histscript_test.gd     (GATES: windowed; it saves the screenshot)
## O15 HISTORY AS A SCRIPT. Bars (stated before measuring):
##  1. five palette commands on a fresh scene, saved as a .kscript, the scene reset, the script run: the scene JSON (scene dict
##     + body state) is byte-equal to the first run's
##  2. a script with an unknown id stops at that line; the message names the line number and the id; the lines before it stay
##     (one undo step), the lines after do not run
##  3. one Ctrl+Z after a script run restores the pre-script scene; the whole script is ONE undo step (6+ lines)
##  4. the saved file is only under user://scripts/ (histscript.gd has one write, on a user:// path)
##  5. placement: the result message is in the status line, drawn inside the window (screenshot tmp/histscript.png)
extends SceneTree

const SHOTS := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
const NAME := "histscript_test_tmp"

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func row(name: String) -> Dictionary:
	for c in m.ui_cmd.commands:
		if c["name"] == name:
			return c
	return {}


func run(name: String) -> void:
	m.ui_cmd.shown = [row(name)]
	m.ui_cmd._run(0)


func run_words(t: String) -> void:
	m.ui_cmd.shown = [{"name": "Pose: " + t, "kind": "command", "keys": "words", "words": true, "run": m._pose_words.bind(t)}]
	m.ui_cmd._run(0)


func scene_json() -> String:
	return JSON.stringify(m._scene_dict()) + "|" + JSON.stringify(m.B.state())


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	m._pose_words("raise the right arm 90, bend the left elbow 45")
	var s0: Dictionary = m._snapshot()
	var s0_json := scene_json()

	# BAR 1: five commands (two parts picked, two pose phrases, a whole-body edit), saved
	m._hs_log = []
	m._hs_sel = ""
	m.sel = "upperarm_l"
	run("Reset the part")
	run_words("turn the head left 20")
	run("Snap to floor")
	m.sel = "upperarm_r"
	run_words("bend the left knee 30")
	run("Reset the part")
	ok(m._hs_log.size() == 5, "the session log holds the 5 commands (%d)" % m._hs_log.size())
	var first := scene_json()
	ok(first != s0_json, "the five commands change the scene")
	var path: String = m._hs_save(NAME)
	var txt := FileAccess.get_file_as_string(path)
	print(txt)
	ok(path == "user://scripts/%s.kscript" % NAME and txt.contains("run reset_the_part") and txt.contains("set sel upperarm_r") and txt.contains("set pose turn the head left 20"),
		"saved %s with run / set sel / set pose lines and the human names as comments" % path)
	m._restore(s0)
	ok(scene_json() == s0_json, "reset: the scene is S0 again")
	m.sel = "head"
	var u0: int = m.undo.size()
	var pre := scene_json()
	var r: Dictionary = await m._hs_play(NAME)
	ok(r["ok"] and r["done"] == 9, "the script ran %d lines (5 commands + 4 set sel): %s" % [r["done"], str(r.get("message", ""))])
	ok(scene_json() == first, "the replayed scene is byte-equal to the first run's (%d bytes)" % first.length())
	var msg: String = m.ui_status.text
	await process_frame
	await process_frame
	m.get_viewport().get_texture().get_image().save_png(SHOTS + "histscript.png")

	# BAR 3: ONE undo step for the whole play
	ok(m.undo.size() == u0 + 1 and r["undo_steps"] == 1, "the 9-line script is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	ok(scene_json() == pre, "one Ctrl+Z restores the pre-script scene")

	# BAR 2: an unknown id stops at its line
	m._restore(s0)
	var bad := "# Kine script v1\nrun reset_the_part\n# a comment\nrun no_such_command\nrun snap_to_floor\n"
	m.sel = "upperarm_l"
	var after_line1: String
	m._restore(s0)
	m.sel = "upperarm_l"
	var rr: Dictionary = await m._hs_run_text("run reset_the_part\n", "one")
	after_line1 = scene_json()
	m._restore(s0)
	m.sel = "upperarm_l"
	var u1: int = m.undo.size()
	var r2: Dictionary = await m._hs_run_text(bad, "bad")
	var m2: String = r2["message"]
	ok(not r2["ok"] and r2["done"] == 1 and m2.contains("line 4") and m2.contains("no_such_command"), "unknown id stops at line 4 naming it: '%s'" % m2.left(150))
	ok(scene_json() == after_line1 and m.undo.size() == u1 + 1, "line 5 did not run; the line before is one undo step (%d)" % (m.undo.size() - u1))
	var r3: Dictionary = await m._hs_run_text("run reset_the_part\nhop twice\n", "junk")
	ok(not r3["ok"] and String(r3["message"]).contains("line 2"), "a line it cannot read stops at line 2: '%s'" % String(r3["message"]).left(120))
	# the script rows in the S box
	run("Help: run a script...")
	var names: Array = m.ui_cmd.shown.map(func(c): return c["name"])
	ok(m.ui_cmd.box.text == "script:" and names.has("Script: " + NAME), "Help: run a script... lists the saved scripts: %s" % str(names))
	m.ui_cmd.close()

	# BAR 4: files only under user://
	var src := FileAccess.get_file_as_string("res://scripts/histscript.gd")
	ok(src.count("FileAccess.WRITE") == 1 and Histscript.DIR.begins_with("user://") and FileAccess.file_exists("user://scripts/%s.kscript" % NAME),
		"histscript.gd has one write, to %s" % Histscript.DIR)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# BAR 5: placement of the message
	var lab: Control = m.ui_status
	var vr := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
	var gr := lab.get_global_rect()
	ok(msg.begins_with("script '") and vr.encloses(gr) and gr.size.x > 100 and lab.is_visible_in_tree(),
		"the result message '%s' is in the status line at %s inside the window %s" % [msg, str(gr), str(vr.size)])
	print("HISTSCRIPT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
