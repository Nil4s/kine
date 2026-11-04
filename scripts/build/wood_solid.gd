class_name WoodSolid
extends RefCounted
## CH4 SOLID WOOD (Nick 11-03, "wood that obeys its grain"): a procedural grain FIELD in 3D. The colour of a point of a board is a function of
## where that point is inside the log, never of where it is on some face, so a cut face (a chamfer, a dovetail flank, a sawn end) shows the grain
## the tree put there and the rings run on across every corner. Reference numbers: docs/CH4_REFERENCE.md.
##
## SPEC (all lengths mm, in the mesh's own space; norm() fills the rest):
##   {"kind": "oak3d", "seed": int, "pith": [x, y, z] (a point on the tree's axis, may lie outside the board), "dir": [x, y, z] (the axis; the grain runs this way),
##    "ring": 2.0 (mean ring spacing), "ring_var": 0.35 (ring wander, in rings), "oval": 0.07 (the trunk is not round), "oval_ang": deg,
##    "pore_p": 0.55 (share of earlywood cells holding a pore), "ray_dens": 0.35 (share of slots holding a medullary ray)}
##
## THE FIELD (one formula, written three times and held equal by tests/ch4_test.gd): GDScript here, C++ in native/src/kine_wood_native.cpp (baking many
## points), GLSL in wood_solid.gdshader (the render). Hash = a 32-bit integer mix, so the three agree on every cell.
##   q = p - pith; t, a, b = q along the axis and two across it; (a, b) turned by oval_ang; rho0 = sqrt((a(1+oval))^2 + b^2)
##   g = rho0 / ring + wander(low-frequency 3D noise)         <- the growth coordinate: its integer part is the ring, its fraction the position in the ring
##   earlywood (large pores, light) -> latewood (dense, 0.77 as bright, the last half of the ring), a sharp step at every integer of g
##   pores: tubes along the axis in segments 8 pore-widths long (round dots on an end face at every depth, streaks on a long face), only in earlywood
##   medullary rays: radial sheets at angular slots, a width, a height along the axis and a radial extent each; lighter than the wood

const KIND := "oak3d"
const EW := Vector3(0.804, 0.635, 0.486)   # earlywood sRGB: the light zone of the fresh Quercus robur disc (205, 162, 124) (docs/CH4_REFERENCE.md)
const LATE_K := 0.77                        # latewood / earlywood brightness, from the 1200 dpi scan (125,99,77) / (162,132,103)
const PORE_CELL := 0.42                     # mm across the pore lattice
const PORE_STRETCH := 8.0                   # a pore is 8x longer along the grain than across
const RAY_SLOTS := 240
const M32 := 0xFFFFFFFF
const MM := 0.001

static var _native_checked := false
static var _native = null


static func norm(spec: Dictionary) -> Dictionary:
	var out := {"kind": KIND}
	out["seed"] = int(spec.get("seed", 1))
	var pi: Array = spec.get("pith", [0, 0, 0])
	out["pith"] = Vector3(float(pi[0]), float(pi[1]), float(pi[2]))
	var di: Array = spec.get("dir", [0, 0, 1])
	var w := Vector3(float(di[0]), float(di[1]), float(di[2]))
	w = w.normalized() if w.length() > 1e-9 else Vector3(0, 0, 1)
	out["w"] = w
	var refv := Vector3(0, 1, 0) if absf(w.y) < 0.9 else Vector3(1, 0, 0)
	var u := w.cross(refv).normalized()
	out["u"] = u
	out["v"] = w.cross(u)
	out["ring"] = clampf(float(spec.get("ring", 2.0)), 0.3, 40.0)
	out["ring_var"] = clampf(float(spec.get("ring_var", 0.35)), 0.0, 2.0)
	out["oval"] = clampf(float(spec.get("oval", 0.07)), 0.0, 0.5)
	out["oval_ang"] = deg_to_rad(float(spec.get("oval_ang", 0.0)))
	out["pore_p"] = clampf(float(spec.get("pore_p", 0.55)), 0.0, 1.0)
	out["ray_dens"] = clampf(float(spec.get("ray_dens", 0.35)), 0.0, 1.0)
	return out


# ---------------------------------------------------------------- the hash and the noise (identical in C++ and GLSL)

static func hash3(x: int, y: int, z: int, s: int) -> float:
	var h: int = (((x & M32) * 0x8da6b343) & M32) ^ (((y & M32) * 0xd8163841) & M32) ^ (((z & M32) * 0xcb1ab31f) & M32) ^ (((s & M32) * 0x165667b1) & M32)
	h ^= h >> 15
	h = (h * 0x2c1b3c6d) & M32
	h ^= h >> 12
	h = (h * 0x297a2d39) & M32
	h ^= h >> 15
	return float(h) / 4294967296.0


