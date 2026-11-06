class_name SoftLive
extends RefCounted
## L22 SOFT-WIRE: the flesh of scripts/soft_body.gd in the running app.
##
## BAKE. When a region is on, the scene is baked at 60 Hz on a worker thread (WorkerThreadPool; SoftBody.bake_scene on a CLONE of the
## scene and a body of its own, sag_frame "body": the standing sag turns with the host bone). The bake is started again 250 ms
## after the clip changed (Main._dm_gen, the edit funnel's counter, plus the scene, its length and the region set), at once when the
## region set itself changed. Until the new bake lands the old one keeps drawing when its regions are the wanted ones.
## DRAW. Each frame (Main._refresh -> _soft_draw) the pieces that have skin vertices near a region get a deformed copy of their mesh:
## the bake's displacement at the playhead frame x the strength goes through SoftBody.vertex_offsets and the vertex's blended skinning
## matrix, exactly as SoftBody.skin_deform does (tests/softwire_test.gd bar 2: equal within 1e-6 m), but only for the vertices a
## cached prefilter marks (rest-pose box grown by 12 cm), so the cost does not scale with the whole mannequin. The original mesh is
## kept and put back when the regions go off (bar 1: byte-identical). The deformed mesh keeps the blend shapes and surface materials.
## Not done: dual-quaternion skinning (the scene's dq_skin) is not followed, a second fighter has no flesh, normals are not recomputed.

const SKEL := "res://data/skeleton.json"
const LIMS := "res://data/body_limits.json"
const HZ := 60.0
const DEBOUNCE_MS := 250
const CAND_MARGIN := 0.08

var engaged := false          # a region is wanted (the layer is live)
var names: Array = []         # the regions of the bake that is drawn
var regs: Array = []          # their geometry (SoftBody.bake_scene "geom"), in the order of names
var bake: Dictionary = {}
var starts := 0               # bakes started (tests read it)
var work_us := 0              # what the live layer spent (tests read it)
var _bake_key: Array = []
var _want_key: Array = []
var _want_since := 0
var _run_key: Array = []
var _task := -1
var _cancel: Array = [false]
var _res: Array = [null]
var _cache := {}              # piece instance id -> {orig, cur, surf: [...]}
var _last_k := -1
var _last_s := -1.0


func busy() -> bool:
	return _task >= 0


func ready() -> bool:
	return not bake.is_empty() and _task < 0 and _bake_key == _want_key and not _want_key.is_empty()


## the mesh a piece has without flesh (its own when it was never swapped)
func orig_mesh(piece: MeshInstance3D) -> Mesh:
	var e = _cache.get(piece.get_instance_id())
	if e != null and piece.mesh == e["cur"]:
		return e["orig"]
	return piece.mesh


# ------------------------------------------------------------ the thread

func _start(m: Node, want: Array) -> void:
	SoftBody.native_door()   # opens the extension on the main thread, never inside the worker
	_cancel = [false]
	_res = [null]
	var cl: Scene = (m.S as Scene).clone()
	var cc := _cancel
	var rs := _res
	var nm := want.duplicate()
	_run_key = _want_key.duplicate()
	starts += 1
	_task = WorkerThreadPool.add_task(func():
		var BB := Body.new()
		BB.load_files(SKEL, LIMS)
		BB.fk()
		rs[0] = SoftBody.bake_scene(cl, BB, nm, HZ, {"sag_frame": "body", "cancel": cc}))


func _stop_task() -> void:
	if _task >= 0:
		_cancel[0] = true
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## collects a finished bake; true when a new one landed
func poll(_m: Node) -> bool:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var r = _res[0]
	if r is Dictionary and not (r as Dictionary).is_empty() and _run_key == _want_key:
		bake = r
		_bake_key = _run_key
		names = (_run_key[2] as Array).duplicate()
		regs = []
		for n in names:
			regs.append(bake["geom"][n])
		_last_k = -1
		return true
	return false


# ------------------------------------------------------------ per frame

