## DEFORMATION GRADED OVER THE SCENE (ROADMAP_400 H17 ★): every frame of the open scene (sampled at the scene's rate, 30 or 60
## Hz) skinned on the body as weighted, and graded per joint region against rest; the worst frames listed worst first, like the
## human check ("frame 41: left elbow -18% volume, forearm skin stretched 1.6x"). F14 (DeformCheck) sweeps each joint through its
## RANGE; this grades what THIS animation does with it. Same skinning (linear blend, SkinPaint's weights in memory), same joints
## (DeformCheck.entries(): shoulder, elbow, wrist, hip, knee both sides, spine, neck), same rest (the zero pose on the scene's body).
##
## THE REGION of a joint: the triangles whose main bone (most weight over the three corners) is the joint's bone or the bone above
## it, and whose rest centre is within L of the joint, L = half the joint bone's length, 7..14 cm (the elbow: ~12 cm each way,
## the crease and the blend band; never the hand). A18's regions (kmesh_body.gd) are per BONE (forearm, upper arm); a joint's
## region straddles two of them, so it is built here from the same rule (nearest bone = most weight) at the joint.
## VOLUME, a local proxy for the signed volume of the region's closed-off part: each triangle and the joint centre make a
## tetrahedron, the region's volume is their signed sum (the divergence-theorem volume of the region closed by coning its cut
## edges to the joint: the cone's own faces add nothing, they pass through the apex). Each apex is a point the triangle's own
## bone carries rigidly: the joint the bone turns about (its origin) for the joint's bone, the joint itself for the bone above
## (it sits still in that bone's frame). So rest = 0 exactly and a rigid move of either side changes nothing: only the skin
## the weights blend moves the number. A linear blend of two rotations about the joint is shorter than either (the matrix
## average shrinks), so the blended skin comes in towards the joint: the elbow-crease collapse and the candy wrapper. The
## loss is V / V_rest - 1 (a ratio: the winding's sign cancels). Measured on the mannequin: left elbow -0.9% at 26 deg,
## -9% at 90, -17% at 150.
## STRETCH / COMPRESSION: per triangle, the singular values of the in-plane deformation (posed edges against the rest
## triangle's 2D frame): the larger one is the stretch (2.3x), the smaller one the compression (0.4x); per region the worst of
## each, with the bone of the triangle where it is (triangles with an edge under 2 mm at rest are skipped: their ratio is noise).
## BARS (a frame is red where any region passes one): volume lost >= 15%, or skin stretched >= 2x (between F14's "bends, with
## losses" at 1.45x and its "will break" at 2.5x). Compression is reported, never a bar on its own: skin folds on the inside of
## every bend (F14's reasoning). sev = the larger of loss / 15% and (stretch - 1) / 1: 1.0 = at a bar.
## OFF THE UI THREAD: the frames are sampled on the main thread in slices of BUDGET_MS (Scene.apply on a scratch body, the
## skeleton posed and read, put back at the end of every slice: the window never shows it); the skinning and grading run on a
## Thread. step() is the per-frame entry; finish_now() runs the whole job at once (tests, the CLI).
class_name DeformScene
extends RefCounted

const VOL_BAR := 0.15
const STRETCH_BAR := 2.0
const MIN_EDGE := 0.002     # m
const L_MIN := 0.07         # m: the region's reach round its joint
const L_MAX := 0.14
const SPACING := 0.1        # s: two listed worst frames are at least this far apart (one moment, one line)
const TOP := 8
const BUDGET_MS := 6.0      # main-thread work per step(): far under one 60 Hz frame (16.7 ms)

var state := "idle"         # idle / sample / measure / done
var progress := 0.0
var res := {}               # the result (see grade(); + "ghosts", "T", "ms", "tris", "verts")
var slice_ms := []          # each step()'s main-thread time, ms (the UI stall)
var _d := {}                # what the worker reads: copied on the main thread, never written there after begin()
var _frames := []           # per frame [M (world skin matrices per bind), org (world bone origins)]
var _nf := 0
var _fps := 30.0
var _scene: Scene = null
var _skel: Skeleton3D = null
var _idx := {}
var _G: Body = null
var _restore := Callable()
var _thr: Thread = null
var _skin_ref: Skin = null
var _done := 0              # frames graded by the worker (written there, read for the progress)
var _per_frame := 0.0       # ms: the dearest frame sampled so far (Scene.apply + pose + read)


