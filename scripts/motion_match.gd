## MOTION MATCHING (ROADMAP 33): the frame database built from the user's scenes, the feature vector, the search,
## the coverage report and the preview player. Read only: scenes/ and moves/ are read, never written.
##
## FEATURES (per frame; root-relative; metres, seconds; Y up, the hero faces +Z, +X is the hero's left):
##   the root = the pelvis's floor point (the scene's offset, x and z); heading = the pelvis's forward (+Z) on the floor.
##   foot_pos 6   each ball (toe base) in the root frame
##   foot_vel 6   each ball's velocity in the root frame (central difference)
##   hip_vel  3   the pelvis's velocity in the root frame
##   traj_pos 6   the root's position at +0.33 / +0.67 / +1.0 s, in the root frame (x, z)
##   traj_dir 6   the root's facing at the same three times, in the root frame (x, z)
## Clavet (2016, "Motion Matching and the Road to Next-Gen Speed", GDC) builds the vector this way: foot positions and
## velocities, hip velocity, a future trajectory. Buttner (2015) is the reference the brief names for the same design;
## its paper was not read for this build, so no detail is taken from it.
##
## NORMALISATION: each dimension is (x - mean) / sd over the database. The five groups are averaged with equal weight,
## so a COST is an RMS distance in standard deviations: 0 = identical, 1.0 = a typical feature one sd away.
## GOOD = 1.0: a query whose best frame is further than that has no good match (a gap in the coverage report).
class_name MotionMatch
extends RefCounted

const HORIZON := [0.33, 0.67, 1.0]   # s: the future trajectory's three points (Clavet 2016)
const GOOD := 1.0                    # cost (RMS in sd) above which a query has no good match
const SEARCH_EVERY := 0.1            # s between two searches in the preview
const XFADE := 0.2                   # s: the cross-fade between the old and the new frame
const DIM := 27
const GROUPS := ["foot_pos", "foot_vel", "hip_vel", "traj_pos", "traj_dir"]
const TRAJ := ["traj_pos", "traj_dir"]
const OFF := {"foot_pos": 0, "foot_vel": 6, "hip_vel": 12, "traj_pos": 15, "traj_dir": 21}
const NDIM := {"foot_pos": 6, "foot_vel": 6, "hip_vel": 3, "traj_pos": 6, "traj_dir": 6}
# coverage: the trajectory alone (the pose is not part of a target); directions every 45 deg, these speeds (m/s)
const COVER_SPEEDS := [0.5, 1.0, 1.5, 2.0, 3.0]
# which weighting a search uses: all five groups (the preview), or the trajectory alone (the coverage report)
const W_FULL := 0
const W_TRAJ := 1


## the database: every scene (and every move that has cards) read from the folders, one row per frame at its fps
static func build(dirs: Array = ["res://scenes/", "res://moves/"]) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var clips: Array = []
	for dir in dirs:
		for fn in DirAccess.get_files_at(dir):
			if not fn.ends_with(".json"):
				continue
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + fn))
			if not (d is Dictionary) or (d.get("cards", []) as Array).is_empty():
				continue   # a move (one pose, no time) has no motion to match
			var S := Scene.new()
			S.from_dict(d)
			clips.append(_clip(S, B, fn.get_basename(), dir + fn))
	return _pack(clips)


## one clip played through Scene.apply at its own fps: the root, the heading, the feet, the hips, every joint's angle
static func _clip(S: Scene, B: Body, cname: String, path: String) -> Dictionary:
	var fps: float = S.fps if S.fps > 0 else 30.0
	var L: float = S.length()
	var n: int = int(floorf(L * fps)) + 1
	var root := PackedVector3Array()
	var head := PackedFloat32Array()
	var bl := PackedVector3Array()
	var br := PackedVector3Array()
	var hip := PackedVector3Array()
	var ang := PackedVector3Array()
	var off := PackedVector3Array()
	for f in n:
		S.apply(B, minf(float(f) / fps, L))
		B.fk()
		root.append(Vector3(B.offset.x, 0.0, B.offset.z))
		var fw: Vector3 = B.G["pelvis"] * Vector3(0, 0, 1)
		head.append(atan2(fw.x, fw.z))
		bl.append(B.P["ball_l"])
		br.append(B.P["ball_r"])
		hip.append(B.P["pelvis"])
		off.append(B.offset)
		for j in Body.ORDER:
			ang.append(B.ang.get(j, Vector3.ZERO))
	return {"name": cname, "path": path, "fps": fps, "n": n, "root": root, "head": head, "bl": bl, "br": br,
		"hip": hip, "ang": ang, "off": off}


