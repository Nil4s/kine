class_name BlKeys
extends RefCounted
## BLENDER-STYLE MODAL KEYS, AS A LAYER (ROADMAP_400 B16). Off by default: Kine's own keys stay (the command
## "Keys: Blender-style G R S on / off" turns it on; remembered in the settings file, [look] blkeys).
## What Kine's own keys are (main.gd, plain press, nothing held): G = second hand on the weapon, R = reset the part,
## S = the command search box, Y = the speed graph tool, X and Z = nothing (Ctrl+Z / Ctrl+Y are undo / redo). With the
## layer OFF this file does nothing on the posing pages, so each of them does what it did there (the model preview is
## the exception, see GRS below). With it ON:
##   G  grab: the picked hand / foot (its IK target) or the hips (the root) follows the mouse; X / Y / Z = along the
##      world axis; a typed number = metres.   R  rotate the picked part: X / Y / Z = its local bend / side / twist
##      (X until you pick), a typed number = degrees.   S  scale where it means something: the weapon's length (a typed
##      number = the factor); a joint has no scale, so it says so.
##   In the model preview (kmesh_edit_ui.gd) the same three act on the selected vertices: X / Y / Z = the mesh axis,
##   a typed number = metres / degrees / factor. One KMeshUndo step per confirmed edit.
##   Enter or left click = keep (ONE undo step); Esc or right click = cancel, the old state put back exactly.
## The live readout is the status line ("R  X  45°"). Behaviour learned from Blender's manual; no Blender code.
## B07: with proportional editing on (O in the model preview, kmesh_proportional.gd) the unselected verts within its
## radius follow, weighted by the falloff; the wheel sizes the radius while a mesh G / R / S is live.
## B22: with the edit mirror on (scripts/kmesh_topomirror.gd) each moved vert's partner moves mirrored, in the same step.
## GRS (round 2 of the model walk): in the model preview (kmesh_edit_ui.gd) G / R / S work WITHOUT the layer, whenever
## the mesh edit is on and showing: the layer then only adds the body-page keys. Posing pages keep their own G (second
## hand), R (reset) and S (search): with the mesh edit off or on another page this file does nothing with the layer off.
## Tests: tests/blkeys_test.gd, tests/kmesh_grs_test.gd.

const CFG := "look"
const DEG_PER_PX := 0.5
const SCALE_PER_PX := 0.005

var m                     # the poser (main.gd)
var on := false           # the layer
var active := ""          # "", "G", "R", "S"
var where := ""           # "pose", "weapon", "mesh"
var axis := -1            # -1 none yet, 0 X, 1 Y, 2 Z
var text := ""            # the typed number
var acc := Vector2.ZERO   # mouse travel since the start
var _start := {}          # pose: B.state()
var _part := ""
var _keep := {}
var _verts := PackedVector3Array()   # mesh: the vertices at the start
var _idx := PackedInt32Array()
var _centre := Vector3.ZERO
var _p0 := Vector3.ZERO
var _pc := {}              # B14: individual origins, vertex -> its island's centre (KMeshPivot.origins)
var last_readout := ""
var _mpp_at := 0.0         # mesh: metres per screen pixel at the selection's depth (set in _begin_mesh; 0 = the camera's distance)
var _floor_pivot := false  # walk-through 6, friction 6: S about the floor point under the middle (the selection reaches the floor)
var _z_said := false       # walk-through 6, friction 7: "Z is depth here; Y is up" is said once per session


func _init(main) -> void:
	m = main


