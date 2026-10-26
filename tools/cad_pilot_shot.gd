extends SceneTree
## godot --path . --position 4000,4000 -s tools/cad_pilot_shot.gd -- C:/Temp/claude/cad/pilot.png
## One picture of the CAD pilot: a 2x1x1 box minus a through hole, every edge filleted 0.1, clay on a dark ground (needs the KineCAD DLL).
const KCad := preload("res://scripts/kcad.gd")


func _init() -> void:
	await process_frame   # the tree is not running inside _init: look_at needs it
	if not KCad.available():
		print("cad_pilot_shot: no KineCAD (", KCad.last_error(), ")")
		quit(0)
		return
	var out := "C:/Temp/claude/cad/pilot.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var box := KCad.box(2, 1, 1)
	var hole := KCad.cylinder(0.25, 1.4)
	var part := KCad.fillet_all(KCad.cut(box, hole), 0.1)
	var mesh := KCad.tessellate(part, 0.002, 0.2)
	print("part faces %d, volume %.6f, %d tris" % [KCad.face_count(part), KCad.volume(part), mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3])
	root.size = Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("14161B")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("D8DCE3")
	mat.roughness = 0.85
	mi.material_override = mat
	mi.rotation = Vector3(0, 0, 0)
	root.add_child(mi)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 0.8
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.35
	root.add_child(fill)
	var cam := Camera3D.new()
	root.add_child(cam)
	# the part lies along X with its hole along Z: look from above and in front
	cam.position = Vector3(1.9, 2.0, 2.6)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 38.0
	cam.current = true
	for i in 6:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	KCad.release_all()
	quit(0)
