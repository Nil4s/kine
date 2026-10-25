class_name EasyHome
extends Node
## EASY HOME (monkey brain easy): what a beginner sees in Easy mode when the scene is empty. A panel at the left edge,
## beside the body (easy_mode.gd free_rect frames the body in the room to its right),
## "What should he do?", with eight picture cards and one text box ("or type it"). A card builds its clip (the
## templates/ files for walk, run, jump, punch, sit down, wave and the kick (roundhouse.json, baked); TextBlocking for typed words), one undo step, then it plays by itself.
## After that the panel is a strip with buttons: Again, Change it (the panel and its text box come back), and four big ones
## that tweak the clip just built (EasyTweak): Faster, Slower (its timing), Bigger, Smaller (its motion). Save video is on the Easy bar.
## With a clip already there, the picker's "Then:" row says Add after (the default: the cards go after the clip) or Start over (replace).
## Expert never shows it: it is a child of EasyMode and only Easy's bar shows it.
## Under the strip, a second row offers up to three "Then <move>" buttons after the move just made (data/catalog.json via
## Catalog.next_after); a press is the same Add after as the Then row's, one undo step.
## A card the builders cannot make says so in one plain sentence and leaves the scene as it was.

const CARDS := [   # [the word on the card, what it builds (a templates/ name or the words TextBlocking reads), its icon]
	["Walk", "walk", "walk"],
	["Run", "run", "run"],
	["Jump", "jump", "jump"],
	["Punch", "punch", "punch"],
	["Kick", "roundhouse", "kick"],
	["Sit down", "sit_down", "sit_down"],
	["Wave", "wave", "wave"],
	["Fall", "fall", "fall"],
]
const HINT := "or type a move: 'jab then cross'"
const PANEL_LEFT := 12.0       # px between the window's left edge and the home panel
const PANEL_W := 478.0         # the cards' grid (4 x 112 + 3 x 10) and the text box and message under it
## words Kine has no builder for. TextBlocking would read "down" as an overhead strike, so these are refused first
const UNDO_NONE := "Undo (Ctrl+Z): nothing to undo yet"   # the Easy Undo tooltip with nothing to take back (the label stays "Undo")
const NO_MOVE := "Pick a move first: click a picture above, or type one in the box."
const TRY := [3, 4, 6, 0]   # the four most common cards (CARDS indices): Punch, Kick, Wave, Walk. An unknown move offers these when no card word is close to it
const TRY_MIN := 0.3        # a card word counts as close to a typed word at this bigram Dice score (try_pick)
const NOT_YET := ["sit"]   # typed words Kine cannot build yet (sit down, wave and fall are templates now)
const STAND_WORDS := {"stand up": "stand_up"}   # typed words that are a derived template (templates.gd DERIVED): sit down played backwards

var m: Node                    # main (untyped: the same pattern as EasyMode)
const SIT_KINDS := ["chair", "stool", "bench"]   # the props SET's sit takes (main.gd SIT_ON)
var _sit_btn: Button           # "Sit on it": the picked chair, stool or bench seats him (SET's own sit)
var _sit_strip: Button         # the same on the strip: with a clip built the panel is hidden, and a chair placed then needs it too
var _pbar: PanelContainer      # THE PROP BAR (top right, Easy only, shown while the scene has props): the picked prop's Turn left, Turn right, Remove; Next prop cycles the props (the list)
var _pbar_name: Label
var _pbar_turn_l: Button
var _pbar_turn_r: Button
var _pbar_remove: Button
var _pbar_next: Button
var _pbar_size: HBoxContainer      # Bigger | Smaller side by side (one row keeps the column short at 1280x720)
var _pbar_bigger: Button
var _pbar_smaller: Button
var _pbar_colour: Button
var _pbar_hand: VBoxContainer      # "In his hand: the sword" + Drop it, at the top of the bar while he holds a weapon (one undo step: the hand is empty)
var _pbar_hand_name: Label
var _pbar_drop: Button
var panel: PanelContainer      # the full panel: the picture cards, the text box, the message
var strip: PanelContainer      # the strip after a clip is built: Again, Change it, Save video
var _edit: LineEdit
var _msg: Label
var _close: Button
var _built := false            # a clip was built from here: the strip shows once the scene has cards
var _open := false             # Change it (or a failed build): the full panel, whatever the scene holds
var _t0 := -1                  # msec at the last click; -1 = nothing being timed
var last_ms := -1              # click -> the first frame the clip plays, msec (the test reads it; -1 = none yet)
var last_build_ms := -1        # the builder alone (the build of the last card or line), msec: reported, not hidden
var video_root := ""           # a TEST's folder (user://...) for Save video; "" = the user's Videos folder (Kine/)
var last_video := {}          # the last Easy save: the playblast's result ({dir, frames, mp4, ffmpeg}); {} = none, or refused
var _toast: PanelContainer
var _toast_text: Label
var _toast_show: Button       # "Open folder": hidden when the message has no file (the empty-scene hint)
var _toast_file := ""         # what Show the file opens: the .mp4 (its folder is shown with it)
var _toast_at := []           # [cards, undo steps] when the saved-video message came up: it goes once the clip changes
var _toast_left := 0.0        # seconds a saved-video message stays up (SAVED_TOAST_S); any next action takes it down sooner
const SAVED_TOAST_S := 8.0
var _names: Array = []        # the clip's move words, for the saved file's name: [undo steps after it, words, starts over]
var _vid_busy := false        # COPY A VIDEO: an import from a video is running (the tracker, then the fit)
var _vid_before := ""         # the scene path when the copy began: a new path when it lands
var _vid_cancel := false      # the fit's own Cancel was pressed
var _vid_refused := false     # a second copy was refused while this one runs: the bar's line says "Still copying the first video" (a refusal alone was overwritten each frame)
var _vid_landed := false      # Add after: the copy's cards are in the open scene (_land_added); the next tick finishes it
var _copy_ask: ConfirmationDialog   # the unsaved open scene's question before a copy: Replace / Add after / Cancel
var _copy_path := ""          # the video the question is about ("" = no question up)
var _copy_box: PanelContainer # COPY PROGRESS (walk-through friction 6: no time left): Easy's bar for a copy, under the Easy bar; shown only while it runs
var _copy_bar: ProgressBar    # the copy's whole progress: the read is the first half, the fit the second
var _copy_left: Label         # "about N s left": shown once COPY_LEFT_MIN % is done (the estimate is the elapsed time scaled to the rest)
var _vid_t0 := 0              # msec when the copy began (the time-left estimate)
const COPY_LEFT_MIN := 10.0   # percent done before the time-left line shows (before it the estimate is a guess)
var _vid_said := ""           # the say line's opening words for the landed clip ("Copied clip.mp4" / "Made \"swing...\"")
var _gen_on := false          # MAKE IT WITH AI VIDEO: main's gen_move (scripts/gen_move.gd) is making the clip
var _gen_words := ""          # the typed words Kine could not build: the button under the message makes them as a video
var _make_btn: Button
var _try_row: HBoxContainer    # "Or try:" and four card words: a typed move Kine cannot build offers moves it can
var _try_btns: Array = []      # one button per card (CARDS order); the refusal shows the four try_pick chose, in that order
var _ai_no: Label             # shown instead of the button when the AI video maker is not set up here
var _cancel_btn: Button
var _clip_word := "the move"   # the clip's name in the say line of a tweak ("the punch now takes 0.8 s")
var _take_n := 0              # MAKE IT WITH AI VIDEO: the take in flight, 1 or 2 (0 = none; a copied video is not a take)
var _take_seed := 1           # the seed of the take in flight: take 2 is take 1's seed + 1
var _takes: Array = []        # this run's takes: {video, pose}; a discarded take's files are removed (_drop_takes)
var _then_add := true         # the picker's "Then:" choice: true = Add after (the cards go after the clip), false = Start over
var _then_box: HBoxContainer  # the "Then:" row: shown only when the scene has cards (an empty scene has nothing to add after)
var _then_add_btn: Button
var _then_start_btn: Button
var _next_row: HBoxContainer  # the strip's second row: up to three "Then <move>" buttons after the move just made (Catalog.next_after)
var _next_btns: Array = []    # the three buttons of _next_row (eh_next_0 .. eh_next_2)
var _next_list: Array = []    # the catalog entries those buttons offer, in order (the press adds that move after the clip)
var _hist: Array = []         # [undo depth, move id] for each move built or added here: the last one is the move at the scene's end
var _row_key := ""            # the ids the row shows now: the row is redrawn only when they change
var _scrub_row: HBoxContainer # THE SCRUB (strip's last row): the slider over the clip's length, and its time beside it
var _scrub: HSlider           # eh_scrub: dragging it stops play and poses the body at that time (as the timeline's scrub does)
var _scrub_time: Label       # eh_scrub_time: "1.2 s / 4.0 s"
var _scrub_ticks: Control    # eh_scrub_ticks: a child of the slider; a tick at each strike card's contact (drawn inside the slider's rect)
var _tick_key: Array = []    # [scene, its times() array, marker count] the ticks were built for
var _tick_list: Array = []   # [{"t": contact time s, "label": "Punch lands", "card": index}], rebuilt with the scrub
var _scrub_sync := false      # true while _process moves the slider to the playhead (that move is not a drag)
var _help_on := false          # the panel shows the help text in place of the picture cards (Help, or the strip's Help)
var _help_lbl: Label
var _help_tour: Button
var _grid: GridContainer
var _row_h := -1.0            # the strip's height when the camera last framed the clip (a row that grows it reframes)
const HELP_TEXT := "Click a picture, or type a move and press Enter ('jab then cross' is two strikes). Then: Add after puts the next move after the clip.\nAfter a clip: Again plays it. Faster, Slower, Bigger and Smaller tweak it. Change it types another move.\nThe bar: Library adds objects. Save video makes a video file."
const HELP_Q := ["how do i", "how do you", "how do we", "how to", "how can i", "how can you", "how would i", "how does", "what can", "help"]   # a typed question: answered with help, not "doesn't know"
const JOIN_S := 0.5           # ADD AFTER: the first added card is reached this many seconds after the clip's end (the join)


