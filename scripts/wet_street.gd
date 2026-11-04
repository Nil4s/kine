class_name WetStreet
extends Node3D
## CH5: wet pavement at night. A cobble + asphalt height field, ONE water level, puddles = height < level (never painted),
## wetness (darker, smoother) near water and in the joints, a lamp, and a planar mirror for the puddles.
## Numbers and their sources: docs/CH5_REFERENCE.md. Shader: scripts/wet_street.gdshader.
## World: metres, +y up. The patch is x in [X0, X0+SPAN_X], z in [Z0, Z0+SPAN_Z]; the camera stands on +z and looks toward -z.

const X0 := -3.2
const Z0 := -13.6
const SPAN_X := 6.4
const SPAN_Z := 14.4
const TEXEL := 0.003                 ## metres per baked pixel (3 mm: joints 4 px wide, rims resolved)
const PITCH := 0.11                  ## cobble pitch (setts 100-120 mm)
const GAP := 0.014                   ## joint width
const GAP_FLOOR := -0.030            ## joint bottom below the stone tops
const TOP_SIG := 0.004               ## per-stone top height sigma
const DOME := 0.007                  ## each stone top is a dome, edge slope about 0.11
const JOINT_DARK := 0.3              ## wet joints: albedo x this at the joint centre
const TILT := 0.045                  ## per-stone tilt range
const ROUND := 0.014                 ## rounding width of a stone edge
const LEVEL := -0.034                ## THE water level: below the joint bottoms, so joints stay dry and only bowls flood
const ASPHALT_X := 0.85              ## asphalt patch: x > this
const DRY_ROUGH_COBBLE := 0.85
const DRY_ROUGH_ASPHALT := 0.92
const WET_ROUGH_COBBLE := 0.15
const WET_ROUGH_ASPHALT := 0.25
const WATER_ROUGH := 0.04
const DRY_ALB_COBBLE := 0.09
const DRY_ALB_ASPHALT := 0.07
const WET_DARKEN := 0.7             ## wet albedo = dry * this (Lekner & Dorf 1988: rough wet surfaces ~0.5-0.7)
const AMBIENT_WET := 0.9             ## just after rain every stone top is wet (the photos show it); rims and joints go to 1
const EYE := 1.6
const LAMP_POS := Vector3(0.3, 6.0, -12.6)   ## the bulb
const BULB_R := 0.3
const FOV := 62.0
const PITCH_DEG := -6.0

## CH5b lamp row: [bulb position, colour (rgb x intensity), post x offset from the bulb]; lamp 0 is the parked scene's lamp
const LAMPS := [
	[Vector3(0.3, 6.0, -12.6), Vector3(1.0, 0.82, 0.6), 150.0, 1.2],
	[Vector3(2.4, 4.8, -4.6), Vector3(1.0, 0.72, 0.42), 16.0, 0.55],
	[Vector3(-2.4, 4.8, -5.8), Vector3(1.0, 0.75, 0.45), 16.0, -0.55],
	[Vector3(2.9, 4.8, -8.8), Vector3(1.0, 0.72, 0.42), 16.0, 0.3],
	[Vector3(-2.9, 4.8, -10.4), Vector3(1.0, 0.75, 0.45), 16.0, -0.3],
]
const BOLLARD := Vector3(0.3, 0.0, -4.0)     ## the S2 shadow caster, on the lamp 0 to camera axis
const WALL_X := 3.3
const AMB_SKY := Vector3(0.045, 0.034, 0.022)  ## sodium sky haze (irradiance / pi)
const WALL_COL := Vector3(0.09, 0.056, 0.03)  ## warm bounce off the lit walls and their windows
var occluders: Array = []            ## [x, z, r, h] vertical cylinders that cast the analytic soft shadows
var light_r := BULB_R
var legacy := false
var env: Environment
var set_pieces: Array = []   ## walls, windows, bollards: hidden in the legacy (one-lamp, black-void) control
var probe := -1
var bowls: Array = []                ## [cx, cz, radius, depth] settled low spots (the only reason water collects)
var level := LEVEL
var himg: Image                      ## FORMAT_RF: height in metres
var mimg: Image                      ## RGBA8: wet albedo rgb, wet roughness a
var wetimg: Image                    ## FORMAT_R8: wetness 0..1
var painted := false                 ## planted control: puddles from a texture that ignores the height
var streak_px := 10.0
var lamp_intensity := 300.0          ## the pool is inverse-square in the shader: E = I cos / d^2
var ripple_px := 30.0               ## ripple slope -> reflection offset in pixels
var dry := false
var refl_gain := 60.0
var mat: ShaderMaterial
var mirror_vp: SubViewport
var mirror_cam: Camera3D
var lamp_light: SpotLight3D
var ground: MeshInstance3D
var _w := 0
var _h := 0