## the joints graded (DeformCheck's) with their words: "left elbow", "spine"
static func region_name(e: Dictionary) -> String:
	return (str(e["side"]) + " " if e["side"] != "" else "") + str(e["fam"])


## world skin matrices (one per bind) and world bone origins, for the skeleton as posed now
static func read_pose(skin: Skin, skel: Skeleton3D, bob: PackedInt32Array) -> Array:
	var gt := skel.global_transform
	var M := []
	for k in skin.get_bind_count():
		M.append(gt * skel.get_bone_global_pose(bob[k]) * skin.get_bind_pose(k))
	return [M, DeformCheck._origins(skel)]


## start a job on the scene (main thread; cheap: the heavy part is in step() slices and the worker).
## model = SkinPaint.read(...) (main.wp). restore puts the real body's pose back on the skeleton.
func begin(model: Dictionary, skel: Skeleton3D, idx: Dictionary, scene: Scene, restore: Callable) -> String:
	if model.is_empty() or model.get("skin") == null:
		return "Deformation over the scene needs a body with a skin: pick the mannequin"
	if scene.cards.is_empty():
		return "Deformation over the scene needs a scene: add a card first"
	stop()
	var skin: Skin = model["skin"]
	_skin_ref = skin
	_done = 0
	_per_frame = 0.0
	_scene = scene
	_skel = skel
	_idx = idx
	_restore = restore
	_fps = float(scene.fps)
	_nf = maxi(1, roundi(scene.length() * _fps) + 1)
	_frames = []
	slice_ms = []
	res = {}
	progress = 0.0
	_G = Body.new()
	_G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_G.set_proportions(scene.body)
	var bob := PackedInt32Array()
	for k in skin.get_bind_count():
		bob.append(SkinPaint.bind_bone(skin, skel, k))
	var nb := skel.get_bone_count()
	var parent := PackedInt32Array()
	var names := PackedStringArray()
	for b in nb:
		parent.append(skel.get_bone_parent(b))
		names.append(skel.get_bone_name(b))
	DeformCheck._pose(_G, skel, idx, {})   # the rest: the zero pose on the scene's body
	var r0 := read_pose(skin, skel, bob)
	restore.call()
	var org0: PackedVector3Array = r0[1]
	# each bone's segment ends at the child that continues the line from its parent (DeformCheck's rule)
	var child := PackedInt32Array()
	child.resize(nb)
	for b in nb:
		child[b] = -1
		var kids := skel.get_bone_children(b)
		if kids.is_empty():
			continue
		var d0 := (org0[b] - org0[parent[b]]) if parent[b] >= 0 else Vector3.UP
		if d0.length() < 1e-6:
			d0 = Vector3.UP
		var bdot := -2.0
		for c in kids:
			var dt := (org0[c] - org0[b]).normalized().dot(d0.normalized())
			if dt > bdot:
				bdot = dt
				child[b] = c
	var surfs := []
	for s in model["surfs"]:
		surfs.append({"verts": s["verts"], "bones": s["bones"], "w": s["w"], "per": s["per"], "tris": s["tris"]})
	_d = {"surfs": surfs, "M0": r0[0], "org0": org0, "child": child, "parent": parent, "names": names, "idx": idx.duplicate(), "bob": bob, "fps": _fps}
	state = "sample"
	return ""


