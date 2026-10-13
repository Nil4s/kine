## main.gd - the poser window: draws the Body (body.gd), mouse + keys, the panels. All math lives in body.gd / moves.gd.
##
## Mouse:  click a part = select;  drag it = swing that joint (its end follows the mouse);  Shift+drag = twist it;
##         drag a HAND or FOOT = the whole arm/leg follows (reach);  Alt+drag a hand/foot = turn only the wrist/ankle;
##         Ctrl+drag the hips = move the body;  right-drag = orbit;  middle-drag = pan;  wheel = zoom.
## Keys:   1 front 2 his right 3 top 4 back 5 his left | R reset joint | Q snap the joint to 90s (Shift+Q: 45s) |
##         M mirror R>L, N mirror L>R | T stick on/off | G left hand on the stick, [ ] slide it, - = stick length |
##         K add a key at the playhead | Del remove the key | Space play/stop | , . previous/next key |
##         C show the collision capsules | Ctrl+S save the pose
## Command line (after --): --pose <json> | --move <json> | --view <1-5> | --t <seconds> | --shot <png> (render, quit)
extends Node3D

const SEL := Color(0.25, 0.55, 1.0)
const LIMIT := Color(1.0, 0.82, 0.15)
const TOUCH := Color(1.0, 0.25, 0.2)

var B := Body.new()
var M := Moves.new()
var parts := {}          # part -> MeshInstance3D (its collision capsule): invisible click target + highlight
var mats := {}
var dots := {}
var skel: Skeleton3D     # the mannequin's own skeleton (assets/mannequin.glb, Quaternius UAL2, CC0)
var bone_idx := {}
var stick_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var show_caps := false
var sel := "upperarm_r"
var cam: Camera3D
var yaw := 0.0
var pitch := -8.0
var dist := 3.4
var target := Vector3(0, 1.0, 0)
var dragging := ""
var playhead := 0.0
var playing := false

var ui_name: Label
var ui_rows := {}
var ui_hips: VBoxContainer
var ui_hip_sliders := []
var ui_info: Label
var ui_poses: OptionButton
var ui_pose_name: LineEdit
var ui_moves: OptionButton
var ui_move_name: LineEdit
var ui_time: HSlider
var ui_keys: Label
var ui_key_t: SpinBox
var _sync := false


func _ready() -> void:
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_world()
	_body()
	_ui()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--pose")
	if i >= 0 and i + 1 < args.size():
		_load_pose(args[i + 1])
	i = args.find("--move")
	if i >= 0 and i + 1 < args.size():
		_load_move(args[i + 1])
	i = args.find("--t")
	if i >= 0 and i + 1 < args.size():
		playhead = float(args[i + 1])
		M.apply(B, playhead)
	i = args.find("--view")
	if i >= 0 and i + 1 < args.size():
		_view(int(args[i + 1]))
	_refresh()
	i = args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		var path: String = args[i + 1]
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()


func _process(dt: float) -> void:
	if playing and not M.keys.is_empty():
		playhead += dt
		if playhead > M.length():
			playhead = 0.0
		M.apply(B, playhead)
		_refresh()


