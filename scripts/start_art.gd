class_name StartArt
extends Node
## START SCREEN PICTURES (scripts/start_screen.gd): the three project cards, drawn from the app's REAL fighter body
## (assets/mannequin.glb, the skinned mesh Overlays.mannequin builds, posed by Overlays.pose_skeleton: the same body
## the window shows), not stick figures. Each picture is rendered ONCE in a SubViewport with its own world, on a graphite
## backdrop, matte off-white body (#D8DCE3), a soft key and a rim light:
##   animation  the fighter in a kick (the STRIKE card of templates/roundhouse.json; else its middle card)
##   modeling   the neutral body (A/T pose) with a sky-blue tint on the right arm (the MODEL page's part colours)
##   building   the fighter small on a floor with two crates and a lamp
## CACHE: user://start_art/<kind>_<key>.png, key = the sha256 of the body file (mannequin.glb and skeleton.json) and VER,
## so a changed body is drawn again and an unchanged one is read from disk. A draw that gives no picture (headless: no
## renderer) leaves the card on its plain backdrop and is not retried this session.

signal changed(kind: String)   # a picture is ready for this card

const DIR := "user://start_art"
const SIZE := Vector2i(640, 300)
const VER := "sa2"   # sa2: the kick is the roundhouse template's strike card
const KINDS := ["animation", "modeling", "building"]
const BG := Color(0.105, 0.11, 0.125)
const SKIN := Color(0.847, 0.863, 0.89)     # #D8DCE3
const TINT := Color(0.45, 0.75, 1.0)        # sky blue: the arm the modeling card shows
const FLOOR := Color(0.165, 0.17, 0.19)
const CRATE := Color(0.62, 0.45, 0.26)
const KICK_SCENE := "res://templates/roundhouse.json"   # the roundhouse template: its STRIKE card is the kick

var textures := {}      # kind -> Texture2D
var renders := 0        # pictures drawn this session (the test counts them)
var disk_hits := 0      # pictures read from the cache (no draw)
var _failed := {}       # kind -> true: no picture came out of a draw
var _busy := false
var _kick: Dictionary = {}


## the cache key: the body file's content (the mesh and the skeleton) and the picture version
static func art_key() -> String:
	var src := FileAccess.get_sha256("res://assets/mannequin.glb") + FileAccess.get_sha256("res://data/skeleton.json") + VER
	return src.sha256_text().substr(0, 16)


static func cache_path(kind: String) -> String:
	return "%s/%s_%s.png" % [DIR, kind, art_key()]


func get_art(kind: String) -> Texture2D:
	return textures.get(kind)


## every card's picture: from the disk cache, else drawn (one at a time, after the frame that asked)
func request_all() -> void:
	if _busy:
		return
	_busy = true
	for kind in KINDS:
		if textures.has(kind) or _failed.has(kind):
			continue
		var p := cache_path(kind)
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(ProjectSettings.globalize_path(p))
			if img != null and not img.is_empty():
				textures[kind] = ImageTexture.create_from_image(img)
				disk_hits += 1
				changed.emit(kind)
				continue
		if not is_inside_tree():
			break
		await get_tree().process_frame
		var img2 := await draw(kind)
		if img2 == null or img2.is_empty():
			_failed[kind] = true
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		img2.save_png(ProjectSettings.globalize_path(p))
		renders += 1
		textures[kind] = ImageTexture.create_from_image(img2)
		changed.emit(kind)
	_busy = false


## the kick of the shipped example: its card named kick, else its strike card (a pose dictionary, Body.to_dict form)
func kick_pose() -> Dictionary:
	if not _kick.is_empty():
		return _kick
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(KICK_SCENE)) if FileAccess.file_exists(KICK_SCENE) else null
	if d is Dictionary:
		var cards: Array = (d as Dictionary).get("cards", [])
		for c in cards:
			var nm := String((c as Dictionary).get("name", "")).to_lower()
			if (nm.contains("roundhouse") or nm.contains("kick")) and (c as Dictionary).get("pose") is Dictionary:
				_kick = (c as Dictionary)["pose"]
				return _kick
		if not cards.is_empty():
			var i := SceneThumbs.pick_card(cards)
			if i >= 0 and (cards[i] as Dictionary).get("pose") is Dictionary:
				_kick = (cards[i] as Dictionary)["pose"]
	return _kick


