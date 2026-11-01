## s193 FIT TO OBJECT: a phone scan (Polycam / Scaniverse / RealityScan export: .obj, .glb, .gltf, .stl) in, a holder or a two-half case that fits it out.
## Pure helpers, no scene tree (the panel is scripts/easy_fit.gd). The scan file is only READ.
##   load_scan(path)         -> triangles (mm), or one plain sentence saying what is wrong
##   oriented(tris)          -> the scan lying flat (PCA: the shortest axis is up, the flattest face down), its low corner at 0,0,0
##   slabs_of(tris)          -> the scan cut into thin layers, each layer its outline (convex hull of what lies in the layer)
##   apply(bodies, f)        -> the replay step "fitobj" (scripts/build/part.gd): builds the holder / case with the CAD kernel
## HOW THE POCKET IS MADE (honest): the CAD kernel (Open CASCADE through KineCAD) takes sketches, extrudes and booleans, not a raw mesh. So the scan is
## SLICED: every layer (0.5 mm thick, at most 48 layers) keeps the hull of the scan's points in it, widened by the Fit clearance, and is extruded as
## a prism. The pocket is the union of those prisms, cut out of a block (Holder) or out of the same shape grown by the wall (Case). Flat walls are
## exact; a slope is a staircase of 0.5 mm steps, always on the loose side (the pocket is never smaller than the scan + clearance). A part of the
## scan that dents inward in one layer (a handle) is filled to that layer's outline: it still fits, it is just not hugging the dent.
## Axes: the scan lies with x = length, y = width, z = height (up). In the part: sketch plane "top" (u = x, v = y, world z = -v), world y = up.
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const LAYER_MM := 0.5
const MAX_LAYERS := 48
const MIN_SIDE := 5.0
const MAX_SIDE := 600.0
const MAX_TRIS := 400000
const SAME_MM := 0.02   # two neighbouring layers whose outlines agree to this are one prism


# ---------------------------------------------------------------- reading a scan file

## {"ok": true, "tris": PackedVector3Array (3 per triangle, in the file's own units x unit_mm = mm), "kind": "obj"} or {"ok": false, "why": a sentence}
static func load_scan(path: String) -> Dictionary:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if p.strip_edges() == "":
		return _bad("Type or pick the scan file first (an .obj, .glb or .stl from your scanning app)")
	if not FileAccess.file_exists(p):
		return _bad("There is no file at %s: check the name, or use Browse" % p)
	var ext := p.get_extension().to_lower()
	var tris := PackedVector3Array()
	var unit := 1.0
	if ext == "obj":
		tris = _read_obj(p)
	elif ext == "stl":
		tris = _read_stl(p)
	elif ext == "glb" or ext == "gltf":
		tris = _read_glb(p)
		unit = 1000.0   # glTF is in metres by its specification
	else:
		return _bad("Kine reads .obj, .glb, .gltf and .stl scans: export one of those from your scanning app")
	if tris.size() < 12:
		return _bad("That file holds no surface Kine can read (%d triangles): export the scan again as .obj, .glb or .stl" % (tris.size() / 3))
	if tris.size() / 3 > MAX_TRIS:
		return _bad("That scan has %d triangles: export it again with fewer (under %d) from your scanning app" % [tris.size() / 3, MAX_TRIS])
	if unit != 1.0:
		for i in tris.size():
			tris[i] *= unit
	return {"ok": true, "tris": tris, "kind": ext, "why": ""}


static func _bad(why: String) -> Dictionary:
	return {"ok": false, "tris": PackedVector3Array(), "kind": "", "why": why}


