## USER PLUGINS (ROADMAP 100). Finds the plugin folders, checks each manifest.json, loads plugin.gd ONLY when the plugin
## is enabled, and runs its commands. Each command is one undo step (main's _plugin_run opens it). A plugin that reports
## a failure (api.fail) is disabled with a message that names it and the next step; the app keeps running.
## Plugins are DISABLED by default. The enable switches live in user://plugins.json (a preference, not work).
## A plugin folder: manifest.json + plugin.gd. docs/PLUGINS.md is the reference. The example is examples/plugins/.
class_name Plugins
extends RefCounted

const MANIFEST_KEYS := ["name", "version", "author", "api", "commands"]

## the folders, the settings file and the data root are PARAMETERS (configure): the app passes the user's, a test passes its
## own temp folders, so a test never reads or writes the real user folder or the real plugins.json
var roots: Array = []                # the folders searched, in order (the app: user://plugins, then res://examples/plugins)
var data_root := ""                  # plugin data is <data_root>/<name>/data/
var state_file := ""                 # the enable switches (a preference, not work)
var host: Dictionary = {}            # "scene", "clamp", "has_joint", "begin", "say", "changed", "run": Callables from main
var found: Array = []                # one record per plugin folder, see _record
var project_root := "res://"         # write_file / read_file work inside this folder (the app: the project; a test: a temp folder)
var timeout_ms := 5000               # a command that runs longer is stopped waiting for, rolled back, and its plugin disabled
var call_log: Dictionary = {}        # every api call made so far, name -> count (the tests read it for coverage)
var _abandoned: Array = []           # threads of commands that ran past the limit: kept alive, never joined


func configure(folders: Array, settings_file: String, data_folder: String) -> void:
	roots = folders
	state_file = settings_file
	data_root = data_folder


## read every root again (the folders, their manifests, the enable switches). Loads nothing: a disabled plugin is never loaded
func scan() -> void:
	for rec in found:
		unload(rec)
	found = []
	var on := _read_state()
	for root in roots:
		var da := DirAccess.open(root)
		if da == null:
			continue
		var dirs := da.get_directories()
		dirs.sort()
		for d in dirs:
			found.append(_record(root, d, on))
	for rec in found:   # the ones switched on come back on; one that no longer loads is switched off, with its message
		if rec["enabled"]:
			var why := load_plugin(rec)
			if why != "":
				rec["enabled"] = false
				rec["error"] = why
				_save_state()   # a switch that no longer works is saved off; nothing else is written by a scan


func _record(root: String, folder: String, on: Dictionary) -> Dictionary:
	var rec := {"folder": folder, "dir": root + "/" + folder, "source": "example" if root.begins_with("res://") else "installed",
		"manifest": {}, "error": "", "enabled": bool(on.get(folder, false)), "loaded": false, "obj": null, "api": null,
		"fault": ""}
	var m: Variant = null
	if FileAccess.file_exists(rec["dir"] + "/manifest.json"):
		m = JSON.parse_string(FileAccess.get_file_as_string(rec["dir"] + "/manifest.json"))
	else:
		rec["error"] = "has no manifest.json: add one next to plugin.gd (docs/PLUGINS.md shows the fields)"
		return rec
	var why := check_manifest(m, folder)
	if why != "":
		rec["error"] = why
		rec["enabled"] = false
		return rec
	rec["manifest"] = m
	return rec


## "" when the manifest is good, else the message that names the fault and the next step
static func check_manifest(m: Variant, folder: String) -> String:
	if not (m is Dictionary):
		return "manifest.json is not a JSON object: it must start with { and hold \"name\", \"version\", \"author\", \"api\", \"commands\""
	var d: Dictionary = m
	for k in MANIFEST_KEYS:
		if not d.has(k):
			return "manifest.json has no \"%s\": add it (docs/PLUGINS.md lists the fields)" % k
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	if re.search(folder) == null:
		return "the folder name '%s' must be lower case letters, digits and _, starting with a letter: rename the folder" % folder
	if String(d["name"]).strip_edges() == "":
		return "manifest.json \"name\" is empty: give the plugin a name people will see in the S box"
	if not PluginAPI.SUPPORTED.has(int(d["api"])):
		return "needs api %d and this app has api %d: ask the author for a version that uses api %d" % [int(d["api"]), PluginAPI.VERSION, PluginAPI.VERSION]
	if d.has("permissions"):
		if not (d["permissions"] is Array):
			return "manifest.json \"permissions\" must be a list like [\"files\"]: the known ones are %s" % ", ".join(PluginAPI.PERMISSIONS)
		for p in d["permissions"]:
			if not PluginAPI.PERMISSIONS.has(String(p)):
				return "manifest.json asks for an unknown permission '%s': the known ones are %s" % [String(p), ", ".join(PluginAPI.PERMISSIONS)]
	if not (d["commands"] is Array) or (d["commands"] as Array).is_empty():
		return "manifest.json \"commands\" must list at least one command: {\"id\", \"name\", \"desc\"}"
	for c in d["commands"]:
		if not (c is Dictionary) or not c.has("id") or not c.has("name"):
			return "every entry in manifest.json \"commands\" needs an \"id\" and a \"name\""
		if re.search(String(c["id"])) == null:
			return "command id '%s' must be lower case letters, digits and _, starting with a letter" % String(c["id"])
	return ""


