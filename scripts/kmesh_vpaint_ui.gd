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
var softness := 1.0     # Friday plan 158: 1 = the falloff over the whole radius (as before), 0 = a hard-edged round brush
var sticker_on := false # armed: the next left click places the sticker instead of painting
var sticker_name := "star"
var sticker_img: Image  # a loaded PNG (sticker_name "file") or the built-in
var sticker_size := 0.2 # metres across
var sticker_rot := 0.0  # degrees
var tex_mode := false   # L53 Texture mode: strokes write the TEXELS of a texture through the UVs (scripts/kmesh_tpaint.gd), not vertex colours
var tp: KMeshTPaint
var _tp_mesh: KMesh
var tex_size := 1024
var tex_pending := {}   # L55: a texture loaded with the scene ({data, size, uv, sha}), applied when Texture mode meets a mesh with the same UVs
var _blank := ""        # L55: the SHA-256 of the texture as Texture mode made it (unpainted)
var _last_px := Vector2.ZERO
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
		n.tex_mode = false
		n.start()
	return String(main.ui_status.text) if main.get("ui_status") != null else ""


## mesh_tools "op:tpaint": Texture mode on / off (paint mode itself is opened first when it is off); returns what it said
static func toggle_tex(main: Node) -> String:
	var n := of(main)
	if n.on and n.tex_mode:
		n.stop()
	elif n.on:
		n.set_tex_mode(true)
	else:
		n.tex_mode = true
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
	if tex_mode:
		_enter_tex()
	view.mark_dirty()
	_ov.visible = true
	panel.visible = true
	_sync_panel()
	m._say("Paint: vertex paint on. Drag on the mesh to paint (%s). [ ] radius, Shift+[ ] strength, O falloff, N blend, X symmetry, F fill the selection, Ctrl+click eyedropper, Shift blurs, Esc leaves" % mode)


## L55: the auto-unwrap Texture mode runs on a mesh without UVs (seams at 60 degrees, LSCM) as ONE undo step on u (the model's undo).
## A mesh that has UVs is left as it is.
static func unwrap_undoable(u: KMeshUndo, mesh: KMesh) -> void:
	if mesh.has_attr("uv"):
		return
	u.begin(mesh)
	KMeshUV.seams_by_angle(mesh, 60.0)
	KMeshUV.unwrap_lscm(mesh)
	u.commit("texture unwrap")


## L55: what the scene saves: {data, size, uv} of the texture as it stands (painted, or still the loaded one); {} = nothing painted
func texture_source() -> Dictionary:
	if tp != null and _tp_mesh != null:
		if tp.hash() == _blank:
			return {}
		return {"data": tp.data(), "size": tp.size, "uv": KMeshTPaintFile.uv_hash(_tp_mesh)}
	if tex_pending.is_empty():
		return {}
	return {"data": tex_pending["data"], "size": tex_pending["size"], "uv": tex_pending["uv"]}


func set_tex_mode(v: bool) -> void:
	tex_mode = v
	if v:
		_enter_tex()
	elif is_instance_valid(view):
		view.paint_tex = null
		view.mark_dirty()
	_status()


## Texture mode: the mesh gets UVs when it has none (seams at 60 degrees, LSCM, packed), a texture of its own, and the view shows it
func _enter_tex() -> void:
	if not mesh.has_attr("uv"):
		unwrap_undoable(ui.undo, mesh)
	if tp == null or _tp_mesh != mesh:
		tp = KMeshTPaint.new(mesh, tex_size)
		_tp_mesh = mesh
		_blank = tp.hash()
		if not tex_pending.is_empty():
			if KMeshTPaintFile.apply(tp, tex_pending, KMeshTPaintFile.uv_hash(mesh)):
				m._say("Paint: the scene's painted texture is back (%d px)" % tp.size)
			else:
				m._say("Paint: the scene's painted texture does not fit this mesh's UVs (or size), so it is not used")
		tex_pending = {}
	view.paint_tex = ImageTexture.create_from_image(tp.image())
	view.mark_dirty()
	m._say("Paint: TEXTURE mode (%s, %d px texture). A stamp across a UV seam colours both islands; the back and hidden side stay clean. Ctrl+Z undoes a stroke" % [tp.engine, tex_size])


