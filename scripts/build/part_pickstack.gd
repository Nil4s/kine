class_name PartPickStack
extends RefCounted
## C45 (F #203): what is under the cursor on a crowded sketch. Alt+click (nothing drawn, no tool) lists every item within reach,
## RULE order: a point beats an edge, an edge beats a face (a closed rectangle / circle). Then nearest first. One item is picked
## at once; two or more open a list. The default click is unchanged.

const RULE := "point > edge > face"
const PT_PX := 9.0
const EDGE_PX := 10.0
const PRI := {"point": 0, "edge": 1, "face": 2}


static func _pts(e: Dictionary) -> Array:   # [[mm, name]]
	match String(e.get("k", "")):
		"line":
			return [[Part.v2(e["a"]), "start"], [Part.v2(e["b"]), "end"]]
		"rect":
			var a := Part.v2(e["a"])
			var b := Part.v2(e["b"])
			return [[a, "corner 1"], [Vector2(b.x, a.y), "corner 2"], [b, "corner 3"], [Vector2(a.x, b.y), "corner 4"]]
		"circle":
			return [[Part.v2(e["c"]), "centre"]]
		"arc":
			return [[Part.v2(e["a"]), "start"], [Part.v2(e["b"]), "end"]]
		"bspline":
			var out := []
			for i in (e["pts"] as Array).size():
				out.append([Part.v2(e["pts"][i]), "point %d" % (i + 1)])
			return out
	return []


## every item under screen point p: [{"kind", "ent", "label", "d", "at"}] sorted by RULE then distance. scr: mm -> screen.
static func stack(ents: Array, p: Vector2, scr: Callable, edge_of: Callable) -> Array:
	var out := []
	for i in ents.size():
		var e: Dictionary = ents[i]
		var k := String(e.get("k", ""))
		var nm := "%s %d" % [k, i + 1]
		for pr in _pts(e):
			var s: Vector2 = scr.call(pr[0])
			if p.distance_to(s) <= PT_PX:
				out.append({"kind": "point", "ent": i, "label": "point: %s of %s" % [pr[1], nm], "d": p.distance_to(s), "at": s})
		var ed: float = edge_of.call(i, p)
		if ed >= 0.0 and ed <= EDGE_PX:
			out.append({"kind": "edge", "ent": i, "label": "edge: %s" % nm, "d": ed, "at": p})
		if (k == "rect" or k == "circle") and _inside(e, p, scr):
			out.append({"kind": "face", "ent": i, "label": "face: inside %s" % nm, "d": 99.0, "at": p})
	out.sort_custom(func(a, b): return PRI[a["kind"]] < PRI[b["kind"]] or (PRI[a["kind"]] == PRI[b["kind"]] and a["d"] < b["d"]))
	return out


static func _inside(e: Dictionary, p: Vector2, scr: Callable) -> bool:
	if String(e["k"]) == "rect":
		var a := Part.v2(e["a"])
		var b := Part.v2(e["b"])
		var poly := PackedVector2Array([scr.call(a), scr.call(Vector2(b.x, a.y)), scr.call(b), scr.call(Vector2(a.x, b.y))])
		return Geometry2D.is_point_in_polygon(p, poly)
	var c := Part.v2(e["c"])
	var r := float(e["r"])
	var poly2 := PackedVector2Array()
	for j in 48:
		poly2.append(scr.call(c + Vector2.from_angle(TAU * j / 48.0) * r))
	return Geometry2D.is_point_in_polygon(p, poly2)


## the screen distance from p to entity i's outline (-1 if it has none): uses the same segments the Dimension tool picks on
static func edge_dist(ents: Array, i: int, p: Vector2, scr: Callable) -> float:
	var e: Dictionary = ents[i]
	var segs := []
	match String(e.get("k", "")):
		"rect":
			var a := Part.v2(e["a"])
			var b := Part.v2(e["b"])
			var c := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
			for j in 4:
				segs.append([c[j], c[(j + 1) % 4]])
		"line":
			segs.append([Part.v2(e["a"]), Part.v2(e["b"])])
		"circle":
			var c2 := Part.v2(e["c"])
			var r := float(e["r"])
			for j in 48:
				segs.append([c2 + Vector2.from_angle(TAU * j / 48.0) * r, c2 + Vector2.from_angle(TAU * (j + 1) / 48.0) * r])
		"arc":
			segs.append([Part.v2(e["a"]), Part.v2(e["m"])])
			segs.append([Part.v2(e["m"]), Part.v2(e["b"])])
		"bspline":
			var sp: Array = e["pts"]
			for j in sp.size() - 1:
				segs.append([Part.v2(sp[j]), Part.v2(sp[j + 1])])
	if segs.is_empty():
		return -1.0
	var best := 1.0e9
	for sg in segs:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, scr.call(sg[0]), scr.call(sg[1]))))
	return best


## the list, the highlight ring and the words: one PartUI helper (one instance, made on first use)
var ui: PartUI
var popup: PopupMenu
var items: Array = []
var chosen := {}
var ring: Control


func open(pu: PartUI, p: Vector2) -> void:
	ui = pu
	var ents: Array = pu._sk().get("ents", [])
	var scr := func(v): return pu.scr(v)
	var eo := func(i, q): return edge_dist(ents, i, q, scr)
	items = stack(ents, p, scr, eo)
	if items.is_empty():
		chosen = {}
		_ring_sync()
		pu._say("Nothing under the cursor (click priority: %s)" % RULE)
		return
	if items.size() == 1:
		_choose(0)
		return
	if popup == null:
		popup = PopupMenu.new()
		pu.pov.add_child(popup)
		popup.id_pressed.connect(_choose)
	popup.clear()
	for i in items.size():
		popup.add_item("%d  %s" % [i + 1, items[i]["label"]], i)
	popup.add_separator()
	popup.add_item("Priority: %s (nearest first)" % RULE, 999)
	popup.set_item_disabled(popup.item_count - 1, true)
	popup.position = Vector2i(p)
	popup.popup()
	pu._say("%d things under the cursor: pick one from the list (priority %s)" % [items.size(), RULE])


func _choose(i: int) -> void:
	if i < 0 or i >= items.size():
		return
	chosen = items[i]
	_ring_sync()
	ui._say("Picked %s (%d of %d under the cursor; priority %s)" % [chosen["label"], i + 1, items.size(), RULE])


func _ring_sync() -> void:
	if ring == null:
		ring = Control.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.draw.connect(_draw_ring)
		ui.pov.add_child(ring)
	ring.queue_redraw()


func _draw_ring() -> void:
	if chosen.is_empty():
		return
	var e: Dictionary = (ui._sk().get("ents", []) as Array)[int(chosen["ent"])]
	var col := Color("#ffc233")
	if chosen["kind"] == "point":
		ring.draw_arc(chosen["at"], 9.0, 0.0, TAU, 24, col, 3.0)
	else:
		var scr := func(v): return ui.scr(v)
		var pl := PackedVector2Array()
		match String(e["k"]):
			"rect":
				var a := Part.v2(e["a"])
				var b := Part.v2(e["b"])
				for c in [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]:
					pl.append(scr.call(c))
			"line":
				pl = PackedVector2Array([scr.call(Part.v2(e["a"])), scr.call(Part.v2(e["b"]))])
			"circle":
				for j in 49:
					pl.append(scr.call(Part.v2(e["c"]) + Vector2.from_angle(TAU * j / 48.0) * float(e["r"])))
			_:
				pass
		if pl.size() >= 2:
			if chosen["kind"] == "face":
				ring.draw_colored_polygon(pl, Color(col, 0.25))
			ring.draw_polyline(pl, col, 3.0)
