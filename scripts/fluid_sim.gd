class_name FluidSim
extends RefCounted
## CH8: the GDScript twin of native/src/kine_fluid_native.cpp (KineFluidNative), the fallback when the DLL is missing. Same algorithm, same loop
## order, doubles: for a 16^3 grid it matches the C++ to ~1e-12 (threads = 1). It is slow (a tiny grid only) and has no mesh voxeliser, no surface
## extraction and no in-mesh check (those are native-only). Papers: Zhu & Bridson 2005, Jiang et al. 2015 (APIC), Bridson's fluid notes (MIC(0) PCG).
## Use Fluid.make() to get whichever exists.

var nx := 0
var ny := 0
var nz := 0
var h := 0.01
var o := Vector3.ZERO
var grav := 9.81
var drift := 0.2
var cfl := 0.5
var dtmax := 0.01
var tol := 1e-6
var max_iter := 300
var ppc := 8
var wlaw := 0
var release_delay := 0.0   # L44: seconds the fluid is held (a diaphragm) before the clock of advance() starts moving it
var wnu := 1e-6
var wfr := 0.0   # wall friction: 0 = free slip, 1 = no slip
## CUT-CELL walls (twin of the C++ block; Batty, Bertails and Bridson 2007). phi: solid signed distance on the cell corners (< 0 inside); wxp/wyp/wzp[c]:
## open fraction of the face between cell c and c+1 / c+nx / c+nx*ny. Without a cut solid they are 0/1 from the solid voxels.
var cut := false
var wdirty := true
var wmin := 0.02
var push_margin := 0.02
var phi := PackedFloat64Array()
var wxp := PackedFloat64Array()
var wyp := PackedFloat64Array()
var wzp := PackedFloat64Array()
var vfrac := PackedFloat64Array()
var solid := PackedByteArray()
var type := PackedByteArray()
var cnt := PackedInt32Array()
var P := PackedFloat64Array()
var V := PackedFloat64Array()
var C := PackedFloat64Array()
var U := PackedFloat64Array()
var Vg := PackedFloat64Array()
var W := PackedFloat64Array()
var mU := PackedFloat64Array()
var mV := PackedFloat64Array()
var mW := PackedFloat64Array()
var pr := PackedFloat64Array()
var rhs := PackedFloat64Array()
var rr := PackedFloat64Array()
var zz := PackedFloat64Array()
var ss := PackedFloat64Array()
var qq := PackedFloat64Array()
var pre := PackedFloat64Array()
var adiag := PackedFloat64Array()
var dq := PackedFloat64Array()
var db := PackedFloat64Array()
var dmode := 1   # 0 = density drift as a pressure source in the velocity solve (first version), 1 = implicit density projection on positions
var idp_tol := 1e-3
var idp_max := 60
var extrap := 1   # velocity extrapolation into the air after the projection (1 = on)
var fl := PackedInt32Array()
var vmax := 0.0
var last_iters := 0


func setup(p_nx: int, p_ny: int, p_nz: int, p_h: float, p_origin: Vector3) -> void:
	nx = p_nx
	ny = p_ny
	nz = p_nz
	h = p_h
	o = p_origin
	var nc := nx * ny * nz
	solid = PackedByteArray()
	solid.resize(nc)
	type = PackedByteArray()
	type.resize(nc)
	cnt = PackedInt32Array()
	cnt.resize(nc)
	for k in nz:
		for j in ny:
			for i in nx:
				if i == 0 or j == 0 or k == 0 or i == nx - 1 or j == ny - 1 or k == nz - 1:
					solid[i + nx * (j + ny * k)] = 1
	U = _zeros((nx + 1) * ny * nz)
	mU = U.duplicate()
	Vg = _zeros(nx * (ny + 1) * nz)
	mV = Vg.duplicate()
	W = _zeros(nx * ny * (nz + 1))
	mW = W.duplicate()
	pr = _zeros(nc)
	rhs = pr.duplicate()
	rr = pr.duplicate()
	zz = pr.duplicate()
	ss = pr.duplicate()
	qq = pr.duplicate()
	pre = pr.duplicate()
	adiag = pr.duplicate()
	dq = pr.duplicate()
	db = pr.duplicate()
	cut = false
	wdirty = true
	phi = PackedFloat64Array()
	wxp = PackedFloat64Array()
	wyp = PackedFloat64Array()
	wzp = PackedFloat64Array()
	P = PackedFloat64Array()
	V = PackedFloat64Array()
	C = PackedFloat64Array()


func _zeros(n: int) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(n)
	return a


func set_threads(_n: int) -> void:
	pass


func set_density_mode(m: int) -> void:
	dmode = m


func set_extrapolation(on: int) -> void:
	extrap = on


func set_release_delay(t: float) -> void:
	release_delay = maxf(t, 0.0)


func set_wall_law(mask: int, nu: float) -> void:
	wlaw = mask
	wnu = nu if nu > 0.0 else 1e-6


func set_wall_friction(f: float) -> void:
	wfr = clampf(f, 0.0, 1.0)


static func _wall_utau(au: float, y: float, nu: float) -> float:
	if au <= 0.0:
		return 0.0
	var kappa := 0.41
	var E := exp(0.41 * 5.2)
	var uv := sqrt(nu * au / y)
	if y * uv / nu < 11.06:
		return uv
	var ut := 0.05 * au
	for it in 30:
		ut = kappa * au / log(E * y * ut / nu)
	return ut


