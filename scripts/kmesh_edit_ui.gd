class_name KMeshEditUI
extends Node
## "Model: edit a test cube (preview)" (ROADMAP_400 A05/A06): the first visible step of the MODEL page. A 4x4-per-side cube
## (side 0.6 m, resting on the floor beside the fighter) is added to the stage as a KMeshView; while it is active:
##   1 / 2 / 3  vertex / edge / face mode (the selection converts)      click  select the element under the mouse
##   Shift+click  toggle it in the selection                            B  box select (drag a rectangle), L  lasso (drag a loop)
##   drag from empty space  box select                                  X  x-ray (select through to the far side)
##   A  select all                                                      Esc  disarm B / L, or leave
##   Ctrl+Z  undo the last mesh edit (A12: "Model: subdivide the test cube (Catmull-Clark)" is one step)
##   K  add a shape key from the current shape (A13)                    [ / ]  the last key's value -0.1 / +0.1
##   T  measure the selection (B20, KMeshMeasure; follows the selection)  Shift+T  next material (the mass with the volume)
##   B05: Delete  delete the selection (Shift+Delete: only the faces)   Ctrl+Delete  dissolve it (verts / edges / faces)
##   M  merge at centre (Shift+M at the first, Alt+M by distance)       Ctrl+Z / Ctrl+Shift+Z  undo / redo
##   E  extrude (Shift+E: each face on its own)   I  inset (Shift+I: each face)   Ctrl+E  bridge two edge loops   (B02 / B03)
##   Ctrl+Z / Ctrl+Y  undo / redo the mesh step
##   Ctrl+T  triangulate (F06; the selected faces in face mode, else all)  Alt+J  triangles to quads (same rule)
##   H  topology heat map on / off (F08): poles, triangles, n-gons, stretched quads tinted, with a legend of counts
## Right / middle mouse still orbit and pan the camera. Nothing is written to the scene; the cube is dropped on leaving.
## B09: the "Add primitive" panel (left edge) adds a cube / plane / UV or ico sphere / cylinder / capsule / torus
## (scripts/kmesh_prims.gd) beside what is there, as ONE undo step; its fields stay live (each change rebuilds the new
## primitive and updates that same step) until the next edit of the mesh.

const SIDE := 0.6
const SPLIT := 4
const AT := Vector3(1.0, SIDE * 0.5, 0.0)   # on the floor, beside the fighter at the origin
const SUBDIV_MAX_FACES := 100000   # A12: one more level past this would make the preview crawl
const EXTRUDE_D := 0.05   # B02: E lifts the selection 5 cm along its normal (then G moves it on, with Blender keys on)
const INSET_D := 0.02     # B03: I insets 2 cm

var m: Node
var on := false
var mesh: KMesh
var sel: KMeshSelect
var view: KMeshView
var xray := false
var undo := KMeshUndo.new()   # B16: the Blender-style G / R / S edits, one step each
var armed := ""               # "", "box", "lasso"
var _press := Vector2.ZERO
var _drag := false
var _kind := ""               # the gesture in progress: "click", "box", "lasso"
var _add := false
var _lasso := PackedVector2Array()
var _ov: Control
var prim_panel: PanelContainer
var _prim_kind: OptionButton
var _prim_box: GridContainer
var _prim_fields := {}        # param -> SpinBox
var live := {}                # B09: the primitive still live: {kind, params, step, base_v, base_f, at}
const PRIM_GAP := 0.1         # m between the new primitive and what is already there
var meas: KMeshMeasure   # B20: the ruler + readout while measuring, else null
var legend: PanelContainer   # F08: the heat map's legend (built on first use)


func setup(main: Node) -> void:
	m = main
	_ov = Control.new()
	_ov.name = "kmesh_overlay"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.visible = false
	_ov.draw.connect(_draw_overlay)
	m.ui_root.add_child(_ov)
	_build_prim_panel()


