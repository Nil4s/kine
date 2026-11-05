## ASSEMBLY LOOP (gap G2 of docs/CHALLENGE_FEEDBACK.md): joints between the parts of an Assembly, and a solver for CLOSED loops (a slider-crank,
## a four-bar), so a drive moves every part the joints tie to it. The record keeps one more OPTIONAL list next to G1MOTION's "drives" / "links":
##   "joints": [{"name", "kind": "revolute" | "slider" | "fixed", "a": part id, "b": part id | "ground",
##               "axis": [x, y, z] (a's frame), "origin": [mm] (a's frame), "origin_b": [mm] (b's frame; the world for ground; optional)}]
##     revolute: a's origin stays on b's origin; a turns about the axis
##     slider:   a's origin stays on the line through b's origin along the axis (carried by b); a does not turn against b
##     fixed:    a weld (the origin coincides and a does not turn against b)
##   Without "origin_b" the joint is where the record's poses put it: b's point is a's origin at the record pose.
## The loops are PLANAR: every revolute axis must be parallel (the common axis n) and every slider axis square to it. A part's place is
## M * Assembly.xf_of(part), M = a turn phi about n through the assembly origin, then a move (x, y) in the plane; the record pose is M = identity.
## The drive's part and its links are KNOWN (G1MOTION's motion); every other part named in a joint is FREE (3 unknowns). Newton-Raphson on the
## constraint residuals (mm; angles x a length scale), analytic Jacobian, full-pivot elimination (rank, the sign of det J = the assembly mode),
## the previous step as the first guess, the step halved when Newton fails or the mode flips; a step that still fails below MIN_STEP is a LOCK
## (a dead / toggle position: no pose past it). Doubles throughout (GDScript float); only the Transform3D handed to the screen is float32.
## NOT HERE: spatial (non-parallel) loops, gears / cams / pin-in-slot joints, joint limits.
class_name AssemblyLoop
extends RefCounted

const TOL := 1e-10        # mm: a constraint is met
const MAX_IT := 25        # Newton iterations per step
const MAX_STEP := 5.0     # drive units (deg / mm) per continuation step
const MIN_STEP := 1e-9    # a step that fails below this is a lock
const RANK_TOL := 1e-3    # a pivot under this x the largest one: the Jacobian has lost rank
const VERIFY_MM := 1e-6   # a joint between two known parts may be off by this much
const KINDS := ["revolute", "slider", "fixed"]


static func joints(asm: Dictionary) -> Array:
	return asm.get("joints", []) if asm.get("joints", null) is Array else []


static func has_joints(asm: Dictionary) -> bool:
	return not joints(asm).is_empty()


static func make_joint(kind: String, a: String, b: String, axis: Array, origin: Array, origin_b: Array = [], nm := "") -> Dictionary:
	var j := {"name": nm if nm != "" else "%s %s-%s" % [kind, a, b], "kind": kind, "a": a, "b": b, "axis": [float(axis[0]), float(axis[1]), float(axis[2])], "origin": [float(origin[0]), float(origin[1]), float(origin[2])]}
	if origin_b.size() >= 3:
		j["origin_b"] = [float(origin_b[0]), float(origin_b[1]), float(origin_b[2])]
	return j


static func add_joint(asm: Dictionary, j: Dictionary) -> void:
	var js: Array = joints(asm).duplicate()
	js.append(j)
	asm["joints"] = js


## a joint from a point and an axis in the ASSEMBLY frame (the screen): the origin and axis go into a's frame, the point into b's, at the record poses
static func joint_at(asm: Dictionary, kind: String, a: String, b: String, axis_w: Vector3, point_mm: Array, nm := "") -> Dictionary:
	var pa: Dictionary = asm["parts"][Assembly.index_of(asm, a)]
	var ra := _rot(pa["rot"])
	var P := _arr(point_mm)
	var oa := _tmul(ra, _sub(P, _arr(pa["pos"])))
	var ax := _tmul(ra, [float(axis_w.x), float(axis_w.y), float(axis_w.z)])
	var ob := P
	if b != "ground":
		var pb: Dictionary = asm["parts"][Assembly.index_of(asm, b)]
		ob = _tmul(_rot(pb["rot"]), _sub(P, _arr(pb["pos"])))
	return make_joint(kind, a, b, ax, oa, ob, nm)


# ------------------------------------------------------------------ doubles (Vector3 / Basis are float32)
static func _arr(a: Variant) -> Array:
	return [float(a[0]), float(a[1]), float(a[2])] if a is Array and (a as Array).size() >= 3 else [0.0, 0.0, 0.0]


static func _sub(a: Array, b: Array) -> Array:
	return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


