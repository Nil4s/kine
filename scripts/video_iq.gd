## VIDEO IQ (Nick 10-19: the video capture "needs refinement, some intelligence behind it"). What VideoImport + VideoCleanup
## already did: MediaPipe's 33 world landmarks (+ hands), the camera tilt levelled, a One Euro jitter filter (zero lag), the floor
## plane from the soles, foot plants from height + speed, the root rebuilt from the stance foot, sparse cards every 5th frame.
## What it did NOT do is look at the footage the way an animator does. Four things, each a pure function on the landmarks:
##   1 CONTACTS   when is a foot (or a hand) on the ground, as the animator reads it. Velocity + height with hysteresis,
##                the method of Zou et al. 2020 ("Reducing footskate in human motion reconstruction with ground contact
##                constraints", WACV): a joint is in contact while it is low AND slow. The landmarks are about the HIPS, so
##                "slow" is slow against the ground, not against the hips: the root's own velocity (the lowest sole's, taken
##                as a running median so a swinging foot cannot vote itself still) is added to every point first. The runs
##                become FootPlant plants (the app's own foot IK holds the sole) and tell the root rebuild which foot is down
##   2 DEPTH      a monocular tracker's depth is the weak axis: a knee or elbow comes out in front when it is behind. The
##                image-plane position is trusted; per frame each chain (hip-knee-ankle, shoulder-elbow-wrist) chooses between
##                the tracker's depth and the depth REFLECTED through the image plane, with every bone rescaled to its median
##                length (a bone is rigid), by a Viterbi pass over the clip: cost = joint limit violated (knee flexion, elbow
##                flexion, elbow hyperextension) + departure from the tracker + jump from the frame before
##   3 SMART KEYS the dense fit reduced to cards at the motion's own turning points: Douglas-Peucker (Ramer 1972, Douglas &
##                Peucker 1973) over the joint-angle curves (a frame is kept when the straight line between its kept
##                neighbours misses it by more than a tolerance), the tolerance bisected so the cards REPLAY within a position
##                error of the dense result (replayed by Scene.apply, not estimated). Linear and spline playback are both tried
##   4 CONFIDENCE the tracker's per-landmark visibility, with lost frames and teleporting landmarks, per body part, as a
##                lane on the timeline; low-confidence spans are named ("left hand lost 1.0-1.5 s") and their landmarks are
##                filled from the good frames either side before anything is fitted
## Nothing here writes a file: main._import_pose stores the result in the scene (Scene.iq, key "iq") as one edit.
class_name VideoIQ
extends RefCounted

## the body parts the confidence is read on: part -> the landmarks that carry it
const PARTS := {"hand_l": [13, 15], "hand_r": [14, 16], "foot_l": [25, 27, 29, 31], "foot_r": [26, 28, 30, 32],
	"head": [0, 7, 8], "body": [11, 12, 23, 24]}
const LABEL := {"hand_l": "left hand", "hand_r": "right hand", "foot_l": "left foot", "foot_r": "right foot", "head": "head",
	"body": "body"}
const LOW := 0.5          # confidence under this is flagged
const LOST := 0.3         # ... and under this it reads "lost", between the two "unsure"
const SPAN_MIN := 0.15    # s: a flagged run shorter than this is a blink, not a span
const GAP_FILL := 1.5     # s: frames the tracker skipped are filled up to this long a gap
const TELEPORT := 0.12    # m: a landmark this far from the mean of its neighbours, which are near each other, jumped
const LOCAL := {"hand_l": 11, "hand_r": 12, "foot_l": 23, "foot_r": 24}   # part -> the landmark its points are filled relative to
const MERGE := 2          # frames: flagged runs this close are one span


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


# ============================================================ 4 CONFIDENCE ================================================

## the frames the tracker skipped (no body found) put back as interpolated frames marked "lost" (vis 0), so the clip is
## uniform in time. A gap longer than GAP_FILL is left (the cards span it)
static func fill_gaps(frames: Array, fps: float) -> Array:
	var out := []
	var dt := 1.0 / maxf(fps, 1.0)
	for i in frames.size():
		if i > 0:
			var t0 := float(frames[i - 1]["t"])
			var gap := float(frames[i]["t"]) - t0
			var miss := int(round(gap / dt)) - 1
			if miss >= 1 and gap <= GAP_FILL:
				for k in range(1, miss + 1):
					var u := float(k) / float(miss + 1)
					var w := []
					for j in 33:
						w.append(((frames[i - 1]["w"] as Array)[j] as Vector3).lerp((frames[i]["w"] as Array)[j], u))
					var z := []
					z.resize(33)
					z.fill(0.0)
					out.append({"t": t0 + gap * u, "w": w, "lost": true, "vis": z})
		out.append(frames[i])
	return out


