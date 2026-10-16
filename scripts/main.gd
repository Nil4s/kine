## main.gd - the poser window. All math lives in body.gd (the body), scene.gd (moving between poses), moves.gd (old files).
##
## Screen:  top bar = views + undo |  left = POSES (click one to put the body in it) |  right = the SELECTED PART
##          (sliders in words) + HANDS & BAT |  bottom = the SCENE (pose cards in a row; the poser moves between them).
## Mouse:   click a part = select;  drag = rotate it;  Shift+drag = roll it;  drag a hand/foot = the whole limb follows
##          (Alt: only the wrist/ankle);  Ctrl+drag the hips = move the body;  the bat: free = drag/Shift/Alt, locked =
##          dragging it moves the hand.   Right-drag = orbit, middle-drag = pan, wheel = zoom.
## Keys:    shown on every button (Q snap, R reset, L lock bat, F fingers, G 2 hands, Space play, Ctrl+Z undo ...).
## Command line (after --): --pose <json> | --scene <json> | --t <s> | --view <1-5> | --focus <joint> | --shot <png>
extends Node3D

const SEL := Color(0.25, 0.55, 1.0)
const LIMIT := Color(1.0, 0.82, 0.15)
const TOUCH := Color(1.0, 0.25, 0.2)
const ARMS_OUT := 25.0   # relaxed arms: degrees out from straight down (Nick 10-12)
const LEFT_W := 250
const RIGHT_W := 370
const BOTTOM_H := 321   # +52 for the timeline (round 6); +7 (round 7): a card with move AND hold rows needs 315 px of
						# panel, it had 308 and ran 1 px off the window's bottom (tests/empty_state_test.gd measured it)
const BOTTOM_EMPTY := 100   # no clips yet: the scene row + the CLIP hint only (round 7: the empty card row, timeline
							# and play row took a third of the screen for nothing)
var bottom_h := BOTTOM_H   # the bottom panel's height now: _layout_bottom() sets it and moves what sits on it
const TOP_H := 68   # round 9: icon over label (Fusion's ribbon); was 46. tests/icons_test.gd keeps every button inside it
const SETTINGS := "user://poser.cfg"   # what the poser remembers between runs (round 9: the theme)
## where settings are saved: under a test script (godot -s), a file of the test's own, read by nobody at boot, so
## the suites (run in parallel) never read or write Nick's setting, nor each other's (round 9: one did, a layout failed)
var settings := SETTINGS
const AUTOSAVE := "user://autosave.json"   # the unsaved scene, every 15 s (round 16, W1): never in scenes/
var autosave := AUTOSAVE   # a test's own (POSER_AUTOSAVE names one; otherwise per process, removed on exit)
var _as_wait := 0.0
var _as_last := ""

var B := Body.new()
var S := Scene.new()
var parts := {}          # part -> MeshInstance3D (its collision capsule): click target + highlight
var mats := {}
var dots := {}
var skel: Skeleton3D     # the mannequin's skeleton (assets/mannequin.glb, Quaternius UAL2, CC0)
var bone_idx := {}
var bat_handle: MeshInstance3D
var bat_barrel: MeshInstance3D
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
var undo := []
var redo := []

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
var ui_play: Button
var ui_natural: CheckBox
var ui_scene_name: LineEdit
var ui_scenes: OptionButton
var ui_tinted := []    # [label, Tok token]: the labels a theme switch re-tints (round 9)
var ui_say_box: StyleBoxFlat
var ui_bar_box: StyleBoxFlat
var ui_find_box: StyleBoxFlat
var world_env: Environment
var floor_mat: StandardMaterial3D
var grid_mesh: ImmediateMesh
var scene_path := ""   # the open scene's file ("" = never saved)
var ui_help: PanelContainer
var ui_cmd: CommandSearch
var ui_cube: ViewCube
var ui_browser: Browser
const RIBBON := ["POSE", "ANIMATE", "CHECK", "VIEW"]
const RIBBON_TIPS := {"POSE": "reset, relax, mirror, collision", "ANIMATE": "trail, onion, spacing, speed graph, stepped, holds",
	"CHECK": "grade the motion, polish, fix, the dummy", "VIEW": "front / sides / top / back, big view (or the cube, or keys 1-5)"}
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
# THE TARGET DUMMY (Nick 10-13): a second mannequin out front; red where the weapon is in it (scripts/dummy.gd)
var T := Dummy.new()
var ov := Overlays.new()    # motion trail (T) and onion skin (O): scripts/overlays.gd
var ui_tween: HSlider
var ui_hist: PanelContainer        # UNDO HISTORY (round 11, #75)
var ui_hist_list: VBoxContainer
var ui_hist_btn: Button
var _step_hint := ""   # what the user just pressed (a button's text, a command's name, a shortcut's command): the undo
                       # step's name when nothing is said about it (#75)
const KEY_WORD := {KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_COMMA: ",", KEY_PERIOD: ".", KEY_MINUS: "-", KEY_EQUAL: "="}
var _previews := {}   # finding -> the cards its fix would write (Fixer.propose), for the hover ghost; cleared each Check
var _pv_job := {}     # the preview being worked out off the main thread: {f, task, scene, out} (a fix can take seconds)
var _pv_hover := {}   # the finding whose Fix button the mouse is on ({} = none)
var _pv_gen := 0      # bumped by every Check: a job started before it is stale
var ui_pole_row: HBoxContainer   # "points": swing the elbow / knee, the hand / foot held (round 10, GATES Q5)
var ui_ease: OptionButton   # the picked card's ease preset (round 10, GATES Q2)
var ui_spline: CheckBox
var ui_loop: CheckBox
var _tween_armed := false   # one undo step per drag of the tween slider
var stepped_view := false   # STEPPED preview (blocking): the scene plays card to card with no in-betweens; never saved
var ui_bp: PanelContainer   # the bottom panel (the scene)
var ui_card_row: ScrollContainer
var ui_play_row: HBoxContainer
var ui_graph: Control       # SPEED GRAPH: tip / hips / head speed over the scene, cards marked, click to scrub
var ui_tools: MenuButton
var ui_timeline: Timeline
## PULLING a hand / foot (or the locked bat's hand): the point the mouse has dragged it to, kept for the whole drag.
## Each move reaches for THIS point; before, it reached for "where the hand is + this move", so whatever the limb
## could not follow (end of reach, the body in the way) was lost: mouse back where it grabbed, the left hand ended
## 516 mm away, a foot 673 (tests/hand_drag_test.gd). NAN = not set (a new drag sets it on its first move)
var _grab := Vector3(NAN, NAN, NAN)   # the scene as one strip: drag edges to retime, click a block to pick it (scripts/timeline.gd)    # "Animator tools": the round-5 tools in one menu (the bottom row is full)
var _sm := {}   # the sample the last Check took of S (a Fix re-uses it instead of re-playing the scene)
var _fixing := false
var ui_find: PanelContainer   # CHECK: the rulebook's findings (scripts/rulebook.gd), each one a button to its moment
var ui_find_list: VBoxContainer
var findings := []
const DetailTool := preload("res://tools/detail.gd")
var dummy_on := true
var dummy_node: Node3D
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


func _input(ev: InputEvent) -> void:
	# Esc in keyboard mode: before the focused control sees it (a text box would only drop its caret)
	if kb_nav and ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_kb_leave()
		get_viewport().set_input_as_handled()


## a control's name, once its text is set (it is added first, labelled right after)
func _name_later(n: Node) -> void:
	Names.give(n)


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
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var testing: bool = Engine.get_main_loop().get_script() != null
	if testing:
		settings = "user://poser_test_%d.cfg" % OS.get_process_id()
		autosave = "user://autosave_test_%d.json" % OS.get_process_id()
	if OS.get_environment("POSER_AUTOSAVE") != "":
		autosave = OS.get_environment("POSER_AUTOSAVE")
	var cf := ConfigFile.new()
	var light: bool = cf.load(settings) == OK and not testing and cf.get_value("look", "light", false)
	if OS.get_cmdline_user_args().has("--light") or OS.get_cmdline_user_args().has("--dark"):   # shots and tests choose
		light = OS.get_cmdline_user_args().has("--light")
	Tok.set_dark(not light)
	var pct: int = int(cf.get_value("look", "scale", 100)) if not testing else 100
	var si := OS.get_cmdline_user_args().find("--scale")   # shots and tests choose
	if si >= 0 and si + 1 < OS.get_cmdline_user_args().size():
		pct = int(OS.get_cmdline_user_args()[si + 1])
	ui_scale = pct if pct in SCALES else 100
	while not scale_fits(ui_scale):   # remembered from a bigger screen: the largest that fits this one
		ui_scale = SCALES[SCALES.find(ui_scale) - 1]
	get_window().content_scale_factor = ui_scale / 100.0
	# the smallest window the layout is made for (round 21, GATES BB1): at 1024 x 768 the scene row and the play row ran
	# off the right and the view was ~390 px between the side panels; Windows now stops a drag below it
	get_window().min_size = Vector2i(MIN_ROOM)
	get_viewport().size_changed.connect(func(): _fit_rows.call_deferred(); _fit_top.call_deferred())
	_world()
	_body()
	add_child(ov)
	ov.setup()
	_ui()
	_fit_rows.call_deferred()
	# not on a scripted shot either (round 13: an agent's screenshot came back with the tour card over the body)
	if (not testing and not OS.get_cmdline_user_args().has("--shot") and _tour_due()) or OS.get_cmdline_user_args().has("--tour"):
		_tour_start.call_deferred()   # FIRST-RUN TOUR: until it is done or skipped once, or asked for
	var args := OS.get_cmdline_user_args()
	if not args.has("--shot") and (not testing or OS.get_environment("POSER_AUTOSAVE") != ""):
		_recover_offer.call_deferred()
	ov.trail_on = args.has("--trail")
	var pi := args.find("--pin")   # --pin foot_l,head: trails on those parts (shots and checks)
	if pi >= 0 and pi + 1 < args.size():
		for j in args[pi + 1].split(","):
			ov.toggle_pin(j)
	ov.onion_on = args.has("--onion")
	ov.spacing_on = args.has("--spacing")
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
		for n in ["Copy right side to left", "Mirror the whole pose", "Arms down 25 deg"]:
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
	if i >= 0 and i + 1 < args.size():
		# --record <dir> [--fps N]: play the scene and save every frame (frame_0000.png ...), then quit
		var dir: String = args[i + 1]
		var fps := 24
		var k := args.find("--fps")
		if k >= 0 and k + 1 < args.size():
			fps = int(args[k + 1])
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
		var n := int(ceil(_ps().length() * fps))
		for f in n + 1:
			playhead = float(f) / fps
			_ps().apply(B, playhead)
			_refresh()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/frame_%04d.png" % [dir, f])
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
	# quitting with nothing unsaved: no autosave to offer next time. A test's own per-process file always goes
	if not _unsaved() or (autosave != AUTOSAVE and OS.get_environment("POSER_AUTOSAVE") == ""):
		_autosave_drop()


func _process(dt: float) -> void:
	_keys_camera(dt)
	_tour_poll()
	_step_hint = ""   # a press that pushed no step must not name a later one
	_pv_poll()
	_dm_poll()
	_kb_poll()
	_as_wait += dt
	if _as_wait >= 15.0:
		_as_wait = 0.0
		autosave_now()
	if ui_bar != null:
		var bt := bar_text()
		if bt != ui_bar.text:   # rebuilt every frame, written only when it differs: no edit path can leave it stale
			ui_bar.text = bt
	if playing and not S.cards.is_empty():
		playhead += dt
		if playhead > _ps().length():
			playhead = 0.0
		_ps().apply(B, playhead)
		_refresh()


# ---------------------------------------------------------------- 3D scene

