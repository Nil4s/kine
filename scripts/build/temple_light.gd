class_name TempleLight
extends RefCounted
## TEMPLE LIGHT (item 232): the light and the picture of an outdoor building (the Chinese hall) in the LIVE view, the same as the final shot.
##   SKY      a procedural sky SHADER: blue gradient, a sun disc and glow that follow the sun, soft clouds (fbm noise, lit from the sun side)
##   SUN      time of day -> elevation, colour (warm when low) and energy; azimuth and size (penumbra) are free; real soft shadows, cascades
##            fitted to what the camera sees, 8192 atlas on the good tier (the tiers of item 230 / Quality: low < medium < high)
##   BOUNCE   the sky's blue ambient fills the shadows (bluer than the lit side); SSAO in the corners; GI mode "off" | "ssil" | "sdfgi"
##   HAZE     exponential fog tinted like the horizon: far ground loses contrast with distance
##   EXPOSURE AgX tone map exposure
##   CAMERA   by numbers: position, target, fov (set_camera / get_camera), so a reference picture's camera can be matched
##   FINAL    final_shot(): the current camera, NO UI at all, to a PNG at a chosen size (default 1920 x 1080): a SubViewport of its own that
##            shares the live world (so the same sky, sun, shadows, GI) with 4x MSAA; a SubViewport draws no Control, so no UI pixel can reach it
## Everything the live toggle changes is snapshotted and put back (off = the view it was). It never touches materials (item 231).

const OUTDOOR_MIN := 2.0   # metres: a part this big is a building (the same line Realistic uses)
const SKY_SHADER := "shader_type sky;
uniform vec3 top_color : source_color = vec3(0.30, 0.55, 0.90);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.88, 0.97);
uniform vec3 ground_color : source_color = vec3(0.45, 0.50, 0.45);
uniform vec3 sun_dir = vec3(0.0, 0.5, 0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);
uniform float sun_cos = 0.99993;
uniform float sun_energy = 14.0;
uniform float cover = 0.5;
uniform float cloud_scale = 0.8;
uniform float seed = 2.0;
uniform sampler2D cloud_tex : repeat_enable, filter_linear_mipmap;
float fbm(vec2 p) { return 0.62 * texture(cloud_tex, p * 0.11).r + 0.28 * texture(cloud_tex, p * 0.37 + vec2(0.31, 0.77)).r + 0.10 * texture(cloud_tex, p * 1.3 + vec2(0.6, 0.2)).r; }
void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	vec3 sd3 = normalize(sun_dir);
	vec3 col = up >= 0.0 ? mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.45)) : mix(horizon_color, ground_color, smoothstep(0.0, 0.2, -up));
	float sd = dot(d, sd3);
	col += sun_color * (pow(max(sd, 0.0), 5.0) * 0.10 + pow(max(sd, 0.0), 80.0) * 0.45);
	float mask = 0.0;
	if (AT_CUBEMAP_PASS) {
		col = mix(col, vec3(0.86, 0.89, 0.94), cover * 0.22 * smoothstep(0.0, 0.3, up));   // the ambient only needs the average of the clouds
	} else if (up > 0.0) {
		vec2 uv = d.xz / (up + 0.2) * cloud_scale + vec2(seed * 3.1, seed * 1.7);
		float n = fbm(uv);
		float n2 = fbm(uv + sd3.xz * 0.10);
		float c = smoothstep(1.0 - cover * 0.9 - 0.02, 1.0 - cover * 0.9 + 0.12, n);
		float lit = clamp(1.0 - max(n2 - n, 0.0) * 6.0, 0.45, 1.0);
		vec3 ccol = mix(vec3(0.50, 0.58, 0.72), vec3(1.0, 0.98, 0.95), lit) * mix(vec3(1.0), sun_color, 0.45);
		mask = c * smoothstep(0.0, 0.10, up);
		col = mix(col, ccol, mask * 0.96);
	}
	if (sd > sun_cos) col = mix(sun_color * sun_energy, col, mask);
	COLOR = col;
}
"
const GROUND_SHADER := "shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 col_a : source_color = vec3(0.20, 0.36, 0.12);
uniform vec3 col_b : source_color = vec3(0.46, 0.55, 0.24);
uniform float tile = 6.0;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y); }
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz / tile;
	float n = vn(p) * 0.55 + vn(p * 4.1) * 0.30 + vn(p * 17.0) * 0.15;
	float fw = clamp(length(fwidth(p)) * 2.0, 0.0, 1.0);   // far away the detail averages out (no shimmer)
	n = mix(n, 0.5, fw);
	ALBEDO = mix(col_a, col_b, n);
	ROUGHNESS = 0.95;
}
"
## the quality tiers (Quality.TIERS): what each may spend on the light. high = the RTX 3070-class default
const TIER := {
	"high": {"atlas": 8192, "filter": 5, "ssao": true, "ssil": true, "gi": true, "radiance": 2, "splits": 4},
	"medium": {"atlas": 4096, "filter": 4, "ssao": true, "ssil": false, "gi": false, "radiance": 1, "splits": 4},
	"low": {"atlas": 2048, "filter": 2, "ssao": false, "ssil": false, "gi": false, "radiance": 0, "splits": 2},
}
const GI_MODES := ["off", "ssil", "sdfgi"]
const DEFAULT_GI := "off"   # what tests/s232_test.gd measured and its rule picked (see the G lines)

