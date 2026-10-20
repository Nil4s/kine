## next_beat.gd - NEXT BEAT, TWO FIGHTERS (ROADMAP I44). The single-fighter "next suggested step" (next_pose.gd) grown to the exchange.
## At the playhead it reads BOTH fighters and proposes the next beat for EITHER, ranked, each with a one-line WHY that names its evidence.
## Read only: nothing here touches a scene it is given; insert() writes into a scene the CALLER hands it (a clone for the ghost, the real one on Enter).
##
## WHAT IT READS (t = the playhead):
##   events      FightRhythm.events (I19): every strike / block / step / feint of both fighters, in time order; "blocked N times running" =
##               the trailing run of blocks in one fighter's own events up to t (RUN_MIN = 2 makes a streak).
##   range       DistanceKeeper.gap (I18): the floor distance from a fighter's root to the other's nearest body volume at t, against HIS reach
##               (the farthest a striking limb gets from his root over his own strike cards; DEFAULT_REACH when he has none). Out of range =
##               the gap exceeds the reach by more than DistanceKeeper.MISS (5 cm); the step in aims at DistanceKeeper.JAM_AIM (80 %) of the reach.
##   fatigue     Exertion (I34): F at t from the work budget. Above Exertion.TIRE_FROM (0.5) his strikes come slower by Exertion.TIRE_K F,
##               above Exertion.TIRED (0.6) a reset (guard back up) is offered, and strikes are demoted by half the excess over 0.5.
##   rhythm      FightRhythm (I19): a third strike of one kind in a row (SAME_KIND) or a fourth from one side (SAME_SIDE) would be flagged, so a strike
##               candidate picks another kind / the other side.
##   combos      ComboMine (I23): Nick's mined combos. A streak of blocks looks for a combo that starts block > strike (his usual answer, with the
##               time he leaves after the block); a fighter who has just struck looks for a combo whose beginning is what he just did (the rest of it).
##   counters    Counter.read_time / Counter.REACT (I3) with Precog (I31): a defence is started no sooner than REACT (0.2 s) after the wind-up shows.
## SCORE (0..1, explicit, so the order can be argued with):
##   answer    0.45 + 0.08 min(run, 5) + 0.20 conf      conf = 1 - exp(-count / 2) of the combo (0 with none)
##   close     0.90 for the fighter whose turn it is, 0.70 for the other, when he is out of range (strikes are not offered out of range)
##   continue  0.40 + 0.30 conf + 0.05 matched cards
##   strike    0.30 + 0.10 when it avoids a rhythm flag
##   defend    0.55 (x 0.5 when the reaction would start before the strike can be read)
##   reset     0.50 + 0.40 (F - 0.6) / 0.4
##   x (0.9 + 0.2 kept-rate of the kind in the suggestion journal, I26: 1.0 when nothing is known); a strike x (1 - 0.5 max(0, F - 0.5))
class_name NextBeat
extends RefCounted

const RUN_MIN := 2
const CONT_WINDOW := 1.2     # s: a fighter who struck this recently is mid-combo
const UPCOMING := 1.0        # s: a strike this soon after t is about to land
const DEFAULT_REACH := 0.75  # m: a strike's reach with no strike card of his own to measure (arm 0.44 of body height + shoulder, Winter 2009)
const STEP_MV := 0.25        # s per step in
const STEP_CAP := 0.5        # m of steps proposed at once (two half-strides, DistanceKeeper.STEP_MAX each)
const MAX_LIST := 5
const KIND_ORDER := ["answer", "close", "continue", "strike", "defend", "reset"]
const KIND_TEXT := {"answer": "answer", "close": "close the distance", "continue": "carry on the combo", "strike": "strike", "defend": "defend", "reset": "reset the guard"}

static var _bodies: Array = []


static func _body(k: int, S: Scene) -> Body:
	while _bodies.size() <= k:
		_bodies.append(DistanceKeeper.new_body())
	var b: Body = _bodies[k]
	if b.body != S.body:
		b.set_proportions(S.body)
	return b


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## a strike event's word as ComboMine names it: the kind word, else "kick" (a foot) / "strike"
static func _word(e: Dictionary) -> String:
	var kd := String(e["kind"])
	if kd in FightRhythm.KIND_WORDS and kd != "punch" and kd != "kick":
		return kd
	return "kick" if String(e["limb"]).begins_with("foot") else "strike"