func build(root: Control) -> void:
	panel = PanelContainer.new()
	panel.name = "easy_home"
	panel.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)   # at the left edge; _process centres it between the top bar and the welcome line
	panel.offset_left = PANEL_LEFT
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_END
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("panel")
	st.set_corner_radius_all(10)
	st.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", st)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title := _label("What should he do?", 26, "text")
	title.name = "eh_title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var help_btn := Button.new()   # the beginner's way to ask what Easy can do (walk-through round 5: there was no help in Easy)
	help_btn.name = "eh_help"
	help_btn.text = "Help"
	help_btn.focus_mode = Control.FOCUS_NONE
	help_btn.tooltip_text = "what Easy can do, and the tour"
	help_btn.custom_minimum_size = Vector2(90, 40)
	help_btn.add_theme_font_size_override("font_size", 18)
	help_btn.pressed.connect(func(): _help_on = not _help_on; _msg.text = "")
	head.add_child(help_btn)
	_help_lbl = _label(HELP_TEXT, 15, "text")
	_help_lbl.name = "eh_help_text"
	_help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_lbl.custom_minimum_size = Vector2(PANEL_W, 0)
	_help_lbl.visible = false
	v.add_child(_help_lbl)
	_help_tour = Button.new()
	_help_tour.name = "eh_help_tour"
	_help_tour.text = "Show the tour"
	_help_tour.focus_mode = Control.FOCUS_NONE
	_help_tour.tooltip_text = "the five-step tour, each step moved on by doing it (Help: show the tour)"
	_help_tour.visible = false
	_help_tour.pressed.connect(func(): m.easy.tour_start())
	v.add_child(_help_tour)
	_then_box = HBoxContainer.new()
	_then_box.name = "eh_then"
	_then_box.add_theme_constant_override("separation", 8)
	v.add_child(_then_box)
	_then_box.add_child(_label("Then:", 18, "text"))
	var then_group := ButtonGroup.new()
	_then_add_btn = _then_button("eh_then_add", "Add after", "keep the clip and add this move after it (one undo step)", then_group)
	_then_add_btn.toggled.connect(func(on: bool): if on: _then_add = true)
	_then_box.add_child(_then_add_btn)
	_then_start_btn = _then_button("eh_then_start", "Start over", "replace the clip with this move (one undo step)", then_group)
	_then_start_btn.toggled.connect(func(on: bool): if on: _then_add = false)
	_then_box.add_child(_then_start_btn)
	_then_add_btn.button_pressed = true
	var grid := GridContainer.new()
	grid.name = "eh_cards"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	_grid = grid
	for i in CARDS.size():
		grid.add_child(_card_button(i))
	_sit_btn = Button.new()
	_sit_btn.name = "eh_sit"
	_sit_btn.text = "Sit on it"
	_sit_btn.focus_mode = Control.FOCUS_NONE
	_sit_btn.tooltip_text = "seat him on the chair, stool or bench you picked (one undo step)"
	_sit_btn.visible = false
	_sit_btn.pressed.connect(sit_on_chair)
	v.add_child(_sit_btn)
	_edit = LineEdit.new()
	_edit.name = "eh_text"
	_edit.placeholder_text = HINT
	_edit.select_all_on_focus = true   # a click into the box selects what is there: a new move replaces it (Windows search, Blender fields)
	_edit.custom_minimum_size = Vector2(PANEL_W - 160.0, 0)
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_submitted.connect(func(t: String): _words(t))
	_edit.text_changed.connect(func(_t: String): _drop_saved_toast())   # typing is an action: a saved-video message goes
	var ask_row := HBoxContainer.new()   # the two other ways to make a move, side by side: type it, or copy it from a video
	ask_row.name = "eh_ask_row"          # (From a video on its own row made the panel overlap the welcome / status lines at 1280x720)
	ask_row.add_theme_constant_override("separation", 8)
	v.add_child(ask_row)
	ask_row.add_child(_edit)
	_msg = _label("", 15, "text")
	_msg.name = "eh_msg"
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(PANEL_W, 0)
	v.add_child(_msg)
	_make_btn = Button.new()
	_make_btn.name = "eh_make_ai"
	_make_btn.text = "Make it with AI video (about %d minutes)" % EasyTake.TAKE_MINUTES   # the fast setting: ~150 s to make a 5 s clip (RESULTS.txt, 2026-10-24)
	_make_btn.focus_mode = Control.FOCUS_NONE
	_make_btn.tooltip_text = AI_WHY   # what it does and how long: the button's tooltip (the two lines under the box stay short)
	_make_btn.visible = false
	_make_btn.pressed.connect(make_ai)
	_try_row = HBoxContainer.new()
	_try_row.name = "eh_try"
	_try_row.add_theme_constant_override("separation", 6)
	_try_row.add_child(_label("Or try:", 15, "text"))
	for i in range(CARDS.size()):   # one button per card, hidden until a refusal picks it (_try_show)
		var tb := Button.new()
		tb.name = "eh_try_%s" % String(CARDS[i][0]).to_lower()
		tb.text = String(CARDS[i][0])
		tb.focus_mode = Control.FOCUS_NONE
		tb.tooltip_text = "build %s and play it (one undo step)" % String(CARDS[i][0]).to_lower()
		tb.visible = false
		tb.pressed.connect(card.bind(i))
		_try_row.add_child(tb)
		_try_btns.append(tb)
	_try_row.visible = false
	v.add_child(_try_row)
	var fv := Button.new()   # FROM A VIDEO on Easy's own panel (video walk-through round 6, goal 1): the same action as More > Copy a video
	fv.name = "eh_from_video"
	fv.text = "From a video"
	fv.focus_mode = Control.FOCUS_NONE
	fv.tooltip_text = "turn a video of one person into a move: pick the file (the same as More > Copy a video)"
	fv.add_theme_font_size_override("font_size", 18)
	fv.pressed.connect(copy_video)
	fv.custom_minimum_size = Vector2(150, 0)
	ask_row.add_child(fv)
	v.add_child(_make_btn)   # under the Or try row: the instant moves first, the 3-minute AI take after (walk-through round 4)
	_ai_no = _label(AI_NO, 15, "warn")
	_ai_no.name = "eh_ai_no"
	_ai_no.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ai_no.custom_minimum_size = Vector2(PANEL_W, 0)
	_ai_no.visible = false
	v.add_child(_ai_no)
	_cancel_btn = Button.new()
	_cancel_btn.name = "eh_gen_cancel"
	_cancel_btn.text = "Cancel"
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	_cancel_btn.tooltip_text = "stop it; the scene stays exactly as it is"
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(cancel_run)
	v.add_child(_cancel_btn)
	_close = Button.new()
	_close.name = "eh_close"
	_close.text = "Close"
	_close.focus_mode = Control.FOCUS_NONE
	_close.tooltip_text = "back to the strip: the clip stays"
	_close.pressed.connect(_close_panel)
	v.add_child(_close)

	strip = PanelContainer.new()
	strip.name = "easy_home_strip"
	strip.visible = false
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	strip.offset_top = 82.0   # under the Easy bar (main's TOP_H is 74)
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.add_theme_stylebox_override("panel", st)
	root.add_child(strip)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	strip.add_child(sv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	sv.add_child(row)
	_next_row = HBoxContainer.new()
	_next_row.name = "eh_next"
	_next_row.add_theme_constant_override("separation", 8)
	_next_row.visible = false
	sv.add_child(_next_row)
	for i in 3:
		var nb := _strip_button("eh_next_%d" % i, "", "", _next_pressed.bind(i), Vector2(170, 44), 20)
		nb.visible = false
		_next_row.add_child(nb)
		_next_btns.append(nb)
	row.add_child(_strip_button("eh_again", "Again", "play the clip from its start", _play, Vector2(150, 56), 22))   # one size for the six
	row.add_child(_strip_button("eh_change", "Change it", "type another move in the box", _change, Vector2(150, 56), 22))
	row.add_child(_strip_button("eh_help_strip", "Help", "what Easy can do, and the tour", _open_help, Vector2(110, 56), 22))
	for t in [["eh_faster", "Faster", "the clip's timing x 0.8 (one undo step)", "faster"], ["eh_slower", "Slower", "the clip's timing x 1.25 (one undo step)", "slower"],
			["eh_bigger", "Bigger", "the motion 20 % further from the rest pose (one undo step)", "bigger"], ["eh_smaller", "Smaller", "the motion 20 % less from the rest pose (one undo step)", "smaller"]]:
		row.add_child(_strip_button(t[0], t[1], t[2], tweak.bind(t[3]), Vector2(150, 56), 22))
	_sit_strip = _strip_button("eh_sit_strip", "Sit on the chair", "seat him on the chair, stool or bench after the clip (one undo step; the sit comes after the last card)", sit_on_chair, Vector2(190, 56), 22)
	_sit_strip.visible = false
	_next_row.add_child(_sit_strip)   # with the Then buttons (it goes after the clip too): on the first row it pushed the strip past 1280 px
	# the second row: the copy's own tools (video walk-through round 6): From a video, Cut start / Cut end, Smoother
	var fix := HBoxContainer.new()
	fix.name = "eh_fix"
	fix.add_theme_constant_override("separation", 8)
	sv.add_child(fix)
	# MOVES (walk-through round 9, friction 1): the move cards are hidden once a clip is built; "Change it" was the only way back, and
	# it said nothing about cards. This one says what it shows. Same action as Change it (the picker opens over the clip, or shuts)
	fix.add_child(_strip_button("eh_moves", "Moves", "show the move cards (Walk, Jump, Punch...) to add after the clip, and the box to type a move", _change, Vector2(130, 56), 22))
	fix.add_child(_strip_button("eh_from_video_strip", "From a video", "turn a video of one person into a move: pick the file (the same as More > Copy a video)", copy_video, Vector2(170, 56), 22))
	fix.add_child(_strip_button("eh_cut_start", "Cut start", "drop the cards before the picked card: the clip starts there (one undo step)", trim.bind(true), Vector2(150, 56), 22))
	fix.add_child(_strip_button("eh_cut_end", "Cut end", "drop the cards after the picked card: the clip ends there (one undo step)", trim.bind(false), Vector2(150, 56), 22))
	fix.add_child(_strip_button("eh_smoother", "Smoother", "smooth the motion one step: each pose blends with its neighbours (one undo step)", smooth, Vector2(170, 56), 22))
	# THE SCRUB (walk-through: "no scrubber in Easy"): the third row, shown with a clip built; drag to pick the moment
	_scrub_row = HBoxContainer.new()
	_scrub_row.name = "eh_scrub_row"
	_scrub_row.add_theme_constant_override("separation", 12)
	_scrub_row.visible = false
	sv.add_child(_scrub_row)
	_scrub = HSlider.new()
	_scrub.name = "eh_scrub"
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.0
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.custom_minimum_size = Vector2(520, 32)   # a big grab area: 32 px tall
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.tooltip_text = "drag to pick a moment of the clip: he stops and stands at that moment"
	var track := StyleBoxFlat.new()   # the whole track drawn (the default unfilled part matched the panel: the knob looked at the end)
	track.bg_color = Tok.c("field").lightened(0.25)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = Tok.c("accent")
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	_scrub.add_theme_stylebox_override("slider", track)
	_scrub.add_theme_stylebox_override("grabber_area", fill)
	_scrub.add_theme_stylebox_override("grabber_area_highlight", fill)
	_scrub.value_changed.connect(_scrub_moved)
	_scrub_row.add_child(_scrub)
	_scrub_ticks = Control.new()   # THE HIT MARKS (beginner round 8, friction 7): the contact of each punch or kick, on the slider
	_scrub_ticks.name = "eh_scrub_ticks"
	_scrub_ticks.mouse_filter = Control.MOUSE_FILTER_PASS   # a click off a tick goes on to the slider (a drag)
	_scrub_ticks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrub_ticks.tooltip_text = _scrub.tooltip_text
	_scrub_ticks.draw.connect(_scrub_ticks_draw)
	_scrub_ticks.gui_input.connect(_scrub_ticks_input)
	_scrub.add_child(_scrub_ticks)
	_scrub.resized.connect(_scrub_ticks.queue_redraw)
	_scrub_time = _label("0.0 s / 0.0 s", 20, "text")
	_scrub_time.name = "eh_scrub_time"
	_scrub_time.custom_minimum_size.x = 170
	_scrub_row.add_child(_scrub_time)
	# no Save video here: the Easy bar has it (two buttons with one label confused the monkey test's beginner)
	_pbar = PanelContainer.new()
	_pbar.name = "easy_prop_bar"
	_pbar.visible = false
	_pbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pbar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pbar.add_theme_stylebox_override("panel", st)
	root.add_child(_pbar)
	# COPY PROGRESS: the bar and its time-left line, under main's import bar (its Cancel is the copy's one: one Cancel on screen)
	_copy_box = PanelContainer.new()
	_copy_box.name = "eh_copy_box"
	_copy_box.visible = false
	_copy_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_copy_box.offset_top = float(82 + 84)   # under main's top import bar (its panel is TOP_H + 14 high 70): the two stack, neither covers the other
	_copy_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_copy_box.add_theme_stylebox_override("panel", st)
	root.add_child(_copy_box)
	var cbv := VBoxContainer.new()
	cbv.add_theme_constant_override("separation", 6)
	_copy_box.add_child(cbv)
	_copy_bar = ProgressBar.new()
	_copy_bar.name = "eh_copy_bar"
	_copy_bar.min_value = 0.0
	_copy_bar.max_value = 100.0
	_copy_bar.show_percentage = true
	_copy_bar.custom_minimum_size = Vector2(360, 28)
	_copy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbv.add_child(_copy_bar)
	_copy_left = _label("", 15, "text")
	_copy_left.name = "eh_copy_left"
	_copy_left.visible = false
	cbv.add_child(_copy_left)
	var pr := VBoxContainer.new()   # a column under Front / Side / Back: a row across the view covered his hips at 1280x720
	pr.add_theme_constant_override("separation", 6)
	_pbar.add_child(pr)
	_pbar_hand = VBoxContainer.new()
	_pbar_hand.name = "eh_hand_row"
	_pbar_hand.add_theme_constant_override("separation", 6)
	pr.add_child(_pbar_hand)
	_pbar_hand_name = _label("", 18, "text")
	_pbar_hand_name.name = "eh_hand_name"
	_pbar_hand_name.custom_minimum_size.x = 150
	_pbar_hand_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pbar_hand.add_child(_pbar_hand_name)
	_pbar_drop = _strip_button("eh_hand_drop", "Drop it", "put the weapon down: he stops holding it (one undo step; Ctrl+Z puts it back in his hand)", _hand_drop, Vector2(150, 40), 18)
	_pbar_hand.add_child(_pbar_drop)
	_pbar_name = _label("", 18, "text")
	_pbar_name.name = "eh_prop_name"
	_pbar_name.custom_minimum_size.x = 150
	_pbar_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pr.add_child(_pbar_name)
	_pbar_turn_l = _strip_button("eh_prop_turn_l", "Turn left", "turn the picked prop 15 degrees to the left (one undo step)", func(): m._prop_turn(-15.0), Vector2(150, 40), 18)
	pr.add_child(_pbar_turn_l)
	_pbar_turn_r = _strip_button("eh_prop_turn_r", "Turn right", "turn the picked prop 15 degrees to the right (one undo step)", func(): m._prop_turn(15.0), Vector2(150, 40), 18)
	pr.add_child(_pbar_turn_r)
	_pbar_size = HBoxContainer.new()
	_pbar_size.name = "eh_prop_size_row"
	_pbar_size.add_theme_constant_override("separation", 6)
	pr.add_child(_pbar_size)
	_pbar_bigger = _strip_button("eh_prop_bigger", "Grow", "make the picked object 15 % bigger (one undo step; Ctrl+Z gives it back)", func(): m._prop_resize(1.15), Vector2(73, 40), 17)
	_pbar_size.add_child(_pbar_bigger)
	_pbar_smaller = _strip_button("eh_prop_smaller", "Shrink", "make the picked object 15 % smaller (one undo step; Ctrl+Z gives it back)", func(): m._prop_resize(1.0 / 1.15), Vector2(73, 40), 17)
	_pbar_size.add_child(_pbar_smaller)
	_pbar_colour = _strip_button("eh_prop_colour", "Colour it", "change the picked prop's colour: blue, red, green, yellow, white, black, then grey (one undo step)", func(): m._prop_colour(), Vector2(150, 40), 18)
	pr.add_child(_pbar_colour)
	_pbar_remove = _strip_button("eh_prop_remove", "Remove", "take the picked prop out of the scene (Ctrl+Z puts it back)", func(): m._prop_del(), Vector2(150, 40), 18)
	pr.add_child(_pbar_remove)
	_pbar_next = _strip_button("eh_prop_next", "Next object", "pick the next object in the scene (in the order they were added)", _prop_next, Vector2(150, 40), 18)
	pr.add_child(_pbar_next)
	_toast = PanelContainer.new()
	_toast.name = "easy_toast"
	_toast.visible = false
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)   # the right of the view, above the status line (_process keeps it there)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_right = -12.0
	var tst := StyleBoxFlat.new()
	tst.bg_color = Tok.c("accent")
	tst.set_corner_radius_all(10)
	tst.set_content_margin_all(18)
	_toast.add_theme_stylebox_override("panel", tst)
	root.add_child(_toast)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 12)
	_toast.add_child(tv)
	_toast_text = _label("", 26, "on_accent")
	_toast_text.name = "eh_toast_text"
	tv.add_child(_toast_text)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 10)
	tv.add_child(tr)
	_toast_show = _toast_button("eh_toast_show", "Open folder", "open the folder with your video in it", func(): OS.shell_show_in_file_manager(_toast_file))
	tr.add_child(_toast_show)
	tr.add_child(_toast_button("eh_toast_ok", "Got it", "hide this message", func(): _toast.visible = false))


