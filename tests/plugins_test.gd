## godot --path . -s tests/plugins_test.gd     (GATES: windowed; it saves the Plugins panel screenshot)
## ROADMAP 100 PLUGIN API. Bars, stated before the run:
##   - EXAMPLE LOADS: examples/plugins/mirror_all_cards is found, OFF by default (not loaded), and loads when switched on;
##   - IN THE SEARCH AND ONE UNDO STEP: its command "Mirror All Cards: Mirror every card" is an S box row that "mirror all"
##     finds; running it changes the poses (the right arm's angles land on the left, reflected), adds exactly ONE undo
##     step, and one Ctrl+Z restores the scene byte for byte (the scene's JSON);
##   - A PLUGIN THAT FAILS IS DISABLED, NAMED: api.fail(...) disables it; the message names the plugin and says "Next
##     step"; its row leaves the S box; the app is still running (frames go on, the scene is still there);
##   - CLAMPED: set_joint(0, "lowerarm_l", (500, 0, 0)) keeps the elbow at its limit (the body's bend max), reports
##     clamped = true, and the card holds the limit, not 500;
##   - WRITES: write_data("sub/ok.txt") lands under user://plugins_test_data/<name>/data/; "../escape.txt" and
##     "/abs.txt" are refused (ok = false, the file is not written);
##   - DISABLED NEVER LOADS: a plugin left off has no object, is not loaded, and adds no S box row.
## The plugins are the test's own folders (user://plugins_test/) plus the shipped example; the state and data files are
## the test's own too (user://plugins_test_state.json, user://plugins_test_data/). Screenshot: tmp/pluginapi.png.
extends SceneTree