## one slice of main-thread work (at most ~BUDGET_MS); true once the result is in `res`
func step(budget_ms := BUDGET_MS) -> bool:
	var t0 := Time.get_ticks_usec()
	match state:
		"sample":
			var skin: Skin = _skin_ref
			var bob: PackedInt32Array = _d["bob"]
			var posed := false
			while _frames.size() < _nf:
				var tf := Time.get_ticks_usec()
				_scene.apply(_G, float(_frames.size()) / _fps)
				Overlays.pose_skeleton(_skel, _idx, _G)
				posed = true
				_frames.append(read_pose(skin, _skel, bob))
				_per_frame = maxf(_per_frame, float(Time.get_ticks_usec() - tf) / 1000.0)
				# stop before a frame that would not fit (the dearest frame so far is the guess): a slice stays near the budget
				if float(Time.get_ticks_usec() - t0) / 1000.0 + _per_frame >= budget_ms:
					break
			if posed:
				_restore.call()   # the window never shows a sampled pose: the body is put back inside the slice
			progress = 0.5 * float(_frames.size()) / float(_nf)
			if _frames.size() >= _nf:
				_d["frames"] = _frames
				state = "measure"
				_thr = Thread.new()
				_thr.start(_work)
		"measure":
			progress = 0.5 + 0.5 * float(_done) / float(_nf)
			if not _thr.is_alive():
				res = _thr.wait_to_finish()
				_thr = null
				state = "done"
	slice_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	return state == "done"


## the whole job at once (tests, scripts): -> res
func finish_now(model: Dictionary, skel: Skeleton3D, idx: Dictionary, scene: Scene, restore: Callable) -> Dictionary:
	var err := begin(model, skel, idx, scene, restore)
	if err != "":
		return {"err": err}
	while not step(1e9):
		OS.delay_msec(1)
	return res


func running() -> bool:
	return state == "sample" or state == "measure"


func stop() -> void:
	if _thr != null:
		_thr.wait_to_finish()
		_thr = null
	if state != "done":
		state = "idle"


# ---------------------------------------------------------------- the worker (reads _d only)

func _work() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var P := prep(_d)
	var fr: Array = _d["frames"]
	var out := []
	for f in fr.size():
		out.append(measure(P, fr[f][0], fr[f][1]))
		_done = f + 1
	var r := grade(P, out, float(_d["fps"]))
	# the ghosts: the whole skin at every listed frame and at the worst frame of every red span
	var want := {}
	for w in r["worst"]:
		want[int(w["frame"])] = true
	for sp in r["spans"]:
		want[int(sp["frame"])] = true
	var gh := {}
	for f in want:
		gh[f] = ghost_data(P, fr[f][0], out[f])
	r["ghosts"] = gh
	r["ms"] = Time.get_ticks_msec() - t0
	r["T"] = P["T"]
	r["tris"] = P["T"].size() / 3
	r["verts"] = P["V"].size()
	return r


