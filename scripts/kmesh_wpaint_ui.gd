class_name KMeshWPaintUI
extends Node
## "Model: weight paint (skin weights)" (ROADMAP_400 H02; the MeshTools line "op:wpaint" turns it on / off): paint the
## model preview's skin weights (the H01 channels, scripts/kmesh_wpaint.gd does the brush) on the mesh open in the
## preview (kmesh_edit_ui.gd), against the fighter's skeleton. While it is on:
##   the mesh shows the ACTIVE bone's weight as a heat (blue 0 -> cyan -> green -> yellow -> red 1), the skeleton's bones
##   are drawn over it (the active one thicker), and a panel (right edge) holds the bone list, brush, radius, strength,
##   value, falloff, X mirror and the lock of the active bone
##   left drag on the mesh   a stroke (one undo step each)        click near a bone (off the mesh) / Alt+click   that bone
##   [ / ]  radius smaller / bigger    Shift+[ / ]  strength less / more    Ctrl+Z / Ctrl+Shift+Z (Ctrl+Y)  undo / redo
##   Esc  leave weight paint (the preview stays open)               a tablet's pen pressure scales each dab
## No new edit-mode key: the mode is entered through the command / the S box. The strokes go on the preview's own undo
## (kmed.undo), so its Ctrl+Z after leaving takes them back too. The wire and the vertex points of the preview are hidden
## while painting (the heat is the picture) and come back on leaving.
## Input: this node is a child of main added after the model preview, so its _unhandled_input runs before main's.

const OFF := 0.001          # m: the heat layer sits this far out along the vertex normals
const BONE_PX := 14.0       # a click this close to a bone's drawn line picks it
const NAME := "kmesh_wpaint"

var m: Node
var on := false
var ed                      # the model preview (KMeshEditUI)
var wp := KMeshWPaint.new()
var bones := []             # KMeshAutoWeights.bones_from_skeleton (skeleton rest space)
var mirror_of := {}
var bone := -1              # the active bone (skeleton bone id)
var brush := KMeshWPaint.ADD
var radius := 0.05
var strength := 0.2
var value := 1.0
var falloff := KMeshSculpt.F_SMOOTH
var mirror := false
var locks := {}             # bone id -> true
var heat_mi: MeshInstance3D
var panel: PanelContainer
var _list: ItemList
var _brush_opt: OptionButton
var _fall_opt: OptionButton
var _radius_spin: SpinBox
var _str_spin: SpinBox
var _val_spin: SpinBox
var _mirror_chk: CheckBox
var _lock_chk: CheckBox
var _locks_lbl: Label
var _ov: Control
var _stroking := false
var pen_target := "strength"   # P09 tablet: what pen pressure scales: strength | radius | both | off (a mouse is always full)
var _pen := KMeshPen.new()
var _stroke_r := 0.05
var _hover := {}
var _heat_dirty := true
var _seen_data = null       # the weights array the heat was built from (an undo swaps it)
var _seen_bones = null
var _seen_verts := PackedVector3Array()   # the positions it was built on (a G / R / S edit moves them)
var _wire0 := true
var _verts0 := true
var _syncing := false


## the weight paint of main (made on first use)
static func of(main: Node) -> KMeshWPaintUI:
	var n = main.get_node_or_null(NAME)
	if n == null:
		n = KMeshWPaintUI.new()
		n.name = NAME
		main.add_child(n)
		n.setup(main)
	return n


## the MeshTools op: on / off. Returns what it says
static func toggle(main: Node) -> String:
	var ui := of(main)
	return ui.stop() if ui.on else ui.start()


func setup(main: Node) -> void:
	m = main
	_ov = Control.new()
	_ov.name = "wpaint_overlay"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.visible = false
	_ov.draw.connect(_draw_overlay)
	m.ui_root.add_child(_ov)
	_build_panel()