## A face that touches a solid wall sideways keeps (1 - wfr) of its speed; the L44 wall law removes u_tau^2 dt / h (same loops as the C++ twin).
func _wall_friction(dt: float) -> void:
	if wfr <= 0.0 and wlaw == 0:
		return
	var s := 1.0 - wfr
	var off := [1, nx, nx * ny]
	for c in fl:
		for ax in 3:
			for side in 2:
				var a: int = c - off[ax] if side == 0 else c
				var b: int = c if side == 0 else c + off[ax]
				if side == 1 and type[b] == 1:
					continue
				var touch := false
				var nw := 0
				for t in 3:
					if t == ax:
						continue
					var lo: bool = solid[a - off[t]] != 0 or solid[b - off[t]] != 0
					var hi: bool = solid[a + off[t]] != 0 or solid[b + off[t]] != 0
					if lo or hi:
						touch = true
					if (wlaw >> t) & 1:
						nw += (1 if lo else 0) + (1 if hi else 0)
				if not touch:
					continue
				var i: int = b % nx
				var j: int = (b / nx) % ny
				var k: int = b / (nx * ny)
				var idx: int
				if ax == 0:
					idx = i + (nx + 1) * (j + ny * k)
				elif ax == 1:
					idx = i + nx * (j + (ny + 1) * k)
				else:
					idx = i + nx * (j + ny * k)
				var g: PackedFloat64Array = U if ax == 0 else (Vg if ax == 1 else W)
				if wfr > 0.0:
					g[idx] *= s
				if nw > 0:
					var au: float = absf(g[idx])
					if au > 1e-12:
						var fill: float = float(cnt[c]) / float(ppc)
						var dep: float = h * (1.0 if fill > 1.0 else (0.1 if fill < 0.1 else fill))
						var ut := _wall_utau(au, 0.5 * dep, wnu)
						var fac: float = 1.0 - dt * nw * ut * ut / (dep * au)
						g[idx] *= fac if fac > 0.0 else 0.0


func set_params(p_g: float, p_drift: float, p_cfl: float, p_dtmax: float, p_iters: int, p_tol: float) -> void:
	grav = p_g
	drift = p_drift
	cfl = p_cfl
	dtmax = p_dtmax
	max_iter = p_iters
	tol = p_tol


func particle_count() -> int:
	return P.size() / 3


func clear_particles() -> void:
	P = PackedFloat64Array()
	V = PackedFloat64Array()
	C = PackedFloat64Array()


func add_solid_box(mn: Vector3, mx: Vector3) -> void:
	wdirty = true
	for k in nz:
		for j in ny:
			for i in nx:
				var cx := o.x + (i + 0.5) * h
				var cy := o.y + (j + 0.5) * h
				var cz := o.z + (k + 0.5) * h
				if cx >= mn.x and cx <= mx.x and cy >= mn.y and cy <= mx.y and cz >= mn.z and cz <= mx.z:
					solid[i + nx * (j + ny * k)] = 1


## ---- cut-cell walls (twin of the C++ block). Native-only: add_cut_mesh.
func _nid(i: int, j: int, k: int) -> int:
	return i + (nx + 1) * (j + (ny + 1) * k)


func add_cut_box(mn: Vector3, mx: Vector3) -> void:
	cut = true
	wdirty = true
	if phi.size() == 0:
		phi.resize((nx + 1) * (ny + 1) * (nz + 1))
		phi.fill(1e9)
	var c := [0.5 * (mn.x + mx.x), 0.5 * (mn.y + mx.y), 0.5 * (mn.z + mx.z)]
	var hf := [0.5 * (mx.x - mn.x), 0.5 * (mx.y - mn.y), 0.5 * (mx.z - mn.z)]
	for k in nz + 1:
		for j in ny + 1:
			for i in nx + 1:
				var p := [o.x + i * h, o.y + j * h, o.z + k * h]
				var out2 := 0.0
				var mq := -1e30
				for a in 3:
					var q: float = absf(p[a] - c[a]) - hf[a]
					if q > 0.0:
						out2 += q * q
					mq = maxf(mq, q)
				var d := sqrt(out2) + minf(mq, 0.0)
				var id := _nid(i, j, k)
				phi[id] = minf(phi[id], d)


func add_cut_halfspace(pt: Vector3, nrm: Vector3) -> void:
	cut = true
	wdirty = true
	if phi.size() == 0:
		phi.resize((nx + 1) * (ny + 1) * (nz + 1))
		phi.fill(1e9)
	var l := sqrt(nrm.x * nrm.x + nrm.y * nrm.y + nrm.z * nrm.z)
	var n := [nrm.x / l, nrm.y / l, nrm.z / l]
	for k in nz + 1:
		for j in ny + 1:
			for i in nx + 1:
				var d: float = (o.x + i * h - pt.x) * n[0] + (o.y + j * h - pt.y) * n[1] + (o.z + k * h - pt.z) * n[2]
				var id := _nid(i, j, k)
				phi[id] = minf(phi[id], d)


func add_cut_mesh(_verts: PackedVector3Array, _tris: PackedInt32Array) -> int:
	push_warning("FluidSim: add_cut_mesh is native-only")
	return 0


func set_cut_wmin(w: float) -> void:
	wmin = w
	wdirty = true


static func _tri_neg(a: float, b: float, c: float) -> float:
	var n := (1 if a < 0.0 else 0) + (1 if b < 0.0 else 0) + (1 if c < 0.0 else 0)
	if n == 0:
		return 0.0
	if n == 3:
		return 1.0
	if n == 1:
		var s: float
		var p: float
		var q: float
		if a < 0.0:
			s = a
			p = b
			q = c
		elif b < 0.0:
			s = b
			p = a
			q = c
		else:
			s = c
			p = a
			q = b
		return (s / (s - p)) * (s / (s - q))
	var x: float
	var y: float
	var z: float
	if a >= 0.0:
		x = a
		y = b
		z = c
	elif b >= 0.0:
		x = b
		y = a
		z = c
	else:
		x = c
		y = a
		z = b
	return 1.0 - (x / (x - y)) * (x / (x - z))