## the skin and the regions, at rest. d: begin()'s copy. -> P
static func prep(d: Dictionary) -> Dictionary:
	var per := 1
	for s in d["surfs"]:
		per = maxi(per, int(s["per"]))
	var V := PackedVector3Array()
	var IB := PackedInt32Array()
	var IW := PackedFloat32Array()
	var T := PackedInt32Array()
	for s in d["surfs"]:
		var off := V.size()
		var sv: PackedVector3Array = s["verts"]
		var sb: PackedInt32Array = s["bones"]
		var sw: PackedFloat32Array = s["w"]
		var sp: int = s["per"]
		V.append_array(sv)
		for i in sv.size():
			for q in per:
				IB.append(sb[i * sp + q] if q < sp else 0)
				IW.append(sw[i * sp + q] if q < sp else 0.0)
		for t in (s["tris"] as PackedInt32Array):
			T.append(t + off)
	var bob: PackedInt32Array = d["bob"]
	var M0: Array = d["M0"]
	var org0: PackedVector3Array = d["org0"]
	var child: PackedInt32Array = d["child"]
	var parent: PackedInt32Array = d["parent"]
	var idx: Dictionary = d["idx"]
	var nv := V.size()
	var rest := PackedVector3Array()
	rest.resize(nv)
	var all := PackedInt32Array()
	for i in nv:
		all.append(i)
	skin_into(rest, all, V, IB, IW, per, M0)
	# the regions
	var nt := T.size() / 3
	var tdom := PackedInt32Array()   # each triangle's main bone (skeleton index)
	tdom.resize(nt)
	for k in nt:
		var acc := {}
		for c in 3:
			var i := T[3 * k + c]
			for q in per:
				var x := IW[i * per + q]
				if x > 0.0:
					var b := bob[IB[i * per + q]]
					acc[b] = float(acc.get(b, 0.0)) + x
		var bb := -1
		var bw := -1.0
		for b in acc:
			if float(acc[b]) > bw or (float(acc[b]) == bw and int(b) < bb):
				bw = acc[b]
				bb = b
		tdom[k] = bb
	var regions := []
	var needm := {}
	for e in DeformCheck.entries():
		var ids := PackedInt32Array()
		var okk := true
		for bn in e["bones"]:
			if not idx.has(bn) or int(idx[bn]) < 0:
				okk = false
				break
			ids.append(int(idx[bn]))
		if not okk:
			continue
		var rb := {}
		for b in ids:
			rb[b] = true
		var par := parent[ids[0]]
		if par >= 0:
			rb[par] = true
		var jb := ids[0]
		var seg := org0[jb].distance_to(org0[child[jb]]) if child[jb] >= 0 else 0.1
		var L := clampf(0.5 * seg, L_MIN, L_MAX)
		var A := PackedInt32Array()     # the region's triangles: corners
		var AB := PackedInt32Array()    # per triangle: the apex joint, the main bone
		var EI := PackedFloat32Array()  # the rest 2D frame's inverse (4) per triangle; all zero = no stretch reading
		var v0 := 0.0
		for k in nt:
			if not rb.has(tdom[k]):
				continue
			var a := rest[T[3 * k]]
			var b2 := rest[T[3 * k + 1]]
			var c2 := rest[T[3 * k + 2]]
			var ctr := (a + b2 + c2) / 3.0
			var near := INF
			for j in ids:
				near = minf(near, ctr.distance_to(org0[j]))
			if near > L:
				continue
			# the cone's apex is a point the triangle's own bone carries rigidly: the joint the bone turns about (its origin)
			# for a joint bone, the region's first joint for the bone above (it sits still in that bone's frame)
			var jn := tdom[k] if ids.has(tdom[k]) else ids[0]
			A.append(T[3 * k])
			A.append(T[3 * k + 1])
			A.append(T[3 * k + 2])
			AB.append(jn)        # the cone's apex
			AB.append(tdom[k])   # the triangle's main bone (named in the stretch words)
			v0 += _tet(a, b2, c2, org0[jn])
			var e1 := b2 - a
			var e2 := c2 - a
			var n := e1.cross(e2)
			if e1.length() < MIN_EDGE or e2.length() < MIN_EDGE or (c2 - b2).length() < MIN_EDGE or n.length() < 1e-12:
				EI.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
			else:
				var u := e1.normalized()
				var w := n.normalized().cross(u)
				# rest edges in the frame (u, w): e1 = (|e1|, 0), e2 = (e2.u, e2.w); the inverse of [[e1u, e2u], [0, e2w]]
				var p := e1.length()
				var q2 := e2.dot(u)
				var r2 := e2.dot(w)
				EI.append_array(PackedFloat32Array([1.0 / p, -q2 / (p * r2), 0.0, 1.0 / r2]))
			for c in 3:
				needm[T[3 * k + c]] = true
		regions.append({"id": e["id"], "fam": e["fam"], "side": e["side"], "name": region_name(e), "A": A, "AB": AB, "EI": EI, "v0": v0 / 6.0, "L": L})
	var need := PackedInt32Array(needm.keys())
	need.sort()
	return {"V": V, "IB": IB, "IW": IW, "per": per, "T": T, "rest": rest, "regions": regions, "need": need, "names": d["names"]}


## cur[i] = sum of w * M[bind] * V[i] over the vertex's influences, for i in list
static func skin_into(cur: PackedVector3Array, list: PackedInt32Array, V: PackedVector3Array, IB: PackedInt32Array, IW: PackedFloat32Array, per: int, M: Array) -> void:
	for i in list:
		var v := V[i]
		var p := Vector3.ZERO
		for q in per:
			var x := IW[i * per + q]
			if x > 0.0:
				p += (M[IB[i * per + q]] as Transform3D) * v * x
		cur[i] = p


