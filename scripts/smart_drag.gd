## smart_drag.gd - SMART DRAG (ROADMAP I12). Dragging one joint moves the rest of the body the way YOUR poses move together.
## LEARN   every pose in poses/ (+ poses/lib) and every card of every scene in scenes/ is one sample: the vector of all joint
##         angles (bend, side, twist per Body.ORDER joint, deg). The mean is taken off (the body's mean pose) and the principal
##         directions of the rest are found: the Gram matrix of the samples (N x N, N ~ 100 against 162 angles, so the dual
##         form is the cheap one) by power iteration with deflation. The first k directions are kept, k the smallest count that
##         explains >= VAR_GOAL (85 %) of the total variance. Read only: poses/ and scenes/ are never written; the model is
##         cached in user:// (cache_path; a test uses its own) and rebuilt when a source file's name or modified time changes.
## FOLLOW  the dragged chain C (the joints the drag itself turns: one joint, or an arm / leg for a hand / foot) changes by d
##         (deg, from the drag's start). The model is the Gaussian N(0, S), S = V diag(lambda) V^T (the top-k components), so
##         the other joints' conditional mean given d is   dx = S_oC (S_CC + eps I)^-1 d,   eps = 1 deg^2 + 2 % of the mean
##         variance of C (a ridge: a direction nobody in the library ever used must not blow up). Each follower goes to
##         ang0 + follow * dx (follow = the 'follow strength', default 0.6; one joint is moved at most MAX_FOLLOW deg), clamped
##         by its joint limits. The gain S_oC (S_CC + eps I)^-1 is computed ONCE per drag (begin); a mouse move is one small
##         matrix-vector product.
## PLANT   the feet on the floor at the drag's start are put back (leg IK, position and orientation) after every move, and the
##         centre of mass is kept over the support polygon (Balance): if either fails the follow is halved until it holds.
class_name SmartDrag
extends RefCounted

const CACHE := "user://smart_drag_model.json"
const VAR_GOAL := 0.85
const MAX_K := 40
const RIDGE_ABS := 1.0
const RIDGE_REL := 0.02
const MAX_FOLLOW := 45.0       # deg: no follower is moved further than this by a drag
const FOOT_TOL := 0.003        # m: a planted foot is put back to within 3 mm (the bar of the test is 1 cm)
const POSE_DIRS := ["res://poses/", "res://poses/lib/"]
const SCENE_DIRS := ["res://scenes/"]
const FEET := {"_l": "foot_l", "_r": "foot_r"}
const LEG := {"_l": ["thigh_l", "calf_l", "foot_l", "ball_l"], "_r": ["thigh_r", "calf_r", "foot_r", "ball_r"]}

var cache_path := CACHE
var pose_dirs: Array = POSE_DIRS
var scene_dirs: Array = SCENE_DIRS
var mean := PackedFloat64Array()
var comps: Array = []          # k x PackedFloat64Array(D): the principal directions (unit length)
var lam := PackedFloat64Array()  # their variances (deg^2)
var n := 0                      # samples
var total_var := 0.0
var sig := ""                   # what the model was built from
var from_cache := false
var last_ms := 0.0
var _oi := {}


func _init() -> void:
	for i in Body.ORDER.size():
		_oi[Body.ORDER[i]] = i


func dims() -> int:
	return Body.ORDER.size() * 3


func k() -> int:
	return comps.size()


func explained() -> float:
	var s := 0.0
	for v in lam:
		s += v
	return s / total_var if total_var > 0.0 else 0.0


func ready_model() -> bool:
	return comps.size() > 0


# ---- the samples ----------------------------------------------------------------------------------------------------

