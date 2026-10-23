class_name SculptPose
extends RefCounted
## C19 (docs/ROADMAP_400.md): SCULPT IN POSE. The body is sculpted where the animation has it (any frame, the elbow bent,
## the knee up) and the stroke lands in the REST mesh, the one "Model: apply the body mesh" writes to the fighter.
## A20 (the pose-aware edit, the rest <-> pose map) was not built when this was: the minimal piece of it lives here
## (affine_of / to_rest), pure math on the KMesh, so A20 can take it over.
##
## THE MAP. For one vertex with weights w_i on binds whose skinning matrices are B_i (bone global pose * bind pose, the
## matrices the GPU skins by, DqSkin.bind_mats), the skinning is AFFINE in the rest position r:
##   LBS:  p = M r,  M = sum_i w_i B_i                                            (A = M.basis, c = M.origin)
##   DQS:  p = ws (R_b S r + 2 t_b),  b = the normalised blend of the dual quaternions, S the blended scale part,
##         ws = the weight sum (dq_skin.gd's header: what DqSkin.skin_one evaluates)  (A = ws R_b S, c = 2 ws t_b)
##   the scene's blend k mixes them: A = (1 - k) A_lbs + k A_dqs,  c likewise
## so p = A r + c, and a posed displacement d (a dab moved the posed vertex from p to p + d) is the rest displacement
## A^-1 d. The rest vertex is set to A^-1 (p' - c): re-skinning it at that pose gives p' to float precision. The weights
## are the body's "skin:<bone>" channels as the fighter holds them (BaseBody.canon(fit4)), so the preview skins what the GPU
## draws; a vertex with no weight takes its nearest bone (BaseBody.build's rule).
##
## THE TWO MESHES. `rest` is the model preview's body KMesh (G01) and stays the truth; `posed` is a copy whose positions
## are rest skinned at the current pose (topology and every channel shared by value: mask, face sets, UVs, weights). The
## sculpt UI strokes `posed` with every brush unchanged (scripts/kmesh_sculpt.gd), so the mask and the face-set freeze
## work as they do on the sphere; at the end of the stroke map_back() writes the moved posed vertices to rest, and the
## channels the stroke painted (mask, face sets). A vertex the stroke did not move is not written: bit-exact in rest.
##
## AS A CORRECTIVE (optional): the rest positions stay bit-exact and the displacement goes into a SHAPE KEY (A13,
## KMeshShapes) tied to the pose, driven by the corrective system's own rule (scripts/corrective.gd, ROADMAP 71):
##   key "corr_<distal bone>_<bend deg>",  value = drive(theta) / drive(theta0),  drive = Corrective.drive_of
##   (smoothstep 0..140 deg of the joint's bend), clamped 0..1 by the key: the full shape at the sculpted bend, faded to
##   nothing at straight, held at 1 past it. The joint is the one of Corrective.JOINTS that is bent now and whose two
##   bones (and the distal one's children: the hand, the foot, the twist bones) carry most of the stroke.
##   The key stores the rest-space delta / its value at this pose, so at this pose the shape is exactly the stroke.
##   The preview skins rest + sum(value * delta) of these keys; the fighter's own corrective pass does not read them yet.

const PREFIX := "corr_"
const DET_MIN := 1e-9   # a blended matrix this near singular is not inverted (the vertex keeps its rest)

var rest: KMesh
var posed: KMesh
var skin: Skin
var skel: Skeleton3D
var k := 0.0                    # the scene's dq_skin blend (0 LBS, 1 DQS)
var corrective := false         # strokes go into a corrective shape key instead of the rest positions
var inputs := {}                # KMeshShapes.body_inputs of the current pose (the drivers read <bone>_bend)
var mats := []                  # the bind matrices of the current pose
var bo := PackedInt32Array()    # 4 binds per rest vertex
var w := PackedFloat32Array()   # their weights (canon: what the GPU holds)
var eff := PackedVector3Array() # rest + the corrective keys at this pose: what `posed` was skinned from
var last_key := ""              # the corrective key the last stroke wrote ("" = rest)
var last_error := ""
var singular := 0               # vertices the last map_back could not invert (left as they were)
var _before := PackedVector3Array()


## the rest mesh, its skin and the skeleton; the weights are read once (a sculpt does not change them)
func setup(r: KMesh, sn: Skin, sk: Skeleton3D) -> SculptPose:
	rest = r
	skin = sn
	skel = sk
	var ws := BaseBody.weights_of(r, sn)
	bo.resize(ws.size() * 4)
	w.resize(ws.size() * 4)
	for v in ws.size():
		var d := BaseBody.canon(BaseBody.fit4(ws[v]))
		if d.is_empty():
			d = {BaseBody.nearest_bind(sn, sk, r.verts[v]) if sn != null and sk != null else 0: 1.0}
		var ks := d.keys()
		ks.sort()
		for q in 4:
			bo[v * 4 + q] = int(ks[q]) if q < ks.size() else 0
			w[v * 4 + q] = float(d[ks[q]]) if q < ks.size() else 0.0
	posed = KMesh.new().from_arrays(r.verts, r.faces)
	posed.attrs = r.attr_snapshot()
	return self


