## spline_chain.gd - SPLINE IK FOR ANY BONE CHAIN (GAP_AUDIT_1106 animation item 5; Blender's Spline IK / Maya's Spline IK handle, said in
## our words: nothing here is their code). A tail, a tentacle, a cape edge: the user's extra bones (bone_editor.gd) in a row follow a
## curve through 3-5 HANDLES the user moves. SpineIK (spine_ik.gd) does the same for the human back with 3 fixed controls; this is the
## general version, for chains of any length, and it adds the stretch.
##
## THE CURVE (kind): "catmull" = a Catmull-Rom spline THROUGH the handles (cubic Hermite pieces, tangent (p[i+1]-p[i-1])/2, one-sided at
## the ends), "bezier" = ONE Bezier of degree n-1 that the handles pull but do not touch (de Casteljau). Parameter u runs 0..n-1. Past
## the last handle the curve goes on in a straight line along its end tangent, so a chain longer than the curve still lies on a line.
## The first handle is the chain's root: it is always put on the root bone's head.
## THE MODES (mode): "keep" = every bone keeps its length; the joints are marched down the curve, each the first point on it that is one
## bone length (straight line) from the last. "stretch" = the chain is stretched (or squeezed) to fit: joints at the same FRACTION of the
## curve's arc length as of the chain's rest length, the last joint on the last handle; each bone's scale is chord / rest length.
## VOLUME (opt-in): a stretched bone's two cross-axes scale by 1/sqrt(s), so s * c * c = 1 (a squash-and-stretch that keeps the volume).
## TWIST: about each bone's own axis, tw0 at the root growing linearly with the chain's rest length to tw1 at the tip (the last bone carries
## all of tw1). The bend itself makes no twist: the frame of the rest bone is carried down the chain by smallest swings.
## Every bone's frame: +Y along the bone (BoneEdit's convention), x = the carried frame turned by the twist, z = x cross y.
##
## THE SOLVE IS IN C++ (native/src/kine_spline_native.cpp, KineSplineNative.solve) when the DLL is there, and in GDScript (_core_gd) when
## not; both do the SAME double arithmetic in the same order (tests/splineik_test.gd bar 7: equal within 1e-9). KINE_NO_NATIVE=1 or
## SplineChain.force_gd forces the GDScript.
## IN THE SCENE (Scene.spline_chains; the file's "spline_chains": {"v": 1, "chains": [...]}, written only when there is a chain):
##   {"name", "bones": [bone names, root first], "ctrl": [[x,y,z] ...] (REST-space points: they ride with the root bone's parent),
##    "kind", "mode", "tw0", "tw1", "volume"}
class_name SplineChain
extends RefCounted

const VERSION := 1
const KINDS := ["catmull", "bezier"]
const MODES := ["keep", "stretch"]
const MIN_HANDLES := 3
const MAX_HANDLES := 5
const TABLE := 200      # arc-length table cells per curve piece
const SCAN := 0.01      # the keep-length march's step along u

static var force_gd := false
static var _door: Variant = null
static var _tried := false


# ------------------------------------------------------------------------------------------------ the numbers (doubles)

static func _pt(c: PackedFloat64Array, k: int, bez: bool, u: float, o: PackedFloat64Array) -> void:
	var top := float(k - 1)
	if u >= top:
		var s := u - top
		for a in 3:
			o[a] = c[(k - 1) * 3 + a] + s * (c[(k - 1) * 3 + a] - c[(k - 2) * 3 + a])
		return
	if u < 0.0:
		u = 0.0
	if bez:
		var t := u / top
		var w := PackedFloat64Array()
		w.resize(k * 3)
		for i in k * 3:
			w[i] = c[i]
		for lvl in range(k - 1, 0, -1):
			for i in lvl * 3:
				w[i] = w[i] + (w[i + 3] - w[i]) * t
		for a in 3:
			o[a] = w[a]
		return
	var sp := int(floor(u))
	if sp > k - 2:
		sp = k - 2
	var t2 := u - float(sp)
	var t3 := t2 * t2 * t2
	var tq := t2 * t2
	var h00 := 2.0 * t3 - 3.0 * tq + 1.0
	var h10 := t3 - 2.0 * tq + t2
	var h01 := -2.0 * t3 + 3.0 * tq
	var h11 := t3 - tq
	for a in 3:
		var p0 := c[sp * 3 + a]
		var p1 := c[(sp + 1) * 3 + a]
		var m0: float
		if sp == 0:
			m0 = c[3 + a] - c[a]
		else:
			m0 = (c[(sp + 1) * 3 + a] - c[(sp - 1) * 3 + a]) * 0.5
		var m1: float
		if sp == k - 2:
			m1 = c[(k - 1) * 3 + a] - c[(k - 2) * 3 + a]
		else:
			m1 = (c[(sp + 2) * 3 + a] - c[sp * 3 + a]) * 0.5
		o[a] = p0 * h00 + m0 * h10 + p1 * h01 + m1 * h11