func load_from(path: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		on = bool(cf.get_value(CFG, "blkeys", false))


func set_on(v: bool, save := true) -> void:
	if active != "":
		cancel()
	on = v
	if save:
		var cf := ConfigFile.new()
		cf.load(m.settings)
		cf.set_value(CFG, "blkeys", on)
		cf.save(m.settings)
	m._say_plain("Keys: Blender-style on. G grabs, R rotates (then X / Y / Z, or type degrees), S scales; Enter keeps, Esc cancels. The command again turns it off" if on \
		else "Keys: Kine's own again (G second hand, R reset the part, S search)")


func toggle() -> void:
	set_on(not on)


static func axis_name(a: int) -> String:
	return ["X", "Y", "Z"][a] if a >= 0 and a <= 2 else ""


## the number typed so far, or NAN
func typed() -> float:
	return text.to_float() if text.is_valid_float() else NAN


## main passes every unhandled input here first; true = used
func input(ev: InputEvent) -> bool:
	if active != "":
		if not on and where != "mesh":
			return false
		return _modal(ev)
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return false
	var k := ev as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or k.shift_pressed or k.meta_pressed:
		if on and k.ctrl_pressed and not k.shift_pressed and k.keycode == KEY_Z and _mesh_on() and m.kmed.undo.steps.size() > 0:   # layer on only: the GRS undo steps
			m._undo()   # L126: through the one ordered log (it used to take the mesh list first, whatever was newest)
			return true
		return false
	if not (k.keycode in [KEY_G, KEY_R, KEY_S]):
		return false
	if not on and not _mesh_on():   # GRS: the model preview has G / R / S with the layer off too; posing does not
		return false
	var fo: Control = m.get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is SpinBox:
		return false
	_begin({KEY_G: "G", KEY_R: "R", KEY_S: "S"}[k.keycode])
	return true


func _mesh_on() -> bool:
	return m.kmed != null and m.kmed.on and m.kmed.showing


func _begin(which: String) -> void:
	if _mesh_on():
		_begin_mesh(which)
		return
	var sel: String = m.sel
	if sel == "" or not (sel in m.B.ang or sel in Body.WEAPON):
		m._say("Blender keys: pick a part first (click it), then %s" % which)
		return
	var weapon := sel in Body.WEAPON
	if which == "S":
		if not weapon:
			m._say("S scales only the weapon's length and model points: a joint has no size of its own. Body size is in Proportions (search it with S off, or the command box)")
			return
	elif weapon:
		m._say("%s turns and moves body parts: pick a hand, a foot or a joint first (the bat is moved by dragging it)" % which)
		return
	if which == "G" and not (sel in ["hand_r", "hand_l", "foot_r", "foot_l", "pelvis"]):
		m._say("G grabs a hand, a foot or the hips (their IK target / root): pick one first, or R to turn this joint")
		return
	where = "weapon" if weapon else "pose"
	_part = sel
	_start = m.B.state()
	_keep = m._lock_snap()
	_p0 = m.B.P[sel] if m.B.P.has(sel) else Vector3.ZERO
	active = which
	axis = 0 if which == "R" else -1
	text = ""
	acc = Vector2.ZERO
	m._step_hint = {"G": "Grab (G)", "R": "Rotate (R)", "S": "Scale (S)"}[which]
	m._push_undo()
	_readout()


func _begin_mesh(which: String) -> void:
	var ui = m.kmed
	var s: KMeshSelect = ui.sel
	var vs := {}
	match s.mode:
		KMeshSelect.VERT:
			vs = s.verts
		KMeshSelect.EDGE:
			for e in s.edges:
				vs[e.x] = true
				vs[e.y] = true
		_:
			for fi in s.faces:
				for v in (ui.mesh.faces[fi] as PackedInt32Array):
					vs[v] = true
	if vs.is_empty():
		m._say("Model: pick vertices first (click one, or B and drag a box), then %s" % which)
		return
	_idx = PackedInt32Array(vs.keys())
	_verts = ui.mesh.verts.duplicate()
	_centre = Vector3.ZERO
	for i in _idx:
		_centre += _verts[i]
	_centre /= float(_idx.size())
	_centre = ui.pivot.centre(_idx, _verts, _centre)   # B14: the pivot mode (median / active / cursor)
	# walk-through 6, friction 6: a box squashed about its middle floats; when the selection reaches the floor (its lowest
	# vertex is on it), S scales about the floor point under the middle. The pivot "." picks stays in charge otherwise
	_floor_pivot = false
	var low := INF
	for i in _idx:
		low = minf(low, _verts[i].y)
	if which == "S" and ui.pivot.mode == "median" and absf(low) < 1e-3:
		_centre.y = 0.0
		_floor_pivot = true
	_pc = ui.pivot.origins(_idx, _verts)
	# the mouse moves the selection as far as it moves on screen at the selection's own depth (walk13 goal 2: a 90 px drag
	# moved the chest 406 mm, because the scale came from the camera's distance, not the chest's)
	var wc: Vector3 = ui.view.global_transform * _centre
	var zc := maxf(-(m.cam.global_transform.affine_inverse() * wc).z, 0.01)
	_mpp_at = zc * 2.0 * tan(deg_to_rad(m.cam.fov * 0.5)) / m.get_viewport().get_visible_rect().size.y
	if ui.prop.on:
		ui.prop.begin(ui.mesh, _idx, _verts)
	where = "mesh"
	active = which
	axis = 0 if which == "R" else -1
	text = ""
	acc = Vector2.ZERO
	ui.undo.begin(ui.mesh)
	KMeshTopoMirror.get_shared().prepare(ui.mesh, ui.view.global_transform, _idx)   # B22: the partner map (cached)
	_readout()


func _modal(ev: InputEvent) -> bool:
	if where == "mesh" and m.kmed.snap.watch(ev):   # B08: Ctrl pressed / let go: the snap comes or goes at once
		_apply()
		return true
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if not mb.pressed:
			return false
		if mb.button_index == MOUSE_BUTTON_LEFT:
			confirm()
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			return true
		if where == "mesh" and m.kmed.prop.on and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			m.kmed.prop.wheel(mb.button_index == MOUSE_BUTTON_WHEEL_UP)   # B07: the proportional radius
			_apply()
			return true
		return false   # the wheel still zooms
	if ev is InputEventMouseMotion:
		if text == "":
			acc += (ev as InputEventMouseMotion).relative
			_apply()
		return true
	if not (ev is InputEventKey):
		return false
	var k := ev as InputEventKey
	if not k.pressed:
		return true
	if k.echo and k.keycode != KEY_BACKSPACE:
		return true
	match k.keycode:
		KEY_ESCAPE:
			cancel()
		KEY_ENTER, KEY_KP_ENTER:
			confirm()
		KEY_X:
			axis = 0
			_apply()
		KEY_Y:
			axis = 1
			_apply()
		KEY_Z:
			axis = 2
			_apply()
		KEY_BACKSPACE:
			text = text.left(-1)
			_apply()
		KEY_MINUS, KEY_KP_SUBTRACT:
			text = text.substr(1) if text.begins_with("-") else "-" + text
			_apply()
		KEY_PERIOD, KEY_KP_PERIOD:
			if not "." in text:
				text += "."
			_apply()
		_:
			if k.keycode >= KEY_0 and k.keycode <= KEY_9:
				text += str(k.keycode - KEY_0)
				_apply()
			elif k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
				text += str(k.keycode - KEY_KP_0)
				_apply()
	return true   # every other key waits: nothing runs half-way through a rotate


## the amount now: the typed number, else the mouse
func value() -> float:
	var t := typed()
	if not is_nan(t):
		return t
	if text != "" and not text.is_valid_float():
		return 0.0   # "-" or "." alone
	match active:
		"R":
			return acc.x * DEG_PER_PX
		"S":
			return 1.0 + acc.x * SCALE_PER_PX
		_:
			return _mouse_move(axis if axis >= 0 else 0)


func _mpp() -> float:
	if where == "mesh" and _mpp_at > 0.0:
		return _mpp_at
	return 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / m.get_viewport().get_visible_rect().size.y


## the mouse travel in the view plane, along one world axis (a)
func _mouse_move(a: int) -> float:
	var dw: Vector3 = m.cam.global_basis.x * acc.x * _mpp() - m.cam.global_basis.y * acc.y * _mpp()
	return dw[a]


## the grab, as a world offset
func _grab_delta() -> Vector3:
	var t := typed()
	if axis >= 0:
		var d := Vector3.ZERO
		d[axis] = t if not is_nan(t) else _mouse_move(axis)
		return d
	if not is_nan(t):
		return (m.cam.global_basis.x as Vector3) * t
	return m.cam.global_basis.x * acc.x * _mpp() - m.cam.global_basis.y * acc.y * _mpp()


func _apply() -> void:
	if where == "mesh":
		_apply_mesh()
	elif where == "weapon":
		var f := value()
		m.B.set_weapon_len(float(_start["wep_len"]) * f)
		m.B.fk()
		m._refresh()
	elif active == "R":
		var v: Vector3 = _start["ang"][_part]
		v[maxi(axis, 0)] += value()
		m.B.set_state(_start)
		m.B.set_ang_safe(_part, v)
		m._lock_keep(_keep)
		m._refresh()
	else:   # G on a hand / foot / the hips
		m.B.set_state(_start)
		var d := _grab_delta()
		if _part == "pelvis":
			m.B.offset = (_start["offset"] as Vector3) + d
			m.B.fk()
		else:
			m.B.reach(_part, _p0 + d)
		m._lock_keep(_keep)
		m._refresh()
	_readout()


func _apply_mesh() -> void:
	var ui = m.kmed
	var mesh: KMesh = ui.mesh
	var v := value()
	if text == "":
		v = ui.snap.step(active, v)   # B08: Ctrl snaps R to 5 degrees, S to 0.1
	var d := Vector3.ZERO
	var basis := Basis.IDENTITY
	var sc := Vector3.ONE
	var ax := Vector3.ZERO
	match active:
		"G":
			d = _grab_delta()
			if text == "":
				d = ui.snap.grab(_idx, _verts, d, axis)   # B08: Ctrl snaps onto the target (Shift+Tab picks it)
		"R":
			ax[maxi(axis, 0)] = 1.0
			basis = Basis(ax, deg_to_rad(v))
		"S":
			if axis >= 0:
				sc[axis] = v
			else:
				sc = Vector3(v, v, v)
	for i in _idx:
		var p := _verts[i]
		match active:
			"G":
				mesh.verts[i] = p + d
			"R":
				mesh.verts[i] = _centre + basis * (p - _centre)
			"S":
				mesh.verts[i] = _centre + (p - _centre) * sc
	ui.pivot.apply_individual(_pc, _verts, active, basis, sc)   # B14: individual origins
	if ui.prop.on:
		ui.prop.apply(mesh, active, d, ax, deg_to_rad(v), sc, _centre)   # B07
	KMeshTopoMirror.get_shared().follow(mesh, _verts)   # B22: the partners move mirrored (same undo step)
	mesh._compute_normals()
	ui.view.mark_dirty()


## "R  X  45°" in the status line
func readout() -> String:
	var v := value()
	var ax := axis_name(axis)
	if axis == 2:   # Kine is Y-up: Z is depth, so a Blender user's "Z = up" is said once, here
		ax = "Z (depth; up is Y here)"
	var amount := ""
	var t := typed()
	match active:
		"R":
			amount = (text if not is_nan(t) else String.num(v, 1)) + "°"
		"S":
			amount = "x " + (text if not is_nan(t) else String.num(v, 3))
		_:
			amount = (text if not is_nan(t) else String.num(v, 3)) + " m"
	var s := "%s  %s  %s" % [active, ax, amount] if ax != "" else "%s  %s" % [active, amount]
	return s


func _readout() -> void:
	# walk-through 6, friction 7: a Blender user types G Z for up; the mesh preview says what the axes are, at the start
	var legend := "     X sideways, Y up, Z depth" if where == "mesh" else ""
	var pivot := "     Scale about the floor point under the middle (. changes the pivot)" if where == "mesh" and _floor_pivot and active == "S" else ""
	var z_note := ""
	if where == "mesh" and axis == 2 and not _z_said:
		_z_said = true   # said once: the first time Z picks the axis
		z_note = "     Z is depth here; Y is up"
	last_readout = readout() + legend + pivot + z_note + "     Enter keeps, Esc cancels, X Y Z pick the axis, type a number"
	m._say_plain(last_readout)


func confirm() -> void:
	var which := active
	active = ""
	if where == "mesh":
		var ui = m.kmed
		var st: Dictionary = ui.undo.commit({"G": "Move", "R": "Rotate", "S": "Scale"}[which] + " vertices")
		ui.view.mark_dirty()
		m._say("Model: %s kept (%d vertices%s)" % [{"G": "move", "R": "rotate", "S": "scale"}[which], _idx.size(), ", one undo step" if not st.is_empty() else ": nothing changed"])
		return
	var changed: bool = m.B.state() != _start
	if not changed:
		m._drop_undo()
		m._refresh()
		m._say("%s: nothing changed (type a number or move the mouse first)" % which)
		return
	m._after_edit()
	m._autokey_card()
	m._journal_write()
	m._say("%s kept on the %s" % [{"G": "Grab", "R": "Rotate", "S": "Scale"}[which], m.nice(_part)])


func cancel() -> void:
	var which := active
	active = ""
	if where == "mesh":
		var ui = m.kmed
		ui.mesh.verts = _verts.duplicate()
		ui.mesh._compute_normals()
		ui.undo.commit("cancelled")   # nothing differs from the start now: no step is kept
		ui.view.mark_dirty()
		m._say("Model: %s cancelled, the vertices are back as they were" % {"G": "move", "R": "rotate", "S": "scale"}[which])
		return
	m.B.set_state(_start)
	m._drop_undo()
	m._refresh()
	m._say("%s cancelled: the %s is back as it was" % [which, m.nice(_part)])
