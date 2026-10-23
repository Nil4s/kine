class_name SculptMatcap
extends Node
## MATCAPS FOR SCULPTING (ROADMAP_400 C12): the sculpt sphere (scripts/kmesh_sculpt_ui.gd) can be drawn with a matcap, a
## picture of a lit ball looked up by the surface's VIEW-SPACE normal: a normal pointing at the camera reads the picture's
## centre, a normal pointing right (+x) its right edge, up (+y) its top. Lighting is baked into the picture, so the form
## reads the same from every side while you orbit, the way ZBrush / Blender sculpt mode show it.
## The SHADER (spatial, unshaded): uv = (n.x, -n.y) * 0.5 + 0.5, colour = texture(uv) * the vertex colour (white when the
##   mesh has none; the brush preset thumbnails use it to show the mask).
## The PICTURES are computed here at startup, analytically per pixel (no files): MATCAPS lists them,
##   clay        warm grey clay: wrapped diffuse from the upper left, a broad dull highlight, a soft rim
##   red wax     deep red with light bleeding into the shadow (wide wrap), a tight wet highlight, a bright rim
##   skin        peach diffuse whose shadow turns red (scattering), a soft sheen
##   chrome      a mirror: the reflected view ray reads a sky / horizon / ground gradient, plus the key light as a hot spot
##   normal      the normal itself as a colour, n * 0.5 + 0.5 (right = red, up = green, facing you = blue)
##   off         no matcap: the view's own lit material
##   Outside the ball's disc each pixel takes the colour of the rim point in its direction, so the linear filter never
##   pulls in a background colour at grazing angles.
## IN SCULPT: V next matcap, Shift+V the one before (the strip at the top left of the clear view shows them; a click picks).
## The choice is a static: it holds for the session, across leaving and re-opening the sphere.

const SIZE := 128
const MATCAPS := ["clay", "red wax", "skin", "chrome", "normal", "off"]
const LIGHT := Vector3(-0.5, 0.62, 0.6)   # the key light of the baked pictures, view space (upper left, in front)

static var chosen := "clay"            # the session's matcap
static var _tex := {}                  # name -> ImageTexture (made once per run)
static var _img := {}                  # name -> Image
static var _shader: Shader
static var _mats := {}                 # name -> ShaderMaterial

var ui                                  # the KMeshSculptUI
var view: KMeshView
var strip: PanelContainer
var _btns := {}


# ---------------------------------------------------------------- the pictures

static func _sat(x: float) -> float:
	return clampf(x, 0.0, 1.0)


## the colour of one matcap at a view-space normal n (unit, z toward the camera)
static func shade(kind: String, n: Vector3) -> Color:
	var l := LIGHT.normalized()
	var v := Vector3(0, 0, 1)
	var h := (l + v).normalized()
	var ndl := n.dot(l)
	var ndh := maxf(n.dot(h), 0.0)
	var rim := pow(1.0 - _sat(n.z), 3.0)
	match kind:
		"normal":
			return Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5)
		"clay":
			var base := Vector3(0.74, 0.64, 0.56)
			var dif := _sat((ndl + 0.35) / 1.35)
			var c := base * (0.22 + 0.78 * dif) + Vector3.ONE * 0.12 * pow(ndh, 12.0) + Vector3(0.9, 0.85, 0.8) * 0.12 * rim
			return Color(_sat(c.x), _sat(c.y), _sat(c.z))
		"red wax":
			var base := Vector3(0.62, 0.07, 0.05)
			var dif := _sat((ndl + 0.6) / 1.6)
			var c := base * (0.18 + 0.95 * dif) + Vector3(0.25, 0.02, 0.0) * (1.0 - dif) * 0.6 + Vector3.ONE * 0.75 * pow(ndh, 70.0) + Vector3(1.0, 0.45, 0.35) * 0.35 * rim
			return Color(_sat(c.x), _sat(c.y), _sat(c.z))
		"skin":
			var dif := _sat((ndl + 0.45) / 1.45)
			var lit := Vector3(0.93, 0.72, 0.6)
			var shadow := Vector3(0.48, 0.2, 0.17)   # the shadow side turns red: light scattered under the skin
			var c := shadow.lerp(lit, pow(dif, 0.8)) + Vector3(1.0, 0.95, 0.9) * 0.18 * pow(ndh, 24.0) + Vector3(1.0, 0.8, 0.7) * 0.15 * rim
			return Color(_sat(c.x), _sat(c.y), _sat(c.z))
		"chrome":
			var r := n * (2.0 * n.z) - v   # the view ray reflected (the camera looks down -z)
			var y := r.y
			var sky := Vector3(0.78, 0.8, 0.82).lerp(Vector3(0.32, 0.42, 0.58), pow(maxf(y, 0.0), 0.6))   # the sky, horizon pale
			var ground := Vector3(0.36, 0.33, 0.3).lerp(Vector3(0.06, 0.06, 0.07), pow(maxf(-y, 0.0), 0.5))   # the ground, dark below
			var c := ground.lerp(sky, smoothstep(-0.2, 0.2, y))   # a soft horizon: no hard step for the filter to straddle
			c += Vector3.ONE * 1.4 * pow(maxf(r.normalized().dot(l), 0.0), 120.0)   # the key light, a hot spot
			c *= 0.85 + 0.15 * (1.0 - rim)
			return Color(_sat(c.x), _sat(c.y), _sat(c.z))
	return Color(0.7, 0.7, 0.7)


