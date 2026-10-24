## weight_xfer.gd - THE WEIGHT-TRANSFER CHECK (docs/INNOVATIONS.md N029): in a combo, each strike needs the weight where it
## starts. A cross drives off the back foot, a lead hook loads the lead side, a kick needs the weight on the support foot
## before the kicking leg leaves the floor. A strike that starts with the weight on the wrong foot is a Check finding,
## "WEIGHT TRANSFER" (WARN), and its Fix shifts the hips onto the right foot on the card the strike starts from.
## WHY: a blind agent keys a jab-cross-kick and cannot see that the cross is thrown off the front foot (it reads as an arm
## punch) or that the kick leaves while the kicking leg still carries the body (it would fall). The numbers say so.
##
## WHAT IS READ (sources and the full reasoning: docs/research/WEIGHT_TRANSFER.md):
##   the strikes   N016's recognizer (MoveRecognizer.analyze) over each card's window (the move into card k and its hold):
##                 its class, its hand or leg ("side") and lead / rear ("stance"). Only these are graded:
##                   cross       (a straight rear-hand punch)  -> the REAR foot = the punching hand's side
##                   hook, lead  (the lead hand's hook)        -> the LEAD foot = the punching hand's side
##                   any kick or knee (front kick, side kick, roundhouse, knee) -> the SUPPORT foot = the other side
##                 Weapon strikes, jabs, uppercuts, elbows and a rear hook are not graded: no source opened says where
##                 their weight must start (stated, not guessed). A square stance (no lead foot) is not graded for punches.
##                 Two windows naming the same strike (peaks under PEAK_GAP apart) count once, the faster. A "cross" whose fist
##                 does not travel forward (the recognizer's path direction, said in the body frame) is a fist coming BACK.
##   when          a punch: the delivery's start (the recognizer's "frames.start": the speed's last low point before its
##                 peak). A kick: LIFT-OFF, the last frame the kicking foot is down before its peak (searched back up to
##                 LOOKBACK s): the moment the support must take the body.
##   the share     the static lever rule along the line joining the two footprints' centres (TextView.left_share: N001's
##                 "weight 81 % on the left foot"; the COM and the footprints are balance.gd's). One foot down = all of it on
##                 that foot. No foot down = not graded.
## BARS (HEURISTIC: the sources give a direction and a coaching split, not a measured distribution; each is set below it):
##   CROSS_MIN 0.45 rear: "more than half of your weight on your rear leg" / "sixty percent ... rear leg" (Evolve MMA);
##                  5 points under one half for the lever rule's footprint resolution
##   HOOK_MIN  0.40 lead: "the weight shifts slightly to the front foot" (Boxing News, Fight school: the hook); lenient
##                  because styles differ (Evolve: the American hook turns the weight onto the back foot as the hips go over)
##   KICK_MIN  0.50 support at lift-off: in single support the support carries all of it (statics); the READY phase before
##                  toe-off is where the support leg does the work (Kinoshita & Fujii 2014, ISBS, 13 taekwondo athletes).
##                  Under half = more weight on the leg that is leaving than on the one that must hold him
## THE FIX (Fixer, the Check panel's Fix button, one Ctrl+Z): the card the strike starts FROM (the last card arrived at by
## the measured moment) gets a pelvis offset along the feet's line toward the needed foot, the feet re-planted where they
## stood (shift()), aiming at the bar + FIX_MARGIN; the strike is measured again as it plays and the aim raised by the
## shortfall, up to FIX_TRIES. No card is added (Fixer never adds one): the shift lives in the pose the strike leaves from.
class_name WeightXfer
extends RefCounted

const FPS := 60.0
const CROSS_MIN := 0.45     # HEURISTIC: share on the rear foot at a cross's start (Evolve MMA: "more than half", 60/40)
const HOOK_MIN := 0.40      # HEURISTIC: share on the lead foot at a lead hook's start (Boxing News: "shifts slightly to the front foot")
const KICK_MIN := 0.50      # HEURISTIC: share on the support foot at the kicking foot's lift-off (statics; Kinoshita & Fujii 2014)
const FIX_MARGIN := 0.15    # HEURISTIC: the fix aims this far over the bar on the card (cross: 60 %, Evolve's own split)
const FIX_GOAL := 0.12      # HEURISTIC: the fix is done when the strike STARTS this far over the bar (cross: 57 %)
const FIX_TRIES := 4
const SHARE_MAX := 0.9      # the fix never aims past 90 % on one foot (the other still touches: it is a stance, not a lift)
const PLANT_TOL := 0.01     # m: a re-planted ball may miss its mark by this much (Balance.TOUCH)
const SINK_MAX := 0.08      # m: the most the hips sink to keep both feet planted while they shift
const PEAK_GAP := 0.25      # s: Rulebook.strikes's own spacing; two windows peaking closer name one strike
const LOOKBACK := 1.0       # s before a kick's peak in which its lift-off is looked for
const KICKS := ["front kick", "side kick", "roundhouse", "knee"]
const MEMO_MAX := 16        # scenes (by their play signature) whose strikes are remembered: Check and Fix ask again and again

