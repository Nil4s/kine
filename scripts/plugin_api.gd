## THE PLUGIN API (ROADMAP 100, extended by L70 / ROADMAP_400 track O): the one object a user plugin's code is handed, as
## api in func command(api, id). It is a NARROW FACADE, not the app. A plugin:
##   - reads COPIES of the cards, the set's objects, the part keys, the open mesh and the selection;
##   - proposes edits: set_joint / add_card / remove_card / set_timing / rename_card, add_object / move_object / remove_object,
##     set_key / remove_key. Each command a plugin runs is ONE undo step (main opens it; the edits inside join it), named
##     after the command in the S box. A command that fails or runs too long is rolled back;
##   - with a PERMISSION named in its manifest: run_tool (the app's own tool lines), export (bvh), write_file / read_file
##     (inside the project: exports/ scenes/ poses/ plugin_out/ only);
##   - always: its own data folder (write_data / read_data) and settings (get_setting / set_setting, kept across updates);
##   - reports a failure with fail(msg): the command stops, and Plugins disables the plugin with that message.
## It holds NO reference to main.gd. main hands over a few Callables; they are private to this object and a plugin is not
## given them. A command runs on a worker thread and every call that needs the app is carried out on the main thread, so a
## runaway loop can be abandoned after Plugins.timeout_ms (the plugin is then "revoked": its calls do nothing).
## HONEST LIMIT: GDScript cannot be sandboxed. A plugin runs with this app's permissions and can reach anything the
## engine can (FileAccess, OS). This facade is the documented way in, not a wall. docs/PLUGINS.md says the same.
## Indices are 0-based (card 0 is the first card). Every result is a Dictionary {"ok": bool, "why": String, ...}.
class_name PluginAPI
extends RefCounted

const VERSION := 2         # the api version this app has. A manifest names "api": 1 or 2 (1 = the cards-only api, still loads)
const SUPPORTED := [1, 2]
const PERMISSIONS := ["files", "export", "tools"]   # what a manifest may ask for in "permissions"
const PROJECT_DIRS := ["exports", "scenes", "poses", "plugin_out"]   # where write_file may put files (inside the project root)
const TOOL_DENY := ["quit", "open", "new", "save", "save_pose", "save_scene", "serve", "exit"]
const HOLD_MIN := 0.05      # seconds: set_timing clamps a hold or a move to this range (and says so)
const HOLD_MAX := 10.0
## every public call, in the order docs/PLUGINS.md describes them. tests/plugins2_test.gd checks that this list equals the
## public methods, that docs/PLUGINS.md names each, and that the suite calls each.
const DOCUMENTED := ["api_version", "has_permission", "card_count", "cards", "joint_names", "scene_info", "set_joint", "add_card",
	"remove_card", "set_timing", "rename_card", "objects", "add_object", "move_object", "remove_object", "keys", "set_key",
	"remove_key", "mesh_info", "mesh_vertices", "selection", "select_card", "select_joint", "run_tool", "export", "get_setting",
	"set_setting", "write_data", "read_data", "write_file", "read_file", "fail", "log"]

var plugin_name := ""       # the folder name (the id), set by Plugins: the data folder's name
var title := ""              # the manifest's name, what log() says it is
var failed := false         # set by fail(); Plugins reads it after the command returns
var fail_msg := ""
var revoked := false        # set by Plugins when a command ran past the time limit: every call now does nothing
var jobs: Array = []        # calls waiting for the main thread (a command runs on a worker thread; see _m)
var _mu := Mutex.new()
var _main_id := OS.get_main_thread_id()
var _host: Dictionary       # Callables from main (the scene, undo opener, status line...): private, never handed out
var _perms: Array = []
var _calls: Dictionary      # shared call log (Plugins.call_log): name -> count
var _data_root := "user://plugins"
var _project_root := "res://"


func _init(plugin: String, host: Dictionary, data_root: String, project_root: String, perms: Array, calls: Dictionary) -> void:
	plugin_name = plugin
	_host = host
	_data_root = data_root
	_project_root = project_root
	_perms = perms
	_calls = calls