## turn plugin i on or off. Returns "" on success, else the message (the plugin stays off). Saves the switch
func set_enabled(i: int, on: bool) -> String:
	var rec: Dictionary = found[i]
	var why := ""
	if on:
		rec["fault"] = ""
		why = load_plugin(rec)
		rec["enabled"] = why == ""
	else:
		unload(rec)
		rec["enabled"] = false
	_save_state()
	_changed()
	return why


## compile plugin.gd and make its object. Nothing runs yet. "" = loaded; else the message with the next step
func load_plugin(rec: Dictionary) -> String:
	if rec["error"] != "":
		return _msg(rec, "is not loaded: " + String(rec["error"]), "fix the manifest, then enable it again")
	if rec["loaded"]:
		return ""
	var path: String = rec["dir"] + "/plugin.gd"
	if not FileAccess.file_exists(path):
		return _msg(rec, "has no plugin.gd", "add plugin.gd next to manifest.json (docs/PLUGINS.md)")
	var sc := GDScript.new()
	sc.source_code = FileAccess.get_file_as_string(path)
	var e := sc.reload()
	if e != OK:
		return _msg(rec, "plugin.gd does not compile (Godot error %d): the script has a syntax error" % e,
			"open plugin.gd, fix the error the console shows, then enable it again")
	var obj = sc.new()
	if obj == null or not obj.has_method("command"):
		return _msg(rec, "plugin.gd has no func command(api, id)", "add func command(api, id) that runs the commands in manifest.json")
	var api := PluginAPI.new(rec["folder"], host, data_root, project_root, rec["manifest"].get("permissions", []), call_log)
	api.title = String(rec["manifest"]["name"])
	rec["obj"] = obj
	rec["api"] = api
	rec["loaded"] = true
	return ""


func unload(rec: Dictionary) -> void:
	rec["obj"] = null
	rec["api"] = null
	rec["loaded"] = false


## run command cid of plugin i. "" = it ran; else the message. A command that calls api.fail disables its plugin
func run(i: int, cid: String) -> String:
	var rec: Dictionary = found[i]
	if not rec["enabled"] or not rec["loaded"]:
		return _msg(rec, "is off, so its command did not run", "turn it on in Plugins, then run the command again")
	var api: PluginAPI = rec["api"]
	api.failed = false
	api.fail_msg = ""
	# The command runs on a WORKER thread: every api call that needs the app is carried out here, on the main thread, while we
	# wait. A command that is still running after timeout_ms is abandoned (GDScript cannot kill a thread): its api is revoked,
	# so it can change nothing any more, and its plugin is disabled. A GDScript runtime error (a null value, a bad index)
	# cannot be caught: the call then gives null, which is not true, so it is a failure too, and the console shows the line
	var box := {"done": false, "ret": null}
	var obj = rec["obj"]
	var th := Thread.new()
	th.start(func():
		box["ret"] = obj.command(api, cid)
		box["done"] = true)
	var t0 := Time.get_ticks_msec()
	while not box["done"] and Time.get_ticks_msec() - t0 < timeout_ms:
		api._service()
		OS.delay_usec(300)
	if not box["done"]:
		api.revoked = true
		_abandoned.append(th)
		_rollback()
		return _disable(rec, "ran longer than %.1f s in command '%s' and was stopped. Its edits were taken back. A runaway loop cannot be killed from inside the app, so it may keep a CPU busy until Kine is restarted" % [timeout_ms / 1000.0, cid])
	th.wait_to_finish()
	api._service()
	var ret = box["ret"]
	if api.failed:
		_rollback()
		return _disable(rec, "stopped in command '%s': %s" % [cid, api.fail_msg])
	if ret != true:
		_rollback()
		return _disable(rec, "command '%s' did not finish: it returned %s instead of true. Either it hit an error in plugin.gd (the console shows the line) or it returned without true" % [cid, str(ret)])
	return ""


