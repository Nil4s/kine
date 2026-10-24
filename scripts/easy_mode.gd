class_name EasyMode
extends Node
## EASY MODE (docs/ROADMAP.md items 3 and 4; beginners are lost in 140+ commands).
## Easy: ONE bar of 7 big labelled buttons (Library, Save video, Play / Stop, Undo, New scene, More, Switch to Expert)
## takes the top strip's place; More opens a menu with the rest (Key this pose, Pose, Undo, Redo, Save scene, Mirror
## pose, Floor, Copy a video). The side panels, the top tools, the scene header and the play row are HIDDEN (never removed). Expert: every one of them is back exactly as it was.
## The mode is remembered in poser.cfg [look] mode. A fresh config is Easy; an existing config with no mode key is
## Expert, so nothing changes for people who already use the app. A test is Expert unless it says otherwise.
## First-run tour (Easy only, once, skippable, Help: show the tour): five steps, each moved on by the real action.

const CFG := "look"
const TOUR := [
	["Drag a hand", "Press on a hand of the body and drag it. The arm follows, and the pose changes."],
	["Key the pose", "Press More, then Key this pose. The body's pose becomes a card on the timeline at the bottom."],
	["Move the playhead", "Drag the playhead (the line on the timeline) to another moment."],
	["Change the pose and key again", "Move a part to a new place, then press More, then Key this pose again."],
	["Press play", "Press Play. The body moves from card to card by itself."],
]

var m: Node                 # main (untyped: the same pattern as Browser)
var on := false             # Easy is showing
var tour_step := -1         # -1 = no tour
var bar: PanelContainer
var tour_card: PanelContainer
var _tour_title: Label
var _tour_text: Label
var _expert: Array = []     # the nodes Easy hides (main's panels and tools)
var _vis := {}              # node -> its visibility before Easy hid it (Expert puts it back)
var _btns := {}             # label -> Button
var _menu: PopupMenu        # the scene list Open shows
var _menu_paths := {}       # Open's row index -> the scene file it opens (the separator has none)
const OPEN_DRAFTS := 5      # Open: the saved scenes, then "Recent drafts" with the newest this many drafts
var _dummy_was := false   # the target dummy was on when Easy came on (Expert puts it back)
var _more: PopupMenu        # the More menu: the actions that are not on the bar (its item id = index in _more_acts)
var _more_acts: Array = []  # [label, tip, Callable] per More entry
var _snap := {}             # the state at the start of the tour step
var _armed := false         # step 1: a hand was dragged (the drag is not let go yet)
var _moved := false         # step 4: the body changed since the step began
static var start_fresh := false   # a TEST only: start as a fresh install does (no settings file = Easy), not as a test (Expert)
var home: EasyHome          # EASY HOME (scripts/easy_home.gd): the empty scene's picture panel, Easy only
var _saved_cam := {}        # Expert's camera (yaw, pitch, dist, target) when Easy came on: Expert gets exactly this back
const FREE_PAD := 8.0       # px between the free rect and the Easy bar, the strip, or the bottom panel
const FRAME_PAD := 12.0     # px of air the body keeps inside the free rect (the framing's margin)
const FRAME_STEP := 2       # the clip is sampled every 2nd frame: a frame moves a hand a few px, inside FRAME_PAD
const FRAME_SAMPLES := 24   # the most poses frame_clip samples (the click waits for them)


## which mode a settings file asks for. A key decides. No key: a file with sections is an existing user (Expert);
## no file (or an empty one) is a fresh start (Easy). Under a test (testing) and no key: Expert, so the suites keep
## the app they were written for.
static func mode_for(cf: ConfigFile, testing := false) -> bool:
	if cf.has_section_key(CFG, "mode"):
		return String(cf.get_value(CFG, "mode", "expert")) == "easy"
	if testing:
		return false
	return cf.get_sections().is_empty()


## main calls this once the UI is built. --easy / --expert (shots, agents) choose for one run and write nothing
func start(cf: ConfigFile, testing: bool) -> void:
	var args := OS.get_cmdline_user_args()
	var forced := args.has("--easy") or args.has("--expert")
	var want := args.has("--easy") if forced else mode_for(cf, testing and not start_fresh)
	if not testing and not forced and not cf.has_section_key(CFG, "mode"):
		_set_cfg("mode", "easy" if want else "expert")   # the first start writes it down: later tour writes cannot flip it
	set_on(want, false)
	if on and not testing and not args.has("--shot") and not m.onboard.pending and tour_due():
		_tour_when_clear.call_deferred()


