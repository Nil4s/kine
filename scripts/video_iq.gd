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


# ============================================================ 3b TORSO SPIKES ==============================================
## A TRACKER GLITCH ON THE TORSO (round 58, cmb02_cross: the left shoulder moved 0.3 m in one frame at 3.00 s at visibility 1.00, and
## the arm fitted from it peaked at 48.6 m/s). Two tests on the shoulders (11, 12) and hips (23, 24), on the file's own frames:
##   P a point more than TORSO_DEV from the mean of its two neighbours, while the neighbours agree (under TORSO_AGREE apart), is replaced
##     by that mean
##   W the shoulder width (11 to 12) more than TORSO_WIDTH off the mean of its neighbours' widths (when those are wide enough to read)
##     is a glitch: both shoulders of that frame are replaced by the mean of the neighbours' shoulders
## Returns how many landmark-frames were replaced. The neighbours are read before any change (no cascade).
const TORSO := [11, 12, 23, 24]
const TORSO_DEV := 0.12       # m
const TORSO_AGREE := 0.05     # m
const TORSO_WIDTH := 0.25     # fraction of the neighbours' mean width
const WIDTH_MIN := 0.05       # m: a shoulder width under this is too narrow to read a ratio from


## MOCAP QUALITY: LEFT / RIGHT LIMB FLIPS, repaired by continuity. A tracker that loses which leg is which for a few frames swaps the
## two limbs' labels (a seeded 4-frame ankle/knee/heel/toe swap on the turn clip put 8 flips through the whole pipeline and took the
## body jitter from 4.1 to 10.9). Per limb group (the legs) a frame is a FLIP EVENT when keeping the labels
## moves the pair by more than FLIP_JUMP on average while swapping them moves it less than half as far (continuity says swapped). A
## flip is an event IN and an event OUT within FLIP_MAX frames: those frames' two labels are exchanged. An event with no partner is a
## label swap that stays (or a leg crossing the other): left alone, so a real crossing step is never "repaired".
const FLIP_JUMP := 0.10   # m: the average jump per pair of the labels as they are
const FLIP_MAX := 12      # frames: a swap that lasts longer than this is not a tracker blip
const FLIP_GROUPS := [[[25, 26], [27, 28], [29, 30], [31, 32]]]   # the legs only: arms and hands cross in a push-up, a pick-up, a bat swing (peak hand speed moved 20-70 % on them)
static var flip_fix := true
static func fix_flips(frames: Array) -> int:
	var fixed := 0
	for g in FLIP_GROUPS:
		var ev := []
		for i in range(1, frames.size()):
			var w0: Array = frames[i - 1]["w"]
			var w1: Array = frames[i]["w"]
			var same := 0.0
			var swap := 0.0
			for pr in g:
				var l0: Vector3 = w0[pr[0]]
				var r0: Vector3 = w0[pr[1]]
				var l1: Vector3 = w1[pr[0]]
				var r1: Vector3 = w1[pr[1]]
				same += l1.distance_to(l0) + r1.distance_to(r0)
				swap += l1.distance_to(r0) + r1.distance_to(l0)
			if same / float(g.size()) > FLIP_JUMP and swap < 0.5 * same:
				ev.append(i)
		var k := 0
		while k + 1 < ev.size():
			if int(ev[k + 1]) - int(ev[k]) <= FLIP_MAX:
				for i in range(int(ev[k]), int(ev[k + 1])):
					var w: Array = frames[i]["w"]
					var vis: Array = frames[i].get("vis", [])
					for pr in g:
						var tmp: Vector3 = w[pr[0]]
						w[pr[0]] = w[pr[1]]
						w[pr[1]] = tmp
						if vis.size() > int(pr[1]):
							var tv: Variant = vis[pr[0]]
							vis[pr[0]] = vis[pr[1]]
							vis[pr[1]] = tv
					fixed += 1
				k += 2
			else:
				k += 1
	return fixed


static func torso_filter(frames: Array) -> int:
	var n := frames.size()
	var done := 0
	var snap := []
	for f in frames:
		var c := []
		for w in (f["w"] as Array):
			c.append(w)
		snap.append(c)
	for i in range(1, n - 1):
		var prv: Array = snap[i - 1]
		var cur: Array = snap[i]
		var nxt: Array = snap[i + 1]
		var out: Array = frames[i]["w"]
		for k in TORSO:
			var a: Vector3 = prv[k]
			var b: Vector3 = nxt[k]
			var m := (a + b) * 0.5
			if (cur[k] as Vector3).distance_to(m) > TORSO_DEV and a.distance_to(b) < TORSO_AGREE:
				out[k] = m
				done += 1
		var wc: float = (cur[11] as Vector3).distance_to(cur[12] as Vector3)
		var wn: float = ((prv[11] as Vector3).distance_to(prv[12] as Vector3) + (nxt[11] as Vector3).distance_to(nxt[12] as Vector3)) * 0.5
		if wn > WIDTH_MIN and absf(wc / wn - 1.0) > TORSO_WIDTH:
			out[11] = ((prv[11] as Vector3) + (nxt[11] as Vector3)) * 0.5
			out[12] = ((prv[12] as Vector3) + (nxt[12] as Vector3)) * 0.5
			done += 2
	return done


# ============================================================ 3c UPPER-BODY DIPS ==========================================
## A TRACKER GLITCH THAT MOVES THE WHOLE UPPER BODY (the spike clips, round 59): for 1 to 5 frames the head, shoulders, elbows and
## wrists all move together, relative to the hips, and come back. pick_up frames 45-47: the tracker's upper body swings about 0.4 m
## from where it was in frames 44 and 48 (the wrists go from -0.87 m to +0.11 m and back in one frame each way: 15 m/s). torso_filter's
## per-point test cannot see it: every point of the block agrees with the others. So this test works on the block as a whole:
##   C  the block's centre = the mean of landmarks 0-22 (nose to index fingers) less the hips' mid point (a whole-body move, a jump
##      or a drop, leaves C where it was: the block is measured from the hips)
##   a run of 1 to DIP_MAX_LEN frames where C departs from the line between the frame before and the frame after by more than
##     DIP_DEV, with those two frames agreeing within DIP_AGREE
##   its departure rate (the largest frame-to-frame move of C across the run and its two ends, per second) is more than DIP_RATE
##     times the body's own median rate over the clip (and at least DIP_MIN_RATE): a slow lean, a crouch, a real fast move that does
##     not come back within 5 frames is not this
## Replaced by linear interpolation across the gap for landmarks 0-22 (the hips and legs keep their values).
## dip_runs returns the runs as [first, last, departure, rate]; dip_filter applies them and returns the landmark-frames replaced.
const DIP_MAX_LEN := 5
const DIP_DEV := 0.10         # m: the block centre's departure from the line between its neighbours
const DIP_AGREE := 0.10       # m: the frames before and after the run agree this closely
const DIP_RATE := 5.0         # x the body's median rate of the block centre
const DIP_MIN_RATE := 1.0     # m/s: the rate floor (a still clip has a median near 0)
const DIP_LAST_UPPER := 22    # landmarks 0 to 22 move with the upper body; 23 on is the hips and the legs


