## godot --headless --path . -s tests/keytypes_test.gd     (ROADMAP 66; headless)
## KEY TYPES on part keys (scripts/part_keys.gd "ktype": key / breakdown / inbetween). Bars stated before the run:
##   - TYPE ROUND TRIP: a breakdown and an in-between survive to_file -> JSON text -> from_file (3 of 3 types read back),
##     and the file holds "ktype" only for the 2 non-default keys;
##   - DEFAULT FILES HASH IDENTICALLY: keys with no "ktype" and the same keys after set_ktype(.., "key") write the same
##     text (same hash), with no "ktype" in it; a file without the field reads every key as "key";
##   - BREAKDOWN ON THE CURVE: add_breakdown at t = 0.6 s (between keys at 0 / 1 / 2 s) puts a key whose angles equal
##     at() before the insertion within 0.01 deg per angle, in memory AND after a save / load; value_at agrees too;
##     at a key's own time, outside the keys, and twice at one time it refuses (false, nothing changed);
##   - MIRRORED: mirror_file puts the type on the twin's keys (breakdown and in-between);
##   - COMMANDS (main.tscn headless, combo3): "Breakdown: add a key at the playhead in between" adds one breakdown key on
##     the curve, ONE undo step (Ctrl+Z takes it back to 2 keys); "Part key type: breakdown" on the key at the playhead is
##     ONE undo step and back on undo; "pick only main keys" picks the 2 main keys of 3 (a breakdown between them is left out).
extends SceneTree

var fails := 0
var nok := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	nok += 1
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func maxd(a: Vector3, b: Vector3) -> float:
	return maxf(absf(a.x - b.x), maxf(absf(a.y - b.y), absf(a.z - b.z)))


func K(pairs: Array) -> Array:
	var out := []
	for p in pairs:
		out.append({"t": float(p[0]), "v": p[1]})
	return out


func kinds(keys: Array) -> String:
	return ",".join(keys.map(func(k): return PartKeys.ktype_of(k)))


