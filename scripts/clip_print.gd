## clip_print.gd - CLIP PERSONALITY FINGERPRINT (ROADMAP_400 L27). Per joint, from the clip as it plays (Scene.sample at the scene's fps):
##   speed    median and 90th percentile of the joint's angular speed (deg/s) over its MOVING frames (>= HOLD_V deg/s)
##   hold     the fraction of frames below HOLD_V (the joint is at rest)
##   lag_ms   OVERLAP: the phase lag between the parent's speed curve and this joint's (the lag of the cross-correlation peak, +-0.5 s,
##            sub-frame by a parabola); + = the child peaks later than its parent
##   ease     how much of the joint's acceleration sits within +-0.1 s of a key (a card's move start and arrival), divided by the share of
##            the time those windows cover: 1 = uniform, > 1 = abrupt at the keys, < 1 = eased in and out
##   arc      (only with_arc) the mean curvature (1/m) of the world path of hands, feet and head
## compare() puts two fingerprints side by side and gives ONE distance: the root of the weighted mean of the squared TERMS, each term a
## mean over the joints that move in both (speed: |ln ratio| / ln 2, 1 = a factor 2; hold: |diff| / 0.25; overlap: |diff| / 100 ms;
## ease: |ln ratio| / ln 2). ARC has weight 0 in the distance: it is a property of the poses, which a timing transfer keeps; it is in the table.
## The distance is exactly 0 to itself and exactly symmetric (only |differences| are used). Read only.
class_name ClipPrint
extends RefCounted