## the settings (typed numbers; the panel, agent_tools and the tests write them)
static var on := false
static var time_h := 15.5        # hours of the day: 6 = sunrise, 12 = noon, 18 = sunset
static var sun_az := -65.0       # the sun's yaw: -50 = on the front-left (shadows fall to the right and back)
static var sun_size := 1.2       # degrees: the penumbra
static var exposure := 0.75
static var haze := 1.0           # 0 = clear, 1 = the default aerial haze, 2 = misty
static var haze_m := 800.0       # the distance at which the haze at haze 1 has taken 63 % of the colour
static var clouds := 0.40        # 0 clear .. 1 overcast
static var gi_mode := "off"    # what the measurement chose (tests/s232_test.gd prints the numbers); "off" | "ssil" | "sdfgi"
static var ground := true        # a far ground plane that the haze fades into the horizon
static var tier_override := ""   # "" = Quality's tier
static var sun_mult := 1.0       # 0 = the sun off (a test control: only the sky lights the scene)
static var sun_gain := 2.8       # item 235: multiplies the sun's energy (the sun / sky balance: more = deeper shadows against the lit side)
static var ambient := 0.8        # item 235: the sky's ambient fill energy (less = darker shadow side)
static var contrast := 1.04      # item 235: the picture's contrast (adjustment)
static var saturation := 1.2     # item 235: the picture's saturation (adjustment)
static var mountains := false     # item 236: a backdrop of distant blue-grey hills behind the scene (two hazy layers about 650 m away, -Z side)
static var tweak := {}            # a test's own Environment overrides, applied after the table (tuning only)
static var final_size := Vector2i(1920, 1080)

static var _saved := {}
static var _ground_node: MeshInstance3D = null
static var _mount_node: Node3D = null
static var last := {}            # what the last apply set (the test reads it)
static var scene_size := 8.0     # metres of what is shown (for the radii)
static var scene_box := AABB()

const ENV_KEYS := ["background_mode", "sky", "ambient_light_source", "ambient_light_energy", "ambient_light_sky_contribution", "ambient_light_color",
	"reflected_light_source", "tonemap_mode", "tonemap_exposure", "tonemap_white", "ssao_enabled", "ssao_radius", "ssao_intensity", "ssao_power",
	"ssao_detail", "ssao_horizon", "ssao_sharpness", "ssao_light_affect", "ssao_ao_channel_affect", "ssil_enabled", "ssil_radius", "ssil_intensity",
	"ssil_sharpness", "ssil_normal_rejection", "ssr_enabled", "glow_enabled", "glow_intensity", "glow_strength", "glow_bloom", "glow_hdr_threshold",
	"adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation", "adjustment_color_correction", "fog_enabled", "fog_mode",
	"fog_light_color", "fog_light_energy", "fog_density", "fog_sky_affect", "fog_aerial_perspective", "sdfgi_enabled", "sdfgi_use_occlusion", "sdfgi_cascades",
	"sdfgi_min_cell_size", "sdfgi_y_scale", "sdfgi_energy", "sdfgi_read_sky_light", "sdfgi_bounce_feedback", "sdfgi_normal_bias", "sdfgi_probe_bias"]
