class_name KMeshVPaintUI
extends Node
## "Model: vertex paint on / off" (ROADMAP_400 E04): a paint mode on the MODEL page's mesh (kmesh_edit_ui.gd's test cube).
## No new edit-mode key: it is entered from the S box (scripts/mesh_tools.gd, "op:vpaint"; the line opens the model
## preview first when it is not open) and left with Esc or the panel's Done. While it is on, a left drag on the mesh is a
## paint stroke (scripts/kmesh_vpaint.gd), ONE undo step each on the model's own undo (Ctrl+Z / Ctrl+Shift+Z as before):
##   [ / ]  radius smaller / bigger     Shift+[ / ]  strength less / more     O  next falloff     N  next blend mode
##   X  X symmetry on / off     F  fill the selection with the colour     Ctrl+click  eyedropper (the colour under the mouse)
##   Shift while stroking  blur     Esc  leave paint mode (the colours stay on the mesh and in view)
## A tablet's pen pressure scales each dab (a mouse is full pressure). A press off the mesh, right / middle mouse and every
## other key fall through to the model preview (box select from empty space, 1 / 2 / 3, orbit and pan), so a selection for
## F can be made without leaving. The panel (right edge): colour picker, blend, falloff, radius, strength, X symmetry,
## blur, eyedropper, fill, done. Paint mode is this node, a child of main that takes its input before main does (Godot
## sends unhandled input to children first), so main needs no hook. The view shows the colours from the first stroke on
## (KMeshView.show_color), and they stay shown after leaving.

const NODE := "kmesh_vpaint"

var m: Node
var on := false
var ui: Node            # the model preview (KMeshEditUI)
var mesh: KMesh
var view: KMeshView
var vp := KMeshVPaint.new()
var color := Color(0.9, 0.15, 0.1, 1.0)
var mode := KMeshVPaint.MIX
var radius := 0.12
var strength := 1.0
var falloff := KMeshSculpt.F_SMOOTH
var sym_x := false
var blur := false
var dropper := false    # the panel's eyedropper: the next click on the mesh picks its colour
var _stroking := false
var _hover := {}        # {"point" (world), "face"} under the mouse, or {}
var _ov: Control
var panel: PanelContainer
var _w := {}            # the panel's widgets by name
var _sync := false


## main's paint-mode node (made on first use)
static func of(main: Node) -> KMeshVPaintUI:
	var n := main.get_node_or_null(NODE)
	if n == null:
		n = KMeshVPaintUI.new()
		n.name = NODE
		main.add_child(n)
		n.setup(main)
	return n


## mesh_tools "op:vpaint": paint mode on / off on the model preview; returns what it said
static func toggle(main: Node) -> String:
	var n := of(main)
	if n.on:
		n.stop()
	else:
		n.start()
	return String(main.ui_status.text) if main.get("ui_status") != null else ""


## mesh_tools "op:vpaint_fill": the selection takes the current colour (one undo step); returns what it said
static func fill_op(main: Node) -> String:
	var n := of(main)
	n.fill_selection()
	return String(main.ui_status.text) if main.get("ui_status") != null else ""


func setup(main: Node) -> void:
	m = main
	_ov = Control.new()
	_ov.name = "vpaint_overlay"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.visible = false
	_ov.draw.connect(_draw_overlay)
	m.ui_root.add_child(_ov)
	_build_panel()


func _model() -> Node:
	return m.get("kmed")


func start() -> void:
	ui = _model()
	if ui == null or not ui.on:
		m._kmesh_edit_start()
		ui = _model()
	mesh = ui.mesh
	view = ui.view
	if not KMeshVPaint.ensure(mesh):
		m._say("Paint: the mesh's \"color\" channel is not a vert / corner Color, so paint cannot use it. Remove it first")
		return
	on = true
	_stroking = false
	dropper = false
	view.show_color = true
	view.mark_dirty()
	_ov.visible = true
	panel.visible = true
	_sync_panel()
	m._say("Paint: vertex paint on. Drag on the mesh to paint (%s). [ ] radius, Shift+[ ] strength, O falloff, N blend, X symmetry, F fill the selection, Ctrl+click eyedropper, Shift blurs, Esc leaves" % mode)


func stop() -> void:
	if not on:
		return
	on = false
	_stroking = false
	_ov.visible = false
	panel.visible = false
	m._say("Paint: vertex paint off (the colours stay on the mesh). Model: vertex paint on / off comes back")


