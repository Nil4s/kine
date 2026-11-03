class_name GlossyFloor
extends RefCounted
## ITEM 277 (Studio v2): a GLOSSY floor reflection that BLURS WITH DISTANCE (Blender's soft smear; StudioLight.mirror_of is a hard mirror).
## How: the product is mirrored across the floor into TWO small side viewports that share the film's world and see only the mirror layer:
##   colour  = what the mirrored surface glows / reflects (a ring keeps its OWN per-pixel colour: its shader is cloned, so the hue runs round the reflection)
##   depth   = how far below the floor that surface is, in fade heights (0 at the contact line, 1 = gone)
## The floor shader gathers the colour in a disc whose radius grows with the depth of the pixel that is being gathered (a scatter-as-gather
## circle of confusion, energy conserving), so the reflection is sharp where the product touches the floor and a soft smear further down, and the
## fade (f^2 with depth) is applied per gathered texel. The floor then carries it as EMISSION, so the bloom of the main camera blooms it too.
## Used only when a caller asks (ov "glossy": true, or the film driver); StudioLight's hard mirror stays the default.

const MIRROR_LAYER := 1 << 18   # the colour copy
const DEPTH_LAYER := 1 << 17    # the depth copy
const BOTH := (1 << 18) | (1 << 17)
const R0 := 0.0014       # blur radius at the contact line, share of the image height
const R1 := 0.032        # extra radius at fade depth 1, share of the image height
const TAPS := 96

const COLOUR := "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec3 body = vec3(0.1);
uniform vec3 glow = vec3(0.0);
uniform float glow_k = 0.0;
void fragment() { ALBEDO = body * 0.06 + glow * glow_k; }
"

