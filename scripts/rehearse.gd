## rehearse.gd - I14 REHEARSE AGAINST YOURSELF. A take (a phone video of the person doing the move, fitted by the video import
## to a Scene; or any Scene) is laid against the open clip, card by card.
##   1 FEATURES: per frame (30 Hz) the bend / side / twist (deg) of the hips (pelvis), the three spine joints, both shoulders
##     (upper arms), elbows (forearms), thighs and knees (calves): 12 joints x 3 = 36 numbers. Distance between two frames =
##     the rms of the 36 differences (deg).
##   2 DTW (dynamic time warping, Sakoe & Chiba 1978; steps right / up / diagonal, no band) aligns the two sequences. A hold is a
##     flat stretch where any frame matches any other, so DTW alone cannot say WHEN a pose was reached.
##   3 EVENTS: card i's time, in either sequence, is the moment the sequence first comes within 1 deg rms of the closest it gets to
##     that card's pose, looked for in a window around where DTW puts the card (linear interpolation between frames: sub-frame).
##     The same rule is run on the clip and on the take, so its small bias (the ease's tail) cancels in the difference.
##   4 REPORT per card: seconds the move into the card took more / less than the clip's ("you were 0.08 s faster on the
##     strike") and the biggest joint differences at the closest frame to the card's pose ("your hip turned 20 deg more").
## Nothing here writes a file or touches a node: the app only reads the result (and edits cards through its one-undo-step paths).
class_name Rehearse
extends RefCounted

const FPS := 30.0
const JOINTS := ["pelvis", "spine_01", "spine_02", "spine_03", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
	"thigh_l", "thigh_r", "calf_l", "calf_r"]
const AXES := ["bend", "side", "twist"]
const TOL := 1.0          # deg rms: "has reached the card's pose" (above the closest it gets)
const BIG := 8.0          # deg: a joint difference this big is worth a line
const LATE := 0.05        # s: a move this much longer / shorter than the clip's is worth a line (1.5 frames)
const MAX_LINES := 3


static func feat(ang: Dictionary) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(JOINTS.size() * 3)
	var k := 0
	for j in JOINTS:
		var a: Vector3 = ang.get(j, Vector3.ZERO)
		f[k] = a.x
		f[k + 1] = a.y
		f[k + 2] = a.z
		k += 3
	return f