static func _dist(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var dx := a[0] - b[0]
	var dy := a[1] - b[1]
	var dz := a[2] - b[2]
	return sqrt(dx * dx + dy * dy + dz * dz)


## the rotation of v about the unit axis (ax, ay, az) by the angle with the given cos and sin (Rodrigues)
static func _rot(v: PackedFloat64Array, ax: float, ay: float, az: float, cs: float, sn: float, o: PackedFloat64Array) -> void:
	var d := ax * v[0] + ay * v[1] + az * v[2]
	var cx := ay * v[2] - az * v[1]
	var cy := az * v[0] - ax * v[2]
	var cz := ax * v[1] - ay * v[0]
	o[0] = v[0] * cs + cx * sn + ax * d * (1.0 - cs)
	o[1] = v[1] * cs + cy * sn + ay * d * (1.0 - cs)
	o[2] = v[2] * cs + cz * sn + az * d * (1.0 - cs)


## THE SOLVE. root (3), lens (n bone lengths), ctrl (k handles x 3), kind 0 catmull / 1 bezier, mode 0 keep / 1 stretch, twists in deg,
## rest_y / rest_x (3 each): the first bone's rest axes in the same space as the handles. Returns flat arrays.
static func _core_gd(root: PackedFloat64Array, lens: PackedFloat64Array, ctrl: PackedFloat64Array, kind: int, mode: int, tw0: float, tw1: float,
		rest_y: PackedFloat64Array, rest_x: PackedFloat64Array, volume: bool) -> Dictionary:
	var n := lens.size()
	var k := ctrl.size() / 3
	var c := ctrl.duplicate()
	for a in 3:
		c[a] = root[a]
	var bez := kind == 1
	var top := float(k - 1)
	var joints := PackedFloat64Array()
	joints.resize((n + 1) * 3)
	var tmp := PackedFloat64Array([0.0, 0.0, 0.0])
	var tot := 0.0
	var cum := PackedFloat64Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in n:
		tot += lens[i]
		cum[i + 1] = tot
	# the arc-length table (also gives the curve's length)
	var cells := TABLE * (k - 1)
	var tab := PackedFloat64Array()
	tab.resize(cells + 1)
	tab[0] = 0.0
	var prev := PackedFloat64Array([c[0], c[1], c[2]])
	for i in range(1, cells + 1):
		_pt(c, k, bez, top * float(i) / float(cells), tmp)
		tab[i] = tab[i - 1] + _dist(prev, tmp)
		prev[0] = tmp[0]
		prev[1] = tmp[1]
		prev[2] = tmp[2]
	var curve_len := tab[cells]
	joints[0] = c[0]
	joints[1] = c[1]
	joints[2] = c[2]
	if mode == 1:
		for i in range(1, n + 1):
			var want := curve_len * (cum[i] / tot if tot > 0.0 else 0.0)
			var u := top
			if i < n:
				# binary search the table cell, then a straight interpolation inside it
				var lo := 0
				var hi := cells
				while hi - lo > 1:
					var mid := (lo + hi) / 2
					if tab[mid] <= want:
						lo = mid
					else:
						hi = mid
				var span := tab[lo + 1] - tab[lo]
				var f := (want - tab[lo]) / span if span > 0.0 else 0.0
				u = top * (float(lo) + f) / float(cells)
			_pt(c, k, bez, u, tmp)
			joints[i * 3] = tmp[0]
			joints[i * 3 + 1] = tmp[1]
			joints[i * 3 + 2] = tmp[2]
	else:
		var u_cur := 0.0
		var J := PackedFloat64Array([c[0], c[1], c[2]])
		for i in n:
			var L := lens[i]
			var found := false
			if u_cur < top:
				var u_lo := u_cur
				var u_hi := u_cur
				while u_hi < top:
					u_lo = u_hi
					u_hi = minf(u_hi + SCAN, top)
					_pt(c, k, bez, u_hi, tmp)
					if _dist(J, tmp) >= L:
						found = true
						break
				if found:
					for _it in 60:
						var um := (u_lo + u_hi) * 0.5
						_pt(c, k, bez, um, tmp)
						if _dist(J, tmp) >= L:
							u_hi = um
						else:
							u_lo = um
					u_cur = (u_lo + u_hi) * 0.5
					_pt(c, k, bez, u_cur, tmp)
			if not found:
				# on the straight continuation E + s T: |E - J + s T| = L
				var ex := c[(k - 1) * 3]
				var ey := c[(k - 1) * 3 + 1]
				var ez := c[(k - 1) * 3 + 2]
				var tx := ex - c[(k - 2) * 3]
				var ty := ey - c[(k - 2) * 3 + 1]
				var tz := ez - c[(k - 2) * 3 + 2]
				var dx := ex - J[0]
				var dy := ey - J[1]
				var dz := ez - J[2]
				var a2 := tx * tx + ty * ty + tz * tz
				var s := 0.0
				if a2 > 1e-18:
					var b2 := 2.0 * (tx * dx + ty * dy + tz * dz)
					var c2 := dx * dx + dy * dy + dz * dz - L * L
					var disc := maxf(b2 * b2 - 4.0 * a2 * c2, 0.0)
					s = maxf((-b2 + sqrt(disc)) / (2.0 * a2), 0.0)
					if u_cur > top:
						s = maxf(s, u_cur - top)
					u_cur = top + s
					tmp[0] = ex + s * tx
					tmp[1] = ey + s * ty
					tmp[2] = ez + s * tz
				else:
					tmp[0] = J[0]
					tmp[1] = J[1] + L
					tmp[2] = J[2]
			joints[(i + 1) * 3] = tmp[0]
			joints[(i + 1) * 3 + 1] = tmp[1]
			joints[(i + 1) * 3 + 2] = tmp[2]
			J[0] = tmp[0]
			J[1] = tmp[1]
			J[2] = tmp[2]
	# the frames
	var axes := PackedFloat64Array()
	axes.resize(n * 9)
	var scl := PackedFloat64Array()
	scl.resize(n)
	var crs := PackedFloat64Array()
	crs.resize(n)
	var twd := PackedFloat64Array()
	twd.resize(n)
	var ry_l := sqrt(rest_y[0] * rest_y[0] + rest_y[1] * rest_y[1] + rest_y[2] * rest_y[2])
	var yp := PackedFloat64Array([rest_y[0] / ry_l, rest_y[1] / ry_l, rest_y[2] / ry_l])
	var ref := PackedFloat64Array([rest_x[0], rest_x[1], rest_x[2]])
	var dd := ref[0] * yp[0] + ref[1] * yp[1] + ref[2] * yp[2]
	ref[0] -= yp[0] * dd
	ref[1] -= yp[1] * dd
	ref[2] -= yp[2] * dd
	var rl := sqrt(ref[0] * ref[0] + ref[1] * ref[1] + ref[2] * ref[2])
	ref[0] /= rl
	ref[1] /= rl
	ref[2] /= rl
	var y := PackedFloat64Array([yp[0], yp[1], yp[2]])
	var chain_len := 0.0
	var o3 := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in n:
		var dx := joints[(i + 1) * 3] - joints[i * 3]
		var dy := joints[(i + 1) * 3 + 1] - joints[i * 3 + 1]
		var dz := joints[(i + 1) * 3 + 2] - joints[i * 3 + 2]
		var bl := sqrt(dx * dx + dy * dy + dz * dz)
		chain_len += bl
		if bl > 1e-12:
			y[0] = dx / bl
			y[1] = dy / bl
			y[2] = dz / bl
		# smallest swing yp -> y carries the reference
		var cs := yp[0] * y[0] + yp[1] * y[1] + yp[2] * y[2]
		var kx := yp[1] * y[2] - yp[2] * y[1]
		var ky := yp[2] * y[0] - yp[0] * y[2]
		var kz := yp[0] * y[1] - yp[1] * y[0]
		var kl := sqrt(kx * kx + ky * ky + kz * kz)
		if kl > 1e-12:
			_rot(ref, kx / kl, ky / kl, kz / kl, cs, kl, o3)
			ref[0] = o3[0]
			ref[1] = o3[1]
			ref[2] = o3[2]
		elif cs < 0.0:
			# anti-parallel: half a turn about any axis square to y
			var px := 0.0
			var py := 0.0
			var pz := 0.0
			if absf(y[0]) < 0.9:
				px = 1.0
			else:
				py = 1.0
			var d2 := px * y[0] + py * y[1] + pz * y[2]
			px -= y[0] * d2
			py -= y[1] * d2
			pz -= y[2] * d2
			var pl := sqrt(px * px + py * py + pz * pz)
			_rot(ref, px / pl, py / pl, pz / pl, -1.0, 0.0, o3)
			ref[0] = o3[0]
			ref[1] = o3[1]
			ref[2] = o3[2]
		var d3 := ref[0] * y[0] + ref[1] * y[1] + ref[2] * y[2]
		ref[0] -= y[0] * d3
		ref[1] -= y[1] * d3
		ref[2] -= y[2] * d3
		var rl2 := sqrt(ref[0] * ref[0] + ref[1] * ref[1] + ref[2] * ref[2])
		ref[0] /= rl2
		ref[1] /= rl2
		ref[2] /= rl2
		yp[0] = y[0]
		yp[1] = y[1]
		yp[2] = y[2]
		var f_far := cum[i + 1] / tot if tot > 0.0 else 0.0
		var tw := tw0 + (tw1 - tw0) * f_far
		twd[i] = tw
		var trad := deg_to_rad(tw)
		_rot(ref, y[0], y[1], y[2], cos(trad), sin(trad), o3)
		var xx := o3[0]
		var xy := o3[1]
		var xz := o3[2]
		axes[i * 9] = xx
		axes[i * 9 + 1] = xy
		axes[i * 9 + 2] = xz
		axes[i * 9 + 3] = y[0]
		axes[i * 9 + 4] = y[1]
		axes[i * 9 + 5] = y[2]
		axes[i * 9 + 6] = xy * y[2] - xz * y[1]
		axes[i * 9 + 7] = xz * y[0] - xx * y[2]
		axes[i * 9 + 8] = xx * y[1] - xy * y[0]
		var sc := 1.0
		if mode == 1 and lens[i] > 0.0:
			sc = bl / lens[i]
		scl[i] = sc
		crs[i] = 1.0 / sqrt(sc) if (volume and sc > 0.0) else 1.0
	return {"joints": joints, "axes": axes, "scale": scl, "cross": crs, "twist": twd, "curve_len": curve_len, "chain_len": chain_len}


# ------------------------------------------------------------------------------------------------ the door to C++

static func _native() -> bool:
	if force_gd or OS.get_environment("KINE_NO_NATIVE") == "1":
		return false
	if not _tried:
		_tried = true
		if NativeExt.ensure("kine_native", "KineSplineNative"):
			_door = load("res://scripts/spline_native.gd")
	return _door != null


static func _flat(a: Array) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	for v in a:
		o.append(v.x)
		o.append(v.y)
		o.append(v.z)
	return o


static func _v3(v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([v.x, v.y, v.z])


## o: {"kind": "catmull"|"bezier", "mode": "keep"|"stretch", "tw0", "tw1" (deg), "volume": bool, "rest_y", "rest_x": Vector3}
## Returns {"joints": [Vector3 x n+1], "axes": [Basis x n] (columns x, y, z), "scale": [..], "cross": [..], "twist": [deg ..],
## "curve_len", "chain_len", "native": bool}
static func solve(root: Vector3, lens: Array, ctrl: Array, o := {}) -> Dictionary:
	return _solve(root, lens, ctrl, o, _native())


static func solve_gd(root: Vector3, lens: Array, ctrl: Array, o := {}) -> Dictionary:
	return _solve(root, lens, ctrl, o, false)


static func _solve(root: Vector3, lens: Array, ctrl: Array, o: Dictionary, native: bool) -> Dictionary:
	var kind := 1 if String(o.get("kind", "catmull")) == "bezier" else 0
	var mode := 1 if String(o.get("mode", "keep")) == "stretch" else 0
	var args := [_v3(root), PackedFloat64Array(lens), _flat(ctrl), kind, mode, float(o.get("tw0", 0.0)), float(o.get("tw1", 0.0)),
		_v3(o.get("rest_y", Vector3.UP)), _v3(o.get("rest_x", Vector3.RIGHT)), bool(o.get("volume", false))]
	var r: Dictionary
	if native:
		r = _door.solve(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9])
	else:
		r = _core_gd(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9])
	var js: PackedFloat64Array = r["joints"]
	var ax: PackedFloat64Array = r["axes"]
	var joints := []
	for i in js.size() / 3:
		joints.append(Vector3(js[i * 3], js[i * 3 + 1], js[i * 3 + 2]))
	var axes := []
	for i in ax.size() / 9:
		axes.append(Basis(Vector3(ax[i * 9], ax[i * 9 + 1], ax[i * 9 + 2]), Vector3(ax[i * 9 + 3], ax[i * 9 + 4], ax[i * 9 + 5]), Vector3(ax[i * 9 + 6], ax[i * 9 + 7], ax[i * 9 + 8])))
	return {"joints": joints, "axes": axes, "scale": Array(r["scale"]), "cross": Array(r["cross"]), "twist": Array(r["twist"]),
		"curve_len": r["curve_len"], "chain_len": r["chain_len"], "native": native}


