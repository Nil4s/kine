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

const MODES := ["solid", "matcap", "silhouette", "xray"]
const DROP_FACTOR := 1.5
const XRAY_ALPHA := 0.3
const SIL_LAYER := 2   # the render-layer bit (value 2) the body joins in silhouette mode

const MATCAP_CODE := """shader_type spatial;
render_mode unshaded;
uniform vec4 shade_col : source_color;
uniform vec4 lit_col : source_color;
uniform vec4 rim_col : source_color;
void fragment() {
	vec3 n = normalize(NORMAL);
	float d = dot(n, normalize(vec3(-0.35, 0.55, 0.75)));
	float t = smoothstep(-0.6, 1.0, d);
	float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.0);
	ALBEDO = mix(shade_col.rgb, lit_col.rgb, t) + rim_col.rgb * rim * 0.25;
}
"""

var mode := "solid"
var _orig := {}   # MeshInstance3D -> the material_override it had (null for none) before any mode touched it
var _layers := {}   # MeshInstance3D -> its render layers before
var _cull := 0
var _msaa := 0
var _have_state := false
var meter := Meter.new()


static func next_mode(cur: String) -> String:
	return MODES[(MODES.find(cur) + 1) % MODES.size()]


## everything that is the figure: the mannequin's pieces and the weapons
static func bodies(m: Node) -> Array:
	var out := []
	for j in m.pieces:
		out.append(m.pieces[j])
	for n in [m.bat_handle, m.bat_barrel, m.bat_knob, m.d2_handle, m.d2_blade]:
		if n != null:
			out.append(n)
	return out


## draw the figure in this mode (m = main). "solid" puts back exactly what was there.
func set_mode(m: Node, want: String) -> void:
	if not want in MODES:
		return
	var cam: Camera3D = m.cam
	var vp: Viewport = m.get_viewport()
	if not _have_state:
		_have_state = true
		_cull = cam.cull_mask
		_msaa = vp.msaa_3d
		for mi in bodies(m):
			_orig[mi] = mi.material_override
			_layers[mi] = mi.layers
	# back to the starting look first, so every mode is applied from the same ground
	for mi in _orig:
		if is_instance_valid(mi):
			mi.material_override = _orig[mi]
			mi.layers = _layers[mi]
	cam.cull_mask = _cull
	vp.msaa_3d = _msaa
	m.world_env.background_color = Tok.c("world")
	mode = want
	match want:
		"matcap":
			var sm := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = MATCAP_CODE
			sm.shader = sh
			sm.set_shader_parameter("shade_col", Tok.c("cube"))
			sm.set_shader_parameter("lit_col", Tok.c("cube_edge"))
			sm.set_shader_parameter("rim_col", Tok.c("heading"))
			for j in m.pieces:
				m.pieces[j].material_override = sm
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
			for j in m.pieces:
				m.pieces[j].material_override = xm


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
