extends SceneTree
## FWORDS (Nick 2026-10-28: free 3D building, nothing forced): on a blank part (the BUILDING card opens an empty Easy Part),
## every word a beginner can see (labels, buttons, placeholders, tooltips, the hint and status lines) is plain and neutral:
## no house / sword / weapon / fighter the user did not choose, no jargon (extrude, fillet, sketch, boolean ...).
## Real clicks at 1280x720 from the real start screen; scans after opening and after each make button is pressed.
## Bars:
##   1 SEEN    at least 15 different strings were scanned on the blank part (the scan is not empty)
##   2 WORDS   no scanned string (text or tooltip) has a banned word
## Prints every scanned string once ("shown: ...") and every hit ("jargon: ...").
const SHOT := "C:/Temp/claude/fwords"
const DIRT := "user://fwords_test"
const MIN_SEEN := 15
const BANNED := "(?i)\\b(houses?|swords?|weapons?|fighters?|sketch\\w*|profiles?|extrud\\w*|fillets?|booleans?|lofts?|kernel\\w*|manifold\\w*|features?|revolv\\w*|params?|mesh\\w*|shell\\w*|bod(y|ies)|primitives?|tessel\\w*|topolog\\w*|planes?|offsets?|dll|cad|f\\d{1,2})\\b"

var fails := 0
var m: Node
var re := RegEx.new()
var seen := {}
var hits := {}


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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


## every visible Label / Button / LineEdit text, placeholder and tooltip under n
func collect(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	elif n is LineEdit and (n as LineEdit).placeholder_text != "":
		out.append((n as LineEdit).placeholder_text)
	if n is Control and (n as Control).tooltip_text.strip_edges() != "":
		out.append((n as Control).tooltip_text)
	for c in n.get_children():
		collect(c, out)


func scan(where: String) -> void:
	var out: Array = []
	collect(m, out)
	for t0 in out:
		var t := String(t0).strip_edges()
		if not seen.has(t):
			print("shown (%s): %s" % [where, t])
		seen[t] = true
		var mt := re.search(t)
		if mt != null:
			hits[t] = mt.get_string()


func press_make(key: String) -> void:
	var b = pu().ep.make_btns[key]
	await click_ctl(b)
	await idle(6)
	scan("after " + key)


func _init() -> void:
	re.compile(BANNED)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	scan("open")
	await shot("open")
	for k in ["draw", "pull", "hole", "mirror", "stick", "repeat"]:
		if pu().ep.make_btns.has(k):
			await press_make(k)
	await shot("pressed")

	print("presses ok, strings scanned %d" % seen.size())
	ok(seen.size() >= MIN_SEEN, "1 SEEN %d different strings scanned on the blank part (at least %d)" % [seen.size(), MIN_SEEN])
	for t in hits:
		print("jargon: \"%s\"  (word: %s)" % [t, hits[t]])
	ok(hits.is_empty(), "2 WORDS %d scanned string(s) with a banned word" % hits.size())
	print("fwords: %d fail" % fails)
	quit(1 if fails > 0 else 0)
