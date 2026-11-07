class_name KMeshSculptUI
extends Node
## "Sculpt: a test sphere (preview)" (ROADMAP_400 C01 + C02): the first visible step of the SCULPT page. A sphere (a cube of
## 24 x 24 quads per side pushed round, r = 0.3 m, 3 458 verts, resting on the floor beside the fighter) is added to the stage
## as a KMeshView; while it is active a left drag on it is a brush stroke (scripts/kmesh_sculpt.gd), one undo step each:
##   D draw  C clay strips  I inflate  S smooth  F flatten  P pinch  E crease  G grab  K snake hook
##   [ / ]  radius smaller / bigger     Shift+[ / ]  strength less / more     O  next falloff     X  X symmetry on / off
##   Ctrl while stroking  invert (push in)     Shift while stroking  smooth     Ctrl+Z / Ctrl+Shift+Z  undo / redo a stroke
##   C07: Y / Z  Y / Z symmetry on / off   R / Shift+R  radial copies up / down (1 = off .. 32)   Alt+R  radial axis X Y Z
##   C18: L  mesh filter on the whole mesh (L again: inflate, smooth, sharpen; scripts/kmesh_filters.gd)
##   Esc  leave (nothing is saved).  A tablet's pen pressure scales each dab (a mouse is full pressure).
##   MASK (C03, scripts/kmesh_mask.gd): M  mask brush (Ctrl or Alt while stroking erases)   Ctrl+I invert   Alt+M clear
##   Shift+B blur   Shift+M mask by cavity. Masked verts are frozen for every brush and drawn darker (KMeshMaskTint).
##   Each mask op is one undo step.
##   C12: V / Shift+V  next / previous matcap (scripts/sculpt_matcap.gd)   C14: B  brush presets panel (scripts/brush_presets_panel.gd)
##   FACE SETS (C09, scripts/kmesh_face_sets_ui.gd): W face-set brush (Ctrl+drag grows the set pressed)   H hide the set
##   under the mouse   Shift+H isolate it   Alt+H show all   Shift+W sculpt only the set under the press   Alt+] / Alt+[
##   grow / shrink it one ring   Ctrl+M mask it (Ctrl+Shift+M everything but it)   Alt+W colours on / off.
##   C08: A / Shift+A  next / previous alpha; the alpha strip (top right) picks the alpha, the stroke method (dots, drag rect,
##   spray), the rotation, or loads a PNG (scripts/sculpt_alpha_strip.gd)
## Right / middle mouse still orbit and pan the camera. The brush ring follows the mouse on the surface.

const R := 0.3
const REMESH_VOXEL := 0.015   # M1: Voxel remesh of the sphere: 1.5 cm voxels, about 7 500 quads (scripts/kmesh_voxel_remesh.gd)
const SPLIT := 24
const AT := Vector3(1.0, R, 0.0)   # on the floor, beside the fighter at the origin
const KEYS := {KEY_D: KMeshSculpt.DRAW, KEY_C: KMeshSculpt.CLAY, KEY_I: KMeshSculpt.INFLATE, KEY_S: KMeshSculpt.SMOOTH,
	KEY_F: KMeshSculpt.FLATTEN, KEY_P: KMeshSculpt.PINCH, KEY_E: KMeshSculpt.CREASE, KEY_G: KMeshSculpt.GRAB, KEY_K: KMeshSculpt.SNAKE,
	KEY_M: KMeshSculpt.MASK}

var m: Node
var on := false
var mesh: KMesh
var view: KMeshView
var undo := KMeshUndo.new()
var sculpt := KMeshSculpt.new()
var brush := KMeshSculpt.DRAW
var radius := 0.08
var strength := 0.001        # metres per dab at full pressure: 1 mm (was 4 mm: a default stroke moved the sphere 59 mm)
var readout: Label           # the brush readout on the SCULPT page: brush, strength, radius (always shown while the sphere is)
var falloff := KMeshSculpt.F_SMOOTH
var sym_x := true
var dyntopo := false        # L52 (scripts/kmesh_dyntopo.gd): edges under the brush are split / collapsed so the detail follows the stroke
var dyn_detail := 0.25      # L_max = dyn_detail * brush radius
var dyn_cb: CheckBox
var sym_y := false          # C07 (scripts/kmesh_sculpt_sym.gd)
var sym_z := false
var radial := 1
var radial_axis := 1
var filt := KMeshFilters.new()   # C18
var spacing := 0.1          # C14: dab spacing, a fraction of the radius (a preset sets it)
var matcap: SculptMatcap    # C12
var presets: BrushPresetsPanel   # C14
var alphas: SculptAlphaStrip     # C08
var alpha := ""                  # C08: the alpha stamped through ("" = none), a preset may set it
var stroke_method := SculptAlphaStroke.DOTS
var alpha_rot := SculptAlphaStroke.R_STROKE
var alpha_angle := 0.0           # deg
var _seed := 0
var _stroking := false
var _grab_plane := Plane()
var _hover := {}     # {"point" (world), "normal" (world)} under the mouse, or {}
var _mouse := Vector2.ZERO
var _ov: Control
var tint: KMeshMaskTint
var fsets := KMeshFaceSetsUI.new()   # C09
var source: Callable   # C19 (scripts/sculpt_pose_ui.gd): the mesh to sculpt, -> {"mesh", "at", "undo", "say"}; empty = the sphere
var left: Callable     # C19: called after leaving
var showing := true    # the page shows the sphere (SCULPT); off on the other pages: hidden, never stopped (set_showing)