static func hash2(i: int, j: int) -> float:
	return fposmod(sin(float(i) * 127.1 + float(j) * 311.7) * 43758.5453, 1.0)


## the eye -> bulb mirror point on the plane y = level, and the angle between the view ray and the plane there
static func reflection_point(eye: Vector3, bulb: Vector3, lvl: float) -> Vector3:
	var t := (eye.y - lvl) / ((eye.y - lvl) + (bulb.y - lvl))
	return Vector3(eye.x + (bulb.x - eye.x) * t, lvl, eye.z + (bulb.z - eye.z) * t)


static func grazing(eye: Vector3, x: Vector3) -> float:
	return asin((eye.y - x.y) / eye.distance_to(x))


## bowls placed so each camera pose has the lamp's reflection inside a puddle, plus two decoys that do not
static func default_bowls(eyes: Array) -> Array:
	var out := []
	for e in eyes:
		var x := reflection_point(e, LAMP_POS, LEVEL)
		out.append([x.x, x.z, 0.62, 0.075])
	out.append([-2.2, -3.5, 0.5, 0.06])
	out.append([1.9, -6.0, 0.7, 0.065])
	return out


func bowl_field(x: float, z: float) -> float:
	var b := 0.0
	for w in bowls:
		var dx: float = x - float(w[0])
		var dz: float = z - float(w[1])
		b -= float(w[3]) * exp(-(dx * dx + dz * dz) / (float(w[2]) * float(w[2])))
	return b


func is_asphalt(x: float, _z: float) -> bool:
	return x > ASPHALT_X


## CH5b irregular setts: rows 80-140 mm deep from Z_START, stones 80-140 mm wide with a per-row offset, all from hashes (no two alike).
## Returns [stone id i, row id j, u, v, e (m to the nearest edge), left, right, top, bottom]; u, v are metres from the stone's left / top edge
## divided by PITCH (so u * PITCH is the distance from the left edge).
const Z_START := -20.0
const X_START := -4.4
var _row_z := PackedFloat32Array()      ## row j starts at _row_z[j]
var _row_x: Array = []                  ## per row: PackedFloat32Array of stone left edges (one more than the stones)
var _cj := 0
var _ci := 0


func _build_layout() -> void:
	_row_z = PackedFloat32Array()
	_row_x = []
	var z := Z_START
	var j := 0
	while z < 4.0:
		_row_z.append(z)
		var xs := PackedFloat32Array()
		var x := X_START - 0.14 * hash2(j, 101)
		var i := 0
		while x < 4.4:
			xs.append(x)
			x += 0.08 + 0.06 * hash2(i, j + 500)
			i += 1
		xs.append(x)
		_row_x.append(xs)
		z += 0.08 + 0.06 * hash2(j, 77)
		j += 1
	_row_z.append(z)


