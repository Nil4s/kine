## QUICK RIG (GAP_AUDIT_1106 animation item 2 "own skeleton", lane L29). A user mesh with no skin (a KMesh) + a few markers or a template
## becomes a rigged character the posing / retarget pipeline takes. Tests: tests/autorig_test.gd.
##   1. MARKERS  the user places a few points (chin, groin, elbows, wrists, knees, ankles for the biped; the same legs + chin, groin,
##      tail_tip for the quadruped; root, tip, (mid) for a tail chain). A marker may be off the surface or even outside.
##   2. SKELETON  the template's joints (the biped: Kine's own 22 main joints, UE5 names, read from data/skeleton.json, so CharImport maps
##      them by NAME; the quadruped and tail: names in this file) are moved onto the markers by scattered-data interpolation (a similarity
##      from the markers, then each joint takes the inverse-distance-weighted residual of the markers; a joint with a marker of its own
##      lands on it) and then PUSHED INSIDE: onto the voxel centre near it with the most clearance from the surface (a chamfer distance
##      transform of the voxelized mesh), checked again against the exact triangle distances.
##   3. WEIGHTS  geodesic voxel binding, after Dionne & de Lasa, "Geodesic Voxel Binding for Production Character Meshes" (SCA 2013), written
##      from the paper: the mesh is voxelized (surface voxels and the inside by scanline parity, per closed component, OR over
##      components so overlapping primitives work); for every bone a shortest path distance d_i through the 26-connected inside voxels
##      from the voxels along the bone; a voxel's weight for bone i is max(0, (W - t_i) / (W + t_i)) normalised, t_i = d_i - d_min (d_min the nearest bone's
##      distance; for two bones this is exactly a linear ramp of half width W in t; W = BLEND_FRAC x the mesh's longest side, at least
##      EDGE_K x the 95th percentile edge: only bones about as near as the nearest one count); SMOOTH passes of
##      diffusion over the voxel graph; each vertex then takes the trilinear blend of the inside voxels around it, its 4 largest
##      weights, normalised. (Pinocchio's heat diffusion, Baran & Popovic 2007, is KMeshAutoWeights; this one needs no manifold mesh:
##      separate primitives that overlap bind as one body.)
##   4. REGISTER  to_character() builds a Skeleton3D (identity rest rotations, bone origins at the joints), the skinned ArrayMesh and a Skin,
##      and returns CharImport.from_node's dict: the same character dict an imported glb gives, so CharImport.map_bones / fit / pose,
##      the retarget and every clip play on it. The weights are also writable on the KMesh as KMeshAutoWeights' two channels.
## Heavy passes (voxelize, chamfer, bind) run in native/src/kine_autorig_native.cpp when the DLL has it; the GDScript twins here are
## the fallback and are measured equal (tests/autorig_test.gd G). Limits: the mesh is assumed Y-up, facing +Z, +X the character's left
## (Kine's frame); a skeleton is fitted, not oriented per bone (rest rotations are identity; CharImport.fit takes the bone directions).
class_name AutoRig
extends RefCounted

const FORMAT := "kine_autorig"
const VERSION := 1
const CELLS := 110          # voxels along the mesh's longest side
const BLEND_FRAC := 0.03    # W (the half width of a blend, in distance difference) = this x the longest side ...
const EDGE_K := 3.4         # ... but at least this x the 95th percentile mesh edge: the weight changes by e / W across an edge of length e
const SMOOTH := 2           # diffusion passes
const CLEAR_WANT := 0.004   # the clearance a joint is pushed to when it can be (the bar is 2 mm)
const JX := 0.000123        # the column centre of the parity scan is nudged off the grid (same constants in the C++)
const JY := 0.000217

static var _skel_json: Dictionary = {}


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "why": why}


static func _native() -> Object:
	if NativeExt.ensure("kine_native", "KineAutoRigNative"):
		return load("res://scripts/autorig_native.gd")
	return null


## ---- templates ----------------------------------------------------------------------------------------------------------------------
## {"joints": [[name, parent name, Vector3]] (parents first), "markers": {key: Vector3 in template space}, "joint_of": {key: joint},
##  "required": [keys], "chain": bool}
static func template(name: String) -> Dictionary:
	match name:
		"biped":
			return _biped_template()
		"quadruped":
			return _quad_template()
		"tail":
			var j: Array = []
			for k in 6:
				j.append(["tail_%02d" % k, "" if k == 0 else "tail_%02d" % (k - 1), Vector3(0, 0, k * 0.2)])
			return {"joints": j, "markers": {"root": Vector3.ZERO, "tip": Vector3(0, 0, 1), "mid": Vector3(0, 0, 0.5)}, "joint_of": {}, "required": ["root", "tip"], "chain": true}
	return {}


static func template_names() -> Array:
	return ["biped", "quadruped", "tail"]


static func _biped_template() -> Dictionary:
	if _skel_json.is_empty():
		_skel_json = JSON.parse_string(FileAccess.get_file_as_string("res://data/skeleton.json"))
	var jd: Dictionary = _skel_json["joints"]
	var joints: Array = []
	var has := {}
	for n in AnimImport.MAIN:
		var p := String(jd[n].get("parent", "")) if jd[n].get("parent") != null else ""
		while p != "" and not AnimImport.MAIN.has(p):
			p = String(jd[p].get("parent", "")) if jd[p].get("parent") != null else ""
		var pp: Array = jd[n]["pos"]
		joints.append([n, p, Vector3(pp[0], pp[1], pp[2])])
		has[n] = joints[joints.size() - 1][2]
	var m := {"chin": Vector3(0, 1.585, 0.085), "groin": Vector3(0, 0.80, 0.0)}
	var jof := {}
	var req := ["chin", "groin"]
	for sd in ["_l", "_r"]:
		for pr in [["elbow", "lowerarm"], ["wrist", "hand"], ["knee", "calf"], ["ankle", "foot"]]:
			var key: String = pr[0] + sd
			m[key] = has[pr[1] + sd]
			jof[key] = pr[1] + sd
			req.append(key)
	return {"joints": joints, "markers": m, "joint_of": jof, "required": req, "chain": false}


