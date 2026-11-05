## blueprint.gd - BLUEPRINTS of a building (docs/BUILD_PLAN.md phase 1g): the SHEETS drawn straight from the record, pure 2D (no mesh, no
## renderer). A sheet is a dictionary in PAPER MILLIMETRES (y down, origin the paper's top-left):
##   {"paper": "A3", "w": 420, "h": 297, "denom": 50, "tab": "Floor 1", "title": "Floor 1 plan", "ents": [...], "area": Rect2 (the drawing's room)}
## and its entities (the one drawing the screen, the SVG, the PNG and the DXF all share):
##   {"t": "line", "a", "b"}  {"t": "poly", "pts"} (closed)  {"t": "arc", "c", "r", "a0", "a1"} (paper angles, y down)
##   {"t": "text", "p", "s", "h", "anc": "l"|"m"|"r", "rot": 0|-90}, each with "cls" (its style / DXF layer) and "d" (data-* attributes).
## TABS: "Floor 1".. "Floor N" (PLAN), "Front" and "Side" (ELEVATIONS, the side seen from the right, +X). Plan: walls as poche
## polygons (cut at each opening: the segments + the openings = the wall's length), door swing = a leaf line + an arc of radius = the
## door's width, a window = three lines, stairs = tread outlines + an up arrow (dashed on the floor above), pieces as outlines, dimension
## chains (opening positions + widths) on the outer walls, overall dimensions, a north arrow (+Z is up the sheet, the front is at the bottom).
## Elevation: wall faces, openings facing the viewer, the roof's silhouette (its solid's convex hull), the ground, floor levels, overall
## dimensions. The SCALE (1:50 / 1:100 / ...) and the PAPER (A4 / A3) are chosen ONCE for the whole set: the first that fits every tab.
## Dimensions are metres, 2 decimals. Plan: x -> paper x, z -> paper -y.
class_name Blueprint
extends RefCounted

const PAPERS := {"A4": Vector2(297, 210), "A3": Vector2(420, 297)}
## [paper, 1:denom] in the order tried: the biggest drawing on the smallest paper first
const TRIES := [["A4", 50], ["A3", 50], ["A4", 100], ["A3", 100], ["A3", 200], ["A3", 500], ["A3", 1000]]
const MARGIN := 10.0   # mm: the border's distance from the paper's edge
const PAD := 4.0       # mm: between the border and the drawing's room
const TB_H := 24.0     # mm: the title block's strip
const TXT := 2.5       # mm: the text height of a dimension
const CHAIN := 11.0    # mm: the opening chain's distance from the wall
const OVERALL := 22.0  # mm: the overall dimension's distance from the wall
## where an export goes (the test points it at a user:// folder of its own)
static var dir := "user://blueprints"
## class -> its drawing: w = line weight (mm), stroke, fill ("" = none), dash (mm, 0 = solid)
const STYLE := {
	"wall": {"w": 0.25, "stroke": "#000000", "fill": "#1b1b1b"}, "jamb": {"w": 0.35, "stroke": "#000000"},
	"door-leaf": {"w": 0.35, "stroke": "#000000"}, "door-arc": {"w": 0.18, "stroke": "#000000"}, "window": {"w": 0.18, "stroke": "#000000"},
	"stairs": {"w": 0.25, "stroke": "#000000"}, "stairs-arrow": {"w": 0.35, "stroke": "#000000"}, "piece": {"w": 0.25, "stroke": "#000000"},
	"dashed": {"w": 0.18, "stroke": "#000000", "dash": 1.8},
	"dim": {"w": 0.13, "stroke": "#202020"}, "dim-text": {"stroke": "#000000"}, "text": {"stroke": "#000000"},
	"border": {"w": 0.5, "stroke": "#000000"}, "title": {"w": 0.3, "stroke": "#000000"}, "title-label": {"stroke": "#606060"}, "title-text": {"stroke": "#000000"},
	"north": {"w": 0.3, "stroke": "#000000"}, "north-head": {"w": 0.3, "stroke": "#000000", "fill": "#000000"},
	"elev-wall": {"w": 0.35, "stroke": "#000000", "fill": "#ececec"}, "elev-door": {"w": 0.3, "stroke": "#000000", "fill": "#ffffff"},
	"elev-window": {"w": 0.3, "stroke": "#000000", "fill": "#d6e6f2"}, "elev-arch": {"w": 0.3, "stroke": "#000000", "fill": "#ffffff"},
	"roof": {"w": 0.4, "stroke": "#000000", "fill": "#c8c8c8"}, "roof-edge": {"w": 0.18, "stroke": "#000000"},
	"ground": {"w": 0.6, "stroke": "#000000"}, "ground-hatch": {"w": 0.13, "stroke": "#404040"}, "level": {"w": 0.18, "stroke": "#000000"},
	"dim-bg": {"w": 0.0, "stroke": "#ffffff", "fill": "#ffffff"}, "callout": {"w": 0.25, "stroke": "#000000"}, "leader": {"w": 0.18, "stroke": "#000000"},
	"callout-text": {"stroke": "#000000"},
}


## custom sheet sizes registered by BlueprintExt (name -> mm); empty by default, so A4 / A3 stay the only papers
static var custom_papers := {}


static func paper_size(paper: String) -> Vector2:
	return PAPERS[paper] if PAPERS.has(paper) else Vector2(custom_papers.get(paper, Vector2(420, 297)))