# ---------------------------------------------------------------- scene

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
	for lab in [["+X his left", Vector3(0.65, 0.01, 0), Color(0.9, 0.4, 0.4)], ["+Z forward", Vector3(0, 0.01, 0.65), Color(0.4, 0.6, 1.0)]]:
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
	for j in Body.ORDER + ["stick", "stick_head"]:
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
		if j.begins_with("stick"):
			continue
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.013
		sm.height = 0.026
		d.mesh = sm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.15, 0.15, 0.18)
		dm.no_depth_test = true
		dm.render_priority = 1
		d.material_override = dm
		add_child(d)
		dots[j] = d
	# the stick you see: a dark shaft and a heavier head
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.31, 0.34)
	metal.metallic = 0.7
	metal.roughness = 0.35
	stick_mesh = MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = Body.STICK_R
	cy.bottom_radius = Body.STICK_R
	stick_mesh.mesh = cy
	stick_mesh.material_override = metal
	add_child(stick_mesh)
	head_mesh = MeshInstance3D.new()
	var hy := CylinderMesh.new()
	hy.top_radius = Body.HEAD_R
	hy.bottom_radius = Body.HEAD_R
	head_mesh.mesh = hy
	head_mesh.material_override = metal
	add_child(head_mesh)


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
		if not B.stick and ((pr[0] as String).begins_with("stick") or (pr[1] as String).begins_with("stick")):
			continue
		if B.depth(pr[0], pr[1]) - float(B.allow.get(pr[0] + "|" + pr[1], 0.0)) > -0.0015:   # stopped against it, or in
			touching[pr[0]] = true
			touching[pr[1]] = true
	for j in Body.ORDER + ["stick", "stick_head"]:
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
			col = Color(SEL.lerp(col, 0.4) if col.a > 0.3 else SEL, 0.42)
		mats[j].albedo_color = col
		parts[j].visible = col.a > 0.0 and (B.stick or not j.begins_with("stick"))
	stick_mesh.visible = B.stick
	head_mesh.visible = B.stick
	if B.stick:
		var s: Array = B.cap("stick")
		var h: Array = B.cap("stick_head")
		_place(stick_mesh, s[0], s[1], Body.STICK_R, false)
		_place(head_mesh, h[0], h[1], Body.HEAD_R, false)
	_panel()


# ---------------------------------------------------------------- camera

func _cam() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	cam.transform = Transform3D(b, target + b * Vector3(0, 0, dist))


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
	for j in Body.ORDER:
		var c: Array = B.cap(j)
		var res := _ray_seg(o, d, c[0], c[1])
		if res.y <= float(B.rad[j]) * 1.15 and res.x < best_t:
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
					sel = j
					dragging = "joint"
					playing = false
					_refresh()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				dragging = "orbit"
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				dragging = "pan"
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				dist = maxf(0.6, dist * 0.9)
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
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		match k.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_view(k.keycode - KEY_0)
			KEY_R:
				if sel == "pelvis":
					B.offset = Vector3.ZERO
				B.set_ang_safe(sel, Vector3.ZERO)
				_after_edit()
			KEY_Q:
				_snap(45.0 if k.shift_pressed else 90.0)
			KEY_M:
				B.mirror_side("_r")
				_after_edit()
			KEY_N:
				B.mirror_side("_l")
				_after_edit()
			KEY_C:
				show_caps = not show_caps
				_refresh()
			KEY_T:
				B.stick = not B.stick
				_after_edit()
			KEY_G:
				B.grip = not B.grip
				_after_edit()
			KEY_BRACKETLEFT:
				B.grip_u = clampf(B.grip_u - 0.05, 0.0, 1.0)
				_after_edit()
			KEY_BRACKETRIGHT:
				B.grip_u = clampf(B.grip_u + 0.05, 0.0, 1.0)
				_after_edit()
			KEY_MINUS:
				B.set_stick_len(B.stick_len - 0.05)
				_after_edit()
			KEY_EQUAL:
				B.set_stick_len(B.stick_len + 0.05)
				_after_edit()
			KEY_K:
				_add_key()
			KEY_DELETE:
				_del_key()
			KEY_SPACE:
				playing = not playing
			KEY_COMMA:
				_step_key(-1)
			KEY_PERIOD:
				_step_key(1)
			KEY_S:
				if k.ctrl_pressed:
					_save_pose()


func _drag_joint(rel: Vector2, twist: bool, move: bool, alt: bool) -> void:
	var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / get_viewport().get_visible_rect().size.y
	var dw: Vector3 = cam.global_basis.x * rel.x * mpp - cam.global_basis.y * rel.y * mpp
	var tip := sel in ["hand_r", "hand_l", "foot_r", "foot_l"]
	if sel == "pelvis" and move:
		B.offset += dw
		B.fk()
	elif twist:
		var v: Vector3 = B.ang[sel]
		B.set_ang_safe(sel, Vector3(v.x, v.y, v.z + rel.x * 0.5))
	elif tip and not alt:
		# the whole arm/leg follows the wrist/ankle (body.gd reach)
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