static func _block_c(w: Array) -> Vector3:
	var c := Vector3.ZERO
	for j in range(DIP_LAST_UPPER + 1):
		c += (w[j] as Vector3)
	c /= float(DIP_LAST_UPPER + 1)
	return c - (((w[23] as Vector3) + (w[24] as Vector3)) * 0.5)


static func dip_runs(frames: Array, fps: float) -> Array:
	var n := frames.size()
	var out := []
	if n < 7:
		return out
	var C := []
	for f in frames:
		C.append(_block_c(f["w"]))
	var rates := []
	for i in range(1, n):
		rates.append((C[i] as Vector3).distance_to(C[i - 1]) * fps)
	var lim := maxf(DIP_RATE * _median(rates), DIP_MIN_RATE)
	var a := 1
	while a < n - 1:
		var found := false
		for L in range(1, DIP_MAX_LEN + 1):
			var b := a + L - 1
			if b > n - 2:
				break
			var c0: Vector3 = C[a - 1]
			var c1: Vector3 = C[b + 1]
			if c0.distance_to(c1) > DIP_AGREE:
				continue
			var worst := 0.0
			for k in range(a, b + 1):
				var t := float(k - (a - 1)) / float(b + 1 - (a - 1))
				worst = maxf(worst, (C[k] as Vector3).distance_to(c0.lerp(c1, t)))
			if worst <= DIP_DEV:
				continue
			var rate := 0.0
			for k in range(a, b + 2):
				rate = maxf(rate, (C[k] as Vector3).distance_to(C[k - 1]) * fps)
			if rate > lim:
				out.append([a, b, worst, rate])
				found = true
				break
		a = (out[out.size() - 1][1] + 2) if found else a + 1   # the frame after a run is a return point
	return out


static func dip_filter(frames: Array, fps: float) -> int:
	var done := 0
	for r in dip_runs(frames, fps):
		var a: int = r[0]
		var b: int = r[1]
		var p: Array = frames[a - 1]["w"]
		var q: Array = frames[b + 1]["w"]
		for k in range(a, b + 1):
			var t := float(k - (a - 1)) / float(b + 1 - (a - 1))
			var w: Array = frames[k]["w"]
			for j in range(DIP_LAST_UPPER + 1):
				w[j] = (p[j] as Vector3).lerp(q[j] as Vector3, t)
				done += 1
	return done


# ============================================================ 3d INVERTED BODY ============================================
## A TRACKER FLIP ABOUT THE HIPS (cmb02_cross, tests/data/spike_cross_pose.json, 2.9-3.7 s): the tracker turns the whole body upside
## down about the hips, the shoulders go from above the hips to below them and the ankles from below to above, and then back; the
## frames either side of the flip are lost. The body did not move that way, so the hand peak (16.4 m/s) was the flip's. A run is one
## when it is bounded by upright frames and is brief:
##   U  the frame before and the frame after are upright: the shoulder centre above the hip centre by INV_UP on the clip's own up axis
##   I  the frames between them include inverted ones (the shoulder centre below the hip centre by INV_UP)
##   T  the first and last inverted frames are within INV_TRANS frames of the upright ones (a flip, not a slow turn; a cartwheel
##      goes through the sideways pose for longer than that)
##   L  the inverted stretch, first to last inverted frame, is INV_MAX_LEN s or less (a handstand is not a tracker flip)
## The whole stretch between the two upright frames is lost: every landmark is the straight line between those two frames (as
## fill_gaps does), and the frames are marked "lost" so the confidence lane and the Easy caution name the span (the repair then
## leaves them as they are: the line is its own fill). INVERSION_FILL = false is the pre-fix pipeline, for the before numbers.
const INV_UP := 0.10        # m: the shoulder centre this far off the hip centre, on the body's own up axis, is upright (+) or inverted (-)
const INV_TRANS := 3        # frames: at most this many frames between the last upright frame and the first inverted one, and back
const INV_MAX_LEN := 1.0    # s: first to last inverted frame
const INV_MIN_FRAMES := 3  # frames: inverted readings in the run; one or two are blips (the pick-up has single-frame ones)
const INV_MIRROR := 0.10    # m: the shoulders' left-right axis this far on the wrong side (the tracker swapped left and right): not an upright anchor
static var stage_ms := {}   # MOCAP QUALITY: ms per stage of the last process() ("prep", "cleanup", "contacts", "fit", "cards", "plants"), tests/mocapq_test.gd
static var _lap_t := 0
static func _lap(stage: String) -> void:
	var now := Time.get_ticks_usec()
	stage_ms[stage] = float(stage_ms.get(stage, 0.0)) + (now - _lap_t) / 1000.0
	_lap_t = now
static var reach_applies := 0   # Scene.apply calls the last VideoCleanup.reachable made (tests/vidspeed_test.gd 3c)
static var INVERSION_FILL := true


## the flip runs as {"p", "q" (the upright frames either side), "lo", "hi" (the frames replaced: p+1 to q-1), "t0", "t1" (the inverted
## stretch, seconds on the file's clock)}. Lost frames (fill_gaps) are neither upright nor inverted: they only count as frames between
static func inversion_spans(frames: Array, fps: float) -> Array:
	var out := []
	var n := frames.size()
	if n < 3:
		return out
	var dt := 1.0 / maxf(fps, 1.0)
	var dy := []
	var mx := []   # the shoulders' left-right axis, x: a MIRRORED body (the tracker swapped left and right) reads negative
	var real_ank := []   # the ankles' centre less the hips' (y): a standing body has its ankles BELOW its hips (y runs down)
	var real_mx := []
	for i in n:
		if bool(frames[i].get("lost", false)):
			dy.append(0.0)
			mx.append(0.0)
			continue
		var w: Array = frames[i]["w"]
		var v := ((w[11] as Vector3).y + (w[12] as Vector3).y - (w[23] as Vector3).y - (w[24] as Vector3).y) * 0.5
		var m := (w[11] as Vector3).x - (w[12] as Vector3).x
		dy.append(v)
		mx.append(m)
		real_ank.append(((w[27] as Vector3).y + (w[28] as Vector3).y - (w[23] as Vector3).y - (w[24] as Vector3).y) * 0.5)
		real_mx.append(m)
	if real_ank.is_empty():
		return out
	var k := -1.0 if _median(real_ank) > 0.0 else 1.0   # up = away from the feet: the usual side, read from the ankles (the shoulders swing in a bend)
	var kx := -1.0 if _median(real_mx) < 0.0 else 1.0  # the usual left-right side
	var st := []   # 1 upright, -1 inverted or mirrored, 0 between (sideways), 2 lost
	var ups := []
	for i in n:
		if bool(frames[i].get("lost", false)):
			st.append(2)
			continue
		# a flip is UPSIDE DOWN (the vertical test); a shoulder swap alone (the body upright, left and right exchanged: combo3's 0.9 s)
		# is not one, and is no upright anchor either: a swap inside a real flip (cross, 3.0 s) is still replaced with it
		var s := 0
		var swapped := kx * float(mx[i]) <= -INV_MIRROR
		if k * float(dy[i]) <= -INV_UP:
			s = -1
		elif k * float(dy[i]) >= INV_UP and not swapped:
			s = 1
			ups.append(i)
		st.append(s)
	for x in range(ups.size() - 1):
		var p: int = ups[x]
		var q: int = ups[x + 1]
		var a := -1
		var b := -1
		var cnt := 0
		for i in range(p + 1, q):
			if int(st[i]) == -1:
				if a < 0:
					a = i
				b = i
				cnt += 1
		if a < 0 or cnt < INV_MIN_FRAMES:   # a single inverted reading is a blip (the pick-up's, 2.19 s), not a flip
			continue
		var gap_in := int(round((float(frames[a]["t"]) - float(frames[p]["t"])) / dt)) - 1
		var gap_out := int(round((float(frames[q]["t"]) - float(frames[b]["t"])) / dt)) - 1
		var span := float(frames[b]["t"]) - float(frames[a]["t"])
		if gap_in > INV_TRANS or gap_out > INV_TRANS or span > INV_MAX_LEN:
			continue
		out.append({"p": p, "q": q, "lo": p + 1, "hi": q - 1, "t0": float(frames[a]["t"]), "t1": float(frames[b]["t"])})
	return out


