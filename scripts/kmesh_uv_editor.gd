class_name KMeshUVEditor
extends Control
## UV editor panel (ROADMAP_400 D01): a 2D view of the model preview mesh's "uv" corner attribute (KMeshUV.UV, one
## Vector2 per face corner = half-edge). Shift+U in the model preview opens / closes it (kmesh_edit_ui.gd). It floats at
## the right edge under the inspector, clear of the "Add primitive" panel (left edge); drag its title strip to move it.
## View: the 0..1 square (orange border, v UP: UV (0,0) is the square's bottom-left pixel corner, (1,1) its top-right), a
##   0.1 grid, the checker behind (C on / off: the same KMeshUV checker the 3D view shows, flipped so a texel sits where
##   the 3D surface samples it). Middle drag pans, the wheel zooms about the mouse, Home frames the square again.
## Select (the keys work while the mouse is over the panel): click a UV vert (the corners of one mesh vertex that share
##   one UV), Shift+click toggles, drag from empty space box selects (Shift adds), L or double-click selects the island
##   under the mouse (faces joined by edges whose two ends share UVs), A all / none.
## Transform: G / R / S move / rotate / scale the selection with the mouse about its bounding-box centre; X / Y lock the
##   u / v axis; typing a number sets it exactly (G: u, or the locked axis; R: degrees, counter-clockwise; S: factor);
##   Enter or a click confirms, Esc or right click cancels. The readout at the bottom shows the value. Each transform is
##   ONE KMeshUndo step on the corner attribute (Ctrl+Z in the model preview undoes it); the 3D checker follows live.

const TITLE := 22.0          # px, the title strip (drag to move the panel)
const MARGIN := 18.0         # px around the 0..1 square when framed
const PICK_PX := 8.0         # px, a click this close to a UV vert picks it
const EPS := 1e-6            # two corners with UVs this close are one UV vert / joined
const SIDE := 380.0          # the panel's default size (square)
const TOP := 310.0           # px from the top: under the inspector panel and the view cube's shading buttons
const UNIT_COL := Color(1.0, 0.6, 0.1)
const READ_COL := Color(1.0, 0.85, 0.4)

var ui                      # KMeshEditUI (mesh, undo, view, m)
var sel := PackedByteArray()  # per corner (half-edge): 1 = selected
var zoom := 0.0             # px per UV unit
var origin := Vector2.ZERO  # local px of UV (0, 0)
var show_checker := true
var mode := ""              # "", "G", "R", "S": the transform in progress
var axis := ""              # "", "x", "y"
var typed := ""             # the number typed during a transform
var value := Vector2.ZERO   # G: (du, dv); R: (degrees, 0); S: (factor, factor)
var pivot := Vector2.ZERO
var _orig := PackedVector2Array()
var _start := Vector2.ZERO  # local px where the transform started
var _mouse := Vector2.ZERO
var _pan := false
var _box := false
var _box_add := false
var _press := Vector2.ZERO
var _move_win := false
var seam_flag := {}        # D13: edge key -> true for flagged seam edges (SeamMotion), drawn red in the view
var seam_sugg := {}        # D13: edge key -> true for the suggested lower-stretch path edges, drawn green
var seam_lines: Array = [] # D13: the flagged-seam list shown under the title
var _sm_rep := {}
var _sm_flagged: Array = []   # chains (Array of Vector2i) that are flagged
var _win_grab := Vector2.ZERO


func setup(edit_ui) -> void:
	ui = edit_ui
	name = "uv_editor"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	visible = false
	size = Vector2(SIDE, SIDE + TITLE)
	mouse_entered.connect(func(): grab_focus())
	mouse_exited.connect(func():
		if mode == "" and not _pan and not _box and not _move_win:
			release_focus())
	ui.m.ui_root.add_child(self)
	get_viewport().size_changed.connect(func():
		if visible:
			place())


func mesh() -> KMesh:
	return ui.mesh


## show the panel; a mesh without UVs is unwrapped first (seams by angle + LSCM, as U does) and the 3D view shows the checker
func open() -> void:
	var mm := mesh()
	if not mm.has_attr(KMeshUV.UV):
		KMeshUV.seams_by_angle(mm, 60.0)
		KMeshUV.unwrap_lscm(mm)
	if ui.view.shading != "uv_checker":
		ui.view.shading = "uv_checker"
		ui.view.mark_dirty()
	visible = true
	place()
	frame_all()
	_fit_sel()


