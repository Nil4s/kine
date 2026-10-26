class_name EasyMode
extends Node
## EASY MODE (docs/ROADMAP.md items 3 and 4; beginners are lost in 140+ commands).
## Easy: ONE bar of 7 big labelled buttons (Library, Save video, Play / Stop, Undo, New scene, More, Switch to Expert)
## takes the top strip's place; More opens a menu with the rest (Save this pose as a card, Move his arms and legs, Redo,
## Open a saved scene, Save the scene, Flip left and right, Put his feet on the floor, Copy a video). The side panels, the top tools, the scene header and the play row are HIDDEN (never removed). Expert: every one of them is back exactly as it was.
## The mode is remembered in poser.cfg [look] mode. A fresh config is Easy; an existing config with no mode key is
## Expert, so nothing changes for people who already use the app. A test is Expert unless it says otherwise.
## First-run tour (Easy only, once, skippable, Help: show the tour): five steps, each moved on by the real action.

const CFG := "look"
const TOUR := [
	["Drag a hand", "Press on a hand of the body and drag it. The arm follows, and the pose changes."],
	["Save the pose", "Press + Add pose, at the end of the cards. The body's pose becomes a card on the timeline at the bottom."],
	["Move the playhead", "Drag the playhead (the line on the timeline) to another moment."],
	["Change the pose and save again", "Move a part to a new place, then press + Add pose again."],
	["Press play", "Press Play. The body moves from card to card by itself."],
]

