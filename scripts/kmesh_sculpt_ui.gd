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
var strength := 0.004
var falloff := KMeshSculpt.F_SMOOTH
var sym_x := true
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


func setup(main: Node) -> void:
	m = main
	_ov = Control.new()
	_ov.name = "sculpt_overlay"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.visible = false
	_ov.draw.connect(_draw_overlay)
	m.ui_root.add_child(_ov)
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
	return {"brush": b, "radius": radius, "strength": strength, "falloff": falloff, "spacing": spacing, "invert": inv, "sym_x": sym_x,
		"sym_y": sym_y, "sym_z": sym_z, "radial": radial, "radial_axis": radial_axis,
		"alpha": alpha, "stroke_method": stroke_method, "alpha_rot": alpha_rot, "alpha_angle": deg_to_rad(alpha_angle), "seed": _seed,   # C08
		"alpha_ref": _local_n((m.get("cam") as Camera3D).global_transform.basis.x) if view != null and m.get("cam") is Camera3D else Vector3.RIGHT}


func _status() -> void:
	m._say("Sculpt: %s, radius %d mm, strength %.1f mm, %s falloff, symmetry %s" % [brush, roundi(radius * 1000.0), strength * 1000.0, falloff, sym_words()])


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
	if not _stroking and filt.input(ev, self):
		return true
	if not _stroking and not filt.active and ((matcap != null and matcap.input(ev)) or (presets != null and presets.input(ev))
			or (alphas != null and alphas.input(ev))):   # C12 V, C14 B, C08 A + drag rect
		return true
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var ke := ev as InputEventKey
		var k := ke.keycode
		if ke.ctrl_pressed and k == KEY_Z:
			var lb := undo.redo() if ke.shift_pressed else undo.undo()
			view.mark_dirty()
			m._say("Sculpt: %s %s" % ["redo" if ke.shift_pressed else "undo", lb] if lb != "" else "Sculpt: nothing to %s" % ("redo" if ke.shift_pressed else "undo"))
			return true
		if _mask_key(ke) or fsets.key(self, ke):
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
