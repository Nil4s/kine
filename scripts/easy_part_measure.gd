class_name EasyMeasure
extends RefCounted
## s055 (Friday plan 55 + 56): the Measure chip in Easy Part's view column. Measure mode: two clicks on the part give the distance between the
## two points ("42.0 mm"), snapped to a corner, then an edge, then the face under the pointer; two clicks INSIDE two faces give the angle between
## them ("90.0 deg"; parallel faces say how far apart they are). A line and a label in screen-size text are drawn over the view.
## A view tool only: nothing goes in the record and nothing in the undo list. Esc (or the chip again) leaves the mode and clears the readouts.
## The part is read from the shown mesh (PartUI.part_mesh), in millimetres, so it works on whatever the part is.

const COL := Color("#ffc233")
const TIP_PX := 12.0        # a corner / an edge within this many pixels of the click wins over the face under it
const FLAT := 0.9995        # two triangles whose normals agree this closely are one flat face (no edge between them)
const SEE_TOL := 0.8        # mm: a point this close to the first surface along the eye ray counts as seen
const KEEP := 6             # readouts kept on the view

var ep                       # the EasyPart
var on := false
var out: Array = []          # {"kind": "dist" | "angle", "a", "b" (mm), "v" (mm or degrees), "txt", "sig"}
var pend: Dictionary = {}    # the first click, waiting for the second
var chip_btn: Button
var ov: Control
var down := Vector2(-1, -1)

var _key := ""
var _tris: Array = []        # [a, b, c, n] in mm
var _verts: Array = []       # corner points (mm): ends of the edges that are really edges
var _edges: Array = []       # [a, b] in mm


func _init(e) -> void:
	ep = e


## the chip (for the view column) and the overlay the readouts draw on
func build(root: Control, col: Control) -> void:
	chip_btn = Button.new()
	chip_btn.name = "easypart_view_measure"
	chip_btn.text = "Measure"
	chip_btn.icon = Icons.sized("part_measure", 16)
	chip_btn.expand_icon = false
	chip_btn.toggle_mode = true
	chip_btn.tooltip_text = "Click two spots on the part to see how far apart they are. Click inside two faces to see the angle between them. View only: no undo step"
	chip_btn.focus_mode = Control.FOCUS_NONE
	chip_btn.custom_minimum_size = Vector2(0, 30)
	chip_btn.add_theme_font_size_override("font_size", 13)
	chip_btn.toggled.connect(set_on)
	col.add_child(chip_btn)
	ov = Control.new()
	ov.name = "easypart_measure_overlay"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.visible = false
	ov.draw.connect(_draw)
	root.add_child(ov)


func set_on(v: bool) -> void:
	if v == on:
		return
	on = v
	chip_btn.set_pressed_no_signal(v)
	pend = {}
	down = Vector2(-1, -1)
	if v:
		ep.armed = ""
		ep._say("Measure: click two spots on the part for the distance, or inside two faces for the angle. Esc leaves Measure (no undo step)")
	else:
		out = []
		ep._say("Measure off (no undo step)")
	ov.queue_redraw()


## every frame: leaves with Easy Part, forgets readouts of a part that has changed, follows the camera
func sync() -> void:
	if ov == null:
		return
	if on and not ep.active():
		set_on(false)
	var sig := String(ep.pu._rec_sig)
	if not out.is_empty() and String(out[0]["sig"]) != sig:
		out = []
		pend = {}
	ov.visible = ep.active() and (on or not out.is_empty())
	if ov.visible:
		ov.queue_redraw()


## a left button event while Measure is on. The camera keeps every press and release; a press and release within a few pixels is a click
func mouse(p: Vector2, pressed: bool) -> bool:
	if pressed:
		down = p
		return false
	if down.x >= 0.0 and p.distance_to(down) < 6.0:
		click(p)
	down = Vector2(-1, -1)
	return false