var m: Node                 # main (untyped: the same pattern as Browser)
var on := false             # Easy is showing
var edit_pick := -1         # the card the user clicked on the strip (-1: none); a + Add pose clears it (card_follows_drag)
var tour_step := -1         # -1 = no tour
var bar: PanelContainer
var views: PanelContainer   # VIEW BUTTONS (walk-through round 5, goal 7): Front, Side, Back, Reset view at the right edge, Easy only
var tour_card: PanelContainer
var _tour_title: Label
var _tour_text: Label
var _expert: Array = []     # the nodes Easy hides (main's panels and tools)
var _vis := {}              # node -> its visibility before Easy hid it (Expert puts it back)
var _btns := {}             # label -> Button
var _menu: PopupMenu        # the scene list Open shows
var _menu_paths := {}       # Open's row index -> the scene file it opens (the separator has none)
var _dummy_was := false   # the target dummy was on when Easy came on (Expert puts it back)
var _more: PopupMenu        # the More menu: the actions that are not on the bar (its item id = index in _more_acts)
var _more_acts: Array = []  # [label, tip, Callable] per More entry
var red_note: PanelContainer   # Easy: the one line that says what the red on the body means (shown while a red spot is lit)
const RED_NOTE := "Red = Check found a problem in this part. Click the red part to see the fix."
var _snap := {}             # the state at the start of the tour step
var _armed := false         # step 1: a hand was dragged (the drag is not let go yet)
var _moved := false         # step 4: the body changed since the step began
static var start_fresh := false   # a TEST only: start as a fresh install does (no settings file = Easy), not as a test (Expert)
var scenes: EasyScenes      # MY SCENES (scripts/easy_scenes.gd): the saved scenes and the examples as big tiles, from the bar's My scenes
var home: EasyHome          # EASY HOME (scripts/easy_home.gd): the empty scene's picture panel, Easy only
var sliders: EasySliders    # EASY SIDE SLIDERS (scripts/easy_sliders.gd): a picked body part's sliders at the right, Easy only
var _saved_cam := {}        # Expert's camera (yaw, pitch, dist, target) when Easy came on: Expert gets exactly this back
const EASY_MORE := {"Save this pose as a card": "Saved pose", "Flip left and right": "Flip", "Put his feet on the floor": "Feet on floor", "Copy a video": "Copied video"}   # a More entry's undo name in Easy (its Expert name is the entry's words)
const FREE_PAD := 8.0       # px between the free rect and the Easy bar, the strip, or the bottom panel
const FRAME_PAD := 12.0     # px of air the body keeps inside the free rect (the framing's margin)
const TOUR_W := 300.0       # the tour card's width (px); its text wraps inside it
const PANEL_MARGIN := 12.0  # px between the tour card and the window's edge
const FRAME_STEP := 2       # the clip is sampled every 2nd frame: a frame moves a hand a few px, inside FRAME_PAD
const FRAME_SAMPLES := 24   # the most poses frame_clip samples (the click waits for them)
const FRAME_FILL := 0.8     # Easy: the body's height (head to feet, radii in) as a share of the free rect's height: a beginner sees the move
const FRAME_WIDTH := 0.9    # Easy: the body's widest reach as a share of the free rect's width
const FRAME_MAX := 0.96     # Easy: the clip's TALLEST moment (hands overhead) at most this share of the free height
var _track: Array = []      # Easy follow: the body's centre (Vector3) at each sample of the clip
var _track_ks: Array = []   # the frame each _track entry is at
var _frame_d := -1.0        # the distance frame_clip set for this clip (-1 = none yet)


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
		["Save video", "Save the clip as a video in your Videos folder (Kine), with a button to show it", func(): home.save_video()],
		["Play / Stop", "Play the scene from the playhead, or stop it", m._toggle_play],
		["New scene", "Start an empty scene (it asks first over unsaved work)", _new],
		["My scenes", "Your saved scenes as big pictures, newest first, and the examples: click one to open it and play it", _my_scenes],
		["Undo", "Take back the last change: a beginner's first need, so it stays on the bar", m._undo],
		["More", "The other things: Save this pose as a card, Move his arms and legs, Redo, Open a saved scene, Save the scene, Flip left and right, Put his feet on the floor", _more_open],
		["Switch to Expert", "Show every panel and tool again, as before", func(): set_on(false)],
	]
	var more := [
		["Save this pose as a card", "Keep the body's pose as a card on the timeline", func(): add_pose("Saved pose", false)],
		["Move his arms and legs", "Drag a part on the body to pose it. Click a part first to pick it, or drag it straight away.", _pose],
		["Redo", "Put back what Undo took back", m._redo],
		["Open a saved scene", "Open one of your scenes", _open],
		["Copy a video", "Turn a video of one person into an animation: pick the file (mp4, mov, webm, avi, mkv)", func(): home.copy_video()],
		["Save the scene", "Save the scene", func(): home.save_scene()],
		["Flip left and right", "The whole body reflected left and right", m._press.bind(KEY_M, true)],
		["Put his feet on the floor", "Plant the feet that slide over the cards, so they stay on the floor", m._plant_all],
	]
	for a in acts:
		var b := _big(a[0], a[1], a[2])
		row.add_child(b)
		_btns[a[0]] = b
	for k in ["Play / Stop", "Save video"]:   # STYLE: the screen's main actions take the "main" token (amber in palettes a, b, c)
		_btns[k].theme_type_variation = "Main"
	# REDO, one click after Undo: a narrow button that is there only while something can be put back (easy_home._process
	# shows it and names it "Redo: Faster", as Undo is named). The More entry stays too.
	var rb := _big("Redo", "Put back what Undo took back", m._redo)
	rb.name = "easy_redo"
	rb.custom_minimum_size = Vector2(150, m.TOP_H - 12)
	rb.size_flags_horizontal = Control.SIZE_FILL
	rb.visible = false
	row.add_child(rb)
	row.move_child(rb, (_btns["Undo"] as Control).get_index() + 1)
	_btns["Redo"] = rb
	# RED IS SAID: Check's red spots on the body (main's redspots) get one plain line in Easy, above the mouse strip
	red_note = PanelContainer.new()
	red_note.name = "easy_red_note"
	red_note.visible = false
	red_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rnl := Label.new()
	rnl.text = RED_NOTE
	rnl.custom_minimum_size = Vector2(300, 0)
	rnl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rnl.add_theme_font_size_override("font_size", 15)
	rnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red_note.add_child(rnl)
	root.add_child(red_note)
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
	_build_views(root)
	scenes = EasyScenes.new()   # MY SCENES: its panel is over the bar (added last), hidden until its button is pressed
	scenes.m = m
	scenes.build(root)
	_build_tour_card(root)
	get_viewport().size_changed.connect(_resized)   # EASY CAMERA: a window resize re-frames the clip (frame_clip)
	home = EasyHome.new()   # the empty scene's "What should he do?" panel: a child of Easy, so Expert never shows it
	home.name = "easy_home_node"
	home.m = m
	add_child(home)
	home.build(root)
	sliders = EasySliders.new()   # EASY SIDE SLIDERS: the picked part's panel (its own _process hides it outside Easy)
	sliders.name = "easy_sliders_node"
	sliders.m = m
	add_child(sliders)
	sliders.build(root)


