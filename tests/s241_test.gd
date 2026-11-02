extends SceneTree
## S241 WHAT A STEP DID (AI ease 1): every Part feature call and agent call that creates or changes bodies returns {step, feature, created, changed, removed}
## (scripts/build/part_fx.gd), taken from the replay's own body list. Bars: each call's created / changed / removed set is checked against the part's body
## list before and after (counts, names at the returned ids), a 2x linear pattern = 1 created "Plinth 2", a join/combine names the removed ids,
## rename = changed with "was", delete = removed, replay keeps keys + names, agent roof / ornament carry the same fields beside their old ones.
var fails := 0
var m: Node
const PartText := preload("res://scripts/build/part_text.gd")


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func names_of(rec: Dictionary) -> Array:
	return Part.replay(rec.duplicate(true)).get("body_names", [])


## check a returned effect against the body lists before / after; "" = consistent
func consistent(r: Dictionary, before: Array, after: Array) -> String:
	if after.size() != before.size() + r["created"].size() - r["removed"].size():
		return "count %d -> %d but created %d removed %d" % [before.size(), after.size(), r["created"].size(), r["removed"].size()]
	for c in r["created"]:
		if int(c["id"]) >= after.size() or String(after[int(c["id"])]) != String(c["name"]):
			return "created %s not at its id in the after list" % str(c)
	for c in r["changed"]:
		if int(c["id"]) >= after.size() or String(after[int(c["id"])]) != String(c["name"]):
			return "changed %s not at its id in the after list" % str(c)
	for c in r["removed"]:
		if int(c["id"]) >= before.size() or String(before[int(c["id"])]) != String(c["name"]):
			return "removed %s not at its id in the before list" % str(c)
	return ""


func go(rec: Dictionary, t: String, fields: Dictionary) -> Dictionary:
	var before := names_of(rec)
	var r := PartFx.append(rec, t, fields)
	var why := consistent(r, before, names_of(rec))
	if why != "":
		r["bad"] = why
	return r


func box(rec: Dictionary, nm: String, x: float, op := "new", into := -1) -> Dictionary:
	var f := {"x": x, "y": 0.0, "z": 0.0, "w": 100.0, "h": 100.0, "d": 100.0, "name": nm, "op": op, "kind": "box"}
	if into >= 0:
		f["into"] = into
	return go(rec, "prim", f)


func sets(r: Dictionary) -> String:
	return "created %d changed %d removed %d" % [r["created"].size(), r["changed"].size(), r["removed"].size()]