## replaces each flip's frames by the straight line (all 33 landmarks, by time) between its two upright frames and marks them lost.
## Returns how many frames were replaced
static func inversion_filter(frames: Array, fps: float) -> int:
	if not INVERSION_FILL:
		return 0
	var done := 0
	var z := []
	z.resize(33)
	z.fill(0.0)
	for r in inversion_spans(frames, fps):
		var p: int = r["p"]
		var q: int = r["q"]
		var tp := float(frames[p]["t"])
		var tq := float(frames[q]["t"])
		var wp: Array = frames[p]["w"]
		var wq: Array = frames[q]["w"]
		for i in range(int(r["lo"]), int(r["hi"]) + 1):
			var u := (float(frames[i]["t"]) - tp) / maxf(tq - tp, 1e-6)
			var w: Array = frames[i]["w"]
			for j in 33:
				w[j] = (wp[j] as Vector3).lerp(wq[j] as Vector3, u)
			frames[i]["lost"] = true
			frames[i]["vis"] = z.duplicate()
			done += 1
	return done


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


## the landmarks of every flagged run (confidence < LOW) filled from the good frames either side (held at the clip's ends).
## A HAND or FOOT run the body still shows is filled by its JOINT ANGLES (_fill_limb: each bone's direction turns along the arc between its two
## good ends along the Hermite curve through their speeds (an ease in / out), the bone keeps its length; a foot planted on its other foot is held). Other parts
## keep the straight line of their points. Runs longer than GAP_FILL are left. Returns how many landmark-frames were replaced
static var ANGLE_FILL := true   # false: every run is the straight line of its points (the pre-fix fill, for the before / after numbers)
const LIMB := {   # part -> the chain (root, mid, tip) the angle fill turns, and the points carried with the tip (a foot's heel, toe)
	"hand_l": {"root": 11, "mid": 13, "tip": 15, "ext": []}, "hand_r": {"root": 12, "mid": 14, "tip": 16, "ext": []},
	"foot_l": {"root": 23, "mid": 25, "tip": 27, "ext": [29, 31]}, "foot_r": {"root": 24, "mid": 26, "tip": 28, "ext": [30, 32]}}
const BEND_MIN := 0.14     # rad (8 deg): a joint bent less than this has no hinge plane to read at its good end
const PLANT_MOVE := 0.03   # m: the other ankle moves no more than this (over the span and a quarter second either side) to read as planted
const PLANT_PELVIS := 5.0  # deg: the hip line turns no more than this between the span's two good ends: the pelvis is steady


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
			if ANGLE_FILL and LIMB.has(p) and not _body_lost(conf, a, b):
				done += _fill_limb(frames, conf, p, a, b)
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


## the whole body is flagged somewhere in a..b (the tracker lost the person, not one limb): that run is a straight line as before
## (the joint-angle fill is for a limb lost on its own; it moved the feet of walk_bat's 8 lost frames past the contact bar)
static func _body_lost(conf: Dictionary, a: int, b: int) -> bool:
	for i in range(a, b + 1):
		if float((conf["parts"]["body"] as Array)[i]) < LOW:
			return true
	return false