## the panel back to the strip (a clip is there); the text box's words stay for the next Change it
func _close_panel() -> void:
	_open = false
	_help_on = false
	_msg.text = ""


## Esc takes the open panel back to the strip when a clip is built (the other Esc uses are untouched)
func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo or (ev as InputEventKey).keycode != KEY_ESCAPE:
		return
	if _open and _clip_kept() and panel != null and panel.visible:
		_close_panel()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if m == null or panel == null:
		return
	_strip_clear_views()
	var on: bool = m.easy.on
	var empty: bool = m.S.cards.is_empty()
	var pb: Button = m.easy.button("Play / Stop")
	if pb != null:   # the button says what a click does now (the walk-through found "Play / Stop" gave no state)
		(pb.get_node("label") as Label).text = "Stop" if m.playing else "Play"   # the words are the child Label (Button.text drew over them)
	var ub: Button = m.easy.button("Undo") if on else null   # Expert runs none of this
	if ub != null:   # UNDO SAYS WHAT IT TAKES BACK, IN THE TOOLTIP: the label stays "Undo" (a beginner finds it each step); the tooltip reads "Undo: Walk"
		var ut: String = "Undo: " + m.easy_name(m.undo[-1]) if not m.undo.is_empty() else UNDO_NONE
		var ul: Label = ub.get_node_or_null("label")   # the bar's words are this child Label (easy_mode._big), not the Button's own text
		if ul != null and ul.text != "Undo":
			ul.text = "Undo"
		if ub.tooltip_text != ut:
			ub.tooltip_text = ut
	var rb: Button = m.easy.button("Redo")   # REDO: one click after Undo, only while something can be put back; named as Undo is ("Redo: Faster")
	rb.visible = on and not m.redo.is_empty()
	if rb.visible:
		var rl: Label = rb.get_node_or_null("label")
		var rt: String = "Redo: " + m.easy_name(m.redo[-1])
		if rl != null and rl.text != "Redo":
			rl.text = "Redo"
		if rb.tooltip_text != rt:
			rb.tooltip_text = rt
	var note: PanelContainer = m.easy.red_note
	var red_on: bool = on and not m.redspots.last.is_empty()   # a red spot is lit on the body at the playhead
	note.visible = red_on
	if red_on and m.ui_mouse != null:   # the line sits just above the mouse strip, at its left
		note.global_position = m.ui_mouse.global_position + Vector2(0, -note.size.y - 6)
	var lib: bool = m.ui_library != null and m.ui_library.visible   # the open library sits where the panel's left half is: one at a time
	panel.visible = on and (empty or _open or _gen_on) and not (lib and not _gen_on) and not _copying()
	if panel.visible:   # centred between the top bar and the welcome line (a short window must not run the picker into the line)
		var vs := panel.get_viewport().get_visible_rect().size
		var top := float(m.TOP_H) + 12.0
		var low := ObjectLibrary.low_edge(vs, float(m.bottom_h), float(m.LINE_H))
		panel.reset_size()
		panel.position = Vector2(PANEL_LEFT, maxf(top, top + (low - top - panel.size.y) * 0.5))
	# the toast sits above the welcome line (which runs the width of the view), so it never covers the line, the status or the strip
	_toast.offset_bottom = -(float(m.bottom_h) + float(m.LINE_H) + float(MouseHint.H) + 14.0)
	_copy_box.visible = on and _copying()   # the copy's bar (the strip's place while a copy runs is the bar's)
	strip.visible = on and not (empty or _open or _gen_on or _copying()) and _built and not lib   # the open library covers the strip's place too: one at a time
	_refresh_next()
	if not on:
		_toast.visible = false
	elif _toast.visible and _toast_file != "":   # a saved-video message is about THAT clip: a new scene, an edit or the save question takes it down
		_toast_left -= dt   # and it goes by itself after its few seconds (a camera turn or a look at the help is no action here)
		var asking: bool = m.ui_save_ask != null and m.ui_save_ask.visible
		var helping: bool = m.ui_help != null and m.ui_help.visible
		if asking or helping or _toast_left <= 0.0 or m.S.cards.size() != int(_toast_at[0]) or m.undo.size() != int(_toast_at[1]):
			_toast.visible = false
	_close.visible = not empty and not _gen_on
	_grid.visible = not _help_on   # the help text takes the cards' place while it is on
	_help_lbl.visible = _help_on
	_help_tour.visible = _help_on
	_then_box.visible = not empty
	var typed_gap: bool = _gen_words != "" and not _gen_on   # a typed line Kine cannot build
	var ai_ok: bool = typed_gap and m.gen_move.available()
	_make_btn.visible = ai_ok
	_sit_btn.visible = sit_ready() and not _help_on   # a chair, stool or bench is picked: he can sit on it
	_prop_bar_update()
	_refresh_sit_strip()
	_scrub_show()
	_try_row.visible = typed_gap and not _help_on   # the same moves as the cards, one click each
	_ai_no.visible = typed_gap and not ai_ok   # no maker here: say so, no button that would fail
	_cancel_btn.visible = _gen_on or (not _copying() and (m._imp_busy() or m._video_pid >= 0))   # the generator, or the tracker's / the fit's own Cancel (a copy keeps the bar's one)
	if _t0 >= 0 and m.playing and m.playhead > 0.0:   # the first frame in which the clip moves
		last_ms = Time.get_ticks_msec() - _t0
		_t0 = -1
	if _gen_on:
		_gen_tick(dt)
	if _vid_busy:
		_video_tick()


## THE PROP BAR: shown in Easy while the scene has props. With a prop picked (click it in the view, or Next prop) it names it and
## shows Turn left, Turn right and Remove; with none picked it offers Next prop only. Under the Front / Side / Back buttons, at the right.
func _prop_bar_update() -> void:
	var n: int = m.S.props.size()
	var lib: bool = m.ui_library != null and m.ui_library.visible
	var held: bool = m.B.wep_on   # a weapon in his hand: the bar's top row names it and offers Drop it, with or without props
	_pbar.visible = m.easy.on and (n > 0 or held) and not lib and not _gen_on and not _copying()
	if not _pbar.visible:
		return
	_pbar_hand.visible = held
	if held:
		_pbar_hand_name.text = "In his hand: the %s" % _held_name()
	var i: int = m.sel_prop
	var have: bool = i >= 0 and i < n
	_pbar_name.visible = n > 0
	_pbar_name.text = ("Picked: the %s" % m._prop_name(i)) if have else "Click an object to pick it. Then Remove takes it out."
	_pbar_turn_l.visible = have
	_pbar_turn_r.visible = have
	_pbar_size.visible = have
	_pbar_colour.visible = have
	_pbar_remove.visible = have
	_pbar_next.visible = n > 0
	_pbar.reset_size()
	var vs := _pbar.get_viewport().get_visible_rect().size
	var views: Control = m.easy.views
	var top := float(m.TOP_H) + 8.0
	if views != null and views.visible:
		top = views.get_global_rect().end.y + 8.0
	if strip.visible:   # the strip (its scrub row too) is taller than the views' place: the bar sits under it, never under the strip
		top = maxf(top, strip.get_global_rect().end.y + 8.0)
	_pbar.position = Vector2(vs.x - _pbar.size.x - 12.0, top)


## THE STRIP CLEAR OF THE VIEW BUTTONS: centred under the bar, but at 1280x720 its 7-button row reached x 1168 and covered
## Front / Side / Back (x 1135+). It moves left until its right edge is 8 px short of the view buttons (never past x 12).
func _strip_clear_views() -> void:
	if strip == null or not strip.visible:
		return
	var vs := strip.get_viewport().get_visible_rect().size
	var x := (vs.x - strip.size.x) * 0.5
	var views: Control = m.easy.views
	if views != null and views.is_visible_in_tree():
		x = minf(x, views.get_global_rect().position.x - 8.0 - strip.size.x)
	x = maxf(12.0, x)
	if absf(strip.position.x - x) > 0.5:
		strip.position.x = x


## the held weapon's plain name ("sword", "2 daggers"): the picker's row for what the body holds, lower-cased
func _held_name() -> String:
	return String(m.WEAPONS[m.weapon_shown()][0]).to_lower()


## DROP IT: the held weapon leaves the hand AND the clip. The weapon is part of each card's pose (Scene.put reads it back at
## every frame), so emptying only the hand gave it back at the next play. One undo step (main's _do snapshot holds the
## cards and the body): Ctrl+Z puts it back in the hand and in the cards.
func _hand_drop() -> void:
	_drop_saved_toast()
	if not m.B.wep_on:
		return
	var what := _held_name()
	m._step_easy = "Drop" if m.easy.on else ""   # the undo step's Easy name (main._push_undo takes it)
	m._do(func() -> void:
		m._bat_remove()
		for c in m.S.cards:
			var d: Dictionary = c.get("pose", {})
			if d.has("weapon"):
				d["weapon"] = {}
			d.erase("weapon2"))
	m._say_plain("He put the %s down. Undo takes it back." % what)


## Next prop: the picked prop moves to the next one in the scene (the first one when none is picked)
func _prop_next() -> void:
	var n: int = m.S.props.size()
	if n == 0:
		return
	m._prop_select((int(m.sel_prop) + 1) % n)


## what is on screen: "panel", "strip" or "hidden" (the test reads it)
func shown() -> String:
	if panel == null:
		return "hidden"
	return "panel" if panel.visible else ("strip" if strip.visible else "hidden")


