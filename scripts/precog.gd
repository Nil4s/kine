## precog.gd - PRECOG CHECK (ROADMAP I31). In a scene with two or more fighters: for every strike (FightRhythm.events: I19's classifier) it finds
## the moment the strike becomes READABLE (Counter.read_time: the wind-up begins - the same moment the counter suggestions use) and the
## fighter who ANSWERS it (I19's matching: the first block / parry / slip / dodge card of another fighter from 0.25 s before to 0.8 s after
## the contact; a card answers one strike only). The reaction's ONSET is the start of its move (the defender's pose starts to change), its
## ARRIVAL the end of that move; the CONTACT is the strike's arrival (I19's tick).
##   PRECOG  onset - readable < Counter.REACT (0.2 s): the defender moves before he could have seen it. Simple visual reaction time is
##           0.20-0.25 s (Woodworth & Schlosberg 1954; the constant Counter.REACT already carries); a choice reaction is slower, so 0.2 s is the
##           kindest bar, not a strict one. (Counter.REACT's own comment cites Thorpe, Fize & Marlot 1996 for the first visual choice signal at 0.15 s.)
##   LATE    the reaction arrives after the contact (beyond TimingCoach.TOL = 5 ms): the hit lands first.
## FIX (one per reaction, both fighters' scenes are CLONED, nothing is written): 1. a PRECOG reaction starts at readable + REACT: the hold of the
## card before it grows by the shift (its move keeps its length; what follows moves later with it). 2. a reaction that would then arrive after the
## contact has its move SHORTENED to end at the contact, down to Counter.MV (0.12 s, a quick guard) with the saved time added to its hold so the
## rest keeps its time; when even that is too late the STRIKE is delayed (the hold of its wind-up card; a first strike has no wind-up card, so its
## move is lengthened) until the reaction at Counter.MV arrives at the contact.
class_name Precog
extends RefCounted

const TOL := 0.005   # s: TimingCoach.TOL, the coach's tolerance for a time "inside" a range


static func _first_ok(v: float) -> bool:
	return v >= Counter.REACT - TOL


## the whole reading: {"items": [{att, def, strike (card), react (card), readable, onset, arrival, contact, gap, status: ok/precog/late/both, text}], "flags", "msg", "ok"}
static func analyze(scenes: Array, names: Array) -> Dictionary:
	var ev := FightRhythm.events(scenes, names)
	var items := []
	var claimed := {}
	var times := scenes.map(func(s): return (s as Scene).times())
	for e in ev:
		if e["type"] != "strike":
			continue
		var a: int = e["who"]
		var contact := float(e["t"])
		var best: Dictionary = {}
		for d in ev:
			if d["type"] != "block" or int(d["who"]) == a or claimed.has("%d_%d" % [d["who"], d["card"]]):
				continue
			if float(d["t"]) >= contact - FightRhythm.ANSWER_BEFORE and float(d["t"]) <= contact + FightRhythm.ANSWER:
				best = d
				break
		if best.is_empty():
			continue
		var w: int = best["who"]
		claimed["%d_%d" % [w, best["card"]]] = true
		var rt: Array = times[w]
		var readable := Counter.read_time(times[a], int(e["card"]))
		var onset := float(rt[int(best["card"])][0])
		var arrival := float(rt[int(best["card"])][1])
		var gap := onset - readable
		var pre := not _first_ok(gap)
		var late := arrival - contact > TOL
		var st := "both" if pre and late else ("precog" if pre else ("late" if late else "ok"))
		var txt := ""
		match st:
			"precog":
				txt = "%s's %s starts %.2f s after %s's wind-up shows: nobody reacts in under %.1f s" % [names[w], best["kind"], gap, names[a], Counter.REACT]
			"late":
				txt = "%s's %s lands %.2f s after the hit: the hit gets there first" % [names[w], best["kind"], arrival - contact]
			"both":
				txt = "%s's %s starts %.2f s after the wind-up shows (under %.1f s) and lands %.2f s after the hit" % [names[w], best["kind"], gap, Counter.REACT, arrival - contact]
			_:
				txt = "%s's %s starts %.2f s after the wind-up shows and lands %.2f s before the hit: readable" % [names[w], best["kind"], gap, contact - arrival]
		items.append({"att": a, "def": w, "strike": int(e["card"]), "react": int(best["card"]), "readable": readable, "onset": onset, "arrival": arrival,
			"contact": contact, "gap": gap, "status": st, "text": txt, "kind": String(best["kind"]), "t0": minf(onset, readable), "t1": maxf(arrival, contact)})
	var flags := items.filter(func(i): return i["status"] != "ok")
	var msg := "no strike is answered here: needs two fighters, one striking and one blocking" if items.is_empty() else (
		"%d answered strike%s, all readable in time" % [items.size(), "" if items.size() == 1 else "s"] if flags.is_empty() else "%d of %d reactions break human timing" % [flags.size(), items.size()])
	return {"items": items, "flags": flags, "msg": msg, "ok": not items.is_empty()}


