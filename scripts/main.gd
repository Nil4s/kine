## main.gd - the poser window: draws the Body (body.gd), mouse + keys, the side panel. All math lives in body.gd.
##
## Mouse:  left-click a body part = select it;  left-drag it = swing that joint (the part's end follows the mouse);
##         Shift + left-drag = twist it about its own length;  on the pelvis, Ctrl + left-drag = move the hips.
##         right-drag = orbit the camera;  middle-drag = pan;  wheel = zoom.
## Keys:   1 front  2 his right side  3 top  4 back  5 his left side;  R = reset the selected joint;
##         Ctrl+S = save the pose (moves/pose_<time>.json);  M = mirror right -> left;  N = mirror left -> right.
## Command line (after --):  --shot <png>  render one frame and quit;  --pose <json>  load a pose first;
##                           --view <1-5>   start from that view.
extends Node3D

const GREY := Color(0.62, 0.63, 0.66)
const SEL := Color(0.25, 0.55, 1.0)
const LIMIT := Color(1.0, 0.82, 0.15)

var B := Body.new()
var parts := {}          # joint -> MeshInstance3D (its capsule, joint -> end): invisible click target + highlight
var skel: Skeleton3D     # the mannequin's own skeleton (assets/mannequin.glb, Quaternius UAL2, CC0)
var bone_idx := {}       # joint -> bone index in skel
var show_caps := false   # C toggles the capsules (the collision shapes, step 2)
var mats := {}           # joint -> StandardMaterial3D
var dots := {}           # joint -> MeshInstance3D (a ball at the joint)
var sel := "upperarm_r"
var cam: Camera3D
var yaw := 0.0
var pitch := -8.0
var dist := 3.4
var target := Vector3(0, 1.0, 0)
var dragging := ""       # "" | "joint" | "orbit" | "pan"
var press_pos := Vector2.ZERO

var ui_name: Label
var ui_rows := {}        # "bend"/"side"/"twist" -> {slider, label}
var ui_hips: VBoxContainer
var ui_hip_sliders := []
var ui_info: Label
var _sync := false


func _ready() -> void:
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_world()
	_body()
	_ui()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--pose")
	if i >= 0 and i + 1 < args.size():
		B.from_dict(JSON.parse_string(FileAccess.get_file_as_string(args[i + 1])))
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
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-30, 200, 0)
	back.light_energy = 0.45
	add_child(back)
	# floor grid: 10 cm lines, every metre brighter; the X (his left) and Z (forward) axes coloured
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
	for j in Body.ORDER:
		var r: float = B.lim[j]["r"]
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = 1.0
		cm.radial_segments = 20
		cm.rings = 6
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = GREY
		m.roughness = 0.6
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_BACK
		mi.material_override = m
		add_child(mi)
		parts[j] = mi
		mats[j] = m
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


