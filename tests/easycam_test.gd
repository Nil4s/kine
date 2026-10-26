## godot --path . -s tests/easycam_test.gd     (EASY CAMERA: the body sits in the free rect between the Easy bar or strip and the bottom card panel)
## BARS (written first; the body below checks each one):
##  1. for punch, kick and walk, every 4th frame of the clip, with the Easy follow camera ticked at that frame (the look-at rides
##     the body's centre; c90df523, 2b780927): the head, both feet and both hands project INSIDE the free rect
##     (below the Easy bar and the strip, above the bottom card panel), at 1600 x 900 and at 1280 x 720. The whole body
##     (every joint, its ends and any weapon, each with its radius) is checked the same way.
##  2. Expert's camera is unchanged by going Easy -> Expert: yaw, pitch, dist, target, the offsets and the transform.
##  3. the free rect is re-framed when a clip is built and when the window resizes (the framing follows the new size).
## --easycam-shot=<png> (after --): a viewport picture after the Punch card, for the screenshot in the task log.
## Window suite: it sets the window size itself (run_par: TOPLEVEL).
extends SceneTree

const SIZES := [Vector2i(1600, 900), Vector2i(1280, 720)]
const CARDS := {"walk": 0, "punch": 3, "kick": 4}   # EasyHome.CARDS index
const FEET := ["foot_l", "foot_r"]
const HANDS := ["hand_l", "hand_r"]

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## the free rect from the real nodes: below the Easy bar (and the strip when it shows), above the bottom card panel
func free_rect() -> Rect2:
	var top: float = m.easy.bar.get_global_rect().end.y
	if m.easy.home.strip.visible:
		top = maxf(top, m.easy.home.strip.get_global_rect().end.y)
	var bottom: float = m.ui_bp.get_global_rect().position.y
	return Rect2(0.0, top, get_root().get_visible_rect().size.x, bottom - top)


func inside_rect(p: Vector2, f: Rect2, r := 0.0) -> bool:
	return p.x - r >= f.position.x and p.x + r <= f.end.x and p.y - r >= f.position.y and p.y + r <= f.end.y


## every 4th frame of the clip: head, feet and hands (centres) inside the free rect, then the whole body (every joint,
## end and weapon point, with its radius in px). Returns [first failure ("" = none), frames checked]
func check_clip(f: Rect2) -> Array:
	var fps := float(m.S.fps)
	var n := int(ceil(m.S.length() * fps))
	var frames := 0
	var cam: Camera3D = m.cam
	var head0: float = m.playhead
	for k in range(0, n + 1, 4):
		# Easy's camera follows the body (c90df523, 2b780927): the look-at rides the live box centre at the playhead, so each
		# frame is posed, the playhead put there and the follow ticked (main does it every frame) before the body is checked
		m.playhead = float(k) / fps
		m._ps().apply(m.B, m.playhead)
		m.easy.follow_tick()
		frames += 1
		for j in ["head"] + FEET + HANDS:
			if cam.is_position_behind(m.B.P[j]) or not inside_rect(cam.unproject_position(m.B.P[j]), f):
				return ["%s outside at frame %d" % [j, k], frames]
		for p in Turntable.points(m.B):
			var c: Vector3 = p[0]
			if cam.is_position_behind(c):
				return ["body point behind the camera at frame %d" % k, frames]
			var q := cam.unproject_position(c)
			var r := absf(cam.unproject_position(c + cam.global_basis.x * float(p[1])).x - q.x)   # the radius in px, here
			if not inside_rect(q, f, r):
				return ["body point (%.0f,%.0f r%.0f) outside at frame %d" % [q.x, q.y, r, k], frames]
	m.playhead = head0
	m._ps().apply(m.B, head0)
	m.easy.follow_tick()
	return ["", frames]


func cam_state() -> Array:
	var c: Camera3D = m.cam
	return [c.transform, c.h_offset, c.v_offset, m.yaw, m.pitch, m.dist, m.target]


func same_state(a: Array, b: Array) -> bool:
	if not a[0].is_equal_approx(b[0]):
		return false
	for k in [1, 2, 3, 4, 5]:
		if absf(float(a[k]) - float(b[k])) > 1e-6:
			return false
	return (a[6] as Vector3).is_equal_approx(b[6])


func _init() -> void:
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--easycam-shot="):
			shot = a.substr(15)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m.easy.set_on(false, false)
	await idle(4)

	# 2. Expert's camera: a clip built in Expert, the camera read; Easy on, framed, off again: the same camera
	m.easy.home.card(CARDS["punch"])
	await idle(4)
	if m.playing:
		m._toggle_play()
	var before := cam_state()
	m.easy.set_on(true, false)
	await idle(4)
	m.easy.frame_clip()
	await idle(2)
	m.easy.set_on(false, false)
	await idle(6)
	var after := cam_state()
	ok(same_state(before, after), "Expert's camera is unchanged going Easy -> Expert (yaw, pitch, dist, target, offsets, transform)")

	# 1. the body in the free rect, punch / kick / walk, at each size; then a resize re-frames the same clip
	for s in SIZES:
		DisplayServer.window_set_size(s)
		get_root().size = s
		await idle(10)
		var vs := get_root().get_visible_rect().size
		ok(vs == Vector2(s), "the window is %dx%d (it shows %dx%d)" % [s.x, s.y, vs.x, vs.y])
		m.easy.set_on(true, false)
		await idle(4)
		for name in ["punch", "kick", "walk"]:
			m.easy.home.card(CARDS[name])
			await idle(6)
			if m.playing:
				m._toggle_play()
			await idle(2)
			var f := free_rect()
			var res := check_clip(f)
			ok(res[0] == "" and res[1] > 0,
				"%s at %dx%d: head, feet, hands and the whole body inside the free rect %s (%d frames every 4th; %s)" % [name, s.x, s.y, str(f), res[1], res[0] if res[0] != "" else "all inside"])
			if name == "punch" and s == SIZES[0] and shot != "":
				await RenderingServer.frame_post_draw
				var err := get_root().get_texture().get_image().save_png(shot)
				ok(err == OK, "the Punch card picture is saved to %s (error %d)" % [shot, err])
		if s == SIZES[0]:
			m.easy.home.card(CARDS["punch"])
			await idle(6)
			if m.playing:
				m._toggle_play()
			DisplayServer.window_set_size(SIZES[1])
			get_root().size = SIZES[1]
			await idle(12)
			var r2 := check_clip(free_rect())
			ok(r2[0] == "", "a resize re-frames the clip: the Punch clip at 1280x720 (after 1600x900) is inside the free rect (%s)" % str(r2[0] if r2[0] != "" else "all inside"))
		m.easy.set_on(false, false)
		await idle(4)

	print("EASY CAM %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