## one limb's flagged run (a hand: shoulder - elbow - wrist; a foot: hip - knee - ankle, the heel and toe carried with the ankle),
## filled from its two good frames by joint angles (_turn). A run at a clip's end holds the nearest good pose (in the root's frame,
## so the body's own motion stays). Returns the landmark-frames written
static func _fill_limb(frames: Array, conf: Dictionary, p: String, a: int, b: int) -> int:
	var L: Dictionary = LIMB[p]
	var root: int = L["root"]
	var mid: int = L["mid"]
	var tip: int = L["tip"]
	var ext: Array = L["ext"]
	var pts: Array = [mid, tip] + ext
	var n := frames.size()
	var ia := a - 1
	var ib := b + 1
	if ia < 0 or ib >= n:   # the run touches a clip's end: hold the nearest good pose
		var G: Array = frames[ia if ia >= 0 else ib]["w"]
		for i in range(a, b + 1):
			var W: Array = frames[i]["w"]
			for k in pts:
				W[k] = ((G[k] as Vector3) - (G[root] as Vector3)) + (W[root] as Vector3)
		return (b - a + 1) * pts.size()
	var A: Array = frames[ia]["w"]
	var B: Array = frames[ib]["w"]
	if p.begins_with("foot") and _planted(frames, conf, p, a, b):
		# the other foot is planted and the pelvis steady: this foot stays where it is (the mean of its two good ends)
		for i in range(a, b + 1):
			var W: Array = frames[i]["w"]
			for k in pts:
				W[k] = ((A[k] as Vector3) + (B[k] as Vector3)) * 0.5
		return (b - a + 1) * pts.size()
	var dt := float(conf["dt"])
	var T := float(ib - ia) * dt
	var good: Array = conf["parts"][p]
	var pre: Array = frames[ia - 1]["w"] if ia >= 1 and float(good[ia - 1]) >= LOW else []
	var nxt: Array = frames[ib + 1]["w"] if ib + 1 < n and float(good[ib + 1]) >= LOW else []
	var d1A := _dir(A, root, mid)
	var d1B := _dir(B, root, mid)
	var d2A := _dir(A, mid, tip)
	var d2B := _dir(B, mid, tip)
	var L1 := ((A[mid] as Vector3) - (A[root] as Vector3)).length() * 0.5 + ((B[mid] as Vector3) - (B[root] as Vector3)).length() * 0.5
	var L2 := ((A[tip] as Vector3) - (A[mid] as Vector3)).length() * 0.5 + ((B[tip] as Vector3) - (B[mid] as Vector3)).length() * 0.5
	# the bones' own velocities at the two good ends (one frame either side), so the fill leaves the span at the speed the
	# limb was moving: a limb in motion at the span's edge is not held still by an ease with zero speed at both ends
	var d1p = _dir(pre, root, mid) if not pre.is_empty() else null
	var d1n = _dir(nxt, root, mid) if not nxt.is_empty() else null
	var d2p = _dir(pre, mid, tip) if not pre.is_empty() else null
	var d2n = _dir(nxt, mid, tip) if not nxt.is_empty() else null
	var fA := Vector3.ZERO
	var fB := Vector3.ZERO
	var fp = null
	var fn = null
	if not ext.is_empty():
		fA = _dir(A, tip, ext[1])
		fB = _dir(B, tip, ext[1])
		fp = _dir(pre, tip, ext[1]) if not pre.is_empty() else null
		fn = _dir(nxt, tip, ext[1]) if not nxt.is_empty() else null
	# the bend (the angle between the two bones) at each good end, its speed from the frame beside it, and the hinge there
	var bA := d1A.angle_to(d2A)
	var bB := d1B.angle_to(d2B)
	var M0b := 0.0
	var M1b := 0.0
	if d1p != null:
		M0b = (bA - float(d1p.angle_to(d2p))) / dt * T
	if d1n != null:
		M1b = (float(d1n.angle_to(d2n)) - bB) / dt * T
	var hA := (d1A.cross(d2A)).normalized() if bA >= BEND_MIN else Vector3.ZERO
	var hB := (d1B.cross(d2B)).normalized() if bB >= BEND_MIN else Vector3.ZERO
	for i in range(a, b + 1):
		var s := float(i - ia) / float(ib - ia)
		var W: Array = frames[i]["w"]
		var d1 := _turn(d1A, d1B, d1p, d1n, T, dt, s)
		var M: Vector3 = (W[root] as Vector3) + d1 * L1
		# the forearm = the upper arm turned about the HINGE by the bend: the hinge (the bend's plane) and the bend are
		# interpolated, not the forearm's own direction, so the plane cannot swing when the joint is nearly straight
		var hn := _hinge(hA, hB, d1A, d1B, s)
		var bend := _herm(bA, bB, M0b, M1b, s)
		var Tp: Vector3 = M + (Quaternion(hn, bend) * d1) * L2
		W[mid] = M
		W[tip] = Tp
		if not ext.is_empty():
			var Rf := Quaternion(fA, _turn(fA, fB, fp, fn, T, dt, s))
			for k in ext:
				W[k] = Tp + Rf * ((A[k] as Vector3) - (A[tip] as Vector3))
	return (b - a + 1) * pts.size()


## the unit direction of the bone a -> b in a frame
static func _dir(W: Array, a: int, b: int) -> Vector3:
	return ((W[b] as Vector3) - (W[a] as Vector3)).normalized()


## the hinge (the bend's plane normal) at fraction s: slerped between the two good ends' hinges when both bend enough to read a
## plane (BEND_MIN), else the one that does; when neither does, the normal of the two upper bones' own turn
static func _hinge(hA: Vector3, hB: Vector3, d1A: Vector3, d1B: Vector3, s: float) -> Vector3:
	if hA != Vector3.ZERO and hB != Vector3.ZERO:
		var nb := hB
		if hA.dot(nb) < 0.0:
			nb = -nb
		return (Quaternion.IDENTITY.slerp(Quaternion(hA, nb), s) * hA).normalized()
	if hA != Vector3.ZERO:
		return hA
	if hB != Vector3.ZERO:
		return hB
	var ax := d1A.cross(d1B)
	return ax.normalized() if ax.length() > 1e-9 else Vector3.UP


## a cubic Hermite between a and b with speeds m0, m1 (in units of the value per span) at fraction s
static func _herm(a: float, b: float, m0: float, m1: float, s: float) -> float:
	var s2 := s * s
	var s3 := s2 * s
	return (2.0 * s3 - 3.0 * s2 + 1.0) * a + (s3 - 2.0 * s2 + s) * m0 + (-2.0 * s3 + 3.0 * s2) * b + (s3 - s2) * m1


## a bone's direction at fraction s (0..1) of a span of T seconds, from dA (the good end before) to dB (the good end after): the
## arc between them about its own axis, with the Hermite curve through the two ends' angular speeds (dp, dn: the direction one
## frame before / after, null when that frame is not good: then the speed is 0 and the curve is the smoothstep, an ease in / out)
static func _turn(dA: Vector3, dB: Vector3, dp, dn, T: float, dt: float, s: float) -> Vector3:
	var th := dA.angle_to(dB)
	var ax := dA.cross(dB)
	if th < 1e-9 or ax.length() < 1e-9:
		return dA.lerp(dB, s).normalized() if dA.lerp(dB, s).length() > 1e-9 else dA
	ax = ax.normalized()
	var m0 := 0.0
	var m1 := 0.0
	if dp != null:
		m0 = dp.angle_to(dA) * signf(dp.cross(dA).dot(ax)) / dt * T
	if dn != null:
		m1 = dB.angle_to(dn) * signf(dB.cross(dn).dot(ax)) / dt * T
	var s2 := s * s
	var s3 := s2 * s
	var ang := (s3 - 2.0 * s2 + s) * m0 + (-2.0 * s3 + 3.0 * s2) * th + (s3 - s2) * m1
	return Quaternion(ax, ang) * dA


## a foot's run is planted when the OTHER foot is good and barely moves over the run (and a quarter second either side) and the
## hip line turns less than PLANT_PELVIS between the run's two good ends
static func _planted(frames: Array, conf: Dictionary, p: String, a: int, b: int) -> bool:
	var other := "foot_r" if p == "foot_l" else "foot_l"
	var dt := float(conf["dt"])
	var win := int(round(0.25 / maxf(dt, 1e-6)))
	var n := frames.size()
	var lo := maxi(a - win, 0)
	var hi := mini(b + win, n - 1)
	var ank: int = LIMB[other]["tip"]
	var mean := Vector3.ZERO
	var cnt := 0
	for i in range(lo, hi + 1):
		if float((conf["parts"][other] as Array)[i]) < LOW:
			return false
		mean += (frames[i]["w"] as Array)[ank] as Vector3
		cnt += 1
	mean /= float(maxi(cnt, 1))
	for i in range(lo, hi + 1):
		if ((frames[i]["w"] as Array)[ank] as Vector3).distance_to(mean) > PLANT_MOVE:
			return false
	var hA: Vector3 = (((frames[a - 1]["w"] as Array)[24] as Vector3) - ((frames[a - 1]["w"] as Array)[23] as Vector3)).normalized()
	var hB: Vector3 = (((frames[b + 1]["w"] as Array)[24] as Vector3) - ((frames[b + 1]["w"] as Array)[23] as Vector3)).normalized()
	return rad_to_deg(hA.angle_to(hB)) < PLANT_PELVIS


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
const CONSENSUS_V := 0.2  # m/s: two low points whose implied root velocities are this close agree on it (contacts)
static var CONS_H := 0.04  # m: only a point this near its ground votes (H_OFF = 0.08 let a foot sliding through a shuffle outvote the planted one)
const BRIDGE := 2         # frames: contact runs this close are one
const MIN_RUN := 3        # frames: a shorter run is a tap
const HAND_H := 0.15      # m above the ground under the soles: a hand this low can be on it
const HAND_V := 0.25
const HAND_MIN := 4
const FLOOR_WIN := 20     # frames: a foot's ground is the lowest it gets within this many frames either side
const HEEL_UP := 0.03     # m: a heel this far above its own ground has left it (the ball roll: a plant then holds the ball, FootPlant "th")
const TRIM := 1           # frames cut off the end of a plant (the toe-off). R14c set 0 (coverage 61 vs 55 %) but the held foot then slid 8.3 cm on combo3 (videoiq 1b, bar 1 cm); 2 gives 0.4 cm