## the page shows the sphere (SCULPT) or not: off = the sphere, its brush ring and the strokes wait, and it comes back as it was
## (kmesh_edit_ui.set_showing; a sculpt of the posed body or of the fighter's parts puts the fighter parts back on leaving)
func set_showing(v: bool) -> void:
	if showing == v:
		return
	showing = v
	if view != null and on:
		view.visible = v
	if _ov != null:
		_ov.visible = on and v
	if has_meta("fighter_vis"):
		var fv: Dictionary = get_meta("fighter_vis")
		for mi in fv:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).visible = fv[mi] if not v else false


func setup(main: Node) -> void:
	m = main
	_ov = Control.new()
	_ov.name = "sculpt_overlay"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.visible = false
	_ov.draw.connect(_draw_overlay)
	m.ui_root.add_child(_ov)
	readout = Label.new()
	readout.name = "sculpt_readout"
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.position = Vector2(16, float(m.TOP_H) + 64.0)   # below the top bar and the Matcap / Alpha rows (it was drawn under them)
	readout.z_index = 10
	_ov.add_child(readout)
	make_sliders()   # p152sculptbrus: Size and Strength sliders under the readout (end of this file)
	matcap = SculptMatcap.new()
	add_child(matcap)
	matcap.setup(self)
	presets = BrushPresetsPanel.new(self)
	m.ui_root.add_child(presets)
	alphas = SculptAlphaStrip.new()
	add_child(alphas)
	alphas.setup(self)


static func make_sphere(r := R, n := SPLIT) -> KMesh:
	var s := KMeshView.make_cube(1.0, n)
	for v in s.verts.size():
		s.verts[v] = s.verts[v].normalized() * r
	s.rebuild()
	return s


func start() -> void:
	if on:
		return
	var src: Dictionary = source.call() if source.is_valid() else {}
	mesh = src.get("mesh", null) if src.has("mesh") else make_sphere()
	KMeshMask.ensure(mesh)   # C03: made before the first undo step so every step diffs the same channel
	undo = src.get("undo", null) if src.has("undo") else KMeshUndo.new()
	view = KMeshView.new()
	view.name = "sculpt_view"
	view.show_wire = false
	view.show_verts = false
	view.smooth_shade = true
	view.set_mesh(mesh)
	m.stage_root.add_child(view)
	tint = KMeshMaskTint.new(mesh)
	view.add_child(tint)
	fsets.attach(self)
	view.position = AT
	if src.has("at"):
		view.transform = src["at"]
	on = true
	_stroking = false
	_ov.visible = true
	_update_readout()
	view.rebuild()
	if matcap != null:
		matcap.attach(view)
	if alphas != null:
		alphas.attach()
	if src.has("say"):
		m._say(String(src["say"]))
		return
	m._say("Sculpt: test sphere. Drag on it to sculpt (%s). D C I S F P E G K pick the brush, M masks, [ ] radius, X symmetry, Ctrl+Z undo, Esc leaves" % brush)


func stop() -> void:
	if not on:
		return
	on = false
	_stroking = false
	filt.active = false
	_ov.visible = false
	if matcap != null:
		matcap.detach()
		presets.close()
	if alphas != null:
		alphas.detach()
	view.queue_free()
	view = null
	if left.is_valid():
		left.call()
		return
	m._say("Sculpt: left the test sphere (nothing was saved). Run Sculpt: a test sphere (preview) to come back")


