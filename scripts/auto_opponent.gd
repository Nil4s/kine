## auto_opponent.gd - AUTO OPPONENT (ROADMAP Innovations I37). Static, no UI (auto_opponent_ui.gd draws it; main.gd owns undo).
## For the HERO's clip it builds fighter 2's whole reactive track. For every hero strike (FightRhythm.events' strikes) it picks one response
## and builds it with the tools that already exist, in time order (fighter 2's track so far is what the next strike is judged against):
##   BLOCK / PARRY / SLIP (and DUCK) / STEP-BACK   Counter.guard / .slip / .duck / .step_back: the defender's own pose, inside its joint
##       limits; the step-back is the distance keeper's slide (one step, the other foot pinned, DistanceKeeper.slide_scene's rule).
##   A DEFENCE IS ONLY KEPT IF A PERSON COULD DO IT: its movement starts >= Counter.REACT (0.2 s) after the strike becomes readable
##       (Counter.read_time, the same moment Precog reads) and is in place by the contact. Otherwise the next choice is tried; when none is
##       timely the strike is TAKEN: HitReaction.react bakes the struck body's reaction over the hit (the momentum of the blow).
##   WHICH response: by what Nick's own two-fighter clips do most for that strike kind (habits(): scenes/*.json read only, FightRhythm's
##       matching of a strike to the other fighter's block / parry / slip / step). With fewer than MIN_N examples for that kind there is
##       no data, and a stated default order stands (DEFAULTS: boxing / fencing choreography convention, NOT measured).
## Nothing of the scenes is written: plan() returns fighter 2's new Scene (a clone of its own with the cards replaced).
class_name AutoOpponent
extends RefCounted

const MIN_N := 3            # examples of a strike kind in Nick's clips before they outvote the default
const HOLD_AFTER := 0.15    # s: the defence is held this long past the contact (the weapon's follow-through)
const REC_MOVE := 0.25      # s: the move back to the guard
const REC_GAP := 0.15       # s: a recovery is only made when there is this much room left before the next defence
const TOL := 0.005          # s: Precog's tolerance
const FAMILIES := ["block", "parry", "slip", "step"]
## the default order per strike kind (first = preferred). Convention of boxing / stick-fencing choreography, NOT measured: a straight
## shot is parried or slipped, a hook blocked, an uppercut or a kick stepped away from, a big swing stepped away from, a thrust parried
const DEFAULTS := {
	"jab": ["parry", "slip", "block", "step"], "cross": ["slip", "block", "parry", "step"], "punch": ["block", "slip", "parry", "step"],
	"hook": ["block", "step", "slip", "parry"], "uppercut": ["step", "block", "slip", "parry"], "kick": ["step", "block", "parry", "slip"],
	"slash": ["step", "block", "slip", "parry"], "swing": ["step", "block", "slip", "parry"], "smash": ["step", "block", "slip", "parry"],
	"thrust": ["parry", "slip", "step", "block"], "stab": ["parry", "slip", "step", "block"]}
const FALLBACK := ["block", "slip", "step", "parry"]


## the family of a defender's card word (FightRhythm.BLOCK_WORDS) or "step"
static func family_of(word: String) -> String:
	match word:
		"block", "deflect", "counter":
			return "block"
		"parry":
			return "parry"
		"slip", "dodge", "duck", "evade", "weave":
			return "slip"
		"step":
			return "step"
	return ""


## Nick's habits: {strike kind: {family: count}} from every scene FILE in `dir` (read only) that has a second fighter. A strike of one
## fighter is answered by the first block / step of another within FightRhythm's window (the same matching I19 uses).
## Also returns "files" (two-fighter files read) in the key "_files".
static func habits(dir := "res://scenes") -> Dictionary:
	var out := {"_files": 0}
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if not f.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not (d is Dictionary) or (d as Dictionary).get("actors", []).is_empty():
			continue
		var S := Scene.new()
		S.from_dict(d)
		var scenes := [S]
		var names := ["hero"]
		for a in S.actors:
			scenes.append(a["scene"])
			names.append(String(a["name"]))
		out["_files"] = int(out["_files"]) + 1
		tally(out, scenes, names)
	return out