## VIEW BUTTONS: the view keys 1 (front), 2 (side, -90), 4 (back) and HOME, turned smoothly; a small column at the right edge
func _build_views(root: Control) -> void:
	views = PanelContainer.new()
	views.name = "easy_views"
	views.visible = false
	views.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)   # under the bar, at the right: clear of the picker, the strip and the save toast
	views.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	views.grow_vertical = Control.GROW_DIRECTION_END
	views.offset_top = float(m.TOP_H) + 8.0
	views.offset_right = -12.0
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("panel")
	st.set_corner_radius_all(10)
	st.set_content_margin_all(8)
	views.add_theme_stylebox_override("panel", st)
	root.add_child(views)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	views.add_child(col)
	var acts := [
		["easy_view_front", "Front", "the view from the front", func(): m._view(1, true)],
		["easy_view_side", "Side", "the view from the side: the camera turns 90 degrees", func(): m._view(2, true)],
		["easy_view_back", "Back", "the view from the back", func(): m._view(4, true)],
		["easy_view_reset", "Reset view", "the first view: the body from the front, a little from above", func(): m._view_home(true)],
		["easy_body_colour", "His colour", "change his colour: skin, white, grey, blue, red, dark, then skin again (one undo step; the Undo button gives the old one back)", func(): m._body_colour_next()],
	]
	for a in acts:
		var b := Button.new()
		b.name = a[0]
		b.text = a[1]
		b.tooltip_text = a[2]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(120, 40)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(a[3])
		col.add_child(b)


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
	b.pressed.connect(func(): _close_more(); m._step_hint = label; f.call())   # the undo step is named after the button; a bar press closes More
	return b


func _build_tour_card(root: Control) -> void:
	tour_card = PanelContainer.new()
	tour_card.name = "easy_tour"
	tour_card.visible = false
	tour_card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the card never takes a click meant for the body; its Skip button still does
	tour_card.custom_minimum_size = Vector2(TOUR_W, 0)
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
	_tour_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tour_title.custom_minimum_size = Vector2(TOUR_W - 24.0, 0)   # the wrap width: a wrapped label is measured at it, never at 1 px
	_tour_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_tour_title)
	_tour_text = Label.new()
	_tour_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tour_text.add_theme_font_size_override("font_size", 14)
	_tour_text.add_theme_color_override("font_color", Tok.c("on_accent"))
	_tour_text.custom_minimum_size = Vector2(TOUR_W - 24.0, 0)   # its height is measured at the card's width (a 1 px width made the card 1500 px tall)
	v.add_child(_tour_text)
	# SKIP (walk-through item 3): a normal-size button, "Skip tour", in its own row at the card's right (it was a tiny corner word)
	var foot := HBoxContainer.new()
	v.add_child(foot)
	var skip := Button.new()
	skip.name = "easy_tour_skip"
	skip.text = "Skip tour"
	skip.focus_mode = Control.FOCUS_NONE
	skip.tooltip_text = "end the tour; it won't show again (Help: show the tour brings it back)"
	skip.custom_minimum_size = Vector2(130, 40)
	skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	skip.pressed.connect(_finish.bind(true))
	foot.add_child(skip)
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
		_track = []   # Easy's follow stops with Easy
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
	if not on and scenes != null:
		scenes.close_panel()
	if bar != null:
		bar.visible = on
	if views != null:
		views.visible = on
	if on != was and m != null and m.ui_status != null:
		m._sides_apply()   # main's own pieces follow the mode (the side panels stay hidden while Easy is on)
		m._rebuild_cards()   # the card lines follow the mode (a name and a picture in Easy; the number and the timing in Expert)
		m._layout_bottom()
		m._fit_rows.call_deferred()
		if on:
			frame_clip.bind(true).call_deferred()   # the free rect is the Easy panel's now: the body is framed in it again (keep_body: framing moves the camera, never the pose)
	if m != null and m.tag != null:
		m._refresh()   # the body's pick light, name tag, dots and axis names follow the mode now (EASY QUIET in main._refresh), at boot too
	if m != null and m.ui_status != null and m.is_welcome(m.ui_status.text):
		m.ui_status.text = m.welcome_words()   # the teaching strip says the words of the mode it is in (one line in Easy)
		m._status_look()
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
	# the empty scene's "What should he do?" panel sits at the left: the body is framed in the room to its right
	var left := 0.0
	if home != null and home.panel != null and m.S.cards.is_empty():
		left = EasyHome.PANEL_LEFT + home.panel.get_combined_minimum_size().x + FREE_PAD
	return Rect2(left, top, vs.x - left, maxf(bottom - top, 40.0))