static func _limbtype(e: Dictionary) -> String:
	return "foot" if String(e["limb"]).begins_with("foot") else "hand"


## the card of fighter w in S nearest-before t whose name or pose reads as the strike we copy: his own strike cards (an event list), newest first
static func _own_strikes(ev: Array, w: int) -> Array:
	return ev.filter(func(e): return int(e["who"]) == w and e["type"] == "strike")


static func _blocks_of(ev: Array, w: int) -> Array:
	return ev.filter(func(e): return int(e["who"]) == w and e["type"] == "block")


## fatigue reports for the fighters (Exertion.analyze: heavy, so the caller caches it with the scene revision)
static func fatigue_of(scenes: Array) -> Array:
	var out := []
	var B := DistanceKeeper.new_body()
	for S in scenes:
		out.append(Exertion.analyze(S, B))
	return out


## the whole reading at playhead t. scenes/names/xfs per fighter (xfs: body space -> the hero's). opt: {"combos": ComboMine's list, "cards_of": Callable(combo, side) -> cards
## (default ComboMine.cards_for), "fatigue": fatigue_of's result ([] = none known), "journal": SuggestionJournal or null}.
## -> {"ok", "msg", "list": [{who, kind, label, why, score, cards, t_start, src}], "state": {...}, "ms"}
static func analyze(scenes: Array, names: Array, xfs: Array, t: float, opt: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var out := {"ok": false, "msg": "", "list": [], "state": {}, "ms": 0.0}
	var n := scenes.size()
	if n < 2:
		out["msg"] = "the next beat needs two fighters: 'Actor: add a second fighter' first"
		return out
	var combos: Array = opt.get("combos", [])
	var cards_of: Callable = opt.get("cards_of", Callable())
	if not cards_of.is_valid():
		cards_of = func(c, side): return ComboMine.cards_for(c, side)
	var fat: Array = opt.get("fatigue", [])
	var sj: Variant = opt.get("journal", null)
	var ev := FightRhythm.events(scenes, names)
	var times := scenes.map(func(s): return (s as Scene).times())
	var past := ev.filter(func(e): return float(e["t"]) <= t + 1e-6)
	# ---- the state of each fighter -----------------------------------------------------------------------------------
	var st := []
	var roots := []
	var bodies := []
	for k in n:
		var S: Scene = scenes[k]
		var B := _body(k, S)
		S.apply(B, t)
		bodies.append(B)
		roots.append((xfs[k] as Transform3D) * (B.P["pelvis"] as Vector3))
	var posedict := []
	for k in n:
		posedict.append((bodies[k] as Body).to_dict())
	for k in n:
		var S: Scene = scenes[k]
		var B: Body = bodies[k]
		var mine := past.filter(func(e): return int(e["who"]) == k)
		var run := 0
		for i in range(mine.size() - 1, -1, -1):
			if mine[i]["type"] == "block":
				run += 1
			else:
				break
		var last_strike: Dictionary = {}
		for e in mine:
			if e["type"] == "strike":
				last_strike = e
		# reach: the farthest a striking limb gets from his root over his own strike cards
		var reach := 0.0
		var RB := _body(n + k, S)
		for e in _own_strikes(ev, k):
			S.apply(RB, float(times[k][int(e["card"])][1]))
			reach = maxf(reach, _flat((RB.E[String(e["limb"])] as Vector3) - (RB.P["pelvis"] as Vector3)).length())
		if reach <= 0.0:
			reach = DEFAULT_REACH
		var o := (k + 1) % n
		var caps: Array = (bodies[o] as Body).cross_caps(xfs[o])
		var gap := DistanceKeeper.gap(roots[k], caps, true)
		st.append({"who": k, "name": String(names[k]), "run": run, "last_strike": last_strike, "reach": reach, "gap": gap,
			"in_range": gap <= reach + DistanceKeeper.MISS, "F": Exertion.at(fat[k], t) if k < fat.size() else 0.0,
			"close_by": maxf(0.0, gap - DistanceKeeper.JAM_AIM * reach), "last": mine[-1] if not mine.is_empty() else {}})
	var cands := []
	for k in n:
		_candidates_of(k, scenes, names, xfs, t, ev, past, times, st, posedict, roots, combos, cards_of, cands)
	# ---- rank --------------------------------------------------------------------------------------------------------
	for c in cands:
		var s := float(c["score"])
		if sj != null:
			s *= 0.9 + 0.2 * float(sj.rate("next beat", String(c["kind"])))
		if c["kind"] in ["answer", "continue", "strike"]:
			s *= 1.0 - 0.5 * maxf(0.0, float(st[int(c["who"])]["F"]) - Exertion.TIRE_FROM)
		c["score"] = snappedf(clampf(s, 0.0, 1.0), 0.001)
	cands.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]) if float(a["score"]) != float(b["score"]) else int(a["who"]) < int(b["who"]))
	var seen := {}
	var list := []
	for c in cands:
		var key := "%d_%s" % [int(c["who"]), c["kind"]]
		if seen.has(key):
			continue
		seen[key] = true
		list.append(c)
		if list.size() >= MAX_LIST:
			break
	out["list"] = list
	out["state"] = {"fighters": st, "t": t}
	out["ok"] = not list.is_empty()
	out["msg"] = "%d beat%s to choose from at %.2f s" % [list.size(), "" if list.size() == 1 else "s", t] if out["ok"] else "nothing to suggest here: the fighters are out of cards to learn from (put the playhead in a fight)"
	out["ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	return out


static func _name(names: Array, k: int) -> String:
	return String(names[k])


static func _pc(f: float) -> String:
	return "%.0f %%" % (f * 100.0)


static func _combo_why(c: Dictionary) -> String:
	return "%d time%s in %d clip%s" % [int(c["count"]), "" if int(c["count"]) == 1 else "s", int(c["clips"]), "" if int(c["clips"]) == 1 else "s"]


static func _conf(c: Dictionary) -> float:
	return 1.0 - exp(-float(c["count"]) / 2.0)


## the mined combo whose first parts are block then a strike: [combo, strike word] best first
static func _answer_combo(combos: Array) -> Dictionary:
	var best: Dictionary = {}
	for c in combos:
		var parts: PackedStringArray = String(c["key"]).split(">")
		if parts.size() >= 2 and parts[0] == "block" and not String(parts[1]).begins_with("block") and (c["strikes"] as Array).has(1):
			if best.is_empty() or int(c["count"]) > int(best["count"]):
				best = c
	return best


## a card shifted to start where the fighter stands: all inserted cards keep their offsets RELATIVE to the first, the first one is at `base` (the offset at t)
static func _rebase(cards: Array, base: Array) -> Array:
	if cards.is_empty():
		return cards
	var o0: Array = (cards[0]["pose"] as Dictionary).get("offset", [0.0, 0.0, 0.0])
	for c in cards:
		var o: Array = (c["pose"] as Dictionary).get("offset", [0.0, 0.0, 0.0])
		c["pose"]["offset"] = [float(base[0]) + float(o[0]) - float(o0[0]), float(base[1]), float(base[2]) + float(o[2]) - float(o0[2])]
	return cards


static func _scale_move(cards: Array, F: float) -> float:
	if F <= Exertion.TIRE_FROM or cards.is_empty():
		return 1.0
	var k := 1.0 + Exertion.TIRE_K * F
	for c in cards:
		if float(c.get("move", 0.0)) > 0.0:
			c["move"] = float(c["move"]) * k
	return k


static func _t_start(S: Scene, t: float) -> float:
	var ts := S.times()
	var c := _anchor(S, t)
	return maxf(t, float(ts[c][1]))


## the card the new ones go after: the last whose arrival is at or before t
static func _anchor(S: Scene, t: float) -> int:
	var ts := S.times()
	var c := 0
	for i in S.cards.size():
		if float(ts[i][1]) <= t + 1e-6:
			c = i
	return c


## put `cards` into S so the first one's move starts at t (the hold of the card before is cut to end there; what was left of it follows the last new
## card, so the cards after keep their offsets from it). Returns the index of the first new card. S is changed: hand it a clone to preview.
static func insert(S: Scene, t: float, cards: Array) -> int:
	var ts := S.times()
	var c := _anchor(S, t)
	var arr := float(ts[c][1])
	var h0 := float(S.cards[c]["hold"])
	var keep := maxf(0.0, t - arr)
	if c < S.cards.size() - 1:
		keep = minf(keep, h0)
	var left := maxf(0.0, h0 - keep)
	S.cards[c]["hold"] = keep
	for k in cards.size():
		S.cards.insert(c + 1 + k, (cards[k] as Dictionary).duplicate(true))
	if not cards.is_empty():
		S.cards[c + cards.size()]["hold"] = float(S.cards[c + cards.size()]["hold"]) + left
	return c + 1


## the time the last of the new cards arrives (the ghost stands there), after insert() on a clone
static func ghost_time(S: Scene, first: int, count: int) -> float:
	return float(S.times()[first + count - 1][1])


static func _candidates_of(k: int, scenes: Array, names: Array, xfs: Array, t: float, ev: Array, past: Array, times: Array, st: Array,
		posedict: Array, roots: Array, combos: Array, cards_of: Callable, cands: Array) -> void:
	var n := scenes.size()
	var o := (k + 1) % n
	var me: Dictionary = st[k]
	var nm := _name(names, k)
	var his := "his"
	var S: Scene = scenes[k]
	var base_off: Array = (posedict[k] as Dictionary)["offset"]
	var F := float(me["F"])
	var fat_note := "" if F <= Exertion.TIRE_FROM else "; at %s fatigue his moves come %s slower" % [_pc(F), _pc(Exertion.TIRE_K * F)]
	var ts0 := _t_start(S, t)
	# ---- close the distance --------------------------------------------------------------------------------------------
	if not bool(me["in_range"]):
		var p := minf(float(me["close_by"]), STEP_CAP)
		var u := _flat((roots[o] as Vector3) - (roots[k] as Vector3))
		if u.length() > 1e-4 and p > 0.01:
			u = u.normalized()
			var v: Vector3 = (xfs[k] as Transform3D).basis.inverse() * (u * p)
			var steps := maxi(1, int(ceil(p / DistanceKeeper.STEP_MAX)))
			var cards := []
			var prev := Vector3.ZERO
			for j in range(1, steps + 1):
				var c := {"name": "step in", "pose": (posedict[k] as Dictionary).duplicate(true), "move": STEP_MV, "hold": 0.0}
				var d: Vector3 = v * (float(j) / float(steps))
				c["pose"]["offset"] = [float(base_off[0]) + d.x, float(base_off[1]), float(base_off[2]) + d.z]
				var sd: Vector3 = d - prev
				prev = d
				c["steps"] = {("_l" if j % 2 == 1 else "_r"): [sd.x, 0.0, sd.z]}
				cards.append(c)
			var first := true
			for e in past:
				if e["type"] == "strike":
					first = int(e["who"]) != k
			cands.append({"who": k, "kind": "close", "label": "%s steps in" % nm, "score": 0.90 if first else 0.70, "cards": cards, "t_start": ts0, "src": "range",
				"why": "%s is out of range: his reach is %.0f cm and the other fighter is %.0f cm away; %d step%s in of %.0f cm puts a strike at %s of his reach" % [
					nm, float(me["reach"]) * 100.0, float(me["gap"]) * 100.0, steps, "" if steps == 1 else "s", p * 100.0, _pc(DistanceKeeper.JAM_AIM)]})
		return   # out of range: no strike would reach, nothing else is offered for him
	# ---- answer a streak of blocks ---------------------------------------------------------------------------------------
	var run := int(me["run"])
	var my_strikes := _own_strikes(ev, k)
	var his_strikes := _own_strikes(ev, o)
	if run >= RUN_MIN:
		var cb := _answer_combo(combos)
		var cards := []
		var src := ""
		var why := "%s has blocked %d times running: %s turn to answer" % [nm, run, his]
		var sc := 0.45 + 0.08 * minf(float(run), 5.0)
		if not cb.is_empty():
			var all: Array = cards_of.call(cb, String((me["last"] as Dictionary).get("side", "")))
			var strike_cards := all.slice(1) if all.size() > 1 else []
			if not strike_cards.is_empty():
				cards = strike_cards.duplicate(true)
				src = "combo"
				var delay := float((cb["holds"] as Array)[0]) + float((cb["moves"] as Array)[1])
				sc += 0.20 * _conf(cb)
				var sw := String((cb["words"] as Array)[1])
				why += "; your usual answer is a %s %.2f s after the block (%s)" % [sw, delay, _combo_why(cb)]
		if cards.is_empty():
			# no mined answer: his own strike of the kind he threw last, else a strike like the other fighter's (same skeleton)
			var pick: Dictionary = {}
			var fromw := k
			if not my_strikes.is_empty():
				pick = my_strikes[-1]
			elif not his_strikes.is_empty():
				pick = his_strikes[-1]
				fromw = o
			if not pick.is_empty():
				var sc_src: Scene = scenes[fromw]
				var cd: Dictionary = (sc_src.cards[int(pick["card"])] as Dictionary).duplicate(true)
				cd["move"] = sc_src.move_time(int(pick["card"]))
				cd["name"] = "answer " + String(pick["kind"])
				cards = [cd]
				src = "own" if fromw == k else "copy"
				why += "; no answer of yours is mined yet, so a %s like %s" % [pick["kind"], "his own" if fromw == k else "the other fighter's"]
		if not cards.is_empty():
			_rebase(cards, base_off)
			var sk := _scale_move(cards, F)
			if sk > 1.0:
				why += fat_note
			cands.append({"who": k, "kind": "answer", "label": "%s answers" % nm, "score": sc, "cards": cards, "t_start": ts0, "src": src, "why": why})
	# ---- carry on a combo ---------------------------------------------------------------------------------------------------
	var ls: Dictionary = me["last_strike"]
	if not ls.is_empty() and t - float(ls["t"]) <= CONT_WINDOW and not combos.is_empty():
		var recent := past.filter(func(e): return int(e["who"]) == k and e["type"] in ["strike", "block", "step"])
		var best: Dictionary = {}
		var best_len := 0
		var best_sc := 0.0
		for c in combos:
			var parts: PackedStringArray = String(c["key"]).split(">")
			var words: Array = c["words"]
			for L in range(mini(3, parts.size() - 1), 0, -1):
				if recent.size() < L:
					continue
				var tail: Array = recent.slice(recent.size() - L)
				var okm := true
				for j in L:
					var e: Dictionary = tail[j]
					var w := String(words[j])
					if e["type"] == "strike":
						okm = okm and w == _word(e) and String(parts[j]).split(".").size() == 3 and String(parts[j]).split(".")[1] == _limbtype(e)
					else:
						okm = okm and w == (String(e["type"]))
					if not okm:
						break
				if okm:
					var s2 := 0.40 + 0.30 * _conf(c) + 0.05 * float(L)
					if s2 > best_sc:
						best_sc = s2
						best = c
						best_len = L
					break
		if not best.is_empty():
			var recent_first: Dictionary = {}
			for e in recent.slice(recent.size() - best_len):
				if e["type"] == "strike":
					recent_first = e
					break
			var all2: Array = cards_of.call(best, String(recent_first.get("side", "")))
			var rest := all2.slice(best_len)
			if not rest.is_empty():
				var cards2 := rest.duplicate(true)
				_rebase(cards2, base_off)
				var sk2 := _scale_move(cards2, F)
				var nxt := String((best["words"] as Array)[best_len])
				cands.append({"who": k, "kind": "continue", "label": "%s follows with a %s" % [nm, nxt], "score": best_sc, "cards": cards2, "t_start": ts0, "src": "combo",
					"why": "%s struck %.2f s ago with a %s: your combo %s goes on with a %s, rhythm %s (%s)%s" % [nm, t - float(ls["t"]), ls["kind"], String(best["name"]), nxt,
						" / ".join((best["moves"] as Array).slice(best_len).map(func(x): return "%.2f s" % float(x))), _combo_why(best), fat_note if sk2 > 1.0 else ""]})
	# ---- a fresh strike, varied by the rhythm rules --------------------------------------------------------------------------
	if run < RUN_MIN and (not my_strikes.is_empty() or not his_strikes.is_empty()):
		var mine_ev := past.filter(func(e): return int(e["who"]) == k and e["type"] == "strike")
		var pool := my_strikes if not my_strikes.is_empty() else his_strikes
		var fromw2 := k if not my_strikes.is_empty() else o
		var lastk := String(mine_ev[-1]["kind"]) if not mine_ev.is_empty() else ""
		var lastside := String(mine_ev[-1]["side"]) if not mine_ev.is_empty() else ""
		var kind_run := 0
		var side_run := 0
		for i in range(mine_ev.size() - 1, -1, -1):
			if String(mine_ev[i]["kind"]) != lastk:
				break
			kind_run += 1
		for i in range(mine_ev.size() - 1, -1, -1):
			if String(mine_ev[i]["side"]) != lastside:
				break
			side_run += 1
		var pick2: Dictionary = pool[0]
		var avoided := false
		var why2 := ""
		var want_other_kind := kind_run >= FightRhythm.SAME_KIND - 1 and lastk != ""
		var want_other_side := side_run >= FightRhythm.SAME_SIDE - 1 and lastside != ""
		for e in pool:
			if want_other_kind and String(e["kind"]) != lastk:
				pick2 = e
				avoided = true
				break
		var sc_src2: Scene = scenes[fromw2]
		var cd2: Dictionary = (sc_src2.cards[int(pick2["card"])] as Dictionary).duplicate(true)
		cd2["move"] = sc_src2.move_time(int(pick2["card"]))
		cd2["name"] = String(pick2["kind"])
		if want_other_side and String(pick2["side"]) == lastside:
			cd2 = Scene.mirror_card(cd2, _body(2 * n, S))
			avoided = true
		var cards3 := [cd2]
		_rebase(cards3, base_off)
		var sk3 := _scale_move(cards3, F)
		if mine_ev.is_empty():
			why2 = "%s has not struck yet and the other fighter is in reach (%.0f cm): a %s opens" % [nm, float(me["gap"]) * 100.0, pick2["kind"]]
		elif avoided:
			why2 = "%s threw %d %s%s in a row from the %s side: a third alike would flag the rhythm, so a %s from the other side" % [nm, maxi(kind_run, side_run), lastk, "" if maxi(kind_run, side_run) == 1 else "s", "left" if lastside == "l" else "right", pick2["kind"]]
		else:
			why2 = "%s last struck %.2f s ago with a %s and the other fighter is in reach (%.0f cm): a %s next keeps the rhythm varied" % [nm, t - float(mine_ev[-1]["t"]), lastk, float(me["gap"]) * 100.0, pick2["kind"]]
		if sk3 > 1.0:
			why2 += fat_note
		cands.append({"who": k, "kind": "strike", "label": "%s throws a %s" % [nm, pick2["kind"]], "score": 0.30 + (0.10 if avoided else 0.0), "cards": cards3, "t_start": ts0, "src": "own" if fromw2 == k else "copy", "why": why2})
	# ---- defend a strike that is about to land -----------------------------------------------------------------------------------
	var up: Dictionary = {}
	for e in ev:
		if int(e["who"]) == o and e["type"] == "strike" and float(e["t"]) > t and float(e["t"]) - t <= UPCOMING:
			up = e
			break
	if not up.is_empty() and String(up["answer"]).find(nm) < 0:
		var blocks := _blocks_of(ev, k)
		var rd := Counter.read_time(times[o], int(up["card"]))
		var early := t < rd + Counter.REACT - Precog.TOL
		var cards4: Array = []
		var from_b := ""
		if not blocks.is_empty():
			var cd3: Dictionary = (S.cards[int(blocks[-1]["card"])] as Dictionary).duplicate(true)
			cd3["move"] = S.move_time(int(blocks[-1]["card"]))
			cd3["hold"] = 0.2
			cards4 = [cd3]
			from_b = "your %s from card %d" % [blocks[-1]["kind"], int(blocks[-1]["card"]) + 1]
		if not cards4.is_empty():
			_rebase(cards4, base_off)
			var arrive := ts0 + float(cards4[0]["move"])
			var late := arrive > float(up["t"]) + Precog.TOL
			var sc4 := 0.55 * (0.5 if early else 1.0) * (0.7 if late else 1.0)
			var why4 := "%s's %s lands at %.2f s and shows from %.2f s; %s started now arrives %.2f s %s the hit" % [_name(names, o), up["kind"], float(up["t"]), rd, from_b, absf(float(up["t"]) - arrive), "after" if late else "before"]
			if early:
				why4 += "; too early to be read: nobody reacts under %.1f s (Precog)" % Counter.REACT
			cands.append({"who": k, "kind": "defend", "label": "%s defends" % nm, "score": sc4, "cards": cards4, "t_start": ts0, "src": "own", "why": why4})
	# ---- a tired fighter resets his guard ------------------------------------------------------------------------------------------
	if F > Exertion.TIRED:
		var g: Dictionary = (S.cards[0] as Dictionary).duplicate(true)
		g["name"] = "guard back up"
		g["move"] = 0.4 * (1.0 + Exertion.TIRE_K * F)
		g["hold"] = 0.3
		g["pose"]["offset"] = base_off
		cands.append({"who": k, "kind": "reset", "label": "%s resets his guard" % nm, "score": 0.50 + 0.40 * (F - Exertion.TIRED) / (1.0 - Exertion.TIRED), "cards": [g], "t_start": ts0, "src": "fatigue",
			"why": "%s is at %s fatigue (past %s): a breath with the guard back up before the next strike" % [nm, _pc(F), _pc(Exertion.TIRED)]})


