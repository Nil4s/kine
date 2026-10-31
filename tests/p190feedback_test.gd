## godot --path . -s tests/p190feedback_test.gd     (P190 FEEDBACK: Send feedback in the Help panel, scripts/p190feedback.gd; needs a window)
## A user's walk with real clicks and real key presses: ? Help, Send feedback, type, Send, Send again with nothing typed.
## Bars:
##  (1) the ? Help button (real click) opens the Help panel, and its Send feedback button (real click) opens the feedback window
##  (2) typed text (real key presses) + Send (real click): exactly ONE line in user://feedback/feedback.jsonl, valid JSON,
##      with the fields time, version, page, mode, part, text, screenshot; text is what was typed, version is 0.4.0
##  (3) the screenshot: the PNG named in the line exists in the folder and is >= 640 px wide
##  (4) empty text: Send is disabled, a real click on it writes nothing (still one line)
##  (5) no network code: the feedback script and the hook in main.gd have no HTTPRequest, HTTPClient, sockets or peers
## Screenshot: user://p190feedback_window.png (the window open, typed, before Send)
extends SceneTree

var fails := 0
var m: Node
const LOG_DIR := "user://p190feedback_test"
const TYPED := "The blade slider jumps when I drag it. Wish: undo on the wheel too"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a real click at the centre of a control: the press and the release go through the viewport's input
func click(c: Control) -> void:
	var at := c.get_global_rect().get_center()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await idle(1)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	root.push_input(u, true)
	await idle(4)


## a real key press per character, into the focused box
func type_text(t: String) -> void:
	for ch in t:
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = ch.unicode_at(0)
		e.keycode = ch.to_upper().unicode_at(0) if ch != " " else KEY_SPACE
		e.physical_keycode = e.keycode
		root.push_input(e, true)
		await idle(1)


func find_btn(under: Node, text: String) -> Button:
	for c in under.find_children("*", "Button", true, false):
		if (c as Button).text == text:
			return c
	return null


func log_lines() -> Array:
	var f := FileAccess.open(LOG_DIR.path_join("feedback.jsonl"), FileAccess.READ)
	if f == null:
		return []
	var out := []
	for l in f.get_as_text().split("\n", false):
		if l.strip_edges() != "":
			out.append(l)
	return out


func _init() -> void:
	# the test's own folder starts empty (its files only)
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	for n in DirAccess.get_files_at(LOG_DIR):
		DirAccess.remove_absolute(LOG_DIR.path_join(n))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	# (1) real clicks: ? Help, then Send feedback in the Help panel
	var hb: Button = m.ui_root.find_child("b_help", true, false)
	await click(hb)
	await idle(2)
	ok(m.ui_help.visible, "(1a) the ? Help button (real click) opens the Help panel")
	var sf := find_btn(m.ui_help, "Send feedback")
	ok(sf != null, "(1b) the Help panel has a Send feedback button")
	if sf != null:
		await click(sf)
		await idle(2)
	var fb = m.feedback
	ok(fb != null and fb.win.visible and not m.ui_help.visible, "(1c) Send feedback (real click) opens the feedback window and closes Help")
	if fb == null:
		print("P190FEEDBACK FAIL (no window)")
		quit(1)
		return
	fb.log_dir = LOG_DIR
	# (4 first) nothing typed: Send is disabled
	var send: Button = fb.send_btn
	ok(send.disabled, "(4a) empty text: Send is disabled")
	await click(send)
	await idle(3)
	ok(log_lines().size() == 0, "(4b) a click on the disabled Send writes nothing")
	# (2) typed text, then Send
	fb.box.grab_focus()
	await idle(2)
	await type_text(TYPED)
	await idle(2)
	ok(fb.box.text == TYPED and not send.disabled, "(2a) typed text lands in the box and Send is enabled")
	m.get_viewport().get_texture().get_image().save_png("user://p190feedback_window.png")
	await click(send)
	var n := 0
	while fb.note.text != fb.DONE and n < 240:
		await process_frame
		n += 1
	ok(fb.note.text == fb.DONE, "(2b) the confirmation says: %s" % fb.note.text)
	var lines := log_lines()
	ok(lines.size() == 1, "(2c) exactly one line in feedback.jsonl (have %d)" % lines.size())
	var rec = JSON.parse_string(lines[0]) if lines.size() > 0 else null
	ok(rec is Dictionary, "(2d) the line is valid JSON (one object)")
	if rec is Dictionary:
		var want := ["time", "version", "page", "mode", "part", "text", "screenshot"]
		var missing := []
		for k in want:
			if not rec.has(k):
				missing.append(k)
		ok(missing.is_empty(), "(2e) all fields present %s (missing: %s)" % [str(want), str(missing)])
		ok(String(rec.get("text", "")) == TYPED, "(2f) text is what was typed")
		ok(String(rec.get("version", "")) == "0.4.0", "(2g) version is the project's: %s" % str(rec.get("version", "")))
		ok(String(rec.get("page", "")) == String(m.cur_page) and String(rec.get("mode", "")) in ["Easy", "Expert"], "(2h) page %s and mode %s" % [str(rec.get("page", "")), str(rec.get("mode", ""))])
		ok(rec.get("part") == null or (rec.get("part") is Dictionary and rec["part"].has("name") and rec["part"].has("steps")), "(2i) part is null (none open) or {name, steps}: %s" % str(rec.get("part")))
		ok(String(rec.get("time", "")).length() >= 19, "(2j) time: %s" % str(rec.get("time", "")))
		# (3) the picture
		var shot = rec.get("screenshot")
		ok(shot is String and FileAccess.file_exists(LOG_DIR.path_join(shot)), "(3a) the screenshot named in the line exists: %s" % str(shot))
		if shot is String:
			var img := Image.load_from_file(LOG_DIR.path_join(shot))
			ok(img != null and img.get_width() >= 640, "(3b) the PNG is >= 640 px wide: %s" % (str(img.get_width()) if img != null else "no image"))
	# (4c) empty again after Send: disabled, and another click writes nothing
	ok(fb.box.text == "" and send.disabled, "(4c) after Send the box is empty and Send is disabled again")
	await click(send)
	await idle(3)
	ok(log_lines().size() == 1, "(4d) a click on Send with nothing typed writes nothing (still one line)")
	# (5) no network code
	var src := FileAccess.get_file_as_string("res://scripts/p190feedback.gd")
	var mt := FileAccess.get_file_as_string("res://scripts/main.gd")
	var hook := mt.substr(mt.find("func _feedback_open"))
	var bad := ["HTTPRequest", "HTTPClient", "StreamPeer", "PacketPeer", "WebSocket", "TCPServer", "UDPServer", "IP.resolve", "TCP", "UDP"]
	var found := []
	for w in bad:
		if src.contains(w) or hook.contains(w):
			found.append(w)
	ok(found.is_empty() and src.length() > 0, "(5) no network code in the feedback script or its hook (found: %s)" % str(found))
	# clean up the test's own files
	for n2 in DirAccess.get_files_at(LOG_DIR):
		DirAccess.remove_absolute(LOG_DIR.path_join(n2))
	DirAccess.remove_absolute(LOG_DIR)
	print("     window screenshot: %s" % ProjectSettings.globalize_path("user://p190feedback_window.png"))
	print("P190FEEDBACK %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
