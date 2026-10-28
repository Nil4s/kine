## godot --path . -s tests/videowalk_test.gd     (VIDEOWALK: a beginner who never used 3D makes a move from a video, real clicks, 1280x720)
## BARS (stated before measuring; the walk's dead ends, found by walking the app with real clicks):
##  1 start screen -> ANIMATION's Easy (real click): the Easy home shows 'From a video' and the typed box
##  2 the copied clip (tests/fixtures/fps16_hammer_2s.webm, via the dialog's pick copy_video_file): 3 cards, playing
##  3 a card click ('Video 2') names the card and says what to do with words on screen: no "'Update'" (no such button in Easy),
##    and the status names '+ Add pose' (a button on screen)
##  4 '+ Add pose' after the picked card: every copied card has a different 'Video <n>' name (the old code read 'Video 1' twice)
##  5 while the clip plays, 'Cut end' (no card picked) does not cut at the moment it is pressed: the cards are as before, and the
##    status says 'Press Stop' (the old code cut the 2 s clip to 0.3 s with one press)
##  6 after Stop and a slider drag to the middle, 'Cut end' still cuts (the clip ends near the slider: <= 60 % of its length)
## Starts at the REAL start screen: ANIMATION's Easy button, then only what Easy shows. Shots: C:/Temp/claude/videowalk/<step>.png
## Prints FRICTION lines (every dead end: the exact words and the press). The file pick goes through copy_video_file(path)
## (the native file dialog cannot be driven headless; it is noted as a step the walk cannot do).
extends SceneTree

const OUT := "C:/Temp/claude/videowalk/"
const CLIP := "res://tests/fixtures/fps16_hammer_2s.webm"

var m: Node
var fails := 0
var clicks := 0
var notes: Array = []
var goal := ""


