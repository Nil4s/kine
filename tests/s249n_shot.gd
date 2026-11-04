extends SceneTree
## s249n picture of the temple build. godot --position -30000,-30000 --path . -s tests/s249n_shot.gd -- out.png
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s257_temple.json"))
	var res := Part.replay((d["part"] as Dictionary).duplicate(true), -1, {})
	var mi := MeshInstance3D.new()
	mi.mesh = res["mesh"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.45, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	root.add_child(mi)
	var bb := mi.get_aabb()
	var c := bb.get_center()
	var cam := Camera3D.new()
	root.add_child(cam)
	var r := bb.size.length()
	cam.look_at_from_position(c + Vector3(0.7, 0.5, 1.0).normalized() * r * 1.1, c)
	cam.far = r * 10.0
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.size = Vector2i(1280, 720)
	for i in 6:
		await process_frame
	var out := OS.get_cmdline_user_args()[0]
	root.get_texture().get_image().save_png(out)
	print("shot ", out, " aabb ", bb)
	print("s249n_shot: 0 fail")
	quit(0)
