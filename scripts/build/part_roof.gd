class_name PartRoof
extends RefCounted
## ITEM 226 ROOF FEATURE (Friday plan; "close every place Blender beats Kine": Blender makes a curved thin roof with raised corners from a subdivided
## plane + proportional edit + solidify; Kine could only intersect two profile solids, whose upturn came out as a horn mid-side).
## A Part feature {"t": "roof", "id", "name", ...} that builds the roof as a THIN CLOSED SHELL: the top surface is a height field over the plan, the
## shell hangs under it by the thickness (measured square to the surface, like Blender's Solidify), and the kernel sews the dense mesh into ONE valid
## solid (KCad.solid_from_mesh, exact volume of the mesh). The record holds the NUMBERS only (not the mesh), so undo, save and replay are small and a
## slider move rebuilds it; the sewn master is cached per parameter set.
##
## THE FIELDS (mm and degrees; every one has a default, see norm()):
##   "type":      "hip" | "gable" | "xieshan" (hip-and-gable: a hip skirt below, a gable above whose triangle is set in) | "pyramid" | "shed" | "flat"
##   "w", "d":    the plan of the building under the roof (X wide, Z deep). "poly": [[x, z], ...] a convex plan instead (pyramid / flat over a polygon)
##   "overhang":  how far the eave sticks out past the plan on every side
##   "height":    the ridge top above the eave line (wins over "pitch", degrees)
##   "sag":       the concave profile: how far the slope dips below a straight line at mid-slope (the Chinese curve; the ridge and the eave line stay put)
##   "lift":      the corner lift: how far each eave corner rises; "lift_len": over how long a stretch of eave (and up the hip) it rises, smoothly
##   "thick":     the shell thickness, square to the slope
##   "gable_in":  xieshan only: how far the gable triangle is set in from the eave end;  "hip_frac": the hip skirt's height as a share of the ridge height
##   "hole":      [w, d] an open top (a skirt / ring for a double eave): the plan size of the opening in the middle of the roof
##   "axis":      "auto" (the ridge runs along the long side) | "x" | "z"
##   "at":        [x, y, z] where the middle of the eave line stands
##   "ridge", "hips", "eave": true = also make that trim as its own thin body ("trim_w", "trim_h" its size)
## Output: bodies[0] is the shell; each trim asked for is one more body.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const TYPES := ["hip", "gable", "xieshan", "pyramid", "shed", "flat"]
const MAX_TRIS := 60000
static var _masters := {}    # hash of the parameters + body index -> kernel id of the sewn solid (a replay copies it)
static var _counts := {}     # hash of the parameters -> how many bodies the roof makes
static var builds := 0       # how many meshes were built (tests read it: a cached replay builds none)


## the fields with defaults and limits: a clean dictionary every other function reads
static func norm(f: Dictionary) -> Dictionary:
	var P := {}
	var tp := String(f.get("type", "hip"))
	P["type"] = tp if TYPES.has(tp) else "hip"
	var poly: Array = []
	for q in f.get("poly", []):
		poly.append(Vector2(float(q[0]), float(q[1])))
	if poly.size() >= 3 and (P["type"] == "pyramid" or P["type"] == "flat" or P["type"] == "hip"):
		P["poly"] = poly
		if P["type"] == "hip":
			P["type"] = "pyramid"
	P["w"] = clampf(float(f.get("w", 8000.0)), 100.0, 200000.0)
	P["d"] = clampf(float(f.get("d", 6000.0)), 100.0, 200000.0)
	P["overhang"] = clampf(float(f.get("overhang", 600.0)), 0.0, 20000.0)
	P["pitch"] = clampf(float(f.get("pitch", 30.0)), 1.0, 70.0)
	P["height"] = maxf(float(f.get("height", 0.0)), 0.0)
	P["sag"] = maxf(float(f.get("sag", 0.0)), 0.0)
	P["lift"] = float(f.get("lift", 0.0))
	P["lift_len"] = maxf(float(f.get("lift_len", 0.0)), 0.0)
	P["lift_pow"] = clampf(float(f.get("lift_pow", 2.0)), 1.0, 6.0)   # item 236: 2 = the old smooth bump; higher = the lift gathers at the very tip (a steeper curl, like a temple's flying eave)
	P["thick"] = clampf(float(f.get("thick", 60.0)), 1.0, 5000.0)
	P["gable_in"] = maxf(float(f.get("gable_in", 0.0)), 0.0)
	P["hip_frac"] = clampf(float(f.get("hip_frac", 0.4)), 0.05, 0.9)
	var hole: Array = f.get("hole", [])
	P["hole"] = Vector2(maxf(float(hole[0]), 0.0), maxf(float(hole[1]), 0.0)) if hole.size() >= 2 else Vector2.ZERO
	var ax := String(f.get("axis", "auto"))
	P["axis"] = ax if ax in ["auto", "x", "z"] else "auto"
	var at: Array = f.get("at", [0, 0, 0])
	P["at"] = Vector3(float(at[0]), float(at[1]), float(at[2])) if at.size() >= 3 else Vector3.ZERO
	P["ridge"] = bool(f.get("ridge", false))
	P["hips"] = bool(f.get("hips", false))
	P["eave"] = bool(f.get("eave", false))
	P["trim_w"] = clampf(float(f.get("trim_w", 0.0)), 0.0, 5000.0)
	P["trim_h"] = clampf(float(f.get("trim_h", 0.0)), 0.0, 5000.0)
	P["detail"] = clampi(int(f.get("detail", 20)), 6, 60)
	return P


