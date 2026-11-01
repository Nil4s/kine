## SHADING MODES + FPS TRUTH (round 42, GATES XX10, UPGRADES_300 #318, #323)
## SHADING is a VIEW setting: how the body is drawn. It is never saved in a scene and never an undo step.
##   solid       today's look, the default: the body keeps the very material it was built with (frames byte for byte)
##   matcap      the body in a ShaderMaterial that shades by the normal's angle to the eye (no lights, no texture)
##   silhouette  the body flat in ONE colour (Tok "ink") on a flat background (Tok "world"): exactly two colours.
##               Done with the camera's cull mask: only the body (and the weapons) are on layer 2, so the floor, the
##               grid, the axes, the joint dots, the collision capsules, the name tag, the dummy and every overlay
##               (trail, onion, ghosts) are simply not drawn. The 2D chrome is not part of the 3D view: hide it
##               (Tab, big view) when you want the bare picture. MSAA is switched off while it is on, because the
##               smoothed edge pixels would be a third and fourth colour.
##   xray        the body see-through (alpha 0.3, no depth write), so the joint dots and what is behind it show
## FPS TRUTH: during playback, the frames per second really reached and the DROPPED frames: a frame whose delta is more
## than 1.5 x the target frame time. Shading.fps_stats(deltas, target) is the pure rule; Shading.Meter feeds it live.
class_name Shading
extends RefCounted

const MODES := ["solid", "matcap", "silhouette", "xray"]   # what "Shading: next" cycles through
const SETTABLE := ["solid", "matcap", "silhouette", "xray", "wireframe"]   # K01: wireframe is picked by name, not cycled
const MATCAPS := ["clay", "wax", "skin"]
const LIGHTS := ["default", "three_point", "rim", "top", "flat"]
const LIGHT_NAMES := {"default": "the stage's own lights", "three_point": "3-point (key, fill, rim)", "rim": "rim only", "top": "top light", "flat": "flat (ambient only)"}
## K02: [rotation_degrees of the light, energy, colour] per role. Front is +z (the stage's sun at (-50, 35) shines toward -z).
## Key:fill 2.0 : 0.7 = 2.9:1, inside the 2:1 to 4:1 band of Brown, Cinematography: Theory and Practice (see light_rig.gd).
const STUDIO := {
	"three_point": {"key": [Vector3(-35, 40, 0), 2.0, Color(1.0, 0.95, 0.88)], "fill": [Vector3(-12, -50, 0), 0.7, Color(0.86, 0.92, 1.0)], "rim": [Vector3(-30, 200, 0), 1.3, Color(1, 1, 1)], "amb": [0.25, Color(0.55, 0.57, 0.62)]},
	"rim": {"key": [Vector3(-35, 40, 0), 0.0, Color(1, 1, 1)], "fill": [Vector3(-12, -50, 0), 0.0, Color(1, 1, 1)], "rim": [Vector3(-25, 205, 0), 2.6, Color(0.86, 0.92, 1.0)], "amb": [0.12, Color(0.55, 0.57, 0.62)]},
	"top": {"key": [Vector3(-90, 0, 0), 1.9, Color(1, 1, 1)], "fill": [Vector3(-12, -50, 0), 0.0, Color(1, 1, 1)], "rim": [Vector3(-30, 200, 0), 0.0, Color(1, 1, 1)], "amb": [0.2, Color(0.55, 0.57, 0.62)]},
	"flat": {"key": [Vector3(-35, 40, 0), 0.0, Color(1, 1, 1)], "fill": [Vector3(-12, -50, 0), 0.0, Color(1, 1, 1)], "rim": [Vector3(-30, 200, 0), 0.0, Color(1, 1, 1)], "amb": [1.0, Color(0.9, 0.9, 0.92)]},
}
## K01 matcaps, drawn by the shader from the view-space normal (no image files): [shade, lit, spec strength, shininess, rim]
const MATCAP_LOOK := {
	"clay": [Color(0.30, 0.27, 0.25), Color(0.80, 0.74, 0.66), 0.05, 12.0, 0.10],
	"wax": [Color(0.22, 0.02, 0.03), Color(0.80, 0.14, 0.12), 0.75, 48.0, 0.30],
	"skin": [Color(0.40, 0.18, 0.15), Color(0.92, 0.68, 0.56), 0.18, 20.0, 0.25],
}
const DROP_FACTOR := 1.5
const XRAY_ALPHA := 0.3
const SIL_LAYER := 2   # the render-layer bit (value 2) the body joins in silhouette mode