func _rollback() -> void:
	if host.has("rollback"):
		host["rollback"].call()


func _disable(rec: Dictionary, why: String) -> String:
	unload(rec)
	rec["enabled"] = false
	_save_state()
	rec["fault"] = _msg(rec, why + ". It is disabled now", "fix plugin.gd, then turn the plugin on again in Plugins")
	_changed()
	return rec["fault"]


## the S box rows: each enabled, loaded plugin's commands, the plugin's name first ("Mirror All Cards: Mirror every card")
func command_rows() -> Array:
	var out := []
	for i in found.size():
		var rec: Dictionary = found[i]
		if not (rec["enabled"] and rec["loaded"]):
			continue
		for c in rec["manifest"]["commands"]:
			out.append({"id": "plugin_%s_%s" % [rec["folder"], String(c["id"])],
				"name": "%s: %s" % [String(rec["manifest"]["name"]), String(c["name"])], "keys": "",
				"run": host["run"].bind(i, String(c["id"])), "also": "plugin " + rec["folder"], "edits": true,
				"desc": "plugin %s: %s" % [rec["manifest"]["name"], String(c.get("desc", ""))]})
	return out


## the S box's step name for command cid of plugin i (the undo list and the toast show it)
func step_name(i: int, cid: String) -> String:
	var rec: Dictionary = found[i]
	for c in rec["manifest"]["commands"]:
		if String(c["id"]) == cid:
			return "%s: %s" % [rec["manifest"]["name"], c["name"]]
	return String(rec["manifest"]["name"])


func _msg(rec: Dictionary, what: String, next: String) -> String:
	return "Plugin '%s' %s. Next step: %s" % [rec["manifest"].get("name", rec["folder"]), what, next]


func _changed() -> void:
	if host.has("changed"):
		host["changed"].call()


func _read_state() -> Dictionary:
	if not FileAccess.file_exists(state_file):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_file))
	return d if d is Dictionary else {}


func _save_state() -> void:
	var on := {}
	for rec in found:
		if rec["enabled"]:
			on[rec["folder"]] = true
	if state_file == "":
		return
	var f := FileAccess.open(state_file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(on, "  "))
		f.close()


# ---- install, update, uninstall (O02 / O09) ---------------------------------------------------------------------------

const MAX_INSTALL_BYTES := 20 * 1024 * 1024

## Install a plugin from a folder or a .zip into the first root. -> {"ok", "why", "action" ("installed" | "updated"), "folder",
## "version", "from_version"}. A new plugin is OFF. An update keeps the enable switch, the settings and the data (they live
## outside the plugin's folder) and refuses an older version. Nothing is written until the whole package has been checked.
func install(src: String) -> Dictionary:
	if roots.is_empty():
		return _inst_no("there is no plugins folder to install into", "start Kine normally")
	var pkg: Dictionary = _read_package(src)
	if not pkg["ok"]:
		return pkg
	var id: String = pkg["id"]
	var m: Variant = pkg["manifest"]
	var why := check_manifest(m, id)
	if why != "":
		return _inst_no("'%s' cannot be installed: %s" % [id, why], "fix manifest.json and install again")
	var dest: String = String(roots[0]) + "/" + id
	var from_v := ""
	var action := "installed"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest)):
		action = "updated"
		if FileAccess.file_exists(dest + "/manifest.json"):
			var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(dest + "/manifest.json"))
			if old is Dictionary:
				from_v = String(old.get("version", ""))
		if from_v != "" and _vercmp(String(m["version"]), from_v) < 0:
			return _inst_no("version %s is older than the installed %s" % [String(m["version"]), from_v], "install the newer one, or uninstall first to go back")
	# write: the old folder goes, the new one is written file by file
	_rm_tree(dest)
	for rel in pkg["files"]:
		var bytes: PackedByteArray = pkg["read"].call(rel)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path((dest + "/" + rel).get_base_dir()))
		var f := FileAccess.open(dest + "/" + rel, FileAccess.WRITE)
		if f == null:
			return _inst_no("could not write %s (error %d)" % [rel, FileAccess.get_open_error()], "check the disk and install again")
		f.store_buffer(bytes)
		f.close()
	scan()
	_changed()
	return {"ok": true, "why": "", "action": action, "folder": id, "version": String(m["version"]), "from_version": from_v}