func bar(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		fails += 1


func say(s: String) -> void:
	print(s)


func note(s: String) -> void:
	notes.append("[%s] %s" % [goal, s])
	print("   FRICTION: " + s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func visible_nodes() -> Array:
	var out := []
	for n in walk(root, []):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in visible_nodes():
		if n is Button:
			out.append(n)
	return out


func btn_names() -> String:
	var out := []
	for b in visible_buttons():
		if (b as Button).text != "":
			out.append((b as Button).text)
	return str(out)


func find_btn(txt: String) -> Control:
	for b in visible_buttons():
		if (b as Button).text.strip_edges() == txt:
			return b
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() == txt:
			var p: Node = n
			while p != null and not (p is Button):
				p = p.get_parent()
			return p if p != null else n
	return null


func mouse_at(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func click_ctl(c: Control) -> bool:
	var p := c.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame
	var under := root.get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		note("COVERED: the click on '%s' at %s lands on %s" % [str(c.name), str(p), str(under.name) if under != null else "nothing"])
	mouse_at(p, true)
	await process_frame
	mouse_at(p, false)
	await idle(3)
	return inside


func click_text(txt: String) -> bool:
	var b := find_btn(txt)
	if b == null:
		note("NOT VISIBLE: no button reads '%s' (visible: %s)" % [txt, btn_names()])
		return false
	clicks += 1
	say("   click '%s' (tooltip: '%s')" % [txt, b.tooltip_text if b is BaseButton else ""])
	return await click_ctl(b)


func shot(n: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "%s.png" % n)
	say("   shot %s.png | status \"%s\" | top bar \"%s\" | cards %d | playing %s | shown %s" % [n, m.ui_status.text, m._imp_lbl.text if m._imp_lbl != null else "", m.S.cards.size(), str(m.playing), m.easy.home.shown()])
	say("   visible buttons: %s" % btn_names())


func start_goal(s: String) -> void:
	goal = s
	clicks = 0
	say("\n== %s ==" % s)


func box() -> LineEdit:
	for n in visible_nodes():
		if n is LineEdit and (n as LineEdit).placeholder_text.begins_with("or type"):
			return n
	return null


func drag_slider(sl: HSlider, frac: float) -> void:
	var r := sl.get_global_rect()
	var x0 := r.position.x + r.size.x * 0.02
	var x1 := r.position.x + r.size.x * frac
	mouse_at(Vector2(x0, r.get_center().y), true)
	await process_frame
	for i in 10:
		var hm := InputEventMouseMotion.new()
		hm.position = Vector2(lerpf(x0, x1, float(i + 1) / 10.0), r.get_center().y)
		hm.global_position = hm.position
		hm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(hm)
		await process_frame
	mouse_at(Vector2(x1, r.get_center().y), false)
	await idle(10)


func copy_names() -> Array:
	var out := []
	for i in m.S.cards.size():
		out.append(String(m._easy_card_name(String(m.S.cards[i]["name"]), i)))
	return out


func visible_slider() -> HSlider:
	for n in walk(root, []):
		if n is HSlider and n.name == "eh_scrub" and (n as Control).is_visible_in_tree():
			return n
	return null


func _init() -> void:
	EasyMode.start_fresh = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.start_screen.show_screen(true)
	await idle(10)

	# 1. the real start screen: ANIMATION's Easy, then the Easy home
	start_goal("STEP 1 start -> Easy")
	await shot("1_start")
	await click_text("Easy")
	await idle(20)
	await shot("2_easy_home")
	bar(find_btn("From a video") != null and box() != null, "1 Easy home shows 'From a video' and the typed box")

	# the copy: the dialog's pick (a native OS dialog cannot be driven headless: noted as a dead end of the walk)
	start_goal("STEP 2 the clip becomes cards")
	note("'From a video' and More > 'Copy a video' open the NATIVE OS file dialog: the walk hands the clip over by copy_video_file")
	m.easy.home.copy_video_file(ProjectSettings.globalize_path(CLIP))
	var f := 0
	while m.easy.home._vid_busy and f < 3000:
		await process_frame
		f += 1
	await idle(20)
	await shot("3_copied")
	bar(m.S.cards.size() == 3 and m.playing, "2 the copied clip: %d cards (want 3), playing %s" % [m.S.cards.size(), str(m.playing)])

	# 3. a card click names it and says what to do, with words on screen
	start_goal("STEP 3 click card 'Video 2'")
	var cb := find_btn("Video 2")   # the card's own button (the test's lookup is not the card's: the status line is what is checked)
	if cb != null:
		await click_ctl(cb)
	await idle(10)
	await shot("4_card2")
	var st3 := String(m.ui_status.text)
	bar(st3.begins_with("Video 2 is picked") and not st3.contains("'Update'") and st3.contains("+ Add pose"),
		"3 card 2 click: status \"%s\" (no 'Update', which Easy does not show; names '+ Add pose')" % st3)

	# 4. + Add pose after the picked card: the copied names stay unique
	start_goal("STEP 4 + Add pose after 'Video 2'")
	await click_text("+ Add pose")
	await idle(10)
	await shot("5_add_pose")
	var names4 := copy_names()
	var uniq := {}
	for n in names4:
		uniq[n] = true
	bar(names4.size() == 4 and uniq.size() == names4.size(), "4 after + Add pose: names %s (every card its own name)" % str(names4))

	# 5. Cut end while the clip plays, nothing picked on the moment: no cut, and the status says why
	start_goal("STEP 5 Cut end while the clip plays")
	await click_text("Again")
	await idle(20)
	var c5: int = m.S.cards.size()
	var L5: float = m.S.length()
	var playing5: bool = m.playing
	await click_text("Cut end")
	await idle(10)
	await shot("6_cut_end_playing")
	var st5 := String(m.ui_status.text)
	bar(playing5 and m.S.cards.size() == c5 and absf(m.S.length() - L5) < 0.001 and st5.contains("Press Stop"),
		"5 Cut end while playing (%.2f s): %d cards, %.2f s, status \"%s\"" % [L5, m.S.cards.size(), m.S.length(), st5])

	# 6. Stop, drag the slider to the middle, Cut end: it cuts there
	start_goal("STEP 6 Stop, slider to the middle, Cut end")
	if m.playing:
		await click_text("Stop")
		await idle(10)
	var sl := visible_slider()
	if sl != null:
		await drag_slider(sl, 0.5)
	var Lb6: float = m.S.length()
	await click_text("Cut end")
	await idle(10)
	await shot("7_cut_end_stopped")
	var La6: float = m.S.length()
	say("   before %.2f s, after %.2f s, status \"%s\"" % [Lb6, La6, m.ui_status.text])
	bar(sl != null and La6 > 0.0 and La6 <= 0.6 * Lb6, "6 Cut end after Stop at the middle: %.2f s -> %.2f s (<= 60 %%)" % [Lb6, La6])

	print("
VIDEOWALK: %s (%d failed bars)" % ["PASS" if fails == 0 else "FAIL", fails])
	m.queue_free()
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)