## main thread: carry out the calls the worker thread is waiting for
func _service() -> void:
	_mu.lock()
	var js := jobs
	jobs = []
	_mu.unlock()
	for j in js:
		j["ret"] = (j["c"] as Callable).callv(j["a"])
		j["done"] = true


# ---- reading (copies: changing them changes nothing) -----------------------------------------------------------------

func api_version() -> int:
	_hit("api_version")
	return VERSION


## true when the manifest asked for permission p ("files", "export", "tools")
func has_permission(p: String) -> bool:
	_hit("has_permission")
	return _perms.has(p)


func card_count() -> int:
	_hit("card_count")
	return _cards().size()


## every card as a copy: {"name", "hold" (s), "move" (s, -1 = automatic), "joints": {joint: Vector3(bend, side, twist) deg}}
func cards() -> Array:
	_hit("cards")
	var out := []
	for c in _cards():
		var joints := {}
		for j in (c["pose"]["joints"] as Dictionary):
			var a: Dictionary = c["pose"]["joints"][j]
			joints[j] = Vector3(float(a["bend"]), float(a["side"]), float(a["twist"]))
		out.append({"name": String(c["name"]), "hold": float(c["hold"]), "move": float(c["move"]), "joints": joints})
	return out


## the joint names the body has (the same names a card's joints use)
func joint_names() -> PackedStringArray:
	_hit("joint_names")
	var out := PackedStringArray()
	for j in Body.ORDER:
		out.append(j)
	return out


## {"name", "cards", "length" (s), "fps", "objects", "keyed_joints"}
func scene_info() -> Dictionary:
	_hit("scene_info")
	var s = _scene()
	if s == null:
		return {"name": "", "cards": 0, "length": 0.0, "fps": 30, "objects": 0, "keyed_joints": 0}
	return {"name": String(s.name), "cards": s.cards.size(), "length": float(s.length()), "fps": int(s.fps),
		"objects": s.props.size(), "keyed_joints": s.part_keys.size()}


# ---- editing (each one joins the command's undo step) ------------------------------------------------------------------

## set one joint of card i to (bend, side, twist) in degrees. The angles are CLAMPED to the joint's limits: the result
## says whether they were ("clamped": true) and the value kept ("value"). Nothing else on the card changes.
func set_joint(i: int, joint: String, v: Vector3) -> Dictionary:
	if _hit("set_joint"):
		return _gone()
	var n := _cards().size()
	if i < 0 or i >= n:
		return _no("there is no card %d: the scene has %d cards (0 to %d)" % [i, n, n - 1])
	if not _host["has_joint"].call(joint):
		return _no("there is no joint called '%s': see joint_names() for the ones the body has" % joint)
	var kept: Vector3 = _host["clamp"].call(joint, v)
	var cs := _cards()
	if _begin():
		return _gone()
	var pose: Dictionary = (cs[i]["pose"] as Dictionary).duplicate(true)   # a pose is replaced whole, never edited in place
	var joints: Dictionary = pose["joints"]
	joints[joint] = {"bend": kept.x, "side": kept.y, "twist": kept.z}
	pose["joints"] = joints
	cs[i]["pose"] = pose
	return {"ok": true, "why": "", "clamped": not kept.is_equal_approx(v), "value": kept}


## a new card after the last one, with the pose of card `from` (default: the last card). Returns its index.
func add_card(card_name: String, from := -1) -> Dictionary:
	if _hit("add_card"):
		return _gone()
	var cs := _cards()
	if cs.is_empty():
		return _no("the scene has no cards to copy a pose from: clip a pose first (Enter), then add_card")
	var src := from if from >= 0 else cs.size() - 1
	if src >= cs.size():
		return _no("there is no card %d to copy: the scene has %d cards" % [from, cs.size()])
	if _begin():
		return _gone()
	var card := {"name": card_name, "pose": (cs[src]["pose"] as Dictionary).duplicate(true), "move": -1.0, "hold": 0.3}
	cs.append(card)
	return {"ok": true, "why": "", "index": cs.size() - 1}