## the geometry constants (canonical frame: the ridge runs along X, the eave rectangle is +-a by +-b, y = 0 at the eave line, mm). swap = the plan was turned
static func geometry(P: Dictionary) -> Dictionary:
	var G := {"type": P["type"], "t": float(P["thick"]), "sag": float(P["sag"]), "lift": float(P["lift"]), "lp": float(P.get("lift_pow", 2.0))}
	var w := float(P["w"])
	var d := float(P["d"])
	var o := float(P["overhang"])
	var swap := false
	var ax := String(P["axis"])
	if ax == "x":
		swap = false
	elif ax == "z":
		swap = true
	else:
		swap = w < d
	if G["type"] in ["hip", "xieshan"] and ax != "auto":
		swap = w < d   # a hip's ridge is always along the long side
	var cw := d if swap else w   # along the ridge
	var cd := w if swap else d   # across it
	G["swap"] = swap
	G["a"] = cw * 0.5 + o
	G["b"] = cd * 0.5 + o
	var a: float = G["a"]
	var b: float = G["b"]
	var run := b   # half the run the slope climbs over
	if G["type"] == "shed":
		run = 2.0 * b
	elif G["type"] in ["pyramid", "hip"]:
		run = minf(a, b)
	var H := 0.0
	if G["type"] != "flat":
		H = float(P["height"]) if float(P["height"]) > 0.0 else tan(deg_to_rad(float(P["pitch"]))) * run
	G["H"] = H
	G["k"] = H / maxf(run, 1e-6)
	G["sag"] = minf(G["sag"], 0.24 * H)
	var ll := float(P["lift_len"])
	if ll <= 0.0:
		ll = 0.3 * minf(a, b)
	G["ll"] = minf(ll, 0.98 * minf(a, b))
	if G["type"] == "xieshan":
		var u1 := float(P["gable_in"])
		if u1 <= 0.0:
			u1 = 0.3 * b
		u1 = clampf(u1, 0.02 * a, 0.6 * a - G["t"] * 2.0)
		G["u1"] = u1
		G["hh"] = float(P["hip_frac"]) * H
		G["ke"] = G["hh"] / u1
		G["tw"] = clampf(G["t"], 1.0, 0.2 * a)
	var hole: Vector2 = P["hole"]
	G["hx"] = (hole.y if swap else hole.x) * 0.5
	G["hz"] = (hole.x if swap else hole.y) * 0.5
	return G


# ----------------------------------------------------------------------------------------------- the surface

## the straight faces at (x, z): [height, d/dx, d/dz]
static func _base(G: Dictionary, x: float, z: float, inner: bool) -> Array:
	var a: float = G["a"]
	var b: float = G["b"]
	var sx := 1.0 if x >= 0.0 else -1.0
	var sz := 1.0 if z >= 0.0 else -1.0
	var u := a - absf(x)
	var v := b - absf(z)
	var H: float = G["H"]
	match String(G["type"]):
		"flat":
			return [0.0, 0.0, 0.0]
		"shed":
			var ks: float = H / (2.0 * b)
			return [ks * (z + b), 0.0, ks]
		"gable":
			var kg: float = H / b
			return [kg * v, 0.0, -kg * sz]
		"pyramid":
			var rx := absf(x) / a
			var rz := absf(z) / b
			if rx >= rz:
				return [H * (1.0 - rx), -H * sx / a, 0.0]
			return [H * (1.0 - rz), 0.0, -H * sz / b]
		"xieshan":
			var kx: float = H / b
			var kv := kx * v
			if inner:
				return [kv, 0.0, -kx * sz]
			var ha: float = float(G["ke"]) * u
			if ha < kv:
				return [ha, -float(G["ke"]) * sx, 0.0]
			return [kv, 0.0, -kx * sz]
		_:   # hip
			var kh: float = G["k"]
			if u < v:
				return [kh * u, -kh * sx, 0.0]
			return [kh * v, 0.0, -kh * sz]


## the corner lift at (x, z): L at each eave corner, falling smoothly to 0 over lift_len along the eave and up the hip
static func _lift(G: Dictionary, x: float, z: float) -> float:
	var ll: float = G["ll"]
	var tu := (float(G["a"]) - absf(x)) / ll
	var tv := (float(G["b"]) - absf(z)) / ll
	if tu >= 1.0 or tv >= 1.0:
		return 0.0
	var fu := 1.0 - maxf(tu, 0.0)
	var fv := 1.0 - maxf(tv, 0.0)
	var lp: float = float(G.get("lp", 2.0))
	if lp != 2.0:
		return float(G["lift"]) * pow(fu, lp) * pow(fv, lp)
	return float(G["lift"]) * fu * fu * fv * fv


## the top surface at (x, z): [height, d/dx, d/dz]. flag: xieshan only, at the set-in line: 1 = the gable side, -1 = the hip skirt side, 0 = by position
static func top(G: Dictionary, x: float, z: float, flag := 0) -> Array:
	var inner := false
	if String(G["type"]) == "xieshan":
		inner = (float(G["a"]) - absf(x) > float(G["u1"]) + 1e-7) if flag == 0 else flag > 0
	var p := _base(G, x, z, inner)
	var h: float = p[0]
	var gx: float = p[1]
	var gz: float = p[2]
	var T := h
	var H: float = G["H"]
	var sg: float = G["sag"]
	if H > 0.0 and sg > 0.0:
		var s := clampf(h / H, 0.0, 1.0)
		T -= sg * 4.0 * s * (1.0 - s)
		var ds: float = sg * 4.0 * (1.0 - 2.0 * s) / H
		gx *= 1.0 - ds
		gz *= 1.0 - ds
	if float(G["lift"]) != 0.0:
		T += _lift(G, x, z)
		var e := 0.5
		gx += (_lift(G, x + e, z) - _lift(G, x - e, z)) / (2.0 * e)
		gz += (_lift(G, x, z + e) - _lift(G, x, z - e)) / (2.0 * e)
	return [T, gx, gz]


