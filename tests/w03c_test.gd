extends SceneTree
## godot --path . --position 4000,4000 -s tests/w03c_test.gd     (W03c + 256: body keys on the steps that point at a body; needs the CAD DLL)
## Bars (written before the run): on tests/data/temple_w03c.json (copy of the 297-step temple part):
##  1 INSERT   insert_step at 6 of a body-making box: result ok, 0 replay errors, and every one of the original bodies (by key) keeps its volume and name (0 mismatches);
##  2 CONTROL  the same box inserted raw into the UNSTAMPED record (index lookup, no shift) breaks: > 0 mismatches or errors (the bar can fail);
##  3 DELETE   delete_step of f1 (the ground, bname'd by f2) is refused in words that name step 2 (f2); the part is unchanged;
##  4 OLD      the file as loaded carries no key field, and replays with the same bodies / volume as before the test touched it;
##  5 EDIT     an index edited by hand on a stamped step wins over its key.
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func load_rec() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/temple_w03c.json"))
	return (d as Dictionary)["part"]


## an unnamed body is called Body<place>, so its name moves with the place by design: compare it as "Body"
func _nm(n: String) -> String:
	return "Body" if n.begins_with("Body") and n.substr(4).is_valid_int() else n


## key -> "volume|name" for the bodies of a replay
func by_key(rec: Dictionary) -> Dictionary:
	var r := Part.replay(rec, -1, {"effects": true, "errors_only": true})
	var out := {}
	for i in (r["body_keys"] as Array).size():
		out[String(r["body_keys"][i])] = "%s|%s" % [String.num_scientific(float(r["volumes"][i])), _nm(str(r["body_names"][i]))]
	return {"map": out, "errors": r["errors"], "volume": r["volume"], "bodies": r["bodies"]}


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 8:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var T := AgentTools.new(m)
	var rec := load_rec()
	var raw_json := JSON.stringify(rec)
	var base := by_key(rec)
	var nb: int = base["bodies"]
	print("temple: %d steps, %d bodies, %d errors" % [(rec["features"] as Array).size(), nb, (base["errors"] as Dictionary).size()])
	ok(not PartBKeys.keyed(rec["features"]), "4 the loaded file has no key field")
	var box := {"t": "prim", "kind": "box", "op": "new", "x": 90000.0, "w": 9.0, "h": 9.0, "d": 9.0, "name": "W03c ins"}
	# 2 CONTROL first: raw insert into the unstamped record, the old index lookup
	var raw := load_rec()
	(raw["features"] as Array).insert(5, Part.new_feature(raw, "prim", {"kind": "box", "op": "new", "x": 90000.0, "w": 9.0, "h": 9.0, "d": 9.0, "name": "W03c ins"}))
	var cr := by_key(raw)
	var bad := 0
	for k in base["map"]:
		if not (cr["map"] as Dictionary).has(k) or cr["map"][k] != base["map"][k]:
			bad += 1
	print("control: raw index insert -> %d bodies mismatched, %d errors" % [bad, (cr["errors"] as Dictionary).size()])
	ok(bad > 0 or (cr["errors"] as Dictionary).size() > 0, "2 CONTROL the old index lookup targets the wrong body after the insert (%d mismatches, %d errors)" % [bad, (cr["errors"] as Dictionary).size()])
	# 1 INSERT
	m.S.part = load_rec()
	var r: Dictionary = (await T.request(1, "insert_step", {"n": 6, "feature": box})).get("result", {})
	ok(bool(r.get("ok", false)), "1 insert_step at 6 ok: %s" % str(r.get("error", "")).left(100))
	print("insert: remapped %d steps, ran %s, errors %s" % [(r.get("remapped", []) as Array).size(), str(r.get("ran")), str(r.get("errors"))])
	var after := by_key(m.S.part)
	var mism := 0
	for k in base["map"]:
		if not (after["map"] as Dictionary).has(k) or after["map"][k] != base["map"][k]:
			mism += 1
			if mism <= 4:
				print("  mismatch %s: before %s  after %s" % [k, str(base["map"][k]), str((after["map"] as Dictionary).get(k, "MISSING"))])
	ok(mism == 0, "1 every original body keeps its volume and name by key (%d mismatches of %d)" % [mism, (base["map"] as Dictionary).size()])
	ok((after["errors"] as Dictionary).is_empty() and int(after["bodies"]) == nb + 1, "1 0 replay errors, bodies %d -> %d" % [nb, int(after["bodies"])])
	ok(PartBKeys.keyed(m.S.part["features"]) and String(m.S.part["features"][5]["name"]) == "W03c ins", "1 the new step sits at place 6 and the part now carries keys")
	# 5 EDIT: a hand-edited index wins over the stamped key
	var fs: Array = m.S.part["features"]
	var bi := -1
	for i in range(8, fs.size()):
		if String(fs[i]["t"]) == "bname" and fs[i].has("bkey"):
			bi = i
			break
	if bi >= 0:
		var oldk := String(fs[bi]["bkey"])
		fs[bi]["body"] = 1
		Part.replay(m.S.part, -1, {"errors_only": true})
		ok(int(fs[bi]["body"]) == 1 and String(fs[bi]["bkey"]) != oldk, "5 an index edited by hand wins; its key follows it (%s -> %s)" % [oldk, String(fs[bi]["bkey"])])
	# 3 DELETE
	m.S.part = load_rec()
	var before_json := JSON.stringify(m.S.part)
	var d: Dictionary = await T.request(2, "delete_step", {"n": 1})
	var msg := str((d.get("error", {}) as Dictionary).get("message", ""))
	print("delete: " + msg.left(260))
	ok(d.has("error") and msg.find("2 (f2)") >= 0 and msg.find("steps") >= 0, "3 delete of a step whose body later steps use is refused, naming them")
	ok(JSON.stringify(m.S.part) == before_json, "3 the part is unchanged by the refusal")
	# 4 OLD
	var again := by_key(load_rec())
	ok(again["map"] == base["map"] and JSON.stringify(load_rec()) == raw_json, "4 an old file replays as before (no key = index)")
	print("W03C done, fails=%d" % fails)
	quit(1 if fails > 0 else 0)