static func curve_point(ctrl: Array, kind: String, u: float) -> Vector3:
	var c := _flat(ctrl)
	var o := PackedFloat64Array([0.0, 0.0, 0.0])
	_pt(c, ctrl.size(), kind == "bezier", u, o)
	return Vector3(o[0], o[1], o[2])


# ------------------------------------------------------------------------------------------------ the chain in the scene

## the bone names of the chain that starts at `first`: down the connected child (else the only child, else the first child)
static func chain_from(bones: Array, first: String) -> Array:
	var out := []
	var n := first
	while n != "" and not n in out:
		out.append(n)
		var ch := BoneEdit.children(bones, n)
		if ch.is_empty():
			break
		var pick: String = ch[0]
		for c in ch:
			if bool(BoneEdit.get_bone(bones, c).get("connect", false)):
				pick = c
				break
		n = pick
	return out


## every bone of the chain exists in the bone list
static func valid(bones: Array, ch: Dictionary) -> bool:
	for n in ch["bones"]:
		if BoneEdit.find(bones, String(n)) < 0:
			return false
	return not (ch["bones"] as Array).is_empty()


static func index_of(chains: Array, bone: String) -> int:
	for i in chains.size():
		if bone in chains[i]["bones"]:
			return i
	return -1


static func by_name(chains: Array, nm: String) -> int:
	for i in chains.size():
		if chains[i]["name"] == nm:
			return i
	return -1


