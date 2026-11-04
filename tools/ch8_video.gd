extends SceneTree
## CH8: renders the dam break and the mug fill to PNG frames (slow motion), from the C++ solver, with the refractive water material.
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tools/ch8_video.gd -- <out_dir> [dam_frames] [mug_frames]
## then: ffmpeg -framerate 30 -i <out_dir>/f%04d.png -c:v libx264 -pix_fmt yuv420p <out_dir>/ch8.mp4
var out := "C:/Users/Nick/tools/kine_workers/out/ch8"
var vp: SubViewport
var cam: Camera3D
var water: MeshInstance3D
var frame := 0
var W := 1280
var H := 720
var water_mat: ShaderMaterial


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var nd := int(args[1]) if args.size() > 1 else 150
	var nm := int(args[2]) if args.size() > 2 else 150
	DirAccess.make_dir_recursive_absolute(out)
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.82, 0.86, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 0.9)
	e.ambient_light_energy = 0.7
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 38
	vp.add_child(cam)
	cam.current = true
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water_refract.gdshader")
	await _dam(nd)
	await _mug(nm)
	print("ch8_video: %d frames in %s" % [frame, out])
	quit(0)


func _box(p: Vector3, s: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	m.mesh = b
	m.position = p
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.8
	m.material_override = mat
	vp.add_child(m)
	return m


func _set_surface(F: Object) -> void:
	var sf: Dictionary = F.surface(1, 0.5)
	var vs: PackedVector3Array = sf["verts"]
	if vs.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = sf["normals"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	water.mesh = am


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("%s/f%04d.png" % [out, frame])
	frame += 1


func _dam(n: int) -> void:
	var F = Fluid.make()
	F.set_threads(8)
	var sc := FluidScenes.dam_break(F, 20)
	var h: float = sc["h"]
	var L := 82 * h
	var Hh := 62 * h
	var D := 10 * h
	var kids := []
	kids.append(_box(Vector3(L / 2, -0.01, D / 2), Vector3(L + 0.1, 0.02, D + 0.1), Color(0.55, 0.57, 0.6)))
	kids.append(_box(Vector3(L / 2, Hh / 2, -0.005), Vector3(L, Hh, 0.01), Color(0.9, 0.92, 0.95)))
	kids.append(_box(Vector3(-0.005, Hh / 2, D / 2), Vector3(0.01, Hh, D), Color(0.7, 0.75, 0.8)))
	kids.append(_box(Vector3(L + 0.005, Hh / 2, D / 2), Vector3(0.01, Hh, D), Color(0.7, 0.75, 0.8)))
	# a gate marker at the column face and ruler ticks every a
	for i in 5:
		kids.append(_box(Vector3(h + i * 0.2, 0.0, D + 0.02), Vector3(0.004, 0.01, 0.004), Color(0.1, 0.1, 0.1)))
	water = MeshInstance3D.new()
	water.material_override = water_mat
	vp.add_child(water)
	cam.position = Vector3(L * 0.5, 0.33, 1.15)
	cam.look_at(Vector3(L * 0.5, 0.2, D * 0.5))
	var total := 0.55   # simulated seconds shown in n frames (slow motion)
	for f in n:
		F.advance(total / n)
		_set_surface(F)
		await _shot()
	for k in kids:
		k.queue_free()
	water.queue_free()


func _mug(n: int) -> void:
	var F = Fluid.make()
	F.set_threads(8)
	var m := FluidScenes.mug(F, 0.003)
	var h: float = m["h"]
	var cx: float = m["cx"]
	var cz: float = m["cz"]
	var rim: float = m["rim"]
	var cap: float = m["cap"]
	# the cup mesh itself
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vs: PackedVector3Array = m["verts"]
	var tr: PackedInt32Array = m["tris"]
	for i in tr.size():
		st.add_vertex(vs[tr[i]])
	st.generate_normals()
	var cup := MeshInstance3D.new()
	cup.mesh = st.commit()
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.92, 0.88, 0.8)
	cm.roughness = 0.35
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cup.material_override = cm
	vp.add_child(cup)
	var table := _box(Vector3(cx, 0.0, cz), Vector3(0.6, 2.0 * h, 0.6), Color(0.45, 0.33, 0.24))
	water = MeshInstance3D.new()
	water.material_override = water_mat
	vp.add_child(water)
	cam.position = Vector3(cx + 0.05, rim * 1.5, cz + 0.30)
	cam.look_at(Vector3(cx, rim * 0.7, cz))
	var step_t := 0.003
	var half := 0.014
	var poured := 0.0
	var seed_i := 100
	var pouring := true
	var total := 1.8
	var per := total / n
	var t := 0.0
	for f in n:
		var target := (f + 1) * per
		while t < target - 1e-9:
			F.advance(step_t)
			t += step_t
			if pouring:
				var k: int = F.add_fluid_box(Vector3(cx - half, rim + 0.03, cz - half), Vector3(cx + half, rim + 0.03 + h, cz + half), Vector3(0, -1.0, 0), seed_i)
				seed_i += 1
				poured += float(k) / 8.0 * h * h * h
				if poured >= 1.5 * cap:
					pouring = false
		_set_surface(F)
		await _shot()
