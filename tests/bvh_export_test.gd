## godot --headless --path . -s tests/bvh_export_test.gd     (GATES OO2)
## THE .BVH ROUND TRIP. Every scene in scenes/ written by BvhExport, then RE-PARSED here by a reader written from the
## format, not from the writer: HIERARCHY (joints, OFFSETs, each joint's CHANNELS in the order listed, End Sites), MOTION
## (Frames, Frame Time, one row per frame), forward kinematics the BVH way: a joint's world = its parent's world *
## translate(OFFSET + its position channels) * the rotation channels multiplied in the order they are listed.
## (1) every joint within 1 cm of Poser's on every frame; (1w) every weapon's knob (its joint) and tip (its End Site)
## within 1 cm; (2) Frames and Frame Time match the scene; (3) the app's "Export animation (.bvh)" writes one.
extends SceneTree

var fails := 0
const DIR := "res://exports/zz_bvh"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the file -> {"joints": [{name, parent, offset, channels, end}], "frames": int, "dt": float, "rows": [PackedFloat64Array]}
static func parse(txt: String) -> Dictionary:
	var tok := PackedStringArray()
	for w in txt.replace("\t", " ").replace("\r", " ").replace("\n", " ").split(" ", false):
		tok.append(w)
	var joints := []
	var stack := []   # indices of open joints (-1 for an End Site)
	var i := 0
	while i < tok.size() and tok[i] != "MOTION":
		var t := tok[i]
		if t == "ROOT" or t == "JOINT":
			joints.append({"name": tok[i + 1], "parent": stack.back() if not stack.is_empty() else -1, "offset": Vector3.ZERO, "channels": [], "end": null})
			i += 2
			if tok[i] != "{":
				return {}
			stack.append(joints.size() - 1)
		elif t == "End":   # End Site { OFFSET x y z }
			var o := Vector3(tok[i + 4].to_float(), tok[i + 5].to_float(), tok[i + 6].to_float())
			joints[stack.back()]["end"] = o
			i += 8
			continue
		elif t == "OFFSET":
			joints[stack.back()]["offset"] = Vector3(tok[i + 1].to_float(), tok[i + 2].to_float(), tok[i + 3].to_float())
			i += 3
		elif t == "CHANNELS":
			var n := tok[i + 1].to_int()
			joints[stack.back()]["channels"] = Array(tok.slice(i + 2, i + 2 + n))
			i += 1 + n
		elif t == "}":
			stack.pop_back()
		i += 1
	# MOTION Frames: n Frame Time: dt
	var frames := tok[i + 2].to_int()
	var dt := tok[i + 5].to_float()
	i += 6
	var per := 0
	for j in joints:
		per += (j["channels"] as Array).size()
	var rows := []
	for f in frames:
		var r := PackedFloat64Array()
		for k in per:
			r.append(tok[i + k].to_float())
		rows.append(r)
		i += per
	return {"joints": joints, "frames": frames, "dt": dt, "rows": rows}