const LIGHT_KEYS := ["rotation_degrees", "light_energy", "light_color", "light_angular_distance", "light_specular", "shadow_enabled", "shadow_bias",
	"shadow_normal_bias", "shadow_blur", "directional_shadow_mode", "directional_shadow_max_distance", "directional_shadow_split_1",
	"directional_shadow_split_2", "directional_shadow_split_3", "directional_shadow_fade_start", "directional_shadow_blend_splits", "sky_mode"]


static func tier_name() -> String:
	var t := tier_override if tier_override != "" else String(Quality.applied.get("tier", "high"))
	return t if TIER.has(t) else "high"


static func forward_plus() -> bool:
	return Quality.current_renderer() == "forward_plus"


## the gi mode this tier and renderer can run (sdfgi and ssil need Forward+ and the high tier; ssao the medium)
static func gi_for(want: String) -> String:
	var t: Dictionary = TIER[tier_name()]
	if not forward_plus() or not bool(t["gi"]):
		return "off"
	if want == "sdfgi" or want == "ssil":
		return want
	return "off"


## ---------------------------------------------------------------- the sun from the time of day
static func sun_elevation(h: float) -> float:
	return clampf(68.0 * sin(PI * (h - 6.0) / 12.0), 2.0, 68.0)


## warm when low (a dawn / dusk orange), nearly white high
static func sun_color(elev: float) -> Color:
	var k := smoothstep(2.0, 50.0, elev)
	return Color(1.0, 0.58, 0.32).lerp(Color(1.0, 0.96, 0.90), k)


static func sun_energy(elev: float) -> float:
	return lerpf(2.4, 3.4, smoothstep(2.0, 40.0, elev))


static func sun_dir_world(elev: float, az: float) -> Vector3:
	# the direction the light TRAVELS is -basis.z of rotation (-elev, az, 0); the sun sits the other way
	var b := Basis.from_euler(Vector3(deg_to_rad(-elev), deg_to_rad(az), 0.0))
	return b.z


static var _cloud_tex: ImageTexture = null


static func cloud_texture() -> ImageTexture:
	if _cloud_tex == null:
		var nz := FastNoiseLite.new()
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = 0.012
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
		nz.fractal_octaves = 4
		nz.seed = 232
		_cloud_tex = ImageTexture.create_from_image(nz.get_seamless_image(512, 512, false, false, 0.1, true))
	return _cloud_tex


static func make_sky(elev: float, az: float) -> Sky:
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var mt := ShaderMaterial.new()
	mt.shader = sh
	var k := smoothstep(2.0, 40.0, elev)   # the low sun warms the horizon and dims the blue
	var sc := sun_color(elev)
	mt.set_shader_parameter("top_color", Color(0.16, 0.48, 0.95).lerp(Color(0.10, 0.28, 0.66), 1.0 - k))
	mt.set_shader_parameter("horizon_color", Color(0.74, 0.89, 1.0).lerp(Color(0.95, 0.72, 0.55), (1.0 - k) * 0.7))
	mt.set_shader_parameter("ground_color", Color(0.52, 0.56, 0.50))
	mt.set_shader_parameter("sun_dir", sun_dir_world(elev, az))
	mt.set_shader_parameter("sun_color", sc)
	mt.set_shader_parameter("sun_cos", cos(deg_to_rad(maxf(sun_size, 0.5) * 0.5 + 0.35)))
	mt.set_shader_parameter("cover", clouds)
	mt.set_shader_parameter("cloud_tex", cloud_texture())
	var s := Sky.new()
	s.sky_material = mt
	s.radiance_size = Sky.RADIANCE_SIZE_256
	s.process_mode = Sky.PROCESS_MODE_QUALITY
	return s


