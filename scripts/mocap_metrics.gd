## MOCAP QUALITY NUMBERS (tests/mocapq_test.gd, tests/_mocapq_prof.gd): what a video import is judged on, measured the same way
## before and after a change. All of them read the clip's scene as it PLAYS (Scene.apply at the fitted frames' times: cards, plants and all), or the tracker's landmark frames ([{"t", "w": 33 Vector3}]), so a fixture of keypoints is the whole input.
##   skate    cm a planted foot slides: per contact (the ball under 2.5 cm of the floor, moving under 0.25 m/s, 3+ frames) the
##            furthest the ball strays from where the contact began; worst and mean over contacts
##   jitter   RMS angular acceleration of the body joints (fingers left out), in 1000 deg/s^2: the high-frequency energy
##   flips    frames where a left/right pair (ankles, knees, wrists, elbows, heels, toes) swapped places between two frames
##            (swapped is under half the distance of staying, and the jump is over 15 cm)
##   bones    mean over the 10 body segments of the length's coefficient of variation over the clip, in percent
##   pen      deepest a sole point goes below the app floor (Body.foot_sole_low < 0), cm; and the share of frames over 5 mm below
class_name MocapMetrics

const SOLE_H := 0.025
const SOLE_V := 0.6
const SOLE_MIN := 3
const PAIRS := [[27, 28], [25, 26], [15, 16], [13, 14], [29, 30], [31, 32]]
const FINGERS := ["index", "middle", "ring", "pinky", "thumb"]


## the scene as it plays (smart cards, plants and all), sampled at the given times: the frames [{"t", "ang", "offset"}] and per frame
## the ball joints and the lowest sole point of each foot above its rest height (Body.foot_sole_low, the app floor).
## {"frames": [...], "t": [...], "ball_l": [Vector3], "low_l": [float], ...}
static func play(B: Body, S: Scene, times: Array) -> Dictionary:
	var keep := B.state()
	var out := {"frames": [], "t": [], "ball_l": [], "ball_r": [], "low_l": [], "low_r": []}
	for t in times:
		S.apply(B, float(t))
		(out["frames"] as Array).append({"t": float(t), "ang": B.ang.duplicate(true), "offset": B.offset})
		(out["t"] as Array).append(float(t))
		for sd in ["_l", "_r"]:
			(out["ball" + sd] as Array).append(B.P["ball" + sd])
			(out["low" + sd] as Array).append(B.foot_sole_low(sd))
	B.set_state(keep)
	return out


## {"worst": cm, "mean": cm, "n": contacts, "list": [[foot, frame a, frame b, cm]]}
static func skate(F: Dictionary) -> Dictionary:
	var ts: Array = F["t"]
	var n := ts.size()
	var list := []
	for sd in ["_l", "_r"]:
		var ball: Array = F["ball" + sd]
		var low: Array = F["low" + sd]
		var down := []
		for i in n:
			var a := maxi(i - 1, 0)
			var b := mini(i + 1, n - 1)
			var d: Vector3 = (ball[b] as Vector3) - (ball[a] as Vector3)
			var v := Vector2(d.x, d.z).length() / maxf(float(ts[b]) - float(ts[a]), 1e-6)
			down.append(float(low[i]) < SOLE_H and v < SOLE_V)
		var i := 0
		while i < n:
			if not down[i]:
				i += 1
				continue
			var a := i
			while i < n and down[i]:
				i += 1
			var b := i - 1
			if b - a + 1 >= SOLE_MIN:
				var p0: Vector3 = ball[a]
				var worst := 0.0
				for k in range(a, b + 1):
					var d: Vector3 = (ball[k] as Vector3) - p0
					worst = maxf(worst, Vector2(d.x, d.z).length())
				list.append(["foot" + sd, a, b, worst * 100.0])
	var w := 0.0
	var sum := 0.0
	for e in list:
		w = maxf(w, float(e[3]))
		sum += float(e[3])
	return {"worst": w, "mean": sum / maxf(float(list.size()), 1.0), "n": list.size(), "list": list}