func cobble_cell(x: float, z: float) -> Array:
	if _row_z.is_empty():
		_build_layout()
	var nr := _row_z.size() - 1
	var j := _cj
	if not (j < nr and z >= _row_z[j] and z < _row_z[j + 1]):
		var lo := 0
		var hi := nr - 1
		while lo < hi:
			var mid := (lo + hi + 1) >> 1
			if _row_z[mid] <= z:
				lo = mid
			else:
				hi = mid - 1
		j = lo
		_cj = j
	var xs: PackedFloat32Array = _row_x[j]
	var ns := xs.size() - 1
	var i := _ci
	if not (i < ns and x >= xs[i] and x < xs[i + 1]):
		var lo2 := 0
		var hi2 := ns - 1
		while lo2 < hi2:
			var mid2 := (lo2 + hi2 + 1) >> 1
			if xs[mid2] <= x:
				lo2 = mid2
			else:
				hi2 = mid2 - 1
		i = lo2
		_ci = i
	var l := xs[i]
	var r := xs[i + 1]
	var t := _row_z[j]
	var bt := _row_z[j + 1]
	var e := minf(minf(x - l, r - x), minf(z - t, bt - z))
	return [i, j, (x - l) / PITCH, (z - t) / PITCH, e, l, r, t, bt]


## the per-stone base height (the tilt and dome are added in height())
func stone_top(i: int, j: int, _u: float, _v: float) -> float:
	return (hash2(i, j) - 0.5) * 2.0 * TOP_SIG


## the surface height in metres: irregular domed stones with a random tilt (up to about 16 degrees), dark joints, or asphalt, plus the bowls
func height(x: float, z: float) -> float:
	var h := 0.0
	if is_asphalt(x, z):
		var gx := x * 3.0
		var gz := z * 3.0
		h = 0.0015 * (sin(gx * 1.7 + sin(gz * 1.3)) * 0.6 + sin(gz * 2.1 - gx * 0.7) * 0.4)
	else:
		var c := cobble_cell(x, z)
		var i: int = c[0]
		var j: int = c[1]
		var cx: float = 0.5 * (float(c[5]) + float(c[6]))
		var cz: float = 0.5 * (float(c[7]) + float(c[8]))
		var da := (x - cx) / (0.5 * (float(c[6]) - float(c[5])))
		var db := (z - cz) / (0.5 * (float(c[8]) - float(c[7])))
		var tx := (hash2(i + 7, j) - 0.5) * 0.4
		var tz := (hash2(i, j + 9) - 0.5) * 0.4
		var dome := DOME * (0.7 + 0.6 * hash2(i + 3, j + 5)) * (1.0 - 0.5 * (da * da + db * db))
		var top := stone_top(i, j, 0.0, 0.0) + tx * (x - cx) + tz * (z - cz) + dome
		var s := smoothstep(GAP * 0.5, GAP * 0.5 + ROUND, float(c[4]))
		h = lerpf(GAP_FLOOR, top, s)
	return h + bowl_field(x, z)


## joint-ness 0 (stone) .. 1 (joint centre)
func joint_amount(x: float, z: float) -> float:
	if is_asphalt(x, z):
		return 0.0
	var c := cobble_cell(x, z)
	return 1.0 - smoothstep(GAP * 0.5, GAP * 0.5 + ROUND, float(c[4]))


func stone_shade(x: float, z: float) -> float:
	if is_asphalt(x, z):
		return 0.85 + 0.3 * hash2(floori(x / 0.004), floori(z / 0.004))
	var c := cobble_cell(x, z)
	return 0.8 + 0.4 * hash2(c[0] + 31, c[1] + 17)


func dry_albedo(x: float, z: float) -> float:
	return (DRY_ALB_ASPHALT if is_asphalt(x, z) else DRY_ALB_COBBLE) * stone_shade(x, z)


func dry_roughness(x: float, z: float) -> float:
	return DRY_ROUGH_ASPHALT if is_asphalt(x, z) else DRY_ROUGH_COBBLE


