## weapon_trail.gd - WEAPON TRAILS (ROADMAP 35). NOT the motion trail (T, scripts/overlays.gd): that draws the tip's path
## as one dot per frame. This draws the blade's SWEEP and exports its two edge points.
##   RIBBON ("Trail: weapon ribbon on/off"): a ribbon swept between the bat's two edge points, the knob end (base) and the
##     tip, over the last N frames (default 6 at the scene's fps). Each frame-to-frame quad fades with its age. A quad is
##     drawn only when the tip moves faster than SPEED_MIN (default 8 m/s), so a slow hold leaves no ribbon.
##   SMEAR FRAMES ("Trail: smear frames on/off"): on a frame where the tip moves more than SMEAR_MIN (default 0.20 m per
##     frame), a ghosted, stretched copy of the bat: the shaft of the frame before, from its knob to the tip's place now.
##     The classic animation smear. It is drawn into the playblast too, because the playblast renders the viewport.
##   EXPORT: sidecar() gives the per-frame base and tip in the scene's world (metres, Y up: the .glb's space). The engine
##     export writes it next to the .glb as <name>_weapon_trail.json (EngineExport.export).
## The samples come from a Body of its own (the scene's proportions), once per scene change, never per frame: the scene
## being edited is never touched.
class_name WeaponTrail
extends Node3D

const N_DEFAULT := 6
const SPEED_MIN_DEFAULT := 8.0    # m/s: the ribbon only where the tip is faster
const SMEAR_MIN_DEFAULT := 0.20   # m per frame (6 m/s at 30 fps): the smear only where the tip moves more than this in one frame
const SHAFT_R := 0.02             # m: the smear's copy of the bat (thickness only; its length is the real one)
const RIBBON_ALPHA := 0.8
const SMEAR_ALPHA := 0.35
const RIBBON_COL := Color(0.85, 0.95, 1.0)
const SMEAR_COL := Color(1.0, 0.92, 0.7)
const FORMAT := "kine-weapon-trail-1"

var ribbon_on := false
var smear_on := false
var n_frames := N_DEFAULT
var speed_min := SPEED_MIN_DEFAULT
var smear_min := SMEAR_MIN_DEFAULT
var info := ""        # what the trail measured, for the status line
var builds := 0       # how many times the samples were taken (tests: once per scene change)
var quads := 0       # the quads in the ribbon mesh now (6 vertices each; tests read it)
var samples := {}     # the last sample() result: fps, t, base, tip, speed, armed
var _src: Scene = null
var _dirty := true
var _body: Body = null
var _ribbon: MeshInstance3D
var _smear: MeshInstance3D
# R23 WEAPON TRAIL IN RENDERS: a fading swept surface between the GRIP and the TIP over the last RENDER_N frames, drawn into the
# playblast and the mp4 shot render (main.gd sets render_active only for the frames it captures). Option render_on, default on;
# the colour is the theme's accent (Tok), lightened. Not stored in the scene.
const RENDER_N := 8
const RENDER_SPEED := 4.0         # m/s: a quad is drawn only where the tip is this fast (a held pose leaves no ribbon)
const RENDER_ALPHA := 0.75
const RENDER_INNER := 0.7          # the ribbon's inner edge, as a fraction of the bat from the knob: the last 30% near the tip
var render_on := true
var render_active := false
var render_quads := 0
var _rr: MeshInstance3D


func setup() -> void:
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = ImmediateMesh.new()
	add_child(_ribbon)
	_smear = MeshInstance3D.new()
	_smear.mesh = CylinderMesh.new()
	_smear.material_override = _mat(SMEAR_COL, SMEAR_ALPHA)
	_smear.visible = false
	add_child(_smear)
	_ribbon.visible = false
	_rr = MeshInstance3D.new()
	_rr.mesh = ImmediateMesh.new()
	_rr.visible = false
	add_child(_rr)


## the scene changed: the samples are taken again the next time they are drawn
func mark_dirty() -> void:
	_dirty = true


static func _mat(col: Color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, a)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


