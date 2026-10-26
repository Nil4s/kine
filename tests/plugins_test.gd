## godot --path . -s tests/plugins_test.gd     (GATES: windowed; it saves the Plugins panel screenshot)
## ROADMAP 100 PLUGIN API. Bars, stated before the run:
##   - EXAMPLE LOADS: examples/plugins/mirror_all_cards is found, OFF by default (not loaded), and loads when switched on;
##   - IN THE SEARCH AND ONE UNDO STEP: its command "Mirror All Cards: Mirror every card" is an S box row that "mirror all"
##     finds; running it reflects the right arm's angles onto the left, adds exactly ONE undo step, and one Ctrl+Z restores
##     the scene's JSON byte for byte;
##   - A PLUGIN THAT FAILS IS DISABLED, NAMED: api.fail(...) disables it; the message names the plugin and says "Next
##     step"; its row leaves the S box; the app is still running;
##   - A COMMAND THAT DOES NOT RETURN TRUE IS DISABLED, NAMED (the runtime-error path: GDScript gives null): same bars;
##   - CLAMPED: set_joint(0, "lowerarm_l", (500, 0, 0)) keeps the elbow at its limit (145), reports clamped = true;
##   - WRITES: write_data("sub/ok.txt") lands under <temp>/data/<name>/data/; "../escape.txt" and "/abs.txt" are refused;
##   - DISABLED NEVER LOADS: a plugin left off has no object and adds no S box row;
##   - ISOLATED: the plugins, the settings file and the data live in a temp folder user://zz_test_plugins_<pid>/ that the
##     test removes at the end. The real user folder and the real plugins.json are never read or written by this test.
## Screenshot: tmp/pluginapi.png (taken after the status toast has gone, so nothing sits over the panel).
extends SceneTree

const SHOTS := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"