func remove_card(i: int) -> Dictionary:
	if _hit("remove_card"):
		return _gone()
	var cs := _cards()
	if i < 0 or i >= cs.size():
		return _no("there is no card %d to remove: the scene has %d cards (0 to %d)" % [i, cs.size(), cs.size() - 1])
	if _begin():
		return _gone()
	cs.remove_at(i)
	return {"ok": true, "why": ""}


## card i's hold (seconds it stays still) and move (seconds it takes to get there; -1 = automatic). Clamped to
## HOLD_MIN .. HOLD_MAX; a move of -1 keeps it automatic. "clamped" says whether a value was changed.
func set_timing(i: int, hold: float, move := -1.0) -> Dictionary:
	if _hit("set_timing"):
		return _gone()
	var cs := _cards()
	if i < 0 or i >= cs.size():
		return _no("there is no card %d: the scene has %d cards (0 to %d)" % [i, cs.size(), cs.size() - 1])
	var h := clampf(hold, HOLD_MIN, HOLD_MAX)
	var m := move if move < 0.0 else clampf(move, HOLD_MIN, HOLD_MAX)
	if _begin():
		return _gone()
	cs[i]["hold"] = h
	cs[i]["move"] = m
	return {"ok": true, "why": "", "clamped": not is_equal_approx(h, hold) or (move >= 0.0 and not is_equal_approx(m, move)), "hold": h, "move": m}


func rename_card(i: int, new_name: String) -> Dictionary:
	if _hit("rename_card"):
		return _gone()
	var cs := _cards()
	if i < 0 or i >= cs.size():
		return _no("there is no card %d to rename: the scene has %d cards (0 to %d)" % [i, cs.size(), cs.size() - 1])
	if new_name.strip_edges() == "":
		return _no("a card needs a name: pass some text")
	if _begin():
		return _gone()
	cs[i]["name"] = new_name
	return {"ok": true, "why": ""}


# ---- objects (the props of the set) ----------------------------------------------------------------------------------

## every object of the set as a copy: {"index", "kind", "pos" (Vector3, metres), "yaw" (deg)}
func objects() -> Array:
	_hit("objects")
	var out := []
	var s = _scene()
	if s == null:
		return out
	for i in s.props.size():
		var xf: Transform3D = s.props[i]["xf"]
		out.append({"index": i, "kind": String(s.props[i]["kind"]), "pos": xf.origin,
			"yaw": rad_to_deg(atan2(-xf.basis.x.z, xf.basis.x.x))})
	return out


## add an object of a kind the app has (see the Set page) at pos. Returns its index.
func add_object(kind: String, pos: Vector3, yaw := 0.0) -> Dictionary:
	if _hit("add_object"):
		return _gone()
	if not Props.has_kind(kind):
		return _no("there is no object kind '%s': use one of the Set page's kinds, for example box, crate or table" % kind)
	var s = _scene()
	if _begin():
		return _gone()
	s.props.append(Props.make(kind, Props.xf_at(pos, yaw)))
	return {"ok": true, "why": "", "index": s.props.size() - 1}


func move_object(i: int, pos: Vector3) -> Dictionary:
	if _hit("move_object"):
		return _gone()
	var s = _scene()
	if s == null or i < 0 or i >= s.props.size():
		return _no("there is no object %d: the scene has %d objects" % [i, s.props.size() if s != null else 0])
	if _begin():
		return _gone()
	var xf: Transform3D = s.props[i]["xf"]
	xf.origin = pos
	s.props[i]["xf"] = xf
	return {"ok": true, "why": ""}


func remove_object(i: int) -> Dictionary:
	if _hit("remove_object"):
		return _gone()
	var s = _scene()
	if s == null or i < 0 or i >= s.props.size():
		return _no("there is no object %d to remove: the scene has %d objects" % [i, s.props.size() if s != null else 0])
	if _begin():
		return _gone()
	s.props.remove_at(i)
	return {"ok": true, "why": ""}


# ---- keys (one joint at a time, on the timeline) ---------------------------------------------------------------------