## the camera's offsets for Easy: the look-at point sits at the free rect's centre (mpp = world units per px at the target)
## SIDE PANEL UP (easy_sliders.gd): the centre moves to the middle of the free rect left of the panel (its edge less 10 px), so the
## body stays in view beside the panel. The distance is not changed; the offset goes back when the panel shuts.
func offsets(vs: Vector2, mpp: float) -> Vector2:
	var fr := free_rect()
	var c := fr.get_center()
	if sliders != null and sliders.shifted():
		# the Library open at the left too: the body goes between the two panels (left of it the hand slid under the Library)
		var left := fr.position.x
		if m.ui_library != null and m.ui_library.is_visible_in_tree():
			left = maxf(left, m.ui_library.get_global_rect().end.x + 10.0)
		var right := minf(fr.end.x, sliders.left_x() - 10.0)
		c.x = (left + maxf(right, left + 40.0)) * 0.5
	return Vector2((vs.x * 0.5 - c.x) * mpp, (c.y - vs.y * 0.5) * mpp)


## FRAME THE CLIP: the body over the whole clip (every frame, joints, ends and any weapon, each with its radius) is framed
## inside the free rect: the target is the middle of its box, the distance the smallest that keeps every point inside.
## Called when a clip is built and when the window resizes. The playhead's pose is put back after the sampling.
## frame_clip one frame later: the clip's first moving frame is not held up by the sampling (~100 ms on the Run card)
func frame_clip_next(keep_body := false) -> void:
	await get_tree().process_frame
	frame_clip(keep_body)


