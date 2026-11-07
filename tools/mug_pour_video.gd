extends SceneTree
## Mug pour in REAL TIME (30 fps of simulated time) through the L31 smoothed water renderer (WaterSurface + WaterRender, ssf on).
## The pour is the ch8 (e) one: a 16 mm stream, one slab of height h every POUR_EVERY steps entering at h / (POUR_EVERY step), 1.5 cups poured.
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tools/mug_pour_video.gd -- <out_dir> [seconds]
## env: POUR_EVERY (default 7, ~0.10 L/s (Nick 11-06)), MUG_HALF (default 0.008 m)
## then: ffmpeg -framerate 30 -i <out_dir>/f%04d.png -c:v libx264 -pix_fmt yuv420p <out_dir>/pour.mp4

const G := 9.81


func _mesh(verts: PackedVector3Array, tris: PackedInt32Array, col: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size() - 2, 3):
		st.add_vertex(verts[tris[i]])
		st.add_vertex(verts[tris[i + 1]])
		st.add_vertex(verts[tris[i + 2]])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


func _box(p: Vector3, s: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	mi.mesh = b
	mi.position = p
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	return mi


func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "C:/Temp/claude/mugpour"
	var secs: float = float(args[1]) if args.size() > 1 else 4.0
	DirAccess.make_dir_recursive_absolute(out)
	var every: int = int(OS.get_environment("POUR_EVERY")) if OS.has_environment("POUR_EVERY") else 7
	var half: float = float(OS.get_environment("MUG_HALF")) if OS.has_environment("MUG_HALF") else 0.008
	var F = Fluid.make()
	F.set_threads(8)
	var mh: float = float(OS.get_environment("MUG_H")) if OS.has_environment("MUG_H") else 0.002
	var m := FluidScenes.mug(F, mh)
	var h: float = m["h"]
	var cx: float = m["cx"]
	var cz: float = m["cz"]
	var rim: float = m["rim"]
	var cap: float = m["cap"]
	var props := [_mesh(m["verts"], m["tris"], Color(0.93, 0.92, 0.88)), _box(Vector3(cx, -0.01, cz), Vector3(0.6, 0.02, 0.6), Color(0.55, 0.42, 0.3))]
	var params := {"sky_top": Color(0.45, 0.62, 0.9), "sky_horizon": Color(0.95, 0.96, 1.0), "scatter_col": Color(0.05, 0.30, 0.38), "scatter_k": 14.0, "foam_gain": 0.0, "debug": 0.0}
	var look := Vector3(cx, rim - 0.02, cz)
	var step_t := mh   # CFL: one cell per step at ~1 m/s
	var poured := 0.0
	var pouring := true
	var t_stop := 0.0
	var seed_i := 100
	var nsteps := 0
	var t := 0.0
	var nf := int(secs * 30.0)
	for f in nf:
		var target := (f + 1) / 30.0
		while t < target - 1e-9:
			F.advance(step_t)
			t += step_t
			nsteps += 1
			if pouring and nsteps % every == 0:
				var k: int = F.add_fluid_box(Vector3(cx - half, rim + 0.03, cz - half), Vector3(cx + half, rim + 0.03 + h, cz + half), Vector3(0, -h / (every * step_t), 0), seed_i)
				seed_i += 1
				poured += float(k) / 8.0 * h * h * h
				if poured >= 1.5 * cap:
					pouring = false
					t_stop = t
		var bs := WaterSurface.build(F, 0.5, 2, 30, h, 1.0, false)
		if bs["pos"].size() == 0:
			continue
		var mesh := WaterSurface.make_mesh(bs["pos"], bs["idx"], WaterSurface.normals(bs["pos"], bs["idx"]), PackedFloat32Array())
		var r: Dictionary = await WaterRender.render(root, {"size": Vector2i(960, 720), "cam_pos": look + Vector3(0.0, 0.16, 0.22), "cam_look": look, "fov": 32.0,
			"water": mesh, "bg": Color(0.88, 0.9, 0.93), "props": props.map(func(p): return p.duplicate()), "params": params, "ssf": true})
		(r["color"] as Image).save_png("%s/f%04d.png" % [out, f])
	print("mug_pour_video: %d frames, %.2f s, pour rate %.3f L/s (every %d, stream %.0f mm), poured %.3f L, cup %.3f L" % [nf, t, poured * 1000.0 / maxf(t_stop if t_stop > 0.0 else t, 1e-6), every, 2000.0 * half, poured * 1000.0, cap * 1000.0])
	quit()