## a card's click: build its clip, then play it
func card(i: int) -> void:
	_drop_saved_toast()
	_t0 = Time.get_ticks_msec()
	last_ms = -1
	_go(String(CARDS[i][1]), String(CARDS[i][0]))


## SAVE VIDEO (Easy's strip and the bar's Export video): the playblast (PNG frames, and an .mp4 when ffmpeg is found) in the
## user's Videos folder, Kine/ (video_folder). A toast names the file and offers Show the file. Expert's export is not changed.
func save_video() -> void:
	last_video = {}
	if m.S.cards.size() < 2:   # nothing to film yet: say what to do, render nothing
		_show_toast(NO_MOVE, "")
		m._say_plain(NO_MOVE)
		return
	var r: Dictionary = await m._save_video_playblast(video_folder(), clip_name())   # piped to ffmpeg, with the progress line and Cancel
	last_video = r
	if r.is_empty():   # refused or cancelled: the playblast's status line says why
		return
	if String(r["mp4"]) != "":
		_show_toast("Your video is saved: %s
%s" % [String(r["mp4"]).get_file(), folder_line(String(r["mp4"]))], String(r["mp4"]))
		m._say_plain("Your video is saved: %s" % String(r["mp4"]).get_file())   # the status line says it short
	else:
		_show_toast("Could not make the video here. Your frames are kept: Open folder opens them.", String(r["dir"]))
		m._say_plain("Could not make the video here. Your frames are kept.")


## where Easy's video goes: a test's folder if one is set, else Videos/Kine, else Documents/Kine
func video_folder() -> String:
	if video_root != "":
		return video_root
	for base in [OS.get_system_dir(OS.SYSTEM_DIR_MOVIES), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)]:
		var dir := String(base).path_join("Kine")
		if String(base) != "" and (DirAccess.dir_exists_absolute(dir) or DirAccess.make_dir_recursive_absolute(dir) == OK):
			return dir
	return "user://Kine"


## the folder a saved video is in, for the toast's second line: the home folder shortened and the folders joined with " > "
## ("Videos > Kine > run_68_20261024_114713"). A path outside the home folder keeps its last two folders. home_dir: a test's home
func folder_line(mp4: String, home_dir := "") -> String:
	var p := mp4
	if p.begins_with("user://") or p.begins_with("res://"):
		p = ProjectSettings.globalize_path(p)
	p = p.replace("\\", "/").get_base_dir()
	var h := (home_dir if home_dir != "" else OS.get_environment("USERPROFILE")).replace("\\", "/").trim_suffix("/")
	if h != "" and p.to_lower().begins_with(h.to_lower() + "/"):
		return " > ".join(p.substr(h.length() + 1).split("/", false))
	var parts := p.split("/", false)
	return " > ".join(parts.slice(maxi(0, parts.size() - 2)))


## THE CLIP'S NAME (the saved file's): the move words of the clip as it is now, joined "walk then sit down" -> "walk_then_sit_down".
## A card or a typed line that adds a move adds its words; Start over and a copied clip begin again; Undo takes its words back.
## "" = no clip here (main names the file after the scene then)
## Easy's Save the scene: a clip never saved yet (no file, or a work copy in scenes/_wip) is named after the whole clip, as its video is
## ("walk_then_stand_up_then_wave", not its first card's "walk"); a scene the user saved or opened keeps its own name
func save_scene() -> void:
	var cn := clip_name()
	if cn != "" and (String(m.scene_path) == "" or String(m.scene_path).contains("/_wip/")):
		m.ui_scene_name.text = cn
	m._save_scene()


func clip_name() -> String:
	if m.S.cards.is_empty():
		return ""
	var words := []
	for e in _names:
		if int(e[0]) > m.undo.size() + m.undo_dropped:
			break
		if bool(e[2]):
			words = []
		words.append(String(e[1]))
	return " then ".join(PackedStringArray(words)).replace(" ", "_")


## a move's words went into the clip: an undo step at depth m.undo.size() (after the step) replaces the words above it
func _note_name(words: String, starts_over: bool) -> void:
	var d: int = m.undo.size() + m.undo_dropped   # not undo.size() alone: at the 60-step cap every move had depth 60 and wiped the words before it
	var kept := []
	for e in _names:
		if int(e[0]) < d:
			kept.append(e)
	if starts_over:
		kept = []
	kept.append([d, words.strip_edges().to_lower(), starts_over])
	_names = kept


func _show_toast(text: String, file: String) -> void:
	m._toast_clear()   # the saved-video message replaces the last Easy toast (it stayed up across it)
	_toast_text.text = text
	_toast_file = file
	_toast_show.visible = file != ""
	_toast.visible = true
	_toast_at = [m.S.cards.size(), m.undo.size()]
	_toast_left = SAVED_TOAST_S


## the saved-video message goes at the next action (a card, a typed line, a tweak, Again, Change it, a copy)
func _drop_saved_toast() -> void:
	if _toast.visible and _toast_file != "":
		_toast.visible = false


func _toast_button(nm: String, text: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(200, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(f)
	return b


## THE NEXT MOVES (Easy, the strip's second row): up to three "Then <move>" buttons after the move just made, from
## Catalog.next_after. A press is _go's Add after for that move (one undo step, named after the move, the same path as the
## "Add after" choice). Hidden in Expert, with an empty scene, and after a copied clip or a clip that is no catalog move.
func _current_move() -> String:
	var depth: int = m.undo.size()
	for i in range(_hist.size() - 1, -1, -1):
		if int(_hist[i][0]) <= depth:   # Undo back past a move's step: the move before it is the last one again
			return String(_hist[i][1])
	return ""


func _refresh_next() -> void:
	if _next_row == null or m == null:
		return
	var shown_on: bool = m.easy.on and _built and not m.S.cards.is_empty()
	var id := _current_move() if shown_on else ""
	var list: Array = Catalog.next_after(id, 3) if id != "" else []
	var key := ""
	for e in list:
		key += String(e["id"]) + ","
	if key != _row_key:
		_row_key = key
		_next_list = list
		for i in _next_btns.size():
			var b: Button = _next_btns[i]
			b.visible = i < list.size()
			if i < list.size():
				var w := String(list[i]["words"]).to_lower()
				b.name = "eh_next_%d" % i
				b.text = "Then " + w
				var fw := b.get_theme_font("font", "Button")   # the button grows to its words: "Then sword swing" is not cut at the edge
				b.custom_minimum_size.x = maxf(170.0, fw.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 2.0 * b.get_theme_stylebox("normal").get_minimum_size().x + 8.0)
				b.tooltip_text = "add %s after %s (one undo step)" % [w, _clip_word]
		_next_row.visible = not list.is_empty()
	var h: float = strip.get_combined_minimum_size().y
	if h != _row_h:   # the row changed the strip's height: the body is framed under the strip again
		_row_h = h
		if shown_on and m.S.cards.size() > 0:
			m.easy.frame_clip_next()


## THE SCRUB: the slider's row is shown while a clip is built (the strip shows it); while the clip plays or the playhead
## moves, the slider follows it. Its value moves only from the playhead here (_scrub_sync), so only a real drag scrubs.
func _scrub_show() -> void:
	_scrub_row.visible = m.easy.on and not m.S.cards.is_empty()
	if not _scrub_row.visible:
		return
	var len: float = maxf(m._ps().length(), 0.01)
	var t: float = clampf(m.playhead, 0.0, len)
	_scrub_sync = true
	if not is_equal_approx(_scrub.max_value, len):
		_scrub.max_value = len
	_scrub.value = t
	_scrub_sync = false
	_scrub_time.text = "%.1f s / %.1f s" % [t, len]
	_scrub_ticks_build()


## THE HIT MARKS: each strike card's contact time (its "hit" marker, else the card's arrival: BeatFight.contacts) is a tick
## on the slider. Rebuilt with the scrub, so a changed clip moves its ticks.
func _scrub_ticks_build() -> void:
	var S: Scene = m.S
	var ts: Array = S.times()
	# _scrub_show runs every frame: rebuild only when the clip changed (times() hands back the same memo array until a card's
	# pose or timing changes) or its markers did
	var key := [S, ts, S.markers.size()]
	if not _tick_key.is_empty() and is_same(_tick_key[0], key[0]) and is_same(_tick_key[1], key[1]) and _tick_key[2] == key[2]:
		return
	_tick_key = key
	_tick_list.clear()
	for i in BeatFight.contacts(S):
		var t: float = float(ts[i][1])
		for mk in S.markers:
			if String(mk["kind"]) == "hit" and float(mk["t"]) >= float(ts[i][0]) - 0.001 and float(mk["t"]) <= float(ts[i][2]) + 0.001:
				t = float(mk["t"])
				break
		var word := String(S.cards[i].get("from", "")).split("|")[0]   # the move's tag: "punch|<serial>", "kick" (the Kick card)
		var nm := "Kick" if word in ["kick", "roundhouse"] else ("Hit" if word == "" else word.capitalize())
		_tick_list.append({"t": t, "label": "%s lands" % nm, "card": i})
	_scrub_ticks.queue_redraw()


## the slider's x for a time (the grabber's centre runs from half a grabber in from each end)
func _scrub_tick_x(t: float) -> float:
	var gw := 16.0
	var ic := _scrub.get_theme_icon("grabber")
	if ic != null:
		gw = float(ic.get_width())
	var span := _scrub.max_value - _scrub.min_value
	var f := 0.0 if span <= 0.0 else clampf((t - _scrub.min_value) / span, 0.0, 1.0)
	return gw * 0.5 + f * maxf(_scrub.size.x - gw, 0.0)


func _scrub_ticks_draw() -> void:
	var col := Tok.c("text")
	for tk in _tick_list:
		var x := _scrub_tick_x(float(tk["t"]))
		_scrub_ticks.draw_line(Vector2(x, 0.0), Vector2(x, 12.0), col, 2.0)
		_scrub_ticks.draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, 0.0), Vector2(x + 4.0, 0.0), Vector2(x, 6.0)]), col)


## the tick under x (within 7 px), or -1
func _scrub_tick_at(x: float) -> int:
	for k in _tick_list.size():
		if absf(_scrub_tick_x(float(_tick_list[k]["t"])) - x) <= 7.0:
			return k
	return -1


## a click on a tick puts the playhead there and poses the body (the drag's own path: _scrub_moved); elsewhere the slider takes it
func _scrub_ticks_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _scrub_tick_at(ev.position.x)
		_scrub_ticks.tooltip_text = ("%s at %.1f s: click to go there" % [_tick_list[h]["label"], float(_tick_list[h]["t"])]) if h >= 0 else _scrub.tooltip_text
		return
	if not (ev is InputEventMouseButton) or not ev.pressed or ev.button_index != MOUSE_BUTTON_LEFT:
		return
	var k := _scrub_tick_at(ev.position.x)
	if k < 0:
		return
	_scrub_ticks.accept_event()
	_scrub_moved(float(_tick_list[k]["t"]))


## the slider moved by a drag: the clip stops and the body poses at that time (the timeline's scrub, in the same order)
func _scrub_moved(v: float) -> void:
	if _scrub_sync or m == null:
		return
	m.playing = false
	m.playhead = v
	m._ps().apply(m.B, m.playhead)
	m._audio_scrub()
	m._refresh()
	_scrub_show()


## a "Then <move>" button: the move is added after the clip, as Add after does
func _next_pressed(i: int) -> void:
	_drop_saved_toast()
	if i >= _next_list.size():
		return
	var e: Dictionary = _next_list[i]
	_t0 = Time.get_ticks_msec()
	last_ms = -1
	_go(String(e["id"]), String(e["words"]), false, true)


## the text box: the same build as a card, named by what was typed
## SIT ON IT (walk-through round 5, goal 4): the picked chair, stool or bench, else the first one in the scene. -1 = none
func _sit_index() -> int:
	var i: int = m.sel_prop
	if i >= 0 and i < m.S.props.size() and String(m.S.props[i]["kind"]) in SIT_KINDS:
		return i
	for j in m.S.props.size():
		if String(m.S.props[j]["kind"]) in SIT_KINDS:
			return j
	return -1


## the button shows when the picked prop is a chair, stool or bench
func sit_ready() -> bool:
	var i: int = m.sel_prop
	return i >= 0 and i < m.S.props.size() and String(m.S.props[i]["kind"]) in SIT_KINDS


## the strip's "Sit on the chair" shows with a clip built and a chair, stool or bench in the scene (the picked one, else the first)
func _refresh_sit_strip() -> void:
	var t := _sit_index()
	_sit_strip.visible = t >= 0
	if t >= 0:
		_sit_strip.text = "Sit on the %s" % String(m.S.props[t]["kind"])