static func _face_open(p00: float, p10: float, p11: float, p01: float) -> float:
	var m := 0.25 * (p00 + p10 + p11 + p01)
	var neg := _tri_neg(p00, p10, m) + _tri_neg(p10, p11, m) + _tri_neg(p11, p01, m) + _tri_neg(p01, p00, m)
	return 1.0 - 0.25 * neg


func rebuild_weights() -> void:
	wdirty = false
	var nc := nx * ny * nz
	wxp = _zeros(nc)
	wyp = _zeros(nc)
	wzp = _zeros(nc)
	for k in nz:
		for j in ny:
			for i in nx:
				var c := _cid(i, j, k)
				if solid[c] != 0:
					continue
				if i < nx - 1 and solid[c + 1] == 0:
					var f := 1.0
					if cut:
						f = _face_open(phi[_nid(i + 1, j, k)], phi[_nid(i + 1, j + 1, k)], phi[_nid(i + 1, j + 1, k + 1)], phi[_nid(i + 1, j, k + 1)])
					wxp[c] = 0.0 if f < wmin else f
				if j < ny - 1 and solid[c + nx] == 0:
					var f := 1.0
					if cut:
						f = _face_open(phi[_nid(i, j + 1, k)], phi[_nid(i + 1, j + 1, k)], phi[_nid(i + 1, j + 1, k + 1)], phi[_nid(i, j + 1, k + 1)])
					wyp[c] = 0.0 if f < wmin else f
				if k < nz - 1 and solid[c + nx * ny] == 0:
					var f := 1.0
					if cut:
						f = _face_open(phi[_nid(i, j, k + 1)], phi[_nid(i + 1, j, k + 1)], phi[_nid(i + 1, j + 1, k + 1)], phi[_nid(i, j + 1, k + 1)])
					wzp[c] = 0.0 if f < wmin else f
	if cut:
		for k in range(1, nz - 1):
			for j in range(1, ny - 1):
				for i in range(1, nx - 1):
					var c := _cid(i, j, k)
					if solid[c] != 0:
						continue
					if wxp[c] == 0.0 and wxp[c - 1] == 0.0 and wyp[c] == 0.0 and wyp[c - nx] == 0.0 and wzp[c] == 0.0 and wzp[c - nx * ny] == 0.0:
						solid[c] = 1
	vfrac = _zeros(nc)
	vfrac.fill(1.0)
	if cut:
		for k in nz:
			for j in ny:
				for i in nx:
					var neg := 0
					for q in 8:
						if phi[_nid(i + (q & 1), j + ((q >> 1) & 1), k + (q >> 2))] < 0.0:
							neg += 1
					var f := 1.0
					if neg == 8:
						f = 0.0
					elif neg > 0:
						var n := 0
						for c in 64:
							var x := o.x + (i + ((c & 3) + 0.5) / 4.0) * h
							var y := o.y + (j + (((c >> 2) & 3) + 0.5) / 4.0) * h
							var z := o.z + (k + ((c >> 4) + 0.5) / 4.0) * h
							if phi_at(x, y, z) >= 0.0:
								n += 1
						f = n / 64.0
					vfrac[_cid(i, j, k)] = maxf(0.05, f)


func face_weights() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.append_array(wxp)
	out.append_array(wyp)
	out.append_array(wzp)
	return out


## [phi, gx, gy, gz] by trilinear interpolation of the corner field (indices clamp outside the grid)
func _phi_g(x: float, y: float, z: float) -> Array:
	var q := [(x - o.x) / h, (y - o.y) / h, (z - o.z) / h]
	var b := [0, 0, 0]
	var f := [0.0, 0.0, 0.0]
	var dim := [nx, ny, nz]
	for a in 3:
		var ba := int(floor(q[a]))
		if ba < 0:
			ba = 0
		if ba > dim[a] - 1:
			ba = dim[a] - 1
		b[a] = ba
		f[a] = minf(1.0, maxf(0.0, q[a] - ba))
	var r := 0.0
	var gx := 0.0
	var gy := 0.0
	var gz := 0.0
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var wx: float = f[0] if dx == 1 else 1.0 - f[0]
				var wy: float = f[1] if dy == 1 else 1.0 - f[1]
				var wz: float = f[2] if dz == 1 else 1.0 - f[2]
				var val := phi[_nid(b[0] + dx, b[1] + dy, b[2] + dz)]
				r += wx * wy * wz * val
				gx += (1.0 if dx == 1 else -1.0) * wy * wz * val
				gy += (1.0 if dy == 1 else -1.0) * wx * wz * val
				gz += (1.0 if dz == 1 else -1.0) * wx * wy * val
	return [r, gx / h, gy / h, gz / h]


func phi_at(x: float, y: float, z: float) -> float:
	return _phi_g(x, y, z)[0]