## the pose to show: the skeleton as it stands now (call after the frame put the pose on it)
func set_pose(dq_k: float, body_inputs := {}) -> void:
	k = dq_k
	inputs = body_inputs
	mats = DqSkin.bind_mats(skel, skin)


## the corrective keys' values at this pose (their drivers, the corrective rule) and rest with them added
func eff_now() -> PackedVector3Array:
	var out := rest.verts
	var mine := []
	for key in KMeshShapes.keys(rest):
		if String(key["name"]).begins_with(PREFIX):
			mine.append(key)
	if mine.is_empty():
		return out
	KMeshShapes.drive(rest, inputs)
	out = out.duplicate()
	for key in mine:
		var val := clampf(float(key["value"]), float(key["min"]), float(key["max"]))
		if val == 0.0 or bool(key["mute"]):
			continue
		var d: PackedVector3Array = key["delta"]
		for v in out.size():
			out[v] += d[v] * val
	return out


## the posed mesh skinned again from rest (a new frame, an undo); its channels copied from rest
func reskin() -> void:
	eff = eff_now()
	posed.verts = DqSkin.skin_surface(eff, bo, w, mats, k)
	posed.attrs = rest.attr_snapshot()
	posed._compute_normals()


## THE MAP of one vertex at this pose: p = A r + c, as a Transform3D (basis A, origin c)
func affine_of(i: int, dq: Array) -> Transform3D:
	var bx := Vector3.ZERO
	var by := Vector3.ZERO
	var bz := Vector3.ZERO
	var bt := Vector3.ZERO
	var piv := -1
	var pw := -1.0
	for q in 4:
		if w[i * 4 + q] > pw:
			pw = w[i * 4 + q]
			piv = bo[i * 4 + q]
	var rp: Quaternion = dq[piv][0]
	var br := Quaternion(0, 0, 0, 0)
	var bd := Quaternion(0, 0, 0, 0)
	var sx := Vector3.ZERO
	var sy := Vector3.ZERO
	var sz := Vector3.ZERO
	var ws := 0.0
	var rigid := true
	for q in 4:
		var x := w[i * 4 + q]
		if x <= 0.0:
			continue
		ws += x
		var b := bo[i * 4 + q]
		var M: Transform3D = mats[b]
		bx += M.basis.x * x
		by += M.basis.y * x
		bz += M.basis.z * x
		bt += M.origin * x
		var e: Array = dq[b]
		var s := x if (e[0] as Quaternion).dot(rp) >= 0.0 else -x
		br += (e[0] as Quaternion) * s
		bd += (e[1] as Quaternion) * s
		var S: Basis = e[2]
		sx += S.x * x
		sy += S.y * x
		sz += S.z * x
		rigid = rigid and bool(e[3])
	var L := Transform3D(Basis(bx, by, bz), bt)
	var n := br.length()
	if k <= 0.0 or n < 1e-9:
		return L
	br = br / n
	bd = bd / n
	var SB := Basis.IDENTITY if rigid else Basis(sx / ws, sy / ws, sz / ws)
	var tq := bd * br.inverse()
	var D := Transform3D(Basis(br) * SB * ws, Vector3(tq.x, tq.y, tq.z) * 2.0 * ws)
	if k >= 1.0:
		return D
	return Transform3D(Basis(L.basis.x.lerp(D.basis.x, k), L.basis.y.lerp(D.basis.y, k), L.basis.z.lerp(D.basis.z, k)), L.origin.lerp(D.origin, k))


## the rest position that skins to posed position p at this pose (null when the map is singular there)
func to_rest(i: int, p: Vector3, dq: Array):
	var T := affine_of(i, dq)
	if absf(T.basis.determinant()) < DET_MIN:
		return null
	return T.basis.inverse() * (p - T.origin)


## a stroke (or any edit of the posed mesh) begins: remember where the posed vertices were
func stroke_begin() -> void:
	_before = posed.verts.duplicate()


