extends SceneTree
## L31: the same stills as tools/liq2_stills.gd with the screen-space smoothing on (opts ssf). Writes compare.png, dam.png, glass.png to C:/Temp/claude/l31/ (WATER3_SSF=0 for the L5 render, WATER3_DEBUG=1 for the normal, 2 for the holes).
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


## an unlit box with vertical stripes (so that refraction through the water is visible)
func _stripes(p: Vector3, s: Vector3) -> MeshInstance3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, Color(0.12, 0.14, 0.2) if (x / 8) % 2 == 0 else Color(0.96, 0.94, 0.88))
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	mi.mesh = b
	mi.position = p
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(6, 6, 6)
	mi.material_override = m
	return mi


func _init() -> void:
	await process_frame
	var size := Vector2i(900, 600)
	var ssf = OS.get_environment("WATER3_SSF") != "0"
	if OS.get_environment("WATER3_SIGMA") != "":
		ssf = {"sigma_w": float(OS.get_environment("WATER3_SIGMA")), "sigma_r": float(OS.get_environment("WATER3_RANGE")) if OS.get_environment("WATER3_RANGE") != "" else 0.008, "reps": int(OS.get_environment("WATER3_REPS")) if OS.get_environment("WATER3_REPS") != "" else 2}
	var dbg := float(OS.get_environment("WATER3_DEBUG")) if OS.get_environment("WATER3_DEBUG") != "" else 0.0
	var params := {"sky_top": Color(0.45, 0.62, 0.9), "sky_horizon": Color(0.9, 0.94, 1.0), "scatter_col": Color(0.05, 0.30, 0.38), "scatter_k": 14.0, "foam_gain": 0.0, "debug": dbg}
	# ---- dam break
	var F = Fluid.make()
	F.set_threads(8)
	var sc := FluidScenes.dam_break(F, 24)
	F.advance(2.0 * sqrt(sc["a"] / (2.0 * G)))
	var bs := WaterSurface.build(F, 0.5, 2, 30, sc["h"], 1.0, false)
	var nrm := WaterSurface.normals(bs["pos"], bs["idx"])
	var mesh := WaterSurface.make_mesh(bs["pos"], bs["idx"], nrm, PackedFloat32Array())
	var ctr := Vector3(0.45, 0.12, 0.05)
	var r1: Dictionary = await WaterRender.render(root, {"size": size, "cam_pos": Vector3(0.75, 0.32, 0.85), "cam_look": Vector3(0.3, 0.1, 0.05), "fov": 34.0, "water": mesh, "bg": Color(0.72, 0.8, 0.9),
		"props": [_box(Vector3(0.4, -0.02, 0.0), Vector3(2.4, 0.04, 1.6), Color(0.82, 0.8, 0.74))], "params": params, "ssf": ssf})
	r1["color"].save_png("C:/Temp/claude/l31/dam.png")
	if r1.has("smooth"):
		print("dam: smoothing chain output ok")
	print("dam: ", bs["pos"].size(), " vertices, ", bs["idx"].size() / 3, " triangles, volume ", bs["volume"])
	# ---- a glass of still water: the mug cut-cell scene filled directly with a square column (inscribed in the cup), settled; only the WATER is drawn
	# (the glass is not rendered: the water cylinder against a striped backdrop is what the reference photo shows).
	var F2 = Fluid.make()
	F2.set_threads(8)
	var m := FluidScenes.mug_cut(F2, 0.003)
	var hh0: float = m["h"]
	var flo: float = 1.4 * hh0 + m["floor"]
	var hs := 0.0255   # half width: sqrt(2) * hs < R_in = 36 mm
	F2.add_fluid_box(Vector3(m["cx"] - hs, flo + 0.002, m["cz"] - hs), Vector3(m["cx"] + hs, flo + 0.100, m["cz"] + hs), Vector3.ZERO, 7)
	for i in 300:
		F2.advance(0.003)
	var bs2 := WaterSurface.build(F2, 0.5, 2, 30, m["h"], 1.0, false)
	var mesh2 := WaterSurface.make_mesh(bs2["pos"], bs2["idx"], WaterSurface.normals(bs2["pos"], bs2["idx"]), PackedFloat32Array())
	var mugc := Vector3(m["cx"], flo + 0.035, m["cz"])
	var back := _stripes(Vector3(m["cx"], mugc.y, m["cz"] - 0.16), Vector3(0.7, 0.4, 0.01))
	var table := _stripes(Vector3(m["cx"], -0.01 + 0.0, m["cz"]), Vector3(0.7, 0.02, 0.5))
	var gp := {"sky_top": Color(0.45, 0.62, 0.9), "sky_horizon": Color(0.95, 0.96, 1.0), "scatter_col": Color(0.05, 0.30, 0.38), "scatter_k": 14.0, "foam_gain": 0.0, "debug": dbg}
	var r2: Dictionary = await WaterRender.render(root, {"size": size, "cam_pos": mugc + Vector3(0.0, 0.085, 0.30), "cam_look": mugc + Vector3(0, 0.0, 0), "fov": 22.0, "water": mesh2, "bg": Color(0.88, 0.9, 0.93),
		"props": [back, table], "params": gp, "ssf": ssf})
	r2["color"].save_png("C:/Temp/claude/l31/glass.png")
	if r2.has("smooth"):   # development: the smoothed depth texture (r depth, g water, b thickness x 10) and the raw depth pass
		for nm in ["smooth", "depth"]:
			var im: Image = r2[nm]
			var o := Image.create(im.get_width(), im.get_height(), false, Image.FORMAT_RGB8)
			for y in im.get_height():
				for x in im.get_width():
					var c := im.get_pixel(x, y)
					o.set_pixel(x, y, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b * 10.0, 0, 1)))
			o.save_png("C:/Temp/claude/l31/glass_%s.png" % nm)
	# ---- compare: reference photo left, ours right
	var ref := Image.load_from_file("res://docs/liquid2/ref_photo_600.jpg")
	var hh := size.y
	ref.resize(int(ref.get_width() * float(hh) / ref.get_height()), hh, Image.INTERPOLATE_LANCZOS)
	var comp := Image.create(ref.get_width() + size.x + 8, hh, false, Image.FORMAT_RGB8)
	comp.fill(Color.WHITE)
	comp.blit_rect(ref, Rect2i(0, 0, ref.get_width(), hh), Vector2i(0, 0))
	var ours: Image = r2["color"]
	ours.convert(Image.FORMAT_RGB8)
	comp.blit_rect(ours, Rect2i(0, 0, size.x, hh), Vector2i(ref.get_width() + 8, 0))
	comp.save_png("C:/Temp/claude/l31/compare.png")
	print("stills written; glass: ", bs2["pos"].size(), " vertices, volume ", bs2["volume"], " L ", bs2["volume"] * 1000.0)
	quit(0)