static func style(cls: String) -> Dictionary:
	return STYLE.get(cls, {"w": 0.2, "stroke": "#000000"})


# ---------------------------------------------------------------- the set

## the tabs of this building ([] when there is nothing to draw)
static func tabs(b: Dictionary) -> Array:
	var out := []
	if b.is_empty() or b.get("rooms", []).is_empty():
		return out
	for s in Building.storey_count(b):
		out.append("Floor %d" % (s + 1))
	out.append("Front")
	out.append("Side")
	return out


static func title_of(tab: String) -> String:
	match tab:
		"Front":
			return "Front elevation"
		"Side":
			return "Side elevation (right)"
	return tab + " plan"


static func _area(paper: String) -> Rect2:
	var P: Vector2 = paper_size(paper)
	return Rect2(MARGIN + PAD, MARGIN + PAD, P.x - 2.0 * (MARGIN + PAD), P.y - 2.0 * (MARGIN + PAD) - TB_H)


## the paper and scale that fit EVERY tab: {"paper", "denom"}
static func choose(b: Dictionary) -> Dictionary:
	var ts := tabs(b)
	for t in TRIES:
		var area := _area(String(t[0]))
		var fits := true
		for tab in ts:
			var sz := _bounds(_view(b, String(tab), 1000.0 / float(t[1]))).size
			if sz.x > area.size.x or sz.y > area.size.y:
				fits = false
				break
		if fits:
			return {"paper": t[0], "denom": t[1]}
	return {"paper": "A3", "denom": 1000}


## one tab as a sheet; pick = a choose() result to reuse
static func sheet(b: Dictionary, tab: String, pick := {}) -> Dictionary:
	var ch: Dictionary = pick if not pick.is_empty() else choose(b)
	var paper: String = ch["paper"]
	var denom: int = int(ch["denom"])
	var P: Vector2 = paper_size(paper)
	var area := _area(paper)
	var ents := _view(b, tab, 1000.0 / float(denom))
	var bb := _bounds(ents)
	ents = _shift(ents, area.get_center() - bb.get_center())
	var ts := tabs(b)
	ents.append_array(_frame(b, tab, paper, denom, ts.find(tab) + 1, ts.size()))
	return {"paper": paper, "w": P.x, "h": P.y, "denom": denom, "k": 1000.0 / float(denom), "tab": tab, "title": title_of(tab), "name": String(b.get("name", "")), "ents": ents, "area": area}


static func _view(b: Dictionary, tab: String, k: float) -> Array:
	if tab.begins_with("Floor "):
		return _plan(b, int(tab.substr(6)) - 1, k)
	return _elev(b, "front" if tab == "Front" else "side", k)


# ---------------------------------------------------------------- entity helpers

static func _line(a: Vector2, c: Vector2, cls: String, d := {}) -> Dictionary:
	return {"t": "line", "a": a, "b": c, "cls": cls, "d": d}


static func _poly(pts: Array, cls: String, d := {}) -> Dictionary:
	return {"t": "poly", "pts": PackedVector2Array(pts), "cls": cls, "d": d}


static func _text(p: Vector2, s: String, h: float, anc: String, cls: String, d := {}, rot := 0.0) -> Dictionary:
	return {"t": "text", "p": p, "s": s, "h": h, "anc": anc, "rot": rot, "cls": cls, "d": d}


static func _shift(ents: Array, off: Vector2) -> Array:
	var out := []
	for e in ents:
		var c: Dictionary = e.duplicate()
		match String(e["t"]):
			"line":
				c["a"] = (e["a"] as Vector2) + off
				c["b"] = (e["b"] as Vector2) + off
			"poly":
				var q := PackedVector2Array()
				for v in e["pts"]:
					q.append(v + off)
				c["pts"] = q
			"arc":
				c["c"] = (e["c"] as Vector2) + off
			"text":
				c["p"] = (e["p"] as Vector2) + off
		out.append(c)
	return out


## the box round everything (text by an estimate of its width)
static func _bounds(ents: Array) -> Rect2:
	var box := [Vector2(INF, INF), Vector2(-INF, -INF)]   # an Array: a lambda changes what it shares, not a captured number
	var add := func(v: Vector2):
		box[0] = Vector2(minf(box[0].x, v.x), minf(box[0].y, v.y))
		box[1] = Vector2(maxf(box[1].x, v.x), maxf(box[1].y, v.y))
	for e in ents:
		match String(e["t"]):
			"line":
				add.call(e["a"])
				add.call(e["b"])
			"poly":
				for v in e["pts"]:
					add.call(v)
			"arc":
				for i in 9:
					var a: float = lerpf(float(e["a0"]), float(e["a1"]), i / 8.0)
					add.call((e["c"] as Vector2) + Vector2(cos(a), sin(a)) * float(e["r"]))
			"text":
				var h := float(e["h"])
				var w := String(e["s"]).length() * 0.55 * h
				var p: Vector2 = e["p"]
				var x0 := p.x if e["anc"] == "l" else (p.x - w * 0.5 if e["anc"] == "m" else p.x - w)
				if float(e["rot"]) == 0.0:
					add.call(Vector2(x0, p.y - h))
					add.call(Vector2(x0 + w, p.y + 0.25 * h))
				else:   # runs up the sheet: the text's start is at the bottom
					var y0 := p.y if e["anc"] == "l" else (p.y + w * 0.5 if e["anc"] == "m" else p.y + w)
					add.call(Vector2(p.x - h, y0 - w))
					add.call(Vector2(p.x + 0.25 * h, y0))
	if box[0].x == INF:
		return Rect2()
	return Rect2(box[0], box[1] - box[0])


