## godot --path . -s tests/plugins2_test.gd     (L70 PLUGIN2, ROADMAP_400 track O: scripting / addons). Bars, written before the code:
##   - REACH: every documented API call (PluginAPI.DOCUMENTED) is called by the suite (coverage 100 %, measured on the call log);
##     the list equals the public methods of PluginAPI (an undocumented new method fails); PLANTED: a fake name in the list
##     is reported missing, so the coverage check can fail; docs/PLUGINS.md names every call;
##   - EVERY EDIT IS ONE UNDO STEP: each mutating call as its own command adds exactly 1 undo step and one Ctrl+Z restores the
##     scene JSON byte for byte; the combined "all" command is 1 step too; the new examples are 1 step each;
##   - ISOLATION: a plugin that fails after 2 edits is disabled with a named message and its edits are rolled back (scene bytes
##     and undo count as before); a planted infinite loop (pure spin) and one that keeps calling the api are stopped waiting after
##     timeout_ms (wall time <= timeout + 1500 ms), named, rolled back, the app runs the next command, and the runaway one cannot
##     change the scene any more (0 changes in 300 ms). A real GDScript runtime error prints SCRIPT ERROR, which fails every suite,
##     so the crash cases are api.fail, a command that returns without true, and the halfway failure;
##   - PERMISSIONS: a plugin without "files" cannot write_file / read_file / export / run_tool (0 files made anywhere in the
##     temp tree); with "files" every escape (.., absolute, C:, res://, user://, backslash, scripts/) is refused (0 files outside
##     <project>/exports|scenes|poses|plugin_out), the in-project ones work; an unknown permission in a manifest is refused;
##   - INSTALL: from a folder and from a zip (off by default, files copied); a zip with a ../ entry is refused with 0 files
##     outside; a bad manifest is refused; an update keeps the enable switch, the settings and the data, and shows old -> new
##     version; a downgrade is refused; uninstall removes the folder;
##   - EXAMPLES: loop_cards, batch_rename and export_counter run with numeric effects.
## The suite works in a temp folder user://zz_test_plugins2_<pid>/ (the project root of the test too) and removes it at the end.
extends SceneTree

const FIX := "res://tests/plugins2_fixtures/"
const STOP := "user://zz_plugins2_stop"

var TMP := ""
var ROOT := ""
var DATA := ""
var STATE := ""
var PROJ := ""
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func rm_tree(p: String) -> void:
	var da := DirAccess.open(p)
	if da == null:
		return
	for d in da.get_directories():
		rm_tree(p + "/" + d)
	for f in da.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func list_tree(p: String) -> Array:
	var out := []
	var da := DirAccess.open(p)
	if da == null:
		return out
	for d in da.get_directories():
		out.append_array(list_tree(p + "/" + d))
	for f in da.get_files():
		out.append(p + "/" + f)
	out.sort()
	return out


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func rec_of(folder: String) -> Dictionary:
	for r in m.plugins.found:
		if r["folder"] == folder:
			return r
	return {}


func idx(folder: String) -> int:
	for i in m.plugins.found.size():
		if m.plugins.found[i]["folder"] == folder:
			return i
	return -1


func scene_json() -> String:
	return JSON.stringify(m._scene_dict())


func run_row(row_name: String) -> void:
	m.ui_cmd.shown = []
	for c in m.ui_cmd.commands:
		if c["name"] == row_name:
			m.ui_cmd.shown = [c]
	m.ui_cmd._run(0)


func install_enable(folder: String, src: String) -> Dictionary:
	var r: Dictionary = m.plugins.install(src)
	if r["ok"]:
		m.plugins.set_enabled(idx(r["folder"]), true)
		m._plugins_changed()
	return r