static func _read_obj(p: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return out
	var vs := PackedVector3Array()
	while not f.eof_reached():
		var ln := f.get_line()
		if ln.length() < 2:
			continue
		if ln[0] == "v" and ln[1] == " ":
			var t := ln.substr(2).strip_edges().split(" ", false)
			if t.size() >= 3:
				vs.append(Vector3(float(t[0]), float(t[1]), float(t[2])))
		elif ln[0] == "f" and ln[1] == " ":
			var t2 := ln.substr(2).strip_edges().split(" ", false)
			var ix: Array = []
			for tok in t2:
				var a := String(tok).split("/")[0]
				if a == "":
					continue
				var k := int(a)
				ix.append(k - 1 if k > 0 else vs.size() + k)
			for j in range(1, ix.size() - 1):
				if int(ix[0]) < 0 or int(ix[j]) < 0 or int(ix[j + 1]) < 0 or maxi(int(ix[0]), maxi(int(ix[j]), int(ix[j + 1]))) >= vs.size():
					continue
				out.append(vs[int(ix[0])])
				out.append(vs[int(ix[j])])
				out.append(vs[int(ix[j + 1])])
	return out


static func _read_stl(p: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var bytes := FileAccess.get_file_as_bytes(p)
	if bytes.size() < 84:
		return out
	var n := bytes.decode_u32(80)
	if bytes.size() == 84 + 50 * int(n):
		for i in int(n):
			var o := 84 + 50 * i + 12
			for k in 3:
				out.append(Vector3(bytes.decode_float(o + 12 * k), bytes.decode_float(o + 12 * k + 4), bytes.decode_float(o + 12 * k + 8)))
		return out
	for ln in bytes.get_string_from_utf8().split("\n"):   # ASCII STL
		var s := String(ln).strip_edges()
		if s.begins_with("vertex"):
			var t := s.substr(6).strip_edges().split(" ", false)
			if t.size() >= 3:
				out.append(Vector3(float(t[0]), float(t[1]), float(t[2])))
	return out


static func _read_glb(p: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(p, st) != OK:
		return out
	var root := doc.generate_scene(st)
	if root == null:
		return out
	_collect(root, Transform3D(), out)
	root.free()
	return out


static func _collect(n: Node, parent_xf: Transform3D, out: PackedVector3Array) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var arr: Array = m.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			if ix == null or (ix as PackedInt32Array).is_empty():
				for i in vs.size():
					out.append(xf * vs[i])
			else:
				for i in ix:
					out.append(xf * vs[i])
	for c in n.get_children():
		_collect(c, xf, out)


# ---------------------------------------------------------------- lying flat, size

## the scan turned so its shortest axis is up and its flattest face is down, then its low corner at 0,0,0.
## PCA of the SURFACE (the exact second moment of every triangle): the longest axis becomes x, the next y, the shortest z.
## Of the two ways up, the one with more near-flat area facing down is down.
static func oriented(tris: PackedVector3Array) -> PackedVector3Array:
	var cen := Vector3.ZERO
	var tot := 0.0
	var nt := tris.size() / 3
	for i in nt:
		var a := tris[3 * i]
		var b := tris[3 * i + 1]
		var c := tris[3 * i + 2]
		var ar := 0.5 * (b - a).cross(c - a).length()
		cen += (a + b + c) / 3.0 * ar
		tot += ar
	if tot <= 0.0:
		return tris
	cen /= tot
	var cov := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in nt:
		var a := tris[3 * i] - cen
		var b := tris[3 * i + 1] - cen
		var c := tris[3 * i + 2] - cen
		var ar := 0.5 * (b - a).cross(c - a).length()
		var s := a + b + c
		for r in 3:
			for q in range(r, 3):
				var v: float = ar / 12.0 * (a[r] * a[q] + b[r] * b[q] + c[r] * c[q] + s[r] * s[q])
				cov[r][q] += v
	cov[1][0] = cov[0][1]
	cov[2][0] = cov[0][2]
	cov[2][1] = cov[1][2]
	var eg := _eigen(cov)
	var vals: Vector3 = eg[0]
	var vecs: Array = eg[1]
	var order := [0, 1, 2]
	order.sort_custom(func(x: int, y: int) -> bool: return vals[x] > vals[y])
	var ex: Vector3 = vecs[order[0]]
	var ey: Vector3 = vecs[order[1]]
	var ez := ex.cross(ey).normalized()
	var out := PackedVector3Array()
	out.resize(tris.size())
	for i in tris.size():
		var d := tris[i] - cen
		out[i] = Vector3(d.dot(ex), d.dot(ey), d.dot(ez))
	# the face that is flat and large goes down
	var down := 0.0
	var up := 0.0
	for i in nt:
		var nrm := (out[3 * i + 1] - out[3 * i]).cross(out[3 * i + 2] - out[3 * i])
		var ar := 0.5 * nrm.length()
		if ar <= 0.0:
			continue
		var nz := nrm.normalized().z
		if nz < -0.94:
			down += ar
		elif nz > 0.94:
			up += ar
	if up > down * 1.02:
		for i in out.size():
			out[i] = Vector3(out[i].x, -out[i].y, -out[i].z)   # a half turn about x: still a proper rotation
	var lo := Vector3(INF, INF, INF)
	for v in out:
		lo = lo.min(v)
	for i in out.size():
		out[i] -= lo
	return out


## Jacobi rotations on a symmetric 3x3: [Vector3 eigenvalues, [eigenvector 0, 1, 2]]
static func _eigen(a: Array) -> Array:
	var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	for _sweep in 60:
		var off := absf(a[0][1]) + absf(a[0][2]) + absf(a[1][2])
		var sc := absf(a[0][0]) + absf(a[1][1]) + absf(a[2][2])
		if off <= 1e-14 * maxf(sc, 1e-30):
			break
		for pq in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			if absf(a[p][q]) < 1e-300:
				continue
			var theta: float = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
			var t: float = (1.0 if theta >= 0.0 else -1.0) / (absf(theta) + sqrt(theta * theta + 1.0))
			var c: float = 1.0 / sqrt(t * t + 1.0)
			var s: float = t * c
			for k in 3:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = c * akp - s * akq
				a[k][q] = s * akp + c * akq
			for k in 3:
				var apk: float = a[p][k]
				var aqk: float = a[q][k]
				a[p][k] = c * apk - s * aqk
				a[q][k] = s * apk + c * aqk
			for k in 3:
				var vkp: float = v[k][p]
				var vkq: float = v[k][q]
				v[k][p] = c * vkp - s * vkq
				v[k][q] = s * vkp + c * vkq
	return [Vector3(a[0][0], a[1][1], a[2][2]), [Vector3(v[0][0], v[1][0], v[2][0]), Vector3(v[0][1], v[1][1], v[2][1]), Vector3(v[0][2], v[1][2], v[2][2])]]


static func size_of(tris: PackedVector3Array) -> Vector3:
	if tris.is_empty():
		return Vector3.ZERO
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in tris:
		lo = lo.min(v)
		hi = hi.max(v)
	return hi - lo


## every point times k, the low corner put back at 0,0,0
static func scaled(tris: PackedVector3Array, k: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(tris.size())
	for i in tris.size():
		out[i] = tris[i] * k
	return out


## true when every side is a size a holder takes
static func fits_holder(sz: Vector3) -> bool:
	for v in [sz.x, sz.y, sz.z]:
		if float(v) < MIN_SIDE or float(v) > MAX_SIDE:
			return false
	return true


# ---------------------------------------------------------------- slicing

## the layers of an oriented scan: [[z0, z1, [[x, y], ...hull]], ...] in mm, from z = 0 up to the scan's height
static func slabs_of(tris: PackedVector3Array) -> Array:
	var h := size_of(tris).z
	var n := clampi(int(ceil(h / LAYER_MM)), 1, MAX_LAYERS)
	var t := h / n
	var pts: Array = []
	for k in n:
		pts.append([])
	for i in tris.size() / 3:
		var a := tris[3 * i]
		var b := tris[3 * i + 1]
		var c := tris[3 * i + 2]
		var zlo := minf(a.z, minf(b.z, c.z))
		var zhi := maxf(a.z, maxf(b.z, c.z))
		var k0 := clampi(int(floor(zlo / t)), 0, n - 1)
		var k1 := clampi(int(floor(zhi / t)), 0, n - 1)
		for k in range(k0, k1 + 1):
			var poly: Array = [a, b, c]
			poly = _clip_z(poly, float(k) * t, true)
			poly = _clip_z(poly, float(k + 1) * t, false)
			for v in poly:
				(pts[k] as Array).append(Vector2(v.x, v.y))
	var out: Array = []
	for k in n:
		var hull := _hull(PackedVector2Array(pts[k]))
		if hull.size() < 3:
			continue
		out.append([snappedf(float(k) * t, 0.0001), snappedf(float(k + 1) * t, 0.0001), _rows(hull)])
	return out


## Sutherland-Hodgman against one z plane: keep_above true keeps z >= zc
static func _clip_z(poly: Array, zc: float, keep_above: bool) -> Array:
	var out: Array = []
	for i in poly.size():
		var p: Vector3 = poly[i]
		var q: Vector3 = poly[(i + 1) % poly.size()]
		var pin := (p.z >= zc) if keep_above else (p.z <= zc)
		var qin := (q.z >= zc) if keep_above else (q.z <= zc)
		if pin:
			out.append(p)
		if pin != qin and absf(q.z - p.z) > 1e-12:
			out.append(p.lerp(q, (zc - p.z) / (q.z - p.z)))
	return out


static func _hull(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return PackedVector2Array()
	var h := Geometry2D.convex_hull(pts)
	if h.size() > 1 and h[0].distance_to(h[h.size() - 1]) < 1e-6:
		h.remove_at(h.size() - 1)
	var out := PackedVector2Array()
	for p in h:   # a corner closer than 0.05 mm to the one before it adds nothing
		if out.is_empty() or out[out.size() - 1].distance_to(p) >= 0.05:
			out.append(p)
	if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 0.05:
		out.remove_at(out.size() - 1)
	return out


static func _rows(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p in poly:
		out.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001)])
	return out


static func _poly(rows: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in rows:
		out.append(Vector2(float(r[0]), float(r[1])))
	return out


# ---------------------------------------------------------------- the record's step

## a "fitobj" step for Part: mode "holder" | "case"; clear, wall, depth in mm (depth only for the holder); slabs from slabs_of; size = the scan's box
static func step(mode: String, slabs: Array, size: Vector3, clear: float, wall: float, depth: float) -> Dictionary:
	return {"mode": mode, "slabs": slabs, "size": [size.x, size.y, size.z], "clear": clear, "wall": wall, "depth": depth}


## the layers of the pocket: [[z0, z1, polygon], ...], z from -clear up to the scan's height + clear (the holder stops at its depth), equal neighbours merged
static func pocket_layers(f: Dictionary) -> Array:
	var slabs: Array = f.get("slabs", [])
	var c := float(f.get("clear", 0.4))
	var sz: Array = f.get("size", [0, 0, 0])
	var h := float(sz[2])
	var top := h + c
	if String(f.get("mode", "holder")) == "holder":
		top = minf(top, float(f.get("depth", h + 2.0 * c)) - c)
	var spans: Array = [[-c, 0.0]]
	for s in slabs:
		spans.append([float(s[0]), float(s[1])])
	spans.append([h, h + c])
	var out: Array = []
	for sp in spans:
		var z0: float = sp[0]
		var z1: float = minf(sp[1], top)
		if z1 - z0 < 1e-4:
			continue
		var all := PackedVector2Array()
		for s in slabs:
			if float(s[1]) > z0 - c - 1e-6 and float(s[0]) < z1 + c + 1e-6:
				all.append_array(_poly(s[2]))
		var hull := _hull(all)
		if hull.size() < 3:
			continue
		var grown := _grow(hull, c)
		if grown.size() < 3:
			continue
		if not out.is_empty() and _same(out[out.size() - 1][2], grown):
			out[out.size() - 1][1] = z1
		else:
			out.append([z0, z1, grown])
	return _merge(out)


## neighbouring layers joined into one prism while the joined outline (the hull of both) stays within MERGE_MM of every layer's own on average.
## Always on the loose side (the joined outline holds every member). Scan noise makes hundreds of 0.05 mm slivers that the kernel's boolean
## cannot be trusted with; this gives it a few clean prisms instead
const MERGE_MM := 0.12

static func _merge(layers: Array) -> Array:
	var out: Array = []
	var min_area := 0.0
	for l in layers:
		if out.is_empty():
			out.append([l[0], l[1], l[2]])
			min_area = absf(_area(l[2]))
			continue
		var g: Array = out[out.size() - 1]
		var both := PackedVector2Array(g[2])
		both.append_array(l[2])
		var hull := _hull(both)
		var a := absf(_area(hull))
		var lo_area := minf(min_area, absf(_area(l[2])))
		var per := 0.0
		for i in hull.size():
			per += hull[i].distance_to(hull[(i + 1) % hull.size()])
		if hull.size() >= 3 and a - lo_area <= MERGE_MM * per:
			g[1] = l[1]
			g[2] = hull
			min_area = lo_area
		else:
			out.append([l[0], l[1], l[2]])
			min_area = absf(_area(l[2]))
	return out


## a polygon pushed out by d mm (round corners); the one outline that results
static func _grow(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	if d <= 0.0:
		return poly
	var res: Array = Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_ROUND)
	var best := PackedVector2Array()
	var best_a := 0.0
	for r in res:
		var a := absf(_area(r))
		if a > best_a:
			best_a = a
			best = r
	# thin the arc: a point closer than 0.1 mm to the one before it goes (corners stay)
	var out := PackedVector2Array()
	for p in best:
		if out.is_empty() or out[out.size() - 1].distance_to(p) >= 0.1:
			out.append(p)
	if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 0.1:
		out.remove_at(out.size() - 1)
	return out


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5


static func _same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > SAME_MM:
			return false
	return true


## where the case splits (mm up the scan): the middle of the widest run of layers
static func split_z(layers: Array) -> float:
	var best := 0.0
	for l in layers:
		best = maxf(best, absf(_area(l[2])))
	var lo := INF
	var hi := -INF
	for l in layers:
		if absf(_area(l[2])) >= best * 0.995:
			lo = minf(lo, float(l[0]))
			hi = maxf(hi, float(l[1]))
	return (lo + hi) * 0.5


## where the scan's low corner sits in the part, mm: scan (x, y, z) -> part plane (x + o.x, y + o.y) and part height z + o.z.
## The block's low corner is at (0, 0) and its floor at height 0: the part stands on the floor
static func placement(f: Dictionary) -> Vector3:
	var wall := float(f.get("wall", 3.0))
	var c := float(f.get("clear", 0.4))
	var lo := Vector2(INF, INF)
	for l in pocket_layers(f):
		for p in (l[2] as PackedVector2Array):
			lo = lo.min(p)
	return Vector3(-lo.x + wall, -lo.y + wall, c + wall)


## scan point (mm) -> the part's world point (metres): plane u = x, v = y, world z = -v, world y = up
static func world_of(f: Dictionary, p: Vector3) -> Vector3:
	var o := placement(f)
	return Vector3(p.x + o.x, p.z + o.z, -(p.y + o.y)) * MM


## a prism of poly (mm, scan frame shifted by o) from height y0 to y1 (mm)
static func _prism(poly: PackedVector2Array, y0: float, y1: float, o: Vector3) -> int:
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(Vector2(p.x + o.x, p.y + o.y) * MM)
	var face := KCad.sketch_face(KCad.polygon(pts), Vector3(0.0, y0 * MM, 0.0), Vector3.RIGHT, Vector3.UP)
	if face == 0:
		return 0
	var s := KCad.extrude(face, (y1 - y0) * MM)
	KCad.release(face)
	return s


## the union of prisms (layers [[z0, z1, poly]] with heights shifted by o.z); 0 and the kernel's words in last_error when one fails
static func _stack(layers: Array, o: Vector3, grow := 0.0, extra_top := 0.0) -> int:
	var cur := 0
	for i in layers.size():
		var l: Array = layers[i]
		var poly: PackedVector2Array = _grow(l[2], grow) if grow > 0.0 else l[2]
		var y1: float = float(l[1]) + o.z + (extra_top if i == layers.size() - 1 else 0.0)
		var pr := _prism(poly, float(l[0]) + o.z, y1, o)
		if pr == 0:
			if cur != 0:
				KCad.release(cur)
			return 0
		if cur == 0:
			cur = pr
			continue
		var u := KCad.union(cur, pr)
		KCad.release(cur)
		KCad.release(pr)
		if u == 0:
			return 0
		cur = u
	return cur


## the layers of the list cut to the heights [lo, hi] (a layer wholly outside goes)
static func _between(layers: Array, lo: float, hi: float) -> Array:
	var out: Array = []
	for l in layers:
		var z0 := maxf(float(l[0]), lo)
		var z1 := minf(float(l[1]), hi)
		if z1 - z0 > 1e-4:
			out.append([z0, z1, l[2]])
	return out


## the "fitobj" replay step: fills `bodies` (Holder: one solid; Case: the lower half, then the upper half). "" or the reason in words
static func apply(bodies: Array, f: Dictionary) -> String:
	if not (f.get("slabs") is Array) or (f["slabs"] as Array).is_empty():
		return "this step holds no scan: pick the scan again and press Build"
	var wall := float(f.get("wall", 3.0))
	var c := float(f.get("clear", 0.4))
	var layers := pocket_layers(f)
	if layers.is_empty():
		return "the depth is too shallow for this object: slide Depth up"
	var o := placement(f)
	var zbot := -c - wall   # the floor of the block, scan height
	var holder := String(f.get("mode", "holder")) == "holder"
	if holder:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for l in layers:
			for p in (l[2] as PackedVector2Array):
				lo = lo.min(p)
				hi = hi.max(p)
		var top: float = float(layers[layers.size() - 1][1])
		var block := _prism(PackedVector2Array([lo - Vector2(wall, wall), Vector2(hi.x + wall, lo.y - wall), hi + Vector2(wall, wall), Vector2(lo.x - wall, hi.y + wall)]), 0.0, top + o.z, o)
		if block == 0:
			return KCad.last_error() if KCad.last_error() != "" else "the holder block did not build"
		var pocket := _stack(layers, o, 0.0, 1.0)   # 1 mm taller than the block: the top is open
		if pocket == 0:
			KCad.release(block)
			return KCad.last_error() if KCad.last_error() != "" else "the pocket did not build: try a smaller clearance or another scan"
		var cut := KCad.cut(block, pocket)
		KCad.release(block)
		KCad.release(pocket)
		if cut == 0:
			return KCad.last_error() if KCad.last_error() != "" else "the pocket could not be cut: try another clearance"
		bodies.append(cut)
		return ""
	# CASE: the outer shape (the pocket grown by the wall, with a floor and a lid of the wall's thickness), cut at the widest section
	var outer: Array = [[zbot, -c, layers[0][2]]]
	for l in layers:
		outer.append(l)
	outer.append([float(layers[layers.size() - 1][1]), float(layers[layers.size() - 1][1]) + wall, layers[layers.size() - 1][2]])
	var zs := split_z(layers)
	var halves: Array = []
	for half in 2:
		var lo_z := -1e9 if half == 0 else zs
		var hi_z := zs if half == 0 else 1e9
		var oh := _between(outer, lo_z, hi_z)
		var ph := _between(layers, lo_z, hi_z)
		var hs := _stack(oh, o, wall)
		if hs == 0:
			for b in halves:
				KCad.release(int(b))
			return KCad.last_error() if KCad.last_error() != "" else "the case did not build"
		var pk := _stack(ph, o)
		if pk == 0:
			KCad.release(hs)
			for b in halves:
				KCad.release(int(b))
			return KCad.last_error() if KCad.last_error() != "" else "the case pocket did not build"
		var done := KCad.cut(hs, pk)
		KCad.release(hs)
		KCad.release(pk)
		if done == 0:
			for b in halves:
				KCad.release(int(b))
			return KCad.last_error() if KCad.last_error() != "" else "the case half could not be cut"
		halves.append(done)
	for b in halves:
		bodies.append(int(b))
	return ""
