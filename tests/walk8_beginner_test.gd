## godot --headless? no: godot --path . -s tests/walk8_beginner_test.gd   (BEGINNER WALK-THROUGH, round 8: EASY mode, real clicks)
## Eight goals a person who never used animation software would try, using only what is on screen: jump and make it higher;
## punch, then kick, then the kick's moment on the slider; a football on the floor and kicked; "dance" typed; slower, then undo;
## a sword from the Library swung, then removed; the video saved and where it went; a new scene, the old one opened and played.
## Every press is a real mouse click on a visible control found by its words; every sentence is typed. A goal the UI does not
## offer is reported NOT DONE with what was visible. Nothing is worked around. The toast's "Open folder" is NOT pressed
## (it opens Explorer on Nick's desktop): the test checks the button and the path it shows instead.
## Screenshots go to C:/Temp/claude/walk8/. The AI video "Make it with AI video" button is NEVER pressed.
extends SceneTree

const OUT := "C:/Temp/claude/walk8/"

var made: Array = []   # scene files this run saved (deleted at the end when they sit in scenes/_wip)
var m: Node
var n_shot := 0
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""
var notes: Array = []  # friction notes for the report (per goal)
var videos_before: Array = []
var results: Array = []  # [goal, done, clicks, seconds, note] for the table


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


## every visible label on a button (a Library tile has a caption label "Sports" AND its name label "Football")
func labels_of(b: Button) -> Array:
	var out := [text_of(b)]
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges())
	return out


func find_btn(txt: String, prefix := false) -> Button:
	for b in visible_buttons():
		for t in labels_of(b):
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


func hit_name(_p: Vector2) -> String:
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
	say("   click '%s' (tooltip: '%s')" % [text_of(b), b.tooltip_text])
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


## a real drag on the Easy scrub slider (eh_scrub) to a fraction of its width: the beginner's way to find a moment
func scrub_to(frac: float) -> bool:
	var s := m.find_child("eh_scrub", true, false) as HSlider
	if s == null or not s.is_visible_in_tree():
		say("   NOT VISIBLE: no eh_scrub slider on screen")
		return false
	clicks += 1
	var r := s.get_global_rect()
	var p := Vector2(r.position.x + r.size.x * frac, r.get_center().y)
	say("   drag eh_scrub to %.0f%% (tooltip: '%s')" % [frac * 100.0, s.tooltip_text])
	await hover(p)
	mouse_btn(true, p)
	await process_frame
	for i in 4:
		move(p + Vector2(i, 0), Vector2(1, 0))
		await process_frame
	mouse_btn(false, p)
	await idle(6)
	return true


func body_on_screen() -> bool:
	var c: Array = m.B.cap("pelvis")
	var at: Vector3 = (c[0] + c[1]) * 0.5
	var vp := m.get_viewport().get_visible_rect()
	return not m.cam.is_position_behind(at) and vp.has_point(m.cam.unproject_position(at))


