class_name StudioLight
extends RefCounted
## ITEMS 263 / 274 / 275 (GPU film vs Blender: lighting was Kine's only gap). A DARK PRODUCT STUDIO for small parts, built from the part's own size:
##   * key, fill and rim (directions of the Blender GPU film), each with its own specular share (0 = "no shine": the light never mirrors),
##     and LIGHT LINKING: a light can ignore the floor (cull mask without FLOOR_LAYER; the floor lives on that one layer only)
##   * a dark gradient backdrop (a sky), a dark floor with the specular term OFF (no sun disc mirrored on a glossy floor)
##   * an optional reflective floor: a planar mirror of the product (its colours AND its glow, fading with depth), added to the floor
##   * bloom set like Blender's compositor glow: HDR threshold above lit metal (edges of lit metal stay quiet), emission above it blooms wide
## It is used only when NiceRender.look == "studio_dark" (or when a caller asks for it): every other picture is untouched.
## Sizes follow the part: the shadow distance, floor size, SSAO radius and mirror fade are multiples of the part's diagonal.

const FLOOR_LAYER := 1 << 19
const ALL_LAYERS := 0xFFFFF
const SPEC_KEY := 0.4
const SPEC_FILL := 0.4
const SPEC_RIM := 0.3
const BLOOM_THRESHOLD := 1.0     # lit metal edges peak below this (specular is cut), emission (energy 3+) is above it
const BLOOM_INTENSITY := 0.7
const KEY_E := 3.4      # s277: the preset's OWN levels are the ones the Blender-matched film needed (it was key 2.0 fill 0.6 rim 1.1 plus overrides)
const FILL_E := 1.6
const RIM_E := 2.2
## s277 wider, softer bloom: the big mips (levels 3..6) carry most of it; legacy (ov "bloom_legacy") is the s263 spread, kept for the control
const BLOOM_LEVELS := [0.0, 0.8, 1.0, 1.0, 0.9, 0.6, 0.4]
const BLOOM_LEVELS_LEGACY := [0.0, 1.0, 1.0, 0.6, 0.3, 0.15, 0.0]
const MIRROR_STRENGTH := 0.55
const GLOSSY_STRENGTH := 0.21   # s277b: Blender's smear peaks at 0.19 luminance, the 0.42 read 0.39 (2x)
const BAR_K := 1.9   # s277b: the film's RGB bar emission (was 3.0: a green and red cloud)
static var last_view := {}

const SKY := "shader_type sky;
uniform vec3 top : source_color = vec3(0.006, 0.007, 0.01);
uniform vec3 mid : source_color = vec3(0.0015, 0.0017, 0.0025);
uniform vec3 bot : source_color = vec3(0.001, 0.001, 0.0015);
void sky() {
	float y = EYEDIR.y;
	vec3 c = y > 0.0 ? mix(mid, top, smoothstep(0.0, 0.7, y)) : mix(mid, bot, smoothstep(0.0, 0.35, -y));
	COLOR = c;
}"

const FLOOR_SHADER := "shader_type spatial;
render_mode depth_draw_never, specular_disabled;
void fragment() { ALBEDO = vec3(0.012, 0.012, 0.015); ROUGHNESS = 0.3; METALLIC = 0.0; }
"

