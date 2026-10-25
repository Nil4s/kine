## godot --path . -s tests/r17_test.gd     (R17; needs a window)
## BUG: the status bar said 2.90 s and the gold frame was on card 9, but the timeline's playhead line sat at 1.69 s.
## After each of play / step / card click / scrub / undo, the x the playhead overlay LAST DREW (Timeline.ph_drawn_x) must equal
## the x of the time the status bar prints, within 1 px. BAR (stated before measuring): 5 of 5 within 1 px, plus a pixel
## check after the card click that a dark ink column stands at that x in the screenshot (saved to $R17_PNG when set).
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


func bar_t() -> float:
	var t: String = m.ui_bar.text
	var re := RegEx.create_from_string("([0-9.]+) / [0-9.]+ s")
	var r := re.search(t)
	return float(r.get_string(1)) if r != null else -1.0


func check(what: String) -> void:
	await idle()
	var tl = m.ui_timeline
	var bt := bar_t()
	var want: float = tl.x_of(bt)
	var got: float = tl.ph_drawn_x
	ok(bt >= 0.0 and absf(want - got) <= 1.0, "%s: bar %.2f s -> x %.1f, line drawn at x %.1f (playhead %.2f)" % [what, bt, want, got, m.playhead])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._refresh()
	await idle()
	m._card_pick(1)
	await check("start, card 2")
	m._toggle_play()
	await create_timer(0.7).timeout
	m._toggle_play()
	await check("play then stop")
	m._go_card(1)
	await check("step to the next clip")
	m._go_card(1)
	await check("step again")
	m._card_pick(8)
	await check("card 9 clicked")
	var img := root.get_texture().get_image()
	var tl = m.ui_timeline
	var gx := int(tl.global_position.x + tl.ph_drawn_x)
	var dark := 0
	for y in range(int(tl.global_position.y) + 4, int(tl.global_position.y) + 30):
		var c := img.get_pixel(clampi(gx, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
		if c.get_luminance() > 0.0 and absf(c.get_luminance() - Tok.c("tl_bg").get_luminance()) > 0.15:
			dark += 1
	ok(dark >= 10, "placement: %d of 26 pixels in the playhead column differ from the timeline background" % dark)
	var png := OS.get_environment("R17_PNG")
	if png != "":
		img.save_png(png)
	tl.scrubbed.emit(1.2)
	await check("scrub to 1.2 s")
	tl.scrubbed.emit(3.4)
	await check("scrub to 3.4 s")
	m._undo()
	await check("undo")
	m._card_pick(4)
	m._undo()
	await check("card click then undo")
	# the bug's shape: the playhead moved by a path that does not call _refresh (the card strip follows it by itself, so the
	# gold frame moved; only the timeline line stayed). Every such path is covered by writing the variable directly.
	m.playhead = 2.89
	await check("playhead written with no refresh (2.89 s)")
	m.playing = true
	m.playhead = 0.5
	m.playing = false
	m.playhead = 3.9
	await check("playhead written while the play flag flips (3.9 s)")
	print("DONE fails=%d" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