## add one exchange's answers to a habits table
static func tally(tab: Dictionary, scenes: Array, names: Array) -> void:
	var ev := FightRhythm.events(scenes, names)
	for e in ev:
		if e["type"] != "strike":
			continue
		for d in ev:
			if int(d["who"]) == int(e["who"]) or (d["type"] != "block" and d["type"] != "step"):
				continue
			if float(d["t"]) >= float(e["t"]) - FightRhythm.ANSWER_BEFORE and float(d["t"]) <= float(e["t"]) + FightRhythm.ANSWER:
				var fam := family_of(String(d["kind"]))
				if fam == "":
					continue
				var k := String(e["kind"])
				if not tab.has(k):
					tab[k] = {}
				tab[k][fam] = int((tab[k] as Dictionary).get(fam, 0)) + 1
				break


## the order of responses for a strike kind and why: {"order": [family], "src": text}
static func order_for(kind: String, hab: Dictionary) -> Dictionary:
	var dflt: Array = DEFAULTS.get(kind, FALLBACK)
	var row: Dictionary = hab.get(kind, {})
	var n := 0
	for fam in row:
		n += int(row[fam])
	if n >= MIN_N:
		var fams: Array = dflt.duplicate()
		fams.sort_custom(func(a, b): return int(row.get(a, 0)) > int(row.get(b, 0)))   # stable enough: ties keep the default's order
		var top: String = fams[0]
		return {"order": fams, "src": "your clips answer a %s with a %s %d of %d times" % [kind, top, int(row.get(top, 0)), n], "data": true}
	return {"order": dflt, "src": "no data in your clips for a %s (%d of %d examples needed): default order, %s first" % [kind, n, MIN_N, dflt[0]], "data": false}


## the kinds Counter can build for a family, tried in this order
static func _try(fam: String, P: Dictionary, DS: Scene, dxf: Transform3D) -> Array:
	match fam:
		"block":
			return [Counter.guard(P, DS, dxf, false)]
		"parry":
			return [Counter.guard(P, DS, dxf, true)]
		"slip":
			var s := Counter.slip(P, DS, dxf)
			if bool(s["ok"]):
				return [s]
			return [s, Counter.duck(P, DS, dxf)]
		"step":
			return [Counter.step_back(P, DS, dxf)]
	return []


static func card_name(kind: String) -> String:
	match kind:
		"BLOCK":
			return "auto block"
		"PARRY":
			return "auto parry"
		"STEP-BACK":
			return "auto dodge step back"
		"DUCK":
			return "auto duck"
	return "auto slip"


## fighter 2's cards from the defences so far. evs: [{start, t, tc, pose, kind, steps}] in time order; `guard` the pose it stands in.
## The card before each move holds until it starts; after the contact + HOLD_AFTER it goes back to the guard when there is room.
static func build(guard: Dictionary, evs: Array, end_t: float) -> Array:
	var first := {"name": "auto guard", "pose": guard, "move": -1.0, "hold": 0.0}
	var cards := [first]
	var last: Dictionary = first
	var arr := 0.0
	for k in evs.size():
		var e: Dictionary = evs[k]
		var st := maxf(float(e["start"]), arr)
		last["hold"] = snappedf(maxf(0.0, st - arr), 0.001)
		var mv := maxf(float(e["t"]) - st, 0.04)
		var c := {"name": card_name(String(e["kind"])), "pose": e["pose"], "move": snappedf(mv, 0.001), "hold": 0.0}
		if e.has("steps") and not (e["steps"] as Dictionary).is_empty():
			c["steps"] = e["steps"]
		cards.append(c)
		last = c
		arr = st + mv
		var leave := maxf(float(e["t"]), float(e["tc"])) + HOLD_AFTER
		var nxt: float = float(evs[k + 1]["start"]) if k + 1 < evs.size() else INF
		if nxt - leave >= REC_MOVE + REC_GAP and leave > arr - 1e-9:
			last["hold"] = snappedf(leave - arr, 0.001)
			var rp: Dictionary = guard.duplicate(true)
			rp["offset"] = (e["pose"] as Dictionary).get("offset", rp.get("offset", [0, 0, 0]))
			var rc := {"name": "auto guard", "pose": rp, "move": REC_MOVE, "hold": 0.0}
			cards.append(rc)
			last = rc
			arr = leave + REC_MOVE
	last["hold"] = snappedf(maxf(0.3, end_t - arr), 0.001)
	return cards


