class_name OwnRigUI
extends Node
## OWN RIG IN THE APP (ROADMAP_400 track J, lane L73): the data and maths are scripts/custom_rig.gd (L69), this is its face.
## Scene menu "Import rig (glTF)..." reads a non-human skeleton as the scene's own rig (Scene.own_rig, saved in the scene file).
##   drawn     every bone is a joint ball at its world position and a line to its parent, over everything (no depth test)
##   click     a left press within PICK_PX of a joint (else of a bone line) picks that bone; a press elsewhere is left to the view
##   rotate    the panel's X / Y / Z degrees turn the picked bone from its rest (one undo step each)
##   key       the Key button keeps the pose at the playhead's frame; moving the playhead plays the keys back (slerp between them)
##   body tools  the human-only tools (joint limits, contacts, retarget, pre-check) answer "not a human rig" on a rig that is not one
## The rig sits at the world origin, rest scale. The body is not hidden.

const PICK_PX := 10.0
const JOINT_R := 0.012
const COL := Color(0.95, 0.75, 0.2)
const COL_PICK := Color(0.2, 0.9, 1.0)
const COL_LINE := Color(0.95, 0.75, 0.2, 0.8)

var m: Node
var cur := ""
var nodes := {}              # bone name -> its joint ball (the test reads the positions)
var last_consumed := false   # did the last mouse press go to the rig (the test reads it)
var panel: PanelContainer
var gate_label: Label
var info: Label
var f_rot: Array = []        # three SpinBoxes: X, Y, Z degrees
var _root: Node3D
var _lines: MeshInstance3D
var _sphere: SphereMesh
var _mat := {}
var _scene_ref: Object = null
var _last_t := -1.0
var _syncing := false
var _sig := ""


func setup(main: Node) -> void:
	m = main
	_root = Node3D.new()
	_root.name = "own_rig_view"
	m.add_child(_root)
	_sphere = SphereMesh.new()
	_sphere.radius = JOINT_R
	_sphere.height = JOINT_R * 2.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	for k in ["n", "p"]:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.no_depth_test = true
		sm.render_priority = 100
		sm.albedo_color = COL if k == "n" else COL_PICK
		_mat[k] = sm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.no_depth_test = true
	lm.render_priority = 99
	lm.vertex_color_use_as_albedo = true
	_mat["l"] = lm
	_lines = MeshInstance3D.new()
	_lines.name = "bone_lines"
	_lines.material_override = lm
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(_lines)
	_build_panel()


func rig() -> Dictionary:
	return m.S.own_rig


func _fps() -> float:
	return float(rig().get("fps", 30.0))


func frame_now() -> int:
	return int(round(float(m.playhead) * _fps()))


## ---- import (the Scene menu); returns "" when done, else the reason
func import_ask() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.glb, *.gltf ; a skeleton (creature, animal, prop rig)"])
	fd.use_native_dialog = true
	fd.title = "Import a rig (glTF / GLB)"
	fd.file_selected.connect(func(p):
		var why := import_file(p)
		if why != "":
			m._say("could not import %s as a rig: %s" % [String(p).get_file(), why])
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


func import_file(path: String) -> String:
	var r := CustomRig.load_glb(path, 30.0)
	if not r["ok"]:
		return String(r["why"])
	if (r["names"] as Array).is_empty():
		return "it has no bones"
	m._step_hint = "Import rig"
	m._push_undo()
	m.S.own_rig = r
	_scene_ref = null   # a new rig: the pose is read from the keys again
	cur = String(r["names"][0])
	m._refresh()
	m._say("imported %s as its own rig: %d bones. %s Click a bone, turn it in the panel, Key it, then move the playhead." % [path.get_file(), (r["names"] as Array).size(), CustomRig.capabilities(r)])
	return ""


## ---- drawing (called from main's _refresh)
func draw() -> void:
	var r: Dictionary = rig()
	if r.is_empty() or not r.get("ok", false):
		_clear()
		panel.visible = false
		return
	if _scene_ref != m.S:
		_scene_ref = m.S
		_last_t = -1.0
	if float(m.playhead) != _last_t:
		_last_t = float(m.playhead)
		if not (r["keys"] as Dictionary).is_empty():
			r["pose"] = CustomRig.pose_at(r, float(frame_now()))
	if cur == "" or not (r["names"] as Array).has(cur):
		cur = String(r["names"][0]) if not (r["names"] as Array).is_empty() else ""
	panel.visible = true
	var g := CustomRig.globals(r, r["pose"])
	var names: Array = r["names"]
	var sig := ",".join(PackedStringArray(names))
	if nodes.size() != names.size() or sig != _sig:
		_clear()
		_sig = sig
		for n in names:
			var mi := MeshInstance3D.new()
			mi.mesh = _sphere
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(mi)
			nodes[n] = mi
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in names.size():
		var nd: MeshInstance3D = nodes[names[i]]
		nd.position = (g[i] as Transform3D).origin
		nd.material_override = _mat["p"] if names[i] == cur else _mat["n"]
		var p: int = r["parent"][i]
		if p >= 0:
			pts.append((g[p] as Transform3D).origin)
			pts.append((g[i] as Transform3D).origin)
			cols.append(COL_LINE)
			cols.append(COL_LINE)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var am := ArrayMesh.new()
	if pts.size() > 0:
		arr[Mesh.ARRAY_VERTEX] = pts
		arr[Mesh.ARRAY_COLOR] = cols
		am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	_lines.mesh = am
	_sync_panel()


func _clear() -> void:
	for n in nodes:
		(nodes[n] as Node).queue_free()
	nodes.clear()
	if _lines != null:
		_lines.mesh = null


## ---- picking
func _scr(p: Vector3) -> Vector2:
	var cam: Camera3D = m.cam
	return Vector2(INF, INF) if cam.is_position_behind(p) else cam.unproject_position(p)


static func _seg_px(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1e-9 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## the bone under the mouse: the nearest joint within PICK_PX, else the nearest bone line (it picks the child end's bone)
func pick_at(mp: Vector2) -> String:
	if rig().is_empty():
		return ""
	var best := PICK_PX
	var id := ""
	for n in nodes:
		var d := mp.distance_to(_scr((nodes[n] as Node3D).global_position))
		if d < best:
			best = d
			id = n
	if id != "":
		return id
	var names: Array = rig()["names"]
	for i in names.size():
		var p: int = rig()["parent"][i]
		if p < 0 or not nodes.has(names[i]) or not nodes.has(names[p]):
			continue
		var d := _seg_px(mp, _scr((nodes[names[p]] as Node3D).global_position), _scr((nodes[names[i]] as Node3D).global_position))
		if d < best:
			best = d
			id = names[i]
	return id


func input(ev: InputEvent) -> bool:
	last_consumed = false
	if rig().is_empty() or nodes.is_empty():
		return false
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var b := pick_at((ev as InputEventMouseButton).position)
		if b != "":
			cur = b
			draw()
			last_consumed = true
			return true
	return false


## ---- rotate, key
func rotate_deg(bone: String, e: Vector3) -> bool:
	if rig().is_empty() or not (rig()["names"] as Array).has(bone):
		return false
	m._step_hint = "Rotate rig bone"
	m._push_undo()
	CustomRig.set_pose(rig(), bone, Quaternion(Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))))
	draw()
	return true