## ---------------------------------------------------------------- the property tables (name -> value)
static func env_props(size: float, mode: String) -> Dictionary:
	var elev := sun_elevation(time_h)
	var t: Dictionary = TIER[tier_name()]
	var fp := forward_plus()
	var gm := gi_for(mode)
	var s := maxf(size, 0.5)
	var hz := Color(0.80, 0.88, 0.96).lerp(Color(0.95, 0.76, 0.60), (1.0 - smoothstep(2.0, 40.0, elev)) * 0.6)
	var d := {
		"background_mode": Environment.BG_SKY,
		"sky": make_sky(elev, sun_az),
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"ambient_light_energy": ambient,
		"ambient_light_sky_contribution": 1.0,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY,
		"tonemap_mode": Environment.TONE_MAPPER_AGX,
		"tonemap_exposure": exposure,
		"tonemap_white": 6.0,
		"ssao_enabled": fp and bool(t["ssao"]),
		"ssao_radius": clampf(s * 0.03, 0.6, 3.0),
		"ssao_intensity": 1.2,
		"ssao_power": 1.5,
		"ssao_detail": 0.5,
		"ssao_horizon": 0.06,
		"ssao_sharpness": 0.9,
		"ssao_light_affect": 0.25,
		"ssao_ao_channel_affect": 0.0,
		"ssil_enabled": fp and bool(t["ssil"]) and gm == "ssil",
		"ssil_radius": clampf(s * 0.08, 2.0, 12.0),
		"ssil_intensity": 1.6,
		"ssil_sharpness": 0.98,
		"ssil_normal_rejection": 1.0,
		"ssr_enabled": false,
		"glow_enabled": true,
		"glow_intensity": 0.4,
		"glow_strength": 0.9,
		"glow_bloom": 0.03,
		"glow_hdr_threshold": 1.2,
		"adjustment_enabled": true,
		"adjustment_brightness": 1.0,
		"adjustment_contrast": contrast,
		"adjustment_saturation": saturation,
		"fog_enabled": haze > 0.001,
		"fog_mode": Environment.FOG_MODE_EXPONENTIAL,
		"fog_light_color": hz,
		"fog_light_energy": 1.0,
		"fog_density": haze / maxf(haze_m, 1.0),
		"fog_sky_affect": 0.0,
		"fog_aerial_perspective": 0.0,
		"sdfgi_enabled": fp and gm == "sdfgi",
		"sdfgi_use_occlusion": true,
		"sdfgi_cascades": 4,
		"sdfgi_min_cell_size": clampf(s / 220.0, 0.15, 1.0),
		"sdfgi_y_scale": Environment.SDFGI_Y_SCALE_75_PERCENT,
		"sdfgi_energy": 0.5,   # item 235: the bounce is scaled down with the deeper sun-to-shade contrast (at 1.0 it lifted the shadow side 4-9 %)
		"sdfgi_read_sky_light": true,
		"sdfgi_bounce_feedback": 0.6,
		"sdfgi_normal_bias": 1.1,
		"sdfgi_probe_bias": 1.1,
	}
	return d


static func far_of(cam_pos: Vector3, box: AABB) -> float:
	var f := 1.0
	for i in 8:
		f = maxf(f, cam_pos.distance_to(box.get_endpoint(i)))
	return f


static func sun_props(cam_pos: Vector3, box: AABB) -> Dictionary:
	var elev := sun_elevation(time_h)
	var t: Dictionary = TIER[tier_name()]
	var s := maxf(box.size.length(), 0.5)
	var maxd := minf(far_of(cam_pos, box) * 1.15, 600.0) if box.size.length() > 0.01 else s * 2.0
	return {
		"rotation_degrees": Vector3(-elev, sun_az, 0.0),
		"light_energy": sun_energy(elev) * sun_mult * sun_gain,
		"light_color": sun_color(elev),
		"light_angular_distance": sun_size,
		"light_specular": 1.0,
		"shadow_enabled": true,
		"shadow_bias": minf(0.004 * s, 0.03),
		"shadow_normal_bias": 1.5,
		"shadow_blur": 1.0,
		"directional_shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(t["splits"]) == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"directional_shadow_max_distance": maxd,
		"directional_shadow_split_1": 0.08,
		"directional_shadow_split_2": 0.22,
		"directional_shadow_split_3": 0.50,
		"directional_shadow_fade_start": 0.9,
		"directional_shadow_blend_splits": true,
		"sky_mode": DirectionalLight3D.SKY_MODE_LIGHT_ONLY,
	}