const MATCAP_CODE := """shader_type spatial;
render_mode unshaded;
uniform vec4 shade_col : source_color;
uniform vec4 lit_col : source_color;
uniform vec4 rim_col : source_color;
uniform float spec : hint_range(0.0, 1.0) = 0.1;
uniform float shine = 16.0;
uniform float rim_amt = 0.2;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(vec3(-0.35, 0.55, 0.75));
	float d = dot(n, l);
	float t = smoothstep(-0.6, 1.0, d);
	vec3 h = normalize(l + vec3(0.0, 0.0, 1.0));
	float sp = pow(max(dot(n, h), 0.0), shine) * spec;
	float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.0);
	ALBEDO = mix(shade_col.rgb, lit_col.rgb, t) + rim_col.rgb * rim * rim_amt + vec3(sp);
}
"""

var mode := "solid"
var _orig := {}   # MeshInstance3D -> the material_override it had (null for none) before any mode touched it
var _layers := {}   # MeshInstance3D -> its render layers before
var _cull := 0
var _msaa := 0
var _have_state := false
var meter := Meter.new()
var matcap := "clay"   # K01: which matcap "matcap" draws
var lights := "default"   # K02: which studio light preset is on
var sky := false   # K02: the procedural gradient sky behind the figure
var hdri := ""   # CG2: a picture file (.hdr or .exr) the sky shows instead of the gradient, and that lights the figure; "" = none
var _debug := 0
var _sky_env: Sky
var _hdri_tex: Texture2D
var _hdri_sky: Sky


static func next_mode(cur: String) -> String:
	return MODES[(MODES.find(cur) + 1) % MODES.size()]


## everything that is the figure: the mannequin's pieces and the weapons
static func bodies(m: Node) -> Array:
	var out := []
	for j in m.pieces:
		out.append(m.pieces[j])
	for n in [m.bat_handle, m.bat_barrel, m.bat_knob, m.d2_handle, m.d2_blade] + m.weapon_pieces():
		if n != null:
			out.append(n)
	if m.ui_props_root != null:   # K01: the set's props are drawn in the same mode as the body
		for c in m.ui_props_root.find_children("*", "MeshInstance3D", true, false):
			out.append(c)
	return out


## the matcap material for kind k
static func matcap_material(k: String) -> ShaderMaterial:
	var look: Array = MATCAP_LOOK[k]
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MATCAP_CODE
	sm.shader = sh
	sm.set_shader_parameter("shade_col", look[0])
	sm.set_shader_parameter("lit_col", look[1])
	sm.set_shader_parameter("rim_col", Tok.c("heading"))
	sm.set_shader_parameter("spec", look[2])
	sm.set_shader_parameter("shine", look[3])
	sm.set_shader_parameter("rim_amt", look[4])
	return sm


## draw the figure in this mode (m = main). "solid" puts back exactly what was there.
func set_mode(m: Node, want: String) -> void:
	if not want in SETTABLE:
		return
	var cam: Camera3D = m.cam
	var vp: Viewport = m.get_viewport()
	if not _have_state:
		_have_state = true
		_cull = cam.cull_mask
		_msaa = vp.msaa_3d
		_debug = vp.debug_draw
	for mi in _orig.keys():   # nodes a rebuilt set left behind
		if not is_instance_valid(mi):
			_orig.erase(mi)
			_layers.erase(mi)
	for mi in bodies(m):   # parts and props that appeared since: remember what they had before any mode
		if not _orig.has(mi):
			_orig[mi] = mi.material_override
			_layers[mi] = mi.layers
	# back to the starting look first, so every mode is applied from the same ground
	for mi in _orig:
		mi.material_override = _orig[mi]
		mi.layers = _layers[mi]
	cam.cull_mask = _cull
	vp.msaa_3d = _msaa
	vp.debug_draw = _debug
	mode = want
	apply_sky(m)
	match want:
		"matcap":
			var sm := matcap_material(matcap)
			for mi in bodies(m):
				mi.material_override = sm
		"silhouette":
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.albedo_color = Tok.c("ink")
			for mi in bodies(m):
				mi.material_override = fm
				mi.layers = SIL_LAYER
			cam.cull_mask = SIL_LAYER
			vp.msaa_3d = Viewport.MSAA_DISABLED
		"xray":
			var xm := StandardMaterial3D.new()
			xm.albedo_color = Color(Tok.c("cube_edge"), XRAY_ALPHA)
			xm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			xm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			for mi in bodies(m):
				mi.material_override = xm
		"wireframe":
			# the engine draws every mesh as its edges (the floor and grid too, as in Blender's wire view); the body also
			# gets one flat unshaded override so the material type is a plain unlit colour, never a lit or textured one
			var wm := StandardMaterial3D.new()
			wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wm.albedo_color = Tok.c("ink")
			for mi in bodies(m):
				mi.material_override = wm
			vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME


## the background: the flat world colour, or (sky on) the picture (CG2) or a procedural gradient sky. The silhouette is always flat.
func apply_sky(m: Node) -> void:
	var e: Environment = m.world_env
	if sky and mode != "silhouette":
		if _hdri_tex != null:
			if _hdri_sky == null:
				var pa := PanoramaSkyMaterial.new()
				pa.panorama = _hdri_tex
				_hdri_sky = Sky.new()
				_hdri_sky.sky_material = pa
			e.sky = _hdri_sky
		else:
			if _sky_env == null:
				var pm := ProceduralSkyMaterial.new()
				pm.sky_top_color = Color(0.20, 0.34, 0.60)
				pm.sky_horizon_color = Color(0.72, 0.78, 0.86)
				pm.ground_horizon_color = Color(0.72, 0.78, 0.86)
				pm.ground_bottom_color = Color(0.16, 0.17, 0.20)
				pm.sky_curve = 0.25
				_sky_env = Sky.new()
				_sky_env.sky_material = pm
			e.sky = _sky_env
		e.background_mode = Environment.BG_SKY
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = Tok.c("world")
	apply_light_source(m)


## CG2: a picture (.hdr or .exr) as the background and the light. The file is read here; a file that is not a picture
## is refused and nothing changes. The picture shows when the sky is on (load_hdri turns it on).
func read_hdri(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return false
	hdri = path
	_hdri_tex = ImageTexture.create_from_image(img)
	_hdri_sky = null
	return true


func load_hdri(m: Node, path: String) -> bool:
	if not read_hdri(path):
		return false
	sky = true
	apply_sky(m)
	return true


func clear_hdri(m: Node) -> void:
	hdri = ""
	_hdri_tex = null
	_hdri_sky = null
	apply_sky(m)


## the picture lights the figure only while it is the background (sky on, not silhouette): its sky is the ambient light and
## the reflections. Otherwise the stage's own ambient colour, as before. Called wherever the background or the lights change.
func apply_light_source(m: Node) -> void:
	var e: Environment = m.world_env
	var lit := _hdri_tex != null and sky and mode != "silhouette"
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if lit else Environment.AMBIENT_SOURCE_COLOR
	if lit:
		e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	elif e.background_mode == Environment.BG_COLOR:
		studio_reflection(e)   # bug3: a flat background has nothing to reflect: a metal block went black
	else:
		e.reflected_light_source = Environment.REFLECTION_SOURCE_BG


## THE BODY LOOK's stage (Nick's "D"): soft lights (ambient 0.22, warm key 0.62, cool rim 0.5, a little fill) and SSAO. The stage is
## built with it and every "back to the stage's own lights" (a lighting preset off, studio "default") puts it back, bit for bit
static func stage_default(m: Node) -> void:
	var e: Environment = m.world_env
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.74)
	e.ambient_light_energy = 0.22
	if e.background_mode == Environment.BG_COLOR:
		studio_reflection(e)
	e.ssao_enabled = true
	e.ssao_radius = 0.35
	e.ssao_intensity = 1.6
	e.ssao_power = 1.5
	e.ssao_detail = 0.0
	var key: DirectionalLight3D = m.light_key
	key.rotation_degrees = Vector3(-42, 38, 0)
	key.light_energy = 0.62
	key.light_color = Color(1.0, 0.97, 0.93)
	key.light_angular_distance = 4.0   # a soft penumbra
	var rim: DirectionalLight3D = m.light_rim
	rim.rotation_degrees = Vector3(-18, 205, 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.82, 0.9, 1.0)
	var fill: DirectionalLight3D = m.light_fill
	fill.rotation_degrees = Vector3(-10, -50, 0)
	fill.light_energy = 0.25
	fill.light_color = Color.WHITE
	m._light_home = [key.basis, fill.basis, rim.basis]


