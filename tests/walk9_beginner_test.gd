## godot --headless? no: godot --path . -s tests/walk9_beginner_test.gd   (BEGINNER WALK-THROUGH, round 9: EASY mode, real clicks)
## Six goals a person who never animated would try, using only what is on screen: 1 jump, then Bigger; 2 type dance, Slower, play;
## 3 Walk, then Then wave (the wave must come after the walk in time); 4 a sword from the Library by category, type swing; 5 pick a card,
## Cut start, Undo; 6 Save video (the file is KEPT and listed in the report). Every press is a real click on a visible control found by its words.
## Screenshots: the scratchpad walk9 folder. Nothing is deleted.
extends SceneTree

const OUT := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/walk9/"

var video_dir := ""      # the test's own folder for Save video (user://), so the user's Videos/Kine is never written
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
	if not ok:
		say("FAIL " + goal)
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



func card_node(i: int) -> Control:
	return m.ui_cards.get_node_or_null("card_%d" % (i + 1)) as Control


## the furthest the playhead gets during one play (the play that runs now or starts at once); NAN if none starts
func play_top(limit := 1500) -> float:
	var ok := await wait_playing()
	if not ok:
		return NAN
	var top := 0.0
	for i in limit:
		if not m.playing:
			break
		top = maxf(top, m.playhead)
		await process_frame
	return top


## the highest the pelvis gets during one play, above base (metres); NAN if none starts
func peak_to_end(base: float, limit := 1500) -> float:
	var ok := await wait_playing()
	if not ok:
		return NAN
	var top := -INF
	for i in limit:
		if not m.playing:
			break
		top = maxf(top, pelvis_y())
		await process_frame
	return top - base


