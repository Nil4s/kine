class_name KMeshCurvesUI
extends Node
## B11 + B12 in the model preview (scripts/kmesh_edit_ui.gd): the "Spin / curves" panel and THE CURVE OBJECT.
## Opened by mesh_tools "op:curves" (the panel), "op:curve_add" / "op:curve_circle" (a new curve), "op:lathe" (the selected
## edge chain), "op:lathe_typed", "op:curve_wrap" (onto the body), "op:curve_to_mesh". No new keys (the map is full).
## SPIN / LATHE (KMeshLathe): angle, steps, screw (cm per turn), turns, axis X / Y / Z (mesh space), centre (the 3D cursor
##   or the mesh's origin), a typed profile ("r,y" pairs in cm). The result is added as ONE undo step and stays LIVE (each
##   field change rebuilds it in that same step) until the next edit, like B09's primitives.
## THE CURVE (KMeshCurve): drawn in the preview (the curve, its handles, its points; the swept tube shaded under it).
##   Left-drag a point (its handles come along) or a handle (the opposite one turns to stay aligned, keeping its length);
##   Alt+click adds a point after the last one, on the plane through it facing the camera. Each drag, add, field change
##   or wrap is ONE undo step of the mesh's own history (Ctrl+Z): the step carries an "apply" callable that KMeshUndo
##   runs (the curve is not mesh data). Repeated changes of one field fold into one step while it is the newest.
##   "Convert to mesh" adds the sweep to the mesh and removes the curve: ONE step (Ctrl+Z gives the curve back).

const PICK_PX := 10.0
const WRAP_OFFSET := 0.003   # m: a belt 3 mm off the skin
const AXES := {"X": Vector3.RIGHT, "Y": Vector3.UP, "Z": Vector3.BACK}

var ui   # KMeshEditUI
var m
var panel: PanelContainer
var curve: KMeshCurve
var sel_pt := -1
var lines: MeshInstance3D
var tube: MeshInstance3D
var lathe_opts := {"angle": 360.0, "steps": 32, "screw": 0.0, "turns": 1, "axis": "Y", "center": "cursor"}
var typed := "0,0 10,0 10,4 6,8 6,20 0,20"
var live := {}          # the lathe still live: {"src", "step", "base_v", "base_f", "base_a"}
var _drag := {}
var _f := {}            # field name -> Control
var _quiet := false     # fields being set from code


## the curves node of a model preview (made on first use)
static func of(edit_ui) -> KMeshCurvesUI:
	var c: KMeshCurvesUI = edit_ui.get_node_or_null("kmesh_curves")
	if c == null:
		c = KMeshCurvesUI.new()
		c.name = "kmesh_curves"
		edit_ui.add_child(c)
		c.setup(edit_ui)
	return c


## KMeshEditUI.input asks this first: a drag on a curve point / handle, Alt+click to add one. true = used
static func handle(edit_ui, ev: InputEvent) -> bool:
	var c: KMeshCurvesUI = edit_ui.get_node_or_null("kmesh_curves")
	return c != null and c.input(ev)


func setup(edit_ui) -> void:
	ui = edit_ui
	m = ui.m
	_build_panel()


func _process(_dt: float) -> void:
	if panel != null and panel.visible and not ui.on:
		panel.visible = false
	if not ui.on and curve != null:
		curve = null   # the preview was left: nothing is kept (like the test cube)
		live = {}


# ---------------------------------------------------------------- undo (the curve rides on the mesh's history)

func _state() -> Variant:
	return curve.to_dict() if curve != null else null


func _restore(d: Variant) -> void:
	curve = KMeshCurve.new().from_dict(d) if d != null else null
	if curve == null or sel_pt >= curve.pts.size():
		sel_pt = -1
	_redraw()
	_fill_fields()


