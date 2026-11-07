class_name FaceWrinkle
extends RefCounted
## face_wrinkle.gd - ROADMAP I09 (lane L62): EXPRESSION WRINKLES on the geometry face (FaceGeo).
## METHOD (measured, so any AU mix works): the posed mask is compared with the rest mask. For every vertex a 2x2 Green strain in the
## tangent plane is fitted from the incident edges (KineWrinkleNative.strain in C++, strain_gd is the GDScript twin; prep() once per mesh, wrinkle() per frame). Where the skin is
## COMPRESSED (the smallest principal strain < 0) a wrinkle forms: its depth follows the compression, its line runs PERPENDICULAR to the
## most compressive direction (the skin buckles across the compression). Wrinkles only form in the anatomical zones where expression
## lines occur (forehead, glabella, crow's feet, nasolabial, bunny lines: zones(), from the landmarks x s). The ridge pattern is drawn
## per fragment by the face shader from per-vertex values: amplitude + line direction (CUSTOM0), phase (CUSTOM1).
## EXTRA: FaceGeo d["au"] has no AU2 (outer brow raiser) or AU9 (nose wrinkler); they are generated here (EXTRA_AUS) and applied by posed().
## State = (amp, dir, phase) per vertex: a pure function of the AU weights, so save/reload and undo are exact when the AU state is.
## Nothing here is MIT / AGPL code; written from the FACS descriptions.

const WAVE := 0.0035       # m x s: spacing of the lines
const DEPTH := 0.00035     # m x s: ridge depth at amplitude 1 (slope = DEPTH * 2 pi / WAVE = 0.63)
const C0 := 0.02           # compression (unitless) where a wrinkle starts to show
const C1 := 0.12           # compression where it is full
const FEATHER := 0.003     # m: a zone fades over this distance inside its border
const EXTRA_AUS := ["AU2", "AU9"]
const DOOR := "res://scripts/face_wrinkle_door.gd"
const SHADER_CODE := """
shader_type spatial;
render_mode cull_back;
uniform float roughness_v = 0.8;
uniform float slope_k = 0.63;
uniform float cavity = 0.18;
varying vec4 wr;
varying vec3 tdv;
varying float ph;
vec3 lin(vec3 c) { return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
void vertex() {
	wr = CUSTOM0;
	tdv = (MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 0.0)).xyz;
	ph = CUSTOM1.x;
}
void fragment() {
	vec3 pp = cross(NORMAL, tdv);
	float pl = length(pp);
	float a = wr.w;
	float sn = sin(6.2831853 * ph);
	if (pl > 1e-5 && a > 0.0) {
		NORMAL = normalize(NORMAL - slope_k * a * sn * pp / pl);
	}
	ALBEDO = lin(COLOR.rgb) * (1.0 - cavity * a * (0.5 - 0.5 * cos(6.2831853 * ph)));
	ROUGHNESS = roughness_v;
}
"""
static var _door: GDScript = null


static func native_available() -> bool:
	return ClassDB.class_exists("KineWrinkleNative") or NativeExt.ensure("kine_native", "KineWrinkleNative")


static func material(_hm: Material) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


## the muscles that drive each zone (FACS): forehead AU1 + AU2 (frontalis), glabella AU4 (corrugator / procerus), crow's feet AU6 + AU12 (orbicularis
## oculi, the smile), nasolabial AU12 + AU10 (zygomaticus, levator labii), bunny lines AU9 (nasalis / levator labii superioris alaeque nasi).
## A zone can wrinkle only when one of its muscles is driven: the gate (0..1) per zone; the compression MEASURED on the mesh gives the depth,
## direction and place inside the zone. This keeps a neighbouring AU's strain spill (AU1 pushes the medial brow) from drawing lines elsewhere.
const DRIVERS := [["AU1", "AU2"], ["AU4"], ["AU6", "AU12"], ["AU12", "AU10"], ["AU9"]]


static func gates(au: Dictionary) -> PackedFloat64Array:
	var o := PackedFloat64Array()
	for zi in 5:
		var dv := 0.0
		for k in DRIVERS[zi]:
			dv += absf(float(au.get(k, 0.0)))
		o.append(_ss(0.0, 0.3, dv))
	return o