static func vnoise(x: float, y: float, z: float, s: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var iz := floori(z)
	var fx := x - ix
	var fy := y - iy
	var fz := z - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var c000 := hash3(ix, iy, iz, s)
	var c100 := hash3(ix + 1, iy, iz, s)
	var c010 := hash3(ix, iy + 1, iz, s)
	var c110 := hash3(ix + 1, iy + 1, iz, s)
	var c001 := hash3(ix, iy, iz + 1, s)
	var c101 := hash3(ix + 1, iy, iz + 1, s)
	var c011 := hash3(ix, iy + 1, iz + 1, s)
	var c111 := hash3(ix + 1, iy + 1, iz + 1, s)
	var x00 := c000 + (c100 - c000) * fx
	var x10 := c010 + (c110 - c010) * fx
	var x01 := c001 + (c101 - c001) * fx
	var x11 := c011 + (c111 - c011) * fx
	var y0 := x00 + (x10 - x00) * fy
	var y1 := x01 + (x11 - x01) * fy
	return y0 + (y1 - y0) * fz


static func sstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- the field

## one point (mm) -> [r, g, b (sRGB 0..1), phase g (continuous growth coordinate), pore 0..1, ray 0..1]
static func field(p: Vector3, sp: Dictionary) -> PackedFloat32Array:
	var seed: int = sp["seed"]
	var pith: Vector3 = sp["pith"]
	var qx: float = p.x - pith.x   # scalar doubles on purpose (Vector3 maths is float32 in Godot): the C++ field does the same
	var qy: float = p.y - pith.y
	var qz: float = p.z - pith.z
	var w: Vector3 = sp["w"]
	var uu: Vector3 = sp["u"]
	var vv: Vector3 = sp["v"]
	var t: float = w.x * qx + w.y * qy + w.z * qz
	var a: float = uu.x * qx + uu.y * qy + uu.z * qz
	var b: float = vv.x * qx + vv.y * qy + vv.z * qz
	var ca := cos(float(sp["oval_ang"]))
	var sa := sin(float(sp["oval_ang"]))
	var a2 := a * ca + b * sa
	var b2 := -a * sa + b * ca
	var ov := 1.0 + float(sp["oval"])
	var rho0 := sqrt(a2 * a2 * ov * ov + b2 * b2)
	var ring: float = sp["ring"]
	var n1 := vnoise(a / 30.0, b / 30.0, t / 120.0, seed + 11)
	var n2 := vnoise(a / 9.0, b / 9.0, t / 45.0, seed + 23)
	var wob := float(sp["ring_var"]) * (2.0 * n1 - 1.0) * 1.5 + 0.15 * (2.0 * n2 - 1.0)
	var g := rho0 / ring + wob
	var gi := floori(g)
	var f := g - gi
	var h1 := hash3(gi, 5, 5, seed + 3)
	var lw := sstep(0.45, 0.93, f) * (0.8 + 0.4 * h1)
	var tone := 1.0 + (LATE_K - 1.0) * minf(lw, 1.0)
	# pores
	var ewz := 1.0 - sstep(0.0, 0.3, f)
	var pa := a2 / PORE_CELL
	var pb := b2 / PORE_CELL
	var pt := t / (PORE_CELL * PORE_STRETCH)
	var ci := floori(pa)
	var cj := floori(pb)
	var ck := floori(pt)
	var cx := 0.5 + 0.3 * (2.0 * hash3(ci, cj, ck, seed + 31) - 1.0)
	var cy := 0.5 + 0.3 * (2.0 * hash3(ci, cj, ck, seed + 32) - 1.0)
	var dx := (pa - ci) - cx
	var dy := (pb - cj) - cy
	var e := sqrt(dx * dx + dy * dy)   # a vessel is a TUBE along the axis, broken into segments (cells) that are on or off
	var present := 1.0 if hash3(ci, cj, ck, seed + 34) < float(sp["pore_p"]) * ewz else 0.0
	var pore := present * (1.0 - sstep(0.17, 0.26, e))
	tone *= 1.0 - 0.45 * pore
	# rays
	var ray := 0.0
	if rho0 > 4.0:
		var th := atan2(b2, a2)
		var dth := TAU / RAY_SLOTS
		var k0 := floori(th / dth)
		for dk in range(-2, 3):
			var k := k0 + dk
			if hash3(k, 0, 0, seed + 41) >= float(sp["ray_dens"]):
				continue
			var cth := (k + 0.5 + 0.8 * (hash3(k, 1, 0, seed + 43) - 0.5)) * dth
			var dd := th - cth
			if cos(dd) <= 0.0:
				continue
			var wk := 0.12 + 0.45 * hash3(k, 2, 0, seed + 44)
			var lat := absf(rho0 * sin(dd))
			if lat >= 0.5 * wk:
				continue
			var hk := 14.0 + 40.0 * hash3(k, 3, 0, seed + 45)
			var zi := floori((t + hash3(k, 4, 0, seed + 46) * hk) / hk)
			if hash3(k, zi, 7, seed + 47) >= 0.6:
				continue
			var lr := 22.0
			var ri := floori((rho0 + hash3(k, 5, 0, seed + 48) * lr) / lr)
			if hash3(k, ri, 9, seed + 53) >= 0.7:
				continue
			ray = maxf(ray, 1.0 - sstep(0.3 * wk, 0.5 * wk, lat))
	tone *= 1.0 + 0.2 * ray
	# fibre streaks and slow tone
	tone *= 0.94 + 0.12 * vnoise(a / 0.45, b / 0.45, t / 18.0, seed + 61)
	tone *= 0.93 + 0.14 * vnoise(qx / 40.0, qy / 40.0, qz / 40.0, seed + 67)
	var c := EW * tone
	return PackedFloat32Array([clampf(c.x, 0.0, 1.0), clampf(c.y, 0.0, 1.0), clampf(c.z, 0.0, 1.0), g, pore, ray])


## the PLANTED CONTROL: the same grain as a 2D picture wrapped on one face (UV mapped): the field is read on the face's own flat (u, v) coordinates,
## the third coordinate stuck at 0, so every face gets its own picture and the rings do not run across an edge.
static func field_2d(p: Vector3, origin: Vector3, ex: Vector3, ey: Vector3, sp: Dictionary) -> PackedFloat32Array:
	var d := p - origin
	return field(Vector3(d.dot(ex), d.dot(ey), 0.0), sp)


# ---------------------------------------------------------------- baking many points (C++ when the DLL is there)

static func _native_impl():
	if not _native_checked:
		_native_checked = true
		if NativeExt.ensure("kine_native", "KineWoodNative"):
			_native = load("res://scripts/build/wood_solid_native.gd")
	return _native


static func has_native() -> bool:
	return _native_impl() != null


## the field at every point (mm): 6 floats each (see field()); C++ when it is built, the GDScript above otherwise (force_gd: always GDScript)
static func sample(pts: PackedVector3Array, spec: Dictionary, force_gd := false) -> PackedFloat32Array:
	var sp := norm(spec)
	var n = null if force_gd else _native_impl()
	if n != null:
		return n.sample(pts, sp)
	var out := PackedFloat32Array()
	out.resize(pts.size() * 6)
	for i in pts.size():
		var r := field(pts[i], sp)
		for k in 6:
			out[i * 6 + k] = r[k]
	return out


## the control's samples (field_2d at every point)
static func sample_2d(pts: PackedVector3Array, origin: Vector3, ex: Vector3, ey: Vector3, spec: Dictionary) -> PackedFloat32Array:
	var sp := norm(spec)
	var local := PackedVector3Array()
	local.resize(pts.size())
	for i in pts.size():
		var d := pts[i] - origin
		local[i] = Vector3(d.dot(ex), d.dot(ey), 0.0)
	return sample(local, spec)


## a flat patch of the field as pixels: origin (mm), the two edge directions (unit), w x h mm at ppm pixels per mm; pixel centres are sampled.
## Returns {"w": px, "h": px, "data": PackedFloat32Array (6 per pixel, row by row)}
static func bake_face(origin: Vector3, ex: Vector3, ey: Vector3, w_mm: float, h_mm: float, ppm: float, spec: Dictionary, force_gd := false) -> Dictionary:
	var nw := maxi(int(round(w_mm * ppm)), 1)
	var nh := maxi(int(round(h_mm * ppm)), 1)
	var pts := PackedVector3Array()
	pts.resize(nw * nh)
	var k := 0
	for j in nh:
		for i in nw:
			pts[k] = origin + ex * ((i + 0.5) / ppm) + ey * ((j + 0.5) / ppm)
			k += 1
	return {"w": nw, "h": nh, "data": sample(pts, spec, force_gd)}


# ---------------------------------------------------------------- the render material

## mode 0: lit wood; 1: the albedo only, unshaded (for tests); 2: the ring phase as (sin, cos) unshaded (for tests)
static func material(spec: Dictionary, mode := 0) -> ShaderMaterial:
	var sp := norm(spec)
	var sh := load("res://scripts/build/wood_solid.gdshader") as Shader
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("pith", sp["pith"])
	m.set_shader_parameter("ax_w", sp["w"])
	m.set_shader_parameter("ax_u", sp["u"])
	m.set_shader_parameter("ax_v", sp["v"])
	m.set_shader_parameter("seed", int(sp["seed"]))
	m.set_shader_parameter("ring", float(sp["ring"]))
	m.set_shader_parameter("ring_var", float(sp["ring_var"]))
	m.set_shader_parameter("oval", float(sp["oval"]))
	m.set_shader_parameter("oval_ang", float(sp["oval_ang"]))
	m.set_shader_parameter("pore_p", float(sp["pore_p"]))
	m.set_shader_parameter("ray_dens", float(sp["ray_dens"]))
	m.set_shader_parameter("mode", mode)
	return m


## the material of a Part look that carries a solid-wood spec ("mat": {"kind": "oak3d", ...}), else null
static func look_material(look: Dictionary, mode := 0) -> ShaderMaterial:
	var spec: Variant = look.get("mat", null)
	if spec is Dictionary and String((spec as Dictionary).get("kind", "")) == KIND:
		return material(spec as Dictionary, mode)
	return null