## the feature row of frame f of one clip (root frame of that frame; see the header)
static func _feat(c: Dictionary, f: int) -> PackedFloat32Array:
	var n: int = c["n"]
	var fps: float = c["fps"]
	var dt := 1.0 / fps
	var root: PackedVector3Array = c["root"]
	var head: PackedFloat32Array = c["head"]
	var bl: PackedVector3Array = c["bl"]
	var br: PackedVector3Array = c["br"]
	var hip: PackedVector3Array = c["hip"]
	var h: float = head[f]
	var ch := cos(h)
	var sh := sin(h)
	var r: Vector3 = root[f]
	var a := maxi(f - 1, 0)
	var b := mini(f + 1, n - 1)
	var span := maxf(float(b - a) * dt, 1e-6)
	var out := PackedFloat32Array()
	out.resize(DIM)
	var p := _loc(bl[f] - r, ch, sh)
	out[0] = p.x; out[1] = p.y; out[2] = p.z
	p = _loc(br[f] - r, ch, sh)
	out[3] = p.x; out[4] = p.y; out[5] = p.z
	p = _loc((bl[b] - bl[a]) / span, ch, sh)
	out[6] = p.x; out[7] = p.y; out[8] = p.z
	p = _loc((br[b] - br[a]) / span, ch, sh)
	out[9] = p.x; out[10] = p.y; out[11] = p.z
	p = _loc((hip[b] - hip[a]) / span, ch, sh)
	out[12] = p.x; out[13] = p.y; out[14] = p.z
	for k in HORIZON.size():
		var idx := mini(f + int(roundf(float(HORIZON[k]) * fps)), n - 1)
		p = _loc(root[idx] - r, ch, sh)
		out[15 + 2 * k] = p.x; out[16 + 2 * k] = p.z
		var hd: float = head[idx]
		var d := _loc(Vector3(sin(hd), 0.0, cos(hd)), ch, sh)
		out[21 + 2 * k] = d.x; out[22 + 2 * k] = d.z
	return out


## a world vector into the frame whose heading is h (the inverse of the heading's turn about Y)
static func _loc(v: Vector3, ch: float, sh: float) -> Vector3:
	return Vector3(ch * v.x - sh * v.z, v.y, sh * v.x + ch * v.z)


## all clips' rows, the mean and sd per dimension, the normalised rows z
static func _pack(clips: Array) -> Dictionary:
	var raw := PackedFloat32Array()
	var clip_of := PackedInt32Array()
	var frame_of := PackedInt32Array()
	var ang := PackedVector3Array()
	var off := PackedVector3Array()
	var root := PackedVector3Array()
	var head := PackedFloat32Array()
	var nfr := 0
	var info := []
	for ci in clips.size():
		var c: Dictionary = clips[ci]
		info.append({"name": c["name"], "path": c["path"], "fps": c["fps"], "n": c["n"], "first": nfr})
		for f in c["n"]:
			raw.append_array(_feat(c, f))
			clip_of.append(ci)
			frame_of.append(f)
		nfr += int(c["n"])
		ang.append_array(c["ang"])
		off.append_array(c["off"])
		root.append_array(c["root"])
		head.append_array(c["head"])
	var mean := PackedFloat32Array()
	var sd := PackedFloat32Array()
	mean.resize(DIM)
	sd.resize(DIM)
	for d in DIM:
		var s := 0.0
		for i in nfr:
			s += raw[i * DIM + d]
		var m := s / maxf(float(nfr), 1.0)
		var v := 0.0
		for i in nfr:
			var df := raw[i * DIM + d] - m
			v += df * df
		mean[d] = m
		sd[d] = maxf(sqrt(v / maxf(float(nfr), 1.0)), 1e-3)
	var z := PackedFloat32Array()
	z.resize(nfr * DIM)
	for i in nfr:
		for d in DIM:
			z[i * DIM + d] = (raw[i * DIM + d] - mean[d]) / sd[d]
	var db := {"n": nfr, "raw": raw, "z": z, "mean": mean, "sd": sd, "clip_of": clip_of, "frame_of": frame_of,
		"clips": info, "ang": ang, "off": off, "root": root, "head": head, "joints": Body.ORDER,
		"scale": [scale_of(GROUPS), scale_of(TRAJ)]}
	# the rows as 9 Vector3 chunks (3 dims each), pre-scaled by the weights: a distance is then a plain squared length
	db["zf"] = _chunks_all(db, 0)
	db["zt"] = _chunks_all(db, 1)
	db["ix"] = [_index(db["zf"], nfr), _index(db["zt"], nfr)]
	return db


