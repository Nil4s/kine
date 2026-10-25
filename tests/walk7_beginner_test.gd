## godot --headless? no: godot --path . --position 3000,3000 -s tests/walk7_beginner_test.gd   (BEGINNER WALK-THROUGH, round 7: EASY mode, real clicks)
## Eight goals a non-technical person would try: a chair, sit, stand and wave, slower and the side view, remove the chair,
## a sword swung twice, undo x3 and redo, save the video and the scene and open it again, an unknown move typed.
## Every press is a real mouse click on a visible button whose label matches the goal; every sentence is typed.
## A goal the UI does not offer is reported NOT DONE with what was visible. Nothing is worked around.
## Screenshots go to C:/Temp/claude/walk7/. The AI video "Make it with AI video" button is NEVER pressed.
extends SceneTree

const OUT := "C:/Temp/claude/walk7/"

var made: Array = []   # scene files this run saved (deleted at the end when they sit in scenes/_wip)
var m: Node
var n_shot := 0
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""
var notes: Array = []  # friction notes for the report (per goal)
var videos_before: Array = []


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


## every visible label on a button (a Library tile has a caption label "Furniture" AND its name label "Chair")
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


func pelvis_y() -> float:
	return ((m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5).y


func shot(name: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	n_shot += 1
	var f := "%s%02d_%s.png" % [OUT, n_shot, name]
	root.get_texture().get_image().save_png(f)
	say("   shot %s | body on screen: %s | cards: %d | props: %d | playing: %s" % [f, str(body_on_screen()), m.S.cards.size(), m.S.props.size(), str(m.playing)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func end_goal(ok: bool, note: String) -> void:
	say("== END %s: done=%s clicks=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, (Time.get_ticks_msec() - t0) / 1000.0, note])


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


func words_say(word: String) -> String:
	var said := ""
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			said += " || " + (n as Label).text.strip_edges()
	return said


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
	videos_before = _kine_videos()

	# 1. A CHAIR FROM THE LIBRARY, THEN WALK TO IT AND SIT ON IT
	begin_goal("1 chair from the Library, walk to it, sit on it")
	var lib1 := await click_text("Library")
	var fur1 := await click_text("Furniture", true)
	await shot("01_furniture_tab")
	var chair1 := await click_text("Chair", true)
	await shot("02_chair_placed")
	var close1 := await click_text("Close")
	await shot("03_library_closed")
	var n1: int = m.S.cards.size()
	var walk1 := await click_text("Walk")
	var played1 := await wait_playing()
	await shot("04_walk_built")
	var sit1 := await click_text("Sit on the chair")
	await idle(30)
	await shot("05_sit_on_chair")
	var sat1: bool = m.S.cards.size() > n1 and has_card("seated")
	if not sit1:
		note("'Sit on the chair' not on screen after the walk")
	end_goal(chair1 and walk1 and played1 and sat1, "(chair placed: %s, walk: %s, sit on it pressed: %s, seated card: %s; cards %d -> %d; pelvis y %.3f)" % [str(chair1), str(walk1), str(sit1), str(sat1), n1, m.S.cards.size(), pelvis_y()])

	# 2. AFTER SITTING: STAND UP AND WAVE (typed first: the box is what a beginner reaches for)
	begin_goal("2 after sitting: stand up and wave")
	var n2: int = m.S.cards.size()
	var chg2 := await click_text("Change it")
	await shot("06_panel_after_sit")
	var typed2 := false
	var bx2 := box()
	if bx2 != null:
		await click_ctl(bx2)
		clicks += 1
		await type_text("stand up then wave", true)
		await idle(30)
		typed2 = m.S.cards.size() > n2
		say("   after typing: cards %s" % str(card_names()))
	else:
		say("   NOT VISIBLE: no text box after 'Change it'")
	await shot("07_stand_and_wave_typed")
	var said2 := words_say("")
	if not typed2:
		note("typed 'stand up then wave': no clip added (words: %s)" % said2.left(200))
	var wave2 := true
	if not has_card("wave") or not typed2:
		var nw := await click_text("Then wave", true)
		if nw:
			await idle(30)
		else:
			wave2 = false
	await shot("08_wave_built")
	var stood := has_card("rising") and has_card("wave")
	end_goal(stood, "(typed stand+wave added a clip: %s, rise cards: %s, wave card: %s, cards %d -> %d)" % [str(typed2), str(has_card("rising")), str(has_card("wave")), n2, m.S.cards.size()])

	# 3. MAKE IT SLOWER, THEN WATCH IT FROM THE SIDE
	begin_goal("3 make it slower, then watch it from the side")
	var slow3 := await click_text("Slower")
	await idle(20)
	await shot("09_slower")
	var yaw0: float = m.yaw
	var side3 := await click_text("Side")
	await idle(20)
	await shot("10_side_view")
	var yaw1: float = m.yaw
	say("   yaw %.1f -> %.1f" % [yaw0, yaw1])
	var side_ok := absf(yaw1 - yaw0) > 60.0
	if not m.playing:
		var pb3 := find_btn("Play", true)
		if pb3 != null:
			await click_text("Play", true)
			await wait_playing()
	await shot("11_side_playing")
	end_goal(slow3 and side3 and side_ok, "(slower: %s, side view clicked: %s, yaw changed %.0f deg, playing: %s)" % [str(slow3), str(side3), absf(yaw1 - yaw0), str(m.playing)])

	# 4. REMOVE THE CHAIR: what happens to the sitting?
	begin_goal("4 remove the chair, see what happens to the sitting")
	var props4: int = m.S.props.size()
	var y4a := pelvis_y()
	var bar4 := m.find_child("eh_prop_name", true, false) as Label
	say("   prop bar says: %s" % (bar4.text if bar4 != null else "(no bar)"))
	var rm_btn := find_btn("Remove")
	if rm_btn == null:
		say("   'Remove' not on screen (no prop picked?): trying 'Next object'")
		await click_text("Next object")
		rm_btn = find_btn("Remove")
	var rm4 := false
	if rm_btn != null:
		rm4 = await click_text("Remove")
	else:
		say("   NOT VISIBLE: no 'Remove' button after picking the next object")
	await idle(20)
	await shot("12_chair_removed")
	var y4b := pelvis_y()
	var warn4 := words_say("")
	say("   props %d -> %d | pelvis y %.3f -> %.3f" % [props4, m.S.props.size(), y4a, y4b])
	say("   words after the removal: %s" % warn4.left(400))
	if warn4.to_lower().contains("chair") or warn4.to_lower().contains("sit"):
		say("   a sentence mentions the chair or the sit")
	end_goal(rm4 and m.S.props.size() < props4, "(remove pressed: %s, props %d -> %d, pelvis y %.3f -> %.3f: the seat is gone, the cards still say 'seated')" % [str(rm4), props4, m.S.props.size(), y4a, y4b])

	# 5. A SWORD IN HIS HAND, SWUNG TWICE
	begin_goal("5 sword in his hand, swing it twice")
	var lib5 := await click_text("Library")
	var wep5 := await click_text("Weapons", true)
	await shot("13_weapons_tab")
	var sw5 := await click_text("Sword")
	await shot("14_sword_picked")
	var close5 := await click_text("Close")
	var held5: bool = m.B.wep_on
	say("   sword in his hand (body.wep_on): %s" % str(held5))
	var n5: int = m.S.cards.size()
	var sw_typed := false
	var cb5 := await click_text("Change it")
	var bx5 := box()
	if bx5 != null:
		await click_ctl(bx5)
		clicks += 1
		await type_text("sword swing", true)
		await idle(30)
		sw_typed = m.S.cards.size() > n5
	else:
		say("   NOT VISIBLE: no text box after 'Change it'")
	await shot("15_swing_once")
	var second5 := await click_text("Then sword swing", true)
	if second5:
		await idle(30)
	await shot("16_swing_twice")
	var swings: int = 0
	for s in card_names():
		if s.to_lower().contains("swing"):
			swings += 1
	say("   swing cards: %d | cards now %s" % [swings, str(card_names())])
	end_goal(sw5 and held5 and sw_typed and swings >= 2, "(sword picked: %s, in hand: %s, swing typed: %s, 'Then sword swing' pressed: %s, swing cards: %d)" % [str(sw5), str(held5), str(sw_typed), str(second5), swings])

	# 6. UNDO THREE TIMES, REDO ONCE
	begin_goal("6 undo three times, redo once")
	var seq6: Array = [card_names().size()]
	var ok6 := true
	for i in 3:
		var u := await click_text("Undo")
		ok6 = ok6 and u
		seq6.append(card_names().size())
		await shot("17_undo_%d" % (i + 1))
		say("   after undo %d: cards %s" % [i + 1, str(card_names())])
	var r6 := await click_text("Redo")
	seq6.append(card_names().size())
	await shot("18_redo")
	say("   after redo: cards %s" % str(card_names()))
	say("   card counts through the presses: %s" % str(seq6))
	var changed6 := true
	for i in range(1, seq6.size()):
		if seq6[i] == seq6[i - 1]:
			changed6 = false
	if not changed6:
		note("some press did not change the card count (counts %s): the undo history is by step, not by visible card" % str(seq6))
	end_goal(ok6 and r6, "(undo x3 found: %s, redo found: %s, counts %s, every press changed the cards: %s)" % [str(ok6), str(r6), str(seq6), str(changed6)])

	# 7. SAVE THE VIDEO; SAVE THE SCENE; NEW SCENE; OPEN IT AGAIN
	begin_goal("7 save the video, save the scene, new scene, open it again")
	var before7: Array = card_names()
	var vid7 := await click_text("Save video")
	var tw := Time.get_ticks_msec()
	while m.easy.home.last_video.is_empty() and Time.get_ticks_msec() - tw < 240000:
		await process_frame
	await idle(10)
	var mp4 := String(m.easy.home.last_video.get("mp4", ""))
	var exists7 := mp4 != "" and FileAccess.file_exists(mp4)
	await shot("19_video_saved")
	say("   file on disk: %s (%s)" % [mp4, str(exists7)])
	var sv7 := await click_text("More")
	var sv7b := await click_menu_item(m.easy._more, "Save the scene")
	await idle(20)
	await shot("20_scene_saved")
	var saved_path: String = str(m.scene_path)
	if saved_path != "":
		made.append(saved_path)
	say("   scene file: %s" % saved_path)
	var nw7 := await click_text("New scene")
	if find_btn("Don't save") != null:
		await shot("21_new_scene_question")
		await click_text("Don't save")
	await idle(20)
	await shot("22_new_scene_empty")
	var cleared7: bool = m.S.cards.is_empty()
	var op7 := await click_text("More")
	var op7b := await click_menu_item(m.easy._more, "Open a saved scene")
	await idle(10)
	await shot("23_open_list")
	var want7 := saved_path.get_file().get_basename().replace("_", " ")
	var op7c := await click_menu_item(m.easy._menu, want7)
	await idle(30)
	await shot("24_reopened")
	var after7: Array = card_names()
	say("   cards before %s | after reopen %s" % [str(before7), str(after7)])
	end_goal(vid7 and exists7 and sv7b and nw7 and cleared7 and op7c and after7 == before7, "(video file: %s, scene saved: %s, new scene cleared: %s, reopened: %s, same cards: %s)" % [str(exists7), str(sv7b), str(cleared7), str(op7c), str(after7 == before7)])

	# 8. AN UNKNOWN MOVE: jumping jack, typed
	begin_goal("8 type a move that is not a card: 'jumping jack'")
	var chg8 := await click_text("Change it")
	var bx8 := box()
	var answer8 := ""
	if bx8 != null:
		await click_ctl(bx8)
		clicks += 1
		await type_text("jumping jack", true)
		await idle(30)
		answer8 = words_say("")
		await shot("25_jumping_jack")
	else:
		say("   NOT VISIBLE: no text box after 'Change it'")
	say("   answer: %s" % answer8.left(600))
	var answered := answer8.to_lower().contains("doesn't know") or answer8.to_lower().contains("jump") or answer8.to_lower().contains("try")
	var offered := answer8.to_lower().contains("punch") or answer8.to_lower().contains("kick") or answer8.to_lower().contains("wave")
	end_goal(bx8 != null and answered, "(answer shown: %s, cards offered in the answer: %s)" % [str(answered), str(offered)])

	say("\nfriction notes:")
	for s in notes:
		say("  " + s)
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
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)


func _kine_videos() -> Array:
	return Array(DirAccess.get_files_at("C:/Users/Nick/Videos/Kine"))