## THE SAMPLES: the scene at its fps on b (a Body of its own; its proportions are the scene's). Frame i is at
## t = min(i / fps, length). base = the knob end (wep_point(0)), tip = wep_point(wep_len), speed[i] = |tip_i - tip_i-1| * fps
## (speed[0] = speed[1]). armed[i] = the weapon is in a hand at frame i. Returns {} for a scene with no cards.
static func sample(S: Scene, b: Body) -> Dictionary:
	if S.cards.size() < 1:
		return {}
	if b.body != S.body:
		b.set_proportions(S.body)
	var fps := float(S.fps)
	var n := int(ceil(S.length() * fps)) + 1
	var out := {"fps": fps, "t": [], "base": [], "tip": [], "grip": [], "speed": [], "armed": []}
	var prev := Vector3.ZERO
	for i in n:
		var t := minf(i / fps, S.length())
		S.apply(b, t)
		var on := b.wep_on
		var base := b.wep_point(0.0) if on else Vector3.ZERO
		var tip := b.wep_point(b.wep_len) if on else Vector3.ZERO
		out["t"].append(t)
		out["base"].append(base)
		out["tip"].append(tip)
		out["grip"].append(b.grip_point() if on else Vector3.ZERO)
		out["armed"].append(on)
		out["speed"].append((tip - prev).length() * fps if i > 0 and on and out["armed"][i - 1] else 0.0)
		prev = tip
	var sp: Array = out["speed"]
	if sp.size() > 1:
		sp[0] = sp[1]
	return out


## the frame index for a scene time, clamped to the samples
func frame_of(t: float) -> int:
	var n: int = (samples.get("t", []) as Array).size()
	return clampi(roundi(t * float(samples.get("fps", 30.0))), 0, maxi(0, n - 1))


## the frames whose ribbon quad is drawn at frame f: k in (f - N, f], k >= 1, tip speed above speed_min. A plain list
## so a test can compare it with the speeds directly.
func ribbon_frames(f: int) -> Array:
	var out := []
	if samples.is_empty():
		return out
	var sp: Array = samples["speed"]
	for k in range(maxi(1, f - n_frames + 1), f + 1):
		if k < sp.size() and sp[k] > speed_min and samples["armed"][k] and samples["armed"][k - 1]:
			out.append(k)
	return out


## the smear at frame f: the frame's tip speed above smear_min (and the bat in hand), else -1
func smear_frame(f: int) -> int:
	if samples.is_empty() or f < 1 or f >= (samples["speed"] as Array).size():
		return -1
	return f if samples["speed"][f] > smear_min and samples["armed"][f] and samples["armed"][f - 1] else -1


## the view: called from main's _refresh with the scene and the playhead. Off = nothing drawn (the scene's frames are the
## same as before: no node is made visible, no pose is touched).
func draw(S: Scene, t: float) -> void:
	var rr := render_active and render_on and not ribbon_on   # (the viewport's own ribbon, when on, is what the render shows)
	if not ribbon_on and not smear_on and not rr:
		_ribbon.visible = false
		_smear.visible = false
		_hide_render()
		info = ""
		return
	if S != _src or _dirty or samples.is_empty():
		_src = S
		_dirty = false
		if _body == null:
			_body = Body.new()
			_body.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		samples = sample(S, _body)
		builds += 1
	if samples.is_empty():
		_ribbon.visible = false
		_smear.visible = false
		_hide_render()
		return
	var f := frame_of(t)
	_draw_render(f, rr)
	_draw_ribbon(f)
	_draw_smear(f)
	info = "weapon trail: %d ribbon quads (tip > %.1f m/s over %d frames), smear %s" % [
		ribbon_frames(f).size(), speed_min, n_frames, ("on at this frame" if smear_frame(f) >= 0 else "off at this frame") if smear_on else "off"]


func _draw_ribbon(f: int) -> void:
	_ribbon.visible = ribbon_on
	var im := _ribbon.mesh as ImmediateMesh
	im.clear_surfaces()
	quads = 0
	if not ribbon_on:
		return
	var ks := ribbon_frames(f)
	quads = ks.size()
	if ks.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat(RIBBON_COL, 1.0))
	for k in ks:
		# the quad between frame k-1 and frame k: its two edges, the knob end (base) and the tip; each vertex carries
		# the alpha of its own frame, so the ribbon is brightest at the playhead and fades back over N frames
		var a0 := _alpha(f - (k - 1))
		var a1 := _alpha(f - k)
		var b0: Vector3 = samples["base"][k - 1]
		var t0: Vector3 = samples["tip"][k - 1]
		var b1: Vector3 = samples["base"][k]
		var t1: Vector3 = samples["tip"][k]
		_vert(im, b0, a0)
		_vert(im, t0, a0)
		_vert(im, b1, a1)
		_vert(im, t0, a0)
		_vert(im, t1, a1)
		_vert(im, b1, a1)
	im.surface_end()


func _hide_render() -> void:
	if _rr != null:
		_rr.visible = false
		(_rr.mesh as ImmediateMesh).clear_surfaces()
	render_quads = 0