## the underside at (x, z): the top minus the thickness square to the slope. kind 3 / 4 = the two copies of the wall's inner line
static func bottom(G: Dictionary, x: float, z: float, kind := 0) -> float:
	var strip := false
	if String(G["type"]) == "xieshan":
		var u: float = float(G["a"]) - absf(x)
		var lo: float = float(G["u1"]) - 1e-7
		var hi: float = float(G["u1"]) + float(G["tw"])
		if u >= lo and u < hi - 1e-7:
			strip = true
		elif absf(u - hi) <= 1e-7:
			strip = (kind == 3) == (x < 0.0)
	var r: Array
	if strip:
		r = top(G, (float(G["a"]) - float(G["u1"])) * (1.0 if x >= 0.0 else -1.0), z, -1)
	else:
		r = top(G, x, z, 0)
	return float(r[0]) - float(G["t"]) * sqrt(1.0 + float(r[1]) * float(r[1]) + float(r[2]) * float(r[2]))


# ----------------------------------------------------------------------------------------------- the mesh

## the grid lines of one axis: [value, kind] sorted. e = the half extent, c = the cell, keep = values that must be a line (positive ones: mirrored)
static func _axis(e: float, c: float, keep: Array, steps: Array) -> Array:
	var prot: Array = [0.0, e, -e]
	for k in keep:
		var kv := float(k)
		if kv > 1e-6 and kv < e - 1e-6:
			prot.append(kv)
			prot.append(-kv)
	var vals: Array = prot.duplicate()
	var j := 1
	while e - j * c > 0.0:
		var v := e - j * c
		var near := false
		for p in prot:
			if absf(absf(v) - absf(float(p))) < 0.35 * c:
				near = true
				break
		if not near:
			vals.append(v)
			vals.append(-v)
		j += 1
	vals.sort()
	var out: Array = []
	for v in vals:
		if not out.is_empty() and absf(float(v) - float((out[-1] as Array)[0])) < 1e-6:
			continue
		out.append([float(v), 0])
	# the wall lines come twice (a step: two vertices at the same place, the vertical face between them)
	var dup: Array = []
	for ln in out:
		var v: float = ln[0]
		var kind := 0
		for s in steps:   # [abs value, first kind]
			if absf(absf(v) - float(s[0])) < 1e-6:
				kind = int(s[1])
		if kind == 0:
			dup.append(ln)
		else:
			dup.append([v, kind])
			dup.append([v, kind + 1])
	return dup