## a dimension: the measured points a, c (paper), n = the side it sits on (unit), off = its distance (mm)
static func _dim(a: Vector2, c: Vector2, n: Vector2, off: float, txt: String, d := {}) -> Array:
	var out := []
	var a2 := a + n * off
	var c2 := c + n * off
	var dp := BlueprintExt.dim_params()
	var gap := float(dp["gap"])
	var over := float(dp["over"])
	out.append(_line(a + n * gap, a2 + n * over, "dim"))
	out.append(_line(c + n * gap, c2 + n * over, "dim"))
	out.append(_line(a2, c2, "dim"))
	var u := (c - a).normalized()
	var t := (u + n).normalized() * 1.4
	out.append(_line(a2 - t, a2 + t, "dim"))
	out.append(_line(c2 - t, c2 + t, "dim"))
	var mid := (a2 + c2) * 0.5
	var tg := float(dp["tgap"])
	var horiz := absf(u.x) > 0.5
	if bool(dp["bg"]):
		out.append(BlueprintExt.dim_bg(mid + (Vector2(0, -tg) if horiz else Vector2(-tg, 0)), txt, horiz))
	if horiz:
		out.append(_text(mid + Vector2(0, -tg), txt, TXT, "m", "dim-text", d))
	else:
		out.append(_text(mid + Vector2(-tg, 0), txt, TXT, "m", "dim-text", d, -90.0))
	return out


static func _m2(v: float) -> String:
	return "%.2f" % v


# ---------------------------------------------------------------- the plan

## a room's group-frame point -> world (x, z)
static func _w(r: Dictionary, x: float, z: float) -> Vector2:
	var v := Vector3(x, 0, z).rotated(Vector3.UP, deg_to_rad(float(r.get("yaw", 0.0))))
	return Vector2(v.x, v.z)


static func _pp(k: float, w: Vector2) -> Vector2:
	return Vector2(w.x * k, -w.y * k)


## one room's walls: [{"id", "axis" ("x" runs along X), "a0", "a1" (along, group frame), "q0", "q1" (across), "in" (the interior side, +1 / -1 on the cross axis), "outer"}]
static func room_walls(b: Dictionary, r: Dictionary) -> Array:
	var c := Vector3(float(r["x"]), 0, float(r["z"])).rotated(Vector3.UP, -deg_to_rad(float(r.get("yaw", 0.0))))
	var w := float(r["w"])
	var d := float(r["d"])
	var t := clampf(Building.num(b, r.get("thickness"), 0.2), 0.01, minf(w, d) * 0.5 - 0.01)
	var out := [
		{"id": "front", "axis": "x", "a0": c.x, "a1": c.x + w, "q0": c.z, "q1": c.z + t, "in": 1.0, "outer": true},
		{"id": "back", "axis": "x", "a0": c.x, "a1": c.x + w, "q0": c.z + d - t, "q1": c.z + d, "in": -1.0, "outer": true},
		{"id": "left", "axis": "z", "a0": c.z + t, "a1": c.z + d - t, "q0": c.x, "q1": c.x + t, "in": 1.0, "outer": true},
		{"id": "right", "axis": "z", "a0": c.z + t, "a1": c.z + d - t, "q0": c.x + w - t, "q1": c.x + w, "in": -1.0, "outer": true}]
	for iw in b.get("walls", []):
		if String(iw.get("room", "")) != String(r["id"]):
			continue
		var bx := Building.inner_box(b, r, iw, Vector3(c.x, 0, c.z))
		if bx.size == Vector3.ZERO:
			continue
		if String(iw.get("axis", "z")) == "z":
			out.append({"id": String(iw["id"]), "axis": "z", "a0": bx.position.z, "a1": bx.end.z, "q0": bx.position.x, "q1": bx.end.x, "in": 1.0, "outer": false})
		else:
			out.append({"id": String(iw["id"]), "axis": "x", "a0": bx.position.x, "a1": bx.end.x, "q0": bx.position.z, "q1": bx.end.z, "in": 1.0, "outer": false})
	return out


## a point along / across a wall -> the room's group frame
static func _g(wl: Dictionary, a: float, q: float) -> Vector2:
	return Vector2(a, q) if wl["axis"] == "x" else Vector2(q, a)


