class_name C20Fit
extends RefCounted
## C20 PRINT FIT (complaints #32, #33, #36). Everything here is opt-in: the default export tessellation (0.1 mm) and the Hinge chip's flat leaves are unchanged.
##   hinge_rec / hinge_check   a print-in-place hinge (a pin inside a knuckle) whose gap is the printer preset's clearance (rec["fit_mm"], C03Tools.PRESETS),
##                             and a check on the real export mesh that the knuckles do not fuse (the least distance between the two bodies).
##   quality_for_fit           a mesh quality (MeshQuality's dictionary) whose deflection is fit / 4, so a curved face sits at most a quarter of the
##                             printer's clearance off the true surface; chord_error_mm measures it back from the mesh; tess_words reports it.
##   anchor_check              a support (an overhang's drop to the ground below it) that lands on a surface under ANCHOR_MIN_MM wide is warned about.
const Part := preload("res://scripts/build/part.gd")
const C03 := preload("res://scripts/build/c03_tools.gd")

const KNUCKLE_R := 3.5      # mm: the knuckle's outer radius
const PIN_R := 1.5          # mm: the pin
const LENGTH := 20.0        # mm
const FUSE_FRAC := 0.5      # the knuckles are called fused when they come closer than this share of the printer's clearance
const ANCHOR_MIN_MM := 2.0  # a support landing on a surface narrower than this breaks loose
const SAMPLE_MM := 1.0     # the overhang is probed on this grid
const OVERHANG_NZ := 0.7071 # a down face steeper than 45 degrees from the vertical needs a support


## the clearance a part's hinge takes: its printer preset's (rec["fit_mm"]); Ender FDM's 0.3 when no printer is chosen
static func hinge_gap(rec: Dictionary) -> float:
	return float(rec["fit_mm"]) if rec.has("fit_mm") else float(C03.PRESETS[3]["clear"])


## a part record: a pin and a knuckle round it, the gap between them = the preset's clearance. Marked rec["pip_hinge"] so the export checklist runs hinge_check.
static func hinge_rec(preset: int) -> Dictionary:
	var rec := Part.make("Print-in-place hinge")
	C03.apply(rec, preset)
	var gap := hinge_gap(rec)
	var fs: Array = []
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": KNUCKLE_R}]), "extrude", LENGTH, "new")
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": PIN_R + gap}]), "extrude", 2.0 * LENGTH + 20.0, "cut", true)
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": PIN_R}]), "extrude", LENGTH, "new")
	rec["features"] = fs
	rec["seq"] = fs.size()
	rec["pip_hinge"] = true
	return rec


## the least distance (mm) between any two bodies of the export mesh ({"v","t"} dictionaries, mm); INF with fewer than two bodies
static func min_body_gap(bodies: Array) -> float:
	var best := INF
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			best = minf(best, _dist(bodies[i], bodies[j]))
			best = minf(best, _dist(bodies[j], bodies[i]))
	return best


static func _dist(a: Dictionary, b: Dictionary) -> float:
	var va: PackedVector3Array = a["v"]
	var vb: PackedVector3Array = b["v"]
	var tb: PackedInt32Array = b["t"]
	var best := INF
	for p in va:
		for k in range(0, tb.size(), 3):
			var x := vb[tb[k]]
			var y := vb[tb[k + 1]]
			var z := vb[tb[k + 2]]
			var n := (y - x).cross(z - x)
			if n.length() < 1e-12:
				continue
			best = minf(best, PrintCheck._point_tri_dist(p, x, y, z, n.normalized()))
	return best


## the knuckle check on a part: {"gap_mm" (the clearance asked), "min_mm" (measured on the mesh), "fused", "line"}. quality = the export's ({} = Normal)
static func hinge_check(rec: Dictionary, quality := {}) -> Dictionary:
	var gap := hinge_gap(rec)
	var bo := MeshExport.bodies_of(rec, quality)
	var bodies: Array = bo["bodies"]
	var mn := min_body_gap(bodies)
	var fused := bodies.size() < 2 or mn < FUSE_FRAC * gap
	var line := ""
	if bodies.size() < 2:
		line = "WARN  The hinge's pin and knuckle are one piece: they will print fused"
	elif fused:
		line = "WARN  The hinge's knuckles come within %.2f mm of each other but the printer needs %.2f mm: they would fuse. Turn on Match the mesh to the fit" % [mn, gap]
	else:
		line = "OK  The hinge's knuckles stay %.2f mm apart (the printer's clearance is %.2f mm): they will move" % [mn, gap]
	return {"gap_mm": gap, "min_mm": mn, "fused": fused, "line": line}


