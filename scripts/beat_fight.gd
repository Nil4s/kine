## beat_fight.gd - FIGHT TO THE BEAT (ROADMAP I15). With the music's beats found (beat_track.gd), every contact of the fight
## (the card a "hit" marker sits on; without markers, each strike card TimingCoach.is_strike names) is moved so it LANDS on a beat
## (or on the off-beat, half way between two beats), by retiming the moves BEFORE it: the wind-up first, the moves before the
## wind-up next (back to the previous contact's follow-through), and only then the strike's own move, which never leaves the
## timing coach's recorded range for that strike (timing_coach.gd peak_range: fist 7.1 .. 11.95 m/s peak over a minimum-jerk bell,
## Sensors 2025 / Stanley 2018 / Flash & Hogan 1985). A contact no beat of the grid can reach inside those limits is FLAGGED with
## the reason and left alone (BeatTrack.snap, the older command, instead refuses the whole job past 25 % of one move).
##   grid: "every" beat | "every2" every second beat (from the first downbeat when there are downbeats) | "down" downbeats only
##   off:  true = the off-beat: the half-way points between consecutive beats of the grid
## Limits that are OURS (the books give the order, not a number): a wind-up never gets shorter than ANTIC_RATIO x its strike
## (as the coach asks) or MIN_FLOOR, and never longer than WINDUP_MAX x its own length; moves before the wind-up may shrink to LEAD_MIN of their length and stretch to WINDUP_MAX; the settle after a fitted contact never gets shorter than SETTLE_RATIO x the strike (the coach's).
## fit() writes the retimed moves into the scene it is given (pass a clone); nothing else changes.
class_name BeatFight
extends RefCounted

const MIN_FLOOR := 0.10   # s: no wind-up or lead-in move shorter than this (ours; MIN_MOVE of Scene.retime is 0.04)
const WINDUP_MAX := 2.0   # x: a move before the strike may stretch to this many times its own length (ours)
const LEAD_MIN := 0.5     # x: a move before the strike may shrink to this fraction of its own length (ours: a half-length lead-in still reads)
const GRIDS := ["every", "every2", "down"]


## the beats the fit may use, in SCENE time (sound time + offset), ascending. Off-beat: the mid-points.
static func grid(beats: Array, off: float, mode: String, offbeat: bool) -> Array:
	var bs := BeatTrack.clean_list(beats)
	var ts := []
	if mode == "down":
		for b in bs:
			if b["down"]:
				ts.append(float(b["t"]) + off)
	elif mode == "every2":
		var first := 0
		for i in bs.size():
			if bs[i]["down"]:
				first = i % 2
				break
		var i := first
		while i < bs.size():
			ts.append(float(bs[i]["t"]) + off)
			i += 2
	else:
		for b in bs:
			ts.append(float(b["t"]) + off)
	if not offbeat:
		return ts
	var mid := []
	for i in range(ts.size() - 1):
		mid.append((float(ts[i]) + float(ts[i + 1])) * 0.5)
	return mid


## the contact cards: the card nearest each hit marker (once each), else every strike card. Ascending.
static func contacts(S: Scene) -> Array:
	var ts := S.times()
	var out := []
	for mk in S.markers:
		if String(mk["kind"]) != "hit":
			continue
		var best := -1
		for i in range(1, S.cards.size()):
			if best < 0 or absf(float(ts[i][1]) - float(mk["t"])) < absf(float(ts[best][1]) - float(mk["t"])):
				best = i
		if best > 0 and not out.has(best):
			out.append(best)
	if out.is_empty():
		for i in range(1, S.cards.size()):
			if TimingCoach.is_strike(S, i):
				out.append(i)
	out.sort()
	return out


## the strike move's recorded range [lo, hi] for card i (seconds); [MIN_MOVE, INF] when the hand barely travels (not a real strike)
static func strike_range(S: Scene, B: Body, i: int) -> Array:
	var ts := S.times()
	var tr := TimingCoach._travel(S, B, float(ts[i - 1][2]), float(ts[i][1]))
	var d: float = tr[0]
	if d < TimingCoach.MIN_TRAVEL:
		return [TimingCoach.MIN_MOVE, INF, d]
	var f := 1.0
	var kind := WeightFeel.kind_at(S, i, B)
	if kind != "":
		var inr := WeightFeel.inertia(B, kind)
		if not inr.is_empty():
			f = pow(float(inr["i"]) / float(WeightFeel.inertia(B, WeightFeel.REF_KIND)["i"]), WeightFeel.N)
	var r := TimingCoach.peak_range(d, f)
	return [float(r[0]), float(r[1]), d]


## how far (seconds, > 0) contact i's arrival can come EARLIER and LATER by retiming what is before it and its own move.
## Returns {"early", "late", "list": [[card, floor, ceil]] (the absorbers in order), "lo", "hi", "d"}
static func reach(S: Scene, B: Body, i: int, prev: int, prev_strike: float) -> Dictionary:
	var rg := strike_range(S, B, i)
	var cur_s := S.move_time(i)
	var list := []
	var early := 0.0
	var late := 0.0
	var j := i - 1
	while j > prev and j >= 1:
		var cur := S.move_time(j)
		var fl := maxf(MIN_FLOOR, LEAD_MIN * cur)
		if j == i - 1:
			fl = maxf(fl, TimingCoach.ANTIC_RATIO * cur_s)
		if j == prev + 1 and prev >= 1:
			fl = maxf(fl, TimingCoach.SETTLE_RATIO * prev_strike)
		fl = minf(fl, cur)
		var ce := maxf(cur, WINDUP_MAX * cur)
		list.append([j, fl, ce])
		early += cur - fl
		late += ce - cur
		j -= 1
	var e_before := early
	var l_before := late
	# the strike's own move, inside the recorded range (a move already outside it can only come back toward it)
	var s_lo := minf(cur_s, float(rg[0]))
	var s_hi := maxf(cur_s, float(rg[1])) if is_finite(float(rg[1])) else cur_s * WINDUP_MAX
	early += cur_s - s_lo
	late += s_hi - cur_s
	return {"early": early, "late": late, "e_before": e_before, "l_before": l_before, "list": list, "lo": s_lo, "hi": s_hi, "d": float(rg[2]), "range": rg}


