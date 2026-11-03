## C50 (complaints #209, #197): inside a sketch, click an existing body edge or corner to PROJECT it into the sketch as reference geometry
## (dashed violet; the lines you draw snap to it; a line end drawn on a reference corner is pinned there by a rule that holds when the body moves),
## and every sketch item has a short unique label: L1 line, R2 rectangle, C3 circle, A4 arc, S5 curvy line (the number is the item's place in the
## sketch), E1 / E2 reference edge, P1 / P2 reference corner. The label shows on hover and in the status line.
## Opt-in: the "Pick body edges as reference" box in the sketch palette is off by default, so a click draws exactly as before.
## A reference is stored in the sketch step as sk["refs"]: [{"id": "E1", "kind": "edge" | "point", "q": [..], "d": [..], "body": N, "s": +-1 (point: which
## end of the edge), "pa": [x, y], "pb": [x, y] (the plane mm it was last projected to)}]. q / d describe the edge the way a fillet edge is described
## (centre inside the body's box, direction), so it is found again when the body is resized; refresh() re-projects while the sketch is open.
class_name PartC50
extends RefCounted

const REF_C := Color("#b58cff")
const PICK_PX := 9.0
const SNAP_PX := 10.0

var pu: PartUI
var chk: CheckBox
var on := false
var hover_label := ""
var hover_at := Vector2.ZERO
var _sig := ""


func _init(p: PartUI) -> void:
	pu = p
	chk = CheckBox.new()
	chk.name = "c50_ref_chk"
	chk.text = "Pick body edges as reference"
	chk.tooltip_text = "Click an edge or a corner of the solid to project it into this sketch as dashed reference geometry. Lines you draw snap to it. Click it again to remove it."
	chk.focus_mode = Control.FOCUS_NONE
	chk.toggled.connect(func(v: bool): on = v; pu.pov.queue_redraw())
	if pu.c15 != null and pu.c15.box != null:   # first row of the scrolling window under the palette: the palette itself must not grow (pconstr clicks its rule row)
		pu.c15.box.add_child(chk)
		pu.c15.box.move_child(chk, 0)
	else:
		pu.sketch_box.add_child(chk)


# ---------------------------------------------------------------- labels (#197)

static func letter(kind: String) -> String:
	match kind:
		"line": return "L"
		"rect": return "R"
		"circle": return "C"
		"arc": return "A"
		"bspline": return "S"
	return "X"


## the label of sketch item i (its place in the sketch, from 1): "L1", "R2" ... unique in the sketch
static func ent_label(sk: Dictionary, i: int) -> String:
	var ents: Array = sk.get("ents", [])
	if i < 0 or i >= ents.size():
		return ""
	return "%s%d" % [letter(String(ents[i].get("k", ""))), i + 1]


## every label in the sketch, in order: items first, then the references
static func all_labels(sk: Dictionary) -> Array:
	var out := []
	for i in (sk.get("ents", []) as Array).size():
		out.append(ent_label(sk, i))
	for r in sk.get("refs", []):
		out.append(String(r["id"]))
	return out


static func ent_words(sk: Dictionary, i: int) -> String:
	var e: Dictionary = sk["ents"][i]
	var k := String(e.get("k", ""))
	var w: String = {"line": "line", "rect": "rectangle", "circle": "circle", "arc": "arc", "bspline": "curvy line"}.get(k, k)
	var s := "%s: %s" % [ent_label(sk, i), w]
	match k:
		"line":
			s += ", %s mm" % Part._short(Part.v2(e["a"]).distance_to(Part.v2(e["b"])))
		"circle":
			s += ", radius %s mm" % Part._short(float(e["r"]))
		"rect":
			var d := (Part.v2(e["b"]) - Part.v2(e["a"])).abs()
			s += ", %s x %s mm" % [Part._short(d.x), Part._short(d.y)]
	return s


# ---------------------------------------------------------------- references

static func refs_of(sk: Dictionary) -> Array:
	return sk.get("refs", [])


static func _next_id(sk: Dictionary, kind: String) -> String:
	var n := 0
	var pre := "E" if kind == "edge" else "P"
	for r in refs_of(sk):
		if String(r["id"]).begins_with(pre):
			n = maxi(n, int(String(r["id"]).substr(1)))
	return "%s%d" % [pre, n + 1]


