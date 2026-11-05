class_name AssemblyDraw
extends RefCounted
## G30/G31: an Assembly record -> Blueprint sheets. Drawing views project the exact OCCT B-rep edges after the Assembly pose;
## straight edges are exact, arcs use their exact end/mid points (closed circles are reconstructed), and overall dimensions use
## KCad.bounds doubles, never the preview mesh. The section cut uses SectionLook's {"n", "w"} plane convention: n.p > w is removed.
## Schematics read optional ratings on each part's rec (v/kv, mva, w, rail, kind, powered) and optional Assembly "wires"
## [{"a", "b", "kind": "power"|"signal", "label"}]. Records without these keys are unchanged and simply draw as plain blocks.
const B := preload("res://scripts/build/blueprint.gd")
const KCad := preload("res://scripts/kcad.gd")
const DENOMS := [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]


# ---------------------------------------------------------------- exact solids, measurement and section
static func _pose(id: int, p: Dictionary) -> int:
	var xf := Assembly.xf_of(p)
	var e := xf.basis.get_euler()
	var out := id
	for step in [[Vector3.BACK, e.z], [Vector3.UP, e.y], [Vector3.RIGHT, e.x]]:
		if absf(float(step[1])) > 1e-9:
			var t := KCad.rotate(out, step[0], float(step[1]))
			if t != 0:
				if out != id:
					KCad.release(out)
				out = t
	var moved := KCad.translate(out, xf.origin)
	if moved != 0:
		if out != id:
			KCad.release(out)
		out = moved
	if out != id:
		KCad.release(id)
	return out


static func _geometry(asm: Dictionary) -> Dictionary:
	var g := {"solids": [], "bounds": PackedFloat64Array(), "part_bounds": {}}
	for p in asm.get("parts", []):
		var res := Part.replay(p["rec"], -1, {"keep": true})
		var ids: Array = []
		for idv in res.get("ids", []):
			var id := _pose(int(idv), p)
			ids.append(id)
			g["solids"].append({"id": id, "part": p})
		g["part_bounds"][String(p["id"])] = _bounds(ids)
	g["bounds"] = _bounds((g["solids"] as Array).map(func(s): return int(s["id"])))
	return g


