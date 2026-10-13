## main.gd - the poser window: draws the Body (body.gd), mouse + keys, the panels. All math lives in body.gd / moves.gd.
##
## Mouse:  click a part = select;  drag it = ROTATE that joint (its end follows the mouse);  Shift+drag = ROLL it;
##         drag a HAND or FOOT = the whole arm/leg follows (reach);  Alt+drag a hand/foot = rotate only the wrist/ankle;
##         Ctrl+drag the hips = move the body;  click a finger = curl it with the sliders;
##         the BAT: free = drag moves it, Shift+drag turns it, Alt+drag spins it; locked = dragging it moves the hand.
##         right-drag = orbit;  middle-drag = pan;  wheel = zoom.
## Keys:   1 front 2 his right 3 top 4 back 5 his left | R reset joint | Q snap the joint to 90s (Shift+Q: 45s) |
##         M mirror R>L, N mirror L>R | B bat on/off | L lock the bat to the hand / free it | F fingers open/grip/fist |
##         G other hand on the bat, [ ] slide it | - = bat length | K key, Del, Space play, , . keys |
##         C show the collision capsules | Ctrl+S save the pose
## Command line (after --): --pose <json> | --move <json> | --view <1-5> | --t <seconds> | --focus <joint> (close-up)
##                           | --shot <png> (render, quit)
extends Node3D

const SEL := Color(0.25, 0.55, 1.0)
const LIMIT := Color(1.0, 0.82, 0.15)
const TOUCH := Color(1.0, 0.25, 0.2)
const ARMS_OUT := 25.0   # relaxed arms: degrees out from straight down

var B := Body.new()
var M := Moves.new()
var parts := {}          # part -> MeshInstance3D (its collision capsule): invisible click target + highlight
var mats := {}
var dots := {}
var skel: Skeleton3D     # the mannequin's own skeleton (assets/mannequin.glb, Quaternius UAL2, CC0)
var bone_idx := {}
var bat_handle: MeshInstance3D
var bat_barrel: MeshInstance3D
var bat_knob: MeshInstance3D
var tag: Label3D         # the selected part's plain name, floating over it
var shapes := ["open", "grip", "fist"]
var shape_i := {"l": 0, "r": 0}
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
var ui_how: Label
var ui_status: Label
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
	i = args.find("--focus")
	if i >= 0 and i + 1 < args.size():
		sel = args[i + 1]
		target = B.P[sel]
		dist = 0.55
		_cam()
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
	# the metal bat you see: a taped handle, a barrel that swells from the handle to full width, a knob
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.64, 0.68)
	metal.metallic = 0.85
	metal.roughness = 0.3
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.08, 0.08, 0.09)
	tape.roughness = 0.9
	bat_handle = MeshInstance3D.new()
	var hy := CylinderMesh.new()
	hy.top_radius = B.wep_r_handle
	hy.bottom_radius = B.wep_r_handle
	bat_handle.mesh = hy
	bat_handle.material_override = tape
	add_child(bat_handle)
	bat_barrel = MeshInstance3D.new()
	var by := CylinderMesh.new()
	by.top_radius = B.wep_r_barrel
	by.bottom_radius = B.wep_r_handle
	bat_barrel.mesh = by
	bat_barrel.material_override = metal
	add_child(bat_barrel)
	bat_knob = MeshInstance3D.new()
	var ky := CylinderMesh.new()
	ky.top_radius = B.wep_r_handle * 1.6
	ky.bottom_radius = B.wep_r_handle * 1.6
	bat_knob.mesh = ky
	bat_knob.material_override = tape
	add_child(bat_knob)
	tag = Label3D.new()
	tag.pixel_size = 0.0009
	tag.fixed_size = true
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.modulate = Color(0.55, 0.78, 1.0)
	tag.outline_size = 8
	add_child(tag)


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
		if B.depth(pr[0], pr[1]) - float(B.allow.get(pr[0] + "|" + pr[1], 0.0)) > -0.0015:   # stopped against it, or in
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
			col = Color(SEL.lerp(col, 0.4) if col.a > 0.3 else SEL, 0.42)
		mats[j].albedo_color = col
		parts[j].visible = col.a > 0.0 and (B.wep_on or not j in Body.WEAPON)
	for m in [bat_handle, bat_barrel, bat_knob]:
		m.visible = B.wep_on
	if B.wep_on:
		_place(bat_knob, B.wep_point(0.0), B.wep_point(0.012), 0.0, false)
		_place(bat_handle, B.wep_point(0.012), B.wep_point(B.wep_handle), 0.0, false)
		_place(bat_barrel, B.wep_point(B.wep_handle), B.wep_point(B.wep_len), 0.0, false)
	var c2: Array = B.cap(sel)
	tag.text = nice(sel)
	tag.position = ((c2[0] as Vector3) + (c2[1] as Vector3)) * 0.5 + Vector3(0, 0.12, 0)
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
			KEY_B:
				_bat_toggle()
			KEY_L:
				_bat_lock()
			KEY_F:
				_fingers()
			KEY_G:
				B.grip = not B.grip
				_after_edit()
			KEY_BRACKETLEFT:
				B.grip_u = clampf(B.grip_u - 0.03, 0.0, B.wep_len)
				_after_edit()
			KEY_BRACKETRIGHT:
				B.grip_u = clampf(B.grip_u + 0.03, 0.0, B.wep_len)
				_after_edit()
			KEY_MINUS:
				B.set_weapon_len(B.wep_len - 0.05)
				_after_edit()
			KEY_EQUAL:
				B.set_weapon_len(B.wep_len + 0.05)
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
	var v2: Vector3 = B.ang[sel]
	ui_status.text = "%s %s:  bend %.1f   side %.1f   roll %.1f" % [
		"ROLLING" if twist else ("MOVING" if move else "ROTATING"), nice(sel), v2.x, v2.y, v2.z]


