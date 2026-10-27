extends SceneTree
## godot --path . --position 4000,4000 -s tests/monkeywalk_test.gd     (MONKEY WALK, EASY: scripts/easy_mode.gd, build_choose.gd, easy_vehicle.gd, package_screen.gd; needs a window)
## A scripted beginner in EASY mode. Real mouse clicks (root.push_input at control centres) from the start screen through every
## Easy page reachable by mouse: the BUILD cards (House / Set, Part, Vehicle with its package steps 1-5, Prop pack, Template),
## the ANIMATION page's Easy bar (Library, My scenes, Undo, More). Per visit it records script errors (a Logger), key names in
## visible text (the same check as carpkg_test key_in), a way back (Home, Back, Done, Cancel), off-screen buttons and overlapping
## buttons at 1280 x 720, and whether a button did anything (its visible state or the message line changed).
## Bars, written before measuring:
##   0 BOOT     the start screen boots with no script error or push_error
##   1 ERRORS   no script error or push_error during any visit
##   2 WORDS    no key name in any visible text of any visit
##   3 BACK     every visit has a visible way back (Home, Back, Done, Cancel)
##   4 FIT      no visible button is off the 1280 x 720 window in any visit
##   5 OVERLAP  no two visible buttons overlap (more than 25 px squared) in any visit
##   6 LIVE     every button the beginner presses changes the screen or says something (no dead button)
##   7 PAGES    Easy shows no ANIMATE / STAGE / CHECK / DELIVER page button (the Easy page bar is hidden)
## Shots in C:/Temp/claude/monkeywalk/: home.png, vehicle_step1.png, animate.png, library.png.

const W := 1280.0
const H := 720.0
const SHOT := "C:/Temp/claude/monkeywalk"
const DIRT := "user://monkeywalk_test"
const BACK_WORDS := ["Home", "Back", "Done", "Cancel", "Close", "Switch to Expert"]
const CARDS := ["house", "part", "vehicle", "props", "template", "step"]

var fails := 0
var m: Node
var errs := 0
var err_log: Array = []
var rows: Array = []
var lg: ErrCount


class ErrCount extends Logger:
	var t
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array) -> void:
		t.errs += 1
		if t.err_log.size() < 12:
			t.err_log.append("%s:%d %s %s" % [file.get_file(), line, code, rationale])


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func idle(n := 4) -> void:
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


## a real click at a control's centre; a control that is missing or hidden is reported, not clicked
func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(6)
	return true


## the first key name in a text (whole words), the carpkg_test check
func key_in(t: String) -> String:
	var low := " " + t.to_lower() + " "
	for k in PackageScreen.BAD_WORDS:
		if low.contains(k) or low.contains(" " + k):
			return k
	return ""


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	if n is Button:
		out.append((n as Button).text)
		out.append((n as Button).tooltip_text)
	if n is Control and (n as Control).tooltip_text != "":
		out.append((n as Control).tooltip_text)
	for c in n.get_children():
		texts_under(c, out)


func visible_buttons() -> Array:
	var out: Array = []
	# a modal (My scenes) covers the screen: the buttons under its shade cannot be pressed, so only its own are counted
	if m.easy != null and m.easy.scenes != null and m.easy.scenes.is_visible_in_tree():
		_collect(m.easy.scenes, out)
		return out
	if m.build_choose != null and m.build_choose.root_box != null and m.build_choose.root_box.is_visible_in_tree():
		_collect(m.build_choose.root_box, out)
		return out
	_collect(m.ui_root, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).get_global_rect().size.x > 0:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