func start() -> void:
	if on:
		return
	mesh = KMeshView.make_cube(SIDE, SPLIT)
	undo = KMeshUndo.new()
	sel = KMeshSelect.new(mesh, KMeshSelect.VERT)
	KMeshShapes.ensure(mesh)   # A13: the cube as made is the basis; K captures an edit as a key
	view = KMeshView.new()
	view.name = "kmesh_view"
	view.set_mesh(mesh, sel)
	m.stage_root.add_child(view)
	view.position = AT
	on = true
	armed = ""
	xray = false
	_ov.visible = true
	live = {}
	prim_panel.visible = true
	view.rebuild()
	m._say("Model: test cube. 1 / 2 / 3 vert / edge / face, click selects, Shift+click adds, B box, L lasso, X x-ray, Delete / Ctrl+Delete delete / dissolve, M merge, E extrude, I inset, Esc leaves")


func stop() -> void:
	if not on:
		return
	on = false
	_drag = false
	_ov.visible = false
	prim_panel.visible = false
	live = {}
	if legend != null:
		legend.visible = false
	view.queue_free()
	view = null
	meas = null
	m._say("Model: left the test cube (nothing was saved). Run Model: edit a test cube (preview) to come back")


func set_mode(md: int) -> void:
	sel.set_mode(md)
	view.mark_dirty()
	m._say("Model: %s mode, %d selected. Click an element, or B and drag a box" % [["vertex", "edge", "face"][md], sel.count()])
	_remeasure()


func _process(_dt: float) -> void:
	if meas != null and on:
		_ov.queue_redraw()   # the label follows the camera


## main passes every unhandled input here while `on`; true = used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).ctrl_pressed:
		# A12 / B05: Ctrl+Z / Ctrl+Shift+Z (or Ctrl+Y) are the mesh's own undo / redo while the cube is open, Ctrl+Delete dissolves, Ctrl+E bridges
		var ck := (ev as InputEventKey).keycode
		if not (ck in [KEY_DELETE, KEY_E, KEY_Y, KEY_T] or (ck == KEY_Z and not (undo.steps.is_empty() and not (ev as InputEventKey).shift_pressed))):
			return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := (ev as InputEventKey).keycode
		if k == KEY_T and (ev as InputEventKey).ctrl_pressed:
			topo("tri")
			return true
		if k == KEY_J and (ev as InputEventKey).alt_pressed:
			topo("quad")
			return true
		if k in [KEY_DELETE, KEY_M] or (k == KEY_Z and (ev as InputEventKey).ctrl_pressed):
			_b05_key(ev as InputEventKey)
			return true
		if _edit_key(ev as InputEventKey):
			return true
		if k == KEY_H and not (ev as InputEventKey).ctrl_pressed and not (ev as InputEventKey).alt_pressed:
			topo("heat")
			return true
		match k:
			KEY_1:
				set_mode(KMeshSelect.VERT)
			KEY_2:
				set_mode(KMeshSelect.EDGE)
			KEY_3:
				set_mode(KMeshSelect.FACE)
			KEY_B:
				armed = "box"
				m._say("Model: drag a rectangle to box select (Shift adds, X toggles x-ray, Esc cancels)")
			KEY_L:
				armed = "lasso"
				m._say("Model: drag a loop to lasso select (Shift adds, X toggles x-ray, Esc cancels)")
			KEY_X:
				xray = not xray
				m._say("Model: x-ray %s: box and lasso %s" % ["on" if xray else "off", "select through to the far side" if xray else "only take what you can see"])
			KEY_T:
				_measure_key((ev as InputEventKey).shift_pressed)
			KEY_A:
				sel.select_all()
				view.mark_dirty()
				m._say("Model: all %d selected. Click empty space to clear" % sel.count())
				_remeasure()
			KEY_K:
				add_shape_key()
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				nudge_shape_key(-0.1 if k == KEY_BRACKETLEFT else 0.1)
			KEY_ESCAPE:
				if armed != "" or _drag:
					armed = ""
					_drag = false
					_ov.queue_redraw()
					m._say("Model: B / L cancelled. Esc again leaves the test cube")
				else:
					stop()
			_:
				return false
		return true
	if ev is InputEventKey:
		return false
	var cam: Camera3D = m.cam
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			_press = mb.position
			_add = mb.shift_pressed
			_drag = true
			_lasso = PackedVector2Array([mb.position])
			_cur = mb.position
			if armed != "":
				_kind = armed
			else:
				if view.click(cam, mb.position, _add):
					_kind = "click"
					_report()
				else:
					_kind = "box"   # a press on empty space starts a box; released in place it just clears
					if not _add:
						view.mark_dirty()
			return true
		if not _drag:
			return false
		_drag = false
		var moved := mb.position.distance_to(_press) > 4.0
		match _kind:
			"box":
				if moved:
					view.select_box(cam, Rect2(_press, Vector2.ZERO).expand(mb.position), xray, _add)
					_report()
				elif armed == "":
					_report()
			"lasso":
				if moved:
					view.select_lasso(cam, _lasso, xray, _add)
					_report()
		if armed != "":
			armed = ""
		_ov.queue_redraw()
		return true
	if ev is InputEventMouseMotion and _drag:
		var mp := (ev as InputEventMouseMotion).position
		if _kind == "lasso" and (_lasso.is_empty() or _lasso[_lasso.size() - 1].distance_to(mp) > 3.0):
			_lasso.append(mp)
		_ov.queue_redraw()
		_cur = mp
		return true
	return false