## the shell as triangles (mm, canonical frame): {"v": PackedVector3Array, "t": PackedInt32Array}
static func shell_mesh(P: Dictionary, G: Dictionary) -> Dictionary:
	if P.has("poly"):
		return _poly_shell(P, G)
	var a: float = G["a"]
	var b: float = G["b"]
	var N := int(P["detail"])
	var span := minf(a, b)
	var c: float = span / float(N)
	var tp := String(G["type"])
	var kx: Array = []
	var kz: Array = []
	var xsteps: Array = []
	if tp == "hip" or tp == "xieshan":
		kx.append(a - b)
	if tp == "xieshan":
		var u1: float = G["u1"]
		kx.append(a - u1)
		kx.append(a - u1 - float(G["tw"]))
		xsteps.append([a - u1, 1])
		xsteps.append([a - u1 - float(G["tw"]), 3])
	var hx: float = G["hx"]
	var hz: float = G["hz"]
	if hx > 0.0 and hz > 0.0:
		kx.append(minf(hx, a - 1.0))
		kz.append(minf(hz, b - 1.0))
	var lx := _axis(a, c, kx, xsteps)
	var lz := _axis(b, c, kz, [])
	var nx := lx.size()
	var nz := lz.size()
	var TV := PackedVector3Array()
	var BV := PackedVector3Array()
	TV.resize(nx * nz)
	BV.resize(nx * nz)
	for i in nx:
		var x: float = lx[i][0]
		var kd: int = lx[i][1]
		for j in nz:
			var z: float = lz[j][0]
			var fl := 0
			if kd == 1 or kd == 2:
				fl = 1 if ((kd == 1) == (x > 0.0)) else -1
			var ty: float = float((top(G, x, z, fl) as Array)[0])
			var by: float = bottom(G, x, z, kd)
			if kd != 0:   # a step that shrinks to nothing (where the hip skirt meets the slope) leaves slivers the kernel's sewing would collapse: below 0.5 mm it is no step
				if kd <= 2:
					var other: float = float((top(G, x, z, -fl) as Array)[0])
					if absf(other - ty) < 0.5:
						ty = float((top(G, x, z, 1) as Array)[0])
				else:
					var ob: float = bottom(G, x, z, 7 - kd)
					if absf(ob - by) < 0.5:
						by = bottom(G, x, z, 3)
			TV[i * nz + j] = Vector3(x, ty, z)
			BV[i * nz + j] = Vector3(x, by, z)
	var weld := {}
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var wid := func(p: Vector3) -> int:
		var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if weld.has(key):
			return weld[key]
		var n := verts.size()
		verts.append(p)
		weld[key] = n
		return n
	var in_hole := func(cx: float, cz: float) -> bool:
		return hx > 0.0 and hz > 0.0 and absf(cx) < hx and absf(cz) < hz
	var exists := func(i: int, j: int) -> bool:
		if i < 0 or j < 0 or i >= nx - 1 or j >= nz - 1:
			return false
		return not in_hole.call((float(lx[i][0]) + float(lx[i + 1][0])) * 0.5, (float(lz[j][0]) + float(lz[j + 1][0])) * 0.5)
	var coll: Array = []
	var emit := func(p: Vector3, q: Vector3, r: Vector3) -> void:
		var ia: int = wid.call(p)
		var ib: int = wid.call(q)
		var ic: int = wid.call(r)
		if ia == ib or ib == ic or ia == ic:
			return
		if (q - p).cross(r - p).length() < 1e-6:   # a step's end cap on a wall: three points on one vertical line. The kernel drops it, so its edges are handed to the neighbours below
			coll.append([ia, ib, ic])
			return
		tris.append(ia)
		tris.append(ib)
		tris.append(ic)
	for i in nx - 1:
		for j in nz - 1:
			if not exists.call(i, j):
				continue
			var q00 := i * nz + j
			var q01 := i * nz + j + 1
			var q10 := (i + 1) * nz + j
			var q11 := (i + 1) * nz + j + 1
			var cx := (float(lx[i][0]) + float(lx[i + 1][0])) * 0.5
			var cz := (float(lz[j][0]) + float(lz[j + 1][0])) * 0.5
			if cx * cz >= 0.0:   # the diagonal that runs along the hips
				emit.call(TV[q00], TV[q01], TV[q11])
				emit.call(TV[q00], TV[q11], TV[q10])
				emit.call(BV[q00], BV[q11], BV[q01])
				emit.call(BV[q00], BV[q10], BV[q11])
			else:
				emit.call(TV[q00], TV[q01], TV[q10])
				emit.call(TV[q01], TV[q11], TV[q10])
				emit.call(BV[q00], BV[q10], BV[q01])
				emit.call(BV[q01], BV[q10], BV[q11])
			# the side walls where the next cell is not there; the outward side is told by the plan direction
			for side in 4:
				var ni: int = i + int([-1, 0, 1, 0][side])
				var nj: int = j + int([0, 1, 0, -1][side])
				if exists.call(ni, nj):
					continue
				var ta: Vector3
				var tb: Vector3
				var ba: Vector3
				var bb: Vector3
				var out := Vector3.ZERO
				match side:
					0: ta = TV[q00]; tb = TV[q01]; ba = BV[q00]; bb = BV[q01]; out = Vector3(-1, 0, 0)
					1: ta = TV[q01]; tb = TV[q11]; ba = BV[q01]; bb = BV[q11]; out = Vector3(0, 0, 1)
					2: ta = TV[q11]; tb = TV[q10]; ba = BV[q11]; bb = BV[q10]; out = Vector3(1, 0, 0)
					_: ta = TV[q10]; tb = TV[q00]; ba = BV[q10]; bb = BV[q00]; out = Vector3(0, 0, -1)
				_wall(emit, ta, tb, ba, bb, out)
	# the long edge of each dropped line triangle is split at the middle point, in the one triangle that holds it
	for ct in coll:
		var ids: Array = (ct as Array).duplicate()
		ids.sort_custom(func(u: int, w: int) -> bool: return verts[u].y > verts[w].y)
		var hi: int = ids[0]
		var mid: int = ids[1]
		var lo: int = ids[2]
		for ti in range(0, tris.size(), 3):
			var done := false
			for k in 3:
				var u: int = tris[ti + k]
				var v: int = tris[ti + (k + 1) % 3]
				var w: int = tris[ti + (k + 2) % 3]
				if (u == hi and v == lo) or (u == lo and v == hi):
					tris[ti] = u
					tris[ti + 1] = mid
					tris[ti + 2] = w
					tris.append(mid)
					tris.append(v)
					tris.append(w)
					done = true
					break
			if done:
				break
	return {"v": verts, "t": tris}


## a wall quad between a top edge and the bottom edge under it, wound to face `out`
static func _wall(emit: Callable, ta: Vector3, tb: Vector3, ba: Vector3, bb: Vector3, out: Vector3) -> void:
	var n1 := (ba - ta).cross(bb - ta)
	var n2 := (bb - ta).cross(tb - ta)
	if n1.dot(out) + n2.dot(out) >= 0.0:
		emit.call(ta, ba, bb)
		emit.call(ta, bb, tb)
	else:
		emit.call(ta, bb, ba)
		emit.call(ta, tb, bb)


