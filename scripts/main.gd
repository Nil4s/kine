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
const BOTTOM_H := 262
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
var wep_mats := {}   # "metal" / "tape" / "wood" / "steel": the weapon's looks per kind
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
var ui_card_btns: Array = []
var _sync := false
var big_view := false
var clean := false          # recording: no highlights, no name tag
var ui_side: Array = []      # the panels Tab hides


func _ready() -> void:
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_world()
	_body()
	_ui()
	var args := OS.get_cmdline_user_args()
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
		S.apply(B, playhead)
	i = args.find("--view")
	if i >= 0 and i + 1 < args.size():
		_view(int(args[i + 1]))
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
		var n := int(ceil(S.length() * fps))
		for f in n + 1:
			playhead = float(f) / fps
			S.apply(B, playhead)
			_refresh()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/frame_%04d.png" % [dir, f])
		get_tree().quit()
		return
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
		if playhead > S.length():
			playhead = 0.0
		S.apply(B, playhead)
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
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	add_child(man)
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
		ap.queue_free()
	skel = man.find_children("*", "Skeleton3D", true, false)[0]
	for j in Body.ORDER:
		bone_idx[j] = skel.find_bone("Head" if j == "head" else j)
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.78, 0.72, 0.64)
		m.roughness = 0.55
		(mi as MeshInstance3D).material_override = m
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
	for j in Body.ORDER:
		if bone_idx[j] >= 0:
			skel.set_bone_pose_rotation(bone_idx[j], B.gltf_local(j))
	if bone_idx["pelvis"] >= 0:
		skel.set_bone_pose_position(bone_idx["pelvis"], B.gltf_pelvis_pos())
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
		cam.v_offset = (BOTTOM_H - TOP_H) * 0.5 * mpp * -1.0
	else:
		cam.h_offset = (RIGHT_W - LEFT_W) * 0.5 * mpp
		cam.v_offset = (BOTTOM_H - TOP_H) * 0.5 * mpp * -1.0


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
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var j := _pick(mb.position)
				if j != "":
					_push_undo()
					sel = j
					dragging = "joint"
					playing = false
					_refresh()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				dragging = "orbit"
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				dragging = "pan"
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				dist = maxf(0.5, dist * 0.9)
				_cam()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				dist = minf(12.0, dist / 0.9)
				_cam()
		else:
			dragging = ""
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
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_view(k.keycode - KEY_0)
			KEY_R: _do(func(): _reset_part())
			KEY_Q: _do(func(): _snap(45.0 if k.shift_pressed else 90.0))
			KEY_M: _do(func(): B.mirror_side("_r"))
			KEY_N: _do(func(): B.mirror_side("_l"))
			KEY_C:
				show_caps = not show_caps
				_refresh()
			KEY_B: _do(func(): _bat_put("hand_r") if not B.wep_on else _bat_remove())
			KEY_L: _do(func(): _bat_lock())
			KEY_F: _do(func(): _fingers_cycle())
			KEY_G: _do(func(): B.grip = not B.grip)
			KEY_BRACKETLEFT: _do(func(): B.grip_u = clampf(B.grip_u - 0.03, 0.0, B.wep_len))
			KEY_BRACKETRIGHT: _do(func(): B.grip_u = clampf(B.grip_u + 0.03, 0.0, B.wep_len))
			KEY_COMMA: _do(func(): B.slide_in_hand(-0.03))
			KEY_PERIOD: _do(func(): B.slide_in_hand(0.03))
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
		B.reach(sel, (B.P[sel] as Vector3) + dw)
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
		B.reach(B.wep_hand, (B.P[B.wep_hand] as Vector3) + dw)
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
	_cam()
	_say("big view: the side panels are hidden (Tab brings them back)" if big_view else "panels back")


func _push_undo() -> void:
	undo.append(B.to_dict())
	if undo.size() > 60:
		undo.pop_front()
	redo.clear()


func _undo() -> void:
	if undo.is_empty():
		_say("nothing to undo")
		return
	redo.append(B.to_dict())
	B.from_dict(undo.pop_back())
	_refresh()
	_say("undone")