func _push_out() -> void:
	if not cut or phi.size() == 0:
		return
	var m := push_margin * h
	for p in particle_count():
		for it in 3:
			var r := _phi_g(P[3 * p], P[3 * p + 1], P[3 * p + 2])
			var d: float = r[0]
			if d >= m:
				break
			var gl := sqrt(r[1] * r[1] + r[2] * r[2] + r[3] * r[3])
			if gl < 0.25:
				break
			var n := [r[1] / gl, r[2] / gl, r[3] / gl]
			var sft := (m - d) / gl
			for a in 3:
				P[3 * p + a] += sft * n[a]
			var vn: float = V[3 * p] * n[0] + V[3 * p + 1] * n[1] + V[3 * p + 2] * n[2]
			if vn < 0.0:
				for a in 3:
					V[3 * p + a] -= vn * n[a]


func open_volume() -> float:
	var tot := 0.0
	for k in range(1, nz - 1):
		for j in range(1, ny - 1):
			for i in range(1, nx - 1):
				if not cut and solid[_cid(i, j, k)] != 0:
					continue
				var n := 0
				for c in 64:
					var x := o.x + (i + ((c & 3) + 0.5) / 4.0) * h
					var y := o.y + (j + (((c >> 2) & 3) + 0.5) / 4.0) * h
					var z := o.z + (k + ((c >> 4) + 0.5) / 4.0) * h
					if (not cut) or phi_at(x, y, z) >= 0.0:
						n += 1
				tot += n / 64.0
	return tot * h * h * h


func add_solid_mesh(_verts: PackedVector3Array, _tris: PackedInt32Array) -> int:
	push_warning("FluidSim: add_solid_mesh is native-only")
	return 0


static func hash32(x_in: int) -> int:
	var x := x_in & 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 0x7feb352d) & 0xFFFFFFFF
	x ^= x >> 15
	x = (x * 0x846ca68b) & 0xFFFFFFFF
	x ^= x >> 16
	return x


func add_fluid_box(mn: Vector3, mx: Vector3, vel: Vector3, seed_i: int) -> int:
	var i0 := int(floor((mn.x - o.x) / h + 1e-9))
	var i1 := int(ceil((mx.x - o.x) / h - 1e-9)) - 1
	var j0 := int(floor((mn.y - o.y) / h + 1e-9))
	var j1 := int(ceil((mx.y - o.y) / h - 1e-9)) - 1
	var k0 := int(floor((mn.z - o.z) / h + 1e-9))
	var k1 := int(ceil((mx.z - o.z) / h - 1e-9)) - 1
	var added := 0
	for k in range(k0, k1 + 1):
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz or solid[i + nx * (j + ny * k)] != 0:
					continue
				var c := i + nx * (j + ny * k)
				for s in 8:
					var sub := [s & 1, (s >> 1) & 1, (s >> 2) & 1]
					var cell := [i, j, k]
					var pos := [0.0, 0.0, 0.0]
					for a in 3:
						var key := ((c * 24 + s * 3 + a) + (seed_i * 1000003)) & 0xFFFFFFFF
						var u := float(hash32(key)) / 4294967296.0
						pos[a] = (cell[a] + 0.5 * sub[a] + 0.5 * (0.1 + 0.8 * u)) * h
					if cut and phi.size() > 0 and phi_at(o.x + pos[0], o.y + pos[1], o.z + pos[2]) < push_margin * h:
						continue
					P.append(o.x + pos[0])
					P.append(o.y + pos[1])
					P.append(o.z + pos[2])
					V.append(vel.x)
					V.append(vel.y)
					V.append(vel.z)
					for q in 9:
						C.append(0.0)
					added += 1
	return added


func _cid(i: int, j: int, k: int) -> int:
	return i + nx * (j + ny * k)


func _mark() -> void:
	cnt.fill(0)
	var N := particle_count()
	for p in N:
		var i := int(floor((P[3 * p] - o.x) / h))
		var j := int(floor((P[3 * p + 1] - o.y) / h))
		var k := int(floor((P[3 * p + 2] - o.z) / h))
		if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz:
			continue
		cnt[_cid(i, j, k)] += 1
	fl = PackedInt32Array()
	for c in nx * ny * nz:
		if solid[c] != 0:
			type[c] = 2
		elif cnt[c] > 0:
			type[c] = 1
			fl.append(c)
		else:
			type[c] = 0
	# an empty cut cell whose upper neighbour is fluid is fluid too (see the C++ twin); top to bottom
	if cut and vfrac.size() > 0:
		var add := false
		for k in range(1, nz - 1):
			for j in range(ny - 2, 0, -1):
				for i in range(1, nx - 1):
					var c := _cid(i, j, k)
					if type[c] == 0 and vfrac[c] < 1.0 and type[c + nx] == 1:
						type[c] = 1
						fl.append(c)
						add = true
		if add:
			fl.sort()


## [base, f, w0, w1, w2]
static func _w3(q: float) -> Array:
	var base := int(floor(q - 0.5))
	var f := q - base
	var a := 1.5 - f
	var b := f - 1.0
	var c := f - 0.5
	return [base, f, 0.5 * a * a, 0.75 - b * b, 0.5 * c * c]


