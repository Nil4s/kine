## godot --headless --path . -s tests/usd_layers_test.gd     (ROADMAP 79, GATES USDL: the layered USD)
## combo3 with two layers ("fix": add on spine_01 and upperarm_r; "lean": over on neck_01 and head, keyed weight 0 -> 1 -> 0.3)
## and a shot camera, written by UsdExport.write_layers, then READ BACK file by file with the usd_export_test reader.
## The composed stage is the USD rule the files rely on: the strongest sublayer's samples are the pose (every layer file holds the
## WHOLE pose at every frame, so the top one plays alone).
## (1) the root lists its sublayers strongest first: props, points, the layers top first, base, skeleton; every file parses;
## (2) base + the top layer at weight 1 = the app's final pose: 3 joints at 3 times within 0.01 deg (bar), and every joint on every
##     frame within 0.01 deg (bar);
## (3) muting the top layer: the composed pose = the app's pose with only the lower layer played (the same two bars);
## (4) muting every layer: the composed pose = the app's pose with no layer (the same two bars);
## (5) the point cache: Kine/JointCache points = the joints' world positions (B.P) within 1 mm (bar), every joint and frame;
## (6) the camera: Camera "Shot" has one sample per frame, its origin = the camera position and its focal length = ShotCam's;
## (7) the app's command writes the same set and returns its root; the export dialog's maya and raw targets offer the layers
##     and maya's needs say Alembic is not written.
## LIMIT, printed not gated: a LOWER layer muted while the one above it is live changes nothing the composed stage shows.
extends SceneTree

var fails := 0
const DIR := "user://zz_usd_layers"
const NM := "usdl_test"
const TOL_DEG := 0.01
const TOL_M := 0.001
const UT := preload("res://tests/usd_export_test.gd")


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the composed rotation of joint k at frame i: the strongest file (list order) that has rotation samples
static func comp(files: Array, i: int, k: int) -> Quaternion:
	for d in files:
		var r: Dictionary = d["r"]
		if not r.is_empty():
			var a: PackedFloat64Array = r[i]
			return Quaternion(a[k * 4 + 1], a[k * 4 + 2], a[k * 4 + 3], a[k * 4]).normalized()   # file: w x y z
	return Quaternion.IDENTITY


## the app's pose of scene S at frame i: rotation per joint (Body.ORDER) and the joints' world positions
static func pose(S: Scene, B: Body, i: int, fps: float) -> Array:
	S.apply(B, minf(i / fps, S.length()))
	B.fk()
	var q := []
	var p := []
	for j in Body.ORDER:
		q.append(B.compose(j, B.ang[j]).normalized())
		p.append(B.P[j])
	return [q, p]


static func read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


static func rm_tree(d: String) -> void:
	var g := ProjectSettings.globalize_path(d)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g + "/" + f)
		DirAccess.remove_absolute(g)


