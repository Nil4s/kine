class_name WeaponParts
extends RefCounted
## B28 WEAPON PARTS ON A MODEL (docs/ROADMAP_400.md). A modelled weapon's faces are tagged grip / guard / blade / pommel (the
## face channel ATTR, 1..4, 0 = untagged; a normal A09 channel, so one KMeshUndo step per tag). analyse() cuts each part out as its own
## mesh, takes its volume with KMeshMeasure.volume (closed, manifold, outward only: an open part is REFUSED with the reason, never
## given a wrong volume), mass = volume x the material's density (KMeshMeasure.MATERIALS, which carries each density's source), and the
## centre of mass from the solid's volume centroid (signed tetrahedra, 64-bit sums). join_book() writes the result into the grip book
## (GripBook.record, kind "model_<name>") as an entry with the weapon's mass, centre of mass, the parts, and the grip axis = the grip
## part's long axis (principal axis of its verts), signed to point from the pommel toward the blade. Hands are not recorded here.
## Mesh space throughout (metres); the grip book entry keeps the same frame.

const ATTR := "wpart"
const ROLES := ["grip", "guard", "blade", "pommel"]
const DEFAULT_MAT := {"grip": "oak", "guard": "steel", "blade": "steel", "pommel": "steel"}
const KIND_PREFIX := "model_"
const ENTRY := "parts"
static var model_name := "sword"   # the book kind the command writes: model_<this>
static var mats := {}   # L135: role -> material name picked in the panel; a missing role uses DEFAULT_MAT


static func id_of(role: String) -> int:
	return ROLES.find(role) + 1


static func ensure(m: KMesh) -> bool:
	if m.has_attr(ATTR):
		return true
	return m.add_attr(ATTR, KMesh.AD_FACE, TYPE_FLOAT, 0.0)