const DEPTH := "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform float floor_y = 0.0;
uniform float fade_h = 0.1;
varying float depth;
void vertex() { depth = floor_y - (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment() { ALBEDO = vec3(clamp(depth / fade_h, 0.0, 1.0)); }
"

const FLOOR := "shader_type spatial;
render_mode depth_draw_never, specular_disabled;
uniform sampler2D refl : filter_linear, hint_default_black;
uniform sampler2D rdepth : filter_linear, hint_default_black;
uniform float strength = 0.55;
uniform float r0 = 1.5;
uniform float r1 = 48.0;
uniform vec2 px = vec2(0.0005, 0.0009);
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
void fragment() {
	ALBEDO = vec3(0.012, 0.012, 0.015);
	ROUGHNESS = 0.3;
	METALLIC = 0.0;
	float rmax = r0 + r1;
	float rot = ign(FRAGCOORD.xy) * 6.2831853;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 96; i++) {
		float fi = (float(i) + 0.5) / 96.0;
		float rr = sqrt(fi);
		float ang = float(i) * 2.39996323 + rot;
		vec2 o = vec2(cos(ang), sin(ang)) * rr;
		vec2 uv = SCREEN_UV + o * rmax * px;
		float d = texture(rdepth, uv).r;
		float rs = r0 + r1 * d;
		if (rr * rmax <= rs) {
			float f = clamp(1.0 - d, 0.0, 1.0);
			acc += texture(refl, uv).rgb * f * f * (rmax * rmax) / (96.0 * rs * rs);
		}
	}
	EMISSION = acc * strength;
}
"

var colour_vp: SubViewport
var depth_vp: SubViewport
var cam_c: Camera3D
var cam_d: Camera3D
var floor_mat: ShaderMaterial
var floor_y := 0.0
var fade_h := 0.1
var mirrors: Array = []
var world_root: Node3D


## builds the floor's glossy material and the two reflection viewports under `host` (any node of the scene tree), sharing `main_vp`'s world. Returns the object.
static func create(host: Node, main_vp: SubViewport, world_root_: Node3D, floor_mi: MeshInstance3D, floor_y_: float, fade_h_: float, strength := 0.55) -> GlossyFloor:
	var g := GlossyFloor.new()
	g.floor_y = floor_y_
	g.fade_h = fade_h_
	g.world_root = world_root_
	var env := Environment.new()   # a plain black background, no tonemap, no glow: the side viewports hold linear HDR numbers, not a picture
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	for k in 2:
		var v := SubViewport.new()
		v.size = main_vp.size
		v.world_3d = main_vp.find_world_3d()
		v.use_hdr_2d = true
		v.msaa_3d = Viewport.MSAA_DISABLED
		v.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var c := Camera3D.new()
		c.cull_mask = MIRROR_LAYER if k == 0 else DEPTH_LAYER
		c.environment = env
		c.current = true
		v.add_child(c)
		host.add_child(v)
		if k == 0:
			g.colour_vp = v
			g.cam_c = c
		else:
			g.depth_vp = v
			g.cam_d = c
	var sh := Shader.new()
	sh.code = FLOOR
	g.floor_mat = ShaderMaterial.new()
	g.floor_mat.shader = sh
	g.floor_mat.render_priority = -10
	g.floor_mat.set_shader_parameter("refl", g.colour_vp.get_texture())
	g.floor_mat.set_shader_parameter("rdepth", g.depth_vp.get_texture())
	g.floor_mat.set_shader_parameter("strength", strength)
	var h := float(main_vp.size.y)
	g.floor_mat.set_shader_parameter("r0", R0 * h)
	g.floor_mat.set_shader_parameter("r1", R1 * h)
	g.floor_mat.set_shader_parameter("px", Vector2(1.0 / main_vp.size.x, 1.0 / main_vp.size.y))
	floor_mi.material_override = g.floor_mat
	return g


## the blur radii in pixels at the contact line and at fade depth 1 (a test reads them)
func radii() -> Vector2:
	return Vector2(float(floor_mat.get_shader_parameter("r0")), float(floor_mat.get_shader_parameter("r1")))


## drops the mirrors of the last picture and mirrors `sources` (MeshInstance3D of the product) across the floor, into both side viewports
func set_sources(sources: Array) -> void:
	for m in mirrors:
		if is_instance_valid(m):
			(m as Node).queue_free()
	mirrors.clear()
	var cs := Shader.new()
	cs.code = COLOUR
	var ds := Shader.new()
	ds.code = DEPTH
	var dm := ShaderMaterial.new()
	dm.shader = ds
	dm.set_shader_parameter("floor_y", floor_y)
	dm.set_shader_parameter("fade_h", fade_h)
	for src in sources:
		var s := src as MeshInstance3D
		if s == null or s.mesh == null or not s.visible:
			continue
		var xf := Transform3D(Basis.from_scale(Vector3(1, -1, 1)), Vector3(0, 2.0 * floor_y, 0)) * s.global_transform
		# the colour copy: every surface from its own colour/glow; a ring band keeps its own shader (per-pixel hue)
		var mc := MeshInstance3D.new()
		mc.mesh = s.mesh
		for k in s.mesh.get_surface_count():
			var mat: Material = s.get_surface_override_material(k)
			if mat == null:
				mat = s.mesh.surface_get_material(k)
			if mat == null:
				mat = s.material_override
			var out: Material = null
			if mat is ShaderMaterial and (mat as ShaderMaterial).has_meta("ring_glow"):
				out = (mat as ShaderMaterial).duplicate()   # the same unshaded hue-round-the-ring shader, this frame's numbers
			else:
				var sm := ShaderMaterial.new()
				sm.shader = cs
				if mat is BaseMaterial3D:
					var b := mat as BaseMaterial3D
					sm.set_shader_parameter("body", Vector3(b.albedo_color.r, b.albedo_color.g, b.albedo_color.b))
					if b.emission_enabled:
						sm.set_shader_parameter("glow", Vector3(b.emission.r, b.emission.g, b.emission.b))
						sm.set_shader_parameter("glow_k", b.emission_energy_multiplier)
				out = sm
			mc.set_surface_override_material(k, out)
		mc.layers = MIRROR_LAYER
		mc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(mc)
		mc.global_transform = xf
		mirrors.append(mc)
		var md := MeshInstance3D.new()
		md.mesh = s.mesh
		md.material_override = dm
		md.layers = DEPTH_LAYER
		md.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(md)
		md.global_transform = xf
		mirrors.append(md)


## copies the main camera into both side cameras
func sync_camera(cam: Camera3D) -> void:
	for c in [cam_c, cam_d]:
		var cc := c as Camera3D
		cc.global_transform = cam.global_transform
		cc.fov = cam.fov
		cc.keep_aspect = cam.keep_aspect
		cc.near = cam.near
		cc.far = cam.far


## draws both side viewports (call, await two frames, then draw the main viewport)
func render_sides() -> void:
	colour_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	depth_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func free_all() -> void:
	for m in mirrors:
		if is_instance_valid(m):
			(m as Node).queue_free()
	mirrors.clear()
	for v in [colour_vp, depth_vp]:
		if is_instance_valid(v):
			(v as Node).queue_free()


## the sharpness of a reflected vertical stick: the 90 % -> 10 % fall distance (px, interpolated) of the row's luminance on the stick's left side, scanning left
## from column x. Returns -1 when the row holds no stick (peak under 0.02). A hard edge reads ~1-2 px, a smear reads wide.
static func line_width(img: Image, x: int, y: int, span := 60) -> float:
	var lo := maxi(x - span, 0)
	var vals := []
	var peak := 0.0
	for xx in range(x, lo - 1, -1):
		var c := img.get_pixel(xx, y)
		var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		vals.append(l)
		peak = maxf(peak, l)
	if peak < 0.02:
		return -1.0
	var floor_l := float(vals[vals.size() - 1])
	var t90 := -1.0
	var t10 := -1.0
	var lv90 := floor_l + 0.9 * (peak - floor_l)
	var lv10 := floor_l + 0.1 * (peak - floor_l)
	for i in range(1, vals.size()):
		var a0: float = vals[i - 1]
		var b0: float = vals[i]
		if t90 < 0.0 and a0 >= lv90 and b0 < lv90:
			t90 = float(i - 1) + (a0 - lv90) / maxf(a0 - b0, 1e-6)
		if t90 >= 0.0 and a0 >= lv10 and b0 < lv10:
			t10 = float(i - 1) + (a0 - lv10) / maxf(a0 - b0, 1e-6)
			break
	if t90 < 0.0 or t10 < 0.0:
		return -1.0
	return t10 - t90
