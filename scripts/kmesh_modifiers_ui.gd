class_name KMeshModifiersUI
extends Node
## A11: the "Modifiers" panel of the model preview (right edge, beside the stage) and the live evaluated surface.
## The panel: a type picker + Add, then one block per modifier, top first: its tick (on / off, named by describe()),
## up / down (reorder), Apply (bake it into the base) and x (remove), then its params (lengths in cm, ticks, choices).
## Every stack edit is ONE KMeshUndo step on the base mesh (Ctrl+Z in the preview takes it back); a run of changes to the
## same field (a SpinBox dragged or typed) stays one step. Apply is one step too (the bake and the stack change together).
## THE VIEWPORT: while any modifier is on, the view's own surface is hidden and a "mod_surface" child of the view draws
## KMeshModifiers.evaluate(base) (flat shaded, Godot winding). The wire, the points, the selection and the pick stay on
## the base cage: edits still go to the base, and the evaluated surface follows it (re-evaluated on the view's rebuilt
## signal when the base or the stack changed; `eval_ms` is the last evaluation's time).

const PANEL_GAP := 12
const MAX_H := 0.6   # of the window's height: past it the list scrolls

var ed: KMeshEditUI
var m: Node
var panel: PanelContainer
var surf: MeshInstance3D
var evaluated: KMesh
var eval_ms := 0.0
var _kind: OptionButton
var _list: VBoxContainer
var _scroll: ScrollContainer
var _sig := 0
var _list_sig := 0


func setup(editor: KMeshEditUI) -> void:
	ed = editor
	m = editor.m
	panel = PanelContainer.new()
	panel.name = "mod_panel"
	panel.visible = false
	var vb := VBoxContainer.new()
	var title := Label.new()
	title.text = "Modifiers"
	vb.add_child(title)
	var hb := HBoxContainer.new()
	_kind = OptionButton.new()
	_kind.name = "opt_mod_kind"
	for t in KMeshModifiers.TYPES:
		_kind.add_item(KMeshModifiers.NAMES[t])
	hb.add_child(_kind)
	var b := Button.new()
	b.name = "btn_mod_add"
	b.text = "Add"
	b.tooltip_text = "add this modifier at the bottom of the stack (one undo step); the mesh itself is not changed"
	b.pressed.connect(func(): add.call_deferred(KMeshModifiers.TYPES[_kind.selected]))
	hb.add_child(b)
	vb.add_child(hb)
	_scroll = ScrollContainer.new()
	_scroll.name = "mod_scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.name = "mod_list"
	_scroll.add_child(_list)
	vb.add_child(_scroll)
	panel.add_child(vb)
	m.ui_root.add_child(panel)


func open() -> void:
	panel.visible = true
	surf = MeshInstance3D.new()
	surf.name = "mod_surface"
	ed.view.add_child(surf)
	ed.view.rebuilt.connect(_on_rebuilt)
	_sig = 0
	refresh_list()
	_on_rebuilt()


func close() -> void:
	panel.visible = false
	surf = null   # freed with the view
	evaluated = null


func _mesh() -> KMesh:
	return ed.mesh


# ---------------------------------------------------------------- the viewport

func _on_rebuilt() -> void:
	if surf == null or not is_instance_valid(surf):
		return
	var mesh := _mesh()
	var on := KMeshModifiers.any_on(mesh.modifiers)
	ed.view._surf.visible = not on
	surf.visible = on
	if hash(mesh.modifiers) != _list_sig:
		refresh_list()   # an undo / redo changed the stack
	if not on:
		surf.mesh = null
		evaluated = null
		_sig = 0
		return
	var sig := hash([mesh.verts, mesh.faces, mesh.modifiers])
	if sig == _sig:
		return
	_sig = sig
	var t0 := Time.get_ticks_usec()
	evaluated = KMeshModifiers.evaluate(mesh)
	eval_ms = (Time.get_ticks_usec() - t0) / 1000.0
	surf.mesh = surface_of(evaluated)
	surf.material_override = ed.view._mat(Tok.c("cube"), true)


## flat-shaded triangles of a KMesh with Godot's clockwise front faces (as KMeshView._surface)
static func surface_of(k: KMesh) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	for fi in k.face_count():
		var fp: PackedInt32Array = k.faces[fi]
		var n := k.face_normals[fi]
		for i in range(1, fp.size() - 1):
			pos.append(k.verts[fp[0]])
			pos.append(k.verts[fp[i + 1]])
			pos.append(k.verts[fp[i]])
			nor.append(n)
			nor.append(n)
			nor.append(n)
	var am := ArrayMesh.new()
	if pos.is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