## the mesh quality that ties the export to the fit: deflection = fit / 4 (clamped to MeshQuality's range). {} when the part has no fit.
static func quality_for_fit(rec: Dictionary) -> Dictionary:
	var fit := float(rec["fit_mm"]) if rec.has("fit_mm") else 0.0
	if fit <= 0.0:
		return {}
	var q := MeshQuality.of("Custom", fit / 4.0)
	q["name"] = "Fit"
	return q


## the worst chord error (mm) of the body meshes about the axis through (cx, cy) parallel to Z, for a round face of radius r: the mid-point of every edge
## whose two ends lie on that radius sits (r - |mid|) inside the true circle
static func chord_error_mm(bodies: Array, cx: float, cy: float, r: float) -> float:
	var worst := 0.0
	for b in bodies:
		var v: PackedVector3Array = b["v"]
		var t: PackedInt32Array = b["t"]
		for k in range(0, t.size(), 3):
			for e in 3:
				var p := v[t[k + e]]
				var q := v[t[k + (e + 1) % 3]]
				if absf(Vector2(p.x - cx, p.y - cy).length() - r) > 0.002 or absf(Vector2(q.x - cx, q.y - cy).length() - r) > 0.002:
					continue
				var mid := (p + q) * 0.5
				worst = maxf(worst, r - Vector2(mid.x - cx, mid.y - cy).length())
	return worst


static func tess_words(q: Dictionary, tris: int, chord_mm := -1.0) -> String:
	var s := "Mesh matched to the fit: curved faces sit at most %.3f mm off the true surface (a quarter of the %.2f mm fit), %d triangles" % [float(q["defl_mm"]), float(q["defl_mm"]) * 4.0, tris]
	if chord_mm >= 0.0:
		s += "; measured %.3f mm" % chord_mm
	return s


## SUPPORT ANCHORS on welded printer-space bodies ({"v","t"}, mm, Z up): every overhang (a down face steeper than 45 degrees, off the bed) is dropped straight
## down onto the first up face under it; the flat patch it lands on (connected up faces of the same slope) is measured across its narrowest way.
## {"warn": [{"width_mm", "at"}], "landings": n, "lines": [...]}. A drop to the bed is wide ground and is not listed.
static func anchor_check(bodies: Array) -> Dictionary:
	var ups := []       # {a,b,c,n,body,ia,ib,ic}
	for bi in bodies.size():
		var v: PackedVector3Array = bodies[bi]["v"]
		var t: PackedInt32Array = bodies[bi]["t"]
		for k in range(0, t.size(), 3):
			var n := (v[t[k + 1]] - v[t[k]]).cross(v[t[k + 2]] - v[t[k]])
			if n.length() < 1e-12:
				continue
			n = n.normalized()
			if n.z > OVERHANG_NZ:
				ups.append({"a": v[t[k]], "b": v[t[k + 1]], "c": v[t[k + 2]], "n": n, "body": bi, "ia": t[k], "ib": t[k + 1], "ic": t[k + 2]})
	var grid := {}
	for i in ups.size():
		var u: Dictionary = ups[i]
		var a: Vector3 = u["a"]
		var b: Vector3 = u["b"]
		var c: Vector3 = u["c"]
		for cx in range(floori(minf(a.x, minf(b.x, c.x)) / 2.0), floori(maxf(a.x, maxf(b.x, c.x)) / 2.0) + 1):
			for cy in range(floori(minf(a.y, minf(b.y, c.y)) / 2.0), floori(maxf(a.y, maxf(b.y, c.y)) / 2.0) + 1):
				var key := Vector2i(cx, cy)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(i)
	var seen := {}      # one sample per 2 mm cell of the overhang
	var patches := {}   # lowest triangle of a patch -> true
	var warn := []
	var landings := 0
	for bi in bodies.size():
		var v: PackedVector3Array = bodies[bi]["v"]
		var t: PackedInt32Array = bodies[bi]["t"]
		for k in range(0, t.size(), 3):
			var a := v[t[k]]
			var b := v[t[k + 1]]
			var c := v[t[k + 2]]
			var n := (b - a).cross(c - a)
			if n.length() < 1e-12:
				continue
			n = n.normalized()
			if n.z > -OVERHANG_NZ or minf(a.z, minf(b.z, c.z)) <= 0.05:
				continue
			var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
			var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
			var sx := lo.x
			while sx <= hi.x + 1e-6:
				var sy := lo.y
				while sy <= hi.y + 1e-6:
					var o := _on_tri(a, b, c, sx, sy)
					sy += SAMPLE_MM
					if o.z != o.z:
						continue
					var ck := Vector3i(floori(o.x / SAMPLE_MM), floori(o.y / SAMPLE_MM), floori(o.z / 2.0))
					if seen.has(ck):
						continue
					seen[ck] = true
					var hit := -1
					var hz := -INF
					for i in grid.get(Vector2i(floori(o.x / 2.0), floori(o.y / 2.0)), []):
						var z := _z_at(ups[i], o.x, o.y)
						if z != z or z >= o.z - 0.01:
							continue
						if z > hz:
							hz = z
							hit = i
					if hit < 0:
						continue
					landings += 1
					var patch := _patch(ups, hit)
					var pid := int(patch["id"])
					if patches.has(pid):
						continue
					patches[pid] = true
					var w := float(patch["width"])
					if w < ANCHOR_MIN_MM:
						warn.append({"width_mm": w, "at": Vector3(o.x, o.y, hz)})
				sx += SAMPLE_MM
	var lines := []
	for w in warn:
		lines.append("WARN  A support would land on a surface only %.1f mm wide near (%.0f, %.0f, %.0f) mm: tree supports can break loose there. Print it another way up or add a wider ledge" % [w["width_mm"], w["at"].x, w["at"].y, w["at"].z])
	if warn.is_empty():
		lines.append(("OK  Supports land on surfaces %.0f mm wide or more" % ANCHOR_MIN_MM) if landings > 0 else "OK  No support lands on the part's own surfaces")
	return {"warn": warn, "landings": landings, "lines": lines}


