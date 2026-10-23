class_name KMeshCurve
extends RefCounted
## B12 (docs/ROADMAP_400.md): A BEZIER CURVE turned into a mesh: belts, straps, cables. Pure maths, no UI (the curve
## object in the model preview is scripts/kmesh_curves_ui.gd).
## THE CURVE: control points {"p", "l" (left handle), "r" (right handle), all absolute positions in mesh space, "tilt"
##   (deg, the profile turned about the tangent there), "radius" (a scale of the profile there)}; open or closed. A
##   segment is the cubic Bezier p_i, r_i, l_i+1, p_i+1. Tilt and radius go linearly in t from point to point.
## TAPER: a radius curve along the LENGTH, Vector2(fraction of the arc length 0..1, scale), piecewise linear (empty = 1),
##   multiplied with the points' radius.
## FRAMES: rotation-minimizing (RMF), by the double reflection method (Wang, Juttler, Zheng, Liu 2008, "Computation of
##   Rotation Minimizing Frames", ACM TOG 27(1)): each sample's normal is the last one reflected twice, across the plane
##   square to the chord and then across the plane square to (t_i+1 - the reflected t_i). No up vector, so no flip where
##   the curve turns straight up (tests/meshcurves_test.gd shows an up-vector frame flipping there and this one not).
##   A CLOSED curve's frame does not in general come back to itself after one lap: the mismatch angle is spread along the
##   length (twist rate constant), so the tube closes with no seam twist.
## THE SWEEP: a profile in the frame's (normal, binormal) plane: "circle" (sides, radius) or "rect" (height along the
##   normal = the thickness, width along the binormal, `rect_segs` verts per width side so a strap can bend across its
##   width), at `res` samples per segment. Quads between rings; an OPEN curve gets an n-gon cap at each end (closed
##   solid), a closed one wraps the last ring to the first (a closed manifold tube, no doubled verts). Faces outward
##   (a closed result is turned if its signed volume is negative). UVs (corner "uv"): u around the profile, v along the length.
## SHRINKWRAP (B13): wrap(sw, offset) moves the control points onto the target's surface + (offset + half the thickness)
##   along its outward normal (handles go with their point); the sweep of a wrapped curve then puts each ring's centre
##   there too, turns its normal to the skin's, and lays the strap's inner face `offset` off the skin and its outer face
##   offset + height (KMeshShrinkwrap.wrap_mesh, nearest): a belt round the waist sits `offset` off the skin.

const PROFILES := ["circle", "rect"]
const K_CIRCLE := 0.5522847498   # handle length / radius of a 4-point bezier circle

var pts: Array = []
var closed := false
var profile := "circle"
var sides := 12
var radius := 0.01      # m (circle)
var width := 0.04       # m (rect, along the binormal)
var height := 0.004     # m (rect, along the normal: the thickness)
var rect_segs := 4      # verts per width side of the rect
var res := 12           # samples per segment
var taper := PackedVector2Array()
var caps := true
var wrap_offset := NAN  # m off the target's surface once wrapped (NAN = not wrapped)


static func point(p: Vector3, l: Vector3, r: Vector3, tilt := 0.0, rad := 1.0) -> Dictionary:
	return {"p": p, "l": l, "r": r, "tilt": tilt, "radius": rad}


# ---------------------------------------------------------------- data

func to_dict() -> Dictionary:
	return {"pts": pts.duplicate(true), "closed": closed, "profile": profile, "sides": sides, "radius": radius, "width": width,
		"height": height, "rect_segs": rect_segs, "res": res, "taper": taper.duplicate(), "caps": caps, "wrap_offset": wrap_offset}


func from_dict(d: Dictionary) -> KMeshCurve:
	pts = (d.get("pts", []) as Array).duplicate(true)
	closed = bool(d.get("closed", false))
	profile = String(d.get("profile", "circle"))
	sides = maxi(3, int(d.get("sides", 12)))
	radius = float(d.get("radius", 0.01))
	width = float(d.get("width", 0.04))
	height = float(d.get("height", 0.004))
	rect_segs = maxi(1, int(d.get("rect_segs", 4)))
	res = maxi(1, int(d.get("res", 12)))
	taper = PackedVector2Array(d.get("taper", PackedVector2Array()))
	caps = bool(d.get("caps", true))
	wrap_offset = float(d.get("wrap_offset", NAN))
	return self


func copy() -> KMeshCurve:
	return KMeshCurve.new().from_dict(to_dict())