static func _plan(b: Dictionary, s: int, k: float) -> Array:
	var ents := []
	var rooms := []
	for r in b.get("rooms", []):
		if int(r.get("storey", 0)) == s:
			rooms.append(r)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var syms := []
	var labels := []
	var chains := []   # [room, wall, openings] of the outer walls, for the dimension chains
	for r in rooms:
		var c := Vector3(float(r["x"]), 0, float(r["z"])).rotated(Vector3.UP, -deg_to_rad(float(r.get("yaw", 0.0))))
		for wl in room_walls(b, r):
			var obs := []
			for o in b.get("openings", []):
				if String(o.get("room", "")) == String(r["id"]) and String(o.get("wall", "front")) == String(wl["id"]):
					var bx := Building.opening_box(b, r, o)
					var x0 := bx.position.x if wl["axis"] == "x" else bx.position.z
					var x1 := bx.end.x if wl["axis"] == "x" else bx.end.z
					obs.append({"o": o, "lo": x0, "hi": x1})
			obs.sort_custom(func(p, q): return p["lo"] < q["lo"])
			var from: float = wl["a0"]
			var cuts := []
			for ob in obs:
				cuts.append([from, ob["lo"]])
				from = ob["hi"]
			cuts.append([from, wl["a1"]])
			for sg in cuts:
				if float(sg[1]) - float(sg[0]) < 1e-4:
					continue
				var pts := []
				for g in [_g(wl, sg[0], wl["q0"]), _g(wl, sg[1], wl["q0"]), _g(wl, sg[1], wl["q1"]), _g(wl, sg[0], wl["q1"])]:
					var wp := _w(r, g.x, g.y)
					lo = Vector2(minf(lo.x, wp.x), minf(lo.y, wp.y))
					hi = Vector2(maxf(hi.x, wp.x), maxf(hi.y, wp.y))
					pts.append(_pp(k, wp))
				ents.append(_poly(pts, "wall", {"room": String(r["id"]), "wall": String(wl["id"])}))
			for ob in obs:
				syms.append([r, wl, ob])
			if wl["outer"] and not obs.is_empty():
				chains.append([r, wl, obs, c])
	if rooms.is_empty():
		return ents
	for sy in syms:
		ents.append_array(_opening_sym(sy[0], sy[1], sy[2], k))
	# stairs and pieces
	for p in b.get("pieces", []):
		var ps := int(p.get("storey", 0))
		if ps == s:
			ents.append_array(_piece_plan(b, p, k, false))
		elif ps == s - 1 and BuildPieces.is_stairs(p):
			ents.append_array(_piece_plan(b, p, k, true))
	# dimensions
	var R := Rect2(lo, hi - lo)
	var left := R.position.x * k
	var right := R.end.x * k
	var bottom := -R.position.y * k
	var top := -R.end.y * k
	ents.append_array(_dim(Vector2(left, bottom), Vector2(right, bottom), Vector2(0, 1), OVERALL, _m2(R.size.x), {"kind": "overall", "axis": "x"}))
	ents.append_array(_dim(Vector2(right, bottom), Vector2(right, top), Vector2(1, 0), OVERALL, _m2(R.size.y), {"kind": "overall", "axis": "z"}))
	var done := {}
	for ch in chains:
		var r: Dictionary = ch[0]
		var wl: Dictionary = ch[1]
		var c: Vector3 = ch[3]
		if absf(fposmod(float(r.get("yaw", 0.0)) + 0.5, 360.0) - 0.5) > 1e-6:
			continue
		var w := float(r["w"])
		var d := float(r["d"])
		var side: String = wl["id"]
		var on_edge := false
		match side:
			"front": on_edge = absf(c.z - R.position.y) < 1e-4
			"back": on_edge = absf(c.z + d - R.end.y) < 1e-4
			"left": on_edge = absf(c.x - R.position.x) < 1e-4
			"right": on_edge = absf(c.x + w - R.end.x) < 1e-4
		if not on_edge:
			continue
		var s0 := c.x if wl["axis"] == "x" else c.z      # the outer wall's whole run (corner to corner)
		var s1 := c.x + w if wl["axis"] == "x" else c.z + d
		var stops := [s0]
		for ob in ch[2]:
			stops.append(ob["lo"])
			stops.append(ob["hi"])
		stops.append(s1)
		for i in range(1, stops.size()):
			var a: float = stops[i - 1]
			var z: float = stops[i]
			if z - a < 1e-4:
				continue
			var ob = null   # the segment is an opening when it runs from an opening's lo to its hi
			for o2 in ch[2]:
				if absf(float(o2["lo"]) - a) < 1e-9 and absf(float(o2["hi"]) - z) < 1e-9:
					ob = o2
			var pa: Vector2
			var pz: Vector2
			var n: Vector2
			match side:
				"front":
					pa = Vector2(a * k, bottom); pz = Vector2(z * k, bottom); n = Vector2(0, 1)
				"back":
					pa = Vector2(a * k, top); pz = Vector2(z * k, top); n = Vector2(0, -1)
				"left":
					pa = Vector2(left, -a * k); pz = Vector2(left, -z * k); n = Vector2(-1, 0)
				_:
					pa = Vector2(right, -a * k); pz = Vector2(right, -z * k); n = Vector2(1, 0)
			var dd := {"kind": "width" if ob != null else "gap", "wall": side}
			if ob != null:
				dd["id"] = String(ob["o"]["id"])
				done[String(ob["o"]["id"])] = true
			ents.append_array(_dim(pa, pz, n, CHAIN, _m2(z - a), dd))
	# an opening that is not on a chain (an inner wall, a turned room) says its width beside it
	for sy in syms:
		var oid := String(sy[2]["o"]["id"])
		if done.has(oid):
			continue
		var r: Dictionary = sy[0]
		var wl: Dictionary = sy[1]
		var mid_a: float = (float(sy[2]["lo"]) + float(sy[2]["hi"])) * 0.5
		var outer: float = wl["q0"] if float(wl["in"]) > 0.0 else wl["q1"]
		var out_g := _g(wl, mid_a, outer - float(wl["in"]) * 2.0 / k)
		var pw := _pp(k, _w(r, out_g.x, out_g.y))
		ents.append(_text(pw, _m2(float(sy[2]["hi"]) - float(sy[2]["lo"])), 2.0, "m", "dim-text", {"kind": "width", "id": oid, "wall": String(wl["id"])}))
		done[oid] = true
	# the north arrow, right of the plan (+Z is up the sheet)
	var bb := _bounds(ents)
	var np := Vector2(bb.end.x + 10.0, bb.position.y + 12.0)
	var ring: Array = []
	for i in 24:
		ring.append(np + Vector2(cos(TAU * i / 24.0), sin(TAU * i / 24.0)) * 5.0)
	ents.append(_poly(ring, "north"))
	ents.append(_line(np + Vector2(0, 5.0), np + Vector2(0, -5.0), "north"))
	ents.append(_poly([np + Vector2(0, -5.0), np + Vector2(-2.0, 1.0), np + Vector2(2.0, 1.0)], "north-head"))
	ents.append(_text(np + Vector2(0, -7.0), "N", 3.5, "m", "text"))
	return ents


