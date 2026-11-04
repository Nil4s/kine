class_name ClockParts
extends RefCounted
## CH2 the clock's parts as PART FEATURE LISTS (the same records the Parts tab keeps): every wheel, the escape wheel, the anchor, the arbors,
## plates, pillars, bridges, dial, numerals, hands, collets, barrel and crutch is a Part.make() record of sketch / extrude / pattern / combine /
## move steps; Part.body_faces() replays it into a solid and the scene draws that mesh. Units mm; each part's local frame has its axis along z,
## the sketch plane at z = 0 and the extrusion towards +z.
## Script path (logged in docs/CH2_FEEDBACK.md): the OUTLINE POINTS of an involute tooth, a sawtooth, a pallet sector, a hand (the sketch has no
## involute curve and no gear macro; those points become line entities). Everything done with them is a Part feature.
## Replaying a 64-tooth wheel takes ~20 s, so the triangles are cached in assets/ch2_parts/ under the hash of the feature list.

const CACHE_DIR := "res://assets/ch2_parts"
const MM := 0.001
const TH := 3.0
const VERSION := 3
const PILLARS := [[-66.0, -50.0], [66.0, -50.0], [-66.0, 120.0], [66.0, 120.0]]
const PLATE_X := 70.5
const PLATE_Y0 := -54.5
const PLATE_Y1 := 135.0
const DIAL_Y0 := -62.0
const DIAL_Y1 := 143.0
const DIAL_X := 75.0
const Z_BACK := 0.0
const Z_FRONT := 26.0
const Z_DIAL := 41.0
const Z_MARKS := 43.0
const B_POS := Vector2(-22.627417, -22.627417)
const CRUTCH_L := 80.0
const CRUTCH_PIN_X := 6.7
const ROD_HALF := 2.5

static var _specs: Array = []


# ------------------------------------------------------------------ feature helpers (Part API only)

static func _ln(pts: PackedVector2Array) -> Array:
	var out := []
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		out.append({"k": "line", "a": Part.arr2(a), "b": Part.arr2(b)})
	return out


static func _circ(c: Vector2, r: float) -> Dictionary:
	return {"k": "circle", "c": Part.arr2(c), "r": r}


static func _sketch(fs: Array, ents: Array) -> String:
	return PartTemplates._sk(fs, "front", ents)


static func _extrude(fs: Array, sk: String, dist: float, op := "new") -> void:
	PartTemplates._ex(fs, sk, "extrude", dist, op)


static func _pattern(fs: Array, body: int, count: int) -> void:
	fs.append({"t": "pattern", "id": "f%d" % (fs.size() + 1), "name": "Pattern%d" % (fs.filter(func(f): return f["t"] == "pattern").size() + 1),
		"body": body, "kind": "circular", "count": count, "axis": "z", "deg": 360.0, "op": "join"})


static func _combine(fs: Array, target: int, tools: Array) -> void:
	fs.append({"t": "combine", "id": "f%d" % (fs.size() + 1), "name": "Combine%d" % (fs.filter(func(f): return f["t"] == "combine").size() + 1),
		"target": target, "tools": tools, "op": "join", "keep": false})


static func _move(fs: Array, body: int, d: Vector3) -> void:
	fs.append({"t": "move", "id": "f%d" % (fs.size() + 1), "name": "Move%d" % (fs.filter(func(f): return f["t"] == "move").size() + 1),
		"body": body, "d": [d.x, d.y, d.z]})


## the toothed ring of a wheel: a root disc, ONE tooth, a circular pattern of the tooth, the join. teeth = the points of ONE tooth (script path), rin the
## depth the tooth's foot sinks into the disc
static func _toothed(fs: Array, r_root: float, tooth: PackedVector2Array, n: int, th: float) -> void:
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, r_root)]), th)
	_extrude(fs, _sketch(fs, _ln(tooth)), th)
	_pattern(fs, 1, n)
	_combine(fs, 0, [1])


## spokes ("crossings"): cut an annulus window between hub and rim, add ONE bar, pattern it, join it
static func _spokes(fs: Array, r_in: float, r_hub: float, count: int, th: float) -> void:
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, r_in), _circ(Vector2.ZERO, r_hub)]), th + 2.0, "cut")
	var bar := PackedVector2Array([Vector2(r_hub - 0.6, -1.3), Vector2(r_in + 0.6, -1.3), Vector2(r_in + 0.6, 1.3), Vector2(r_hub - 0.6, 1.3)])
	_extrude(fs, _sketch(fs, _ln(bar)), th)
	_pattern(fs, 1, count)
	_combine(fs, 0, [1])


