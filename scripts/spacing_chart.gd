class_name SpacingChart
extends RefCounted
## L96 (ROADMAP_400 L24): a spacing chart from a real reference. Agent tool `spacing` (agent_tools.gd, the MCP server). Not in METHODS.
##   {action:"read",  joint, ref, landmark?}   both charts + the per-frame difference (no undo step)
##   {action:"match", joint, ref, landmark?}   Match spacing: re-time the in-betweens toward the reference; the keys never move; ONE undo step
## ref = a tracker file (tools/see_video.py pose.json, read by VideoImport); landmark = the MediaPipe point (0..32), default from the joint.
## The chart: a track is (frame times, positions). Its PROGRESS is the cumulative path length / the whole path (0..1) at each frame; the ticks of
## the classic spacing chart. Two charts compare BY TIME: the move's normalised time tau = (t - t0) / (t1 - t0), the reference's progress read
## at the clip's frame times by a cubic (Catmull-Rom) through its own frames. A step is the progress gained in one frame; the difference is in %
## of an EVEN step (1 / frames in the move). The clip's positions are the joint's key values (degrees, value space: for a one-axis turn the
## arc length is proportional to the angle), the reference's are the tracked landmark's world points (m).
## Match: inside every key-to-key segment the in-betweens (ktype inbetween, linear) sit on the clip's frames at value a + (b - a) * ease(u),
## ease = the reference's progress at the segment's normalised time u. Earlier in-betweens are replaced; the real keys are untouched.

const JOINT_LM := {"upperarm_l": 13, "upperarm_r": 14, "lowerarm_l": 15, "lowerarm_r": 16, "hand_l": 15, "hand_r": 16,
	"thigh_l": 25, "thigh_r": 26, "calf_l": 27, "calf_r": 28, "foot_l": 27, "foot_r": 28}


static func _err(s: String) -> Dictionary:
	return {"ok": false, "error": s}


static func ref_track(P: Dictionary, lm: int) -> Dictionary:
	var t := []
	var p := []
	for f in P["frames"]:
		t.append(float(f["t"]))
		p.append((f["w"] as Array)[lm])
	return {"t": t, "p": p}


static func clip_track(S: Scene, joint: String) -> Dictionary:
	var keys: Array = S.part_keys[joint]
	var t0 := float(keys[0]["t"])
	var t1 := float(keys[keys.size() - 1]["t"])
	var t := []
	var i := 0
	while t0 + float(i) / float(S.fps) < t1 - 1e-6:
		t.append(t0 + float(i) / float(S.fps))
		i += 1
	t.append(t1)
	var p := []
	for x in t:
		p.append(PartKeys.value_at(keys, float(x)))
	return {"t": t, "p": p}


## cumulative path length / whole path, per sample (all zeros for a track that does not move)
static func progress(tr: Dictionary) -> Array:
	var p: Array = tr["p"]
	var c := [0.0]
	for i in range(1, p.size()):
		c.append(float(c[i - 1]) + (p[i] as Vector3).distance_to(p[i - 1]))
	var tot := float(c[c.size() - 1])
	if tot < 1e-9:
		return c.map(func(_x): return 0.0)
	return c.map(func(x): return float(x) / tot)


## the reference's progress at normalised time tau (0..1): a cubic Hermite through its frames, slopes by central differences
static func ref_at(R: Dictionary, pg: Array, tau: float) -> float:
	var t: Array = R["t"]
	var n := t.size()
	var tt := float(t[0]) + clampf(tau, 0.0, 1.0) * (float(t[n - 1]) - float(t[0]))
	var i := 0
	while i < n - 2 and tt >= float(t[i + 1]):
		i += 1
	var h := float(t[i + 1]) - float(t[i])
	var m0 := _slope(t, pg, i)
	var m1 := _slope(t, pg, i + 1)
	var s := clampf((tt - float(t[i])) / maxf(h, 1e-9), 0.0, 1.0)
	var s2 := s * s
	var s3 := s2 * s
	var v := (2 * s3 - 3 * s2 + 1) * float(pg[i]) + (s3 - 2 * s2 + s) * h * m0 + (-2 * s3 + 3 * s2) * float(pg[i + 1]) + (s3 - s2) * h * m1
	return clampf(v, 0.0, 1.0)


static func _slope(t: Array, pg: Array, i: int) -> float:
	var n := t.size()
	var a := maxi(i - 1, 0)
	var b := mini(i + 1, n - 1)
	return (float(pg[b]) - float(pg[a])) / maxf(float(t[b]) - float(t[a]), 1e-9)


