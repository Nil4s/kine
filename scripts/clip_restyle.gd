## clip_restyle.gd - STYLE TRANSFER BY FINGERPRINT (ROADMAP_400 L21). Clip A's timing statistics (ClipPrint) on clip B's poses.
## B's KEY POSES (every card's pose) are never touched. What changes, on B's cards only: the time of each move ("move"), each hold
## ("hold"), the ease of each move ("ease" preset + "ease_bias"), and the scene's "natural" (the limb lag), so that B's fingerprint
## moves toward A's. Search (plan): for every ease preset x bias x natural, scale the moves so the median speed equals A's (one exact
## step: speed goes as 1 / time), keep the best three by the speed / ease / overlap terms, then for each solve the hold scale by
## bisection on the hold fraction, and keep the candidate with the smallest ClipPrint distance to A. If nothing beats B as it is (A onto A:
## the distance is 0), plan() says changed = false and apply_plan() writes nothing.
## PLANTS and MARKERS are in seconds, so they are carried through the retime by the piecewise-linear map of the old card times to the new
## ones (a plant that starts and ends at card arrivals keeps doing so). Scenes with other time-keyed layers (part keys, IK keys, shots,
## face, lip, audio, beats, attributes, strips) or a spline are refused: those would need retiming too.
class_name ClipRestyle
extends RefCounted

const KINDS := ["smooth", "linear", "in", "out", "reach", "strike", "throw", "settle"]
const BIASES := [-0.5, 0.0, 0.5]
const BIAS_MORE := [-0.75, -0.25, 0.25, 0.75]
const MOVE_MIN := 0.04
const KEEP := 3
const TIMED := ["part_keys", "ik", "shots", "face", "lip", "audio_tracks", "beats", "beats_audio", "attrs", "clips"]


static func blocked(S: Scene) -> String:
	if S.cards.size() < 2:
		return "the clip needs two cards"
	if S.spline:
		return "a spline scene keeps its timing in its stops: not retimed"
	for f in TIMED:
		var v: Variant = S.get(f)
		if (v is Array and not (v as Array).is_empty()) or (v is Dictionary and not (v as Dictionary).is_empty()):
			return "the scene has time-keyed '%s', which a retime would not move: not retimed" % f
	return ""


static func tmap(t: float, old: Array, nw: Array) -> float:
	var po := []
	var pn := []
	for i in old.size():
		for k in 3:
			po.append(float(old[i][k]))
			pn.append(float(nw[i][k]))
	if po.is_empty():
		return t
	if t <= float(po[0]):
		return t - float(po[0]) + float(pn[0])
	for i in range(1, po.size()):
		if t <= float(po[i]) and float(po[i]) > float(po[i - 1]):
			return lerpf(float(pn[i - 1]), float(pn[i]), (t - float(po[i - 1])) / (float(po[i]) - float(po[i - 1])))
	return t - float(po[-1]) + float(pn[-1])


static func _put(S: Scene, mv0: Array, h0: Array, km: float, kh: float, kind: String, bias: float, nat: bool) -> void:
	for i in S.cards.size():
		var c: Dictionary = S.cards[i]
		if i > 0:
			c["move"] = maxf(MOVE_MIN, snappedf(float(mv0[i]) * km, 0.001))
			if kind == "smooth":
				c.erase("ease")
			else:
				c["ease"] = kind
			if absf(bias) < 0.005:
				c.erase("ease_bias")
			else:
				c["ease_bias"] = bias
		c["hold"] = maxf(0.0, snappedf(float(h0[i]) * kh, 0.001))
	S.natural = nat


static func _tm(c: Dictionary, k: String) -> float:
	var x := float(c["terms"][k])
	return 0.0 if is_nan(x) else x


## the working numbers of one candidate: the fingerprint and its comparison with A
static func _eval(S: Scene, fpA: Dictionary) -> Dictionary:
	var fp := ClipPrint.measure(S)
	if not bool(fp.get("ok", false)):
		return {"fp": fp, "c": {"terms": {}, "distance": INF}, "soft": INF, "ok": false}
	var c := ClipPrint.compare(fp, fpA)
	var soft := sqrt((pow(_tm(c, "speed"), 2.0) + pow(_tm(c, "ease"), 2.0) + pow(_tm(c, "overlap"), 2.0)) / 3.0)
	return {"fp": fp, "c": c, "soft": soft, "ok": true}


## the move scale that makes the median speed A's, from a measurement at scale km
static func _km_fix(e: Dictionary, fpA: Dictionary, km: float) -> float:
	var s := float(e["fp"]["global"]["speed"])
	var a := float(fpA["global"]["speed"])
	if is_nan(s) or is_nan(a) or s <= 0.0 or a <= 0.0:
		return km
	return clampf(km * s / a, 0.05, 20.0)


