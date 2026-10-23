class_name BoneEditUI
extends Node
## "Rig: bone editor" (ROADMAP_400 J01; the data and the maths are scripts/bone_editor.gd). Your own bones on the body:
## drawn as octahedral bones (Blender's shape: a short wide part at the head, tapering to the tail), coloured by how many of
## your bones are above them (Tok s_hips, s_head, s_tip, sg_motion, sg_phase, then again); the picked one in Tok focus.
## They are drawn whenever the scene has some; the editor itself (keys, handles, panel) only while it is open:
##   click        pick a bone (yours, a words-made chain's, or one of the body's own joints as a parent / extrude source)
##   drag the head or tail ball of a picked bone   move that end at rest (on the plane facing the camera; one undo step)
##   E            extrude: a child from the picked bone's tail, the same way on, attached to it, and picked (one step)
##   Shift+A      add a 10 cm bone under the picked bone, from its tail, pointing up (one step)
##   X / Delete   delete the picked bone: its children hang on its parent, where they are (one step)
##   Tab          pick the next of your bones          Esc  close the editor          Ctrl+Z / Ctrl+Y  undo / redo (the app's)
## The panel (left): your bones, and the picked one's name, parent, length (cm) and roll (degrees); each change is one undo step.
## The body's own UE5 bones are not edited here (see bone_editor.gd). A words-made chain (J24: "add a tail with 8 bones") is
## picked like the rest; its first edit turns the whole chain into bones of yours, in that same undo step (the words "curl the
## tail 40" then no longer reach it: it is yours to edit).

const DEPTH_TOK := ["s_hips", "s_head", "s_tip", "sg_motion", "sg_phase"]
const PICK_PX := 10.0
const HANDLE_PX := 12.0

var m: Node
var on := false
var cur := ""              # the pick: one of your bones, a core joint, or "rigx:<chain>:<bone>"
var nodes := {}            # your bone's name -> its drawn MeshInstance3D (the test reads them)
var handles: Array = []    # [head ball, tail ball]
var panel: PanelContainer
var list: ItemList
var f_name: LineEdit
var f_parent: OptionButton
var f_len: SpinBox
var f_roll: SpinBox
var info: Label
var _root: Node3D
var _octa: ArrayMesh
var _mats := {}
var _drag := {}
var _sig := ""
var _list_ids: Array = []
var _parent_ids: Array = []


func setup(main: Node) -> void:
	m = main
	_root = Node3D.new()
	_root.name = "bones_x"
	m.add_child(_root)
	_octa = _make_octa()
	for i in 2:
		var h := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.012
		sm.height = 0.024
		h.mesh = sm
		h.name = "handle_" + ["head", "tail"][i]
		h.material_override = _mat("focus")
		h.visible = false
		_root.add_child(h)
		handles.append(h)
	_build_panel()