var TMP := ""
var ROOT := ""
var DATA := ""
var STATE := ""
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## write one plugin folder of the test: its manifest and its plugin.gd
func make_plugin(folder: String, manifest: Dictionary, src: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + "/" + folder))
	var f := FileAccess.open(ROOT + "/" + folder + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	f = FileAccess.open(ROOT + "/" + folder + "/plugin.gd", FileAccess.WRITE)
	f.store_string(src)
	f.close()


func manifest(name: String, cid: String) -> Dictionary:
	return {"name": name, "version": "0.1.0", "author": "test", "api": 1,
		"commands": [{"id": cid, "name": "Run " + cid, "desc": "the test's command"}]}


## remove a folder and everything in it (the test's own temp folder only)
func rm_tree(p: String) -> void:
	var da := DirAccess.open(p)
	if da == null:
		return
	for d in da.get_directories():
		rm_tree(p + "/" + d)
	for f in da.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


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

	# the test's own temp folder: plugins, settings and data
	TMP = "user://zz_test_plugins_%d" % OS.get_process_id()
	ROOT = TMP + "/plugins"
	DATA = TMP + "/data"
	STATE = TMP + "/state.json"
	rm_tree(TMP)
	make_plugin("throws", manifest("Throws Plugin", "boom"),
		"extends RefCounted\n\nfunc command(api, id: String) -> bool:\n\tapi.fail(\"the card index is wrong: pass a card that exists\")\n\treturn false\n")
	make_plugin("no_return", manifest("Quiet Plugin", "hush"),
		"extends RefCounted\n\nfunc command(api, id: String):\n\tapi.log(\"this command never says it finished\")\n")
	make_plugin("clamp_probe", manifest("Clamp Probe", "bend"),
		"extends RefCounted\n\nvar last := {}\n\nfunc command(api, id: String) -> bool:\n\tlast = api.set_joint(0, \"lowerarm_l\", Vector3(500, 0, 0))\n\treturn true\n")
	make_plugin("escape", manifest("Escape Probe", "write"),
		"extends RefCounted\n\nvar last := {}\n\nfunc command(api, id: String) -> bool:\n\tlast = {\"escape\": api.write_data(\"../escape.txt\", \"x\"), \"absolute\": api.write_data(\"/abs.txt\", \"x\"), \"inside\": api.write_data(\"sub/ok.txt\", \"hi\")}\n\treturn true\n")
	make_plugin("sleeper", manifest("Sleeper", "nap"),
		"extends RefCounted\n\nfunc command(api, id: String) -> bool:\n\tapi.log(\"should never run: it is off\")\n\treturn true\n")

	m.plugins.configure([ROOT, "res://examples/plugins"], STATE, DATA)
	m.plugins.scan()
	m._plugins_changed()

	# BARS 1: the example is found, off, not loaded
	var ex := rec_of("mirror_all_cards")
	ok(not ex.is_empty() and ex["error"] == "" and not ex["enabled"] and not ex["loaded"],
		"the example is found, has a good manifest, and is OFF by default (not loaded)")
	ok(not m.ui_cmd.commands.any(func(c): return c["name"].begins_with("Mirror All Cards")),
		"a plugin that is off adds no S box row")
	var why: String = m.plugins.set_enabled(rec_index("mirror_all_cards"), true)
	ok(why == "" and rec_of("mirror_all_cards")["loaded"], "switched on: it loads (%s)" % why)
	m._plugins_changed()

	# BARS 2: the command is in the S box, and "mirror all" finds it
	var row_name := "Mirror All Cards: Mirror every card"
	ok(m.ui_cmd.commands.any(func(c): return c["name"] == row_name), "its command is an S box row named '%s'" % row_name)
	ok(m.ui_cmd.matches("", "mirror all").any(func(c): return c["name"] == row_name),
		"the search for 'mirror all' finds it")

	# BARS 3: one undo step, the pose reflected, one Ctrl+Z back to the same bytes
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
		"card 0: the left upper arm holds the right's angles reflected (bend %.1f side %.1f twist %.1f)" % [after_j["bend"], after_j["side"], after_j["twist"]])
	ok(scene_json() != before, "the mirror changed the scene")
	ok(String(m.undo[-1].get("name", "")) == row_name, "the undo step is named after the command: '%s'" % String(m.undo[-1].get("name", "")))
	m._undo()
	ok(scene_json() == before, "one Ctrl+Z restores the scene byte for byte")
	run_row(row_name)
	var mirrored_twice := scene_json()
	ok(String(m.ui_status.text).contains("one undo step"), "the status line says it was one undo step: '%s'" % String(m.ui_status.text).left(120))

	# BARS 4: a failing plugin is disabled, named, and the app keeps running
	m.plugins.set_enabled(rec_index("throws"), true)
	m._plugins_changed()
	var n_rows: int = m.ui_cmd.commands.size()
	run_row("Throws Plugin: Run boom")
	var st := String(m.ui_status.text)
	ok(not rec_of("throws")["enabled"] and not rec_of("throws")["loaded"], "the failing plugin is switched off and unloaded")
	ok(st.contains("Throws Plugin") and st.contains("Next step") and st.contains("card index is wrong"),
		"its message names it and the next step: '%s'" % st.left(170))
	ok(String(rec_of("throws")["fault"]).contains("Throws Plugin") and String(rec_of("throws")["fault"]).contains("Next step"),
		"the panel row keeps the same named message")
	ok(m.ui_cmd.commands.size() < n_rows and not m.ui_cmd.commands.any(func(c): return c["name"].begins_with("Throws Plugin")),
		"its row leaves the S box")
	ok(m.is_inside_tree() and scene_json() == mirrored_twice and m.S.cards.size() == 2, "the app is still running with its scene (unchanged by the failure)")
	ok(not FileAccess.get_file_as_string(STATE).contains("throws"), "the switch is saved off (the next start stays off)")

	# BARS 4b: a command that does not return true is disabled too (GDScript gives null for a runtime error)
	m.plugins.set_enabled(rec_index("no_return"), true)
	m._plugins_changed()
	run_row("Quiet Plugin: Run hush")
	var qst := String(m.ui_status.text)
	ok(not rec_of("no_return")["enabled"] and qst.contains("Quiet Plugin") and qst.contains("did not finish") and qst.contains("Next step"),
		"a command that does not return true is disabled with its name and the next step: '%s'" % qst.left(150))
	ok(m.is_inside_tree() and m.S.cards.size() == 2, "and the app keeps running")

	# BARS 5: clamped to the joint's limit
	m.plugins.set_enabled(rec_index("clamp_probe"), true)
	m._plugins_changed()
	var lim_hi: float = m.B.lim["lowerarm_l"]["bend"].y
	run_row("Clamp Probe: Run bend")
	var last: Dictionary = rec_of("clamp_probe")["obj"].last
	var kept: Vector3 = last.get("value", Vector3.ZERO)
	var held: float = float(m.S.cards[0]["pose"]["joints"]["lowerarm_l"]["bend"])
	ok(last["ok"] and last["clamped"] and absf(kept.x - lim_hi) < 0.001,
		"set_joint 500 deg is clamped to the elbow limit %.0f (clamped %s, kept %.1f)" % [lim_hi, last["clamped"], kept.x])
	ok(absf(held - lim_hi) < 0.001, "the card holds the limit (%.1f), not 500" % held)

	# BARS 6: writes only under the plugin's data folder
	m.plugins.set_enabled(rec_index("escape"), true)
	m._plugins_changed()
	run_row("Escape Probe: Run write")
	var w: Dictionary = rec_of("escape")["obj"].last
	ok(not w["escape"]["ok"] and not w["absolute"]["ok"] and w["inside"]["ok"],
		"'../escape.txt' and '/abs.txt' are refused; 'sub/ok.txt' is written (%s | %s)" % [w["escape"]["why"].left(60), w["inside"]["path"]])
	ok(not FileAccess.file_exists(DATA + "/escape/escape.txt") and not FileAccess.file_exists("/abs.txt")
		and FileAccess.file_exists(DATA + "/escape/data/sub/ok.txt"),
		"no file outside the data folder; the inside one is in <temp>/data/escape/data/")

	# BARS 7: a plugin left off never loads
	var sr := rec_of("sleeper")
	ok(not sr["enabled"] and not sr["loaded"] and sr["obj"] == null, "the plugin left off has no object and is not loaded")
	ok(not m.ui_cmd.commands.any(func(c): return c["name"].begins_with("Sleeper")), "and it adds no S box row")

	# the panel, with the example on (and the failures shown). The status toast is waited out, so none sits over the panel
	m._plugins_changed()
	await create_timer(float(m.TOAST_T) + 0.5).timeout
	m.ui_plugins.open()
	await shot("pluginapi.png")
	ok(m.ui_plugins.visible, "the Plugins panel opens (screenshot: tmp/pluginapi.png)")
	m.ui_plugins.close()

	# the temp folder goes: plugins, settings and data
	rm_tree(TMP)
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP)), "the test's temp folder is removed")
	print("PLUGINS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