## per part and frame, 0..1: the tracker's visibility (mean over the part's landmarks; 1 when the file has none), x0.3 where a
## landmark jumped away and back (a teleport), 0 on a lost frame. Returns {"c" (the worst part per frame), "parts", "spans",
## "dt", "t0"}; span times are seconds from the first frame (the scene's own clock)
static func confidence(frames: Array, fps: float) -> Dictionary:
	var n := frames.size()
	var parts := {}
	for p in PARTS:
		parts[p] = []
	var overall := []
	for i in n:
		var f: Dictionary = frames[i]
		var lost := bool(f.get("lost", false))
		var vis: Array = f.get("vis", [])
		var cmin := 1.0
		for p in PARTS:
			var c := 0.0
			if not lost:
				var s := 0.0
				for k in PARTS[p]:
					s += float(vis[k]) if vis.size() > int(k) else 1.0
				c = s / float((PARTS[p] as Array).size())
				if i > 0 and i < n - 1 and not bool(frames[i - 1].get("lost", false)) and not bool(frames[i + 1].get("lost", false)):
					for k in PARTS[p]:
						var a: Vector3 = (frames[i - 1]["w"] as Array)[k]
						var b: Vector3 = (frames[i + 1]["w"] as Array)[k]
						var dev := ((f["w"] as Array)[k] as Vector3).distance_to((a + b) * 0.5)
						if dev > TELEPORT and a.distance_to(b) < dev:
							c *= 0.3
							break
			(parts[p] as Array).append(c)
			cmin = minf(cmin, c)
		overall.append(cmin)
	var t0 := float(frames[0]["t"]) if n > 0 else 0.0
	return {"c": overall, "parts": parts, "dt": 1.0 / maxf(fps, 1.0), "t0": t0, "spans": _spans(frames, parts, t0)}


static func _runs(c: Array, thr: float) -> Array:
	var runs := []
	var i := 0
	while i < c.size():
		if float(c[i]) >= thr:
			i += 1
			continue
		var a := i
		while i < c.size() and float(c[i]) < thr:
			i += 1
		if runs.size() > 0 and a - int(runs[-1][1]) - 1 <= MERGE:
			runs[-1][1] = i - 1
		else:
			runs.append([a, i - 1])
	return runs


static func _spans(frames: Array, parts: Dictionary, t0: float) -> Array:
	var out := []
	var n := frames.size()
	var body_runs := _runs(parts["body"], LOW)
	for p in PARTS:
		for r in _runs(parts[p], LOW):
			var a: int = r[0]
			var b: int = r[1]
			var ta := float(frames[a]["t"]) - t0
			var tb := float(frames[b]["t"]) - t0
			if tb - ta < SPAN_MIN - 1e-6:
				continue
			if p != "body":   # the whole body lost covers every part: one span says it
				var inside := false
				for br in body_runs:
					if a >= int(br[0]) - MERGE and b <= int(br[1]) + MERGE and float(frames[int(br[1])]["t"]) - float(frames[int(br[0])]["t"]) >= SPAN_MIN:
						inside = true
				if inside:
					continue
			var m := 0.0
			for i in range(a, b + 1):
				m += float((parts[p] as Array)[i])
			m /= float(b - a + 1)
			var what := "tracking lost" if p == "body" else "%s %s" % [LABEL[p], "lost" if m < LOST else "unsure"]
			out.append({"part": p, "t0": snappedf(ta, 0.001), "t1": snappedf(tb, 0.001), "c": snappedf(m, 0.01), "what": what,
				"text": "%s %.1f-%.1f s" % [what, ta, tb]})
	out.sort_custom(func(x, y): return float(x["t0"]) < float(y["t0"]))
	return out


## the landmarks of every flagged run (confidence < LOW) put back on the line between the good frames either side (held at the
## clip's ends). Runs longer than GAP_FILL are left. Returns how many landmark-frames were replaced
static func repair(frames: Array, conf: Dictionary) -> int:
	var n := frames.size()
	var done := 0
	var dt := float(conf["dt"])
	for p in PARTS:
		for r in _runs(conf["parts"][p], LOW):
			var a: int = r[0]
			var b: int = r[1]
			if float(b - a + 1) * dt > GAP_FILL:
				continue
			var ia := a - 1
			var ib := b + 1
			if ia < 0 and ib >= n:
				continue
			var fa: Array = (frames[ia]["w"] if ia >= 0 else frames[ib]["w"])
			var fb: Array = (frames[ib]["w"] if ib < n else frames[ia]["w"])
			var anc: int = LOCAL.get(p, -1)   # the landmark this part's points are measured from, when it is good here
			for k in PARTS[p]:
				for i in range(a, b + 1):
					var u := float(i - ia) / float(ib - ia) if ia >= 0 and ib < n else 0.0
					var va: Vector3 = fa[k]
					var vb: Vector3 = fb[k]
					if anc >= 0:   # in the shoulder's / hip's frame, so the body's own motion is not lost with the limb's
						va -= fa[anc] as Vector3
						vb -= fb[anc] as Vector3
					var v := va.lerp(vb, u)
					if anc >= 0:
						v += (frames[i]["w"] as Array)[anc] as Vector3
					(frames[i]["w"] as Array)[k] = v
					done += 1
	return done