## Blender's octahedral bone, unit length along +Y: the head at 0, a square ring at 0.1 (half-width 0.1), the tail at 1
static func _make_octa() -> ArrayMesh:
	var hd := Vector3.ZERO
	var tl := Vector3.UP
	var r := [Vector3(0.1, 0.1, 0.0), Vector3(0.0, 0.1, 0.1), Vector3(-0.1, 0.1, 0.0), Vector3(0.0, 0.1, -0.1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = r[i]
		var b: Vector3 = r[(i + 1) % 4]
		for v in [hd, b, a, tl, a, b]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _mat(tok: String) -> StandardMaterial3D:
	if not _mats.has(tok):
		var mt := StandardMaterial3D.new()
		mt.roughness = 0.5
		_mats[tok] = mt
	(_mats[tok] as StandardMaterial3D).albedo_color = Tok.c(tok)
	(_mats[tok] as StandardMaterial3D).no_depth_test = on   # open: drawn over the body (Blender's "in front"), so a bone inside the hand still shows
	return _mats[tok]


static func depth_tok(d: int) -> String:
	return DEPTH_TOK[d % DEPTH_TOK.size()]


func toggle() -> void:
	if on:
		stop()
	else:
		start()


func start() -> void:
	on = true
	if cur == "":
		cur = String(m.S.bones[0]["name"]) if not m.S.bones.is_empty() else String(m.sel) if BoneEdit.is_core(m.B, String(m.sel)) else "hand_r"
	panel.visible = true
	_sig = ""
	draw()
	m._say("Bone editor: click a bone, E extrude a child from its tail, Shift+A add, X delete, drag a picked bone's end balls, Tab next, Esc closes (each edit is one undo step)")


func stop() -> void:
	on = false
	_drag = {}
	panel.visible = false
	draw()
	m._say("Bone editor closed: your bones stay on the body and in the scene (Rig: bone editor opens it again)")


# ------------------------------------------------------------------ drawing

## the bones at the pose now (main's _refresh calls this); the handles and the panel only while the editor is open
func draw() -> void:
	var S: Scene = m.S
	var B: Body = m.B
	if cur != "" and not _exists(cur):
		cur = ""
	var show: bool = S != null and not m.clean
	var seen := {}
	if show:
		for b in S.bones:
			var n := String(b["name"])
			var nd: MeshInstance3D = nodes.get(n)
			if nd == null:
				nd = MeshInstance3D.new()
				nd.mesh = _octa
				nd.name = "bone_" + n
				_root.add_child(nd)
				nodes[n] = nd
			var xf := BoneEdit.posed_xf(B, S.bones, n)
			var L := BoneEdit.length(B, S.bones, n)
			nd.transform = Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * L), xf.origin)
			nd.material_override = _mat("focus" if on and n == cur else depth_tok(BoneEdit.depth(S.bones, n)))
			nd.visible = true
			seen[n] = true
	for n in nodes.keys():
		if not seen.has(n):
			(nodes[n] as Node3D).queue_free()
			nodes.erase(n)
	var ht := _ends(cur) if on and show and cur != "" and not BoneEdit.is_core(B, cur) else []
	for i in 2:
		(handles[i] as Node3D).visible = not ht.is_empty()
		if not ht.is_empty():
			(handles[i] as Node3D).position = ht[i]
	var sg := var_to_str(S.bones) + "|" + cur + "|" + str(S.rigx.size()) + "|" + str(on)
	if sg != _sig:
		_sig = sg
		_sync()


## [head, tail] of a pick at the pose now
func _ends(id: String) -> Array:
	if id.begins_with("rigx:"):
		var p := id.split(":")
		var pts := RigWords.points(m.B, m.S.rigx[int(p[1])])
		return [pts[int(p[2])], pts[int(p[2]) + 1]]
	return BoneEdit.posed_ht(m.B, m.S.bones, id)


func _exists(id: String) -> bool:
	if id.begins_with("rigx:"):
		var p := id.split(":")
		return int(p[1]) < m.S.rigx.size() and int(p[2]) < (m.S.rigx[int(p[1])]["bones"] as Array).size()
	return BoneEdit.is_core(m.B, id) or BoneEdit.find(m.S.bones, id) >= 0


# ------------------------------------------------------------------ editing (each one undo step)

## a words-made chain's bone becomes yours (the whole chain), inside the step that edits it; returns the bone's name
func _own(id: String) -> String:
	if not id.begins_with("rigx:"):
		return id
	var p := id.split(":")
	var c: Dictionary = m.S.rigx[int(p[1])]
	var names := BoneEdit.from_chain(m.B, m.S.bones, c)
	m.S.rigx.remove_at(int(p[1]))
	return names[int(p[2])]


func _editable(id: String) -> bool:
	if id == "" or not _exists(id):
		m._say("Bone editor: pick a bone first (click one, or Tab)")
		return false
	if BoneEdit.is_core(m.B, id):
		m._say("%s is the body's own bone: the UE5 skeleton is not edited here. E grows a bone of yours from it, Shift+A adds one" % id)
		return false
	return true


func _edit(id: String, f: Callable, label: String) -> void:
	m._step_hint = label
	m._do(func():
		cur = _own(id)
		f.call(cur))
	_sig = ""
	draw()


func extrude() -> String:
	if cur == "" or not _exists(cur):
		cur = "hand_r"
	var made := [""]
	_edit(cur, func(n):
		made[0] = BoneEdit.extrude(m.B, m.S.bones, n)["name"], "Extrude bone")
	cur = made[0]
	_sig = ""
	draw()
	m._say("extruded %s from the tail of %s (one undo step)" % [cur, BoneEdit.get_bone(m.S.bones, cur)["parent"]])
	return cur


