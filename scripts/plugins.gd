## USER PLUGINS (ROADMAP 100). Finds the plugin folders, checks each manifest.json, loads plugin.gd ONLY when the plugin
## is enabled, and runs its commands. Each command is one undo step (main's _plugin_run opens it). A plugin that reports
## a failure (api.fail) is disabled with a message that names it and the next step; the app keeps running.
## Plugins are DISABLED by default. The enable switches live in user://plugins.json (a preference, not work).
## A plugin folder: manifest.json + plugin.gd. docs/PLUGINS.md is the reference. The example is examples/plugins/.
class_name Plugins
extends RefCounted

const MANIFEST_KEYS := ["name", "version", "author", "api", "commands"]

var roots: Array = ["user://plugins", "res://examples/plugins"]   # installed plugins, then the ones shipped in the repo
var data_root := "user://plugins"    # plugin data is user://plugins/<name>/data/ (a test may move the root)
var state_file := "user://plugins.json"
var host: Dictionary = {}            # "scene", "clamp", "has_joint", "begin", "say", "changed", "run": Callables from main
var found: Array = []                # one record per plugin folder, see _record


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
	_save_state()


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
	if int(d["api"]) != PluginAPI.VERSION:
		return "needs api %d and this app has api %d: ask the author for a version that uses api %d" % [int(d["api"]), PluginAPI.VERSION, PluginAPI.VERSION]
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
	var api := PluginAPI.new(rec["folder"], host["scene"], host["clamp"], host["has_joint"], host["begin"], host["say"], data_root)
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
	rec["obj"].command(api, cid)
	if api.failed:
		unload(rec)
		rec["enabled"] = false
		_save_state()
		rec["fault"] = _msg(rec, "stopped in command '%s': %s. It is disabled now" % [cid, api.fail_msg],
			"fix plugin.gd, then turn the plugin on again in Plugins")
		_changed()
		return rec["fault"]
	return ""


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
	var f := FileAccess.open(state_file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(on, "  "))
		f.close()