## a 4-point bezier circle of radius r around `axis` through c (closed), or an open S-curve of `n` points along +X
static func circle(c: Vector3, r: float, axis := Vector3.UP) -> KMeshCurve:
	var cv := KMeshCurve.new()
	cv.closed = true
	axis = axis.normalized()
	var a := Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD
	a = (a - axis * a.dot(axis)).normalized()
	var b := axis.cross(a)
	for i in 4:
		var t := TAU * i / 4.0
		var d := a * cos(t) + b * sin(t)
		var tg := -a * sin(t) + b * cos(t)
		cv.pts.append(point(c + d * r, c + d * r - tg * r * K_CIRCLE, c + d * r + tg * r * K_CIRCLE))
	return cv


static func s_curve(at: Vector3, length := 0.6, n := 4) -> KMeshCurve:
	var cv := KMeshCurve.new()
	n = maxi(n, 2)
	var step := length / (n - 1)
	for i in n:
		var p := at + Vector3(step * i, 0.08 * (1.0 if i % 2 == 1 else -1.0) * (1.0 if i > 0 and i < n - 1 else 0.5), 0.0)
		var h := Vector3(step / 3.0, 0.0, 0.0)
		cv.pts.append(point(p, p - h, p + h))
	return cv


func seg_count() -> int:
	return pts.size() if closed and pts.size() > 2 else maxi(pts.size() - 1, 0)


func _ctrl(s: int) -> Array:
	var a: Dictionary = pts[s]
	var b: Dictionary = pts[(s + 1) % pts.size()]
	return [a["p"], a["r"], b["l"], b["p"]]


## the curve at segment s, parameter t (0..1)
func at(s: int, t: float) -> Vector3:
	var c := _ctrl(s)
	var u := 1.0 - t
	return c[0] * (u * u * u) + c[1] * (3.0 * u * u * t) + c[2] * (3.0 * u * t * t) + c[3] * (t * t * t)


## d/dt at segment s, t; where a handle sits on its point (zero derivative) the chord's direction stands in
func deriv(s: int, t: float) -> Vector3:
	var c := _ctrl(s)
	var u := 1.0 - t
	var d: Vector3 = (c[1] - c[0]) * (3.0 * u * u) + (c[2] - c[1]) * (6.0 * u * t) + (c[3] - c[2]) * (3.0 * t * t)
	if d.length_squared() < 1e-20:
		var e := 1e-4
		d = at(s, minf(t + e, 1.0)) - at(s, maxf(t - e, 0.0))
	if d.length_squared() < 1e-20:
		d = c[3] - c[0]
	return d


## the samples the sweep uses: {"x": positions, "t": unit tangents, "tilt" (deg), "rad" (point radius x taper), "s": arc
## length to each} — res per segment; an open curve ends on its last point, a closed one does not repeat the first.
## "L": the total length (a closed curve's includes the way back to the first sample)
func samples(r := -1) -> Dictionary:
	r = res if r < 1 else r
	var X := PackedVector3Array()
	var T := PackedVector3Array()
	var tilt := PackedFloat64Array()
	var prad := PackedFloat64Array()
	var ns := seg_count()
	for s in ns:
		var a: Dictionary = pts[s]
		var b: Dictionary = pts[(s + 1) % pts.size()]
		for i in r:
			var t := float(i) / r
			X.append(at(s, t))
			T.append(deriv(s, t).normalized())
			tilt.append(lerpf(float(a["tilt"]), float(b["tilt"]), t))
			prad.append(lerpf(float(a["radius"]), float(b["radius"]), t))
	if not closed and ns > 0:
		var b: Dictionary = pts[pts.size() - 1]
		X.append(at(ns - 1, 1.0))
		T.append(deriv(ns - 1, 1.0).normalized())
		tilt.append(float(b["tilt"]))
		prad.append(float(b["radius"]))
	var S := PackedFloat64Array([0.0])
	for i in range(1, X.size()):
		S.append(S[i - 1] + X[i].distance_to(X[i - 1]))
	var L := S[S.size() - 1] + (X[X.size() - 1].distance_to(X[0]) if closed and X.size() > 0 else 0.0)
	var rad := PackedFloat64Array()
	for i in X.size():
		rad.append(prad[i] * taper_at(S[i] / L if L > 0.0 else 0.0))
	return {"x": X, "t": T, "tilt": tilt, "rad": rad, "s": S, "L": L}


## the taper scale at a fraction f of the length (piecewise linear over `taper`, held flat past its ends; empty = 1)
func taper_at(f: float) -> float:
	if taper.is_empty():
		return 1.0
	if f <= taper[0].x:
		return taper[0].y
	for i in range(1, taper.size()):
		if f <= taper[i].x:
			var a := taper[i - 1]
			var b := taper[i]
			return lerpf(a.y, b.y, (f - a.x) / maxf(b.x - a.x, 1e-12))
	return taper[taper.size() - 1].y


