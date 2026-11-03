extends SceneTree
## godot --path . --position 4000,4000 -s tests/w03e_test.gd     (W03e: the incremental cache works on a KEYED part; nested face.body refs are keyed; needs the CAD DLL)
## Bars (written before the run), on tests/data/temple_w03c.json stamped with keys (PartBKeys.stamp):
##  1 KEYED    the stamped temple is keyed, and a warm full replay with {"inc"} stores snapshots;
##  2 RANGE    edit_step at 290 (w 700 -> 720) runs exactly steps 290..297 (8 step runs, "from" 290) not 297;
##  3 HASH     the mesh after that edit hashes equal to a FULL replay (no cache) of the edited record, and volumes + errors are equal;
##  4 TIME     edit time and full-replay time are printed; bar: the edit is faster than the full replay (control);
##  5 CONTROL  with the cache cleared (cold), the same edit runs all 297 steps (the bar "ran 8" can fail);
##  6 NESTED   offset_face face.body and draft faces[].body get keys; after insert_step of a body-making box before them they follow the body (face.body == step body),
##             0 errors; CONTROL: the raw index insert leaves face.body on the old number (!= body).
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func load_rec() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/temple_w03c.json"))
	return (d as Dictionary)["part"]


func mesh_hash(res: Dictionary) -> String:
	var mesh: ArrayMesh = res["mesh"]
	if mesh == null:
		return "none"
	var h := ""
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		h += str((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array().hex_encode().sha256_text())
	return h.sha256_text()


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
	PartBKeys.stamp(rec)
	var nfe: int = (rec["features"] as Array).size()
	ok(PartBKeys.keyed(rec["features"]), "1 the stamped temple is keyed (%d steps)" % nfe)
	# warm
	Part.inc_clear()
	var t0 := Time.get_ticks_usec()
	var w0 := Part.step_runs
	Part.replay(rec, -1, {"inc": true, "errors_only": true})
	print("warm full replay: %d step runs, %.0f ms" % [Part.step_runs - w0, (Time.get_ticks_usec() - t0) / 1000.0])
	var w1 := Part.step_runs
	Part.replay(rec, -1, {"inc": true, "errors_only": true})
	ok(Part.step_runs - w1 == 0, "1 an unchanged keyed part replays 0 steps from the cache (%d)" % (Part.step_runs - w1))
	# edit 290 incrementally
	m.S.part = rec.duplicate(true)
	var r: Dictionary = (await T.request(1, "edit_step", {"n": 290, "params": {"w": 720.0}})).get("result", {})
	print("edit_step 290: ok=%s ran=%s of=%s from=%s ms=%s errors=%s" % [str(r.get("ok")), str(r.get("ran")), str(r.get("of")), str(r.get("from")), str(r.get("ms")), str(r.get("errors")).left(80)])
	ok(bool(r.get("ok", false)) and int(r.get("from", 0)) == 290 and int(r.get("ran", 999)) <= nfe - 289 + 1, "2 edit at 290 ran %s steps (from %s), the part has %d" % [str(r.get("ran")), str(r.get("from")), nfe])
	var edited: Dictionary = m.S.part
	# time + hash: incremental replay of the edited record vs a full one
	var edited_inc := edited.duplicate(true)
	Part.replay(edited_inc, -1, {"inc": true, "errors_only": true})   # make sure the edited chain is cached too
	var ei := edited.duplicate(true)
	ei["features"][289]["w"] = 740.0   # a second edit at 290, timed through the cache
	var s1 := Part.step_runs
	var ta := Time.get_ticks_usec()
	var ri := Part.replay(ei, -1, {"inc": true})
	var ms_inc := (Time.get_ticks_usec() - ta) / 1000.0
	var ran_inc := Part.step_runs - s1
	var s2 := Part.step_runs
	var tb := Time.get_ticks_usec()
	var rf := Part.replay(ei.duplicate(true), -1, {})
	var ms_full := (Time.get_ticks_usec() - tb) / 1000.0
	var ran_full := Part.step_runs - s2
	print("TIME incremental: %d steps, %.0f ms   full replay (control): %d steps, %.0f ms" % [ran_inc, ms_inc, ran_full, ms_full])
	ok(ran_inc == nfe - 289 and ran_full == nfe, "2 incremental ran %d (= %d), full ran %d (= %d)" % [ran_inc, nfe - 289, ran_full, nfe])
	ok(mesh_hash(ri) == mesh_hash(rf) and mesh_hash(ri) != "none", "3 mesh hash equal: %s" % mesh_hash(ri).left(12))
	ok(is_equal_approx(float(ri["volume"]), float(rf["volume"])) and (ri["errors"] as Dictionary) == (rf["errors"] as Dictionary) and int(ri["bodies"]) == int(rf["bodies"]), "3 volume %s vs %s, same errors, bodies %d" % [str(ri["volume"]), str(rf["volume"]), int(ri["bodies"])])
	ok(ms_inc < ms_full, "4 the edit is faster than the full replay (%.0f vs %.0f ms)" % [ms_inc, ms_full])
	# 5 CONTROL cold
	Part.inc_clear()
	var s3 := Part.step_runs
	Part.replay(ei.duplicate(true), -1, {"inc": true, "errors_only": true})
	ok(Part.step_runs - s3 == nfe, "5 CONTROL a cold cache runs all %d steps (%d)" % [nfe, Part.step_runs - s3])
	# 6 NESTED
	var np := Part.make("nested")
	Part.prim(np, "box", {"x": 0.0, "y": 0.0, "z": 0.0, "w": 40.0, "h": 40.0, "d": 40.0, "name": "A"})
	Part.prim(np, "box", {"x": 100.0, "y": 0.0, "z": 0.0, "w": 40.0, "h": 40.0, "d": 40.0, "name": "B"})
	var fr := Part.replay(np, -1, {"faces": true})
	var fd: Dictionary = {}
	var fd2: Dictionary = {}
	for fc in fr["faces"]:
		if int(fc["body"]) == 1 and (fc["n"] as Vector3).dot(Vector3(0, 1, 0)) > 0.9:
			fd = Part.describe_face(fc)
		if int(fc["body"]) == 1 and (fc["n"] as Vector3).dot(Vector3(1, 0, 0)) > 0.9:
			fd2 = Part.describe_face(fc)
	ok(not fd.is_empty() and not fd2.is_empty() and int(fd["body"]) == 1, "6 setup: face descriptors on body 1")
	(np["features"] as Array).append(Part.new_feature(np, "offset_face", {"body": 1, "face": fd, "mm": 5.0}))
	(np["features"] as Array).append(Part.new_feature(np, "draft", {"body": 1, "faces": [fd2], "deg": 2.0, "dir": "y"}))
	var raw := np.duplicate(true)
	(raw["features"] as Array).insert(0, Part.new_feature(raw, "prim", {"kind": "box", "op": "new", "x": 900.0, "w": 9.0, "h": 9.0, "d": 9.0, "name": "N"}))
	# CONTROL: raw insert leaves the nested number behind
	var fo: Dictionary = (raw["features"] as Array)[3]
	ok(int(fo["face"]["body"]) == 1 and int(fo["body"]) == 1, "6 CONTROL raw index insert leaves face.body at 1 (the body it described is now 2 by place; the number is stale)")
	m.S.part = np.duplicate(true)
	var ri2: Dictionary = (await T.request(2, "insert_step", {"n": 1, "feature": {"t": "prim", "kind": "box", "op": "new", "x": 900.0, "w": 9.0, "h": 9.0, "d": 9.0, "name": "N"}})).get("result", {})
	ok(bool(ri2.get("ok", false)), "6 insert_step at 1 ok: %s" % str(ri2.get("error", "")).left(100))
	var fs: Array = m.S.part["features"]
	var offf: Dictionary = fs[3]
	var drf: Dictionary = fs[4]
	print("offset_face: body=%s face.body=%s face_bk=%s   draft: body=%s faces.body=%s faces_bk=%s" % [str(offf.get("body")), str(offf["face"].get("body")), str(offf.get("face_bk")), str(drf.get("body")), str(drf["faces"][0].get("body")), str(drf.get("faces_bk"))])
	ok(offf.has("face_bk") and drf.has("faces_bk"), "6 nested refs carry keys")
	ok(int(offf["face"]["body"]) == int(offf["body"]) and int(offf["body"]) == 2, "6 offset_face face.body followed the body to 2 (body %s)" % str(offf["body"]))
	ok(int(drf["faces"][0]["body"]) == int(drf["body"]) and int(drf["body"]) == 2, "6 draft faces[0].body followed the body to 2 (body %s)" % str(drf["body"]))
	ok((ri2.get("errors", {}) as Dictionary).is_empty(), "6 0 replay errors after the insert")
	# the cache agrees with a cold replay on the nested part
	var a := Part.replay(m.S.part.duplicate(true), -1, {"inc": true})
	Part.inc_clear()
	var b := Part.replay(m.S.part.duplicate(true), -1, {})
	ok(mesh_hash(a) == mesh_hash(b), "6 nested part: cached replay hash equals cold replay hash")
	print("W03E done, fails=%d" % fails)
	quit(1 if fails > 0 else 0)