func add_bone() -> String:
	if cur == "" or not _exists(cur):
		cur = "hand_r"
	var made := [""]
	_edit(cur, func(n):
		made[0] = BoneEdit.add(m.B, m.S.bones, n)["name"], "Add bone")
	cur = made[0]
	_sig = ""
	draw()
	m._say("added %s under %s (one undo step)" % [cur, BoneEdit.get_bone(m.S.bones, cur)["parent"]])
	return cur


func delete_bone() -> bool:
	if not _editable(cur):
		return false
	var gone := cur
	var up := [""]
	_edit(cur, func(n):
		up[0] = BoneEdit.get_bone(m.S.bones, n)["parent"]
		BoneEdit.delete(m.B, m.S.bones, n), "Delete bone")
	cur = up[0] if not BoneEdit.is_core(m.B, up[0]) else (String(m.S.bones[0]["name"]) if not m.S.bones.is_empty() else up[0])
	_sig = ""
	draw()
	m._say("deleted %s: its children now hang on %s, where they were (one undo step)" % [gone if not gone.begins_with("rigx:") else "the bone", up[0]])
	return true


func set_parent(np: String) -> bool:
	if not _editable(cur):
		return false
	if not cur.begins_with("rigx:"):
		if np == cur or np in BoneEdit.below(m.S.bones, cur) or not _exists(np):
			m._say("%s cannot hang under %s (itself, one of its own children, or not a bone): nothing was changed" % [cur, np])
			return false
		if BoneEdit.get_bone(m.S.bones, cur)["parent"] == np:
			return false
	_edit(cur, func(n):
		BoneEdit.reparent(m.B, m.S.bones, n, np), "Parent bone")
	m._say("%s now hangs on %s; it stayed where it was (one undo step)" % [cur, np])
	return true


func set_roll(deg: float) -> bool:
	if not _editable(cur):
		return false
	_edit(cur, func(n):
		BoneEdit.set_roll(m.B, m.S.bones, n, deg), "Bone roll")
	m._say("%s roll %.1f deg (one undo step)" % [cur, deg])
	return true


func set_length(L: float) -> bool:
	if not _editable(cur):
		return false
	_edit(cur, func(n):
		BoneEdit.set_length(m.B, m.S.bones, n, L), "Bone length")
	m._say("%s is %.1f cm long (one undo step)" % [cur, L * 100.0])
	return true


func rename(nn: String) -> bool:
	if not _editable(cur):
		return false
	var w := BoneEdit.clean_name(nn)
	if w == "" or BoneEdit.is_core(m.B, w) or BoneEdit.find(m.S.bones, w) >= 0:
		m._say("the name '%s' is taken or empty (letters, digits and _ only): nothing was changed" % nn)
		_sig = ""
		draw()
		return false
	_edit(cur, func(n):
		BoneEdit.rename(m.S.bones, n, w), "Rename bone")
	cur = w
	_sig = ""
	draw()
	m._say("renamed to %s (one undo step)" % w)
	return true


func pick(id: String) -> void:
	cur = id
	_sig = ""
	draw()
	if id != "":
		var what := "the body's own bone (a parent / extrude source)" if BoneEdit.is_core(m.B, id) else "a words-made chain's bone (its first edit makes the chain yours)" if id.begins_with("rigx:") else "your bone"
		m._say("picked %s: %s" % [_label(id), what])


func next_bone() -> void:
	var ids := _all_ids()
	if ids.is_empty():
		return
	pick(ids[(ids.find(cur) + 1) % ids.size()])


func _all_ids() -> Array:
	var ids := []
	for b in m.S.bones:
		ids.append(String(b["name"]))
	for i in m.S.rigx.size():
		for k in (m.S.rigx[i]["bones"] as Array).size():
			ids.append("rigx:%d:%d" % [i, k])
	return ids


func _label(id: String) -> String:
	if id.begins_with("rigx:"):
		var p := id.split(":")
		return "%s bone %d (words rig)" % [m.S.rigx[int(p[1])]["name"], int(p[2]) + 1]
	return id


# ------------------------------------------------------------------ the mouse and the keys

