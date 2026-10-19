## journal.gd - THE JOURNAL (ROADMAP item 2, CRASH-PROOF): no edit is lost to a crash.
##
## Every undo step's result (main's _scene_dict(false), the state the autosave holds) is appended to one file per scene:
## <dir>/<scene key>.jsonl. A line is one entry (values are var_to_bytes, base64: exact, int and float kept apart):
##   {"i": n, "t": unix seconds, "path": scene path, "full": "<b64 of the whole state>"}          every FULL_EVERY entries
##   {"i": n, "t": ..., "path": ..., "set": [[[path], "<b64>"], ...], "del": [[path], ...]}        the rest
## A diff names only the parts that changed since the entry before: a path is a list of dictionary keys and array
## keys, or array indices for an array of dictionaries (the cards, the fighters); a dictionary is split to DICT_DEPTH,
## an array to ARRAY_DEPTH; below that a part is compared whole. What changed is found by hashes, not by the scene's own
## objects (the scene edits its dictionaries in place, so the journal keeps its own record of hashes).
## The file stays open between entries and is flushed after each one: a crash loses at most the entry being written,
## and a torn last line is skipped on read (the entries before it stand).
## <dir>/session.json: {"clean": bool}. The app sets it false at start and true on a clean quit; a start that finds it
## false (and a journal newer than its scene's file) offers the work back. Saving a scene trims its journal.
class_name Journal
extends RefCounted

const FULL_EVERY := 50
const DICT_DEPTH := 4   # a dictionary is split into its keys above this depth; below it a value is compared whole
const ARRAY_DEPTH := 6  # an array of dictionaries (the cards, the fighters) is split into its elements above this depth
const SESSION := "session.json"

var dir := ""          # the folder the journals and the session flag live in (user:// paths); "" = off
var path := ""         # the scene path this journal is for ("" = not saved yet)
var key := ""          # the file name (without .jsonl) of the open scene
var _base: Variant = null   # the hash tree of the last entry (null = the next entry is a whole state)
var _n := 0                 # the next entry's index (= the lines in the file)
var _force_full := true
var _f: FileAccess = null   # the file, open for appending while this journal is open
var appends := 0            # entries written this run, and the time they took on the caller's thread (us)
var total_us := 0
var last_us := 0


## the file's name for a scene: its base name, and a hash of the whole path (two scenes with one name stay apart)
static func key_for(scene_path: String) -> String:
	if scene_path == "":
		return "unsaved"
	var safe := ""
	for ch in scene_path.get_file().get_basename():
		var c := ch.unicode_at(0)
		safe += ch if (c >= 48 and c <= 57) or (c >= 97 and c <= 122) or ch in ["-", "_"] else "_"
	return "%s-%08x" % [safe.left(40), scene_path.hash() & 0xffffffff]


func open(dir_: String, scene_path: String) -> void:
	close()
	dir = dir_
	path = scene_path
	key = key_for(scene_path)
	_base = null
	_n = 0
	if dir != "" and FileAccess.file_exists(file()):
		_n = FileAccess.get_file_as_string(file()).count("\n")
	_force_full = true   # the next entry is a whole state: nothing before it is needed to read this file


func file() -> String:
	return dir.path_join(key + ".jsonl") if dir != "" else ""


## the next entry is written whole (a restore starts the journal from the state it brought back)
func force_full() -> void:
	_force_full = true


## appends the entry for `state` (main's _scene_dict(false)). False when nothing changed since the last entry
func append(state: Dictionary) -> bool:
	if dir == "":
		return false
	var t0 := Time.get_ticks_usec()
	var full := _force_full or _base == null or _n % FULL_EVERY == 0
	var tree: Variant
	var body := ""
	if full:
		tree = _tree(state, 0)
		body = "\"full\":\"%s\"" % _enc(state)
	else:
		var sets := []
		var dels := []
		tree = _walk(_base, state, 0, [], sets, dels)
		if sets.is_empty() and dels.is_empty():
			_base = tree
			return false
		var ss := PackedStringArray()
		for s in sets:
			ss.append("[%s,\"%s\"]" % [JSON.stringify(s[0]), _enc(s[1])])
		var ds := PackedStringArray()
		for p in dels:
			ds.append(JSON.stringify(p))
		body = "\"set\":[%s],\"del\":[%s]" % [",".join(ss), ",".join(ds)]
	var line := "{\"i\":%d,\"t\":%d,\"path\":%s,%s}" % [_n, int(Time.get_unix_time_from_system()), JSON.stringify(path), body]
	if _f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		_f = FileAccess.open(file(), FileAccess.READ_WRITE) if FileAccess.file_exists(file()) else FileAccess.open(file(), FileAccess.WRITE)
		if _f == null:
			return false
	_f.seek_end()
	_f.store_line(line)
	_f.flush()
	_base = tree
	_n += 1
	_force_full = false
	last_us = Time.get_ticks_usec() - t0
	total_us += last_us
	appends += 1
	return true