static func quiet_light(L: DirectionalLight3D) -> void:
	L.light_energy = 0.0
	L.shadow_enabled = false


## item 236: the distant mountains: two layers of a hill silhouette (a strip of triangles along an arc, heights from seeded noise) at `r` metres, behind -Z.
## Returns a Node3D named "temple_mountains" whose children are the layers; its meshes' heights are the numbers the test reads.
static func make_mountains(r: float, centre: Vector3, y0: float) -> Node3D:
	var root := Node3D.new()
	root.name = "temple_mountains"
	var layers := [{"r": r, "h": 200.0, "col": Color(0.30, 0.42, 0.62), "seed": 11, "freq": 0.9}, {"r": r * 0.82, "h": 120.0, "col": Color(0.25, 0.37, 0.54), "seed": 23, "freq": 1.3}]
	for L in layers:
		var nz := FastNoiseLite.new()
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.seed = int(L["seed"])
		nz.frequency = float(L["freq"])
		var n := 160
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		var rr: float = L["r"]
		for i in n + 1:
			var f := float(i) / float(n)
			var th := deg_to_rad(lerpf(-85.0, 85.0, f))
			var x := sin(th) * rr
			var z := -cos(th) * rr
			var e := 0.5 + 0.5 * nz.get_noise_1d(f * 6.0)
			var hgt: float = float(L["h"]) * (0.18 + 0.82 * e * e) * (0.55 + 0.45 * cos(th * 1.5))
			verts.append(Vector3(x, y0 - 6.0, z))
			verts.append(Vector3(x, y0 + hgt, z))
			var nn := Vector3(-sin(th), 0.15, cos(th)).normalized()
			norms.append(nn)
			norms.append(nn)
		for i in n:
			var a := i * 2
			idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mt := StandardMaterial3D.new()
		mt.albedo_color = L["col"]
		mt.roughness = 1.0
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = mt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.name = "mountain_layer"
		root.add_child(mi)
	root.position = Vector3(centre.x, 0.0, centre.z)
	return root


static func make_ground(y: float, size: float, centre: Vector3) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(maxf(size, 1.0) * 60.0, maxf(size, 1.0) * 60.0)
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var mt := ShaderMaterial.new()
	mt.shader = sh
	mt.set_shader_parameter("tile", clampf(size * 0.06, 1.0, 12.0))
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mt
	mi.position = Vector3(centre.x, y, centre.z)
	mi.name = "temple_ground"
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED   # the distant plane stays out of the GI volume
	return mi


## the bounds of what the live view shows: the part on screen (Part.replay aabb), else a default stage
static func shown_box(m: Node) -> AABB:
	if m.get("bld") != null and m.bld.part != null and m.bld.part.get("res") is Dictionary:
		var r: Dictionary = m.bld.part.res
		if r.get("aabb") is AABB and (r["aabb"] as AABB).size.length() > 0.01:
			return r["aabb"]
	return AABB(Vector3(-2, 0, -2), Vector3(4, 2, 4))


static func is_outdoor(box: AABB) -> bool:
	return box.size.length() >= OUTDOOR_MIN