# ---------------------------------------------------------------- stack edits (one undo step each)

func _step(label: String, f: Callable):
	var mesh := _mesh()
	ed.undo.begin(mesh)
	var r = f.call()
	ed.undo.commit(label)
	refresh_list()
	ed.view.rebuild()
	return r


func add(type: String) -> int:
	var i: int = _step("Add %s modifier" % KMeshModifiers.NAMES.get(type, type), func(): return KMeshModifiers.add(_mesh(), type))
	m._say("Model: %s" % (KMeshModifiers.last_error if i < 0 else "added %s (the mesh itself is unchanged; Apply bakes it, Ctrl+Z takes it back)" % KMeshModifiers.describe(_mesh().modifiers[i])))
	return i


## GRS / Ctrl+1..3 (Blender): a Subdivide modifier at `levels` at the bottom of the stack, one undo step. -1 when the stack
## refuses it (last_error says why): the caller then subdivides the mesh itself and says so.
func add_level(levels: int) -> int:
	var i: int = _step("Add Subdivide x%d modifier" % levels, func(): return KMeshModifiers.add(_mesh(), "subdiv", {"levels": levels}))
	if i < 0:
		m._say("Model: %s" % KMeshModifiers.last_error)
		return -1
	m._say("Model: added Subdivide x%d (Catmull-Clark) as a modifier: the mesh itself is unchanged; Apply bakes it, Ctrl+Z takes it back" % levels)
	return i


func remove(i: int) -> bool:
	var nm := _name(i)
	var r: bool = _step("Remove %s modifier" % nm, func(): return KMeshModifiers.remove(_mesh(), i))
	if r:
		m._say("Model: removed %s (Ctrl+Z brings it back)" % nm)
	return r


func move(i: int, to: int) -> int:
	if to < 0 or to >= _mesh().modifiers.size() or to == i:
		return i
	var r: int = _step("Move %s modifier" % _name(i), func(): return KMeshModifiers.move(_mesh(), i, to))
	m._say("Model: %s is now %d of %d (the order changes the result)" % [_name(r), r + 1, _mesh().modifiers.size()])
	return r


func toggle(i: int) -> bool:
	var r: bool = _step("Toggle %s modifier" % _name(i), func(): return KMeshModifiers.toggle(_mesh(), i))
	m._say("Model: %s %s" % [_name(i), "on" if r else "off"])
	return r


## one param; a run of changes to the same field of the same modifier stays one undo step
func set_param(i: int, key: String, value):
	var mesh := _mesh()
	var label := "Modifier %d %s" % [i + 1, key]
	var top: Dictionary = ed.undo.steps.back() if not ed.undo.steps.is_empty() else {}
	var r
	if ed.undo.redos.is_empty() and top.get("label", "") == label and top.get("kind", "") == "mods" and top.get("mesh") == mesh:
		r = KMeshModifiers.set_param(mesh, i, key, value)
		top["m_new"] = mesh.modifiers.duplicate(true)
	else:
		ed.undo.begin(mesh)
		r = KMeshModifiers.set_param(mesh, i, key, value)
		ed.undo.commit(label)
	_list_sig = hash(mesh.modifiers)   # the field already shows it: no list rebuild under the cursor
	if i < _list.get_child_count():
		var cb := _list.get_child(i).find_child("mod_%d_on" % i, true, false) as CheckBox
		if cb != null:
			cb.text = KMeshModifiers.describe(mesh.modifiers[i])
	ed.view.rebuild()
	return r


## bake modifier i into the base: one undo step (the mesh and the stack change together)
func apply(i: int) -> bool:
	var mesh := _mesh()
	var nm := _name(i)
	ed.undo.begin(mesh)
	var err := KMeshModifiers.apply_mod(mesh, i)
	ed.undo.commit("Apply %s modifier" % nm)
	if err != "":
		m._say("Model: cannot apply %s: %s" % [nm, err])
		return false
	ed._after_topo()   # the selection named the old verts / faces
	refresh_list()
	ed.view.rebuild()
	m._say("Model: applied %s: the mesh is now %d verts %d faces (Ctrl+Z takes it back)" % [nm, mesh.vert_count(), mesh.face_count()])
	return true


