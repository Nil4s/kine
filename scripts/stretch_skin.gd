## stretch_skin.gd - THE SKIN FOLLOWS THE STRETCH (L33; builds on L28 / PR #245: Body.stretch, Body.stretch_cross, spline chains).
## Body.stretch {k: s} makes the bone that ENDS at joint k (parent[k]) s times longer and Body.stretch_cross {k: c} is its cross scale
## (volume mode: c = 1/sqrt(s)). A bone b = parent[k] therefore carries the scale S_b in ITS OWN AXIS a = unit(p0[k] - p0[b]):
##     S_b x = c x + (s - c) a (a . x)             (s along the bone, c across it; the child's rest offset maps to s * offset exactly)
## THE SKIN: linear blend, with the scale taken IN BONE SPACE FIRST and the blend after:
##     p(v) = sum_b w_b (P_b + G_b S_b (v - p0_b))
## (not a scale on the bone before the blend: #242 measured that putting a uniform scale on a bone first moves a hip vertex shared with
## an unscaled bone by 1.7 mm). The viewport's skeleton gives the engine the stretched JOINT positions (pose_positions: the child bones'
## local positions times s) and the engine skins with the rotations as it always did; this class then moves each affected vertex in the
## mesh's REST space to the point v' that the engine's plain blend maps onto p(v):  v' = A^-1 (p - o),  A = sum w L_k, o = sum w t_k
## (L_k, t_k the skinning matrix of the vertex's bone k). Only the vertices that weigh on a stretched bone are touched, and nothing runs
## unless Body.has_stretch(): with no stretch no node, mesh or pose is written, so every pose is byte-identical to before.
## LIMITS: normals are not re-derived; the hand and fingers ride the moved joints without the cross scale; one stretched child per bone.
class_name StretchSkin
extends RefCounted

var on := true             # tests turn it off for the control; View menu is not needed (it only runs with a stretch)
var rebuilds := 0
var _entries := []         # [{"mi", "base" (the mesh before this pass), "last" (the mesh this pass made, or null), "key"}]
var _sk: Skeleton3D
var _idx: Dictionary
var _corr
var _cache := {}           # (vertex hash, bones hash, scales) -> displaced vertices
var _aff := {}


## {bone joint: {"k": the stretched child, "a": unit axis (rest), "s", "c"}} for the body now
static func bones_of(B: Body) -> Dictionary:
	var out := {}
	for k in B.stretch:
		var b: String = B.parent.get(k, "")
		if b == "":
			continue
		out[b] = {"k": k, "a": ((B.p0[k] as Vector3) - (B.p0[b] as Vector3)).normalized(), "s": float(B.stretch[k]), "c": float(B.stretch_cross.get(k, 1.0))}
	return out


## the skeleton's child bones moved to the stretched joints (their local position times s), put back when the stretch goes. Called by
## Overlays.pose_skeleton; nothing is written for a body with no stretch that never had one.
static func pose_positions(sk: Skeleton3D, idx: Dictionary, B: Body) -> void:
	if not B.has_stretch():
		if sk.has_meta("ss_pos"):
			for bi in sk.get_meta("ss_pos"):
				sk.set_bone_pose_position(int(bi), sk.get_bone_rest(int(bi)).origin)
			sk.remove_meta("ss_pos")
		return
	var want := {}
	for k in B.stretch:
		var bk: int = idx.get(k, -1)
		var pb: int = idx.get(B.parent.get(k, ""), -1)
		if bk < 0 or pb < 0:
			continue
		var c := bk
		while c >= 0 and c != pb:   # the bones from the Kine parent (exclusive) down to k (inclusive)
			want[c] = float(B.stretch[k])
			c = sk.get_bone_parent(c)
	var had: Array = sk.get_meta("ss_pos") if sk.has_meta("ss_pos") else []
	for bi in had:
		if not want.has(bi):
			sk.set_bone_pose_position(int(bi), sk.get_bone_rest(int(bi)).origin)
	for bi in want:
		sk.set_bone_pose_position(int(bi), sk.get_bone_rest(int(bi)).origin * float(want[bi]))
	sk.set_meta("ss_pos", want.keys())


## the meshes to correct: each MeshInstance3D with a skin. corr (optional) = the Corrective whose arrays_of() saves reading them back
func attach(meshes: Array, sk: Skeleton3D, idx: Dictionary, corr = null) -> void:
	_sk = sk
	_idx = idx
	_corr = corr
	_entries = []
	for mi in meshes:
		var x := mi as MeshInstance3D
		if x != null and x.skin != null and x.mesh is ArrayMesh:
			_entries.append({"mi": x, "base": x.mesh, "last": null, "key": -1})


