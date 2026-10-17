## fixer.gd - the Fix button on a Check finding (Nick 10-14: "fixes could update the clip only, not delete them; we
## always have ctrl+z"). A fix only UPDATES cards (move time, flow, pose): never adds, deletes, renames or reorders one
## (asserted). Each fix is re-checked by the rulebook; it is kept only if it removes its problem and makes nothing worse.
## The caller (main.gd) snapshots the scene for Ctrl+Z before calling apply().
class_name Fixer
extends RefCounted

## the parts a head fix may calm: the trunk and neck (the arms ride on them), and the hips' slide (offset)
const TRUNK := ["spine_01", "spine_02", "spine_03", "neck_01", "head"]


## the button's words for a finding, or "" = no safe automatic fix (the row says so)
static func label(f: Dictionary, S: Scene) -> String:
	match f["rule"]:
		"TIP SPEED", "FIST SPEED":
			return "Fix: give this move more time"
		"STRIKE FRAMES":
			return "Fix: make the swing quicker"
		"HITCH":
			return "" if S.spline else "Fix: let the body flow through this card"
		"HEAD QUIET":
			return "Fix: steady the head on this card" if f["card"] > 0 else ""
		"FOOT SLIDE":
			# round 5 had none on purpose (rewriting a card's stance is the animator's call). Round 10 (#51) plants the
			# foot instead: no pose changes, one undo, and it is still the animator who presses it
			return "Fix: plant this foot" if f.has("foot") else ""
	return ""


## apply the fix; returns {"kept", "msg", "before", "after"}. S's cards keep their count, names and order.
## KEPT only if its own finding is gone, the scene has no more FAILs than before, and (a pose fix) no more frames with
## parts inside each other; else the cards are put back and the words say why. sm0: the sample Check already took of
## this scene (saves one full pass: ~4 s on combo3, where every frame re-plants the feet).
## FIX PREVIEW (round 10, #79): the cards this fix WOULD write, with the scene left exactly as it was (the edit runs on a
## deep copy of the cards; the scene's own list is put back, the same object). No check is run: it is a look, not a verdict
static func propose(f: Dictionary, S: Scene, B: Body, sm0 := {}) -> Array:
	var orig := S.cards
	S.cards = orig.duplicate(true)
	match f["rule"]:
		"TIP SPEED", "FIST SPEED":
			_more_time(f, S, B)
		"STRIKE FRAMES":
			_quicker(f, S, B)
		"HITCH":
			_flow(f, S, B)
		"HEAD QUIET":
			_steady_head(f, S, B, sm0 if not sm0.is_empty() else Rulebook.sample(S, B))
		"FOOT SLIDE":
			_plant(f, S, B)
	var after := S.cards
	S.cards = orig
	return after


static func apply(f: Dictionary, S: Scene, B: Body, sm0 := {}) -> Dictionary:
	var names := S.cards.map(func(c): return c["name"])
	var before := S.cards.duplicate(true)
	if sm0.is_empty():
		sm0 = Rulebook.sample(S, B)
	var all0 := Rulebook.check(S, B, sm0)
	var r := {}
	match f["rule"]:
		"TIP SPEED", "FIST SPEED":
			r = _more_time(f, S, B)
		"STRIKE FRAMES":
			r = _quicker(f, S, B)
		"HITCH":
			r = _flow(f, S, B)
		"HEAD QUIET":
			r = _steady_head(f, S, B, sm0)
		"FOOT SLIDE":
			r = _plant(f, S, B)
	assert(S.cards.map(func(c): return c["name"]) == names, "a fix changed the cards' count, names or order")
	var did: String = r["did"]
	var all1: Array = r["after"] if r.get("after") != null else Rulebook.check(S, B)
	var still := all1.filter(func(x): return _same_finding(f, x))
	var fails0 := all0.filter(func(x): return x["sev"] == "FAIL").size()
	var fails1 := all1.filter(func(x): return x["sev"] == "FAIL").size()
	var new := all1.filter(func(x): return all0.filter(func(y): return y["rule"] == x["rule"] and y["card"] == x["card"]).is_empty())
	var why := ""
	if r.get("same", false):
		why = "nothing could be changed"
	elif not still.is_empty():
		why = "it did not remove the problem"
	elif fails1 > fails0:
		why = "it made the scene worse (must-fix %d -> %d: %s)" % [fails0, fails1, ", ".join(new.map(func(x): return "%s on card %d" % [x["rule"], x["card"] + 1]))]
	elif r.get("bad1", 0) > r.get("bad0", 0):
		why = "it pushes parts inside each other (%d -> %d frames)" % [r["bad0"], r["bad1"]]
	if why != "":
		S.cards = before
		return {"kept": false, "msg": "Not applied: %s.  Tried: %s" % [why, did], "before": all0, "after": all0}
	var extra := ("  New to look at: " + ", ".join(new.map(func(x): return "%s on card %d" % [x["rule"], x["card"] + 1]))) if not new.is_empty() else ""
	return {"kept": true, "msg": "Fixed: " + did + extra, "before": all0, "after": all1}