static func _bounds(ids: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array([INF, INF, INF, -INF, -INF, -INF])
	for idv in ids:
		var b := KCad.bounds(int(idv))
		if b.size() != 6:
			continue
		for i in 3:
			out[i] = minf(out[i], b[i])
			out[i + 3] = maxf(out[i + 3], b[i + 3])
	return PackedFloat64Array() if out[0] == INF else out


static func _release(g: Dictionary) -> void:
	for s in g.get("solids", []):
		KCad.release(int(s["id"]))


static func _default_cut(b: PackedFloat64Array) -> Dictionary:
	if b.size() != 6:
		return {"n": Vector3.BACK, "w": 0.0}
	return {"n": Vector3.BACK, "w": (b[2] + b[5]) * 0.5}


static func _cut_geo(g: Dictionary, cut: Dictionary) -> void:
	if cut.is_empty() or (g["bounds"] as PackedFloat64Array).size() != 6:
		return
	var b: PackedFloat64Array = g["bounds"]
	var n: Vector3 = (cut.get("n", Vector3.BACK) as Vector3).normalized()
	var size := Vector3(b[3] - b[0], b[4] - b[1], b[5] - b[2]).length() * 2.0 + 1.0
	var tool := KCad.box(size, size, size)
	var axis := Vector3.BACK.cross(n)
	var rot := Basis.IDENTITY
	if axis.length() > 1e-8:
		rot = Basis(axis.normalized(), Vector3.BACK.angle_to(n))
	elif n.dot(Vector3.BACK) < 0.0:
		rot = Basis(Vector3.RIGHT, PI)
	var e := rot.get_euler()
	for step in [[Vector3.BACK, e.z], [Vector3.UP, e.y], [Vector3.RIGHT, e.x]]:
		if absf(float(step[1])) > 1e-9:
			var t := KCad.rotate(tool, step[0], float(step[1]))
			if t != 0:
				KCad.release(tool)
				tool = t
	var u := rot * Vector3.RIGHT
	var v := rot * Vector3.UP
	var origin := n * float(cut.get("w", 0.0)) - (u + v) * (size * 0.5)
	var moved := KCad.translate(tool, origin)
	if moved != 0:
		KCad.release(tool)
		tool = moved
	for s in g["solids"]:
		var kept := KCad.cut(int(s["id"]), tool)
		if kept != 0:
			KCad.release(int(s["id"]))
			s["id"] = kept
	KCad.release(tool)


static func _size_mm(b: PackedFloat64Array, axis: int) -> float:
	return (b[axis + 3] - b[axis]) * 1000.0 if b.size() == 6 else 0.0


# ---------------------------------------------------------------- orthographic B-rep projection
static func _basis(n: Vector3) -> Array:
	var nn := n.normalized()
	var u := Vector3.UP.cross(nn)
	if u.length() < 0.01:
		u = Vector3.RIGHT
	u = u.normalized()
	var v := nn.cross(u).normalized()
	return [u, v]


static func _point(p: Vector3, basis: Array, k: float) -> Vector2:
	return Vector2(p.dot(basis[0]), -p.dot(basis[1])) * k


static func _arc3(a: Vector2, mid: Vector2, b: Vector2, cls: String, data: Dictionary) -> Array:
	var d := 2.0 * (a.x * (mid.y - b.y) + mid.x * (b.y - a.y) + b.x * (a.y - mid.y))
	if absf(d) < 1e-9:
		return [B._line(a, b, cls, data)]
	var aa := a.length_squared()
	var mm := mid.length_squared()
	var bb := b.length_squared()
	var c := Vector2((aa * (mid.y - b.y) + mm * (b.y - a.y) + bb * (a.y - mid.y)) / d,
		(aa * (b.x - mid.x) + mm * (a.x - b.x) + bb * (mid.x - a.x)) / d)
	var r := c.distance_to(a)
	var a0 := (a - c).angle()
	var am := (mid - c).angle()
	var a1 := (b - c).angle()
	var forward := fposmod(a1 - a0, TAU)
	if fposmod(am - a0, TAU) > forward + 1e-6:
		forward = -fposmod(a0 - a1, TAU)
	return [{"t": "arc", "c": c, "r": r, "a0": a0, "a1": a0 + forward, "cls": cls, "d": data}]


static func _edge_entities(e: Dictionary, basis: Array, k: float, cls: String, data: Dictionary) -> Array:
	var a := _point(e["a"], basis, k)
	var mid := _point(e["center"], basis, k)
	var b := _point(e["b"], basis, k)
	if a.distance_to(b) < 1e-7:
		var c := (a + mid) * 0.5
		var r := a.distance_to(mid) * 0.5
		if r > 1e-6:
			return [{"t": "arc", "c": c, "r": r, "a0": (a - c).angle(), "a1": (a - c).angle() + TAU, "cls": cls, "d": data}]
	if a.distance_to(b) < 1e-6:
		return []
	return _arc3(a, mid, b, cls, data)


static func _project_box(b: PackedFloat64Array, basis: Array, k: float) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	if b.size() != 6:
		return Rect2()
	for i in 8:
		var p := Vector3(b[0] if i & 1 == 0 else b[3], b[1] if i & 2 == 0 else b[4], b[2] if i & 4 == 0 else b[5])
		var q := _point(p, basis, k)
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	return Rect2(lo, hi - lo)


static func _projection(g: Dictionary, which: String, n: Vector3, k: float, label_names: bool) -> Array:
	var out: Array = []
	var basis := _basis(n)
	for s in g["solids"]:
		var p: Dictionary = s["part"]
		var data := {"view": which, "part": String(p["id"])}
		var cls := "piece"
		if which == "section":
			data["section"] = "cut"
			cls = "wall"
		for e in KCad.edges(int(s["id"])):
			out.append_array(_edge_entities(e, basis, k, cls, data))
	# Labels come from exact part boxes, so they follow poses too. Large assemblies use ids to remain legible.
	if which != "section":
		for p in g.get("parts", []):
			var id := String(p["id"])
			var b: PackedFloat64Array = g["part_bounds"].get(id, PackedFloat64Array())
			if b.size() != 6:
				continue
			var c := Vector3((b[0] + b[3]) * 0.5, (b[1] + b[4]) * 0.5, (b[2] + b[5]) * 0.5)
			var label := String(p["name"]) if label_names else id
			out.append(B._text(_point(c, basis, k) + Vector2(0, 0.8), label, 1.8 if not label_names else 2.0, "m", "callout-text", {"view": which, "part": id, "label": "part"}))
	var bb := _project_box(g["bounds"], basis, k)
	var title := {"plan": "PLAN / TOP", "front": "FRONT", "section": "SECTION A-A"}[which] as String
	out.append(B._text(Vector2(bb.get_center().x, bb.position.y - 12.0), title, 3.0, "m", "title-text", {"view": which, "label": "view"}))
	var off := 8.0
	if which == "plan":
		out.append_array(B._dim(Vector2(bb.position.x, bb.end.y), Vector2(bb.end.x, bb.end.y), Vector2(0, 1), off, "%.3f mm" % _size_mm(g["bounds"], 0), {"view": which, "kind": "overall", "axis": "x", "value_mm": _size_mm(g["bounds"], 0)}))
		out.append_array(B._dim(bb.end, Vector2(bb.end.x, bb.position.y), Vector2(1, 0), off, "%.3f mm" % _size_mm(g["bounds"], 2), {"view": which, "kind": "overall", "axis": "z", "value_mm": _size_mm(g["bounds"], 2)}))
	else:
		out.append_array(B._dim(Vector2(bb.position.x, bb.end.y), Vector2(bb.end.x, bb.end.y), Vector2(0, 1), off, "%.3f mm" % _size_mm(g["bounds"], 0), {"view": which, "kind": "overall", "axis": "x", "value_mm": _size_mm(g["bounds"], 0)}))
		out.append_array(B._dim(bb.end, Vector2(bb.end.x, bb.position.y), Vector2(1, 0), off, "%.3f mm" % _size_mm(g["bounds"], 1), {"view": which, "kind": "overall", "axis": "y", "value_mm": _size_mm(g["bounds"], 1)}))
	return out


static func _choose_denom(b: PackedFloat64Array) -> int:
	if b.size() != 6:
		return 1
	var w := maxf(b[3] - b[0], b[5] - b[2])
	var h := maxf(b[5] - b[2], b[4] - b[1])
	for d in DENOMS:
		var k := 1000.0 / float(d)
		if w * k <= 94.0 and h * k <= 80.0:
			return int(d)
	return 10000


static func _mass_g(asm: Dictionary) -> float:
	for p in asm.get("parts", []):
		if (p.get("rec", {}) as Dictionary).has("bom"):
			return float(AssemblyBom.bom(asm)["mass_kg"]) * 1000.0
	return -1.0


static func sheet(asm: Dictionary, opts := {}) -> Dictionary:
	var g := _geometry(asm)
	g["parts"] = asm.get("parts", [])
	var denom := int(opts.get("denom", _choose_denom(g["bounds"])))
	var k := 1000.0 / float(maxi(denom, 1))
	var names := (asm.get("parts", []) as Array).size() <= 12
	var views: Array = []
	views.append(_projection(g, "plan", Vector3.UP, k, names))
	views.append(_projection(g, "front", Vector3.BACK, k, names))
	var cut: Dictionary = opts.get("cut", _default_cut(g["bounds"]))
	_cut_geo(g, cut)
	var section_n: Vector3 = cut.get("n", Vector3.BACK)
	views.append(_projection(g, "section", section_n, k, false))
	_release(g)
	var centres := [Vector2(72, 104), Vector2(205, 104), Vector2(333, 104)]
	var ents: Array = []
	for i in views.size():
		var bb := B._bounds(views[i])
		ents.append_array(B._shift(views[i], centres[i] - bb.get_center()))
	ents.append(B._text(Vector2(20, 224), "OCCT B-rep edge projection; exact-solid bounds. Section: SectionLook plane n.p = w, n.p > w removed. Dimensions in mm.", 2.1, "l", "text"))
	var mass: float = _mass_g(asm)
	if mass >= 0.0:
		ents.append(B._text(Vector2(20, 232), "MODEL MASS %.3f g (exact solids x BOM densities)" % mass, 2.5, "l", "title-text", {"kind": "mass", "value_g": mass}))
	var title := "Assembly plan / front / section"
	ents.append_array(B._frame(asm, "Front", "A3", denom, 1, 1))
	for e in ents:
		if e["t"] == "text" and e["d"].get("field", "") == "sheet":
			e["s"] = title
		if e["t"] == "text" and String(e["s"]).begins_with("SHEET"):
			e["s"] = "SHEET (dimensions in mm)"
	var P := B.paper_size("A3")
	return {"paper": "A3", "w": P.x, "h": P.y, "denom": denom, "k": k, "tab": "Drawing", "title": title, "name": String(asm.get("name", "Assembly")), "ents": ents, "area": B._area("A3")}


# ---------------------------------------------------------------- rated blocks, wires and schematic layout
static func _rec(p: Dictionary) -> Dictionary:
	return p.get("rec", {}) as Dictionary


static func _powered(rec: Dictionary) -> bool:
	if ["battery", "generator", "grid", "source"].has(String(rec.get("kind", "")).to_lower()):
		return false
	return bool(rec.get("powered", false)) or rec.has("w")


static func validate_schematic(asm: Dictionary) -> Array:
	var errors: Array = []
	var ids := {}
	for p in asm.get("parts", []):
		ids[String(p["id"])] = p
	var valid_power: Array = []
	for w in asm.get("wires", []):
		var a := String(w.get("a", ""))
		var b := String(w.get("b", ""))
		if not ids.has(a) or not ids.has(b):
			errors.append({"kind": "unknown-endpoint", "part": b if not ids.has(b) else a, "why": "wire %s -> %s names a missing part" % [a, b]})
		elif String(w.get("kind", "power")) == "power":
			valid_power.append([a, b])
	for id in ids:
		var rec := _rec(ids[id])
		var kind := String(rec.get("kind", "")).to_lower()
		if (kind == "transformer" and float(rec.get("mva", 0.0)) <= 0.0) or (["bus", "grid"].has(kind) and float(rec.get("v", rec.get("kv", 0.0))) <= 0.0):
			errors.append({"kind": "missing-rating", "part": id, "why": "MISSING RATING: " + id})
		if _powered(rec):
			var connected := false
			for w in valid_power:
				if w[0] == id or w[1] == id:
					connected = true
			if not connected:
				errors.append({"kind": "no-power", "part": id, "why": "NO POWER: " + id})
	return errors


static func _ratings(rec: Dictionary) -> Array:
	var out: Array = []
	for key in ["v", "kv", "mva", "w", "rail"]:
		if not rec.has(key):
			continue
		var default_unit := "kV" if key == "kv" else ("V" if key == "v" else ("MVA" if key == "mva" else "W"))
		var unit := String(rec.get("unit", default_unit)) if key == "v" or key == "kv" else default_unit
		if key == "rail":
			out.append("rail %s" % str(rec[key]))
		else:
			out.append("%s %s" % [String.num(float(rec[key])), unit])
	return out


static func _layers(asm: Dictionary) -> Dictionary:
	# Shortest paths from real sources, not longest-path relaxation: electrical ties and breaker loops are cyclic.
	var layers := {}
	var incoming := {}
	var wires: Array = []
	for p in asm.get("parts", []):
		var id := String(p["id"])
		var rec := _rec(p)
		if ["battery", "generator", "grid", "source"].has(String(rec.get("kind", "")).to_lower()):
			layers[id] = 0
	for w in asm.get("wires", []):
		var a := String(w.get("a", ""))
		var b := String(w.get("b", ""))
		if String(w.get("kind", "power")) != "power":
			continue
		wires.append([a, b])
		incoming[b] = true
	for p in asm.get("parts", []):
		var id := String(p["id"])
		if not incoming.has(id) and not layers.has(id):
			layers[id] = 0
	var queue: Array = layers.keys()
	while not queue.is_empty():
		var a := String(queue.pop_front())
		for w in wires:
			if w[0] == a and not layers.has(w[1]):
				layers[w[1]] = int(layers[a]) + 1
				queue.append(w[1])
	# A completely cyclic island still gets a deterministic column and is never allowed to run to infinity.
	var next_layer := 0
	for v in layers.values():
		next_layer = maxi(next_layer, int(v) + 1)
	for p in asm.get("parts", []):
		var id := String(p["id"])
		if not layers.has(id):
			layers[id] = next_layer
	return layers


static func _block(ents: Array, id: String, rec: Dictionary, c: Vector2, w: float, h: float) -> void:
	var kind := String(rec.get("kind", "block")).to_lower()
	var data := {"block": id, "kind": kind}
	if ["bus", "grid"].has(kind):
		ents.append(B._line(c + Vector2(-w * 0.5, 0), c + Vector2(w * 0.5, 0), "border", data))
	elif kind == "transformer":
		for side in [-1.0, 1.0]:
			var pts: Array = []
			for i in 32:
				pts.append(c + Vector2(side * 4.0, 0) + Vector2(cos(TAU * i / 32.0), sin(TAU * i / 32.0)) * 4.0)
			ents.append(B._poly(pts, "piece", data))
	elif kind == "breaker":
		ents.append(B._poly([c + Vector2(-4, -4), c + Vector2(4, -4), c + Vector2(4, 4), c + Vector2(-4, 4)], "piece", data))
	elif kind == "generator":
		var pts: Array = []
		for i in 40:
			pts.append(c + Vector2(cos(TAU * i / 40.0), sin(TAU * i / 40.0)) * 6.0)
		ents.append(B._poly(pts, "piece", data))
		ents.append(B._text(c + Vector2(0, 1), "G", 3.0, "m", "title-text", data))
	else:
		ents.append(B._poly([c + Vector2(-w / 2, -h / 2), c + Vector2(w / 2, -h / 2), c + Vector2(w / 2, h / 2), c + Vector2(-w / 2, h / 2)], "piece", data))
	ents.append(B._text(c + Vector2(0, -h * 0.5 - 1.5), id, 2.0, "m", "title-text", data))
	var ratings := _ratings(rec)
	for i in ratings.size():
		ents.append(B._text(c + Vector2(0, h * 0.5 + 3.0 + i * 3.0), String(ratings[i]), 1.65, "m", "text", data))


static func schematic_sheet(asm: Dictionary, _opts := {}) -> Dictionary:
	var layers := _layers(asm)
	var counts := {}
	var subs := {}
	var max_layer := 0
	var max_sub := 1
	for p in asm.get("parts", []):
		var id := String(p["id"])
		var layer := int(layers.get(id, 0))
		var count := int(counts.get(layer, 0))
		var sub := int(count / 6)
		var row := count % 6
		counts[layer] = count + 1
		subs[layer] = sub + 1
		max_sub = maxi(max_sub, sub + 1)
		max_layer = maxi(max_layer, layer)
		layers[id] = [layer, row, sub]
	var places := {}
	var column_step := 330.0 / maxi(max_layer + 1, 1)
	var sub_step := minf(58.0, column_step / max_sub)
	var bw := clampf(sub_step - 4.0, 24.0, 54.0)
	var bh := 18.0
	for p in asm.get("parts", []):
		var id := String(p["id"])
		var lr: Array = layers[id]
		var base := lerpf(55.0, 365.0, float(lr[0]) / maxi(max_layer, 1))
		var sub_count := int(subs[lr[0]])
		var x := base + (float(lr[2]) - float(sub_count - 1) * 0.5) * sub_step
		x = clampf(x, 14.0 + bw * 0.5, 406.0 - bw * 0.5)
		var y := 38.0 + float(lr[1]) * 34.0
		places[id] = Vector2(x, y)
	var ents: Array = []
	for w in asm.get("wires", []):
		var a := String(w.get("a", ""))
		var b := String(w.get("b", ""))
		if not places.has(a) or not places.has(b):
			continue
		var kind := String(w.get("kind", "power"))
		var data := {"a": a, "b": b, "wire": kind}
		var cls := "dim" if kind == "power" else "dashed"
		var pa: Vector2 = places[a]
		var pb: Vector2 = places[b]
		if absf(pa.x - pb.x) > 1.0 and absf(pa.y - pb.y) > 1.0:
			var elbow := Vector2((pa.x + pb.x) * 0.5, pa.y)
			var elbow2 := Vector2(elbow.x, pb.y)
			ents.append(B._line(pa, elbow, cls, data))
			ents.append(B._line(elbow, elbow2, cls, data))
			ents.append(B._line(elbow2, pb, cls, data))
		else:
			ents.append(B._line(pa, pb, cls, data))
		if String(w.get("label", "")) != "":
			ents.append(B._text((places[a] + places[b]) * 0.5 + Vector2(0, -1.5), String(w["label"]), 1.5, "m", "text", data))
	for p in asm.get("parts", []):
		var id := String(p["id"])
		_block(ents, id, _rec(p), places[id], bw, bh)
	var errors := validate_schematic(asm)
	for i in mini(errors.size(), 5):
		ents.append(B._text(Vector2(20, 225 + i * 5), String(errors[i]["why"]), 2.2, "l", "callout-text", {"warning": errors[i]["kind"], "part": errors[i]["part"]}))
	if errors.size() > 5:
		ents.append(B._text(Vector2(20, 250), "+ %d more connection/rating warnings" % (errors.size() - 5), 2.2, "l", "callout-text", {"warning": "more"}))
	var title := "Assembly power / signal schematic"
	ents.append_array(B._frame(asm, "Front", "A3", 1, 1, 1))
	for e in ents:
		if e["t"] == "text" and e["d"].get("field", "") == "sheet":
			e["s"] = title
		if e["t"] == "text" and e["d"].get("field", "") == "scale":
			e["s"] = "NTS"
		if e["t"] == "text" and String(e["s"]).begins_with("SHEET"):
			e["s"] = "SHEET (power / signal, NTS)"
	var P := B.paper_size("A3")
	return {"paper": "A3", "w": P.x, "h": P.y, "denom": 0, "k": 0.0, "tab": "Schematic", "title": title, "name": String(asm.get("name", "Assembly")), "ents": ents, "area": B._area("A3"), "warnings": errors}


# ---------------------------------------------------------------- SVG + PNG
static func render_png(host: Node, sh: Dictionary, ppm := 3.0) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(int(float(sh["w"]) * ppm), 1), maxi(int(float(sh["h"]) * ppm), 1))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	var bv := BlueprintView.new()
	bv.sheet = sh
	bv.ppm = ppm
	bv.size = Vector2(vp.size)
	vp.add_child(bv)
	host.add_child(vp)
	for i in 4:
		await host.get_tree().process_frame
	var im := vp.get_texture().get_image()
	vp.queue_free()
	return im