## the lane as the timeline reads it: {"n", "dt", "c": [0..100 per frame], "spans": [...]} out of Scene.iq
static func lane_colour(c: float) -> Color:
	var red := Tok.c("fd_active")
	var gold := Tok.c("mk_gold")
	var green := Tok.c("fd_startup")
	if c < LOW:
		return red
	if c < 0.8:
		return red.lerp(gold, (c - LOW) / 0.3) if c < 0.65 else gold.lerp(green, (c - 0.65) / 0.15)
	return green


# ================================================================ 2 DEPTH ================================================

const CHAINS := [[23, 25, 27, "knee"], [24, 26, 28, "knee"], [11, 13, 15, "elbow"], [12, 14, 16, "elbow"]]
const SLACK := 3.0        # deg: a limit is violated only past this (the landmarks are not exact)
const W_LIMIT := 0.05     # cost per degree outside a limit
const W_RAW := 1.0        # cost per metre away from the tracker's own point
const W_TIME := 2.0       # cost per metre of jump from the frame before (relative to the hips)


## the body's limits as the depth pass reads them: the knee's and the elbow's flexion, deg, [lowest (negative = hyperextension),
## highest]
static func limits_of(B: Body) -> Dictionary:
	var out := {}
	for pr in [["knee", "calf_r"], ["elbow", "lowerarm_r"]]:
		var r: Vector2 = B.lim[pr[1]]["bend"]
		out[pr[0]] = Vector2(-minf(absf(r.x), absf(r.y)), maxf(absf(r.x), absf(r.y)))
	return out


## a chain's signed flexion, deg: + = the knee bent (shin behind the thigh) / the elbow bent (forearm in front), against the hip
## line r (left minus right) of the person. A hyperextension is negative
static func flexion(kind: String, d: Vector3, e: Vector3, rhat: Vector3) -> float:
	var ang := rad_to_deg(d.angle_to(e))
	var s := d.cross(e).dot(rhat)
	if kind == "knee":
		return ang if s >= 0.0 else -ang
	return ang if s <= 0.0 else -ang


## degrees a chain is beyond its limit (SLACK allowed): the knee's SIGNED flexion (a knee bends one way whatever the thigh's twist
## does), the elbow's flexion past its maximum. An elbow's "backward" is the hinge's side, which is the upper arm's twist, and
## landmarks carry no twist (a hanging right arm in combo3 bends "backward" by 70 deg in the truth, twisted): the elbow's side is
## held by continuity only. `up` is kept for the signature
static func violation(kind: String, d: Vector3, e: Vector3, rh: Vector3, up: Vector3, lim: Vector2) -> float:
	var fl := flexion(kind, d, e, rh)
	if kind == "knee":
		return maxf(0.0, maxf(lim.x - SLACK - fl, fl - lim.y - SLACK))
	return maxf(0.0, absf(fl) - lim.y - SLACK)


## every limb bone set to its median length over the clip (the chain's mid, then its tip, from the root): a bone is rigid. Run on
## the cleaned frames, where the filter's different smoothing per landmark has made the lengths breathe
static func normalize_lengths(frames: Array) -> void:
	for ch in CHAINS:
		var l1 := []
		var l2 := []
		for f in frames:
			var w: Array = f["w"]
			l1.append(((w[ch[1]] as Vector3) - (w[ch[0]] as Vector3)).length())
			l2.append(((w[ch[2]] as Vector3) - (w[ch[1]] as Vector3)).length())
		var L1 := _median(l1)
		var L2 := _median(l2)
		for f in frames:
			var w: Array = f["w"]
			var b: Vector3 = (w[ch[0]] as Vector3) + ((w[ch[1]] as Vector3) - (w[ch[0]] as Vector3)).normalized() * L1
			w[ch[2]] = b + ((w[ch[2]] as Vector3) - (w[ch[1]] as Vector3)).normalized() * L2
			w[ch[1]] = b


static func _reflect(v: Vector3, ax: Vector3) -> Vector3:
	return v - 2.0 * v.dot(ax) * ax