## six times the signed volume of the tetrahedron (a, b, c, o)
static func _tet(a: Vector3, b: Vector3, c: Vector3, o: Vector3) -> float:
	return (a - o).dot((b - o).cross(c - o))


## one frame: per region {"vol" (fraction, - = lost), "smax", "smax_b", "smin", "smin_b", "sev", "why"}
static func measure(P: Dictionary, M: Array, org: PackedVector3Array) -> Array:
	var cur := PackedVector3Array()
	cur.resize((P["V"] as PackedVector3Array).size())
	skin_into(cur, P["need"], P["V"], P["IB"], P["IW"], P["per"], M)
	var out := []
	for R in P["regions"]:
		var A: PackedInt32Array = R["A"]
		var AB: PackedInt32Array = R["AB"]
		var EI: PackedFloat32Array = R["EI"]
		var vol := 0.0
		var smax := 1.0
		var smin := 1.0
		var bmax := -1
		var bmin := -1
		for k in A.size() / 3:
			var a := cur[A[3 * k]]
			var b := cur[A[3 * k + 1]]
			var c := cur[A[3 * k + 2]]
			vol += _tet(a, b, c, org[AB[2 * k]])
			var i00 := EI[4 * k]
			if i00 == 0.0:
				continue
			var f1 := b - a
			var f2 := c - a
			var d1 := f1 * i00   # column 1 of [f1 f2] * Einv (Einv[1][0] = 0)
			var d2 := f1 * EI[4 * k + 1] + f2 * EI[4 * k + 3]
			var g11 := d1.dot(d1)
			var g12 := d1.dot(d2)
			var g22 := d2.dot(d2)
			var hm := 0.5 * (g11 + g22)
			var dd := sqrt(maxf(0.0, 0.25 * (g11 - g22) * (g11 - g22) + g12 * g12))
			var s1 := sqrt(hm + dd)
			var s2 := sqrt(maxf(0.0, hm - dd))
			if s1 > smax:
				smax = s1
				bmax = AB[2 * k + 1]
			if s2 < smin:
				smin = s2
				bmin = AB[2 * k + 1]
		var v0: float = R["v0"]
		var fv := (vol / 6.0) / v0 - 1.0 if absf(v0) > 1e-12 else 0.0   # a ratio: the winding (Godot's faces are clockwise) cancels
		var sv := maxf(-fv / VOL_BAR, 0.0)
		var ss := (smax - 1.0) / (STRETCH_BAR - 1.0)
		out.append({"vol": fv, "smax": smax, "smax_b": bmax, "smin": smin, "smin_b": bmin, "sev": maxf(sv, ss), "why": "vol" if sv >= ss else "stretch"})
	return out