## the symbols of one opening on its wall (group frame -> paper)
static func _opening_sym(r: Dictionary, wl: Dictionary, ob: Dictionary, k: float) -> Array:
	var out := []
	var o: Dictionary = ob["o"]
	var kind := String(o.get("kind", "door"))
	var lo: float = ob["lo"]
	var hi: float = ob["hi"]
	var q0: float = wl["q0"]
	var q1: float = wl["q1"]
	var data := {"id": String(o["id"]), "kind": kind, "room": String(r["id"]), "wall": String(wl["id"])}
	var P := func(a: float, q: float) -> Vector2:
		var g := _g(wl, a, q)
		return _pp(k, _w(r, g.x, g.y))
	out.append(_line(P.call(lo, q0), P.call(lo, q1), "jamb", data))
	out.append(_line(P.call(hi, q0), P.call(hi, q1), "jamb", data))
	if kind == "window":
		for q in [q0, (q0 + q1) * 0.5, q1]:
			out.append(_line(P.call(lo, q), P.call(hi, q), "window", data))
	elif kind == "door":
		var sgn: float = wl["in"]
		var face: float = q1 if sgn > 0.0 else q0
		var hinge: Vector2 = P.call(lo, face)
		var leaf: Vector2 = P.call(lo, face + sgn * (hi - lo))
		var shut: Vector2 = P.call(hi, face)
		out.append(_line(hinge, leaf, "door-leaf", data))
		var a0 := (leaf - hinge).angle()
		var dl := wrapf((shut - hinge).angle() - a0, -PI, PI)
		out.append({"t": "arc", "c": hinge, "r": (hi - lo) * k, "a0": a0, "a1": a0 + dl, "cls": "door-arc", "d": data})
	return out


## a piece in plan: stairs = the treads' outlines + an up arrow, the others = their footprint outline
static func _piece_plan(b: Dictionary, p: Dictionary, k: float, dashed: bool) -> Array:
	var out := []
	var yaw := deg_to_rad(float(p.get("yaw", 0.0)))
	var org := Vector2(float(p["x"]), float(p["z"]))
	var L := func(lx: float, lz: float) -> Vector2:
		var v := Vector3(lx, 0, lz).rotated(Vector3.UP, yaw)
		return _pp(k, Vector2(v.x, v.z) + org)
	var rects := []   # footprints in local (x0, z0, x1, z1)
	if String(p["kind"]) == "ramp":
		var hw := BuildPieces.value(p, "w") * 0.5
		var hd := BuildPieces.value(p, "d") * 0.5
		rects.append([-hw, -hd, hw, hd])
	else:
		for bx in BuildPieces.local_boxes(b, p):
			rects.append([bx.position.x, bx.position.z, bx.end.x, bx.end.z])
	if rects.is_empty():
		return out
	var data := {"piece": String(p["id"]), "kind": String(p["kind"])}
	var x0 := INF
	var z0 := INF
	var x1 := -INF
	var z1 := -INF
	for e in rects:
		x0 = minf(x0, e[0]); z0 = minf(z0, e[1]); x1 = maxf(x1, e[2]); z1 = maxf(z1, e[3])
	if dashed:
		var pts := [L.call(x0, z0), L.call(x1, z0), L.call(x1, z1), L.call(x0, z1)]
		for i in 4:
			out.append(_line(pts[i], pts[(i + 1) % 4], "dashed", data))
		return out
	if BuildPieces.is_stairs(p):
		for e in rects:
			out.append(_poly([L.call(e[0], e[1]), L.call(e[2], e[1]), L.call(e[2], e[3]), L.call(e[0], e[3])], "stairs", data))
		var cen := func(e) -> Vector2:
			return L.call((e[0] + e[2]) * 0.5, (e[1] + e[3]) * 0.5)
		var way := [cen.call(rects[0])]
		if String(p["kind"]) == "stairs_l":
			way.append(cen.call(rects[int(BuildPieces.stairs_numbers(b, p)["a"])]))
		way.append(cen.call(rects[rects.size() - 1]))
		for i in range(1, way.size()):
			out.append(_line(way[i - 1], way[i], "stairs-arrow", data))
		var tip: Vector2 = way[way.size() - 1]
		var dir: Vector2 = (tip - way[way.size() - 2]).normalized()
		for sgn in [-1.0, 1.0]:
			out.append(_line(tip, tip - dir.rotated(sgn * 0.45) * 3.0, "stairs-arrow", data))
		var start_dir: Vector2 = (way[1] - way[0]).normalized()
		out.append(_text(way[0] - start_dir * 5.2, "UP", 2.2, "m", "text", data))   # just before the arrow's tail, clear of the flight's outline
	else:
		out.append(_poly([L.call(x0, z0), L.call(x1, z0), L.call(x1, z1), L.call(x0, z1)], "piece", data))
		out.append(_text(L.call((x0 + x1) * 0.5, (z0 + z1) * 0.5) + Vector2(0, 0.8), String(BuildPieces.DEFS[String(p["kind"])]["label"]), 1.8, "m", "text", data))
	return out


