## fight_rhythm.gd - FIGHT RHYTHM (ROADMAP I19). With two or more fighters in the scene, a TEMPO MAP of the exchange read from the cards:
## every ACTION is one tick: a STRIKE (BeatFight.contacts: the card a "hit" marker sits on, else the cards TimingCoach.is_strike names;
## its time is the contact = the arrival of that card), a BLOCK (a card named block / parry / slip / dodge / duck / ... : I3's counter cards
## and I11's fight-phrase answers carry those names), a STEP (a card with "steps"), or a FEINT (the card this module inserts). Each strike
## says who ATTACKS, with which limb and side (the end effector that travels furthest in the strike's move: TimingCoach._travel's idea),
## its KIND (a word of the card's name: jab / cross / hook / kick ..., else punch or kick from the limb) and who ANSWERS (the first block of
## another fighter from 0.25 s before to ANSWER = 0.8 s after the contact).
##   The BEATS of the tempo are the strikes and feints (the attacks), in time order across all fighters; INTERVAL = the time between two.
## FLAGS (the numbers are Nick's brief, except where said):
##   MONOTONY  interval  the same interval (within one frame) three times in a row
##             side      one fighter strikes from the same side (hand/foot l or r) four times in a row
##             kind      one fighter throws the same kind of strike three times in a row
##   DEAD AIR  more than DEAD_AIR = 1.2 s between two actions of any kind (strike, block, step, feint). 1.2 s is NICK'S number, a heuristic: I found
##             no published figure for stage-fight or screen-fight choreography to cite.
##   RUSH      two strikes of one fighter closer than the least he needs to recover from the first: the follow-through of a strike takes at
##             least TimingCoach.SETTLE_RATIO (1.5) times the strike's own move (the timing coach's rule), so the next strike cannot
##             arrive sooner than that after the first. (The coach has no recovery table; this is its settle rule applied to the interval.)
## SUGGESTIONS, one per flag:
##   add a pause     stretch the hold before the strike by PAUSE_LO .. PAUSE_HI = 0.2 .. 0.4 s (interval monotony: 0.3; rush: the deficit)
##   change side     mirror the strike card (and its wind-up card before it) with Scene.mirror_card, the app's mirror; the root stays put
##   add a feint     the feint maker (I20, scripts/feint.gd): Feint.make on the strike card, its FIRST variant (the real strike from the other
##                   side): a feint that stops at 40-60 % of the reach, a re-chamber, the real strike. For dead air the feint's stop is moved
##                   (the wind-up waits less, the feint holds its stop) to the middle of the gap.
##   a pause         stretches the hold before the strike of the fighter it is applied to AND shifts, by the same amount, the cards of the
##                   OTHER fighters from the first one that answers the pause point: blocks keep their offset to the strikes.
## analyze() reads; fix() builds a changed CLONE of one fighter's scene; nothing here writes a file or touches the scenes it is given.
class_name FightRhythm
extends RefCounted

const DEAD_AIR := 1.2
const SAME_INTERVAL := 3
const SAME_SIDE := 4
const SAME_KIND := 3
const PAUSE_LO := 0.2
const PAUSE_HI := 0.4
const PAUSE_MID := 0.3
const ANSWER := 0.8
const ANSWER_BEFORE := 0.25
const KIND_WORDS := ["jab", "cross", "hook", "uppercut", "punch", "kick", "slash", "swing", "thrust", "stab", "smash"]
const BLOCK_WORDS := ["block", "parry", "slip", "dodge", "duck", "deflect", "evade", "weave", "counter"]
const LIMBS := ["hand_l", "hand_r", "foot_l", "foot_r"]


static func _is_feint(nm: String) -> bool:
	return nm.begins_with("feint") and not nm.contains("back")


static func _word(nm: String, words: Array) -> String:
	for w in words:
		if nm.contains(w):
			return w
	return ""


