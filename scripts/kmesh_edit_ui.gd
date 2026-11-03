class_name KMeshEditUI
extends Node
## "Model: edit a test cube (preview)" (ROADMAP_400 A05/A06): the first visible step of the MODEL page. A 4x4-per-side cube
## (side 0.6 m, resting on the floor beside the fighter) is added to the stage as a KMeshView; while it is active:
##   1 / 2 / 3  vertex / edge / face mode (the selection converts)      click  select the element under the mouse
##   Shift+click  toggle it in the selection                            B  box select (drag a rectangle), L  lasso (drag a loop)
##   drag from empty space  box select                                  X  x-ray (select through to the far side)
##   A  select all                                                      Esc  disarm B / L, or leave
##   G / R / S  grab / rotate / scale the selected vertices (on the model preview WITHOUT the Blender-keys layer; then X / Y / Z,
##      a typed number, click or Enter keeps, Esc or right click cancels; O proportional, the wheel its radius: scripts/bl_keys.gd)
##   Alt+click  select the edge LOOP through the edge under the mouse (Shift+Alt+click adds it; kmesh_select.gd select_loop)
##   click again at the same spot (face mode, within 3 px and 0.6 s)  the face BEHIND the one picked, and so on, wrapping (C45, kmesh_pickstack.gd)
##   Ctrl+1 / Ctrl+2 / Ctrl+3  a Subdivide modifier at level 1 / 2 / 3 on the stack (one undo step; the modifiers panel)
##   Ctrl+Z  undo the last mesh edit (A12: "Model: subdivide the test cube (Catmull-Clark)" is one step)
##   K  add a shape key from the current shape (A13)                    [ / ]  the last key's value -0.1 / +0.1
##   T  measure the selection (B20, KMeshMeasure; follows the selection)  Shift+T  next material (the mass with the volume)
##   B05: Delete  delete the selection (Shift+Delete: only the faces)   Ctrl+Delete  dissolve it (verts / edges / faces)
##   M  merge at centre (Shift+M at the first, Alt+M by distance)       Ctrl+Z / Ctrl+Shift+Z  undo / redo
##   E  extrude, I  inset (Shift: each face on its own): live, the mouse sets the distance (from where E / I was pressed),
##      click or Enter confirms (one undo step), Esc or right click cancels (nothing changed), a typed number sets it exactly
##      (scripts/kmesh_drag_op.gd)   Ctrl+E  bridge two edge loops   (B02 / B03)
##   Ctrl+B  bevel the selected edges (2 cm, 1 segment, round; B03, kmesh_bevel.gd): live until the next edit, [ / ] segments, Shift+[ / ] width, Alt+[ / ] profile
##   Ctrl+Z / Ctrl+Y  undo / redo the mesh step
##   B06: F  make a face (2 verts: an edge)   Alt+F  fill the holes touching the selection (Shift+Alt+F: triangles)   Ctrl+F  grid fill
##   Ctrl+T  triangulate (F06; the selected faces in face mode, else all)  Alt+J  triangles to quads (same rule)
##   Ctrl+R  loop cut (hover, wheel = cuts, click cuts; Shift+click slides first, then click)   Shift+K  knife   V  edge split   (B04, kmesh_cut_tool.gd)
##   H  topology heat map on / off (F08): poles, triangles, n-gons, stretched quads tinted, with a legend of counts
##   U  surface shading: plain -> UV checker -> UV stretch heat (D05; the first U unwraps: seams where faces meet at
##      over 60 deg, then LSCM, KMeshUV)
##   O  proportional editing on / off (B07, KMeshProportional; Shift+O falloff, Alt+O connected only, wheel = radius in G)
##   Shift+H  colour by body region on / off (A18, KMeshBody: every vert's nearest bone + region, kept fresh every frame;
##      a legend bottom right, the hover readout at the mouse)
##   Ctrl+P  pack the UV islands (D04, KMeshUVPack: 4 px margin, each island turned to its smallest box, equal texel density; one undo step)
##   Shift+U  the UV editor panel on / off (D01, scripts/kmesh_uv_editor.gd: select / move / rotate / scale UVs)
##   Alt+H  colour by anatomy on / off (A19, KMeshAnatomy: deltoid, patella, knuckles ... per vert, carried through edits);
##      while on, Alt+drag paints the brush tag (one undo step a stroke), Alt+Shift+click picks the tag under the mouse
##   B08 / B14 (Blender keys on, G / R / S): Ctrl held while moving snaps (scripts/kmesh_snap.gd); Shift+Tab  next snap
##      target (vertex, edge, midpoint, face, grid 1 / 5 / 10 cm, the fighter's skin)   .  next pivot for R / S (median,
##      active, 3D cursor, individual origins; scripts/kmesh_pivot.gd)   Shift+right-click  put the 3D cursor there
## Right / middle mouse still orbit and pan the camera. Nothing is written to the scene; the cube is dropped on leaving.
## B09: the "Add primitive" panel (left edge) adds a cube / plane / UV or ico sphere / cylinder / capsule / torus
## (scripts/kmesh_prims.gd) beside what is there, as ONE undo step; its fields stay live (each change rebuilds the new
## primitive and updates that same step) until the next edit of the mesh.
## A11: the "Modifiers" panel (right edge, scripts/kmesh_modifiers_ui.gd): a non-destructive stack, the view shows its result.

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
var prop := KMeshProportional.new()   # B07: proportional editing for the Blender-style G / R / S
var body: KMeshBody          # A18: the body labels of the mesh + the colour-by-region view
var mods: KMeshModifiersUI   # A11: the modifier stack panel + the evaluated surface
var uved: KMeshUVEditor   # D01: the UV editor panel (built on first Shift+U)
var mat_panel: KMeshMaterialPanel   # E01: the Materials panel (top right; shows itself while `on`)
var anat: KMeshAnatomy       # A19: the anatomy tags + the colour-by-anatomy view and its brush
var source: Callable   # G01 (scripts/base_body.gd): what mesh to open, -> {"mesh": KMesh, "at": Transform3D}; empty = the test cube
var left: Callable     # G01: called after leaving (the fighter shows again)
var snap: KMeshSnap      # B08: snapping during G / R / S (Ctrl), its target (Shift+Tab) and marker
var pivot: KMeshPivot    # B14: the pivot for R / S (.) and the 3D cursor (Shift+right-click)
var refp: KMeshRefPlanesUI   # B21: reference images on planes + their panel (scripts/kmesh_refplanes_ui.gd)
var files: KMeshFileUI       # the mesh file: Ctrl+S (save), Save / Open... on the MESH group (scripts/kmesh_file_ui.gd)
var _model_page := true       # the page is MODEL (the side panels show); set_showing
var _mp_prev := true          # the MODEL panels were shown at the last set_showing
var showing := true          # the page shows this mesh (MODEL, SURFACE); off on the other pages: hidden, never stopped (set_showing)
var _mods_back := false      # the Modifiers panel was open when the page left it
var _uv_back := false        # the UV editor was open when the page left it


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
	mods = KMeshModifiersUI.new()
	add_child(mods)
	mods.setup(self)
	mat_panel = KMeshMaterialPanel.new(self)
	m.ui_root.add_child(mat_panel)
	snap = KMeshSnap.new()
	add_child(snap)
	snap.setup(self)
	pivot = KMeshPivot.new()
	add_child(pivot)
	pivot.setup(self)
	refp = KMeshRefPlanesUI.new()
	add_child(refp)
	refp.setup(self)
	files = KMeshFileUI.new()   # the mesh file: Ctrl+S, Save, Open... (scripts/kmesh_file_ui.gd)
	add_child(files)
	files.setup(self)
	var steps := MeshSteps.new()   # P151 model from words: the typed steps panel (scripts/mesh_steps.gd), shown on the MODEL page only
	m.ui_root.add_child(steps)
	steps.setup(self)