## a unit vector square to t (the first frame's normal): the world axis least along t, made square
static func any_normal(t: Vector3) -> Vector3:
	var a := Vector3.RIGHT
	var lo := absf(t.x)
	if absf(t.y) < lo:
		a = Vector3.UP
		lo = absf(t.y)
	if absf(t.z) < lo:
		a = Vector3.BACK
	return (a - t * a.dot(t)).normalized()


## ROTATION-MINIMIZING normals along positions X with unit tangents T (double reflection; see the header). closed: the
## lap's mismatch spread along the arc length S (L = the lap's length). n0: the first normal (square to T[0]), else any
static func rmf(X: PackedVector3Array, T: PackedVector3Array, closed_lap := false, S := PackedFloat64Array(), L := 0.0, n0 := Vector3.ZERO) -> PackedVector3Array:
	var n := X.size()
	var R := PackedVector3Array()
	if n == 0:
		return R
	var r0 := n0 - T[0] * n0.dot(T[0])
	R.append(r0.normalized() if r0.length_squared() > 1e-12 else any_normal(T[0]))
	var last := n if closed_lap else n - 1
	var r_end := Vector3.ZERO
	for i in last:
		var j := (i + 1) % n
		var ri := R[i]
		var v1 := X[j] - X[i]
		var c1 := v1.dot(v1)
		var rl := ri
		var tl := T[i]
		if c1 > 1e-24:
			rl = ri - v1 * (2.0 / c1 * v1.dot(ri))
			tl = T[i] - v1 * (2.0 / c1 * v1.dot(T[i]))
		var v2 := T[j] - tl
		var c2 := v2.dot(v2)
		var rn := rl - v2 * (2.0 / c2 * v2.dot(rl)) if c2 > 1e-24 else rl
		rn = (rn - T[j] * rn.dot(T[j])).normalized()   # keep it square to the tangent (round-off)
		if j == 0:
			r_end = rn
		else:
			R.append(rn)
	if closed_lap and L > 0.0:
		# the angle from R[0] to where the lap brought it, about T[0]; spread it back along the length
		var phi := atan2(T[0].dot(R[0].cross(r_end)), R[0].dot(r_end))
		for i in range(1, n):
			R[i] = R[i].rotated(T[i], -phi * S[i] / L).normalized()
	return R


## the profile in the frame's (normal, binormal) plane, CCW, scaled by 1 (radius / width / height are the curve's)
func profile_2d() -> PackedVector2Array:
	var out := PackedVector2Array()
	if profile == "rect":
		var hh := height * 0.5
		var hw := width * 0.5
		# corners (-h,-w) (h,-w) (h,w) (-h,w): the -h side is the inner face (against the skin when wrapped)
		out.append(Vector2(-hh, -hw))
		out.append(Vector2(hh, -hw))
		for i in range(1, rect_segs + 1):   # outer side, along the width
			out.append(Vector2(hh, -hw + width * i / rect_segs))
		out.append(Vector2(-hh, hw))
		for i in range(1, rect_segs):   # inner side, back
			out.append(Vector2(-hh, hw - width * i / rect_segs))
		return out
	for k in maxi(sides, 3):
		var a := TAU * k / maxi(sides, 3)
		out.append(Vector2(cos(a), sin(a)) * radius)
	return out


## the rect profile's inner-face verts (x = -height / 2), as profile indices
func inner_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	var p := profile_2d()
	for k in p.size():
		if profile == "rect" and p[k].x < 0.0:
			out.append(k)
	return out