func close() -> void:
	if mode != "":
		cancel()
	visible = false
	release_focus()


## at the right edge under the inspector; never over the "Add primitive" panel (moved right of it if the window is narrow)
func place() -> void:
	var vr := get_viewport_rect().size
	var s := minf(SIDE, maxf(160.0, vr.y - TOP - 210.0))
	size = Vector2(s, s + TITLE)
	position = Vector2(vr.x - s - 6.0, TOP)
	var pp: Control = ui.prim_panel
	if pp != null and pp.is_visible_in_tree() and get_global_rect().intersects(pp.get_global_rect()):
		position.x = pp.get_global_rect().end.x + 8.0
	var mp: Control = ui.mat_panel
	if mp != null and mp.is_visible_in_tree():
		# walk-through 3: docked in the Materials column, UNDER that panel (beside it, the panel covered the mesh and its
		# clicks landed here). Its width is the Materials column's; its height is what the page has left above the status row
		# below the lowest visible control of the Materials column too (a clipped Name / colour field sits under the panel's box)
		var bottom: float = ui.m.nav_clear_rect().end.y
		var top: float = mp.position.y + mp.size.y + 8.0
		for c in mp.find_children("*", "Control", true, false):
			if (c as Control).is_visible_in_tree():
				top = maxf(top, (c as Control).get_global_rect().end.y + 8.0)
		s = clampf(bottom - top - TITLE, 120.0, SIDE)
		size = Vector2(mp.size.x, s + TITLE)
		position = Vector2(mp.position.x, top)


func frame_all() -> void:
	zoom = minf(size.x, size.y - TITLE) - 2.0 * MARGIN
	origin = Vector2((size.x - zoom) * 0.5, TITLE + (size.y - TITLE + zoom) * 0.5)
	queue_redraw()


## local px of a UV (v up)
func uv_to_px(uv: Vector2) -> Vector2:
	return origin + Vector2(uv.x, -uv.y) * zoom


func px_to_uv(p: Vector2) -> Vector2:
	var d := (p - origin) / zoom
	return Vector2(d.x, -d.y)


func _uvs() -> PackedVector2Array:
	return mesh().attr_data(KMeshUV.UV) if mesh().has_attr(KMeshUV.UV) else PackedVector2Array()


func _fit_sel() -> void:
	var n := mesh().half_edge_count()
	if sel.size() != n:
		sel = PackedByteArray()
		sel.resize(n)


func selected_corners() -> PackedInt32Array:
	_fit_sel()
	var out := PackedInt32Array()
	for h in sel.size():
		if sel[h] == 1:
			out.append(h)
	return out


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()   # an undo / redo in the model preview changes the UVs under us


# ---------------------------------------------------------------- selection

## the corner nearest `p` (local px) within PICK_PX, or -1
func corner_at(p: Vector2) -> int:
	var uv := _uvs()
	var best := -1
	var bd := PICK_PX * PICK_PX
	for h in uv.size():
		var d := uv_to_px(uv[h]).distance_squared_to(p)
		if d < bd:
			bd = d
			best = h
	return best


## every corner of the same mesh vertex with (nearly) the same UV as corner h
func _uv_vert(h: int) -> PackedInt32Array:
	var uv := _uvs()
	var hv := mesh().he_vert
	var out := PackedInt32Array()
	for c in uv.size():
		if hv[c] == hv[h] and uv[c].distance_to(uv[h]) < EPS:
			out.append(c)
	return out


func select_click(p: Vector2, add := false) -> bool:
	_fit_sel()
	var h := corner_at(p)
	if not add:
		sel.fill(0)
	if h == -1:
		queue_redraw()
		return false
	var on := 0 if add and sel[h] == 1 else 1
	for c in _uv_vert(h):
		sel[c] = on
	queue_redraw()
	return true


## corners whose UV lies inside the local-px rect r
func select_box(r: Rect2, add := false) -> int:
	_fit_sel()
	if not add:
		sel.fill(0)
	var uv := _uvs()
	var n := 0
	for h in uv.size():
		if r.has_point(uv_to_px(uv[h])):
			sel[h] = 1
			n += 1
	queue_redraw()
	return n