## the index in edges (replay "edges": c a b d q body) that best matches the stored descriptor, or -1
static func match_in(edges: Array, r: Dictionary) -> int:
	var q := Vector3(float(r["q"][0]), float(r["q"][1]), float(r["q"][2]))
	var d := Vector3(float(r["d"][0]), float(r["d"][1]), float(r["d"][2]))
	var best := -1
	var best_s := Part.MATCH_MAX
	for i in edges.size():
		if int(edges[i]["body"]) != int(r.get("body", 0)):
			continue
		var s: float = (edges[i]["q"] as Vector3).distance_to(q) + 0.5 * (1.0 - absf((edges[i]["d"] as Vector3).dot(d)))
		if s < best_s:
			best_s = s
			best = i
	return best


## the world end (a or b) of edge e that the sign s names
static func end_of(e: Dictionary, s: int) -> Vector3:
	var a: Vector3 = e["a"]
	var b: Vector3 = e["b"]
	var c: Vector3 = e["c"]
	var d: Vector3 = e["d"]
	return a if (a - c).dot(d) * float(s) > 0.0 else b


## the plane mm points a reference stands for: an edge gives [pa, pb], a point gives [pa]
static func points_of(r: Dictionary) -> Array:
	if String(r.get("kind", "")) == "point":
		return [Part.v2(r["pa"])]
	return [Part.v2(r["pa"]), Part.v2(r["pb"])]


## the point a "refpt" rule means: ref index ri, end rp (0 / 1; a corner has only 0). Vector2.INF when the reference is gone
static func ref_point(sk: Dictionary, ri: int, rp: int) -> Vector2:
	var rs := refs_of(sk)
	if ri < 0 or ri >= rs.size():
		return Vector2.INF
	var pts := points_of(rs[ri])
	return pts[mini(rp, pts.size() - 1)]


## re-find every reference in edges (the model as it is now) and re-project it onto the sketch plane pl. Returns how many moved
static func refresh(sk: Dictionary, edges: Array, pl: Dictionary) -> int:
	var moved := 0
	for r in refs_of(sk):
		var i := match_in(edges, r)
		if i < 0:
			continue
		var e: Dictionary = edges[i]
		var pa: Vector2
		var pb: Vector2
		if String(r["kind"]) == "point":
			pa = Part.to_plane(pl, end_of(e, int(r["s"])))
			pb = pa
		else:
			pa = Part.to_plane(pl, e["a"])
			pb = Part.to_plane(pl, e["b"])
		var na := Part.arr2(pa)
		var nb := Part.arr2(pb)
		if na != r.get("pa") or nb != r.get("pb"):
			moved += 1
		r["pa"] = na
		r["pb"] = nb
		var q: Vector3 = e["q"]
		var d: Vector3 = e["d"]
		r["q"] = [q.x, q.y, q.z]
		r["d"] = [d.x, d.y, d.z]
	return moved


## add the edge e (replay "edges" entry) as a reference; returns its id
static func add_edge(sk: Dictionary, e: Dictionary, pl: Dictionary) -> String:
	var q: Vector3 = e["q"]
	var d: Vector3 = e["d"]
	var r := {"id": _next_id(sk, "edge"), "kind": "edge", "q": [q.x, q.y, q.z], "d": [d.x, d.y, d.z], "body": int(e["body"]), "s": 1,
		"pa": Part.arr2(Part.to_plane(pl, e["a"])), "pb": Part.arr2(Part.to_plane(pl, e["b"]))}
	if not sk.has("refs"):
		sk["refs"] = []
	sk["refs"].append(r)
	return String(r["id"])


## add the corner (world point v, an end of edge e) as a reference; returns its id
static func add_point(sk: Dictionary, e: Dictionary, v: Vector3, pl: Dictionary) -> String:
	var q: Vector3 = e["q"]
	var d: Vector3 = e["d"]
	var s := 1 if (v - (e["c"] as Vector3)).dot(d) > 0.0 else -1
	var pa := Part.arr2(Part.to_plane(pl, v))
	var r := {"id": _next_id(sk, "point"), "kind": "point", "q": [q.x, q.y, q.z], "d": [d.x, d.y, d.z], "body": int(e["body"]), "s": s, "pa": pa, "pb": pa}
	if not sk.has("refs"):
		sk["refs"] = []
	sk["refs"].append(r)
	return String(r["id"])


## remove reference ri and the pins that used it (later pins slide down one)
static func remove_ref(sk: Dictionary, ri: int) -> void:
	var rs := refs_of(sk)
	if ri < 0 or ri >= rs.size():
		return
	rs.remove_at(ri)
	var cons: Array = sk.get("cons", [])
	for j in range(cons.size() - 1, -1, -1):
		if String(cons[j].get("k", "")) == "refpt":
			var cr := int(cons[j].get("r", -1))
			if cr == ri:
				cons.remove_at(j)
			elif cr > ri:
				cons[j]["r"] = cr - 1