func _params(ev: InputEvent) -> Dictionary:
	var b := brush
	var inv := false
	if ev is InputEventWithModifiers:
		inv = (ev as InputEventWithModifiers).ctrl_pressed or (b == KMeshSculpt.MASK and (ev as InputEventWithModifiers).alt_pressed)
		if (ev as InputEventWithModifiers).shift_pressed:
			b = KMeshSculpt.SMOOTH
	_seed += 1
	return KMeshTopoMirror.get_shared().sculpt_params(mesh, view.global_transform if view != null else Transform3D.IDENTITY, {"brush": b, "radius": radius, "strength": strength, "falloff": falloff, "spacing": spacing, "invert": inv, "sym_x": sym_x, "dyntopo": dyntopo, "detail": dyn_detail,
		"sym_y": sym_y, "sym_z": sym_z, "radial": radial, "radial_axis": radial_axis,
		"alpha": alpha, "stroke_method": stroke_method, "alpha_rot": alpha_rot, "alpha_angle": deg_to_rad(alpha_angle), "seed": _seed,   # C08
		"alpha_ref": _local_n((m.get("cam") as Camera3D).global_transform.basis.x) if view != null and m.get("cam") is Camera3D else Vector3.RIGHT})   # B22: the edit mirror on = its partner map


func _status() -> void:
	m._say("Sculpt: %s, radius %d mm, strength %.1f mm, %s falloff, symmetry %s" % [brush, roundi(radius * 1000.0), strength * 1000.0, falloff, sym_words()])
	_update_readout()


## the readout on the page: the brush, its strength and radius, and the keys that change them
func _update_readout() -> void:
	if readout != null:
		readout.text = "%s   strength %.1f mm (Shift+[ ] )   radius %d mm ( [ ] )" % [brush, strength * 1000.0, roundi(radius * 1000.0)]
	_sync_sliders()


## "X Z, radial 6 around Y", or "off"
func sym_words() -> String:
	var w := PackedStringArray()
	for a in [[sym_x, "X"], [sym_y, "Y"], [sym_z, "Z"]]:
		if a[0]:
			w.append(a[1])
	var s := " ".join(w)
	if radial > 1:
		s += ("%sradial %d around %s" % [", " if s != "" else "", radial, "XYZ"[radial_axis]])
	return s if s != "" else "off"


## C03: Ctrl+I invert, Alt+M clear, Shift+B blur, Shift+M mask by cavity; each one undo step. true = used
func _mask_key(ke: InputEventKey) -> bool:
	var k := ke.keycode
	var op := ""
	if ke.ctrl_pressed and not ke.alt_pressed and k == KEY_I:
		op = "invert"
	elif ke.alt_pressed and not ke.ctrl_pressed and k == KEY_M:
		op = "clear"
	elif ke.shift_pressed and not ke.ctrl_pressed and not ke.alt_pressed and k == KEY_B:
		op = "blur"
	elif ke.shift_pressed and not ke.ctrl_pressed and not ke.alt_pressed and k == KEY_M:
		op = "cavity"
	if op == "":
		return false
	undo.begin(mesh)
	var said := ""
	match op:
		"invert":
			KMeshMask.invert(mesh)
			said = "inverted"
		"clear":
			KMeshMask.clear(mesh)
			said = "cleared"
		"blur":
			KMeshMask.blur(mesh)
			said = "blurred over the neighbours"
		"cavity":
			said = "set to the concave areas (%d verts)" % KMeshMask.by_cavity(mesh)
	undo.commit("mask " + op)
	m._say("Sculpt: mask %s. Masked areas are frozen; Ctrl+Z takes it back" % said)
	return true


var _pie_mouse := Vector2(-1, -1)   # the last mouse motion seen (events carry it; the OS cursor can differ under a pushed event)


## P04: a ring of the brushes around the mouse; releasing the mouse on a wedge picks it (scripts/ring_menu.gd, release_pick)
func _open_pie() -> void:
	var its: Array = []
	for kc in KEYS:
		var b: String = KEYS[kc]
		its.append({"name": b, "run": func():
			brush = b
			_status()})
	m.ui_pie.open(_pie_mouse if _pie_mouse.x >= 0.0 else m.get_viewport().get_pie_mouse_position(), "Brush", its)


## the surface under the screen point: {"point", "normal"} in world space, or {}
func surface_at(cam: Camera3D, p: Vector2) -> Dictionary:
	var hit := view.ray_face(cam.project_ray_origin(p), cam.project_ray_normal(p))
	if hit.is_empty():
		return {}
	var nl: Vector3 = mesh.face_normals[int(hit["face"])]
	return {"point": hit["point"], "normal": (view.global_transform.basis * nl).normalized(), "face": int(hit["face"])}


