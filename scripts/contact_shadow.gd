## contact_shadow.gd - CONTACT SHADOWS (ROADMAP R4): a soft dark blob on the floor under each foot (and under the tip of
## a held bat), darkest when the sole is on the floor and gone by FADE_H above it. The directional light's shadow tells the
## eye which way the light falls; this tells it WHERE the foot touches (the "ambient occlusion" a real floor gives for
## free; Blender/Maya show a floating foot as readily as a planted one). Built from the Body each refresh; never touches
## the pose. Off = nothing drawn.
## Size: the foot's own footprint (ankle to toe tip long) plus a rim; width = foot breadth 0.055 x stature (Winter,
## "Biomechanics and Motor Control of Human Movement" 4th ed., Table 4.1 segment dimensions: foot breadth ~ 0.055 H) plus
## the rim. Darkness: ALPHA_MAX x (1 - smoothstep(0, FADE_H, sole height)).
class_name ContactShadow
extends Node3D

const FADE_H := 0.15      # m: the sole this far up and the blob is gone (Nick's spec)
const ALPHA_MAX := 0.7    # the darkest centre, sole on the floor (mine: readable on both floor palettes)
const RIM := 0.03         # m: the blob reaches this far past the footprint on every side
const BREADTH := 0.055 * 1.75   # m: foot breadth of a 1.75 m person (Winter)
const LIFT := 0.003       # m: drawn this far above the floor so the floor does not hide it
const TIP_R := 0.05       # m: the bat tip's blob radius

var on := true
## what is drawn: key ("foot_l", "foot_r", "bat") -> {"centre": Vector2 (x, z on the floor), "alpha": float, "h": float}
var last := {}
var _mi := {}


static func _soft_texture() -> ImageTexture:
	var n := 64
	var im := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0).length()
			var a := 1.0 - smoothstep(0.0, 1.0, r)
			im.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(im)


func _quad(key: String) -> MeshInstance3D:
	if _mi.has(key):
		return _mi[key]
	var mi := MeshInstance3D.new()
	mi.name = "contact_" + key
	mi.mesh = PlaneMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _tex
	m.albedo_color = Color(0, 0, 0, 0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	_mi[key] = mi
	return mi


var _tex: ImageTexture


static func alpha_at(h: float) -> float:
	return ALPHA_MAX * (1.0 - smoothstep(0.0, FADE_H, maxf(h, 0.0)))


func _put(key: String, c: Vector2, dir: Vector2, length: float, width: float, h: float) -> void:
	var mi := _quad(key)
	var a := alpha_at(h)
	last[key] = {"centre": c, "alpha": a, "h": h}
	mi.visible = a > 0.002
	(mi.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0, a)
	(mi.mesh as PlaneMesh).size = Vector2(width, length)   # plane: x = width, z = length
	mi.position = Vector3(c.x, LIFT, c.y)
	mi.rotation = Vector3(0, atan2(dir.x, dir.y), 0)


## draw for this pose (or clear, when off)
func show_body(B: Body) -> void:
	if _tex == null:
		_tex = _soft_texture()
	last = {}
	for k in _mi:
		(_mi[k] as MeshInstance3D).visible = false
	if not on:
		return
	for sd in ["_l", "_r"]:
		var heel: Vector3 = B.P["foot" + sd]
		var toe: Vector3 = B.E["ball" + sd]
		var h := B.foot_sole_low(sd)
		var a := Vector2(heel.x, heel.z)
		var b := Vector2(toe.x, toe.z)
		var d := b - a
		var ln := d.length()
		var dir := d / ln if ln > 1e-4 else Vector2(0, 1)
		_put("foot" + sd, (a + b) * 0.5, dir, ln + 2.0 * RIM, BREADTH + 2.0 * RIM, h)
	if B.wep_on:
		var tip := B.wep_point(B.wep_len)
		_put("bat", Vector2(tip.x, tip.z), Vector2(0, 1), 2.0 * TIP_R, 2.0 * TIP_R, tip.y)
