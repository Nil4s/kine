extends SceneTree
## godot --path . --position 4000,4000 -s tests/s244_test.gd     (ITEM 244 AI EASE 4: CHECKPOINT + REPLAY FROM STEP; needs the CAD DLL)
## Bars: 1 EDIT150 edit_step(150) on a 200-step part runs exactly steps 150..200 (51, Part.step_runs) and equals a full replay of the edited record (volume + box per body, exact);
##   2 EDIT199 edit_step(199) runs 2; 3 CHECKPOINT checkpoint/restore round-trips the part, building and light byte-identical; 4 REFS insert/delete keep later body numbers valid or refuse with the reason;
##   5 UNDO one undo step per call, one undo restores the pre-edit part; 6 MEMORY shapes freed after many edits (KCad.live_count back to the baseline); the time of edit_step(150) vs a full replay is printed.
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func big(n: int) -> Dictionary:
	var rec := Part.make("big")
	for k in n:
		Part.prim(rec, "box", {"x": (k % 17) * 30.0, "y": 0.0, "z": (k / 17) * 30.0, "w": 20.0, "h": 20.0, "d": 20.0, "name": "B%d" % k})
	return rec


## per body: volume, the box of its edges and its name, as text (exact). A replay WITHOUT inc: a full one
func shape_of(rec: Dictionary) -> Array:
	var r := Part.replay(rec, -1, {"keep": true, "errors_only": true})
	var out: Array = []
	for i in (r["ids"] as Array).size():
		var id := int(r["ids"][i])
		out.append("%s %s %s" % [String.num_scientific(float(r["volumes"][i])), str(Part._bbox(KCad.edges(id))), str(r["body_names"][i])])
	Part.release_kept(r["ids"])
	return out