func _process(_dt: float) -> void:
	if on and (ui == null or not ui.on or ui.mesh != mesh or not is_instance_valid(view)):
		on = false   # the model preview was left or its mesh replaced: nothing to paint on
		_stroking = false
		_ov.visible = false
		panel.visible = false


func params(ev: InputEvent = null) -> Dictionary:
	var b := blur
	if ev is InputEventWithModifiers and (ev as InputEventWithModifiers).shift_pressed:
		b = true
	return {"color": color, "mode": mode, "radius": radius, "strength": strength, "falloff": falloff, "blur": b, "sym_x": sym_x}


func _status() -> void:
	_sync_panel()
	_ov.queue_redraw()
	m._say("Paint: %s, radius %d mm, strength %d %%, %s falloff, X symmetry %s%s" % [mode, roundi(radius * 1000.0), roundi(strength * 100.0), falloff, "on" if sym_x else "off", ", blur" if blur else ""])


## the surface under the screen point: {"point" (world), "face"}, or {}
func surface_at(cam: Camera3D, p: Vector2) -> Dictionary:
	var hit := view.ray_face(cam.project_ray_origin(p), cam.project_ray_normal(p))
	return {} if hit.is_empty() else {"point": hit["point"], "face": int(hit["face"])}


func _local(wp: Vector3) -> Vector3:
	return view.global_transform.affine_inverse() * wp


## F / the panel / "op:vpaint_fill": the model's selection takes the colour (blend mode, strength), one undo step
func fill_selection() -> void:
	ui = _model()
	if ui == null or not ui.on:
		m._kmesh_edit_start()
		ui = _model()
	if ui.sel.is_empty():
		m._say("Paint: nothing selected to fill. Select verts or faces first (click, B box, A all), then F")
		return
	ui.undo.begin(ui.mesh)
	var n := KMeshVPaint.fill(ui.mesh, ui.sel, color, mode, strength)
	ui.undo.commit("vertex paint fill")
	ui.view.show_color = true
	ui.view.mark_dirty()
	m._say("Paint: filled %d corner colours of the %d selected %s (%s). Ctrl+Z undoes" % [n, ui.sel.count(), ["verts", "edges", "faces"][ui.sel.mode], mode])


func pick_color(c: Color) -> void:
	color = c
	dropper = false
	_sync_panel()
	m._say("Paint: picked colour #%s from the mesh" % c.to_html(false))


## this node takes input before main (a child): the model preview gets what paint does not use
func _unhandled_input(ev: InputEvent) -> void:
	if on and input(ev):
		get_viewport().set_input_as_handled()


## true = used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var ke := ev as InputEventKey
		if ke.ctrl_pressed or ke.alt_pressed:
			return false   # Ctrl+Z and the rest: the model preview's
		match ke.keycode:
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				var f := 1.15 if ke.keycode == KEY_BRACKETRIGHT else 1.0 / 1.15
				if ke.shift_pressed:
					strength = clampf(strength * f, 0.01, 1.0)
				else:
					radius = clampf(radius * f, 0.005, 1.0)
			KEY_O:
				falloff = KMeshSculpt.FALLOFFS[(KMeshSculpt.FALLOFFS.find(falloff) + 1) % KMeshSculpt.FALLOFFS.size()]
			KEY_N:
				mode = KMeshVPaint.MODES[(KMeshVPaint.MODES.find(mode) + 1) % KMeshVPaint.MODES.size()]
			KEY_X:
				sym_x = not sym_x
			KEY_F:
				fill_selection()
				return true
			KEY_ESCAPE:
				stop()
				return true
			_:
				return false
		_status()
		return true
	if ev is InputEventKey:
		return false
	var cam: Camera3D = m.cam
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			var s := surface_at(cam, mb.position)
			if s.is_empty():
				return false   # off the mesh: the model preview's (box select)
			if mb.ctrl_pressed or dropper:
				pick_color(KMeshVPaint.sample(mesh, s["face"], _local(s["point"])))
				return true
			ui.undo.begin(mesh)
			vp.begin(mesh, params(mb))
			vp.to(_local(s["point"]), 1.0)
			_stroking = true
			view.mark_dirty()
			return true
		if not _stroking:
			return false
		_stroking = false
		vp.end()
		var st: Dictionary = ui.undo.commit("vertex paint " + ("blur" if vp.p["blur"] else String(vp.p["mode"])))
		if not st.is_empty():
			m._say("Paint: one %s stroke (%d dabs), one undo step (Ctrl+Z takes it back)" % ["blur" if vp.p["blur"] else String(vp.p["mode"]), vp.dabs])
		return true
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_hover = surface_at(cam, mm.position)
		_ov.queue_redraw()
		if not _stroking:
			return false
		if not _hover.is_empty():
			vp.to(_local(_hover["point"]), KMeshSculpt.pressure_of(mm))
			view.mark_dirty()
		return true
	return false