# ---------------------------------------------------------------- the elevations

static func _elev(b: Dictionary, which: String, k: float) -> Array:
	var front := which == "front"
	var ents := []
	var P := func(w: Vector3) -> Vector2:   # a world point -> paper
		return Vector2((w.x if front else -w.z) * k, -w.y * k)
	var umin := INF
	var umax := -INF
	var ytop := 0.0
	var rooms: Array = b.get("rooms", []).duplicate()
	rooms.sort_custom(func(p, q): return int(p.get("storey", 0)) < int(q.get("storey", 0)))
	for r in rooms:
		var yaw := deg_to_rad(float(r.get("yaw", 0.0)))
		var c := Vector3(float(r["x"]), 0, float(r["z"])).rotated(Vector3.UP, -yaw)
		var y0 := Building.base_y(b, r)
		var h := Building.num(b, r.get("height"), 2.7)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for g in [Vector2(0, 0), Vector2(float(r["w"]), 0), Vector2(float(r["w"]), float(r["d"])), Vector2(0, float(r["d"]))]:
			for y in [y0, y0 + h]:
				var v := Vector3(c.x + g.x, y, c.z + g.y).rotated(Vector3.UP, yaw)
				var q: Vector2 = P.call(v)
				lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
				hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		umin = minf(umin, lo.x / k)
		umax = maxf(umax, hi.x / k)
		ytop = maxf(ytop, y0 + h)
		ents.append(_poly([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)], "elev-wall", {"room": String(r["id"])}))
	for r in rooms:   # the openings facing the viewer
		var yaw := deg_to_rad(float(r.get("yaw", 0.0)))
		for o in b.get("openings", []):
			if String(o.get("room", "")) != String(r["id"]) or not Building.WALLS.has(String(o.get("wall", ""))):
				continue
			var gn := {"front": Vector3(0, 0, -1), "back": Vector3(0, 0, 1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}[String(o["wall"])] as Vector3
			var wn := gn.rotated(Vector3.UP, yaw)
			if not ((front and wn.z < -0.7) or (not front and wn.x > 0.7)):
				continue
			var bx := Building.opening_box(b, r, o)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for cx in [bx.position.x, bx.end.x]:
				for cz in [bx.position.z, bx.end.z]:
					for cy in [bx.position.y, bx.end.y]:
						var q: Vector2 = P.call(Vector3(cx, cy, cz).rotated(Vector3.UP, yaw))
						lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
						hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
			var kind := String(o.get("kind", "door"))
			var data := {"id": String(o["id"]), "kind": kind, "room": String(r["id"])}
			ents.append(_poly([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)], "elev-" + kind, data))
			if kind == "window":
				ents.append(_line(Vector2((lo.x + hi.x) * 0.5, lo.y), Vector2((lo.x + hi.x) * 0.5, hi.y), "window", data))
				ents.append(_line(Vector2(lo.x, (lo.y + hi.y) * 0.5), Vector2(hi.x, (lo.y + hi.y) * 0.5), "window", data))
			ents.append(_text(Vector2((lo.x + hi.x) * 0.5, lo.y - 1.2), _m2((hi.x - lo.x) / k), 2.0, "m", "dim-text", {"kind": "width", "id": String(o["id"])}))
	var uall0 := umin
	var uall1 := umax
	var rs := Building.roof_solid(b)
	if not rs.is_empty():
		var pr := PackedVector2Array()
		for v in rs["verts"]:
			var q: Vector2 = P.call(v)
			pr.append(q)
			uall0 = minf(uall0, q.x / k)
			uall1 = maxf(uall1, q.x / k)
			ytop = maxf(ytop, (v as Vector3).y)
		var hull := Geometry2D.convex_hull(pr)
		if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
			hull.remove_at(hull.size() - 1)
		ents.append(_poly(Array(hull), "roof", {"kind": String(b["roof"].get("kind", "gable"))}))
		var seen := {}
		for f in rs["faces"]:
			for i in f.size():
				var pa: Vector2 = P.call(rs["verts"][f[i]])
				var pb: Vector2 = P.call(rs["verts"][f[(i + 1) % f.size()]])
				if pa.distance_to(pb) < 1e-3:
					continue
				var key := "%d,%d,%d,%d" % [roundi(pa.x * 100), roundi(pa.y * 100), roundi(pb.x * 100), roundi(pb.y * 100)]
				var rkey := "%d,%d,%d,%d" % [roundi(pb.x * 100), roundi(pb.y * 100), roundi(pa.x * 100), roundi(pa.y * 100)]
				if seen.has(key) or seen.has(rkey):
					continue
				seen[key] = true
				ents.append(_line(pa, pb, "roof-edge"))
	# the ground, with its hatch
	var g0 := (uall0 - 1.0) * k
	var g1 := (uall1 + 1.0) * k
	ents.append(_line(Vector2(g0, 0), Vector2(g1, 0), "ground"))
	var hx := g0
	while hx < g1:
		ents.append(_line(Vector2(hx + 2.0, 0.3), Vector2(hx, 2.3), "ground-hatch"))
		hx += 1.8
	# dimensions: overall width under the ground, overall height on the right, the floor levels on the left
	ents.append_array(_dim(Vector2(umin * k, 2.3), Vector2(umax * k, 2.3), Vector2(0, 1), 8.0, _m2(umax - umin), {"kind": "overall", "axis": "u"}))
	ents.append_array(_dim(Vector2(g1, 0), Vector2(g1, -ytop * k), Vector2(1, 0), 8.0, _m2(ytop), {"kind": "overall", "axis": "y"}))
	var levels := [0.0]
	for s in range(1, Building.storey_count(b)):
		levels.append(float(s) * Building.num(b, "floor_height", 2.8))
	for y in levels:
		var ly: float = -y * k
		ents.append(_line(Vector2(g0 - 9.0, ly), Vector2(g0 - 2.0, ly), "level"))
		ents.append(_text(Vector2(g0 - 10.0, ly - 0.8), "%+.2f" % y, 2.2, "r", "text", {"kind": "level"}))
	return ents