## the stroke ends: the moved posed vertices go to rest (or into the corrective key), the painted channels too.
## -> the vertices written (0 also when the corrective mode had no bent joint: the posed mesh is put back)
func map_back() -> int:
	last_error = ""
	last_key = ""
	singular = 0
	var idx := PackedInt32Array()
	var pv := posed.verts
	if _before.size() == pv.size():
		for i in pv.size():
			if pv[i] != _before[i]:
				idx.append(i)
	for nm in posed.attrs:   # the mask / face sets the stroke painted (channels only the posed copy has get added)
		var pr: Dictionary = posed.attrs[nm]
		if not rest.attrs.has(nm) or rest.attrs[nm]["data"] != pr["data"]:
			rest.attrs[nm] = {"domain": pr["domain"], "type": pr["type"], "default": pr["default"], "data": pr["data"].duplicate()}
	if idx.is_empty():
		return 0
	var dq := DqSkin.dqs_of(mats)
	var nr := PackedVector3Array()
	nr.resize(idx.size())
	var ok := PackedByteArray()
	ok.resize(idx.size())
	for j in idx.size():
		var r = to_rest(idx[j], pv[idx[j]], dq)
		if r == null:
			singular += 1
			continue
		nr[j] = r
		ok[j] = 1
	if not corrective:
		var rv := rest.verts
		rest.verts = PackedVector3Array()   # one owner while writing
		for j in idx.size():
			if ok[j]:   # the corrective keys on at this pose stay keys: only the stroke's own change goes to rest
				var i := idx[j]
				rv[i] = nr[j] if eff[i] == rv[i] else rv[i] + (nr[j] - eff[i])
		rest.verts = rv
		rest._compute_normals()
		_put_back(idx, ok)
		return idx.size() - singular
	var jt := joint_of(idx)
	if jt.is_empty():
		last_error = "no elbow or knee is bent at this frame: a corrective is tied to a bend. Bend the joint, or sculpt the rest (corrective off)"
		for j in idx.size():
			ok[j] = 0
		_put_back(idx, ok)
		return 0
	var key := ensure_key(jt)
	var val := clampf(float(key["value"]), float(key["min"]), float(key["max"]))
	var d: PackedVector3Array = key["delta"]
	for j in idx.size():
		if ok[j]:
			d[idx[j]] += (nr[j] - eff[idx[j]]) / val
	key["delta"] = d
	last_key = String(key["name"])
	_put_back(idx, ok)
	return idx.size() - singular


## vertices that could not be mapped go back to where they were in the posed mesh
func _put_back(idx: PackedInt32Array, ok: PackedByteArray) -> void:
	var any := false
	var pv := posed.verts
	for j in idx.size():
		if not ok[j]:
			pv[idx[j]] = _before[idx[j]]
			any = true
	if any:
		posed.verts = pv
		posed._compute_normals()


## the joint the corrective is tied to: of Corrective.JOINTS bent now, the one whose bones carry most of the moved
## vertices' weight (the distal bone's children count as it). [key, distal, proximal, bend deg] or []
func joint_of(idx: PackedInt32Array) -> Array:
	var best := []
	var bw := 0.0
	for jt in Corrective.JOINTS:
		var bend := float(inputs.get(String(jt[1]) + "_bend", 0.0))
		if Corrective.drive_of(bend) <= 0.0:
			continue
		var dist := skel.find_bone(jt[1])
		var prox := skel.find_bone(jt[2])
		var mine := {}
		for b in skin.get_bind_count():
			var c := SkinPaint.bind_bone(skin, skel, b)
			if c == prox:
				mine[b] = true
				continue
			while c >= 0 and c != dist:
				c = skel.get_bone_parent(c)
			if c == dist:
				mine[b] = true
		var s := 0.0
		for i in idx:
			for q in 4:
				if mine.has(bo[i * 4 + q]):
					s += w[i * 4 + q]
		if s > bw:
			bw = s
			best = [jt[0], jt[1], jt[2], bend]
	return best


## the corrective key of joint jt at its bend now: made (zero delta, driven by the corrective rule) the first time
func ensure_key(jt: Array) -> Dictionary:
	var nm := "%s%s_%d" % [PREFIX, jt[1], roundi(float(jt[3]))]
	var i := KMeshShapes.find(rest, nm)
	if i < 0:
		var b0 := float(jt[3])
		i = KMeshShapes.add_key(rest, nm, PackedVector3Array(), KMeshShapes.BASIS, 1.0)
		KMeshShapes.put_driver(rest, {"key": nm, "expr": "smoothstep(0.0, %s, %s_bend) / %s" % [var_to_str(Corrective.FULL_DEG), jt[1], var_to_str(Corrective.drive_of(b0))]})
		KMeshShapes.drive(rest, inputs)
	return KMeshShapes.keys(rest)[i]


## the key's value at a bend (the corrective rule): what the driver gives
static func weight_at(bend: float, bend0: float) -> float:
	return clampf(Corrective.drive_of(bend) / maxf(Corrective.drive_of(bend0), 1e-12), 0.0, 1.0)


## THE UNDO of a pose sculpt: the sculpt UI brackets every stroke (and mask / face-set op) on the POSED mesh with
## begin / commit; the step is kept on the REST mesh (one step per stroke), and an undo / redo skins the posed copy again
class PoseUndo extends KMeshUndo:
	var sp: SculptPose

	func _init(s: SculptPose) -> void:
		sp = s

	func begin(_m: KMesh) -> void:
		sp.stroke_begin()
		super.begin(sp.rest)

	func commit(label := "edit") -> Dictionary:
		sp.map_back()
		var st := super.commit(label + (" (in pose, as a corrective)" if sp.corrective else " (in pose)"))
		if sp.corrective:
			sp.reskin()   # the posed copy shows exactly what the key gives
		return st

	func undo() -> String:
		var lb := super.undo()
		sp.reskin()
		return lb

	func redo() -> String:
		var lb := super.redo()
		sp.reskin()
		return lb
