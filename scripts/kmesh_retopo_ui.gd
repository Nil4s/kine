class_name KMeshRetopoUI
extends RefCounted
## I11: the RETOPO mode of the model preview (Q). Draw strokes on the mesh with the left button; where they meet they cut the
## surface into patches, each closed region of 2 to 6 sides is filled with quads at once (KMeshRetopoNet + KineRetopoNative; the
## method is Takayama, Panozzo, Sorkine-Hornung, Sorkine-Hornung 2013, "Sketch-Based Generation and Editing of Quad Meshes", ACM TOG
## 32(4)). Keys while the mode is on (KMeshEditUI.input hands every event here first):
##   Q  in / out                       left drag  draw a stroke on the surface (snaps to it; a stroke end near another joins it)
##   wheel over a side  its edge count +-1 (opposite sides of a 4-sided patch follow, so neighbours stay consistent; the
##                      patches that cannot be filled with the counts are drawn red and say why)
##   Delete / Backspace / X  with the pointer over a stroke: delete it (the patches either side merge and are filled again)
##   Enter  Bake: the quads replace the mesh in ONE undo step (Ctrl+Z gives the source back), with the heat map on
##   Esc  leave, nothing changed.        Right / middle mouse still orbit and pan.
## The strokes, the patch quads and the counts are drawn on the preview's overlay.

const PICK_PX := 14.0

var ui   # KMeshEditUI
var net: KMeshRetopoNet
var on := false
var drawing := false
var cur := PackedVector3Array()
var hover_arc := -1
var hover_stroke := -1
var mouse := Vector2.ZERO
var panel: PanelContainer
var status: Label
var _mesh: KMesh
var last_said := ""


static func handle(u, ev: InputEvent) -> bool:
	var t: KMeshRetopoUI = u.get_meta("kretopo") if u.has_meta("kretopo") else null
	if t == null:
		t = KMeshRetopoUI.new()
		t.ui = u
		u.set_meta("kretopo", t)
		u._ov.draw.connect(t._draw)
	if t.on and t._mesh != u.mesh:
		t.stop()
	return t.input(ev)


static func of(u) -> KMeshRetopoUI:
	return u.get_meta("kretopo") if u.has_meta("kretopo") else null


## MeshTools op:retopo
static func toggle(m) -> String:
	var u = m.kmed
	if u == null or not u.on:
		return "Model: open a mesh in the model preview first, then Retopo (Q)"
	var t := of(u)
	if t == null:
		handle(u, InputEventKey.new())
		t = of(u)
	if t.on:
		t.stop()
	else:
		t.start()
	return t.last_said


func _say(s: String) -> void:
	last_said = "Model: " + s
	ui.m._say(last_said)


func start() -> void:
	if on or ui.mesh == null or ui.mesh.verts.size() < 4:
		return
	_mesh = ui.mesh
	net = KMeshRetopoNet.new()
	net.setup(ui.mesh)
	on = true
	_build_panel()
	(panel.find_child("edge_len", true, false) as SpinBox).set_value_no_signal(net.edge_len * 100.0)
	panel.visible = true
	_refresh()
	_say("Retopo: drag on the mesh to draw strokes; where they meet they make patches that fill with quads. Wheel over a side = its edge count, Delete over a stroke removes it, Enter bakes, Esc leaves%s" % ("" if net.nat != null else " (the native solver is not built: patches are not fitted to the surface)"))
	ui._ov.queue_redraw()


func stop() -> void:
	if not on:
		return
	on = false
	drawing = false
	net = null
	if panel != null:
		panel.visible = false
	ui._ov.queue_redraw()
	_say("left Retopo")


func _build_panel() -> void:
	if panel != null:
		return
	var m = ui.m
	panel = PanelContainer.new()
	panel.name = "retopo_panel"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Tok.c("float"), 0.92)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(m._label("Retopo (Q)", 14, "text"))
	status = m._label("", 13, "text:0.8")
	status.name = "status"
	vb.add_child(status)
	var row := HBoxContainer.new()
	var lb: Label = m._label("Edge length (cm)", 13, "text:0.8")
	row.add_child(lb)
	var sp := SpinBox.new()
	sp.name = "edge_len"
	sp.min_value = 0.2
	sp.max_value = 100.0
	sp.step = 0.1
	sp.value = 5.0
	sp.value_changed.connect(_on_edge_len)
	row.add_child(sp)
	vb.add_child(row)
	var bk := Button.new()
	bk.name = "bake"
	bk.text = "Bake to a new mesh (Enter)"
	bk.pressed.connect(bake)
	vb.add_child(bk)
	var fx := Button.new()
	fx.name = "autofix"
	fx.text = "Auto counts"
	fx.tooltip_text = "pick edge counts again for every side you have not set, so every patch can be filled"
	fx.pressed.connect(auto_counts)
	vb.add_child(fx)
	var cl := Button.new()
	cl.name = "clear"
	cl.text = "Clear strokes"
	cl.pressed.connect(clear)
	vb.add_child(cl)
	m.ui_root.add_child(panel)
	var r: Rect2 = m.nav_clear_rect()
	panel.position = Vector2(r.position.x + 12.0, r.position.y + 12.0)