func _p2g() -> void:
	U.fill(0.0)
	mU.fill(0.0)
	Vg.fill(0.0)
	mV.fill(0.0)
	W.fill(0.0)
	mW.fill(0.0)
	var N := particle_count()
	for p in N:
		for c in 3:
			var off := [0.5, 0.5, 0.5]
			off[c] = 0.0
			var dim := [nx, ny, nz]
			dim[c] += 1
			var mom: PackedFloat64Array = U if c == 0 else (Vg if c == 1 else W)
			var ws: PackedFloat64Array = mU if c == 0 else (mV if c == 1 else mW)
			var wx := _w3((P[3 * p] - o.x) / h - off[0])
			var wy := _w3((P[3 * p + 1] - o.y) / h - off[1])
			var wz := _w3((P[3 * p + 2] - o.z) / h - off[2])
			for kk in 3:
				var nk: int = wz[0] + kk
				if nk < 0 or nk >= dim[2]:
					continue
				var dz: float = (kk - wz[1]) * h
				for jj in 3:
					var nj: int = wy[0] + jj
					if nj < 0 or nj >= dim[1]:
						continue
					var dy: float = (jj - wy[1]) * h
					for ii in 3:
						var ni: int = wx[0] + ii
						if ni < 0 or ni >= dim[0]:
							continue
						var dx: float = (ii - wx[1]) * h
						var Wt: float = wx[2 + ii] * wy[2 + jj] * wz[2 + kk]
						var idx: int = ni + dim[0] * (nj + dim[1] * nk)
						mom[idx] += Wt * (V[3 * p + c] + C[9 * p + 3 * c] * dx + C[9 * p + 3 * c + 1] * dy + C[9 * p + 3 * c + 2] * dz)
						ws[idx] += Wt
			# PackedArrays copied by value into locals: write them back
			if c == 0:
				U = mom
				mU = ws
			elif c == 1:
				Vg = mom
				mV = ws
			else:
				W = mom
				mW = ws
	for n in U.size():
		U[n] = U[n] / mU[n] if mU[n] > 0.0 else 0.0
	for n in Vg.size():
		Vg[n] = Vg[n] / mV[n] if mV[n] > 0.0 else 0.0
	for n in W.size():
		W[n] = W[n] / mW[n] if mW[n] > 0.0 else 0.0


func _isf(c: int) -> bool:
	return type[c] == 1


func _ap(c: int, off: int) -> float:
	if type[c] == 1 and type[c + off] == 1:
		return -(wxp[c] if off == 1 else (wyp[c] if off == nx else wzp[c]))
	return 0.0


func _precond(r: PackedFloat64Array, z: PackedFloat64Array) -> void:
	var sx := 1
	var sy := nx
	var sz := nx * ny
	for c in fl:
		var t := r[c]
		if type[c - sx] == 1:
			t -= _ap(c - sx, sx) * pre[c - sx] * qq[c - sx]
		if type[c - sy] == 1:
			t -= _ap(c - sy, sy) * pre[c - sy] * qq[c - sy]
		if type[c - sz] == 1:
			t -= _ap(c - sz, sz) * pre[c - sz] * qq[c - sz]
		qq[c] = t * pre[c]
	for q in range(fl.size() - 1, -1, -1):
		var c := fl[q]
		var t := qq[c]
		if type[c + sx] == 1:
			t -= _ap(c, sx) * pre[c] * z[c + sx]
		if type[c + sy] == 1:
			t -= _ap(c, sy) * pre[c] * z[c + sy]
		if type[c + sz] == 1:
			t -= _ap(c, sz) * pre[c] * z[c + sz]
		z[c] = t * pre[c]


func _dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var s := 0.0
	for c in fl:
		s += a[c] * b[c]
	return s


func _pcg(x: PackedFloat64Array, b: PackedFloat64Array, tl: float, maxit: int, warm: bool) -> void:
	var n := fl.size()
	last_iters = 0
	if n == 0:
		return
	var sx := 1
	var sy := nx
	var sz := nx * ny
	for c in fl:
		var d := wxp[c - sx] + wxp[c] + wyp[c - sy] + wyp[c] + wzp[c - sz] + wzp[c]
		adiag[c] = d
	var tau := 0.97
	var sigma := 0.25
	for c in fl:
		var e := adiag[c]
		if type[c - sx] == 1:
			var m := c - sx
			var p := pre[m]
			e -= (_ap(m, sx) * p) * (_ap(m, sx) * p) + tau * (_ap(m, sx) * (_ap(m, sy) + _ap(m, sz)) * p * p)
		if type[c - sy] == 1:
			var m := c - sy
			var p := pre[m]
			e -= (_ap(m, sy) * p) * (_ap(m, sy) * p) + tau * (_ap(m, sy) * (_ap(m, sx) + _ap(m, sz)) * p * p)
		if type[c - sz] == 1:
			var m := c - sz
			var p := pre[m]
			e -= (_ap(m, sz) * p) * (_ap(m, sz) * p) + tau * (_ap(m, sz) * (_ap(m, sx) + _ap(m, sy)) * p * p)
		if e < sigma * adiag[c]:
			e = adiag[c]
		pre[c] = 1.0 / sqrt(e)
	var bmax := 0.0
	for c in fl:
		bmax = maxf(bmax, absf(b[c]))
	if bmax == 0.0:
		for c in fl:
			x[c] = 0.0
		return
	if not warm:
		for c in fl:
			x[c] = 0.0
	var r0 := 0.0
	for c in fl:
		var t := adiag[c] * x[c]
		if type[c - sx] == 1:
			t -= wxp[c - sx] * x[c - sx]
		if type[c + sx] == 1:
			t -= wxp[c] * x[c + sx]
		if type[c - sy] == 1:
			t -= wyp[c - sy] * x[c - sy]
		if type[c + sy] == 1:
			t -= wyp[c] * x[c + sy]
		if type[c - sz] == 1:
			t -= wzp[c - sz] * x[c - sz]
		if type[c + sz] == 1:
			t -= wzp[c] * x[c + sz]
		rr[c] = b[c] - t
		r0 = maxf(r0, absf(rr[c]))
	if r0 < tl * bmax:
		return
	_precond(rr, zz)
	for c in fl:
		ss[c] = zz[c]
	var sig := _dot(zz, rr)
	for it in maxit:
		for c in fl:
			var t := adiag[c] * ss[c]
			if type[c - sx] == 1:
				t -= wxp[c - sx] * ss[c - sx]
			if type[c + sx] == 1:
				t -= wxp[c] * ss[c + sx]
			if type[c - sy] == 1:
				t -= wyp[c - sy] * ss[c - sy]
			if type[c + sy] == 1:
				t -= wyp[c] * ss[c + sy]
			if type[c - sz] == 1:
				t -= wzp[c - sz] * ss[c - sz]
			if type[c + sz] == 1:
				t -= wzp[c] * ss[c + sz]
			zz[c] = t
		var den := _dot(ss, zz)
		if den == 0.0:
			break
		var al := sig / den
		var rmax := 0.0
		for c in fl:
			x[c] += al * ss[c]
			rr[c] -= al * zz[c]
			rmax = maxf(rmax, absf(rr[c]))
		last_iters = it + 1
		if rmax < tl * bmax:
			break
		_precond(rr, zz)
		var sig2 := _dot(zz, rr)
		var be := sig2 / sig
		sig = sig2
		for c in fl:
			ss[c] = zz[c] + be * ss[c]