static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## the AU2 / AU9 blendshapes (cached in d)
static func extra_au(d: Dictionary) -> Dictionary:
	if d.has("wr_au"):
		return d["wr_au"]
	var an: Dictionary = d["anchors"]
	var s := float(an["top"]) / 1.754
	var ey := float((an["eye_l"] as Vector3).y)
	var by := float((an["brow_l"] as Vector3).y)
	var vs: PackedVector3Array = d["verts"]
	var d2 := PackedVector3Array()
	var d9 := PackedVector3Array()
	d2.resize(vs.size())
	d9.resize(vs.size())
	for i in vs.size():
		var p := vs[i]
		var sg := 1.0 if p.x >= 0.0 else -1.0
		var r2 := Vector2(p.x - sg * 0.034 * s, p.y - (by + 0.008 * s)).length() / (0.028 * s)
		if r2 < 1.0:
			var k := cos(r2 * PI * 0.5)
			d2[i] = Vector3(0.0, 0.005 * s * k * k, 0.0)
		var r9 := Vector2(p.x - sg * 0.012 * s, p.y - (ey - 0.008 * s)).length() / (0.016 * s)
		if r9 < 1.0:
			var k9 := cos(r9 * PI * 0.5)
			d9[i] = Vector3(-sg * 0.0025 * s * k9 * k9, 0.0035 * s * k9 * k9, 0.0)
	var d6p := PackedVector3Array()
	d6p.resize(vs.size())
	var hx := float((an["eye_l"] as Vector3).x)
	for i in vs.size():
		var p := vs[i]
		var sg := 1.0 if p.x >= 0.0 else -1.0
		var c := Vector2(sg * (hx + 0.015 * s), ey)
		var off := Vector2(p.x, p.y) - c
		var r6 := off.length() / (0.030 * s)
		if r6 < 1.0:
			var k6 := cos(r6 * PI * 0.5)
			var dd := -off * (0.45 * k6 * k6)
			d6p[i] = Vector3(dd.x, dd.y, 0.0)
	var o := {"AU2": d2, "AU9": d9, "AU6p": d6p}
	d["wr_au"] = o
	return o


## FaceGeo.posed + the EXTRA_AUS
static func posed(d: Dictionary, st: Dictionary) -> PackedVector3Array:
	var v := FaceGeo.posed(d, st)
	var au: Dictionary = st.get("au", {})
	var ex := extra_au(d)
	for k in EXTRA_AUS:
		var w := float(au.get(k, 0.0))
		if w != 0.0:
			var dl: PackedVector3Array = ex[k]
			for i in v.size():
				v[i] += dl[i] * w
	return v


## zone weights, types and phase fields of the REST mask (cached in d): zt (0 none, 1..5), zw (0..1), phi (m), nrm (rest normals)
static func zones(d: Dictionary) -> Dictionary:
	if d.has("wr_zone"):
		return d["wr_zone"]
	var an: Dictionary = d["anchors"]
	var s := float(an["top"]) / 1.754
	var hx := float((an["eye_l"] as Vector3).x)
	var ey := float((an["eye_l"] as Vector3).y)
	var by := float((an["brow_l"] as Vector3).y)
	var my := float((an["mouth"] as Vector3).y)
	var vs: PackedVector3Array = d["verts"]
	var n := vs.size()
	var zt := PackedByteArray()
	var zw := PackedFloat32Array()
	var phi := PackedFloat32Array()
	zt.resize(n)
	zw.resize(n)
	phi.resize(n)
	var wing := Vector2(0.019 * s, my + 0.022 * s)
	var corner := Vector2(0.031 * s, my - 0.004 * s)
	var ab := corner - wing
	var abn := Vector2(-ab.y, ab.x).normalized()
	var cc := Vector2(hx + 0.015 * s, ey)
	for i in n:
		var p := vs[i]
		var ax := absf(p.x)
		var q := Vector2(ax, p.y)
		var cand := [0.0, 0.0, 0.0, 0.0, 0.0]
		cand[0] = minf(0.040 * s - ax, minf(p.y - (by + 0.005 * s), by + 0.030 * s - p.y))             # forehead
		cand[1] = minf(0.012 * s - ax, minf(p.y - (by - 0.012 * s), by + 0.005 * s - p.y))             # glabella
		cand[2] = minf(minf(0.028 * s - q.distance_to(cc), ax - (hx + 0.008 * s)), 1.19 * (ax - cc.x + 0.004 * s) - absf(p.y - ey))                           # crow's feet (a fan of +-50 deg about the horizontal outward from the lateral canthus)
		var t := clampf((q - wing).dot(ab) / ab.length_squared(), 0.0, 1.0)
		cand[3] = 0.012 * s - q.distance_to(wing + ab * t)                                             # nasolabial
		cand[4] = minf(minf(ax - 0.005 * s, 0.020 * s - ax), minf(p.y - (ey - 0.020 * s), ey + 0.004 * s - p.y))   # bunny lines
		var bi := 0
		for k in 5:
			if float(cand[k]) > float(cand[bi]):
				bi = k
		var wgt := clampf(float(cand[bi]) / FEATHER, 0.0, 1.0)
		if wgt <= 0.0:
			continue
		zt[i] = bi + 1
		zw[i] = wgt
		match bi:
			0:
				phi[i] = p.y
			1:
				phi[i] = p.x
			2:
				phi[i] = atan2(p.y - cc.y, ax - cc.x) * 0.020 * s
			3:
				phi[i] = (q - wing).dot(abn)
			4:
				phi[i] = (ax + p.y) * 0.7071
	var lam := WAVE * s
	var phase := PackedFloat32Array()
	phase.resize(n)
	for i in n:
		if zt[i] != 0:
			var f := float(phi[i]) / lam
			phase[i] = f - floorf(f)
	var z := {"zt": zt, "zw": zw, "phi": phi, "phase": phase, "nrm": FaceGeo._normals(vs, d["tris"])}
	d["wr_zone"] = z
	return z