func _on_edge_len(cm: float) -> void:
	if net == null:
		return
	net.edge_len = cm * 0.01
	_refresh()


func _refresh() -> void:
	if status == null or net == null:
		return
	var s := net.stats()
	var t := "%d strokes, %d patches" % [s["strokes"], s["patches"]]
	if int(s["unsolved"]) > 0:
		t += ", %d red (counts do not fit)" % s["unsolved"]
	var skipped: Array = net.skipped_regions()
	if not skipped.is_empty():
		t += ", %d skipped (%s)" % [skipped.size(), String(skipped[0]["reason"])]
		var lines: PackedStringArray = []
		for r in skipped:
			lines.append("Region %d: %s" % [int(r["patch"]) + 1, String(r["reason"])])
		status.tooltip_text = "\n".join(lines)
	else:
		status.tooltip_text = ""
	status.text = t
	ui._ov.queue_redraw()


func clear() -> void:
	if net == null:
		return
	for id in net.strokes.keys():
		net.strokes.erase(id)
	net.rebuild()
	_refresh()
	_say("Retopo: all strokes cleared")


func auto_counts() -> void:
	if net == null:
		return
	for a in net.arcs:
		a["pinned"] = false
		a["count"] = maxi(1, int(round(a["len"] / net.edge_len)))
	net.auto_fix()
	net._layout_and_solve()
	_refresh()
	_say("Retopo: edge counts picked again (%s)" % status.text)


## replace the mesh by the baked quads, one undo step; the heat map shows the result
func bake() -> String:
	if net == null:
		return ""
	var k := net.bake()
	if k.faces.is_empty():
		_say("Retopo: nothing to bake yet: draw strokes that close at least one region of 2 to 6 sides")
		return last_said
	var nq := k.faces.size()
	ui.undo.begin(ui.mesh)
	for an in ui.mesh.list_attrs():
		ui.mesh.remove_attr(an)
	ui.mesh.from_arrays(k.verts, k.faces)
	ui.undo.commit("Retopo bake")
	ui.sel.clear()
	ui.view.mark_dirty()
	if not ui.view.show_heat:
		ui.topo("heat")
	stop()
	_say("Retopo: baked %d quads (%d verts). Ctrl+Z brings the source back" % [nq, k.verts.size()])
	return last_said


# ------------------------------------------------------------------ input
func _local(world: Vector3) -> Vector3:
	return ui.view.global_transform.affine_inverse() * world


func _hit(p: Vector2) -> Variant:
	var cam: Camera3D = ui.m.cam
	var r: Array = ui.view.ray_at(cam, p)
	var h: Dictionary = ui.view.ray_face(r[0], r[1])
	if h.is_empty():
		return null
	return _local(h["point"])