## the view-space normal a matcap pixel stands for (the rim's normal outside the disc)
static func normal_at(px: float, py: float, size := SIZE) -> Vector3:
	var x := (px + 0.5) / size * 2.0 - 1.0
	var y := 1.0 - (py + 0.5) / size * 2.0
	var r2 := x * x + y * y
	if r2 >= 1.0:
		var k := 1.0 / sqrt(r2)
		return Vector3(x * k, y * k, 0.0)
	return Vector3(x, y, sqrt(1.0 - r2))


static func image(kind: String) -> Image:
	if _img.has(kind):
		return _img[kind]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for py in SIZE:
		for px in SIZE:
			img.set_pixel(px, py, shade(kind, normal_at(px, py)))
	_img[kind] = img
	return img


static func texture(kind: String) -> ImageTexture:
	if not _tex.has(kind):
		_tex[kind] = ImageTexture.create_from_image(image(kind))
	return _tex[kind]


## what the shader reads at uv: the picture bilinear-filtered like the GPU (texel centres at (i + 0.5) / size, clamped)
static func sample(kind: String, uv: Vector2) -> Color:
	var img := image(kind)
	var x := uv.x * SIZE - 0.5
	var y := uv.y * SIZE - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var c := func(i: int, j: int) -> Color: return img.get_pixel(clampi(i, 0, SIZE - 1), clampi(j, 0, SIZE - 1)).srgb_to_linear()
	var top: Color = (c.call(x0, y0) as Color).lerp(c.call(x0 + 1, y0), fx)
	var bot: Color = (c.call(x0, y0 + 1) as Color).lerp(c.call(x0 + 1, y0 + 1), fx)
	return top.lerp(bot, fy).linear_to_srgb()


## the uv the shader reads for a view-space normal
static func uv_of(n: Vector3) -> Vector2:
	var u := n.normalized()
	return Vector2(u.x, -u.y) * 0.5 + Vector2(0.5, 0.5)


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D matcap : source_color, filter_linear, repeat_disable;
void fragment() {
	vec3 n = normalize(NORMAL);
	ALBEDO = texture(matcap, vec2(n.x, -n.y) * 0.5 + 0.5).rgb * COLOR.rgb;
}
"""
	return _shader


## a material wearing that matcap; null for "off"
static func material(kind: String) -> ShaderMaterial:
	if kind == "off" or not MATCAPS.has(kind):
		return null
	if not _mats.has(kind):   # one per matcap: the view re-dresses on every rebuild (each frame of a stroke)
		var mt := ShaderMaterial.new()
		mt.shader = shader()
		mt.set_shader_parameter("matcap", texture(kind))
		_mats[kind] = mt
	return _mats[kind]


# ---------------------------------------------------------------- in sculpt

func setup(sculpt_ui) -> void:
	ui = sculpt_ui
	name = "sculpt_matcap"
	strip = PanelContainer.new()
	strip.name = "matcap_strip"
	strip.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(6)
	strip.add_theme_stylebox_override("panel", st)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	strip.add_child(hb)
	var lb := Label.new()
	lb.text = "Matcap"
	lb.tooltip_text = "V next matcap, Shift+V the one before"
	lb.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(lb)
	var grp := ButtonGroup.new()
	for k in MATCAPS:
		var b := Button.new()
		b.name = "btn_matcap_" + String(k).replace(" ", "_")
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s (V cycles the matcaps)" % k
		if k == "off":
			b.text = "off"
		else:
			var small := image(k).duplicate() as Image
			small.resize(24, 24, Image.INTERPOLATE_BILINEAR)
			b.icon = ImageTexture.create_from_image(small)
		b.pressed.connect(pick.bind(k))
		hb.add_child(b)
		_btns[k] = b
	ui.m.ui_root.add_child(strip)


## the sculpt view now shows; it wears the session's matcap, also after each rebuild
func attach(v: KMeshView) -> void:
	view = v
	if not view.rebuilt.is_connected(_dress):
		view.rebuilt.connect(_dress)
	_dress()
	strip.visible = true
	_mark()
	place()


func detach() -> void:
	view = null
	strip.visible = false


func _dress() -> void:
	if view == null or not is_instance_valid(view):
		return
	var mt := material(chosen)
	if mt != null:   # "off": the view's rebuild has just set its own material; leave it
		(view.get_node("surf") as MeshInstance3D).material_override = mt


func _mark() -> void:
	if _btns.has(chosen):
		(_btns[chosen] as Button).set_pressed_no_signal(true)


## pick a matcap by name (the strip's buttons, V, a test)
func pick(kind: String) -> void:
	if not MATCAPS.has(kind):
		return
	var was := chosen
	chosen = kind
	_mark()
	if view != null and is_instance_valid(view):
		if kind == "off" and was != "off":
			view.rebuild()   # the view's own material back
		else:
			_dress()
	ui.m._say("Sculpt: matcap %s (V next, Shift+V back; it stays for this session)" % kind if kind != "off" else "Sculpt: matcap off, the lit material (V next)")


func cycle(step := 1) -> void:
	pick(MATCAPS[posmod(MATCAPS.find(chosen) + step, MATCAPS.size())])


## top left of the clear view
func place() -> void:
	var cl: Rect2 = ui.m.nav_clear_rect()
	strip.size = strip.get_combined_minimum_size()
	strip.global_position = cl.position + Vector2(12, 12)


func _process(_dt: float) -> void:
	if strip != null and strip.visible:
		place()


## sculpt keys: V / Shift+V. true = used
func input(ev: InputEvent) -> bool:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return false
	var ke := ev as InputEventKey
	if ke.keycode == KEY_V and not ke.ctrl_pressed and not ke.alt_pressed and not ke.meta_pressed:
		cycle(-1 if ke.shift_pressed else 1)
		return true
	return false
