class_name BodySliders
extends RefCounted
## ROADMAP_400 C22: fat / muscle / bone sliders as region brushes on a KMesh body (tests/bodysliders_test.gd).
## A stroke works on a bone's REGION (the verts KMeshBody labels with that bone) and asks for an AMOUNT: the change of the
## region's girth in metres at mid-bone (perimeter of the cross-section by the plane square to the bone, half way along it).
##   lean  reduces subcutaneous volume: girth - amount        bulk  grows muscle volume: girth + amount
##   soft  relaxes the surface: Taubin smoothing (a pull toward the mean of the neighbours, then a push back, so the limb
##         does not shrink as plain Laplacian smoothing does on a coarse tube); amount unused
## Verts move along their own normal (square to the bone), scaled by a taper that is 0 over the first/last 10 % of the bone
## and 1 from 30 % to 70 %: the joint rings (shoulder, elbow) stay where they are. A bulk/lean stroke is closed-loop: the
## girth is measured and the scale corrected (up to 3 passes) until the change is within 0.5 % of the amount.
## BOUNDS: girth is clamped to mean +- 3 SD of the ANSUR II (Gordon et al. 2014, NATICK/TR-15/007) "biceps circumference,
## flexed" for the sex. The numbers below are UNVERIFIED (from memory; not checked against the report, no DOI/PMID). Not
## scaled by stature or mass; only the upper arm has a table so far (other regions are unbounded and say so).
## Pure (no nodes). stroke() edits in place; stroke_undoable() brackets it as ONE KMeshUndo step.

const BRUSHES := ["lean", "bulk", "soft"]
## metres: ANSUR II biceps circumference flexed, mean and SD (UNVERIFIED, from memory)
const ANSUR := {"upperarm": {"male": [0.339, 0.032], "female": [0.296, 0.030]}}
const SOFT_PASSES := 3
const SOFT_LAMBDA := 0.5
const SOFT_MU := -0.53


static func _kind(region: String) -> String:
	return region.split("_")[0]


## {"min","max"} girth in metres (mean -/+ 3 SD) for a region and sex; {} when the region has no table
static func bound(region: String, sex := "male") -> Dictionary:
	var t: Dictionary = ANSUR.get(_kind(region), {})
	if t.is_empty():
		return {}
	var ms: Array = t[sex if t.has(sex) else "male"]
	return {"min": float(ms[0]) - 3.0 * float(ms[1]), "max": float(ms[0]) + 3.0 * float(ms[1]), "mean": float(ms[0]), "sd": float(ms[1])}


static func _seg(sk: Skeleton3D, bone: String) -> Dictionary:
	for s in KMeshBody.segments_from_skeleton(sk, true):
		if s["bone"] == bone:
			return s
	return {}


## the verts KMeshBody labels with `bone`
static func region_verts(mesh: KMesh, sk: Skeleton3D, bone: String) -> PackedInt32Array:
	KMeshBody.refresh(mesh, KMeshBody.segments_from_skeleton(sk, true))
	var bi := KMeshBody.BONES.find(bone)
	var ch: PackedFloat32Array = mesh.attr_data(KMeshBody.CH_BONE)
	var out := PackedInt32Array()
	for v in ch.size():
		if int(ch[v]) == bi:
			out.append(v)
	return out


## the taper along the bone: t in 0..1 from the bone's start
static func taper(t: float) -> float:
	return smoothstep(0.1, 0.3, t) * smoothstep(0.1, 0.3, 1.0 - t)


## perimeter (m) of the region's faces cut by the plane square to the bone, half way along it
static func girth(mesh: KMesh, sk: Skeleton3D, bone: String) -> float:
	var seg := _seg(sk, bone)
	if seg.is_empty():
		return 0.0
	var ids := region_verts(mesh, sk, bone)
	return _girth(mesh, ids, seg["a"], seg["b"])


static func _girth(mesh: KMesh, ids: PackedInt32Array, a: Vector3, b: Vector3) -> float:
	var inr := PackedByteArray()
	inr.resize(mesh.verts.size())
	for v in ids:
		inr[v] = 1
	var u := (b - a).normalized()
	var d0 := u.dot((a + b) * 0.5)
	var vs := mesh.verts
	var total := 0.0
	for f in mesh.faces:
		var n: int = f.size()
		var ok := true
		for i in n:
			if inr[f[i]] == 0:
				ok = false
				break
		if not ok:
			continue
		for i in range(1, n - 1):
			var tri := [f[0], f[i], f[i + 1]]
			var pts := []
			for e in 3:
				var p: Vector3 = vs[tri[e]]
				var q: Vector3 = vs[tri[(e + 1) % 3]]
				var sp := u.dot(p) - d0
				var sq := u.dot(q) - d0
				if (sp >= 0.0) != (sq >= 0.0):
					pts.append(p.lerp(q, sp / (sp - sq)))
			if pts.size() == 2:
				total += (pts[0] as Vector3).distance_to(pts[1])
	return total