static func _quad_template() -> Dictionary:
	var j: Array = [
		["pelvis", "", Vector3(0, 0.50, -0.28)], ["spine_01", "pelvis", Vector3(0, 0.51, -0.05)], ["spine_02", "spine_01", Vector3(0, 0.52, 0.20)],
		["neck_01", "spine_02", Vector3(0, 0.58, 0.30)], ["head", "neck_01", Vector3(0, 0.68, 0.45)],
		["tail_01", "pelvis", Vector3(0, 0.52, -0.40)], ["tail_02", "tail_01", Vector3(0, 0.58, -0.54)], ["tail_03", "tail_02", Vector3(0, 0.58, -0.70)]]
	var m := {"chin": Vector3(0, 0.64, 0.66), "groin": Vector3(0, 0.38, -0.10), "tail_tip": Vector3(0, 0.55, -0.80)}
	var jof := {}
	var req := ["chin", "groin", "tail_tip"]
	for s in [["l", 1.0], ["r", -1.0]]:
		var sd: String = s[0]
		var x: float = s[1]
		j.append(["front_upper_" + sd, "spine_02", Vector3(0.09 * x, 0.45, 0.22)])
		j.append(["front_lower_" + sd, "front_upper_" + sd, Vector3(0.09 * x, 0.27, 0.24)])
		j.append(["front_paw_" + sd, "front_lower_" + sd, Vector3(0.09 * x, 0.09, 0.25)])
		j.append(["hind_upper_" + sd, "pelvis", Vector3(0.09 * x, 0.45, -0.28)])
		j.append(["hind_lower_" + sd, "hind_upper_" + sd, Vector3(0.10 * x, 0.26, -0.36)])
		j.append(["hind_paw_" + sd, "hind_lower_" + sd, Vector3(0.09 * x, 0.09, -0.29)])
		for pr in [["elbow", "front_lower"], ["wrist", "front_paw"], ["knee", "hind_lower"], ["ankle", "hind_paw"]]:
			var key: String = pr[0] + "_" + sd
			m[key] = _tj(j, pr[1] + "_" + sd)
			jof[key] = pr[1] + "_" + sd
			req.append(key)
	return {"joints": j, "markers": m, "joint_of": jof, "required": req, "chain": false}


static func _tj(j: Array, n: String) -> Vector3:
	for x in j:
		if x[0] == n:
			return x[2]
	return Vector3.ZERO


## ---- geometry helpers -------------------------------------------------------------------------------------------------------------
## the mesh's triangles (faces fanned) and the closed component (union-find over shared vertices) of each: {"tris", "comp", "ncomp"}
static func tris_of(mesh: KMesh) -> Dictionary:
	var par := PackedInt32Array()
	par.resize(mesh.verts.size())
	for i in par.size():
		par[i] = i
	for f in mesh.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size()):
			var a := fa[0]
			while par[a] != a:
				par[a] = par[par[a]]
				a = par[a]
			var b := fa[k]
			while par[b] != b:
				par[b] = par[par[b]]
				b = par[b]
			if a != b:
				par[a] = b
	var tris := PackedInt32Array()
	var comp := PackedInt32Array()
	var ids := {}
	for f in mesh.faces:
		var fa := f as PackedInt32Array
		var r := fa[0]
		while par[r] != r:
			r = par[r]
		if not ids.has(r):
			ids[r] = ids.size()
		for k in range(1, fa.size() - 1):
			tris.append(fa[0])
			tris.append(fa[k])
			tris.append(fa[k + 1])
			comp.append(ids[r])
	return {"tris": tris, "comp": comp, "ncomp": ids.size()}


static func grid_of(mesh: KMesh, cells: int) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v in mesh.verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var ext := hi - lo
	var longest := maxf(ext.x, maxf(ext.y, ext.z))
	var vs := longest / float(cells)
	var org := lo - Vector3(3, 3, 3) * vs
	return {"vs": vs, "origin": org, "nx": int(ceil(ext.x / vs)) + 7, "ny": int(ceil(ext.y / vs)) + 7, "nz": int(ceil(ext.z / vs)) + 7, "longest": longest, "lo": lo, "hi": hi}


static func _len3(a: Vector3, b: Vector3) -> float:
	var dx: float = b.x - a.x
	var dy: float = b.y - a.y
	var dz: float = b.z - a.z
	return sqrt(dx * dx + dy * dy + dz * dz)