## the part keys of a joint as copies: [{"t" seconds, "v" Vector3 degrees}] by time ([] when it has none)
func keys(joint: String) -> Array:
	_hit("keys")
	var s = _scene()
	var out := []
	if s == null or not s.part_keys.has(joint):
		return out
	for k in s.part_keys[joint]:
		out.append({"t": float(k["t"]), "v": k["v"]})
	return out


## key joint at time t (s) to v (degrees, clamped to the joint's limits). A key at the same time (within 1 ms) is replaced.
func set_key(joint: String, t: float, v: Vector3) -> Dictionary:
	if _hit("set_key"):
		return _gone()
	if not _host["has_joint"].call(joint):
		return _no("there is no joint called '%s': see joint_names() for the ones the body has" % joint)
	if t < 0.0:
		return _no("a key time cannot be negative: pass seconds from the start")
	var s = _scene()
	var kept: Vector3 = _host["clamp"].call(joint, v)
	if _begin():
		return _gone()
	var pk: Dictionary = s.part_keys.duplicate(true)
	var list: Array = pk.get(joint, [])
	for n in range(list.size() - 1, -1, -1):
		if absf(float(list[n]["t"]) - t) < 0.001:
			list.remove_at(n)
	list.append({"t": t, "v": kept})
	list.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	pk[joint] = list
	s.part_keys = pk
	return {"ok": true, "why": "", "clamped": not kept.is_equal_approx(v), "value": kept}


func remove_key(joint: String, t: float) -> Dictionary:
	if _hit("remove_key"):
		return _gone()
	var s = _scene()
	if s == null or not s.part_keys.has(joint):
		return _no("joint '%s' has no keys" % joint)
	var pk: Dictionary = s.part_keys.duplicate(true)
	var list: Array = pk[joint]
	var found := -1
	for n in list.size():
		if absf(float(list[n]["t"]) - t) < 0.001:
			found = n
	if found < 0:
		return _no("joint '%s' has no key at %.3f s: keys() lists the times" % [joint, t])
	if _begin():
		return _gone()
	list.remove_at(found)
	if list.is_empty():
		pk.erase(joint)
	else:
		pk[joint] = list
	s.part_keys = pk
	return {"ok": true, "why": ""}


# ---- the mesh being edited (read only) -------------------------------------------------------------------------------

## {"ok", "verts", "faces", "bounds_min", "bounds_max"} of the mesh open in the model page, or ok false when none is open
func mesh_info() -> Dictionary:
	_hit("mesh_info")
	var km = _mesh()
	if km == null:
		return _no("no mesh is open: open a model on the MODEL page first")
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in km.verts:
		lo = lo.min(v)
		hi = hi.max(v)
	if km.verts.is_empty():
		lo = Vector3.ZERO
		hi = Vector3.ZERO
	return {"ok": true, "why": "", "verts": km.vert_count(), "faces": km.face_count(), "bounds_min": lo, "bounds_max": hi}


## a copy of the first max_count vertex positions: {"ok", "vertices": PackedVector3Array, "truncated"}
func mesh_vertices(max_count := 5000) -> Dictionary:
	_hit("mesh_vertices")
	var km = _mesh()
	if km == null:
		return _no("no mesh is open: open a model on the MODEL page first")
	var n := clampi(max_count, 0, 100000)
	return {"ok": true, "why": "", "vertices": km.verts.slice(0, n), "truncated": km.verts.size() > n}


# ---- selection ------------------------------------------------------------------------------------------------------

## {"card" (index, -1 = none), "joint", "object" (the picked object's id or "")}
func selection() -> Dictionary:
	_hit("selection")
	var r = _m(_host["sel_get"])
	return r if r is Dictionary else {"card": -1, "joint": "", "object": ""}


func select_card(i: int) -> Dictionary:
	if _hit("select_card"):
		return _gone()
	var n := _cards().size()
	if i < 0 or i >= n:
		return _no("there is no card %d to select: the scene has %d cards" % [i, n])
	_m(_host["sel_card"], [i])
	return {"ok": true, "why": ""}


