## godot --headless --path . -s tools/export_usd.gd -- scenes/<name>.json [out.usda]   (GATES XX9)
## A scene -> USDA (UsdSkel). The writer is UsdExport (scripts/usd_export.gd); the app's "Export animation (.usda)" calls it too.
extends SceneTree


func _init() -> void:
	var args: Array = Array(OS.get_cmdline_user_args())
	if args.is_empty():
		push_error("usage: -- scenes/<name>.json [out.usda] [--skinned [--face]]")
		quit(1)
		return
	var skinned := args.has("--skinned")
	var face := args.has("--face")
	args = args.filter(func(a): return not String(a).begins_with("--"))
	var src: String = args[0]
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(src)))
	var out: String = args[1] if args.size() > 1 else "res://exports/%s.usda" % src.get_file().get_basename()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r: Array
	if skinned:   # L19: the mannequin with its skin weights (and, with --face, the face geometry and its six AU shapes)
		r = UsdExport.write_skinned(S, B, UsdWire.standalone(S, B, face), out)
	else:
		r = UsdExport.write(S, B, out)
	if r[0] != OK:
		push_error("could not write %s (%s)" % [out, error_string(r[0])])
		quit(1)
		return
	print("%s -> %s: %d joints, %d frames at %d fps" % [src, out, r[1]["joints"], r[1]["frames"], S.fps])
	quit(0)