## GDScript twin of KineAutoRigNative.voxelize: bit 1 = inside by parity (any component), bit 2 = touched by a triangle
static func voxelize_gd(verts: PackedVector3Array, tris: PackedInt32Array, comp: PackedInt32Array, org: Vector3, vs: float, nx: int, ny: int, nz: int) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(nx * ny * nz)
	m.fill(0)
	var nt := tris.size() / 3
	var ox: float = org.x
	var oy: float = org.y
	var oz: float = org.z
	var ncomp := 0
	for c in comp:
		ncomp = maxi(ncomp, c + 1)
	for t in nt:
		var a := verts[tris[t * 3]]
		var b := verts[tris[t * 3 + 1]]
		var c := verts[tris[t * 3 + 2]]
		var l := maxf(_len3(a, b), maxf(_len3(b, c), _len3(c, a)))
		var n := maxi(1, ceili(l / (0.5 * vs)))
		for i in n + 1:
			for j in n + 1 - i:
				var u := float(i) / n
				var v := float(j) / n
				var w := 1.0 - u - v
				var px: float = a.x * w + b.x * u + c.x * v
				var py: float = a.y * w + b.y * u + c.y * v
				var pz: float = a.z * w + b.z * u + c.z * v
				var ix := floori((px - ox) / vs)
				var iy := floori((py - oy) / vs)
				var iz := floori((pz - oz) / vs)
				if ix >= 0 and iy >= 0 and iz >= 0 and ix < nx and iy < ny and iz < nz:
					var q := ix + nx * (iy + ny * iz)
					m[q] = m[q] | 2
	var by: Array = []
	by.resize(ncomp)
	for c in ncomp:
		by[c] = PackedInt32Array()
	for t in nt:
		var lst: PackedInt32Array = by[comp[t]]
		lst.append(t)
		by[comp[t]] = lst
	for c in ncomp:
		var cols := {}
		for t in by[c]:
			var a := verts[tris[t * 3]]
			var b := verts[tris[t * 3 + 1]]
			var d := verts[tris[t * 3 + 2]]
			var det: float = (b.y - d.y) * (a.x - d.x) + (d.x - b.x) * (a.y - d.y)
			if absf(det) < 1e-18:
				continue
			var x0: float = minf(a.x, minf(b.x, d.x))
			var x1: float = maxf(a.x, maxf(b.x, d.x))
			var y0: float = minf(a.y, minf(b.y, d.y))
			var y1: float = maxf(a.y, maxf(b.y, d.y))
			var ix0 := maxi(0, ceili((x0 - ox) / vs - 0.5 - JX) - 1)
			var ix1 := mini(nx - 1, floori((x1 - ox) / vs - 0.5 - JX) + 1)
			var iy0 := maxi(0, ceili((y0 - oy) / vs - 0.5 - JY) - 1)
			var iy1 := mini(ny - 1, floori((y1 - oy) / vs - 0.5 - JY) + 1)
			for iy in range(iy0, iy1 + 1):
				for ix in range(ix0, ix1 + 1):
					var cx: float = ox + (ix + 0.5 + JX) * vs
					var cy: float = oy + (iy + 0.5 + JY) * vs
					var l0: float = ((b.y - d.y) * (cx - d.x) + (d.x - b.x) * (cy - d.y)) / det
					var l1: float = ((d.y - a.y) * (cx - d.x) + (a.x - d.x) * (cy - d.y)) / det
					var l2 := 1.0 - l0 - l1
					if l0 < 0.0 or l1 < 0.0 or l2 < 0.0:
						continue
					var key := ix + nx * iy
					var col: PackedFloat64Array = cols.get(key, PackedFloat64Array())
					col.append(l0 * a.z + l1 * b.z + l2 * d.z)
					cols[key] = col
		for key in cols:
			var zs: PackedFloat64Array = cols[key]
			if zs.size() < 2:
				continue
			zs.sort()
			var k := 0
			while k + 1 < zs.size():
				var k0 := maxi(ceili((zs[k] - oz) / vs - 0.5), 0)
				var k1 := mini(ceili((zs[k + 1] - oz) / vs - 0.5) - 1, nz - 1)
				for iz in range(k0, k1 + 1):
					var q := int(key) + nx * ny * iz
					m[q] = m[q] | 1
				k += 2
	return m


## GDScript twin of KineAutoRigNative.edt
static func edt_gd(mask: PackedByteArray, vs: float, nx: int, ny: int, nz: int) -> PackedFloat32Array:
	var n := nx * ny * nz
	var d := PackedFloat64Array()
	d.resize(n)
	for i in n:
		d[i] = 1e30 if mask[i] != 0 else 0.0
	var w1 := vs
	var w2 := vs * sqrt(2.0)
	var w3 := vs * sqrt(3.0)
	for pass_i in 2:
		var fwd := pass_i == 0
		for zz in nz:
			var z := zz if fwd else nz - 1 - zz
			for yy in ny:
				var y := yy if fwd else ny - 1 - yy
				for xx in nx:
					var x := xx if fwd else nx - 1 - xx
					var i := x + nx * (y + ny * z)
					if mask[i] == 0:
						continue
					var best := d[i]
					for dz in range(-1, 2):
						for dy in range(-1, 2):
							for dx in range(-1, 2):
								if dx == 0 and dy == 0 and dz == 0:
									continue
								var key := dz if dz != 0 else (dy if dy != 0 else dx)
								if (key > 0) if fwd else (key < 0):
									continue
								var a := x + dx
								var b := y + dy
								var c := z + dz
								var k := absi(dx) + absi(dy) + absi(dz)
								var w := w1 if k == 1 else (w2 if k == 2 else w3)
								var nd: float
								if a < 0 or b < 0 or c < 0 or a >= nx or b >= ny or c >= nz:
									nd = w
								else:
									nd = d[a + nx * (b + ny * c)] + w
								if nd < best:
									best = nd
					d[i] = best
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = d[i]
	return out


static func _seg_dist(px: float, py: float, pz: float, a: Vector3, b: Vector3) -> float:
	var abx: float = b.x - a.x
	var aby: float = b.y - a.y
	var abz: float = b.z - a.z
	var l2 := abx * abx + aby * aby + abz * abz
	var qx: float = px - a.x
	var qy: float = py - a.y
	var qz: float = pz - a.z
	var t := clampf((qx * abx + qy * aby + qz * abz) / l2, 0.0, 1.0) if l2 > 1e-18 else 0.0
	var rx := qx - abx * t
	var ry := qy - aby * t
	var rz := qz - abz * t
	return sqrt(rx * rx + ry * ry + rz * rz)