static func free_name(chains: Array) -> String:
	var i := 1
	while by_name(chains, "spline_%d" % i) >= 0:
		i += 1
	return "spline_%d" % i


## a new chain on `names` (root first): `k` handles spread along the chain's rest polyline by length (rest space)
static func make(B: Body, bones: Array, names: Array, nm: String, k := 4) -> Dictionary:
	k = clampi(k, MIN_HANDLES, MAX_HANDLES)
	var pts: Array = [BoneEdit.rest_ht(B, bones, names[0])[0]]
	var lens: Array = []
	for n in names:
		var ht := BoneEdit.rest_ht(B, bones, n)
		pts.append(ht[1])
		lens.append((ht[1] as Vector3).distance_to(ht[0]))
	var tot := 0.0
	for l in lens:
		tot += l
	var ctrl := []
	for h in k:
		var want: float = tot * float(h) / float(k - 1)
		var acc := 0.0
		var p: Vector3 = pts[pts.size() - 1]
		for i in lens.size():
			if want <= acc + lens[i] + 1e-12:
				var f: float = (want - acc) / lens[i] if lens[i] > 0.0 else 0.0
				p = (pts[i] as Vector3).lerp(pts[i + 1], f)
				break
			acc += lens[i]
		ctrl.append(p)
	return {"name": nm, "bones": names.duplicate(), "ctrl": ctrl, "kind": "catmull", "mode": "keep", "tw0": 0.0, "tw1": 0.0, "volume": false}