## the buttons that are off the window or overlap another (nested buttons are not compared)
func layout_faults(tag: String) -> Array:
	var f: Array = []
	var bs := visible_buttons()
	var shown := {}
	for b in bs:
		var r := shown_rect(b)
		shown[b] = r
		if r.size.x <= 0 or r.size.y <= 0:
			continue   # scrolled or clipped out of its panel: the beginner cannot see it
		if r.position.x < -1 or r.position.y < -1 or r.end.x > W + 1 or r.end.y > H + 1:
			f.append("off-screen %s %s" % [tag, _path(b)])
	for i in bs.size():
		for j in range(i + 1, bs.size()):
			var a: Control = bs[i]
			var b: Control = bs[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ov: Rect2 = (shown[a] as Rect2).intersection(shown[b] as Rect2)
			if ov.get_area() > 25.0:
				f.append("overlap %s %s / %s" % [tag, _path(a), _path(b)])
	return f


## the part of a control's rect that a clipping ancestor (a ScrollContainer, or clip_contents) lets through
func shown_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is Control and ((p is ScrollContainer) or (p as Control).clip_contents):
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


func _path(n: Node) -> String:
	var t := ""
	if n is Button:
		t = "(" + (n as Button).text.left(20) + ")"
	return String(n.name) + t


func bar_snapshot() -> String:
	var parts: Array = []
	for b in visible_buttons():
		parts.append((b as Button).text)
	var t: String = m.ui_toast.text if m.ui_toast != null and m.ui_toast.visible else ""
	t += "#status:" + (m.ui_status.text if m.ui_status != null else "")
	if m.easy != null and m.easy._more != null and m.easy._more.visible:
		t += "#more-menu"
	return "|".join(parts) + "#" + t + "#" + str(m.S.kind) + "#" + str(m.cur_page)


func has_back() -> String:
	for b in visible_buttons():
		var t: String = (b as Button).text
		if BACK_WORDS.has(t) or String(b.name).contains("back") or String(b.name).contains("home"):
			return t if t != "" else String(b.name)
	return ""


## one visit: errors, words, back and layout are read off the screen now
func record(page: String, dead_note := "") -> void:
	await idle(6)
	var texts: Array = []
	texts_under(m.ui_root, texts)
	var words := {}
	for t in texts:
		var k := key_in(String(t))
		if k != "":
			words[k] = String(t).left(60)
			print("  key word %s in: %s" % [k, String(t).left(90)])
	var faults := layout_faults(page)
	var r := {"page": page, "errs": errs, "words": words, "back": has_back(), "faults": faults, "dead": dead_note}
	rows.append(r)
	print("VISIT %s: errors %d, key words %d, back [%s], layout faults %d%s" % [page, errs, words.size(), r["back"], faults.size(), (" DEAD: " + dead_note) if dead_note != "" else ""])
	errs = 0
	err_log.clear()


func btn_text(t: String) -> Button:
	for b in visible_buttons():
		if (b as Button).get_meta("label", (b as Button).text) == t:
			return b
	return null


func start_fresh_screen() -> void:
	m.start_screen.show_screen()
	await idle(6)


func leave() -> void:
	var h := btn_text("Home")
	if h != null:
		await click_ctl(h)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)
	if not m.start_screen.is_visible_in_tree():
		m.start_screen.show_screen()
		await idle(6)


func build_visit(id: String) -> void:
	await start_fresh_screen()
	var ss: StartScreen = m.start_screen
	await click_ctl(ss.find_child("easy_building", true, false))
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)
	root.get_texture().get_image().save_png(SHOT + "/build_after_card.png")
	await click_ctl(m.ui_root.find_child("easybuild_btn_what_to_build", true, false) as Control)   # the Easy bar's chooser button (the card itself starts the house)
	var chooser: Control = m.build_choose.root_box if m.build_choose != null else null
	if chooser == null or not chooser.is_visible_in_tree():
		await record("BUILD (chooser)", "BUILD card did not open the chooser")
		await leave()
		return
	await record("BUILD chooser (open)")
	# the chooser's own Easy card: ui_root also holds a node named easy_part (easy_part.gd), which find_child returned first (a probe error)
	var pc := m.build_choose.root_box.find_child("easy_" + id, true, false) as Control
	var b0 := bar_snapshot()
	# Import STEP opens a native file dialog (not a button in the snapshot): the test answers the ask with a no-op and counts the ask as the change
	var asked := [false]
	m.build_choose.step_picker = func(_cb: Callable): asked[0] = true
	if not await click_ctl(pc):
		await record("BUILD " + id, "card choose_%s not found" % id)
		await leave()
		return
	await idle(8)
	# the Template card opens a PopupMenu of the starter buildings (not a Button in the snapshot): an open list is the change
	var listed: bool = m.build_choose._starters != null and m.build_choose._starters.visible
	await record("BUILD " + id, "" if (bar_snapshot() != b0 or asked[0] or listed) else "card %s changed nothing" % id)
	if listed:
		m.build_choose._starters.hide()
	if id == "vehicle" and m.build_choose._car_screen != null:
		var car: PackageScreen = m.build_choose._car_screen
		for i in range(1, 6):
			var sb: Button = car.step_btns.get(i, null)
			if sb.disabled:   # step 5 Body is greyed on purpose (not made yet, its tooltip says so): a disabled button takes no press, so it is not a dead button
				continue
			var s0 := bar_snapshot()
			var was_on := car.step == i   # the step the screen is already on: a press changes nothing, and that is right
			await click_ctl(sb)
			await idle(6)
			await record("VEHICLE step %d" % i, "" if (bar_snapshot() != s0 or was_on) else "step %d changed nothing" % i)
			if i == 1:
				root.get_texture().get_image().save_png(SHOT + "/vehicle_step1.png")
	await leave()