## DEPTH. frames are changed in place. axis = the camera's depth direction in the frames' axes. Returns {"frames": the frames
## with a chain moved by more than 3 cm, "flipped": chain-frames whose depth was reflected}
static func fix_depth(frames: Array, axis: Vector3, lims: Dictionary) -> Dictionary:
	var n := frames.size()
	var moved := {}
	var flipped := 0
	var ax := axis.normalized()
	for ch in CHAINS:
		var ia: int = ch[0]
		var ib: int = ch[1]
		var ic: int = ch[2]
		var kind: String = ch[3]
		var l1 := []
		var l2 := []
		for f in frames:
			var w: Array = f["w"]
			l1.append(((w[ib] as Vector3) - (w[ia] as Vector3)).length())
			l2.append(((w[ic] as Vector3) - (w[ib] as Vector3)).length())
		var L1 := _median(l1)
		var L2 := _median(l2)
		if L1 < 1e-4 or L2 < 1e-4:
			continue
		# candidates per frame: 4 = (mid reflected?) x (tip reflected?) ; each is [b', c']
		var cand := []
		var unary := []
		for i in n:
			var w: Array = frames[i]["w"]
			var a: Vector3 = w[ia]
			var b: Vector3 = w[ib]
			var c: Vector3 = w[ic]
			var rh: Vector3 = ((w[23] as Vector3) - (w[24] as Vector3)).normalized()
			var up: Vector3 = (((w[11] as Vector3) + (w[12] as Vector3)) - ((w[23] as Vector3) + (w[24] as Vector3))).normalized()
			var cs := []
			var us := []
			for s in 4:
				var vb := b - a
				var vc := c - b
				if s & 1:
					vb = _reflect(vb, ax)
				if s & 2:
					vc = _reflect(vc, ax)
				var b2 := a + vb.normalized() * L1
				var c2 := b2 + vc.normalized() * L2
				var cost := W_RAW * (b2.distance_to(b) + c2.distance_to(c))
				cost += W_LIMIT * violation(kind, vb, vc, rh, up, lims[kind])
				cs.append([b2, c2])
				us.append(cost)
			cand.append(cs)
			unary.append(us)
		# Viterbi over the clip
		var best := []
		var back := []
		best.append(unary[0].duplicate())
		back.append([0, 0, 0, 0])
		for i in range(1, n):
			var bi := []
			var bk := []
			var wp: Array = frames[i - 1]["w"]
			var wc: Array = frames[i]["w"]
			for s in 4:
				var bv := INF
				var bs := 0
				for r in 4:
					var jump := ((cand[i][s][0] as Vector3) - (wc[ia] as Vector3)).distance_to((cand[i - 1][r][0] as Vector3) - (wp[ia] as Vector3)) \
						+ ((cand[i][s][1] as Vector3) - (wc[ia] as Vector3)).distance_to((cand[i - 1][r][1] as Vector3) - (wp[ia] as Vector3))
					var v: float = float(best[i - 1][r]) + W_TIME * jump
					if v < bv:
						bv = v
						bs = r
				bi.append(bv + float(unary[i][s]))
				bk.append(bs)
			best.append(bi)
			back.append(bk)
		var s := 0
		for r in 4:
			if float(best[n - 1][r]) < float(best[n - 1][s]):
				s = r
		for i in range(n - 1, -1, -1):
			var w: Array = frames[i]["w"]
			var b0: Vector3 = w[ib]
			var c0: Vector3 = w[ic]
			w[ib] = cand[i][s][0]
			w[ic] = cand[i][s][1]
			if s != 0:
				flipped += 1
			if b0.distance_to(w[ib]) > 0.03 or c0.distance_to(w[ic]) > 0.03:
				moved[i] = true
			s = int(back[i][s])
	return {"frames": moved.size(), "flipped": flipped}


# =============================================================== 1 CONTACTS ==============================================

static var H_ON := 0.05        # m: a point this near the ground can touch it ...
static var H_OFF := 0.08       # ... and stays touching until it is this far
static var H_PIV := 0.08       # m: a heel / ball is a LOCKED pivot (VideoImport.solve) while this near its ground in a contact; the contact itself is wider
static var V_ON := 0.25        # m/s, against the ground: slow enough to touch
static var V_OFF := 0.30
const BRIDGE := 2         # frames: contact runs this close are one
const MIN_RUN := 3        # frames: a shorter run is a tap
const HAND_H := 0.15      # m above the ground under the soles: a hand this low can be on it
const HAND_V := 0.25
const HAND_MIN := 4
const FLOOR_WIN := 20     # frames: a foot's ground is the lowest it gets within this many frames either side
const TRIM := 2           # frames cut off the end of a plant (the toe-off; VideoCleanup.reachable cuts what the leg cannot hold)