## the GDScript twin of KineWrinkleNative.prep + wrinkle (the strain part): 4 floats per vertex (line direction xyz, compression), zero outside the zones.
## Same arithmetic: unique neighbours in first-seen order with multiplicity m, the same inverse formula.
static func strain_gd(rest: PackedVector3Array, posed_v: PackedVector3Array, nrm: PackedVector3Array, tris: PackedInt32Array, zt: PackedByteArray) -> PackedFloat32Array:
	var n := rest.size()
	var out := PackedFloat32Array()
	out.resize(n * 4)
	var nbl := {}
	for t in tris.size() / 3:
		var v := [tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2]]
		for s in 3:
			var i: int = v[s]
			if zt[i] == 0:
				continue
			if not nbl.has(i):
				nbl[i] = [[], []]
			var L: Array = nbl[i]
			for o in [1, 2]:
				var j: int = v[(s + o) % 3]
				var at: int = (L[0] as Array).find(j)
				if at < 0:
					(L[0] as Array).append(j)
					(L[1] as Array).append(1)
				else:
					(L[1] as Array)[at] += 1
	for i in nbl:
		var L: Array = nbl[i]
		var nx := float(nrm[i].x)
		var ny := float(nrm[i].y)
		var nz := float(nrm[i].z)
		var rx := 1.0
		var ry := 0.0
		var rz := 0.0
		if absf(nx) >= 0.9:
			rx = 0.0
			ry = 1.0
		var ex := ry * nz - rz * ny
		var ey := rz * nx - rx * nz
		var ez := rx * ny - ry * nx
		var l := sqrt(ex * ex + ey * ey + ez * ez)
		if l < 1e-12:
			l = 1e-12
		ex /= l
		ey /= l
		ez /= l
		var e1x := ex
		var e1y := ey
		var e1z := ez
		var e2x := ny * ez - nz * ey
		var e2y := nz * ex - nx * ez
		var e2z := nx * ey - ny * ex
		var g00 := 0.0
		var g01 := 0.0
		var g02 := 0.0
		var g11 := 0.0
		var g12 := 0.0
		var g22 := 0.0
		var js: Array = L[0]
		var ms: Array = L[1]
		var ents := []
		for k in js.size():
			var j: int = js[k]
			var m := float(ms[k])
			var r0 := (float(rest[j].x) - float(rest[i].x)) * 1000.0
			var r1 := (float(rest[j].y) - float(rest[i].y)) * 1000.0
			var r2 := (float(rest[j].z) - float(rest[i].z)) * 1000.0
			var x := r0 * e1x + r1 * e1y + r2 * e1z
			var y := r0 * e2x + r1 * e2y + r2 * e2z
			var f0 := x * x
			var f1 := 2.0 * x * y
			var f2 := y * y
			g00 += m * (f0 * f0)
			g01 += m * (f0 * f1)
			g02 += m * (f0 * f2)
			g11 += m * (f1 * f1)
			g12 += m * (f1 * f2)
			g22 += m * (f2 * f2)
			ents.append([j, m * f0, m * f1, m * f2, r0 * r0 + r1 * r1 + r2 * r2])
		var reg := 1e-6
		var a00: float = g00 + reg
		var a01: float = g01
		var a02: float = g02
		var a11: float = g11 + reg
		var a12: float = g12
		var a22: float = g22 + reg
		var det := a00 * (a11 * a22 - a12 * a12) - a01 * (a01 * a22 - a12 * a02) + a02 * (a01 * a12 - a11 * a02)
		if absf(det) < 1e-18 or ents.is_empty():
			continue
		var b0 := 0.0
		var b1 := 0.0
		var b2 := 0.0
		for en in ents:
			var jn: int = en[0]
			var q0 := (float(posed_v[jn].x) - float(posed_v[i].x)) * 1000.0
			var q1 := (float(posed_v[jn].y) - float(posed_v[i].y)) * 1000.0
			var q2 := (float(posed_v[jn].z) - float(posed_v[i].z)) * 1000.0
			var gg := 0.5 * ((q0 * q0 + q1 * q1 + q2 * q2) - float(en[4]))
			b0 += gg * float(en[1])
			b1 += gg * float(en[2])
			b2 += gg * float(en[3])
		var i00 := (a11 * a22 - a12 * a12) / det
		var i01 := (a02 * a12 - a01 * a22) / det
		var i02 := (a01 * a12 - a02 * a11) / det
		var i11 := (a00 * a22 - a02 * a02) / det
		var i12 := (a01 * a02 - a00 * a12) / det
		var i22 := (a00 * a11 - a01 * a01) / det
		var ea := i00 * b0 + i01 * b1 + i02 * b2
		var eb := i01 * b0 + i11 * b1 + i12 * b2
		var ec := i02 * b0 + i12 * b1 + i22 * b2
		var mid := 0.5 * (ea + ec)
		var rad := sqrt(0.5 * (ea - ec) * 0.5 * (ea - ec) + eb * eb)
		var lmin := mid - rad
		var lmax := mid + rad
		var v1x := eb
		var v1y := lmax - ea
		var v2x := lmax - ec
		var v2y := eb
		var l1 := v1x * v1x + v1y * v1y
		var l2 := v2x * v2x + v2y * v2y
		var vx: float
		var vy: float
		if l1 >= l2:
			vx = v1x
			vy = v1y
		else:
			vx = v2x
			vy = v2y
		var ll := vx * vx + vy * vy
		if ll < 1e-30:
			vx = 1.0 if ea >= ec else 0.0
			vy = 0.0 if ea >= ec else 1.0
		else:
			ll = sqrt(ll)
			vx /= ll
			vy /= ll
		if vx < 0.0 or (vx == 0.0 and vy < 0.0):
			vx = -vx
			vy = -vy
		out[i * 4] = vx * e1x + vy * e2x
		out[i * 4 + 1] = vx * e1y + vy * e2y
		out[i * 4 + 2] = vx * e1z + vy * e2z
		out[i * 4 + 3] = -lmin if lmin < 0.0 else 0.0
	return out