## remove an installed plugin (not a shipped example). Its data and settings stay unless purge is true.
func uninstall(i: int, purge := false) -> Dictionary:
	if i < 0 or i >= found.size():
		return _inst_no("there is no such plugin", "open the Plugins panel and pick one")
	var rec: Dictionary = found[i]
	if rec["source"] != "installed" or not String(rec["dir"]).begins_with(String(roots[0])):
		return _inst_no("'%s' is a shipped example and cannot be uninstalled" % rec["folder"], "switch it off instead")
	var folder: String = rec["folder"]
	unload(rec)
	rec["enabled"] = false
	_rm_tree(rec["dir"])
	if purge:
		_rm_tree(data_root + "/" + folder)
	found.remove_at(i)
	_save_state()
	_changed()
	return {"ok": true, "why": ""}


func _inst_no(why: String, next: String) -> Dictionary:
	return {"ok": false, "why": "%s. Next step: %s" % [why, next]}


## {"ok", "id", "manifest", "files": [rel], "read": Callable(rel) -> bytes} for a folder or a zip, after the checks
func _read_package(src: String) -> Dictionary:
	var files := []
	var total := 0
	var base := src.rstrip("/\\")
	if base.to_lower().ends_with(".zip"):
		var zr := ZIPReader.new()
		if zr.open(base) != OK:
			return _inst_no("could not open '%s' as a zip" % base.get_file(), "pick a .zip made by zipping the plugin folder")
		var all := zr.get_files()
		for e in all:
			var path: String = e
			if path.contains("..") or path.begins_with("/") or path.contains(":") or path.contains("\\"):
				zr.close()
				return _inst_no("the zip has an entry '%s' that leaves the plugin folder (.. or an absolute path); nothing was installed" % path, "ask the author for a clean zip")
		var prefix := ""
		if all.has("manifest.json"):
			prefix = ""
		else:
			for e in all:
				if String(e).ends_with("/manifest.json") and String(e).count("/") == 1:
					prefix = String(e).get_base_dir() + "/"
		if not all.has(prefix + "manifest.json"):
			zr.close()
			return _inst_no("the zip has no manifest.json at its top (or in one top folder)", "zip the plugin folder so manifest.json is inside it")
		var m0: Variant = JSON.parse_string(zr.read_file(prefix + "manifest.json").get_string_from_utf8())
		var id0 := prefix.trim_suffix("/") if prefix != "" else _safe_id(base.get_file().get_basename())
		for e in all:
			var path2: String = e
			if path2.ends_with("/") or not path2.begins_with(prefix):
				continue
			total += zr.read_file(path2).size()
			files.append(path2.substr(prefix.length()))
		if total > MAX_INSTALL_BYTES:
			zr.close()
			return _inst_no("the package is larger than %d MB" % (MAX_INSTALL_BYTES / 1048576), "plugins are small scripts: remove the big files")
		var cache := {}
		for rel in files:
			cache[rel] = zr.read_file(prefix + rel)
		zr.close()
		return {"ok": true, "id": id0, "manifest": m0, "files": files, "read": func(rel): return cache[rel]}
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base)):
		return _inst_no("'%s' is neither a folder nor a .zip" % src, "pick the plugin's folder or its zip")
	if not FileAccess.file_exists(base + "/manifest.json"):
		return _inst_no("'%s' has no manifest.json" % base.get_file(), "pick the folder that holds manifest.json and plugin.gd")
	_list_files(base, "", files)
	for rel in files:
		total += FileAccess.get_file_as_bytes(base + "/" + rel).size()
	if total > MAX_INSTALL_BYTES:
		return _inst_no("the folder is larger than %d MB" % (MAX_INSTALL_BYTES / 1048576), "plugins are small scripts: remove the big files")
	var m1: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "/manifest.json"))
	return {"ok": true, "id": base.get_file(), "manifest": m1, "files": files, "read": func(rel): return FileAccess.get_file_as_bytes(base + "/" + rel)}


func _list_files(root: String, rel: String, out: Array) -> void:
	var da := DirAccess.open(root + ("/" + rel if rel != "" else ""))
	if da == null:
		return
	for d in da.get_directories():
		if not d.begins_with("."):
			_list_files(root, (rel + "/" if rel != "" else "") + d, out)
	for f in da.get_files():
		if not f.begins_with(".") and not f.ends_with(".uid"):
			out.append((rel + "/" if rel != "" else "") + f)


func _safe_id(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" else "_"
	return out


## -1, 0, 1 comparing dotted numbers ("1.10.0" > "1.9.2")
func _vercmp(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for n in maxi(pa.size(), pb.size()):
		var x := int(pa[n]) if n < pa.size() else 0
		var y := int(pb[n]) if n < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


func _rm_tree(p: String) -> void:
	var da := DirAccess.open(p)
	if da == null:
		return
	for d in da.get_directories():
		_rm_tree(p + "/" + d)
	for f in da.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