const MIRROR_SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec3 body = vec3(0.1);
uniform vec3 glow = vec3(0.0);
uniform float glow_k = 0.0;
uniform float floor_y = 0.0;
uniform float fade_h = 0.1;
uniform float strength = 0.55;
varying float depth;
void vertex() { depth = floor_y - (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment() {
	float f = clamp(1.0 - depth / fade_h, 0.0, 1.0);
	ALBEDO = (body * 0.06 + glow * glow_k) * f * f * strength;
	ALPHA = 1.0;
}
"


## the size-scaled numbers of the studio for a part of diagonal `diag` (metres): returned so a test can read them
static func scaled(diag: float) -> Dictionary:
	var d := maxf(diag, 0.02)
	return {"shadow_dist": d * 3.0, "floor_size": d * 40.0, "ssao_radius": d * 0.03, "fade_h": d * 0.45, "bias": d * 0.02}


## a light with its own shine: spec 0 = no specular at all; link_floor false = the light ignores the floor
static func set_light(l: Light3D, spec: float, link_floor := true) -> void:
	l.light_specular = clampf(spec, 0.0, 1.0)
	l.light_cull_mask = ALL_LAYERS if link_floor else (ALL_LAYERS & ~FLOOR_LAYER)


## the floor: dark, specular off (a DirectionalLight never mirrors as a white disc), on the floor layer only (so a linked light can skip it)
static func make_floor(y: float, centre: Vector3, size: float) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	var fm := ShaderMaterial.new()   # dark, no specular, and it does NOT write depth: the planar mirror under it is hidden only by the product, not by the floor
	var fs := Shader.new()
	fs.code = FLOOR_SHADER
	fm.shader = fs
	fm.render_priority = -10   # drawn before the mirror, which then sits on it (the floor writes no depth)
	var fl := MeshInstance3D.new()
	fl.mesh = pm
	fl.material_override = fm
	fl.layers = FLOOR_LAYER
	fl.position = Vector3(centre.x, y, centre.z)
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return fl


## the planar mirror of one product instance: same mesh, flipped across the floor, each surface drawn from its own colour and glow, OPAQUE and depth-written
## (an additive mirror piled 70 fins into white), over the floor, hidden only by the product
static func mirror_of(src: MeshInstance3D, floor_y: float, fade_h: float, strength := MIRROR_STRENGTH) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = MIRROR_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	for s in src.mesh.get_surface_count():
		var mat: Material = src.get_surface_override_material(s)
		if mat == null:
			mat = src.mesh.surface_get_material(s)
		if mat == null:
			mat = src.material_override
		var sm := ShaderMaterial.new()
		sm.shader = sh
		if mat is ShaderMaterial and (mat as ShaderMaterial).has_meta("ring_glow"):
			var rg: Vector3 = (mat as ShaderMaterial).get_meta("ring_glow")
			sm.set_shader_parameter("glow", rg)
			sm.set_shader_parameter("glow_k", float((mat as ShaderMaterial).get_meta("ring_k", 2.0)))
		elif mat is BaseMaterial3D:
			var b := mat as BaseMaterial3D
			sm.set_shader_parameter("body", Vector3(b.albedo_color.r, b.albedo_color.g, b.albedo_color.b))
			if b.emission_enabled:
				sm.set_shader_parameter("glow", Vector3(b.emission.r, b.emission.g, b.emission.b))
				sm.set_shader_parameter("glow_k", b.emission_energy_multiplier)
		sm.set_shader_parameter("floor_y", floor_y)
		sm.set_shader_parameter("fade_h", fade_h)
		sm.set_shader_parameter("strength", strength)
		sm.render_priority = 10
		mi.set_surface_override_material(s, sm)
	mi.transform = Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3(0, 2.0 * floor_y, 0)) * src.transform
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## ITEM 269b: a mirror made by mirror_of copies its source's colours once; for a source whose material CHANGES (film keys) call this each time it changes:
## the mirror takes the source's transform and, per surface, its present body colour and glow
static func sync_mirror(mir: MeshInstance3D, src: MeshInstance3D, floor_y: float) -> void:
	mir.transform = Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3(0, 2.0 * floor_y, 0)) * src.transform
	for s in src.mesh.get_surface_count():
		var mat: Material = src.get_surface_override_material(s)
		if mat == null:
			mat = src.material_override
		var sm := mir.get_surface_override_material(s) as ShaderMaterial
		if sm == null or not (mat is BaseMaterial3D):
			continue
		var b := mat as BaseMaterial3D
		sm.set_shader_parameter("body", Vector3(b.albedo_color.r, b.albedo_color.g, b.albedo_color.b))
		if b.emission_enabled:
			sm.set_shader_parameter("glow", Vector3(b.emission.r, b.emission.g, b.emission.b))
			sm.set_shader_parameter("glow_k", b.emission_energy_multiplier)
		else:
			sm.set_shader_parameter("glow", Vector3.ZERO)
			sm.set_shader_parameter("glow_k", 0.0)


## the studio's environment: the backdrop sky, low ambient, ACES, bloom (the part's emission blooms, lit metal edges do not), SSAO scaled to the part
static func make_env(diag: float, ov := {}) -> Environment:
	var sc := scaled(diag)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY
	sm.shader = sh
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(ov.get("exposure", 1.25))
	env.glow_enabled = bool(ov.get("bloom", true))
	env.glow_intensity = float(ov.get("bloom_intensity", BLOOM_INTENSITY))
	env.glow_bloom = 0.0   # a non-zero bloom adds a share of the whole image: a flat brown haze over the dark backdrop
	env.glow_hdr_threshold = float(ov.get("bloom_threshold", BLOOM_THRESHOLD))
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var lv: Array = BLOOM_LEVELS_LEGACY if bool(ov.get("bloom_legacy", false)) else BLOOM_LEVELS
	for li in 7:
		env.set_glow_level(li, float(lv[li]))
	if not bool(ov.get("bloom_legacy", false)):
		env.glow_intensity = float(ov.get("bloom_intensity", BLOOM_INTENSITY))
	env.ssao_enabled = true
	env.ssao_radius = float(sc["ssao_radius"])
	env.ssao_intensity = 1.2
	return env