static func _bore(fs: Array, r: float, th: float) -> void:
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, r)]), th + 2.0, "cut")


## one tooth of ClockCH2.involute_outline: its flank points, closed under the root circle (the foot sinks to 0.75 of the root radius)
static func tooth_of(n: int, m: float) -> PackedVector2Array:
	var ol := ClockCH2.involute_outline(n, m)
	var per: int = ol.size() / n
	var pts := PackedVector2Array()
	for i in per - 2:
		pts.append(ol[i])
	var rin: float = 0.75 * ol[0].length()
	pts.insert(0, ol[0].normalized() * rin)
	pts.append(ol[per - 3].normalized() * rin)
	return pts


static func gear_feats(n: int, m: float, th: float, bore: float, spokes := 0, hub := 0.0) -> Array:
	var rp := m * n * 0.5
	var rf := rp - 1.1 * m
	var fs := []
	_toothed(fs, rf - 0.002, tooth_of(n, m), n, th)
	if spokes > 0:
		_spokes(fs, rf - 3.5, hub, spokes, th)
	_bore(fs, bore, th)
	return fs


static func escape_feats() -> Array:
	var p := TAU / ClockCH2.ESC_TEETH
	var rr := ClockCH2.ESC_ROOT
	var tooth := PackedVector2Array([Vector2.from_angle(0.16 * p) * 28.0, Vector2.from_angle(0.16 * p) * rr, Vector2(ClockCH2.ESC_R, 0.0),
		Vector2.from_angle(0.55 * p) * (rr + 0.3), Vector2.from_angle(0.55 * p) * 28.0])
	var fs := []
	_toothed(fs, rr - 0.1, tooth, ClockCH2.ESC_TEETH, ClockCH2.ESC_TH)
	_spokes(fs, 27.0, 5.5, 5, ClockCH2.ESC_TH)
	_bore(fs, 1.6, ClockCH2.ESC_TH)
	return fs


## the anchor in its own frame (pivot at the origin): hub, two arms, two pallet sectors, joined
static func anchor_feats() -> Array:
	var fs := []
	var th := ClockCH2.ESC_TH
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, 6.0)]), th)
	var blades := ClockCH2.blade_polys()
	for b in blades:
		var mid := Vector2.ZERO
		for v in (b as PackedVector2Array):
			mid += v
		mid /= (b as PackedVector2Array).size()
		var dirv := mid.normalized()
		var perp := Vector2(-dirv.y, dirv.x) * 1.6
		var arm := PackedVector2Array([dirv * 5.0 - perp, dirv * mid.length() - perp, dirv * mid.length() + perp, dirv * 5.0 + perp])
		_extrude(fs, _sketch(fs, _ln(arm)), th)
	for b in blades:
		_extrude(fs, _sketch(fs, _ln(b)), th)
	_combine(fs, 0, [1, 2, 3, 4])
	return fs


static func rod_feats(len_mm: float, dia: float) -> Array:
	var fs := []
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, dia * 0.5)]), len_mm)
	return fs


static func disc_feats(r: float, th: float, bore := 0.0) -> Array:
	var fs := []
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, r)]), th)
	if bore > 0.0:
		_bore(fs, bore, th)
	return fs


## the going barrel: a drum with a floor (cavity cut from the open side) ; the lid is a disc
static func drum_feats() -> Array:
	var fs := []
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, 22.0)]), 11.0)
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, 20.0)]), 9.0, "cut")
	_bore(fs, 2.4, 11.0)
	return fs