## a convex polygon plan: rings of the outline shrunk toward the middle (the apex stands over the middle: exact planar faces, hips from the corners)
static func _poly_shell(P: Dictionary, G: Dictionary) -> Dictionary:
	var poly: Array = P["poly"]
	var o := float(P["overhang"])
	var cen := Vector2.ZERO
	for q in poly:
		cen += q
	cen /= float(poly.size())
	# the eave outline: every edge pushed out by the overhang
	var n := poly.size()
	var pts: Array = []
	var area2 := 0.0
	for i in n:
		area2 += (poly[i] as Vector2).cross(poly[(i + 1) % n])
	var sgn := 1.0 if area2 > 0.0 else -1.0
	var lines: Array = []   # per edge: [normal, offset]
	for i in n:
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % n]
		var dir := (p1 - p0).normalized()
		var nm := Vector2(dir.y, -dir.x) * sgn   # outward
		lines.append([nm, nm.dot(p0 - cen) + o])
	for i in n:
		var l0: Array = lines[(i + n - 1) % n]
		var l1: Array = lines[i]
		var n0: Vector2 = l0[0]
		var n1: Vector2 = l1[0]
		var det := n0.x * n1.y - n0.y * n1.x
		if absf(det) < 1e-9:
			continue
		var c0: float = l0[1]
		var c1: float = l1[1]
		pts.append(Vector2((c0 * n1.y - c1 * n0.y) / det, (n0.x * c1 - n1.x * c0) / det) + cen)
	n = pts.size()
	var R := int(P["detail"])
	var seg := maxi(2, R / 3)   # points per edge of the outline
	var ring: Array = []
	for i in n:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		for s in seg:
			ring.append(p0.lerp(p1, float(s) / float(seg)))
	var m := ring.size()
	var H: float = G["H"]
	var hole: Vector2 = P["hole"]
	# the corner lift is a bump round each corner; the height is a pyramid over the middle
	var corners: Array = pts
	var ll: float = G["ll"] if float(P["lift_len"]) > 0.0 else 0.3 * _min_radius(pts, cen)
	var TV := PackedVector3Array()
	var BV := PackedVector3Array()
	var rings := R
	for r in rings + 1:
		var f := 1.0 - float(r) / float(rings)   # 1 at the eave, 0 at the middle
		for i in m:
			var q: Vector2 = cen + ((ring[i] as Vector2) - cen) * f
			var h := H * (1.0 - _gauge(lines, q - cen)) if String(G["type"]) != "flat" else 0.0
			var gr := _poly_grad(lines, q - cen, H) if String(G["type"]) != "flat" else Vector2.ZERO
			var T := h
			var sg: float = G["sag"]
			if H > 0.0 and sg > 0.0:
				var s := clampf(h / H, 0.0, 1.0)
				T -= sg * 4.0 * s * (1.0 - s)
				gr *= 1.0 - sg * 4.0 * (1.0 - 2.0 * s) / H
			var lf := 0.0
			if float(G["lift"]) != 0.0:
				var dv := 1e12
				for cp in corners:
					dv = minf(dv, q.distance_to(cp))
				var tq := dv / ll
				if tq < 1.0:
					lf = float(G["lift"]) * (1.0 - tq) * (1.0 - tq)
					var e := 0.5
					gr += Vector2((_corner_bump(G, corners, q + Vector2(e, 0), ll) - _corner_bump(G, corners, q - Vector2(e, 0), ll)) / (2.0 * e),
						(_corner_bump(G, corners, q + Vector2(0, e), ll) - _corner_bump(G, corners, q - Vector2(0, e), ll)) / (2.0 * e))
			T += lf
			TV.append(Vector3(q.x, T, q.y))
			BV.append(Vector3(q.x, T - float(G["t"]) * sqrt(1.0 + gr.x * gr.x + gr.y * gr.y), q.y))
	var weld := {}
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var wid := func(p: Vector3) -> int:
		var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if weld.has(key):
			return weld[key]
		var k := verts.size()
		verts.append(p)
		weld[key] = k
		return k
	var emit := func(p: Vector3, q: Vector3, r: Vector3) -> void:
		var ia: int = wid.call(p)
		var ib: int = wid.call(q)
		var ic: int = wid.call(r)
		if ia == ib or ib == ic or ia == ic:
			return
		tris.append(ia)
		tris.append(ib)
		tris.append(ic)
	var first_ring := 0
	if hole.x > 0.0:   # an open top: the rings stop where the middle opening starts (a ring-shaped skirt)
		first_ring = 0
	var last_ring := rings
	if hole.x > 0.0:
		last_ring = clampi(roundi(float(rings) * (1.0 - clampf(minf(hole.x, hole.y) / (2.0 * _min_radius(pts, cen)), 0.05, 0.95))), 1, rings)
	for r in range(first_ring, last_ring):
		for i in m:
			var i1 := (i + 1) % m
			var a0 := r * m + i
			var a1 := r * m + i1
			var b0 := (r + 1) * m + i
			var b1 := (r + 1) * m + i1
			# the ring runs counter-clockwise seen from above when sgn > 0; the top faces up either way (the volume sign decides at the end)
			emit.call(TV[a0], TV[b0], TV[b1])
			emit.call(TV[a0], TV[b1], TV[a1])
			emit.call(BV[a0], BV[b1], BV[b0])
			emit.call(BV[a0], BV[a1], BV[b1])
	# the eave wall
	for i in m:
		var i1 := (i + 1) % m
		_wall_poly(emit, TV[i], TV[i1], BV[i], BV[i1], (TV[i] + TV[i1]) * 0.5 - Vector3(cen.x, TV[i].y, cen.y))
	if hole.x > 0.0:
		for i in m:
			var i1 := (i + 1) % m
			var ra := last_ring * m
			_wall_poly(emit, TV[ra + i], TV[ra + i1], BV[ra + i], BV[ra + i1], Vector3(cen.x, TV[ra + i].y, cen.y) - (TV[ra + i] + TV[ra + i1]) * 0.5)
	else:
		pass   # the middle point is a single vertex (the rings close on it)
	return {"v": verts, "t": tris}