func input(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed or k.echo:
			return on and drawing
		var kc := k.keycode & KEY_CODE_MASK
		var mod := k.ctrl_pressed or k.alt_pressed or k.shift_pressed or k.meta_pressed
		if kc == KEY_Q and not mod:
			if on:
				stop()
			else:
				start()
			return true
		if not on:
			return false
		if kc == KEY_ESCAPE:
			if drawing:
				drawing = false
				cur = PackedVector3Array()
				ui._ov.queue_redraw()
			else:
				stop()
			return true
		if kc == KEY_ENTER or kc == KEY_KP_ENTER:
			bake()
			return true
		if kc in [KEY_DELETE, KEY_BACKSPACE, KEY_X] and not mod:
			if hover_stroke >= 0:
				var id := hover_stroke
				hover_stroke = -1
				hover_arc = -1
				net.delete_stroke(id)
				_refresh()
				_say("Retopo: stroke deleted; %s" % status.text)
			return true
		return false
	if not on:
		return false
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var h: Variant = _hit(mb.position)
				if h == null:
					return false
				drawing = true
				cur = PackedVector3Array([h])
				ui._ov.queue_redraw()
				return true
			if drawing:
				drawing = false
				var pts := cur
				cur = PackedVector3Array()
				if pts.size() >= 2:
					var id := net.add_stroke(pts)
					_refresh()
					_say("Retopo: %s" % (status.text if id >= 0 else "that stroke was too short"))
				ui._ov.queue_redraw()
				return true
			return false
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_pick(mb.position)
			if hover_arc >= 0:
				var d := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				var n: int = net.arcs[hover_arc]["count"]
				var solved := net.set_count(hover_arc, n + d, true)
				_refresh()
				_say("Retopo: that side has %d edges (%d patches re-solved); %s" % [net.arcs[hover_arc]["count"], solved.size(), status.text])
				return true
		return false
	if ev is InputEventMouseMotion:
		mouse = (ev as InputEventMouseMotion).position
		if drawing:
			var h2: Variant = _hit(mouse)
			if h2 != null and (cur.is_empty() or (h2 as Vector3).distance_to(cur[cur.size() - 1]) > net.hs * 0.8):
				cur.append(h2)
			ui._ov.queue_redraw()
		else:
			_pick(mouse)
		return false
	return false


func _scr(p: Vector3) -> Variant:
	return ui.view._screen(ui.m.cam, ui.view.global_transform * p)


func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	return ui.view._seg_dist(p, a, b)


## the arc and the stroke under the pointer
func _pick(p: Vector2) -> void:
	var ba := -1
	var bd := PICK_PX
	for ai in net.arcs.size():
		var pl: PackedVector3Array = net.arcs[ai]["pts"]
		var prev: Variant = null
		for i in range(0, pl.size(), 2):
			var s: Variant = _scr(pl[i])
			if s != null and prev != null:
				var d := _seg_d(p, prev, s)
				if d < bd:
					bd = d
					ba = ai
			prev = s
	var bs := -1
	var bd2 := PICK_PX
	for id in net.strokes:
		var pl2: PackedVector3Array = net.strokes[id]
		var prev2: Variant = null
		for i in range(0, pl2.size(), 2):
			var s2: Variant = _scr(pl2[i])
			if s2 != null and prev2 != null:
				var d2 := _seg_d(p, prev2, s2)
				if d2 < bd2:
					bd2 = d2
					bs = id
			prev2 = s2
	if ba != hover_arc or bs != hover_stroke:
		hover_arc = ba
		hover_stroke = bs
		ui._ov.queue_redraw()


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	if not on or net == null or not ui.on:
		return
	var ov: Control = ui._ov
	var cam: Camera3D = ui.m.cam
	var xf: Transform3D = ui.view.global_transform
	var eye: Vector3 = cam.global_position
	var good := Color(0.25, 0.95, 0.65, 0.85)
	var bad := Color(1.0, 0.25, 0.2, 0.95)
	for p in net.patches:
		if not p["valid"]:
			continue
		if p["ok"]:
			var pv: PackedFloat64Array = p["verts"]
			var qv: PackedInt32Array = p["quads"]
			var sc := PackedVector2Array()
			var vis := PackedByteArray()
			var nv := pv.size() / 3
			sc.resize(nv)
			vis.resize(nv)
			for i in nv:
				var w := xf * Vector3(pv[i * 3], pv[i * 3 + 1], pv[i * 3 + 2])
				if cam.is_position_behind(w):
					continue
				sc[i] = cam.unproject_position(w)
				vis[i] = 1
			for q in qv.size() / 4:
				var a := qv[q * 4]
				var b := qv[q * 4 + 1]
				var c := qv[q * 4 + 2]
				var d := qv[q * 4 + 3]
				if vis[a] == 0 or vis[b] == 0 or vis[c] == 0 or vis[d] == 0:
					continue
				var pa := xf * Vector3(pv[a * 3], pv[a * 3 + 1], pv[a * 3 + 2])
				var pb := xf * Vector3(pv[b * 3], pv[b * 3 + 1], pv[b * 3 + 2])
				var pc := xf * Vector3(pv[c * 3], pv[c * 3 + 1], pv[c * 3 + 2])
				if (pb - pa).cross(pc - pa).dot(eye - pa) <= 0.0:
					continue   # facing away
				ov.draw_polyline(PackedVector2Array([sc[a], sc[b], sc[c], sc[d], sc[a]]), good, 1.0)
		else:
			var ring: PackedInt32Array = p["ring"]
			for h in ring:
				var pl: PackedVector3Array = net.arcs[h >> 1]["pts"]
				var prev: Variant = null
				for pt in pl:
					var s: Variant = _scr(pt)
					if s != null and prev != null:
						ov.draw_line(prev, s, bad, 3.0)
					prev = s
	var font := ThemeDB.fallback_font
	for ai in net.arcs.size():
		var a: Dictionary = net.arcs[ai]
		var pl2: PackedVector3Array = a["pts"]
		var hov := ai == hover_arc
		var col := Tok.c("pick_hover") if hov else Color(1.0, 0.85, 0.2, 0.95)
		var prev2: Variant = null
		for pt in pl2:
			var s2: Variant = _scr(pt)
			if s2 != null and prev2 != null:
				ov.draw_line(prev2, s2, col, 3.0 if hov else 2.0)
			prev2 = s2
		var mid: Variant = _scr(pl2[pl2.size() / 2])
		if mid != null:
			ov.draw_string(font, mid + Vector2(4, -4), str(a["count"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE if a["pinned"] else Color(1, 1, 1, 0.75))
	if drawing and cur.size() > 1:
		var prev3: Variant = null
		for pt in cur:
			var s3: Variant = _scr(pt)
			if s3 != null and prev3 != null:
				ov.draw_line(prev3, s3, Color(1.0, 0.5, 0.1), 2.0)
			prev3 = s3
	if hover_stroke >= 0 and hover_arc < 0 and net.strokes.has(hover_stroke):
		ov.draw_circle(mouse, 4.0, bad)
