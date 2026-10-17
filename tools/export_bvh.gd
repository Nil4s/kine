## godot --headless --path . -s tools/export_bvh.gd -- scenes/<name>.json [out.bvh] [--check out.json]   (GATES G, OO2)
## A scene -> BVH. The writer is BvhExport (scripts/bvh_export.gd, round 34: the app's "Export animation (.bvh)" calls the
## same one); this is its command line. Exits 1 if the Euler round trip is off by 0.001 degree or more.
## --check writes every joint's world position at 4 frames, for the import test (Blender must land within 1 cm).
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- scenes/<name>.json [out.bvh] [--check out.json]")
		quit(1)
		return
	var src: String = args[0]
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(src)))
	var out := "res://moves/bvh/%s.bvh" % src.get_file().get_basename()
	if args.size() > 1 and not args[1].begins_with("--"):
		out = args[1]
	var ci := args.find("--check")
	var check_path: String = args[ci + 1] if ci >= 0 and ci + 1 < args.size() else ""
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r := BvhExport.write(S, B, out)
	var info: Dictionary = r[1]
	if r[0] != OK:
		push_error("could not write %s (%s)" % [out, error_string(r[0])])
		quit(1)
		return
	print("%s -> %s: %d joints, %d frames at %d fps (%.2f s); Euler round trip worst %.6f deg" % [src, out, info["joints"], info["frames"], S.fps, S.length(), info["worst_rt"]])
	if check_path != "":
		var fc := FileAccess.open(check_path, FileAccess.WRITE)
		fc.store_string(JSON.stringify({"fps": S.fps, "frames": info["at"]}))
		fc.close()
		print("check positions -> %s (frames %s)" % [check_path, str(info["at"].keys())])
	quit(0 if info["worst_rt"] < 1e-3 else 1)
