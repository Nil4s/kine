class_name KMeshPivot
extends Node
## PIVOT MODES FOR R / S + THE 3D CURSOR (ROADMAP_400 B14), for the Blender-style G / R / S of the model preview
## (bl_keys.gd). "." (period, model preview) cycles the pivot:
##   median      the centre of the selected vertices (what R / S always did)
##   active      the element clicked last (a vertex, an edge's midpoint, a face's centre), if it is still selected;
##               else the median, said so
##   cursor      the 3D cursor
##   individual  each island turns / scales about its own centre: in face mode an island is a set of selected faces
##               that share a vertex (so faces apart each scale about their own centre), in vertex / edge mode a set
##               of selected vertices joined by edges of the mesh
## The 3D cursor: Shift+right-click puts it on the surface under the mouse (the test mesh or the fighter's skin, the
## nearer; past both, the floor). Drawn as a crosshair (a red / white ring, four ticks) while the model preview is on;
## drawn_at = its centre on screen. Starts at the world origin (the fighter's feet).
## Tests: tests/pivot_test.gd.

const MODES := ["median", "active", "cursor", "individual"]
const NAMES := {"median": "median point", "active": "active element", "cursor": "3D cursor", "individual": "individual origins"}
const CROSS_R := 10.0

var ui                    # the model preview (KMeshEditUI)
var m                     # the poser (main.gd)
var mode := "median"
var cursor := Vector3.ZERO          # world
var active := {}                    # the element clicked last: {"mode", "key"}
var drawn_at := Vector2(NAN, NAN)   # where the crosshair was last drawn (screen)
var _ov: Control
var _last_cam := Transform3D()


func setup(edit_ui) -> void:
	ui = edit_ui
	m = ui.m
	name = "kmesh_pivot"
	_ov = Control.new()
	_ov.name = "cursor3d"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.draw.connect(_draw)
	m.ui_root.add_child(_ov)


func cycle() -> String:
	mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
	m._say("Model: pivot %s (. next; R / S turn and scale about it%s)" % [NAMES[mode], ", Shift+right-click places the cursor" if mode == "cursor" else ""])
	return mode