func _world() -> void:
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
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-30, 200, 0)
	back.light_energy = 0.45
	add_child(back)
	var im := ImmediateMesh.new()
	var gm := MeshInstance3D.new()
	gm.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	gm.material_override = m
	grid_mesh = im
	_grid()
	add_child(gm)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4, 4)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Tok.c("floor")
	floor_mat = fm
	floor.material_override = fm
	floor.position.y = -0.002
	add_child(floor)
	for lab in [["his left", Vector3(0.68, 0.01, 0), Color(0.9, 0.4, 0.4)], ["he faces this way", Vector3(0, 0.01, 0.7), Color(0.4, 0.6, 1.0)]]:
		var l := Label3D.new()
		l.text = lab[0]
		l.position = lab[1]
		l.modulate = lab[2]
		l.pixel_size = 0.0018
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	_cam()


func _body() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.72, 0.64)
	skin.roughness = 0.55
	var mq := Overlays.mannequin(self, skin)
	skel = mq[1]
	bone_idx = mq[2]
	for j in Body.ORDER + Body.WEAPON:
		var mi := MeshInstance3D.new()
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
		if not j in Body.BODY:
			continue
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.011
		sm.height = 0.022
		d.mesh = sm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.15, 0.15, 0.18)
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
	tag = Label3D.new()
	tag.pixel_size = 0.0009
	tag.fixed_size = true
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = Color(0.55, 0.78, 1.0)
	tag.outline_size = 8
	tag.font_size = 30
	add_child(tag)
	_dummy_build()


## the floor grid in the theme's colours (a theme switch rebuilds it; the two axis lines are content)
func _grid() -> void:
	grid_mesh.clear_surfaces()
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in range(-20, 21):
		var x := k * 0.1
		var c := Tok.c("grid_major") if k % 10 == 0 else Tok.c("grid")
		for seg in [[Vector3(x, 0, -2), Vector3(x, 0, 2)], [Vector3(-2, 0, x), Vector3(2, 0, x)]]:
			grid_mesh.surface_set_color(c)
			grid_mesh.surface_add_vertex(seg[0])
			grid_mesh.surface_set_color(c)
			grid_mesh.surface_add_vertex(seg[1])
	for ax in [[Vector3(0.6, 0.001, 0), Color(0.9, 0.3, 0.3)], [Vector3(0, 0.001, 0.6), Color(0.3, 0.5, 0.95)]]:
		grid_mesh.surface_set_color(ax[1])
		grid_mesh.surface_add_vertex(Vector3(0, 0.001, 0))
		grid_mesh.surface_set_color(ax[1])
		grid_mesh.surface_add_vertex(ax[0])
	grid_mesh.surface_end()


## the dummy: the same mannequin, blue-grey, standing (T.D), turned to face the hero
func _dummy_build() -> void:
	dummy_mat = StandardMaterial3D.new()
	dummy_mat.albedo_color = Color(0.45, 0.5, 0.58)
	dummy_mat.roughness = 0.7
	var dq := Overlays.mannequin(self, dummy_mat)
	dummy_node = dq[0]
	Overlays.pose_skeleton(dq[1], dq[2], T.D)
	hit_tag = Label3D.new()
	hit_tag.pixel_size = 0.0009
	hit_tag.fixed_size = true
	hit_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hit_tag.no_depth_test = true
	hit_tag.modulate = Color(1.0, 0.45, 0.35)
	hit_tag.outline_size = 10
	hit_tag.font_size = 34
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
		hit_tag.text = "%s  (%.2f m up the weapon)" % [h["zone"], h["u"]]


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
	if not dummy_on:
		ui_dummy.text = "dummy off"
		return
	if S.cards.size() < 2:
		ui_dummy.text = _dummy_head(T.dist, solid)
		return
	ui_dummy.text = _dummy_head(T.dist, solid) + "\nmeasuring the scene's hits..."
	if _dm_job.is_empty():
		_dm_start()


func _dm_start() -> void:
	var job := {"gen": _dm_gen, "out": {}}
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
		if dummy_on and S.cards.size() >= 2:
			_dm_start()
		return
	ui_dummy.text = job["out"]["txt"]
	SL = job["out"]["SL"]
	if SL != null:
		ov.mark_dirty()   # what plays changed: the trail / speed graph pass follows it
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


## the weapon's radii + materials for its kind
func _wep_look() -> void:
	var hm := bat_handle.mesh as CylinderMesh
	var bm := bat_barrel.mesh as CylinderMesh
	hm.top_radius = B.wep_r_handle
	hm.bottom_radius = B.wep_r_handle
	if B.wep_kind == "staff":
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


## a capsule (or cylinder) from a to b: Godot's meshes run along their local Y
func _place(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float, capsule := true) -> void:
	var d := b - a
	var L := d.length()
	if capsule:
		(mi.mesh as CapsuleMesh).height = maxf(L + 2.0 * r, 2.0 * r + 0.001)
	else:
		(mi.mesh as CylinderMesh).height = maxf(L, 0.001)
	var y := d / L if L > 1e-6 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _refresh() -> void:
	_sym_prev = B.ang.duplicate()
	Overlays.pose_skeleton(skel, bone_idx, B)
	for tg in ui_toggles:
		(tg[0] as Button).set_pressed_no_signal(tg[1].call())
	if ui_browser != null and ui_browser.visible:
		ui_browser.follow()
	var touching := {}
	for pr in B.pairs:
		if not B.wep_on and (pr[0] in Body.WEAPON or pr[1] in Body.WEAPON):
			continue
		if B.depth(pr[0], pr[1]) - float(B.allow.get(pr[0] + "|" + pr[1], 0.0)) > 0.001:
			touching[pr[0]] = true
			touching[pr[1]] = true
	for j in Body.ORDER + Body.WEAPON:
		var c: Array = B.cap(j)
		_place(parts[j], c[0], c[1], B.rad[j])
		if dots.has(j):
			dots[j].position = B.P[j]
		var col := Color(0.62, 0.63, 0.66, 0.25 if show_caps else 0.0)
		if j in Body.ORDER and not B.at_limit(j).is_empty():
			col = Color(LIMIT, 0.45)
		if touching.has(j):
			col = Color(TOUCH, 0.45)
		if j == sel:
			col = Color(SEL.lerp(col, 0.4) if col.a > 0.3 else SEL, 0.35)
		if clean:
			col.a = 0.0
		mats[j].albedo_color = col
		parts[j].visible = col.a > 0.0 and (B.wep_on or not j in Body.WEAPON)
	for m in [bat_handle, bat_barrel, bat_knob]:
		m.visible = B.wep_on
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
	for d in dots.values():
		d.visible = not clean
	tag.text = nice(sel)
	tag.position = ((c2[0] as Vector3) + (c2[1] as Vector3)) * 0.5 + Vector3(0, 0.1, 0)
	_dummy_refresh()
	if not clean or ov.trail_on or ov.onion_on or not ov.pins.is_empty():
		ov.trail(_ps())
		ov.onion(_ps(), playhead)
	if ov.spacing_on or ov.graph_on:
		ov.trail(_ps())
	ov.spacing(playhead)
	var pulled: String = B.wep_hand if sel in Body.WEAPON else sel
	ov.reach_marker(B.P[pulled] if B.P.has(pulled) else Vector3.ZERO, _grab, dragging == "joint" and not is_nan(_grab.x) and B.P.has(pulled))
	if ui_graph != null:
		ui_graph.visible = ov.graph_on and S.cards.size() >= 2
		ui_graph.queue_redraw()
	_panel()


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
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	cam.transform = Transform3D(b, target + b * Vector3(0, 0, dist))
	var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600, 900)
	var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / vs.y
	if big_view:
		cam.h_offset = 0.0
		cam.v_offset = (bottom_h - TOP_H) * 0.5 * mpp * -1.0
	else:
		cam.h_offset = (RIGHT_W - LEFT_W) * 0.5 * mpp
		cam.v_offset = (bottom_h - TOP_H) * 0.5 * mpp * -1.0


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

func _pick(mp: Vector2) -> String:
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var best := ""
	var best_t := INF
	var cand: Array = Body.ORDER + (Body.WEAPON if B.wep_on else [])
	for j in cand:
		var c: Array = B.cap(j)
		var res := _ray_seg(o, d, c[0], c[1])
		if res.y <= maxf(float(B.rad[j]) * 1.15, 0.014) and res.x < best_t:
			best_t = res.x
			best = j
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
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and ui_cmd.visible:
			ui_cmd.close()   # a click in the view puts the search away
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var j := _pick(mb.position)
				if j != "":
					_push_undo()
					sel = j
					_clicked_part = true   # the tour's step 1 (clicking the part already picked counts too)
					dragging = "joint"
					_grab = Vector3(NAN, NAN, NAN)
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
			# a right CLICK (not a drag) on a part: the ring. The few pixels it wobbled are not a turn: undone
			if was == "orbit" and mb.button_index == MOUSE_BUTTON_RIGHT and not _rpress.is_empty():
				if mb.position.distance_to(_rpress["at"]) < 5.0 and _rpress["part"] != "":
					yaw = _rpress["yaw"]
					pitch = _rpress["pitch"]
					_cam()
					_ring_open(_rpress["part"], mb.position)
				_rpress = {}
			if was == "joint" and not is_nan(_grab.x):
				_grab = Vector3(NAN, NAN, NAN)
				_refresh()   # the reach marker goes with the drag
	elif ev is InputEventMouseMotion and dragging != "":
		var mm := ev as InputEventMouseMotion
		var rel := mm.relative
		if dragging == "orbit":
			yaw -= rel.x * 0.4
			pitch = clampf(pitch - rel.y * 0.4, -89.0, 89.0)
			_cam()
		elif dragging == "pan":
			var k := dist * 0.0012
			target += -cam.global_basis.x * rel.x * k + cam.global_basis.y * rel.y * k
			_cam()
		elif dragging == "joint":
			_drag_joint(rel, mm.shift_pressed, mm.ctrl_pressed, mm.alt_pressed)
	elif ev is InputEventKey and ev.pressed:
		var k := ev as InputEventKey
		if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is SpinBox:
			return
		if k.unicode == 63 and not k.ctrl_pressed:   # "?" by the character typed, on any layout (Nick's ABNT2 too): X2
			keys_overlay(ui_keys == null or not ui_keys.visible)
			return
		if k.keycode == KEY_ESCAPE and ui_keys != null and ui_keys.visible:
			keys_overlay(false)
			return
		var combo: String = ("Ctrl+" if k.ctrl_pressed else "") + ("Shift+" if k.shift_pressed else "") + KEY_WORD.get(k.keycode, OS.get_keycode_string(k.keycode))
		for c in ui_cmd.commands:
			if c["keys"] == combo:
				_step_hint = c["name"]
		if k.ctrl_pressed:
			match k.keycode:
				KEY_Z: _undo()
				KEY_Y: _redo()
				KEY_S: _save_scene() if k.shift_pressed else _save_pose()   # Ctrl+Shift+S = the scene (round 15, V3)
				KEY_C: _copy_pose()
				KEY_V: _paste_pose("mirrored" if k.shift_pressed else "")
			return
		match k.keycode:
			KEY_S:
				ui_cmd.open()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_view(k.keycode - KEY_0)
			KEY_R: _do(func(): _reset_part())
			KEY_Q: _do(func(): _snap(45.0 if k.shift_pressed else 90.0))
			KEY_M when k.shift_pressed: _tool(0)
			KEY_M: _do(func(): B.mirror_side("_r"))
			KEY_N: _do(func(): B.mirror_side("_l"))
			KEY_C:
				show_caps = not show_caps
				_refresh()
			# into the right hand, as its button says ("In right hand (B)"); already there = off (V3: a bat in the LEFT
			# hand used to come off, so B, B to move it)
			KEY_B: _do(func(): _bat_remove() if B.wep_on and B.wep_hand == "hand_r" else _bat_put("hand_r"))
			KEY_L: _do(func(): _bat_lock())
			KEY_F: _do(func(): _fingers_cycle())
			KEY_G: _do(_toggle_second)
			KEY_H: _dummy_toggle()
			KEY_T when k.shift_pressed:
				if not sel in Body.BODY:
					_say("Shift+T pins a trail on a BODY part: click one first (the weapon's own trail is T)")
				else:
					var on := ov.toggle_pin(sel)
					_refresh()
					_say(("trail pinned on %s (its end).  Shift+T again removes it.  %s" % [sel, ov.info]) if on else "trail on %s removed" % sel)
			KEY_T:
				ov.trail_on = not ov.trail_on
				ov.mark_dirty()
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
		B.reach(sel, _grab)
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
	_after_edit()
	var v2: Vector3 = B.ang[sel]
	var what := "ROLLING" if twist else ("MOVING" if (move and sel == "pelvis") else ("SWINGING THE %s OF" % ("ELBOW" if sel.begins_with("hand") else "KNEE") if tip and move else ("PULLING" if tip and not alt else "ROTATING")))
	_say("%s the %s     %s" % [what, nice(sel), _angles_words(sel, v2)])


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
	f.call()
	_after_edit()


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
	_say("posed: %s%s" % [text, ("   (stopped short: %s)" % ", ".join(stopped.map(func(x): return "%s %s %.0f of %.0f" % [nice(x["joint"]), x["axis"], x["reached"], x["asked"]]))) if not stopped.is_empty() else ""])
	return {"ok": true, "ops": rep}