## is x the same problem as f (after the fix moved times about)? same rule on the same card; a hitch: within 0.12 s
static func _same_finding(f: Dictionary, x: Dictionary) -> bool:
	if x["rule"] != f["rule"]:
		return false
	if f["rule"] == "HITCH":
		return absf(x["t"] - f["t"]) < 0.12
	if f["rule"] == "FOOT SLIDE":   # the same foot sliding over the same stretch
		return x.get("foot", "") == f.get("foot", "") and x["t"] < f.get("t1", f["t"]) + 0.1 and x.get("t1", x["t"]) > f["t"] - 0.1
	return x["card"] == f["card"]


## a creeping foot: plant it (Scene PLANTED FEET) on every card whose move or hold overlaps the stretch [t, t1]
static func _plant(f: Dictionary, S: Scene, B: Body) -> Dictionary:
	var sd: String = f["foot"]
	var ts := S.times()
	var on := []
	for c in range(1, S.cards.size()):
		if ts[c][0] < f["t1"] and ts[c][2] > f["t"] and not sd in S.cards[c].get("plant", []):
			S.cards[c]["plant"] = S.cards[c].get("plant", []) + [sd]
			on.append(c + 1)
	if on.is_empty():
		return {"did": "nothing to plant", "same": true}
	return {"did": "the %s foot planted on card%s %s" % ["left" if sd == "_l" else "right", "s" if on.size() > 1 else "", ", ".join(on.map(func(x): return str(x)))]}


## a too-fast move: its card's move time scaled by speed / bar (speed ~ 1 / time), +5%, until the finding is gone
## (usually once: speed is ~ distance / time)
static func _more_time(f: Dictionary, S: Scene, B: Body) -> Dictionary:
	var c: int = f["card"]
	var m0 := S.move_time(c)
	var bar: float = Rulebook.FIST_WARN if f["rule"] == "FIST SPEED" else Rulebook.AT.TIP_MAX.get(_kind(S, B), 40.0)
	var v: float = f["v"]
	var all := []
	for k in 4:
		S.cards[c]["move"] = S.move_time(c) * maxf(1.05, v / bar * 1.05)
		all = Rulebook.check(S, B)
		var left := all.filter(func(x): return x["rule"] == f["rule"] and x["card"] == c)
		if left.is_empty():
			break
		v = left[0]["v"]
	return {"did": "card %d '%s': move %.2f -> %.2f s" % [c + 1, S.cards[c]["name"], m0, S.move_time(c)], "after": all}


## a swing that lasts too many frames: its card's move time x 0.85 until it is gone
static func _quicker(f: Dictionary, S: Scene, B: Body) -> Dictionary:
	var c: int = f["card"]
	var m0 := S.move_time(c)
	var all := []
	for k in 4:
		S.cards[c]["move"] = maxf(0.05, S.move_time(c) * 0.85)
		all = Rulebook.check(S, B)
		if all.filter(func(x): return x["rule"] == "STRIKE FRAMES" and x["card"] == c).is_empty():
			break
	return {"did": "card %d '%s': move %.2f -> %.2f s" % [c + 1, S.cards[c]["name"], m0, S.move_time(c)], "after": all}


## a dead stop between two fast moves (no spline): the card it stops at becomes a FLOW card (passed through)
static func _flow(f: Dictionary, S: Scene, B: Body) -> Dictionary:
	var ts := S.times()
	var best := -1
	for i in range(1, S.cards.size() - 1):
		if best < 0 or absf(float(ts[i][1]) - f["t"]) < absf(float(ts[best][1]) - f["t"]):
			best = i
	if best < 0 or absf(float(ts[best][1]) - f["t"]) > 0.1:
		return {"did": "no card sits at that stop", "same": true}
	S.cards[best]["flow"] = true
	return {"did": "card %d '%s' now flows (passed through without stopping)" % [best + 1, S.cards[best]["name"]]}


