class_name JointAxes
extends RefCounted
## C24 (#317, #348): a second turning axis on a hinge frame, and a pivot that lands on a hidden tip put on the nearest visible feature.
## Both are opt-in fields on a hinge feature; a hinge without them replays and sweeps exactly as before.
## SECOND AXIS: "axis2": [x, y, z] (any direction not along "axis"), "track2": [[t_s, deg], ...] (a Curves channel like "track"), "limit2": 0..90 deg
## (default 90 = no stop). The second axis is fixed in the moving part (it turns with the part), so the pose at the angles (a, b) is
## R(axis, a) * R(axis2, b): the part turns b about axis2 first, then the whole thing turns a about axis. Each axis has its own limit.
## AUTO PLACE: {"autoplace": true} on a hinge, or auto_place() on its own: when the pivot "o" is not on the body's surface (a chamfered tip
## leaves the box corner in the air), it moves to the nearest VISIBLE feature of that body: a hole's centre, the midpoint of an edge, or the
## centre of a face. The answer says which one, how far it moved and the words for it (the choice is shown).
const KCad := preload("res://scripts/kcad.gd")
const HIDDEN_MM := 0.5   # the pivot is "on the body" when a triangle of it is within this many mm
const MM := 0.001


static func has2(f: Dictionary) -> bool:
	if not (f.get("axis2") is Array) or (f["axis2"] as Array).size() != 3 or not (f.get("axis") is Array):
		return false
	return axis2(f).length() > 0.5 and absf(axis2(f).dot(Part._axis(f))) < 0.999


static func axis2(f: Dictionary) -> Vector3:
	var a: Array = f.get("axis2", [0, 0, 0])
	return Vector3(float(a[0]), float(a[1]), float(a[2])).normalized()


static func limit2(f: Dictionary) -> float:
	return clampf(float(f.get("limit2", 90.0)), 0.0, 90.0)


## the second angle at time t (the curve clamped to its own limit); 0 when the hinge has no second axis
static func deg2_at(f: Dictionary, t: float) -> float:
	if not has2(f) or (f.get("track2", []) as Array).is_empty():
		return 0.0
	return clampf(float(Curves.eval(f["track2"], t, Curves.mode_of(f))), -limit2(f), limit2(f))


## the part id turned b about axis2, then a about axis, both through the pivot (metres, radians); a new shape the caller releases
static func swing2(id: int, pivot: Vector3, f: Dictionary, a: float, b: float) -> int:
	var m0 := Part._swing(id, pivot, axis2(f), b)
	if m0 == 0:
		return 0
	var m1 := Part._swing(m0, pivot, Part._axis(f), a)
	KCad.release(m0)
	return m1


## the pose as a basis (for the closed form in tests and for any view): R(axis, a) * R(axis2, b)
static func basis_of(f: Dictionary, a: float, b: float) -> Basis:
	return Basis(Part._axis(f), a) * Basis(axis2(f), b)


# ---------------------------------------------------------------- auto place

static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))   # 0.01 mm


static func _ekey(p: Vector3, q: Vector3) -> String:
	var ka := _key(p)
	var kb := _key(q)
	var swap := ka.x > kb.x or (ka.x == kb.x and (ka.y > kb.y or (ka.y == kb.y and ka.z > kb.z)))
	return "%s|%s" % [str(kb if swap else ka), str(ka if swap else kb)]