## THE SWEEP. sw: a shrinkwrap target when the curve is wrapped (see the header); null = free in space.
## -> {"mesh": KMesh, "x", "t", "n" (the frame normals), "rad", "s", "L", "ring": profile verts per ring} or {} with
## "error" when there is nothing to sweep
func sweep(sw: KMeshShrinkwrap = null) -> Dictionary:
	if pts.size() < 2 or (closed and pts.size() < 3 and seg_count() < 2):
		return {"error": "a curve needs at least 2 points (3 to close)."}
	var sm := samples()
	var X: PackedVector3Array = sm["x"]
	var T: PackedVector3Array = sm["t"]
	var S: PackedFloat64Array = sm["s"]
	var L: float = sm["L"]
	var wrapped := sw != null and not is_nan(wrap_offset)
	var skin_n := PackedVector3Array()
	if wrapped:   # each ring's centre onto the skin + (offset + half the thickness); tangents from the new centres
		var half := height * 0.5 if profile == "rect" else radius
		var hint := -1
		for i in X.size():
			var h := sw.nearest(X[i], 0.0, hint)
			if h.is_empty():
				skin_n.append(Vector3.ZERO)
				continue
			hint = h["t"]
			var nn := sw.normal_at(h["t"], h["b"])
			skin_n.append(nn)
			X[i] = h["p"] + nn * (wrap_offset + half)
		var n := X.size()
		for i in n:
			var a := X[(i - 1 + n) % n] if (closed or i > 0) else X[i]
			var b := X[(i + 1) % n] if (closed or i < n - 1) else X[i]
			if (b - a).length_squared() > 1e-20:
				T[i] = (b - a).normalized()
		S = PackedFloat64Array([0.0])
		for i in range(1, n):
			S.append(S[i - 1] + X[i].distance_to(X[i - 1]))
		L = S[n - 1] + (X[n - 1].distance_to(X[0]) if closed else 0.0)
	var N := rmf(X, T, closed, S, L)
	var tilt: PackedFloat64Array = sm["tilt"]
	var rad: PackedFloat64Array = sm["rad"]
	for i in N.size():
		if wrapped and skin_n[i] != Vector3.ZERO:
			var sn := skin_n[i] - T[i] * skin_n[i].dot(T[i])
			if sn.length_squared() > 1e-12:
				N[i] = sn.normalized()
		if tilt[i] != 0.0:
			N[i] = N[i].rotated(T[i], deg_to_rad(tilt[i])).normalized()
	var prof := profile_2d()
	var np := prof.size()
	var ns := X.size()
	var vs := PackedVector3Array()
	for i in ns:
		var b := T[i].cross(N[i])
		for k in np:
			vs.append(X[i] + (N[i] * prof[k].x + b * prof[k].y) * rad[i])
	var fs: Array = []
	var uv := PackedVector2Array()
	var rings := ns if closed else ns - 1
	for i in rings:
		var i2 := (i + 1) % ns
		var v0 := S[i] / L
		var v1 := (S[i2] if i2 != 0 else L) / L
		for k in np:
			var k2 := (k + 1) % np
			fs.append(PackedInt32Array([i * np + k, i * np + k2, i2 * np + k2, i2 * np + k]))
			var u0 := float(k) / np
			var u1 := float(k + 1) / np
			uv.append_array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
	if not closed and caps:
		var c0 := PackedInt32Array()
		var c1 := PackedInt32Array()
		var lo := Vector2.INF
		var hi := -Vector2.INF
		for p in prof:
			lo = lo.min(p)
			hi = hi.max(p)
		var span := (hi - lo).max(Vector2(1e-9, 1e-9))
		var cu0 := PackedVector2Array()
		var cu1 := PackedVector2Array()
		for k in np:
			c0.append(np - 1 - k)
			cu0.append((prof[np - 1 - k] - lo) / span)
			c1.append((ns - 1) * np + k)
			cu1.append((prof[k] - lo) / span)
		fs.append(c0)
		uv.append_array(cu0)
		fs.append(c1)
		uv.append_array(cu1)
	var km := KMesh.new().from_arrays(vs, fs)
	km.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	km.set_attr_data("uv", uv)
	if km.is_closed() and KMeshValidate._volume(km) < 0.0:
		KMeshLathe.flip(km)
	if wrapped and profile == "rect":   # the inner face `offset` off the skin, the outer face the thickness further
		var inner := inner_ids()
		var vin := PackedInt32Array()
		var vout := PackedInt32Array()
		for i in ns:
			for k in np:
				if inner.has(k):
					vin.append(i * np + k)
				else:
					vout.append(i * np + k)
		sw.wrap_mesh(km, {"verts": vin, "offset": wrap_offset})
		sw.wrap_mesh(km, {"verts": vout, "offset": wrap_offset + height})
	return {"mesh": km, "x": X, "t": T, "n": N, "rad": rad, "s": S, "L": L, "ring": np}


## SHRINKWRAP the control points onto sw's surface, offset + half the thickness out along its normal (handles move
## with their point); the sweep follows (see the header). -> points moved
func wrap(sw: KMeshShrinkwrap, offset := 0.003) -> int:
	var half := height * 0.5 if profile == "rect" else radius
	var moved := 0
	for i in pts.size():
		var d: Dictionary = pts[i]
		var h := sw.nearest(d["p"])
		if h.is_empty():
			continue
		var q: Vector3 = h["p"] + sw.normal_at(h["t"], h["b"]) * (offset + half)
		var dv: Vector3 = q - d["p"]
		d["p"] = q
		d["l"] = d["l"] + dv
		d["r"] = d["r"] + dv
		moved += 1
	wrap_offset = offset
	return moved


## the nearest point of the curve to every sample of a dense polyline (n per segment): for measuring
func polyline(n := 400) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in seg_count():
		for i in n:
			out.append(at(s, float(i) / n))
	if not closed and seg_count() > 0:
		out.append(at(seg_count() - 1, 1.0))
	return out
