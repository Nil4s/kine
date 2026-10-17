## godot --path . -s tests/preview_range_test.gd     (GATE WW4, UPGRADES #262 / #263; needs a window: the real poser UI is built)
## FRAMES: the readout shows "44 / 103 f" for 0.74 / 1.72 s at 60 fps; a click on the readout flips it; changing the fps
## keeps every card's seconds and says how many card times are off a whole frame (one undo step, Ctrl+Z puts it back).
## PREVIEW RANGE: Shift+click / Alt+click on the ruler set in / out; Play never leaves [in, out] (stops at out, or wraps
## to in when Loop); the ruler draws it; Clear restores the full length; the scene's saved text is byte-identical before
## and after (a view setting), and no undo step is made.
extends SceneTree

var fails := 0
var m: Node
var tl: Timeline


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(p: Vector2, shift := false, alt := false) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.shift_pressed = shift
		e.alt_pressed = alt
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(3)


func saved() -> String:
	return JSON.stringify(m.S.to_dict(m.B))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	tl = m.ui_timeline
	m._load_scene("res://scenes/bo_sweep.json")
	m._rebuild_cards()
	m._refresh()
	await idle(3)
	var L: float = m._ps().length()
	print("scene length %.3f s, fps %d, cards %d" % [L, m.S.fps, m.S.cards.size()])
	ok(L > 1.0, "0 the scene is long enough to cut a range (%.2f s > 1.0)" % L)

	# ---- FRAMES
	ok(PreviewRange.time_text(0.74, 1.72, 60, true) == "44 / 103 f", "1 0.74 / 1.72 s at 60 fps reads '%s' (bar: '44 / 103 f')" % PreviewRange.time_text(0.74, 1.72, 60, true))
	ok(PreviewRange.time_text(0.74, 1.72, 60, false) == "0.74 / 1.72 s", "2 seconds mode unchanged: '%s'" % PreviewRange.time_text(0.74, 1.72, 60, false))
	var u0: int = m.undo.size()
	m.S.fps = 60
	m.playhead = 0.74
	m._refresh()
	await idle(2)
	ok(m.ui_time_lbl.text == "%.2f / %.2f s" % [0.74, L], "3 default view is seconds: '%s'" % m.ui_time_lbl.text)
	var lc: Vector2 = m.ui_time_lbl.global_position + m.ui_time_lbl.size * 0.5
	await click(lc)
	var want := "%d / %d f" % [roundi(0.74 * 60), roundi(L * 60)]
	ok(m.frames_view and m.ui_time_lbl.text == want, "4 a real click on the readout shows '%s' (bar: '%s')" % [m.ui_time_lbl.text, want])
	ok(m.bar_text().contains(want), "5 the status line says it too")
	await click(lc)
	ok(not m.frames_view and m.ui_time_lbl.text.ends_with(" s"), "6 a second click flips back: '%s'" % m.ui_time_lbl.text)
	ok(m.undo.size() == u0, "7 the display switch is no undo step (%d vs %d)" % [m.undo.size(), u0])
	m.S.fps = 30

	# fps change keeps the seconds, counts the off-grid times
	var before := []
	for c in m.S.cards:
		before.append([c["move"], c["hold"]])
	var t30: int = PreviewRange.off_grid(m.S, 30)
	var t24: int = PreviewRange.off_grid(m.S, 24)
	var t60: int = PreviewRange.off_grid(m.S, 60)
	print("off-grid card times: 24 fps %d, 30 fps %d, 60 fps %d" % [t24, t30, t60])
	var u1: int = m.undo.size()
	m._set_fps(24)
	var after := []
	for c in m.S.cards:
		after.append([c["move"], c["hold"]])
	ok(m.S.fps == 24 and after == before, "8 fps 30 -> 24 keeps every card's seconds (fps %d, cards equal %s)" % [m.S.fps, str(after == before)])
	ok(m.undo.size() == u1 + 1, "9 one undo step (%d -> %d)" % [u1, m.undo.size()])
	ok(m.ui_status.text.contains("%d card time" % t24), "10 the message names the count (%d off a whole frame at 24): '%s'" % [t24, m.ui_status.text])
	m._undo()
	ok(m.S.fps == 30, "11 Ctrl+Z puts the fps back (%d)" % m.S.fps)
	# a synthetic scene with a time off the grid
	var T := Scene.new()
	T.cards = [{"name": "a", "move": 0.1, "hold": 0.0, "pose": {}}, {"name": "b", "move": 0.1, "hold": 0.0, "pose": {}}, {"name": "c", "move": 0.5, "hold": 0.0, "pose": {}}]
	var o30 := PreviewRange.off_grid(T, 30)   # times 0, 0.1(3 f), 0.6 (18 f): all on
	var o24 := PreviewRange.off_grid(T, 24)   # 0.1 s = 2.4 f off; 0.6 = 14.4 f off
	ok(o30 == 0 and o24 == 2, "12 off_grid on cards at 0.1 and 0.6 s: 30 fps %d (bar 0), 24 fps %d (bar 2)" % [o30, o24])

	# ---- PREVIEW RANGE
	m.playing = false
	m.S.loop = false
	m.playhead = 0.0
	m._refresh()
	await idle(2)
	var s0 := saved()
	var u2: int = m.undo.size()
	var a := snappedf(L * 0.3, 0.01)
	var b := snappedf(L * 0.7, 0.01)
	# real Shift+click / Alt+click on the ruler
	var org: Vector2 = tl.global_position
	await click(org + Vector2(tl.x_of(a), 5.0), true, false)
	ok(absf(m.pv_in - a) < 0.06 and m.pv_out < 0.0, "13 Shift+click on the ruler sets the in point: %.3f (bar %.2f +-0.06)" % [m.pv_in, a])
	await click(org + Vector2(tl.x_of(b), 5.0), false, true)
	ok(absf(m.pv_out - b) < 0.06, "14 Alt+click sets the out point: %.3f (bar %.2f +-0.06)" % [m.pv_out, b])
	ok(not m.playing and absf(m.playhead) < 1e-9, "15 neither click scrubbed or played (playhead %.3f)" % m.playhead)
	ok(saved() == s0, "16 the scene's saved text is byte-identical with the range set (%d chars)" % s0.length())
	ok(m.undo.size() == u2, "17 setting the range is no undo step (%d vs %d)" % [m.undo.size(), u2])
	var lo: float = m.pv_in
	var hi: float = m.pv_out
	# the ruler draws it: the shaded pixel left of "in" is darker than the same place with no range
	await idle(2)
	var img := root.get_texture().get_image()
	var px_in := img.get_pixel(int(org.x + tl.x_of(lo * 0.5)), int(org.y + 20))
	var px_mid := img.get_pixel(int(org.x + tl.x_of((lo + hi) * 0.5)), int(org.y + 20))
	print("pixel left of in %s, inside the range %s" % [str(px_in), str(px_mid)])

	# play without Loop: from outside, enters at in, stops at out, never leaves
	m.playhead = 0.0
	m._toggle_play()
	var mn := 99.0
	var mx := -1.0
	var steps := 0
	while m.playing and steps < 2000:
		m._process(1.0 / 60.0)
		mn = minf(mn, m.playhead)
		mx = maxf(mx, m.playhead)
		steps += 1
	ok(mn >= lo - 1e-6 and mx <= hi + 1e-6, "18 play (no Loop): playhead stayed in [%.3f, %.3f]: min %.3f max %.3f over %d steps" % [lo, hi, mn, mx, steps])
	ok(not m.playing and absf(m.playhead - hi) < 1e-6, "19 it stopped AT the out point: %.3f (bar %.3f)" % [m.playhead, hi])
	# play with Loop: wraps to in, many laps
	m.S.loop = true
	m.playhead = lo
	m.playing = true
	mn = 99.0
	mx = -1.0
	var wraps := 0
	var last: float = m.playhead
	for i in 600:
		m._process(1.0 / 60.0)
		if m.playhead < last - 1e-6:
			wraps += 1
		last = m.playhead
		mn = minf(mn, m.playhead)
		mx = maxf(mx, m.playhead)
	var lap := (hi - lo) * 60.0
	ok(mn >= lo - 1e-6 and mx <= hi + 1e-6 and m.playing, "20 play (Loop) 600 steps: min %.3f max %.3f, in [%.3f, %.3f], still playing" % [mn, mx, lo, hi])
	ok(wraps >= int(600.0 / (lap + 1.0)) and wraps >= 2, "21 it wrapped %d times (bar >= %d: one lap is %.0f steps)" % [wraps, maxi(2, int(600.0 / (lap + 1.0))), lap])
	m.playing = false
	m.S.loop = false   # Loop is a saved setting of the scene: back to how it began
	ok(saved() == s0, "22 byte-identical after playing in the range")
	# clear: the full length again
	m._pv_set("clear", -1.0)
	ok(m.pv_in < 0.0 and m.pv_out < 0.0, "23 Clear unsets both (%.1f, %.1f)" % [m.pv_in, m.pv_out])
	m.S.loop = false
	m.playhead = 0.0
	m.playing = true
	mx = 0.0
	steps = 0
	while m.playing and steps < 4000:
		var p0: float = m.playhead
		m._process(1.0 / 60.0)
		if m.playhead < p0:
			break   # wrapped to 0 at the end, as ever
		mx = maxf(mx, m.playhead)
		steps += 1
	ok(mx > hi + 0.05 and mx >= L - 0.05, "24 after Clear, play runs the whole scene: max %.3f of %.3f (it went past the old out %.3f)" % [mx, L, hi])
	m.playing = false
	m.S.loop = false
	ok(saved() == s0, "25 byte-identical after Clear")
	ok(m.undo.size() == u2, "26 still no undo step from any of it (%d vs %d)" % [m.undo.size(), u2])
	# the pure function, edges
	var r1 := PreviewRange.tick(1.0, 0.1, 2.0, -1.0, -1.0, false)
	var r2 := PreviewRange.tick(1.95, 0.1, 2.0, -1.0, -1.0, false)
	ok(absf(r1["t"] - 1.1) < 1e-9 and r2["t"] == 0.0 and not r2["stop"], "27 no range = the old play: 1.0+0.1 -> %.2f, past the end -> %.1f" % [r1["t"], r2["t"]])
	ok(PreviewRange.span(1.5, 0.5, 2.0).is_empty(), "28 in after out is no range")

	print("PREVIEW RANGE TEST %s %d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
