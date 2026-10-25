## godot --headless --path . -s tests/usd_pxr_ref.gd -- <dir>     (ROADMAP 79, the pxr check's reference)
## Writes into <dir>: the layered set (<dir>/usdl_test_usd/, the same scene as tests/usd_layers_test.gd), the flat
## export (<dir>/flat/combo3.usda), and ref.json: the app's pose (rotation w x y z per joint, Body.ORDER) at every frame for
## three configs: "full" (both layers), "lower" (the fix only: the top layer muted), "none" (no layer). tests/py/usd_pxr_check.py
## composes the USD with pxr and compares against ref.json.
extends SceneTree

const NM := "usdl_test"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "user://usd_pxr"
	var abs := ProjectSettings.globalize_path(dir) if dir.begins_with("user://") else dir
	DirAccess.make_dir_recursive_absolute(abs + "/flat")
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	S.layers = [
		{"name": "fix", "mode": "add", "w": 1.0, "v": {"spine_01": Vector3(12, 0, 0), "upperarm_r": Vector3(0, 0, 25)}},
		{"name": "lean", "mode": "over", "w": 1.0, "wk": [[0.0, 0.0], [0.6, 1.0], [1.2, 0.3]], "v": {"neck_01": Vector3(-20, 0, 0), "head": Vector3(0, 15, 0)}},
	]
	S.shots = [{"t": 0.0, "name": "Shot 1", "keys": [{"t": 0.0, "pos": Vector3(0.6, 1.4, 3.0), "aim": Vector3(0, 1.0, 0), "f": 50.0},
		{"t": 1.0, "pos": Vector3(1.2, 1.5, 2.5), "aim": Vector3(0, 1.1, 0), "f": 35.0}]}]
	var fps := float(S.fps)
	var n := int(ceil(S.length() * fps - 1e-6)) + 1
	var w1 := UsdExport.write_layers(S, B, abs, NM)
	var fw := UsdExport.write(S, B, abs + "/flat/combo3.usda")
	print("WROTE layered=%d flat=%d root=%s" % [w1[0], fw[0], w1[1].get("root", "")])
	var cfgs := {}
	var lower := S.clone()
	lower.layers = [S.layers[0].duplicate(true)]
	var none := S.clone()
	none.layers = []
	none.layer = {}
	for pair in [["full", S], ["lower", lower], ["none", none]]:
		var sc: Scene = pair[1]
		var frames := []
		for i in n:
			sc.apply(B, minf(i / fps, S.length()))
			B.fk()
			var row := []
			for j in Body.ORDER:
				var q := B.compose(j, B.ang[j]).normalized()
				row.append([q.w, q.x, q.y, q.z])
			frames.append(row)
		cfgs[pair[0]] = frames
	var f := FileAccess.open(abs + "/ref.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"n": n, "fps": fps, "joints": Body.ORDER, "configs": cfgs}))
	f.close()
	print("REF written n=%d configs=%s" % [n, cfgs.keys()])
	TestFiles.cleanup()
	quit(0)
