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
const TOP_H := 46

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
var ui_poses: ItemList
var ui_pose_name: LineEdit
var ui_cards: HBoxContainer
var ui_time: HSlider
var ui_time_lbl: Label
var ui_play: Button
var ui_natural: CheckBox
var ui_scene_name: LineEdit
var ui_scenes: OptionButton
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
var ui_spline: CheckBox
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


## the scene the window plays: landed on the solid dummy, or as authored
func _ps() -> Scene:
	var p: Scene = SL if dummy_on and solid and SL != null else S
	p.stepped = stepped_view   # a view setting: the scene that PLAYS shows it, whichever one that is
	if p != S:
		p.moving_holds = S.moving_holds
	return p


func _ready() -> void:
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_world()
	_body()
	add_child(ov)
	ov.setup()
	_ui()
	var args := OS.get_cmdline_user_args()
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
	i = args.find("--t")
	if i >= 0 and i + 1 < args.size():
		playhead = float(args[i + 1])
		_ps().apply(B, playhead)
	i = args.find("--tween")   # --tween <card number> <bias>: pick that card and slide the tween (for shots and checks)
	if i >= 0 and i + 2 < args.size():
		_card_pick(int(args[i + 1]) - 1)
		_sync = true
		ui_tween.value = float(args[i + 2])
		_sync = false
		_tween(float(args[i + 2]))
	if args.has("--check"):   # open the CHECK panel (shots and tests)
		_check()
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
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()


func _process(dt: float) -> void:
	_keys_camera(dt)
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
	e.background_color = Color(0.11, 0.115, 0.13)
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
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in range(-20, 21):
		var x := k * 0.1
		var c := Color(0.32, 0.33, 0.37) if k % 10 == 0 else Color(0.19, 0.2, 0.23)
		for seg in [[Vector3(x, 0, -2), Vector3(x, 0, 2)], [Vector3(-2, 0, x), Vector3(2, 0, x)]]:
			im.surface_set_color(c)
			im.surface_add_vertex(seg[0])
			im.surface_set_color(c)
			im.surface_add_vertex(seg[1])
	for ax in [[Vector3(0.6, 0.001, 0), Color(0.9, 0.3, 0.3)], [Vector3(0, 0.001, 0.6), Color(0.3, 0.5, 0.95)]]:
		im.surface_set_color(ax[1])
		im.surface_add_vertex(Vector3(0, 0.001, 0))
		im.surface_set_color(ax[1])
		im.surface_add_vertex(ax[0])
	im.surface_end()
	add_child(gm)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4, 4)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.13, 0.135, 0.15)
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


func _dummy_hits() -> void:
	if ui_dummy == null:
		return
	if not dummy_on:
		ui_dummy.text = "dummy off"
		return
	var txt := "dummy %.2f m out, %s" % [T.dist, "SOLID: the weapon stops on it" if solid else "see-through"]
	SL = null
	if S.cards.size() >= 2:
		var HB := Body.new()
		HB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var hs: Array = T.hits(S, HB, 30)
		if hs.is_empty():
			txt += "
the scene: no hit at this range"
		for x in hs:
			txt += "
%.2fs  %s  %.1f m/s  (%.2f m up)" % [x["t"], x["zone"], x["speed"], x["u"]]
		if solid and not hs.is_empty():
			var r: Array = T.landed(S, HB)
			SL = r[0]
			txt += "
lands %.2fs on the %s, rebounds; plays %.2f s" % [r[1]["t"], r[1]["zone"], SL.length()]
	ui_dummy.text = txt


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


func _view(k: int) -> void:
	pitch = -8.0
	match k:
		1: yaw = 0.0
		2: yaw = -90.0
		3:
			yaw = 0.0
			pitch = -89.0
		4: yaw = 180.0
		5: yaw = 90.0
		6:   # from below (the ViewCube's bottom face)
			yaw = 0.0
			pitch = 89.0
	_cam()


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
		if k.ctrl_pressed:
			match k.keycode:
				KEY_Z: _undo()
				KEY_Y: _redo()
				KEY_S: _save_pose()
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
			KEY_B: _do(func(): _bat_put("hand_r") if not B.wep_on else _bat_remove())
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
	var what := "ROLLING" if twist else ("MOVING" if (move and sel == "pelvis") else ("PULLING" if tip and not alt else "ROTATING"))
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


func _after_edit() -> void:
	B.apply_grip()
	_refresh()


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
	return {"body": B.to_dict(), "scene": S, "cards": S.cards.duplicate(true), "sel": sel_card, "holds": S.moving_holds}


func _restore(u: Dictionary) -> void:
	B.from_dict(u["body"])
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
	undo.append(_snapshot())
	if undo.size() > 60:
		undo.pop_front()
	redo.clear()


func _undo() -> void:
	if undo.is_empty():
		_say("nothing to undo")
		return
	redo.append(_snapshot())
	_restore(undo.pop_back())
	_say("undone")


func _redo() -> void:
	if redo.is_empty():
		return
	undo.append(_snapshot())
	_restore(redo.pop_back())
	_say("redone")


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


# ---------------------------------------------------------------- ui building