var _cur := Vector2.ZERO
var _stats_sig := ""
var _stats_line := ""


## A14: the mesh's counts for the status line's readout (main.bar_text, every frame while `on`). Recounted only when
## the counts, the selection or the undo stack change (a move of verts changes no count)
func stats_text() -> String:
	if not on or mesh == null:
		return ""
	var sig := "%d %d %d %d %d %d" % [mesh.verts.size(), mesh.faces.size(), mesh.half_edge_count(), sel.mode, sel.count(), undo.steps.size()]
	if sig != _stats_sig:
		_stats_sig = sig
		_stats_line = KMeshStats.line(KMeshStats.of(mesh, sel))
	return _stats_line


## A12: Catmull-Clark the whole test cube `levels` times (scripts/kmesh_subdiv.gd), one undo step; the selection is cleared
## (its indices were the old mesh's)
func subdivide(levels := 1) -> void:
	var nf := mesh.domain_count(KMesh.AD_CORNER)   # level 1 makes one quad per corner, each level after 4 per quad
	for i in levels - 1:
		nf *= 4
	if nf > SUBDIV_MAX_FACES:
		m._say("Model: subdividing would make " + str(nf) + " faces, past the preview's " + str(SUBDIV_MAX_FACES) + ". Ctrl+Z a step back first")
		return
	undo.begin(mesh)
	var r := KMeshSubdiv.subdivide(mesh, levels)
	mesh.attrs = {}   # the new channels are sized for the new faces: from_arrays must not fit the old ones
	mesh.from_arrays(r.verts, r.faces)
	mesh.attrs = r.attrs
	undo.commit("subdivide")
	sel.clear()
	view.mark_dirty()
	m._say("Model: subdivided (Catmull-Clark), now " + str(mesh.face_count()) + " faces. Ctrl+Z takes it back")


## A13 K: the current shape becomes a new key at value 1 (the others go to 0, so the cube does not move); one undo step
func add_shape_key() -> int:
	undo.begin(mesh)
	var i := KMeshShapes.add_from_current(mesh, "Key %d" % (KMeshShapes.keys(mesh).size() + 1), KMeshShapes.BASIS, 1.0)
	if i < 0:
		undo.commit("cancelled")
		m._say("Model: " + KMeshShapes.last_error)
		return i
	for j in KMeshShapes.keys(mesh).size():
		if j != i:
			KMeshShapes.keys(mesh)[j]["value"] = 0.0
	KMeshShapes.apply(mesh)
	undo.commit("Add shape key")
	view.mark_dirty()
	m._say("Model: shape key '%s' added at weight 1.0 ([ / ] change it, Ctrl+Z takes it back)" % KMeshShapes.keys(mesh)[i]["name"])
	return i