func tick(m: Node) -> void:
	var t0 := Time.get_ticks_usec()
	var S: Scene = m.S
	var want: Array = SoftBody.regions_of(S)
	if want.is_empty():
		release(m)
		work_us += Time.get_ticks_usec() - t0
		return
	engaged = true
	var key := [S.get_instance_id(), m._dm_gen, want, snappedf(S.length(), 1e-6)]
	if key != _want_key:
		_want_key = key
		_want_since = Time.get_ticks_msec()
	poll(m)
	if _task >= 0 and _run_key != _want_key:
		_stop_task()   # the clip changed under a running bake: it ends at its next frame
	if _task < 0 and _bake_key != _want_key:
		var same_regs: bool = not _bake_key.is_empty() and (_bake_key[2] as Array) == want and _bake_key[0] == key[0]
		if not same_regs or Time.get_ticks_msec() - _want_since >= DEBOUNCE_MS:
			_start(m, want)
	if bake.is_empty() or names != want or _bake_key[0] != key[0]:
		_restore_all()
	else:
		_apply(m, S)
	work_us += Time.get_ticks_usec() - t0


## the live layer off: meshes back, thread ended, bake dropped
func release(_m: Node) -> void:
	if not engaged and _task < 0 and _cache.is_empty():
		return
	_stop_task()
	_restore_all()
	_cache = {}
	bake = {}
	names = []
	regs = []
	_bake_key = []
	_want_key = []
	_run_key = []
	_last_k = -1
	engaged = false


func _restore_all() -> void:
	for id in _cache:
		var e: Dictionary = _cache[id]
		var p = e["piece"]
		if is_instance_valid(p) and (p as MeshInstance3D).mesh == e["cur"]:
			(p as MeshInstance3D).mesh = e["orig"]
			e["cur"] = e["orig"]
	_last_k = -1


func frame_of(t: float) -> int:
	return clampi(roundi(t * HZ), 0, int(bake["frames"]) - 1)


func _apply(m: Node, S: Scene) -> void:
	var s := SoftBody.strength_of(S)
	if s <= 0.0:
		_restore_all()
		return
	var k := frame_of(m.playhead)
	var disps := []
	for n in names:
		var d: PackedVector3Array = (bake["regions"][n]["disp"] as Array)[k]
		disps.append(d if s == 1.0 else _scaled(d, s))
	for j in m.pieces:
		var piece: MeshInstance3D = m.pieces[j]
		if is_instance_valid(piece):
			_deform_piece(piece, m.B, disps)