func _draw_overlay() -> void:
	if not on or _hover.is_empty() or not is_instance_valid(view):
		return
	var cam: Camera3D = m.cam
	var c: Vector3 = _hover["point"]
	if cam.is_position_behind(c):
		return
	var sc := cam.unproject_position(c)
	var rp := cam.unproject_position(c + cam.global_transform.basis.x * radius * view.global_transform.basis.get_scale().x)
	_ov.draw_arc(sc, sc.distance_to(rp), 0.0, TAU, 48, color if not blur else Tok.c("pick_hover"), 1.5, true)


# ---------------------------------------------------------------- the panel

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "vpaint_panel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position.x -= 12
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Vertex paint"
	box.add_child(title)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(150, 28)
	cp.color = color
	cp.color_changed.connect(_panel_set.bind("color"))
	box.add_child(cp)
	_w["color"] = cp
	var bm := OptionButton.new()
	for md in KMeshVPaint.MODES:
		bm.add_item(md)
	bm.item_selected.connect(_panel_set.bind("mode"))
	box.add_child(bm)
	_w["mode"] = bm
	var fo := OptionButton.new()
	for fk in KMeshSculpt.FALLOFFS:
		fo.add_item(fk + " falloff")
	fo.item_selected.connect(_panel_set.bind("falloff"))
	box.add_child(fo)
	_w["falloff"] = fo
	for f in [["radius", "radius mm", 5.0, 1000.0, 1.0], ["strength", "strength %", 1.0, 100.0, 1.0]]:
		var sb := SpinBox.new()
		sb.min_value = f[2]
		sb.max_value = f[3]
		sb.step = f[4]
		sb.suffix = f[1].split(" ")[1]
		sb.prefix = f[1].split(" ")[0]
		sb.value_changed.connect(_panel_set.bind(f[0]))
		box.add_child(sb)
		_w[f[0]] = sb
	var sy := CheckBox.new()
	sy.text = "X symmetry"
	sy.toggled.connect(_panel_set.bind("sym_x"))
	box.add_child(sy)
	_w["sym_x"] = sy
	var bl := CheckBox.new()
	bl.text = "blur brush"
	bl.toggled.connect(_panel_set.bind("blur"))
	box.add_child(bl)
	_w["blur"] = bl
	var row := HBoxContainer.new()
	box.add_child(row)
	for b in [["eyedropper", arm_dropper], ["fill", fill_selection], ["done", stop]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.focus_mode = Control.FOCUS_NONE
		bt.pressed.connect(b[1])
		row.add_child(bt)
		_w[b[0]] = bt
	m.ui_root.add_child(panel)


func arm_dropper() -> void:
	dropper = true
	m._say("Paint: click the mesh to pick its colour")


## a panel widget changed (not while _sync_panel writes them)
func _panel_set(v, what: String) -> void:
	if _sync:
		return
	match what:
		"mode":
			mode = KMeshVPaint.MODES[v]
		"falloff":
			falloff = KMeshSculpt.FALLOFFS[v]
		"radius":
			radius = float(v) / 1000.0
		"strength":
			strength = float(v) / 100.0
		_:
			set(what, v)
	_ov.queue_redraw()


func _sync_panel() -> void:
	if panel == null:
		return
	_sync = true
	_w["color"].color = color
	_w["mode"].select(KMeshVPaint.MODES.find(mode))
	_w["falloff"].select(KMeshSculpt.FALLOFFS.find(falloff))
	_w["radius"].value = radius * 1000.0
	_w["strength"].value = strength * 100.0
	_w["sym_x"].button_pressed = sym_x
	_w["blur"].button_pressed = blur
	_sync = false
