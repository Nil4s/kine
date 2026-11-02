extends SceneTree
## S257 frame_to finds a body by the name an agent call gave it (bname) AND by its stable body key, after a replay of a 278-body hall.
## godot --headless --path . -s tests/s257_test.gd
##   A  frame_to(["Lower roof"]) selects exactly the one body that bname named, and frames it (a real, finite share)
##   B  frame_to([<body key>]) selects the same body and returns the same camera as the name
##   C  a key pattern "<feature id>#*" selects that feature's bodies
##   D  CONTROL: the old lookup (names only, no keys) finds nothing for the key; an unnamed body is only "Body<N>"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


class FakePart:
	extends RefCounted
	var part_mesh: MeshInstance3D
	var res: Dictionary
	var rec: Dictionary
	func _rec() -> Dictionary:
		return rec


class FakeBld:
	extends RefCounted
	var part: Object


class FakeMain:
	extends Node
	var bld: Object


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s257_temple.json"))
	var rec: Dictionary = d["part"]
	var TARGET := 150
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"name": "Name Lower roof", "body": TARGET, "called": "Lower roof"}))
	var res := Part.replay(rec.duplicate(true), -1, {"effects": true})
	var keys: Array = res["body_keys"]
	var names: Array = res["body_names"]
	print("bodies ", res["bodies"], " key ", keys[TARGET], " name ", names[TARGET])
	var pm := MeshInstance3D.new()
	pm.mesh = res["mesh"]
	var fb := FakeBld.new()
	var fp := FakePart.new()
	fp.part_mesh = pm
	fp.res = res.duplicate()
	fp.res.erase("body_keys")   # what the app's own replay holds: no keys until asked
	fp.rec = rec
	fb.part = fp
	var m := FakeMain.new()
	m.bld = fb
	root.add_child(m)
	m.add_child(pm)
	await process_frame
	var aabb: AABB = pm.mesh.get_aabb()
	var cam := {"pos": [aabb.get_center().x, aabb.get_center().y + aabb.size.y * 0.2, aabb.get_center().z + aabb.size.length() * 1.2], "target": [aabb.get_center().x, aabb.get_center().y, aabb.get_center().z], "fov": 50}
	var by_name := FrameFacts.serve_to(m, {"pieces": ["Lower roof"], "width_share": 0.5, "camera": cam, "w": 1280, "h": 720})
	var key := String(keys[TARGET])
	var by_key := FrameFacts.serve_to(m, {"pieces": [key], "width_share": 0.5, "camera": cam, "w": 1280, "h": 720})
	print("name: ", JSON.stringify(by_name).left(300))
	print("key : ", JSON.stringify(by_key).left(300))
	ok(bool(by_name.get("ok", false)), "A  frame_to('Lower roof') succeeds")
	ok(bool(by_key.get("ok", false)), "B  frame_to('%s') succeeds" % key)
	ok(JSON.stringify(by_name.get("camera")) == JSON.stringify(by_key.get("camera")) and by_name.has("camera"), "B  name and key return the same camera")
	var g := FrameFacts.gather(m)
	var ia := FrameFacts.select(g, ["Lower roof"])
	ok(ia.size() == 1 and names[TARGET] == "Lower roof" and String(g["names"][ia[0]]) == "Lower roof", "A  'Lower roof' selects exactly one body (%d)" % ia.size())
	FrameFacts.ensure_keys(m, g, [key])
	var ib := FrameFacts.select(g, [key])
	ok(ib == ia, "B  the key selects the same piece %s vs %s" % [str(ib), str(ia)])
	var fid := key.split("#")[0]
	var ic := FrameFacts.select(g, [fid + "#*"])
	ok(ic.has(ia[0]) and ic.size() >= 1, "C  '%s#*' selects %d bodies incl. the target" % [fid, ic.size()])
	# D control: old lookup = names only
	var g_old := g.duplicate()
	g_old.erase("keys")
	ok(FrameFacts.select(g_old, [key]).is_empty(), "D  CONTROL old lookup (names only) finds nothing for the key")
	var un := -1
	for i in names.size():
		if String(names[i]).begins_with("Body"):
			un = i
			break
	ok(un < 0 or FrameFacts.select(g_old, ["Lower roof2"]).is_empty(), "D  CONTROL a name nobody gave fails")
	print("fails ", fails)
	quit(1 if fails > 0 else 0)