static func crutch_feats() -> Array:
	var fs := []
	var stem := PackedVector2Array([Vector2(-3, 6), Vector2(3, 6), Vector2(3, -CRUTCH_L - 6.0), Vector2(-3, -CRUTCH_L - 6.0)])
	_extrude(fs, _sketch(fs, _ln(stem)), 2.4)
	_move(fs, 0, Vector3(0, 0, 2.6))
	_extrude(fs, _sketch(fs, [_circ(Vector2(-CRUTCH_PIN_X, -CRUTCH_L), 1.6)]), 5.0)
	_extrude(fs, _sketch(fs, [_circ(Vector2(CRUTCH_PIN_X, -CRUTCH_L), 1.6)]), 5.0)
	# the pins sit beside the stem's end: a cross bar joins them (the stem's end is at -L - 6, the bar at -L +- 2)
	_extrude(fs, _sketch(fs, _ln(PackedVector2Array([Vector2(-CRUTCH_PIN_X, -CRUTCH_L - 1.6), Vector2(CRUTCH_PIN_X, -CRUTCH_L - 1.6), Vector2(CRUTCH_PIN_X, -CRUTCH_L + 1.6), Vector2(-CRUTCH_PIN_X, -CRUTCH_L + 1.6)]))), 2.4)
	_move(fs, 3, Vector3(0, 0, 2.6))
	_combine(fs, 0, [1, 2, 3])
	return fs


static func plate_feats(holes: Array) -> Array:
	var fs := []
	_extrude(fs, _sketch(fs, [PartTemplates._rect(Vector2(-PLATE_X, PLATE_Y0), Vector2(PLATE_X, PLATE_Y1))]), 3.0)
	var hs := []
	for h in holes:
		hs.append(_circ(Vector2(h[0], h[1]), h[2]))
	_extrude(fs, _sketch(fs, hs), 5.0, "cut")
	return fs


static func dial_feats() -> Array:
	var fs := []
	_extrude(fs, _sketch(fs, [PartTemplates._rect(Vector2(-DIAL_X, DIAL_Y0), Vector2(DIAL_X, DIAL_Y1))]), 2.0)
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, 5.0), _circ(Vector2(0, 70), 2.4)]), 4.0, "cut")
	return fs


static func _tick(c: Vector2, ang: float, r0: float, r1: float, w: float) -> PackedVector2Array:
	var d := Vector2.from_angle(ang)
	var n := Vector2(-d.y, d.x) * w * 0.5
	return PackedVector2Array([c + d * r0 - n, c + d * r1 - n, c + d * r1 + n, c + d * r0 + n])


## 60 minute ticks round the centre (every fifth longer and wider), 60 seconds ticks round the seconds sub-dial
static func marks_feats() -> Array:
	var ents := []
	for i in 60:
		var a := PI * 0.5 - TAU * i / 60.0
		var big := i % 5 == 0
		ents.append_array(_ln(_tick(Vector2.ZERO, a, 44.0 if big else 46.0, 50.0, 1.6 if big else 0.7)))
		var bigs := i % 5 == 0
		ents.append_array(_ln(_tick(Vector2(0, 70), a, 13.0 if bigs else 14.5, 17.0, 1.0 if bigs else 0.45)))
	var fs := []
	_extrude(fs, _sketch(fs, ents), 0.5)
	return fs


## 12 numerals set in Kine's own font outlines (PartText), upright, on a circle of radius 36 about the centre
static func numerals_feats() -> Array:
	var PT := preload("res://scripts/build/part_text.gd")
	var h8 = PT.raw("8")
	var sc := 7.0 / maxf((h8["bb"] as Rect2).size.y, 0.001)
	var all := []
	for k in 12:
		var num := 12 if k == 0 else k
		var rw = PT.raw(str(num))
		if not bool(rw["ok"]):
			continue
		var a := PI * 0.5 - TAU * k / 12.0
		var rr = PT.rings(rw, sc, (rw["bb"] as Rect2).get_center(), Vector2.from_angle(a) * 36.0, false)
		all.append_array(rr[0])
		all.append_array(rr[1])
	var fs := []
	_extrude(fs, _sketch(fs, PT.ents_of(all)), 0.5)
	return fs


static func hand_feats(kind: String) -> Array:
	var pts := PackedVector2Array()
	var th := 1.2
	if kind == "hour":   # a spade
		pts = PackedVector2Array([Vector2(-1.4, -6), Vector2(1.4, -6), Vector2(1.4, 10), Vector2(3.8, 15), Vector2(0, 30), Vector2(-3.8, 15), Vector2(-1.4, 10)])
	elif kind == "minute":
		pts = PackedVector2Array([Vector2(-1.1, -9), Vector2(1.1, -9), Vector2(0.8, 38), Vector2(0, 49), Vector2(-0.8, 38)])
	else:
		th = 0.8
		pts = PackedVector2Array([Vector2(-0.35, -6), Vector2(0.35, -6), Vector2(0.35, 14.5), Vector2(-0.35, 14.5)])
	var fs := []
	_extrude(fs, _sketch(fs, _ln(pts)), th)
	return fs