func key_now() -> bool:
	if rig().is_empty():
		return false
	m._step_hint = "Key rig"
	m._push_undo()
	for n in rig()["names"]:   # a key holds EVERY bone: a bone left out of a key would hold the next key's value before it
		if not (rig()["pose"] as Dictionary).has(n):
			rig()["pose"][n] = Quaternion.IDENTITY
	CustomRig.key(rig(), frame_now())
	m._say("keyed the rig at frame %d (%d keys); move the playhead to play it back" % [frame_now(), (rig()["keys"] as Dictionary).size()])
	return true


## the human-only tools: on an own rig this says so and runs nothing
func body_tools_pressed() -> Dictionary:
	var r := CustomRig.human_tool(rig(), "precheck")
	gate_label.text = "Body tools: ready (human rig)" if r["ok"] else String(r["why"])
	return r


## ---- the panel
func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "own_rig_panel"
	panel.visible = false
	panel.position = Vector2(12, 96)
	panel.custom_minimum_size = Vector2(250, 0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Tok.c("panel")
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", bg)
	var vb := VBoxContainer.new()
	var title := Label.new()
	title.text = "Own rig"
	vb.add_child(title)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(240, 0)
	vb.add_child(info)
	var row := HBoxContainer.new()
	for i in 3:
		var sb := SpinBox.new()
		sb.name = "rot_" + ["x", "y", "z"][i]
		sb.min_value = -180
		sb.max_value = 180
		sb.step = 1
		sb.prefix = ["X ", "Y ", "Z "][i]
		sb.tooltip_text = "turn the picked bone about its own %s axis, degrees from its rest (one undo step)" % ["X", "Y", "Z"][i]
		sb.value_changed.connect(func(_v): _spin_changed())
		row.add_child(sb)
		f_rot.append(sb)
	vb.add_child(row)
	var kb := Button.new()
	kb.name = "btn_rig_key"
	kb.text = "Key at the playhead"
	kb.tooltip_text = "keep this pose at the playhead's frame; between two keys the rig is interpolated"
	kb.pressed.connect(key_now)
	vb.add_child(kb)
	var bt := Button.new()
	bt.name = "btn_rig_body_tools"
	bt.text = "Body tools (limits, contacts, retarget)"
	bt.tooltip_text = "the human-only tools: they run on a human rig, and say so on any other"
	bt.pressed.connect(body_tools_pressed)
	vb.add_child(bt)
	gate_label = Label.new()
	gate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gate_label.custom_minimum_size = Vector2(240, 0)
	vb.add_child(gate_label)
	panel.add_child(vb)
	m.ui_root.add_child(panel)


func _spin_changed() -> void:
	if _syncing or cur == "":
		return
	rotate_deg(cur, Vector3((f_rot[0] as SpinBox).value, (f_rot[1] as SpinBox).value, (f_rot[2] as SpinBox).value))


func _sync_panel() -> void:
	if info == null or rig().is_empty():
		return
	info.text = "%s  (%d bones, frame %d, %d keys)" % [cur, (rig()["names"] as Array).size(), frame_now(), (rig()["keys"] as Dictionary).size()]
	var q: Quaternion = (rig()["pose"] as Dictionary).get(cur, Quaternion.IDENTITY)
	var e := Basis(q).get_euler()
	_syncing = true
	for i in 3:
		(f_rot[i] as SpinBox).value = snappedf(rad_to_deg(e[i]), 0.01)
	_syncing = false