## the reference points a drawn point can land on, as [{"p": mm, "ri", "rp", "id"}]: corners, edge ends
static func targets(sk: Dictionary) -> Array:
	var out := []
	var rs := refs_of(sk)
	for ri in rs.size():
		var pts := points_of(rs[ri])
		for rp in pts.size():
			out.append({"p": pts[rp], "ri": ri, "rp": rp, "id": String(rs[ri]["id"])})
	return out


## after a line was added: each end that sits on a reference point gets a "refpt" rule ({"k": "refpt", "a": ent, "ap": 0 | 1, "r": ref, "rp": end})
## so it stays on the reference when the body moves. Returns the number of rules added
static func pin_new_line(sk: Dictionary, ent: int) -> int:
	var ents: Array = sk.get("ents", [])
	if ent < 0 or ent >= ents.size() or String(ents[ent].get("k", "")) != "line":
		return 0
	var n := 0
	var tg := targets(sk)
	for ap in 2:
		var p := Part.v2(ents[ent]["a" if ap == 0 else "b"])
		for t in tg:
			if p.distance_to(t["p"]) < 1e-3:
				if not sk.has("cons"):
					sk["cons"] = []
				sk["cons"].append({"k": "refpt", "a": ent, "ap": ap, "r": int(t["ri"]), "rp": int(t["rp"])})
				n += 1
				break
	return n


# ---------------------------------------------------------------- UI hooks (called by PartUI)

func _plane() -> Dictionary:
	return pu._plane()


## the model edge nearest the pointer: {"i": edge_cache index, "pt": world corner or null}; {} if none within reach
func pick_model(p: Vector2) -> Dictionary:
	var best := {}
	var best_d := PICK_PX
	for i in pu.edge_cache.size():
		var e: Dictionary = pu.edge_cache[i]
		var a: Vector3 = e["a"]
		var b: Vector3 = e["b"]
		if a.distance_to(b) < 1e-6 or pu.m.cam.is_position_behind(a) or pu.m.cam.is_position_behind(b):
			continue   # a closed curve has no ends to project
		var pa: Vector2 = pu.m.cam.unproject_position(a)
		var pb: Vector2 = pu.m.cam.unproject_position(b)
		var da := p.distance_to(pa)
		var db := p.distance_to(pb)
		if da < best_d and da <= db:
			best_d = da
			best = {"i": i, "pt": a}
		elif db < best_d:
			best_d = db
			best = {"i": i, "pt": b}
	if not best.is_empty():
		return best
	best_d = PICK_PX
	for i in pu.edge_cache.size():
		var e: Dictionary = pu.edge_cache[i]
		var a: Vector3 = e["a"]
		var b: Vector3 = e["b"]
		if a.distance_to(b) < 1e-6 or pu.m.cam.is_position_behind(a) or pu.m.cam.is_position_behind(b):
			continue
		var pa: Vector2 = pu.m.cam.unproject_position(a)
		var pb: Vector2 = pu.m.cam.unproject_position(b)
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pa, pb))
		if d < best_d:
			best_d = d
			best = {"i": i, "pt": null}
	return best


## the reference nearest the pointer: its index, or -1
func pick_ref(p: Vector2) -> int:
	var sk := pu._sk()
	var best := -1
	var best_d := PICK_PX
	var rs := refs_of(sk)
	for ri in rs.size():
		var pts := points_of(rs[ri])
		var d := 1e9
		if pts.size() == 1:
			d = p.distance_to(pu.scr(pts[0]))
		else:
			d = p.distance_to(Geometry2D.get_closest_point_to_segment(p, pu.scr(pts[0]), pu.scr(pts[1])))
		if d < best_d:
			best_d = d
			best = ri
	return best


## a press while the box is on: a reference under the pointer is removed, else a model corner / edge is projected. True when it took the press
func press(p: Vector2) -> bool:
	if not on or pu.sk == "":
		return false
	var sk := pu._sk()
	var ri := pick_ref(p)
	if ri >= 0:
		pu.m._step_hint = "Remove reference"
		pu.m._push_undo()
		var id := String(refs_of(sk)[ri]["id"])
		remove_ref(sk, ri)
		pu._say("Removed reference %s" % id)
		pu._after_sketch_edit()
		return true
	var hit := pick_model(p)
	if hit.is_empty():
		return false
	var e: Dictionary = pu.edge_cache[int(hit["i"])]
	pu.m._step_hint = "Reference from the solid"
	pu.m._push_undo()
	var id2: String
	if hit["pt"] != null:
		id2 = add_point(sk, e, hit["pt"], _plane())
		pu._say("%s: corner of the solid projected into the sketch (dashed). Lines you draw snap to it." % id2)
	else:
		id2 = add_edge(sk, e, _plane())
		pu._say("%s: edge of the solid projected into the sketch (dashed). Lines you draw snap to it." % id2)
	pu._after_sketch_edit()
	return true