func _name(i: int) -> String:
	var st := _mesh().modifiers
	return KMeshModifiers.NAMES[st[i]["type"]] if i >= 0 and i < st.size() else "?"


## the stack in one line (the S box's "Model: modifier stack" says it)
func say_stack() -> String:
	var st := _mesh().modifiers
	if st.is_empty():
		return "Model: no modifiers yet. Pick one in the Modifiers panel (right) and press Add: mirror, subdivide, solidify, array, displace"
	var parts := []
	for mod in st:
		parts.append(KMeshModifiers.describe(mod) + ("" if mod["on"] else " (off)"))
	return "Model: modifiers, top first: %s. The view shows the result (%.0f ms), edits go to the base" % [" -> ".join(parts), eval_ms]


# ---------------------------------------------------------------- the panel

func refresh_list() -> void:
	var mesh := _mesh()
	_list_sig = hash(mesh.modifiers)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for i in mesh.modifiers.size():
		_list.add_child(_block(i, mesh.modifiers[i]))
	_fit()
	_fit.call_deferred()   # the new rows' minimum sizes settle a frame later


## the list scrolls past MAX_H of the window's height, so a long stack never runs off the screen
func _fit() -> void:
	var ms := _list.get_combined_minimum_size()
	var vh := panel.get_viewport_rect().size.y
	_scroll.custom_minimum_size = Vector2(ms.x, minf(ms.y, vh * MAX_H))
	panel.reset_size()
	if ed != null and ed.m != null and ed.m._mesh_page():   # a mesh page: the top of the left column (Materials has the right edge, Add primitive the middle)
		panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 0)
		panel.position = Vector2(PANEL_GAP, ed.m.nav_clear_rect().position.y + PANEL_GAP)
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, PANEL_GAP)


func _block(i: int, mod: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.name = "mod_%d" % i
	var hb := HBoxContainer.new()
	var on := CheckBox.new()
	on.name = "mod_%d_on" % i
	on.text = KMeshModifiers.describe(mod)
	on.button_pressed = bool(mod["on"])
	on.toggled.connect(func(_p): toggle.call_deferred(i))   # deferred: the list is rebuilt under the button
	on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(on)
	for b in [["up", "↑", "move up (runs earlier)", func(): move.call_deferred(i, i - 1)], ["down", "↓", "move down (runs later)", func(): move.call_deferred(i, i + 1)],
			["apply", "Apply", "bake it into the mesh (one undo step)", func(): apply.call_deferred(i)], ["x", "×", "remove it", func(): remove.call_deferred(i)]]:
		var bt := Button.new()
		bt.name = "mod_%d_%s" % [i, b[0]]
		bt.text = b[1]
		bt.tooltip_text = b[2]
		bt.pressed.connect(b[3])
		hb.add_child(bt)
	vb.add_child(hb)
	var g := GridContainer.new()
	g.columns = 2
	for p in KMeshModifiers.PARAMS[mod["type"]]:
		var key := String(p[0])
		var kind := String(p[5])
		var l := Label.new()
		l.text = key.replace("_", " ") + (" (cm)" if kind == "m" else "")
		g.add_child(l)
		var w: Control
		if kind == "b":
			var cb := CheckBox.new()
			cb.button_pressed = bool(mod[key])
			cb.toggled.connect(func(pr): set_param(i, key, pr))
			w = cb
		elif kind.begins_with("e:"):
			var ob := OptionButton.new()
			for it in kind.substr(2).split(","):
				ob.add_item(it)
			ob.selected = int(mod[key])
			ob.item_selected.connect(func(s): set_param(i, key, s))
			w = ob
		elif kind == "s":   # B13: a channel name
			var le := LineEdit.new()
			le.text = String(mod[key])
			le.placeholder_text = "(none)"
			le.text_submitted.connect(func(t): set_param(i, key, t))
			w = le
		else:
			var s := SpinBox.new()
			var k := 100.0 if kind == "m" else 1.0
			s.min_value = float(p[2]) * k
			s.max_value = float(p[3]) * k
			s.step = float(p[4]) * k
			s.value = float(mod[key]) * k
			s.value_changed.connect(func(v): set_param(i, key, v / k if kind == "m" else v))
			w = s
		w.name = "mod_%d_%s" % [i, key]
		g.add_child(w)
	vb.add_child(g)
	vb.add_child(HSeparator.new())
	return vb
