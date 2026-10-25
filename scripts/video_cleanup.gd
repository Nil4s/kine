## VIDEO CLEANUP (ROADMAP 16, "phone video to clean animation"). The default last step of the video import (main.gd
## _import_pose; "import raw" skips it). VideoImport.parse gives the tracker's 33 world landmarks per frame; this cleans them
## BEFORE the fit, so the fit and FootPlant do the rest with no hand cleanup:
##   1 JITTER: a One Euro filter (Casiez, Roussel, Vogel, CHI 2012) on every landmark. Its two knobs, as the paper sets them:
##     min_cutoff (Hz) sets the smoothing when a point is still (lower = less jitter at rest), beta (per cm/s) lets the cutoff
##     rise with speed (higher = less lag on fast moves). Tuned per body part in GROUPS. Run forward AND backward and averaged,
##     so the smoothing has no lag (an offline clip has all its frames; the causal filter's delay is only for live input).
##   2 FLOOR: the feet are the floor. A plane is fitted through the sole points of the planted feet (least squares, y = a + bx
##     + cz) and the whole body is turned so that plane is level. VideoImport.level is a trunk estimate of the camera's tilt;
##     this is the floor itself, and it runs on the smoothed landmarks.
##   3 PLANTS: a foot is planted while its sole is under PLANT_H above its floor AND its speed is under PLANT_V, for PLANT_MIN
##     frames or more. Each run is a plant {foot, t0, t1} (FootPlant's list, the scene's "plants"): the sole is held at its
##     t0 place when the scene plays. The lowest planted sole ends on the floor (VideoImport.solve puts the lower sole on it).
class_name VideoCleanup
extends RefCounted

const REACH_TOL := 0.003  # m: reachable() cuts a plant where its ankle misses the pin by more than this (FootPlant.MISS_BAR, 1 mm, is the editor's)
const END_H := 0.02  # m: a plant's end has its sole this near the floor (reachable)
const PIVOT_H := 0.06  # m: a heel this near the floor, toes up, is at its heel strike (the pivot starts)
const PIVOT_MAX := 0.25  # s: the longest a heel pivot (FootPlant "tf") may last: a heel strike's toes come down in a few frames
const SEAT_TOL := 0.02   # m: a plant's held sole is this near the floor (reachable moves t0 on to a sample that is)
const PLANT_H := 0.02      # m: a sole this close to its floor is down (the brief's 2 cm)
const PLANT_V := 0.15      # m/s: and the middle of the foot moves this slowly (the brief's 0.15 m/s)
const PLANT_MIN := 3       # frames: a shorter run is a tap, not a plant (the brief's 3)
const TRIM := 4            # frames cut off the end of each run (the toe-off; see detect)
const TRUNK := [11, 12, 23, 24]
const HEAD := [0, 7, 8]
const ARMS := [13, 14, 15, 16]
const LEGS := [25, 26, 27, 28]
const FEET := [29, 30, 31, 32]
## the bones whose turn the jitter is read on: [parent, child] landmark pairs (the limbs and the trunk's two halves)
const SEGS := [[23, 25], [25, 27], [24, 26], [26, 28], [11, 13], [13, 15], [12, 14], [14, 16], [23, 11], [24, 12]]


## One Euro's (min_cutoff Hz, beta) per landmark. Casiez et al.'s rule: start at a low min_cutoff (jitter at rest) and raise beta
## until a fast move lags no more. The trunk moves slowly and is smoothed hardest; the hands and feet keep their peaks.
## beta is per cm/s on the speed (the paper's units: pixels/s; the points are in cm here, so the same numbers read alike).
## Measured on walk_bat (tests/video_cleanup_test.gd): the arms' beta 0.3 let the 1.5 cm noise through (the noise itself
## reads as speed), so the arms are set at 0.03 and the test's peak-speed bar holds.
static func _group(k: int) -> Vector2:
	if k in TRUNK:
		return Vector2(0.5, 0.01)
	if k in HEAD:
		return Vector2(1.0, 0.02)
	if k in ARMS:
		return Vector2(1.0, 0.03)
	if k in LEGS or k in FEET:
		return Vector2(1.0, 0.03)
	return Vector2(1.0, 0.03)


static func _alpha(fc: float, te: float) -> float:
	var tau := 1.0 / (2.0 * PI * fc)
	return 1.0 / (1.0 + tau / te)