func start() -> void:
	if on:
		return
	var src: Dictionary = source.call() if source.is_valid() else {}
	mesh = src["mesh"] if src.has("mesh") else KMeshView.make_cube(SIDE, SPLIT)
	undo = KMeshUndo.new()
	sel = KMeshSelect.new(mesh, KMeshSelect.VERT)
	undo.sel = sel   # the undo steps keep the picks (Ctrl+Z puts back the selection the edit started from)
	KMeshShapes.ensure(mesh)   # A13: the cube as made is the basis; K captures an edit as a key
	view = KMeshView.new()
	view.name = "kmesh_view"
	view.set_mesh(mesh, sel)
	m.stage_root.add_child(view)
	view.position = AT
	if src.has("at"):
		view.transform = src["at"]
	on = true
	armed = ""
	xray = false
	_ov.visible = true
	live = {}
	prim_panel.visible = true
	view.rebuild()
	if body == null:
		body = KMeshBody.new()
		body.setup(self)
		add_child(body)
	body.tick()   # A18: labelled from the first frame
	mods.open()
	if anat == null:
		anat = KMeshAnatomy.new()
		anat.setup(self)
		add_child(anat)
	anat.tick()   # A19: tagged from the first frame
	m._say("Model: test cube. 1 / 2 / 3 vert / edge / face, click selects, Shift+click adds, Alt+click an edge loop, click twice quickly = the face behind, B box, L lasso, G R S move rotate scale, E extrude, I inset, Ctrl+1 subdivide, Delete, M merge, Esc leaves")