## the limb that travels furthest in card i's move: [limb, metres]
static func _limb(S: Scene, B: Body, i: int) -> Array:
	var ts := S.times()
	S.apply(B, ts[i][0])
	var p0 := {}
	for l in LIMBS:
		p0[l] = B.E[l]
	S.apply(B, ts[i][1])
	var best := "hand_r"
	var bd := -1.0
	for l in LIMBS:
		var d: float = (B.E[l] as Vector3).distance_to(p0[l])
		if d > bd:
			bd = d
			best = l
	return [best, bd]


## the strike cards: BeatFight.contacts (hit markers, else TimingCoach.is_strike, whose word list has hook and uppercut) without the feint cards
static func strike_cards(S: Scene) -> Array:
	return BeatFight.contacts(S).filter(func(i): return not _is_feint(String(S.cards[i]["name"]).to_lower()))


## every action of every fighter, in time order: {t, who, name, card, type: strike / block / step / feint, kind, side, limb, answer}
static func events(scenes: Array, names: Array) -> Array:
	var out := []
	var B := DistanceKeeper.new_body()
	for w in scenes.size():
		var S: Scene = (scenes[w] as Scene).clone()
		var ts := S.times()
		var con := strike_cards(S)
		for i in range(1, S.cards.size()):
			var nm := String(S.cards[i]["name"]).to_lower()
			var e := {"t": float(ts[i][1]), "t0": float(ts[i][0]), "who": w, "name": String(names[w]), "card": i, "type": "", "kind": "", "side": "", "limb": "", "answer": ""}
			if _is_feint(nm):
				e["type"] = "feint"
				e["kind"] = "feint"
			elif con.has(i) and not (_word(nm, BLOCK_WORDS) != "" and _word(nm, KIND_WORDS) == ""):
				var lm := _limb(S, B, i)
				e["type"] = "strike"
				e["limb"] = lm[0]
				e["side"] = String(lm[0]).substr(String(lm[0]).length() - 1)
				var kw := _word(nm, KIND_WORDS)
				e["kind"] = kw if kw != "" else ("kick" if String(lm[0]).begins_with("foot") else "punch")
			elif _word(nm, BLOCK_WORDS) != "":
				e["type"] = "block"
				e["kind"] = _word(nm, BLOCK_WORDS)
			elif not (S.cards[i].get("steps", {}) as Dictionary).is_empty() or nm.begins_with("step"):
				e["type"] = "step"
				e["kind"] = "step"
			if e["type"] != "":
				out.append(e)
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]) if float(a["t"]) != float(b["t"]) else int(a["who"]) < int(b["who"]))
	for e in out:
		if e["type"] != "strike":
			continue
		for d in out:
			if d["type"] == "block" and int(d["who"]) != int(e["who"]) and float(d["t"]) >= float(e["t"]) - ANSWER_BEFORE and float(d["t"]) <= float(e["t"]) + ANSWER:
				e["answer"] = "%s %s" % [d["name"], d["kind"]]
				break
	return out


## the runs (start, length) of equal values in a list, length >= min_len
static func _runs(vals: Array, same: Callable, min_len: int) -> Array:
	var res := []
	var s := 0
	for k in range(1, vals.size() + 1):
		if k == vals.size() or not same.call(vals[k - 1], vals[k]):
			if k - s >= min_len:
				res.append([s, k - s])
			s = k
	return res


static func _fname(v: Array, i: int) -> String:
	return String(v[i]["name"])


