## twinning.gd - TWINNING (ROADMAP 19; sources and bars in docs/research/TWINNING.md).
## "Twinning" (Animation Mentor, https://animationmentor.com/?p=4836): a pose that looks mirrored down the middle, or two
## halves that move with identical timing, which reads flat. Here: a left limb and a right limb that are the exact mirror
## of each other while both are moving. The mirror is the one Body.mirror_pose uses: a left joint takes its twin's
## rotation reflected, (x, y, z, w) -> (x, -y, -z, w), so the difference is compared as ang_deg(L, M(R)).
## A window of WIN seconds is flagged when the mean difference of its joints is under D_DEG AND both sides move faster
## than S_DEG; a run of flagged frames at least WIN long is a finding. Arms and legs are graded apart.
## NOT in the default Check: "Check: twinning" shows these (main.gd), and "Fix: offset the picked side by 3 frames"
## shifts the picked side's joints later by OFFSET frames over the flagged range (offset(), one undo step).
class_name Twinning
extends RefCounted

const WIN := 0.3          # s: the sliding window, and the shortest run that counts (the brief)
const D_DEG := 10.0       # deg: mean mirror difference under which a window is twins (ours, calibrated on scenes/*.json)
const S_DEG := 60.0       # deg/s: both sides faster than this are moving (ours, calibrated on scenes/*.json)
const FPS := 60.0         # sampling rate, as the rulebook
const OFFSET := 3         # frames: the fix's offset (the brief)
const EPS := 1e-4
## the joints each kind is graded on (suffix _l / _r). A leg pair is graded the same way; a walk's legs alternate, so
## they do not twin there (Kubo et al. 2004, cited in rulebook.gd GAIT: arms and legs out of phase in walking)
const PARTS := {"arm": ["upperarm", "lowerarm"], "leg": ["thigh", "calf"]}


static func _mirror(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


## the scene at FPS: per kind, the mirror difference (deg) and the speed of the slower side (deg/s) per frame
static func sample(S: Scene, B: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was_stepped := S.stepped
	S.stepped = false   # the grade is of the scene as it plays (as Rulebook.sample)
	var q := []   # per frame: joint -> Quaternion of the joint's rotation
	var ts := []
	for i in n:
		var t := minf(i / FPS, S.length())
		S.apply(B, t)
		var f := {}
		for kind in PARTS:
			for p in PARTS[kind]:
				for s in ["_l", "_r"]:
					f[p + s] = B.compose(p + s, B.ang[p + s])
		q.append(f)
		ts.append(t)
	S.stepped = was_stepped
	var kinds := {}
	for kind in PARTS:
		var parts: Array = PARTS[kind]
		var d := []
		var mv := []
		for i in n:
			var sd := 0.0
			for p in parts:
				sd += Rulebook.ang_deg(q[i][p + "_l"], _mirror(q[i][p + "_r"]))
			d.append(sd / parts.size())
		for i in n:
			var sl := 0.0
			var sr := 0.0
			if i > 0:
				for p in parts:
					sl += Rulebook.ang_deg(q[i - 1][p + "_l"], q[i][p + "_l"]) * FPS
					sr += Rulebook.ang_deg(q[i - 1][p + "_r"], q[i][p + "_r"]) * FPS
				sl /= parts.size()
				sr /= parts.size()
			mv.append(minf(sl, sr))
		kinds[kind] = {"d": d, "mv": mv}
	return {"t": ts, "kinds": kinds}


## the findings: [{"sev": "NOTE", "t", "t0", "t1", "kind", "rule": "TWINNING", "msg", "card"}] by time
static func findings(S: Scene, B: Body, sm := {}) -> Array:
	if S.cards.size() < 2:
		return []
	if sm.is_empty():
		sm = sample(S, B)
	var half := int(round(WIN * FPS / 2.0))
	var win := int(round(WIN * FPS))
	var out := []
	var ts: Array = sm["t"]
	for kind in PARTS:
		var k: Dictionary = sm["kinds"][kind]
		var d: Array = k["d"]
		var mv: Array = k["mv"]
		var n := d.size()
		var pre := [0.0]
		for x in d:
			pre.append(pre.back() + float(x))
		var flag := []
		for i in n:
			var a := maxi(0, i - half)
			var b := mini(n, i + half + 1)
			var g: float = (float(pre[b]) - float(pre[a])) / float(b - a)
			flag.append(g < D_DEG and float(mv[i]) > S_DEG)
		var i := 0
		while i < n:
			if not flag[i]:
				i += 1
				continue
			var j := i
			while j < n and flag[j]:
				j += 1
			if j - i >= win:
				var t0 := float(ts[i])
				var t1 := float(ts[j - 1])
				var who := "arms" if kind == "arm" else "legs"
				out.append({"sev": "NOTE", "t": t0, "t0": t0, "t1": t1, "kind": kind, "rule": "TWINNING",
					"msg": "%s twin from %.2f to %.2f s: offset one side by 2-4 frames or change its pose" % [who, t0, t1],
					"card": Rulebook.card_at(S, t0)})
			i = j
	out.sort_custom(func(x, y): return x["t"] < y["t"])
	return out


## the fix: each range's joints of the picked side (side "l" or "r"), moved later by OFFSET frames. ranges: [{"kind", "t0",
## "t1"}] as findings() gives them. A joint with no part keys is baked over the whole scene at the frame rate first (a part
## key replaces the card blend for its joint, so a joint with a few keys would otherwise hold outside them); a joint with
## keys gets the window baked. Within [t0, t1] the baked angles move later by the offset; keys in (t1, t1 + offset] go.
## Returns the number of joints changed. The caller takes one undo snapshot before this call.
static func offset(S: Scene, B: Body, side: String, ranges: Array) -> int:
	var d := OFFSET / float(S.fps)
	var changed := 0
	for r in ranges:
		var a := float(r["t0"])
		var b := float(r["t1"])
		for p in PARTS[String(r["kind"])]:
			if _shift(S, B, p + "_" + side, a, b, d):
				changed += 1
	return changed


static func _shift(S: Scene, B: Body, j: String, a: float, b: float, d: float) -> bool:
	var keys: Array = S.part_keys.get(j, [])
	var whole := keys.is_empty()
	var step := 1.0 / S.fps
	var lo := 0.0 if whole else a
	var hi := S.length() if whole else b
	var was_stepped := S.stepped
	S.stepped = false
	var grid := []   # [t, Vector3] of the joint as it plays now (before any change)
	var t := lo
	while t <= hi + EPS:
		var tt := minf(t, S.length())
		S.apply(B, tt)
		grid.append([tt, (B.ang[j] as Vector3)])
		t += step
	S.stepped = was_stepped
	var out := []
	for k in keys:
		var tk := float(k["t"])
		if tk < a - EPS or tk > b + d + EPS:
			out.append(k)
	for g in grid:
		var tt: float = g[0]
		if whole:
			if tt < a - EPS:
				out.append({"t": tt, "v": g[1]})
			elif tt <= b + EPS:
				out.append({"t": tt + d, "v": g[1]})
			elif tt > b + d + EPS:
				out.append({"t": tt, "v": g[1]})
		else:
			out.append({"t": tt + d, "v": g[1]})
	if out.is_empty():
		return false
	out.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	# the infinity and modifiers live on the first key (PartKeys.put): they stay with the first key
	if not keys.is_empty():
		var first: Dictionary = keys[0]
		for f in ["inf", "mods"]:
			if first.has(f) and not (out[0] as Dictionary).has(f):
				out[0][f] = first[f]
	S.part_keys[j] = out
	return true