func stop() -> void:
	if not on:
		return
	on = false
	_drag = false
	_ov.visible = false
	prim_panel.visible = false
	mods.close()
	live = {}
	if legend != null:
		legend.visible = false
	if body != null:
		body.close()
	if uved != null:
		uved.close()
	if anat != null:
		anat.close()
	view.queue_free()
	view = null
	meas = null
	m._say("Model: left the test cube (nothing was saved). Run Model: edit a test cube (preview) to come back")
	if left.is_valid():
		left.call()


## the page shows the cube (MODEL, SURFACE) or not (the other pages). Off: the cube, its primitive / Modifiers / UV panels and
## its Materials panel are hidden, and its keys and clicks wait; nothing is stopped, so the edits, the undo and the open panels
## come back as they were. A body-mesh edit's fighter parts (base_body.gd, meta fighter_vis) are put back on leaving and hidden again
func set_showing(v: bool, model_page := true) -> void:
	if showing == v and model_page == _model_page:
		return
	showing = v
	_model_page = model_page
	var mp := v and model_page   # the MODEL side panels (Add primitive, Modifiers) belong to MODEL only: SURFACE shows the mesh and its Materials
	if view != null and on:
		view.visible = v
	if _ov != null:
		_ov.visible = on and v
	if prim_panel != null:
		prim_panel.visible = on and mp
	if mods != null and mods.panel != null:
		if not mp and _mp_prev:
			_mods_back = mods.panel.visible   # open when the MODEL panels go: back when MODEL comes back
		mods.panel.visible = mp and on and _mods_back
	_mp_prev = mp
	if uved != null:
		if not v:
			_uv_back = uved.visible
			uved.visible = false
		elif on and _uv_back:
			uved.visible = true
			uved.place()
	if has_meta("fighter_vis"):
		var fv: Dictionary = get_meta("fighter_vis")
		for mi in fv:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).visible = fv[mi] if not v else false


## the MODEL side panels are hidden on the other pages whatever opened the mesh (BaseBody.start's mods.open shows them)
func sync_panels() -> void:
	if not on or (showing and _model_page):
		return
	if mods != null and mods.panel != null and mods.panel.visible:
		_mods_back = true
		mods.panel.visible = false
	if prim_panel != null:
		prim_panel.visible = false


func set_mode(md: int) -> void:
	sel.set_mode(md)
	view.mark_dirty()
	m._say("Model: %s mode, %d selected. Click an element, or B and drag a box; then G R S move, rotate, scale" % [["vertex", "edge", "face"][md], sel.count()])
	_remeasure()


## a text box that still holds the keyboard eats Ctrl+Z / Ctrl+Y (LineEdit's own undo runs before the mesh sees the key):
## while the mesh is on, an empty one gives the key back; the view click above releases any other
func _input(ev: InputEvent) -> void:
	if on and ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).ctrl_pressed and (ev as InputEventKey).keycode in [KEY_Z, KEY_Y]:
		var fo := get_viewport().gui_get_focus_owner()
		if fo is LineEdit and (fo as LineEdit).text == "":
			fo.release_focus()


func _release_text_focus() -> void:
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit:
		fo.release_focus()


