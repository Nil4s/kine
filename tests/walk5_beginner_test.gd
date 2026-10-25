## godot --path . --position 3000,3000 -s tests/walk5_beginner_test.gd   (BEGINNER WALK-THROUGH, round 5: EASY mode, real clicks)
## Eight NEW goals a non-technical person would try next, every press a real mouse click, every pose a real drag, every
## sentence typed. A goal the UI does not offer is reported as NOT DONE with what was visible; nothing is worked around.
## Screenshots after each step go to C:/Temp/claude/walk5/. Checks that are not part of a goal are marked "(check)".
## The AI video button is NEVER pressed. The Easy settings file is the test's own (user://poser_test_<pid>.cfg).
extends SceneTree

const OUT := "C:/Temp/claude/walk5/"

var m: Node
var n_shot := 0
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""


func say(s: String) -> void:
	print(s)
	lines.append(s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):   # INTERNAL children too: a dialog's button row is internal
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


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func find_btn(txt: String, prefix := false) -> Button:
	for b in visible_buttons():
		var t := text_of(b)
		if t == txt or (prefix and t.begins_with(txt)):
			return b
	return null


func btn_names() -> String:
	var out := []
	for b in visible_buttons():
		var t := text_of(b)
		if t != "":
			out.append(t)
	return str(out)


func visible_words() -> String:
	var out := []
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges())
	return str(out)


func mouse_btn(down: bool, p: Vector2, which := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = which
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e)


func move(p: Vector2, rel: Vector2, mask := MOUSE_BUTTON_MASK_LEFT) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = mask
	root.push_input(e)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


func hit_name(p: Vector2) -> String:
	var h := get_root().get_viewport().gui_get_hovered_control()
	return "none" if h == null else str(h.name) + " (" + h.get_class() + ")"


## a real click on a Control: the mouse goes down and up on its middle
func click_ctl(c: Control) -> bool:
	var r := c.get_global_rect()
	var w := c.get_window()
	if w != null and w != get_root():
		r.position += Vector2(w.position)
	var p := r.get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		say("   COVERED: the click at %s lands on %s, not on the button" % [str(p), hit_name(p)])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return inside


## a click on the first visible button with these words (the words a beginner reads on it)
func click_text(txt: String, prefix := false) -> bool:
	var b := find_btn(txt, prefix)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s'" % txt)
		return false
	clicks += 1
	say("   click '%s'" % text_of(b))
	return await click_ctl(b)


## a click on one row of a popup menu (Easy's More list, the Open list): the row's place in the list
func click_menu_item(menu: PopupMenu, txt: String) -> bool:
	if menu == null or not menu.visible:
		say("   NOT VISIBLE: the menu is not open (wanted '%s')" % txt)
		return false
	var idx := -1
	var items := []
	for i in menu.item_count:
		items.append(menu.get_item_text(i))
		if menu.get_item_text(i) == txt:
			idx = i
	if idx < 0:
		say("   NOT VISIBLE: the menu has %s, not '%s'" % [str(items), txt])
		return false
	clicks += 1
	var pos := Vector2(menu.position)
	var sz := Vector2(menu.size)
	var rowh := sz.y / float(menu.item_count)
	var p := Vector2(pos.x + sz.x * 0.5, pos.y + (idx + 0.5) * rowh)
	say("   click menu row '%s' (of %s)" % [txt, str(items)])
	await hover(p)
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return true


## a real drag of a body part: press on it, move in steps, let go
func drag(j: String, d := Vector2(48, -48)) -> void:
	clicks += 1
	var c: Array = m.B.cap(j)
	var p: Vector2 = m.cam.unproject_position(c[0].lerp(c[1], 0.75))
	await hover(p)
	say("   drag '%s' from %s by %s (under the pointer: %s)" % [j, str(p), str(d), hit_name(p)])
	var st := d / 6.0
	mouse_btn(true, p)
	await process_frame
	for i in 6:
		move(p + st * (i + 1), st)
		await process_frame
	mouse_btn(false, p + d)
	await idle(3)


## a real right-drag on empty view (the camera turns; a beginner's way round the body)
func right_drag(p: Vector2, d: Vector2) -> void:
	clicks += 1
	await hover(p)
	say("   right-drag from %s by %s (under the pointer: %s)" % [str(p), str(d), hit_name(p)])
	mouse_btn(true, p, MOUSE_BUTTON_RIGHT)
	await process_frame
	var st := d / 8.0
	for i in 8:
		move(p + st * (i + 1), st, MOUSE_BUTTON_MASK_RIGHT)
		await process_frame
	mouse_btn(false, p + d, MOUSE_BUTTON_RIGHT)
	await idle(6)


