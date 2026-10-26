## godot --path . -s tests/play_speed_test.gd     (ROADMAP 48: REAL SPEED / EVERY FRAME; needs a window: the real poser UI is built)
## The playback mode, run in the real app (main.tscn, combo3 read only) with a SIMULATED SLOW FRAME: m.play_delay makes each
## playing frame really cost 90 ms (about 2 scene frames at 24 fps), so the frames are slow on any machine.
##   1 REAL SPEED: 1.0 s of scene covered in 1.0 s of wall time (+-5 %). The wall time is the test's own clock, sampled
##     beside the playhead one frame behind (the sample of frame k holds the steps through frame k-1).
##   2 REAL SPEED reports dropped frames: PlaySpeed.dropped > 0 (scene frames a step jumped over), and the bar says
##     "Real speed: dropping N frames" with that N.
##   3 EVERY FRAME: the playhead visits every frame index of the first second exactly once, in order (sampled on each
##     rendered frame), and reports a speed below 1 (the bar says "Every frame: 0.x speed", the number below 1).
##   4 THE LABEL matches the mode: the button's words and icon and the readout's start name the current mode, both ways.
##   5 ANTI-VACUITY: with no delay, a fast machine (1/60 s frames) in every-frame mode shows 1.0x (it waits, it does not
##     run ahead), so the < 1 of test 3 is the slow frame and not a constant.
extends SceneTree

var fails := 0
var m: Node
const FRAME_COST := 0.09   # s: the simulated slow frame, injected through m.play_delay
const BAR := 0.05          # the real-speed tolerance: 5 % of wall time


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func stop_play() -> void:
	m.playing = false
	m.play_delay = 0.0
	await idle(2)