func _process(_dt: float) -> void:
	if on and (meas != null or prop.showing(m.blk) or not prop.last_circle.is_empty()):   # B07: one more frame clears the circle
		_ov.queue_redraw()   # the label follows the camera
	if body != null and on:
		body.tick()   # A18: the labels follow the mesh and the body
	if anat != null and on:
		anat.tick()   # A19: new verts tagged, the view fresh


## main passes every unhandled input here while `on`; true = used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	# B (walk-through 5): while the name box holds the keyboard (F2), its typing is its own (the letters are not tool keys);
	# Esc gives the keys back to the view and is used up there, so the cube stays open and F3 opens the search again
	if ev is InputEventKey and ev.pressed and not ev.echo and m.ui_scene_name != null and m.get_viewport().gui_get_focus_owner() == m.ui_scene_name:
		var kn := ev as InputEventKey
		if kn.keycode == KEY_ESCAPE:
			m.ui_scene_name.release_focus()
			return true
		if kn.keycode != KEY_F3 and kn.unicode > 0 and not kn.ctrl_pressed:
			return false
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_release_text_focus()   # a click on the view leaves a text box (the library search, the S box): Ctrl+Z goes to the mesh again
	if KMeshDragOp.handle(self, ev):   # E / I live drag: the mouse sets the distance, click / Enter confirms, Esc cancels (scripts/kmesh_drag_op.gd)
		return true
	if KMeshCutTool.handle(self, ev):   # B04: Ctrl+R loop cut, Shift+K knife, V edge split (modal while running)
		return true
	if KMeshCurvesUI.handle(self, ev):   # B12: drag a curve point / handle, Alt+click adds one (scripts/kmesh_curves_ui.gd)
		return true
	if refp.input(ev):   # B21: only the two-point clicks while armed
		return true
	if snap.input(ev) or pivot.input(ev):   # B08 / B14: Shift+Tab, ".", Shift+right-click (a left press only notes the active element)
		return true
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_S and (ev as InputEventKey).ctrl_pressed and not (ev as InputEventKey).shift_pressed and not (ev as InputEventKey).alt_pressed:
		files.save_cmd()   # Ctrl+S here saves the mesh file (POSE keeps its own Ctrl+S: main's pose box, off this page)
		return true
	if ev is InputEventKey and ev.pressed and not ev.echo and _ctrl_digit(ev as InputEventKey) > 0:
		_subdiv_key(_ctrl_digit(ev as InputEventKey))   # Blender's Ctrl+1..3: a Subdivide modifier at that level
		return true
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).ctrl_pressed:
		# A12 / B05: Ctrl+Z / Ctrl+Shift+Z (or Ctrl+Y) are the mesh's own undo / redo while the cube is open, Ctrl+Delete dissolves, Ctrl+E bridges
		var ck := (ev as InputEventKey).keycode
		if not (ck in [KEY_DELETE, KEY_E, KEY_Y, KEY_T, KEY_F, KEY_B, KEY_P] or (ck == KEY_Z and not (undo.steps.is_empty() and not (ev as InputEventKey).shift_pressed))):
			return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := (ev as InputEventKey).keycode
		if k == KEY_F2 and not (ev as InputEventKey).is_command_or_control_pressed() and not (ev as InputEventKey).shift_pressed and not (ev as InputEventKey).alt_pressed and m.ui_scene_name != null:
			# B (walk-through 5): F2 (rename) puts the caret in the name box, its text selected; Enter or Esc gives the view back
			m.ui_scene_name.grab_focus()
			m.ui_scene_name.select_all()
			return true
		if k == KEY_F3 and not (ev as InputEventKey).is_command_or_control_pressed() and not (ev as InputEventKey).shift_pressed and not (ev as InputEventKey).alt_pressed:
			# the S box (command search) from here: S is Scale in this mode (Blender), so the box cannot open on S (Blender's F3 = menu search)
			m.ui_cmd.open()
			return true
		if KMeshBevel.key(self, ev as InputEventKey):   # B03: Ctrl+B, and [ / ] while the bevel is live
			return true
		if k == KEY_T and (ev as InputEventKey).ctrl_pressed:
			topo("tri")
			return true
		if k == KEY_P and (ev as InputEventKey).ctrl_pressed:   # D04: pack the UV islands (KMeshUVPack), one undo step
			KMeshUVPack.run_ui(self, "pack")
			return true
		if k == KEY_J and (ev as InputEventKey).alt_pressed:
			topo("quad")
			return true
		if k in [KEY_DELETE, KEY_M] or (k == KEY_Z and (ev as InputEventKey).ctrl_pressed):
			_b05_key(ev as InputEventKey)
			return true
		if _edit_key(ev as InputEventKey) or KMeshFill.key(self, ev as InputEventKey):   # B06: F / Alt+F / Ctrl+F
			return true
		if k == KEY_O:   # B07
			m._say(prop.key(ev as InputEventKey, m.blk != null and m.blk.on))
			return true
		if k == KEY_H and (ev as InputEventKey).alt_pressed and not (ev as InputEventKey).ctrl_pressed:
			anat.toggle()   # A19
			return true
		if k == KEY_H and not (ev as InputEventKey).ctrl_pressed and not (ev as InputEventKey).alt_pressed:
			if (ev as InputEventKey).shift_pressed:
				if anat.on:
					anat.toggle()   # A19: one colouring at a time
				body.toggle()   # A18
			else:
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
			KEY_U when (ev as InputEventKey).shift_pressed:
				toggle_uv_editor()
			KEY_U:
				cycle_uv_shading()
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
		if anat != null and anat.on and (anat.stroking or (mb.pressed and mb.alt_pressed)):   # A19: the tag brush
			if mb.pressed:
				anat.press(mb.position, mb.shift_pressed)
			else:
				anat.release()
			_ov.queue_redraw()
			return true
		if mb.pressed:
			_press = mb.position
			_add = mb.shift_pressed
			_drag = true
			_lasso = PackedVector2Array([mb.position])
			_cur = mb.position
			if armed != "":
				_kind = armed
			elif mb.alt_pressed and _alt_loop(cam, mb.position, _add):   # Blender's Alt+click: the edge loop through that edge
				_kind = "click"
				_report()
			else:
				if not mb.alt_pressed and _click_behind(cam, mb.position, _add):   # C45: a quick second click at the same spot = the face behind
					_kind = "click"
				elif view.click(cam, mb.position, _add):
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
	if ev is InputEventMouseMotion and anat != null and anat.on:
		if anat.stroking:
			anat.drag((ev as InputEventMouseMotion).position)   # A19: the stroke goes on
			return true
		if not _drag:
			anat.hover((ev as InputEventMouseMotion).position)
			_ov.queue_redraw()
	if ev is InputEventMouseMotion and not _drag and body != null and body.on:
		body.hover((ev as InputEventMouseMotion).position)   # A18: the readout follows the mouse (the event goes on)
		_ov.queue_redraw()
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
		sel.restore(undo.last_sel)
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