# ---------------------------------------------------------------- the frame and the title block

static func _frame(b: Dictionary, tab: String, paper: String, denom: int, idx: int, count: int) -> Array:
	var P: Vector2 = paper_size(paper)
	var out := []
	out.append(_poly([Vector2(MARGIN, MARGIN), Vector2(P.x - MARGIN, MARGIN), Vector2(P.x - MARGIN, P.y - MARGIN), Vector2(MARGIN, P.y - MARGIN)], "border"))
	var y0 := P.y - MARGIN - TB_H
	out.append(_line(Vector2(MARGIN, y0), Vector2(P.x - MARGIN, y0), "title"))
	var W := P.x - 2.0 * MARGIN
	var cells := [["PROJECT", String(b.get("name", "Untitled")), 0.30], ["SHEET  (dimensions in metres)", title_of(tab), 0.30], ["SCALE", "1:%d" % denom, 0.10],
		["DATE", Time.get_date_string_from_system(), 0.14], ["DRAWN WITH", "Kine", 0.16]]
	var x := MARGIN
	for i in cells.size():
		var cw: float = W * float(cells[i][2])
		if i > 0:
			out.append(_line(Vector2(x, y0), Vector2(x, y0 + TB_H), "title"))
		out.append(_text(Vector2(x + 2.0, y0 + 4.5), String(cells[i][0]), 2.0, "l", "title-label"))
		var val := String(cells[i][1])
		var th := 5.0
		while th > 2.5 and val.length() * 0.55 * th > cw - 4.0:
			th -= 0.5
		out.append(_text(Vector2(x + 2.0, y0 + 14.5), val, th, "l", "title-text", {"field": String(cells[i][0]).get_slice(" ", 0).to_lower()}))
		if i == 1:
			out.append(_text(Vector2(x + 2.0, y0 + 21.0), "%s   %d / %d" % [paper, idx, count], 2.4, "l", "title-label", {"field": "size"}))
		x += cw
	return out


# ---------------------------------------------------------------- SVG

static func _n(v: float) -> String:
	return String.num(snappedf(v, 0.001), 3)


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


static func _attrs(cls: String, d: Dictionary) -> String:
	var s := ' class="%s"' % cls
	for key in d:
		s += ' data-%s="%s"' % [key, _esc(str(d[key]))]
	return s


## the sheet as SVG: 1 user unit = 1 mm, the width and height in mm (exact at scale)
static func to_svg(sh: Dictionary) -> String:
	var o := PackedStringArray()
	o.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
	o.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%smm\" height=\"%smm\" viewBox=\"0 0 %s %s\">" % [_n(sh["w"]), _n(sh["h"]), _n(sh["w"]), _n(sh["h"])])
	o.append("<title>%s - %s</title>" % [_esc(String(sh["name"])), _esc(String(sh["title"]))])
	o.append("<rect x=\"0\" y=\"0\" width=\"%s\" height=\"%s\" fill=\"#ffffff\"/>" % [_n(sh["w"]), _n(sh["h"])])
	o.append("<g id=\"sheet\" data-paper=\"%s\" data-scale=\"1:%d\" data-denom=\"%d\" data-mm-per-m=\"%s\" data-units=\"mm\">" % [sh["paper"], sh["denom"], sh["denom"], _n(sh["k"])])
	for e in sh["ents"]:
		var cls := String(e["cls"])
		var st := style(cls)
		var stroke := String(st.get("stroke", "#000000"))
		var sw := _n(float(st.get("w", 0.2)))
		var dash := ""
		if float(st.get("dash", 0.0)) > 0.0:
			dash = " stroke-dasharray=\"%s %s\"" % [_n(st["dash"]), _n(float(st["dash"]) * 0.7)]
		var a := _attrs(cls, e["d"])
		match String(e["t"]):
			"line":
				o.append("<line%s x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"%s\" stroke-width=\"%s\"%s/>" % [a, _n(e["a"].x), _n(e["a"].y), _n(e["b"].x), _n(e["b"].y), stroke, sw, dash])
			"poly":
				var pts := []
				for v in e["pts"]:
					pts.append("%s,%s" % [_n(v.x), _n(v.y)])
				o.append("<polygon%s points=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"miter\"%s/>" % [a, " ".join(pts), String(st.get("fill", "none")), stroke, sw, dash])
			"arc":
				var c: Vector2 = e["c"]
				var r := float(e["r"])
				var a0 := float(e["a0"])
				var a1 := float(e["a1"])
				var sp := c + Vector2(cos(a0), sin(a0)) * r
				var ep := c + Vector2(cos(a1), sin(a1)) * r
				o.append("<path%s data-r=\"%s\" d=\"M %s %s A %s %s 0 %d %d %s %s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\"/>" % [a, _n(r), _n(sp.x), _n(sp.y), _n(r), _n(r), 1 if absf(a1 - a0) > PI else 0, 1 if a1 > a0 else 0, _n(ep.x), _n(ep.y), stroke, sw])
			"text":
				var anchor := {"l": "start", "m": "middle", "r": "end"}[String(e["anc"])] as String
				var p: Vector2 = e["p"]
				var tr := "" if float(e["rot"]) == 0.0 else " transform=\"rotate(%s %s %s)\"" % [_n(e["rot"]), _n(p.x), _n(p.y)]
				o.append("<text%s x=\"%s\" y=\"%s\" font-family=\"Arial, Helvetica, sans-serif\" font-size=\"%s\" text-anchor=\"%s\" fill=\"%s\"%s>%s</text>" % [a, _n(p.x), _n(p.y), _n(e["h"]), anchor, stroke, tr, _esc(String(e["s"]))])
	o.append("</g>")
	o.append("</svg>")
	return "\n".join(o) + "\n"


