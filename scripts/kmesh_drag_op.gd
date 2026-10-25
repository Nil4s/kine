class_name KMeshDragOp
extends RefCounted
## E (extrude) and I (inset) as a live drag, the way Blender does it (walk-through 05_04 / 06_05; the ops are
## scripts/kmesh_extrude.gd). E or I starts at once: the first preview is the op at amount 0, already one undo step.
## The mouse sets the amount: extrude = the distance along the selection's normal from where the mouse was when E was
## pressed (the closest point of the mouse ray to that normal line); inset = how much farther the mouse is from the face
## centre, in the face plane, than it was at the start. Every motion rebuilds the preview in place (the step is replaced,
## never doubled). The left mouse button's release confirms (a click or a drag-and-let-go; the press does nothing), Enter
## confirms too (the step stays: one undo step); right click or Esc cancels: the step is taken back and the selection
## and the redo list are as they were (no step). The ribbon's Extrude / Inset buttons do not start a drag (KMeshEditUI.quick). Typed numbers set the amount exactly
## (metres: E 0.3 Enter); Backspace takes a character back. While the drag runs KMeshEditUI.input sends every key and
## mouse button here first. The state lives on the UI as meta "kdrag".

const KEY := "kdrag"
const INSET_MIN := 0.001       # m: an inset of nothing would leave degenerate faces

var ui                         # KMeshEditUI
var kind := ""                 # "extrude" | "inset"
var each := false              # Shift: each face on its own
var sel0 := {}                 # the selection before the drag: {mode, verts, edges, faces}
var live := {}                 # the undo step of the current preview ({} = none)
var redos0: Array = []         # the redo list before the drag (a cancel puts it back)
var amount := 0.0              # m, what the preview shows
var s0 := 0.0                  # the measure at the start (see _measure)
var origin := Vector3.ZERO     # world: a point on the extrude line / the inset centre
var axis := Vector3.ZERO       # world unit: the normal (extrude's line, inset's plane)
var typed := ""
var err := ""
var vertical := false         # extrude along a normal that points at the camera: the mouse's up / down moves it (chosen at the start)


static func active(u) -> KMeshDragOp:
	return u.get_meta(KEY) if u.has_meta(KEY) else null


## E / I: start the drag (true = handled). Nothing selected: the old path reports it.
static func start(u, kind_: String, each_: bool) -> bool:
	if u.sel.is_empty():
		return false
	var d := KMeshDragOp.new()
	d.ui = u
	d.kind = kind_
	d.each = each_
	d.sel0 = {"mode": u.sel.mode, "verts": u.sel.verts.duplicate(), "edges": u.sel.edges.duplicate(), "faces": u.sel.faces.duplicate()}
	d.redos0 = u.undo.redos.duplicate()
	d._geometry()
	u.set_meta(KEY, d)
	var mouse: Vector2 = u.get_meta("kmouse", Vector2.ZERO)
	d.vertical = kind_ == "extrude" and d._line_on_view(mouse)
	d.s0 = d._measure(mouse)
	if is_nan(d.s0):
		d.s0 = 0.0
	d._preview(0.0)
	if d.err != "":
		u.remove_meta(KEY)
		u.m._say("Model: %s: %s" % [kind_, d.err])
		return true
	d._say()
	return true


## KMeshEditUI.input calls this first; true = used
static func handle(u, ev: InputEvent) -> bool:
	if ev is InputEventMouse:
		u.set_meta("kmouse", (ev as InputEventMouse).position)
	var d := active(u)
	if d == null:
		return false
	if ev is InputEventMouseMotion:
		d.move((ev as InputEventMouseMotion).position)
		return true
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if not mb.pressed:
				d.confirm()   # the release confirms: no second click needed
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			d.cancel()
			return true
		return false   # the other buttons: the camera's
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed or k.echo:
			return true
		var kc := k.keycode & KEY_CODE_MASK
		match kc:
			KEY_ESCAPE:
				d.cancel()
			KEY_ENTER, KEY_KP_ENTER:
				if d.typed != "":
					d.set_typed()
				d.confirm()
			KEY_BACKSPACE:
				if d.typed != "":
					d.typed = d.typed.left(d.typed.length() - 1)
					d.set_typed()
			KEY_PERIOD, KEY_KP_PERIOD:
				if not d.typed.contains("."):
					d.typed += "."
					d.set_typed()
			KEY_MINUS, KEY_KP_SUBTRACT:
				if d.typed == "":
					d.typed = "-"
					d.set_typed()
			_:
				if (kc >= KEY_0 and kc <= KEY_9) or (kc >= KEY_KP_0 and kc <= KEY_KP_9):
					d.typed += str(kc - KEY_0 if kc <= KEY_9 else kc - KEY_KP_0)
					d.set_typed()
		return true
	return false


# ---------------------------------------------------------------- the drag

