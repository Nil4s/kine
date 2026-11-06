class_name Xform64
extends RefCounted
## G4DBL: a CAD pose in DOUBLES. Godot's Transform3D / Vector3 are float32 (1e-4 mm at 100 mm); a pose here is a PackedFloat64Array of 12:
## the 3x3 turn row major [r00 r01 r02 r10 r11 r12 r20 r21 r22], then the move [tx ty tz]. Units are the caller's (Assembly.xf64_of: metres).
## A point is an Array [x, y, z] of floats (doubles). Convert to Transform3D ONLY for display (to_t3d).

static func identity() -> PackedFloat64Array:
	return PackedFloat64Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])


static func make(rot9: PackedFloat64Array, t: Array) -> PackedFloat64Array:
	var o := rot9.duplicate()
	o.resize(12)
	o[9] = float(t[0])
	o[10] = float(t[1])
	o[11] = float(t[2])
	return o


## the turn of Basis.from_euler (YXZ: z first, then x, then y; R = Ry Rx Rz) from degrees, as a pose
static func from_euler_deg(rot_deg: Array, t: Array) -> PackedFloat64Array:
	var x := deg_to_rad(float(rot_deg[0]))
	var y := deg_to_rad(float(rot_deg[1]))
	var z := deg_to_rad(float(rot_deg[2]))
	var rx := PackedFloat64Array([1, 0, 0, 0, cos(x), -sin(x), 0, sin(x), cos(x)])
	var ry := PackedFloat64Array([cos(y), 0, sin(y), 0, 1, 0, -sin(y), 0, cos(y)])
	var rz := PackedFloat64Array([cos(z), -sin(z), 0, sin(z), cos(z), 0, 0, 0, 1])
	return make(_mm3(_mm3(ry, rx), rz), t)


## a turn of ang radians about the axis [x, y, z] (Rodrigues), then the move t
static func from_axis_angle(axis: Array, ang: float, t: Array) -> PackedFloat64Array:
	var l := sqrt(float(axis[0]) * float(axis[0]) + float(axis[1]) * float(axis[1]) + float(axis[2]) * float(axis[2]))
	var x := float(axis[0]) / l
	var y := float(axis[1]) / l
	var z := float(axis[2]) / l
	var c := cos(ang)
	var s := sin(ang)
	var k := 1.0 - c
	return make(PackedFloat64Array([c + x * x * k, x * y * k - z * s, x * z * k + y * s, y * x * k + z * s, c + y * y * k, y * z * k - x * s, z * x * k - y * s, z * y * k + x * s, c + z * z * k]), t)


static func _mm3(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	o.resize(9)
	for i in 3:
		for j in 3:
			o[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]
	return o


## a * b: b first, then a
static func compose(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	o.resize(12)
	for i in 3:
		for j in 3:
			o[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]
		o[9 + i] = a[i * 3] * b[9] + a[i * 3 + 1] * b[10] + a[i * 3 + 2] * b[11] + a[9 + i]
	return o


## the inverse of any pose with an invertible turn (adjugate / determinant: exact to a few ulps, orthonormal or not)
static func inverse(a: PackedFloat64Array) -> PackedFloat64Array:
	var c0 := a[4] * a[8] - a[5] * a[7]
	var c1 := a[5] * a[6] - a[3] * a[8]
	var c2 := a[3] * a[7] - a[4] * a[6]
	var det := a[0] * c0 + a[1] * c1 + a[2] * c2
	var r := PackedFloat64Array([
		c0 / det, (a[2] * a[7] - a[1] * a[8]) / det, (a[1] * a[5] - a[2] * a[4]) / det,
		c1 / det, (a[0] * a[8] - a[2] * a[6]) / det, (a[2] * a[3] - a[0] * a[5]) / det,
		c2 / det, (a[1] * a[6] - a[0] * a[7]) / det, (a[0] * a[4] - a[1] * a[3]) / det])
	var o := r.duplicate()
	o.resize(12)
	for i in 3:
		o[9 + i] = -(r[i * 3] * a[9] + r[i * 3 + 1] * a[10] + r[i * 3 + 2] * a[11])
	return o


## the point p (an Array of 3 doubles) through the pose
static func apply(a: PackedFloat64Array, p: Array) -> Array:
	return [a[0] * p[0] + a[1] * p[1] + a[2] * p[2] + a[9], a[3] * p[0] + a[4] * p[1] + a[5] * p[2] + a[10], a[6] * p[0] + a[7] * p[1] + a[8] * p[2] + a[11]]


## the direction p through the turn only
static func apply_dir(a: PackedFloat64Array, p: Array) -> Array:
	return [a[0] * p[0] + a[1] * p[1] + a[2] * p[2], a[3] * p[0] + a[4] * p[1] + a[5] * p[2], a[6] * p[0] + a[7] * p[1] + a[8] * p[2]]


## the largest entry difference of two poses
static func max_diff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var m := 0.0
	for i in 12:
		m = maxf(m, absf(a[i] - b[i]))
	return m


## display only: the float32 Transform3D (each entry is the double rounded to float32)
static func to_t3d(a: PackedFloat64Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0], a[3], a[6]), Vector3(a[1], a[4], a[7]), Vector3(a[2], a[5], a[8])), Vector3(a[9], a[10], a[11]))


static func from_t3d(t: Transform3D) -> PackedFloat64Array:
	var b := t.basis
	return PackedFloat64Array([b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, t.origin.x, t.origin.y, t.origin.z])


## the turn as [unit axis, radians], in doubles: for a float32 kernel call with ONE rounding at the end
static func axis_angle(a: PackedFloat64Array) -> Array:
	var tr := a[0] + a[4] + a[8]
	var ang := acos(clampf((tr - 1.0) * 0.5, -1.0, 1.0))
	var ax := [a[7] - a[5], a[2] - a[6], a[3] - a[1]]
	var l := sqrt(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2])
	if l < 1e-12:
		if ang < 1e-9:
			return [[0.0, 0.0, 1.0], 0.0]
		var d := [a[0], a[4], a[8]]   # a half turn: the axis from the largest diagonal term
		var k := 0
		if d[1] > d[k]:
			k = 1
		if d[2] > d[k]:
			k = 2
		var v := [0.0, 0.0, 0.0]
		v[k] = sqrt(maxf((d[k] + 1.0) * 0.5, 0.0))
		for j in 3:
			if j != k:
				v[j] = a[k * 3 + j] / (2.0 * v[k])
		return [v, ang]
	return [[ax[0] / l, ax[1] / l, ax[2] / l], atan2(l * 0.5, (tr - 1.0) * 0.5)]