## wetness 0..1: rain-damp everywhere, wetter on the rim of a puddle (bowl field close to the level), joints stay damp, water = 1
func wetness(x: float, z: float) -> float:
	var b := bowl_field(x, z)
	var rim := clampf((b + 0.003) / (level + 0.003), 0.0, 1.0)
	var w := maxf(AMBIENT_WET, rim)
	w = maxf(w, 0.9 * joint_amount(x, z))
	if height(x, z) < level:
		w = 1.0
	return w


func wet_roughness(x: float, z: float) -> float:
	var w := wetness(x, z)
	var wr := WET_ROUGH_ASPHALT if is_asphalt(x, z) else WET_ROUGH_COBBLE
	return lerpf(dry_roughness(x, z), wr, w)


func wet_albedo(x: float, z: float) -> float:
	return dry_albedo(x, z) * lerpf(1.0, WET_DARKEN, wetness(x, z))


## true where this scene has water. Unless the planted control is on, it is the height field against the level, nothing else.
func has_water(x: float, z: float) -> bool:
	if painted:
		return painted_mask(x, z)
	return height(x, z) < level


## the planted control: blobs of "puddle" from noise that never looks at the height
static func painted_mask(x: float, z: float) -> bool:
	var v := sin(x * 2.9 + 1.3) * sin(z * 2.3 - 0.7) + 0.5 * sin(x * 7.1 + z * 5.3)
	return v > 0.55


func tex_xy(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x - X0) / TEXEL), 0, _w - 1), clampi(int((z - Z0) / TEXEL), 0, _h - 1))


func texel_center(px: int, py: int) -> Vector2:
	return Vector2(X0 + (float(px) + 0.5) * TEXEL, Z0 + (float(py) + 0.5) * TEXEL)


## bake the height field and the wet material into images (GDScript; the ground quad is flat, the shader reads these)
func bake() -> void:
	_w = int(SPAN_X / TEXEL)
	_h = int(SPAN_Z / TEXEL)
	var hd := PackedFloat32Array()
	hd.resize(_w * _h)
	var md := PackedByteArray()
	md.resize(_w * _h * 4)
	var wd := PackedByteArray()
	wd.resize(_w * _h)
	for py in _h:
		for px in _w:
			var p := texel_center(px, py)
			var hh := height(p.x, p.y)
			var k := py * _w + px
			hd[k] = hh
			var w := 1.0 if hh < level else wetness_dry_height(p.x, p.y)
			var a := dry_albedo(p.x, p.y) * lerpf(1.0, WET_DARKEN, w) * lerpf(1.0, JOINT_DARK, joint_amount(p.x, p.y))
			var wr := WET_ROUGH_ASPHALT if is_asphalt(p.x, p.y) else WET_ROUGH_COBBLE
			var r := lerpf(dry_roughness(p.x, p.y), wr, w)
			var tint := 1.0 if is_asphalt(p.x, p.y) else 0.95
			md[k * 4] = int(clampf(a * 255.0 * tint, 0.0, 255.0))
			md[k * 4 + 1] = int(clampf(a * 255.0 * 0.97, 0.0, 255.0))
			md[k * 4 + 2] = int(clampf(a * 255.0 * 0.92, 0.0, 255.0))
			md[k * 4 + 3] = int(clampf(r * 255.0, 0.0, 255.0))
			wd[k] = int(clampf(w * 255.0, 0.0, 255.0))
	himg = Image.create_from_data(_w, _h, false, Image.FORMAT_RF, hd.to_byte_array())
	mimg = Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, md)
	wetimg = Image.create_from_data(_w, _h, false, Image.FORMAT_R8, wd)
	mimg.generate_mipmaps()
	wetimg.generate_mipmaps()


## wetness for a pixel already known to be above the water (avoids the second height() call)
func wetness_dry_height(x: float, z: float) -> float:
	var b := bowl_field(x, z)
	var rim := clampf((b + 0.003) / (level + 0.003), 0.0, 1.0)
	return maxf(maxf(AMBIENT_WET, rim), 0.9 * joint_amount(x, z))