## the wrinkle state of face state st: {"verts", "comp", "dir", "amp", "phase", "c0", "c1", "native"}
## The strain is measured on `posed + the orbital purse-string (AU6)`: the orbicularis oculi draws the skin around the eye toward the lateral
## canthus (a tangential squeeze: the crow's feet), which d["au"]["AU6"] (cheek lift + lid) does not move; that internal motion is NOT drawn
## as geometry (verts stay posed()), it only feeds the compression.
static func compute(d: Dictionary, st: Dictionary, force_gd: bool = false) -> Dictionary:
	var z := zones(d)
	var rest: PackedVector3Array = d["verts"]
	var au: Dictionary = st.get("au", {})
	var use_native := not force_gd and native_available()
	if use_native and _door == null:
		_door = load(DOOR)
	var ex := extra_au(d)
	var tab: Dictionary = d["au"]
	var vs: PackedVector3Array
	var fast := float(st.get("jaw_deg", 0.0)) == 0.0 and float(st.get("eye_pitch_deg", 0.0)) == 0.0 and float(au.get("AU45", 0.0)) == 0.0 and float(au.get("AU25", 0.0)) == 0.0
	if fast and use_native:
		var dl := []
		var wt := PackedFloat32Array()
		for k in au:
			var w := float(au[k])
			if w != 0.0 and tab.has(k):
				dl.append(tab[k])
				wt.append(w)
		for k in EXTRA_AUS:
			var w2 := float(au.get(k, 0.0))
			if w2 != 0.0:
				dl.append(ex[k])
				wt.append(w2)
		vs = _door.blend(rest, dl, wt)
	else:
		vs = posed(d, st)
	var w6 := float(au.get("AU6", 0.0))
	var s := float((d["anchors"] as Dictionary)["top"]) / 1.754
	var par := PackedFloat64Array([WAVE * s, C0, C1])
	par.append_array(gates(au))
	par.append(w6)
	var r: Dictionary
	if use_native:
		if not z.has("prep"):
			z["prep"] = _door.prep(rest, z["nrm"], d["tris"], z["zt"])
		r = _door.wrinkle(z["prep"], vs, ex["AU6p"], z["zt"], z["zw"], par)
	else:
		r = _wrinkle_gd(rest, _add(vs, ex["AU6p"], w6) if w6 != 0.0 else vs, z, d["tris"], par)
	r["phase"] = z["phase"]
	r["verts"] = vs
	r["native"] = use_native
	return r