func start() -> String:
	if on:
		return ""
	if m.skel == null:
		return "Model: weight paint needs a skeleton: pick the mannequin first"
	if m.kmed == null or not m.kmed.on:
		m._kmesh_edit_start()
	ed = m.kmed
	var sk: Skeleton3D = m.skel
	bones = KMeshAutoWeights.bones_from_skeleton(sk)
	mirror_of = KMeshWPaint.mirror_map(bones)
	bone = _strongest()
	heat_mi = MeshInstance3D.new()
	heat_mi.name = "wpaint_heat"
	heat_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ed.view.add_child(heat_mi)
	_wire0 = ed.view.show_wire
	_verts0 = ed.view.show_verts
	ed.view.show_wire = false
	ed.view.show_verts = false
	ed.view.mark_dirty()
	on = true
	_stroking = false
	_fill_list()
	_sync_panel()
	panel.visible = true
	_ov.visible = true
	_heat_dirty = true
	_rebuild_heat()
	var bound: bool = ed.mesh.has_attr(KMeshWPaint.CH_BONES)
	return "Model: weight paint on '%s'%s. Drag on the mesh to paint (%s), click near a bone to pick it, [ ] radius, Ctrl+Z undo, Esc leaves" % [bone_name(bone), "" if bound else " (no weights yet: the first stroke starts them; 'Model: bind to the skeleton' gives auto weights)", brush]


func stop() -> String:
	if not on:
		return ""
	on = false
	_stroking = false
	panel.visible = false
	_ov.visible = false
	if is_instance_valid(heat_mi):
		heat_mi.queue_free()
	heat_mi = null
	if ed != null and ed.view != null and is_instance_valid(ed.view):
		ed.view.show_wire = _wire0
		ed.view.show_verts = _verts0
		ed.view.mark_dirty()
	return "Model: left weight paint (the strokes stay; Ctrl+Z in the preview takes them back)"


func bone_name(id: int) -> String:
	for b in bones:
		if int(b["id"]) == id:
			return String(b["name"])
	return "(none)"


## the bone with the most weight on the mesh (the first bone when it has none)
func _strongest() -> int:
	var mesh: KMesh = ed.mesh
	var best := int(bones[0]["id"]) if not bones.is_empty() else -1
	if not (mesh.has_attr(KMeshWPaint.CH_BONES) and mesh.has_attr(KMeshWPaint.CH_WEIGHTS)):
		return best
	var tot := {}
	var cbs: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_BONES)
	var cws: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_WEIGHTS)
	for v in cbs.size():
		for q in 4:
			var id := roundi(cbs[v][q])
			if id >= 0:
				tot[id] = float(tot.get(id, 0.0)) + cws[v][q]
	var bw := 0.0
	for id in tot:
		if float(tot[id]) > bw:
			bw = tot[id]
			best = id
	return best


func set_bone(id: int) -> void:
	bone = id
	_heat_dirty = true
	_sync_panel()
	_ov.queue_redraw()
	m._say("Model: painting '%s'%s" % [bone_name(id), " (locked: strokes leave it as it is)" if locks.has(id) else ""])


func set_lock(id: int, locked: bool) -> void:
	if locked:
		locks[id] = true
	else:
		locks.erase(id)
	_sync_panel()


func _params() -> Dictionary:
	_pen.target = pen_target
	var br := brush
	if _pen.erasing():   # P09: the eraser end subtracts where the brush adds, and adds where it subtracts
		br = KMeshWPaint.SUB if brush == KMeshWPaint.ADD else (KMeshWPaint.ADD if brush == KMeshWPaint.SUB else brush)
	return {"brush": br, "bone": bone, "radius": radius, "strength": strength, "value": value, "falloff": falloff,
		"mirror": mirror, "mirror_of": mirror_of, "locks": locks.duplicate()}


func _process(_dt: float) -> void:
	if not on:
		return
	if ed == null or not ed.on or not is_instance_valid(heat_mi):
		stop()
		return
	var mesh: KMesh = ed.mesh
	var d = mesh.attr_data(KMeshWPaint.CH_WEIGHTS) if mesh.has_attr(KMeshWPaint.CH_WEIGHTS) else null
	var b = mesh.attr_data(KMeshWPaint.CH_BONES) if mesh.has_attr(KMeshWPaint.CH_BONES) else null
	if _heat_dirty or d != _seen_data or b != _seen_bones or mesh.verts != _seen_verts or ed.view.dirty:
		_rebuild_heat()
	_ov.queue_redraw()