## one step of the mesh history that turns the curve from `before` into what it is now; `fold`: a field change of the
## same name while its step is still the newest updates that step instead
func _push(label: String, before: Variant, fold := "") -> Dictionary:
	var after: Variant = _state()
	if before == after:
		return {}
	var u: KMeshUndo = ui.undo
	if fold != "" and not u.steps.is_empty():
		var top: Dictionary = u.steps[u.steps.size() - 1]
		if top.get("fold", "") == fold and top.has("c"):
			top["c"][1] = after
			_redraw()
			return top
	var cc := [before, after]
	var st := {"label": label, "kind": "curve", "bytes": 1024, "mesh": ui.mesh, "c": cc, "fold": fold,
		"apply": func(back: bool): _restore(cc[0] if back else cc[1])}
	u.steps.append(st)
	u.redos.clear()
	u._trim()
	_redraw()
	return st


# ---------------------------------------------------------------- the curve

func new_curve(kind := "s") -> String:
	var b: Variant = _state()
	var at := _free_spot()
	curve = KMeshCurve.circle(at + Vector3(0.0, 0.0, 0.0), 0.2) if kind == "circle" else KMeshCurve.s_curve(at - Vector3(0.3, 0.0, 0.0))
	sel_pt = 0
	_push("New curve", b)
	_fill_fields()
	panel.visible = true
	_place_panel()
	return "Model: a new %s curve (%d points; drag a point or a handle, Alt+click adds one; one undo step)" % ["circle" if kind == "circle" else "bezier", curve.pts.size()]


## a spot beside the mesh (mesh space): PRIM_GAP past its +X side, half way up
func _free_spot() -> Vector3:
	if ui.mesh.vert_count() == 0:
		return Vector3(0.0, 0.3, 0.0)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in ui.mesh.verts:
		lo = lo.min(v)
		hi = hi.max(v)
	return Vector3(hi.x + 0.1 + 0.35, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)


func add_point_at(local: Vector3) -> void:
	var b: Variant = _state()
	var last: Dictionary = curve.pts[curve.pts.size() - 1]
	var d: Vector3 = (local - last["p"]) / 3.0
	curve.pts.append(KMeshCurve.point(local, local - d, local + d))
	sel_pt = curve.pts.size() - 1
	_push("Add a curve point", b)


## a curve field changed (profile, sides, radius, width, thickness, taper, tilt, closed): one step per field while it is
## the newest
func set_field(name_: String, v) -> void:
	if curve == null:
		return
	var b: Variant = _state()
	match name_:
		"profile":
			curve.profile = KMeshCurve.PROFILES[clampi(int(v), 0, 1)]
		"sides":
			curve.sides = maxi(3, int(v))
		"radius":
			curve.radius = maxf(0.0005, float(v))
		"width":
			curve.width = maxf(0.001, float(v))
		"thickness":
			curve.height = maxf(0.0005, float(v))
		"taper":
			curve.taper = PackedVector2Array() if absf(float(v) - 1.0) < 1e-9 else PackedVector2Array([Vector2(0, 1), Vector2(1, float(v))])
		"tilt":
			if sel_pt >= 0:
				curve.pts[sel_pt]["tilt"] = float(v)
		"closed":
			curve.closed = bool(v) and curve.pts.size() >= 3
	_push("Curve " + name_, b, "field:" + name_)


func wrap_body() -> String:
	if curve == null:
		return "Model: no curve to wrap. Make one first (Model: new curve)"
	var sw := KMeshShrinkwrap.body(m)
	if sw == null:
		return "Model: " + KMeshShrinkwrap.last_error
	var b: Variant = _state()
	var n := curve.wrap(sw, WRAP_OFFSET)
	_push("Shrinkwrap the curve", b)
	return "Model: the curve's %d points wrapped onto the body (%s off the skin; the sweep follows the skin; one undo step)" % [n, Units.len(WRAP_OFFSET)]


func _target() -> KMeshShrinkwrap:
	if curve == null or is_nan(curve.wrap_offset):
		return null
	return KMeshShrinkwrap.body(m)