func select_joint(joint: String) -> Dictionary:
	if _hit("select_joint"):
		return _gone()
	if not _host["has_joint"].call(joint):
		return _no("there is no joint called '%s': see joint_names() for the ones the body has" % joint)
	_m(_host["sel_joint"], [joint])
	return {"ok": true, "why": ""}


# ---- the app's own tools and export (need a permission in the manifest) ------------------------------------------------

## run one line of the app's tool language (the lines of a saved script, for example "card=2" or "set=head:15,0,0").
## Needs "tools". Quit, open, new and save are not allowed. -> {"ok", "why", "said"}
func run_tool(line: String) -> Dictionary:
	if _hit("run_tool"):
		return _gone()
	if not _perms.has("tools"):
		return _need("tools")
	var tok := line.strip_edges()
	if tok == "" or TOOL_DENY.has(tok.get_slice(" ", 0).get_slice("=", 0)):
		return _no("the tool line '%s' is not allowed from a plugin (quit, open, new and save are the user's)" % tok)
	if _begin():
		return _gone()
	var r = _m(_host["tool"], [tok])
	return r if r is Dictionary else _no("the tool '%s' did not answer" % tok)


## write the scene to <data>/<plugin>/exports/<scene name>.bvh. kind: "bvh". Needs "export". -> {"ok", "why", "path", "bytes"}
func export(kind: String) -> Dictionary:
	if _hit("export"):
		return _gone()
	if not _perms.has("export"):
		return _need("export")
	if kind != "bvh":
		return _no("cannot export '%s': the kinds are bvh" % kind)
	var s = _scene()
	var base := String(s.name).validate_filename() if s != null else "scene"
	var path := "%s/%s/exports/%s.bvh" % [_data_root, plugin_name, base if base != "" else "scene"]
	var r = _m(_host["export"], [kind, path])
	if not (r is Dictionary) or not r.get("ok", false):
		return _no(String(r.get("why", "the export failed")) if r is Dictionary else "the export failed")
	return {"ok": true, "why": "", "path": path, "bytes": FileAccess.get_file_as_bytes(path).size()}


# ---- settings, and files ---------------------------------------------------------------------------------------------

## a value the plugin saved with set_setting (kept across restarts and across updates of the plugin)
func get_setting(key: String, default: Variant = null) -> Variant:
	_hit("get_setting")
	var d := _settings()
	return d.get(key, default)


func set_setting(key: String, value: Variant) -> Dictionary:
	if _hit("set_setting"):
		return _gone()
	var d := _settings()
	d[key] = value
	var p := "%s/%s/settings.json" % [_data_root, plugin_name]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return _no("could not save the setting (error %d)" % FileAccess.get_open_error())
	f.store_string(JSON.stringify(d))
	f.close()
	return {"ok": true, "why": ""}


## the plugin's own data folder: <data>/<name>/data/<rel>
func write_data(rel: String, text: String) -> Dictionary:
	if _hit("write_data"):
		return _gone()
	var p := _data_path(rel)
	if p == "":
		return _no("'%s' is not a file inside your data folder: use a plain relative name like scores.txt (no .., no leading /)" % rel)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return _no("could not open %s for writing (error %d)" % [p, FileAccess.get_open_error()])
	f.store_string(text)
	f.close()
	return {"ok": true, "why": "", "path": p}


func read_data(rel: String) -> Dictionary:
	_hit("read_data")
	var p := _data_path(rel)
	if p == "":
		return _no("'%s' is not a file inside your data folder: use a plain relative name like scores.txt (no .., no leading /)" % rel)
	if not FileAccess.file_exists(p):
		return _no("there is no file '%s' in your data folder yet: write_data creates it" % rel)
	return {"ok": true, "why": "", "text": FileAccess.get_file_as_string(p)}


