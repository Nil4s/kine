## corrective.gd - CORRECTIVE SHAPES (ROADMAP 71, Nick: "the elbow and the knee pinch when they bend").
## Linear-blend skinning turns a bent joint into a candy wrapper: the vertices on the inside of the bend are pulled
## toward the joint and the limb's cross-section shrinks. A corrective pushes the vertices round each joint outward
## along their rest normals, by an amount that grows with the bend:
##     off(v) = AMP * drive(theta) * w(v) * n(v)            (metres, in the mesh's rest space; the skinning carries it)
##   theta = the joint's bend in degrees (Body.ang[bone].x: 0 = straight, the stop of an elbow or knee)
##   drive = smoothstep(0, FULL_DEG, theta): 0 at straight, 1 from 140 deg on (a human elbow's bend stops near 145 deg:
##           body_limits.json lowerarm_r bend [0, 145], calf_r [0, 145])
##   w(v)  = (the skin weight of v on the joint's two bones) * (1 - smoothstep(R0, R1, d)), d = rest distance of v from
##           the joint centre: full within R0 = 2 cm, gone past R1 = 10 cm (the bulge of the flexed muscle is a few cm)
##   n(v)  = the rest normal of v (outward)
## With drive 0 nothing is written: the mesh is the one the file gave, so the feature on or off is byte-identical at
## straight joints. Applies to every MeshInstance3D given to attach() (the main body's pieces, the dummy). Imported
## characters: the importer takes props, weapons and animations, not skinned characters, so there is no import step.
## Blend shapes named *elbow* / *knee* are not read (the mannequin has none).
class_name Corrective
extends RefCounted

const FULL_DEG := 140.0    # the bend at which the corrective is fully on
const AMP := 0.013         # m: the outward push at full drive, at the joint (tuned by tests/corrective_test.gd; 0.012
                           # before the weld: the welded smooth normal points a little less across the limb)
const R0 := 0.02           # m: full weight this close to the joint centre
const R1 := 0.10           # m: no weight past this distance
const WELD_EPS := 1e-5     # m: vertices this close at rest are one point of the skin (see _weld)
## the four joints: [key, distal bone (its origin is the joint centre, its Body.ang x is the bend), proximal bone]
const JOINTS := [["elbow_l", "lowerarm_l", "upperarm_l"], ["elbow_r", "lowerarm_r", "upperarm_r"],
	["knee_l", "calf_l", "thigh_l"], ["knee_r", "calf_r", "thigh_r"]]

var on := true             # View > Display > Corrective shapes
var weld := true           # one push per rest position (tests turn it off to show the seam crack it fixes)
var _entries := []         # [mesh instance, rest ArrayMesh, rest surface arrays, flags, materials, dirs, aff] per mesh
var _last := {}            # joint key -> the drive last written (no rebuild when nothing changed)
var rebuilds := 0          # how many mesh rebuilds the last updates made (tests: 0 at straight joints)
var _wcache := {}          # skin + vertex count -> weights(): the body's pieces share one skin and one vertex set
var _gcache := {}          # the same key -> girth_shapes() (R11)
var girth_on := true       # R11: body mass thickens the skin (Proportions.girth_lambda); tests turn it off for the control
var last_lambda := 0.0     # the girth lambda last written


## the smoothstep the bend is driven by: 0 at straight, 1 from FULL_DEG on
static func drive_of(bend_deg: float) -> float:
	return smoothstep(0.0, FULL_DEG, maxf(0.0, bend_deg))


## THE WEIGHT, per vertex, from the rest mesh: [{key: PackedVector3Array dir, key_aff: PackedInt32Array}] per
## surface. dir = w(v) * n(v) for the vertices the joint reaches; aff = those vertex indices. Pure: no scene needed
## beyond the skeleton's rest pose.
static func weights(sk: Skeleton3D, skin: Skin, src: ArrayMesh, weld := true) -> Array:
	var binds := []
	for k in skin.get_bind_count():
		var bb := skin.get_bind_bone(k)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(k))
		binds.append(bb)
	var cen := {}   # the joint centres at rest, composed from the rest transforms: asking the Skeleton3D for its global
	for jt in JOINTS:   # pose here made it keep a stale pose (the bent limbs then rendered straight; see _rest_origin)
		cen[jt[1]] = _rest_origin(sk, sk.find_bone(jt[1]))
	var pair := {}
	for jt in JOINTS:
		pair[jt[0]] = [sk.find_bone(jt[1]), sk.find_bone(jt[2])]
	var out := []
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nv := vs.size()
		var per := bones.size() / maxi(1, nv)
		var dirs := {}
		var aff := {}
		for jt in JOINTS:
			var key: String = jt[0]
			var pb: Array = pair[key]
			var c: Vector3 = cen[jt[1]]
			var dv := PackedVector3Array()
			dv.resize(nv)
			var ai := PackedInt32Array()
			for v in nv:
				var sw := 0.0
				for q in per:
					var w: float = wts[v * per + q]
					if w <= 0.0:
						continue
					var bi: int = binds[bones[v * per + q]]
					if bi == pb[0] or bi == pb[1]:
						sw += w
				if sw <= 0.0:
					continue
				var d := (vs[v] - c).length()
				var wj := sw * (1.0 - smoothstep(R0, R1, d))
				if wj <= 0.0:
					continue
				var n: Vector3 = ns[v] if ns.size() == nv else Vector3.UP
				dv[v] = n * wj
				ai.append(v)
			dirs[key] = dv
			aff[key] = ai
		out.append({"dirs": dirs, "aff": aff, "vs": vs, "ns": ns})
	if weld:
		_weld(out)
	for o in out:
		o.erase("vs")
		o.erase("ns")
	return out


