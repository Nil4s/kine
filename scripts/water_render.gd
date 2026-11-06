class_name WaterRender
extends RefCounted
## L5: renders a water mesh with shaders/water_v2.gdshader (thickness from shaders/water_thick.gdshader) into images, in its own World3D.
## Usage (inside a SceneTree script):  var r = await WaterRender.render(root, {...})  ->  {color: Image, thick: Image}
## L31: opts["ssf"] = true (or a Dictionary of sigma_w, sigma_r, reps) turns on SCREEN-SPACE SMOOTHING: the nearest surface depth is rendered (water_ssf_depth.gdshader), smoothed
## by a separable bilateral filter (water_ssf_smooth.gdshader), and the normal, the surface point and the thickness the shader uses are rebuilt from the smoothed image
## (water_v3.gdshader). Off = the L5 render with water_v2.gdshader, unchanged.
## opts: size (Vector2i), cam_pos, cam_look, fov, water (Mesh), props (Array of Node3D, layer 1 only), sky colour via the environment, shader params in "params".

const WATER_LAYER := 2   # bit value 2: seen by the thickness camera as well
const SSF_LAYER := 4     # bit value 4: seen only by the depth camera of the screen-space smoothing


static func _linear_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	return e


static func _float_view(main: SubViewport, size: Vector2i, cam: Camera3D, mask: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.use_hdr_2d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	main.add_child(vp)
	var c := Camera3D.new()
	c.fov = cam.fov
	c.cull_mask = mask
	c.environment = _linear_env()
	vp.add_child(c)
	c.global_transform = cam.global_transform
	c.current = true
	return vp


## builds the viewports and returns {main, thick, depth (null when ssf is off), chain: Array of the smoothing SubViewports}
static func _setup(host: Node, opts: Dictionary) -> Dictionary:
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
	var thick := _float_view(main, size, cam, WATER_LAYER)
	var tmat := ShaderMaterial.new()
	tmat.shader = load("res://shaders/water_thick.gdshader")
	var ssf = opts.get("ssf", false)
	var use_ssf: bool = (ssf is bool and ssf) or ssf is Dictionary
	var sp: Dictionary = ssf if ssf is Dictionary else {}
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water_v3.gdshader" if use_ssf else "res://shaders/water_v2.gdshader")
	wmat.set_shader_parameter("thick_tex", thick.get_texture())
	var mesh: Mesh = opts["water"]
	var chain: Array = []
	var depth: SubViewport = null
	if use_ssf:
		# the span of depths: the mesh box seen along the camera axis
		var fwd := -cam.global_transform.basis.z
		var bb := mesh.get_aabb()
		var zmin := 1e9
		var zmax := -1e9
		for k in 8:
			var corner := bb.position + bb.size * Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1)
			var dz := (corner - cam.global_position).dot(fwd)
			zmin = minf(zmin, dz)
			zmax = maxf(zmax, dz)
		var z0 := maxf(zmin - 0.002, 0.001)
		var zr := maxf(zmax - z0 + 0.002, 0.01)
		depth = _float_view(main, size, cam, SSF_LAYER)
		var dmat := ShaderMaterial.new()
		dmat.shader = load("res://shaders/water_ssf_depth.gdshader")
		dmat.set_shader_parameter("z0", z0)
		dmat.set_shader_parameter("zr", zr)
		var md := MeshInstance3D.new()
		md.mesh = mesh
		md.material_override = dmat
		md.layers = SSF_LAYER
		md.extra_cull_margin = 10.0
		main.add_child(md)
		# the 2D chain: pack the two passes, then (horizontal, vertical) x reps
		var modes := [0]
		for r in int(sp.get("reps", 2)):
			modes.append(1)
			modes.append(2)
		var prev: Texture2D = depth.get_texture()
		var pix_per_m := float(size.y) / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
		for m in modes:
			var vp := SubViewport.new()
			vp.size = size
			vp.disable_3d = true
			vp.use_hdr_2d = true
			vp.transparent_bg = false
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			main.add_child(vp)
			var rect := ColorRect.new()
			rect.size = Vector2(size)
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/water_ssf_smooth.gdshader")
			mat.set_shader_parameter("src", prev)
			mat.set_shader_parameter("thick_tex", thick.get_texture())
			mat.set_shader_parameter("mode", 0 if m == 0 else 1)
			mat.set_shader_parameter("dir", Vector2(0, 1) if m == 2 else Vector2(1, 0))
			mat.set_shader_parameter("z0", z0)
			mat.set_shader_parameter("zr", zr)
			mat.set_shader_parameter("pix_per_m", pix_per_m)
			mat.set_shader_parameter("sigma_w", float(sp.get("sigma_w", 0.006)))
			mat.set_shader_parameter("sigma_r", float(sp.get("sigma_r", 0.008)))
			mat.set_shader_parameter("tmax", 3.0 * zr)
			rect.material = mat
			vp.add_child(rect)
			chain.append(vp)
			prev = vp.get_texture()
		wmat.set_shader_parameter("ssf_tex", prev)
		wmat.set_shader_parameter("ssf_on", 1.0)
		wmat.set_shader_parameter("ssf_z0", z0)
		wmat.set_shader_parameter("ssf_zr", zr)
	for k in opts.get("params", {}):
		wmat.set_shader_parameter(k, opts["params"][k])
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
	return {"main": main, "thick": thick, "depth": depth, "chain": chain}


static func render(host: Node, opts: Dictionary) -> Dictionary:
	var s := _setup(host, opts)
	var main: SubViewport = s["main"]
	var thick: SubViewport = s["thick"]
	# each stage of the chain may read the one before it a frame late
	for i in 4 + (s["chain"] as Array).size() + 2:
		await RenderingServer.frame_post_draw
	var out := {"color": main.get_texture().get_image(), "thick": thick.get_texture().get_image()}
	if s["depth"] != null:
		out["smooth"] = ((s["chain"] as Array).back() as SubViewport).get_texture().get_image()
		out["depth"] = (s["depth"] as SubViewport).get_texture().get_image()
	main.queue_free()
	return out


## L31: the cost of a view in ms per frame: wall clock with vsync off over `frames` frames after 20 warm-up frames, and the GPU time of the smoothing viewports
## (depth pass + chain) per frame when the driver reports it. Returns {wall, gpu}.
static func time_frames(host: Node, opts: Dictionary, frames: int) -> Dictionary:
	var vs := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var s := _setup(host, opts)
	var vps: Array = []
	if s["depth"] != null:
		vps.append(s["depth"])
		vps.append_array(s["chain"])
	for vp in vps:
		RenderingServer.viewport_set_measure_render_time((vp as SubViewport).get_viewport_rid(), true)
	for i in 20:
		await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	var gpu := 0.0
	for i in frames:
		await RenderingServer.frame_post_draw
		for vp in vps:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu((vp as SubViewport).get_viewport_rid())
	var wall := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	(s["main"] as SubViewport).queue_free()
	DisplayServer.window_set_vsync_mode(vs)
	return {"wall": wall, "gpu": gpu / float(frames)}


## linear-light float of an sRGB 8 bit channel
static func lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)
