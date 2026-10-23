class_name MaterialLibrary
extends Node
## MATERIAL LIBRARY (ROADMAP_400 E02): PBR presets a material slot (scripts/kmesh_material.gd) can wear, and a picture of
## each (a lit sphere). The picker panel is scripts/material_library_ui.gd ("Library..." on the Materials panel).
## SHIPPED presets: data/materials/library.json, read only. Metals carry "f0", their LINEAR specular reflectance from the
##   commonly used PBR charts (N. Hoffman, "Physics and Math of Shading", SIGGRAPH 2015; S. Lagarde's DONTNOD chart:
##   iron 0.560 0.570 0.580, gold 1.000 0.766 0.336, copper 0.955 0.638 0.538); their base colour is f0 in sRGB and
##   metallic is 1. Every other preset is a dielectric: metallic 0, an sRGB albedo with each channel in 30..240.
##   Skin has subsurface on (sss > 0).
## USER presets: user://material_library.json (to_file form, KMeshMaterial), written by save_user ("Save current slot to
##   library"); kept apart from the shipped ones and never written into res://.
## PICTURES: a sphere drawn off screen in a SubViewport with its own world (as SceneThumbs), cached in
##   user://matlib_thumbs/<sha256 of the slot>.png, so a preset is drawn once per install, not once per open.

signal made(key: String)   # a picture is ready (thumb(slot) has it)

const SHIPPED := "res://data/materials/library.json"
const USER := "user://material_library.json"
const DIR := "user://matlib_thumbs"
const SIZE := Vector2i(64, 64)
const STAGE_V := "1"   # part of the cache key: a changed stage draws every picture again
const METAL_LUM := [0.5, 1.0]   # linear luminance of a metal's F0 (the charts: raw metals are 0.5..1.0, sRGB 186..255)
const DIEL_SRGB := [30, 240]    # a dielectric's albedo, each sRGB channel

var renders := 0          # pictures drawn this session (the test counts them)
var disk_hits := 0
var _tex := {}            # key -> ImageTexture
var _vp: SubViewport
var _ball: MeshInstance3D
var _drawing := false


# ---------------------------------------------------------------- the presets

## the shipped presets: [{name, group, slot (a clean KMeshMaterial slot), f0 (metals), source}]
static func shipped() -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED))
	var out := []
	if not (d is Dictionary) or not ((d as Dictionary).get("presets") is Array):
		push_error("material library: %s is damaged" % SHIPPED)
		return out
	for p in (d as Dictionary)["presets"]:
		var e := preset(p)
		if not e.is_empty():
			out.append(e)
	return out


## one entry of the shipped file -> {name, group, slot, f0, source}; {} when it is malformed
static func preset(p: Variant) -> Dictionary:
	if not (p is Dictionary) or not (p as Dictionary).has("name"):
		return {}
	var over := {"name": String(p["name"]), "roughness": float(p.get("roughness", 0.6)), "sss": float(p.get("sss", 0.0))}
	var f0: Variant = p.get("f0")
	if f0 is Array and (f0 as Array).size() == 3:
		over["albedo"] = Color(float(f0[0]), float(f0[1]), float(f0[2])).linear_to_srgb()
		over["metallic"] = 1.0
	elif p.get("albedo") is Array and (p["albedo"] as Array).size() == 3:
		var a: Array = p["albedo"]
		over["albedo"] = Color8(int(a[0]), int(a[1]), int(a[2]))
		over["metallic"] = 0.0
	else:
		return {}
	return {"name": over["name"], "group": String(p.get("group", "")), "slot": KMeshMaterial.clean(over), "f0": f0 if f0 is Array else null,
		"source": String(p.get("source", "")), "user": false}


## "" when the preset is physically plausible, else why not
static func implausible(e: Dictionary) -> String:
	var s: Dictionary = e["slot"]
	var c: Color = s["albedo"]
	if e["f0"] != null:
		var lin := c.srgb_to_linear()
		var lum := 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
		if s["metallic"] != 1.0:
			return "a metal with metallic %.2f (must be 1)" % s["metallic"]
		if lum < METAL_LUM[0] or lum > METAL_LUM[1]:
			return "a metal whose F0 luminance %.3f is outside %s" % [lum, METAL_LUM]
		return ""
	if s["metallic"] != 0.0:
		return "a dielectric with metallic %.2f (must be 0)" % s["metallic"]
	for ch in [c.r8, c.g8, c.b8]:
		if ch < DIEL_SRGB[0] or ch > DIEL_SRGB[1]:
			return "a dielectric albedo channel %d outside sRGB %s" % [ch, DIEL_SRGB]
	if e["group"] == "skin" and s["sss"] <= 0.0:
		return "skin without subsurface"
	return ""