## every pose / card as a full angle vector, and the signature of the files they came from
func collect() -> Dictionary:
	var out := []
	var sg := PackedStringArray()
	for dir in pose_dirs:
		for fn in DirAccess.get_files_at(dir):
			if fn.ends_with(".json"):
				var path: String = String(dir) + fn
				sg.append("%s@%d" % [path, FileAccess.get_modified_time(path)])
				var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
				if d is Dictionary and (d as Dictionary).get("joints") is Dictionary:
					out.append(NextPose.full_of_pose(d))
	for dir in scene_dirs:
		for fn in DirAccess.get_files_at(dir):
			if fn.ends_with(".json"):
				var path: String = String(dir) + fn
				sg.append("%s@%d" % [path, FileAccess.get_modified_time(path)])
				for c in NextPose.read_file(path):
					out.append(c["a"])
	sg.sort()
	return {"samples": out, "sig": str(hash("|".join(sg))) + ":" + str(sg.size())}


## load the cache if it is current, else read the sources and fit; true when ready
func refresh() -> bool:
	var c := collect()
	if ready_model() and sig == c["sig"]:
		return true
	if _load_cache(c["sig"]):
		return true
	fit(c["samples"])
	sig = c["sig"]
	_save_cache()
	return ready_model()


# ---- the model ------------------------------------------------------------------------------------------------------

## principal directions of the samples (PackedFloat32Array each); returns k
func fit(samples: Array) -> int:
	var t0 := Time.get_ticks_usec()
	comps = []
	lam = PackedFloat64Array()
	from_cache = false
	n = samples.size()
	var D := dims()
	mean = PackedFloat64Array()
	mean.resize(D)
	total_var = 0.0
	if n < 3:
		return 0
	for s in samples:
		for d in D:
			mean[d] += s[d]
	for d in D:
		mean[d] /= n
	var X: Array = []
	for s in samples:
		var r := PackedFloat64Array()
		r.resize(D)
		for d in D:
			r[d] = s[d] - mean[d]
		X.append(r)
	var G: Array = []
	var trace := 0.0
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		G.append(row)
	for i in n:
		var xi: PackedFloat64Array = X[i]
		for j in range(i, n):
			var xj: PackedFloat64Array = X[j]
			var s := 0.0
			for d in D:
				s += xi[d] * xj[d]
			G[i][j] = s
			G[j][i] = s
		trace += G[i][i]
	total_var = trace / float(n - 1)
	if trace < 1e-9:
		return 0
	var acc := 0.0
	for m in MAX_K:
		var u := PackedFloat64Array()
		u.resize(n)
		var nu := 0.0
		for i in n:
			u[i] = 1.0 + 0.37 * sin(float(i) * 1.7 + float(m) * 0.9)
			nu += u[i] * u[i]
		nu = sqrt(nu)
		for i in n:
			u[i] /= nu
		var mu := 0.0
		for it in 400:
			var w := PackedFloat64Array()
			w.resize(n)
			var nw := 0.0
			for i in n:
				var gi: PackedFloat64Array = G[i]
				var s := 0.0
				for j in n:
					s += gi[j] * u[j]
				w[i] = s
				nw += s * s
			nw = sqrt(nw)
			if nw < 1e-10 * trace:
				mu = 0.0
				break
			var diff := 0.0
			for i in n:
				w[i] /= nw
				diff += absf(w[i] - u[i])
			u = w
			mu = nw
			if diff < 1e-9:
				break
		if mu < 1e-8 * trace:
			break
		var v := PackedFloat64Array()
		v.resize(D)
		for i in n:
			var xi: PackedFloat64Array = X[i]
			var ui := u[i]
			for d in D:
				v[d] += ui * xi[d]
		var inv := 1.0 / sqrt(mu)
		for d in D:
			v[d] *= inv
		comps.append(v)
		lam.append(mu / float(n - 1))
		acc += mu
		for i in n:
			var gi: PackedFloat64Array = G[i]
			for j in n:
				gi[j] -= mu * u[i] * u[j]
		if acc / trace >= VAR_GOAL:
			break
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return comps.size()