static func _hxz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## CONTACTS on landmark frames {"t","w"} (hips-relative). Returns {"list": [{"kind": "foot"/"hand", "part", "f0", "f1", "t0",
## "t1"}] by f0 (t from the first frame), "hint": [per frame "_l" / "_r" / "" : the one foot down], "ground": per-frame ground
## height relative to the hips, "root": per-frame root velocity (xz, m/s)}
static func contacts(frames: Array, fps: float) -> Dictionary:
	var n := frames.size()
	var T0 := float(frames[0]["t"])
	var dtf := 1.0 / maxf(fps, 1.0)
	# per point velocity (xz, 5-point central difference), hips-relative
	var pts := {"hl": 29, "tl": 31, "hr": 30, "tr": 32, "wl": 15, "wr": 16}
	var ys := {}
	var vel := {}
	for k in pts:
		var ya := []
		var va := []
		for i in n:
			ya.append(((frames[i]["w"] as Array)[pts[k]] as Vector3).y)
			var a := maxi(i - 2, 0)
			var b := mini(i + 2, n - 1)
			var dt := maxf(float(frames[b]["t"]) - float(frames[a]["t"]), 1e-6)
			va.append((_hxz((frames[b]["w"] as Array)[pts[k]]) - _hxz((frames[a]["w"] as Array)[pts[k]])) / dt)
		ys[k] = ya
		vel[k] = va
	# each foot's own ground, per frame: the lowest its sole gets within FLOOR_WIN frames either side (every foot is on the ground
	# once a step), so a tracker that holds the far leg 10 cm high all clip, or lets it drift, is read against the foot itself
	var gf := {}
	for sd in ["l", "r"]:
		var base := []
		for i in n:
			base.append(minf(float(ys["h" + sd][i]), float(ys["t" + sd][i])))
		var fl := []
		for i in n:
			var m := INF
			for j in range(maxi(i - FLOOR_WIN, 0), mini(i + FLOOR_WIN + 1, n)):
				m = minf(m, float(base[j]))
			fl.append(m)
		gf[sd] = fl
	var gm := []   # the lowest sole point's height above its own ground, over both feet, per frame (the foot that is down)
	var root := []
	for i in n:
		var low := ""
		var lh := INF
		for k in ["hl", "tl", "hr", "tr"]:
			var h := float(ys[k][i]) - float(gf[k.right(1)][i])
			if h < lh:
				lh = h
				low = k
		gm.append(lh)
		root.append(-(vel[low][i] as Vector2))
	# the root's velocity: a running median over 9 frames, so a swinging foot cannot vote itself still
	var rmed := []
	for i in n:
		var xs := []
		var zs := []
		for j in range(maxi(i - 4, 0), mini(i + 5, n)):
			xs.append((root[j] as Vector2).x)
			zs.append((root[j] as Vector2).y)
		rmed.append(Vector2(_median(xs), _median(zs)))
	root = rmed
	var list := []
	var flag := {"_l": [], "_r": []}
	var piv := {}
	for sd in ["_l", "_r"]:
		var h: Array = ys["h" + sd.right(1)]
		var t: Array = ys["t" + sd.right(1)]
		var vh: Array = vel["h" + sd.right(1)]
		var vt: Array = vel["t" + sd.right(1)]
		var st := false
		var on := []
		for i in n:
			var gfi: float = gf[sd.right(1)][i]
			var hh := minf(float(h[i]), float(t[i])) - gfi
			var ground_v := minf(((vh[i] as Vector2) + (root[i] as Vector2)).length() if float(h[i]) - gfi < H_OFF else INF,
				((vt[i] as Vector2) + (root[i] as Vector2)).length() if float(t[i]) - gfi < H_OFF else INF)
			if st:
				st = hh < H_OFF and ground_v < V_OFF
			else:
				st = hh < H_ON and ground_v < V_ON
			on.append(st)
		flag[sd] = _clean_runs(on)
		for k in 2:   # the pivots that are down: the heel and the ball, each while it is within H_PIV of its ground
			var pv := []
			for i in n:
				pv.append(bool(flag[sd][i]) and float(ys[("h" if k == 0 else "t") + sd.right(1)][i]) - float(gf[sd.right(1)][i]) < H_PIV)
			piv["%s%d" % [sd, k]] = pv
	for sd in ["_l", "_r"]:
		for r in _runs_of(flag[sd]):
			list.append({"kind": "foot", "part": "foot" + sd, "f0": r[0], "f1": r[1], "t0": snappedf(float(frames[r[0]]["t"]) - T0, 0.001),
				"t1": snappedf(float(frames[r[1]]["t"]) - T0, 0.001)})
	# the hands: low and still against the ground (a crawl, a push-up, a hand on the floor)
	for sd in ["_l", "_r"]:
		var w: Array = ys["w" + sd.right(1)]
		var vw: Array = vel["w" + sd.right(1)]
		var on := []
		for i in n:
			on.append(float(w[i]) - minf(float(gf["l"][i]), float(gf["r"][i])) < HAND_H and ((vw[i] as Vector2) + (root[i] as Vector2)).length() < HAND_V)
		var cl := _clean_runs(on, HAND_MIN)
		for r in _runs_of(cl):
			list.append({"kind": "hand", "part": "hand" + sd, "f0": r[0], "f1": r[1], "t0": snappedf(float(frames[r[0]]["t"]) - T0, 0.001),
				"t1": snappedf(float(frames[r[1]]["t"]) - T0, 0.001)})
	list.sort_custom(func(a, b): return int(a["f0"]) < int(b["f0"]))
	var hint := []
	for i in n:
		var l: bool = flag["_l"][i]
		var r: bool = flag["_r"][i]
		hint.append("_l" if l and not r else ("_r" if r and not l else ""))
	return {"list": list, "hint": hint, "flags": flag, "piv": piv, "ground": gm, "root": root}


## a bool series with gaps of BRIDGE or fewer frames closed and runs under `min_run` dropped
static func _clean_runs(on: Array, min_run := MIN_RUN) -> Array:
	var n := on.size()
	var o := on.duplicate()
	var i := 0
	while i < n:
		if o[i]:
			i += 1
			continue
		var a := i
		while i < n and not o[i]:
			i += 1
		if a > 0 and i < n and i - a <= BRIDGE:
			for j in range(a, i):
				o[j] = true
	i = 0
	while i < n:
		if not o[i]:
			i += 1
			continue
		var a := i
		while i < n and o[i]:
			i += 1
		if i - a < min_run:
			for j in range(a, i):
				o[j] = false
	return o


static func _runs_of(on: Array) -> Array:
	var out := []
	var i := 0
	while i < on.size():
		if not on[i]:
			i += 1
			continue
		var a := i
		while i < on.size() and on[i]:
			i += 1
		out.append([a, i - 1])
	return out