func frame_clip(keep_body := false) -> void:   # keep_body: the body is put back exactly as it was (a card just added: its pose is the card's)
	if m == null or not on:
		if m != null:
			m._cam()
		return
	var keep: Dictionary = m.B.state() if keep_body else {}
	var vs := get_viewport().get_visible_rect().size
	var fr := free_rect()
	var fps := float(m.S.fps)
	# an empty scene frames the body as it stands (its rest pose): the camera kept the last clip's look-at point otherwise,
	# and the body could sit under the bottom bar (the press on a hand there lands on the bar, not the body)
	var last := 0 if m.S.cards.is_empty() else int(ceil(m.S.length() * fps))
	# at most FRAME_SAMPLES poses spread over the clip (a pose is ~3.5 ms and the click waits for them: every 2nd frame of a
	# 5 s walk cost ~260 ms, past easyhome's 500 ms click-to-motion bar), the last frame too
	var step := maxi(FRAME_STEP, int(ceil(float(last) / float(FRAME_SAMPLES))))
	var ks := range(0, last + 1, step)
	if ks[-1] != last:
		ks.append(last)
	# EASY FOLLOW: each sample gives the body's centre (the middle of its box, radii in) and its height and reach from that centre.
	# The distance is set from the clip's tallest height and widest reach, so the body fills FRAME_FILL of the free rect's height
	# at every frame, and the look-at point follows the centre (follow_tick): a walk that travels stays big and in the free view.
	var centres: Array = []
	var tallest := 0.0
	var heights: Array = []
	var reach := 0.0
	for k in ks:
		m._ps().apply(m.B, float(k) / fps)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var pts := Turntable.points(m.B)
		for p in pts:
			var rr := Vector3.ONE * float(p[1])
			lo = lo.min((p[0] as Vector3) - rr)
			hi = hi.max((p[0] as Vector3) + rr)
		var c := (lo + hi) * 0.5 if lo.x < INF else Vector3.ZERO
		centres.append(c)
		if lo.x < INF:
			tallest = maxf(tallest, hi.y - lo.y)
			heights.append(hi.y - lo.y)
			for p in pts:
				var flat := Vector2((p[0] as Vector3).x - c.x, (p[0] as Vector3).z - c.z)
				reach = maxf(reach, flat.length() + float(p[1]))
	if keep_body:
		m.B.set_state(keep)
	else:
		m._ps().apply(m.B, m.playhead)
	# world units per px at the target: the body's typical height is FRAME_FILL of the free height, its width fits FRAME_WIDTH of the free width
	# The TYPICAL height (the median sample) is FRAME_FILL: a dance with the hands overhead for a beat is framed for the body
	# most of the clip (the tallest moment framed at 80 % left the arms-down body at 67 %), and the tallest moment still fits
	# (FRAME_MAX)
	heights.sort()
	var typical: float = heights[heights.size() / 2] if not heights.is_empty() else tallest
	var mpp := maxf(maxf(typical / (FRAME_FILL * maxf(fr.size.y, 1.0)), tallest / (FRAME_MAX * maxf(fr.size.y, 1.0))), 2.0 * reach / (FRAME_WIDTH * maxf(fr.size.x, 1.0)))
	mpp = maxf(mpp, 1e-4)
	var tan_half: float = tan(deg_to_rad(m.cam.fov * 0.5))
	_frame_d = mpp * vs.y / (2.0 * tan_half)
	_track = centres
	_track_ks = ks
	m.dist = _frame_d
	m.target = _track_at(m.playhead)
	m._cam()


## the look-at point at clip time t: the sampled centres, interpolated between the samples
func _track_at(t: float) -> Vector3:
	if _track.is_empty():
		return m.target
	var f := clampf(t * float(m.S.fps), 0.0, float(_track_ks[-1]))
	var i := 0
	while i + 1 < _track_ks.size() - 1 and float(_track_ks[i + 1]) <= f:
		i += 1
	var a := float(_track_ks[i])
	var b := float(_track_ks[mini(i + 1, _track_ks.size() - 1)])
	var w := clampf((f - a) / maxf(b - a, 1e-6), 0.0, 1.0)
	return (_track[i] as Vector3).lerp(_track[mini(i + 1, _track.size() - 1)], w)


## EASY FOLLOW (main calls it every frame while Easy shows): the look-at point rides the body's centre at the playhead. The
## distance stays the one frame_clip set, so the body keeps its size and the wheel still zooms.
func follow_tick() -> void:
	if m == null or not on or _track.is_empty():
		return
	var c := _body_centre()
	if not c.is_equal_approx(m.target):
		m.target = c
		m._cam()


## the middle of the body's box as it is posed now (every point with its radius): the look-at point of the follow. The
## sampled centres (frame_clip) were 0.77 s apart: a jump's apex and a walk's step were framed 50-110 px off centre
func _body_centre() -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in Turntable.points(m.B):
		var rr := Vector3.ONE * float(p[1])
		lo = lo.min((p[0] as Vector3) - rr)
		hi = hi.max((p[0] as Vector3) + rr)
	return (lo + hi) * 0.5 if lo.x < INF else m.target


## the distance frame_clip set for the clip (-1: no clip framed yet): Reset view uses it in Easy
func frame_dist() -> float:
	return _frame_d


## the look-at point the follow has now (main's target while Easy shows)
func follow_target() -> Vector3:
	return m.target


