## godot --headless --path . -s tools/export_usd.gd -- scenes/<name>.json [out.usda]   (GATES XX9)
## A scene -> USDA (UsdSkel). The writer is UsdExport (scripts/usd_export.gd); the app's "Export animation (.usda)" calls it too.
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- scenes/<name>.json [out.usda]")
		quit(1)
		return
	var src: String = args[0]
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(src)))
	var out: String = args[1] if args.size() > 1 else "res://exports/%s.usda" % src.get_file().get_basename()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r := UsdExport.write(S, B, out)
	if r[0] != OK:
		push_error("could not write %s (%s)" % [out, error_string(r[0])])
		quit(1)
		return
	print("%s -> %s: %d joints, %d frames at %d fps" % [src, out, r[1]["joints"], r[1]["frames"], S.fps])
	quit(0)