## per face its UV island id: faces joined across an edge whose two ends have the same UVs on both sides
func islands() -> PackedInt32Array:
	var mm := mesh()
	var uv := _uvs()
	var nf := mm.face_count()
	var p := PackedInt32Array()
	p.resize(nf)
	for f in nf:
		p[f] = f
	var hn := mm.he_next
	var ht := mm.he_twin
	var hf := mm.he_face
	for h in uv.size():
		var t := ht[h]
		if t == -1 or t < h:
			continue
		# h: a->b in F, t: b->a in G. a is corner h of F and corner next(t) of G; b is next(h) of F and t of G
		if uv[h].distance_to(uv[hn[t]]) < EPS and uv[hn[h]].distance_to(uv[t]) < EPS:
			var x := KMeshUV._find(p, hf[h])
			var y := KMeshUV._find(p, hf[t])
			if x != y:
				p[x] = y
	var out := PackedInt32Array()
	out.resize(nf)
	for f in nf:
		out[f] = KMeshUV._find(p, f)
	return out


## the face whose UV polygon holds `p` (local px), else the face of the nearest corner within PICK_PX, else -1
func face_at(p: Vector2) -> int:
	var mm := mesh()
	var uv := _uvs()
	var at := px_to_uv(p)
	for f in mm.face_count():
		var poly := PackedVector2Array()
		var h0 := mm.face_he0[f]
		for i in (mm.faces[f] as PackedInt32Array).size():
			poly.append(uv[h0 + i])
		if Geometry2D.is_point_in_polygon(at, poly):
			return f
	var h := corner_at(p)
	return mm.he_face[h] if h != -1 else -1


## select every corner of face f's island (add: keep the rest); returns how many corners
func select_island(f: int, add := false) -> int:
	_fit_sel()
	if not add:
		sel.fill(0)
	if f < 0:
		queue_redraw()
		return 0
	var isl := islands()
	var hf := mesh().he_face
	var n := 0
	for h in sel.size():
		if isl[hf[h]] == isl[f]:
			sel[h] = 1
			n += 1
	queue_redraw()
	return n


func select_island_at(p: Vector2, add := false) -> int:
	return select_island(face_at(p), add)


func select_all() -> void:
	_fit_sel()
	var any := false
	for b in sel:
		if b == 1:
			any = true
			break
	sel.fill(0 if any else 1)
	queue_redraw()


# ---------------------------------------------------------------- transform

## start G / R / S on the selection: one KMeshUndo step opens; false when nothing is selected
func begin(md: String) -> bool:
	var cs := selected_corners()
	if cs.is_empty() or not mesh().has_attr(KMeshUV.UV):
		ui.m._say("UV: nothing selected. Click a UV vert, drag a box, or L for the island under the mouse")
		return false
	if mode != "":
		cancel()
	_orig = _uvs().duplicate()
	var bb := Rect2(_orig[cs[0]], Vector2.ZERO)
	for h in cs:
		bb = bb.expand(_orig[h])
	pivot = bb.get_center()
	mode = md
	axis = ""
	typed = ""
	value = Vector2.ZERO if md == "G" else (Vector2.ONE if md == "S" else Vector2.ZERO)
	_start = _mouse
	ui.undo.begin(mesh())
	grab_focus()
	queue_redraw()
	return true


## the transform's value from the mouse at `p` (local px), unless a number was typed
func drag_to(p: Vector2) -> void:
	_mouse = p
	if mode == "" or typed != "":
		return
	var a := px_to_uv(_start)
	var b := px_to_uv(p)
	match mode:
		"G":
			value = b - a
		"R":
			value = Vector2(rad_to_deg((b - pivot).angle() - (a - pivot).angle()), 0.0)
		"S":
			var d0 := (a - pivot).length()
			var f := (b - pivot).length() / d0 if d0 > 1e-9 else 1.0
			value = Vector2(f, f)
	_apply()


## a typed number (the readout's value): G = u (or the locked axis), R = degrees, S = factor
func type_value(text: String) -> void:
	typed = text
	var v := text.to_float() if text.is_valid_float() else (1.0 if mode == "S" else 0.0)
	match mode:
		"G":
			value = Vector2(0.0, v) if axis == "y" else Vector2(v, 0.0)
		"R":
			value = Vector2(v, 0.0)
		"S":
			value = Vector2(v if axis != "y" else 1.0, v if axis != "x" else 1.0)
	_apply()


func set_axis(ax: String) -> void:
	axis = "" if axis == ax else ax
	if typed != "":
		type_value(typed)
	else:
		drag_to(_mouse)
	_apply()