static func _corner_bump(G: Dictionary, corners: Array, q: Vector2, ll: float) -> float:
	var dv := 1e12
	for cp in corners:
		dv = minf(dv, q.distance_to(cp))
	var tq := dv / ll
	return 0.0 if tq >= 1.0 else float(G["lift"]) * (1.0 - tq) * (1.0 - tq)


static func _wall_poly(emit: Callable, ta: Vector3, tb: Vector3, ba: Vector3, bb: Vector3, out: Vector3) -> void:
	out.y = 0.0
	_wall(emit, ta, tb, ba, bb, out)


static func _min_radius(pts: Array, cen: Vector2) -> float:
	var r := 1e12
	for p in pts:
		r = minf(r, (p as Vector2).distance_to(cen))
	return r


## the gauge of the outline at v (from the middle): 1 on the eave, 0 at the middle
static func _gauge(lines: Array, v: Vector2) -> float:
	var g := 0.0
	for l in lines:
		g = maxf(g, (l[0] as Vector2).dot(v) / maxf(float(l[1]), 1e-6))
	return g


static func _poly_grad(lines: Array, v: Vector2, H: float) -> Vector2:
	var g := -1e9
	var best := Vector2.ZERO
	for l in lines:
		var gv := (l[0] as Vector2).dot(v) / maxf(float(l[1]), 1e-6)
		if gv > g:
			g = gv
			best = (l[0] as Vector2) / maxf(float(l[1]), 1e-6)
	return -best * H


# ----------------------------------------------------------------------------------------------- the trims

## a thin bar swept along a 3D path (mm): width w across, height h up from the path line; the frame is mitred at the corners
static func sweep_mesh(path: Array, closed: bool, w: float, h: float, down := 0.0) -> Dictionary:
	var n := path.size()
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	if n < 2 or w <= 0.0 or h <= 0.0:
		return {"v": verts, "t": tris}
	var ring: Array = []
	for i in n:
		var p: Vector3 = path[i]
		var tp: Vector3 = ((path[(i + 1) % n] as Vector3) - p) if (closed or i < n - 1) else (p - (path[i - 1] as Vector3))
		var tm: Vector3 = (p - (path[(i + n - 1) % n] as Vector3)) if (closed or i > 0) else tp
		tp = tp.normalized()
		tm = tm.normalized()
		var tg := (tp + tm).normalized()
		var s := Vector3.UP.cross(tg).normalized()
		var s0 := Vector3.UP.cross(tp).normalized()
		var scl := 1.0 / maxf(s.dot(s0), 0.3)
		var half := s * (w * 0.5 * scl)
		ring.append([p - half + Vector3.UP * -down, p + half + Vector3.UP * -down, p + half + Vector3.UP * h, p - half + Vector3.UP * h])
	for i in n:
		for k in 4:
			verts.append((ring[i][k] as Vector3))
	var seg_n := n if closed else n - 1
	for i in seg_n:
		var j := (i + 1) % n
		for k in 4:
			var k1 := (k + 1) % 4
			var a := i * 4 + k
			var b := i * 4 + k1
			var c := j * 4 + k1
			var d := j * 4 + k
			tris.append_array(PackedInt32Array([a, b, c, a, c, d]))
	if not closed:
		tris.append_array(PackedInt32Array([0, 2, 1, 0, 3, 2]))
		var l := (n - 1) * 4
		tris.append_array(PackedInt32Array([l, l + 1, l + 2, l, l + 2, l + 3]))
	if signed_volume(verts, tris) < 0.0:
		for t in range(0, tris.size(), 3):
			var tmp := tris[t + 1]
			tris[t + 1] = tris[t + 2]
			tris[t + 2] = tmp
	return {"v": verts, "t": tris}


## the trims as paths on the top surface (canonical frame, mm)
static func trim_paths(P: Dictionary, G: Dictionary) -> Dictionary:
	var out := {"ridge": [], "hips": [], "eave": []}
	var a: float = G["a"]
	var b: float = G["b"]
	var tp := String(G["type"])
	var f := func(x: float, z: float) -> Vector3:
		return Vector3(x, float((top(G, x, z, 0) as Array)[0]), z)
	var n := 40
	if P.has("poly"):
		return out
	if tp in ["gable", "hip", "xieshan"]:
		var x1 := a
		if tp == "hip":
			x1 = a - b
		elif tp == "xieshan":
			x1 = a - float(G["u1"]) - 1e-3
		var path: Array = []
		for i in n + 1:
			var x := -x1 + 2.0 * x1 * float(i) / float(n)
			path.append(f.call(x, 0.0))
		out["ridge"] = path
	if tp in ["hip", "xieshan"]:
		var paths: Array = []
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var path: Array = []
				var lam_max := b if tp == "hip" else minf(float(G["u1"]), b * 0.999)
				for i in n + 1:
					var u := lam_max * float(i) / float(n)
					var v := u
					if tp == "xieshan":
						v = u * float(G["ke"]) / float(G["k"])
					path.append(f.call(sx * (a - u), sz * (b - v)))
				paths.append(path)
		out["hips"] = paths
	if tp == "pyramid":
		var paths: Array = []
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var path: Array = []
				for i in n + 1:
					var s := float(i) / float(n)
					path.append(f.call(sx * a * (1.0 - s * 0.98), sz * b * (1.0 - s * 0.98)))
				paths.append(path)
		out["hips"] = paths
	# the eave: round the outline (a hole's ring has the same outer edge)
	var loop: Array = []
	var m := 24
	for i in m:
		loop.append(f.call(-a + 2.0 * a * float(i) / float(m), -b))
	for i in m:
		loop.append(f.call(a, -b + 2.0 * b * float(i) / float(m)))
	for i in m:
		loop.append(f.call(a - 2.0 * a * float(i) / float(m), b))
	for i in m:
		loop.append(f.call(-a, b - 2.0 * b * float(i) / float(m)))
	out["eave"] = loop
	return out