## put the stretched skin on the pieces for the pose B (call after Overlays.pose_skeleton and Corrective.update)
func update(B: Body) -> void:
	rebuilds = 0
	if not (on and B.has_stretch()):
		for e in _entries:
			if e["last"] != null:
				if (e["mi"] as MeshInstance3D).mesh == e["last"]:
					(e["mi"] as MeshInstance3D).mesh = e["base"]
				e["last"] = null
				e["key"] = -1
		return
	var sb := bones_of(B)
	var skey := var_to_str([B.stretch, B.stretch_cross, B.ang, B.offset, B.body]).hash()
	var sc := {}   # skeleton bone index -> Basis of the scale in the bone's own (rest) axes
	var g := []    # the bones' globals, composed from the local poses (the engine's cached global can lag)
	var nb := _sk.get_bone_count()
	g.resize(nb)
	for b in nb:
		var p := _sk.get_bone_parent(b)
		g[b] = (g[p] as Transform3D) * _sk.get_bone_pose(b) if p >= 0 else _sk.get_bone_pose(b)
	for j in sb:
		var bi: int = _idx.get(j, -1)
		var ki: int = _idx.get(sb[j]["k"], -1)
		if bi < 0 or ki < 0:
			continue
		var ro := Corrective._rest_origin(_sk, ki) - Corrective._rest_origin(_sk, bi)
		sc[bi] = [ro.normalized(), float(sb[j]["s"]), float(sb[j]["c"])]
	for e in _entries:
		var mi: MeshInstance3D = e["mi"]
		var base: ArrayMesh
		if e["last"] != null and mi.mesh == e["last"]:
			base = e["base"]
		else:
			base = mi.mesh as ArrayMesh
			e["base"] = base
			e["key"] = -1
		if e["key"] == skey and e["last"] != null and mi.mesh == e["last"]:
			continue
		var made := _build(mi, base, sc, g)
		if made == null:
			if e["last"] != null and mi.mesh == e["last"]:
				mi.mesh = base
			e["last"] = null
			e["key"] = skey
			continue
		mi.mesh = made
		e["last"] = made
		e["key"] = skey
		rebuilds += 1


