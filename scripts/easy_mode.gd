class_name EasyMode
extends Node
## EASY MODE (docs/ROADMAP.md items 3 and 4; beginners are lost in 140+ commands).
## Easy: ONE bar of 12 big labelled buttons takes the top strip's place; the side panels, the top tools, the scene
## header and the play row are HIDDEN (never removed). Expert: every one of them is back exactly as it was.
## The mode is remembered in poser.cfg [look] mode. A fresh config is Easy; an existing config with no mode key is
## Expert, so nothing changes for people who already use the app. A test is Expert unless it says otherwise.
## First-run tour (Easy only, once, skippable, Help: show the tour): five steps, each moved on by the real action.

const CFG := "look"
const TOUR := [
	["Drag a hand", "Press on a hand of the body and drag it. The arm follows, and the pose changes."],
	["Key the pose", "Press Key this pose. The body's pose becomes a card on the timeline at the bottom."],
	["Move the playhead", "Drag the playhead (the line on the timeline) to another moment."],
	["Change the pose and key again", "Move a part to a new place, then press Key this pose again."],
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
var _menu: PopupMenu
var _snap := {}             # the state at the start of the tour step
var _armed := false         # step 1: a hand was dragged (the drag is not let go yet)
var _moved := false         # step 4: the body changed since the step began


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
	var want := args.has("--easy") if forced else mode_for(cf, testing)
	if not testing and not forced and not cf.has_section_key(CFG, "mode"):
		_set_cfg("mode", "easy" if want else "expert")   # the first start writes it down: later tour writes cannot flip it
	set_on(want, false)
	if on and not testing and not args.has("--shot") and tour_due():
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
	var acts := [
		["Pose (drag parts)", "Drag a part on the body to pose it. Click a part first to pick it, or drag it straight away.", _pose],
		["Key this pose", "Keep the body's pose as a card on the timeline (Enter)", m._card_add],
		["Play / Stop", "Play the scene from the playhead, or stop it (Space)", m._toggle_play],
		["Undo", "Take back the last change (Ctrl+Z)", m._undo],
		["Redo", "Put back what Undo took back (Ctrl+Y)", m._redo],
		["New scene", "Start an empty scene (it asks first over unsaved work)", _new],
		["Open", "Open one of your scenes", _open],
		["Save", "Save the scene (Ctrl+Shift+S)", m._save_scene],
		["Mirror pose", "The whole body reflected left and right (Shift+M)", m._press.bind(KEY_M, true)],
		["Floor (snap feet)", "Plant the feet that slide over the cards, so they stay on the floor", m._plant_all],
		["Export video", "Render the scene from the camera to a video in exports/", func(): m._export_playblast()],
		["Switch to Expert", "Show every panel and tool again, as before", func(): set_on(false)],
	]
	for a in acts:
		var b := _big(a[0], a[1], a[2])
		row.add_child(b)
		_btns[a[0]] = b
	_menu = PopupMenu.new()
	_menu.name = "easy_open_menu"
	_menu.id_pressed.connect(func(i: int): m._scene_picked(i))
	bar.add_child(_menu)
	_build_tour_card(root)


## one big button: its label wraps in the button (two lines at 12 buttons across a 1280-px window)
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
		for n in _expert:
			if n != null and not _vis.has(n):
				_vis[n] = n.visible
				n.visible = false
	elif was and not on:
		if tour_step >= 0:
			_finish(true, false)
		for n in _vis:
			if is_instance_valid(n):
				n.visible = _vis[n]
		_vis.clear()
	if bar != null:
		bar.visible = on
	if on != was and m != null and m.ui_status != null:
		m._sides_apply()   # main's own pieces follow the mode (the side panels stay hidden while Easy is on)
		m._layout_bottom()
		m._fit_rows.call_deferred()
	if save and m != null:
		_set_cfg("mode", "easy" if on else "expert")
		m._say("Easy mode: the 12 buttons, larger. Expert brings every panel back." if on else "Expert mode: every panel and tool is back.")


func _set_cfg(key: String, v: Variant) -> void:
	if m == null:
		return
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value(CFG, key, v)
	cf.save(m.settings)


# ---------------------------------------------------------------- the 12 buttons' actions

func _pose() -> void:
	m._say("Drag a part on the body to pose it. Click a part first to pick it, or drag it straight away.")


func _new() -> void:
	m._new_asked()   # ROADMAP 50: Save / Don't save / Cancel when the open scene has unsaved changes


func _open() -> void:
	if m.ui_scenes.item_count == 0:
		m._say("No scenes yet: New scene starts one, and Save keeps it.")
		return
	_menu.clear()
	for i in m.ui_scenes.item_count:
		_menu.add_item(m.ui_scenes.get_item_text(i), i)
	var at: Rect2 = (_btns["Open"] as Control).get_global_rect()
	_menu.position = Vector2i(at.position + Vector2(0, at.size.y))
	_menu.popup()


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
		1, 3: at = (_btns["Key this pose"] as Control).get_global_rect()
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
