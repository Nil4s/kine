class_name CmdLearn
extends RefCounted
## P18 LEARN-FROM-ME HOTKEYS. record(id) counts every command run. suggest(cmds, keys) lists the most-used commands that have no hotkey
## (neither in the registry "keys" nor in PageKeys), each with a free key to offer: [{id, name, runs, key}], most runs first.
## The UI shows it as a non-modal toast: accept() binds the key (global), dismiss() is remembered for good (also after a restart).
## File: {"schema": 1, "runs": {id: n}, "dismissed": [ids]} (user://kine_cmd_learn.json). Tests: tests/pagehot_test.gd.

const SCHEMA := 1
const MIN_RUNS := 3
const LIMIT := 3

var path := "user://kine_cmd_learn.json"
var counts := {}
var dismissed: Array = []


func _init(p := "user://kine_cmd_learn.json") -> void:
	path = p
	load_file()


func record(id: String) -> void:
	counts[id] = int(counts.get(id, 0)) + 1


func runs(id: String) -> int:
	return int(counts.get(id, 0))


func is_dismissed(id: String) -> bool:
	return dismissed.has(id)


func dismiss(id: String) -> void:
	if not dismissed.has(id):
		dismissed.append(id)
	save_file()


static func candidates() -> Array:
	var out := []
	for pre in ["Alt+", "Ctrl+Alt+", "Ctrl+Shift+"]:
		for ch in "QWERTYUIOPASDFGHJKLZXCVBNM1234567890":
			out.append(pre + ch)
	return out


func suggest(cmds: Array, keys: PageKeys, min_runs := MIN_RUNS, limit := LIMIT) -> Array:
	var used := {}
	for c in cmds:
		if String(c["keys"]) != "":
			used[String(c["keys"])] = true
	for b in keys.items:
		used[String(b["key"])] = true
	var rows := []
	for c in cmds:
		var id := String(c["id"])
		if String(c["keys"]) != "" or keys.has_cmd(id) or dismissed.has(id) or runs(id) < min_runs:
			continue
		rows.append({"id": id, "name": String(c.get("name", id)), "runs": runs(id)})
	rows.sort_custom(func(a, b): return a["runs"] > b["runs"] or (a["runs"] == b["runs"] and a["id"] < b["id"]))
	var out := []
	var cand := candidates()
	for r in rows:
		if out.size() >= limit:
			break
		for k in cand:
			if not used.has(k):
				used[k] = true
				r["key"] = k
				out.append(r)
				break
	return out


## the user said yes: bind the offered key globally
func accept(id: String, key: String, keys: PageKeys) -> Dictionary:
	return keys.bind(key, id)


func save_file() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"schema": SCHEMA, "runs": counts, "dismissed": dismissed}, "\t", true))
	f.close()
	return true


func load_file() -> void:
	counts = {}
	dismissed = []
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var j := JSON.new()
	var parsed := j.parse(f.get_as_text()) == OK
	f.close()
	if not parsed or not (j.data is Dictionary) or int(j.data.get("schema", 0)) != SCHEMA:
		return
	var R: Variant = j.data.get("runs", {})
	if R is Dictionary:
		for k in R:
			counts[String(k)] = int(R[k])
	var D: Variant = j.data.get("dismissed", [])
	if D is Array:
		for k in D:
			dismissed.append(String(k))