func _init() -> void:
	var base := func() -> Dictionary:
		return {"hand_l": K([[0.0, Vector3(0, 0, 0)], [1.0, Vector3(40, -10, 5)], [2.0, Vector3(10, 0, 0)]])}

	# A. the type round trip through the file's text
	var pk: Dictionary = base.call()
	PartKeys.set_ktype(pk, "hand_l", 1, "breakdown")
	PartKeys.set_ktype(pk, "hand_l", 2, "inbetween")
	var txt := JSON.stringify(PartKeys.to_file(pk))
	var back := PartKeys.from_file(JSON.parse_string(txt))
	ok(kinds(back["hand_l"]) == "key,breakdown,inbetween", "A round trip: the 3 keys read back as key,breakdown,inbetween (%s)" % kinds(back["hand_l"]))
	ok(txt.count("ktype") == 2, "A the file holds \"ktype\" for the 2 non-default keys only (%d)" % txt.count("ktype"))

	# B. default files hash identically
	var d1: Dictionary = base.call()
	var d2: Dictionary = base.call()
	PartKeys.set_ktype(d2, "hand_l", 1, "breakdown")
	PartKeys.set_ktype(d2, "hand_l", 1, "key")   # back to the default: erased, not stored
	var t1 := JSON.stringify(PartKeys.to_file(d1))
	var t2 := JSON.stringify(PartKeys.to_file(d2))
	ok(t1 == t2 and t1.hash() == t2.hash() and t1.count("ktype") == 0, "B default keys write the same text as after set_ktype(key): hash %d == %d, 0 \"ktype\" in it" % [t1.hash(), t2.hash()])
	var old := PartKeys.from_file(JSON.parse_string(t1))
	ok(kinds(old["hand_l"]) == "key,key,key", "B a file without the field reads every key as key (%s)" % kinds(old["hand_l"]))

	# C. the breakdown on the curve (in memory, then after a save / load)
	var pc: Dictionary = base.call()
	var t := 0.6
	var before := PartKeys.at(pc["hand_l"], t)
	var vb := PartKeys.value_at(pc["hand_l"], t)
	ok(PartKeys.add_breakdown(pc, "hand_l", t), "C add_breakdown between keys: true")
	var after := PartKeys.at(pc["hand_l"], t)
	var key_here := PartKeys.key_near(pc["hand_l"], t, PartKeys.SAME_T)
	var dev := maxd(after, before)
	ok(dev < 0.01 and key_here >= 0 and PartKeys.ktype_of(pc["hand_l"][key_here]) == "breakdown" and pc["hand_l"].size() == 4,
		"C in memory: the breakdown sits on the curve, deviation %.6f deg (bar 0.01), %d keys" % [dev, pc["hand_l"].size()])
	ok(maxd(PartKeys.value_at(pc["hand_l"], t), vb) < 0.01, "C value_at (modifiers) agrees too: %.6f deg" % maxd(PartKeys.value_at(pc["hand_l"], t), vb))
	var loaded := PartKeys.from_file(JSON.parse_string(JSON.stringify(PartKeys.to_file(pc))))
	var dev2 := maxd(PartKeys.at(loaded["hand_l"], t), before)
	ok(dev2 < 0.01, "C after save / load: deviation %.6f deg (bar 0.01)" % dev2)
	ok(not PartKeys.add_breakdown(pc, "hand_l", 0.0) and not PartKeys.add_breakdown(pc, "hand_l", 2.5) and not PartKeys.add_breakdown(pc, "hand_l", 1.0) and pc["hand_l"].size() == 4,
		"C refuses outside the keys, on a key's own time, and does not change the keys")

	# E. the commands, through main (headless)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.sel = "lowerarm_r"
	var S = m.S
	# D. mirrored by mirror_file (the twin hand_r) and the file: the body is main's
	var mf := PartKeys.mirror_file(PartKeys.to_file(pc), m.B)
	ok(mf.has("hand_r") and (mf["hand_r"] as Array).size() == 4 and mf["hand_r"][1].get("ktype") == "breakdown", "D mirror_file: the twin's key at 0.6 s is a breakdown (%s)" % str(mf.get("hand_r", [])).substr(0, 80))
	S.part_keys["lowerarm_r"] = K([[0.2, Vector3(5, 0, 0)], [0.8, Vector3(30, 2, 0)]])
	m.playhead = 0.5
	var u0: int = m.undo.size()
	m._part_breakdown()
	var ks: Array = S.part_keys["lowerarm_r"]
	ok(ks.size() == 3 and kinds(ks) == "key,breakdown,key" and m.undo.size() == u0 + 1, "E Breakdown command: 3 keys (%s), %d undo step" % [kinds(ks), m.undo.size() - u0])
	m._undo()
	ok((S.part_keys["lowerarm_r"] as Array).size() == 2 and m.undo.size() == u0, "E Ctrl+Z takes the breakdown back: %d keys, %d undo steps" % [(S.part_keys["lowerarm_r"] as Array).size(), m.undo.size() - u0])
	m._part_breakdown()   # again, for the picks below
	m.playhead = 0.2
	var u1: int = m.undo.size()
	m._part_ktype("breakdown")
	ok(PartKeys.ktype_of(S.part_keys["lowerarm_r"][0]) == "breakdown" and m.undo.size() == u1 + 1, "E Part key type command: the key at the playhead is a breakdown, %d undo step" % (m.undo.size() - u1))
	m._undo()
	ok(PartKeys.ktype_of(S.part_keys["lowerarm_r"][0]) == "key", "E Ctrl+Z puts the key back")
	m._part_ktype("breakdown")   # 0.2 breakdown, 0.5 breakdown, 0.8 key: then pick only main keys
	var ce := CurveEditor.new()
	ce.scene = S
	ce.joint = "lowerarm_r"
	ce.visible = true
	m.ui_curve = ce
	m._curve_main_keys()
	var said: String = m.ui_status.text
	ok(ce.picked_keys() == [2] and said.contains("picked 1 main key"), "E pick only main keys: picks %s (the one main key), status '%s'" % [str(ce.picked_keys()), said])
	m.playhead = 0.5
	ce.picked = []
	m._part_ktype("key")   # no picks: the key at the playhead (0.5 s) goes back to key
	ce.pick_main_keys()
	ok(ce.picked_keys() == [1, 2] and ce.picked.size() == 6 and kinds(S.part_keys["lowerarm_r"]) == "breakdown,key,key", "E after the 0.5 s key is back to key: picks %s (6 dots), types %s" % [str(ce.picked_keys()), kinds(S.part_keys["lowerarm_r"])])
	ce.picked = [[0, 2]]   # a pick on the curve editor wins over the playhead: the 0.8 s key becomes a breakdown
	m._part_ktype("breakdown")
	ok(kinds(S.part_keys["lowerarm_r"]) == "breakdown,key,breakdown", "E with a pick on the 0.8 s key the pick is the one set, not the playhead's 0.5 s: %s" % kinds(S.part_keys["lowerarm_r"]))

	print("%d ok" % (nok - fails))
	print("KEYTYPES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
