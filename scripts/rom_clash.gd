## RANGE-OF-MOTION CLASH + CLOTHES-SAFE CLEARANCE (ROADMAP_400 B24 ★, B25 ★): the parts added to the fighter (B23's armour
## plates, any skinned part beside the body pieces) checked against the body over MOTION, not just the rest pose.
##   B24  every frame of a ROM TEST (a built-in sweep of each joint that can move the part against the body, from rest out
##        to each end of each axis of F14's limits, data/body_limits.json via Body.lim, STEP_DEG apart) or of the OPEN
##        SCENE: the part vertices INSIDE the body skin (and inside another part) with their depth; the frames listed worst
##        first, one per moment ("frame 67, left elbow bend 145°: armour_1 (biceps_l) 4.0 mm into the left biceps").
##   B25  per part vertex the MINIMUM CLEARANCE to the skin over all those frames (signed: - = inside) and the frame where it
##        happens; green > WARN (1 cm), yellow 0..1 cm, red < 0. A part within 1 cm anywhere over the motion is warned about.
## REUSED, not rebuilt: the frames are sampled by H17's sampler (DeformScene.step: main-thread slices of BUDGET_MS, the
## skeleton put back inside every slice; this class extends it, plays the ROM test as a Scene, and replaces the worker);
## the posed skin is held in B13's BVH (KMeshShrinkwrap.build: outward normals per closed part, so the mannequin's
## inward-wound parts point out; its nearest-point query, ray test and box walk); the skinning is H04's (DqSkin.skin_one)
## at the scene's LBS / DQS mix (Scene.dq_skin), plain linear blend when it is 0. The joints and their limits are F14's
## (DeformCheck.entries(), Body.lim). The red lane, the list and the overlay: RomClashUI.
## PER FRAME (WorkerThreadPool tasks, one frame each, results kept in frame order: deterministic):
##   1. the parts skinned (world: the skeleton's transform x the skinning in skeleton space);
##   2. the body's closed parts that can come within CAP of them: each part's rest box carried by every bone that moves it
##      (conservative: an LBS point is a convex mix of its bones' images), padded by PAD for DQS; only those are skinned
##      and put in a BVH;
##   3. per part vertex: INSIDE the body when the WINDING NUMBER of the posed skin about it is positive on 2 of B13's 3
##      skew rays (signed crossings: out +1, in -1). B13's parity counts a point inside two overlapping parts, or inside a
##      limb folded into itself (the forearm pressed into the biceps, one welded part), as outside; the winding number
##      counts 2. DEPTH / CLEARANCE: the distance to the nearest skin triangle (the measurement an independent nearest-
##      triangle check makes), negative when inside, capped at CAP outside;
##   4. part against part: a vertex of one part inside another CLOSED part (winding, depth to its surface); for an open
##      part (a sheet), an edge of the other part crossing it marks both its ends (depth: the nearer end's distance).
## A FRAME's grade (its place in the list) is its total penetration: the depths summed over its offending vertices (one
## vertex at 4 mm is less than twenty at 4 mm); its words give the deepest. Known limits: a clearance beyond CAP is
## reported as CAP (green); the winding number of an open body part is unreliable (the mannequin has 2 boundary edges).
class_name RomClash
extends DeformScene

const CAP := 0.03           # m: clearance is measured out to this (beyond: "clear", reported as CAP)
const WARN := 0.01          # m: B25's warning band (yellow under it, red inside)
const EPS_IN := 1e-5        # m: inside deeper than this counts (a vertex on the skin is float noise)
const STEP_DEG := 10.0      # the ROM sweep's step
const ROM_FPS := 30
const PAD := 0.02           # m: the conservative box of a body part, padded (DQS bulges past the LBS hull a little)
const MIN_EXT := 5.0        # deg: an axis end under this is locked (DeformCheck's rule)
const RAYS := [Vector3(0.267, 0.534, 0.802), Vector3(-0.577, 0.211, -0.789), Vector3(0.123, -0.951, 0.284)]   # B13's
const AXIS_WORD := {"bend": "bend", "side": "side", "twist": "twist"}


var mode := "scene"         # "rom" / "scene"
var opts := {}
var _angs := []             # per sampled frame: the scratch body's angles (the words of a scene frame)
var _mx := Mutex.new()
var _P := {}
var _out := []


## the ROM test as a Scene the H17 sampler can play: frame f = poses[f] on the zero pose
class RomSweep:
	extends Scene
	var poses := []   # [{"angs": {bone: Vector3}, "label", "entry", "axis", "deg"}]

	func apply(B: Body, t: float) -> void:
		if B.body != body:
			B.set_proportions(body)
		B.squash = {}
		var f := clampi(roundi(t * float(fps)), 0, poses.size() - 1)
		for j in B.ang:
			B.ang[j] = Vector3.ZERO
		var a: Dictionary = poses[f]["angs"]
		for j in a:
			B.ang[j] = a[j]
		B.fk()

	func length() -> float:
		return float(maxi(poses.size() - 1, 0)) / float(fps)