## SIT ON IT: SET's own sit (main._prop_sit: a card that puts him on the seat) on the picked chair, then the clip bookkeeping
## a card build does: the strip shows, the clip plays, the camera frames it. One undo step (main._prop_sit pushes it).
## Nothing picked: the chair _sit_index names is picked first; with a clip, the sit goes after its last card
func sit_on_chair() -> void:
	var t := _sit_index()
	if t < 0:
		m._say_plain("Pick a chair, a stool or a bench first: click it in the view, or add one with Library")
		return
	if not sit_ready():
		m._prop_select(t)
	if m.S.cards.size() > 0:
		m.sel_card = m.S.cards.size() - 1
	var was: int = m.S.cards.size()
	var go := _walk_to_sit(t)
	var walked := not (go["cards"] as Array).is_empty()   # a clip that ends away from the chair: the walk to its front, then the sit (one undo step)
	if String(go["why"]) != "":
		m._say_plain("%s; the sit is placed at the chair" % String(go["why"]))
	if (go["cards"] as Array).is_empty():
		m._prop_sit()
	else:
		m._walk_sit_add(go["cards"])
	_note_name("sit on the %s" % m._prop_name(m.sel_prop), was == 0)   # the saved video is named after it too ("walk_then_sit_on_the_chair")
	_built = true
	_open = false
	_gen_words = ""
	_msg.text = ""
	if was == 0:
		_hist.clear()
	_hist.append([m.undo.size(), "sit_down"])   # the catalog's sit: its Then row offers Stand up first (goes_after)
	_clip_word = "the clip"
	_refresh_next()
	m._layout_bottom()
	_play()
	m._say_plain(("He walks to the %s and sits on it. Again plays it; Undo takes it back." if walked else "He sits on the %s. Again plays it; Undo takes it back.") % m._prop_name(m.sel_prop))
	m.easy.frame_clip_next()


## WALK TO THE CHAIR (round 8, goal 1): the clip's end is walked to the stand point in front of the chair (Rise.fwd_of /
## Rise.seat_of: STAND_FWD ahead of the seat, facing away from it), by PathWalk's walk, then Rise.sit_down's run backs him onto the
## seat. Returns {"cards": [...]} (the walk then the sit, names as the sit's), or {"cards": [], "why": "..."} when no walk is
## needed (the body already stands there) or the walk is refused (why: the walk's own words; the sit is then placed alone).
func _walk_to_sit(t: int) -> Dictionary:
	var none := {"cards": [], "why": ""}
	if m.S.cards.is_empty():
		return none
	var p: Dictionary = m.S.props[t]
	var seat := Rise.seat_of(p)
	var fwd := Rise.fwd_of(p)
	var stand := Vector3(seat.x, 0.0, seat.z) + fwd * Rise.STAND_FWD
	var keep: Dictionary = m.B.state()
	m._ps().apply(m.B, m.S.length())
	var pel: Vector3 = m.B.P["pelvis"]
	m.B.set_state(keep)
	var at_end := Vector3(pel.x, 0.0, pel.z)
	if at_end.distance_to(stand) < 0.15:
		return none
	var d := (stand - at_end).normalized()
	# PathWalk's stand card puts its hips HIP_BACK behind its first point: the first point is set so the hips start where the clip ends
	var r: Dictionary = PathWalk.build([at_end + d * PathWalk.HIP_BACK, stand], 1.3)
	if not bool(r["ok"]):
		return {"cards": [], "why": "the walk to the chair is refused (%s)" % String(r["why"])}
	var walk: Array = (r["scene"] as Dictionary)["cards"]
	var rise: Dictionary = Rise.sit_down(m.B, p)
	m.B.set_state(keep)
	var kind: String = m._prop_name(t)
	var cards: Array = walk.duplicate()
	for c in rise["cards"]:
		var cc: Dictionary = c.duplicate()
		cc["name"] = "sit on the %s: %s" % [kind, String(c["name"])]
		cards.append(cc)
	return {"cards": cards, "why": ""}


## typed "sit", "sit down", "sit on the chair" (no "then", no comma) with a chair, stool or bench in the scene: he sits on it.
## No such prop: false, and the words go to the builder as before
func _sit_typed(t: String) -> bool:
	var low := t.to_lower()
	if low.contains(",") or low.contains(";") or low.contains(" then "):
		return false
	var ws := low.replace(".", " ").replace("!", " ").split(" ", false)
	if not ws.has("sit"):
		return false
	var i := _sit_index()
	if i < 0:
		return false
	m._prop_select(i)
	sit_on_chair()
	return true


func _words(text: String) -> void:
	_drop_saved_toast()
	var t := text.strip_edges()
	if t == "":
		_fail("Type a move first, such as 'jab then cross' or 'roundhouse', or click a picture.")
		return
	if _is_help_question(t):   # "how do I make him jump": the answer is help, not "doesn't know"
		_ask_help(t)
		return
	if _sit_typed(t):   # "sit", "sit down", "sit on the chair" with a chair in the scene: he sits on it
		return
	_t0 = Time.get_ticks_msec()
	last_ms = -1
	_go(t, "Typed: " + t, true)


## a typed question about how to use Easy ("how do I ...", "how to ...", "help", "?")
func _is_help_question(t: String) -> bool:
	var low := t.to_lower().strip_edges()
	if low == "?" or low.begins_with("?") or low.ends_with("?"):
		return true
	for q in HELP_Q:
		if low == q or low.begins_with(q + " "):
			return true
	return false


## the card word a question names first ("how do i make him run and jump" -> "run"), or "" when none is named
func _move_in(t: String) -> String:
	var low := " " + t.to_lower().replace("?", " ").replace(",", " ").replace(".", " ") + " "
	var best := ""
	var at := 1 << 30
	for c in CARDS:
		var w := String(c[0]).to_lower()
		var i := low.find(" " + w + " ")
		if i >= 0 and i < at:
			at = i
			best = w
	return best


## the answer to a typed question: the move it names (typed the way the box takes it), else the help in one line
func _ask_help(t: String) -> void:
	var w := _move_in(t)
	_edit.text = ""   # the question is used: the next typing starts clean (the box kept old words in round 5)
	if w != "":
		_msg.text = "Type '%s' in the box and press Enter, or click its picture." % w
	else:
		_msg.text = "Type a move in the box and press Enter, such as 'jump' or 'jab then cross'. Or click a picture. Help (top right) says more."
	_msg.add_theme_color_override("font_color", Tok.c("text"))
	_open = true
	_help_on = false
	_t0 = -1


## the strip's Help: the panel comes back with the help text
func _open_help() -> void:
	_open = true
	_help_on = true
	_msg.text = ""


func _go(what: String, label: String, typed := false, force_add := false) -> void:
	if _gen_on:
		m._say_plain(GEN_BUSY)
		return
	var t := Time.get_ticks_msec()
	var add: bool = m.easy.on and (_then_add or force_add) and not m.S.cards.is_empty()   # force_add: a "Then <move>" button (the same Add after)   # Easy's "Then: Add after" with a clip in the scene: the cards go after it (Expert's cards still replace)
	var prev := _clip_word
	var err := _build(what, label, what if typed else label, add)
	last_build_ms = Time.get_ticks_msec() - t
	if err != "":
		_gen_words = what if typed else ""   # a typed line Kine cannot build: the AI video button makes it
		if typed:
			_try_show(what)
			_edit.select_all.call_deferred()   # the refused words stay in the box, selected: the next keystroke replaces them, not glues to them
		_fail(err, err.begins_with("Kine doesn't know"))
		return
	_built = true
	_open = false
	_gen_words = ""
	_msg.text = ""
	_edit.text = ""   # a built move uses the box's words: the next typing starts clean (walk-through round 5)
	_note_name(what if typed else label, not add)
	_clip_word = "the clip" if add else ("the typed move" if typed else "the " + label.to_lower())
	var nm := what.strip_edges().to_lower()
	if not add:
		_hist.clear()
	_hist.append([m.undo.size(), nm if String(Catalog.by_id(nm).get("kind", "")) == "move" else ""])   # the move just made: its "Then" buttons come from the catalog
	_refresh_next()
	m._layout_bottom()   # the bottom panel has its clip rows now: the free rect is the real one
	_play()
	var new_word := "'%s'" % what if typed else "the " + label.to_lower()
	var tail := (" " + _ball_line) if _ball_line != "" else ""
	if add:   # the say line says both moves in plain words; it still opens "Made the wave" (the card's name)
		m._say_plain("Made %s, added after %s. Again plays the whole clip; Undo takes it back.%s" % [new_word, prev, tail])
	else:   # the say line names the clip just built (it kept the last clip's words: "Faster: the walk now takes..." after a typed wave)
		m._say_plain("Made %s. Again plays it; Change it types another move.%s" % [new_word, tail])
	m.easy.frame_clip_next()  # EASY CAMERA: framed in the free rect under the bar / strip, one frame AFTER the clip starts (the click-to-motion bar)


## COPY A VIDEO (Easy's More): a video of one person -> the Expert import (main._import_video: the tracker, then the fit: the
## same pipeline, not a second one). One undo step (the scene before the copy: main._import_land pushes it). The status line
## says the progress in one plain sentence; the import's own bar (with its Cancel: during the tracking it stops the tracker, during
## the fit the fit) is shown as it always is.
## The clip plays at once and the camera frames it, as a card does. A video with no person, or one that cannot be read, is
## one sentence saying why and what to try.
const VIDEO_TYPES := "*.mp4, *.mov, *.webm, *.avi, *.mkv ; videos"
const NO_PERSON := "Couldn't find a person in this video. Try one where the whole body is in view."
const NO_READER := "The video reader would not start on this computer, so this video cannot be read."


## MAKE IT WITH AI VIDEO (the button under a typed line Kine cannot build): the words -> main's gen_move (the same local
## ComfyUI clip as Expert's "Video: make a move from words"), then the copy's landing (main._import_video: one undo step,
## the clip plays, the camera frames it). Cancel stops the generator and the scene stays as it was.
const GEN_NOT_RUNNING := "The AI video maker is not running on this computer, so this move can't be made. Try one of the cards."
const GEN_SHORT := "Say the move in a few more words, such as 'swings a sledgehammer down onto the ground'."
const GEN_BUSY := "A video is already being made or copied: wait for it, or press Cancel."
const AI_WHY := "Makes a short video of a person doing it on this computer, then copies the move. Takes about 3 minutes."
const AI_NO := "AI video isn't set up on this computer."   # shown in place of the button when the maker is not on this computer
const UNCLEAR := "The video was unclear; try different words."   # both takes came out bad with a person found
const BARELY := "The AI video barely moved. Try other words, like 'throws a fast punch'."   # the second take is still for most of its clip (EasyTake.frozen_fraction)


## ONE RETAKE (EasyTake): a take the tracker reads as bad (no person in half its frames, a score under 0.5, or still for over half
## its clip) is made once more with the next seed; the good take is imported, and a second bad one imports nothing and says why. Two takes at most.
func make_ai() -> void:
	if _gen_words == "":
		return
	if not m.gen_move.available():
		_fail(AI_NO)
		return
	if _gen_on or _vid_busy or m._imp_busy() or m._video_pid >= 0 or m.gen_move.busy():
		m._say_plain(GEN_BUSY)
		return
	if _gen_words.length() < 4:
		_fail(GEN_SHORT)
		return
	m.gen_move.python = m.video_python
	_take_n = 1
	_take_seed = randi_range(1, 99998)
	_takes = []
	m.video_gate = _take_gate   # every take's tracker output comes through the gate (main._video_poll)
	_start_take()   # no Python / the maker's script did not start: the same plain sentence, nothing kept


## one take: the generator starts with _take_seed. false = it did not start (the abort has said why)
func _start_take() -> bool:
	if m.gen_move.start(_gen_words, 5.0, _take_seed, EasyTake.FAST_STEPS, EasyTake.FAST_WIDTH, EasyTake.FAST_HEIGHT) != "":
		_take_abort(GEN_NOT_RUNNING)
		return false
	_takes.append({"video": String(m.gen_move.out), "pose": ""})
	_gen_on = true
	_open = true
	m.gen_easy = true   # main's _gen_poll stays out: this home polls the run, says it and lands it
	_msg.text = ""
	m._say_plain(_gen_line())
	return true