## A13 [ / ]: the last key's value up or down, the cube re-blended; one undo step
func nudge_shape_key(dv: float) -> float:
	var ks := KMeshShapes.keys(mesh)
	if ks.is_empty():
		m._say("Model: no shape keys yet. Move vertices (G), then K adds the shape as a key")
		return NAN
	var k: Dictionary = ks[ks.size() - 1]
	undo.begin(mesh)
	var v := KMeshShapes.set_value(mesh, k["name"], snappedf(float(k["value"]) + dv, 0.01))
	KMeshShapes.apply(mesh)
	undo.commit("Shape key value")
	view.mark_dirty()
	m._say("Model: shape key '%s' at weight %.1f ([ lowers, ] raises, Ctrl+Z takes it back)" % [k["name"], v])
	return v


## B20: T turns the measure on / off; Shift+T (turning it on if needed) steps the material for the mass
func _measure_key(shift: bool) -> void:
	if meas != null and not shift:
		meas.queue_free()
		meas = null
		_ov.queue_redraw()
		m._say("Model: measure off")
		return
	if meas == null:
		meas = KMeshMeasure.new()
		meas.name = "kmesh_measure"
		view.add_child(meas)
	if shift:
		meas.cycle_material()
	_remeasure()


func _remeasure() -> void:
	if meas == null:
		return
	var r := meas.measure(mesh, sel)
	_ov.queue_redraw()
	m._say("Model: measure %s%s" % [r["text"], "" if meas.material == "" else " (%s %.0f kg/m³)" % [meas.material, meas.density]])


## B05: delete / dissolve / merge on the selection, one undo step each
func _b05_key(e: InputEventKey) -> void:
	if e.keycode == KEY_Z:
		var lb := undo.redo() if e.shift_pressed else undo.undo()
		sel.clear()
		view.mark_dirty()
		if view.show_heat:
			view.rebuild()   # F08: the legend counts the mesh as it is now
		_legend_update()
		m._say("Model: %s %s" % ["redone" if e.shift_pressed else "undone", lb if lb != "" else "(nothing to %s)" % ("redo" if e.shift_pressed else "undo")])
		return
	var it := KMeshDissolve.from_select(sel)
	var before := "%s verts %s faces" % [str(mesh.vert_count()), str(mesh.face_count())]
	var what := ""
	var md: String = ["verts", "edges", "faces"][sel.mode]
	undo.begin(mesh)
	if e.keycode == KEY_M and e.alt_pressed:
		what = "merged %d by distance" % KMeshDissolve.merge_by_distance(mesh, KMeshDissolve.MERGE_DIST, it["verts"])
	elif e.keycode == KEY_M:
		KMeshDissolve.merge(mesh, it["verts"], "first" if e.shift_pressed else "centre")
		what = "merged at %s" % ("the first" if e.shift_pressed else "the centre")
	elif e.ctrl_pressed:
		match sel.mode:
			KMeshSelect.VERT:
				KMeshDissolve.dissolve_verts(mesh, it[md])
			KMeshSelect.EDGE:
				KMeshDissolve.dissolve_edges(mesh, it[md])
			_:
				KMeshDissolve.dissolve_faces(mesh, it[md])
		what = "dissolved the " + md
	else:
		var kind := "only_faces" if e.shift_pressed and sel.mode == KMeshSelect.FACE else md
		KMeshDissolve.delete(mesh, kind, it[md])
		what = "deleted the " + kind.replace("_", " ")
	if undo.commit(what).is_empty():   # nothing changed: no step kept
		m._say("Model: nothing to do. Select %s first (Delete deletes, Ctrl+Delete dissolves, M merges)" % ("two or more verts" if e.keycode == KEY_M else "something"))
		return
	sel.clear()
	view.mark_dirty()
	m._say("Model: %s: %s now %s verts %s faces. Ctrl+Z undoes" % [what, before, str(mesh.vert_count()), str(mesh.face_count())])