## the global shadow settings of a tier (atlas size and soft filter)
static func set_shadows(tier: String) -> void:
	var t: Dictionary = TIER[tier]
	RenderingServer.directional_shadow_atlas_set_size(int(t["atlas"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(t["filter"]) as RenderingServer.ShadowQuality)


static func _snap(o: Object, keys: Array) -> Dictionary:
	var d := {}
	for k in keys:
		d[k] = o.get(k)
	return d


static func _put(o: Object, props: Dictionary) -> void:
	for k in props:
		o.set(k, props[k])


## the light of a camera position: (re)apply to main's own environment and lights (used by set_live, and again when a knob changes)
static func apply(m: Node, cam_pos := Vector3.INF) -> void:
	var box := shown_box(m)
	scene_box = box
	scene_size = maxf(box.size.length(), 8.0)
	var cp: Vector3 = cam_pos if cam_pos.is_finite() else (m.cam.global_position if m.cam != null else Vector3(0, 5, 50))
	var e: Environment = m.world_env
	var ep := env_props(scene_size, gi_mode)
	_put(e, ep)
	_put(e, tweak)
	var sp := sun_props(cp, box)
	_put(m.light_key, sp)
	quiet_light(m.light_fill)
	quiet_light(m.light_rim)
	set_shadows(tier_name())
	if ground:
		if _ground_node == null or not is_instance_valid(_ground_node):
			_ground_node = make_ground(box.position.y - 0.003 * scene_size, scene_size, box.get_center())
			m.add_child(_ground_node)
		else:
			_ground_node.position = Vector3(box.get_center().x, box.position.y - 0.003 * scene_size, box.get_center().z)
	if on and mountains:
		if _mount_node == null or not is_instance_valid(_mount_node):
			_mount_node = make_mountains(650.0, box.get_center(), box.position.y - 0.003 * scene_size)
			m.add_child(_mount_node)
	elif _mount_node != null:
		if is_instance_valid(_mount_node):
			_mount_node.free()
		_mount_node = null
	last = {"env": ep, "sun": sp, "tier": tier_name(), "gi": gi_for(gi_mode), "elev": sun_elevation(time_h), "box": box}


## VIEW > Temple light on / off. Off puts back every value it took. Returns a line in words.
static func set_live(m: Node, want: bool) -> String:
	if want == on:
		return "Temple light is already " + ("on" if on else "off")
	if want:
		if Realistic.live_on:
			Realistic.set_live(m, false)
		_saved = {"env": _snap(m.world_env, ENV_KEYS), "lights": [], "atlas": int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)),
			"cam_far": m.cam.far if m.cam != null else 100.0}
		for L in [m.light_key, m.light_fill, m.light_rim]:
			_saved["lights"].append([L, _snap(L, LIGHT_KEYS)])
		on = true
		apply(m)
		if m.cam != null:
			m.cam.far = maxf(m.cam.far, 2500.0)   # the far ground has to reach the haze
		return "Temple light on (%s tier, GI %s): sky with clouds, sun at %.0f h, soft shadows, haze. View > Temple light turns it off" % [tier_name(), last["gi"], time_h]
	_put(m.world_env, _saved["env"])
	for row in _saved["lights"]:
		_put(row[0], row[1])
	var tr := String(Quality.applied.get("tier", "high"))
	var p := Quality.preset(tr)
	RenderingServer.directional_shadow_atlas_set_size(int(p["dir_shadow"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p["dir_filter"]) as RenderingServer.ShadowQuality)
	if m.cam != null:
		m.cam.far = float(_saved["cam_far"])
	if _ground_node != null and is_instance_valid(_ground_node):
		_ground_node.queue_free()
	_ground_node = null
	if _mount_node != null and is_instance_valid(_mount_node):
		_mount_node.free()
	_mount_node = null
	on = false
	_saved = {}
	return "Temple light off: the fast look is back"


## a knob changed while it is on: apply again
static func refresh(m: Node) -> void:
	if on:
		apply(m)


## ---------------------------------------------------------------- CAMERA BY NUMBERS
static func get_camera(m: Node) -> Dictionary:
	var c: Camera3D = m.cam
	var fwd := -c.global_transform.basis.z
	return {"pos": c.global_position, "target": c.global_position + fwd * maxf(float(m.dist), 1.0), "fov": c.fov, "near": c.near, "far": c.far}


## put main's orbit camera at pos looking at tgt with a vertical field of view of fov degrees. No roll (the orbit camera has none)
static func set_camera(m: Node, pos: Vector3, tgt: Vector3, fov := 45.0, near := -1.0, far := -1.0) -> Dictionary:
	var d := pos - tgt
	var L := d.length()
	if L < 0.001:
		return {"ok": false, "error": "the camera and its target are the same point"}
	m.target = tgt
	m.dist = L
	m.pitch = rad_to_deg(-asin(clampf(d.y / L, -1.0, 1.0)))
	m.yaw = rad_to_deg(atan2(d.x, d.z))
	m._cam()
	var b := Basis.from_euler(Vector3(deg_to_rad(m.pitch), deg_to_rad(m.yaw), 0.0))
	m.cam.transform = Transform3D(b, tgt + b * Vector3(0, 0, L))
	m.cam.fov = clampf(fov, 5.0, 120.0)
	if near > 0.0:
		m.cam.near = near
	if far > 0.0:
		m.cam.far = far
	refresh(m)
	return {"ok": true, "pos": m.cam.global_position, "target": tgt, "fov": m.cam.fov, "pitch": m.pitch, "yaw": m.yaw, "dist": L}


## FRAME TO A WIDTH (item 235): the camera that shows a front face `face` (Rect2: x, y = left and bottom in metres, size = width, height) at pct of the
## picture width, looking straight on from (cx, cam_y) at (cx, tgt_y), the face at z = face_z. Pure numbers: distance = width * f / (pct * size), f = (size/2) / tan(fov/2)
static func frame_width(_m: Node, face: Rect2, pct: float, fov := 45.0, cam_y := 4.5, tgt_y := 6.3, size := 1024.0, face_z := 0.0) -> Dictionary:
	var f := (size * 0.5) / tan(deg_to_rad(fov) * 0.5)
	var d := face.size.x * f / (maxf(pct, 0.05) * size)
	var cx := face.position.x + face.size.x * 0.5
	return {"pos": Vector3(cx, cam_y, face_z + d), "target": Vector3(cx, tgt_y, face_z), "fov": fov, "dist": d}


## ---------------------------------------------------------------- FINAL SHOT
## The current camera (or spec {pos, target, fov}) as a PNG with no UI at all: a SubViewport of its own that shares the live world. It draws
## only the 3D world (a SubViewport has no canvas of main's), at full quality (4x MSAA, scale 1.0, whatever Fast view is). The temple light
## is on for it; if it was off it is switched on for the shot and put back. Returns {ok, path, w, h, ms, text}.
static func final_shot(m: Node, path: String, size := Vector2i.ZERO, spec := {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var sz: Vector2i = size if size != Vector2i.ZERO else final_size
	if sz.x < 16 or sz.y < 16 or sz.x > 8192 or sz.y > 8192:
		return {"ok": false, "text": "NOT DONE: the size must be between 16 and 8192 pixels each way"}
	var was_on := on
	if not on:
		set_live(m, true)
	var c: Camera3D = m.cam
	var xf: Transform3D = c.global_transform
	var fov := c.fov
	if spec.has("pos") and spec.has("target"):
		var pos: Vector3 = spec["pos"]
		var tg: Vector3 = spec["target"]
		xf = Transform3D(Basis.looking_at((tg - pos).normalized(), Vector3.UP), pos)
		fov = float(spec.get("fov", fov))
	var vp := SubViewport.new()
	vp.size = sz
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_debanding = true
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.transform = xf
	cam.fov = fov
	cam.near = c.near
	cam.far = maxf(c.far, 2500.0)
	vp.add_child(cam)
	m.add_child(vp)
	cam.current = true
	apply(m, xf.origin)   # the shadow cascades fit THIS camera
	for i in 10:   # SDFGI and the soft shadow filter settle over a few frames
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	m.remove_child(vp)
	vp.queue_free()
	if not was_on:
		set_live(m, false)
	else:
		apply(m)
	if img == null or img.is_empty():
		return {"ok": false, "text": "NOT DONE: the picture could not be drawn"}
	img.convert(Image.FORMAT_RGB8)
	var gp := ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
	DirAccess.make_dir_recursive_absolute(gp.get_base_dir())
	if img.save_png(gp) != OK:
		return {"ok": false, "text": "NOT DONE: the picture could not be saved at " + gp}
	return {"ok": true, "path": gp, "w": img.get_width(), "h": img.get_height(), "ms": Time.get_ticks_msec() - t0, "image": img,
		"text": "Final shot saved: %s (%d x %d, no interface)" % [gp, img.get_width(), img.get_height()]}


## ---------------------------------------------------------------- agent_tools: temple_light / final_shot
static func settings_dict() -> Dictionary:
	return {"on": on, "time": time_h, "sun_az": sun_az, "sun_size": sun_size, "exposure": exposure, "haze": haze, "clouds": clouds, "gi": gi_mode, "mountains": mountains,
		"tier": tier_name(), "sun_elevation": snappedf(sun_elevation(time_h), 0.1)}


static func set_from(p: Dictionary) -> void:
	time_h = clampf(float(p.get("time", time_h)), 5.0, 19.0)
	sun_az = float(p.get("sun_az", sun_az))
	sun_size = clampf(float(p.get("sun_size", sun_size)), 0.0, 6.0)
	exposure = clampf(float(p.get("exposure", exposure)), 0.2, 4.0)
	haze = clampf(float(p.get("haze", haze)), 0.0, 4.0)
	clouds = clampf(float(p.get("clouds", clouds)), 0.0, 1.0)
	if p.has("gi") and GI_MODES.has(String(p["gi"])):
		gi_mode = String(p["gi"])
	if p.has("ground"):
		ground = bool(p["ground"])
	if p.has("mountains"):
		mountains = bool(p["mountains"])


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.INF


## {on?, time, sun_az, sun_size, exposure, haze, clouds, gi, ground, camera:{pos:[x,y,z], target:[x,y,z], fov}} -> the settings now (and the camera)
static func serve(m: Node, p: Dictionary) -> Dictionary:
	set_from(p)
	var msg := ""
	if p.has("on"):
		msg = set_live(m, bool(p["on"]))
	else:
		refresh(m)
	var out := {"ok": true, "settings": settings_dict(), "text": msg}
	if p.get("camera") is Dictionary:
		var cp: Dictionary = p["camera"]
		var pos := _v3(cp.get("pos"))
		var tg := _v3(cp.get("target"))
		if not pos.is_finite() or not tg.is_finite():
			return {"ok": false, "error": "camera needs {\"pos\": [x, y, z], \"target\": [x, y, z], \"fov\": 45} in metres"}
		var r := set_camera(m, pos, tg, float(cp.get("fov", 45.0)), float(cp.get("near", -1.0)), float(cp.get("far", -1.0)))
		if not bool(r["ok"]):
			return {"ok": false, "error": String(r["error"])}
		out["camera"] = {"pos": [pos.x, pos.y, pos.z], "target": [tg.x, tg.y, tg.z], "fov": float(r["fov"])}
	elif p.has("get_camera"):
		var g := get_camera(m)
		out["camera"] = {"pos": [g["pos"].x, g["pos"].y, g["pos"].z], "target": [g["target"].x, g["target"].y, g["target"].z], "fov": g["fov"]}
	return out


## {out, w, h, camera?} -> the PNG written (awaits)
static func serve_final(m: Node, p: Dictionary) -> Dictionary:
	var out := String(p.get("out", "user://final_shot.png"))
	var sz := Vector2i(int(p.get("w", 1920)), int(p.get("h", 1080)))
	var spec := {}
	if p.get("camera") is Dictionary:
		var cp: Dictionary = p["camera"]
		var pos := _v3(cp.get("pos"))
		var tg := _v3(cp.get("target"))
		if pos.is_finite() and tg.is_finite():
			spec = {"pos": pos, "target": tg, "fov": float(cp.get("fov", 45.0))}
	set_from(p)
	var r: Dictionary = await final_shot(m, out, sz, spec)
	r.erase("image")
	return r