## one forward One Euro pass over a series of points (metres in, metres out; the filter works in cm)
static func one_euro(xs: Array, fps: float, min_cutoff: float, beta: float, dcutoff := 1.0) -> Array:
	var te := 1.0 / maxf(fps, 1.0)
	var out := []
	var prev := Vector3.ZERO
	var xh := Vector3.ZERO
	var dxh := Vector3.ZERO
	for i in xs.size():
		var x: Vector3 = (xs[i] as Vector3) * 100.0
		if i == 0:
			xh = x
		else:
			var dx := (x - prev) / te
			dxh = dxh.lerp(dx, _alpha(dcutoff, te))
			var fc := min_cutoff + beta * dxh.length()
			xh = xh.lerp(x, _alpha(fc, te))
		prev = x
		out.append(xh / 100.0)
	return out


## forward and backward, averaged: the lag of one pass is cancelled by the other's
static func one_euro_zero_lag(xs: Array, fps: float, min_cutoff: float, beta: float) -> Array:
	var f := one_euro(xs, fps, min_cutoff, beta)
	var rev := xs.duplicate()
	rev.reverse()
	var b := one_euro(rev, fps, min_cutoff, beta)
	b.reverse()
	var out := []
	for i in f.size():
		out.append(((f[i] as Vector3) + (b[i] as Vector3)) * 0.5)
	return out


## every frame's 33 landmarks smoothed; frames are {"t", "w"} as VideoImport.parse makes them
static func smooth(frames: Array, fps: float) -> Array:
	var n := frames.size()
	var out := []
	for i in n:
		var o := {"t": frames[i]["t"], "w": []}
		if frames[i].has("vis"):
			o["vis"] = frames[i]["vis"]   # VIDEO IQ: the tracker's visibility rides along
		if frames[i].has("hands"):
			o["hands"] = frames[i]["hands"]   # ROADMAP 90: the hands are not smoothed here (HandImport smooths the finger angles)
		out.append(o)
	for k in 33:
		var g := _group(k)
		var xs := []
		for f in frames:
			xs.append((f["w"] as Array)[k])
		var ys := one_euro_zero_lag(xs, fps, g.x, g.y)
		for i in n:
			(out[i]["w"] as Array).append(ys[i])
	return out


## THE PLANTS: per foot, the runs of frames whose sole is under PLANT_H above that foot's floor (its 10th percentile over the
## clip) and whose foot moves under PLANT_V. [{"foot": "foot_l", "t0": s, "t1": s}] by t0, the FootPlant form
static func detect(frames: Array, fps: float) -> Array:
	var out := []
	var n := frames.size()
	if n < 2:
		return out
	var ts := []
	for f in frames:
		ts.append(float(f["t"]))
	for sd in ["_l", "_r"]:
		var mid := []
		var hs := []
		for f in frames:
			var w: Array = f["w"]
			var heel: Vector3 = w[VideoImport.HEEL[sd]]
			var toe: Vector3 = w[VideoImport.TOE[sd]]
			mid.append((heel + toe) * 0.5)
			hs.append(minf(heel.y, toe.y))
		var srt := hs.duplicate()
		srt.sort()
		var floor_y: float = srt[int(0.1 * (n - 1))]
		var down := []
		for i in n:
			var a := maxi(i - 1, 0)
			var b := mini(i + 1, n - 1)
			var dt: float = maxf(ts[b] - ts[a], 1e-6)
			var v: float = (mid[b] - mid[a]).length() / dt
			down.append(float(hs[i]) - floor_y < PLANT_H and v < PLANT_V)
		var i := 0
		while i < n:
			if not down[i]:
				i += 1
				continue
			var a := i
			while i < n and down[i]:
				i += 1
			# the last TRIM frames are the toe-off: the foot is already rolling off and the leg is at full stretch, where the
			# planting solver misses by up to 7 mm (MocapClean's TRIM, measured on the clean walk: round 43). Walk_bat's
			# first plant missed 14 mm over the last 0.13 s until they were cut
			var b := i - 1 - TRIM
			if b - a + 1 >= PLANT_MIN:
				out.append({"foot": "foot" + sd, "t0": ts[a], "t1": ts[b]})
	out.sort_custom(func(x, y): return float(x["t0"]) < float(y["t0"]))
	return out


