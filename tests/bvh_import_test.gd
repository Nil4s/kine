## godot --headless --path . -s tests/bvh_import_test.gd     (GATES WW7)
## BVH IMPORT ROUND TRIP. A repo scene -> BvhExport.write -> BvhImport.load_file -> to_scene -> sampled at every BVH frame time:
## every joint's rotation within 0.01 deg of the original's (rotation difference by BvhExport.rt_err, which compares the
## rotations compose() makes, so a twist of +180 vs -180 is not a false miss; the bend/side/twist numbers are also
## compared where they are not at a +-180 wrap), the hips' offset and every world joint position within 0.1 mm.
## Also: a malformed file is refused with a reason, an unknown joint is listed, a sparse import, old scenes unchanged.
extends SceneTree

var fails := 0
const DIR := "user://zz_bvh_import"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func roundtrip(sn: String, B: Body) -> Dictionary:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sn)))
	var path := "%s/%s.bvh" % [DIR, sn]
	var w := BvhExport.write(S, B, path)
	var bv := BvhImport.load_file(path)
	if w[0] != OK or not bv["ok"]:
		return {"err": "write %s / parse: %s" % [w[0], bv.get("why", "")]}
	var r := BvhImport.to_scene(bv, B)
	if not r["ok"]:
		return {"err": r["why"]}
	var S2: Scene = r["scene"]
	var n: int = bv["frames"].size()
	var worst_deg := 0.0
	var worst_ang := 0.0
	var worst_off := 0.0
	var worst_pos := 0.0
	var at := ""
	for i in n:
		var t := minf(i / float(S.fps), S.length())
		S.apply(B, t)
		var q0 := {}
		var a0 := {}
		var P0 := {}
		for j in Body.ORDER:
			q0[j] = B.compose(j, B.ang[j])
			a0[j] = B.ang[j]
			P0[j] = B.P[j]
		var off0: Vector3 = B.offset
		S2.apply(B, i * float(bv["dt"]))
		worst_off = maxf(worst_off, (B.offset - off0).length())
		for j in Body.ORDER:
			var e := BvhExport.rt_err(q0[j], B.compose(j, B.ang[j]))
			if e > worst_deg:
				worst_deg = e
				at = "%s frame %d %s" % [sn, i, j]
			var d: Vector3 = (a0[j] as Vector3 - B.ang[j]).abs()
			if absf(a0[j].z) < 179.0:   # not at the twist wrap
				worst_ang = maxf(worst_ang, maxf(d.x, maxf(d.y, d.z)))
			worst_pos = maxf(worst_pos, (P0[j] as Vector3).distance_to(B.P[j]))
	return {"n": n, "deg": worst_deg, "ang": worst_ang, "off": worst_off, "pos": worst_pos, "at": at, "r": r, "S": S2, "S0": S}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for sn in ["combo3", "walk_bat"]:
		var r := roundtrip(sn, B)
		if r.has("err"):
			ok(false, "%s: %s" % [sn, r["err"]])
			continue
		ok(r["deg"] < 0.01, "1 %s %d frames: worst rotation difference %.5f deg (bar < 0.01) at %s" % [sn, r["n"], r["deg"], r["at"]])
		ok(r["ang"] < 0.01, "1b %s worst bend/side/twist number difference %.5f deg (bar < 0.01)" % [sn, r["ang"]])
		ok(r["off"] < 0.0001, "2 %s hips offset difference %.7f m (bar < 0.0001)" % [sn, r["off"]])
		ok(r["pos"] < 0.0001, "3 %s worst world joint position difference %.7f m (bar < 0.0001)" % [sn, r["pos"]])
		ok((r["r"]["cards"] as int) == r["n"], "4 %s one card per frame: %d cards for %d frames; %s" % [sn, r["r"]["cards"], r["n"], r["r"]["text"]])
		if sn == "combo3":
			ok("weapon" in r["r"]["not_mapped"], "5 the exporter's weapon joint is listed, not silently dropped: %s" % [r["r"]["not_mapped"]])
	# sparse: cards about every 0.1 s
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	BvhExport.write(S, B, DIR + "/sp.bvh")
	var bv := BvhImport.load_file(DIR + "/sp.bvh")
	var ev := BvhImport.every_for(float(bv["fps"]))
	var sp := BvhImport.to_scene(bv, B, ev)
	ok(sp["ok"] and sp["cards"] < bv["frames"].size() and ev == 3 and sp["scene"].length() > 0.0 and absf(sp["scene"].length() - (bv["frames"].size() - 1) * bv["dt"]) < 0.01,
		"6 sparse every %d (bar 3 at 30 fps): %d cards for %d frames, length %.3f vs %.3f s" % [ev, sp["cards"], bv["frames"].size(), sp["scene"].length(), (bv["frames"].size() - 1) * bv["dt"]])
	# any channel order, centimetres: Xrotation Yrotation Zrotation, scale 0.01
	var txt := "HIERARCHY\nROOT pelvis\n{\n OFFSET 0 0 0\n CHANNELS 6 Zposition Yposition Xposition Yrotation Xrotation Zrotation\n JOINT mystery\n {\n  OFFSET 0 10 0\n  CHANNELS 3 Xrotation Yrotation Zrotation\n  End Site\n  {\n   OFFSET 0 5 0\n  }\n }\n}\nMOTION\nFrames: 2\nFrame Time: 0.5\n0 100 0 0 0 0 0 0 0\n0 100 0 10 0 0 0 0 0\n"
	var b2 := BvhImport.parse(txt)
	var r2 := BvhImport.to_scene(b2, B, 1, 0.01)
	var mp: Vector3 = Vector3.ZERO
	if r2["ok"]:
		r2["scene"].apply(B, 0.0)
		mp = B.offset
	ok(b2["ok"] and r2["ok"] and r2["not_mapped"] == ["mystery"] and absf(mp.y + (B.p0["pelvis"] as Vector3).y - 1.0) < 1e-6 and r2["scene"].fps == 2,
		"7 foreign order + cm: parsed, hips y %.4f m (bar 1.0), 'not mapped: mystery' in: %s" % [mp.y + (B.p0["pelvis"] as Vector3).y, r2.get("text", r2.get("why", ""))])
	# malformed files: refused with a reason, no crash
	var good := FileAccess.get_file_as_string(DIR + "/sp.bvh")
	var rows := good.split("\n")
	var bad := {
		"truncated MOTION": "\n".join(rows.slice(0, rows.size() - 6)) + "\n" + rows[rows.size() - 6].left(40),
		"wrong channel count": good.replace("CHANNELS 3 Zrotation", "CHANNELS 4 Zrotation").replace("CHANNELS 6 Xposition", "CHANNELS 5 Xposition"),
		"no MOTION": good.get_slice("MOTION", 0),
		"not BVH": "hello world",
		"empty": "",
		"letters in a frame": good.replace("Frame Time: ", "Frame Time: ").replace(rows[rows.size() - 3].substr(0, 8), "abcdefgh"),
		"zero frame time": good.replace("Frame Time: 0.033333333", "Frame Time: 0"),
		"unclosed": good.replace("\n}\nMOTION", "\nMOTION"),
	}
	for k in bad:
		var br := BvhImport.parse(bad[k])
		var why := String(br.get("why", ""))
		ok(not br["ok"] and why.length() > 10, "8 refused: %s -> \"%s\"" % [k, why.left(110)])
	ok(not BvhImport.load_file("user://zz_nope.bvh")["ok"], "9 a missing file is refused")
	var nr := BvhImport.to_scene(BvhImport.parse(txt.replace("ROOT pelvis", "ROOT hips")), B)
	ok(not nr["ok"] and "pelvis" in nr["why"], "10 a skeleton with no pelvis is refused: %s" % nr.get("why", "").left(80))
	# the app's drop: a .bvh becomes a scene in scenes/_wip (removed again here)
	BvhExport.write(S, B, DIR + "/zz_drop.bvh")
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._on_drop(PackedStringArray([ProjectSettings.globalize_path(DIR + "/zz_drop.bvh")]))
	var wp := "res://scenes/_wip/zz_drop.json"
	ok(FileAccess.file_exists(wp) and m.S.cards.size() == bv["frames"].size() and m.scene_path == wp, "11 dropping a .bvh opens it as scenes/_wip/zz_drop.json: %d cards (bar %d)" % [m.S.cards.size(), bv["frames"].size()])
	m._on_drop(PackedStringArray([ProjectSettings.globalize_path(DIR + "/sp.bvh").replace("sp.bvh", "zz_nope.bvh")]))
	ok(m.scene_path == wp, "12 dropping a missing .bvh changes nothing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(wp))
	m.queue_free()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("BVH IMPORT TEST %s %d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