func _local(wp: Vector3) -> Vector3:
	return view.global_transform.affine_inverse() * wp


func _local_n(wn: Vector3) -> Vector3:
	return (view.global_transform.basis.inverse() * wn).normalized()


## main passes every unhandled input here while `on`; true = used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventMouseMotion:
		_pie_mouse = (ev as InputEventMouseMotion).position   # P04: where the pie opens
	if not _stroking and filt.input(ev, self):
		return true
	if not _stroking and not filt.active and ((matcap != null and matcap.input(ev)) or (presets != null and presets.input(ev))
			or (alphas != null and alphas.input(ev))):   # C12 V, C14 B, C08 A + drag rect
		return true
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var ke := ev as InputEventKey
		var k := ke.keycode
		if ke.ctrl_pressed and k == KEY_Z:
			m._redo() if ke.shift_pressed else m._undo()   # P12: through Main, the newest step of ALL pages (Main._pu_route)
			return true
		if _mask_key(ke) or fsets.key(self, ke):
			return true
		if k == KEY_Q and not ke.ctrl_pressed and not ke.alt_pressed and not ke.shift_pressed and m.pie_on and m.ui_pie != null:
			_open_pie()   # P04: the brush pie (option, off by default)
			return true
		if KEYS.has(k) and not ke.ctrl_pressed:
			brush = KEYS[k]
			_status()
			return true
		match k:
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				var f := 1.15 if k == KEY_BRACKETRIGHT else 1.0 / 1.15
				if ke.shift_pressed:
					strength = clampf(strength * f, 0.0002, 0.05)
				else:
					radius = clampf(radius * f, 0.01, 0.5)
				_status()
				_ov.queue_redraw()
			KEY_O:
				falloff = KMeshSculpt.FALLOFFS[(KMeshSculpt.FALLOFFS.find(falloff) + 1) % KMeshSculpt.FALLOFFS.size()]
				_status()
			KEY_X:
				sym_x = not sym_x
				_status()
			KEY_Y:
				sym_y = not sym_y
				_status()
			KEY_Z:
				sym_z = not sym_z
				_status()
			KEY_R:
				if ke.alt_pressed:
					radial_axis = (radial_axis + 1) % 3
				else:
					radial = clampi(radial + (-1 if ke.shift_pressed else 1), 1, KMeshSculptSym.MAX_RADIAL)
				_status()
			KEY_ESCAPE:
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
			var s := surface_at(cam, mb.position)
			if s.is_empty():
				return false   # a press off the sphere is not a stroke
			undo.begin(mesh)
			sculpt.begin(mesh, fsets.params(self, _params(mb), s))
			_grab_plane = Plane(cam.global_transform.basis.z, s["point"])   # grab: the drag slides on a screen-facing plane
			sculpt.to(_local(s["point"]), _local_n(s["normal"]), 1.0)
			_stroking = true
			view.mark_dirty()
			return true
		if not _stroking:
			return false
		_stroking = false
		sculpt.end()
		var st := undo.commit("sculpt " + String(sculpt.p["brush"]))
		if not st.is_empty():
			m._say("Sculpt: one %s stroke, one undo step (Ctrl+Z takes it back)" % sculpt.p["brush"])
		return true
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_mouse = mm.position
		_hover = surface_at(cam, mm.position)
		_ov.queue_redraw()
		if not _stroking:
			return false
		var pr := KMeshSculpt.pressure_of(mm)
		if sculpt.p["brush"] == KMeshSculpt.GRAB or sculpt.p["brush"] == KMeshSculpt.SNAKE:
			var wp = _grab_plane.intersects_ray(cam.project_ray_origin(mm.position), cam.project_ray_normal(mm.position))
			if wp != null:
				sculpt.to(_local(wp), _local_n(cam.global_transform.basis.z), pr)
				if sculpt.p["brush"] == KMeshSculpt.SNAKE:
					_grab_plane = Plane(cam.global_transform.basis.z, wp)
		elif not _hover.is_empty():
			sculpt.to(_local(_hover["point"]), _local_n(_hover["normal"]), pr)
		view.mark_dirty()
		return true
	return false


