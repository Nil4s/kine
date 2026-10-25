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
const POSE_BATCH := 8     # the strip's pictures: up to this many poses are drawn in ONE frame, each on its own stage (see _pool_stages)
const BATCH_US := 6000    # ...and a frame stops adding poses to its batch once this much time has gone (a frame never takes long)
const POSE_TRIES := 3    # a picture that comes back empty is drawn again this many times, then the card keeps none
var _pool_st: Array = []  # the stages the strip's pictures are drawn in: made on the first batch, reused (scene pictures keep _vp)
var _inbatch := {}        # pose key -> true while its picture is being drawn: a request for it waits for that draw


func _ready() -> void:
	_stage.call_deferred()   # the mannequin is loaded at start-up, not on the first open of the list
	_pool_stages.call_deferred(POSE_BATCH)   # the strip's stages too: the first Run does not pay for building them (75 ms)


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


## the same picture by its key (pose_key made once by the caller)
func picture_of_key(key: String) -> Texture2D:
	return _ptex.get(key)


## ask for the picture of a pose; made_pose(key) says when it is there. Returns the key. rank orders the queue (a lower
## rank is drawn first; the strip gives the cards in view the lowest ranks); a request with no rank goes last
func request_pose(pose: Dictionary, rank := 1 << 30) -> String:
	return request_key(pose_key(pose), pose, rank)


## request_pose with the key already made (a card row makes it once: pose_key is a JSON dump and a hash)
func request_key(key: String, pose: Dictionary, rank := 1 << 30) -> String:
	if _ptex.has(key) or _inbatch.has(key):
		return key   # made_pose(key) comes with the picture (a batch in flight, or the picture is at hand)
	for q in _pq:
		if q[0] == key:
			return key
	var at := _pq.size()
	for j in _pq.size():
		if int(_pq[j][2]) > rank:
			at = j
			break
	_pq.insert(at, [key, pose, rank, 0])
	_ppump()
	return key


## the next frame, from the main loop: the node itself may have left the tree meanwhile (the gentle test rebuilds the whole app
## around a running thumbnail pump: get_tree() was null on the next line and the pump died on a script error)
func _frame() -> Signal:
	return (Engine.get_main_loop() as SceneTree).process_frame


## the queue, in rank order. Pictures on disk (or in memory) are taken at once; the rest are drawn in batches of up to
## POSE_BATCH poses in ONE frame (_draw_batch), so the strip's pictures come a few frames apart, not one a frame.
## Every queued key is made once: a key drawn in one batch is not drawn again (its made_pose serves every card)
func _ppump() -> void:
	if _pbusy:
		return
	_pbusy = true
	await _frame()   # never on the frame that asked
	while not _pq.is_empty():
		var t0 := Time.get_ticks_usec()
		var batch: Array = []   # [key, pose, rank, tries] to draw in this frame
		while not _pq.is_empty() and batch.size() < POSE_BATCH:
			var q: Array = _pq.pop_front()
			var key: String = q[0]
			if _ptex.has(key):
				made_pose.emit(key)
				continue
			var img := _disk_pose(key)
			if img != null:
				_ptex[key] = ImageTexture.create_from_image(img)
				made_pose.emit(key)
			else:
				batch.append(q)
				_inbatch[key] = true
			if Time.get_ticks_usec() - t0 > BATCH_US:
				break
		if batch.is_empty():
			await _frame()   # only disk hits so far: the next frame takes the rest
			continue
		var t1 := Time.get_ticks_usec()
		var poses: Array = []
		for q in batch:
			poses.append(q[1])
		var imgs: Array = await _draw_batch(poses)
		var per_ms := (Time.get_ticks_usec() - t1) / 1000.0 / float(batch.size())
		for j in batch.size():
			var q: Array = batch[j]
			var key: String = q[0]
			var img: Image = imgs[j] if j < imgs.size() else null
			_inbatch.erase(key)
			if img != null and not img.is_empty():
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
				img.save_png(ProjectSettings.globalize_path("%s/p_%s.png" % [DIR, key]))
				renders += 1
				render_ms.append(per_ms)
				_ptex[key] = ImageTexture.create_from_image(img)
			elif int(q[3]) + 1 < POSE_TRIES:
				q[3] = int(q[3]) + 1   # an empty read-back (the stage not yet rendered) is drawn again, never left as a card with no picture
				_pq.push_front(q)
				continue
			made_pose.emit(key)
	_pbusy = false