func click(p: Vector2) -> void:
	var s := snap(p)
	if s.is_empty():
		ep._say("Measure: nothing there. Click on the part")
		return
	s["sig"] = String(ep.pu._rec_sig)
	if pend.is_empty():
		pend = s
		ep._say("Measure: first spot set. Click the second spot" + (" (inside another face for the angle)" if s["k"] == "face" else ""))
		ov.queue_redraw()
		return
	var a: Dictionary = pend
	pend = {}
	var pa: Vector3 = a["at"]
	var pb: Vector3 = s["at"]
	var r := {"a": pa, "b": pb, "sig": s["sig"]}
	if a["k"] == "face" and s["k"] == "face":
		var n1: Vector3 = a["n"]
		var n2: Vector3 = s["n"]
		var ang := rad_to_deg(acos(clampf(n1.dot(n2), -1.0, 1.0)))
		r["kind"] = "angle"
		r["v"] = ang
		if ang < 0.05 or ang > 179.95:
			var gap := absf(n1.dot(pb - pa))
			r["txt"] = "Same flat face" if gap < 0.05 else "Parallel, %.1f mm apart" % gap
			r["gap"] = gap
		else:
			r["txt"] = "%.1f deg" % ang
	else:
		var d := pa.distance_to(pb)
		r["kind"] = "dist"
		r["v"] = d
		r["txt"] = "%.1f mm" % d
	out.append(r)
	while out.size() > KEEP:
		out.pop_front()
	ep._say("Measure: " + String(r["txt"]) + ". Click again to measure another")
	ov.queue_redraw()


# ---------------------------------------------------------------- what is under a click

## {"k": "vertex" | "edge" | "face", "at": mm point, "n": unit normal facing the eye (faces)}, or {} when nothing is there
func snap(p: Vector2) -> Dictionary:
	if not _geo():
		return {}
	var cam: Camera3D = ep.m.cam
	var cand: Array = []
	for v in _verts:
		var w: Vector3 = (v as Vector3) * 0.001
		if cam.is_position_behind(w):
			continue
		var d := p.distance_to(cam.unproject_position(w))
		if d <= TIP_PX:
			cand.append([d, v])
	cand.sort_custom(func(x, y): return x[0] < y[0])
	for c in cand:
		if _seen(c[1]):
			return {"k": "vertex", "at": c[1]}
	cand = []
	for e in _edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		if cam.is_position_behind(a * 0.001) or cam.is_position_behind(b * 0.001):
			continue
		var pa := cam.unproject_position(a * 0.001)
		var pb := cam.unproject_position(b * 0.001)
		var q := Geometry2D.get_closest_point_to_segment(p, pa, pb)
		var d := p.distance_to(q)
		if d <= TIP_PX:
			var t := 0.0 if pa.distance_to(pb) < 1e-6 else clampf(pa.distance_to(q) / pa.distance_to(pb), 0.0, 1.0)
			cand.append([d, a.lerp(b, t)])
	cand.sort_custom(func(x, y): return x[0] < y[0])
	for c in cand:
		if _seen(c[1]):
			return {"k": "edge", "at": c[1]}
	var ro: Vector3 = cam.project_ray_origin(p) * 1000.0
	var rd: Vector3 = cam.project_ray_normal(p)
	var h := _first(ro, rd)
	if h.is_empty():
		return {}
	var n: Vector3 = h["n"]
	if n.dot(rd) > 0.0:
		n = -n
	return {"k": "face", "at": h["at"], "n": n}


## the nearest triangle on the ray (mm): {"t": distance, "at", "n"} or {}
func _first(ro: Vector3, rd: Vector3) -> Dictionary:
	var best := {}
	var bt := INF
	for t in _tris:
		var h: Variant = Geometry3D.ray_intersects_triangle(ro, rd, t[0], t[1], t[2])
		if h != null:
			var dd := ro.distance_to(h as Vector3)
			if dd < bt:
				bt = dd
				best = {"t": dd, "at": h, "n": t[3]}
	return best


## a point (mm) on the surface that the eye can see: nothing nearer along the ray from the eye
func _seen(pt: Vector3) -> bool:
	var ro: Vector3 = ep.m.cam.global_position * 1000.0
	var rd := (pt - ro).normalized()
	var h := _first(ro, rd)
	return h.is_empty() or float(h["t"]) >= ro.distance_to(pt) - SEE_TOL