## the fix of one item: {"ok", "why", "scenes": {fighter: Scene clone}, "msg", "onset", "arrival", "contact"} (what the new times will be)
static func fix(scenes: Array, names: Array, it: Dictionary) -> Dictionary:
	if String(it.get("status", "ok")) == "ok":
		return {"ok": false, "why": "this reaction is already readable in time: pick a flagged one"}
	var a: int = it["att"]
	var d: int = it["def"]
	var A: Scene = (scenes[a] as Scene).clone()
	var D: Scene = (scenes[d] as Scene).clone()
	var si: int = it["strike"]
	var ri: int = it["react"]
	if si < 1 or si >= A.cards.size() or ri < 1 or ri >= D.cards.size():
		return {"ok": false, "why": "those cards are gone: press Precog check again to read the clip fresh"}
	var tsd := D.times()
	var onset := float(tsd[ri][0])
	var mv := float(tsd[ri][1]) - onset
	var contact := float(it["contact"])
	var readable := float(it["readable"])
	var parts := []
	var onset2 := maxf(onset, readable + Counter.REACT)
	if onset2 > onset + 1e-6:
		(D.cards[ri - 1] as Dictionary)["hold"] = float(D.cards[ri - 1]["hold"]) + (onset2 - onset)
		parts.append("%s waits %.2f s longer" % [names[d], onset2 - onset])
	var mv2 := mv
	if onset2 + mv > contact + 1e-6:
		if contact - onset2 >= Counter.MV - 1e-6:
			mv2 = snappedf(contact - onset2, 0.001)
			(D.cards[ri] as Dictionary)["move"] = mv2
			(D.cards[ri] as Dictionary)["hold"] = float(D.cards[ri]["hold"]) + (mv - mv2)
			parts.append("its move is %.2f s instead of %.2f s" % [mv2, mv])
		else:
			mv2 = minf(mv, Counter.MV)
			(D.cards[ri] as Dictionary)["move"] = mv2
			(D.cards[ri] as Dictionary)["hold"] = float(D.cards[ri]["hold"]) + (mv - mv2)
			var delay := snappedf(onset2 + mv2 - contact + 0.001, 0.001)
			if si >= 2:
				(A.cards[si - 1] as Dictionary)["hold"] = float(A.cards[si - 1]["hold"]) + delay
			else:
				var tsa := A.times()
				(A.cards[si] as Dictionary)["move"] = float(tsa[si][1]) - float(tsa[si][0]) + delay
			parts.append("%s's strike comes %.2f s later (it cannot be answered any sooner)" % [names[a], delay])
			contact += delay
	var out := {"ok": true, "why": "", "scenes": {d: D}, "msg": "; ".join(parts), "onset": onset2, "arrival": onset2 + mv2, "contact": contact}
	if a != d and parts.size() > 0 and String(parts[-1]).contains("strike comes"):
		out["scenes"][a] = A
	return out