func _tex_refresh() -> void:
	if view.paint_tex is ImageTexture:
		(view.paint_tex as ImageTexture).update(tp.image())


## one stamp at screen point p (radius in px from the metre radius at the surface point under it)
func _tex_stamp(p: Vector2) -> int:
	var s := surface_at(m.cam, p)
	if s.is_empty():
		return 0
	var cam: Camera3D = m.cam
	var model: Transform3D = view.global_transform
	var mvp := cam.get_camera_projection() * Projection(cam.global_transform.affine_inverse() * model)
	var wp: Vector3 = s["point"]
	var rpx := cam.unproject_position(wp).distance_to(cam.unproject_position(wp + cam.global_transform.basis.x * radius * model.basis.get_scale().x))
	return tp.stamp(mvp, model.affine_inverse() * cam.global_position, Vector2i(m.get_viewport().get_visible_rect().size), p, rpx, color, strength, 1.0 - softness, 2)


func _tex_to(p: Vector2, first: bool) -> void:
	if first:
		_tex_stamp(p)
	else:
		var n := int(_last_px.distance_to(p) / 3.0)
		if n == 0:
			return
		for i in range(1, n + 1):
			_tex_stamp(_last_px.lerp(p, float(i) / n))
	_last_px = p
	_tex_refresh()


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
	elif on:
		_place()


## the panel sits LEFT of the Materials panel, top aligned with it (the Materials panel's "Library..." button stays clear
## of it: the two used to share the right edge, and Library could not be clicked with paint on). Without a Materials
## panel it sits at the right edge, centred vertically.
func _place() -> void:
	panel.reset_size()
	var sz := panel.size
	var mp: Control = ui.mat_panel if ui != null and ui.get("mat_panel") != null else null
	if mp != null and mp.visible:
		panel.position = Vector2(mp.position.x - sz.x - 12.0, mp.position.y)
	else:
		var vs := m.get_viewport().get_visible_rect().size
		panel.position = Vector2(vs.x - sz.x - 12.0, (vs.y - sz.y) * 0.5)


func params(ev: InputEvent = null) -> Dictionary:
	var b := blur
	if ev is InputEventWithModifiers and (ev as InputEventWithModifiers).shift_pressed:
		b = true
	return {"color": color, "mode": mode, "radius": radius, "strength": strength, "falloff": falloff, "blur": b, "sym_x": sym_x, "hardness": 1.0 - softness}


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


## the ordered log takes a texture stroke back (back) or forward
func tex_undo_redo(back: bool) -> void:
	var r: bool = tp.undo() if back else tp.redo()
	_tex_refresh()
	m._say("Paint: texture stroke %s" % (("undone" if back else "redone") if r else "- nothing to take"))


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



var _pie_mouse := Vector2(-1, -1)   # the last mouse motion seen (events carry it; the OS cursor can differ under a pushed event)


## P04 follow-up: the brush pie (option m.pie_on, off by default); a release on a wedge picks it (scripts/ring_menu.gd, release_pick)
func _open_pie() -> void:
	var its: Array = []
	for b in KMeshVPaint.MODES + ["blur"]:
		its.append({"name": b, "run": func():
			blur = (b == "blur")
			if not blur:
				mode = b
			_status()})
	m.ui_pie.open(_pie_mouse if _pie_mouse.x >= 0.0 else m.get_viewport().get_pie_mouse_position(), "Brush", its)