## per-frame foot flags -> F1 against another series (the same layout): {"f1", "precision", "recall"}
static func f1(got: Array, truth: Array) -> Dictionary:
	var tp := 0
	var fp := 0
	var fn := 0
	for i in mini(got.size(), truth.size()):
		if got[i] and truth[i]:
			tp += 1
		elif got[i]:
			fp += 1
		elif truth[i]:
			fn += 1
	var p := float(tp) / maxf(float(tp + fp), 1.0)
	var r := float(tp) / maxf(float(tp + fn), 1.0)
	return {"f1": 2.0 * p * r / maxf(p + r, 1e-9), "precision": p, "recall": r}


## the contact runs as FootPlant plants (feet only), TRIM frames shorter at the toe-off end
static func plants_of(list: Array, fps: float) -> Array:
	var out := []
	for c in list:
		if c["kind"] != "foot":
			continue
		var t1 := float(c["t1"]) - TRIM / maxf(fps, 1.0)
		if t1 - float(c["t0"]) >= MIN_RUN / maxf(fps, 1.0):
			out.append({"foot": c["part"], "t0": c["t0"], "t1": t1})
	return out


## where each contact is on the floor, from the fitted body: the sole's middle (heel and ball) for a foot, the hand for a hand,
## the median over the contact's frames; "yaw" = the foot's direction (heel -> ball) in degrees about y. fitted is
## VideoImport.solve's output
static func locate(B: Body, fitted: Array, list: Array) -> Array:
	var keep := B.state()
	var out := []
	for c in list:
		var xs := []
		var zs := []
		var yws := []
		var ys := []
		for i in range(int(c["f0"]), int(c["f1"]) + 1):
			for j in fitted[i]["ang"]:
				B.ang[j] = fitted[i]["ang"][j]
			B.offset = fitted[i]["offset"]
			B.fk()
			var sd: String = String(c["part"]).right(2)
			if c["kind"] == "foot":
				var hl := VideoImport.heel(B, sd)
				var bl: Vector3 = B.P["ball" + sd]
				var m := (hl + bl) * 0.5
				xs.append(m.x)
				zs.append(m.z)
				ys.append(minf(hl.y, bl.y))
				yws.append(rad_to_deg(atan2(bl.x - hl.x, bl.z - hl.z)))
			else:
				var hp: Vector3 = B.P["hand" + sd]
				xs.append(hp.x)
				zs.append(hp.z)
				ys.append(hp.y)
		var d: Dictionary = c.duplicate()
		d["x"] = snappedf(_median(xs), 0.001)
		d["z"] = snappedf(_median(zs), 0.001)
		d["y"] = snappedf(_median(ys), 0.001)
		if not yws.is_empty():
			d["yaw"] = snappedf(_median(yws), 0.1)
		out.append(d)
	B.set_state(keep)
	return out


## where each contact is on the floor AS THE SCENE PLAYS IT (the footprints are drawn here): the final scene V (cards + plants)
## at the contact's middle (the middle of its overlap with a plant of the same foot when there is one: the planted foot stands
## still there), the sole's middle (heel, ball) for a foot, the hand for a hand. "t" = the time read. The dense fit's own
## spot (locate) can be 10 cm from where the planted, sparse scene puts the foot
static func locate_played(B: Body, V: Scene, list: Array) -> Array:
	var keep := B.state()
	var out := []
	for c in list:
		var a := float(c["t0"])
		var b := float(c["t1"])
		for p in V.plants:
			if p["foot"] == c["part"] and float(p["t0"]) < b and float(p["t1"]) > a:
				a = maxf(a, float(p["t0"]))
				b = minf(b, float(p["t1"]))
				break
		var t := (a + b) * 0.5
		V.apply(B, t)
		B.fk()
		var d: Dictionary = c.duplicate()
		var sd: String = String(c["part"]).right(2)
		if c["kind"] == "foot":
			var hl := VideoImport.heel(B, sd)
			var bl: Vector3 = B.P["ball" + sd]
			d["x"] = snappedf((hl.x + bl.x) * 0.5, 0.001)
			d["z"] = snappedf((hl.z + bl.z) * 0.5, 0.001)
			d["y"] = snappedf(minf(hl.y, bl.y), 0.001)
			d["yaw"] = snappedf(rad_to_deg(atan2(bl.x - hl.x, bl.z - hl.z)), 0.1)
		else:
			var hp: Vector3 = B.P["hand" + sd]
			d["x"] = snappedf(hp.x, 0.001)
			d["z"] = snappedf(hp.z, 0.001)
			d["y"] = snappedf(hp.y, 0.001)
		d["t"] = snappedf(t, 0.001)
		out.append(d)
	B.set_state(keep)
	return out


# ============================================================== 3 SMART KEYS =============================================