func shape(r: Dictionary, c: int, ch: int, rm: int) -> bool:
	return r.get("bad", "") == "" and bool(r.get("ok", false)) and r["created"].size() == c and r["changed"].size() == ch and r["removed"].size() == rm


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	if not Part.available():
		print("FAIL no DLL")
		quit(1)
		return
	var rec := Part.make("s241")

	# ---- box / prim (new), sketch + extrude (new, join), revolve
	var r := box(rec, "Plinth", 0.0)
	ok(shape(r, 1, 0, 0) and r["created"][0]["name"] == "Plinth" and int(r["created"][0]["id"]) == 0 and String(r["created"][0]["key"]) != "", "1 prim box new: 1 created 'Plinth' id 0 with a key (%s)" % sets(r))
	ok(int(r["step"]) == 0 and String(r["feature"]) == String(r["id"]) and r["t"] == "prim", "2 the entry names its step index and feature")
	var k_plinth := String(r["created"][0]["key"])
	var rs := go(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [300.0, 0.0], "b": [400.0, 100.0]}], "dims": [], "name": "Sk"})
	ok(shape(rs, 0, 0, 0), "3 a sketch makes and changes nothing (%s)" % sets(rs))
	var re := go(rec, "extrude", {"sketch": rs["id"], "dist": 100.0, "both": false, "op": "new", "name": "Pillar"})
	ok(shape(re, 1, 0, 0) and re["created"][0]["name"] == "Pillar", "4 sketch extrude new: 1 created Pillar (%s)" % sets(re))
	var rs2 := go(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [50.0, 0.0], "b": [150.0, 100.0]}], "dims": [], "name": "Sk2"})
	var rj := go(rec, "extrude", {"sketch": rs2["id"], "dist": 100.0, "both": false, "op": "join", "into": 0})
	ok(shape(rj, 0, 1, 0) and rj["changed"][0]["key"] == k_plinth and int(rj["changed"][0]["id"]) == 0, "5 extrude join into body 0: Plinth changed, same key (%s)" % sets(rj))
	var rs3 := go(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [500.0, 0.0], "b": [550.0, 100.0]}], "dims": [], "name": "Sk3"})
	var rv := go(rec, "revolve", {"sketch": rs3["id"], "axis": "y", "deg": 360.0, "op": "new", "name": "Drum"})
	ok(shape(rv, 1, 0, 0) and rv["created"][0]["name"] == "Drum", "6 revolve new: 1 created Drum (%s)" % sets(rv))
	var drum := int(rv["created"][0]["id"])
	var k_drum := String(rv["created"][0]["key"])

	# ---- pattern: 2x linear (new) = 1 created; 3x = 2; join = changed; circular; grid
	var p2 := go(rec, "pattern", {"body": 0, "kind": "linear", "count": 2, "dir": "z", "mm": 300.0, "op": "new"})
	ok(shape(p2, 1, 0, 0) and p2["created"][0]["name"] == "Plinth 2", "7 2x linear pattern op new: 1 created named 'Plinth 2' (%s: %s)" % [sets(p2), str(p2["created"])])
	var p3 := go(rec, "pattern", {"body": 0, "kind": "linear", "count": 3, "dir": "z", "mm": -300.0, "op": "new"})
	ok(shape(p3, 2, 0, 0) and p3["created"][0]["name"] == "Plinth 2" and p3["created"][1]["name"] == "Plinth 3", "8 3x linear op new: 2 created, the new ids are the last two (%s)" % str(p3["created"]))
	var pj := go(rec, "pattern", {"body": drum, "kind": "linear", "count": 2, "dir": "x", "mm": 200.0, "op": "join"})
	ok(shape(pj, 0, 1, 0) and pj["changed"][0]["key"] == k_drum, "9 pattern join: the source body changed, nothing created (%s)" % sets(pj))
	var pc := go(rec, "pattern", {"body": 0, "kind": "circular", "count": 4, "axis": "y", "deg": 360.0, "op": "new"})
	ok(shape(pc, 3, 0, 0), "10 circular pattern op new x4: 3 created (%s)" % sets(pc))
	var pg := go(rec, "pattern", {"body": 0, "kind": "grid", "count": 2, "mm": 250.0, "dir": "x", "rows": 2, "mm2": 250.0, "dir2": "z", "layers": 1, "mm3": 0.0, "dir3": "y", "op": "new"})
	print("     grid: ", sets(pg), " ", pg.get("error", ""), " ", pg.get("bad", ""))
	ok(shape(pg, 3, 0, 0), "11 grid pattern 2x2 op new: 3 created (%s, ok %s)" % [sets(pg), str(pg["ok"])])

	# ---- mirror
	var rm := Part.make("mirror")
	box(rm, "Wing", 100.0)
	var mi := go(rm, "mirror", {"plane": "right", "op": "join"})
	ok(mi.get("bad", "") == "" and bool(mi["ok"]) and mi["changed"].size() == 1 and mi["created"].size() == 0, "12 mirror: the last body changed (%s)" % sets(mi))

	# ---- combine: join returns the removed ids; cut; intersect; keep
	var rc := Part.make("combine")
	box(rc, "Base", 0.0)
	var cap := box(rc, "Cap", 50.0)
	var cj := go(rc, "combine", {"target": 0, "tools": [1], "op": "join", "keep": false})
	ok(shape(cj, 0, 1, 1) and cj["removed"][0]["name"] == "Cap" and int(cj["removed"][0]["id"]) == 1 and cj["removed"][0]["key"] == cap["created"][0]["key"], "13 combine join: Cap removed (id 1, its own key), Base changed (%s)" % sets(cj))
	box(rc, "Tool", 50.0)
	var cc := go(rc, "combine", {"target": 0, "tools": [1], "op": "cut", "keep": false})
	ok(shape(cc, 0, 1, 1) and cc["removed"][0]["name"] == "Tool", "14 combine cut: Tool removed, target changed (%s)" % sets(cc))
	box(rc, "Probe", 20.0)
	var ci := go(rc, "combine", {"target": 0, "tools": [1], "op": "intersect", "keep": true})
	ok(shape(ci, 0, 1, 0), "15 combine intersect keep: target changed, tool kept (%s)" % sets(ci))
	box(rc, "Early", 10.0)
	var cr := go(rc, "combine", {"target": 2, "tools": [0], "op": "join", "keep": false})
	ok(shape(cr, 0, 1, 1) and cr["removed"][0]["id"] == 0 and cr["changed"][0]["name"] == "Early", "16 combine whose tool comes BEFORE its target pairs by the fields (%s)" % str(cr))
	var rj2 := Part.make("opjoin")
	box(rj2, "A", 0.0)
	var bj := box(rj2, "B", 50.0, "join", 0)
	ok(shape(bj, 0, 1, 0) and bj["changed"][0]["name"] == "A", "17 prim op join into 0: A changed (%s)" % sets(bj))
	var rcut := Part.make("opcut")
	box(rcut, "A", 0.0)
	var bc := box(rcut, "C", 50.0, "cut", 0)
	ok(shape(bc, 0, 1, 0), "18 prim op cut: A changed (%s)" % sets(bc))

	# ---- split
	var rsp := Part.make("split")
	box(rsp, "Slab", 0.0)
	var sp := go(rsp, "split", {"plane": "right", "at": 50.0})
	ok(shape(sp, 1, 1, 0) and sp["changed"][0]["name"] == "Slab", "19 split: the cut body changed, its other half created (%s: %s)" % [sets(sp), str(sp["created"])])

	# ---- text (part_text) as steps
	var rt := Part.make("text")
	var tx: Dictionary = PartText.part_record("KINE", 100.0, 20.0)
	var tsk := go(rt, "sketch", {"plane": "top", "ents": tx["rec"]["features"][0]["ents"], "dims": []})
	var tex := go(rt, "extrude", {"sketch": tsk["id"], "dist": 20.0, "both": false, "op": "new", "name": "Letters"})
	ok(shape(tex, 4, 0, 0) and tex["created"][0]["name"] == "Letters 1" and tex["created"][3]["name"] == "Letters 4", "20 part_text KINE: one body per letter, 4 created named Letters 1..4 (%s: %s)" % [sets(tex), str(tex["created"].map(func(c): return c["name"]))])

	# ---- agent calls: roof, ornament (old fields kept, new fields beside them)
	var at := AgentTools.new(m)
	m.S.part = Part.make("s241 roof")
	var rr: Dictionary = await at.request(1, "part_roof", {"type": "hip", "w": 6000, "d": 4000, "overhang": 400, "height": 1500, "thick": 100, "name": "Roof"})
	var rres: Dictionary = rr.get("result", {})
	ok(rr.has("result") and rres.has("id") and rres.has("volume_mm3") and rres.has("box_mm") and rres.has("words"), "21 part_roof keeps its old fields")
	var rn := names_of(m.S.part)
	ok(rres.has("created") and rres["created"].size() == int(rres["bodies"]) and int(rres["step"]) == 0 and rres["created"].size() >= 1, "22 part_roof returns created = every body it made (%d of %d)" % [rres.get("created", []).size(), int(rres.get("bodies", -1))])
	ok(consistent(rres["fx"], [], rn) == "" and rres["changed"].is_empty() and rres["removed"].is_empty(), "23 roof entry matches the body list: %s" % str(rn))
	var roof_keys: Array = rres["created"].map(func(c): return c["key"])
	var orr: Dictionary = await at.request(2, "ornament", {"kind": "ridge_dragon", "count": 2, "seed": 3, "size": [1000.0, 1100.0, 300.0], "roof": true})
	var ores: Dictionary = orr.get("result", {})
	ok(ores.has("kind") and ores.has("places") and ores.has("box_mm"), "24 ornament keeps its old fields")
	ok(ores.get("created", []).size() == 2 and ores["changed"].is_empty() and ores["removed"].is_empty() and consistent(ores["fx"], rn, names_of(m.S.part)) == "", "25 ornament x2 returns 2 created, consistent with the list (%s)" % str(ores.get("created", [])))
	var o_keys: Array = ores["created"].map(func(c): return c["key"])
	ok(not o_keys.any(func(k): return roof_keys.has(k)), "26 keys differ between the roof's bodies and the ornaments")

	# ---- rename (changed with was), delete (removed), replay keeps ids/keys
	var rn_rec := Part.make("rename")
	box(rn_rec, "Door", 0.0)
	box(rn_rec, "Wall", 300.0)
	var res0 := Part.replay(rn_rec, -1, {"effects": true})
	var rnm := PartFx.rename(rn_rec, 1, "Door panel high")
	ok(bool(rnm["ok"]) and rnm["changed"].size() == 1 and rnm["created"].is_empty() and rnm["removed"].is_empty() and rnm["changed"][0]["name"] == "Door panel high" and rnm["changed"][0]["was"] == "Wall" and rnm["changed"][0]["key"] == res0["body_keys"][1], "27 rename: changed 1 with name and was, same key (%s)" % str(rnm["changed"]))
	var rnm2 := PartFx.rename(rn_rec, 1, "Door panel high")
	ok(not bool(rnm2["ok"]) and rnm2["changed"].is_empty(), "28 renaming to the same name changes nothing")
	var rnm3 := PartFx.rename(rn_rec, 1, "Door panel low")
	ok(bool(rnm3["ok"]) and rnm3["changed"].size() == 1 and rnm3["changed"][0]["was"] == "Door panel high", "29 a second rename (rewrites the naming step) reports the net change")
	var bn := Part.new_feature(rn_rec, "bname", {"name": "N", "body": 0, "called": "Left door"})
	(rn_rec["features"] as Array).append(bn)
	var bne := PartFx.after(rn_rec, bn)
	ok(shape(bne, 0, 1, 0) and bne["changed"][0]["was"] == "Door", "30 a bname step appended: changed 1 with was (%s)" % str(bne["changed"]))
	var before_del := names_of(rn_rec)
	var first := String((rn_rec["features"] as Array)[0]["id"])
	var dl := PartFx.delete(rn_rec, first)
	ok(bool(dl["ok"]) and dl["removed"].size() == 1 and dl["removed"][0]["name"] == "Left door" and dl["created"].is_empty() and int(dl["step"]) == 0, "31 delete the first box: its body removed (%s)" % str(dl["removed"]))
	ok(names_of(rn_rec).size() == before_del.size() - 1, "32 delete matches the lists (%d -> %d)" % [before_del.size(), names_of(rn_rec).size()])

	# ---- replay stability
	var ra := Part.replay(rec, -1, {"effects": true})
	var rb := Part.replay(rec, -1, {"effects": true})
	ok(ra["body_keys"] == rb["body_keys"] and ra["body_names"] == rb["body_names"] and ra["effects"] == rb["effects"], "33 replay twice: same keys, names and effects (%d bodies)" % ra["bodies"])
	var ku := {}
	for k in ra["body_keys"]:
		ku[k] = true
	ok(ku.size() == ra["body_keys"].size() and ra["body_keys"].size() == int(ra["bodies"]), "34 keys are unique, one per body")
	ok(String(ra["body_keys"][0]) == k_plinth, "35 Plinth keeps its key after every later join / pattern / combine (%s)" % k_plinth)
	var upto := Part.replay(rec, 3, {"effects": true})
	ok(upto["body_keys"][0] == ra["body_keys"][0] and ra["effects"].size() == (rec["features"] as Array).size(), "36 a prefix replay gives the same first key; one effect entry per step (%d)" % ra["effects"].size())
	var sumc := 0
	var sumr := 0
	for e in ra["effects"]:
		sumc += e["created"].size()
		sumr += e["removed"].size()
	ok(int(ra["bodies"]) == sumc - sumr, "37 created - removed over all steps = body count (%d - %d = %d)" % [sumc, sumr, ra["bodies"]])
	var plain := Part.replay(rec)
	ok(not plain.has("effects") and plain["bodies"] == ra["bodies"] and absf(float(plain["volume"]) - float(ra["volume"])) < 1e-12, "38 a replay without the want is unchanged (no effects key, same bodies and volume)")
	print("s241: %d fail" % fails)
	quit(1 if fails > 0 else 0)