func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 16
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.085, 0.09, 0.105, 0.94)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.19, 0.21, 0.25)
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(6)
	var hov := btn.duplicate()
	hov.bg_color = Color(0.26, 0.3, 0.37)
	var prs := btn.duplicate()
	prs.bg_color = Color(0.2, 0.42, 0.75)
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", hov)
	th.set_stylebox("pressed", "Button", prs)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return th


func _label(t: String, size := 16, col := Color(1, 1, 1), wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(120, 0)
	return l


func _button(t: String, f: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
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
	parent.add_child(_label(t, 15, Color(0.6, 0.75, 1.0)))


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
	top.anchor_right = 1.0
	top.offset_bottom = TOP_H
	ui_root.add_child(top)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 6)
	top.add_child(tb)
	tb.add_child(_label("POSER  ", 20, Color(0.6, 0.78, 1.0)))
	# round 7, Fusion's ribbon: tabs, then that tab's tools; Undo / Redo / Search / Help always on the right. Nothing
	# was removed: every button the bar had is in a tab (tests/ribbon_test.gd counts them), and the play row keeps its own
	ui_ribbon = {}
	ui_ribbon_tabs = {}
	var group := ButtonGroup.new()
	for t in RIBBON:
		var tbtn := _button(t, _ribbon.bind(t), RIBBON_TIPS[t])
		tbtn.toggle_mode = true
		tbtn.button_group = group
		tbtn.add_theme_font_size_override("font_size", 15)
		tbtn.add_theme_color_override("font_pressed_color", Color(0.6, 0.78, 1.0))
		ui_ribbon_tabs[t] = tbtn
		tb.add_child(tbtn)
		var tools := HBoxContainer.new()
		tools.add_theme_constant_override("separation", 6)
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
	ui_ribbon["POSE"].add_child(_button("Arms 25 deg", _do.bind(_arms_relaxed)))
	ui_ribbon["POSE"].add_child(_button("Mirror pose (Shift+M)", _tool.bind(0), "the whole body left <-> right (the weapon changes hands)"))
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
	# always there
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(fill)
	tb.add_child(_button("Undo (Ctrl+Z)", _undo))
	tb.add_child(_button("Redo (Ctrl+Y)", _redo))
	tb.add_child(_button("Search (S)", func(): ui_cmd.open(), "type a few letters of any command: mirror, trail, check, staff...  Enter runs it"))
	tb.add_child(_button("? Help", func(): ui_help.visible = not ui_help.visible))
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
	lv.add_child(_label("1  POSES", 19, Color(0.6, 0.78, 1.0)))
	lv.add_child(_label("Click a pose: the body takes it.", 14, Color(1, 1, 1, 0.65), true))
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
	_row(lv, [_button("Delete pose", _delete_pose, "click a pose in the list, then Delete twice (it goes to the trash folder)")])
	_row(lv, [_button("CLIP this pose  (Enter)", _card_add, "the body as it is now becomes the next clip in the scene below")])
	lv.add_child(_label("WEAPON  (in the right hand)", 14, Color(0.6, 0.78, 1.0)))
	_row(lv, [_button("Bat", _do.bind(_kind.bind("metal_bat")), "metal bat 0.84 m"), _button("Bo staff", _do.bind(_kind.bind("staff")), "staff 1.8 m")])
	_row(lv, [_button("Hammer", _do.bind(_kind.bind("long_hammer")), "long hammer 1.1 m"), _button("None", _do.bind(_bat_remove), "remove the weapon")])
	_row(lv, [_button("2nd hand on/off (G)", _do.bind(_toggle_second), "the other hand on the shaft; [ ] slide it")])
	ui_slide_btn = _button("Slide , . : body follows", _slide_mode, "an option, not a rule: , . either move the hand along a weapon that stays put (the arm follows), or slide the weapon through a hand that stays put")
	_row(lv, [ui_slide_btn])
	_row(lv, [_button("Hand to the end", _do.bind(_hand_to_end), "Nick 10-13: a long weapon swings from its end - the main hand slides to the lower end in 3 cm steps (the body follows, or the weapon moves: the toggle above)")])
	lv.add_child(_label("TARGET DUMMY  (H)", 14, Color(1.0, 0.6, 0.5)))
	_row(lv, [_button("On/off", _dummy_toggle, "a second mannequin out front: it turns red where the weapon is in it (H)"),
		_button("Closer", _dummy_move.bind(-0.25), "the dummy 25 cm closer"), _button("Farther", _dummy_move.bind(0.25), "the dummy 25 cm farther")])
	_row(lv, [_button("Solid / see-through", _dummy_solid, "solid: the swing stops on the dummy and rebounds (the scene plays as landed); see-through: the scene as you made it")])
	ui_dummy = _label("dummy %.2f m out" % T.dist, 13, Color(1.0, 0.8, 0.75), true)
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
	vb.add_child(_label("2  SELECTED PART  (click the body)", 15, Color(0.6, 0.78, 1.0)))
	ui_title = _label("", 22, Color(1, 1, 1), true)
	vb.add_child(ui_title)
	ui_how = _label("", 14, Color(0.75, 0.9, 1.0), true)
	vb.add_child(ui_how)
	for k in ["bend", "side", "twist"]:
		var box := VBoxContainer.new()
		var l := _label("", 15, Color(1, 1, 1), true)
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
		var l := _label("", 15, Color(1, 1, 1), true)
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
	_row(vb, [_button("Right to left (M)", _do.bind(B.mirror_side.bind("_r"))),
		_button("Left to right (N)", _do.bind(B.mirror_side.bind("_l")))])
	_section(vb, "HANDS")
	_row(vb, [_label("right:", 15), _button("Open", _do.bind(_fingers.bind("r", "open"))), _button("Grip", _do.bind(_fingers.bind("r", "grip"))),
		_button("Fist", _do.bind(_fingers.bind("r", "fist")))])
	_row(vb, [_label("left:  ", 15), _button("Open", _do.bind(_fingers.bind("l", "open"))), _button("Grip", _do.bind(_fingers.bind("l", "grip"))),
		_button("Fist", _do.bind(_fingers.bind("l", "fist")))])
	vb.add_child(_label("Fingers one by one: click a finger on the body (zoom in with the wheel).", 13, Color(1, 1, 1, 0.55), true))
	_section(vb, "WEAPON")
	_row(vb, [_button("Metal bat", _do.bind(_kind.bind("metal_bat"))), _button("Staff (bo)", _do.bind(_kind.bind("staff"))),
		_button("Long hammer", _do.bind(_kind.bind("long_hammer")))])
	_row(vb, [_button("In right hand (B)", _do.bind(_bat_put.bind("hand_r"))), _button("In left hand", _do.bind(_bat_put.bind("hand_l")))])
	_row(vb, [_button("Main hand down (,)", _do.bind(_slide.bind(-0.03)), "the hand slides toward the lower end; the weapon stays, the arm follows"),
		_button("Main hand up (.)", _do.bind(_slide.bind(0.03)), "the hand slides toward the tip; the weapon stays, the arm follows")])
	_row(vb, [_button("Lock bat to hand / Free it (L)", _do.bind(_bat_lock)), _button("Remove bat", _do.bind(_bat_remove))])
	_row(vb, [_button("Other hand on the bat (G)", _do.bind(func(): B.grip = not B.grip)),
		_button("Save grip as standard", _save_grip, "the bat's place in the hand + the fingers become the grip 'Bat in hand' uses")])
	vb.add_child(_label("[ ] slide the other hand along the shaft,  , . slide the main hand,  - = change the length", 13, Color(1, 1, 1, 0.55), true))
	_section(vb, "NUMBERS")
	ui_math_btn = _button("Show the math (for Claude)", func(): ui_math.visible = not ui_math.visible)
	vb.add_child(ui_math_btn)
	ui_math = _label("", 12, Color(1, 1, 1, 0.6), true)
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
	bh.add_child(_label("3  SCENE  (clips)", 19, Color(0.6, 0.78, 1.0)))
	bh.add_child(_label("your clips in a row; Play and the body moves from clip to clip on its own", 14, Color(1, 1, 1, 0.6)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp)
	ui_scene_name = LineEdit.new()
	ui_scene_name.placeholder_text = "scene name"
	ui_scene_name.custom_minimum_size = Vector2(160, 0)
	bh.add_child(ui_scene_name)
	bh.add_child(_button("Save scene", _save_scene))
	ui_scenes = OptionButton.new()
	ui_scenes.focus_mode = Control.FOCUS_NONE
	ui_scenes.custom_minimum_size = Vector2(170, 0)
	bh.add_child(ui_scenes)
	bh.add_child(_button("Open scene", func():
		if ui_scenes.selected >= 0:
			_load_scene(ui_scenes.get_item_metadata(ui_scenes.selected))
			_rebuild_cards()
			_refresh()))
	bh.add_child(_button("Delete scene", _delete_scene, "the scene picked in the list: press twice (it goes to the trash folder)"))
	bh.add_child(_button("New empty scene", func(): S = Scene.new(); sel_card = -1; playhead = 0.0; _rebuild_cards()))
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
	ph.add_theme_constant_override("separation", 8)
	bv.add_child(ph)
	ui_play = _button("  Play (Space)  ", _toggle_play)
	ph.add_child(ui_play)
	ph.add_child(_button("Slower", _speed.bind(1.1), "10% slower: the picked card, or the whole scene with no card picked (Save scene keeps it)"))
	ph.add_child(_button("Faster", _speed.bind(1.0 / 1.1), "10% faster: the picked card, or the whole scene with no card picked (Save scene keeps it)"))
	ui_time = HSlider.new()
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
	ph.add_child(_label("tween", 14, Color(1, 1, 1, 0.75)))
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
	ph.add_child(_button("Check", _check, "grade the scene against real recorded human motion (docs/MOTION_RULES.md); click a problem to jump to it"))
	ph.add_child(_button("Polish", _polish, "smooth the scene and add the in-between detail (~30 cards) into a NEW scene; yours is not touched"))
	ph.add_child(_button("Fix moves through the body", _clear_scene,
		"where a move between two cards passes an arm or the bat through the body, add a pass-by card that goes around"))

	# ---- status line
	ui_status = _label("Click a body part to select it.  Drag it to rotate.  Click a pose on the left to start from it.", 16, Color(1.0, 0.9, 0.55), true)
	ui_status.anchor_top = 1.0
	ui_status.anchor_bottom = 1.0
	ui_status.offset_top = -BOTTOM_H - 48
	ui_status.offset_bottom = -BOTTOM_H - 8
	ui_status.offset_left = LEFT_W + 12
	ui_status.anchor_right = 1.0
	ui_status.offset_right = -RIGHT_W - 12
	ui_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	ui_status.add_theme_stylebox_override("normal", sb)
	ui_root.add_child(ui_status)

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
	ui_help = PanelContainer.new()
	ui_help.anchor_left = 0.5
	ui_help.anchor_right = 0.5
	ui_help.offset_left = -360
	ui_help.offset_right = 360
	ui_help.offset_top = TOP_H + 30
	ui_root.add_child(ui_help)
	var hv := VBoxContainer.new()
	hv.custom_minimum_size = Vector2(700, 0)
	ui_help.add_child(hv)
	hv.add_child(_label("HOW IT WORKS", 22, Color(0.6, 0.78, 1.0)))
	hv.add_child(_label("1  POSE THE BODY.  Click a part, drag it.  Or use the sliders on the right, which say what each one does.  The body stops at real joint limits (yellow) and where parts meet (red).  Drag a hand or a foot and the whole arm or leg follows.  Ctrl+Z undoes.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("2  SAVE IT.  Type a name on the left, 'Save body as a pose'.  It joins the list; click it any time to get it back.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("3  MAKE A SCENE.  Put the body in a pose, CLIP this pose: it becomes a clip at the bottom.  Pose the next moment, add it.  Each card says how long the body takes to get there ('move', auto = the poser picks a natural time) and how long it stays ('hold').", 16, Color(1, 1, 1), true))
	hv.add_child(_label("4  PLAY.  The body moves from card to card on its own: the hips lead, the hands arrive last.  'Fix moves through the body' adds a pass-by card where an arm or the bat would go through the body.  Click a card to see that moment; change the body, then 'Update' on the card.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("5  SEE THE MOTION.  T = motion trail: the weapon tip's path, one dot per frame (far apart = fast), blue slow to red fast, white = the cards.  Shift+T = a trail on the part you clicked (feet, hands, head, hips: as many as you like).  O = onion skin: the card before (orange) and after (green) as ghosts.  'tween' slider: the picked card becomes a mix of its two neighbours (past the ends = overshoot); '+ tween' adds an in-between card.  'Smooth (spline)': one curve through every card, only holds stop.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("6  ANIMATOR TOOLS (top bar, ANIMATE tab).  Shift+M = mirror the whole pose left <-> right (the weapon changes hands).  Mirror the scene = a left-handed copy saved in _wip.  Shift+O = spacing ghosts: where the arms and weapon are every 0.1 s around the playhead; bunched = slow, a wide fan = fast.  Y = speed graph: tip, hips and head speed over the whole scene, click it to jump there.  Stepped preview = poses only, no in-betweens (blocking).  Moving holds = a held pose keeps drifting slightly toward the next one instead of freezing.  Check also flags FOOT SLIDE: a planted foot creeping along the floor.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("7  TIMELINE (under the clips).  Each clip is a block: solid = moving into the pose, striped = holding it.  Drag a block's edge to change how long it takes (later clips slide along); a clip with no hold: drag its edge right to pull one out.  Shift = fine steps.  Click a block to jump to that clip; drag the ruler to scrub.  Grab a HAND or FOOT and drag: the limb follows; past its reach a yellow line shows where you are pulling it.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("TOP BAR = TABS.  POSE (reset, relax, mirror, collision), ANIMATE (trail, onion, spacing, speed graph, stepped, moving holds, the Animator tools menu), CHECK (check, polish, fix, the dummy), VIEW (the five views, big view).  A lit button = that tool is on.  Undo, Redo, Search and Help are always on the right.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("BROWSER (left panel, 2nd tab).  Every part of the body by name, folded like the body (torso, arms with their fingers, legs), the weapon, and the scene's clips.  Click one: selected, the same as clicking it in the view (a finger joint is one click here).  Click in the view and its row lights up.  CUBE (top right of the view): click a face to look from that side.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("RIGHT-CLICK a part (click, don't drag: right-DRAG still turns the view): a ring around the mouse.  Up = Reset, then clockwise: Snap 90, Copy to the other side, CLIP this pose, Pin a trail, Snap 45.  Click one; the middle or Esc cancels.", 16, Color(1, 1, 1), true))
	hv.add_child(_label("S = SEARCH.  Don't remember where something is?  Press S, type a word (mirror, trail, staff, slower...), Enter.  Every button and key is in it, with its shortcut.", 16, Color(1, 0.9, 0.5), true))
	hv.add_child(_label("View: ARROWS slide the view, Shift+ARROWS turn around the body, PageUp/PageDown or the wheel zoom, Tab = big view.  Mouse: right-drag = turn around, middle-drag = slide.", 15, Color(1, 1, 1, 0.7), true))
	hv.add_child(_button("Got it", func(): ui_help.visible = false))
	ui_help.visible = false
	# ---- CHECK: the findings panel (top right of the view)
	ui_find = PanelContainer.new()
	ui_find.offset_left = LEFT_W + 12   # the left edge of the view: the body (centre) stays in sight while you jump
	ui_find.offset_right = LEFT_W + 12 + 420
	ui_find.offset_top = TOP_H + 12
	var fst := StyleBoxFlat.new()
	fst.bg_color = Color(0.09, 0.1, 0.12, 0.94)
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
	ui_graph = Control.new()
	ui_graph.anchor_top = 1.0
	ui_graph.anchor_bottom = 1.0
	ui_graph.anchor_right = 1.0
	ui_graph.offset_left = LEFT_W + 12
	ui_graph.offset_right = -RIGHT_W - 12
	ui_graph.offset_bottom = -BOTTOM_H - 60
	ui_graph.offset_top = -BOTTOM_H - 60 - 120
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


# ---------------------------------------------------------------- the right panel

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
	if ui_timeline != null:
		ui_timeline.queue_redraw()
	ui_play.text = "  Stop (Space)  " if playing else "  Play (Space)  "
	_sync = false


func _panel_part() -> void:
	var v: Vector3 = B.ang[sel]
	var L: Dictionary = B.lim[sel]
	var lims: Array = B.at_limit(sel)
	ui_title.text = nice(sel).to_upper() + ("   (at its limit)" if not lims.is_empty() else "")
	ui_title.modulate = LIMIT if not lims.is_empty() else Color(1, 1, 1)
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
	ui_title.text = "METAL BAT  " + ("(locked in the %s)" % nice(B.wep_hand) if locked else "(free)")
	ui_title.modulate = Color(1, 1, 1)
	ui_how.text = ("LOCKED: the sliders shift the bat inside the hand.  Dragging the bat moves the hand.  'Free it' to move it alone." if locked
		else "FREE: drag = move it,  Shift+drag = turn it,  Alt+drag = spin it.  When it sits right in the fingers: 'Lock bat to hand'.")
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
	var span := 0.3 if locked else 2.0
	var names := ["bat left / right", "bat up / down", "bat forward / back"]
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

func _rebuild_cards() -> void:
	if ui_cards == null:
		return
	_dummy_hits()   # the cards changed: the landed scene and its hits too
	ov.mark_dirty()
	if ui_browser != null:
		ui_browser.refresh()
	for c in ui_cards.get_children():
		c.queue_free()
	_layout_bottom()
	if S.cards.is_empty():
		ui_cards.add_child(_label("No clips yet.  Pose the body (or click a pose on the left), then press  CLIP this pose.  Pose the next moment, clip it too, and press Play.", 16, Color(1, 1, 1, 0.55)))
	var ts := S.times()
	for i in S.cards.size():
		var c: Dictionary = S.cards[i]
		var pc := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.2, 0.36, 0.62) if i == sel_card else (Color(0.25, 0.2, 0.12) if c["name"] == "pass-by" else Color(0.16, 0.17, 0.2))
		st.set_corner_radius_all(6)
		st.set_content_margin_all(6)
		pc.add_theme_stylebox_override("panel", st)
		pc.custom_minimum_size = Vector2(196, 0)
		ui_cards.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		pc.add_child(v)
		var nb := _button("%d  %s" % [i + 1, c["name"]], _card_pick.bind(i), "show this moment (at %.2f s)" % ts[i][1])
		v.add_child(nb)
		if i > 0:
			var mh := HBoxContainer.new()
			v.add_child(mh)
			mh.add_child(_label("move", 13, Color(1, 1, 1, 0.7)))
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
		hh.add_child(_label("hold", 13, Color(1, 1, 1, 0.7)))
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


## the bottom panel's height follows the scene: no clips = the scene row and the hint, nothing else. Everything that
## stands on the panel (side panels' bottoms, the status line, the speed graph, the camera's centring) moves with it
func _layout_bottom() -> void:
	if ui_bp == null or ui_status == null or ui_graph == null or ui_timeline == null:   # mid-build
		return
	var empty := S.cards.is_empty()
	bottom_h = BOTTOM_EMPTY if empty else BOTTOM_H
	ui_card_row.custom_minimum_size.y = 26 if empty else 112
	ui_timeline.visible = not empty
	ui_play_row.visible = not empty
	ui_bp.offset_top = -bottom_h
	for p in ui_side:
		p.offset_bottom = -bottom_h - 6
	ui_status.offset_top = -bottom_h - 48
	ui_status.offset_bottom = -bottom_h - 8
	ui_graph.offset_bottom = -bottom_h - 60
	ui_graph.offset_top = -bottom_h - 60 - 120
	_cam()


## a key, as if pressed in the view: a command that has a key runs through the key's own code, so the two never differ
func _press(code: Key, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	_unhandled_input(k)


## everything S can find: each runs what its button / key runs. "also" = other words people would type for it
func _commands() -> Array:
	var c := []
	var add := func(n: String, keys: String, f: Callable, also := ""): c.append({"name": n, "keys": keys, "run": f, "also": also})
	for v in [["Front view", 1], ["His right view", 2], ["Top view", 3], ["Back view", 4], ["His left view", 5]]:
		add.call(v[0], str(v[1]), _press.bind(KEY_0 + v[1]), "camera look")
	add.call("Undo", "Ctrl+Z", _undo, "back")
	add.call("Redo", "Ctrl+Y", _redo)
	add.call("Save pose", "Ctrl+S", _save_pose, "store keep")
	add.call("CLIP this pose (add a card)", "Enter", _press.bind(KEY_ENTER), "key frame add new")
	add.call("Play / pause", "Space", _press.bind(KEY_SPACE), "run stop")
	add.call("Big view (hide the panels)", "Tab", _press.bind(KEY_TAB), "fullscreen")
	add.call("Reset the part", "R", _press.bind(KEY_R), "zero")
	add.call("Snap the part to 90", "Q", _press.bind(KEY_Q), "round")
	add.call("Snap the part to 45", "Shift+Q", _press.bind(KEY_Q, true), "round")
	add.call("Copy right side to left", "M", _press.bind(KEY_M), "mirror symmetry")
	add.call("Copy left side to right", "N", _press.bind(KEY_N), "mirror symmetry")
	add.call("Mirror the whole pose", "Shift+M", _press.bind(KEY_M, true), "flip left right")
	add.call("Mirror the scene (left-handed copy)", "", _tool.bind(5), "flip")
	add.call("Collision shapes on/off", "C", _press.bind(KEY_C), "capsules hit")
	add.call("Motion trail on/off", "T", _press.bind(KEY_T), "path arc")
	add.call("Pin a trail on the picked part", "Shift+T", _press.bind(KEY_T, true), "path arc")
	add.call("Onion skin on/off", "O", _press.bind(KEY_O), "ghost before after")
	add.call("Spacing ghosts on/off", "Shift+O", _press.bind(KEY_O, true), "ghost timing")
	add.call("Speed graph on/off", "Y", _press.bind(KEY_Y), "curve velocity")
	add.call("Stepped preview on/off", "", _tool.bind(3), "blocking poses")
	add.call("Moving holds on/off", "", _tool.bind(4), "drift")
	add.call("Check the motion", "", _check, "grade problems rules")
	add.call("Polish the scene (new copy)", "", _polish, "smooth detail")
	add.call("Fix moves through the body", "", _clear_scene, "collision pass")
	add.call("Add an in-between card", "", _tween_add, "tween")
	add.call("Slower (10%)", "", _speed.bind(1.1), "timing")
	add.call("Faster (10%)", "", _speed.bind(1.0 / 1.1), "timing")
	add.call("Save scene", "", _save_scene)
	add.call("New empty scene", "", func(): S = Scene.new(); sel_card = -1; playhead = 0.0; _rebuild_cards())
	add.call("Reset body", "", _do.bind(_reset_all), "t-pose")
	add.call("Arms down 25 deg", "", _do.bind(_arms_relaxed), "relax a-pose")
	add.call("Dummy on/off", "H", _press.bind(KEY_H), "target enemy mannequin")
	add.call("Dummy solid / see-through", "", _dummy_solid, "target")
	add.call("Dummy closer", "", _dummy_move.bind(-0.25), "target")
	add.call("Dummy farther", "", _dummy_move.bind(0.25), "target")
	add.call("Weapon: metal bat", "", _do.bind(_kind.bind("metal_bat")))
	add.call("Weapon: bo staff", "", _do.bind(_kind.bind("staff")))
	add.call("Weapon: long hammer", "", _do.bind(_kind.bind("long_hammer")))
	add.call("Weapon in right hand", "B", _do.bind(_bat_put.bind("hand_r")), "bat")
	add.call("Weapon in left hand", "", _do.bind(_bat_put.bind("hand_l")), "bat")
	add.call("Remove the weapon", "", _do.bind(_bat_remove), "bat none")
	add.call("Lock weapon to hand / free it", "L", _press.bind(KEY_L), "bat")
	add.call("Second hand on the weapon", "G", _press.bind(KEY_G), "two hands grip")
	add.call("Main hand to the end", "", _do.bind(_hand_to_end), "grip slide")
	add.call("Fingers: next shape", "F", _press.bind(KEY_F), "hand open fist")
	for side in [["r", "right"], ["l", "left"]]:
		for f in ["open", "grip", "fist"]:
			add.call("Fingers %s: %s" % [side[1], f], "", _do.bind(_fingers.bind(side[0], f)), "hand")
	add.call("Help", "", func(): ui_help.visible = not ui_help.visible, "how manual")
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
		_say("Mirror the scene needs a scene: at least two cards")
		return
	var keep := B.to_dict()
	var d := S.to_dict(B)
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for c in d["cards"]:
		M.from_dict(c["pose"])
		M.mirror_pose()
		c["pose"] = M.to_dict()
		if c.has("steps"):
			var st := {}
			for sd in c["steps"]:
				var v: Array = c["steps"][sd]
				st["_r" if sd == "_l" else "_l"] = [-float(v[0]), v[1], v[2]]
			c["steps"] = st
	B.from_dict(keep)
	var base := S.name.trim_suffix("_mirrored")
	d["scene"] = base + "_mirrored" if not S.name.ends_with("_mirrored") else base
	d["plan"] = "Mirror the scene (Body.mirror_pose on every card) from " + S.name
	var path := "res://scenes/_wip/%s.json" % d["scene"]
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
	g.draw_rect(Rect2(Vector2.ZERO, g.size), Color(0.07, 0.08, 0.1, 0.9))
	if c.is_empty() or c["t"].size() < 2:
		return
	var T: float = c["t"][-1]
	var font: Font = g.get_theme_default_font()
	var rows := [["tip", "tip" if c["armed"] else "wrist", Color(1.0, 0.55, 0.3)],
		["hips", "hips", Color(0.45, 0.75, 1.0)], ["head", "head", Color(0.75, 0.9, 0.5)]]
	var lw := 118.0
	var h := (g.size.y - 8.0) / rows.size()
	for r in rows.size():
		var y0 := 4.0 + h * r
		var s: Array = c[rows[r][0]]
		var top := 0.0
		for v in s:
			top = maxf(top, v)
		g.draw_string(font, Vector2(8, y0 + h * 0.5 + 6), "%s %.1f m/s" % [rows[r][1], top], HORIZONTAL_ALIGNMENT_LEFT, lw - 10, 13, Color(1, 1, 1, 0.8))
		g.draw_line(Vector2(lw, y0 + h - 2), Vector2(g.size.x - 8, y0 + h - 2), Color(1, 1, 1, 0.12), 1.0)
		var pts := PackedVector2Array()
		for i in s.size():
			var x := lw + (g.size.x - lw - 8.0) * float(c["t"][i]) / maxf(T, 1e-6)
			pts.append(Vector2(x, y0 + h - 2 - (h - 8) * (float(s[i]) / maxf(top, 1e-6))))
		g.draw_polyline(pts, rows[r][2], 2.0, true)
	# the rate it was read at: the scene's fps (the trail's pass). Check reads 60, where a fast arc reads FASTER (a 30 fps
	# chord cuts the corner: bo_spin's staff 81.9 here, 96.5 in Check), so the graph says so instead of disagreeing silently
	g.draw_string(font, Vector2(8, g.size.y - 4), "at %d fps%s" % [int(c.get("fps", 30)), "" if int(c.get("fps", 30)) >= 60 else " (Check: 60)"], HORIZONTAL_ALIGNMENT_LEFT, lw - 10, 11, Color(1, 1, 1, 0.45))
	for i in c["cards"].size():
		var x := lw + (g.size.x - lw - 8.0) * float(c["cards"][i]) / maxf(T, 1e-6)
		g.draw_line(Vector2(x, 2), Vector2(x, g.size.y - 2), Color(1, 1, 1, 0.18), 1.0)
		g.draw_string(font, Vector2(x + 2, 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))
	var px := lw + (g.size.x - lw - 8.0) * clampf(playhead / maxf(T, 1e-6), 0.0, 1.0)
	g.draw_line(Vector2(px, 0), Vector2(px, g.size.y), Color(1, 1, 1, 0.9), 2.0)


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
	if S.cards.size() < 2:
		_say("Check needs a scene: at least two cards")
		return
	if given != null:   # a Fix already checked the scene it left
		findings = given
		_sm = {}
	else:
		# the scene AS MADE, not the dummy's landed version (_ps): the impact stop is the dummy's physics, not the
		# animator's move, and a Fix edits S (10-14: grading SL made a fixed card's finding come back)
		_sm = Rulebook.sample(S, ov.GB)
		findings = Rulebook.check(S, ov.GB, _sm)
	for c in ui_find_list.get_children():
		ui_find_list.remove_child(c)   # detach now: queue_free alone leaves the old rows listed until the frame ends
		c.queue_free()
	var fails := findings.filter(func(f): return f["sev"] == "FAIL").size()
	var head := HBoxContainer.new()
	ui_find_list.add_child(head)
	var title := _label("CHECK  -  " + ("clean: nothing here breaks the rulebook" if findings.is_empty() else "%d to look at (%d must fix)" % [findings.size(), fails]), 18, Color(0.6, 0.85, 1.0) if findings.is_empty() else Color(1.0, 0.85, 0.5))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Close", func(): ui_find.visible = false))
	if not findings.is_empty():
		ui_find_list.add_child(_label("Click one to jump there.  Red = breaks a real human limit, yellow = looks off.", 13, Color(1, 1, 1, 0.6), true))
	for f in findings:
		var b := Button.new()
		b.text = "%s  %.2f s  card %d '%s'  -  %s
%s" % ["MUST FIX" if f["sev"] == "FAIL" else "look", f["t"], f["card"] + 1, S.cards[mini(f["card"], S.cards.size() - 1)]["name"], f["rule"], f["msg"]]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(380, 0)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if f["sev"] == "FAIL" else Color(1.0, 0.86, 0.5))
		b.pressed.connect(_goto_finding.bind(f))
		ui_find_list.add_child(b)
		var lbl := Fixer.label(f, S)
		if lbl != "":
			var fx := _button(lbl, _fix.bind(f))
			fx.add_theme_font_size_override("font_size", 14)
			ui_find_list.add_child(fx)
		else:
			ui_find_list.add_child(_label("   no automatic fix: " + ("two cards fight here; change one of them" if f["rule"] == "HITCH" else "the foot creeps between two cards' stances: give the cards the same foot spot, or step it on purpose" if f["rule"] == "FOOT SLIDE" else "it is in the poses; change the cards around it"), 12, Color(1, 1, 1, 0.5), true))
	# a ScrollContainer has no height of its own: size it to the list (up to most of the view), else it collapses to 0
	(ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(56.0 + 128.0 * findings.size(), 60.0, 440.0))
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
func _fix(f: Dictionary) -> void:
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
		_say("Polish needs a scene: at least two cards")
		return
	_say("polishing '%s'..." % S.name)
	await get_tree().process_frame
	await get_tree().process_frame
	var keep := B.to_dict()
	var C := Scene.new()
	C.from_dict(S.to_dict(B))
	B.from_dict(keep)
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
		_say("a scene needs at least 2 cards to play")
		return
	playing = not playing
	if playing and playhead >= _ps().length() - 0.01:
		playhead = 0.0
	_refresh()


func _clear_scene() -> void:
	var keep := B.to_dict()
	var n := S.clear(B)
	B.from_dict(keep)
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
	var nm := ui_pose_name.text.strip_edges().replace(" ", "_")
	var path := "res://moves/%s.json" % (nm if nm != "" else "pose_" + _stamp())
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
		_say("only your own poses can be renamed (the library + starter poses keep their names)")
		return
	var nm := ui_pose_name.text.strip_edges().replace(" ", "_")
	for bad in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]:
		nm = nm.replace(bad, "")
	if nm == "":
		_say("type the new name in the box above first")
		return
	var path := "res://moves/%s.json" % nm
	if FileAccess.file_exists(path):
		_say("a pose called '%s' already exists" % nm)
		return
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(old), ProjectSettings.globalize_path(path))
	if err != OK:
		_say("couldn't rename (error %d)" % err)
		return
	ui_pose_name.text = ""
	_lists()
	_say("renamed %s -> %s" % [old.get_file().get_basename(), nm])


## DELETE (Nick 10-13: "delete option should exist, let's stick with done creations only"). Nothing is erased: the file
## goes to res://trash/ (put it back by hand). A press asks, the second press on the same thing deletes. The library
## (poses/lib) is kept: the tools and the transition table read it.
var _del_armed := ""


func _trash(path: String) -> bool:
	if _del_armed != path:
		_del_armed = path
		_say("press Delete again to remove '%s' (it goes to the trash folder)" % path.get_file().get_basename())
		return false
	_del_armed = ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://trash"))
	var to := "res://trash/%s_%s.json" % [path.get_file().get_basename(), _stamp()]
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(to))
	if err != OK:
		_say("couldn't delete (error %d)" % err)
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
		_say("library poses stay (the tools use them)")
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
	var idx := [sel_card] if sel_card >= 0 and sel_card < S.cards.size() else range(S.cards.size())
	for i in idx:
		var c: Dictionary = S.cards[i]
		if i > 0:
			c["move"] = snappedf(maxf(0.04, S.move_time(i) * k), 0.01)
		c["hold"] = snappedf(float(c["hold"]) * k, 0.01)
	_rebuild_cards()
	_refresh()
	_say("%s %s: the scene is now %.2f s (Save scene keeps it)" % ["card '%s'" % S.cards[sel_card]["name"] if idx.size() == 1 and sel_card >= 0 else "whole scene", "slower" if k > 1.0 else "faster", _ps().length()])


func _load_pose(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d.has("keys") or d.has("cards"):
		_load_scene(path)
		return
	B.from_dict(d)
	B.capture_second()   # a pose with both hands on the shaft loads with both hands holding it


func _save_scene() -> void:
	if S.cards.is_empty():
		_say("the scene is empty")
		return
	var nm := ui_scene_name.text.strip_edges().replace(" ", "_")
	S.name = nm if nm != "" else "scene_" + _stamp()
	var keep := B.to_dict()
	var d := S.to_dict(B)
	B.from_dict(keep)
	_write("res://scenes/%s.json" % S.name, d)
	_lists()
	_refresh()
	_say("saved scene %s: %d cards, %.2f s, %d frames with parts inside each other" % [S.name, S.cards.size(), S.length(), d["bad_frames"].size()])


func _load_scene(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
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
	if ui_natural != null:
		ui_natural.set_pressed_no_signal(S.natural)   # the boxes show THIS scene's settings (10-14: they kept the last ones)
		ui_spline.set_pressed_no_signal(S.spline)
	ov.mark_dirty()
	_dummy_hits()
	sel_card = -1
	playhead = 0.0
	S.apply(B, 0.0)