## the visible features of a triangle soup (metres): [{"kind": "hole"|"edge"|"face", "p": Vector3}]
static func features_of(tris: PackedVector3Array) -> Array:
	var groups := {}   # plane key -> {"n", "tris": [i...], "area", "cen"}
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var cr := (tris[i + 1] - a).cross(tris[i + 2] - a)
		var ar := cr.length() * 0.5
		if ar < 1e-12:
			continue
		var n := cr.normalized()
		var d := n.dot(a)
		var k := Vector4i(roundi(n.x * 100), roundi(n.y * 100), roundi(n.z * 100), roundi(d * 1e4))   # 0.1 mm planes
		if not groups.has(k):
			groups[k] = {"n": n, "tris": [], "area": 0.0, "cen": Vector3.ZERO}
		var g: Dictionary = groups[k]
		g["tris"].append(i)
		g["area"] = float(g["area"]) + ar
		g["cen"] = (g["cen"] as Vector3) + (a + tris[i + 1] + tris[i + 2]) / 3.0 * ar
	var out: Array = []
	var edge_groups := {}   # edge key -> [[group index, p, q], ...]
	var gl: Array = groups.values()
	for gi in gl.size():
		var g: Dictionary = gl[gi]
		if float(g["area"]) < 1e-8:
			continue
		out.append({"kind": "face", "p": (g["cen"] as Vector3) / float(g["area"])})
		var cnt := {}
		for ti in g["tris"]:
			for e in 3:
				var p := tris[ti + e]
				var q := tris[ti + (e + 1) % 3]
				var ek := _ekey(p, q)
				if not cnt.has(ek):
					cnt[ek] = [0, p, q]
				cnt[ek][0] += 1
		var bnd: Array = []
		for ek in cnt:
			if int(cnt[ek][0]) == 1:
				bnd.append([cnt[ek][1], cnt[ek][2]])
				var es: Array = edge_groups.get(ek, [])
				es.append([gi, cnt[ek][1], cnt[ek][2]])
				edge_groups[ek] = es
		for lp in _loops(bnd):
			if lp.size() >= 8:
				var c := Vector3.ZERO
				for v in lp:
					c += v
				c /= float(lp.size())
				var r := 0.0
				for v in lp:
					r += c.distance_to(v)
				r /= float(lp.size())
				var spread := 0.0
				for v in lp:
					spread = maxf(spread, absf(c.distance_to(v) - r))
				if r > 1e-4 and spread < 0.02 * r:
					out.append({"kind": "hole", "p": c, "r": r})
	# an edge: a boundary edge shared by two different plane groups. The midpoint of its whole run per group pair.
	var runs := {}
	for ek in edge_groups:
		var es: Array = edge_groups[ek]
		if es.size() == 2 and int(es[0][0]) != int(es[1][0]):
			var rk := "%d,%d" % [mini(int(es[0][0]), int(es[1][0])), maxi(int(es[0][0]), int(es[1][0]))]
			var pts: Array = runs.get(rk, [])
			pts.append(es[0][1])
			pts.append(es[0][2])
			runs[rk] = pts
	for rk in runs:
		var pts: Array = runs[rk]
		var best := 0.0
		var pa: Vector3 = pts[0]
		var pb: Vector3 = pts[0]
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				var dd := (pts[i] as Vector3).distance_to(pts[j])
				if dd > best:
					best = dd
					pa = pts[i]
					pb = pts[j]
		if best > 1e-4:
			out.append({"kind": "edge", "p": (pa + pb) * 0.5})
	return out


## chains of segments [[p, q], ...] into point loops
static func _loops(segs: Array) -> Array:
	var nxt := {}
	for s in segs:
		var k := _key(s[0])
		var l: Array = nxt.get(k, [])
		l.append(s)
		nxt[k] = l
	var used := {}
	var out: Array = []
	for s in segs:
		if used.has(s):
			continue
		var pts: Array = []
		var cur: Array = s
		used[s] = true
		while true:
			pts.append(cur[0])
			var cand: Array = nxt.get(_key(cur[1]), [])
			var f: Array = []
			for c in cand:
				if not used.has(c):
					f = c
					break
			if f.is_empty():
				break
			used[f] = true
			cur = f
		out.append(pts)
	return out


## the distance (metres) from p to the surface made of the triangles
static func _dist_to_tris(p: Vector3, tris: PackedVector3Array) -> float:
	var best := INF
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var pl := Plane(a, b, c)
		var q := pl.project(p)
		if Geometry3D.ray_intersects_triangle(q + pl.normal, -pl.normal, a, b, c) != null:
			best = minf(best, absf(pl.distance_to(p)))
		for e in [[a, b], [b, c], [c, a]]:
			best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, e[0], e[1])))
	return best


## where a pivot (mm) on body `bi` of the record (the steps before step `upto`) should land. Answers {"ok", "hidden" (bool), "p" (Vector3, mm: the
## new place; the old one when it is already on the body), "kind", "moved_mm", "words"}.
static func auto_place(rec: Dictionary, bi: int, o_mm: Vector3, upto := -1) -> Dictionary:
	var faces := Part.body_faces(rec, upto)
	if bi < 0 or bi >= faces.size():
		return {"ok": false, "why": "there is no body %d" % bi}
	var tris: PackedVector3Array = faces[bi]
	var p := o_mm * MM
	if _dist_to_tris(p, tris) <= HIDDEN_MM * MM:
		return {"ok": true, "hidden": false, "p": o_mm, "kind": "", "moved_mm": 0.0, "words": "The pivot is on the part: it stays where it is."}
	var best: Dictionary = {}
	var bd := INF
	for c in features_of(tris):
		var d := p.distance_to(c["p"])
		var w := d * (1.0 if c["kind"] != "face" else 1.25)   # a hole or an edge beats a face centre that is only a little nearer
		if w < bd:
			bd = w
			best = c
	if best.is_empty():
		return {"ok": false, "why": "the part has no visible feature to put the pivot on"}
	var np: Vector3 = best["p"]
	var nm: String = {"hole": "the centre of a hole", "edge": "the middle of an edge", "face": "the centre of a face"}[best["kind"]]
	var moved := p.distance_to(np) / MM
	return {"ok": true, "hidden": true, "p": np / MM, "kind": best["kind"], "moved_mm": moved,
		"words": "The pivot was in the air (a hidden tip), so it moved %s mm onto %s." % [str(snappedf(moved, 0.1)), nm]}


# ---------------------------------------------------------------- the hinge dialog's rows (PartUI)