## THE INDEX (exact nearest neighbour, ROADMAP 33 speed): the rows are grouped into K ~ sqrt(n) buckets around centroids
## (evenly spaced seeds, then two re-centrings: the clips are continuous, so neighbouring frames share a bucket). Each bucket
## keeps its radius and each row its distance to the bucket's centroid. A search measures the query to every centroid, visits the
## buckets nearest-first and stops when a bucket's lower bound (distance - radius) cannot beat the best; inside a bucket a row
## is skipped when |query-centroid - row-centroid| (the triangle inequality) cannot beat it either. Both are lower bounds on the
## true distance, so the result is the brute-force argmin (ties to the lower row, as the scan did); EPS absorbs float rounding.
const EPS := 1e-4


static func _index(zs: PackedVector3Array, n: int) -> Dictionary:
	var k := clampi(int(roundf(sqrt(float(n)))), 1, 64)
	var cen := PackedVector3Array()
	cen.resize(k * 9)
	for c in k:
		var src := mini((c * n) / k + n / (2 * k), n - 1)
		for j in 9:
			cen[c * 9 + j] = zs[src * 9 + j]
	var owner := PackedInt32Array()
	owner.resize(n)
	for pass_i in 3:
		for i in n:
			var bd := INF
			var bc := 0
			for c in k:
				var s := 0.0
				var j := 0
				while j < 9:
					s += (zs[i * 9 + j] - cen[c * 9 + j]).length_squared()
					if s >= bd:
						break
					j += 1
				if j == 9:
					bd = s
					bc = c
			owner[i] = bc
		if pass_i == 2:
			break
		var sum := PackedVector3Array()
		sum.resize(k * 9)
		var cnt := PackedInt32Array()
		cnt.resize(k)
		for i in n:
			var c := owner[i]
			cnt[c] += 1
			for j in 9:
				sum[c * 9 + j] += zs[i * 9 + j]
		for c in k:
			if cnt[c] > 0:
				for j in 9:
					cen[c * 9 + j] = sum[c * 9 + j] / float(cnt[c])
	# rows grouped by bucket (ascending row index inside a bucket), their distance to the centroid, the bucket radius
	var start := PackedInt32Array()
	start.resize(k + 1)
	for i in n:
		start[owner[i] + 1] += 1
	for c in k:
		start[c + 1] += start[c]
	var fill := start.duplicate()
	var rows := PackedInt32Array()
	rows.resize(n)
	for i in n:
		rows[fill[owner[i]]] = i
		fill[owner[i]] += 1
	var dm := PackedFloat32Array()
	dm.resize(n)
	var rad := PackedFloat32Array()
	rad.resize(k)
	for c in k:
		for p in range(start[c], start[c + 1]):
			var i := rows[p]
			var s := 0.0
			for j in 9:
				s += (zs[i * 9 + j] - cen[c * 9 + j]).length_squared()
			dm[p] = sqrt(s)
			rad[c] = maxf(rad[c], dm[p])
	return {"k": k, "cen": cen, "rad": rad, "start": start, "rows": rows, "dm": dm}


