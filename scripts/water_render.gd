class_name WaterRender
extends RefCounted
## L5: renders a water mesh with shaders/water_v2.gdshader (thickness from shaders/water_thick.gdshader) into images, in its own World3D.
## Usage (inside a SceneTree script):  var r = await WaterRender.render(root, {...})  ->  {color: Image, thick: Image}
## opts: size (Vector2i), cam_pos, cam_look, fov, water (Mesh), props (Array of Node3D, layer 1 only), sky colour via the environment, shader params in "params".

const WATER_LAYER := 2   # bit value 2: seen by the thickness camera as well


static func _linear_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	return e


static func render(host: Node, opts: Dictionary) -> Dictionary:
	var size: Vector2i = opts.get("size", Vector2i(960, 600))
	var main := SubViewport.new()
	main.size = size
	main.own_world_3d = true
	main.msaa_3d = Viewport.MSAA_4X
	main.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(main)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = opts.get("bg", Color(0.8, 0.85, 0.9))
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	main.add_child(we)
	for n in opts.get("props", []):
		main.add_child(n)
	var cam := Camera3D.new()
	cam.fov = opts.get("fov", 38.0)
	cam.cull_mask = 1
	main.add_child(cam)
	cam.position = opts["cam_pos"]
	cam.look_at(opts["cam_look"], opts.get("up", Vector3.UP))
	cam.current = true
	# thickness pass: its own float viewport, same world (child of the main viewport), sees only layer 2
	var thick := SubViewport.new()
	thick.size = size
	thick.transparent_bg = true
	thick.use_hdr_2d = true
	thick.msaa_3d = Viewport.MSAA_DISABLED
	thick.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.add_child(thick)
	var tcam := Camera3D.new()
	tcam.fov = cam.fov
	tcam.cull_mask = WATER_LAYER
	tcam.environment = _linear_env()
	thick.add_child(tcam)
	tcam.global_transform = cam.global_transform
	tcam.current = true
	var tmat := ShaderMaterial.new()
	tmat.shader = load("res://shaders/water_thick.gdshader")
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water_v2.gdshader")
	wmat.set_shader_parameter("thick_tex", thick.get_texture())
	for k in opts.get("params", {}):
		wmat.set_shader_parameter(k, opts["params"][k])
	var mesh: Mesh = opts["water"]
	var mi := MeshInstance3D.new()   # drawn in the main view with the water material
	mi.mesh = mesh
	mi.material_override = wmat
	mi.layers = 1
	mi.extra_cull_margin = 10.0
	main.add_child(mi)
	var mt := MeshInstance3D.new()   # drawn in the thickness view only
	mt.mesh = mesh
	mt.material_override = tmat
	mt.layers = WATER_LAYER
	mt.extra_cull_margin = 10.0
	main.add_child(mt)
	for i in 4:
		await RenderingServer.frame_post_draw
	var out := {"color": main.get_texture().get_image(), "thick": thick.get_texture().get_image()}
	main.queue_free()
	return out


## linear-light float of an sRGB 8 bit channel
static func lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## L31 STUB (bars commit): the frame timing is not implemented yet.
static func time_frames(_host: Node, _opts: Dictionary, _frames: int) -> float:
	return -1.0