const JOINTS := ["pelvis", "spine_03", "head", "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
const PARENT := {"spine_03": "pelvis", "head": "spine_03", "upperarm_l": "spine_03", "lowerarm_l": "upperarm_l", "hand_l": "lowerarm_l",
	"upperarm_r": "spine_03", "lowerarm_r": "upperarm_r", "hand_r": "lowerarm_r",
	"thigh_l": "pelvis", "calf_l": "thigh_l", "foot_l": "calf_l", "thigh_r": "pelvis", "calf_r": "thigh_r", "foot_r": "calf_r"}
const ARC_JOINTS := ["head", "hand_l", "hand_r", "foot_l", "foot_r"]
const HOLD_V := 5.0        # deg/s: slower than this = at rest
const KEY_WIN := 0.1       # s: the window round a key for the ease share
const LAG_MAX := 0.5       # s
const W := {"speed": 1.0, "hold": 1.0, "overlap": 1.0, "ease": 1.0, "arc": 0.0}
const TERMS := ["speed", "hold", "overlap", "ease", "arc"]


static func measure(S: Scene, with_arc := false) -> Dictionary:
	var rate := float(maxi(S.fps, 1))
	var L: float = S.length()
	if S.cards.size() < 2 or L <= 0.0:
		return {"ok": false, "error": "a clip needs two cards and some length"}
	var n := int(ceil(L * rate)) + 1
	var tr := {}
	for j in JOINTS:
		tr[j] = []
	for f in n:
		var s: Dictionary = S.sample(minf(float(f) / rate, L))
		var ang: Dictionary = s.get("ang", {})
		for j in JOINTS:
			if ang.has(j):
				(tr[j] as Array).append(ang[j])
	# the key frames
	var ts: Array = S.times()
	var nacc := maxi(n - 2, 0)
	var mask := PackedByteArray()
	mask.resize(nacc)
	var w := int(round(KEY_WIN * rate))
	for i in range(1, ts.size()):
		for tk in [float(ts[i][0]), float(ts[i][1])]:
			var kf := int(round(tk * rate))
			for f in range(maxi(kf - w, 0), mini(kf + w + 1, nacc)):
				mask[f] = 1
	var speeds := {}
	var out := {}
	for j in JOINTS:
		var a: Array = tr[j]
		if a.size() != n:
			continue
		var v := PackedFloat64Array()
		v.resize(n - 1)
		for f in n - 1:
			var d: Vector3 = (a[f + 1] as Vector3) - (a[f] as Vector3)
			d.z = wrapf(d.z, -180.0, 180.0)
			v[f] = d.length() * rate
		speeds[j] = v
		out[j] = _stats(v, mask, rate)
	for j in JOINTS:
		if not out.has(j):
			continue
		out[j]["lag_ms"] = NAN
		var p: String = PARENT.get(j, "")
		if p != "" and out.has(p) and out[j]["moves"] and out[p]["moves"]:
			out[j]["lag_ms"] = _lag(speeds[p], speeds[j], int(round(LAG_MAX * rate))) / rate * 1000.0
	if with_arc:
		_arcs(S, out, n, rate, L)
	return {"ok": true, "rate": rate, "len": L, "joints": out, "global": _global(out)}


static func _stats(v: PackedFloat64Array, mask: PackedByteArray, rate: float) -> Dictionary:
	var mv := []
	for x in v:
		if x >= HOLD_V:
			mv.append(x)
	var r := {"moves": not mv.is_empty(), "hold": 1.0 - float(mv.size()) / maxf(float(v.size()), 1.0), "speed": NAN, "p90": NAN, "ease": NAN, "lag_ms": NAN, "arc": NAN}
	if mv.is_empty():
		return r
	mv.sort()
	r["speed"] = float(mv[int(mv.size() * 0.5)])
	r["p90"] = float(mv[mini(int(mv.size() * 0.9), mv.size() - 1)])
	var tot := 0.0
	var inw := 0.0
	var nw := 0
	var na := mask.size()
	for f in na:
		var acc := absf(v[f + 1] - v[f]) * rate
		tot += acc
		if mask[f] == 1:
			inw += acc
			nw += 1
	if na > 0 and tot > 1e-9 and nw > 0:
		var frac := float(nw) / float(na)
		r["ease"] = (inw / tot) / frac
	return r


## the lag (frames, + = b peaks later than a) at the cross-correlation peak of two speed curves
static func _lag(a: PackedFloat64Array, b: PackedFloat64Array, lm: int) -> float:
	var n := a.size()
	var c := PackedFloat64Array()
	c.resize(2 * lm + 1)
	for k in range(-lm, lm + 1):
		var s := 0.0
		for f in range(maxi(0, -k), mini(n, n - k)):
			s += a[f] * b[f + k]
		c[k + lm] = s
	var best := -1.0
	var bk := 0
	for d in range(0, lm + 1):
		for sg in ([1, -1] if d > 0 else [1]):
			var k: int = d * sg
			if c[k + lm] > best + 1e-9 * maxf(best, 0.0):
				best = c[k + lm]
				bk = k
	var off := 0.0
	if absi(bk) < lm:
		var ym := c[bk - 1 + lm]
		var yp := c[bk + 1 + lm]
		var den := ym - 2.0 * c[bk + lm] + yp
		if den < -1e-12:
			off = clampf(0.5 * (ym - yp) / den, -0.5, 0.5)
	return float(bk) + off


static func _arcs(S: Scene, out: Dictionary, n: int, rate: float, L: float) -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var pos := {}
	for j in ARC_JOINTS:
		pos[j] = []
	for f in n:
		S.apply(B, minf(float(f) / rate, L))
		B.fk()
		for j in ARC_JOINTS:
			(pos[j] as Array).append(B.P[j])
	for j in ARC_JOINTS:
		if not out.has(j):
			continue
		var p: Array = pos[j]
		var sum := 0.0
		var cnt := 0
		for f in range(1, p.size() - 1):
			var a: Vector3 = (p[f] as Vector3) - (p[f - 1] as Vector3)
			var b: Vector3 = (p[f + 1] as Vector3) - (p[f] as Vector3)
			var la := a.length()
			var lb := b.length()
			if la * rate < 0.05 or lb * rate < 0.05:
				continue
			sum += a.angle_to(b) / (0.5 * (la + lb))
			cnt += 1
		out[j]["arc"] = sum / float(cnt) if cnt > 0 else NAN


static func _global(js: Dictionary) -> Dictionary:
	var ls := 0.0
	var ns := 0
	var hs := 0.0
	var nh := 0
	var lg := 0.0
	var nl := 0
	var es := 0.0
	var ne := 0
	var ar := 0.0
	var na := 0
	for j in JOINTS:
		if not js.has(j):
			continue
		var s: Dictionary = js[j]
		hs += float(s["hold"])
		nh += 1
		if not is_nan(float(s["speed"])):
			ls += log(float(s["speed"]))
			ns += 1
		if not is_nan(float(s["lag_ms"])):
			lg += float(s["lag_ms"])
			nl += 1
		if not is_nan(float(s["ease"])):
			es += float(s["ease"])
			ne += 1
		if not is_nan(float(s["arc"])):
			ar += float(s["arc"])
			na += 1
	return {"speed": exp(ls / ns) if ns > 0 else NAN, "hold": hs / nh if nh > 0 else NAN, "lag_ms": lg / nl if nl > 0 else NAN,
		"ease": es / ne if ne > 0 else NAN, "arc": ar / na if na > 0 else NAN}


static func _term(k: String, x: Dictionary, y: Dictionary) -> float:
	match k:
		"speed":
			if is_nan(float(x["speed"])) or is_nan(float(y["speed"])):
				return NAN
			return absf(log(float(x["speed"])) - log(float(y["speed"]))) / log(2.0)
		"hold":
			return absf(float(x["hold"]) - float(y["hold"])) / 0.25
		"overlap":
			if is_nan(float(x["lag_ms"])) or is_nan(float(y["lag_ms"])):
				return NAN
			return absf(float(x["lag_ms"]) - float(y["lag_ms"])) / 100.0
		"ease":
			if is_nan(float(x["ease"])) or is_nan(float(y["ease"])):
				return NAN
			return absf(log(float(x["ease"]) + 0.1) - log(float(y["ease"]) + 0.1)) / log(2.0)
		"arc":
			if is_nan(float(x["arc"])) or is_nan(float(y["arc"])):
				return NAN
			return absf(log(float(x["arc"]) + 1.0) - log(float(y["arc"]) + 1.0))
	return NAN


static func compare(a: Dictionary, b: Dictionary) -> Dictionary:
	var rows := []
	var sums := {}
	var cnts := {}
	for k in TERMS:
		sums[k] = 0.0
		cnts[k] = 0
	var ja: Dictionary = a.get("joints", {})
	var jb: Dictionary = b.get("joints", {})
	for j in JOINTS:
		if not ja.has(j) or not jb.has(j):
			continue
		var row := {"joint": j, "a": ja[j], "b": jb[j]}
		for k in TERMS:
			var t := _term(k, ja[j], jb[j])
			row[k] = t
			if not is_nan(t):
				sums[k] += t
				cnts[k] += 1
		rows.append(row)
	var terms := {}
	var acc := 0.0
	var wsum := 0.0
	for k in TERMS:
		terms[k] = sums[k] / cnts[k] if cnts[k] > 0 else NAN
		if float(W[k]) > 0.0 and cnts[k] > 0:
			acc += float(W[k]) * terms[k] * terms[k]
			wsum += float(W[k])
	return {"rows": rows, "terms": terms, "distance": sqrt(acc / wsum) if wsum > 0.0 else 0.0}


static func _f(x: float, fmt: String) -> String:
	return "-" if is_nan(x) else fmt % x


## the numbers table: one line per joint, A | B, then the terms and the one distance
static func table(a: Dictionary, b: Dictionary, na := "A", nb := "B") -> String:
	var c := compare(a, b)
	var s := "%-11s | %s: speed  hold  lag ms  ease  arc | %s: speed  hold  lag ms  ease  arc\n" % ["joint", na, nb]
	for r in c["rows"]:
		var line := "%-11s |" % r["joint"]
		for side in ["a", "b"]:
			var x: Dictionary = r[side]
			line += " %6s %5s %6s %5s %5s |" % [_f(float(x["speed"]), "%.0f"), _f(float(x["hold"]), "%.2f"), _f(float(x["lag_ms"]), "%.0f"), _f(float(x["ease"]), "%.2f"), _f(float(x["arc"]), "%.1f")]
		s += line + "\n"
	var t: Dictionary = c["terms"]
	s += "terms (0 = alike, 1 = clearly apart): speed %s hold %s overlap %s ease %s (arc %s, not in the distance)\n" % [
		_f(float(t["speed"]), "%.3f"), _f(float(t["hold"]), "%.3f"), _f(float(t["overlap"]), "%.3f"), _f(float(t["ease"]), "%.3f"), _f(float(t["arc"]), "%.3f")]
	s += "distance %.4f" % float(c["distance"])
	return s