static func _dot(a: Array, b: Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func _cross(a: Array, b: Array) -> Array:
	return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


static func _unit(a: Array) -> Array:
	var l := sqrt(_dot(a, a))
	return [a[0] / l, a[1] / l, a[2] / l] if l > 1e-300 else [0.0, 0.0, 1.0]


static func _mm3(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	o.resize(9)
	for i in 3:
		for j in 3:
			o[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]
	return o


## the record's turn as a double matrix (row major), Basis.from_euler's YXZ order: z first, then x, then y (R = Ry Rx Rz)
static func _rot(rot_deg: Variant) -> PackedFloat64Array:
	var r := _arr(rot_deg)
	var x := deg_to_rad(r[0])
	var y := deg_to_rad(r[1])
	var z := deg_to_rad(r[2])
	var rx := PackedFloat64Array([1, 0, 0, 0, cos(x), -sin(x), 0, sin(x), cos(x)])
	var ry := PackedFloat64Array([cos(y), 0, sin(y), 0, 1, 0, -sin(y), 0, cos(y)])
	var rz := PackedFloat64Array([cos(z), -sin(z), 0, sin(z), cos(z), 0, 0, 0, 1])
	return _mm3(_mm3(ry, rx), rz)


static func _mul(m: PackedFloat64Array, v: Array) -> Array:
	return [m[0] * v[0] + m[1] * v[1] + m[2] * v[2], m[3] * v[0] + m[4] * v[1] + m[5] * v[2], m[6] * v[0] + m[7] * v[1] + m[8] * v[2]]


static func _tmul(m: PackedFloat64Array, v: Array) -> Array:
	return [m[0] * v[0] + m[3] * v[1] + m[6] * v[2], m[1] * v[0] + m[4] * v[1] + m[7] * v[2], m[2] * v[0] + m[5] * v[1] + m[8] * v[2]]


## a point of a part's own frame (mm) at the record pose {"pos", "rot"}, in the assembly frame (mm, doubles)
static func pose_mm(p: Dictionary, local: Array) -> Array:
	var w := _mul(_rot(p["rot"]), _arr(local))
	var o := _arr(p["pos"])
	return [w[0] + o[0], w[1] + o[1], w[2] + o[2]]


# ------------------------------------------------------------------ the model
## the solver's view of the record for one drive: {"ok", "why", "n", "u", "w", "free", "idx", "cons", "verify", "m", "scale", "drive", "links", "wrap"}
static func model(asm: Dictionary, drive_name: String) -> Dictionary:
	var md := {"ok": false, "why": "", "free": [], "idx": {}, "cons": [], "verify": [], "m": 0}
	var d := AssemblyMotion.drive_of(asm, drive_name)
	if d.is_empty():
		md["why"] = "the assembly has no drive called '%s'" % drive_name
		return md
	md["drive"] = d
	var lk: Array = []
	for l in AssemblyMotion.links(asm):
		if String((l as Dictionary).get("drive", "")) == drive_name:
			lk.append(l)
	md["links"] = lk
	md["wrap"] = String(d.get("kind", "rotate")) == "rotate" and lk.is_empty()   # a turn alone repeats every 360 deg
	var known := {String(d["part"]): true}
	for l in lk:
		known[String(l["part"])] = true
	var js := joints(asm)
	var ps := {}
	for j in js:
		for k in ["a", "b"]:
			var id := String(j.get(k, ""))
			if id == "ground" and k == "b":
				continue
			var i := Assembly.index_of(asm, id)
			if i < 0:
				md["why"] = "joint '%s' names a part that isn't there (%s)" % [String(j.get("name", "")), id]
				return md
			ps[id] = asm["parts"][i]
		if not KINDS.has(String(j.get("kind", ""))):
			md["why"] = "joint '%s' is a '%s': only revolute, slider and fixed are solved" % [String(j.get("name", "")), String(j.get("kind", ""))]
			return md
	# the common axis: the first revolute's, else the drive's turn axis, else square to the sliders
	var n: Array = []
	for j in js:
		if String(j["kind"]) == "revolute":
			n = _unit(_mul(_rot(ps[String(j["a"])]["rot"]), _arr(j["axis"])))
			break
	if n.is_empty() and String(d.get("kind", "rotate")) == "rotate":
		n = _unit(_arr(d.get("axis")))
	if n.is_empty():
		var s1: Array = []
		for j in js:
			if String(j["kind"]) == "slider":
				var sw := _unit(_mul(_rot(ps[String(j["a"])]["rot"]), _arr(j["axis"])))
				if s1.is_empty():
					s1 = sw
				elif sqrt(_dot(_cross(s1, sw), _cross(s1, sw))) > 1e-6:
					n = _unit(_cross(s1, sw))
					break
		if n.is_empty():
			var t := [1.0, 0.0, 0.0] if s1.is_empty() or absf(s1[0]) < 0.9 else [0.0, 1.0, 0.0]
			n = _unit(_cross(s1 if not s1.is_empty() else [0.0, 0.0, 1.0], t))
	var t0 := [1.0, 0.0, 0.0] if absf(n[0]) < 0.9 else [0.0, 1.0, 0.0]
	var u := _unit(_sub(t0, [n[0] * _dot(t0, n), n[1] * _dot(t0, n), n[2] * _dot(t0, n)]))
	var w := _cross(n, u)
	md["n"] = n
	md["u"] = u
	md["w"] = w
	var free: Array = []
	for id in ps:
		if not known.has(id) and not free.has(id):
			free.append(id)
	var idx := {}
	for i in free.size():
		idx[free[i]] = i
	md["free"] = free
	md["idx"] = idx
	var pts: Array = []
	var cons: Array = []
	var verify: Array = []
	var m := 0
	for j in js:
		var a := String(j["a"])
		var b := String(j["b"])
		var kind := String(j["kind"])
		var pa: Dictionary = ps[a]
		var ra := _rot(pa["rot"])
		var pw := pose_mm(pa, _arr(j["origin"]))
		var qw := pw
		if j.has("origin_b"):
			qw = _arr(j["origin_b"]) if b == "ground" else pose_mm(ps[b], _arr(j["origin_b"]))
		var c := {"name": String(j.get("name", "")), "kind": kind, "a": a, "b": b, "pa": [_dot(pw, u), _dot(pw, w)], "pb": [_dot(qw, u), _dot(qw, w)]}
		var axw := _unit(_mul(ra, _arr(j["axis"])))
		if kind == "revolute" and sqrt(_dot(_cross(axw, n), _cross(axw, n))) > 1e-9:
			md["why"] = "joint '%s' turns about an axis the other joints don't share: only planar loops are solved" % c["name"]
			return md
		if kind == "slider":
			if absf(_dot(axw, n)) > 1e-9:
				md["why"] = "joint '%s' slides out of the plane the other joints turn in: only planar loops are solved" % c["name"]
				return md
			var d2 := [_dot(axw, u), _dot(axw, w)]
			var l2 := sqrt(d2[0] * d2[0] + d2[1] * d2[1])
			c["d"] = [d2[0] / l2, d2[1] / l2]
		c["rows"] = 3 if kind == "fixed" else 2
		pts.append(c["pa"])
		pts.append(c["pb"])
		if idx.has(a) or idx.has(b):
			cons.append(c)
			m += int(c["rows"])
		else:
			verify.append(c)
	var cx := 0.0
	var cy := 0.0
	for p in pts:
		cx += p[0] / pts.size()
		cy += p[1] / pts.size()
	var sc := 0.0
	for p in pts:
		sc += sqrt((p[0] - cx) * (p[0] - cx) + (p[1] - cy) * (p[1] - cy)) / pts.size()
	md["scale"] = maxf(sc, 1.0)
	md["cons"] = cons
	md["verify"] = verify
	md["m"] = m
	md["nq"] = 3 * free.size()
	# a known part in a joint must move in the plane
	for id in known:
		if ps.has(id) and _known_state(md, id, 1.0) == null:
			md["why"] = "the drive turns %s about an axis its joints don't share" % String(ps[id]["name"])
			return md
	if m < 3 * free.size():
		md["why"] = "the joints leave %d degree%s of freedom free: add a joint or a drive" % [3 * free.size() - m, "" if 3 * free.size() - m == 1 else "s"]
		return md
	md["ok"] = true
	return md


## the planar state [x, y, phi, z along n] a G1MOTION motion gives a known part; null when it turns out of the plane
static func _motion_state(md: Dictionary, kind: String, axis: Variant, origin: Variant, val: float) -> Variant:
	var n: Array = md["n"]
	var a := _unit(_arr(axis))
	if kind == "slide":
		var dv := [a[0] * val, a[1] * val, a[2] * val]
		return [_dot(dv, md["u"]), _dot(dv, md["w"]), 0.0, _dot(dv, n)]
	var c := _dot(a, n)
	if absf(1.0 - absf(c)) > 1e-9:
		return null if absf(val) > 0.0 else [0.0, 0.0, 0.0, 0.0]
	var phi := deg_to_rad(val) * signf(c)
	var o := _arr(origin)
	var ox := _dot(o, md["u"])
	var oy := _dot(o, md["w"])
	return [ox - (cos(phi) * ox - sin(phi) * oy), oy - (sin(phi) * ox + cos(phi) * oy), phi, 0.0]


static func _known_state(md: Dictionary, id: String, v: float) -> Variant:
	var d: Dictionary = md["drive"]
	if String(d["part"]) == id:
		return _motion_state(md, String(d.get("kind", "rotate")), d.get("axis"), d.get("origin"), v)
	for l in md["links"]:
		if String(l["part"]) == id:
			return _motion_state(md, String(l.get("kind", "rotate")), l.get("axis"), l.get("origin"), float(l.get("gain", 1.0)) * v)
	return [0.0, 0.0, 0.0, 0.0]


static func _knowns(md: Dictionary, v: float) -> Dictionary:
	var out := {}
	var d: Dictionary = md["drive"]
	out[String(d["part"])] = _known_state(md, String(d["part"]), v)
	for l in md["links"]:
		out[String(l["part"])] = _known_state(md, String(l["part"]), v)
	return out


static func _state(id: String, q: PackedFloat64Array, md: Dictionary, kn: Dictionary) -> Array:
	if id == "ground":
		return [0.0, 0.0, 0.0, 0.0]
	if md["idx"].has(id):
		var k: int = md["idx"][id] * 3
		return [q[k], q[k + 1], q[k + 2], 0.0]
	var s = kn.get(id, null)
	return s if s != null else [0.0, 0.0, 0.0, 0.0]


# ------------------------------------------------------------------ residuals and Jacobian
## {"r": residuals, "J": m x nq row major}; constraints of the verify list -> "v" (worst mm)
static func _eval(md: Dictionary, q: PackedFloat64Array, kn: Dictionary, list_key := "cons") -> Dictionary:
	var cons: Array = md[list_key]
	var nq: int = md["nq"]
	var r := PackedFloat64Array()
	var J := PackedFloat64Array()
	var mrows := 0
	for c in cons:
		mrows += int(c["rows"])
	r.resize(mrows)
	J.resize(mrows * nq)
	J.fill(0.0)
	var sc: float = md["scale"]
	var row := 0
	for c in cons:
		var sa := _state(c["a"], q, md, kn)
		var sb := _state(c["b"], q, md, kn)
		var ia: int = md["idx"][c["a"]] * 3 if md["idx"].has(c["a"]) else -1
		var ib: int = md["idx"][c["b"]] * 3 if md["idx"].has(c["b"]) else -1
		var ca := cos(sa[2])
		var sna := sin(sa[2])
		var cb := cos(sb[2])
		var snb := sin(sb[2])
		var p0: Array = c["pa"]
		var q0: Array = c["pb"]
		var rax: float = ca * p0[0] - sna * p0[1]
		var ray: float = sna * p0[0] + ca * p0[1]
		var rbx: float = cb * q0[0] - snb * q0[1]
		var rby: float = snb * q0[0] + cb * q0[1]
		var ex: float = rax + sa[0] - rbx - sb[0]
		var ey: float = ray + sa[1] - rby - sb[1]
		var kind: String = c["kind"]
		if kind == "slider":
			var d0: Array = c["d"]
			var dx: float = cb * d0[0] - snb * d0[1]
			var dy: float = snb * d0[0] + cb * d0[1]
			r[row] = dx * ey - dy * ex
			r[row + 1] = (sa[2] - sb[2]) * sc
			if ia >= 0:
				J[row * nq + ia] = -dy
				J[row * nq + ia + 1] = dx
				J[row * nq + ia + 2] = dx * rax - dy * (-ray)   # dir x d(Pa)/dphi, d(Pa)/dphi = (-ray, rax)
				J[(row + 1) * nq + ia + 2] = sc
			if ib >= 0:
				J[row * nq + ib] = dy
				J[row * nq + ib + 1] = -dx
				J[row * nq + ib + 2] = -(dx * ex + dy * ey) - (dx * rbx - dy * (-rby))
				J[(row + 1) * nq + ib + 2] = -sc
		else:
			r[row] = ex
			r[row + 1] = ey
			if ia >= 0:
				J[row * nq + ia] = 1.0
				J[(row + 1) * nq + ia + 1] = 1.0
				J[row * nq + ia + 2] = -ray
				J[(row + 1) * nq + ia + 2] = rax
			if ib >= 0:
				J[row * nq + ib] = -1.0
				J[(row + 1) * nq + ib + 1] = -1.0
				J[row * nq + ib + 2] = rby
				J[(row + 1) * nq + ib + 2] = -rbx
			if kind == "fixed":
				r[row + 2] = (sa[2] - sb[2]) * sc
				if ia >= 0:
					J[(row + 2) * nq + ia + 2] = sc
				if ib >= 0:
					J[(row + 2) * nq + ib + 2] = -sc
		row += int(c["rows"])
	return {"r": r, "J": J, "m": mrows}


static func _norm(r: PackedFloat64Array) -> float:
	var x := 0.0
	for v in r:
		x = maxf(x, absf(v))
	return x


## full-pivot elimination of A (m x n, m >= n) against rhs: {"ok", "x" (least squares through the normal equations when m > n), "rank", "ratio", "sign"}
static func _lin(A: PackedFloat64Array, m: int, n: int, rhs: PackedFloat64Array) -> Dictionary:
	var M := A.duplicate()
	var b := rhs.duplicate()
	if m > n:   # J^T J x = J^T b, the rank and pivots still come from J below
		var N := PackedFloat64Array()
		N.resize(n * n)
		var nb := PackedFloat64Array()
		nb.resize(n)
		for i in n:
			for j in n:
				var s := 0.0
				for k in m:
					s += A[k * n + i] * A[k * n + j]
				N[i * n + j] = s
			var t := 0.0
			for k in m:
				t += A[k * n + i] * rhs[k]
			nb[i] = t
		var sol := _lin(N, n, n, nb)
		var ru := _rank(A, m, n)
		sol["rank"] = ru["rank"]
		sol["ratio"] = ru["ratio"]
		sol["sign"] = 0
		return sol
	var col := PackedInt32Array()
	col.resize(n)
	for i in n:
		col[i] = i
	var sgn := 1
	var pmax := 0.0
	var pmin := INF
	var ok := true
	for k in n:
		var bi := k
		var bj := k
		var bv := -1.0
		for i in range(k, n):
			for j in range(k, n):
				var v := absf(M[i * n + j])
				if v > bv:
					bv = v
					bi = i
					bj = j
		if bi != k:
			for j in n:
				var t := M[k * n + j]
				M[k * n + j] = M[bi * n + j]
				M[bi * n + j] = t
			var tb := b[k]
			b[k] = b[bi]
			b[bi] = tb
			sgn = -sgn
		if bj != k:
			for i in n:
				var t := M[i * n + k]
				M[i * n + k] = M[i * n + bj]
				M[i * n + bj] = t
			var tc := col[k]
			col[k] = col[bj]
			col[bj] = tc
			sgn = -sgn
		var p := M[k * n + k]
		pmax = maxf(pmax, absf(p))
		pmin = minf(pmin, absf(p))
		if absf(p) <= 1e-300 or (pmax > 0.0 and absf(p) < 1e-14 * pmax):
			ok = false
			pmin = absf(p)
			break
		if p < 0.0:
			sgn = -sgn
		for i in range(k + 1, n):
			var f := M[i * n + k] / p
			if f == 0.0:
				continue
			for j in range(k, n):
				M[i * n + j] -= f * M[k * n + j]
			b[i] -= f * b[k]
	var x := PackedFloat64Array()
	x.resize(n)
	if ok:
		for k in range(n - 1, -1, -1):
			var s := b[k]
			for j in range(k + 1, n):
				s -= M[k * n + j] * x[col[j]]
			x[col[k]] = s / M[k * n + k]
	var ratio := pmin / pmax if pmax > 0.0 else 0.0
	return {"ok": ok, "x": x, "rank": _rank_from(M, n, pmax) if ok else _rank(A, m, n)["rank"], "ratio": ratio if ok else 0.0, "sign": sgn if ok else 0}


static func _rank_from(M: PackedFloat64Array, n: int, pmax: float) -> int:
	var r := 0
	for k in n:
		if absf(M[k * n + k]) >= RANK_TOL * pmax:
			r += 1
	return r


## the rank of A (m x n) by full-pivot elimination: {"rank", "ratio" (smallest pivot / largest)}
static func _rank(A: PackedFloat64Array, m: int, n: int) -> Dictionary:
	var M := A.duplicate()
	var pmax := 0.0
	var pmin := INF
	var steps := mini(m, n)
	var rank := 0
	for k in steps:
		var bi := k
		var bj := k
		var bv := -1.0
		for i in range(k, m):
			for j in range(k, n):
				var v := absf(M[i * n + j])
				if v > bv:
					bv = v
					bi = i
					bj = j
		for j in n:
			var t := M[k * n + j]
			M[k * n + j] = M[bi * n + j]
			M[bi * n + j] = t
		for i in m:
			var t := M[i * n + k]
			M[i * n + k] = M[i * n + bj]
			M[i * n + bj] = t
		var p := M[k * n + k]
		pmax = maxf(pmax, absf(p))
		pmin = minf(pmin, absf(p))
		if absf(p) >= RANK_TOL * pmax and absf(p) > 1e-300:
			rank += 1
		if absf(p) <= 1e-300:
			break
		for i in range(k + 1, m):
			var f := M[i * n + k] / p
			for j in range(k, n):
				M[i * n + j] -= f * M[k * n + j]
	return {"rank": rank, "ratio": pmin / pmax if pmax > 0.0 else 0.0}


# ------------------------------------------------------------------ Newton and continuation
## one Newton solve from q0 with the known parts kn: {"ok", "why", "q", "it", "res", "rank", "ratio", "mode"}
static func _newton(md: Dictionary, q0: PackedFloat64Array, kn: Dictionary, max_it := MAX_IT) -> Dictionary:
	var nq: int = md["nq"]
	var q := q0.duplicate()
	var ev := _eval(md, q, kn)
	var res := _norm(ev["r"])
	var it := 0
	while res >= TOL:
		if it >= max_it:
			return {"ok": false, "why": "no convergence in %d iterations (residual %s mm)" % [max_it, String.num_scientific(res)], "q": q, "it": it, "res": res}
		var neg := PackedFloat64Array()
		neg.resize(int(ev["m"]))
		for i in neg.size():
			neg[i] = -ev["r"][i]
		var sol := _lin(ev["J"], int(ev["m"]), nq, neg)
		it += 1
		if not bool(sol["ok"]):
			return {"ok": false, "why": "the Jacobian is singular", "q": q, "it": it, "res": res}
		var dx: PackedFloat64Array = sol["x"]
		var lam := 1.0
		var qn := q
		var evn := ev
		var rn := INF
		for k in 12:
			qn = q.duplicate()
			for i in nq:
				qn[i] += lam * dx[i]
			evn = _eval(md, qn, kn)
			rn = _norm(evn["r"])
			if rn < res or rn < TOL:
				break
			lam *= 0.5
		if not (rn < res or rn < TOL):
			return {"ok": false, "why": "Newton stalled (residual %s mm)" % String.num_scientific(res), "q": q, "it": it, "res": res}
		q = qn
		ev = evn
		res = rn
	var fin := _lin(ev["J"], int(ev["m"]), nq, PackedFloat64Array(ev["r"]))
	return {"ok": true, "why": "", "q": q, "it": it, "res": res, "rank": int(fin["rank"]), "ratio": float(fin["ratio"]), "mode": int(fin["sign"]), "singular": not bool(fin["ok"])}


static func _verify(md: Dictionary, q: PackedFloat64Array, kn: Dictionary) -> float:
	if (md["verify"] as Array).is_empty():
		return 0.0
	return _norm(_eval(md, q, kn, "verify")["r"])


## from (v0, q) to v1 in steps of at most max_step, halving a step that fails or flips the mode: {"ok", "q", "v", "it", "steps", "locked", "lock_at", "rank", "ratio", "mode", "why"}
static func _go(md: Dictionary, q: PackedFloat64Array, v0: float, v1: float, mode: int, opts: Dictionary) -> Dictionary:
	var hmax := float(opts.get("max_step", MAX_STEP))
	var v := v0
	var cur := q
	var it := 0
	var steps := 0
	var h := hmax
	var last := {"rank": md["nq"], "ratio": 1.0, "mode": mode}
	var max_it := int(opts.get("max_it", MAX_IT))
	while absf(v1 - v) > 1e-12 * maxf(1.0, absf(v1)):
		var rem := v1 - v
		var hs := signf(rem) * minf(h, absf(rem))
		var r := _newton(md, cur, _knowns(md, v + hs), max_it)
		it += int(r["it"])
		if bool(r["ok"]) and not bool(r.get("singular", false)) and (mode == 0 or int(r["mode"]) == 0 or int(r["mode"]) == mode):
			v = v1 if absf(hs) >= absf(rem) else v + hs
			cur = r["q"]
			mode = int(r["mode"]) if int(r["mode"]) != 0 else mode
			last = r
			steps += 1
			h = minf(h * 2.0, hmax)
			continue
		h = absf(hs) * 0.5
		if h < MIN_STEP:
			var ev := _eval(md, cur, _knowns(md, v))
			var ru := _rank(ev["J"], int(ev["m"]), int(md["nq"]))
			return {"ok": false, "locked": true, "lock_at": v, "toward": v1, "q": cur, "v": v, "it": it, "steps": steps, "rank": int(ru["rank"]), "ratio": float(ru["ratio"]), "mode": mode,
				"why": "locked at %s: the joints can't follow the drive past it (rank %d of %d)" % [String.num(v, 4), int(ru["rank"]), int(md["nq"])]}
	return {"ok": true, "locked": false, "q": cur, "v": v, "it": it, "steps": steps, "rank": int(last.get("rank", md["nq"])), "ratio": float(last.get("ratio", 1.0)), "mode": mode, "why": ""}


## assemble the record (drive at 0) and go to v along the shortest path (a lone turn wraps to -180..180): the record's own assembly mode
static func _fresh(md: Dictionary, v: float, opts: Dictionary) -> Dictionary:
	var q0 := PackedFloat64Array()
	q0.resize(int(md["nq"]))
	q0.fill(0.0)
	var a := _newton(md, q0, _knowns(md, 0.0))
	if not bool(a["ok"]):
		return {"ok": false, "locked": false, "it": int(a["it"]), "why": "the record's poses can't be put together by the joints: " + String(a["why"])}
	var vt := wrapf(v, -180.0, 180.0) if bool(md["wrap"]) else v
	var r := _go(md, a["q"], 0.0, vt, int(a["mode"]), opts)
	r["it"] = int(r["it"]) + int(a["it"])
	if bool(r["ok"]) and vt != v:   # the same pose, posed at the asked value
		var f := _newton(md, r["q"], _knowns(md, v))
		r["it"] = int(r["it"]) + int(f["it"])
		if bool(f["ok"]):
			r["q"] = f["q"]
		r["v"] = v
	return r


## the moves (part id -> Transform3D, metres) of a solution: the drive and its links as G1MOTION poses them, every free part from its state
static func _moves(asm: Dictionary, md: Dictionary, drive_name: String, v: float, q: PackedFloat64Array) -> Dictionary:
	var out := AssemblyMotion.open_moves(asm, drive_name, v)
	var n: Array = md["n"]
	var nv := Vector3(n[0], n[1], n[2])
	for id in md["free"]:
		var k: int = md["idx"][id] * 3
		var t := [md["u"][0] * q[k] + md["w"][0] * q[k + 1], md["u"][1] * q[k] + md["w"][1] * q[k + 1], md["u"][2] * q[k] + md["w"][2] * q[k + 1]]
		out[id] = Transform3D(Basis(nv, q[k + 2]), Vector3(t[0], t[1], t[2]) * Assembly.MM)
	return out


static func _states(md: Dictionary, v: float, q: PackedFloat64Array) -> Dictionary:
	var out := _knowns(md, v)
	for id in md["free"]:
		var k: int = md["idx"][id] * 3
		out[id] = [q[k], q[k + 1], q[k + 2], 0.0]
	out["_n"] = md["n"]
	out["_u"] = md["u"]
	out["_w"] = md["w"]
	return out


## the pose with the drive at v, solved from the record (stateless). {"ok", "why", "moves", "states", "it", "rank", "ratio", "mode", "n" (unknowns), "m" (equations), "locked", "lock_at"}
## When not ok, "moves" still has the drive's own part and its links (G1MOTION), so the screen shows the crank turning and the rest still
static func solve(asm: Dictionary, drive_name: String, v: float, opts := {}) -> Dictionary:
	var md := model(asm, drive_name)
	if not bool(md["ok"]):
		return {"ok": false, "why": md["why"], "moves": AssemblyMotion.open_moves(asm, drive_name, v), "states": {}, "it": 0, "locked": false}
	var r := _fresh(md, v, opts)
	var out := {"ok": bool(r["ok"]), "why": String(r.get("why", "")), "it": int(r.get("it", 0)), "rank": int(r.get("rank", 0)), "ratio": float(r.get("ratio", 0.0)), "mode": int(r.get("mode", 0)),
		"n": int(md["nq"]), "m": int(md["m"]), "locked": bool(r.get("locked", false)), "lock_at": r.get("lock_at", null)}
	if bool(r["ok"]):
		var off := _verify(md, r["q"], _knowns(md, v))
		if off > VERIFY_MM:
			out["ok"] = false
			out["why"] = "a joint between the drive and a fixed part is broken by %s mm" % String.num_scientific(off)
		out["moves"] = _moves(asm, md, drive_name, v, r["q"])
		out["states"] = _states(md, v, r["q"])
	else:
		out["moves"] = AssemblyMotion.open_moves(asm, drive_name, v)
		out["states"] = {}
	return out


## the drive at each of vals in turn, each step from the last one's pose (opts "warm": false solves each from the record's zero guess with
## no continuation: the planted control). {"ok", "why", "steps": [{"v", "ok", "moves", "states", "it", "rank", "ratio", "mode"}],
## "locks": [{"at", "toward", "rank", "ratio"}], "unsolved": [v], "iters_total", "iters_max", "ms", "n", "m"}
static func sweep(asm: Dictionary, drive_name: String, vals: Array, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var out := {"ok": false, "why": "", "steps": [], "locks": [], "unsolved": [], "iters_total": 0, "iters_max": 0, "ms": 0.0, "n": 0, "m": 0}
	var md := model(asm, drive_name)
	if not bool(md["ok"]):
		out["why"] = md["why"]
		return out
	out["n"] = md["nq"]
	out["m"] = md["m"]
	var warm := bool(opts.get("warm", true))
	var have := false
	var q := PackedFloat64Array()
	var vprev := 0.0
	var mode := 0
	var steps: Array = []
	var locks: Array = []
	var unsolved: Array = []
	var itot := 0
	var imax := 0
	var last_failed = null
	for vv in vals:
		var v := float(vv)
		var r: Dictionary
		if not warm:
			var q0 := PackedFloat64Array()
			q0.resize(int(md["nq"]))
			q0.fill(0.0)
			r = _newton(md, q0, _knowns(md, v))
			r["locked"] = false
		elif have:
			r = _go(md, q, vprev, v, mode, opts)
			if not bool(r["ok"]) and bool(r.get("locked", false)):
				locks.append({"at": r["lock_at"], "toward": v, "rank": r["rank"], "ratio": r["ratio"]})
		else:
			r = _fresh(md, v, opts)
			if bool(r["ok"]) and last_failed != null:   # back in reach: where the reach begins
				var back := _go(md, r["q"], v, float(last_failed), int(r["mode"]), opts)
				if bool(back.get("locked", false)):
					locks.append({"at": back["lock_at"], "toward": last_failed, "rank": back["rank"], "ratio": back["ratio"]})
				itot += int(back["it"])
		var it := int(r.get("it", 0))
		itot += it
		imax = maxi(imax, it)
		if bool(r["ok"]):
			q = r["q"]
			vprev = v
			mode = int(r.get("mode", mode))
			have = true
			last_failed = null
			steps.append({"v": v, "ok": true, "moves": _moves(asm, md, drive_name, v, q), "states": _states(md, v, q), "it": it, "rank": int(r.get("rank", 0)), "ratio": float(r.get("ratio", 0.0)), "mode": mode})
		else:
			have = false
			last_failed = v
			unsolved.append(v)
			steps.append({"v": v, "ok": false, "moves": AssemblyMotion.open_moves(asm, drive_name, v), "states": {}, "it": it, "why": String(r.get("why", ""))})
	out["steps"] = steps
	out["locks"] = locks
	out["unsolved"] = unsolved
	out["iters_total"] = itot
	out["iters_max"] = imax
	out["ok"] = unsolved.size() < vals.size()
	out["why"] = "" if unsolved.is_empty() else ("%d of %d steps have no pose" % [unsolved.size(), vals.size()])
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## a point of part pid's own frame (mm) where the solution `states` puts it (mm, doubles). A part the solution doesn't move stays at its record pose
static func world_mm(asm: Dictionary, states: Dictionary, pid: String, local: Array) -> Array:
	var p: Dictionary = asm["parts"][Assembly.index_of(asm, pid)]
	var P := pose_mm(p, local)
	if not states.has(pid) or states.get(pid) == null:
		return P
	return apply_state(P, states[pid], states)


## an assembly-frame point P (mm) carried by the planar state s = [x, y, phi, z along n] (doubles); frame = a states dict with "_n", "_u", "_w"
static func apply_state(P: Array, s: Array, frame: Dictionary) -> Array:
	var n: Array = frame["_n"]
	var c := cos(s[2])
	var sn := sin(s[2])
	var nx := _cross(n, P)
	var nd := _dot(n, P)
	var R := [P[0] * c + nx[0] * sn + n[0] * nd * (1.0 - c), P[1] * c + nx[1] * sn + n[1] * nd * (1.0 - c), P[2] * c + nx[2] * sn + n[2] * nd * (1.0 - c)]
	var u: Array = frame["_u"]
	var w: Array = frame["_w"]
	for i in 3:
		R[i] += u[i] * s[0] + w[i] * s[1] + n[i] * s[3]
	return R


## lines for the screen: one per lock, and the count of steps with no pose
static func lock_words(res: Dictionary, unit: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lp: Dictionary = res.get("loop", {})
	for l in lp.get("locks", []):
		out.append("Locked at %s %s (a dead position: rank %d): no pose toward %s %s" % [String.num(float(l["at"]), 2), unit, int(l["rank"]), String.num(float(l["toward"]), 2), unit])
	var un: Array = lp.get("unsolved", [])
	if not un.is_empty():
		out.append("%d step%s with no pose (not checked)" % [un.size(), "" if un.size() == 1 else "s"])
	return out