## the bat. Locked: dragging it moves the hand that holds it. Free: drag = move it, Shift+drag = turn it (tilt toward
## the mouse), Alt+drag = spin it about its own length. It stops at the body.
func _drag_bat(rel: Vector2, dw: Vector3, turn: bool, spin: bool) -> void:
	if B.wep_hand != "":
		B.reach(B.wep_hand, (B.P[B.wep_hand] as Vector3) + dw)
		_after_edit()
		ui_status.text = "the bat is LOCKED to the %s: dragging it moves the hand (L frees it)" % nice(B.wep_hand)
		return
	if spin:
		var axis: Vector3 = (B.wep_rot * Vector3.UP).normalized()
		B.move_weapon(Vector3.ZERO, Quaternion(axis, deg_to_rad(rel.x * 0.6)))
		ui_status.text = "SPINNING the bat about its length"
	elif turn:
		var R := Quaternion(cam.global_basis.y, deg_to_rad(rel.x * 0.5)) * Quaternion(cam.global_basis.x, deg_to_rad(rel.y * 0.5))
		B.move_weapon(Vector3.ZERO, R)
		ui_status.text = "TURNING the bat about its knob"
	else:
		B.move_weapon(dw, Quaternion.IDENTITY)
		ui_status.text = "MOVING the bat"
	_after_edit()


func _bat_toggle() -> void:
	if B.wep_on:
		B.wep_on = false
		B.grip = false
		if sel in Body.WEAPON:
			sel = "hand_r"
	else:
		B.weapon_to_hand("hand_r")
		B.hand_shape("r", "grip")
		shape_i["r"] = 1
		sel = "bat_handle"
	_after_edit()


## lock the bat to the nearest hand where it is now, or free it
func _bat_lock() -> void:
	if not B.wep_on:
		return
	if B.wep_hand != "":
		B.unlock_weapon()
		ui_status.text = "bat FREE: drag it to fit it, then L to lock it to the hand"
	else:
		var mid := B.wep_point(B.wep_handle * 0.5)
		var h := "hand_r" if (B.E["hand_r"] as Vector3).distance_to(mid) <= (B.E["hand_l"] as Vector3).distance_to(mid) else "hand_l"
		B.lock_weapon(h)
		ui_status.text = "bat LOCKED to the %s: it now moves with the hand" % nice(h)
	_refresh()


## cycle the selected side's fingers: open -> grip -> fist
func _fingers() -> void:
	var side := "l" if sel.ends_with("_l") else "r"
	shape_i[side] = (shape_i[side] + 1) % shapes.size()
	B.hand_shape(side, shapes[shape_i[side]])
	ui_status.text = "%s hand: %s" % ["left" if side == "l" else "right", shapes[shape_i[side]]]
	_after_edit()