static func plan(S: Scene, fpA: Dictionary) -> Dictionary:
	var why := blocked(S)
	if why != "":
		return {"ok": false, "error": why}
	if not bool(fpA.get("ok", false)):
		return {"ok": false, "error": "the source clip has no fingerprint: " + String(fpA.get("error", ""))}
	var e0 := _eval(S, fpA)
	if not e0["ok"]:
		return {"ok": false, "error": String(e0["fp"].get("error", "this clip has no fingerprint"))}
	var d0 := float(e0["c"]["distance"])
	var none := {"ok": true, "changed": false, "before": d0, "after": d0}
	if d0 < 1e-9:
		return none
	var orig: Array = S.cards
	var orig_nat := S.natural
	var old_t: Array = S.times().duplicate(true)
	S.cards = orig.duplicate(true)
	var mv0 := []
	var h0 := []
	for i in S.cards.size():
		mv0.append(S.move_time(i) if i > 0 else 0.0)
		h0.append(float(S.cards[i]["hold"]))
	var hA := float(fpA["global"]["hold"])
	# stage 1: every ease x bias x natural, the moves scaled to A's speed
	var cands := []
	var tried := {}
	var combos := []
	for k in KINDS:
		for b in BIASES:
			for nat in [true, false]:
				combos.append([k, b, nat])
	var ci := 0
	while ci < combos.size():
		var cb: Array = combos[ci]
		ci += 1
		var key := "%s|%s|%s" % [cb[0], cb[1], cb[2]]
		if tried.has(key):
			continue
		tried[key] = true
		_put(S, mv0, h0, 1.0, 1.0, cb[0], cb[1], cb[2])
		var km := _km_fix(_eval(S, fpA), fpA, 1.0)
		_put(S, mv0, h0, km, 1.0, cb[0], cb[1], cb[2])
		var e := _eval(S, fpA)
		cands.append({"kind": cb[0], "bias": cb[1], "nat": cb[2], "km": km, "soft": float(e["soft"])})
		if ci == combos.size() and combos.size() == KINDS.size() * BIASES.size() * 2:
			# stage 1b: the finer biases for the best (kind, natural) so far
			cands.sort_custom(func(x, y): return x["soft"] < y["soft"])
			for bb in BIAS_MORE:
				combos.append([cands[0]["kind"], bb, cands[0]["nat"]])
	cands.sort_custom(func(x, y): return x["soft"] < y["soft"])
	# stage 2: the best few, their hold solved, the full distance
	var best_d := INF
	var best := {}
	for q in mini(KEEP, cands.size()):
		var cd: Dictionary = cands[q]
		var km2 := float(cd["km"])
		var kh := 1.0
		var lo := log(0.05)
		var hi := log(20.0)
		for it in 7:
			kh = exp(0.5 * (lo + hi))
			_put(S, mv0, h0, km2, kh, cd["kind"], cd["bias"], cd["nat"])
			var eh := _eval(S, fpA)
			var h := float(eh["fp"]["global"]["hold"])
			if h > hA:
				hi = 0.5 * (lo + hi)
			else:
				lo = 0.5 * (lo + hi)
		kh = exp(0.5 * (lo + hi))
		_put(S, mv0, h0, km2, kh, cd["kind"], cd["bias"], cd["nat"])
		km2 = _km_fix(_eval(S, fpA), fpA, km2)
		_put(S, mv0, h0, km2, kh, cd["kind"], cd["bias"], cd["nat"])
		var ef := _eval(S, fpA)
		var df := float(ef["c"]["distance"])
		if df < best_d:
			best_d = df
			best = {"km": km2, "kh": kh, "kind": cd["kind"], "bias": cd["bias"], "nat": cd["nat"]}
	if best.is_empty() or best_d >= d0 * 0.999:
		S.cards = orig
		S.natural = orig_nat
		return none
	_put(S, mv0, h0, best["km"], best["kh"], best["kind"], best["bias"], best["nat"])
	var new_t: Array = S.times().duplicate(true)
	var cards_out := []
	for c in S.cards:
		var o := {"move": c["move"], "hold": c["hold"], "has_ease": c.has("ease"), "has_bias": c.has("ease_bias")}
		if c.has("ease"):
			o["ease"] = c["ease"]
		if c.has("ease_bias"):
			o["ease_bias"] = c["ease_bias"]
		cards_out.append(o)
	var natural_out := S.natural
	S.cards = orig
	S.natural = orig_nat
	var plants := []
	for p in S.plants:
		plants.append([snappedf(tmap(float(p["t0"]), old_t, new_t), 0.001), snappedf(tmap(float(p["t1"]), old_t, new_t), 0.001)])
	var marks := []
	for mk in S.markers:
		marks.append(snappedf(tmap(float(mk["t"]), old_t, new_t), 0.001))
	return {"ok": true, "changed": true, "before": d0, "after": best_d, "cards": cards_out, "natural": natural_out, "plants": plants,
		"markers": marks, "move_scale": best["km"], "hold_scale": best["kh"], "ease": best["kind"], "ease_bias": best["bias"]}


## write a plan into the scene (key poses are not touched); the caller makes it ONE undo step
static func apply_plan(S: Scene, pl: Dictionary) -> void:
	if not bool(pl.get("changed", false)):
		return
	var cs: Array = pl["cards"]
	for i in mini(cs.size(), S.cards.size()):
		var c: Dictionary = S.cards[i]
		var o: Dictionary = cs[i]
		c["move"] = o["move"]
		c["hold"] = o["hold"]
		if i == 0:
			continue
		if bool(o["has_ease"]):
			c["ease"] = o["ease"]
		else:
			c.erase("ease")
		if bool(o["has_bias"]):
			c["ease_bias"] = o["ease_bias"]
		else:
			c.erase("ease_bias")
	S.natural = bool(pl["natural"])
	for i in mini(S.plants.size(), (pl["plants"] as Array).size()):
		S.plants[i]["t0"] = pl["plants"][i][0]
		S.plants[i]["t1"] = pl["plants"][i][1]
	for i in mini(S.markers.size(), (pl["markers"] as Array).size()):
		S.markers[i]["t"] = pl["markers"][i]
