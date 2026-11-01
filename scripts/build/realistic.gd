class_name Realistic
extends RefCounted
## REALISM IN THE RENDER (Friday plan 224). The light and the picture, one place, two users: the Nice picture's REAL-LOOK preset
## (NiceRender.look = "real") and the live view's optional "Realistic" toggle (VIEW > Realistic, default OFF: the fast look stays).
##   OUTDOOR (a building: size >= OUTDOOR_MIN metres): a procedural physical sky with a sun disc, a sun that matches it (the same
##     direction lights the ground and the sky's ambient and reflections), a ground and a haze that fades it into the horizon.
##   STUDIO (a part): the 3 lights (key with a soft shadow, fill, rim) on a soft gradient sky, a glossy floor that fades into the
##     background by depth fog (no floor edge), real shadows and real reflections of the part in the floor.
## Both: AgX tone map with an exposure, SSAO + SSIL, SSR for glossy surfaces, soft sun shadows (a sun angular size = PCSS-style
## penumbra) with 4 cascades fitted to the size of what is shown, a slight bloom, a NEUTRAL colour-grading LUT (identity).
## Everything is a table of property -> value (env_props / sun_props), so the live toggle can snapshot exactly what it changes and put
## every one of them back (off = the view it was, bit for bit). Radii and distances scale with `size` (the metres of what is shown).

const OUTDOOR_MIN := 2.0   # metres: what is shown at least this big is a building (outdoor), smaller is a part (studio)
const ATLAS := 8192   # the directional shadow atlas for the Nice picture (a bigger map = smaller texels = a smoother shadow edge)
const SUN_ELEVATION := 46.0
const SUN_AZIMUTH := -30.0   # the sun's yaw: it stands on the left of the 3/4 camera (so the shadows fall to the right, in view)

static var _saved := {}   # the live toggle's snapshot: {"env": {prop: value}, "lights": [[node, {prop: value}]], "shadow_q": int, "msaa": int}
static var live_on := false


static func kind_for(size_m: float) -> String:
	return "outdoor" if size_m >= OUTDOOR_MIN else "studio"


## the sky of a kind: a procedural physical sky (outdoor: blue, a sun disc) or a soft grey-blue gradient (studio: no disc)
static func make_sky(kind: String) -> Sky:
	var pm := ProceduralSkyMaterial.new()
	if kind == "outdoor":
		pm.sky_top_color = Color(0.16, 0.36, 0.76)
		pm.sky_horizon_color = Color(0.62, 0.76, 0.92)
		pm.sky_curve = 0.18
		pm.ground_horizon_color = Color(0.62, 0.74, 0.88)
		pm.ground_bottom_color = Color(0.36, 0.40, 0.44)
		pm.ground_curve = 0.05
		pm.sun_angle_max = 28.0
		pm.sun_curve = 0.1
		pm.sky_energy_multiplier = 1.0
	else:
		pm.sky_top_color = Color(1.0, 1.0, 1.0)
		pm.sky_horizon_color = Color(0.82, 0.86, 0.92)
		pm.sky_curve = 0.25
		pm.ground_horizon_color = Color(0.55, 0.57, 0.61)
		pm.ground_bottom_color = Color(0.22, 0.23, 0.26)
		pm.ground_curve = 0.1
		pm.sun_angle_max = 0.0
		pm.sky_energy_multiplier = 1.0
	pm.use_debanding = true
	var sk := Sky.new()
	sk.sky_material = pm
	sk.radiance_size = Sky.RADIANCE_SIZE_256
	return sk


## the neutral colour grade: a ramp black to white is the identity LUT (the grade is wired in, ready for a real look-up table)
static func neutral_lut() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color.BLACK)
	g.set_color(1, Color.WHITE)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