## a drawn point near a reference point lands on it (screen reach SNAP_PX). Returns v unchanged otherwise
func snap(screen: Vector2, v: Vector2) -> Vector2:
	var sk := pu._sk()
	var best := v
	var best_d := SNAP_PX
	for t in targets(sk):
		var d := screen.distance_to(pu.scr(t["p"]))
		if d < best_d:
			best_d = d
			best = t["p"]
	# along a reference edge: the nearest point of it
	if best == v:
		for r in refs_of(sk):
			if String(r["kind"]) != "edge":
				continue
			var a := Part.v2(r["pa"])
			var b := Part.v2(r["pb"])
			var q := Geometry2D.get_closest_point_to_segment(screen, pu.scr(a), pu.scr(b))
			if screen.distance_to(q) < best_d:
				best_d = screen.distance_to(q)
				best = Geometry2D.get_closest_point_to_segment(v, a, b)
	return best


## the pointer moved in the sketch: name what is under it (item or reference) on the status line and next to the pointer
func hover(p: Vector2) -> void:
	var sk := pu._sk()
	var txt := ""
	var ri := pick_ref(p)
	if ri >= 0:
		var r: Dictionary = refs_of(sk)[ri]
		txt = "%s: reference %s from the solid" % [r["id"], "corner" if String(r["kind"]) == "point" else "edge"]
	else:
		var h := pu.pick_ent(p)
		if not h.is_empty():
			txt = ent_words(sk, int(h["ent"]))
	if txt != hover_label:
		hover_label = txt
		hover_at = p
		if txt != "":
			pu._say(txt)
		pu.pov.queue_redraw()
	else:
		hover_at = p


## keep the references on the model: re-project them when the solid's edges changed, then re-solve the pins
func sync() -> void:
	if pu.sk == "":
		return
	var sk := pu._sk()
	if refs_of(sk).is_empty():
		return
	if refresh(sk, pu.edge_cache, _plane()) > 0:
		if (sk.get("cons", []) as Array).size() > 0:
			Part.solve(sk)
		pu.pov.queue_redraw()


func draw() -> void:
	var sk := pu._sk()
	if sk.is_empty():
		return
	for r in refs_of(sk):
		var pts := points_of(r)
		var lab_at: Vector2
		if pts.size() == 1:
			var s := pu.scr(pts[0])
			pu.pov.draw_circle(s, 5.5, Color(REF_C, 0.35))
			pu.pov.draw_arc(s, 5.5, 0.0, TAU, 20, REF_C, 2.0)
			lab_at = s
		else:
			var sa := pu.scr(pts[0])
			var sb := pu.scr(pts[1])
			if sa.distance_to(sb) < 2.0:
				pu.pov.draw_circle(sa, 5.5, REF_C)   # an edge square to the sketch plane is one point
			else:
				pu.pov.draw_dashed_line(sa, sb, REF_C, 3.0, 8.0)
			pu.pov.draw_circle(sa, 3.0, REF_C)
			pu.pov.draw_circle(sb, 3.0, REF_C)
			lab_at = (sa + sb) * 0.5
		if hover_label.begins_with(String(r["id"]) + ":"):
			pu._pill(lab_at + Vector2(8, -22), String(r["id"]), Color(0.28, 0.16, 0.5, 0.95), Color.WHITE, 12)
	if hover_label != "":
		pu._pill(hover_at + Vector2(14, 12), hover_label, Color(0.1, 0.12, 0.2, 0.95), Color.WHITE, 12)
	if on:
		var h := pick_model(pu.cur_px)
		if not h.is_empty():
			var e: Dictionary = pu.edge_cache[int(h["i"])]
			if h["pt"] != null:
				pu.pov.draw_arc(pu.m.cam.unproject_position(h["pt"]), 8.0, 0.0, TAU, 20, REF_C, 3.0)
			else:
				pu.pov.draw_line(pu.m.cam.unproject_position(e["a"]), pu.m.cam.unproject_position(e["b"]), Color(REF_C, 0.7), 5.0)