static func _scaled(d: PackedVector3Array, s: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(d.size())
	for i in d.size():
		out[i] = d[i] * s
	return out


# ------------------------------------------------------------ skinning (the arithmetic of SoftBody.skin_deform)

## the skinning matrix of each bind of the piece now, and the skeleton's global transform; [] when the piece has no skin
static func _skin_mats(piece: MeshInstance3D) -> Array:
	var sk := piece.get_node_or_null(piece.skeleton) as Skeleton3D
	var skin := piece.skin
	if sk == null or skin == null:
		return []
	var mb := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		mb.append(sk.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	return [mb, sk.global_transform]


## the posed world place of every vertex of `mesh` (all surfaces in order) on this piece's skeleton, as SoftBody.skin_deform computes it
func posed_world(piece: MeshInstance3D, mesh: Mesh) -> PackedVector3Array:
	var sm := _skin_mats(piece)
	var out := PackedVector3Array()
	if sm.is_empty():
		return out
	var mb: Array = sm[0]
	var gt: Transform3D = sm[1]
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)
		for i in verts.size():
			var mt := _blend(mb, bones, weights, i, per)
			out.append(gt * (mt[0] * verts[i].x + mt[1] * verts[i].y + mt[2] * verts[i].z + mt[3]))
	return out


static func _blend(mb: Array, bones: PackedInt32Array, weights: PackedFloat32Array, i: int, per: int) -> Array:
	var bx := Vector3.ZERO
	var by := Vector3.ZERO
	var bz := Vector3.ZERO
	var bo := Vector3.ZERO
	for q in per:
		var wq := weights[i * per + q]
		if wq <= 0.0:
			continue
		var mt: Transform3D = mb[bones[i * per + q]]
		bx += mt.basis.x * wq
		by += mt.basis.y * wq
		bz += mt.basis.z * wq
		bo += mt.origin * wq
	return [bx, by, bz, bo]


## the cache entry of a piece: the original arrays, and per surface the vertices near a region at REST (box grown by CAND_MARGIN)
func _entry(piece: MeshInstance3D) -> Dictionary:
	var id := piece.get_instance_id()
	var e = _cache.get(id)
	if e != null and (piece.mesh == e["cur"] or piece.mesh == e["orig"]) and e["names"] == names:
		return e
	var mesh := (e["orig"] if e != null and piece.mesh == e["cur"] else piece.mesh) as ArrayMesh
	if mesh == null:
		return {}
	var skn := piece.get_node_or_null(piece.skeleton) as Skeleton3D
	var gt := skn.global_transform if skn != null else piece.global_transform
	var surfs := []
	var any := false
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cand := PackedInt32Array()
		var by_reg := []   # per region: the positions in cand its box (grown) holds at rest
		for r in regs:
			by_reg.append([])
		# a piece is a share of the triangles of one vertex buffer: only the vertices its index array uses are drawn
		var used := PackedByteArray()
		used.resize(verts.size())
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array:
			for q in (idx as PackedInt32Array):
				used[q] = 1
		else:
			used.fill(1)
		for i in verts.size():
			if used[i] == 0:
				continue
			var w := gt * verts[i]
			var hit_any := false
			for ri in regs.size():
				var r: Dictionary = regs[ri]
				var u: Vector3 = (r["xf"] as Transform3D).affine_inverse() * w + (r["size"] as Vector3) * 0.5
				var s: Vector3 = r["size"]
				if u.x >= -CAND_MARGIN and u.y >= -CAND_MARGIN and u.z >= -CAND_MARGIN and u.x <= s.x + CAND_MARGIN and u.y <= s.y + CAND_MARGIN and u.z <= s.z + CAND_MARGIN:
					if not hit_any:
						cand.append(i)
						hit_any = true
					(by_reg[ri] as Array).append(cand.size() - 1)
		any = any or cand.size() > 0
		surfs.append({"arr": arr, "cand": cand, "by_reg": by_reg, "blend": mesh.surface_get_blend_shape_arrays(si), "mat": mesh.surface_get_material(si),
			"fmt": mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS})
	var ne := {"piece": piece, "orig": mesh, "cur": mesh, "names": names.duplicate(), "surf": surfs, "any": any}
	_cache[id] = ne
	return ne


func _deform_piece(piece: MeshInstance3D, B: Body, disps: Array) -> void:
	var e := _entry(piece)
	if e.is_empty() or not e["any"]:
		return
	var sm := _skin_mats(piece)
	if sm.is_empty():
		return
	var mb: Array = sm[0]
	var gt: Transform3D = sm[1]
	var gi := gt.basis.inverse()
	var new_surfs := []
	var moved := false
	for sd in e["surf"]:
		var arr: Array = sd["arr"]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cand: PackedInt32Array = sd["cand"]
		if cand.is_empty():
			new_surfs.append(null)
			continue
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)
		var mats := []
		var world := PackedVector3Array()
		world.resize(cand.size())
		for c in cand.size():
			var i := cand[c]
			var mt := _blend(mb, bones, weights, i, per)
			mats.append(mt)
			world[c] = gt * (mt[0] * verts[i].x + mt[1] * verts[i].y + mt[2] * verts[i].z + mt[3])
		var off := PackedVector3Array()
		off.resize(cand.size())
		var by_reg: Array = sd["by_reg"]
		for ri in regs.size():
			var pos: Array = by_reg[ri]
			if pos.is_empty():
				continue
			var sub := PackedVector3Array()
			sub.resize(pos.size())
			for q in pos.size():
				sub[q] = world[pos[q]]
			var o := SoftBody.vertex_offsets(regs[ri], B, disps[ri], sub)
			for q in pos.size():
				off[pos[q]] += o[q]
		var nv := verts.duplicate()
		var hit := false
		for c in cand.size():
			if off[c].length() > 1e-9:
				var m3: Array = mats[c]
				var bas := Basis(m3[0], m3[1], m3[2])
				if absf(bas.determinant()) > 1e-12:
					var i := cand[c]
					nv[i] = verts[i] + bas.inverse() * (gi * off[c])
					hit = true
		moved = moved or hit
		new_surfs.append(nv if hit else null)
	var orig: ArrayMesh = e["orig"]
	if not moved:
		if piece.mesh != orig:
			piece.mesh = orig
			e["cur"] = orig
		return
	var out := ArrayMesh.new()
	out.blend_shape_mode = orig.blend_shape_mode
	for b in orig.get_blend_shape_count():
		out.add_blend_shape(orig.get_blend_shape_name(b))
	for si in e["surf"].size():
		var sd: Dictionary = e["surf"][si]
		var arr2: Array = (sd["arr"] as Array).duplicate()
		if new_surfs[si] != null:
			arr2[Mesh.ARRAY_VERTEX] = new_surfs[si]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2, sd["blend"], {}, sd["fmt"])
		if sd["mat"] != null:
			out.surface_set_material(si, sd["mat"])
	piece.mesh = out
	e["cur"] = out