func _init() -> void:
	EasyMode.start_fresh = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	video_dir = ProjectSettings.globalize_path("user://walk9_out_%d" % OS.get_process_id())   # the test's own folder: never the user's Videos/Kine
	DirAccess.make_dir_recursive_absolute(video_dir)
	m.easy.home.video_root = video_dir
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if not m.easy.on:
		m.easy.set_on(true)
		await idle(10)
		say("   forced Easy (set_on(true)) | Easy now: %s" % str(m.easy.on))
	say("start: home panel %s | words: %s" % [m.easy.home.shown(), visible_words()])
	await shot("00_start")

	# 1. JUMP, THEN BIGGER
	begin_goal("1 make him jump, then make the jump higher")
	var base1 := pelvis_y()
	var j1 := await click_text("Jump")
	var h1a := await peak_to_end(base1)
	await shot("01_jump_played")
	var big1 := await click_text("Bigger")   # the tweak plays the clip itself at once
	var h1b := await peak_to_end(base1)
	await shot("02_jump_bigger")
	say("   jump rise: %.3f m, after Bigger: %.3f m" % [h1a, h1b])
	if not big1:
		note("no 'Bigger' button on the strip after the jump")
	end_goal(j1 and big1 and not is_nan(h1b) and h1b > h1a * 1.05, "(jump rise %.3f m, after Bigger %.3f m)" % [h1a, h1b])

	# 2. TYPE DANCE, SLOWER, PLAY
	begin_goal("2 type dance, make it slower, play it")
	var n2: int = m.S.cards.size()
	var len2a: float = m.S.length()
	var ch2 := await click_text("Change it") if box() == null else false   # the strip hides the box: Change it brings it back
	var typed2 := await type_move("dance")
	await shot("03_dance_typed")
	say("   answer under the box: %s" % words_say().left(300))
	var dance2: bool = m.S.cards.size() > n2
	var len2b: float = m.S.length()
	var slow2 := await click_text("Slower")
	await idle(20)
	var len2c: float = m.S.length()
	await shot("04_slower")
	say("   clip %.2f s -> dance %.2f s -> slower %.2f s" % [len2a, len2b, len2c])
	var again2 := await click_text("Again")
	var top2 := await play_top()
	await shot("05_played")
	var played2: bool = not is_nan(top2) and top2 >= len2c * 0.9
	say("   played to %.2f s of %.2f s" % [top2, len2c])
	if not dance2:
		note("typed 'dance': no card was added (the answer above says why)")
	end_goal(typed2 and dance2 and slow2 and len2c > len2b * 1.1 and again2 and played2, "(dance card added: %s, slower %.2f -> %.2f s, played the whole clip: %s)" % [str(dance2), len2b, len2c, str(played2)])

	# 3. WALK, THEN WAVE (the wave must come after the walk)
	begin_goal("3 make a walk, then a wave after it, and check the order")
	var n3a: int = m.S.cards.size()
	var hidden3 := find_btn("Walk") == null   # the picture grid is shut after a clip: the Moves button must open it in one click
	var ch3 := await click_text("Moves") if hidden3 else false
	var moves3: bool = ch3 if hidden3 else true
	if not moves3:
		say("FAIL goal 3 moves: after a clip, no button on screen opens the move cards in one click (wanted 'Moves')")
	var walk3 := await click_text("Walk")
	await shot("06_walk_built")
	var walk_end3: float = m.S.length()
	var n3: int = m.S.cards.size()
	var then3 := await click_text("Then wave")
	await shot("07_then_wave")
	var t3: Array = m.S.times()
	var wave_start3: float = float((t3[n3] as Array)[0]) if t3.size() > n3 else -1.0   # times(): [start, move end, hold end] per card
	var wave_cards3: int = 0 if not words_say().contains("Made the wave") else m.S.cards.size() - n3   # the cards are named by phase; the say line names the move
	var after3: bool = then3 and walk3 and n3 > n3a and wave_cards3 > 0 and wave_start3 >= walk_end3 - 0.001
	say("   walk ends at %.2f s; wave starts at %.2f s (%d wave cards after the walk's %d cards)" % [walk_end3, wave_start3, wave_cards3, n3])
	var again3 := await click_text("Again")
	var top3 := await play_top()
	await shot("08_walk_wave_played")
	say("   played to %.2f s of %.2f s" % [top3, m.S.length()])
	if not then3:
		note("after the walk, no 'Then wave' button on the second row")
	end_goal(moves3 and after3 and again3 and top3 >= m.S.length() * 0.9, "(walk %.2f s, wave starts %.2f s, wave cards after: %d, whole clip played: %s)" % [walk_end3, wave_start3, wave_cards3, str(top3 >= m.S.length() * 0.9)])

	# 4. SWORD FROM THE LIBRARY, THEN TYPE SWING
	begin_goal("4 sword from the Library (by category), then type swing")
	var lib4 := await click_text("Library")
	var wp4 := await click_text("Weapons", true)
	var sw4 := await click_text("Sword")
	await shot("09_sword_picked")
	var cl4 := await click_text("Close")
	var held4: bool = m.B.wep_on
	var n4: int = m.S.cards.size()
	var ch4 := await click_text("Change it")
	var typed4 := await type_move("swing")
	await shot("10_swing_typed")
	say("   answer under the box: %s" % words_say().left(300))
	var swing4: bool = m.S.cards.size() > n4
	if not swing4:
		note("typed 'swing' alone: no card added (the answer above says why)")
	end_goal(lib4 and sw4 and held4 and typed4 and swing4, "(sword in hand: %s, swing cards %d -> %d)" % [str(held4), n4, m.S.cards.size()])

	# 5. CUT START, THEN UNDO
	begin_goal("5 cut the start of the clip, then undo it")
	var n5: int = m.S.cards.size()
	var pick5 := false
	if card_node(3) != null and card_node(3).is_visible_in_tree():
		pick5 = await click_ctl(card_node(3))
		say("   picked card 4 of %d: '%s'" % [n5, str(m.S.cards[3].get("name", "?"))])
	var cut5 := await click_text("Cut start")
	await shot("11_cut_start")
	var n5b: int = m.S.cards.size()
	var und5 := await click_text("Undo")
	await idle(20)
	var n5c: int = m.S.cards.size()
	await shot("12_undone")
	say("   cards %d -> cut %d -> undo %d" % [n5, n5b, n5c])
	var head5: Vector2 = m.cam.unproject_position(m.B.cap("head")[0]) if m.B.cap("head").size() > 0 else Vector2.ZERO
	var strip_bottom5: float = m.easy.home.strip.get_global_rect().end.y if m.easy.home.strip.is_visible_in_tree() else 0.0
	say("   head on screen at y %.0f, strip bottom at y %.0f" % [head5.y, strip_bottom5])
	if head5.y < strip_bottom5:
		note("after Cut start the strip covers his head (head y %.0f, strip bottom y %.0f): the camera framing is under the old strip size" % [head5.y, strip_bottom5])
	if not pick5:
		note("no card to pick on the strip: Cut start needs a card clicked first, and nothing on the strip says so")
	end_goal(pick5 and cut5 and n5b < n5 and und5 and n5c == n5, "(picked: %s, cut: %s, cards %d -> %d -> %d)" % [str(pick5), str(cut5), n5, n5b, n5c])

	# 6. SAVE VIDEO (KEPT: the file is listed in the report, not deleted)
	begin_goal("6 save the video and find the file")
	var vid6 := await click_text("Save video")
	var tw := Time.get_ticks_msec()
	while m.easy.home.last_video.is_empty() and Time.get_ticks_msec() - tw < 240000:
		await process_frame
	await idle(10)
	var mp4 := String(m.easy.home.last_video.get("mp4", ""))
	var size6 := 0
	if mp4 != "" and FileAccess.file_exists(mp4):
		var fh := FileAccess.open(mp4, FileAccess.READ)
		size6 = int(fh.get_length())
		fh.close()
	var toast6: bool = m.easy.home._toast.visible and m.easy.home._toast_show.visible
	await shot("13_video_saved")
	say("   VIDEO FILE: %s (%d bytes) | toast: %s" % [mp4, size6, toast_words()])
	if not toast6:
		note("saved video: no toast with an Open folder button on screen")
	end_goal(vid6 and size6 > 0 and toast6, "(video file %s, %d bytes, toast with Open folder: %s)" % [mp4, size6, str(toast6)])

	say("\nfriction notes:")
	for s in notes:
		say("  " + s)
	say("\nSUMMARY (goal | done | clicks | seconds):")
	for r in results:
		say("  %s | %s | %d | %.1f" % [r[0], "yes" if r[1] else "NO", r[2], r[3]])
	say("\nlast video: " + str(m.easy.home.last_video))
	if mp4 != "" and mp4.begins_with(video_dir) and FileAccess.file_exists(mp4):
		DirAccess.remove_absolute(mp4)   # the one file this run made, in its own folder under user://; the folder stays
		say("removed the run's video " + mp4)
	var lf := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\n")
	lf.close()
	quit(0)