## the faces tagged `role`
static func faces_of(m: KMesh, role: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if m == null or not m.has_attr(ATTR):
		return out
	var d: PackedFloat32Array = m.attr_data(ATTR)
	var id := id_of(role)
	for fi in d.size():
		if int(d[fi]) == id:
			out.append(fi)
	return out


## tag `faces` as `role` (the caller brackets the undo step); returns how many
static func tag(m: KMesh, faces, role: String) -> int:
	if id_of(role) <= 0 or not ensure(m):
		return 0
	var d: PackedFloat32Array = m.attr_data(ATTR).duplicate()
	var n := 0
	for fi in faces:
		if int(fi) >= 0 and int(fi) < d.size():
			d[int(fi)] = float(id_of(role))
			n += 1
	m.set_attr_data(ATTR, d)
	return n


## the faces `fl` of m as a mesh of their own (verts renumbered)
static func cut(m: KMesh, fl: PackedInt32Array) -> KMesh:
	var remap := {}
	var vs := PackedVector3Array()
	var fs: Array = []
	for fi in fl:
		var nf := PackedInt32Array()
		for v in (m.faces[fi] as PackedInt32Array):
			if not remap.has(v):
				remap[v] = vs.size()
				vs.append(m.verts[v])
			nf.append(remap[v])
		fs.append(nf)
	return KMesh.new().from_arrays(vs, fs)


## volume centroid of a closed mesh (signed tetrahedra from the first vert, 64-bit sums)
static func centroid(m: KMesh) -> Vector3:
	var o: Vector3 = m.verts[0]
	var vt := 0.0
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	for f in m.faces:
		var ff: PackedInt32Array = f
		var a: Vector3 = m.verts[ff[0]]
		for i in range(1, ff.size() - 1):
			var b: Vector3 = m.verts[ff[i]]
			var c: Vector3 = m.verts[ff[i + 1]]
			var ax := float(a.x) - o.x
			var ay := float(a.y) - o.y
			var az := float(a.z) - o.z
			var bx := float(b.x) - o.x
			var by := float(b.y) - o.y
			var bz := float(b.z) - o.z
			var qx := float(c.x) - o.x
			var qy := float(c.y) - o.y
			var qz := float(c.z) - o.z
			var v := (ax * (by * qz - bz * qy) + ay * (bz * qx - bx * qz) + az * (bx * qy - by * qx)) / 6.0
			vt += v
			cx += v * (ax + bx + qx) / 4.0
			cy += v * (ay + by + qy) / 4.0
			cz += v * (az + bz + qz) / 4.0
	if vt == 0.0:
		return o
	return Vector3(o.x + cx / vt, o.y + cy / vt, o.z + cz / vt)


## the long axis of a point cloud (unit; sign arbitrary): power iteration on its covariance
static func long_axis(m: KMesh) -> Vector3:
	var n := m.verts.size()
	var mean := Vector3.ZERO
	for v in m.verts:
		mean += v
	mean /= float(n)
	var c := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # xx xy xz yy yz zz
	for v in m.verts:
		var d: Vector3 = v - mean
		c[0] += d.x * d.x
		c[1] += d.x * d.y
		c[2] += d.x * d.z
		c[3] += d.y * d.y
		c[4] += d.y * d.z
		c[5] += d.z * d.z
	var u := Vector3(1, 0.7, 0.3).normalized()
	for _i in 200:
		var w := Vector3(c[0] * u.x + c[1] * u.y + c[2] * u.z, c[1] * u.x + c[3] * u.y + c[4] * u.z, c[2] * u.x + c[4] * u.y + c[5] * u.z)
		if w.length() < 1e-30:
			break
		u = w.normalized()
	return u


## {"ok": true, "parts": {role: {volume_m3, mass_kg, com, material, kg_m3, src, faces}}, "mass_kg", "com", "grip_axis"} or
## {"ok": false, "why": the reason}. `mats` overrides DEFAULT_MAT per role
static func analyse(m: KMesh, mats := {}) -> Dictionary:
	var parts := {}
	var mt := 0.0
	var mc := Vector3.ZERO
	var meshes := {}
	for role in ROLES:
		var fl := faces_of(m, role)
		if fl.is_empty():
			return {"ok": false, "why": "no faces are tagged as the %s: select them and run Model: tag as %s" % [role, role]}
		var pm := cut(m, fl)
		var vr := KMeshMeasure.volume(pm)
		if not vr["ok"]:
			return {"ok": false, "why": "the %s is refused: %s" % [role, vr["why"]]}
		var mat := String(mats.get(role, DEFAULT_MAT[role]))
		if not KMeshMeasure.MATERIALS.has(mat):
			return {"ok": false, "why": "the %s has an unknown material '%s' (known: %s)" % [role, mat, ", ".join(KMeshMeasure.MATERIALS.keys())]}
		var rho := float(KMeshMeasure.MATERIALS[mat]["kg_m3"])
		var kg := KMeshMeasure.mass(float(vr["m3"]), rho)
		var com := centroid(pm)
		parts[role] = {"volume_m3": vr["m3"], "mass_kg": kg, "com": com, "material": mat, "kg_m3": rho,
			"src": String(KMeshMeasure.MATERIALS[mat]["src"]), "faces": fl.size()}
		meshes[role] = pm
		mt += kg
		mc += com * kg
	var com_all := mc / mt
	var ax := long_axis(meshes["grip"])
	if ax.dot((parts["blade"]["com"] as Vector3) - (parts["pommel"]["com"] as Vector3)) < 0.0:
		ax = -ax
	return {"ok": true, "parts": parts, "mass_kg": mt, "com": com_all, "grip_axis": ax}


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## analyse and put the weapon in the grip book; {"ok": false, "why"} (and the book untouched) when a part is refused
static func join_book(m: KMesh, wname: String, mats := {}) -> Dictionary:
	var r := analyse(m, mats)
	if not r["ok"]:
		return r
	var ps := {}
	for role in r["parts"]:
		var p: Dictionary = (r["parts"][role] as Dictionary).duplicate()
		p["com"] = _arr(p["com"])
		ps[role] = p
	var e := {"name": ENTRY, "label": "weapon parts of the model", "ref": "B28: mass = closed-mesh volume x density; densities from KMeshMeasure.MATERIALS",
		"hands": [], "mass_kg": r["mass_kg"], "com": _arr(r["com"]), "grip_axis": _arr(r["grip_axis"]), "parts": ps}
	r["kind"] = KIND_PREFIX + wname
	r["file"] = GripBook.record(r["kind"], e)
	return r
