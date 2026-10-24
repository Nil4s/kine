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
signal made_pose(key: String)   # a picture is ready for this POSE (the strip's cards): key = pose_key(pose)

const SIZE := Vector2i(96, 64)
const DIR := "user://thumbs"
const STRIKE_WORDS := ["strike", "contact", "thrust", "hit"]

var pick_on := false      # K29 (scripts/thumb_pick.gd): draw the clip's most readable frame instead of its strike / middle card
var picked := {}          # scene path -> the time (s) the picker chose (the test reads it)
var renders := 0          # pictures drawn this session (the test counts them)
var disk_hits := 0       # pictures read from user://thumbs without a draw
var render_ms: Array = []   # measured: the milliseconds each draw took
var _tex := {}            # scene path -> {"sha": String, "tex": ImageTexture}
var _queue: Array = []
var _busy := false
var _pending: Array = []
var _intaking := false
const INTAKE_US := 4000
var _vp: SubViewport
var _sk: Skeleton3D
var _idx := {}
var _tb: Body
var _ptex := {}           # pose key -> ImageTexture (the strip's cards)
var _pq: Array = []       # [key, pose] waiting for a draw or a disk read
var _pbusy := false
var _drawing := false     # the one stage draws one picture at a time (scenes and poses share it)
var _cam: Camera3D        # the stage's camera: aimed at each picture's own body (_aim)
const FRAME_VER := "f2"   # the picture's framing: f2 = aimed at the body's root (f1 framed the origin: a walk's first cards fell off the edge); the cache keys carry it


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
	return "%s/%s_%s.png" % [DIR, FRAME_VER, sha]   # the framing version is in the name: an old picture is never read back


## the scene's picture if it is at hand: from memory, or read from the disk cache (no draw). Otherwise the file is
## queued and drawn when its turn comes; made is emitted for the picture when it is ready
func request(path: String) -> void:
	# nothing is read here: opening the list only notes the paths. The hash, the cache read and the draw all happen
	# a few at a time on the frames AFTER the list is up (35 file hashes + PNG reads on the open frame were 80+ ms)
	if not _pending.has(path):
		_pending.append(path)
	_intake()


## the notes of request(), a time budget per frame: memory hit, disk hit (made at once), or queued for a draw
func _intake() -> void:
	if _intaking:
		return
	_intaking = true
	while not _pending.is_empty():
		await _frame()
		var t0 := Time.get_ticks_usec()
		while not _pending.is_empty() and Time.get_ticks_usec() - t0 < INTAKE_US:
			_look(_pending.pop_front())
	_intaking = false


func _look(path: String) -> void:
	var sha := FileAccess.get_sha256(path)
	if sha == "":
		return
	if pick_on:
		sha += "_pick"   # the picked frame is another picture of the same file: its own cache entry
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
		while _drawing:
			await _frame()
		_drawing = true
		await _render(path)
		_drawing = false
		await _frame()
	_busy = false


## THE STRIP'S CARDS: a picture of ONE POSE, cached by the hash of the pose itself (memory and user://thumbs/p_<hash>.png),
## so a card that is moved, renamed, retimed or duplicated never draws again; only an Update (a new pose) does. Drawn one
## per frame like the scene pictures, after the frame that asked, so a rebuild of the strip never waits for them.
static func pose_key(pose: Dictionary) -> String:
	return (JSON.stringify(pose, "", true) + "|" + FRAME_VER).sha256_text()


## the picture of this pose if it is at hand (memory), else null
func pose_picture(pose: Dictionary) -> Texture2D:
	return _ptex.get(pose_key(pose))


## ask for the picture of a pose; made_pose(key) says when it is there. Returns the key
func request_pose(pose: Dictionary) -> String:
	var key := pose_key(pose)
	if _ptex.has(key):
		return key
	for q in _pq:
		if q[0] == key:
			return key
	_pq.append([key, pose])
	_ppump()
	return key