func _gen_line() -> String:
	var s := int(m.gen_move.t)
	var clock := "%d:%02d" % [int(s / 60.0), s % 60]
	if _take_n == 2:
		return "That video came out unclear. Making another one (about %d more minutes)... %s" % [EasyTake.TAKE_MINUTES, clock]
	return "Making the video… %s" % clock


## every frame while the generator runs: the progress on the say line; when it is over, the clip lands like a copied video
func _gen_tick(dt: float) -> void:
	var r: String = m.gen_move.poll(dt)
	if r == "":
		m._say_plain(_gen_line())
		return
	_gen_on = false
	m.gen_easy = false
	if r != "done":
		_take_abort(GEN_NOT_RUNNING)
		return
	_vid_busy = true
	_vid_cancel = false
	_vid_before = String(m.scene_path)
	_vid_said = "Made \"%s\"" % _gen_words
	_t0 = -1
	m._land_undo = "Make it with AI video"
	m._say_plain("Reading your video: 0 %")
	m._import_video(m.gen_move.out)   # the tracker; when it exits, _take_gate judges the take
	if m._video_pid < 0 and not m._imp_busy():
		_take_abort(NO_READER)


## main's video_gate: the take's tracker output is judged (EasyTake). Good: the import goes on. Bad and the first: the retake
## starts now (false: main stops here). Bad and the second: nothing is imported, and the plain sentence says why.
func _take_gate(pose: String) -> bool:
	if _take_n == 0:
		return true
	var v := EasyTake.judge(pose)
	_takes[_takes.size() - 1]["pose"] = pose
	if not bool(v["bad"]):
		_drop_takes(true)   # the other take's files go; this one's stay (its import is the scene)
		_takes = []
		_take_n = 0
		m.video_gate = Callable()
		return true
	if _take_n == 1:
		_take_n = 2
		_take_seed += 1
		_vid_busy = false
		m._land_undo = ""
		_start_take()   # says the retake line itself
		return false
	var why := NO_PERSON if float(v["found"]) < EasyTake.BAD_FOUND else (BARELY if float(v["frozen"]) > EasyTake.BAD_FROZEN else UNCLEAR)
	_take_abort(why)
	return false


## the run is over with no import: every take's files go, the gate is cleared, and the sentence says why
func _take_abort(sentence: String) -> void:
	_take_stop()
	m.gen_easy = false
	_gen_on = false
	_fail(sentence)


## removes the takes' files: all of them, or all but the last (the one kept). A take's pose has its .progress file beside it
func _drop_takes(keep_last: bool) -> void:
	var n: int = maxi(_takes.size() - 1 if keep_last else _takes.size(), 0)
	for i in n:
		var t: Dictionary = _takes[i]
		var files: Array = [String(t["video"])]
		if String(t["pose"]) != "":
			files.append(String(t["pose"]))
			files.append(String(t["pose"]).get_basename() + ".progress")
		for f in files:
			if f != "" and FileAccess.file_exists(f):
				DirAccess.remove_absolute(f)
	_takes = _takes.slice(n)


## a run that stops (Cancel, or every take bad): the takes' files go and the gate is cleared (the say line is the caller's)
func _take_stop() -> void:
	_drop_takes(false)
	_take_n = 0
	m.video_gate = Callable()
	_vid_busy = false
	m._land_undo = ""


## Cancel: the generator is stopped (its python process killed) and nothing is changed; during the tracker or the fit, the import's own Cancel
func cancel_run() -> void:
	if _gen_on:
		if m.gen_move.pid >= 0:
			OS.kill(m.gen_move.pid)
		Children.done(m.gen_move.pid)
		m.gen_move.pid = -1
		_gen_on = false
		m.gen_easy = false
		_t0 = -1
		_take_stop()
		m._say_plain("Stopped. Nothing was changed.")
		return
	if m._video_pid >= 0 or m._imp_busy():
		m._import_cancel()


func copy_video() -> void:
	if _gen_on or _vid_busy or m._imp_busy() or m._video_pid >= 0:
		_refuse()
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray([VIDEO_TYPES])
	fd.use_native_dialog = true
	fd.title = "Copy a video of a person"
	fd.current_dir = String(OS.get_system_dir(OS.SYSTEM_DIR_MOVIES))
	fd.file_selected.connect(func(p: String): fd.queue_free(); copy_video_file(p))
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## a second copy (or any video job) while one runs: refused; the bar's line says the first is still going
func _refuse() -> void:
	if _vid_busy:
		_vid_refused = true
	m._say("A video is already being copied: wait for it, or press Cancel on the bar")


## the copy of one file (the dialog's pick; a test calls it with its own clip). An open scene with unsaved cards is asked about first
func copy_video_file(path: String) -> void:
	if _gen_on or _vid_busy or m._imp_busy() or m._video_pid >= 0:
		_refuse()
		return
	if not FileAccess.file_exists(path):
		_fail("That video file could not be found. Pick it again with Copy a video.")
		return
	if not m.S.cards.is_empty() and m._unsaved():   # the copy would replace these cards: ask first
		_ask_copy(path)
		return
	_start_copy(path, false)


## the unsaved open scene's question before a copy (main's _ask_save pattern): Replace / Add after / Cancel
func _ask_copy(path: String) -> void:
	_copy_path = path
	if _copy_ask == null:
		_copy_ask = ConfirmationDialog.new()
		_copy_ask.name = "CopyAsk"
		_copy_ask.title = "Replace your clip?"
		_copy_ask.dialog_autowrap = true
		_copy_ask.min_size = Vector2i(440, 0)
		_copy_ask.ok_button_text = "Add after"
		var rb := _copy_ask.add_button("Replace", false, "replace")
		rb.name = "Replace"
		_copy_ask.confirmed.connect(func(): copy_choose("add"))
		_copy_ask.custom_action.connect(func(a: StringName): copy_choose(String(a)))
		_copy_ask.canceled.connect(func(): copy_choose("cancel"))
		m.add_child(_copy_ask)
	_copy_ask.dialog_text = "Your clip has changes that are not saved. Replace puts the copied video in its place (Undo brings yours back). Add after keeps yours and adds the copy after it. Cancel keeps the scene as it is."
	_copy_ask.popup_centered()


## how = "replace" | "add" | "cancel" (the question's buttons; a test calls it). A late canceled after a button is no second answer
func copy_choose(how: String) -> void:
	var path := _copy_path
	if path == "":
		return
	_copy_path = ""
	_copy_ask.hide()
	if how == "cancel":
		m._say("Cancelled. The scene is as it was.")
		return
	_start_copy(path, how == "add")


func _start_copy(path: String, add: bool) -> void:
	_drop_saved_toast()
	_vid_busy = true
	_vid_cancel = false
	_vid_refused = false
	_vid_landed = false
	_vid_t0 = Time.get_ticks_msec()
	_copy_bar.value = 0.0
	_copy_left.visible = false
	panel.visible = false   # the picker goes at once (_process sets it again each frame: _copying keeps it away)
	_vid_before = String(m.scene_path)
	_vid_said = "Copied %s" % path.get_file()
	_t0 = -1
	m._land_undo = "Copy a video"
	if add:   # Add after: the landing hands the copy's cards here instead of opening it as a scene
		m.easy_copy_land = _land_added
	m._import_video(path)
	if m._video_pid < 0 and not m._imp_busy():   # the tracker did not start: there is nothing to wait for
		_vid_busy = false
		m._land_undo = ""
		m.easy_copy_land = Callable()
		_fail(NO_READER)


## Add after, the copy landed: its cards join the open scene at the end (one undo step; the scene's file and place stay)
func _land_added(d: Dictionary) -> void:
	m._land_undo = ""
	var err := _append(d, "Copied video", "Copied video")
	if err != "":
		_vid_busy = false
		_fail(err)
		return
	_vid_landed = true


## every frame while a copy runs: the say line shows the progress; when both steps are over, the result
func _video_tick() -> void:
	if _vid_landed:   # Add after: the copy's cards are in the scene now
		_vid_landed = false
		_vid_busy = false
		m._land_undo = ""
		_copied()
		return
	if m._video_pid >= 0:   # the tracker reads the video
		var f := _tracker_progress()
		var words := "Reading your video: %d %%" % roundi(f * 50.0) if f >= 0.0 else "Reading your video..."   # the whole copy's figure (the read is its first half), the same as the bar
		m._say_plain(_copy_say(words))
		_copy_show(f * 0.5 if f >= 0.0 else 0.0, words)
		if m._imp_lbl != null:   # the top bar's line (main's _imp_show named it "tracking <file>" for Expert)
			m._imp_lbl.text = words
		if m._imp_bar != null and f >= 0.0:   # its own percent follows the same read (main's _video_bar runs only every 4th of a second)
			m._imp_bar.value = f * 100.0
		return
	if m._imp_busy():   # the fit: the import's own bar and Cancel show it too
		if bool(m._imp.get("cancel", false)):
			_vid_cancel = true
		m._say_plain(_copy_say("Fitting the moves to the body: %d %%" % roundi(50.0 + VideoIQ.progress * 50.0)))   # the whole copy's figure
		_copy_show(0.5 + VideoIQ.progress * 0.5, "Fitting the moves to the body")
		return
	if String(m.scene_path) != _vid_before and not m.S.cards.is_empty():
		_vid_busy = false
		m._land_undo = ""
		_takes = []   # the kept take is the scene now: its files stay
		_take_n = 0
		m.video_gate = Callable()
		_copied()
	elif m._video_cancelled:   # stopped while the tracker read the video: nothing landed
		_take_stop()
		m._say_plain("Stopped. Nothing was changed.")
	elif _vid_cancel:
		_take_stop()
		m._say_plain("Cancelled. The scene is as it was.")
	else:
		_take_abort(NO_PERSON)


## the bar's line while a copy runs: after a refused second copy it names the first one as still going
func _copy_say(words: String) -> String:
	return ("Still copying the first video: " + words) if _vid_refused else words


## Easy's copy bar: frac = the whole copy's fraction (0..1; the read is the first half, the fit the second). Once COPY_LEFT_MIN % is
## done, "about N s left" = the elapsed time scaled to the rest; before that the line stays hidden (too early to guess)
func _copy_show(frac: float, words: String) -> void:
	var done := maxf(clampf(frac, 0.0, 1.0), _copy_bar.value / 100.0)   # never back: a tracker read that is not written yet is no 0 %
	_copy_bar.value = done * 100.0
	# ONE NUMBER: main's import bar counts each step from 0 (it read 27 % while this bar read 13 %): in Easy it is hidden, and the
	# words' percent is this whole-copy figure too
	if m._imp_bar != null:
		m._imp_bar.visible = false
	_copy_bar.tooltip_text = words
	if done * 100.0 >= COPY_LEFT_MIN:
		var secs := (Time.get_ticks_msec() - _vid_t0) / 1000.0
		_copy_left.text = "about %d s left" % maxi(1, roundi(secs * (1.0 - done) / done))
		_copy_left.visible = true
	else:
		_copy_left.visible = false


## the tracker's fraction read (tools/see_video.py --progress), or -1 when none is written yet
func _tracker_progress() -> float:
	var pf := String(m._video_prog)
	if pf == "" or not FileAccess.file_exists(pf):
		return -1.0
	var t := FileAccess.get_file_as_string(pf).strip_edges()
	return t.to_float() if t.is_valid_float() else -1.0


## the copied clip: built and playing, framed like a card's (the same steps as _go)
func _copied() -> void:
	_hist.clear()   # a copied clip is not a catalog move: no "Then" buttons for it
	_names = []     # nor a name from its move words: the scene's own name is used
	_built = true
	_open = false
	_gen_words = ""
	_msg.text = ""
	_clip_word = "the copied clip"
	m._layout_bottom()
	_play()
	m.easy.frame_clip_next()
	var say := "%s: %d cards. Again plays it from the start; Undo takes it back." % [_vid_said, m.S.cards.size()]
	var caution := _limb_caution()
	m._say_plain(say + " " + caution if caution != "" else say)


## the tracker's own word for a limb it lost or was unsure of (Scene.iq spans on a hand or a foot: a limb out of view, or
## low confidence): one plain sentence, "" when every limb was seen
func _limb_caution() -> String:
	var items := []
	for sp in (m.S.iq.get("spans", []) as Array):
		var p := String(sp.get("part", ""))
		if not (p.begins_with("hand_") or p.begins_with("foot_")):
			continue
		var what := "%s %s" % ["left" if p.ends_with("_l") else "right", "leg" if p.begins_with("foot_") else "arm"]
		if not items.has(what):
			items.append(what)
	if items.is_empty():
		return ""
	var who := "his " + String(items[0])
	if items.size() > 1:
		var legs := items.filter(func(s): return String(s).ends_with("leg")).size()
		who = "his legs" if legs == items.size() else ("his arms" if legs == 0 else "his arms and legs")
	return "Part of him was outside the video, so %s may look wrong: drag it to fix it." % who