## the frames a pose edit on card c can move: the moves into c and out of it (a spline: one card further each way,
## its slopes use the neighbours, and its joints read the curve up to Scene.LEAD x 5 = 75 ms AHEAD, so the window
## opens that much earlier: found when the window first missed 2.82-2.87 s on combo3_detail), one frame of margin.
## Everything outside is re-used from the sample before the edit (tests/fix_test.gd: windowed == full, bit for bit).
## PLANTED FEET CARRY FORWARD (round 32, MM2): with pinning on, a foot pinned on the cards after b stands where card c
## put it (Scene._anchors), and a HOLD plants as its move ended; so the window runs on through every following card
## that pins a foot, and the move after (a step or a free leg leaves FROM the pinned place), to that card's hold end (B: to read the anchors; its pose is kept)
static func window(S: Scene, c: int, B: Body = null) -> Vector2:
	var ts := S.times()
	var k := 2 if S.spline else 1
	var a: int = maxi(c - (k - 1), 0)
	var b: int = mini(c + k, S.cards.size() - 1)
	var lead := Scene.LEAD * 5.0 if S.spline else 0.0
	var end := float(ts[b][1])
	if S.pin and B != null:
		var keep := B.state()
		var E := S._anchors(B)
		B.set_state(keep)
		B.fk()
		# per foot: still LIVE (its anchor came from the edit) while cards pin it; the move into any card reads the
		# anchor before (a step starts from it, a free leg blends out of it), so that card is in; then a non-pin ends it
		var live := {"_l": true, "_r": true}
		while b + 1 < S.cards.size() and (live["_l"] or live["_r"]):
			b += 1
			for sd in live:
				live[sd] = live[sd] and E[b][sd][3] == "pin"
		end = float(ts[b][2]) if b < S.cards.size() - 1 else S.length()
	return Vector2(float(ts[a][0]) - lead - 1.0 / Rulebook.FPS, end + 1.0 / Rulebook.FPS)


## the head travels too far: the card's trunk, neck and the hips' slide blended back toward the card before by the
## LEAST amount that brings the head under the bar (bisection, 6 steps = 1.6%); only the card's window is re-played
## per step. The arms and the weapon ride on the trunk, so the words report what that did to the tip speed.
static func _steady_head(f: Dictionary, S: Scene, B: Body, sm0: Dictionary) -> Dictionary:
	var c: int = f["card"]
	var a := Moves._flat(S.cards[c - 1]["pose"])
	var orig: Dictionary = S.cards[c]["pose"].duplicate(true)
	var b := Moves._flat(orig)
	var w := window(S, c, B)
	var base := Rulebook.sample(S, B, sm0, w.x, w.y, true)   # the window again, to count its contacts
	var tip0 := _tip_in(base, S, c)
	var lo := 0.0
	var hi := 1.0
	var best := -1.0
	for it in 6:
		var k := (lo + hi) * 0.5
		_put(S, B, c, a, b, k)
		var sm := Rulebook.sample(S, B, sm0, w.x, w.y)
		if Rulebook.check(S, B, sm).filter(func(x): return x["rule"] == "HEAD QUIET" and x["card"] == c).is_empty():
			best = k
			lo = k   # quiet: try keeping more of the original
		else:
			hi = k
	if best < 0.0:
		S.cards[c]["pose"] = orig
		return {"did": "card %d: even 98%% of the card before's trunk keeps the head moving (the move itself carries it)" % (c + 1), "same": true}
	_put(S, B, c, a, b, best)
	var sm1 := Rulebook.sample(S, B, sm0, w.x, w.y, true)
	return {"did": "card %d '%s': trunk and hips eased %.0f%% back toward card %d; head %.0f cm -> under %.0f.  Tip %.1f -> %.1f m/s" % [c + 1, S.cards[c]["name"], (1.0 - best) * 100.0, c, f["v"] * 100.0, Rulebook.HEAD_WARN * 100.0, tip0, _tip_in(sm1, S, c)],
		"after": Rulebook.check(S, B, sm1), "bad0": base["bad"], "bad1": sm1["bad"]}


static func _put(S: Scene, B: Body, c: int, a: Dictionary, b: Dictionary, k: float) -> void:
	var p := b.duplicate(true)
	for j in TRUNK:
		if a["ang"].has(j) and b["ang"].has(j):
			p["ang"][j] = (a["ang"][j] as Vector3) + Scene._d(a["ang"][j], b["ang"][j], j) * k
	p["offset"] = (a["offset"] as Vector3).lerp(b["offset"], k)
	Scene.put(B, p)
	if S.on_floor:
		S._ground(B)
	B.apply_grip()
	S.cards[c]["pose"] = B.to_dict()


## the weapon tip's fastest while moving into card c (m/s), read off a sample
static func _tip_in(sm: Dictionary, S: Scene, c: int) -> float:
	var ts := S.times()
	var v := 0.0
	for i in sm["t"].size():
		if sm["t"][i] >= float(ts[c][0]) - 1e-4 and sm["t"][i] <= float(ts[c][2]) + 1e-4:
			v = maxf(v, sm["tip"][i])
	return v


static func _kind(S: Scene, B: Body) -> String:
	S.apply(B, 0.0)
	return B.wep_kind if B.wep_on else ""