## the user's presets (user://material_library.json): entries like shipped()'s, user = true
static func user_presets() -> Array:
	var out := []
	if not FileAccess.file_exists(USER):
		return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(USER))
	var mats := KMeshMaterial.from_file(d if d is Array else [])
	for s in mats:
		out.append({"name": s["name"], "group": "mine", "slot": s, "f0": null, "source": USER, "user": true})
	return out


## shipped + user, the user's last
static func all() -> Array:
	return shipped() + user_presets()


## add (or replace, by name) a slot in the user library; returns OK or an error
static func save_user(slot: Dictionary) -> int:
	var mats := []
	for e in user_presets():
		if e["name"] != slot.get("name", ""):
			mats.append(e["slot"])
	mats.append(KMeshMaterial.clean(slot))
	var f := FileAccess.open(USER, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(KMeshMaterial.to_file(mats), "\t"))
	f.close()
	return OK


## the shipped (or user) preset of that name, else {}
static func find(name: String) -> Dictionary:
	for e in all():
		if String(e["name"]).to_lower() == name.to_lower():
			return e
	return {}


## names matching a filter (every word of it, in the name or the group)
static func matches(e: Dictionary, filter: String) -> bool:
	var hay := ("%s %s" % [e["name"], e["group"]]).to_lower()
	for w in filter.to_lower().split(" ", false):
		if not hay.contains(w):
			return false
	return true


# ---------------------------------------------------------------- the pictures

static func key_of(slot: Dictionary) -> String:
	return (STAGE_V + JSON.stringify(KMeshMaterial.to_file([slot]), "", true)).sha256_text()


static func cache_path(key: String) -> String:
	return "%s/%s.png" % [DIR, key]


## the picture of a slot if it is at hand (memory), else null
func picture(slot: Dictionary) -> Texture2D:
	return _tex.get(key_of(slot))


## the picture of a slot: memory, else the disk cache, else drawn now (two frames) and cached. null if it cannot be drawn
func thumb(slot: Dictionary) -> Texture2D:
	var key := key_of(slot)
	if _tex.has(key):
		return _tex[key]
	var img: Image = null
	if FileAccess.file_exists(cache_path(key)):
		img = Image.load_from_file(ProjectSettings.globalize_path(cache_path(key)))
		if img != null and not img.is_empty():
			disk_hits += 1
	if img == null or img.is_empty():
		img = await draw(slot)
		if img == null or img.is_empty():
			return null
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		img.save_png(ProjectSettings.globalize_path(cache_path(key)))
	_tex[key] = ImageTexture.create_from_image(img)
	made.emit(key)
	return _tex[key]


## forget the pictures in memory (the disk cache stays)
func forget() -> void:
	_tex.clear()


func _frame() -> Signal:
	return (Engine.get_main_loop() as SceneTree).process_frame


## the sphere wearing this slot, drawn now; null when it cannot be (not in the tree)
func draw(slot: Dictionary) -> Image:
	while _drawing:
		await _frame()
	_drawing = true
	_stage()
	_ball.material_override = KMeshMaterial.material(slot, true)
	await _frame()
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		_drawing = false
		return null
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		_drawing = false
		return null
	var img := _vp.get_texture().get_image()
	renders += 1
	_drawing = false
	return img


## the stage: a sphere under a key and a rim light, a procedural sky to reflect (metals read as metals), own world
func _stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "matlib_stage"
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.5, 0.62)
	sm.sky_horizon_color = Color(0.72, 0.72, 0.7)
	sm.ground_bottom_color = Color(0.12, 0.11, 0.1)
	sm.ground_horizon_color = Color(0.45, 0.43, 0.4)
	sky.sky_material = sm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 40, 0)
	key.light_energy = 1.4
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -150, 0)
	rim.light_energy = 0.5
	_vp.add_child(rim)
	_ball = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	sp.radial_segments = 48
	sp.rings = 24
	_ball.mesh = sp
	_vp.add_child(_ball)
	var cam := Camera3D.new()
	cam.fov = 30.0
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.25, 2.3), Vector3.ZERO)
	cam.current = true