const SHOTS := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
const ROOT := "user://plugins_test"
const DATA := "user://plugins_test_data"
const STATE := "user://plugins_test_state.json"

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## write one plugin folder of the test: its manifest and its plugin.gd
func make_plugin(folder: String, manifest: Dictionary, src: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/" + folder)
	var f := FileAccess.open(ROOT + "/" + folder + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	f = FileAccess.open(ROOT + "/" + folder + "/plugin.gd", FileAccess.WRITE)
	f.store_string(src)
	f.close()


func manifest(name: String, cid: String) -> Dictionary:
	return {"name": name, "version": "0.1.0", "author": "test", "api": 1,
		"commands": [{"id": cid, "name": "Run " + cid, "desc": "the test's command"}]}


func rec_of(folder: String) -> Dictionary:
	for r in m.plugins.found:
		if r["folder"] == folder:
			return r
	return {}


func rec_index(folder: String) -> int:
	for i in m.plugins.found.size():
		if m.plugins.found[i]["folder"] == folder:
			return i
	return -1


## the S box runs a row the way Enter does (its running signal names the undo step)
func run_row(row_name: String) -> void:
	m.ui_cmd.shown = []
	for c in m.ui_cmd.commands:
		if c["name"] == row_name:
			m.ui_cmd.shown = [c]
	m.ui_cmd._run(0)


func scene_json() -> String:
	return JSON.stringify(m._scene_dict())


func shot(file: String) -> void:
	for f in 3:
		await process_frame
	m.get_viewport().get_texture().get_image().save_png(SHOTS + file)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame

	# the test's own folders, state and data (the real user://plugins and user://plugins.json are never touched)
	for f in ["user://plugins_test_state.json", "user://plugins_test_data/escape/data/sub/ok.txt",
			"user://plugins_test_data/escape/data/sub", "user://plugins_test_data/escape/data",
			"user://plugins_test_data/escape"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	make_plugin("throws", manifest("Throws Plugin", "boom"),
		"extends RefCounted\n\nfunc command(api, id: String) -> void:\n\tapi.fail(\"the card index is wrong: pass a card that exists\")\n")
	make_plugin("clamp_probe", manifest("Clamp Probe", "bend"),
		"extends RefCounted\n\nvar last := {}\n\nfunc command(api, id: String) -> void:\n\tlast = api.set_joint(0, \"lowerarm_l\", Vector3(500, 0, 0))\n")
	make_plugin("escape", manifest("Escape Probe", "write"),
		"extends RefCounted\n\nvar last := {}\n\nfunc command(api, id: String) -> void:\n\tlast = {\"escape\": api.write_data(\"../escape.txt\", \"x\"),\n\t\t\"absolute\": api.write_data(\"/abs.txt\", \"x\"), \"inside\": api.write_data(\"sub/ok.txt\", \"hi\")}\n")
	make_plugin("sleeper", manifest("Sleeper", "nap"),
		"extends RefCounted\n\nfunc command(api, id: String) -> void:\n\tapi.log(\"should never run: it is off\")\n")

	m.plugins.roots = [ROOT, "res://examples/plugins"]
	m.plugins.data_root = DATA
	m.plugins.state_file = STATE
	m.plugins.scan()
	m._plugins_changed()

	# BARS 1: the example is found, off, not loaded
	var ex := rec_of("mirror_all_cards")
	ok(not ex.is_empty() and ex["error"] == "" and not ex["enabled"] and not ex["loaded"],
		"the example is found, has a good manifest, and is OFF by default (not loaded)")
	ok(not m.ui_cmd.commands.any(func(c): return c["name"].begins_with("Mirror All Cards")),
		"a plugin that is off adds no S box row")
	var ei := rec_index("mirror_all_cards")
	var why: String = m.plugins.set_enabled(ei, true)
	ok(why == "" and rec_of("mirror_all_cards")["loaded"], "switched on: it loads (%s)" % why)
	m._plugins_changed()

	# BARS 2: the command is in the S box, and "mirror all" finds it
	var row_name := "Mirror All Cards: Mirror every card"
	ok(m.ui_cmd.commands.any(func(c): return c["name"] == row_name), "its command is an S box row named '%s'" % row_name)
	ok(m.ui_cmd.matches("", "mirror all").any(func(c): return c["name"] == row_name),
		"the search for 'mirror all' finds it")

	# BARS 3: one undo step, the poses reflected, one Ctrl+Z back to the same bytes
	m.S.cards.clear()
	m._pose_words("raise the right arm 90")
	m._card_add()
	m._pose_words("bend the left elbow 45")
	m._card_add()
	var before := scene_json()
	var undo_before: int = m.undo.size()
	var old_r: Dictionary = (m.S.cards[0]["pose"]["joints"]["upperarm_r"] as Dictionary).duplicate()
	run_row(row_name)
	var after_j: Dictionary = m.S.cards[0]["pose"]["joints"]["upperarm_l"]
	ok(m.undo.size() == undo_before + 1, "running it adds exactly one undo step (%d -> %d)" % [undo_before, m.undo.size()])
	ok(absf(float(after_j["bend"]) - float(old_r["bend"])) < 0.001 and absf(float(after_j["side"]) - float(old_r["side"])) < 0.001
		and absf(float(after_j["twist"]) + float(old_r["twist"])) < 0.001,
		"card 0: the left upper arm now holds the right's angles reflected (bend %.1f side %.1f twist %.1f)" % [after_j["bend"], after_j["side"], after_j["twist"]])
	ok(scene_json() != before, "the mirror changed the scene")
	ok(String(m.undo[-1].get("name", "")) == row_name, "the undo step is named after the command: '%s'" % String(m.undo[-1].get("name", "")))
	m._undo()
	ok(scene_json() == before, "one Ctrl+Z restores the scene byte for byte")
	run_row(row_name)   # and again, so the screenshot shows the mirrored state's own step name
	var mirrored_twice := scene_json()
	ok(String(m.ui_status.text).contains("one undo step"), "the status line says it was one undo step: '%s'" % String(m.ui_status.text).left(120))

	# BARS 4: a failing plugin is disabled, named, and the app keeps running
	var ti := rec_index("throws")
	m.plugins.set_enabled(ti, true)
	m._plugins_changed()
	var n_rows: int = m.ui_cmd.commands.size()
	run_row("Throws Plugin: Run boom")
	await process_frame
	var st := String(m.ui_status.text)
	ok(not rec_of("throws")["enabled"] and not rec_of("throws")["loaded"], "the failing plugin is switched off and unloaded")
	ok(String(rec_of("throws")["fault"]).contains("Throws Plugin") and String(rec_of("throws")["fault"]).contains("Next step"), "the panel row keeps the same named message")
	ok(st.contains("Throws Plugin") and st.contains("Next step") and st.contains("card index is wrong"),
		"its message names it and the next step: '%s'" % st.left(170))
	ok(m.ui_cmd.commands.size() < n_rows and not m.ui_cmd.commands.any(func(c): return c["name"].begins_with("Throws Plugin")),
		"its row leaves the S box")
	ok(m.is_inside_tree() and scene_json() == mirrored_twice and m.S.cards.size() == 2, "the app is still running with its scene (unchanged by the failure)")
	ok(not FileAccess.get_file_as_string(STATE).contains("throws"), "the switch is saved off (the next start stays off)")

	# BARS 5: clamped to the joint's limit
	var ci := rec_index("clamp_probe")
	m.plugins.set_enabled(ci, true)
	m._plugins_changed()
	var lim_hi: float = m.B.lim["lowerarm_l"]["bend"].y
	run_row("Clamp Probe: Run bend")
	var last: Dictionary = rec_of("clamp_probe")["obj"].last
	var held: float = float(m.S.cards[0]["pose"]["joints"]["lowerarm_l"]["bend"])
	var kept: Vector3 = last.get("value", Vector3.ZERO)
	ok(last["ok"] and last["clamped"] and absf(kept.x - lim_hi) < 0.001,
		"set_joint 500 deg is clamped to the elbow limit %.0f (clamped %s, kept %.1f)" % [lim_hi, last["clamped"], kept.x])
	ok(absf(held - lim_hi) < 0.001, "the card holds the limit (%.1f), not 500" % held)

	# BARS 6: writes only under the plugin's data folder
	var ei2 := rec_index("escape")
	m.plugins.set_enabled(ei2, true)
	m._plugins_changed()
	run_row("Escape Probe: Run write")
	var w: Dictionary = rec_of("escape")["obj"].last
	ok(not w["escape"]["ok"] and not w["absolute"]["ok"] and w["inside"]["ok"],
		"'../escape.txt' and '/abs.txt' are refused; 'sub/ok.txt' is written (%s | %s)" % [w["escape"]["why"].left(60), w["inside"]["path"]])
	ok(not FileAccess.file_exists(DATA + "/escape/escape.txt") and not FileAccess.file_exists("/abs.txt")
		and FileAccess.file_exists(DATA + "/escape/data/sub/ok.txt"),
		"no file outside the data folder; the inside one is in user://plugins_test_data/escape/data/")

	# BARS 7: a plugin left off never loads
	var sr := rec_of("sleeper")
	ok(not sr["enabled"] and not sr["loaded"] and sr["obj"] == null, "the plugin left off has no object and is not loaded")
	ok(not m.ui_cmd.commands.any(func(c): return c["name"].begins_with("Sleeper")), "and it adds no S box row")

	# the panel, with the example on (and the failure shown)
	m._plugins_changed()
	m.ui_plugins.open()
	await shot("pluginapi.png")
	ok(m.ui_plugins.visible, "the Plugins panel opens (screenshot: tmp/pluginapi.png)")
	m.ui_plugins.close()

	# the test's own folders are removed by the next run's setup, not left in the real user space; the state is the test's
	print("PLUGINS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