## GDScript twin of KineAutoRigNative.bind -> {"n", "w": PackedFloat32Array n * nb in voxel index order}
static func bind_gd(mask: PackedByteArray, vs: float, nx: int, ny: int, nz: int, org: Vector3, sa: PackedVector3Array, sb: PackedVector3Array, sbone: PackedInt32Array, nb: int, R: float, smooth: int) -> Dictionary:
	var N := nx * ny * nz
	var cid := PackedInt32Array()
	cid.resize(N)
	cid.fill(-1)
	var vox := PackedInt32Array()
	for i in N:
		if mask[i] != 0:
			cid[i] = vox.size()
			vox.append(i)
	var n := vox.size()
	var vx := PackedInt32Array()
	var vy := PackedInt32Array()
	var vz := PackedInt32Array()
	var cx := PackedFloat64Array()
	var cy := PackedFloat64Array()
	var cz := PackedFloat64Array()
	for k in n:
		var i := vox[k]
		var x := i % nx
		var y := (i / nx) % ny
		var z := i / (nx * ny)
		vx.append(x)
		vy.append(y)
		vz.append(z)
		cx.append(org.x + (x + 0.5) * vs)
		cy.append(org.y + (y + 0.5) * vs)
		cz.append(org.z + (z + 0.5) * vs)
	var INF_D := 1e30
	var D := PackedFloat64Array()
	D.resize(n * nb)
	D.fill(INF_D)
	var off: Array = []
	var wl := PackedFloat64Array()
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0 and dz == 0:
					continue
				off.append(Vector3i(dx, dy, dz))
				wl.append(vs * sqrt(float(dx * dx + dy * dy + dz * dz)))
	for b in nb:
		var d := PackedFloat64Array()
		d.resize(n)
		d.fill(INF_D)
		var any := false
		for s in sbone.size():
			if sbone[s] != b:
				continue
			for k in n:
				var sd := _seg_dist(cx[k], cy[k], cz[k], sa[s], sb[s])
				if sd <= 1.5 * vs and sd < d[k]:
					d[k] = sd
					any = true
		if not any:
			var bd := INF_D
			var bk := -1
			for s in sbone.size():
				if sbone[s] != b:
					continue
				for k in n:
					var sd := _seg_dist(cx[k], cy[k], cz[k], sa[s], sb[s])
					if sd < bd:
						bd = sd
						bk = k
			if bk >= 0:
				d[bk] = bd
		var hk := PackedFloat64Array()
		var hv := PackedInt32Array()
		for k in n:
			if d[k] < INF_D:
				_hpush(hk, hv, d[k], k)
		while hk.size() > 0:
			var top := _hpop(hk, hv)
			var u: int = top[1]
			if top[0] > d[u]:
				continue
			var x := vx[u]
			var y := vy[u]
			var z := vz[u]
			for q in 26:
				var o: Vector3i = off[q]
				var a := x + o.x
				var bb := y + o.y
				var c := z + o.z
				if a < 0 or bb < 0 or c < 0 or a >= nx or bb >= ny or c >= nz:
					continue
				var v := cid[a + nx * (bb + ny * c)]
				if v < 0:
					continue
				var nd := d[u] + wl[q]
				if nd < d[v]:
					d[v] = nd
					_hpush(hk, hv, nd, v)
		for k in n:
			D[k * nb + b] = d[k]
	var W := PackedFloat64Array()
	W.resize(n * nb)
	W.fill(0.0)
	for k in n:
		var dm := INF_D
		for b in nb:
			dm = minf(dm, D[k * nb + b])
		if dm >= INF_D:
			var bd := INF_D
			var bb := 0
			for s in sbone.size():
				var sd := _seg_dist(cx[k], cy[k], cz[k], sa[s], sb[s])
				if sd < bd:
					bd = sd
					bb = sbone[s]
			W[k * nb + bb] = 1.0
			continue
		var sum := 0.0
		for b in nb:
			var x := D[k * nb + b]
			var t := x - dm
			var r := 0.0 if x >= INF_D else maxf(0.0, (R - t) / (R + t))
			W[k * nb + b] = r
			sum += r
		for b in nb:
			W[k * nb + b] = W[k * nb + b] / sum
	var six := [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]
	for it in smooth:
		var W2 := PackedFloat64Array()
		W2.resize(n * nb)
		for k in n:
			var nbr := PackedInt32Array()
			for q in 6:
				var o: Vector3i = six[q]
				var a := vx[k] + o.x
				var bb := vy[k] + o.y
				var c := vz[k] + o.z
				if a < 0 or bb < 0 or c < 0 or a >= nx or bb >= ny or c >= nz:
					continue
				var v := cid[a + nx * (bb + ny * c)]
				if v >= 0:
					nbr.append(v)
			for b in nb:
				if nbr.is_empty():
					W2[k * nb + b] = W[k * nb + b]
					continue
				var s := 0.0
				for v in nbr:
					s += W[v * nb + b]
				W2[k * nb + b] = 0.5 * W[k * nb + b] + 0.5 * s / nbr.size()
		W = W2
	var out := PackedFloat32Array()
	out.resize(n * nb)
	for i in out.size():
		out[i] = W[i]
	return {"n": n, "w": out}


static func _hpush(hk: PackedFloat64Array, hv: PackedInt32Array, key: float, val: int) -> void:
	hk.append(key)
	hv.append(val)
	var i := hk.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if hk[p] <= hk[i]:
			break
		var tk := hk[p]
		hk[p] = hk[i]
		hk[i] = tk
		var tv := hv[p]
		hv[p] = hv[i]
		hv[i] = tv
		i = p


static func _hpop(hk: PackedFloat64Array, hv: PackedInt32Array) -> Array:
	var out := [hk[0], hv[0]]
	var last := hk.size() - 1
	hk[0] = hk[last]
	hv[0] = hv[last]
	hk.resize(last)
	hv.resize(last)
	var i := 0
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < last and hk[l] < hk[m]:
			m = l
		if r < last and hk[r] < hk[m]:
			m = r
		if m == i:
			break
		var tk := hk[m]
		hk[m] = hk[i]
		hk[i] = tk
		var tv := hv[m]
		hv[m] = hv[i]
		hv[i] = tv
		i = m
	return out


## exact distance from p to the triangle (a, b, c), Ericson, Real-Time Collision Detection 5.1.5
static func pt_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return p.distance_to(a)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return p.distance_to(b)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return p.distance_to(a + ab * (d1 / (d1 - d3)))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return p.distance_to(c)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return p.distance_to(a + ac * (d2 / (d2 - d6)))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return p.distance_to(b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))))
	var den := 1.0 / (va + vb + vc)
	return p.distance_to(a + ab * (vb * den) + ac * (vc * den))


## ray parity along an oblique ray, per closed component (comp: per triangle), OR over components: is p inside the solid?
static func inside_exact(verts: PackedVector3Array, tris: PackedInt32Array, comp: PackedInt32Array, p: Vector3) -> bool:
	var d := Vector3(0.5774, -0.3011, 0.7573).normalized()
	var par := {}
	for t in tris.size() / 3:
		var a := verts[tris[t * 3]]
		var e1 := verts[tris[t * 3 + 1]] - a
		var e2 := verts[tris[t * 3 + 2]] - a
		var h := d.cross(e2)
		var det := e1.dot(h)
		if absf(det) < 1e-14:
			continue
		var f := 1.0 / det
		var sv := p - a
		var u := f * sv.dot(h)
		if u < 0.0 or u > 1.0:
			continue
		var q := sv.cross(e1)
		var v := f * d.dot(q)
		if v < 0.0 or u + v > 1.0:
			continue
		if f * e2.dot(q) > 1e-9:
			par[comp[t]] = int(par.get(comp[t], 0)) + 1
	for c in par:
		if int(par[c]) % 2 == 1:
			return true
	return false


