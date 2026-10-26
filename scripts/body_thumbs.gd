class_name BodyThumbs
extends Node
## G07 BODY PICTURES (the Browser's Bodies rows): a small front three-quarter picture of each .kbody's mesh, drawn at runtime
## off screen in a SubViewport with its own world (nothing in the window moves), the way SceneThumbs draws the scenes.
## CACHE: user://thumbs/b_<sha256 of the .kbody file>_<size>.png, never in bodies/. A body file is never overwritten (BodyFile), so
## a path's picture holds; a file with new content has a new hash and is drawn again. One picture per two frames, after the
## frame that asked, so the Browser never waits for them. A draw that gives no picture (headless: no renderer) is not
## retried for that file this session.

signal made(path: String)   # a picture is ready for this .kbody (memory, disk or drawn)

const SIZE := Vector2i(64, 64)
const DIR := "user://thumbs"

var renders := 0      # pictures drawn this session (the test counts them)
var disk_hits := 0    # pictures read from the cache without a draw
var _tex := {}        # path -> {"sha", "tex"}
var _failed := {}     # sha -> true: no picture came out of a draw
var _queue: Array = []
var _busy := false
var _vp: SubViewport
var _mi: MeshInstance3D
var _cam: Camera3D


static func cache_path(sha: String) -> String:
	return "%s/b_%s_%d.png" % [DIR, sha, SIZE.x]   # the size in the name: a resized picture is a new entry


## the picture of a .kbody if it is at hand, else null
func picture(path: String) -> Texture2D:
	var have: Variant = _tex.get(path)
	return (have as Dictionary)["tex"] if have is Dictionary else null


## ask for a body's picture; made(path) says when it is there
func request(path: String) -> void:
	if _tex.has(path) or _queue.has(path):
		return
	_queue.append(path)
	_pump()


func _frame() -> Signal:
	return (Engine.get_main_loop() as SceneTree).process_frame


func _pump() -> void:
	if _busy:
		return
	_busy = true
	await _frame()   # never on the frame that asked
	while not _queue.is_empty():
		var path: String = _queue.pop_front()
		var sha := FileAccess.get_sha256(path)
		if sha == "" or _failed.has(sha):
			continue
		var img: Image = null
		if FileAccess.file_exists(cache_path(sha)):
			img = Image.load_from_file(ProjectSettings.globalize_path(cache_path(sha)))
			if img != null and not img.is_empty():
				disk_hits += 1
		if img == null or img.is_empty():
			var b := BodyFile.load_file(path)
			if not b.is_empty():
				img = await draw(b["mesh"])
				if not is_instance_valid(self):
					return
			if img != null and not img.is_empty():
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
				img.save_png(ProjectSettings.globalize_path(cache_path(sha)))
				renders += 1
		if img == null or img.is_empty():
			_failed[sha] = true
			continue
		_tex[path] = {"sha": sha, "tex": ImageTexture.create_from_image(img)}
		made.emit(path)
		await _frame()
	_busy = false


## wait until every asked picture is done (tests)
func settle() -> void:
	while _busy or not _queue.is_empty():
		await _frame()


## the picture of a body mesh, drawn now (two frames); null when it cannot be drawn
func draw(k: KMesh) -> Image:
	_stage()
	_mi.mesh = k.to_array_mesh()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in k.verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var c := (lo + hi) * 0.5
	var sz := hi - lo
	_cam.size = maxf(sz.y, maxf(sz.x, sz.z) * float(SIZE.y) / float(SIZE.x)) * 1.08
	_cam.look_at_from_position(c + Vector3(0.45, 0.12, 1.0).normalized() * 6.0, c, Vector3.UP)
	await _frame()
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		return null
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		return null
	return _vp.get_texture().get_image()


func _stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "body_thumb_stage"
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Quality.thumb_msaa() as Viewport.MSAA
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PoseLibrary.BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
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
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 20.0
	_vp.add_child(_cam)
	_cam.current = true
	var skin := StandardMaterial3D.new()
	skin.albedo_color = PoseLibrary.SKIN
	skin.roughness = 0.55
	_mi = MeshInstance3D.new()
	_mi.material_override = skin
	_vp.add_child(_mi)