# ----------------------------------------------------------------------------------------------- the world

static func signed_volume(v: PackedVector3Array, t: PackedInt32Array) -> float:
	var s := 0.0
	for i in range(0, t.size(), 3):
		s += v[t[i]].dot(v[t[i + 1]].cross(v[t[i + 2]])) / 6.0
	return s


## canonical -> world (mm): the plan turned a quarter when the ridge runs along Z, then moved to "at"
static func to_world(G: Dictionary, P: Dictionary, p: Vector3) -> Vector3:
	var q := Vector3(p.z, p.y, -p.x) if bool(G["swap"]) else p
	return q + (P["at"] as Vector3)


## s237 THE RIDGE AND THE CORNERS FROM THE ROOF'S OWN PARAMETERS (an ornament seated on the roof reads these, not a number typed by hand):
## {"a": Vector3, "b": Vector3} the two ends of the main ridge (world mm; y = the top surface there, sag and lift included), {} for a roof with no ridge line
## (flat, shed, pyramid, a polygon). A hip's ridge ends where its two hips meet it, a xieshan's at the gable's set-in line, a gable's at the gable ends.
static func ridge_line(f: Dictionary) -> Dictionary:
	var P := norm(f)
	if P.has("poly") and (P["poly"] as Array).size() >= 3:
		return {}
	var G := geometry(P)
	var half := 0.0
	match String(G["type"]):
		"hip":
			half = float(G["a"]) - minf(float(G["a"]), float(G["b"]))
		"xieshan":
			half = float(G["a"]) - float(G["u1"])
		"gable":
			half = float(G["a"])
		_:
			return {}
	var ya: float = float(top(G, -half, 0.0, 1)[0])
	var yb: float = float(top(G, half, 0.0, 1)[0])
	return {"a": to_world(G, P, Vector3(-half, ya, 0.0)), "b": to_world(G, P, Vector3(half, yb, 0.0))}


## the four eave corners of a hip-family roof, each: {"at": the point `inset` mm in along the hip from the corner (on the top surface), "dir": outward, level}
static func corner_points(f: Dictionary, inset: float) -> Array:
	var P := norm(f)
	var G := geometry(P)
	var out: Array = []
	var a: float = G["a"]
	var b: float = G["b"]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var o := Vector3(sx, 0.0, sz).normalized()
			var x: float = sx * (a - inset * 0.7071)
			var z: float = sz * (b - inset * 0.7071)
			var w := to_world(G, P, Vector3(x, float(top(G, x, z)[0]), z))
			var d := to_world(G, P, o) - to_world(G, P, Vector3.ZERO)
			out.append({"at": w, "dir": Vector3(d.x, 0.0, d.z).normalized()})
	return out


## every body of the roof: [{"name", "v" (mm), "t"}]; the first is the shell
static func meshes(f: Dictionary) -> Array:
	builds += 1
	var P := norm(f)
	var G := geometry(P)
	var out: Array = []
	var sh := shell_mesh(P, G)
	out.append(_finish("Roof", sh["v"], sh["t"], G, P))
	var want_trim: bool = P["ridge"] or P["hips"] or P["eave"]
	if want_trim:
		var tw := float(P["trim_w"]) if float(P["trim_w"]) > 0.0 else 3.0 * float(P["thick"])
		var th := float(P["trim_h"]) if float(P["trim_h"]) > 0.0 else 2.0 * float(P["thick"])
		var emb := 0.4 * float(P["thick"])   # sunk into the shell so the trim touches it (a join merges them)
		var tp := trim_paths(P, G)
		if P["ridge"] and not (tp["ridge"] as Array).is_empty():
			var m := sweep_mesh(tp["ridge"], false, tw, th + emb, emb)
			out.append(_finish("Ridge", m["v"], m["t"], G, P))
		if P["hips"]:
			var k := 1
			for path in tp["hips"]:
				var m := sweep_mesh(path, false, tw, th + emb, emb)
				out.append(_finish("Hip ridge %d" % k, m["v"], m["t"], G, P))
				k += 1
		if P["eave"]:
			var m := sweep_mesh(tp["eave"], true, tw, th + emb, emb)
			out.append(_finish("Eave edge", m["v"], m["t"], G, P))
	return out


static func _finish(nm: String, v: PackedVector3Array, t: PackedInt32Array, G: Dictionary, P: Dictionary) -> Dictionary:
	var vv := PackedVector3Array()
	for p in v:
		vv.append(to_world(G, P, p))
	var tt := t
	if signed_volume(vv, tt) < 0.0:
		tt = PackedInt32Array()
		for i in range(0, t.size(), 3):
			tt.append(t[i])
			tt.append(t[i + 2])
			tt.append(t[i + 1])
	return {"name": nm, "v": vv, "t": tt}


## the number of edges that do not have exactly two triangles (0 = closed): tests and the replay read it
static func open_edges(t: PackedInt32Array) -> int:
	var cnt := {}
	for i in range(0, t.size(), 3):
		for k in 3:
			var a := t[i + k]
			var b := t[i + (k + 1) % 3]
			var key := (mini(a, b) << 24) | maxi(a, b)
			cnt[key] = int(cnt.get(key, 0)) + (1 if a < b else 1000)
	var bad := 0
	for key in cnt:
		if int(cnt[key]) != 1001:
			bad += 1
	return bad