## rest space -> the posed world, for a chain: the root bone's parent carries the handles
static func carry(B: Body, bones: Array, ch: Dictionary) -> Transform3D:
	var par := String(BoneEdit.get_bone(bones, ch["bones"][0]).get("parent", ""))
	if par == "":
		return Transform3D()
	return BoneEdit.posed_xf(B, bones, par) * BoneEdit.rest_xf(B, bones, par).affine_inverse()


static func rest_lens(B: Body, bones: Array, ch: Dictionary) -> Array:
	return (ch["bones"] as Array).map(func(n): return BoneEdit.length(B, bones, n))


## the solve for a scene chain, in the posed world
static func solve_chain(B: Body, bones: Array, ch: Dictionary) -> Dictionary:
	var K := carry(B, bones, ch)
	var first: String = ch["bones"][0]
	var rx := BoneEdit.rest_xf(B, bones, first)
	var ctrl := (ch["ctrl"] as Array).map(func(p): return K * (p as Vector3))
	var root: Vector3 = K * (BoneEdit.rest_ht(B, bones, first)[0] as Vector3)
	return solve(root, rest_lens(B, bones, ch), ctrl, {"kind": ch["kind"], "mode": ch["mode"], "tw0": ch["tw0"], "tw1": ch["tw1"], "volume": ch["volume"],
		"rest_y": K.basis * rx.basis.y, "rest_x": K.basis * rx.basis.x})


