## godot --path . --position 3000,3000 -s tests/walk4_beginner_test.gd   (BEGINNER WALK-THROUGH, round 4: EASY mode, real clicks)
## A non-technical person's pass: every press is a real mouse click at the button's centre (a covered button is reported as
## "COVERED"), every pose a real drag. A screenshot after each step goes to C:/Temp/claude/walk4/. MEASURES, FIXES NOTHING.
## The log is printed and written to C:/Temp/claude/walk4/log.txt. Video: the Easy Save video button, into the Videos/Kine folder.
## The AI video button is NEVER pressed: only its text is read.
extends SceneTree

const OUT := "C:/Temp/claude/walk4/"

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
	for c in n.get_children(true):   # INTERNAL children too: a dialog's button row is internal (get_children() skips it)
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


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


## what a click at p lands on (the top control under the pointer): the test's own check that nothing covers the button
func hit_name(p: Vector2) -> String:
	var h := get_root().get_viewport().gui_get_hovered_control()
	return "none" if h == null else str(h.name) + " (" + h.get_class() + ")"


## a real click on a Control: the mouse goes down and up on its middle
func click_ctl(c: Control) -> bool:
	var p := c.get_global_rect().get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		say("   COVERED: the click at %s lands on %s, not on the button" % [str(p), hit_name(p)])
	btn(true, p)
	await process_frame
	btn(false, p)
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