func _load_cache(want_sig: String) -> bool:
	if not FileAccess.file_exists(cache_path):
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
	if not (d is Dictionary) or String((d as Dictionary).get("sig", "")) != want_sig or int((d as Dictionary).get("dims", 0)) != dims():
		return false
	mean = PackedFloat64Array(d["mean"])
	comps = []
	for c in d["comps"]:
		comps.append(PackedFloat64Array(c))
	lam = PackedFloat64Array(d["lam"])
	n = int(d["n"])
	total_var = float(d["total_var"])
	sig = want_sig
	from_cache = true
	return comps.size() > 0


func _save_cache() -> void:
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f == null:
		return
	var cs := []
	for c in comps:
		cs.append(Array(c).map(func(x): return snappedf(x, 1e-6)))
	f.store_string(JSON.stringify({"dims": dims(), "sig": sig, "n": n, "total_var": total_var, "mean": Array(mean), "lam": Array(lam), "comps": cs}))


# ---- a drag ---------------------------------------------------------------------------------------------------------

## the joints a drag of this part turns by itself (the model conditions on them)
static func chain_of(part: String) -> Array:
	if part.begins_with("hand_"):
		var s := part.right(2)
		return ["clavicle" + s, "upperarm" + s, "lowerarm" + s]
	if part.begins_with("foot_"):
		var s := part.right(2)
		return ["thigh" + s, "calf" + s]
	if part.begins_with("upperarm_"):
		return ["clavicle_" + part.right(1), part]   # the shoulder rhythm moves the collarbone with the arm
	return [part]


## Gaussian conditioning: for the chain's 3c angles, the gain columns (one PackedFloat64Array(D) per conditioned angle)
func gains(cdims: PackedInt32Array) -> Array:
	var D := dims()
	var c := cdims.size()
	var kk := comps.size()
	# S_oC columns: S[:, cd] = sum_m lam_m V_m[:] V_m[cd]
	var sc: Array = []
	for a in c:
		var col := PackedFloat64Array()
		col.resize(D)
		for m in kk:
			var vm: PackedFloat64Array = comps[m]
			var w: float = lam[m] * vm[cdims[a]]
			if absf(w) < 1e-12:
				continue
			for r in D:
				col[r] += w * vm[r]
		sc.append(col)
	var scc: Array = []
	var md := 0.0
	for a in c:
		var row := PackedFloat64Array()
		row.resize(c)
		for b in c:
			row[b] = (sc[a] as PackedFloat64Array)[cdims[b]]
		scc.append(row)
		md += row[a]
	var eps := RIDGE_ABS + RIDGE_REL * md / float(c)
	# invert (S_CC + eps I) by Gauss-Jordan
	var A: Array = []
	for a in c:
		var row := PackedFloat64Array()
		row.resize(2 * c)
		for b in c:
			row[b] = scc[a][b] + (eps if a == b else 0.0)
		row[c + a] = 1.0
		A.append(row)
	for col in c:
		var piv := col
		for r in range(col + 1, c):
			if absf(A[r][col]) > absf(A[piv][col]):
				piv = r
		var tmp: PackedFloat64Array = A[col]
		A[col] = A[piv]
		A[piv] = tmp
		var pv: float = A[col][col]
		for x in 2 * c:
			A[col][x] /= pv
		for r in c:
			if r != col:
				var f: float = A[r][col]
				if f != 0.0:
					for x in 2 * c:
						A[r][x] -= f * A[col][x]
	# gain column a = sum_b S[:, b] * inv[b][a]
	var out: Array = []
	for a in c:
		var g := PackedFloat64Array()
		g.resize(D)
		for b in c:
			var iv: float = A[b][c + a]
			if iv == 0.0:
				continue
			var sb: PackedFloat64Array = sc[b]
			for r in D:
				g[r] += sb[r] * iv
		out.append(g)
	return out