# ---------------------------------------------------------------- the sweep

## the F14 joints that can move a part against the body: the joint moves a bone of the part (it is in the joint's
## subtree) or swings a limb hanging off the part (the joint's parent bone is one of the part's). pbones: skeleton bone
## index -> true
static func relevant(skel: Skeleton3D, idx: Dictionary, pbones: Dictionary) -> Array:
	var out := []
	for e in DeformCheck.entries():
		var ok := true
		var ids := []
		for bn in e["bones"]:
			if not idx.has(bn) or int(idx[bn]) < 0:
				ok = false
				break
			ids.append(int(idx[bn]))
		if not ok:
			continue
		var hit := pbones.has(skel.get_bone_parent(ids[0]))
		var stack := ids.duplicate()
		while not stack.is_empty() and not hit:
			var b: int = stack.pop_back()
			hit = pbones.has(b)
			for c in skel.get_bone_children(b):
				stack.append(c)
		if hit:
			out.append(e)
	return out


## the ROM poses: the rest, then per joint, axis and end a ramp from STEP_DEG-ish out to the end (inclusive). lims:
## {bone: {"bend": Vector2(lo, hi), ...}} overrides Body.lim (a test sweeping past the human range)
static func sweep(G: Body, entries: Array, step := STEP_DEG, lims := {}) -> Array:
	var poses := [{"angs": {}, "label": "rest", "entry": "", "axis": "", "deg": 0.0}]
	for e in entries:
		var b0: String = e["bones"][0]
		var lim: Dictionary = G.lim.get(b0, {})
		var over: Dictionary = lims.get(b0, {})
		for axis in ["bend", "side", "twist"]:
			var r: Vector2 = over.get(axis, lim.get(axis, Vector2.ZERO))
			for ext in [r.y, r.x]:
				if absf(ext) < MIN_EXT:
					continue
				var n := maxi(1, ceili(absf(ext) / step))
				for s in range(1, n + 1):
					var deg: float = ext * float(s) / float(n)
					var angs := {}
					for bn in e["bones"]:
						angs[bn] = Vector3(deg if axis == "bend" else 0.0, deg if axis == "side" else 0.0, deg if axis == "twist" else 0.0)
					poses.append({"angs": angs, "label": "%s %s %d°" % [region_name(e), AXIS_WORD[axis], roundi(deg)], "entry": e["id"], "axis": axis, "deg": deg})
	return poses


# ---------------------------------------------------------------- the parts

## a part's KMesh (mesh space): B23's own, else welded from its drawn surfaces
static func part_kmesh(mi: MeshInstance3D, skin: Skin) -> KMesh:
	if mi.has_meta("armour_kmesh"):
		return mi.get_meta("armour_kmesh")
	var srcs := []
	for si in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(si)
		srcs.append({"arr": arr, "tris": arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()})
	return BaseBody.to_kmesh(srcs, skin)


static func part_name(mi: Node) -> String:
	var lb := String(mi.get_meta("armour_label", ""))
	return String(mi.name) + (" (" + lb + ")" if lb != "" else "")


## per vertex 4 bind indices / weights as the GPU holds them (fit4 + canon; no weight: the nearest bind at 1)
static func infl4(k: KMesh, skin: Skin, sk: Skeleton3D) -> Array:
	var ws := BaseBody.weights_of(k, skin)
	var IB := PackedInt32Array()
	var IW := PackedFloat32Array()
	for v in k.verts.size():
		var d: Dictionary = BaseBody.canon(BaseBody.fit4(ws[v]))
		if d.is_empty():
			d = {BaseBody.nearest_bind(skin, sk, k.verts[v]) if sk != null else 0: 1.0}
		var bk := d.keys()
		bk.sort()
		for q in 4:
			IB.append(int(bk[q]) if q < bk.size() else 0)
			IW.append(float(d[bk[q]]) if q < bk.size() else 0.0)
	return [IB, IW]


static func fan(faces: Array) -> PackedInt32Array:
	var T := PackedInt32Array()
	for f in faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			T.append_array([fp[0], fp[i], fp[i + 1]])
	return T


# ---------------------------------------------------------------- the job (main thread)