func _init() -> void:
	rm_tree(DIR)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var N := Body.ORDER.size()
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	S.layers = [
		{"name": "fix", "mode": "add", "w": 1.0, "v": {"spine_01": Vector3(12, 0, 0), "upperarm_r": Vector3(0, 0, 25)}},
		{"name": "lean", "mode": "over", "w": 1.0, "wk": [[0.0, 0.0], [0.6, 1.0], [1.2, 0.3]], "v": {"neck_01": Vector3(-20, 0, 0), "head": Vector3(0, 15, 0)}},
	]
	S.camera = [{"t": 0.0, "pos": Vector3(0.6, 1.4, 3.0), "aim": Vector3(0, 1.0, 0), "f": 50.0},
		{"t": 1.0, "pos": Vector3(1.2, 1.5, 2.5), "aim": Vector3(0, 1.1, 0), "f": 35.0}]
	var fps := float(S.fps)
	var n := int(ceil(S.length() * fps - 1e-6)) + 1
	var frames := [0, n / 2, n - 1]
	var three := ["spine_01", "upperarm_r", "head"]
	var r := UsdExport.write_layers(S, B, DIR, NM)
	ok(r[0] == OK, "write_layers wrote the set (%s)" % error_string(r[0]))
	if r[0] != OK:
		_done()
		return
	var info: Dictionary = r[1]
	var root_path: String = info["root"]
	var folder := root_path.get_base_dir()
	var sub: Array = info["sublayers"]
	# (1) the root's sublayers, in the order it lists them
	var root_txt := read(root_path)
	var listed := []
	for ln in root_txt.split("\n"):
		var s := ln.strip_edges()
		if s.begins_with("@./"):
			listed.append(s.trim_prefix("@./").trim_suffix(",").trim_suffix("@"))
	var want := [NM + "_props.usda", NM + "_points.usda", NM + "_layer_01_lean.usda", NM + "_layer_00_fix.usda", NM + "_base.usda", NM + "_skeleton.usda"]
	ok(listed == want and listed == sub, "1 root lists %d sublayers, strongest first: %s" % [listed.size(), listed])
	var docs := {}
	var all_parse := true
	for f in want:
		var d: Dictionary = UT.parse(read(folder + "/" + f))
		docs[f] = d
		if d.is_empty():
			all_parse = false
	ok(all_parse and (docs[NM + "_base.usda"]["r"] as Dictionary).size() == n and (docs[NM + "_layer_01_lean.usda"]["r"] as Dictionary).size() == n
		and (docs[NM + "_skeleton.usda"]["joints"] as Array).size() == N,
		"1b every file parses with the usd_export_test reader; base and both layers have %d samples; skeleton has %d joints" % [n, N])
	var meta: Dictionary = UT.parse(root_txt)["meta"]
	ok(meta.get("upAxis") == "Y" and int(meta.get("endTimeCode", "-1")) == n - 1 and absf(float(meta.get("timeCodesPerSecond", "0")) - fps) < 1e-9,
		"1c root header: upAxis %s, timeCodesPerSecond %s, endTimeCode %s (scene %d frames)" % [meta.get("upAxis"), meta.get("timeCodesPerSecond"), meta.get("endTimeCode"), n])
	var top := [docs[NM + "_layer_01_lean.usda"], docs[NM + "_layer_00_fix.usda"], docs[NM + "_base.usda"], docs[NM + "_skeleton.usda"]]
	var lower := [docs[NM + "_layer_00_fix.usda"], docs[NM + "_base.usda"], docs[NM + "_skeleton.usda"]]
	var bare := [docs[NM + "_base.usda"], docs[NM + "_skeleton.usda"]]
	# app references: the final pose (all layers), only the lower layer, no layer
	var S_lower := S.clone()
	S_lower.layers = [S.layers[0].duplicate(true)]
	var S_none := S.clone()
	S_none.layers = []
	S_none.layer = {}
	# (2)(3)(4) the composed stage against the app, at 3 frames x 3 joints (bar) and on every joint and frame (bar)
	var cases := [["2 base + top layer", top, S], ["3 top layer muted", lower, S_lower], ["4 every layer muted", bare, S_none]]
	for c in cases:
		var files: Array = c[1]
		var ref: Scene = c[2]
		var worst3 := 0.0
		var at3 := ""
		var worst_all := 0.0
		var at_all := ""
		for i in n:
			var P := pose(ref, B, i, fps)
			for k in N:
				var e := BvhExport.rt_err(P[0][k], comp(files, i, k))
				if e > worst_all:
					worst_all = e
					at_all = "frame %d %s" % [i, Body.ORDER[k]]
				if i in frames and Body.ORDER[k] in three and e > worst3:
					worst3 = e
					at3 = "frame %d %s" % [i, Body.ORDER[k]]
		ok(worst3 <= TOL_DEG, "%s: composed = app pose, 3 joints %s at frames %s: worst %.6f deg (bar %.2f; at %s)" % [c[0], three, frames, worst3, TOL_DEG, at3])
		ok(worst_all <= TOL_DEG, "%s: every joint, every frame (%d): worst %.6f deg (bar %.2f; at %s)" % [c[0], n, worst_all, TOL_DEG, at_all])
	# the known limit (not gated): with the lean layer live, muting the fix leaves the composed stage where it was. The app's
	# pose with the fix muted (the lean layer alone) is what the DCC should show, and it is not what the stage shows.
	var S_lean := S.clone()
	S_lean.layers = [S.layers[1].duplicate(true)]
	var lim_err := 0.0
	for i in frames:
		var Pl := pose(S_lean, B, i, fps)
		for k in N:
			lim_err = maxf(lim_err, BvhExport.rt_err(Pl[0][k], comp(top, i, k)))
	print("note LIMIT (not gated): muting the fix (layer 0) under the live lean layer changes nothing in the stage; the app's pose with the fix muted differs from the stage by %.3f deg (worst, at the 3 frames, all joints)" % lim_err)
	# (5) the point cache, every joint and frame, within 1 mm
	var pts_txt := read(folder + "/" + NM + "_points.usda")
	var pts := {}
	var in_pts := false
	for ln in pts_txt.split("\n"):
		var s := ln.strip_edges()
		if s.begins_with("point3f[] points.timeSamples"):
			in_pts = true
		elif in_pts and s == "}":
			in_pts = false
		elif in_pts and ":" in s:
			pts[s.get_slice(":", 0).to_int()] = UT.nums(s.get_slice(":", 1))
	var worst_p := 0.0
	var at_p := ""
	var pts_ok := pts.size() == n
	for i in n:
		var P := pose(S, B, i, fps)
		if not pts.has(i) or (pts[i] as PackedFloat64Array).size() != N * 3:
			pts_ok = false
			break
		for k in N:
			var v: PackedFloat64Array = pts[i]
			var got := Vector3(v[k * 3], v[k * 3 + 1], v[k * 3 + 2])
			var e := got.distance_to(P[1][k])
			if e > worst_p:
				worst_p = e
				at_p = "frame %d %s" % [i, Body.ORDER[k]]
	ok(pts_ok and worst_p <= TOL_M, "5 point cache: %d frames x %d joints = joint world positions, worst %.6f m (bar %.3f m; at %s)" % [pts.size(), N, worst_p, TOL_M, at_p])
	# (6) the camera
	var cam_txt := read(folder + "/" + NM + "_props.usda")
	var cam_ok := cam_txt.find("def Camera \"Shot\"") >= 0
	var fo := {}
	var cam_tr := {}
	var mode := ""
	for ln in cam_txt.split("\n"):
		var s := ln.strip_edges()
		if s.begins_with("float focalLength.timeSamples"):
			mode = "f"
		elif s.begins_with("matrix4d xformOp:transform.timeSamples"):
			mode = "t"
		elif s == "}":
			mode = ""
		elif mode != "" and ":" in s:
			if mode == "f":
				fo[s.get_slice(":", 0).to_int()] = s.get_slice(":", 1).replace(",", "").to_float()
			else:
				cam_tr[s.get_slice(":", 0).to_int()] = UT.nums(s.get_slice(":", 1))
	var worst_cam := 0.0
	for i in n:
		if not cam_tr.has(i) or not fo.has(i):
			cam_ok = false
			break
		var t := minf(i / fps, S.length())
		var k := ShotCam.sample(S.camera, t)
		var origin := Vector3(cam_tr[i][12], cam_tr[i][13], cam_tr[i][14])
		worst_cam = maxf(worst_cam, origin.distance_to(k["pos"]))
		worst_cam = maxf(worst_cam, absf(float(fo[i]) - float(k["f"])))
	ok(cam_ok and fo.size() == n and cam_tr.size() == n and worst_cam <= 1e-4,
		"6 camera Shot: %d samples, origin and focal length = ShotCam at each frame, worst %.7f (m or mm)" % [cam_tr.size(), worst_cam])
	# (7) the app's command, and the dialog
	var app: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	await process_frame
	app._load_scene("res://scenes/combo3.json")
	app.S.layers = S.layers.duplicate(true)
	app.S.camera = S.camera.duplicate(true)
	var out: String = app._export_usd_layers(DIR)
	var cmd_ok := out != "" and FileAccess.file_exists(out) and UT.parse(read(out)).has("meta")
	var cmd_sub := 0
	if cmd_ok:
		for ln in read(out).split("\n"):
			if ln.strip_edges().begins_with("@./"):
				cmd_sub += 1
	ok(cmd_ok and cmd_sub == 6,
		"7 the command wrote %s with %d sublayers (the 6 of the scene: props, points, 2 layers, base, skeleton); the same set as write_layers" % [out.get_file(), cmd_sub])
	app.queue_free()
	var mt := ExportDialog.target("maya")
	var rt := ExportDialog.target("raw")
	var has_layers := func(t: Dictionary) -> bool:
		for f in t["formats"]:
			if String(f["run"]) == "usda_layers":
				return true
		return false
	var needs := String(mt.get("needs", ""))
	ok(has_layers.call(mt) and has_layers.call(rt) and needs.find("ALEMBIC") >= 0 and needs.find("point cache") >= 0,
		"7b the export dialog: maya and raw offer the USD layers; maya's needs say Alembic is not written and why (point cache)")
	rm_tree(DIR)
	_done()


func _done() -> void:
	print("USD LAYERS TEST %s %d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