## the press: what a drag of `part` is measured against. locked = joints that never follow. Returns {} when there is no model
func begin(B: Body, part: String, locked := []) -> Dictionary:
	if not ready_model():
		return {}
	var chain := chain_of(part)
	var cdims := PackedInt32Array()
	var skip := {}
	for j in chain:
		if not _oi.has(j):
			return {}
		skip[j] = true
		for a in 3:
			cdims.append(int(_oi[j]) * 3 + a)
	for j in locked:
		skip[j] = true
	var feet := {}
	for sd in FEET:
		if chain.has("thigh" + sd):
			continue   # the dragged leg is not planted
		if Balance.footprint(B, sd).size() > 0:
			var fn: String = FEET[sd]
			feet[sd] = {"p": B.P[fn], "g": B.G[fn]}
			for j in LEG[sd]:
				skip[j] = true
	var foll := []
	for j in Body.ORDER:
		if not skip.has(j):
			foll.append(j)
	var bal := Balance.read(B)
	return {"part": part, "chain": chain, "cdims": cdims, "gain": gains(cdims), "ang0": B.ang.duplicate(), "feet": feet,
		"followers": foll, "floor": minf(float(bal["margin"]), 0.0), "scale": 1.0, "miss": 0.0}


## one mouse move: the followers go to ang0 + follow * dx; the feet are put back; the balance is held. Returns the scale of
## the follow that held (1 = all of it)
func apply(B: Body, st: Dictionary, follow: float) -> float:
	if st.is_empty():
		return 0.0
	var t0 := Time.get_ticks_usec()
	var ang0: Dictionary = st["ang0"]
	var cd: PackedInt32Array = st["cdims"]
	var gain: Array = st["gain"]
	var D := dims()
	var delta := PackedFloat64Array()
	delta.resize(cd.size())
	for a in cd.size():
		var j: String = Body.ORDER[cd[a] / 3]
		delta[a] = float((B.ang[j] as Vector3)[cd[a] % 3]) - float((ang0[j] as Vector3)[cd[a] % 3])
	var dx := PackedFloat64Array()
	dx.resize(D)
	for a in cd.size():
		var da := delta[a]
		if absf(da) < 1e-9:
			continue
		var g: PackedFloat64Array = gain[a]
		for r in D:
			dx[r] += g[r] * da
	var foll: Array = st["followers"]
	var s := 1.0
	var tries := 0
	while true:
		for j in foll:
			var o: Vector3 = ang0[j]
			var i := int(_oi[j]) * 3
			var v := o
			for a in 3:
				v[a] = o[a] + clampf(follow * s * dx[i + a], -MAX_FOLLOW, MAX_FOLLOW)
			B.ang[j] = B.clamp_ang(j, v)
		B.fk()
		var miss := plant(B, st)
		st["miss"] = miss
		var held := miss <= FOOT_TOL
		if held and not (st["feet"] as Dictionary).is_empty() and s > 0.0:
			held = float(Balance.read(B)["margin"]) >= float(st["floor"]) - 1e-4
		if held or tries >= 5:
			break
		tries += 1
		s = 0.0 if tries >= 5 else s * 0.5
	st["scale"] = s
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return s


## the planted feet back on their spots (position and world orientation, as PartDrag does for a body move); the worst miss (m)
func plant(B: Body, st: Dictionary) -> float:
	var worst := 0.0
	var feet: Dictionary = st["feet"]
	var was_fast := B.fast
	B.fast = true   # limits only while the legs are put back: the contact search costs 10x and a planted foot is not a contact question
	for sd in feet:
		var fl: String = FEET[sd]
		var f: Dictionary = feet[sd]
		B.reach(fl, f["p"])
		var gc: Quaternion = B.G[B.parent[fl]]
		var v := B.decompose(fl, (gc.inverse() * (f["g"] as Quaternion)).normalized())
		var old: Vector3 = B.ang[fl]
		while v.z - old.z > 180.0:
			v.z -= 360.0
		while v.z - old.z < -180.0:
			v.z += 360.0
		B.set_ang(fl, v)
		worst = maxf(worst, ((B.P[fl] as Vector3) - (f["p"] as Vector3)).length())
	B.fast = was_fast
	return worst