## the per-dimension scale for a set of groups: sqrt of the group's weight, 0 outside the set. Groups are averaged,
## so the scaled squared distance is the mean squared difference over the set's dimensions (a cost is an RMS in sd)
static func scale_of(groups: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(DIM)
	for gname in groups:
		var nd: int = NDIM[gname]
		for k in nd:
			out[int(OFF[gname]) + k] = sqrt(1.0 / float(nd * groups.size()))
	return out


static func _chunks_all(db: Dictionary, which: int) -> PackedVector3Array:
	var z: PackedFloat32Array = db["z"]
	var n: int = db["n"]
	var out := PackedVector3Array()
	out.resize(n * 9)
	for i in n:
		for c in 9:
			out[i * 9 + c] = _chunk(z, i * DIM + 3 * c, db, which, 3 * c)
	return out


static func _chunk(z: PackedFloat32Array, base: int, db: Dictionary, which: int, d0: int) -> Vector3:
	var sc: PackedFloat32Array = (db["scale"] as Array)[which]
	return Vector3(z[base] * sc[d0], z[base + 1] * sc[d0 + 1], z[base + 2] * sc[d0 + 2])


## a normalised query (27 floats) as the 9 chunks a search takes, with the same weighting
static func chunks(db: Dictionary, q: PackedFloat32Array, which: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(9)
	for c in 9:
		out[c] = _chunk(q, 3 * c, db, which, 3 * c)
	return out


## the normalised query for frame g's own pose with a target trajectory v (m/s, root frame; Y ignored):
## the trajectory at +0.33 / +0.67 / +1.0 s is v * t, the facing is v's direction (forward when v is ~0)
static func query_of(db: Dictionary, g: int, v: Vector3) -> PackedFloat32Array:
	var raw: PackedFloat32Array = (db["raw"] as PackedFloat32Array).slice(g * DIM, (g + 1) * DIM)
	var dir := Vector3(0, 0, 1) if Vector2(v.x, v.z).length() < 0.05 else Vector3(v.x, 0.0, v.z).normalized()
	for k in HORIZON.size():
		raw[15 + 2 * k] = v.x * float(HORIZON[k])
		raw[16 + 2 * k] = v.z * float(HORIZON[k])
		raw[21 + 2 * k] = dir.x
		raw[22 + 2 * k] = dir.z
	var mean: PackedFloat32Array = db["mean"]
	var sd: PackedFloat32Array = db["sd"]
	var q := PackedFloat32Array()
	q.resize(DIM)
	for d in DIM:
		q[d] = (raw[d] - mean[d]) / sd[d]
	return q


## the nearest frame, exactly the brute-force argmin over every row (ties to the lower row), found through the bucket index
## (see _index). Returns [frame, squared weighted distance]
static func search(db: Dictionary, qc: PackedVector3Array, which: int) -> Array:
	var zs: PackedVector3Array = db["zf"] if which == W_FULL else db["zt"]
	var ix: Dictionary = (db["ix"] as Array)[which]
	var k: int = ix["k"]
	var cen: PackedVector3Array = ix["cen"]
	var rad: PackedFloat32Array = ix["rad"]
	var start: PackedInt32Array = ix["start"]
	var rows: PackedInt32Array = ix["rows"]
	var dm: PackedFloat32Array = ix["dm"]
	# the query to every centroid, and the buckets' lower bounds, visited nearest-first (selection: a few buckets are enough)
	var dq := PackedFloat32Array()
	dq.resize(k)
	var lb := PackedFloat32Array()
	lb.resize(k)
	for c in k:
		var s := 0.0
		var base := c * 9
		for j in 9:
			s += (cen[base + j] - qc[j]).length_squared()
		dq[c] = sqrt(s)
		lb[c] = maxf(dq[c] - rad[c], 0.0)
	var best := INF
	var bi := -1
	for _v in k:
		var c := 0
		var lo := INF
		for t in k:
			if lb[t] < lo:
				lo = lb[t]
				c = t
		if lo >= INF or lo * lo > best * (1.0 + EPS) + 1e-9:
			break
		lb[c] = INF
		var dc := dq[c]
		for p in range(start[c], start[c + 1]):
			var gap := dc - dm[p]
			if gap * gap > best * (1.0 + EPS) + 1e-9:
				continue
			var i := rows[p]
			var base := i * 9
			var s := 0.0
			var j := 0
			while j < 9:
				s += (zs[base + j] - qc[j]).length_squared()
				if s > best:
					break
				j += 1
			if j == 9 and (s < best or (s == best and i < bi)):
				best = s
				bi = i
	return [bi, best]


## the weighted squared distance from the query chunks to frame g, under the same weighting as a search
static func row_sq(db: Dictionary, qc: PackedVector3Array, g: int, which: int) -> float:
	var zs: PackedVector3Array = db["zf"] if which == W_FULL else db["zt"]
	var s := 0.0
	for c in 9:
		s += (zs[g * 9 + c] - qc[c]).length_squared()
	return s


## COVERAGE: the trajectory alone, in 8 directions (every 45 deg, 0 = forward, 90 = the left) at each speed in
## COVER_SPEEDS, plus standing still. A query with no good frame (cost above GOOD) is a gap: the clip to add.
static func coverage(db: Dictionary) -> Dictionary:
	var cases: Array = [[0.0, 0.0]]
	for sp in COVER_SPEEDS:
		for k in 8:
			cases.append([float(sp), 45.0 * k])
	var rows: Array = []
	var gaps: Array = []
	var worst := 0.0
	var clips: Array = db["clips"]
	var clip_of: PackedInt32Array = db["clip_of"]
	var frame_of: PackedInt32Array = db["frame_of"]
	for cse in cases:
		var sp: float = cse[0]
		var deg: float = cse[1]
		var rad := deg_to_rad(deg)
		var v := Vector3(sin(rad) * sp, 0.0, cos(rad) * sp)
		var qc := chunks(db, query_of(db, 0, v), W_TRAJ)
		var res := search(db, qc, W_TRAJ)
		var g: int = res[0]
		var cost := sqrt(float(res[1]))
		var row := {"speed": sp, "deg": deg, "cost": cost, "clip": clips[clip_of[g]]["name"],
			"frame": frame_of[g], "good": cost <= GOOD}
		rows.append(row)
		worst = maxf(worst, cost)
		if cost > GOOD:
			gaps.append(row)
	var lines := PackedStringArray()
	lines.append("MOTION MATCHING COVERAGE: %d of %d queries have a good match (cost <= %.1f sd); worst %.2f" % [
		rows.size() - gaps.size(), rows.size(), GOOD, worst])
	for row in rows:
		lines.append("%s %4.1f m/s %5.0f deg  cost %.2f  best %s f%d" % ["  " if row["good"] else "GAP", row["speed"],
			row["deg"], row["cost"], row["clip"], row["frame"]])
	return {"rows": rows, "gaps": gaps, "worst": worst, "text": "\n".join(lines)}


## THE PREVIEW PLAYER: the playing frame advances at its clip's fps; every SEARCH_EVERY s the nearest frame to the
## target (the playing frame's own pose and the target trajectory) is searched for; a new frame is cross-faded in over
## XFADE s from the pose on screen. The root moves by the playing clip's own root motion (in the root frame).
class Player:
	extends RefCounted
	var db: Dictionary
	var g := 0               # the global frame playing
	var acc := 0.0           # clip frames advanced since the last whole frame
	var since := SEARCH_EVERY
	var cost := 0.0          # the playing frame's cost under the last query
	var xf := 1.0            # cross-fade progress 0..1 (1 = done)
	var from_ang := PackedVector3Array()
	var shown := PackedVector3Array()
	var root := Vector3.ZERO
	var switches := 0
	var searches := 0
	var last_ms := 0.0

	func _init(d: Dictionary, start: int = 0) -> void:
		db = d
		g = start
		shown = _row(g)

	func _row(i: int) -> PackedVector3Array:
		var J: int = (db["joints"] as Array).size()
		return (db["ang"] as PackedVector3Array).slice(i * J, (i + 1) * J)

	func clip_name() -> String:
		return db["clips"][db["clip_of"][g]]["name"]

	func frame_in_clip() -> int:
		return db["frame_of"][g]

	## the root's motion of frame i -> i + 1, in the root frame of frame i
	func _delta(i: int) -> Vector3:
		var root_a: Vector3 = (db["root"] as PackedVector3Array)[i]
		var root_b: Vector3 = (db["root"] as PackedVector3Array)[i + 1]
		var h: float = (db["head"] as PackedFloat32Array)[i]
		return MotionMatch._loc(root_b - root_a, cos(h), sin(h))

	## one frame of the preview: v = the target velocity (m/s, root frame). Returns the pose and the readout.
	func step(dt: float, v: Vector3) -> Dictionary:
		var clip: Dictionary = db["clips"][db["clip_of"][g]]
		var last: int = int(clip["first"]) + int(clip["n"]) - 1
		since += dt
		acc += dt * float(clip["fps"])
		while acc >= 1.0 and g < last:
			acc -= 1.0
			root += _delta(g)
			g += 1
		if g >= last:
			acc = 0.0
			since = maxf(since, SEARCH_EVERY)   # the clip has ended: look for the next frame now
		if since >= SEARCH_EVERY:
			since = 0.0
			var qc := MotionMatch.chunks(db, MotionMatch.query_of(db, g, v), MotionMatch.W_FULL)
			var t0 := Time.get_ticks_usec()
			var res := MotionMatch.search(db, qc, MotionMatch.W_FULL)
			last_ms = float(Time.get_ticks_usec() - t0) / 1000.0
			searches += 1
			var here := MotionMatch.row_sq(db, qc, g, MotionMatch.W_FULL)
			if int(res[0]) != g and float(res[1]) < here:
				from_ang = shown.duplicate()
				xf = 0.0
				g = int(res[0])
				acc = 0.0
				switches += 1
			cost = sqrt(MotionMatch.row_sq(db, qc, g, MotionMatch.W_FULL))
		xf = minf(1.0, xf + dt / MotionMatch.XFADE)
		var tgt := _row(g)
		var w := smoothstep(0.0, 1.0, xf)
		for k in tgt.size():
			shown[k] = tgt[k] if xf >= 1.0 or from_ang.size() != tgt.size() else from_ang[k].lerp(tgt[k], w)
		return {"ang": shown, "offset": Vector3(root.x, float((db["off"] as PackedVector3Array)[g].y), root.z),
			"clip": clip_name(), "frame": frame_in_clip(), "cost": cost, "xf": xf, "good": cost <= MotionMatch.GOOD,
			"ms": last_ms, "switches": switches}