## the whole reading. {"events", "beats" (attacks), "intervals": [dt ...], "flags": [...], "msg", "fps"}
## a flag: {type: interval / side / kind / dead_air / rush, t0, t1, who, text, fix: {kind: pause / side / feint, who, card, ...} or {}}
static func analyze(scenes: Array, names: Array, fps := 30) -> Dictionary:
	var ev := events(scenes, names)
	var flags := []
	var frame := 1.0 / float(maxi(1, fps))
	var beats := ev.filter(func(e): return e["type"] == "strike" or e["type"] == "feint")
	var iv := []
	for k in range(1, beats.size()):
		iv.append(float(beats[k]["t"]) - float(beats[k - 1]["t"]))
	# MONOTONY: interval. The flagged run is the beats a..a+n (n equal intervals); the pause goes before beat a+j+1 (j = min(n/2, 2)) so the runs left over are shorter
	for r in _runs(iv, func(a, b): return absf(float(a) - float(b)) <= frame + 1e-6, SAME_INTERVAL):
		var a: int = r[0]
		var n: int = r[1]
		var j := mini(n / 2, 2)
		var tgt: Dictionary = beats[a + j + 1]
		flags.append({"type": "interval", "t0": float(beats[a]["t"]), "t1": float(beats[a + n]["t"]), "who": int(tgt["who"]),
			"text": "monotony: %d beats in a row %.2f s apart (within one frame)" % [n, float(iv[a])],
			"fix": {"kind": "pause", "who": int(tgt["who"]), "card": int(tgt["card"]), "amount": PAUSE_MID, "label": "Add a pause (%.1f s)" % PAUSE_MID}})
	# per fighter: side and kind runs, rush
	for w in scenes.size():
		var mine := beats.filter(func(e): return int(e["who"]) == w)
		for r in _runs(mine, func(a, b): return a["type"] == "strike" and b["type"] == "strike" and a["side"] == b["side"], SAME_SIDE):
			var tgt: Dictionary = mine[int(r[0]) + SAME_SIDE - 1]
			flags.append({"type": "side", "t0": float(mine[r[0]]["t"]), "t1": float(mine[int(r[0]) + int(r[1]) - 1]["t"]), "who": w,
				"text": "monotony: %s strikes from the %s side %d times in a row" % [names[w], "left" if mine[r[0]]["side"] == "l" else "right", int(r[1])],
				"fix": {"kind": "side", "who": w, "card": int(tgt["card"]), "label": "Change side"}})
		for r in _runs(mine, func(a, b): return a["type"] == "strike" and b["type"] == "strike" and a["kind"] == b["kind"], SAME_KIND):
			var s1: Dictionary = mine[int(r[0]) + 1]
			var s2: Dictionary = mine[int(r[0]) + SAME_KIND - 1]
			flags.append({"type": "kind", "t0": float(mine[r[0]]["t"]), "t1": float(mine[int(r[0]) + int(r[1]) - 1]["t"]), "who": w,
				"text": "monotony: %s throws the same strike (%s) %d times in a row" % [names[w], mine[r[0]]["kind"], int(r[1])],
				"fix": {"kind": "feint", "who": w, "strike": int(s2["card"]), "at": (float(s1["t"]) + float(s2["t"])) * 0.5, "label": "Add a feint here"}})
		for k in range(1, mine.size()):
			var a2: Dictionary = mine[k - 1]
			var b2: Dictionary = mine[k]
			if a2["type"] != "strike" or b2["type"] != "strike":
				continue
			var S: Scene = scenes[w]
			var ts := S.times()
			var need := TimingCoach.SETTLE_RATIO * (float(ts[int(a2["card"])][1]) - float(ts[int(a2["card"])][0]))
			var dt := float(b2["t"]) - float(a2["t"])
			if dt < need - 1e-6:
				var amt := maxf(PAUSE_LO, minf(need - dt + 0.02, PAUSE_HI)) if need - dt + 0.02 <= PAUSE_HI else need - dt + 0.02
				flags.append({"type": "rush", "t0": float(a2["t"]), "t1": float(b2["t"]), "who": w,
					"text": "rush: %s strikes again %.2f s after the last, less than the %.2f s he needs to recover (1.5 times the %.2f s strike)" % [names[w], dt, need, need / TimingCoach.SETTLE_RATIO],
					"fix": {"kind": "pause", "who": w, "card": int(b2["card"]), "amount": snappedf(amt, 0.01), "label": "Add a pause (%.2f s)" % amt}})
	# DEAD AIR: any two consecutive actions of any kind
	for k in range(1, ev.size()):
		var g := float(ev[k]["t"]) - float(ev[k - 1]["t"])
		if g > DEAD_AIR + 1e-6:
			var fw := _feint_owner(scenes, ev, k)
			var fx := {}
			if fw >= 0:
				fx = {"kind": "feint", "who": fw, "strike": _near_strike(scenes[fw], ev, fw, (float(ev[k]["t"]) + float(ev[k - 1]["t"])) * 0.5),
					"at": (float(ev[k]["t"]) + float(ev[k - 1]["t"])) * 0.5, "label": "Add a feint here", "from": "dead_air", "t0": float(ev[k - 1]["t"])}
			flags.append({"type": "dead_air", "t0": float(ev[k - 1]["t"]), "t1": float(ev[k]["t"]), "who": int(ev[k]["who"]),
				"text": "dead air: %.2f s with no strike, block or step (the limit is %.1f s: Nick's number, a heuristic)" % [g, DEAD_AIR], "fix": fx})
	flags.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
	var strikes := ev.filter(func(e): return e["type"] == "strike").size()
	var msg := "no strikes found: needs two fighters with strike cards" if ev.is_empty() else ("%d action%s, %d strike%s: the rhythm is varied, no flags" % [ev.size(), "" if ev.size() == 1 else "s", strikes, "" if strikes == 1 else "s"]
		if flags.is_empty() else "%d flag%s over %d actions" % [flags.size(), "" if flags.size() == 1 else "s", ev.size()])
	return {"events": ev, "beats": beats, "intervals": iv, "flags": flags, "msg": msg, "fps": fps, "ok": not ev.is_empty()}