## the picture of a pose from the disk cache, or null (a file that is missing or empty)
func _disk_pose(key: String) -> Image:
	var f := "%s/p_%s.png" % [DIR, key]
	if not FileAccess.file_exists(f):
		return null
	var img := Image.load_from_file(f)
	if img == null or img.is_empty():
		return null
	disk_hits += 1
	return img


## several poses in ONE frame: pose j on stage j of the pool, all stages rendered together and read back together.
## Returns one Image (or null) per pose, in order
func _draw_batch(poses: Array) -> Array:
	var out: Array = []
	out.resize(poses.size())
	out.fill(null)
	while _drawing:
		await _frame()
	_drawing = true
	var sts := _pool_stages(poses.size())
	for j in poses.size():
		var st: Dictionary = sts[j]
		(st["tb"] as Body).from_dict(poses[j])
		_aim_at(st["cam"], st["tb"])
		Overlays.pose_skeleton(st["sk"], st["idx"], st["tb"])
	await _frame()
	if not is_inside_tree():
		_drawing = false
		return out
	for st in sts:
		(st["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if is_inside_tree():
		for j in poses.size():
			var vp := sts[j]["vp"] as SubViewport
			if is_instance_valid(vp):
				out[j] = vp.get_texture().get_image()
	_drawing = false
	return out


## the pool's first n stages (made as they are needed, then kept)
func _pool_stages(n: int) -> Array:
	while _pool_st.size() < n:
		_pool_st.append(_new_stage("pose_stage_%d" % _pool_st.size()))
	return _pool_st.slice(0, n)


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


## the scene pictures' stage (the one draw_pose and _render use): made once
func _stage() -> void:
	if _vp != null:
		return
	var st := _new_stage("scene_thumb_stage")
	_vp = st["vp"]
	_cam = st["cam"]
	_sk = st["sk"]
	_idx = st["idx"]
	_tb = st["tb"]
	_aim()


## one stage: its own world, lights, camera and mannequin (the same look as every picture). Returns
## {vp, cam, sk, idx, tb}; the stage is a child of this node
func _new_stage(nm: String) -> Dictionary:
	var vp := SubViewport.new()
	vp.name = nm
	vp.size = SIZE
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PoseLibrary.BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.1
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.35
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = PoseLibrary.CAM_SIZE
	cam.near = 0.05
	cam.far = 20.0
	vp.add_child(cam)
	var tb := Body.new()
	tb.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_aim_at(cam, tb)
	cam.current = true
	var skin := StandardMaterial3D.new()
	skin.albedo_color = PoseLibrary.SKIN
	skin.roughness = 0.55
	var mq := Overlays.mannequin(vp, skin)
	return {"vp": vp, "cam": cam, "sk": mq[1], "idx": mq[2], "tb": tb}


## the camera looks at the body where it stands: its root (the hips' offset, x and z) moves with the walk, so a card
## standing 3.9 m back is framed as well as the one at the origin (the same view direction, only shifted)
func _aim() -> void:
	if _cam == null or _tb == null:
		return
	_aim_at(_cam, _tb)


func _aim_at(cam: Camera3D, tb: Body) -> void:
	var c := Vector3(tb.offset.x, PoseLibrary.CAM_AT.y, tb.offset.z)
	cam.look_at_from_position(c + (PoseLibrary.CAM_FROM - PoseLibrary.CAM_AT), c)


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