func _after_edit() -> void:
	if symmetry:
		_mirror_changed()
	B.apply_grip()
	_refresh()


## SYMMETRY MODE (round 22, GATES CC1, UPGRADES #65): while on, an edit on one side moves its twin, reflected the way
## Copy side does (bend, side, -twist). Only the joints the edit CHANGED since the last refresh are copied, so dragging
## an arm leaves the legs as they were, and the middle (its own twin) is never touched. Runs inside the edit's own undo
## step: one Ctrl+Z takes back both sides
var symmetry := false
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


func _big_view() -> void:
	big_view = not big_view
	for p in ui_side:
		p.visible = not big_view
	_place_cube()
	_cam()
	_say("big view: the side panels are hidden (Tab brings them back)" if big_view else "panels back")


## an undo step = the body AND the open scene's cards (10-14: a Fix or "+ tween" changes cards, so Ctrl+Z must bring
## them back). The cards come back only into the scene they were taken from: opening another scene makes them stale.
func _snapshot() -> Dictionary:
	return {"body": B.state(), "scene": S, "cards": S.cards.duplicate(true), "sel": sel_card, "holds": S.moving_holds}


func _restore(u: Dictionary) -> void:
	B.set_state(u["body"])   # lossless (round 8): from_dict re-solved from the file's rounded numbers
	if u["scene"] == S and u.get("holds", S.moving_holds) != S.moving_holds:   # a scene setting, undone like a card
		S.moving_holds = u["holds"]
		_rebuild_cards()
	if u["scene"] == S and JSON.stringify(u["cards"]) != JSON.stringify(S.cards):
		S.cards = u["cards"].duplicate(true)
		sel_card = mini(u["sel"], S.cards.size() - 1)
		_rebuild_cards()
		if ui_find != null and ui_find.visible:
			_check()   # the findings were for the cards just put back
	_refresh()


func _push_undo() -> void:
	var u := _snapshot()
	if _step_hint != "":
		u["hint"] = step_name(_step_hint)
	_step_hint = ""
	undo.append(u)
	_history_rows.call_deferred()
	if undo.size() > 60:
		undo.pop_front()
	redo.clear()


func _undo() -> void:
	if undo.is_empty():
		_say("nothing to undo yet: click a part and drag it, and Ctrl+Z will take that back")
		return
	var u: Dictionary = undo.pop_back()
	var now := _snapshot()
	now["name"] = _step_label(u)   # the step keeps its name on the way back and forth
	redo.append(now)
	_restore(u)
	_say("undone: " + now["name"])
	_history_rows()


func _redo() -> void:
	if redo.is_empty():
		return
	var r: Dictionary = redo.pop_back()
	var now := _snapshot()
	now["name"] = _step_label(r)
	undo.append(now)
	_restore(r)
	_say("redone: " + now["name"])
	_history_rows()


func _reset_part() -> void:
	if sel in Body.WEAPON:
		return
	if sel == "pelvis":
		B.offset = Vector3.ZERO
	B.set_ang_safe(sel, Vector3.ZERO)


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
	_say("snapped the %s to %d-degree steps" % [nice(sel), int(step)])


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


func _bat_remove() -> void:
	B.wep_on = false
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
			_say("LOCKED in BOTH hands (the %s holds it, the other hand keeps its grip at %.2f m): they move together. G lets the second hand go" % [nice(h), B.grip_u])
		else:
			_say("LOCKED to the %s: it moves with the hand (the other hand isn't on the shaft%s)" % [nice(h), "" if off < 0.0 else ": %.0f cm off" % (off * 100.0)])


func _fingers(side: String, kind: String) -> void:
	B.hand_shape(side, kind)
	_say("%s hand: %s" % ["left" if side == "l" else "right", kind])


var _shape_i := {"l": 0, "r": 0}
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
		_say("the weapon slid in the hand: hand at %.2f m from the lower end" % B.hold_u())
		return
	if B.slide_hand(d):
		_say("main hand at %.2f m from the lower end%s" % [B.hold_u(), ", the other hand re-gripped" if B.grip else ""])
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
	_say("second hand on the weapon at %.2f m" % B.grip_u)


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
			B.slide_in_hand(-d)
			B.apply_grip()
		n += 1
	_say("main hand at %.2f m from the lower end%s" % [B.hold_u(), "" if B.hold_u() <= 0.1 else " (the arm can't follow further: turn the weapon or the body)"])


func _slide_mode() -> void:
	slide_body = not slide_body
	ui_slide_btn.text = "Slide , . : body follows" if slide_body else "Slide , . : weapon moves"
	_say("now , and . %s" % ("move the hand along the weapon, the weapon stays and the arm follows" if slide_body else "slide the weapon through the hand, the hand stays"))


## switch the weapon kind; if one is in a hand, it goes back in that hand with this kind's grip
func _kind(k: String) -> void:
	var h := B.wep_hand
	B.set_kind(k)
	if B.wep_on and h != "":
		B.weapon_to_hand(h)
	elif not B.wep_on:
		B.weapon_to_hand("hand_r")
	sel = "bat_handle"
	_say({"metal_bat": "metal bat (0.84 m)", "staff": "staff / bo (1.8 m): slide your hand along it with , and .  and put the other hand on with G, [ ]",
		"long_hammer": "long hammer (1.1 m, steel head across the tip): G for both hands, [ ] to slide the other hand"}[k])


# ---------------------------------------------------------------- words

## a plain name for a part: "upperarm_r" -> "right upper arm"
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
			out.append("%s %.0f" % [["swing", "raise/tilt", "roll"][k], v[k]])
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


func _say(t: String) -> void:
	if ui_status != null:
		ui_status.text = t
	# UNDO HISTORY (round 11, #75): the first thing said after a step is pushed names it ("ROTATING the right upper
	# arm", "card 12: the right foot planted"...); its first clause, without the numbers that follow
	if not undo.is_empty() and not undo[-1].has("name") and not t.begins_with("undone") and not t.begins_with("redone"):
		undo[-1]["name"] = step_name(t)
		_history_rows()


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