## a copy is running (Easy's Copy a video; the AI take's own tracker is not one): the picker stays away and the bar's Cancel is the one
func _copying() -> bool:
	return _vid_busy and m._land_undo == "Copy a video"


## the clip for one card or one typed line: one undo step. "" = built; else the one sentence why not
func _build(what: String, label: String, easy := "", add := false) -> String:
	var nm := what.strip_edges().to_lower()
	var d: Dictionary
	var path := ""
	if Templates.has_file(nm):   # the picker's templates and the baked kick (templates/roundhouse.json: instant)
		d = Templates.read(nm)
		if d.is_empty():
			return "The %s template file is missing: rebuild the templates (tools/make_templates.gd) and try again." % nm
		_tag_cards(d, nm)
		path = UserPaths.w(Templates.new_path(nm))
	else:
		var r := _words_dict(nm)
		if not r["ok"]:
			return String(r["error"])
		d = r["dict"]
		path = load("res://scripts/text_blocking.gd").unique_path(UserPaths.w("res://scenes/_wip"), load("res://scripts/text_blocking.gd").slug(nm))
	if add:   # ADD AFTER: the new cards join the clip in the scene (no new scene file)
		return _append(d, label, easy)
	d["scene"] = path.get_file().get_basename()
	d["plan"] = "Easy home: %s" % label
	var seats: Array = m.S.props.filter(func(p): return String(p["kind"]) in SIT_KINDS)   # the seats stay: a chair placed, then Walk, kept the chair (round 7: it was gone, so no sit). Other props: as before
	if not seats.is_empty() and not d.has("props"):
		d["props"] = seats.map(func(p): return Props.to_dict(p))
	_ball_line = ""
	if _has_kick(d.get("cards", [])):   # a kick: the foot reaches a football on the floor (the clip moves, not the ball)
		var ball = _ball_at(m.S.props)
		if ball != null:
			_shift_cards(d.get("cards", []), _reach_delta(d.get("cards", []), ball))
			_ball_line = BALL_SAID
	var held: Dictionary = PoseBake.held_of(m.B).duplicate(true) if m.B.wep_on else {}   # the sword in his hand: the new scene's cards keep it
	m._step_hint = label   # the undo step is named after the card (main's undo list shows it)
	m._step_easy = easy if m.easy.on else ""   # and, in Easy, by its short name: "Walk", or the typed words (cut to 18 characters)
	m._push_undo()
	m.undo[-1]["swap"] = true   # the card makes a NEW Scene object: Ctrl+Z puts the empty one back whole (main._restore; path_walk_ui does the same)
	m._write(path, d)
	m._load_scene(path, true)   # a card build is a work copy in scenes/_wip: unsaved until the user saves it
	if not held.is_empty():
		_hold_again(held)
	m._rebuild_cards()
	m._refresh()
	return ""


## ADD AFTER: the move's cards go after the clip's last card in the scene that is open (one undo step, main._do: the
## same as the copied video's landing). The first added card is reached JOIN_S seconds after the clip ends, at the
## clip's end root position, so the body carries on from where the clip stopped instead of jumping back to the move's start.
func _append(d: Dictionary, label: String, easy: String) -> String:
	var T := Scene.new()
	T.from_dict(d)
	var new_cards: Array = T.cards
	if new_cards.is_empty():
		return "The %s has no cards to add." % label.to_lower()
	var S: Scene = m.S
	var o: Vector3 = S.sample(S.length())["offset"]
	var first: Dictionary = new_cards[0]
	first["move"] = JOIN_S
	first["pose"]["offset"] = [o.x, o.y, o.z]
	_ball_line = ""
	var ball = _ball_at(S.props)
	var move := Vector2.ZERO
	if ball != null and _has_kick(new_cards):   # a kick: the clip moves so the foot reaches the ball (the whole scene, so the join holds)
		move = _reach_delta(new_cards, ball)
		_shift_cards(new_cards, move)
		_ball_line = BALL_SAID
	var held: bool = m.B.wep_on
	m._step_hint = "Add " + label.to_lower()
	m._step_easy = ("Add " + easy.to_lower()) if m.easy.on else ""   # Easy's undo names it: "Undo: Add wave"
	m._do(func():
		if move != Vector2.ZERO:
			_shift_cards(S.cards, move)
		S.cards.append_array(new_cards)
		if held:   # the sword in his hand rides into the added cards (the body is the live one: it still holds it)
			var added := Scene.new()
			added.cards = new_cards
			ObjectLibrary.arm_cards(added, m.B)
		m._rebuild_cards())
	m._refresh()
	return ""


const BALL_SAID := "The ball doesn't fly yet: his foot reaches it, and it stays where it is."
var _ball_line := ""   # the sentence the last kick adds to the say line ("" = no ball in the scene)


## the first football in a props list: {c: its centre on the floor, r: its radius}, or null
static func _ball_at(props: Array) -> Variant:
	for p in props:
		if String((p as Dictionary)["kind"]) == "ball":
			var sp: Array = Props.kind_of("ball")["spheres"][0]
			return {"c": ((p as Dictionary)["xf"] as Transform3D) * Vector3(sp[0]), "r": float(sp[1])}
	return null


## a kick's clip: any card named roundhouse (the Kick card's move)
static func _has_kick(cards: Array) -> bool:
	for c in cards:
		if String((c as Dictionary).get("name", "")).to_lower().contains("roundhouse"):
			return true
	return false


## the floor move (x, z) that puts the kicking toe on the ball: the closest toe to the ball's centre, over the cards (both feet,
## the body's own solve on a scratch body), lands at the ball's edge plus 2 cm, on the line from the ball through where it was
static func _reach_delta(cards: Array, ball: Dictionary) -> Vector2:
	var W := Body.new()
	W.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var bc: Vector3 = ball["c"]
	var best := INF
	var at := Vector3.ZERO
	for c in cards:
		Scene.put(W, Moves._flat((c as Dictionary)["pose"]))
		W.fk()
		for sd in ["_l", "_r"]:
			var t: Vector3 = W.P["ball" + sd]
			var dist := Vector2(t.x - bc.x, t.z - bc.z).length()
			if dist < best:
				best = dist
				at = t
	var bxz := Vector2(bc.x, bc.z)
	var from := Vector2(at.x, at.z) - bxz
	var dir := from.normalized() if from.length() > 1e-6 else Vector2(0, 1)
	return (bxz + dir * (float(ball["r"]) + 0.02)) - Vector2(at.x, at.z)


## every card's offset moves by d (x, z): a card's offset is its body's place on the floor
static func _shift_cards(cards: Array, d: Vector2) -> void:
	if d == Vector2.ZERO:
		return
	for c in cards:
		var p: Dictionary = (c as Dictionary)["pose"]
		var o: Array = p.get("offset", [0, 0, 0])
		p["offset"] = [float(o[0]) + d.x, float(o[1]), float(o[2]) + d.y]


## the held sword (or the held weapon, as a state) put back into the body of a freshly loaded scene, then into every card
func _hold_again(held: Dictionary) -> void:
	var s0: Dictionary = m.B._state0()
	s0.merge(held, true)
	m.B._set_state0(s0)
	ObjectLibrary.arm_cards(m.S, m.B)


## the template a typed part names, when it is a card's own word ("walk", "sit down", "kick" = the Kick card's roundhouse
## file). "" = not a card word: TextBlocking builds it. CARDS is the one list, so the typed box and the cards cannot part ways.
## (bare "roundhouse" is not here on purpose: tools/make_templates.gd bakes that file from the words, and must not read it back)
static func _card_template(part: String) -> String:
	var w := part.strip_edges().to_lower()
	if STAND_WORDS.has(w):
		return String(STAND_WORDS[w])
	if Templates.WORDS.has(w):   # typed dance words: "dance", "groove" (not a card: the Easy cards and the refusal's buttons are unchanged)
		return String(Templates.WORDS[w])
	for c in CARDS:
		if String(c[0]).to_lower() == w:
			return String(c[1])
	return ""


## THE REFUSAL'S TRY BUTTONS: the card moves whose word is closest to the typed line (bigram Dice on the whole line and on each
## of its words, at least TRY_MIN), closest first; the rest of the four come from TRY. Returns four card indices (fewer never).
static func try_pick(typed: String, n := 4) -> Array:
	var whole := typed.to_lower().strip_edges()
	var parts: Array = [whole]
	for w in whole.split(" ", false):
		parts.append(String(w))
	var near: Array = []   # [score, card index]
	for i in range(CARDS.size()):
		var w := String(CARDS[i][0]).to_lower()
		var best := 0.0
		for p in parts:
			best = maxf(best, _dice(String(p), w))
		if best >= TRY_MIN:
			near.append([best, i])
	near.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for pair in near:
		out.append(pair[1])
	for i in TRY:
		if out.size() >= n:
			break
		if not out.has(i):
			out.append(i)
	return out.slice(0, n)


## bigram Dice similarity of two strings, 0..1 (0 when either is shorter than two letters)
static func _dice(a: String, b: String) -> float:
	var ga := _bigrams(a)
	var gb := _bigrams(b)
	if ga.is_empty() or gb.is_empty():
		return 0.0
	var total := ga.size() + gb.size()
	var common := 0
	for g in ga:
		var at: int = gb.find(g)
		if at >= 0:
			common += 1
			gb.remove_at(at)
	return 2.0 * float(common) / float(total)


static func _bigrams(s: String) -> Array:
	var out: Array = []
	for i in range(s.length() - 1):
		out.append(s.substr(i, 2))
	return out


## the refusal's buttons: the picked cards in order, after the "Or try:" label (the rest stay hidden)
func _try_show(typed: String) -> void:
	var pick: Array = try_pick(typed)
	for tb in _try_btns:
		(tb as Button).visible = false
	for k in range(pick.size()):
		var tb: Button = _try_btns[pick[k]]
		_try_row.move_child(tb, k + 1)
		tb.visible = true


## the sentence for a typed part Kine cannot build: one short line (the "Or try" buttons carry the moves it knows)
static func _cannot_build(part: String) -> String:
	var shown := part if part.length() <= 40 else part.substr(0, 37) + "..."
	return "Kine doesn't know '%s' yet." % shown


## words -> one scene dict. "jab then cross" is two strikes (split on "then", "," and ";"); a part that is a card's word
## is that card's template file, any other part is built by TextBlocking on a fresh body. The parts are joined in order.
## {ok, dict} or {ok: false, error}
func _words_dict(text: String) -> Dictionary:
	var parts: Array = []
	for p in text.replace(",", " then ").replace(";", " then ").split(" then ", false):
		var s := String(p).strip_edges()
		if s != "":
			parts.append(s)
	if parts.is_empty():
		return {"ok": false, "error": "Type a move first, such as 'jab then cross' or 'roundhouse'."}
	var out := {}
	for p in parts:
		var d: Dictionary
		var tmpl := _card_template(p)
		if tmpl != "":
			d = Templates.read(tmpl)
			if d.is_empty():
				return {"ok": false, "error": "The %s template file is missing: rebuild the templates (tools/make_templates.gd) and try again." % tmpl}
			_tag_cards(d, tmpl)
		else:
			for w in String(p).split(" ", false):
				if w in NOT_YET:
					return {"ok": false, "error": _cannot_build(p)}
			var W := Body.new()   # a scratch body: TextBlocking poses it card by card (main's words box does the same)
			W.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			var r: Dictionary = load("res://scripts/text_blocking.gd").build(p, W)
			if not r["ok"]:
				if String(r["error"]).begins_with("no attack"):
					return {"ok": false, "error": _cannot_build(p)}
				return {"ok": false, "error": "Kine can't build '%s': %s." % [p, String(r["error"])]}
			d = (r["scene"] as Scene).to_dict(W)
			_tag_cards(d, p)
		if out.is_empty():
			out = d
		else:
			(out["cards"] as Array).append_array(d["cards"])
	return {"ok": true, "dict": out, "strikes": parts.size()}


