extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tools/ch2_render.gd -- [out_dir] [seconds] [fps] [sub]
## CH2: renders the running regulator clock to a PNG sequence with sub-frames (the shutter): `sub` frames per output frame are drawn at evenly
## spaced times inside one frame time and written as sub-frame images; tools/ch2_video.sh averages each group of `sub` into one frame (motion blur) and
## encodes out/ch2/clock.mp4. 1280 x 720.
const ClockC := preload("res://scripts/build/clock_ch2.gd")
const SceneC := preload("res://scripts/build/clock_ch2_scene.gd")
const KEYS := [   # t, camera position (m), target (m), fov
	[0.0, Vector3(0.02, -0.30, 2.55), Vector3(0.0, -0.33, 0.0), 30.0],
	[4.0, Vector3(0.02, -0.28, 2.40), Vector3(0.0, -0.30, 0.0), 30.0],
	[9.0, Vector3(0.30, 0.16, 0.62), Vector3(0.0, 0.06, 0.02), 34.0],
	[13.0, Vector3(0.16, 0.12, 0.30), Vector3(0.0, 0.075, 0.02), 38.0],
	[17.0, Vector3(-0.10, 0.10, 0.34), Vector3(0.0, 0.05, 0.03), 38.0],
	[20.0, Vector3(0.0, 0.06, 0.72), Vector3(0.0, 0.05, 0.0), 32.0]]


func smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func cam_at(t: float) -> Array:
	var i := 0
	while i < KEYS.size() - 2 and t > KEYS[i + 1][0]:
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var u := smooth(clampf((t - a[0]) / (b[0] - a[0]), 0.0, 1.0))
	return [(a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u), lerpf(a[3], b[3], u)]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "C:/Temp/claude/ch2_frames"
	var secs: float = float(args[1]) if args.size() > 1 else 20.0
	var fps: int = int(args[2]) if args.size() > 2 else 30
	var sub: int = int(args[3]) if args.size() > 3 else 4
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	var C := ClockC.new()
	var sim := C.simulate(secs + 1.0)
	C.capture_base(sim["theta"][0])
	var world := Node3D.new()
	root.add_child(world)
	var sc := SceneC.new()
	sc.build(world, C)
	# sky for the reflections, soft room light
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.24, 0.32)
	sky_mat.sky_horizon_color = Color(0.95, 0.80, 0.60)
	sky_mat.ground_horizon_color = Color(0.35, 0.28, 0.22)
	sky_mat.ground_bottom_color = Color(0.05, 0.04, 0.04)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.05
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.90, 0.75)
	key.light_energy = 2.2
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 6.0
	key.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	world.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.70, 0.80, 1.0)
	fill.light_energy = 1.2
	fill.omni_range = 4.0
	fill.position = Vector3(-0.8, 0.5, 1.4)
	world.add_child(fill)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.85, 0.65)
	spot.light_energy = 14.0
	spot.spot_range = 3.0
	spot.spot_angle = 24.0
	spot.shadow_enabled = true
	spot.position = Vector3(0.45, 0.45, 0.9)
	world.add_child(spot)
	spot.look_at(Vector3(0.0, 0.06, 0.03), Vector3.UP)
	var cam := Camera3D.new()
	cam.far = 30.0
	world.add_child(cam)
	cam.current = true
	var dt: float = sim["dt"]
	var th: PackedFloat64Array = sim["theta"]
	var ph: PackedFloat64Array = sim["phi"]
	var total := int(secs * fps)
	for f in total:
		for s in sub:
			var t := (float(f) + (float(s) + 0.5) / float(sub) * 0.5) / float(fps)   # a half-frame shutter
			var i := mini(int(t / dt), th.size() - 1)
			sc.pose(th[i], ph[i])
			var cp := cam_at(float(f) / float(fps))
			cam.position = cp[0]
			cam.look_at_from_position(cp[0], cp[1], Vector3.UP)
			cam.fov = cp[2]
			await process_frame
			await process_frame
			var img := root.get_texture().get_image()
			img.save_png("%s/f%05d.png" % [out_dir, f * sub + s])
	print("ch2_render: %d frames written to %s" % [total * sub, out_dir])
	quit()