func _resized() -> void:
	if on:
		frame_clip.bind(true).call_deferred()   # a resize re-frames the body; it never poses it (no undo step for a pose change)


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
	_close_more()         # the menu closes as its item runs (a dialog it opens must not sit under the menu)
	m._step_hint = a[0]   # the undo step is named after the entry, as a bar button's is
	m._step_easy = EASY_MORE.get(a[0], "") if on else ""   # and in Easy by its short name ("Flip", "Saved pose")
	(a[2] as Callable).call()
	m._step_easy = ""


func _close_more() -> void:
	if _more != null:
		_more.hide()


## + ADD POSE (the strip's end button, Easy only) and More's Save this pose as a card: the one way a pose becomes a card.
## strip = the button's press: a pose the card before it already has is refused in plain words (no duplicate card).
## The card goes after the selected card (at the end when none or the last is selected), is selected, is scrolled into view,
## and its undo step is named undo_name (Easy: "Add pose" / "Saved pose").
func add_pose(undo_name := "Add pose", strip := true) -> void:
	if strip and not m.S.cards.is_empty():
		var ref: int = m.sel_card if m.sel_card >= 0 else m.S.cards.size() - 1
		if same_pose(m.S.cards[ref]["pose"], m.B.to_dict()):
			m._say("Move him first, then add the pose.")
			return
	# EASY: a drag followed by + Add pose is ONE undo step: the drag's own step (taken at its press, so it holds the body as it
	# was before the drag) takes the card too. Undo then removes the card and puts the body back; Redo puts both back.
	var merge: bool = on and not m.undo.is_empty() and bool(m.undo[-1].get("drag", false))
	m._step_easy = undo_name if on else ""
	m._undo_merge = merge
	m._card_add()
	m._undo_merge = false
	if merge:
		var d: Dictionary = m.undo[-1]
		d.erase("drag")   # the merged step is no longer a bare drag: the next + Add pose makes its own step
		d["easy"] = undo_name
		d["name"] = undo_name
		m._tree.set_name(m._tree.cur, undo_name)
		m._undo_tips()
		m._history_rows()
	var i: int = m.sel_card
	await m.get_tree().process_frame
	m.ui_card_row.queue_sort()   # after a rebuild the strip's scroll range can stay 0 until the next sort
	await m.get_tree().process_frame
	var pc := m.ui_cards.get_node_or_null("card_%d" % (i + 1)) as Control
	if pc != null:
		m.ui_card_row.ensure_control_visible(pc)


## EDIT A PICKED CARD (walk-through round 5, goal 3): in Easy, a body drag with a card picked on the strip writes the body's pose
## into that card, in place. The drag's own undo step (taken at its press, so it holds the card as it was) takes the change too,
## and is named "Change pose". The card count and the other cards do not move; the pick can change after it and the edit stays.
func card_follows_drag() -> void:
	var i: int = m.sel_card
	if i < 0 or i >= m.S.cards.size() or i != edit_pick or m.undo.is_empty():
		return   # only a card the user clicked (edit_pick): + Add pose's new card is selected but waits for its own pose
	if m.undo.back().get("body") == m.B.state():
		return   # nothing moved: the card keeps its pose
	m.S.cards[i]["pose"] = m.B.to_dict()
	var d: Dictionary = m.undo[-1]
	d.erase("drag")   # the step is no longer a bare drag: a + Add pose after it makes its own step
	d["easy"] = "Change pose"
	d["name"] = "Change pose"
	m._tree.set_name(m._tree.cur, "Change pose")
	m._undo_tips()
	m._history_rows()
	m._rebuild_cards()
	m._say("card %d takes the body's new pose (Undo takes it back)" % (i + 1))


## the strip's button (main's _rebuild_cards puts it after the last card, or in an empty Easy strip with its tip)
func strip_button() -> Button:
	var b: Button = m._button("Add pose", add_pose, "Add a card: the body's pose now, after the selected card. Drag his arms and legs first, then press it")
	b.text = "+ Add pose"
	b.name = "add_pose"
	b.custom_minimum_size = Vector2(m.CARD_W - 8, m.CARD_PIC_H + 16)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 14)
	return b