## the fighter that takes the feint in a dead-air gap before event k: the later event's fighter if he has a strike, else any who has
static func _feint_owner(scenes: Array, ev: Array, k: int) -> int:
	var order := [int(ev[k]["who"]), int(ev[k - 1]["who"])]
	for w in scenes.size():
		order.append(w)
	for w in order:
		if not strike_cards((scenes[w] as Scene).clone()).is_empty():
			return w
	return -1


## the strike card of fighter w nearest after t (else the last before it)
static func _near_strike(S: Scene, ev: Array, w: int, t: float) -> int:
	var best := -1
	for e in ev:
		if int(e["who"]) == w and e["type"] == "strike":
			if best < 0:
				best = int(e["card"])
			if float(e["t"]) >= t:
				return int(e["card"])
			best = int(e["card"])
	return best


## who answers whom: [[strike event, block event]] - in time order each strike takes the earliest block of another fighter inside its window
## (ANSWER_BEFORE .. ANSWER) that no earlier strike took, so a block is the answer of one strike only
static func answer_pairs(ev: Array) -> Array:
	var out := []
	var used := {}
	for e in ev:
		if e["type"] != "strike":
			continue
		for d in ev:
			if d["type"] == "block" and int(d["who"]) != int(e["who"]) and not used.has(d) and float(d["t"]) >= float(e["t"]) - ANSWER_BEFORE and float(d["t"]) <= float(e["t"]) + ANSWER:
				used[d] = true
				out.append([e, d])
				break
	return out


## the blocks of the OTHER fighters that answer a strike of fighter w at or after card `from`
static func _answers(scenes: Array, names: Array, w: int, from: int) -> Array:
	return answer_pairs(events(scenes, names)).filter(func(p): return int(p[0]["who"]) == w and int(p[0]["card"]) >= from).map(func(p): return p[1])