## every Environment property the Realistic look sets (name -> value) for a kind and a size (metres of what is shown)
static func env_props(kind: String, size: float, ov := {}) -> Dictionary:
	var s := maxf(size, 0.02)
	var outdoor := kind == "outdoor"
	var d := {
		"background_mode": Environment.BG_SKY,
		"sky": make_sky(kind),
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"ambient_light_energy": 0.9 if outdoor else 0.45,
		"ambient_light_sky_contribution": 1.0,
		"reflected_light_source": Environment.REFLECTION_SOURCE_SKY if bool(ov.get("reflect", true)) else Environment.REFLECTION_SOURCE_DISABLED,
		"tonemap_mode": Environment.TONE_MAPPER_AGX,
		"tonemap_exposure": 1.0,
		"tonemap_white": 6.0,
		"ssao_enabled": bool(ov.get("ssao", true)),
		"ssao_radius": s * 0.18,
		"ssao_intensity": 2.2,
		"ssao_power": 1.6,
		"ssao_detail": 0.5,
		"ssao_horizon": 0.06,
		"ssao_sharpness": 0.9,
		"ssao_light_affect": 0.3,
		"ssao_ao_channel_affect": 0.0,
		"ssil_enabled": bool(ov.get("ssil", true)),
		"ssil_radius": s * 0.4,
		"ssil_intensity": 1.0,
		"ssil_sharpness": 0.98,
		"ssil_normal_rejection": 1.0,
		"ssr_enabled": bool(ov.get("ssr", true)),
		"ssr_max_steps": 64,
		"ssr_fade_in": 0.15,
		"ssr_fade_out": 2.0,
		"ssr_depth_tolerance": s * 0.02,
		"glow_enabled": true,
		"glow_intensity": 0.5,
		"glow_strength": 0.9,
		"glow_bloom": 0.04,
		"glow_hdr_threshold": 1.1,
		"adjustment_enabled": true,
		"adjustment_brightness": 1.0,
		"adjustment_contrast": 1.0,
		"adjustment_saturation": 1.0,
		"adjustment_color_correction": neutral_lut(),
		"fog_enabled": true,
		"fog_mode": Environment.FOG_MODE_EXPONENTIAL,
		"fog_light_color": Color(0.62, 0.76, 0.92) if outdoor else Color(0.82, 0.86, 0.92),
		"fog_density": 0.45 / (s * (14.0 if outdoor else 9.0)),
		"fog_sky_affect": 0.0,
		"sdfgi_enabled": bool(ov.get("sdfgi", false)) and outdoor,
	}
	return d


## every DirectionalLight3D property of the sun (key) for a kind and a size
static func sun_props(kind: String, size: float, ov := {}) -> Dictionary:
	var s := maxf(size, 0.02)
	var outdoor := kind == "outdoor"
	return {
		"rotation_degrees": Vector3(-SUN_ELEVATION, SUN_AZIMUTH, 0.0),
		"light_energy": float(ov.get("sun", 2.6 if outdoor else 3.2)),
		"light_color": Color(1.0, 0.96, 0.88) if outdoor else Color(1.0, 0.97, 0.92),
		"light_angular_distance": float(ov.get("angular", 1.8)),   # the sun's size in degrees: the penumbra (PCSS-style, with the soft filter on)
		"light_specular": 1.0,
		"shadow_enabled": bool(ov.get("shadow", true)),
		"shadow_bias": float(ov.get("bias", minf(0.004 * s, 0.02))),   # scales with what is shown (a fixed bias floats a small part off its floor)
		"shadow_normal_bias": float(ov.get("nbias", 1.5)),
		"shadow_blur": float(ov.get("blur", 1.0)),
		"directional_shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"directional_shadow_max_distance": s * float(ov.get("maxd", 2.0 if outdoor else 6.0)),   # the cascades are fitted to what is shown, not the world
		"directional_shadow_split_1": 0.06,
		"directional_shadow_split_2": 0.18,
		"directional_shadow_split_3": 0.45,
		"directional_shadow_fade_start": 0.85,
		"directional_shadow_blend_splits": true,
		"sky_mode": DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if outdoor else DirectionalLight3D.SKY_MODE_LIGHT_ONLY,
	}


static func apply_props(o: Object, props: Dictionary) -> void:
	for k in props:
		o.set(k, props[k])


static func snapshot_props(o: Object, names: Array) -> Dictionary:
	var out := {}
	for k in names:
		out[k] = o.get(k)
	return out


static func set_soft_shadows(on: bool, level := RenderingServer.SHADOW_QUALITY_SOFT_HIGH) -> void:
	RenderingServer.directional_soft_shadow_filter_set_quality(level if on else RenderingServer.SHADOW_QUALITY_SOFT_LOW)