func build(eyes: Array = [Vector3(0, EYE, 1.5)]) -> void:
	if bowls.is_empty():
		bowls = default_bowls(eyes)
	bake()
	# environment: night
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.015, 0.02, 0.045)
	psm.sky_horizon_color = Color(0.14, 0.085, 0.05)
	psm.ground_horizon_color = Color(0.12, 0.075, 0.045)
	psm.ground_bottom_color = Color(0.03, 0.025, 0.02)
	psm.sky_energy_multiplier = 0.35
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.45)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# ground: one flat quad, the shader reads the baked height
	var q := QuadMesh.new()
	q.size = Vector2(SPAN_X, SPAN_Z)
	q.orientation = PlaneMesh.FACE_Y
	ground = MeshInstance3D.new()
	ground.mesh = q
	ground.position = Vector3(X0 + SPAN_X * 0.5, 0.0, Z0 + SPAN_Z * 0.5)
	ground.custom_aabb = AABB(Vector3(-4, -1, -8), Vector3(8, 2, 16))
	mat = ShaderMaterial.new()
	mat.shader = load("res://scripts/wet_street.gdshader")
	mat.set_shader_parameter("tex_h", ImageTexture.create_from_image(himg))
	mat.set_shader_parameter("tex_m", ImageTexture.create_from_image(mimg))
	mat.set_shader_parameter("level", level)
	mat.set_shader_parameter("origin", Vector2(X0, Z0))
	mat.set_shader_parameter("span", Vector2(SPAN_X, SPAN_Z))
	mat.set_shader_parameter("texel", TEXEL)
	mat.set_shader_parameter("streak_px", streak_px)
	mat.set_shader_parameter("refl_gain", refl_gain)
	mat.set_shader_parameter("tex_w", ImageTexture.create_from_image(wetimg))
	_make_occluders()
	_push_lights()
	mat.set_shader_parameter("asphalt_x", ASPHALT_X)
	mat.set_shader_parameter("ripple_px", ripple_px)
	mat.set_shader_parameter("plane_y", level)
	ground.material_override = mat
	add_child(ground)
	var far := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(120, 120)
	fq.orientation = PlaneMesh.FACE_Y
	far.mesh = fq
	far.position = Vector3(0, -0.03, -40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.04, 0.035)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	far.material_override = fm
	add_child(far)
	# mirror: a second camera below the water plane
	mirror_vp = SubViewport.new()
	mirror_vp.size = Vector2i(1280, 720)
	mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mirror_vp.own_world_3d = false
	mirror_vp.msaa_3d = Viewport.MSAA_4X
	add_child(mirror_vp)
	mirror_cam = Camera3D.new()
	mirror_cam.current = true
	mirror_cam.cull_mask = 0xFFFFF & ~2   # the row's extra bulbs (layer 2) are not mirrored: only lamp 0's image is in the puddles (bar B)
	mirror_vp.add_child(mirror_cam)
	mat.set_shader_parameter("refl", mirror_vp.get_texture())
	_build_lamps()
	_build_walls()
	_build_bollards()


func lamp_count() -> int:
	return 1 if legacy else LAMPS.size()


func bollard_pos() -> Vector3:
	return BOLLARD


func _make_occluders() -> void:
	occluders.clear()
	for l in LAMPS:
		var lp: Vector3 = l[0]
		occluders.append([lp.x + float(l[3]), lp.z, 0.07, lp.y + 0.6])
	occluders.append([BOLLARD.x, BOLLARD.z, 0.12, 0.9])
	occluders.append([-1.6, -7.0, 0.12, 0.9])
	occluders.append([2.0, -2.2, 0.12, 0.9])
	occluders.append([-2.0, -9.5, 0.12, 0.9])