# ------------------------------------------------------------------ the registry

## every part: {"id", "role": "moving"|"fixed", "feats", "pos": Vector3 mm (the part's z = 0 plane), "mat", "shaft"}
static func specs() -> Array:
	if not _specs.is_empty():
		return _specs
	var S := []
	var spoke_of := {"C64": [5, 6.0, 1.6], "T60": [5, 5.5, 1.6], "M36": [4, 5.0, 1.6], "H40": [4, 7.0, 4.0], "BAR56": [5, 6.0, 2.4]}
	for g in ClockCH2.GEARS:
		var sp: Array = spoke_of.get(g[0], [0, 0.0, 1.6])
		var p := ClockCH2.pos_of(g[1])
		S.append({"id": g[0], "role": "moving", "feats": gear_feats(g[2], g[3], g[5], sp[2], sp[0], sp[1]), "pos": Vector3(p.x, p.y, g[4]), "mat": "brass", "shaft": g[1]})
	var ep := ClockCH2.pos_of("E")
	var D: float = ClockCH2.anchor_dims()["D"]
	S.append({"id": "ESC", "role": "moving", "feats": escape_feats(), "pos": Vector3(ep.x, ep.y, ClockCH2.ESC_Z0), "mat": "brass", "shaft": "E"})
	S.append({"id": "ANCHOR", "role": "moving", "feats": anchor_feats(), "pos": Vector3(ep.x, ep.y + D, ClockCH2.ESC_Z0), "mat": "steel", "shaft": "A"})
	S.append({"id": "ARB_ANCHOR", "role": "moving", "feats": rod_feats(41.2, 3.2), "pos": Vector3(ep.x, ep.y + D, -11.2), "mat": "steel", "shaft": "A"})
	S.append({"id": "CRUTCH", "role": "moving", "feats": crutch_feats(), "pos": Vector3(ep.x, ep.y + D, -13.8), "mat": "steel", "shaft": "A"})
	var arb := {"C": [-2.0, 58.0, 1.6], "T": [-2.0, 32.0, 1.6], "E": [-2.0, 58.0, 1.6], "M": [-2.0, 42.0, 1.6]}
	for s in arb:
		var q := ClockCH2.pos_of(s)
		S.append({"id": "ARB_" + s, "role": "moving", "feats": rod_feats(arb[s][1], arb[s][2] * 2.0), "pos": Vector3(q.x, q.y, arb[s][0]), "mat": "steel", "shaft": s})
	S.append({"id": "SPRING_ARBOR", "role": "moving", "feats": rod_feats(35.0, 4.8), "pos": Vector3(B_POS.x, B_POS.y, -2.0), "mat": "steel", "shaft": "B"})
	S.append({"id": "HOUR_PIPE", "role": "moving", "feats": _pipe(), "pos": Vector3(0, 0, 35.5), "mat": "steel", "shaft": "H"})
	S.append({"id": "BARREL", "role": "moving", "feats": drum_feats(), "pos": Vector3(B_POS.x, B_POS.y, 11.0), "mat": "brass", "shaft": "B"})
	S.append({"id": "BARREL_LID", "role": "moving", "feats": disc_feats(22.0, 1.0, 2.4), "pos": Vector3(B_POS.x, B_POS.y, 10.0), "mat": "brass", "shaft": "B"})
	S.append({"id": "HAND_HOUR", "role": "moving", "feats": hand_feats("hour"), "pos": Vector3(0, 0, 45.0), "mat": "blue", "shaft": "H"})
	S.append({"id": "HAND_MIN", "role": "moving", "feats": hand_feats("minute"), "pos": Vector3(0, 0, 47.6), "mat": "blue", "shaft": "C"})
	S.append({"id": "HAND_SEC", "role": "moving", "feats": hand_feats("second"), "pos": Vector3(ep.x, ep.y, 52.0), "mat": "blue", "shaft": "E"})
	S.append({"id": "COLLET_HOUR", "role": "moving", "feats": disc_feats(5.6, 2.6, 4.0), "pos": Vector3(0, 0, 44.2), "mat": "brass", "shaft": "H"})
	S.append({"id": "COLLET_MIN", "role": "moving", "feats": disc_feats(3.0, 2.8, 1.6), "pos": Vector3(0, 0, 46.8), "mat": "brass", "shaft": "C"})
	S.append({"id": "COLLET_SEC", "role": "moving", "feats": disc_feats(2.4, 2.2, 1.6), "pos": Vector3(ep.x, ep.y, 51.3), "mat": "brass", "shaft": "E"})
	var holes := [[0.0, 0.0, 2.1], [0.0, 36.0, 2.1], [0.0, 70.0, 2.1], [24.0, 0.0, 2.1], [B_POS.x, B_POS.y, 2.9], [0.0, ep.y + D, 2.1]]
	S.append({"id": "PLATE_BACK", "role": "fixed", "feats": plate_feats(holes), "pos": Vector3(0, 0, Z_BACK), "mat": "plate", "shaft": ""})
	S.append({"id": "PLATE_FRONT", "role": "fixed", "feats": plate_feats(holes), "pos": Vector3(0, 0, Z_FRONT), "mat": "plate", "shaft": ""})
	for i in PILLARS.size():
		S.append({"id": "PILLAR_%d" % i, "role": "fixed", "feats": disc_feats(3.5, 23.0), "pos": Vector3(PILLARS[i][0], PILLARS[i][1], 3.0), "mat": "brass", "shaft": ""})
	S.append({"id": "BRIDGE_BARREL", "role": "fixed", "feats": _bridge(Rect2(-60, -38, 57, 30), [[B_POS.x, B_POS.y, 3.0]]), "pos": Vector3(0, 0, 29.0), "mat": "plate", "shaft": ""})
	S.append({"id": "COCK", "role": "fixed", "feats": _bridge(Rect2(-8, 62, 16, 72), [[0.0, 70.0, 2.1], [0.0, ep.y + D, 2.1]]), "pos": Vector3(0, 0, 29.0), "mat": "plate", "shaft": ""})
	S.append({"id": "DIAL", "role": "fixed", "feats": dial_feats(), "pos": Vector3(0, 0, Z_DIAL), "mat": "enamel", "shaft": ""})
	S.append({"id": "DIAL_MARKS", "role": "fixed", "feats": marks_feats(), "pos": Vector3(0, 0, Z_MARKS), "mat": "ink", "shaft": ""})
	S.append({"id": "DIAL_NUMERALS", "role": "fixed", "feats": numerals_feats(), "pos": Vector3(0, 0, Z_MARKS), "mat": "ink", "shaft": ""})
	_specs = S
	return S