## THE WELD (corrfix): the mannequin's file splits a vertex where its hard edges and UV seams run (8546 vertices,
## several copies at one rest position, each with its own face normal). Pushed along their own normals the copies
## part and the seam opens into a dark slit at a bent elbow. So every copy at one rest position (within WELD_EPS)
## gets ONE push: the normalised sum of the copies' normals (the smooth normal there) times the copies' mean weight.
## Across surfaces too. A single vertex keeps its own normal and weight.
static func _weld(out: Array) -> void:
	var groups := {}   # position key -> [[surface, vertex], ...]
	for si in out.size():
		var vs: PackedVector3Array = out[si]["vs"]
		for v in vs.size():
			var k := Vector3i((vs[v] / WELD_EPS).round())
			if not groups.has(k):
				groups[k] = []
			groups[k].append(Vector2i(si, v))
	for jt in JOINTS:
		var key: String = jt[0]
		var touched := {}   # surface -> {vertex: true} newly affected
		for k in groups:
			var g: Array = groups[k]
			if g.size() < 2:
				continue
			var nsum := Vector3.ZERO
			var wsum := 0.0
			for m in g:
				var o: Dictionary = out[m.x]
				var ns: PackedVector3Array = o["ns"]
				var n: Vector3 = ns[m.y] if ns.size() == (o["vs"] as PackedVector3Array).size() else Vector3.UP
				nsum += n
				wsum += (o["dirs"][key] as PackedVector3Array)[m.y].length()
			if wsum <= 0.0:
				continue
			var nn := nsum.normalized() if nsum.length() > 1e-6 else Vector3.UP
			var d := nn * (wsum / g.size())
			for m in g:
				var dv: PackedVector3Array = out[m.x]["dirs"][key]
				if dv[m.y] == Vector3.ZERO:
					if not touched.has(m.x):
						touched[m.x] = {}
					touched[m.x][m.y] = true
				dv[m.y] = d
				out[m.x]["dirs"][key] = dv
		for si in touched:
			var ai: PackedInt32Array = out[si]["aff"][key]
			for v in touched[si]:
				ai.append(v)
			ai.sort()
			out[si]["aff"][key] = ai


## R11 GIRTH SHAPES: how each vertex moves OUT across its bones' axes when the body is heavier. For a bone i with axis
## (a_i, t_i) and elasticity e_i (Proportions.girth_e), the skin at radial offset r_i(v) = (v - a_i) minus its part along t_i
## moves to  r_i * (exp(e_i lambda) - 1)  and the vertex takes its skin weights' mix of that:
##     dv = sum_i w_i r_i (exp(e_i lambda) - 1)  ~  lambda S1 + lambda^2 S2 + lambda^3 S3,
##     S1 = sum w_i e_i r_i,  S2 = sum w_i e_i^2/2 r_i,  S3 = sum w_i e_i^3/6 r_i
## (exp's cubic Taylor: off by < 0.2 % of the radius at |lambda| 0.55, the P1..P99 range is 0.38). A bone that is not
## ours takes its nearest ancestor that is. Only across the axis: no vertex moves along a bone, so no length changes.
## -> per surface [S1, S2, S3] (PackedVector3Array each)
static func girth_shapes(sk: Skeleton3D, skin: Skin, src: ArrayMesh) -> Array:
	var ref := Body.new()
	ref.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var ours := {}   # bone -> joint
	for j in Body.ORDER:
		var b := sk.find_bone("Head" if j == "head" else j)
		if b >= 0:
			ours[b] = j
	var ax := {}   # bone -> [a, t, e]
	for k in skin.get_bind_count():
		var bb := skin.get_bind_bone(k)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(k))
		var c := bb
		while c >= 0 and not ours.has(c):
			c = sk.get_bone_parent(c)
		var j: String = ours[c] if c >= 0 else "pelvis"
		var a: Vector3 = ref.p0[j]
		var t: Vector3 = ((ref.e0[j] as Vector3) - a).normalized()
		ax[k] = [a, t, Proportions.girth_e(j)]
	var out := []
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nv := vs.size()
		var per := bones.size() / maxi(1, nv)
		var s1 := PackedVector3Array()
		var s2 := PackedVector3Array()
		var s3 := PackedVector3Array()
		s1.resize(nv)
		s2.resize(nv)
		s3.resize(nv)
		for v in nv:
			var a1 := Vector3.ZERO
			var a2 := Vector3.ZERO
			var a3 := Vector3.ZERO
			for q in per:
				var w: float = wts[v * per + q]
				if w <= 0.0:
					continue
				var d: Array = ax[bones[v * per + q]]
				var e: float = d[2]
				if e == 0.0:
					continue
				var rel: Vector3 = vs[v] - (d[0] as Vector3)
				var r: Vector3 = rel - (d[1] as Vector3) * rel.dot(d[1])
				a1 += r * (w * e)
				a2 += r * (w * e * e * 0.5)
				a3 += r * (w * e * e * e / 6.0)
			s1[v] = a1
			s2[v] = a2
			s3[v] = a3
		out.append([s1, s2, s3])
	return out