static var _memo := {}


## the graded strikes of a scene, each with the weight where it starts:
## [{"card", "class", "side" ("_l"/"_r", the striking limb), "need" (the foot that must carry it), "role" ("rear" / "lead" /
##   "support"), "t" (s, the measured moment), "when" ("start" / "lift-off"), "share" (0..1 on the needed foot), "bar",
##   "peak" (frame), "speed" (m/s)}]
static func strikes(S: Scene, B: Body) -> Array:
	var out := []
	if S.cards.size() < 2:
		return out
	var keep := B.state()
	var was := S.stepped
	S.stepped = false   # graded as it really plays (Rulebook.sample's rule)
	# off the main thread (the Fix PREVIEW runs Fixer.propose in a WorkerThreadPool task): the serial sampler, which neither
	# touches EventQuery's shared cache nor starts a group task from inside a pool thread
	var main := OS.get_thread_caller_id() == OS.get_main_thread_id()
	var key := ""
	if main:
		key = PoseBake.signature(S).hex_encode().sha256_text() + str(B.body.hash())
		if _memo.has(key):
			S.stepped = was
			return (_memo[key] as Array).duplicate(true)
	var clip := EventQuery.sample([{"S": S, "B": B, "xf": Transform3D.IDENTITY, "name": String(S.name)}], FPS, {"cross": false, "bal": false}, not main)
	var ts := S.times()
	var dn: PackedByteArray = clip["down"][0]
	var n: int = clip["n"]
	for k in range(1, S.cards.size()):
		var f0 := int(round(float(ts[k][0]) * FPS))
		var f1 := mini(int(round(float(ts[k][2]) * FPS)), n - 1)
		var r := MoveRecognizer.analyze(clip, 0, f0, f1)
		if not r.get("strike", false) or r.get("unknown", true) or String(r.get("group", "")) == "weapon":
			continue
		var cls := String(r["class"])
		var sd := "_l" if String(r["side"]) == "left" else "_r"
		var other := "_r" if sd == "_l" else "_l"
		var it := {"card": k, "class": cls, "side": sd, "peak": int(r["frames"]["peak"]), "speed": float(r["speed"]["peak_ms"])}
		if cls == "cross" and not String(r["path"]["direction"]).begins_with("forward"):
			continue   # a "cross" whose fist does not travel forward is a fist pulled back (text-blocked "hook, step in"'s follow-through: back 12 cm)
		if cls == "cross" and String(r["stance"]) == "rear":
			it.merge({"need": sd, "role": "rear", "bar": CROSS_MIN, "when": "start", "f": int(r["frames"]["start"])})
		elif cls == "hook" and String(r["stance"]) == "lead":
			it.merge({"need": sd, "role": "lead", "bar": HOOK_MIN, "when": "start", "f": int(r["frames"]["start"])})
		elif cls in KICKS:
			var bit := 1 if sd == "_l" else 2
			var lo := maxi(0, it["peak"] - int(LOOKBACK * FPS))
			var lift := -1
			for f in range(it["peak"], lo - 1, -1):
				if int(dn[f]) & bit:
					lift = f
					break
			if lift < 0:
				continue   # the kicking foot was never down in the second before: nothing left the floor to grade
			it.merge({"need": other, "role": "support", "bar": KICK_MIN, "when": "lift-off", "f": lift})
		else:
			continue
		if int(dn[it["f"]]) == 0:
			continue   # in the air at the measured moment: no foot to load (before the duplicate test, so it cannot evict one)
		# the same strike seen from two cards' windows: keep the faster
		var dup := -1
		for i in out.size():
			if absi(int(out[i]["peak"]) - int(it["peak"])) < int(PEAK_GAP * FPS):
				dup = i
		if dup >= 0:
			if float(out[dup]["speed"]) >= float(it["speed"]):
				continue
			out.remove_at(dup)
		var fr: int = it["f"]
		var d := int(dn[fr])
		var need_bit := 1 if it["need"] == "_l" else 2
		var share := 0.0
		if d == 3:
			S.apply(B, fr / FPS)
			var ls := TextView.left_share(B, Balance.com(B))
			share = ls if it["need"] == "_l" else 1.0 - ls
		else:
			share = 1.0 if d == need_bit else 0.0
		it["t"] = fr / FPS
		it["share"] = share
		out.append(it)
	S.stepped = was
	B.set_state(keep)
	B.fk()
	if main:
		if _memo.size() >= MEMO_MAX:
			_memo.clear()
		_memo[key] = out.duplicate(true)
	return out