## the displaced mesh for the piece, or null when none of its vertices weighs on a stretched bone
func _build(mi: MeshInstance3D, base: ArrayMesh, sc: Dictionary, g: Array) -> ArrayMesh:
	var sn := mi.skin
	var nbind := sn.get_bind_count()
	var bone_of := []
	var M := []
	var MS := []
	var scaled := {}
	for k in nbind:
		var bi := SkinPaint.bind_bone(sn, _sk, k)
		bone_of.append(bi)
		var m0 := (g[bi] as Transform3D) * sn.get_bind_pose(k)
		M.append(m0)
		if sc.has(bi):
			var a: Vector3 = (sn.get_bind_pose(k).basis * (sc[bi][0] as Vector3)).normalized()   # the axis in the bone's own coordinates
			var s: float = sc[bi][1]
			var c: float = sc[bi][2]
			var S := Basis(Vector3(c + (s - c) * a.x * a.x, (s - c) * a.x * a.y, (s - c) * a.x * a.z),
				Vector3((s - c) * a.x * a.y, c + (s - c) * a.y * a.y, (s - c) * a.y * a.z),
				Vector3((s - c) * a.x * a.z, (s - c) * a.y * a.z, c + (s - c) * a.z * a.z))
			MS.append((g[bi] as Transform3D) * Transform3D(S, Vector3.ZERO) * sn.get_bind_pose(k))
			scaled[k] = true
		else:
			MS.append(m0)
	if scaled.is_empty():
		return null
	var am := ArrayMesh.new()
	var any := false
	var done := {}
	for si in base.get_surface_count():
		var arr: Array = _arrays(mi, base, si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bo.size() / maxi(vs.size(), 1)
		var ck := [hash(vs), hash(bo), var_to_str(sc).hash(), var_to_str(M).hash(), si]
		var nv: PackedVector3Array
		if _cache.has(ck):
			nv = _cache[ck]
		else:
			nv = vs.duplicate()
			for i in vs.size():
				var hit := false
				for q in per:
					if w[i * per + q] > 0.0 and scaled.has(bo[i * per + q]):
						hit = true
						break
				if not hit:
					continue
				var ax := Vector3.ZERO
				var ay := Vector3.ZERO
				var az := Vector3.ZERO
				var o := Vector3.ZERO
				var p := Vector3.ZERO
				for q in per:
					var wk := w[i * per + q]
					if wk <= 0.0:
						continue
					var mk: Transform3D = M[bo[i * per + q]]
					ax += mk.basis.x * wk
					ay += mk.basis.y * wk
					az += mk.basis.z * wk
					o += mk.origin * wk
					p += (MS[bo[i * per + q]] as Transform3D) * vs[i] * wk
				var A := Basis(ax, ay, az)
				if absf(A.determinant()) > 1e-9:
					nv[i] = A.inverse() * (p - o)
			if _cache.size() > 400:
				_cache.clear()
			_cache[ck] = nv
		if nv != vs:
			any = true
		arr = arr.duplicate()
		arr[Mesh.ARRAY_VERTEX] = nv
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, base.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		am.surface_set_material(si, base.surface_get_material(si))
	return am if any else null


func _arrays(mi: MeshInstance3D, base: ArrayMesh, si: int) -> Array:
	if _corr != null:
		var a: Array = _corr.arrays_of(mi, base)
		if not a.is_empty():
			return a[si]
	return base.surface_get_arrays(si)


# ------------------------------------------------------------------------------------------------ for the exports (glTF, BVH, USD)

## a bone's own scale as the per-joint scale KEY: (c, s, c) in the bone's own axes (glTF: the bone's local Y runs along the bone)
static func own_local(B: Body) -> Dictionary:
	var out := {}
	var bs := bones_of(B)
	for j in bs:
		out[j] = Vector3(bs[j]["c"], bs[j]["s"], bs[j]["c"])
	return out


## the same as the diagonal of S_b in the rest world axes (BVH, USD: their joints' local axes are the world axes at rest, so the oblique
## part of S_b has no per-axis form: the diagonal is what is written; the joint POSITIONS carry the stretch exactly)
static func own_world(B: Body) -> Dictionary:
	var out := {}
	var bs := bones_of(B)
	for j in bs:
		var a: Vector3 = bs[j]["a"]
		var s: float = bs[j]["s"]
		var c: float = bs[j]["c"]
		out[j] = Vector3(c + (s - c) * a.x * a.x, c + (s - c) * a.y * a.y, c + (s - c) * a.z * a.z)
	return out


## THE KEYS of a joint tree for one frame. order: parents first. parent {j: parent or null}, rot {j: local rotation}, trest {j: rest local
## translation}, own {j: the joint's own scale (default 1)}, mult {j: factor on the joint's rest offset (the stretch)}.
## -> {"scale": {j: local scale = own / parent's own: a child does not inherit its parent's stretch (segment-scale-compensate)},
##     "pos": {j: local translation key}}. The translation is chosen so that the joint lands EXACTLY where the body puts it: the parent's
## scaled global basis scales the translation in a viewer, so T = Gs_parent^-1 * Rg_parent * (mult * trest).
static func tree_keys(order: Array, parent: Dictionary, rot: Dictionary, trest: Dictionary, own: Dictionary, mult: Dictionary) -> Dictionary:
	var Gs := {}
	var Rg := {}
	var scale := {}
	var pos := {}
	for j in order:
		var p = parent[j]
		var o: Vector3 = own.get(j, Vector3.ONE)
		var po: Vector3 = own.get(p, Vector3.ONE) if p != null else Vector3.ONE
		var ls := Vector3(o.x / po.x, o.y / po.y, o.z / po.z)
		var Rb := Basis(rot[j] as Quaternion)
		if p == null:
			Gs[j] = Rb * Basis.from_scale(ls)
			Rg[j] = Rb
			pos[j] = trest[j]
		else:
			var want: Vector3 = (Rg[p] as Basis) * ((trest[j] as Vector3) * float(mult.get(j, 1.0)))
			pos[j] = (Gs[p] as Basis).inverse() * want
			Gs[j] = (Gs[p] as Basis) * Rb * Basis.from_scale(ls)
			Rg[j] = (Rg[p] as Basis) * Rb
		scale[j] = ls
	return {"scale": scale, "pos": pos}


## the joints a scene may stretch (the children whose offset grows): limb keys with a stretch, and the joints of body spline chains.
## Used by the BVH writer, whose channel list is fixed before the frames are posed.
static func scene_joints(S: Scene, B: Body) -> Array:
	var out := []
	for tip in S.ik:
		if tip == SpineIK.KEY:
			continue
		var on := false
		for k in S.ik[tip]:
			if float((k as Dictionary).get("stretch", 0.0)) > 1.0:
				on = true
		if on:
			var ch: Array = LimbIK.chain(B, tip)
			for j in [ch[1], ch[2]]:
				if not j in out:
					out.append(j)
	for c in S.spline_body:
		var js: Array = c["joints"]
		for i in range(1, js.size()):
			if not js[i] in out:
				out.append(js[i])
	return out