func _draw_overlay() -> void:
	if not on or _hover.is_empty() or view == null:
		return
	var cam: Camera3D = m.cam
	var c: Vector3 = _hover["point"]
	if cam.is_position_behind(c):
		return
	var sc := cam.unproject_position(c)
	var rp := cam.unproject_position(c + cam.global_transform.basis.x * radius * view.global_transform.basis.get_scale().x)
	_ov.draw_arc(sc, sc.distance_to(rp), 0.0, TAU, 48, Tok.c("pick_hover"), 1.5, true)


## M1: Voxel remesh of the sphere (ribbon SPHERE group, scripts/kmesh_voxel_remesh.gd): the sphere becomes an even mesh at
## REMESH_VOXEL; one undo step (Ctrl+Z takes it back). The sphere keeps its place and its view; its mask channel starts again.
func remesh() -> void:
	if not on or view == null:
		return
	var r := KMeshVoxelRemesh.apply(mesh, REMESH_VOXEL, undo)
	if not r["ok"]:
		m._say("Remesh: " + String(r["why"]))
		return
	view.set_mesh(mesh)
	view.rebuild()
	tint.refresh(true)
	m._say("Remesh: the sphere is an even mesh of %d quads (1.5 cm). Ctrl+Z takes it back" % mesh.faces.size())


## Ctrl+Z / Ctrl+Shift+Z, and the top bar's Undo / Redo buttons while the sphere shows (walk13: they only knew pose undo)
func undo_redo(back: bool) -> void:
	var lb := undo.undo() if back else undo.redo()
	view.mark_dirty()
	m._say("Sculpt: %s %s" % ["undo" if back else "redo", lb] if lb != "" else "Sculpt: nothing to %s" % ("undo" if back else "redo"))


## p152sculptbrus: two sliders under the readout, in plain words: Size (the brush's radius, 10 to 300 mm) and Strength (what one
## dab moves a vert, 0.2 to 50 mm). They set the same radius and strength as [ ] and Shift+[ ]; a slider is no undo step (the
## strokes are the undo steps). The word beside each says what it feels like: small / medium / big, soft / firm / hard.
var size_sl: HSlider
var strength_sl: HSlider
var size_lbl: Label
var strength_lbl: Label


func make_sliders() -> void:
	var box := VBoxContainer.new()
	box.name = "sculpt_sliders"
	box.position = Vector2(16, float(m.TOP_H) + 92.0)   # under the readout line (its y is TOP_H + 64)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_index = 10
	_ov.add_child(box)
	size_lbl = Label.new()
	size_lbl.name = "sculpt_size_label"
	size_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(size_lbl)
	size_sl = _slider("sculpt_size", 10.0, 300.0, 1.0, _on_size)
	box.add_child(size_sl)
	strength_lbl = Label.new()
	strength_lbl.name = "sculpt_strength_label"
	strength_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(strength_lbl)
	strength_sl = _slider("sculpt_strength", 0.2, 50.0, 0.1, _on_strength)
	box.add_child(strength_sl)
	_make_remesh_slider(box)   # plan 154
	dyn_cb = CheckBox.new()   # L52
	dyn_cb.name = "sculpt_dyntopo"
	dyn_cb.text = "Dynamic detail"
	dyn_cb.tooltip_text = "Dynamic detail: under the brush, long edges are split and tiny ones merged, so the mesh gets finer where you sculpt. One undo step per stroke."
	dyn_cb.focus_mode = Control.FOCUS_NONE
	dyn_cb.toggled.connect(_on_dyntopo)
	box.add_child(dyn_cb)
	var pie_cb := CheckBox.new()   # P04
	pie_cb.name = "sculpt_pie"
	pie_cb.text = "Brush pie menu (Q)"
	pie_cb.tooltip_text = "Q opens a ring of the brushes around the mouse; release the mouse on one to pick it. Off by default."
	pie_cb.focus_mode = Control.FOCUS_NONE
	pie_cb.button_pressed = m.pie_on
	pie_cb.toggled.connect(func(v: bool): m.pie_on = v)
	box.add_child(pie_cb)
	_sync_sliders()


