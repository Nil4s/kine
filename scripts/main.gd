## main.gd - the poser window. All math lives in body.gd (the body), scene.gd (moving between poses), moves.gd (old files).
##
## Screen:  top bar = views + undo |  left = POSES (click one to put the body in it) |  right = the SELECTED PART
##          (sliders in words) + HANDS & BAT |  bottom = the SCENE (pose cards in a row; the poser moves between them).
## Mouse:   click a part = select;  drag = the natural thing for that part (head looks, hips move the body with the feet planted,
##          spine bends along its length, a limb swings toward the mouse; scripts/part_drag.gd);  Shift+drag = roll it;  drag a hand/foot = the whole limb follows
##          (Alt: only the wrist/ankle);  Ctrl+drag the hips = move the body;  the bat: free = drag/Shift/Alt, locked =
##          dragging it moves the hand.   Right-drag = orbit, middle-drag = pan, wheel = zoom.
## Keys:    shown on every button (Q snap, R reset, L lock bat, F fingers, G 2 hands, Space play, Ctrl+Z undo ...).
## Command line (after --): --pose <json> | --scene <json> | --t <s> | --view <1-5> | --focus <joint> | --shot <png>
extends Node3D

const SEL := Color(0.25, 0.55, 1.0)
const LIMIT := Color(1.0, 0.82, 0.15)
const TOUCH := Color(1.0, 0.25, 0.2)
const ARMS_OUT := 25.0   # relaxed arms: degrees out from straight down (Nick 10-12)
const LEFT_W := 240   # round 36 (RR3): the browser; was 250
const RIGHT_W := 290   # round 36 (RR2): the inspector; was 370 (a panel of sentences)
const BOTTOM_H := 256   # round 36 (RR4): the scene row 35 + the cards 161 + the ONE strip 34, separations 12, margins 8, the 6-px gap; was 321 (timeline and play row apart)
const BOTTOM_FOLDED := 48   # RR4: the ONE strip (34) + the panel's margins (8) + the 6-px gap; was 118 (QQ4: timeline + play row); tests/fold_test.gd holds it
const BOTTOM_EMPTY := 100   # no clips yet: the scene row + the CLIP hint only (round 7: the empty card row, timeline
							# and play row took a third of the screen for nothing)
var ui_bh: HBoxContainer   # the bottom panel's header row (the scene's name and buttons): folded away with the cards
var bottom_h := BOTTOM_H   # the bottom panel's height now: _layout_bottom() sets it and moves what sits on it
const TOP_H := 74   # round 36 (RR1): two thin rows, Fusion's: the strip (tabs, the scene, the small icons) STRIP_H, then the
## tools (icons only) over their group captions. Round 9 was one row of icon-over-label at 68; tests/icons_test.gd
## keeps every button inside it
const STRIP_H := 28
const TOOLS_H := 30
const CAP_H := 14
const SETTINGS := "user://poser.cfg"   # what the poser remembers between runs (round 9: the theme)
## where settings are saved: under a test script (godot -s), a file of the test's own, read by nobody at boot, so
## the suites (run in parallel) never read or write Nick's setting, nor each other's (round 9: one did, a layout failed)
var settings := SETTINGS
const AUTOSAVE := "user://autosave.json"   # the unsaved scene, every 15 s (round 16, W1): never in scenes/
var autosave := AUTOSAVE   # a test's own (POSER_AUTOSAVE names one; otherwise per process, removed on exit)
const RECENT_N := 10   # File > Recent (ROADMAP 59): the scenes opened or saved, newest first (settings [recent] scenes)
const RING_N := 5      # File > Restore... (ROADMAP 59): the last autosaves, rotating: user://autosave_1.json is the newest
var _as_wait := 0.0
var _as_last := ""
const JOURNAL := "user://journal"   # ROADMAP 2 (CRASH-PROOF): one .jsonl per scene, trimmed on save (scripts/journal.gd)
var journal_dir := JOURNAL
var journal_on := false   # on in the app; a test runs it only when POSER_JOURNAL names its own folder
var journal := Journal.new()
var _jpending := false    # an undo step was pushed or undone since the last journal entry
var journal_offer := {}   # a session that did not quit cleanly: {state, t, path, n} (File: restore unsaved work)
var quit_clean := true    # false = the window goes without a clean quit (a test's simulated kill)
var journal_capture_us := 0   # the scene's capture for the journal, summed (us): the numbers the journal test prints

var B := Body.new()
var S := Scene.new()
## TWO CHARACTERS IN MAIN (round 50, GATES TC3): B and S are always THE ACTIVE actor, so every edit, undo step and view
## works on whoever is active unchanged. actors_rt is the runtime list built from the hero's S.actors (TC1): actor 0 =
## the hero (the file's top level, at the identity), actor k = S.actors[k - 1] with a Body of its own. Empty = one
## actor, and nothing anywhere does any extra work (_pose_others returns at once).
var actors_rt := []   # [{"name", "B": Body, "S": Scene, "xf": Transform3D (in the hero's space), "t": playhead last posed at}]
var actor_on := 0     # which actor B and S are
## THE SECOND FIGHTER ON SCREEN (TC4): the active actor is drawn by skel at the world origin (every pick, drag and
## projection assumes it); stage_root (the floor, its axes, the lights, the other fighters) carries the inverse of the
## active actor's placement, and the camera moves with it when that changes, so nothing on screen jumps
var stage_root: Node3D
const ACTOR_TINTS := [Color(0.47, 0.58, 0.74), Color(0.5, 0.68, 0.52), Color(0.74, 0.5, 0.48), Color(0.62, 0.52, 0.74)]
var actor_men := []   # per actor k: {"node", "skel", "idx", "wep": [handle, barrel]} under stage_root; empty with one actor
var co: CoEdit = null   # ROADMAP 30: live co-editing (scripts/co_edit.gd); null when not hosting or joined
var _co_seen := ""   # the session state last said in the status line
var _dummy_auto := false   # the dummy put away because there are 2+ fighters (the other fighter is the target)
var _dummy_keep := true    # what dummy_on was before that
var parts := {}         # part -> MeshInstance3D (its collision capsule): click target + highlight
var mats := {}
var dots := {}
var skel: Skeleton3D     # the mannequin's skeleton (assets/mannequin.glb, Quaternius UAL2, CC0)
var bone_idx := {}
var bat_handle: MeshInstance3D
var bat_barrel: MeshInstance3D
var d2_handle: MeshInstance3D   # the off-hand dagger (round 33): drawn, riding its hand
var d2_blade: MeshInstance3D
var bat_knob: MeshInstance3D
var wep_mats := {}
var slide_body := true   # , . slide the main hand: true = the weapon stays, the body follows; false = the weapon slides in the hand
var ui_slide_btn: Button   # "metal" / "tape" / "wood" / "steel": the weapon's looks per kind
var tag: Label3D
var show_caps := false
var sel := "upperarm_r"
var cam: Camera3D
var yaw := 0.0
var pitch := -8.0
var dist := 4.0
var target := Vector3(0, 0.95, 0)
var dragging := ""
var playhead := 0.0
var playing := false
var sel_card := -1
var undo := []   # the current branch, back: the state before each step (Ctrl+Z walks it)
var redo := []   # the current branch, forward: the states Ctrl+Z left (Ctrl+Y walks it)
var _tree := UndoTree.new()   # UNDO AS A TREE (ROADMAP 15, scripts/undo_tree.gd): every step, and the branches they make

# ui
var ui_root: Control
var ui_title: Label
var ui_how: Label
var ui_rows := {}
var ui_hip_box: VBoxContainer
var ui_hips := []
var ui_math: Label
var ui_math_btn: Button
var ui_status: Label
var ui_bar: Label   # STATUS BAR (round 9, GATES P4): what is picked, where you are, what Check said; always on
var check_ran := false   # the bar says "not run" until Check has graded this scene
var pose_clip := {}   # COPY / PASTE (round 10): the copied pose, empty until Ctrl+C
var check_at := 0   # the undo depth when Check ran: a different depth = the count is from before an edit
var ui_poses: ItemList
var ui_pose_name: LineEdit
var ui_cards: HBoxContainer
var ui_time: HSlider
var ui_time_lbl: Label
var ui_fps_lbl: Label   # XX10: the frames per second really reached while playing, and the dropped ones
var play_clock := PlaySpeed.new()   # ROADMAP 48: REAL SPEED or EVERY FRAME (a view setting, never saved, not an undo step)
var play_delay := 0.0   # the test's simulated slow frame: seconds each playing frame costs on top (0 = none)
var ui_mode_btn: Button   # ROADMAP 48: the playback mode, as its icon and words; a click changes it
var ui_mode_lbl: Label    # ROADMAP 48: "Real speed: dropping N frames" / "Every frame: 0.6x speed"
var _mode_painted := ""   # the mode and palette the bar's colours were last set for
var shading := Shading.new()   # XX10: how the body is drawn (a view setting, never saved)
var _was_playing := false
var ui_play: Button
var ui_gear: PanelContainer   # RR4: the play options box (the gear opens it; a click elsewhere closes it)
var ui_gear_btn: Button
var ui_natural: CheckBox
var ui_scene_name: LineEdit
var ui_scenes: OptionButton
var thumbs: SceneThumbs   # ROADMAP 51: the pictures in the scene list (scripts/scene_thumbs.gd)
var ui_tinted := []    # [label, Tok token]: the labels a theme switch re-tints (round 9)
var ui_say_box: StyleBoxFlat
var ui_bar_box: StyleBoxFlat   # RR5: none (the line has no box); kept for the retheme's null check
var ui_find_box: StyleBoxFlat
var world_env: Environment
var floor_mat: StandardMaterial3D
var grid_mesh: ImmediateMesh   # the floor grid (the axes: axis_mesh)
var scene_path := ""   # the open scene's file ("" = never saved)
var clips_ui: ClipsUI   # CLIPS (GAP row 12): the commands, dialog and picked clip (scripts/clips_ui.gd)
var export_ui: ExportDialog   # EXPORT... (ROADMAP 57): one dialog for every target; runs the writers below (scripts/export_dialog.gd)
var mm_ui: MotionMatchUI   # MOTION MATCHING PREVIEW (ROADMAP 33): the commands and the preview (scripts/motion_match_ui.gd)
var ui_help: PanelContainer
var ui_why: PanelContainer   # WHAT WENT WRONG? (ROADMAP 43): the last refusal explained (scripts/whywrong.gd)
var ui_why_box: VBoxContainer
var _why_last: Dictionary = {}   # the last refusal or error: {text, cmd, part, frame, at}
var _why_cmd := ""               # the command (or button) the user ran last: the refusal's "you tried"
var ui_cmd: CommandSearch
## MACROS (ROADMAP 81; scripts/macros.gd): palette steps recorded in order, saved by name in macros_file. Playing one is
## ONE undo step (_push_undo opens it once, at the first edit of the play). rec_label = the REC indicator while recording
var macros_file := "user://macros.json"
var macros: Array = []
var rec_name := ""             # the macro being recorded ("" = not recording)
var rec_steps: Array = []
var rec_label: Label
var _macro_nest := 0           # > 0 while a macro plays
var _macro_pushed := false     # the play's one undo step is already open
var ui_cube: ViewCube
var ui_browser: Browser
const RIBBON := ["POSE", "ANIMATE", "SET", "CHECK", "EXPORT", "VIEW"]   # SET: round 37 (SS5), the props   # EXPORT: round 35a, QQ4 (Fusion's workspaces: what it is FOR)
const RIBBON_TIPS := {"POSE": "reset, relax, mirror, collision", "ANIMATE": "trail, onion, spacing, speed graph, stepped, holds",
	"SET": "props to pose with: add, move, turn, delete, your own models", "CHECK": "grade the motion, polish, fix, the dummy", "EXPORT": "the animation out: Export... (any engine or tool), frame data, a version",
	"VIEW": "front / sides / top / back, big view (or the cube, or keys 1-5)"}
## THE GROUPS (round 36, GATES RR1; Fusion's CREATE / MODIFY): each tab's tools by label, in order, under a caption.
## The caption is a menu of its group's tools by full name. A tool not named here stays after the groups
const RIBBON_GROUPS := {
	"POSE": [["CLIP", ["CLIP this pose (Enter)"]], ["BODY", ["Reset body", "Arms 25°", "Mirror pose (Shift+M)", "Symmetry"]],
		["SHOW", ["Collision (C)"]], ["SHAPE", ["Sketch line of action", "Line of action"]], ["LIBRARY", ["Pose library"]]],
	"ANIMATE": [["OVERLAYS", ["Trail (T)", "Onion (O)", "Spacing (Shift+O)", "Speed graph (Y)", "Balance (Shift+B)"]], ["PLAYBACK", ["Stepped", "Moving holds"]],
		["JUMP", ["Airborne"]], ["KEY", ["Auto-key (Ctrl+K)"]], ["TOOLS", ["Animator tools"]], ["MIRROR", ["Mirror scene", "Mirror in place"]], ["MAKE", ["From video", "Ask AI"]]],
	"SET": [["ADD", ["Add prop", "Import model"]], ["EDIT", ["Turn left", "Turn right", "Delete prop"]], ["USE", ["Sit here", "Step up", "Pick up", "Put down"]]],
	"CHECK": [["GRADE", ["Check", "Polish", "Fix moves through the body"]], ["DUMMY", ["Dummy (H)"]], ["FRAMES", ["Frame data", "Frame boxes", "Frame rate"]]],
	"EXPORT": [["FILES", ["Export...", "Export frame data (json)..."]], ["VERSION", ["Save version"]]],
	"VIEW": [["CAMERA", ["Front (1)", "His right (2)", "Top (3)", "Back (4)", "His left (5)", "Big view (Tab)"]],
		["DISPLAY", ["Hints", "Light", "Follow system", "UI size", "Easy mode", "Corrective shapes"]]],
}
var ui_caps := {}         # tab -> [[caption MenuButton, [its tools]], ...]
var ui_doc: Label         # the strip's middle: the scene's name, clips, length
var ui_doc_dot: Label     # unsaved changes
var ui_ribbon := {}        # tab -> its row of tools (round 7)
var ui_ribbon_tabs := {}   # tab -> its tab button
var ui_toggles := []       # [button, func -> is it on]: the ribbon's on/off buttons show their state (synced in _refresh)
var ui_ring: RingMenu   # right-CLICK a part: a ring of actions (round 7, scripts/ring_menu.gd)
var _rpress := {}   # the right button's press: where, the view's turn then, the part under it (click vs drag)   # left panel, 2nd tab: every part by name + the scene's clips (round 7, scripts/browser.gd)   # top-right of the view: turns with the camera, click a face = that view (round 7)   # S: type to find any command (round 7, scripts/command_search.gd)
var ui_card_btns: Array = []
var _sync := false
var big_view := false
var clean := false          # recording: no highlights, no name tag
var ui_side: Array = []      # the panels Tab hides
var easy: EasyMode           # EASY MODE (scripts/easy_mode.gd): the 12-button bar; Expert = every panel and tool
var ui_top_bar: Control      # the top strip (Easy hides it and shows its own bar)

## ROOM TO WORK (round 35a, GATES QQ4; Nick 10-16 "not like fusion that is more minimalist, more space to design"):
## each side panel folds to a RAIL_W rail (one click on its << / >>; the rail's own button opens it), the bottom panel
## folds to the timeline and the play row (when the scene has clips; an empty scene's start row stays). Remembered.
## A user's first start: both sides folded (FOLD_DEFAULT); tests start open (as they start in the dark theme).
## lw() / rw(): what the left / right side takes from the view now (0 in the big view)
const RAIL_W := 40
const FOLD_DEFAULT := {"left": true, "right": true, "bottom": true}
var fold := {"left": false, "right": false, "bottom": false}
var ui_rails := {}      # "left" / "right" -> the rail (a PanelContainer)
var ui_fold_btn := {}   # "left" / "right" / "bottom" / "bottom_open" -> its fold button
var ui_side_of := {}    # "left" / "right" -> the panel


func lw() -> float:
	return 0.0 if big_view or easy.on else float(RAIL_W if fold["left"] else LEFT_W)


func rw() -> float:
	return 0.0 if big_view or easy.on else float(RAIL_W if fold["right"] else RIGHT_W)


func _fold(which: String, on: bool, save := true) -> void:
	fold[which] = on
	_sides_apply()
	_layout_bottom()
	_fit_rows.call_deferred()
	if save:
		var cf := ConfigFile.new()
		cf.load(settings)
		cf.set_value("layout", "fold_" + which, on)
		cf.save(settings)


## every side piece shown or hidden, and everything that sits beside the panels moved to the view's new edges
func _sides_apply() -> void:
	for k in ui_side_of:
		ui_side_of[k].visible = not big_view and not fold[k] and not clean and not easy.on
		if ui_rails.has(k):
			ui_rails[k].visible = not big_view and fold[k] and not clean and not easy.on
		if ui_fold_btn.has(k):
			ui_fold_btn[k].visible = not big_view and not fold[k] and not clean and not easy.on
	if ui_status == null:
		return
	for c in [ui_bar, ui_graph]:
		c.offset_left = lw() + 12
		c.offset_right = -rw() - 12
	_place_akey_frame()
	_strip_fit()
	if ui_find != null:
		ui_find.offset_left = lw() + 12
		ui_find.offset_right = lw() + 12 + 420
	if ui_hist != null:
		ui_hist.offset_left = -rw() - 12 - 300
		ui_hist.offset_right = -rw() - 12
	_place_cube()
	_place_nav()
	_cam()


## THE SAY STRIP FITS ITS WORDS (QQ4): it was the view's whole width for one short line; now its width is the text's
## (and the close x), up to the view's width, where it wraps as before
## RR5: the teaching strip (WELCOME, first start) is the yellow box above the line; anything else is said on the line
## itself: small, grey, one line, left of the camera bar; a STOP reason in amber
const LINE_FS := 13


func _status_look() -> void:
	var teach := ui_status.text == WELCOME
	ui_status.add_theme_stylebox_override("normal", ui_say_box if teach else StyleBoxEmpty.new())
	ui_status.add_theme_font_size_override("font_size", 16 if teach else LINE_FS)
	ui_status.add_theme_color_override("font_color", Tok.c("say") if teach else (Tok.c("warn") if ui_status.text.contains("STOPPED") else Tok.of("text:0.7")))
	ui_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hx := ui_status.get_node_or_null("hints_close")
	if hx != null:
		hx.visible = teach
	if not teach and ui_status.text != "" and _teach_pending:
		_taught()


## the first start is over: the first thing said after the welcome (a pick, a drag, a key) ends it, for good
var _teach_pending := false


func _end_teach() -> void:
	if ui_status != null and ui_status.text == WELCOME:
		_say_plain("")
	if _teach_pending:
		_taught()


func _taught() -> void:
	_teach_pending = false
	var cf := ConfigFile.new()
	cf.load(settings)
	cf.set_value("look", "taught", true)
	cf.save(settings)


func _strip_fit() -> void:
	if ui_status == null:
		return
	_status_look()
	if ui_status.text != WELCOME:
		_line_fit()
		return
	ui_status.offset_top = -bottom_h - 82
	ui_status.offset_bottom = -bottom_h - 40
	var room := get_viewport().get_visible_rect().size.x - lw() - rw() - 24
	var f := ui_status.get_theme_font("font")
	var fs := ui_status.get_theme_font_size("font_size")
	var w := f.get_string_size(ui_status.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12 + 34
	# one line when it fits (a measured width + autowrap can break the last word onto a 2nd line that grows the
	# strip down into the scene panel); it wraps only when longer than the view is wide
	ui_status.autowrap_mode = TextServer.AUTOWRAP_OFF if w <= room else TextServer.AUTOWRAP_WORD_SMART
	ui_status.anchor_right = 0.0
	ui_status.offset_left = lw() + 12
	ui_status.offset_right = lw() + 12 + minf(w, room)


func _rail(which: String, title: String) -> void:
	var r := PanelContainer.new()
	r.name = "rail_" + which
	r.offset_top = TOP_H + 6
	r.anchor_bottom = 1.0
	r.offset_bottom = -BOTTOM_H - 6
	if which == "left":
		r.offset_left = 6
		r.offset_right = RAIL_W
	else:
		r.anchor_left = 1.0
		r.anchor_right = 1.0
		r.offset_left = -RAIL_W
		r.offset_right = -6
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.c("panel")
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(2)
	r.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	r.add_child(v)
	var b := _button(">>" if which == "left" else "<<", _fold.bind(which, false), "open the %s panel" % title.to_lower())
	_rail_slim(b)
	b.name = "open_" + which
	v.add_child(b)
	# the name, one letter a line (a rail is too thin for a word); a click on it opens the panel too
	var t := Button.new()
	t.name = "rail_name_" + which
	t.flat = true
	t.focus_mode = Control.FOCUS_NONE
	t.text = "\n".join(title.split(""))
	t.tooltip_text = "open the %s panel" % title.to_lower()
	t.pressed.connect(_fold.bind(which, false))
	_rail_slim(t)
	v.add_child(t)
	r.visible = false
	ui_root.add_child(r)
	ui_rails[which] = r


func _rail_slim(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 14)
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(4)
		b.add_theme_stylebox_override(st, e)


func _fold_button(which: String) -> void:
	var b := _button("<<" if which == "left" else ">>", _fold.bind(which, true), "fold this panel to a thin rail: more room for the body (remembered)")
	b.name = "fold_" + which
	b.flat = true
	b.offset_top = TOP_H + 8
	b.offset_bottom = TOP_H + 8 + 26
	if which == "left":
		b.offset_left = LEFT_W - 34
		b.offset_right = LEFT_W - 6
	else:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_left = -6 - 18 - 30   # left of the panel's scroll bar
		b.offset_right = -6 - 18
	ui_root.add_child(b)
	ui_fold_btn[which] = b
# THE TARGET DUMMY (Nick 10-13): a second mannequin out front; red where the weapon is in it (scripts/dummy.gd)
var T := Dummy.new()
var ov := Overlays.new()    # motion trail (T) and onion skin (O): scripts/overlays.gd
var trail_edit := TrailEdit.new()   # ROADMAP 69: the key dots on a pinned trail are drag handles: scripts/trail_edit.gd
var wt := WeaponTrail.new()   # WEAPON TRAILS (ROADMAP 35): the blade's sweep ribbon and the smear frames: scripts/weapon_trail.gd
var loa := LineOfAction.new()   # ROADMAP 23: sketch a line of action -> pose (scripts/line_of_action.gd)
var rings := RangeRings.new()   # ROADMAP 38: floor rings at the picked fighter's reach, the other fighter inside or not (scripts/range_rings.gd)
var bal := BalanceView.new()   # LIVE BALANCE (Shift+B, round 43 YY1): the feet's support and the COM over them
var ui_tween: HSlider
var ui_hist: PanelContainer        # UNDO HISTORY (round 11, #75)
var ui_hist_list: VBoxContainer
var ui_hist_btn: Button
const HIST_SHOWN := 10             # ROADMAP 45: the History panel lists the newest 10 steps
var ui_undo_btn: Button            # ROADMAP 45: its tooltip is "Undo: <the step it takes back>"
var ui_redo_btn: Button
var _step_hint := ""   # what the user just pressed (a button's text, a command's name, a shortcut's command): the undo
                       # step's name when nothing is said about it (#75)
const KEY_WORD := {KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_COMMA: ",", KEY_PERIOD: ".", KEY_MINUS: "-", KEY_EQUAL: "="}
var _previews := {}   # finding -> the cards its fix would write (Fixer.propose), for the hover ghost; cleared each Check
var _pv_job := {}     # the preview being worked out off the main thread: {f, task, scene, out} (a fix can take seconds)
var _pv_hover := {}   # the finding whose Fix button the mouse is on ({} = none)
var _pv_gen := 0      # bumped by every Check: a job started before it is stale
var ui_pole_row: HBoxContainer   # "points": swing the elbow / knee, the hand / foot held (round 10, GATES Q5)
var ui_ease: OptionButton   # the picked card's ease preset (round 10, GATES Q2)
var ui_ease_bias: HSlider   # ROADMAP 55: the picked card's Slow in / Slow out slider (Play options)
var ui_spline: CheckBox
var ui_loop: CheckBox
var _tween_armed := false   # one undo step per drag of the tween slider
var _ease_bias_armed := false   # ROADMAP 55: one undo step per drag of the card's "Slow in ... Slow out" slider
var stepped_view := false   # STEPPED preview (blocking): the scene plays card to card with no in-betweens; never saved
var ui_bp: PanelContainer   # the bottom panel (the scene)
var ui_card_row: ScrollContainer
var ui_play_row: HBoxContainer
var _band_sig := ""   # YY7: what the curve editor's people band was measured on (part + the scene's cards and keys)
var ui_curve: CurveEditor   # CURVE EDITOR (XX2): the picked part's part keys as curves, made on first use
var ui_graph: Control       # SPEED GRAPH: tip / hips / head speed over the scene, cards marked, click to scrub
var ui_tools: MenuButton
var ui_timeline: Timeline
## PULLING a hand / foot (or the locked bat's hand): the point the mouse has dragged it to, kept for the whole drag.
## Each move reaches for THIS point; before, it reached for "where the hand is + this move", so whatever the limb
## could not follow (end of reach, the body in the way) was lost: mouse back where it grabbed, the left hand ended
## 516 mm away, a foot 673 (tests/hand_drag_test.gd). NAN = not set (a new drag sets it on its first move)
var pv_in := -1.0    # WW4 PREVIEW RANGE: in / out seconds, -1 = not set. A view setting: never saved, never an undo step
var pv_out := -1.0
var frames_view := false   # WW4: the time readout in frames ("44 / 103 f") instead of seconds; a view setting
var _grab := Vector3(NAN, NAN, NAN)   # the scene as one strip: drag edges to retime, click a block to pick it (scripts/timeline.gd)    # "Animator tools": the round-5 tools in one menu (the bottom row is full)
var _pd := {}   # ROADMAP 41 (scripts/part_drag.gd): the plain drag's handle on the pressed part; {} = none
var _pd_mp := Vector2(NAN, NAN)   # the mouse as the last move left it (the drag pulls the handle to its ray)
var _magnet := ""   # the last hand drag's magnet step (GripMagnet.drag): what the status line says
var ik_contact := false   # ROADMAP 88: on, a hand dragged with a wall / table in the set slides along it (ContactIK), not through
var _sm := {}   # the sample the last Check took of S (a Fix re-uses it instead of re-playing the scene)
var _fixing := false
var ui_find: PanelContainer   # CHECK: the rulebook's findings (scripts/rulebook.gd), each one a button to its moment
var ui_find_list: VBoxContainer
var findings := []
const DetailTool := preload("res://tools/detail.gd")
var dummy_on := true
var dummy_node: Node3D
# THE SET (round 37, SS5 / SS6): the scene's props (S.props) shown under ui_props_root; one picked (sel_prop, -1 none)
const Importer := preload("res://scripts/importer.gd")
const LIBRARY := "user://library"
var library := LIBRARY        # a test's own: user://zz_lib_<pid>, removed on exit
var ui_props_root: Node3D
var sel_prop := -1
var _prop_drag := {}
var ui_prop_btns := {}
var ui_use_btns := {}         # TT3: Sit here / Step up (greyed by the picked prop's kind)
const SIT_ON := ["chair", "stool", "bench"]
const STEP_ON := ["box", "crate", "step", "stairs"]
const REACH := 0.12          # UU2: a hand this close to a prop (m, its surface to the prop's) can take hold of it
const TWO_HANDS := ["box", "crate", "moving_box"]   # held in both hands when both are near
var _pick_t := INF            # how far along the ray _pick's part was (a prop in front of it wins the click)
var dummy_mat: StandardMaterial3D
var hit_tag: Label3D
var hit_dot: MeshInstance3D
var ui_dummy: Label
var solid := true            # the dummy stops the weapon (the scene plays as landed: impact + rebound)
var SL: Scene = null         # that landed scene (Dummy.landed), rebuilt when the scene or the dummy changes


## KEYBOARD ONLY (round 14, U4, item 83). The mouse never gives a control focus (every button is FOCUS_NONE), so
## Space / Enter / Tab stay the view's keys (play, add a card, big view). F6 enters the panels: every control can take
## focus, the first one has it; Tab / Shift+Tab move in reading order (the tree's: top bar, left, right, the scene row,
## then CHECK and HISTORY); Enter / Space press; Esc gives the keys back to the view. A press that rebuilds a row
## (picking a card) frees the focused control: focus goes back to the control at the same NAME path (U2).
var kb_nav := false
var _kb_was := {}      # instance id -> its focus mode before (put back on Esc). Ids, not the controls: a rebuilt
                       # row frees its controls, and iterating freed objects as dictionary keys hung the window
var _kb_path := ""     # the focused control's path (names only), to find it again after a rebuild


static func _kb_kind(n: Node) -> bool:
	return (n is BaseButton or n is Range or n is LineEdit) and not (n is ScrollBar) and not (n is ProgressBar) 		and not Names.internal(n)


func _kb_take(c: Control) -> void:
	if not _kb_was.has(c.get_instance_id()):
		_kb_was[c.get_instance_id()] = c.focus_mode
	c.focus_mode = Control.FOCUS_ALL


func _kb_enter() -> void:
	kb_nav = true
	var all := []
	_kb_walk(ui_root, all)
	for c in all:
		_kb_take(c)
	var first: Control = ui_ribbon_tabs["POSE"]
	first.grab_focus()
	_say("KEYBOARD: Tab / Shift+Tab move from control to control, Enter or Space presses, Esc gives the keys back to the view")


func _kb_walk(n: Node, out: Array) -> void:
	for c in n.get_children(false):
		if c is Control and _kb_kind(c):
			out.append(c)
		_kb_walk(c, out)


func _kb_leave() -> void:
	kb_nav = false
	get_viewport().gui_release_focus()
	for id: int in _kb_was:
		var c := instance_from_id(id)
		if c is Control:
			(c as Control).focus_mode = _kb_was[id]
	_kb_was = {}
	_kb_path = ""
	_say("keys back to the view: Space plays, Tab = big view.  F6 = the panels by keyboard again")


## called every frame in keyboard mode: remember where focus is; find it again if a rebuild took it away
func _kb_poll() -> void:
	if not kb_nav:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null and is_ancestor_of(f):
		_kb_path = "/".join(Array(String(get_path_to(f)).split("/")).filter(func(x): return not x.begins_with("@")))
	elif _kb_path != "":
		var n: Node = self   # the address by NAMES only: a rebuilt row's containers get new @ numbers
		for part in _kb_path.split("/"):
			n = n.find_child(part, true, false) if n != null else null
		if n is Control and (n as Control).is_visible_in_tree():
			(n as Control).grab_focus()


## HOVER SAYS WHAT IS UNDER THE MOUSE (round 26, GATES GG2, UPGRADES #35): with no button down, the part under the
## mouse is lit HOVER (the selected one keeps SEL) and named on the status line; a press, a drag or a panel ends it
const HOVER := Color(0.92, 0.94, 1.0)   # pale, far from SEL's blue
var hover_part := ""
var hover_fighter := -1   # FIGHTER HOVER: the other fighter (actors_rt index) whose part the mouse is on, -1 none
var hover_fpart := ""     # ... and that part
## THE BAR DOES NOT FLICKER (round 35a, GATES QQ2): the status line names the hovered part through _bar_hover, which
## takes hover_part only once it has RESTED: BAR_REST on a part, BAR_LEAVE off the body (so a pointer crossing the
## body names nothing, and one sliding off a part for an instant does not wipe its name). The light on the body is
## still instant; only the words wait. QQ1's record: a mouse moved over the body flipped the bar 15 times in 4 s.
const BAR_REST := 0.15
const BAR_LEAVE := 0.3
var _bar_hover := ""
var _bar_want := ""
var _bar_want_t := 0.0


func _hover_at(p: Vector2) -> void:
	var j := _pick(p)   # only called with no drag on (a drag's motion goes to the drag)
	var fk := -1   # FIGHTER HOVER: a part of another fighter nearer than the active one's (the click's rule, _unhandled_input)
	var fj := ""
	var pa := _pick_actor(p) if actors_rt.size() >= 2 else [-1, "", INF]
	if int(pa[0]) >= 0 and (j == "" or float(pa[2]) < _pick_t):
		fk = int(pa[0])
		fj = String(pa[1])
		j = ""
	if j != hover_part or fk != hover_fighter or fj != hover_fpart:
		hover_part = j
		hover_fighter = fk
		hover_fpart = fj
		_refresh()


## the fighter hover off (a press, a panel, the mouse gone): nothing of another fighter is lit
func _fh_clear() -> void:
	hover_fighter = -1
	hover_fpart = ""


## WHAT LIGHT A PART HAS NOW (one name, the strongest wins): "sel" (picked, or a member of the picked group), "hover"
## (what a click would pick), "lock", "touch" (it collides), "limit" (a joint at its stop), "" none. A selected locked
## part reads "sel" (its look mixes the lock in, _look_of). touching: the parts in contact this refresh (_refresh)
func part_look(j: String, touching := {}) -> String:
	if j == sel or sel_more.has(j):
		return "sel"
	if j == hover_part:
		return "hover"
	if locked_parts.has(j):
		return "lock"
	if touching.has(j):
		return "touch"
	if j in Body.ORDER and B.P.has(j) and not B.at_limit(j).is_empty():
		return "limit"
	return ""


## the colour part j's skin is lit with now (a = its strength); clear when it has no light (tests read this)
func skin_col(j: String) -> Color:
	var lk: Array = skp.look_of(j)
	return lk[0] if not lk.is_empty() else Color(0, 0, 0, 0)


## a light's look on the skin: [Color (Tok token, a = how much of the skin it covers), rim strength]. The picked part is
## the strongest, with a full rim along its silhouette and border; the hover is the same, fainter; the warnings (limit,
## touch, lock) only tint, no rim, so a hand at its limit never reads as picked
func _look_of(lk: String) -> Array:
	match lk:
		"sel":
			return [Color(Tok.c("pick_sel"), 0.42), 1.0]
		"hover":
			return [Color(Tok.c("pick_hover"), 0.22), 0.6]
		"lock":
			return [Color(Tok.c("pick_lock"), 0.35), 0.0]
		"touch":
			return [Color(Tok.c("pick_touch"), 0.35), 0.0]
		"limit":
			return [Color(Tok.c("pick_limit"), 0.28), 0.0]
	return []


## LOCK A PART (round 26, GATES GG3, UPGRADES #24): a locked part is picked but never grabbed, keeps its angles through
## every edit (_do and a drag's reach put them back), and is drawn LOCK_COL. View state only: never in a pose or scene
const LOCK_COL := Color(0.5, 0.5, 0.55)
var locked_parts := {}
var ui_lock_btn: Button
var _drag_locks := {}


## HIDE A PART (round 30, GATES KK1, UPGRADES #24): the Browser's eye. The part's piece of the mannequin (split at load,
## Overlays.split_parts), its capsule and dot are not drawn and a click goes through it. View state only, like a lock:
## no undo step, never in a pose or scene file
var pieces := {}         # part -> its piece of the mannequin
var skp := SkinPick.new()  # PRECISE PICK: the ray against the posed skin, and the part's own skin lit (scripts/skin_pick.gd)
var pick_us := 0           # how long the last _pick took (microseconds): the hover's cost, read by precise_pick_test
var wp := {}             # WEIGHT PAINT (ROADMAP 72): the mannequin's skin weights, scripts/skin_paint.gd
var wp_on := false
var wp_bind := -1        # the skin bind index of the bone the brush works on
var wp_mode := "add"     # add | subtract | smooth
var wp_radius := 0.08    # metres, on the skin
var wp_strength := 0.25  # per dab, at the centre
var wp_stroke := false
var wp_key := "mannequin"  # the sidecar's name under user://weights
var wp_centres := []     # the brush centres of the last stroke (the test reads them)
var wp_row: HBoxContainer   # the Bone / Brush / size / strength row, shown while Weight paint is on
var wp_bone_pick: OptionButton
var wp_mode_pick: OptionButton
var corr := Corrective.new()   # ROADMAP 71: the elbow / knee corrective on the body's pieces (View > Display)
var dummy_corr := Corrective.new()   # the same on the dummy
var hidden_parts := {}


## every part in js hidden (on) or shown; one line on the bar
func _set_hidden(js: Array, on: bool) -> void:
	for j in js:
		if on:
			hidden_parts[j] = true
		else:
			hidden_parts.erase(j)
	_refresh()
	_say_plain(("%s hidden: a click goes through it (the eye in the Browser shows it again)" if on else "%s shown") % (nice(js[0]).capitalize() if js.size() == 1 else "%d parts" % js.size()))


## every part in js locked (on) or free: the folder row's lock
func _set_locked(js: Array, on: bool) -> void:
	for j in js:
		if on:
			locked_parts[j] = true
		else:
			locked_parts.erase(j)
	_refresh()
	_say_plain(("%s locked: they keep their pose while you change the rest" if on else "%s unlocked") % ("%d parts" % js.size()))


func _toggle_lock(j := "") -> void:
	if j == "":
		j = sel
	if j in Body.WEAPON:
		_say_plain("the weapon has its own lock: L locks it to the hand")
		return
	if locked_parts.has(j):
		locked_parts.erase(j)
	else:
		locked_parts[j] = true
	_refresh()
	_say_plain(("%s locked: it keeps its pose while you change the rest (Unlock: right-click it, or S 'unlock')" if locked_parts.has(j) else "%s unlocked") % nice(j).capitalize())


func _lock_snap() -> Dictionary:
	var d := {}
	for j in locked_parts:
		d[j] = B.ang[j]
	return d


## the locked parts back to the angles in snap; true if any had moved
func _lock_keep(snap: Dictionary) -> bool:
	var moved := false
	for j in snap:
		if locked_parts.has(j) and not (B.ang[j] as Vector3).is_equal_approx(snap[j]):
			B.ang[j] = snap[j]
			moved = true
	if moved:
		B.fk()
	return moved


## the status line, without naming an undo step (_say names the newest unnamed one)
func _say_plain(t: String) -> void:
	if ui_status != null:
		ui_status.text = t
		ui_status.visible = hints_on or t != ""
		_strip_fit()


## TYPE THE ANGLE WHILE DRAGGING (round 27, GATES HH1, UPGRADES #29): during a drag on a body part, digits - . and
## Backspace type the current axis' angle (it is the part's angle at once, clamped by the joint); Tab = the next axis;
## Enter (or the release) ends the drag, one undo step; Esc cancels it. Read in _input: before the GUI takes Tab
const NUM_AXES := ["bend", "side", "twist"]
var _num_on := false
var _num_axis := 0
var _num_text := ""
var _num_start := {}


## true if the key was the typed angle's
func _num_key(k: InputEventKey) -> bool:
	if dragging != "joint" or sel in Body.WEAPON:
		return false
	var ch := ""
	if k.keycode >= KEY_0 and k.keycode <= KEY_9:
		ch = str(k.keycode - KEY_0)
	elif k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
		ch = str(k.keycode - KEY_KP_0)
	elif k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		ch = "-"
	elif k.keycode in [KEY_PERIOD, KEY_KP_PERIOD]:
		ch = "."
	match k.keycode:
		KEY_TAB:
			_num_on = true
			_num_axis = (_num_axis + 1) % 3
			_num_text = ""
		KEY_BACKSPACE:
			if not _num_on:
				return false
			_num_text = _num_text.left(-1)
			_num_apply()
		KEY_ENTER, KEY_KP_ENTER:
			if not _num_on:
				return false
			dragging = ""
			_num_on = false
			_after_edit()
			_autokey_card()
		KEY_ESCAPE:
			B.set_state(_num_start)
			_drop_undo()
			dragging = ""
			_num_on = false
			_refresh()
			_say_plain("drag cancelled: the %s is back as it was" % nice(sel))
		_:
			if ch == "":
				return false
			_num_on = true
			_num_text += ch
			_num_apply()
	_refresh()
	return true


func _num_apply() -> void:
	if not _num_text.is_valid_float():
		return   # "-" or "." alone: wait for a digit
	var v: Vector3 = B.ang[sel]
	v[_num_axis] = _num_text.to_float()
	B.set_ang_safe(sel, v)
	_after_edit()


## A NAVIGATION BAR (round 27, GATES HH2, UPGRADES #23): a 2 x 3 block under the ViewCube at the view's right edge
## (first at the bottom centre: it sat over the feet at the opening view, hover_test caught it). Orbit and Pan
## are tools (while on, a left drag in the view orbits / pans; Esc or the button again = off); - + zoom; Fit frames the
## body (and the weapon when out) inside the view the panels leave; Grid shows / hides the floor grid. No undo steps
const NAV_H := 28   # one button's height
const NAV_W := 30   # RR4: an icon (was a 50-px word)
var ui_nav: GridContainer
var nav_tool := ""
var grid_node: MeshInstance3D


func _build_nav() -> void:
	ui_nav = GridContainer.new()
	ui_nav.name = "nav_bar"
	ui_nav.columns = 6   # RR4: one small icon bar at the view's bottom centre (Fusion's); was a 2 x 3 block under the cube
	ui_nav.add_theme_constant_override("h_separation", 2)
	for b in [["nav_orbit", "Orbit", func(): _nav_set("orbit" if nav_tool != "orbit" else ""), "while on, a left drag turns the view round the body (Esc: off)", true, "orbit"],
			["nav_pan", "Pan", func(): _nav_set("pan" if nav_tool != "pan" else ""), "while on, a left drag slides the view (Esc: off)", true, "pan"],
			["nav_out", "Zoom out (-)", _nav_zoom.bind(1.0 / 0.8), "zoom out", false, "zoom_out"],
			["nav_in", "Zoom in (+)", _nav_zoom.bind(0.8), "zoom in", false, "zoom_in"],
			["nav_fit", "Fit", _nav_fit, "frame the whole body (and the weapon) in the view", false, "fit"],
			["nav_grid", "Grid", _nav_grid, "show or hide the floor grid", true, "grid"]]:
		var bt := _button(b[1], b[2], b[3])
		bt.name = b[0]
		bt.toggle_mode = b[4]
		bt.focus_mode = Control.FOCUS_NONE
		_icon_only(bt, b[5], Vector2(NAV_W, NAV_H))
		ui_nav.add_child(bt)
	(ui_nav.get_node("nav_grid") as Button).set_pressed_no_signal(true)
	ui_root.add_child(ui_nav)
	_place_nav()


## RR4 / RR5: at the status line's RIGHT end (the cube stands alone at the top right). Not the bottom centre the gate
## first said: the opening view frames the whole body there and the bar covered its feet (HH2: the bar covers no part)
const LINE_H := 32   # the status line's band above the scene panel


func _place_nav() -> void:
	if ui_nav == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var w := 6 * NAV_W + 5 * 2
	ui_nav.offset_right = vs.x - 12
	ui_nav.offset_left = ui_nav.offset_right - w
	ui_nav.offset_top = vs.y - bottom_h - 6 - LINE_H + (LINE_H - NAV_H) * 0.5
	ui_nav.offset_bottom = ui_nav.offset_top + NAV_H
	_line_fit()


## the line's two texts left of the camera bar: the messages from the view's left edge, the readout right-aligned
## against the bar; the readout keeps its whole width up to half the room, the messages get the rest (each clipped
## with an ellipsis)
func _line_fit() -> void:
	if ui_status == null or ui_bar == null or ui_nav == null:
		return
	var y0 := -bottom_h - 6 - LINE_H
	var x0 := lw() + 12
	var x1 := ui_nav.offset_left - 14
	var f := ui_bar.get_theme_font("font")
	var need := f.get_string_size(ui_bar.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ui_bar.get_theme_font_size("font_size")).x + 4
	var split := maxf(x1 - minf(need, (x1 - x0) * 0.5), x0)
	ui_bar.anchor_left = 0.0
	ui_bar.anchor_right = 0.0
	ui_bar.offset_left = split   # as wide as its words (or half the room): the rest of the line is the view's
	ui_bar.offset_right = x1
	ui_bar.offset_top = y0
	ui_bar.offset_bottom = -bottom_h - 6
	if ui_status.text != WELCOME:
		ui_status.autowrap_mode = TextServer.AUTOWRAP_OFF
		ui_status.clip_text = true
		ui_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ui_status.anchor_right = 0.0
		ui_status.offset_left = lw() + 12
		var fs := ui_status.get_theme_font("font")
		var said := fs.get_string_size(ui_status.text, HORIZONTAL_ALIGNMENT_LEFT, -1, LINE_FS).x + 4
		ui_status.offset_right = minf(lw() + 12 + said, split - 16)   # as wide as its words
		ui_status.offset_top = y0
		ui_status.offset_bottom = -bottom_h - 6


func _nav_set(t: String) -> void:
	nav_tool = t
	(ui_nav.get_node("nav_orbit") as Button).set_pressed_no_signal(t == "orbit")
	(ui_nav.get_node("nav_pan") as Button).set_pressed_no_signal(t == "pan")
	_say_plain({"orbit": "Orbit: a left drag turns the view.  Esc or Orbit again: back to posing", "pan": "Pan: a left drag slides the view.  Esc or Pan again: back to posing"}.get(t, "back to posing: a left drag turns a part"))


func _nav_zoom(f: float) -> void:
	dist = clampf(dist * f, 0.5, 12.0)
	_cam()


## the body (and the weapon when out) framed in the CLEAR view: between the ribbon and the say-line, between the left
## panel and the cube / nav strip (no panels in the big view). Projected, then the distance and the centre corrected (3 passes: depth makes one
## pass approximate). The pivot moves to the body's middle, as Fusion's Fit does
const FIT_FILL := 0.85


func nav_clear_rect() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var x0 := lw()
	var x1 := vs.x - rw() - (ViewCube.SIZE + 24)   # the cube's strip (RR4: the nav bar is at the bottom, under the say-line's band)
	return Rect2(x0, TOP_H, x1 - x0, vs.y - bottom_h - 88 - TOP_H)   # above the say-line


func fit_points() -> Array:
	var out := []
	for j in Body.BODY + (Body.WEAPON if B.wep_on else []):
		var c: Array = B.cap(j)
		out.append_array([c[0], c[1]])
	return out


func _nav_fit() -> void:
	var pts := fit_points()
	var mid := Vector3.ZERO
	for q in pts:
		mid += q
	target = mid / pts.size()
	var clear := nav_clear_rect()
	var vs := get_viewport().get_visible_rect().size
	for it in 4:
		_cam()
		var r := Rect2(cam.unproject_position(pts[0]), Vector2.ZERO)
		for q in pts:
			r = r.expand(cam.unproject_position(q))
		r = r.grow(14.0)   # the capsules' thickness on screen
		var need := maxf(r.size.x / clear.size.x, r.size.y / clear.size.y) / FIT_FILL
		var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / vs.y
		var d := clear.get_center() - r.get_center()
		target -= cam.global_basis.x * d.x * mpp - cam.global_basis.y * d.y * mpp
		dist = clampf(dist * need, 0.5, 12.0)
	_cam()


func _nav_grid() -> void:
	grid_node.visible = not grid_node.visible
	(ui_nav.get_node("nav_grid") as Button).set_pressed_no_signal(grid_node.visible)


## SEVERAL PARTS AT ONCE (round 28, GATES II1, UPGRADES #66): sel is the part the panel shows and the drag holds;
## sel_more are the others in the group. Ctrl+click (no motion) adds a part, or takes a member out; a plain press off
## the group starts a new one; a drag turns every member by the change of sel's angles (each through set_ang_safe)
var sel_more: Array = []
var _group_sel := ""   # the sel the group was made for: anything else that moves sel (the ring, a list, a key) ends it
var _gp := {}   # the press: {part, ctrl, at, group before}


func group() -> Array:
	return [sel] + sel_more


func _group_press(j: String, ctrl: bool, at: Vector2) -> void:
	var g := group()
	_gp = {"part": j, "ctrl": ctrl, "at": at, "was": g}
	_group_sel = j
	if j in Body.WEAPON:
		sel_more = []
	elif ctrl or g.has(j):
		sel_more = g.filter(func(x): return x != j and not x in Body.WEAPON)   # added for now; a still release decides
	else:
		sel_more = []


## a Ctrl press that did not move: it was a click. A member's click takes it out; the press's empty step goes
func _group_release(at: Vector2) -> void:
	var gp := _gp
	_gp = {}
	if not gp["ctrl"] or at.distance_to(gp["at"]) >= 4.0:
		return
	_drop_undo()   # a selection change is not an edit
	var was: Array = gp["was"]
	var j: String = gp["part"]
	if was.has(j) and was.size() > 1:
		var rest := was.filter(func(x): return x != j)
		sel = rest.back()
		sel_more = rest.slice(0, rest.size() - 1)
		_group_sel = sel
	_refresh()
	_say_plain("%d parts selected: drag any of them to turn them all (Ctrl+click: add / take out; a plain click: one part)" % group().size() if group().size() > 1 else "one part selected")


## the members follow sel's change of angles
func _group_follow(before: Vector3) -> void:
	if sel_more.is_empty() or sel in Body.WEAPON:
		return
	var d: Vector3 = (B.ang[sel] as Vector3) - before
	if d.is_zero_approx():
		return
	for j in sel_more:   # a locked member: the drag's _lock_keep, right after, puts it back
		B.set_ang_safe(j, (B.ang[j] as Vector3) + d)
	B.fk()
	_refresh()


## SELECTION SETS (round 28, GATES II2, UPGRADES #67): a named group in one go (the first part is the one shown).
## No "both arms": the same change of angles turns the two sides opposite ways (Symmetry is for that)
const SEL_SETS := {"spine": ["spine_01", "spine_02", "spine_03"], "neck and head": ["neck_01", "head"],
	"left arm": ["upperarm_l", "lowerarm_l", "hand_l"], "right arm": ["upperarm_r", "lowerarm_r", "hand_r"],
	"left leg": ["thigh_l", "calf_l", "foot_l"], "right leg": ["thigh_r", "calf_r", "foot_r"]}


func _select_set(parts: Array) -> void:
	if not parts.is_empty():
		sel = parts[0]
	sel_more = parts.slice(1)
	_group_sel = sel
	playing = false
	_refresh()
	_say_plain("%d parts selected (%s): drag any of them to turn them all" % [group().size(), ", ".join(group().map(nice))] if group().size() > 1 else "one part: %s" % nice(sel))


## SCENE VERSIONS (round 29, GATES JJ1, UPGRADES #69): snapshots of the open scene in scenes/_versions/<scene>/vNNN.json
## (the scene list reads only scenes/ itself, so they never show as scenes). Going back to one = its cards into the
## open scene as one undo step; the scene's own file changes only when it is saved
var ui_versions: MenuButton
var _version_paths: Array = []
## COMPARE WITH (ROADMAP 28, scripts/version_diff.gd): an older version laid over the open scene while it is compared:
## {"path", "name", "scene": Scene, "rows": card rows, "marks": frame marks}; {} = not comparing. Nothing is written.
var vdiff := {}
var ui_vdiff: PanelContainer
var ui_vdiff_text: Label


func versions_dir() -> String:
	var nm := safe_file(S.name)
	return "res://scenes/_versions/%s" % (nm if nm != "" else "unnamed")


## the open scene's versions, newest first
func versions() -> Array:
	var out := []
	var d := DirAccess.open(versions_dir())
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with("v") and f.ends_with(".json"):
			out.append(versions_dir() + "/" + f)
	out.sort()
	out.reverse()
	return out


func _save_version() -> void:
	var list := versions()
	var n := 1 if list.is_empty() else (list[0] as String).get_file().get_basename().substr(1).to_int() + 1
	var d := _scene_dict()   # TC3: the hero's file with its actors, whoever is active (the body kept)
	d["version"] = {"n": n, "saved": Time.get_datetime_string_from_system(false, true)}
	var path := "%s/v%03d.json" % [versions_dir(), n]
	_write(path, d)
	_say_plain("version %d of %s kept (%d cards).  Versions, in the scene row, goes back to it" % [n, S.name, S.cards.size()])


## EXPORT TO GAME (round 31, GATES LL2): the scene as the ARPG's PoseTable, exports/<scene>.json + .cs (never scenes/).
## The table is sampled from the scene frame by frame, so the body's pose is kept and put back.
func _export_game(dir := "res://exports") -> Array:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: export to the game needs at least 2 cards (a move)")
		return []
	var acts := _export_actors()
	if not acts.is_empty():   # TC6: one clip per fighter
		var rs := GameExport.write_actors(acts, dir, _export_base())
		_refresh()
		_say_plain("exported to the game, one clip per fighter: %s (each PoseTable in its own frame; its placement is in the .json as \"placement\")" % ", ".join(rs.map(func(r): return (r[0] as String).get_file() + " / " + (r[1] as String).get_file())))
		return rs
	var keep := B.state()
	var out := GameExport.write(S, B, dir)
	B.set_state(keep)
	_refresh()
	var T: Dictionary = out[2]
	var n := 0
	var w := 0.0
	for s in T["tracks"]:
		n += (T["tracks"][s] as Array).size()
		w = maxf(w, T["worst"][s])
	_say_plain("exported to the game: %s (%d keys on 11 bones, within %.2f° of Kine). The hands, feet and fingers do not reach the game" % [(out[0] as String).get_basename() + ".json / .cs", n, w])
	return out


## EXPORT .GLB (round 34, GATES OO1; Nick 10-16: "universal files to use in all engines"): the scene as glTF 2.0,
## exports/<scene>.glb: the mannequin, its skeleton with UE5's bone names, one animation keyed on every frame, the
## weapons as animated nodes. Godot, Blender and Unreal 5 import it as it is; Unity through glTFast (docs/EXPORT.md).
func _export_glb(dir := "res://exports") -> String:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: an animation needs at least 2 cards (a move)")
		return ""
	var acts := _export_actors()
	if not acts.is_empty():   # TC6: every fighter in one file, each armature named by its fighter, at its placement
		var mp := "%s/%s.glb" % [dir, _export_base()]
		var e := GltfExport.write_actors(acts, mp)
		_refresh()
		if e != OK:
			_say_plain("NOT DONE: the .glb could not be written (%s)" % error_string(e))
			return ""
		_say_plain("exported %s: %d fighters (%s), one armature each at its place, one animation. Opens in Godot, Blender, Unreal 5; Unity via glTFast" % [mp.get_file(), acts.size(), ", ".join(acts.map(func(a): return a["name"]))])
		return mp
	var nm := S.name if S.name != "" else "scene"
	var path := "%s/%s.glb" % [dir, nm]
	var keep := B.state()
	var err := GltfExport.write(S, B, path)
	B.set_state(keep)
	_refresh()
	if err != OK:
		_say_plain("NOT DONE: the .glb could not be written (%s)" % error_string(err))
		return ""
	_say_plain("exported %s.glb: %d frames at %d fps, the mannequin and its skeleton (UE5 bone names)%s. Opens in Godot, Blender, Unreal 5; Unity via glTFast" % [nm, int(ceil(S.length() * S.fps - 1e-6)) + 1, S.fps, ", the weapons as nodes" if B.wep_on or B.wep2_on else ""])
	return path


## EXPORT .FBX (ROADMAP 78): the scene as binary FBX 7.4 (FbxExport, the ASCII text is a debug view only): the skeleton with UE5 bone names, one take, the
## rotations and the pelvis on every frame, in centimetres. root_motion (the Unreal preset, "_ue5") moves the pelvis's
## travel onto the root bone. Several fighters: one .fbx each, its rig placed where it stands (a root null). The
## weapons and props are not in it. Blender 4.5 reads this binary file; it cannot read ASCII FBX.
func _export_fbx(dir := "res://exports", root_motion := false) -> String:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: an animation needs at least 2 cards (a move)")
		return ""
	var sfx := "_ue5" if root_motion else ""
	var acts := _export_actors()
	var first := ""
	var bones := 0
	var frames := 0
	if not acts.is_empty():
		for a in acts:
			var p := "%s/%s%s_%s.fbx" % [dir, _export_base(), sfx, safe_file(String(a["name"]))]
			var r := FbxExport.write(a["S"], a["B"], p, root_motion, a["xf"], String(a["name"]))
			if r["err"] != OK:
				_refresh()
				_say_plain("NOT DONE: %s could not be written (%s)" % [p.get_file(), error_string(r["err"])])
				return ""
			if first == "":
				first = p
				bones = (r["bones"] as PackedStringArray).size()
				frames = int(r["keys"])
		_refresh()
		_say_plain("exported %d .fbx, one per fighter, each at its place: %d bones, %d frames at %d fps, UE5 bone names, centimetres, Y up. The weapons are not in them" % [acts.size(), bones, frames, S.fps])
		return first
	var nm := S.name if S.name != "" else "scene"
	var path := "%s/%s%s.fbx" % [dir, nm, sfx]
	var keep := B.state()
	var r2 := FbxExport.write(S, B, path, root_motion)
	B.set_state(keep)
	_refresh()
	if r2["err"] != OK:
		_say_plain("NOT DONE: the .fbx could not be written (%s)" % error_string(r2["err"]))
		return ""
	_say_plain("exported %s.fbx: %d bones, %d frames at %d fps, UE5 bone names, centimetres, Y up%s. The weapons and props are not in it" % [nm, (r2["bones"] as PackedStringArray).size(), int(r2["keys"]), S.fps, ", root motion on the root bone" if root_motion else ""])
	return path


## EXPORT FOR AN ENGINE (ROADMAP item 9): the pre-flight report prints line by line BEFORE the file is written; the
## logic and the checks are in scripts/engine_export.gd (EngineExport), the needs in docs/research/ENGINES.md.
func _export_engine(id: String, dir := "res://exports") -> String:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: an animation needs at least 2 cards (a move)")
		return ""
	var keep := B.state()
	var r: Dictionary = EngineExport.export(S, B, id, dir, func(lines): for l in lines: print(l))   # every line to the console (the log)
	B.set_state(keep)
	_refresh()
	if r["err"] != OK:
		_say_plain("NOT DONE: the file could not be written (%s)" % error_string(r["err"]))
		return ""
	_say_plain("exported %s for %s: %d checks, %d WRONG. %s" % [String(r["path"]).get_file(), EngineExport.preset(id)["label"], (r["lines"] as Array).size(), r["wrong"], EngineExport.preset(id)["needs"]])
	return r["path"]


## EXPORT... (ROADMAP 57): the one dialog for every target (scripts/export_dialog.gd). The old commands stay in the palette.
func _export_dialog_open() -> void:
	if export_ui == null:
		export_ui = ExportDialog.new(self)
	export_ui.open()


## EXPORT PLAYBLAST (VIDEO): the scene from the CURRENT camera, one image per frame at the scene's fps over the preview
## range (or the whole scene), saved as exports/playblast/<scene>_<stamp>/frame_0000.png ... and, when ffmpeg is found
## (PATH, POSER_FFMPEG or the argument), as <scene>.mp4 beside them. Each frame is posed by _ps().apply + _refresh, the
## path play and scrub use, so frame k is what the view shows at its time. The panels are hidden while it renders.
## Returns {"dir", "frames", "mp4", "ffmpeg"}; {} when refused. with_mp4 = false: the PNG frames only (the review page's frames)
func _export_playblast(root_dir := PlayblastExport.ROOT, ffmpeg_path := "", with_mp4 := true) -> Dictionary:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: a playblast needs at least 2 cards (a move): press Enter to add a card, or open a scene in the list below")
		return {}
	var sp := PlayblastExport.span(pv_in, pv_out, _ps().length())
	var fps: int = S.fps
	var n := PlayblastExport.frame_count(sp[0], sp[1], fps)
	var nm := safe_file(S.name) if S.name != "" else "scene"
	var dir := "%s/%s_%s" % [root_dir, nm, _stamp()]
	var gdir := ProjectSettings.globalize_path(dir)
	if DirAccess.make_dir_recursive_absolute(gdir) != OK:
		_say_plain("NOT DONE: the folder %s could not be made: close anything using it, or choose another place, and run Export playblast (video) again" % dir)
		return {}
	var keep := B.state()
	var keep_t := playhead
	var keep_playing := playing
	var keep_clean := clean
	playing = false
	clean = true
	_sides_apply()
	ui_root.visible = false
	var shot := _shot_blast_begin()   # THE SHOT CAMERA: when the scene has one, every frame is ITS view, the 16:9 frame
	for f in n:
		playhead = PlayblastExport.time_of(f, sp[0], sp[1], fps)
		_ps().apply(B, playhead)
		_refresh()
		_shot_blast_frame(shot)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_shot_blast_image(shot, get_viewport().get_texture().get_image()).save_png("%s/frame_%04d.png" % [gdir, f])
	_shot_blast_end(shot)
	ui_root.visible = true
	clean = keep_clean
	_sides_apply()
	B.set_state(keep)
	playhead = keep_t
	playing = keep_playing
	_refresh()
	var ff := PlayblastExport.find_ffmpeg(ffmpeg_path) if with_mp4 else ""
	var mp4 := ""
	var how := ""
	if not with_mp4:
		how = ""
	elif ff == "":
		how = ". No .mp4: ffmpeg was not found; install it (winget install Gyan.FFmpeg, or ffmpeg.org), then run Export playblast (video) again, or set POSER_FFMPEG to ffmpeg.exe"
	elif PlayblastExport.encode(ff, gdir, fps, "%s/%s.mp4" % [gdir, nm], S.audio, sp[0]) == OK and FileAccess.file_exists("%s/%s.mp4" % [gdir, nm]):
		mp4 = "%s/%s.mp4" % [gdir, nm]
		how = " and %s.mp4" % nm
	else:
		how = ". No .mp4: ffmpeg (%s) failed on the frames; the PNGs are fine, run ffmpeg on them yourself" % ff
	_say_plain("playblast: %d PNG frames at %d fps (%s to %s) in %s%s" % [n, fps, Units.time(sp[0], S.fps), Units.time(sp[1], S.fps), dir, how])
	return {"dir": gdir, "frames": n, "mp4": mp4, "ffmpeg": ff}


## REVIEW WITH FRAME COMMENTS (ROADMAP 29; scripts/review.gd): the playblast's frames (the same capture, no mp4, the frames
## kept in a temporary folder and removed after) -> ONE self-contained page, root/<scene>_<date>.html (never over an
## earlier one). Returns the page's path; "" when refused. Nothing leaves the machine.
func _export_review(root_dir := Review.DIR) -> String:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: a review page needs at least 2 cards (a move): press Enter to add a card, or open a scene in the list below")
		return ""
	var fps: int = S.fps
	var first := roundi(PlayblastExport.span(pv_in, pv_out, _ps().length())[0] * float(fps))   # the scene frame of the first page frame
	var rs: Dictionary = await _export_playblast("user://review_frames", "", false)
	if rs.is_empty():
		return ""
	var gdir: String = rs["dir"]
	var n: int = rs["frames"]
	var uris := []
	for f in n:
		var png := "%s/frame_%04d.png" % [gdir, f]
		var u := Review.frame_uri(png)
		if u != "":
			uris.append(u)
		DirAccess.remove_absolute(png)
	DirAccess.remove_absolute(gdir)
	if uris.size() != n:
		_say_plain("NOT DONE: %d of %d frames could not be read back for the page; nothing was written" % [n - uris.size(), n])
		return ""
	var date := Time.get_date_string_from_system()
	var dir_abs := ProjectSettings.globalize_path(root_dir)
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var out := Review.page_path(safe_file(S.name) if S.name != "" else "scene", date, root_dir)
	var fh := FileAccess.open(out, FileAccess.WRITE)
	if fh == null:
		_say_plain("NOT DONE: the page %s could not be written: close anything using it, and run Review: export a review page again" % out)
		return ""
	fh.store_string(Review.html(S.name if S.name != "" else "scene", fps, first, uris, date))
	fh.close()
	_say_plain("review page: %d frames at %d fps in %s. Open it in any browser; comments are kept there, and Download comments writes a .json to import back" % [n, fps, out])
	return out


func _review_import_ask() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json ; review comments"])
	fd.use_native_dialog = true
	fd.title = "Import review comments (.json)"
	fd.file_selected.connect(func(p): _review_import(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## the comments of a review page's .json as notes on this scene: one undo step; the ones already here are not doubled.
## Returns the number added, -1 when refused (the reason on the status line, nothing changed)
func _review_import(path: String) -> int:
	var r := Review.from_comments(FileAccess.get_file_as_string(path))
	if not r["ok"]:
		_say("could not import %s: %s; pick the .json a review page saved" % [path.get_file(), r["why"]])
		return -1
	var before := S.notes.size()
	_push_undo()
	S.notes = Review.merge(S.notes, r["notes"])
	_markers_changed()
	var added := S.notes.size() - before
	_say("imported %d comments from %s as notes on the timeline (%d were already there): click one to jump. Ctrl+Z undoes" % [r["notes"].size(), path.get_file(), r["notes"].size() - added])
	return added


## EXPORT .BVH (round 34, GATES OO2): the scene as exports/<scene>.bvh (BvhExport, the writer tools/export_bvh.gd uses):
## the skeleton with UE5's bone names, every frame, the weapons as joints in their hands. Every retargeter reads BVH.
func _export_bvh(dir := "res://exports") -> String:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: an animation needs at least 2 cards (a move)")
		return ""
	var acts := _export_actors()
	if not acts.is_empty():   # TC6: a BVH holds one skeleton, so one file per fighter, placed by its root channels
		var rs := BvhExport.write_actors(acts, dir, _export_base())
		_refresh()
		var bad := rs.filter(func(r): return r[1] != OK)
		if not bad.is_empty():
			_say_plain("NOT DONE: %s could not be written (%s)" % [(bad[0][0] as String).get_file(), error_string(bad[0][1])])
			return ""
		_say_plain("exported one .bvh per fighter: %s (%d frames at %d fps each, placed where they stand). Opens in Blender, MotionBuilder, Cascadeur and any retargeter" % [", ".join(rs.map(func(r): return (r[0] as String).get_file())), rs[0][2]["frames"], rs[0][2]["fps"]])
		return rs[0][0]
	var nm := S.name if S.name != "" else "scene"
	var path := "%s/%s.bvh" % [dir, nm]
	var r := BvhExport.write(S, B, path)
	_refresh()
	if r[0] != OK:
		_say_plain("NOT DONE: the .bvh could not be written (%s)" % error_string(r[0]))
		return ""
	var info: Dictionary = r[1]
	_say_plain("exported %s.bvh: %d joints, %d frames at %d fps%s. Opens in Blender, MotionBuilder, Cascadeur and any retargeter" % [nm, info["joints"], info["frames"], S.fps, " (the weapons as joints in their hands)" if not BvhExport.weapons_of(S).is_empty() else ""])
	return path


## EXPORT .USDA (round 42, GATES XX9): the scene as exports/<scene>.usda (UsdExport): a UsdSkel SkelRoot, Skeleton and
## SkelAnimation, one time sample per frame. Opens in Blender, Houdini, Maya, usdview, Omniverse.
func _export_usd(dir := "res://exports") -> String:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: an animation needs at least 2 cards (a move)")
		return ""
	var acts := _export_actors()
	if not acts.is_empty():   # TC6: every fighter in one stage, a SkelRoot each at its placement
		var mp := "%s/%s.usda" % [dir, _export_base()]
		var mr := UsdExport.write_actors(acts, mp)
		_refresh()
		if mr[0] != OK:
			_say_plain("NOT DONE: the .usda could not be written (%s)" % error_string(mr[0]))
			return ""
		_say_plain("exported %s: %d fighters (%s), a UsdSkel each at its place, %d frames at %d fps (Y up, metres; the weapons are not in it)" % [mp.get_file(), acts.size(), ", ".join(mr[1]["prims"]), mr[1]["frames"], mr[1]["fps"]])
		return mp
	var nm := S.name if S.name != "" else "scene"
	var path := "%s/%s.usda" % [dir, nm]
	var r := UsdExport.write(S, B, path)
	_refresh()
	if r[0] != OK:
		_say_plain("NOT DONE: the .usda could not be written (%s)" % error_string(r[0]))
		return ""
	_say_plain("exported %s.usda: %d joints, %d frames at %d fps (UsdSkel, Y up, metres; the weapons are not in it)" % [nm, r[1]["joints"], r[1]["frames"], S.fps])
	return path


## EXPORT USD LAYERS (ROADMAP 79, GATES USDL): the scene as exports/<name>_usd/ (UsdExport.write_layers): a root <name>.usda
## whose sublayers are the props and camera, the joint point cache (Points, not Alembic), one override per animation layer,
## the base animation and the skeleton. Returns the root's path ("" when not written). One fighter only: with several, the
## flat Export animation (.usda) holds them all.
func _export_usd_layers(dir := "res://exports") -> String:
	if S.cards.size() < 2:
		_say_plain("NOT NOW: an animation needs at least 2 cards (a move)")
		return ""
	if not _export_actors().is_empty():
		_say_plain("NOT NOW: the layers are one fighter; with several fighters, Export animation (.usda) puts each one in its file")
		return ""
	var nm := S.name if S.name != "" else "scene"
	var r := UsdExport.write_layers(S, B, dir, nm)
	_refresh()
	if r[0] != OK:
		_say_plain("NOT DONE: the layers could not be written (%s); check the exports folder is writable" % error_string(r[0]))
		return ""
	var info: Dictionary = r[1]
	_say_plain("exported %s_usd/: %d layer%s under %s (mute one in your DCC; a lower layer shows only once the one above it is muted), joints in %s_points.usda as a point cache (no Alembic: see the export dialog)" % [
		UsdExport.prim_name(nm), info["layers"], "" if info["layers"] == 1 else "s", (info["root"] as String).get_file(), UsdExport.prim_name(nm)])
	return info["root"]


## TWO CHARACTERS IN THE EXPORTS (round 50, GATES TC6): every fighter, hero first, with its own body, scene and placement
## (its xf in the hero's space); [] with one fighter, and the exports write what they always wrote
func _export_actors() -> Array:
	_actors_sync()
	if actors_rt.size() < 2:
		return []
	return actors_rt.map(func(a): return {"name": a["name"], "S": a["S"], "B": a["B"], "xf": a["xf"]})


## the file name of a multi-fighter export: the hero's scene, whoever is active
func _export_base() -> String:
	var nm := _hero_scene().name
	return safe_file(nm) if nm != "" else "scene"


func _versions_menu() -> void:
	var pm := ui_versions.get_popup()
	pm.clear()
	pm.add_item("Save a version now", 0)
	pm.add_separator()
	_version_paths = versions()
	if _version_paths.is_empty():
		pm.add_item("no versions yet", 1)
		pm.set_item_disabled(pm.item_count - 1, true)
		pm.set_item_tooltip(pm.item_count - 1, "NOT NOW: this scene has no versions yet. 'Save a version now' (above) keeps the scene as it is, to come back to")
	for i in _version_paths.size():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_version_paths[i]))
		var v: Dictionary = d.get("version", {})
		pm.add_item("v%d   %s   %d cards" % [v.get("n", 0), String(v.get("saved", "")).get_slice(" ", 1).left(5), (d.get("cards", []) as Array).size()], 100 + i)
	# COMPARE WITH (ROADMAP 28): ids 50.. compare, 2 stops, 3 restores the one compared (ids 100.. restore a row)
	if not _version_paths.is_empty():
		pm.add_separator()
		for i in mini(_version_paths.size(), 50):
			pm.add_item("Versions: compare with v%d ..." % _version_n(_version_paths[i]), 50 + i)
			pm.set_item_tooltip(pm.item_count - 1, "the version over the open scene: its body as a magenta ghost at the playhead, the changes card by card, and marks on the timeline where a joint differs by more than 2 deg")
	if not vdiff.is_empty():
		pm.add_separator()
		pm.add_item("Versions: restore this one (v%d)" % _version_n(vdiff["path"]), 3)
		pm.set_item_tooltip(pm.item_count - 1, "opens the compared version as the scene's cards, one undo step (the scene's file is not touched)")
		pm.add_item("Versions: stop comparing", 2)


func _version_picked(id: int) -> void:
	if id == 0:
		_save_version()
	elif id == 2:
		_vdiff_clear()
	elif id == 3 and not vdiff.is_empty():
		var p: String = vdiff["path"]
		_vdiff_clear()
		_open_version(p)
	elif id >= 100 and id - 100 < _version_paths.size():
		_open_version(_version_paths[id - 100])
	elif id >= 50 and id < 100 and id - 50 < _version_paths.size():
		_compare_version(_version_paths[id - 50])


func _version_n(path: String) -> int:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int((d.get("version", {}) as Dictionary).get("n", 0)) if d is Dictionary else 0


## COMPARE WITH (ROADMAP 28): the version laid over the open scene (ghost at the playhead, rows, timeline marks)
func _compare_version(path: String) -> void:
	var old := VersionDiff.load_scene(path)
	if old == null:
		_say_plain("NOT NOW: %s will not open as a scene" % path.get_file())
		return
	vdiff = {"path": path, "name": path.get_file().get_basename(), "scene": old}
	_vdiff_update()
	ui_timeline.queue_redraw()
	_refresh()
	var n_rows: int = vdiff["rows"].size()
	_say_plain("comparing with %s: %d change%s, %d frame%s over 2 deg (magenta on the timeline).  Versions: stop comparing, to clear" % [vdiff["name"], n_rows, "" if n_rows == 1 else "s", vdiff["marks"].size(), "" if vdiff["marks"].size() == 1 else "s"])


func _vdiff_clear() -> void:
	vdiff = {}
	ui_vdiff.visible = false
	ui_timeline.queue_redraw()
	_refresh()


## the rows and the frame marks of the compared version against the open scene; the panel's text
func _vdiff_update() -> void:
	if vdiff.is_empty():
		return
	var old: Scene = vdiff["scene"]
	vdiff["rows"] = VersionDiff.card_rows(old, S)
	vdiff["marks"] = VersionDiff.frame_marks(old, S)
	var lines := ["comparing: %s (%d cards)  vs  now (%d cards)" % [vdiff["name"], old.cards.size(), S.cards.size()]]
	if vdiff["rows"].is_empty() and vdiff["marks"].is_empty():
		lines.append("no differences: the two are the same")
	for r in vdiff["rows"]:
		var mark: String = {"added": "+ added    ", "removed": "- removed  ", "retimed": "~ retimed  ", "joints": "~ joints   "}[r["kind"]]
		lines.append("%s%s  %s" % [mark, r["name"], r["detail"]])
	var marks: Array = vdiff["marks"]
	if not marks.is_empty():
		lines.append("frames over 2 deg: %d, %.2f s to %.2f s" % [marks.size(), float(marks[0]["t"]), float(marks[-1]["t"])])
	ui_vdiff_text.text = "
".join(lines)
	ui_vdiff.visible = true


## a version's cards into the open scene: one undo step, the scene then unsaved (its file untouched)
func _open_version(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var V := Scene.new()
	V.from_dict(d)
	_do(func():
		S.cards = V.cards   # the cards only: an undo step holds the cards, not the scene's settings (Natural, Loop)
		sel_card = -1
		S.apply(B, 0.0))
	playhead = 0.0
	ov.mark_dirty()
	wt.mark_dirty()
	_rebuild_cards()
	_refresh()
	_say_plain("back to version %d: %d cards (Ctrl+Z undoes; Save scene keeps it)" % [d.get("version", {}).get("n", 0), S.cards.size()])


func _input(ev: InputEvent) -> void:
	if hk != null and hk.take_input(ev):   # the hotkey editor: a key for the row being set, or Esc closes it
		get_viewport().set_input_as_handled()
		return
	# the gear's box closes on a press outside it and its gear (RR4)
	if ui_gear != null and ui_gear.visible and ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var at := (ev as InputEventMouseButton).position
		if not ui_gear.get_global_rect().has_point(at) and not ui_gear_btn.get_global_rect().has_point(at):
			ui_gear.visible = false
	if (ev is InputEventMouseButton or ev is InputEventKey) and ev.is_pressed() and not ev.is_echo():
		_tour_inputs += 1
		if tour_step >= 0 and ev is InputEventKey and (ev as InputEventKey).keycode == KEY_ESCAPE:
			_tour_end(true)   # Esc closes the tour (QQ3)
			get_viewport().set_input_as_handled()
			return
	if ev is InputEventKey and ev.pressed and not ev.echo and _num_key(ev as InputEventKey):
		get_viewport().set_input_as_handled()
		return
	if nav_tool != "" and ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_nav_set("")
		get_viewport().set_input_as_handled()
		return
	# Esc in keyboard mode: before the focused control sees it (a text box would only drop its caret)
	if kb_nav and ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_kb_leave()
		get_viewport().set_input_as_handled()


## a control's name, once its text is set (it is added first, labelled right after)
func _name_later(n: Node) -> void:
	Names.give(n)


## RECORD (the --record / --playblast flags; GATES WW6): play the scene, one frame per 1/fps, from the clean big view.
## dir: PNG frames go there ("" = none); avi: one MJPEG AVI of the same frames ("" = none); burn: scene name, frame,
## seconds and the Check finding count drawn into each frame. Returns the number of frames.
func _record(dir: String, fps: int, burn: bool, avi: String) -> int:
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	for p in ui_side:
		p.visible = false
	ui_root.visible = false
	clean = true
	big_view = true
	dist = 4.6
	target = Vector3(0, 1.05, 0.2)
	_cam()
	cam.v_offset = 0.0
	var finds := -1
	var layer: CanvasLayer = null
	if burn:
		if S.cards.size() >= 2:
			finds = Rulebook.check(S, ov.GB, Rulebook.sample(S, ov.GB)).size()
		layer = Playblast.make_overlay()
		add_child(layer)
	var jpgs := []
	var n := int(ceil(_ps().length() * fps))
	for f in n + 1:
		playhead = float(f) / fps
		_ps().apply(B, playhead)
		_refresh()
		if layer != null:
			(layer.get_node("burn") as Label).text = Playblast.text(S.name, f, playhead, finds)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if dir != "":
			img.save_png("%s/frame_%04d.png" % [dir, f])
		if avi != "":
			jpgs.append(img.save_jpg_to_buffer(0.9))
	if layer != null:
		layer.queue_free()
	if avi != "" and not jpgs.is_empty():
		var sz := get_viewport().get_visible_rect().size
		AviWriter.write(avi, jpgs, int(sz.x), int(sz.y), fps)
	return n + 1


## SHADING + FPS TRUTH (round 42, GATES XX10): the logic is in scripts/shading.gd
func _shading_next() -> void:
	var nxt := Shading.next_mode(shading.mode)
	shading.set_mode(self, nxt)
	_say("shading: %s (a view setting, not saved in the scene).  Shading: next goes on to %s" % [nxt, Shading.next_mode(nxt)])


## each frame: while playing, count the frames and the dropped ones; the readout beside the time
func _fps_poll(dt: float) -> void:
	if playing and not _was_playing:
		var hz := DisplayServer.screen_get_refresh_rate()
		shading.meter.start(1.0 / (hz if hz > 0.0 else 60.0))
	_was_playing = playing
	if playing:
		shading.meter.feed(dt)
		if ui_fps_lbl != null and shading.meter.frames > 0:
			var t := Shading.fps_text(shading.meter.stats())
			if t != ui_fps_lbl.text:
				ui_fps_lbl.text = t
	# ROADMAP 48: the mode's words and colour; "dropping N frames" while real speed is skipping
	_mode_paint()
	if ui_mode_lbl != null:
		var mt := play_clock.label_now()
		if mt != ui_mode_lbl.text:
			ui_mode_lbl.text = mt
			ui_mode_lbl.add_theme_color_override("font_color", Tok.c("warn") if play_clock.mode == PlaySpeed.REAL and play_clock.dropped > 0 else Tok.c("info" if play_clock.mode == PlaySpeed.REAL else "say"))


## the scene the window plays: landed on the solid dummy, or as authored
func _ps() -> Scene:
	var p: Scene = SL if dummy_on and solid and SL != null else S
	p.stepped = stepped_view   # a view setting: the scene that PLAYS shows it, whichever one that is
	if p != S:
		p.moving_holds = S.moving_holds
	return p


func _ready() -> void:
	# EVERY WIDGET BY NAME (round 14, U2): each control the window builds is named from what it says (scripts/names.gd)
	# at once (a click that rebuilds a row must not leave it nameless for a frame); one with nothing to say yet (its
	# text is set after it is added) gets its name a frame later
	get_tree().node_added.connect(func(n: Node):
		if kb_nav and n is Control and _kb_kind(n):
			_kb_take(n)
		if Names.wants(n):
			if Names.said(n) != "":
				Names.give(n)
			else:
				_name_later.call_deferred(n))
	easy = EasyMode.new()   # first: lw() / rw() read easy.on while the world is built (scripts/easy_mode.gd)
	easy.m = self
	add_child(easy)
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var testing: bool = Engine.get_main_loop().get_script() != null
	if testing:
		settings = "user://poser_test_%d.cfg" % OS.get_process_id()
		autosave = "user://autosave_test_%d.json" % OS.get_process_id()
		library = "user://zz_lib_%d" % OS.get_process_id()
		macros_file = "user://macros_test_%d.json" % OS.get_process_id()   # a test never touches the real macros file
	ui_props_root = Node3D.new()
	ui_props_root.name = "set"
	add_child(ui_props_root)
	_library_load()
	macros = Macros.load_file(macros_file)   # ROADMAP 81
	get_window().files_dropped.connect(_on_drop)
	get_tree().set_auto_accept_quit(false)   # ROADMAP 50: the window's close asks first (_notification below)
	if OS.get_environment("POSER_AUTOSAVE") != "":
		autosave = OS.get_environment("POSER_AUTOSAVE")
	var jenv := OS.get_environment("POSER_JOURNAL")   # a test's own folder (never user://journal)
	journal_on = jenv != "" or not testing
	journal_dir = jenv if jenv != "" else JOURNAL
	if journal_on:
		_journal_boot()
	var cf := ConfigFile.new()
	cf.load(settings)
	# THE THEME (ROADMAP 58): "system" on a first start (Windows' dark mode), or the user's own "light" / "dark". A test
	# starts dark (its settings file is its own); a light flag saved by an older build is the user's explicit choice
	var pref := "dark" if testing else "system"
	if cf.has_section_key("look", "light"):
		pref = "light" if cf.get_value("look", "light", false) else "dark"
	theme_pref = String(cf.get_value("look", "theme", pref))
	if OS.get_cmdline_user_args().has("--light") or OS.get_cmdline_user_args().has("--dark"):   # shots and tests choose
		theme_pref = "light" if OS.get_cmdline_user_args().has("--light") else "dark"
	if theme_pref not in ["system", "light", "dark"]:
		theme_pref = "system"
	Tok.set_dark(_theme_wanted())
	# THE SCALE (ROADMAP 58): the saved one (the user chose it), or a test's 100, or on a first start the screen's pick,
	# made once the ribbon is built (_auto_scale_now). Nothing is saved for the pick: it is made again each start
	var pct := 100 if testing else (int(cf.get_value("look", "scale", 0)) if cf.has_section_key("look", "scale") else 0)
	var si := OS.get_cmdline_user_args().find("--scale")   # shots and tests choose
	if si >= 0 and si + 1 < OS.get_cmdline_user_args().size():
		pct = int(OS.get_cmdline_user_args()[si + 1])
	scale_auto = pct not in SCALES
	ui_scale = pct if pct in SCALES else 100
	while not scale_fits(ui_scale):   # remembered from a bigger screen: the largest that fits this one
		ui_scale = SCALES[SCALES.find(ui_scale) - 1]
	get_window().content_scale_factor = ui_scale / 100.0
	# the smallest window the layout is made for (round 21, GATES BB1): at 1024 x 768 the scene row and the play row ran
	# off the right and the view was ~390 px between the side panels; Windows now stops a drag below it
	get_window().min_size = Vector2i(MIN_ROOM)
	get_viewport().size_changed.connect(func(): _fit_rows.call_deferred(); _fit_top.call_deferred(); _place_nav.call_deferred(); _place_akey_frame.call_deferred(); _strip_fit.call_deferred(); _browser_fit.call_deferred())
	_world()
	_body()
	add_child(ov)
	add_child(wt)
	add_child(bal)
	add_child(loa)
	add_child(rings)
	ov.setup()
	_onion_load()   # ROADMAP 70: the per-part onion options, from the settings file (never poser.cfg in tests)
	wt.setup()
	loa.setup()
	rings.setup()
	hk = Hotkeys.new(self)   # HOTKEYS: the saved keys, applied by _commands() (scripts/hotkeys.gd)
	hk.load_from(settings)
	_ui()
	if scale_auto:
		_auto_scale_now()
	if not testing and not cf.get_value("look", "hints", true):
		_set_hints(false, false)   # remembered (QQ3)
	# RR5: the yellow teaching strip only on a first start (a test's own settings file: its first start, unless the
	# test wrote "taught" into it)
	_teach_pending = not cf.get_value("look", "taught", false)
	if not _teach_pending and ui_status.text == WELCOME:
		_say_plain("")
	for k in fold:   # QQ4: a user's folds, remembered (the first start: FOLD_DEFAULT); a test starts open
		if not testing and cf.get_value("layout", "fold_" + k, FOLD_DEFAULT[k]):
			_fold(k, true, false)
	_fit_rows.call_deferred()
	# not on a scripted shot either (round 13: an agent's screenshot came back with the tour card over the body)
	easy.build(ui_root, [ui_top_bar, ui_cube, ui_nav, ui_bh, ui_play_row, ui_side_of["left"], ui_side_of["right"]] + ui_rails.values())
	easy.start(cf, testing)   # EASY MODE: the saved mode (a fresh config is Easy); its own tour, once
	if (not testing and not easy.on and not OS.get_cmdline_user_args().has("--shot") and _tour_due()) or OS.get_cmdline_user_args().has("--tour"):
		_tour_after_recover.call_deferred()   # FIRST-RUN TOUR: until it is done or skipped once, or asked for
	var args := OS.get_cmdline_user_args()
	if not args.has("--shot") and (not testing or OS.get_environment("POSER_AUTOSAVE") != ""):
		_recover_offer.call_deferred()
	ov.trail_on = args.has("--trail")
	var pi := args.find("--pin")   # --pin foot_l,head: trails on those parts (shots and checks)
	if pi >= 0 and pi + 1 < args.size():
		for j in args[pi + 1].split(","):
			ov.toggle_pin(j)
	ov.onion_on = args.has("--onion")
	bal.on = args.has("--balance")
	ov.spacing_on = args.has("--spacing")
	fd_on = args.has("--frame-data")   # FRAME DATA (ROADMAP 12): --frame-data = the strip and the boxes (shots)
	fd_boxes = fd_on
	ov.graph_on = args.has("--graph")
	stepped_view = args.has("--stepped")
	var i := args.find("--pose")
	if i >= 0 and i + 1 < args.size():
		_load_pose(args[i + 1])
	i = args.find("--kind")
	if i >= 0 and i + 1 < args.size():
		_kind(args[i + 1])
		B.apply_grip()
	i = args.find("--scene")
	if i >= 0 and i + 1 < args.size():
		_load_scene(args[i + 1])
	if args.has("--spline"):   # Smooth (spline) on, for shots and checks
		S.spline = true
		_rebuild_cards()
	i = args.find("--t")
	if i >= 0 and i + 1 < args.size():
		playhead = float(args[i + 1])
		_ps().apply(B, playhead)
	i = args.find("--frame")   # --frame N [--fps F]: exactly frame N, at t = N / F (F: the scene's own fps) (U3)
	if i >= 0 and i + 1 < args.size():
		var fk := args.find("--fps")
		playhead = float(args[i + 1]) / (float(args[fk + 1]) if fk >= 0 and fk + 1 < args.size() else float(S.fps))
		_ps().apply(B, playhead)
	i = args.find("--tween")   # --tween <card number> <bias>: pick that card and slide the tween (for shots and checks)
	if i >= 0 and i + 2 < args.size():
		_card_pick(int(args[i + 1]) - 1)
		_sync = true
		ui_tween.value = float(args[i + 2])
		_sync = false
		_tween(float(args[i + 2]))
	if args.has("--history"):   # the undo history panel, after a few named steps (shots)
		for n in ["Copy right side to left", "Mirror the whole pose", "Arms down 25°"]:
			for c in ui_cmd.commands:
				if c["name"] == n:
					_step_hint = n
					c["run"].call()
		_undo()
		_toggle_history()
	if args.has("--check"):   # open the CHECK panel (shots and tests)
		_check()
	i = args.find("--hover-fix")   # --hover-fix <n>: the preview ghost of the n-th Fix button (1 = first), for shots
	if i >= 0 and i + 1 < args.size():
		var fx := findings.filter(func(x): return Fixer.label(x, S) != "")
		if int(args[i + 1]) - 1 < fx.size():
			_fix_hover(fx[int(args[i + 1]) - 1])
	i = args.find("--view")
	if i >= 0 and i + 1 < args.size():
		_view(int(args[i + 1]))
	i = args.find("--dummy")
	if i >= 0 and i + 1 < args.size():
		T.place(float(args[i + 1]))
	if args.has("--no-dummy"):
		dummy_on = false
	if args.has("--caps"):
		show_caps = true
	if args.has("--clean"):
		clean = true
	i = args.find("--yaw")
	if i >= 0 and i + 1 < args.size():
		yaw = float(args[i + 1])
		_cam()
	i = args.find("--pitch")
	if i >= 0 and i + 1 < args.size():
		pitch = float(args[i + 1])
		_cam()
	i = args.find("--focus")
	if i >= 0 and i + 1 < args.size():
		sel = args[i + 1]
		target = B.P[sel]
		dist = 0.55
		_cam()
	i = args.find("--dist")
	if i >= 0 and i + 1 < args.size():
		dist = float(args[i + 1])
		_cam()
	_refresh()
	_rebuild_cards()
	await dummy_settle()   # round 14: the dummy measures on a worker; a shot shows what PLAYS (landed on it or not)
	if args.find("--t") >= 0 or args.find("--frame") >= 0:
		_ps().apply(B, playhead)   # (and --dummy's range now counts: it used to move the dummy after --t had posed)
		_refresh()
	i = args.find("--record")
	var pb := args.find("--playblast")
	if (i >= 0 and i + 1 < args.size()) or (pb >= 0 and pb + 1 < args.size()):
		# --record <dir> [--fps N] [--burn]: play the scene and save every frame (frame_0000.png ...), then quit
		# --playblast out.avi [--fps N] [--burn]: the same frames as one MJPEG AVI (GATES WW6)
		var fps := 24
		var k := args.find("--fps")
		if k >= 0 and k + 1 < args.size():
			fps = int(args[k + 1])
		await _record(args[i + 1] if i >= 0 else "", fps, args.has("--burn"), args[pb + 1] if pb >= 0 else "")
		get_tree().quit()
		return
	i = args.find("--tl-drag")   # --tl-drag card,seconds: hold a timeline drag on that card's edge (for screenshots)
	if i >= 0 and i + 1 < args.size():
		var cd: PackedStringArray = args[i + 1].split(",")
		await get_tree().process_frame
		var ci := int(cd[0]) - 1
		var x0 := ui_timeline.x_of(S.times()[ci][1])
		for x in [x0, x0 + float(cd[1]) * ui_timeline.pps()]:
			var ev: InputEvent = InputEventMouseButton.new() if x == x0 else InputEventMouseMotion.new()
			if ev is InputEventMouseButton:
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
			ev.position = Vector2(x, Timeline.RULER + 12.0)
			ui_timeline._gui_input(ev)
	i = args.find("--tab")   # --tab 1: the left panel's Browser tab (screenshots)
	if i >= 0 and i + 1 < args.size():
		(ui_browser.get_parent() as TabContainer).current_tab = int(args[i + 1])
	i = args.find("--sel")   # --sel part: select that part (screenshots)
	if i >= 0 and i + 1 < args.size():
		sel = args[i + 1]
		_refresh()
	i = args.find("--ring")   # --ring part: the right-click ring open on that part, the 1st wedge hovered (screenshots)
	if i >= 0 and i + 1 < args.size():
		await get_tree().process_frame
		_ring_open(args[i + 1], cam.unproject_position(B.P[args[i + 1]]))
		ui_ring.hover = 0
	i = args.find("--ribbon")   # --ribbon ANIMATE: open that ribbon tab (screenshots)
	if i >= 0 and i + 1 < args.size():
		_ribbon(args[i + 1])
	i = args.find("--do")   # --do "Point the right hand": run that registered command, by its name (screenshots)
	if i >= 0 and i + 1 < args.size():
		for c in _commands():
			if c["name"] == args[i + 1]:
				(c["run"] as Callable).call()
	i = args.find("--back")   # --back bend:60,twist:30: the whole back bent that way (screenshots)
	if i >= 0 and i + 1 < args.size():
		for kv in args[i + 1].split(","):
			B.back_bend(kv.get_slice(":", 0), float(kv.get_slice(":", 1)))
		_refresh()
	i = args.find("--slide")   # --slide upperarm_r,side,80: move that joint's slider, as a hand would (screenshots)
	if i >= 0 and i + 1 < args.size():
		var sl: PackedStringArray = args[i + 1].split(",")
		sel = sl[0]
		_on_slider(float(sl[2]), sl[1])
	i = args.find("--sec")   # --sec HANDS: open that inspector section (screenshots)
	if i >= 0 and i + 1 < args.size() and ui_secs.has(args[i + 1]):
		_sec_open(args[i + 1], true)
	i = args.find("--cmd")   # --cmd text: the S search open with that typed (screenshots)
	if i >= 0 and i + 1 < args.size():
		ui_cmd.open()
		ui_cmd.box.text = args[i + 1]
		ui_cmd._filter()
	i = args.find("--pull")   # --pull part,dx,dy: hold a drag of that hand/foot, dx/dy metres in the view (screenshots)
	if i >= 0 and i + 1 < args.size():
		var pd: PackedStringArray = args[i + 1].split(",")
		await get_tree().process_frame
		var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / get_viewport().get_visible_rect().size.y
		sel = pd[0]
		dragging = "joint"
		_grab = Vector3(NAN, NAN, NAN)
		for k in 10:   # in ten steps, as a hand would
			_drag_joint(Vector2(float(pd[1]), -float(pd[2])) / mpp / 10.0, false, false, false)
	i = args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		var path: String = args[i + 1]
		while not _pv_job.is_empty():   # --hover-fix: a preview being worked out is part of the picture
			await get_tree().process_frame
		_doc_line(true)   # the strip's length is throttled (400 ms): a shot taken inside the window showed the length
		# from before the scene settled (walk_bat 3.15 s in one shot, 3.45 s in the next; tests/py/determinism.py, round 42)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()


## a test's own settings file goes with it (ribbon_test clicks VIEW > Light like any button: one file per run piled up)
func _exit_tree() -> void:
	if not _pv_job.is_empty():   # a fix preview still being worked out on a worker thread
		WorkerThreadPool.wait_for_task_completion(_pv_job["task"])
	if not _dm_job.is_empty():   # the dummy's measurement, the same
		WorkerThreadPool.wait_for_task_completion(_dm_job["task"])
	if settings != SETTINGS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings))
	if library != LIBRARY:
		_rm_tree(library)   # SS6: a test's own library
	if journal_on:
		if not _unsaved() or _discarding:
			journal.trim()   # nothing unsaved (or Don't save was chosen): the journal has nothing to give back
		if quit_clean:
			journal.set_session(true)   # a clean quit: the next start offers nothing
		journal.close()
	# quitting with nothing unsaved: no autosave to offer next time. A test's own per-process file always goes
	if not _unsaved() or _discarding or (autosave != AUTOSAVE and OS.get_environment("POSER_AUTOSAVE") == ""):
		_autosave_drop()
	if autosave != AUTOSAVE and OS.get_environment("POSER_AUTOSAVE") == "" and FileAccess.file_exists(_later_path()):
		DirAccess.remove_absolute(_later_path())


func _process(dt: float) -> void:
	_co_tick()   # ROADMAP 30: the session's socket, the owned fighter's playhead
	_doc_line()   # RR1: the strip catches up (throttled) after edits that do not refresh
	_keys_camera(dt)
	if shot_through:
		_shot_apply()   # THE SHOT CAMERA follows the playhead (play, scrub, an edit)
	_tour_poll()
	_step_hint = ""   # a press that pushed no step must not name a later one
	_pv_poll()
	_video_poll(dt)
	_live_poll(dt)
	if mm_ui != null:
		mm_ui.tick(dt)   # MOTION MATCHING PREVIEW: steers and plays the matched frames while it is on (nothing otherwise)
	_dm_poll()
	_kb_poll()
	_as_wait += dt
	if _as_wait >= 15.0:
		_as_wait = 0.0
		autosave_now()
	if _jpending and dragging == "":
		_journal_write()   # an edit no _do ended (a slider, the end of a drag, an undo): its result, once settled
	if hover_part != "" or hover_fighter >= 0:   # the mouse went onto a panel (it eats the motion, so the view never hears it leave)
		var hc := get_viewport().gui_get_hovered_control()
		if dragging != "" or (hc != null and hc != ui_browser and hc.mouse_filter == Control.MOUSE_FILTER_STOP):   # the Browser lights a part itself (KK2)
			hover_part = ""
			_fh_clear()
			_refresh()
	var now := Time.get_ticks_msec() / 1000.0
	if hover_part != _bar_want:
		_bar_want = hover_part
		_bar_want_t = now
	if _bar_want != _bar_hover and now - _bar_want_t >= (BAR_REST if _bar_want != "" else BAR_LEAVE):
		_bar_hover = _bar_want
	if ui_bar != null:
		var bt := bar_text()
		if bt != ui_bar.text:   # rebuilt every frame, written only when it differs: no edit path can leave it stale
			ui_bar.text = bt
	_props_pose()   # UU2: carried and falling props follow the playhead (nothing when no card carries)
	var _a_before := playhead   # the sound follows whatever moved the playhead this frame (_audio_tick)
	if playing and not S.cards.is_empty():
		# WW4: inside the preview range, if one is set. ROADMAP 48: how far the playhead moves is the play clock's mode
		var stp := play_clock.advance(playhead, dt, S.fps, _ps().length(), pv_in, pv_out, S.loop)
		playhead = stp["t"]
		if stp["stop"]:
			playing = false
		_ps().apply(B, playhead)
		_refresh()
		if play_delay > 0.0:
			OS.delay_msec(roundi(play_delay * 1000.0))   # the test's slow frame: this frame really costs that long
	_audio_tick(_a_before, dt)
	_fps_poll(dt)


# ---------------------------------------------------------------- 3D scene

func _world() -> void:
	stage_root = Node3D.new()   # TC4: the floor, its axes and the lights (identity with one actor: _stage_sync)
	stage_root.name = "stage"
	add_child(stage_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Tok.c("world")
	world_env = e
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	stage_root.add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-30, 200, 0)
	back.light_energy = 0.45
	stage_root.add_child(back)
	var im := ImmediateMesh.new()
	var gm := MeshInstance3D.new()
	gm.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # the grid fades out (round 24)
	gm.material_override = m
	grid_mesh = im
	var am := MeshInstance3D.new()
	axis_mesh = ImmediateMesh.new()
	am.mesh = axis_mesh
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.vertex_color_use_as_albedo = true
	am.material_override = amat
	stage_root.add_child(am)
	_grid()
	stage_root.add_child(gm)
	grid_node = gm
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4, 4)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Tok.c("floor")
	floor_mat = fm
	floor.material_override = fm
	floor.position.y = -0.002
	stage_root.add_child(floor)
	for lab in [["X  his left", Vector3(0.72, 0.01, 0), AXES[0][1]], ["Y  up", Vector3(0, AXIS_Y + 0.05, 0), AXES[1][1]], ["Z  he faces this way", Vector3(0, 0.01, 0.74), AXES[2][1]]]:
		var l := Label3D.new()
		l.name = "axis_" + String(lab[0]).left(1)
		l.text = lab[0]
		l.position = lab[1]
		l.modulate = lab[2]
		l.pixel_size = 0.0018
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stage_root.add_child(l)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	ShotGizmo.attach(self)   # THE SHOT CAMERA's body in the 3D view (scripts/shot_gizmo.gd)
	_cam()


func _body() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.72, 0.64)
	skin.roughness = 0.55
	var mq := Overlays.mannequin(self, skin)
	skel = mq[1]
	bone_idx = mq[2]
	pieces = Overlays.split_parts(mq[0], skel, bone_idx)
	_wp_setup()   # the skin weights, and the sidecar's if the character was painted before (ROADMAP 72)
	corr.attach(pieces.values(), skel)
	_skp_build()   # PRECISE PICK: the picked / hovered part's own skin is tinted (scripts/skin_pick.gd)
	for j in Body.WEAPON + Body.WEAPON2:   # the weapon's capsules: its pick and its light (a body part has none: its skin is lit)
		_new_cap(j)
	for j in Body.BODY:
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.011
		sm.height = 0.022
		d.mesh = sm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = side_col(j)
		dm.no_depth_test = true
		dm.render_priority = 1
		d.material_override = dm
		add_child(d)
		dots[j] = d
	# the metal bat: a taped handle, a barrel swelling from the handle to full width, a knob
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.64, 0.68)
	metal.metallic = 0.85
	metal.roughness = 0.3
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.08, 0.08, 0.09)
	tape.roughness = 0.9
	bat_handle = _cyl(B.wep_r_handle, B.wep_r_handle, tape)
	bat_barrel = _cyl(B.wep_r_barrel, B.wep_r_handle, metal)
	bat_knob = _cyl(B.wep_r_handle * 1.6, B.wep_r_handle * 1.6, tape)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.24, 0.14)
	wood.roughness = 0.75
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.3, 0.31, 0.33)
	steel.metallic = 0.9
	steel.roughness = 0.35
	wep_mats = {"metal": metal, "tape": tape, "wood": wood, "steel": steel}
	d2_handle = _cyl(0.013, 0.013, tape)
	d2_blade = _cyl(0.004, 0.011, steel)
	tag = Label3D.new()
	tag.pixel_size = 0.0009
	tag.fixed_size = true
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = Color(0.55, 0.78, 1.0)
	tag.outline_size = 5
	tag.font_size = 16   # RR5: the part's name on the body, small (was 30: a headline over the shoulder)
	add_child(tag)
	_dummy_build()


## the floor grid in the theme's colours (a theme switch rebuilds it; the two axis lines are content)
## THE FLOOR FADES (round 24, GATES EE1, UPGRADES #45): full to GRID_FULL m from the middle, nothing at GRID_END (its
## edge), each line cut into GRID_STEP pieces so the fade is smooth; the origin's axes are their own mesh, never faded:
## X red toward his left, Y green up, Z blue the way he faces, each with an arrowhead (and its letter, a Label3D)
const GRID_FULL := 1.0
const GRID_END := 2.0
const GRID_STEP := 0.1
const AXIS_Y := 0.3
const AXES := [[Vector3(0.6, 0.001, 0), Color(0.9, 0.3, 0.3)], [Vector3(0, AXIS_Y, 0), Color(0.35, 0.8, 0.35)], [Vector3(0, 0.001, 0.6), Color(0.3, 0.5, 0.95)]]
var axis_mesh: ImmediateMesh


static func grid_alpha(p: Vector3) -> float:
	return clampf((GRID_END - Vector2(p.x, p.z).length()) / (GRID_END - GRID_FULL), 0.0, 1.0)


func _grid() -> void:
	grid_mesh.clear_surfaces()
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := int(round(GRID_END / GRID_STEP))
	for k in range(-n, n + 1):
		var x := k * GRID_STEP
		var c := Tok.c("grid_major") if k % 10 == 0 else Tok.c("grid")
		for i in range(-n, n):
			for seg in [[Vector3(x, 0, i * GRID_STEP), Vector3(x, 0, (i + 1) * GRID_STEP)], [Vector3(i * GRID_STEP, 0, x), Vector3((i + 1) * GRID_STEP, 0, x)]]:
				var a0 := grid_alpha(seg[0])
				var a1 := grid_alpha(seg[1])
				if a0 <= 0.0 and a1 <= 0.0:
					continue
				grid_mesh.surface_set_color(Color(c, c.a * a0))
				grid_mesh.surface_add_vertex(seg[0])
				grid_mesh.surface_set_color(Color(c, c.a * a1))
				grid_mesh.surface_add_vertex(seg[1])
	grid_mesh.surface_end()
	axis_mesh.clear_surfaces()
	axis_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for ax in AXES:
		var tip: Vector3 = ax[0]
		var o := Vector3(0, 0.001, 0)
		var d := (tip - o).normalized()
		var side := Vector3.UP if absf(d.y) < 0.5 else Vector3.RIGHT
		var w := d.cross(side).normalized() * 0.03
		for seg in [[o, tip], [tip, tip - d * 0.06 + w], [tip, tip - d * 0.06 - w]]:
			axis_mesh.surface_set_color(ax[1])
			axis_mesh.surface_add_vertex(seg[0])
			axis_mesh.surface_set_color(ax[1])
			axis_mesh.surface_add_vertex(seg[1])
	axis_mesh.surface_end()


## the dummy: the same mannequin, blue-grey, standing (T.D), turned to face the hero
func _dummy_build() -> void:
	dummy_mat = StandardMaterial3D.new()
	dummy_mat.albedo_color = Color(0.45, 0.5, 0.58)
	dummy_mat.roughness = 0.7
	var dq := Overlays.mannequin(self, dummy_mat)
	dummy_node = dq[0]
	Overlays.pose_skeleton(dq[1], dq[2], T.D)
	dummy_corr.attach(dq[0].find_children("*", "MeshInstance3D", true, false), dq[1])
	dummy_corr.update(T.D)
	hit_tag = Label3D.new()
	hit_tag.pixel_size = 0.0009
	hit_tag.fixed_size = true
	hit_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hit_tag.no_depth_test = true
	hit_tag.modulate = Color(1.0, 0.45, 0.35)
	hit_tag.outline_size = 10
	hit_tag.font_size = 18   # RR5 (was 34)
	add_child(hit_tag)
	hit_dot = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	hit_dot.mesh = sm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1.0, 0.3, 0.2)
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.no_depth_test = true
	hit_dot.material_override = hm
	add_child(hit_dot)


## the dummy now: where it stands, and red with a tag where the weapon is in it
func _dummy_refresh() -> void:
	dummy_node.visible = dummy_on
	dummy_node.transform = T.xf
	var h := T.touch(B) if dummy_on else {}
	hit_tag.visible = not h.is_empty()
	hit_dot.visible = not h.is_empty()
	dummy_mat.albedo_color = Color(0.85, 0.3, 0.25) if not h.is_empty() else Color(0.45, 0.5, 0.58)
	if not h.is_empty():
		hit_dot.position = h["at"]
		hit_tag.position = (h["at"] as Vector3) + Vector3(0, 0.12, 0)
		hit_tag.text = "%s  (%s up the weapon)" % [h["zone"], Units.len(h["u"])]


## the timeline's height: its 34 px of rows, and the strips under the ruler (the frame strip, ROADMAP 12; the boxes lane, ROADMAP 36)
func _tl_height() -> void:
	ui_timeline.custom_minimum_size.y = 34.0 + (Timeline.AUDIO_H if _a_path != "" else 0.0) + ui_timeline.clip_px() + _tl_under_ruler()


## the px under the ruler that the frame strip and the boxes lane take (0 with neither on)
func _tl_under_ruler() -> float:
	if ui_timeline == null:
		return 0.0
	return (Timeline.FD_H + 3.0 if not ui_timeline.fd.is_empty() else 0.0) + ui_timeline.bx_px() + ui_timeline.shots_px() + ui_timeline.sp_px()


# ---------------------------------------------------------------- FRAME DATA (ROADMAP 12; scripts/frame_data.gd)
var fd_on := false           # the frame strip on the timeline
var fd_boxes := false        # the hitboxes / hurtboxes drawn in the view
var fd_fps := 60             # the game's frame rate the counts use (a setting: the "fps" button)
var fd_cache := {}           # {"key": the scene + dummy + fps it was made for, "fd": FrameData.analyze's result}
var fd_node: MeshInstance3D = null
var fd_btn: Button = null
var hitbox_ui: HitBoxesUI   # HIT / HURT BOXES (ROADMAP 36): the commands and the dialog (scripts/hit_boxes_ui.gd)


## a box picked on the timeline's lane (ROADMAP 36): its handles show in the view
func _bx_pick(i: int) -> void:
	if hitbox_ui == null:
		hitbox_ui = HitBoxesUI.new(self)
	hitbox_ui.pick(i)


func _fd_toggle() -> void:
	fd_on = not fd_on
	_refresh()


func _fd_boxes_toggle() -> void:
	fd_boxes = not fd_boxes
	_refresh()


func _fd_cycle_fps() -> void:
	var order := [24, 30, 60, 120]
	fd_fps = order[(order.find(fd_fps) + 1) % order.size()]
	if fd_btn != null:
		fd_btn.tooltip_text = "Frame rate\nthe frame rate the frame data counts in (24, 30, 60, 120 fps): now %d fps" % fd_fps
	_say_plain("frame data now counts in %d fps (click again for the next: 24, 30, 60, 120 fps)" % fd_fps)
	_refresh()


## the frame data of the scene as it is now (a fresh body: the live one is not moved). Made again only when the cards,
## the dummy or the frame rate change
func _fd_data() -> Dictionary:
	var key := "%d|%s|%s|%s" % [fd_fps, var_to_str(S.cards), var_to_str(T.xf) if dummy_on else "-", var_to_str(S.boxes)]
	if String(fd_cache.get("key", "")) != key:
		var Bc := Body.new()
		Bc.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		Bc.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
		Bc.ground()
		fd_cache = {"key": key, "fd": FrameData.analyze(S, Bc, fd_fps, T if dummy_on else null)}
	return fd_cache["fd"]


## the strip and the boxes for this refresh (both off: nothing is analysed)
func _fd_refresh() -> void:
	if ui_timeline != null:
		var before := _tl_under_ruler()
		ui_timeline.fd = _fd_data() if fd_on and not S.cards.is_empty() else {}
		ui_timeline.sp = LimbIK.space_lane(S.ik, S.length()) if not S.ik.is_empty() else []   # ROADMAP 63: the space segments
		ui_timeline.bx = HitBoxes.lanes(S.boxes, float(fd_fps)) if not S.boxes.is_empty() and not S.cards.is_empty() else []   # ROADMAP 36: the boxes lane
		if before != _tl_under_ruler():
			_tl_height()
			_layout_bottom()   # the panel makes room for the frame strip and the lane, or gives it back
		ui_timeline.queue_redraw()
	if not fd_boxes or S.cards.is_empty():
		if fd_node != null:
			fd_node.visible = false
		return
	var fd := _fd_data()
	var fr: Dictionary = FrameData.frame_at(fd, playhead)
	var groups := [[fr["hurtboxes"], Color(0.6, 0.7, 0.85)]]
	var auto_hits := []   # the auto-detected hitboxes (active frames) and the user's own hit boxes (any frame, ROADMAP 36)
	var own_hits := []
	for c in fr["hitboxes"]:
		(own_hits if c.has("src") else auto_hits).append(c)
	if fr["active"]:
		groups.append([auto_hits, Color(1.0, 0.3, 0.25)])
	if not own_hits.is_empty():
		groups.append([own_hits, Color(1.0, 0.75, 0.2)])
	if fd_node == null:
		fd_node = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		fd_node.material_override = m
		add_child(fd_node)
	fd_node.mesh = FrameData.wire(groups)
	fd_node.visible = true


## the frame data as JSON, where the user picks (never in scenes/)
func _fd_export() -> void:
	if S.cards.is_empty():
		_say_plain("no frame data: the scene has no cards")
		return
	var data := _fd_data()
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.json ; frame data"])
	dlg.current_file = "%s_frames.json" % S.name
	dlg.current_dir = ProjectSettings.globalize_path("res://exports")
	dlg.title = "Export frame data (json)"
	dlg.use_native_dialog = true
	dlg.file_selected.connect(func(p):
		var e := FrameData.write_json(data, p)
		if e == OK:
			_say_plain("frame data written: %s (startup %d f, active %d f, recovery %d f at %d fps)" % [p.get_file(), data["startup"], data["active"], data["recovery"], data["fps"]])
		else:
			_say_plain("NOT WRITTEN: %s could not be saved (error %d)" % [p.get_file(), e])
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(800, 500))


## the dummy on/off and its range; the scene's hits listed (time, zone, speed of the spot that lands)
func _dummy_toggle() -> void:
	dummy_on = not dummy_on
	_dummy_hits()
	_refresh()


func _dummy_solid() -> void:
	solid = not solid
	_dummy_hits()
	_refresh()


func _dummy_move(d: float) -> void:
	T.place(clampf(T.dist + d, 0.6, 3.0))
	_dummy_hits()
	_refresh()


## THE DUMMY'S HITS, OFF THE MAIN THREAD (round 14, GATES U1): sampling the whole scene against the dummy took 1.3 s
## per card edit on a 30-card scene. Now an edit only starts a job: a copy of the scene and a dummy of its own, on a
## worker thread (as the fix preview does). Only the NEWEST edit's result lands (_dm_gen); one that finishes stale
## starts the next. Meanwhile the text says "measuring..." and SL is cleared, so playback never shows an old landing.
var _dm_job := {}
var _dm_gen := 0


func _dummy_hits() -> void:
	if ui_dummy == null:
		return
	_dm_gen += 1
	SL = null
	fighter_hits = []   # TC5: a report of the scene before this edit is never shown as current
	if _fighters_on():
		ui_dummy.text = _fighters_head() + ": measuring who hits whom..."
		ui_browser.refresh()
		if _dm_job.is_empty():
			_dm_start()
		return
	if not dummy_on:
		ui_dummy.text = "dummy off"
		ui_browser.refresh()
		return
	if S.cards.size() < 2:
		ui_dummy.text = _dummy_head(T.dist, solid)
		ui_browser.refresh()
		return
	ui_dummy.text = _dummy_head(T.dist, solid) + "\nmeasuring the scene's hits..."
	ui_browser.refresh()
	if _dm_job.is_empty():
		_dm_start()


func _dm_start() -> void:
	var job := {"gen": _dm_gen, "out": {}}
	if _fighters_on():   # TC5: the same job, the same worker: the hero against each other fighter
		var hs: Scene = (actors_rt[0]["S"] as Scene).clone()
		hs.actors = []   # (the others go in below, cloned once)
		var others := []
		for k in range(1, actors_rt.size()):
			others.append({"name": actors_rt[k]["name"], "S": (actors_rt[k]["S"] as Scene).clone(), "xf": actors_rt[k]["xf"]})
		job["task"] = WorkerThreadPool.add_task(func(): job["out"] = _fighters_measure(hs, others))
		_dm_job = job
		return
	var sc := S.clone()
	var d := T.dist
	var y := T.yaw
	var so := solid
	job["task"] = WorkerThreadPool.add_task(func(): job["out"] = _dummy_measure(sc, d, y, so))
	_dm_job = job


## called every frame: a finished job lands if it is the newest; a stale one starts the next
func _dm_poll() -> void:
	if _dm_job.is_empty() or not WorkerThreadPool.is_task_completed(_dm_job["task"]):
		return
	WorkerThreadPool.wait_for_task_completion(_dm_job["task"])
	var job := _dm_job
	_dm_job = {}
	if job["gen"] != _dm_gen:
		if _fighters_on() or (dummy_on and S.cards.size() >= 2):
			_dm_start()
		return
	ui_dummy.text = job["out"]["txt"]
	ui_browser.refresh()
	if job["out"].has("hits"):   # TC5: the fighters' report (nothing lands: the fighters do not stop each other)
		fighter_hits = job["out"]["hits"]
		return
	SL = job["out"]["SL"]
	if SL != null:
		ov.mark_dirty()   # what plays changed: the trail / speed graph pass follows it
		wt.mark_dirty()
		_refresh()        # (the pass runs when the window redraws its overlays)


## wait for the dummy's measurement to land (tests and scripted shots that read it)
func dummy_settle() -> void:
	while not _dm_job.is_empty():
		await get_tree().process_frame
		_dm_poll()


static func _dummy_head(dist: float, so: bool) -> String:
	return "dummy %.2f m out, %s" % [dist, "SOLID: the weapon stops on it" if so else "see-through"]


## the measurement itself, on ITS OWN scene, dummy and body (so it can run on any thread): {"txt", "SL"}
static func _dummy_measure(sc: Scene, dist: float, yaw: float, so: bool) -> Dictionary:
	var td := Dummy.new()
	td.place(dist, yaw)
	var txt := _dummy_head(dist, so)
	var sl: Scene = null
	var HB := Body.new()
	HB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var hs: Array = td.hits(sc, HB, 30)
	if hs.is_empty():
		txt += "\nthe scene: no hit at this range"
	for x in hs:
		txt += "\n%.2fs  %s  %.1f m/s  (%.2f m up)" % [x["t"], x["zone"], x["speed"], x["u"]]
	if so and not hs.is_empty():
		var r: Array = td.landed(sc, HB)
		sl = r[0]
		txt += "\nlands %.2fs on the %s, rebounds; plays %.2f s" % [r[1]["t"], r[1]["zone"], sl.length()]
	return {"txt": txt, "SL": sl}


## TWO FIGHTERS (round 50, GATES TC5): with 2+ fighters the dummy is put away and its report is made between the
## fighters instead: the hero against each other one at its placement, over the whole scene, at the scene's fps
## (Dummy.fighter_hits). The same job and worker as the dummy's (_dm_start / _dm_poll, newest edit wins); the rows land
## in fighter_hits and the text in ui_dummy (the browser's dummy row shows it, a row per contact)
var fighter_hits := []   # [{"t", "kind", "zone", "part", "on", "by", "depth", "speed", "u", "at", "vs": actor k}, ...]


func _fighters_on() -> bool:
	return actors_rt.size() >= 2


func _fighters_head() -> String:
	return "%d fighters" % actors_rt.size()


## the measurement itself, on ITS OWN scenes and bodies (any thread): {"txt", "hits"}
static func _fighters_measure(hs: Scene, others: Array) -> Dictionary:
	var HB := Body.new()
	HB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var all := []
	var names := ["the hero"]
	for k in others.size():
		var o: Dictionary = others[k]
		names.append(o["name"])
		var OB := Body.new()
		OB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		for h in Dummy.fighter_hits(hs, HB, o["S"], OB, o["xf"], hs.fps):
			h["vs"] = k + 1
			all.append(h)
	all.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	var txt := "%d fighters: " % (others.size() + 1)
	if all.is_empty():
		txt += "they never touch in the scene"
	else:
		txt += "%d contact%s, the first %.2fs %s (%s)" % [all.size(), "" if all.size() == 1 else "s", all[0]["t"], all[0]["zone"], all[0]["kind"]]
	for h in all:
		var who: String = names[0] if h["by"] == "hero" else names[h["vs"]]
		var whom: String = names[h["vs"]] if h["by"] == "hero" else names[0]
		var what: String = "weapon" if Body.is_wep(h["part"]) else String(h["part"])
		txt += "\n%.2fs  %s  %s: %s's %s on %s's %s  %.1f m/s  %.1f cm deep" % [h["t"], h["zone"], h["kind"], who, what, whom, h["on"], h["speed"], float(h["depth"]) * 100.0]
		if float(h["u"]) >= 0.0:
			txt += "  (%.2f m up)" % h["u"]
	return {"txt": txt, "hits": all}


## the contact NOW between the hero and the other fighters, drawn as the dummy's is (the red dot and the tag), after the
## others are posed. One fighter: returns at once (the dummy's own drawing stands)
func _fighters_mark() -> void:
	if not _fighters_on() or hit_tag == null:
		return
	var hb: Body = actors_rt[0]["B"]
	var best := []
	var bk := 0
	for k in range(1, actors_rt.size()):
		var cs: Array = hb.cross_contacts(actors_rt[k]["B"], actors_rt[k]["xf"])
		if not cs.is_empty() and (best.is_empty() or float(cs[0][2]) > float(best[2])):
			best = cs[0]
			bk = k
	hit_tag.visible = not best.is_empty()
	hit_dot.visible = not best.is_empty()
	if best.is_empty():
		return
	var at: Vector3 = _stage_xf() * Dummy.cross_at(hb, actors_rt[bk]["B"], actors_rt[bk]["xf"], best)   # hero space -> the view's
	hit_dot.position = at
	hit_tag.position = at + Vector3(0, 0.12, 0)
	hit_tag.text = "%s  (%s, %.1f cm)" % [Dummy.cross_name(best).get_slice("|", 1), best[3], float(best[2]) * 100.0]


## the playhead to contact i of the fighters' report (its row in the browser)
func _goto_hit(i: int) -> void:
	if i < 0 or i >= fighter_hits.size():
		return
	var h: Dictionary = fighter_hits[i]
	playing = false
	playhead = float(h["t"])
	_ps().apply(B, playhead)
	_refresh()
	_say("%s: %s on the %s (%s), %.1f m/s" % [Units.time(h["t"], S.fps), h["kind"], h["zone"], h["on"], h["speed"]])


## Hits: make the struck fighter react (ROADMAP 14, round 52). The first row of the fighters' report that lands on a body
## part (a hit or a strike) turns its victim by the momentum it delivers (hit_reaction.gd); the reaction is baked as cards
## over its window on the VICTIM's scene (made the active fighter first, so its own Ctrl+Z). One undo step.
func _hit_react() -> void:
	_actors_sync()
	if not _fighters_on():
		_say("Hits: make the struck fighter react needs two fighters: 'Actor: add a second fighter' first")
		return
	var pick := -1
	for i in fighter_hits.size():
		var r: Dictionary = fighter_hits[i]
		if (r["kind"] == "hit" or r["kind"] == "struck") and not Body.is_wep(String(r["on"])):
			pick = i
			break
	if pick < 0:
		_say("no contact in the fighters' report lands on a body part to react to: swing into the other fighter, or pick a stronger hit (the report is in the browser's dummy row)")
		return
	var h: Dictionary = fighter_hits[pick]
	var vk: int = 0 if h["by"] == "other" else int(h["vs"])   # the struck fighter
	var sk: int = int(h["vs"]) if h["by"] == "other" else 0   # the striker
	var r := HitReaction.react(actors_rt[vk]["S"], actors_rt[vk]["B"], actors_rt[vk]["xf"], h, actors_rt[sk]["B"])
	if not r["ok"]:
		_say("no reaction: %s (pick a fighter with a contact, then try again)" % r["why"])
		return
	_actor_set(vk)   # the struck fighter is the active one: its cards and body take the step, its Ctrl+Z undoes it
	_push_undo()
	S.cards = r["cards"]
	_rebuild_cards()
	ov.mark_dirty()
	wt.mark_dirty()
	_refresh()
	var J: Vector3 = r["J"]
	_say("%s reacts to %s's %s at %s (%s): impulse %.1f kg m/s (%.2f kg x %.1f m/s), its %s turns %.0f°/s at most, the pelvis is shoved %.2f m/s; %s of cards" % [
		actors_rt[vk]["name"], actors_rt[sk]["name"], "weapon" if Body.is_wep(String(h["part"])) else String(h["part"]),
		Units.time(float(r["t0"]), S.fps), h["zone"], J.length(), float(r["m_eff"]), float(r["v_rel"]), String(h["on"]), rad_to_deg(float(r["peak"])),
		float(r["shove"]), Units.time(float(r["t1"]) - float(r["t0"]), S.fps)])


## the weapon's radii + materials for its kind
func _wep_look() -> void:
	var hm := bat_handle.mesh as CylinderMesh
	var bm := bat_barrel.mesh as CylinderMesh
	hm.top_radius = B.wep_r_handle
	hm.bottom_radius = B.wep_r_handle
	if B.wep_kind == "dagger":
		# a taped grip, a steel blade narrowing to the point
		bm.top_radius = 0.004
		bm.bottom_radius = B.wep_r_barrel
		bat_handle.material_override = wep_mats["tape"]
		bat_barrel.material_override = wep_mats["steel"]
	elif B.wep_kind == "staff":
		bm.top_radius = B.wep_r_handle
		bm.bottom_radius = B.wep_r_handle
		bat_handle.material_override = wep_mats["wood"]
		bat_barrel.material_override = wep_mats["wood"]
	elif not B.wep_head.is_empty():
		bm.top_radius = float(B.wep_head[1])
		bm.bottom_radius = float(B.wep_head[1])
		bat_handle.material_override = wep_mats["tape"]
		bat_barrel.material_override = wep_mats["steel"]
	else:
		bm.top_radius = B.wep_r_barrel
		bm.bottom_radius = B.wep_r_handle
		bat_handle.material_override = wep_mats["tape"]
		bat_barrel.material_override = wep_mats["metal"]


func _cyl(top: float, bottom: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	mi.mesh = c
	mi.material_override = m
	add_child(mi)
	return mi


## one translucent capsule for part j (parts[j], mats[j]): a weapon's always; a body part's only while the Collision
## view is on (show_caps), since a body part is picked and lit on its own skin
func _new_cap(j: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "cap_" + j
	var cm := CapsuleMesh.new()
	cm.radius = B.rad[j]
	cm.height = 1.0
	cm.radial_segments = 20
	cm.rings = 6
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	parts[j] = mi
	mats[j] = m
	return mi


## PRECISE PICK (Nick 10-19): the pick and the highlight read the body's skinned pieces as drawn (scripts/skin_pick.gd)
func _skp_build() -> void:
	var part_of := {}
	for j in pieces:
		part_of[pieces[j]] = j
	skp.build(pieces.values(), skel, part_of)


## a capsule (or cylinder) from a to b: Godot's meshes run along their local Y
func _place(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float, capsule := true) -> void:
	var d := b - a
	var L := d.length()
	if capsule:
		if (not B.seg_s.is_empty() or mi.has_meta("pr")) and (mi.mesh as CapsuleMesh).radius != r:
			(mi.mesh as CapsuleMesh).radius = r   # PR1: proportions change a part's radius (a default body: as before)
			mi.set_meta("pr", true)
		(mi.mesh as CapsuleMesh).height = maxf(L + 2.0 * r, 2.0 * r + 0.001)
	else:
		(mi.mesh as CylinderMesh).height = maxf(L, 0.001)
	var y := d / L if L > 1e-6 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _refresh() -> void:
	_actors_view()
	_curve_sync()
	if ui_akey != null and auto_key:
		ui_akey.queue_redraw()   # the frame reads Tok on each draw: a palette switch shows at once
	if not sel_more.is_empty() and sel != _group_sel:
		sel_more = []
	_sym_prev = B.ang.duplicate()
	Overlays.pose_skeleton(skel, bone_idx, B)
	corr.update(B)
	_face_draw()   # ROADMAP 31 + 74: the jaw, the mouth shape, the brows and the eyes at the playhead (scripts/face.gd)
	for tg in ui_toggles:
		(tg[0] as Button).set_pressed_no_signal(tg[1].call())
	_doc_line()
	_insp_fit.call_deferred()   # RR2: rows shown / hidden change the box's height
	_sync_weapon()
	_fd_refresh()   # FRAME DATA (ROADMAP 12): the strip and the boxes on active frames
	if ui_browser != null and ui_browser.visible:
		ui_browser.follow()
	var touching := {}
	for pr in B.pairs:
		if not B.wep_on and (pr[0] in Body.WEAPON or pr[1] in Body.WEAPON):
			continue
		if not B.wep2_on and (pr[0] in Body.WEAPON2 or pr[1] in Body.WEAPON2):
			continue
		if B.depth(pr[0], pr[1]) - float(B.allow.get(pr[0] + "|" + pr[1], 0.0)) > 0.001:
			touching[pr[0]] = true
			touching[pr[1]] = true
	var looks := {}   # PRECISE PICK: each body part's light on its own skin (SkinPick.set_looks)
	for j in Body.ORDER + Body.WEAPON + Body.WEAPON2:
		var body: bool = not (j in Body.WEAPON or j in Body.WEAPON2)
		if dots.has(j):
			dots[j].position = B.P[j]
		var lk := part_look(j, touching)
		if body:
			if not clean and not wp_on and lk != "" and not hidden_parts.has(j):   # weight paint shows the weights instead
				looks[j] = _look_of(lk)
				if lk == "sel" and locked_parts.has(j):   # picked AND locked: the pick's colour greyed toward the lock's
					looks[j][0] = Color(Tok.c("pick_sel").lerp(Tok.c("pick_lock"), 0.4), looks[j][0].a)
			if pieces.has(j):
				pieces[j].visible = not hidden_parts.has(j)
			if show_caps and not clean and not parts.has(j):
				_new_cap(j)   # the Collision view: the body's capsules, made while it is on
			elif not show_caps and parts.has(j):
				parts[j].queue_free()   # off: gone from the tree (a body part's light is its skin)
				parts.erase(j)
				mats.erase(j)
		if not parts.has(j):
			continue
		var c: Array = B.cap(j)
		_place(parts[j], c[0], c[1], B.rad[j])
		var col := Color(0.62, 0.63, 0.66, 0.25 if show_caps else 0.0)
		if lk == "limit" or lk == "touch":   # the Collision view shows what the capsules collide with
			col = Color(LIMIT if lk == "limit" else TOUCH, 0.45)
		if not body:   # the weapon (not skinned): its capsule is its light
			if lk == "lock":
				col = Color(LOCK_COL, 0.45)
			elif lk == "hover":
				col = Color(HOVER, 0.3)
			elif lk == "sel":
				col = Color(SEL, 0.35)
		if clean:
			col.a = 0.0
		mats[j].albedo_color = col
		parts[j].visible = col.a > 0.0 and (B.wep_on or not j in Body.WEAPON) and (B.wep2_on or not j in Body.WEAPON2) and not hidden_parts.has(j)
	skp.set_looks(looks)
	for m in [bat_handle, bat_barrel, bat_knob]:
		m.visible = B.wep_on
	d2_handle.visible = B.wep2_on
	d2_blade.visible = B.wep2_on
	if B.wep2_on:
		var hu := float(Body.KINDS[B.wep2_kind]["handle"])
		_place(d2_handle, B.wep2_point(0.0), B.wep2_point(hu), 0.0, false)
		_place(d2_blade, B.wep2_point(hu), B.wep2_point(B.wep2_len()), 0.0, false)
	if B.wep_on:
		_wep_look()
		if B.wep_kind == "staff":
			# one even wooden shaft (the two halves drawn the same), no knob
			bat_knob.visible = false
			_place(bat_handle, B.wep_point(0.0), B.wep_point(B.wep_handle), 0.0, false)
			_place(bat_barrel, B.wep_point(B.wep_handle), B.wep_point(B.wep_len), 0.0, false)
		elif not B.wep_head.is_empty():
			# the long hammer: a taped shaft to the head, the steel head across the tip
			_place(bat_knob, B.wep_point(0.0), B.wep_point(0.012), 0.0, false)
			_place(bat_handle, B.wep_point(0.012), B.wep_point(B.wep_len - 0.02), 0.0, false)
			var hc: Array = B.cap("bat_barrel")
			var hd: Vector3 = ((hc[1] as Vector3) - (hc[0] as Vector3)).normalized() * float(B.wep_head[1])
			_place(bat_barrel, (hc[0] as Vector3) - hd, (hc[1] as Vector3) + hd, 0.0, false)
		else:
			_place(bat_knob, B.wep_point(0.0), B.wep_point(0.012), 0.0, false)
			_place(bat_handle, B.wep_point(0.012), B.wep_point(B.wep_handle), 0.0, false)
			_place(bat_barrel, B.wep_point(B.wep_handle), B.wep_point(B.wep_len), 0.0, false)
	var c2: Array = B.cap(sel)
	tag.visible = not clean
	for dj in dots:
		dots[dj].visible = not clean and not hidden_parts.has(dj)
	tag.text = nice(sel)
	tag.position = ((c2[0] as Vector3) + (c2[1] as Vector3)) * 0.5 + Vector3(0, 0.1, 0)
	_dummy_refresh()
	bal.show_body(B)
	_hand_sliders_sync()
	_auto_pin_sync()
	if not clean or ov.trail_on or ov.onion_on or not ov.pins.is_empty() or ov.has_rigs():
		ov.trail(_ps())
		ov.onion(_ps(), playhead)
	if ov.spacing_on or ov.graph_on:
		ov.trail(_ps())
	ov.spacing(playhead)
	ov.version_ghost(vdiff.get("scene", null), playhead)   # COMPARE WITH (ROADMAP 28): the version's body, magenta
	wt.draw(_ps(), playhead)   # weapon trail ribbon + smear (ROADMAP 35)
	var pulled: String = B.wep_hand if sel in Body.WEAPON else sel
	ov.reach_marker(B.P[pulled] if B.P.has(pulled) else Vector3.ZERO, _grab, dragging == "joint" and not is_nan(_grab.x) and B.P.has(pulled))
	if ui_graph != null:
		ui_graph.visible = ov.graph_on and S.cards.size() >= 2
		ui_graph.queue_redraw()
	_panel()
	_pose_others()
	_actors_draw()
	_fighters_mark()
	_rings_draw()   # ROADMAP 38: the range rings (View toggle)
	_ikh_draw()   # IK2: the pinned limbs' target / pole handles
	_sph_draw()   # ROADMAP 61: the back's spline curve and its three handles
	loa.draw(B)   # ROADMAP 23: the current line of action (View toggle)
	_frh_draw()   # ROADMAP 6: the reverse-foot handles of the picked foot
	_sec_draw()   # ROADMAP 26: the secondary chains (ponytail, cloth, bo) at the playhead, from their baked keys
	if hitbox_ui != null:
		hitbox_ui.draw_handles()   # ROADMAP 36: the picked box's end and radius handles
	_foot_plant_draw()   # ROADMAP 8: the footprint under a planted foot
	_cons_draw()   # CN: each active constraint's line from the part to what it follows


# ---------------------------------------------------------------- camera

## arrows slide the view (Shift+arrows turn around the body), PageUp / PageDown zoom; held = keeps moving
func _keys_camera(dt: float) -> void:
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is SpinBox:
		return
	var x := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
	var y := float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
	var z := float(Input.is_key_pressed(KEY_PAGEDOWN)) - float(Input.is_key_pressed(KEY_PAGEUP))
	if x == 0.0 and y == 0.0 and z == 0.0:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		yaw -= x * 90.0 * dt
		pitch = clampf(pitch + y * 60.0 * dt, -89.0, 89.0)
	else:
		var sp := dist * 0.6 * dt
		target += cam.global_basis.x * x * sp + cam.global_basis.y * y * sp
	dist = clampf(dist * (1.0 + z * 1.2 * dt), 0.4, 12.0)
	_cam()


## the camera looks at the body, shifted so the body sits in the middle of the free space between the panels
func _cam() -> void:
	if shot_through and _shot_apply():
		return   # THE SHOT CAMERA: looking through it, the view is the keyed camera (_shot_apply)
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	cam.transform = Transform3D(b, target + b * Vector3(0, 0, dist))
	var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600, 900)
	var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / vs.y
	cam.h_offset = (rw() - lw()) * 0.5 * mpp
	cam.v_offset = (bottom_h + 6 + LINE_H - TOP_H) * 0.5 * mpp * -1.0   # RR5: centred above the status line too


## THE CUBE'S VIEWS (round 22, GATES CC2, UPGRADES #22): look FROM direction d (the camera sits at target + d * dist),
## a face, an edge (two faces) or a corner (three). Smooth: the turn eases over VIEW_T seconds the short way round (yaw
## wrapped to within 180 of where it is). Keys 1-5 stay instant (_view): tests and the CLI shoot right after them
const VIEW_T := 0.3
const HOME := {"yaw": 0.0, "pitch": -8.0, "dist": 4.0, "target": Vector3(0, 0.95, 0)}   # the view the poser opens with
var _view_tw: Tween


func _view_dir(d: Vector3, smooth := true) -> void:
	d = d.normalized()
	var y1 := rad_to_deg(atan2(d.x, d.z))
	var p1 := clampf(-rad_to_deg(asin(clampf(d.y, -1.0, 1.0))), -89.0, 89.0)
	if absf(d.y) > 0.999:
		y1 = yaw   # straight up or down: keep the turn round the vertical as it is
	_turn_to(y1, p1, dist, target, smooth)


func _view_home(smooth := true) -> void:
	_turn_to(HOME["yaw"], HOME["pitch"], HOME["dist"], HOME["target"], smooth)


func _turn_to(y1: float, p1: float, d1: float, t1: Vector3, smooth: bool) -> void:
	if _view_tw != null and _view_tw.is_valid():
		_view_tw.kill()
	var y0 := yaw
	var y_goal := y1   # where it ends: the yaw asked for (the key views' own numbers, 180 not -180)
	y1 = y0 + wrapf(y1 - y0, -180.0, 180.0)   # the short way round
	if not smooth:
		yaw = y_goal
		pitch = p1
		dist = d1
		target = t1
		_cam()
		return
	var p0 := pitch
	var d0 := dist
	var t0 := target
	_view_tw = create_tween()
	_view_tw.tween_method(func(k: float):
		var e := ease(k, -2.0)   # in-out
		yaw = lerpf(y0, y1, e)
		pitch = lerpf(p0, p1, e)
		dist = lerpf(d0, d1, e)
		target = t0.lerp(t1, e)
		_cam(), 0.0, 1.0, VIEW_T)
	_view_tw.tween_callback(func(): yaw = y_goal; _cam())


func _view(k: int, smooth := false) -> void:
	var y := 0.0
	var p := -8.0
	match k:
		2: y = -90.0
		3: p = -89.0
		4: y = 180.0
		5: y = 90.0
		6: p = 89.0   # from below (the ViewCube's bottom face)
	_turn_to(y, p, dist, target, smooth)


# ---------------------------------------------------------------- picking + dragging

## PRECISE PICK (Nick 10-19: "100% precise to the body"): the body part is the one whose SKIN the ray meets first,
## on the mesh as drawn now (SkinPick.pick: the posed triangles, the part with the most skin weight at the hit point).
## The weapon keeps its capsule (it is not skinned); the nearer of the two wins, as before. Hidden parts: the ray goes
## through them (KK1)
func _pick(mp: Vector2) -> String:
	var t0 := Time.get_ticks_usec()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var hit: Array = skp.pick(o, d, hidden_parts)
	var best: String = hit[0]
	var best_t: float = hit[1]
	for j in (Body.WEAPON if B.wep_on else []):
		if hidden_parts.has(j):
			continue
		var c: Array = B.cap(j)
		var res := _ray_seg(o, d, c[0], c[1])
		if res.y <= maxf(float(B.rad[j]) * 1.15, 0.014) and res.x < best_t:
			best_t = res.x
			best = j
	_pick_t = best_t
	pick_us = Time.get_ticks_usec() - t0
	return best


static func _ray_seg(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Vector2:
	var u := b - a
	var w := o - a
	var A := d.dot(d)
	var Bq := d.dot(u)
	var C := u.dot(u)
	var D := d.dot(w)
	var E := u.dot(w)
	var den := A * C - Bq * Bq
	var t := 0.0
	if den > 1e-9:
		t = (A * E - Bq * D) / den
	t = clampf(t, 0.0, 1.0)
	var s := maxf(0.0, (u * t - w).dot(d) / A)
	return Vector2(s, ((o + d * s) - (a + u * t)).length())


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and not ev.pressed and hk != null:
		hk.released(ev as InputEventKey)   # the ? that is held: its cheat sheet hides
	if wp_on and _wp_input(ev):   # WEIGHT PAINT (ROADMAP 72): a press on the body paints, the rest of the mouse is the view's
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and ui_cmd.visible:
			ui_cmd.close()   # a click in the view puts the search away
		if mb.pressed:
			hover_part = ""   # a press ends the hover (the drag shows the selection)
			_fh_clear()
			if loa.armed and mb.button_index != MOUSE_BUTTON_LEFT:
				loa.armed = false   # ROADMAP 23: any other press cancels the line-of-action stroke
				_say("line of action cancelled")
			if mb.button_index == MOUSE_BUTTON_LEFT and nav_tool != "":   # the nav bar's Orbit / Pan tool (HH2)
				dragging = nav_tool
			elif mb.button_index == MOUSE_BUTTON_LEFT and loa.armed:
				loa.armed = false
				loa.begin(mb.position)
				dragging = "loa"
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if hitbox_ui != null and hitbox_ui.press(mb.position):   # ROADMAP 36: a box's handle, or a box picked in the view, takes the press
					return
				if _frh_press(mb.position):   # ROADMAP 6: a foot's roll handle takes the press
					return
				if _sph_press(mb.position):   # ROADMAP 61: a spine spline handle takes the press
					return
				if _trail_press(mb.position):   # ROADMAP 69: a key dot on a pinned part's trail takes the press
					return
				if _ikh_press(mb.position):   # IK2: an IK handle drawn here takes the press
					return
				var j := _pick(mb.position)
				var pp := _pick_prop(mb.position)
				var pa := _pick_actor(mb.position)   # TC4: another fighter's part, nearer than ours: it becomes the active one
				if int(pa[0]) >= 0 and (j == "" or float(pa[2]) < _pick_t) and (int(pp[0]) < 0 or float(pa[2]) < float(pp[1])):
					_actor_go(int(pa[0]))   # the view does not move (_stage_sync); the press goes on as a press on that part
					_say_plain("fighter %d of %d (%s): edits, cards and Ctrl+Z are this one's now" % [actor_on + 1, actors_rt.size(), "the hero" if actor_on == 0 else actors_rt[actor_on]["name"]])
					j = String(pa[1])
					_pick_t = float(pa[2])
					pp = [-1, INF]
				if int(pp[0]) >= 0 and (j == "" or float(pp[1]) < _pick_t):   # a prop in front of the body: the prop
					_prop_press(int(pp[0]), mb.position, float(pp[1]))
					return
				if sel_prop >= 0:
					sel_prop = -1
					_props_show()
				if j != "" and locked_parts.has(j):   # LOCKED (round 26, GG3): picked, never grabbed; no undo step
					sel = j
					playing = false
					_refresh()
					_say_plain("the %s is locked: right-click it > Unlock, or S and type 'unlock'" % nice(j))
				elif j != "":
					_drag_locks = _lock_snap()
					_num_start = B.state()   # Esc during the drag puts this back (HH1)
					_num_axis = 0
					_num_text = ""   # each drag types afresh
					_push_undo()
					undo[-1]["name"] = "Drag " + nice(j)   # ROADMAP 45: the drag's step is named by what it moved
					_tree.set_name(_tree.cur, undo[-1]["name"])
					_undo_tips()
					_group_press(j, mb.ctrl_pressed, mb.position)
					sel = j
					_clicked_part = true   # the tour's step 1 (clicking the part already picked counts too)
					_end_teach()   # RR5: the first pick ends the welcome, for good
					dragging = "joint"
					_grab = Vector3(NAN, NAN, NAN)
					_pd = {}
					_pd_mp = Vector2(NAN, NAN)
					if not j in Body.WEAPON and not j in ["hand_r", "hand_l", "foot_r", "foot_l"] and B.P.has(j) and sel_more.is_empty():   # a SET (Select: spine, Ctrl+click) turns every member by the same change (the old drag): PartDrag spreads or swings a turn its own way
						_pd = PartDrag.begin(B, j, cam.project_ray_origin(mb.position), cam.project_ray_normal(mb.position))
					playing = false
					_refresh()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				dragging = "orbit"
				_rpress = {"at": mb.position, "yaw": yaw, "pitch": pitch, "part": _pick(mb.position)}
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				dragging = "pan"
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				dist = maxf(0.5, dist * 0.9)
				_cam()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				dist = minf(12.0, dist / 0.9)
				_cam()
		else:
			var was := dragging
			dragging = ""
			_num_on = false
			if was == "prop":
				_prop_release()
			if was == "ik_handle":
				_ikh_release()
			if was == "spine_handle":
				_sph_release()
			if was == "trail_key":
				_trail_release()
			if was == "loa":
				_loa_release(mb.shift_pressed)
			if was == "foot_handle":
				_frh_release()
			if was == "box_handle" and hitbox_ui != null:
				hitbox_ui.release()   # ROADMAP 36: one undo step for a moved box handle
			# a right CLICK (not a drag) on a part: the ring. The few pixels it wobbled are not a turn: undone
			if was == "orbit" and mb.button_index == MOUSE_BUTTON_RIGHT and not _rpress.is_empty():
				if mb.position.distance_to(_rpress["at"]) < 5.0 and _rpress["part"] != "":
					yaw = _rpress["yaw"]
					pitch = _rpress["pitch"]
					_cam()
					_ring_open(_rpress["part"], mb.position)
				_rpress = {}
			if was == "joint" and not _gp.is_empty():
				_group_release(mb.position)
			if was == "joint" and not is_nan(_grab.x):
				if sel in ["hand_r", "hand_l"] and B.wep_on and B.wep_hand != "" and B.wep_hand != sel:
					var r := GripMagnet.drag(B, sel, _grab)   # NA6: the one full fit, on release (the drag was quick)
					_after_edit()
					if r != "free":
						_say("the %s %s the %s" % [nice(sel), {"snap": "holds", "held": "holds", "let go": "let go of"}[r], B.wep_kind.replace("_", " ")])
				_grab = Vector3(NAN, NAN, NAN)
				_refresh()   # the reach marker goes with the drag
			if was == "joint":
				_autokey_card()   # ROADMAP 42: the drag that moved the body keys a card at the playhead (its undo step is the press's)
	elif ev is InputEventMouseMotion and dragging != "":
		var mm := ev as InputEventMouseMotion
		var rel := mm.relative
		if dragging == "prop":
			_prop_move(mm.position)
			return
		if dragging == "ik_handle":
			_ikh_move(mm.position)
			return
		if dragging == "spine_handle":
			_sph_move(mm.position)
			return
		if dragging == "trail_key":
			_trail_move(mm.position)
			return
		if dragging == "loa":
			loa.add_point(mm.position)
			return
		if dragging == "foot_handle":
			_frh_move(mm.position)
			return
		if dragging == "box_handle":
			hitbox_ui.move(mm.position)
			return
		if dragging == "orbit":
			if shot_through:
				_shot_hand_over()   # as Blender: orbiting leaves the camera view, from where the camera was
			yaw -= rel.x * 0.4
			pitch = clampf(pitch - rel.y * 0.4, -89.0, 89.0)
			_cam()
		elif dragging == "pan":
			var k := dist * 0.0012
			target += -cam.global_basis.x * rel.x * k + cam.global_basis.y * rel.y * k
			_cam()
		elif dragging == "joint" and not _num_on:   # a typed angle holds the part (HH1)
			var before: Vector3 = B.ang[sel] if not sel in Body.WEAPON else Vector3.ZERO
			_pd_mp = mm.position
			_drag_joint(rel, mm.shift_pressed, mm.ctrl_pressed, mm.alt_pressed)
			_group_follow(before)
			if _lock_keep(_drag_locks):   # a hand's reach can turn a locked arm: it stays
				_refresh()
	elif ev is InputEventMouseMotion:
		_hover_at((ev as InputEventMouseMotion).position)
	elif ev is InputEventKey and ev.pressed:
		var k := ev as InputEventKey
		if not _pressing and (get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is SpinBox):
			return
		if hk.dispatch(k):   # a key the user gave a command (or a built-in key that moved away): scripts/hotkeys.gd
			return
		if k.keycode == KEY_ESCAPE and ui_keys != null and ui_keys.visible:
			keys_overlay(false)
			return
		if k.alt_pressed and not k.ctrl_pressed and k.keycode == KEY_E:   # Alt+E relax, Shift+Alt+E blend to the card before (Blender's keys; WW3)
			_step_hint = "Blend to previous card" if k.shift_pressed else "Relax to the in-between"
			_inbetween("prev" if k.shift_pressed else "relax")
			return
		if k.shift_pressed and not k.ctrl_pressed and not k.alt_pressed and k.keycode == KEY_E:   # Shift+E the breakdowner slider (XX4)
			_step_hint = "Breakdowner"
			_breakdowner_popup()
			return
		var combo: String = ("Ctrl+" if k.ctrl_pressed else "") + ("Shift+" if k.shift_pressed else "") + KEY_WORD.get(k.keycode, OS.get_keycode_string(k.keycode))
		for c in ui_cmd.commands:
			if c["keys"] == combo:
				_step_hint = c["name"]
				_why_cmd = c["name"]
		if k.ctrl_pressed:
			match k.keycode:
				KEY_Z: _undo()
				KEY_K: _toggle_autokey()   # ROADMAP 42: auto-key on / off (Ctrl+K)
				KEY_Y: _redo()
				KEY_S: _save_scene() if k.shift_pressed else _save_pose()   # Ctrl+Shift+S = the scene (round 15, V3)
				KEY_E: _inbetween("push")   # Ctrl+E push from the in-between (WW3)
				KEY_C: _copy_pose()
				KEY_V: _paste_pose("mirrored" if k.shift_pressed else "")
				KEY_BRACKETRIGHT: _marker_jump(true)
				KEY_BRACKETLEFT: _marker_jump(false)
			return
		match k.keycode:
			KEY_S:
				ui_cmd.open()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_view(k.keycode - KEY_0)
			KEY_R: _do(func(): _reset_part())
			KEY_Q: _do(func(): _snap(45.0 if k.shift_pressed else 90.0))
			KEY_M when k.shift_pressed: _tool(0)
			KEY_M: _do(func(): _mirror_side("_r"))
			KEY_N: _do(func(): _mirror_side("_l"))
			KEY_C:
				show_caps = not show_caps
				_refresh()
			# into the right hand, as its button says ("In right hand (B)"); already there = off (V3: a bat in the LEFT
			# hand used to come off, so B, B to move it)
			KEY_B when k.shift_pressed:   # before KEY_B (the bat): match takes the first pattern that fits
				bal.on = not bal.on
				_refresh()
				_say(("%s.  Green = inside the feet, amber = within 2 cm of the edge, red = he tips, grey = in the air" % bal.words()) if bal.on else "balance off")
			KEY_B: _do(func(): _bat_remove() if B.wep_on and B.wep_hand == "hand_r" else _bat_put("hand_r"))
			KEY_L: _do(func(): _bat_lock())
			KEY_F: _do(func(): _fingers_cycle())
			KEY_G: _do(_toggle_second)
			KEY_H: _dummy_toggle()
			KEY_K: _key_part()
			KEY_T when k.shift_pressed:
				if not sel in Body.BODY:
					_say("Shift+T pins a trail on a BODY part: click one first (the weapon's own trail is T)")
				elif sel == ov.auto_pin:
					ov.auto_pin = ""   # the trail shown while picked becomes a pin: it stays when another part is picked
					_refresh()
					_say("trail on %s pinned: it stays when you pick another part.  Shift+T again removes it." % sel)
				else:
					var on := ov.toggle_pin(sel)
					_refresh()
					_say(("trail pinned on %s (its end).  Shift+T again removes it.  %s" % [sel, ov.info]) if on else "trail on %s removed" % sel)
			KEY_T:
				ov.trail_on = not ov.trail_on
				ov.mark_dirty()
				wt.mark_dirty()
				_refresh()
				_say(ov.info if ov.trail_on else "motion trail off")
			KEY_O when k.shift_pressed:
				_tool(1)
			KEY_Y:
				_tool(2)
			KEY_O:
				ov.onion_on = not ov.onion_on
				_refresh()
				_say("onion skin: orange = the card before, green = the card after" if ov.onion_on else "onion skin off")
			KEY_BRACKETLEFT: _do(func(): B.grip_u = clampf(B.grip_u - 0.03, 0.0, B.wep_len))
			KEY_BRACKETRIGHT: _do(func(): B.grip_u = clampf(B.grip_u + 0.03, 0.0, B.wep_len))
			KEY_COMMA: _do(func(): _slide(-0.03))
			KEY_PERIOD: _do(func(): _slide(0.03))
			KEY_MINUS: _do(func(): B.set_weapon_len(B.wep_len - 0.05))
			KEY_EQUAL: _do(func(): B.set_weapon_len(B.wep_len + 0.05))
			KEY_SPACE: _toggle_play()
			KEY_TAB: _big_view()
			KEY_F6: _kb_enter()
			KEY_ENTER, KEY_KP_ENTER: _card_add()


func _drag_joint(rel: Vector2, twist: bool, move: bool, alt: bool) -> void:
	B.last_stop = {}
	var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / get_viewport().get_visible_rect().size.y
	var dw: Vector3 = cam.global_basis.x * rel.x * mpp - cam.global_basis.y * rel.y * mpp
	var tip := sel in ["hand_r", "hand_l", "foot_r", "foot_l"]
	if sel in Body.WEAPON:
		_drag_bat(rel, dw, twist, alt)
		return
	if sel == "pelvis" and move:
		B.offset += dw
		B.fk()
	elif twist:
		var v: Vector3 = B.ang[sel]
		B.set_ang_safe(sel, Vector3(v.x, v.y, v.z + rel.x * 0.5))
	elif tip and move:   # Ctrl+drag a hand / foot: swing the elbow / knee round, the end held (IK POLE)
		B.swing_pole(sel, rel.x * 0.5)
	elif tip and not alt:
		if is_nan(_grab.x):
			_grab = B.P[sel]
		_grab += dw
		# CONTACT (ROADMAP 88): a hand with contact on and a wall / table in the set is held on the nearest face, palm on it
		var faces: Array = ContactIK.surfaces(S.props) if ik_contact and sel in ["hand_r", "hand_l"] else []
		# THE MAGNET (round 47, GATES CC3): the free hand near the weapon the other hand holds snaps onto its handle,
		# slides and rolls along it, lets go when pulled off (no weapon in the other hand: the plain reach, as before)
		if not faces.is_empty():
			ContactIK.reach(B, sel, _grab, faces)
		elif sel in ["hand_r", "hand_l"]:
			_magnet = GripMagnet.drag(B, sel, _grab, true)   # NA6: quick while the mouse moves; searched once on release
		else:
			B.reach(sel, _grab)
	elif not _pd.is_empty() and not is_nan(_pd_mp.x) and _pd.get("part", "") == sel:
		var follow := Callable()
		if shoulder_follow and sel.begins_with("upperarm"):
			follow = func(): B.shoulder_follow(sel.right(2))   # YY5, inside the rounds so the handle still lands on the mouse
		PartDrag.move(B, _pd, cam.project_ray_origin(_pd_mp), cam.project_ray_normal(_pd_mp), follow)   # ROADMAP 41: any part, no mode
	else:
		var p: Vector3 = B.P[sel]
		var e: Vector3 = B.E[sel]
		if sel == "pelvis":
			e = B.P["neck_01"]
		var r1 := e - p
		var r2 := r1 + dw
		var ax := r1.cross(r2)
		if ax.length() > 1e-9:
			B.turn_world(sel, Quaternion(ax.normalized(), r1.angle_to(r2)))
	_arm_edit = sel if sel.begins_with("upperarm") and not move and (_pd.is_empty() or is_nan(_pd_mp.x)) else ""   # a part drag followed the shoulder itself
	_after_edit()
	var v2: Vector3 = B.ang[sel]
	if _magnet in ["snap", "held", "let go"] and tip and not move and not twist:
		var mw := {"snap": "SNAPPED onto the %s: both hands hold it now (drag along it to slide, round it to roll, away to let go)",
			"held": "SLIDING the hand on the %s", "let go": "LET GO of the %s"}
		_say(String(mw[_magnet]) % B.wep_kind.replace("_", " "))
		_magnet = ""
		return
	_magnet = ""
	var what: String = "ROLLING" if twist else ({"look": "LOOKING WITH", "bend": "BENDING THE SPINE AT", "move": "MOVING THE BODY BY"}.get(PartDrag.kind(sel), "ROTATING") if not _pd.is_empty() and not is_nan(_pd_mp.x) else ("MOVING" if (move and sel == "pelvis") else ("SWINGING THE %s OF" % ("ELBOW" if sel.begins_with("hand") else "KNEE") if tip and move else ("PULLING" if tip and not alt else "ROTATING"))))
	_say("%s the %s     %s%s" % [what, nice(sel), _angles_words(sel, v2), stop_words(B.last_stop)])


## A DRAG THAT STOPS SAYS WHY (round 35, GATES PP2): the reason Body.set_ang_safe recorded, in words; "" if it went
## all the way. Typed poses say "stopped short" the same way
func stop_words(st: Dictionary) -> String:
	if st.is_empty():
		return ""
	if st["kind"] == "limit":
		return "     STOPPED: the %s is at its limit, %s %.0f (its range %.0f to %.0f)" % [nice(st["joint"]), st["axis"], st["at"], st["lo"], st["hi"]]
	var ps: Array = st["pairs"]
	if ps.is_empty():
		return "     STOPPED: it would go deeper into the body"
	# the moving part first (the one below the dragged joint), the two deepest contacts, the rest counted
	var below := func(x: String) -> bool:
		var y := x
		while y != "":
			if y == st["joint"]:
				return true
			y = B.parent.get(y, "")
		return false
	var said := ps.slice(0, 2).map(func(q): return "the %s meets the %s" % ([nice(q[0]), nice(q[1])] if below.call(q[0]) or not below.call(q[1]) else [nice(q[1]), nice(q[0])]))
	return "     STOPPED: " + ", ".join(said) + ("  (+ %d more)" % (ps.size() - 2) if ps.size() > 2 else "")


func _drag_bat(rel: Vector2, dw: Vector3, turn: bool, spin: bool) -> void:
	if B.wep_hand != "":
		if is_nan(_grab.x):
			_grab = B.P[B.wep_hand]
		_grab += dw
		B.reach(B.wep_hand, _grab)
		_after_edit()
		_say("the bat is LOCKED in the %s: dragging it moves the hand.  'Free the bat' to move it alone." % nice(B.wep_hand))
		return
	if spin:
		var axis: Vector3 = (B.wep_rot * Vector3.UP).normalized()
		B.move_weapon(Vector3.ZERO, Quaternion(axis, deg_to_rad(rel.x * 0.6)))
		_say("SPINNING the bat about its length")
	elif turn:
		var R := Quaternion(cam.global_basis.y, deg_to_rad(rel.x * 0.5)) * Quaternion(cam.global_basis.x, deg_to_rad(rel.y * 0.5))
		B.move_weapon(Vector3.ZERO, R)
		_say("TURNING the bat about its knob")
	else:
		B.move_weapon(dw, Quaternion.IDENTITY)
		_say("MOVING the bat")
	_after_edit()


# ---------------------------------------------------------------- actions

## run an edit with undo, then refresh
func _do(f: Callable) -> void:
	_push_undo()
	var keep := _lock_snap()
	f.call()
	_lock_keep(keep)   # a locked part keeps its angles through Reset, Mirror, Snap, a pose... (round 26, GG3)
	_autokey_card()   # ROADMAP 42: with auto-key on, the change keys a card at the playhead (same undo step)
	_after_edit()
	_journal_write()   # ROADMAP 2: the scene as this edit left it, in the journal


## WORDS TO A POSE (round 13, #93): "raise the right arm 90, bend the left elbow 45" (scripts/pose_words.gd). ONE undo
## step. Every op is reported with what was asked and what the joint REACHED (a limit or a contact stops it)
func _pose_words(text: String) -> Dictionary:
	var r := PoseWords.parse(text)
	if not r["ok"]:
		_say(r["error"])
		return r
	var rep := []
	_do(func():
		var carry := 0.0   # a chest turn one spine joint couldn't take (a limit, a contact) goes on to the next one up
		for op in r["ops"]:
			var j: String = op["joint"]
			var v: Vector3 = B.ang[j]
			var want := v
			want[op["axis"]] = op["deg"] if op["mode"] == "to" else v[op["axis"]] + op["deg"] + (carry if j.begins_with("spine_0") else 0.0)
			B.set_ang_safe(j, want)
			var got: float = B.ang[j][op["axis"]]
			carry = want[op["axis"]] - got if j.begins_with("spine_0") and j != "spine_03" and op["mode"] == "by" else 0.0
			rep.append({"joint": j, "axis": PoseWords.AXES[op["axis"]], "asked": snappedf(want[op["axis"]], 0.01), "reached": snappedf(got, 0.01),
				"stopped": absf(got - want[op["axis"]]) > 0.05}))
	sel = r["ops"][-1]["joint"]
	var stopped := rep.filter(func(x): return x["stopped"])
	_say("posed: %s%s" % [text, ("   (stopped short: %s)" % ", ".join(stopped.map(func(x): return "%s %s %.0f° of %.0f°" % [nice(x["joint"]), x["axis"], x["reached"], x["asked"]]))) if not stopped.is_empty() else ""])
	return {"ok": true, "ops": rep}


func _after_edit() -> void:
	if not vdiff.is_empty():   # COMPARE WITH: the marks follow the open scene's edits
		_vdiff_update()
	if shoulder_follow and _arm_edit != "":   # YY5: only a hand edit of an upper arm; never a load, paste or play
		B.shoulder_follow(_arm_edit.right(2))
	_arm_edit = ""
	if symmetry:
		_mirror_changed()
	B.apply_grip()
	_refresh()


## SYMMETRY MODE (round 22, GATES CC1, UPGRADES #65): while on, an edit on one side moves its twin, reflected the way
## Copy side does (bend, side, -twist). Only the joints the edit CHANGED since the last refresh are copied, so dragging
## an arm leaves the legs as they were, and the middle (its own twin) is never touched. Runs inside the edit's own undo
## step: one Ctrl+Z takes back both sides
var symmetry := false
var shoulder_follow := true   # YY5: raising an upper arm by hand brings its collarbone (Body.shoulder_follow)
var _arm_edit := ""           # the upper arm the current slider / drag edit turned ("" = none): what follows it
var _sym_prev := {}   # the angles at the last refresh: what an edit is measured against


func _mirror_changed() -> void:
	var moved := false
	for j in Body.ORDER:
		var t := Body.twin(j)
		if t == j or not _sym_prev.has(j) or (B.ang[j] as Vector3).is_equal_approx(_sym_prev[j]):
			continue
		if not (B.ang[t] as Vector3).is_equal_approx(_sym_prev[t]):
			continue   # both sides changed (Copy side, Mirror pose, a pasted pose): the edit already set them
		var v: Vector3 = B.ang[j]
		B.ang[t] = B.clamp_ang(t, Vector3(v.x, v.y, -v.z))
		moved = true
	if moved:
		B.fk()


func _toggle_symmetry() -> void:
	symmetry = not symmetry
	_refresh()
	_say("symmetry ON: drag a part on one side and its twin on the other side follows, reflected" if symmetry else "symmetry off: each side moves on its own")


## AUTO-KEY (ROADMAP 42): while on, a pose change made at the playhead keys a card there. A card whose arrival or hold
## holds the playhead takes the body as its pose; otherwise a new card goes into the sequence at the playhead. A view
## setting: not saved, and it is not an undo step of its own (the change it keys is one step with it)
var auto_key := false
var ui_akey: Control   # the red frame round the 3D view while auto-key is on (the view's edges, Tok "autokey")


func _toggle_autokey() -> void:
	auto_key = not auto_key
	if ui_akey != null:
		ui_akey.visible = auto_key
		ui_akey.queue_redraw()
	_refresh()
	_say("Auto-key ON: changes make keys" if auto_key else "Auto-key off: changes stay in the body until you key them")


## the frame sits on the 3D view: between the side panels, under the top bar, above the status line and the timeline
func _build_akey_frame() -> void:
	ui_akey = Control.new()
	ui_akey.name = "autokey_frame"
	ui_akey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_akey.visible = auto_key
	ui_akey.draw.connect(func(): ui_akey.draw_rect(Rect2(Vector2(2, 2), ui_akey.size - Vector2(4, 4)), Tok.c("autokey"), false, 4.0))   # inset: the 4 px band lies inside the view
	ui_root.add_child(ui_akey)
	ui_root.move_child(ui_akey, -1)   # drawn over the panels that touch the view's edges
	_place_akey_frame()


func _place_akey_frame() -> void:
	if ui_akey == null:
		return
	var vs := get_viewport().get_visible_rect().size
	ui_akey.offset_left = lw()
	ui_akey.offset_right = vs.x - rw()
	ui_akey.offset_top = TOP_H
	ui_akey.offset_bottom = vs.y - bottom_h - LINE_H - 6
	ui_akey.queue_redraw()


## a change to the body at the playhead, once it is made (the undo step is already pushed: it covers the card too)
func _autokey_card() -> void:
	if not auto_key or undo.is_empty():
		return
	if undo.back().get("body") == B.state():
		return   # nothing moved: no card
	var ci := LimbIK.card_at(S, playhead)
	if ci >= 0:
		S.cards[ci]["pose"] = B.to_dict()
		_rebuild_cards()
		_say("Auto-key: card %d takes the body at %s" % [ci + 1, Units.time(playhead, S.fps)])
		return
	var at := S.cards.size()
	var ts := S.times()
	for i in ts.size():
		if playhead < float(ts[i][1]) - 0.001:
			at = i
			break
	var prev_end := float(ts[at - 1][2]) if at > 0 else 0.0
	S.add("auto key %d" % (S.cards.size() + 1), B.to_dict(), at)
	if at > 0:
		S.cards[at]["move"] = snappedf(maxf(0.04, playhead - prev_end), 0.001)   # the card arrives at the playhead
	sel_card = at
	_rebuild_cards()
	_refresh()
	_say("Auto-key: card %d keyed at %s" % [at + 1, Units.time(playhead, S.fps)])


func _big_view() -> void:
	big_view = not big_view
	_sides_apply()
	_say("big view: the side panels are hidden (Tab brings them back)" if big_view else "panels back")


## an undo step = the body AND the open scene's cards (10-14: a Fix or "+ tween" changes cards, so Ctrl+Z must bring
## them back). The cards come back only into the scene they were taken from: opening another scene makes them stale.
func _snapshot() -> Dictionary:
	_actors_sync()
	var H := _hero_scene()
	# TC3: tagged with the actor it was taken on, and the actors as they are (the same Body / Scene objects: an add or a
	# remove is undone by putting the list back), so _restore never puts one actor's body onto another
	return {"actor": actor_on, "hero": H, "hero_actors": H.actors.duplicate(), "rt": actors_rt.map(func(a): return (a as Dictionary).duplicate()),
		"body": B.state(), "pbody": S.body.duplicate(true), "scene": S,"cards": S.cards.duplicate(true), "sel": sel_card, "holds": S.moving_holds, "fps": S.fps,
		"props": S.props.map(func(p): return Props.to_dict(p)), "pk": S.part_keys.duplicate(true),
		"markers": S.markers.duplicate(true), "fitness": S.fitness, "breath": S.breath, "layer": S.layer.duplicate(), "layer_w": S.layer_w,
		"layers": S.layers.duplicate(true), "ik": S.ik.duplicate(true),   # IK keys (limb_ik.gd), undone like a card
		"secondary": S.secondary.duplicate(true),   # SECONDARY MOTION (ROADMAP 26), undone like a card
		"skin_w": SkinPaint.snapshot(wp),   # WEIGHT PAINT (ROADMAP 72): every stroke is one step, undone with the weights
		"plants": S.plants.duplicate(true),   # foot plants (foot_plant.gd), undone like a card
		"drivers": S.drivers.duplicate(true),   # user drivers (drivers.gd), undone like a card
		"audio": S.audio.duplicate(),   # the sound on the timeline (AudioTrack), undone like a card
		"lip": S.lip.duplicate(true),   # the lip-sync channel (lip_sync.gd), undone like a card
		"face": S.face.duplicate(true),   # THE FACE keys (face.gd), undone like a card
		"attrs": S.attrs.duplicate(true),   # CUSTOM ATTRIBUTES (custom_attr.gd, ROADMAP 82), undone like a card
		"beats_audio": S.beats_audio.duplicate(true),   # ROADMAP 32: the music beats, undone like a card
		"cons": S.cons.duplicate(true),   # constraints (round 51, constraints.gd), undone like a card
		"shots": H.shots.duplicate(true),   # THE SHOTS (ROADMAP 75; shot_camera.gd), the hero's, undone like a card
		"beats": H.beats.duplicate(true),   # ROADMAP 13: the exchange's beats (the hero's), undone like a card
		"notes": S.notes.duplicate(true),   # ROADMAP 29: the review notes, undone like a marker
		"sets": S.sets.duplicate(true),   # selection / keying sets (part_sets.gd), undone like a card
		"clips": S.clips.duplicate(true),   # CLIPS (clips.gd), undone like a card
		"boxes": S.boxes.duplicate(true),   # HIT / HURT BOXES (hit_boxes.gd), undone like a card
		"others": actors_rt.map(func(a): return {"S": a["S"], "cards": (a["S"] as Scene).cards.duplicate(true)}),   # ROADMAP 53: every fighter's cards (a copy writes the other one's)
		"flags": BAKE_FLAGS.map(func(f): return S.get(f))}   # DD4: the playback switches a bake turns off


const BAKE_FLAGS := ["on_floor", "pin", "spline", "stepped", "natural", "floor_body"]


func _restore(u: Dictionary) -> void:
	if mm_ui != null:
		mm_ui.halt()   # a motion matching preview ends with the step taken back: it would play over the restored pose
	if _actors_restore(u) or not actors_rt.is_empty():   # TC3: onto the actor the step was taken on first (its own body and scene)
		ov.mark_dirty()
		wt.mark_dirty()
		_rebuild_cards()
	if u["scene"] == S and u.has("fps"):
		S.fps = int(u["fps"])   # WW4: the frame rate is a scene setting, undone like a card
	if u["scene"] == S and u.has("pbody") and u["pbody"] != S.body:
		S.body = u["pbody"].duplicate(true)   # PR1: the proportions, undone like a card (the body's come back in its state)
		ov.mark_dirty()
		wt.mark_dirty()
	B.set_state(u["body"])   # lossless (round 8): from_dict re-solved from the file's rounded numbers
	if u["scene"] == S and u.get("holds", S.moving_holds) != S.moving_holds:   # a scene setting, undone like a card
		S.moving_holds = u["holds"]
		_rebuild_cards()
	if u["scene"] == S and u.has("markers") and JSON.stringify(u["markers"]) != JSON.stringify(S.markers):
		S.markers = u["markers"].duplicate(true)   # WW5: the markers, undone like a card
		if ui_timeline != null:
			ui_timeline.queue_redraw()
	if u["scene"] == S and u.has("notes") and JSON.stringify(u["notes"]) != JSON.stringify(S.notes):
		S.notes = u["notes"].duplicate(true)   # ROADMAP 29: the review notes, undone like a marker
		if ui_timeline != null:
			ui_timeline.queue_redraw()
	if u.has("beats") and u.get("hero") == _hero_scene() and var_to_str(u["beats"]) != var_to_str(_hero_scene().beats):
		_hero_scene().beats = u["beats"].duplicate(true)   # ROADMAP 13: the beats, undone like a card
		if ui_choreo != null and is_instance_valid(ui_choreo.win):
			ui_choreo.refresh()
	if u["scene"] == S and u.has("props") and JSON.stringify(u["props"]) != JSON.stringify(S.props.map(func(p): return Props.to_dict(p))):
		S.props = u["props"].map(func(q): return Props.from_dict(q))   # the set, undone like a card (SS5)
		if sel_prop >= S.props.size():
			sel_prop = -1
		_props_show()
	if u["scene"] == S and u.has("pk"):
		S.part_keys = u["pk"].duplicate(true)   # PART KEYS (WW1), undone like a card
	if u["scene"] == S and u.has("attrs") and var_to_str(u["attrs"]) != var_to_str(S.attrs):
		S.attrs = u["attrs"].duplicate(true)   # CUSTOM ATTRIBUTES (ROADMAP 82), undone like a card
		_attr_sig = ""
		_attr_refresh()   # the rows of an undone add go, and come back on redo, without waiting for the next refresh
	if u["scene"] == S and u.has("secondary") and var_to_str(u["secondary"]) != var_to_str(S.secondary):
		S.secondary = u["secondary"].duplicate(true)   # SECONDARY MOTION (ROADMAP 26), undone like a card
	if u["scene"] == S and u.has("ik") and var_to_str(u["ik"]) != var_to_str(S.ik):
		S.ik = u["ik"].duplicate(true)   # IK keys (limb_ik.gd), undone like a card
		_dummy_hits()
	if u["scene"] == S and u.has("sets") and var_to_str(u["sets"]) != var_to_str(S.sets):
		S.sets = u["sets"].duplicate(true)   # selection / keying sets (part_sets.gd), undone like a card
		if ui_browser != null:
			ui_browser.refresh()
	if u["scene"] == S and u.has("drivers") and var_to_str(u["drivers"]) != var_to_str(S.drivers):
		S.drivers = u["drivers"].duplicate(true)   # user drivers (GAP row 15), undone like a card
	if u.has("skin_w") and not wp.is_empty():
		SkinPaint.restore(wp, u["skin_w"])
		_skp_build()
	if u["scene"] == S and u.has("plants") and var_to_str(u["plants"]) != var_to_str(S.plants):
		S.plants = u["plants"].duplicate(true)   # foot plants (ROADMAP 8), undone like a card
	if u["scene"] == S and u.has("cons") and var_to_str(u["cons"]) != var_to_str(S.cons):
		S.cons = u["cons"].duplicate(true)   # constraints (round 51), undone like a card
		_dummy_hits()
	if u.has("shots") and var_to_str(u["shots"]) != var_to_str((u.get("hero", S) as Scene).shots):
		(u.get("hero", S) as Scene).shots = u["shots"].duplicate(true)   # the shots and their cameras, undone like a card (ROADMAP 75)
		if ui_timeline != null:
			ui_timeline.queue_redraw()
	if u["scene"] == S and u.has("clips") and var_to_str(u["clips"]) != var_to_str(S.clips):
		S.clips = u["clips"].duplicate(true)   # CLIPS, undone like a card
		_dummy_hits()
	if u["scene"] == S and u.has("lip") and var_to_str(u["lip"]) != var_to_str(S.lip):
		S.lip = u["lip"].duplicate(true)   # the lip-sync channel, undone like a card
	if u["scene"] == S and u.has("face") and var_to_str(u["face"]) != var_to_str(S.face):
		S.face = u["face"].duplicate(true)   # THE FACE (ROADMAP 74), undone like a card
	if u["scene"] == S and u.has("boxes") and var_to_str(u["boxes"]) != var_to_str(S.boxes):
		S.boxes = u["boxes"].duplicate(true)   # HIT / HURT BOXES (ROADMAP 36), undone like a card (the view and the lane follow in _refresh)
	if u["scene"] == S and u.has("audio") and JSON.stringify(u["audio"]) != JSON.stringify(S.audio):
		S.audio = u["audio"].duplicate()   # the sound, undone like a card
		_audio_reload()
	if u["scene"] == S and u.has("beats_audio") and var_to_str(u["beats_audio"]) != var_to_str(S.beats_audio):
		S.beats_audio = u["beats_audio"].duplicate(true)   # ROADMAP 32: the music beats, undone like a card
		if ui_timeline != null:
			ui_timeline.queue_redraw()
	if u["scene"] == S and u.has("flags"):
		for k in BAKE_FLAGS.size():   # DD4: Ctrl+Z on a bake gives the floor, the pins, spline ... back
			S.set(BAKE_FLAGS[k], u["flags"][k])
	if u["scene"] == S and u.has("fitness"):
		S.fitness = u["fitness"]   # FATIGUE (ROADMAP 39): the fitness slider, undone with the retime it came with
	if u["scene"] == S and u.has("layers") and var_to_str(u["layers"]) != var_to_str(S.layers):
		S.layers = u["layers"].duplicate(true)   # NA1: the layers, undone like a card
		_dummy_hits()
	if u["scene"] == S and u.has("layer") and (u["breath"] != S.breath or u["layer"] != S.layer or u["layer_w"] != S.layer_w):
		S.breath = u["breath"]   # BREATH (YY6) and the LAYER (YY9): scene settings, undone like a card (the undo audit
		S.layer = u["layer"].duplicate()   # did not fingerprint them, so a lost breath / layer passed it)
		S.layer_w = u["layer_w"]
		_dummy_hits()
	if u["scene"] == S and JSON.stringify(u["cards"]) != JSON.stringify(S.cards):
		S.cards = u["cards"].duplicate(true)
		sel_card = mini(u["sel"], S.cards.size() - 1)
		_rebuild_cards()
		if ui_find != null and ui_find.visible:
			_check()   # the findings were for the cards just put back
	for e in u.get("others", []):   # ROADMAP 53: the other fighters' cards, undone as well; re-posed at the playhead
		var oS: Scene = e["S"]
		if oS != S and var_to_str(e["cards"]) != var_to_str(oS.cards):
			oS.cards = e["cards"].duplicate(true)
			for a in actors_rt:
				if a["S"] == oS:
					a["t"] = NAN
	_refresh()


func _push_undo() -> void:
	if _macro_nest > 0:   # ROADMAP 81: a macro's edits share the one undo step, opened before its first edit
		if _macro_pushed:
			return
		_macro_pushed = true
	_tree_sync()
	if _jpending:
		_journal_write()   # the scene now is the last step's result: journaled before this step changes anything
	var u := _snapshot()
	if _step_hint != "":
		u["hint"] = step_name(_step_hint)
	_step_hint = ""
	undo.append(u)
	_tree.push(u)   # a new branch node when there was a redo: the abandoned future stays in the tree
	_undo_tips()
	_history_rows.call_deferred()
	if undo.size() > 60:
		undo.pop_front()
		_tree.trim_root()
	redo.clear()
	_jpending = true
	_co_sync()


func _undo() -> void:
	_tree_sync()
	if undo.is_empty():
		_say("nothing to undo yet: click a part and drag it, and Ctrl+Z will take that back")
		return
	var u: Dictionary = undo.pop_back()
	_actor_set(int(u.get("actor", 0)))   # TC3: the redo step is taken on the actor this step changes
	var now := _snapshot()
	now["name"] = _step_label(u)   # the step keeps its name on the way back and forth
	redo.append(now)
	_tree.step_back(now)
	_restore(u)
	_say("undone: " + now["name"])
	_toast("Undid: " + now["name"])
	_undo_tips()
	_history_rows()
	_jpending = true
	_co_sync()


func _redo() -> void:
	_tree_sync()
	if redo.is_empty():
		return
	var r: Dictionary = redo.pop_back()
	_actor_set(int(r.get("actor", 0)))   # TC3: as _undo
	var now := _snapshot()
	now["name"] = _step_label(r)
	undo.append(now)
	_tree.step_forward(now)
	_restore(r)
	_say("redone: " + now["name"])
	_toast("Redid: " + now["name"])
	_undo_tips()
	_history_rows()
	_jpending = true
	_co_sync()


## an edit that moved nothing is taken back out: its step, and its node in the tree
func _drop_undo() -> void:
	_tree_sync()
	undo.pop_back()
	_tree.drop_cur()
	_undo_tips()
	_history_rows.call_deferred()


## the undo list cut to n0 + 1 entries, so the steps since state n0 are ONE step named `step` (ai_box's calls)
func _squash_undo(n0: int, step: String) -> void:
	_tree_sync()
	if n0 < 0 or undo.size() <= n0:
		return
	undo.resize(n0 + 1)
	_tree.squash(n0)
	undo[n0]["hint"] = step
	_tree.set_hint(_tree.cur, step)
	_undo_tips()
	_history_rows.call_deferred()


## the tree and the lists must agree: the lists are what Ctrl+Z / Ctrl+Y read, so when something outside the tree
## changed them (a list cleared, or cut), the tree is rebuilt from the lists: the same states, the same names
func _tree_sync() -> void:
	if _tree.path().size() - 1 == undo.size() and _tree.forward().size() == redo.size():
		return
	_tree.reset()
	for i in undo.size():   # undo[i] = the state before step i + 1: push labels the node it makes with its name / hint
		_tree.push(undo[i])
	var p := _tree.cur
	for j in range(redo.size() - 1, -1, -1):   # redo[-1] is the state right after the live one; its name is its own
		p = _tree.add(p, redo[j], redo[j])


## the History panel's click: the work goes to node `id` (any step, on any branch). One action, not an undo step: the
## lists are rebuilt from the tree, so Ctrl+Z walks back from there along the branch the node is on
func _tree_go(id: int) -> void:
	_tree_sync()
	if id == _tree.cur or not _tree.has(id) or _tree.node(id)["state"] == null:
		return
	var target: Dictionary = _tree.node(id)["state"]
	_actor_set(int(target.get("actor", 0)))
	var now := _snapshot()
	_tree.jump(id, now)
	undo.clear()
	redo.clear()
	var p := _tree.path()
	for i in p.size() - 1:
		var e: Dictionary = _tree.node(p[i])["state"]
		e["name"] = _step_label(_tree.node(p[i + 1]))
		undo.append(e)
	var fw := _tree.forward()
	for k in range(fw.size() - 1, -1, -1):
		var e2: Dictionary = _tree.node(fw[k])["state"]
		e2["name"] = _step_label(_tree.node(fw[k]))
		redo.append(e2)
	_restore(target)
	_say("history: %d step%s done" % [undo.size(), "" if undo.size() == 1 else "s"])
	_undo_tips()
	_history_rows()
	_jpending = true


# ---------------------------------------------------------------- actors (round 50, GATES TC3)

## a file xf {"pos": [x, z], "yaw": deg} as the transform from that actor's body space into the hero's
static func actor_xf(xf: Dictionary) -> Transform3D:
	var p: Array = xf.get("pos", [0.0, 0.0])
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(xf.get("yaw", 0.0)))), Vector3(float(p[0]), 0.0, float(p[1])))


## the hero's scene (actor 0): what the file is, whoever is active
func _hero_scene() -> Scene:
	if actors_rt.size() > actor_on and actors_rt[actor_on]["S"] == S:
		return actors_rt[0]["S"]
	return S


## the hero's body, whoever is active
func _hero_body() -> Body:
	return B if _hero_scene() == S else actors_rt[0]["B"]


## actors_rt made from hero_S.actors (each actor keeps the Body it had: a rebuild never resets a pose)
func _actors_build(hero_B: Body, hero_S: Scene) -> void:
	var had := {}
	for a in actors_rt:
		had[a["S"]] = a["B"]
	actors_rt = []
	if hero_S.actors.is_empty():
		return
	actors_rt.append({"name": "hero", "B": hero_B, "S": hero_S, "xf": Transform3D.IDENTITY, "t": NAN})
	for a in hero_S.actors:
		var b: Body = had.get(a["scene"])
		if b == null:   # a body of its own, made as the hero's (_ready); posed from its scene by _pose_others
			b = Body.new()
			b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			b.fk()
		actors_rt.append({"name": a["name"], "B": b, "S": a["scene"], "xf": actor_xf(a["xf"]), "t": NAN})
	Constraints.link(hero_S)   # round 51: each fighter's scene can read the others (a head that looks at the other fighter)


## actors_rt kept in step with the open scene: a scene opened, made new or recovered (or an agent's "new" that sets S
## straight) is the hero now, with the actors its file lists
func _actors_sync() -> void:
	if actors_rt.is_empty():
		actor_on = 0
		if not S.actors.is_empty():
			_actors_build(B, S)
		return
	if actor_on >= actors_rt.size() or actors_rt[actor_on]["S"] != S or actors_rt[actor_on]["B"] != B:
		actor_on = 0
		actors_rt = []
		_actors_build(B, S)


## back to the hero and one actor list no more (before a scene is opened, made new or recovered)
func _actors_home() -> void:
	if not actors_rt.is_empty() and actor_on != 0 and actors_rt[actor_on]["S"] == S:
		B = actors_rt[0]["B"]
		S = actors_rt[0]["S"]
	actor_on = 0
	actors_rt = []


## B and S become actor k's (quiet: no refresh). The actor left keeps its pose until the playhead moves
func _actor_set(k: int) -> bool:
	_actors_sync()
	if k == actor_on or k < 0 or k >= actors_rt.size():
		return false
	if co != null and co.connected() and co.may_edit(k) != "":
		_say(co.may_edit(k) + " Or press Co-edit: stop to animate it yourself.")   # ROADMAP 30: the other animator's fighter is read only here
		return false
	actors_rt[actor_on]["t"] = playhead
	actor_on = k
	B = actors_rt[k]["B"]
	S = actors_rt[k]["S"]
	sel_card = mini(sel_card, S.cards.size() - 1)
	_stage_sync()   # TC4: the new active actor at the origin, the view moved with it (no jump)
	return true


## an undo / redo step's actors put back (an add or a remove undone), then its actor made active. True if B / S changed
func _actors_restore(u: Dictionary) -> bool:
	if not u.has("actor"):
		return false
	_actors_sync()
	var H := _hero_scene()
	var moved := false
	if u.get("hero") == H and not _same_actors(u["hero_actors"], H.actors):
		if actor_on != 0:
			B = actors_rt[0]["B"]
			S = actors_rt[0]["S"]
			actor_on = 0
			moved = true
		H.actors = (u["hero_actors"] as Array).duplicate()
		actors_rt = (u["rt"] as Array).map(func(a): return (a as Dictionary).duplicate())
		for a in actors_rt:
			a["t"] = NAN   # posed again at the playhead
	return _actor_set(int(u["actor"])) or moved


static func _same_actors(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i]["scene"] != b[i]["scene"]:
			return false
	return true


## THE HOOK (TC3): every refresh, each actor that is not active is posed from its own scene at the playhead (once per
## playhead: an actor left keeps its own edits until the playhead moves). Drawing them is TC4. One actor: returns at once
## LIVE CO-EDITING (ROADMAP 30, scripts/co_edit.gd). Commands: "Co-edit: host" (a confirm first; then it listens on every
## network address, so other computers can join; the port is typed in the dialog), "Co-edit: join" (address:port),
## "Co-edit: stop". The host's owned fighter is the active one when it hosts; the joiner's is the active one when it
## joins. The other fighter is drawn at its peer's playhead and cannot be made active here (_actor_set refuses it).
var ui_co_line: Label
var ui_co_dlg: ConfirmationDialog
var ui_co_port: LineEdit
var ui_co_join_dlg: ConfirmationDialog
var ui_co_addr: LineEdit
var _co_where := ""       # the address:port the session is on (the host's, or the one joined)
var _co_line_text := ""   # the status line's text as last set (set only when it changes)


func _co_dialogs() -> void:
	if ui_co_dlg != null:
		return
	ui_co_dlg = ConfirmationDialog.new()
	ui_co_dlg.name = "co_host_dialog"
	ui_co_dlg.title = "Host a live co-edit"
	ui_co_dlg.dialog_autowrap = true
	ui_co_dlg.min_size = Vector2i(440, 0)
	ui_co_dlg.dialog_text = "Other computers on your network can connect while hosting.\nEach side animates one fighter. The host saves the scene.\nPort (the guests type address:port):"
	ui_co_dlg.ok_button_text = "Host on the network"
	ui_co_port = LineEdit.new()
	ui_co_port.name = "co_port"
	ui_co_port.text = "4242"
	ui_co_dlg.add_child(ui_co_port)
	ui_co_dlg.register_text_enter(ui_co_port)
	ui_co_dlg.confirmed.connect(func(): _co_host(int(ui_co_port.text), true))
	ui_co_dlg.canceled.connect(func(): _say("live co-edit: not hosted"))
	add_child(ui_co_dlg)
	ui_co_join_dlg = ConfirmationDialog.new()
	ui_co_join_dlg.name = "co_join_dialog"
	ui_co_join_dlg.title = "Join a live co-edit"
	ui_co_join_dlg.dialog_autowrap = true
	ui_co_join_dlg.min_size = Vector2i(440, 0)
	ui_co_join_dlg.dialog_text = "The host's address and port, as the host's status line shows them (address:port):"
	ui_co_join_dlg.ok_button_text = "Join"
	ui_co_addr = LineEdit.new()
	ui_co_addr.name = "co_addr"
	ui_co_addr.placeholder_text = "192.168.0.10:4242"
	ui_co_join_dlg.add_child(ui_co_addr)
	ui_co_join_dlg.register_text_enter(ui_co_addr)
	ui_co_join_dlg.confirmed.connect(func(): _co_join_text(ui_co_addr.text))
	add_child(ui_co_join_dlg)


func _co_host_ask() -> void:
	_co_dialogs()
	if co != null:
		_say("a live co-edit is on already (%s): press Co-edit: stop to end it" % _co_where)
		return
	ui_co_dlg.popup_centered()


func _co_join_ask() -> void:
	_co_dialogs()
	if co != null:
		_say("a live co-edit is on already (%s): press Co-edit: stop to end it" % _co_where)
		return
	ui_co_join_dlg.popup_centered()


func _co_stop_cmd() -> void:
	if co == null:
		_say("no live co-edit is on: run Co-edit: host or Co-edit: join to start one")
		return
	_co_stop()
	_say("live co-edit stopped: both scenes keep their work")


func _co_join_text(t: String) -> void:
	var s := t.strip_edges()
	var i := s.rfind(":")
	if i <= 0 or not s.substr(i + 1).is_valid_int():
		_say("write the host's address and port as address:port, e.g. 192.168.0.10:4242 (type it in the box)")
		return
	_co_join(s.substr(0, i), int(s.substr(i + 1)))


func _co_fighters() -> void:
	_actors_sync()
	if co != null:
		co.fighters = actors_rt.map(func(a): return a["S"])


func _co_host(port: int, lan_confirmed: bool) -> void:
	_co_stop(false)
	if port <= 0 or port > 65535:
		_say("the port is a number from 1 to 65535: type it again")
		return
	_actors_sync()
	if actors_rt.size() < 2:
		_say("live co-edit needs two fighters: add a second one first")
		return
	co = CoEdit.new()
	co.on_applied = Callable(self, "_co_applied")
	_co_fighters()
	var bind := "*" if lan_confirmed else CoEdit.LOOPBACK   # confirmed: every network address, the LAN included
	var err := co.host(port, bind, actor_on)
	if err != "":
		_say(err)
		co = null
		return
	var where: Array = []
	if lan_confirmed:
		for a in CoEdit.addresses().split(", ", false):
			where.append("%s:%d" % [a, port])
	_co_where = ", ".join(where) if not where.is_empty() else "127.0.0.1:%d" % port
	_say("live co-edit: hosting, fighter %d is yours. Join at %s" % [actor_on + 1, _co_where])
	_co_status()


func _co_join(addr: String, port: int) -> void:
	_co_stop(false)
	if port <= 0 or port > 65535:
		_say("the port is a number from 1 to 65535: type it again")
		return
	_actors_sync()
	co = CoEdit.new()
	co.on_applied = Callable(self, "_co_applied")
	_co_fighters()
	var err := co.join(addr, port, actor_on)
	if err != "":
		_say(err)
		co = null
		return
	_co_where = "%s:%d" % [addr, port]
	_say("live co-edit: joining %s as fighter %d" % [_co_where, actor_on + 1])
	_co_status()


func _co_stop(say := true) -> void:
	if co != null:
		co.close()
		co = null
		_co_seen = ""
		_co_where = ""
		for a in actors_rt:
			a.erase("pt")
		_pose_others()
	_co_status()
	if say:
		_say("live co-edit stopped")


## the status line: who animates which fighter, and the peer's connection (hidden without a session)
func _co_status() -> void:
	var t := ""
	if co != null:
		var peer := "fighter %d" % (co.peer_own + 1) if co.peer_own >= 0 else "fighter ?"
		var link := ""
		match co.state:
			"connected":
				link = "connected (%s)" % _co_where
			"listening":
				link = "waiting for a guest at %s" % _co_where
			"connecting", "handshaking":
				link = "connecting to %s" % _co_where
			_:
				link = "not connected: %s" % co.note if co.note != "" else "not connected"
		t = "CO-EDIT   you animate fighter %d   |   %s is the other animator's (read only)   |   peer: %s" % [co.own + 1, peer, link]
	if t != _co_line_text and ui_co_line != null:
		_co_line_text = t
		ui_co_line.text = t
		ui_co_line.visible = t != ""

## the peer's cards or playhead arrived: that fighter is drawn again
func _co_applied(f: int, what: String) -> void:
	_actors_sync()
	if co == null or f < 0 or f >= actors_rt.size() or f == actor_on:
		return
	if what == "t":
		actors_rt[f]["pt"] = co.peer_t
	else:
		actors_rt[f]["t"] = -INF   # its cards changed: it is posed again
	_pose_others()
	_refresh()


## once a frame: the socket, the states said once, the owned fighter's playhead to the peer
func _co_tick() -> void:
	if co == null:
		return
	_co_fighters()
	co.poll()
	if co.state != _co_seen:
		_co_seen = co.state
		_say_plain("live co-edit: %s%s" % [co.state, (" (" + co.note + ")") if co.note != "" else ""])
	if co.connected():
		co.set_t(playhead)
	_co_status()


func _co_sync() -> void:
	if co == null or not co.connected():
		return
	_co_fighters()
	co.sync_owned()


func _pose_others() -> void:
	if actors_rt.is_empty() and S.actors.is_empty():
		return
	_actors_sync()
	for k in actors_rt.size():
		var a: Dictionary = actors_rt[k]
		var at: float = a.get("pt", playhead)   # ROADMAP 30: a co-edit peer's own playhead, else the shared one
		if k == actor_on or a["t"] == at:
			continue
		(a["S"] as Scene).apply(a["B"], at)
		a["t"] = at


## made active, shown: the cards row is that actor's scene
func _actor_go(k: int) -> void:
	if _actor_set(k):
		ov.mark_dirty()
		wt.mark_dirty()
		_rebuild_cards()
	_refresh()


## Actor: add a second fighter: a mirrored copy of this scene (Scene.mirror_file), 1.5 m in front, turned to face this
## one. One undo step
func _actor_add() -> void:
	_actors_sync()
	if actors_rt.size() >= 2:
		_say("there are two fighters already (the most for now): use 'Actor: switch to the next fighter' to pose the other one, or 'Actor: remove this fighter' on it first")
		return
	if S.cards.is_empty():
		_say("the second fighter is a mirrored copy of this scene: press Enter to add the body as a card first, or open a scene in the list below")
		return
	_push_undo()
	var keep := B.state()   # lossless: to_dict poses the body it is given
	var d := S.to_dict(B)
	B.set_state(keep)
	d.erase("actors")
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S2 := Scene.new()
	S2.from_dict(Scene.mirror_file(d, M))
	S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.5], "yaw": 180.0}, "scene": S2})
	_actors_build(B, S)
	_refresh()
	_say("a second fighter: '%s' (this scene mirrored), 150 cm in front, facing this one.  'Actor: switch to the next fighter' poses it; Save scene keeps both" % S2.name)


## Actor: switch to the next fighter (not an undo step: which actor is active is a view, like the picked part)
func _actor_next() -> void:
	_actors_sync()
	if actors_rt.size() < 2:
		_say("there is one fighter: use 'Actor: add a second fighter' to make another")
		return
	_actor_go((actor_on + 1) % actors_rt.size())
	_say("fighter %d of %d (%s): edits, cards and Ctrl+Z are this one's now" % [actor_on + 1, actors_rt.size(), "the hero" if actor_on == 0 else actors_rt[actor_on]["name"]])


## Actor: remove this fighter (not the hero: the hero is the scene file itself). One undo step
func _actor_remove() -> void:
	_actors_sync()
	if actors_rt.size() < 2:
		_say("there is one fighter, the scene itself: use 'Actor: add a second fighter' to make another")
		return
	if actor_on == 0:
		_say("the hero is the scene itself and stays: use 'Actor: switch to the next fighter', then remove that one")
		return
	_push_undo()
	var k := actor_on
	var nm: String = actors_rt[k]["name"]
	var H: Scene = actors_rt[0]["S"]
	_actor_set(0)
	H.actors.remove_at(k - 1)
	_actors_build(B, H)
	ov.mark_dirty()
	wt.mark_dirty()
	_rebuild_cards()
	_refresh()
	_say("removed %s; the hero is active (Ctrl+Z brings it back)" % nm)


## actor k placed (pos [x, z] metres, yaw degrees, in the hero's space): its file xf and its runtime transform
func actor_place(k: int, pos: Vector2, yaw: float) -> void:
	_actors_sync()
	if k < 1 or k >= actors_rt.size():
		return
	var H: Scene = actors_rt[0]["S"]
	H.actors[k - 1]["xf"] = {"pos": [pos.x, pos.y], "yaw": yaw}
	actors_rt[k]["xf"] = actor_xf(H.actors[k - 1]["xf"])
	_dummy_hits()   # TC5: the fighters' report is measured again


## CROSS CONTACT (TC2, wired for TC5): the hero's body against actor k's, at its placement (Body.cross_contacts rows)
func actor_contacts(k: int) -> Array:
	_actors_sync()
	if k < 1 or k >= actors_rt.size():
		return []
	return (actors_rt[0]["B"] as Body).cross_contacts(actors_rt[k]["B"], actors_rt[k]["xf"])


## the stage's transform: the inverse of the active actor's placement (the identity for the hero and with one actor)
func _stage_xf() -> Transform3D:
	if actor_on > 0 and actor_on < actors_rt.size():
		return (actors_rt[actor_on]["xf"] as Transform3D).affine_inverse()
	return Transform3D.IDENTITY


## the stage put under the active actor; the camera moved by the same rigid step (a turn about Y and a shift: the
## actors' placements are only that), so every point of the world stays where it was on screen
func _stage_sync() -> void:
	if stage_root == null:
		return
	var want := _stage_xf()
	var had := stage_root.transform
	if want == had:
		return
	stage_root.transform = want
	var D := want * had.affine_inverse()
	if _view_tw != null and _view_tw.is_valid():
		_view_tw.kill()
	target = D * target
	yaw = wrapf(yaw + rad_to_deg(atan2(D.basis.z.x, D.basis.z.z)), -180.0, 180.0)
	_cam()


## start of every refresh: the actor list in step, the dummy away with 2+ fighters (back with one), the stage placed.
## One actor: returns at once
func _actors_view() -> void:
	if actors_rt.is_empty() and S.actors.is_empty() and actor_men.is_empty() and not _dummy_auto:
		return
	_actors_sync()
	var many := actors_rt.size() >= 2
	if many != _dummy_auto:
		_dummy_auto = many
		if many:
			_dummy_keep = dummy_on
			dummy_on = false
		else:
			dummy_on = _dummy_keep
		_dummy_hits()
	_stage_sync()


## end of every refresh: each fighter that is not active drawn as a mannequin at its placement, posed from its body
## (posed by _pose_others), with its weapon. One actor: nothing exists and nothing is done
func _actors_draw() -> void:
	if actors_rt.is_empty() and actor_men.is_empty():
		return
	_stage_sync()
	while actor_men.size() > actors_rt.size():
		(actor_men.pop_back()["node"] as Node).queue_free()
	while actor_men.size() < actors_rt.size():
		actor_men.append(_actor_man())
	for k in actor_men.size():
		var mq: Dictionary = actor_men[k]
		var n: Node3D = mq["node"]
		n.visible = k != actor_on
		if k == actor_on:
			continue
		var b: Body = actors_rt[k]["B"]
		n.transform = actors_rt[k]["xf"]
		Overlays.pose_skeleton(mq["skel"], mq["idx"], b)
		var tag: Label3D = mq["tag"]
		tag.text = String(actors_rt[k]["name"])
		tag.position = b.P["head"] + Vector3(0, 0.28, 0)
		var w: Array = mq["wep"]
		for mi in w:
			(mi as MeshInstance3D).visible = b.wep_on
		if b.wep_on:
			_place(w[0], b.wep_point(0.0), b.wep_point(b.wep_handle), 0.0, false)
			_place(w[1], b.wep_point(b.wep_handle), b.wep_point(b.wep_len), 0.0, false)
		_fh_draw(k, b)   # the off-hand weapon and the fighter-hover light (own functions, below _actor_man)


## one other fighter's mannequin (made as the dummy's is: Overlays.mannequin) and its weapon, under the stage
func _actor_man() -> Dictionary:
	var root := Node3D.new()
	root.name = "fighter_%d" % actor_men.size()
	stage_root.add_child(root)
	var skin := StandardMaterial3D.new()
	# a colour of its own per fighter (Maya / Blender give each character a wire colour): blue, green, red, violet;
	# the active one keeps the plain skin, so which one you pose is plain at a glance
	skin.albedo_color = ACTOR_TINTS[actor_men.size() % ACTOR_TINTS.size()]
	skin.roughness = 0.6
	var mq := Overlays.mannequin(root, skin)
	var tag := Label3D.new()   # the fighter's name over its head (click the body to pose it)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 22
	tag.outline_size = 6
	tag.modulate = skin.albedo_color.lightened(0.35)
	root.add_child(tag)
	var w := []
	for r in [[B.wep_r_handle, B.wep_r_handle, "tape"], [B.wep_r_barrel, B.wep_r_handle, "metal"]]:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = r[0]
		c.bottom_radius = r[1]
		mi.mesh = c
		mi.material_override = wep_mats[r[2]]
		root.add_child(mi)
		w.append(mi)
	var fp := SkinPick.new()   # PRECISE PICK on this fighter too: its click and its hover light are on its own skin
	fp.build((mq[0] as Node).find_children("*", "MeshInstance3D", true, false), mq[1])
	var mdict := {"node": root, "skel": mq[1], "idx": mq[2], "wep": w, "tag": tag, "skp": fp}
	mdict.merge(_fh_meshes(root))
	return mdict


## FIGHTER HOVER AND THE OFF-HAND WEAPON OF A FIGHTER THAT IS NOT ACTIVE: the same two cylinders as the active body's
## (d2_handle, d2_blade: the dagger's look), under the fighter's node, so the node's visibility covers them. The hovered
## part's light is on the fighter's own skin (its SkinPick, _fh_draw), as the active body's is
func _fh_meshes(root: Node3D) -> Dictionary:
	var tape: Material = wep_mats["tape"]
	var steel: Material = wep_mats["steel"]
	var w2 := []
	for r in [[0.013, 0.013, tape], [0.004, 0.011, steel]]:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = r[0]
		c.bottom_radius = r[1]
		mi.mesh = c
		mi.material_override = r[2]
		root.add_child(mi)
		w2.append(mi)
	return {"wep2": w2}


## one fighter that is not active, this refresh: its off-hand weapon where its body holds it, and the hovered part's light
## (only when the mouse is on that fighter: hover_fighter)
func _fh_draw(k: int, b: Body) -> void:
	var mq: Dictionary = actor_men[k]
	var w2: Array = mq["wep2"]
	for mi in w2:
		(mi as MeshInstance3D).visible = b.wep2_on
	if b.wep2_on:
		var hu := float(Body.KINDS[b.wep2_kind]["handle"])
		_place(w2[0], b.wep2_point(0.0), b.wep2_point(hu), 0.0, false)
		_place(w2[1], b.wep2_point(hu), b.wep2_point(b.wep2_len()), 0.0, false)
	var j := hover_fpart if k == hover_fighter else ""
	(mq["skp"] as SkinPick).set_looks({j: _look_of("hover")} if j != "" and b.P.has(j) and not clean else {})


## a click on a fighter that is not active (TC4): [k, part, t along the ray] of the nearest part hit; [-1, "", INF] none.
## The ray is taken into that fighter's body space (stage * its placement); the test is _pick's
func _pick_actor(mp: Vector2) -> Array:
	var best := [-1, "", INF]
	if actors_rt.size() < 2 or stage_root == null:
		return best
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	for k in mini(actors_rt.size(), actor_men.size()):
		if k == actor_on:
			continue
		var hit: Array = (actor_men[k]["skp"] as SkinPick).pick(o, d)   # its skin as drawn (PRECISE PICK)
		if String(hit[0]) != "" and float(hit[1]) < float(best[2]):
			best = [k, String(hit[0]), float(hit[1])]
	return best


## the file the open scene saves as: the hero's scene with every other actor in "actors" (TC1), whoever is active.
## The hero's body is kept and put back (to_dict poses it)
func _scene_dict(frames := true) -> Dictionary:
	_actors_sync()
	var H := _hero_scene()
	var hb := _hero_body()
	var keep := hb.state()
	var d := H.to_dict(hb, frames)
	hb.set_state(keep)
	return d


## KEY ONE PART (round 41, WW1, UPGRADES #239): K keys the picked part's 3 angles at the playhead as a PART KEY
## (scripts/part_keys.gd); keying the same time again replaces it. One undo step
func _key_part() -> void:
	if PartSets.of(self).key_active():   # an active KEYING SET: K keys all its parts (part_sets.gd); none: the one part, below
		return
	if not sel in Body.BODY or S.cards.is_empty():
		_say("K keys a BODY part at the playhead: open a scene with cards and click a part first")
		return
	var t := clampf(playhead, 0.0, S.length())
	_do(func(): PartKeys.put(S.part_keys, sel, t, B.ang[sel]))
	_say("keyed %s at %s  (%d key%s on it; Ctrl+Z takes it back)" % [sel, Units.time(t, S.fps), S.part_keys[sel].size(), "" if S.part_keys[sel].size() == 1 else "s"])


## IK / FK WITH POLE TARGETS (GAP_ANALYSIS row 13; scripts/limb_ik.gd). The picked part names the limb (an arm part or a
## finger: that hand; a leg part: that foot). Each command is one undo step
func _ik_tip() -> String:
	return LimbIK.limb_of(sel)


func _ik_words(tip: String) -> String:
	return ("left " if tip.ends_with("_l") else "right ") + ("hand" if tip.begins_with("hand") else "foot")


func _ik_pin() -> void:
	var tip := _ik_tip()
	if tip == "":
		_say("IK pins a hand or a foot: click a hand, a foot, or a part of that arm or leg first")
		return
	if S.cards.is_empty():
		_say("IK keys live in a scene: open a scene, or press Enter to add the body as a card, then pin")
		return
	var t := clampf(playhead, 0.0, S.length())
	var r := {}
	_do(func(): r.merge(LimbIK.pin(S, B, tip, t)))
	_dummy_hits()
	var p: Vector3 = r["target"]
	_say("pinned the %s at %s, at (%s, %s, %s): it stays there whatever the body does, its %s toward the pole (Ctrl+Z takes it back)" % [_ik_words(tip), Units.time(t, S.fps), Units.len(p.x), Units.len(p.y), Units.len(p.z), "elbow" if tip.begins_with("hand") else "knee"])


## SPACE SWITCHING (ROADMAP 63): the picked hand / foot's target lives in the world, the chest, the pelvis, the held
## weapon or the other hand from the playhead on; its tip stays where it is at this frame (one undo step)
## ROADMAP 88: contact mode on / off (no body change: no undo step). Read by _drag_joint for the hands.
func _ik_contact_toggle() -> void:
	ik_contact = not ik_contact
	_say("CONTACT ON: a hand you drag slides along the nearest wall or table in the set, palm on it" if ik_contact else "CONTACT OFF: a hand you drag pulls through everything, as before")


func _ik_space(space: String) -> void:
	var tip := _ik_tip()
	if space == "other":
		if not tip.begins_with("hand"):
			_say("only a hand follows the other hand: click a hand (or a part of that arm) first")
			return
		space = Body.twin(tip)
	if tip == "":
		_say("a space belongs to a hand or a foot: click a hand, a foot, or a part of that arm or leg first")
		return
	if S.cards.is_empty():
		_say("IK keys live in a scene: open a scene, or press Enter to add the body as a card, then switch its space")
		return
	var t := clampf(playhead, 0.0, S.length())
	var r := {}
	_do(func(): r.merge(LimbIK.switch_space(S, B, tip, t, space)))
	if not r.get("ok", false):
		_drop_undo()
		match String(r.get("why", "")):
			"no_weapon":
				_say("there is no weapon at %.2f s to be a space: pick a weapon first, or choose chest / pelvis / world" % t)
			"loop":
				_say("that space would follow this %s round in a circle: pick another space, or switch the other limb to the world first" % _ik_words(tip))
			"self":
				_say("a limb cannot be in its own space: pick the chest, the pelvis, the weapon or the other hand")
			_:
				_say("that is not a space: choose world, chest, pelvis, weapon or the other hand")
		return
	_dummy_hits()
	if String(r["why"]) == "same":
		_drop_undo()
		_say("the %s is already in %s space at %.2f s: nothing to switch; pick another space to move it" % [_ik_words(tip), space, t])
		return
	_say("the %s is in %s space from %.2f s (was %s%s): it moved %.2f mm at this frame, and follows %s from here (Ctrl+Z takes it back)" % [_ik_words(tip), space, t, r["from"], ", pinned first" if r["pinned"] else "", float(r["moved"]) * 1000.0, "nothing: it stays in the world" if space == "world" else "the " + space.replace("_l", " (left)").replace("_r", " (right)")])


func _ik_release() -> void:
	var tip := _ik_tip()
	if tip == "":
		_say("release lets a pinned hand or foot go: click that hand or foot (or a part of its limb) first")
		return
	var ks: Array = S.ik.get(tip, [])
	var t := clampf(playhead, 0.0, S.length())
	if ks.is_empty() or LimbIK.weight_at(ks, t) <= 0.0:
		_say("the %s is not pinned here: use 'IK: pin the picked hand/foot here' first, or move the playhead to where it is pinned" % _ik_words(tip))
		return
	if LimbIK.card_at(S, t) < 0:
		_say("release writes the pose into a card: click a card (the playhead goes onto it), or press Enter to add one here, then release")
		return
	var r := {}
	_do(func(): r.merge(LimbIK.release(S, B, tip, t)))
	_dummy_hits()
	_say("released the %s at %s: card %d now holds its pinned pose (off by %.2f° at most), so it follows the cards from here without a jump" % [_ik_words(tip), Units.time(t, S.fps), int(r["card"]) + 1, float(r["residual"])])


func _ik_to_fk() -> void:
	var tip := _ik_tip()
	if tip == "":
		_say("IK -> FK matches a hand or foot: click a hand, a foot, or a part of that arm or leg first")
		return
	var ks: Array = S.ik.get(tip, [])
	var t := clampf(playhead, 0.0, S.length())
	if ks.is_empty() or LimbIK.weight_at(ks, t) <= 0.0:
		_say("the %s is already FK here: use 'FK -> IK: match at this frame' to put it in IK, or move the playhead to where it is in IK" % _ik_words(tip))
		return
	if LimbIK.card_at(S, t) < 0:
		_say("IK -> FK writes the pose into a card: click a card (the playhead goes onto it), or press Enter to add one here")
		return
	var r := {}
	_do(func(): r.merge(LimbIK.to_fk(S, B, tip, t)))
	_dummy_hits()
	_say("the %s is FK from %.2f s: card %d holds its IK pose (off by %.2f deg at most), the blend keyed 0, nothing jumps (Ctrl+Z takes it back)" % [_ik_words(tip), t, int(r["card"]) + 1, float(r["residual"])])


func _ik_to_ik() -> void:
	var tip := _ik_tip()
	if tip == "":
		_say("FK -> IK matches a hand or foot: click a hand, a foot, or a part of that arm or leg first")
		return
	if S.cards.is_empty():
		_say("IK keys live in a scene: open a scene, or press Enter to add the body as a card first")
		return
	var t := clampf(playhead, 0.0, S.length())
	_do(func(): LimbIK.to_ik(S, B, tip, t))
	_dummy_hits()
	_say("the %s is IK from %.2f s: target and pole keyed where the FK limb is, the blend keyed 1, nothing jumps (Ctrl+Z takes it back)" % [_ik_words(tip), t])


func _ik_snap_fk() -> void:
	var tip := _ik_tip()
	if tip == "" or not S.ik.has(tip):
		_say("snap FK to IK needs a limb with IK keys: click a pinned hand or foot, or use 'IK: pin the picked hand/foot here' first")
		return
	var t := clampf(playhead, 0.0, S.length())
	if LimbIK.card_at(S, t) < 0:
		_say("snap FK to IK writes into a card: click a card (the playhead goes onto it), or press Enter to add one here")
		return
	var r := {}
	_do(func(): r.merge(LimbIK.snap_fk(S, B, tip, t)))
	_dummy_hits()
	_say("card %d took the %s's IK pose (off by %.2f° at most); its IK keys stay" % [int(r["card"]) + 1, _ik_words(tip), float(r["residual"])])


func _ik_snap_ik() -> void:
	var tip := _ik_tip()
	if tip == "":
		_say("snap IK to FK keys a hand or foot's IK target: click a hand, a foot, or a part of that arm or leg first")
		return
	if S.cards.is_empty():
		_say("IK keys live in a scene: open a scene, or press Enter to add the body as a card first")
		return
	var t := clampf(playhead, 0.0, S.length())
	var r := {}
	_do(func(): r.merge(LimbIK.snap_ik(S, B, tip, t)))
	_dummy_hits()
	_say("the %s's IK target and pole keyed at %s where the cards put it (IK weight there %.2f)" % [_ik_words(tip), Units.time(t, S.fps), float(r["w"])])


## FOOT PLANTS over a time range (ROADMAP 8; scripts/foot_plant.gd). The picked foot's sole holds where it is at the start
## of the range. "to the next card": from the playhead to the next card's arrival. "over the selected range": the picked
## cards (first arrival to the last one's hold end). One undo step each; a leg that cannot reach is said, with its frames
func _foot_tip_or_say(what: String) -> String:
	var tip := _ik_tip()
	if not tip.begins_with("foot"):
		_say("%s holds a foot: click a foot (or a part of that leg) first" % what)
		return ""
	return tip


func _foot_plant_at(tip: String, t0: float, t1: float) -> void:
	if S.cards.size() < 2:
		_say("a foot plant needs a card after the first: add the body as a card, then plant")
		return
	if t1 - t0 < 1.0 / float(maxi(S.fps, 1)):
		_say("nothing to plant: that range has no time in it. Drag a range on the timeline first")
		return
	var p := {"foot": tip, "t0": t0, "t1": t1}
	var rep := {}
	_do(func():
		S.plants = FootPlant.add(S.plants, p)
		rep.merge(FootPlant.scan(S, B, p))   # the range, frame by frame: the misses are reported, never hidden
		S.apply(B, clampf(playhead, 0.0, S.length())))
	_dummy_hits()
	var who := _ik_words(tip)
	if (rep["bad"] as Array).is_empty():
		_say("the %s is planted %.2f-%.2f s: its sole holds on every frame (worst %.2f mm, turn %.2f°; Ctrl+Z takes it back)" % [who, t0, t1, float(rep["worst"]) * 1000.0, float(rep["turn_worst"])])
	else:
		var bad: Array = rep["bad"]
		_say("the %s is planted %.2f-%.2f s, but its leg cannot reach the planted place on %d of %d frames (%.2f-%.2f s, worst %.0f mm): the foot slides there" % [who, t0, t1, bad.size(), int(rep["frames"]), float(bad[0][0]), float(bad[-1][0]), float(rep["worst"]) * 1000.0])


func _foot_plant_next() -> void:
	var tip := _foot_tip_or_say("a foot plant")
	if tip == "":
		return
	var t := clampf(playhead, 0.0, S.length())
	var t1 := -1.0
	for r in S.times():
		if float(r[1]) > t + 1e-4:
			t1 = float(r[1])
			break
	if t1 < 0.0:
		_say("no card after the playhead: the plant runs to the next card, so put the playhead before one, or use 'Foot: plant the picked foot over the selected range'")
		return
	_foot_plant_at(tip, t, t1)


func _foot_plant_range() -> void:
	var tip := _foot_tip_or_say("a foot plant")
	if tip == "":
		return
	var rg := card_range()
	if rg.is_empty():
		_say("pick the cards the foot is planted over (Shift+click a second card for a range)")
		return
	var ts := S.times()
	_foot_plant_at(tip, float(ts[rg[0]][1]), float(ts[rg[-1]][2]))


func _foot_unplant() -> void:
	var tip := _foot_tip_or_say("unplant")
	if tip == "":
		return
	var t := clampf(playhead, 0.0, S.length())
	if FootPlant.remove_at(S.plants, tip, t).size() == S.plants.size():
		_say("no plant of the %s covers %s: move the playhead into its planted range" % [_ik_words(tip), Units.time(t, S.fps)])
		return
	_do(func():
		S.plants = FootPlant.remove_at(S.plants, tip, t)
		S.apply(B, t))
	_dummy_hits()
	_say("the %s is free at %s: it follows the cards again (Ctrl+Z takes the plant back)" % [_ik_words(tip), Units.time(t, S.fps)])


var _fp_line: MeshInstance3D   # the footprints under the planted feet (ROADMAP 8)


func _foot_plant_draw() -> void:
	if _fp_line == null:
		_fp_line = MeshInstance3D.new()
		_fp_line.name = "foot_plants"
		_fp_line.mesh = ImmediateMesh.new()
		add_child(_fp_line)
	var im := _fp_line.mesh as ImmediateMesh
	im.clear_surfaces()
	if clean or S == null or S.plants.is_empty():
		return
	var t := clampf(playhead, 0.0, S.length())
	for f in FootPlant.footprint(B, S.plants, t, S.fps):
		var pts: Array = f["pts"]
		im.surface_begin(Mesh.PRIMITIVE_LINES, Overlays._mat())
		im.surface_set_color(Color(side_col(String(f["foot"])), 0.35 + 0.65 * float(f["w"])))
		for k in pts.size():   # heel -> ball -> toe tip -> heel: a small footprint on the floor
			im.surface_add_vertex(pts[k])
			im.surface_add_vertex(pts[(k + 1) % pts.size()])
		im.surface_end()


## IN-VIEW IK HANDLES (round 50, GATES IK2; docs/research/BLENDER_IK.md section g). Each limb pinned at the playhead
## (IK weight > 0) shows a cube at its target and a sphere at its pole, a dashed line from the elbow / knee to the pole
## (Maya's pole vector line, Blender's dashed relationship line). Drawn on top of the body; a press inside one takes it
## (nowhere else: every other click goes to _pick as before). Dragging the target moves it in the view plane (a foot's
## on its floor plane: horizontal through it), dragging the pole swings the elbow / knee; the limb is solved each mouse
## move (LimbIK.solve, mixed by the weight as playback does). Release keys the target / pole at the playhead: one undo step
const IKH_CUBE := 0.06    # m, the target cube's edge
const IKH_BALL := 0.03    # m, the pole sphere's radius
var _ikh_root: Node3D
var _ikh_nodes := {}      # tip -> [cube, sphere]
var _ikh_line: MeshInstance3D
var _ikh_drag := {}       # the drag: {tip, kind "target"/"pole", target, pole, rot?, w, n, p0, off, fk?, moved}


func _ikh_build() -> void:
	_ikh_root = Node3D.new()
	_ikh_root.name = "ik_handles"
	add_child(_ikh_root)
	for tip in LimbIK.LIMBS:
		var col := side_col(tip)
		var mc := StandardMaterial3D.new()
		mc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mc.no_depth_test = true
		mc.render_priority = 3
		mc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mc.albedo_color = Color(col, 0.55)
		var cube := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * IKH_CUBE
		cube.mesh = bm
		cube.material_override = mc
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = IKH_BALL
		sm.height = IKH_BALL * 2.0
		ball.mesh = sm
		ball.material_override = mc
		_ikh_root.add_child(cube)
		_ikh_root.add_child(ball)
		_ikh_nodes[tip] = [cube, ball]
	_ikh_line = MeshInstance3D.new()
	_ikh_line.mesh = ImmediateMesh.new()
	_ikh_root.add_child(_ikh_line)


## the limbs pinned at the playhead (IK weight > 0 there), in LimbIK.LIMBS order
func _ikh_pinned() -> Array:
	var out := []
	if S == null or S.ik.is_empty():
		return out
	var t := clampf(playhead, 0.0, S.length())
	for tip in LimbIK.LIMBS:
		var ks: Array = S.ik.get(tip, [])
		if not ks.is_empty() and LimbIK.weight_at(ks, t) > 0.0:
			out.append(tip)
	return out


## the limb's target and pole as drawn: the drag's live points, or its keys sampled at the playhead
func _ikh_at(tip: String) -> Dictionary:
	if not _ikh_drag.is_empty() and _ikh_drag["tip"] == tip:
		return _ikh_drag
	return LimbIK.sample(S.ik[tip], clampf(playhead, 0.0, S.length()), LimbIK.frames(B))   # ROADMAP 63: a limb in a space is drawn in the world


func _ikh_draw() -> void:
	if _ikh_root == null:
		_ikh_build()
	var on := [] if clean else _ikh_pinned()
	var im := _ikh_line.mesh as ImmediateMesh
	im.clear_surfaces()
	for tip in LimbIK.LIMBS:
		var nd: Array = _ikh_nodes[tip]
		var vis: bool = tip in on
		(nd[0] as Node3D).visible = vis
		(nd[1] as Node3D).visible = vis
		if not vis:
			continue
		var k := _ikh_at(tip)
		(nd[0] as Node3D).position = k["target"]
		(nd[1] as Node3D).position = k["pole"]
		var a: Vector3 = B.P[B.parent[tip]]   # the elbow / knee
		var b: Vector3 = k["pole"]
		var n := maxi(2, int(ceil(a.distance_to(b) / 0.025)))
		im.surface_begin(Mesh.PRIMITIVE_LINES, Overlays._mat())
		im.surface_set_color(side_col(tip))
		for s in range(0, n, 2):   # dashed: 2.5 cm on, 2.5 cm off
			im.surface_add_vertex(a.lerp(b, float(s) / n))
			im.surface_add_vertex(a.lerp(b, minf(1.0, float(s + 1) / n)))
		im.surface_end()


## the handle under the mouse: [tip, "target" / "pole"] or [] (inside its drawn footprint: the cube's half edge, the
## sphere's radius, at its depth; the nearest to the eye wins)
func _ikh_hit(mp: Vector2) -> Array:
	var best := []
	var best_d := INF
	var vh := get_viewport().get_visible_rect().size.y
	var fwd := -cam.global_basis.z
	for tip in ([] if clean else _ikh_pinned()):
		var k := _ikh_at(tip)
		for kind in ["target", "pole"]:
			var p: Vector3 = k[kind]
			var depth := (p - cam.global_position).dot(fwd)
			if depth <= cam.near:
				continue
			var r_px := (IKH_CUBE * 0.5 if kind == "target" else IKH_BALL) / (depth * tan(deg_to_rad(cam.fov * 0.5))) * vh * 0.5
			if cam.unproject_position(p).distance_to(mp) <= r_px and depth < best_d:
				best_d = depth
				best = [tip, kind]
	return best


## a press on a handle starts its drag (one undo step pushed now, dropped again if the mouse never moves); false = no handle
func _ikh_press(mp: Vector2) -> bool:
	var h := _ikh_hit(mp)
	if h.is_empty():
		return false
	var tip: String = h[0]
	var kind: String = h[1]
	var t := clampf(playhead, 0.0, S.length())
	var fr := LimbIK.frames(B)
	var k := LimbIK.sample(S.ik[tip], t, fr)
	_step_hint = "Move the IK %s" % kind
	_push_undo()
	var d := {"tip": tip, "kind": kind, "target": k["target"], "pole": k["pole"], "w": k["w"], "moved": false, "space": k.get("space", "world"), "fr": fr}
	if k.has("rot"):
		d["rot"] = k["rot"]
	var p0: Vector3 = k[kind]
	var o := cam.project_ray_origin(mp)
	var rd := cam.project_ray_normal(mp)
	var n := cam.global_basis.z   # the view plane through the handle
	if kind == "target" and tip.begins_with("foot") and absf(rd.y) > 0.05:
		n = Vector3.UP   # a foot's target slides on its floor plane (horizontal through it)
	d["n"] = n
	d["p0"] = p0
	var hit = _ikh_plane(o, rd, p0, n)
	d["off"] = (p0 - hit) if hit != null else Vector3.ZERO
	if float(k["w"]) < 1.0:   # the limb's FK at t, to mix with as playback does (LimbIK.play)
		var F := Body.new()
		F.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		LimbIK._fk_at(S, F, tip, t)
		d["fk"] = {}
		for j in LimbIK.chain(B, tip):
			d["fk"][j] = F.ang[j]
	_ikh_drag = d
	sel = tip
	playing = false
	dragging = "ik_handle"
	_refresh()
	_say("IK %s of the %s: drag it; the %s follows. Release keys it at %s" % [kind, _ik_words(tip), "hand" if tip.begins_with("hand") else "foot", Units.time(t, S.fps)])
	return true


static func _ikh_plane(o: Vector3, d: Vector3, p0: Vector3, n: Vector3) -> Variant:
	var den := d.dot(n)
	if absf(den) < 1e-6:
		return null
	var s := (p0 - o).dot(n) / den
	return null if s < 0.0 else o + d * s


func _ikh_move(mp: Vector2) -> void:
	if _ikh_drag.is_empty():
		return
	var hit = _ikh_plane(cam.project_ray_origin(mp), cam.project_ray_normal(mp), _ikh_drag["p0"], _ikh_drag["n"])
	if hit == null:
		return
	_ikh_drag[_ikh_drag["kind"]] = (hit as Vector3) + (_ikh_drag["off"] as Vector3)
	_ikh_drag["moved"] = true
	var r := _ikh_pose()
	_refresh()
	var tip: String = _ikh_drag["tip"]
	_say("MOVING the IK %s of the %s%s" % [_ikh_drag["kind"], _ik_words(tip),
		("     out of reach by %.1f cm" % (float(r["miss"]) * 100.0)) if float(r["miss"]) > 0.002 else ""])


## the dragged limb solved onto the live target / pole (and mixed by the weight). IK3: the pin wins over the grip; the
## weapon hand moved, the other hand follows the weapon unless it is pinned itself (as Scene.apply)
func _ikh_pose() -> Dictionary:
	var tip: String = _ikh_drag["tip"]
	var r := LimbIK.solve(B, tip, _ikh_drag["target"], _ikh_drag["pole"], _ikh_drag.get("rot", null))
	if _ikh_drag.has("fk"):
		var w: float = _ikh_drag["w"]
		for j in _ikh_drag["fk"]:
			B.ang[j] = (_ikh_drag["fk"][j] as Vector3).lerp(B.ang[j], w)
		B.fk()
		r["miss"] = ((B.P[tip] as Vector3) - (_ikh_drag["target"] as Vector3)).length()
	var other := "hand_l" if B.wep_hand == "hand_r" else "hand_r"
	if B.wep_on and B.grip and B.wep_hand == tip and not other in _ikh_pinned():
		B.apply_grip()
	return r


## release: the dragged point keyed at the playhead (weight and hand turn as they were there); no move = no undo step
## ROADMAP 23: the next left drag on the view is one line-of-action stroke (scripts/line_of_action.gd)
func _loa_arm() -> void:
	loa.armed = true
	loa.on = true
	_refresh()
	_say("LINE OF ACTION: drag one stroke on the view, from the head down to the planted foot. Shift on release mirrors the lean. A right click cancels")


func _loa_release(mirror: bool) -> void:
	var pts := loa.take_stroke()
	if pts.size() < 3:
		_say("line of action: the stroke was a click, not a line. Drag again")
		return
	_loa_apply(pts, mirror)


## one stroke = one undo step (Ctrl+Z puts the pose back as it was before the drag)
func _loa_apply(pts: Array, mirror: bool) -> Dictionary:
	_push_undo()
	var rep: Dictionary = loa.apply(B, cam, pts, mirror)
	if rep.is_empty():
		_say("line of action: the stroke is too short to bend the body. Drag a longer line")
		return rep
	_after_edit()
	_refresh()
	var lim_txt := "" if (rep["limits"] as Array).is_empty() else ", at a limit: " + ", ".join(rep["limits"])
	_say("LINE OF ACTION%s: spine, neck and head within %.1f mm of the stroke; the support knee %.0f mm off%s (press Ctrl+Z to undo)" % [" (mirrored)" if mirror else "", float(rep["worst"]) * 1000.0, float(rep["knee"]) * 1000.0, lim_txt])
	return rep


func _ikh_release() -> void:
	var d := _ikh_drag
	_ikh_drag = {}
	if d.is_empty():
		return
	if not d["moved"]:
		_drop_undo()
		_refresh()
		return
	var t := clampf(playhead, 0.0, S.length())
	var key := {"t": t, "target": d["target"], "pole": d["pole"], "w": d["w"]}
	if d.has("rot"):
		key["rot"] = d["rot"]
	if d.get("space", "world") != "world":   # ROADMAP 63: keyed in the space the limb is in, so the run goes on
		key.merge(LimbIK.to_local(key, d["fr"], d["space"]), true)
		key["space"] = d["space"]
	LimbIK.put(S.ik, d["tip"], key)
	_dummy_hits()
	_refresh()
	var p: Vector3 = d[d["kind"]]
	_say("keyed the %s's IK %s at %s, at (%s, %s, %s) (Ctrl+Z takes it back)" % [_ik_words(d["tip"]), d["kind"], Units.time(t, S.fps), Units.len(p.x), Units.len(p.y), Units.len(p.z)])


## SPLINE IK FOR THE BACK (ROADMAP 61; scripts/spine_ik.gd). With the lower / middle back or the chest picked and the spline
## on at the playhead (spine key weight > 0), the view draws the curve through the three controls and the handles: a cube at
## the HIP (spine_01's joint; dragging it sideways twists the base of the spine), a ball for the MID back and a cube for the
## CHEST (drag in the view plane; the back bends along the curve each mouse move). Release keys the controls at the playhead,
## one undo step, mirrored / saved / undone with the other IK keys.
const SPH_CUBE := 0.07    # m, the hip and chest cubes' edge
const SPH_BALL := 0.04    # m, the mid ball's radius
const SPH_DEG_PX := 0.25  # deg of hip twist per pixel of sideways drag
var _sph_root: Node3D
var _sph_nodes := {}      # "hip" / "mid" / "chest" -> its mesh
var _sph_line: MeshInstance3D
var _sph_drag := {}       # the drag: {kind, target, pole, twist, w, n, p0, off, x0, tw0, fk?, moved}


func _sph_build() -> void:
	_sph_root = Node3D.new()
	_sph_root.name = "spine_handles"
	add_child(_sph_root)
	for kind in ["hip", "mid", "chest"]:
		var mc := StandardMaterial3D.new()
		mc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mc.no_depth_test = true
		mc.render_priority = 3
		mc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mc.albedo_color = Color(Tok.c("focus") if kind == "hip" else SIDE_MID, 0.6)
		var mi := MeshInstance3D.new()
		if kind == "mid":
			var sm := SphereMesh.new()
			sm.radius = SPH_BALL
			sm.height = SPH_BALL * 2.0
			mi.mesh = sm
		else:
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * SPH_CUBE
			mi.mesh = bm
		mi.material_override = mc
		_sph_root.add_child(mi)
		_sph_nodes[kind] = mi
	_sph_line = MeshInstance3D.new()
	_sph_line.mesh = ImmediateMesh.new()
	_sph_root.add_child(_sph_line)


## the spline is shown now: a back part is picked and the spine key's weight at the playhead is above 0
func _sph_active() -> bool:
	if clean or S == null or not SpineIK.is_spine_part(sel) or not S.ik.has(SpineIK.KEY):
		return false
	return LimbIK.weight_at(S.ik[SpineIK.KEY], clampf(playhead, 0.0, S.length())) > 0.0


## the controls as drawn: the drag's live ones, or the keys sampled at the playhead
func _sph_at() -> Dictionary:
	if not _sph_drag.is_empty():
		return _sph_drag
	return SpineIK.sample(S.ik[SpineIK.KEY], clampf(playhead, 0.0, S.length()))


func _sph_points() -> Dictionary:
	var k := _sph_at()
	return {"hip": B.P["spine_01"], "mid": k["pole"], "chest": k["target"]}


func _sph_draw() -> void:
	if _sph_root == null:
		_sph_build()
	var on := _sph_active()
	_sph_root.visible = on
	var im := _sph_line.mesh as ImmediateMesh
	im.clear_surfaces()
	if not on:
		return
	var pts := _sph_points()
	for kind in pts:
		(_sph_nodes[kind] as Node3D).position = pts[kind]
	var curve := SpineIK.polyline(pts["hip"], pts["mid"], pts["chest"], 2.0, 40)
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, Overlays._mat())
	im.surface_set_color(Tok.c("info"))
	for p in curve:
		im.surface_add_vertex(p)
	im.surface_end()
	# a tick across the curve at each vertebral joint (where the bones meet it), square to the view
	im.surface_begin(Mesh.PRIMITIVE_LINES, Overlays._mat())
	im.surface_set_color(Tok.c("info"))
	var right := cam.global_basis.x * 0.02
	for j in SpineIK.JOINTS + [SpineIK.END]:
		var q: Vector3 = B.P[j]
		im.surface_add_vertex(q - right)
		im.surface_add_vertex(q + right)
	im.surface_end()


## the handle under the mouse: "hip" / "mid" / "chest" or "" (inside its drawn footprint at its depth; the nearest wins)
func _sph_hit(mp: Vector2) -> String:
	if not _sph_active():
		return ""
	var best := ""
	var best_d := INF
	var vh := get_viewport().get_visible_rect().size.y
	var fwd := -cam.global_basis.z
	var pts := _sph_points()
	for kind in pts:
		var p: Vector3 = pts[kind]
		var depth := (p - cam.global_position).dot(fwd)
		if depth <= cam.near:
			continue
		var r_px := (SPH_BALL if kind == "mid" else SPH_CUBE * 0.5) / (depth * tan(deg_to_rad(cam.fov * 0.5))) * vh * 0.5
		if cam.unproject_position(p).distance_to(mp) <= maxf(r_px, 6.0) and depth < best_d:
			best_d = depth
			best = kind
	return best


func _sph_press(mp: Vector2) -> bool:
	var kind := _sph_hit(mp)
	if kind == "":
		return false
	var t := clampf(playhead, 0.0, S.length())
	var k := SpineIK.sample(S.ik[SpineIK.KEY], t)
	_step_hint = "Move the spine spline %s" % kind
	_push_undo()
	var d := {"kind": kind, "target": k["target"], "pole": k["pole"], "twist": k["twist"], "w": k["w"], "moved": false,
		"x0": mp.x, "tw0": k["twist"]}
	var p0: Vector3 = _sph_points()[kind]
	var o := cam.project_ray_origin(mp)
	var rd := cam.project_ray_normal(mp)
	d["n"] = cam.global_basis.z
	d["p0"] = p0
	var hit = _ikh_plane(o, rd, p0, d["n"])
	d["off"] = (p0 - hit) if hit != null else Vector3.ZERO
	if float(k["w"]) < 1.0:   # the back's FK at t, to mix with as playback does
		var F := Body.new()
		F.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		SpineIK._fk_at(S, F, t)
		d["fk"] = SpineIK.angles(F)
	_sph_drag = d
	playing = false
	dragging = "spine_handle"
	_refresh()
	_say("SPINE SPLINE %s: drag it; the back bends along the curve%s. Release keys it at %.2f s" % [kind, " (sideways = twist the base)" if kind == "hip" else "", t])
	return true


func _sph_move(mp: Vector2) -> void:
	if _sph_drag.is_empty():
		return
	var d := _sph_drag
	if d["kind"] == "hip":
		var tw: Vector2 = d["tw0"]
		var dt := (mp.x - float(d["x0"])) * SPH_DEG_PX
		d["twist"] = Vector2(clampf(tw.x + dt, -90.0, 90.0), tw.y)
	else:
		var hit = _ikh_plane(cam.project_ray_origin(mp), cam.project_ray_normal(mp), d["p0"], d["n"])
		if hit == null:
			return
		d["target" if d["kind"] == "chest" else "pole"] = (hit as Vector3) + (d["off"] as Vector3)
	d["moved"] = true
	var r := SpineIK.pose(B, d, d.get("fk", null))
	_refresh()
	var cl: Array = r["clamped"]
	_say("MOVING the spine spline %s%s%s" % [d["kind"], ("     a limit holds the %s" % ", ".join(cl.map(func(j): return nice(j)))) if not cl.is_empty() else "",
		("     the chest is %.1f cm from its handle" % (float(r["miss"]) * 100.0)) if float(r["miss"]) > 0.002 else ""])


func _sph_release() -> void:
	var d := _sph_drag
	_sph_drag = {}
	if d.is_empty():
		return
	if not d["moved"]:
		_drop_undo()
		_refresh()
		return
	var t := clampf(playhead, 0.0, S.length())
	SpineIK.put(S.ik, {"t": t, "target": d["target"], "pole": d["pole"], "w": d["w"], "twist": d["twist"]})
	_dummy_hits()
	_refresh()
	_say("keyed the spine spline's %s at %.2f s (Ctrl+Z takes it back)" % [d["kind"], t])


func _spine_pin() -> void:
	if not SpineIK.is_spine_part(sel):
		_say("spline IK bends the back: click the lower back, middle back or chest first")
		return
	if S.cards.is_empty():
		_say("IK keys live in a scene: open a scene, or press Enter to add the body as a card, then pin")
		return
	var t := clampf(playhead, 0.0, S.length())
	var r := {}
	_do(func(): r.merge(SpineIK.pin(S, B, t)))
	_dummy_hits()
	_say("spline IK on the back at %.2f s: drag the hip, mid-back and chest handles to bend it along the curve (it matches the pose within %.1f mm now; Ctrl+Z takes it back)" % [t, float(r["err"]) * 1000.0])


func _spine_off() -> void:
	if not SpineIK.is_spine_part(sel):
		_say("spline IK bends the back: click the lower back, middle back or chest first, then turn it off")
		return
	var t := clampf(playhead, 0.0, S.length())
	var r := {}
	_do(func(): r.merge(SpineIK.off(S, t)))
	if not r["ok"]:
		_say("the back is not on the spline here: use 'Spine IK: spline the back here' first, or move the playhead to where it is on")
		return
	_say("spline IK off at %.2f s: the back follows the cards again over the last frame (Ctrl+Z takes it back)" % t)


## EDITABLE TRAILS (ROADMAP 69; scripts/trail_edit.gd). A press on a key dot (a card's moment) of a pinned part's trail
## takes it; the dragged part moves at that key, the trail redraws as the mouse moves. One undo step per drag, pushed at
## the press and dropped again when the mouse never moved.
func _trail_press(mp: Vector2) -> bool:
	if clean or S == null or ov.pins.is_empty() or S.cards.size() < 2:
		return false
	var d: Dictionary = trail_edit.hit(cam, S, ov.pins, mp)
	if d.is_empty():
		return false
	_push_undo()
	var msg := trail_edit.begin(S, cam, mp, d)
	if trail_edit.drag.is_empty():
		_drop_undo()
		_say(msg)
		return true
	undo[-1]["name"] = "Drag trail key of " + nice(d["part"])
	_tree.set_name(_tree.cur, undo[-1]["name"])
	sel = d["part"]
	playhead = clampf(float(d["t"]), 0.0, S.length())
	playing = false
	dragging = "trail_key"
	_refresh()
	_say(msg)
	return true


func _trail_move(mp: Vector2) -> void:
	var msg := trail_edit.move(S, cam, mp)
	ov.mark_dirty()   # the trail is rebuilt from the keys as they stand now
	_refresh()
	if msg != "":
		_say(msg)


## the picked body part's trail is shown while T is on, with no Shift+T needed (ROADMAP 69): pinned on pick, unpinned
## when the part or T goes. Shift+T on it makes it a pin (ov.auto_pin cleared)
func _auto_pin_sync() -> void:
	var want := sel if (ov.trail_on and not clean and sel in Body.BODY and (sel == ov.auto_pin or not ov.pins.has(sel))) else ""   # (its own auto pin is in pins: not a reason to drop it, or it flips every frame)
	var cur: String = ov.auto_pin
	if cur != "" and cur != want:
		ov.auto_pin = ""
		if ov.pins.has(cur):
			ov.toggle_pin(cur)
	if want != "" and ov.auto_pin == "":
		ov.toggle_pin(want)
		ov.auto_pin = want


func _trail_release() -> void:
	var moved := trail_edit.end()
	if not moved:
		_drop_undo()
		_refresh()
		return
	_after_edit()
	ov.mark_dirty()
	_refresh()
	_say("%s   (Ctrl+Z takes it back in one step)" % trail_edit.last)


## REVERSE-FOOT HANDLES (ROADMAP item 6; scripts/foot_handles.gd, scripts/foot_roll.gd). A picked foot shows three handles
## (heel, ball, toe tip). A press on one and a drag up rolls the foot about that point; release keys the leg and the toe
## joint at the playhead, one undo step. Not shown while the foot is IK-pinned or planted at the playhead (those hold it).
var _frh_line: MeshInstance3D
var _frh_drag := {}       # the drag: {sd, kind, start, y0, up, moved}


## the side ("_l" / "_r") whose handles show now, or "": a foot is picked, not pinned, not planted at the playhead
func _frh_active() -> String:
	if clean or S == null or not sel in ["foot_l", "foot_r"]:
		return ""
	var t := clampf(playhead, 0.0, S.length())
	if sel in _ikh_pinned():
		return ""
	for p in S.plants:
		if String(p["foot"]) == sel and FootPlant.weight(p, t, S.fps) > 0.0:
			return ""
	return sel.right(2)


func _frh_draw() -> void:
	if _frh_line == null:
		_frh_line = MeshInstance3D.new()
		_frh_line.name = "foot_handles"
		_frh_line.mesh = ImmediateMesh.new()
		add_child(_frh_line)
	var im := _frh_line.mesh as ImmediateMesh
	im.clear_surfaces()
	var sd := String(_frh_drag["sd"]) if not _frh_drag.is_empty() else _frh_active()
	if sd == "":
		return
	FootHandles.draw(im, B, sd, String(_frh_drag["kind"]) if not _frh_drag.is_empty() else "")


## a press on a handle of the picked foot starts its roll (one undo step pushed now, dropped if the mouse never moves)
func _frh_press(mp: Vector2) -> bool:
	var sd := _frh_active()
	if sd == "":
		return false
	var kind := FootHandles.hit(cam, mp, B, sd)
	if kind == "":
		return false
	_step_hint = "Roll the foot on its %s" % kind
	_push_undo()
	_frh_drag = {"sd": sd, "kind": kind, "start": FootHandles.snapshot(B), "y0": mp.y, "up": 0.0, "moved": false}
	sel = "foot" + sd
	playing = false
	dragging = "foot_handle"
	_refresh()
	_say("ROLL the %s foot on its %s: drag up (the foot turns about that point); release keys it at %s" % [nice(sel).to_lower(), kind, Units.time(clampf(playhead, 0.0, S.length()), S.fps)])
	return true


func _frh_move(mp: Vector2) -> void:
	if _frh_drag.is_empty():
		return
	_frh_drag["up"] = float(_frh_drag["y0"]) - mp.y
	_frh_drag["moved"] = true
	var r := FootHandles.drag(B, _frh_drag["sd"], _frh_drag["kind"], _frh_drag["start"], _frh_drag["up"])
	_after_edit()
	_say("ROLLING the foot on its %s by %.1f°%s" % [_frh_drag["kind"], float(r.get("roll", 0.0)),
		"     stopped at %.1f of %.1f deg: the leg cannot turn it further about that point" % [float(r["roll"]), float(r["asked"])] if r.get("stopped", false) else ""])


## release: the leg and the toe joint keyed at the playhead (as K keys a part); no move = no undo step
func _frh_release() -> void:
	var d := _frh_drag
	_frh_drag = {}
	if d.is_empty():
		return
	if not d["moved"]:
		_drop_undo()
		_refresh()
		return
	var t := clampf(playhead, 0.0, S.length())
	for j in FootHandles.keys_of(B, d["sd"]):
		PartKeys.put(S.part_keys, j, t, B.ang[j])
	_refresh()
	_say("keyed the %s foot's roll on its %s at %s (Ctrl+Z takes it back)" % [String(d["sd"]).trim_prefix("_"), d["kind"], Units.time(t, S.fps)])
## USER CONSTRAINTS (round 51, GATES CN; scripts/constraints.gd): Child Of, Track To (look at), Floor, on the scene's
## stack, played after IK. The TARGET is picked first ("Constraint: use the picked part as the target", a view setting,
## not undone), then the owner is the picked part. With no target picked: the other hand (Child Of), the other fighter's
## head or else the weapon (look at). Every edit is one undo step
var cons_target := {}


## CONSTRAINTS ON SCREEN (Blender draws a dashed relationship line from a constrained bone to its target): for each
## constraint on at the playhead, a line from its owner to its target in the owner's side colour, faded by the
## influence; Child Of solid, look-at (Track To) dashed from between the eyes; Floor a cross on the floor under the foot.
## A view only: nothing saved, no undo
var _cons_line: MeshInstance3D


func _cons_draw() -> void:
	if _cons_line == null:
		_cons_line = MeshInstance3D.new()
		_cons_line.name = "constraint_lines"
		_cons_line.mesh = ImmediateMesh.new()
		add_child(_cons_line)
	var im := _cons_line.mesh as ImmediateMesh
	im.clear_surfaces()
	if clean or S == null or S.cons.is_empty():
		return
	var t := clampf(playhead, 0.0, S.length())
	for c in S.cons:
		var w := Constraints.weight(c, t)
		if w <= 0.0 or c.get("mute", false):
			continue
		var owner := String(c["owner"])
		var col := Color(side_col(owner) if owner.ends_with("_l") or owner.ends_with("_r") else Color(1.0, 0.85, 0.3), 0.35 + 0.65 * w)
		var ty := String(c["type"])
		var a: Vector3 = LookAt.eye_point(B) if ty == "track_to" else B.P[owner]
		im.surface_begin(Mesh.PRIMITIVE_LINES, Overlays._mat())
		im.surface_set_color(col)
		if ty == "floor":
			var y := float(c.get("height", 0.0))
			var f := Vector3(a.x, y, a.z)
			for d in [Vector3(0.06, 0, 0), Vector3(0, 0, 0.06)]:
				im.surface_add_vertex(f - d)
				im.surface_add_vertex(f + d)
			im.surface_add_vertex(a)
			im.surface_add_vertex(f)
		else:
			var x = Constraints.target_xf(S, B, c.get("target", {}), t)
			if x == null:
				im.surface_end()
				continue
			var b: Vector3 = (x as Transform3D).origin
			var n := 1 if ty == "child_of" else maxi(2, int(ceil(a.distance_to(b) / 0.03)))
			for k in range(0, n, 1 if n == 1 else 2):   # look-at dashed: 3 cm on, 3 cm off
				im.surface_add_vertex(a.lerp(b, float(k) / n))
				im.surface_add_vertex(a.lerp(b, minf(1.0, float(k + 1) / n)))
		im.surface_end()


func _cons_words(owner: String) -> String:
	if owner == "pelvis":
		return "hips"
	if owner == "head":
		return "head"
	return _ik_words(owner)


func _cons_tg_words(tg: Dictionary) -> String:
	match String(tg.get("kind", "")):
		"part":
			return nice(String(tg["part"]))
		"weapon":
			return "the weapon"
		"actor":
			return "fighter %d's %s" % [int(tg["actor"]) + 1, nice(String(tg.get("part", "head")))]
		"point":
			return "a spot in the world"
		"prop":
			return "prop %d" % (int(tg["prop"]) + 1)
	return "?"


## the picked part's owner for an existing constraint (fade / release / remove): its limb's hand / foot, the hips, the head
func _cons_owner_picked() -> String:
	for ty in ["child_of", "track_to"]:
		var o := Constraints.owner_of(ty, sel)
		if o != "" and Constraints.last_on(S, o) >= 0:
			return o
	return ""


func _cons_pick_target() -> void:
	if sel in Body.WEAPON:
		cons_target = {"kind": "weapon"}
	elif B.lim.has(sel):
		cons_target = {"kind": "part", "part": sel}
	else:
		_say("click a body part or the weapon first, then use the picked part as the target")
		return
	_say("constraint target: %s (now pick the part that follows it, or the head to look at it)" % _cons_tg_words(cons_target))


func _cons_target_fighter() -> void:
	_actors_sync()
	if actors_rt.size() < 2:
		_say("there is no other fighter: add one with 'Actor: add a second fighter' first")
		return
	cons_target = {"kind": "actor", "actor": 1 if actor_on == 0 else 0, "part": "head"}
	_say("constraint target: %s" % _cons_tg_words(cons_target))


func _cons_child_of() -> void:
	var owner := Constraints.owner_of("child_of", sel)
	if owner == "":
		_say("Child Of moves a hand, a foot or the hips: click one of them (or a part of that arm or leg) first")
		return
	if S.cards.is_empty():
		_say("constraints live in a scene: open a scene, or press Enter to add the body as a card first")
		return
	var tg := cons_target
	if tg.is_empty() or Constraints.bad_target(B, owner, tg) != "":
		tg = {"kind": "part", "part": Body.twin(owner)} if owner.begins_with("hand") else {"kind": "point", "at": B.P[owner]}
	var why := Constraints.bad_target(B, owner, tg)
	if why != "":
		_say("the %s cannot follow %s (%s): pick another target with 'Constraint: use the picked part as the target'" % [_cons_words(owner), _cons_tg_words(tg), why])
		return
	var t := clampf(playhead, 0.0, S.length())
	if Constraints.target_xf(S, B, tg, t) == null:
		_say("%s is not there now: pick another target with 'Constraint: use the picked part as the target'" % _cons_tg_words(tg))
		return
	_do(func(): Constraints.add_child_of(S, B, owner, tg, t))
	_dummy_hits()
	_say("the %s now follows %s from %s, keeping where it is from it (fade it out to let go; Ctrl+Z takes it back)" % [_cons_words(owner), _cons_tg_words(tg), Units.time(t, S.fps)])


func _cons_look() -> void:
	if S.cards.is_empty():
		_say("constraints live in a scene: open a scene, or press Enter to add the body as a card first")
		return
	_actors_sync()
	var tg := cons_target
	if tg.is_empty() or Constraints.bad_target(B, "head", tg) != "":
		if actors_rt.size() >= 2:
			tg = {"kind": "actor", "actor": 1 if actor_on == 0 else 0, "part": "head"}
		elif B.wep_on:
			tg = {"kind": "weapon"}
		else:
			tg = {"kind": "point", "at": LookAt.eye_point(B) + LookAt.head_forward(B) * 2.0}
	var t := clampf(playhead, 0.0, S.length())
	if Constraints.bad_target(B, "head", tg) != "" or Constraints.target_xf(S, B, tg, t) == null:
		_say("the head cannot look at %s now: pick another target with 'Constraint: use the picked part as the target'" % _cons_tg_words(tg))
		return
	_do(func(): Constraints.add_track_to(S, B, tg, t))
	_dummy_hits()
	_say("the head looks at %s from %s (turning in over %d frames), never past the neck's limits" % [_cons_tg_words(tg), Units.time(t, S.fps), Constraints.FADE_FRAMES])


func _cons_floor() -> void:
	var owner := Constraints.owner_of("floor", sel)
	if owner == "":
		_say("the floor keeps a foot up: click a foot or a part of that leg first")
		return
	if S.cards.is_empty():
		_say("constraints live in a scene: open a scene, or press Enter to add the body as a card first")
		return
	_do(func(): Constraints.add_floor(S, owner))
	_dummy_hits()
	_say("the %s never goes below the floor now (Ctrl+Z takes it back)" % _cons_words(owner))


func _cons_fade(to: float) -> void:
	var owner := _cons_owner_picked()
	if owner == "":
		_say("no constraint on the picked part: click a part that has one, or add one with 'Constraint: child of the target'")
		return
	var i := Constraints.last_on(S, owner)
	var t := clampf(playhead, 0.0, S.length())
	_do(func(): Constraints.fade(S, i, t, to))
	_dummy_hits()
	_say("the %s's constraint fades %s over %d frames from %s" % [_cons_words(owner), "in" if to > 0.0 else "out", Constraints.FADE_FRAMES, Units.time(t, S.fps)])


func _cons_release() -> void:
	var owner := _cons_owner_picked()
	if owner == "" or not owner in LimbIK.LIMBS:
		_say("release keeping the pose works on a held hand or foot: click one that has a Child Of, or fade the constraint out instead")
		return
	var i := Constraints.last_on(S, owner)
	var t := clampf(playhead, 0.0, S.length())
	if Constraints.weight(S.cons[i], t) <= 0.0:
		_say("the %s's constraint is off here: move the playhead to where it holds, then release" % _cons_words(owner))
		return
	if LimbIK.card_at(S, t) < 0:
		_say("release writes the pose into a card: click a card (the playhead goes onto it), or press Enter to add one here, then release")
		return
	var r := {}
	_do(func(): r.merge(Constraints.release_keep(S, B, i, t)))
	_dummy_hits()
	_say("released the %s at %s: card %d now holds the pose the constraint gave it (off by %.2f°), so nothing jumps" % [_cons_words(owner), Units.time(t, S.fps), int(r.get("card", 0)) + 1, float(r.get("residual", 0.0))])


func _cons_remove() -> void:
	var owner := _cons_owner_picked()
	if owner == "":
		_say("no constraint on the picked part: click a part that has one (a held hand or foot, the hips, the head)")
		return
	var i := Constraints.last_on(S, owner)
	_do(func(): S.cons.remove_at(i))
	_dummy_hits()
	_say("removed the %s's constraint (Ctrl+Z puts it back)" % _cons_words(owner))


## USER DRIVERS (GAP_ANALYSIS row 15; scripts/drivers.gd): the picked part's bend follows another part's bend, every frame
## (driven = source * factor + offset). The SOURCE is picked first ("Driver: use the picked part as the source", a view
## choice, not undone), then the follower is the picked part. Every edit is one undo step
var drv_source := ""


func _drv_pick_source() -> void:
	if not B.lim.has(sel):
		_say("click a body part first, then use it as the driver's source")
		return
	drv_source = sel
	_say("driver source: %s (now pick the part that follows it, then 'Driver: the picked part follows the source')" % nice(sel))


func _drv_follow() -> void:
	if not B.lim.has(sel):
		_say("click the part that follows first, then 'Driver: the picked part follows the source'")
		return
	if drv_source == "" or not B.lim.has(drv_source):
		_say("no driver source yet: click the part that drives, then 'Driver: use the picked part as the source'")
		return
	if drv_source == sel:
		_say("a part cannot drive itself: pick another source")
		return
	var d := {"driven": sel, "axis": 0, "source": drv_source, "src_axis": 0, "factor": 1.0, "offset": 0.0}
	_do(func(): Drivers.put(S.drivers, d))
	_dummy_hits()
	_say("%s now follows %s at factor 1.0 (bend on bend, every frame; the factor presets change it; Ctrl+Z takes it back)" % [nice(sel), nice(drv_source)])


func _drv_factor(f: float) -> void:
	var i := Drivers.on(S.drivers, sel)
	if i < 0:
		_say("no driver on the picked part: click the part that follows, then 'Driver: the picked part follows the source'")
		return
	_do(func(): S.drivers[i]["factor"] = f)
	_dummy_hits()
	_say("%s follows %s x %s now (Ctrl+Z takes it back)" % [nice(sel), nice(String(S.drivers[i]["source"])), str(f)])


func _drv_remove() -> void:
	if Drivers.on(S.drivers, sel) < 0:
		_say("no driver on the picked part: nothing to take off. Pick the driven part first")
		return
	_do(func(): Drivers.remove_on(S.drivers, sel))
	_dummy_hits()
	_say("removed the driver on %s (Ctrl+Z puts it back)" % nice(sel))


## SECONDARY MOTION (ROADMAP item 26; scripts/secondary_motion.gd). A ponytail, a cloth strip or an oak bo hangs from a
## joint and follows it with lag and overshoot. "Secondary: add ..." adds the item AND bakes it in one undo step: the sim
## runs over the scene's frames and the keys are written to the scene (S.secondary). The view draws the baked chain at the
## playhead; before a bake the chain shows at rest. Bake again after the animation changes.
var _sec_line: MeshInstance3D


func _sec_attach_now(item: Dictionary) -> Vector3:
	return SecondaryMotion.attach_point(B, item)


func _sec_add(key: String) -> void:
	var item := SecondaryMotion.preset(key)
	item["name"] = SecondaryMotion.free_name(S.secondary, String(item["name"]))
	var sec := SecondaryMotion.with_item(S.secondary, item)
	sec = SecondaryMotion.bake_scene(S, B, sec)
	_do(func(): S.secondary = sec)
	_dummy_hits()
	_say("added the %s and baked it: %d frames of keys (Ctrl+Z takes it back)" % [String(item["name"]), S.length() * S.fps + 1])


func _sec_bake() -> void:
	if (S.secondary.get("items", []) as Array).is_empty():
		_say("no secondary motion yet: 'Secondary: add a ponytail' (or a cloth strip, or a weapon flex) first")
		return
	var sec := SecondaryMotion.bake_scene(S, B, S.secondary)
	_do(func(): S.secondary = sec)
	_dummy_hits()
	_say("baked %d secondary item(s) to keys (Ctrl+Z takes it back)" % (S.secondary.get("items", []) as Array).size())


func _sec_clear() -> void:
	if (S.secondary.get("items", []) as Array).is_empty():
		_say("no secondary motion to clear: run Secondary: add a ponytail to add one")
		return
	_do(func(): S.secondary = {})
	_dummy_hits()
	_say("took the secondary motion off the scene (Ctrl+Z puts it back)")


## the overlay: each item's chain at the playhead, from its baked keys (at rest when not baked yet)
func _sec_draw() -> void:
	if _sec_line == null:
		_sec_line = MeshInstance3D.new()
		_sec_line.name = "secondary"
		_sec_line.mesh = ImmediateMesh.new()
		add_child(_sec_line)
	var im := _sec_line.mesh as ImmediateMesh
	im.clear_surfaces()
	var items: Array = S.secondary.get("items", []) if S != null else []
	if items.is_empty() or clean:
		return
	var t := clampf(playhead, 0.0, S.length())
	var cols := [Color(0.35, 0.85, 1.0, 0.9), Color(1.0, 0.6, 0.25, 0.9), Color(0.6, 1.0, 0.45, 0.9)]
	for k in items.size():
		var item: Dictionary = items[k]
		var th := SecondaryMotion.replay(S.secondary, item, t)
		var pts := SecondaryMotion.points(item, _sec_attach_now(item), th)
		im.surface_begin(Mesh.PRIMITIVE_LINES, Overlays._mat())
		im.surface_set_color(cols[k % cols.size()])
		for i in pts.size() - 1:
			im.surface_add_vertex(pts[i])
			im.surface_add_vertex(pts[i + 1])
		for p in pts:   # a small cross at every node: the joints the baked keys drive
			for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				im.surface_add_vertex(p - ax * 0.012)
				im.surface_add_vertex(p + ax * 0.012)
		im.surface_end()


## ASK AI (round 46, GATES BB2): opens / closes the AI box (scripts/ai_box.gd) at the right, above the cards. The box
## and its model live as long as the window; closing it while it works stops it
var ui_ai: AiBox


func _ai_toggle() -> void:
	if ui_ai == null:
		ui_ai = AiBox.new()
		ui_ai.anchor_left = 1.0
		ui_ai.anchor_right = 1.0
		ui_ai.anchor_top = 1.0
		ui_ai.anchor_bottom = 1.0
		ui_ai.offset_right = -RIGHT_W - 12   # left of the part panel, as the undo history sits
		ui_ai.offset_left = -RIGHT_W - 12 - 460
		ui_ai.add_theme_stylebox_override("panel", ui_find_box)   # the floating panels' look (follows the theme)
		ui_ai.offset_bottom = -BOTTOM_H - 92 - 12
		ui_ai.offset_top = ui_ai.offset_bottom - 360
		ui_ai.visible = false
		ui_root.add_child(ui_ai)
		ui_ai.setup(self)
	ui_ai.visible = not ui_ai.visible
	if ui_ai.visible:
		ui_ai.ui_in.grab_focus()
		_say("type what should happen and press Enter: the AI builds it here, one Ctrl+Z per step")
	else:
		ui_ai.stop()


## BAKE (round 48, DD4, UPGRADES_300 #250): the open scene flattened into one card per frame (scripts/bake.gd), one undo step
func _bake() -> void:
	if S.cards.is_empty():
		_say("nothing to bake: the scene has no cards yet. Add a card (pose the body, then + Card) first")
		return
	_step_hint = "Bake to cards"
	_push_undo()
	var GB := Body.new()
	GB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r := Bake.bake(S, GB, float(S.fps))
	sel_card = clampi(sel_card, 0, S.cards.size() - 1)
	_rebuild_cards()
	_refresh()
	_say("BAKED: %d cards became %d (one a frame at %d fps)%s; Ctrl+Z gives them back" % [r["was"], r["cards"], S.fps,
		("; part keys on %d part%s folded in" % [r["part_keys"], "" if r["part_keys"] == 1 else "s"]) if r["part_keys"] > 0 else ""]
		+ ("; turned off (now inside the cards): %s" % ", ".join(r["off"]) if not (r["off"] as Array).is_empty() else ""))


## KEY REDUCTION (ROADMAP 68, scripts/key_reduce.gd): a tolerance slider over every joint's part keys. The readout says
## how many keys stay and where the worst error is. A drag previews on the scene; the first change takes ONE undo step
## (_kr_armed); closing the panel keeps the result.
var _kr_armed := false
var _kr_pop: PopupPanel = null
var _kr_slider: HSlider = null
var _kr_orig := {}
var _kr_readout: Label = null
var _kr_last := ""


func _keyreduce_popup() -> void:
	if S.part_keys.is_empty():
		_say("reduce keys: this scene has no part keys. Press K to key a part first, or bring in a bake or a video import")
		return
	if _kr_pop == null:
		_kr_pop = PopupPanel.new()
		var box := VBoxContainer.new()
		var lab := Label.new()
		lab.text = "Reduce keys: tolerance (deg)"
		box.add_child(lab)
		_kr_slider = HSlider.new()
		_kr_slider.min_value = 0.0
		_kr_slider.max_value = 5.0
		_kr_slider.step = 0.05
		_kr_slider.custom_minimum_size = Vector2(300, 28)
		_kr_slider.tooltip_text = "REDUCE KEYS: the most a key's removal may move the curve (on any angle channel). 0 removes nothing"
		_kr_slider.value_changed.connect(_kr_drag)
		box.add_child(_kr_slider)
		_kr_readout = Label.new()
		box.add_child(_kr_readout)
		_kr_pop.add_child(box)
		_kr_pop.popup_hide.connect(_kr_done)
		add_child(_kr_pop)
	_kr_orig = S.part_keys.duplicate(true)
	_kr_armed = false
	_kr_slider.set_value_no_signal(0.5)
	_kr_last = _kr_text(KeyReduce.reduce(_kr_orig, 0.5))
	_kr_readout.text = _kr_last
	_kr_pop.popup_centered(Vector2i(340, 100))
	_say("reduce keys: drag the tolerance (deg); the readout shows the keys that stay and the worst error. Esc or a click away keeps it; Ctrl+Z takes it back")


func _kr_drag(v: float) -> void:
	if not _kr_armed:
		_step_hint = "Reduce keys"
		_push_undo()
		_kr_armed = true
	var r := KeyReduce.reduce(_kr_orig, v)
	S.part_keys = r["pk"]
	_kr_last = _kr_text(r)
	_kr_readout.text = _kr_last
	_refresh()


func _kr_done() -> void:
	if _kr_armed:
		_say("REDUCED the part keys: %s. Ctrl+Z gives them back" % _kr_last)
	else:
		_say("reduce keys: nothing changed (drag the tolerance to thin the keys)")
	_kr_armed = false
	_refresh()


func _kr_text(r: Dictionary) -> String:
	var s := "%d -> %d keys, worst error %.2f deg" % [int(r["before"]), int(r["after"]), float(r["worst"])]
	if String(r["joint"]) != "":
		s += " at %.2f s (%s)" % [float(r["t"]), String(r["joint"])]
	return s


## CURVE EDITOR (round 42, XX2, UPGRADES_300 #240): opens / closes the panel (scripts/curve_editor.gd) that draws the
## picked part's part keys as curves; dragging a key there is one undo step
func _curve_toggle() -> void:
	if ui_curve == null:
		ui_curve = GraphEditor.new()   # GE: the curve editor plus channels, pivot scale, normalize, cycles (graph_editor.gd)
		ui_curve.anchor_top = 1.0
		ui_curve.anchor_bottom = 1.0
		ui_curve.anchor_right = 1.0
		ui_curve.offset_bottom = -BOTTOM_H - 92 - 126
		ui_curve.offset_top = ui_curve.offset_bottom - 190
		ui_curve.visible = false
		ui_curve.begin = _push_undo
		ui_curve.limit = func(j, v): return B.clamp_ang(j, v)
		ui_curve.changed = func(): S.apply(B, playhead); _refresh()
		ui_curve.say = func(t): _say(t)
		ui_root.add_child(ui_curve)
	ui_curve.visible = not ui_curve.visible
	_curve_sync()
	if ui_curve.visible:
		ui_curve.frame_all()
	_say("curve editor open: drag a key to change its angle and time (Ctrl+Z takes a drag back)" if ui_curve.visible else "curve editor closed")


## GRAPH EDITOR (round 51, GE1-GE4; scripts/graph_editor.gd): the channels view, the normalized view, the Cycles modifier
func _graph_cmd(what: String) -> void:
	if what == "cycles":
		if not S.part_keys.has(sel):
			_say("%s has no part keys: press K to key it, then add the Cycles modifier" % sel)
			return
		if PartKeys.mods_of(S.part_keys[sel]).any(func(x): return String(x.get("type", "")) == "cycles"):
			_say("%s already repeats (a Cycles modifier): open the curve editor's Mods menu to remove it" % sel)
			return
		_do(func(): PartKeys.add_mod(S.part_keys, sel, {"type": "cycles", "ch": -1, "before": "repeat", "after": "repeat", "before_n": 0, "after_n": 0, "mix": 1.0}))
		if ui_curve != null and ui_curve.visible:
			ui_curve.frame_all()
		_say("%s now repeats its keys before and after them (Cycles)  (Ctrl+Z takes it back)" % sel)
	elif ui_curve == null or not ui_curve.visible:
		_curve_toggle()
	if what == "cycles":
		pass
	elif what == "multi":
		var ge := ui_curve as GraphEditor
		ge.set_multi(not ge.multi)
		_say("graph editor: %s" % ("every keyed part, one channel per part and angle; click a channel to hide it" if ge.multi else "the picked part only"))
	else:
		var ge := ui_curve as GraphEditor
		ge.set_normalize(not ge.normalize)
		_say("graph editor: %s" % ("each curve fitted to -1..1 (the keys are not changed)" if ge.normalize else "degrees"))


var _why_sig := 0
var _why_all := []   # DD5: every HITCH / TIP SPEED span of the open scene (Why.spans)


func _curve_sync() -> void:
	if ui_curve == null or not ui_curve.visible:
		return
	var moved: bool = ui_curve.scene != S or ui_curve.joint != sel
	ui_curve.scene = S
	ui_curve.joint = sel
	ui_curve.playhead = playhead
	ui_curve.fps = S.fps
	ui_curve.card_times = S.times().map(func(x): return float(x[1]))   # DD0: Ctrl-snap to the cards
	ui_curve.offset_left = lw() + 12
	ui_curve.offset_right = -rw() - 12
	var sig := "%s|%d" % [sel, hash(var_to_str([S.cards, S.part_keys]))]
	if sig != _band_sig and not ui_curve._dragging:   # YY7: the people's band, measured again only when the scene changed
		_band_sig = sig   # (never mid-drag, and the view is refitted only for a new part: a refit under the mouse moved the key)
		ui_curve.band = GaitBand.for_part(S, sel) if GaitBand.joint_of(sel) != "" else {}
	var wsig := hash(var_to_str([S.cards, S.part_keys, S.spline, S.natural, S.pin, S.on_floor]))
	if wsig != _why_sig and not ui_curve._dragging:   # DD5: the rules' spans, measured again only when the scene changed
		_why_sig = wsig
		_why_all = Why.spans(S, ov.GB)
	ui_curve.why = Why.for_joint(_why_all, sel)
	if moved:
		ui_curve.sel_i = -1
		ui_curve.picked = []   # DD0: a new part, a new set of dots (the old [angle, index] pairs meant the old part's keys)
		ui_curve.frame_all()
	ui_curve.queue_redraw()


## BLOCK -> SPLINE -> CHECK (round 43, YY8; docs/ANIM_RESEARCH.md: animators block in stepped keys, add breakdowns
## while still stepped, then spline and polish). One guided path over the parts Poser already has: BLOCK = the stepped
## preview on (each card holds until the next); SPLINE = it off, so the scene plays exactly as before, and Check runs.
## Each switch is the stepped toggle's own ONE undo step (it puts the scene's pose on the body); the scene is not edited.
func _stage_block() -> void:
	if S.cards.size() < 2:
		_say("blocking needs a scene of two cards or more: press Enter to add the body as a card")
		return
	if stepped_view:
		_say("already blocking (stepped): pose the key cards, then run 'Spline and check' from search")
		return
	_tool(3)
	_say("1 BLOCK: each card holds until the next (stepped).  Pose the key cards, add breakdowns while it is stepped; then 'Spline and check'")


func _stage_spline() -> void:
	if S.cards.size() < 2:
		_say("spline and check needs a scene of two cards or more: press Enter to add the body as a card")
		return
	var was := stepped_view
	if stepped_view:
		_tool(3)
	_check()
	_say("%s3 CHECK: %s" % ["2 SPLINE: in-betweens back, the scene's own playback.  " if was else "", "clean" if findings.is_empty() else "%d findings to look at (the list below)" % findings.size()])


## YY7: every leg joint of the scene's walk against 42 real walkers; the ones outside named
func _gait_compare() -> void:
	var r := GaitBand.report(S)
	if not r["ok"]:
		_say("compare to real walkers: %s; open a walk (e.g. walk_bat) and search this again" % r["why"])
		return
	if r["listed"].is_empty():
		_say("compare to real walkers: hips, knees and ankles all inside the people's band (2 SD) for 90 %% of the step; open the curve editor on a thigh, calf or foot to see the band")
		return
	_say("outside real walkers (more than 2 SD for over 10 %% of the step): %s; open the curve editor on it to see where" % ", ".join(r["listed"].map(func(x): return "%s %s %d %%" % [x["part"].right(1).replace("r", "right").replace("l", "left"), x["joint"], int(round(x["out"] * 100.0))])))


## KEY INTERPOLATION (round 42, XX1, UPGRADES_300 #241 #242 #247): set the picked part's key nearest the playhead
## (kind "interp": constant / linear / bezier; "handle": auto_clamped / auto / vector / aligned / free) or the whole part's
## INFINITY (kind "inf": hold / linear / cycle / cycle_offset). Logic lives in scripts/part_keys.gd. One undo step
func _part_curve(kind: String, mode: String) -> void:
	if not S.part_keys.has(sel):
		_say("%s has no part keys: press K to key it, then set how its curve runs" % sel)
		return
	var idx := PartKeys.key_near(S.part_keys[sel], playhead)
	if kind != "inf" and idx < 0:
		_say("no %s key near the playhead (0.05 s): move the playhead onto a key, then set it" % sel)
		return
	_do(func():
		if kind == "inf":
			PartKeys.set_inf(S.part_keys, sel, mode)
		elif kind == "interp":
			PartKeys.set_interp(S.part_keys, sel, idx, mode)
		else:
			PartKeys.set_handle_type(S.part_keys, sel, idx, mode))
	_say("%s %s: %s  (Ctrl+Z takes it back)" % [sel, kind, mode])


## ROADMAP 66: set the TYPE of the picked part's key(s) ("key" / "breakdown" / "inbetween"): the curve editor's picks on
## this part when it is open with some, else the key nearest the playhead. One undo step (saved and mirrored with the keys)
func _part_ktype(kt: String) -> void:
	if not S.part_keys.has(sel) or (S.part_keys[sel] as Array).is_empty():
		_say("%s has no part keys: press K to key it, then set its type" % sel)
		return
	var idxs := []
	if ui_curve != null and ui_curve.visible and ui_curve.joint == sel:
		idxs = ui_curve.picked_keys()
	if idxs.is_empty():
		var i := PartKeys.key_near(S.part_keys[sel], playhead)
		if i >= 0:
			idxs = [i]
	if idxs.is_empty():
		_say("no %s key near the playhead (0.05 s): move the playhead onto a key, or pick keys in the curve editor, then set the type" % sel)
		return
	_do(func():
		for i in idxs:
			PartKeys.set_ktype(S.part_keys, sel, i, kt))
	_say("%d %s key%s set to %s  (Ctrl+Z takes it back)" % [idxs.size(), sel, "" if idxs.size() == 1 else "s", kt])


## ROADMAP 66: "Breakdown: add a key at the playhead in between": a breakdown key on the picked part at the playhead, its
## angles the curve's own there, so the pose does not change. Needs the playhead strictly between two of its keys
func _part_breakdown() -> void:
	if not S.part_keys.has(sel) or (S.part_keys[sel] as Array).size() < 2:
		_say("%s needs two part keys to put a breakdown between them: press K at two times, then try again" % sel)
		return
	var keys: Array = S.part_keys[sel]
	var t := clampf(playhead, 0.0, S.length())
	if t <= float(keys[0]["t"]) or t >= float(keys[keys.size() - 1]["t"]):
		_say("the playhead is outside %s's keys (%.2f to %.2f s): move it between two of them" % [sel, float(keys[0]["t"]), float(keys[keys.size() - 1]["t"])])
		return
	if PartKeys.key_near(keys, t, PartKeys.SAME_T) >= 0:
		_say("a key is already at %.2f s on %s: pick it and set its type (key / breakdown / inbetween)" % [t, sel])
		return
	_do(func(): PartKeys.add_breakdown(S.part_keys, sel, t))
	_say("breakdown added on %s at %.2f s, on the curve  (Ctrl+Z takes it back)" % [sel, t])


## ROADMAP 66: "pick only main keys" in the curve editor: the picks become the "key"s only, so a retime moves just them
func _curve_main_keys() -> void:
	if ui_curve == null or not ui_curve.visible:
		_say("open the curve editor first (Curve editor), then pick only main keys")
		return
	var n: int = ui_curve.pick_main_keys()
	_say("picked %d main key%s; breakdowns and in-betweens are left out of the pick" % [n, "" if n == 1 else "s"])


func _reset_part() -> void:
	if sel in Body.WEAPON or not B.ang.has(sel):
		_say("nothing to reset: pick a body part first (click it on the figure)")
		return
	var was: Vector3 = B.ang[sel]
	var off: Vector3 = B.offset
	if sel == "pelvis":
		B.offset = Vector3.ZERO
	B.set_ang_safe(sel, Vector3.ZERO)
	if was.is_zero_approx() and off.is_equal_approx(B.offset):
		_say("the %s is already straight: drag it to bend it, or pick another part" % nice(sel))


## snap the selected joint's free angles to the nearest 90 (or 45) the range allows; it stops at contact
func _snap(step: float) -> void:
	if sel in Body.WEAPON:
		return
	var v: Vector3 = B.ang[sel]
	var L: Dictionary = B.lim[sel]
	var out := v
	for k in 3:
		var key: String = ["bend", "side", "twist"][k]
		var r: Vector2 = L[key]
		if r.y - r.x < 0.5:
			continue
		var s := snappedf(v[k], step)
		if s < r.x:
			s += step
		if s > r.y:
			s -= step
		out[k] = clampf(s, r.x, r.y)
	B.set_ang_safe(sel, out)
	_say("snapped the %s to %d° steps" % [nice(sel), int(step)])


func _arms_relaxed() -> void:
	for sd in ["_r", "_l"]:
		B.set_ang_safe("upperarm" + sd, Vector3(0, -90 + ARMS_OUT, 0))
		B.set_ang_safe("lowerarm" + sd, Vector3(10, 0, 0))


func _reset_all() -> void:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()


func _bat_put(h: String) -> void:
	B.weapon_to_hand(h)
	sel = "bat_handle"
	_say("bat in the %s with the standard grip (Nick's). It moves with the hand. 'Free the bat' to refit it." % nice(h))


## ONE WEAPON PICKER (round 25, GATES FF1, Nick 10-16: "weapons could be a drop down list so it looks cleaner"): the
## same dropdown in both panels; picking = what the old buttons did (one undo step); _refresh makes every picker show
## what the body holds, whatever changed it (B, undo, a scene, the search); select() does not fire item_selected
const WEAPONS := [["None", "", "no weapon"], ["Metal bat", "metal_bat", "84 cm"], ["Bo staff", "staff", "180 cm"], ["Long hammer", "long_hammer", "110 cm"], ["Long axe", "long_axe", "120 cm"], ["Dagger", "dagger", "30 cm"], ["2 daggers", "two_daggers", "30 cm"]]
var ui_weapon_pickers: Array[OptionButton] = []


func _weapon_picker(nm := "opt_weapon") -> OptionButton:   # names differ: every control is found by its name
	var o := OptionButton.new()
	o.name = nm
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for w in WEAPONS:
		o.add_item("%s   (%s)" % [w[0], w[2]] if w[1] != "" else w[0])
	o.tooltip_text = "the weapon in the hand: pick one, or None to take it away"
	o.item_selected.connect(_pick_weapon)
	ui_weapon_pickers.append(o)
	return o


func _pick_weapon(k: int) -> void:
	if k == weapon_shown():
		return
	if WEAPONS[k][1] == "two_daggers":
		_do(_two_daggers)
		return
	_do(_bat_remove if WEAPONS[k][1] == "" else _kind.bind(WEAPONS[k][1]))


## the picker's row for what the body holds
func weapon_shown() -> int:
	if not B.wep_on:
		return 0
	if B.wep2_on:
		return WEAPONS.size() - 1
	for k in WEAPONS.size():
		if WEAPONS[k][1] == B.wep_kind:
			return k
	return 0


func _sync_weapon() -> void:
	var k := weapon_shown()
	for o in ui_weapon_pickers:
		if is_instance_valid(o) and o.selected != k:
			o.select(k)


func _bat_remove() -> void:
	B.wep_on = false
	B.wep2_on = false
	B.grip = false
	if sel in Body.WEAPON:
		sel = "hand_r"
	_say("bat removed")


func _bat_lock() -> void:
	if not B.wep_on:
		return
	if B.wep_hand != "":
		B.unlock_weapon()
		_say("bat FREE: drag it (Shift = turn, Alt = spin) or use the sliders to fit it, then 'Lock bat to hand'")
	else:
		var mid := B.wep_point(B.wep_handle * 0.5)
		var h := "hand_r" if (B.E["hand_r"] as Vector3).distance_to(mid) <= (B.E["hand_l"] as Vector3).distance_to(mid) else "hand_l"
		B.lock_weapon(h)
		var off := B.capture_second()
		if off >= 0.0 and off <= 0.05:
			_say("LOCKED in BOTH hands (the %s holds it, the other hand keeps its grip at %s): they move together. G lets the second hand go" % [nice(h), Units.len(B.grip_u)])
		else:
			_say("LOCKED to the %s: it moves with the hand (the other hand isn't on the shaft%s)" % [nice(h), "" if off < 0.0 else ": %.0f cm off" % (off * 100.0)])


func _fingers(side: String, kind: String) -> void:
	B.hand_shape(side, kind)
	_say("%s hand: %s" % ["left" if side == "l" else "right", kind])


var _shape_i := {"l": 0, "r": 0}
var ui_hand := {}   # "rcurl" / "rspread" / "lcurl" / "lspread" -> HSlider (YY3)
var ui_finger := {}   # "rthumb" / "rindex" ... "lpinky" -> HSlider (ROADMAP 73: one curl per finger)
var ui_back := {}   # "bend" / "side" / "twist" -> HSlider (YY4)


func _on_back_slider(v: float, k: String) -> void:
	B.back_bend(k, v)
	_refresh()
	_say("the back: %s %.0f° over the spine, neck and head" % [{"bend": "forward", "side": "side", "twist": "twist"}[k], B.back_of(k)])


## LAYER (round 43, YY9): the body's change from what the scene plays at the playhead, added to the scene's one layer
## (divided by the weight, so at this weight the change shows exactly; weight 0 becomes 1).
## LAYERS (round 49, NA1): the change goes onto the ACTIVE layer (layer_on: -1 = the YY9 one, else S.layers[i]). An
## additive layer adds (change / weight here); an OVERRIDE layer's angle is set so that lerp(below, angle, weight) is
## the body now (below = what plays with this layer muted). A LOCKED layer refuses; weight 0 here refuses (nothing could show).
var layer_on := -1


func _layer_active() -> Dictionary:
	return S.layers[layer_on] if layer_on >= 0 and layer_on < S.layers.size() else {}


func _layer_name() -> String:
	return String(_layer_active().get("name", "the first layer (additive)")) if layer_on >= 0 else "the first layer (additive)"


func _layer_take() -> void:
	if S.cards.size() < 2:
		_say("a layer is over a scene: open one with two cards or more")
		return
	var L := _layer_active()
	if bool(L.get("lock", false)):
		_say("LOCKED: '%s' is locked; 'Layer: lock' unlocks it, or 'Layer: next' picks another" % _layer_name())
		return
	if not L.is_empty() and Scene.layer_weight(L, playhead) <= 0.0:
		_say("'%s' has weight 0 here, so no change could show: use 'Layer stronger' first" % _layer_name())
		return
	var now := B.ang.duplicate()
	var PB := Body.new()
	PB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_ps().apply(PB, playhead)   # what plays here, layer included
	var n := 0
	if L.is_empty():
		if S.layer_w <= 0.0:
			S.layer_w = 1.0
		for j in now:
			var d: Vector3 = (now[j] as Vector3) - (PB.ang[j] as Vector3)
			if d.length() > 0.01:
				S.layer[j] = (S.layer.get(j, Vector3.ZERO) as Vector3) + d / S.layer_w
				n += 1
	else:
		var w := Scene.layer_weight(L, playhead)
		var below := {}
		if L["mode"] == "over":
			var was: bool = L.get("mute", false)
			L["mute"] = true
			var QB := Body.new()
			QB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			_ps().apply(QB, playhead)
			L["mute"] = was
			below = QB.ang
		for j in now:
			var d: Vector3 = (now[j] as Vector3) - (PB.ang[j] as Vector3)
			if d.length() <= 0.01:
				continue
			if L["mode"] == "add":
				L["v"][j] = (L["v"].get(j, Vector3.ZERO) as Vector3) + d / w
			else:
				var bl: Vector3 = below[j]
				L["v"][j] = bl + ((now[j] as Vector3) - bl) / w
			n += 1
	_dummy_hits()   # the landed copy (SL) carries the layer too
	_ps().apply(B, playhead)
	_say(("layer '%s': %d part%s changed, over the whole scene (cards untouched; 'Layer weaker' / 'Layer: delete')" % [_layer_name(), n, "" if n == 1 else "s"]) if n > 0 else "layer: the body is what the scene plays here; turn a part first, then keep the change")


## step: the ACTIVE layer's weight change (clamped 0..1); -9 deletes it. A layer with keyed weight changes the key at
## the playhead (one is added there if none is)
func _layer_weight(step: float) -> void:
	var L := _layer_active()
	if L.is_empty() and S.layer.is_empty():
		_say("no layer: turn a part, then search 'Layer: keep this change through the whole scene'")
		return
	if bool(L.get("lock", false)):
		_say("LOCKED: '%s' is locked; 'Layer: lock' unlocks it" % _layer_name())
		return
	if L.is_empty():
		if step <= -9.0:
			S.layer = {}
			S.layer_w = 1.0
		else:
			S.layer_w = clampf(S.layer_w + step, 0.0, 1.0)
	elif step <= -9.0:
		S.layers.remove_at(layer_on)
		layer_on = mini(layer_on, S.layers.size() - 1)
	else:
		L["w"] = clampf(float(L["w"]) + step, 0.0, 1.0)   # a keyed layer: "w" scales its curve (NA2)
	_dummy_hits()
	_ps().apply(B, playhead)
	if step <= -9.0:
		_say("layer deleted; active now: %s" % _layer_name())
	else:
		_say("'%s' weight %.2f here (0 = the layers below alone, 1 = the full change)" % [_layer_name(), Scene.layer_weight(_layer_active(), playhead) if layer_on >= 0 else S.layer_w])


## MERGE DOWN (round 49, NA3; scripts/layer_merge.gd): every layer into the cards, then the layers are gone. One undo step
func _layer_merge() -> void:
	if S.layer.is_empty() and S.layers.is_empty():
		_say("no layers to merge: the cards already play everything. To add one, pose a part and use 'Layer: keep this change through the whole scene'")
		return
	if S.layers.any(func(L): return bool(L.get("lock", false))):
		_say("LOCKED: a locked layer cannot be merged; unlock it first ('Layer: next', then 'Layer: lock')")
		return
	_step_hint = "Merge layers down"
	_push_undo()
	var r := LayerMerge.merge(S)
	layer_on = -1
	_rebuild_cards()
	_dummy_hits()
	_ps().apply(B, playhead)
	_refresh()
	_say("merged into %d card%s: at the cards' arrivals the scene plays as layered within %.3f° (%d passes); between them within %.2f° (%s). Ctrl+Z gives the layers back" % [r["cards"], "" if r["cards"] == 1 else "s", r["at_cards"], r["iters"], r["every_frame"], r["frame_at"]])


## NA1: a new layer on top, made active ("add" or "over")
func _layer_new(mode: String) -> void:
	S.layers.append({"name": "Layer %d" % (S.layers.size() + 2), "mode": mode, "w": 1.0, "wk": [], "mute": false, "solo": false, "lock": false, "v": {}})
	layer_on = S.layers.size() - 1
	_say("new %s layer '%s' on top, active: pose a part, then 'Layer: keep this change through the whole scene'" % ["additive" if mode == "add" else "override", _layer_name()])


## NA1: mute / solo / lock the active layer (the YY9 first layer has only its weight)
func _layer_flag(f: String) -> void:
	var L := _layer_active()
	if L.is_empty():
		_say("'%s' only has a weight; make a further layer ('Layer: new additive' / 'Layer: new override') or 'Layer: next'" % _layer_name())
		return
	L[f] = not bool(L.get(f, false))
	_dummy_hits()
	_ps().apply(B, playhead)
	_say("'%s' %s %s" % [_layer_name(), f, "on" if L[f] else "off"])


## NA1: the next layer becomes active (the first layer, then each of S.layers, round)
func _layer_next() -> void:
	layer_on = layer_on + 1 if layer_on + 1 < S.layers.size() else -1
	var L := _layer_active()
	var bits := []
	for f in ["mute", "solo", "lock"]:
		if bool(L.get(f, false)):
			bits.append(f)
	_say("active layer: %s%s%s" % [_layer_name(), (", " + String(L["mode"]).replace("add", "additive").replace("over", "override")) if not L.is_empty() else "",
		(" [" + ", ".join(bits) + "]") if not bits.is_empty() else ""])


## NA1: the active layer's weight KEYED at the playhead (to w, or to its weight here)
func _layer_key_w(w := -1.0) -> void:
	var L := _layer_active()
	if L.is_empty() or bool(L.get("lock", false)):
		_say("to key a weight, pick a further, unlocked layer ('Layer: next')" if L.is_empty() else "LOCKED: '%s' is locked; use 'Layer: lock' to unlock it" % _layer_name())
		return
	var wk: Array = L["wk"]
	var v := (Scene.key_curve(wk, playhead) if not wk.is_empty() else float(L["w"])) if w < 0.0 else w
	for k in wk:
		if absf(float(k[0]) - playhead) < 1e-4:
			k[1] = v
			_say("'%s' weight key at %s = %.2f" % [_layer_name(), Units.time(playhead, S.fps), v])
			return
	wk.append([playhead, v])
	wk.sort_custom(func(a, b): return a[0] < b[0])
	_dummy_hits()
	_say("'%s' weight keyed at %s = %.2f (%d keys; the weight now follows them)" % [_layer_name(), Units.time(playhead, S.fps), v, wk.size()])


## BREATH (YY6): step = -1 toggles (off <-> 15 a minute), else the rate changes by step (6..40 a minute)
func _breath_set(step: float) -> void:
	if step == -1.0:
		S.breath = 0.0 if S.breath > 0.0 else Body.BREATH_DEFAULT
	else:
		S.breath = clampf((S.breath if S.breath > 0.0 else Body.BREATH_DEFAULT) + step, 6.0, 40.0)
	_dummy_hits()   # the landed copy of the scene (SL) carries the rate too
	_ps().apply(B, playhead)
	_say("breathing: %s" % ("off" if S.breath <= 0.0 else "%.0f breaths a minute (people at rest 12 to 20 breaths a minute), ~5 mm at the chest" % S.breath))


## a hand slider moved: the whole hand follows (the undo step was taken when the drag began)
func _on_hand_slider(v: float, sd: String, k: String) -> void:
	var cs := B.hand_curl_of(sd)
	if k == "curl":
		B.hand_curl(sd, v, cs.y)
	else:
		B.hand_curl(sd, cs.x, v)
	_refresh()
	_say("%s hand: curl %.0f%%, spread %.0f%%" % ["right" if sd == "r" else "left", B.hand_curl_of(sd).x * 100.0, B.hand_curl_of(sd).y * 100.0])


func _hand_point(sd: String) -> void:
	B.hand_point(sd)
	_say("%s hand: pointing (the index straight)" % ["right" if sd == "r" else "left"])


## one finger's curl slider moved (ROADMAP 73): that finger bends at the hand's spread; the other fingers stay
func _on_finger_slider(v: float, sd: String, f: String) -> void:
	B.finger_curl(sd, f, v, B.hand_curl_of(sd).y)
	B.fk()
	_refresh()
	_say("%s %s: curl %.0f%%" % ["right" if sd == "r" else "left", f, v * 100.0])


## the hand a pose goes on (ROADMAP 73): the picked part's side when it is a hand or finger part; "" = pick one first
func _hand_side_of_sel() -> String:
	var hand := sel.begins_with("hand_")
	for f in ["thumb_", "index_", "middle_", "ring_", "pinky_"]:
		hand = hand or sel.begins_with(f)
	if not hand:
		return ""
	return "l" if sel.ends_with("_l") else "r"


## a pose button or palette entry (ROADMAP 73): no hand picked = no undo step (the message says what to pick)
func _pose_pick(pname: String) -> void:
	if _hand_side_of_sel() == "":
		_say("pick a hand or finger part first: the %s pose goes on that hand" % pname)
		return
	_do(_hand_pose.bind(pname))


## a named hand pose (ROADMAP 73): ONE undo step (_do). With cards in the scene, the hand's 15 joints are keyed at the
## playhead the way K keys a part (PartKeys.put); with no cards the pose just goes on the hand
func _hand_pose(pname: String) -> void:
	var side := _hand_side_of_sel()
	if side == "":
		_say("pick a hand or finger part first: the %s pose goes on that hand" % pname)
		return
	B.hand_pose(side, pname)
	var side_name := "right" if side == "r" else "left"
	if S.cards.is_empty():
		_say("%s hand: %s pose (no cards yet, so nothing is keyed: open a scene with cards to key it)" % [side_name, pname])
		return
	var t := clampf(playhead, 0.0, S.length())
	for j in B.hand_joints(side):
		PartKeys.put(S.part_keys, j, t, B.ang[j])
	_say("%s hand: %s pose, keyed at %.2f s (15 joints; Ctrl+Z takes it back)" % [side_name, pname, t])


## the hand sliders read the body back (no signal: a refresh is not a drag)
func _hand_sliders_sync() -> void:
	for k in ui_back:
		(ui_back[k] as HSlider).set_value_no_signal(B.back_of(k))
	for sd in ["r", "l"]:
		if ui_hand.has(sd + "curl"):
			var cs := B.hand_curl_of(sd)
			(ui_hand[sd + "curl"] as HSlider).set_value_no_signal(cs.x)
			(ui_hand[sd + "spread"] as HSlider).set_value_no_signal(cs.y)
		for f in ["thumb", "index", "middle", "ring", "pinky"]:
			if ui_finger.has(sd + f):
				(ui_finger[sd + f] as HSlider).set_value_no_signal(B.finger_curl_of(sd, f))
func _fingers_cycle() -> void:
	var side := "l" if sel.ends_with("_l") else "r"
	_shape_i[side] = (_shape_i[side] + 1) % 3
	_fingers(side, ["open", "grip", "fist"][_shape_i[side]])


## save the bat's place in the hand + the fingers as the new standard grip
func _save_grip() -> void:
	if not B.wep_on or B.wep_hand == "":
		_say("lock the bat to a hand first")
		return
	var h := B.wep_hand
	var sd := h.substr(h.length() - 2)
	var fing := {}
	for j in Body.FINGERS:
		if j.ends_with(sd):
			var v: Vector3 = B.ang[j]
			fing[j] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
	var d := {"_note": "standard %s grip, saved from the poser (body.gd weapon_to_hand)" % B.wep_kind, "weapon": B.wep_kind,
		"hand": h, "local_pos": Body._p(B.wep_lpos), "local_rot": Body._q(B.wep_lrot), "fingers": fing,
		"other_hand_m": B.grip_u if B.grip else -1.0}
	_confirm("Make this the standard %s grip?\nEvery weapon put in a hand from now on uses it; Ctrl+Z can't bring the old grip back." % B.wep_kind.replace("_", " "),
		"Make it standard", _save_grip_now.bind(d))


func _save_grip_now(d: Dictionary) -> void:
	_write("res://data/grips/%s.json" % B.wep_kind, d)
	_say("saved as the standard %s grip (where the main hand holds + the fingers%s)" % [B.wep_kind.replace("_", " "), ", + the other hand" if B.grip else ""])


## slide the main hand along the shaft, the weapon stays put, the body follows
func _slide(d: float) -> void:
	if not B.wep_on or B.wep_hand == "":
		_say("put a weapon in the hand first")
		return
	if not slide_body:
		B.slide_in_hand(-d)
		B.apply_grip()
		_say("the weapon slid in the hand: hand at %s from the lower end" % Units.len(B.hold_u()))
		return
	if B.slide_hand(d):
		_say("main hand at %s from the lower end%s" % [Units.len(B.hold_u()), ", the other hand re-gripped" if B.grip else ""])
	else:
		_say("the arm can't reach further that way: turn the weapon or move the body first")


## G: the second hand on / off. On: if that hand is already on the shaft, it keeps the grip it has there.
func _toggle_second() -> void:
	if B.grip:
		B.grip = false
		_say("second hand off the weapon")
		return
	var off := B.capture_second()
	if off < 0.0 or off > 0.05:
		B.grip = true   # the fitted grip of this kind (or the rough reach) takes the hand to the shaft
	_say("second hand on the weapon at %s" % Units.len(B.grip_u))


## the main hand to the weapon's lower end (6 cm of shaft left below the fist), in 3 cm steps so the arm follows
## smoothly; stops where the arm can't go further
func _hand_to_end() -> void:
	if not B.wep_on or B.wep_hand == "":
		_say("put a weapon in the hand first")
		return
	var n := 0
	while B.hold_u() > 0.09 and n < 60:
		var d := -minf(0.03, B.hold_u() - 0.06)
		if slide_body:
			if not B.slide_hand(d):
				break
		else:
			# round 36: slide_in_hand moves the hand's place on the shaft BY d; this was -d (copied from _slide's
			# key, where d is the weapon's move), so with "weapon moves" on the hand climbed to the far end
			if B.hold_u() + d < 0.0:
				break
			B.slide_in_hand(d)
			B.apply_grip()
		n += 1
	_say("main hand at %s from the lower end%s" % [Units.len(B.hold_u()), "" if B.hold_u() <= 0.1 else " (the arm can't follow further: turn the weapon or the body)"])


func _slide_mode() -> void:
	slide_body = not slide_body
	ui_slide_btn.text = "Slide , . : body follows" if slide_body else "Slide , . : weapon moves"
	_say("now , and . %s" % ("move the hand along the weapon, the weapon stays and the arm follows" if slide_body else "slide the weapon through the hand, the hand stays"))


## switch the weapon kind; if one is in a hand, it goes back in that hand with this kind's grip
func _kind(k: String) -> void:
	var h := B.wep_hand
	B.wep2_on = false   # one weapon picked: the off-hand one is put away
	B.set_kind(k)
	if B.wep_on and h != "":
		B.weapon_to_hand(h)
	elif not B.wep_on:
		B.weapon_to_hand("hand_r")
	sel = "bat_handle"
	_say({"metal_bat": "metal bat (84 cm)", "staff": "staff / bo (180 cm): slide your hand along it with , and .  and put the other hand on with G, [ ]",
		"long_hammer": "long hammer (110 cm, steel head across the tip): G for both hands, [ ] to slide the other hand",
		"long_axe": "long axe (1.2 m haft, a Dane axe's): G for both hands, [ ] to slide the other hand. Import a video now and he holds it in both",
		"dagger": "dagger (30 cm, one hand)"}[k])


## DUAL WIELD (round 33, Nick 10-16): a dagger in each hand; the main one in the right (or the hand it is in now),
## the off-hand one in the other. Mirror swaps what the hands hold
func _two_daggers() -> void:
	var h := B.wep_hand if B.wep_on and B.wep_hand != "" else "hand_r"
	B.grip = false
	B.set_kind("dagger")
	B.weapon_to_hand(h)
	B.grip = false
	B.wep2_kind = "dagger"
	B.wep2_to_hand(B.twin(h))
	sel = "bat_handle"
	_say("two daggers: one in each hand (30 cm). Mirror pose swaps them: the other hand leads")


# ---------------------------------------------------------------- words

## a plain name for a part: "upperarm_r" -> "right upper arm"
## LEFT AND RIGHT (round 24, GATES EE2, UPGRADES #42): his left red (the floor's X, "his left"), his right blue, the
## middle dark; the joint dots and the selected part's name carry it
const SIDE_L := Color(0.9, 0.3, 0.3)
const SIDE_R := Color(0.3, 0.5, 0.95)
const SIDE_MID := Color(0.15, 0.15, 0.18)


static func side_col(j: String) -> Color:
	return SIDE_L if j.ends_with("_l") else (SIDE_R if j.ends_with("_r") else SIDE_MID)


static func nice(j: String) -> String:
	var names := {"pelvis": "hips", "spine_01": "lower back", "spine_02": "middle back", "spine_03": "chest",
		"neck_01": "neck", "head": "head", "clavicle": "shoulder", "upperarm": "upper arm", "lowerarm": "elbow / forearm",
		"hand": "wrist / hand", "thigh": "hip joint / thigh", "calf": "knee / shin", "foot": "ankle / foot", "ball": "toes",
		"bat_handle": "bat (handle)", "bat_barrel": "bat (barrel)"}
	if names.has(j):
		return names[j]
	var side := ""
	var base := j
	if j.ends_with("_l") or j.ends_with("_r"):
		side = "left " if j.ends_with("_l") else "right "
		base = j.substr(0, j.length() - 2)
	for f in ["thumb", "index", "middle", "ring", "pinky"]:
		if base.begins_with(f + "_"):
			var k := int(base.substr(base.length() - 1))
			return side + f + " finger, " + ["", "base", "middle", "tip"][k] + " joint"
	return side + names.get(base, base)


func _angles_words(j: String, v: Vector3) -> String:
	var out := []
	var L: Dictionary = B.lim[j]
	for k in 3:
		var key: String = ["bend", "side", "twist"][k]
		var r: Vector2 = L[key]
		if r.y - r.x > 0.5:
			out.append("%s %.0f°" % [["swing", "raise/tilt", "roll"][k], v[k]])
	return "   ".join(out)


func _how(j: String) -> String:
	if j in Body.WEAPON:
		return ""
	if j == "pelvis":
		return "Drag: tip the whole body.   Shift+drag: turn it.   Ctrl+drag: move it.   (or the sliders)"
	if j in ["hand_r", "hand_l"]:
		return "Drag: the whole arm follows the wrist.   Alt+drag: bend only the wrist.   Shift+drag: roll the hand."
	if j in ["foot_r", "foot_l"]:
		return "Drag: the whole leg follows the ankle.   Alt+drag: bend only the ankle.   Shift+drag: roll the foot."
	if j in Body.FINGERS:
		return "Drag: curl this finger joint.   Use the buttons below for the whole hand (open / grip / fist)."
	return "Drag: rotate it (its far end follows the mouse).   Shift+drag: roll it about its own length."


## FEEDBACK YOU CAN SEE (round 24, GATES EE3, UPGRADES #41): Ctrl+Z / Ctrl+Y show a toast over the view naming the
## step, gone after TOAST_T (a new one replaces it); a Fix flashes the cards it changed, fading back over FLASH_T
const TOAST_T := 1.6
const FLASH_T := 0.7
const FLASH_COL := Color(1.7, 1.5, 0.75)
var ui_toast: Label
var _toast_gen := 0


func _toast(t: String) -> void:
	if ui_root == null:
		return
	if ui_toast == null:
		ui_toast = Label.new()
		ui_toast.name = "toast"
		ui_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui_toast.add_theme_font_size_override("font_size", 18)
		ui_toast.add_theme_color_override("font_color", Tok.c("say"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Tok.c("say_bg")
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(10)
		ui_toast.add_theme_stylebox_override("normal", sb)
		ui_root.add_child(ui_toast)
	ui_toast.text = t
	ui_toast.visible = true
	ui_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	ui_toast.position.y = 96
	_toast_gen += 1
	var g := _toast_gen
	get_tree().create_timer(TOAST_T).timeout.connect(func():
		if g == _toast_gen and is_instance_valid(ui_toast):
			ui_toast.visible = false)


func _flash_cards(idx: Array) -> void:
	for i in idx:
		var pc := ui_cards.get_node_or_null("card_%d" % (i + 1)) as Control
		if pc == null:
			continue
		pc.modulate = FLASH_COL
		pc.create_tween().tween_property(pc, "modulate", Color.WHITE, FLASH_T)


func _say(t: String) -> void:
	if WhyWrong.is_problem(t):   # WHAT WENT WRONG? keeps the last refusal with its command, part and frame
		_why_last = {"text": t, "cmd": _why_cmd if _why_cmd != "" else "a key press", "part": nice(sel),
			"frame": roundi(playhead * float(S.fps)), "at": playhead}
	if ui_status != null:
		ui_status.text = t
		ui_status.visible = hints_on or t != ""
		_strip_fit()
	# UNDO HISTORY (round 11, #75): the first thing said after a step is pushed names it ("ROTATING the right upper
	# arm", "card 12: the right foot planted"...); its first clause, without the numbers that follow
	if not undo.is_empty() and not undo[-1].has("name") and not t.begins_with("undone") and not t.begins_with("redone"):
		undo[-1]["name"] = step_name(t)
		_tree.set_name(_tree.cur, step_name(t))   # the live step's node (the tree names what the lists name)
		_undo_tips()
		_history_rows()


## WHAT WENT WRONG? (ROADMAP 43): the panel opens on the last refusal (or says nothing went wrong yet)
func _why_toggle() -> void:
	if ui_why.visible:
		ui_why.visible = false
		return
	_why_show()


func _why_show() -> void:
	for c in ui_why_box.get_children():
		ui_why_box.remove_child(c)
		c.queue_free()
	ui_why.visible = true
	ui_why_box.add_child(_label("WHAT WENT WRONG?", 22, "heading"))
	if _why_last.is_empty():
		ui_why_box.add_child(_label("Nothing went wrong yet.  When a command refuses (it says 'pick a part first', 'needs two cards', 'NOT PLACED'...), this panel says what you tried, why it did not work, and the one next step.", 16, "text", true))
		ui_why_box.add_child(_button("Close", func(): ui_why.visible = false))
		_say_plain("Nothing went wrong yet")
		return
	var ex := WhyWrong.explain(String(_why_last["text"]))
	ui_why_box.add_child(_label("You tried:  %s" % _why_last["cmd"], 16, "text", true))
	ui_why_box.add_child(_label("Picked: %s, at frame %d (%s)" % [_why_last["part"], _why_last["frame"], Units.time(float(_why_last["at"]), S.fps)], 15, "text:0.7", true))
	ui_why_box.add_child(_label("The app said:  \"%s\"" % _why_last["text"], 15, "text:0.7", true))
	ui_why_box.add_child(_label("Why:  %s" % ex["why"], 16, "text", true))
	ui_why_box.add_child(_button("Next: %s" % ex["step"], _why_step.bind(ex)))
	ui_why_box.add_child(_button("Close", func(): ui_why.visible = false))


## the one next step: runs its registry command where there is one, else puts its words on the status line
func _why_step(ex: Dictionary) -> void:
	ui_why.visible = false
	var cmd: String = ex["cmd"]
	for c in ui_cmd.commands:
		if cmd != "" and c["name"] == cmd:
			_step_hint = cmd
			_why_cmd = cmd
			(c["run"] as Callable).call()
			return
	_say_plain("next: %s" % ex["step"])


## ROADMAP 45: the Undo and Redo buttons say what they will take back: "Undo: Drag left hand", "Redo: Retime: 3 cards"
func _undo_tips() -> void:
	if ui_undo_btn == null or ui_redo_btn == null:
		return
	ui_undo_btn.tooltip_text = ("Undo: " + _step_label(undo[-1])) if not undo.is_empty() else "Undo (Ctrl+Z)\nnothing to undo yet"
	ui_redo_btn.tooltip_text = ("Redo: " + _step_label(redo[-1])) if not redo.is_empty() else "Redo (Ctrl+Y)\nnothing to redo yet"


## what a step is called: what was said about it, else what was pressed, else "change"
static func _step_label(u: Dictionary) -> String:
	var n := String(u.get("name", u.get("hint", "change")))
	return n.left(1).to_upper() + n.substr(1)


## a status line -> a short step name: up to the first double space / "(" / ".  ", at most 48 characters
static func step_name(t: String) -> String:
	var n := t.strip_edges()
	for cut in ["  ", " (", ".  ", "   ["]:
		var at := n.find(cut)
		if at > 0:
			n = n.left(at)
	n = n.rstrip(".:")
	return (n.left(46) + "..") if n.length() > 48 else n


func _toggle_history() -> void:
	ui_hist.visible = not ui_hist.visible
	_history_rows()


## the History panel: every step of the tree (ROADMAP 15), newest first. A branch is indented under the step it left;
## the live step is marked "> "; a step off the current branch is dimmed. A row = jump to that state (not an undo step)
func _history_rows() -> void:
	if ui_hist == null or not ui_hist.visible:
		return
	_tree_sync()
	for c in ui_hist_list.get_children():
		ui_hist_list.remove_child(c)
		c.queue_free()
	var rows := _tree.listing()
	var total := rows.size()
	if rows.size() > HIST_SHOWN:   # ROADMAP 45: the newest HIST_SHOWN steps (Ctrl+Z reaches the older ones)
		rows = rows.slice(0, HIST_SHOWN)
	var head := HBoxContainer.new()
	ui_hist_list.add_child(head)
	var title := _label("HISTORY  -  %s" % ("last %d of %d steps" % [rows.size(), total] if total > HIST_SHOWN else "%d step%s" % [total, "" if total == 1 else "s"]), 16, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Close", _toggle_history))
	var on_path := {}
	for id in _tree.path():
		on_path[id] = true
	for r in rows:
		var id: int = r["id"]
		var pad := ""
		for _i in int(r["col"]):
			pad += "   "   # em spaces: a branch is visibly indented (four ASCII spaces are a few pixels)
		var b := _button(pad + ("> " if id == _tree.cur else "   ") + _step_label(_tree.node(id)) + "   " + String(_tree.node(id)["time"]), _tree_go.bind(id))
		b.name = "step_%d" % id   # U2: the step it goes to
		if not on_path.has(id) and not _tree.forward().has(id):
			b.modulate.a = 0.55   # a branch off the current one
		_hist_row(b)
	if rows.is_empty():
		ui_hist_list.add_child(_label("nothing yet: every change you make shows up here", 13, "text:0.6", true))
	(ui_hist.get_child(0) as ScrollContainer).custom_minimum_size.y = clampf(70.0 + 40.0 * rows.size(), 110.0, 420.0)
	ui_hist.reset_size()


## a history row: a fixed width, a long name cut with "..." (the full name in its tooltip)
func _hist_row(b: Button) -> void:
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size.x = 260
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = b.text.strip_edges()
	ui_hist_list.add_child(b)


## go to the state with `n` steps done, along the current branch (the steps back, then the steps forward)
func _history_go(n: int) -> void:
	_tree_sync()
	var full := _tree.path() + _tree.forward()
	if n >= 0 and n < full.size():
		_tree_go(full[n])


# ---------------------------------------------------------------- ui building

func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 16
	var box := func(col: Color, r := 6, m := 6) -> StyleBoxFlat:
		var b := StyleBoxFlat.new()
		b.bg_color = col
		b.set_corner_radius_all(r)
		b.set_content_margin_all(m)
		return b
	th.set_stylebox("panel", "PanelContainer", box.call(Tok.c("panel"), 8, 10))
	# the top bar: the panel's colour with thin margins, so an icon-over-label button fits in TOP_H (round 9)
	th.set_type_variation("TopBar", "PanelContainer")
	var bar: StyleBoxFlat = box.call(Tok.c("panel"), 0, 0)
	bar.content_margin_left = 10
	bar.content_margin_right = 10
	bar.content_margin_bottom = 2
	th.set_stylebox("panel", "TopBar", bar)
	# the scene panel (RR4): thin top / bottom margins, so the folded strip is one 44-px row
	th.set_type_variation("BottomBar", "PanelContainer")
	var bb: StyleBoxFlat = box.call(Tok.c("panel"), 8, 8)
	bb.content_margin_top = 4
	bb.content_margin_bottom = 4
	th.set_stylebox("panel", "BottomBar", bb)
	# a ribbon button: the button's look with thin top/bottom margins (icon over label is two rows tall)
	# round 36 (RR1): a FLAT square, lit only on hover / when on (Fusion's toolbar has no boxes at rest)
	th.set_type_variation("Ribbon", "Button")
	for st in [["normal", "panel"], ["hover", "btn_hover"], ["pressed", "accent"], ["hover_pressed", "accent"], ["disabled", "panel"]]:
		var rb: StyleBoxFlat = box.call(Tok.c(st[1]), 4, 3)
		th.set_stylebox(st[0], "Ribbon", rb)
	# a tab: small words, no box; the open one underlined in the accent
	th.set_type_variation("RibbonTab", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var tb2 := StyleBoxFlat.new()
		tb2.bg_color = Tok.c("btn_hover") if st == "hover" else Tok.c("panel")
		tb2.set_content_margin_all(4)
		tb2.content_margin_left = 10
		tb2.content_margin_right = 10
		if st.contains("pressed"):
			tb2.border_color = Tok.c("accent")
			tb2.border_width_bottom = 2
		th.set_stylebox(st, "RibbonTab", tb2)
	th.set_font_size("font_size", "RibbonTab", 12)
	th.set_color("font_color", "RibbonTab", Tok.of("text:0.6"))
	th.set_color("font_hover_color", "RibbonTab", Tok.c("text"))
	th.set_color("font_pressed_color", "RibbonTab", Tok.c("heading"))
	th.set_color("font_hover_pressed_color", "RibbonTab", Tok.c("heading"))
	# a section's header in the inspector (RR2): a hairline above, the words, no box
	th.set_type_variation("Section", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sx := StyleBoxFlat.new()
		sx.bg_color = Tok.c("btn_hover") if st.begins_with("hover") else Tok.c("panel")
		sx.border_color = Tok.c("btn")
		sx.border_width_top = 1
		sx.content_margin_top = 3
		sx.content_margin_bottom = 2
		sx.content_margin_left = 4
		th.set_stylebox(st, "Section", sx)
	th.set_color("font_color", "Section", Tok.of("text:0.6"))
	th.set_color("font_hover_color", "Section", Tok.c("text"))
	# a group's caption: tiny grey words under the group, no box
	th.set_type_variation("RibbonCap", "MenuButton")
	var capbox := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		th.set_stylebox(st, "RibbonCap", capbox)
	th.set_font_size("font_size", "RibbonCap", 10)
	th.set_color("font_color", "RibbonCap", Tok.of("text:0.5"))
	th.set_color("font_hover_color", "RibbonCap", Tok.c("text"))
	th.set_stylebox("normal", "Button", box.call(Tok.c("btn")))
	th.set_stylebox("hover", "Button", box.call(Tok.c("btn_hover")))
	th.set_stylebox("pressed", "Button", box.call(Tok.c("accent")))
	# THE FOCUS RING (round 14, U4): a 2 px "focus" token border just outside the control, no fill (it only shows in
	# keyboard mode: F6; the mouse never gives a control focus). Drawn over each control's own box
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Tok.c("focus")
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(7)
	ring.set_expand_margin_all(4)   # 2 px of the panel between the control and the ring: it reads against the panel on both sides, whatever the control's own fill (a pressed button is the accent)
	for t in ["Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "HSlider", "VSlider"]:
		th.set_stylebox("focus", t, ring)
	for t in ["Button", "MenuButton"]:   # the ribbon's icons are white: the palette tints them
		th.set_color("icon_normal_color", t, Tok.c("btn_text"))
		th.set_color("icon_hover_color", t, Tok.c("btn_text"))
		th.set_color("icon_focus_color", t, Tok.c("btn_text"))
		th.set_color("icon_pressed_color", t, Tok.c("on_accent"))
		th.set_color("icon_hover_pressed_color", t, Tok.c("on_accent"))
	if not Tok.dark:
		# LIGHT (round 9): Godot's own look is dark, so every control that draws its own box or text gets the palette.
		# Dark keeps Godot's look for these (nothing Nick knows changes)
		var tx := Tok.c("text")
		for t in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
			th.set_color("font_color", t, tx)
			th.set_color("font_hover_color", t, tx)
			th.set_color("font_focus_color", t, tx)
			th.set_color("font_pressed_color", t, Tok.c("on_accent"))
			th.set_color("font_hover_pressed_color", t, Tok.c("on_accent"))
			th.set_color("font_disabled_color", t, Tok.dim(0.4))
		for t in ["CheckBox", "CheckButton"]:
			th.set_color("font_pressed_color", t, tx)
			th.set_color("font_hover_pressed_color", t, tx)
			th.set_stylebox("normal", t, StyleBoxEmpty.new())
			th.set_stylebox("pressed", t, StyleBoxEmpty.new())
			th.set_stylebox("hover", t, box.call(Tok.c("btn_hover")))
		var edge := Tok.c("btn_hover").darkened(0.15)
		var field: StyleBoxFlat = box.call(Tok.c("field"), 4, 5)
		field.content_margin_top = 2   # + the 1 px border = Godot's own field height: a card is as tall in light as in dark
		field.content_margin_bottom = 2
		field.border_color = edge
		field.set_border_width_all(1)
		for t in ["LineEdit", "SpinBox"]:
			th.set_stylebox("normal", t, field)
			th.set_color("font_color", t, tx)
			th.set_color("font_placeholder_color", t, Tok.dim(0.45))
			th.set_color("caret_color", t, tx)
		for t in ["ItemList", "Tree"]:
			th.set_stylebox("panel", t, field)
			th.set_stylebox("focus", t, StyleBoxEmpty.new())
			th.set_color("font_color", t, tx)
			th.set_color("font_selected_color", t, Tok.c("on_accent"))
			th.set_color("font_hovered_color", t, tx)
			th.set_stylebox("selected", t, box.call(Tok.c("accent"), 3, 2))
			th.set_stylebox("selected_focus", t, box.call(Tok.c("accent"), 3, 2))
			th.set_stylebox("hovered", t, box.call(Tok.c("btn_hover"), 3, 2))
			th.set_color("guide_color", t, Color(tx, 0.1))
			th.set_color("relationship_line_color", t, Color(tx, 0.25))
		th.set_color("font_color", "ItemList", tx)
		th.set_stylebox("panel", "TabContainer", box.call(Tok.c("panel"), 6, 6))
		th.set_stylebox("tab_selected", "TabContainer", box.call(Tok.c("panel"), 4, 6))
		th.set_stylebox("tab_unselected", "TabContainer", box.call(Tok.c("btn"), 4, 6))
		th.set_stylebox("tab_hovered", "TabContainer", box.call(Tok.c("btn_hover"), 4, 6))
		th.set_color("font_selected_color", "TabContainer", tx)
		th.set_color("font_unselected_color", "TabContainer", Tok.dim(0.6))
		th.set_color("font_hovered_color", "TabContainer", tx)
		th.set_stylebox("panel", "PopupMenu", box.call(Tok.c("float"), 6, 6))
		th.set_color("font_color", "PopupMenu", tx)
		th.set_color("font_hover_color", "PopupMenu", tx)
		th.set_stylebox("hover", "PopupMenu", box.call(Tok.c("btn_hover"), 3, 2))
		th.set_stylebox("panel", "TooltipPanel", box.call(Tok.c("float"), 4, 6))
		th.set_color("font_color", "TooltipLabel", tx)
		th.set_stylebox("slider", "HSlider", box.call(Tok.c("btn_hover").darkened(0.1), 3, 2))
		th.set_stylebox("grabber_area", "HSlider", box.call(Tok.c("accent"), 3, 2))
		th.set_stylebox("grabber_area_highlight", "HSlider", box.call(Tok.c("accent"), 3, 2))
	return th


## LIGHT / DARK (round 9, GATES P3): every token at once; remembered in user://poser.cfg. A view setting: no undo step
## FIRST-RUN TOUR (round 12, #71): five steps in a small card under the top bar. Each moves on when the user DOES it
## (watched every frame, no Next button): click a part, drag it, clip two cards, play, check. Skip ends it; finishing
## or skipping saves "tour done", so it never shows again. A test or --tour starts it on purpose
const TOUR := [
	["Click a body part", "Click any part of the mannequin: an arm, a leg, the head. Its name and angles show on the right."],
	["Drag it", "Drag on the part you picked: it turns. (Ctrl+Z takes any change back.)"],
	["Clip two moments", "Press Enter (CLIP this pose) to keep this pose as a card. Change the pose a little and press Enter again."],
	["Play", "Press Space (or Play): the body moves from card to card on its own."],
	["Check", "Press Check (CHECK tab): it grades the motion against real recorded humans and says what looks off."],
]
var tour_step := -1          # -1 = no tour
var _tour_at := {}           # what the step started from (to see the user do it)
var _clicked_part := false   # set by a click on the body; the tour reads and clears it
var _tour_inputs := 0        # the user's presses so far (a click, a key, a button): a tour step needs one of its own
var ui_tour: PanelContainer


## not done or skipped yet (the settings remember it)
func _tour_due() -> bool:
	var cf := ConfigFile.new()
	cf.load(settings)
	return not cf.get_value("look", "tour_done", false)


## ONE INTRO AT A TIME (round 35a, GATES QQ2; QQ1 recorded the tour card and "Unsaved work found" both appearing at
## 0.40 s, the dialog modal over the tour's Skip): the recover offer (deferred after this) goes first; the tour starts
## once it is answered, or at once when there is nothing to recover
func _tour_after_recover() -> void:
	await get_tree().process_frame
	while ui_recover != null and ui_recover.visible:
		await ui_recover.visibility_changed
	if is_inside_tree():
		_tour_start()


func _tour_start() -> void:
	if ui_tour == null:
		ui_tour = PanelContainer.new()
		ui_tour.anchor_left = 0.5
		ui_tour.anchor_right = 0.5
		ui_tour.offset_left = -230
		ui_tour.offset_right = 230
		ui_tour.offset_top = TOP_H + 10
		var st := StyleBoxFlat.new()
		st.bg_color = Tok.c("accent")
		st.set_corner_radius_all(8)
		st.set_content_margin_all(12)
		ui_tour.add_theme_stylebox_override("panel", st)
		var v := VBoxContainer.new()
		ui_tour.add_child(v)
		var h := HBoxContainer.new()
		v.add_child(h)
		var t := _label("", 17, "on_accent")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		h.add_child(_button("Skip", _tour_end.bind(true), "end the tour; it won't show again (Help has it all)"))
		var x := _button("x", _tour_end.bind(true), "close the tour (Esc); it won't show again (Help -> First steps tour)")
		x.name = "tour_close"
		h.add_child(x)
		v.add_child(_label("", 14, "on_accent", true))
		ui_root.add_child(ui_tour)
	tour_step = -1
	_tour_go(0)


func _tour_go(k: int) -> void:
	tour_step = k
	if k >= TOUR.size():
		_tour_end(false)
		return
	_clicked_part = false
	_tour_at = {"sel": sel, "body": JSON.stringify(B.state()), "cards": S.cards.size(), "inputs": _tour_inputs}
	var v := ui_tour.get_child(0)
	(v.get_child(0).get_child(0) as Label).text = "Step %d of %d:  %s" % [k + 1, TOUR.size(), TOUR[k][0]]
	(v.get_child(1) as Label).text = TOUR[k][1]
	ui_tour.visible = true


## every frame: has the user done this step?
func _tour_poll() -> void:
	if tour_step < 0:
		return
	var did := false
	match tour_step:
		0: did = sel != _tour_at["sel"] or _clicked_part
		1: did = JSON.stringify(B.state()) != _tour_at["body"] and dragging == ""   # after the drag is let go
		2: did = S.cards.size() >= 2 and S.cards.size() > _tour_at["cards"]
		3: did = playing
		4: did = check_ran
	if did and _tour_inputs > int(_tour_at["inputs"]):   # the user's own doing (QQ2), not a load or a recovery
		_tour_go(tour_step + 1)


func _tour_end(skipped: bool) -> void:
	tour_step = -1
	if ui_tour != null:
		ui_tour.visible = false
	var cf := ConfigFile.new()
	cf.load(settings)
	cf.set_value("look", "tour_done", true)
	cf.save(settings)
	_say("tour skipped: Help (top right) has every key and click" if skipped else "tour done: you can pose, clip, play and check. Help (top right) has the rest")


## UI SIZE (round 11, #84): the window's content scale: every control, font and offset grows together (the layout reads
## the visible rect, which shrinks by the same factor, so nothing is placed for the wrong size). Remembered
## The layout needs 1280 x 720 of room at the chosen size (measured: at less, the rows run off the window), so a size is
## offered only when the window leaves that much: on 1600 x 900, 90 / 100 / 125; 150 needs 1920 x 1080 or more.
## The play row's Check / Polish / Fix (the CHECK tab has them too) hide, last first, when the row would not fit.
const SCALES := [90, 100, 125, 150]
const MIN_ROOM := Vector2(1280, 720)
var ui_scale := 100
var ui_play_extra: Array = []


func scale_fits(pct: int) -> bool:
	return pct <= 100 or Vector2(get_window().size) / (pct / 100.0) >= MIN_ROOM - Vector2(1, 1)


## FIRST-START SCALE (ROADMAP 58): the size a screen gets when the user has not chosen one. Pure, so a test injects
## sizes. want: 150 on a 4K-class screen (2880 px wide, or 140+ dpi), 125 on a HiDPI laptop (110+ dpi), else 100.
## Then the largest SCALES step at or below want that the window leaves room for: the layout's MIN_ROOM, and the whole
## top bar (ribbon_w, in the layout's own px) so no tab's tools run off the right edge. 1366 x 728 gives 100 (the top bar
## needs 751 px).
static func auto_scale(win: Vector2, screen: Vector2, dpi: float, ribbon_w: float) -> int:
	var want := 100
	if screen.x >= 2880.0 or dpi >= 140.0:
		want = 150
	elif dpi >= 110.0:
		want = 125
	var best := 90
	for p in SCALES:   # ascending
		if p <= want and win.x / (p / 100.0) >= maxf(ribbon_w, MIN_ROOM.x) - 1.0 and win.y / (p / 100.0) >= MIN_ROOM.y - 1.0:
			best = p
	return best


## the pick for the window as it is now, and the size it is set to (not saved: a first start only)
func _auto_scale_now() -> void:
	var ribbon_w := ui_top_bar.get_combined_minimum_size().x if ui_top_bar != null else 0.0
	var pick := auto_scale(Vector2(get_window().size), Vector2(DisplayServer.screen_get_size()), DisplayServer.screen_get_dpi(), ribbon_w)
	ui_scale = pick
	get_window().content_scale_factor = pick / 100.0
	_fit_rows.call_deferred()
	_fit_top.call_deferred()


func _fit_rows() -> void:
	if ui_play_row == null:
		return
	for b in ui_play_extra:
		b.visible = true
	var room := get_viewport().get_visible_rect().end.x - 8
	for k in range(ui_play_extra.size() - 1, -1, -1):
		if ui_play_row.get_global_rect().position.x + ui_play_row.get_combined_minimum_size().x <= room:
			break
		ui_play_extra[k].visible = false


## THE TRANSPORT (RR4): the start / the end; the clip before / after the playhead (its arrival)
func _go_end(last: bool) -> void:
	playing = false
	playhead = S.length() if last else 0.0
	_ps().apply(B, playhead)
	_refresh()


func _go_card(dir: int) -> void:
	if S.cards.is_empty():
		return
	var t := S.times()
	var k := -1
	if dir > 0:
		for i in t.size():
			if t[i][1] > playhead + 1e-3:
				k = i
				break
	else:
		for i in range(t.size() - 1, -1, -1):
			if t[i][1] < playhead - 1e-3:
				k = i
				break
	if k < 0:
		k = 0 if dir < 0 else t.size() - 1
	playing = false
	_timeline_pick(k)


func _gear_open() -> void:
	if ui_gear.visible:
		ui_gear.visible = false
		return
	var r := ui_gear_btn.get_global_rect()
	var sz := ui_gear.get_combined_minimum_size()
	ui_gear.position = Vector2(r.end.x - sz.x, r.position.y - sz.y - 6)
	ui_gear.size = sz
	ui_gear.visible = true


func _set_scale(pct: int) -> void:
	if not scale_fits(pct):
		_say("UI size %d %% needs a window of at least %d x %d px (this one is %d x %d px): make the window bigger (maximise it), then choose it again" % [pct, MIN_ROOM.x * pct / 100, MIN_ROOM.y * pct / 100, get_window().size.x, get_window().size.y])
		return
	ui_scale = pct
	scale_auto = false   # the user chose it: remembered, and no longer picked from the screen
	get_window().content_scale_factor = pct / 100.0
	var cf := ConfigFile.new()
	cf.load(settings)
	cf.set_value("look", "scale", pct)
	cf.save(settings)
	_fit_rows.call_deferred()
	_fit_top.call_deferred()
	_say("UI size %d %%" % pct)


## HINTS ON/OFF (round 35a, GATES QQ3): the teaching texts (the welcome line on the yellow strip, the selected part's
## "Drag: rotate it..." line, the Poses and Scene captions) go; what the app SAYS about what you did still shows
const WELCOME := "Click a body part to select it.  Drag it to rotate.  POSES, on the left, has poses to start from."
var hints_on := true
var ui_hint_labels: Array = []


func _set_hints(on: bool, save := true) -> void:
	hints_on = on
	_hints_apply()
	if save:
		var cf := ConfigFile.new()
		cf.load(settings)
		cf.set_value("look", "hints", on)
		cf.save(settings)
		_say_plain("hints on (VIEW > Hints to hide them)" if on else "")


func _hints_apply() -> void:
	for l in ui_hint_labels:
		if not is_instance_valid(l):
			continue
		if (l as Label).has_meta("hint_text"):
			(l as Label).text = l.get_meta("hint_text") if hints_on else ""
		else:
			l.visible = hints_on
	if ui_how != null:
		ui_how.visible = false   # RR2: how to use the part is the title's tooltip, never a line in the box
	if ui_status != null:
		if not hints_on and ui_status.text == WELCOME:
			ui_status.text = ""
		ui_status.visible = hints_on or ui_status.text != ""


## PER-PART ONION (ROADMAP 70): View options > the onion panel. Ghosts of the picked parts only, the frames before and
## after the playhead, the step between them. Remembered in the settings file under [onion]; the tests' own settings file
## is the one read and written there (never poser.cfg).
var onion_pop: PopupPanel
var _onion_ui := {}


func _onion_load() -> void:
	var cf := ConfigFile.new()
	if cf.load(settings) != OK:
		return
	ov.onion_parts_on = bool(cf.get_value("onion", "parts", false))
	ov.onion_before = clampi(int(cf.get_value("onion", "before", 2)), 0, Overlays.ONION_MAX)
	ov.onion_after = clampi(int(cf.get_value("onion", "after", 2)), 0, Overlays.ONION_MAX)
	ov.onion_step = clampi(int(cf.get_value("onion", "step", 1)), 1, Overlays.ONION_STEP_MAX)
	ov.onion_picks = Array(cf.get_value("onion", "picks", []))


func _onion_save() -> void:
	var cf := ConfigFile.new()
	cf.load(settings)
	cf.set_value("onion", "parts", ov.onion_parts_on)
	cf.set_value("onion", "before", ov.onion_before)
	cf.set_value("onion", "after", ov.onion_after)
	cf.set_value("onion", "step", ov.onion_step)
	cf.set_value("onion", "picks", ov.onion_picks)
	cf.save(settings)


func _onion_panel_open() -> void:
	if onion_pop == null:
		onion_pop = PopupPanel.new()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		onion_pop.add_child(v)
		var parts := CheckBox.new()
		parts.text = "Ghosts of the picked parts only (not the whole body)"
		parts.toggled.connect(_onion_set_parts)
		v.add_child(parts)
		_onion_ui["parts"] = parts
		var pick := Button.new()
		pick.pressed.connect(_onion_pick_sel)
		v.add_child(pick)
		_onion_ui["pick"] = pick
		var picks := Label.new()
		v.add_child(picks)
		_onion_ui["picks"] = picks
		for k in [["before", "Frames before", Overlays.ONION_MAX], ["after", "Frames after", Overlays.ONION_MAX], ["step", "Step (frames)", Overlays.ONION_STEP_MAX]]:
			var row := HBoxContainer.new()
			var lb := Label.new()
			lb.text = k[1]
			lb.custom_minimum_size = Vector2(140, 0)
			row.add_child(lb)
			var sp := SpinBox.new()
			sp.min_value = 1 if k[0] == "step" else 0
			sp.max_value = k[2]
			sp.step = 1
			sp.value_changed.connect(func(_x): _onion_frames())
			row.add_child(sp)
			v.add_child(row)
			_onion_ui[k[0]] = sp
		var legend := Label.new()
		legend.text = "past = warm, future = cool. The farther from the playhead, the fainter."
		legend.modulate = Tok.dim(0.6)
		v.add_child(legend)
		add_child(onion_pop)
	onion_pop.theme = ui_root.theme
	_onion_panel_sync()
	onion_pop.popup_centered(Vector2i(380, 0))


func _onion_panel_sync() -> void:
	if onion_pop == null:
		return
	(_onion_ui["parts"] as CheckBox).set_pressed_no_signal(ov.onion_parts_on)
	(_onion_ui["pick"] as Button).text = ("Unpick %s" if ov.onion_picks.has(sel) else "Pick the selected part (%s)") % nice(sel)
	(_onion_ui["picks"] as Label).text = "Picked: " + (", ".join(ov.onion_picks.map(func(p): return nice(p))) if not ov.onion_picks.is_empty() else "none yet")
	(_onion_ui["before"] as SpinBox).set_value_no_signal(ov.onion_before)
	(_onion_ui["after"] as SpinBox).set_value_no_signal(ov.onion_after)
	(_onion_ui["step"] as SpinBox).set_value_no_signal(ov.onion_step)


func _onion_set_parts(on: bool) -> void:
	ov.onion_parts_on = on
	if on:
		ov.onion_on = true
		if ov.onion_picks.is_empty():
			_say("pick a part first: select it, then View options > Pick the selected part")
	_onion_save()
	_onion_panel_sync()
	_refresh()
	if not on:
		_say("onion skin: the whole body again")


func _onion_pick_sel() -> void:
	if ov.onion_picks.has(sel):
		ov.onion_picks.erase(sel)
	else:
		ov.onion_picks.append(sel)
	ov.onion_on = ov.onion_on or ov.onion_parts_on
	_onion_save()
	_onion_panel_sync()
	_refresh()
	_say("onion skin shows: %s" % (", ".join(ov.onion_picks.map(func(p): return nice(p))) if not ov.onion_picks.is_empty() else "no part (pick one)"))


func _onion_frames() -> void:
	if onion_pop == null:
		return
	ov.onion_before = int((_onion_ui["before"] as SpinBox).value)
	ov.onion_after = int((_onion_ui["after"] as SpinBox).value)
	ov.onion_step = int((_onion_ui["step"] as SpinBox).value)
	_onion_save()
	_refresh()


## THE THEME PREFERENCE (ROADMAP 58): "system" (follows Windows' dark mode), "light" or "dark". Saved as look/theme; the
## old look/light flag is kept in step so a build without this still reads the same palette
var theme_pref := "system"
var scale_auto := false      # no size chosen yet: _auto_scale_now picks it from the screen
var sys_dark_probe := Callable()   # a test stubs the system's dark flag here; empty = DisplayServer.is_dark_mode()


func _system_dark() -> bool:
	return bool(sys_dark_probe.call()) if sys_dark_probe.is_valid() else DisplayServer.is_dark_mode()


## the palette the current preference asks for: true = dark
func _theme_wanted() -> bool:
	match theme_pref:
		"light":
			return false
		"dark":
			return true
	return _system_dark()


func _save_theme(extra := {}) -> void:
	var cf := ConfigFile.new()
	cf.load(settings)
	cf.set_value("look", "theme", theme_pref)
	cf.set_value("look", "light", not Tok.dark)
	for k in extra:
		cf.set_value("look", k, extra[k])
	cf.save(settings)


func _set_light(on: bool) -> void:
	theme_pref = "light" if on else "dark"
	Tok.set_dark(not on)
	_retheme()
	_save_theme()
	_say("light theme (VIEW > Light again for dark)" if on else "dark theme")


## VIEW > Follow system: on = the palette is Windows' (dark or light, re-read when the window gets focus); off = the
## palette it has now, kept as an explicit choice
func _set_theme_system(on: bool) -> void:
	theme_pref = "system" if on else ("dark" if Tok.dark else "light")
	if on and _theme_wanted() != Tok.dark:
		Tok.set_dark(_theme_wanted())
		_retheme()
	_save_theme()
	_say(("theme follows Windows (%s now)" % ("dark" if Tok.dark else "light")) if on else "theme fixed to %s (VIEW > Follow system to follow Windows again)" % theme_pref)


## a window that gets focus again picks up a change of Windows' dark mode, while the preference is "system"
## (called from the one _notification, next to the close request)
func _focus_theme() -> void:
	if theme_pref == "system" and ui_root != null and _theme_wanted() != Tok.dark:
		Tok.set_dark(_theme_wanted())
		_retheme()


## everything built with the old palette takes the new one
func _retheme() -> void:
	ui_root.theme = _theme()
	ui_tinted = ui_tinted.filter(func(x): return is_instance_valid(x[0]))
	for x in ui_tinted:
		(x[0] as Label).add_theme_color_override("font_color", Tok.of(x[1]))
	for t in ui_ribbon_tabs:
		(ui_ribbon_tabs[t] as Button).add_theme_color_override("font_pressed_color", Tok.c("heading") if Tok.dark else Tok.c("on_accent"))
	ui_say_box.bg_color = Tok.c("say_bg")
	_strip_fit.call_deferred()   # RR5: the line's colour is chosen by what it says (after the tint loop)
	if ui_bar_box != null:
		ui_bar_box.bg_color = Tok.c("panel")
	for r in ui_rails.values():
		(r.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Tok.c("panel")
	ui_find_box.bg_color = Tok.c("float")
	if ui_vdiff != null and ui_vdiff.has_theme_stylebox_override("panel"):
		(ui_vdiff.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Tok.c("float")
	world_env.background_color = Tok.c("world")
	floor_mat.albedo_color = Tok.c("floor")
	_grid()
	_rebuild_cards()
	if ui_find.visible and S.cards.size() >= 2:
		_check(findings)
	if ui_browser != null:
		ui_browser.recolor()   # the folder rows carry the heading colour (in place: the folds and scroll stay, AA2)
		ui_browser.refresh()
	for w in [ui_timeline, ui_graph, ui_cube, ui_ring]:
		if w != null:
			w.queue_redraw()
	_refresh()


## col: a Tok token ("text", "heading", "text:0.6" ...) or a Color. Token labels are remembered: a theme switch
## re-tints them (round 9)
func _label(t: String, size := 16, col: Variant = "text", wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	if col is String:   # the FONT's colour: modulate would also tint a label's own box (the status line's went brown)
		l.add_theme_color_override("font_color", Tok.of(col))
		ui_tinted.append([l, col])
	else:
		l.modulate = col
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(120, 0)
	return l


## the ribbon's icons (GATES P5): a tool button's label -> its drawing in scripts/icons.gd
const ICON_OF := {"Reset body": "reset", "Snap to floor": "floor", "Arms 25°": "arms", "Mirror pose (Shift+M)": "mirror", "Symmetry": "symmetry", "Collision (C)": "collision",
	"Trail (T)": "trail", "Onion (O)": "onion", "Weight paint": "weights", "Spacing (Shift+O)": "spacing", "Speed graph (Y)": "graph", "Balance (Shift+B)": "balance", "Stepped": "stepped",
	"Moving holds": "holds", "Airborne": "air", "Auto-key (Ctrl+K)": "autokey", "Animator tools": "tools", "Check": "check", "Polish": "polish", "Fix moves through the body": "fix",
	"Dummy (H)": "dummy", "Front (1)": "front", "His right (2)": "right", "Top (3)": "top", "Back (4)": "back", "His left (5)": "left",
	"Big view (Tab)": "big", "Light": "light", "Follow system": "auto_theme", "Hints": "hints", "Export...": "export", "Save version": "version", "UI size": "size", "CLIP this pose (Enter)": "clip", "Undo (Ctrl+Z)": "undo", "Redo (Ctrl+Y)": "redo", "History": "history", "Search (S)": "search", "? Help": "help",
	"Add prop": "prop", "Import model": "import", "From video": "video", "Ask AI": "ai", "Turn left": "turn_l", "Turn right": "turn_r", "Delete prop": "delete",
	"Sit here": "sit", "Step up": "step", "Pick up": "take", "Put down": "put", "Pose library": "poselib", "Easy mode": "easy", "View options": "gear", "Corrective shapes": "corrective",
	"Sketch line of action": "loa_sketch", "Line of action": "loa", "Mirror scene": "mirror_scene", "Mirror in place": "mirror_inplace", "Frame data": "fd", "Frame boxes": "fd_boxes", "Frame rate": "fd_rate", "Export frame data (json)...": "export_fd", "What went wrong?": "whywrong"}


## icon over a small label, Fusion's ribbon look; the theme tints the (white) icon
## HOVER HINTS (round 11, #85): every ribbon / top-bar button says what it does in the status line while the mouse is
## on it. The words: its tooltip; else the registry command it is (same name, its shortcut in "(X)", or a name that
## starts with it). Leaving puts the normal bar back (bar_text reads _hover_hint first)
var _hover_hint := ""
var tips: TipVideo


## THE SCENE IN THE STRIP (round 36, RR1): its name, its clips and length; the dot while it has unsaved changes
var _doc_t := 0   # the last time the strip was worked out (the dot compares the cards as JSON: not every drag frame)


func _doc_line(force := false) -> void:
	if ui_doc == null or (not force and Time.get_ticks_msec() - _doc_t < 400):
		return
	_doc_t = Time.get_ticks_msec()
	var nm: String = S.name if S.name != "" else "untitled"
	ui_doc.text = "%s   ·  %d clips  ·  %s" % [nm, S.cards.size(), Units.time(_ps().length(), S.fps)] if S.cards.size() > 0 else "%s   ·  no clips yet" % nm
	ui_doc_dot.visible = _unsaved()


## a button's name: its text, or for an icon-only one (round 36) the label it kept
func label_of(b: Node) -> String:
	return String(b.get_meta("label", b.get("text") if b.get("text") != null else ""))


func _hover_hints() -> void:
	for b in ui_root.find_children("*", "BaseButton", true, false):
		if not (b is Button) or not ICON_OF.has(label_of(b)):
			continue
		var t: String = label_of(b)
		if b.tooltip_text == "":
			var key := t.get_slice("(", 1).trim_suffix(")") if t.contains("(") else "~"
			for c in ui_cmd.commands:
				if c["name"] == t or c["keys"] == key or (c["name"] as String).begins_with(t):
					b.tooltip_text = c["desc"]
					break
		# the tooltip leads with the name (an icon has no words); the hover line keeps "name:  what it does"
		if b.get_meta("label", "") != "" and not b.tooltip_text.begins_with(t):
			b.tooltip_text = t + ("\n" + b.tooltip_text if b.tooltip_text != "" else "")
		b.mouse_entered.connect(func(): _hover_hint = "%s:  %s" % [t, b.tooltip_text.trim_prefix(t + "\n").trim_prefix(t)])
		b.mouse_exited.connect(func(): _hover_hint = "")


## ICONS ONLY (round 36, GATES RR1): the words go to the label (tests and the caption menus find it there), the
## tooltip and the hover line; the button is the icon on a flat square that lights on hover / when on
func _iconise(b: Node) -> void:
	if not (b is Button) or not ICON_OF.has(label_of(b)):
		return
	var t := label_of(b)
	b.set_meta("label", t)
	b.icon = Icons.tex(ICON_OF[t])
	b.text = ""
	b.theme_type_variation = "Ribbon"
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(32, TOOLS_H)
	if b.name.begins_with("@"):
		b.name = "b_" + "_".join(t.to_lower().replace("(", " ").replace(")", " ").replace(".", " ").replace("?", "help").split(" ", false))


## DISABLED SAYS WHY (round 22, GATES CC3, UPGRADES #46): a control greyed out keeps its own tooltip and adds the
## reason and what to do after GREY_TAG (one place, so every greyed control reads the same way); why "" = enabled
const GREY_TAG := "
NOT NOW: "


func _grey(c: Control, why: String) -> void:
	var base: String = c.tooltip_text.get_slice(GREY_TAG, 0)
	c.set("disabled", why != "")
	if c is Slider:   # a slider has no `disabled`: editable=false greys it (the ease slider on each card)
		(c as Slider).editable = why == ""
		c.modulate.a = 1.0 if why == "" else 0.5
	c.tooltip_text = base + (GREY_TAG + why if why != "" else "")


func _button(t: String, f: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(func(): _step_hint = t; _why_cmd = t; _tour_inputs += 1)   # first: an undo step pushed by f is named after the button
	b.pressed.connect(f)
	return b


func _row(parent: Control, items: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for it in items:
		h.add_child(it)
		if it is Button:
			(it as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			(it as Button).clip_text = true   # a row never pushes the panel wider than the screen
	parent.add_child(h)
	return h


## ONE TYPE SCALE (round 25, GATES FF3, UPGRADES #40): the properties panel has two sizes, PROP_BIG (the part's name)
## and PROP_TXT (everything else), one weight; a value row reads label dim, value bright, its hint dim under them
const PROP_BIG := 15   # round 36 (RR2): the inspector's two sizes, Fusion-small (round 25: 22 / 15)
const PROP_TXT := 13


## a value row in parent: [name (dim), value (bright)] then the hint (dim, hidden when empty). Returns the three labels
func _prop_row(parent: Control) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var n := _label("", PROP_TXT, "text:0.6")
	var v := _label("", PROP_TXT, "text")
	h.add_child(n)
	h.add_child(v)
	parent.add_child(h)
	var hint := _label("", PROP_TXT, "text:0.6", true)
	parent.add_child(hint)
	return [n, v, hint]


func _set_prop(r: Array, name: String, value: String, hint := "") -> void:
	(r[0] as Label).text = name
	(r[1] as Label).text = value
	(r[2] as Label).text = hint
	(r[2] as Label).visible = false   # RR2: the words are the row's tooltip
	(r[0] as Label).tooltip_text = hint


## A FOLDED SECTION (round 36, RR2): a thin rule, a header that opens / folds it (▸ / ▾), the rows under it; folded at
## the start. Returns the box its rows go in. A weapon picked opens WEAPON (what the box is about then)
var ui_secs := {}   # "HANDS" / "WEAPON" / "NUMBERS" -> [header button, body]


func _section(parent: Control, t: String) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.name = "sec_body_" + t.to_lower()
	body.add_theme_constant_override("separation", 4)
	body.visible = false
	var hb := Button.new()
	hb.name = "sec_" + t.to_lower()
	hb.theme_type_variation = "Section"
	hb.focus_mode = Control.FOCUS_NONE
	hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hb.tooltip_text = "open / fold the %s rows" % t.to_lower()
	hb.pressed.connect(func(): _sec_open(t, not body.visible))
	parent.add_child(hb)
	parent.add_child(body)
	ui_secs[t] = [hb, body]
	_sec_open(t, false)
	return body


func _sec_open(t: String, on: bool) -> void:
	var hb: Button = ui_secs[t][0]
	(ui_secs[t][1] as Control).visible = on
	hb.text = ("\u25be  " if on else "\u25b8  ") + t
	_insp_fit.call_deferred()


## an icon button with no words: the words stay its label and lead its tooltip (as the ribbon's, RR1)
func _icon_only(b: Button, icon: String, sz: Vector2) -> void:
	b.set_meta("label", b.text)
	b.tooltip_text = b.text + ("\n" + b.tooltip_text if b.tooltip_text != "" else "")
	b.text = ""
	b.icon = Icons.tex(icon)
	b.theme_type_variation = "Ribbon"
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.custom_minimum_size = sz


## a button showing short words: its full name stays its label and leads its tooltip
func _short(b: Button, words: String) -> Button:
	b.set_meta("label", b.text)
	b.tooltip_text = b.text + ("
" + b.tooltip_text if b.tooltip_text != "" else "")
	b.text = words
	return b


## a button's label changes (the lock's Lock / Unlock): the words, the tooltip's lead
func _set_label(b: Button, t: String) -> void:
	var old := label_of(b)
	b.set_meta("label", t)
	b.tooltip_text = t + b.tooltip_text.trim_prefix(old)


## the slider on its name's line, between the name and the number (RR2: one line per angle)
func _row_slider(l: Array, s: HSlider) -> void:
	var h := (l[0] as Label).get_parent() as HBoxContainer
	h.add_theme_constant_override("separation", 6)
	(l[0] as Label).custom_minimum_size.x = 80
	(l[0] as Label).size_flags_horizontal = Control.SIZE_FILL   # the slider takes the free width, not the words
	(l[1] as Label).size_flags_horizontal = Control.SIZE_FILL
	(l[0] as Label).mouse_filter = Control.MOUSE_FILTER_PASS
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(60, 18)
	h.add_child(s)
	h.move_child(s, 1)
	(l[1] as Label).custom_minimum_size.x = 50
	(l[1] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## THE BOX FITS WHAT IT SHOWS (RR2): its height is its rows' (folded sections are one line each), up to the room above
## the scene panel, where it scrolls
var ui_insp: PanelContainer
var ui_insp_vb: VBoxContainer
var ui_attr_box: VBoxContainer   # ROADMAP 82: the picked part's attribute rows (one slider each, value at the playhead)
var ui_attr_name: LineEdit       # the "+ attribute" form: name, min, max, default
var ui_attr_min: LineEdit
var ui_attr_max: LineEdit
var ui_attr_def: LineEdit
var ui_attr_sliders := {}        # attribute id -> [slider, prop row]
var _attr_sig := ""              # the rows shown: rebuilt only when the part or its attributes change (a drag keeps its slider)


## RR6: the browser box as tall as its shown rows (a folder opened grows it), never past the scene panel; the tree
## scrolls inside it when the rows need more room than that
func _browser_fit() -> void:
	var lp: Control = ui_side_of.get("left")
	if lp == null or ui_browser == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var sb := lp.get_theme_stylebox("panel")
	var head: float = (lp.get_child(0) as Control).get_child(0).get_combined_minimum_size().y + 2.0
	var want := head + ui_browser.content_h() + (sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM) if sb != null else 0.0)
	lp.offset_bottom = minf(-bottom_h - 6.0, lp.offset_top + want - vs.y)


func _insp_fit() -> void:
	if ui_insp == null or ui_insp_vb == null:
		return
	ui_title.tooltip_text = ui_how.text   # how to use it: the name's tooltip
	var sb := ui_insp.get_theme_stylebox("panel")
	var want := ui_insp_vb.get_combined_minimum_size().y + (sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM) if sb != null else 0.0)
	var room := get_viewport().get_visible_rect().size.y - bottom_h - 6.0 - ui_insp.offset_top - 6.0
	ui_insp.offset_bottom = ui_insp.offset_top + minf(want, room)


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = _theme()
	layer.add_child(ui_root)

	# ---- top bar
	var top := PanelContainer.new()
	top.theme_type_variation = "TopBar"
	top.anchor_right = 1.0
	top.offset_bottom = TOP_H
	ui_top_bar = top
	ui_root.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	top.add_child(tv)
	var strip := HBoxContainer.new()   # row 1: POSER, the tabs, the scene, the small icons
	strip.name = "top_strip"
	strip.custom_minimum_size.y = STRIP_H
	strip.add_theme_constant_override("separation", 2)
	tv.add_child(strip)
	var tb := HBoxContainer.new()      # row 2: the tab's tools
	tb.name = "top_tools"
	tb.custom_minimum_size.y = TOOLS_H
	tb.add_theme_constant_override("separation", 2)
	tv.add_child(tb)
	var caps := Control.new()          # row 3: the captions, each placed under its group (_place_caps)
	caps.name = "ribbon_caps"
	caps.custom_minimum_size.y = CAP_H
	caps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(caps)
	var logo := _label("KINE", 13, "heading")
	logo.custom_minimum_size.x = 64
	strip.add_child(logo)
	# round 7, Fusion's ribbon: tabs, then that tab's tools; Undo / Redo / Search / Help always on the right. Nothing
	# was removed: every button the bar had is in a tab (tests/ribbon_test.gd counts them), and the play row keeps its own
	ui_ribbon = {}
	ui_ribbon_tabs = {}
	var group := ButtonGroup.new()
	for t in RIBBON:
		var tbtn := _button(t, _ribbon.bind(t), RIBBON_TIPS[t])
		tbtn.name = "tab_" + t.to_lower()   # U2 scopes: tab_check (the tab), ribbon_check/b_check (its button)
		tbtn.toggle_mode = true
		tbtn.button_group = group
		tbtn.theme_type_variation = "RibbonTab"
		ui_ribbon_tabs[t] = tbtn
		strip.add_child(tbtn)
		var tools := HBoxContainer.new()
		tools.add_theme_constant_override("separation", 6)
		tools.name = "ribbon_" + t.to_lower()
		ui_ribbon[t] = tools
	for t in RIBBON:
		tb.add_child(ui_ribbon[t])
	var tog := func(tab: String, label: String, f: Callable, on: Callable, tip := ""):
		var b := _button(label, f, tip)
		b.toggle_mode = true
		ui_toggles.append([b, on])
		ui_ribbon[tab].add_child(b)
	# POSE
	ui_ribbon["POSE"].add_child(_button("CLIP this pose (Enter)", _card_add, "the body as it is now becomes the next clip in the scene"))
	ui_ribbon["POSE"].add_child(_button("Reset body", _do.bind(_reset_all)))
	ui_ribbon["POSE"].add_child(_button("Snap to floor", _floor_snap, "lift or sink the picked card (or the body) so its lowest point touches the floor; the joints stay. Ctrl+Z takes it back"))
	ui_ribbon["POSE"].add_child(_button("Arms 25°", _do.bind(_arms_relaxed), "both arms relaxed: 25° out from straight down"))
	ui_ribbon["POSE"].add_child(_button("Mirror pose (Shift+M)", _tool.bind(0), "the whole body left <-> right (the weapon changes hands)"))
	ui_ribbon["POSE"].add_child(_button("Sketch line of action", _loa_arm, "sketch: drag one stroke on the view, and the spine and the support leg bend to follow it (Shift = mirror the lean). Pose: draw a line of action"))
	ui_ribbon["POSE"].add_child(_button("Pose library", PoseLibrary.toggle.bind(self), "every saved pose as a picture: click to apply, drag right on it to blend 0-100 %, Ctrl = flipped (scripts/pose_library.gd)"))
	tog.call("POSE", "Symmetry", _toggle_symmetry, func(): return symmetry,
		"while on, dragging a part on one side moves the same part on the other side, reflected (the middle stays)")
	tog.call("POSE", "Line of action", func(): loa.on = not loa.on; _refresh(), func(): return loa.on,
		"the current line of action, faint: head, spine, pelvis, support knee and ankle. A C or an S shows the pose's shape")
	tog.call("POSE", "Collision (C)", func(): show_caps = not show_caps; _refresh(), func(): return show_caps,
		"see the capsules the body collides with. Yellow = a joint at its limit, red = touching another part")
	tog.call("POSE", "Weight paint", _wp_toggle, func(): return wp_on,
		"paint how much each bone moves each part of the skin: the body shows the picked bone's weight as a heat map (dark = none, orange = all). Drag on the body with the brush; Ctrl+Z takes a stroke back")
	_wp_ui(tb)
	# ANIMATE
	tog.call("ANIMATE", "Trail (T)", _press.bind(KEY_T), func(): return ov.trail_on, "the weapon tip's path, one dot per frame, blue slow to red fast")
	tog.call("ANIMATE", "Onion (O)", _press.bind(KEY_O), func(): return ov.onion_on, "the two cards before (orange, then red) and after (green, then cyan) as ghosts, the farther ones fainter")
	tog.call("ANIMATE", "Spacing (Shift+O)", _tool.bind(1), func(): return ov.spacing_on, "arms + weapon every 0.1 s around the playhead: bunched = slow")
	tog.call("ANIMATE", "Speed graph (Y)", _tool.bind(2), func(): return ov.graph_on)
	tog.call("ANIMATE", "Balance (Shift+B)", _press.bind(KEY_B, true), func(): return bal.on, "the centre of mass over the feet: green inside, amber near the edge, red he tips")
	tog.call("ANIMATE", "Stepped", _tool.bind(3), func(): return stepped_view, "poses only, no in-betweens (blocking)")
	tog.call("ANIMATE", "Moving holds", _tool.bind(4), func(): return S.moving_holds, "a held pose keeps drifting slightly toward the next")
	tog.call("ANIMATE", "Auto-key (Ctrl+K)", _toggle_autokey, func(): return auto_key,
		"auto-key: a pose change at the playhead keys a card there (or updates the card on that frame). On = a red frame round the view and a red playhead")
	tog.call("ANIMATE", "Airborne", _toggle_air, func(): return sel_card >= 0 and sel_card < S.cards.size() and S.cards[sel_card].get("air", false),
		"the picked card is in the air: from the card before to the card after, no foot touches the floor and the hips fly a real arc (g = 9.81)")
	# "Mirror the scene" lives in the Animator tools menu at the end of this row (a button for it too ran the bar off the screen)
	ui_tools = MenuButton.new()
	ui_tools.text = "Animator tools"
	ui_tools.tooltip_text = "mirror the pose or the scene, the trail on a part, and the other round-5 tools"
	ui_tools.flat = false
	ui_tools.focus_mode = Control.FOCUS_NONE
	var pm := ui_tools.get_popup()
	pm.add_item("Mirror the pose  (left <-> right, whole body)   Shift+M", 0)
	pm.add_item("Mirror the scene  (a left-handed copy in _wip)", 5)
	pm.add_check_item("Spacing ghosts  (every 0.1 s: bunched = slow)   Shift+O", 1)
	pm.add_check_item("Speed graph  (tip, hips, head)   Y", 2)
	pm.add_check_item("Stepped preview  (poses only, no in-betweens)", 3)
	pm.add_check_item("Moving holds  (a held pose keeps breathing)", 4)
	pm.id_pressed.connect(_tool)
	ui_ribbon["ANIMATE"].add_child(ui_tools)
	# ROADMAP 54: the two mirrors one click away (the menu item above stays): a copy in _wip, or the open scene itself
	ui_ribbon["ANIMATE"].add_child(_button("Mirror scene", _mirror_scene, "Mirror scene: a left-handed copy of this scene, saved in scenes/_wip and opened (yours is untouched)"))
	ui_ribbon["ANIMATE"].add_child(_button("Mirror in place", _mirror_in_place, "Mirror in place: this scene mirrored left <-> right, card by card, as ONE undo step (Ctrl+Z takes it back; nothing is saved)"))
	ui_ribbon["ANIMATE"].add_child(_button("Ask AI", _ai_toggle, "type what should happen (\"he waves, then sits\") and an AI builds the cards on this scene: each of its steps is one Ctrl+Z. Runs on this machine (Ollama) or with your own Claude / GPT / Gemini key"))
	ui_ribbon["ANIMATE"].add_child(_button("From video", _video_ask, "animation from a video of a person: pick a phone clip, the tracker finds the body in every frame and it arrives as a new scene with the feet planted. Or drop the video on the window"))
	# CHECK
	ui_ribbon["CHECK"].add_child(_button("Check", _check, "grade the scene against real recorded human motion; click a problem to jump to it"))
	ui_ribbon["CHECK"].add_child(_button("Polish", _polish, "smooth the scene and add the in-between detail into a NEW scene; yours is not touched"))
	ui_ribbon["CHECK"].add_child(_button("Fix moves through the body", _clear_scene))
	tog.call("CHECK", "Dummy (H)", _dummy_toggle, func(): return dummy_on, "a second mannequin out front: red where the weapon is in it")
	tog.call("CHECK", "Frame data", _fd_toggle, func(): return fd_on, "frame data: startup (green) / active (red) / recovery (blue) on the timeline, with the counts (ROADMAP 12)")
	tog.call("CHECK", "Frame boxes", _fd_boxes_toggle, func(): return fd_boxes, "hitboxes (red) on active frames and hurtboxes (grey) on every frame, in the view")
	fd_btn = _button("Frame rate", _fd_cycle_fps, "the frame rate the frame data counts in (24, 30, 60, 120 fps): now %d fps" % fd_fps)
	ui_ribbon["CHECK"].add_child(fd_btn)
	# EXPORT (round 35a, QQ4): what leaves Poser, in one place (each also in the search, by its long name)
	ui_ribbon["EXPORT"].add_child(_button("Export...", _export_dialog_open, "one dialog for every engine and tool: Unreal 5, Unity, Godot, Blender, Maya / MotionBuilder, Web, raw data. It shows what each needs and the warnings for this scene (docs/EXPORT.md)"))
	ui_ribbon["EXPORT"].add_child(_button("Export frame data (json)...", _fd_export, "startup, active, recovery and the hitboxes per frame, in metres (Y up), saved where you pick (FRAME_DATA: docs/research/FRAME_DATA.md)"))
	ui_ribbon["EXPORT"].add_child(_button("Save version", _save_version, "the scene as it is now kept as a version (Versions, in the scene row, brings it back)"))
	# SET (round 37, SS5 / SS6): props to pose with
	var ap := MenuButton.new()
	ap.text = "Add prop"
	ap.name = "menu_add_prop"
	ap.flat = false
	ap.focus_mode = Control.FOCUS_NONE
	ap.tooltip_text = "put a prop in front of the body, on the floor: a box, a chair, a table, stairs, a bed... or one of your own models"
	ap.about_to_popup.connect(_prop_menu_fill.bind(ap))
	ap.get_popup().id_pressed.connect(_prop_menu_pick.bind(ap))
	ui_ribbon["SET"].add_child(ap)
	ui_ribbon["SET"].add_child(_button("Import model", _import_ask, "bring in your own .glb model (a box, furniture, an object): it is checked, copied into your library and put in the set. Or drop the file on the window"))
	for tt in [["Turn left", -15.0], ["Turn right", 15.0]]:
		var ptb := _button(tt[0], _prop_turn.bind(tt[1]), "turn the picked prop 15° round its middle")
		ui_prop_btns[tt[0]] = ptb
		ui_ribbon["SET"].add_child(ptb)
	var dpb := _button("Delete prop", _prop_del, "take the picked prop out of the scene (Ctrl+Z puts it back)")
	ui_prop_btns["Delete prop"] = dpb
	ui_ribbon["SET"].add_child(dpb)
	ui_use_btns["Sit here"] = _button("Sit here", _prop_sit, "a new card: the body sits on the picked chair, stool or bench (facing away from its back, feet on the floor)")
	ui_use_btns["Step up"] = _button("Step up", _prop_step, "a new card: the nearer foot steps onto the picked box, step or stairs (the other stays on the floor)")
	ui_use_btns["Pick up"] = _button("Pick up", _prop_take, "the hand(s) next to the picked prop hold it from the selected card on: it moves with them")
	ui_use_btns["Put down"] = _button("Put down", _prop_put, "the hands let the prop go at the selected card: it falls onto what is under it (real gravity)")
	for k in ui_use_btns:
		ui_ribbon["SET"].add_child(ui_use_btns[k])
	# VIEW
	for v in [["Front (1)", 1], ["His right (2)", 2], ["Top (3)", 3], ["Back (4)", 4], ["His left (5)", 5]]:
		ui_ribbon["VIEW"].add_child(_button(v[0], _view.bind(v[1])))
	ui_ribbon["VIEW"].add_child(_button("Big view (Tab)", _big_view, "hide the side panels so the body fills the screen"))
	tog.call("VIEW", "Hints", func(): _set_hints(not hints_on), func(): return hints_on, "the teaching lines (how to click, drag, start): on or off (remembered)")
	tog.call("VIEW", "Light", func(): _set_light(Tok.dark), func(): return not Tok.dark, "light or dark theme (remembered)")
	tog.call("VIEW", "Follow system", func(): _set_theme_system(theme_pref != "system"), func(): return theme_pref == "system", "the palette follows Windows' dark mode (remembered); Light sets it by hand")
	tog.call("VIEW", "Corrective shapes", func(): corr.on = not corr.on; dummy_corr.on = corr.on; _refresh(); dummy_corr.update(T.D), func(): return corr.on,
		"the elbows and knees keep their volume as they bend: the skin pushes out along its normals as the bend goes 0 -> 140 deg (scripts/corrective.gd). Off = the plain skinning, which pinches at a bent joint")
	tog.call("VIEW", "Easy mode", func(): easy.set_on(not easy.on), func(): return easy.on, "Easy: the 12 big buttons, the panels hidden (a fresh start is Easy). Off = Expert: every panel and tool, as before (remembered)")
	var us := MenuButton.new()
	us.text = "UI size"
	us.flat = false
	us.focus_mode = Control.FOCUS_NONE
	us.tooltip_text = "make the buttons and words bigger or smaller: 90 / 100 / 125 / 150 % (remembered)"
	for p in SCALES:
		us.get_popup().add_radio_check_item("%d %%" % p, p)
	us.get_popup().id_pressed.connect(_set_scale)
	us.about_to_popup.connect(func():
		for k in SCALES.size():
			us.get_popup().set_item_checked(k, SCALES[k] == ui_scale)
			us.get_popup().set_item_disabled(k, not scale_fits(SCALES[k]))
			us.get_popup().set_item_tooltip(k, "" if scale_fits(SCALES[k]) else GREY_TAG.strip_edges() + " %d %% needs a window of at least %d x %d px: make the window bigger (maximise it)" % [SCALES[k], MIN_ROOM.x * SCALES[k] / 100, MIN_ROOM.y * SCALES[k] / 100])
			us.get_popup().set_item_text(k, "%d %%" % SCALES[k] + ("" if scale_fits(SCALES[k]) else "   (needs a bigger window)")))
	ui_ribbon["VIEW"].add_child(us)
	ui_ribbon["VIEW"].add_child(_button("View options", _onion_panel_open, "onion skin options: ghosts of the picked parts only, the frames before and after, the step between them (remembered)"))
	# always there, in the strip: the scene in the middle, the small icons on the right
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(fill)
	ui_doc_dot = _label("\u25cf", 11, "warn")
	ui_doc_dot.tooltip_text = "changes not saved yet (Save scene keeps them; the autosave keeps them meanwhile)"
	ui_doc_dot.mouse_filter = Control.MOUSE_FILTER_PASS
	strip.add_child(ui_doc_dot)
	ui_doc = _label("", 13, "text")
	ui_doc.name = "doc_name"
	strip.add_child(ui_doc)
	var fill2 := Control.new()
	fill2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(fill2)
	var right0 := strip.get_child_count()
	ui_undo_btn = _button("Undo (Ctrl+Z)", _undo)
	strip.add_child(ui_undo_btn)
	ui_hist_btn = _button("History", _toggle_history, "every change by name, newest on top: click one to go back (or forward) to exactly there")
	ui_redo_btn = _button("Redo (Ctrl+Y)", _redo)
	strip.add_child(ui_redo_btn)
	_undo_tips()
	strip.add_child(ui_hist_btn)
	strip.add_child(_button("Search (S)", func(): ui_cmd.open(), "type a few letters of any command: mirror, trail, check, staff...  Enter runs it"))
	var hb := _button("? Help", func(): ui_help.visible = not ui_help.visible, "every key and mouse move, on one page")
	strip.add_child(hb)
	var wb := _button("What went wrong?", _why_toggle, "the last refusal or error, explained in plain words, with the one next step")
	strip.add_child(wb)
	for t in RIBBON:
		_group(t)
		for b in ui_ribbon[t].get_children():
			_iconise(b)
	ui_top_right = strip.get_children().slice(right0)
	for b in ui_top_right:
		_iconise(b)
		(b as Control).custom_minimum_size = Vector2(28, STRIP_H - 4)
	hb.name = "b_help"
	wb.name = "b_why"
	var tfill := Control.new()
	tfill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(tfill)
	ui_tb = tb
	for t in RIBBON:
		ui_caps[t] = []
		for g in RIBBON_GROUPS.get(t, []):
			var cap := MenuButton.new()
			cap.name = "cap_" + String(g[0]).to_lower()
			cap.text = String(g[0]) + " \u25be"
			cap.flat = true
			cap.focus_mode = Control.FOCUS_NONE
			cap.theme_type_variation = "RibbonCap"
			cap.tooltip_text = "the %s tools by name" % String(g[0]).to_lower()
			var tools: Array = ui_ribbon[t].get_children().filter(func(c): return c is Button and label_of(c) in g[1])
			for i in tools.size():
				cap.get_popup().add_item(label_of(tools[i]), i)
			cap.get_popup().id_pressed.connect(func(i): _run_tool(tools[i], cap))
			caps.add_child(cap)
			ui_caps[t].append([cap, tools])
	get_viewport().size_changed.connect(_place_caps.call_deferred)
	ui_more = MenuButton.new()
	ui_more.name = "b_more_tools"
	ui_more.text = "More"
	ui_more.tooltip_text = "the tab's tools that do not fit this window"
	ui_more.flat = false
	ui_more.visible = false
	ui_more.get_popup().id_pressed.connect(_more_pick)
	tb.add_child(ui_more)
	tb.move_child(ui_more, tb.get_children().find(tfill))
	_ribbon("POSE")

	# ---- left: poses
	var lp := PanelContainer.new()
	lp.offset_left = 6
	lp.offset_top = TOP_H + 6
	lp.offset_right = LEFT_W
	lp.anchor_bottom = 1.0
	lp.offset_bottom = -BOTTOM_H - 6
	ui_root.add_child(lp)
	ui_side.append(lp)
	ui_side_of["left"] = lp
	# THE BROWSER (round 36, RR3; Fusion's): ONE slim tree, the left panel's whole content: Scene (its clips), Poses
	# (Library / Mine), Body, Weapon, Target dummy. A row picks (a pose applies, a clip shows, a part is selected); its
	# right-click menu has the rest (Rename / Delete / CLIP a pose, the dummy's Closer / Farther / Solid). The round-7
	# Poses tab's list and name box stay the pose model (hidden): the tree shows the list, a name dialog holds the box
	var lv := VBoxContainer.new()
	lv.name = "browser_box"
	lv.add_theme_constant_override("separation", 2)
	lp.add_child(lv)
	var lhd := HBoxContainer.new()
	lhd.name = "browser_head"
	lhd.add_theme_constant_override("separation", 2)
	lv.add_child(lhd)
	var bt := _label("BROWSER", PROP_TXT, "heading")
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lhd.add_child(bt)
	var sv := _button("Save pose", _pose_ask.bind("save"), "save the body as a pose (Ctrl+S): it asks the name")
	sv.name = "b_save_pose"
	_icon_only(sv, "save", Vector2(26, 24))
	lhd.add_child(sv)
	var xl := _button("Fold this box (the POSES rail opens it)", _fold.bind("left", true), "fold the browser to a thin rail: more room for the body (remembered)")
	xl.name = "fold_left"
	_icon_only(xl, "close", Vector2(26, 24))
	lhd.add_child(xl)
	ui_fold_btn["left"] = xl
	ui_browser = Browser.new()
	ui_browser.m = self
	ui_browser.name = "Browser"
	lv.add_child(ui_browser)
	ui_poses = ItemList.new()   # the pose model: the tree's Poses rows are its items
	ui_poses.visible = false
	ui_poses.item_selected.connect(_pose_apply)
	lv.add_child(ui_poses)
	ui_name_dlg = ConfirmationDialog.new()
	ui_name_dlg.name = "pose_name_dialog"
	ui_name_dlg.min_size = Vector2i(320, 0)
	ui_pose_name = LineEdit.new()
	ui_pose_name.name = "edit_name"
	ui_pose_name.placeholder_text = "name for the body's pose"
	ui_name_dlg.add_child(ui_pose_name)
	ui_name_dlg.register_text_enter(ui_pose_name)
	ui_name_dlg.confirmed.connect(func(): _rename_pose() if _name_for == "rename" else _save_pose())
	add_child(ui_name_dlg)
	ui_dummy = _label("dummy %s out" % Units.len(T.dist), 13, "dummy_text", true)   # the dummy's readout: the tree's row shows it
	ui_dummy.visible = false
	lv.add_child(ui_dummy)

	# ---- right: the selected part
	var rp := PanelContainer.new()
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.offset_left = -RIGHT_W
	rp.offset_right = -6
	rp.offset_top = TOP_H + 6
	rp.offset_bottom = TOP_H + 300   # _insp_fit: as tall as what it shows (RR2)
	ui_root.add_child(rp)
	ui_side.append(rp)
	ui_side_of["right"] = rp
	ui_insp = rp
	_rail("left", "POSES")
	_rail("right", "PART")
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO   # a bar only when it is taller than the window allows
	rp.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.custom_minimum_size = Vector2(RIGHT_W - 34, 0)
	vb.add_theme_constant_override("separation", 3)
	sc.add_child(vb)
	ui_insp_vb = vb
	var pth := Theme.new()   # ONE TYPE SCALE (round 25, #40): the panel's buttons at the text size too
	for t in ["Button", "OptionButton", "Label"]:
		pth.set_font_size("font_size", t, PROP_TXT)
	vb.theme = pth
	# THE HEADER (RR2): the part's name, its lock, the x that folds the box to its rail; how to use it is the name's
	# tooltip (ui_how keeps the words, hidden)
	var hd := HBoxContainer.new()
	hd.name = "insp_head"
	hd.add_theme_constant_override("separation", 2)
	vb.add_child(hd)
	ui_title = _label("", PROP_BIG, "heading")
	ui_title.clip_text = true
	ui_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ui_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_title.mouse_filter = Control.MOUSE_FILTER_PASS
	hd.add_child(ui_title)
	ui_lock_btn = _button("Lock this part", _toggle_lock.bind(""), "a locked part keeps its pose while you change the rest: it cannot be dragged, and Reset or Mirror leave it")
	ui_lock_btn.name = "btn_lock_part"
	_icon_only(ui_lock_btn, "lock", Vector2(26, 24))
	hd.add_child(ui_lock_btn)
	var xb := _button("Fold this box (the PART rail opens it)", _fold.bind("right", true), "fold the inspector to a thin rail: more room for the body (remembered)")
	xb.name = "fold_right"
	_icon_only(xb, "close", Vector2(26, 24))
	hd.add_child(xb)
	ui_fold_btn["right"] = xb
	ui_how = _label("", PROP_TXT, "info", true)
	ui_how.visible = false
	vb.add_child(ui_how)
	for k in ["bend", "side", "twist"]:
		var box := VBoxContainer.new()
		var l := _prop_row(box)
		var s := HSlider.new()
		s.name = "slider_" + k   # by its axis: the label before it is the hint, and its words change with the part
		s.step = 0.5
		s.drag_started.connect(_push_undo)
		s.value_changed.connect(_on_slider.bind(k))
		_row_slider(l, s)
		vb.add_child(box)
		ui_rows[k] = {"slider": s, "label": l, "box": box}
	ui_hip_box = VBoxContainer.new()
	vb.add_child(ui_hip_box)
	for k in 3:
		var l := _prop_row(ui_hip_box)
		var s := HSlider.new()
		s.name = "slider_hip_%d" % k
		s.step = 0.005
		s.drag_started.connect(_push_undo)
		s.value_changed.connect(_on_hip.bind(k))
		_row_slider(l, s)
		ui_hips.append([s, l])
	# RR2: the part's actions on ONE row, short words; each keeps its full name (label, tooltip, Search)
	var acts := _row(vb, [_short(_button("Reset (R)", _do.bind(_reset_part), "the part back to straight (0°, 0°, 0°)"), "Reset"),
		_short(_button("90° (Q)", _do.bind(_snap.bind(90.0)), "round the part's angles to the 90° steps its range allows"), "90°"),
		_short(_button("45°", _do.bind(_snap.bind(45.0)), "round the part's angles to the 45° steps its range allows"), "45°"),
		_short(_button("Right to left (M)", _do.bind(_mirror_side.bind("_r")), "the left arm and leg take the right ones' pose, reflected"), "R→L"),
		_short(_button("Left to right (N)", _do.bind(_mirror_side.bind("_l")), "the right arm and leg take the left ones' pose, reflected"), "L→R")])
	acts.name = "insp_actions"
	acts.add_theme_constant_override("separation", 3)
	ui_pole_row = _row(vb, [_label("points", PROP_TXT), _button("<", _do.bind(_pole.bind(-15.0)), "swing the elbow / knee 15 deg one way; the hand / foot stays (Ctrl+drag does it by hand)"),
		_button(">", _do.bind(_pole.bind(15.0)), "swing the elbow / knee 15 deg the other way; the hand / foot stays (Ctrl+drag does it by hand)")])
	var hands := _section(vb, "HANDS")
	var frow := _row(hands, [_label("right:", PROP_TXT), _button("Open", _do.bind(_fingers.bind("r", "open"))), _button("Grip", _do.bind(_fingers.bind("r", "grip"))),
		_button("Fist", _do.bind(_fingers.bind("r", "fist"))), _button("Relaxed", _do.bind(_fingers.bind("r", "relaxed")))])
	frow.name = "fingers_r"
	frow = _row(hands, [_label("left:  ", PROP_TXT), _button("Open", _do.bind(_fingers.bind("l", "open"))), _button("Grip", _do.bind(_fingers.bind("l", "grip"))),
		_button("Fist", _do.bind(_fingers.bind("l", "fist"))), _button("Relaxed", _do.bind(_fingers.bind("l", "relaxed")))])
	frow.name = "fingers_l"
	# YY3: one CURL and one SPREAD slider per hand (Body.hand_curl, people's proportions), and Point
	for sd in ["r", "l"]:
		for k in ["curl", "spread"]:
			var hl := _prop_row(hands)
			_set_prop(hl, "%s %s" % ["right" if sd == "r" else "left", k], "")
			var hs := HSlider.new()
			hs.name = "hand_%s_%s" % [k, sd]
			hs.min_value = 0.0
			hs.max_value = 1.0
			hs.step = 0.01
			hs.drag_started.connect(_push_undo)
			hs.value_changed.connect(_on_hand_slider.bind(sd, k))
			_row_slider(hl, hs)
			ui_hand[sd + k] = hs
		var pb := _button("Point (%s)" % ["right" if sd == "r" else "left"], _do.bind(_hand_point.bind(sd)), "the index straight, the other fingers and the thumb curled")
		pb.name = "b_point_" + sd   # the label's side is in brackets, which the auto-name drops: both would be b_point
		_row(hands, [pb])
	# ROADMAP 73: one curl slider per finger (thumb too) per hand (Body.finger_curl), then the named poses (Body.hand_pose)
	for sd in ["r", "l"]:
		for f in ["thumb", "index", "middle", "ring", "pinky"]:
			var fl := _prop_row(hands)
			_set_prop(fl, "%s %s curl" % ["right" if sd == "r" else "left", f], "")
			var fs := HSlider.new()
			fs.name = "finger_%s_%s" % [f, sd]
			fs.min_value = 0.0
			fs.max_value = 1.0
			fs.step = 0.01
			fs.drag_started.connect(_push_undo)
			fs.value_changed.connect(_on_finger_slider.bind(sd, f))
			_row_slider(fl, fs)
			ui_finger[sd + f] = fs
	for half in [Body.POSE_NAMES.slice(0, 4), Body.POSE_NAMES.slice(4)]:
		var prow: Array = []
		for pn in half:
			var pbn := _button(pn, _pose_pick.bind(pn), "the picked hand (or the hand of the picked finger) goes to the %s pose; with cards, its joints are keyed at the playhead" % pn)
			pbn.name = "b_pose_" + pn
			prow.append(pbn)
		_row(hands, prow)
	# YY4: the whole back, one slider per way (Body.back_bend: shared by each joint's range)
	var back := _section(vb, "BACK")
	for k in ["bend", "side", "twist"]:
		var bl := _prop_row(back)
		_set_prop(bl, {"bend": "forward", "side": "side", "twist": "twist"}[k], "")
		var bs := HSlider.new()
		bs.name = "back_" + k
		var br := B.back_range(k)
		bs.min_value = br.x
		bs.max_value = br.y
		bs.step = 0.5
		bs.drag_started.connect(_push_undo)
		bs.value_changed.connect(_on_back_slider.bind(k))
		_row_slider(bl, bs)
		ui_back[k] = bs
	back.add_child(_label("The spine, neck and head share the bend by their ranges: they reach their limits together.", PROP_TXT, "text:0.55", true))
	hands.add_child(_label("Fingers one by one: click a finger on the body (zoom in with the wheel).", PROP_TXT, "text:0.55", true))
	# ROADMAP 82: CUSTOM ATTRIBUTES on the picked part (custom_attr.gd): "+ attribute" defines one; its slider keys the value at the playhead
	var attrs_sec := _section(vb, "ATTRIBUTES")
	attrs_sec.add_child(_label("A value on this part, keyed per card like an angle (grip 0 .. 1). The engine reads it from the .glb.", PROP_TXT, "text:0.55", true))
	ui_attr_box = VBoxContainer.new()
	ui_attr_box.name = "attr_rows"
	attrs_sec.add_child(ui_attr_box)
	ui_attr_name = LineEdit.new()
	ui_attr_name.name = "attr_name"
	ui_attr_name.placeholder_text = "name, e.g. grip"
	ui_attr_name.tooltip_text = "the attribute's name: letters, digits or _, starting with a letter"
	ui_attr_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_attr_min = _attr_field("attr_min", "0", "the lowest value the slider reaches")
	ui_attr_max = _attr_field("attr_max", "1", "the highest value the slider reaches")
	ui_attr_def = _attr_field("attr_default", "0", "the value with no card keyed (between min and max)")
	_row(attrs_sec, [_label("name", PROP_TXT, "text:0.6"), ui_attr_name])
	_row(attrs_sec, [_label("min", PROP_TXT, "text:0.6"), ui_attr_min, _label("max", PROP_TXT, "text:0.6"), ui_attr_max])
	_row(attrs_sec, [_label("default", PROP_TXT, "text:0.6"), ui_attr_def, _button("+ attribute", _attr_add, "add the attribute to the picked part: one undo step (Ctrl+Z takes it back)")])
	var wep := _section(vb, "WEAPON")
	_row(wep, [_weapon_picker("opt_weapon_panel")])
	_row(wep, [_button("In right hand (B)", _do.bind(_bat_put.bind("hand_r"))), _button("In left hand", _do.bind(_bat_put.bind("hand_l")))])
	_row(wep, [_button("Main hand down (,)", _do.bind(_slide.bind(-0.03)), "the hand slides toward the lower end; the weapon stays, the arm follows"),
		_button("Main hand up (.)", _do.bind(_slide.bind(0.03)), "the hand slides toward the tip; the weapon stays, the arm follows")])
	_row(wep, [_button("Lock bat to hand / Free it (L)", _do.bind(_bat_lock))])
	# from the old left panel (RR3)
	ui_slide_btn = _button("Slide , . : body follows", _slide_mode, "an option, not a rule: , . either move the hand along a weapon that stays put (the arm follows), or slide the weapon through a hand that stays put")
	_row(wep, [_short(_button("2nd hand on/off (G)", _do.bind(_toggle_second), "the other hand on the shaft; [ ] slide it"), "2nd hand"), ui_slide_btn])
	_row(wep, [_button("Hand to the end", _do.bind(_hand_to_end), "ROADMAP 10-13: a long weapon swings from its end - the main hand slides to the lower end in 3 cm steps (the body follows, or the weapon moves: the toggle above)")])
	_row(wep, [_button("Other hand on the bat (G)", _do.bind(func(): B.grip = not B.grip)),
		_button("Save grip as standard", _save_grip, "the bat's place in the hand + the fingers become the grip 'Bat in hand' uses")])
	wep.add_child(_label("[ ] slide the other hand along the shaft,  , . slide the main hand,  - = change the length", PROP_TXT, "text:0.55", true))
	var num := _section(vb, "NUMBERS")
	ui_math_btn = _button("Show the math (for Claude)", func(): ui_math.visible = not ui_math.visible)
	num.add_child(ui_math_btn)
	ui_math = _label("", PROP_TXT, "text:0.6", true)
	ui_math.visible = false
	num.add_child(ui_math)

	# ---- bottom: the scene
	var bp := PanelContainer.new()
	ui_bp = bp
	bp.theme_type_variation = "BottomBar"
	bp.anchor_top = 1.0
	bp.anchor_bottom = 1.0
	bp.anchor_right = 1.0
	bp.offset_top = -BOTTOM_H
	bp.offset_left = 6
	bp.offset_right = -6
	bp.offset_bottom = -6
	ui_root.add_child(bp)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bp.add_child(bv)
	var bh := HBoxContainer.new()
	ui_bh = bh
	bh.add_theme_constant_override("separation", 4)   # the template button made the row 3 px wider than a 1280 window at 125 %
	bv.add_child(bh)
	bh.add_child(_label("3  SCENE  (clips)", 19, "heading"))
	var intro := _label("your clips in a row; Play and the body moves from clip to clip on its own", 14, "text:0.6")
	intro.set_meta("hint_text", intro.text)   # hints off empties it (it keeps its width: the buttons do not move)
	ui_hint_labels.append(intro)
	intro.clip_text = true   # a narrow window (or a big UI size) shortens this line, never pushes the buttons off (round 11)
	intro.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.custom_minimum_size.x = 40
	intro.size_flags_stretch_ratio = 20.0   # the free room goes to the words first (the spacer after it shares it 20:1)
	bh.add_child(intro)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp)
	ui_scene_name = LineEdit.new()
	ui_scene_name.placeholder_text = "scene name"
	ui_scene_name.custom_minimum_size = Vector2(160, 0)
	ui_scene_name.text_submitted.connect(func(_t): _step_hint = "Save scene"; _save_scene())   # Enter saves (V3: one action less)
	bh.add_child(ui_scene_name)
	bh.add_child(_button("Save scene", _save_scene))
	ui_scenes = OptionButton.new()
	ui_scenes.name = "opt_scene"
	ui_scenes.focus_mode = Control.FOCUS_NONE
	ui_scenes.custom_minimum_size = Vector2(170, 0)
	ui_scenes.fit_to_longest_item = false   # round 45: a long work-copy name pushed the play row off a 1280 window
	ui_scenes.clip_text = true
	ui_scenes.item_selected.connect(_scene_picked)   # V3: picking a scene opens it (asks first if this one has unsaved changes)
	# ROADMAP 51: a picture of each scene's body in the list (scripts/scene_thumbs.gd); drawn when the list opens
	thumbs = SceneThumbs.new()
	thumbs.name = "scene_thumbs"
	add_child(thumbs)
	thumbs.made.connect(_thumb_made)
	ui_scenes.get_popup().add_theme_constant_override("icon_max_width", SceneThumbs.SIZE.x)
	ui_scenes.add_theme_constant_override("icon_max_width", 18)   # the CLOSED button shows the open scene's picture too: at full size it made the scene row 76 px tall and pushed the strip off the screen
	ui_scenes.get_popup().about_to_popup.connect(_scenes_opening)
	bh.add_child(ui_scenes)
	bh.add_child(_button("Open scene", func():
		if ui_scenes.selected >= 0:
			_scene_picked(ui_scenes.selected)))   # ROADMAP 50: asks first when the open scene has unsaved changes
	bh.add_child(_button("Delete scene", _delete_scene, "the scene picked in the list (it asks first; the file goes to the trash folder)"))
	ui_versions = MenuButton.new()   # SCENE VERSIONS (round 29, JJ1)
	ui_versions.name = "btn_versions"
	ui_versions.text = "Versions"
	ui_versions.flat = false
	ui_versions.focus_mode = Control.FOCUS_NONE
	ui_versions.tooltip_text = "save the scene as it is now as a version, or go back to one (the scene's file is not touched)"
	ui_versions.about_to_popup.connect(_versions_menu)
	ui_versions.get_popup().id_pressed.connect(_version_picked)
	bh.add_child(ui_versions)
	ui_loop = CheckBox.new()
	ui_loop.text = "Loop"
	ui_loop.name = "check_loop"
	ui_loop.add_theme_font_size_override("font_size", 13)
	ui_loop.focus_mode = Control.FOCUS_NONE
	ui_loop.tooltip_text = "ON: the scene plays round and round (a walk, an idle). CHECK then grades the seam: the end must meet the start."
	ui_loop.toggled.connect(func(on): _push_undo(); S.loop = on; check_ran = false; _refresh())
	bh.add_child(_button("New empty scene", _new_asked))
	bh.add_child(_short(_button("New from template...", _template_ask, "five starting scenes: walk, run, jump, punch, sword swing (each checked against real people's numbers); opens as a new scene in scenes/_wip"), "Template..."))
	var fb := _button("Fold", _fold.bind("bottom", true), "fold the scene panel to the timeline and Play: more room for the body (remembered)")
	fb.name = "fold_bottom"
	bh.add_child(fb)
	ui_fold_btn["bottom"] = fb
	var cs := ScrollContainer.new()
	cs.custom_minimum_size = Vector2(0, 112)
	cs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(cs)
	ui_card_row = cs
	ui_cards = HBoxContainer.new()
	ui_cards.add_theme_constant_override("separation", 8)
	cs.add_child(ui_cards)
	ui_timeline = Timeline.new()
	ui_timeline.m = self
	ui_timeline.tooltip_text = "drag a card's edge to change its move (or hold); click a card to jump to it; drag the ruler to scrub"
	ui_timeline.scrubbed.connect(func(t: float):
		playing = false
		playhead = t
		_ps().apply(B, playhead)
		_audio_scrub()
		_refresh())
	ui_timeline.picked.connect(_timeline_pick)
	ui_timeline.box_picked.connect(_bx_pick)   # ROADMAP 36: a box on the boxes lane picked
	ui_timeline.range_set.connect(func(which: String, t: float): _pv_set(which, t))   # WW4: Shift+click / Alt+click on the ruler
	ui_timeline.finding_picked.connect(_finding_mark)
	ui_timeline.retime_started.connect(_retime_begin)
	ui_timeline.retimed.connect(_retime_step)
	ui_timeline.shot_cut.connect(_shot_cut_drag)   # ROADMAP 75: a cut on the shots lane dragged
	# ONE STRIP (round 36, RR4): first / previous / play / next / last / loop, the clips on their track, the time, the
	# speed, Natural, a gear for the rest (Smooth, tween, ease, + tween), the Clips button that opens the cards above
	var ph := HBoxContainer.new()
	ui_play_row = ph
	ph.name = "play_row"
	ph.add_theme_constant_override("separation", 4)
	bv.add_child(ph)
	for t in [["First clip (Home)", _go_end.bind(false), "first", "the start of the scene"],
			["Previous clip", _go_card.bind(-1), "prev", "the clip before the playhead"]]:
		var trb := _button(t[0], t[1], t[3])
		_icon_only(trb, t[2], Vector2(30, 30))
		ph.add_child(trb)
	ui_play = _button("Play (Space)", _toggle_play, "play the scene from the playhead; Space again stops it")
	ui_play.name = "b_play"
	_icon_only(ui_play, "play", Vector2(34, 30))
	ph.add_child(ui_play)
	for t in [["Next clip", _go_card.bind(1), "next", "the clip after the playhead"],
			["Last clip (End)", _go_end.bind(true), "last", "the end of the scene"]]:
		var trb := _button(t[0], t[1], t[3])
		_icon_only(trb, t[2], Vector2(30, 30))
		ph.add_child(trb)
	ui_timeline.custom_minimum_size = Vector2(0, 34)
	ui_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(ui_timeline)
	var ob := _button("Clips", _fold.bind("bottom", false), "open the scene panel again: the clips and the scene's buttons")
	ob.name = "open_bottom"
	ob.visible = false
	ob.add_theme_font_size_override("font_size", 13)
	ob.custom_minimum_size.y = 30
	ui_fold_btn["bottom_open"] = ob
	var sl := _short(_button("Slower", _speed.bind(1.1), "10% slower: the picked card, or the whole scene with no card picked (Save scene keeps it)"), "\u2212")
	var fa := _short(_button("Faster", _speed.bind(1.0 / 1.1), "10% faster: the picked card, or the whole scene with no card picked (Save scene keeps it)"), "+")
	for b in [sl, fa]:
		b.custom_minimum_size = Vector2(26, 30)
		b.theme_type_variation = "Ribbon"   # flat, thin margins: the strip stays one 34-px row
	ui_time = HSlider.new()
	ui_time.name = "slider_time"
	ui_time.step = 0.01
	ui_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_time.custom_minimum_size = Vector2(0, 26)
	ui_time.value_changed.connect(func(v):
		if _sync:
			return
		playhead = v
		playing = false
		_ps().apply(B, playhead)
		_refresh())
	ph.add_child(ui_time)
	ui_time.visible = false   # round 6: the timeline above scrubs; two scrubbers is one too many
	ui_time_lbl = _label("0.00 s", 13, "text:0.75")
	ui_time_lbl.custom_minimum_size = Vector2(104, 0)
	ui_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.add_child(ui_time_lbl)
	# ROADMAP 48: the playback mode, as an icon and words, and the readout beside it ("dropping N frames")
	ui_mode_btn = _button("Real speed", _mode_toggle, "")
	ui_mode_btn.name = "b_play_mode"
	ui_mode_btn.add_theme_font_size_override("font_size", 13)
	ui_mode_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ui_mode_btn.add_theme_constant_override("icon_max_width", 18)
	ph.add_child(ui_mode_btn)
	ui_mode_lbl = _label("Real speed", 13, "info")
	ui_mode_lbl.name = "play_mode_readout"
	ui_mode_lbl.tooltip_text = "the playback mode: real speed keeps wall-clock time (dropped frames are counted); every frame shows each frame in order (its speed is shown)"
	ph.add_child(ui_mode_lbl)
	ui_fps_lbl = _label("", 13, "text:0.75")
	ui_fps_lbl.name = "fps_readout"
	ui_fps_lbl.tooltip_text = "the real frames per second while playing, and the frames that took more than 1.5× the target time (dropped)"
	ph.add_child(ui_fps_lbl)
	ui_time_lbl.mouse_filter = Control.MOUSE_FILTER_STOP   # WW4: a click on the readout flips seconds <-> frames
	ui_time_lbl.tooltip_text = "click: show the time in seconds or in frames (at the scene's frame rate)"
	ui_time_lbl.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_toggle_frames())
	ph.add_child(_label("speed", 12, "text:0.5"))
	ph.add_child(sl)
	ph.add_child(fa)
	ph.add_child(ui_loop)   # the scene's Loop (a property of the file): on the strip, as an icon
	ui_natural = CheckBox.new()
	ui_natural.text = "Natural"
	ui_natural.add_theme_font_size_override("font_size", 13)
	ui_natural.button_pressed = true
	ui_natural.focus_mode = Control.FOCUS_NONE
	ui_natural.tooltip_text = "ON: the hips start first and the hands arrive last, like a real body. OFF: everything moves together."
	ui_natural.toggled.connect(func(on): S.natural = on; _dummy_hits(); _ps().apply(B, playhead); _refresh())
	ph.add_child(ui_natural)
	# the gear: the rest of the play options, in a small box above it
	ui_gear = PanelContainer.new()   # a panel on the UI, not a popup window: it takes the window's clicks like the rest
	ui_gear.name = "play_options"
	ui_gear.visible = false
	ui_root.add_child(ui_gear)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 6)
	ui_gear.add_child(gv)
	var gb := _button("Play options", _gear_open, "Smooth (spline), tween, ease, + tween")
	gb.name = "b_gear"
	_icon_only(gb, "gear", Vector2(30, 30))
	ui_gear_btn = gb
	ph.add_child(gb)
	ph.add_child(ob)
	ui_spline = CheckBox.new()
	ui_spline.text = "Smooth (spline)"
	ui_spline.focus_mode = Control.FOCUS_NONE
	ui_spline.tooltip_text = "ON: one smooth curve through every card; only cards with a hold stop. OFF: the body eases to a stop at every card."
	ui_spline.toggled.connect(func(on): S.spline = on; _rebuild_cards(); _ps().apply(B, playhead); _refresh())
	gv.add_child(ui_spline)
	var tw := HBoxContainer.new()
	gv.add_child(tw)
	tw.add_child(_label("tween", 14, "text:0.75"))
	ui_tween = HSlider.new()
	ui_tween.min_value = -0.25
	ui_tween.max_value = 1.25
	ui_tween.step = 0.01
	ui_tween.value = 0.5
	ui_tween.custom_minimum_size = Vector2(140, 26)
	ui_tween.focus_mode = Control.FOCUS_NONE
	ui_tween.tooltip_text = "TWEEN MACHINE: the picked card becomes a mix of the cards either side. Left = like the card before, right = like the card after, past the ends = overshoot. 'Update' keeps it."
	ui_tween.value_changed.connect(func(v): if not _sync: _tween(v))
	ui_tween.drag_ended.connect(func(_c): _tween_armed = false)
	tw.add_child(ui_tween)
	tw.add_child(_button("+ tween", _tween_add, "add an in-between card after the picked one, halfway to the next (then slide 'tween')"))
	var ew := HBoxContainer.new()
	gv.add_child(ew)
	ew.add_child(_label("ease", 14, "text:0.75"))
	ui_ease = OptionButton.new()
	ui_ease.name = "opt_ease"
	ui_ease.focus_mode = Control.FOCUS_NONE
	for e in Scene.ALL_EASES:
		ui_ease.add_item(e)
	ui_ease.tooltip_text = "how the move INTO the picked card eases: smooth (natural), linear, in (starts slow), out (ends slow), snap (holds, then jumps: a hit, a cut); reach / strike / throw / settle: measured from real motion (docs/research/EASE_PRESETS.md)"
	ui_ease.item_selected.connect(func(k): if not _sync: _set_ease(Scene.ALL_EASES[k]))
	ew.add_child(ui_ease)
	_gear_ease_bias(gv)
	ui_play_extra = []   # RR4: Check / Polish / Fix left the play row (the ribbon's CHECK tab, Search)

	# ---- status line
	ui_status = _label(WELCOME, 16, "say", true)
	ui_status.name = "status_line"
	ui_status.anchor_top = 1.0
	ui_status.anchor_bottom = 1.0
	ui_status.offset_top = -BOTTOM_H - 82
	ui_status.offset_bottom = -BOTTOM_H - 40
	ui_status.offset_left = LEFT_W + 12
	ui_status.anchor_right = 1.0
	ui_status.offset_right = -RIGHT_W - 12
	ui_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.c("say_bg")
	ui_say_box = sb
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	# the close (x): hints off (QQ3). The strip ignores the mouse; its own child button does not
	var hx := Button.new()
	hx.name = "hints_close"
	hx.text = "x"
	hx.flat = true
	hx.focus_mode = Control.FOCUS_NONE
	hx.tooltip_text = "hide the teaching hints (VIEW > Hints brings them back); messages about what you do still show"
	hx.anchor_left = 1.0
	hx.anchor_right = 1.0
	hx.offset_left = -26
	hx.offset_right = -2
	hx.offset_top = 2
	hx.offset_bottom = 24
	hx.pressed.connect(func(): _set_hints(false))
	ui_status.add_child(hx)
	ui_status.add_theme_stylebox_override("normal", sb)
	ui_root.add_child(ui_status)
	# COMPARE WITH (ROADMAP 28): the diff list, top left of the view, only while a version is compared (it never takes a click)
	ui_vdiff = PanelContainer.new()
	ui_vdiff.name = "vdiff_panel"
	ui_vdiff.visible = false
	ui_vdiff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_vdiff.set_anchors_preset(Control.PRESET_TOP_LEFT)   # over the 3D view, right of the browser column
	ui_vdiff.offset_left = 256
	ui_vdiff.offset_top = 96
	ui_vdiff.custom_minimum_size = Vector2(400, 0)
	var vsb := StyleBoxFlat.new()
	vsb.bg_color = Tok.c("float")
	vsb.set_corner_radius_all(6)
	vsb.set_content_margin_all(8)
	ui_vdiff.add_theme_stylebox_override("panel", vsb)
	ui_vdiff_text = _label("", 13, "text:0.85", true)
	ui_vdiff_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_vdiff.add_child(ui_vdiff_text)
	ui_root.add_child(ui_vdiff)
	ui_co_line = Label.new()   # ROADMAP 30: who animates which fighter, the peer's state (hidden without a session)
	ui_co_line.name = "co_line"
	ui_co_line.visible = false
	ui_root.add_child(ui_co_line)
	# ---- status bar: one line, always there (Fusion's bottom bar)
	ui_bar = _label("", 12, "text:0.55")   # RR5: the readout, small and grey, on the status line's right
	ui_bar.anchor_top = 1.0
	ui_bar.anchor_bottom = 1.0
	ui_bar.offset_top = -BOTTOM_H - 34
	ui_bar.offset_bottom = -BOTTOM_H - 6
	ui_bar.offset_left = LEFT_W + 12
	ui_bar.anchor_right = 1.0
	ui_bar.offset_right = -RIGHT_W - 12
	ui_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_bar.clip_text = true
	ui_bar.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ui_bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bb := StyleBoxEmpty.new()   # RR5: no box: quiet words on the view (Fusion's bottom bar)
	ui_bar_box = null
	ui_bar.add_theme_stylebox_override("normal", bb)
	ui_root.add_child(ui_bar)
	_build_nav()
	_build_akey_frame()

	# ---- help
	ui_cube = ViewCube.new()
	ui_cube.m = self
	ui_cube.anchor_left = 1.0
	ui_cube.anchor_right = 1.0
	ui_root.add_child(ui_cube)
	_place_cube()
	ui_ring = RingMenu.new()
	ui_ring.top_margin = TOP_H
	ui_root.add_child(ui_ring)
	ui_cmd = CommandSearch.new()
	ui_cmd.offset_top = TOP_H + 10
	ui_root.add_child(ui_cmd)
	ui_cmd.commands = _commands()
	ui_cmd.files_provider = _search_files   # ROADMAP 52: the saved poses and scenes, read each time the box opens
	ui_cmd.pose_by_words = _pose_words
	_hover_hints()
	tips = TipVideo.new()   # ROADMAP 49: a 2 s clip of the tool beside the hint, after 0.6 s on a button
	tips.name = "tips"
	add_child(tips)
	tips.attach_all(self, ui_root)
	ui_cmd.running.connect(func(n): _step_hint = n; _why_cmd = n; _macro_note(n))
	rec_label = _label("", 16, "fail")   # ROADMAP 81: the REC indicator, shown only while a macro is recorded
	rec_label.anchor_left = 0.5
	rec_label.anchor_right = 0.5
	rec_label.offset_left = -260
	rec_label.offset_right = 260
	rec_label.offset_top = TOP_H + 4
	rec_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rec_label.visible = false
	ui_root.add_child(rec_label)
	ui_help = PanelContainer.new()
	ui_help.name = "help_panel"
	ui_help.anchor_left = 0.5
	ui_help.anchor_right = 0.5
	ui_help.offset_left = -360
	ui_help.offset_right = 360
	ui_help.offset_top = TOP_H + 30
	ui_root.add_child(ui_help)
	var hv := VBoxContainer.new()
	hv.custom_minimum_size = Vector2(700, 0)
	ui_help.add_child(hv)
	hv.add_child(_label("HOW IT WORKS", 22, "heading"))
	hv.add_child(_label("1  POSE THE BODY.  Click a part, drag it.  Or use the sliders on the right, which say what each one does.  The body stops at real joint limits (yellow) and where parts meet (red).  Drag a hand or a foot and the whole arm or leg follows.  Ctrl+Z undoes.", 16, "text", true))
	hv.add_child(_label("2  SAVE IT.  Type a name on the left, 'Save body as a pose'.  It joins the list; click it any time to get it back.", 16, "text", true))
	hv.add_child(_label("3  MAKE A SCENE.  Put the body in a pose, CLIP this pose: it becomes a clip at the bottom.  Pose the next moment, add it.  Each card says how long the body takes to get there ('move', auto = the poser picks a natural time) and how long it stays ('hold').", 16, "text", true))
	hv.add_child(_label("4  PLAY.  The body moves from card to card on its own: the hips lead, the hands arrive last.  'Fix moves through the body' adds a pass-by card where an arm or the bat would go through the body.  Click a card to see that moment; change the body, then 'Update' on the card.", 16, "text", true))
	hv.add_child(_label("5  SEE THE MOTION.  T = motion trail: the weapon tip's path, one dot per frame (far apart = fast), blue slow to red fast, white = the cards.  Shift+T = a trail on the part you clicked (feet, hands, head, hips: as many as you like).  O = onion skin: the card before (orange) and after (green) as ghosts.  'tween' slider: the picked card becomes a mix of its two neighbours (past the ends = overshoot); '+ tween' adds an in-between card.  'Smooth (spline)': one curve through every card, only holds stop.", 16, "text", true))
	hv.add_child(_label("6  ANIMATOR TOOLS (top bar, ANIMATE tab).  Shift+M = mirror the whole pose left <-> right (the weapon changes hands).  Mirror the scene = a left-handed copy saved in _wip.  Shift+O = spacing ghosts: where the arms and weapon are every 0.1 s around the playhead; bunched = slow, a wide fan = fast.  Y = speed graph: tip, hips and head speed over the whole scene, click it to jump there.  Stepped preview = poses only, no in-betweens (blocking).  Moving holds = a held pose keeps drifting slightly toward the next one instead of freezing.  Check also flags FOOT SLIDE: a planted foot creeping along the floor.", 16, "text", true))
	hv.add_child(_label("7  TIMELINE (under the clips).  Each clip is a block: solid = moving into the pose, striped = holding it.  Drag a block's edge to change how long it takes (later clips slide along); a clip with no hold: drag its edge right to pull one out.  Shift = fine steps.  Click a block to jump to that clip; drag the ruler to scrub.  Grab a HAND or FOOT and drag: the limb follows; past its reach a yellow line shows where you are pulling it.", 16, "text", true))
	hv.add_child(_label("TOP BAR = TABS.  POSE (reset, relax, mirror, collision), ANIMATE (trail, onion, spacing, speed graph, stepped, moving holds, the Animator tools menu), CHECK (check, polish, fix, the dummy), VIEW (the five views, big view).  A lit button = that tool is on.  Undo, Redo, Search and Help are always on the right.", 16, "text", true))
	hv.add_child(_label("BROWSER (left panel, 2nd tab).  Every part of the body by name, folded like the body (torso, arms with their fingers, legs), the weapon, and the scene's clips.  Click one: selected, the same as clicking it in the view (a finger joint is one click here).  Click in the view and its row lights up.  CUBE (top right of the view): click a face to look from that side.", 16, "text", true))
	hv.add_child(_label("RIGHT-CLICK a part (click, don't drag: right-DRAG still turns the view): a ring around the mouse.  Up = Reset, then clockwise: Snap 90°, Copy to the other side, CLIP this pose, Pin a trail, Snap 45°.  Click one; the middle or Esc cancels.", 16, "text", true))
	hv.add_child(_label("S = SEARCH.  Don't remember where something is?  Press S, type a word (mirror, trail, staff, slower...), Enter.  Every button and key is in it, with its shortcut.", 16, "say", true))
	hv.add_child(_label("View: ARROWS slide the view, Shift+ARROWS turn around the body, PageUp/PageDown or the wheel zoom, Tab = big view.  F6 = the panels by keyboard (Tab moves, Enter presses, Esc back).  Mouse: right-drag = turn around, middle-drag = slide.", 15, "text:0.7", true))
	hv.add_child(_button("Got it", func(): ui_help.visible = false))
	ui_help.visible = false
	# ---- WHAT WENT WRONG? (ROADMAP 43): the last refusal, what was tried, why, and the one next step (scripts/whywrong.gd)
	ui_why = PanelContainer.new()
	ui_why.name = "why_panel"
	ui_why.anchor_left = 0.5
	ui_why.anchor_right = 0.5
	ui_why.offset_left = -260
	ui_why.offset_right = 260
	ui_why.offset_top = TOP_H + 30
	ui_root.add_child(ui_why)
	ui_why_box = VBoxContainer.new()
	ui_why_box.custom_minimum_size = Vector2(500, 0)
	ui_why.add_child(ui_why_box)
	ui_why.visible = false
	# ---- CHECK: the findings panel (top right of the view)
	ui_find = PanelContainer.new()
	ui_find.name = "check_panel"
	ui_find.offset_left = LEFT_W + 12   # the left edge of the view: the body (centre) stays in sight while you jump
	ui_find.offset_right = LEFT_W + 12 + 420
	ui_find.offset_top = TOP_H + 12
	var fst := StyleBoxFlat.new()
	fst.bg_color = Tok.c("float")
	ui_find_box = fst
	fst.set_corner_radius_all(8)
	fst.set_content_margin_all(10)
	ui_find.add_theme_stylebox_override("panel", fst)
	ui_root.add_child(ui_find)
	var fsc := ScrollContainer.new()
	fsc.custom_minimum_size = Vector2(400, 0)
	fsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui_find.add_child(fsc)
	ui_find_list = VBoxContainer.new()
	ui_find_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_find_list.add_theme_constant_override("separation", 6)
	fsc.add_child(ui_find_list)
	ui_find.visible = false
	# ---- UNDO HISTORY (round 11): to the right of the findings' place, the same look
	ui_hist = PanelContainer.new()
	ui_hist.name = "history_panel"
	ui_hist.anchor_left = 1.0
	ui_hist.anchor_right = 1.0
	ui_hist.offset_left = -RIGHT_W - 12 - 300
	ui_hist.offset_right = -RIGHT_W - 12
	ui_hist.offset_top = TOP_H + 12
	ui_hist.add_theme_stylebox_override("panel", fst)
	ui_root.add_child(ui_hist)
	var hsc := ScrollContainer.new()
	hsc.custom_minimum_size = Vector2(280, 110)
	hsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui_hist.add_child(hsc)
	ui_hist_list = VBoxContainer.new()
	ui_hist_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsc.add_child(ui_hist_list)
	ui_hist.visible = false
	ui_graph = Control.new()
	ui_graph.anchor_top = 1.0
	ui_graph.anchor_bottom = 1.0
	ui_graph.anchor_right = 1.0
	ui_graph.offset_left = LEFT_W + 12
	ui_graph.offset_right = -RIGHT_W - 12
	ui_graph.offset_bottom = -BOTTOM_H - 92
	ui_graph.offset_top = -BOTTOM_H - 92 - 120
	ui_graph.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_graph.draw.connect(_draw_graph)
	ui_graph.gui_input.connect(_graph_input)
	ui_graph.mouse_exited.connect(func(): _graph_hover = -1.0; ui_graph.queue_redraw())
	ui_graph.visible = false
	ui_root.add_child(ui_graph)
	_lists()


func _lists() -> void:
	ui_poses.clear()
	for dir in ["res://poses/lib", "res://poses", "res://moves"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			if not f.ends_with(".json"):
				continue
			var path: String = dir + "/" + f
			var txt := FileAccess.get_file_as_string(path)
			if txt.contains("\"keys\"") or txt.contains("\"cards\""):
				continue
			var i := ui_poses.add_item(f.get_basename().replace("_", " ") + {"res://poses": "", "res://poses/lib": "   (library)"}.get(dir, "   (yours)"))
			ui_poses.set_item_metadata(i, path)
	if ui_browser != null:
		ui_browser.refresh()
	_fill_scene_list()
	_show_open_scene()


## THE DROPDOWN'S ROWS (ROADMAP 59): the recent scenes first, then every scene; the open scene is selected by _show_open_scene
## (the last row with its file wins, so the picked row is the one in the list proper)
func _fill_scene_list() -> void:
	ui_scenes.clear()
	for p in _recent_list():   # File > Recent (ROADMAP 59): the last scenes opened or saved, first and marked; a missing one greyed
		var i := ui_scenes.item_count
		var miss := not FileAccess.file_exists(p)
		ui_scenes.add_item(p.get_file().get_basename().replace("_", " ") + ("   (missing)" if miss else "   (recent)"))
		ui_scenes.set_item_metadata(i, p)
		ui_scenes.set_item_disabled(i, miss)
	# round 45 (Nick 10-18: his video import "doesn't show on open scene"): the work copies in scenes/_wip (imports,
	# mirrors, polishes) are listed too, marked; opening one picks it, so Delete still trashes only the scene on screen
	for dir in ["res://scenes", "res://moves", "res://scenes/_wip"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".json"):
				continue
			var path: String = dir + "/" + f
			var txt := FileAccess.get_file_as_string(path)
			if txt.contains("\"keys\"") or txt.contains("\"cards\""):
				ui_scenes.add_item(f.get_basename().replace("_", " ") + ("   (work copy)" if dir.ends_with("_wip") else ""))
				ui_scenes.set_item_metadata(ui_scenes.item_count - 1, path)


## the list opens: each scene's picture is asked for (a cached one is set at once, the rest are drawn a frame apart)
func _scenes_opening() -> void:
	if thumbs != null:
		for i in ui_scenes.item_count:
			thumbs.request(ui_scenes.get_item_metadata(i))
	_fit_scene_list.call_deferred()   # once the popup has its place: its size is set after it is shown


## the list is never taller than the window (less a margin): past that it scrolls, and the open scene is in view
func _fit_scene_list() -> void:
	await get_tree().process_frame   # the popup is given its own size on the show: after that frame
	var pop := ui_scenes.get_popup()
	if not pop.visible:
		return
	var cap := int(get_viewport().get_visible_rect().size.y) - 16
	pop.max_size = Vector2i(0, cap)
	pop.size = Vector2i(pop.size.x, mini(pop.size.y, cap))
	await get_tree().process_frame
	if ui_scenes.selected >= 0:
		pop.scroll_to_item(ui_scenes.selected)


## a scene's picture is ready: its row in the list gets it (the row is found by its file, so a re-list in between is safe)
func _thumb_made(path: String) -> void:
	if path == _restore_shown and ui_restore_pic != null and thumbs != null:   # the Restore... dialog's picture
		ui_restore_pic.texture = thumbs.picture(path)
	if ui_scenes == null or thumbs == null:
		return
	var tex := thumbs.picture(path)
	if tex == null:
		return
	var pop := ui_scenes.get_popup()
	for i in ui_scenes.item_count:
		if ui_scenes.get_item_metadata(i) == path:
			pop.set_item_icon(i, tex)


## the dropdown shows the scene that is OPEN (round 9: it kept showing the first file, and Delete scene trashes the
## dropdown's pick, not the open scene). An open scene that is not listed = nothing picked (scenes/_wip is listed
## since round 45, marked "work copy").
var _relisting := false


func _show_open_scene() -> void:
	if ui_scenes == null:
		return
	ui_scenes.select(-1)
	for i in ui_scenes.item_count:
		if ui_scenes.get_item_metadata(i) == scene_path:
			ui_scenes.select(i)
	# a scene written since the list was read (an import, a mirror, a polish: each opens its new file): read it again
	if ui_scenes.selected < 0 and not _relisting and scene_path.begins_with("res://") and FileAccess.file_exists(scene_path):
		_relisting = true
		_lists()
		_relisting = false


# ---------------------------------------------------------------- the right panel

## the weapon in words: "metal bat", "bo staff", "long hammer"
func wep_noun() -> String:
	return {"metal_bat": "metal bat", "staff": "bo staff", "long_hammer": "long hammer"}.get(B.wep_kind, B.wep_kind.replace("_", " "))


## the status bar's line: the picked part and its angles (or the weapon), the card, the playhead, Check's count.
## Public: tests and the CLI read the same words the user sees
func bar_text() -> String:
	if _hover_hint != "":
		return _hover_hint
	var what := ""
	if _num_on:
		what = "TYPE %s = %s_   (it is %.1f)   Tab: next axis   Enter: done   Esc: cancel the drag" % [NUM_AXES[_num_axis], _num_text, (B.ang[sel] as Vector3)[_num_axis]]
	elif _bar_hover != "" and _bar_hover != sel:
		what = "pointing at the %s  (click: pick it, drag: turn it)" % (wep_noun() if _bar_hover in Body.WEAPON else nice(_bar_hover))
	elif sel in Body.WEAPON:
		what = wep_noun() + ("  in the " + nice(B.wep_hand) if B.wep_hand != "" else "  free")
	else:
		var v: Vector3 = B.ang[sel]
		what = "%s  swing %.0f  raise %.0f  roll %.0f" % [nice(sel), v.x, v.y, v.z]
		if not sel_more.is_empty():
			what += "   (+ %d more turn with it)" % sel_more.size()
	var card := "no cards" if S.cards.is_empty() else ("card %d / %d" % [sel_card + 1, S.cards.size()] if sel_card >= 0 else "%d cards, none picked" % S.cards.size())
	var t := PreviewRange.time_text(playhead, _ps().length(), S.fps, frames_view)
	var fails := findings.filter(func(f): return f["sev"] == "FAIL").size()
	var chk := "Check: not run" if not check_ran else ("Check: clean" if findings.is_empty() else "Check: %d (%d must fix)" % [findings.size(), fails])
	if check_ran and undo.size() != check_at:
		chk += ", changed since"
	return "   |   ".join([what, card, t, chk])


func _attr_field(nm: String, v: String, tip: String) -> LineEdit:
	var e := LineEdit.new()
	e.name = nm
	e.text = v
	e.custom_minimum_size.x = 56
	e.tooltip_text = tip
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


## ROADMAP 82: the picked part's attributes. The rows are rebuilt only when the part or its attributes change, so a drag
## keeps its slider; the values follow the playhead on every refresh.
func _attr_refresh() -> void:
	if ui_attr_box == null:
		return
	var names: Array = CustomAttr.names_on(S.attrs, sel) if sel in Body.ORDER else []
	var sig := sel + "|" + str(names)
	for n in names:
		var a: Dictionary = S.attrs[CustomAttr.id_of(sel, n)]
		sig += "|%s:%s:%s" % [a["min"], a["max"], a["default"]]
	if sig != _attr_sig:
		_attr_sig = sig
		for c in ui_attr_box.get_children():
			ui_attr_box.remove_child(c)
			c.queue_free()
		ui_attr_sliders.clear()
		for n in names:
			var id := CustomAttr.id_of(sel, n)
			var a: Dictionary = S.attrs[id]
			var box := VBoxContainer.new()
			var r := _prop_row(box)
			var s := HSlider.new()
			s.name = "attr_" + n
			s.min_value = float(a["min"])
			s.max_value = float(a["max"])
			s.step = 0.01
			s.drag_started.connect(_push_undo)
			s.value_changed.connect(_on_attr.bind(id))
			_row_slider(r, s)
			s.add_theme_stylebox_override("slider", _attr_track())   # a track that shows at 0 in both palettes
			ui_attr_box.add_child(box)
			ui_attr_sliders[id] = [s, r]
			_row(box, [_button("delete %s" % n, _do.bind(_attr_delete.bind(id)), "remove %s from %s and its keys: one undo step (Ctrl+Z brings it back)" % [n, sel])])
	for n in names:
		var id := CustomAttr.id_of(sel, n)
		var t := clampf(playhead, 0.0, S.length())
		var v := CustomAttr.value_at(S.attrs, id, t)
		var keys: Array = S.attrs[id]["keys"]
		(ui_attr_sliders[id][0] as HSlider).set_value_no_signal(v)
		_set_prop(ui_attr_sliders[id][1], n, "%.2f" % v,
			"%s on %s: %d key%s; the value at the playhead. Drag the slider to key it there" % [n, sel, keys.size(), "" if keys.size() == 1 else "s"])


## the slider's track: a text-tinted strip (Tok "text:0.45"), so it reads at value 0 in the dark and the light palette
func _attr_track() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.of("text:0.45")
	sb.set_corner_radius_all(3)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


## "delete" on an attribute row (one undo step)
func _attr_delete(id: String) -> void:
	CustomAttr.remove(S.attrs, id)
	_say("deleted %s on %s (Ctrl+Z brings it back with its keys)" % [CustomAttr.name_of(id), CustomAttr.part_of(id)])


## a slider of an attribute: the value is keyed at the playhead (a drag is one undo step: its start takes the step)
func _on_attr(v: float, id: String) -> void:
	if _sync or S.cards.is_empty():
		return
	CustomAttr.key(S.attrs, id, clampf(playhead, 0.0, S.length()), v)
	_after_edit()


## "+ attribute": the picked part gets the named attribute (one undo step). An error names the fix and changes nothing
func _attr_add() -> void:
	var part := sel
	if not (part in Body.ORDER):
		_say("pick a BODY part first: the attribute goes on a joint (hand_r, upperarm_l ...)")
		return
	var nums := [ui_attr_min.text, ui_attr_max.text, ui_attr_def.text]
	var what := ["min", "max", "default"]
	for k in 3:
		if not (nums[k] as String).is_valid_float():
			_say("%s is a number, e.g. 0 or 0.5 (type it in the %s box)" % [what[k], what[k]])
			return
	var mn := float(nums[0])
	var mx := float(nums[1])
	var df := float(nums[2])
	var nm := ui_attr_name.text.strip_edges().to_lower()
	var probe: Dictionary = S.attrs.duplicate(true)
	var e := CustomAttr.define(probe, part, nm, mn, mx, df)
	if e != "":
		_say(e)
		return
	_do(func(): CustomAttr.define(S.attrs, part, nm, mn, mx, df))
	ui_attr_name.text = ""
	_say("added %s on %s (%s to %s, default %s): drag its slider at a card to key a value" % [nm, part, mn, mx, df])


## the pose's mirror (M / N, the buttons) and its attributes: the source side's attributes are copied to the twin parts
func _mirror_side(from_side: String) -> void:
	B.mirror_side(from_side)
	CustomAttr.copy_side(S.attrs, from_side)


func _panel() -> void:
	if ui_title == null:
		return
	_sync = true
	if sel in Body.WEAPON:
		_panel_bat()
	else:
		_panel_part()
	_attr_refresh()   # ROADMAP 82: the picked part's attribute sliders at the playhead
	ui_time.max_value = maxf(_ps().length(), 0.01)
	ui_time.value = playhead
	ui_time_lbl.text = PreviewRange.time_text(playhead, _ps().length(), S.fps, frames_view)
	if ui_ease != null:
		_grey(ui_ease, "this scene is Smooth (spline): one curve through every card sets the timing; turn Smooth off to ease card by card" if S.spline
			else ("pick a card first (click one in the scene row): the ease is the move INTO that card" if sel_card < 0
			else ("the first card has no move into it: pick card 2 or later" if sel_card == 0 else "")))
		ui_ease.select(Scene.ALL_EASES.find(S.cards[sel_card].get("ease", "smooth")) if sel_card >= 0 and sel_card < S.cards.size() else 0)
		if ui_ease_bias != null:
			var bwhy: String = "" if (not S.spline and sel_card > 0) else "pick card 2 or later with Smooth off: the slider shapes the move INTO a card"
			_grey(ui_ease_bias, bwhy)
			var bv := float(S.cards[sel_card].get("ease_bias", 0.0)) if sel_card > 0 and sel_card < S.cards.size() else 0.0
			if not is_equal_approx(ui_ease_bias.value, bv) and not _ease_bias_armed:
				var was := _sync
				_sync = true
				ui_ease_bias.value = bv
				_sync = was
	if ui_timeline != null:
		ui_timeline.queue_redraw()
	if label_of(ui_play) != ("Stop (Space)" if playing else "Play (Space)"):
		_set_label(ui_play, "Stop (Space)" if playing else "Play (Space)")
		ui_play.icon = Icons.tex("stop" if playing else "play")
	_sync = false


## a section's header (and its rows) shown only where it is about the picked part: BACK for the trunk, HANDS for the
## limbs (round 43, YY4: one more header made the hips' box 314 tall, over the inspector's 300)
func _sec_show(t: String, on: bool) -> void:
	if not ui_secs.has(t):
		return
	(ui_secs[t][0] as Control).visible = on
	if not on and (ui_secs[t][1] as Control).visible:
		_sec_open(t, false)


func _panel_part() -> void:
	var trunk: bool = sel in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"]
	_sec_show("BACK", trunk)
	_sec_show("HANDS", not trunk)
	var v: Vector3 = B.ang[sel]
	var L: Dictionary = B.lim[sel]
	var lims: Array = B.at_limit(sel)
	ui_title.text = nice(sel).to_upper() + ("   (at its limit)" if not lims.is_empty() else "")
	if not sel_more.is_empty():
		ui_title.text += "   + %d more" % sel_more.size()
	ui_lock_btn.visible = true
	_set_label(ui_lock_btn, "Unlock this part" if locked_parts.has(sel) else "Lock this part")
	ui_lock_btn.toggle_mode = true
	ui_lock_btn.set_pressed_no_signal(locked_parts.has(sel))
	if locked_parts.has(sel):
		ui_title.text += "   (LOCKED)"
	if side_col(sel) != SIDE_MID:
		ui_title.add_theme_color_override("font_color", side_col(sel))
	else:
		ui_title.remove_theme_color_override("font_color")
	ui_title.modulate = LIMIT if not lims.is_empty() else Color.WHITE
	ui_how.text = _how(sel)
	var vals := {"bend": v.x, "side": v.y, "twist": v.z}
	var words := {"bend": "SWING", "side": "RAISE / TILT", "twist": "ROLL"}
	for k in ["bend", "side", "twist"]:
		var r: Vector2 = L[k]
		var row: Dictionary = ui_rows[k]
		var free := r.y - r.x > 0.5
		row["box"].visible = free
		if not free:
			continue
		row["slider"].min_value = r.x
		row["slider"].max_value = r.y
		row["slider"].value = vals[k]
		var lk := locked_parts.has(sel)
		row["slider"].editable = not lk
		var say0: String = L["say"].get(k, "")
		row["slider"].tooltip_text = (GREY_TAG + "this part is locked: right-click it > Unlock to change it") if lk else say0.replace("+ = ", "more = ")
		var say: String = L["say"].get(k, "")
		_set_prop(row["label"], words[k], "%.0f deg" % vals[k], say.replace("+ = ", "more = "))
	ui_hip_box.visible = sel == "pelvis"
	ui_pole_row.visible = sel in ["hand_r", "hand_l", "foot_r", "foot_l"]
	(ui_pole_row.get_child(0) as Label).text = ("elbow" if sel.begins_with("hand") else "knee") + "  (Ctrl+drag)"
	var names := ["hips left / right", "hips up / down", "hips forward / back"]
	for k in 3:
		ui_hips[k][0].min_value = -1.0 if k != 1 else -0.9
		ui_hips[k][0].max_value = 1.0 if k != 1 else 0.4
		ui_hips[k][0].value = B.offset[k]
		_set_prop(ui_hips[k][1], names[k], "%.2f m" % B.offset[k])
	if ui_math.visible:
		var A := B.compose(sel, v)
		var con: Array = B.contacts()
		ui_math.text = "%s  bend %.2f° side %.2f° twist %.2f°\nA (turn from rest, rest axes) %s\nG (turn from rest, now) %s\njoint %s   end %s\ncontacts: %s\n(MATH.md explains every number)" % [
			sel, v.x, v.y, v.z, _qs(A), _qs(B.G[sel]), _vs(B.P[sel]), _vs(B.E[sel]),
			"none" if con.is_empty() else ", ".join(con.map(func(c): return "%s/%s %.0f mm" % [c[0], c[1], c[2] * 1000.0]))]


func _panel_bat() -> void:
	ui_lock_btn.visible = false   # the weapon's own lock is L (part locks are for body parts)
	if ui_secs.has("WEAPON") and not (ui_secs["WEAPON"][1] as Control).visible:
		_sec_open("WEAPON", true)   # RR2: the weapon picked: its rows are what the box is about
	var locked := B.wep_hand != ""
	ui_title.remove_theme_color_override("font_color")
	ui_title.text = {"metal_bat": "METAL BAT", "staff": "BO STAFF", "long_hammer": "LONG HAMMER"}.get(B.wep_kind, B.wep_kind.to_upper()) + "  " + ("(locked in the %s)" % nice(B.wep_hand) if locked else "(free)")
	ui_title.modulate = Color.WHITE
	var w := wep_noun()   # round 9: the panel said "bat" for the staff and the hammer too
	ui_how.text = ("LOCKED: the sliders shift the %s inside the hand.  Dragging the %s moves the hand.  'Free it' to move it alone." % [w, w] if locked
		else "FREE: drag = move it,  Shift+drag = turn it,  Alt+drag = spin it.  When it sits right in the fingers: 'Lock bat to hand' (any weapon).")
	var q: Quaternion = B.wep_lrot if locked else B.wep_rot
	var pos: Vector3 = B.knob_in_hand(B.wep_lpos, B.wep_lrot, B.wep_hand) if locked else B.wep_pos   # the sliders read metres in this hand
	var e: Vector3 = Basis(q).get_euler() * (180.0 / PI)
	var words := {"bend": "TILT forward / back", "side": "TURN left / right", "twist": "TILT sideways"}
	var vals := {"bend": e.x, "side": e.y, "twist": e.z}
	for k in ["bend", "side", "twist"]:
		var row: Dictionary = ui_rows[k]
		row["box"].visible = true
		row["slider"].min_value = -180.0
		row["slider"].max_value = 180.0
		row["slider"].value = vals[k]
		_set_prop(row["label"], words[k], "%.0f deg" % vals[k])
	ui_hip_box.visible = true
	ui_pole_row.visible = false
	var span := 0.3 if locked else 2.0
	var names := [w + " left / right", w + " up / down", w + " forward / back"]
	for k in 3:
		ui_hips[k][0].min_value = -span if (k != 1 or locked) else -0.2
		ui_hips[k][0].max_value = span
		ui_hips[k][0].value = pos[k]
		_set_prop(ui_hips[k][1], names[k], "%.3f m" % pos[k], "inside the hand" if locked else "")
	if ui_math.visible:
		var x := B.wep_xform()
		ui_math.text = "knob %s  tip %s\nrotation %s\nin the hand: pos %s rot %s" % [_vs(x[0]), _vs(B.wep_point(B.wep_len)), _qs(x[1]), _vs(B.wep_lpos), _qs(B.wep_lrot)]


static func _qs(q: Quaternion) -> String:
	return "(%.3f, %.3f, %.3f, %.3f) %.1f deg" % [q.x, q.y, q.z, q.w, rad_to_deg(q.get_angle())]


static func _vs(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _on_slider(val: float, k: String) -> void:
	if _sync or locked_parts.has(sel):
		return
	if sel in Body.WEAPON:
		_bat_from_sliders()
		return
	var v: Vector3 = B.ang[sel]
	match k:
		"bend": v.x = val
		"side": v.y = val
		"twist": v.z = val
	B.set_ang_safe(sel, v)
	_arm_edit = sel if sel.begins_with("upperarm") else ""
	_after_edit()


func _on_hip(val: float, k: int) -> void:
	if _sync:
		return
	if sel in Body.WEAPON:
		_bat_from_sliders()
		return
	B.offset[k] = val
	B.fk()
	_after_edit()


func _bat_from_sliders() -> void:
	var e := Vector3(ui_rows["bend"]["slider"].value, ui_rows["side"]["slider"].value, ui_rows["twist"]["slider"].value) * (PI / 180.0)
	var q := Basis.from_euler(e).get_rotation_quaternion()
	var pos := Vector3(ui_hips[0][0].value, ui_hips[1][0].value, ui_hips[2][0].value)
	if B.wep_hand != "":
		B.wep_lrot = q
		B.wep_lpos = B.lpos_from_knob(pos, B.wep_lrot, B.wep_hand)   # stored in default-hand metres (round 52)
	else:
		B.wep_rot = q
		B.wep_pos = pos
	_after_edit()


# ---------------------------------------------------------------- the scene strip

## EXAMPLES (round 12, #80): three finished scenes, opened from the empty state as a COPY: no path, a new name, so
## Save writes a new file and the example is never written
const EXAMPLES := [["walk", "res://scenes/walk_bat.json"], ["swing", "res://scenes/swing_fore.json"], ["dodge", "res://scenes/dodge_side.json"]]


func _open_example(path: String) -> void:
	_load_scene(path)
	scene_path = ""
	S.name = path.get_file().get_basename() + "_mine"
	if ui_scene_name != null:
		ui_scene_name.text = S.name
	_show_open_scene()
	_rebuild_cards()
	_refresh()
	_say("example '%s' opened as a copy: press Play to watch it, change any card, Save scene keeps yours as '%s'" % [path.get_file().get_basename(), S.name])


func _rebuild_cards() -> void:
	_doc_line(true)   # RR1: a load or a new scene changes the strip's name
	if sel_prop >= S.props.size():
		sel_prop = -1
	_props_show()   # SS5: the scene's set
	if ui_cards == null:
		return
	_dummy_hits()   # the cards changed: the landed scene and its hits too
	ov.mark_dirty()
	wt.mark_dirty()
	if ui_browser != null:
		ui_browser.refresh()
	for c in ui_cards.get_children():
		ui_cards.remove_child(c)   # detach now: a freed card_3 would still hold its name for a frame
		c.queue_free()
	_ease_bias_armed = false   # a rebuild (pick, undo, any edit) ends the slider's drag: its next move gets its own undo step
	_layout_bottom()
	if S.cards.is_empty():
		# THREE WAYS IN (round 26, GATES GG1, UPGRADES #47): clip the body as it is, open a scene, or an example (a copy)
		ui_cards.add_child(_label("No clips yet.  Start here:", 16, "text:0.55"))
		for st in [["Clip this pose  (Enter)", _card_add, "the body as it is now becomes clip 1; pose the next moment and clip again, then Play"],
				["Open a scene", func(): ui_scenes.show_popup(), "pick one of your scenes from the list"]]:
			var sb := _button(st[0], st[1], st[2])
			sb.name = "start_" + ("clip" if st[0].begins_with("Clip") else "open")
			sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sb.add_theme_font_size_override("font_size", 13)   # fits the collapsed row (26 px)
			ui_cards.add_child(sb)
		ui_cards.add_child(_label("   or try one:", 16, "text:0.55"))
		for ex in EXAMPLES:
			var eb := _button("Example: " + ex[0], _open_example.bind(ex[1]), "open '%s' as a copy to look at and change; Save makes a new file, the example stays as it is" % ex[1].get_file().get_basename())
			eb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			eb.add_theme_font_size_override("font_size", 13)   # fits the collapsed row (26 px): the empty panel keeps its height
			ui_cards.add_child(eb)
	var ts := S.times()
	for i in S.cards.size():
		var c: Dictionary = S.cards[i]
		var pc := PanelContainer.new()
		pc.name = "card_%d" % (i + 1)   # a named scope: card_3/.../b_update (U2)
		var st := StyleBoxFlat.new()
		st.bg_color = Tok.c("card_sel") if i in card_range() else (Tok.c("card_passby") if c["name"] == "pass-by" else Tok.c("card"))
		st.set_corner_radius_all(6)
		st.set_content_margin_all(6)
		pc.add_theme_stylebox_override("panel", st)
		pc.custom_minimum_size = Vector2(196, 0)
		ui_cards.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		pc.add_child(v)
		var nb := _button("%d  %s" % [i + 1, c["name"]], _card_pick.bind(i), "show this moment (at %.2f s)" % ts[i][1])
		nb.name = "b_pick"   # not from its text: the card's name changes
		nb.tooltip_text += ".  Double-click to rename it"
		nb.gui_input.connect(_card_title_input.bind(i, nb))   # V3: a card's name, in place
		v.add_child(nb)
		if i > 0:
			var mh := HBoxContainer.new()
			v.add_child(mh)
			mh.add_child(_label("move", 13, "text:0.7"))
			var ms := SpinBox.new()
			ms.min_value = 0.0
			ms.max_value = 5.0
			ms.step = 0.05
			ms.value = maxf(0.0, c["move"])
			ms.suffix = "s" if c["move"] > 0.0 else "s (auto %.2f)" % S.move_time(i)
			ms.custom_minimum_size = Vector2(150, 0)
			ms.tooltip_text = "seconds to get here from the card before. 0 = auto (natural time from how far the body moves)"
			ms.value_changed.connect(func(x): _push_undo(); _markers_hold(); S.cards[i]["move"] = x if x > 0.0 else -1.0; _markers_follow(); _retimed())
			mh.add_child(ms)
		var hh := HBoxContainer.new()
		v.add_child(hh)
		hh.add_child(_label("hold", 13, "text:0.7"))
		var hs := SpinBox.new()
		hs.min_value = 0.0
		hs.max_value = 5.0
		hs.step = 0.05
		hs.value = c["hold"]
		hs.suffix = "s"
		hs.tooltip_text = "seconds the body stays still in this pose"
		hs.value_changed.connect(func(x): _push_undo(); _markers_hold(); S.cards[i]["hold"] = x; _markers_follow(); _retimed(false))
		hh.add_child(hs)
		var bh := HBoxContainer.new()
		v.add_child(bh)
		bh.add_child(_button("<", _card_move.bind(i, -1), "move this card earlier"))
		bh.add_child(_button(">", _card_move.bind(i, 1), "move this card later"))
		bh.add_child(_button("Update", _card_update.bind(i), "replace this card's pose with the body as it is now"))
		bh.add_child(_button("X", _card_del.bind(i), "delete this card"))


## ROADMAP 55: the picked card's "Slow in ... Even ... Slow out" slider (Scene.ease_bias: -1 arrives slowly, 0 = the curve as it
## is, +1 leaves slowly). It sits in the Play options under the ease dropdown, NOT in the card: two more rows made the picked
## card 51 px taller than the bottom panel's budget (BOTTOM_H), the panel ran off the screen and the strip's buttons with it.
## The slider previews while it is dragged and is one undo step per drag; 0 erases the key (old scenes save unchanged)
func _gear_ease_bias(gv: Control) -> void:
	var br := HBoxContainer.new()
	gv.add_child(br)
	br.add_child(_label("Slow in", 11, "text:0.6"))
	var sl := HSlider.new()
	sl.name = "card_ease_bias"
	sl.min_value = -1.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.custom_minimum_size = Vector2(110, 22)
	sl.focus_mode = Control.FOCUS_NONE
	sl.tooltip_text = "Slow in ... Even ... Slow out: the move INTO the picked card. Left = it arrives slowly (the first half covers most of the distance), middle = the ease as it is, right = it leaves slowly (the first half covers little).  Drag = a preview; one drag is one Ctrl+Z"
	sl.value_changed.connect(func(x): if not _sync: _ease_bias_drag(sel_card, x))
	sl.drag_ended.connect(func(_c): _ease_bias_armed = false)
	br.add_child(sl)
	br.add_child(_label("Slow out", 11, "text:0.6"))
	ui_ease_bias = sl


## the slider moved on card i: the first move of a drag pushes the undo step; the rest of the drag previews it
func _ease_bias_drag(i: int, x: float) -> void:
	if i <= 0 or i >= S.cards.size() or S.spline:
		return
	if not _ease_bias_armed:
		_push_undo()
		_ease_bias_armed = true
	Scene.set_ease_bias(S.cards[i], x)
	_retimed(false)
	var v := float(S.cards[i].get("ease_bias", 0.0))
	var what := "even (the ease as it is)" if absf(v) < 0.005 else ("slow in: arrives slowly" if v < 0.0 else "slow out: leaves slowly")
	_say("card %d: %+.2f, %s.  Ctrl+Z undoes" % [i + 1, v, what])


## (round 7) the four card edits push an undo step: a card's X could not be undone ("we always have ctrl+z")
func _card_add() -> void:
	_push_undo()
	var nm := ui_pose_name.text.strip_edges()
	var at := sel_card + 1 if sel_card >= 0 else -1
	S.add(nm if nm != "" else "pose %d" % (S.cards.size() + 1), B.to_dict(), at)
	sel_card = at if at >= 0 else S.cards.size() - 1
	playhead = S.times()[sel_card][1]
	_rebuild_cards()
	_refresh()
	_say("added card %d.  Pose the next moment and add it too, then Play." % (sel_card + 1))


func _card_pick(i: int) -> void:
	_push_undo()
	_tween_armed = false   # a new card: its first tween nudge gets its own undo step
	_ease_bias_armed = false
	sel_card = i
	sel_end = -1
	playing = false
	playhead = S.times()[i][1]
	Scene.put(B, Moves._flat(S.cards[i]["pose"]))
	_rebuild_cards()
	_refresh()
	_say("card %d '%s': change the body, then 'Update' on the card to keep it" % [i + 1, S.cards[i]["name"]])


## the ViewCube sits in the view's top-right corner: left of the right panel, or the screen's corner in big view
func _place_cube() -> void:
	if ui_cube == null:
		return
	var r := rw() + 10.0
	ui_cube.offset_right = -r
	ui_cube.offset_left = -r - ViewCube.SIZE
	ui_cube.offset_top = TOP_H + 8
	ui_cube.offset_bottom = TOP_H + 8 + ViewCube.SIZE


## the ring for part j at screen point p: up = reset, then clockwise. The part is selected first (what the ring acts on)
func _ring_open(j: String, p: Vector2) -> void:
	sel = j
	playing = false
	_refresh()
	var side := "_r" if j.ends_with("_r") else ("_l" if j.ends_with("_l") else "")
	var other := {"_r": "left", "_l": "right"}
	var its := [
		{"name": "Reset
(R)", "run": _do.bind(_reset_part)},
		{"name": "Snap 90
(Q)", "run": _do.bind(_snap.bind(90.0))},
		{"name": ("Copy to
%s side" % other[side]) if side != "" else "Mirror
whole pose", "run": _do.bind(_mirror_side.bind(side)) if side != "" else _tool.bind(0)},
		{"name": "CLIP
this pose", "run": _card_add},
		{"name": "Pin a
trail here", "run": _press.bind(KEY_T, true)},
		{"name": "Snap 45", "run": _do.bind(_snap.bind(45.0))},
		{"name": ("Unlock
this part" if locked_parts.has(j) else "Lock
this part"), "run": _toggle_lock.bind(j)},
	]
	ui_ring.open(p, nice(j), its)


## show one ribbon tab's tools
func _ribbon(t: String) -> void:
	for k in RIBBON:
		ui_ribbon[k].visible = k == t
		ui_ribbon_tabs[k].set_pressed_no_signal(k == t)   # by hand: _no_signal does not release the group's others
	_ribbon_tab = t
	_fit_top()
	_place_caps.call_deferred()


## a tab's tools in its groups' order with a thin divider between groups (RR1); unnamed tools stay at the end
func _group(t: String) -> void:
	var row: HBoxContainer = ui_ribbon[t]
	var at := 0
	var gs: Array = RIBBON_GROUPS.get(t, [])
	for gi in gs.size():
		if gi > 0:
			var sep := VSeparator.new()
			sep.name = "group_sep"
			sep.custom_minimum_size.x = 12
			row.add_child(sep)
			row.move_child(sep, at)
			at += 1
		for lab in gs[gi][1]:
			for c in row.get_children():
				if c is Button and label_of(c) == lab:
					row.move_child(c, at)
					at += 1
					break


## each caption under its group: from its first shown tool's left to its last's right; none shown -> hidden
func _place_caps() -> void:
	for t in ui_caps:
		for pair in ui_caps[t]:
			var cap: MenuButton = pair[0]
			var shown: Array = (pair[1] as Array).filter(func(b): return (b as Control).is_visible_in_tree())
			cap.visible = t == _ribbon_tab and not shown.is_empty()
			if not cap.visible:
				continue
			var par := cap.get_parent() as Control
			var x0: float = (shown[0] as Control).get_global_rect().position.x - par.global_position.x
			var x1: float = (shown[-1] as Control).get_global_rect().end.x - par.global_position.x
			cap.position = Vector2(x0, 0)
			cap.size = Vector2(maxf(x1 - x0, cap.get_minimum_size().x), CAP_H)


## a tool picked by name from a menu (a caption's, or More's): the same as pressing it; a menu tool opens its own
## menu where the picker was
func _run_tool(b: Control, at: Control) -> void:
	if b is MenuButton:
		var pm := (b as MenuButton).get_popup()
		(b as MenuButton).about_to_popup.emit()
		pm.position = Vector2i(at.get_screen_position() + Vector2(0, at.size.y))
		pm.popup()
	elif b is Button:
		(b as Button).pressed.emit()


## THE TOP BAR ON A SMALL WINDOW (round 21, GATES BB1, UPGRADES #4): at 1280 x 720 the ANIMATE and VIEW tabs pushed
## History, Search and Help off the window. When the bar does not fit: first COMPACT (each label loses its "(key)":
## the key stays in the tooltip, on the ? list and in Search), then the tab's last tools go into a "More" menu, last
## first, until it fits. Run on a tab switch, a resize and a UI size change. Widths are summed from each control's own
## minimum (a container's cached minimum lags a text change by a frame)
var ui_tb: HBoxContainer
var ui_top_right: Array = []
var ui_more: MenuButton
var _ribbon_tab := "POSE"
var _more_tools: Array = []   # the tools now in More, in order


func _min_w(n: Control) -> float:
	if not n.visible:
		return 0.0
	if n is BoxContainer:
		var w := 0.0
		var k := 0
		for c in n.get_children():
			if c is Control and (c as Control).visible:
				w += _min_w(c)
				k += 1
		return w + maxf(0, k - 1) * n.get_theme_constant("separation")
	return maxf(n.get_minimum_size().x, n.custom_minimum_size.x)


func _top_fits() -> bool:
	# the room: to the window's right edge less the top panel's own right margin (round 22: a fixed 6 px was 4 short)
	# the top panel: the NEAREST PanelContainer up the tree (round 40: since round 36 the row sits in a VBox, so the
	# parent cast was null, the margin read 0 and the bar could run 10 px off the window)
	var right := 0.0
	var pc: Node = ui_tb.get_parent()
	while pc != null and not pc is PanelContainer:
		pc = pc.get_parent()
	if pc != null:
		var sb := (pc as PanelContainer).get_theme_stylebox("panel")
		right = sb.get_margin(SIDE_RIGHT) if sb != null else 0.0
	var room := get_viewport().get_visible_rect().end.x - right - ui_tb.get_global_rect().position.x
	var w := 0.0
	var k := 0
	for c in ui_tb.get_children():
		if c is Control and (c as Control).visible:
			k += 1   # every shown child takes a gap, the expanding filler too (round 22: it was left out, 6 px short)
			if not ((c as Control).size_flags_horizontal & Control.SIZE_EXPAND):
				w += _min_w(c)
	return w + maxf(0, k - 1) * ui_tb.get_theme_constant("separation") <= room


func _fit_top() -> void:
	if ui_tb == null:
		return
	_place_caps.call_deferred()   # the captions follow whatever this pass hides
	var all: Array = []
	for t in RIBBON:
		all.append_array(ui_ribbon[t].get_children())
	all.append_array(ui_top_right)
	for b in all:
		if b is Button and b.has_meta("full"):
			b.text = b.get_meta("full")
	var tools: Array = ui_ribbon[_ribbon_tab].get_children().filter(func(c): return c is Button)
	for b in ui_ribbon[_ribbon_tab].get_children():
		(b as Control).visible = true
	ui_more.visible = false
	_more_tools = []
	if _top_fits():
		return
	for b in all:
		if b is Button and " (" in b.text:
			b.set_meta("full", b.text)
			if b.tooltip_text == "":
				b.tooltip_text = b.text
			elif not b.text in b.tooltip_text:
				b.tooltip_text = b.text + ": " + b.tooltip_text
			b.text = b.text.get_slice(" (", 0)
	ui_more.visible = true
	var k := tools.size() - 1
	while not _top_fits() and k >= 0:
		(tools[k] as Control).visible = false
		_more_tools.push_front(tools[k])
		k -= 1
	var row: Array = ui_ribbon[_ribbon_tab].get_children()
	for i in row.size():   # a group divider after the last shown tool goes too
		if row[i] is VSeparator:
			var after: Array = row.slice(i + 1).filter(func(c): return c is Button and (c as Control).visible)
			(row[i] as Control).visible = not after.is_empty()
	if _more_tools.is_empty():
		ui_more.visible = false
		return
	var pm := ui_more.get_popup()
	pm.clear()
	for i in _more_tools.size():
		pm.add_item(label_of(_more_tools[i]), i)


## a tool picked from More: the same as pressing it (a menu tool opens its own menu where More is)
func _more_pick(i: int) -> void:
	_run_tool(_more_tools[i], ui_more)   # a toggle too: its action is on pressed, and _refresh lights it from the state


## the bottom panel's height follows the scene: no clips = the scene row and the hint, nothing else. Everything that
## stands on the panel (side panels' bottoms, the status line, the speed graph, the camera's centring) moves with it
func _layout_bottom() -> void:
	if ui_bp == null or ui_status == null or ui_bar == null or ui_graph == null or ui_timeline == null:   # mid-build
		return
	var empty := S.cards.is_empty()
	var folded: bool = fold["bottom"] and not empty
	bottom_h = BOTTOM_EMPTY if empty else (BOTTOM_FOLDED if folded else BOTTOM_H)
	ui_bh.visible = not folded and not easy.on
	if not empty:
		bottom_h += int(ui_timeline.clip_px() + _tl_under_ruler())   # CLIPS: the panel grows by the strips' rows (none: as before); the frame strip and the boxes lane too (ROADMAP 12 / 36)
	ui_card_row.visible = not folded
	if ui_fold_btn.has("bottom_open"):
		ui_fold_btn["bottom_open"].visible = folded
		ui_fold_btn["bottom"].visible = not empty
	ui_card_row.custom_minimum_size.y = 26 if empty else 112
	ui_timeline.visible = not empty
	ui_play_row.visible = not empty and not easy.on
	ui_bp.offset_top = -bottom_h
	for p in ui_side + ui_rails.values():
		if p != ui_insp and p != ui_side_of.get("left"):   # RR2 / RR6: the inspector and the browser are as tall as they need
			p.offset_bottom = -bottom_h - 6
	_insp_fit()
	_browser_fit()
	_strip_fit()   # RR5: the line's place follows the panel (the strip's too)
	ui_graph.offset_bottom = -bottom_h - 92
	ui_graph.offset_top = -bottom_h - 92 - 120
	_place_nav()
	_cam()


## a key, as if pressed in the view: a command that has a key runs through the key's own code, so the two never differ
var _pressing := false   # a command chosen from the registry runs its key: no text box's focus may swallow it


## WEAPON TRAILS (ROADMAP 35): the two toggles; the ribbon and the smear are drawn by wt (scripts/weapon_trail.gd)
func _wtrail_ribbon() -> void:
	wt.ribbon_on = not wt.ribbon_on
	_refresh()
	_say(("weapon ribbon on: the bat's sweep over the last %d frames, where the tip is faster than %.0f m/s.  %s" % [wt.n_frames, wt.speed_min, wt.info]) if wt.ribbon_on else "weapon ribbon off")


func _wtrail_smear() -> void:
	wt.smear_on = not wt.smear_on
	_refresh()
	_say(("smear frames on: a stretched copy of the bat on the frames where the tip moves more than %.0f cm.  %s" % [wt.smear_min * 100.0, wt.info]) if wt.smear_on else "smear frames off")


func _press(code: Key, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	# round 46: with the AI box's typing line focused, "Lock weapon to hand" from the search did NOTHING (the key guard
	# below is for TYPING; a chosen command is not typing). undo_audit found it: 3 commands vacuous
	_pressing = true
	_unhandled_input(k)
	_pressing = false


## everything S can find: each runs what its button / key runs. "also" = other words people would type for it.
## THE COMMAND REGISTRY (round 8, GATES O2): each entry also has an "id" (a unique slug, what tools/poser_cli.gd
## and the tests call it by), a one-line "desc" (the search shows it as the tooltip) and "edits": true when it changes
## the body or the scene's cards, so it must be ONE undo step (tests/undo_audit_test.gd holds every command to that).
## KEYS ON ONE SCREEN (round 17, GATES X2): every registry command that has a key, rebuilt from the registry each time
## it opens (a command given a key shows up with nothing else to change), grouped by what you hold: plain keys,
## Shift + a key, Ctrl + a key. ? opens and closes it, Esc closes it
var ui_keys: PanelContainer
var hk: Hotkeys   # HOTKEYS: rebinding, the saved keys, the editor (scripts/hotkeys.gd)


func keys_overlay(on: bool) -> void:
	if ui_keys == null:
		ui_keys = PanelContainer.new()
		ui_keys.name = "keys_overlay"
		var st := StyleBoxFlat.new()
		st.bg_color = Tok.c("float")
		st.set_corner_radius_all(8)
		st.set_content_margin_all(14)
		ui_keys.add_theme_stylebox_override("panel", st)
		ui_root.add_child(ui_keys)
	ui_keys.visible = on
	if not on:
		return
	for ch in ui_keys.get_children():
		ui_keys.remove_child(ch)
		ch.queue_free()
	var v := VBoxContainer.new()
	ui_keys.add_child(v)
	v.add_child(_label("EVERY KEY  (hold ? to see it, let go to hide it; Esc closes it; S finds the rest by name)", 16, "heading"))
	var scr := ScrollContainer.new()   # capped to the room (at 125 % the UI has 720 px): it scrolls rather than run off
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scr)
	var cols := HFlowContainer.new()   # the areas wrap to the width: a row of them, then the next row
	cols.add_theme_constant_override("h_separation", 28)
	cols.add_theme_constant_override("v_separation", 14)
	scr.add_child(cols)
	for g in Hotkeys.cheat_groups(ui_cmd.commands):   # [area, rows]: grouped by what the command is for (scripts/hotkeys.gd)
		var rows: Array = g[1]
		var gv := VBoxContainer.new()
		cols.add_child(gv)
		gv.add_child(_label(String(g[0]).to_upper(), 14, "text:0.7"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		gv.add_child(grid)
		for c in rows:
			var kl := _label(String(c["keys"]), 15, "say")
			kl.name = "key_" + String(c["id"])
			grid.add_child(kl)
			grid.add_child(_label(String(c["name"]), 15, "text"))
	var room := get_viewport().get_visible_rect().size - Vector2(60, 60)
	scr.custom_minimum_size = Vector2(minf(1100.0, room.x - 28), minf(640.0, room.y - 68))
	ui_keys.reset_size()
	ui_keys.position = ((get_viewport().get_visible_rect().size - ui_keys.size) / 2.0).floor()   # centred, after its size is known


func _commands() -> Array:
	var c := []
	var add := func(n: String, keys: String, f: Callable, also: String, edits: bool, desc: String):
		var id := n.to_lower()
		id = id.replace("°", "")   # the degree sign shown in a name is not part of its id (ids are ASCII: they cross the CLI pipe and stay what hotkeys.gd and the docs say)
		for ch in ["/", "(", ")", ",", ":", "%"]:
			id = id.replace(ch, " ")
		c.append({"id": "_".join(id.split(" ", false)), "name": n, "keys": keys, "run": f, "also": also, "edits": edits, "desc": desc})
	for v in [["Front view", 1], ["His right view", 2], ["Top view", 3], ["Back view", 4], ["His left view", 5]]:
		add.call(v[0], str(v[1]), _press.bind(KEY_0 + v[1]), "camera look", false, "camera: %s" % v[0].to_lower())
	add.call("Every key on one screen", "?", keys_overlay.bind(true), "keys shortcuts help cheat sheet hotkeys", false, "a list of every key the poser has, made from this registry (? or Esc closes it)")
	add.call("Pose: draw a line of action", "", _loa_arm, "line of action sketch stroke draw curve spine lean", false, "drag one stroke on the view: the spine and the support leg bend to follow it (Shift on release = mirror the lean; one Ctrl+Z)")
	add.call("Undo", "Ctrl+Z", _undo, "back", false, "take back the last change to the body or the cards")
	add.call("Redo", "Ctrl+Y", _redo, "", false, "put back what Undo took back")
	add.call("Record macro", "", _macro_record, "macro record macros start recording steps", false, "start a macro: every palette command you run from now is a step (with the part picked when it ran); Stop macro recording saves it")
	add.call("Stop macro recording", "", _macro_stop, "macro stop end save finish recording", false, "save the macro being recorded under its name; it then shows in the S box as 'Macro: <name>'")
	add.call("Play macro...", "", func(): ui_cmd.open_with("macro:"), "macro play run list saved", false, "the S box lists the saved macros: click or Enter plays one on the part picked now (ONE undo step)")
	add.call("First steps tour", "", _tour_start, "tour help start begin learn new intro guide", false, "five steps that show the poser by doing: click a part, drag it, clip two cards, play, check")
	add.call("Help: show the tour", "", easy.tour_start, "help tour easy beginner first steps learn guide intro", false, "the Easy tour: five steps (drag a hand, key the pose, move the playhead, key again, play), each moved on by doing it")
	add.call("Mode: Easy (12 buttons, large)", "", easy.set_on.bind(true), "easy beginner simple mode buttons hide panels", false, "hide the panels and tools; the 12 buttons stay large (remembered)")
	add.call("Mode: Expert (every panel and tool)", "", easy.set_on.bind(false), "expert advanced full mode panels all tools", false, "every panel and tool back, as before (remembered)")
	add.call("Edit: undo history...", "", _toggle_history, "steps list back forward", false, "every change by name, as a tree: branches where an edit came after an undo; click one to jump to exactly that state")
	add.call("Save pose", "Ctrl+S", _save_pose, "store keep", false, "save the body as a pose file in poses/ (the Poses list)")
	add.call("Pose library", "", PoseLibrary.toggle.bind(self), "poses thumbnails pictures grid blend mix flipped mirrored apply studio library", false, "every saved pose as a picture: click to apply, drag right on it to blend 0-100 %, Ctrl = flipped, only the selected parts")
	add.call("CLIP this pose (add a card)", "Enter", _press.bind(KEY_ENTER), "key frame add new", true, "add the body as a new card after the picked one")
	add.call("Play / pause", "Space", _press.bind(KEY_SPACE), "run stop", false, "play the scene from the playhead, or stop it")
	add.call("Big view (hide the panels)", "Tab", _press.bind(KEY_TAB), "fullscreen", false, "hide the side panels so the body gets the whole window")
	add.call("Keyboard: the panels by keys", "F6", _kb_enter, "keyboard", false, "Tab / Shift+Tab move from control to control, Enter or Space presses, Esc gives the keys back to the view")
	add.call("Reset the part", "R", _press.bind(KEY_R), "zero", true, "the picked part back to straight (0°, 0°, 0°)")
	add.call("Snap to floor", "", _floor_snap, "floor ground snap stand sole foot knee lift sink drop touch pose root", true, "the picked card (or the body) moves straight up or down so its lowest point (sole, knee, hip or hand) is on the floor; the joints stay")
	add.call("Snap to floor: all cards", "", _floor_snap.bind(true), "floor ground snap all cards every range sole foot knee lift sink", true, "every card moves straight up or down so its lowest point is on the floor; the joints stay; one undo step")
	add.call("Key the part here", "K", _press.bind(KEY_K), "part key keyframe channel", true, "a part key: the picked part's 3 angles at the playhead, over the cards' blend (WW1)")
	add.call("Spine IK: spline the back here", "", _spine_pin, "spine ik spline curve bezier back bend chest hip mid vertebrae twist", true, "the picked back part's spine becomes a curve through a hip, a mid-back and a chest handle: drag the handles and the back bends along it, bones keeping their length, twist spread from hip to chest, every joint inside its limits")
	add.call("Spine IK: spline off here", "", _spine_off, "spine ik spline off release curve back unlock", true, "the back follows the cards again from the playhead (over the last frame)")
	add.call("IK: pin the picked hand/foot here", "", _ik_pin, "ik inverse kinematics pin lock plant stick hand foot target pole table wall contact world space", true, "the picked limb's hand (or foot) stays where it is now from the playhead on, whatever the body does; its elbow (knee) keeps to the side it bends now (a pole)")
	add.call("IK: contact mode on/off (a hand slides on a wall or table)", "", _ik_contact_toggle, "ik contact wall table slide surface palm hand drag touch", false, "while on, a hand you drag is held on the nearest wall or table of the set with its palm on the surface, so it slides along it instead of passing through; off = the plain pull")
	add.call("IK space: world", "", func(): _ik_space("world"), "ik space switch world follow free hand foot parent child of", true, "the picked hand (or foot) stops following anything: its target is in the world from the playhead, and it does not move at this frame")
	add.call("IK space: chest", "", func(): _ik_space("chest"), "ik space switch chest follow torso spine parent child of hand foot", true, "the picked hand (or foot) follows the chest from the playhead on (its target is stored relative to the chest); it does not move at this frame")
	add.call("IK space: pelvis", "", func(): _ik_space("pelvis"), "ik space switch pelvis hips follow parent child of hand foot", true, "the picked hand (or foot) follows the pelvis from the playhead on; it does not move at this frame")
	add.call("IK space: weapon", "", func(): _ik_space("weapon"), "ik space switch weapon bat sword follow hold second hand parent child of", true, "the picked hand follows the held weapon from the playhead on (use it for the hand that is NOT holding the weapon); it does not move at this frame")
	add.call("IK space: other hand", "", func(): _ik_space("other"), "ik space switch other hand follow clap two hand parent child of", true, "the picked hand (or foot) follows the other hand from the playhead on; it does not move at this frame")
	add.call("IK: release the picked limb here", "", _ik_release, "ik fk unpin unlock free let go release hand foot", true, "the pinned hand (or foot) follows the cards again from the card at the playhead: its pinned pose goes into that card first, so nothing jumps")
	add.call("IK -> FK: match at this frame", "", _ik_to_fk, "ik fk switch match bake blend pop snap rigify", true, "the picked limb leaves IK here: its IK pose goes into the card at the playhead and the IK/FK blend is keyed 0, so the limb does not move at the switch")
	add.call("FK -> IK: match at this frame", "", _ik_to_ik, "ik fk switch match blend pop snap rigify target pole", true, "the picked limb enters IK here: target and pole keyed on the FK hand/foot and elbow/knee, the IK/FK blend keyed 1, so the limb does not move at the switch")
	add.call("IK: snap FK to IK", "", _ik_snap_fk, "ik fk match switch visual key rigify card", true, "the card at the playhead takes the picked limb's IK pose (what you see), the IK keys stay")
	add.call("IK: snap IK to FK", "", _ik_snap_ik, "ik fk match switch target pole rigify", true, "the picked limb's IK target and pole keyed at the playhead where the cards put the limb (the IK weight stays)")
	add.call("Constraint: use the picked part as the target", "", _cons_pick_target, "constraint target parent child of follow look track blender", false, "the picked body part (or the weapon) becomes what the next Child Of follows or the head looks at (a choice, not an edit)")
	add.call("Constraint: target the other fighter's head", "", _cons_target_fighter, "constraint target fighter actor opponent look track", false, "the other fighter's head becomes the target of the next constraint (two fighters)")
	add.call("Constraint: target the picked prop", "", _cons_target_prop, "constraint target prop box door ball chair table carried hold", false, "the picked prop becomes the target of the next constraint (Child Of follows it where it is: carried in a hand, or moved by its keys)")
	add.call("Prop: key its place here", "", _prop_key, "prop key keyframe animate move position turn door ball box set", true, "a key for the picked prop at the playhead: where it is and how it is turned (a door: its swing too); between keys it moves smoothly")
	add.call("Prop: delete its keys", "", _prop_unkey, "prop key keyframe clear remove animation", true, "the picked prop's keys go: it stays where it is at the playhead")
	add.call("Grip: wrap the hand round the picked prop", "", _grip_prop_cmd, "grip wrap hand fingers close round prop ball box cylinder any shape keyframe", true, "the picked hand's fingers close round the picked prop's surface (any shape; a ball, a cylinder, a box, an imported model) and the thumb opposes; the finger poses are keyed at the playhead; one undo step")
	add.call("Door: open 15 deg (key here)", "", _door_swing.bind(15.0), "door swing open hinge push key", true, "the picked door's leaf turns 15 deg more open about its hinge, keyed at the playhead (up to 110 deg)")
	add.call("Door: close 15 deg (key here)", "", _door_swing.bind(-15.0), "door swing close shut hinge pull key", true, "the picked door's leaf turns 15 deg back toward shut, keyed at the playhead (down to -110 deg: the other way)")
	add.call("Constraint: child of the target", "", _cons_child_of, "constraint child of parent follow hold attach hand foot hips prop door hip blender", true, "the picked hand, foot (or the hips) follows the target from the playhead on, keeping where it is from it now; the arm / leg bends to reach")
	add.call("Constraint: head looks at the target", "", _cons_look, "constraint track to look at aim head gaze watch face blender", true, "the head turns to the target from the playhead (over 6 frames), never past the neck's limits")
	add.call("Constraint: keep the picked foot above the floor", "", _cons_floor, "constraint floor ground foot limit sink through blender", true, "the picked foot never goes below the floor, whatever moves it")
	add.call("Constraint: fade out over 6 frames", "", _cons_fade.bind(0.0), "constraint influence off release let go key blend", true, "the picked part's constraint goes from what it is at the playhead to off over 6 frames (no pop)")
	add.call("Constraint: fade in over 6 frames", "", _cons_fade.bind(1.0), "constraint influence on key blend", true, "the picked part's constraint goes from what it is at the playhead to fully on over 6 frames")
	add.call("Constraint: release here keeping the pose", "", _cons_release, "constraint apply visual key release let go keep transform card", true, "the held hand / foot's pose at the playhead goes into the card there, then its constraint is off: it follows the cards without a jump")
	add.call("Constraint: remove the picked part's constraint", "", _cons_remove, "constraint delete remove clear", true, "the last constraint on the picked hand, foot, hips or head is taken off")
	add.call("Driver: use the picked part as the source", "", _drv_pick_source, "driver drive follow source expression link blender", false, "the picked part becomes what the next driver's follower reads (a choice, not an edit)")
	add.call("Driver: the picked part follows the source", "", _drv_follow, "driver drive follow link expression factor blender", true, "the picked part's bend follows the source's bend every frame, factor 1.0 (the factor presets change it)")
	add.call("Driver: factor 0.5", "", _drv_factor.bind(0.5), "driver factor half scale ratio", true, "the picked part's driver: it follows its source at half the source's angle")
	add.call("Driver: factor 2", "", _drv_factor.bind(2.0), "driver factor double scale ratio", true, "the picked part's driver: it follows its source at twice the source's angle")
	add.call("Secondary: add a ponytail", "", _sec_add.bind("ponytail"), "secondary ponytail hair tail sway lag overshoot bake spring", true, "a ponytail hangs from the head and follows it with lag and overshoot; baked to keys")
	add.call("Secondary: add a cloth strip", "", _sec_add.bind("cloth"), "secondary cloth strip belt flap sway lag overshoot bake spring", true, "a cloth strip hangs from the belt and follows the body; baked to keys")
	add.call("Secondary: add a weapon flex (oak bo)", "", _sec_add.bind("bo"), "secondary weapon flex bo staff shaft wobble strike bend bake", true, "a 180 cm oak bo clamped at the right hand bends and settles after a strike; baked to keys")
	add.call("Secondary: bake", "", _sec_bake, "secondary bake keys rebake update animation", true, "bake every secondary item again over the scene (after the animation changed)")
	add.call("Secondary: clear", "", _sec_clear, "secondary clear remove off delete chain", true, "takes every secondary item and its keys off the scene (Ctrl+Z puts them back)")
	add.call("Driver: factor -1", "", _drv_factor.bind(-1.0), "driver factor negative mirror invert opposite", true, "the picked part's driver: it moves the opposite way to its source")
	add.call("Driver: remove the picked part's driver", "", _drv_remove, "driver delete remove clear", true, "the picked part stops following its source (its angle is the card's again)")
	_shot_commands(add)   # THE SHOT CAMERA (shot_camera.gd)
	if clips_ui == null:
		clips_ui = ClipsUI.new(self)
	clips_ui.commands(add)   # CLIPS placed as strips (GAP row 12; scripts/clips_ui.gd)
	if face_ui == null:
		face_ui = FaceUI.new(self)
	face_ui.commands(add)   # THE FACE panel (ROADMAP 74; scripts/face_ui.gd)
	if hitbox_ui == null:
		hitbox_ui = HitBoxesUI.new(self)
	hitbox_ui.commands(add)   # HIT / HURT BOXES per frame (ROADMAP 36; scripts/hit_boxes_ui.gd)
	if mm_ui == null:
		mm_ui = MotionMatchUI.new(self)
	mm_ui.commands(add)   # MOTION MATCHING PREVIEW + coverage report (ROADMAP 33; scripts/motion_match_ui.gd)
	add.call("Bake to cards", "", _bake, "bake flatten curves part keys modifiers export agent frames", true, "flatten the scene into one card per frame as it really plays (part keys, modifiers, floor, pins, layer, breathing baked in; those switches go off), one undo step (DD4)")
	add.call("Reduce part keys (tolerance slider)", "", _keyreduce_popup, "reduce keys key reduction thin decimate simplify dense bake video import tolerance error curve slider", true, "drop the part keys the curve can lose within a tolerance in degrees (every angle channel); the readout shows keys kept and the worst error; one undo step (ROADMAP 68)")
	add.call("Curve editor", "", _curve_toggle, "graph curves keys channel animation", false, "open or close the curve editor: the picked part's part keys drawn as curves; drag a key to change its angle and time (XX2)")
	add.call("Graph editor: every keyed part (channels)", "", _graph_cmd.bind("multi"), "graph editor channels multi several parts curves all f-curves blender", false, "the curve editor shows every part with part keys at once, one coloured channel per part and angle; click a channel to hide or show it (GE1)")
	add.call("Graph editor: normalize", "", _graph_cmd.bind("normalize"), "graph editor normalize normalise -1 1 fit scale curves", false, "draw every curve fitted to -1..1 (display only: the keys are not changed) (GE3)")
	add.call("Part keys: add Cycles modifier", "", _graph_cmd.bind("cycles"), "cycles cycle repeat loop modifier f-curve graph part keys blender", true, "the picked part's keyed span repeats before and after itself, for ever (Blender's Cycles modifier; the keys are not changed) (GE4)")
	for ip in PartKeys.INTERPS:   # KEY INTERPOLATION (XX1)
		add.call("Part key: " + ip + " interpolation", "", _part_curve.bind("interp", ip), "key curve blender graph " + ip, true, "the picked part's key at the playhead leaves toward the next key as " + ip)
	for hd in PartKeys.HANDLES:
		add.call("Part key: " + hd + " handle", "", _part_curve.bind("handle", hd), "key curve bezier blender graph " + hd, true, "the picked part's key at the playhead gets the " + hd + " bezier handle type")
	for inf in PartKeys.INFS:
		add.call("Part keys: " + inf + " infinity", "", _part_curve.bind("inf", inf), "key curve extrapolation blender graph repeat loop " + inf, true, "what the picked part's curve does before its first and after its last key: " + inf)
	for kt in PartKeys.KTYPES:   # ROADMAP 66: the key types (key / breakdown / inbetween)
		add.call("Part key type: " + kt, "", _part_ktype.bind(kt), "key type keyframe breakdown inbetween main " + kt, true, "the picked part's key (or the curve editor's picked keys on it) becomes a " + kt + " key")
	add.call("Breakdown: add a key at the playhead in between", "", _part_breakdown, "breakdown in between key add playhead interpolated pose blender", true, "a breakdown key on the picked part at the playhead, on its curve: the pose does not change")
	add.call("Curve editor: pick only main keys", "", _curve_main_keys, "pick select main keys only retime breakdown inbetween curve", false, "the curve editor picks just its main keys (not breakdowns or in-betweens), so a drag retimes only them")
	add.call("Snap the part to 90°", "Q", _press.bind(KEY_Q), "round", true, "round the picked part's angles to the 90° steps its range allows")
	add.call("Snap the part to 45°", "Shift+Q", _press.bind(KEY_Q, true), "round", true, "round the picked part's angles to the 45° steps its range allows")
	add.call("Copy right side to left", "M", _press.bind(KEY_M), "mirror symmetry", true, "the left arm and leg take the right ones' pose, reflected")
	add.call("Copy left side to right", "N", _press.bind(KEY_N), "mirror symmetry", true, "the right arm and leg take the left ones' pose, reflected")
	add.call("Mirror in place", "", _mirror_in_place, "mirror left right reflect whole scene cards symmetry", true, "the open scene mirrored left <-> right, card by card, as ONE undo step (Ctrl+Z takes it back; nothing is saved)")
	add.call("Mirror the scene (a copy in _wip)", "", _mirror_scene, "mirror copy save file left handed reflect scene wip", false, "a left-handed copy of the scene saved in scenes/_wip and opened; the open scene is untouched")
	for st in SEL_SETS:   # SELECTION SETS (round 28, GATES II2, UPGRADES #67)
		add.call("Select: " + st, "", _select_set.bind(SEL_SETS[st]), "group set several parts together " + st, false, "select %s together: a drag on any of them turns them all" % st)
	add.call("Select: just one part", "", _select_set.bind([]), "group set single clear one", false, "back to the one part the panel shows")
	PartSets.of(self).commands(add)   # the user's own SELECTION SETS and KEYING SETS (scripts/part_sets.gd)
	add.call("Lock / unlock this part", "", _toggle_lock.bind(""), "freeze hold keep unlock protect", false, "a locked part keeps its pose while you change the rest: it cannot be dragged, and Reset or Mirror leave it")
	add.call("Symmetry on / off", "", _toggle_symmetry, "live both sides twin symmetric", false, "while on, dragging a part on one side moves the same part on the other side, reflected")
	add.call("Auto-key on / off", "Ctrl+K", _toggle_autokey, "auto key keyframe record toggle card", false, "while on, a pose change made at the playhead keys a card there (or updates the card on that frame); the 3D view gets a red frame")
	add.call("Look at the picked prop", "", _look_at.bind("prop"), "gaze head neck eyes face turn", true, "the neck and head turn so the gaze points at the picked prop (real gaze shifts: scripts/look_at.gd)")
	add.call("Look at the camera", "", _look_at.bind("camera"), "gaze head neck eyes face turn", true, "the neck and head turn so the gaze points at the camera")
	add.call("Mirror the whole pose", "Shift+M", _press.bind(KEY_M, true), "mirror flip left right", true, "the whole body reflected left <-> right; the weapon changes hands")
	for e in Scene.ALL_EASES:
		add.call("Ease: " + e, "", _set_ease.bind(e), "easing timing curve " + {"smooth": "natural", "linear": "constant even", "in": "slow start accelerate", "out": "slow end decelerate", "snap": "jump cut hit step", "reach": "real arm reach minimum jerk bell", "strike": "punch hit late peak", "throw": "swing pitch proximal distal sequence whip", "settle": "land damped spring sway"}[e], true,
			"the picked card's move eases '%s'" % e)
	# ROADMAP 17: the measured presets, named as the motion they were measured from (docs/research/EASE_PRESETS.md)
	for e in EasePresets.KINDS:
		add.call("Card: ease like a real " + e, "", _set_ease.bind(e), "ease like real human " + e + " motion measured preset", true,
			"the picked card's move into it follows measured %s motion (formula and source: docs/research/EASE_PRESETS.md)" % e)
	add.call("Airborne: this card is in the air", "", _toggle_air, "jump air fly leap hop flight gravity", true, "on/off: from the card before to the card after, the feet leave the floor and the hips fly the arc gravity gives (0.57 s in the air = 40 cm up)")
	add.call("Plant the left foot on this card", "", _toggle_plant.bind("_l"), "pin lock foot slide skate stick floor", true, "on/off: the left foot stays where it stood in the card before (no sliding)")
	add.call("Plant the right foot on this card", "", _toggle_plant.bind("_r"), "pin lock foot slide skate stick floor", true, "on/off: the right foot stays where it stood in the card before (no sliding)")
	add.call("Foot: plant the picked foot from the playhead to the next card", "", _foot_plant_next, "foot plant pin lock slide skate stick floor hold range", true, "the picked foot's sole stays where it is at the playhead until the next card arrives (eases on and off over 3 frames; the leg is re-solved, the pelvis is not touched; a leg that cannot reach is reported)")
	add.call("Foot: plant the picked foot over the selected range", "", _foot_plant_range, "foot plant pin lock slide skate stick floor hold range selected cards", true, "the picked foot's sole stays where it is at the first selected card's arrival, until the last selected card's hold ends (Shift+click a second card to select a range)")
	add.call("Foot: unplant", "", _foot_unplant, "foot unplant free release let go slide skate plant", true, "the picked foot's plant over the playhead is taken off: it follows the cards again")
	add.call("Copy pose", "Ctrl+C", _copy_pose, "clipboard", false, "remember the body's pose (every angle, the hips, and the weapon in its hand) to paste on another card; pasted mirrored, the weapon goes to the other hand")
	add.call("Paste pose", "Ctrl+V", _paste_pose.bind(""), "clipboard", true, "the copied pose onto the body (Update keeps it on the card)")
	add.call("Paste pose mirrored", "Ctrl+Shift+V", _paste_pose.bind("mirrored"), "clipboard flip left right", true, "the copied pose reflected left <-> right")
	add.call("Paste flipped, selected parts", "", _paste_flipped.bind(1.0, true), "clipboard flip left right group only", true, "the copied pose reflected left <-> right, on the selected parts only (every other joint stays)")
	add.call("Paste flipped 50%", "", _paste_flipped.bind(0.5, false), "clipboard flip left right blend half", true, "the copied pose reflected, half of the way from the current pose (angles only)")
	add.call("Paste flipped 50%, selected parts", "", _paste_flipped.bind(0.5, true), "clipboard flip left right blend half group", true, "half of the way to the reflected copied pose, on the selected parts only")
	add.call("Paste to this part", "", _paste_pose.bind("part"), "clipboard arm leg only", true, "the copied pose on the picked part and the parts below it only (an arm, a leg)")
	add.call("Mirror the scene (left-handed copy)", "", _tool.bind(5), "left handed copy", false, "a reflected copy of the scene, saved in scenes/_wip and opened (yours untouched)")
	for st in StyleTransfer.STYLES:
		add.call("Style: make it " + st + "...", "", _style_dialog.bind(st), "style transfer make it %s heavier older tired angrier walk" % st, false, "a copy of this scene in the style (timing, spacing, posture; ROADMAP 25), with an intensity 0-100 %; saved in scenes/_wip and opened (yours untouched)")
	add.call("Body: proportions...", "", _proportions_dialog, "proportions height stature tall short size body limbs arm leg length character ansur woman man female male", false, "a small dialog: a preset (ANSUR II 5th / 50th / 95th, woman or man) or a stature; the cards keep their angles, the feet stay on the floor (PR1)")
	for pk in Proportions.PRESETS:
		add.call("Body: " + Proportions.PRESET_NAMES[pk], "", func(): proportions_set(Proportions.preset(pk)), "proportions height stature body " + pk.replace("_", " "), true, "the body's proportions: %s (ANSUR II stature %.1f cm), the cards retargeted (PR1)" % [Proportions.PRESET_NAMES[pk], float(Proportions.PRESETS[pk]["stature"]) * 100.0])
	add.call("Body: the mannequin's own proportions", "", func(): proportions_set({}), "proportions default reset height body", true, "the body back to the mannequin as shipped (%.1f cm), the cards retargeted (PR1)" % (Proportions.DEFAULT_STATURE * 100.0))
	add.call("Actor: add a second fighter (mirror of this one, facing it)", "", _actor_add, "actor fighter character opponent two second partner duel versus", true, "a second fighter in the scene: this scene mirrored, 150 cm in front, turned to face this one (TC3; Save scene keeps both)")
	add.call("Actor: switch to the next fighter", "", _actor_next, "actor fighter character opponent other active swap", false, "the next fighter becomes the one you pose: its own cards, its own body, its own Ctrl+Z")
	add.call("Pose: copy to the other fighter", "", _pose_to_other.bind(false), "copy pose fighter actor other duplicate transfer", true, "the active fighter's pose at the playhead goes onto the other fighter's card at that moment (a card is made if none); one Ctrl+Z")
	add.call("Pose: copy to the other fighter, mirrored", "", _pose_to_other.bind(true), "copy pose fighter actor other mirror flip left right", true, "the same, reflected left <-> right: the app's own mirror of the pose; one Ctrl+Z")
	add.call("Actor: remove this fighter", "", _actor_remove, "actor fighter character opponent delete", true, "the active fighter leaves the scene (not the hero: the hero is the scene itself); Ctrl+Z brings it back")
	add.call("Ragdoll: fall from here (pins: picked parts)", "", _ragdoll_fall, "ragdoll fall limp knockout drop gravity collapse faint pin hang", false, "the body goes limp and falls from the current pose under gravity, the picked parts held in place; baked as editable cards into a NEW scene in scenes/_wip (ROADMAP 27)")
	add.call("Hits: make the struck fighter react", "", _hit_react, "hit hits react reaction struck fighter impact knock momentum recoil shove", true, "the first hit in the fighters' report on a body part turns the struck fighter by its momentum (0.3-0.6 s), baked as editable cards on its scene; one undo step (ROADMAP 14)")
	add.call("Add marker at the playhead", "", _marker_add, "cue event hit step swoosh note flag sound", true, "a named moment (m1, m2, ...) on the timeline at the playhead; the game export lists it as an event")
	add.call("Delete marker at the playhead", "", _marker_delete, "cue event remove flag", true, "removes the marker within one frame of the playhead")
	add.call("Range rings on/off", "", _rings_toggle, "range rings distance reach arm weapon step in opponent fighter spacing measure guide", false, "floor rings around the picked fighter at its arm reach, arm and weapon reach, and a step-in range; a ring turns bright when the other fighter's nearest part is inside it; the label gives the distance in cm (ROADMAP 38)")
	add.call("Exchange view: fighters' rows and beats", "", _choreo_open, "choreo choreography exchange fight fighters beats reach parry strike guard", false, "one row per fighter on one time line, beats (who strikes whom) with each one's reach and guard; drag a row to shift that fighter")
	add.call("Check: weapon clashes", "", _weapon_clash, "clash parry pass through weapons bat swing contact sparks meet fighters", false, "finds where the two fighters' weapons meet over the timeline: CLASH, PARRY, or PASS-THROUGH (the weapons go through each other: must fix); a spark marks each contact, the report prints the time, point and speed (ROADMAP 37)")
	add.call("Dope sheet", "", _dope_toggle, "keys diamonds rows timing blender breakdown extreme", false, "show or hide the dope sheet: a row of diamonds per body part group; drag a card diamond to retime it")
	add.call("Cycle card key type", "", _ktype_cycle, "breakdown moving hold extreme key blender mark", true, "the picked card becomes the next kind of key: key, breakdown, moving hold, extreme (drawn on the dope sheet)")
	add.call("Next marker", "Ctrl+]", _marker_jump.bind(true), "cue event flag jump", false, "the playhead jumps to the next marker")
	add.call("Previous marker", "Ctrl+[", _marker_jump.bind(false), "cue event flag jump", false, "the playhead jumps to the marker before")
	add.call("Collision shapes on/off", "C", _press.bind(KEY_C), "capsules hit", false, "show the capsules that stop parts going through each other")
	add.call("Motion trail on/off", "T", _press.bind(KEY_T), "path arc", false, "draw the weapon tip's path over the scene")
	add.call("Trail: weapon ribbon on/off", "", _wtrail_ribbon, "trail weapon ribbon sweep blade swipe arc path", false, "a ribbon swept by the bat between its knob and its tip over the last 6 frames, fading; drawn only where the tip is faster than 8 m/s (not the motion trail, T)")
	add.call("Trail: smear frames on/off", "", _wtrail_smear, "trail smear frames motion blur ghost stretch playblast", false, "on a fast frame (the tip moves more than 20 cm in one frame) a ghosted, stretched copy of the bat from the frame before, in the playblast too")
	add.call("Pin a trail on the picked part", "Shift+T", _press.bind(KEY_T, true), "path arc", false, "draw the picked body part's path over the scene (again removes it)")
	add.call("Balance on/off", "Shift+B", _press.bind(KEY_B, true), "centre of mass com feet tip fall weight", false, "the centre of mass over the feet: green inside, amber near the edge, red he tips")
	add.call("Onion skin on/off", "O", _press.bind(KEY_O), "ghost before after", false, "ghosts of the card before (orange) and after (green)")
	add.call("Spacing ghosts on/off", "Shift+O", _press.bind(KEY_O, true), "ghost timing", false, "ghosts every 0.1 s: bunched = slow, spread = fast")
	add.call("Speed graph on/off", "Y", _press.bind(KEY_Y), "curve velocity", false, "tip, hips and head speed over the scene; click it to scrub")
	add.call("Stepped preview on/off", "", _tool.bind(3), "blocking poses", true, "play card to card with no in-betweens (view only, never saved)")
	add.call("Moving holds on/off", "", _tool.bind(4), "drift", true, "during a hold the upper body drifts a little toward the next card (saved with the scene)")
	add.call("Check: could a human do this? (on / off)", "", _human_check, "human limits speed torque balance tipping real possible biomechanics", false, "adds joint speed and tipping against recorded human limits to Check (experimental: the limits are still being verified)")
	add.call("Check the motion", "", _check, "grade problems rules", false, "grade the scene against the rulebook; each finding jumps to its moment")
	add.call("Check: critique the animation", "", _critique, "critique notes anticipation follow-through floaty even timing craft", false, "animation-craft notes that point at frames (NOTE only, never must-fix): anticipation, floaty, dead stop, even timing")
	add.call("Check: stunt load report", "", _stunt_check, "stunt injury load landing impact valgus spine neck fall injury", false, "landing load (body weights), knee valgus, spine compression and flex+twist, neck speed for stunt teams (ROADMAP 24): NOTES only, never must-fix")
	add.call("Check: twinning", "", _twin_check, "twin twins mirror arms legs symmetric robotic", false, "lists the arms or legs that move as exact mirror twins for 0.3 s or more (ROADMAP 19); not part of the default Check")
	add.call("Fix: offset the picked side by 3 frames", "", _twin_fix, "twin offset delay side shift frames", true, "moves the picked side's arm / leg joints 3 frames later over the twinning ranges from Check: twinning (one undo step)")
	add.call("Polish the scene (new copy)", "", _polish, "smooth detail", false, "the detail pass on a copy in scenes/_wip, opened (yours untouched)")
	add.call("Block out a move from words...", "", _words_ask, "text type words phrase prompt describe blocking block out attack move overhead sweep thrust jab uppercut hook axe bat staff hammer dagger step lunge", false, "type a move (\"overhead axe strike, step in\", \"fast jab\", \"staff sweep right\"): the closest of your saved attacks is retrieved and adapted by the app's own ops (mirror, weapon swap + grip, step, retime to docs/ATTACK_RULES.md) into a NEW blocked-out scene in scenes/_wip (ready, anticipation, strike, follow-through, recovery), opened; the status says what it started from and what it could not find")
	add.call("Fix moves through the body", "", _clear_scene, "collision pass", true, "add pass-by cards so no move goes through the body")
	add.call("Breakdowner 25%", "", _breakdowner.bind(0.25), "slerp neighbour tween", true, "the picked card's pose (selected parts, else the whole body) a quarter of the way from the card before to the card after, joint by joint")
	add.call("Breakdowner 50%", "", _breakdowner.bind(0.5), "slerp neighbour tween halfway", true, "the picked card's pose (selected parts, else the whole body) halfway between the card before and the card after, joint by joint")
	add.call("Breakdowner slider", "Shift+E", _breakdowner_popup, "slerp neighbour tween slider overshoot", false, "opens a slider: the picked card between the card before (0) and after (1), joint by joint; past the ends overshoots (-50% to 150%)")
	add.call("Breakdowner 75%", "", _breakdowner.bind(0.75), "slerp neighbour tween", true, "the picked card's pose (selected parts, else the whole body) three quarters of the way from the card before to the card after")
	add.call("Push from the in-between", "Ctrl+E", _inbetween.bind("push"), "breakdown exaggerate tween", true, "the picked card's pose (the selected parts, else the whole body) moves 25% AWAY from the mix of its two neighbours; stops at joint limits and says so")
	add.call("Relax to the in-between", "Alt+E", _inbetween.bind("relax"), "breakdown soften tween", true, "the picked card's pose moves 25% TOWARD the mix of its two neighbours (the selected parts, else the whole body)")
	add.call("Blend to rest pose", "", _inbetween.bind("rest"), "straight zero", true, "the selected parts (else the whole body) 25% of the way to the straight pose")
	add.call("Blend to previous card", "Shift+Alt+E", _inbetween.bind("prev"), "neighbour breakdown", true, "the selected parts (else the whole body) 25% of the way to the card before")
	add.call("Blend to next card", "", _inbetween.bind("next"), "neighbour breakdown", true, "the selected parts (else the whole body) 25% of the way to the card after")
	add.call("Add an in-between card", "", _tween_add, "tween inbetween in-between", true, "a new card halfway between the picked card and the next")
	add.call("Fatigue: slow the fight as it goes...", "", _fatigue_dialog, "fatigue tired slow fight endurance fitness strikes rounds stamina", false, "retimes the scene so strikes late in the fight are slower (up to ~10% in speed for the elite fighters measured, Sensors 2025), with a fitness slider; the hit markers say which cards are strikes; rests (holds of 1.5 s or more) recover (ROADMAP 39)")
	add.call("Retime: scale the range around the playhead...", "", _retime_range_dialog, "retime range playhead scale stretch slow fast tempo speed time percent", true, "scale everything timed in a range (the preview range from the ruler, or the picked cards: cards, keys, plants, IK, layers, props, markers, camera) about the playhead, 50 to 200 %: what is after the range shifts so nothing overlaps; the audio stays put; one undo step (ROADMAP 67)")
	add.call("Slower (10%)", "", _speed.bind(1.1), "timing", true, "the picked card (or the whole scene) 10% slower")
	add.call("Faster (10%)", "", _speed.bind(1.0 / 1.1), "timing", true, "the picked card (or the whole scene) 10% faster")
	add.call("Preview range: start at the playhead", "", _pv_set.bind("in", -1.0), "in point loop section", false, "Play and Loop run only between the in and out points (a view setting: never saved, not an undo step). Also Shift+click on the ruler")
	add.call("Preview range: end at the playhead", "", _pv_set.bind("out", -1.0), "out point loop section", false, "the out point at the playhead. Also Alt+click on the ruler")
	add.call("Preview range: clear", "", _pv_set.bind("clear", -1.0), "in out full length", false, "Play and Loop use the whole scene again")
	add.call("Time readout: seconds or frames", "", _toggle_frames, "timecode f s display", false, "flip the time readout between seconds and frames (a click on the readout does it too); a view setting")
	add.call("Frame rate: next (24, 30, 60 fps)", "", _fps_next, "fps film smooth", true, "the scene's frame rate steps 24, 30, 60 fps and round; every card keeps its seconds (the text says how many are then off a whole frame)")
	add.call("Loop: close the seam", "", _loop_close, "timing", true, "the last card becomes a copy of the first, so a loop's end meets its start (and Loop is turned on)")
	add.call("Point the right hand", "", _do.bind(_hand_point.bind("r")), "finger index point hand curl fist", true, "the right index straight, the other fingers and the thumb curled")
	add.call("Point the left hand", "", _do.bind(_hand_point.bind("l")), "finger index point hand curl fist", true, "the left index straight, the other fingers and the thumb curled")
	add.call("Hand pose: relaxed", "", _pose_pick.bind("relaxed"), "hand pose finger relaxed", true, "the picked hand (or the hand of the picked finger) to the relaxed pose; with cards, keyed at the playhead")
	add.call("Hand pose: open", "", _pose_pick.bind("open"), "hand pose finger open", true, "the picked hand (or the hand of the picked finger) to the open pose; with cards, keyed at the playhead")
	add.call("Hand pose: fist", "", _pose_pick.bind("fist"), "hand pose finger fist", true, "the picked hand (or the hand of the picked finger) to the fist pose; with cards, keyed at the playhead")
	add.call("Hand pose: point", "", _pose_pick.bind("point"), "hand pose finger point", true, "the picked hand (or the hand of the picked finger) to the point pose; with cards, keyed at the playhead")
	add.call("Hand pose: pinch", "", _pose_pick.bind("pinch"), "hand pose finger pinch", true, "the picked hand (or the hand of the picked finger) to the pinch pose; with cards, keyed at the playhead")
	add.call("Hand pose: claw", "", _pose_pick.bind("claw"), "hand pose finger claw", true, "the picked hand (or the hand of the picked finger) to the claw pose; with cards, keyed at the playhead")
	add.call("Hand pose: ok", "", _pose_pick.bind("ok"), "hand pose finger ok", true, "the picked hand (or the hand of the picked finger) to the ok pose; with cards, keyed at the playhead")
	add.call("Hand pose: grip", "", _pose_pick.bind("grip"), "hand pose finger grip", true, "the picked hand (or the hand of the picked finger) to the grip pose; with cards, keyed at the playhead")
	add.call("Block: stepped keys", "", _stage_block, "block blocking stepped keys pose to pose stage plan", true, "step 1 of 3: every card holds until the next (no in-betweens), to pose the key cards and add breakdowns before smoothing")
	add.call("Spline and check", "", _stage_spline, "spline smooth stage finish check polish blocking", true, "steps 2 and 3: the in-betweens come back (the scene's own playback) and Check grades the motion")
	add.call("Compare the walk to real walkers", "", _gait_compare, "gait walk people real compare hip knee ankle band curve normal", false, "plays the walk and measures each hip, knee and ankle against the 42 walkers (Fukuchi 2018); names the ones outside")
	add.call("Layer: keep this change through the whole scene", "", _do.bind(_layer_take), "layer additive offset tweak whole scene non destructive lean", true, "what you changed on the body here (against what the scene plays here) goes onto ONE layer over the whole scene; the cards are not touched")
	add.call("Layer: new additive", "", _do.bind(_layer_new.bind("add")), "layer add additive new animation layer", true, "a new additive layer on top, made active (Maya: animation layers)")
	add.call("Layer: new override", "", _do.bind(_layer_new.bind("over")), "layer override replace new animation layer", true, "a new override layer on top: its angles replace what is below, by its weight")
	add.call("Layer: next", "", _layer_next, "layer active select cycle animation layer", false, "the next layer becomes the one edits go to")
	add.call("Layer: mute", "", _do.bind(_layer_flag.bind("mute")), "layer mute off silence", true, "the active layer stops playing (again: plays)")
	add.call("Layer: solo", "", _do.bind(_layer_flag.bind("solo")), "layer solo only alone", true, "only soloed layers play over the cards (again: off)")
	add.call("Layer: lock", "", _do.bind(_layer_flag.bind("lock")), "layer lock protect", true, "the active layer refuses edits (again: unlocks)")
	add.call("Layer: key the weight here", "", _do.bind(_layer_key_w.bind(-1.0)), "layer weight key influence animate", true, "the active layer's weight keyed at the playhead; it follows its keys over time")
	add.call("Layer: merge down (into the cards)", "", _layer_merge, "layer merge bake flatten collapse apply", true, "every layer goes into the cards' poses and the layers are removed (one undo step)")
	add.call("Layer stronger", "", _do.bind(_layer_weight.bind(0.25)), "layer weight more additive", true, "the layer's weight +0.25 (0..1)")
	add.call("Layer weaker", "", _do.bind(_layer_weight.bind(-0.25)), "layer weight less additive", true, "the layer's weight -0.25 (0 = the scene as the cards play it)")
	add.call("Layer: delete", "", _do.bind(_layer_weight.bind(-9.0)), "layer remove clear additive", true, "the layer goes; the scene plays its cards again")
	add.call("Breathing on/off", "", _do.bind(_breath_set.bind(-1.0)), "breath breathe chest idle alive rest", true, "the chest rises and falls as people's do at rest (15 breaths a minute, ~5 mm at the chest), on top of every pose while it plays")
	add.call("Breathe faster", "", _do.bind(_breath_set.bind(2.0)), "breath breathe rate quicker", true, "2 breaths a minute more (people at rest 12 to 20 breaths a minute; after effort more)")
	add.call("Breathe slower", "", _do.bind(_breath_set.bind(-2.0)), "breath breathe rate calmer", true, "2 breaths a minute fewer")
	add.call("Shoulders follow the arm on/off", "", func(): shoulder_follow = not shoulder_follow; _say("shoulders follow the arm: %s (raising an upper arm past 30 deg lifts and draws back its collarbone, as people's do)" % ("ON" if shoulder_follow else "OFF")), "clavicle collarbone shrug scapula rhythm shoulder", false, "raising an upper arm by hand brings its collarbone up and back (McClure 2001); off = the collarbone stays where you put it")
	add.call("Plant every sliding foot", "", _plant_all, "foot slide skate plant lock feet contact fix all", true, "Check's foot slides, every one planted at once (each as its own Fix would), checked again; one undo step")
	add.call("Ask AI", "", _ai_toggle, "ai llm model chat prompt type words describe gpt claude gemini ollama assistant agent generate make animate", false, "type what should happen and an AI builds the cards on this scene, one Ctrl+Z per step")
	add.call("Audio: add a sound file (wav / ogg / mp3)", "", _audio_ask, "audio sound music wav ogg mp3 voice track waveform lip sync timing import", false, "pick a sound file: it appears under the timeline as a waveform, plays in step with Play and sounds a short slice as you drag the playhead")
	add.call("Lip-sync: from the audio track", "", _lip_from_audio, "lip sync lipsync mouth jaw talk speech audio voice visemes timing", true, "bake a jaw and mouth shapes from the sound (a wav on the timeline): the loudness opens the jaw 0-15 deg, the zero-crossing rate picks closed, round, open or wide; one undo step")
	add.call("Audio: remove the sound", "", _audio_remove, "audio sound delete clear track waveform", true, "take the sound off the timeline (the file stays on disk); one undo step")
	add.call("Audio: louder (+3 dB)", "", _audio_gain.bind(3.0), "audio sound volume gain louder up db", true, "the sound 3 dB louder (about 1.4×), up to +12 dB; in playback and the playblast; one undo step")
	add.call("Audio: quieter (-3 dB)", "", _audio_gain.bind(-3.0), "audio sound volume gain quieter down softer db", true, "the sound 3 dB quieter, down to -30 dB; in playback and the playblast; one undo step")
	add.call("Beats: find the beats in the sound", "", _beats_find, "beats bpm tempo music beat grid downbeat bar audio", true, "find the beats and the tempo of the sound (a wav): marks on the timeline, bars marked when a 4/4 grid is evident; one undo step")
	add.call("Beats: snap the contact cards to the nearest beat", "", _beats_snap, "beats snap contact hit strike align music sync", true, "move each hit (contact) card so it lands on its nearest beat; a card never moves more than 25 % of its own move, else nothing moves; one undo step")
	add.call("Weight: time the swing to the weapon", "", _weight_feel, "weight heavy light weapon mass inertia swing slow fast windup recovery hammer dagger bat feel", true, "retime the wind-up and recovery of the swing by the held weapon's moment of inertia about the shoulder (a heavy weapon is slower, a light one quicker; Cross & Bower: time goes as I^0.27); the hit card and its pose stay; one undo step")
	add.call("Beats: clear the beats", "", _beats_clear, "beats clear remove music", true, "take the beat marks off the timeline; one undo step")
	add.call("Audio: move the sound to start at the playhead", "", _audio_to_playhead, "audio sound offset slide shift sync start align", true, "the sound begins at the playhead's time: slide it to line a hit or a word with a pose; one undo step")
	add.call("Animation from video", "", _video_ask, "video mp4 mov phone clip tracking track person mocap motion capture camera film record webcam", false, "pick a video of a person: the tracker (MediaPipe, on this machine) finds the body in every frame and it arrives as a new scene with the feet planted. Or drop the video on the window")
	add.call("Animation from video (import raw)", "", _video_ask.bind(true), "video raw import no cleanup jitter floor tilt mocap phone clip tracking person", false, "the same video import with no cleanup: the tracker's frames as they came (no jitter filter, no floor level, the card-based foot lock instead)")
	add.call("Live: start the webcam puppet", "", _live_toggle, "live webcam camera puppet track person mirror follow pose body mocap record now real time", false, "your own body in front of the webcam poses the mannequin in real time (MediaPipe on this machine, over 127.0.0.1 only); run it again to stop")
	add.call("Live: record / stop", "", _live_record, "live record stop keep take capture webcam puppet", false, "the first press starts recording what the body does; the next keeps the take as a NEW scene in scenes/_wip, opened (never over one)")
	add.call("Import animation (fbx / glb / gltf / bvh)...", "", _anim_import_ask, "fbx mixamo unreal ue4 ue5 glb gltf bvh animation import retarget skeleton rig mocap motion capture clip", false, "pick an animation file from another skeleton (Mixamo, Unreal, Blender ...): its bones are matched to ours by name, its rest pose and size are allowed for, and it arrives as a NEW scene of cards in scenes/_wip (yours untouched). Or drop the file on the window")
	add.call("Clean up mocap", "", _mocap_clean, "bvh capture foot lock skate slide pop flip cleanup", true, "for a scene with a card per frame (a dropped .bvh): plant the standing feet so they stop sliding, mend one-frame joint pops, and report flips and limbs through the body on the status line (one undo step)")
	add.call("Co-edit: host (one animator per fighter)...", "", _co_host_ask, "co edit live coedit host network lan share multiplayer together", false, "host a live session on your network: one animator per fighter, the host saves the scene (asks first)")
	add.call("Co-edit: join...", "", _co_join_ask, "co edit live coedit join connect guest network lan", false, "join a hosted live session by its address:port (the status line of the host shows it)")
	add.call("Co-edit: stop", "", _co_stop_cmd, "co edit live coedit stop end disconnect leave", false, "end the live session (both scenes keep their work)")
	add.call("Save scene", "Ctrl+Shift+S", _save_scene, "", false, "write the scene to scenes/<name>.json (Enter in the name box does it too)")
	for p in _recent_list():   # File > Recent (ROADMAP 59): the scenes opened or saved, newest first
		var miss := not FileAccess.file_exists(p)
		var how := "%s is not on disk any more: File > Recent drops it when %d newer scenes are opened" % [p.get_file(), RECENT_N]
		if not miss:
			how = "open %s (the same as picking it in the scene list)" % p.get_file()
		add.call("File > Recent: " + p.get_file().get_basename().replace("_", " ") + ("  (missing)" if miss else ""), "", _open_recent.bind(p), "recent open scene file again last", false, how)
	add.call("File > Restore...", "", _restore_open, "restore autosave autosaved unsaved crash lost back earlier kept", false, "the last 5 autosaves (time, scene, cards) with a picture of each: pick one, it opens as a NEW copy in scenes/_wip (never over a file; the scene on screen asks first)")
	add.call("File: restore unsaved work", "", _journal_restore, "journal unsaved recover restore crash lost work back", false, "bring back the work a session left unsaved when Kine did not close cleanly: the state after its last edit, still unsaved (the status line offers it at start)")
	add.call("Export...", "", _export_dialog_open, "export engine target unreal ue5 unity godot blender maya motionbuilder web three raw data format glb bvh usda game", false, "one dialog for every target: pick the engine or tool, see its format, what it needs, the frame rate and a checklist for this scene, then export")
	add.call("Export to game", "", _export_game, "arpg unity posetable game export csharp json", false, "the scene as the game's PoseTable: exports/<scene>.json and .cs, paste-ready (11 bones; hands, feet and fingers do not reach the game)")
	add.call("Export animation (.glb)", "", _export_glb, "gltf glb blender unreal ue5 unity godot universal export fbx", false, "the scene as exports/<scene>.glb, the open 3D standard: the mannequin, its skeleton (UE5 bone names) and the animation, for any engine")
	add.call("Export animation (.fbx)", "", _export_fbx, "fbx autodesk maya motionbuilder unity unreal ue5 blender export skeleton binary", false, "the scene as exports/<scene>.fbx: binary FBX 7.4 in centimetres, the skeleton with UE5 bone names and the animation. Unreal, Unity, Maya and Blender 4.5 read it")
	add.call("Export for Unreal 5...", "", _export_engine.bind("ue5"), "unreal ue5 engine export glb root motion scale centimetres manny delivery", false, "the scene as exports/<scene>_ue5.glb for Unreal 5: root motion on the root bone, units checked (the pre-flight report prints first; docs/research/ENGINES.md)")
	add.call("Export for Unity...", "", _export_engine.bind("unity"), "unity engine export glb gltfast metres delivery", false, "the scene as exports/<scene>_unity.glb for Unity (glTFast): metres and Y up checked (the pre-flight report prints first; docs/research/ENGINES.md)")
	add.call("Export for Godot...", "", _export_engine.bind("godot"), "godot engine export glb skeleton delivery", false, "the scene as exports/<scene>_godot.glb for Godot 4: metres and Y up checked (the pre-flight report prints first; docs/research/ENGINES.md)")
	add.call("Export animation (.usda)", "", _export_usd, "usd usda usdskel openusd pixar omniverse houdini blender export", false, "the scene as exports/<scene>.usda, UsdSkel skeleton animation (no weapons)")
	add.call("Export playblast (video)", "", _export_playblast, "playblast render video mp4 png sequence ffmpeg movie export", false, "render the scene from the current camera, frame by frame at its fps over the preview range (or all of it): a PNG folder in exports/playblast/, and an .mp4 when ffmpeg is installed")
	add.call("Review: export a review page", "", _export_review, "review comments frame notes feedback director page html share local", false, "one self-contained HTML file in exports/review/: the playblast frames, a scrubber, a comment box per frame, and Download comments (.json). Nothing is uploaded")
	add.call("Review: import comments...", "", _review_import_ask, "review comments frame notes feedback director import json markers", true, "pick a comments .json from a review page: each comment becomes a marker on the timeline at its frame (click it to jump; Ctrl+Z undoes)")
	add.call("Export animation (.bvh)", "", _export_bvh, "bvh mocap motion capture blender maya motionbuilder cascadeur retarget export", false, "the scene as exports/<scene>.bvh, the motion-capture format every retargeter reads (the weapons as joints in their hands)")
	add.call("Save a version", "", _save_version, "snapshot history keep copy", false, "the scene as it is now kept as a version (Versions, in the scene row, goes back to one)")
	add.call("New empty scene", "", _new_asked, "", false, "start a new scene with no cards (the open one stays on disk)")
	add.call("New from template...", "", _template_ask, "template starting scene walk run jump punch sword swing new example", false, "pick one of five starting scenes (walk, run, jump, punch, sword swing), each checked against real people's numbers: it opens as a NEW scene in scenes/_wip (never over a scene of yours)")
	add.call("Reset body", "", _do.bind(_reset_all), "t-pose", true, "every joint back to straight and the hips to the origin")
	add.call("Arms down 25°", "", _do.bind(_arms_relaxed), "relax a-pose", true, "both arms relaxed: 25° out from straight down")
	add.call("Dummy on/off", "H", _press.bind(KEY_H), "target enemy mannequin", false, "show or hide the target dummy")
	add.call("Dummy solid / see-through", "", _dummy_solid, "target", false, "solid: the weapon stops on the dummy (impact + rebound); see-through: it passes")
	add.call("Dummy closer", "", _dummy_move.bind(-0.25), "target", false, "move the dummy 25 cm closer")
	add.call("Dummy farther", "", _dummy_move.bind(0.25), "target", false, "move the dummy 25 cm farther")
	add.call("Weapon: metal bat", "", _do.bind(_kind.bind("metal_bat")), "", true, "switch the weapon to the metal bat (84 cm)")
	add.call("Weapon: bo staff", "", _do.bind(_kind.bind("staff")), "", true, "switch the weapon to the bo staff (180 cm)")
	add.call("Weapon: long hammer", "", _do.bind(_kind.bind("long_hammer")), "", true, "switch the weapon to the long hammer (110 cm)")
	add.call("Weapon: long axe", "", _do.bind(_kind.bind("long_axe")), "viking dane axe two handed", true, "switch the weapon to the long axe (120 cm, a bit each side of the tip)")
	add.call("Weapon in right hand", "B", _do.bind(_bat_put.bind("hand_r")), "bat", true, "the weapon into the right hand with its standard grip")
	add.call("Weapon in left hand", "", _do.bind(_bat_put.bind("hand_l")), "bat", true, "the weapon into the left hand with its standard grip")
	add.call("Remove the weapon", "", _do.bind(_bat_remove), "bat none", true, "take the weapon away")
	add.call("Lock weapon to hand / free it", "L", _press.bind(KEY_L), "bat", true, "locked: the weapon moves with the hand; free: drag it to refit")
	add.call("Second hand on the weapon", "G", _press.bind(KEY_G), "two hands grip", true, "the other hand on the shaft, or off it")
	add.call("Main hand to the end", "", _do.bind(_hand_to_end), "grip slide", true, "slide the main hand to the weapon's lower end")
	add.call("Grip lower on the weapon", "[", _do.bind(func(): B.grip_u = clampf(B.grip_u - 0.03, 0.0, B.wep_len)), "hand slide knob", true, "the main hand 3 cm toward the knob")
	add.call("Grip higher on the weapon", "]", _do.bind(func(): B.grip_u = clampf(B.grip_u + 0.03, 0.0, B.wep_len)), "hand slide tip", true, "the main hand 3 cm toward the tip")
	add.call("Slide the hands down the weapon", ",", _do.bind(func(): _slide(-0.03)), "grip choke", true, "both hands 3 cm down the shaft together")
	add.call("Slide the hands up the weapon", ".", _do.bind(func(): _slide(0.03)), "grip choke", true, "both hands 3 cm up the shaft together")
	add.call("Weapon shorter", "-", _do.bind(func(): B.set_weapon_len(B.wep_len - 0.05)), "length size", true, "the weapon 5 cm shorter")
	add.call("Weapon longer", "=", _do.bind(func(): B.set_weapon_len(B.wep_len + 0.05)), "length size", true, "the weapon 5 cm longer")
	add.call("Fingers: next shape", "F", _press.bind(KEY_F), "hand open fist", true, "the picked side's fingers: open -> grip -> fist")
	for side in [["r", "right"], ["l", "left"]]:
		for f in ["open", "grip", "fist", "relaxed"]:
			add.call("Fingers %s: %s" % [side[1], f], "", _do.bind(_fingers.bind(side[0], f)), "hand", true, "the %s hand's fingers: %s" % [side[1], f])
	add.call("Shading: next", "", _shading_next, "solid matcap silhouette xray x-ray look material", false, "draw the body solid, matcap, silhouette or x-ray (a display setting, not saved in the scene)")
	add.call("Light / dark theme", "", func(): _set_light(Tok.dark), "colour white bright night", false, "switch the light and dark look (remembered)")
	for p in SCALES:
		add.call("UI size %d %%" % p, "", _set_scale.bind(p), "zoom bigger smaller scale font text size", false, "buttons and words at %d %% (remembered)" % p)
	add.call("Help", "", func(): ui_help.visible = not ui_help.visible, "how manual", false, "show or hide the help panel")
	add.call("What went wrong?", "", _why_toggle, "why error wrong refused refusal explain not work failed stuck", false, "says what the last refusal or error meant in plain words: what you tried, why it did not work, and the one next step (a button runs it)")
	add.call("Pick a part", "", _select_set.bind(["upperarm_r"]), "pick select choose part body click", false, "picks the right upper arm, so the next command has a part to act on")
	add.call("Help: edit hotkeys", "", hk.open_editor, "hotkeys keys key shortcut shortcuts rebind bind change remap", false, "change any command's key: search, click its key, press the new one (a key another command has is refused until pressed again)")
	return Hotkeys.apply(c, hk.over)   # the keys the user chose (scripts/hotkeys.gd) replace the built-in ones


## EXCHANGE VIEW (ROADMAP 13; scripts/choreo.gd, scripts/choreo_view.gd): one row per fighter, the beats, the reach and
## guard report. Its own Window; every edit here is one undo step (the beats with the hero, a shift with its fighter)
var ui_choreo = null   # ChoreoView while its window is open


## ROADMAP 38: the range rings (scripts/range_rings.gd): the picked fighter's rings against the others, drawn on the floor
func _rings_draw() -> void:
	var others := []
	if rings.on and actors_rt.size() >= 2 and stage_root != null and actor_on < actors_rt.size():
		for k in actors_rt.size():
			if k != actor_on:
				others.append({"name": actors_rt[k]["name"], "B": actors_rt[k]["B"], "W": stage_root.transform * (actors_rt[k]["xf"] as Transform3D)})
	var pW := stage_root.transform * (actors_rt[actor_on]["xf"] as Transform3D) if (rings.on and actors_rt.size() >= 2 and stage_root != null and actor_on < actors_rt.size()) else Transform3D.IDENTITY
	rings.update(B, pW, others)


func _rings_toggle() -> void:
	if not rings.on and actors_rt.size() < 2:
		_say("the range rings need two fighters: Actor: add a second fighter first")
		return
	rings.on = not rings.on
	_refresh()
	if rings.on:
		var r: Dictionary = rings.last["reaches"] if rings.last.has("reaches") else {}
		_say("range rings on: arm %s, arm + weapon %s, step-in %s; the label is the other fighter's nearest part" % [Units.len(float(r.get("arm", 0.0))), Units.len(float(r["weapon"])) if r.get("has_weapon", false) else "(no weapon held)", Units.len(float(r.get("step_in", 0.0)))])
	else:
		_say("range rings off")


func _choreo_open() -> void:
	_actors_sync()
	if actors_rt.size() < 2:
		_say("the exchange view needs two fighters: Actor: add a second fighter first")
		return
	if ui_choreo != null and is_instance_valid(ui_choreo.win):
		ui_choreo.win.grab_focus()
		return
	ui_choreo = ChoreoView.open(self)


## a fighter's whole timeline moved by dt seconds (Choreo.shift). Its scene is made the active one first, so the undo
## step holds its cards. False (nothing done, no undo step) when the shift is not possible
func _choreo_shift(k: int, dt: float) -> bool:
	_actors_sync()
	if k < 0 or k >= actors_rt.size() or absf(dt) < 0.001:
		return false
	var probe: Scene = (actors_rt[k]["S"] as Scene).clone()
	if Choreo.shift(probe, dt) == 0.0:
		return false
	_actor_go(k)
	_push_undo()
	Choreo.shift(S, dt)
	_rebuild_cards()
	_dummy_hits()
	_refresh()
	return true


## the hero's beats: add one at t (who strikes whom), or delete the one at index i. One undo step each
func _choreo_beat_add(t: float, by: int, on: int, name: String) -> void:
	_push_undo()
	Choreo.add(_hero_scene().beats, t, by, on, name)
	_choreo_changed()


func _choreo_beat_del(i: int) -> void:
	var bs: Array = _hero_scene().beats
	if i < 0 or i >= bs.size():
		return
	_push_undo()
	bs.remove_at(i)
	_choreo_changed()


func _choreo_changed() -> void:
	if ui_choreo != null and is_instance_valid(ui_choreo.win):
		ui_choreo.refresh()
	_refresh()


## WEAPON CLASH (ROADMAP 37; scripts/weapon_clash.gd): where the two fighters' weapons meet over the timeline. A spark
## marks each contact in the view; the report prints every event (time, frame, point, speed); a PASS-THROUGH is what
## the animator must fix. The sparks of the last check are replaced by the next one.
var clash_sparks := []   # MeshInstance3D: the sparks of the last check


func _weapon_clash() -> void:
	_actors_sync()
	for sp in clash_sparks:
		if is_instance_valid(sp):
			sp.queue_free()
	clash_sparks.clear()
	var fs := Choreo.fighters_of(self)
	if fs.size() < 2:
		_say("Check: weapon clashes needs two fighters (Actor: add a second fighter first)")
		return
	var ev := WeaponClash.scan(fs, float((fs[0]["S"] as Scene).fps))
	for e in ev:
		var sp := WeaponClash.spark(e["point"])
		add_child(sp)
		clash_sparks.append(sp)
		print(e["text"])
	if ev.is_empty():
		_say("Check: weapon clashes: none, the weapons never meet: move a swing into the other fighter's weapon to test one")
		return
	var through := 0
	for e in ev:
		if e["kind"] == "PASS-THROUGH":
			through += 1
	_say("Check: weapon clashes: %d (%d PASS-THROUGH, must fix). %s" % [ev.size(), through, ev[0]["text"]])


## MARKERS (round 41, GATES WW5, UPGRADES_300 #261): named moments on the timeline (Markers). Add / Delete at the playhead are
## one undo step each; Next / Previous only move the playhead
func _marker_add() -> void:
	_push_undo()
	var mk := Markers.add(S.markers, playhead)
	_markers_changed()
	_say("marker %s at %s (note).  Ctrl+] / Ctrl+[ jump between markers; Ctrl+Z undoes" % [mk["name"], Units.time(mk["t"], S.fps)])


func _marker_delete() -> void:
	var i := Markers.near(S.markers, playhead, 1.0 / float(S.fps))
	if i < 0:
		_say("no marker within one frame of the playhead: press Ctrl+] / Ctrl+[ to move onto one")
		return
	_push_undo()
	var gone: Dictionary = S.markers[i]
	S.markers.remove_at(i)
	_markers_changed()
	_say("marker %s at %s deleted.  Ctrl+Z undoes" % [gone["name"], Units.time(gone["t"], S.fps)])


func _marker_jump(fwd: bool) -> void:
	var t := Markers.next_t(S.markers, playhead) if fwd else Markers.prev_t(S.markers, playhead)
	if t < 0.0:
		_say("no marker %s the playhead: press Ctrl+%s for the other way, or add one with Add marker" % (["after", "["] if fwd else ["before", "]"]))
		return
	playhead = t
	_ps().apply(B, minf(playhead, _ps().length()))
	_refresh()
	_say("marker at %.2f s" % t)


func _markers_changed() -> void:
	if ui_timeline != null:
		ui_timeline.queue_redraw()
	_refresh()


## the timing is about to change: remember it, so the markers ride with the time they sit in
var _mk_old: Array = []
var _mk_list: Array = []
func _markers_hold() -> void:
	_mk_old = S.times().duplicate(true) if not S.markers.is_empty() else []
	_mk_list = S.markers.duplicate(true)


## ... and the timing changed: every marker moves with the card time it was in (Markers.remap)
func _markers_follow() -> void:
	if not _mk_list.is_empty() and _mk_old.size() == S.cards.size():
		S.markers = Markers.remap(_mk_list, _mk_old, S.times())
		if ui_timeline != null:
			ui_timeline.queue_redraw()


## a retime drag begins / goes on (the timeline's edge and the dope sheet's card diamond share this: one undo step, the markers follow)
func _retime_begin() -> void:
	_push_undo()
	_markers_hold()


func _retime_step(final: bool) -> void:
	_markers_follow()
	if final:
		_retimed()
	else:
		S.apply(B, minf(playhead, S.length()))   # live while dragging: the scene as made (the landed copy is rebuilt on release)
		_refresh()


## DOPE SHEET (round 42, GATES XX3, UPGRADES_300 #252 + #253; scripts/dope_sheet.gd): rows of key diamonds. "Dope sheet" opens
## and closes it; "Cycle card key type" sets the picked card's Blender type (key > breakdown > moving hold > extreme); the sheet's
## buttons set one directly. Dragging a card diamond retimes the card through the timeline's own path
var ui_dope: DopeSheet


## NA0: a copy of card i arriving at time t. t must fall inside a card's MOVE (after its start, before its arrival): that
## move is split, the copy arrives at t and the card that owned the move still arrives when it did. One undo step.
func _dope_copy(i: int, t: float) -> bool:
	var ts := S.times()
	var k := -1
	for j in range(1, S.cards.size()):
		if t > float(ts[j][0]) + 1e-6 and t < float(ts[j][1]) - 1e-6:
			k = j
	if k < 0:
		_say("NOT COPIED: drop the copy inside a move (between a card's hold and the next card's arrival), not on a card or a hold")
		return false
	_step_hint = "Copy card"
	_push_undo()
	var c: Dictionary = (S.cards[i] as Dictionary).duplicate(true)
	c["name"] = "%s copy" % S.cards[i]["name"]
	c["move"] = t - float(ts[k][0])
	c["hold"] = 0.0
	var arrive_k := float(ts[k][1])
	S.cards.insert(k, c)
	S.cards[k + 1]["move"] = arrive_k - t
	_rebuild_cards()
	_refresh()
	_say("copied a card to %.2f s; the cards after it arrive when they did. Ctrl+Z takes it back" % t)
	return true


## NA0: the part keys of `joints` at t0 moved (or with `copy`, copied) to t1, whole frames. A moved key stops one frame
## short of a neighbour of the same joint (never onto or past it); a copy onto an existing key replaces that key's value.
## One undo step. Returns how many keys moved / were copied.
func _dope_part(joints: Array, t0: float, t1: float, copy: bool) -> int:
	if absf(t1 - t0) < 1e-6:
		return 0
	_step_hint = "Copy part keys" if copy else "Move part keys"
	_push_undo()
	var fr := 1.0 / float(maxi(S.fps, 1))
	var n := 0
	for j in joints:
		var ks: Array = S.part_keys.get(j, [])
		var idx := PartKeys.key_near(ks, t0, PartKeys.SAME_T)
		if idx < 0:
			continue
		if copy:
			var src: Dictionary = (ks[idx] as Dictionary).duplicate(true)
			PartKeys.put(S.part_keys, j, t1, src["v"])
			var ni := PartKeys.key_near(S.part_keys[j], t1, PartKeys.SAME_T)
			for f in ["interp", "handle", "hin", "hout", "ktype"]:   # ROADMAP 66: a copy keeps the type
				if src.has(f):
					S.part_keys[j][ni][f] = src[f]
			n += 1
			continue
		var lo := (float(ks[idx - 1]["t"]) + fr) if idx > 0 else 0.0
		var hi := (float(ks[idx + 1]["t"]) - fr) if idx < ks.size() - 1 else INF
		ks[idx]["t"] = clampf(t1, lo, hi)
		n += 1
	_refresh()
	_say("%s %d part key%s from %s to %s. Ctrl+Z takes it back" % ["copied" if copy else "moved", n, "" if n == 1 else "s", Units.time(t0, S.fps), Units.time(t1, S.fps)])
	return n


func _dope_toggle() -> void:
	if ui_dope == null:
		ui_dope = DopeSheet.new()
		ui_dope.m = self
		ui_dope.retime_started.connect(_retime_begin)
		ui_dope.retimed.connect(_retime_step)
		ui_dope.picked.connect(_card_pick)
		ui_root.add_child(ui_dope)
	ui_dope.visible = not ui_dope.visible
	if ui_dope.visible:
		var vp := get_viewport().get_visible_rect().size
		var sz := Vector2(minf(980.0, vp.x - 24.0), minf(250.0, vp.y - 24.0))
		ui_dope.custom_minimum_size = sz
		ui_dope.size = sz
		ui_dope.position = Vector2(floorf((vp.x - sz.x) / 2.0), maxf(12.0, vp.y - sz.y - 150.0))
		_say("dope sheet: drag a card diamond to retime it; Cycle card key type marks the picked card")
	else:
		_say("dope sheet closed")


func _ktype_cycle() -> void:
	if sel_card < 0 or sel_card >= S.cards.size():
		_say("pick a card first: click a card on the timeline, then Cycle card key type")
		return
	_ktype_set(DopeSheet.next_kind(DopeSheet.kind_of(S.cards[sel_card])))


func _ktype_set(kind: String) -> void:
	if sel_card < 0 or sel_card >= S.cards.size():
		_say("pick a card first: click a card on the timeline, then choose its key type")
		return
	if DopeSheet.kind_of(S.cards[sel_card]) == kind:
		_say("card %d is already %s: choose another type, or pick another card" % [sel_card + 1, "a plain key" if kind == "key" else "a %s key" % DopeSheet.label_of(kind)])
		return
	_push_undo()
	if kind == "key":
		S.cards[sel_card].erase("ktype")   # a plain key is the absence of the field: the file stays as before
	else:
		S.cards[sel_card]["ktype"] = kind
	if ui_dope != null:
		ui_dope.canvas.queue_redraw()
	_refresh()
	_say("card %d is now %s.  Ctrl+Z undoes" % [sel_card + 1, "a plain key" if kind == "key" else "a %s key" % DopeSheet.label_of(kind)])


## the timing changed (timeline drag, a move/hold box): everything that was built from the old timing is rebuilt.
## rebuild=false keeps the card boxes (a box being typed into must not be freed under the cursor)
func _retimed(rebuild := true) -> void:
	if rebuild:
		_rebuild_cards()   # also: the landed dummy copy + the trail/graph/ghost pass
	else:
		_dummy_hits()
		ov.mark_dirty()
		wt.mark_dirty()
	if ui_find != null and ui_find.visible:
		ui_find.visible = false   # the findings were for the old timing
		_say("timing changed: press Check again to grade the new timing.  Ctrl+Z undoes the change")
	_ps().apply(B, minf(playhead, _ps().length()))
	_refresh()


## a block on the timeline: the same as clicking the card, then the card row scrolls to show it
func _timeline_pick(i: int) -> void:
	_card_pick(i)
	await get_tree().process_frame
	if i < ui_cards.get_child_count():
		(ui_cards.get_parent() as ScrollContainer).ensure_control_visible(ui_cards.get_child(i))


## ANIMATOR TOOLS (round 5, the ten complaints: docs/COMPLAINTS.md)
## IK POLE from the panel: swing, and say how far it got (a contact or a limit can stop it short)
func _pole(deg: float) -> void:
	var w := "elbow" if sel.begins_with("hand") else "knee"
	var got := B.swing_pole(sel, deg)
	_say(("the %s swung %.0f°; the %s stays where it was" % [w, got, nice(sel)]) if absf(got - deg) < 1.0
		else "the %s swung only %.0f of %.0f deg: the limb touches the body there or a joint is at its limit" % [w, got, deg])


## PLANT A FOOT on the picked card (on <-> off): it stays where it stood in the card before (Scene PLANTED FEET). One undo
func _toggle_plant(sd: String) -> void:
	if sel_card < 1 or sel_card >= S.cards.size():
		_say("pick a card after the first: a planted foot stays where it stood in the card before")
		return
	_push_undo()
	var p: Array = S.cards[sel_card].get("plant", []).duplicate()
	var on := not sd in p
	if on:
		p.append(sd)
	else:
		p.erase(sd)
	if p.is_empty():
		S.cards[sel_card].erase("plant")
	else:
		S.cards[sel_card]["plant"] = p
	_retimed()
	_say("card %d: the %s foot %s.  Ctrl+Z undoes" % [sel_card + 1, "left" if sd == "_l" else "right",
		"planted (it stays where it stood in the card before)" if on else "free again"])


## AIRBORNE (round 40, GATES VV1, #230): the picked card is in the air (on <-> off). A run of them between two cards on
## the floor is a jump: Scene FLIGHTS. One undo step; it says the flight time and the height it means
func _toggle_air() -> void:
	if sel_card < 1 or sel_card >= S.cards.size() - 1:
		_say("pick a card with a card before it and after it: a jump leaves the floor after one and lands on the next")
		return
	_push_undo()
	var on: bool = not S.cards[sel_card].get("air", false)
	if on:
		S.cards[sel_card]["air"] = true
	else:
		S.cards[sel_card].erase("air")
	_retimed()
	var tail := "on the floor again"
	for f in S.flights():
		if sel_card > int(f["k"]) and sel_card < int(f["l"]):
			var T := float(f["t1"]) - float(f["t0"])
			tail = "in the air %.2f s: the hips rise %.0f cm (people's standing jump ~40 cm = 0.57 s)" % [T, Scene.G * T * T / 8.0 * 100.0]
	_say("card %d: %s.  Ctrl+Z undoes" % [sel_card + 1, tail])


## EASE PRESET of the picked card (the move into it). One undo step
func _set_ease(kind: String) -> void:
	if sel_card < 1 or sel_card >= S.cards.size():
		_say("pick a card after the first: the ease is how the move INTO it goes")
		return
	if S.spline:
		_say("Smooth (spline) is on: the scene is one curve and cards' ease is not used.  Untick it to ease card by card")
		return
	_push_undo()
	if kind == "smooth":
		S.cards[sel_card].erase("ease")
	else:
		S.cards[sel_card]["ease"] = kind
	_retimed()
	_say("card %d eases '%s' into its pose.  Ctrl+Z undoes" % [sel_card + 1, kind])


func _copy_pose() -> void:
	pose_clip = B.pose_copy()
	_say("pose copied.  Ctrl+V pastes it, Ctrl+Shift+V pastes it mirrored, 'Paste to this part' (S) pastes just one limb")


## how: "" = the whole pose, "mirrored", "part" = the picked part and below. One undo step; nothing copied = nothing done
## LOOK AT (round 42, GATES XX6): the neck and head turn so the gaze points at the picked prop or at the camera
## (scripts/look_at.gd). ONE undo step; the body has no eyes, so the whole turn is the neck's and head's
func _look_at(what: String) -> void:
	var t := Vector3.ZERO
	if what == "prop":
		if sel_prop < 0 or sel_prop >= S.props.size():
			_say("pick a prop first: click it in the view (or Add prop), then Look at the picked prop")
			return
		t = ((S.props[sel_prop]["xf"] as Transform3D).origin) + Vector3(0, 0.3, 0)
	else:
		t = cam.global_position
	var res := {}
	_do(func(): res.merge(LookAt.solve(B, t), true))
	var msg := "looking at the %s: turned the neck and head %.0f deg" % ["picked " + _prop_name(sel_prop) if what == "prop" else "camera", res["head_deg"]]
	if not res["reachable"]:
		msg += "; it is %.1f deg past what the neck and head reach: move the target nearer the front" % res["error"]
	_say(msg + ".  Ctrl+Z undoes; Update keeps it on the card")


func _paste_pose(how: String) -> void:
	if pose_clip.is_empty():
		_say("nothing copied yet: press Ctrl+C on the pose you want first, then Ctrl+V here")
		return
	if how == "part" and not sel in Body.ORDER:
		_say("pick a body part first: the paste goes to it and the parts below it")
		return
	_do(func(): B.pose_paste(pose_clip, how == "mirrored", B.below(sel) if how == "part" else []))
	_say({"": "pose pasted", "mirrored": "pose pasted, mirrored", "part": "pasted to the %s and below" % nice(sel)}[how] + ".  Ctrl+Z undoes; Update keeps it on the card")


## PASTE FLIPPED WITH OPTIONS (round 42, GATES XX4, #282): the copied pose reflected, on the selected parts only and/or
## at a factor; logic in breakdowner.gd; one undo step
## Pose: copy to the other fighter (ROADMAP 53; scripts/pose_copy.gd): the active fighter's pose at the playhead goes onto the
## other fighter's card at that moment (a card is made there when none is). One undo step. mirrored = the app's own mirror
func _pose_to_other(mirrored: bool) -> void:
	_actors_sync()
	if actors_rt.size() < 2:
		_say("there is one fighter: use 'Actor: add a second fighter' first, then copy the pose to it")
		return
	var k := (actor_on + 1) % actors_rt.size()
	if co != null and co.connected() and co.may_edit(k) != "":
		_say(co.may_edit(k) + " Or press Co-edit: stop to animate it yourself.")
		return
	var TB: Body = actors_rt[k]["B"]
	var TS: Scene = actors_rt[k]["S"]
	var t := playhead
	var at := [0]
	_do(func():
		at[0] = PoseCopy.copy(B, S, TB, TS, t, mirrored, false)
		actors_rt[k]["t"] = NAN   # the other fighter is posed again from its new card
	)
	var who := "the hero" if k == 0 else String(actors_rt[k]["name"])
	_say("pose copied%s to %s: its card %d at %.2f s.  Ctrl+Z undoes" % [" mirrored" if mirrored else "", who, at[0] + 1, t])


func _paste_flipped(f: float, selected_only: bool) -> void:
	if pose_clip.is_empty():
		_say("nothing copied yet: press Ctrl+C on the pose you want first, then paste it flipped here")
		return
	if selected_only and group().size() < 2 and not sel in Body.ORDER:
		_say("pick a body part first (Ctrl+click for more): the flipped paste goes to the selected parts only")
		return
	var js: Array = group().filter(func(j): return j in Body.ORDER) if selected_only else []
	_push_undo()
	var n := Breakdowner.paste(B, pose_clip, true, js, f)
	if S.on_floor:
		S._ground(B)
	B.apply_grip()
	_refresh()
	_say("pose pasted flipped %d%% on %s: %d joints moved.  Ctrl+Z undoes; Update keeps it on the card" % [round(f * 100.0), "%d parts" % js.size() if selected_only else "the whole body", n])


func _tool(id: int) -> void:
	var pm := ui_tools.get_popup()
	match id:
		0:
			_do(func(): B.mirror_pose())
			_say("mirrored: the whole body left <-> right (the weapon changed hands).  Ctrl+Z undoes; Update keeps it on the card")
		1:
			ov.spacing_on = not ov.spacing_on
			ov.mark_dirty()
			wt.mark_dirty()
			_refresh()
			_say("spacing ghosts every 0.1 s: orange = before, green = after.  Bunched = slow, spread = fast" if ov.spacing_on else "spacing ghosts off")
		2:
			ov.graph_on = not ov.graph_on
			ov.mark_dirty()
			wt.mark_dirty()
			_refresh()
			_say("speed graph: tip, hips, head over the scene; the grey lines are the cards.  Click it to move the playhead" if ov.graph_on else "speed graph off")
		3:
			_push_undo()   # round 8 (undo audit): it puts the scene's pose on the body; a pose not yet on a card was lost
			stepped_view = not stepped_view
			ov.mark_dirty()
			wt.mark_dirty()
			_ps().apply(B, playhead)
			_refresh()
			_say("STEPPED: each card's pose holds until the next one arrives (no in-betweens).  Press Check to grade the real motion" if stepped_view else "stepped preview off: in-betweens back")
		4:
			_push_undo()
			S.moving_holds = not S.moving_holds
			_rebuild_cards()
			_ps().apply(B, playhead)
			_refresh()
			_say(("MOVING HOLDS: during a hold the upper body drifts %d%% toward the next card (the feet stay).  Saved with the scene" % int(Scene.HOLD_DRIFT * 100.0)) if S.moving_holds else "moving holds off: holds are still again")
		5:
			_mirror_scene()
	pm.set_item_checked(pm.get_item_index(1), ov.spacing_on)
	pm.set_item_checked(pm.get_item_index(2), ov.graph_on)
	pm.set_item_checked(pm.get_item_index(3), stepped_view)
	pm.set_item_checked(pm.get_item_index(4), S.moving_holds)


## the whole scene mirrored, card by card (and each card's steps), into scenes/_wip/<name>_mirrored.json, opened
func _mirror_scene() -> void:
	var H := _hero_scene()   # TC3: the file is the hero's scene (with its actors), whoever is active
	if H.cards.size() < 2:
		_say("Mirror the scene needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	var d := _mirrored_dict()
	# the file name made safe (round 19: the raw name wrote "_wip/x" into scenes/_wip/_wip/, and "a:b" was a name Windows
	# refuses); always in scenes/_wip, whatever folder the name gives
	var path := "res://scenes/_wip/%s.json" % safe_file(String(d["scene"])).trim_prefix("_wip/")
	_write(path, d)
	_load_scene(path)
	_rebuild_cards()
	_refresh()
	_say("mirrored scene saved as %s and opened; '%s' is untouched" % [path.get_file(), H.name])


## RETIME A RANGE (ROADMAP 67; scripts/retime_range.gd). The range is the preview range (the ruler's in and out) or else the
## picked cards; the cards and part keys in it scale about the playhead; the dialog asks for the percent. One undo step
var ui_rr_dlg: ConfirmationDialog
var ui_rr_slider: HSlider
var ui_rr_val: Label
var ui_rr_range: Label


## the range to retime: [r0, r1] from the preview range, else from the picked cards, else []
func _retime_range_span() -> Array:
	var sp := PreviewRange.span(pv_in, pv_out, S.length())
	if not sp.is_empty():
		return sp
	var rg := card_range()
	if rg.is_empty():
		return []
	var ts := S.times()
	return [float(ts[rg[0]][0]), float(ts[rg[-1]][2])]


func _retime_range_dialog() -> void:
	var sp := _retime_range_span()
	if sp.is_empty():
		_say("no range to retime: Shift+click the ruler for the in point and Alt+click for the out point, or pick two cards (Shift+click)")
		return
	if ui_rr_dlg == null:
		ui_rr_dlg = ConfirmationDialog.new()
		ui_rr_dlg.name = "retime_range_dialog"
		ui_rr_dlg.title = "Retime: scale the range around the playhead"
		ui_rr_dlg.min_size = Vector2i(440, 0)
		var box := VBoxContainer.new()
		ui_rr_range = Label.new()
		box.add_child(ui_rr_range)
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = "length"
		h.add_child(l)
		ui_rr_slider = HSlider.new()
		ui_rr_slider.name = "slider_retime_range"
		ui_rr_slider.min_value = 50.0
		ui_rr_slider.max_value = 200.0
		ui_rr_slider.step = 5.0
		ui_rr_slider.custom_minimum_size = Vector2(200, 26)
		ui_rr_slider.tooltip_text = "100 = as it is; 150 = the range takes half as long again. Cards and keys after the range shift so nothing overlaps"
		ui_rr_val = Label.new()
		ui_rr_slider.value_changed.connect(func(v): ui_rr_val.text = "%d %%" % roundi(v))
		h.add_child(ui_rr_slider)
		h.add_child(ui_rr_val)
		box.add_child(h)
		ui_rr_dlg.add_child(box)
		ui_rr_dlg.confirmed.connect(func(): _retime_range(float(roundi(ui_rr_slider.value))))
		add_child(ui_rr_dlg)
	ui_rr_range.text = "range %.2f to %.2f s (%.2f s long); the playhead at %.2f s stays put.
Cards, keys, plants, IK, layers, props, markers and camera move with it. The audio stays where it is (it is the reference)." % [sp[0], sp[1], sp[1] - sp[0], clampf(playhead, 0.0, S.length())]
	ui_rr_slider.value = 100.0
	ui_rr_val.text = "100 %"
	ui_rr_dlg.popup_centered()


## scales the range about the playhead by pct %. "" = done, else what was wrong
func _retime_range(pct: float) -> String:
	var sp := _retime_range_span()
	if sp.is_empty():
		_say("no range to retime: Shift+click the ruler for the in point and Alt+click for the out point, or pick two cards (Shift+click)")
		return "no range"
	if pct == 100.0:
		_say("100 %% is as it is: move the slider off 100 %% to retime the range")
		return "as it is"
	var p := clampf(playhead, 0.0, S.length())
	var err := RetimeRange.check(S, sp[0], sp[1], p, pct)
	if err != "":
		_say("retime refused: %s. Move the playhead into the range, or stretch less, then try again" % err)
		return err
	_push_undo()
	var n := RetimeRange.apply(S, sp[0], sp[1], p, pct)   # every timed thing in the scene moves on one map, markers too
	_rebuild_cards()
	_refresh()
	_say("range %.2f-%.2f s at %.0f %%: %d cards and the part keys in it moved; the scene is now %.2f s (Ctrl+Z undoes)" % [sp[0], sp[1], pct, n, S.length()])
	return ""


## FATIGUE (ROADMAP 39): asks for the fighter's fitness (0-100 %), then retimes every strike (cards the hit markers land on)
## by Fatigue.plan. One undo step. "" = done, else what was wrong
var ui_fat_dlg: ConfirmationDialog
var ui_fat_slider: HSlider
var ui_fat_val: Label


func _fatigue_dialog() -> void:
	if Fatigue.strike_cards(S).is_empty():
		_say("Fatigue needs the strikes marked: put a hit marker on each strike card (Marker: hit), then try again")
		return
	if ui_fat_dlg == null:
		ui_fat_dlg = ConfirmationDialog.new()
		ui_fat_dlg.name = "fatigue_dialog"
		ui_fat_dlg.title = "Fatigue: slow the fight as it goes"
		ui_fat_dlg.min_size = Vector2i(380, 0)
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = "fitness"
		h.add_child(l)
		ui_fat_slider = HSlider.new()
		ui_fat_slider.name = "slider_fitness"
		ui_fat_slider.min_value = 0.0
		ui_fat_slider.max_value = 1.0
		ui_fat_slider.step = 0.05
		ui_fat_slider.custom_minimum_size = Vector2(180, 26)
		ui_fat_slider.tooltip_text = "0.5 = the elite fighters measured (about 10 % slower strikes after a long fight); 1 = no slowing; 0 = twice as much"
		ui_fat_val = Label.new()
		ui_fat_slider.value_changed.connect(func(v): ui_fat_val.text = "%.2f  (end of fight: %.0f %% slower)" % [v, Fatigue.decline(1.0, v) * 100.0])
		h.add_child(ui_fat_slider)
		h.add_child(ui_fat_val)
		ui_fat_dlg.add_child(h)
		ui_fat_dlg.confirmed.connect(func(): fatigue(ui_fat_slider.value))
		add_child(ui_fat_dlg)
	ui_fat_slider.value = S.fitness
	ui_fat_slider.value_changed.emit(S.fitness)
	ui_fat_dlg.popup_centered()


func fatigue(fitness: float) -> String:
	if Fatigue.strike_cards(S).is_empty():
		return "no strikes marked: put a hit marker on each strike card first"
	_push_undo()
	_markers_hold()
	S.fitness = clampf(fitness, 0.0, 1.0)
	var p := Fatigue.apply(S, S.fitness)
	_markers_follow()
	_rebuild_cards()
	_refresh()
	_say("fatigue at fitness %.2f: %d strikes slowed, the last to %.0f %% of its speed; the scene is now %s.  Ctrl+Z undoes" % [S.fitness, p.size(), float(p[-1]["speed"]) * 100.0, Units.time(_ps().length(), S.fps)])
	return ""


## THE MIRROR (ROADMAP 54): the hero's scene mirrored, as the file that Mirror the scene writes and Mirror in place
## applies. Scene.mirror_file does the work; the live body is not touched (lossless, round 8)
func _mirrored_dict() -> Dictionary:
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	# Scene.mirror_file (TC1): cards by Scene.MIRROR_CARD (round 19, Z1), part_keys (WW1), ik, layer (YY9), layers with
	# the hips' offset x negated (NA1, NA2), props x and yaw negated, each actor's scene and place; the name toggles
	# "_mirrored"; bad_frames recomputed on the mirrored motion (the original's named the wrong side)
	var d := Scene.mirror_file(_scene_dict(), M)
	d["plan"] = "Mirror the scene (Scene.MIRROR_CARD on every card) from " + _hero_scene().name
	return d


## MIRROR IN PLACE (ROADMAP 54): the open scene mirrored left <-> right, the same dict as Mirror the scene, applied to
## the open scene itself as ONE undo step. The name stays and nothing is written: Save scene keeps it. An actor on
## screen is brought to the hero first (the mirror is the hero's file, as Mirror the scene does)
func _mirror_in_place() -> void:
	if actor_on != 0 and not _actor_set(0):
		_say("Mirror in place works on the hero's scene: press Actor: switch to the next fighter until the hero is on screen")
		return
	if S.cards.size() < 2:
		_say("Mirror in place needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	var d := _mirrored_dict()
	d["scene"] = S.name   # the mirror's name ("_mirrored") is for the copy; in place the scene keeps its own
	d.erase("plan")
	var n := S.cards.size()
	_do(func():
		S.from_dict(d)   # the same reader as a load: the open scene object stays, so Ctrl+Z puts its cards back into it
		actors_rt = []   # the actors are the file's now: built again from S.actors (their bodies posed from their scenes)
		actor_on = 0
		_actors_sync()
		sel_card = mini(sel_card, S.cards.size() - 1)
		ov.mark_dirty()
		wt.mark_dirty()
		_dummy_hits()
		_rebuild_cards()
		S.apply(B, playhead))
	_say("mirrored in place: the whole scene left <-> right, %d cards.  Ctrl+Z takes it back in one step; nothing is saved until you save" % n)


## STYLE TRANSFER (ROADMAP 25): "Style: make it <older | tired | heavy | angry>" asks for the intensity (0-100 %), then saves
## a NEW scene in scenes/_wip and opens it (yours untouched). The logic is StyleTransfer.make (scripts/style_transfer.gd).
func _style_dialog(style: String) -> void:
	if S.cards.size() < 2:
		_say("Style needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	ui_style_name = style
	if ui_style_dlg == null:
		ui_style_dlg = ConfirmationDialog.new()
		ui_style_dlg.name = "style_dialog"
		ui_style_dlg.title = "Style transfer"
		ui_style_dlg.min_size = Vector2i(340, 0)
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = "intensity (%)"
		h.add_child(l)
		ui_style_pct = SpinBox.new()
		ui_style_pct.name = "spin_style_pct"
		ui_style_pct.min_value = 0.0
		ui_style_pct.max_value = 100.0
		ui_style_pct.step = 1.0
		ui_style_pct.value = 100.0
		h.add_child(ui_style_pct)
		ui_style_dlg.add_child(h)
		ui_style_dlg.confirmed.connect(func(): _style_save(ui_style_name, ui_style_pct.value))
		add_child(ui_style_dlg)
	ui_style_dlg.title = "Style transfer: " + style
	ui_style_dlg.popup_centered()


## the style made from the hero's scene file, into scenes/_wip/<name>_<style>.json, opened (as _mirror_scene does)
func _style_save(style: String, pct: float) -> void:
	var H := _hero_scene()   # TC3: the file is the hero's scene (with its actors), whoever is active
	var d := StyleTransfer.make(_scene_dict(), style, pct)
	var path := "res://scenes/_wip/%s.json" % safe_file(String(d["scene"])).trim_prefix("_wip/")
	_write(path, d)
	_load_scene(path)
	_rebuild_cards()
	_refresh()
	_say("style %s at %d%%: saved as %s and opened; '%s' is untouched" % [style, int(round(pct)), path.get_file(), H.name])


## TYPE A MOVE, GET BLOCKING (ROADMAP 22): a line of words -> a blocked-out scene in scenes/_wip, opened. The work is
## scripts/text_blocking.gd: the closest of Nick's saved attack segments (scenes/, read only) retrieved and adapted by
## the app's own ops (Scene.mirror_card, Body.set_kind + weapon_to_hand + apply_grip / hold_bat, the card's steps +
## Scene.pin_cards, Scene.retime to docs/ATTACK_RULES.md); the status says which and what it could not find
var ui_words_dlg: ConfirmationDialog
var ui_words: LineEdit


func _words_ask() -> void:
	if ui_words_dlg == null:
		ui_words_dlg = ConfirmationDialog.new()
		ui_words_dlg.name = "words_dialog"
		ui_words_dlg.title = "Block out a move from words"
		ui_words_dlg.ok_button_text = "Block it out"
		ui_words_dlg.min_size = Vector2i(440, 0)
		ui_words = LineEdit.new()
		ui_words.name = "edit_words"
		ui_words.placeholder_text = "overhead axe strike, step in   /   fast jab   /   staff sweep right"
		ui_words_dlg.add_child(ui_words)
		ui_words_dlg.register_text_enter(ui_words)
		ui_words_dlg.confirmed.connect(_words_build)
		add_child(ui_words_dlg)
	ui_words_dlg.popup_centered()
	ui_words.grab_focus.call_deferred()
	ui_words.select_all.call_deferred()


func _words_build() -> void:
	var text := ui_words.text.strip_edges()
	if text == "":
		_say("Block out a move from words needs some words: an attack (overhead, sweep, thrust, jab, uppercut, hook), a weapon (axe, bat, staff, hammer, dagger; none = a fist), a side (left / right), a step (step in, step back, lunge), a speed (fast, heavy, slow)")
		return
	var W := Body.new()   # a scratch body: the build poses it card by card; the live body takes the opened scene
	W.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r: Dictionary = TextBlocking.build(text, W)
	if not r["ok"]:
		_say("'%s': %s: type a move like 'overhead axe strike, step in'" % [text, r["error"]])
		return
	var S2: Scene = r["scene"]
	var path := TextBlocking.unique_path("res://scenes/_wip", TextBlocking.slug(text))
	var d := S2.to_dict(W)
	d["plan"] = "Block out a move from words '%s': %s" % [text, r["status"]]
	_write(path, d)
	_load_scene(path)
	_rebuild_cards()
	_refresh()
	_say("'%s' blocked out as %s and opened (%d cards: %s). %s" % [text, path.get_file(), S2.cards.size(), ", ".join(S2.cards.map(func(c): return String(c["name"]).get_slice(":", 0))), r["status"]])


## NEW FROM TEMPLATE (ROADMAP 44): a picker of the five starting scenes (walk, run, jump, punch, sword swing; scripts/templates.gd,
## the files in templates/). The pick becomes a NEW scene scenes/_wip/<template>[_N].json (never over one) and is opened; the
## template files themselves are only read
var ui_tpl_dlg: ConfirmationDialog
var ui_tpl_list: ItemList
var ui_tpl_blurb: Label


func _template_ask() -> void:
	if ui_tpl_dlg == null:
		ui_tpl_dlg = ConfirmationDialog.new()
		ui_tpl_dlg.name = "template_dialog"
		ui_tpl_dlg.title = "New from template"
		ui_tpl_dlg.ok_button_text = "Make the scene"
		ui_tpl_dlg.min_size = Vector2i(460, 0)
		var v := VBoxContainer.new()
		var hd := Label.new()
		hd.text = "A starting scene, checked against real people's numbers. It opens as a new file in scenes/_wip; yours stay untouched."
		hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hd.custom_minimum_size = Vector2(440, 0)
		v.add_child(hd)
		ui_tpl_list = ItemList.new()
		ui_tpl_list.name = "list_templates"
		ui_tpl_list.custom_minimum_size = Vector2(440, 150)
		ui_tpl_list.select_mode = ItemList.SELECT_SINGLE
		for nm in Templates.NAMES:
			ui_tpl_list.add_item(String(Templates.INFO[nm][0]))
			ui_tpl_list.set_item_metadata(ui_tpl_list.item_count - 1, nm)
		ui_tpl_list.item_selected.connect(_template_blurb)
		ui_tpl_list.item_activated.connect(func(_i): ui_tpl_dlg.hide(); _template_build())
		v.add_child(ui_tpl_list)
		ui_tpl_blurb = Label.new()
		ui_tpl_blurb.name = "label_template_blurb"
		ui_tpl_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ui_tpl_blurb.custom_minimum_size = Vector2(440, 44)
		v.add_child(ui_tpl_blurb)
		ui_tpl_dlg.add_child(v)
		ui_tpl_dlg.confirmed.connect(_template_build)
		add_child(ui_tpl_dlg)
	if not ui_tpl_list.is_anything_selected():
		ui_tpl_list.select(0)
	_template_blurb(ui_tpl_list.get_selected_items()[0])
	ui_tpl_dlg.popup_centered()


func _template_blurb(i: int) -> void:
	ui_tpl_blurb.text = String(Templates.INFO[String(ui_tpl_list.get_item_metadata(i))][1])


func _template_build() -> void:
	if ui_tpl_list == null or not ui_tpl_list.is_anything_selected():
		_say("New from template needs a pick: choose walk, run, jump, punch or sword swing in the list, then press Make the scene")
		return
	var nm := String(ui_tpl_list.get_item_metadata(ui_tpl_list.get_selected_items()[0]))
	var d := Templates.read(nm)
	if d.is_empty():
		_say("The %s template file (templates/%s.json) is missing: rebuild the templates with  godot --headless --path . -s tools/make_templates.gd  and pick again" % [nm, nm])
		return
	# opening the new scene replaces the open one: unsaved changes get the same save prompt as New and Open
	if _unsaved():
		_ask_save(_scene_label(), _template_build_now.bind(nm, d))
		return
	_template_build_now(nm, d)


func _template_build_now(nm: String, d: Dictionary) -> void:
	var path := Templates.new_path(nm)
	d["scene"] = path.get_file().get_basename()
	d["plan"] = "from the %s template" % String(Templates.INFO[nm][0]).to_lower()
	_write(path, d)
	_load_scene(path)
	_rebuild_cards()
	_refresh()
	_say("%s template: saved as %s and opened (%d cards); the template itself is untouched" % [Templates.INFO[nm][0], path.get_file(), S.cards.size()])


## SPEED GRAPH: three strips (small multiples, each its own scale: the tip moves metres where the head moves
## centimetres), the cards as grey lines, the playhead white; read from the trail's pass (nothing re-played)
func _draw_graph() -> void:
	var g := ui_graph
	var c: Dictionary = ov.curves
	g.draw_rect(Rect2(Vector2.ZERO, g.size), Tok.c("graph_bg"))
	if c.is_empty() or c["t"].size() < 2:
		return
	var T: float = c["t"][-1]
	var font: Font = g.get_theme_default_font()
	var rows := [["tip", "tip" if c["armed"] else "wrist", Tok.c("s_tip")],
		["hips", "hips", Tok.c("s_hips")], ["head", "head", Tok.c("s_head")]]
	var lw := 118.0
	var h := (g.size.y - 8.0 - GRAPH_AXIS) / rows.size()
	for r in rows.size():
		var y0 := 4.0 + h * r
		var s: Array = c[rows[r][0]]
		var top := 0.0
		for v in s:
			top = maxf(top, v)
		g.draw_string(font, Vector2(8, y0 + h * 0.5 + 6), "%s %.1f m/s" % [rows[r][1], top], HORIZONTAL_ALIGNMENT_LEFT, lw - 10, 13, Tok.of("ink:0.8"))
		g.draw_line(Vector2(lw, y0 + h - 2), Vector2(g.size.x - 8, y0 + h - 2), Tok.of("ink:0.12"), 1.0)
		var pts := PackedVector2Array()
		for i in s.size():
			var x := lw + (g.size.x - lw - 8.0) * float(c["t"][i]) / maxf(T, 1e-6)
			pts.append(Vector2(x, y0 + h - 2 - (h - 8) * (float(s[i]) / maxf(top, 1e-6))))
		g.draw_polyline(pts, rows[r][2], 2.0, true)
	# the rate it was read at: the scene's fps (the trail's pass). Check reads 60, where a fast arc reads FASTER (a 30 fps
	# chord cuts the corner: bo_spin's staff 81.9 here, 96.5 in Check), so the graph says so instead of disagreeing silently
	g.draw_string(font, Vector2(8, g.size.y - 4), "at %d fps%s" % [int(c.get("fps", 30)), "" if int(c.get("fps", 30)) >= 60 else " (Check: 60)"], HORIZONTAL_ALIGNMENT_LEFT, lw - 10, 11, Tok.of("ink:0.45"))
	for i in c["cards"].size():
		var x := lw + (g.size.x - lw - 8.0) * float(c["cards"][i]) / maxf(T, 1e-6)
		g.draw_line(Vector2(x, 2), Vector2(x, g.size.y - 2), Tok.of("ink:0.18"), 1.0)
		g.draw_string(font, Vector2(x + 2, 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.of("ink:0.45"))
	var px := lw + (g.size.x - lw - 8.0) * clampf(playhead / maxf(T, 1e-6), 0.0, 1.0)
	g.draw_line(Vector2(px, 0), Vector2(px, g.size.y), Tok.of("ink:0.9"), 2.0)
	# the time axis (round 23, GATES DD2): a tick and its seconds under the strips
	var ay := g.size.y - GRAPH_AXIS
	g.draw_line(Vector2(lw, ay), Vector2(g.size.x - 8, ay), Tok.of("ink:0.35"), 1.0)
	for s in graph_ticks(T):
		var x: float = lw + (g.size.x - lw - 8.0) * float(s) / maxf(T, 1e-6)
		g.draw_line(Vector2(x, ay), Vector2(x, ay + 4), Tok.of("ink:0.5"), 1.0)
		var lab := ("%.1f" % s).trim_suffix(".0") + ("s" if s == 0.0 else "")
		var tw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		g.draw_string(font, Vector2(clampf(x - tw * 0.5, lw + 6, g.size.x - 8 - tw), ay + 14), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tok.of("ink:0.6"))
	# the hover line and its readout
	if _graph_hover >= 0.0:
		var hx := lw + (g.size.x - lw - 8.0) * clampf(_graph_hover / maxf(T, 1e-6), 0.0, 1.0)
		g.draw_line(Vector2(hx, 0), Vector2(hx, ay), Tok.c("accent"), 1.0)
		var txt := graph_readout()
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var bx := clampf(hx + 6, lw, g.size.x - tw - 14)
		g.draw_rect(Rect2(bx - 3, 3, tw + 6, 17), Color(Tok.c("float"), 0.92))
		g.draw_string(font, Vector2(bx, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tok.c("heading"))


## A SPEED GRAPH YOU CAN READ (round 23, GATES DD2, UPGRADES #44): the time axis's ticks (every 0.5 s, 1 s past 6 s,
## from 0, none past the end), and the readout under the mouse: the three speeds at that time, linear between samples
const GRAPH_AXIS := 16.0
var _graph_hover := -1.0   # the time under the mouse (-1 = the mouse is not on the graph)


static func graph_ticks(T: float) -> Array:
	var step := 0.5 if T <= 6.0 else 1.0
	var out := []
	var k := 0
	while k * step <= T + 1e-6:
		out.append(k * step)
		k += 1
	return out


func graph_value(row: String, t: float) -> float:
	var c: Dictionary = ov.curves
	var ts: Array = c["t"]
	var s: Array = c[row]
	if t <= float(ts[0]):
		return float(s[0])
	for i in range(1, ts.size()):
		if t <= float(ts[i]):
			var f := (t - float(ts[i - 1])) / maxf(float(ts[i]) - float(ts[i - 1]), 1e-9)
			return lerpf(float(s[i - 1]), float(s[i]), f)
	return float(s[-1])


func graph_readout() -> String:
	if _graph_hover < 0.0 or ov.curves.is_empty() or ov.curves["t"].size() < 2:
		return ""
	var c: Dictionary = ov.curves
	return "%.2f s   %s %.2f   hips %.2f   head %.2f m/s" % [_graph_hover, "tip" if c["armed"] else "wrist",
		graph_value("tip", _graph_hover), graph_value("hips", _graph_hover), graph_value("head", _graph_hover)]


func _graph_input(ev: InputEvent) -> void:
	var lw := 118.0
	if ev is InputEventMouseMotion and not ov.curves.is_empty():
		var x := (ev as InputEventMouseMotion).position.x
		_graph_hover = clampf((x - lw) / maxf(ui_graph.size.x - lw - 8.0, 1.0), 0.0, 1.0) * float(ov.curves["t"][-1]) if x >= lw else -1.0
		ui_graph.queue_redraw()
	if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if ov.curves.is_empty():
			return
		var T: float = ov.curves["t"][-1]
		playing = false
		playhead = clampf((ev.position.x - lw) / maxf(ui_graph.size.x - lw - 8.0, 1.0), 0.0, 1.0) * T
		_ps().apply(B, playhead)
		_refresh()


## CHECK: the rulebook over the scene as it plays; the panel lists each finding as a button that jumps to it
func _check(given = null) -> void:
	_previews.clear()   # the previews were for the cards as they were
	_pv_gen += 1
	_pv_hover = {}
	ov.fix_preview(S, [], 0.0)
	if S.cards.size() < 2:
		_say("Check needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	if given != null:   # a Fix already checked the scene it left
		findings = given
		_sm = {}
	else:
		# the scene AS MADE, not the dummy's landed version (_ps): the impact stop is the dummy's physics, not the
		# animator's move, and a Fix edits S (10-14: grading SL made a fixed card's finding come back)
		_sm = Rulebook.sample(S, ov.GB)
		findings = Rulebook.check(S, ov.GB, _sm)
	check_ran = true
	check_at = undo.size()
	for c in ui_find_list.get_children():
		ui_find_list.remove_child(c)   # detach now: queue_free alone leaves the old rows listed until the frame ends
		c.queue_free()
	var fails := findings.filter(func(f): return f["sev"] == "FAIL").size()
	var head := HBoxContainer.new()
	ui_find_list.add_child(head)
	var title := _label("CHECK  -  " + ("clean: nothing here breaks the rulebook" if findings.is_empty() else "%d findings to look at (%d must fix)" % [findings.size(), fails]), 18, "heading" if findings.is_empty() else "warn")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Close", _close_findings))
	if not findings.is_empty():
		ui_find_list.add_child(_label("Click one to jump there.  Red = breaks a real human limit, yellow = looks off.", 13, "text:0.6", true))
	for fk in findings.size():
		var f: Dictionary = findings[fk]
		var b := Button.new()
		b.name = "finding_%d" % (fk + 1)   # U2: the n-th finding, as `check` numbers them
		b.text = "%s  %.2f s  card %d '%s'  -  %s
%s" % ["MUST FIX" if f["sev"] == "FAIL" else "look", f["t"], f["card"] + 1, S.cards[mini(f["card"], S.cards.size() - 1)]["name"], f["rule"], f["msg"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(380, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Tok.c("fail") if f["sev"] == "FAIL" else Tok.c("warn"))
		b.pressed.connect(_goto_finding.bind(f))
		ui_find_list.add_child(b)
		var lbl := Fixer.label(f, S)   # the action first, under its finding; then why (round 25, #81: fewer scrolls)
		if lbl != "":
			var fx := _button(lbl, _fix.bind(f))
			fx.name = "fix_%d" % (fk + 1)
			fx.add_theme_font_size_override("font_size", 14)
			fx.mouse_entered.connect(_fix_hover.bind(f))   # FIX PREVIEW (#79): a blue ghost of the result, nothing changed
			fx.mouse_exited.connect(_fix_hover.bind({}))
			ui_find_list.add_child(fx)
			if f["rule"] == "HEAD QUIET":   # NA2: a pose fix can go onto a layer instead (timing fixes cannot)
				var fl := _button("   ...or on a layer (the cards stay as they are)", _fix_layer.bind(f))
				fl.name = "fixlayer_%d" % (fk + 1)
				fl.add_theme_font_size_override("font_size", 12)
				ui_find_list.add_child(fl)
		else:
			ui_find_list.add_child(_label("   no automatic fix: " + ("two cards fight here; change one of them" if f["rule"] == "HITCH" else "the foot creeps between two cards' stances: give the cards the same foot spot, or step it on purpose" if f["rule"] == "FOOT SLIDE" else "it is in the poses; change the cards around it"), 12, "text:0.5", true))
		if Rulebook.WHY.has(f["rule"]):   # WHY + SOURCE (round 12, #78)
			var wr := HBoxContainer.new()
			var wl := _label("   why: " + Rulebook.WHY[f["rule"]], 12, "text:0.7", true)
			wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			wr.add_child(wl)
			var sb := _button("source", _open_source.bind(Rulebook.URL[f["rule"]]), Rulebook.SRC.get(f["rule"], ""))
			sb.name = "source_%d" % (fk + 1)
			sb.add_theme_font_size_override("font_size", 12)
			sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			wr.add_child(sb)
			ui_find_list.add_child(wr)
	# a ScrollContainer has no height of its own: size it to the list (up to most of the view), else it collapses to 0
	(ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(56.0 + 128.0 * findings.size(), 60.0,
		minf(440.0, get_viewport().get_visible_rect().size.y - bottom_h - 82 - (TOP_H + 12) - 26)))   # ends above the status line (round 9: the bar moved it up)
	ui_find.visible = true
	_say("check: " + ("clean" if findings.is_empty() else "%d findings, %d must fix.  Click one to jump to it." % [findings.size(), fails]))


## CRITIQUE (ROADMAP 11): the animation-craft notes (scripts/critique.gd) in their own section of the CHECK panel. Notes only:
## the rulebook's findings, Check and its Fix are untouched (findings / check_ran are not set here)
func _critique() -> void:
	if S.cards.size() < 2:
		_say("Critique needs a scene of two cards or more: add a card first")
		return
	var notes := Critique.check(S, ov.GB)
	for c in ui_find_list.get_children():
		ui_find_list.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	ui_find_list.add_child(head)
	var title := _label("CRITIQUE  -  " + ("nothing to note in the craft rules" if notes.is_empty() else "%d notes (never must-fix)" % notes.size()), 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Close", _close_findings))
	ui_find_list.add_child(_label("Animation craft, from the twelve principles: notes, not errors. Click one to jump to its moment.", 13, "text:0.6", true))
	for k in notes.size():
		var f: Dictionary = notes[k]
		var b := Button.new()
		b.name = "note_%d" % (k + 1)
		b.text = "note  %s  card %d '%s'  -  %s\n%s" % [Units.time(f["t"], S.fps), f["card"] + 1, S.cards[mini(f["card"], S.cards.size() - 1)]["name"], f["rule"], f["msg"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(380, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Tok.of("text:0.85"))
		b.pressed.connect(_goto_finding.bind(f))
		ui_find_list.add_child(b)
	(ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(56.0 + 110.0 * notes.size(), 60.0,
		minf(440.0, get_viewport().get_visible_rect().size.y - bottom_h - 82 - (TOP_H + 12) - 26)))
	ui_find.visible = true
	_say("critique: " + ("nothing to note" if notes.is_empty() else "%d notes (never must-fix). Click one to jump to it." % notes.size()))


## ROADMAP 24: the stunt-load report (StuntLoad, scripts/stunt_load.gd): landing g, knee valgus, spine, neck. NOTE only
func _stunt_check() -> void:
	if S.cards.size() < 2:
		_say("Stunt load needs a scene of two cards or more: add a card first")
		return
	var notes := StuntLoad.findings(S, ov.GB)
	for c in ui_find_list.get_children():
		ui_find_list.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	ui_find_list.add_child(head)
	var title := _label("STUNT LOAD REPORT  -  %d notes (never must-fix)" % notes.size(), 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Close", _close_findings))
	ui_find_list.add_child(_label("Loads a performer would take, from the motion: landing (vGRF in body weights), knee valgus, spine (NIOSH 3400 N, ours), neck. Bars and sources: docs/research/STUNT_LOAD.md. Click one to jump to its moment.", 13, "text:0.6", true))
	for k in notes.size():
		var f: Dictionary = notes[k]
		var b := Button.new()
		b.name = "stunt_%d" % (k + 1)
		b.text = "%s  card %d  -  %s\n%s" % [Units.time(f["t"], S.fps), f["card"] + 1, f["rule"], f["msg"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(380, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Tok.of("text:0.85"))
		b.pressed.connect(_goto_finding.bind(f))
		ui_find_list.add_child(b)
	(ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(56.0 + 110.0 * notes.size(), 60.0,
		minf(440.0, get_viewport().get_visible_rect().size.y - bottom_h - 82 - (TOP_H + 12) - 26)))
	ui_find.visible = true
	_say("stunt load: %d notes (never must-fix). Click one to jump to it." % notes.size())


## Check is fresh: it ran, and nothing has been changed since (an edit pushes an undo step; an undo takes one away)
func findings_live() -> bool:
	return check_ran and check_at == undo.size() and not findings.is_empty()


## a finding's mark on the timeline clicked: the same as its row in the Check list, and that row shown
func _finding_mark(i: int) -> void:
	var f: Dictionary = findings[i]
	_goto_finding(f)
	ui_find.visible = true
	var row := ui_find_list.get_node_or_null("finding_%d" % (i + 1)) as Control
	if row != null:
		var sc := ui_find_list.get_parent() as ScrollContainer
		sc.ensure_control_visible.call_deferred(row)


func _goto_finding(f: Dictionary) -> void:
	playing = false
	playhead = f["t"]
	sel_card = mini(f["card"], S.cards.size() - 1)
	_ps().apply(B, playhead)
	_rebuild_cards()
	_refresh()
	_say("%s at %s (card %d): %s" % [f["rule"], Units.time(f["t"], S.fps), sel_card + 1, f["msg"]])


## FIX: the finding's fix (scripts/fixer.gd) on the open scene's cards: it only UPDATES cards (never adds or deletes
## one), keeps it only if the problem is gone and nothing got worse, and is one Ctrl+Z step. The file is not written:
## Save scene keeps it, as with every edit.
## open a rule's source: a web page in the browser, a doc of ours in the system's viewer. Tests only record it
var last_source := ""


func _open_source(url: String) -> void:
	last_source = url
	_say("source: " + url)
	if Engine.get_main_loop().get_script() == null:
		OS.shell_open(ProjectSettings.globalize_path(url) if url.begins_with("res://") else url)


func _close_findings() -> void:
	ui_find.visible = false
	ov.fix_preview(S, [], 0.0)


## hovering a Fix button: the playhead jumps to the finding and a blue ghost shows the body there AFTER the fix; the
## scene is not touched until the click. {} = leave (ghost off; the playhead stays, so you can compare)
func _fix_hover(f: Dictionary) -> void:
	_pv_hover = f
	if f.is_empty() or _fixing:
		ov.fix_preview(S, [], 0.0)
		return
	playhead = clampf(f["t"], 0.0, S.length())
	_ps().apply(B, playhead)
	if _previews.has(f):
		_show_preview(f)
		return
	ov.fix_preview(S, [], 0.0)
	_say("PREVIEW: working out '%s'..." % Fixer.label(f, S))
	if _pv_job.is_empty():
		_pv_start(f)


## work a preview out on a copy of the scene and a body of its own, on a worker thread: the window never waits
func _pv_start(f: Dictionary) -> void:
	var sc := S.clone()
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.set_state(ov.GB.state())
	var job := {"f": f, "scene": sc, "out": [], "gen": _pv_gen}
	job["task"] = WorkerThreadPool.add_task(func(): job["out"] = Fixer.propose(f, sc, b))
	_pv_job = job


## called every frame: collect a finished preview job, show it if the mouse is still on its button, start the next
func _pv_poll() -> void:
	if _pv_job.is_empty() or not WorkerThreadPool.is_task_completed(_pv_job["task"]):
		return
	WorkerThreadPool.wait_for_task_completion(_pv_job["task"])
	var job := _pv_job
	_pv_job = {}
	if job["gen"] == _pv_gen:
		_previews[job["f"]] = job["out"]
	if not _pv_hover.is_empty() and not _fixing:
		if _previews.has(_pv_hover):
			_show_preview(_pv_hover)
		else:
			_pv_start(_pv_hover)


func _show_preview(f: Dictionary) -> void:
	ov.fix_preview(S, _previews[f], playhead)
	_say("PREVIEW: the blue ghost is this moment after '%s'.  Click to apply it (Ctrl+Z undoes)" % Fixer.label(f, S))


## FIX ON A LAYER (round 49, GATES NA2; scripts/layer_fix.gd): the fix's pose change as additive layers, cards untouched
func _fix_layer(f: Dictionary) -> void:
	ov.fix_preview(S, [], 0.0)
	_pv_hover = {}
	if _fixing:
		return
	_fixing = true
	_say("fixing %s on a layer... (it plays the scene to check the fix)" % f["rule"])
	await get_tree().process_frame
	var r := LayerFix.make(f, S, ov.GB, _sm)
	if r["ok"]:
		_step_hint = "Fix on a layer"
		_push_undo()
		S.layers.append_array(r["layers"])
		layer_on = S.layers.size() - 1
		_dummy_hits()
		_ps().apply(B, playhead)
		_check()
	_refresh()
	var tail := ""
	if r["ok"]:   # the layer matches the fix AT the card; between cards it is close, not equal: say what Check now finds
		var still := findings.filter(func(x): return Fixer._same_finding(f, x))
		tail = ("   Check: %s is gone. " % f["rule"]) if still.is_empty() else ("   Check: %s is still found (a layer follows the fix at the card, only nearly between cards: the plain Fix is the full one). " % f["rule"])
		tail += "'Layer weaker' dials it; Ctrl+Z undoes it"
	_say(String(r["msg"]).replace("Fixed: ", "On a layer: ") + tail)
	_fixing = false


func _fix(f: Dictionary) -> void:
	ov.fix_preview(S, [], 0.0)
	_pv_hover = {}
	if _fixing:
		return
	if Fixer.label(f, S) == "":   # no fix for this rule: Fixer.apply has none to run (and _fixing would stay set)
		_say("%s has no automatic fix: click its card and drag the parts by hand" % f["rule"])
		return
	_fixing = true
	_say("fixing %s on card %d... (it plays the scene to check the fix)" % [f["rule"], f["card"] + 1])
	await get_tree().process_frame
	await get_tree().process_frame
	var u := _snapshot()
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = Fixer.apply(f, S, ov.GB, _sm)
	if r["kept"]:
		undo.append(u)
		redo.clear()
		_rebuild_cards()
		_ps().apply(B, playhead)
		_check(r["after"])
	_refresh()
	if r["kept"]:
		var changed := []
		for i in mini(u["cards"].size(), S.cards.size()):
			if JSON.stringify(u["cards"][i]) != JSON.stringify(S.cards[i]):
				changed.append(i)
		_flash_cards(changed)
	_say(r["msg"] + ("   (Ctrl+Z undoes it)" if r["kept"] else "") + "   [%.1f s]" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_fixing = false


## POLISH: the detail pass (tools/detail.gd) on the open scene -> scenes/_wip/<name>_polished.json, opened. Nick's file
## is never written; picking it in the list brings it back.
func _polish() -> void:
	if S.cards.size() < 2:
		_say("Polish needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	_say("polishing '%s'..." % S.name)
	await get_tree().process_frame
	await get_tree().process_frame
	var keep := B.state()   # lossless (round 8): to_dict rounds, so the live body jumped a rounding step
	var C := Scene.new()
	C.from_dict(S.to_dict(B))
	B.set_state(keep)
	var n0 := C.cards.size()
	var r: Array = DetailTool.polish(ov.GB, C, 30)
	var D: Scene = r[0]
	var base := S.name.trim_suffix("_polished")
	D.name = base + "_polished"
	var path := "res://scenes/_wip/%s.json" % D.name
	var d := D.to_dict(ov.GB)
	d["plan"] = "Polish (tools/detail.gd) from " + base
	_write(path, d)
	_load_scene(path)
	_rebuild_cards()
	_refresh()
	_say("polished: %d cards -> %d, one smooth curve.  Saved as %s; your '%s' is untouched.  Press Check to see what is left." % [n0, D.cards.size(), path.get_file(), base])


## RAGDOLL (ROADMAP 27, round 53): the body as it stands now goes limp and falls under gravity (ragdoll.gd, a deterministic
## position-based solver), the picked parts held in place (a pin is a particle of infinite mass where the part was). The
## fall is baked as cards (30 per second) into a NEW scene in scenes/_wip, opened; the live body and your scene are untouched.
func _ragdoll_fall() -> void:
	var pins: Array = []
	for j in group():
		if Ragdoll.is_sim(String(j)):
			pins.append(String(j))
	_say("ragdoll: falling%s..." % (" with %s held" % ", ".join(pins) if not pins.is_empty() else ""))
	await get_tree().process_frame
	var keep := B.state()
	var keep_ang: Dictionary = B.ang.duplicate()
	var R := Ragdoll.new()
	R.setup(B, pins)
	R.run(4.0)
	var cards := R.bake(keep_ang, Ragdoll.CARD_FPS)
	var rest := R.t_rest
	var contact := R.t_contact
	B.set_state(keep)
	var C := Scene.new()
	var base := safe_file(S.name.trim_suffix("_ragdoll") + "_ragdoll")
	C.from_dict({"scene": base, "fps": Ragdoll.CARD_FPS, "cards": cards})
	C.on_floor = false   # the solver is the floor and the feet: playback must not re-ground or re-plant them
	C.pin = false
	var d := C.to_dict(B)
	d["plan"] = "Ragdoll (scripts/ragdoll.gd) from %s, pins: %s" % [S.name, ", ".join(pins) if not pins.is_empty() else "none"]
	var out := "res://scenes/_wip/%s.json" % base
	var n := 2
	while FileAccess.file_exists(out):   # never over an earlier fall: _ragdoll_2, _ragdoll_3 ...
		out = "res://scenes/_wip/%s_%d.json" % [base, n]
		n += 1
	_write(out, d)
	_load_scene(out)
	_rebuild_cards()
	_refresh()
	_say("ragdoll: %d cards, first floor contact %s, %s. Saved as %s; your '%s' is untouched." % [
		cards.size(), "%.2f s" % contact if contact >= 0.0 else "none",
		"at rest at %.2f s" % rest if rest >= 0.0 else "still moving at 4 s",
		out.get_file(), S.name])


## PUSH / RELAX / BLEND TO REST / BLEND TO NEIGHBOUR (round 41, GATES WW3, #279 #280): logic in inbetween.gd; one undo step
func _inbetween(op: String) -> void:
	var why := Inbetween.refuse(S, sel_card, op)
	if why != "":
		_say("%s: %s. Pick a middle card (one with a card before and after it)" % [op, why])
		return
	_push_undo()
	var js := Inbetween.joints_for(B, group())
	var r := Inbetween.run(B, S, sel_card, op, Inbetween.FACTOR, js)
	if S.on_floor:
		S._ground(B)
	B.apply_grip()
	_refresh()
	_say(Inbetween.describe(op, Inbetween.FACTOR, r, "%d parts" % js.size() if group().size() > 1 else "the whole body"))


## BREAKDOWNER (round 42, GATES XX4, #278): logic in breakdowner.gd. _bd_armed keeps a slider drag to ONE undo step
var _bd_armed := false
var _bd_pop: PopupPanel = null


func _breakdowner(f: float) -> void:
	var why := Breakdowner.refuse(S, sel_card)
	if why != "":
		_say("breakdowner: %s. Pick a middle card" % why)
		return
	if not _bd_armed:
		_push_undo()
	var js := Inbetween.joints_for(B, group())
	var r := Breakdowner.run(B, S, sel_card, f, js)
	if S.on_floor:
		S._ground(B)
	B.apply_grip()
	_refresh()
	_say(Breakdowner.describe(f, r, "%d parts" % js.size() if group().size() > 1 else "the whole body") + ".  Ctrl+Z undoes; Update keeps it on the card")


## Shift+E: a small slider, 0 = the card before, 1 = the card after, -0.5..1.5 overshoots. Closing it ends the undo step.
func _breakdowner_popup() -> void:
	var why := Breakdowner.refuse(S, sel_card)
	if why != "":
		_say("breakdowner: %s. Pick a middle card" % why)
		return
	if _bd_pop == null:
		_bd_pop = PopupPanel.new()
		var sl := HSlider.new()
		sl.name = "bd_slider"
		sl.min_value = Breakdowner.MIN_F
		sl.max_value = Breakdowner.MAX_F
		sl.step = 0.01
		sl.value = 0.5
		sl.custom_minimum_size = Vector2(260, 28)
		sl.tooltip_text = "BREAKDOWNER: 0 = like the card before, 1 = like the card after, past the ends = overshoot"
		sl.value_changed.connect(func(v): _breakdowner(v); _bd_armed = true)
		_bd_pop.add_child(sl)
		_bd_pop.popup_hide.connect(func(): _bd_armed = false)
		add_child(_bd_pop)
	_bd_armed = false
	_bd_pop.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()) - Vector2i(130, 20), Vector2i(280, 40)))
	_say("breakdowner: drag the slider (0 = card before, 1 = card after, past the ends overshoots); Esc or a click away closes it")


## TWEEN MACHINE: the body = the picked card's two neighbours mixed by bias (Scene.mix_flat); Update keeps it
func _tween(bias: float) -> void:
	if sel_card <= 0 or sel_card >= S.cards.size() - 1:
		_say("tween: pick a card that has a card before it and after it")
		return
	if not _tween_armed:
		_push_undo()
		_tween_armed = true
	var a := Moves._flat(S.cards[sel_card - 1]["pose"])
	var b := Moves._flat(S.cards[sel_card + 1]["pose"])
	Scene.put(B, Scene.mix_flat(a, b, bias))
	if S.on_floor:
		S._ground(B)
	B.apply_grip()
	_refresh()
	_say("tween %d%%: '%s' -> '%s'.  Press Update on card %d to keep it (Ctrl+Z undoes)" % [round(bias * 100.0), S.cards[sel_card - 1]["name"], S.cards[sel_card + 1]["name"], sel_card + 1])


## a new in-between card after the picked one, halfway to the next
func _tween_add() -> void:
	if sel_card < 0 or sel_card >= S.cards.size() - 1:
		_say("+ tween: pick a card that has a card after it")
		return
	var a := Moves._flat(S.cards[sel_card]["pose"])
	var b := Moves._flat(S.cards[sel_card + 1]["pose"])
	_push_undo()
	Scene.put(B, Scene.mix_flat(a, b, 0.5))
	if S.on_floor:
		S._ground(B)
	B.apply_grip()
	var mv: float = S.move_time(sel_card + 1) * 0.5
	S.cards[sel_card + 1]["move"] = mv
	S.add("tween", B.to_dict(), sel_card + 1)
	S.cards[sel_card + 1]["move"] = mv
	S.cards[sel_card + 1]["hold"] = 0.0
	sel_card += 1
	playhead = S.times()[sel_card][1]
	_sync = true
	ui_tween.value = 0.5
	_sync = false
	_rebuild_cards()
	_refresh()
	_say("added a tween card (%d): slide 'tween' to favour either side, then Update" % (sel_card + 1))


## a card's name (round 13: the agent test found no way to name a card at all). One undo step
## a double-click on a card's title: a name box in its place (Enter keeps the name, Esc or clicking away keeps the old)
func _card_title_input(ev: InputEvent, i: int, nb: Button) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.shift_pressed and mb.button_index == MOUSE_BUTTON_LEFT and sel_card >= 0 and not mb.double_click:
		nb.accept_event()   # Shift+click: the range to this card (X1); the picked card and the body stay
		sel_end = i if i != sel_card else -1
		_range_of = sel_card
		_rebuild_cards()
		var r := card_range()
		_say("cards %d-%d picked: Faster / Slower retime them all (a plain click picks one again)" % [r[0] + 1, r[-1] + 1])
		return
	if not (ev is InputEventMouseButton and ev.double_click and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	nb.accept_event()
	var ed := LineEdit.new()
	ed.name = "edit_card_name"
	ed.text = S.cards[i]["name"]
	ed.custom_minimum_size = nb.size
	nb.get_parent().add_child(ed)
	nb.get_parent().move_child(ed, nb.get_index())
	nb.visible = false
	ed.grab_focus()
	ed.select_all()
	ed.text_submitted.connect(func(t):
		ed.set_meta("done", true)   # the rename rebuilds the row, which takes the box's focus: not a cancel
		_step_hint = "Rename card"
		_card_rename(i, t))
	ed.focus_exited.connect(func():
		if not ed.has_meta("done"):
			ed.set_meta("done", true)
			_rebuild_cards.call_deferred())   # Esc / clicked away: the old name stays (after this event, never inside a rebuild)
	_say("type the card's new name, Enter keeps it (Esc: no change)")


## LOOP: close the seam (round 16, W2): the last card's pose = the first's, and the scene marked a loop
func _loop_close() -> void:
	if S.cards.size() < 2:
		_say("a loop needs 2 cards or more: add cards first (Enter)")
		return
	_push_undo()
	S.cards[-1]["pose"] = S.cards[0]["pose"].duplicate(true)
	S.loop = true
	if ui_loop != null:
		ui_loop.set_pressed_no_signal(true)
	check_ran = false
	_rebuild_cards()
	_ps().apply(B, playhead)
	_refresh()
	_say("the last card is now a copy of the first: the loop's end meets its start. Check grades the speed across it too.")


## PLANT EVERY SLIDING FOOT (round 43, GATES YY2): the work is Fixer.plant_all. One undo step, or none when it keeps nothing.
func _plant_all() -> void:
	_push_undo()
	var keep := B.state()
	var r := Fixer.plant_all(S, B)
	B.set_state(keep)   # Check samples the scene on B: the body goes back as it was
	if not r["kept"]:
		undo.pop_back()
		_say("%s. Press Check for the other rules" % r["msg"])
		return
	check_ran = false
	_rebuild_cards()
	_ps().apply(B, playhead)
	_refresh()
	_say("%s. One Ctrl+Z puts it back" % r["msg"])


## CLEAN UP MOCAP (round 42, GATES XX7): the work is in scripts/mocap_clean.gd. Needs a card per frame.
func _mocap_clean() -> void:
	if S.cards.size() < 8:
		_say("this scene has %d cards: clean-up reads a card per frame, like a .bvh import. Drop a .bvh on the window, or open an imported scene" % S.cards.size())
		return
	_push_undo()   # taken first, dropped again if nothing changed
	var keep := B.state()   # the analysis plays the scene on B; with nothing to do the body goes back as it WAS (the
	                        # playhead's pose is not always it: undo_audit, round 43, after the toe-off trim left nothing)
	var r := MocapClean.clean(S, B, {})
	if int(r["locked"]) + int(r["repaired"]) == 0:
		undo.pop_back()
		B.set_state(keep)
		_say("%s. Nothing to plant or mend: no standing foot and no pop in this scene. Press Check for the other rules" % r["text"])
		return
	check_ran = false
	_rebuild_cards()
	_ps().apply(B, playhead)
	_refresh()
	_say("%s. One Ctrl+Z puts it back" % r["text"])


func _card_rename(i: int, nm: String) -> void:
	nm = nm.strip_edges()
	if i < 0 or i >= S.cards.size() or nm == "":
		_say("pick a card and type a name (the name can't be empty)")
		return
	_push_undo()
	S.cards[i]["name"] = nm
	_rebuild_cards()
	_say("card %d is now '%s'" % [i + 1, nm])


func _card_update(i: int) -> void:
	_push_undo()
	S.cards[i]["pose"] = B.to_dict()
	if S.cards[i]["name"] == "pass-by":
		S.cards[i]["name"] = "pose %d" % (i + 1)
	_rebuild_cards()
	_say("card %d updated from the body" % (i + 1))


## SNAP TO FLOOR (ROADMAP 46): the picked card (or the body when no card is picked, or there are no cards) moves straight
## up or down so its lowest capsule point is on the floor; the joints stay. all = every card. One undo step
func _floor_snap(all := false) -> void:
	if all:
		if S.cards.is_empty():
			_say("no cards to snap: pose the body and press Enter to add it as a card, or use 'Snap to floor' for the body alone")
			return
		var n := S.cards.size()
		_do(func():
			FloorSnap.snap_all(S, B)
			S.apply(B, playhead)
			_rebuild_cards())
		_say("all %d cards are on the floor now: the lowest point of each is at 0 cm (Ctrl+Z takes it back)" % n)
		return
	if S.cards.is_empty():
		_do(func(): B.ground_body())
		_say("the body is on the floor now (Ctrl+Z takes it back)")
		return
	if sel_card < 0:
		_do(func(): B.ground_body())
		_say("the body is on the floor now, but no card is picked: click a card, then 'Update' keeps it there (Ctrl+Z takes it back)")
		return
	var i := sel_card
	_do(func():
		S.cards[i]["pose"] = FloorSnap.snapped_pose(B, S.cards[i]["pose"])
		S.apply(B, playhead)
		_rebuild_cards())
	_say("card %d is on the floor now: the lowest point at 0 cm, the joints as they were (Ctrl+Z takes it back)" % (i + 1))


func _card_del(i: int) -> void:
	_push_undo()
	S.cards.remove_at(i)
	sel_card = mini(sel_card, S.cards.size() - 1)
	playhead = minf(playhead, _ps().length())
	_rebuild_cards()
	_refresh()


func _card_move(i: int, d: int) -> void:
	var j := i + d
	if j < 0 or j >= S.cards.size():
		return
	_push_undo()
	var c = S.cards[i]
	S.cards[i] = S.cards[j]
	S.cards[j] = c
	sel_card = j
	_rebuild_cards()
	_refresh()


## FRAMES + PREVIEW RANGE (WW4, #262/#263): view settings, see scripts/preview_range.gd
func _toggle_frames() -> void:
	frames_view = not frames_view
	_say("the time shows in %s (click it to flip)" % ("frames, at %d fps" % S.fps if frames_view else "seconds"))
	_refresh()


func _pv_set(which: String, t: float) -> void:
	if which == "clear":
		pv_in = -1.0
		pv_out = -1.0
		_say("preview range cleared: Play and Loop use the whole scene")
	else:
		var at := playhead if t < 0.0 else t
		if which == "in":
			pv_in = at
		else:
			pv_out = at
		var sp := PreviewRange.span(pv_in, pv_out, _ps().length())
		if sp.is_empty():
			_say("%s point at %s; set the other one after it (the range must be longer than a frame)" % [which, Units.time(at, S.fps)])
		else:
			_say("preview range %s to %s: Play and Loop stay inside it (a view setting, not saved)" % [Units.time(sp[0], S.fps), Units.time(sp[1], S.fps)])
	_refresh()


func _fps_next() -> void:
	var k: int = PreviewRange.FPS_CHOICES.find(S.fps)
	_set_fps(PreviewRange.FPS_CHOICES[(k + 1) % PreviewRange.FPS_CHOICES.size()])


func _set_fps(f: int) -> void:
	if f == S.fps:
		_say("already at %d fps: run Frame rate: next to choose another" % f)
		return
	_push_undo()
	S.fps = f
	var off := PreviewRange.off_grid(S, f)
	if off == 0:
		_say("%d fps: every card keeps its seconds, all on whole frames" % f)
	else:
		_say("%d fps: every card keeps its seconds; %d card time%s not on a whole frame" % [f, off, " is" if off == 1 else "s are"])
	_refresh()


func _toggle_play() -> void:
	if S.cards.size() < 2:
		_say("a scene needs two cards or more to play: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	playing = not playing
	_a_after = -1.0   # the sound starts (or stops) with the next frame
	if playing and playhead >= _ps().length() - 0.01:
		playhead = 0.0
	var sp := PreviewRange.span(pv_in, pv_out, _ps().length())
	if playing and not sp.is_empty() and (playhead < sp[0] or playhead >= sp[1] - 0.01):
		playhead = sp[0]   # WW4: Play starts inside the range
	if playing:
		play_clock.start(play_clock.mode)   # ROADMAP 48: each pass counts its own dropped frames and speed
	_refresh()


## ROADMAP 48: REAL SPEED / EVERY FRAME, the playback mode. A view setting: the scene is not changed, no undo step.
func _mode_toggle() -> void:
	var nxt := PlaySpeed.next_mode(play_clock.mode)
	play_clock.start(nxt)
	_mode_paint()
	var what := "the playhead keeps wall-clock time: a slow machine skips frames" if nxt == PlaySpeed.REAL else "each frame is shown once, in order, even when that is slower than real time"
	_say("%s: %s.  Click again for %s" % [PlaySpeed.label(nxt, 0, 0.0), what, "Every frame" if nxt == PlaySpeed.REAL else "Real speed"])


## the mode's icon, words and colour on the bar (Tok: info for real speed, say for every frame), set when either changes
func _mode_paint() -> void:
	if ui_mode_btn == null:
		return
	var key := "%s|%s" % [play_clock.mode, Tok.dark]
	if key == _mode_painted:
		return
	_mode_painted = key
	var real := play_clock.mode == PlaySpeed.REAL
	ui_mode_btn.text = "Real speed" if real else "Every frame"
	ui_mode_btn.icon = Icons.tex("realtime" if real else "frames")
	ui_mode_btn.tooltip_text = "Real speed: the playhead keeps wall-clock time (a slow machine skips frames).\nEvery frame: each frame is shown once, in order, even when slower than real time.\nclick: change it"
	var col := Tok.c("info" if real else "say")
	for k in ["font_color", "font_hover_color", "font_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		ui_mode_btn.add_theme_color_override(k, col)
	if ui_mode_lbl != null:
		ui_mode_lbl.add_theme_color_override("font_color", col)   # the base colour; the poll sets "warn" while frames drop


## NEW EMPTY SCENE (one function for its button and its registry entry; round 20, GATES AA3: the two copies did not
## refresh, so the speed graph stayed up over the empty scene with the old scene's curves)
func _new_scene() -> void:
	_actors_home()   # TC3
	if not vdiff.is_empty():   # COMPARE WITH: a comparison belongs to the scene it was made in
		_vdiff_clear()
	S = Scene.new()
	scene_path = ""
	_clean = _doc_key()   # the new empty scene is the saved state: nothing unsaved until it is edited (ROADMAP 50)
	_show_open_scene()
	check_ran = false
	sel_card = -1
	playhead = 0.0
	_rebuild_cards()
	_refresh()


func _clear_scene() -> void:
	var keep := B.state()   # lossless (round 8): to_dict rounds, so the live body jumped a rounding step
	_push_undo()   # round 8 (undo audit): the pass-by cards it adds could not be undone
	var n := S.clear(B)
	B.set_state(keep)
	if n == 0:
		undo.pop_back()   # nothing added: no empty undo step
	_rebuild_cards()
	_refresh()
	_say("added %d pass-by card(s) so nothing goes through the body" % n if n > 0 else "no move goes through the body")


# ---------------------------------------------------------------- files

func _stamp() -> String:
	return Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")


func _write(path: String, d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()


func _save_pose() -> void:
	var nm := safe_file(ui_pose_name.text).replace("_wip/", "")   # X3: a safe file name (poses have no _wip)
	var path := "res://moves/%s.json" % (nm if nm != "" else "pose_" + _stamp())
	if FileAccess.file_exists(path):
		_confirm("A pose called '%s' already exists.\nReplace it with the body as it is now? Ctrl+Z can't bring the old file back." % path.get_file().get_basename(),
			"Replace it", _save_pose_now.bind(path))
		return
	_save_pose_now(path)


func _save_pose_now(path: String) -> void:
	var d := B.to_dict()
	d["note"] = "angles in degrees from rest (bend, side, twist; meaning in data/body_limits.json 'say'); A = the joint's turn in rest axes, G = its turn from rest in the world now (quaternions x,y,z,w); pos/end in metres, character space (+Y up, +Z forward, +X his left); contacts = parts inside each other (m). Math: MATH.md"
	_write(path, d)
	_lists()
	_say("saved pose " + path.get_file())


## THE BROWSER'S POSES (RR3): a pose row applies the pose; its menu renames / deletes it / makes a clip of it. Rename and
## Save ask the name in a small dialog (the old panel's name box)
var ui_name_dlg: ConfirmationDialog
var _name_for := "save"


func _pose_apply(i: int) -> void:
	if ui_poses.get_selected_items() != PackedInt32Array([i]):
		ui_poses.select(i)
	_push_undo()
	_load_pose(ui_poses.get_item_metadata(i))
	_refresh()
	_say("the body is now in pose '%s'" % ui_poses.get_item_text(i))


func _pose_ask(what: String, i := -1) -> void:
	if i >= 0:
		ui_poses.select(i)
	_name_for = what
	ui_name_dlg.title = "Rename the pose" if what == "rename" else "Save the body as a pose"
	ui_name_dlg.ok_button_text = "Rename" if what == "rename" else "Save pose"
	ui_pose_name.text = ui_poses.get_item_text(i).get_slice("   ", 0) if what == "rename" and i >= 0 else ""
	ui_name_dlg.popup_centered()
	ui_pose_name.grab_focus.call_deferred()
	ui_pose_name.select_all.call_deferred()


## a browser row's right-click menu: [label, callable] items (main builds them; the tree only asks)
var ui_ctx: PopupMenu
var ui_ctx_items: Array = []


func _row_menu(md: Dictionary, at: Vector2) -> void:
	var items := []
	if md.has("pose"):
		var i: int = md["pose"]
		items = [["Apply", _pose_apply.bind(i)], ["CLIP this pose (Enter)", func(): _pose_apply(i); _card_add()],
			["Rename...", _pose_ask.bind("rename", i)], ["Delete pose", func(): ui_poses.select(i); _delete_pose()]]
	elif md.get("menu", "") == "poses":
		items = [["Save pose...", _pose_ask.bind("save")], ["Pose library (pictures)...", PoseLibrary.toggle.bind(self)]]
	elif md.get("menu", "") == "dummy":
		items = [["On/off (H)", _dummy_toggle], ["Closer", _dummy_move.bind(-0.25)], ["Farther", _dummy_move.bind(0.25)],
			["Solid / see-through", _dummy_solid]]
	elif md.has("card"):
		items = [["Show this clip", _timeline_pick.bind(md["card"])]]
	elif md.has("hit"):
		items = [["Go to this contact", _goto_hit.bind(md["hit"])]]
	elif md.has("pset") or String(md.get("menu", "")).begins_with("psets"):
		items = PartSets.of(self).menu(md)   # selection / keying sets (part_sets.gd)
	if items.is_empty():
		return
	if ui_ctx == null:
		ui_ctx = PopupMenu.new()
		ui_ctx.name = "browser_menu"
		ui_ctx.id_pressed.connect(func(id): (ui_ctx_items[id][1] as Callable).call())
		add_child(ui_ctx)
	ui_ctx.clear()
	ui_ctx_items = items
	for k in items.size():
		ui_ctx.add_item(items[k][0], k)
	ui_ctx.position = Vector2i(at)
	ui_ctx.reset_size()
	ui_ctx.popup()


## Nick 10-13: "the option to rename poses, now it's just random names, hard to find". Only his own (moves/):
## the library and the starter poses are named by the tools that use them.
func _rename_pose() -> void:
	var sel_i := ui_poses.get_selected_items()
	if sel_i.is_empty():
		_say("click the pose to rename in the list first")
		return
	var old: String = ui_poses.get_item_metadata(sel_i[0])
	if not old.begins_with("res://moves/"):
		_say("only your own poses can be renamed (the library + starter poses keep their names): pick one you saved, or Save pose this one under a new name")
		return
	var nm := ui_pose_name.text.strip_edges().replace(" ", "_")
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		nm = nm.replace(bad, "")
	if nm == "":
		_say("type the new name first")
		return
	var path := "res://moves/%s.json" % nm
	if FileAccess.file_exists(path):
		_say("a pose called '%s' already exists: pick it again > Rename... and type another name" % nm)
		return
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(old), ProjectSettings.globalize_path(path))
	if err != OK:
		_say("couldn't rename (error %d): close any program that has the file open, then press Rename again" % err)
		return
	ui_pose_name.text = ""
	_lists()
	_say("renamed %s -> %s" % [old.get_file().get_basename(), nm])


## CONFIRM ONLY WHAT CAN'T BE UNDONE (round 11, #76). Every edit to the body or the cards is one Ctrl+Z away and asks
## nothing. What touches a FILE can't be undone, so it asks once, naming the file:
##   Delete pose / Delete scene      -> the file moves to trash/ (round 11: a dialog; it was "press twice")
##   Save scene / Save pose onto ANOTHER file of that name -> it would be replaced
##   Save grip                       -> replaces the standard grip in data/grips/
## Not asked: saving the open scene onto its own file (that is what Save means), Polish / Mirror the scene (they write
## a NEW copy in scenes/_wip/, a machine copy remade on each press), a test's own settings file.
var ui_confirm: ConfirmationDialog
var _confirm_do: Callable


func _confirm(msg: String, ok_text: String, f: Callable) -> void:
	if ui_confirm == null:
		ui_confirm = ConfirmationDialog.new()
		ui_confirm.title = "Can't be undone"
		ui_confirm.dialog_autowrap = true
		ui_confirm.min_size = Vector2i(420, 0)
		ui_confirm.confirmed.connect(func(): _confirm_do.call())
		ui_confirm.canceled.connect(func(): _say("nothing changed"))
		add_child(ui_confirm)
	_confirm_do = f
	ui_confirm.dialog_text = msg
	ui_confirm.ok_button_text = ok_text
	ui_confirm.popup_centered()
	_say(msg.get_slice("\n", 0))


## SAVE PROMPTS (ROADMAP 50): the window's close, New and opening another scene ask "Save changes to <name>?" when the
## open scene has unsaved changes: Save (then the same thing goes on), Don't save (it goes on and the work is thrown
## away, its autosave and journal with it), Cancel (nothing happens, the scene stays open). Nothing unsaved: no dialog.
## A crash or a kill never reaches this code: the journal still offers the work at the next start.
var ui_save_ask: ConfirmationDialog
var _save_ask_then: Callable      # what goes on after Save or Don't save
var _save_ask_quit := false       # the question is for the window's close: Don't save then quits without a dialog
var _discarding := false          # Don't save on the way out: the exit drops the autosave and the journal too
var quit_fn: Callable             # a test's stand-in for get_tree().quit() (empty in the app)
var save_hook: Callable           # a test's stand-in for Save (the real one writes scenes/, which a test never does)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:   # the X, Alt+F4, the OS: the app decides (set_auto_accept_quit is off)
		_close_asked()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_theme()


func _close_asked() -> void:
	if ui_save_ask != null and ui_save_ask.visible:
		return   # already asking
	if _unsaved():
		_ask_save(_scene_label(), _quit_app, true)
	else:
		_quit_app()


func _quit_app() -> void:
	if quit_fn.is_valid():
		quit_fn.call()
		return
	get_tree().quit()


func _scene_label() -> String:
	var H := _hero_scene()
	return H.name if H.name != "" else "this scene"


## asks Save / Don't save / Cancel about the open scene, then calls `then` (not on Cancel). Pressing Esc or the X is Cancel
func _ask_save(what: String, then: Callable, quitting := false) -> void:
	if ui_save_ask == null:
		ui_save_ask = ConfirmationDialog.new()
		ui_save_ask.title = "Unsaved changes"
		ui_save_ask.dialog_autowrap = true
		ui_save_ask.min_size = Vector2i(440, 0)
		ui_save_ask.ok_button_text = "Save"
		ui_save_ask.add_button("Don't save", false, "discard")
		ui_save_ask.confirmed.connect(func(): _save_ask_choose("save"))
		ui_save_ask.custom_action.connect(func(a: StringName): _save_ask_choose(String(a)))
		ui_save_ask.canceled.connect(func(): _save_ask_choose("cancel"))
		add_child(ui_save_ask)
	_save_ask_then = then
	_save_ask_quit = quitting
	ui_save_ask.dialog_text = "Save changes to %s?\nThey are not saved yet. Don't save throws them away." % what
	ui_save_ask.popup_centered()
	_say("Save changes to %s? Save keeps them, Don't save throws them away, Cancel keeps the scene open" % what)


## how = "save" | "discard" | "cancel" (the dialog's buttons, and what a test calls)
func _save_ask_choose(how: String) -> void:
	ui_save_ask.hide()
	var then := _save_ask_then
	_save_ask_then = Callable()
	if how == "cancel" or not then.is_valid():
		_say("kept open: the scene stays as it is (Save scene keeps your work)")
		return
	if how == "discard":
		_discarding = _save_ask_quit
		_autosave_drop()   # the work goes: no Recover offer for it next start
		if journal_on:
			journal.trim()
		then.call()
		return
	if save_hook.is_valid():
		save_hook.call()
	else:
		_save_scene()
	if _unsaved():   # the save did not happen (an empty name, a co-edit guest, or a replace question is up now)
		_say("not saved yet, so the scene stays open: answer the question, or Save scene, then close or open again")
		return
	then.call()


func _trash(path: String) -> void:
	_confirm("Move '%s' to the trash folder?\nIt is kept in trash/ (put it back by hand); Ctrl+Z can't bring it back." % path.get_file().get_basename(),
		"Move to trash", _trash_now.bind(path))


func _trash_now(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://trash"))
	var to := "res://trash/%s_%s.json" % [path.get_file().get_basename(), _stamp()]
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(to))
	if err != OK:
		_say("couldn't delete (error %d): close any program that has the file open, then press Delete again" % err)
		return false
	_lists()
	_say("deleted '%s' (in trash/ if you want it back)" % path.get_file().get_basename())
	return true


func _delete_pose() -> void:
	var sel_i := ui_poses.get_selected_items()
	if sel_i.is_empty():
		_say("click the pose to delete in the list first")
		return
	var path: String = ui_poses.get_item_metadata(sel_i[0])
	if path.begins_with("res://poses/lib/"):
		_say("library poses stay (the tools use them): pick one of your own poses to delete")
		return
	_trash(path)


func _delete_scene() -> void:
	if ui_scenes.selected < 0:
		_say("pick the scene to delete in the list first")
		return
	_trash(ui_scenes.get_item_metadata(ui_scenes.selected))


## SPEED (Nick 10-13: "speed in some of them need a little adjustment"): the picked card's move + hold, or every card's,
## times k (1.1 = 10% slower). An auto move becomes its number first, so it scales too.
func _speed(k: float) -> void:
	if S.cards.is_empty():
		_say("open a scene first")
		return
	_push_undo()   # round 8 (undo audit): Faster / Slower changed every card's timing with no way back
	var idx := card_range() if not card_range().is_empty() else range(S.cards.size())   # X1: a Shift+click range too
	var mv := idx.map(func(i): return S.move_time(i) if i > 0 else 0.0)   # all read before any is written
	for n in idx.size():
		var i: int = idx[n]
		var c: Dictionary = S.cards[i]
		if i > 0:
			c["move"] = snappedf(maxf(0.04, mv[n] * k), 0.01)
		c["hold"] = snappedf(float(c["hold"]) * k, 0.01)
	_rebuild_cards()
	_refresh()
	_say("%s %s: the scene is now %s (Save scene keeps it)" % ["card '%s'" % S.cards[sel_card]["name"] if idx.size() == 1 and sel_card >= 0 else ("cards %d-%d" % [idx[0] + 1, idx[-1] + 1] if idx.size() < S.cards.size() or sel_end >= 0 else "whole scene"), "slower" if k > 1.0 else "faster", Units.time(_ps().length(), S.fps)])


func _load_pose(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d.has("keys") or d.has("cards"):
		_load_scene(path)
		return
	B.from_dict(d)
	B.capture_second()   # a pose with both hands on the shaft loads with both hands holding it


func _save_scene() -> void:
	if _hero_scene().cards.is_empty():
		_say("the scene is empty: press Enter to add the body as a card, then Save scene")
		return
	var nm := ui_scene_name.text.strip_edges()
	var to := "res://scenes/%s.json" % (safe_file(nm) if safe_file(nm) != "" else "scene_" + _stamp())
	if FileAccess.file_exists(to) and to != scene_path:
		_confirm("A different scene called '%s' already exists.\nReplace it with this one? Ctrl+Z can't bring the old file back." % to.get_file().get_basename(),
			"Replace it", _save_scene_now.bind(nm))
		return
	_save_scene_now(nm)


## A NAME AS A FILE (round 17, GATES X3): the name as typed stays the scene's (or pose's) name, shown and saved inside the
## file; the FILE's name is made safe: / \ : * ? " < > | and control characters -> _, spaces -> _ (as before),
## no leading dot (so no "..": nothing escapes the folder), no trailing dot or space (Windows drops them), a Windows
## device name (CON, NUL, COM1...) gets a _, at most 100 characters. Letters of any script and emoji stay. One leading
## "_wip/" is kept as the folder (machine copies and tests save there)
static func safe_file(nm: String) -> String:
	nm = nm.strip_edges()
	var pre := ""
	if nm.begins_with("_wip/") or nm.begins_with("_wip\\"):
		pre = "_wip/"
		nm = nm.substr(5)
	var out := ""
	for ch in nm:
		out += "_" if ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "] or ch.unicode_at(0) < 32 else ch
	out = out.rstrip(".")
	while out.begins_with("."):
		out = "_" + out.substr(1)
	var stem := out.get_slice(".", 0).to_upper()
	if stem in ["CON", "PRN", "AUX", "NUL"] or (stem.length() == 4 and (stem.begins_with("COM") or stem.begins_with("LPT")) and stem[3] in "123456789"):
		out += "_"
	out = out.left(100)
	return pre + out if out != "" else ""


func _save_scene_now(nm: String) -> void:
	if co != null and co.connected() and not co.is_host:
		_say("live co-edit: the host saves the scene (your fighter's work is on its side too): ask the host to save, or save your own copy under another name")
		return
	var H := _hero_scene()   # TC3: the file is the hero's scene, whoever is active
	H.name = nm if nm != "" else "scene_" + _stamp()   # the name as typed: what the scene is called
	var d := _scene_dict()   # TC3: the hero's file with its actors (lossless: the body kept, round 8)
	var fname := safe_file(H.name) if safe_file(H.name) != "" else "scene_" + _stamp()
	_write("res://scenes/%s.json" % fname, d)
	_clean = _doc_key()
	_autosave_drop()
	scene_path = "res://scenes/%s.json" % fname
	_recent_note(scene_path)
	_journal_saved()
	_lists()
	_refresh()
	_say("saved scene %s: %d cards, %s, %d frames with parts inside each other" % [H.name, H.cards.size(), Units.time(H.length(), S.fps), d["bad_frames"].size()])


## the scene list's pick: opens it at once when nothing would be lost, asks first when the scene open now has changes
## that are not saved (opening can't be undone)
func _scene_picked(i: int) -> void:
	_open_scene_file(ui_scenes.get_item_metadata(i))


## opens a scene file the one way every pick does (the scene list, the S box's scene rows): at once, or asking first
## when the scene open now has unsaved changes
func _open_scene_file(path: String) -> void:
	if path == scene_path and _unsaved() == false:
		return
	var go := func():
		_load_scene(path)
		_rebuild_cards()
		_refresh()
	if _unsaved():
		_ask_save(_scene_label(), go)   # ROADMAP 50: Save / Don't save / Cancel
	else:
		go.call()


## New empty scene: asks first when the open scene has unsaved changes (ROADMAP 50)
func _new_asked() -> void:
	if _unsaved():
		_ask_save(_scene_label(), _new_scene)
	else:
		_new_scene()


## THE S BOX'S FILES (ROADMAP 52): the saved poses and scenes, listed the way _lists() lists them (poses/lib, poses,
## moves/ for a pose file; scenes, moves/ and scenes/_wip for a scene file: a file with cards or keys is a scene). Read
## when the box opens, not per keystroke
func _search_files() -> Array:
	var rows := []
	var scene := {}   # path -> is a scene file (each file read once)
	for dir in ["res://poses/lib", "res://poses", "res://moves", "res://scenes", "res://scenes/_wip"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			if not f.ends_with(".json"):
				continue
			var path: String = dir + "/" + f
			if not scene.has(path):
				var txt := FileAccess.get_file_as_string(path)
				scene[path] = txt.contains("\"keys\"") or txt.contains("\"cards\"")
			var is_scene: bool = scene[path]
			# poses/ holds pose files and scenes/ scene files; moves/ holds both (each goes to the list the app shows it in)
			if (is_scene and dir.begins_with("res://poses")) or (not is_scene and dir.begins_with("res://scenes")):
				continue
			rows.append(_file_row(path, "scene" if is_scene else "pose"))
	for mac in macros:   # ROADMAP 81: each saved macro is a row "Macro: <name>"
		var nm: String = mac["name"]
		rows.append({"name": Macros.ROW + nm, "kind": "macro", "also": "macro play recorded", "keys": "", "run": _macro_play.bind(nm),
			"desc": "%d steps, played on the part picked now: ONE undo step (Ctrl+Z takes all of it back)" % mac["steps"].size()})
	return rows


func _file_row(path: String, kind: String) -> Dictionary:
	var nm := path.get_file().get_basename().replace("_", " ")
	if kind == "pose":
		return {"name": nm, "kind": kind, "also": "pose", "keys": "", "run": _search_pose.bind(path),
			"desc": "%s: the body takes this pose (one undo step)" % path}
	return {"name": nm, "kind": kind, "also": "scene", "keys": "", "run": _open_scene_file.bind(path),
		"desc": "%s: opens the scene (asks first when this one has unsaved changes)" % path}


## MACROS (ROADMAP 81). Record: each palette command run while recording is a step; the words of a "Pose: ..." row are
## kept too. Play: the steps run in order on the part picked NOW (a step that needs a part stops the macro, naming the
## step, when none is picked); the whole play is one undo step. Undo / Redo / the macro commands are never steps.
const MACRO_SKIP := ["Record macro", "Stop macro recording", "Play macro...", "Undo", "Redo"]


func _macro_record() -> void:
	if rec_name != "":
		_say("already recording '%s': run the commands, then Stop macro recording" % rec_name)
		return
	rec_name = Macros.new_name(macros)
	rec_steps = []
	_macro_indicator()
	_say("recording '%s': each palette command you run is a step. Stop macro recording saves it" % rec_name)


func _macro_stop() -> void:
	if rec_name == "":
		_say("not recording: run Record macro first, then the commands, then Stop macro recording")
		return
	var nm := rec_name
	var n := rec_steps.size()
	if n > 0:
		macros.append({"name": nm, "steps": rec_steps})
	rec_name = ""
	rec_steps = []
	_macro_indicator()
	if n == 0:
		_say("'%s' has no steps, so nothing was saved: Record macro, run a command, then Stop" % nm)
	elif Macros.save_file(macros_file, macros):
		_say("saved '%s' with %d steps: type 'macro' in the S box to play it on any part" % [nm, n])
	else:
		_say("'%s' is kept for this session only: %s could not be written" % [nm, macros_file])


## a palette command or a Pose: row run while recording becomes a step (main's running signal, before it runs)
func _macro_note(n: String) -> void:
	if rec_name == "" or _macro_nest > 0 or n in MACRO_SKIP or n.begins_with(Macros.ROW):
		return
	var c := _command_named(n)
	if not c.is_empty():
		var has := B.ang.has(sel)
		rec_steps.append({"name": n, "words": "", "part": sel if has else "", "needs_part": bool(c["edits"]) and has})
	elif n.begins_with("Pose: "):
		rec_steps.append({"name": n, "words": n.substr(6), "part": "", "needs_part": false})
	else:
		return   # a saved pose or scene row is not a command: not a step
	_macro_indicator()


func _command_named(n: String) -> Dictionary:
	for c in ui_cmd.commands:
		if c["name"] == n:
			return c
	return {}


func _macro_indicator() -> void:
	rec_label.visible = rec_name != ""
	rec_label.text = "REC  %s   %d step%s   (Stop macro recording saves it)" % [rec_name, rec_steps.size(), "" if rec_steps.size() == 1 else "s"]


func _macro_play(nm: String) -> void:
	var mac := Macros.find(macros, nm)
	if mac.is_empty():
		_say("there is no macro called '%s': type 'macro' in the S box to see the saved ones" % nm)
		return
	if rec_name != "":
		_say("stop recording first: '%s' cannot play while '%s' is being recorded (Stop macro recording)" % [nm, rec_name])
		return
	var steps: Array = mac["steps"]
	_macro_nest = 1
	_macro_pushed = false
	_step_hint = Macros.ROW + nm   # the one undo step is named after the macro
	var stop := ""
	var done := 0
	for i in steps.size():
		var st: Dictionary = steps[i]
		var where := "step %d of %d (%s)" % [i + 1, steps.size(), st["name"]]
		if st["needs_part"] and not B.ang.has(sel):
			stop = "stopped at %s: it needs a body part picked, and none is (the weapon or nothing is). Pick a body part, then run %s%s again" % [where, Macros.ROW, nm]
			break
		if st["words"] != "":
			var r: Dictionary = _pose_words(st["words"])
			if not r["ok"]:
				stop = "stopped at %s: %s" % [where, String(r["error"])]
				break
		else:
			var c := _command_named(st["name"])
			if c.is_empty():
				stop = "stopped at %s: that command is gone. Record the macro again" % where
				break
			(c["run"] as Callable).call()
		done += 1
	var opened := _macro_pushed   # an edit ran: the play's one undo step exists
	_macro_nest = 0
	_step_hint = ""
	_refresh()
	if stop == "":
		_say("played '%s': %d steps, one undo step (Ctrl+Z takes it back)" % [nm, done])
	elif opened:
		_say("Macro '%s' %s. The %d step(s) before it are one undo step: Ctrl+Z takes them back" % [nm, stop, done])
	else:
		_say("Macro '%s' %s. Nothing in the scene changed" % [nm, stop])


## a pose row of the S box: the body takes the pose, one undo step (the same as a pick in the Poses list)
func _search_pose(path: String) -> void:
	_push_undo()
	_load_pose(path)
	_refresh()
	_say("the body is now in pose '%s'" % path.get_file().get_basename().replace("_", " "))


var _clean := "[]"   # the cards as last opened or saved: anything else is unsaved work
var sel_end := -1    # X1: Shift+click a second card = the range from sel_card to it (-1 = just the picked card)
var _range_of := -1  # the picked card the range was made from: anything else picking a card ends the range


## the picked cards: the range sel_card..sel_end (either order), the one picked card, or none
func card_range() -> Array:
	if sel_card < 0 or sel_card >= S.cards.size():
		return []
	if sel_end < 0 or sel_end >= S.cards.size() or _range_of != sel_card:
		return [sel_card]
	return range(mini(sel_card, sel_end), maxi(sel_card, sel_end) + 1)


## RETIME (round 16+1, GATES X1): cards a..b (0-based, inclusive) play at pct %: the move into each and its hold x pct/100
## (to 1 ms). "" = done, else what was wrong. One undo step
func retime(a: int, b: int, pct: float) -> String:
	if S.cards.size() < 2:
		return "retime needs a scene of 2+ cards"
	if a < 0 or b >= S.cards.size() or a > b:
		return "no cards %d-%d (the scene has %d; the first must not be after the last)" % [a + 1, b + 1, S.cards.size()]
	if not (pct >= 10.0 and pct <= 1000.0):
		return "retime by 10 to 1000 %% (100 = as it is), not %s" % pct
	_push_undo()
	_markers_hold()
	S.retime(a, b, pct)   # the loop lives in Scene.retime (TextBlocking retimes a blocking by the same op)
	_markers_follow()
	_rebuild_cards()
	_refresh()
	_say("cards %d-%d at %.0f %%: the scene is now %s (Save scene keeps it)" % [a + 1, b + 1, pct, Units.time(_ps().length(), S.fps)])
	return ""


## AUTOSAVE (round 16, GATES W1): the unsaved scene to `autosave`, atomically: a temp file, then a rename, so a crash
## in the middle leaves the last good copy. Nothing unsaved, or nothing new since the last write: no write
func autosave_now() -> bool:
	if not _unsaved():
		return false
	var d := _scene_dict(false)   # TC3: the hero's file with its actors (the body kept). No bad_frames: that whole-scene
	# collision playback froze the app 1.4-7 s every 15 s on a two-fighter combo3; Save scene still writes them
	var what := JSON.stringify([d, scene_path])   # what is held, without the time: the same twice = no write
	if what == _as_last:
		return false
	var js := JSON.stringify({"scene": d, "path": scene_path, "at": Time.get_datetime_string_from_system(false, true)}, " ")
	var fp := ProjectSettings.globalize_path(autosave)
	DirAccess.make_dir_recursive_absolute(fp.get_base_dir())
	var f := FileAccess.open(fp + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(js)
	f.close()
	if DirAccess.rename_absolute(fp + ".tmp", fp) != OK:
		return false
	_as_last = what
	_ring_push(fp)
	return true


func _autosave_drop() -> void:
	var fp := ProjectSettings.globalize_path(autosave)
	for q in [fp, fp + ".tmp"]:
		if FileAccess.file_exists(q):
			DirAccess.remove_absolute(q)
	_as_last = ""


## RESTORE... (ROADMAP 59): every autosave written is also kept as the newest of RING_N rotating copies:
## user://autosave_1.json (the newest) .. user://autosave_5.json (the oldest; the next write drops it). A copy of the
## autosave file's bytes. A save or a quit does not drop them: the history is what Restore... is for, and it is bounded
func _ring_path(n: int) -> String:
	return autosave.get_basename() + "_%d.json" % n


func _ring_push(fp: String) -> void:
	if FileAccess.file_exists(_ring_path(RING_N)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_ring_path(RING_N)))
	for n in range(RING_N - 1, 0, -1):
		if FileAccess.file_exists(_ring_path(n)):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(_ring_path(n)), ProjectSettings.globalize_path(_ring_path(n + 1)))
	DirAccess.copy_absolute(fp, ProjectSettings.globalize_path(_ring_path(1)))


## the kept autosaves, newest first: {path, at, name, cards, a} (a = the file's {scene, path, at}); unreadable ones skipped
func _ring_list() -> Array:
	var out := []
	for n in range(1, RING_N + 1):
		var p := _ring_path(n)
		if not FileAccess.file_exists(p):
			continue
		var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if not (a is Dictionary) or not (a.get("scene") is Dictionary) or not (a["scene"] as Dictionary).has("cards"):
			continue
		out.append({"path": p, "at": String(a.get("at", "")), "name": String(a["scene"].get("name", "")) if String(a["scene"].get("name", "")) != "" else String(a.get("path", "")).get_file().get_basename(), "cards": (a["scene"]["cards"] as Array).size(), "a": a})
	return out


## File > Restore...: the kept autosaves as a list (newest first) with a picture of the picked one. The copy is made by
## _restore_copy, after the scene on screen is saved or given up (it asks)
var ui_restore: AcceptDialog
var ui_restore_list: ItemList
var ui_restore_pic: TextureRect
var ui_restore_info: Label
var _restore_rows: Array = []
var _restore_shown := ""   # the autosave file whose picture the dialog shows


func _restore_open() -> void:
	_restore_rows = _ring_list()
	if _restore_rows.is_empty():
		_say("no autosaves kept yet: Kine keeps the last %d as you edit an unsaved scene (open File > Restore... to list them)" % RING_N)
		return
	if ui_restore == null:
		_restore_build()
	ui_restore_list.clear()
	for r in _restore_rows:
		ui_restore_list.add_item("%s   %s   %d cards" % [r["at"], r["name"] if r["name"] != "" else "(no name)", r["cards"]])
	ui_restore_list.select(0)
	_restore_pick(0)
	ui_restore.popup_centered()


func _restore_build() -> void:
	ui_restore = AcceptDialog.new()
	ui_restore.name = "restore_dialog"
	ui_restore.title = "Restore an autosave"
	ui_restore.ok_button_text = "Open as a new copy"
	ui_restore.min_size = Vector2i(620, 440)
	ui_restore.size = Vector2i(620, 440)   # the buttons sit at its foot: the content must not push them off the window
	var vb := VBoxContainer.new()
	vb.name = "restore_box"
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_bottom = -60
	ui_restore.add_child(vb)
	ui_restore_list = ItemList.new()
	ui_restore_list.name = "restore_list"
	ui_restore_list.custom_minimum_size = Vector2(0, 160)
	ui_restore_list.item_selected.connect(_restore_pick)
	vb.add_child(ui_restore_list)
	var hb := HBoxContainer.new()
	hb.name = "restore_row"
	vb.add_child(hb)
	ui_restore_pic = TextureRect.new()
	ui_restore_pic.name = "restore_pic"
	ui_restore_pic.custom_minimum_size = Vector2(SceneThumbs.SIZE.x * 3, SceneThumbs.SIZE.y * 3)
	ui_restore_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ui_restore_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(ui_restore_pic)
	ui_restore_info = Label.new()
	ui_restore_info.name = "restore_info"
	ui_restore_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_restore_info.custom_minimum_size = Vector2(280, 0)
	ui_restore_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ui_restore_info)
	ui_restore.confirmed.connect(_restore_go)
	add_child(ui_restore)


## the picked autosave: its time, scene, cards; its picture (drawn at once when cached, else when its turn comes)
func _restore_pick(i: int) -> void:
	if i < 0 or i >= _restore_rows.size():
		return
	var r: Dictionary = _restore_rows[i]
	_restore_shown = r["path"]
	ui_restore_info.text = "autosaved %s\n'%s', %d cards\nOpens as a NEW copy in scenes/_wip. The scene you have open and its file are not touched" % [
		r["at"], r["name"] if r["name"] != "" else "(no name)", r["cards"]]
	if thumbs != null:
		thumbs.request(r["path"])
		ui_restore_pic.texture = thumbs.picture(r["path"])


func _restore_go() -> void:
	var sel := ui_restore_list.get_selected_items()
	if sel.is_empty():
		_say("pick an autosave in the list, then Open as a new copy")
		return
	var r: Dictionary = _restore_rows[sel[0]]
	var go := func(): _restore_copy(r)
	if _unsaved():
		_ask_save(_scene_label(), go)   # asks first: opening replaces the scene on screen
	else:
		go.call()


## the autosave as a NEW scene in scenes/_wip, named after its scene (never over a file: _2, _3), opened as a clean copy
func _restore_copy(r: Dictionary) -> void:
	var a: Dictionary = r["a"]
	var nm := safe_file(String(r["name"])).trim_prefix("_wip/")
	var path := TextBlocking.unique_path("res://scenes/_wip", (nm if nm != "" else "autosave") + "_restored")
	_write(path, a["scene"])
	_load_scene(path)
	_rebuild_cards()
	_refresh()
	_say("restored the autosave from %s as scenes/_wip/%s: %d cards. Your scenes are untouched" % [r["at"], path.get_file(), r["cards"]])


## RECENT (ROADMAP 59): the scenes opened or saved, newest first, at most RECENT_N, in the settings file [recent] scenes.
## A test's own settings file is the one written (never poser.cfg). A missing file stays listed, marked (missing), until
## RECENT_N newer scenes push it out
func _recent_list() -> Array:
	var cf := ConfigFile.new()
	cf.load(settings)
	var out := []
	for p in cf.get_value("recent", "scenes", []):
		out.append(String(p))
	return out


func _recent_note(path: String) -> void:
	if path == "":
		return
	var l := _recent_list()
	l.erase(path)
	l.push_front(path)
	var cf := ConfigFile.new()
	cf.load(settings)
	cf.set_value("recent", "scenes", l.slice(0, RECENT_N))
	cf.save(settings)
	_recent_changed()


## the scene list and the palette's File > Recent group show the new order at once
func _recent_changed() -> void:
	if ui_scenes != null:
		_fill_scene_list()
		_show_open_scene()
	if ui_cmd != null:
		ui_cmd.commands = _commands()


## File > Recent: a scene from the list, opened as the list's pick would open it
func _open_recent(path: String) -> void:
	if not FileAccess.file_exists(path):
		_say("%s is not on disk any more (moved or deleted): open another scene; it leaves File > Recent when %d newer ones are opened" % [path.get_file(), RECENT_N])
		return
	_open_scene_file(path)


## THE JOURNAL (ROADMAP 2, CRASH-PROOF; scripts/journal.gd): the scene after every edit, so a crash loses no edit that
## was made. Written by _do, by the next undo step, and by the frame that ends a drag or an undo (_process)
func _journal_write() -> void:
	_jpending = false
	if not journal_on:
		return
	if journal.path != scene_path or journal.dir != journal_dir:
		journal.open(journal_dir, scene_path)
	var t0 := Time.get_ticks_usec()
	var st := _scene_dict(false)
	journal_capture_us += Time.get_ticks_usec() - t0
	journal.append(st)


## a save: the work is on disk now, so the journal of the scene (and of the file it became) is dropped
func _journal_saved() -> void:
	if not journal_on:
		return
	journal.trim()
	journal.open(journal_dir, scene_path)
	journal.trim()


## start: a session that did not quit cleanly leaves its journals behind. The newest journal newer than its scene's
## file is offered (journal_offer); every journal is moved aside to .old, so this session starts its own
func _journal_boot() -> void:
	journal.dir = journal_dir
	var was_clean := journal.session_clean()
	journal.set_session(false)
	if was_clean:
		return
	var best := {}
	for f in DirAccess.get_files_at(journal_dir):
		if not f.ends_with(".jsonl"):
			continue
		var fp := journal_dir.path_join(f)
		var r := Journal.restore(fp)
		if not r.is_empty():
			var saved := -1
			if r["path"] != "" and FileAccess.file_exists(r["path"]):
				saved = int(FileAccess.get_modified_time(r["path"]))
			if int(r["t"]) > saved and (best.is_empty() or int(r["t"]) > int(best["t"])):
				best = Journal.restore(fp, saved)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(fp), ProjectSettings.globalize_path(fp) + ".old")
	if not best.is_empty():
		journal_offer = best
		_journal_offer_say.call_deferred()


func _journal_offer_say() -> void:
	if journal_offer.is_empty():
		return
	var local := int(journal_offer["t"]) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	_say("Restore the work from %s (%d edits after the last save): File: restore unsaved work" % [
		Time.get_datetime_string_from_unix_time(local, true), int(journal_offer["n"])])


## File: restore unsaved work: the scene as the last journaled edit left it, still unsaved (Save scene keeps it).
## The journal goes on from it, whole, so a second crash is covered too; the moved-aside files are dropped
func _journal_restore() -> void:
	if journal_offer.is_empty():
		_say("no unsaved work to restore: no session was left without a clean quit. Open a scene to start")
		return
	var o := journal_offer
	journal_offer = {}
	_restore_work({"scene": o["state"], "path": o["path"]})
	if journal_on:
		for f in DirAccess.get_files_at(journal_dir):
			if f.ends_with(".old"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(journal_dir.path_join(f)))
		journal.open(journal_dir, scene_path)
		journal.force_full()
		_journal_write()
	_say("restored the work from the journal (%d edits): it is not saved yet, Save scene keeps it" % int(o["n"]))


var ui_recover: ConfirmationDialog
var _recovering := false   # Recover opens the scene's file under the autosave: that open must not drop the autosave


## on start: an autosave that differs from its scene on disk is offered back (Recover / Discard)
var _recover_discard := false


## LATER keeps the offered work in a slot of its own (the autosave's own slot is overwritten by the next autosave, and
## dropped by a quit with nothing unsaved or by opening a scene): <autosave>_later.json, offered when the main slot
## has nothing; one later slot (a newer Later replaces it)
func _later_path() -> String:
	return ProjectSettings.globalize_path(autosave).get_basename() + "_later.json"


func _recover_closed() -> void:
	var from: String = ui_recover.get_meta("from", "")
	if _recover_discard:
		_recover_discard = false
		if from == _later_path():
			DirAccess.remove_absolute(from)
		else:
			_autosave_drop()
		_say("the unsaved work was discarded")
	else:
		if from != _later_path():
			DirAccess.rename_absolute(from, _later_path())
			_as_last = ""
		_say("the unsaved work is kept: it is offered again next time Kine starts")


func _offer_drop(fp: String) -> void:
	if fp == _later_path():
		DirAccess.remove_absolute(fp)
	else:
		_autosave_drop()


func _recover_offer() -> void:
	var fp := ProjectSettings.globalize_path(autosave)
	if not FileAccess.file_exists(fp):
		fp = _later_path()
		if not FileAccess.file_exists(fp):
			return
	var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(fp))
	if not (a is Dictionary) or not (a.get("scene") is Dictionary) or not a["scene"].has("cards"):
		_offer_drop(fp)   # unreadable: nothing to give back
		return
	var path: String = a.get("path", "")
	if path != "" and FileAccess.file_exists(path):
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if disk is Dictionary and JSON.stringify(disk.get("cards")) == JSON.stringify(a["scene"]["cards"]):
			_offer_drop(fp)   # the same as the file: nothing was lost
			return
	if ui_recover == null:
		ui_recover = ConfirmationDialog.new()
		ui_recover.name = "recover_dialog"
		ui_recover.title = "Unsaved work found"
		ui_recover.ok_button_text = "Recover it"
		ui_recover.cancel_button_text = "Discard"
		ui_recover.get_cancel_button().name = "b_discard"
		ui_recover.get_ok_button().name = "b_recover"
		add_child(ui_recover)
		ui_recover.confirmed.connect(_recover)
		# ONLY THE DISCARD BUTTON DISCARDS (round 35a, GATES QQ3): Esc and the window's (x) also cancel; closing an
		# intro must never throw work away, so they mean LATER: the autosave stays and the next start offers it again
		ui_recover.get_cancel_button().pressed.connect(func(): _recover_discard = true)
		ui_recover.canceled.connect(func(): _recover_closed.call_deferred())   # after the button's own pressed
	var nm: String = a["scene"].get("name", "")
	if nm == "" and path != "":
		nm = path.get_file().get_basename()
	ui_recover.dialog_text = "Kine closed with unsaved work:
'%s', %d cards, autosaved %s.
Recover it?" % [
		nm if nm != "" else "a new scene", a["scene"]["cards"].size(), String(a.get("at", "")).replace("T", " ")]
	ui_recover.set_meta("autosave", a)
	ui_recover.set_meta("from", fp)
	ui_recover.popup_centered()


## Recover: the autosaved scene comes back, still marked unsaved (its file on disk is what _clean holds)
func _recover() -> void:
	var a: Dictionary = ui_recover.get_meta("autosave")
	if ui_recover.get_meta("from", "") == _later_path():
		DirAccess.remove_absolute(_later_path())   # it is open again; the autosave holds it from here
	_restore_work(a)


## the unsaved work a dict holds ({"scene", "path"}) comes back, still unsaved (Recover, and File: restore unsaved work)
func _restore_work(a: Dictionary) -> void:
	var path: String = a.get("path", "")
	_clean = "[]"
	_actors_home()   # TC3
	if path != "" and FileAccess.file_exists(path):
		_recovering = true
		_load_scene(path)   # sets _clean to the disk version
		_recovering = false
	S = Scene.new()
	S.from_dict(a["scene"])
	scene_path = path
	if ui_loop != null:
		ui_natural.set_pressed_no_signal(S.natural)
		ui_spline.set_pressed_no_signal(S.spline)
		ui_loop.set_pressed_no_signal(S.loop)
	if ui_scene_name != null:
		ui_scene_name.text = S.name
	_show_open_scene()
	ov.mark_dirty()
	wt.mark_dirty()
	_dummy_hits()
	sel_card = -1
	playhead = 0.0
	S.apply(B, 0.0)
	_rebuild_cards()
	_refresh()
	_say("recovered '%s' (%d cards): it is not saved yet, Save scene keeps it" % [S.name, S.cards.size()])


## ---------------------------------------------------------------- THE SET (round 37, GATES SS5 / SS6)
## The scene's props as nodes under ui_props_root (rebuilt whole: a set is a handful of boxes); the picked one tinted
var _gone_said := {}   # prop kinds whose missing model file was already said


func _props_show() -> void:
	Props.settle(S.props)   # UU1: whatever changed, every prop rests on what is under it
	B.props = S.solid_props()   # TT2: the live body stands on the set too (never on what it carries)
	if ui_props_root == null:
		return
	for c in ui_props_root.get_children():
		ui_props_root.remove_child(c)
		c.queue_free()
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color(Tok.c("accent"), 0.35)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in S.props.size():
		var n := Props.mesh(S.props[i])
		if Props.model_missing(S.props[i]) and not _gone_said.has(S.props[i]["kind"]):
			_gone_said[S.props[i]["kind"]] = true
			_say_plain("the model file of the %s is missing: it is drawn as a box. Open the importer and add the model again, or delete the prop" % S.props[i]["kind"])
		n.name = "prop_%d" % i
		if i == sel_prop:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_overlay = tint
		ui_props_root.add_child(n)
	for k in ui_prop_btns:
		_grey(ui_prop_btns[k], "" if sel_prop >= 0 else "pick a prop first: click it in the view, or add one with Add prop")
	var kind := String(S.props[sel_prop]["kind"]) if sel_prop >= 0 and sel_prop < S.props.size() else ""
	if ui_use_btns.has("Sit here"):
		_grey(ui_use_btns["Sit here"], "" if kind in SIT_ON else "pick a chair, a stool or a bench first (Add prop puts one in the set)")
		_grey(ui_use_btns["Step up"], "" if kind in STEP_ON else "pick a box, a crate, a step or the stairs first (Add prop puts one in the set)")
		_grey(ui_use_btns["Pick up"], "" if kind != "" and sel_card >= 0 else ("pick a card first: the body on it holds the prop" if kind != "" else "pick a prop first: click it in the view, or add one with Add prop"))
		_grey(ui_use_btns["Put down"], "" if not _held_at(sel_card).is_empty() else "pick a card where a prop is held (after its Pick up card): the hands let it go there")
	_props_pose()
	if ui_browser != null:
		ui_browser.refresh()


## the prop under the mouse: [index, distance along the ray] ([-1, INF] none); a ray against each solid box
func _pick_prop(mp: Vector2) -> Array:
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var best := -1
	var bt := INF
	for i in S.props.size():
		for sw in Props.solids(S.props[i]):
			var inv: Transform3D = (sw["xf"] as Transform3D).affine_inverse()
			var lo := inv * o
			var ld := inv.basis * d
			var h: Vector3 = sw["half"]
			var t0 := -INF
			var t1 := INF
			var hit := true
			for k in 3:
				if absf(ld[k]) < 1e-9:
					if absf(lo[k]) > h[k]:
						hit = false
						break
				else:
					var a := (-h[k] - lo[k]) / ld[k]
					var b := (h[k] - lo[k]) / ld[k]
					t0 = maxf(t0, minf(a, b))
					t1 = minf(t1, maxf(a, b))
			if hit and t1 >= maxf(t0, 0.0) and maxf(t0, 0.0) < bt:
				bt = maxf(t0, 0.0)
				best = i
	return [best, bt]


func _prop_name(i: int) -> String:
	return String(S.props[i]["kind"]).replace("_", " ") if i >= 0 and i < S.props.size() else ""


## a press on a prop: picked, and a drag moves it over the floor (snapped onto what it stands over); one undo step
func _prop_press(i: int, mp: Vector2, t: float) -> void:
	_step_hint = "Move prop"
	_push_undo()
	sel_prop = i
	playing = false
	_prop_live(i)
	var hp := cam.project_ray_origin(mp) + cam.project_ray_normal(mp) * t
	var o: Vector3 = (S.props[i]["xf"] as Transform3D).origin
	_prop_drag = {"i": i, "plane": hp.y, "off": Vector3(o.x - hp.x, 0.0, o.z - hp.z), "moved": false, "from": o,
		"turn": Input.is_key_pressed(KEY_SHIFT), "yaw0": Props.yaw_of(S.props[i]["xf"]), "a0": atan2(hp.x - o.x, hp.z - o.z)}
	dragging = "prop"
	_end_teach()
	_props_show()
	_say_plain("the %s: drag to move it (it steps onto what it stands over); Turn left / right and Delete are in SET" % _prop_name(i))


func _prop_move(mp: Vector2) -> void:
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 1e-4 or _prop_drag.is_empty():
		return
	var t := (float(_prop_drag["plane"]) - o.y) / d.y
	if t <= 0.0:
		return
	var i: int = _prop_drag["i"]
	if _prop_drag["turn"]:   # row 22: Shift+drag turns the prop about its middle, following the mouse round it
		_prop_turn_drag(o + d * t)
		return
	var hp := o + d * t + (_prop_drag["off"] as Vector3)
	var p: Dictionary = S.props[i]
	var xf: Transform3D = p["xf"]
	xf.origin = Vector3(hp.x, 0.0, hp.z)
	p["xf"] = xf
	var others := []
	for k in S.props.size():
		if k != i:
			others.append(S.props[k])
	xf.origin.y = Props.snap_y(p, others)
	p["xf"] = xf
	_prop_drag["moved"] = xf.origin.distance_to(_prop_drag["from"]) > 0.001   # a still mouse is a click, not a move
	var n := ui_props_root.get_node_or_null("prop_%d" % i)
	if n != null:
		(n as Node3D).transform = xf


func _prop_release() -> void:
	if _prop_drag.is_empty():
		return
	if not _prop_drag["moved"]:
		undo.pop_back()   # a click that only picked: no step
		_history_rows()
	else:
		_prop_autokey(_prop_drag["i"])   # row 22: a keyed prop moved = a key at the playhead
		_props_show()   # UU1: what stood on it settles
		var y: float = (S.props[_prop_drag["i"]]["xf"] as Transform3D).origin.y
		_say("moved the %s%s" % [_prop_name(_prop_drag["i"]), "" if y < 0.001 else ": it stands on what is under it, %.0f cm up" % (y * 100.0)])
		_doc_line()
	_prop_drag = {}


func _prop_menu_fill(ap: MenuButton) -> void:
	var pm := ap.get_popup()
	pm.clear()
	var cat := Props.catalogue()
	for k in cat.size():
		pm.add_item("%s   (%s)" % [String(cat[k][0]).replace("_", " "), cat[k][1]], k)
		pm.set_item_metadata(k, cat[k][0])


func _prop_menu_pick(id: int, ap: MenuButton) -> void:
	var pm := ap.get_popup()
	_step_hint = "Add prop"
	_tour_inputs += 1
	_prop_add(String(pm.get_item_metadata(pm.get_item_index(id))))


## where a new prop goes: in front of the body, beside it first (the dummy stands straight ahead), the first spot
## whose footprint keeps 10 cm clear of the dummy and of every other prop; none clear: the last spot tried
func _prop_spot(kind: String) -> Vector3:
	var o := Vector3(B.offset.x, 0.0, B.offset.z)
	var spot := o
	for dz in [1.0, 1.8, 2.6]:
		for dx in [-1.0, 1.0, -1.9, 1.9, 0.0]:
			spot = o + Vector3(dx, 0.0, dz)
			var r := _foot(Props.make(kind, Props.xf_at(spot, 0.0))).grow(0.1)
			var clear := not (dummy_on and r.grow(0.3).has_point(Vector2(T.xf.origin.x, T.xf.origin.z)))   # 0.3: the dummy's body
			for q in S.props:
				clear = clear and not r.intersects(_foot(q))
			if clear:
				return spot
	return spot


## a prop's footprint on the floor (x, z), from its solid boxes' corners
func _foot(p: Dictionary) -> Rect2:
	var r := Rect2()
	var first := true
	for sw in Props.solids(p):
		var xf: Transform3D = sw["xf"]
		var h: Vector3 = sw["half"]
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c := xf * Vector3(h.x * sx, 0.0, h.z * sz)
				if first:
					r = Rect2(Vector2(c.x, c.z), Vector2.ZERO)
					first = false
				else:
					r = r.expand(Vector2(c.x, c.z))
	return r


## a prop of the set in front of the body, on the floor (or on what it lands over); picked; one undo step
func _prop_add(kind: String) -> void:
	if not Props.has_kind(kind):
		return
	_push_undo()
	var p := Props.make(kind, Props.xf_at(_prop_spot(kind), 0.0))
	var xf: Transform3D = p["xf"]
	xf.origin.y = Props.snap_y(p, S.props)
	p["xf"] = xf
	S.props.append(p)
	sel_prop = S.props.size() - 1
	_props_show()
	_doc_line()
	_say("added a %s in front of the body: drag it to move it; Turn and Delete are in SET; Ctrl+Z takes it back" % _prop_name(sel_prop))


func _prop_turn(deg: float) -> void:
	if sel_prop < 0 or sel_prop >= S.props.size():
		return
	_push_undo()
	_prop_live(sel_prop)
	var d := Props.to_dict(S.props[sel_prop])
	d["yaw"] = wrapf(float(d["yaw"]) + deg, -180.0, 180.0)
	S.props[sel_prop] = Props.from_dict(d)
	_prop_autokey(sel_prop)
	_props_show()
	_doc_line()
	_say("turned the %s to %.0f°" % [_prop_name(sel_prop), float(d["yaw"])])


func _prop_del() -> void:
	if sel_prop < 0 or sel_prop >= S.props.size():
		return
	_push_undo()
	var nm := _prop_name(sel_prop)
	S.props.remove_at(sel_prop)
	for c in S.cards:   # UU2: the cards' take / drop marks follow the props' new numbers
		if c.has("take"):
			if int(c["take"]["prop"]) == sel_prop:
				c.erase("take")
			elif int(c["take"]["prop"]) > sel_prop:
				c["take"]["prop"] = int(c["take"]["prop"]) - 1
		if c.has("drop"):
			if int(c["drop"]) == sel_prop:
				c.erase("drop")
			elif int(c["drop"]) > sel_prop:
				c["drop"] = int(c["drop"]) - 1
	sel_prop = -1
	_props_show()
	_doc_line()
	_say("deleted the %s: Ctrl+Z puts it back" % nm)


## SIT HERE (TT3, #205): a new card after the picked one: the body faces away from the seat's back (the prop's +Z),
## its hips just behind the seat's middle, thighs level and shins down; grounding on the set lifts the thighs onto the
## seat; a foot left hanging is planted on the floor. One undo step; a pose that still goes into the seat is said
func _prop_sit() -> void:
	if sel_prop < 0 or not String(S.props[sel_prop]["kind"]) in SIT_ON:
		return
	_push_undo()
	var p: Dictionary = S.props[sel_prop]
	var xf: Transform3D = p["xf"]
	var fwd: Vector3 = (xf.basis * Vector3(0, 0, 1)).normalized()
	var sup: Dictionary = Props.supports(p)[0]
	var seat: Vector3 = (sup["xf"] as Transform3D) * Vector3((sup["c"] as Vector2).x, 0.0, (sup["c"] as Vector2).y)
	var at := seat - fwd * 0.05
	var a: Dictionary = B.state()
	B.set_ang("pelvis", Vector3(0, 0, rad_to_deg(atan2(fwd.x, fwd.z))))
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(90, 0, 0))
		B.set_ang("calf" + sd, Vector3(90, 0, 0))
	B.offset = Vector3(at.x - (B.p0["pelvis"] as Vector3).x, B.offset.y, at.z - (B.p0["pelvis"] as Vector3).z)
	B.fk()
	B.props = S.props
	B.ground()
	for sd in ["_l", "_r"]:   # a foot hanging (a high stool): onto the floor
		var fs := B.foot_state(sd)
		if not fs[2]:
			var ball: Vector3 = fs[0]
			B.plant(sd, Vector3(ball.x, (B.p0["ball" + sd] as Vector3).y, ball.z), fs[1], true)
	_use_card("sit on the %s" % _prop_name(sel_prop), a)


## STEP UP (TT3, #205): a new card: the foot nearer the picked box / step / stairs stands on its lowest top, 12 cm in
## from the edge nearest the body; the other stays. A top out of the leg's reach is refused in words, nothing changed
func _prop_step() -> void:
	if sel_prop < 0 or not String(S.props[sel_prop]["kind"]) in STEP_ON:
		return
	var p: Dictionary = S.props[sel_prop]
	var hips: Vector3 = B.P["pelvis"]
	var best := {}
	for s in Props.supports(p):   # the lowest top (the stairs: the first step)
		if best.is_empty() or float(s["y"]) < float(best["y"]):
			best = s
	var sx: Transform3D = best["xf"]
	var c: Vector2 = best["c"]
	var h: Vector2 = best["half"]
	var lh := sx.affine_inverse() * hips
	var inset := Vector2(minf(0.12, h.x), minf(0.12, h.y))
	var lp := Vector2(clampf(lh.x, c.x - h.x + inset.x, c.x + h.x - inset.x), clampf(lh.z, c.y - h.y + inset.y, c.y + h.y - inset.y))
	var top: float = best["y"]
	var sd := "_l" if (B.P["ball_l"] as Vector3).distance_to(sx * Vector3(lp.x, top, lp.y)) < (B.P["ball_r"] as Vector3).distance_to(sx * Vector3(lp.x, top, lp.y)) else "_r"
	var target := sx * Vector3(lp.x, 0.0, lp.y)
	target.y = top + (B.p0["ball" + sd] as Vector3).y
	_push_undo()
	var a: Dictionary = B.state()
	var miss := B.plant(sd, target, B.foot_state(sd)[1], true)
	if miss > 0.02:
		B.set_state(a)
		undo.pop_back()
		_history_rows()
		_refresh()
		_say("the %s's top is out of the foot's reach (it misses by %.0f cm): move it closer to the feet, then Step up again" % [_prop_name(sel_prop), miss * 100.0])
		return
	_use_card("step up on the %s" % _prop_name(sel_prop), a)


## PICK UP (UU2, #206): on the selected card, the hand(s) within REACH of the picked prop hold it from that card's
## arrival on (a box or a crate in both hands when both are near). Out of reach: said with the distance, nothing
## changed. One undo step. The grip is where the prop is in the hand(s) on this card: nothing else is stored
func _prop_take() -> void:
	if sel_prop < 0 or sel_prop >= S.props.size() or sel_card < 0:
		return
	var p: Dictionary = S.props[sel_prop]
	_ps().apply(B, S.times()[sel_card][1])
	var gap := {}
	for sd in ["_l", "_r"]:
		var c := B.cap("hand" + sd)
		var best := INF
		for pt in Props._samples(c[0], c[1]):
			for sw in Props.solids(p):
				best = minf(best, Props._sd(sw, pt))
		gap[sd] = best - float(B.rad["hand" + sd])
	var near: Array = ["_l", "_r"].filter(func(sd): return float(gap[sd]) <= REACH)
	if near.is_empty():
		_say("the hands are %.0f cm from the %s on card %d (a hand must be within %.0f cm): pose a hand next to it on this card, then Pick up" % [
			minf(gap["_l"], gap["_r"]) * 100.0, _prop_name(sel_prop), sel_card + 1, REACH * 100.0])
		return
	if near.size() == 2 and not String(p["kind"]) in TWO_HANDS:
		near = ["_l"] if float(gap["_l"]) < float(gap["_r"]) else ["_r"]
	_push_undo()
	S.cards[sel_card]["take"] = {"prop": sel_prop, "hands": near}
	_rebuild_cards()
	_props_show()
	_refresh()
	_doc_line()
	_say("card %d: %s the %s from here on; Put down on a later card lets it go. Ctrl+Z takes it back" % [sel_card + 1,
		"both hands hold" if near.size() == 2 else ("the left hand holds" if near[0] == "_l" else "the right hand holds"), _prop_name(sel_prop)])


## the carry going on at card k's arrival (taken on an earlier card, not yet let go): {} = none
func _held_at(k: int) -> Dictionary:
	if k < 0:
		return {}
	for c in S.carries():
		if int(c["a"]) < k and (int(c["b"]) < 0 or int(c["b"]) >= k):
			return c
	return {}


## PUT DOWN (UU3): the hands let the held prop go at the selected card; it falls onto what is under it
func _prop_put() -> void:
	var c := _held_at(sel_card)
	if c.is_empty():
		return
	_push_undo()
	var pi: int = c["prop"]
	for k in range(int(c["a"]) + 1, S.cards.size()):   # one drop per carry: an earlier or later one moves here
		if int(S.cards[k].get("drop", -1)) == pi:
			S.cards[k].erase("drop")
	S.cards[sel_card]["drop"] = pi
	_rebuild_cards()
	_props_show()
	_refresh()
	_doc_line()
	var d: Dictionary = {}
	var cs := S.carries()
	for k in cs.size():
		if int(cs[k]["a"]) == int(c["a"]):
			d = S._carry_data(B)[k]
	var h := float(d.get("drop", Transform3D()).origin.y) - float(d.get("land", 0.0)) if d.has("drop") else 0.0
	_say("card %d: the hands let the %s go; it falls %.0f cm in %s onto %s. Ctrl+Z takes it back" % [sel_card + 1, _prop_name(pi),
		h * 100.0, Units.time(float(d.get("tf", 0.0)), S.fps), "the floor" if float(d.get("land", 0.0)) < 0.001 else "what is under it"])


## the set as it is at the playhead: carried props in the hands, dropped ones falling (every frame while any card
## carries; the stored props are their homes)
func _props_pose() -> void:
	if ui_props_root == null or (S.carries().is_empty() and not Props.any_animated(S.props)):
		return
	var pa := _ps().props_at(playhead, B) if _ps() == S else S.props_at(playhead, B)
	for i in pa.size():
		var n := ui_props_root.get_node_or_null("prop_%d" % i)
		if n != null and i != int(_prop_drag.get("i", -1)):   # the one being dragged shows where the mouse has it
			Props.pose_node(n as Node3D, pa[i])


## ---- GENERIC PROPS (GAP_ANALYSIS row 22): keys over time, the door's hinge, Shift+drag turns, a prop as a target
const DOOR_MAX := 110.0   # deg either way: an interior door's leaf stops at the wall / its stop well before 180


## a keyed prop's stored place set to where its keys have it at the playhead (so a drag or a turn starts from what is shown)
func _prop_live(i: int) -> void:
	if i < 0 or i >= S.props.size() or not Props.animated(S.props[i]):
		return
	var q := Props.posed(S.props[i], playhead)
	S.props[i]["xf"] = q["xf"]
	if q.has("swing"):
		S.props[i]["swing"] = q["swing"]


## after a move or a turn: a keyed prop gets a key at the playhead (Blender's auto-key on a keyed object)
func _prop_autokey(i: int) -> void:
	if i >= 0 and i < S.props.size() and Props.animated(S.props[i]):
		Props.key_at(S.props[i], playhead, S.props[i]["xf"], float(S.props[i].get("swing", 0.0)))


func _prop_turn_drag(hp: Vector3) -> void:
	var i: int = _prop_drag["i"]
	var xf: Transform3D = S.props[i]["xf"]
	var a := atan2(hp.x - xf.origin.x, hp.z - xf.origin.z)
	var yaw := float(_prop_drag["yaw0"]) + rad_to_deg(angle_difference(float(_prop_drag["a0"]), a))
	yaw = snappedf(yaw, 5.0) if Input.is_key_pressed(KEY_CTRL) else yaw
	S.props[i]["xf"] = Props.xf_at(xf.origin, yaw)
	_prop_drag["moved"] = absf(angle_difference(deg_to_rad(float(_prop_drag["yaw0"])), deg_to_rad(yaw))) > 0.001
	var n := ui_props_root.get_node_or_null("prop_%d" % i)
	if n != null:
		Props.pose_node(n as Node3D, S.props[i])


func _prop_key() -> void:
	if sel_prop < 0 or sel_prop >= S.props.size():
		_say("pick a prop first: click it in the view (or Add prop), then Prop: key its place here")
		return
	var i := sel_prop
	_do(func():
		_prop_live(i)
		Props.key_at(S.props[i], playhead, S.props[i]["xf"], float(S.props[i].get("swing", 0.0))))
	_props_show()
	_doc_line()
	_say("keyed the %s at %s (%d keys): move the playhead, drag or turn it, and it is keyed there too; Ctrl+Z takes it back" % [
		_prop_name(sel_prop), Units.time(playhead, S.fps), (S.props[sel_prop]["keys"] as Array).size()])


## GRIP ANY PROP (ROADMAP 18; scripts/any_grip.gd): the picked hand's fingers close round the picked prop at the playhead
## (its surface, any shape), the thumb opposing; the finger and thumb poses are keyed there. One undo step
func _grip_prop_cmd() -> void:
	if sel_prop < 0 or sel_prop >= S.props.size():
		_say("pick a prop first: click it in the view, then Grip: wrap the hand round the picked prop")
		return
	var h := "hand_l" if sel.ends_with("_l") else "hand_r"
	var t := clampf(playhead, 0.0, S.length())
	var F := AnyGrip.field_of(Props.posed(S.props[sel_prop], t))
	var name := _prop_name(sel_prop)
	var rep := {}
	_do(func(): rep.merge(AnyGrip.grip_prop(B, h, F, S.part_keys, t)))
	var touch := 0
	for f in GripWrap.LONG:
		if float((rep[f] as Array)[2][1]) <= 0.003:
			touch += 1
	_props_show()
	_say("%s hand wrapped round the %s (%s shape): %d of 4 fingertips on it, the rest at their limits or short; keyed at %s; Ctrl+Z takes it back" % [
		"left" if h == "hand_l" else "right", name, rep["pattern"], touch, Units.time(t, S.fps)])


func _prop_unkey() -> void:
	if sel_prop < 0 or sel_prop >= S.props.size() or not Props.animated(S.props[sel_prop]):
		_say("pick a prop that has keys first (Prop: key its place here makes one), then delete its keys")
		return
	var i := sel_prop
	_do(func():
		_prop_live(i)
		S.props[i].erase("keys"))
	_props_show()
	_doc_line()
	_say("the %s's keys are gone: it stays where it was at %s. Ctrl+Z puts them back" % [_prop_name(i), Units.time(playhead, S.fps)])


## the picked door's leaf turned by deg about its hinge, keyed at the playhead (a door with no keys gets a key at 0 s
## first, shut as it stands, so the swing PLAYS from it)
func _door_swing(deg: float) -> void:
	if sel_prop < 0 or sel_prop >= S.props.size() or not Props.hinged(S.props[sel_prop]):
		_say("pick a door first: Add prop puts one in the set, click it in the view, then Door: open 15 deg")
		return
	var i := sel_prop
	_do(func():
		_prop_live(i)
		var p: Dictionary = S.props[i]
		if not Props.animated(p) and playhead > Props.SAME_T:
			Props.key_at(p, 0.0, p["xf"], float(p.get("swing", 0.0)))
		p["swing"] = clampf(float(p.get("swing", 0.0)) + deg, -DOOR_MAX, DOOR_MAX)
		Props.key_at(p, playhead, p["xf"], float(p["swing"])))
	_props_show()
	_doc_line()
	_say("the door is %.0f° open at %s (keyed): move the playhead and open or close it again to key the swing; Ctrl+Z takes it back" % [
		float(S.props[i]["swing"]), Units.time(playhead, S.fps)])


func _cons_target_prop() -> void:
	if sel_prop < 0 or sel_prop >= S.props.size():
		_say("pick a prop first: click it in the view (or Add prop), then Constraint: target the picked prop")
		return
	cons_target = {"kind": "prop", "prop": sel_prop}
	_say("constraint target: the %s (now pick the hand that follows it, then Constraint: child of the target)" % _prop_name(sel_prop))


## the posed body becomes a card after the selected one; what goes into a prop on it is said (TT1's own reading)
func _use_card(nm: String, before: Dictionary) -> void:
	var at := sel_card + 1 if sel_card >= 0 else -1
	S.add(nm, B.to_dict(), at)
	sel_card = at if at >= 0 else S.cards.size() - 1
	playhead = S.times()[sel_card][1]
	_rebuild_cards()
	_refresh()
	var hits := Rulebook.prop_hits(S.props, B)
	if hits.is_empty():
		_say("added card %d: %s. Ctrl+Z takes it back" % [sel_card + 1, nm])
	else:
		_say("added card %d: %s, but the %s is %.1f cm into the %s: move it out (Check lists it)" % [sel_card + 1, nm,
			Rulebook.part_words(hits[0][0]), float(hits[0][2]) * 100.0, String(S.props[hits[0][1]]["kind"])])


## a row in the browser's Set: pick prop i (no undo step)
func _prop_select(i: int) -> void:
	if i < 0 or i >= S.props.size():
		return
	sel_prop = i
	_props_show()
	_say_plain("the %s: drag it in the view to move it; Turn and Delete are in SET" % _prop_name(i))


## ---- IMPORT (SS6): a dropped file, or Import model's picker, goes through the importer (scripts/importer.gd)
func _library_load() -> void:
	for e in Importer.library_list(library)["props"]:
		var r: Dictionary = Importer.inspect(e["path"])
		if r["ok"]:
			Props.register("my " + String(e["name"]), r["aabb"], e["path"], r["scale_factor"])


func _on_drop(files: PackedStringArray) -> void:
	for f in files:
		if f.to_lower().ends_with(".bvh") and AnimImport.is_kine_bvh(f):
			_import_bvh(f)
		elif f.to_lower().ends_with(".bvh"):
			_import_anim(f)
		elif f.get_extension().to_lower() == "fbx":
			_import_anim(f)
		elif VIDEO_EXT.has(f.get_extension().to_lower()):
			_import_video(f)
		elif f.to_lower().ends_with(".json") and VideoImport.load_file(f)["ok"]:
			_import_pose(f)
		else:
			_import_file(f)


## ---- AUDIO TRACK (GAP_ANALYSIS row 23). The scene keeps S.audio = {"path", "offset", "gain_db"}; the stream and its peak
## envelope (AudioTrack, computed once per file) live here, not in the file. Play: the AudioStreamPlayer plays from
## (playhead - offset), re-seeked when the playhead jumps; a drag of the ruler plays one short slice per frame.
const AUDIO_SLICE_EXTRA := 0.04   # s added to one frame for a scrub slice
var audio_env := {}             # AudioTrack.envelope of the loaded sound; {} = none
var audio_seeks := 0            # how many times Play (re)started the sound (tests)
var audio_err := 0.0            # sound position - wanted position (s), read right after the playhead moved this frame (tests)
var audio_slices := 0           # how many scrub slices were sounded (tests)
var _a_player: AudioStreamPlayer
var mouth_mi: MeshInstance3D   # LIP-SYNC (ROADMAP 31): the mouth drawn on the head, from S.lip (lip_sync.gd); made on first use
var _a_path := "<unset>"        # the path the stream was loaded for (a change reloads it: open, undo, remove)
var _a_on := false              # the player is running for Play
var _a_after := -1.0            # the playhead at the end of the last tick (a different one now = the user moved it)
var _a_slice_until := 0         # msec when the scrub slice stops
var _a_slice_frame := -1


func audio_stream() -> AudioStream:
	return _a_player.stream if _a_player != null else null


## where the sound is, in its own seconds; -1 when it is not sounding. The engine mixes in chunks, so its position is up to
## a chunk old: the class reference says to add the time since the last mix (the output latency is not taken off)
func audio_position() -> float:
	if _a_player == null or not _a_player.playing:
		return -1.0
	return _a_player.get_playback_position() + AudioServer.get_time_since_last_mix()


func _audio_reload() -> void:
	_a_path = String(S.audio.get("path", ""))
	_a_on = false
	_a_slice_until = 0
	if _a_player == null:
		_a_player = AudioStreamPlayer.new()
		_a_player.name = "audio_track"
		add_child(_a_player)
	_a_player.stop()
	_a_player.stream = AudioTrack.load_stream(_a_path)
	audio_env = {} if _a_path == "" else AudioTrack.envelope(_a_player.stream, _a_path)
	if ui_timeline != null:
		_tl_height()
		ui_timeline.queue_redraw()


func _audio_ask() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; sounds"])
	fd.use_native_dialog = true
	fd.title = "A sound for the timeline"
	fd.file_selected.connect(func(p): _audio_set(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## put a sound on the timeline (one undo step). Returns true when it loaded
func _audio_set(path: String) -> bool:
	if not AudioTrack.EXTS.has(path.get_extension().to_lower()):
		_say("could not add %s: it is not a wav, ogg or mp3; pick one of those" % path.get_file())
		return false
	var st := AudioTrack.load_stream(path)
	if st == null:
		_say("could not add %s: the file is missing or Godot cannot read it; pick another wav, ogg or mp3" % path.get_file())
		return false
	_push_undo()
	S.audio = {"path": path, "offset": 0.0, "gain_db": 0.0}
	_audio_reload()
	var env := audio_env
	_say("sound added: %s, %s from 0.00 s%s" % [path.get_file(), Units.time(st.get_length(), S.fps), "" if env.get("ok", false) else " (ogg / mp3 / compressed wav have no waveform here: a flat bar with the name stands in; it still plays)"])
	_refresh()
	return true


## ---- LIP-SYNC (ROADMAP 31; scripts/lip_sync.gd). The channel S.lip is baked from the sound on the timeline; the mouth
## is a dark shape on the head: its width from the mouth shape, its opening from the jaw channel.
func _lip_from_audio() -> void:
	if S.audio.is_empty():
		_say("no sound on the timeline: run Audio: add a sound file first (a wav)")
		return
	var r := LipSync.read_wav(String(S.audio.get("path", "")))
	if not r["ok"]:
		_say("lip-sync: %s (try another sound)" % r["why"])
		return
	var off := float(S.audio.get("offset", 0.0))
	var A := LipSync.analyse(LipSync.windows(r["mono"], int(r["rate"])))
	var lip := LipSync.bake(A, S.fps, off, maxf(S.length(), off + float(r["length"])))
	_push_undo()
	S.lip = lip
	var opened := 0
	for sh in (A["shape"] as PackedStringArray):
		if sh != "M":
			opened += 1
	_say("lip-sync baked: %d mouth changes, %d of %d windows voiced, jaw 0-%d° (Ctrl+Z removes it)" % [lip["mouth"].size(), opened, (A["shape"] as PackedStringArray).size(), int(LipSync.JAW_MAX)])
	_refresh()


## THE FACE on the head (ROADMAP 74; scripts/face.gd): the brows (L/R), the eyes (look + blink), and the mouth (the jaw and
## the viseme shape). Drawn at the playhead from the face keys and the lip-sync channel (the lip sync drives the jaw and the
## visemes when it is there). While the Face panel is open its sliders are the preview. Nothing shows with neither.
var face_root: Node3D           # the brows and eyes (made on first use)
var face_brow: Array = []       # [brow_l, brow_r] MeshInstance3D (BoxMesh)
var face_eye: Array = []        # [eye_l, eye_r] (sclera, SphereMesh)
var face_pupil: Array = []      # [pupil_l, pupil_r]
var face_ui: FaceUI


func _face_make() -> void:
	face_root = Node3D.new()
	face_root.name = "face_parts"
	add_child(face_root)
	for i in 2:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1, 1)
		b.mesh = bm
		b.material_override = StandardMaterial3D.new()
		b.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face_root.add_child(b)
		face_brow.append(b)
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		e.mesh = sm
		e.material_override = StandardMaterial3D.new()
		e.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face_root.add_child(e)
		face_eye.append(e)
		var p := MeshInstance3D.new()
		p.mesh = sm
		p.material_override = StandardMaterial3D.new()
		p.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face_root.add_child(p)
		face_pupil.append(p)


func _face_draw() -> void:
	var live := face_ui != null and face_ui.live()
	var on := live or not S.lip.is_empty() or not S.face.is_empty()
	if not on:
		if mouth_mi != null:
			mouth_mi.visible = false
		if face_root != null:
			face_root.visible = false
		return
	if mouth_mi == null:
		mouth_mi = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		mouth_mi.mesh = sm
		mouth_mi.material_override = StandardMaterial3D.new()
		mouth_mi.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		add_child(mouth_mi)
	if face_root == null:
		_face_make()
	var P: Dictionary = Face.pose(face_ui.values(), {}, playhead) if live else Face.at(S.face, S.lip, playhead)
	var geo := _face_geo()
	if geo.is_empty():
		return   # no head mesh to anchor on
	var g: Quaternion = B.G["head"]
	var front: Vector3 = g * Vector3(0, 0, 1)
	var up: Vector3 = g * Vector3(0, 1, 0)
	var left: Vector3 = g * Vector3(1, 0, 0)   # +X = the hero's LEFT (data/skeleton.json)
	var ink: Color = Tok.c("ink")
	var pupil_c: Color = Tok.c("accent")
	var white: Color = Tok.c("text")
	var blink := float(P["blink"])
	face_root.visible = true
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0   # side 0 = the left (+X), 1 = the right
		var sfx := "_l" if side == 0 else "_r"
		var v := float(P["brow" + sfx])
		var bpos := face_at(geo["brow" + sfx]) + front * 0.004 + up * (0.012 * v)
		var tilt := -clampf(v, -1.0, 1.0) * 0.3 * sx
		var bb: MeshInstance3D = face_brow[side]
		(bb.material_override as StandardMaterial3D).albedo_color = ink
		bb.transform = Transform3D(Basis(g) * Basis(Vector3(0, 0, 1), tilt) * Basis.from_scale(Face.BROW_SIZE), bpos)
		var epos := face_at(geo["eye" + sfx]) + front * 0.001
		var eb: MeshInstance3D = face_eye[side]
		(eb.material_override as StandardMaterial3D).albedo_color = white
		eb.transform = Transform3D(Basis(g) * Basis.from_scale(Vector3(Face.EYE_SIZE.x, Face.EYE_SIZE.y * (1.0 - 0.9 * blink), Face.EYE_SIZE.z)), epos)
		var look := left * sin(deg_to_rad(float(P["eye_yaw_deg"]))) + up * sin(deg_to_rad(float(P["eye_pitch_deg"])))
		var pb: MeshInstance3D = face_pupil[side]
		(pb.material_override as StandardMaterial3D).albedo_color = pupil_c
		pb.visible = blink < 0.5
		pb.transform = Transform3D(Basis(g) * Basis.from_scale(Vector3(Face.IRIS_D, Face.IRIS_D, Face.IRIS_D * 0.6)), epos + front * 0.003 + look * 0.005)
	var jaw := float(P["jaw_deg"])
	var sz := Face.mouth_size(String(P["mouth"]), jaw)
	(mouth_mi.material_override as StandardMaterial3D).albedo_color = Tok.c("fail")
	mouth_mi.visible = true
	mouth_mi.transform = Transform3D(Basis(g) * Basis.from_scale(Vector3(sz.x * Face.MOUTH_W_K, sz.y, sz.z)), face_at(geo["mouth"]) + front * 0.002 - up * sz.y * 0.25)


var face_geo: Dictionary = {}   # the anchors on the head mesh in rest space (Face.anchors), read once from the head piece


func _face_geo() -> Dictionary:
	if face_geo.is_empty() and pieces.has("head"):
		var mesh: Mesh = (pieces["head"] as MeshInstance3D).mesh
		var pts := PackedVector3Array()
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for i in ix:
				pts.append(vs[i])
		face_geo = Face.anchors(pts)
	return face_geo


## a point on the head given in REST space, carried by the head joint now (the same carry as Body.cap): where it is in the world
func face_at(rest: Vector3) -> Vector3:
	return (B.P["head"] as Vector3) + (B.G["head"] as Quaternion) * (rest - (B.p0["head"] as Vector3))


func _audio_remove() -> void:
	if S.audio.is_empty():
		_say("no sound on the timeline: run Audio: add a sound file first")
		return
	_push_undo()
	S.audio = {}
	_audio_reload()
	_say("sound removed from the timeline (the file is still on disk; add it again to bring it back)")
	_refresh()


## the sound's loudness in steps of 3 dB (about 1.4x the amplitude), -30 .. +12 dB; saved as gain_db, used by playback
## and mixed into the playblast's mp4 (PlayblastExport.args). One undo step
## ROADMAP 10: the human-limits rules in or out of Check (HumanLimits.on), then Check again
func _human_check() -> void:
	HumanLimits.on = not HumanLimits.on
	_check()
	_say(("Check now asks 'could a human do this?' too: joint speed and tipping against recorded limits (experimental)" if HumanLimits.on else "Check is back to the rulebook alone"))


## TWINNING (ROADMAP 19; scripts/twinning.gd): the mirror twins the default Check does not grade. Shown in the Check list.
func _twin_check() -> void:
	if S.cards.size() < 2:
		_say("Check: twinning needs a scene of two cards or more: add a card first")
		return
	var f := Twinning.findings(S, ov.GB)
	_check(f)
	_say("twinning: nothing moves as a mirror twin for 0.3 s or more" if f.is_empty() else "twinning: %d range(s) listed in Check; 'Fix: offset the picked side by 3 frames' offsets the picked side" % f.size())


func _twin_fix() -> void:
	var side := "l" if sel.ends_with("_l") else ("r" if sel.ends_with("_r") else "")
	if side == "":
		_say("pick a left or right arm or leg part first: the side to offset (picked: %s)" % sel)
		return
	var ranges := []
	for f in Twinning.findings(S, ov.GB):
		ranges.append({"kind": f["kind"], "t0": f["t0"], "t1": f["t1"]})
	if ranges.is_empty():
		_say("no twinning to fix: Check: twinning lists none, so pick another check")
		return
	_push_undo()   # one undo step for the whole offset
	var n := Twinning.offset(S, ov.GB, side, ranges)
	_refresh()
	var left := Twinning.findings(S, ov.GB)
	_check(left)
	_say("offset the %s side by %d frames over %d range(s): %d joint(s) moved, %d twin range(s) left (Ctrl+Z undoes it)" % [
		"left" if side == "l" else "right", Twinning.OFFSET, ranges.size(), n, left.size()])


func _audio_gain(step: float) -> void:
	if S.audio.is_empty():
		_say("no sound on the timeline: run Audio: add a sound file first")
		return
	var g := clampf(float(S.audio.get("gain_db", 0.0)) + step, -30.0, 12.0)
	if absf(g - float(S.audio.get("gain_db", 0.0))) < 1e-6:
		_say("the sound is already as %s as it goes (%+.0f dB): try the other way" % ["loud" if step > 0 else "quiet", g])
		return
	_push_undo()
	S.audio["gain_db"] = g
	if _a_player != null:
		_a_player.volume_db = g
	_say("the sound is at %+.0f dB now (0 = as recorded; Ctrl+Z puts it back)" % g)
	_refresh()


## MUSIC BEATS (ROADMAP 32; scripts/beat_track.gd): the beats of the sound, kept in the scene as "beats_audio"
func _beats_find() -> void:
	if S.audio.is_empty() or _a_player == null or _a_player.stream == null:
		_say("no sound on the timeline: run Audio: add a sound file first (beats need a wav)")
		return
	var r := BeatTrack.analyze(_a_player.stream)
	if not r["ok"]:
		_say("beats: %s (try another sound)" % r["msg"])
		return
	_push_undo()
	S.beats_audio = r["beats"]
	var nd := 0
	for b in r["beats"]:
		if b["down"]:
			nd += 1
	_say("beats: %d at %.1f BPM%s.  Beats: snap the contact cards moves hits onto them.  Ctrl+Z undoes" % [r["beats"].size(), float(r["bpm"]), (", %d bars (4/4 grid) marked" % nd) if nd > 0 else ", no 4/4 grid evident (every beat plain)"])
	if ui_timeline != null:
		ui_timeline.queue_redraw()
	_refresh()


## snaps each contact card (the card a hit marker sits on) onto its nearest beat; one undo step. Runs on a clone first:
## when any card would need more than 25 % of its move, nothing changes and the message says why
func _beats_snap() -> void:
	if S.beats_audio.is_empty():
		_say("no beats yet: run Beats: find the beats in the sound first")
		return
	var trial := S.clone()
	var r := BeatTrack.snap(trial, S.beats_audio, float(S.audio.get("offset", 0.0)))
	if not r["ok"]:
		_say(r["msg"] + " (pick other cards, or add a hit marker)")
		return
	var worst := 0.0
	for mv in r["moves"]:
		worst = maxf(worst, absf(float(mv[1])))
	_push_undo()
	_markers_hold()
	S.cards = trial.cards
	_markers_follow()
	_retimed()
	_say("%d contact card(s) snapped onto the beat (largest move %.0f ms).  Ctrl+Z undoes" % [r["contacts"], worst * 1000.0])


## WEIGHT FEEL (ROADMAP 40; scripts/weight_feel.gd): the swing's wind-up and recovery by the held weapon's inertia
func _weight_feel() -> void:
	var trial := S.clone()
	var r := WeightFeel.apply(trial, B)
	if not r["ok"]:
		_say(r["msg"] + " (nothing changed; pick another weapon or card, then try again)")
		return
	_push_undo()
	_markers_hold()
	S.cards = trial.cards
	_markers_follow()
	_retimed()
	_say(r["msg"] + ".  Ctrl+Z undoes")


func _beats_clear() -> void:
	if S.beats_audio.is_empty():
		_say("no beats on the timeline to clear: run Beats: find the beats in the sound first")
		return
	_push_undo()
	S.beats_audio = []
	if ui_timeline != null:
		ui_timeline.queue_redraw()
	_say("beat marks taken off the timeline (Ctrl+Z puts them back)")
	_refresh()


func _audio_to_playhead() -> void:
	if S.audio.is_empty():
		_say("no sound on the timeline: run Audio: add a sound file first")
		return
	var t := snappedf(playhead, 0.001)
	if absf(t - float(S.audio["offset"])) < 1e-6:
		_say("the sound already starts at %.2f s: click the timeline to move the playhead, then run this again" % t)
		return
	_push_undo()
	S.audio["offset"] = t
	_say("the sound now starts at %.2f s (Ctrl+Z puts it back)" % t)
	_refresh()


## keep the sound in step with the playhead. before = the playhead before this frame's advance, dt = the advance
func _audio_tick(before: float, dt: float) -> void:
	if String(S.audio.get("path", "")) != _a_path:
		_audio_reload()
	if _a_player == null or _a_player.stream == null or S.audio.is_empty():
		_a_after = playhead
		return
	_a_player.volume_db = float(S.audio.get("gain_db", 0.0))
	if not playing:
		if _a_on:
			_a_player.stop()
			_a_on = false
		if _a_slice_until > 0 and Time.get_ticks_msec() >= _a_slice_until:
			_a_player.stop()
			_a_slice_until = 0
		_a_after = playhead
		return
	var want := playhead - float(S.audio["offset"])
	var jumped := _a_after < 0.0 or absf(before - _a_after) > 1e-4 or playhead < before - 1e-6 or playhead - before > dt + 1e-4
	if want < 0.0 or want >= _a_player.stream.get_length():
		if _a_on or _a_player.playing:
			_a_player.stop()
		_a_on = false
	elif jumped or not _a_on or not _a_player.playing:
		_a_slice_until = 0
		_a_player.play(want)
		_a_on = true
		audio_seeks += 1
	if _a_on and _a_player.playing:
		audio_err = audio_position() - (playhead - float(S.audio["offset"]))   # against the true offset, not the seek's own value
	_a_after = playhead


## the playhead was dragged (not playing): sound ~1 frame + 40 ms of it, at most one slice per rendered frame
func _audio_scrub() -> void:
	if _a_player == null or _a_player.stream == null or S.audio.is_empty() or playing:
		return
	var fr := Engine.get_process_frames()
	if fr == _a_slice_frame:
		return
	_a_slice_frame = fr
	var want := playhead - float(S.audio["offset"])
	if want < 0.0 or want >= _a_player.stream.get_length():
		_a_player.stop()
		_a_slice_until = 0
		return
	_a_player.volume_db = float(S.audio.get("gain_db", 0.0))
	_a_player.play(want)
	_a_slice_until = Time.get_ticks_msec() + int(round((1.0 / maxf(S.fps, 1) + AUDIO_SLICE_EXTRA) * 1000.0))
	audio_slices += 1


## ---- VIDEO TO ANIMATION (round 45, GATES AA2). A video goes to tools/see_video.py (MediaPipe, run as its own process
## so the window keeps working: _video_poll); its pose.json comes back through _import_pose: VideoImport fits the body
## per frame and rebuilds the travel, MocapClean plants the standing feet, and it opens as a NEW scene in scenes/_wip
## (one card per frame, like a .bvh: Animator tools / Simplify make it sparse). Nothing else changes; one refusal line.
const VIDEO_EXT := ["mp4", "mov", "avi", "webm", "mkv", "m4v"]
var video_python := "python"   # the interpreter that has mediapipe + opencv (tests point it elsewhere to check refusals)
var _video_pid := -1
var _video_out := ""
var _video_name := ""
var _video_t := 0.0
var _video_raw := false   # "import raw": the tracker's frames go straight to the fit, no VideoCleanup (jitter, floor, plants)


func _video_ask(raw := false) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.mp4, *.mov, *.avi, *.webm, *.mkv, *.m4v ; videos"])
	fd.use_native_dialog = true
	fd.title = "Animation from a video of a person"
	fd.file_selected.connect(func(p): _import_video(p, raw); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


func _import_video(path: String, raw := false) -> void:
	if _video_pid >= 0 and OS.is_process_running(_video_pid):
		_say("still tracking %s: one video at a time; try again when it arrives" % _video_name)
		return
	if not FileAccess.file_exists(path):
		_say("could not track %s: no such file; pick the video again" % path.get_file())
		return
	_video_name = path.get_file()
	_video_raw = raw
	_video_out = OS.get_user_data_dir().path_join("video_track/%s.json" % safe_file(path.get_file().get_basename()))
	DirAccess.make_dir_recursive_absolute(_video_out.get_base_dir())
	if FileAccess.file_exists(_video_out):
		DirAccess.remove_absolute(_video_out)
	var tool := ProjectSettings.globalize_path("res://tools/see_video.py")
	_video_pid = OS.create_process(video_python, PackedStringArray([tool, path, _video_out]))
	if _video_pid < 0:
		_say("could not track %s: \"%s\" did not start (it needs Python with mediapipe and opencv-python: run pip install mediapipe opencv-python)" % [_video_name, video_python])
		return
	_video_t = 0.0
	_say("tracking %s: finding the person in every frame (about a second per second of video)..." % _video_name)


func _video_poll(dt: float) -> void:
	if _video_pid < 0:
		return
	_video_t += dt
	if OS.is_process_running(_video_pid):
		return
	_video_pid = -1
	if not FileAccess.file_exists(_video_out):
		_say("could not track %s: the tracker found no person, or could not read the video. Try a clip with one person, whole body in view" % _video_name)
		return
	_import_pose(_video_out, _video_name, _video_raw)


## a pose file (tools/see_video.py's) -> a new scene in scenes/_wip, opened. Returns the new scene's path ("" refused).
## The cleanup (VideoCleanup: One Euro jitter, the floor level, foot plants held where the leg reaches) is the default;
## raw = true is "import raw", the tracker's frames as they came (MocapClean's card lock instead)
func _import_pose(path: String, from := "", raw := false) -> String:
	var P := VideoImport.load_file(path)
	if not P["ok"]:
		_say("could not import %s: %s; pick a pose file the tracker wrote, or a video" % [(from if from != "" else path.get_file()), P["why"]])
		return ""
	var keep := B.state()
	# AA3: the weapon in his hand now (any but a dagger) is the one he holds in the video, in both hands
	var held: String = B.wep_kind if B.wep_on and B.wep_hand != "" and B.wep_kind != "dagger" else ""
	var frames: Array = P["frames"]
	var C := {}
	if not raw:
		C = VideoCleanup.run(frames, P["fps"], float(P.get("tilt", 0.0)))
		frames = C["frames"]
	var fitted := VideoImport.solve(B, frames, held)
	var V := VideoImport.to_scene(B, fitted, P["fps"], 1, safe_file((from if from != "" else path.get_file()).get_basename()))
	var r := {"locked": 0, "text": ""}
	if raw:
		r = MocapClean.clean(V, B, {})   # needs a card per frame: thinned after
		V = VideoImport.thin(V, VideoImport.every_for(V.fps))
	else:
		V = VideoImport.thin(V, VideoImport.every_for(V.fps))
		V.plants = VideoCleanup.reachable(V, B, FootPlant.from_file(C["plants"]), V.fps)
		r = {"locked": V.plants.size(), "text": VideoCleanup.report(V.plants.size(), C["jitter_raw"], C["jitter_clean"], C["tilt"])}
	B.set_state(keep)
	var d: Dictionary = V.to_dict(B)
	var src: String = from if from != "" else path.get_file()
	d["plan"] = "Video import of %s: %d frames at %d fps tracked by MediaPipe (tools/see_video.py), fitted by VideoImport%s; %s" % [src, fitted.size(), V.fps, (", the camera's %.0f deg tilt levelled" % P["tilt"]) if float(P["tilt"]) > 0.0 else "", r["text"]]
	var base := safe_file(String(d["scene"]))
	var out := "res://scenes/_wip/%s.json" % base
	var n := 2
	while FileAccess.file_exists(out):   # never over an earlier import
		out = "res://scenes/_wip/%s_%d.json" % [base, n]
		n += 1
	_write(out, d)
	_load_scene(out)
	_rebuild_cards()
	_refresh()
	_say("imported %s as scenes/_wip/%s: %d frames in %d cards, the feet planted (%d locked)%s. The leg away from the camera is the least sure: check its knee, then move its cards like any others" % [src, out.get_file(), fitted.size(), V.cards.size(), int(r["locked"]),
		(", the %s in both hands" % held.replace("_", " ")) if held != "" else ". Holding a weapon in the video? Pick it first (Weapon: long axe ...), then import: he holds it in both hands"])
	return out


## ---- LIVE WEBCAM PUPPET (roadmap 21; scripts/live_puppet.gd). The webcam's tracker (tools/live_pose.py, MediaPipe) sends the
## person's landmarks over 127.0.0.1 and the body follows him, every frame, through the video import's fit. "Live: record /
## stop" keeps the take as a NEW scene in scenes/_wip, opened as a video import's is (never over one). Nothing else changes.
var live := LivePuppet.new()
var _live_said := false


func _live_toggle() -> void:
	if live.running:
		_live_end("the webcam puppet is off")
		return
	live.python = video_python
	var why := live.start(ProjectSettings.globalize_path("res://tools/live_pose.py"))
	if why != "":
		_say("live: could not start the webcam puppet: %s (try again, or pick another camera)" % why)
		return
	_live_said = false
	_say("live: the webcam puppet is starting on 127.0.0.1:%d. Stand where the camera sees your whole body: the mannequin follows you. Live: record / stop keeps what you do" % live.port)


## the take is kept first when one is running, then the tracker stops and the socket closes
func _live_end(why: String) -> void:
	if live.recording:
		_live_record()
	var f := live.fps()
	var lat := live.latency_ms()
	live.stop()
	_say("live: %s (posed %d frames at %.0f fps; camera to pose %.0f ms mean, %.0f ms worst)" % [why, live.frames_posed, f, lat[0], lat[1]])


func _live_record() -> void:
	if not live.running:
		_say("live: start the webcam puppet first (run Live: start the webcam puppet)")
		return
	if not live.recording:
		live.record_start()
		_say("live: recording. Press Live: record / stop again to keep the take as a new scene")
		return
	var r := live.record_stop(B)
	if not r["ok"]:
		_say("live: the take was not kept: %s (try recording again)" % r["why"])
		return
	_load_scene(r["path"])
	_rebuild_cards()
	_refresh()
	_say("live: the take is the new scene scenes/_wip/%s: %d frames at %.0f fps in %d cards. Check it, then move its cards like any others" % [String(r["path"]).get_file(), r["frames"], r["fps"], r["cards"]])


func _live_poll(_dt: float) -> void:
	if not live.running:
		return
	var got := live.poll(B)
	if not got.is_empty():
		if not _live_said:
			_live_said = true
			_say("live: the body follows you")
		_refresh()
	if live.ended:
		_live_end(live.error if live.error != "" else "the tracker stopped")


## BVH IMPORT (round 41, GATES WW7): a dropped .bvh (a Poser export) becomes a NEW scene in scenes/_wip, opened. The
## work is in scripts/bvh_import.gd; a refusal puts its reason on the status line and changes nothing.
func _import_bvh(path: String) -> void:
	var bv := BvhImport.load_file(path)
	var r := BvhImport.to_scene(bv, B, 1, 1.0, safe_file(path.get_file().get_basename())) if bv["ok"] else bv
	if not r["ok"]:
		_say("could not import %s: %s. Try another .bvh, or export it again from Blender" % [path.get_file(), r["why"]])
		return
	var d: Dictionary = (r["scene"] as Scene).to_dict(B)
	d["plan"] = "BVH import of %s: %s" % [path.get_file(), r["text"]]
	var base := safe_file(String(d["scene"]))
	var out := "res://scenes/_wip/%s.json" % base
	var n := 2
	while FileAccess.file_exists(out):   # never over an earlier import: walk_2, walk_3 ...
		out = "res://scenes/_wip/%s_%d.json" % [base, n]
		n += 1
	_write(out, d)
	_load_scene(out)
	_rebuild_cards()
	_refresh()
	_say("imported %s as scenes/_wip/%s: %s" % [path.get_file(), out.get_file(), r["text"]])


## ANIMATION IMPORT FROM OTHER SKELETONS (GAP_ANALYSIS row 26): .fbx / .glb / .gltf / .bvh -> a NEW scene in scenes/_wip,
## opened. The work is in scripts/anim_import.gd (method: docs/research/RETARGET.md); a refusal changes nothing.
func _anim_import_ask() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.fbx, *.glb, *.gltf, *.bvh ; animations"])
	fd.use_native_dialog = true
	fd.title = "Import an animation (Mixamo, Unreal, Blender ...)"
	fd.file_selected.connect(func(p): _import_anim(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## returns the new scene's path ("" refused)
func _import_anim(path: String) -> String:
	var r := AnimImport.import_file(path, B, safe_file(path.get_file().get_basename()))
	if not r["ok"]:
		_say("could not import %s: %s. Try another file, or export it again as .fbx with its mesh (Mixamo: With Skin)" % [path.get_file(), r["why"]])
		return ""
	var d: Dictionary = (r["scene"] as Scene).to_dict(B)
	d["plan"] = "Animation import of %s: %s. %s" % [path.get_file(), r["text"], r["report"]]
	var base := safe_file(String(d["scene"]))
	var out := "res://scenes/_wip/%s.json" % base
	var n := 2
	while FileAccess.file_exists(out):   # never over an earlier import
		out = "res://scenes/_wip/%s_%d.json" % [base, n]
		n += 1
	_write(out, d)
	_load_scene(out)
	_rebuild_cards()
	_refresh()
	_say("imported %s as scenes/_wip/%s: %d cards, %s. Play it, then move its cards like any others" % [path.get_file(), out.get_file(), (r["scene"] as Scene).cards.size(), r["report"]])
	return out


func _import_ask() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.glb, *.gltf ; glTF models"])
	fd.use_native_dialog = true
	fd.title = "Import a model (.glb)"
	fd.file_selected.connect(func(p): _import_file(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## checked, copied into the library (the original never changed), registered as a prop and put in the set. A
## refusal: the reason on the status line, nothing changed. Returns the importer's answer
func _import_file(path: String) -> Dictionary:
	var r: Dictionary = Importer.inspect(path)
	if not r["ok"]:
		_say("could not import %s: %s Try another .glb, or open it in Blender and export it as .glb again" % [path.get_file(), r["why"]])
		return r
	if r["kind"] == "rigged" and AnimImport.load_source(path)["ok"]:   # a skeleton WITH an animation: the animation import
		var o := _import_anim(path)
		return {"ok": o != "", "path": o, "why": "" if o != "" else "refused (the reason is on the status line)"}
	if r["kind"] == "rigged":
		var aa: Dictionary = Importer.accept(path, "animation", library)
		_say(("%s has a skeleton: importing animations comes later (UPGRADES #209); it was kept in your library. To use a model as a prop, drop one without a skeleton" % path.get_file()) if aa["ok"] else "could not import %s: %s Try another .glb, or open it in Blender and export it as .glb again" % [path.get_file(), aa["why"]])
		return aa
	var a: Dictionary = Importer.accept(path, "prop", library)
	if not a["ok"]:
		_say("could not import %s: %s Try another .glb, or open it in Blender and export it as .glb again" % [path.get_file(), a["why"]])
		return a
	var kind := "my " + String(a["path"]).get_file().get_basename()
	Props.register(kind, r["aabb"], a["path"], r["scale_factor"])
	_prop_add(kind)
	_say("imported %s as a prop: it is in the set and in Add prop%s" % [path.get_file(), "" if String(r["scale_note"]) == "" else ". " + String(r["scale_note"])])
	return a


## ---- WEIGHT PAINT (ROADMAP 72): the skin of the body, painted. One stroke = one undo step; the weights are saved on release
## to user://weights/<key>.weights.json (the mannequin's own file is never written) and applied again on the next load.
func _wp_setup() -> void:
	wp = SkinPaint.read(pieces.values(), skel)
	if wp.is_empty() or wp["skin"] == null:
		wp = {}
		return
	SkinPaint.load_into(wp, wp_key)
	SkinPaint.apply(wp)
	if wp_bind < 0:
		wp_bind = _wp_bind_of("lowerarm_r")


## the skin's bind index of a body joint (-1 when the skin does not bind it)
func _wp_bind_of(j: String) -> int:
	if wp.is_empty() or not bone_idx.has(j):
		return -1
	var skin: Skin = wp["skin"]
	var nm := skel.get_bone_name(int(bone_idx[j]))
	for k in skin.get_bind_count():
		if skin.get_bind_name(k) == nm:
			return k
	return -1


## the Bone and Brush lists and the two sliders: their own row on the toolbar, shown only while Weight paint is on
func _wp_ui(bar: Control) -> void:
	var pose := HBoxContainer.new()
	pose.name = "weight_paint_row"
	pose.add_theme_constant_override("separation", 6)
	pose.visible = false
	bar.add_child(pose)
	wp_row = pose
	wp_bone_pick = OptionButton.new()
	wp_bone_pick.tooltip_text = "the bone the brush adds, takes or smooths. While Weight paint is on the body shows this bone's weight"
	for j in Body.ORDER:
		var k := _wp_bind_of(j)
		if k >= 0:
			wp_bone_pick.add_item(nice(j))
			wp_bone_pick.set_item_metadata(wp_bone_pick.item_count - 1, k)
			if k == wp_bind:
				wp_bone_pick.select(wp_bone_pick.item_count - 1)
	wp_bone_pick.item_selected.connect(func(i: int):
		wp_bind = int(wp_bone_pick.get_item_metadata(i))
		_wp_show())
	pose.add_child(wp_bone_pick)
	wp_mode_pick = OptionButton.new()
	wp_mode_pick.tooltip_text = "Add: the bone gains weight; Subtract: it loses; Smooth: it evens out with its neighbours"
	for m in ["Add", "Subtract", "Smooth"]:
		wp_mode_pick.add_item(m)
	wp_mode_pick.item_selected.connect(func(i: int):
		wp_mode = ["add", "subtract", "smooth"][i])
	pose.add_child(wp_mode_pick)
	var rad := HSlider.new()
	rad.min_value = 0.02
	rad.max_value = 0.3
	rad.step = 0.005
	rad.value = wp_radius
	rad.custom_minimum_size = Vector2(90, 0)
	rad.tooltip_text = "brush radius on the skin (metres): the paint reaches this far from the mouse"
	rad.value_changed.connect(func(v: float): wp_radius = v)
	pose.add_child(rad)
	var stn := HSlider.new()
	stn.min_value = 0.05
	stn.max_value = 1.0
	stn.step = 0.01
	stn.value = wp_strength
	stn.custom_minimum_size = Vector2(90, 0)
	stn.tooltip_text = "brush strength: how much weight one dab moves at the centre of the brush"
	stn.value_changed.connect(func(v: float): wp_strength = v)
	pose.add_child(stn)


func _wp_toggle() -> void:
	if wp.is_empty():
		_say("no skin to paint: Weight paint works on a body with a skin: pick the mannequin")
		return
	wp_on = not wp_on
	if wp_row != null:
		wp_row.visible = wp_on
	_wp_show()
	_say("weight paint on: pick a bone in Bone, then drag on the body. The colour shows that bone's weight: dark = none, orange = all" if wp_on else "weight paint off")


## the body's colours follow the picked bone while the mode is on; off = the body as it was
func _wp_show() -> void:
	if not wp.is_empty():
		SkinPaint.apply(wp, wp_bind if wp_on else -1)
		if not wp_on:
			_skp_build()   # the painted weights decide the pick and the light from now on


## a left press on the body starts a stroke (and one undo step); a press off the body is the view's. True = taken
func _wp_input(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			if wp_bind < 0:
				_say("pick a bone first: choose one in the Bone list, then press on the body")
				return true
			SkinPaint.refresh(wp)   # the stroke lands on the shape the body has when it starts
			var hit = SkinPaint.pick(wp, mb.position, cam)
			if hit == null:
				return false
			_push_undo()
			wp_stroke = true
			wp_centres = []
			_wp_dab(hit)
			return true
		if wp_stroke:
			wp_stroke = false
			var saved := SkinPaint.save(wp, wp_key)
			_say(("weight stroke done (%d dabs), the weights are saved" % wp_centres.size()) if saved else "weight stroke done, but the weights could not be saved (the disk is full or read-only): free some space, then paint again")
			return true
		return false
	if ev is InputEventMouseMotion and wp_stroke:
		var hit = SkinPaint.pick(wp, (ev as InputEventMouseMotion).position, cam)
		if hit != null:
			_wp_dab(hit)
		return true
	return false


## one brush dab at c: every surface's weights move for the picked bone, then the meshes are redrawn
func _wp_dab(c: Vector3) -> void:
	wp_centres.append(c)
	for s in wp["surfs"]:
		SkinPaint.paint(s, s["pos"], c, wp_radius, wp_bind, wp_strength, wp_mode)
	SkinPaint.apply(wp, wp_bind if wp_on else -1)


## a test's own library folder goes with it (never the user's)
static func _rm_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_rm_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _unsaved() -> bool:
	var H := _hero_scene()   # TC3: the file is the hero's scene, whoever is active
	return (not H.cards.is_empty() or not H.props.is_empty()) and _doc_key() != _clean


## what "saved" compares: the cards, and the set when there is one (no props: the same string as before round 37); with
## a second actor (TC3) each actor's name, place and cards too (one actor: the same string as before)
func _doc_key() -> String:
	var H := _hero_scene()
	var k := JSON.stringify(H.cards) + ("" if H.props.is_empty() else JSON.stringify(H.props.map(func(p): return Props.to_dict(p))))
	if not H.shots.is_empty():
		k += "|shots" + var_to_str(H.shots)   # the shots and their cameras: an unsaved change too (ROADMAP 75)
	for a in H.actors:
		k += "|" + JSON.stringify([a["name"], a["xf"], (a["scene"] as Scene).cards])
	return k


func _load_scene(path: String) -> void:
	var probe: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (probe is Dictionary):   # a missing, empty or non-JSON file is refused with a message, not a crash
		_say_plain("NOT NOW: %s is not a scene file (missing, empty or not JSON)" % path.get_file())
		return
	_actors_home()   # TC3: the opened file's hero goes on the hero's body; its actors are built from it
	if not vdiff.is_empty():   # COMPARE WITH: a comparison belongs to the scene it was made in
		_vdiff_clear()
	scene_path = path
	layer_on = -1   # NA1: edits go to the first layer of a newly opened scene
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check_ran = false
	S = Scene.new()
	if d.has("cards"):
		S.from_dict(d)
		if not S.props_skipped.is_empty():
			_say.call_deferred("this scene's set names models your library does not have (%s): they were left out" % ", ".join(S.props_skipped))
	else:   # an old move file: its keys become cards
		var prev := 0.0
		for k in d.get("keys", []):
			S.add("key %.2fs" % k["t"], k["pose"])
			S.cards[-1]["move"] = maxf(0.05, k["t"] - prev) if S.cards.size() > 1 else -1.0
			S.cards[-1]["hold"] = 0.0
			prev = k["t"]
		S.name = d.get("name", "move")
	if ui_scene_name != null:
		ui_scene_name.text = S.name
	_recent_note(path)
	_show_open_scene()
	if ui_natural != null:
		ui_natural.set_pressed_no_signal(S.natural)   # the boxes show THIS scene's settings (10-14: they kept the last ones)
		ui_spline.set_pressed_no_signal(S.spline)
		ui_loop.set_pressed_no_signal(S.loop)
	ov.mark_dirty()
	wt.mark_dirty()
	_dummy_hits()
	sel_card = -1
	playhead = 0.0
	_clean = _doc_key()
	if not _recovering:
		_autosave_drop()   # opened a scene: what was unsaved was given up (it asks first, V3)
		if journal_on:
			journal.trim()   # ... and its journal goes with it
	S.apply(B, 0.0)


# ---------------------------------------------------------------- THE SHOT CAMERA (docs/GAP_ANALYSIS.md row 21; GATES SC)
## scripts/shot_camera.gd holds the keys' maths; here: the commands, look-through and the playblast's use of it. The keys
## are the HERO's scene's (the file's top level), in the hero's world; with another fighter active the stage moves, and
## the camera with it (_stage_xf). Look-through is a VIEW: never saved, never an undo step.
var shot_through := false   # looking through the shot camera
var ui_shot: ShotFrame      # the 16:9 frame and passepartout (scripts/shot_frame.gd)
var _shot_fov := 40.0       # the viewport camera's own fov, put back when look-through ends
var _shot_dof: CameraAttributesPractical   # the rack focus's depth of field (ROADMAP 76; _shot_dof_set)


func _shot_commands(add: Callable) -> void:
	add.call("Camera: key the shot camera from the view", "", _shot_key_view, "shot camera key keyframe film cinema lens frame record angle view animate",
		true, "the shot camera keyed at the playhead where the view is now (looking at the view's pivot, its framing as the lens); while looking through, the camera as it plays there")
	add.call("Camera: look through the shot camera", "", _shot_toggle, "shot camera view through active numpad 0 frame 16:9 passepartout film",
		false, "the view shows the keyed shot camera at the playhead in a 16:9 frame (again: back to the free view); the playblast renders through it")
	add.call("Camera: remove the key here", "", _shot_remove, "shot camera key delete remove unkey", true, "the shot camera's key at the playhead goes (the last one: the scene has no shot camera)")
	for mm in ShotCam.LENSES:
		add.call("Camera: lens %d mm" % mm, "", _shot_lens.bind(float(mm)), "shot camera focal length zoom lens %d mm wide tele" % mm, true,
			"the shot camera's focal length at the playhead: %d mm on a 36 mm sensor (%.1f deg across a 16:9 frame); keys it there if it has no key" % [mm, ShotCam.fov_h(mm)])
	add.call("Shots: add a shot from the current view at the playhead", "", _shot_add, "shot shots cut new add camera angle view playhead",
		true, "a cut at the playhead's frame: a new shot whose camera is the view as it is now, on from there to the next cut (the first shot starts at 0 s)")
	add.call("Shots: delete the shot at the playhead", "", _shot_delete, "shot shots cut delete remove", true,
		"the shot on at the playhead goes; the shot before it runs on to the next cut")
	add.call("Shots: rename the shot at the playhead", "", _shot_rename_ask, "shot shots name rename title label", true,
		"type the shot's name (it shows on the SHOTS lane)")
	add.call("Camera: impact shake at the playhead", "", _shot_shake_here, "shot camera shake impact hit jolt vibrate quake tremor camera shake",
		true, "a camera shake (ShotFx Impact preset: about 2 cm and 1 deg, 0.6 s, decaying) starts at the playhead; the shot camera must be keyed (ROADMAP 76)")
	add.call("Camera: impact shakes on the hit markers", "", _shot_shake_markers, "shot camera shake impact hit markers jolt all",
		true, "an Impact shake at every hit marker of the scene (a marker named or kinded hit or impact); one undo step")
	add.call("Camera: remove the shake at the playhead", "", _shot_shake_remove, "shot camera shake remove delete unshake",
		true, "the shake that starts at the playhead (within half a frame) goes")
	add.call("Camera: focus distance here", "", _shot_focus_dist, "shot camera focus rack depth of field dof distance pivot blur",
		true, "a rack-focus key at the playhead: the distance from the shot camera to where it looks (its aim point)")
	add.call("Camera: focus on the selected part here", "", _shot_focus_part, "shot camera focus rack depth of field dof track part follow selected",
		true, "a rack-focus key at the playhead that TRACKS the selected part: the focus distance is the camera-to-part distance at every frame until the next focus key")
	add.call("Camera: remove the focus key here", "", _shot_focus_remove, "shot camera focus rack depth of field dof remove delete",
		true, "the rack-focus key at the playhead (within half a frame) goes")


## THE SHOTS (ROADMAP 75; shot_camera.gd): the scene's list of cuts, each shot with its own camera. The first shot always
## starts at 0 s. Each command is ONE undo step (_do); a cut dragged on the lane takes one at its first move (_shot_cut_drag).
var ui_shot_dlg: ConfirmationDialog
var ui_shot_name: LineEdit
var _shot_rename_i := -1
var _shot_drag_undo := false   # a cut's drag has taken its undo step (at its first move)


func _shot_shots() -> Array:
	return _hero_scene().shots


## the shot on at the playhead (-1 = the scene has no shots)
func shot_now_index() -> int:
	return ShotCam.shot_index(_shot_shots(), playhead)


## the camera track of the shot on at the playhead ([] = none)
func _shot_keys() -> Array:
	var i := shot_now_index()
	return _shot_shots()[i]["keys"] if i >= 0 else []


## the first shot, when the scene has none (inside an edit's undo step)
func _shot_ensure() -> void:
	if _shot_shots().is_empty():
		_shot_shots().append({"t": 0.0, "name": ShotCam.SHOT_NAME % 1, "keys": []})


## a shot is gone: the first shot starts at 0 s again
func _shot_drop(i: int) -> void:
	_shot_shots().remove_at(i)
	if not _shot_shots().is_empty():
		_shot_shots()[0]["t"] = 0.0


func _shot_add() -> void:
	if _hero_scene().cards.is_empty():
		_say("a shot is taken from a scene: open a scene, or press Enter to add the body as a card, then add a shot")
		return
	var fps := float(S.fps)
	var first := _shot_shots().is_empty()
	var fr := 0 if first else roundi(clampf(playhead, 0.0, S.length()) * fps)   # a cut lands on a whole frame
	var t := float(fr) / fps
	if not first and fr <= 0:
		_say("the first shot starts at 0 s: move the playhead past 0 s, then add a shot there")
		return
	for sh in _shot_shots():
		if roundi(float(sh["t"]) * fps) == fr:
			_say("a shot already starts at %.2f s (%s): move the playhead to another frame, then add a shot" % [t, sh["name"]])
			return
	var key := ShotCam.sample(_shot_keys(), t) if shot_through else _shot_view_key(t)
	key["t"] = t
	var idx := ShotCam.insert_index(_shot_shots(), t)
	var nm := ShotCam.SHOT_NAME % (_shot_shots().size() + 1)
	_do(func(): _shot_shots().insert(idx, {"t": t, "name": nm, "keys": [key]}))
	_say("%s: a cut at %.2f s, the view from there (%.0f mm); Ctrl+Z takes it back" % [nm, t, float(key["f"])])


func _shot_delete() -> void:
	var i := shot_now_index()
	if i < 0:
		_say("no shots yet: 'Shots: add a shot from the current view at the playhead' makes the first one")
		return
	var nm := String(_shot_shots()[i]["name"])
	_do(func(): _shot_drop(i))
	_say("deleted %s (%d left)%s" % [nm, _shot_shots().size(), "; the scene has no shots now" if _shot_shots().is_empty() else ""])
	if _shot_shots().is_empty():
		_shot_off()


## the rename dialog (the shot on at the playhead); its OK is _shot_rename_to
func _shot_rename_ask() -> void:
	var i := shot_now_index()
	if i < 0:
		_say("no shots yet: 'Shots: add a shot from the current view at the playhead' makes the first one, then rename it")
		return
	if ui_shot_dlg == null:
		ui_shot_dlg = ConfirmationDialog.new()
		ui_shot_dlg.title = "Rename the shot"
		ui_shot_dlg.ok_button_text = "Rename"
		ui_shot_dlg.min_size = Vector2i(320, 0)
		ui_shot_name = LineEdit.new()
		ui_shot_name.name = "edit_shot_name"
		ui_shot_name.placeholder_text = "name for the shot"
		ui_shot_dlg.add_child(ui_shot_name)
		ui_shot_dlg.register_text_enter(ui_shot_name)
		ui_shot_dlg.confirmed.connect(func(): _shot_rename_to(_shot_rename_i, ui_shot_name.text))
		add_child(ui_shot_dlg)
	_shot_rename_i = i
	ui_shot_name.text = String(_shot_shots()[i]["name"])
	ui_shot_dlg.popup_centered()
	ui_shot_name.select_all()
	ui_shot_name.grab_focus()


## shot i's name: one undo step; an empty name is refused (the old one stays)
func _shot_rename_to(i: int, nm: String) -> void:
	nm = nm.strip_edges()
	if i < 0 or i >= _shot_shots().size() or nm == "":
		_say("the shot's name is empty: type a name, then Rename")
		return
	if String(_shot_shots()[i]["name"]) == nm:
		return
	_do(func(): _shot_shots()[i]["name"] = nm)
	_say("the shot is called %s now (Ctrl+Z takes it back)" % nm)


## a cut dragged on the SHOTS lane (timeline.gd shot_cut): the first move takes the one undo step, the rest move that cut
func _shot_cut_drag(i: int, t: float, final: bool) -> void:
	var sh := _shot_shots()
	if i <= 0 or i >= sh.size():
		return
	if not _shot_drag_undo:
		_push_undo()
		_shot_drag_undo = true
	sh[i]["t"] = t
	if final:
		_shot_drag_undo = false
		_after_edit()
		_journal_write()
		_say("the cut to %s is at %.2f s (Ctrl+Z takes it back)" % [sh[i]["name"], t])
	ui_timeline.queue_redraw()
	if shot_through:
		_shot_apply()


## the free part of the view (between the panels), or the whole viewport in a clean render (playblast, --clean)
func _shot_free() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	if clean or ui_root == null or not ui_root.visible:
		return Rect2(Vector2.ZERO, vs)
	var top := float(TOP_H) + 8.0
	var bot := float(bottom_h + 6 + LINE_H) + 8.0
	return Rect2(lw() + 8.0, top, maxf(64.0, vs.x - lw() - rw() - 16.0), maxf(36.0, vs.y - top - bot))


func shot_rect() -> Rect2i:
	return ShotCam.frame_rect(_shot_free())


## the shot camera at t in the RENDER's space (the stage under the active fighter): {"pos", "aim", "f"}; {} = none
func shot_at(t: float) -> Dictionary:
	var i := ShotCam.shot_index(_shot_shots(), t)   # the shot on at t (ROADMAP 75): its camera, in the render's space
	if i < 0:
		return {}
	var k := ShotCam.sample(_shot_shots()[i]["keys"], t)
	if k.is_empty():
		return k
	var X := _stage_xf()
	return {"pos": X * (k["pos"] as Vector3), "aim": X * (k["aim"] as Vector3), "f": k["f"]}


## what the shot camera SHOWS at t (the playblast and look-through; the gizmo keeps shot_at, the keyed camera): {"xf"
## (the transform, shaken by the shot's shake), "f", "focus" (m, the rack focus; NAN = no focus keys)}; {} = no keys
func shot_view_at(t: float) -> Dictionary:
	var k := shot_at(t)
	if k.is_empty():
		return k
	var fx: Dictionary = ShotCam.fx_at(_shot_shots(), t)
	var xf := ShotCam.xf(k["pos"], k["aim"])
	xf = ShotFx.shaken(xf, fx.get("shake", []), t)
	var focus := NAN
	var kp := ShotCam.at(_shot_shots(), t)   # the keyed camera's position in the hero's space (the focus is measured from it)
	if not fx.get("focus", []).is_empty() and not kp.is_empty():
		var hero := _hero_scene()
		focus = ShotFx.focus_at(fx["focus"], t,
			func(tt: float) -> Vector3: return ShotCam.at(_shot_shots(), tt)["pos"] as Vector3,
			func(j: String, tt: float) -> Vector3: return ShotFx.part_at(hero, j, tt))
	return {"xf": xf, "f": k["f"], "focus": focus}


## the playhead's rack focus into the viewport camera's depth of field (Godot's CameraAttributesPractical): sharp at
## `dist`, blurred on both sides; no focus (NAN) = no DOF (the camera's attributes are cleared)
func _shot_dof_set(dist: float) -> void:
	if cam == null:
		return
	if is_nan(dist):
		cam.attributes = null
		return
	if _shot_dof == null:
		_shot_dof = CameraAttributesPractical.new()
		_shot_dof.dof_blur_far_enabled = true
		_shot_dof.dof_blur_near_enabled = true
		_shot_dof.dof_blur_far_transition = 1.5
		_shot_dof.dof_blur_near_transition = 1.5
		_shot_dof.dof_blur_amount = 0.08
	_shot_dof.dof_blur_far_distance = dist
	_shot_dof.dof_blur_near_distance = dist
	cam.attributes = _shot_dof


## look-through: the viewport camera becomes the shot camera at the playhead. false = not looking through (no keys
## left: it turns itself off and the free view comes back)
func _shot_apply() -> bool:
	if not shot_through or cam == null:
		return false
	var k := shot_view_at(playhead)
	if k.is_empty():
		_shot_off()
		return false
	var r := shot_rect()
	ShotCam.apply_to(cam, k["xf"], k["f"], r, get_viewport().get_visible_rect().size)
	_shot_dof_set(float(k["focus"]))
	if ui_shot == null and ui_root != null:
		ui_shot = ShotFrame.new()
		ui_shot.name = "shot_frame"
		ui_root.add_child(ui_shot)
		ui_root.move_child(ui_shot, 0)   # under every panel
	if ui_shot != null:
		ui_shot.visible = not clean
		ui_shot.show_rect(r, "SHOT CAMERA  %.0f mm  16:9" % float(k["f"]))
	return true


func _shot_off() -> void:
	var was := shot_through
	shot_through = false
	if ui_shot != null:
		ui_shot.visible = false
	if cam != null:
		cam.attributes = null   # the free view has no rack focus (ROADMAP 76)
	if was and cam != null:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = _shot_fov
		_cam()


## leave look-through with the free view put where the shot camera is (its aim the pivot), so an orbit starts from the
## camera's own view instead of jumping back (Blender: orbiting in camera view leaves it at the camera)
func _shot_hand_over() -> void:
	var k := shot_at(playhead)
	_shot_off()
	if k.is_empty():
		return
	var d: Vector3 = (k["pos"] as Vector3) - (k["aim"] as Vector3)
	if d.length() < 1e-4:
		return
	target = k["aim"]
	dist = d.length()
	d = d.normalized()
	pitch = clampf(rad_to_deg(-asin(clampf(d.y, -1.0, 1.0))), -89.0, 89.0)
	yaw = rad_to_deg(atan2(d.x, d.z))
	_cam()
	_say("left the shot camera's view (orbiting): the free view starts where the camera was; 'Camera: look through' goes back")


func _shot_toggle() -> void:
	if shot_through:
		_shot_off()
		_say("back to the free view: orbit, pan and zoom move the view again (the shot camera stays keyed)")
		return
	if _shot_shots().is_empty():
		_say("this scene has no shot camera yet: frame the view, then use 'Camera: key the shot camera from the view'")
		return
	_shot_fov = cam.fov
	shot_through = true
	_shot_apply()
	var k := ShotCam.sample(_shot_keys(), playhead)
	_say("looking through the shot camera (%.0f mm, 16:9 frame); the playblast renders this. Run it again to get the free view back" % float(k["f"]))


## the key the current view makes: the lens where the view's rendered origin is (its pan offset included), aimed at the
## view's pivot (target), the focal length that frames in the 16:9 frame what the view shows across the same height
func _shot_view_key(t: float) -> Dictionary:
	var vs := get_viewport().get_visible_rect().size
	var r := shot_rect()
	var Xi := _stage_xf().affine_inverse()
	var o: Vector3 = cam.get_camera_transform().origin
	var fv := rad_to_deg(2.0 * atan(tan(deg_to_rad(cam.fov) * 0.5) * float(r.size.y) / vs.y))
	return {"t": t, "pos": Xi * o, "aim": Xi * target, "f": clampf(ShotCam.f_for_fov_v(fv), ShotCam.F_MIN, ShotCam.F_MAX)}


func _shot_key_view() -> void:
	if _hero_scene().cards.is_empty():
		_say("the shot camera is keyed in a scene: open a scene, or press Enter to add the body as a card, then key the camera")
		return
	var t := clampf(playhead, 0.0, S.length())
	var key := ShotCam.sample(_shot_keys(), t) if shot_through else _shot_view_key(t)
	key["t"] = t
	var first := _shot_shots().is_empty()
	_do(func():
		_shot_ensure()
		ShotCam.put(_shot_keys(), key))
	var p: Vector3 = key["pos"]
	_say("shot camera keyed at %s: lens at (%s, %s, %s), %.0f mm%s (Ctrl+Z takes it back)" % [Units.time(t, S.fps), Units.len(p.x), Units.len(p.y), Units.len(p.z), float(key["f"]),
		"; 'Camera: look through the shot camera' shows it" if first else ""])


func _shot_remove() -> void:
	var ks := _shot_keys()
	var i := ShotCam.key_near(ks, playhead, 0.5 / maxf(1.0, float(S.fps)) + 0.001)
	if i < 0:
		_say("no shot camera key at the playhead: move the playhead onto a camera key (%d in this scene), then remove it" % ks.size())
		return
	var t := float(ks[i]["t"])
	var si := shot_now_index()
	var last := ks.size() == 1   # the shot's last key: the shot goes with it
	_do(func():
		_shot_keys().remove_at(i)
		if _shot_keys().is_empty():
			_shot_drop(si))
	_say("removed the shot camera's key at %s%s" % [Units.time(t, S.fps), "; that was the shot's last key, so the shot is gone" if last else ""])
	if _shot_shots().is_empty():
		_shot_off()


func _shot_lens(mm: float) -> void:
	var ks := _shot_keys()
	if ks.is_empty():
		_say("the lens belongs to the shot camera: use 'Camera: key the shot camera from the view' first, then pick a lens")
		return
	var i := ShotCam.key_near(ks, playhead, 0.5 / maxf(1.0, float(S.fps)) + 0.001)
	var t := clampf(playhead, 0.0, S.length())
	var at_t := t if i < 0 else float(ks[i]["t"])
	if i >= 0 and absf(float(ks[i]["f"]) - mm) < 1e-6:
		_say("the shot camera's key at %s is already %.0f mm: pick another lens, or move the playhead to another time" % [Units.time(at_t, S.fps), mm])
		return
	_do(func():
		if i >= 0:
			_shot_keys()[i]["f"] = mm
		else:
			var k := ShotCam.sample(_shot_keys(), t)
			k["t"] = t
			k["f"] = mm
			ShotCam.put(_shot_keys(), k))
	_say("shot camera lens %.0f mm at %s (%.1f° across the 16:9 frame)%s" % [mm, Units.time(at_t, S.fps), ShotCam.fov_h(mm), "" if i >= 0 else ", a new key"])


## ---- CAMERA SHAKE and RACK FOCUS (ROADMAP 76; scripts/shot_fx.gd): each shot's own fx, one undo step each ----------
## _shot_fx() = the shot on at the playhead's fx: its own shake and rack focus (made in the shot when it has none)
func _shot_fx() -> Dictionary:
	var i := shot_now_index()
	if i < 0:
		return {}
	var sh: Dictionary = _shot_shots()[i]
	if not sh.has("fx"):
		sh["fx"] = {}
	return sh["fx"]


func _shot_fx_need_keys(what: String) -> bool:
	if _shot_keys().is_empty():
		_say("%s belongs to the shot camera: click 'Camera: key the shot camera from the view' first" % what)
		return false
	return true


func _shot_shake_here() -> void:
	if not _shot_fx_need_keys("the shake"):
		return
	var t := clampf(playhead, 0.0, S.length())
	var e := ShotFx.impact(t, ShotFx.list(_shot_fx(), "shake").size() + 1)
	_do(func(): ShotCam.put(ShotFx.list(_shot_fx(), "shake"), e))
	_say("camera shake at %.2f s: Impact, about 2 cm and 1 deg on the shot camera for %.1f s, decaying (Ctrl+Z takes it back)" % [t, float(e["dur"])])


func _shot_shake_markers() -> void:
	var ts := []
	for mk in S.markers:
		var nm := String(mk.get("name", "")).to_lower()
		var kd := String(mk.get("kind", "")).to_lower()
		if nm.contains("hit") or nm.contains("impact") or kd.contains("hit") or kd.contains("impact"):
			ts.append(float(mk["t"]))
	if ts.is_empty():
		_say("no hit markers in this scene: name a marker 'hit' or 'impact' (Markers: at the playhead), or put one shake at the playhead with 'Camera: impact shake at the playhead'")
		return
	if not _shot_fx_need_keys("the shakes"):
		return
	_do(func():
		var L := ShotFx.list(_shot_fx(), "shake")
		for t in ts:
			ShotCam.put(L, ShotFx.impact(float(t), L.size() + 1)))
	_say("%d impact shake%s, one at each hit marker (%s); Ctrl+Z takes them all back" % [ts.size(), "" if ts.size() == 1 else "s", ", ".join(ts.map(func(x): return "%.2f s" % float(x)))])


func _shot_shake_remove() -> void:
	var L: Array = _shot_fx().get("shake", [])
	var i := ShotCam.key_near(L, playhead, 0.5 / maxf(1.0, float(S.fps)) + 0.001)
	if i < 0:
		_say("no shake starts at the playhead: move the playhead onto a shake's start (%d in this scene), then remove it" % L.size())
		return
	var t := float(L[i]["t"])
	_do(func(): ShotFx.list(_shot_fx(), "shake").remove_at(i))
	_say("removed the shake that starts at %.2f s" % t)


func _shot_focus_dist() -> void:
	if not _shot_fx_need_keys("the focus"):
		return
	var t := clampf(playhead, 0.0, S.length())
	var k := ShotCam.sample(_shot_keys(), t)
	var d := maxf(ShotFx.DIST_MIN, (k["pos"] as Vector3).distance_to(k["aim"] as Vector3))
	var key := {"t": t, "dist": d}
	_do(func(): ShotCam.put(ShotFx.list(_shot_fx(), "focus"), key))
	_say("rack focus at %.2f s: %s, the distance to where the shot camera looks (between two focus keys the focus racks; 'look through' shows the blur)" % [t, Units.len(d)])


func _shot_focus_part() -> void:
	if not _shot_fx_need_keys("the focus"):
		return
	var t := clampf(playhead, 0.0, S.length())
	var j := sel
	var q := ShotFx.part_at(_hero_scene(), j, t)
	if is_nan(q.x):
		_say("'%s' has no point to focus on: select a joint (a hand, a foot, the head) in the body, then focus on it" % j)
		return
	var k := ShotCam.sample(_shot_keys(), t)
	var key := {"t": t, "part": j}
	_do(func(): ShotCam.put(ShotFx.list(_shot_fx(), "focus"), key))
	_say("focus tracks %s from %.2f s (%s from the shot camera now); the blur follows it until the next focus key" % [j, t, Units.len((k["pos"] as Vector3).distance_to(q))])


func _shot_focus_remove() -> void:
	var L: Array = _shot_fx().get("focus", [])
	var i := ShotCam.key_near(L, playhead, 0.5 / maxf(1.0, float(S.fps)) + 0.001)
	if i < 0:
		_say("no focus key at the playhead: move the playhead onto a focus key (%d in this scene), then remove it" % L.size())
		return
	var t := float(L[i]["t"])
	_do(func(): ShotFx.list(_shot_fx(), "focus").remove_at(i))
	_say("removed the focus key at %.2f s" % t)


## THE PLAYBLAST THROUGH THE SHOT CAMERA: {} = the scene has none (the frames are the view, as before); else look-through
## is on for the render (the panels are hidden, so the frame is the largest 16:9 in the window) and each image is cut to it
func _shot_blast_begin() -> Dictionary:
	if _shot_shots().is_empty():
		return {}
	var was := shot_through
	if not was:
		_shot_fov = cam.fov
	shot_through = true
	_shot_apply()
	return {"was": was, "rect": shot_rect()}


func _shot_blast_frame(sb: Dictionary) -> void:
	if not sb.is_empty():
		_shot_apply()


func _shot_blast_image(sb: Dictionary, img: Image) -> Image:
	return img if sb.is_empty() else img.get_region(sb["rect"])


func _shot_blast_end(sb: Dictionary) -> void:
	if not sb.is_empty() and not sb["was"]:
		_shot_off()
## ---- PROPORTIONS (round 51, GATES PR; scripts/proportions.gd) ----------------------------------------------------
## "Body: proportions..." opens a small dialog (a preset, the stature in cm); OK sets the scene's body: ONE undo step.
## The cards are RETARGETED (Proportions.retarget: every angle kept, the hips raised or lowered so the soles stand where
## they stood); world IK targets stay where they are and the new limbs reach them where they can.
var ui_prop_dlg: ConfirmationDialog
var ui_prop_preset: OptionButton
var ui_prop_stature: SpinBox
var ui_style_dlg: ConfirmationDialog
var ui_style_pct: SpinBox
var ui_style_name := ""
const PROP_KEYS := ["", "female_5", "female_50", "female_95", "male_5", "male_50", "male_95", "custom"]


func _proportions_dialog() -> void:
	if ui_prop_dlg == null:
		ui_prop_dlg = ConfirmationDialog.new()
		ui_prop_dlg.name = "proportions_dialog"
		ui_prop_dlg.title = "Body: proportions"
		ui_prop_dlg.min_size = Vector2i(340, 0)
		var v := VBoxContainer.new()
		ui_prop_preset = OptionButton.new()
		ui_prop_preset.name = "opt_preset"
		for k in PROP_KEYS:
			ui_prop_preset.add_item("the mannequin as shipped (%.1f cm)" % (Proportions.DEFAULT_STATURE * 100.0) if k == "" else ("custom stature" if k == "custom"
				else "%s (ANSUR II, %.1f cm)" % [Proportions.PRESET_NAMES[k], float(Proportions.PRESETS[k]["stature"]) * 100.0]))
		ui_prop_preset.item_selected.connect(func(i):
			var k: String = PROP_KEYS[i]
			if k != "custom":
				ui_prop_stature.set_value_no_signal((Proportions.DEFAULT_STATURE if k == "" else float(Proportions.PRESETS[k]["stature"])) * 100.0))
		v.add_child(ui_prop_preset)
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = "stature (cm)"
		h.add_child(l)
		ui_prop_stature = SpinBox.new()
		ui_prop_stature.name = "spin_stature"
		ui_prop_stature.min_value = 100.0
		ui_prop_stature.max_value = 230.0
		ui_prop_stature.step = 0.1
		ui_prop_stature.value_changed.connect(func(_x): ui_prop_preset.select(PROP_KEYS.size() - 1))
		h.add_child(ui_prop_stature)
		v.add_child(h)
		ui_prop_dlg.add_child(v)
		ui_prop_dlg.confirmed.connect(func():
			var k: String = PROP_KEYS[ui_prop_preset.selected]
			if k == "":
				proportions_set({})
			elif k == "custom":
				var d := S.body.duplicate(true)
				d.erase("preset")
				d["stature"] = ui_prop_stature.value / 100.0
				proportions_set(d)
			else:
				proportions_set(Proportions.preset(k)))
		add_child(ui_prop_dlg)
	var at := PROP_KEYS.find(String(S.body.get("preset", ""))) if not S.body.is_empty() else 0
	ui_prop_preset.select(at if at >= 0 else PROP_KEYS.size() - 1)
	ui_prop_stature.set_value_no_signal(float(S.body.get("stature", Proportions.DEFAULT_STATURE)) * 100.0)
	ui_prop_dlg.popup_centered()


## the scene's proportions -> d ({} = the default body): cards retargeted, one undo step. Returns what was set.
func proportions_set(d: Dictionary) -> Dictionary:
	var nd := Proportions.clean(d)
	if nd == S.body:
		_say("the body already has these proportions: pick another preset or stature in 'Body: proportions...'")
		return nd
	_do(func():
		Proportions.retarget(S, B, nd)
		B.set_proportions(nd)   # the pose as it was, on the new bones
		_dummy_hits()
		ov.mark_dirty()
		wt.mark_dirty()
		if not S.cards.is_empty():
			S.apply(B, playhead))
	var st := float(nd.get("stature", Proportions.DEFAULT_STATURE))
	_say("body: %s, %.1f cm tall; every card keeps its angles, the feet stay on the floor (Ctrl+Z takes it back)" % [Proportions.PRESET_NAMES.get(String(nd.get("preset", "")), "the mannequin as shipped" if nd.is_empty() else "custom"), st * 100.0])
	return nd
