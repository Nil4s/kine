## godot --headless --path . -s tools/physics/check_bvh.gd -- file.bvh   : does Kine's BvhImport read a physics export?
extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var bv: Dictionary = BvhImport.parse(FileAccess.get_file_as_string(a[0]))
	if not bv["ok"]:
		print("parse failed: ", bv["why"]); quit(1); return
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r: Dictionary = BvhImport.to_scene(bv, B)
	print("import ok=", r.get("ok"), " frames=", bv["frames"].size(), " fps=", bv["fps"], " not_mapped=", r.get("not_mapped"), " missing=", r.get("missing"), " why=", r.get("why", ""))
	quit(0 if r.get("ok") else 1)
