extends SceneTree
## godot --path . --position 4000,4000 -s tests/shot54_test.gd : the fold at frame 53, self-collision off vs on, to C:/Temp/claude/c54/
func _init():
	create_timer(300.0).timeout.connect(func(): quit(2))
	var pt = load("res://tests/prof54_test.gd").new()
	var fx = pt.fixture()
	var off = pt.bake(fx, false)
	var on = pt.bake(fx, true)
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/c54")
	root.size = Vector2i(1280, 720)
	var res := {}
	for nm in ["off", "on"]:
		var fr: PackedVector3Array = (off if nm == "off" else on)["frames"][53]
		var sv := SubViewport.new(); sv.size = Vector2i(640, 720); sv.own_world_3d = true
		root.add_child(sv)
		var mesh := ArrayMesh.new(); var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = fr; arr[Mesh.ARRAY_INDEX] = Cloth.faces()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new(); mi.mesh = mesh
		var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.8, 0.2, 0.2 if nm == "on" else 0.5); mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat; sv.add_child(mi)
		var cam := Camera3D.new(); sv.add_child(cam)
		var c := Vector3.ZERO
		for v in fr: c += v
		c /= fr.size()
		cam.position = c + Vector3(0.9, 0.2, 0.7); cam.look_at_from_position(cam.position, c); cam.fov = 40
		var l := DirectionalLight3D.new(); sv.add_child(l); l.rotation_degrees = Vector3(-40, 30, 0)
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await process_frame; await process_frame; await process_frame
		sv.get_texture().get_image().save_png("C:/Temp/claude/c54/fold_%s.png" % nm)
	quit()