## FLIGHT (round 56; Nick: the hurdles clip's trail foot was "planted" 3.56-4.06 s while the athlete cleared the hurdle, and the high
## jump's body ended on the floor). The tracker's hips-relative landmarks cannot see a rigid rise (the whole body moves, the feet
## stay where they are against the hips), and Body.ground() put the lowest sole on the floor every frame, so a jump was never
## in the scene. The image can: the hips' and the ankles' image heights in the same picture. The metres per image unit come
## from the leg itself (the ankles' image height above the hips over their world height above the hips, the first frames),
## and the pelvis's rise is its image height against its standing height. A frame is airborne when that rise is FLY_RISE or more;
## a run shorter than FLY_MIN frames is a blink. {"on": [bool per frame], "rise": [m per frame, + up]}; empty when the file has no image.
const FLY_RISE := 0.12     # m: the pelvis this far above its standing height is in the air (a stride's bob is ~5 cm)
const FLY_MIN := 4         # frames: a shorter airborne run is not a flight


static func _hips_ankles_seen(f: Dictionary) -> bool:
	var vis: Array = f.get("vis", [])
	if vis.size() < 29:
		return true
	return minf(minf(float(vis[23]), float(vis[24])), minf(float(vis[27]), float(vis[28]))) >= 0.5


static func flight_of(frames: Array) -> Dictionary:
	var n := frames.size()
	var on := []
	var rise := []
	for i in n:
		on.append(false)
		rise.append(0.0)
	if n < 3 or not (frames[0] as Dictionary).has("hy") or not (frames[0] as Dictionary).has("ay"):
		return {"on": on, "rise": rise}
	var ref := 0.0
	var ppm := 0.0
	var k := mini(3, n)
	for i in k:
		var f: Dictionary = frames[i]
		var w: Array = f["w"]
		var leg := -((w[27] as Vector3).y + (w[28] as Vector3).y) * 0.5   # ankles below the hips, m (y up)
		ref += float(f["hy"]) / float(k)
		if leg > 0.1:
			ppm += (float(f["ay"]) - float(f["hy"])) / leg / float(k)
	if ppm <= 0.0:
		return {"on": on, "rise": rise}
	var air := []
	for i in n:
		# a frame whose hips or ankles the tracker does not see (visibility under 0.5) has no image height to read: it is grounded
		var r := (ref - float(frames[i]["hy"])) / ppm if _hips_ankles_seen(frames[i]) else 0.0
		rise[i] = r
		air.append(r >= FLY_RISE)
	var runs := _clean_runs(air, FLY_MIN)
	for i in n:
		on[i] = bool(runs[i])
	return {"on": on, "rise": rise}


## the body's height for one frame: the lowest sole on the floor (Body.ground) unless the frame is airborne (flight_of): then the
## body keeps the rise the image shows above its last grounded height, so a jump stays in the air. When the flight ends, the
## height eases from the last flight height to the grounded one over BLEND_IN frames (no pelvis step at the landing), so the
## body does not drop in one frame. `last` carries the grounded height and the rise there (empty until the first grounded frame).
const BLEND_IN := 6        # frames: the landing eases from the flight's height to the floor's over this many frames
static func vertical(B: Body, fly: Dictionary, i: int, last: Dictionary) -> void:
	var on: Array = fly.get("on", [])
	if i < on.size() and bool(on[i]) and last.has("y"):
		B.offset.y = float(last["y"]) + float(fly["rise"][i]) - float(last["r"])
		last["fly"] = B.offset.y
		last["landing"] = true
		B.fk()
		return
	B.ground()
	var g := B.offset.y
	if last.get("landing", false):
		last["from"] = float(last.get("fly", g))
		last["n"] = 0
		last["landing"] = false
	if last.has("from") and int(last["n"]) < BLEND_IN:
		last["n"] = int(last["n"]) + 1
		B.offset.y = lerpf(float(last["from"]), g, float(last["n"]) / float(BLEND_IN))
		B.fk()
	last["y"] = g
	last["r"] = float(fly["rise"][i]) if i < (fly.get("rise", []) as Array).size() else 0.0


