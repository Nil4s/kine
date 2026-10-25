## godot --headless --path . -s tests/schema_test.gd     (GATES T1)
## SCHEMA + VALIDATOR: docs/scene.schema.json's enums are the code's own tables; every scene and pose of Nick's
## validates; 8 files broken on purpose each fail with exactly ONE error at the expected path; and python's jsonschema
## (the reference implementation) finds the same count on every file, at the same place (its path is ours or our
## parent: it reports a bad KEY at the object holding it).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var sc := Validate.schema()
	var D: Dictionary = sc["$defs"]
	ok(D["pose"]["properties"]["joints"]["propertyNames"]["enum"] == Body.ORDER, "the schema's joint names are Body.ORDER (%d)" % Body.ORDER.size())
	ok(D["weapon"]["properties"]["kind"]["enum"] == Body.KINDS.keys(), "the schema's weapon kinds are Body.KINDS %s" % [Body.KINDS.keys()])
	ok(D["card"]["properties"]["ease"]["enum"] == Scene.EASES, "the schema's eases are Scene.EASES")
	# Nick's files
	var files := []
	for dir in ["res://scenes/", "res://poses/", "res://poses/lib/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				files.append(dir + f)
	var bad := files.filter(func(f): return not Validate.file(f).is_empty())
	ok(files.size() > 25 and bad.is_empty(), "%d scene + pose files of Nick's validate (bad: %s)" % [files.size(), bad])
	# broken on purpose: [what, edit, the one path]
	var sd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	var pd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json"))
	var cases := [
		["a hold below 0", func(d): d["cards"][2]["hold"] = -1.0, "$.cards[2].hold", sd],
		["a joint name typo", func(d): d["cards"][0]["pose"]["joints"]["lowerarm_rr"] = d["cards"][0]["pose"]["joints"]["lowerarm_r"], "$.cards[0].pose.joints.lowerarm_rr", sd],
		["an angle as text", func(d): d["cards"][1]["pose"]["joints"]["head"]["bend"] = "90", "$.cards[1].pose.joints.head.bend", sd],
		["a weapon that isn't one", func(d): d["cards"][0]["pose"]["weapon"]["kind"] = "chainsaw", "$.cards[0].pose.weapon.kind", sd],
		["a top-level typo", func(d): d["fsp"] = 30, "$.fsp", sd],
		["an ease that isn't one", func(d): d["cards"][3]["ease"] = "bounce", "$.cards[3].ease", sd],
		["a card with no pose", func(d): d["cards"][4].erase("pose"), "$.cards[4]", sd],
		["a pose offset of 2 numbers", func(d): d["offset"] = [0.0, 0.1], "$.offset", pd],
	]
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/schema_cases")
	var paths := {}
	for i in cases.size():
		var c: Array = cases[i]
		var d: Dictionary = (c[3] as Dictionary).duplicate(true)
		c[1].call(d)
		var p := OS.get_user_data_dir() + "/schema_cases/case_%d.json" % i
		var fh := FileAccess.open(p, FileAccess.WRITE)
		fh.store_string(JSON.stringify(d))
		fh.close()
		paths[p] = c
		var es := Validate.file(p)
		ok(es.size() == 1 and es[0]["path"] == c[2], "%s: %d error at %s: %s" % [c[0], es.size(), es[0]["path"] if es.size() > 0 else "-", es[0]["msg"] if es.size() > 0 else ""])
	# the reference agrees, on Nick's files and on the broken ones
	var all: Array = files.map(func(f): return ProjectSettings.globalize_path(f)) + paths.keys()
	var outp := []
	var code := OS.execute("python", [ProjectSettings.globalize_path("res://tests/py/schema_ref.py"), ProjectSettings.globalize_path(Validate.SCHEMA)] + all, outp, true)
	var ref: Variant = JSON.parse_string(String(outp[0]).strip_edges().get_slice("\n", String(outp[0]).strip_edges().get_slice_count("\n") - 1)) if code == 0 else null
	ok(ref is Dictionary and ref.size() == all.size(), "python jsonschema ran over the same %d files (exit %d)" % [all.size(), code])
	var differ := []
	if ref is Dictionary:
		for f in all:
			var ours := Validate.file(f)
			var theirs: Array = ref[f]
			if ours.size() != theirs.size():
				differ.append("%s: ours %d, jsonschema %d %s" % [f.get_file(), ours.size(), theirs.size(), theirs])
			elif ours.size() == 1 and not (ours[0]["path"] == theirs[0][0] or ours[0]["path"].begins_with(theirs[0][0] + ".") or ours[0]["path"].begins_with(theirs[0][0] + "[")):
				differ.append("%s: ours at %s, jsonschema at %s" % [f.get_file(), ours[0]["path"], theirs[0][0]])
	ok(ref is Dictionary and differ.is_empty(), "jsonschema agrees on every file: the same count, the same place %s" % [differ])
	for p in paths:
		DirAccess.remove_absolute(p)
	print("SCHEMA TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
