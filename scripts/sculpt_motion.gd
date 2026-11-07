class_name SculptMotion
extends RefCounted
## C23 (docs/ROADMAP_400.md): SCULPT CHECKED IN MOTION. After a body-sculpt stroke, the 8 frames of the open scene where the
## STROKED REGION deforms most are picked, and a small skinned patch of the body round the region is posed at each (the thumbnail
## strip, scripts/sculpt_motion_ui.gd, draws them). This file is the pure part: the metric, the choice, the patches.
##
## THE METRIC. Frames f = 0 .. ceil(length * fps), t = min(f / fps, length); the scene applied on a body of its own, a copy of the
## skeleton posed (nothing the window shows moves), the REST mesh (as just sculpted) skinned at that pose with the scene's dq_skin
## blend. REGION = the rest vertices the stroke moved. EDGES = the mesh edges with both ends in the region (rest length > 1 mm).
##   score(f) = mean over EDGES of | ln( posed length / rest length ) |       0 = rigid; stretch and squash both count
## CHOSEN = the TOP (8) frames by score (ties: the lower frame), kept in time order; a scene with fewer frames shows them all.
## ON THE MAIN THREAD, IN SLICES: step(budget_ms) does a slice of the work (the edge scan, some frames, some patch vertices) and
## returns true while there is more; max_slice_ms is the longest slice (the test's 50 ms bar; the UI asks for 6 ms).
## THE PATCH: the vertices within PATCH_R (>= 0.12 m, 2.2 x the region's radius) of the region's centre at rest and the faces
## among them, skinned at each chosen frame; the region's vertices are coloured red (unshaded), the rest grey and lit by a
## headlight. The camera of a thumbnail looks down the region's mean normal at that frame, centred on its bbox, orthographic;
## one common size for all thumbnails (the largest region extent x 1.6 + 3 cm), so the region is always inside the picture.

const TOP := 8
const SIZE := 160
const MIN_EDGE := 0.001

var rest: KMesh
var bo := PackedInt32Array()
var w := PackedFloat32Array()
var scene: Scene
var main: Node
var skc: Skeleton3D
var bone_idx := {}
var skin: Skin
var G: Body
var k := 0.0
var fps := 30.0
var nf := 0
var length := 0.0
var region := PackedInt32Array()
var flag := PackedByteArray()
var ea := PackedInt32Array()
var eb := PackedInt32Array()
var el := PackedFloat32Array()
var scores := PackedFloat64Array()
var chosen: Array = []
var thumbs: Array = []        # [{"frame","t","score","image","cam_xf","cam_size"}] in time order (image set by the UI)
var patch_v := PackedInt32Array()      # rest vertex ids of the patch
var patch_tri := PackedInt32Array()    # triangles, indices into the patch
var patch_pos: Array = []     # per chosen frame: PackedVector3Array, the patch skinned there
var state := "idle"           # idle / edges / frames / patch_pick / patch_skin / done
var max_slice_ms := 0.0
var total_ms := 0.0
var _fc := 0                  # faces scanned
var _f := 0                   # frames scored / patches skinned
var _pi := 0                  # patch vertex cursor
var _P := PackedVector3Array()
var _seen := {}
var _t0 := 0
var _budget := 6.0
var _cur: PackedVector3Array
var _mats: Array = []
var _dq: Array = []


## the rest mesh and its skin weights (from the pose sculpt), the app's skeleton / scene
func setup(sp: SculptPose, m: Node) -> SculptMotion:
	rest = sp.rest
	bo = sp.bo
	w = sp.w
	skin = sp.skin
	main = m
	scene = m._ps()
	skc = (m.skel as Skeleton3D).duplicate()
	bone_idx = m.bone_idx
	G = Body.new()
	G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	k = float(scene.dq_skin)
	fps = float(scene.fps)
	length = scene.length()
	nf = int(ceil(length * fps)) + 1
	return self


static func frame_count(sc: Scene) -> int:
	return int(ceil(sc.length() * float(sc.fps))) + 1