## the per-frame grades -> {"frames": [per frame: {"sev", "r" (worst region index), "text"}], "worst": [the TOP worst moments],
## "spans": [{"t0", "t1", "frame", "kind", "reason", "yellow"}] (consecutive red frames), "regions": [names], "per": the raw
## per-frame per-region grades, "fps"}
static func grade(P: Dictionary, per_frame: Array, fps: float) -> Dictionary:
	var regs := []
	for R in P["regions"]:
		regs.append(R["name"])
	var names: PackedStringArray = P["names"]
	var frames := []
	for f in per_frame.size():
		var g: Array = per_frame[f]
		var wr := -1
		var ws := -1.0
		for r in g.size():
			if float(g[r]["sev"]) > ws:
				ws = g[r]["sev"]
				wr = r
		frames.append({"frame": f, "sev": ws, "r": wr, "text": describe(f, regs[wr], g[wr], names) if wr >= 0 else "frame %d" % f})
	# worst first, one line per moment: a listed frame takes its whole hill with it (the frames on either side while the grade
	# keeps falling away from it, and at least SPACING), so the list is the animation's separate peaks, not one peak's neighbours
	var order := range(frames.size())
	order.sort_custom(func(a, b): return float(frames[a]["sev"]) > float(frames[b]["sev"]) or (float(frames[a]["sev"]) == float(frames[b]["sev"]) and a < b))
	var worst := []
	var gap := maxi(1, roundi(SPACING * fps))
	var taken := PackedByteArray()
	taken.resize(frames.size())
	for f in order:
		if taken[f] == 1:
			continue
		worst.append(frames[f])
		for dir in [-1, 1]:
			var k: int = f
			while k + dir >= 0 and k + dir < frames.size() and (absi(k + dir - f) < gap or float(frames[k + dir]["sev"]) <= float(frames[k]["sev"]) + 1e-9):
				k += dir
				taken[k] = 1
		taken[f] = 1
		if worst.size() >= TOP:
			break
	var spans := []
	var f0 := -1
	for f in frames.size() + 1:
		var red := f < frames.size() and float(frames[f]["sev"]) >= 1.0
		if red and f0 < 0:
			f0 = f
		elif not red and f0 >= 0:
			var wf := f0
			for k in range(f0, f):
				if float(frames[k]["sev"]) > float(frames[wf]["sev"]):
					wf = k
			spans.append({"t0": float(f0) / fps, "t1": float(f - 1) / fps, "f0": f0, "f1": f - 1, "frame": wf, "kind": "deforms",
				"reason": "skin past a bar: " + str(frames[wf]["text"]), "yellow": false})
			f0 = -1
	return {"frames": frames, "worst": worst, "spans": spans, "regions": regs, "per": per_frame, "fps": fps}


## "frame 41: left elbow -18% volume, forearm skin stretched 1.6x, upper arm skin squashed to 0.4x"
static func describe(f: int, region: String, g: Dictionary, names: PackedStringArray) -> String:
	var v := float(g["vol"])
	var s := "frame %d: %s %s%.0f%% volume" % [f, region, "+" if v > 0.005 else ("-" if v < -0.005 else ""), absf(100.0 * v)]
	if int(g["smax_b"]) >= 0 and float(g["smax"]) >= 1.05:
		s += ", %s skin stretched %.1fx" % [DeformCheck.nice(names[int(g["smax_b"])]), float(g["smax"])]
	if int(g["smin_b"]) >= 0 and float(g["smin"]) <= 0.95:
		s += ", %s skin squashed to %.1fx" % [DeformCheck.nice(names[int(g["smin_b"])]), float(g["smin"])]
	return s


## the whole skin at one frame, pushed 3 mm out along its normals (so it does not fight the body's own skin), with each
## vertex's severity (its worst region's, 0 outside every region): {"pos", "sev"}
static func ghost_data(P: Dictionary, M: Array, g: Array) -> Dictionary:
	var V: PackedVector3Array = P["V"]
	var T: PackedInt32Array = P["T"]
	var cur := PackedVector3Array()
	cur.resize(V.size())
	var all := PackedInt32Array()
	for i in V.size():
		all.append(i)
	skin_into(cur, all, V, P["IB"], P["IW"], P["per"], M)
	var nrm := PackedVector3Array()
	nrm.resize(V.size())
	var one := PackedVector3Array()   # one face's own normal per vertex: where the faces round a vertex cancel (a pole on a seam)
	one.resize(V.size())
	for k in T.size() / 3:
		var a := cur[T[3 * k]]
		var n := (cur[T[3 * k + 1]] - a).cross(cur[T[3 * k + 2]] - a)
		for c in 3:
			nrm[T[3 * k + c]] += n
			if one[T[3 * k + c]] == Vector3.ZERO:
				one[T[3 * k + c]] = n
	var sev := PackedFloat32Array()
	sev.resize(V.size())
	for r in (P["regions"] as Array).size():
		var A: PackedInt32Array = P["regions"][r]["A"]
		var s: float = g[r]["sev"]
		for i in A:
			sev[i] = maxf(sev[i], s)
	for i in V.size():
		cur[i] += (nrm[i] if nrm[i].length_squared() > 1e-14 else one[i]).normalized() * 0.003
	return {"pos": cur, "sev": sev}
