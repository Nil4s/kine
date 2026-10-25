## godot --path . -s tests/longplay_test.gd     (LONG PLAY: the 61-card axe clip plays at the window's real frame rate; needs a window)
## Bars, written before measuring (window pinned to 1600x900 as the coordinator's probe):
##  (a) a copy of scenes/axe_strike_pose.json plays 120 frames: the median frame is <= 30 ms and the p90 <= 45 ms
##  (b) the playhead keeps real time: after 2 s of wall clock playing it reads 2.0 +- 0.3 s
##  (c) the picture is the same: every frame the baked (served) pose equals a live solve at the same playhead (bit for bit on the joints)
## Found 10-25 by PerfDoc brackets + per-statement timers: the bake restarted every frame (its held state carries the weapon pose), and
## each restart took the scene's signature (~20 ms); the mouse hint rebuilt its line 20 times a second while playing.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	root.content_scale_size = Vector2i(1600, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	if m.easy.on:
		m.easy.set_on(false, false)
	await idle(4)
	var src := "res://scenes/axe_strike_pose.json"
	var copy := "user://zz_longplay_axe.json"
	DirAccess.copy_absolute(src, copy)
	m._load_scene(copy)
	await idle(5)
	ok(m.S.cards.size() == 61, "the copy has the 61 cards of the axe clip (%d)" % m.S.cards.size())

	# (a) 120 frames of play: the wall-clock gap between frames
	m.playhead = 0.0
	m._toggle_play()
	var gaps := []
	var last := Time.get_ticks_usec()
	for f in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		gaps.append((now - last) / 1000.0)
		last = now
	gaps.sort()
	var med: float = gaps[60]
	var p90: float = gaps[108]
	print("longplay frames: median %.1f ms, p90 %.1f ms, max %.1f ms" % [med, p90, gaps[-1]])
	ok(med <= 30.0, "(a) the axe clip plays at a median frame of %.1f ms (bar 30 ms)" % med)
	ok(p90 <= 45.0, "(a) the 90th percentile frame is %.1f ms (bar 45 ms)" % p90)

	# (b) the playhead in real time: start, let 2 s of wall clock pass, read it
	m.playhead = 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	var ph: float = m.playhead
	m._toggle_play()
	print("longplay playhead after 2 s: %.3f s" % ph)
	ok(absf(ph - 2.0) <= 0.3, "(b) after 2 s of play the playhead is %.2f s (bar 2.0 +- 0.3)" % ph)

	# (c) served frames equal live solves: the playhead stepped by real frames, each frame's pose compared with a live solve
	m.playing = true
	var bad := 0
	for f in 90:
		await process_frame
		var pht: float = m.playhead
		var served := str(m.B.P)
		m.playing = false
		PoseBake.serving = false
		m._ps().apply(m.B, m._ps().play_t(pht))
		var live := str(m.B.P)
		m.playing = true
		PoseBake.serving = true
		if served != live:
			bad += 1
	ok(bad == 0, "(c) every played frame equals a live solve of the same playhead (%d of 90 differ)" % bad)

	DirAccess.remove_absolute(copy)
	print("longplay: ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