## a pause of `amount` before card i of fighter w is made by the caller; this makes the same amount before the first card of each OTHER
## fighter that answers one of the strikes it moves (else the first card that starts at or after the pause point).
## Returns [{who, scene}] for the fighters changed.
static func pause_others(scenes: Array, names: Array, w: int, i: int, amount: float) -> Array:
	var tp := float((scenes[w] as Scene).times()[i][0])
	var ans := _answers(scenes, names, w, i)
	var out := []
	for o in scenes.size():
		if o == w:
			continue
		var S2 := (scenes[o] as Scene).clone()
		var ts := S2.times()
		var k := -1
		for d in ans:   # the earliest card of his that answers a strike the pause moves (a block that answers an earlier strike stays)
			if int(d["who"]) == o and (k < 0 or int(d["card"]) < k):
				k = int(d["card"])
		if k < 0:
			for c in S2.cards.size():
				if float(ts[c][0]) >= tp - 1e-6:
					k = c
					break
		if k < 0:
			continue   # nothing of his after the pause point
		var h := maxi(0, k - 1)
		(S2.cards[h] as Dictionary)["hold"] = float(S2.cards[h]["hold"]) + amount
		out.append({"who": o, "scene": S2})
	return out


## the feint of a flag, made by the feint maker (I20) on the strike card (else the next nearest strike card of that fighter that works)
static func _feint_fix(scenes: Array, names: Array, f: Dictionary, xfs: Array) -> Dictionary:
	var w: int = f["who"]
	var dk := (w + 1) % scenes.size()
	var S: Scene = (scenes[w] as Scene).clone()
	var DS: Scene = (scenes[dk] as Scene).clone()
	var axf: Transform3D = xfs[w] if xfs.size() > w else Transform3D.IDENTITY
	var dxf: Transform3D = xfs[dk] if xfs.size() > dk else Transform3D.IDENTITY
	var at: float = f["at"]
	var ts := S.times()
	var cands := [int(f["strike"])]
	var others := strike_cards(S).filter(func(c): return c != int(f["strike"]))
	others.sort_custom(func(a, b): return absf(float(ts[a][1]) - at) < absf(float(ts[b][1]) - at))
	cands.append_array(others)
	var why := ""
	for ci in cands:
		if ci < 2:
			if why == "":
				why = "pick a strike card that has a wind-up card before it (card 3 or later), then try again"
			continue
		var r := Feint.make(S, axf, DS, dxf, ci)
		if not bool(r["ok"]):
			if why == "":
				why = String(r["why"])
			continue
		var o: Dictionary = (r["options"] as Array)[0]   # the first variant
		var N: Scene = (o["scene"] as Scene).clone()
		var def_scene = o["def"]
		var t_stop := float(o["t_stop"])
		var kf := int(o["k_feint"])
		var t_real := float(o["t_real"])
		# the feint, the re-chamber and the real strike take longer than the one move they replace: the wind-up before them waits that much
		# less (as far as it holds, and the feint's stop stays REACT after the wind-up can be read), so the real strike lands where the original did
		var hp := float(N.cards[kf - 1]["hold"])
		var d1 := clampf(minf(t_real - float(r["t_arr"]), t_stop - (float(r["t_read"]) + Feint.REACT)), 0.0, hp)
		if d1 > 0.001:
			N.cards[kf - 1]["hold"] = snappedf(hp - d1, 0.001)
			t_stop -= d1
			t_real -= d1
		if String(f.get("from", "")) == "dead_air":
			# the stop goes to the middle of the gap: the wind-up before it waits less still, the feint holds its stop longer (the real strike stays put)
			var want := maxf((float(f["t0"]) + t_real) * 0.5, float(r["t_read"]) + Feint.REACT)
			var d := minf(t_stop - want, float(N.cards[kf - 1]["hold"]))
			if d > 0.001:
				N.cards[kf - 1]["hold"] = snappedf(float(N.cards[kf - 1]["hold"]) - d, 0.001)
				N.cards[kf]["hold"] = snappedf(float(N.cards[kf]["hold"]) + d, 0.001)
				t_stop -= d
		if d1 > 0.001 or String(f.get("from", "")) == "dead_air":
			var cv := Feint.move_counter(DS, {"t_read": r["t_read"], "t_arr": r["t_arr"]}, t_stop)
			def_scene = cv["scene"] if cv["ok"] else def_scene
		return {"ok": true, "why": "", "who": w, "scene": N, "frac": float(r["frac"]), "t_stop": t_stop, "ci": ci, "feint_res": r, "att_who": w, "def_who": dk,
			"also": [{"who": dk, "scene": def_scene}] if def_scene != null else [],
			"msg": "%s feints at %.2f s: stops at %.0f%% of the reach of card %d, re-chambers, then the real strike (%s)%s" % [names[w], t_stop, float(r["frac"]) * 100.0, ci + 1,
				String(o["label"]).to_lower(), "; %s's counter moves onto the feint" % names[dk] if def_scene != null else ""]}
	return {"ok": false, "why": "the feint maker cannot make a feint here: " + why}


