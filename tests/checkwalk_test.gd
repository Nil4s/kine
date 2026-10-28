extends SceneTree
## godot --path . --position 4000,4000 -s tests/checkwalk_test.gd     (CHECKWALK: a beginner walk of the CHECK page from the real start screen, 1280 x 720)
## Real clicks (root.push_input) on the ANIMATION card, the CHECK page, then every CHECK tool by its icon or its caption menu.
## Records what each tool says (status line, any panel / dialog words) and a shot per tool under C:/Temp/claude/checkwalk/.
## Dead ends are KNOWN bars: they pin the words the walk met. Nothing in scripts/ is changed by this test.
const SHOT := "C:/Temp/claude/checkwalk"
const OLD := ["Check", "Polish", "Fix moves through the body", "Timing coach", "Weapon weight", "Parry rebound", "What I learned from you", "Fight to the beat", "Choreograph to the song",
	"Fight distance", "Sell the hit", "Gaze director", "Safety sheet", "Reaction direction", "Fight rhythm", "Breakfall check", "Recovery step", "Precog check", "Auto opponent", "Fatigue",
	"Momentum ledger", "Airborne spin check", "Real-mocap check", "Realism score", "My style", "Use my style", "Star this clip", "My best take", "Make this one more like my best", "Speed limits",
	"My combos", "Auto camera", "My camera", "Frame it my way", "Make it physical", "Accept span", "Keep this pose", "Dummy (H)", "Frame data", "Frame boxes", "Frame rate"]
var fails := 0
var m: Node
var rows: Array = []


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		root.push_input(e, true)
		await process_frame


func label_of(b: Node) -> String:
	return String(b.get_meta("label", b.get("text") if b.get("text") != null else ""))


func tool_of(t: String) -> Button:
	for c in m.ui_ribbon["CHECK"].get_children():
		if c is Button and label_of(c) == t:
			return c
	return null


func cap_of(t: String) -> Array:
	for pair in m.ui_caps["CHECK"]:
		for b in pair[1]:
			if label_of(b) == t:
				return [pair[0], (pair[1] as Array).find(b)]
	return [null, -1]


## every visible Label text in a window other than the main one (a panel, a dialog, a popup)
func panel_words() -> String:
	var out := ""
	for w in root.get_children():
		if w == m or not (w is Control or w is Window):
			continue
		if w is Control and not (w as Control).is_visible_in_tree():
			continue
		var stack: Array = [w]
		while not stack.is_empty():
			var c: Node = stack.pop_back()
			if c is Label and (c as Label).is_visible_in_tree() and (c as Label).text != "":
				out += " | " + (c as Label).text
			stack.append_array(c.get_children())
	return out


## is a visible label with this text anywhere in the app (panels live inside main too)
func shows(txt: String) -> bool:
	for c in m.find_children("*", "Label", true, false):
		if (c as Label).is_visible_in_tree() and (c as Label).text.contains(txt):
			return true
	return false


func slug(t: String) -> String:
	var s := ""
	for ch in t.to_lower():
		s += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return s


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await idle(4)
	DirAccess.make_dir_recursive_absolute(SHOT)
	m.start_screen.show_screen(true)
	await idle(4)
	root.get_texture().get_image().save_png(SHOT + "/00_start_screen.png")
	await click_ctl(m.start_screen._cards["animation"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)
	await click_ctl(m.ui_page_btns["CHECK"])
	await idle(4)
	root.get_texture().get_image().save_png(SHOT + "/01_check_page.png")
	ok(m.ui_ribbon["CHECK"].get_children().size() > 0, "CHECK page is open from the start screen")
	var shown := 0
	var combos_left := false
	for b in m.ui_ribbon["CHECK"].get_children():
		if b is Button and (b as Control).is_visible_in_tree():
			shown += 1
	ok(shown >= 12, "CHECK row shows %d icons" % shown)
	for t in OLD:
		var b := tool_of(t)
		var via := "icon"
		var before := String(m.ui_status.text) if m.ui_status != null else ""
		if b != null and b.is_visible_in_tree():
			await click_ctl(b)
		else:
			var cp := cap_of(t)
			if cp[0] == null:
				ok(false, "'%s' is not on CHECK at all" % t)
				rows.append([t, "MISSING", "", ""])
				continue
			via = "caption " + String((cp[0] as MenuButton).text)
			await click_ctl(cp[0])
			var pm: PopupMenu = (cp[0] as MenuButton).get_popup()
			await idle(2)
			var ix := -1
			for i in pm.item_count:
				if pm.get_item_text(i) == t:
					ix = i
			if ix >= 0:
				pm.id_pressed.emit(pm.get_item_id(ix))
			pm.hide()
			await idle(3)
		await idle(6)
		var status := String(m.ui_status.text) if m.ui_status != null else ""
		var words := panel_words()
		var shot := "%s/%s.png" % [SHOT, slug(t)]
		root.get_texture().get_image().save_png(shot)
		rows.append([t, via, status, words.substr(0, 300), status == before])
		print("walk: [%s] (%s) status='%s' panel='%s'" % [t, via, status, words.substr(0, 300)])
		await key(KEY_ESCAPE)
		await idle(3)
		if t == "My combos":
			combos_left = shows("MY COMBOS")
	var f := FileAccess.open(SHOT + "/walk.txt", FileAccess.WRITE)
	for r in rows:
		f.store_line(" || ".join(r.map(func(x): return str(x))))
	f.close()
	ok(rows.size() == 41, "walk visited 41 tools (%d)" % rows.size())
	# KNOWN dead ends (the words and the press the walk met)
	var silent: Array = []
	for r in rows:
		if r[4] == true:
			silent.append(r[0])
	ok(silent == ["Dummy (H)", "Frame data", "Frame boxes"], "KNOWN dead end: a press that prints nothing new (Dummy (H), Frame data, Frame boxes): the old line stays (%s)" % str(silent))
	var chk: String = rows[0][2]
	ok(chk == "Check needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below", "KNOWN dead end: Check on an empty scene says 'press Enter to add the body as a card' (the bar reads 'Clip this pose (Enter)')")
	ok(combos_left, "KNOWN dead end: Escape does not close the MY COMBOS panel (it is still on screen after Esc)")
	ok(rows.filter(func(r): return r[1] == "icon").size() == 20 and rows.filter(func(r): return String(r[1]).begins_with("caption")).size() == 21, "KNOWN: 20 icons on the row, 21 tools only under a caption menu")
	print("checkwalk: %d fails" % fails)
	quit(1 if fails > 0 else 0)