## K02: put the studio lights on (the stage's own three lights are re-aimed, never added or removed)
func apply_lights(m: Node) -> void:
	var e: Environment = m.world_env
	if lights == "default" or not STUDIO.has(lights):
		stage_default(m)
		apply_light_source(m)
		return
	var st: Dictionary = STUDIO[lights]
	for pair in [[m.light_key, "key"], [m.light_fill, "fill"], [m.light_rim, "rim"]]:
		var L: DirectionalLight3D = pair[0]
		var d: Array = st[pair[1]]
		L.rotation_degrees = d[0]
		L.light_energy = d[1]
		L.light_color = d[2]
	e.ambient_light_energy = st["amb"][0]
	e.ambient_light_color = st["amb"][1]
	apply_light_source(m)


## how many of the stage's directional lights are shining
static func light_count(m: Node) -> int:
	var n := 0
	for L in [m.light_key, m.light_fill, m.light_rim]:
		if L.light_energy > 0.001:
			n += 1
	return n


## K01 / K02 are remembered in the settings file (a test's own file, never poser.cfg). Silhouette is not (it hides the chrome).
func save_cfg(m: Node) -> void:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value("view", "shading", mode if mode != "silhouette" else "solid")
	cf.set_value("view", "matcap", matcap)
	cf.set_value("view", "lights", lights)
	cf.set_value("view", "sky", sky)
	cf.set_value("view", "hdri", hdri)
	cf.save(m.settings)


func load_cfg(m: Node) -> void:
	var cf := ConfigFile.new()
	if cf.load(m.settings) != OK:
		return
	var md := String(cf.get_value("view", "shading", "solid"))
	matcap = String(cf.get_value("view", "matcap", "clay"))
	if not matcap in MATCAPS:
		matcap = "clay"
	lights = String(cf.get_value("view", "lights", "default"))
	if not lights in LIGHTS:
		lights = "default"
	sky = bool(cf.get_value("view", "sky", false))
	var hp := String(cf.get_value("view", "hdri", ""))
	if hp != "":
		read_hdri(hp)   # a picture that has gone missing is simply not shown
	if md in SETTABLE and md != "silhouette":
		set_mode(m, md)
	elif sky:
		apply_sky(m)
	if lights != "default":
		apply_lights(m)


## ---------------------------------------------------------------- FPS TRUTH

## the pure rule: [frames per second reached, dropped frames, frames] from a list of frame deltas (seconds) and the
## target frame time. A dropped frame took more than DROP_FACTOR x the target.
static func fps_stats(deltas: Array, target: float) -> Array:
	var total := 0.0
	var dropped := 0
	for d in deltas:
		total += float(d)
		if float(d) > DROP_FACTOR * target:
			dropped += 1
	return [float(deltas.size()) / total if total > 0.0 else 0.0, dropped, deltas.size()]


static func fps_text(st: Array) -> String:
	return "playing %.1f fps, %d dropped" % [st[0], st[1]]


## the live counter: start() when playback begins (the first delta after it covers the idle time before, so it is not
## counted), feed(dt) every playing frame, stats() any time
class Meter extends RefCounted:
	var target := 1.0 / 60.0
	var frames := 0
	var total := 0.0
	var dropped := 0
	var _skip := true

	func start(tgt: float) -> void:
		target = tgt
		frames = 0
		total = 0.0
		dropped = 0
		_skip = true

	func feed(dt: float) -> void:
		if _skip:
			_skip = false
			return
		frames += 1
		total += dt
		if dt > Shading.DROP_FACTOR * target:
			dropped += 1

	func stats() -> Array:
		return [float(frames) / total if total > 0.0 else 0.0, dropped, frames]


## bug3: a studio gradient sky used ONLY for reflections (the background stays the flat colour; the ambient stays its colour).
## A metallic surface shows nothing but reflections, so with a flat background it rendered nearly black.
static var _studio_sky: Sky = null


static func studio_sky() -> Sky:
	if _studio_sky == null:
		var pm := ProceduralSkyMaterial.new()
		pm.sky_top_color = Color(1.0, 1.0, 1.0)
		pm.sky_horizon_color = Color(0.90, 0.90, 0.88)   # s217: a studio cyclorama, not a dark floor: a side face and a drum's side reflect the horizon and the ground half
		pm.ground_horizon_color = Color(0.88, 0.87, 0.85)
		pm.ground_bottom_color = Color(0.85, 0.84, 0.83)
		pm.sky_curve = 0.3
		pm.sun_angle_max = 0.0
		pm.sky_energy_multiplier = 1.2
		_studio_sky = Sky.new()
		_studio_sky.sky_material = pm
		_studio_sky.radiance_size = Sky.RADIANCE_SIZE_128
	return _studio_sky


static func studio_reflection(e: Environment) -> void:
	e.sky = studio_sky()
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