## FIT scene S (a clone) to the beat grid. Returns
## {"ok" (any contact moved), "msg", "fits": [{card, from, to, beat, changes: [[card, old, new]]}],
##  "flags": [{card, t, beat, why}], "grid": [times], "contacts": n}
static func fit(S: Scene, B: Body, beats: Array, off: float, mode := "every", offbeat := false) -> Dictionary:
	var res := {"ok": false, "msg": "", "fits": [], "flags": [], "grid": [], "contacts": 0}
	if beats.is_empty():
		res["msg"] = "no beats yet: run Beats: find the beats in the sound first (the music track must be a wav)"
		return res
	var g := grid(beats, off, mode, offbeat)
	res["grid"] = g
	if g.is_empty():
		res["msg"] = ("no downbeats were found in this sound (no clear 4/4 grid): pick 'every beat' or 'every 2nd beat'" if mode == "down"
			else "the grid has fewer than two beats, so there is nothing to land on: pick 'every beat' or find the beats again")
		return res
	var cs := contacts(S)
	res["contacts"] = cs.size()
	if cs.is_empty():
		res["msg"] = "no contacts to fit: put a hit marker (kind hit) on each strike card, or name the card (contact, strike, punch...)"
		return res
	var prev := 0
	var prev_strike := 0.0
	var used := []
	for i in cs:
		var ts := S.times()
		var arrive := float(ts[i][1])
		var rc := reach(S, B, i, prev, prev_strike)
		var lo_t := arrive - float(rc["early"])
		var hi_t := arrive + float(rc["late"])
		# the nearest free beat inside the reach
		var best := INF
		for b in g:
			if used.has(b) or float(b) < lo_t - 1e-4 or float(b) > hi_t + 1e-4:
				continue
			if absf(float(b) - arrive) < absf(best - arrive):
				best = float(b)
		if best == INF:
			var near := INF
			for b in g:
				if absf(float(b) - arrive) < absf(near - arrive):
					near = float(b)
			var why := ""
			if near == INF:
				why = "no beat to land on"
			else:
				var need := near - arrive
				var nm := "off-beat" if offbeat else "beat"
				if need < 0.0:
					why = "the nearest %s is %.0f ms earlier; the moves before it can give %.0f ms and the strike %.0f ms more (it cannot go under %.2f s, the fastest recorded punch of %.2f m); left alone" % [
						nm, -need * 1000.0, float(rc["e_before"]) * 1000.0, (S.move_time(i) - float(rc["lo"])) * 1000.0, float(rc["lo"]), float(rc["d"])]
				else:
					why = "the nearest %s is %.0f ms later; the moves before it can stretch %.0f ms and the strike %.0f ms more (it cannot take over %.2f s, the slowest recorded punch of %.2f m); left alone" % [
						nm, need * 1000.0, float(rc["l_before"]) * 1000.0, (float(rc["hi"]) - S.move_time(i)) * 1000.0, float(rc["hi"]), float(rc["d"])]
			res["flags"].append({"card": i, "t": arrive, "beat": near if near != INF else -1.0, "why": "card %d (%s): %s" % [i + 1, S.cards[i]["name"], why]})
			prev = i
			prev_strike = S.move_time(i)
			continue
		used.append(best)
		var need := best - arrive
		var changes := []
		var rest := need
		# absorbers in order: wind-up, then the moves before it, then the strike's own move
		var order := (rc["list"] as Array).duplicate()
		order.append([i, float(rc["lo"]), float(rc["hi"])])
		for a in order:
			if absf(rest) < 1e-9:
				break
			var cj: int = a[0]
			var cur := S.move_time(cj)
			var nv := clampf(cur + rest, float(a[1]), float(a[2]))
			nv = snappedf(nv, 0.001)
			if absf(nv - cur) < 1e-9:
				continue
			changes.append([cj, cur, nv])
			rest -= nv - cur
			S.cards[cj]["move"] = nv
		var after := float(S.times()[i][1])
		res["fits"].append({"card": i, "from": arrive, "to": after, "beat": best, "changes": changes})
		prev = i
		prev_strike = S.move_time(i)
	var moved := 0
	for f in res["fits"]:
		if not (f["changes"] as Array).is_empty():
			moved += 1
	res["ok"] = moved > 0
	if res["ok"]:
		res["msg"] = "%d of %d contacts on the %s%s" % [(res["fits"] as Array).size(), cs.size(), "off-beat" if offbeat else "beat", ("" if (res["flags"] as Array).is_empty() else ", %d flagged (see the timeline)" % (res["flags"] as Array).size())]
	else:
		res["msg"] = "no contact could be fitted: " + ("; ".join((res["flags"] as Array).map(func(f): return String(f["why"]))) if not (res["flags"] as Array).is_empty() else "they already sit on the beat")
	return res