static func shape_of(pg: Array) -> String:
	var n := pg.size() - 1
	if n < 4:
		return "linear"
	var slow_in := float(pg[int(roundf(0.25 * n))]) < 0.20
	var slow_out := float(pg[int(roundf(0.75 * n))]) > 0.80
	return "in-out" if slow_in and slow_out else ("ease-in" if slow_in else ("ease-out" if slow_out else "linear"))


## reference vs clip at the clip's frames, by time. Differences in % of an even step
static func compare(R: Dictionary, C: Dictionary) -> Dictionary:
	var rp := progress(R)
	var cp := progress(C)
	var n := (C["t"] as Array).size() - 1
	var c0 := float(C["t"][0])
	var span := maxf(float(C["t"][n]) - c0, 1e-9)
	var sr := []
	for k in n + 1:
		sr.append(ref_at(R, rp, (float(C["t"][k]) - c0) / span))
	var diff := []
	var worst := 0.0
	var sq := 0.0
	var pk_r := 0.0
	var pk_c := 0.0
	for k in n:
		var a := float(sr[k + 1]) - float(sr[k])
		var b := float(cp[k + 1]) - float(cp[k])
		var d := (b - a) * float(n) * 100.0
		diff.append(d)
		worst = maxf(worst, absf(d))
		sq += d * d
		pk_r = maxf(pk_r, a * n)
		pk_c = maxf(pk_c, b * n)
	return {"frames": n, "diff_pct": diff, "max_pct": worst, "rms_pct": sqrt(sq / maxf(float(n), 1.0)),
		"ticks_ref": rp, "ticks_clip": cp, "ref_peak": pk_r, "clip_peak": pk_c,
		"ref_shape": shape_of(sr), "clip_shape": shape_of(cp)}


## Match spacing on joint j of S (the caller owns the undo step). Returns the number of in-between keys
static func match_keys(S: Scene, j: String, R: Dictionary) -> int:
	var rp := progress(R)
	var real := []
	for k in S.part_keys[j]:
		if PartKeys.ktype_of(k) != "inbetween":
			real.append(k)
	var t0 := float(real[0]["t"])
	var out := real.duplicate()
	var fps := float(S.fps)
	for s in real.size() - 1:
		var a: Dictionary = real[s]
		var b: Dictionary = real[s + 1]
		var ta := float(a["t"])
		var tb := float(b["t"])
		var i := int(ceil((ta - t0) * fps + 1e-6))
		while t0 + float(i) / fps < tb - 1e-6:
			var f := t0 + float(i) / fps
			i += 1
			if f <= ta + 1e-6:
				continue
			var e := ref_at(R, rp, (f - ta) / (tb - ta))
			var va: Vector3 = a["v"]
			out.append({"t": f, "v": va + ((b["v"] as Vector3) - va) * e, "ktype": "inbetween", "interp": "linear"})
	out.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	S.part_keys[j] = out
	return out.size() - real.size()


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var a := String(p.get("action", "read"))
	if not a in ["read", "match"]:
		return _err("action is one of read, match")
	var S: Scene = m.S
	var j := String(p.get("joint", ""))
	if not S.part_keys.has(j) or (S.part_keys[j] as Array).size() < 2:
		return _err("joint needs a joint with at least two part keys (got '%s')" % j)
	var lm := int(p["landmark"]) if p.has("landmark") else int(JOINT_LM.get(j, -1))
	if lm < 0 or lm > 32:
		return _err("landmark needs a MediaPipe point 0..32 (the joint '%s' has no default)" % j)
	var P := VideoImport.load_file(String(p.get("ref", "")))
	if not P["ok"]:
		return _err("ref needs a tracker file: " + String(P.get("why", "unreadable")))
	var R := ref_track(P, lm)
	if float(progress(R).back()) == 0.0:
		return _err("the reference landmark does not move in this file: there is no spacing to read")
	var C := clip_track(S, j)
	if float(progress(C).back()) == 0.0:
		return _err("the clip's joint does not move between its keys: there is no spacing to match")
	var before := compare(R, C)
	if a == "read":
		return {"ok": true, "result": before}
	m._push_undo()
	var n := match_keys(S, j, R)
	var after := compare(R, clip_track(S, j))
	if m.has_method("_refresh"):
		m._refresh()
	return {"ok": true, "result": {"inbetweens": n, "max_pct_before": before["max_pct"], "max_pct_after": after["max_pct"], "clip_shape": after["clip_shape"], "ref_shape": after["ref_shape"]}}
