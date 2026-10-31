extends SceneTree
## p199storymode (Friday plan item 199, Story mode: build a prop, give it to the fighter, film a scene: one guided flow).
## Kine's own loop, build -> act -> film: Easy's More menu has "Make a story", a card with three steps, each a real button:
##   1 Build a prop     opens BUILD (the Easy Part page), one blank part to draw on
##   2 Give it to the fighter   the part he holds (one undo step); plain words name the next step when there is no solid yet
##   3 Film it          Save video (the playblast of the clips he has, one undo step is not needed: nothing in the scene changes)
## Each step's word says To do or Done, read from the built state (a solid body on the part, the held part, a saved video).
## A beginner walk with real clicks: the More button, the card's buttons, the Walk picture, the BUILD draw and pull tools.
## The only code calls: the More entry itself (pick_more, the popup's item) and the page switch back to POSE after BUILD.
## Bars were written before the code. Measured from the built result (pixels, undo list length, the body's solid count,
## the held part's kind, the PNG files on disk), not from the code's own variables.
##   B1 the More menu opens the card with a real click; the card is on the 1280 x 720 view and each of its 3 step buttons is at least 28 px tall
##   B2 before anything is built: 0 of 3 steps are Done, and the three status words say To do
##   B3 real click on Give it to the fighter with no solid part: the undo list is unchanged and he holds no part
##   B4 real click on Film it with no clip: no video is made (the last video is empty) and the scene has no cards
##   B5 real click on Open BUILD: the page is BUILD
##   B6 a box drawn and pulled up with real clicks: the part has exactly 1 solid body
##   B7 real click on the Walk picture: the scene has at least 2 cards
##   B8 the card again: exactly 1 of 3 steps is Done (Build a prop), and its word says Done
##   B9 real click on Give it to the fighter: he holds a part; the undo list grows by exactly 1; step 2 says Done
##   B10 real click on Film it: a video is made: at least 1 frame, the PNG files on disk equal the frame count, and all 3 steps say Done
## Set P199_SHOT=<png path> to keep a picture of the card (default C:/Temp/claude/p199storymode/card.png).
const SHOT := "C:/Temp/claude/p199storymode"
const DIRT := "user://p199storymode_test"

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


## a real click on a control: the mouse moves there, presses and releases
func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu():
	return m.bld.part


func story_btn(i: int) -> Button:
	return m.find_child("story_step_%d" % i, true, false) as Button


func story_status(i: int) -> String:
	var l := m.find_child("story_status_%d" % i, true, false) as Label
	return l.text if l != null else "(no label)"


func done_count() -> int:
	var n := 0
	for i in [1, 2, 3]:
		if story_status(i) == "Done":
			n += 1
	return n


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.easy.set_on(true, false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	m.easy.home.video_root = DIRT + "/video"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT + "/video"))
	await idle(20)

	# B1 the More menu, a real click; the card from its Make a story entry
	await click_ctl(m.easy._btns["More"])
	m.easy.pick_more("Make a story")
	await idle(10)
	var card: Control = m.find_child("easy_story", true, false) as Control
	var vr := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var b1_ok := card != null and card.is_visible_in_tree() and vr.encloses(card.get_global_rect())
	var tall := true
	for i in [1, 2, 3]:
		var b := story_btn(i)
		tall = tall and b != null and b.is_visible_in_tree() and b.get_global_rect().size.y >= 28.0
	ok(b1_ok and tall, "B1 More > Make a story opens the card on the view, each of its 3 step buttons at least 28 px tall (card %s)" % (str(card.get_global_rect()) if card != null else "missing"))
	if card != null:
		var img := root.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(SHOT)
		img.save_png("%s/card.png" % SHOT)

	# B2 nothing built: 0 done, all three say To do
	ok(done_count() == 0 and story_status(1) == "To do" and story_status(2) == "To do" and story_status(3) == "To do",
		"B2 before anything: %d of 3 done (words: %s / %s / %s)" % [done_count(), story_status(1), story_status(2), story_status(3)])

	# B3 Give with no solid part: nothing changes
	var u0: int = m.undo.size()
	await click_ctl(story_btn(2))
	ok(m.undo.size() == u0 and not PartWeapon.is_part(m.B.wep_kind), "B3 Give it to the fighter with no solid part: undo list %d -> %d, he holds no part" % [u0, m.undo.size()])

	# B4 Film with no clip: no video, no cards
	await click_ctl(story_btn(3))
	ok(m.easy.home.last_video.is_empty() and m.S.cards.is_empty(), "B4 Film it with no clip: no video made (%s), %d cards" % [str(not m.easy.home.last_video.is_empty()), m.S.cards.size()])

	# B5 Open BUILD: real click on step 1
	await click_ctl(story_btn(1))
	await idle(20)
	ok(m.cur_page == "BUILD", "B5 Open BUILD: the page is %s" % m.cur_page)

	# B6 a box drawn and pulled up with real clicks
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.06, 0.0, -0.02)), scr(Vector3(0.06, 0.0, 0.02)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	var bodies: int = int(pu().res.get("bodies", 0))
	ok(bodies == 1, "B6 a drawn and pulled box: %d solid body (want 1)" % bodies)

	# B7 back to the animation page (a code call), then the Walk picture (a real click)
	m._page_set("POSE")
	await idle(20)
	m.easy.set_on(true, false)
	await idle(10)
	await click_ctl(m.easy.home.card_btn(0))
	await idle(60)
	ok(m.S.cards.size() >= 2, "B7 the Walk picture: %d cards" % m.S.cards.size())

	# B8 the card again: one step Done
	await click_ctl(m.easy._btns["More"])
	m.easy.pick_more("Make a story")
	await idle(10)
	ok(done_count() == 1 and story_status(1) == "Done", "B8 card again: %d of 3 done, step 1 says %s" % [done_count(), story_status(1)])

	# B9 Give it to the fighter, a real click
	u0 = m.undo.size()
	await click_ctl(story_btn(2))
	await idle(20)
	var held: bool = PartWeapon.is_part(m.B.wep_kind)
	ok(held and m.undo.size() == u0 + 1 and story_status(2) == "Done", "B9 Give: he holds a part %s, undo list %d -> %d, step 2 says %s" % [str(held), u0, m.undo.size(), story_status(2)])

	# B10 Film it, a real click: a video of the clips he has
	await click_ctl(story_btn(3))
	var t0 := Time.get_ticks_msec()
	while m.easy.home.last_video.is_empty() and Time.get_ticks_msec() - t0 < 600000:
		await process_frame
	var lv: Dictionary = m.easy.home.last_video
	var frames := int(lv.get("frames", 0))
	var pngs := 0
	if not lv.is_empty():
		for f in DirAccess.get_files_at(String(lv["dir"])):
			if f.ends_with(".png"):
				pngs += 1
	await idle(5)
	ok(frames >= 1 and pngs == frames and done_count() == 3, "B10 Film it: %d frames, %d PNG files on disk, %d of 3 done" % [frames, pngs, done_count()])

	print("p199storymode: %d fail" % fails)
	quit(1 if fails > 0 else 0)