## THE BAKE: the sweep added to the mesh, the curve removed, ONE step
func to_mesh() -> String:
	if curve == null:
		return "Model: no curve to convert. Make one first (Model: new curve)"
	var r := curve.sweep(_target())
	if r.has("error"):
		return "Model: " + String(r["error"])
	var km: KMesh = r["mesh"]
	var cb: Variant = _state()
	var base_v: PackedVector3Array = ui.mesh.verts.duplicate()
	var base_f: Array = ui.mesh.faces.duplicate()
	var base_a: Dictionary = ui.mesh.attr_snapshot()
	ui.undo.begin(ui.mesh)
	_append(base_v, base_f, base_a, km)
	curve = null
	sel_pt = -1
	var st: Dictionary = ui.undo.commit("Curve to mesh")
	var cc := [cb, null]
	st["apply"] = func(back: bool): _restore(cc[0] if back else cc[1])
	ui._after_topo()
	_redraw()
	_fill_fields()
	return "Model: the curve is now mesh (%d verts, %d faces added; one undo step: Ctrl+Z gives the curve back)" % [km.vert_count(), km.face_count()]


# ---------------------------------------------------------------- the lathe

func _axis() -> Vector3:
	return AXES.get(String(lathe_opts["axis"]), Vector3.UP)


func _center() -> Vector3:
	if String(lathe_opts["center"]) == "cursor" and ui.pivot != null:
		return ui.view.global_transform.affine_inverse() * ui.pivot.cursor
	return Vector3.ZERO


func _opts(closed: bool) -> Dictionary:
	return {"axis": _axis(), "center": _center(), "angle": float(lathe_opts["angle"]), "steps": int(lathe_opts["steps"]),
		"screw": float(lathe_opts["screw"]), "turns": int(lathe_opts["turns"]), "closed_profile": closed}


## the profile: the selected edge chain ("sel") or the typed one ("typed") -> {"pts": PackedVector3Array, "closed"} or {}
func _profile(src: Dictionary) -> Dictionary:
	if src["from"] == "sel":
		return {"pts": src["pts"], "closed": src["closed"]}
	var p := KMeshLathe.parse(typed)
	if p.is_empty():
		return {}
	return {"pts": KMeshLathe.place(p["pts"], _axis(), _center()), "closed": p["closed"]}


func lathe(from_sel := true) -> String:
	var src := {"from": "typed"}
	if from_sel:
		var edges: Array = ui.sel.edges.keys() if ui.sel.mode == KMeshSelect.EDGE else _edges_of_verts()
		var ch := KMeshLathe.chain(edges)
		if ch.is_empty():
			return "Model: " + KMeshLathe.last_error
		var pts := PackedVector3Array()
		for v in (ch["verts"] as PackedInt32Array):
			pts.append(ui.mesh.verts[v])
		src = {"from": "sel", "pts": pts, "closed": ch["closed"]}
	var pr := _profile(src)
	if pr.is_empty():
		return "Model: " + KMeshLathe.last_error
	var km := KMeshLathe.spin(pr["pts"], _opts(pr["closed"]))
	if km == null:
		return "Model: " + KMeshLathe.last_error
	var base_v: PackedVector3Array = ui.mesh.verts.duplicate()
	var base_f: Array = ui.mesh.faces.duplicate()
	var base_a: Dictionary = ui.mesh.attr_snapshot()
	ui.undo.begin(ui.mesh)
	_append(base_v, base_f, base_a, km)
	var st: Dictionary = ui.undo.commit("Lathe")
	live = {"src": src, "step": st, "base_v": base_v, "base_f": base_f, "base_a": base_a}
	ui._after_topo()
	panel.visible = true
	_place_panel()
	return "Model: lathed %s (%d verts, %d faces; %s; one undo step, the fields stay live until the next edit)" % [
		"the selected edges" if from_sel else "the typed profile", km.vert_count(), km.face_count(), _words()]