## the fix of a flag: {"ok", "why", "who", "scene" (a clone of that fighter's scene, changed), "also": [{who, scene}] (other fighters changed with it), "msg"}
## xfs: each fighter's floor transform (the feint maker aims at the defender); [] = all at the origin
static func fix(scenes: Array, names: Array, flag: Dictionary, xfs := []) -> Dictionary:
	var f: Dictionary = flag.get("fix", {})
	if f.is_empty():
		return {"ok": false, "why": "nothing to suggest here: no fighter has a strike card to feint with (add a strike first)"}
	var w: int = f["who"]
	var S2 := (scenes[w] as Scene).clone()
	match String(f["kind"]):
		"pause":
			var i: int = f["card"]
			if i < 1 or i >= S2.cards.size():
				return {"ok": false, "why": "that card is gone: press Fight rhythm again to read the clip fresh"}
			var also := pause_others(scenes, names, w, i, float(f["amount"]))
			(S2.cards[i - 1] as Dictionary)["hold"] = float(S2.cards[i - 1]["hold"]) + float(f["amount"])
			var who := ", ".join(also.map(func(a): return String(names[int(a["who"])])))
			return {"ok": true, "why": "", "who": w, "scene": S2, "also": also,
				"msg": "%s waits %.2f s longer before card %d%s" % [names[w], float(f["amount"]), i + 1,
					"; %s's cards from the answer on move %.2f s later too, so the blocks keep their distance to the strikes" % [who, float(f["amount"])] if not also.is_empty() else ""]}
		"side":
			var i2: int = f["card"]
			if i2 < 1 or i2 >= S2.cards.size():
				return {"ok": false, "why": "that card is gone: press Fight rhythm again to read the clip fresh"}
			var M := DistanceKeeper.new_body()
			var con := strike_cards(S2)
			var which := [i2]
			if i2 - 1 >= 1 and not con.has(i2 - 1):
				which.append(i2 - 1)   # the wind-up goes with it, or the strike would come out of the wrong shoulder
			for c in which:
				var off = S2.cards[c]["pose"]["offset"]
				var mc := Scene.mirror_card(S2.cards[c], M)
				mc["pose"]["offset"] = off   # mirrored limbs, the same place on the floor
				S2.cards[c] = mc
			return {"ok": true, "why": "", "who": w, "scene": S2, "also": [], "msg": "%s strikes from the other side on card %d (mirrored with the wind-up)" % [names[w], i2 + 1]}
		"feint":
			return _feint_fix(scenes, names, f, xfs)
	return {"ok": false, "why": "unknown suggestion"}


## the pose u of the way from a to b (Scene.blend on the flat joints), as a pose dictionary (tests/i31 builds wind-ups with it)
static func blend_pose(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var B := DistanceKeeper.new_body()
	B.from_dict(a)
	var mid := Scene.new().blend(Moves._flat(a), Moves._flat(b), u)
	for j in mid["ang"]:
		B.ang[j] = mid["ang"][j]
	B.offset = mid["offset"]
	return B.to_dict()