static func spec_of(id: String) -> Dictionary:
	for sp in specs():
		if sp["id"] == id:
			return sp
	return {}


static func _pipe() -> Array:
	var fs := []
	_extrude(fs, _sketch(fs, [_circ(Vector2.ZERO, 4.0)]), 10.5)
	_bore(fs, 2.4, 10.5)
	return fs


static func _bridge(r: Rect2, holes: Array) -> Array:
	var fs := []
	_extrude(fs, _sketch(fs, [PartTemplates._rect(r.position, r.end)]), 2.5)
	var hs := []
	for h in holes:
		hs.append(_circ(Vector2(h[0], h[1]), h[2]))
	_extrude(fs, _sketch(fs, hs), 4.0, "cut")
	return fs


# ------------------------------------------------------------------ meshes (replayed once, cached on disk)

static func key_of(spec: Dictionary) -> String:
	return "%s_%s" % [spec["id"], (JSON.stringify(spec["feats"]) + str(VERSION)).md5_text().substr(0, 10)]


## the triangles (metres, the part's frame) of a spec: from the cache, else replayed from its features and cached
static func triangles(spec: Dictionary) -> PackedVector3Array:
	var path := "%s/%s.bin" % [CACHE_DIR, key_of(spec)]
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var v = bytes_to_var(f.get_buffer(f.get_length()))
		if v is PackedVector3Array:
			return v
	var rec := Part.make(String(spec["id"]))
	rec["features"] = (spec["feats"] as Array).duplicate(true)
	var all := PackedVector3Array()
	for fcs in Part.body_faces(rec):
		all.append_array(fcs)
	if not all.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
		var w := FileAccess.open(path, FileAccess.WRITE)
		if w != null:
			w.store_buffer(var_to_bytes(all))
	return all


static func mesh_of(tris: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat shading: a plate's long fan triangles must not blend their normals
	for v in tris:
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## the feature kinds of a record in order (what the scene stores on each moving body)
static func history_of(spec: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for f in spec["feats"]:
		out.append(String(f["t"]))
	return out