## adds the studio (floor, key, fill, rim, environment) to `world`; the part is already in it. ov: "rim_floor" (the rim lights the floor, default false)
static func build(world: Node3D, box: AABB, ov := {}) -> Dictionary:
	var diag := maxf(box.size.length(), 0.02)
	var sc := scaled(diag)
	var c := box.get_center()
	var out := {"diag": diag}
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.72)
	key.light_energy = float(ov.get("key_energy", KEY_E))
	set_light(key, SPEC_KEY, bool(ov.get("key_floor", false)))   # light linking: key and fill ignore the floor, so the backdrop stays black
	key.shadow_enabled = true
	key.light_angular_distance = 2.5
	key.directional_shadow_max_distance = float(sc["shadow_dist"])
	key.shadow_bias = float(sc["bias"])
	world.add_child(key)
	key.look_at_from_position(c + Vector3(0.58, 0.67, 0.44), c, Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.74, 1.0)
	fill.light_energy = float(ov.get("fill_energy", FILL_E))
	set_light(fill, SPEC_FILL, bool(ov.get("key_floor", false)))
	world.add_child(fill)
	fill.look_at_from_position(c + Vector3(-0.42, 0.23, 0.54), c, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1, 1, 1)
	rim.light_energy = float(ov.get("rim_energy", RIM_E))
	set_light(rim, SPEC_RIM, bool(ov.get("rim_floor", false)))   # the rim from behind would mirror in the floor
	world.add_child(rim)
	rim.look_at_from_position(c + Vector3(0.05, 0.21, -0.58), c, Vector3.UP)
	var fl := make_floor(box.position.y - 0.0005 * diag, c, float(sc["floor_size"]))
	world.add_child(fl)
	var we := WorldEnvironment.new()
	we.environment = make_env(diag, ov)
	world.add_child(we)
	out.merge({"key": key, "fill": fill, "rim": rim, "floor": fl, "env": we.environment, "floor_y": fl.position.y, "fade_h": float(sc["fade_h"])})
	return out


## the picture of an already painted mesh in the studio (an Image, null when it cannot be drawn). ov: "reflect" (default true), "extra": Node3D (more product:
## a ring band; mirrored too), "view_dir", "bloom", "exposure", "fill_h", "key_energy" ...
static func draw_mesh(host: Node, mesh: ArrayMesh, box: AABB, size := NiceRender.SIZE, ov := {}) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_debanding = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var world := Node3D.new()
	vp.add_child(world)
	var solid := MeshInstance3D.new()
	solid.mesh = mesh
	world.add_child(solid)
	var product: Array = [solid]
	if ov.has("extra"):
		world.add_child(ov["extra"])
		product.append(ov["extra"])
	var st := build(world, box, ov)
	var glossy: GlossyFloor = null
	if bool(ov.get("glossy", false)) and bool(ov.get("reflect", true)):
		pass   # made after the camera exists (below)
	elif bool(ov.get("reflect", true)):
		for p in product:
			var mi := p as MeshInstance3D
			if mi != null:
				world.add_child(mirror_of(mi, float(st["floor_y"]), float(st["fade_h"]), float(ov.get("mirror", MIRROR_STRENGTH))))
	var cam := Camera3D.new()
	cam.fov = float(ov.get("fov", 30.0))
	cam.near = 0.01 * maxf(float(st["diag"]), 0.1)
	cam.far = float(st["diag"]) * 120.0
	world.add_child(cam)
	cam.current = true
	host.add_child(vp)
	var dir: Vector3 = (ov.get("view_dir", Vector3(0.6, 0.3, 1.0)) as Vector3).normalized()
	var target := box.get_center()
	var dist := float(st["diag"]) * 2.0
	var fsz := Vector2(size)
	var fh := float(ov.get("fill_h", 0.5))
	var fw := float(ov.get("fill_w", NiceRender.FILL_W))
	for it in 6:
		cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
		var r := NiceRender._screen_box(cam, box)
		var sc2 := minf(fh * fsz.y / maxf(r.size.y, 1.0), fw * fsz.x / maxf(r.size.x, 1.0))
		var err := r.get_center() - fsz * 0.5
		var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / fsz.y
		target += cam.global_transform.basis.x * err.x * mpp - cam.global_transform.basis.y * err.y * mpp
		dist /= sc2
	cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
	last_view = {"xf": cam.global_transform, "fov": cam.fov, "floor_y": st["floor_y"]}
	if bool(ov.get("glossy", false)) and bool(ov.get("reflect", true)):   # s277: the blurred reflection (scripts/build/glossy_floor.gd)
		glossy = GlossyFloor.create(host, vp, world, st["floor"], float(st["floor_y"]), float(st["fade_h"]), float(ov.get("mirror", GLOSSY_STRENGTH)))
		cam.cull_mask = ALL_LAYERS & ~GlossyFloor.BOTH
		glossy.sync_camera(cam)
		glossy.set_sources(product)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		glossy.render_sides()
		for i in 3:
			await RenderingServer.frame_post_draw
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if glossy != null:
		if ov.has("glossy_debug"):
			glossy.colour_vp.get_texture().get_image().save_png(String(ov["glossy_debug"]) + "_colour.png")
			glossy.depth_vp.get_texture().get_image().save_png(String(ov["glossy_debug"]) + "_depth.png")
		glossy.free_all()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img