## main passes unhandled input here while the editor is open; true = used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := ev as InputEventKey
		if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
			return false
		match k.keycode:
			KEY_E:
				extrude()
				return true
			KEY_A:
				if k.shift_pressed:
					add_bone()
					return true
			KEY_X, KEY_DELETE:
				delete_bone()
				return true
			KEY_TAB:
				next_bone()
				return true
			KEY_ESCAPE:
				stop()
				return true
		return false
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			if _press_handle(mb.position):
				return true
			var id := pick_at(mb.position)
			if id != "":
				pick(id)
			return true
		if not _drag.is_empty():
			_release()
			return true
		return false
	if ev is InputEventMouseMotion and not _drag.is_empty():
		_move((ev as InputEventMouseMotion).position)
		return true
	return false


func _scr(p: Vector3) -> Vector2:
	var cam: Camera3D = m.cam
	return Vector2(INF, INF) if cam.is_position_behind(p) else cam.unproject_position(p)


static func _seg_px(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1e-9 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## the bone under the mouse: yours and the words-made chains first, then the body's own (within PICK_PX)
func pick_at(mp: Vector2) -> String:
	var best := PICK_PX
	var id := ""
	for x in _all_ids():
		var ht := _ends(x)
		var d := _seg_px(mp, _scr(ht[0]), _scr(ht[1]))
		if d < best:
			best = d
			id = x
	if id != "":
		return id
	best = PICK_PX
	for j in Body.ORDER:
		var d := _seg_px(mp, _scr(m.B.P[j]), _scr(m.B.E[j]))
		if d < best:
			best = d
			id = j
	return id


func _press_handle(mp: Vector2) -> bool:
	if cur == "" or BoneEdit.is_core(m.B, cur) or not _exists(cur):
		return false
	var ht := _ends(cur)
	var which := -1
	var best := HANDLE_PX
	for i in 2:
		var d := mp.distance_to(_scr(ht[i]))
		if d <= best:
			best = d
			which = i
	if which < 0:
		return false
	m._step_hint = "Move bone " + ["head", "tail"][which]
	m._push_undo()
	cur = _own(cur)
	var cam: Camera3D = m.cam
	_drag = {"which": which, "moved": false, "plane": Plane(-cam.global_transform.basis.z, ht[which])}
	return true


func _move(mp: Vector2) -> void:
	var cam: Camera3D = m.cam
	var hit: Variant = (_drag["plane"] as Plane).intersects_ray(cam.project_ray_origin(mp), cam.project_ray_normal(mp))
	if hit == null:
		return
	var S: Scene = m.S
	var p := BoneEdit.posed_to_rest(m.B, S.bones, cur, hit)
	var ht := BoneEdit.rest_ht(m.B, S.bones, cur)
	var h: Vector3 = p if _drag["which"] == 0 else ht[0]
	var t: Vector3 = p if _drag["which"] == 1 else ht[1]
	if h.distance_to(t) < BoneEdit.MIN_LEN:
		return
	BoneEdit.set_world(m.B, S.bones, cur, h, t, float(BoneEdit.get_bone(S.bones, cur)["roll"]))
	_drag["moved"] = true
	draw()
	m._say("moving %s's %s: %.1f cm long" % [cur, ["head", "tail"][_drag["which"]], h.distance_to(t) * 100.0])


func _release() -> void:
	var moved: bool = _drag["moved"]
	_drag = {}
	if moved:
		m._after_edit()
		m._say("moved %s (one undo step)" % cur)
	else:
		m._drop_undo()
		m._refresh()
	_sig = ""
	draw()


# ------------------------------------------------------------------ the panel

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "bone_panel"
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
	title.text = "Bone editor"
	vb.add_child(title)
	list = ItemList.new()
	list.name = "bone_list"
	list.custom_minimum_size = Vector2(240, 120)
	list.item_selected.connect(func(i): pick(_list_ids[i]))
	vb.add_child(list)
	var g := GridContainer.new()
	g.columns = 2
	var row := func(t: String, c: Control):
		var l := Label.new()
		l.text = t
		g.add_child(l)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(c)
	f_name = LineEdit.new()
	f_name.name = "bone_name"
	f_name.tooltip_text = "the bone's name: Enter renames it (letters, digits and _; one undo step)"
	f_name.text_submitted.connect(func(t): rename(t))
	row.call("Name", f_name)
	f_parent = OptionButton.new()
	f_parent.name = "bone_parent"
	f_parent.tooltip_text = "hang the bone on another bone; it stays where it is (one undo step)"
	f_parent.item_selected.connect(func(i): set_parent(_parent_ids[i]))
	row.call("Parent", f_parent)
	f_len = SpinBox.new()
	f_len.name = "bone_length"
	f_len.min_value = BoneEdit.MIN_LEN * 100.0
	f_len.max_value = BoneEdit.MAX_LEN * 100.0
	f_len.step = 0.1
	f_len.suffix = "cm"
	f_len.tooltip_text = "the bone's length: the head and the direction stay (one undo step)"
	f_len.value_changed.connect(func(v): set_length(v / 100.0))
	row.call("Length", f_len)
	f_roll = SpinBox.new()
	f_roll.name = "bone_roll"
	f_roll.min_value = -180.0
	f_roll.max_value = 180.0
	f_roll.step = 0.5
	f_roll.suffix = "°"
	f_roll.tooltip_text = "the turn of the bone about its own axis, degrees (one undo step)"
	f_roll.value_changed.connect(func(v): set_roll(v))
	row.call("Roll", f_roll)
	vb.add_child(g)
	var hb := HBoxContainer.new()
	for b in [["Add", "Shift+A: a 10 cm bone under the picked one", add_bone], ["Extrude", "E: a child from the picked bone's tail", extrude],
			["Delete", "X: the picked bone goes, its children hang on its parent", delete_bone], ["Done", "Esc: close the editor", stop]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.name = "btn_bone_" + String(b[0]).to_lower()
		bt.tooltip_text = b[1]
		bt.focus_mode = Control.FOCUS_NONE
		bt.pressed.connect(b[2])
		hb.add_child(bt)
	vb.add_child(hb)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.custom_minimum_size = Vector2(240, 0)
	vb.add_child(info)
	panel.add_child(vb)
	m.ui_root.add_child(panel)


## the panel shows the bones and the pick (no signal fires: setting a field here is not an edit)
func _sync() -> void:
	if panel == null:
		return
	var S: Scene = m.S
	var B: Body = m.B
	list.clear()
	_list_ids = _all_ids()
	for id in _list_ids:
		var lab := _label(id)
		if not id.begins_with("rigx:"):
			lab = "%s%s   (on %s)" % ["  ".repeat(BoneEdit.depth(S.bones, id)), id, BoneEdit.get_bone(S.bones, id)["parent"]]
		list.add_item(lab)
		if id == cur:
			list.select(list.item_count - 1)
	var core := cur == "" or BoneEdit.is_core(B, cur)
	for c in [f_name, f_parent, f_len, f_roll]:
		if c is LineEdit:
			(c as LineEdit).editable = not core
		elif c is SpinBox:
			(c as SpinBox).editable = not core
		else:
			(c as OptionButton).disabled = core
	f_parent.clear()
	_parent_ids = []
	if cur == "":
		f_name.text = ""
		info.text = "Click a bone, or E to grow one from the right hand"
		return
	var ht := _ends(cur)
	var par := ""
	var roll := 0.0
	if cur.begins_with("rigx:"):
		par = String(S.rigx[int(cur.split(":")[1])]["parent"]) if int(cur.split(":")[2]) == 0 else "(the chain)"
		f_name.text = _label(cur)
	elif core:
		par = String(B.parent[cur])
		f_name.text = cur
	else:
		var b := BoneEdit.get_bone(S.bones, cur)
		par = String(b["parent"])
		roll = float(b["roll"])
		f_name.text = cur
	var skip := BoneEdit.below(S.bones, cur) + [cur]
	for j in Body.ORDER:
		_parent_ids.append(j)
	for b in S.bones:
		if not (String(b["name"]) in skip):
			_parent_ids.append(String(b["name"]))
	for p in _parent_ids:
		f_parent.add_item(p)
	f_parent.select(_parent_ids.find(par))
	f_len.set_value_no_signal(((ht[1] as Vector3).distance_to(ht[0])) * 100.0)
	f_roll.set_value_no_signal(roll)
	info.text = "the body's own bone: not edited here (E grows one of yours from it)" if core else \
		"a words-made chain: its first edit makes the chain yours" if cur.begins_with("rigx:") else \
		"E extrude   Shift+A add   X delete   Tab next   drag the end balls"