## snap the selected joint's free angles to the nearest multiple of 90 (or 45) the range allows; it stops at contact
func _snap(step: float) -> void:
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
	_after_edit()


func _after_edit() -> void:
	B.apply_grip()
	_refresh()


# ---------------------------------------------------------------- panels

func _label(t: String, size := 14) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(t: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(f)
	return b


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# ---- right: the selected joint
	var pc := PanelContainer.new()
	pc.anchor_left = 1.0
	pc.anchor_right = 1.0
	pc.offset_left = -400
	pc.offset_right = -10
	pc.offset_top = 10
	layer.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	pc.add_child(vb)
	ui_name = _label("", 22)
	vb.add_child(ui_name)
	for k in ["bend", "side", "twist"]:
		var l := _label("", 14)
		l.custom_minimum_size = Vector2(370, 0)
		vb.add_child(l)
		var s := HSlider.new()
		s.step = 0.5
		s.custom_minimum_size = Vector2(370, 22)
		s.value_changed.connect(_on_slider.bind(k))
		vb.add_child(s)
		ui_rows[k] = {"slider": s, "label": l}
	ui_hips = VBoxContainer.new()
	vb.add_child(ui_hips)
	for k in 3:
		var l := _label("", 14)
		ui_hips.add_child(l)
		var s := HSlider.new()
		s.min_value = -1.0 if k != 1 else -0.9
		s.max_value = 1.0 if k != 1 else 0.4
		s.step = 0.005
		s.custom_minimum_size = Vector2(370, 22)
		s.value_changed.connect(_on_hip.bind(k))
		ui_hips.add_child(s)
		ui_hip_sliders.append([s, l])
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(_button("Reset joint", func(): B.set_ang_safe(sel, Vector3.ZERO); _after_edit()))
	hb.add_child(_button("Snap 90", func(): _snap(90.0)))
	hb.add_child(_button("Snap 45", func(): _snap(45.0)))
	hb.add_child(_button("Reset all", _reset_all))
	var hb2 := HBoxContainer.new()
	vb.add_child(hb2)
	hb2.add_child(_button("Mirror R>L", func(): B.mirror_side("_r"); _after_edit()))
	hb2.add_child(_button("Mirror L>R", func(): B.mirror_side("_l"); _after_edit()))
	hb2.add_child(_button("Stick", func(): B.stick = not B.stick; _after_edit()))
	hb2.add_child(_button("2-hand grip", func(): B.grip = not B.grip; _after_edit()))
	ui_info = _label("", 12)
	ui_info.custom_minimum_size = Vector2(370, 0)
	vb.add_child(ui_info)
	# ---- left: poses and moves
	var lp := PanelContainer.new()
	lp.offset_left = 10
	lp.offset_top = 70
	layer.add_child(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 5)
	lp.add_child(lv)
	lv.add_child(_label("POSES", 16))
	ui_poses = OptionButton.new()
	ui_poses.custom_minimum_size = Vector2(300, 0)
	ui_poses.focus_mode = Control.FOCUS_NONE
	lv.add_child(ui_poses)
	var ph := HBoxContainer.new()
	lv.add_child(ph)
	ph.add_child(_button("Load pose", func():
		if ui_poses.selected >= 0:
			_load_pose(ui_poses.get_item_metadata(ui_poses.selected))
			_refresh()))
	ui_pose_name = LineEdit.new()
	ui_pose_name.placeholder_text = "name"
	ui_pose_name.custom_minimum_size = Vector2(110, 0)
	ph.add_child(ui_pose_name)
	ph.add_child(_button("Save pose", _save_pose))
	lv.add_child(_label("MOVE (animation / transition)", 16))
	ui_moves = OptionButton.new()
	ui_moves.focus_mode = Control.FOCUS_NONE
	lv.add_child(ui_moves)
	var mh := HBoxContainer.new()
	lv.add_child(mh)
	mh.add_child(_button("Load move", func():
		if ui_moves.selected >= 0:
			_load_move(ui_moves.get_item_metadata(ui_moves.selected))
			_refresh()))
	mh.add_child(_button("New", func(): M = Moves.new(); playhead = 0.0; _refresh()))
	ui_move_name = LineEdit.new()
	ui_move_name.placeholder_text = "move name"
	ui_move_name.custom_minimum_size = Vector2(100, 0)
	mh.add_child(ui_move_name)
	mh.add_child(_button("Save move", _save_move))
	var kh := HBoxContainer.new()
	lv.add_child(kh)
	kh.add_child(_label("key at", 14))
	ui_key_t = SpinBox.new()
	ui_key_t.step = 0.05
	ui_key_t.max_value = 30.0
	ui_key_t.suffix = "s"
	kh.add_child(ui_key_t)
	kh.add_child(_button("Add key (K)", _add_key))
	kh.add_child(_button("Delete key", _del_key))
	var th := HBoxContainer.new()
	lv.add_child(th)
	th.add_child(_button("< key", func(): _step_key(-1)))
	th.add_child(_button("Play / Stop", func(): playing = not playing))
	th.add_child(_button("key >", func(): _step_key(1)))
	ui_time = HSlider.new()
	ui_time.step = 0.01
	ui_time.custom_minimum_size = Vector2(300, 22)
	ui_time.value_changed.connect(func(v):
		if _sync:
			return
		playhead = v
		playing = false
		M.apply(B, playhead)
		_refresh())
	lv.add_child(ui_time)
	ui_keys = _label("", 12)
	ui_keys.custom_minimum_size = Vector2(300, 0)
	lv.add_child(ui_keys)
	var help := _label("click = select | drag = swing | Shift+drag = twist | drag a hand/foot = whole limb (Alt: wrist/ankle only) | Ctrl+drag hips = move\nright-drag orbit | middle-drag pan | wheel zoom | 1 front 2 right 3 top 4 back 5 left | Q snap 90 (Shift+Q 45) | R reset joint\nM/N mirror | T stick | G 2-hand grip, [ ] slide | - = stick length | K key, Del, Space play, , . keys | C capsules | Ctrl+S save", 12)
	help.position = Vector2(12, 8)
	help.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(help)
	_lists()


func _lists() -> void:
	ui_poses.clear()
	ui_moves.clear()
	for dir in ["res://poses", "res://moves"]:
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
			var box: OptionButton = ui_moves if txt.contains("\"keys\"") else ui_poses
			box.add_item(("* " if dir == "res://poses" else "") + f.get_basename())
			box.set_item_metadata(box.item_count - 1, path)


func _panel() -> void:
	if ui_name == null:
		return
	_sync = true
	var v: Vector3 = B.ang[sel]
	var L: Dictionary = B.lim[sel]
	var lims: Array = B.at_limit(sel)
	ui_name.text = sel + ("   [AT LIMIT: " + ", ".join(lims) + "]" if not lims.is_empty() else "")
	var vals := {"bend": v.x, "side": v.y, "twist": v.z}
	for k in ["bend", "side", "twist"]:
		var r: Vector2 = L[k]
		var row: Dictionary = ui_rows[k]
		row["slider"].min_value = r.x
		row["slider"].max_value = maxf(r.y, r.x + 0.001)
		row["slider"].value = vals[k]
		row["slider"].editable = r.y - r.x > 0.5
		row["label"].text = "%s  %.1f deg   (%s .. %s)   %s" % [k, vals[k], r.x, r.y, L["say"].get(k, "")]
	ui_hips.visible = sel == "pelvis"
	var names := ["hips left/right (x, m)", "hips up/down (y, m)", "hips forward/back (z, m)"]
	for k in 3:
		ui_hip_sliders[k][0].value = B.offset[k]
		ui_hip_sliders[k][1].text = "%s  %.3f" % [names[k], B.offset[k]]
	var A := B.compose(sel, v)
	var g: Quaternion = B.G[sel]
	var con: Array = B.contacts()
	ui_info.text = "A (turn from rest, rest axes)  %s\nG (turn from rest, now)  %s\njoint  %s\nend    %s\nbone t %s  bend axis %s  side axis %s\nstick %s  %.2f m  2-hand grip %s at %.2f\ncontacts inside: %s" % [
		_qs(A), _qs(g), _vs(B.P[sel]), _vs(B.E[sel]), _vs(B.t_ax[sel]), _vs(B.b_ax[sel]), _vs(B.a_ax[sel]),
		"on" if B.stick else "off", B.stick_len, "on" if B.grip else "off", B.grip_u,
		"none" if con.is_empty() else ", ".join(con.map(func(c): return "%s/%s %.0fmm" % [c[0], c[1], c[2] * 1000.0]))]
	ui_time.max_value = maxf(M.length(), 0.01)
	ui_time.value = playhead
	ui_key_t.value = playhead if not M.keys.is_empty() else 0.0
	var ks := M.keys.map(func(k): return "%.2fs" % k["t"])
	ui_keys.text = "%s: %d keys %s   playhead %.2fs" % [M.name, M.keys.size(), ", ".join(ks), playhead]
	_sync = false


static func _qs(q: Quaternion) -> String:
	return "(%.3f, %.3f, %.3f, %.3f)  %.1f deg" % [q.x, q.y, q.z, q.w, rad_to_deg(q.get_angle())]


static func _vs(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _on_slider(val: float, k: String) -> void:
	if _sync:
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
	B.offset[k] = val
	B.fk()
	_after_edit()


func _reset_all() -> void:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	_after_edit()


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
	ui_info.text = "saved " + ProjectSettings.globalize_path(path) + "\n" + ui_info.text
	_lists()


func _load_pose(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d.has("keys"):
		_load_move(path)
		return
	B.from_dict(d)


func _add_key() -> void:
	var t := ui_key_t.value if ui_key_t != null else playhead
	if M.keys.is_empty():
		t = 0.0
	elif absf(t - playhead) < 0.001 and t <= M.length():
		t = M.length() + 0.5   # the playhead on an old key: the new key goes half a second after the last
	M.add_key(t, B.to_dict())
	playhead = t
	_refresh()


func _del_key() -> void:
	for k in M.keys.size():
		if absf(M.keys[k]["t"] - playhead) < 0.02:
			M.keys.remove_at(k)
			break
	_refresh()


func _step_key(dir: int) -> void:
	if M.keys.is_empty():
		return
	var ts: Array = M.keys.map(func(k): return k["t"])
	var nxt := playhead
	if dir > 0:
		for t in ts:
			if t > playhead + 0.001:
				nxt = t
				break
	else:
		for i in range(ts.size() - 1, -1, -1):
			if ts[i] < playhead - 0.001:
				nxt = ts[i]
				break
	playhead = nxt
	playing = false
	M.apply(B, playhead)
	_refresh()


func _save_move() -> void:
	var nm := ui_move_name.text.strip_edges().replace(" ", "_")
	M.name = nm if nm != "" else "move_" + _stamp()
	var keep := playhead
	var d := M.to_dict(B)
	M.apply(B, keep)
	_write("res://moves/%s.json" % M.name, d)
	ui_info.text = "saved move %s: %d keys, %.2fs, %d frames with parts inside each other\n" % [M.name, M.keys.size(), M.length(), d["bad_frames"].size()] + ui_info.text
	_lists()


func _load_move(path: String) -> void:
	M = Moves.new()
	M.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	playhead = 0.0
	M.apply(B, 0.0)