## start a job: how = "rom" (the ROM test) or "scene" (the open scene). o: "parts" (MeshInstance3Ds; default B23's
## parts), "joints" (bone names of the F14 entries to sweep; default the relevant ones), "lims" (see sweep), "step"
## (deg). -> "" or what is missing
func begin_clash(m: Node, how: String, o := {}) -> String:
	var plist: Array = o.get("parts", ArmourFromBody.parts(m))
	plist = plist.filter(func(x): return is_instance_valid(x) and x is MeshInstance3D and (x as Node).is_inside_tree())
	if plist.is_empty():
		return "The clash check needs a part on the fighter: make one first (Model: armour from the body)"
	var skin := BaseBody.skin_of(m)
	if skin == null or m.wp.is_empty():
		return "The clash check needs a body with a skin: pick the mannequin"
	stop()
	mode = how
	opts = o
	var skel: Skeleton3D = m.skel
	var idx: Dictionary = m.bone_idx
	var bob := PackedInt32Array()
	for k in skin.get_bind_count():
		bob.append(SkinPaint.bind_bone(skin, skel, k))
	var pdata := []
	var pbones := {}
	for mi in plist:
		var k := part_kmesh(mi, skin)
		var inf := infl4(k, skin, skel)
		var IW: PackedFloat32Array = inf[1]
		var IB: PackedInt32Array = inf[0]
		for i in IB.size():
			if IW[i] > 0.0:
				pbones[bob[IB[i]]] = true
		pdata.append({"name": part_name(mi), "verts": k.verts, "IB": IB, "IW": IW, "T": fan(k.faces), "closed": k.is_closed()})
	var scene: Scene
	var poses := []
	var rel := relevant(skel, idx, pbones)
	if how == "rom":
		var G0 := Body.new()
		G0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var ents := rel
		if o.has("joints"):
			var want: Array = o["joints"]
			ents = DeformCheck.entries().filter(func(e): return want.has(e["bones"][0]) or want.has(e["id"]))
		poses = sweep(G0, ents, float(o.get("step", STEP_DEG)), o.get("lims", {}))
		var rs := RomSweep.new()
		rs.fps = ROM_FPS
		rs.body = m._ps().body
		rs.poses = poses
		scene = rs
	else:
		scene = m._ps()
		if scene.cards.is_empty():
			return "The clash check over the scene needs a scene: add a card first"
	# the body: its surfaces read one per slice ("read", below: one read is a GPU-side copy, all at once stalled the window
	# ~95 ms), the painted weights laid on, welded on the worker
	var rq := []
	var rest := BaseBody.rest_meshes(m)
	for j in m.pieces:
		var am := rest[m.pieces[j]] as ArrayMesh
		if am != null:
			for si in am.get_surface_count():
				rq.append([am, si])
	# the words of a site: the A19 rule at the rest pose (skeleton space), per bind the rest skinning matrix
	var rest_m := []
	for k in skin.get_bind_count():
		rest_m.append(skel.get_bone_global_rest(bob[k]) * skin.get_bind_pose(k))
	var names := PackedStringArray()
	for b in skel.get_bone_count():
		names.append(skel.get_bone_name(b))
	_skin_ref = skin
	_scene = scene
	_skel = skel
	_idx = idx
	_restore = func(): Overlays.pose_skeleton(skel, idx, m.B)
	_fps = float(scene.fps)
	_nf = maxi(1, roundi(scene.length() * _fps) + 1)
	_frames = []
	_angs = []
	slice_ms = []
	res = {}
	progress = 0.0
	_done = 0
	_per_frame = 0.0
	_G = Body.new()
	_G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_G.set_proportions(scene.body)
	_d = {"bob": bob, "gt": skel.global_transform, "k": clampf(float(m.S.dq_skin), 0.0, 1.0), "parts": pdata,
		"srcs": [], "rq": rq, "wps": (m.wp as Dictionary).get("surfs", []), "skin": skin, "mode": how, "poses": poses, "fps": _fps, "rest_m": rest_m,
		"seg": KMeshAnatomy.body_from_skeleton(skel)["seg"], "names": names, "rel": rel, "angs": _angs}
	state = "read"
	return ""