func pelvis_y() -> float:
	return ((m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5).y


## the highest the pelvis gets during one play of the clip (from the start); NAN if it did not play
func play_peak() -> float:
	var ok := await wait_playing()
	if not ok:
		return NAN
	var top := -INF
	for i in 1200:
		if not m.playing:
			break
		top = maxf(top, pelvis_y())
		await process_frame
	return top


func toast_words() -> String:
	var h = m.easy.home
	if h == null or h._toast == null or not h._toast.visible:
		return "(no toast)"
	return "toast: '%s' [button '%s' tooltip '%s']" % [h._toast_text.text, h._toast_show.text, h._toast_show.tooltip_text]


func status_words() -> String:
	var out := []
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			var t := (n as Label).text.strip_edges()
			if t.length() > 3:
				out.append(t)
	return str(out.slice(0, 12))


func shot(name: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	n_shot += 1
	var f := "%s%02d_%s.png" % [OUT, n_shot, name]
	root.get_texture().get_image().save_png(f)
	say("   shot %s | body on screen: %s | cards: %d | props: %d | playing: %s" % [f, str(body_on_screen()), m.S.cards.size(), m.S.props.size(), str(m.playing)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())
	say("   " + toast_words())


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func end_goal(ok: bool, note_s: String) -> void:
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	say("== END %s: done=%s clicks=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, secs, note_s])
	results.append([goal, ok, clicks, secs, note_s])


func note(s: String) -> void:
	notes.append("[%s] %s" % [goal.get_slice(" ", 0), s])
	say("   FRICTION: " + s)


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


func has_card(word: String) -> bool:
	for s in card_names():
		if s.to_lower().contains(word):
			return true
	return false


func count_card(word: String) -> int:
	var k := 0
	for s in card_names():
		if s.to_lower().contains(word):
			k += 1
	return k


func words_say() -> String:
	var said := ""
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			said += " || " + (n as Label).text.strip_edges()
	return said


func box() -> LineEdit:
	return visible_line_edit("or type")


## types a move into the text box (the panel comes back first with Change it when a clip is there)
func press_key(kc: Key, ctrl := false) -> void:
	var kd := InputEventKey.new()
	kd.keycode = kc
	kd.physical_keycode = kc
	kd.ctrl_pressed = ctrl
	kd.pressed = true
	root.push_input(kd)
	await process_frame
	var ku := InputEventKey.new()
	ku.keycode = kc
	ku.physical_keycode = kc
	ku.ctrl_pressed = ctrl
	ku.pressed = false
	root.push_input(ku)
	await process_frame


func type_move(words: String) -> bool:
	var bx := box()
	if bx == null:
		say("   NOT VISIBLE: no text box")
		return false
	await click_ctl(bx)
	clicks += 1
	# the box keeps the last words typed (a refused 'dance' stays): a beginner selects all and deletes first
	if bx.text != "":
		say("   the box still says '%s': select all and delete" % bx.text)
		await press_key(KEY_A, true)
		await press_key(KEY_BACKSPACE)
	await type_text(words, true)
	await idle(30)
	return true


func _init() -> void:
	EasyMode.start_fresh = true
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if not m.easy.on:
		m.easy.set_on(true)
		await idle(10)
		say("   forced Easy (set_on(true)) | Easy now: %s" % str(m.easy.on))
	say("start: home panel %s | words: %s" % [m.easy.home.shown(), visible_words()])
	videos_before = _kine_videos() + _kine_dirs()   # files AND folders that were there before this run: never removed

	# 1. MAKE HIM JUMP, THEN HIGHER
	begin_goal("1 make him jump, then make the jump higher")
	var base1 := pelvis_y()
	var j1 := await click_text("Jump")
	var pk1a := await play_peak()
	await shot("01_jump_played")
	var h1a := pk1a - base1
	var big1 := await click_text("Bigger")
	await idle(20)
	var pk1b := NAN
	var ag1 := await click_text("Again")
	if ag1:
		pk1b = await play_peak()
	await shot("02_jump_bigger")
	var h1b := pk1b - base1
	say("   jump rise: %.3f m, then Bigger: %.3f m" % [h1a, h1b])
	if not big1:
		note("no 'Bigger' button after the jump: the strip's four tweak buttons are the only way to change height")
	end_goal(j1 and ag1 and not is_nan(h1b) and h1b > h1a * 1.05, "(jump card: %s, rise %.3f m, after Bigger %.3f m)" % [str(j1), h1a, h1b])

	# 2. PUNCH, THEN KICK, THEN THE KICK'S MOMENT ON THE SLIDER
	begin_goal("2 make him punch, then kick, then check when the kick lands with the slider")
	var ch2 := await click_text("Change it")
	var pu2 := await click_text("Punch")
	await shot("03_punch_built")
	var ch2b := await click_text("Change it")
	var ki2 := await click_text("Kick")
	await shot("04_kick_built")
	var both2: bool = has_card("cross") and has_card("roundhouse")
	var len2: float = m.S.length()
	var sc2 := await scrub_to(0.6)
	await shot("05_slider_at_60")
	var ph2: float = m.playhead
	say("   playhead after the drag: %.2f s of %.2f s (60%% = %.2f s) | label: %s" % [ph2, len2, len2 * 0.6, str((m.find_child("eh_scrub_time", true, false) as Label).text) if m.find_child("eh_scrub_time", true, false) != null else "(no label)"])
	var slid2: bool = sc2 and absf(ph2 - len2 * 0.6) < len2 * 0.1
	if not slid2:
		note("the slider did not land the playhead at 60%% (playhead %.2f of %.2f s)" % [ph2, len2])
	note("the slider shows a time, not the kick's landing: the beginner has to guess which frame is the hit (no marker on the slider)")
	end_goal(pu2 and ki2 and both2 and slid2, "(punch: %s, kick: %s, cards %s, slider moved the playhead: %s)" % [str(pu2), str(ki2), str(card_names()), str(slid2)])

	# 3. A FOOTBALL ON THE FLOOR, AND KICK IT
	begin_goal("3 put a football on the floor and kick it")
	var props3: int = m.S.props.size()
	var lib3 := await click_text("Library")
	var sp3 := await click_text("Sports", true)
	await shot("06_sports_tab")
	var ball3 := await click_text("Football", true)
	await idle(10)
	await shot("07_ball_on_floor")
	var cl3 := await click_text("Close")
	var ballp3: bool = m.S.props.size() > props3
	var n3: int = m.S.cards.size()
	var ch3 := await click_text("Change it")
	var ki3 := await click_text("Kick")
	await idle(30)
	await shot("08_football_kicked")
	var said3 := words_say()
	var line3: bool = said3.contains("doesn't fly")
	say("   say line mentions the ball: %s | words: %s" % [str(line3), said3.left(300)])
	if not line3:
		note("after a kick with a ball on the floor, the say line does not mention the ball")
	end_goal(lib3 and ball3 and ballp3 and ki3 and m.S.cards.size() > n3 and line3, "(football placed: %s, props %d -> %d, kick added: %s, ball sentence: %s)" % [str(ball3), props3, m.S.props.size(), str(ki3), str(line3)])

	# 4. MAKE HIM DANCE (typed, the way Kine takes a word it has no card for)
	begin_goal("4 make him dance")
	var n4: int = m.S.cards.size()
	var ch4 := await click_text("Change it")
	var typed4 := await type_move("dance")
	await shot("09_dance_typed")
	var ans4 := words_say()
	say("   answer under the box: %s" % ans4.left(500))
	var dance4: bool = has_card("danc") or m.S.cards.size() > n4
	if not dance4:
		note("'dance' typed: no card added; the answer was: %s" % ans4.left(160))
	note("the Easy cards have no dance: the picture grid offers 8 moves and nothing says which words Kine knows")
	end_goal(typed4 and has_card("danc"), "(typed: %s, cards %d -> %d, dance card: %s)" % [str(typed4), n4, m.S.cards.size(), str(has_card("danc"))])

	# 5. SLOWER, THEN UNDO
	begin_goal("5 make the whole thing slower, then undo it")
	var len5a: float = m.S.length()
	if find_btn("Slower") == null:
		say("   'Slower' not on screen: the panel is open; pressing Escape (it goes back to the strip)")
		await press_key(KEY_ESCAPE)
		await idle(20)
	var sl5 := await click_text("Slower")
	await idle(20)
	var len5b: float = m.S.length()
	await shot("10_slower")
	var slowed5: bool = m.S.length() > len5a * 1.1
	if not slowed5:
		note("Slower did not change the clip (%.2f s): the say line gave the reason; Undo is not pressed, so it does not take back another step" % m.S.length())
	var und5 := await click_text("Undo") if slowed5 else false
	await idle(20)
	var len5c: float = m.S.length()
	await shot("11_undone")
	say("   clip length %.2f s -> slower %.2f s -> undo %.2f s" % [len5a, len5b, len5c])
	end_goal(sl5 and und5 and slowed5 and absf(len5c - len5a) < 0.01, "(slower: %s, length %.2f -> %.2f, undo: %s -> %.2f)" % [str(sl5), len5a, len5b, str(und5), len5c])

	# 6. A SWORD FROM THE LIBRARY, SWUNG, THEN REMOVED
	begin_goal("6 give him a sword from the Library, swing it, then remove the sword")
	var lib6 := await click_text("Library")
	var wp6 := await click_text("Weapons", true)
	var sw6 := await click_text("Sword")
	await shot("12_sword_picked")
	var cl6 := await click_text("Close")
	var held6: bool = m.B.wep_on
	say("   sword in his hand (body.wep_on): %s" % str(held6))
	var n6: int = m.S.cards.size()
	var ch6 := await click_text("Change it")
	var typed6 := await type_move("sword swing")
	await shot("13_swing_typed")
	var swing6: bool = m.S.cards.size() > n6 and words_say().contains("swing")   # the cards are named by phase (no 'swing' in the name)
	# removing the sword: the words a beginner would read on a button (none of these is named for a held weapon yet)
	var rem6 := false
	for t in ["Remove sword", "Put the sword away", "Put away", "Drop", "Empty hand", "Drop sword"]:
		var b6 := find_btn(t, true)
		if b6 != null:
			rem6 = await click_text(t, true)
			break
	if not rem6:
		say("   NOT VISIBLE: no button to take the sword out of his hand (tried: Remove sword, Put away, Drop, Empty hand)")
		note("no control takes a held sword out of his hand: the prop bar's Remove is for objects on the floor only")
	await idle(20)
	if not rem6 and m.B.wep_on:
		note("the sword is still in his hand; the only thing that takes it away is Undo, which also takes back the swing")
		for i in 4:
			if not m.B.wep_on:
				break
			await click_text("Undo")
			await idle(20)
	var held6b: bool = m.B.wep_on
	await shot("14_sword_removed")
	say("   sword in his hand after the removal try: %s" % str(held6b))
	end_goal(sw6 and held6 and swing6 and not held6b, "(sword picked: %s, in hand: %s, swing card: %s, removed by a sword control: %s, hand empty after: %s, by Undo presses)" % [str(sw6), str(held6), str(swing6), str(rem6), str(not held6b)])

	# 7. SAVE THE VIDEO AND FIND IT; SAVE THE SCENE
	begin_goal("7 save the video and find where it was saved; save the scene")
	var before7: Array = card_names()
	var vid7 := await click_text("Save video")
	var tw := Time.get_ticks_msec()
	while m.easy.home.last_video.is_empty() and Time.get_ticks_msec() - tw < 240000:
		await process_frame
	await idle(10)
	var mp4 := String(m.easy.home.last_video.get("mp4", ""))
	var vdir := String(m.easy.home.last_video.get("dir", ""))
	var exists7 := (mp4 != "" and FileAccess.file_exists(mp4)) or (vdir != "" and DirAccess.dir_exists_absolute(vdir))
	await shot("15_video_saved")
	var toast7: bool = m.easy.home._toast.visible and m.easy.home._toast_show.visible
	var named7: bool = toast7 and m.easy.home._toast_text.text.contains("Kine") or (toast7 and m.easy.home._toast_text.text.contains(mp4.get_file()))
	say("   file on disk: %s (%s) | folder %s | toast names it: %s" % [mp4, str(exists7), vdir, str(named7)])
	if not toast7:
		note("saved video: no toast with an Open folder button on screen")
	var sv7 := await click_text("More")
	var sv7b := await click_menu_item(m.easy._more, "Save the scene")
	await idle(20)
	await shot("16_scene_saved")
	var saved_path: String = str(m.scene_path)
	if saved_path != "":
		made.append(saved_path)
	say("   scene file: %s" % saved_path)
	end_goal(vid7 and exists7 and toast7 and sv7b, "(video saved: %s, file: %s, toast names the folder: %s, Open folder shows it (not pressed), scene saved: %s)" % [str(vid7), str(exists7), str(named7), str(sv7b)])

	# 8. NEW SCENE, OPEN THE PREVIOUS ONE, PLAY IT
	begin_goal("8 start a new scene, open the previous one again, play it")
	var nw8 := await click_text("New scene")
	if find_btn("Don't save") != null:
		await shot("17_new_scene_question")
		await click_text("Don't save")
	await idle(20)
	await shot("18_new_scene_empty")
	var cleared8: bool = m.S.cards.is_empty()
	var op8 := await click_text("More")
	var op8b := await click_menu_item(m.easy._more, "Open a saved scene")
	await idle(10)
	await shot("19_open_list")
	var want8 := saved_path.get_file().get_basename().replace("_", " ")
	var op8c := await click_menu_item(m.easy._menu, want8)
	await idle(30)
	var after8: Array = card_names()
	var played8 := false
	if m.playing:
		note("the opened scene was already playing (the bar shows Stop): nothing to press")
		played8 = true
	elif find_btn("Play", true) != null:
		await click_text("Play", true)
		played8 = await wait_playing()
	var pl8 := played8
	await shot("20_reopened_played")
	say("   cards before %s | after reopen %s | played: %s" % [str(before7), str(after8), str(played8)])
	end_goal(nw8 and cleared8 and op8c and pl8 and played8 and after8 == before7, "(new scene cleared: %s, reopened: %s, same cards: %s, played: %s)" % [str(cleared8), str(op8c), str(after8 == before7), str(played8)])

	say("\nfriction notes:")
	for s in notes:
		say("  " + s)
	say("\nSUMMARY (goal | done | clicks | seconds):")
	for r in results:
		say("  %s | %s | %d | %.1f" % [r[0], "yes" if r[1] else "NO", r[2], r[3]])
	say("\nlast video: " + str(m.easy.home.last_video))
	for p in made:   # only the scene files this run saved, and only where the run put them under scenes/_wip
		if p.contains("_wip") and FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			say("removed the run's scene file " + p)
	# the Videos/Kine files this run made (the folder existed before: only the new files go)
	for f in _kine_videos():
		if not videos_before.has(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("C:/Users/Nick/Videos/Kine/" + f))
			say("removed the run's video " + f)
	for d in _kine_dirs():
		if not videos_before.has(d):
			_rm_tree("C:/Users/Nick/Videos/Kine/" + d)
			say("removed the run's video folder " + d)
	var lf := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\n")
	lf.close()
	quit(0)


func _kine_videos() -> Array:
	return Array(DirAccess.get_files_at("C:/Users/Nick/Videos/Kine"))


func _kine_dirs() -> Array:
	return Array(DirAccess.get_directories_at("C:/Users/Nick/Videos/Kine"))


func _rm_tree(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "/" + f))
	for d in DirAccess.get_directories_at(path):
		_rm_tree(path + "/" + d)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