## the bar, the tour card, the hidden list: once, from main's _ui (after the panels exist)
func build(root: Control, expert: Array) -> void:
	_expert = expert
	bar = PanelContainer.new()
	bar.name = "easy_bar"
	bar.theme_type_variation = "TopBar"
	bar.anchor_right = 1.0
	bar.offset_bottom = m.TOP_H
	bar.visible = false
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.name = "easy_row"
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	# the bar: 7 buttons at most (More counts). Each More entry is one click after More, so it is reachable in 2.
	var acts := [
		["Library", "Open the object library: weapons, furniture, sports, everyday things, armour and your own models. Click one to place it", func(): m._library_toggle()],
		["Save video", "Render the scene from the camera to a video in your Videos folder (Kine/), with a button to show it", func(): home.save_video()],
		["Play / Stop", "Play the scene from the playhead, or stop it (Space)", m._toggle_play],
		["New scene", "Start an empty scene (it asks first over unsaved work)", _new],
		["Undo", "Take back the last change (Ctrl+Z): a beginner's first need, so it stays on the bar", m._undo],
		["More", "The other things: Key this pose, Pose, Redo, Open, Save scene, Mirror pose, Floor (snap feet)", _more_open],
		["Switch to Expert", "Show every panel and tool again, as before", func(): set_on(false)],
	]
	var more := [
		["Key this pose", "Keep the body's pose as a card on the timeline (Enter)", m._card_add],
		["Pose (drag parts)", "Drag a part on the body to pose it. Click a part first to pick it, or drag it straight away.", _pose],
		["Redo", "Put back what Undo took back (Ctrl+Y)", m._redo],
		["Open", "Open one of your scenes", _open],
		["Copy a video", "Turn a video of one person into an animation: pick the file (mp4, mov, webm, avi, mkv)", func(): home.copy_video()],
		["Save scene", "Save the scene (Ctrl+Shift+S)", m._save_scene],
		["Mirror pose", "The whole body reflected left and right (Shift+M)", m._press.bind(KEY_M, true)],
		["Floor (snap feet)", "Plant the feet that slide over the cards, so they stay on the floor", m._plant_all],
	]
	for a in acts:
		var b := _big(a[0], a[1], a[2])
		row.add_child(b)
		_btns[a[0]] = b
	_more = PopupMenu.new()
	_more.name = "easy_more_menu"
	_more.add_theme_font_size_override("font_size", 18)
	for i in more.size():
		_more.add_item(more[i][0], i)
		_more.set_item_tooltip(i, more[i][1])
	_more.id_pressed.connect(_more_picked)
	bar.add_child(_more)
	_more_acts = more
	_menu = PopupMenu.new()
	_menu.name = "easy_open_menu"
	_menu.index_pressed.connect(func(i: int): if _menu_paths.has(i): m._open_scene_file(_menu_paths[i]))
	bar.add_child(_menu)
	_build_tour_card(root)
	get_viewport().size_changed.connect(_resized)   # EASY CAMERA: a window resize re-frames the clip (frame_clip)
	home = EasyHome.new()   # the empty scene's "What should he do?" panel: a child of Easy, so Expert never shows it
	home.name = "easy_home_node"
	home.m = m
	add_child(home)
	home.build(root)


## one big button: its label wraps in the button (two lines at 7 buttons across a 1280-px window)
func _big(label: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = "easy_" + str(_btns.size() + 1)
	b.set_meta("label", label)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, m.TOP_H - 12)
	var l := Label.new()
	l.name = "label"
	l.text = label
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(l)
	b.pressed.connect(func(): m._step_hint = label; f.call())   # the undo step is named after the button
	return b