static func _foot(sd: String) -> String:
	return "left" if sd == "_l" else "right"


static func _what(it: Dictionary) -> String:
	match String(it["class"]):
		"cross":
			return "the cross (%s hand)" % _foot(it["side"])
		"hook":
			return "the lead hook (%s hand)" % _foot(it["side"])
	return "the %s (%s leg)" % [it["class"], _foot(it["side"])]


static func _why(it: Dictionary) -> String:
	match String(it["role"]):
		"rear":
			return "a cross drives forward off the back foot"
		"lead":
			return "a lead hook turns over a loaded lead side"
	return "the support foot must hold him once the kicking leg leaves"


## Check's findings: one WARN per graded strike that starts under its bar. v = the share on the needed foot (0..1)
## sm: Rulebook's sample of this scene, when the caller has one: a scene holding a weapon in EVERY frame is skipped without
## sampling again (its strikes are weapon strikes, not graded; a kick with a weapon in hand is not graded either: stated)
static func findings(S: Scene, B: Body, sm := {}) -> Array:
	var out := []
	if sm.has("_raw") and not (sm["_raw"] as Array).is_empty() and (sm["_raw"] as Array).all(func(r): return bool(r.get("wep", false))):
		return out
	for it in strikes(S, B):
		if float(it["share"]) >= float(it["bar"]):
			continue
		var pc := roundi(float(it["share"]) * 100.0)
		var f := Rulebook._f("WARN", it["t"], "WEIGHT TRANSFER", "%.2f s: %s %s with %d %% of his weight on the %s (%s) foot and %d %% on the other; %s, so it wants %d %% or more there (the lever rule over the feet, N001)." % [
			it["t"], _what(it), "starts" if it["when"] == "start" else "lifts off", pc, it["role"], _foot(it["need"]), 100 - pc, _why(it), roundi(float(it["bar"]) * 100.0)], float(it["share"]))
		f.merge({"need": it["need"], "role": it["role"], "class": it["class"], "bar": it["bar"], "strike_card": it["card"], "when": it["when"]})
		out.append(f)
	return out


## the two footprints' centres on the floor (x, z), as TextView.left_share takes them; {} when a foot is up
static func _centres(B: Body) -> Dictionary:
	var cen := {}
	for sd in ["_l", "_r"]:
		var f := Balance.footprint(B, sd)
		if f.is_empty():
			return {}
		var lo := f[0]
		var hi := f[0]
		for q in f:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		cen[sd] = (lo + hi) * 0.5
	return cen


## the card the measured moment leaves from: the last card arrived at by then (its hold, or the move after it)
static func from_card(S: Scene, t: float) -> int:
	var ts := S.times()
	var j := -1
	for i in ts.size():
		if float(ts[i][1]) <= t + 1e-4:
			j = i
	return j


## the same strike again after an edit (same striking card, else the nearest peak)
static func _again(S: Scene, B: Body, f: Dictionary) -> Dictionary:
	var best := {}
	for it in strikes(S, B):
		if it["need"] != f["need"] or it["class"] != f["class"]:
			continue
		if best.is_empty() or absf(float(it["t"]) - float(f["t"])) < absf(float(best["t"]) - float(f["t"])):
			best = it
	return best


## the card pose `orig` with the hips moved by (dx, dz) along the floor and both feet put back where they stood (Body.plant:
## the ball on its mark, the foot pointing as it pointed; flat first, the heel let up if a flat foot cannot reach, as a
## pushing back foot does). If a leg still cannot reach, the hips sink 1 cm at a time (up to SINK_MAX): a weight shift
## bends the knees a little, as it does in people. Leaves the pose in B; returns the worst ball miss (m)
static func shift(B: Body, orig: Dictionary, dxz: Vector2, S: Scene = null) -> float:
	Scene.put(B, Moves._flat(orig))
	if S != null and S.on_floor:
		S._ground(B)
	B.fk()
	var fs := {}
	for sd in ["_l", "_r"]:
		fs[sd] = B.foot_state(sd)
	var base := B.offset + Vector3(dxz.x, 0.0, dxz.y)
	var miss := INF
	for k in int(SINK_MAX / 0.01) + 1:
		B.offset = base - Vector3(0.0, 0.01 * k, 0.0)
		B.fk()
		miss = 0.0
		for sd in ["_l", "_r"]:
			var e := B.plant(sd, fs[sd][0], fs[sd][1], true)
			if e > PLANT_TOL:
				e = B.plant(sd, fs[sd][0], fs[sd][1], false)
			miss = maxf(miss, e)
		if miss <= PLANT_TOL:
			break
	B.apply_grip()
	return miss


