## SCENE THUMBNAILS (ROADMAP 51): a small picture of the body for each scene in the scene list (main's dropdown).
## The body is the app's own mannequin (Overlays.mannequin, posed by Body.from_dict and Overlays.pose_skeleton, the way
## PoseLibrary draws its thumbnails) at the scene's STRIKE card (the first card named strike, contact, thrust or hit),
## else its middle card. Drawn off screen in a SubViewport with its own world, so nothing in the window moves.
## CACHE: user://thumbs/<sha256 of the scene file>.png, never in scenes/. A changed file has a new hash, so it is drawn
## again; an unchanged one is read from disk (or memory) and never drawn twice. Pictures are drawn one per frame,
## queued from the list's opening, so the list itself never waits for them.
class_name SceneThumbs
extends Node

signal made(path: String)   # a picture is ready for this scene file (memory or disk or drawn)

const SIZE := Vector2i(96, 64)
const DIR := "user://thumbs"
const STRIKE_WORDS := ["strike", "contact", "thrust", "hit"]

var renders := 0          # pictures drawn this session (the test counts them)
var disk_hits := 0       # pictures read from user://thumbs without a draw
var render_ms: Array = []   # measured: the milliseconds each draw took
var _tex := {}            # scene path -> {"sha": String, "tex": ImageTexture}
var _queue: Array = []
var _busy := false
var _vp: SubViewport
var _sk: Skeleton3D
var _idx := {}
var _tb: Body


func _ready() -> void:
	_stage.call_deferred()   # the mannequin is loaded at start-up, not on the first open of the list


## the card a picture is drawn from: the first strike-like card, else the middle one (-1: no cards)
static func pick_card(cards: Array) -> int:
	if cards.is_empty():
		return -1
	for i in cards.size():
		var nm := String((cards[i] as Dictionary).get("name", "")).to_lower()
		for w in STRIKE_WORDS:
			if nm.contains(w):
				return i
	return cards.size() / 2


static func cache_path(sha: String) -> String:
	return "%s/%s.png" % [DIR, sha]


## the scene's picture if it is at hand: from memory, or read from the disk cache (no draw). Otherwise the file is
## queued and drawn when its turn comes; made is emitted for the picture when it is ready
func request(path: String) -> void:
	var sha := FileAccess.get_sha256(path)
	if sha == "":
		return
	var have: Variant = _tex.get(path)
	if have is Dictionary and (have as Dictionary)["sha"] == sha:
		made.emit(path)
		return
	if FileAccess.file_exists(cache_path(sha)):
		var img := Image.load_from_file(cache_path(sha))
		if img != null and not img.is_empty():
			_tex[path] = {"sha": sha, "tex": ImageTexture.create_from_image(img)}
			disk_hits += 1
			made.emit(path)
			return
	if not _queue.has(path):
		_queue.append(path)
	_pump()


## the picture of a scene file, or null while it is not ready
func picture(path: String) -> Texture2D:
	var have: Variant = _tex.get(path)
	return (have as Dictionary)["tex"] if have is Dictionary else null


## forget the pictures in memory (the disk cache stays): the next request reads them back from disk
func forget() -> void:
	_tex.clear()


## queued draws, one per frame (a draw is two frames: its own, then the readback)
func _pump() -> void:
	if _busy:
		return
	_busy = true
	while not _queue.is_empty():
		var path: String = _queue.pop_front()
		await _render(path)
		await get_tree().process_frame
	_busy = false


## wait until every queued picture is drawn (tests)
func settle() -> void:
	while _busy or not _queue.is_empty():
		await get_tree().process_frame


func _stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "scene_thumb_stage"
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
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
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = PoseLibrary.CAM_SIZE
	cam.near = 0.05
	cam.far = 20.0
	_vp.add_child(cam)
	cam.look_at_from_position(PoseLibrary.CAM_AT + (PoseLibrary.CAM_FROM - PoseLibrary.CAM_AT), PoseLibrary.CAM_AT)
	cam.current = true
	var skin := StandardMaterial3D.new()
	skin.albedo_color = PoseLibrary.SKIN
	skin.roughness = 0.55
	var mq := Overlays.mannequin(_vp, skin)
	_sk = mq[1]
	_idx = mq[2]
	_tb = Body.new()
	_tb.load_files("res://data/skeleton.json", "res://data/body_limits.json")


## draw one scene's picture: its strike (or middle) card posed on the mannequin, saved to the cache under its hash
func _render(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var sha := FileAccess.get_sha256(path)
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary and not (d as Dictionary).has("cards") and (d as Dictionary).get("scene") is Dictionary:
		d = (d as Dictionary)["scene"]   # an autosave (File > Restore..., ROADMAP 59): drawn from the scene it holds
	if not (d is Dictionary) or not (d as Dictionary).has("cards"):
		return
	var cards: Array = (d as Dictionary)["cards"]
	var i := pick_card(cards)
	if i < 0 or not (cards[i] as Dictionary).get("pose") is Dictionary:
		return
	var t0 := Time.get_ticks_usec()
	_stage()
	_tb.from_dict((cards[i] as Dictionary)["pose"])
	Overlays.pose_skeleton(_sk, _idx, _tb)
	await get_tree().process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	_tex[path] = {"sha": sha, "tex": ImageTexture.create_from_image(img)}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	img.save_png(ProjectSettings.globalize_path(cache_path(sha)))
	renders += 1
	render_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	made.emit(path)