## one frame -> {name: [world position, world rotation]} and {name: End Site world position}
static func pose(doc: Dictionary, row: PackedFloat64Array) -> Array:
	var P := []
	var R := []
	var at := {}
	var ends := {}
	var k := 0
	for idx in (doc["joints"] as Array).size():
		var j: Dictionary = doc["joints"][idx]
		var t: Vector3 = j["offset"]
		var q := Quaternion.IDENTITY
		for c in j["channels"]:
			var v := row[k]
			k += 1
			match c:
				"Xposition": t.x += v
				"Yposition": t.y += v
				"Zposition": t.z += v
				"Xrotation": q = q * Quaternion(Vector3.RIGHT, deg_to_rad(v))
				"Yrotation": q = q * Quaternion(Vector3.UP, deg_to_rad(v))
				"Zrotation": q = q * Quaternion(Vector3.BACK, deg_to_rad(v))
		var p: int = j["parent"]
		if p < 0:
			P.append(t)
			R.append(q)
		else:
			P.append((P[p] as Vector3) + (R[p] as Quaternion) * t)
			R.append((R[p] as Quaternion) * q)
		at[j["name"]] = P[idx]
		if j["end"] != null:
			ends[j["name"]] = (P[idx] as Vector3) + (R[idx] as Quaternion) * (j["end"] as Vector3)
	return [at, ends]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var names := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json"):
			names.append(f.get_basename())
	names.sort()
	var worst := 0.0
	var at_w := ""
	var worst_wep := 0.0
	var at_wep := ""
	var frames := 0
	var wep_frames := 0
	var head_bad := []
	var missing := []
	for sn in names:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sn)))
		var path := "%s/%s.bvh" % [DIR, sn]
		var r := BvhExport.write(S, B, path)
		if r[0] != OK:
			ok(false, "%s: not written (%s)" % [sn, error_string(r[0])])
			continue
		var doc := parse(FileAccess.get_file_as_string(path))
		if doc.is_empty():
			ok(false, "%s: the file does not parse" % sn)
			continue
		var n := int(ceil(S.length() * S.fps - 1e-6)) + 1
		if doc["frames"] != n or absf(doc["dt"] - 1.0 / S.fps) > 1e-6:
			head_bad.append("%s %d frames / %.6f s vs %d / %.6f" % [sn, doc["frames"], doc["dt"], n, 1.0 / S.fps])
		for i in mini(n, doc["frames"]):
			S.apply(B, minf(i / float(S.fps), S.length()))
			var got: Array = pose(doc, doc["rows"][i])
			frames += 1
			for j in Body.ORDER:
				if not got[0].has(j):
					if not j in missing:
						missing.append(j)
					continue
				var d: float = (got[0][j] as Vector3).distance_to(B.P[j])
				if d > worst:
					worst = d
					at_w = "%s frame %d %s" % [sn, i, j]
			for w in [["weapon", B.wep_on], ["weapon2", B.wep2_on]]:
				if not w[1]:
					continue
				if not got[0].has(w[0]):
					worst_wep = 999.0
					at_wep = "%s: no %s joint" % [sn, w[0]]
					continue
				wep_frames += 1
				var knob: Vector3 = B.wep_point(0.0) if w[0] == "weapon" else B.wep2_point(0.0)
				var tip: Vector3 = B.wep_point(B.wep_len) if w[0] == "weapon" else B.wep2_point(B.wep2_len())
				var d := maxf((got[0][w[0]] as Vector3).distance_to(knob), (got[1][w[0]] as Vector3).distance_to(tip))
				if d > worst_wep:
					worst_wep = d
					at_wep = "%s frame %d %s" % [sn, i, w[0]]
	ok(frames > 500 and missing.is_empty() and worst <= 0.01, "1 %d scenes, %d frames re-parsed: every joint within %.4f m of Poser (worst %s; joints missing: %s)" % [names.size(), frames, worst, at_w, missing])
	ok(wep_frames > 500 and worst_wep <= 0.01, "1w %d weapon-frames: knob and tip within %.4f m (worst %s)" % [wep_frames, worst_wep, at_wep])
	ok(head_bad.is_empty(), "2 every file's Frames and Frame Time = its scene's (off: %s)" % [head_bad])
	# (3) the app's own command
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var row := {}
	for c in m._commands():
		if c["name"] == "Export animation (.bvh)":
			row = c
	m._load_scene("res://scenes/bo_spin.json")
	var out: String = m._export_bvh(DIR)
	var doc := parse(FileAccess.get_file_as_string(out)) if out != "" else {}
	var has_w := false
	if not doc.is_empty():
		for j in doc["joints"]:
			has_w = has_w or j["name"] == "weapon"
	ok(not row.is_empty() and (row["run"] as Callable).get_method() == "_export_bvh" and not doc.is_empty() and doc["frames"] == int(ceil(m.S.length() * m.S.fps - 1e-6)) + 1 and has_w,
		"3 the command 'Export animation (.bvh)' (bound to %s) wrote %s: %s frames, a weapon joint %s" % [row["run"].get_method() if not row.is_empty() else "-", out.get_file(), doc.get("frames", "-"), has_w])
	m.queue_free()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("BVH EXPORT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