static func _hxz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## CONTACTS on landmark frames {"t","w"} (hips-relative). Returns {"list": [{"kind": "foot"/"hand", "part", "f0", "f1", "t0",
## "t1"}] by f0 (t from the first frame), "hint": [per frame "_l" / "_r" / "" : the one foot down], "ground": per-frame ground
## height relative to the hips, "root": per-frame root velocity (xz, m/s)}
## `seen` (optional) {"_l": [bool], "_r": [bool]} per frame: false where the tracker LOST that foot (confidence under LOST). A
## lost foot gives no evidence of a contact: its landmarks are the repair's fill (a held or straight-line guess), which reads
## as low and still, and a whole clip of it planted the foot over 1 s of the body walking away (93 cm of slide on a 20-frame
## AI walk). A contact run more than half unseen is dropped; one crossing a short dropout stays
static func contacts(frames: Array, fps: float, fly := {}, seen := {}) -> Dictionary:
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
		# R14b: the root's velocity is the one the LOW points agree on. In a double support the lowest point alone can be the
		# trailing foot's toe, still rolling off (hips-relative speed != the root's), and a 9-frame median of that put 0.4-1 m/s on
		# the leading foot at its heel strike (it then read as moving and its stance started 6-8 frames late). Every point within
		# H_OFF of its own ground votes with -its velocity; the vote with the most others within CONSENSUS_V of it wins (ties:
		# the lower point). With one candidate or none this is the lowest point's, as it was
		var cand := []
		for k in ["hl", "tl", "hr", "tr"]:
			var hk := float(ys[k][i]) - float(gf[k.right(1)][i])
			if hk < CONS_H:
				cand.append([k, hk, -(vel[k][i] as Vector2)])
		var best: Vector2 = -(vel[low][i] as Vector2)
		if cand.size() > 1:
			var top := -1
			var top_h := INF
			for a in cand:
				var votes := 0
				for b in cand:
					if ((a[2] as Vector2) - (b[2] as Vector2)).length() < CONSENSUS_V:
						votes += 1
				if votes > top or (votes == top and float(a[1]) < top_h):
					top = votes
					top_h = float(a[1])
					best = a[2]
		root.append(best)
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
			if i < (fly.get("on", []) as Array).size() and bool(fly["on"][i]):
				st = false   # FLIGHT: no foot is on the floor in the air, whatever its height and its speed read as (flight_of)
			on.append(st)
		flag[sd] = _clean_runs(on)
		var sn: Array = seen.get(sd, [])
		if sn.size() == n:   # LOST: a contact made mostly of frames the tracker did not see is the fill's guess, not a stance (see `seen`);
			for r in _runs_of(flag[sd]):   # one that only crosses a short dropout keeps it (walk_bat's real stances do)
				var unseen := 0
				for i in range(int(r[0]), int(r[1]) + 1):
					unseen += 0 if bool(sn[i]) else 1
				if unseen * 2 > int(r[1]) - int(r[0]) + 1:
					for i in range(int(r[0]), int(r[1]) + 1):
						flag[sd][i] = false
		for k in 2:   # the pivots that are down: the heel and the ball, each while it is within H_PIV of its ground
			var pv := []
			for i in n:
				pv.append(bool(flag[sd][i]) and float(ys[("h" if k == 0 else "t") + sd.right(1)][i]) - float(gf[sd.right(1)][i]) < H_PIV)
			piv["%s%d" % [sd, k]] = pv
	var heeloff := {}   # "foot_l|f0" -> the time (s from the first frame) the heel leaves the floor for good inside that contact
	for sd in ["_l", "_r"]:
		for r in _runs_of(flag[sd]):
			var fh := int(r[1]) + 1   # walk back from the run's end while the heel stands HEEL_UP above its own ground
			while fh - 1 > int(r[0]) and float(ys["h" + sd.right(1)][fh - 1]) - float(gf[sd.right(1)][fh - 1]) > HEEL_UP:
				fh -= 1
			if fh <= int(r[1]) - 1 and fh > int(r[0]) + 2:
				heeloff["foot%s|%d" % [sd, int(r[0])]] = snappedf(float(frames[fh]["t"]) - T0, 0.001)
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
	return {"list": list, "heeloff": heeloff, "hint": hint, "flags": flag, "piv": piv, "ground": gm, "root": root}


## per foot, per frame of `to`: whether the tracker saw that foot (its confidence >= LOST) at the nearest frame of `from` in time
static func seen_feet(conf: Dictionary, from: Array, to: Array) -> Dictionary:
	var out := {"_l": [], "_r": []}
	if from.is_empty():
		return out
	var j := 0
	for f in to:
		while j + 1 < from.size() and absf(float(from[j + 1]["t"]) - float(f["t"])) <= absf(float(from[j]["t"]) - float(f["t"])):
			j += 1
		for sd in ["_l", "_r"]:
			var pc: Array = conf["parts"].get("foot" + sd, [])
			# a frame where the WHOLE body was lost (fill_gaps) is not this: the fill between good frames is a fair guess for a
			# planted foot there (walk_bat's 8 lost frames sit inside real stances); only a foot lost while the body is seen counts
			(out[sd] as Array).append(j >= pc.size() or float(pc[j]) >= LOST or bool(from[j].get("lost", false)))
	return out


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
static func plants_of(list: Array, fps: float, heeloff := {}) -> Array:
	var out := []
	for c in list:
		if c["kind"] != "foot":
			continue
		var t1 := float(c["t1"]) - TRIM / maxf(fps, 1.0)
		if t1 - float(c["t0"]) >= MIN_RUN / maxf(fps, 1.0):
			var q := {"foot": c["part"], "t0": c["t0"], "t1": t1}
			var key := "%s|%d" % [c["part"], int(c["f0"])]
			if heeloff.has(key) and float(heeloff[key]) > float(c["t0"]) and float(heeloff[key]) < t1:
				q["th"] = heeloff[key]
			out.append(q)
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
			if cancelled():
				return _unmemo(best)
			var mid := sqrt(lo * hi)
			var idx := dp_keys(feat, ts, mid)
			var ex := {}
			for i in idx:
				ex[i] = true
			var V := VideoImport.thin(dense, 1000000, ex)
			V.spline = spline
			V.memo_slopes = true   # VIDEO SPEED: the trial scenes sample the same cards at every t (see Scene._slope)
			var e := pos_error(ref, _positions(V, B, ts))
			if e.x <= target and e.y <= worst_cap:
				lo = mid
				if best.is_empty() or idx.size() < int(best["cards"]) or (idx.size() == int(best["cards"]) and e.x < float(best["mean"])):
					best = {"scene": V, "keys": idx, "mean": e.x, "worst": e.y, "spline": spline, "dense": n, "cards": idx.size()}
			else:
				hi = mid
	if best.is_empty():   # nothing passed: every frame (the dense scene itself)
		best = {"scene": dense, "keys": range(n), "mean": 0.0, "worst": 0.0, "spline": false, "dense": n, "cards": n}
	return _unmemo(best)


## the scene a caller gets back is an ordinary scene again (its slope memo is dropped: a later edit must read live cards)
static func _unmemo(d: Dictionary) -> Dictionary:
	if d.has("scene"):
		(d["scene"] as Scene).memo_clear()
	return d


# ================================================================ THE WHOLE IMPORT =======================================

static func _ints(a: Array) -> Array:
	return a.map(func(v): return int(round(clampf(float(v), 0.0, 1.0) * 100.0)))


## ---- OFF THE MAIN THREAD (R13). main runs process on a worker (a 100-frame clip is 4-5 s of solving) and the window keeps
## drawing. The worker never touches a node or a file. cancel_flag / progress are the only things main and the worker share:
## main sets cancel_flag[0] (Cancel, or quitting) and the stages below return {} / [] at their next check; the worker sets progress.
static var cancel_flag := [false]
static var progress := 0.0


static func cancelled() -> bool:
	return bool(cancel_flag[0])