static func dist(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var s := 0.0
	for i in a.size():
		var d := a[i] - b[i]
		s += d * d
	return sqrt(s / float(a.size()))


## a Scene sampled at FPS: {"f": [features per frame], "n"}; frame k is at k / FPS s
static func sequence(S: Scene) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var f := []
	for k in n:
		f.append(feat(S.sample(float(k) / FPS).get("ang", {})))
	return {"f": f, "n": n}


## DTW of two feature lists; returns for every frame of a the (float) frame of b it is matched to (mean of its matches)
static func dtw_map(a: Array, b: Array) -> PackedFloat32Array:
	var na := a.size()
	var nb := b.size()
	var D := PackedFloat32Array()
	D.resize((na + 1) * (nb + 1))
	D.fill(INF)
	var W := nb + 1
	D[0] = 0.0
	for i in range(1, na + 1):
		for j in range(1, nb + 1):
			var c := dist(a[i - 1], b[j - 1])
			var m := minf(D[(i - 1) * W + j - 1], minf(D[(i - 1) * W + j], D[i * W + j - 1]))
			D[i * W + j] = c + m
	var sum := PackedFloat32Array()
	sum.resize(na)
	var cnt := PackedInt32Array()
	cnt.resize(na)
	var i := na
	var j := nb
	while i > 0 and j > 0:
		sum[i - 1] += float(j - 1)
		cnt[i - 1] += 1
		var d0 := D[(i - 1) * W + j - 1]
		var d1 := D[(i - 1) * W + j]
		var d2 := D[i * W + j - 1]
		if d0 <= d1 and d0 <= d2:
			i -= 1
			j -= 1
		elif d1 <= d2:
			i -= 1
		else:
			j -= 1
	var out := PackedFloat32Array()
	out.resize(na)
	for k in na:
		out[k] = sum[k] / float(maxi(1, cnt[k]))
	return out


## the moment (s) the sequence f first comes within TOL deg rms of the closest it gets to `target` within frames lo..hi (linear
## between frames): [arrival s, closest distance]. Run on the clip AND the take so the ease's tail biases cancel
static func event(f: Array, target: PackedFloat32Array, lo: int, hi: int) -> Array:
	lo = clampi(lo, 0, f.size() - 1)
	hi = clampi(hi, lo, f.size() - 1)
	var d := []
	var dmin := INF
	for k in range(lo, hi + 1):
		var x := dist(f[k], target)
		d.append(x)
		dmin = minf(dmin, x)
	var thr := dmin + TOL
	var arrive := float(lo)
	for q in d.size():
		if d[q] <= thr:
			if q > 0:
				arrive = float(lo + q - 1) + (d[q - 1] - thr) / maxf(1e-9, d[q - 1] - d[q])
			break
	return [arrive / FPS, dmin]


## where a sequence STOPS for a card, looked for in frames lo..hi: a run of frames whose speed (rms of the 36 angle changes per
## frame) is under STILL_V, that starts inside the window. Of the runs the one starting nearest `near` (a frame, from the DTW map) is
## taken; no run (a pass-through card, a shaky video) = the slowest frame nearest `near`. Returns [arrival s (sub-frame: where the
## speed crosses STILL_V), settled frame (the run's second frame), found]. Speed, not distance to the card's pose: a real
## difference in a pose (the hips turned 20 deg more) moves the closest frame, but not the instant the body comes to rest.
const STILL_V := 0.15   # deg per frame
static func stop_at(f: Array, near: float, lo: int, hi: int) -> Array:
	lo = clampi(lo, 1, f.size() - 2)
	hi = clampi(hi, lo, f.size() - 2)
	var v := {}
	for k in range(lo - 1, hi + 1):
		v[k] = dist(f[k + 1], f[k])
	var best := -1
	var bd := INF
	for k in range(lo, hi + 1):
		if v[k] < STILL_V and v[k - 1] >= STILL_V and absf(float(k) - near) < bd:
			best = k
			bd = absf(float(k) - near)
	if best >= 0:
		var x: float = float(best - 1) + (v[best - 1] - STILL_V) / maxf(1e-9, v[best - 1] - v[best])
		return [x / FPS, mini(best + 1, f.size() - 1), true]
	var bk := lo
	var bs := INF
	for k in range(lo, hi + 1):
		var sc := float(v[k]) + 0.02 * absf(float(k) - near)
		if sc < bs:
			bs = sc
			bk = k
	return [float(bk) / FPS, mini(bk + 1, f.size() - 1), false]


static func _side(j: String) -> String:
	return "left " if j.ends_with("_l") else ("right " if j.ends_with("_r") else "")


## the sentences for one card's joint differences (take - clip, deg): top MAX_LINES of the ones past BIG
static func lines(delta: Dictionary) -> Array:
	var items := []   # [abs, text, joint, axis, value]
	var sp := Vector3.ZERO
	for j in JOINTS:
		var v: Vector3 = delta.get(j, Vector3.ZERO)
		if j.begins_with("spine"):
			sp += v
			continue
		for ax in 3:
			var x: float = [v.x, v.y, v.z][ax]
			if absf(x) < BIG:
				continue
			var n := int(round(absf(x)))
			var more := x > 0.0
			var txt := ""
			if j == "pelvis":
				txt = ["your hip tipped %d deg %s forward", "your hip tilted %d deg %s to the side", "your hip turned %d deg %s"][ax] % [n, "more" if more else "less"]
			elif j.begins_with("lowerarm"):
				txt = "your %selbow stayed %d deg %s bent" % [_side(j), n, "more" if more else "less"]
			elif j.begins_with("calf"):
				txt = "your %sknee stayed %d deg %s bent" % [_side(j), n, "more" if more else "less"]
			elif j.begins_with("upperarm"):
				txt = "your %sshoulder %s %d deg %s" % [_side(j), ["swung forward", "lifted out", "rolled"][ax], n, "more" if more else "less"]
			else:
				txt = "your %sthigh %s %d deg %s" % [_side(j), ["swung forward", "opened out", "rolled"][ax], n, "more" if more else "less"]
			items.append([absf(x), txt, j, AXES[ax], x])
	for ax in 3:
		var x: float = [sp.x, sp.y, sp.z][ax]
		if absf(x) >= BIG:
			var n := int(round(absf(x)))
			items.append([absf(x), "your spine %s %d deg %s" % [["bent forward", "leaned sideways", "rotated"][ax], n, "more" if x > 0.0 else "less"], "spine", AXES[ax], x])
	items.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for q in mini(MAX_LINES, items.size()):
		out.append({"text": items[q][1], "joint": items[q][2], "axis": items[q][3], "deg": items[q][4]})
	return out


## THE COMPARISON. S = the open clip, T = the take (a Scene). Returns {"cards": [per card {"i", "name", "t_clip", "t_take",
## "move_delta" (s, take - clip: negative = faster), "delta" {joint: Vector3 deg}, "lines": [...], "text", "k_take" (the take's
## closest frame)}], "map" (clip frame -> take frame, float), "take" (the take's features)}
static func compare(S: Scene, T: Scene) -> Dictionary:
	var A := sequence(S)
	var Tk := sequence(T)
	var fa: Array = A["f"]
	var ft: Array = Tk["f"]
	var map := dtw_map(fa, ft)
	var ts := S.times()
	var nc := S.cards.size()
	var cards := []
	var tc := []
	var tt := []
	for i in nc:
		var flat: Dictionary = Moves._flat(S.cards[i]["pose"])
		var target := feat(flat["ang"])
		var arr: float = ts[i][1]
		var prv: float = ts[i - 1][1] if i > 0 else arr - 0.4
		var nxt: float = ts[i + 1][1] if i < nc - 1 else arr + 0.4
		var lo := int(floor((prv + arr) * 0.5 * FPS))
		var hi := int(ceil((arr + nxt) * 0.5 * FPS))
		var ec := event(fa, target, lo, hi)
		var m_lo: float = map[clampi(lo, 0, map.size() - 1)]
		var m_hi: float = map[clampi(hi, 0, map.size() - 1)]
		var et := event(ft, target, int(floor(m_lo)) - 3, int(ceil(m_hi)) + 3)
		tc.append(float(ec[0]))
		tt.append(float(et[0]))
		# the pose is read where the take has come to rest after that moment (not at its closest frame: a real difference moves that)
		var k0 := int(ceil(float(et[0]) * FPS))
		var kb := mini(k0 + 3, ft.size() - 1)
		for q in range(k0, mini(k0 + 9, ft.size() - 1)):
			if dist(ft[q + 1], ft[q]) < STILL_V:
				kb = q + 1
				break
		var tf: PackedFloat32Array = ft[kb]
		var delta := {}
		for q in JOINTS.size():
			delta[JOINTS[q]] = Vector3(tf[q * 3] - target[q * 3], tf[q * 3 + 1] - target[q * 3 + 1], tf[q * 3 + 2] - target[q * 3 + 2])
		cards.append({"i": i, "name": String(S.cards[i].get("name", "card %d" % (i + 1))), "t_clip": tc[i], "t_take": tt[i],
			"delta": delta, "k_take": kb, "lines": lines(delta), "close": float(et[1])})
	for i in nc:
		var md := 0.0
		if i > 0:
			md = (tt[i] - tt[i - 1]) - (tc[i] - tc[i - 1])
		cards[i]["move_delta"] = md
		cards[i]["text"] = card_text(cards[i])
	return {"cards": cards, "map": map, "take": ft}


static func card_text(c: Dictionary) -> String:
	var parts := []
	var md: float = c["move_delta"]
	if int(c["i"]) > 0 and absf(md) >= LATE:
		parts.append("you were %.2f s %s on it" % [absf(md), "faster" if md < 0.0 else "slower"])
	for l in c["lines"]:
		parts.append(l["text"])
	if parts.is_empty():
		return "as the clip"
	return ", ".join(parts)


## the take's time for the clip's time t (the ghost follows the playhead through this)
static func take_time(map: PackedFloat32Array, t: float) -> float:
	if map.is_empty():
		return t
	var x := clampf(t * FPS, 0.0, float(map.size() - 1))
	var k := int(floor(x))
	var k2 := mini(k + 1, map.size() - 1)
	return lerpf(map[k], map[k2], x - float(k)) / FPS


## USE MY TIMING: each card's move becomes the clip's move plus the measured difference (never under 0.04 s). Edits S.cards only
static func use_timing(S: Scene, R: Dictionary) -> int:
	var n := 0
	var mv := []
	for i in S.cards.size():
		mv.append(S.move_time(i) if i > 0 else 0.0)
	for c in R["cards"]:
		var i: int = c["i"]
		if i == 0:
			continue
		var m := snappedf(maxf(0.04, mv[i] + float(c["move_delta"])), 0.001)
		if absf(m - mv[i]) > 1e-6:
			n += 1
		S.cards[i]["move"] = m
	return n


## USE MY POSE ON THIS CARD: the card's pose with the 36 compared angles taken from the take's closest frame
## (Bw: a Body that is free to be changed; the rest of the pose - offset, feet, weapon - stays the card's)
static func use_pose(S: Scene, T: Scene, R: Dictionary, i: int, Bw: Body) -> bool:
	if i < 0 or i >= R["cards"].size():
		return false
	var c: Dictionary = R["cards"][i]
	var tf: PackedFloat32Array = (R["take"] as Array)[int(c["k_take"])]
	Bw.from_dict(S.cards[i]["pose"])
	for q in JOINTS.size():
		var j: String = JOINTS[q]
		if Bw.ang.has(j):
			Bw.ang[j] = Bw.clamp_ang(j, Vector3(tf[q * 3], tf[q * 3 + 1], tf[q * 3 + 2]))
	Bw.fk()
	S.cards[i]["pose"] = Bw.to_dict()
	return true
