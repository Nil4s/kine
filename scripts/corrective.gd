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
const AMP := 0.012         # m: the outward push at full drive, at the joint (tuned by tests/corrective_test.gd)
const R0 := 0.02           # m: full weight this close to the joint centre
const R1 := 0.10           # m: no weight past this distance
## the four joints: [key, distal bone (its origin is the joint centre, its Body.ang x is the bend), proximal bone]
const JOINTS := [["elbow_l", "lowerarm_l", "upperarm_l"], ["elbow_r", "lowerarm_r", "upperarm_r"],
	["knee_l", "calf_l", "thigh_l"], ["knee_r", "calf_r", "thigh_r"]]

var on := true             # View > Display > Corrective shapes
var _entries := []         # [mesh instance, rest ArrayMesh, rest surface arrays, flags, materials, dirs, aff] per mesh
var _last := {}            # joint key -> the drive last written (no rebuild when nothing changed)
var rebuilds := 0          # how many mesh rebuilds the last updates made (tests: 0 at straight joints)
var _wcache := {}          # skin + vertex count -> weights(): the body's pieces share one skin and one vertex set


## the smoothstep the bend is driven by: 0 at straight, 1 from FULL_DEG on
static func drive_of(bend_deg: float) -> float:
	return smoothstep(0.0, FULL_DEG, maxf(0.0, bend_deg))


## THE WEIGHT, per vertex, from the rest mesh: [{key: PackedVector3Array dir, key_aff: PackedInt32Array}] per
## surface. dir = w(v) * n(v) for the vertices the joint reaches; aff = those vertex indices. Pure: no scene needed
## beyond the skeleton's rest pose.
static func weights(sk: Skeleton3D, skin: Skin, src: ArrayMesh) -> Array:
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
		out.append({"dirs": dirs, "aff": aff})
	return out


## the meshes to correct (each MeshInstance3D with a skin, a skeleton): remembers each one's rest mesh
func attach(meshes: Array, sk: Skeleton3D) -> void:
	_entries = []
	_last = {}
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m == null or m.skin == null or not (m.mesh is ArrayMesh):
			continue
		var src := m.mesh as ArrayMesh
		var key := "%d|%s" % [m.skin.get_instance_id(), str(_vcounts(src))]
		if not _wcache.has(key):
			_wcache[key] = weights(sk, m.skin, src)   # a split piece has the same skin and vertices as its source
		var wd: Array = _wcache[key]
		var arrs := []
		var flags := []
		var mats := []
		for si in src.get_surface_count():
			arrs.append(src.surface_get_arrays(si))
			flags.append(src.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			mats.append(src.surface_get_material(si))
		_entries.append([m, src, arrs, flags, mats, wd])


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


## write the corrective for the pose B into the meshes (call after Overlays.pose_skeleton). A mesh is rebuilt only
## when one of its joints has a drive above 0 and that drive changed; a mesh whose joints are straight is the file's own.
func update(B: Body) -> void:
	rebuilds = 0
	var dr := drives(B)
	if dr == _last:
		return
	_last = dr
	for e in _entries:
		var mi: MeshInstance3D = e[0]
		var any := false
		for jt in JOINTS:
			if float(dr[jt[0]]) > 0.0:
				any = true
		if not any:
			if mi.mesh != e[1]:
				mi.mesh = e[1]
				rebuilds += 1
			continue
		var am := ArrayMesh.new()
		var arrs: Array = e[2]
		for si in arrs.size():
			var arr: Array = (arrs[si] as Array).duplicate()
			var vs: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
			var wd: Dictionary = e[5][si]
			for jt in JOINTS:
				var k: float = float(dr[jt[0]])
				if k <= 0.0:
					continue
				var dv: PackedVector3Array = wd["dirs"][jt[0]]
				var ai: PackedInt32Array = wd["aff"][jt[0]]
				var amp := AMP * k
				for i in ai:
					vs[i] = vs[i] + dv[i] * amp
			arr[Mesh.ARRAY_VERTEX] = vs
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, int(e[3][si]))
			am.surface_set_material(si, e[4][si])
		mi.mesh = am
		rebuilds += 1