## the history list: future steps (redo, dimmed) on top, then "now", then the past, newest first. A row = go there
func _history_rows() -> void:
	if ui_hist == null or not ui_hist.visible:
		return
	for c in ui_hist_list.get_children():
		ui_hist_list.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	ui_hist_list.add_child(head)
	var title := _label("HISTORY  -  %d step%s" % [undo.size(), "" if undo.size() == 1 else "s"], 16, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Close", _toggle_history))
	for k in redo.size():   # redo[0] is the farthest future
		var b := _button("   " + _step_label(redo[k]), _history_go.bind(undo.size() + redo.size() - k))
		b.name = "step_%d" % (undo.size() + redo.size() - k)   # U2: the step it goes to
		b.modulate.a = 0.55
		_hist_row(b)
	ui_hist_list.add_child(_label("> now", 14, "heading"))
	for i in range(undo.size() - 1, -1, -1):
		var hb := _button(_step_label(undo[i]), _history_go.bind(i))
		hb.name = "step_%d" % i
		_hist_row(hb)
	if undo.is_empty() and redo.is_empty():
		ui_hist_list.add_child(_label("nothing yet: every change you make shows up here", 13, "text:0.6", true))
	(ui_hist.get_child(0) as ScrollContainer).custom_minimum_size.y = clampf(70.0 + 40.0 * (undo.size() + redo.size()), 110.0, 420.0)
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


## go to the state with `n` steps done (undo / redo one at a time, so the stacks stay exactly as Ctrl+Z / Ctrl+Y leave them)
func _history_go(n: int) -> void:
	while undo.size() > n:
		_undo()
	while undo.size() < n and not redo.is_empty():
		_redo()
	_say("history: %d step%s done" % [undo.size(), "" if undo.size() == 1 else "s"])


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
	var bar: StyleBoxFlat = box.call(Tok.c("panel"), 0, 4)
	bar.content_margin_left = 10
	bar.content_margin_right = 10
	th.set_stylebox("panel", "TopBar", bar)
	# a ribbon button: the button's look with thin top/bottom margins (icon over label is two rows tall)
	th.set_type_variation("Ribbon", "Button")
	for st in [["normal", "btn"], ["hover", "btn_hover"], ["pressed", "accent"]]:
		var rb: StyleBoxFlat = box.call(Tok.c(st[1]), 6, 6)
		rb.content_margin_top = 2
		rb.content_margin_bottom = 2
		th.set_stylebox(st[0], "Ribbon", rb)
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
var ui_tour: PanelContainer


## not done or skipped yet (the settings remember it)
func _tour_due() -> bool:
	var cf := ConfigFile.new()
	cf.load(settings)
	return not cf.get_value("look", "tour_done", false)


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
	_tour_at = {"sel": sel, "body": JSON.stringify(B.state()), "cards": S.cards.size()}
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
	if did:
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


func _set_scale(pct: int) -> void:
	if not scale_fits(pct):
		_say("UI size %d %% needs a window of at least %d x %d (this one is %d x %d): make the window bigger (maximise it), then choose it again" % [pct, MIN_ROOM.x * pct / 100, MIN_ROOM.y * pct / 100, get_window().size.x, get_window().size.y])
		return
	ui_scale = pct
	get_window().content_scale_factor = pct / 100.0
	var cf := ConfigFile.new()
	cf.load(settings)
	cf.set_value("look", "scale", pct)
	cf.save(settings)
	_fit_rows.call_deferred()
	_fit_top.call_deferred()
	_say("UI size %d %%" % pct)


func _set_light(on: bool) -> void:
	Tok.set_dark(not on)
	_retheme()
	var cf := ConfigFile.new()
	cf.load(settings)
	cf.set_value("look", "light", on)
	cf.save(settings)
	_say("light theme (VIEW > Light again for dark)" if on else "dark theme")


## everything built with the old palette takes the new one
func _retheme() -> void:
	ui_root.theme = _theme()
	ui_tinted = ui_tinted.filter(func(x): return is_instance_valid(x[0]))
	for x in ui_tinted:
		(x[0] as Label).add_theme_color_override("font_color", Tok.of(x[1]))
	for t in ui_ribbon_tabs:
		(ui_ribbon_tabs[t] as Button).add_theme_color_override("font_pressed_color", Tok.c("heading") if Tok.dark else Tok.c("on_accent"))
	ui_say_box.bg_color = Tok.c("say_bg")
	ui_bar_box.bg_color = Tok.c("panel")
	ui_find_box.bg_color = Tok.c("float")
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
const ICON_OF := {"Reset body": "reset", "Arms 25 deg": "arms", "Mirror pose (Shift+M)": "mirror", "Symmetry": "symmetry", "Collision (C)": "collision",
	"Trail (T)": "trail", "Onion (O)": "onion", "Spacing (Shift+O)": "spacing", "Speed graph (Y)": "graph", "Stepped": "stepped",
	"Moving holds": "holds", "Animator tools": "tools", "Check": "check", "Polish": "polish", "Fix moves through the body": "fix",
	"Dummy (H)": "dummy", "Front (1)": "front", "His right (2)": "right", "Top (3)": "top", "Back (4)": "back", "His left (5)": "left",
	"Big view (Tab)": "big", "Light": "light", "UI size": "size", "Undo (Ctrl+Z)": "undo", "Redo (Ctrl+Y)": "redo", "History": "history", "Search (S)": "search", "? Help": "help"}


## icon over a small label, Fusion's ribbon look; the theme tints the (white) icon
## HOVER HINTS (round 11, #85): every ribbon / top-bar button says what it does in the status line while the mouse is
## on it. The words: its tooltip; else the registry command it is (same name, its shortcut in "(X)", or a name that
## starts with it). Leaving puts the normal bar back (bar_text reads _hover_hint first)
var _hover_hint := ""


func _hover_hints() -> void:
	for b in ui_root.find_children("*", "BaseButton", true, false):
		if not (b is Button) or not ICON_OF.has((b as Button).text):
			continue
		var t: String = b.text
		if b.tooltip_text == "":
			var key := t.get_slice("(", 1).trim_suffix(")") if t.contains("(") else "~"
			for c in ui_cmd.commands:
				if c["name"] == t or c["keys"] == key or (c["name"] as String).begins_with(t):
					b.tooltip_text = c["desc"]
					break
		b.mouse_entered.connect(func(): _hover_hint = "%s:  %s" % [t, b.tooltip_text])
		b.mouse_exited.connect(func(): _hover_hint = "")


func _iconise(b: Node) -> void:
	if not (b is Button) or not ICON_OF.has(b.text):
		return
	b.icon = Icons.tex(ICON_OF[b.text])
	b.theme_type_variation = "Ribbon"
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_constant_override("h_separation", 2)


## DISABLED SAYS WHY (round 22, GATES CC3, UPGRADES #46): a control greyed out keeps its own tooltip and adds the
## reason and what to do after GREY_TAG (one place, so every greyed control reads the same way); why "" = enabled
const GREY_TAG := "
NOT NOW: "


func _grey(c: Control, why: String) -> void:
	var base: String = c.tooltip_text.get_slice(GREY_TAG, 0)
	c.set("disabled", why != "")
	c.tooltip_text = base + (GREY_TAG + why if why != "" else "")


func _button(t: String, f: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(func(): _step_hint = t)   # first: an undo step pushed by f is named after the button
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


func _section(parent: Control, t: String) -> void:
	var s := HSeparator.new()
	parent.add_child(s)
	parent.add_child(_label(t, 15, "heading"))


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
	ui_root.add_child(top)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 6)
	top.add_child(tb)
	tb.add_child(_label("POSER  ", 20, "heading"))
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
		tbtn.add_theme_font_size_override("font_size", 15)
		tbtn.add_theme_color_override("font_pressed_color", Tok.c("heading") if Tok.dark else Tok.c("on_accent"))
		ui_ribbon_tabs[t] = tbtn
		tb.add_child(tbtn)
		var tools := HBoxContainer.new()
		tools.add_theme_constant_override("separation", 6)
		tools.name = "ribbon_" + t.to_lower()
		ui_ribbon[t] = tools
	tb.add_child(VSeparator.new())
	for t in RIBBON:
		tb.add_child(ui_ribbon[t])
	var tog := func(tab: String, label: String, f: Callable, on: Callable, tip := ""):
		var b := _button(label, f, tip)
		b.toggle_mode = true
		ui_toggles.append([b, on])
		ui_ribbon[tab].add_child(b)
	# POSE
	ui_ribbon["POSE"].add_child(_button("Reset body", _do.bind(_reset_all)))
	ui_ribbon["POSE"].add_child(_button("Arms 25 deg", _do.bind(_arms_relaxed), "both arms relaxed: 25 degrees out from straight down"))
	ui_ribbon["POSE"].add_child(_button("Mirror pose (Shift+M)", _tool.bind(0), "the whole body left <-> right (the weapon changes hands)"))
	tog.call("POSE", "Symmetry", _toggle_symmetry, func(): return symmetry,
		"while on, dragging a part on one side moves the same part on the other side, reflected (the middle stays)")
	tog.call("POSE", "Collision (C)", func(): show_caps = not show_caps; _refresh(), func(): return show_caps,
		"see the capsules the body collides with. Yellow = a joint at its limit, red = touching another part")
	# ANIMATE
	tog.call("ANIMATE", "Trail (T)", _press.bind(KEY_T), func(): return ov.trail_on, "the weapon tip's path, one dot per frame, blue slow to red fast")
	tog.call("ANIMATE", "Onion (O)", _press.bind(KEY_O), func(): return ov.onion_on, "the card before (orange) and after (green) as ghosts")
	tog.call("ANIMATE", "Spacing (Shift+O)", _tool.bind(1), func(): return ov.spacing_on, "arms + weapon every 0.1 s around the playhead: bunched = slow")
	tog.call("ANIMATE", "Speed graph (Y)", _tool.bind(2), func(): return ov.graph_on)
	tog.call("ANIMATE", "Stepped", _tool.bind(3), func(): return stepped_view, "poses only, no in-betweens (blocking)")
	tog.call("ANIMATE", "Moving holds", _tool.bind(4), func(): return S.moving_holds, "a held pose keeps drifting slightly toward the next")
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
	# CHECK
	ui_ribbon["CHECK"].add_child(_button("Check", _check, "grade the scene against real recorded human motion; click a problem to jump to it"))
	ui_ribbon["CHECK"].add_child(_button("Polish", _polish, "smooth the scene and add the in-between detail into a NEW scene; yours is not touched"))
	ui_ribbon["CHECK"].add_child(_button("Fix moves through the body", _clear_scene))
	tog.call("CHECK", "Dummy (H)", _dummy_toggle, func(): return dummy_on, "a second mannequin out front: red where the weapon is in it")
	# VIEW
	for v in [["Front (1)", 1], ["His right (2)", 2], ["Top (3)", 3], ["Back (4)", 4], ["His left (5)", 5]]:
		ui_ribbon["VIEW"].add_child(_button(v[0], _view.bind(v[1])))
	ui_ribbon["VIEW"].add_child(_button("Big view (Tab)", _big_view, "hide the side panels so the body fills the screen"))
	tog.call("VIEW", "Light", func(): _set_light(Tok.dark), func(): return not Tok.dark, "light or dark theme (remembered)")
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
			us.get_popup().set_item_tooltip(k, "" if scale_fits(SCALES[k]) else GREY_TAG.strip_edges() + " %d %% needs a window of at least %d x %d: make the window bigger (maximise it)" % [SCALES[k], MIN_ROOM.x * SCALES[k] / 100, MIN_ROOM.y * SCALES[k] / 100])
			us.get_popup().set_item_text(k, "%d %%" % SCALES[k] + ("" if scale_fits(SCALES[k]) else "   (needs a bigger window)")))
	ui_ribbon["VIEW"].add_child(us)
	# always there
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(fill)
	tb.add_child(_button("Undo (Ctrl+Z)", _undo))
	ui_hist_btn = _button("History", _toggle_history, "every change by name, newest on top: click one to go back (or forward) to exactly there")
	tb.add_child(_button("Redo (Ctrl+Y)", _redo))
	tb.add_child(ui_hist_btn)
	tb.add_child(_button("Search (S)", func(): ui_cmd.open(), "type a few letters of any command: mirror, trail, check, staff...  Enter runs it"))
	tb.add_child(_button("? Help", func(): ui_help.visible = not ui_help.visible, "every key and mouse move, on one page"))
	for t in RIBBON:
		for b in ui_ribbon[t].get_children():
			_iconise(b)
	for b in tb.get_children().slice(tb.get_children().find(fill)):
		_iconise(b)
	ui_tb = tb
	ui_top_right = tb.get_children().slice(tb.get_children().find(fill) + 1)
	ui_more = MenuButton.new()
	ui_more.name = "b_more_tools"
	ui_more.text = "More"
	ui_more.tooltip_text = "the tab's tools that do not fit this window"
	ui_more.flat = false
	ui_more.visible = false
	ui_more.get_popup().id_pressed.connect(_more_pick)
	tb.add_child(ui_more)
	tb.move_child(ui_more, tb.get_children().find(fill))
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
	# Nick 10-13 "we can't see individual poses": the buttons below the list had squeezed it to nothing. The panel
	# scrolls now and the list keeps its own height
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# round 7: two tabs, Poses (as it was, the first) and Browser (Fusion's tree: every part by name, the clips)
	var ltabs := TabContainer.new()
	ltabs.focus_mode = Control.FOCUS_NONE
	lp.add_child(ltabs)
	lsc.name = "Poses"
	ltabs.add_child(lsc)
	ui_browser = Browser.new()
	ui_browser.m = self
	ui_browser.name = "Browser"
	ltabs.add_child(ui_browser)
	ltabs.tab_changed.connect(func(_t): ui_browser.refresh())   # it does not follow while hidden: catch up on show
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(lv)
	lv.add_child(_label("1  POSES", 19, "heading"))
	lv.add_child(_label("Click a pose: the body takes it.", 14, "text:0.65", true))
	ui_poses = ItemList.new()
	ui_poses.custom_minimum_size = Vector2(0, 240)
	ui_poses.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_poses.focus_mode = Control.FOCUS_NONE
	ui_poses.item_selected.connect(func(i):
		_push_undo()
		_load_pose(ui_poses.get_item_metadata(i))
		_refresh()
		_say("the body is now in pose '%s'" % ui_poses.get_item_text(i)))
	lv.add_child(ui_poses)
	ui_pose_name = LineEdit.new()
	ui_pose_name.placeholder_text = "name for the body's pose"
	lv.add_child(ui_pose_name)
	_row(lv, [_button("Save pose", _save_pose, "save the body as a pose (Ctrl+S)"),
		_button("Rename", _rename_pose, "click one of YOUR poses in the list, type the new name above, press Rename")])
	_row(lv, [_button("Delete pose", _delete_pose, "click a pose in the list, then Delete (it asks first; the file goes to the trash folder)")])
	_row(lv, [_button("CLIP this pose  (Enter)", _card_add, "the body as it is now becomes the next clip in the scene below")])
	lv.add_child(_label("WEAPON  (in the right hand)", 14, "heading"))
	_row(lv, [_button("Bat", _do.bind(_kind.bind("metal_bat")), "metal bat 0.84 m"), _button("Bo staff", _do.bind(_kind.bind("staff")), "staff 1.8 m")])
	_row(lv, [_button("Hammer", _do.bind(_kind.bind("long_hammer")), "long hammer 1.1 m"), _button("None", _do.bind(_bat_remove), "remove the weapon")])
	_row(lv, [_button("2nd hand on/off (G)", _do.bind(_toggle_second), "the other hand on the shaft; [ ] slide it")])
	ui_slide_btn = _button("Slide , . : body follows", _slide_mode, "an option, not a rule: , . either move the hand along a weapon that stays put (the arm follows), or slide the weapon through a hand that stays put")
	_row(lv, [ui_slide_btn])
	_row(lv, [_button("Hand to the end", _do.bind(_hand_to_end), "Nick 10-13: a long weapon swings from its end - the main hand slides to the lower end in 3 cm steps (the body follows, or the weapon moves: the toggle above)")])
	lv.add_child(_label("TARGET DUMMY  (H)", 14, "dummy"))
	_row(lv, [_button("On/off", _dummy_toggle, "a second mannequin out front: it turns red where the weapon is in it (H)"),
		_button("Closer", _dummy_move.bind(-0.25), "the dummy 25 cm closer"), _button("Farther", _dummy_move.bind(0.25), "the dummy 25 cm farther")])
	_row(lv, [_button("Solid / see-through", _dummy_solid, "solid: the swing stops on the dummy and rebounds (the scene plays as landed); see-through: the scene as you made it")])
	ui_dummy = _label("dummy %.2f m out" % T.dist, 13, "dummy_text", true)
	lv.add_child(ui_dummy)

	# ---- right: the selected part
	var rp := PanelContainer.new()
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.offset_left = -RIGHT_W
	rp.offset_right = -6
	rp.offset_top = TOP_H + 6
	rp.anchor_bottom = 1.0
	rp.offset_bottom = -BOTTOM_H - 6
	ui_root.add_child(rp)
	ui_side.append(rp)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS   # Nick 10-13 couldn't find the weapon rows below
	rp.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.custom_minimum_size = Vector2(RIGHT_W - 34, 0)
	vb.add_theme_constant_override("separation", 5)
	sc.add_child(vb)
	vb.add_child(_label("2  SELECTED PART  (click the body)", 15, "heading"))
	ui_title = _label("", 22, "text", true)
	vb.add_child(ui_title)
	ui_how = _label("", 14, "info", true)
	vb.add_child(ui_how)
	for k in ["bend", "side", "twist"]:
		var box := VBoxContainer.new()
		var l := _label("", 15, "text", true)
		box.add_child(l)
		var s := HSlider.new()
		s.step = 0.5
		s.custom_minimum_size = Vector2(0, 24)
		s.drag_started.connect(_push_undo)
		s.value_changed.connect(_on_slider.bind(k))
		box.add_child(s)
		vb.add_child(box)
		ui_rows[k] = {"slider": s, "label": l, "box": box}
	ui_hip_box = VBoxContainer.new()
	vb.add_child(ui_hip_box)
	for k in 3:
		var l := _label("", 15, "text", true)
		ui_hip_box.add_child(l)
		var s := HSlider.new()
		s.step = 0.005
		s.custom_minimum_size = Vector2(0, 24)
		s.drag_started.connect(_push_undo)
		s.value_changed.connect(_on_hip.bind(k))
		ui_hip_box.add_child(s)
		ui_hips.append([s, l])
	_row(vb, [_button("Reset (R)", _do.bind(_reset_part)), _button("90 (Q)", _do.bind(_snap.bind(90.0))),
		_button("45", _do.bind(_snap.bind(45.0)))])
	ui_pole_row = _row(vb, [_label("points", 15), _button("<", _do.bind(_pole.bind(-15.0)), "swing the elbow / knee 15 deg one way; the hand / foot stays (Ctrl+drag does it by hand)"),
		_button(">", _do.bind(_pole.bind(15.0)), "swing the elbow / knee 15 deg the other way; the hand / foot stays (Ctrl+drag does it by hand)")])
	_row(vb, [_button("Right to left (M)", _do.bind(B.mirror_side.bind("_r"))),
		_button("Left to right (N)", _do.bind(B.mirror_side.bind("_l")))])
	_section(vb, "HANDS")
	var frow := _row(vb, [_label("right:", 15), _button("Open", _do.bind(_fingers.bind("r", "open"))), _button("Grip", _do.bind(_fingers.bind("r", "grip"))),
		_button("Fist", _do.bind(_fingers.bind("r", "fist")))])
	frow.name = "fingers_r"
	frow = _row(vb, [_label("left:  ", 15), _button("Open", _do.bind(_fingers.bind("l", "open"))), _button("Grip", _do.bind(_fingers.bind("l", "grip"))),
		_button("Fist", _do.bind(_fingers.bind("l", "fist")))])
	frow.name = "fingers_l"
	vb.add_child(_label("Fingers one by one: click a finger on the body (zoom in with the wheel).", 13, "text:0.55", true))
	_section(vb, "WEAPON")
	_row(vb, [_button("Metal bat", _do.bind(_kind.bind("metal_bat"))), _button("Staff (bo)", _do.bind(_kind.bind("staff"))),
		_button("Long hammer", _do.bind(_kind.bind("long_hammer")))])
	_row(vb, [_button("In right hand (B)", _do.bind(_bat_put.bind("hand_r"))), _button("In left hand", _do.bind(_bat_put.bind("hand_l")))])
	_row(vb, [_button("Main hand down (,)", _do.bind(_slide.bind(-0.03)), "the hand slides toward the lower end; the weapon stays, the arm follows"),
		_button("Main hand up (.)", _do.bind(_slide.bind(0.03)), "the hand slides toward the tip; the weapon stays, the arm follows")])
	_row(vb, [_button("Lock bat to hand / Free it (L)", _do.bind(_bat_lock)), _button("Remove bat", _do.bind(_bat_remove))])
	_row(vb, [_button("Other hand on the bat (G)", _do.bind(func(): B.grip = not B.grip)),
		_button("Save grip as standard", _save_grip, "the bat's place in the hand + the fingers become the grip 'Bat in hand' uses")])
	vb.add_child(_label("[ ] slide the other hand along the shaft,  , . slide the main hand,  - = change the length", 13, "text:0.55", true))
	_section(vb, "NUMBERS")
	ui_math_btn = _button("Show the math (for Claude)", func(): ui_math.visible = not ui_math.visible)
	vb.add_child(ui_math_btn)
	ui_math = _label("", 12, "text:0.6", true)
	ui_math.visible = false
	vb.add_child(ui_math)

	# ---- bottom: the scene
	var bp := PanelContainer.new()
	ui_bp = bp
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
	bh.add_theme_constant_override("separation", 6)
	bv.add_child(bh)
	bh.add_child(_label("3  SCENE  (clips)", 19, "heading"))
	var intro := _label("your clips in a row; Play and the body moves from clip to clip on its own", 14, "text:0.6")
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
	ui_scenes.item_selected.connect(_scene_picked)   # V3: picking a scene opens it (asks first if this one has unsaved changes)
	bh.add_child(ui_scenes)
	bh.add_child(_button("Open scene", func():
		if ui_scenes.selected >= 0:
			_load_scene(ui_scenes.get_item_metadata(ui_scenes.selected))
			_rebuild_cards()
			_refresh()))
	bh.add_child(_button("Delete scene", _delete_scene, "the scene picked in the list (it asks first; the file goes to the trash folder)"))
	ui_loop = CheckBox.new()
	ui_loop.text = "Loop"
	ui_loop.name = "check_loop"
	ui_loop.focus_mode = Control.FOCUS_NONE
	ui_loop.tooltip_text = "ON: the scene plays round and round (a walk, an idle). CHECK then grades the seam: the end must meet the start."
	ui_loop.toggled.connect(func(on): _push_undo(); S.loop = on; check_ran = false; _refresh())
	bh.add_child(ui_loop)   # a property of the scene FILE: with its buttons (the play row has no room at 100 %)
	bh.add_child(_button("New empty scene", _new_scene))
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
		_refresh())
	ui_timeline.picked.connect(_timeline_pick)
	ui_timeline.retime_started.connect(_push_undo)
	ui_timeline.retimed.connect(func(final: bool):
		if final:
			_retimed()
		else:
			S.apply(B, minf(playhead, S.length()))   # live while dragging: the scene as made (the landed copy is rebuilt on release)
			_refresh())
	bv.add_child(ui_timeline)
	var ph := HBoxContainer.new()
	ui_play_row = ph
	ph.name = "play_row"
	ph.add_theme_constant_override("separation", 8)
	bv.add_child(ph)
	ui_play = _button("  Play (Space)  ", _toggle_play)
	ph.add_child(ui_play)
	ph.add_child(_button("Slower", _speed.bind(1.1), "10% slower: the picked card, or the whole scene with no card picked (Save scene keeps it)"))
	ph.add_child(_button("Faster", _speed.bind(1.0 / 1.1), "10% faster: the picked card, or the whole scene with no card picked (Save scene keeps it)"))
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
	ui_time_lbl = _label("0.00 s", 15)
	ui_time_lbl.custom_minimum_size = Vector2(130, 0)
	ph.add_child(ui_time_lbl)
	ui_natural = CheckBox.new()
	ui_natural.text = "Natural movement"
	ui_natural.button_pressed = true
	ui_natural.focus_mode = Control.FOCUS_NONE
	ui_natural.tooltip_text = "ON: the hips start first and the hands arrive last, like a real body. OFF: everything moves together."
	ui_natural.toggled.connect(func(on): S.natural = on; _dummy_hits(); _ps().apply(B, playhead); _refresh())
	ph.add_child(ui_natural)
	ui_spline = CheckBox.new()
	ui_spline.text = "Smooth (spline)"
	ui_spline.focus_mode = Control.FOCUS_NONE
	ui_spline.tooltip_text = "ON: one smooth curve through every card; only cards with a hold stop. OFF: the body eases to a stop at every card."
	ui_spline.toggled.connect(func(on): S.spline = on; _rebuild_cards(); _ps().apply(B, playhead); _refresh())
	ph.add_child(ui_spline)
	ph.add_child(_label("tween", 14, "text:0.75"))
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
	ph.add_child(ui_tween)
	ph.add_child(_button("+ tween", _tween_add, "add an in-between card after the picked one, halfway to the next (then slide 'tween')"))
	ph.add_child(_label("ease", 14, "text:0.75"))
	ui_ease = OptionButton.new()
	ui_ease.name = "opt_ease"
	ui_ease.focus_mode = Control.FOCUS_NONE
	for e in Scene.EASES:
		ui_ease.add_item(e)
	ui_ease.tooltip_text = "how the move INTO the picked card eases: smooth (natural), linear, in (starts slow), out (ends slow), snap (holds, then jumps: a hit, a cut)"
	ui_ease.item_selected.connect(func(k): if not _sync: _set_ease(Scene.EASES[k]))
	ph.add_child(ui_ease)
	ui_play_extra = [_button("Check", _check, "grade the scene against real recorded human motion (docs/MOTION_RULES.md); click a problem to jump to it"),
		_button("Polish", _polish, "smooth the scene and add the in-between detail (~30 cards) into a NEW scene; yours is not touched"),
		_button("Fix moves through the body", _clear_scene,
		"where a move between two cards passes an arm or the bat through the body, add a pass-by card that goes around")]
	for b in ui_play_extra:
		ph.add_child(b)

	# ---- status line
	ui_status = _label("Click a body part to select it.  Drag it to rotate.  Click a pose on the left to start from it.", 16, "say", true)
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
	ui_status.add_theme_stylebox_override("normal", sb)
	ui_root.add_child(ui_status)
	# ---- status bar: one line, always there (Fusion's bottom bar)
	ui_bar = _label("", 14, "text:0.8")
	ui_bar.anchor_top = 1.0
	ui_bar.anchor_bottom = 1.0
	ui_bar.offset_top = -BOTTOM_H - 34
	ui_bar.offset_bottom = -BOTTOM_H - 6
	ui_bar.offset_left = LEFT_W + 12
	ui_bar.anchor_right = 1.0
	ui_bar.offset_right = -RIGHT_W - 12
	ui_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_bar.clip_text = true
	ui_bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bb := StyleBoxFlat.new()
	bb.bg_color = Tok.c("panel")
	ui_bar_box = bb
	bb.set_corner_radius_all(4)
	bb.content_margin_left = 10
	bb.content_margin_right = 10
	ui_bar.add_theme_stylebox_override("normal", bb)
	ui_root.add_child(ui_bar)

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
	ui_cmd.pose_by_words = _pose_words
	_hover_hints()
	ui_cmd.running.connect(func(n): _step_hint = n)
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
	hv.add_child(_label("RIGHT-CLICK a part (click, don't drag: right-DRAG still turns the view): a ring around the mouse.  Up = Reset, then clockwise: Snap 90, Copy to the other side, CLIP this pose, Pin a trail, Snap 45.  Click one; the middle or Esc cancels.", 16, "text", true))
	hv.add_child(_label("S = SEARCH.  Don't remember where something is?  Press S, type a word (mirror, trail, staff, slower...), Enter.  Every button and key is in it, with its shortcut.", 16, "say", true))
	hv.add_child(_label("View: ARROWS slide the view, Shift+ARROWS turn around the body, PageUp/PageDown or the wheel zoom, Tab = big view.  F6 = the panels by keyboard (Tab moves, Enter presses, Esc back).  Mouse: right-drag = turn around, middle-drag = slide.", 15, "text:0.7", true))
	hv.add_child(_button("Got it", func(): ui_help.visible = false))
	ui_help.visible = false
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
	ui_scenes.clear()
	for dir in ["res://scenes", "res://moves"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".json"):
				continue
			var path: String = dir + "/" + f
			var txt := FileAccess.get_file_as_string(path)
			if txt.contains("\"keys\"") or txt.contains("\"cards\""):
				ui_scenes.add_item(f.get_basename().replace("_", " "))
				ui_scenes.set_item_metadata(ui_scenes.item_count - 1, path)
	_show_open_scene()