func _words() -> String:
	var o := lathe_opts
	var s := "%d deg x %d steps around %s through the %s" % [int(o["angle"]), int(o["steps"]), o["axis"], "3D cursor" if o["center"] == "cursor" else "origin"]
	if float(o["screw"]) != 0.0:
		s += ", screw %s a turn x %d" % [Units.len(float(o["screw"])), int(o["turns"])]
	return s


## edge mode is the natural one; in vertex mode the edges between selected verts make the chain
func _edges_of_verts() -> Array:
	var out := []
	for e in ui.mesh.edges():
		if ui.sel.verts.has(e.x) and ui.sel.verts.has(e.y):
			out.append(e)
	return out


func lathe_is_live() -> bool:
	if live.is_empty() or ui.undo.steps.is_empty() or not is_same(ui.undo.steps[ui.undo.steps.size() - 1], live["step"]):
		return false
	return ui.mesh.verts == live["step"].get("new_v", PackedVector3Array())


## one lathe field changed: kept for the next lathe, and the live one rebuilt in its own step
func set_lathe(name_: String, v) -> bool:
	lathe_opts[name_] = v
	if not lathe_is_live():
		live = {}
		return false
	var pr := _profile(live["src"])
	if pr.is_empty():
		return false
	var km := KMeshLathe.spin(pr["pts"], _opts(pr["closed"]))
	if km == null:
		m._say("Model: " + KMeshLathe.last_error)
		return false
	_append(live["base_v"], live["base_f"], live["base_a"], km)
	var st: Dictionary = live["step"]
	st["new_v"] = ui.mesh.verts.duplicate()
	st["new_f"] = ui.mesh.faces.duplicate()
	st["a_new"] = ui.mesh.attr_snapshot()
	ui._after_topo()
	m._say("Model: lathe %s (%d verts; still one undo step)" % [_words(), km.vert_count()])
	return true


## base + the new piece (its "uv" corners kept; every other channel takes its default on the new items)
func _append(base_v: PackedVector3Array, base_f: Array, base_a: Dictionary, km: KMesh) -> void:
	var mesh: KMesh = ui.mesh
	var vs := base_v.duplicate()
	vs.append_array(km.verts)
	var fs := base_f.duplicate()
	var o := base_v.size()
	var nc := 0
	for f in base_f:
		nc += (f as PackedInt32Array).size()
	for f in km.faces:
		var g := PackedInt32Array(f)
		for i in g.size():
			g[i] += o
		fs.append(g)
	var a := {}
	for k in base_a:
		var r: Dictionary = base_a[k]
		a[k] = {"domain": r["domain"], "type": r["type"], "default": r["default"], "data": r["data"].duplicate()}
	if km.has_attr("uv") and not a.has("uv"):
		var z := PackedVector2Array()
		z.resize(nc)
		a["uv"] = {"domain": KMesh.AD_CORNER, "type": TYPE_VECTOR2, "default": Vector2.ZERO, "data": z}
	mesh.attrs = a
	mesh.from_arrays(vs, fs)   # the channels are fitted: the base is a prefix, the new items take the default
	if km.has_attr("uv") and mesh.attr_info("uv").get("type", -1) == TYPE_VECTOR2:
		var d: PackedVector2Array = mesh.attr_data("uv")
		var s: PackedVector2Array = km.attr_data("uv")
		for i in s.size():
			d[nc + i] = s[i]
		mesh.set_attr_data("uv", d)


# ---------------------------------------------------------------- drawing