func body_on_screen() -> bool:
	var c: Array = m.B.cap("pelvis")
	var at: Vector3 = (c[0] + c[1]) * 0.5
	var vp := m.get_viewport().get_visible_rect()
	return not m.cam.is_position_behind(at) and vp.has_point(m.cam.unproject_position(at))


func shot(name: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	n_shot += 1
	var f := "%s%02d_%s.png" % [OUT, n_shot, name]
	root.get_texture().get_image().save_png(f)
	say("   shot %s | body on screen: %s | cards: %d | playing: %s" % [f.get_file(), str(body_on_screen()), m.S.cards.size(), str(m.playing)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func end_goal(ok: bool, note: String) -> void:
	say("== END %s: done=%s clicks=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, (Time.get_ticks_msec() - t0) / 1000.0, note])


func wait_playing(limit := 240) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


func wait_for(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await process_frame
	return false


func type_text(s: String, enter := false) -> void:
	for c in s:
		var kd := InputEventKey.new()
		kd.keycode = (KEY_SPACE if c == " " else c.to_upper().unicode_at(0)) as Key
		kd.unicode = c.unicode_at(0)
		kd.pressed = true
		root.push_input(kd)
		await process_frame
		var ku := InputEventKey.new()
		ku.keycode = kd.keycode
		ku.unicode = kd.unicode
		ku.pressed = false
		root.push_input(ku)
		await process_frame
	if enter:
		var ke := InputEventKey.new()
		ke.keycode = KEY_ENTER
		ke.pressed = true
		root.push_input(ke)
		await process_frame
		ke.pressed = false
		root.push_input(ke)
		await process_frame


func visible_line_edit(placeholder_start: String) -> LineEdit:
	for n in visible_nodes():
		if n is LineEdit and (n as LineEdit).placeholder_text.begins_with(placeholder_start):
			return n
	return null


func card_names() -> Array:
	var out := []
	for c in m.S.cards:
		out.append(str(c.get("name", "?")))
	return out


## the picture cards of the home panel, shown when the panel is open (Easy's "What should he do?")
func panel_open() -> bool:
	return m.easy.home.shown() == "panel"


func box() -> LineEdit:
	return visible_line_edit("or type")


func _init() -> void:
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if not m.easy.on:
		m.easy.set_on(true)
		await idle(10)
		say("   forced Easy (set_on(true)) | Easy now: %s" % str(m.easy.on))
	say("start: home panel %s | words: %s" % [m.easy.home.shown(), visible_words()])

	# 1. MAKE HIM WALK, THEN SIT DOWN: typed in the box ("walk then sit down")
	begin_goal("1 walk, then sit down (typed: 'walk then sit down')")
	var b1 := box()
	var got1 := false
	var n1: int = m.S.cards.size()
	if b1 != null:
		await click_ctl(b1)
		clicks += 1
		await type_text("walk then sit down", true)
		got1 = await wait_playing()
	else:
		say("   NOT VISIBLE: no text box on the start screen")
	await shot("01_walk_then_sit_typed")
	var names1 := card_names()
	var has_walk := names1.filter(func(s): return s.to_lower().contains("step")).size() > 0   # the walk's own cards are named "step L/R"
	var has_sit := names1.filter(func(s): return s.to_lower().contains("seated")).size() > 0   # the sit ends on "seated"
	say("   cards now: %s" % str(names1))
	end_goal(got1 and m.S.cards.size() > n1 and has_walk and has_sit, "(cards %d -> %d, walk steps %s, ends seated %s)" % [n1, m.S.cards.size(), str(has_walk), str(has_sit)])

	# 2. SLOWER, THEN PLAY IT
	begin_goal("2 make the walk slower, then play it")
	var slow := await click_text("Slower")
	await idle(20)
	var played_auto: bool = m.playing
	await shot("02_slower")
	var play2 := false
	if not m.playing:
		var pb := find_btn("Play", true)
		if pb == null:
			pb = find_btn("Stop", true)
		if pb != null:
			play2 = await click_text(text_of(pb))
			play2 = play2 and await wait_playing()
	else:
		play2 = true
	await shot("03_slower_playing")
	var refused := visible_words().contains("as slow as it goes")
	end_goal(slow and play2 and not refused, "(slower clicked: %s, refused at the limit: %s, already playing after the press: %s)" % [str(slow), str(refused), str(played_auto)])

	# 3. CHANGE ONE POSE IN THE MIDDLE: pick a card on the timeline, drag the arm, play
	begin_goal("3 change one pose in the middle: pick a card, drag the arm, play")
	var cards_btn: Array = []
	for c in walk(m.ui_cards, []):   # the timeline's cards sit under a scroll row: every visible Button under the strip
		if c is Button and (c as Button).is_visible_in_tree():
			cards_btn.append(c)
	say("   timeline buttons visible: %d" % cards_btn.size())
	var pick_ok := false
	var n_before: int = m.S.cards.size()
	if cards_btn.size() > 0:
		var mid: Button = cards_btn[cards_btn.size() / 2]
		pick_ok = await click_ctl(mid)
		clicks += 1
	else:
		say("   NOT VISIBLE: no timeline card is on screen to pick")
	await shot("04_card_picked")
	await drag("hand_r", Vector2(-70, -30))
	await shot("05_arm_dragged")
	var kept := false
	if await click_text("More"):
		kept = await click_menu_item(m.easy._more, "Save this pose as a card")
	await shot("06_pose_kept")
	var pl3 := await click_text("Play", true)
	var played3 := await wait_playing()
	await shot("07_pose_playing")
	var n_after: int = m.S.cards.size()
	say("   cards before %d, after %d" % [n_before, n_after])
	# done = the picked card's pose changed in place: a NEW card (count up) is not a change
	end_goal(pick_ok and kept and played3 and n_after == n_before, "(a card picked: %s, pose kept: %s, cards %d -> %d (a new card, not a change, when up), played: %s)" % [str(pick_ok), str(kept), n_before, n_after, str(played3)])

	# 4. A CHAIR FROM THE LIBRARY, THEN MAKE HIM SIT ON IT
	begin_goal("4 chair from the Library, then make him sit on it")
	var lib := await click_text("Library")
	await shot("08_library_open")
	var fur := await click_text("Furniture", true)
	await shot("09_furniture_tab")
	var chair := await click_text("Chair", true)
	await shot("10_chair_placed")
	var pelvis_y0: float = ((m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5).y
	var sit_btn_visible := find_btn("Sit", true) != null
	say("   '%s' button visible after the chair: %s | pelvis y %.3f" % ["Sit...", str(sit_btn_visible), pelvis_y0])
	if lib and find_btn("Library") != null:
		await click_text("Library")
	var sat := false
	var n4: int = m.S.cards.size()
	var ch := await click_text("Change it")
	var bx := box()
	if bx != null:
		await click_ctl(bx)
		clicks += 1
		await type_text("sit on the chair", true)
		await idle(30)
		sat = m.S.cards.size() > n4
	else:
		say("   NOT VISIBLE: no text box to type the sit in")
	await shot("11_sit_on_chair")
	var pelvis_y1: float = ((m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5).y
	say("   pelvis y before %.3f, after the sit %.3f" % [pelvis_y0, pelvis_y1])
	end_goal(chair and sat, "(chair placed: %s, sit-on-chair built and played: %s; the picture decides whether it lands on the seat)" % [str(chair), str(sat)])

	# 5. SAVE, NEW SCENE, OPEN AGAIN
	begin_goal("5 save the scene, close it (New scene), open it again")
	var before5: Array = card_names()
	var sv := await click_text("More")
	var sv2 := await click_menu_item(m.easy._more, "Save the scene")
	await idle(20)
	await shot("12_saved")
	var saved_path: String = str(m.scene_path)
	say("   scene file: %s" % saved_path)
	var nw := await click_text("New scene")
	var dont := false
	if find_btn("Don't save") != null or find_btn("Save", false) != null:
		await shot("13_new_scene_question")
		dont = await click_text("Don't save") if find_btn("Don't save") != null else false
	await idle(20)
	await shot("14_new_scene_empty")
	var cleared: bool = m.S.cards.is_empty()
	var op := await click_text("More")
	var op2 := await click_menu_item(m.easy._more, "Open a saved scene")
	await idle(10)
	await shot("15_open_list")
	var want_name := saved_path.get_file().get_basename().replace("_", " ")
	var op3 := await click_menu_item(m.easy._menu, want_name)
	await idle(30)
	await shot("16_reopened")
	var after5: Array = card_names()
	say("   cards before save %s | after reopen %s" % [str(before5), str(after5)])
	end_goal(sv and sv2 and nw and cleared and op3 and after5 == before5, "(saved: %s, cleared: %s, reopened: %s, same cards: %s)" % [str(sv2), str(cleared), str(op3), str(after5 == before5)])

	# 6. A SECOND CLIP: WAVE; SAVE THE VIDEO; FIND THE FILE
	begin_goal("6 second clip: wave; save the video; find the file")
	var chg := await click_text("Change it")
	await shot("17_panel_again")
	var wv := await click_text("Wave", false)
	var wplay := await wait_playing()
	await shot("18_wave_built")
	var vid := await click_text("Save video")
	var tw := Time.get_ticks_msec()
	while m.easy.home.last_video.is_empty() and Time.get_ticks_msec() - tw < 240000:
		await process_frame
	await idle(10)
	var mp4 := String(m.easy.home.last_video.get("mp4", ""))
	var exists := mp4 != "" and FileAccess.file_exists(mp4)
	await shot("19_video_saved")
	var toast := ""
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "" and (n as Label).text.length() > 20:
			toast += " || " + (n as Label).text
	say("   toast/long text: " + toast)
	say("   file on disk: %s (%s)" % [mp4, str(exists)])
	end_goal(wv and wplay and vid and exists, "(wave built: %s, mp4: %s)" % [str(wv), mp4])

	# 7. THE SIDE VIEW, THEN BACK TO THE FRONT
	begin_goal("7 turn the camera to see him from the side, then back to the front")
	var yaw0: float = m.yaw   # degrees (main.gd: pitch and yaw are degrees)
	var vp := root.get_visible_rect().size
	var empty_p := Vector2(vp.x * 0.88, vp.y * 0.42)
	await right_drag(empty_p, Vector2(240, 0))
	await shot("20_turned")
	var yaw1: float = m.yaw
	var side := absf(yaw1 - yaw0) > 60.0
	say("   yaw %.1f -> %.1f deg" % [yaw0, yaw1])
	await right_drag(empty_p, Vector2(-240, 0))
	await shot("21_turned_back")
	var yaw2: float = m.yaw
	var back := absf(yaw2 - yaw0) < 5.0
	say("   yaw back %.1f deg" % yaw2)
	var front_btn := find_btn("Front", true) != null or find_btn("View", true) != null or find_btn("Side", true) != null
	say("   a view button on screen: %s" % str(front_btn))
	end_goal(side and back, "(side: %s, back to front: %s)" % [str(side), str(back)])

	# 8. HELP: what a beginner clicks when stuck, then "how do I make him jump"
	begin_goal("8 find help: ? / Help / tour; then 'how do I make him jump'")
	var help_btns := []
	for b in visible_buttons():
		var t := text_of(b).to_lower()
		if t.contains("help") or t == "?" or t.contains("tour") or t.contains("how"):
			help_btns.append(text_of(b))
	say("   help-like buttons on screen: %s" % str(help_btns))
	await shot("22_help_look")
	var hb := await click_text("Help", true)   # the buttons a beginner would try; each one reports NOT VISIBLE when it is not there
	var hp := await click_text("?", false)
	var tour := await click_text("Tour", true)
	var jump_ok := false
	var chg8 := await click_text("Change it")
	var bx8 := box()
	if bx8 != null:
		await click_ctl(bx8)
		clicks += 1
		await type_text("how do I make him jump", true)
		await idle(20)
		await shot("23_how_do_i_jump")
		var said := ""
		for n in visible_nodes():
			if n is Label and (n as Label).text.strip_edges() != "":
				said += " || " + (n as Label).text
		say("   words after the typed question: %s" % said)
		for n in visible_nodes():
			if n is Label and (n as Label).text.to_lower().contains("jump") and (n as Label).text.length() > 14 and not (n as Label).text.to_lower().contains("doesn't know"):
				jump_ok = true
	else:
		say("   NOT VISIBLE: no text box after 'Change it'")
	end_goal(jump_ok, "(help button found: %s, answer found: %s)" % [str(hb or hp or tour), str(jump_ok)])

	say("\nlast video: " + str(m.easy.home.last_video))
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