## a fresh scene: 3 cards, one box prop, one head key at 0.5 s
func fresh_scene() -> void:
	m.S.cards.clear()
	m.S.props.clear()
	m.S.part_keys = {}
	m._pose_words("raise the right arm 90")
	m._card_add()
	m._pose_words("bend the left elbow 45")
	m._card_add()
	m._pose_words("raise the left arm 60")
	m._card_add()
	m.S.props.append(Props.make("box", Props.xf_at(Vector3(1, 0, 0), 0.0)))
	m.S.part_keys = {"head": [{"t": 0.5, "v": Vector3(10, 0, 0)}]}


func mf(name: String, version: String, perms := [], api := 2) -> String:
	return JSON.stringify({"name": name, "version": version, "author": "t", "api": api, "permissions": perms,
		"commands": [{"id": "go", "name": "go"}]})


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	TMP = "user://zz_test_plugins2_%d" % OS.get_process_id()
	ROOT = TMP + "/plugins"
	DATA = TMP + "/data"
	STATE = TMP + "/state.json"
	PROJ = TMP + "/project"
	rm_tree(TMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STOP))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROJ))
	m.plugins.configure([ROOT, "res://examples/plugins"], STATE, DATA)
	m.plugins.project_root = PROJ
	m.plugins.timeout_ms = 700
	m.plugins.scan()
	fresh_scene()

	# ---- INSTALL from a folder: the probe fixture (off by default) --------------------------------------------------------
	var r: Dictionary = m.plugins.install(FIX + "probe")
	ok(r["ok"] and r["action"] == "installed" and r["folder"] == "probe", "install from a folder: %s" % str(r.get("why", "")))
	ok(not rec_of("probe").is_empty() and not rec_of("probe")["enabled"] and not rec_of("probe")["loaded"],
		"an installed plugin is OFF and not loaded")
	ok(FileAccess.file_exists(ROOT + "/probe/plugin.gd") and FileAccess.file_exists(ROOT + "/probe/manifest.json"),
		"its files are copied under the plugins folder")
	ok(rec_of("probe")["manifest"]["permissions"] == ["files", "export", "tools"], "its permissions are read from the manifest")
	m.plugins.set_enabled(idx("probe"), true)
	m._plugins_changed()

	# ---- the probe: every call, one command, one undo step -----------------------------------------------------------------
	m.plugins.host["mesh"] = func(): return KMeshPrims.cube(Vector3.ONE, 2)
	var km: KMesh = KMeshPrims.cube(Vector3.ONE, 2)
	var before := scene_json()
	var u0: int = m.undo.size()
	var t0 := Time.get_ticks_msec()
	run_row("Probe: All")
	var L: Dictionary = rec_of("probe")["obj"].last
	ok(not L.is_empty(), "the probe's 'all' command ran to its end (%d ms)" % (Time.get_ticks_msec() - t0))
	ok(m.undo.size() == u0 + 1, "the combined command is exactly ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	ok(L["ver"] == PluginAPI.VERSION and L["n"] == 3 and L["cards"].size() == 3 and L["joints"].size() > 20, "api_version / card_count / cards / joint_names")
	ok(L["perm_files"] == true and L["perm_nope"] == false, "has_permission is true for a granted one only")
	var info: Dictionary = L["info"]
	ok(info["cards"] == 3 and absf(float(info["length"]) - m.S.length()) < 0.0001 and info["objects"] == 1 and info["keyed_joints"] == 1
		and String(info["name"]) == m.S.name, "scene_info: cards 3, length %.3f s, objects 1, keyed joints 1" % float(info["length"]))
	ok(L["objs0"].size() == 1 and L["objs0"][0]["kind"] == "box" and (L["objs0"][0]["pos"] as Vector3).distance_to(Vector3(1, 0, 0)) < 0.001,
		"objects(): the box at (1,0,0)")
	ok(L["add_obj"]["ok"] and L["add_obj"]["index"] == 1 and not L["bad_obj"]["ok"] and String(L["bad_obj"]["why"]).contains("no_such_kind_zz"),
		"add_object adds a crate (index 1); an unknown kind is refused and named")
	ok(L["move_obj"]["ok"] and (L["objs1"][0]["pos"] as Vector3).distance_to(Vector3(2, 0, 1)) < 0.001, "move_object: the box is at (2,0,1)")
	ok(L["rm_obj"]["ok"] and m.S.props.size() == 1, "remove_object: the crate is gone again")
	ok(L["setj"]["ok"] and L["add_card"]["ok"] and L["add_card"]["index"] == 3 and L["rm_card"]["ok"] and m.S.cards.size() == 3, "set_joint / add_card / remove_card")
	ok(L["timing"]["ok"] and absf(float(m.S.cards[0]["hold"]) - 0.9) < 1e-6 and absf(float(m.S.cards[0]["move"]) - 0.7) < 1e-6, "set_timing: hold 0.9, move 0.7")
	ok(L["rename"]["ok"] and String(m.S.cards[0]["name"]) == "Renamed", "rename_card")
	var lim: Vector3 = L["setk"]["value"]
	ok(L["setk"]["ok"] and L["setk"]["clamped"] and lim.x < 500.0 and lim.x > 0.0, "set_key clamps 500 deg to the head's limit (%.1f)" % lim.x)
	ok(L["keys"].size() == 2 and absf(float(L["keys"][0]["t"]) - 0.25) < 1e-6 and absf(float(L["keys"][1]["t"]) - 0.5) < 1e-6, "keys(): sorted by time, 2 keys")
	ok(L["rmk"]["ok"] and (m.S.part_keys["head"] as Array).size() == 1, "remove_key: one key left")
	var mi: Dictionary = L["mesh"]
	ok(mi["ok"] and mi["verts"] == km.vert_count() and mi["faces"] == km.face_count()
		and ((mi["bounds_max"] as Vector3) - (mi["bounds_min"] as Vector3)).distance_to(Vector3.ONE) < 0.001,
		"mesh_info: %d verts, %d faces, bounds 1 x 1 x 1" % [mi["verts"], mi["faces"]])
	ok(L["verts"]["ok"] and (L["verts"]["vertices"] as PackedVector3Array).size() == 10 and L["verts"]["truncated"], "mesh_vertices(10): 10 points, truncated flag")
	ok(L["sel0"].has("card") and L["selc"]["ok"] and L["selj"]["ok"] and L["sel1"]["card"] == 1 and L["sel1"]["joint"] == "hand_r", "selection / select_card / select_joint")
	ok(L["tool"]["ok"] and m.sel == "head", "run_tool('sel=head') ran the app's own tool (the head is picked)")
	ok(not L["tool_bad"]["ok"] and String(L["tool_bad"]["why"]).contains("not allowed"), "run_tool('quit') is refused: '%s'" % String(L["tool_bad"]["why"]).left(80))
	ok(L["exp"]["ok"] and int(L["exp"]["bytes"]) > 200 and FileAccess.get_file_as_string(L["exp"]["path"]).begins_with("HIERARCHY"),
		"export('bvh') wrote %d bytes of BVH to %s" % [int(L["exp"]["bytes"]), String(L["exp"]["path"]).get_file()])
	ok(not L["exp_bad"]["ok"], "export of an unknown kind is refused")
	ok(L["set"]["ok"] and L["get"] == 7 and L["get_def"] == "dflt", "set_setting / get_setting round-trip (7) and default")
	ok(L["wd"]["ok"] and L["rd"]["text"] == "hi", "write_data / read_data")
	ok(L["wf"]["ok"] and L["rf"]["text"] == "proj" and FileAccess.file_exists(PROJ + "/exports/p.txt"), "write_file / read_file inside <project>/exports")
	ok(String(m.ui_status.text).contains("Probe"), "log() reached the status line")
	m._undo()
	ok(scene_json() == before, "one Ctrl+Z restores the scene byte for byte after the combined command")

	# ---- each mutating call as its own command: exactly one undo step, bytes back -------------------------------------------
	var worst := 0
	for cid in ["set_joint", "add_card", "remove_card", "set_timing", "rename_card", "move_object", "add_object", "remove_object", "set_key", "remove_key", "tool"]:
		before = scene_json()
		u0 = m.undo.size()
		run_row("Probe: " + cid)
		var d: int = m.undo.size() - u0
		var changed := scene_json() != before
		m._undo()
		var back := scene_json() == before
		ok(d == 1 and changed and back, "%s: %d undo step, changed %s, one Ctrl+Z restores bytes %s" % [cid, d, changed, back])
		worst = maxi(worst, absi(d - 1))
	ok(worst == 0, "every one-call command was exactly one undo step")

	# ---- ISOLATION ----------------------------------------------------------------------------------------------------------
	install_enable("halfway", FIX + "halfway")
	before = scene_json()
	u0 = m.undo.size()
	run_row("Halfway: go")
	var st := String(m.ui_status.text)
	ok(not rec_of("halfway")["enabled"] and st.contains("Halfway") and st.contains("Next step") and st.contains("halfway on purpose"),
		"a plugin that fails after 2 edits is disabled and named: '%s'" % st.left(120))
	ok(scene_json() == before and m.undo.size() == u0, "its 2 edits are rolled back: scene bytes and undo count (%d) as before" % u0)

	for spin in ["spin", "spinapi"]:
		install_enable(spin, FIX + spin)
		before = scene_json()
		u0 = m.undo.size()
		var n_rows: int = m.ui_cmd.commands.size()
		var w0 := Time.get_ticks_msec()
		run_row("%s: go" % ("Spin" if spin == "spin" else "Spin Api"))
		var wall := Time.get_ticks_msec() - w0
		ok(wall <= m.plugins.timeout_ms + 1500 and wall >= m.plugins.timeout_ms - 100, "%s: stopped waiting after %d ms (timeout %d ms)" % [spin, wall, m.plugins.timeout_ms])
		var ts := String(m.ui_status.text)
		ok(not rec_of(spin)["enabled"] and ts.contains("Next step") and ts.contains("longer than"), "%s: disabled, named, clear message: '%s'" % [spin, ts.left(130)])
		ok(m.ui_cmd.commands.size() < n_rows, "%s: its row left the S box" % spin)
		ok(scene_json() == before and m.undo.size() == u0, "%s: its edits are rolled back (bytes and undo count)" % spin)
		var snap := scene_json()
		await create_timer(0.3).timeout
		ok(scene_json() == snap, "%s: the runaway loop cannot change the scene any more (0 changes in 300 ms)" % spin)
		# the app is usable: another command runs, is one undo step
		u0 = m.undo.size()
		run_row("Probe: set_joint")
		ok(m.undo.size() == u0 + 1 and String(m.ui_status.text).contains("one undo step"), "%s: the next command still runs and is one undo step" % spin)
		m._undo()
		ok(scene_json() == before, "%s: and Ctrl+Z still works" % spin)
	ok(m.is_inside_tree() and m.S.cards.size() == 3, "the app is still running with its scene")

	# ---- PERMISSIONS -------------------------------------------------------------------------------------------------------
	install_enable("nofiles", FIX + "nofiles")
	var tree0 := list_tree(TMP)
	var esc_n := "C:/Temp/kine_plugin_escape_n.txt"
	run_row("No Files: try")
	var N: Dictionary = rec_of("nofiles")["obj"].last
	var bad_n := 0
	for k in ["inside", "up", "abs", "read", "export", "tool"]:
		if N[k]["ok"] or not String(N[k]["why"]).contains("permission"):
			bad_n += 1
	ok(bad_n == 0, "a plugin without permissions: write_file, read_file, export and run_tool are all refused naming the permission (%d wrong)" % bad_n)
	ok(list_tree(TMP) == tree0 and not FileAccess.file_exists(esc_n) and not FileAccess.file_exists(PROJ + "/exports/n.txt"), "...and it made 0 files anywhere")

	install_enable("withfiles", FIX + "withfiles")
	tree0 = list_tree(TMP)
	var outside_before := FileAccess.file_exists("C:/Temp/kine_plugin_escape_w.txt")
	run_row("With Files: try")
	var W: Dictionary = rec_of("withfiles")["obj"].last
	var refused := 0
	for k in ["up", "up2", "abs", "slash", "back", "scripts", "root", "res", "user", "read_up"]:
		if not W[k]["ok"]:
			refused += 1
	ok(refused == 10, "with 'files': 10 of 10 escapes refused (.., absolute, C:, res://, user://, backslash, scripts/, project root) (%d)" % refused)
	ok(W["ok"]["ok"] and W["scenes"]["ok"] and W["read_ok"]["text"] == "x", "with 'files': exports/ and scenes/ (new subfolder) work, and read back")
	ok(not W["export"]["ok"] and String(W["export"]["why"]).contains("permission"), "'files' does not grant 'export'")
	var added := list_tree(TMP).filter(func(p): return not tree0.has(p))
	var stray := added.filter(func(p): return not (String(p).begins_with(PROJ + "/exports/") or String(p).begins_with(PROJ + "/scenes/")))
	ok(added.size() == 2 and stray.is_empty() and not FileAccess.file_exists("C:/Temp/kine_plugin_escape_w.txt") and not outside_before,
		"exactly the 2 allowed files were made, %d stray, none outside the project" % stray.size())
	ok(not FileAccess.file_exists(TMP + "/w.txt") and not FileAccess.file_exists(PROJ + "/w.txt") and not FileAccess.file_exists("user://w.txt"),
		"no w.txt at the temp root, the project root or user://")
	# a typo in permissions is refused (PLANTED: "file" for "files")
	write(TMP + "/src/typo/manifest.json", mf("Typo", "1.0.0", ["file"]))
	write(TMP + "/src/typo/plugin.gd", "extends RefCounted\nfunc command(api, id):\n\treturn true\n")
	r = m.plugins.install(TMP + "/src/typo")
	ok(not r["ok"] and String(r["why"]).contains("file") and String(r["why"]).contains("Next step") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(ROOT + "/typo")),
		"an unknown permission is refused, nothing installed: '%s'" % String(r.get("why", "")).left(100))

	# ---- INSTALL: zip, evil zip, bad manifest, update, downgrade, uninstall ------------------------------------------------
	var zp := ProjectSettings.globalize_path(TMP + "/zipped_plug.zip")
	var zw := ZIPPacker.new()
	zw.open(zp)
	zw.start_file("zipped_plug/manifest.json")
	zw.write_file(mf("Zipped", "1.0.0", ["export"]).to_utf8_buffer())
	zw.close_file()
	zw.start_file("zipped_plug/plugin.gd")
	zw.write_file("extends RefCounted\nfunc command(api, id):\n\treturn true\n".to_utf8_buffer())
	zw.close_file()
	zw.close()
	r = m.plugins.install(zp)
	ok(r["ok"] and r["folder"] == "zipped_plug" and FileAccess.file_exists(ROOT + "/zipped_plug/plugin.gd") and not rec_of("zipped_plug")["enabled"],
		"install from a zip: %s (off by default)" % str(r.get("why", r.get("folder", ""))))
	var evil := ProjectSettings.globalize_path(TMP + "/evil_plug.zip")
	zw = ZIPPacker.new()
	zw.open(evil)
	zw.start_file("evil_plug/manifest.json")
	zw.write_file(mf("Evil", "1.0.0").to_utf8_buffer())
	zw.close_file()
	zw.start_file("evil_plug/plugin.gd")
	zw.write_file("extends RefCounted\nfunc command(api, id):\n\treturn true\n".to_utf8_buffer())
	zw.close_file()
	zw.start_file("evil_plug/../../evil.txt")
	zw.write_file("x".to_utf8_buffer())
	zw.close_file()
	zw.close()
	tree0 = list_tree(TMP)
	r = m.plugins.install(evil)
	ok(not r["ok"] and String(r["why"]).contains("..") and list_tree(TMP) == tree0 and not FileAccess.file_exists(TMP + "/evil.txt"),
		"a zip with a ../ entry is refused and 0 files were made: '%s'" % String(r.get("why", "")).left(90))
	write(TMP + "/src/badapi/manifest.json", mf("Bad", "1.0.0", [], 99))
	write(TMP + "/src/badapi/plugin.gd", "extends RefCounted\n")
	r = m.plugins.install(TMP + "/src/badapi")
	ok(not r["ok"] and String(r["why"]).contains("api"), "api 99 is refused: '%s'" % String(r.get("why", "")).left(80))
	r = m.plugins.install(TMP + "/src")
	ok(not r["ok"], "a folder with no manifest is refused")
	write(TMP + "/src/old1/manifest.json", mf("Old One", "1.0.0", [], 1))
	write(TMP + "/src/old1/plugin.gd", "extends RefCounted\nfunc command(api, id):\n\treturn true\n")
	r = m.plugins.install(TMP + "/src/old1")
	ok(r["ok"], "an api 1 manifest still installs (backward compatible)")
	# update keeps switch, settings, data
	write(TMP + "/src/upd/manifest.json", mf("Upd", "1.0.0"))
	write(TMP + "/src/upd/plugin.gd", "extends RefCounted\nfunc command(api, id):\n\tapi.set_setting('volume', 11)\n\tapi.write_data('keep.txt', 'kept')\n\treturn true\n")
	install_enable("upd", TMP + "/src/upd")
	run_row("Upd: go")
	write(TMP + "/src2/upd/manifest.json", mf("Upd", "1.1.0"))
	write(TMP + "/src2/upd/plugin.gd", "extends RefCounted\nfunc command(api, id):\n\tapi.log('v11 sees volume %d' % api.get_setting('volume', 0))\n\treturn api.get_setting('volume', 0) == 11\n")
	r = m.plugins.install(TMP + "/src2/upd")
	ok(r["ok"] and r["action"] == "updated" and r["from_version"] == "1.0.0" and r["version"] == "1.1.0", "update 1.0.0 -> 1.1.0 reported (%s)" % str(r.get("action", r.get("why", ""))))
	ok(rec_of("upd")["enabled"] and rec_of("upd")["loaded"] and rec_of("upd")["manifest"]["version"] == "1.1.0", "the update kept the enable switch and loaded the new code")
	m._plugins_changed()
	run_row("Upd: go")
	ok(rec_of("upd")["enabled"] and String(m.ui_status.text).contains("v11 sees volume 11"), "the setting survived the update: the new version read volume 11")
	ok(FileAccess.get_file_as_string(DATA + "/upd/data/keep.txt") == "kept", "the plugin's data survived the update")
	r = m.plugins.install(TMP + "/src/upd")
	ok(not r["ok"] and String(r["why"]).contains("older") and rec_of("upd")["manifest"]["version"] == "1.1.0", "a downgrade is refused and the installed version stays 1.1.0")
	r = m.plugins.uninstall(idx("upd"))
	ok(r["ok"] and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(ROOT + "/upd")) and rec_of("upd").is_empty(), "uninstall removes the folder and the entry")
	ok(not FileAccess.get_file_as_string(STATE).contains("\"upd\""), "...and its switch")
	r = m.plugins.uninstall(idx("mirror_all_cards"))
	ok(not r["ok"], "a shipped example cannot be uninstalled")

	# ---- COVERAGE and DOCS -----------------------------------------------------------------------------------------------
	var seen: Dictionary = m.plugins.call_log
	var miss := []
	for nm in PluginAPI.DOCUMENTED:
		if not seen.has(nm):
			miss.append(nm)
	ok(miss.is_empty(), "every documented API call was exercised: %d of %d (missing %s)" % [PluginAPI.DOCUMENTED.size() - miss.size(), PluginAPI.DOCUMENTED.size(), str(miss)])
	var planted := PluginAPI.DOCUMENTED.duplicate()
	planted.append("zz_fake_call")
	ok(planted.filter(func(nm): return not seen.has(nm)) == ["zz_fake_call"], "PLANTED: a documented call nobody calls is reported missing")
	var pub := []
	for md in (load("res://scripts/plugin_api.gd") as GDScript).get_script_method_list():
		var nm: String = md["name"]
		if not nm.begins_with("_"):
			pub.append(nm)
	pub.sort()
	var docd := PluginAPI.DOCUMENTED.duplicate()
	docd.sort()
	ok(pub == docd, "DOCUMENTED equals the public methods of PluginAPI (%d vs %d)" % [docd.size(), pub.size()])
	var md_text := FileAccess.get_file_as_string("res://docs/PLUGINS.md")
	var undocumented := PluginAPI.DOCUMENTED.filter(func(nm): return not md_text.contains(nm + "("))
	ok(undocumented.is_empty(), "docs/PLUGINS.md names every call (%d of %d; missing %s)" % [PluginAPI.DOCUMENTED.size() - undocumented.size(), PluginAPI.DOCUMENTED.size(), str(undocumented)])

	# ---- EXAMPLES ----------------------------------------------------------------------------------------------------------
	ok(FileAccess.file_exists("res://examples/plugins/loop_cards/plugin.gd") and FileAccess.file_exists("res://examples/plugins/batch_rename/plugin.gd")
		and FileAccess.file_exists("res://examples/plugins/export_counter/plugin.gd") and FileAccess.file_exists("res://examples/plugins/mirror_all_cards/plugin.gd"),
		"4 example plugins ship under examples/plugins/")
	for ex in ["loop_cards", "batch_rename", "export_counter"]:
		ok(not rec_of(ex).is_empty() and rec_of(ex)["error"] == "" and not rec_of(ex)["enabled"], "%s: found, manifest good, off by default (%s)" % [ex, rec_of(ex).get("error", "")])
		m.plugins.set_enabled(idx(ex), true)
	m._plugins_changed()
	fresh_scene()
	before = scene_json()
	u0 = m.undo.size()
	var c0: Dictionary = (m.S.cards[0]["pose"]["joints"] as Dictionary).duplicate(true)
	run_row("Loop Cards: Close the loop")
	ok(m.undo.size() == u0 + 1 and m.S.cards.size() == 4 and JSON.stringify(m.S.cards[3]["pose"]["joints"]) == JSON.stringify(c0),
		"loop_cards: 3 -> 4 cards, the last pose equals the first, 1 undo step")
	m._undo()
	ok(scene_json() == before, "loop_cards: Ctrl+Z restores bytes")
	u0 = m.undo.size()
	run_row("Batch Rename: Number the cards")
	var names: Array = m.S.cards.map(func(c): return String(c["name"]))
	ok(m.undo.size() == u0 + 1 and names == ["Take 01", "Take 02", "Take 03"], "batch_rename: %s, 1 undo step" % str(names))
	m._undo()
	ok(scene_json() == before, "batch_rename: Ctrl+Z restores bytes")
	u0 = m.undo.size()
	run_row("Export Counter: Export BVH")
	run_row("Export Counter: Export BVH")
	var exdir := DATA + "/export_counter/exports"
	var nfiles := 0
	for f in DirAccess.get_files_at(exdir):
		if f.ends_with(".bvh"):
			nfiles += 1
	var cnt: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA + "/export_counter/settings.json")).get("exports", 0)
	ok(nfiles >= 1 and int(cnt) == 2 and m.undo.size() == u0, "export_counter: BVH written (%d file), counter setting = %d after 2 runs, 0 undo steps (it edits nothing)" % [nfiles, int(cnt)])

	# ---- end: let the runaway loops end, remove the temp ---------------------------------------------------------------
	write(STOP, "stop")
	await create_timer(0.5).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STOP))
	rm_tree(TMP)
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP)), "the test's temp folder is removed")
	print("plugins2: %d fail" % fails)
	TestFiles.cleanup()
	quit(fails)