func begin(reg: PackedInt32Array) -> void:
	region = reg
	flag = PackedByteArray()
	flag.resize(rest.verts.size())
	for v in reg:
		flag[v] = 1
	ea = PackedInt32Array()
	eb = PackedInt32Array()
	el = PackedFloat32Array()
	scores = PackedFloat64Array()
	chosen = []
	thumbs = []
	patch_pos = []
	_seen = {}
	_fc = 0
	_f = 0
	_pi = 0
	_P = PackedVector3Array()
	_P.resize(rest.verts.size())
	max_slice_ms = 0.0
	total_ms = 0.0
	state = "edges"


func _over() -> bool:
	return float(Time.get_ticks_usec() - _t0) / 1000.0 >= _budget


## one slice of the work; true while there is more
func step(budget_ms := 6.0) -> bool:
	_budget = budget_ms
	_t0 = Time.get_ticks_usec()
	match state:
		"edges":
			_edges()
		"frames":
			_frames()
		"patch_pick":
			_pick_patch()
		"patch_skin":
			_skin_patches()
	var ms := float(Time.get_ticks_usec() - _t0) / 1000.0
	max_slice_ms = maxf(max_slice_ms, ms)
	total_ms += ms
	return state != "done" and state != "idle"


func finish_now(reg: PackedInt32Array) -> void:
	begin(reg)
	while step(1e9):
		pass


func _edges() -> void:
	var faces := rest.faces
	var vs := rest.verts
	while _fc < faces.size():
		var f: PackedInt32Array = faces[_fc]
		var n := f.size()
		for i in n:
			var a := f[i]
			var b := f[(i + 1) % n]
			if flag[a] == 0 or flag[b] == 0:
				continue
			var key := mini(a, b) * 1000003 + maxi(a, b)
			if _seen.has(key):
				continue
			_seen[key] = true
			var l := vs[a].distance_to(vs[b])
			if l > MIN_EDGE:
				ea.append(mini(a, b))
				eb.append(maxi(a, b))
				el.append(l)
		_fc += 1
		if (_fc & 63) == 0 and _over():
			return
	_seen = {}
	scores.resize(nf)
	_f = 0
	state = "frames"


## the skeleton posed at frame f and its skinning matrices
func _pose(f: int) -> void:
	scene.apply(G, minf(float(f) / fps, length))
	Overlays.pose_skeleton(skc, bone_idx, G)
	_mats = DqSkin.bind_mats(skc, skin)
	_dq = DqSkin.dqs_of(_mats)


func _skin(v: int) -> Vector3:
	return DqSkin.skin_one(rest.verts[v], v, bo, w, 4, _mats, _dq, k)[0]


func _frames() -> void:
	while _f < nf:
		_pose(_f)
		for v in region:
			_P[v] = _skin(v)
		var s := 0.0
		for e in ea.size():
			s += absf(log(maxf(_P[ea[e]].distance_to(_P[eb[e]]), 1e-9) / el[e]))
		scores[_f] = s / maxf(1.0, float(ea.size()))
		_f += 1
		if _over():
			return
	var ix := range(nf)
	ix.sort_custom(func(a, b): return scores[a] > scores[b] or (scores[a] == scores[b] and a < b))
	chosen = ix.slice(0, mini(TOP, nf))
	chosen.sort()
	state = "patch_pick"


## the patch: vertices near the region's centre at rest, the faces among them
func _pick_patch() -> void:
	var vs := rest.verts
	var c := Vector3.ZERO
	for v in region:
		c += vs[v]
	c /= maxf(1.0, float(region.size()))
	var rad := 0.0
	for v in region:
		rad = maxf(rad, vs[v].distance_to(c))
	var pr := maxf(0.12, rad * 2.2)
	var map := {}
	patch_v = PackedInt32Array()
	for v in vs.size():
		if flag[v] == 1 or vs[v].distance_to(c) < pr:
			map[v] = patch_v.size()
			patch_v.append(v)
	patch_tri = PackedInt32Array()
	for f in rest.faces:
		var ok := true
		for v in f:
			if not map.has(v):
				ok = false
				break
		if not ok:
			continue
		for i in range(1, f.size() - 1):
			patch_tri.append(map[f[0]])
			patch_tri.append(map[f[i]])
			patch_tri.append(map[f[i + 1]])
	_f = 0
	_pi = 0
	_cur = PackedVector3Array()
	_cur.resize(patch_v.size())
	state = "patch_skin"