var _stack := KMeshPickStack.new()   # C45
var _click_ms := -100000
var _click_p := Vector2(-1.0e6, -1.0e6)
var _click_n := 0


## C45: the 2nd, 3rd ... plain click within 3 px and 0.6 s of the last one (face mode, no Shift) walks the faces behind the first pick.
## A first click, a click elsewhere or a slow click is the ordinary click (false: the caller does it).
func _click_behind(cam: Camera3D, p: Vector2, add: bool) -> bool:
	var now := Time.get_ticks_msec()
	var again := sel.mode == KMeshSelect.FACE and not add and now - _click_ms <= 600 and p.distance_to(_click_p) <= KMeshPickStack.SAME_SPOT_PX
	_click_ms = now
	if not again:
		_click_p = p
		_click_n = 1
		return false
	if _click_n == 1:
		_stack.last_p = Vector2(-1.0e6, -1.0e6)   # build the stack, front face first
		_stack.next(view, cam, p)
	_click_n += 1
	return _alt_behind(cam, p, false)


## C45 (M #233): a repeated plain click in face mode picks the face under the mouse, and each Alt+click at the same spot the next one BEHIND it
## (nothing is deleted); the picked face is named in the status line and highlighted by the selection. False on a miss.
func _alt_behind(cam: Camera3D, p: Vector2, add: bool) -> bool:
	var r := _stack.next(view, cam, p)
	if r.is_empty():
		return false
	var fi: int = r["face"]
	if not add:
		sel.clear()
	sel.faces[fi] = true
	view.mark_dirty()
	m._say("Model: face %d, %d of %d under the mouse (click again quickly for the one behind it)" % [fi, int(r["depth"]), int(r["of"])])
	return true