## the dropdown shows the scene that is OPEN (round 9: it kept showing the first file, and Delete scene trashes the
## dropdown's pick, not the open scene). An open scene that is not listed (scenes/_wip) = nothing picked.
func _show_open_scene() -> void:
	if ui_scenes == null:
		return
	ui_scenes.select(-1)
	for i in ui_scenes.item_count:
		if ui_scenes.get_item_metadata(i) == scene_path:
			ui_scenes.select(i)


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
	if sel in Body.WEAPON:
		what = wep_noun() + ("  in the " + nice(B.wep_hand) if B.wep_hand != "" else "  free")
	else:
		var v: Vector3 = B.ang[sel]
		what = "%s  swing %.0f  raise %.0f  roll %.0f" % [nice(sel), v.x, v.y, v.z]
	var card := "no cards" if S.cards.is_empty() else ("card %d / %d" % [sel_card + 1, S.cards.size()] if sel_card >= 0 else "%d cards, none picked" % S.cards.size())
	var t := "%.2f / %.2f s" % [playhead, _ps().length()]
	var fails := findings.filter(func(f): return f["sev"] == "FAIL").size()
	var chk := "Check: not run" if not check_ran else ("Check: clean" if findings.is_empty() else "Check: %d (%d must fix)" % [findings.size(), fails])
	if check_ran and undo.size() != check_at:
		chk += ", changed since"
	return "   |   ".join([what, card, t, chk])