func _slider(nm: String, lo: float, hi: float, step: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.name = nm
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(240, 20)
	s.focus_mode = Control.FOCUS_NONE   # the keys stay the brush's keys (a focused slider would take the arrows)
	s.value_changed.connect(cb)
	return s


func _on_dyntopo(on_: bool) -> void:
	dyntopo = on_
	m._say("Sculpt: dynamic detail %s (edges longer than %d %% of the brush radius are split under the brush)" % ["on" if on_ else "off", roundi(dyn_detail * 100.0)])


func _on_size(v: float) -> void:
	radius = v / 1000.0
	_status()
	_ov.queue_redraw()


func _on_strength(v: float) -> void:
	strength = v / 1000.0
	_status()


## the sliders show the brush's current radius and strength (the keys [ ] move them too); the words say what it feels like
func _sync_sliders() -> void:
	if size_sl == null:
		return
	var r_mm := radius * 1000.0
	var s_mm := strength * 1000.0
	size_sl.set_value_no_signal(r_mm)
	strength_sl.set_value_no_signal(s_mm)
	size_lbl.text = "Size  %d mm  (%s)" % [roundi(r_mm), "small" if r_mm < 40.0 else ("medium" if r_mm < 120.0 else "big")]
	strength_lbl.text = "Strength  %.1f mm  (%s)" % [s_mm, "soft" if s_mm < 2.0 else ("firm" if s_mm < 20.0 else "hard")]


## ---- plan 154: Remesh slider (lighter <-> smoother). The slider's value is a number of doublings of the triangle count: -2 = a quarter,
## -1 = half (lighter), 0 = as now, +1 = double (smoother), +2 = four times. Letting go of the handle rebuilds the sphere as an even
## voxel mesh (scripts/kmesh_voxel_remesh.gd) with about that many triangles; one undo step. The slider goes back to 0, so the next
## move is again relative to what the sphere is now.
var remesh_sl: HSlider
var remesh_lbl: Label
var _remesh_busy := false


func _make_remesh_slider(box: VBoxContainer) -> void:
	remesh_lbl = Label.new()
	remesh_lbl.name = "sculpt_remesh_label"
	remesh_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(remesh_lbl)
	remesh_sl = _slider("sculpt_remesh", -2.0, 2.0, 0.5, _on_remesh_value)
	remesh_sl.tooltip_text = "Remesh: drag left for a lighter mesh (fewer, evenly sized triangles), right for a smoother one (more). Let go to rebuild; Ctrl+Z takes it back."
	remesh_sl.drag_ended.connect(_on_remesh_released)
	box.add_child(remesh_sl)
	_on_remesh_value(0.0)


func _on_remesh_value(v: float) -> void:
	if remesh_lbl == null:
		return
	if v == 0.0 or mesh == null:
		remesh_lbl.text = "Remesh: lighter <-> smoother"
	else:
		remesh_lbl.text = "Remesh: %s, about %d triangles" % ["lighter" if v < 0.0 else "smoother", int(round(mesh.triangle_count() * pow(2.0, v)))]


func _on_remesh_released(changed: bool) -> void:
	if not changed or remesh_sl == null or _remesh_busy:
		return
	var v := remesh_sl.value
	remesh_sl.set_value_no_signal(0.0)
	_on_remesh_value(0.0)
	if v != 0.0:
		remesh_by(v)


## rebuild the sculpt mesh with about triangles * 2^doublings triangles, evenly sized. One undo step. Returns the result of the apply.
func remesh_by(doublings: float) -> Dictionary:
	if not on or view == null or mesh == null:
		return {"ok": false, "why": "no sculpt mesh"}
	_remesh_busy = true
	var target := maxf(float(mesh.triangle_count()) * pow(2.0, doublings), 12.0)
	var area := 0.0
	for f in mesh.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size() - 1):
			area += (mesh.verts[fa[k]] - mesh.verts[fa[0]]).cross(mesh.verts[fa[k + 1]] - mesh.verts[fa[0]]).length() * 0.5
	var h := sqrt(3.0 * area / target)   # a surface-net mesh has about 3 A / h^2 triangles (1.5 quads per cell face area)
	for _i in 2:   # one correction from the measured count
		var t := KMeshVoxelRemesh.remesh(mesh, h)
		if not t["ok"]:
			break
		var got := float((t["mesh"] as KMesh).triangle_count())
		if absf(got / target - 1.0) < 0.03:
			break
		h *= sqrt(got / target)
	var tris0 := mesh.triangle_count()
	var r := KMeshVoxelRemesh.apply(mesh, h, undo)
	_remesh_busy = false
	if not r["ok"]:
		m._say("Remesh: " + String(r["why"]))
		return r
	view.set_mesh(mesh)
	view.rebuild()
	tint.refresh(true)
	m._say("Remesh: %s, %d -> %d triangles, evenly sized. Ctrl+Z takes it back" % ["lighter" if mesh.triangle_count() < tris0 else "smoother", tris0, mesh.triangle_count()])
	return r