## the sole's heights at t with NO plants on the scene: {"_l": [ball y, heel y], "_r": [...]}, one Scene.apply per time (memo)
static func _plant_free_pose(V: Scene, B: Body, t: float, memo: Dictionary) -> Dictionary:
	if memo.has(t):
		return memo[t]
	V.apply(B, t)
	var out := {}
	for sd in ["_l", "_r"]:
		out[sd] = [(B.P["ball" + sd] as Vector3).y, FootRoll.heel_point(B, sd).y]
	memo[t] = out
	return out


## REACH: a plant holds only while the leg can still reach its pin. FootPlant.scan reads each sample's miss (the ankle off its
## pin, MISS_BAR = 1 mm); a plant that misses is ended one step before its first bad sample, and dropped if that leaves less
## than PLANT_MIN frames. Scene V must hold the thinned cards; its plants are set to the result by the caller
static func reachable(V: Scene, B: Body, plants: Array, fps: float) -> Array:
	var dt := 1.0 / maxf(fps, 1.0)
	var step := dt / 4.0
	V.plants = plants
	# A PLANTED FOOT IS ON THE FLOOR: a plant holds the sole exactly as it stands at t0 (FootPlant), and a video's first frames of
	# a plant can have the sole up to 2 cm above the floor (the foot still rolling down). t0 moves on to the first sample at
	# which the body's own sole (ball, heel) is within SEAT_TOL of the floor (y = 0, the scene's on_floor), so the hold keeps the
	# foot where it stands on the ground; the foot's turn is the played one. A plant that never gets there keeps its t0
	V.plants = []
	# the scans below that run with NO plants (V.plants = []) read a time's pose the same way, so each time is one Scene.apply,
	# shared by the heel pivot scan and the sole scan (they walk the same grid of times from the same t0)
	var pose_memo := {}
	for p in plants:
		var sd: String = String(p["foot"]).right(2)
		var t := float(p["t0"])
		# R14b HEEL PIVOT: a heel strike. The fitted heel comes within PIVOT_H of the floor while the toes are still up; the sole is flat
		# (heel and ball both within SEAT_TOL) a few frames on, at tf. The plant starts at the heel strike and holds the HEEL until
		# tf (FootPlant "tf"), the whole sole as it stands at tf after. Only when the sole gets flat within PIVOT_MAX: a foot whose
		# toes stay up is not planted (no toes floating through a stance)
		var th0 := t
		while th0 < float(p["t1"]) - PLANT_MIN * dt:
			if float(_plant_free_pose(V, B, th0, pose_memo)[sd][1]) <= PIVOT_H:
				break
			th0 += step
		if th0 < float(p["t1"]) - PLANT_MIN * dt:
			V.apply(B, th0)
			if (B.P["ball" + sd] as Vector3).y > SEAT_TOL:
				var tf := th0 + step
				while tf < minf(th0 + PIVOT_MAX, float(p["t1"]) - PLANT_MIN * dt):
					var pf: Array = _plant_free_pose(V, B, tf, pose_memo)[sd]
					if float(pf[0]) <= SEAT_TOL and float(pf[1]) <= SEAT_TOL:
						break
					tf += step
				if tf < minf(th0 + PIVOT_MAX, float(p["t1"]) - PLANT_MIN * dt):
					p["t0"] = th0
					p["tf"] = tf
					continue
		while t < float(p["t1"]) - PLANT_MIN * dt:
			var pt: Array = _plant_free_pose(V, B, t, pose_memo)[sd]
			if minf(float(pt[0]), float(pt[1])) <= SEAT_TOL:
				break
			t += step
		if t < float(p["t1"]) - PLANT_MIN * dt:
			p["t0"] = t
	V.plants = []
	for p in plants:
		# R14b: the heel-off hold pins the BALL where it stood at the reference time. A ball that was up there (a heel strike the
		# pivot did not bring flat) is a hold in the air: the plant ends where the heel-off would have begun instead
		if p.has("th"):
			var sdh: String = String(p["foot"]).right(2)
			V.apply(B, FootPlant.ref_time(p))
			if (B.P["ball" + sdh] as Vector3).y > SEAT_TOL:
				p["t1"] = minf(float(p["t1"]), float(p["th"]))
				p.erase("th")
	for p in plants:
		p["reach"] = true   # R14: the hips drop to the pin (FootPlant._lower_for_reach) instead of the plant being cut where the leg misses
	V.plants = plants
	for p in plants:
		for _g in 40:
			var r := FootPlant.scan(V, B, p, step)
			var bad: Array = (r["bad"] as Array).filter(func(b): return float(b[1]) > REACH_TOL)   # R14b: a video plant keeps a leg that misses its pin by a few mm
			if bad.is_empty():
				break
			var tb := float(bad[0][0])
			# R14b: a heel pivot whose heel the leg cannot yet reach (the fitted heel is high at the strike) starts where it can: t0 moves
			# past the leading misses; if that is the flat time already, the pivot is not needed and the plant is the whole-sole hold
			if p.has("tf") and tb <= float(p["t0"]) + 1e-6:
				var k := 0
				while k + 1 < bad.size() and float(bad[k + 1][0]) - float(bad[k][0]) < step * 1.5:
					k += 1
				p["t0"] = float(bad[k][0]) + step
				if float(p["t0"]) >= float(p["tf"]) - 1e-6:
					p.erase("tf")
				continue
			# R14: the flat hold is lost where the heel starts to rise (the ankle moves on): the plant turns to the BALL there
			# (FootPlant "th", the roll kept) and is cut only where the ball hold cannot reach either
			V.apply(B, FootPlant.ref_time(p))
			var ball_down: bool = (B.P["ball" + String(p["foot"]).right(2)] as Vector3).y <= SEAT_TOL   # a heel strike with the toes up cannot pin its ball
			if ball_down and (not p.has("th") or float(p["th"]) > tb - 1e-6) and tb - dt > float(p["t0"]) + PLANT_MIN * dt:
				p["th"] = tb - dt
				continue
			# R14c TOE PIVOT: the ball hold misses too (the foot is on its toes): from one frame before the miss only the toe tip is held
			if ball_down and p.has("th") and not p.has("tt") and float(p["th"]) < tb - 1e-6 and tb - dt > float(p["th"]) + 2.0 * dt:
				p["tt"] = tb - dt
				continue
			p["t1"] = tb - step
			if p.has("th") and float(p["th"]) >= float(p["t1"]):
				p.erase("th")
			if p.has("tt") and float(p["tt"]) >= float(p["t1"]):
				p.erase("tt")
			if float(p["t1"]) - float(p["t0"]) < PLANT_MIN * dt:
				p["t1"] = float(p["t0"])
				break
	var out := []
	for p in plants:
		if float(p["t1"]) - float(p["t0"]) >= PLANT_MIN * dt:
			out.append(p)
	V.plants = out
	# R14b: a plant ends where its sole is on the floor: the toe-off end is cut back to the last sample whose planted sole (heel or ball)
	# is within END_H of the floor, so no plant ends with the foot standing in the air
	for p in out:
		var sde: String = String(p["foot"]).right(2)
		V.plants = out
		while float(p["t1"]) - float(p["t0"]) >= PLANT_MIN * dt:
			V.apply(B, float(p["t1"]))
			var low_e := minf((B.P["ball" + sde] as Vector3).y, FootRoll.heel_point(B, sde).y)
			if p.has("tt"):
				low_e = minf(low_e, (B.E["ball" + sde] as Vector3).y - (B.e0["ball" + sde] as Vector3).y)   # R14c: on its toes the toe tip is the contact
			if low_e <= END_H:
				break
			p["t1"] = float(p["t1"]) - step
	var kept := []
	for p in out:
		if float(p["t1"]) - float(p["t0"]) >= PLANT_MIN * dt:
			kept.append(p)
	out = kept
	# the drop each plant ends on (FootPlant: the release keeps it, so the hips do not jump at t1)
	for p in out:
		V.plants = out
		V.apply(B, float(p["t1"]))
		var yon: float = (B.P["pelvis"] as Vector3).y
		V.plants = []
		V.apply(B, float(p["t1"]))
		p["dend"] = maxf((B.P["pelvis"] as Vector3).y - yon, 0.0)
	V.plants = out
	return out