## {bone name: its posed Transform3D, the cross scales and the stretch in its basis} for the chain
static func pose(B: Body, bones: Array, ch: Dictionary) -> Dictionary:
	var out := {}
	if not valid(bones, ch):
		return out
	var r := solve_chain(B, bones, ch)
	for i in (ch["bones"] as Array).size():
		var b: Basis = r["axes"][i]
		var c: float = r["cross"][i]
		var s: float = r["scale"][i]
		out[ch["bones"][i]] = Transform3D(Basis(b.x * c, b.y * s, b.z * c), r["joints"][i])
	return out


static func to_file(chains: Array) -> Dictionary:
	return {"v": VERSION, "chains": chains.map(func(c):
		var d := {"name": String(c["name"]), "bones": (c["bones"] as Array).map(func(n): return String(n)),
			"ctrl": (c["ctrl"] as Array).map(func(p): return BoneEdit._a(p)), "kind": String(c["kind"]), "mode": String(c["mode"]),
			"tw0": snappedf(float(c["tw0"]), 0.0001), "tw1": snappedf(float(c["tw1"]), 0.0001)}
		if bool(c["volume"]):
			d["volume"] = true
		return d)}


static func from_file(d: Variant) -> Array:
	var out := []
	if not (d is Dictionary and d.has("chains") and d["chains"] is Array):
		return out
	for c in d["chains"]:
		if not (c is Dictionary and c.has("name") and c.has("bones") and c.has("ctrl") and c["bones"] is Array and c["ctrl"] is Array):
			continue
		var cs: Array = c["ctrl"]
		if cs.size() < MIN_HANDLES or cs.size() > MAX_HANDLES or (c["bones"] as Array).is_empty():
			continue
		var kind := String(c.get("kind", "catmull"))
		var mode := String(c.get("mode", "keep"))
		out.append({"name": String(c["name"]), "bones": (c["bones"] as Array).map(func(n): return String(n)),
			"ctrl": cs.map(func(p): return BoneEdit._v(p)), "kind": kind if kind in KINDS else "catmull", "mode": mode if mode in MODES else "keep",
			"tw0": float(c.get("tw0", 0.0)), "tw1": float(c.get("tw1", 0.0)), "volume": bool(c.get("volume", false))})
	return out