func msg_of(r: Dictionary) -> String:
	return str((r.get("error", {}) as Dictionary).get("message", ""))


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var T := AgentTools.new(m)
	Part.inc_clear()
	var base_live := KCad.live_count()
	m.S.part = big(200)
	Part.replay(m.S.part, -1, {"inc": true, "errors_only": true})   # the cache is warm: the part was built once
	var full0 := shape_of(m.S.part)
	# 1 EDIT150
	var u0: int = m.undo.size()
	var pre := JSON.stringify(m.S.part)
	var r1: Dictionary = (await T.request(1, "edit_step", {"n": 150, "params": {"w": 33.0, "name": "Wide"}})).get("result", {})
	ok(int(r1.get("ran", -1)) == 51 and int(r1.get("from", 0)) == 150, "1 edit_step(150) ran %s steps from step %s of %s (wanted 51 = steps 150..200), %s ms" % [str(r1.get("ran")), str(r1.get("from")), str(r1.get("of")), str(r1.get("ms"))])
	ok(r1.get("changed", []) == [149] and (r1.get("created", [1]) as Array).is_empty() and (r1.get("removed", [1]) as Array).is_empty(), "1 changed/created/removed = %s / %s / %s" % [str(r1.get("changed")), str(r1.get("created")), str(r1.get("removed"))])
	var edited: Dictionary = (m.S.part as Dictionary).duplicate(true)
	var t1 := Time.get_ticks_msec()
	var full1 := shape_of(edited)
	var ms_full1 := Time.get_ticks_msec() - t1
	var inc_r := Part.replay(edited, -1, {"inc": true, "errors_only": true, "keep": true})
	var inc1: Array = []
	for i in (inc_r["ids"] as Array).size():
		inc1.append("%s %s %s" % [String.num_scientific(float(inc_r["volumes"][i])), str(Part._bbox(KCad.edges(int(inc_r["ids"][i])))), str(inc_r["body_names"][i])])
	Part.release_kept(inc_r["ids"])
	ok(full1 == inc1 and full1[149] != full0[149] and full1[148] == full0[148] and full1.size() == 200, "1 the result equals a full replay of the edited record, volumes + boxes per body exact (%d bodies); body 149 differs from before" % full1.size())
	ok(m.undo.size() == u0 + 1, "5 one call = one undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	await idle(3)
	ok(JSON.stringify(m.S.part) == pre, "5 one undo restores the pre-edit part")
	# 2 EDIT199
	var r2: Dictionary = (await T.request(2, "edit_step", {"id": "f199", "params": {"h": 7.0}})).get("result", {})
	ok(int(r2.get("ran", -1)) == 2, "2 edit_step(199) ran %s steps (wanted 2), %s ms" % [str(r2.get("ran")), str(r2.get("ms"))])
	m._undo()
	await idle(3)
	var r2b: Dictionary = (await T.request(3, "edit_step", {"n": 150, "params": {"w": 41.0}})).get("result", {})
	print("TIMING edit_step(150): %s ms (ran %s of 200 steps); full replay of the same part: %d ms" % [str(r2b.get("ms")), str(r2b.get("ran")), ms_full1])
	m._undo()
	await idle(3)
	var bad: Dictionary = await T.request(4, "edit_step", {"n": 500, "params": {"w": 1}})
	ok(bad.has("error"), "2 a step that does not exist is refused: %s" % msg_of(bad).left(80))
	# 3 CHECKPOINT
	m.S.building = {"name": "T", "nature": [{"id": "n1", "kind": "tree"}]}
	var p0: PackedByteArray = var_to_bytes(m.S.part)
	var b0: PackedByteArray = var_to_bytes(m.S.building)
	var l0 := JSON.stringify(PartReplayCalls.light_state())
	var c1: Dictionary = (await T.request(5, "checkpoint", {"name": "A"})).get("result", {})
	ok(int(c1.get("steps", 0)) == 200, "3 checkpoint A has 200 steps")
	await T.request(6, "edit_step", {"n": 10, "params": {"w": 50.0}})
	await T.request(7, "delete_step", {"n": 200})
	m.S.building = {}
	TempleLight.set_from({"time": 9.0, "clouds": 0.9})
	var lst: Dictionary = (await T.request(8, "checkpoints", {})).get("result", {})
	ok((lst["checkpoints"] as Array).size() == 1 and int(lst["checkpoints"][0]["steps"]) == 200, "3 checkpoints() lists A with its step count: %s" % str(lst["checkpoints"]))
	await T.request(9, "restore", {"name": "A"})
	ok(var_to_bytes(m.S.part) == p0 and var_to_bytes(m.S.building) == b0 and JSON.stringify(PartReplayCalls.light_state()) == l0, "3 restore gives back the part, building and light byte-identical")
	ok((await T.request(10, "restore", {"name": "nope"})).has("error"), "3 restoring an unknown name is refused")
	# 4 REFS: 5 boxes (bodies 0..4), then appear on body 3 and on body 4
	var rp := Part.make("refs")
	for k in 5:
		Part.prim(rp, "box", {"x": k * 30.0, "w": 20.0, "h": 20.0, "d": 20.0, "name": "R%d" % k})
	(rp["features"] as Array).append(Part.new_feature(rp, "appear", {"body": 3, "preset": "Custom", "color": [0.9, 0.1, 0.1]}))
	(rp["features"] as Array).append(Part.new_feature(rp, "appear", {"body": 4, "preset": "Custom", "color": [0.1, 0.1, 0.9]}))
	m.S.part = rp
	var r4: Dictionary = (await T.request(11, "insert_step", {"n": 3, "feature": {"t": "prim", "kind": "box", "op": "new", "x": 500.0, "w": 9.0, "h": 9.0, "d": 9.0, "name": "Ins"}})).get("result", {})
	var fs: Array = m.S.part["features"]
	ok(fs.size() == 8 and String(fs[2]["name"]) == "Ins", "4 insert_step put the new box at place 3 (%d steps)" % fs.size())
	ok(int(fs[6]["body"]) == 4 and int(fs[7]["body"]) == 5 and (r4.get("remapped", []) as Array).size() == 2, "4 insert: later body numbers moved 3->4 and 4->5 (%s), remapped %s" % [str([fs[6]["body"], fs[7]["body"]]), str(r4.get("remapped"))])
	var got: Array = []
	for s in shape_of(m.S.part):
		got.append((s as String).split(" ")[-1])
	ok(got == ["R0", "R1", "Ins", "R2", "R3", "R4"], "4 body order after the insert %s; created %s" % [str(got), str(r4.get("created"))])
	var d2: Dictionary = await T.request(13, "delete_step", {"n": 5})   # R3 is body 4; the first appear points at it
	ok(d2.has("error") and msg_of(d2).find("points at body 4") >= 0, "4 deleting a step whose body a later step points at is refused: %s" % msg_of(d2).left(120))
	var d3: Dictionary = (await T.request(14, "delete_step", {"n": 3})).get("result", {})
	fs = m.S.part["features"]
	ok(not d3.is_empty() and (d3.get("removed", []) as Array) == [2] and int(fs[5]["body"]) == 3 and int(fs[6]["body"]) == 4, "4 delete_step of the inserted box: removed %s, refs back to 3 / 4" % str(d3.get("removed")))
	# 6 MEMORY
	m.S.part = big(200)
	Part.replay(m.S.part, -1, {"inc": true, "errors_only": true})
	for k in 40:
		await T.request(100 + k, "edit_step", {"n": 20 + k * 4, "params": {"w": 21.0 + k}})
	m.S.part = {}
	Part.inc_clear()
	await idle(3)
	var live := KCad.live_count()
	ok(live == base_live, "6 shapes freed after 40 edits + inc_clear: live %d, baseline %d" % [live, base_live])
	print("s244: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
