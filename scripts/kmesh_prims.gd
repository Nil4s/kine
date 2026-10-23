class_name KMeshPrims
extends RefCounted
## B09 (docs/ROADMAP_400.md): the primitives of the MODEL page, built as KMesh: cube, plane, UV sphere, ico sphere,
## cylinder, capsule, torus. All in metres, centred on the origin (Y up), quads wherever the shape allows (the
## poles of the UV sphere and capsule are triangle fans, the cylinder caps one n-gon each, the ico sphere is triangles by
## nature), welded (shared verts), every face CCW seen from outside, so the signed volume is positive.
## build(kind, params) is what the Add primitive control calls; PARAMS lists each kind's live parameters with defaults
## and ranges (the control makes its fields from it).

const KINDS := ["cube", "plane", "uv_sphere", "ico_sphere", "cylinder", "capsule", "torus"]
const NAMES := {"cube": "Cube", "plane": "Plane", "uv_sphere": "UV sphere", "ico_sphere": "Ico sphere",
	"cylinder": "Cylinder", "capsule": "Capsule", "torus": "Torus"}

## kind -> [[param, default, min, max, step, is_length]]; lengths in metres, the rest are counts
const PARAMS := {
	"cube": [["size", 0.5, 0.01, 10.0, 0.01, true], ["segments", 1, 1, 64, 1, false]],
	"plane": [["size_x", 1.0, 0.01, 50.0, 0.01, true], ["size_z", 1.0, 0.01, 50.0, 0.01, true],
		["segments_x", 1, 1, 256, 1, false], ["segments_z", 1, 1, 256, 1, false]],
	"uv_sphere": [["radius", 0.25, 0.005, 10.0, 0.005, true], ["segments", 32, 3, 256, 1, false], ["rings", 16, 2, 128, 1, false]],
	"ico_sphere": [["radius", 0.25, 0.005, 10.0, 0.005, true], ["subdivisions", 2, 0, 6, 1, false]],
	"cylinder": [["radius", 0.25, 0.005, 10.0, 0.005, true], ["depth", 0.5, 0.005, 20.0, 0.005, true],
		["segments", 32, 3, 256, 1, false], ["height_segments", 1, 1, 128, 1, false]],
	"capsule": [["radius", 0.15, 0.005, 10.0, 0.005, true], ["depth", 0.4, 0.0, 20.0, 0.005, true],
		["segments", 32, 3, 256, 1, false], ["rings", 8, 1, 64, 1, false], ["height_segments", 1, 1, 128, 1, false]],
	"torus": [["major_radius", 0.3, 0.01, 10.0, 0.005, true], ["minor_radius", 0.08, 0.002, 5.0, 0.002, true],
		["major_segments", 48, 3, 256, 1, false], ["minor_segments", 16, 3, 128, 1, false]],
}


## the defaults of one kind as {param: value}
static func defaults(kind: String) -> Dictionary:
	var d := {}
	for p in PARAMS.get(kind, []):
		d[p[0]] = p[1]
	return d


## clamp every param into its range (counts to ints); unknown keys dropped, missing ones defaulted
static func clean(kind: String, params: Dictionary) -> Dictionary:
	var d := {}
	for p in PARAMS.get(kind, []):
		var v = params.get(p[0], p[1])
		if p[5]:
			d[p[0]] = clampf(float(v), float(p[2]), float(p[3]))
		else:
			d[p[0]] = clampi(int(v), int(p[2]), int(p[3]))
	return d


## one primitive by name with its params (missing params take the defaults); null for an unknown kind
static func build(kind: String, params := {}) -> KMesh:
	var p := clean(kind, params)
	match kind:
		"cube":
			return cube(Vector3.ONE * float(p["size"]), p["segments"])
		"plane":
			return plane(p["size_x"], p["size_z"], p["segments_x"], p["segments_z"])
		"uv_sphere":
			return uv_sphere(p["radius"], p["segments"], p["rings"])
		"ico_sphere":
			return ico_sphere(p["radius"], p["subdivisions"])
		"cylinder":
			return cylinder(p["radius"], p["depth"], p["segments"], p["height_segments"])
		"capsule":
			return capsule(p["radius"], p["depth"], p["segments"], p["rings"], p["height_segments"])
		"torus":
			return torus(p["major_radius"], p["minor_radius"], p["major_segments"], p["minor_segments"])
	return null