## a plain name for a part: "upperarm_r" -> "right upper arm"
static func nice(j: String) -> String:
	var names := {"pelvis": "hips", "spine_01": "lower back", "spine_02": "mid back", "spine_03": "chest",
		"neck_01": "neck", "head": "head", "clavicle": "shoulder blade", "upperarm": "upper arm", "lowerarm": "forearm",
		"hand": "hand (wrist)", "thigh": "thigh (hip joint)", "calf": "shin (knee)", "foot": "foot (ankle)", "ball": "toes",
		"bat_handle": "bat handle", "bat_barrel": "bat barrel"}
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
			return side + f + " " + ["", "base joint", "middle joint", "tip joint"][k]
	return side + names.get(base, base)


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
	var hb3 := HBoxContainer.new()
	vb.add_child(hb3)
	hb3.add_child(_button("Bat on/off (B)", _bat_toggle))
	hb3.add_child(_button("Lock/free bat (L)", _bat_lock))
	hb3.add_child(_button("Fingers (F)", _fingers))
	hb3.add_child(_button("2-hand (G)", func(): B.grip = not B.grip; _after_edit()))
	var hb4 := HBoxContainer.new()
	vb.add_child(hb4)
	hb4.add_child(_button("Arms relaxed 25 deg", _arms_relaxed))
	hb4.add_child(_button("Hands open", func(): B.hand_shape("l", "open"); B.hand_shape("r", "open"); _after_edit()))
	ui_how = _label("", 13)
	ui_how.custom_minimum_size = Vector2(370, 0)
	ui_how.modulate = Color(0.75, 0.9, 1.0)
	vb.add_child(ui_how)
	ui_info = _label("", 12)
	ui_info.custom_minimum_size = Vector2(370, 0)
	ui_info.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(ui_info)
	# ---- left: poses and moves
	var lp := PanelContainer.new()
	lp.offset_left = 10
	lp.offset_top = 66
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
	var help := _label("BODY: click = select | drag = rotate | Shift+drag = roll | drag a hand/foot = whole limb (Alt: wrist/ankle only) | Ctrl+drag hips = move\nBAT: B on/off | free: drag = move, Shift = turn, Alt = spin | L lock to hand / free | F fingers open/grip/fist | G 2-hand, [ ] slide | - = length\nVIEW: right-drag orbit | middle-drag pan | wheel zoom | 1 front 2 right 3 top 4 back 5 left    TOOLS: Q snap 90 (Shift+Q 45) | R reset | M/N mirror | K key, Space play | C capsules | Ctrl+S save", 12)
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.position = Vector2(12, 8)
	help.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(help)
	ui_status = _label("click a body part to select it", 18)
	ui_status.anchor_top = 1.0
	ui_status.anchor_bottom = 1.0
	ui_status.offset_top = -40
	ui_status.offset_left = 330
	ui_status.modulate = Color(1.0, 0.92, 0.6)
	layer.add_child(ui_status)
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
	if sel in Body.WEAPON:
		_panel_bat()
		_sync = false
		return
	var v: Vector3 = B.ang[sel]
	var L: Dictionary = B.lim[sel]
	var lims: Array = B.at_limit(sel)
	ui_name.text = nice(sel).to_upper() + ("   [AT LIMIT: " + ", ".join(lims) + "]" if not lims.is_empty() else "")
	ui_how.text = _how(sel)
	var vals := {"bend": v.x, "side": v.y, "twist": v.z}
	for k in ["bend", "side", "twist"]:
		var r: Vector2 = L[k]
		var row: Dictionary = ui_rows[k]
		row["slider"].min_value = r.x
		row["slider"].max_value = maxf(r.y, r.x + 0.001)
		row["slider"].value = vals[k]
		row["slider"].editable = r.y - r.x > 0.5
		var word: String = {"bend": "ROTATE", "side": "ROTATE (other way)", "twist": "ROLL"}[k]
		row["label"].text = "%s  %.1f deg   [%s .. %s]\n   %s" % [word, vals[k], r.x, r.y, L["say"].get(k, "")] if r.y - r.x > 0.5 else "%s: locked (this joint can't move that way)" % word
	ui_hips.visible = sel == "pelvis"
	var names := ["hips left/right (x, m)", "hips up/down (y, m)", "hips forward/back (z, m)"]
	for k in 3:
		ui_hip_sliders[k][0].value = B.offset[k]
		ui_hip_sliders[k][1].text = "%s  %.3f" % [names[k], B.offset[k]]
	var A := B.compose(sel, v)
	var g: Quaternion = B.G[sel]
	var con: Array = B.contacts()
	ui_info.text = "math (MATH.md): A turn from rest %s\nG turn now %s\njoint %s  end %s\nbat %s %s  2-hand %s at %.2f m\ncontacts inside: %s" % [
		_qs(A), _qs(g), _vs(B.P[sel]), _vs(B.E[sel]),
		"on" if B.wep_on else "off", ("locked to " + nice(B.wep_hand)) if B.wep_hand != "" else "free", "on" if B.grip else "off", B.grip_u,
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


## what the mouse does on this part, in words
func _how(j: String) -> String:
	if j == "pelvis":
		return "drag = tip the whole body | Shift+drag = turn it | Ctrl+drag = move it (or the 3 sliders below)"
	if j in ["hand_r", "hand_l"]:
		return "drag = the whole arm follows the wrist | Alt+drag = rotate only the wrist | Shift+drag = roll the hand | F = finger shape"
	if j in ["foot_r", "foot_l"]:
		return "drag = the whole leg follows the ankle | Alt+drag = rotate only the ankle | Shift+drag = roll the foot"
	if j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
		return "drag = curl this finger joint | sliders = exact | F on the hand = open/grip/fist for all fingers"
	return "drag = rotate (the far end follows the mouse) | Shift+drag = roll it about its own length | Q = snap to 90"


## the bat's panel: rotation and position, in the HAND's frame when locked (fit it in the fist) or the world when free
func _panel_bat() -> void:
	ui_name.text = "METAL BAT  (%.2f m)  %s" % [B.wep_len, ("locked to " + nice(B.wep_hand)) if B.wep_hand != "" else "free"]
	ui_how.text = ("LOCKED: the sliders fit the bat inside the hand (it stays there when the arm moves) | drag = move the hand | L = free it" if B.wep_hand != ""
		else "FREE: drag = move | Shift+drag = turn | Alt+drag = spin | sliders = exact | when it sits right in the fingers, L locks it to the hand")
	var q: Quaternion = B.wep_lrot if B.wep_hand != "" else B.wep_rot
	var pos: Vector3 = B.wep_lpos if B.wep_hand != "" else B.wep_pos
	var e: Vector3 = Basis(q).get_euler() * (180.0 / PI)
	var words := {"bend": "TILT forward/back (about X)", "side": "TURN left/right (about Y)", "twist": "TILT sideways (about Z)"}
	var vals := {"bend": e.x, "side": e.y, "twist": e.z}
	for k in ["bend", "side", "twist"]:
		var row: Dictionary = ui_rows[k]
		row["slider"].min_value = -180.0
		row["slider"].max_value = 180.0
		row["slider"].editable = true
		row["slider"].value = vals[k]
		row["label"].text = "%s  %.1f deg" % [words[k], vals[k]]
	ui_hips.visible = true
	var span := 0.3 if B.wep_hand != "" else 2.0
	var names := ["knob left/right (x, m)", "knob up/down (y, m)", "knob forward/back (z, m)"]
	for k in 3:
		var sl: HSlider = ui_hip_sliders[k][0]
		sl.min_value = -span if (k != 1 or B.wep_hand != "") else -0.2
		sl.max_value = span
		sl.value = pos[k]
		ui_hip_sliders[k][1].text = "%s  %.3f%s" % [names[k], pos[k], "  (in the hand)" if B.wep_hand != "" else ""]
	var x := B.wep_xform()
	ui_info.text = "knob %s  tip %s\nrotation %s\nother hand %s at %.2f m from the knob ([ ])" % [
		_vs(x[0]), _vs(B.wep_point(B.wep_len)), _qs(x[1]), "on" if B.grip else "off", B.grip_u]


func _bat_from_sliders() -> void:
	var e := Vector3(ui_rows["bend"]["slider"].value, ui_rows["side"]["slider"].value, ui_rows["twist"]["slider"].value) * (PI / 180.0)
	var q := Basis.from_euler(e).get_rotation_quaternion()
	var pos := Vector3(ui_hip_sliders[0][0].value, ui_hip_sliders[1][0].value, ui_hip_sliders[2][0].value)
	if B.wep_hand != "":
		B.wep_lrot = q
		B.wep_lpos = pos
	else:
		B.wep_rot = q
		B.wep_pos = pos
	_after_edit()


## both arms hanging relaxed, 25 deg out from the body (Nick: arms usually rest ~25 deg to the sides), elbows soft
func _arms_relaxed() -> void:
	for sd in ["_r", "_l"]:
		B.set_ang_safe("upperarm" + sd, Vector3(0, -90 + ARMS_OUT, 0))
		B.set_ang_safe("lowerarm" + sd, Vector3(10, 0, 0))
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