func _build_tour_card(root: Control) -> void:
	tour_card = PanelContainer.new()
	tour_card.name = "easy_tour"
	tour_card.visible = false
	tour_card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the card never takes a click meant for the body; its Skip button still does
	tour_card.custom_minimum_size = Vector2(300, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("accent")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(12)
	tour_card.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	tour_card.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	_tour_title = Label.new()
	_tour_title.add_theme_font_size_override("font_size", 17)
	_tour_title.add_theme_color_override("font_color", Tok.c("on_accent"))
	_tour_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_tour_title)
	var skip := Button.new()
	skip.name = "easy_tour_skip"
	skip.text = "Skip"
	skip.focus_mode = Control.FOCUS_NONE
	skip.tooltip_text = "end the tour; it won't show again (Help: show the tour brings it back)"
	skip.pressed.connect(_finish.bind(true))
	h.add_child(skip)
	_tour_text = Label.new()
	_tour_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tour_text.add_theme_font_size_override("font_size", 14)
	_tour_text.add_theme_color_override("font_color", Tok.c("on_accent"))
	v.add_child(_tour_text)
	root.add_child(tour_card)


# ---------------------------------------------------------------- the mode

func set_on(v: bool, save := true) -> void:
	var was := on
	on = v
	if on and not was:
		if m != null:
			_saved_cam = {"yaw": m.yaw, "pitch": m.pitch, "dist": m.dist, "target": m.target}   # Expert's own view, kept for the way back
		for n in _expert:
			if n != null and not _vis.has(n):
				_vis[n] = n.visible
				n.visible = false
		_dummy_was = m != null and m.dummy_on
		if _dummy_was:   # the target dummy stands between the camera and the body, a dark giant over him: Easy puts it away
			m.dummy_on = false
			m._dummy_hits()
	elif was and not on:
		if tour_step >= 0:
			_finish(true, false)
		if not _saved_cam.is_empty() and m != null:   # Expert's camera is exactly what it was before Easy (main._cam places it)
			m.yaw = _saved_cam["yaw"]
			m.pitch = _saved_cam["pitch"]
			m.dist = _saved_cam["dist"]
			m.target = _saved_cam["target"]
			_saved_cam = {}
		for n in _vis:
			if is_instance_valid(n):
				n.visible = _vis[n]
		_vis.clear()
		if _dummy_was and m != null and not m.dummy_on:   # Expert gets its dummy back as it was
			m.dummy_on = true
			m._dummy_hits()
		_dummy_was = false
	if bar != null:
		bar.visible = on
	if on != was and m != null and m.ui_status != null:
		m._sides_apply()   # main's own pieces follow the mode (the side panels stay hidden while Easy is on)
		m._layout_bottom()
		m._fit_rows.call_deferred()
	if save and m != null:
		_set_cfg("mode", "easy" if on else "expert")
		m._say("Easy: 7 big buttons (More has the rest), panels hidden." if on else "Expert: every panel is back.")


func _set_cfg(key: String, v: Variant) -> void:
	if m == null:
		return
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value(CFG, key, v)
	cf.save(m.settings)


# ---------------------------------------------------------------- the camera (Easy's frame)

## the free rect (px): below the Easy bar, or below the strip when it is there (the strip's own height, shown or not), above the
## bottom card panel and the status line. The body is framed inside it (frame_clip); Expert's camera does not use it.
func free_rect() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var top := float(m.TOP_H)
	if home != null and home.strip != null:
		top = maxf(top, 82.0 + home.strip.get_combined_minimum_size().y)   # the strip sits at 82 (under the bar), see easy_home.gd
	top += FREE_PAD
	var bottom := vs.y - float(m.bottom_h) - float(m.LINE_H) - FREE_PAD
	return Rect2(0.0, top, vs.x, maxf(bottom - top, 40.0))


## the camera's offsets for Easy: the look-at point sits at the free rect's centre (mpp = world units per px at the target)
func offsets(vs: Vector2, mpp: float) -> Vector2:
	var c := free_rect().get_center()
	return Vector2((vs.x * 0.5 - c.x) * mpp, (c.y - vs.y * 0.5) * mpp)


## FRAME THE CLIP: the body over the whole clip (every frame, joints, ends and any weapon, each with its radius) is framed
## inside the free rect: the target is the middle of its box, the distance the smallest that keeps every point inside.
## Called when a clip is built and when the window resizes. The playhead's pose is put back after the sampling.
## frame_clip one frame later: the clip's first moving frame is not held up by the sampling (~100 ms on the Run card)
func frame_clip_next() -> void:
	await get_tree().process_frame
	frame_clip()