## true = used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventMouseMotion:
		_pie_mouse = (ev as InputEventMouseMotion).position
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_Q and not ev.ctrl_pressed and not ev.alt_pressed 			and not ev.shift_pressed and m.pie_on and m.ui_pie != null:
		_open_pie()   # the brush pie (Q is free on this page; snap-90 stays on the S search line)
		return true
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var ke := ev as InputEventKey
		if tex_mode and ke.ctrl_pressed and ke.keycode == KEY_Z and tp != null:
			m._redo() if ke.shift_pressed else m._undo()   # L126: the one ordered log (P12); tex_undo_redo takes the texture step
			return true
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
			if sticker_on:
				place_sticker(int(s["face"]), _local(s["point"]))
				return true
			if tex_mode:
				tp.begin_stroke()
				_tex_to(mb.position, true)
				_stroking = true
				return true
			ui.undo.begin(mesh)
			vp.begin(mesh, params(mb))
			vp.to(_local(s["point"]), 1.0, int(s["face"]))
			_stroking = true
			view.mark_dirty()
			return true
		if not _stroking:
			return sticker_on   # a sticker click is used on press; its release is too
		_stroking = false
		if tex_mode:
			var tn := tp.end_stroke()
			if tn > 0:
				m._pu_note("tex", m.cur_page, tp)   # L126: the texture stroke joins the ordered log
			m._say("Paint: one texture stroke (%d texels), one undo step (Ctrl+Z takes it back)" % tn)
			return true
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
		if not _hover.is_empty() and tex_mode:
			_tex_to(mm.position, false)
		elif not _hover.is_empty():
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
	if sticker_on:
		var hr := sc.distance_to(cam.unproject_position(c + cam.global_transform.basis.x * sticker_size * 0.5 * view.global_transform.basis.get_scale().x))
		_ov.draw_rect(Rect2(sc - Vector2.ONE * hr, Vector2.ONE * hr * 2.0), Tok.c("pick_hover"), false, 1.5)
		return
	_ov.draw_arc(sc, sc.distance_to(rp), 0.0, TAU, 48, color if not blur else Tok.c("pick_hover"), 1.5, true)


# ---------------------------------------------------------------- the panel

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "vpaint_panel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)   # _place() puts it beside the Materials panel
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
	var tx := CheckBox.new()
	tx.text = "Texture mode"
	tx.toggled.connect(_panel_set.bind("tex_mode"))
	box.add_child(tx)
	_w["tex_mode"] = tx
	var bl := CheckBox.new()
	bl.text = "blur brush"
	bl.toggled.connect(_panel_set.bind("blur"))
	box.add_child(bl)
	_w["blur"] = bl
	var so := HBoxContainer.new()
	box.add_child(so)
	var sl := Label.new()
	sl.text = "soft"
	so.add_child(sl)
	var ss := HSlider.new()
	ss.name = "softness"
	ss.min_value = 0.0
	ss.max_value = 100.0
	ss.step = 1.0
	ss.custom_minimum_size = Vector2(130, 18)
	ss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ss.value_changed.connect(_panel_set.bind("softness"))
	so.add_child(ss)
	_w["softness"] = ss
	_build_sticker_panel(box)
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
		"softness":
			softness = float(v) / 100.0
		"tex_mode":
			set_tex_mode(bool(v))
		"sticker_name":
			sticker_name = String(sticker_options()[v])
			sticker_img = null if sticker_name == "file" else KMeshSticker.builtin(sticker_name)
		"sticker_size":
			sticker_size = float(v) / 1000.0
		"sticker_rot":
			sticker_rot = float(v)
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
	_w["softness"].value = softness * 100.0
	_w["sticker_size"].value = sticker_size * 1000.0
	_w["sticker_rot"].value = sticker_rot
	_w["sticker_on"].button_pressed = sticker_on
	_w["sym_x"].button_pressed = sym_x
	_w["blur"].button_pressed = blur
	_w["tex_mode"].button_pressed = tex_mode
	_sync = false


# ---------------------------------------------------------------- stickers (Friday plan 158)

func sticker_options() -> Array:
	return KMeshSticker.NAMES + ["file"]