## a unit axis square to `d` (the hinge's line): which = 1 one way, 2 the other way round (d x first)
static func perp_axis(d: Vector3, which: int) -> Vector3:
	var p1 := d.cross(Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	return p1 if which == 1 else d.normalized().cross(p1).normalized()


## the rows: Second turn (None / Sideways / Other way), its angle, and "Put the pivot on a visible spot" with the choice in words.
## State lives in pu.hp: "ax2" (0..2), "deg2" (deg), "snap" (bool), "snap_res" (auto_place's answer). Nothing is read unless the user touches a row.
static func rows(pu: Node) -> Control:
	pu.f_dial.visible = true
	var outer := VBoxContainer.new()
	outer.name = "part_joint_rows"
	var more := CheckButton.new()   # collapsed by default: the dialog keeps its height (the dial hides while it is open) so OK stays on screen
	more.name = "part_joint_more"
	more.text = "Second turn, visible pivot"
	more.focus_mode = Control.FOCUS_NONE
	outer.add_child(more)
	var v := VBoxContainer.new()
	v.name = "part_joint_body"
	v.visible = false
	outer.add_child(v)
	more.toggled.connect(func(on: bool) -> void:
		v.visible = on
		pu.f_dial.visible = not on
		for c in outer.get_parent().get_children():   # open: the angle rows fold away so OK stays above the timeline
			if c != outer and c is HBoxContainer:
				c.visible = not on)
	var h := HBoxContainer.new()
	var l: Label = pu._label("Second turn")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var ob := OptionButton.new()
	ob.name = "part_axis2"
	for t in ["None", "Sideways", "Other way"]:
		ob.add_item(t)
	ob.selected = int(pu.hp.get("ax2", 0))
	ob.tooltip_text = "A second line the part also turns round, square to the first one (a ball joint's second turn)"
	h.add_child(ob)
	v.add_child(h)
	var h2 := HBoxContainer.new()
	var l2: Label = pu._label("Second angle (deg)")
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_child(l2)
	var le := LineEdit.new()
	le.name = "part_deg2"
	le.custom_minimum_size.x = 70.0
	le.text = str(pu.hp.get("deg2", 30.0))
	le.editable = ob.selected > 0
	le.text_changed.connect(func(t: String) -> void:
		pu.hp["deg2"] = t.to_float()
		pu._preview())
	h2.add_child(le)
	v.add_child(h2)
	ob.item_selected.connect(func(i: int) -> void:
		pu.hp["ax2"] = i
		le.editable = i > 0
		if not pu.hp.has("deg2"):
			pu.hp["deg2"] = le.text.to_float()
		pu._preview())
	var cb := CheckBox.new()
	cb.name = "part_snap"
	cb.text = "Put the pivot on a visible spot"
	cb.tooltip_text = "If the pivot sits in the air (a hidden tip), move it onto the nearest hole centre, edge middle or face centre"
	cb.button_pressed = bool(pu.hp.get("snap", false))
	for k in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_color"]:
		cb.add_theme_color_override(k, Color(0.92, 0.94, 1.0))
	v.add_child(cb)
	var words: Label = pu._label("", 13, true)
	words.name = "part_snap_words"
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size.x = 260.0
	v.add_child(words)
	cb.toggled.connect(func(on: bool) -> void:
		pu.hp["snap"] = on
		pu.hp.erase("snap_res")
		words.text = ""
		if on and pu.hp.has("o") and int(pu.hp.get("body", -1)) >= 0:
			var r := auto_place(pu._rec(), int(pu.hp["body"]), (pu.hp["o"] as Vector3) / Part.MM)
			pu.hp["snap_res"] = r
			words.text = String(r.get("words", r.get("why", "")))
		pu._preview())
	if cb.button_pressed and pu.hp.has("snap_res"):
		words.text = String(pu.hp["snap_res"].get("words", ""))
	return outer


## the dialog's extras for the hinge feature `f` being built from pu.hp (d = the line, du = seconds). Nothing is added when the rows were not used.
static func add_to_feature(f: Dictionary, hp: Dictionary, d: Vector3, du: float, old: Dictionary) -> void:
	if int(hp.get("ax2", 0)) > 0:
		var a2 := perp_axis(d, int(hp["ax2"]))
		f["axis2"] = [a2.x, a2.y, a2.z]
		f["track2"] = [[0.0, 0.0], [du, float(hp.get("deg2", 30.0))]]
		if old.has("limit2"):
			f["limit2"] = old["limit2"]
	else:
		for k in ["axis2", "track2", "limit2"]:
			if old.has(k):
				f[k] = old[k]   # an edit of a two-axis hinge keeps its second axis
	if bool(hp.get("snap", false)) and hp.get("snap_res") is Dictionary:
		var r: Dictionary = hp["snap_res"]
		if bool(r.get("ok", false)) and bool(r.get("hidden", false)):
			var p: Vector3 = r["p"]
			f["o"] = [p.x, p.y, p.z]
			f["placed"] = {"kind": String(r["kind"]), "moved_mm": float(r["moved_mm"])}