## the normal (extrude's line, inset's plane) and the centre, in world space, from the selection before the drag
func _geometry() -> void:
	var m: KMesh = ui.mesh
	var vs := {}
	var n := Vector3.ZERO
	if sel0["mode"] == KMeshSelect.FACE:
		for fi in sel0["faces"].keys():
			n += m._newell(fi)
			for v in (m.faces[fi] as PackedInt32Array):
				vs[v] = true
	else:
		if sel0["mode"] == KMeshSelect.EDGE:
			for e in sel0["edges"].keys():
				vs[e.x] = true
				vs[e.y] = true
		else:
			for v in sel0["verts"].keys():
				vs[v] = true
		for v in vs:
			n += m.vert_normals[v]
	var c := Vector3.ZERO
	for v in vs:
		c += ui.view._to_world(v)
	origin = c / float(maxi(vs.size(), 1))
	var nl := n.normalized() if n.length() > 1e-9 else Vector3.UP
	axis = (ui.view.global_transform.basis * nl).normalized()


## where the mouse is, as a number that grows with the amount: extrude = the position along the normal line (the
## closest point of the mouse ray to it); inset = the distance from the centre within the face plane. NAN when the
## ray cannot tell (parallel to the line or the plane).
func _measure(p: Vector2) -> float:
	var r: Array = ui.view.ray_at(ui.m.cam, p)
	var o: Vector3 = r[0]
	var d: Vector3 = (r[1] as Vector3).normalized()
	if kind == "extrude":
		if vertical:
			return -p.y * _m_per_px()
		var b := axis.dot(d)
		var den := 1.0 - b * b
		if den < 1e-4:
			return NAN
		var w := origin - o
		return (b * d.dot(w) - axis.dot(w)) / den
	var den2 := axis.dot(d)
	if absf(den2) < 1e-4:
		return NAN
	var t := axis.dot(origin - o) / den2
	return ((o + d * t) - origin).length()


## the normal line is (nearly) along the view: the line has no screen direction, so the mouse moves it up / down
func _line_on_view(p: Vector2) -> bool:
	var r: Array = ui.view.ray_at(ui.m.cam, p)
	var d: Vector3 = (r[1] as Vector3).normalized()
	return 1.0 - axis.dot(d) * axis.dot(d) < 0.1


## metres per screen pixel at the selection's depth (perspective; the camera's fov is vertical)
func _m_per_px() -> float:
	var cam: Camera3D = ui.m.cam
	var z := maxf(-(cam.global_transform.affine_inverse() * origin).z, 0.01)
	var h := float(cam.get_viewport().get_visible_rect().size.y)
	return z * 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / h


func move(p: Vector2) -> void:
	var raw := _measure(p)
	if is_nan(raw):
		return
	var a := raw - s0
	if kind == "inset":
		a = maxf(a, INSET_MIN)
	typed = ""
	if absf(a - amount) < 1e-6:
		return
	_preview(a)
	_say()


## the typed number is the amount, metres (inset: at least INSET_MIN)
func set_typed() -> void:
	if not typed.is_valid_float():
		_say()
		return
	var a := typed.to_float()
	if kind == "inset":
		a = maxf(a, INSET_MIN)
	_preview(a)
	_say()


func _restore_sel() -> void:
	ui.sel.mode = sel0["mode"]
	ui.sel.verts = sel0["verts"].duplicate()
	ui.sel.edges = sel0["edges"].duplicate()
	ui.sel.faces = sel0["faces"].duplicate()


## the op at amount `amt` from the selection before the drag; the previous preview step is replaced (one step)
func _preview(amt: float) -> void:
	var u: KMeshUndo = ui.undo
	if not live.is_empty() and not u.steps.is_empty() and is_same(u.steps[u.steps.size() - 1], live):
		u.undo()
	live = {}
	_restore_sel()
	amount = amt
	u.begin(ui.mesh)
	var r: Dictionary
	if kind == "extrude":
		r = KMeshExtrude.extrude(ui.mesh, ui.sel, amt, each)
	else:
		r = KMeshExtrude.inset(ui.mesh, ui.sel, amt, each)
	err = String(r.get("error", ""))
	if err != "":
		u.commit(kind)
		return
	live = u.commit("Extrude" if kind == "extrude" else "Inset")
	ui.view.mark_dirty()
	ui._ov.queue_redraw()


func confirm() -> void:
	ui.remove_meta(KEY)
	ui.view.mark_dirty()
	ui._ov.queue_redraw()
	var what := "Extrude" if kind == "extrude" else "Inset"
	ui.m._say("Model: %s by %s%s; the new part is selected (Ctrl+Z takes it back)" % [what.to_lower(), Units.len(amount), ", each face on its own" if each else ""])


func cancel() -> void:
	var u: KMeshUndo = ui.undo
	if not live.is_empty() and not u.steps.is_empty() and is_same(u.steps[u.steps.size() - 1], live):
		u.undo()
	u.redos = redos0
	_restore_sel()
	ui.remove_meta(KEY)
	ui.view.mark_dirty()
	ui._ov.queue_redraw()
	ui.m._say("Model: %s cancelled (nothing changed)" % kind)


func _say() -> void:
	var what := "extrude" if kind == "extrude" else "inset"
	var val := ("type %s" % typed) if typed != "" else Units.len(amount)
	ui.m._say("Model: %s %s%s. Mouse moves it; type a number for an exact one; click or Enter confirms, Esc or right click cancels" % [what, val, ", each face on its own" if each else ""])