func _build_sticker_panel(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	box.add_child(row)
	var so := OptionButton.new()
	for n in sticker_options():
		so.add_item(String(n) if n != "file" else "PNG file")
	so.item_selected.connect(_panel_set.bind("sticker_name"))
	row.add_child(so)
	_w["sticker_name"] = so
	var on_b := Button.new()
	on_b.text = "Sticker"
	on_b.toggle_mode = true
	on_b.focus_mode = Control.FOCUS_NONE
	on_b.toggled.connect(func(v: bool):
		if not _sync:
			set_sticker_on(v))
	row.add_child(on_b)
	_w["sticker_on"] = on_b
	var pb := Button.new()
	pb.text = "PNG..."
	pb.focus_mode = Control.FOCUS_NONE
	pb.pressed.connect(_pick_png)
	row.add_child(pb)
	_w["sticker_png"] = pb
	var r1 := HBoxContainer.new()
	box.add_child(r1)
	for f in [["sticker_size", "size", 10.0, 1000.0, "mm"], ["sticker_rot", "turn", -180.0, 180.0, "deg"]]:
		var sb := SpinBox.new()
		sb.min_value = f[2]
		sb.max_value = f[3]
		sb.step = 1.0
		sb.prefix = f[1]
		sb.suffix = f[4]
		sb.custom_minimum_size = Vector2(112, 0)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.value_changed.connect(_panel_set.bind(f[0]))
		r1.add_child(sb)
		_w[f[0]] = sb
	var r2 := HBoxContainer.new()
	box.add_child(r2)
	for b in [["denser", densify], ["save", save_colours]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.focus_mode = Control.FOCUS_NONE
		bt.pressed.connect(b[1])
		r2.add_child(bt)
		_w[b[0]] = bt


func set_sticker_on(v: bool) -> void:
	sticker_on = v
	dropper = false
	if v and sticker_img == null:
		sticker_img = KMeshSticker.builtin(sticker_name if sticker_name != "file" else "star")
	_ov.queue_redraw()
	_sync_panel()
	if v:
		m._say("Paint: sticker armed (%s, %d mm). Click the mesh to place it; size and turn in the panel; Ctrl+Z takes the last one back" % [sticker_name, roundi(sticker_size * 1000.0)])


func _pick_png() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png ; PNG image"])
	fd.title = "Sticker image (PNG)"
	fd.size = Vector2i(560, 380)
	fd.file_selected.connect(func(path: String):
		use_png(path)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered()


## a PNG as the sticker; true when it loaded
func use_png(path: String) -> bool:
	var img := KMeshSticker.load_png(path)
	if img == null:
		m._say("Paint: could not read '%s' as a PNG sticker" % path)
		return false
	sticker_img = img
	sticker_name = "file"
	_sync = true
	_w["sticker_name"].select(sticker_options().find("file"))
	_sync = false
	m._say("Paint: sticker image %s (%d x %d)" % [path.get_file(), img.get_width(), img.get_height()])
	return true


## place the sticker at a surface point of face `face` (mesh-local): ONE undo step. Returns the corners coloured.
func place_sticker(face: int, point: Vector3) -> int:
	if sticker_img == null:
		sticker_img = KMeshSticker.builtin(sticker_name if sticker_name != "file" else "star")
	ui.undo.begin(mesh)
	var n := KMeshSticker.place(mesh, face, point, sticker_img, sticker_size, deg_to_rad(sticker_rot))
	var st: Dictionary = ui.undo.commit("sticker " + sticker_name)
	view.show_color = true
	view.mark_dirty()
	if not st.is_empty():
		m._say("Paint: sticker %s placed (%d corners coloured), one undo step (Ctrl+Z takes it back)" % [sticker_name, n])
	return n


## "denser": one subdivision level so a small brush or a sticker has vertices to colour (Ctrl+Z takes it back)
func densify() -> void:
	if not on or ui == null:
		return
	if mesh.domain_count(KMesh.AD_CORNER) > 60000:
		m._say("Paint: the mesh is already dense (%d faces)" % mesh.face_count())
		return
	if not (mesh.shapes.get("keys", []) as Array).is_empty():
		m._say("Paint: this mesh has shape keys, which a split would break. Delete them first")
		return
	ui.undo.begin(mesh)
	var r := KMeshSubdiv.subdivide(mesh, 1, INF)   # every edge sharp: the faces split, the shape stays (no rounding)
	mesh.attrs = {}
	mesh.from_arrays(r.verts, r.faces)
	mesh.attrs = r.attrs
	if not mesh.shapes.is_empty():
		mesh.shapes["basis"] = mesh.verts.duplicate()   # no keys: the basis is the mesh as it is now (the file loads again)
	ui.undo.commit("denser")
	ui.sel.clear()
	view.mark_dirty()
	m._say("Paint: the mesh is denser, %d faces (each face split in four, same shape). Ctrl+Z takes it back" % mesh.face_count())


## "save": the mesh with its colours as a .kmesh in the exports folder; returns its path
func save_colours() -> String:
	var dir := UserPaths.w("res://exports")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := ProjectSettings.globalize_path(dir) + "/painted_model.kmesh"
	var e := mesh.save(path)
	m._say("Paint: saved the colours with the mesh to %s" % path if e == OK else "Paint: NOT saved (%s)" % KMesh.last_error)
	return path if e == OK else ""