## THE FIX (Fixer.apply / propose call it): the hips of the card the strike starts from moved along the feet's line toward
## the needed foot (a pelvis offset, the feet re-planted where they stood), aiming at the bar + FIX_MARGIN; the strike is
## measured again as it plays and the aim raised by the shortfall, up to FIX_TRIES. {"did", "same" when nothing could be
## changed, "share0", "share1"}. Fixer re-checks the whole scene, keeps it or puts the cards back.
## (DragBalance, I24, was tried first: with both soles held flat its ankle limits stop the hips after ~10 points of share,
## measured on the guard stance, too little to turn a front-foot cross around; people let the unloaded heel rise.)
static func fix(f: Dictionary, S: Scene, B: Body) -> Dictionary:
	var j := from_card(S, float(f["t"]))
	if j < 0:
		return {"did": "no card before %.2f s to shift" % f["t"], "same": true}
	var need: String = f["need"]
	var other := "_r" if need == "_l" else "_l"
	var bar := float(f["bar"])
	var aim := bar + FIX_MARGIN
	var orig: Dictionary = S.cards[j]["pose"].duplicate(true)
	var keep := B.state()
	var s0 := float(f["v"])
	var s1 := s0
	var moved := 0.0
	var tries := 0
	var stop := ""
	var best := {}
	for k in FIX_TRIES:
		tries += 1
		Scene.put(B, Moves._flat(orig))
		if S.on_floor:
			S._ground(B)   # as it plays: the soles on the floor (a card stored 1-2 cm up still has its stance)
		B.fk()
		var cen := _centres(B)
		if cen.is_empty():
			stop = "card %d has a foot off the floor: there is no stance to shift" % (j + 1)
			break
		var d: Vector2 = (cen[need] as Vector2) - (cen[other] as Vector2)
		if d.length_squared() < 1e-6:
			stop = "the feet are together on card %d: no line to shift along" % (j + 1)
			break
		var c := Balance.com(B)
		var now := clampf((Vector2(c.x, c.z) - (cen[other] as Vector2)).dot(d) / d.length_squared(), 0.0, 1.0)
		var dxz := d * (minf(aim, SHARE_MAX) - now)
		var miss := shift(B, orig, dxz, S)
		if miss > PLANT_TOL:
			stop = "the legs cannot keep the feet planted that far (%.1f cm off)" % (miss * 100.0)
			break   # a shift that slides a foot is not kept; the best try so far (if any) stands
		S.cards[j]["pose"] = B.to_dict()
		var it := _again(S, B, f)
		var sh := float(it["share"]) if not it.is_empty() else -1.0
		if sh > s1:
			s1 = sh
			moved = dxz.length()
			best = S.cards[j]["pose"]
		if sh >= bar + FIX_GOAL or aim >= SHARE_MAX:
			break
		aim += maxf(0.05, bar + FIX_GOAL - sh)   # the move out of the card blends part of the shift away: aim higher
	B.set_state(keep)
	B.fk()
	if s1 <= s0 + 1e-3 or best.is_empty():
		S.cards[j]["pose"] = orig
		return {"did": "card %d: the weight could not be moved onto the %s foot%s" % [j + 1, _foot(need), (" (" + stop + ")") if stop != "" else ""], "same": true}
	S.cards[j]["pose"] = best
	return {"did": "card %d '%s': hips %.1f cm toward the %s foot, feet kept planted (%d tr%s); %s now %s with %d %% on it (was %d %%, wants %d %%)" % [
		j + 1, S.cards[j]["name"], moved * 100.0, _foot(need), tries, "y" if tries == 1 else "ies",
		"the strike" if f["when"] == "start" else "the kick", "starts" if f["when"] == "start" else "lifts off",
		roundi(s1 * 100.0), roundi(s0 * 100.0), roundi(bar * 100.0)], "share0": s0, "share1": s1, "card": j}