# ---------------------------------------------------------------- DXF (R12 ASCII: LINE / ARC / TEXT, millimetres, y up)

static func to_dxf(sh: Dictionary) -> String:
	var o := PackedStringArray()
	var g := func(code: int, v: Variant):
		o.append(str(code))
		o.append(v if v is String else (_n(v) if v is float else str(v)))
	var layers := {}
	for e in sh["ents"]:
		layers[_layer(String(e["cls"]))] = true
	g.call(0, "SECTION")
	g.call(2, "HEADER")
	g.call(9, "$ACADVER")
	g.call(1, "AC1009")
	g.call(0, "ENDSEC")
	g.call(0, "SECTION")
	g.call(2, "TABLES")
	g.call(0, "TABLE")
	g.call(2, "LAYER")
	g.call(70, layers.size())
	for ly in layers:
		g.call(0, "LAYER")
		g.call(2, ly)
		g.call(70, 0)
		g.call(62, 7)
		g.call(6, "CONTINUOUS")
	g.call(0, "ENDTAB")
	g.call(0, "ENDSEC")
	g.call(0, "SECTION")
	g.call(2, "ENTITIES")
	var seg := func(a: Vector2, c: Vector2, ly: String):
		g.call(0, "LINE")
		g.call(8, ly)
		g.call(10, a.x)
		g.call(20, -a.y)
		g.call(30, 0.0)
		g.call(11, c.x)
		g.call(21, -c.y)
		g.call(31, 0.0)
	for e in sh["ents"]:
		var ly := _layer(String(e["cls"]))
		match String(e["t"]):
			"line":
				seg.call(e["a"], e["b"], ly)
			"poly":
				var pts: PackedVector2Array = e["pts"]
				for i in pts.size():
					seg.call(pts[i], pts[(i + 1) % pts.size()], ly)
			"arc":
				var c: Vector2 = e["c"]
				var a0 := rad_to_deg(float(e["a0"]))
				var a1 := rad_to_deg(float(e["a1"]))
				var s0 := -maxf(a0, a1)   # y flipped: the sweep runs the other way, counter-clockwise from -max to -min
				var s1 := -minf(a0, a1)
				g.call(0, "ARC")
				g.call(8, ly)
				g.call(10, c.x)
				g.call(20, -c.y)
				g.call(30, 0.0)
				g.call(40, float(e["r"]))
				g.call(50, fposmod(s0, 360.0))
				g.call(51, fposmod(s1, 360.0))
			"text":
				var p: Vector2 = e["p"]
				var h := float(e["h"])
				var w := String(e["s"]).length() * 0.55 * h
				var shift := 0.0 if e["anc"] == "l" else (-w * 0.5 if e["anc"] == "m" else -w)
				var rot := -float(e["rot"])
				var dir := Vector2.from_angle(deg_to_rad(rot))
				var q := Vector2(p.x, -p.y) + dir * shift
				g.call(0, "TEXT")
				g.call(8, ly)
				g.call(10, q.x)
				g.call(20, q.y)
				g.call(30, 0.0)
				g.call(40, h)
				g.call(1, String(e["s"]))
				g.call(50, rot)
	g.call(0, "ENDSEC")
	g.call(0, "EOF")
	return "\n".join(o) + "\n"


static func _layer(cls: String) -> String:
	return cls.to_upper().replace("-", "_")


# ---------------------------------------------------------------- files

static func file_name(b: Dictionary, tab: String, ext: String) -> String:
	var nm := String(b.get("name", "building")).to_lower()
	var slug := ""
	for ch in nm:
		slug += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return "%s_%s.%s" % [slug if slug != "" else "building", tab.to_lower().replace(" ", ""), ext]


## writes text to dir/<name>_<tab>.<ext>; the path ("" when it could not be written)
static func save_text(b: Dictionary, tab: String, ext: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/%s" % [dir, file_name(b, tab, ext)]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return path


## the PNG's size in pixels at 300 dpi
static func png_size(sh: Dictionary) -> Vector2i:
	return Vector2i(roundi(float(sh["w"]) / 25.4 * 300.0), roundi(float(sh["h"]) / 25.4 * 300.0))