## the "+ Add pose" button wherever it is: the pinned slot right of the strip (cards), or inside the empty strip with its tip
func add_button() -> Button:
	for box in [m.ui_add_slot, m.ui_cards]:
		if box != null and box.get_node_or_null("add_pose") != null:
			return box.get_node("add_pose") as Button
	return null


## where the tour points for "+ Add pose": the strip's button when it is there, else the More button
func _add_rect() -> Rect2:
	var ab: Control = add_button()
	if ab != null and ab.is_visible_in_tree():
		return ab.get_global_rect()
	return (_btns["More"] as Control).get_global_rect()


## two poses the same: every number within half a thousandth (a pose saved from the body and read back is the same)
static func same_pose(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not same_pose(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for k in a.size():
			if not same_pose(a[k], b[k]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.0005
	return a == b


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


func _my_scenes() -> void:
	scenes.open_panel()


func _open() -> void:
	m._fill_scene_list()   # the drafts as they are now (Easy's clip of this click is one of them)
	m._show_open_scene()
	_menu.clear()
	_menu_paths.clear()
	var seen := {}
	for i in m.ui_scenes.item_count:   # the saved scenes, once each, in the list's order (newest first): the recent row of a scene is the same scene; its group rows and drafts are not here
		var p := String(m.ui_scenes.get_item_metadata(i))
		if p.begins_with("#") or m.is_draft_path(p) or seen.has(p) or m.ui_scenes.is_item_disabled(i):
			continue
		seen[p] = true
		_open_row(p.get_file().get_basename().replace("_", " "), p)
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
	set_process(true)
	_place_card.call_deferred()


## the card sits by the thing the step is about: the body for 1, the Key button for 2 and 4, the timeline for 3,
## the Play button for 5. Above the target when it sits low on the window, else below it. Step 1 starts at the top left
## (the free room under the bar). Any spot that covers the body's screen rect is passed over for the top corners.
func _place_card() -> void:
	if tour_card == null or not tour_card.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var sz := Vector2(TOUR_W, tour_card.get_combined_minimum_size().y)
	var top := float(m.TOP_H) + FREE_PAD
	var at: Rect2
	match tour_step:
		0: at = Rect2(PANEL_MARGIN, top, 0, 0)   # the body is in the middle and its arm reaches the right edge: the top left is free
		1, 3: at = _add_rect()   # + Add pose: the strip's button (More's Save this pose as a card when the strip has none)
		2: at = m.ui_timeline.get_global_rect()
		_: at = (_btns["Play / Stop"] as Control).get_global_rect()
	var cands: Array = []
	if tour_step == 0:
		cands = [Vector2(PANEL_MARGIN, top), Vector2(vp.x - sz.x - PANEL_MARGIN, top)]
	else:
		var x := clampf(at.get_center().x - sz.x * 0.5, PANEL_MARGIN, vp.x - sz.x - PANEL_MARGIN)
		var y := at.end.y + 10.0 if at.get_center().y < vp.y * 0.5 else at.position.y - sz.y - 10.0
		cands = [Vector2(x, y), Vector2(PANEL_MARGIN, top), Vector2(vp.x - sz.x - PANEL_MARGIN, top)]
	var body := _body_rect()
	var pick: Vector2 = cands[-1]
	for c in cands:
		var p: Vector2 = Vector2(clampf(c.x, PANEL_MARGIN, maxf(PANEL_MARGIN, vp.x - sz.x - PANEL_MARGIN)), clampf(c.y, top, maxf(top, vp.y - sz.y - PANEL_MARGIN)))
		if not body.has_area() or not Rect2(p, sz).intersects(body):
			pick = p
			break
	tour_card.position = pick
	tour_card.size = sz


## the body's screen rect (px): every joint, end and weapon point projected; empty when nothing is on screen
func _body_rect() -> Rect2:
	if m == null or m.B == null or m.cam == null:
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in Turntable.points(m.B):
		var v: Vector3 = p[0]
		if m.cam.is_position_behind(v):
			continue
		var s: Vector2 = m.cam.unproject_position(v)
		lo = lo.min(s)
		hi = hi.max(s)
	if lo.x == INF:
		return Rect2()
	return Rect2(lo, hi - lo)


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