func frame_clip() -> void:
	if m == null or not on or m.S.cards.is_empty():
		if m != null:
			m._cam()
		return
	var vs := get_viewport().get_visible_rect().size
	var F := free_rect().grow(-FRAME_PAD)
	var fps := float(m.S.fps)
	var pts := []
	var last := int(ceil(m.S.length() * fps))
	# at most FRAME_SAMPLES poses spread over the clip (a pose is ~3.5 ms and the click waits for them: every 2nd frame of a
	# 5 s walk cost ~260 ms, past easyhome's 500 ms click-to-motion bar), the last frame too; easycam checks every 4th frame
	var step := maxi(FRAME_STEP, int(ceil(float(last) / float(FRAME_SAMPLES))))
	var ks := range(0, last + 1, step)
	if ks[-1] != last:
		ks.append(last)
	for k in ks:
		m._ps().apply(m.B, float(k) / fps)
		pts.append_array(Turntable.points(m.B))
	m._ps().apply(m.B, m.playhead)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in pts:
		lo = lo.min(p[0])
		hi = hi.max(p[0])
	var centre := (lo + hi) * 0.5
	var a := 0.6
	var b := 40.0
	for it in 16:   # 40 m / 2^16: under a millimetre (each step runs every point, so the count is the click's cost)
		var mid := (a + b) * 0.5
		if _fits(pts, centre, mid, vs, F):
			b = mid
		else:
			a = mid
	m.target = centre
	m.dist = b
	m._cam()


## every point (with its radius) projects inside F with the camera at centre, distance d (the offsets as _cam sets them)
func _fits(pts: Array, centre: Vector3, d: float, vs: Vector2, F: Rect2) -> bool:
	var cam: Camera3D = m.cam
	var b := Basis.from_euler(Vector3(deg_to_rad(m.pitch), deg_to_rad(m.yaw), 0))
	cam.transform = Transform3D(b, centre + b * Vector3(0, 0, d))
	var mpp := 2.0 * d * tan(deg_to_rad(cam.fov * 0.5)) / vs.y
	var o := offsets(vs, mpp)
	cam.h_offset = o.x
	cam.v_offset = o.y
	for p in pts:
		var c: Vector3 = p[0]
		if cam.is_position_behind(c):
			return false
		var q := cam.unproject_position(c)
		var r := float(p[1]) / mpp
		if q.x - r < F.position.x or q.x + r > F.end.x or q.y - r < F.position.y or q.y + r > F.end.y:
			return false
	return true


func _resized() -> void:
	if on:
		frame_clip.call_deferred()


# ---------------------------------------------------------------- the bar's actions

func _pose() -> void:
	m._say("Drag a part on the body to pose it. Click a part first to pick it, or drag it straight away.")


func _more_open() -> void:
	var at: Rect2 = (_btns["More"] as Control).get_global_rect()
	var vw := get_viewport().get_visible_rect().size.x
	_more.position = Vector2i(int(clampf(at.position.x, 0.0, vw - 280.0)), int(at.end.y))
	_more.popup()


func _more_picked(i: int) -> void:
	var a: Array = _more_acts[i]
	m._step_hint = a[0]   # the undo step is named after the entry, as a bar button's is
	(a[2] as Callable).call()


## a test or the tour: the bar's More button, then the entry with these words (two clicks, as a beginner makes them)
func pick_more(label: String) -> bool:
	for i in _more_acts.size():
		if _more_acts[i][0] == label:
			(_btns["More"] as Button).pressed.emit()
			_more_picked(i)
			return true
	return false


func more_labels() -> Array:
	return _more_acts.map(func(a): return a[0])


func _new() -> void:
	m._new_asked()   # ROADMAP 50: Save / Don't save / Cancel when the open scene has unsaved changes


func _open() -> void:
	m._fill_scene_list()   # the drafts as they are now (Easy's clip of this click is one of them)
	m._show_open_scene()
	_menu.clear()
	_menu_paths.clear()
	for i in m.ui_scenes.item_count:   # the saved scenes, in the list's order (newest first); its group rows and drafts are not here
		var p := String(m.ui_scenes.get_item_metadata(i))
		if not (p.begins_with("#") or m.is_draft_path(p)):
			_open_row(m.ui_scenes.get_item_text(i), p)
	var drafts: Array = m.draft_paths().slice(0, OPEN_DRAFTS)
	if not drafts.is_empty():
		_menu.add_separator("Recent drafts")
		for p in drafts:
			_open_row(String(p).get_file().get_basename().replace("_", " ") + "   (draft)", String(p))
	if _menu_paths.is_empty():
		m._say("No scenes yet: New scene starts one, and Save keeps it.")
		return
	var at: Rect2 = (_btns["More"] as Control).get_global_rect()   # Open is in the More menu: its list drops under More
	_menu.position = Vector2i(at.position + Vector2(0, at.size.y))
	_menu.popup()


