extends SceneTree
## CH5c step 1: where does the pale asphalt come from? Diagnosis on the PARKED (CH5b) shader: toggle one light term at a time, dry and wet,
## and print the mean sRGB luminance of the asphalt strip (ground rays landing at x in [1.2, 2.6], z in [-7, -1], outside every bowl).
## godot --path . -s tests/ch5cdiag_test.gd (wtest.sh ch5cdiag). Not a bar: prints a table.
var ws: WetStreet
const OUT := "C:/Users/Nick/tools/kine_workers/out/ch5c/"


func _init() -> void:
	_run.call_deferred()


func asphalt_mean(cam: Camera3D, img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var o := cam.project_ray_origin(Vector2(x, y))
			var d := cam.project_ray_normal(Vector2(x, y))
			if d.y >= -0.001:
				continue
			var g := o + d * (-o.y / d.y)
			if g.x < 1.2 or g.x > 2.6 or g.z < -7.0 or g.z > -1.0:
				continue
			if ws.bowl_field(g.x, g.z) < -0.01:
				continue
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return s / maxf(float(n), 1.0)


func shot(cam: Camera3D, name: String) -> float:
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT)
	img.save_png(OUT + "diag_" + name + ".png")
	var m := asphalt_mean(cam, img)
	print("DIAG %-26s asphalt mean luminance %.4f" % [name, m])
	return m


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var poses := [Vector3(-1.2, WetStreet.EYE, 1.5), Vector3(0.0, WetStreet.EYE, 1.5), Vector3(1.2, WetStreet.EYE, 1.5)]
	ws = WetStreet.new()
	root.add_child(ws)
	ws.build(poses)
	var cam := Camera3D.new()
	cam.fov = WetStreet.FOV
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 80.0
	root.add_child(cam)
	cam.global_position = Vector3(0.0, WetStreet.EYE, 1.5)
	cam.rotation_degrees = Vector3(WetStreet.PITCH_DEG, 0, 0)
	cam.current = true
	var m: ShaderMaterial = ws.mat
	var lc: PackedVector3Array = m.get_shader_parameter("lamp_cols")
	var amb: Vector3 = m.get_shader_parameter("amb_sky")
	var wal: Vector3 = m.get_shader_parameter("wall_col")
	var zero := PackedVector3Array()
	zero.resize(8)
	for mode in ["wet", "dry"]:
		ws.set_dry(mode == "dry")
		await shot(cam, mode + "_base")
		m.set_shader_parameter("lamp_cols", zero)
		await shot(cam, mode + "_no_lamps")
		m.set_shader_parameter("amb_sky", Vector3.ZERO)
		await shot(cam, mode + "_no_lamps_no_amb")
		m.set_shader_parameter("wall_col", Vector3.ZERO)
		await shot(cam, mode + "_nothing_but_mirror")
		m.set_shader_parameter("amb_sky", amb)
		m.set_shader_parameter("wall_col", wal)
		m.set_shader_parameter("lamp_cols", lc)
		m.set_shader_parameter("diff_gain", 0.0)
		await shot(cam, mode + "_spec_only")
		m.set_shader_parameter("diff_gain", 0.4)
		m.set_shader_parameter("amb_sky", Vector3.ZERO)
		m.set_shader_parameter("wall_col", Vector3.ZERO)
		await shot(cam, mode + "_lamps_only")
		m.set_shader_parameter("amb_sky", amb)
		m.set_shader_parameter("wall_col", wal)
	print("ch5cdiag: 0 fail")
	quit(0)
