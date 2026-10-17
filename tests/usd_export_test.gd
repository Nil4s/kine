## godot --headless --path . -s tests/usd_export_test.gd     (GATES XX9)
## THE .USDA ROUND TRIP. combo3 and walk_bat written by UsdExport, then READ BACK by a small USDA reader written here
## from the format (header metadata, joints, bindTransforms, restTransforms, time samples), not by the writer's code.
## (1) per frame per joint, the file's rotation = the scene's sampled rotation within 1e-4 degrees; (2) translations
## = the scene's offsets (pelvis: world position) within 1e-5 m; (3) header: upAxis "Y", metersPerUnit 1, fps and
## frame range = the scene's; (4) the hierarchy: joint paths parents first, parent paths match Body.parent, bind =
## world rest position, rest = offset to parent; (5) the app's command writes one. pxr / usdcat: checked, see below.
extends SceneTree

var fails := 0
const DIR := "res://exports/zz_usd"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## "( (..), (..) )" or "(a, b, c)" -> flat floats
static func nums(s: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for w in s.replace("(", " ").replace(")", " ").replace("[", " ").replace("]", " ").replace(",", " ").split(" ", false):
		out.append(w.to_float())
	return out


## the file -> {meta: {key: value}, joints, bind: [Vector3], rest: [Vector3], anim_joints, t: {frame: floats}, r: {frame: floats}}
static func parse(txt: String) -> Dictionary:
	var d := {"meta": {}, "joints": [], "bind": [], "rest": [], "anim_joints": [], "t": {}, "r": {}, "scales": 0}
	var lines := txt.split("\n")
	if lines[0] != "#usda 1.0":
		return {}
	var in_head := true
	var cur := ""   # the attribute whose time samples are open
	var in_anim := false
	for ln in lines.slice(1):
		var s := ln.strip_edges()
		if in_head:
			if s == ")":
				in_head = false
			elif "=" in s:
				d["meta"][s.get_slice("=", 0).strip_edges()] = s.get_slice("=", 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
			continue
		if s.begins_with("def SkelAnimation"):
			in_anim = true
		if s.begins_with("uniform token[] joints"):
			var toks := []
			for w in s.get_slice("=", 1).replace("[", "").replace("]", "").split(",", false):
				toks.append(w.strip_edges().trim_prefix("\"").trim_suffix("\""))
			d["anim_joints" if in_anim else "joints"] = toks
		elif s.begins_with("uniform matrix4d[] bindTransforms") or s.begins_with("uniform matrix4d[] restTransforms"):
			var f := nums(s.get_slice("=", 1))
			var key := "bind" if "bindTransforms" in s else "rest"
			for k in f.size() / 16:
				d[key].append(Vector3(f[k * 16 + 12], f[k * 16 + 13], f[k * 16 + 14]))
		elif s.begins_with("float3[] translations.timeSamples"):
			cur = "t"
		elif s.begins_with("quatf[] rotations.timeSamples"):
			cur = "r"
		elif s.begins_with("half3[] scales"):
			d["scales"] = nums(s.get_slice("=", 1)).size() / 3
		elif s == "}":
			cur = ""
		elif cur != "" and ":" in s:
			d[cur][s.get_slice(":", 0).to_int()] = nums(s.get_slice(":", 1))
	return d


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var N := Body.ORDER.size()
	for sn in ["combo3", "walk_bat"]:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sn)))
		var path := "%s/%s.usda" % [DIR, sn]
		var r := UsdExport.write(S, B, path)
		ok(r[0] == OK, "%s written (%s)" % [sn, error_string(r[0])])
		var doc := parse(FileAccess.get_file_as_string(path))
		ok(not doc.is_empty(), "%s parses" % sn)
		var n := int(ceil(S.length() * S.fps - 1e-6)) + 1
		var worst_r := 0.0
		var worst_t := 0.0
		var at_r := ""
		var q: Dictionary = doc["r"]
		var t: Dictionary = doc["t"]
		for i in n:
			if not q.has(i) or not t.has(i) or q[i].size() != N * 4 or t[i].size() != N * 3:
				worst_r = 999.0
				at_r = "frame %d missing or short" % i
				break
			S.apply(B, minf(i / float(S.fps), S.length()))
			B.fk()
			for k in N:
				var j: String = Body.ORDER[k]
				var want := B.compose(j, B.ang[j]).normalized()
				var got := Quaternion(q[i][k * 4 + 1], q[i][k * 4 + 2], q[i][k * 4 + 3], q[i][k * 4]).normalized()   # file: w x y z
				var e := BvhExport.rt_err(want, got)
				if e > worst_r:
					worst_r = e
					at_r = "frame %d %s" % [i, j]
				var off: Vector3 = B.P[j] if B.parent[j] == "" else (B.p0[j] as Vector3) - (B.p0[B.parent[j]] as Vector3)
				worst_t = maxf(worst_t, off.distance_to(Vector3(t[i][k * 3], t[i][k * 3 + 1], t[i][k * 3 + 2])))
		ok(worst_r <= 1e-4, "1 %s: %d frames x %d joints, rotation worst %.7f deg (bar 1e-4; at %s)" % [sn, n, N, worst_r, at_r])
		ok(worst_t <= 1e-5, "2 %s: translations worst %.7f m (bar 1e-5)" % [sn, worst_t])
		var m: Dictionary = doc["meta"]
		ok(m.get("upAxis") == "Y" and absf(float(m.get("metersPerUnit", "0")) - 1.0) < 1e-12 and absf(float(m.get("timeCodesPerSecond", "0")) - S.fps) < 1e-9 and int(m.get("endTimeCode", "-1")) == n - 1 and int(m.get("startTimeCode", "-1")) == 0 and q.size() == n,
			"3 %s: upAxis %s, metersPerUnit %s, timeCodesPerSecond %s (scene %d), end %s (scene %d), %d samples" % [sn, m.get("upAxis"), m.get("metersPerUnit"), m.get("timeCodesPerSecond"), S.fps, m.get("endTimeCode"), n - 1, q.size()])
		var J: Array = doc["joints"]
		var bad := []
		var worst_b := 0.0
		if J.size() != N or doc["bind"].size() != N or doc["rest"].size() != N or doc["anim_joints"] != J or doc["scales"] != N:
			bad.append("sizes %d/%d/%d/%d scales %d" % [J.size(), doc["bind"].size(), doc["rest"].size(), doc["anim_joints"].size(), doc["scales"]])
		else:
			var seen := {}
			for k in N:
				var j: String = Body.ORDER[k]
				var pj: String = B.parent[j]
				var want_path: String = j if pj == "" else "%s/%s" % [J[Body.ORDER.find(pj)], j]
				if J[k] != want_path or (pj != "" and not seen.has(J[Body.ORDER.find(pj)])):
					bad.append(j)
				seen[J[k]] = true
				worst_b = maxf(worst_b, (doc["bind"][k] as Vector3).distance_to(B.p0[j]))
				var ro: Vector3 = B.p0[j] if pj == "" else (B.p0[j] as Vector3) - (B.p0[pj] as Vector3)
				worst_b = maxf(worst_b, (doc["rest"][k] as Vector3).distance_to(ro))
		ok(bad.is_empty() and worst_b <= 1e-5, "4 %s: %d joint paths (parents first, = Body.parent), bind/rest worst %.7f m (bad: %s)" % [sn, J.size(), worst_b, bad])
	# (5) the app's command
	var app: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	await process_frame
	var row := {}
	for c in app._commands():
		if c["name"] == "Export animation (.usda)":
			row = c
	app._load_scene("res://scenes/combo3.json")
	var out: String = app._export_usd(DIR)
	var doc := parse(FileAccess.get_file_as_string(out)) if out != "" else {}
	ok(not row.is_empty() and (row["run"] as Callable).get_method() == "_export_usd" and not doc.is_empty() and doc["r"].size() == int(ceil(app.S.length() * app.S.fps - 1e-6)) + 1,
		"5 the command 'Export animation (.usda)' wrote %s: %d samples" % [out.get_file(), doc.get("r", {}).size()])
	app.queue_free()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("pxr / usdcat: NOT INSTALLED here (python -c 'import pxr' fails; where usdcat finds nothing), so no external validation")
	print("USD EXPORT TEST %s %d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