## the UV of one corner under the current transform
func _xf(u: Vector2) -> Vector2:
	match mode:
		"G":
			var d := value
			if axis == "x":
				d.y = 0.0
			elif axis == "y":
				d.x = 0.0
			return u + d
		"R":
			var r := deg_to_rad(value.x)
			var c := cos(r)
			var s := sin(r)
			var q := u - pivot
			return pivot + Vector2(q.x * c - q.y * s, q.x * s + q.y * c)
		"S":
			var k := value
			if axis == "x":
				k.y = 1.0
			elif axis == "y":
				k.x = 1.0
			return pivot + (u - pivot) * k
	return u


func _apply() -> void:
	if mode == "":
		return
	var out := _orig.duplicate()
	for h in selected_corners():
		out[h] = _xf(_orig[h])
	mesh().set_attr_data(KMeshUV.UV, out)
	ui.view.mark_dirty()   # the 3D checker follows live
	queue_redraw()


func readout() -> String:
	var t := typed if typed != "" else ""
	match mode:
		"G":
			var d := value
			if axis == "x":
				d.y = 0.0
			elif axis == "y":
				d.x = 0.0
			return "Move  du %.4f  dv %.4f%s%s" % [d.x, d.y, ("   [" + t + "]") if t != "" else "", ("   axis " + axis) if axis != "" else ""]
		"R":
			return "Rotate  %.2f deg%s" % [value.x, ("   [" + t + "]") if t != "" else ""]
		"S":
			return "Scale  %.4f x %.4f%s%s" % [value.x if axis != "y" else 1.0, value.y if axis != "x" else 1.0, ("   [" + t + "]") if t != "" else "", ("   axis " + axis) if axis != "" else ""]
	return ""


## keep the transform: its one undo step is closed
func confirm() -> Dictionary:
	if mode == "":
		return {}
	var what: String = {"G": "UV move", "R": "UV rotate", "S": "UV scale"}[mode]
	var said := readout()
	mode = ""
	var st: Dictionary = ui.undo.commit(what)
	ui.view.mark_dirty()
	ui.m._say("UV: %s. Ctrl+Z undoes" % said if not st.is_empty() else "UV: nothing moved")
	queue_redraw()
	return st


## put the UVs back as they were: no step is kept
func cancel() -> void:
	if mode == "":
		return
	mode = ""
	mesh().set_attr_data(KMeshUV.UV, _orig)
	ui.undo.commit("cancelled")   # nothing changed: commit keeps no step
	ui.view.mark_dirty()
	ui.m._say("UV: cancelled")
	queue_redraw()


# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var mp := (ev as InputEventMouseMotion).position
		if _move_win:
			position += mp - _win_grab
			accept_event()
			return
		if _pan:
			origin += (ev as InputEventMouseMotion).relative
		elif mode != "":
			drag_to(mp)
		_mouse = mp
		queue_redraw()
		accept_event()
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		_mouse = mb.position
		accept_event()
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(mb.position, 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			MOUSE_BUTTON_MIDDLE:
				_pan = mb.pressed
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and mode != "":
					cancel()
			MOUSE_BUTTON_LEFT:
				_left(mb)
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if _key(ev as InputEventKey):
			accept_event()


func zoom_at(p: Vector2, f: float) -> void:
	var uv := px_to_uv(p)
	zoom = clampf(zoom * f, 20.0, 40000.0)
	origin += p - uv_to_px(uv)
	queue_redraw()


func _left(mb: InputEventMouseButton) -> void:
	grab_focus()
	if mb.pressed:
		if mode != "":
			confirm()
			return
		if mb.position.y < TITLE:
			_move_win = true
			_win_grab = mb.position
			return
		if mb.double_click:
			_report(select_island_at(mb.position, mb.shift_pressed), "island")
			return
		_press = mb.position
		_box_add = mb.shift_pressed
		if select_click(mb.position, mb.shift_pressed):
			_report(selected_corners().size(), "")
		else:
			_box = true
		return
	if _move_win:
		_move_win = false
		return
	if _box:
		_box = false
		if mb.position.distance_to(_press) > 4.0:
			_report(select_box(Rect2(_press, Vector2.ZERO).expand(mb.position), _box_add), "")
		queue_redraw()


func _key(k: InputEventKey) -> bool:
	if k.ctrl_pressed or k.alt_pressed:
		return mode != ""   # no Ctrl+Z in the middle of a transform
	var kc := k.keycode
	if mode != "":
		match kc:
			KEY_ENTER, KEY_KP_ENTER:
				confirm()
			KEY_ESCAPE:
				cancel()
			KEY_X:
				set_axis("x")
			KEY_Y:
				set_axis("y")
			KEY_BACKSPACE:
				if typed.length() > 1:
					type_value(typed.substr(0, typed.length() - 1))
				else:
					_untype()
			KEY_MINUS, KEY_KP_SUBTRACT:
				type_value(typed.substr(1) if typed.begins_with("-") else "-" + typed)
			KEY_PERIOD, KEY_KP_PERIOD:
				if not "." in typed:
					type_value(typed + ".")
			_:
				var dg := _digit(kc)
				if dg >= 0:
					type_value(typed + str(dg))
		return true   # every key belongs to the transform until it is kept or cancelled
	match kc:
		KEY_G, KEY_R, KEY_S:
			begin({KEY_G: "G", KEY_R: "R", KEY_S: "S"}[kc])
		KEY_L:
			_report(select_island_at(_mouse, k.shift_pressed), "island")
		KEY_A:
			select_all()
			_report(selected_corners().size(), "")
		KEY_C:
			show_checker = not show_checker
			queue_redraw()
		KEY_M:
			seam_motion_check()
		KEY_N:
			seam_motion_suggest()
		KEY_HOME:
			frame_all()
		_:
			return false
	return true


func _untype() -> void:
	typed = ""
	drag_to(_mouse)
	_apply()


static func _digit(kc: int) -> int:
	if kc >= KEY_0 and kc <= KEY_9:
		return kc - KEY_0
	if kc >= KEY_KP_0 and kc <= KEY_KP_9:
		return kc - KEY_KP_0
	return -1


func _report(n: int, what: String) -> void:
	ui.m._say("UV: %d corners selected%s. G / R / S move / rotate / scale, L the island under the mouse" % [n, (" (" + what + ")") if what != "" else ""])


# ---------------------------------------------------------------- D13 seams that avoid motion

## the marked seam edges of the mesh ("seam" attribute > 0.5), unique, a < b
func _seam_edges() -> Array:
	var mm := mesh()
	var out: Array = []
	if mm == null or not mm.has_attr(KMeshUV.SEAM):
		return out
	var d: PackedFloat32Array = mm.attr_data(KMeshUV.SEAM)
	var i := 0
	for e in mm.edges():
		if i < d.size() and d[i] > 0.5:
			out.append(e)
		i += 1
	return out


## M: flag the seams that cross a high-stretch area of the open scene (SeamMotion). Writes nothing to the mesh.
## -> {"flagged_seams": [{"edges", "max_local", "n_flagged"}], "seams": the same for all, "report"}
func seam_motion_check() -> Dictionary:
	seam_flag = {}
	seam_sugg = {}
	seam_lines = []
	_sm_flagged = []
	var seams := _seam_edges()
	if seams.is_empty() or BaseBody.skin_of(ui.m) == null:
		seam_lines = ["seam motion: no seams marked (or no skin)"]
		queue_redraw()
		return {"flagged_seams": [], "seams": [], "report": {}}
	_sm_rep = SeamMotion.run(mesh(), ui.m, seams)
	var byk := {}
	for r in _sm_rep["edges"]:
		byk[SeamMotion.ekey(r["edge"].x, r["edge"].y)] = r
	var all: Array = []
	var fl: Array = []
	for ch in SeamMotion.chains(seams):
		var mx := 0.0
		var nf := 0
		for e in ch:
			var r: Dictionary = byk[SeamMotion.ekey(e.x, e.y)]
			mx = maxf(mx, float(r["local"]))
			if r["flag"]:
				nf += 1
				seam_flag[SeamMotion.ekey(e.x, e.y)] = true
		var c := {"edges": ch, "max_local": mx, "n_flagged": nf}
		all.append(c)
		if nf > 0:
			fl.append(c)
			_sm_flagged.append(ch)
	var k := 0
	for c in fl:
		k += 1
		seam_lines.append("seam %d: %d of %d edges over %.2f, worst %.2f" % [k, c["n_flagged"], (c["edges"] as Array).size(), SeamMotion.THRESHOLD, c["max_local"]])
	if fl.is_empty():
		seam_lines = ["seam motion: no seam crosses stretch >= %.2f" % SeamMotion.THRESHOLD]
	else:
		seam_lines.append("N suggests a lower-stretch path")
	queue_redraw()
	return {"flagged_seams": fl, "seams": all, "report": _sm_rep}


## N: for every flagged open seam, a nearby lower-stretch path with the same ends (green). -> the suggestions that improve
func seam_motion_suggest() -> Array:
	if _sm_rep.is_empty():
		seam_motion_check()
	var out: Array = []
	seam_sugg = {}
	for ch in _sm_flagged:
		var sg := SeamMotion.suggest(mesh(), _sm_rep, ch)
		if sg.is_empty() or not sg["ok"]:
			continue
		out.append(sg)
		for e in sg["edges"]:
			seam_sugg[SeamMotion.ekey(e.x, e.y)] = true
		seam_lines.append("suggested path: worst %.2f instead of %.2f" % [sg["max_local"], sg["orig_max"]])
	queue_redraw()
	return out


# ---------------------------------------------------------------- draw

func square_rect() -> Rect2:
	return Rect2(uv_to_px(Vector2(0, 1)), Vector2(zoom, zoom))


func _draw() -> void:
	var bg := Tok.c("panel")
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	var tc := Tok.c("text")
	var font := get_theme_default_font()
	var sq := square_rect()
	if show_checker:
		KMeshUV.checker_material()   # makes the shared checker texture on first use
		var tex: Texture2D = KMeshUV._checker_tex
		if tex != null:
			# image row 0 is v = 0 (Godot samples top-down): flip it so v grows upward like the square
			draw_set_transform(Vector2(0, sq.end.y), 0.0, Vector2(1, -1))
			draw_texture_rect(tex, Rect2(sq.position.x, 0.0, sq.size.x, sq.size.y), false, Color(1, 1, 1, 0.45))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var gc := Color(tc, 0.12)
	for i in range(1, 10):
		var t := i / 10.0
		draw_line(uv_to_px(Vector2(t, 0)), uv_to_px(Vector2(t, 1)), gc, 1.0)
		draw_line(uv_to_px(Vector2(0, t)), uv_to_px(Vector2(1, t)), gc, 1.0)
	draw_rect(sq, UNIT_COL, false, 1.0)
	var mm := mesh()
	if mm != null and mm.has_attr(KMeshUV.UV) and visible:
		_fit_sel()
		var uv := _uvs()
		var ec := Color(tc, 0.7)
		var sc := Tok.c("pick_sel")
		for f in mm.face_count():
			var n := (mm.faces[f] as PackedInt32Array).size()
			var h0 := mm.face_he0[f]
			for i in n:
				var a := h0 + i
				var b := h0 + (i + 1) % n
				draw_line(uv_to_px(uv[a]), uv_to_px(uv[b]), sc if sel[a] == 1 and sel[b] == 1 else ec, 1.0)
				if not seam_flag.is_empty() or not seam_sugg.is_empty():
					var fv: PackedInt32Array = mm.faces[f]
					var mk := SeamMotion.ekey(fv[i], fv[(i + 1) % n])
					if seam_flag.has(mk):
						draw_line(uv_to_px(uv[a]), uv_to_px(uv[b]), Color(1, 0.15, 0.1), 2.5)
					elif seam_sugg.has(mk):
						draw_line(uv_to_px(uv[a]), uv_to_px(uv[b]), Color(0.2, 0.9, 0.3), 2.5)
		for h in uv.size():
			if sel[h] == 1:
				draw_rect(Rect2(uv_to_px(uv[h]) - Vector2(2.5, 2.5), Vector2(5, 5)), sc, true)
	if _box:
		var r := Rect2(_press, Vector2.ZERO).expand(_mouse)
		var hc := Tok.c("pick_hover")
		draw_rect(r, Color(hc, 0.15), true)
		draw_rect(r, hc, false, 1.0)
	draw_rect(Rect2(0, 0, size.x, TITLE), Color(bg.darkened(0.25), 1.0), true)
	draw_string(font, Vector2(8, 16), "UV editor   Shift+U closes   C checker", HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 13, tc)
	for li in seam_lines.size():
		draw_string(font, Vector2(8, TITLE + 16 + li * 15), seam_lines[li], HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 12, Color(1, 0.4, 0.3))
	if mode != "":
		var rt := readout() +"   Enter keeps, Esc cancels"
		draw_rect(Rect2(0, size.y - 22, size.x, 22), Color(0, 0, 0, 0.6), true)
		draw_string(font, Vector2(8, size.y - 7), rt, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 13, READ_COL)