## R14f STANCE HEIGHT. The video fit's hips RISE across a stance (R14e probe: pelvis 0.90 -> 0.96 m while the true one stays near 0.86-0.91),
## so a stance leg sits at 98-99 % of its length and FootPlant's hip drop runs out. Here the fit is corrected where it is made: over each
## plant (the detector's span, eased in and out over FootPlant.BLEND frames) the pelvis is lowered, never raised, until the stance leg
## (hip to the pinned ankle) is STANCE_REACH of its length; the plant's IK then holds the foot. 96 % = a knee flexed about 16 deg:
## stance-phase knee flexion in walking is ~5 deg at heel strike, 15-20 deg in loading response, ~10 deg mid stance (Perry & Burnfield 2010,
## "Gait Analysis"; Kirtley 2006), and a leg of thigh+shank length L with the knee flexed k has hip-ankle distance L*cos(k/2) about
## (k = 16 deg: 0.990 for equal segments, so 96 % is more bent than the mean: a heuristic that keeps the 2 cm solver margin, REACH_SLACK 98 %).
const STANCE_REACH := 0.96
static var stance_fix := true   # false: the fit as it was before R14f (the test's before/after table)
static func stance_height(B: Body, fitted: Array, plants: Array, fps: float) -> Dictionary:
	var n := fitted.size()
	var need := []
	need.resize(n)
	need.fill(0.0)
	var keep := B.state()
	var dt := 1.0 / maxf(fps, 1.0)
	for p in plants:
		var foot: String = p["foot"]
		var ch := LimbIK.chain(B, foot)
		var reach := (B.p0[ch[1]] as Vector3).distance_to(B.p0[ch[0]] as Vector3) + (B.p0[foot] as Vector3).distance_to(B.p0[ch[1]] as Vector3)
		var i0 := clampi(int(round(float(p["t0"]) / dt)), 0, n - 1)
		var i1 := clampi(int(round(float(p["t1"]) / dt)), 0, n - 1)
		var pin := Vector3.INF
		var hips := {}
		for i in range(maxi(i0 - FootPlant.BLEND, 0), mini(i1 + FootPlant.BLEND, n - 1) + 1):
			for j in fitted[i]["ang"]:
				B.ang[j] = fitted[i]["ang"][j]
			B.offset = fitted[i]["offset"]
			B.fk()
			hips[i] = B.P[ch[0]]
			if pin == Vector3.INF and i >= i0 and minf((B.P["ball" + String(foot).right(2)] as Vector3).y, FootRoll.heel_point(B, String(foot).right(2)).y) <= 0.02:
				pin = B.P[foot]
		if pin == Vector3.INF:
			continue
		for i in hips:
			var h: Vector3 = (hips[i] as Vector3) - pin
			var hy := sqrt(maxf(pow(reach * STANCE_REACH, 2.0) - h.x * h.x - h.z * h.z, 0.0))
			var w := FootPlant.weight({"t0": float(i0) * dt, "t1": float(i1) * dt}, float(i) * dt, int(round(fps)))
			need[i] = maxf(float(need[i]), maxf(h.y - hy, 0.0) * w)
	B.set_state(keep)
	# a 5-frame running mean: the drop eases across the edges and cannot step between frames
	var lowered := 0
	var worst := 0.0
	var sm := []
	for i in n:
		var s := 0.0
		for k in range(-2, 3):
			s += float(need[clampi(i + k, 0, n - 1)])
		sm.append(s / 5.0)
	for i in n:
		var d := float(sm[i])
		if d > 1e-4:
			var o: Vector3 = fitted[i]["offset"]
			fitted[i]["offset"] = Vector3(o.x, o.y - d, o.z)
			lowered += 1
			worst = maxf(worst, d)
	return {"frames": lowered, "worst": worst}


## MOCAP QUALITY: JOINT-ANGLE SMOOTHING. The landmarks are smoothed (VideoCleanup One Euro) but the fit turns each frame's noise into
## angles again: the arms' twist and the feet's turn, where a near-straight limb has no plane to read, carried most of the jitter
## (turn clip: upperarm 12 and 11 of a body RMS 4.1, in 1000 deg/s^2). Each series (bend, side, twist, unwrapped) goes
## through the same zero-lag One Euro as the landmarks, in DEGREES, tuned per joint group: slow trunk and head hardest, the arms
## and hands keep their fast peaks (beta). The legs' thighs, calves, feet and toes are left alone: the floor, the plants and the stance
## height are solved on them (smoothing a foot's turn lifted or sank it 4-11 cm off the floor: the fit grounded the raw angle)
static var angle_smooth := false   # the keys are CHOSEN on the unsmoothed dense scene (the legs, the plants and the floor contact stay as they were); see _smooth_cards
const SMOOTH_JUMP := 60.0   # deg: a joint whose reading jumps this far in a frame is not smoothed
const SMOOTH_DEV := 8.0     # deg: nor one the smoothing would move this far from its fit anywhere
static var smooth_off := []   # joint-name prefixes left out (the test's before/after rows)
const SMOOTH := {"upperarm": Vector2(1.2, 0.012), "lowerarm": Vector2(1.5, 0.015), "clavicle": Vector2(0.8, 0.01), "spine": Vector2(0.8, 0.008), "neck": Vector2(0.8, 0.008), "head": Vector2(1.0, 0.01), "hand": Vector2(1.5, 0.02)}
## the smart cards (chosen on the unsmoothed dense scene, so the keys, the legs and everything the plants read are exactly what they
## were) take their values from the SMOOTHED fit: sk["scene"] becomes the same keys over the smoothed angles
static func _smooth_cards(B: Body, sk: Dictionary, fitted: Array, fps: float, scene_name: String) -> void:
	if (sk["keys"] as Array).size() >= fitted.size():
		return
	var fs: Array = fitted.duplicate(true)
	smooth_angles(fs, fps)
	var ex := {}
	for i in sk["keys"]:
		ex[i] = true
	var ds := VideoImport.to_scene(B, fs, fps, 1, scene_name)
	var V := VideoImport.thin(ds, 1000000, ex)
	V.spline = bool(sk["spline"])
	V.memo_slopes = true
	sk["scene"] = V
	sk["dense_scene"] = ds   # the dense scene the cards now replay (the same keys over the smoothed angles)


static func _amax(v: Vector3) -> float:
	return maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))


static func smooth_angles(fitted: Array, fps: float) -> void:
	var n := fitted.size()
	if n < 3:
		return
	for j in (fitted[0]["ang"] as Dictionary):
		var prm := Vector2.ZERO
		for k in SMOOTH:
			if String(j).begins_with(k) and not k in smooth_off:
				prm = SMOOTH[k]
		if prm == Vector2.ZERO:
			continue
		var xs := []
		var prev := Vector3.ZERO
		var steady := true
		for i in n:
			var v: Vector3 = fitted[i]["ang"][j]
			if i > 0:
				for c in 3:
					while v[c] - prev[c] > 180.0:
						v[c] -= 360.0
					while v[c] - prev[c] < -180.0:
						v[c] += 360.0
				# an Euler triple can jump between two readings of ONE turn (a limb through its gimbal: bend near 90, side near 180);
				# averaging the two readings is a different rotation (14 cm mean on walk_bat's cards). Such a joint is left as it is
				if _amax(v - prev) > SMOOTH_JUMP:
					steady = false
			prev = v
			xs.append(v / 100.0)   # one_euro_zero_lag works in cm: a /100 here makes its units degrees
		if not steady:
			continue
		var ys := VideoCleanup.one_euro_zero_lag(xs, fps, prm.x, prm.y)
		var dev := 0.0
		for i in n:
			dev = maxf(dev, _amax((ys[i] as Vector3) - (xs[i] as Vector3)) * 100.0)
		if dev > SMOOTH_DEV:   # smoothing that moves a joint this far is cutting a real move, not noise
			continue
		for i in n:
			fitted[i]["ang"][j] = (ys[i] as Vector3)