func _redraw() -> void:
	if ui.view == null or not is_instance_valid(ui.view):
		return
	if lines == null or not is_instance_valid(lines) or lines.get_parent() != ui.view:
		lines = MeshInstance3D.new()
		lines.name = "curve_lines"
		lines.mesh = ImmediateMesh.new()
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.vertex_color_use_as_albedo = true
		mt.no_depth_test = true
		mt.use_point_size = true
		mt.point_size = 9.0
		mt.render_priority = 2
		lines.material_override = mt
		ui.view.add_child(lines)
		tube = MeshInstance3D.new()
		tube.name = "curve_tube"
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color(0.85, 0.62, 0.32)
		tube.material_override = tm
		ui.view.add_child(tube)
	var im := lines.mesh as ImmediateMesh
	im.clear_surfaces()
	if curve == null or curve.pts.size() < 2:
		tube.mesh = null
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var poly := curve.polyline(24)
	var n := poly.size()
	var segs := n if curve.closed else n - 1
	for i in segs:
		im.surface_set_color(Color(1.0, 0.85, 0.2))
		im.surface_add_vertex(poly[i])
		im.surface_add_vertex(poly[(i + 1) % n])
	for i in curve.pts.size():
		var d: Dictionary = curve.pts[i]
		for hk in ["l", "r"]:
			im.surface_set_color(Color(0.6, 0.8, 1.0))
			im.surface_add_vertex(d["p"])
			im.surface_add_vertex(d[hk])
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_POINTS)
	for i in curve.pts.size():
		var d: Dictionary = curve.pts[i]
		im.surface_set_color(Color(1.0, 0.4, 0.1) if i == sel_pt else Color(1, 1, 1))
		im.surface_add_vertex(d["p"])
		im.surface_set_color(Color(0.6, 0.8, 1.0))
		im.surface_add_vertex(d["l"])
		im.surface_add_vertex(d["r"])
	im.surface_end()
	var r := curve.sweep(_target())
	tube.mesh = (r["mesh"] as KMesh).to_array_mesh() if r.has("mesh") else null


# ---------------------------------------------------------------- the mouse

func _world(p: Vector3) -> Vector3:
	return ui.view.global_transform * p


## the point / handle under screen point sp: {"i", "k": "p" / "l" / "r"} or {}
func pick(sp: Vector2) -> Dictionary:
	if curve == null:
		return {}
	var cam: Camera3D = m.cam
	var best := PICK_PX
	var hit := {}
	for i in curve.pts.size():
		for k in ["p", "l", "r"]:
			var w := _world(curve.pts[i][k])
			if cam.is_position_behind(w):
				continue
			var d := cam.unproject_position(w).distance_to(sp)
			if d < best or (k == "p" and d <= best + 0.5 and not hit.is_empty() and hit["k"] != "p"):
				best = d
				hit = {"i": i, "k": k}
	return hit


## the mouse ray onto the plane through world point w facing the camera
func _on_plane(sp: Vector2, w: Vector3) -> Variant:
	var cam: Camera3D = m.cam
	var pl := Plane(-cam.global_transform.basis.z, w)
	return pl.intersects_ray(cam.project_ray_origin(sp), cam.project_ray_normal(sp))


func input(ev: InputEvent) -> bool:
	if curve == null or not ui.on:
		return false
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			if mb.alt_pressed and not (ui.anat != null and ui.anat.on):
				var last: Dictionary = curve.pts[curve.pts.size() - 1]
				var hit: Variant = _on_plane(mb.position, _world(last["p"]))
				if hit == null:
					return false
				add_point_at(ui.view.global_transform.affine_inverse() * (hit as Vector3))
				m._say("Model: curve point %d added (one undo step)" % curve.pts.size())
				return true
			var h := pick(mb.position)
			if h.is_empty():
				return false
			sel_pt = h["i"]
			var w := _world(curve.pts[h["i"]][h["k"]])
			var g: Variant = _on_plane(mb.position, w)
			_drag = {"i": h["i"], "k": h["k"], "w": w, "grab": (w - (g as Vector3)) if g != null else Vector3.ZERO, "before": _state()}
			_fill_fields()
			_redraw()
			return true
		if not _drag.is_empty():
			var d := _drag
			_drag = {}
			var st := _push("Move a curve %s" % ("point" if d["k"] == "p" else "handle"), d["before"])
			m._say("Model: curve point %d %s (one undo step)" % [int(d["i"]) + 1, "moved" if not st.is_empty() else "left where it was"])
			return true
		return false
	if ev is InputEventMouseMotion and not _drag.is_empty():
		var hit: Variant = _on_plane((ev as InputEventMouseMotion).position, _drag["w"])
		if hit != null:
			move_to(_drag["i"], _drag["k"], ui.view.global_transform.affine_inverse() * ((hit as Vector3) + _drag["grab"]))
		return true
	return false