## the shown part as triangles, corners and edges in mm (rebuilt when the part or its mesh changes)
func _geo() -> bool:
	var pm: MeshInstance3D = ep.pu.part_mesh
	if pm == null or pm.mesh == null or pm.mesh.get_surface_count() == 0:
		return false
	var key := "%d|%d|%s" % [pm.mesh.get_instance_id(), String(ep.pu._rec_sig).hash(), str(pm.global_transform)]
	if key == _key:
		return true
	_key = key
	_tris = []
	_verts = []
	_edges = []
	var xf: Transform3D = pm.global_transform
	var ids := {}
	var pts: Array = []
	var emap := {}
	for s in pm.mesh.get_surface_count():
		var arr: Array = pm.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: Variant = arr[Mesh.ARRAY_INDEX]
		var n := vs.size() if ix == null else (ix as PackedInt32Array).size()
		for k in range(0, n - 2, 3):
			var tri: Array = []
			for j in 3:
				var vi: int = k + j if ix == null else (ix as PackedInt32Array)[k + j]
				tri.append(xf * vs[vi] * 1000.0)
			var nn: Vector3 = ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3))
			if nn.length() < 1e-9:
				continue
			nn = nn.normalized()
			_tris.append([tri[0], tri[1], tri[2], nn])
			var vid: Array = []
			for j in 3:
				var q := Vector3i(roundi((tri[j] as Vector3).x * 1000.0), roundi((tri[j] as Vector3).y * 1000.0), roundi((tri[j] as Vector3).z * 1000.0))
				if not ids.has(q):
					ids[q] = pts.size()
					pts.append(tri[j])
				vid.append(ids[q])
			for j in 3:
				var i0: int = vid[j]
				var i1: int = vid[(j + 1) % 3]
				if i0 == i1:
					continue
				var ek := Vector2i(mini(i0, i1), maxi(i0, i1))
				if not emap.has(ek):
					emap[ek] = []
				(emap[ek] as Array).append(nn)
	var used := {}
	for ek in emap:
		var ns: Array = emap[ek]
		var feature := ns.size() == 1
		for q in ns:
			if (q as Vector3).dot(ns[0]) < FLAT:
				feature = true
		if feature:
			_edges.append([pts[(ek as Vector2i).x], pts[(ek as Vector2i).y]])
			used[(ek as Vector2i).x] = true
			used[(ek as Vector2i).y] = true
	for i in used:
		_verts.append(pts[i])
	return not _tris.is_empty()


# ---------------------------------------------------------------- the readouts

func _draw() -> void:
	var cam: Camera3D = ep.m.cam
	if cam == null:
		return
	for r in out:
		var a: Vector3 = (r["a"] as Vector3) * 0.001
		var b: Vector3 = (r["b"] as Vector3) * 0.001
		if cam.is_position_behind(a) or cam.is_position_behind(b):
			continue
		var sa := cam.unproject_position(a)
		var sb := cam.unproject_position(b)
		ov.draw_line(sa, sb, COL, 3.0, true)
		ov.draw_circle(sa, 5.0, COL)
		ov.draw_circle(sb, 5.0, COL)
		_pill(String(r["txt"]), (sa + sb) * 0.5 + Vector2(0, -20))
	if not pend.is_empty():
		var w: Vector3 = (pend["at"] as Vector3) * 0.001
		if not cam.is_position_behind(w):
			var sp := cam.unproject_position(w)
			ov.draw_circle(sp, 7.0, COL)
			ov.draw_arc(sp, 11.0, 0.0, TAU, 24, COL, 2.0)


## a label in screen-size text (15 px whatever the zoom), kept inside the window
func _pill(txt: String, c: Vector2) -> void:
	var f: Font = ThemeDB.fallback_font
	var fs := 15
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(c - Vector2(sz.x * 0.5 + 8.0, sz.y * 0.5 + 4.0), sz + Vector2(16.0, 8.0))
	var vp := ov.size
	r.position.x = clampf(r.position.x, 2.0, maxf(2.0, vp.x - r.size.x - 2.0))
	r.position.y = clampf(r.position.y, 2.0, maxf(2.0, vp.y - r.size.y - 2.0))
	ov.draw_rect(r, Color(0.06, 0.07, 0.1, 0.94))
	ov.draw_rect(r, COL, false, 1.5)
	ov.draw_string(f, r.position + Vector2(8.0, 4.0 + f.get_ascent(fs)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