## the sole points (heel, toe) of every frame that falls inside a plant of its foot
static func planted_points(frames: Array, plants: Array) -> Array:
	var pts := []
	for f in frames:
		var t := float(f["t"])
		for p in plants:
			if t >= float(p["t0"]) - 1e-6 and t <= float(p["t1"]) + 1e-6:
				var sd: String = String(p["foot"]).right(2)
				var w: Array = f["w"]
				pts.append(w[VideoImport.HEEL[sd]])
				pts.append(w[VideoImport.TOE[sd]])
	return pts


## the unit normal of the plane through points: least squares y = a + bx + cz, normal (-b, 1, -c). UP when it cannot be read
static func plane_normal(pts: Array) -> Vector3:
	if pts.size() < 3:
		return Vector3.UP
	var n := 0.0
	var sx := 0.0
	var sz := 0.0
	var sy := 0.0
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for p in pts:
		var v: Vector3 = p
		n += 1.0
		sx += v.x
		sz += v.z
		sy += v.y
		sxx += v.x * v.x
		szz += v.z * v.z
		sxz += v.x * v.z
		sxy += v.x * v.y
		szy += v.z * v.y
	var M := Basis(Vector3(n, sx, sz), Vector3(sx, sxx, sxz), Vector3(sz, sxz, szz))
	if absf(M.determinant()) < 1e-12:
		return Vector3.UP
	var c := M.inverse() * Vector3(sy, sxy, szy)
	return Vector3(-c.y, 1.0, -c.z).normalized()