## the next frame, from the main loop: the node itself may have left the tree meanwhile (the gentle test rebuilds the whole app
## around a running thumbnail pump: get_tree() was null on the next line and the pump died on a script error)
func _frame() -> Signal:
	return (Engine.get_main_loop() as SceneTree).process_frame


func _ppump() -> void:
	if _pbusy:
		return
	_pbusy = true
	await _frame()   # never on the frame that asked
	while not _pq.is_empty():
		var q: Array = _pq.pop_front()
		var key: String = q[0]
		if not _ptex.has(key):
			var f := "%s/p_%s.png" % [DIR, key]
			var img: Image = null
			if FileAccess.file_exists(f):
				img = Image.load_from_file(f)
				if img != null and not img.is_empty():
					disk_hits += 1
			if img == null or img.is_empty():
				var t0 := Time.get_ticks_usec()
				for attempt in 3:   # an empty read-back (the stage not yet rendered) is drawn again, never left as a card with no picture
					img = await draw_pose(q[1])
					if img != null and not img.is_empty():
						break
				if img != null and not img.is_empty():
					DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
					img.save_png(ProjectSettings.globalize_path(f))
					renders += 1
					render_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
			if img != null and not img.is_empty():
				_ptex[key] = ImageTexture.create_from_image(img)
		made_pose.emit(key)
		await _frame()
	_pbusy = false


## the picture of a pose, drawn now on the thumbnail stage (two frames); null when it cannot be drawn
func draw_pose(pose: Dictionary) -> Image:
	while _drawing:
		await _frame()
	_drawing = true
	_stage()
	_tb.from_dict(pose)
	_aim()
	Overlays.pose_skeleton(_sk, _idx, _tb)
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
	_drawing = false
	return img


## wait until every queued picture is drawn (tests)
func settle() -> void:
	while _pbusy or not _pq.is_empty() or _busy or _intaking or not _pending.is_empty() or not _queue.is_empty():
		await _frame()


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
	_cam = cam
	_aim()
	cam.current = true
	var skin := StandardMaterial3D.new()
	skin.albedo_color = PoseLibrary.SKIN
	skin.roughness = 0.55
	var mq := Overlays.mannequin(_vp, skin)
	_sk = mq[1]
	_idx = mq[2]
	_tb = Body.new()
	_tb.load_files("res://data/skeleton.json", "res://data/body_limits.json")


## the camera looks at the body where it stands: its root (the hips' offset, x and z) moves with the walk, so a card
## standing 3.9 m back is framed as well as the one at the origin (the same view direction, only shifted)
func _aim() -> void:
	if _cam == null or _tb == null:
		return
	var c := Vector3(_tb.offset.x, PoseLibrary.CAM_AT.y, _tb.offset.z)
	_cam.look_at_from_position(c + (PoseLibrary.CAM_FROM - PoseLibrary.CAM_AT), c)


## draw one scene's picture: its strike (or middle) card posed on the mannequin, saved to the cache under its hash
func _render(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var sha := FileAccess.get_sha256(path) + ("_pick" if pick_on else "")
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
	if pick_on:
		picked[path] = pick_into(d as Dictionary, _tb)
	else:
		_tb.from_dict((cards[i] as Dictionary)["pose"])
	_aim()
	Overlays.pose_skeleton(_sk, _idx, _tb)
	await _frame()
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		return
	var img := _vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	_tex[path] = {"sha": sha, "tex": ImageTexture.create_from_image(img)}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	img.save_png(ProjectSettings.globalize_path(cache_path(sha)))
	renders += 1
	render_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	made.emit(path)


## K29: pose B at the most readable frame of the scene dict d, seen from the thumbnail's own camera; returns that time (s)
static func pick_into(d: Dictionary, B: Body) -> float:
	var S := Scene.new()
	S.from_dict(d)
	var cam := Transform3D(Basis(), PoseLibrary.CAM_FROM).looking_at(PoseLibrary.CAM_AT, Vector3.UP)
	var r := ThumbPick.best(S, B, cam.basis.x, cam.basis.y)
	S.apply(B, float(r["t"]))
	return float(r["t"])
