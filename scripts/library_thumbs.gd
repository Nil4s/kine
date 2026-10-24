class_name LibraryThumbs
extends Node
## LIBRARY PICTURES (the object library's tiles, scripts/object_library.gd). Each object is drawn ONCE from its own data:
## a prop's collision solids (Props.kind_of), a weapon's shaft (Body.KINDS: len and barrel radius), an armour plate's size.
## These are schematic shapes, not the meshes: a tile says what the object is, and the placed object is the real one.
## CACHE: user://thumbs/lib/<sha256 of the shapes>_64.png, never in the scene folders. A changed object has new shapes, so a
## new key and a new picture; an unchanged one is read from disk. Drawn off screen in a SubViewport with its own world (the
## way BodyThumbs and SceneThumbs draw), one object per frame, after the frame that asked, so the panel never waits for them.
## A shape is one of: ["box", centre, size], ["ball", centre, radius], ["cyl", centre, height, radius] (Vector3 / float).

signal made(id: String)   # a picture is ready for this object (memory, disk or drawn)

const SIZE := Vector2i(64, 64)
const DIR := "user://thumbs/lib"

var renders := 0       # pictures drawn this session (the test counts them)
var disk_hits := 0     # pictures read from the cache without a draw
var _tex := {}         # id -> ImageTexture
var _asked := {}       # id -> true: asked once; a picture is drawn or read once per session, however many tiles ask
var _failed := {}      # sha -> true: no picture came out of a draw (headless: no renderer)
var _queue: Array = []  # [{"id", "shapes"}]
var _busy := false
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _mat: StandardMaterial3D


static func cache_path(sha: String) -> String:
	return "%s/%s_%d.png" % [DIR, sha, SIZE.x]   # the size in the name: a resized picture is a new entry


static func key_of(shapes: Array) -> String:
	return JSON.stringify(shapes).sha256_text()


## the picture of an object if it is at hand, else null
func picture(id: String) -> Texture2D:
	return _tex.get(id)


## ask for an object's picture; made(id) says when it is there. An object already asked for is not asked twice.
func request(id: String, shapes: Array) -> void:
	if _asked.has(id):
		return
	_asked[id] = true
	_queue.append({"id": id, "shapes": shapes})
	_pump()


func _frame() -> Signal:
	return (Engine.get_main_loop() as SceneTree).process_frame


func _pump() -> void:
	if _busy:
		return
	_busy = true
	await _frame()   # never on the frame that asked
	while not _queue.is_empty():
		var q: Dictionary = _queue.pop_front()
		var sha := key_of(q["shapes"])
		if _failed.has(sha):
			continue
		var img: Image = null
		if FileAccess.file_exists(cache_path(sha)):
			img = Image.load_from_file(ProjectSettings.globalize_path(cache_path(sha)))
			if img != null and not img.is_empty():
				disk_hits += 1
		if img == null or img.is_empty():
			img = await draw(q["shapes"])
			if not is_instance_valid(self):
				return
			if img != null and not img.is_empty():
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
				img.save_png(ProjectSettings.globalize_path(cache_path(sha)))
				renders += 1
		if img == null or img.is_empty():
			_failed[sha] = true
			continue
		_tex[q["id"]] = ImageTexture.create_from_image(img)
		made.emit(q["id"])
		await _frame()
	_busy = false


## wait until every asked picture is done (tests)
func settle() -> void:
	while _busy or not _queue.is_empty():
		await _frame()


## the picture of an object's shapes, drawn now; null when it cannot be drawn
func draw(shapes: Array) -> Image:
	_stage()
	for c in _world.get_children():
		c.free()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for s in shapes:
		var c: Vector3 = s[1]
		var half := _half(s)
		lo = lo.min(c - half)
		hi = hi.max(c + half)
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(s)
		mi.material_override = _mat
		mi.position = c
		_world.add_child(mi)
	if shapes.is_empty():
		return null
	var mid := (lo + hi) * 0.5
	var ext := hi - lo
	# the view's height: the largest extent plus a margin, so a 2 m staff and a 9 cm bat both fill the picture
	_cam.size = maxf(ext.x, maxf(ext.y, ext.z)) * 1.25 + 0.05
	_cam.look_at_from_position(mid + Vector3(0.45, 0.25, 1.0).normalized() * 6.0, mid, Vector3.UP)
	await _frame()
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		return null
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		return null
	return _vp.get_texture().get_image()


static func _half(s: Array) -> Vector3:
	match String(s[0]):
		"box":
			return (s[2] as Vector3) * 0.5
		"ball":
			return Vector3.ONE * float(s[2])
		_:
			return Vector3(float(s[3]), float(s[2]) * 0.5, float(s[3]))


static func _mesh(s: Array) -> Mesh:
	match String(s[0]):
		"box":
			var b := BoxMesh.new()
			b.size = s[2]
			return b
		"ball":
			var sp := SphereMesh.new()
			sp.radius = float(s[2])
			sp.height = float(s[2]) * 2.0
			return sp
		_:
			var cy := CylinderMesh.new()
			cy.height = float(s[2])
			cy.top_radius = float(s[3])
			cy.bottom_radius = float(s[3])
			return cy


func _stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "library_thumb_stage"
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Tok.c("world")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE   # a light, not a surface: white is the light's own colour in both themes
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.1
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.35
	_vp.add_child(fill)
	_world = Node3D.new()
	_world.name = "shapes"
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Tok.c("cube")
	_mat.roughness = 0.6
	_vp.add_child(_world)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.current = true
	_vp.add_child(_cam)