## the fill and the rim: no shadows, soft, from the other side (studio) / the sky fills it all (outdoor: a faint bounce from the ground side)
static func fill_props(kind: String) -> Dictionary:
	return {"rotation_degrees": Vector3(-20.0, 130.0, 0.0), "light_energy": 0.35 if kind == "studio" else 0.25, "light_color": Color(0.86, 0.92, 1.0),
		"shadow_enabled": false, "light_angular_distance": 0.0, "light_specular": 0.0, "sky_mode": DirectionalLight3D.SKY_MODE_LIGHT_ONLY}


static func rim_props(kind: String) -> Dictionary:
	return {"rotation_degrees": Vector3(-25.0, 200.0, 0.0), "light_energy": 0.9 if kind == "studio" else 0.0, "light_color": Color(1, 1, 1),
		"shadow_enabled": false, "light_angular_distance": 0.0, "light_specular": 0.0, "sky_mode": DirectionalLight3D.SKY_MODE_LIGHT_ONLY}


## the ground a building stands on (outdoor) or the glossy studio floor: a big plane at y that the fog fades out. Grass has a quiet noise
## so it is not one flat colour; the studio floor is a pale glossy plastic (SSR shows the part in it)
static func ground(kind: String, y: float, size: float, centre: Vector3) -> MeshInstance3D:
	var s := maxf(size, 0.02)
	var pm := PlaneMesh.new()
	pm.size = Vector2(s * 80.0, s * 80.0)
	var mt := StandardMaterial3D.new()
	if kind == "outdoor":
		var nz := FastNoiseLite.new()
		nz.frequency = 0.02
		nz.fractal_octaves = 3
		var tex := NoiseTexture2D.new()
		tex.noise = nz
		tex.width = 512
		tex.height = 512
		tex.seamless = true
		var gr := Gradient.new()
		gr.set_color(0, Color(0.30, 0.42, 0.20))
		gr.set_color(1, Color(0.46, 0.55, 0.28))
		tex.color_ramp = gr
		mt.albedo_texture = tex
		mt.uv1_scale = Vector3(8.0, 8.0, 1.0)
		mt.roughness = 0.9
		mt.metallic_specular = 0.2
	else:
		mt.albedo_color = Color(0.62, 0.64, 0.68)
		mt.roughness = 0.4
		mt.metallic = 0.0
		mt.metallic_specular = 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mt
	mi.position = Vector3(centre.x, y, centre.z)
	mi.name = "realistic_ground"
	return mi


## ---------------------------------------------------------------- the LIVE view

static var _env_names: Array = []
static var _sun_names: Array = []


static func _names() -> void:
	if _env_names.is_empty():
		_env_names = env_props("studio", 1.0).keys()
		_sun_names = sun_props("studio", 1.0).keys()


## the kind the live view shows now: the BUILD page with a house is outdoor, everything else (a part, the body) is studio
static func live_kind(m: Node) -> String:
	if m.get("bld") != null and bool(m.bld.on) and not (m.bld.part != null and bool(m.bld.part.on)):
		return "outdoor"
	return "studio"


## switch the live view's Realistic look on or off on main's own environment and three lights. Off puts back every value it took.
## Returns a line in words (what is on, or what was put back). The stage's grid, floor and bodies are not touched.
static func set_live(m: Node, on: bool) -> String:
	_names()
	if on == live_on:
		return "Realistic view is already " + ("on" if on else "off")
	var e: Environment = m.world_env
	var lights: Array = [m.light_key, m.light_fill, m.light_rim]
	if on:
		var kind := live_kind(m)
		var size := 8.0 if kind == "outdoor" else 1.0   # the live view's stage is about a body big (the floor is 4 m); a house is metres
		_saved = {"env": snapshot_props(e, _env_names), "lights": [], "shadow_q": 0, "msaa": 0, "kind": kind}
		for L in lights:
			_saved["lights"].append([L, snapshot_props(L, _sun_names)])
		apply_props(e, env_props(kind, size))
		apply_props(lights[0], sun_props(kind, size))
		apply_props(lights[1], fill_props(kind))
		apply_props(lights[2], rim_props(kind))
		set_soft_shadows(true)
		live_on = true
		return "Realistic view on (%s): sky, sun, soft shadows, ambient occlusion, reflections. View > Realistic turns it off" % kind
	apply_props(e, _saved["env"])
	for row in _saved["lights"]:
		apply_props(row[0], row[1])
	set_soft_shadows(false)
	live_on = false
	_saved = {}
	return "Realistic view off: the fast look is back"