func _project(dt: float) -> void:
	for n in Vg.size():
		Vg[n] -= grav * dt
	_wall_friction(dt)
	for k in nz:
		for j in ny:
			for i in nx + 1:
				var s := (i == 0 or i == nx) or wxp[_cid(i - 1, j, k)] == 0.0
				if s:
					U[i + (nx + 1) * (j + ny * k)] = 0.0
	for k in nz:
		for j in ny + 1:
			for i in nx:
				var s := (j == 0 or j == ny) or wyp[_cid(i, j - 1, k)] == 0.0
				if s:
					Vg[i + nx * (j + (ny + 1) * k)] = 0.0
	for k in nz + 1:
		for j in ny:
			for i in nx:
				var s := (k == 0 or k == nz) or wzp[_cid(i, j, k - 1)] == 0.0
				if s:
					W[i + nx * (j + ny * k)] = 0.0
	for c in pr.size():
		if type[c] != 1:
			pr[c] = 0.0
	var sc := h / dt
	for c in fl:
		var i := c % nx
		var j := (c / nx) % ny
		var k := c / (nx * ny)
		var div := wxp[c] * U[(i + 1) + (nx + 1) * (j + ny * k)] - wxp[c - 1] * U[i + (nx + 1) * (j + ny * k)] \
				+ wyp[c] * Vg[i + nx * ((j + 1) + (ny + 1) * k)] - wyp[c - nx] * Vg[i + nx * (j + (ny + 1) * k)] \
				+ wzp[c] * W[i + nx * (j + ny * (k + 1))] - wzp[c - nx * ny] * W[i + nx * (j + ny * k)]
		var eps := 0.0
		if dmode == 0:
			eps = minf(1.0, maxf(0.0, float(cnt[c]) / ppc - 1.0))
			if eps == 0.0 and cnt[c] < ppc and type[c - 1] == 1 and type[c + 1] == 1 and type[c - nx] == 1 and type[c + nx] == 1 and type[c - nx * ny] == 1 and type[c + nx * ny] == 1:
				eps = maxf(-0.5, float(cnt[c]) / ppc - 1.0)
		rhs[c] = -sc * div + sc * (h / maxf(dt, dtmax)) * drift * eps
	_pcg(pr, rhs, tol, max_iter, true)
	var f := dt / h
	for k in nz:
		for j in ny:
			for i in range(1, nx):
				var a := _cid(i - 1, j, k)
				var b := _cid(i, j, k)
				if wxp[a] == 0.0:
					continue
				if type[a] == 1 or type[b] == 1:
					U[i + (nx + 1) * (j + ny * k)] -= f * (pr[b] - pr[a])
	for k in nz:
		for j in range(1, ny):
			for i in nx:
				var a := _cid(i, j - 1, k)
				var b := _cid(i, j, k)
				if wyp[a] == 0.0:
					continue
				if type[a] == 1 or type[b] == 1:
					Vg[i + nx * (j + (ny + 1) * k)] -= f * (pr[b] - pr[a])
	for k in range(1, nz):
		for j in ny:
			for i in nx:
				var a := _cid(i, j, k - 1)
				var b := _cid(i, j, k)
				if wzp[a] == 0.0:
					continue
				if type[a] == 1 or type[b] == 1:
					W[i + nx * (j + ny * k)] -= f * (pr[b] - pr[a])
	if extrap == 1:
		_extrapolate()


