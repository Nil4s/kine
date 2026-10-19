## THE PLUGIN API (ROADMAP 100): the one object a user plugin's code is handed, as api in func command(api, id).
## It is a NARROW FACADE, not the app. A plugin:
##   - reads COPIES of the cards (cards(), card_count()): poses in joint angles (degrees), holds and move times;
##   - proposes edits: set_joint (clamped to the joint's limits), add_card, remove_card, set_timing. Each command a
##     plugin runs is ONE undo step (main opens it; the edits inside join it), named after the command in the S box;
##   - writes files only under user://plugins/<name>/data/ (write_data / read_data; a path that leaves it is refused);
##   - reports a failure with fail(msg): the command stops, and Plugins disables the plugin with that message.
## It holds NO reference to main.gd. main hands over a few Callables (the scene, the active body's limits, the undo
## opener, the status line); they are private to this object and a plugin is not given them.
## HONEST LIMIT: GDScript cannot be sandboxed. A plugin runs with this app's permissions and can reach anything the
## engine can. This facade is the documented way in, not a wall. docs/PLUGINS.md says the same.
## Indices are 0-based (card 0 is the first card). Every result is a Dictionary {"ok": bool, "why": String, ...}.
class_name PluginAPI
extends RefCounted

const VERSION := 1          # the api version a manifest names ("api": 1); another number disables the plugin
const HOLD_MIN := 0.05      # seconds: set_timing clamps a hold or a move to this range (and says so)
const HOLD_MAX := 10.0

var plugin_name := ""       # the folder name (the id), set by Plugins: the data folder's name
var title := ""              # the manifest's name, what log() says it is
var failed := false         # set by fail(); Plugins reads it after the command returns
var fail_msg := ""
var _scene_fn: Callable     # () -> the open Scene (scripts/scene.gd): private, never handed out
var _clamp: Callable        # (joint, Vector3) -> Vector3: the active body's joint limits
var _has_joint: Callable    # (joint) -> bool
var _begin: Callable        # () -> opens the command's undo step (a no-op after the first call in one command)
var _say: Callable          # (text) -> the status line
var _data_root := "user://plugins"


func _init(plugin: String, scene_fn: Callable, clamp: Callable, has_joint: Callable, begin: Callable, say: Callable,
		data_root: String) -> void:
	plugin_name = plugin
	_scene_fn = scene_fn
	_clamp = clamp
	_has_joint = has_joint
	_begin = begin
	_say = say
	_data_root = data_root


# ---- reading (copies: changing them changes nothing) -----------------------------------------------------------------

func api_version() -> int:
	return VERSION


func card_count() -> int:
	return _cards().size()


## every card as a copy: {"name", "hold" (s), "move" (s, -1 = automatic), "joints": {joint: Vector3(bend, side, twist) deg}}
func cards() -> Array:
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
	var out := PackedStringArray()
	for j in Body.ORDER:
		out.append(j)
	return out


# ---- editing (each one joins the command's undo step) ------------------------------------------------------------------

## set one joint of card i to (bend, side, twist) in degrees. The angles are CLAMPED to the joint's limits: the result
## says whether they were ("clamped": true) and the value kept ("value"). Nothing else on the card changes.
func set_joint(i: int, joint: String, v: Vector3) -> Dictionary:
	if i < 0 or i >= card_count():
		return _no("there is no card %d: the scene has %d cards (0 to %d)" % [i, card_count(), card_count() - 1])
	if not _has_joint.call(joint):
		return _no("there is no joint called '%s': see joint_names() for the ones the body has" % joint)
	var kept: Vector3 = _clamp.call(joint, v)
	var cs := _cards()
	_begin.call()
	var pose: Dictionary = (cs[i]["pose"] as Dictionary).duplicate(true)   # a pose is replaced whole, never edited in place
	var joints: Dictionary = pose["joints"]
	joints[joint] = {"bend": kept.x, "side": kept.y, "twist": kept.z}
	pose["joints"] = joints
	cs[i]["pose"] = pose
	return {"ok": true, "why": "", "clamped": not kept.is_equal_approx(v), "value": kept}