func _panel() -> void:
	if ui_title == null:
		return
	_sync = true
	if sel in Body.WEAPON:
		_panel_bat()
	else:
		_panel_part()
	ui_time.max_value = maxf(_ps().length(), 0.01)
	ui_time.value = playhead
	ui_time_lbl.text = "%.2f / %.2f s" % [playhead, _ps().length()]
	if ui_ease != null:
		_grey(ui_ease, "this scene is Smooth (spline): one curve through every card sets the timing; turn Smooth off to ease card by card" if S.spline
			else ("pick a card first (click one in the scene row): the ease is the move INTO that card" if sel_card < 0
			else ("the first card has no move into it: pick card 2 or later" if sel_card == 0 else "")))
		ui_ease.select(Scene.EASES.find(S.cards[sel_card].get("ease", "smooth")) if sel_card >= 0 and sel_card < S.cards.size() else 0)
	if ui_timeline != null:
		ui_timeline.queue_redraw()
	ui_play.text = "  Stop (Space)  " if playing else "  Play (Space)  "
	_sync = false


func _panel_part() -> void:
	var v: Vector3 = B.ang[sel]
	var L: Dictionary = B.lim[sel]
	var lims: Array = B.at_limit(sel)
	ui_title.text = nice(sel).to_upper() + ("   (at its limit)" if not lims.is_empty() else "")
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
		var say: String = L["say"].get(k, "")
		row["label"].text = "%s   %.0f deg      (%s)" % [words[k], vals[k], say.replace("+ = ", "more = ")]
	ui_hip_box.visible = sel == "pelvis"
	ui_pole_row.visible = sel in ["hand_r", "hand_l", "foot_r", "foot_l"]
	(ui_pole_row.get_child(0) as Label).text = ("elbow" if sel.begins_with("hand") else "knee") + "  (Ctrl+drag)"
	var names := ["hips left / right", "hips up / down", "hips forward / back"]
	for k in 3:
		ui_hips[k][0].min_value = -1.0 if k != 1 else -0.9
		ui_hips[k][0].max_value = 1.0 if k != 1 else 0.4
		ui_hips[k][0].value = B.offset[k]
		ui_hips[k][1].text = "%s   %.2f m" % [names[k], B.offset[k]]
	if ui_math.visible:
		var A := B.compose(sel, v)
		var con: Array = B.contacts()
		ui_math.text = "%s  bend %.2f side %.2f twist %.2f deg\nA (turn from rest, rest axes) %s\nG (turn from rest, now) %s\njoint %s   end %s\ncontacts: %s\n(MATH.md explains every number)" % [
			sel, v.x, v.y, v.z, _qs(A), _qs(B.G[sel]), _vs(B.P[sel]), _vs(B.E[sel]),
			"none" if con.is_empty() else ", ".join(con.map(func(c): return "%s/%s %.0f mm" % [c[0], c[1], c[2] * 1000.0]))]


func _panel_bat() -> void:
	var locked := B.wep_hand != ""
	ui_title.text = {"metal_bat": "METAL BAT", "staff": "BO STAFF", "long_hammer": "LONG HAMMER"}.get(B.wep_kind, B.wep_kind.to_upper()) + "  " + ("(locked in the %s)" % nice(B.wep_hand) if locked else "(free)")
	ui_title.modulate = Color.WHITE
	var w := wep_noun()   # round 9: the panel said "bat" for the staff and the hammer too
	ui_how.text = ("LOCKED: the sliders shift the %s inside the hand.  Dragging the %s moves the hand.  'Free it' to move it alone." % [w, w] if locked
		else "FREE: drag = move it,  Shift+drag = turn it,  Alt+drag = spin it.  When it sits right in the fingers: 'Lock bat to hand' (any weapon).")
	var q: Quaternion = B.wep_lrot if locked else B.wep_rot
	var pos: Vector3 = B.wep_lpos if locked else B.wep_pos
	var e: Vector3 = Basis(q).get_euler() * (180.0 / PI)
	var words := {"bend": "TILT forward / back", "side": "TURN left / right", "twist": "TILT sideways"}
	var vals := {"bend": e.x, "side": e.y, "twist": e.z}
	for k in ["bend", "side", "twist"]:
		var row: Dictionary = ui_rows[k]
		row["box"].visible = true
		row["slider"].min_value = -180.0
		row["slider"].max_value = 180.0
		row["slider"].value = vals[k]
		row["label"].text = "%s   %.0f deg" % [words[k], vals[k]]
	ui_hip_box.visible = true
	ui_pole_row.visible = false
	var span := 0.3 if locked else 2.0
	var names := [w + " left / right", w + " up / down", w + " forward / back"]
	for k in 3:
		ui_hips[k][0].min_value = -span if (k != 1 or locked) else -0.2
		ui_hips[k][0].max_value = span
		ui_hips[k][0].value = pos[k]
		ui_hips[k][1].text = "%s   %.3f m%s" % [names[k], pos[k], "  (inside the hand)" if locked else ""]
	if ui_math.visible:
		var x := B.wep_xform()
		ui_math.text = "knob %s  tip %s\nrotation %s\nin the hand: pos %s rot %s" % [_vs(x[0]), _vs(B.wep_point(B.wep_len)), _qs(x[1]), _vs(B.wep_lpos), _qs(B.wep_lrot)]


static func _qs(q: Quaternion) -> String:
	return "(%.3f, %.3f, %.3f, %.3f) %.1f deg" % [q.x, q.y, q.z, q.w, rad_to_deg(q.get_angle())]