## box of `size`, n x n quads on every side. 6n^2 + 2 verts, 6n^2 faces
static func cube(size := Vector3.ONE, n := 1) -> KMesh:
	n = maxi(n, 1)
	var vs := PackedVector3Array()
	var fs: Array = []
	var ids := {}
	var h := size * 0.5
	for a in 3:
		for s in [-1, 1]:
			var u := (a + 1) % 3
			var v := (a + 2) % 3
			var corner := func(i: int, j: int) -> int:
				var ix := [0, 0, 0]
				ix[a] = n if s > 0 else 0
				ix[u] = i
				ix[v] = j
				var key: int = (ix[0] * (n + 1) + ix[1]) * (n + 1) + ix[2]
				if not ids.has(key):
					ids[key] = vs.size()
					var q := Vector3.ZERO
					for k in 3:
						q[k] = -h[k] + size[k] * float(ix[k]) / float(n)
					vs.append(q)
				return ids[key]
			for i in n:
				for j in n:
					var f: Array = [corner.call(i, j), corner.call(i + 1, j), corner.call(i + 1, j + 1), corner.call(i, j + 1)]
					if s < 0:
						f.reverse()
					fs.append(f)
	return KMesh.new().from_arrays(vs, fs)


## flat grid in XZ facing +Y. (nx + 1)(nz + 1) verts, nx nz quads; open (one border loop)
static func plane(sx := 1.0, sz := 1.0, nx := 1, nz := 1) -> KMesh:
	nx = maxi(nx, 1)
	nz = maxi(nz, 1)
	var vs := PackedVector3Array()
	for j in nz + 1:
		for i in nx + 1:
			vs.append(Vector3(sx * (float(i) / nx - 0.5), 0.0, sz * (float(j) / nz - 0.5)))
	var fs: Array = []
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			fs.append([a, a + nx + 1, a + nx + 2, a + 1])   # CCW seen from +Y (x right, z toward the viewer)
	return KMesh.new().from_arrays(vs, fs)


## the ring of `seg` verts at height y and radius r, starting at +X, CCW seen from +Y
static func _ring(vs: PackedVector3Array, seg: int, r: float, y: float) -> int:
	var base := vs.size()
	for i in seg:
		var t := TAU * float(i) / seg
		vs.append(Vector3(r * cos(t), y, -r * sin(t)))
	return base


## quads between two rings (lo below hi), outward
static func _band(fs: Array, seg: int, lo: int, hi: int) -> void:
	for i in seg:
		var k := (i + 1) % seg
		fs.append([lo + i, lo + k, hi + k, hi + i])


## a fan from the pole vert to a ring; top = the pole is above the ring
static func _fan(fs: Array, seg: int, ring: int, pole: int, top: bool) -> void:
	for i in seg:
		var k := (i + 1) % seg
		fs.append([ring + i, ring + k, pole] if top else [ring + k, ring + i, pole])


## a stack of rings (radius, height) from bottom to top, closed with poles (when the end radius is 0) or n-gon caps
static func _lathe(seg: int, prof: Array) -> KMesh:
	var vs := PackedVector3Array()
	var fs: Array = []
	var rings := []   # ring base, or -(pole + 1)
	for q in prof:
		var r: float = q[0]
		if r <= 0.0:
			rings.append(-(vs.size() + 1))
			vs.append(Vector3(0.0, q[1], 0.0))
		else:
			rings.append(_ring(vs, seg, r, q[1]))
	for k in rings.size() - 1:
		var a: int = rings[k]
		var b: int = rings[k + 1]
		if a >= 0 and b >= 0:
			_band(fs, seg, a, b)
		elif a < 0:
			_fan(fs, seg, b, -a - 1, false)
		else:
			_fan(fs, seg, a, -b - 1, true)
	var first: int = rings[0]
	var last: int = rings[rings.size() - 1]
	if first >= 0:   # bottom cap: one n-gon, CW seen from above = CCW from below
		var cap := PackedInt32Array()
		for i in seg:
			cap.append(first + seg - 1 - i)
		fs.append(cap)
	if last >= 0:
		var cap := PackedInt32Array()
		for i in seg:
			cap.append(last + i)
		fs.append(cap)
	return KMesh.new().from_arrays(vs, fs)


## latitude / longitude sphere: seg (rings - 1) + 2 verts, seg rings faces (2 seg pole triangles, the rest quads)
static func uv_sphere(radius := 1.0, seg := 32, rings := 16) -> KMesh:
	seg = maxi(seg, 3)
	rings = maxi(rings, 2)
	var prof := []
	for k in rings + 1:
		var th := PI * (1.0 - float(k) / rings)   # from the south pole (PI) up to the north (0)
		prof.append([0.0 if k == 0 or k == rings else radius * sin(th), radius * cos(th)])
	return _lathe(seg, prof)


## open-ended tube of height `depth` with an n-gon cap at each end: seg (hs + 1) verts, seg hs + 2 faces
static func cylinder(radius := 1.0, depth := 2.0, seg := 32, hs := 1) -> KMesh:
	seg = maxi(seg, 3)
	hs = maxi(hs, 1)
	var prof := []
	for k in hs + 1:
		prof.append([radius, depth * (float(k) / hs - 0.5)])
	return _lathe(seg, prof)