## a real drag of a body part: press on it, move in steps, let go
func drag(j: String, d := Vector2(48, -48)) -> void:
	clicks += 1
	var c: Array = m.B.cap(j)
	var p: Vector2 = m.cam.unproject_position(c[0].lerp(c[1], 0.75))
	await hover(p)
	say("   drag '%s' from %s by %s (under the pointer: %s)" % [j, str(p), str(d), hit_name(p)])
	var st := d / 6.0
	btn(true, p)
	await process_frame
	for i in 6:
		move(p + st * (i + 1), st)
		await process_frame
	btn(false, p + d)
	await idle(3)


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


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func end_goal(ok: bool, note: String) -> void:
	say("== END %s: success=%s clicks=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, (Time.get_ticks_msec() - t0) / 1000.0, note])


func wait_playing(limit := 240) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


## typed keys into the focused box: one key event per character, then Enter if enter
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


func _init() -> void:
	EasyMode.start_fresh = true
	var vids: Variant = DirAccess.get_directories_at("C:/Users/Nick/Videos/Kine")
	say("videos folder before run: " + str(vids))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)

	# 1. FIRST OPEN: a fresh start, nothing clicked
	begin_goal("1 first open")
	await shot("01_first_open")
	var is_easy: bool = m.easy.on
	var panel_up: bool = m.easy.home.shown() == "panel"
	say("   words on screen: %s" % visible_words())
	end_goal(is_easy and panel_up and body_on_screen(), "(easy: %s, home panel: %s)" % [str(is_easy), m.easy.home.shown()])

	# 2. MAKE HIM PUNCH, then a "Then ..." suggestion
	begin_goal("2 make him punch, then a Then suggestion")
	var punched := await click_text("Punch")
	var played := await wait_playing()
	await shot("02_punch_played")
	var then_ok := false
	var then_btn := find_btn("Then ", true)
	if then_btn != null:
		var then_name := text_of(then_btn)
		then_ok = await click_text(then_name)
		var played2 := await wait_playing()
		await shot("03_then_played")
		then_ok = then_ok and played2
	else:
		say("   no 'Then ...' button is visible after the punch")
		await shot("03_no_then")
	end_goal(punched and played and then_ok, "(punch played: %s, then played: %s)" % [str(played), str(then_ok)])

	# 3. OWN POSE: drag an arm, + Add pose, drag again, + Add pose, play
	begin_goal("3 own pose: drag, + Add pose, drag, + Add pose, play")
	await drag("hand_r", Vector2(-70, -30))
	await shot("04_drag_arm_1")
	var add1 := await click_text("+ Add pose")
	await shot("05_add_pose_1")
	await drag("hand_r", Vector2(60, 50))
	await shot("06_drag_arm_2")
	var add2 := await click_text("+ Add pose")
	await shot("07_add_pose_2")
	var play_b := find_btn("Play / Stop") != null
	var pl := await click_text("Play / Stop") if play_b else await click_text("Play", true)
	var own_played := await wait_playing()
	await shot("08_own_pose_playing")
	end_goal(add1 and add2 and own_played, "(add pose x2: %s/%s, playing: %s, cards now %d)" % [str(add1), str(add2), str(own_played), m.S.cards.size()])

	# 4. UNDO TWICE, REDO ONCE
	begin_goal("4 undo twice, redo once")
	var cards_before: int = m.S.cards.size()
	var u1 := await click_text("Undo")
	await shot("09_undo_1")
	var u2 := await click_text("Undo")
	await shot("10_undo_2")
	var cards_after_undo: int = m.S.cards.size()
	var r1 := await click_text("Redo")
	await shot("11_redo_1")
	end_goal(u1 and u2 and r1, "(cards %d -> %d after two undos -> %d after redo)" % [cards_before, cards_after_undo, m.S.cards.size()])

	# 5. SWORD: Library, Weapons tab, Sword; then the search box
	begin_goal("5 give him a sword")
	var lib := await click_text("Library")
	await shot("12_library_open")
	var tab := await click_text("Weapons", true)
	await shot("13_weapons_tab")
	var sword := await click_text("Sword")
	await shot("14_sword_given")
	var held: bool = m.B.wep_on and m.B.wep_kind == "sword" and m.B.wep_hand == "hand_r"
	end_goal(lib and tab and sword and held, "(sword in right hand: %s)" % str(held))
	# the search box: a beginner who types 'sword' (not a click, a check of what it shows)
	say("   (check, not counted) typing 'sword' into the library search box")
	var sb: LineEdit = null
	for n in visible_nodes():
		if n is LineEdit and (n as LineEdit).name == "library_search":
			sb = n
	if sb != null:
		await click_ctl(sb)
		await type_text("sword")
		await shot("15_search_sword")
		var hits := 0
		for b in visible_buttons():
			if text_of(b).to_lower().contains("sword"):
				hits += 1
		say("   tiles named sword visible after the search: %d" % hits)
		for i in 5:
			var kb := InputEventKey.new()
			kb.keycode = KEY_BACKSPACE
			kb.pressed = true
			root.push_input(kb)
			await process_frame
			kb.pressed = false
			root.push_input(kb)
			await process_frame
	else:
		say("   no visible library search box")
	await click_text("Library")
	await shot("16_library_closed")

	# 6. SAVE THE VIDEO and find where it went
	begin_goal("6 save the video and find it")
	var saved := await click_text("Save video")
	var tw := Time.get_ticks_msec()
	while m.easy.home.last_video.is_empty() and Time.get_ticks_msec() - tw < 240000:
		await process_frame
	await idle(10)
	var toast := ""
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "" and (n as Label).text.length() > 20:
			toast += " || " + (n as Label).text
	say("   toast/long text: " + toast)
	var mp4 := String(m.easy.home.last_video.get("mp4", ""))
	await shot("17_saved_toast")
	end_goal(saved and mp4 != "", "(mp4: %s)" % mp4)

	# 7. NEW SCENE
	begin_goal("7 start a new scene")
	var nw := await click_text("New scene")
	await shot("18_new_scene_dialog")
	var ask := ""
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			ask += " || " + (n as Label).text
	say("   save question on screen:" + ask)
	var dsn := root.find_child("DontSave", true, false)
	if dsn != null:
		var chain := ""
		var q: Node = dsn
		while q != null:
			var vis := str((q as CanvasItem).is_visible_in_tree()) if q is CanvasItem else ("win:" + str((q as Window).visible) if q is Window else "-")
			chain += " < %s(%s, %s)" % [q.name, q.get_class(), vis]
			q = q.get_parent()
		say("   DontSave chain:" + chain)
		say("   DontSave text='%s' rect=%s" % [(dsn as Button).text, str((dsn as Control).get_global_rect())])
	var dn := find_btn("Don't save")
	say("   'Don't save' button: %s" % (str(dn.name) if dn != null else "NOT VISIBLE (named DontSave in the tree: %s)" % str(root.find_child("DontSave", true, false) != null)))
	var in_vis := dsn != null and visible_nodes().has(dsn)
	var in_btns := dsn != null and visible_buttons().has(dsn)
	say("   DontSave in visible_nodes: %s | in visible_buttons: %s | is Button: %s" % [str(in_vis), str(in_btns), str(dsn is Button)])
	var dont := false
	if find_btn("Don't save") != null:
		dont = await click_text("Don't save")
	elif in_vis and dsn is Button:
		clicks += 1
		say("   click 'Don't save' (found by its node name DontSave: the text search did not return it)")
		dont = await click_ctl(dsn as Button)
	await shot("19_new_scene_empty")
	end_goal(nw and (dont or m.S.cards.is_empty()), "(cards now %d)" % m.S.cards.size())

	# 8. READ THE AI VIDEO BUTTON's explanation (typed words Kine cannot build; the button is NOT pressed)
	begin_goal("8 read the AI video button's explanation (not pressed)")
	var box := visible_line_edit("or type")
	if box != null:
		await click_ctl(box)
		await type_text("backflip", true)
		await shot("20_ai_button_text")
		var why := ""
		for n in visible_nodes():
			if n is Label and (n as Label).text.strip_edges() != "":
				why += " || " + (n as Label).text
		var mk := ""
		for b in visible_buttons():
			if text_of(b) != "":
				mk += " || " + text_of(b) + " [tip: " + (b as Button).tooltip_text + "]"
		say("   words after the typed move: %s" % why)
		say("   buttons after the typed move: %s" % mk)
		end_goal(why != "" or mk != "", "(not pressed)")
	else:
		say("   no visible text box")
		end_goal(false, "")

	say("\nvideos folder after run: " + str(DirAccess.get_directories_at("C:/Users/Nick/Videos/Kine")))
	say("last video: " + str(m.easy.home.last_video))
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