## parse -> confidence -> repair -> depth -> cleanup -> contacts -> fit -> smart cards -> plants. P = VideoImport.parse's result
## (its frames are changed). Returns {"scene", "iq", "text", "conf", "depth", "contacts", "keys", "fitted", "frames", "dense",
## "repaired"}. retarget = true fits with VideoRetarget (GMR-style IK, feet pinned on the contacts) instead of VideoImport.solve
static func process(B: Body, P: Dictionary, held := "", scene_name := "video_import", retarget := false) -> Dictionary:
	var fps := float(P["fps"])
	progress = 0.0
	stage_ms = {}
	_lap_t = Time.get_ticks_usec()
	var frames: Array = VideoIQ.fill_gaps(P["frames"], fps)
	var inverted := VideoIQ.inversion_filter(frames, fps)   # a tracker flip about the hips (3d INVERTED BODY): lost, a straight line between the upright frames
	var flipped_limbs := VideoIQ.fix_flips(frames) if flip_fix else 0   # a limb pair whose labels swapped for a few frames: swapped back by continuity
	VideoIQ.torso_filter(frames)   # a glitch on the shoulders or hips (3b TORSO SPIKES), before anything reads the body
	VideoIQ.dip_filter(frames, fps)   # a glitch that moves the whole upper body for 1-5 frames (3c UPPER-BODY DIPS)
	# FLIGHT: read from the tracker's image on the file's own frames, carried to the filled frames by time
	var fly_raw := flight_of(P["frames"])
	var fly := {"on": [], "rise": []}
	var pj := 0
	for f in frames:
		while pj + 1 < P["frames"].size() and absf(float(P["frames"][pj + 1]["t"]) - float(f["t"])) <= absf(float(P["frames"][pj]["t"]) - float(f["t"])):
			pj += 1
		(fly["on"] as Array).append(fly_raw["on"][pj] if not (fly_raw["on"] as Array).is_empty() else false)
		(fly["rise"] as Array).append(fly_raw["rise"][pj] if not (fly_raw["rise"] as Array).is_empty() else 0.0)
	var conf := confidence(frames, fps)
	var repaired := repair(frames, conf)
	var dp := fix_depth(frames, P.get("axis", Vector3(0, 0, 1)), limits_of(B))
	if cancelled():
		return {}
	progress = 0.1
	_lap("prep")
	var C := VideoCleanup.run(frames, fps, float(P.get("tilt", 0.0)))
	normalize_lengths(C["frames"])
	_lap("cleanup")
	var K := contacts(C["frames"], fps, fly, seen_feet(conf, frames, C["frames"]))
	_lap("contacts")
	if cancelled():
		return {}
	progress = 0.2
	var fitted: Array
	if retarget and held == "":   # "Retarget to body (IK)": VideoRetarget, with THIS pass's contacts pinning the planted feet
		fitted = VideoRetarget.solve(C["frames"], B, {"fps": fps, "smooth": false, "iq": K, "fly": fly})
	else:
		fitted = VideoImport.solve(B, C["frames"], held, fps, K["piv"], fly)
	if cancelled():
		return {}
	progress = 0.7
	_lap("fit")
	if stance_fix and not fitted.is_empty():
		stance_height(B, fitted, plants_of(K["list"], fps, K["heeloff"]), fps)
	if toe_fix and not fitted.is_empty():
		settle_toes(B, fitted)
	var dense := VideoImport.to_scene(B, fitted, fps, 1, scene_name)
	var sk := smart_cards(B, dense, fitted)
	if angle_smooth and not fitted.is_empty():
		_smooth_cards(B, sk, fitted, fps, scene_name)
	if cancelled():
		return {}
	progress = 0.95
	_lap("cards")
	var V: Scene = sk["scene"]
	V.memo_slopes = true   # VIDEO SPEED: this scene's cards are fixed from here to the return below (reachable and the located pass only read it)
	var reach_n0 := Scene.apply_calls
	V.plants = VideoCleanup.reachable(V, B, FootPlant.from_file(plants_of(K["list"], fps, K["heeloff"])), V.fps)
	reach_applies = Scene.apply_calls - reach_n0   # the Scene.apply calls reachable made (tests/vidspeed_test.gd 3c)
	_lap("plants")
	var located := locate_played(B, V, K["list"])
	_lap("locate")
	_unmemo(sk)
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
		"dense": sk.get("dense_scene", dense), "repaired": repaired, "located": located, "inverted": inverted, "limb_flips": flipped_limbs}


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


## THE TOES FROM CONTACT, NOT FROM THE TRACKER (Nick 10-20: "feet bend when they are supposed to be straight"). The fit
## aims each toe joint at MediaPipe's toe-tip landmark (31 / 32), a point a few cm from the toe joint that the tracker
## places to within a few cm: on the Heian kata, Mixkit 49611 and 49630 imports the toes stood bent 10-30 deg (median)
## with the foot FLAT on the floor and 30-58 deg in the air, often at the joint's 60 deg limit. A real foot: toes straight
## when it stands flat or swings; bent up only at push-off, the heel lifted and the toes still on the floor (the windlass
## of gait). So per frame, per foot: straight, unless straight puts the toe tip through the floor (push-off: the heel up,
## the toe joint on the floor); then the least bend that keeps the tip on the floor. The floor is the frame's lowest sole
## point before the change, and the hips are not moved (a re-ground moved the root and broke the plants: 93 -> 54 %).
static var toe_fix := true
static func settle_toes(B: Body, fitted: Array) -> void:
	var keep := B.state()
	for fr in fitted:
		for j in fr["ang"]:
			B.ang[j] = fr["ang"][j]
		B.offset = fr["offset"]
		B.fk()
		var fl := minf(_low(B, "_l"), _low(B, "_r"))   # the floor: the lowest sole point (ground put it at the floor)
		for sd in ["_l", "_r"]:
			var b: String = "ball" + sd
			B.ang[b] = Vector3.ZERO
			B.fk_sub(b)
			if float((B.E[b] as Vector3).y) < fl - 0.002:   # straight, the tip would go through the floor: bent just enough
				var r: Vector2 = B.lim[b]["bend"]
				var best := 0.0
				var k := 1.0
				var found := false
				while k <= maxf(absf(r.x), absf(r.y)) and not found:
					for sg in [1.0, -1.0]:
						var v: float = sg * k
						if v < r.x or v > r.y:
							continue
						B.ang[b] = Vector3(v, 0.0, 0.0)
						B.fk_sub(b)
						if float((B.E[b] as Vector3).y) >= fl - 0.002:
							best = v
							found = true
							break
					k += 1.0
				B.ang[b] = Vector3(best, 0.0, 0.0)
				B.fk_sub(b)
			fr["ang"][b] = B.ang[b]
	B.set_state(keep)


## the lowest point of a foot (heel's back, toe joint, toe tip)
static func _low(B: Body, sd: String) -> float:
	return minf(float(VideoImport.heel(B, sd).y), minf(float((B.P["ball" + sd] as Vector3).y), float((B.E["ball" + sd] as Vector3).y)))