## a file inside the PROJECT, only under exports/, scenes/, poses/ or plugin_out/ (and never outside it). Needs "files".
func write_file(rel: String, text: String) -> Dictionary:
	if _hit("write_file"):
		return _gone()
	if not _perms.has("files"):
		return _need("files")
	var p := _project_path(rel)
	if p == "":
		return _no("'%s' is not allowed: a project file is <folder>/<name> with the folder one of %s, no .., no drive, no leading /" % [rel, ", ".join(PROJECT_DIRS)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return _no("could not open %s for writing (error %d)" % [rel, FileAccess.get_open_error()])
	f.store_string(text)
	f.close()
	return {"ok": true, "why": "", "path": p}


func read_file(rel: String) -> Dictionary:
	_hit("read_file")
	if not _perms.has("files"):
		return _need("files")
	var p := _project_path(rel)
	if p == "":
		return _no("'%s' is not allowed: a project file is <folder>/<name> with the folder one of %s" % [rel, ", ".join(PROJECT_DIRS)])
	if not FileAccess.file_exists(p):
		return _no("there is no project file '%s'" % rel)
	return {"ok": true, "why": "", "text": FileAccess.get_file_as_string(p)}


# ---- stopping and talking ----------------------------------------------------------------------------------------------

## the command cannot go on: Plugins disables this plugin and shows msg with the plugin's name and the next step
func fail(msg: String) -> void:
	_hit("fail")
	failed = true
	fail_msg = msg


## a line on the status bar (what the command did, in words)
func log(msg: String) -> void:
	if _hit("log"):
		return
	_m(_host["say"], ["%s: %s" % [title if title != "" else plugin_name, msg]])


# ---- private --------------------------------------------------------------------------------------------------------------

## count the call; true when this plugin was stopped (the caller then does nothing). A stopped runaway sleeps a little
func _hit(nm: String) -> bool:
	_calls[nm] = int(_calls.get(nm, 0)) + 1
	if revoked:
		OS.delay_msec(20)
	return revoked


func _gone() -> Dictionary:
	return _no("this plugin was stopped (its command ran too long): nothing was changed")


func _need(perm: String) -> Dictionary:
	return _no("needs the '%s' permission: the plugin's manifest.json must list it in \"permissions\" (and the user installs it knowing that)" % perm)


## run c on the main thread and wait for its answer (a command runs on a worker thread so a runaway loop can be abandoned)
func _m(c: Callable, args := []) -> Variant:
	if revoked:
		return null
	if OS.get_thread_caller_id() == _main_id:
		return c.callv(args)
	var job := {"c": c, "a": args, "done": false, "ret": null}
	_mu.lock()
	jobs.append(job)
	_mu.unlock()
	while not job["done"]:
		if revoked:
			return null
		OS.delay_usec(300)
	return job["ret"]


## opens the command's undo step (a no-op after the first call in one command)
func _begin() -> bool:
	_m(_host["begin"])
	return revoked


func _scene():
	return _host["scene"].call()


func _mesh():
	if not _host.has("mesh"):
		return null
	return _host["mesh"].call()


func _cards() -> Array:
	var s = _scene()
	return s.cards if s != null else []


func _settings() -> Dictionary:
	var p := "%s/%s/settings.json" % [_data_root, plugin_name]
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


func _no(why: String) -> Dictionary:
	return {"ok": false, "why": why}


## <data>/<name>/data/<rel>, or "" when rel would leave that folder
func _data_path(rel: String) -> String:
	if _bad_rel(rel):
		return ""
	return "%s/%s/data/%s" % [_data_root, plugin_name, rel]


## <project>/<dir>/<rest>, or "" unless rel is a plain relative path whose first folder is one of PROJECT_DIRS
func _project_path(rel: String) -> String:
	if _bad_rel(rel):
		return ""
	var parts := rel.split("/")
	if parts.size() < 2 or not PROJECT_DIRS.has(parts[0]):
		return ""
	return "%s/%s" % [_project_root, rel]


func _bad_rel(rel: String) -> bool:
	if rel == "" or rel.begins_with("/") or rel.begins_with("\\") or rel.contains(":") or rel.contains("\\"):
		return true
	for part in rel.split("/"):
		if part == "" or part == "." or part == "..":
			return true
	return false
