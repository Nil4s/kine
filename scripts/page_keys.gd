class_name PageKeys
extends RefCounted
## P06 PAGE HOTKEYS. A binding is {cmd, key, scope}: scope "" = global, otherwise a page id (animate, model, sculpt, ...).
## resolve(key, page): the page's own binding wins, then the global one. bind() refuses a second command on the same key AND the same scope
## (it reports {conflict}; confirm=true moves the key). The same key on another scope is not a conflict.
## File: {"schema": 2, "bindings": [{cmd, key, scope}]} sorted, so the same map is the same bytes. The old schema-1 profile of hotkeys.gd
## ({"schema": 1, "keys": {cmd: key}}) loads with every binding global. Tests: tests/pagehot_test.gd.

const SCHEMA := 2
const FILE := "user://kine_pagekeys.json"

var items: Array = []   # [{cmd, key, scope}]


func _at(key: String, scope: String) -> int:
	for i in items.size():
		if String(items[i]["key"]) == key and String(items[i]["scope"]) == scope:
			return i
	return -1


func bind(key: String, cmd: String, scope := "", confirm := false) -> Dictionary:
	if key == "" or cmd == "":
		return {"ok": false, "msg": "a key and a command are needed"}
	if key in Hotkeys.RESERVED:
		return {"ok": false, "msg": "%s is fixed and cannot be bound" % key}
	var i := _at(key, scope)
	if i >= 0 and String(items[i]["cmd"]) != cmd:
		if not confirm:
			return {"ok": false, "conflict": String(items[i]["cmd"]), "msg": "%s is already %s's key on %s" % [key, items[i]["cmd"], scope if scope != "" else "every page"]}
		items.remove_at(i)
	elif i >= 0:
		return {"ok": true, "msg": "unchanged"}
	# one command has one key per scope: a rebind replaces its old key there
	for j in range(items.size() - 1, -1, -1):
		if String(items[j]["cmd"]) == cmd and String(items[j]["scope"]) == scope:
			items.remove_at(j)
	items.append({"cmd": cmd, "key": key, "scope": scope})
	return {"ok": true, "msg": "%s is now %s" % [cmd, key]}


func unbind(key: String, scope := "") -> bool:
	var i := _at(key, scope)
	if i < 0:
		return false
	items.remove_at(i)
	return true


## the command a key runs on a page: the page binding first, then the global one ("" = none)
func resolve(key: String, page: String) -> String:
	if page != "":
		var i := _at(key, page)
		if i >= 0:
			return String(items[i]["cmd"])
	var g := _at(key, "")
	return String(items[g]["cmd"]) if g >= 0 else ""


func has_cmd(cmd: String) -> bool:
	return items.any(func(b): return String(b["cmd"]) == cmd)


func has_key(key: String) -> bool:
	return items.any(func(b): return String(b["key"]) == key)


## the global bindings as the old profile map: cmd -> key
func global_map() -> Dictionary:
	var m := {}
	for b in items:
		if String(b["scope"]) == "":
			m[String(b["cmd"])] = String(b["key"])
	return m


## same key + same scope held by more than one command: [{key, scope, ids}]
func conflicts() -> Array:
	var by := {}
	for b in items:
		var k := "%s|%s" % [b["scope"], b["key"]]
		if not by.has(k):
			by[k] = {"key": String(b["key"]), "scope": String(b["scope"]), "ids": []}
		var ids: Array = by[k]["ids"]
		if not ids.has(String(b["cmd"])):
			ids.append(String(b["cmd"]))
	var out := []
	for k in by:
		if (by[k]["ids"] as Array).size() > 1:
			out.append(by[k])
	return out


func to_json() -> String:
	var a := items.duplicate(true)
	a.sort_custom(func(x, y): return "%s|%s|%s" % [x["scope"], x["key"], x["cmd"]] < "%s|%s|%s" % [y["scope"], y["key"], y["cmd"]])
	return JSON.stringify({"schema": SCHEMA, "bindings": a}, "\t", true)


## {ok, keys: PageKeys, msg}
static func from_json(txt: String) -> Dictionary:
	var j := JSON.new()
	if txt.strip_edges() == "" or j.parse(txt) != OK or not (j.data is Dictionary):
		return {"ok": false, "keys": PageKeys.new(), "msg": "the keymap file is not readable"}
	var D: Dictionary = j.data
	var pk := PageKeys.new()
	if D.has("schema") and int(D["schema"]) == 1 and D.get("keys", null) is Dictionary:
		for c in D["keys"]:
			if D["keys"][c] is String and String(D["keys"][c]) != "":
				pk.items.append({"cmd": String(c), "key": String(D["keys"][c]), "scope": ""})
		return {"ok": true, "keys": pk, "msg": "old keymap loaded as global"}
	if not D.has("schema") or int(D["schema"]) != SCHEMA or not (D.get("bindings", null) is Array):
		return {"ok": false, "keys": PageKeys.new(), "msg": "the keymap file is from another version"}
	for b in D["bindings"]:
		if not (b is Dictionary) or not (b.get("cmd", null) is String) or not (b.get("key", null) is String) or not (b.get("scope", "") is String):
			return {"ok": false, "keys": PageKeys.new(), "msg": "the keymap file has a bad binding"}
		pk.items.append({"cmd": String(b["cmd"]), "key": String(b["key"]), "scope": String(b.get("scope", ""))})
	return {"ok": true, "keys": pk, "msg": "keymap loaded"}


func save_file(path := FILE) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json())
	f.close()
	return true


## replaces the bindings with the file; a file that cannot be used leaves them empty
func load_file(path := FILE) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var r := from_json(f.get_as_text() if f != null else "")
	if f != null:
		f.close()
	items = (r["keys"] as PageKeys).items if r["ok"] else []
	return r