## the "read" slices (one surface or more per call, as the budget allows), then DeformScene's own
func step(budget_ms := BUDGET_MS) -> bool:
	if state != "read":
		return super.step(budget_ms)
	var t0 := Time.get_ticks_usec()
	var rq: Array = _d["rq"]
	var srcs: Array = _d["srcs"]
	while not rq.is_empty():
		var it: Array = rq.pop_front()
		read_into(srcs, it[0], it[1])
		if float(Time.get_ticks_usec() - t0) / 1000.0 * 2.0 >= budget_ms:
			break
	if rq.is_empty():
		for s in srcs:   # the painted weights (ROADMAP 72) where the weight-paint model holds the same vertices (as BaseBody.sources)
			for ws in _d["wps"]:
				if (ws["verts"] as PackedVector3Array) == (s["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
					s["arr"][Mesh.ARRAY_BONES] = ws["bones"]
					s["arr"][Mesh.ARRAY_WEIGHTS] = ws["w"]
					break
		state = "sample"
	slice_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	return false


## one surface into the source list as BaseBody.sources does it (a surface sharing another's vertices adds its triangles)
static func read_into(srcs: Array, am: ArrayMesh, si: int) -> void:
	var arr := am.surface_get_arrays(si)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var k := -1
	for q in srcs.size():
		if (srcs[q]["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array) == vs:
			k = q
			break
	if k < 0:
		srcs.append({"arr": arr, "tris": PackedInt32Array()})
		k = srcs.size() - 1
	var ix = arr[Mesh.ARRAY_INDEX]
	if ix != null:
		var t: PackedInt32Array = srcs[k]["tris"]
		t.append_array(ix)
		srcs[k]["tris"] = t


func running() -> bool:
	return state == "read" or super.running()


func _sampled(_f: int) -> void:
	_angs.append(_G.ang.duplicate())


## the whole job at once (tests, scripts): -> res
func clash_now(m: Node, how: String, o := {}) -> Dictionary:
	var err := begin_clash(m, how, o)
	if err != "":
		return {"err": err}
	while not step(1e9):
		OS.delay_msec(1)
	return res


# ---------------------------------------------------------------- the worker

func _work() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	_P = prep_clash(_d)
	var fr: Array = _d["frames"]
	_out = []
	_out.resize(fr.size())
	var gid := WorkerThreadPool.add_group_task(_one, fr.size(), -1, false, "rom clash")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var r := grade_clash(_P, _out, _d)
	r["ms"] = Time.get_ticks_msec() - t0
	r["mode"] = mode
	_P = {}
	return r


func _one(f: int) -> void:
	var M: Array = (_d["frames"] as Array)[f][0]
	var r := frame_clash(_P, M)
	_mx.lock()
	_out[f] = r
	_done += 1
	_mx.unlock()


## the body and the parts at rest: d = begin_clash's copy. -> P
static func prep_clash(d: Dictionary) -> Dictionary:
	var skin: Skin = d["skin"]
	var bk := BaseBody.to_kmesh(d["srcs"], skin)
	var V := bk.verts
	var nv := V.size()
	var ws := BaseBody.weights_of(bk, skin)
	var IB := PackedInt32Array()
	var IW := PackedFloat32Array()
	IB.resize(nv * 4)
	IW.resize(nv * 4)
	for v in nv:
		var dd: Dictionary = BaseBody.fit4(ws[v])
		var ks := dd.keys()
		ks.sort()
		for q in mini(4, ks.size()):
			IB[v * 4 + q] = int(ks[q])
			IW[v * 4 + q] = float(dd[ks[q]])
	var T := fan(bk.faces)
	var nt := T.size() / 3
	# the closed parts (connected components)
	var up := PackedInt32Array()
	up.resize(nv)
	for i in nv:
		up[i] = i
	for k in nt:
		var a := KMeshShrinkwrap._root(up, T[k * 3])
		for c in [1, 2]:
			var b := KMeshShrinkwrap._root(up, T[k * 3 + c])
			if a != b:
				up[b] = a
	var cid := {}
	var comps := []
	var vcomp := PackedInt32Array()
	vcomp.resize(nv)
	for i in nv:
		var r := KMeshShrinkwrap._root(up, i)
		if not cid.has(r):
			cid[r] = comps.size()
			comps.append({"verts": PackedInt32Array(), "tris": PackedInt32Array(), "binds": {}, "lo": Vector3.INF, "hi": -Vector3.INF})
		var c: Dictionary = comps[cid[r]]
		vcomp[i] = cid[r]
		var vl: PackedInt32Array = c["verts"]
		vl.append(i)
		c["verts"] = vl
		c["lo"] = (c["lo"] as Vector3).min(V[i])
		c["hi"] = (c["hi"] as Vector3).max(V[i])
		for q in 4:
			if IW[i * 4 + q] > 0.0:
				c["binds"][IB[i * 4 + q]] = true
	for k in nt:
		var c: Dictionary = comps[vcomp[T[k * 3]]]
		var tl: PackedInt32Array = c["tris"]
		tl.append(k)
		c["tris"] = tl
	return {"V": V, "IB": IB, "IW": IW, "T": T, "comps": comps, "vcomp": vcomp, "parts": d["parts"],
		"k": d["k"], "gt": d["gt"], "body_k": bk}


## skinned positions (world) of the listed verts (all when list is empty) at the skeleton-space matrices mats
static func skin_pts(V: PackedVector3Array, IB: PackedInt32Array, IW: PackedFloat32Array, list: PackedInt32Array, mats: Array, dq: Array, k: float, gt: Transform3D) -> PackedVector3Array:
	var n := list.size() if not list.is_empty() else V.size()
	var out := PackedVector3Array()
	out.resize(n)
	for j in n:
		var i := list[j] if not list.is_empty() else j
		var p := Vector3.ZERO
		if k > 0.0:
			p = DqSkin.skin_one(V[i], i, IB, IW, 4, mats, dq, k)[0]
		else:
			for q in 4:
				var x := IW[i * 4 + q]
				if x > 0.0:
					p += (mats[IB[i * 4 + q]] as Transform3D) * V[i] * x
		out[j] = gt * p
	return out


## THE WINDING NUMBER of the closed, outward-oriented triangles of sw about p along the ray p + t d (t > 0): +1 for every
## crossing that leaves (the ray along the outward normal), -1 for one that enters. B13's BVH and ray test, its oriented
## normals (tn); a sum, not B13's parity, so a point inside two overlapping parts (or a part folded into itself: the
## forearm pressed into the biceps) counts 2, not 0
static func winding(sw: KMeshShrinkwrap, p: Vector3, d: Vector3) -> int:
	var inv := Vector3(1.0 / d.x if d.x != 0.0 else INF, 1.0 / d.y if d.y != 0.0 else INF, 1.0 / d.z if d.z != 0.0 else INF)
	var w := 0
	var stack := PackedInt32Array([0])
	while not stack.is_empty():
		var nd := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var iv := sw._slab(nd, p, inv, 0.0, KMeshShrinkwrap.FAR)
		if not is_nan(iv.x) and not is_nan(iv.y) and iv.x > iv.y:
			continue
		var cn := sw.bcount[nd]
		if cn > 0:
			for j in range(sw.bstart[nd], sw.bstart[nd] + cn):
				var h := KMeshShrinkwrap.ray_tri(p, d, sw.tp[j * 3], sw.tp[j * 3 + 1], sw.tp[j * 3 + 2])
				if h.w > 0.0 and h.x > 0.0:
					w += 1 if d.dot(sw.tn[j]) > 0.0 else -1
			continue
		stack.append(sw.bright[nd])
		stack.append(sw.bleft[nd])
	return w


## inside the body (any of its closed parts, or several): a positive winding number on 2 of B13's 3 skew rays
static func inside(sw: KMeshShrinkwrap, p: Vector3) -> bool:
	var votes := 0
	for k in RAYS.size():
		if winding(sw, p, (RAYS[k] as Vector3).normalized()) > 0:
			votes += 1
			if votes >= 2:
				return true
		elif k - votes >= 1:
			return false
	return false


static func _box_meets(alo: Vector3, ahi: Vector3, blo: Vector3, bhi: Vector3) -> bool:
	return alo.x <= bhi.x and alo.y <= bhi.y and alo.z <= bhi.z and blo.x <= ahi.x and blo.y <= ahi.y and blo.z <= ahi.z


## the body vertex of a surface point of sw (triangle t in leaf order, barycentric b): the heaviest corner, global numbering
static func _site(sw: KMeshShrinkwrap, t: int, b: Vector3, gtri: PackedInt32Array, T: PackedInt32Array) -> int:
	var src := sw.tsrc[t]
	var g := gtri[src]
	var c := 0 if b.x >= b.y and b.x >= b.z else (1 if b.y >= b.z else 2)
	return T[g * 3 + c]


## ONE FRAME (any thread): M = world skin matrices per bind (H17's read_pose). -> {"clr": [per part PackedFloat32Array],
## "site": [per part PackedInt32Array: the body vertex of the nearest / exit point, -1 none], "pv": [per part
## PackedFloat32Array: depth into another part, 0 none], "pvo": [per part PackedInt32Array: that part], "comps": n}
static func frame_clash(P: Dictionary, Mw: Array) -> Dictionary:
	var gt: Transform3D = P["gt"]
	var gi := gt.affine_inverse()
	var mats := []
	for x in Mw:
		mats.append(gi * (x as Transform3D))
	var k: float = P["k"]
	var dq := DqSkin.dqs_of(mats) if k > 0.0 else []
	var parts: Array = P["parts"]
	var pos := []
	var plo := []
	var phi := []
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for part in parts:
		var pp := skin_pts(part["verts"], part["IB"], part["IW"], PackedInt32Array(), mats, dq, k, gt)
		var a := Vector3.INF
		var b := -Vector3.INF
		for p in pp:
			a = a.min(p)
			b = b.max(p)
		pos.append(pp)
		plo.append(a)
		phi.append(b)
		lo = lo.min(a)
		hi = hi.max(b)
	var grow := Vector3.ONE * (CAP + PAD)
	# the body's parts that can come near: conservative boxes
	var V: PackedVector3Array = P["V"]
	var T: PackedInt32Array = P["T"]
	var sel := PackedInt32Array()
	var comps: Array = P["comps"]
	for ci in comps.size():
		var c: Dictionary = comps[ci]
		var clo: Vector3 = c["lo"]
		var chi: Vector3 = c["hi"]
		var blo := Vector3.INF
		var bhi := -Vector3.INF
		for bnd in c["binds"]:
			var W: Transform3D = Mw[bnd]
			for corner in 8:
				var q := W * Vector3(chi.x if corner & 1 else clo.x, chi.y if corner & 2 else clo.y, chi.z if corner & 4 else clo.z)
				blo = blo.min(q)
				bhi = bhi.max(q)
		if _box_meets(blo - grow, bhi + grow, lo, hi):
			sel.append(ci)
	var out := {"clr": [], "site": [], "pv": [], "pvo": [], "comps": sel.size()}
	var sw: KMeshShrinkwrap = null
	var gtri := PackedInt32Array()   # sw's source triangles -> the body's
	if not sel.is_empty():
		var vl := PackedInt32Array()
		for ci in sel:
			vl.append_array(comps[ci]["verts"])
			gtri.append_array(comps[ci]["tris"])
		gtri.sort()
		var at := {}
		for j in vl.size():
			at[vl[j]] = j
		var faces := []
		for g in gtri:
			faces.append(PackedInt32Array([at[T[g * 3]], at[T[g * 3 + 1]], at[T[g * 3 + 2]]]))
		var sub := KMesh.new()
		sub.verts = skin_pts(V, P["IB"], P["IW"], vl, mats, dq, k, gt)
		sub.faces = faces
		sw = KMeshShrinkwrap.build(sub, Transform3D.IDENTITY, false)   # every triangle, oriented outward per closed part
	for pi in parts.size():
		var pp: PackedVector3Array = pos[pi]
		var clr := PackedFloat32Array()
		var site := PackedInt32Array()
		clr.resize(pp.size())
		site.resize(pp.size())
		clr.fill(CAP)
		site.fill(-1)
		if sw != null and sw.tri_count() > 0:
			var blo := sw.bmin[0]
			var bhi := sw.bmax[0]
			var hint := -1
			for i in pp.size():
				var p := pp[i]
				var ins := p.x >= blo.x and p.y >= blo.y and p.z >= blo.z and p.x <= bhi.x and p.y <= bhi.y and p.z <= bhi.z and inside(sw, p)
				var hn := sw.nearest(p, 0.0 if ins else CAP, hint)
				if hn.is_empty():
					continue
				hint = hn["t"]
				clr[i] = -float(hn["d"]) if ins else float(hn["d"])
				site[i] = _site(sw, hn["t"], hn["b"], gtri, T)
		out["clr"].append(clr)
		out["site"].append(site)
	# part against part
	var psw := {}
	for pi in parts.size():
		var pv := PackedFloat32Array()
		var pvo := PackedInt32Array()
		pv.resize((pos[pi] as PackedVector3Array).size())
		pvo.resize(pv.size())
		pvo.fill(-1)
		out["pv"].append(pv)
		out["pvo"].append(pvo)
	for a in parts.size():
		for b in parts.size():
			if a == b or not _box_meets(plo[a], phi[a], plo[b], phi[b]):
				continue
			if not psw.has(b):
				var kb := KMesh.new()
				kb.verts = pos[b]
				var fb := []
				var Tb: PackedInt32Array = parts[b]["T"]
				for t in range(0, Tb.size(), 3):
					fb.append(PackedInt32Array([Tb[t], Tb[t + 1], Tb[t + 2]]))
				kb.faces = fb
				psw[b] = KMeshShrinkwrap.build(kb, Transform3D.IDENTITY, false)   # (oriented outward per closed part)
			var sb: KMeshShrinkwrap = psw[b]
			var pa: PackedVector3Array = pos[a]
			var pv: PackedFloat32Array = out["pv"][a]
			var pvo: PackedInt32Array = out["pvo"][a]
			if bool(parts[b]["closed"]):
				for i in pa.size():
					var p := pa[i]
					if p.x < plo[b].x or p.y < plo[b].y or p.z < plo[b].z or p.x > phi[b].x or p.y > phi[b].y or p.z > phi[b].z:
						continue
					if not inside(sb, p):
						continue
					var h := sb.nearest(p)
					if not h.is_empty() and float(h["d"]) > EPS_IN and float(h["d"]) > pv[i]:
						pv[i] = h["d"]
						pvo[i] = b
			else:
				var Ta: PackedInt32Array = parts[a]["T"]
				var seen := {}
				for t in range(0, Ta.size(), 3):
					for c in 3:
						var u := Ta[t + c]
						var w := Ta[t + (c + 1) % 3]
						var key := Vector2i(mini(u, w), maxi(u, w))
						if seen.has(key):
							continue
						seen[key] = true
						var e := pa[w] - pa[u]
						var L := e.length()
						if L < 1e-9:
							continue
						if sb.cast(pa[u], e / L, 0.0, L).is_empty():
							continue
						var du := float(sb.nearest(pa[u])["d"])
						var dw := float(sb.nearest(pa[w])["d"])
						var dd := maxf(minf(du, dw), EPS_IN * 2.0)
						for vv in [u, w]:
							if dd > pv[vv]:
								pv[vv] = dd
								pvo[vv] = b
	return out


# ---------------------------------------------------------------- grading

## the words of a body site: its A19 tag at the rest pose ("the left forearm flexors"), else its region
static func site_words(P: Dictionary, d: Dictionary, v: int) -> String:
	if v < 0:
		return "the body"
	var IB: PackedInt32Array = P["IB"]
	var IW: PackedFloat32Array = P["IW"]
	var V: PackedVector3Array = P["V"]
	var rm: Array = d["rest_m"]
	var p := Vector3.ZERO
	var bw := -1.0
	var bb := 0
	for q in 4:
		var x := IW[v * 4 + q]
		if x > 0.0:
			p += (rm[IB[v * 4 + q]] as Transform3D) * V[v] * x
			if x > bw:
				bw = x
				bb = IB[v * 4 + q]
	var bone := String((d["names"] as PackedStringArray)[(d["bob"] as PackedInt32Array)[bb]])
	var tag := KMeshAnatomy.rule(bone, p, d["seg"])
	if tag == "":
		return "the " + DeformCheck.nice(bone)
	var side := " left" if tag.ends_with("_l") else (" right" if tag.ends_with("_r") else "")
	return "the%s %s" % [side, KMeshAnatomy.stem_of(tag).replace("_", " ")]


## "left elbow bend 140°" for a scene frame: of the joints that can move the parts against the body (relevant()), the
## one bent furthest from rest in that frame, at its largest angle
static func scene_words(d: Dictionary, f: int) -> String:
	var angs: Array = d["angs"]
	if f >= angs.size():
		return ""
	var a: Dictionary = angs[f]
	var best := 0.5
	var out := ""
	for e in d["rel"]:
		var v: Vector3 = a.get(e["bones"][0], Vector3.ZERO)
		var ax := 0 if absf(v.x) >= absf(v.y) and absf(v.x) >= absf(v.z) else (1 if absf(v.y) >= absf(v.z) else 2)
		if absf(v[ax]) > best:
			best = absf(v[ax])
			out = "%s %s %d°" % [region_name(e), ["bend", "side", "twist"][ax], roundi(v[ax])]
	return out


## the frames graded: -> {"frames": [per frame {"frame", "sev" (m: the deepest), "part", "v", "kind" ("body"/"part"/""),
## "n" (offending verts), "text"}], "worst": [the worst moments, worst first], "spans" (consecutive clashing frames, for
## the lane), "parts": [per part {"name", "minc", "minf", "red", "yellow", "green", "T"}], "warn": [B25 lines], "posed":
## {frame: [per part posed verts]}, "bpos": {frame: posed body}, "bodyT", "per": the raw frames, "fps", "labels"}
static func grade_clash(P: Dictionary, per: Array, d: Dictionary) -> Dictionary:
	var parts: Array = P["parts"]
	var fps: float = d["fps"]
	var poses: Array = d["poses"]
	var frames := []
	for f in per.size():
		var g: Dictionary = per[f]
		var best := 0.0
		var tot := 0.0
		var bpi := -1
		var bv := -1
		var kind := ""
		var n := 0
		for pi in parts.size():
			var clr: PackedFloat32Array = g["clr"][pi]
			var pv: PackedFloat32Array = g["pv"][pi]
			for i in clr.size():
				var dep := -clr[i]
				var off := false
				if dep > EPS_IN:
					off = true
					if dep > best:
						best = dep
						bpi = pi
						bv = i
						kind = "body"
				if pv[i] > EPS_IN:
					off = true
					if pv[i] > best:
						best = pv[i]
						bpi = pi
						bv = i
						kind = "part"
				if off:
					n += 1
					tot += maxf(dep, pv[i])
		frames.append({"frame": f, "sev": tot, "deep": best, "part": bpi, "v": bv, "kind": kind, "n": n, "text": describe_clash(P, d, per, f, bpi, bv, kind, best)})
	# worst first, one per moment (H17's rule: a listed frame takes its hill with it, at least SPACING)
	var order := range(frames.size())
	order.sort_custom(func(a, b): return float(frames[a]["sev"]) > float(frames[b]["sev"]) or (float(frames[a]["sev"]) == float(frames[b]["sev"]) and a < b))
	var worst := []
	var gap := maxi(1, roundi(SPACING * fps)) if mode_of(d) == "scene" else 1
	var taken := PackedByteArray()
	taken.resize(frames.size())
	for f in order:
		if float(frames[f]["sev"]) <= EPS_IN:
			break
		if taken[f] == 1:
			continue
		worst.append(frames[f])
		for dir in [-1, 1]:
			var kk: int = f
			while kk + dir >= 0 and kk + dir < frames.size() and (absi(kk + dir - f) < gap or float(frames[kk + dir]["sev"]) <= float(frames[kk]["sev"]) + 1e-9) and float(frames[kk + dir]["sev"]) > EPS_IN:
				if mode_of(d) == "rom" and String(poses[kk + dir]["entry"]) + String(poses[kk + dir]["axis"]) != String(poses[f]["entry"]) + String(poses[f]["axis"]):
					break   # a ROM moment is one joint's one ramp
				kk += dir
				taken[kk] = 1
		taken[f] = 1
		if worst.size() >= TOP:
			break
	var spans := []
	var f0 := -1
	for f in frames.size() + 1:
		var red := f < frames.size() and float(frames[f]["sev"]) > EPS_IN
		if red and f0 < 0:
			f0 = f
		elif not red and f0 >= 0:
			var wf := f0
			for kk in range(f0, f):
				if float(frames[kk]["sev"]) > float(frames[wf]["sev"]):
					wf = kk
			spans.append({"t0": float(f0) / fps, "t1": float(f - 1) / fps, "f0": f0, "f1": f - 1, "frame": wf, "kind": "clash",
				"reason": "armour cuts in: " + str(frames[wf]["text"]), "yellow": false})
			f0 = -1
	# B25: per vertex the minimum clearance over every frame and where
	var pout := []
	var warn := []
	for pi in parts.size():
		var nv: int = (parts[pi]["verts"] as PackedVector3Array).size()
		var minc := PackedFloat32Array()
		var minf := PackedInt32Array()
		minc.resize(nv)
		minf.resize(nv)
		minc.fill(INF)
		for f in per.size():
			var clr: PackedFloat32Array = per[f]["clr"][pi]
			for i in nv:
				if clr[i] < minc[i]:   # strict: the first frame of a tie
					minc[i] = clr[i]
					minf[i] = f
		var red := 0
		var yel := 0
		var lo := INF
		var lv := -1
		for i in nv:
			if minc[i] < 0.0:
				red += 1
			elif minc[i] <= WARN:
				yel += 1
			if minc[i] < lo:
				lo = minc[i]
				lv = i
		pout.append({"name": parts[pi]["name"], "minc": minc, "minf": minf, "red": red, "yellow": yel, "green": nv - red - yel, "T": parts[pi]["T"], "low": lo, "low_v": lv})
		if lv >= 0 and lo <= WARN:
			var f: int = minf[lv]
			warn.append("%s: %d of %d verts come within %s of the skin over the motion (%d inside); closest %s at frame %d%s" % [parts[pi]["name"],
				red + yel, nv, Units.len(WARN), red, ("%s inside" % Units.len(-lo)) if lo < 0.0 else Units.len(lo), f, _frame_words(P, d, per, f, pi, lv)])
	# what the overlay draws: the parts (and the body, for the model preview) at every listed frame
	var want := {}
	for w in worst:
		want[int(w["frame"])] = true
	for sp in spans:
		want[int(sp["frame"])] = true
	for pp in pout:
		if int(pp["low_v"]) >= 0:
			want[int((pp["minf"] as PackedInt32Array)[int(pp["low_v"])])] = true
	var posed := {}
	var bpos := {}
	var gt: Transform3D = P["gt"]
	var gi := gt.affine_inverse()
	for f in want:
		var mats := []
		for x in ((d["frames"] as Array)[f][0] as Array):
			mats.append(gi * (x as Transform3D))
		var dq := DqSkin.dqs_of(mats) if float(P["k"]) > 0.0 else []
		var ps := []
		for part in parts:
			ps.append(skin_pts(part["verts"], part["IB"], part["IW"], PackedInt32Array(), mats, dq, P["k"], gt))
		posed[f] = ps
		bpos[f] = skin_pts(P["V"], P["IB"], P["IW"], PackedInt32Array(), mats, dq, P["k"], gt)
	var labels := []
	for f in per.size():
		labels.append(String(poses[f]["label"]) if f < poses.size() else "")
	return {"frames": frames, "worst": worst, "spans": spans, "parts": pout, "warn": warn, "posed": posed, "bpos": bpos,
		"bodyT": P["T"], "per": per, "fps": fps, "labels": labels, "k": P["k"]}


static func mode_of(d: Dictionary) -> String:
	return String(d.get("mode", "scene"))


## ", left elbow bend 140°" (the ROM pose, or the joint between the part and the body site in a scene frame)
static func _frame_words(P: Dictionary, d: Dictionary, per: Array, f: int, pi: int, v: int) -> String:
	if mode_of(d) == "rom":
		var poses: Array = d["poses"]
		return (", " + String(poses[f]["label"])) if f < poses.size() else ""
	var w := scene_words(d, f)
	return (", " + w) if w != "" else ""


## "frame 22, left elbow bend 140°: armour_1 (biceps_l) 6.2 mm into the left forearm flexors (31 verts)"
static func describe_clash(P: Dictionary, d: Dictionary, per: Array, f: int, pi: int, v: int, kind: String, dep: float) -> String:
	if pi < 0:
		return "frame %d%s: clear" % [f, (", " + String((d["poses"] as Array)[f]["label"])) if mode_of(d) == "rom" and f < (d["poses"] as Array).size() else ""]
	var part: Dictionary = P["parts"][pi]
	var into := ""
	if kind == "part":
		into = "into " + String(P["parts"][(per[f]["pvo"][pi] as PackedInt32Array)[v]]["name"])
	else:
		into = "into " + site_words(P, d, (per[f]["site"][pi] as PackedInt32Array)[v])
	return "frame %d%s: %s %.1f mm %s" % [f, _frame_words(P, d, per, f, pi, v), part["name"], dep * 1000.0, into]


## B25's colour of a clearance: green past WARN, yellow 0..WARN, red inside
static func heat(c: float) -> Color:
	return Color(0.95, 0.12, 0.1) if c < 0.0 else (Color(0.98, 0.85, 0.1) if c <= WARN else Color(0.2, 0.8, 0.3))