static func _add(v: PackedVector3Array, dl: PackedVector3Array, w: float) -> PackedVector3Array:
	var o := v.duplicate()
	for i in o.size():
		o[i] += dl[i] * w
	return o


static func _wrinkle_gd(rest: PackedVector3Array, sp: PackedVector3Array, z: Dictionary, tris: PackedInt32Array, par: PackedFloat64Array) -> Dictionary:
	var sa := strain_gd(rest, sp, z["nrm"], tris, z["zt"])
	var n := rest.size()
	var comp := PackedFloat32Array()
	var dir := PackedVector3Array()
	var amp := PackedFloat32Array()
	var c0 := PackedFloat32Array()
	comp.resize(n)
	dir.resize(n)
	amp.resize(n)
	c0.resize(n * 4)
	var zt: PackedByteArray = z["zt"]
	var zw: PackedFloat32Array = z["zw"]
	var phi: PackedFloat32Array = z["phi"]
	for i in n:
		if zt[i] == 0:
			continue
		comp[i] = sa[i * 4 + 3]
		dir[i] = Vector3(sa[i * 4], sa[i * 4 + 1], sa[i * 4 + 2])
		amp[i] = _ss(par[1], par[2], comp[i]) * zw[i] * par[2 + zt[i]]
		c0[i * 4] = sa[i * 4]
		c0[i * 4 + 1] = sa[i * 4 + 1]
		c0[i * 4 + 2] = sa[i * 4 + 2]
		c0[i * 4 + 3] = amp[i]
	return {"dir": dir, "comp": comp, "amp": amp, "c0": c0}


## the CPU twin of the shader: n' - n at every vertex (n = the posed mask normal)
static func normal_delta(d: Dictionary, w: Dictionary) -> PackedVector3Array:
	var vs: PackedVector3Array = w["verts"]
	var nm := FaceGeo._normals(vs, d["tris"])
	var amp: PackedFloat32Array = w["amp"]
	var dir: PackedVector3Array = w["dir"]
	var ph: PackedFloat32Array = w["phase"]
	var out := PackedVector3Array()
	out.resize(vs.size())
	var k := DEPTH * TAU / WAVE
	for i in vs.size():
		if amp[i] <= 0.0:
			continue
		var pp := nm[i].cross(dir[i])
		if pp.length() < 1.0e-5:
			continue
		var n2 := (nm[i] - pp.normalized() * (k * amp[i] * sin(TAU * ph[i]))).normalized()
		out[i] = n2 - nm[i]
	return out


static func state_hash(w: Dictionary) -> int:
	return [hash((w["amp"] as PackedFloat32Array).to_byte_array()), hash((w["dir"] as PackedVector3Array).to_byte_array()), hash((w["phase"] as PackedFloat32Array).to_byte_array())].hash()


## FaceGeo.mask_mesh + the wrinkle attributes: CUSTOM0 = (line direction xyz, amplitude), CUSTOM1 = (phase, 0, 0, 0)
static func mask_mesh(d: Dictionary, verts: PackedVector3Array, w: Dictionary, skin: Color = FaceGeo.SKIN) -> ArrayMesh:
	var base := FaceGeo.mask_mesh(d, verts, skin)
	var ar := base.surface_get_arrays(0)
	ar[Mesh.ARRAY_CUSTOM0] = w["c0"]
	ar[Mesh.ARRAY_CUSTOM1] = w["phase"]
	var am := ArrayMesh.new()
	var fl := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar, [], {}, fl)
	return am