## Velocity extrapolation into the air (twin of KineFluidNative::extrapolate; Bridson 2015): two layers of faces beyond the fluid get the mean of their
## valid face neighbours. Valid = touches a fluid cell. Faces on walls and solids stay as they are.
func _extrapolate() -> void:
	for c in 3:
		var g: PackedFloat64Array = U if c == 0 else (Vg if c == 1 else W)
		var d := [nx, ny, nz]
		d[c] += 1
		var st := [1, d[0], d[0] * d[1]]
		var cs := [1, nx, nx * ny]
		var tot := g.size()
		var vf := PackedByteArray()
		vf.resize(tot)
		for k in d[2]:
			for j in d[1]:
				for i in d[0]:
					var f: int = i + d[0] * (j + d[1] * k)
					var ij := [i, j, k]
					if ij[c] == 0 or ij[c] == d[c] - 1:
						vf[f] = 2
						continue
					var b: int = i + nx * (j + ny * k)
					var a: int = b - cs[c]
					# solid on exactly one side: the wall's normal velocity (fixed 0); solid on both sides: inside the wall, extrapolated (free slip)
					var wcl: bool = (wxp[a] if c == 0 else (wyp[a] if c == 1 else wzp[a])) == 0.0
					if wcl and not (type[a] == 2 and type[b] == 2):
						vf[f] = 2
					elif type[a] == 1 or type[b] == 1:
						vf[f] = 1
		for layer in 2:
			var nf := PackedByteArray()
			nf.resize(tot)
			for k in d[2]:
				for j in d[1]:
					for i in d[0]:
						var f: int = i + d[0] * (j + d[1] * k)
						if vf[f] != 0:
							continue
						var sum := 0.0
						var n := 0
						if i > 0 and vf[f - st[0]] == 1:
							sum += g[f - st[0]]
							n += 1
						if i < d[0] - 1 and vf[f + st[0]] == 1:
							sum += g[f + st[0]]
							n += 1
						if j > 0 and vf[f - st[1]] == 1:
							sum += g[f - st[1]]
							n += 1
						if j < d[1] - 1 and vf[f + st[1]] == 1:
							sum += g[f + st[1]]
							n += 1
						if k > 0 and vf[f - st[2]] == 1:
							sum += g[f - st[2]]
							n += 1
						if k < d[2] - 1 and vf[f + st[2]] == 1:
							sum += g[f + st[2]]
							n += 1
						if n > 0:
							g[f] = sum / n
							nf[f] = 1
			for f in tot:
				if nf[f] != 0:
					vf[f] = 1
		# g is a typed local copy of the member: write it back
		if c == 0:
			U = g
		elif c == 1:
			Vg = g
		else:
			W = g


## Density correction on POSITIONS (dmode 1): the twin of KineFluidNative::density_project (Kugelstadt et al., Implicit Density Projection for Volume
## Conserving Liquids, IEEE TVCG 2019; particle shifting: Xu, Stansby, Laurence 2009, Lind et al. 2012). A q = h * excess, d = -grad q, particles move by d.
func _density_project() -> void:
	var n := fl.size()
	if n == 0:
		return
	var sx := 1
	var sy := nx
	var sz := nx * ny
	for c in fl:
		var ex := 0.0
		var rest: float = ppc * vfrac[c]
		if vfrac[c] < 1.0:
			ex = 0.0
		elif cnt[c] > rest:
			ex = float(cnt[c]) / rest - 1.0
		elif cnt[c] < rest and type[c - sx] == 1 and type[c + sx] == 1 and type[c - sy] == 1 and type[c + sy] == 1 and type[c - sz] == 1 and type[c + sz] == 1:
			ex = maxf(-0.5, float(cnt[c]) / rest - 1.0)
		db[c] = h * ex
	for c in dq.size():
		if type[c] != 1:
			dq[c] = 0.0
	var saved := last_iters
	_pcg(dq, db, idp_tol, idp_max, false)
	last_iters = saved
	U.fill(0.0)
	Vg.fill(0.0)
	W.fill(0.0)
	for k in nz:
		for j in ny:
			for i in range(1, nx):
				var a := _cid(i - 1, j, k)
				var b := _cid(i, j, k)
				if wxp[a] == 0.0:
					continue
				if type[a] == 1 or type[b] == 1:
					U[i + (nx + 1) * (j + ny * k)] = -(dq[b] - dq[a])
	for k in nz:
		for j in range(1, ny):
			for i in nx:
				var a := _cid(i, j - 1, k)
				var b := _cid(i, j, k)
				if wyp[a] == 0.0:
					continue
				if type[a] == 1 or type[b] == 1:
					Vg[i + nx * (j + (ny + 1) * k)] = -(dq[b] - dq[a])
	for k in range(1, nz):
		for j in ny:
			for i in nx:
				var a := _cid(i, j, k - 1)
				var b := _cid(i, j, k)
				if wzp[a] == 0.0:
					continue
				if type[a] == 1 or type[b] == 1:
					W[i + nx * (j + ny * k)] = -(dq[b] - dq[a])
	var N := particle_count()
	var org := [o.x, o.y, o.z]
	var dimc := [nx, ny, nz]
	for p in N:
		var dsp := [0.0, 0.0, 0.0]
		for c in 3:
			var off := [0.5, 0.5, 0.5]
			off[c] = 0.0
			var dim := [nx, ny, nz]
			dim[c] += 1
			var g: PackedFloat64Array = U if c == 0 else (Vg if c == 1 else W)
			var wx := _w3((P[3 * p] - o.x) / h - off[0])
			var wy := _w3((P[3 * p + 1] - o.y) / h - off[1])
			var wz := _w3((P[3 * p + 2] - o.z) / h - off[2])
			var vs := 0.0
			for kk in 3:
				var nk: int = wz[0] + kk
				if nk < 0 or nk >= dim[2]:
					continue
				for jj in 3:
					var nj: int = wy[0] + jj
					if nj < 0 or nj >= dim[1]:
						continue
					for ii in 3:
						var ni: int = wx[0] + ii
						if ni < 0 or ni >= dim[0]:
							continue
						vs += wx[2 + ii] * wy[2 + jj] * wz[2 + kk] * g[ni + dim[0] * (nj + dim[1] * nk)]
			dsp[c] = vs
		for a in 3:
			var m := 0.5 * h
			var dd := maxf(-m, minf(m, dsp[a]))
			var nxp := [P[3 * p], P[3 * p + 1], P[3 * p + 2]]
			nxp[a] += dd
			var cc := [0, 0, 0]
			var bad := false
			for q in 3:
				cc[q] = int(floor((nxp[q] - org[q]) / h))
				if cc[q] < 0 or cc[q] >= dimc[q]:
					bad = true
			if not bad and solid[_cid(cc[0], cc[1], cc[2])] != 0:
				bad = true
			if not bad:
				P[3 * p + a] = nxp[a]
	_push_out()