## the vertices with the girth of lambda added
static func girthed(base: PackedVector3Array, sh: Array, lam: float) -> PackedVector3Array:
	var out := base.duplicate()
	var l2 := lam * lam
	var l3 := l2 * lam
	var a: PackedVector3Array = sh[0]
	var b: PackedVector3Array = sh[1]
	var c: PackedVector3Array = sh[2]
	for i in out.size():
		out[i] = base[i] + a[i] * lam + b[i] * l2 + c[i] * l3
	return out


## the meshes to correct (each MeshInstance3D with a skin, a skeleton): remembers each one's rest mesh

## the inputs of weights() and girth_shapes(): the joints' rest poses, the skin's binds, the mesh's surfaces (the cache key)
static func _inputs(sk: Skeleton3D, skin: Skin, src: ArrayMesh) -> Array:
	var rests := []
	for b in sk.get_bone_count():
		rests.append(sk.get_bone_rest(b))
	var binds := []
	for k in skin.get_bind_count():
		binds.append([skin.get_bind_bone(k), skin.get_bind_name(k), skin.get_bind_pose(k)])
	var surfs := []
	for si in src.get_surface_count():
		surfs.append(src.surface_get_arrays(si))
	return [rests, binds, surfs]

func attach(meshes: Array, sk: Skeleton3D) -> void:
	_entries = []
	_last = {}
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m == null or m.skin == null or not (m.mesh is ArrayMesh):
			continue
		var src := m.mesh as ArrayMesh
		var key := "%d|%s|%s" % [m.skin.get_instance_id(), str(_vcounts(src)), weld]
		if not _wcache.has(key):
			# a split piece has the same skin and vertices as its source; the result is cached on its inputs (BodyCache)
			_wcache[key] = BodyCache.fetch("weights", [_inputs(sk, m.skin, src), weld], func(): return weights(sk, m.skin, src, weld))
		var wd: Array = _wcache[key]
		if not _gcache.has(key):
			_gcache[key] = BodyCache.fetch("girth", [_inputs(sk, m.skin, src)], func(): return girth_shapes(sk, m.skin, src))
		var arrs := []
		var flags := []
		var mats := []
		for si in src.get_surface_count():
			arrs.append(src.surface_get_arrays(si))
			flags.append(src.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			mats.append(src.surface_get_material(si))
		# ROADMAP 99: which joints can change what THIS piece draws: those whose affected vertices its triangles use. The app's 52
		# pieces each draw one body part; an elbow bending rebuilds the few pieces at the elbow, not all 52
		var deps := []
		for jt in JOINTS:
			var hit := false
			for si in arrs.size():
				var idx = (arrs[si] as Array)[Mesh.ARRAY_INDEX]
				var used := {}
				if idx != null:
					for v in (idx as PackedInt32Array):
						used[v] = true
				for v in (wd[si]["aff"][jt[0]] as PackedInt32Array):
					if idx == null or used.has(v):
						hit = true
						break
				if hit:
					break
			if hit:
				deps.append(jt[0])
		_entries.append([m, src, arrs, flags, mats, wd, deps, null, _gcache[key], key, null])


## a bone's rest origin in the skeleton's space: the rest transforms of its chain, root first. Not
## Skeleton3D.get_bone_global_rest: once the engine has been asked for a global pose, a later pose change is not shown.
static func _rest_origin(sk: Skeleton3D, bi: int) -> Vector3:
	var chain := []
	var c := bi
	while c >= 0:
		chain.push_front(c)
		c = sk.get_bone_parent(c)
	var t := Transform3D.IDENTITY
	for b in chain:
		t = t * sk.get_bone_rest(b)
	return t.origin


## the vertex count of each surface (the cache key)
static func _vcounts(m: ArrayMesh) -> Array:
	var out := []
	for si in m.get_surface_count():
		out.append((m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	return out


## the drive of each joint from the body's pose (bend in degrees): {joint key: 0..1}
func drives(B: Body) -> Dictionary:
	var out := {}
	for jt in JOINTS:
		out[jt[0]] = drive_of(float(B.ang[jt[1]].x)) if on else 0.0
	return out


## the surface arrays of the mesh `mesh` this class put on `mi` (the file's own, or the last one it built); [] for any other mesh.
## L22: reading them back from the engine costs about 1 ms a surface, and the soft flesh needs them every frame.
func arrays_of(mi: MeshInstance3D, mesh: Mesh) -> Array:
	for e in _entries:
		if e[0] == mi:
			if mesh == e[1]:
				return e[2]
			if e.size() > 10 and e[10] != null and e[10][0] == mesh:
				return e[10][1]
			return []
	return []


## L64: vs[i] += dv[i] * amp for the vertices in ai. KineDockNative.push is the same loop in C++; _push_gd is the GDScript twin and
## the reference (PerfDoc.refresh_full).
static var _native := -1
static var _door = null   # scripts/dock_native.gd
static var native_pushes := 0   # tests


static func native_ok() -> bool:
	if _native < 0:
		_native = 1 if NativeExt.ensure("kine_native", "KineDockNative") else 0
		if _native == 1:
			_door = load("res://scripts/dock_native.gd")
	return _native == 1 and _door != null


static func push(vs: PackedVector3Array, dv: PackedVector3Array, ai: PackedInt32Array, amp: float) -> PackedVector3Array:
	if PerfDoc.refresh_full or not native_ok():
		return _push_gd(vs, dv, ai, amp)
	native_pushes += 1
	return _door.push(vs, dv, ai, amp)


static func _push_gd(vs: PackedVector3Array, dv: PackedVector3Array, ai: PackedInt32Array, amp: float) -> PackedVector3Array:
	var out := vs.duplicate()
	for i in ai:
		out[i] = out[i] + dv[i] * amp
	return out


## write the corrective for the pose B into the meshes (call after Overlays.pose_skeleton). A mesh is rebuilt only
## when one of its joints has a drive above 0 and that drive changed; a mesh whose joints are straight is the file's own.
func update(B: Body) -> void:
	rebuilds = 0
	var dr := drives(B)
	var lam := snappedf(Proportions.girth_lambda(B.body), 0.001) if girth_on else 0.0   # R11: 0.1 % steps of girth
	dr["girth"] = lam
	last_lambda = lam
	if dr == _last:
		return
	_last = dr
	var gdone := {}   # (shapes, surface) -> the girthed vertices, made once for all the pieces
	for e in _entries:
		var mi: MeshInstance3D = e[0]
		var sub := {}   # the drives of the joints this piece depends on: unchanged = nothing to rebuild
		for k in e[6]:
			sub[k] = dr[k]
		sub["girth"] = lam
		if e[7] == sub:
			continue
		e[7] = sub
		var any := lam != 0.0
		for jt in JOINTS:
			if sub.has(jt[0]) and float(dr[jt[0]]) > 0.0:
				any = true
		if not any:
			if mi.mesh != e[1]:
				mi.mesh = e[1]
				rebuilds += 1
			continue
		var am := ArrayMesh.new()
		var arrs: Array = e[2]
		var built := []   # the surface arrays of the mesh made here (arrays_of: the soft flesh reads them instead of the engine)
		for si in arrs.size():
			var arr: Array = (arrs[si] as Array).duplicate()
			var vs: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
			if lam != 0.0:
				var gk := "%s|%d" % [e[9], si]
				if not gdone.has(gk):
					gdone[gk] = girthed(arr[Mesh.ARRAY_VERTEX], e[8][si], lam)
				vs = gdone[gk]
			var wd: Dictionary = e[5][si]
			for jt in JOINTS:
				var k: float = float(dr[jt[0]])
				if k <= 0.0 or not sub.has(jt[0]):
					continue
				var dv: PackedVector3Array = wd["dirs"][jt[0]]
				var ai: PackedInt32Array = wd["aff"][jt[0]]
				vs = push(vs, dv, ai, AMP * k)
			arr[Mesh.ARRAY_VERTEX] = vs
			built.append(arr)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, int(e[3][si]))
			am.surface_set_material(si, e[4][si])
		mi.mesh = am
		e[10] = [am, built]
		rebuilds += 1