func animate_visit() -> void:
	await start_fresh_screen()
	var ss: StartScreen = m.start_screen
	await click_ctl(ss.find_child("easy_animation", true, false))
	await click_ctl(ss._cards["animation"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)
	ok(m.easy != null and m.easy.on, "precondition: Easy is on after the Easy card")
	await record("ANIMATE POSE (Easy)")
	var pages_seen := []
	for p in ["ANIMATE", "STAGE", "CHECK", "DELIVER"]:
		var pb: Button = m.ui_page_btns.get(p, null)
		if pb != null and pb.is_visible_in_tree():
			pages_seen.append(p)
	ok(pages_seen.is_empty(), "7 PAGES Easy shows no ANIMATE / STAGE / CHECK / DELIVER page button (%s visible)" % str(pages_seen))
	for nm in ["Library", "My scenes", "Undo", "More"]:
		var eb: Button = m.easy._btns.get(nm, null)
		var b0 := bar_snapshot()
		var pressed := await click_ctl(eb)
		var d := ""
		if not pressed:
			d = "Easy button %s not visible" % nm
		elif bar_snapshot() == b0:
			d = "Easy button %s changed nothing" % nm
		await record("ANIMATE Easy bar: " + nm, d)
		if nm == "Library" and m.ui_library != null and m.ui_library.visible:
			root.get_texture().get_image().save_png(SHOT + "/library.png")
			await click_ctl(eb)
		if nm == "More":
			root.get_texture().get_image().save_png(SHOT + "/more.png")
			if m.easy._more != null:
				m.easy._more.hide()
		if nm == "My scenes":
			await click_ctl(btn_text("Close"))
	root.get_texture().get_image().save_png(SHOT + "/animate.png")
	await leave()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	lg = ErrCount.new()
	lg.t = self
	OS.add_logger(lg)
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
	ss.show_screen()
	await idle(6)
	ok(errs == 0, "0 BOOT start screen with %d errors (%s)" % [errs, str(err_log.slice(0, 3))])
	root.get_texture().get_image().save_png(SHOT + "/home.png")
	errs = 0
	err_log.clear()

	await animate_visit()
	for id in CARDS:
		await build_visit(id)

	OS.remove_logger(lg)
	_bars()
	_write_findings()
	print("monkeywalk: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _bars() -> void:
	var e := 0
	var words := []
	var backless := []
	var fit := []
	var over := []
	var dead := []
	for r in rows:
		e += int(r["errs"])
		for k in r["words"]:
			words.append("%s: %s" % [r["page"], k])
		if String(r["back"]) == "":
			backless.append(String(r["page"]))
		for f in r["faults"]:
			if String(f).begins_with("off-screen"):
				fit.append(String(f))
			else:
				over.append(String(f))
		if String(r["dead"]) != "":
			dead.append("%s: %s" % [r["page"], r["dead"]])
	ok(e == 0, "1 ERRORS %d script errors or push_errors over %d visits" % [e, rows.size()])
	ok(words.is_empty(), "2 WORDS key names in visible text: %s" % str(words.slice(0, 4)))
	ok(backless.is_empty(), "3 BACK visits with no visible way back: %s" % str(backless))
	ok(fit.is_empty(), "4 FIT buttons off the window: %s" % str(fit.slice(0, 4)))
	ok(over.is_empty(), "5 OVERLAP overlapping buttons: %s" % str(over.slice(0, 4)))
	ok(dead.is_empty(), "6 LIVE dead buttons: %s" % str(dead))


func _write_findings() -> void:
	var lines := ["# Monkey walk (Easy) findings", "", "Run: tests/monkeywalk_test.gd, 1280 x 720, real mouse clicks.", "", "| page | problem | evidence | file:line |", "|---|---|---|---|"]
	for r in rows:
		for k in r["words"]:
			lines.append("| %s | key name in text | \"%s\" (%s) | scripts/easy_mode.gd / build_choose.gd (the control's text) |" % [r["page"], k, r["words"][k]])
		if String(r["back"]) == "":
			lines.append("| %s | dead end: no visible way back | no Home / Back / Done / Cancel button | scripts/main.gd _home_button |" % r["page"])
		if int(r["errs"]) > 0:
			lines.append("| %s | script errors | %d | see log |" % [r["page"], r["errs"]])
		for f in r["faults"]:
			lines.append("| %s | layout | %s | scripts/easy_mode.gd |" % [r["page"], f])
		if String(r["dead"]) != "":
			lines.append("| %s | button does nothing | %s | scripts/easy_mode.gd |" % [r["page"], r["dead"]])
	DirAccess.make_dir_recursive_absolute(SHOT)
	var f := FileAccess.open(SHOT + "/FINDINGS.md", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