static func surface_distance(verts: PackedVector3Array, tris: PackedInt32Array, p: Vector3) -> float:
	var best := INF
	for t in tris.size() / 3:
		best = minf(best, pt_tri(p, verts[tris[t * 3]], verts[tris[t * 3 + 1]], verts[tris[t * 3 + 2]]))
	return best


## ---- the fit ------------------------------------------------------------------------------------------------------------------------
static func _missing(tpl: Dictionary, markers: Dictionary) -> Array:
	var out := []
	for k in tpl["required"]:
		if not markers.has(k):
			out.append(k)
	return out


## joint positions (Array of Vector3, template order) before they are pushed inside
static func fit(tpl: Dictionary, markers: Dictionary) -> Array:
	var joints: Array = tpl["joints"]
	if bool(tpl["chain"]):
		var poly: Array = [markers["root"]]
		if markers.has("mid"):
			poly.append(markers["mid"])
		poly.append(markers["tip"])
		var lens: Array = [0.0]
		for i in range(1, poly.size()):
			lens.append(float(lens[i - 1]) + (poly[i] as Vector3).distance_to(poly[i - 1]))
		var out := []
		for k in joints.size():
			var s: float = float(lens[lens.size() - 1]) * k / float(joints.size() - 1)
			var seg := 1
			while seg < lens.size() - 1 and float(lens[seg]) < s:
				seg += 1
			var l0: float = lens[seg - 1]
			var l1: float = lens[seg]
			var u := (s - l0) / maxf(l1 - l0, 1e-9)
			out.append((poly[seg - 1] as Vector3).lerp(poly[seg], clampf(u, 0.0, 1.0)))
		return out
	var tm: Dictionary = tpl["markers"]
	var jat := {}
	for i in joints.size():
		jat[joints[i][0]] = i
	var T: Array = []
	var M: Array = []
	var forced := {}
	for k in markers:
		var m: Vector3 = markers[k]
		if tm.has(k):
			T.append(tm[k])
			M.append(m)
			if tpl["joint_of"].has(k):
				forced[jat[tpl["joint_of"][k]]] = m
		elif jat.has(k):   # a marker named after a joint: that joint, exactly
			T.append(joints[jat[k]][2])
			M.append(m)
			forced[jat[k]] = m
	var n := T.size()
	var cT := Vector3.ZERO
	var cM := Vector3.ZERO
	for i in n:
		cT += T[i]
		cM += M[i]
	cT /= n
	cM /= n
	var sT := 0.0
	var sM := 0.0
	for i in n:
		sT += ((T[i] as Vector3) - cT).length_squared()
		sM += ((M[i] as Vector3) - cM).length_squared()
	var s := sqrt(sM / sT) if sT > 1e-12 else 1.0
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for j in joints:
		lo = lo.min(j[2])
		hi = hi.max(j[2])
	var ext := hi - lo
	var eps := pow(0.05 * maxf(ext.x, maxf(ext.y, ext.z)), 2.0)
	var out := []
	for i in joints.size():
		if forced.has(i):
			out.append(forced[i])
			continue
		var tj: Vector3 = joints[i][2]
		var sw := 0.0
		var disp := Vector3.ZERO
		for q in n:
			var w := 1.0 / (((T[q] as Vector3) - tj).length_squared() + eps)
			disp += w * ((M[q] as Vector3) - (s * ((T[q] as Vector3) - cT) + cM))
			sw += w
		out.append(s * (tj - cT) + cM + disp / sw)
	return out


## the voxel centre near p with the most clearance (the chamfer distance, capped at 3 voxels) minus half the move: p itself when it already
## has 3 voxels of clearance
static func _push_in(p: Vector3, g: Dictionary, mask: PackedByteArray, e: PackedFloat32Array) -> Vector3:
	var vs: float = g["vs"]
	var org: Vector3 = g["origin"]
	var nx: int = g["nx"]
	var ny: int = g["ny"]
	var nz: int = g["nz"]
	var cap := 3.0 * vs
	var ip := Vector3i(floori((p.x - org.x) / vs), floori((p.y - org.y) / vs), floori((p.z - org.z) / vs))
	if ip.x >= 0 and ip.y >= 0 and ip.z >= 0 and ip.x < nx and ip.y < ny and ip.z < nz and e[ip.x + nx * (ip.y + ny * ip.z)] >= cap:
		return p
	var best := p
	for mult in [5, 10, 20, 40]:
		var rr := int(mult)
		var bs := -INF
		var be := 0.0
		for z in range(maxi(ip.z - rr, 0), mini(ip.z + rr, nz - 1) + 1):
			for y in range(maxi(ip.y - rr, 0), mini(ip.y + rr, ny - 1) + 1):
				for x in range(maxi(ip.x - rr, 0), mini(ip.x + rr, nx - 1) + 1):
					var i := x + nx * (y + ny * z)
					if mask[i] == 0:
						continue
					var c := org + Vector3(x + 0.5, y + 0.5, z + 0.5) * vs
					var sc := minf(e[i], cap) - 0.5 * c.distance_to(p)
					if sc > bs:
						bs = sc
						best = c
						be = e[i]
		if be >= 1.5 * vs:
			break
	return best