func _g2p() -> void:
	var N := particle_count()
	var k4 := 4.0 / (h * h)
	for p in N:
		for c in 3:
			var off := [0.5, 0.5, 0.5]
			off[c] = 0.0
			var dim := [nx, ny, nz]
			dim[c] += 1
			var g: PackedFloat64Array = U if c == 0 else (Vg if c == 1 else W)
			var wx := _w3((P[3 * p] - o.x) / h - off[0])
			var wy := _w3((P[3 * p + 1] - o.y) / h - off[1])
			var wz := _w3((P[3 * p + 2] - o.z) / h - off[2])
			var vs := 0.0
			var c0 := 0.0
			var c1 := 0.0
			var c2 := 0.0
			for kk in 3:
				var nk: int = wz[0] + kk
				if nk < 0 or nk >= dim[2]:
					continue
				var dz: float = (kk - wz[1]) * h
				for jj in 3:
					var nj: int = wy[0] + jj
					if nj < 0 or nj >= dim[1]:
						continue
					var dy: float = (jj - wy[1]) * h
					for ii in 3:
						var ni: int = wx[0] + ii
						if ni < 0 or ni >= dim[0]:
							continue
						var dx: float = (ii - wx[1]) * h
						var Wt: float = wx[2 + ii] * wy[2 + jj] * wz[2 + kk]
						var u: float = g[ni + dim[0] * (nj + dim[1] * nk)]
						vs += Wt * u
						c0 += Wt * u * dx
						c1 += Wt * u * dy
						c2 += Wt * u * dz
			V[3 * p + c] = vs
			C[9 * p + 3 * c] = k4 * c0
			C[9 * p + 3 * c + 1] = k4 * c1
			C[9 * p + 3 * c + 2] = k4 * c2


func _advect(dt: float) -> void:
	var N := particle_count()
	var org := [o.x, o.y, o.z]
	var dim := [nx, ny, nz]
	vmax = 0.0
	for p in N:
		for a in 3:
			var np := [P[3 * p], P[3 * p + 1], P[3 * p + 2]]
			np[a] += dt * V[3 * p + a]
			var cc := [0, 0, 0]
			var bad := false
			for q in 3:
				cc[q] = int(floor((np[q] - org[q]) / h))
				if cc[q] < 0 or cc[q] >= dim[q]:
					bad = true
			if not bad and solid[_cid(cc[0], cc[1], cc[2])] != 0:
				bad = true
			if bad:
				V[3 * p + a] = 0.0
			else:
				P[3 * p + a] = np[a]
		vmax = maxf(vmax, sqrt(V[3 * p] * V[3 * p] + V[3 * p + 1] * V[3 * p + 1] + V[3 * p + 2] * V[3 * p + 2]))
	_push_out()


func step(dt: float) -> void:
	if wdirty or wxp.size() == 0:
		rebuild_weights()
	_mark()
	if dmode == 1:
		_density_project()
		_mark()
	_p2g()
	_project(dt)
	_g2p()
	_advect(dt)


func advance(T_in: float) -> int:
	var T := T_in
	if release_delay > 0.0:   # a held column is at rest and nothing acts on it: the hold costs no steps
		var hold := minf(release_delay, T)
		release_delay -= hold
		T -= hold
	var t := 0.0
	var n := 0
	while t < T - 1e-12:
		var dt := dtmax
		if vmax > 1e-9:
			dt = minf(dt, cfl * h / vmax)
		dt = maxf(dt, dtmax * 0.05)
		if t + dt > T:
			dt = T - t
		step(dt)
		t += dt
		n += 1
	return n


func particle_data() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(6 * particle_count())
	for p in particle_count():
		for a in 3:
			out[6 * p + a] = P[3 * p + a]
			out[6 * p + 3 + a] = V[3 * p + a]
	return out


func positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in particle_count():
		out.append(Vector3(P[3 * p], P[3 * p + 1], P[3 * p + 2]))
	return out


func get_pressure(i: int, j: int, k: int) -> float:
	if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz:
		return 0.0
	return pr[_cid(i, j, k)] * 1000.0


func solid_count() -> int:
	var n := 0
	for s in solid:
		n += 1 if s != 0 else 0
	return n


func particles_in_solid() -> int:
	var n := 0
	for p in particle_count():
		var i := int(floor((P[3 * p] - o.x) / h))
		var j := int(floor((P[3 * p + 1] - o.y) / h))
		var k := int(floor((P[3 * p + 2] - o.z) / h))
		if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz or solid[_cid(i, j, k)] != 0:
			n += 1
	return n


func volume_ratio() -> float:
	var N := particle_count()
	if N == 0:
		return 1.0
	var c2 := PackedInt32Array()
	c2.resize(nx * ny * nz)
	for p in N:
		var i := int(floor((P[3 * p] - o.x) / h))
		var j := int(floor((P[3 * p + 1] - o.y) / h))
		var k := int(floor((P[3 * p + 2] - o.z) / h))
		if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz:
			continue
		c2[_cid(i, j, k)] += 1
	var s := 0.0
	for c in c2:
		s += minf(c, ppc)
	return s / N


func stats() -> Dictionary:
	return {"n": particle_count(), "fluid_cells": fl.size(), "vmax": vmax, "pcg_iters": last_iters}