static func _scene_with(DS0: Scene, cards: Array) -> Scene:
	var S2 := DS0.clone()
	S2.cards = cards
	return S2


## THE PLAN. AS / axf: the hero's scene and placement; DS0 / dxf: fighter 2's scene (only its first card's pose is kept as the guard) and
## placement; hab: habits(). {"ok", "why", "items": [...], "scene": Scene (fighter 2's new track), "msg", "counts": {response: n}}
## item: {strike (card), kind (strike word), name, contact, readable, resp (BLOCK / PARRY / SLIP / DUCK / STEP-BACK / HIT / NONE), start, t (in place), src, why, tried}
static func plan(AS: Scene, axf: Transform3D, DS0: Scene, dxf: Transform3D, hab: Dictionary = {}) -> Dictionary:
	var fail := {"ok": false, "why": "", "items": [], "scene": null, "msg": "", "counts": {}}
	if DS0.cards.is_empty() or AS.cards.size() < 2:
		fail["why"] = "the hero needs a clip with a strike and fighter 2 a first card: draw the hero's strikes first"
		return fail
	var strikes := []
	for e in FightRhythm.events([AS], ["hero"]):
		if e["type"] == "strike":
			strikes.append(e)
	if strikes.is_empty():
		fail["why"] = "no strike in the hero's clip: name a card for its move (jab, cross, hook, kick, swing, thrust ...) or mark the hit, then try again"
		return fail
	var guard: Dictionary = (DS0.cards[0]["pose"] as Dictionary).duplicate(true)
	var end_t := AS.length() + 0.3
	var DS := _scene_with(DS0, build(guard, [], end_t))
	var evs := []
	var items := []
	var ts := AS.times()
	for e in strikes:
		var ci: int = e["card"]
		var kind: String = e["kind"]
		var od := order_for(kind, hab)
		var it := {"strike": ci, "kind": kind, "name": String(AS.cards[ci]["name"]), "contact": float(e["t"]), "readable": Counter.read_time(ts, ci),
			"resp": "NONE", "start": 0.0, "t": 0.0, "src": od["src"], "why": "", "tried": [], "order": od["order"]}
		var P := Counter.strike(AS, axf, DS, dxf, ci)
		if not bool(P["ok"]):
			it["why"] = String(P["why"])
			items.append(it)
			continue
		it["contact"] = float(P["tc"])
		it["readable"] = float(P["t_read"])
		if not bool(P["contact"]):
			it["why"] = "this %s never touches fighter 2 (it falls short): nothing to answer" % P["what"]
			items.append(it)
			continue
		var chosen: Dictionary = {}
		for fam in od["order"]:
			for r in _try(fam, P, DS, dxf):
				var why := ""
				if not bool(r["ok"]):
					why = String(r["why"])
				elif float(r["start"]) < float(P["t_read"]) + Counter.REACT - TOL:
					why = "starts %.2f s after it shows: under the %.1f s a person needs to react" % [float(r["start"]) - float(P["t_read"]), Counter.REACT]
				elif float(r["t"]) > float(P["tc"]) + TOL:
					why = "in place %.2f s after the hit" % (float(r["t"]) - float(P["tc"]))
				if why == "":
					chosen = r
					break
				(it["tried"] as Array).append("%s: %s" % [String(r["kind"]).to_lower(), why])
			if not chosen.is_empty():
				break
		if chosen.is_empty():
			it["resp"] = "HIT"
			var avail := float(P["tc"]) - float(P["t_read"])
			if avail < Counter.REACT + Counter.MV:
				it["why"] = "only %.2f s between the wind-up showing and the hit, a person needs %.1f s to react plus %.2f s to move: he takes it" % [avail, Counter.REACT, Counter.MV]
			else:
				it["why"] = "none of the four defences works against this one (%s): he takes it" % String((it["tried"] as Array)[0] if not (it["tried"] as Array).is_empty() else "no path").left(110)
			items.append(it)
			continue
		it["resp"] = String(chosen["kind"])
		if it["resp"] == "STAY":
			it["resp"] = "SLIP"
		it["start"] = float(chosen["start"])
		it["t"] = float(chosen["t"])
		it["why"] = String(od["src"])
		if _fam_of_kind(String(chosen["kind"])) != String(od["order"][0]) and not (it["tried"] as Array).is_empty():
			it["why"] += "; but " + String((it["tried"] as Array)[0])
		evs.append({"start": float(chosen["start"]), "t": float(chosen["t"]), "tc": float(P["tc"]), "pose": chosen["pose"], "kind": String(chosen["kind"]),
			"steps": chosen.get("steps", {})})
		DS = _scene_with(DS0, build(guard, evs, end_t))
		items.append(it)
	# the hits: HitReaction over the track so far, in time order (a window is 0.3-0.6 s: a defence inside one is lost and reported)
	var ba := Counter.scratch(AS)
	var bb := Counter.scratch(DS)
	for it in items:
		if it["resp"] != "HIT":
			continue
		var rows := Dummy.fighter_hits(AS, ba, DS, bb, dxf, AS.fps)
		var pick := {}
		var best := 0.2
		for r in rows:
			if String(r["by"]) == "hero" and not Body.is_wep(String(r["on"])) and absf(float(r["t"]) - float(it["contact"])) < best:
				best = absf(float(r["t"]) - float(it["contact"]))
				pick = r
		if pick.is_empty():
			it["resp"] = "NONE"
			it["why"] = "the blow does not reach a body part of fighter 2 in the contact report: nothing to react to"
			continue
		var old_ts := DS.times()
		var n_old := DS.cards.size()
		var rx := HitReaction.react(DS, bb, dxf, pick, ba)
		if not bool(rx["ok"]):
			it["resp"] = "NONE"
			it["why"] = "no reaction could be built: " + String(rx["why"])
			continue
		var a_old := -1   # the first card after the reaction window: it must still start its move when it did (the cards after keep their MOVES, not their times)
		for i in n_old:
			if a_old < 0 and float(old_ts[i][1]) > float(rx["t1"]) + 1e-9:
				a_old = i
		DS.cards = rx["cards"]
		if a_old >= 0:
			var a_new := DS.cards.size() - (n_old - a_old)
			var new_ts := DS.times()
			var shift := float(old_ts[a_old][0]) - float(new_ts[a_new][0])
			if shift > 1e-6 and a_new >= 1:
				(DS.cards[a_new - 1] as Dictionary)["hold"] = snappedf(float(DS.cards[a_new - 1]["hold"]) + shift, 0.001)
		it["start"] = float(rx["t0"])
		it["t"] = float(rx["t1"])
		it["hit"] = {"impulse": (rx["J"] as Vector3).length(), "peak": rad_to_deg(float(rx["peak"])), "shove": float(rx["shove"]), "on": String(pick["on"])}
		it["why"] += "; the reaction takes %.2f s" % (float(rx["t1"]) - float(rx["t0"]))
	var counts := {}
	for it in items:
		counts[it["resp"]] = int(counts.get(it["resp"], 0)) + 1
	var parts := []
	for k in counts:
		parts.append("%d %s" % [counts[k], String(k).to_lower()])
	return {"ok": true, "why": "", "items": items, "scene": DS, "counts": counts,
		"msg": "%d strike%s answered: %s" % [items.size(), "" if items.size() == 1 else "s", ", ".join(parts)]}


static func _fam_of_kind(k: String) -> String:
	match k:
		"BLOCK":
			return "block"
		"PARRY":
			return "parry"
		"STEP-BACK":
			return "step"
	return "slip"