## the heat of the active bone: the mesh's triangles, the weight per vertex as u into the ramp (blended, then coloured), unshaded
func _rebuild_heat() -> void:
	_heat_dirty = false
	var mesh: KMesh = ed.mesh
	_seen_data = mesh.attr_data(KMeshWPaint.CH_WEIGHTS) if mesh.has_attr(KMeshWPaint.CH_WEIGHTS) else null
	_seen_bones = mesh.attr_data(KMeshWPaint.CH_BONES) if mesh.has_attr(KMeshWPaint.CH_BONES) else null
	_seen_verts = mesh.verts
	var nv := mesh.verts.size()
	var wv := PackedFloat32Array()
	wv.resize(nv)
	for v in nv:
		wv[v] = KMeshWPaint.weight_of(mesh, v, bone)
	var pos := PackedVector3Array()
	var uvs := PackedVector2Array()
	for fi in mesh.face_count():
		var fp: PackedInt32Array = mesh.faces[fi]
		for i in range(1, fp.size() - 1):
			for c in [0, i + 1, i]:   # Godot's front face is clockwise; KMesh is counter-clockwise
				var v := fp[c]
				pos.append(mesh.verts[v] + mesh.vert_normals[v] * OFF)
				uvs.append(Vector2(clampf(wv[v], 0.0, 1.0), 0.5))
	if pos.is_empty():
		heat_mi.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	heat_mi.mesh = am
	if heat_mi.material_override == null:
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.albedo_texture = ramp()   # the WEIGHT is blended across a triangle, then coloured (Blender's way): 0.5 is green
		mt.texture_repeat = false
		mt.cull_mode = BaseMaterial3D.CULL_BACK
		heat_mi.material_override = mt


## KMeshWPaint.heat_color as a 256-texel strip (u = the weight)
static func ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([0.0, 0.25, 0.5, 0.75, 1.0].map(func(x): return KMeshWPaint.heat_color(x)))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


# ---------------------------------------------------------------- bones on screen

## the bone's drawn segments in world space: [[a, b], ...] (rest pose, through the skeleton's transform)
func bone_segments(id: int) -> Array:
	var sk: Skeleton3D = m.skel
	var gx := sk.global_transform
	for b in bones:
		if int(b["id"]) == id:
			var out := []
			for e in (b["ends"] as PackedVector3Array):
				out.append([gx * (b["a"] as Vector3), gx * e])
			return out
	return []