## B02 / B03 (scripts/kmesh_extrude.gd): E extrude, I inset, Ctrl+E bridge, Ctrl+Z / Ctrl+Y undo / redo; true = used
func _edit_key(k: InputEventKey) -> bool:
	if k.ctrl_pressed and (k.keycode == KEY_Z or k.keycode == KEY_Y):
		var lb := undo.undo() if k.keycode == KEY_Z else undo.redo()
		sel.clear()
		view.mark_dirty()
		m._say("Model: %s %s" % ["undone:" if k.keycode == KEY_Z else "redone:", lb] if lb != "" else "Model: nothing to %s on the test cube" % ("undo" if k.keycode == KEY_Z else "redo"))
		return true
	if not (k.keycode == KEY_E or k.keycode == KEY_I) or k.alt_pressed or (k.ctrl_pressed and k.keycode == KEY_I):
		return false
	var each := k.shift_pressed
	var what := "Bridge" if k.ctrl_pressed else ("Extrude" if k.keycode == KEY_E else "Inset")
	undo.begin(mesh)
	var r: Dictionary
	match what:
		"Bridge":
			r = KMeshExtrude.bridge(mesh, sel)
		"Extrude":
			r = KMeshExtrude.extrude(mesh, sel, EXTRUDE_D, each)
		_:
			r = KMeshExtrude.inset(mesh, sel, INSET_D, each)
	undo.commit(what)
	view.mark_dirty()
	if String(r.get("error", "")) != "":
		m._say("Model: %s: %s" % [what.to_lower(), r["error"]])
	elif what == "Bridge":
		m._say("Model: bridged the two loops with a ring of new faces (Ctrl+Z takes it back)")
	else:
		m._say("Model: %s by %s%s; the new part is selected (Ctrl+Z takes it back)" % [what.to_lower(), Units.len(EXTRUDE_D if what == "Extrude" else INSET_D), ", each face on its own" if each else ""])
	return true


func _report() -> void:
	if meas != null:
		_remeasure()
		return
	var nm: String = ["vertices", "edges", "faces"][sel.mode]
	if sel.count() == 0:
		m._say("Model: nothing selected. Click an element, or B and drag a box")
	else:
		m._say("Model: %d %s selected (Shift+click adds, 1 / 2 / 3 converts)" % [sel.count(), nm])


func _draw_overlay() -> void:
	if on and meas != null:
		meas.draw_label(_ov, m.cam)
	if not on or not _drag:
		return
	var c := Tok.c("pick_hover")
	if _kind == "box":
		var r := Rect2(_press, Vector2.ZERO).expand(_cur)
		_ov.draw_rect(r, Color(c, 0.15), true)
		_ov.draw_rect(r, c, false, 1.0)
	elif _kind == "lasso" and _lasso.size() > 1:
		_ov.draw_polyline(_lasso, c, 1.5)


# ---- B09: Add primitive ---------------------------------------------------------------------------------------------

func _build_prim_panel() -> void:
	prim_panel = PanelContainer.new()
	prim_panel.name = "prim_panel"
	prim_panel.visible = false
	var vb := VBoxContainer.new()
	var title := Label.new()
	title.text = "Add primitive"
	vb.add_child(title)
	var hb := HBoxContainer.new()
	_prim_kind = OptionButton.new()
	_prim_kind.name = "opt_prim_kind"
	for k in KMeshPrims.KINDS:
		_prim_kind.add_item(KMeshPrims.NAMES[k])
	_prim_kind.item_selected.connect(func(i): _prim_fields_for(KMeshPrims.KINDS[i]))
	hb.add_child(_prim_kind)
	var add := Button.new()
	add.name = "btn_prim_add"
	add.text = "Add"
	add.tooltip_text = "add this primitive beside the mesh (one undo step); its fields stay live until the next edit"
	add.pressed.connect(func(): add_prim(KMeshPrims.KINDS[_prim_kind.selected], _field_params()))
	hb.add_child(add)
	vb.add_child(hb)
	_prim_box = GridContainer.new()
	_prim_box.columns = 2
	vb.add_child(_prim_box)
	prim_panel.add_child(vb)
	m.ui_root.add_child(prim_panel)
	_prim_fields_for(KMeshPrims.KINDS[0])


## the param fields of one kind, at its defaults; lengths are shown in cm
func _prim_fields_for(kind: String, vals := {}) -> void:
	for c in _prim_box.get_children():
		_prim_box.remove_child(c)
		c.queue_free()
	_prim_fields = {}
	for p in KMeshPrims.PARAMS[kind]:
		var l := Label.new()
		l.text = String(p[0]).replace("_", " ") + (" (cm)" if p[5] else "")
		_prim_box.add_child(l)
		var s := SpinBox.new()
		s.name = "spin_prim_" + p[0]
		var k := 100.0 if p[5] else 1.0
		s.min_value = float(p[2]) * k
		s.max_value = float(p[3]) * k
		s.step = float(p[4]) * k
		s.value = float(vals.get(p[0], p[1])) * k
		s.value_changed.connect(func(_v): set_prim_param(p[0], _field_params()[p[0]]))
		_prim_box.add_child(s)
		_prim_fields[p[0]] = s
	prim_panel.reset_size()
	prim_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 12)