func _skin_patches() -> void:
	while _f < chosen.size():
		if _pi == 0:
			_pose(chosen[_f])
		else:
			_pose(chosen[_f])   # a slice that ended mid-frame poses it again (cheap: bones only)
		while _pi < patch_v.size():
			_cur[_pi] = _skin(patch_v[_pi])
			_pi += 1
			if (_pi & 63) == 0 and _over():
				return
		patch_pos.append(_cur.duplicate())
		_make_thumb(_f)
		_f += 1
		_pi = 0
		if _over():
			return
	var sz := 0.0
	for t in thumbs:
		sz = maxf(sz, float(t["need"]))
	for t in thumbs:
		t["cam_size"] = sz
	state = "done"


## the camera of one thumbnail from the patch skinned at its frame
func _make_thumb(j: int) -> void:
	var pos: PackedVector3Array = patch_pos[j]
	var rmap := {}
	for i in patch_v.size():
		if flag[patch_v[i]] == 1:
			rmap[i] = true
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for i in range(0, patch_tri.size(), 3):
		var a := patch_tri[i]
		var b := patch_tri[i + 1]
		var c := patch_tri[i + 2]
		var fn := (pos[b] - pos[a]).cross(pos[c] - pos[a])
		nrm[a] += fn
		nrm[b] += fn
		nrm[c] += fn
	var mean := Vector3.ZERO
	var cen := Vector3.ZERO
	for i in rmap:
		mean += nrm[i].normalized()
		cen += pos[i]
	cen /= maxf(1.0, float(rmap.size()))
	var d := mean.normalized() if mean.length() > 0.2 * maxf(1.0, float(rmap.size())) else Vector3(0, 0, 1)
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.BACK
	var bas := Basis.looking_at(-d, up)
	var x0 := 1e9
	var y0 := 1e9
	var x1 := -1e9
	var y1 := -1e9
	for i in rmap:
		var l := bas.inverse() * (pos[i] - cen)
		x0 = minf(x0, l.x)
		y0 = minf(y0, l.y)
		x1 = maxf(x1, l.x)
		y1 = maxf(y1, l.y)
	var mid := cen + bas * Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)
	thumbs.append({"frame": chosen[j], "t": minf(float(chosen[j]) / fps, length), "score": scores[chosen[j]], "image": null,
		"cam_xf": Transform3D(bas, mid + d * 0.8), "need": maxf(x1 - x0, y1 - y0) * 1.6 + 0.03, "cam_size": 0.1, "normal": d})


## the arrays of thumbnail j's patch mesh (one flat colour per triangle: red and unshaded where at least two of its corners are in
## the region, else grey with a headlight), so the red marker ends where the region ends
func patch_arrays(j: int) -> Array:
	var pos: PackedVector3Array = patch_pos[j]
	var d: Vector3 = thumbs[j]["normal"]
	var vo := PackedVector3Array()
	var no := PackedVector3Array()
	var col := PackedColorArray()
	for i in range(0, patch_tri.size(), 3):
		var a := patch_tri[i]
		var b := patch_tri[i + 1]
		var c := patch_tri[i + 2]
		var fn := (pos[b] - pos[a]).cross(pos[c] - pos[a]).normalized()
		var inr := int(flag[patch_v[a]]) + int(flag[patch_v[b]]) + int(flag[patch_v[c]])
		var cl := Color(1, 0, 0)
		if inr < 2:
			var lit := 0.4 + 0.6 * absf(fn.dot(d))
			cl = Color(0.62 * lit, 0.64 * lit, 0.68 * lit)
		for v in [a, b, c]:
			vo.append(pos[v])
			no.append(fn)
			col.append(cl)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vo
	arr[Mesh.ARRAY_NORMAL] = no
	arr[Mesh.ARRAY_COLOR] = col
	return arr