## one picture, drawn now (two frames); null when it cannot be drawn
func draw(kind: String) -> Image:
	var vp := SubViewport.new()
	vp.name = "start_art_" + kind
	vp.size = SIZE
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()     # soft key from the front right
	key.rotation_degrees = Vector3(-38, 32, 0)
	key.light_energy = 1.0
	vp.add_child(key)
	var rim := DirectionalLight3D.new()     # rim from behind: the silhouette reads on the dark backdrop
	rim.rotation_degrees = Vector3(-22, 158, 0)
	rim.light_energy = 0.9
	vp.add_child(rim)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 0.62
	var mq := Overlays.mannequin(vp, skin)
	var sk: Skeleton3D = mq[1]
	var idx: Dictionary = mq[2]
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 30.0
	vp.add_child(cam)
	match kind:
		"animation":
			if not kick_pose().is_empty():
				b.from_dict(kick_pose())
			b.offset = Vector3.ZERO
			cam.size = PoseLibrary.CAM_SIZE
			cam.look_at_from_position(Vector3(0.0, 0.98, 0.0) + Vector3(1.9, 0.6, 3.6), Vector3(0.0, 0.98, 0.0), Vector3.UP)
			Overlays.pose_skeleton(sk, idx, b)
		"modeling":
			cam.size = PoseLibrary.CAM_SIZE
			cam.look_at_from_position(Vector3(0.0, 0.98, 0.0) + Vector3(1.9, 0.6, 3.6), Vector3(0.0, 0.98, 0.0), Vector3.UP)
			Overlays.pose_skeleton(sk, idx, b)
		"building":
			_add_set(vp)
			cam.size = 3.4
			cam.look_at_from_position(Vector3(2.6, 2.1, 6.4), Vector3(0.1, 0.9, -0.4), Vector3.UP)
			b.offset = Vector3(-0.2, 0.0, 0.3)
			Overlays.pose_skeleton(sk, idx, b)
		_:
			vp.queue_free()
			return null
	cam.current = true
	if kind == "modeling":
		var mat := StandardMaterial3D.new()
		mat.albedo_color = TINT
		mat.roughness = 0.55
		var parts := Overlays.split_parts(mq[0], sk, idx)   # the body's parts as pieces: the right arm takes the tint
		for pj in ["upperarm_r", "lowerarm_r", "hand_r"]:
			if parts.has(pj):
				(parts[pj] as MeshInstance3D).material_override = mat
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(vp):
		return null
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_inside_tree() and is_instance_valid(vp):
		img = vp.get_texture().get_image()
		vp.queue_free()
	return img


## the stage of the building card: a floor, two crates and a lamp on a pole (its light lights the floor)
func _add_set(vp: SubViewport) -> void:
	var fl := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(9.0, 0.04, 7.0)
	fl.mesh = fm
	fl.position = Vector3(0.0, -0.02, 0.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = FLOOR
	fmat.roughness = 0.9
	fl.material_override = fmat
	vp.add_child(fl)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = CRATE
	cmat.roughness = 0.8
	for c in [[Vector3(1.25, 0.25, -0.45), 0.5], [Vector3(0.55, 0.19, -1.25), 0.38]]:
		var cr := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * float(c[1])
		cr.mesh = bm
		cr.position = c[0]
		cr.material_override = cmat
		vp.add_child(cr)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.02
	pm.bottom_radius = 0.02
	pm.height = 2.3
	pole.mesh = pm
	pole.position = Vector3(-1.5, 1.15, -0.9)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.5, 0.52, 0.56)
	pole.material_override = pmat
	vp.add_child(pole)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	bulb.mesh = sm
	bulb.position = Vector3(-1.5, 2.35, -0.9)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1.0, 0.85, 0.4)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.8, 0.35)
	lmat.emission_energy_multiplier = 3.0
	bulb.material_override = lmat
	vp.add_child(bulb)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-1.5, 2.3, -0.9)
	lamp.light_energy = 2.2
	lamp.omni_range = 7.0
	lamp.light_color = Color(1.0, 0.85, 0.5)
	vp.add_child(lamp)
