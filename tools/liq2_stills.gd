extends SceneTree
## L5 stills: dam break and the poured mug through scripts/water_surface.gd + scripts/water_render.gd + shaders/water_v2.gdshader.
## Writes docs/liquid2/dam.png, mug.png and compare.png (reference photo on the left, ours on the right).
## Run (visible window offscreen):  godot --path . -s tools/liq2_stills.gd

const G := 9.81


func _prop_mesh(verts: PackedVector3Array, tris: PackedInt32Array, col: Color) -> MeshInstance3D:
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
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	return mi


func _init() -> void:
	await process_frame
	var size := Vector2i(900, 600)
	var params := {"sky_top": Color(0.45, 0.62, 0.9), "sky_horizon": Color(0.9, 0.94, 1.0), "scatter_col": Color(0.02, 0.2, 0.28), "scatter_k": 5.0}
	# ---- dam break
	var F = Fluid.make()
	F.set_threads(8)
	var sc := FluidScenes.dam_break(F, 24)
	F.advance(2.0 * sqrt(sc["a"] / (2.0 * G)))
	var bs := WaterSurface.build(F, 0.5, 4, 14, sc["h"], 0.6, true)
	var nrm := WaterSurface.normals(bs["pos"], bs["idx"])
	var mesh := WaterSurface.make_mesh(bs["pos"], bs["idx"], nrm, bs["foam"])
	var ctr := Vector3(0.45, 0.12, 0.05)
	var r1: Dictionary = await WaterRender.render(root, {"size": size, "cam_pos": Vector3(0.75, 0.32, 0.85), "cam_look": Vector3(0.3, 0.1, 0.05), "fov": 34.0, "water": mesh, "bg": Color(0.72, 0.8, 0.9),
		"props": [_box(Vector3(0.4, -0.02, 0.0), Vector3(2.4, 0.04, 1.6), Color(0.82, 0.8, 0.74))], "params": params})
	r1["color"].save_png("res://docs/liquid2/dam.png")
	print("dam: ", bs["pos"].size(), " vertices, ", bs["idx"].size() / 3, " triangles, volume ", bs["volume"])
	# ---- mug
	var F2 = Fluid.make()
	F2.set_threads(8)
	var m := FluidScenes.mug_cut(F2, 0.003)
	var step_t := 0.003
	var half := 0.014
	var poured := 0.0
	var t := 0.0
	var seed_i := 100
	while poured < 1.0 * m["cap"] or t < 0.0:
		F2.advance(step_t)
		t += step_t
		var n: int = F2.add_fluid_box(Vector3(m["cx"] - half, m["rim"] + 0.03, m["cz"] - half), Vector3(m["cx"] + half, m["rim"] + 0.03 + m["h"], m["cz"] + half), Vector3(0, -1.0, 0), seed_i)
		seed_i += 1
		poured += float(n) / 8.0 * m["h"] * m["h"] * m["h"]
	for i in 160:   # settle
		F2.advance(step_t)
	var bs2 := WaterSurface.build(F2, 0.5, 4, 4, m["h"], 1.0, true)
	var mesh2 := WaterSurface.make_mesh(bs2["pos"], bs2["idx"], WaterSurface.normals(bs2["pos"], bs2["idx"]), bs2["foam"])
	var mugc := Vector3(m["cx"], 0.05, m["cz"])
	var r2: Dictionary = await WaterRender.render(root, {"size": size, "cam_pos": mugc + Vector3(0.0, 0.07, 0.34), "cam_look": mugc + Vector3(0, 0.01, 0), "fov": 24.0, "water": mesh2, "bg": Color(0.75, 0.78, 0.82),
		"props": [_prop_mesh(m["verts"], m["tris"], Color(0.93, 0.92, 0.9)), _box(Vector3(m["cx"], -0.02, m["cz"]), Vector3(1.0, 0.04, 1.0), Color(0.55, 0.45, 0.35))], "params": params})
	r2["color"].save_png("res://docs/liquid2/mug_pour.png")
	# ---- compare: reference photo left, our mug right
	var ref := Image.load_from_file("C:/Temp/liq2_ref/ref_a.jpg")
	var hh := size.y
	ref.resize(int(ref.get_width() * float(hh) / ref.get_height()), hh, Image.INTERPOLATE_LANCZOS)
	var comp := Image.create(ref.get_width() + size.x + 8, hh, false, Image.FORMAT_RGB8)
	comp.fill(Color.WHITE)
	comp.blit_rect(ref, Rect2i(0, 0, ref.get_width(), hh), Vector2i(0, 0))
	var ours: Image = r1["color"]
	ours.convert(Image.FORMAT_RGB8)
	comp.blit_rect(ours, Rect2i(0, 0, size.x, hh), Vector2i(ref.get_width() + 8, 0))
	comp.save_png("res://docs/liquid2/compare.png")
	print("stills written; mug: ", bs2["pos"].size(), " vertices, volume ", bs2["volume"])
	quit(0)