## the point of triangle abc above (x, y), or a point with NAN z when (x, y) is outside it
static func _on_tri(a: Vector3, b: Vector3, c: Vector3, x: float, y: float) -> Vector3:
	var z := _z_at({"a": a, "b": b, "c": c}, x, y)
	return Vector3(x, y, z)


## the z of the up triangle u under (x, y); NAN outside it
static func _z_at(u: Dictionary, x: float, y: float) -> float:
	var a: Vector3 = u["a"]
	var b: Vector3 = u["b"]
	var c: Vector3 = u["c"]
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-12:
		return NAN
	var l1 := ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / d
	var l2 := ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / d
	var l3 := 1.0 - l1 - l2
	if l1 < -1e-6 or l2 < -1e-6 or l3 < -1e-6:
		return NAN
	return l1 * a.z + l2 * b.z + l3 * c.z


## the patch round up triangle `first`: up faces joined by a shared vertex with a near-equal normal and a height within 0.05 mm of the plane.
## {"id" (its lowest triangle index), "width" (mm: the narrowest way across, over 12 turns of the frame)}
static func _patch(ups: Array, first: int) -> Dictionary:
	var by_vert := {}
	for i in ups.size():
		var u: Dictionary = ups[i]
		for key in ["ia", "ib", "ic"]:
			var kk := Vector2i(int(u["body"]), int(u[key]))
			if not by_vert.has(kk):
				by_vert[kk] = []
			(by_vert[kk] as Array).append(i)
	var n0: Vector3 = ups[first]["n"]
	var d0 := n0.dot(ups[first]["a"])
	var inset := {first: true}
	var stack := [first]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var u: Dictionary = ups[i]
		for key in ["ia", "ib", "ic"]:
			for j in by_vert[Vector2i(int(u["body"]), int(u[key]))]:
				if inset.has(j):
					continue
				var w: Dictionary = ups[j]
				if (w["n"] as Vector3).dot(n0) < 0.98 or absf(n0.dot(w["a"]) - d0) > 0.05:
					continue
				inset[j] = true
				stack.append(j)
	var pts := []
	var low := first
	for i in inset:
		low = mini(low, int(i))
		for key in ["a", "b", "c"]:
			pts.append(ups[i][key])
	var best := INF
	for s in 12:
		var ang := PI * float(s) / 12.0
		var ax := Vector2(cos(ang), sin(ang))
		var ay := Vector2(-ax.y, ax.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pts:
			var q := Vector2(p.x, p.y)
			var pr := Vector2(q.dot(ax), q.dot(ay))
			lo = Vector2(minf(lo.x, pr.x), minf(lo.y, pr.y))
			hi = Vector2(maxf(hi.x, pr.x), maxf(hi.y, pr.y))
		best = minf(best, minf(hi.x - lo.x, hi.y - lo.y))
	return {"id": low, "width": best}


## the checklist lines the export dialog adds when "Match the mesh to the fit" is on
static func check_lines(rec: Dictionary, bodies: Array, quality: Dictionary) -> Array:
	var out := []
	if bool(rec.get("pip_hinge", false)):
		out.append(String(hinge_check(rec, quality)["line"]))
	out.append_array(anchor_check(bodies)["lines"])
	return out