## a cylinder of height `depth` with a hemisphere of `radius` on each end (total height depth + 2 radius); `rings`
## bands per hemisphere, `hs` bands along the straight part. seg (2 rings + hs - 1) + 2 verts, seg (2 rings + hs) faces
## (depth 0: a UV sphere of 2 rings bands)
static func capsule(radius := 0.5, depth := 1.0, seg := 32, rings := 8, hs := 1) -> KMesh:
	seg = maxi(seg, 3)
	rings = maxi(rings, 1)
	hs = maxi(hs, 1)
	if depth <= 0.0:
		return uv_sphere(radius, seg, rings * 2)
	var h := depth * 0.5
	var prof := []
	for k in rings + 1:   # bottom cap: south pole .. equator
		var th := 0.5 * PI * float(k) / rings
		prof.append([0.0 if k == 0 else radius * sin(th), -h - radius * cos(th)])
	for k in range(1, hs):
		prof.append([radius, -h + depth * float(k) / hs])
	for k in rings + 1:   # top cap: equator .. north pole
		var th := 0.5 * PI * float(k) / rings
		prof.append([0.0 if k == rings else radius * cos(th), h + radius * sin(th)])
	return _lathe(seg, prof)


## ring torus around Y: major_seg minor_seg verts and quads
static func torus(major := 1.0, minor := 0.25, mseg := 48, nseg := 12) -> KMesh:
	mseg = maxi(mseg, 3)
	nseg = maxi(nseg, 3)
	var vs := PackedVector3Array()
	for i in mseg:
		var t := TAU * float(i) / mseg
		var dir := Vector3(cos(t), 0.0, -sin(t))
		for j in nseg:
			var p := TAU * float(j) / nseg
			vs.append(dir * (major + minor * cos(p)) + Vector3(0.0, minor * sin(p), 0.0))
	var fs: Array = []
	for i in mseg:
		var i2 := (i + 1) % mseg
		for j in nseg:
			var j2 := (j + 1) % nseg
			fs.append([i * nseg + j, i2 * nseg + j, i2 * nseg + j2, i * nseg + j2])
	return KMesh.new().from_arrays(vs, fs)


## icosahedron split `sub` times (each triangle into 4), every vert pushed onto the sphere: 10 4^sub + 2 verts,
## 20 4^sub triangles
static func ico_sphere(radius := 1.0, sub := 2) -> KMesh:
	var g := (1.0 + sqrt(5.0)) * 0.5
	var vs := PackedVector3Array([Vector3(-1, g, 0), Vector3(1, g, 0), Vector3(-1, -g, 0), Vector3(1, -g, 0),
		Vector3(0, -1, g), Vector3(0, 1, g), Vector3(0, -1, -g), Vector3(0, 1, -g),
		Vector3(g, 0, -1), Vector3(g, 0, 1), Vector3(-g, 0, -1), Vector3(-g, 0, 1)])
	var fs: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in maxi(sub, 0):
		var mid := {}
		var nf: Array = []
		var half := func(a: int, b: int) -> int:
			var key := mini(a, b) * 1048576 + maxi(a, b)
			if not mid.has(key):
				mid[key] = vs.size()
				vs.append((vs[a] + vs[b]) * 0.5)
			return mid[key]
		for f in fs:
			var ab: int = half.call(f[0], f[1])
			var bc: int = half.call(f[1], f[2])
			var ca: int = half.call(f[2], f[0])
			nf.append_array([[f[0], ab, ca], [f[1], bc, ab], [f[2], ca, bc], [ab, bc, ca]])
		fs = nf
	for i in vs.size():
		vs[i] = vs[i].normalized() * radius
	return KMesh.new().from_arrays(vs, fs)


## the closed-form volume of each solid (the smooth shape the mesh approximates); 0 for the plane
static func analytic_volume(kind: String, params := {}) -> float:
	var p := clean(kind, params)
	match kind:
		"cube":
			return pow(float(p["size"]), 3.0)
		"uv_sphere", "ico_sphere":
			return 4.0 / 3.0 * PI * pow(float(p["radius"]), 3.0)
		"cylinder":
			return PI * pow(float(p["radius"]), 2.0) * float(p["depth"])
		"capsule":
			return PI * pow(float(p["radius"]), 2.0) * (float(p["depth"]) + 4.0 / 3.0 * float(p["radius"]))
		"torus":
			return 2.0 * PI * PI * float(p["major_radius"]) * pow(float(p["minor_radius"]), 2.0)
	return 0.0