func _field_params() -> Dictionary:
	var kind: String = KMeshPrims.KINDS[_prim_kind.selected]
	var d := {}
	for p in KMeshPrims.PARAMS[kind]:
		var s: SpinBox = _prim_fields.get(p[0])
		if s != null:
			d[p[0]] = s.value / 100.0 if p[5] else int(s.value)
	return d


## the primitive's verts moved to its place: resting on the mesh's floor, PRIM_GAP to the +X side of it
func _placed(pm: KMesh, at: Vector3) -> PackedVector3Array:
	var lo := Vector3.INF
	for v in pm.verts:
		lo = lo.min(v)
	var out := PackedVector3Array()
	out.resize(pm.verts.size())
	for i in pm.verts.size():
		out[i] = pm.verts[i] + Vector3(at.x - lo.x, at.y - lo.y, at.z)
	return out


func _append(base_v: PackedVector3Array, base_f: Array, pm: KMesh, at: Vector3) -> void:
	var vs := base_v.duplicate()
	vs.append_array(_placed(pm, at))
	var fs := base_f.duplicate()
	var o := base_v.size()
	for f in pm.faces:
		var g := PackedInt32Array(f)
		for i in g.size():
			g[i] += o
		fs.append(g)
	mesh.attrs = {}   # (the test mesh carries no attributes; a primitive starts without any)
	mesh.from_arrays(vs, fs)


## add a primitive beside the mesh as one undo step; it stays live (set_prim_param rebuilds it) until the next edit
func add_prim(kind: String, params := {}) -> bool:
	if not on or not KMeshPrims.KINDS.has(kind):
		return false
	var p := KMeshPrims.clean(kind, params)
	var pm := KMeshPrims.build(kind, p)
	var at := Vector3.ZERO
	if mesh.vert_count() > 0:
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for v in mesh.verts:
			lo = lo.min(v)
			hi = hi.max(v)
		at = Vector3(hi.x + PRIM_GAP, lo.y, 0.0)
	var base_v := mesh.verts.duplicate()
	var base_f := mesh.faces.duplicate()
	undo.begin(mesh)
	_append(base_v, base_f, pm, at)
	var st := undo.commit("Add " + KMeshPrims.NAMES[kind])
	live = {"kind": kind, "params": p, "step": st, "base_v": base_v, "base_f": base_f, "at": at}
	_after_topo()
	var ki := KMeshPrims.KINDS.find(kind)
	if _prim_kind.selected != ki:
		_prim_kind.select(ki)
	_prim_fields_for(kind, p)
	m._say("Model: added a %s (%s verts, %s faces; one undo step). Its fields stay live until the next edit" % [KMeshPrims.NAMES[kind].to_lower(), str(pm.vert_count()), str(pm.face_count())])
	return true


## is the last added primitive still live: its step is the newest one and the mesh is still exactly what it made
func is_live() -> bool:
	if live.is_empty() or undo.steps.is_empty() or not is_same(undo.steps[undo.steps.size() - 1], live["step"]):
		return false
	var st: Dictionary = live["step"]
	return mesh.verts == st["new_v"] and KMeshUndo._same_faces(mesh.faces, st["new_f"])