## the kernel id of body k of the roof (a fresh copy the caller owns), or 0 + KCad.last_error()
static func solid(f: Dictionary, k: int, mesh: Dictionary) -> int:
	var key := hash(JSON.stringify(norm(f)) + "|" + str(k))
	if _masters.has(key):
		var c := KCad.translate(int(_masters[key]), Vector3.ZERO)
		if c != 0:
			return c
		_masters.erase(key)
	var vs := PackedVector3Array()
	for p in (mesh["v"] as PackedVector3Array):
		vs.append(p * MM)
	var id := KCad.solid_from_mesh(vs, mesh["t"], 1e-6)
	if id == 0:
		return 0
	_masters[key] = id
	return KCad.translate(id, Vector3.ZERO)


## the replay arm (Part.replay): the step adds the shell and each trim as new bodies. "" or the plain reason it could not
static func add(bodies: Array, f: Dictionary) -> String:
	if not KCad.has_mesh_solid():
		return "The part library is older than this step: restart Kine, or reinstall it"
	if PartFast.roof_copy(bodies, f):   # s249 fast build: the same roof somewhere else is a translated copy
		return ""
	var fkey := hash(JSON.stringify(norm(f)))
	if _counts.has(fkey):   # a replay of the same numbers: copy the sewn solids, build nothing
		var got: Array = []
		for k in int(_counts[fkey]):
			var mk := hash(JSON.stringify(norm(f)) + "|" + str(k))
			var c := KCad.translate(int(_masters[mk]), Vector3.ZERO) if _masters.has(mk) else 0
			if c == 0:
				for g in got:
					KCad.release(int(g))
				got = []
				break
			got.append(c)
		if not got.is_empty():
			bodies.append_array(got)
			return ""
	var ms := meshes(f)
	_counts[fkey] = ms.size()
	var made: Array = []
	for k in ms.size():
		var m: Dictionary = ms[k]
		if (m["t"] as PackedInt32Array).size() / 3 > MAX_TRIS:
			for id in made:
				KCad.release(int(id))
			return "This roof is too fine to build: lower its detail"
		var id := solid(f, k, m)
		if id == 0:
			for mid in made:
				KCad.release(int(mid))
			return ("The %s could not become a solid: " % String(m["name"]).to_lower()) + (KCad.last_error() if KCad.last_error() != "" else "the mesh is open")
		made.append(id)
	PartFast.roof_keep(f, made)
	bodies.append_array(made)
	return ""


## the plain words for the timeline
static func words(f: Dictionary) -> String:
	var P := norm(f)
	var s := "%s roof %s x %s mm" % [P["type"], str(snappedf(float(P["w"]), 1.0)), str(snappedf(float(P["d"]), 1.0))]
	if float(P["sag"]) > 0.0:
		s += ", sag %s" % str(snappedf(float(P["sag"]), 1.0))
	if float(P["lift"]) != 0.0:
		s += ", corners up %s" % str(snappedf(float(P["lift"]), 1.0))
	return s


## a new roof record's fields from a short dictionary (the agent's call): the unknown keys are dropped, the rest kept as given
static func fields_of(p: Dictionary) -> Dictionary:
	var out := {}
	for k in ["type", "w", "d", "poly", "overhang", "height", "pitch", "sag", "lift", "lift_len", "lift_pow", "thick", "gable_in", "hip_frac", "hole", "axis", "at", "ridge", "hips", "eave", "trim_w", "trim_h", "detail", "name"]:
		if p.has(k):
			out[k] = p[k]
	return out


## AGENT TOOLS: {"part_roof": ...} adds a roof step to the part on screen (ONE undo step) and answers what it made.
## p: the fields above (+ "edit": a step id to change instead). Returns {"ok", "id", "bodies", "volume_mm3", "box_mm", "error"}
static func serve(m: Node, p: Dictionary) -> Dictionary:
	if not Part.available():
		return {"ok": false, "error": Part.why_not()}
	var rec: Dictionary = (m.S.part as Dictionary).duplicate(true) if not m.S.part.is_empty() else Part.make("Part")
	var fields := fields_of(p)
	var edit := String(p.get("edit", ""))
	var feat: Dictionary
	if edit != "":
		var idx := Part.index_of(rec, edit)
		if idx < 0 or String((rec["features"] as Array)[idx].get("t", "")) != "roof":
			return {"ok": false, "error": "There is no roof step %s in this part" % edit}
		feat = (rec["features"] as Array)[idx]
		feat.merge(fields, true)
	else:
		feat = Part.new_feature(rec, "roof", fields)
		(rec["features"] as Array).append(feat)
	var res := Part.replay(rec, -1, {"effects": true})
	var errs: Dictionary = res["errors"]
	if errs.has(String(feat["id"])):
		return {"ok": false, "error": String(errs[String(feat["id"])])}
	m._step_hint = ("Edit " if edit != "" else "") + String(feat["name"])
	m._push_undo()
	m.S.part = rec
	if m.has_method("_fit_top"):
		m._fit_top.call_deferred()
	var bb: Variant = res.get("aabb", null)
	return PartFx.merge_into({"ok": true, "id": String(feat["id"]), "bodies": int(res["bodies"]), "volume_mm3": float(res["volume"]) / (MM * MM * MM), "box_mm": bb, "words": words(feat)}, res, String(feat["id"]))