## RMS angular acceleration over the body joints, in 1000 deg/s^2
static func jitter(fitted: Array) -> float:
	var sum := 0.0
	var m := 0
	var n := fitted.size()
	for i in range(1, n - 1):
		var dt := (float(fitted[i + 1]["t"]) - float(fitted[i - 1]["t"])) * 0.5
		if dt < 1e-6:
			continue
		for j in (fitted[i]["ang"] as Dictionary):
			var skip := false
			for f in FINGERS:
				if String(j).contains(f):
					skip = true
			if skip:
				continue
			var a: Vector3 = fitted[i - 1]["ang"][j]
			var b: Vector3 = fitted[i]["ang"][j]
			var c: Vector3 = fitted[i + 1]["ang"][j]
			var acc := (a - b * 2.0 + c) / (dt * dt)
			sum += acc.length_squared()
			m += 1
	return sqrt(sum / maxf(float(m), 1.0)) / 1000.0


## left/right swaps in landmark frames
static func flips(frames: Array) -> int:
	var n := 0
	for i in range(1, frames.size()):
		var w0: Array = frames[i - 1]["w"]
		var w1: Array = frames[i]["w"]
		for p in PAIRS:
			var l0: Vector3 = w0[p[0]]
			var r0: Vector3 = w0[p[1]]
			var l1: Vector3 = w1[p[0]]
			var r1: Vector3 = w1[p[1]]
			var same := l1.distance_to(l0) + r1.distance_to(r0)
			var swap := l1.distance_to(r0) + r1.distance_to(l0)
			if swap < 0.5 * same and same > 0.15:
				n += 1
	return n


## left/right swaps in the fitted feet: the ball joints, by FK
static func foot_flips(F: Dictionary) -> int:
	var n := 0
	var l: Array = F["ball_l"]
	var r: Array = F["ball_r"]
	for i in range(1, l.size()):
		var same := (l[i] as Vector3).distance_to(l[i - 1]) + (r[i] as Vector3).distance_to(r[i - 1])
		var swap := (l[i] as Vector3).distance_to(r[i - 1]) + (r[i] as Vector3).distance_to(l[i - 1])
		if swap < 0.5 * same and same > 0.15:
			n += 1
	return n


## mean coefficient of variation (percent) of the body segments' lengths
static func bones(frames: Array) -> float:
	var sum := 0.0
	for s in VideoCleanup.SEGS:
		var ls := []
		for f in frames:
			var w: Array = f["w"]
			ls.append(((w[s[1]] as Vector3) - (w[s[0]] as Vector3)).length())
		var mean := 0.0
		for x in ls:
			mean += float(x)
		mean /= maxf(float(ls.size()), 1.0)
		var v := 0.0
		for x in ls:
			v += (float(x) - mean) * (float(x) - mean)
		sum += sqrt(v / maxf(float(ls.size()), 1.0)) / maxf(mean, 1e-6) * 100.0
	return sum / VideoCleanup.SEGS.size()


## {"deepest": cm, "share": fraction of frames more than 5 mm under the floor}
static func penetration(F: Dictionary) -> Dictionary:
	var deep := 0.0
	var under := 0
	var n: int = (F["t"] as Array).size()
	for i in n:
		var lo := minf(float(F["low_l"][i]), float(F["low_r"][i]))
		deep = maxf(deep, -lo)
		if lo < -0.005:
			under += 1
	return {"deepest": deep * 100.0, "share": float(under) / maxf(float(n), 1.0)}


## the jitter's share per joint: [[joint, rms in 1000 deg/s^2]] largest first (for finding where it comes from)
static func jitter_by_joint(fitted: Array) -> Array:
	var acc := {}
	var cnt := {}
	for i in range(1, fitted.size() - 1):
		var dt := (float(fitted[i + 1]["t"]) - float(fitted[i - 1]["t"])) * 0.5
		if dt < 1e-6:
			continue
		for j in (fitted[i]["ang"] as Dictionary):
			var a: Vector3 = fitted[i - 1]["ang"][j]
			var b: Vector3 = fitted[i]["ang"][j]
			var c: Vector3 = fitted[i + 1]["ang"][j]
			acc[j] = float(acc.get(j, 0.0)) + ((a - b * 2.0 + c) / (dt * dt)).length_squared()
			cnt[j] = int(cnt.get(j, 0)) + 1
	var out := []
	for j in acc:
		out.append([j, sqrt(float(acc[j]) / maxf(float(cnt[j]), 1.0)) / 1000.0])
	out.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
	return out