static func _vs(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _on_slider(val: float, k: String) -> void:
	if _sync:
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
		B.wep_lpos = pos
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
	if ui_cards == null:
		return
	_dummy_hits()   # the cards changed: the landed scene and its hits too
	ov.mark_dirty()
	if ui_browser != null:
		ui_browser.refresh()
	for c in ui_cards.get_children():
		ui_cards.remove_child(c)   # detach now: a freed card_3 would still hold its name for a frame
		c.queue_free()
	_layout_bottom()
	if S.cards.is_empty():
		ui_cards.add_child(_label("No clips yet.  Pose the body, press  CLIP this pose, pose the next moment, clip it, press Play.   Or start from one:", 16, "text:0.55"))
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
			ms.value_changed.connect(func(x): _push_undo(); S.cards[i]["move"] = x if x > 0.0 else -1.0; _retimed())
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
		hs.value_changed.connect(func(x): _push_undo(); S.cards[i]["hold"] = x; _retimed(false))
		hh.add_child(hs)
		var bh := HBoxContainer.new()
		v.add_child(bh)
		bh.add_child(_button("<", _card_move.bind(i, -1), "move this card earlier"))
		bh.add_child(_button(">", _card_move.bind(i, 1), "move this card later"))
		bh.add_child(_button("Update", _card_update.bind(i), "replace this card's pose with the body as it is now"))
		bh.add_child(_button("X", _card_del.bind(i), "delete this card"))


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
	var r := 10.0 if big_view else RIGHT_W + 10.0
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
whole pose", "run": _do.bind(B.mirror_side.bind(side)) if side != "" else _tool.bind(0)},
		{"name": "CLIP
this pose", "run": _card_add},
		{"name": "Pin a
trail here", "run": _press.bind(KEY_T, true)},
		{"name": "Snap 45", "run": _do.bind(_snap.bind(45.0))},
	]
	ui_ring.open(p, nice(j), its)


## show one ribbon tab's tools
func _ribbon(t: String) -> void:
	for k in RIBBON:
		ui_ribbon[k].visible = k == t
		ui_ribbon_tabs[k].set_pressed_no_signal(k == t)   # by hand: _no_signal does not release the group's others
	_ribbon_tab = t
	_fit_top()


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
	var right := 0.0
	var pc := ui_tb.get_parent() as PanelContainer
	if pc != null:
		var sb := pc.get_theme_stylebox("panel")
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
	var all: Array = []
	for t in RIBBON:
		all.append_array(ui_ribbon[t].get_children())
	all.append_array(ui_top_right)
	for b in all:
		if b is Button and b.has_meta("full"):
			b.text = b.get_meta("full")
	var tools: Array = ui_ribbon[_ribbon_tab].get_children()
	for b in tools:
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
	if _more_tools.is_empty():
		ui_more.visible = false
		return
	var pm := ui_more.get_popup()
	pm.clear()
	for i in _more_tools.size():
		pm.add_item(String(_more_tools[i].get("text")), i)


## a tool picked from More: the same as pressing it (a menu tool opens its own menu where More is)
func _more_pick(i: int) -> void:
	var b: Control = _more_tools[i]
	if b is MenuButton:
		var pm := (b as MenuButton).get_popup()
		(b as MenuButton).about_to_popup.emit()
		pm.position = Vector2i(ui_more.get_screen_position() + Vector2(0, ui_more.size.y))
		pm.popup()
	elif b is Button:
		(b as Button).pressed.emit()   # a toggle too: its action is on pressed, and _refresh lights it from the state


## the bottom panel's height follows the scene: no clips = the scene row and the hint, nothing else. Everything that
## stands on the panel (side panels' bottoms, the status line, the speed graph, the camera's centring) moves with it
func _layout_bottom() -> void:
	if ui_bp == null or ui_status == null or ui_bar == null or ui_graph == null or ui_timeline == null:   # mid-build
		return
	var empty := S.cards.is_empty()
	bottom_h = BOTTOM_EMPTY if empty else BOTTOM_H
	ui_card_row.custom_minimum_size.y = 26 if empty else 112
	ui_timeline.visible = not empty
	ui_play_row.visible = not empty
	ui_bp.offset_top = -bottom_h
	for p in ui_side:
		p.offset_bottom = -bottom_h - 6
	ui_status.offset_top = -bottom_h - 82
	ui_status.offset_bottom = -bottom_h - 40
	ui_bar.offset_top = -bottom_h - 34
	ui_bar.offset_bottom = -bottom_h - 6
	ui_graph.offset_bottom = -bottom_h - 92
	ui_graph.offset_top = -bottom_h - 92 - 120
	_cam()


## a key, as if pressed in the view: a command that has a key runs through the key's own code, so the two never differ
func _press(code: Key, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	_unhandled_input(k)


## everything S can find: each runs what its button / key runs. "also" = other words people would type for it.
## THE COMMAND REGISTRY (round 8, GATES O2): each entry also has an "id" (a unique slug, what tools/poser_cli.gd
## and the tests call it by), a one-line "desc" (the search shows it as the tooltip) and "edits": true when it changes
## the body or the scene's cards, so it must be ONE undo step (tests/undo_audit_test.gd holds every command to that).
## KEYS ON ONE SCREEN (round 17, GATES X2): every registry command that has a key, rebuilt from the registry each time
## it opens (a command given a key shows up with nothing else to change), grouped by what you hold: plain keys,
## Shift + a key, Ctrl + a key. ? opens and closes it, Esc closes it
var ui_keys: PanelContainer


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
	v.add_child(_label("EVERY KEY  (? or Esc closes this; S finds the rest by name)", 16, "heading"))
	var scr := ScrollContainer.new()   # capped to the room (at 125 % the UI has 720 px): it scrolls rather than run off
	scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scr)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	scr.add_child(cols)
	var keyed: Array = ui_cmd.commands.filter(func(c): return String(c["keys"]) != "")
	for g in [["KEYS", func(k: String): return not k.begins_with("Shift+") and not k.begins_with("Ctrl+")],
			["SHIFT + KEY", func(k: String): return k.begins_with("Shift+")], ["CTRL + KEY", func(k: String): return k.begins_with("Ctrl+")]]:
		var rows: Array = keyed.filter(func(c): return g[1].call(String(c["keys"])))
		if rows.is_empty():
			continue
		var gv := VBoxContainer.new()
		cols.add_child(gv)
		gv.add_child(_label(g[0], 14, "text:0.7"))
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
	var want := cols.get_combined_minimum_size()
	scr.custom_minimum_size = Vector2(minf(want.x, room.x - 28), minf(want.y, room.y - 28 - 40))
	ui_keys.reset_size()
	ui_keys.position = ((get_viewport().get_visible_rect().size - ui_keys.size) / 2.0).floor()   # centred, after its size is known


func _commands() -> Array:
	var c := []
	var add := func(n: String, keys: String, f: Callable, also: String, edits: bool, desc: String):
		var id := n.to_lower()
		for ch in ["/", "(", ")", ",", ":", "%"]:
			id = id.replace(ch, " ")
		c.append({"id": "_".join(id.split(" ", false)), "name": n, "keys": keys, "run": f, "also": also, "edits": edits, "desc": desc})
	for v in [["Front view", 1], ["His right view", 2], ["Top view", 3], ["Back view", 4], ["His left view", 5]]:
		add.call(v[0], str(v[1]), _press.bind(KEY_0 + v[1]), "camera look", false, "camera: %s" % v[0].to_lower())
	add.call("Every key on one screen", "?", keys_overlay.bind(true), "keys shortcuts help cheat sheet hotkeys", false, "a list of every key the poser has, made from this registry (? or Esc closes it)")
	add.call("Undo", "Ctrl+Z", _undo, "back", false, "take back the last change to the body or the cards")
	add.call("Redo", "Ctrl+Y", _redo, "", false, "put back what Undo took back")
	add.call("First steps tour", "", _tour_start, "tour help start begin learn new intro guide", false, "five steps that show the poser by doing: click a part, drag it, clip two cards, play, check")
	add.call("Undo history", "", _toggle_history, "steps list back forward", false, "every change by name, newest on top: click one to go back (or forward) to exactly there")
	add.call("Save pose", "Ctrl+S", _save_pose, "store keep", false, "save the body as a pose file in poses/ (the Poses list)")
	add.call("CLIP this pose (add a card)", "Enter", _press.bind(KEY_ENTER), "key frame add new", true, "add the body as a new card after the picked one")
	add.call("Play / pause", "Space", _press.bind(KEY_SPACE), "run stop", false, "play the scene from the playhead, or stop it")
	add.call("Big view (hide the panels)", "Tab", _press.bind(KEY_TAB), "fullscreen", false, "hide the side panels so the body gets the whole window")
	add.call("Keyboard: the panels by keys", "F6", _kb_enter, "keyboard", false, "Tab / Shift+Tab move from control to control, Enter or Space presses, Esc gives the keys back to the view")
	add.call("Reset the part", "R", _press.bind(KEY_R), "zero", true, "the picked part back to straight (0, 0, 0)")
	add.call("Snap the part to 90", "Q", _press.bind(KEY_Q), "round", true, "round the picked part's angles to the 90-degree steps its range allows")
	add.call("Snap the part to 45", "Shift+Q", _press.bind(KEY_Q, true), "round", true, "round the picked part's angles to the 45-degree steps its range allows")
	add.call("Copy right side to left", "M", _press.bind(KEY_M), "mirror symmetry", true, "the left arm and leg take the right ones' pose, reflected")
	add.call("Copy left side to right", "N", _press.bind(KEY_N), "mirror symmetry", true, "the right arm and leg take the left ones' pose, reflected")
	add.call("Symmetry on / off", "", _toggle_symmetry, "live both sides twin symmetric", false, "while on, dragging a part on one side moves the same part on the other side, reflected")
	add.call("Mirror the whole pose", "Shift+M", _press.bind(KEY_M, true), "flip left right", true, "the whole body reflected left <-> right; the weapon changes hands")
	for e in Scene.EASES:
		add.call("Ease: " + e, "", _set_ease.bind(e), "easing timing curve " + {"smooth": "natural", "linear": "constant even", "in": "slow start accelerate", "out": "slow end decelerate", "snap": "jump cut hit step"}[e], true,
			"the picked card's move eases '%s'" % e)
	add.call("Plant the left foot on this card", "", _toggle_plant.bind("_l"), "pin lock foot slide skate stick floor", true, "on/off: the left foot stays where it stood in the card before (no sliding)")
	add.call("Plant the right foot on this card", "", _toggle_plant.bind("_r"), "pin lock foot slide skate stick floor", true, "on/off: the right foot stays where it stood in the card before (no sliding)")
	add.call("Copy pose", "Ctrl+C", _copy_pose, "clipboard", false, "remember the body's pose (every angle and the hips) to paste on another card")
	add.call("Paste pose", "Ctrl+V", _paste_pose.bind(""), "clipboard", true, "the copied pose onto the body (Update keeps it on the card)")
	add.call("Paste pose mirrored", "Ctrl+Shift+V", _paste_pose.bind("mirrored"), "clipboard flip left right", true, "the copied pose reflected left <-> right")
	add.call("Paste to this part", "", _paste_pose.bind("part"), "clipboard arm leg only", true, "the copied pose on the picked part and the parts below it only (an arm, a leg)")
	add.call("Mirror the scene (left-handed copy)", "", _tool.bind(5), "flip", false, "a reflected copy of the scene, saved in scenes/_wip and opened (yours untouched)")
	add.call("Collision shapes on/off", "C", _press.bind(KEY_C), "capsules hit", false, "show the capsules that stop parts going through each other")
	add.call("Motion trail on/off", "T", _press.bind(KEY_T), "path arc", false, "draw the weapon tip's path over the scene")
	add.call("Pin a trail on the picked part", "Shift+T", _press.bind(KEY_T, true), "path arc", false, "draw the picked body part's path over the scene (again removes it)")
	add.call("Onion skin on/off", "O", _press.bind(KEY_O), "ghost before after", false, "ghosts of the card before (orange) and after (green)")
	add.call("Spacing ghosts on/off", "Shift+O", _press.bind(KEY_O, true), "ghost timing", false, "ghosts every 0.1 s: bunched = slow, spread = fast")
	add.call("Speed graph on/off", "Y", _press.bind(KEY_Y), "curve velocity", false, "tip, hips and head speed over the scene; click it to scrub")
	add.call("Stepped preview on/off", "", _tool.bind(3), "blocking poses", true, "play card to card with no in-betweens (view only, never saved)")
	add.call("Moving holds on/off", "", _tool.bind(4), "drift", true, "during a hold the upper body drifts a little toward the next card (saved with the scene)")
	add.call("Check the motion", "", _check, "grade problems rules", false, "grade the scene against the rulebook; each finding jumps to its moment")
	add.call("Polish the scene (new copy)", "", _polish, "smooth detail", false, "the detail pass on a copy in scenes/_wip, opened (yours untouched)")
	add.call("Fix moves through the body", "", _clear_scene, "collision pass", true, "add pass-by cards so no move goes through the body")
	add.call("Add an in-between card", "", _tween_add, "tween", true, "a new card halfway between the picked card and the next")
	add.call("Slower (10%)", "", _speed.bind(1.1), "timing", true, "the picked card (or the whole scene) 10% slower")
	add.call("Faster (10%)", "", _speed.bind(1.0 / 1.1), "timing", true, "the picked card (or the whole scene) 10% faster")
	add.call("Loop: close the seam", "", _loop_close, "timing", true, "the last card becomes a copy of the first, so a loop's end meets its start (and Loop is turned on)")
	add.call("Save scene", "Ctrl+Shift+S", _save_scene, "", false, "write the scene to scenes/<name>.json (Enter in the name box does it too)")
	add.call("New empty scene", "", _new_scene, "", false, "start a new scene with no cards (the open one stays on disk)")
	add.call("Reset body", "", _do.bind(_reset_all), "t-pose", true, "every joint back to straight and the hips to the origin")
	add.call("Arms down 25 deg", "", _do.bind(_arms_relaxed), "relax a-pose", true, "both arms relaxed: 25 degrees out from straight down")
	add.call("Dummy on/off", "H", _press.bind(KEY_H), "target enemy mannequin", false, "show or hide the target dummy")
	add.call("Dummy solid / see-through", "", _dummy_solid, "target", false, "solid: the weapon stops on the dummy (impact + rebound); see-through: it passes")
	add.call("Dummy closer", "", _dummy_move.bind(-0.25), "target", false, "move the dummy 25 cm closer")
	add.call("Dummy farther", "", _dummy_move.bind(0.25), "target", false, "move the dummy 25 cm farther")
	add.call("Weapon: metal bat", "", _do.bind(_kind.bind("metal_bat")), "", true, "switch the weapon to the metal bat (0.84 m)")
	add.call("Weapon: bo staff", "", _do.bind(_kind.bind("staff")), "", true, "switch the weapon to the bo staff (1.8 m)")
	add.call("Weapon: long hammer", "", _do.bind(_kind.bind("long_hammer")), "", true, "switch the weapon to the long hammer (1.1 m)")
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
		for f in ["open", "grip", "fist"]:
			add.call("Fingers %s: %s" % [side[1], f], "", _do.bind(_fingers.bind(side[0], f)), "hand", true, "the %s hand's fingers: %s" % [side[1], f])
	add.call("Light / dark theme", "", func(): _set_light(Tok.dark), "colour white bright night", false, "switch the light and dark look (remembered)")
	for p in SCALES:
		add.call("UI size %d %%" % p, "", _set_scale.bind(p), "zoom bigger smaller scale font text size", false, "buttons and words at %d %% (remembered)" % p)
	add.call("Help", "", func(): ui_help.visible = not ui_help.visible, "how manual", false, "show or hide the help panel")
	return c


## the timing changed (timeline drag, a move/hold box): everything that was built from the old timing is rebuilt.
## rebuild=false keeps the card boxes (a box being typed into must not be freed under the cursor)
func _retimed(rebuild := true) -> void:
	if rebuild:
		_rebuild_cards()   # also: the landed dummy copy + the trail/graph/ghost pass
	else:
		_dummy_hits()
		ov.mark_dirty()
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
	_say(("the %s swung %.0f deg; the %s stays where it was" % [w, got, nice(sel)]) if absf(got - deg) < 1.0
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
func _paste_pose(how: String) -> void:
	if pose_clip.is_empty():
		_say("nothing copied yet: press Ctrl+C on the pose you want first, then Ctrl+V here")
		return
	if how == "part" and not sel in Body.ORDER:
		_say("pick a body part first: the paste goes to it and the parts below it")
		return
	_do(func(): B.pose_paste(pose_clip, how == "mirrored", B.below(sel) if how == "part" else []))
	_say({"": "pose pasted", "mirrored": "pose pasted, mirrored", "part": "pasted to the %s and below" % nice(sel)}[how] + ".  Ctrl+Z undoes; Update keeps it on the card")


func _tool(id: int) -> void:
	var pm := ui_tools.get_popup()
	match id:
		0:
			_do(func(): B.mirror_pose())
			_say("mirrored: the whole body left <-> right (the weapon changed hands).  Ctrl+Z undoes; Update keeps it on the card")
		1:
			ov.spacing_on = not ov.spacing_on
			ov.mark_dirty()
			_refresh()
			_say("spacing ghosts every 0.1 s: orange = before, green = after.  Bunched = slow, spread = fast" if ov.spacing_on else "spacing ghosts off")
		2:
			ov.graph_on = not ov.graph_on
			ov.mark_dirty()
			_refresh()
			_say("speed graph: tip, hips, head over the scene; the grey lines are the cards.  Click it to move the playhead" if ov.graph_on else "speed graph off")
		3:
			_push_undo()   # round 8 (undo audit): it puts the scene's pose on the body; a pose not yet on a card was lost
			stepped_view = not stepped_view
			ov.mark_dirty()
			_ps().apply(B, playhead)
			_refresh()
			_say("STEPPED: each card's pose holds until the next one arrives (no in-betweens).  Check still grades the real motion" if stepped_view else "stepped preview off: in-betweens back")
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
	if S.cards.size() < 2:
		_say("Mirror the scene needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	var keep := B.state()   # lossless (round 8): to_dict rounds, so the live body jumped a rounding step
	var d := S.to_dict(B)
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	d["cards"] = d["cards"].map(func(c): return Scene.mirror_card(c, M))   # by Scene.MIRROR_CARD (round 19, Z1)
	B.set_state(keep)
	var base := S.name.trim_suffix("_mirrored")
	d["scene"] = base + "_mirrored" if not S.name.ends_with("_mirrored") else base
	# the file's own record of the mirrored motion (bad_frames names parts: the original's were the wrong side)
	var S2 := Scene.new()
	S2.from_dict(d)
	var plan: String = "Mirror the scene (Scene.MIRROR_CARD on every card) from " + S.name
	d = S2.to_dict(M)
	d["plan"] = plan
	# the file name made safe (round 19: the raw name wrote "_wip/x" into scenes/_wip/_wip/, and "a:b" was a name Windows
	# refuses); always in scenes/_wip, whatever folder the name gives
	var path := "res://scenes/_wip/%s.json" % safe_file(String(d["scene"])).trim_prefix("_wip/")
	_write(path, d)
	_load_scene(path)
	_rebuild_cards()
	_refresh()
	_say("mirrored scene saved as %s and opened; '%s' is untouched" % [path.get_file(), S.name])


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
	var h := (g.size.y - 8.0) / rows.size()
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


func _graph_input(ev: InputEvent) -> void:
	var lw := 118.0
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
	var title := _label("CHECK  -  " + ("clean: nothing here breaks the rulebook" if findings.is_empty() else "%d to look at (%d must fix)" % [findings.size(), fails]), 18, "heading" if findings.is_empty() else "warn")
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
		var lbl := Fixer.label(f, S)
		if lbl != "":
			var fx := _button(lbl, _fix.bind(f))
			fx.name = "fix_%d" % (fk + 1)
			fx.add_theme_font_size_override("font_size", 14)
			fx.mouse_entered.connect(_fix_hover.bind(f))   # FIX PREVIEW (#79): a blue ghost of the result, nothing changed
			fx.mouse_exited.connect(_fix_hover.bind({}))
			ui_find_list.add_child(fx)
		else:
			ui_find_list.add_child(_label("   no automatic fix: " + ("two cards fight here; change one of them" if f["rule"] == "HITCH" else "the foot creeps between two cards' stances: give the cards the same foot spot, or step it on purpose" if f["rule"] == "FOOT SLIDE" else "it is in the poses; change the cards around it"), 12, "text:0.5", true))
	# a ScrollContainer has no height of its own: size it to the list (up to most of the view), else it collapses to 0
	(ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(56.0 + 128.0 * findings.size(), 60.0,
		minf(440.0, get_viewport().get_visible_rect().size.y - bottom_h - 82 - (TOP_H + 12) - 26)))   # ends above the status line (round 9: the bar moved it up)
	ui_find.visible = true
	_say("check: " + ("clean" if findings.is_empty() else "%d findings, %d must fix.  Click one to jump to it." % [findings.size(), fails]))


func _goto_finding(f: Dictionary) -> void:
	playing = false
	playhead = f["t"]
	sel_card = mini(f["card"], S.cards.size() - 1)
	_ps().apply(B, playhead)
	_rebuild_cards()
	_refresh()
	_say("%s at %.2f s (card %d): %s" % [f["rule"], f["t"], sel_card + 1, f["msg"]])


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


func _fix(f: Dictionary) -> void:
	ov.fix_preview(S, [], 0.0)
	_pv_hover = {}
	if _fixing:
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


func _toggle_play() -> void:
	if S.cards.size() < 2:
		_say("a scene needs two cards or more to play: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	playing = not playing
	if playing and playhead >= _ps().length() - 0.01:
		playhead = 0.0
	_refresh()


## NEW EMPTY SCENE (one function for its button and its registry entry; round 20, GATES AA3: the two copies did not
## refresh, so the speed graph stayed up over the empty scene with the old scene's curves)
func _new_scene() -> void:
	S = Scene.new()
	scene_path = ""
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
		_say("type the new name in the box above first")
		return
	var path := "res://moves/%s.json" % nm
	if FileAccess.file_exists(path):
		_say("a pose called '%s' already exists: type another name in the box above, then press Rename" % nm)
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
	_say("%s %s: the scene is now %.2f s (Save scene keeps it)" % ["card '%s'" % S.cards[sel_card]["name"] if idx.size() == 1 and sel_card >= 0 else ("cards %d-%d" % [idx[0] + 1, idx[-1] + 1] if idx.size() < S.cards.size() or sel_end >= 0 else "whole scene"), "slower" if k > 1.0 else "faster", _ps().length()])


func _load_pose(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d.has("keys") or d.has("cards"):
		_load_scene(path)
		return
	B.from_dict(d)
	B.capture_second()   # a pose with both hands on the shaft loads with both hands holding it


func _save_scene() -> void:
	if S.cards.is_empty():
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
	S.name = nm if nm != "" else "scene_" + _stamp()   # the name as typed: what the scene is called
	var keep := B.state()   # lossless (round 8): to_dict rounds, so the live body jumped a rounding step
	var d := S.to_dict(B)
	B.set_state(keep)
	var fname := safe_file(S.name) if safe_file(S.name) != "" else "scene_" + _stamp()
	_write("res://scenes/%s.json" % fname, d)
	_clean = JSON.stringify(S.cards)
	_autosave_drop()
	scene_path = "res://scenes/%s.json" % fname
	_lists()
	_refresh()
	_say("saved scene %s: %d cards, %.2f s, %d frames with parts inside each other" % [S.name, S.cards.size(), S.length(), d["bad_frames"].size()])


## the scene list's pick: opens it at once when nothing would be lost, asks first when the scene open now has changes
## that are not saved (opening can't be undone)
func _scene_picked(i: int) -> void:
	var path: String = ui_scenes.get_item_metadata(i)
	if path == scene_path and _unsaved() == false:
		return
	var go := func():
		_load_scene(path)
		_rebuild_cards()
		_refresh()
	if _unsaved():
		_confirm("Open '%s'?
The changes to '%s' aren't saved, and opening can't be undone." % [path.get_file().get_basename(), S.name if S.name != "" else "this scene"],
			"Open it", go)
	else:
		go.call()


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
	var k := pct / 100.0
	var mv := []
	for i in range(a, b + 1):
		mv.append(S.move_time(i) if i > 0 else 0.0)   # read every move BEFORE writing any: an auto move reads its neighbours
	for i in range(a, b + 1):
		if i > 0:
			S.cards[i]["move"] = snappedf(maxf(0.04, mv[i - a] * k), 0.001)
		S.cards[i]["hold"] = snappedf(float(S.cards[i]["hold"]) * k, 0.001)
	_rebuild_cards()
	_refresh()
	_say("cards %d-%d at %.0f %%: the scene is now %.2f s (Save scene keeps it)" % [a + 1, b + 1, pct, _ps().length()])
	return ""


## AUTOSAVE (round 16, GATES W1): the unsaved scene to `autosave`, atomically: a temp file, then a rename, so a crash
## in the middle leaves the last good copy. Nothing unsaved, or nothing new since the last write: no write
func autosave_now() -> bool:
	if not _unsaved():
		return false
	var keep := B.state()
	var d := S.to_dict(B)
	B.set_state(keep)
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
	return true


func _autosave_drop() -> void:
	var fp := ProjectSettings.globalize_path(autosave)
	for q in [fp, fp + ".tmp"]:
		if FileAccess.file_exists(q):
			DirAccess.remove_absolute(q)
	_as_last = ""


var ui_recover: ConfirmationDialog
var _recovering := false   # Recover opens the scene's file under the autosave: that open must not drop the autosave


## on start: an autosave that differs from its scene on disk is offered back (Recover / Discard)
func _recover_offer() -> void:
	var fp := ProjectSettings.globalize_path(autosave)
	if not FileAccess.file_exists(fp):
		return
	var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(fp))
	if not (a is Dictionary) or not (a.get("scene") is Dictionary) or not a["scene"].has("cards"):
		_autosave_drop()   # unreadable: nothing to give back
		return
	var path: String = a.get("path", "")
	if path != "" and FileAccess.file_exists(path):
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if disk is Dictionary and JSON.stringify(disk.get("cards")) == JSON.stringify(a["scene"]["cards"]):
			_autosave_drop()   # the same as the file: nothing was lost
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
		ui_recover.canceled.connect(func(): _autosave_drop(); _say("the unsaved work was discarded"))
	var nm: String = a["scene"].get("name", "")
	if nm == "" and path != "":
		nm = path.get_file().get_basename()
	ui_recover.dialog_text = "Poser closed with unsaved work:
'%s', %d cards, autosaved %s.
Recover it?" % [
		nm if nm != "" else "a new scene", a["scene"]["cards"].size(), String(a.get("at", "")).replace("T", " ")]
	ui_recover.set_meta("autosave", a)
	ui_recover.popup_centered()


## Recover: the autosaved scene comes back, still marked unsaved (its file on disk is what _clean holds)
func _recover() -> void:
	var a: Dictionary = ui_recover.get_meta("autosave")
	var path: String = a.get("path", "")
	_clean = "[]"
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
	_dummy_hits()
	sel_card = -1
	playhead = 0.0
	S.apply(B, 0.0)
	_rebuild_cards()
	_refresh()
	_say("recovered '%s' (%d cards): it is not saved yet, Save scene keeps it" % [S.name, S.cards.size()])


func _unsaved() -> bool:
	return not S.cards.is_empty() and JSON.stringify(S.cards) != _clean


func _load_scene(path: String) -> void:
	scene_path = path
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check_ran = false
	S = Scene.new()
	if d.has("cards"):
		S.from_dict(d)
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
	_show_open_scene()
	if ui_natural != null:
		ui_natural.set_pressed_no_signal(S.natural)   # the boxes show THIS scene's settings (10-14: they kept the last ones)
		ui_spline.set_pressed_no_signal(S.spline)
		ui_loop.set_pressed_no_signal(S.loop)
	ov.mark_dirty()
	_dummy_hits()
	sel_card = -1
	playhead = 0.0
	_clean = JSON.stringify(S.cards)
	if not _recovering:
		_autosave_drop()   # opened a scene: what was unsaved was given up (it asks first, V3)
	S.apply(B, 0.0)