## change one live parameter: the primitive is rebuilt in place and its undo step updated (still one step)
func set_prim_param(param: String, value) -> bool:
	if not on:
		return false
	if not is_live():
		live = {}
		return false
	var p: Dictionary = live["params"].duplicate()
	p[param] = value
	p = KMeshPrims.clean(live["kind"], p)
	if p == live["params"]:
		return true
	var pm := KMeshPrims.build(live["kind"], p)
	_append(live["base_v"], live["base_f"], pm, live["at"])
	var st: Dictionary = live["step"]
	st["new_v"] = mesh.verts.duplicate()
	st["new_f"] = mesh.faces.duplicate()
	var fb := 0
	for f in st["old_f"]:
		fb += (f as PackedInt32Array).size() * 4
	for f in st["new_f"]:
		fb += (f as PackedInt32Array).size() * 4
	st["bytes"] = ((st["old_v"] as PackedVector3Array).size() + mesh.verts.size()) * 12 + fb
	live["params"] = p
	_after_topo()
	return true


## the topology changed: a fresh selection on the same mesh, the view rebuilt
func _after_topo() -> void:
	sel = KMeshSelect.new(mesh, sel.mode)
	view.set_mesh(mesh, sel)
	view.rebuild()
# ---------------------------------------------------------------- F06 / F08

## "tri" (triangulate), "quad" (tris to quads): the selected faces in face mode, else every face; one KMeshUndo step.
## "heat": the topology heat map on / off.
func topo(what: String) -> void:
	if not on:
		return
	if what == "heat":
		view.show_heat = not view.show_heat
		view.rebuild()
		_legend_update()
		if view.show_heat:
			m._say("Model: topology heat map on: " + KMeshTopo.words(view.heat) + ". H turns it off")
		else:
			m._say("Model: topology heat map off (H turns it on)")
		return
	var only = sel.faces.keys() if sel.mode == KMeshSelect.FACE and not sel.faces.is_empty() else null
	var nf0 := mesh.face_count()
	undo.begin(mesh)
	var r := KMeshTopo.triangulate(mesh, only) if what == "tri" else KMeshTopo.quadrangulate(mesh, only)
	var st := undo.commit("triangulate" if what == "tri" else "tris to quads")
	sel.clear()
	view.mark_dirty()
	view.rebuild()
	_legend_update()
	var scope := "the selected faces" if only != null else "the whole mesh"
	if st.is_empty():
		m._say("Model: nothing to %s in %s (%s)" % ["triangulate" if what == "tri" else "join", scope, "every face is already a triangle" if what == "tri" else "no pair of triangles is flat and square enough"])
	elif what == "tri":
		m._say("Model: triangulated %s: %d faces became %d triangles (%d faces now). Ctrl+Z undoes" % [scope, int(r["faces"]), int(r["tris"]), mesh.face_count()])
	else:
		m._say("Model: tris to quads on %s: %d quads made, %d triangles left (%d faces, was %d). Ctrl+Z undoes" % [scope, int(r["quads"]), int(r["left"]), mesh.face_count(), nf0])


func _legend_update() -> void:
	if legend == null:
		legend = PanelContainer.new()
		legend.name = "topo_legend"
		legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(Tok.c("float"), 0.92)
		st.set_corner_radius_all(8)
		st.set_content_margin_all(8)
		legend.add_theme_stylebox_override("panel", st)
		var vb := VBoxContainer.new()
		vb.name = "rows"
		vb.add_theme_constant_override("separation", 3)
		legend.add_child(vb)
		vb.add_child(m._label("Topology heat map (H)", 14, "text"))
		for r in KMeshTopo.LEGEND:
			var row := HBoxContainer.new()
			row.name = r[0]
			row.add_theme_constant_override("separation", 6)
			var sw := ColorRect.new()
			sw.name = "swatch"
			sw.color = r[3]
			sw.custom_minimum_size = Vector2(14, 14)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(sw)
			var lb: Label = m._label("", 13, "text:0.8")
			lb.name = "words"
			row.add_child(lb)
			vb.add_child(row)
		m.ui_root.add_child(legend)
	legend.visible = on and view != null and view.show_heat
	if not legend.visible:
		return
	var c: Dictionary = view.heat["counts"]
	for r in KMeshTopo.LEGEND:
		var lb: Label = legend.get_node("rows/%s/words" % r[0])
		lb.text = "%s: %d  (%s)" % [r[1], int(c[r[0]]), r[2]]
	legend.reset_size()
	var cl: Rect2 = m.nav_clear_rect()
	legend.position = Vector2(cl.position.x + 12.0, cl.end.y - legend.get_combined_minimum_size().y - 12.0)