func _open_row(text: String, path: String) -> void:
	_menu.add_item(text)
	_menu_paths[_menu.item_count - 1] = path


## the bar's button for a label (Expert's tests and the tour use it)
func button(label: String) -> Button:
	return _btns.get(label)


func labels() -> Array:
	return _btns.keys()


# ---------------------------------------------------------------- the tour

func tour_due() -> bool:
	if m == null:
		return false
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return not cf.get_value(CFG, "easy_tour_done", false)


func _tour_when_clear() -> void:
	await get_tree().process_frame
	while m.ui_recover != null and m.ui_recover.visible:   # the recover offer first, as the old tour waits too
		await m.ui_recover.visibility_changed
	if is_inside_tree() and on and tour_step < 0 and tour_due():
		tour_start()


## Help: show the tour (or the first start). The tour is Easy's: in Expert it switches to Easy first
func tour_start() -> void:
	if not on:
		set_on(true)
	tour_step = -1
	_go(0)


func _go(k: int) -> void:
	if k >= TOUR.size():
		_finish(false)
		return
	tour_step = k
	_armed = false
	_moved = false
	_snap = {"cards": m.S.cards.size(), "playhead": m.playhead, "body": JSON.stringify(m.B.state())}
	_tour_title.text = "Step %d of %d:  %s" % [k + 1, TOUR.size(), TOUR[k][0]]
	_tour_text.text = TOUR[k][1]
	tour_card.visible = true
	tour_card.reset_size()
	set_process(true)
	_place_card.call_deferred()


## the card sits by the thing the step is about: the body for 1, the Key button for 2 and 4, the timeline for 3,
## the Play button for 5. Above the target when it sits low on the window, else below it.
func _place_card() -> void:
	if tour_card == null or not tour_card.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var at: Rect2
	match tour_step:
		0: at = Rect2(vp.x - 20, vp.y * 0.3, 0, 0)   # the body is in the middle: the card sits at its right edge
		1, 3: at = (_btns["More"] as Control).get_global_rect()   # Key this pose is in More
		2: at = m.ui_timeline.get_global_rect()
		_: at = (_btns["Play / Stop"] as Control).get_global_rect()
	var sz := tour_card.get_combined_minimum_size()
	var x := clampf(at.get_center().x - sz.x * 0.5, 8.0, vp.x - sz.x - 8.0)
	var y := at.end.y + 10.0 if at.get_center().y < vp.y * 0.5 else at.position.y - sz.y - 10.0
	tour_card.position = Vector2(x, clampf(y, 8.0, vp.y - sz.y - 8.0))
	tour_card.size = sz


## every frame, while a step waits: the user's real action moves it on
func _process(_dt: float) -> void:
	if tour_step < 0 or m == null:
		set_process(false)
		return
	if JSON.stringify(m.B.state()) != _snap["body"]:
		_moved = true
	match tour_step:
		0:
			if m.dragging == "joint" and m.sel in ["hand_l", "hand_r"]:
				_armed = true
			elif _armed and m.dragging == "":
				_go(1)
		1:
			if m.S.cards.size() > _snap["cards"]:
				_go(2)
		2:
			if absf(m.playhead - float(_snap["playhead"])) > 0.005 and not m.playing:
				_go(3)
		3:
			if m.S.cards.size() > _snap["cards"] and _moved:
				_go(4)
		4:
			if m.playing:
				_finish(false)


## the end (done or skipped): the card goes, and the tour is not due again
func _finish(skipped: bool, save := true) -> void:
	tour_step = -1
	set_process(false)
	if tour_card != null:
		tour_card.visible = false
	if save:
		_set_cfg("easy_tour_done", true)
		m._say("Tour skipped. Help: show the tour brings it back." if skipped else "Tour done: Help: show the tour brings it back.")