## variance of the curvature proxy |mean of neighbours - vert| over ids
static func curvature_variance(mesh: KMesh, ids: PackedInt32Array) -> float:
	var cs := PackedFloat64Array()
	for v in ids:
		var nb := mesh.vert_neighbors(v)
		if nb.is_empty():
			continue
		var m := Vector3.ZERO
		for w in nb:
			m += mesh.verts[w]
		cs.append((m / nb.size() - mesh.verts[v]).length())
	if cs.size() < 2:
		return 0.0
	var mu := 0.0
	for c in cs:
		mu += c
	mu /= cs.size()
	var s := 0.0
	for c in cs:
		s += (c - mu) * (c - mu)
	return s / cs.size()


## one stroke, in place. -> {"ok", "moved", "clamped", "message", "girth_before", "girth_after", "amount"}
static func stroke(mesh: KMesh, sk: Skeleton3D, region: String, brush: String, amount: float, sex := "male") -> Dictionary:
	var seg := _seg(sk, region)
	var res := {"ok": false, "moved": 0, "clamped": false, "message": "", "girth_before": 0.0, "girth_after": 0.0, "amount": 0.0}
	if seg.is_empty() or not BRUSHES.has(brush):
		res["message"] = "unknown region or brush"
		return res
	var a: Vector3 = seg["a"]
	var b: Vector3 = seg["b"]
	var u := (b - a).normalized()
	var len := (b - a).length()
	var ids := region_verts(mesh, sk, region)
	var g0 := _girth(mesh, ids, a, b)
	res["girth_before"] = g0
	res["girth_after"] = g0
	res["ok"] = true
	if brush == "soft":
		_soft(mesh, ids, a, u, len)
		res["moved"] = ids.size()
		res["girth_after"] = _girth(mesh, ids, a, b)
		return res
	var want := absf(amount) * (1.0 if brush == "bulk" else -1.0)
	var bd := bound(region, sex)
	if not bd.is_empty():
		var tgt := g0 + want
		if tgt > float(bd["max"]) or tgt < float(bd["min"]):
			var lim := minf(maxf(tgt, float(bd["min"])), float(bd["max"]))
			want = lim - g0
			res["clamped"] = true
			res["message"] = "%s stopped at the ANSUR II limit: %s girth %.0f mm (%s mean %.0f %s 3 SD of %.0f mm; Gordon 2014, UNVERIFIED table)" % [
				brush, _kind(region), lim * 1000.0, sex, float(bd["mean"]) * 1000.0, "+" if tgt > g0 else "-", float(bd["sd"]) * 1000.0]
	res["amount"] = want
	if absf(want) < 1e-6:
		return res
	var orig := mesh.verts.duplicate()
	var dirs := PackedVector3Array()
	dirs.resize(ids.size())
	var nrm := mesh.vert_normals
	for i in ids.size():
		var v := ids[i]
		var t := (orig[v] - a).dot(u) / len
		var nn: Vector3 = nrm[v]
		nn -= u * nn.dot(u)
		dirs[i] = nn.normalized() * taper(t) if nn.length() > 1e-6 else Vector3.ZERO
	var k := want / TAU
	for _it in 3:
		for i in ids.size():
			mesh.verts[ids[i]] = orig[ids[i]] + dirs[i] * k
		var dg := _girth(mesh, ids, a, b) - g0
		if absf(dg - want) <= 0.005 * absf(want) or absf(dg) < 1e-9:
			break
		k *= want / dg
	res["moved"] = ids.size()
	res["girth_after"] = _girth(mesh, ids, a, b)
	return res


static func _soft(mesh: KMesh, ids: PackedInt32Array, a: Vector3, u: Vector3, len: float) -> void:
	var nbs := []
	var w := PackedFloat32Array()
	for v in ids:
		nbs.append(mesh.vert_neighbors(v))
		w.append(taper((mesh.verts[v] - a).dot(u) / len))
	for _p in SOFT_PASSES * 2:
		var lam := SOFT_LAMBDA if _p % 2 == 0 else SOFT_MU
		var nw := PackedVector3Array()
		nw.resize(ids.size())
		for i in ids.size():
			var nb: PackedInt32Array = nbs[i]
			var p: Vector3 = mesh.verts[ids[i]]
			if nb.is_empty() or w[i] <= 0.0:
				nw[i] = p
				continue
			var m := Vector3.ZERO
			for q in nb:
				m += mesh.verts[q]
			nw[i] = p + (m / nb.size() - p) * (lam * w[i])
		for i in ids.size():
			mesh.verts[ids[i]] = nw[i]


## stroke() as ONE undo step (nothing moved = no step)
static func stroke_undoable(undo: KMeshUndo, mesh: KMesh, sk: Skeleton3D, region: String, brush: String, amount: float, sex := "male") -> Dictionary:
	undo.begin(mesh)
	var r := stroke(mesh, sk, region, brush, amount, sex)
	mesh.rebuild()
	undo.commit("%s %s" % [brush, region])
	return r