## the model preview's input (KMeshEditUI.input calls this first): "." cycles, Shift+right-click places the cursor;
## a left press notes the element under the mouse as the active one (not used: the click goes on to select)
func input(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := ev as InputEventKey
		if k.keycode == KEY_PERIOD and not (k.ctrl_pressed or k.alt_pressed or k.shift_pressed):   # Numpad . is frame selected (main.gd _mesh_view_key)
			cycle()
			return true
		return false
	if ev is InputEventMouseButton and ev.pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.shift_pressed:
			place_at(mb.position)
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT and ui.armed == "":
			_note_active(mb.position)
	return false


func _note_active(p: Vector2) -> void:
	var h: Dictionary = ui.view.pick(m.cam, p)
	if h.is_empty():
		return
	match ui.sel.mode:
		KMeshSelect.VERT:
			if int(h["vert"]) >= 0:
				active = {"mode": KMeshSelect.VERT, "key": int(h["vert"])}
		KMeshSelect.EDGE:
			if (h["edge"] as Vector2i).x >= 0:
				active = {"mode": KMeshSelect.EDGE, "key": h["edge"]}
		_:
			active = {"mode": KMeshSelect.FACE, "key": int(h["face"])}


## the 3D cursor onto the surface under screen point p (the mesh or the skin, the nearer; else the floor). true = placed
func place_at(p: Vector2) -> bool:
	var cam: Camera3D = m.cam
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	var best := INF
	var at := Vector3.ZERO
	var on := ""
	var h: Dictionary = ui.view.ray_face(o, d)
	if not h.is_empty():
		best = float(h["t"])
		at = h["point"]
		on = "the mesh"
	var sp: SkinPick = m.get("skp")
	if sp != null:
		var b: Array = sp.pick(o, d, m.hidden_parts)
		if float(b[1]) < best:
			best = b[1]
			at = b[2]
			on = "the fighter's skin"
	if on == "" and d.y < -1e-6 and o.y > 0.0:
		at = o + d * (-o.y / d.y)
		on = "the floor"
	if on == "":
		m._say("Model: nothing under the mouse to put the 3D cursor on (aim at the mesh, the fighter or the floor)")
		return false
	cursor = at
	_ov.queue_redraw()
	m._say("Model: 3D cursor on %s (%s). Pivot: %s (. cycles; cursor is one of them)" % [on, Units.len(at.x) + ", " + Units.len(at.y) + ", " + Units.len(at.z), NAMES[mode]])
	return true


## the pivot for R / S of the vertices idx (start: the mesh's verts at the start; median: their centre), mesh space
func centre(idx: PackedInt32Array, start: PackedVector3Array, median: Vector3) -> Vector3:
	match mode:
		"cursor":
			return ui.view.global_transform.affine_inverse() * cursor
		"active":
			var a := active_point(start)
			if a.is_empty():
				m._say("Model: no active element in the selection (click one last): turning about the median instead")
				return median
			return a["point"]
	return median


## the active element's centre (mesh space) if it is in the selection now: {"point"} or {}
func active_point(start: PackedVector3Array) -> Dictionary:
	var s: KMeshSelect = ui.sel
	if active.is_empty() or int(active["mode"]) != s.mode or not s._live().has(active["key"]):
		return {}
	var k = active["key"]
	match s.mode:
		KMeshSelect.VERT:
			return {"point": start[int(k)]}
		KMeshSelect.EDGE:
			return {"point": (start[(k as Vector2i).x] + start[(k as Vector2i).y]) * 0.5}
	var f: PackedInt32Array = ui.mesh.faces[int(k)]
	var c := Vector3.ZERO
	for v in f:
		c += start[v]
	return {"point": c / float(f.size())}


## individual origins: vertex -> its island's centre (mesh space); {} in the other modes
func origins(idx: PackedInt32Array, start: PackedVector3Array) -> Dictionary:
	if mode != "individual":
		return {}
	var mesh: KMesh = ui.mesh
	var s: KMeshSelect = ui.sel
	var inset := {}
	for i in idx:
		inset[i] = true
	var parent := {}
	for i in idx:
		parent[i] = i
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	var join := func(a: int, b: int) -> void:
		var ra: int = find.call(a)
		var rb: int = find.call(b)
		if ra != rb:
			parent[ra] = rb
	if s.mode == KMeshSelect.FACE:
		for fi in s.faces:
			var f: PackedInt32Array = mesh.faces[fi]
			for v in f:
				join.call(f[0], v)
	else:
		for f in mesh.faces:
			var n := (f as PackedInt32Array).size()
			for k in n:
				var a: int = f[k]
				var b: int = f[(k + 1) % n]
				if inset.has(a) and inset.has(b):
					join.call(a, b)
	var sum := {}
	var cnt := {}
	for i in idx:
		var r: int = find.call(i)
		sum[r] = (sum.get(r, Vector3.ZERO) as Vector3) + start[i]
		cnt[r] = int(cnt.get(r, 0)) + 1
	var out := {}
	for i in idx:
		var r: int = find.call(i)
		out[i] = (sum[r] as Vector3) / float(cnt[r])
	return out


## individual origins after the move loop (bl_keys._apply_mesh): each vertex again from its start, about its island's
## centre (pc: origins()). basis / sc: the rotate / scale of this frame
func apply_individual(pc: Dictionary, start: PackedVector3Array, which: String, basis: Basis, sc: Vector3) -> void:
	if pc.is_empty() or which == "G":
		return
	var mesh: KMesh = ui.mesh
	for i in pc:
		var c: Vector3 = pc[i]
		mesh.verts[i] = c + basis * (start[i] - c) if which == "R" else c + (start[i] - c) * sc


func _process(_dt: float) -> void:
	if ui == null:
		return
	var show: bool = ui.on
	if show != _ov.visible:
		_ov.visible = show
	if show and m.cam.global_transform != _last_cam:
		_last_cam = m.cam.global_transform
		_ov.queue_redraw()


func _draw() -> void:
	drawn_at = Vector2(NAN, NAN)
	if not ui.on:
		return
	var cam: Camera3D = m.cam
	if cam.is_position_behind(cursor):
		return
	var s := cam.unproject_position(cursor)
	var r := CROSS_R
	for q in 8:   # the ring in red / white quarters, like Blender's
		_ov.draw_arc(s, r, q * TAU / 8.0, (q + 1) * TAU / 8.0, 6, Color(0.9, 0.15, 0.1) if q % 2 == 0 else Color(1, 1, 1), 2.0)
	for dv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_ov.draw_line(s + dv * (r * 0.4), s + dv * (r * 1.7), Color(0.05, 0.05, 0.05), 1.5)
	drawn_at = s