## a new card after the last one, with the pose of card `from` (default: the last card). Returns its index.
func add_card(card_name: String, from := -1) -> Dictionary:
	var cs := _cards()
	if cs.is_empty():
		return _no("the scene has no cards to copy a pose from: clip a pose first (Enter), then add_card")
	var src := from if from >= 0 else cs.size() - 1
	if src >= cs.size():
		return _no("there is no card %d to copy: the scene has %d cards" % [from, cs.size()])
	_begin.call()
	var card := {"name": card_name, "pose": (cs[src]["pose"] as Dictionary).duplicate(true), "move": -1.0, "hold": 0.3}
	cs.append(card)
	return {"ok": true, "why": "", "index": cs.size() - 1}


func remove_card(i: int) -> Dictionary:
	var cs := _cards()
	if i < 0 or i >= cs.size():
		return _no("there is no card %d to remove: the scene has %d cards (0 to %d)" % [i, cs.size(), cs.size() - 1])
	_begin.call()
	cs.remove_at(i)
	return {"ok": true, "why": ""}


## card i's hold (seconds it stays still) and move (seconds it takes to get there; -1 = automatic). Clamped to
## HOLD_MIN .. HOLD_MAX; a move of -1 keeps it automatic. "clamped" says whether a value was changed.
func set_timing(i: int, hold: float, move := -1.0) -> Dictionary:
	var cs := _cards()
	if i < 0 or i >= cs.size():
		return _no("there is no card %d: the scene has %d cards (0 to %d)" % [i, cs.size(), cs.size() - 1])
	var h := clampf(hold, HOLD_MIN, HOLD_MAX)
	var m := move if move < 0.0 else clampf(move, HOLD_MIN, HOLD_MAX)
	_begin.call()
	cs[i]["hold"] = h
	cs[i]["move"] = m
	return {"ok": true, "why": "", "clamped": not is_equal_approx(h, hold) or (move >= 0.0 and not is_equal_approx(m, move)), "hold": h, "move": m}


# ---- files: only under user://plugins/<name>/data/ -------------------------------------------------------------------

func write_data(rel: String, text: String) -> Dictionary:
	var p := _data_path(rel)
	if p == "":
		return _no("'%s' is not a file inside your data folder: use a plain relative name like scores.txt (no .., no leading /)" % rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return _no("could not open %s for writing (error %d)" % [p, FileAccess.get_open_error()])
	f.store_string(text)
	f.close()
	return {"ok": true, "why": "", "path": p}


func read_data(rel: String) -> Dictionary:
	var p := _data_path(rel)
	if p == "":
		return _no("'%s' is not a file inside your data folder: use a plain relative name like scores.txt (no .., no leading /)" % rel)
	if not FileAccess.file_exists(p):
		return _no("there is no file '%s' in your data folder yet: write_data creates it" % rel)
	return {"ok": true, "why": "", "text": FileAccess.get_file_as_string(p)}


# ---- stopping and talking ----------------------------------------------------------------------------------------------

## the command cannot go on: Plugins disables this plugin and shows msg with the plugin's name and the next step
func fail(msg: String) -> void:
	failed = true
	fail_msg = msg


## a line on the status bar (what the command did, in words)
func log(msg: String) -> void:
	_say.call("%s: %s" % [title if title != "" else plugin_name, msg])


# ---- private --------------------------------------------------------------------------------------------------------------

func _cards() -> Array:
	var s = _scene_fn.call()
	return s.cards if s != null else []


func _no(why: String) -> Dictionary:
	return {"ok": false, "why": why}


## user://plugins/<name>/data/<rel>, or "" when rel would leave that folder
func _data_path(rel: String) -> String:
	if rel == "" or rel.begins_with("/") or rel.begins_with("\\") or rel.contains(":") or rel.contains("\\"):
		return ""
	for part in rel.split("/"):
		if part == "" or part == "." or part == "..":
			return ""
	return "%s/%s/data/%s" % [_data_root, plugin_name, rel]
