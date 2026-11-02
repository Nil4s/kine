## godot --path . -s tests/easy_mode_test.gd     (EASY MODE, docs/ROADMAP.md 3 and 4; needs a window)
## The mode rule (fresh = Easy, existing = Expert, a test = Expert unless it says so); Easy shows exactly the 7 big
## buttons (More holds the rest, one click away) and hides the expert panels; each action runs; Expert puts every panel's visibility back exactly
## as it was; the tour advances on the real actions only. The settings are the test's own file (user://poser_test_*.cfg).
extends SceneTree

const LABELS := ["Library", "Save video", "Play / Stop", "Undo", "New scene", "My scenes", "More", "Switch to Expert"]   # the bar (8: My scenes, Easy 120)
const UNDO_NONE := "Undo: nothing to undo yet"   # the Easy Undo tooltip with nothing to take back (the label stays "Undo")
const MORE := ["Save this pose as a card", "Move his arms and legs", "Redo", "Open a saved scene", "Copy a video", "Save the scene", "Flip left and right", "Put his feet on the floor", "Make a story"]   # 254: "Make a story" is the 9th More entry, added deliberately by f4322197 (p199storymode); the bar was stale

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


## a point well inside the part's own capsule (the middle of a hand is nearer its forearm's pick)
func inside(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position(c[0].lerp(c[1], 0.75))


## where a person presses a part: a point of its capsule that is on screen, not under a panel (the bottom bar hides what is
## behind it: a press there lands on the bar), and that the pick takes for this part (a finger in front of the hand is
## what a person sees and presses, so such a point is passed over). Falls back to inside() when no point qualifies.
func press_point(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	var vp := m.get_viewport().get_visible_rect()
	for t in [0.75, 0.6, 0.9, 0.45, 0.3, 0.15]:
		var q: Vector2 = m.cam.unproject_position(c[0].lerp(c[1], t))
		if not vp.has_point(q):
			continue
		var hm := InputEventMouseMotion.new()   # the pointer over the point, no button: the hover the press will see
		hm.position = q
		hm.global_position = q
		root.push_input(hm, true)
		await process_frame
		if m.get_viewport().gui_get_hovered_control() == null and m._pick(q) == j:
			return q
	return inside(j)


## a real drag of a part: press on it, move in steps, let go
func drag(j: String, d := Vector2(48, -48)) -> void:
	var p := await press_point(j)
	var st := d / 6.0
	btn(true, p)
	await process_frame
	for i in 6:
		move(p + st * (i + 1), st)
		await process_frame
	btn(false, p + d)
	await process_frame


## the pointer over a screen point with no button: the hover the bar's words follow once it has rested (BAR_REST)
func hover_at(q: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = q
	hm.global_position = q
	root.push_input(hm, true)
	await process_frame
	await create_timer(m.BAR_REST + 0.1).timeout
	await idle(2)


## a screen point on the part's capsule that the pick takes as `want` (default: the part itself), read as the view stands now:
## in Expert the finger's own point, in Easy (the view is framed again) a point of the finger that the pick takes as its hand.
## NAN when no point qualifies
func finger_point(j: String, want := "") -> Vector2:
	var c: Array = m.B.cap(j)
	var vp := m.get_viewport().get_visible_rect()
	for t in [0.5, 0.35, 0.65, 0.25, 0.75, 0.15, 0.85]:
		var q: Vector2 = m.cam.unproject_position(c[0].lerp(c[1], t))
		if not vp.has_point(q) or q.y > vp.size.y - 140.0:
			continue
		if m._pick(q) == (want if want != "" else j):
			return q
	return Vector2(NAN, NAN)


## a real drag started on a screen point: press there, move in steps, let go
func drag_at(p: Vector2, d: Vector2) -> void:
	var st := d / 6.0
	btn(true, p)
	await process_frame
	for i in 6:
		move(p + st * (i + 1), st)
		await process_frame
	btn(false, p + d)
	await process_frame


## every card's line (the picture's name button and the timing line): text by node name, "" when none
func card_lines() -> Dictionary:
	var out := {}
	for n in m.ui_cards.find_children("*", "Button", true, false):
		if n.name == "b_pick" or n.name == "b_timing":
			out[str(n.get_parent().get_parent().name) + "/" + str(n.name)] = String(n.text)
	return out


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## a real click on a Control: the mouse goes down and up on its middle, as a beginner's press does
func add_btn() -> Button:   # the strip's + Add pose, fetched fresh: a card's change rebuilds the strip (an old reference is freed)
	return m.easy.add_button()


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	btn(true, p)
	await process_frame
	_click_check(c, p)
	btn(false, p)
	await idle(3)


## CLICK MISS: after the press, the GUI's hovered control must be c or inside c (else the click went to another control)
func _click_check(c: Control, at: Vector2) -> void:
	var h: Control = m.get_viewport().gui_get_hovered_control()
	if h == null or not (h == c or c.is_ancestor_of(h)):
		print("CLICK MISS %s hit %s (at %s, final transform %s)" % [c.name, h.name if h != null else "none", str(at), str(root.get_final_transform())])


## the words of a line that are size, weight, key or jargon (the Easy bar's rule for its own hints)
func plain_bad(t: String) -> Array:
	var out := []
	for w in ["cm", "kg", "Ctrl+Z", "arming"]:
		if t.find(w) >= 0:
			out.append(w)
	return out


## a word typed in capitals (CROSS, RECOVER): two or more letters, all upper case
func has_caps_word(t: String) -> bool:
	for w in t.split(" ", false):
		if w.length() >= 2 and w == w.to_upper() and w != w.to_lower():
			return true
	return false


## the step's name on the Easy bar's Undo button. The button's LABEL is always "Undo" (a beginner finds it again each step);
## the name is its TOOLTIP ("Undo: Walk"). A label that is not "Undo" returns "label reads ..", which no name check accepts.
func undo_words() -> String:
	var b: Button = m.easy.button("Undo")
	if b == null:
		return "?"
	var lab := String((b.get_node("label") as Label).text)
	return b.tooltip_text if lab == "Undo" else "label reads '%s'" % lab


func panels() -> Array:
	return [m.ui_top_bar, m.ui_side_of["left"], m.ui_side_of["right"], m.ui_cube, m.ui_nav, m.ui_bh, m.ui_play_row] + m.ui_rails.values()


func vis_now() -> Array:
	return panels().map(func(n): return n.visible)


func cfg_mode() -> String:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return String(cf.get_value("look", "mode", ""))


## a fresh start: the settings file removed, the app built again (Easy under EasyMode.start_fresh, Expert without it)
func fresh_start(easy: bool) -> void:
	var path: String = m.settings
	m.queue_free()
	await idle(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	EasyMode.start_fresh = easy
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	EasyMode.start_fresh = false


## the teaching texts on screen now: the first-start strip, the hint row, the hint labels (only what is shown)
func teach_lines() -> Array:
	var out: Array = []
	if m.ui_status.is_visible_in_tree() and m.is_welcome(m.ui_status.text):
		out.append(m.ui_status.text)
	if m.ui_mouse.visible and m.ui_mouse.shown_text() != "":
		out.append(m.ui_mouse.shown_text())
	for l in m.ui_hint_labels:
		if is_instance_valid(l) and (l as Control).is_visible_in_tree() and (not (l is Label) or (l as Label).text != ""):
			out.append(str(l.get("text")) if l is Label else str(l))
	return out


## OVERLAP (Nick's beginner walk-through): in Easy the library panel, the picker, the welcome line, the status line, the
## save toast, the card strip and the Easy top bar never overlap one another, and all sit inside the window, at 1600x900 and 1280x720
const OVERLAP_SIZES := [Vector2i(1600, 900), Vector2i(1280, 720)]
const OVERLAP_STATES := ["picker", "picker + toast", "library", "library + toast", "strip", "strip + toast", "picker + redo toast", "strip + redo toast", "strip + prop bar"]
const OVERLAP_WANT := {   # the panels each state must show (so an empty screen cannot pass)
	"picker": ["picker panel"], "picker + toast": ["picker panel", "save toast"],
	"library": ["library panel"], "library + toast": ["library panel", "save toast"],
	"strip": ["picker strip", "card strip"], "strip + toast": ["picker strip", "save toast"],
	"picker + redo toast": ["picker panel", "redo toast"], "strip + redo toast": ["picker strip", "card strip", "redo toast"],
	"strip + prop bar": ["picker strip", "card strip", "prop bar"],
}


## the "Then <move>" buttons after the move just made (the strip's second row), visible ones only
func next_btns() -> Array:
	var out := []
	for b in m.easy.home.strip.find_children("eh_next_*", "Button", true, false):
		if b.is_visible_in_tree():
			out.append(b)
	return out


## every visible button in Easy's bar, the picker and the strip
func easy_buttons() -> Array:
	var out := []
	for host in [m.easy.bar, m.easy.home.strip, m.easy.home.panel]:
		for b in host.find_children("*", "Button", true, false):
			if b.is_visible_in_tree():
				out.append(b)
	return out


## the global rects of what is on screen in Easy: [name, rect] for each visible item with content
func easy_rects() -> Array:
	var out := []
	var cands := [
		["easy top bar", m.easy.bar, true],
		["library panel", m.ui_library, m.ui_library != null and m.ui_library.visible],
		["picker panel", m.easy.home.panel, true],
		["picker strip", m.easy.home.strip, true],
		["welcome line", m.ui_mouse, m.ui_mouse.visible and m.ui_mouse.shown_text() != ""],
		["status line", m.ui_status, m.ui_status.text != ""],
		["readout", m.ui_bar, m.ui_bar.text != ""],
		["save toast", m.easy.home._toast, true],
		["prop bar", m.easy.home._pbar, m.easy.home._pbar != null and m.easy.home._pbar.is_visible_in_tree()],
		["redo toast", m.ui_toast, m.ui_toast != null and m.ui_toast.visible],
		["card strip", m.ui_cards, true],
		["view buttons", m.easy.views, m.easy.views != null],   # Front / Side / Back / Reset view: the strip covered them at 1280x720
	]
	for c in cands:
		var n: Control = c[1]
		if c[2] and is_instance_valid(n) and n.is_visible_in_tree() and n.size.x > 0.0 and n.size.y > 0.0:
			out.append([c[0], n.get_global_rect()])
	return out


## the pairs of rects that share an area (a 1 px edge touch does not count)
func overlap_pairs(rects: Array) -> Array:
	var bad := []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var x: Rect2 = rects[i][1].intersection(rects[j][1])
			if x.size.x > 1.0 and x.size.y > 1.0:
				bad.append("%s x %s" % [rects[i][0], rects[j][0]])
	return bad


## the names of the rects that reach past the window's edge
func outside_window(rects: Array, win: Vector2) -> Array:
	var out := []
	for r in rects:
		var q: Rect2 = r[1]
		if q.position.x < -0.5 or q.position.y < -0.5 or q.end.x > win.x + 0.5 or q.end.y > win.y + 0.5:
			out.append(r[0])
	return out


## THE SCRUB (Easy's slider under the strip's buttons): the slider and its time label must not overlap a visible strip button,
## the prop bar or the body's screen box; a strip state shows the row. Returns the names it overlaps (empty = fine)
func scrub_bad(st: String) -> Array:
	var out := []
	var h = m.easy.home
	var row: Control = h._scrub_row
	if row == null or not row.is_visible_in_tree():
		if st.begins_with("strip"):
			out.append("scrub row hidden")
		return out
	var parts := [["scrub", h._scrub.get_global_rect()], ["scrub time", h._scrub_time.get_global_rect()]]
	var others := []
	for b in h.strip.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			others.append([b.name, (b as Control).get_global_rect()])
	if h._pbar.is_visible_in_tree():
		others.append(["prop bar", h._pbar.get_global_rect()])
	var bb := body_screen_box()
	if bb.size.x > 0.0:
		others.append(["body", bb])
	for p in parts:
		for o in others:
			var x: Rect2 = (p[1] as Rect2).intersection(o[1])
			if x.size.x > 1.0 and x.size.y > 1.0:
				out.append("%s x %s" % [p[0], o[0]])
	return out


## the body's screen box (each capsule end projected by m.cam, grown by its radius): the same measure as easyhome_test's body_box
func body_screen_box() -> Rect2:
	var cam: Camera3D = m.cam
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var mpp: float = 2.0 * float(m.dist) * tan(deg_to_rad(cam.fov * 0.5)) / vs.y
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in Turntable.points(m.B):
		if cam.is_position_behind(p[0]):
			continue
		var q := cam.unproject_position(p[0])
		var r: float = float(p[1]) / mpp
		lo = lo.min(q - Vector2(r, r))
		hi = hi.max(q + Vector2(r, r))
	return Rect2(lo, hi - lo) if lo.x < INF else Rect2()


## one state of the overlap bar: the scene and the panels the state names, then settled
func overlap_set(st: String) -> void:
	m._new_scene()
	await idle(4)
	if m.ui_library == null:   # made on its first open (the easy_overlap suite runs this bar first)
		m._library_toggle()
		await idle(2)
	m.ui_library.hide_panel()
	if st.begins_with("strip"):
		m.easy.home.card(0)
		var t := 0
		while m.easy.home.shown() != "strip" and t < 300:
			await process_frame
			t += 1
	if st.begins_with("library"):
		m.ui_library.open()
	if st.contains("prop bar"):   # a prop in the scene: the prop bar (Easy, under Front / Side / Back) is on screen
		m._prop_add("chair")
		await idle(4)
	m.easy.home._toast.visible = false
	if m.ui_toast != null:   # made on its first toast (main._toast)
		m.ui_toast.visible = false
	if st.ends_with("+ toast"):
		m.easy.home._show_toast("Your video is saved: punch_169.mp4", "C:/Users/Nick/Videos/Kine/punch_169.mp4")
	if st.ends_with("redo toast"):
		m._toast("Redid: Move hand")   # the Redo toast (main's _toast), as Ctrl+Y and the Easy More menu's Redo show it
	m._say_plain("Sword picked up: it is in his right hand now. Undo takes it back.")
	await idle(8)


## ITEM 1 (walk-through): a toast in Easy covers no visible Button. Each shown toast's global rect is checked against every
## visible Button under the window (a 1 px edge touch does not count). Returns the names of the toasts that cover one
func toast_over_buttons() -> Array:
	var bad := []
	var toasts := {"redo toast": m.ui_toast, "save toast": m.easy.home._toast}
	for nm in toasts:
		var t: Control = toasts[nm]
		if t == null or not t.is_visible_in_tree():
			continue
		var btns := []
		_visible_buttons(m, btns, t)   # the toast's own buttons (Open folder, Got it) are part of it, not a button it covers
		for b in btns:
			var x: Rect2 = t.get_global_rect().intersection(b)
			if x.size.x > 1.0 and x.size.y > 1.0:
				bad.append("%s over a button at %s" % [nm, str(Rect2i(b))])
	return bad


func _visible_buttons(n: Node, out: Array, skip: Node) -> void:
	if n == skip:
		return
	if n is Button and (n as Button).is_visible_in_tree() and (n as Button).size.x > 0.0:
		out.append((n as Control).get_global_rect())
	for c in n.get_children():
		_visible_buttons(c, out, skip)


## sizes: the window sizes to measure. Embedded (run_par's host window) a test cannot resize its window, so easy_mode
## measures the size it has; tests/easy_overlap_test.gd (a TOPLEVEL window suite) measures both OVERLAP_SIZES
func overlap_bar(sizes: Array = OVERLAP_SIZES) -> void:
	var win0: Vector2i = m.get_window().size
	for sz in sizes:
		m.get_window().size = sz
		await idle(8)
		for st in OVERLAP_STATES:
			await overlap_set(st)
			var rects := easy_rects()
			var names := rects.map(func(r): return r[0])
			var miss: Array = OVERLAP_WANT[st].filter(func(w): return not (w in names))
			var bad := overlap_pairs(rects)
			var out := outside_window(rects, Vector2(m.get_viewport().get_visible_rect().size))
			var geo := rects.map(func(r): return "%s %s" % [r[0], str(Rect2i(r[1]))])
			var over := toast_over_buttons()
			var scrub := scrub_bad(st)
			ok(miss.is_empty() and bad.is_empty() and out.is_empty() and over.is_empty() and scrub.is_empty(),
				"overlap %dx%d [%s]: no two overlap (%s), all inside the window (%s), shown (%s missing), no toast over a button (%s), the scrub clear of the buttons, prop bar and body (%s); rects %s" % [sz.x, sz.y, st,
				str(bad), str(out), str(miss), str(over), str(scrub), str(geo)])
	m.get_window().size = win0
	m.ui_library.hide_panel()
	await idle(4)


func _init() -> void:
	# 1. the rule, from in-memory settings (no window needed for this part)
	var cf := ConfigFile.new()
	ok(EasyMode.mode_for(cf), "a fresh config (no file, no sections) is Easy")
	cf.set_value("layout", "fold_left", true)
	ok(not EasyMode.mode_for(cf), "an existing config (sections, no mode key) stays Expert")
	cf.set_value("look", "mode", "easy")
	ok(EasyMode.mode_for(cf), "a stored mode wins over the sections")
	cf.set_value("look", "mode", "expert")
	ok(not EasyMode.mode_for(cf), "a stored Expert is Expert")
	ok(not EasyMode.mode_for(ConfigFile.new(), true), "under a test with no key: Expert (the suites keep their app)")

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	ok(m.easy != null and not m.easy.on, "a test starts in Expert (no key in its own settings file)")
	ok(cfg_mode() == "", "and writes no mode into its settings file at start")
	if (get_script() as Script).resource_path.get_file() == "easy_overlap_test.gd":   # the window suite: only the overlap bar, at both sizes
		m.easy.set_on(true, false)
		await idle(4)
		await overlap_bar()
		m.easy.set_on(false, false)
		await idle(4)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
		print("EASY OVERLAP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
		TestFiles.cleanup()
		quit(fails)
		return

	# 2. Expert before anything: remember every panel's visibility, then check Easy hides exactly those
	m._new_scene()
	await idle()
	var before := vis_now()
	var dummy0: bool = m.dummy_on
	m.easy.set_on(true, false)
	await idle()
	ok(dummy0 and not m.dummy_on, "Easy puts the target dummy away (it stood between the camera and the body): on %s -> %s" % [str(dummy0), str(m.dummy_on)])
	ok(m.easy.bar.visible, "Easy: the bar is on screen")
	var bts: Array = m.easy.labels()
	var shown: Array = []
	for n in m.easy.bar.find_children("*", "Button", true, false):
		if n.get_meta("label", "") != "" and n.visible:   # Redo is on the bar only while something can be put back (checked below)
			shown.append(n.get_meta("label"))
	ok(shown.size() == 8 and LABELS.all(func(l): return l in shown) and bts.size() == 9, "Easy shows exactly the 8 labelled buttons (Redo is the 9th, hidden with nothing to redo): %s" % str(shown))
	ok(vis_now().all(func(v): return not v), "Easy hides every expert panel, top tools, the scene header, the play row and the nav/cube %s" % str(range(panels().size()).filter(func(i): return panels()[i].visible)))
	ok(m.ui_bp.visible, "the bottom panel (timeline and cards) stays: the tour and Play need it")
	ok(m.lw() == 0.0 and m.rw() == 0.0, "the body view takes the room the hidden side panels had")
	ok(m.easy.button("Undo") != null and m.easy.more_labels() == MORE, "Undo is on the bar; the More menu holds the other %d actions" % MORE.size())
	ok(m.easy.button("New scene").pressed.get_connections().size() > 0 and m.easy.button("Save video").pressed.get_connections().size() > 0, "New scene and Save video are wired (not run here: a dialog / a render)")
	
	m._refresh()
	var dots_on: Array = m.dots.values().filter(func(d): return d.visible)
	ok(not m.tag.visible and dots_on.is_empty() and m.axis_tags.all(func(a): return not a.visible),
		"Easy quiet: no part name tag (%s), no joint dots (%d shown), no axis names on the floor" % [str(m.tag.visible), dots_on.size()])
	m.easy.set_on(false, false)
	await idle()
	m._refresh()
	ok(m.tag.visible and m.dots.values().any(func(d): return d.visible) and m.axis_tags.all(func(a): return a.visible),
		"Expert: the part name tag, the joint dots and the axis names are back")
	ok(vis_now() == before, "Expert restores every panel's visibility exactly as it was, on the same scene: %s" % str(before))
	ok(m.dummy_on == dummy0, "Expert brings the target dummy back as it was (%s)" % str(m.dummy_on))

	# 2b. the hint row and the readout: Easy's one plain line and no readout; Expert's exactly as they were (stored in Expert first)
	m.ui_mouse.refresh()
	await idle(2)
	var x_hint: String = m.ui_mouse.shown_text()
	var x_bar_text: String = m.ui_bar.text
	var x_bar_vis: bool = m.ui_bar.visible
	m.easy.set_on(true, false)
	await idle(4)
	m.ui_mouse.refresh()
	await idle(2)
	var e_hint: String = m.ui_mouse.shown_text()
	var e_bad_words := []
	for w in ["nothing", "pan", "pick", "Middle"]:
		if e_hint.contains(w):
			e_bad_words.append(w)
	ok(e_hint != "" and e_bad_words.is_empty(), "Easy: the hint row is one plain line with none of nothing / pan / pick / Middle: '%s'" % e_hint)
	ok(not m.ui_bar.visible, "Easy: the readout (the card count and the seconds) is hidden")
	var w_status: String = m.ui_status.text
	m.ui_status.text = "Your video is saved: punch_2.mp4"   # the welcome line is gone: the one-line hint row must show
	await idle(2)
	m.ui_mouse.refresh()
	await idle(2)
	ok(m.ui_mouse.visible, "Easy: the hint row is on screen once the welcome line is gone")
	m.ui_status.text = w_status
	m.easy.set_on(false, false)
	await idle(4)
	m.ui_mouse.refresh()
	await idle(2)
	ok(m.ui_mouse.shown_text() == x_hint, "Expert switch: the hint row is its old text again ('%s')" % x_hint)
	ok(m.ui_bar.visible == x_bar_vis and m.ui_bar.text == x_bar_text, "Expert switch: the readout is shown again, as it was ('%s')" % x_bar_text)
	m.easy.set_on(true, false)
	await idle()

	# 3. each button runs its action
	m.easy.pick_more("Move his arms and legs")
	await idle()
	ok(m.ui_status.text.begins_with("Drag a part"), "Move his arms and legs says how to pose, on the say line")
	var n0: int = m.S.cards.size()
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.S.cards.size() == n0 + 1, "Save this pose as a card adds a card (%d -> %d)" % [n0, m.S.cards.size()])
	m.easy.button("Undo").pressed.emit()
	await idle()
	ok(m.S.cards.size() == n0, "Undo (on the bar) takes the card back")
	m.easy.pick_more("Redo")
	await idle()
	ok(m.S.cards.size() == n0 + 1, "Redo puts it back")
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.S.cards.size() == n0 + 2, "a second card: two are needed to play")
	# REDO ON THE BAR (Easy): after an Undo a visible Redo control, named as Undo is; one press puts the step back; it hides when nothing is left
	m.easy.button("Undo").pressed.emit()
	await idle()
	var rbtn: Button = m.easy.button("Redo")
	ok(rbtn.visible and m.S.cards.size() == n0 + 1, "Easy: after Undo the bar shows Redo (visible %s, %d cards)" % [str(rbtn.visible), m.S.cards.size()])
	ok((rbtn.get_node("label") as Label).text == "Redo" and rbtn.tooltip_text.begins_with("Redo: "), "Easy: the Redo button reads 'Redo' and its tooltip names the step (label '%s', tooltip '%s')" % [(rbtn.get_node("label") as Label).text, rbtn.tooltip_text])
	rbtn.pressed.emit()
	await idle()
	ok(m.S.cards.size() == n0 + 2 and not rbtn.visible, "Easy: one press on Redo restores the step (%d cards) and Redo hides with nothing left" % m.S.cards.size())
	m._pose_words("raise the right arm 90")
	await idle()
	var body_before := JSON.stringify(m.B.state())
	m.easy.pick_more("Flip left and right")
	await idle()
	ok(JSON.stringify(m.B.state()) != body_before, "Flip left and right changes the body (a raised right arm goes to the left)")
	m.easy.button("Undo").pressed.emit()
	await idle()
	var pw := func() -> String:   # what the button SHOWS: its Label's words, and no Button.text drawn over them
		var b: Button = m.easy.button("Play / Stop")
		return (b.get_node("label") as Label).text if b.text == "" else "OVERLAP: " + b.text
	m.easy.button("Play / Stop").pressed.emit()
	await idle()
	ok(m.playing, "Play / Stop starts the scene (two cards)")
	await idle(2)
	ok(pw.call() == "Stop", "while it plays the button says Stop (%s)" % pw.call())
	m.easy.button("Play / Stop").pressed.emit()
	await idle()
	ok(not m.playing, "Play / Stop again stops it")
	await idle(2)
	ok(pw.call() == "Play", "stopped, the button says Play (%s)" % pw.call())
	m.easy.pick_more("Put his feet on the floor")
	await idle()
	ok(true, "Put his feet on the floor runs without an error")
	# B: the More menu closes as its item runs (after_08: it stayed open behind New scene's "Unsaved changes" dialog)
	ok(not m.easy._more.visible, "B: the More menu is closed after its item (Put his feet on the floor) runs")
	m.easy._more_open()
	await idle()
	ok(m.easy._more.visible, "B: More opens its menu (precondition for the bar check)")
	m.easy.button("Play / Stop").pressed.emit()   # a bar button runs while More is open: More closes too
	await idle()
	ok(not m.easy._more.visible, "B: pressing a bar button (Play / Stop) closes the More menu that was open")
	m.easy.button("Play / Stop").pressed.emit()   # stop again
	await idle()
	# the precondition (an empty list would pass): a draft in scenes/_wip, and a saved scene that is also recent
	var draft_made := Templates.create("run")   # a draft file in scenes/_wip, not opened: the open scene stays as it is
	ok(draft_made != "", "precondition: a Run draft is in scenes/_wip for the Open check (%s)" % draft_made)
	m._fill_scene_list()
	for i in m.ui_scenes.item_count:
		var rp := String(m.ui_scenes.get_item_metadata(i))
		if not (rp.begins_with("#") or m.is_draft_path(rp) or m.ui_scenes.is_item_disabled(i)):
			m._recent_note(rp, true)
			break
	m.easy.pick_more("Open a saved scene")
	await idle()
	# Open (Easy, plain words): ONE entry per saved scene (the list's recent row and its saved row are the same scene), no
	# "Recent drafts" section and no "(draft)" word. Expert's list is not this menu (its list keeps its own rows)
	var saved_paths := {}
	for i in m.ui_scenes.item_count:
		var mp := String(m.ui_scenes.get_item_metadata(i))
		if not (mp.begins_with("#") or m.is_draft_path(mp) or m.ui_scenes.is_item_disabled(i)):
			saved_paths[mp] = true
	var om_paths := {}
	var om_text := []
	for k in m.easy._menu.item_count:
		om_paths[String(m.easy._menu_paths.get(k, ""))] = true
		om_text.append(m.easy._menu.get_item_text(k))
	var om_bad := om_text.filter(func(t): return String(t).to_lower().find("draft") >= 0 or String(t).find("(recent)") >= 0 or String(t).find("Recent") >= 0)
	ok(m.easy._menu.item_count == saved_paths.size() and saved_paths.size() > 0 and om_paths.size() == m.easy._menu.item_count and om_bad.is_empty(),
		"Easy's Open: one entry per saved scene (%d), no duplicate, no draft or recent words: %d rows, %d distinct, bad %s" % [saved_paths.size(), m.easy._menu.item_count, om_paths.size(), str(om_bad)])
	m.easy._menu.hide()
	await idle()

	# 4. the tour: each step waits, and moves on only on the real action
	m._new_scene()
	await idle()
	m.easy.tour_start()
	await idle()
	ok(m.easy.tour_step == 0 and m.easy.tour_card.visible, "the tour starts at step 1 and its card is on screen")
	# 4a. the tour card is READABLE and out of the body's way: its text and Skip are on screen with a size, inside the
	# window, the text colour is not the card's own colour, and the card's rect does not cover the body's screen rect
	var tc: PanelContainer = m.easy.tour_card
	var tt: Label = m.easy._tour_title
	var tx: Label = m.easy._tour_text
	var sk: Button = tc.find_child("easy_tour_skip", true, false)
	var vp := Rect2(Vector2.ZERO, get_root().get_visible_rect().size)
	ok(tt.is_visible_in_tree() and tx.is_visible_in_tree() and sk.is_visible_in_tree(),
		"4a the tour's step label, text and Skip button are visible in the tree")
	ok(tt.size.x > 0 and tt.size.y > 0 and tx.size.x > 0 and tx.size.y > 0 and sk.size.x > 0 and sk.size.y > 0,
		"4a the step label, text and Skip have a size (%s, %s, %s)" % [str(tt.size), str(tx.size), str(sk.size)])
	ok(vp.encloses(tt.get_global_rect()) and vp.encloses(tx.get_global_rect()) and vp.encloses(sk.get_global_rect()) and vp.encloses(tc.get_global_rect()),
		"4a the tour card, its text and Skip lie inside the window (card %s)" % str(tc.get_global_rect()))
	var bg: Color = (tc.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
	ok(tx.get_theme_color("font_color") != bg and tt.get_theme_color("font_color") != bg,
		"4a the tour's text colour differs from the card's background (text %s, card %s)" % [str(tx.get_theme_color("font_color")), str(bg)])
	ok(sk.get_global_rect().get_center().x > 0 and sk.mouse_filter != Control.MOUSE_FILTER_IGNORE and vp.has_point(sk.get_global_rect().get_center()),
		"4a the Skip button takes a click, centred on the window")
	# 4a+ (walk-through item 3): the Skip button reads "Skip tour" and is a normal-size button: as tall as a plain Next button
	# of the same theme (the Easy tour has no Next of its own, so the reference is a plain Button with that word)
	var ref_b := Button.new()
	ref_b.text = "Next"
	get_root().add_child(ref_b)
	var ref_h: float = ref_b.get_combined_minimum_size().y
	ref_b.queue_free()
	ok(sk.text == "Skip tour" and sk.size.y >= ref_h - 0.5 and sk.get_combined_minimum_size().y >= ref_h - 0.5,
		"4a+ the tour's Skip reads 'Skip tour' and is as tall as a plain Next (%s, height %.0f, Next %.0f)" % [sk.text, sk.size.y, ref_h])
	var body_r := Rect2()
	var body_first := true
	for pt in Turntable.points(m.B):
		var wp: Vector3 = pt[0]
		if m.cam.is_position_behind(wp):
			continue
		var sp: Vector2 = m.cam.unproject_position(wp)
		body_r = Rect2(sp, Vector2.ZERO) if body_first else body_r.expand(sp)
		body_first = false
	ok(not body_first and not body_r.intersects(tc.get_global_rect()),
		"4a the tour card does not cover the body's screen rect (body %s, card %s)" % [str(body_r), str(tc.get_global_rect())])
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.easy.tour_step == 0, "step 1 (drag a hand) does not move on for a Save-the-pose press")
	await drag("hand_r")
	await idle()
	ok(m.easy.tour_step == 1, "step 1: dragging a hand moves on (now %d)" % (m.easy.tour_step + 1))
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.easy.tour_step == 2, "step 2: Save this pose as a card moves on (now %d)" % (m.easy.tour_step + 1))
	var ph0: float = m.playhead
	var tl: Control = m.ui_timeline
	var length: float = m._ps().length()
	var at_t := 0.25 * length if absf(ph0 - 0.25 * length) > 0.1 * length else 0.75 * length   # far from where it is now
	var x0: float = tl.x_of(at_t)   # a real click on the ruler
	var y := Timeline.RULER * 0.5   # the ruler (the top strip of the timeline) is the scrub: a click there moves the playhead
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(x0, y)
	tl._gui_input(press)
	await idle()
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(x0, y)
	tl._gui_input(rel)
	await idle()
	print("probe tl ph0=%.3f ph=%.3f step=%d playing=%s len=%.2f at=%.2f" % [ph0, m.playhead, m.easy.tour_step, m.playing, length, at_t])
	ok(absf(m.playhead - ph0) > 0.005 and m.easy.tour_step == 3, "step 3: a click on the timeline moves the playhead and moves on (playhead %.2f)" % m.playhead)
	await drag("hand_l")
	await idle()
	m.easy.pick_more("Save this pose as a card")
	await idle()
	ok(m.easy.tour_step == 4, "step 4: change the pose and save again moves on (now %d)" % (m.easy.tour_step + 1))
	m.easy.button("Play / Stop").pressed.emit()
	await idle()
	ok(m.easy.tour_step == -1 and not m.easy.tour_due(), "step 5: Play ends the tour, and it is done (not due again)")
	m.playing = false
	# Skip, from a fresh settings file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	m.easy.tour_start()
	await idle()
	m.easy.tour_card.find_child("easy_tour_skip", true, false).pressed.emit()
	await idle()
	ok(m.easy.tour_step == -1 and not m.easy.tour_card.visible and not m.easy.tour_due(), "Skip ends the tour and it is not due again")

	# 4b. a Punch card (EasyHome.CARDS 3): Easy's card lines and bottom panel, and Expert's exactly as they were
	m.easy.set_on(false, false)
	await idle()
	m.easy.home.card(3)
	await idle(12)
	var x_lines := card_lines()
	var x_h: float = m.ui_bp.size.y
	m.easy.set_on(true, false)
	await idle(12)
	m._refresh()
	await idle(2)
	var e_lines := card_lines()
	var e_names := []
	for c in m.S.cards:
		e_names.append(m._easy_card_name(c["name"]))
	var e_bad := []
	for k in e_lines:
		var t: String = e_lines[k]
		if t.find(" s") >= 0 or t.to_lower().find("hold") >= 0 or k.ends_with("/b_timing"):
			e_bad.append(t)
	var e_picks := []
	for k in e_lines:
		if k.ends_with("/b_pick"):
			e_picks.append(e_lines[k])
	ok(m.S.cards.size() >= 4 and e_bad.is_empty(), "Easy after the Punch card: no card line has seconds, a hold or a timing line %s" % str(e_bad))
	ok(e_picks.size() == m.S.cards.size() and e_picks.all(func(t): return t in e_names) and e_picks[0] == "Guard", "Easy: each card's line is its name, capitalised (%s)" % str(e_picks))
	ok(m.ui_bp.size.y <= m.ui_card_row.size.y + 40.0, "Easy: the bottom panel (%d px) is no taller than the card row (%d px) + 40" % [int(m.ui_bp.size.y), int(m.ui_card_row.size.y)])
	var lim := []
	for j in Body.ORDER:
		if m.part_look(j) == "limit":
			lim.append(j)
	ok(not lim.is_empty(), "the Punch card puts a body part at its joint limit (so the bar below has something to check): %s" % str(lim))
	ok(lim.all(func(j): return m.skin_col(j).a == 0.0), "Easy: no body part has the limit tint (%s)" % str(lim))
	# FOOT PADS AND THE RED (Easy playback): the video's footprint pads are not drawn; a red spot on the body gets its one line
	m.S.iq = {"contacts": [{"part": "foot_r", "kind": "foot", "x": 0.0, "z": 0.0, "yaw": 0.0, "t0": 0.0, "t1": m.S.length()}]}
	m._check()
	await idle(3)
	m._refresh()
	await idle(2)
	var pads := 0
	if m._iq_mesh != null:
		pads += (m._iq_mesh.mesh as ImmediateMesh).get_surface_count()
	if m._fp_line != null:
		pads += (m._fp_line.mesh as ImmediateMesh).get_surface_count()
	ok(pads == 0, "Easy playback of the Punch card: no foot pad or footprint is drawn (%d surfaces)" % pads)
	if m.redspots.spots.is_empty():   # the Punch card has no problem Check glows: one FAIL on the hips at mid-clip, so the line has a red to explain
		m.redspots.set_findings([{"rule": "HIPS TURN", "sev": "FAIL", "msg": "the hips turn too fast", "t": m.S.length() * 0.5}])
	var t_keep: float = m.playhead
	var lit_t := -1.0   # the first frame (every 3rd) where Check's red spot is on the body: the line must show there
	for k in range(0, int(m.S.length() * m.S.fps) + 1, 3):
		m.playhead = float(k) / float(m.S.fps)
		m._refresh()
		if not m.redspots.last.is_empty():
			lit_t = m.playhead
			break
	var red_lit: bool = lit_t >= 0.0
	m.playhead = lit_t if red_lit else t_keep
	m._refresh()
	await idle(2)
	ok(not red_lit or m.easy.red_note.visible, "Easy: a red spot on the body is said in one line (red lit at %.2f s: %s, line shown: %s)" % [lit_t, str(red_lit), str(m.easy.red_note.visible)])
	ok(red_lit or not m.easy.red_note.visible, "Easy: no red spot at the playhead, no red line (lit: %s)" % str(red_lit))
	m.easy.set_on(false, false)
	await idle(12)
	m._refresh()
	await idle(2)
	ok(lim.any(func(j): return m.skin_col(j).a > 0.0), "Expert: the limit tint shows on the same body (the check above can see it)")
	ok(m._iq_mesh != null and (m._iq_mesh.mesh as ImmediateMesh).get_surface_count() > 0, "Expert: the foot pad shows (the check above can see it)")
	ok(not m.easy.red_note.visible, "Expert: no Easy red line")
	ok(card_lines() == x_lines, "Expert switch: every card line is the old text again (%d lines)" % x_lines.size())
	ok(absf(m.ui_bp.size.y - x_h) < 0.5, "Expert switch: the bottom panel is its old height (%d px -> %d px)" % [int(x_h), int(m.ui_bp.size.y)])
	m.easy.set_on(true, false)
	await idle(4)

	# 5. Expert: every panel's visibility exactly as before the Easy switch
	m.easy.button("Switch to Expert").pressed.emit()
	await idle()
	ok(not m.easy.on and not m.easy.bar.visible, "Switch to Expert leaves Easy")
	ok(m.ui_top_bar.visible and m.ui_side_of["left"].visible and m.ui_side_of["right"].visible and m.ui_bh.visible and m.ui_cube.visible and m.ui_nav.visible, "Expert switch: the top bar, both side panels, the scene header, cube and nav are back")
	ok(cfg_mode() == "expert", "the Expert choice is saved in the settings file")
	ok(m.lw() == m.LEFT_W and m.rw() == m.RIGHT_W, "the view's room is the side panels' again")
	m.easy.set_on(true)
	await idle()
	ok(m.easy.on and cfg_mode() == "easy", "turning Easy on again is saved as easy")
	m.easy.set_on(false)
	await idle()

	# 6. UNDO SAYS WHAT IT TAKES BACK (Easy only): "Undo: Walk", "Undo: Faster", "Undo" with nothing to undo; the toast says the short name
	m.easy.set_on(true, false)
	m.undo.clear()
	m.redo.clear()
	m._new_scene()
	m.undo.clear()
	m.redo.clear()
	await idle(3)
	ok(undo_words() == UNDO_NONE, "6: an empty scene with nothing to undo: the Undo button reads 'Undo' and its tooltip says so (%s)" % undo_words())
	m.easy.home.panel.find_child("eh_card_0", true, false).pressed.emit()   # Walk
	await idle(30)
	ok(undo_words() == "Undo: Walk", "6: after the Walk card the Undo button reads 'Undo: Walk' (%s)" % undo_words())
	m.easy.home.strip.find_child("eh_faster", true, false).pressed.emit()
	await idle(10)
	ok(undo_words() == "Undo: Faster", "6: after Faster the Undo button reads 'Undo: Faster' (%s)" % undo_words())
	m.easy.button("Undo").pressed.emit()
	await idle(10)
	ok(undo_words() == "Undo: Walk", "6: after Undo the button reads 'Undo: Walk' (%s)" % undo_words())
	ok(m.ui_toast != null and m.ui_toast.text == "Took back: Faster", "6: the toast after Undo says 'Took back: Faster' (the same words as the status line) (%s)" % (m.ui_toast.text if m.ui_toast else "none"))
	ok(m.ui_status.text.begins_with("Took back: Faster"), "6: the say line after Undo says 'Took back: Faster', no Expert step name (%s)" % m.ui_status.text)
	m.easy.button("Undo").pressed.emit()
	await idle(10)
	ok(undo_words() == UNDO_NONE, "6: undoing the Walk card leaves nothing to undo: 'Undo' (%s)" % undo_words())
	# a placed library object is one undo step, named by its tile
	m._library_toggle()
	await idle(3)
	var sword_id := ""
	for it in m.ui_library.items:
		if it["name"] == "Sword":
			sword_id = String(it["id"])
	var u0: int = m.undo.size()
	var placed: bool = sword_id != "" and m.ui_library.place(sword_id)
	await idle(6)
	ok(placed and m.undo.size() == u0 + 1, "6: a library Sword is one undo step (%d -> %d steps; id '%s')" % [u0, m.undo.size(), sword_id])
	ok(undo_words() == "Undo: Sword", "6: after a library Sword the Undo button reads 'Undo' with the tooltip 'Undo: Sword' (%s)" % undo_words())
	# 6b. ITEM 5 (Easy): the sword at its pick is clear. No body part reads "touch" (the red pick_touch tint) and the held sword
	# sinks into no body part, so the frozen pick-time pose shows no red
	var red := Tok.c("pick_touch")
	var tinted := []
	for j in Body.ORDER:
		var sc: Color = m.skin_col(j)
		if sc.a > 0.0 and sc.is_equal_approx(Color(red, sc.a)):
			tinted.append(j)
	var sword_hits := ObjectLibrary._wep_hits(m.B)
	ok(tinted.is_empty() and sword_hits == 0, "6b: the sword at its pick: no body part red (%s), the sword sinks into %d part(s)" % [str(tinted), sword_hits])
	# a drag's undo is named in everyday words: "Undo: Move hand", not "Drag left wrist / h.."
	m._library_toggle()
	await idle(3)
	m.playing = false
	await drag("hand_l")
	await idle(6)
	ok(undo_words() == "Undo: Move hand", "6: after dragging a hand the Undo button reads 'Undo: Move hand' (%s)" % undo_words())
	m.easy.button("Undo").pressed.emit()
	await idle(6)
	ok(m.ui_status.text.begins_with("Took back: Move hand"), "6: its toast says 'Took back: Move hand' (%s)" % m.ui_status.text)
	m.easy.button("Undo").pressed.emit()
	await idle(4)
	ok(undo_words() == UNDO_NONE, "6: undoing the Sword leaves nothing to undo: 'Undo' (%s)" % undo_words())
	m.ui_library.hide_panel()
	# More's entries that change the body: one undo step each, named in Easy ("Flip", "Feet on floor")
	m.easy.pick_more("Flip left and right")
	await idle(4)
	ok(undo_words() == "Undo: Flip" and m.undo.size() == 1, "6: More > Flip left and right is one step: 'Undo: Flip' (%s, %d steps)" % [undo_words(), m.undo.size()])
	m.easy.button("Undo").pressed.emit()
	await idle(4)
	m.easy.pick_more("Put his feet on the floor")
	await idle(4)
	# feet on the floor keeps nothing on an empty scene: the step is dropped (Fixer.plant_all: "one undo step, or none"), so no step
	ok(undo_words() == UNDO_NONE and m.undo.size() == 0,"6: More > Put his feet on the floor with nothing to plant adds no step (%s, %d steps)" % [undo_words(), m.undo.size()])
	# the button never grows: a long name is cut to 18 characters (+ "..") and the bar's button keeps its height
	var h0: float = m.easy.button("Undo").size.y
	m._step_easy = "a very long typed move name that is cut"
	m._push_undo()
	await idle(3)
	var cut := undo_words()
	ok(cut.begins_with("Undo: a very long type") and cut.length() <= 24 and cut.ends_with(".."), "6: a long name is cut in the button: '%s'" % cut)
	ok(m.easy.button("Undo") != null and (m.easy.button("Undo").get_node("label") as Label).text == "Undo", "6: the Undo label stays 'Undo' with a long name (the name is the tooltip only)")
	ok(is_equal_approx(m.easy.button("Undo").size.y, h0),"6: the Undo button keeps its height with a long name (%.0f -> %.0f px)" % [h0, m.easy.button("Undo").size.y])
	m._undo()
	await idle(2)
	# Expert: the step's name never uses the Easy short name, and Expert's Undo tooltip is the Expert name
	var ex: Dictionary = {"name": "Cards 1-8 at 80 %: the scene is now 3.96 s", "easy": "Faster"}
	ok(m._step_label(ex) == "Cards 1-8 at 80 %: the scene is now 3.96 s", "6: Expert's _step_label ignores the Easy name")

	# 9. THE FIRST-START LINE: a fresh Easy start shows exactly one teaching line, in Easy's words; the first real pick ends
	# it for good; an Expert fresh start still shows the Expert welcome (the strip's own words)
	await fresh_start(true)
	var lines := teach_lines()
	ok(lines.size() == 1 and lines[0] == MouseHint.EASY_LINE, "9: a fresh Easy start shows exactly one teaching line, in Easy's words: %s" % str(lines))
	var head_p: Vector2 = m.cam.unproject_position((m.B.cap("head")[0] + m.B.cap("head")[1]) * 0.5)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = head_p
		e.global_position = head_p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(3)
	cf = ConfigFile.new()
	cf.load(m.settings)
	ok(m.sel == "head" and not (m.ui_status.is_visible_in_tree() and m.is_welcome(m.ui_status.text)) and cf.get_value("look", "taught", false) == true,
		"9: after the first real pick the teaching strip is gone and the settings say taught ('%s')" % m.ui_status.text.left(40))
	ok(not teach_lines().any(func(t): return t != MouseHint.EASY_LINE), "9: and what is left teaching is Easy's line only: %s" % str(teach_lines()))
	await fresh_start(false)
	lines = teach_lines()
	ok(not m.easy.on and lines.size() == 1 and lines[0] == m.WELCOME, "9: an Expert fresh start still shows the Expert welcome: %s" % str(lines))

	# 10. THE PLAIN WORDS (a beginner's walk-through): the sword's place line and the library's line have no size, weight,
	# key or jargon; the drag's hand is the hand that holds the sword; the Punch card's strip names are plain words
	m.easy.set_on(true, false)
	await idle(6)
	if m.ui_library != null and m.ui_library.visible:
		m.ui_library.hide_panel()
	m._library_toggle()
	await idle(2)
	var lib_open := plain_bad(m.ui_status.text)
	ok(lib_open.is_empty(), "10: Easy's library line has none of cm / kg / Ctrl+Z / arming (%s)" % str(lib_open))
	if m.B.wep_on:
		m._bat_remove()
		await idle(2)
	m._kind("sword")
	await idle(2)
	var sword_said: String = m.ui_status.text
	var sword_bad := plain_bad(sword_said)
	ok(sword_bad.is_empty() and sword_said != "", "10: Easy's sword place line has none of cm / kg / Ctrl+Z / arming: '%s' %s" % [sword_said, str(sword_bad)])
	var sid := ""
	for it in m.ui_library.items:
		if String(it["name"]).to_lower() == "sword":
			sid = String(it["id"])
	ok(sid != "", "10: the library lists a Sword tile")
	if sid != "":
		m.ui_library.place(sid)
		await idle(2)
	var tile_note: String = m.ui_library._note.text
	var note_bad := plain_bad(tile_note)
	ok(note_bad.is_empty(), "10: Easy's library hint after a sword tile has none of cm / kg / Ctrl+Z / arming: '%s' %s" % [tile_note, str(note_bad)])
	# a left-hand drag onto the sword that is in the right hand: the hint names the hand that holds it (his right)
	m._kind("sword")
	await idle(2)
	ok(m.B.wep_hand == "hand_r", "10: the sword is in his right hand before the drag (%s)" % m.B.wep_hand)
	m.sel = "hand_l"
	m.dragging = "joint"
	m._grab = m.B.wep_point(m.B.wep_handle * 0.5)
	btn(false, Vector2(10, 10))
	await idle(3)
	var drag_said: String = m.ui_status.text
	ok(drag_said.to_lower().find("right hand") >= 0 and drag_said.find("wrist") < 0 and drag_said.find("left hand holds") < 0,
		"10: the drag's hint names the hand that holds the sword (his right): '%s'" % drag_said)
	# the Punch card's strip names: plain words, no all-caps word, the names of the card as they are
	m.easy.home.card(3)
	await idle(12)
	var p_names := []
	for k in card_lines():
		if k.ends_with("/b_pick"):
			p_names.append(card_lines()[k])
	var p_caps := p_names.filter(func(t): return has_caps_word(String(t)))
	var p_want := ["Guard", "Wind up", "Punch", "Back to guard"]
	var p_sorted := p_names.duplicate()
	p_sorted.sort()
	var p_want_sorted := p_want.duplicate()
	p_want_sorted.sort()
	ok(p_caps.is_empty() and p_sorted == p_want_sorted, "10: the Punch card's strip names are plain words, in sentence case: %s (all caps: %s)" % [str(p_names), str(p_caps)])
	m._new_scene()
	await idle()
	# 10b. the Run card's strip (round 2): no template code ("mid R0", "off L1", "air 0", "land R2", "half step L", "stop: ...",
	# "swing 3") is shown, and the first card reads "Run 1" (its name is "<Move> <place in the strip>")
	m.easy.home.card(1)
	await idle(12)
	var r_lines := card_lines()
	var r_names := []
	for i in m.S.cards.size():
		r_names.append(String(r_lines.get("card_%d/b_pick" % (i + 1), "")))
	var code_re := RegEx.create_from_string("^(mid|off|air|land|swing|half step|step|stop)\\b")   # the template codes (main.EASY_CODE_NAME)
	var r_codes := r_names.filter(func(t): return code_re.search(String(t).to_lower()) != null)
	ok(r_names.size() >= 4 and r_codes.is_empty() and r_names[0] == "Run 1" and r_names.all(func(t): return String(t).begins_with("Run ")),
		"10b: Easy's Run strip has no template codes and reads 'Run 1' first: %s (codes: %s)" % [str(r_names), str(r_codes)])
	m.easy.set_on(false, false)
	m._refresh()
	await idle(12)
	var x_run := card_lines()
	ok(x_run.get("card_1/b_pick", "") == "1 %s" % String(m.S.cards[0]["name"]), "10b: Expert's strip keeps the stored names with the number: '%s'" % str(x_run.get("card_1/b_pick", "")))
	m.easy.set_on(true, false)
	await idle(6)
	# 10c. the drag's stop in Easy: plain words, no digits and no degree sign; Expert's line keeps its numbers
	var drag_lim := {"kind": "limit", "joint": "upperarm_r", "axis": "side", "at": 90.0, "lo": -95.0, "hi": 90.0}
	var e_stop: String = m.stop_words(drag_lim)
	var e_digits := RegEx.create_from_string("[0-9°]").search(e_stop)
	ok(e_digits == null and e_stop.find("His arm can't bend further that way.") >= 0,
		"10c: Easy's drag limit has no digits or degree sign and names the arm: '%s'" % e_stop.strip_edges())
	m.easy.set_on(false, false)
	var x_stop: String = m.stop_words(drag_lim)
	ok("STOPPED: the right upper arm is at its limit, side 90" in x_stop, "10c: Expert's drag limit keeps its numbers: '%s'" % x_stop.strip_edges())
	m.easy.set_on(true, false)
	# 10d. Save (Easy): "Saved <name> (<seconds> seconds)."; Expert keeps "saved scene <name>: N cards, ..."
	m._save_scene_now("zz_run_68")
	await idle(2)
	var e_save: String = m.ui_status.text
	var sv_re := RegEx.create_from_string("^Saved .*seconds\\)\\.$")
	ok(sv_re.search(e_save) != null and e_save.find("zz run 68") >= 0, "10d: Easy's save status reads 'Saved <name> (<n> seconds).': '%s'" % e_save)
	m.easy.set_on(false, false)
	m._save_scene_now("zz_run_68")
	await idle(2)
	var x_save: String = m.ui_status.text
	ok(x_save.begins_with("saved scene zz_run_68: ") and x_save.find(" frames with parts inside each other") >= 0, "10d: Expert's save status keeps its words: '%s'" % x_save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPaths.w("res://scenes/zz_run_68.json")))
	m.easy.set_on(false, false)
	await idle(6)

	# 10e. + ADD POSE (Easy): the strip's end button. An empty scene shows it with the tip; a press adds the body's pose as a
	# card after the selected one (the new card selected, in view, one undo step "Add pose"); the same pose as the card
	# before is refused in plain words; More's Save this pose as a card still adds; Expert has no button
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	var tip_ok := false
	for c in m.ui_cards.get_children():
		if c is Label and (c as Label).text == "Drag his arms and legs, then press + Add pose":
			tip_ok = true
	var ab: Button = add_btn()
	ok(ab != null and ab.is_visible_in_tree() and ab.text == "+ Add pose", "10e: an empty Easy scene shows the '+ Add pose' button in the strip")
	ok(tip_ok, "10e: the empty strip has the tip 'Drag his arms and legs, then press + Add pose'")
	var tour_t := ""
	for st in m.easy.TOUR:
		tour_t += String(st[1]) + " "
	ok(tour_t.find("+ Add pose") >= 0 and tour_t.find("Save this pose as a card") < 0 and tour_t.find("then press More") < 0, "10e: the Easy tour says 'press + Add pose' (no 'More, then Save this pose as a card')")
	await drag_at(spot("hand_r"), Vector2(48, -48))   # a plain press on the hand's centre, as a beginner's (a finger under it picks the hand in Easy: 10g)
	await idle(2)
	await click_ctl(add_btn())
	ok(m.S.cards.size() == 1, "10e: a real click on '+ Add pose' after a drag adds one card (%d)" % m.S.cards.size())
	ok(undo_words() == "Undo: Add pose", "10e: the undo step is named 'Add pose' (%s)" % undo_words())
	var pc1 := m.ui_cards.get_node_or_null("card_1") as Control
	var row: Rect2 = m.ui_card_row.get_global_rect()
	ok(m.sel_card == 0 and pc1 != null and pc1.get_global_rect().position.x >= row.position.x - 1.0 and pc1.get_global_rect().end.x <= row.end.x + 1.0, "10e: the new card is selected and in view in the strip (sel %d)" % m.sel_card)
	ok(m.ui_status.text.begins_with("added card"), "10e: the status line says the card was added (%s)" % m.ui_status.text)
	move(inside("hand_r"), Vector2.ZERO)   # the pointer over the hand first, as a person's is (the press picks what it hovers)
	await idle(2)
	await drag("hand_r", Vector2(0, -70))   # up: a pose clearly different from card 1 (back the way it came could land on the rest pose the arm started from)
	await idle(2)
	await click_ctl(add_btn())
	ok(m.S.cards.size() == 2 and m.sel_card == 1, "10e: a second drag and '+ Add pose' make 2 cards, the second selected (%d, sel %d)" % [m.S.cards.size(), m.sel_card])
	await click_ctl(add_btn())
	ok(m.S.cards.size() == 2 and m.ui_status.text == "Move him first, then add the pose.", "10e: '+ Add pose' with the body unmoved adds nothing and says 'Move him first, then add the pose.' (%d cards, '%s')" % [m.S.cards.size(), m.ui_status.text])
	# PLAY: the hand moves from the first pose to the second (somewhere between the two card times it is clearly away from both ends)
	var ttimes: Array = m.S.times()
	var ends: Array = []
	var best := 0.0
	if ttimes.size() >= 2:
		m._ps().apply(m.B, float(ttimes[0][1]))
		var p0: Vector3 = m.B.P["hand_r"]
		m._ps().apply(m.B, float(ttimes[1][1]))
		var p1: Vector3 = m.B.P["hand_r"]
		ends = [p0, p1]
		for k in range(1, 20):   # the move itself: from the first card's leaving to the second card's arriving
			m._ps().apply(m.B, lerpf(float(ttimes[1][0]), float(ttimes[1][1]), k / 20.0))
			var pm: Vector3 = m.B.P["hand_r"]
			best = maxf(best, minf(pm.distance_to(p0), pm.distance_to(p1)))
	var span: float = ends[0].distance_to(ends[1]) if ends.size() == 2 else 0.0
	ok(span > 0.05 and best > 0.25 * span, "10e: Play moves the hand between the two '+ Add pose' poses (%d poses %.3f m apart; mid-move the hand is %.3f m from both ends)" % [ttimes.size(), span, best])
	await click_ctl(m.easy.button("Undo"))
	ok(m.S.cards.size() == 1, "10e: Undo removes the added card (%d)" % m.S.cards.size())
	m.easy.pick_more("Save this pose as a card")
	await idle(2)
	ok(m.S.cards.size() == 2, "10e: More > Save this pose as a card still adds a card (%d)" % m.S.cards.size())
	m.easy.set_on(false, false)
	await idle(4)
	ok(m.easy.add_button() == null, "10e: Expert has no '+ Add pose' button")
	m._new_scene()
	await idle(4)

	# 10f. NEXT MOVES (Easy): after the Walk card, three "Then <move>" buttons (Catalog.next_after). None overlaps another Easy
	# control. A press adds that move after the clip as ONE undo step (the strip's cards grow); Undo takes it back; after the
	# add the buttons offer the added move's next moves; Expert shows none, and an empty scene shows none.
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	if m.ui_library != null and m.ui_library.visible:   # an open library covers the picker: close it, as the overlap bar does
		m.ui_library.hide_panel()
		await idle(4)
	await click_ctl(m.easy.home.panel.find_child("eh_card_0", true, false))   # Walk, a real click
	await idle(4)
	var nb := next_btns()
	var texts := nb.map(func(b): return String(b.text))
	ok(texts == ["Then run", "Then wave", "Then sit down"], "10f: after the Walk card three buttons read 'Then run', 'Then wave', 'Then sit down' (%s)" % str(texts))
	if m.ui_toast != null:   # a Redo toast left by an earlier step of this run is not this bar's subject: hidden, as overlap_set does
		m.ui_toast.visible = false
	var rs: Array = easy_rects().filter(func(r): return r[0] != "picker strip" and r[0] != "easy top bar")
	for b in nb:
		rs.append(["then " + b.text, b.get_global_rect()])
	for b in easy_buttons():
		if not String(b.name).begins_with("eh_next_"):   # the Then buttons are the rects above
			rs.append(["button " + b.name, b.get_global_rect()])
	var then_over := overlap_pairs(rs)
	ok(then_over.is_empty(), "10f: the Then buttons overlap no other Easy control (%s)" % str(then_over))
	ok(outside_window(rs, Vector2(m.get_window().size)).is_empty(), "10f: the Then buttons and the Easy controls sit inside the window")
	var nw0: int = m.S.cards.size()
	var uw0: int = m.undo.size()
	await click_ctl(nb[0])
	await idle(4)
	var run_n: int = Templates.read("run")["cards"].size()
	ok(m.S.cards.size() == nw0 + run_n and m.undo.size() == uw0 + 1, "10f: 'Then run' adds the run's %d cards after the walk as ONE undo step (cards %d -> %d, undo %d -> %d)" % [run_n, nw0, m.S.cards.size(), uw0, m.undo.size()])
	await idle(3)
	# + Add pose stays in reach on a long strip: the walk + run is many cards, more than the strip shows, and the button is pinned
	var apb := add_btn()
	var row_r: Rect2 = m.ui_card_row.get_global_rect()
	var ap_r: Rect2 = apb.get_global_rect() if apb != null else Rect2()
	var win_r := Rect2(Vector2.ZERO, Vector2(m.get_window().size))
	ok(apb != null and apb.is_visible_in_tree() and win_r.encloses(ap_r) and (m.ui_cards.size.x > row_r.size.x) and ap_r.position.x >= row_r.end.x - 1.0,
		"10f: with %d cards (strip %.0f px wide in a %.0f px view) '+ Add pose' is on screen, right of the strip (%s)" % [m.S.cards.size(), m.ui_cards.size.x, row_r.size.x, str(ap_r)])
	ok(undo_words() == "Undo: Add run", "10f: the undo step is named after the move: 'Undo: Add run' (%s)" % undo_words())
	var nb2 := next_btns().map(func(b): return String(b.text))
	ok(nb2 == ["Then jump", "Then sword swing", "Then walk"], "10f: after the run the buttons offer the run's next moves (%s)" % str(nb2))
	m.easy.button("Undo").pressed.emit()
	await idle(4)
	ok(m.S.cards.size() == nw0 and m.undo.size() == uw0, "10f: Undo removes the added run in one step (%d cards)" % m.S.cards.size())
	var nb3 := next_btns().map(func(b): return String(b.text))
	ok(nb3 == texts, "10f: after Undo the buttons offer the walk's moves again (%s)" % str(nb3))
	m.easy.set_on(false, false)
	await idle(4)
	ok(next_btns().is_empty(), "10f: Expert shows no Then buttons")
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	ok(next_btns().is_empty(), "10f: an empty scene shows no Then buttons")
	# the catalog: the shipped file is good, and a copy with one missing source fails the check
	var entries: Array = Catalog.load()
	ok(entries.size() > 0 and Catalog.problems(entries).is_empty(), "10f: the shipped catalog has %d entries and no problems (%s)" % [entries.size(), str(Catalog.problems(entries))])
	var broken: Array = entries.duplicate(true)
	broken[0]["source"] = "templates/no_such_move.json"
	var tmp := "user://poser_test_catalog.json"
	var wf := FileAccess.open(tmp, FileAccess.WRITE)
	wf.store_string(JSON.stringify(broken))
	wf.close()
	var probs: Array = Catalog.problems(Catalog.load(tmp))
	ok(probs.size() == 1 and String(probs[0]).find("no_such_move") >= 0, "10f: a catalog with one missing source fails the check (%s)" % str(probs))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	m.easy.set_on(false, false)
	await idle(4)
	m._new_scene()
	await idle(4)

	# 10h. A DRAG + "+ Add pose" IS ONE UNDO STEP (Easy, walk-through a/b/c): Undo removes the card AND puts the body back as it
	# was before the drag; Redo puts both back. Toast and status line use the same words; a toast is gone after a few seconds
	# and the next action's message replaces it.
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	var pose0 := JSON.stringify(m.B.state())
	var u0h: int = m.undo.size()
	await drag("hand_r")
	await idle(2)
	var pose1 := JSON.stringify(m.B.state())
	ok(pose1 != pose0 and m.undo.size() == u0h + 1, "10h: the drag is one undo step (pose moved %s, undo %d -> %d)" % [str(pose1 != pose0), u0h, m.undo.size()])
	await click_ctl(add_btn())
	await idle(4)
	ok(m.S.cards.size() == 1 and m.undo.size() == u0h + 1, "10h: '+ Add pose' after the drag adds a card with no step of its own (cards %d, undo %d -> %d)" % [m.S.cards.size(), u0h + 1, m.undo.size()])
	ok(undo_words() == "Undo: Add pose", "10h: the one step is named 'Add pose' (%s)" % undo_words())
	var pose_after := JSON.stringify(m.B.state())
	var cards_after := JSON.stringify(m.S.cards)
	await click_ctl(m.easy.button("Undo"))
	await idle(4)
	ok(m.S.cards.size() == 0, "10h: Undo removes the card (%d cards)" % m.S.cards.size())
	ok(JSON.stringify(m.B.state()) == pose0, "10h: Undo puts the hand back as it was before the drag")
	ok(m.ui_status.text.begins_with("Took back: Add pose") and m.ui_toast.text == "Took back: Add pose", "10h: Undo says 'Took back: Add pose' in the toast and the status line (toast '%s', status '%s')" % [m.ui_toast.text, m.ui_status.text])
	await click_ctl(m.easy.button("Redo"))
	await idle(4)
	ok(m.S.cards.size() == 1 and JSON.stringify(m.S.cards) == cards_after, "10h: Redo puts the card back")
	ok(JSON.stringify(m.B.state()) == pose_after, "10h: Redo puts the pose back as it was after the add")
	ok(m.ui_status.text.begins_with("Put back: Add pose") and m.ui_toast.text == "Put back: Add pose", "10h: Redo says 'Put back: Add pose' in the toast and the status line (toast '%s', status '%s')" % [m.ui_toast.text, m.ui_status.text])
	# a toast is gone after a few seconds (5 s bar: the Easy toast is up for 3 s)
	await create_timer(4.0).timeout
	ok(not m.ui_toast.visible, "10h: the Redo toast is gone 4 s later")
	# the next action's message replaces a toast that is still up: opening the library takes the old one down
	m._undo()
	await idle(2)
	ok(m.ui_toast.visible, "10h: a fresh toast shows after an Undo (%s)" % m.ui_toast.text)
	m._library_toggle()
	await idle(2)
	ok(not m.ui_toast.visible, "10h: opening the library takes the stale toast down")
	m._library_toggle()
	await idle(2)
	m.easy.set_on(false, false)
	await idle(4)
	# 10g. THE FINGER IS THE HAND (Easy): a beginner presses a hand and lands on a finger; in Easy the press picks the hand, so a real
	# press + drag started on a finger's screen point moves the arm by the hand (>= 5 cm), its undo step is named for the hand, and the
	# hover over the finger says "right hand". Expert keeps the finger: the same point picks and names the finger.
	m.easy.set_on(false, false)
	m._new_scene()
	await idle(4)
	var fq := finger_point("middle_01_r")
	ok(fq.is_finite(), "10g: a screen point of the right middle finger's base joint is found (%s)" % str(fq))
	await hover_at(fq)
	ok(m._pick(fq) == "middle_01_r" and m.bar_text().contains("right middle finger"), "10g: Expert: the hover over the finger names it (pick '%s', bar '%s')" % [m._pick(fq), m.bar_text()])
	btn(true, fq)
	await process_frame
	btn(false, fq)
	await idle(2)
	ok(m.sel == "middle_01_r", "10g: Expert: a press on the finger picks the finger (sel '%s')" % m.sel)
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	fq = finger_point("middle_01_r", "hand_r")
	ok(fq.is_finite(), "10g: in Easy a point of the finger picks the right hand (%s)" % str(fq))
	await hover_at(fq)
	# Easy's bar keeps its words hidden (the short line), so the hover's name is the part the hover lights and what the words call it
	ok(m.hover_part == "hand_r" and m.part_words(m.hover_part) == "right hand", "10g: Easy: the hover over the finger lights the hand and calls it 'right hand' (hover '%s', words '%s')" % [m.hover_part, m.part_words(m.hover_part)])
	var hand0: Vector3 = m.B.P["hand_r"]
	await drag_at(fq, Vector2(48, -48))
	await idle(2)
	var hand_moved: float = (m.B.P["hand_r"] - hand0).length()
	ok(hand_moved >= 0.05, "10g: Easy: a press + drag started on the finger moves the hand %.3f m (>= 0.05)" % hand_moved)
	var last_undo: Dictionary = m.undo[-1] if not m.undo.is_empty() else {}
	ok(m.easy_name(last_undo) == "Move hand", "10g: Easy: the undo step is named for the hand: '%s'" % m.easy_name(last_undo))
	# 10i. PLAIN MOVE NAMES (Easy): every card of a move (a template, a Then move) reads "<Move> <n>" in plain words, numbered per
	# move run in strip order ("Punch 1..4", then "Kick 1..7"): no ":" and no card label wider than its card. The full name
	# stays in the tooltip; Expert shows the stored names.
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	if m.ui_library != null and m.ui_library.visible:
		m.ui_library.hide_panel()
		await idle(4)
	await click_ctl(m.easy.home.panel.find_child("eh_card_3", true, false))   # Punch, a real click
	await idle(8)
	var s10i_kick_btn: Button = null
	for b in next_btns():
		if b.text == "Then kick":
			s10i_kick_btn = b
	ok(s10i_kick_btn != null, "10i: after Punch the Then row offers 'Then kick' (%s)" % str(next_btns().map(func(x): return x.text)))
	if s10i_kick_btn != null:
		await click_ctl(s10i_kick_btn)
		await idle(12)
	var s10i_pl := card_lines()
	var s10i_pl_names := []
	var s10i_plain_re := RegEx.create_from_string("^[A-Z][a-z]+( [a-z]+)? [0-9]+$")
	var s10i_tight := []
	var s10i_strip_tip_ok := true
	for i in m.S.cards.size():
		var s10i_nb: Button = null
		for n in m.ui_cards.find_children("b_pick", "Button", true, false):
			if n.get_parent().get_parent().name == "card_%d" % (i + 1):
				s10i_nb = n
		if s10i_nb == null:
			s10i_tight.append("card %d missing" % (i + 1))
			continue
		s10i_pl_names.append(s10i_nb.text)
		var s10i_card_w: float = (s10i_nb.get_parent().get_parent() as Control).size.x
		if s10i_nb.get_combined_minimum_size().x > s10i_card_w + 0.5:
			s10i_tight.append("%s (%.0f > %.0f)" % [s10i_nb.text, s10i_nb.get_combined_minimum_size().x, s10i_card_w])
		if s10i_nb.tooltip_text.find(String(m.S.cards[i]["name"])) < 0:
			s10i_strip_tip_ok = false
	var s10i_names_ok: bool = s10i_pl_names.size() == m.S.cards.size() and s10i_pl_names.all(func(t): return String(t) in ["Guard", "Wind up", "Punch", "Back to guard"] or s10i_plain_re.search(String(t)) != null)
	var s10i_no_colon: bool = s10i_pl_names.all(func(t): return String(t).find(":") < 0)
	var s10i_jargon_left: Array = s10i_pl_names.filter(func(t): return String(t).to_lower().begins_with("anticipation") or String(t).to_lower().begins_with("strike") or String(t).to_lower().begins_with("follow-through") or String(t).to_lower().begins_with("recovery") or String(t).to_lower().begins_with("ready"))
	ok(m.S.cards.size() >= 9 and s10i_names_ok and s10i_no_colon and s10i_jargon_left.is_empty(), "10i: no jargon left: every label is a plain name or '<Word> <n>', no ':' (%s)" % str(s10i_pl_names))
	ok(s10i_pl_names.size() >= 9 and s10i_pl_names.slice(0, 4) == ["Guard", "Wind up", "Punch", "Back to guard"] and s10i_pl_names.slice(4).all(func(t): return String(t).begins_with("Kick ")) and s10i_pl_names[4] == "Kick 1" and s10i_pl_names[-1] == "Kick %d" % (m.S.cards.size() - 4),
		"10i: the plain names stay (Guard, Wind up, Punch, Back to guard); the jargon cards are 'Kick 1..n' in their run (%s)" % str(s10i_pl_names))
	ok(s10i_tight.is_empty(), "10i: no strip label is wider than its card (%s)" % str(s10i_tight))
	ok(s10i_strip_tip_ok, "10i: each card's tooltip keeps the original name")
	# Expert: the stored names, as before
	m.easy.set_on(false, false)
	m._refresh()
	await idle(12)
	var s10i_xl := card_lines()
	var s10i_x_ok := true
	for i in m.S.cards.size():
		if String(s10i_xl.get("card_%d/b_pick" % (i + 1), "")) != "%d %s" % [i + 1, m.S.cards[i]["name"]]:
			s10i_x_ok = false
	ok(s10i_x_ok, "10i: Expert's strip shows the original names with their numbers")
	m.easy.set_on(true, false)
	await idle(6)
	# "Then sword swing" (a Then button after Walk + Then run) fits its button
	m._new_scene()
	await idle(4)
	await click_ctl(m.easy.home.panel.find_child("eh_card_0", true, false))
	await idle(6)
	for b in next_btns():
		if b.text == "Then run":
			await click_ctl(b)
			await idle(10)
			break
	var s10i_sw_btn: Button = null
	for b in next_btns():
		if b.text == "Then sword swing":
			s10i_sw_btn = b
	ok(s10i_sw_btn != null, "10i: after Walk + Then run the Then row offers 'Then sword swing'")
	if s10i_sw_btn != null:
		var s10i_tw: float = s10i_sw_btn.get_theme_font("font", "Button").get_string_size(s10i_sw_btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s10i_sw_btn.get_theme_font_size("font_size", "Button")).x
		var s10i_pad: float = s10i_sw_btn.get_theme_stylebox("normal").get_minimum_size().x
		ok(s10i_tw + s10i_pad <= s10i_sw_btn.size.x + 0.5 and s10i_sw_btn.get_combined_minimum_size().x <= s10i_sw_btn.size.x + 0.5,
			"10i: the 'Then sword swing' text fits its button (text %.0f + s10i_pad %.0f <= button %.0f)" % [s10i_tw, s10i_pad, s10i_sw_btn.size.x])
	m.easy.set_on(false, false)
	m._new_scene()
	await idle(4)

	# 11. the overlap bar: Easy's panels, toast and lines, at the window's own size (both sizes: the easy_overlap suite)
	m.easy.set_on(true, false)
	await idle(4)
	await overlap_bar([m.get_window().size])
	m.easy.set_on(false, false)
	await idle(4)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("EASY MODE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