func _push_lights() -> void:
	var pa := PackedVector3Array()
	var ca := PackedVector3Array()
	for i in 8:
		if i < LAMPS.size():
			var l: Array = LAMPS[i]
			pa.append((l[0] as Vector3) - Vector3(0, BULB_R, 0))
			ca.append((l[1] as Vector3) * (float(l[2]) if i > 0 else lamp_intensity))
		else:
			pa.append(Vector3.ZERO)
			ca.append(Vector3.ZERO)
	var oa := PackedVector4Array()
	for i in 16:
		if i < occluders.size():
			var o: Array = occluders[i]
			oa.append(Vector4(o[0], o[1], o[2], o[3]))
		else:
			oa.append(Vector4(0, 0, 0, 0))
	mat.set_shader_parameter("lamps", pa)
	mat.set_shader_parameter("lamp_cols", ca)
	mat.set_shader_parameter("n_lamps", lamp_count())
	mat.set_shader_parameter("occ", oa)
	mat.set_shader_parameter("n_occ", 0 if legacy else occluders.size())
	mat.set_shader_parameter("light_r", light_r)
	mat.set_shader_parameter("probe_lamp", probe)
	mat.set_shader_parameter("amb_sky", Vector3(0.015, 0.018, 0.03) if legacy else AMB_SKY)
	mat.set_shader_parameter("wall_col", Vector3.ZERO if legacy else WALL_COL)
	mat.set_shader_parameter("wall_x", WALL_X - 0.1)
	mat.set_shader_parameter("spec_gain", spec_gain)
	mat.set_shader_parameter("diff_gain", 1.0 if legacy else diff_gain)
	mat.set_shader_parameter("wide_gain", 0.0 if legacy else wide_gain)


var spec_gain := 1.0
var wide_gain := 0.0
var diff_gain := 0.4          ## night exposure of the diffuse light: the stone is near black, only glints and reflections are bright


func set_legacy(on: bool) -> void:
	legacy = on
	for n in set_pieces:
		(n as Node3D).visible = not on
	if on:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.01, 0.012, 0.02)
	else:
		env.background_mode = Environment.BG_SKY
	_push_lights()


func set_probe(i: int) -> void:
	probe = i
	_push_lights()


func set_light_radius(r: float) -> void:
	light_r = r
	_push_lights()


func _build_walls() -> void:
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.2, 0.13, 0.1)
	wm.roughness = 0.9
	var win_on := StandardMaterial3D.new()
	win_on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	win_on.albedo_color = Color(0.85, 0.5, 0.22)
	var win_off := StandardMaterial3D.new()
	win_off.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	win_off.albedo_color = Color(0.03, 0.035, 0.05)
	for side in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 10.0, 18.0)
		w.mesh = bm
		w.position = Vector3(side * (WALL_X + 0.1), 5.0, -6.0)
		w.material_override = wm
		add_child(w)
		set_pieces.append(w)
		for r in 2:
			for c in 6:
				var q := MeshInstance3D.new()
				var qm := QuadMesh.new()
				qm.size = Vector2(1.0, 1.4)
				q.mesh = qm
				q.position = Vector3(side * (WALL_X - 0.005), 2.4 + 2.9 * float(r), -1.0 - 2.2 * float(c))
				q.rotation_degrees = Vector3(0, -90.0 * side, 0)
				var on := hash2(c + 3 * r, int(side) + 4) > 0.45
				q.material_override = win_on if on else win_off
				add_child(q)
				set_pieces.append(q)
	for l in LAMPS:
		var o := OmniLight3D.new()
		o.position = (l[0] as Vector3) + Vector3(0, -0.2, 0)
		o.omni_range = 9.0
		o.light_energy = 1.3
		o.light_specular = 0.0   # no engine highlights on the walls and posts in the mirror pass
		o.light_color = Color(1.0, 0.76, 0.5)
		add_child(o)


func _build_bollards() -> void:
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.08, 0.08, 0.09)
	bm.roughness = 0.5
	for o in occluders:
		if float(o[3]) > 1.0:
			continue
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(o[2])
		cm.bottom_radius = float(o[2])
		cm.height = float(o[3])
		m.mesh = cm
		m.position = Vector3(o[0], float(o[3]) * 0.5, o[1])
		m.material_override = bm
		add_child(m)
		set_pieces.append(m)