## real-app pass: play from 0 until the playhead has covered one second of scene.
## returns {"cov": scene seconds covered, "wal": wall seconds, "visits": frame indices shown (every mode), "n": frames}
func pass_play(mode: String, need_visits: bool) -> Dictionary:
	m.playing = false
	m.playhead = 0.0
	m._refresh()
	await idle(2)
	if m.play_clock.mode != mode:
		m.ui_mode_btn.pressed.emit()   # the button itself: the real path
	m.play_delay = FRAME_COST
	var fps: int = m.S.fps
	var visits := [0]
	m._toggle_play()
	var p0: float = m.playhead
	var t0 := Time.get_ticks_usec()
	var t_prev := t0
	var cov := 0.0
	var wal := 0.0
	var n := 0
	while n < 400:
		await process_frame
		var now := Time.get_ticks_usec()
		cov = m.playhead - p0            # the steps through the frame before this one
		wal = (t_prev - t0) / 1e6          # ... which ended at the previous sample
		t_prev = now
		var idx := roundi(m.playhead * fps)
		if idx != visits[-1]:
			visits.append(idx)
		n += 1
		if cov >= 1.0 or not m.playing:
			break
	var res: Dictionary = {"cov": cov, "wal": wal, "visits": visits, "n": n, "fps": fps, "label": m.ui_mode_lbl.text}
	await stop_play()
	return res


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	m._refresh()
	await idle(3)
	var L: float = m._ps().length()
	print("scene length %.3f s, fps %d, cards %d" % [L, m.S.fps, m.S.cards.size()])
	ok(L > 1.0, "0 the scene is longer than one second (%.2f s)" % L)

	# ---- the words (pure)
	ok(PlaySpeed.label(PlaySpeed.REAL, 0, 0.0) == "Real speed", "1a real speed with no drops reads 'Real speed'")
	ok(PlaySpeed.label(PlaySpeed.REAL, 3, 0.0) == "Real speed: dropping 3 frames", "1b real speed with drops reads 'Real speed: dropping 3 frames'")
	ok(PlaySpeed.label(PlaySpeed.EVERY, 0, 0.6) == "Every frame: 0.6× speed", "1c every frame reads its speed: '%s'" % PlaySpeed.label(PlaySpeed.EVERY, 0, 0.6))

	# ---- 5 anti-vacuity: a fast machine (1/60 s frames, no delay) in every-frame mode runs at 1.0x, not faster
	var fast := PlaySpeed.new()
	fast.start(PlaySpeed.EVERY)
	var tt := 0.0
	for i in 120:
		var r := fast.advance(tt, 1.0 / 60.0, 24, L, -1.0, -1.0, false)
		tt = r["t"]
	var fs := fast.speed()
	ok(absf(fs - 1.0) < 0.05 and fast.shown == 48, "5 every frame on a fast machine shows 48 frames in 2 s at %.3fx (not ahead of real time)" % fs)

	# ---- 1 + 2 REAL SPEED, slow frames
	m.play_clock.start(PlaySpeed.REAL)
	m._mode_paint()
	var r1: Dictionary = await pass_play(PlaySpeed.REAL, false)
	var ratio: float = r1["cov"] / maxf(r1["wal"], 1e-6)
	print("real: covered %.3f s of scene in %.3f s of wall (%d frames), ratio %.4f, dropped %d" % [r1["cov"], r1["wal"], r1["n"], ratio, m.play_clock.dropped])
	ok(absf(ratio - 1.0) <= BAR, "1 real speed covers %.3f s of scene in %.3f s of wall: ratio %.4f (within 5 %%)" % [r1["cov"], r1["wal"], ratio])
	ok(m.play_clock.dropped > 0, "2 real speed reports dropped frames: %d (a 90 ms frame at %d fps)" % [m.play_clock.dropped, r1["fps"]])
	var want_real := PlaySpeed.label(PlaySpeed.REAL, m.play_clock.dropped, 0.0)
	ok(m.ui_mode_lbl.text == want_real and m.ui_mode_lbl.text.begins_with("Real speed: dropping "), "4a the bar reads '%s'" % m.ui_mode_lbl.text)
	ok(m.ui_mode_btn.text == "Real speed" and m.ui_mode_btn.icon != null, "4b the button says 'Real speed' with its icon")
	var real_icon = m.ui_mode_btn.icon

	# ---- 3 + 4 EVERY FRAME, the same slow frames
	m.ui_mode_btn.pressed.emit()
	await idle(2)
	ok(m.play_clock.mode == PlaySpeed.EVERY and m.ui_mode_btn.text == "Every frame", "4c one click changes the mode: the button reads '%s'" % m.ui_mode_btn.text)
	ok(m.ui_mode_btn.icon != real_icon, "4d the icon changes with the mode")
	var r2: Dictionary = await pass_play(PlaySpeed.EVERY, true)
	var vis: Array = r2["visits"]
	var seq_ok := true
	for i in vis.size():
		if vis[i] != i:
			seq_ok = false
	print("every: %d frames shown, indices %s, speed %.3f" % [vis.size(), str(vis.slice(0, 8)), m.play_clock.speed()])
	ok(seq_ok and vis.size() >= r2["fps"], "3a every frame visits frame indices 0..%d exactly once, in order (%d visits)" % [r2["fps"], vis.size()])
	var sp: float = m.play_clock.speed()
	ok(sp > 0.0 and sp < 1.0, "3b every frame reports a speed below 1: %.3f" % sp)
	var want_e := PlaySpeed.label(PlaySpeed.EVERY, 0, sp)
	ok(m.ui_mode_lbl.text == want_e and m.ui_mode_lbl.text.begins_with("Every frame: ") and m.ui_mode_lbl.text.ends_with("× speed"), "4e the bar reads '%s'" % m.ui_mode_lbl.text)
	ok(not m.ui_mode_lbl.text.contains("dropping"), "4f every frame never says it drops")
	var shown_speed := float(m.ui_mode_lbl.text.trim_prefix("Every frame: ").trim_suffix("× speed"))
	ok(shown_speed < 1.0 and absf(shown_speed - sp) < 0.06, "3c the number on the bar is the speed: %.1f" % shown_speed)

	# ---- the mode goes back: one more click, real speed again
	m.ui_mode_btn.pressed.emit()
	await idle(2)
	ok(m.play_clock.mode == PlaySpeed.REAL and m.ui_mode_lbl.text.begins_with("Real speed"), "4g the second click returns to real speed: '%s'" % m.ui_mode_lbl.text)

	print("RESULT " + ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)