## Alt+click on an edge (Blender): the edge loop through it. False when no edge is under the mouse (then the click is a plain one).
func _alt_loop(cam: Camera3D, p: Vector2, add: bool) -> bool:
	var h: Dictionary = view.pick(cam, p)
	if h.is_empty() or (h["edge"] as Vector2i).x < 0:
		return false
	var e: Vector2i = h["edge"]
	sel.select_loop(e.x, e.y, add)
	view.mark_dirty()
	m._say("Model: edge loop selected (%d edges). Shift+Alt+click adds another loop; S scales it, G moves it" % sel.count())
	return true


## Ctrl+1..3 alone (no Shift / Alt): the digit 1..3, else 0
static func _ctrl_digit(k: InputEventKey) -> int:
	if not k.ctrl_pressed or k.alt_pressed or k.shift_pressed or k.keycode not in [KEY_1, KEY_2, KEY_3]:
		return 0
	return int(k.keycode - KEY_0)


## Ctrl+1..3 (Blender): a Subdivide modifier at `levels` on the stack; if the stack refuses it, the mesh is subdivided
## by the direct path (subdivide), which says so in the status line.
func _subdiv_key(levels: int) -> void:
	if mods == null or mods.add_level(levels) < 0:   # the stack refused it (its status said why): subdivide the mesh, which says so
		subdivide(levels)


## Ctrl+Z / Ctrl+Y, and the top bar's Undo / Redo buttons while this page shows (walk13: they only knew pose undo)
func undo_redo(back: bool) -> void:
	var lb := undo.undo() if back else undo.redo()
	sel.restore(undo.last_sel)
	view.mark_dirty()
	m._say("Model: %s %s" % ["undone:" if back else "redone:", lb] if lb != "" else "Model: nothing to %s on the test cube" % ("undo" if back else "redo"))


## B02 / B03 (scripts/kmesh_extrude.gd): E extrude, I inset, Ctrl+E bridge, Ctrl+Z / Ctrl+Y undo / redo; true = used
func _edit_key(k: InputEventKey) -> bool:
	if k.ctrl_pressed and (k.keycode == KEY_Z or k.keycode == KEY_Y):
		undo_redo(k.keycode == KEY_Z)
		return true
	if not (k.keycode == KEY_E or k.keycode == KEY_I) or k.alt_pressed or (k.ctrl_pressed and k.keycode == KEY_I):
		return false
	if not k.ctrl_pressed and KMeshDragOp.start(self, "extrude" if k.keycode == KEY_E else "inset", k.shift_pressed):
		return true   # E / I with a selection: the live drag (KMeshDragOp); nothing selected: the immediate path below reports it
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


## The ribbon's Extrude / Inset buttons (scripts/expert_pages.gd): the op applies at once, one undo step, the new part
## selected; no drag. Extrude lifts the faces BUTTON_EXTRUDE_D; Inset insets by BUTTON_INSET_F of the face's size
## (sqrt of the mean area of the selected faces). To size it differently: E (or I) then a number and Enter (E 0.3
## Enter), or E then a drag and a click or Enter (KMeshDragOp), all of them one step too.
const BUTTON_EXTRUDE_D := 0.10   # m
const BUTTON_INSET_F := 0.20


func quick(kind_: String) -> void:
	if sel.is_empty():
		m._say("Model: %s: pick a face first (click it, or B to box-select), then the button" % kind_)
		return
	var amt := BUTTON_EXTRUDE_D
	if kind_ == "inset":
		var fs: Array = sel.faces.keys()
		var mean := 0.0
		for fi in fs:
			mean += sqrt(KMeshMeasure.face_area(mesh, fi))
		amt = BUTTON_INSET_F * (mean / float(maxi(fs.size(), 1)))
	var what := "Extrude" if kind_ == "extrude" else "Inset"
	undo.begin(mesh)
	var r: Dictionary = KMeshExtrude.extrude(mesh, sel, amt) if kind_ == "extrude" else KMeshExtrude.inset(mesh, sel, amt)
	undo.commit(what)   # an op that changed nothing keeps no step
	view.mark_dirty()
	if String(r.get("error", "")) != "":
		m._say("Model: %s: %s" % [kind_, r["error"]])
	else:
		m._say("Model: %s by %s (Ctrl+Z undoes). E or I, then a number and Enter, sizes it" % [kind_, Units.len(amt)])