## the joints whose world position the replay error is read on
const ERR_JOINTS := ["pelvis", "spine_03", "head", "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]


## the curves the keys are chosen on: the joints' WORLD positions in cm (what the viewer sees; the joint angles of a dense fit
## carry twist ambiguities that move nothing, and chasing them cost 4 times the cards)
const FOOT_W := 1.0   # the feet's curves count this much more: a foot is the joint a viewer reads against the floor


static func _pos_features(ref: Array) -> Array:
	var out := []
	for p in ref:
		var v := PackedFloat32Array()
		for k in (p as PackedVector3Array).size():
			var q: Vector3 = (p as PackedVector3Array)[k]
			var w := FOOT_W if String(ERR_JOINTS[k]).begins_with("foot") or String(ERR_JOINTS[k]).begins_with("ball") else 1.0
			v.append(q.x * 100.0 * w)
			v.append(q.y * 100.0 * w)
			v.append(q.z * 100.0 * w)
		out.append(v)
	return out


## Douglas-Peucker over the feature curves: the frames kept, ascending
static func dp_keys(feat: Array, ts: Array, tol: float) -> Array:
	var n := feat.size()
	var keep := {0: true, n - 1: true}
	var stack := [[0, n - 1]]
	var D: int = (feat[0] as PackedFloat32Array).size()
	while not stack.is_empty():
		var s: Array = stack.pop_back()
		var a: int = s[0]
		var b: int = s[1]
		if b - a < 2:
			continue
		var span := maxf(float(ts[b]) - float(ts[a]), 1e-6)
		var worst := 0.0
		var wi := -1
		var fa: PackedFloat32Array = feat[a]
		var fb: PackedFloat32Array = feat[b]
		for i in range(a + 1, b):
			var u := (float(ts[i]) - float(ts[a])) / span
			var fi: PackedFloat32Array = feat[i]
			var e := 0.0
			for k in D:
				e = maxf(e, absf(fi[k] - (fa[k] + (fb[k] - fa[k]) * u)))
			if e > worst:
				worst = e
				wi = i
		if wi >= 0 and worst > tol:
			keep[wi] = true
			stack.append([a, wi])
			stack.append([wi, b])
	var ks := keep.keys()
	ks.sort()
	return ks


static func _positions(S: Scene, B: Body, ts: Array) -> Array:
	var out := []
	for t in ts:
		S.apply(B, float(t))
		var p := PackedVector3Array()
		for j in ERR_JOINTS:
			p.append(B.P[j])
		out.append(p)
	return out


## the mean and the worst joint position error (m) between two position lists
static func pos_error(a: Array, b: Array) -> Vector2:
	var sum := 0.0
	var cnt := 0
	var worst := 0.0
	for i in a.size():
		var pa: PackedVector3Array = a[i]
		var pb: PackedVector3Array = b[i]
		for k in pa.size():
			var d := pa[k].distance_to(pb[k])
			sum += d
			cnt += 1
			worst = maxf(worst, d)
	return Vector2(sum / maxf(float(cnt), 1.0), worst)


## SMART KEYS: the dense scene (a card per fitted frame) -> few cards at the motion's turning points, timing kept. The
## tolerance is bisected until the cards REPLAY (Scene.apply, linear and spline both tried) within `target` m mean joint error
## of the dense scene. Returns {"scene", "keys" (the frames kept), "mean", "worst" (m), "spline", "dense", "cards"}
static func smart_cards(B: Body, dense: Scene, fitted: Array, target := 0.0299, worst_cap := 0.3) -> Dictionary:
	var n := fitted.size()
	var ts := []
	var t0 := float(fitted[0]["t"])
	for fr in fitted:
		ts.append(float(fr["t"]) - t0)
	var ref := _positions(dense, B, ts)
	var feat := _pos_features(ref)
	var best := {}
	if n < 8:
		return {"scene": dense, "keys": range(n), "mean": 0.0, "worst": 0.0, "spline": false, "dense": n, "cards": n}
	for spline in [false, true]:
		var lo := 0.2
		var hi := 15.0
		for it in 12:
			var mid := sqrt(lo * hi)
			var idx := dp_keys(feat, ts, mid)
			var ex := {}
			for i in idx:
				ex[i] = true
			var V := VideoImport.thin(dense, 1000000, ex)
			V.spline = spline
			var e := pos_error(ref, _positions(V, B, ts))
			if e.x <= target and e.y <= worst_cap:
				lo = mid
				if best.is_empty() or idx.size() < int(best["cards"]) or (idx.size() == int(best["cards"]) and e.x < float(best["mean"])):
					best = {"scene": V, "keys": idx, "mean": e.x, "worst": e.y, "spline": spline, "dense": n, "cards": idx.size()}
			else:
				hi = mid
	if best.is_empty():   # nothing passed: every frame (the dense scene itself)
		best = {"scene": dense, "keys": range(n), "mean": 0.0, "worst": 0.0, "spline": false, "dense": n, "cards": n}
	return best


# ================================================================ THE WHOLE IMPORT =======================================

static func _ints(a: Array) -> Array:
	return a.map(func(v): return int(round(clampf(float(v), 0.0, 1.0) * 100.0)))


## parse -> confidence -> repair -> depth -> cleanup -> contacts -> fit -> smart cards -> plants. P = VideoImport.parse's result
## (its frames are changed). Returns {"scene", "iq", "text", "conf", "depth", "contacts", "keys", "fitted", "frames", "dense",
## "repaired"}. retarget = true fits with VideoRetarget (GMR-style IK, feet pinned on the contacts) instead of VideoImport.solve
static func process(B: Body, P: Dictionary, held := "", scene_name := "video_import", retarget := false) -> Dictionary:
	var fps := float(P["fps"])
	var frames: Array = VideoIQ.fill_gaps(P["frames"], fps)
	var conf := confidence(frames, fps)
	var repaired := repair(frames, conf)
	var dp := fix_depth(frames, P.get("axis", Vector3(0, 0, 1)), limits_of(B))
	var C := VideoCleanup.run(frames, fps, float(P.get("tilt", 0.0)))
	normalize_lengths(C["frames"])
	var K := contacts(C["frames"], fps)
	var fitted: Array
	if retarget and held == "":   # "Retarget to body (IK)": VideoRetarget, with THIS pass's contacts pinning the planted feet
		fitted = VideoRetarget.solve(C["frames"], B, {"fps": fps, "smooth": false, "iq": K})
	else:
		fitted = VideoImport.solve(B, C["frames"], held, fps, K["piv"])
	var dense := VideoImport.to_scene(B, fitted, fps, 1, scene_name)
	var sk := smart_cards(B, dense, fitted)
	var V: Scene = sk["scene"]
	V.plants = VideoCleanup.reachable(V, B, FootPlant.from_file(plants_of(K["list"], fps)), V.fps)
	var located := locate_played(B, V, K["list"])
	var feet := 0
	var hands := 0
	for c in located:
		if c["kind"] == "foot":
			feet += 1
		else:
			hands += 1
	var iq := {"fps": fps, "dt": snappedf(1.0 / fps, 0.0001), "conf": _ints(conf["c"]), "parts": {}, "spans": conf["spans"], "contacts": located,
		"keys": {"frames": fitted.size(), "cards": int(sk["cards"]), "mean_cm": snappedf(float(sk["mean"]) * 100.0, 0.01), "spline": bool(sk["spline"])},
		"depth": {"frames": int(dp["frames"]), "flipped": int(dp["flipped"])}, "repaired": repaired}
	for p in PARTS:
		iq["parts"][p] = _ints(conf["parts"][p])
	var txt := "%d contacts (%d foot, %d hand), %d plants hold; %d frames -> %d cards (%s, %.1f cm mean replay error); depth: %d chain-frames reflected, %d frames corrected; confidence: %d low spans%s" % [
		located.size(), feet, hands, V.plants.size(), fitted.size(), int(sk["cards"]), "spline" if sk["spline"] else "linear", float(sk["mean"]) * 100.0,
		int(dp["flipped"]), int(dp["frames"]), (conf["spans"] as Array).size(), ("; " + "; ".join((conf["spans"] as Array).map(func(s): return s["text"]))) if not (conf["spans"] as Array).is_empty() else ""]
	return {"scene": V, "iq": iq, "text": txt, "conf": conf, "depth": dp, "contacts": K, "keys": sk, "fitted": fitted, "frames": C["frames"],
		"dense": dense, "repaired": repaired, "located": located}


## the iq dict of a scene file, kept only if it is well formed (a hand-edited file never crashes the timeline)
static func from_file(d: Variant) -> Dictionary:
	if not d is Dictionary:
		return {}
	var out := {}
	if (d as Dictionary).get("conf", null) is Array and ((d as Dictionary)["conf"] as Array).size() > 1:
		out = (d as Dictionary).duplicate(true)
		if not out.get("spans", []) is Array:
			out["spans"] = []
		if not out.get("contacts", []) is Array:
			out["contacts"] = []
		out["dt"] = maxf(float(out.get("dt", 1.0 / 30.0)), 0.001)
	return out


## the scene file's form: the same dictionary (a copy), nothing but numbers, strings and arrays
static func to_file(iq: Dictionary) -> Dictionary:
	return iq.duplicate(true)


## MIRROR: the left and right swap (parts, contact feet), the floor x negated, yaw negated
static func mirror_file(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return d
	var out: Dictionary = d.duplicate(true)
	var twin := func(p: String) -> String:
		if p.ends_with("_l"):
			return p.left(p.length() - 2) + "_r"
		if p.ends_with("_r"):
			return p.left(p.length() - 2) + "_l"
		return p
	var parts := {}
	for p in (d.get("parts", {}) as Dictionary):
		parts[twin.call(p)] = d["parts"][p]
	out["parts"] = parts
	for s in out.get("spans", []):
		s["part"] = twin.call(s["part"])
		s["what"] = String(s["what"]).replace("left", "L#").replace("right", "left").replace("L#", "right")
		s["text"] = String(s["text"]).replace("left", "L#").replace("right", "left").replace("L#", "right")
	for c in out.get("contacts", []):
		c["part"] = twin.call(c["part"])
		c["x"] = -float(c.get("x", 0.0))
		if c.has("yaw"):
			c["yaw"] = -float(c["yaw"])
	return out