## EASY: every card of one move build is tagged with the move it came from ("punch|<serial>"): the strip reads "Punch 1, 2..".
## The serial makes two punches in a row two runs. Saved with the card (Scene.to_dict "from"); Expert never reads it
static func _tag_cards(d: Dictionary, tag: String) -> void:
	var s := "%s|%d" % [tag.strip_edges().to_lower(), Time.get_ticks_usec()]
	for c in d.get("cards", []):
		(c as Dictionary)["from"] = s


## play from the start: a playing clip is stopped first, so Again and a new build both start at 0
func _play() -> void:
	_drop_saved_toast()
	if m.playing:
		m._toggle_play()
	m.playhead = 0.0
	m._toggle_play()


## FASTER / SLOWER / BIGGER / SMALLER on the clip just built: one press = one undo step, the clip plays again from its start,
## the camera frames it, and the say line names what happened. A press at a limit changes nothing and says why.
func tweak(how: String) -> void:
	_drop_saved_toast()
	if _gen_on or _vid_busy or m._imp_busy():
		m._say_plain(GEN_BUSY)
		return
	var S: Scene = m.S
	if S.cards.size() < 2:
		m._say_plain("Nothing to change yet: build a move first.")
		return
	var before := S.length()
	var said := ""
	if how == "faster" or how == "slower":
		var k: float = EasyTweak.FASTER if how == "faster" else EasyTweak.SLOWER
		var stop := EasyTweak.timing_stop(S, k)
		if stop != "":
			m._say_plain(stop)
			m._toast(stop)   # round 8: the refusal is also the Easy toast (the status line alone was missed)
			return
		m._step_easy = how.capitalize() if m.easy.on else ""   # "Faster" / "Slower": the undo step's Easy name (main.retime pushes it)
		var err: String = m.retime(0, S.cards.size() - 1, k * 100.0)   # main.retime: one undo step, the holds and moves x k
		m._step_easy = ""
		if err != "":
			m._say_plain(err)
			return
		said = "%s: %s now takes %.1f s." % [how.capitalize(), _clip_word, S.length()]
	else:
		var k: float = EasyTweak.BIGGER if how == "bigger" else EasyTweak.SMALLER
		var fly := EasyTweak.flight_retimed(S, k)   # a jump: the flight lasts sqrt(k) longer, so it goes k times as high
		var poses := EasyTweak.exaggerated(S, m.B, k)
		if poses.is_empty() and fly.is_empty():
			m._say_plain("Nothing to make %s: the clip has no pose to move from." % ("bigger" if k > 1.0 else "smaller"))
			return
		m._step_easy = how.capitalize() if m.easy.on else ""   # "Bigger" / "Smaller"
		m._push_undo()
		for i in poses:
			S.cards[i]["pose"] = poses[i]
		for i in fly:
			S.cards[i]["move"] = fly[i]["move"]
			S.cards[i]["hold"] = fly[i]["hold"]
		m._retimed()
		var pct := roundi(absf(k - 1.0) * 100.0)
		said = "%s: %s now moves %d %% %s." % [how.capitalize(), _clip_word, pct, "further" if k > 1.0 else "less"]
	m._say_plain(said)
	_play()
	m.easy.frame_clip_next()


## CUT START / CUT END (video walk-through round 6, goal 4; beginner walk-through 9, friction): Cut start drops what is BEFORE the
## good part's start, Cut end what is AFTER its end. Which point: a card picked on the strip with the playhead on it (the pick sets the
## playhead to the card's arrival) is the card path, as before. Otherwise the moved slider is the point (the slider is what a beginner
## just touched; a pick left from earlier is not). The slider's cut keeps the motion at the playhead: a new card holds the pose there,
## the card it cut into keeps its own move (shortened to what is left). One undo step; the clip plays again from its new start.
## It keeps 2+ cards.
func trim(start: bool) -> void:
	_drop_saved_toast()
	if _gen_on or _vid_busy or m._imp_busy():
		m._say_plain(GEN_BUSY)
		return
	var S: Scene = m.S
	var n: int = S.cards.size()
	var i: int = m.sel_card
	if n < 3:
		m._say_plain("Nothing to cut: the clip needs 3 or more cards.")
		return
	var L: float = S.length()
	var t: float = m.playhead
	var picked: bool = i >= 0 and i < n
	var on_pick: bool = picked and absf(t - float(S.times()[i][1])) < 1e-3
	var nothing_before: bool = t <= 1e-3 if start else t >= L - 1e-3   # the cut would drop nothing on that side
	var all_of_it: bool = t >= L - 1e-3 if start else t <= 1e-3        # the cut would drop the whole clip
	if picked and (on_pick or nothing_before or all_of_it):
		_trim_card(start, i)
		return
	if nothing_before or all_of_it:
		if start:
			m._say_plain("Cut start: the playhead is at the %s, so %s. Drag the slider to where the good part starts, then press Cut start." % ["start" if nothing_before else "end", "nothing is before it" if nothing_before else "Cut start would drop the whole clip"])
		else:
			m._say_plain("Cut end: the playhead is at the %s, so %s. Drag the slider to where the good part ends, then press Cut end." % ["end" if nothing_before else "start", "nothing is after it" if nothing_before else "Cut end would drop the whole clip"])
		return
	m.playing = false
	var err := _cut_at(start, t)
	if err != "":
		m._say_plain(err)
		return
	m._step_easy = ""
	_play()
	m.easy.frame_clip_next()


## the card path: the picked card is where the good part starts (or ends); the cards on the far side are dropped
func _trim_card(start: bool, i: int) -> void:
	var S: Scene = m.S
	var n: int = S.cards.size()
	var word := "starts" if start else "ends"
	var drop: Array = range(0, i) if start else range(i + 1, n)
	if drop.is_empty():
		m._say_plain("The clip already %s here: pick a card further in." % word)
		return
	if n - drop.size() < 2:
		m._say_plain("That would leave one card: pick a card further %s." % ("in" if start else "back"))
		return
	m._step_hint = "Cut start" if start else "Cut end"
	m._step_easy = m._step_hint
	m._push_undo()
	for k in drop.size():
		S.cards.remove_at(drop[drop.size() - 1 - k])
	m.sel_card = 0 if start else i
	m.msel = []
	m.sel_end = -1
	m.playhead = 0.0
	m._retimed()
	m._step_easy = ""
	m._say_plain("Cut %s: %s is now %d cards, %.1f s. Undo takes the cut back." % ["the start" if start else "the end", _clip_word, S.cards.size(), S.length()])
	_play()
	m.easy.frame_clip_next()


## the playhead's cut at time t (0 < t < length). Returns "" when done, else the status line's words (nothing changed).
## Cut start: the first card is the pose at t, then the card the playhead is in, its move cut to what is left (or, in its hold,
## the hold cut to what is left), then the cards after. Cut end: the cards before, then the pose at t arriving by the move it had,
## or (in a hold) the card with its hold cut to the playhead.
func _cut_at(start: bool, t: float) -> String:
	var S: Scene = m.S
	var n: int = S.cards.size()
	var ts: Array = S.times()
	var k := 0
	for j in n:
		if float(ts[j][0]) <= t:
			k = j
	var in_move: bool = t < float(ts[k][1]) - 1e-3   # the playhead is on the move into card k (not yet arrived there)
	m._ps().apply(m.B, t)   # the pose at t, as the app plays it (the scrub poses the body the same way)
	var pose: Dictionary = m.B.to_dict()
	var new_cards: Array = []
	if start:
		if in_move:
			new_cards.append({"name": "Cut", "pose": pose, "move": 0.0, "hold": 0.0})
			var rest: Dictionary = (S.cards[k] as Dictionary).duplicate(true)
			rest["move"] = snappedf(maxf(0.04, float(ts[k][1]) - t), 0.001)
			new_cards.append(rest)
			for j in range(k + 1, n):
				new_cards.append(S.cards[j])
		else:
			var hold_left: float = float(ts[k][2]) - t
			new_cards.append({"name": "Cut", "pose": pose, "move": 0.0, "hold": snappedf(maxf(0.0, hold_left), 0.001)})
			for j in range(k + 1, n):
				new_cards.append(S.cards[j])
	else:
		if in_move:
			for j in k:
				new_cards.append(S.cards[j])
			new_cards.append({"name": "Cut", "pose": pose, "move": snappedf(maxf(0.04, t - float(ts[k][0])), 0.001), "hold": 0.0})
		else:
			for j in range(0, k + 1):
				new_cards.append(S.cards[j])
			var last: Dictionary = (new_cards[k] as Dictionary).duplicate(true)
			last["hold"] = snappedf(maxf(0.0, t - float(ts[k][1])), 0.001)
			new_cards[k] = last
	if new_cards.size() < 2:
		return "That would leave one card: move the slider %s." % ("back" if start else "further in")
	m._step_hint = "Cut start" if start else "Cut end"
	m._step_easy = m._step_hint
	m._push_undo()
	S.cards.clear()
	S.cards.append_array(new_cards)
	m.sel_card = 0 if start else new_cards.size() - 1
	m.msel = []
	m.sel_end = -1
	m.playhead = 0.0
	m._retimed()
	m._step_easy = ""
	m._say_plain("Cut %s at %.1f s: %s is now %d cards, %.1f s. Undo takes the cut back." % ["start" if start else "end", t, _clip_word, S.cards.size(), S.length()])
	return ""


## SMOOTHER (video walk-through round 6, goal 5): one press smooths the clip one step (EasyTweak.smoothed). One undo step; the clip
## plays again from its start; the status line says what it did.
func smooth() -> void:
	_drop_saved_toast()
	if _gen_on or _vid_busy or m._imp_busy():
		m._say_plain(GEN_BUSY)
		return
	var S: Scene = m.S
	if S.cards.size() < 3:
		m._say_plain("Nothing to smooth yet: the clip needs 3 or more cards.")
		return
	var poses := EasyTweak.smoothed(S, m.B)
	if poses.is_empty():
		m._say_plain("Nothing to smooth: the clip has no poses to blend.")
		return
	m._step_hint = "Smoother"
	m._step_easy = "Smoother"
	m._push_undo()
	for i in poses:
		S.cards[i]["pose"] = poses[i]
	m._retimed()
	m._step_easy = ""
	m._say_plain("Smoother: %s is smoother now (each pose blends with its neighbours). Smoother again smooths it more; Undo takes it back." % _clip_word)
	_play()
	m.easy.frame_clip_next()


## Change it: the panel with its box. A second press (or Esc, or Close) puts the strip back when a clip is built.
func _change() -> void:
	_drop_saved_toast()
	if _open and _clip_kept():
		_close_panel()
		return
	_open = true
	_msg.text = ""
	_edit.grab_focus.call_deferred()
	_edit.select_all.call_deferred()   # the box's old words (a failed line) are selected: typing replaces them


## THE STRIP STAYS (walk-through round 7, goals 2-5): with a clip built, a refused line does not open the panel (the strip's
## Again, Then and tweak buttons are the controls the user is using). The refusal goes to the status line. The panel is open
## only when it already was (Change it): then the sentence goes in its box, as before.
func _clip_kept() -> bool:
	return m.easy.on and _built and not m.S.cards.is_empty()


func _fail(sentence: String, quiet := false) -> void:   # quiet: the panel alone says it (a typed word Kine doesn't know)
	_t0 = -1
	if _clip_kept() and not _open:
		_msg.text = ""
		m._say_plain(sentence)
		return
	_msg.text = sentence
	_msg.add_theme_color_override("font_color", Tok.c("warn"))
	_open = true   # the panel comes back with the sentence (no clip yet, or Change it is open)
	if quiet and m.easy.on:
		m._say_plain("")   # Easy: the panel says it; the status line under the body would only repeat it (walk-through round 4)
	else:
		m._say(sentence)


func _card_button(i: int) -> Button:
	var b := Button.new()
	b.name = "eh_card_%d" % i
	b.set_meta("label", CARDS[i][0])
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(112, 92)
	b.tooltip_text = "build %s and play it (one undo step)" % String(CARDS[i][0]).to_lower()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var pic := TextureRect.new()
	pic.name = "icon"
	pic.texture = Icons.big(String(CARDS[i][2]))
	pic.custom_minimum_size = Vector2(40, 40)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var word := _label(String(CARDS[i][0]), 16, "text")
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(word)
	b.pressed.connect(card.bind(i))
	return b


func _then_button(nm: String, text: String, tip: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 40)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _strip_button(nm: String, text: String, tip: String, f: Callable, size := Vector2(120, 40), font := 0) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = size
	if font > 0:
		b.add_theme_font_size_override("font_size", font)
	b.pressed.connect(f)
	return b


func _label(text: String, size: int, tok: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Tok.c(tok))
	return l