static func write(host: Node, asm: Dictionary, kind := "drawing", opts := {}) -> Dictionary:
	if (asm.get("parts", []) as Array).is_empty():
		return {"ok": false, "why": "Put a part in the assembly first", "text": "NOT DONE: Put a part in the assembly first", "svg": "", "png": ""}
	var sh := sheet(asm, opts) if kind == "drawing" else schematic_sheet(asm, opts)
	var dir := String(opts.get("dir", Assembly.export_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stem := String(opts.get("stem", MeshExport.stem(String(asm.get("name", "Assembly"))) + "_" + kind))
	var svg_path := "%s/%s.svg" % [dir, stem]
	var png_path := "%s/%s.png" % [dir, stem]
	var f := FileAccess.open(svg_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "why": "The SVG could not be written", "text": "NOT DONE: The SVG could not be written", "svg": svg_path, "png": ""}
	f.store_string(B.to_svg(sh))
	f.close()
	var im: Image = await render_png(host, sh, float(opts.get("ppm", 3.0)))
	var err := im.save_png(png_path) if im != null and not im.is_empty() else ERR_CANT_CREATE
	var ok := err == OK
	return {"ok": ok, "why": "" if ok else error_string(err), "text": ("exported %s sheet: %s + %s" % [kind, svg_path.get_file(), png_path.get_file()]) if ok else "NOT DONE: " + error_string(err), "svg": svg_path, "png": png_path, "sheet": sh, "warnings": sh.get("warnings", [])}