## a capsule from a to b with radius r: Godot's CapsuleMesh runs along its local Y, height includes the round ends
func _place(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var L := d.length()
	(mi.mesh as CapsuleMesh).height = maxf(L + 2.0 * r, 2.0 * r + 0.001)
	var y := d / L if L > 1e-6 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _refresh() -> void:
	# the skinned body: every bone gets the glTF local rotation the math says (body.gd gltf_local, MATH.md)
	for j in Body.ORDER:
		if bone_idx[j] >= 0:
			skel.set_bone_pose_rotation(bone_idx[j], B.gltf_local(j))
	if bone_idx["pelvis"] >= 0:
		skel.set_bone_pose_position(bone_idx["pelvis"], B.gltf_pelvis_pos())
	for j in Body.ORDER:
		var a: Vector3 = B.P[j]
		var b: Vector3 = B.E[j]
		if j == "pelvis":   # the hips: a bar between the two hip joints, not up the spine
			a = B.P["thigh_r"]
			b = B.P["thigh_l"]
		_place(parts[j], a, b, B.lim[j]["r"])
		dots[j].position = B.P[j]
		var c := Color(GREY, 0.25 if show_caps else 0.0)
		if not B.at_limit(j).is_empty():
			c = Color(LIMIT, 0.45)
		if j == sel:
			c = Color(SEL.lerp(LIMIT, 0.35) if c.a > 0.4 else SEL, 0.4)
		mats[j].albedo_color = c
		parts[j].visible = c.a > 0.0
	_panel()


# ---------------------------------------------------------------- camera

func _cam() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	cam.transform = Transform3D(b, target + b * Vector3(0, 0, dist))


func _view(k: int) -> void:
	pitch = -8.0
	match k:
		1: yaw = 0.0        # front: the camera on +Z looking at his face
		2: yaw = -90.0      # his right side (-X)
		3:
			yaw = 0.0
			pitch = -89.0   # top
		4: yaw = 180.0      # back
		5: yaw = 90.0       # his left side
	_cam()


# ---------------------------------------------------------------- picking + dragging

## the nearest body part under the mouse: ray against each capsule (segment + radius)
func _pick(mp: Vector2) -> String:
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var best := ""
	var best_t := INF
	for j in Body.ORDER:
		var a: Vector3 = B.P[j]
		var b: Vector3 = B.E[j]
		if j == "pelvis":
			a = B.P["thigh_r"]
			b = B.P["thigh_l"]
		var r: float = B.lim[j]["r"]
		var res := _ray_seg(o, d, a, b)
		if res.y <= r and res.x < best_t:
			best_t = res.x
			best = j
	return best


## closest approach of the ray o + d*s (s >= 0) to the segment a-b: Vector2(s along the ray, distance)
static func _ray_seg(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Vector2:
	var u := b - a
	var w := o - a
	var A := d.dot(d)
	var Bq := d.dot(u)
	var C := u.dot(u)
	var D := d.dot(w)
	var E := u.dot(w)
	var den := A * C - Bq * Bq
	var s := 0.0
	var t := 0.0
	if den > 1e-9:
		s = (Bq * E - C * D) / den
		t = (A * E - Bq * D) / den
	t = clampf(t, 0.0, 1.0)
	s = maxf(0.0, (u * t - w).dot(d) / A)
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
			_drag_joint(rel, mm.shift_pressed, mm.ctrl_pressed)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var k := ev as InputEventKey
		match k.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_view(k.keycode - KEY_0)
			KEY_R:
				if sel == "pelvis":
					B.offset = Vector3.ZERO
				B.set_ang(sel, Vector3.ZERO)
				_refresh()
			KEY_C:
				show_caps = not show_caps
				_refresh()
			KEY_M:
				B.mirror_side("_r")
				_refresh()
			KEY_N:
				B.mirror_side("_l")
				_refresh()
			KEY_S:
				if k.ctrl_pressed:
					_save()


## one mouse move while dragging the selected part. Metres per pixel at the target: 2*dist*tan(fov/2)/height
func _drag_joint(rel: Vector2, twist: bool, move: bool) -> void:
	var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / get_viewport().get_visible_rect().size.y
	var dw: Vector3 = cam.global_basis.x * rel.x * mpp - cam.global_basis.y * rel.y * mpp
	if sel == "pelvis" and move:
		B.offset += dw
		B.fk()
	elif twist:
		var v: Vector3 = B.ang[sel]
		B.set_ang(sel, Vector3(v.x, v.y, v.z + rel.x * 0.5))
	else:
		# swing: turn the joint so its end point follows the mouse. R turns (end - joint) onto (end + dw - joint)
		var p: Vector3 = B.P[sel]
		var e: Vector3 = B.E[sel]
		if sel == "pelvis":
			e = B.P["neck_01"]
		var r1 := e - p
		var r2 := r1 + dw
		var ax := r1.cross(r2)
		if ax.length() > 1e-9:
			B.turn_world(sel, Quaternion(ax.normalized(), r1.angle_to(r2)))
	_refresh()


# ---------------------------------------------------------------- panel

func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var pc := PanelContainer.new()
	pc.anchor_left = 1.0
	pc.anchor_right = 1.0
	pc.offset_left = -400
	pc.offset_right = -10
	pc.offset_top = 10
	layer.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	ui_name = Label.new()
	ui_name.add_theme_font_size_override("font_size", 22)
	vb.add_child(ui_name)
	for k in ["bend", "side", "twist"]:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		var l := Label.new()
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
	for b in [["Reset joint", func(): B.set_ang(sel, Vector3.ZERO); _refresh()],
			["Reset all", func(): _reset_all()], ["Mirror R>L", func(): B.mirror_side("_r"); _refresh()],
			["Save", func(): _save()]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.pressed.connect(b[1])
		bt.focus_mode = Control.FOCUS_NONE
		hb.add_child(bt)
	ui_info = Label.new()
	ui_info.add_theme_font_size_override("font_size", 13)
	ui_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_info.custom_minimum_size = Vector2(370, 0)
	vb.add_child(ui_info)
	var help := Label.new()
	help.text = "click a part = select | drag it = swing | Shift+drag = twist | Ctrl+drag hips = move\nright-drag orbit | middle-drag pan | wheel zoom | 1 front 2 right 3 top 4 back 5 left\nR reset joint | M mirror R>L | N mirror L>R | C show capsules | Ctrl+S save"
	help.add_theme_font_size_override("font_size", 13)
	help.position = Vector2(12, 10)
	help.modulate = Color(1, 1, 1, 0.7)
	layer.add_child(help)


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
	# the math for this joint, as it is now
	var A := B.compose(sel, v)
	var g: Quaternion = B.G[sel]
	ui_info.text = "A (turn from rest, rest axes)  %s\nG (turn from rest, now)  %s\njoint  %s\nend    %s\nbone t %s   bend axis %s   side axis %s" % [
		_qs(A), _qs(g), _vs(B.P[sel]), _vs(B.E[sel]), _vs(B.t_ax[sel]), _vs(B.b_ax[sel]), _vs(B.a_ax[sel])]
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
	B.set_ang(sel, v)
	_refresh()


func _on_hip(val: float, k: int) -> void:
	if _sync:
		return
	B.offset[k] = val
	B.fk()
	_refresh()


func _reset_all() -> void:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	_refresh()


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://moves"))
	var t := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path := "res://moves/pose_%s.json" % t
	var f := FileAccess.open(path, FileAccess.WRITE)
	var d := B.to_dict()
	d["note"] = "angles in degrees from rest (bend, side, twist; meaning in data/body_limits.json 'say'); A = the joint's turn in rest axes, G = its turn from rest in the world now (quaternions x,y,z,w); pos/end in metres, character space (+Y up, +Z forward, +X his left). Math: MATH.md"
	f.store_string(JSON.stringify(d, " "))
	f.close()
	ui_info.text = "saved " + ProjectSettings.globalize_path(path) + "\n" + ui_info.text