## D05: plain -> "uv_checker" -> "uv_stretch" -> plain. A mesh without UVs is unwrapped first (seams by angle + LSCM).
func cycle_uv_shading() -> void:
	if not mesh.has_attr(KMeshUV.UV):
		KMeshUV.seams_by_angle(mesh, 60.0)
		KMeshUV.unwrap_lscm(mesh)
	var nxt := {"": "uv_checker", "uv_checker": "uv_stretch"}
	view.shading = nxt.get(view.shading, "")
	view.rebuild()
	match view.shading:
		"uv_checker":
			m._say("Model: UV checker. Even squares = no stretch; U again shows the stretch heat map")
		"uv_stretch":
			m._say("Model: UV stretch, worst face %.2f× (blue none, red stretched). U again goes back to plain" % float(view.stretch.get("angle_max", 1.0)))
		_:
			m._say("Model: plain shading. U shows the UV checker")


## D01: the UV editor panel on / off (Shift+U)
func toggle_uv_editor() -> void:
	if uved == null:
		uved = KMeshUVEditor.new()
		uved.setup(self)
	if uved.visible:
		uved.close()
		m._say("Model: UV editor closed")
	else:
		uved.open()
		m._say("Model: UV editor (right). Mouse over it: click / box / L island, G R S move rotate scale, middle drag pans, wheel zooms. Shift+U closes")


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
	if on:
		prop.draw(_ov, m.cam, view, m.blk)   # B07: the proportional radius while a G / R / S is live
	if on and body != null:
		body.draw(_ov)
	if on and anat != null:
		anat.draw(_ov)
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
	# the keys go back to the model view: Enter (keeping a G / E value) re-pressed the focused Add and added another primitive
	# each time (MODEL walk-through 6: +64 verts per Enter)
	add.focus_mode = Control.FOCUS_NONE
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
	var nc := 0
	for f in base_f:
		nc += (f as PackedInt32Array).size()
	var ne := 0
	for e in mesh.edges():
		if e.y < o:
			ne += 1
	for k in mesh.attrs:   # A19: the base's channels kept (it is a prefix of the result), the primitive's get the default
		var r: Dictionary = mesh.attrs[k]
		var d = r["data"]
		d.resize({KMesh.AD_VERT: o, KMesh.AD_FACE: base_f.size(), KMesh.AD_CORNER: nc, KMesh.AD_EDGE: ne}[r["domain"]])
		r["data"] = d
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
		# walk-through 6, friction 5: the part rests on the floor (y = 0) when the mesh reaches up to it; a mesh wholly
		# under the floor gets the part at its lowest point
		at = Vector3(hi.x + PRIM_GAP, 0.0 if hi.y >= 0.0 else lo.y, 0.0)
	var base_v := mesh.verts.duplicate()
	var base_f := mesh.faces.duplicate()
	undo.begin(mesh)
	_append(base_v, base_f, pm, at)
	var st := undo.commit("Add " + KMeshPrims.NAMES[kind])
	live = {"kind": kind, "params": p, "step": st, "base_v": base_v, "base_f": base_f, "at": at}
	_after_topo()
	# the new part comes selected, so G / S / R move it at once (walk-through 6: a box select through x-ray caught the
	# neighbouring table verts and missed some of the cylinder's)
	var md := sel.mode
	sel.mode = KMeshSelect.VERT
	for v in range(base_v.size(), mesh.vert_count()):
		sel.verts[v] = true
	sel.set_mode(md)
	view.rebuild()
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
	undo.sel = sel
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
	legend.visible = on and showing and view != null and view.show_heat
	if not legend.visible:
		return
	var c: Dictionary = view.heat["counts"]
	for r in KMeshTopo.LEGEND:
		var lb: Label = legend.get_node("rows/%s/words" % r[0])
		lb.text = "%s: %d  (%s)" % [r[1], int(c[r[0]]), r[2]]
	legend.reset_size()
	var cl: Rect2 = m.nav_clear_rect()
	legend.position = Vector2(cl.position.x + 12.0, cl.end.y - legend.get_combined_minimum_size().y - 12.0)