func _build_lamps() -> void:
	for l in LAMPS:
		_build_lamp(l[0], l[3])


func _build_lamp(lpos: Vector3, post_dx: float = 1.2) -> void:
	# a cantilever lamp: the pole stands 1.2 m to the side and an arm carries the globe on a thin cable, so the mirror image of the
	# globe is not cut by the pole
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.06, 0.06, 0.07)
	pm.roughness = 0.5
	var arm_y := lpos.y + 0.6
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.09
	cm.height = arm_y
	post.mesh = cm
	post.position = Vector3(lpos.x + post_dx, arm_y * 0.5, lpos.z)
	post.material_override = pm
	add_child(post)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(absf(post_dx), 0.05, 0.05)
	arm.mesh = am
	arm.position = Vector3(lpos.x + post_dx * 0.5, arm_y, lpos.z)
	arm.material_override = pm
	add_child(arm)
	var cable := MeshInstance3D.new()
	var km := CylinderMesh.new()
	km.top_radius = 0.01
	km.bottom_radius = 0.01
	km.height = arm_y - lpos.y
	cable.mesh = km
	cable.position = Vector3(lpos.x, lpos.y + (arm_y - lpos.y) * 0.5, lpos.z)
	cable.material_override = pm
	add_child(cable)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BULB_R
	sm.height = BULB_R * 2.0
	bulb.mesh = sm
	bulb.position = lpos
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(1.0, 0.97, 0.9)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.97, 0.9)
	bm.emission_energy_multiplier = 4.0
	bulb.material_override = bm
	if lamp_light != null:
		bulb.layers = 2
	add_child(bulb)
	# glare around the bulb (bloom as in the photo): an additive billboard on layer 2, so the mirror does not draw it (bar B)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1.0, 0.86, 0.62, 0.75), Color(1.0, 0.72, 0.4, 0.18), Color(1.0, 0.6, 0.3, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.albedo_texture = gt
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glare := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(3.2, 3.2)
	glare.mesh = gq
	glare.material_override = gm
	glare.position = lpos
	glare.layers = 2
	add_child(glare)
	set_pieces.append(glare)
	if lamp_light != null:
		return
	lamp_light = SpotLight3D.new()
	lamp_light.position = lpos - Vector3(0, BULB_R + 0.02, 0)
	lamp_light.rotation_degrees = Vector3(-90, 0, 0)
	lamp_light.spot_angle = 75.0
	lamp_light.spot_range = 30.0
	lamp_light.light_energy = 10.0
	lamp_light.light_specular = 0.0
	lamp_light.light_color = Color(1.0, 0.86, 0.68)
	lamp_light.spot_attenuation = 1.0
	add_child(lamp_light)


## aim the mirror camera: position mirrored about y = level, look direction y flipped, up = +y (image is the real view flipped vertically)
func sync_mirror(cam: Camera3D) -> void:
	var vs: Vector2i = cam.get_viewport().size
	if mirror_vp.size != vs:
		mirror_vp.size = vs
	mirror_cam.fov = cam.fov
	mirror_cam.near = cam.near
	mirror_cam.far = cam.far
	mirror_cam.keep_aspect = cam.keep_aspect
	var c := cam.global_position
	var d := -cam.global_transform.basis.z
	var mc := Vector3(c.x, 2.0 * level - c.y, c.z)
	mirror_cam.global_position = mc
	mirror_cam.look_at(mc + Vector3(d.x, -d.y, d.z), Vector3.UP)
	mat.set_shader_parameter("streak_px", streak_px)


## the planted dry control: the same scene with the water and the wet look switched off (shader switch, no rebake)
func set_dry(on: bool) -> void:
	dry = on
	mat.set_shader_parameter("dry", 1.0 if on else 0.0)


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and mirror_cam != null and cam != mirror_cam:
		sync_mirror(cam)