## the journal of the scene is gone: its work is on disk now (a save), or was given up (a scene opened on purpose)
func trim() -> void:
	close()
	if dir == "":
		return
	if FileAccess.file_exists(file()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file()))
	_base = null
	_n = 0
	_force_full = true


## the file closes (the app quits, or the journal moves to another scene)
func close() -> void:
	_f = null


## reads a journal file: {"state": the last state, "t": the last entry's time, "path": its scene, "n": the entries
## newer than `since`}. {} when no entry can be read. A torn last line ends the read; the entries before it stand
static func restore(file_path: String, since := 0) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var state := {}
	var t := 0
	var p := ""
	var n := 0
	var any := false
	for line in FileAccess.get_file_as_string(file_path).split("\n", false):
		var e: Variant = JSON.parse_string(line)
		if not (e is Dictionary) or not e.has("i"):
			break
		if e.get("full") is String:
			state = _dec(e["full"])
		else:
			for s in e.get("set", []):
				_put(state, s[0], _dec(s[1]))
			for q in e.get("del", []):
				_drop(state, q)
		t = int(e.get("t", 0))
		p = str(e.get("path", ""))
		any = true
		if t > since:
			n += 1
	if not any:
		return {}
	return {"state": state, "t": t, "path": p, "n": n}


## the session flag: true when the last run quit cleanly (or there is no flag yet)
func session_clean() -> bool:
	if dir == "" or not FileAccess.file_exists(dir.path_join(SESSION)):
		return true
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(SESSION)))
	return bool(d.get("clean", true)) if d is Dictionary else true


func set_session(clean: bool) -> void:
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir.path_join(SESSION), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"clean": clean, "t": int(Time.get_unix_time_from_system())}))
		f.close()


# ---------------------------------------------------------------- the hash tree and the diff

static func _enc(v: Variant) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(v))


static func _dec(s: String) -> Variant:
	return bytes_to_var(Marshalls.base64_to_raw(s))


static func _splits(v: Variant, d: int) -> bool:
	if v is Dictionary:
		return d < DICT_DEPTH
	return v is Array and d < ARRAY_DEPTH and not (v as Array).is_empty() and (v as Array)[0] is Dictionary


## the tree of the state: a dictionary or array of dictionaries is split (see the constants), a hash at each part below
static func _tree(v: Variant, d: int) -> Variant:
	if _splits(v, d) and v is Dictionary:
		var t := {}
		for k in v:
			t[k] = _tree(v[k], d + 1)
		return t
	if _splits(v, d):
		var a := []
		for e in v:
			a.append(_tree(e, d + 1))
		return a
	return hash(v)


## the tree of `v` as it is now, and what differs from `base` (the last tree): sets [path, value] and dels [path].
## One pass: the hash of each part is kept for the next entry; a part is copied (set) only when its hash moved.
## path is one array the walk pushes and pops (a copy is made only when a part is written)
static func _walk(base: Variant, v: Variant, d: int, path: Array, sets: Array, dels: Array) -> Variant:
	if _splits(v, d) and v is Dictionary and base is Dictionary:
		var t := {}
		for k in v:
			path.push_back(k)
			t[k] = _walk(base[k] if base.has(k) else null, v[k], d + 1, path, sets, dels)
			path.pop_back()
		for k in base:
			if not v.has(k):
				dels.append(path + [k])
		return t
	if _splits(v, d) and v is Array and base is Array and base.size() == v.size():
		var a := []
		for i in v.size():
			path.push_back(i)
			a.append(_walk(base[i], v[i], d + 1, path, sets, dels))
			path.pop_back()
		return a
	if _splits(v, d):   # a new part, or one of another shape: the whole of it, and its tree for the next entry
		sets.append([path.duplicate(), v])
		return _tree(v, d)
	var h: int = hash(v)
	if base is int and base == h:
		return h
	sets.append([path.duplicate(), v])
	return h


static func _put(root: Dictionary, p: Array, v: Variant) -> void:
	var c: Variant = root
	for j in p.size() - 1:
		c = c[int(p[j])] if c is Array else c[p[j]]
	if p.is_empty():
		return
	if c is Array:
		c[int(p[-1])] = v
	else:
		c[p[-1]] = v


static func _drop(root: Dictionary, p: Array) -> void:
	var c: Variant = root
	for j in p.size() - 1:
		c = c[int(p[j])] if c is Array else c[p[j]]
	if c is Dictionary and not p.is_empty():
		c.erase(p[-1])