## JITTER, as the animator sees it: for each bone, how far its direction departs from the mean of its two neighbours' directions
## (the high-frequency part of its turn), in degrees per frame, averaged over the bones and frames. Smooth motion reads 0
static func jitter(frames: Array) -> float:
	var sum := 0.0
	var m := 0
	for s in SEGS:
		var d := []
		for f in frames:
			var w: Array = f["w"]
			var v: Vector3 = (w[s[1]] as Vector3) - (w[s[0]] as Vector3)
			d.append(v.normalized() if v.length() > 1e-6 else Vector3.ZERO)
		for i in range(1, d.size() - 1):
			var avg: Vector3 = (d[i - 1] as Vector3) + (d[i + 1] as Vector3)
			if avg.length() < 1e-6 or (d[i] as Vector3) == Vector3.ZERO:
				continue
			sum += rad_to_deg((d[i] as Vector3).angle_to(avg.normalized()))
			m += 1
	return sum / maxf(float(m), 1.0)


## the whole cleanup. frames are VideoImport.parse's {"t", "w"}. Returns {"frames" (cleaned, same form), "plants" (FootPlant
## form, before REACH), "tilt" (deg the floor was turned by), "jitter_raw", "jitter_clean" (deg/frame)}
static func run(frames: Array, fps: float, levelled := 0.0) -> Dictionary:
	var jit_raw := jitter(frames)
	var sm := smooth(frames, fps)
	var nrm := plane_normal(planted_points(sm, detect(sm, fps)))
	var tilt := rad_to_deg(nrm.angle_to(Vector3.UP))
	# VideoImport.level already turned the clip (levelled = the degrees it removed, 6 and up): a second fit through the planted
	# soles, which span ~0.4 m with 10 cm of height spread, is ill-conditioned and turned the body 13 deg more. The floor turn
	# is for a clip the import left alone (a small tilt, below LEVEL_MIN). The decision prints
	if levelled > 0.0:
		print("video cleanup: floor turn skipped, VideoImport.level already turned the clip %.1f deg (the soles' plane would have turned it %.1f deg more)" % [levelled, tilt])
		tilt = 0.0
	if tilt > 0.0:
		var R := Quaternion(nrm, Vector3.UP)
		for f in sm:
			var w: Array = f["w"]
			for k in w.size():
				w[k] = R * (w[k] as Vector3)
	var plants := detect(sm, fps)
	var jit_clean := jitter(sm)
	return {"frames": sm, "plants": plants, "tilt": tilt, "jitter_raw": jit_raw, "jitter_clean": jit_clean}


## the report line, as the import shows it: n is the plants that hold (after REACH), so the caller passes the final count
static func report(n: int, jit_raw: float, jit_clean: float, tilt: float) -> String:
	var cut := 0.0 if jit_raw <= 0.0 else 100.0 * (1.0 - jit_clean / jit_raw)
	return "%d foot plants locked, jitter reduced from %.2f to %.2f deg/frame (high-frequency energy, %.0f %% less), floor tilt corrected by %.1f deg" % [n, jit_raw, jit_clean, cut, tilt]