## a point (its handles come along) or a handle (the opposite one turns to stay in line, its length kept) to `local`
func move_to(i: int, k: String, local: Vector3) -> void:
	var d: Dictionary = curve.pts[i]
	if k == "p":
		var dv: Vector3 = local - d["p"]
		d["p"] = local
		d["l"] = d["l"] + dv
		d["r"] = d["r"] + dv
	else:
		d[k] = local
		var o := "r" if k == "l" else "l"
		var len_o: float = (d[o] - d["p"]).length()
		var dir: Vector3 = d["p"] - local
		if dir.length_squared() > 1e-16:
			d[o] = d["p"] + dir.normalized() * len_o
	_redraw()


# ---------------------------------------------------------------- the panel

func _spin(nm: String, lo: float, hi: float, st: float, v: float, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.name = "spin_" + nm
	s.min_value = lo
	s.max_value = hi
	s.step = st
	s.value = v
	s.custom_minimum_size.x = 84
	s.value_changed.connect(func(x): if not _quiet: cb.call(x))
	_f[nm] = s
	return s


func _row(grid: GridContainer, label: String, c: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	grid.add_child(c)


func _opt(nm: String, items: Array, sel: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.name = "opt_" + nm
	for it in items:
		o.add_item(it)
	o.select(sel)
	o.item_selected.connect(func(i): if not _quiet: cb.call(i))
	_f[nm] = o
	return o


func _btn(nm: String, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = "btn_" + nm
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(func(): m._say(cb.call()))
	return b


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "curves_panel"
	panel.visible = false
	var vb := VBoxContainer.new()
	var t1 := Label.new()
	t1.text = "Spin / lathe"
	vb.add_child(t1)
	var g1 := GridContainer.new()
	g1.columns = 4
	_row(g1, "angle", _spin("angle", 1, 360, 1, 360, func(x): set_lathe("angle", float(x))))
	_row(g1, "steps", _spin("steps", 1, 256, 1, 32, func(x): set_lathe("steps", int(x))))
	_row(g1, "screw cm", _spin("screw", -100, 100, 0.1, 0, func(x): set_lathe("screw", float(x) / 100.0)))
	_row(g1, "turns", _spin("turns", 1, 64, 1, 1, func(x): set_lathe("turns", int(x))))
	_row(g1, "axis", _opt("axis", ["X", "Y", "Z"], 1, func(i): set_lathe("axis", ["X", "Y", "Z"][i])))
	_row(g1, "centre", _opt("center", ["3D cursor", "origin"], 0, func(i): set_lathe("center", ["cursor", "origin"][i])))
	vb.add_child(g1)
	var pe := LineEdit.new()
	pe.name = "edit_profile"
	pe.text = typed
	pe.tooltip_text = "a typed profile: r,y pairs in cm (radius from the axis, height along it); add the word closed to close it"
	pe.text_changed.connect(func(s): typed = s)
	vb.add_child(pe)
	var h1 := HBoxContainer.new()
	h1.add_child(_btn("lathe", "Lathe selection", "revolve the selected edge chain (one undo step; the fields stay live)", func(): return lathe(true)))
	h1.add_child(_btn("lathe_typed", "Lathe typed", "revolve the typed profile", func(): return lathe(false)))
	vb.add_child(h1)
	vb.add_child(HSeparator.new())
	var t2 := Label.new()
	t2.text = "Curve (drag points / handles, Alt+click adds)"
	vb.add_child(t2)
	var h2 := HBoxContainer.new()
	h2.add_child(_btn("curve_new", "New curve", "a bezier curve beside the mesh", func(): return new_curve("s")))
	h2.add_child(_btn("curve_circle", "New circle", "a closed bezier circle", func(): return new_curve("circle")))
	vb.add_child(h2)
	var g2 := GridContainer.new()
	g2.columns = 4
	_row(g2, "profile", _opt("profile", ["circle", "strap"], 0, func(i): set_field("profile", i)))
	_row(g2, "sides", _spin("sides", 3, 64, 1, 12, func(x): set_field("sides", int(x))))
	_row(g2, "radius cm", _spin("radius", 0.05, 50, 0.05, 1, func(x): set_field("radius", float(x) / 100.0)))
	_row(g2, "width cm", _spin("width", 0.1, 50, 0.1, 4, func(x): set_field("width", float(x) / 100.0)))
	_row(g2, "thick cm", _spin("thickness", 0.05, 10, 0.05, 0.4, func(x): set_field("thickness", float(x) / 100.0)))
	_row(g2, "taper end", _spin("taper", 0, 4, 0.05, 1, func(x): set_field("taper", float(x))))
	_row(g2, "tilt deg", _spin("tilt", -720, 720, 1, 0, func(x): set_field("tilt", float(x))))
	var cl := CheckBox.new()
	cl.name = "chk_closed"
	cl.toggled.connect(func(on_): if not _quiet: set_field("closed", on_))
	_f["closed"] = cl
	_row(g2, "closed", cl)
	vb.add_child(g2)
	var h3 := HBoxContainer.new()
	h3.add_child(_btn("curve_wrap", "Wrap on body", "shrinkwrap the curve onto the fighter's skin, 3 mm off (one undo step)", wrap_body))
	h3.add_child(_btn("curve_to_mesh", "Convert to mesh", "the sweep becomes mesh, one undo step", to_mesh))
	vb.add_child(h3)
	panel.add_child(vb)
	m.ui_root.add_child(panel)


func _fill_fields() -> void:
	if curve == null:
		return
	_quiet = true
	(_f["profile"] as OptionButton).select(KMeshCurve.PROFILES.find(curve.profile))
	(_f["sides"] as SpinBox).value = curve.sides
	(_f["radius"] as SpinBox).value = curve.radius * 100.0
	(_f["width"] as SpinBox).value = curve.width * 100.0
	(_f["thickness"] as SpinBox).value = curve.height * 100.0
	(_f["taper"] as SpinBox).value = curve.taper[curve.taper.size() - 1].y if not curve.taper.is_empty() else 1.0
	(_f["tilt"] as SpinBox).value = float(curve.pts[sel_pt]["tilt"]) if sel_pt >= 0 and sel_pt < curve.pts.size() else 0.0
	(_f["closed"] as CheckBox).button_pressed = curve.closed
	_quiet = false


## beside the Add primitive panel (left edge), kept inside the window
func _place_panel() -> void:
	panel.reset_size()
	var win := panel.get_viewport_rect().size
	var x := 12.0
	if ui.prim_panel != null and ui.prim_panel.visible:
		x = ui.prim_panel.get_global_rect().end.x + 8.0
	var sz := panel.get_combined_minimum_size()
	x = clampf(x, 0.0, maxf(0.0, win.x - sz.x))
	panel.position = Vector2(x, clampf(win.y - sz.y - 56.0, 0.0, maxf(0.0, win.y - sz.y)))


func toggle() -> String:
	panel.visible = not panel.visible
	if panel.visible:
		_place_panel()
	return "Model: the Spin / curves panel %s" % ("on: lathe the selected edges or a typed profile; New curve for a belt or a cable" if panel.visible else "off")


## mesh_tools "op:" names
static func op(name_: String, main: Node) -> String:
	var c := of(main.kmed)
	var said := ""
	match name_:
		"curves":
			said = c.toggle()
		"curve_add":
			said = c.new_curve("s")
		"curve_circle":
			said = c.new_curve("circle")
		"lathe":
			said = c.lathe(true)
		"lathe_typed":
			said = c.lathe(false)
		"curve_wrap":
			said = c.wrap_body()
		"curve_to_mesh":
			said = c.to_mesh()
	main._say(said)
	return said