func _redo() -> void:
	if redo.is_empty():
		return
	undo.append(B.to_dict())
	B.from_dict(redo.pop_back())
	_refresh()
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
		_say("bat LOCKED to the %s: it now moves with the hand" % nice(h))


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
	tb.add_child(_label("view (arrows move it):", 14, Color(1, 1, 1, 0.6)))
	for v in [["Front (1)", 1], ["His right (2)", 2], ["Top (3)", 3], ["Back (4)", 4], ["His left (5)", 5]]:
		tb.add_child(_button(v[0], _view.bind(v[1])))
	tb.add_child(VSeparator.new())
	tb.add_child(_button("Undo (Ctrl+Z)", _undo))
	tb.add_child(_button("Redo (Ctrl+Y)", _redo))
	tb.add_child(_button("Collision (C)", func(): show_caps = not show_caps; _refresh(),
		"see the capsules the body collides with. Yellow = a joint at its limit, red = touching another part"))
	tb.add_child(_button("Reset body", _do.bind(_reset_all)))
	tb.add_child(_button("Arms 25 deg", _do.bind(_arms_relaxed)))
	tb.add_child(_button("Big view (Tab)", _big_view, "hide the side panels so the body fills the screen"))
	tb.add_child(_button("? Help", func(): ui_help.visible = not ui_help.visible))

	# ---- left: poses
	var lp := PanelContainer.new()
	lp.offset_left = 6
	lp.offset_top = TOP_H + 6
	lp.offset_right = LEFT_W
	lp.anchor_bottom = 1.0
	lp.offset_bottom = -BOTTOM_H - 6
	ui_root.add_child(lp)
	ui_side.append(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	lp.add_child(lv)
	lv.add_child(_label("1  POSES", 19, Color(0.6, 0.78, 1.0)))
	lv.add_child(_label("Click a pose: the body takes it.", 14, Color(1, 1, 1, 0.65), true))
	ui_poses = ItemList.new()
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
	_row(lv, [_button("CLIP this pose  (Enter)", _card_add, "the body as it is now becomes the next clip in the scene below")])
	lv.add_child(_label("WEAPON  (in the right hand)", 14, Color(0.6, 0.78, 1.0)))
	_row(lv, [_button("Bat", _do.bind(_kind.bind("metal_bat")), "metal bat 0.84 m"), _button("Bo staff", _do.bind(_kind.bind("staff")), "staff 1.8 m")])
	_row(lv, [_button("Hammer", _do.bind(_kind.bind("long_hammer")), "long hammer 1.1 m"), _button("None", _do.bind(_bat_remove), "remove the weapon")])
	_row(lv, [_button("2nd hand on/off (G)", _do.bind(func(): B.grip = not B.grip), "the other hand on the shaft; [ ] slide it")])

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
	_row(vb, [_button("Main hand down the shaft (,)", _do.bind(B.slide_in_hand.bind(-0.03))),
		_button("Main hand up the shaft (.)", _do.bind(B.slide_in_hand.bind(0.03)))])
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
	bh.add_child(_button("New empty scene", func(): S = Scene.new(); sel_card = -1; playhead = 0.0; _rebuild_cards()))
	var cs := ScrollContainer.new()
	cs.custom_minimum_size = Vector2(0, 112)
	cs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(cs)
	ui_cards = HBoxContainer.new()
	ui_cards.add_theme_constant_override("separation", 8)
	cs.add_child(ui_cards)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 8)
	bv.add_child(ph)
	ui_play = _button("  Play (Space)  ", _toggle_play)
	ph.add_child(ui_play)
	ui_time = HSlider.new()
	ui_time.step = 0.01
	ui_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_time.custom_minimum_size = Vector2(0, 26)
	ui_time.value_changed.connect(func(v):
		if _sync:
			return
		playhead = v
		playing = false
		S.apply(B, playhead)
		_refresh())
	ph.add_child(ui_time)
	ui_time_lbl = _label("0.00 s", 15)
	ui_time_lbl.custom_minimum_size = Vector2(130, 0)
	ph.add_child(ui_time_lbl)
	ui_natural = CheckBox.new()
	ui_natural.text = "Natural movement"
	ui_natural.button_pressed = true
	ui_natural.focus_mode = Control.FOCUS_NONE
	ui_natural.tooltip_text = "ON: the hips start first and the hands arrive last, like a real body. OFF: everything moves together."
	ui_natural.toggled.connect(func(on): S.natural = on; S.apply(B, playhead); _refresh())
	ph.add_child(ui_natural)
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
	hv.add_child(_label("View: ARROWS slide the view, Shift+ARROWS turn around the body, PageUp/PageDown or the wheel zoom, Tab = big view.  Mouse: right-drag = turn around, middle-drag = slide.", 15, Color(1, 1, 1, 0.7), true))
	hv.add_child(_button("Got it", func(): ui_help.visible = false))
	ui_help.visible = false
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
	ui_time.max_value = maxf(S.length(), 0.01)
	ui_time.value = playhead
	ui_time_lbl.text = "%.2f / %.2f s" % [playhead, S.length()]
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
	for c in ui_cards.get_children():
		c.queue_free()
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
			ms.value_changed.connect(func(x): S.cards[i]["move"] = x if x > 0.0 else -1.0; _rebuild_cards(); _refresh())
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
		hs.value_changed.connect(func(x): S.cards[i]["hold"] = x; _refresh())
		hh.add_child(hs)
		var bh := HBoxContainer.new()
		v.add_child(bh)
		bh.add_child(_button("<", _card_move.bind(i, -1), "move this card earlier"))
		bh.add_child(_button(">", _card_move.bind(i, 1), "move this card later"))
		bh.add_child(_button("Update", _card_update.bind(i), "replace this card's pose with the body as it is now"))
		bh.add_child(_button("X", _card_del.bind(i), "delete this card"))


func _card_add() -> void:
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
	sel_card = i
	playing = false
	playhead = S.times()[i][1]
	Scene.put(B, Moves._flat(S.cards[i]["pose"]))
	_rebuild_cards()
	_refresh()
	_say("card %d '%s': change the body, then 'Update' on the card to keep it" % [i + 1, S.cards[i]["name"]])


func _card_update(i: int) -> void:
	S.cards[i]["pose"] = B.to_dict()
	if S.cards[i]["name"] == "pass-by":
		S.cards[i]["name"] = "pose %d" % (i + 1)
	_rebuild_cards()
	_say("card %d updated from the body" % (i + 1))


func _card_del(i: int) -> void:
	S.cards.remove_at(i)
	sel_card = mini(sel_card, S.cards.size() - 1)
	playhead = minf(playhead, S.length())
	_rebuild_cards()
	_refresh()


func _card_move(i: int, d: int) -> void:
	var j := i + d
	if j < 0 or j >= S.cards.size():
		return
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
	if playing and playhead >= S.length() - 0.01:
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


func _load_pose(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d.has("keys") or d.has("cards"):
		_load_scene(path)
		return
	B.from_dict(d)


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
	sel_card = -1
	playhead = 0.0
	S.apply(B, 0.0)