## the frames whose grip-to-tip quad is in the render ribbon at frame f: every armed k in (f - RENDER_N, f], provided the tip
## was faster than RENDER_SPEED somewhere in that window (a swing's run-up is slow, so it is the window that is gated, not each
## quad: the ribbon then shows the whole acceleration; a held pose leaves none)
func render_frames(f: int) -> Array:
	var out := []
	if samples.is_empty():
		return out
	var sp: Array = samples["speed"]
	var fast := false
	for k in range(maxi(1, f - RENDER_N + 1), f + 1):
		if k < sp.size() and sp[k] > RENDER_SPEED and samples["armed"][k] and samples["armed"][k - 1]:
			fast = true
			out.append(k)
		elif k < sp.size() and samples["armed"][k] and samples["armed"][k - 1]:
			out.append(k)
	return out if fast else []


func _draw_render(f: int, on: bool) -> void:
	var im := _rr.mesh as ImmediateMesh
	im.clear_surfaces()
	render_quads = 0
	_rr.visible = false
	if not on:
		return
	var ks := render_frames(f)
	render_quads = ks.size()
	if ks.is_empty():
		return
	var col := Tok.c("accent").lightened(0.45)
	_rr.visible = true
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _rmat())
	for k in ks:
		var a0 := _ralpha(f - (k - 1))
		var a1 := _ralpha(f - k)
		var g0: Vector3 = render_inner(k - 1)
		var t0: Vector3 = samples["tip"][k - 1]
		var g1: Vector3 = render_inner(k)
		var t1: Vector3 = samples["tip"][k]
		for v in [[g0, a0 * 0.6], [t0, a0], [g1, a1 * 0.6], [t0, a0], [t1, a1], [g1, a1 * 0.6]]:   # the inner edge is fainter than the tip's
			im.surface_set_color(Color(col.r, col.g, col.b, v[1]))
			im.surface_add_vertex(v[0])
	im.surface_end()


## the render ribbon's inner edge at frame k: 70% of the way from the knob end to the tip
func render_inner(k: int) -> Vector3:
	return (samples["base"][k] as Vector3).lerp(samples["tip"][k], RENDER_INNER)


const RSHADER := "shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
void fragment() { ALBEDO = COLOR.rgb; ALPHA = COLOR.a; }
"
static var _rsh: Shader = null


static func _rmat() -> ShaderMaterial:
	# additive: the ribbon only adds light, so the bodies behind it stay visible; the vertex alpha scales what is added
	if _rsh == null:
		_rsh = Shader.new()
		_rsh.code = RSHADER
	var m := ShaderMaterial.new()
	m.shader = _rsh
	return m


func _ralpha(age: int) -> float:
	return RENDER_ALPHA * clampf(1.0 - float(age) / float(RENDER_N), 0.0, 1.0)


func _alpha(age: int) -> float:
	return RIBBON_ALPHA * clampf(1.0 - float(age) / float(maxi(1, n_frames)), 0.0, 1.0)


static func _vert(im: ImmediateMesh, p: Vector3, a: float) -> void:
	im.surface_set_color(Color(RIBBON_COL.r, RIBBON_COL.g, RIBBON_COL.b, a))
	im.surface_add_vertex(p)


func _draw_smear(f: int) -> void:
	var k := smear_frame(f) if smear_on else -1
	_smear.visible = k >= 0
	if k < 0:
		return
	# a copy of the bat as it was one frame ago (knob to tip), stretched so its tip is where the tip is now
	var a: Vector3 = samples["base"][k - 1]
	var b: Vector3 = samples["tip"][k]
	var d := b - a
	var L := d.length()
	if L < 1e-6:
		_smear.visible = false
		return
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	_smear.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	var cm := _smear.mesh as CylinderMesh
	cm.top_radius = SHAFT_R
	cm.bottom_radius = SHAFT_R
	cm.height = L


## the export: per frame the base (knob end) and tip in the scene's world, metres, Y up (the .glb's space). {} with no weapon.
static func sidecar(S: Scene, b: Body, scene_name: String) -> Dictionary:
	var s := sample(S, b)
	if s.is_empty() or not (s["armed"] as Array).has(true):
		return {}
	var frames := []
	for i in (s["t"] as Array).size():
		var on: bool = s["armed"][i]
		frames.append({"t": snappedf(float(s["t"][i]), 1e-6), "held": on,
			"base": _v3(s["base"][i]) if on else null, "tip": _v3(s["tip"][i]) if on else null,
			"speed": snappedf(float(s["speed"][i]), 1e-6)})
	return {"format": FORMAT, "scene": scene_name, "fps": int(s["fps"]), "units": "m", "up": "+Y",
		"note": "base = the knob end (the butt), tip = the far end of the bat; the same space as the .glb's root. Frame i is at t = i / fps.",
		"frames": frames}


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 1e-7), snappedf(v.y, 1e-7), snappedf(v.z, 1e-7)]