static func _seg2(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-9 else 0.0
	return p.distance_to(a + ab * t)


## the bone whose drawn line is nearest the screen point: [id, px], [-1, INF] when none is in front of the camera
func bone_at(cam: Camera3D, sp: Vector2) -> Array:
	var best := -1
	var bd := INF
	for b in bones:
		for s in bone_segments(int(b["id"])):
			if cam.is_position_behind(s[0]) or cam.is_position_behind(s[1]):
				continue
			var d := _seg2(sp, cam.unproject_position(s[0]), cam.unproject_position(s[1]))
			if d < bd:
				bd = d
				best = int(b["id"])
	return [best, bd]


# ---------------------------------------------------------------- input

func _unhandled_input(ev: InputEvent) -> void:
	if on and input(ev):
		get_viewport().set_input_as_handled()


func _surface_at(cam: Camera3D, sp: Vector2) -> Dictionary:
	var hit: Dictionary = ed.view.ray_face(cam.project_ray_origin(sp), cam.project_ray_normal(sp))
	if hit.is_empty():
		return {}
	return {"point": hit["point"], "face": hit["face"]}


func _local(wpt: Vector3) -> Vector3:
	return ed.view.global_transform.affine_inverse() * wpt


## true = used
func input(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed:
		var ke := ev as InputEventKey
		var k := ke.keycode
		if ke.ctrl_pressed and (k == KEY_Z or k == KEY_Y):
			var re := k == KEY_Y or ke.shift_pressed
			var lb: String = ed.undo.redo() if re else ed.undo.undo()
			ed.view.mark_dirty()
			_heat_dirty = true
			m._say("Model: %s %s" % ["redone" if re else "undone", lb] if lb != "" else "Model: nothing to %s" % ("redo" if re else "undo"))
			return true
		if ke.echo:
			return false
		match k:
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				var f := 1.15 if k == KEY_BRACKETRIGHT else 1.0 / 1.15
				if ke.shift_pressed:
					strength = clampf(strength * f, 0.01, 1.0)
				else:
					radius = clampf(radius * f, 0.005, 1.0)
				_sync_panel()
				_status()
				return true
			KEY_ESCAPE:
				if _stroking:
					return true
				m._say(stop())
				return true
		return false
	if ev is InputEventKey:
		return false
	var cam: Camera3D = m.cam
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			var s := _surface_at(cam, mb.position)
			if mb.alt_pressed or s.is_empty():
				var hit := bone_at(cam, mb.position)
				if int(hit[0]) >= 0 and (mb.alt_pressed or float(hit[1]) <= BONE_PX):
					set_bone(int(hit[0]))
					return true
				return false   # off the mesh and off the bones: the preview's own click (box select)
			if bone < 0:
				m._say("Model: pick a bone to paint first (the list, or click near a bone)")
				return true
			ed.undo.begin(ed.mesh)
			wp.begin(ed.mesh, _params())
			_stroke_r = float(wp.p["radius"])
			_pen_dab()
			wp.to(_local(s["point"]), Vector3.UP, _pen.sk())
			wp.flush()
			_stroking = true
			_heat_dirty = true
			return true
		if not _stroking:
			return false
		_stroking = false
		wp.end()
		var st: Dictionary = ed.undo.commit("weight paint " + brush)
		_heat_dirty = true
		if not st.is_empty():
			m._say("Model: one %s stroke on '%s' (%d verts), one undo step (Ctrl+Z takes it back)" % [brush, bone_name(bone), wp.touched.size()])
		return true
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_hover = _surface_at(cam, mm.position)
		_ov.queue_redraw()
		_pen.target = pen_target
		_pen.note(mm)
		if not _stroking:
			return false
		if not _hover.is_empty():
			_pen_dab()
			wp.to(_local(_hover["point"]), Vector3.UP, _pen.sk())
			wp.flush()
			_heat_dirty = true
		return true
	return false


## P09: before a dab, the pen's radius factor (radius mode) goes into the running stroke
func _pen_dab() -> void:
	var rk := _pen.rk()
	if rk != 1.0:
		wp.p["radius"] = _stroke_r * rk


func _status() -> void:
	m._say("Model: weight paint %s on '%s', radius %d mm, strength %.2f%s, %s falloff, X mirror %s" % [brush, bone_name(bone),
		roundi(radius * 1000.0), strength, (", value %.2f" % value) if brush == KMeshWPaint.SET else "", falloff, "on" if mirror else "off"])


# ---------------------------------------------------------------- panel + overlay

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "wpaint_panel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -250
	panel.offset_right = -8
	panel.offset_top = 64
	var vb := VBoxContainer.new()
	var title := Label.new()
	title.text = "Weight paint"
	vb.add_child(title)
	_list = ItemList.new()
	_list.name = "list_wp_bones"
	_list.custom_minimum_size = Vector2(230, 200)
	_list.item_selected.connect(func(i):
		if not _syncing:
			set_bone(int(_list.get_item_metadata(i))))
	vb.add_child(_list)
	_lock_chk = CheckBox.new()
	_lock_chk.name = "chk_wp_lock"
	_lock_chk.text = "Lock this bone"
	_lock_chk.tooltip_text = "a locked bone's weights never change; the other bones rescale around it"
	_lock_chk.toggled.connect(func(b):
		if not _syncing:
			set_lock(bone, b))
	vb.add_child(_lock_chk)
	_locks_lbl = Label.new()
	_locks_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_locks_lbl.custom_minimum_size = Vector2(230, 0)
	vb.add_child(_locks_lbl)
	var g := GridContainer.new()
	g.columns = 2
	_brush_opt = _opt(g, "Brush", "opt_wp_brush", KMeshWPaint.MODES, func(i):
		brush = KMeshWPaint.MODES[i]
		_status())
	_fall_opt = _opt(g, "Falloff", "opt_wp_falloff", KMeshSculpt.FALLOFFS, func(i): falloff = KMeshSculpt.FALLOFFS[i])
	_radius_spin = _spin(g, "Radius (cm)", "spin_wp_radius", 0.5, 100.0, 0.5, func(x): radius = x / 100.0)
	_str_spin = _spin(g, "Strength", "spin_wp_strength", 0.01, 1.0, 0.01, func(x): strength = x)
	_val_spin = _spin(g, "Set value", "spin_wp_value", 0.0, 1.0, 0.01, func(x): value = x)
	vb.add_child(g)
	_mirror_chk = CheckBox.new()
	_mirror_chk.name = "chk_wp_mirror"
	_mirror_chk.text = "X mirror (_l <-> _r)"
	_mirror_chk.toggled.connect(func(b):
		if not _syncing:
			mirror = b)
	vb.add_child(_mirror_chk)
	panel.add_child(vb)
	m.ui_root.add_child(panel)


func _opt(g: GridContainer, label: String, nm: String, items: Array, cb: Callable) -> OptionButton:
	var l := Label.new()
	l.text = label
	g.add_child(l)
	var o := OptionButton.new()
	o.name = nm
	for it in items:
		o.add_item(String(it))
	o.item_selected.connect(func(i):
		if not _syncing:
			cb.call(i))
	g.add_child(o)
	return o


func _spin(g: GridContainer, label: String, nm: String, lo: float, hi: float, st: float, cb: Callable) -> SpinBox:
	var l := Label.new()
	l.text = label
	g.add_child(l)
	var s := SpinBox.new()
	s.name = nm
	s.min_value = lo
	s.max_value = hi
	s.step = st
	s.value_changed.connect(func(x):
		if not _syncing:
			cb.call(x))
	g.add_child(s)
	return s


## the bones, the ones with weight on the mesh first (then the skeleton's order)
func _fill_list() -> void:
	_syncing = true
	_list.clear()
	var mesh: KMesh = ed.mesh
	var has := {}
	if mesh.has_attr(KMeshWPaint.CH_BONES):
		for c in (mesh.attr_data(KMeshWPaint.CH_BONES) as PackedColorArray):
			for q in 4:
				has[roundi(c[q])] = true
	for pass_ in 2:
		for b in bones:
			var id := int(b["id"])
			if has.has(id) != (pass_ == 0):
				continue
			var i := _list.add_item(String(b["name"]) + ("" if has.has(id) else "  (no weight)"))
			_list.set_item_metadata(i, id)
	_syncing = false


func _sync_panel() -> void:
	_syncing = true
	for i in _list.item_count:
		if int(_list.get_item_metadata(i)) == bone:
			_list.select(i)
			_list.ensure_current_is_visible()
	_lock_chk.button_pressed = locks.has(bone)
	_locks_lbl.text = "Locked: " + ", ".join(locks.keys().map(func(k): return bone_name(k))) if not locks.is_empty() else ""
	_brush_opt.selected = KMeshWPaint.MODES.find(brush)
	_fall_opt.selected = KMeshSculpt.FALLOFFS.find(falloff)
	_radius_spin.value = radius * 100.0
	_str_spin.value = strength
	_val_spin.value = value
	_mirror_chk.button_pressed = mirror
	_syncing = false


func _draw_overlay() -> void:
	if not on or ed == null or not is_instance_valid(ed.view):
		return
	var cam: Camera3D = m.cam
	var dim := Color(Tok.c("cube_edge"), 0.8)
	var act := Tok.c("focus")
	for b in bones:
		var id := int(b["id"])
		for s in bone_segments(id):
			if cam.is_position_behind(s[0]) or cam.is_position_behind(s[1]):
				continue
			_ov.draw_line(cam.unproject_position(s[0]), cam.unproject_position(s[1]), act if id == bone else dim, 3.0 if id == bone else 1.0, true)
	if _hover.is_empty():
		return
	var c: Vector3 = _hover["point"]
	if cam.is_position_behind(c):
		return
	var sc := cam.unproject_position(c)
	var rp := cam.unproject_position(c + cam.global_transform.basis.x * radius * ed.view.global_transform.basis.get_scale().x)
	_ov.draw_arc(sc, sc.distance_to(rp), 0.0, TAU, 48, Tok.c("pick_hover"), 1.5, true)