## ---- build --------------------------------------------------------------------------------------------------------------------------
## -> {"ok", "why", "template", "joints": [{"name", "parent" (index, -1), "pos"}], "ids" (V * 4, -1 = none), "w" (V * 4),
##     "grid": {"mask", "vs", "origin", "nx", "ny", "nz"}, "info": {"ms", "native", "vs", "cells", "min_clear", "voxels"}}
## opts: "cells" (voxels along the longest side), "gd" (true: the fallback even when the DLL is there)
static func build(mesh: KMesh, template_name: String, markers: Dictionary, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	if mesh == null or mesh.verts.size() < 4 or mesh.faces.is_empty():
		return _fail("the mesh has no faces: add or open a model first")
	var tpl := template(template_name)
	if tpl.is_empty():
		return _fail("unknown template '%s': use biped, quadruped or tail" % template_name)
	var miss := _missing(tpl, markers)
	if not miss.is_empty():
		return _fail("place the marker%s %s first (the %s template needs %s)" % ["" if miss.size() == 1 else "s", ", ".join(miss), template_name, ", ".join(tpl["required"])])
	var nat: Object = null if bool(opts.get("gd", false)) else _native()
	var cells := int(opts.get("cells", CELLS))
	var td := tris_of(mesh)
	var g := grid_of(mesh, cells)
	var vs: float = g["vs"]
	var org: Vector3 = g["origin"]
	var nx: int = g["nx"]
	var ny: int = g["ny"]
	var nz: int = g["nz"]
	var mask: PackedByteArray = nat.voxelize(mesh.verts, td["tris"], td["comp"], org, vs, nx, ny, nz) if nat != null else voxelize_gd(mesh.verts, td["tris"], td["comp"], org, vs, nx, ny, nz)
	var nin := 0
	for i in mask.size():
		if mask[i] != 0:
			nin += 1
	if nin < 20:
		return _fail("the mesh has no inside to put bones in: is it closed (a solid body, not a sheet)?")
	var e: PackedFloat32Array = nat.edt(mask, vs, nx, ny, nz) if nat != null else edt_gd(mask, vs, nx, ny, nz)
	# skeleton
	var joints: Array = tpl["joints"]
	var jat := {}
	for i in joints.size():
		jat[joints[i][0]] = i
	var fitted := fit(tpl, markers)
	var J: Array = []
	var min_clear := INF
	for i in joints.size():
		# minimal move: a fitted joint that is already inside with CLEAR_WANT to spare stays (it keeps the template's bone directions)
		var p: Vector3 = fitted[i]
		var c := surface_distance(mesh.verts, td["tris"], p)
		if c < CLEAR_WANT or not inside_exact(mesh.verts, td["tris"], td["comp"], p):
			p = _push_in(fitted[i], g, mask, e)
			c = surface_distance(mesh.verts, td["tris"], p)
		if c < CLEAR_WANT:   # thin place: look at every voxel round it by the exact distance
			var ipos := Vector3i(floori((p.x - org.x) / vs), floori((p.y - org.y) / vs), floori((p.z - org.z) / vs))
			for z in range(ipos.z - 2, ipos.z + 3):
				for y in range(ipos.y - 2, ipos.y + 3):
					for x in range(ipos.x - 2, ipos.x + 3):
						if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz or mask[x + nx * (y + ny * z)] == 0:
							continue
						var q := org + Vector3(x + 0.5, y + 0.5, z + 0.5) * vs
						var cq := surface_distance(mesh.verts, td["tris"], q)
						if cq > c:
							c = cq
							p = q
		min_clear = minf(min_clear, c)
		J.append({"name": joints[i][0], "parent": jat[joints[i][1]] if joints[i][1] != "" else -1, "pos": p})
	# bones: one per joint, its segments to its children's joints; a leaf gets a stub along its parent's direction
	var sa := PackedVector3Array()
	var sb := PackedVector3Array()
	var sbone := PackedInt32Array()
	for b in J.size():
		var has_child := false
		for c in J.size():
			if int(J[c]["parent"]) == b:
				sa.append(J[b]["pos"])
				sb.append(J[c]["pos"])
				sbone.append(b)
				has_child = true
		if not has_child:
			var pa := int(J[b]["parent"])
			var dir := Vector3.UP
			var ln := 0.05
			if pa >= 0:
				var dv: Vector3 = (J[b]["pos"] as Vector3) - (J[pa]["pos"] as Vector3)
				if dv.length() > 1e-6:
					dir = dv.normalized()
					ln = dv.length() * 0.4
			sa.append(J[b]["pos"])
			sb.append((J[b]["pos"] as Vector3) + dir * ln)
			sbone.append(b)
	var R: float = maxf(float(opts.get("r_frac", BLEND_FRAC)) * float(g["longest"]), EDGE_K * _edge95(mesh))
	var bw: Dictionary = nat.bind(mask, vs, nx, ny, nz, org, sa, sb, sbone, J.size(), R, int(opts.get("smooth", SMOOTH))) if nat != null else bind_gd(mask, vs, nx, ny, nz, org, sa, sb, sbone, J.size(), R, int(opts.get("smooth", SMOOTH)))
	var vw := _vertex_weights(mesh.verts, mask, bw, J.size(), g, sa, sb, sbone)
	return {"ok": true, "why": "", "template": template_name, "joints": J, "ids": vw["ids"], "w": vw["w"],
		"grid": {"mask": mask, "vs": vs, "origin": org, "nx": nx, "ny": ny, "nz": nz},
		"info": {"ms": Time.get_ticks_msec() - t0, "native": nat != null, "vs": vs, "cells": cells, "min_clear": min_clear, "voxels": nin}}


## each vertex: a tent-kernel blend (radius 1.5 voxels, inside voxels only: continuous in the vertex position) of the 27 voxels round it, its 4 largest weights, normalised
## the 95th percentile of the mesh's edge lengths
static func _edge95(mesh: KMesh) -> float:
	var ls := PackedFloat64Array()
	for f in mesh.faces:
		var fa := f as PackedInt32Array
		for k in fa.size():
			ls.append(mesh.verts[fa[k]].distance_to(mesh.verts[fa[(k + 1) % fa.size()]]))
	if ls.is_empty():
		return 0.0
	ls.sort()
	return ls[mini(ls.size() - 1, int(ls.size() * 0.95))]


static func _vertex_weights(verts: PackedVector3Array, mask: PackedByteArray, bw: Dictionary, nb: int, g: Dictionary, sa: PackedVector3Array, sb: PackedVector3Array, sbone: PackedInt32Array) -> Dictionary:
	var vs: float = g["vs"]
	var org: Vector3 = g["origin"]
	var nx: int = g["nx"]
	var ny: int = g["ny"]
	var nz: int = g["nz"]
	var N := nx * ny * nz
	var cid := PackedInt32Array()
	cid.resize(N)
	cid.fill(-1)
	var k := 0
	for i in N:
		if mask[i] != 0:
			cid[i] = k
			k += 1
	var W: PackedFloat32Array = bw["w"]
	var ids := PackedInt32Array()
	var w := PackedFloat32Array()
	ids.resize(verts.size() * 4)
	w.resize(verts.size() * 4)
	var acc := PackedFloat64Array()
	acc.resize(nb)
	for vi in verts.size():
		var p := verts[vi]
		acc.fill(0.0)
		var tot := 0.0
		var ix0 := floori((p.x - org.x) / vs)
		var iy0 := floori((p.y - org.y) / vs)
		var iz0 := floori((p.z - org.z) / vs)
		var rad := 1.5 * vs
		for z in range(iz0 - 1, iz0 + 2):
			for y in range(iy0 - 1, iy0 + 2):
				for x in range(ix0 - 1, ix0 + 2):
					if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz:
						continue
					var q := cid[x + nx * (y + ny * z)]
					if q < 0:
						continue
					var dd := (org + Vector3(x + 0.5, y + 0.5, z + 0.5) * vs).distance_to(p)
					if dd >= rad:
						continue
					var cf := 1.0 - dd / rad
					tot += cf
					var base := q * nb
					for b in nb:
						var wv := W[base + b]
						if wv != 0.0:
							acc[b] += cf * wv
		if tot <= 1e-9:   # no inside voxel among the eight: the nearest one
			var best := INF
			var bq := -1
			var ix := floori((p.x - org.x) / vs)
			var iy := floori((p.y - org.y) / vs)
			var iz := floori((p.z - org.z) / vs)
			for r in range(1, 6):
				for z in range(iz - r, iz + r + 1):
					for y in range(iy - r, iy + r + 1):
						for x in range(ix - r, ix + r + 1):
							if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz:
								continue
							var q2 := cid[x + nx * (y + ny * z)]
							if q2 < 0:
								continue
							var d := (org + Vector3(x + 0.5, y + 0.5, z + 0.5) * vs).distance_to(p)
							if d < best:
								best = d
								bq = q2
				if bq >= 0:
					break
			if bq >= 0:
				for b in nb:
					acc[b] = W[bq * nb + b]
				tot = 1.0
		if tot <= 1e-9:   # still nothing: the nearest bone segment
			var bd := INF
			var bb := 0
			for s in sbone.size():
				var sd := _seg_dist(p.x, p.y, p.z, sa[s], sb[s])
				if sd < bd:
					bd = sd
					bb = sbone[s]
			acc[bb] = 1.0
			tot = 1.0
		# the four largest
		var pick := []
		var rest := acc.duplicate()
		for q in 4:
			var bi := 0
			var bv := -1.0
			for b in nb:
				if rest[b] > bv:
					bv = rest[b]
					bi = b
			if bv <= 1e-9:
				break
			pick.append([bi, bv])
			rest[bi] = -1.0
		var s4 := 0.0
		for pk in pick:
			s4 += pk[1]
		for q in 4:
			if q < pick.size():
				ids[vi * 4 + q] = pick[q][0]
				w[vi * 4 + q] = pick[q][1] / s4
			else:
				ids[vi * 4 + q] = -1
				w[vi * 4 + q] = 0.0
	return {"ids": ids, "w": w}


## ---- the character ------------------------------------------------------------------------------------------------------------------
## Skeleton3D + skinned MeshInstance3D from a build result -> CharImport.from_node's dict ("root" is the caller's to add or free)
static func to_character(mesh: KMesh, res: Dictionary) -> Dictionary:
	if not res.get("ok", false):
		return _fail(String(res.get("why", "no rig")))
	var root := Node3D.new()
	root.name = "AutoRig"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	var J: Array = res["joints"]
	var glob := []
	for i in J.size():
		sk.add_bone(J[i]["name"])
	for i in J.size():
		var pa := int(J[i]["parent"])
		sk.set_bone_parent(i, pa)
		var local: Vector3 = (J[i]["pos"] as Vector3) - ((J[pa]["pos"] as Vector3) if pa >= 0 else Vector3.ZERO)
		sk.set_bone_rest(i, Transform3D(Basis(), local))
	sk.reset_bone_poses()
	var skin := Skin.new()
	for i in J.size():
		skin.add_named_bind(J[i]["name"], Transform3D(Basis(), -(J[i]["pos"] as Vector3)))
	var idx := PackedInt32Array()
	for f in mesh.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size() - 1):
			idx.append(fa[0])
			idx.append(fa[k])
			idx.append(fa[k + 1])
	var bones := PackedInt32Array()
	bones.resize((res["ids"] as PackedInt32Array).size())
	for i in bones.size():
		bones[i] = maxi(res["ids"][i], 0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = mesh.verts
	arr[Mesh.ARRAY_NORMAL] = mesh.vert_normals
	arr[Mesh.ARRAY_INDEX] = idx
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = res["w"]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = am
	mi.skin = skin
	root.add_child(mi)
	mi.skeleton = NodePath("../Skeleton3D")
	var ch := CharImport.from_node(root)
	if not ch["ok"]:
		root.free()
		return ch
	ch["path"] = "autorig:" + String(res.get("template", ""))
	return ch


## the weights as KMeshAutoWeights' two vertex channels on `mesh` (what its weight-paint and deform tools read)
static func write_channels(mesh: KMesh, res: Dictionary) -> void:
	var nv := mesh.verts.size()
	var cb := PackedColorArray()
	var cw := PackedColorArray()
	for i in nv:
		var ids: PackedInt32Array = res["ids"]
		var w: PackedFloat32Array = res["w"]
		cb.append(Color(ids[i * 4], ids[i * 4 + 1], ids[i * 4 + 2], ids[i * 4 + 3]))
		cw.append(Color(w[i * 4], w[i * 4 + 1], w[i * 4 + 2], w[i * 4 + 3]))
	for chn in [[KMeshAutoWeights.CH_BONES, cb, Color(-1, -1, -1, -1)], [KMeshAutoWeights.CH_WEIGHTS, cw, Color(0, 0, 0, 0)]]:
		if not mesh.has_attr(chn[0]):
			mesh.add_attr(chn[0], KMesh.AD_VERT, TYPE_COLOR, chn[2])
		mesh.set_attr_data(chn[0], chn[1])


## the character posed by Kine's pose B (CharImport.pose) and then STANDING ON THE FLOOR: the skeleton is a fitted one, not the mannequin's,
## so its feet are a few mm to a few cm off where Kine's sole is (bone directions turned to Kine's, a different ankle height). The root
## is moved straight up or down so that the lowest foot vertex of the skinned mesh sits at the height of Kine's lowest sole point
## (Body.sole_low, the same floor rule as Body.ground). Returns the shift in metres.
static func pose(ch: Dictionary, mapping: Dictionary, ft: Dictionary, B: Body) -> float:
	CharImport.pose(ch, mapping, ft, B)
	if not ch.has("_feet"):
		ch["_feet"] = _foot_verts(ch, mapping)
	var feet: PackedInt32Array = ch["_feet"]
	if feet.is_empty():
		return 0.0
	var sk: Skeleton3D = ch["sk"]
	var pts: PackedVector3Array = (CharImport.skin_points(sk, (ch["meshes"] as Array)[0]) as Array)[0]
	var lo := INF
	for v in feet:
		lo = minf(lo, pts[v].y)
	var shift := B.sole_low() - lo
	var root := 0
	while sk.get_bone_parent(root) >= 0:
		root = sk.get_bone_parent(root)
	var xf := sk.get_bone_pose(root)
	xf.origin.y += shift
	sk.set_bone_pose(root, xf)
	return shift


## the vertices whose heaviest bone is a foot or a toe ball (cached on the character)
static func _foot_verts(ch: Dictionary, mapping: Dictionary) -> PackedInt32Array:
	var sk: Skeleton3D = ch["sk"]
	var want := {}
	for j in ["foot_l", "foot_r", "ball_l", "ball_r"]:
		if mapping["map"].has(j):
			want[int(mapping["map"][j])] = true
	var mi: MeshInstance3D = (ch["meshes"] as Array)[0]
	var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var nv := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var out := PackedInt32Array()
	for i in nv:
		var bi := -1
		var bw := 0.0
		for k in 4:
			if w[i * 4 + k] > bw:
				bw = w[i * 4 + k]
				bi = bo[i * 4 + k]
		if bi >= 0 and want.has(bi):
			out.append(i)
	return out


## ---- the session: markers, template, build, undo, save ------------------------------------------------------------------------------
class Session extends RefCounted:
	static var last_error := ""
	var mesh: KMesh
	var template := ""
	var markers := {}
	var result := {}
	var opts := {}
	var _undo: Array = []
	var _redo: Array = []

	func _init(m: KMesh = null) -> void:
		mesh = m

	func _snap() -> Dictionary:
		return {"template": template, "markers": markers.duplicate(), "result": result}

	func _restore(s: Dictionary) -> void:
		template = s["template"]
		markers = (s["markers"] as Dictionary).duplicate()
		result = s["result"]

	func _push() -> void:
		_undo.append(_snap())
		_redo.clear()

	func set_template(t: String) -> void:
		_push()
		template = t
		result = {}

	func place(marker_name: String, pos: Vector3) -> void:
		_push()
		markers[marker_name] = pos
		result = {}

	func remove(marker_name: String) -> void:
		if not markers.has(marker_name):
			return
		_push()
		markers.erase(marker_name)
		result = {}

	func build() -> bool:
		_push()
		result = AutoRig.build(mesh, template, markers, opts)
		return bool(result.get("ok", false))

	func undo() -> bool:
		if _undo.is_empty():
			return false
		_redo.append(_snap())
		_restore(_undo.pop_back())
		return true

	func redo() -> bool:
		if _redo.is_empty():
			return false
		_undo.append(_snap())
		_restore(_redo.pop_back())
		return true

	func to_dict() -> Dictionary:
		var mk := {}
		for k in markers:
			var v: Vector3 = markers[k]
			mk[k] = [v.x, v.y, v.z]
		var d := {"format": AutoRig.FORMAT, "version": AutoRig.VERSION, "template": template, "markers": mk, "verts": mesh.verts.size() if mesh != null else 0}
		if bool(result.get("ok", false)):
			var js := []
			for j in result["joints"]:
				var p: Vector3 = j["pos"]
				js.append({"name": j["name"], "parent": j["parent"], "pos": [p.x, p.y, p.z]})
			d["result"] = {"template": result["template"], "joints": js, "ids": Marshalls.raw_to_base64((result["ids"] as PackedInt32Array).to_byte_array()),
				"w": Marshalls.raw_to_base64((result["w"] as PackedFloat32Array).to_byte_array())}
		return d

	func save(path: String) -> bool:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			last_error = "could not write %s" % path
			return false
		f.store_string(JSON.stringify(to_dict()))
		f.close()
		return true

	static func from_dict(m: KMesh, d: Dictionary) -> Session:
		last_error = ""
		if String(d.get("format", "")) != AutoRig.FORMAT:
			last_error = "this is not a Kine quick-rig file (format '%s'): open a .autorig.json that Kine saved" % String(d.get("format", ""))
			return null
		if int(d.get("version", 0)) > AutoRig.VERSION:
			last_error = "this quick-rig file is from a newer Kine (version %d)" % int(d.get("version", 0))
			return null
		if m != null and int(d.get("verts", 0)) != m.verts.size():
			last_error = "the rig was made for a mesh of %d vertices, this one has %d: open the model it was made on" % [int(d.get("verts", 0)), m.verts.size()]
			return null
		var s := Session.new(m)
		s.template = String(d.get("template", ""))
		for k in d.get("markers", {}):
			var a: Array = d["markers"][k]
			s.markers[k] = Vector3(a[0], a[1], a[2])
		if d.has("result"):
			var r: Dictionary = d["result"]
			var js := []
			for j in r["joints"]:
				js.append({"name": String(j["name"]), "parent": int(j["parent"]), "pos": Vector3(j["pos"][0], j["pos"][1], j["pos"][2])})
			s.result = {"ok": true, "why": "", "template": String(r["template"]), "joints": js,
				"ids": Marshalls.base64_to_raw(r["ids"]).to_int32_array(), "w": Marshalls.base64_to_raw(r["w"]).to_float32_array(), "info": {}}
		return s

	static func load_from(m: KMesh, path: String) -> Session:
		last_error = ""
		if not FileAccess.file_exists(path):
			last_error = "%s does not exist" % path.get_file()
			return null
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary:
			last_error = "%s is not a readable quick-rig file" % path.get_file()
			return null
		return from_dict(m, d)
