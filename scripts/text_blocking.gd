## text_blocking.gd - TYPE A MOVE, GET BLOCKING (ROADMAP 22): "overhead axe strike, step in" -> a scene of key poses
## (cards) READY -> ANTICIPATION -> STRIKE -> FOLLOW-THROUGH -> RECOVERY, in scenes/_wip.
## RETRIEVE AND ADAPT (round 2 of this feature; the first solved every pose from scratch with IK and the hands missed by
## 9-52 cm): nothing is posed from scratch. Nick's saved scenes (scenes/*.json, read only) are real, already-good motion;
## an INDEX of their attack segments is built (index(): per strike the Check's own strike finder, Rulebook.strikes,
## finds the contact; the windup, follow-through and recovery cards around it; the tip path's direction: overhead /
## sweep left or right / thrust, from the swing plane at the peak; the step; the weapon). For a phrase the best segment
## is picked, then ADAPTED by the app's own operations only:
##   mirror     Scene.mirror_card (Mirror the scene), when the words want the other side
##   weapon     Body.set_kind + Body.weapon_to_hand (main._kind: the user picking another weapon); on a two-handed
##              weapon the second hand is put on the haft by Body.apply_grip, its place on the haft (the card's grip_m,
##              which playback slides between cards) chosen where the hand reaches, the palm fitted onto the shaft's
##              axis (Body.fit_hand); if it still misses, both arms searched together (Body.hold_bat, the drag's path,
##              from the arms as they are); then the hold is LOCKED (Body.capture_second, the Lock both hands button:
##              the card carries the hand's place and turn on the shaft, and the plant and the play re-fit to it)
##   step       the card's "steps" entry (what Nick's own step cards carry) + Scene.pin_cards (the leg re-planted); the
##              hips follow the step by the share Nick's own step cards show
##   timing     Scene.retime (the Faster / Slower op) to the weapon's row of docs/ATTACK_RULES.md, speed words scaling
##              the anticipation and recovery; then the same op again on whichever part holds the trouble until the
##              peak sits inside the strike under the weapon's cap, no joint turns faster than it did in the source,
##              and the Check has no new HEAD QUIET / TIP SPEED / FIST SPEED, nor a SEQUENCE the timing made (the
##              wind-up sped to the row until the weapon turned fastest in it, or a second strike in the recovery)
##   balance    a card whose re-planted feet leave the centre of mass past them (the source's did not): the hips moved
##              over the feet (the BALANCE rule's own advice, the card's offset), the feet re-pinned
##   intensity  "heavy": the strike card's ease "in" (the EASE PRESETS)
## Where no saved segment fits the status SAYS so: "no saved thrust to start from: blocked from the closest, a jab". A word
## the lexicon does not know is listed back, not guessed at.
## PUNCHES AND KICKS are not retrieved: scenes/ has none, and adapting the closest (a bat thrust with the bat taken away
## for a jab) gave a wrong move (N016's recognizer named it). Those words go to StrikeBlocking (strike_blocking.gd), which
## generates the key poses and times them to the cited human speeds. (A staff / spear thrust is still retrieved: a
## dagger's thrust with the staff swapped in, which arcs like a swing; see strike_blocking.gd's header.)
## build(text, B) -> {ok, error} | {ok, scene, source, status, notes, unknown, grip (m per card), peak, peak_t, window,
## cap, must_fix_new, human_new, ...}. B is posed as a side effect; nothing is written here (save() writes where told).
class_name TextBlocking
extends RefCounted

const AT := preload("res://tools/attack_timing.gd")

## word -> the weapon's Body.KINDS name ("" = no weapon: a fist)
const WEAPON := {"axe": "long_axe", "hatchet": "long_axe", "bat": "metal_bat", "staff": "staff", "bo": "staff",
	"hammer": "long_hammer", "sledge": "long_hammer", "dagger": "dagger", "knife": "dagger", "sword": "sword", "longsword": "longsword",
	"katana": "katana", "spear": "spear", "lance": "spear",
	"fist": "", "fists": "", "hand": ""}
## word -> the attack shape
const ATTACK := {"overhead": "overhead", "downward": "overhead", "down": "overhead", "chop": "overhead",
	"horizontal": "sweep", "sweep": "sweep", "swing": "sweep", "cut": "sweep", "slash": "sweep", "arc": "sweep",
	"thrust": "thrust", "stab": "thrust", "poke": "thrust", "jab": "jab", "punch": "jab", "straight": "jab",
	"uppercut": "uppercut", "hook": "hook", "backhand": "sweep", "forehand": "sweep",
	"cross": "cross", "roundhouse": "roundhouse", "kick": "front kick", "teep": "front kick"}
## two words -> the attack (StrikeBlocking generates these: no saved scene has one)
const ATTACK2 := {"front kick": "front kick", "push kick": "front kick", "side kick": "side kick", "round kick": "roundhouse",
	"round house": "roundhouse", "roundhouse kick": "roundhouse", "turning kick": "roundhouse"}
## word -> which hand / leg of the stance strikes (StrikeBlocking.side_of)
const LEAD := {"lead": "lead", "front": "lead", "rear": "rear", "back": "rear"}
## word -> the side the swing ENDS on: "left" = his left (+x, where swing_fore's forehand lands), "right" = his right
const SIDE := {"left": "left", "right": "right", "forehand": "left", "backhand": "right"}
## phrase -> footwork ("in" = the lead foot steps forward, "back" = it steps back, "lunge" = a long step forward)
const FOOT := {"step in": "in", "step forward": "in", "step back": "back", "lunge": "lunge", "stand": "stand",
	"stand still": "stand", "pivot": "pivot"}
const SPEED := {"fast": "fast", "quick": "fast", "light": "light", "heavy": "heavy", "slow": "slow"}
## speed -> [anticipation factor, recovery factor]
const SPEED_F := {"fast": [0.7, 0.8], "light": [0.8, 0.8], "heavy": [1.3, 1.3], "slow": [1.6, 1.6]}
const FILLER := ["a", "an", "the", "with", "at", "to", "and", "then", "his", "her", "my", "of", "on", "it", "strike",
	"attack", "move", "hit", "blow", "from", "in", "back"]
## Body kind -> its docs/ATTACK_RULES.md row (AT.RULES key); thrusts use the spear row for timing
const ROW := {"dagger": "knife", "metal_bat": "metal_bat", "staff": "staff", "long_axe": "hammer", "long_hammer": "hammer",
	"sword": "metal_bat", "longsword": "metal_bat", "katana": "metal_bat", "spear": "spear"}   # a blade swings like the bat row
## kinds held in two hands on the haft, and where on it the top hand may hold (m from the butt): the search range
const TWO := ["long_axe", "long_hammer", "staff", "longsword", "katana", "spear"]
const HAFT := {"long_axe": [0.1, 0.6], "long_hammer": [0.1, 0.6], "staff": [0.3, 1.3], "longsword": [0.04, 0.12], "katana": [0.04, 0.10], "spear": [0.6, 1.4]}
const STEP := {"in": 0.25, "back": -0.2, "lunge": 0.4}   # m along the body's front (+z), for the lead foot
const HIPS_PER_STEP := 0.45   # the hips follow a step this much of its length (combo3's STRIKE: 17 cm for a 38 cm step)
const REST := 0.2             # s: a card that holds this long is a rest (the ready or the recovery), not part of a swing
const BUDGET_FPS := 30.0      # the strike budget in ATTACK_RULES is in 30 fps frames
const SAFE := 0.95            # the tip may peak at this share of its cap
const GRIP_OK := 0.02         # m: the free hand this close to its grip spot holds the haft
const THRUST_HOLD := 0.6      # m: a two-hand thrust holds the haft a spear's way, the top hand this far up from the butt
const BAL_IN := 0.01          # m: the hips moved until the centre of mass is this far inside the feet
const LOOPS := 10             # retimes at most, after the rows' timing
## the Check's must-fixes that more time cures (SEQUENCE: only when the weapon's fastest turn is in the wind-up, or
## the finding is a second strike outside the strike card)
const RETIME_RULES := ["HEAD QUIET", "TIP SPEED", "FIST SPEED", "SEQUENCE"]
## a shape no saved segment has starts from the nearest one that exists, in this order
const CLOSEST := {"uppercut": ["thrust", "overhead", "sweep"], "thrust": ["overhead", "sweep"], "overhead": ["sweep", "thrust"],
	"sweep": ["overhead", "thrust"]}
const PASS_BY := ["fix (skin)", "pass-by"]   # clearance cards Fix added to a scene: not key poses, left out of a blocking

static var _idx := []   # index() once per run


static func _mid(r: Array) -> float:
	return (float(r[0]) + float(r[1])) * 0.5


## the words -> {ok, error | weapon, kind, attack, side, foot, speed, unknown: [words], notes: [...]}
static func parse(text: String) -> Dictionary:
	var clean := text.to_lower()
	for ch in [",", ".", ";", ":", "-", "/", "(", ")", "!", "?", "\""]:
		clean = clean.replace(ch, " ")
	var words: Array = clean.split(" ", false)
	var out := {"ok": false, "error": "", "weapon": "", "kind": "", "attack": "", "side": "", "foot": "", "speed": "",
		"unknown": [], "notes": [], "lead": ""}
	var weapon_word := ""
	var i := 0
	while i < words.size():
		var w: String = words[i]
		var nxt: String = words[i + 1] if i + 1 < words.size() else ""
		if ATTACK2.has(w + " " + nxt):
			out["attack"] = ATTACK2[w + " " + nxt]
			i += 2
			continue
		var nxt2: String = (nxt + " " + words[i + 2]) if i + 2 < words.size() else ""
		if LEAD.has(w) and w != "back" and nxt != "" and (ATTACK.has(nxt) or ATTACK2.has(nxt2) or nxt in ["hand", "leg"]):
			out["lead"] = LEAD[w]   # "rear hook", "lead uppercut" ("back" stays footwork: "step back")
			i += 1
			continue
		if FOOT.has(w + " " + nxt):
			out["foot"] = FOOT[w + " " + nxt]
			i += 2
			continue
		if FOOT.has(w):
			out["foot"] = FOOT[w]
		elif WEAPON.has(w):
			weapon_word = w
		elif SIDE.has(w) and ATTACK.has(w):   # forehand / backhand: a sweep AND its side
			out["side"] = SIDE[w]
			if String(out["attack"]) == "":
				out["attack"] = ATTACK[w]
		elif ATTACK.has(w):
			out["attack"] = ATTACK[w]
		elif SIDE.has(w):
			out["side"] = SIDE[w]
		elif SPEED.has(w):
			out["speed"] = SPEED[w]
		elif not FILLER.has(w):
			(out["unknown"] as Array).append(w)
		i += 1
	if weapon_word != "":
		out["weapon"] = weapon_word
		out["kind"] = WEAPON[weapon_word]
		if weapon_word == "sword":
			(out["notes"] as Array).append("sword: no sword kind yet, the metal bat's length and grip are used")
		if weapon_word == "knife":
			(out["notes"] as Array).append("knife: the dagger kind is used (the short blade)")
	if String(out["attack"]) == "":
		out["error"] = "no attack in it: say overhead, sweep, thrust, jab, cross, hook, uppercut, front kick, roundhouse or side kick"
		return out
	out["ok"] = true
	return out


## the shape the segments are classed by: a jab is a thrust (of the fist or the weapon), a hook a sweep; an uppercut
## stays an uppercut (no saved one exists: the pick says so and starts from the closest)
static func _shape(attack: String) -> String:
	return {"jab": "thrust", "hook": "sweep"}.get(attack, attack)


static func _pass_by(name: String) -> bool:
	for p in PASS_BY:
		if name.begins_with(p):
			return true
	return false


static func _is_return(name: String) -> bool:
	var n := name.to_lower()
	for w in ["recover", "ready", "guard", "catch", "rest", "stand"]:
		if n.contains(w):
			return true
	return false


static func _hand_of(S: Scene, i: int) -> String:
	var w: Dictionary = (S.cards[i]["pose"] as Dictionary).get("weapon", {})
	return String(w.get("hand", "")) if not w.is_empty() else ""


## THE INDEX: every attack segment in scenes/*.json (read only). Per strike the Check finds (Rulebook.strikes on the
## tip's 60 fps speed): {scene, kind, two, ready, windup: [i..], strike, ft: [i..], recovery (-1 = none: the ready
## again), dropped: [names], dir, side, step: {sd: Vector3}, peak, cards (the scene's card count), feat}. A strike
## whose contact card is a clearance pass-by, a return to guard, or has the weapon out of the hands (a staff caught in
## the air) is not an attack segment. Built once per run.
static func index(B: Body) -> Array:
	if not _idx.is_empty():
		return _idx
	var out := []
	var files := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json") and not f.get_basename() in AT.NOT_ATTACKS:
			files.append(f)
	files.sort()
	for f in files:
		var S := Scene.new()
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f))
		if not (d is Dictionary and (d as Dictionary).has("cards")):
			continue
		S.from_dict(d)
		if S.cards.size() < 3:
			continue
		var sm := Rulebook.sample(S, B)
		var ts := S.times()
		var n := S.cards.size()
		for st in Rulebook.strikes(sm["tip"]):
			var pk: int = st["pk"]
			var t_pk: float = sm["t"][pk]
			var c := S.span(t_pk)
			if c < 0:
				c = Rulebook.card_at(S, t_pk)
			if c <= 0:
				continue
			var cname := String(S.cards[c]["name"])
			var hand := _hand_of(S, c)
			var armed: bool = not (S.cards[c]["pose"] as Dictionary).get("weapon", {}).is_empty()
			if _pass_by(cname) or _is_return(cname) or (armed and hand == ""):
				continue
			# the windup: back from the contact to the last rest (a hold of REST or more) or the first card
			var windup := []
			var i := c - 1
			while i > 0 and float(S.cards[i]["hold"]) < REST:
				if not _pass_by(String(S.cards[i]["name"])):
					windup.push_front(i)
				i -= 1
			# after the contact: the cards to the first rest; the last of them is the recovery if it is named a return
			# (recover / guard / catch...), else it is a follow-through and the ready is the recovery. A return card right
			# after that rest, if it is the scene's last, is the recovery (combo3's "recover" after its follow-through's hold)
			var tail := []
			i = c + 1
			while i < n:
				if not _pass_by(String(S.cards[i]["name"])):
					tail.append(i)
				if float(S.cards[i]["hold"]) >= REST:
					break
				i += 1
			var ft := []
			var rec := -1
			if not tail.is_empty():
				if _is_return(String(S.cards[tail[-1]]["name"])):
					rec = tail[-1]
					ft = tail.slice(0, tail.size() - 1)
				else:
					ft = tail
					if tail[-1] + 1 == n - 1 and _is_return(String(S.cards[n - 1]["name"])):
						rec = n - 1
			# a card with the weapon out of the hand (let go, caught later) cannot follow a card with it in the hand: the
			# weapon would jump to the free hand mid-move (bo_sweep's catch). Left out, and said.
			var dropped := []
			if armed:
				var keep := []
				for k in ft:
					if _hand_of(S, k) == hand:
						keep.append(k)
					else:
						dropped.append(String(S.cards[k]["name"]))
				ft = keep
				if rec >= 0 and _hand_of(S, rec) != hand:
					dropped.append(String(S.cards[rec]["name"]))
					rec = -1
			# the direction, from the tip path: thrust = at the peak the tip moves along the weapon; else the swing
			# plane through the windup's end, the peak and the contact: a sideways normal = overhead (an uppercut when
			# the tip rises), an upright normal = a sweep, whose side is where the tip ends
			var raw: Array = sm["_raw"]
			var fr := func(t: float) -> int: return clampi(int(round(t * Rulebook.FPS)), 0, raw.size() - 1)
			var a_t: float = ts[windup[-1]][1] if not windup.is_empty() else ts[0][2]
			var pa: Vector3 = raw[fr.call(a_t)]["tip"]
			var pm: Vector3 = raw[pk]["tip"]
			var pb: Vector3 = raw[fr.call(ts[c][1])]["tip"]
			var v: Vector3 = (raw[mini(pk + 1, raw.size() - 1)]["tip"] as Vector3) - (raw[maxi(pk - 1, 0)]["tip"] as Vector3)
			var vh := v.normalized()
			var along := absf((raw[pk]["wd"] as Vector3).normalized().dot(vh)) if armed else 0.0
			var nrm := (pm - pa).cross(pb - pm)
			var plane := nrm.normalized() if nrm.length() > 1e-6 else Vector3.ZERO
			var dir := "sweep"
			if armed and along > 0.6:
				dir = "thrust"
			elif absf(plane.x) >= 0.6:
				dir = "uppercut" if vh.y > 0.5 else "overhead"
			var side := "left" if pb.x - pa.x > 0.0 else "right"
			if dir != "sweep":
				side = ""
			var w: Dictionary = S.cards[c]["pose"].get("weapon", {})
			out.append({"scene": "scenes/" + f, "kind": String(w.get("kind", "")) if not w.is_empty() else "", "hand": hand,
				"two": bool(w.get("two_hand_grip", false)), "ready": 0, "windup": windup, "strike": c, "ft": ft, "recovery": rec,
				"dropped": dropped, "dir": dir, "side": side, "step": S._steps(c), "peak": float(sm["tip"][pk]), "cards": n,
				"feat": {"along": snappedf(along, 0.01), "plane": [snappedf(plane.x, 0.01), snappedf(plane.y, 0.01), snappedf(plane.z, 0.01)],
					"v": [snappedf(vh.x, 0.01), snappedf(vh.y, 0.01), snappedf(vh.z, 0.01)], "dx": snappedf(pb.x - pa.x, 0.01),
					"t_pk": snappedf(t_pk, 0.001)}})
	_idx = out
	return out


## one line per index entry, for the test's print and the research doc
static func describe(e: Dictionary) -> String:
	return "%-22s %-10s %-8s %-5s strike %2d (windup %s, ft %s, rec %2d%s) step %s peak %5.1f m/s  plane %s v %s along %.2f" % [
		e["scene"], e["kind"] if e["kind"] != "" else "(fist)", e["dir"], e["side"], e["strike"], str(e["windup"]), str(e["ft"]), e["recovery"],
		(", dropped " + str(e["dropped"])) if not (e["dropped"] as Array).is_empty() else "",
		"yes" if not (e["step"] as Dictionary).is_empty() else "no", e["peak"], str(e["feat"]["plane"]), str(e["feat"]["v"]), e["feat"]["along"]]


## the best segment for the words: {entry, mirror, shape (the shape it has), notes}. Lower cost wins: the shape (a
## missing shape takes the CLOSEST shape that exists), the weapon (same kind 0, same hand count 2, else 3), the side
## (a sweep the words want on the other side is mirrored: 1), a long windup (0.1 a card), a real recovery card
## (-0.5), a saved peak over the weapon's own cap (the Check's TIP SPEED on the source: 2 per multiple over)
static func pick(idx: Array, kind: String, shape: String, side: String) -> Dictionary:
	var have := {}
	for e in idx:
		have[e["dir"]] = true
	var want := shape
	var notes := []
	if not have.has(want):
		for alt in CLOSEST.get(shape, []):
			if have.has(alt):
				want = alt
				break
		if want == shape:
			return {"entry": {}, "mirror": false, "shape": shape, "notes": ["no saved attack segment at all: nothing to start from"]}
	var best := {}
	var best_cost := INF
	var best_mirror := false
	var armed := kind != ""
	for e in idx:
		if e["dir"] != want:
			continue
		var cost := 0.0
		var ek: String = e["kind"]
		if ek != kind:
			var e_two: bool = TWO.has(ek)
			var w_two: bool = TWO.has(kind)
			cost += 2.0 if (armed and e_two == w_two) or (not armed and not e_two) else 3.0
		var mir := false
		if want == "sweep" and side != "" and e["side"] != side:
			mir = true
			cost += 1.0
		cost += 0.1 * (e["windup"] as Array).size()
		if int(e["recovery"]) >= 0:
			cost -= 0.5
		if ek != "" and ROW.has(ek):
			cost += 2.0 * maxf(0.0, float(e["peak"]) / float(AT.TIP_MAX[ROW[ek]]) - 1.0)
		if cost < best_cost:
			best_cost = cost
			best = e
			best_mirror = mir
	var scene := String(best["scene"])
	var what := "%s %s" % [best["kind"].replace("_", " ") if best["kind"] != "" else "unarmed", best["dir"]]
	if want != shape:
		notes.append("no saved %s to start from: blocked from the closest, Nick's %s (%s)%s" % [shape, what, scene,
			" with the weapon taken away" if not armed and best["kind"] != "" else (" with the %s swapped in" % kind.replace("_", " ")) if armed and best["kind"] != kind else ""])
	elif not armed and best["kind"] != "":
		notes.append("no saved punch to start from: blocked from Nick's %s (%s) with the weapon taken away" % [what, scene])
	elif armed and best["kind"] != kind:
		notes.append("no saved %s %s: blocked from Nick's %s (%s) with the %s swapped in" % [kind.replace("_", " "), shape, what, scene, kind.replace("_", " ")])
	else:
		notes.append("blocked from Nick's %s (%s)" % [what, scene])
	if best_mirror:
		notes.append("mirrored (Mirror the scene, card by card): the saved one ends on his %s, the words say %s" % [best["side"], side])
	if not (best["dropped"] as Array).is_empty():
		notes.append("left out of the saved move: %s (the weapon leaves the hand there; it would jump mid-move)" % ", ".join(best["dropped"]))
	return {"entry": best, "mirror": best_mirror, "shape": want, "notes": notes}


## a card of the source scene, for the blocking: a deep copy of the card as Scene.from_dict holds it (the file form of
## its steps), mirrored by the app's op when asked. M: a scratch body for the mirror
static func _card(S: Scene, i: int, role: String, mirror: bool, M: Body) -> Dictionary:
	var c: Dictionary = (S.cards[i] as Dictionary).duplicate(true)
	if mirror:
		c = Scene.mirror_card(c, M)
	c["name"] = ("%s: %s" % [role, S.cards[i]["name"]]) if role != "" else String(S.cards[i]["name"])
	return c


## the segment's cards as a scene at the source's own timing (the baseline the Check is compared against, and the
## cards the blocking starts from). The move into a kept card is the time the source takes from the kept card before
## it (the clearance cards between are left out, their time is not). roles: parallel list of role names
static func _segment(e: Dictionary, mirror: bool, M: Body) -> Dictionary:
	var S0 := Scene.new()
	S0.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + String(e["scene"]))))
	var S := Scene.new()
	S.fps = S0.fps
	S.natural = S0.natural
	var kept := [[int(e["ready"]), "ready"]]
	for i in e["windup"]:
		kept.append([int(i), "anticipation"])
	kept.append([int(e["strike"]), "strike"])
	for i in e["ft"]:
		kept.append([int(i), "follow-through"])
	if int(e["recovery"]) >= 0:
		kept.append([int(e["recovery"]), "recovery"])
	var roles := []
	for k in kept.size():
		var i: int = kept[k][0]
		var role: String = kept[k][1]
		var c := _card(S0, i, "STRIKE" if role == "strike" else role, mirror, M)
		if k == 0:
			c["name"] = "ready"
			c["move"] = -1.0
			c["hold"] = maxf(float(c["hold"]), 0.3)
			c.erase("steps")
		else:
			# its own move, plus the clearance cards' time right before it (the source's attacks before this one, when
			# the ready is not its neighbour, add nothing: the kept card keeps its own move)
			var mv := S0.move_time(i)
			var j := i - 1
			while j > kept[k - 1][0] and _pass_by(String(S0.cards[j]["name"])):
				mv += S0.move_time(j) + float(S0.cards[j]["hold"])
				j -= 1
			c["move"] = snappedf(mv, 0.001)
		S.cards.append(c)
		roles.append(role)
	if int(e["recovery"]) < 0:
		var r: Dictionary = (S.cards[0] as Dictionary).duplicate(true)
		r["name"] = "recovery"
		r["move"] = 0.5
		r["hold"] = 0.3
		S.cards.append(r)
		roles.append("recovery")
	return {"scene": S, "roles": roles, "src": S0}


static func _strike_of(roles: Array) -> int:
	return roles.find("strike")


## the free palm's distance from the shaft's axis (m), the number Lock both hands reads to say the hand is on the shaft
## (Body.capture_second's `off`, computed without capturing); past either end of the shaft, the distance past it if
## larger. 0 with no second hand.
static func palm_off(B: Body) -> float:
	if not (B.wep_on and B.grip and B.wep_hand != ""):
		return 0.0
	var o := "hand_l" if B.wep_hand == "hand_r" else "hand_r"
	var x := B.wep_xform()
	var pl: Vector3 = (x[1] as Quaternion).inverse() * (B.palm_point(o) - (x[0] as Vector3))
	var off := Vector2(pl.x, pl.z).length()
	if pl.y < 0.0:
		off = maxf(off, -pl.y)
	elif pl.y > B.wep_len:
		off = maxf(off, pl.y - B.wep_len)
	return off


## the free palm onto the shaft's axis, the app's fitter (Body.fit_hand, the op Lock both hands' _fit_second runs) with
## the hand's turn kept: the last centimetres apply_grip's two-joint reach stops short of (a limit or the body in the
## way). Tried where the palm is along the shaft, then up to 10 cm either way (inside HAFT); the closest kept.
## Returns the palm's distance from the axis (m) after it
static func _palm_fit(B: Body, kind: String) -> float:
	var o := "hand_l" if B.wep_hand == "hand_r" else "hand_r"
	var x := B.wep_xform()
	var q: Quaternion = x[1]
	var knob: Vector3 = x[0]
	var u_now: float = (q.inverse() * (B.palm_point(o) - knob)).y
	var r: Array = HAFT[kind]
	var lo := minf(float(r[0]), u_now)
	var hi := minf(maxf(float(r[1]), u_now), B.wep_len)
	var keep := B.ang.duplicate()
	var best := palm_off(B)
	var won := keep
	for du in [0.0, 0.05, -0.05, 0.1, -0.1]:
		if best <= GRIP_OK * 0.5:   # within _fit_second's own 1 cm: held (each fit is a whole-arm search, ~0.4 s)
			break
		var u := clampf(u_now + du, lo, hi)
		B.ang = keep.duplicate()
		B.fk()
		var target: Vector3 = knob + q * Vector3(0, u, 0) + ((B.P[o] as Vector3) - B.palm_point(o))
		B.fit_hand(o, target, B.G[o])
		var p := palm_off(B)
		if p < best - 1e-4:
			best = p
			won = B.ang.duplicate()
	B.ang = won
	B.fk()
	return best


## the free hand onto the haft, the app's way. A card Nick saved with Lock both hands keeps its own lock when the
## weapon is his and the hand still holds. Else: apply_grip reaches the wrist to its spot, the top hand's place on
## the haft (grip_u, the card's grip_m) searched over the handle where the kind's default misses (a real axe or
## hammer swing slides the top hand down the haft at the strike); the palm fitted onto the axis from there
## (_palm_fit). Still off: both arms searched together (hold_bat, the drag's solver, both its starts), the weapon's
## line weighted 0.5 then 0.25 per radian, the palm fitted again; the hold with the palm closest to the axis is kept.
## Then the hold is LOCKED (Body.capture_second, the Lock both hands button): the card carries the second hand's
## place and turn on the shaft, and every apply_grip from here (the plant, the play) re-fits the hand to that spot
## instead of reaching for the default. Returns {miss (m, grip_miss: 0 when locked), palm (m, palm_off), aim (deg the
## weapon's line turned), moved (m the bat hand moved), kept (Nick's own lock)}
static func _hold_two(B: Body, kind: String, u0: float, swap: bool) -> Dictionary:
	var h := B.wep_hand
	var o := "hand_l" if h == "hand_r" else "hand_r"
	B.grip = true
	if not swap and not B.grip2.is_empty() and String(B.grip2.get("hand", "")) == o:
		B.apply_grip()
		if B.grip_miss() <= GRIP_OK and palm_off(B) <= GRIP_OK:
			return {"miss": B.grip_miss(), "palm": palm_off(B), "aim": 0.0, "moved": 0.0, "kept": true}
	B.grip2 = {}
	var keep := B.ang.duplicate()
	var try_u := func(u: float) -> float:
		B.grip_u = u
		B.apply_grip()
		var m := B.grip_miss()
		B.ang = keep.duplicate()
		B.fk()
		return m
	var best_u := u0
	var best: float = try_u.call(u0)
	if best > GRIP_OK:
		var r: Array = HAFT[kind]
		var u: float = r[0]
		while u <= float(r[1]) + 1e-6:
			var m: float = try_u.call(u)
			if m < best - 1e-4:
				best = m
				best_u = u
			u += 0.05
	B.grip_u = best_u
	B.apply_grip()
	var at: Vector3 = B.P[h]
	var ax := B.wep_axis()
	var start := B.ang.duplicate()
	var won := start
	var out := {"miss": INF, "palm": INF, "aim": 0.0, "moved": 0.0, "kept": false}
	for dw in [NAN, 0.5, 0.25]:   # NAN: the hold as apply_grip left it, the bat hand where Nick had it
		B.ang = start.duplicate()
		B.fk()
		if not is_nan(dw):
			B.hold_bat(at, ax, true, true, NAN, 15.0, false, dw)
			B.apply_grip()
		var p := _palm_fit(B, kind)
		var m := (B.P[o] as Vector3).distance_to(B.grip_wrist())
		if p < float(out["palm"]) - 1e-4 or (absf(p - float(out["palm"])) <= 1e-4 and m < float(out["miss"])):
			out = {"miss": m, "palm": p, "aim": rad_to_deg(B.wep_axis().angle_to(ax)), "moved": ((B.P[h] as Vector3) - at).length(), "kept": false}
			won = B.ang.duplicate()
		if p <= GRIP_OK * 0.5:
			break
	B.ang = won
	B.fk()
	B.capture_second()   # the lock; nothing captured when the palm is still over 5 cm off (the default reach stays)
	out["miss"] = B.grip_miss()
	out["palm"] = palm_off(B)
	return out


## a card's pose with the words' weapon in the hand: swapped the way the user picks another weapon (main._kind:
## Body.set_kind, then Body.weapon_to_hand in the hand it is in) when the kind differs; "" = the weapon taken away and
## the hands made fists; a two-handed kind holds with both hands on every card (_hold_two). Returns the pose and the
## card's grip miss (m; 0 one-handed)
static func _arm(B: Body, pose: Dictionary, kind: String, thrust: bool, swap: bool) -> Dictionary:
	B.grip2 = {}
	B.from_dict(pose)
	var out := {"miss": 0.0, "palm": 0.0, "aim": 0.0, "moved": 0.0}
	if kind == "":
		B.wep_on = false
		B.grip = false
		B.hand_shape("r", "fist")
		B.hand_shape("l", "fist")
		out["pose"] = B.to_dict()
		return out
	var h := B.wep_hand if B.wep_on and B.wep_hand != "" else "hand_r"
	if swap:
		B.set_kind(kind)
		B.weapon_to_hand(h)
		B.grip2 = {}
	if TWO.has(kind):
		var u0: float = B.grip_u
		if thrust and swap:
			u0 = THRUST_HOLD   # a spear's hold: the butt hand where it is, the top hand THRUST_HOLD up the haft
		out = _hold_two(B, kind, u0, swap)
	else:
		B.grip = false
	out["pose"] = B.to_dict()
	return out


## the words' footwork on the strike card: the lead foot's "steps" entry (the app's own step record; the hips follow
## HIPS_PER_STEP of it), the recovery stepping back by the same. Returns a note, or ""
static func _footwork(S: Scene, roles: Array, foot: String, mirror: bool) -> String:
	var s := _strike_of(roles)
	var c: Dictionary = S.cards[s]
	var st: Dictionary = S._steps(s)
	if foot == "pivot":
		return "pivot: the turn of the feet is not built yet, the stance is kept"
	if foot == "stand":
		if st.is_empty():
			return ""
		c.erase("steps")
		for k in range(s + 1, S.cards.size()):
			S.cards[k].erase("steps")
		return "stand still: the saved step (%.0f cm) taken out, the feet stay" % [(st.values()[0] as Vector3).length() * 100.0]
	if not STEP.has(foot):
		return ""
	var d: float = STEP[foot]
	var lead := "_l"
	var have := Vector3.ZERO
	if not st.is_empty():
		lead = st.keys()[0]
		have = st[lead]
	elif mirror:
		lead = "_r"
	if foot == "in" and have.z >= 0.1:
		return "the saved move already steps in %.0f cm on the strike: kept" % (have.z * 100.0)
	var step := Vector3(have.x, 0.0, d)
	c["steps"] = {lead: [step.x, step.y, step.z]}
	var dz := (step.z - have.z) * HIPS_PER_STEP
	for k in range(s, S.cards.size() - 1):   # the strike and its follow-through stand on the new foot: the hips go with it
		if roles[k] == "recovery":
			break
		var p: Dictionary = S.cards[k]["pose"]
		var o: Array = p.get("offset", [0, 0, 0])
		p["offset"] = [float(o[0]), float(o[1]), float(o[2]) + dz]
	var r: Dictionary = S.cards[-1]
	r["steps"] = {lead: [-step.x, -step.y, -step.z]}
	var words := {"in": "steps in", "back": "steps back", "lunge": "lunges"}
	return "the lead foot %s %.0f cm on the strike (the card's steps, the leg re-planted; the hips %.0f cm with it) and comes back on the recovery" % [words[foot], absf(d) * 100.0, dz * 100.0]


## retime a..b (inclusive) so the moves and holds in it sum to `target` s (Scene.retime, the Faster / Slower op)
static func _retime_to(S: Scene, a: int, b: int, target: float, skip_last_hold := false) -> float:
	if a > b or a < 1:
		return 1.0
	var now := 0.0
	for i in range(a, b + 1):
		now += S.move_time(i) + (0.0 if (skip_last_hold and i == b) else float(S.cards[i]["hold"]))
	if now <= 1e-6:
		return 1.0
	var pct := clampf(target / now * 100.0, 10.0, 1000.0)
	S.retime(a, b, pct)
	return pct / 100.0


## the fastest frame over the keys: [speed, time]
static func _peak(sm: Dictionary, keys: Array) -> Array:
	var best := 0.0
	var at := 0.0
	for key in keys:
		var v: Array = sm[key]
		for i in v.size():
			if float(v[i]) > best:
				best = float(v[i])
				at = float(sm["t"][i])
	return [best, at]


## findings keyed for the "nothing NEW vs the source" comparison: rule, plus the joint for JOINT SPEED
static func _key(f: Dictionary) -> String:
	return String(f["rule"]) + ("|" + String(f["joint"]) if f.has("joint") else "")


static func _counts(fs: Array, sev := "") -> Dictionary:
	var out := {}
	for f in fs:
		if sev != "" and f["sev"] != sev:
			continue
		out[_key(f)] = int(out.get(_key(f), 0)) + 1
	return out


## the findings of `got` that the source did not have (by key, one for one)
static func _new(src: Array, got: Array, sev := "") -> Array:
	var have := _counts(src, sev)
	var out := []
	for f in got:
		if sev != "" and f["sev"] != sev:
			continue
		var k := _key(f)
		if int(have.get(k, 0)) > 0:
			have[k] = int(have[k]) - 1
		else:
			out.append(f)
	return out


static func _words_of(fs: Array) -> Array:
	return fs.map(func(f): return "%s%s at %.2f s" % [f["rule"], (" (" + String(f["joint"]).replace("_", " ") + ")") if f.has("joint") else "", f["t"]])


## the balance of a card's pose as HumanLimits reads it (Balance.read, after apply_grip): the margin (m, + inside)
static func _margin(B: Body, pose: Dictionary) -> Dictionary:
	B.grip2 = {}
	B.from_dict(pose)
	B.apply_grip()
	return Balance.read(B)


## the closest point of the support polygon to q (floor, x/z)
static func _onto(poly: PackedVector2Array, q: Vector2) -> Vector2:
	var best := q
	var d := INF
	if poly.size() < 3:
		for v in poly:
			if q.distance_to(v) < d:
				d = q.distance_to(v)
				best = v
		return best
	for i in poly.size():
		var p := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(p) < d:
			d = q.distance_to(p)
			best = p
	return best


## the blocking. {ok, error} when the words have no attack; else the scene and everything the test grades.
static func build(text: String, B: Body) -> Dictionary:
	var P: Dictionary = parse(text)
	if not P["ok"]:
		return P
	var gen := StrikeBlocking.move_of(P)
	if gen != "":
		return StrikeBlocking.build(P, B, gen, text)   # no saved punch or kick exists: generated key poses
	var kind: String = P["kind"]
	var armed := kind != ""
	var two := armed and TWO.has(kind)
	var shape: String = _shape(P["attack"])
	var side: String = P["side"]
	if P["attack"] == "hook" and side == "":
		side = "left"   # a right-hander's hook comes across to his left
	var notes: Array = P["notes"].duplicate()
	var idx := index(B)
	var pk := pick(idx, kind, shape, side)
	notes += pk["notes"]
	var e: Dictionary = pk["entry"]
	if e.is_empty():
		return {"ok": false, "error": pk["notes"][0]}
	var built_shape: String = pk["shape"]
	var row := "knife"
	if armed:
		row = "spear" if built_shape == "thrust" else String(ROW[kind])
	var cap: float = Rulebook.FIST_WARN
	var cap_name := "fist (Rulebook.FIST_WARN)"
	if armed:
		cap = minf(float(AT.TIP_MAX[row]), float(AT.TIP_MAX[ROW[kind]]))
		cap_name = "%s tip (docs/ATTACK_RULES.md)" % (row if AT.TIP_MAX[row] <= AT.TIP_MAX[ROW[kind]] else ROW[kind])
	var keys := ["tip"] if armed else ["hand_l", "hand_r"]   # unarmed: either hand's end, what the FIST SPEED rule reads
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	# THE SOURCE SEGMENT as it is (the baseline): its Check, human limits and balance per card
	var seg0 := _segment(e, false, M)
	var S0: Scene = seg0["scene"]
	S0.name = "src_" + slug(text)
	var src_fs: Array = Rulebook.check(S0, B)
	var src_human: Array = HumanLimits.findings(S0, B)
	var src_margin := []
	for c in S0.cards:
		src_margin.append(float(_margin(B, c["pose"])["margin"]))
	# THE BLOCKING: the segment (mirrored if the words want the other side) ...
	var seg := _segment(e, pk["mirror"], M)
	var S: Scene = seg["scene"]
	var roles: Array = seg["roles"]
	S.name = slug(text)
	var s := _strike_of(roles)
	var n := S.cards.size()
	# ... the weapon swapped (or taken away), both hands on a two-handed one
	var swapped := kind != String(e["kind"])
	var grip := []
	var aim := 0.0
	var moved := 0.0
	for i in n:
		var r := _arm(B, S.cards[i]["pose"], kind, built_shape == "thrust", swapped)
		S.cards[i]["pose"] = r["pose"]
		grip.append(float(r["miss"]))
		aim = maxf(aim, float(r["aim"]))
		moved = maxf(moved, float(r["moved"]))
	if two:
		notes.append("%s: both hands on the haft on every card, the hold locked (apply_grip, the top hand slid to where it reaches, its palm fitted onto the axis, Lock both hands%s)" % [kind.replace("_", " "),
			("; where the free arm could not get there both arms were searched together (hold_bat): the %s's line turned up to %.0f deg, the bat hand moved up to %.0f cm" % [kind.replace("_", " "), aim, moved * 100.0]) if aim > 0.5 or moved > 0.005 else ""])
	# ... the footwork, the legs re-planted by the app's pin (steps -> Body.plant)
	var fw := _footwork(S, roles, String(P["foot"]), pk["mirror"])
	if fw != "":
		notes.append(fw)
	S.pin_cards(B)
	# ... the balance the source had: a card whose centre of mass is now past the feet gets its hips moved over them
	var bal_notes := []
	for i in range(1, n):
		for it in 3:
			var bal := _margin(B, S.cards[i]["pose"])
			var m := float(bal["margin"])
			if m >= 0.0 or src_margin[i] < 0.0 or (bal["poly"] as PackedVector2Array).size() == 0:
				break
			var com: Vector3 = bal["com"]
			var q := Vector2(com.x, com.z)
			var to := _onto(bal["poly"], q) - q
			if to.length() < 1e-6:
				break
			var d: Vector2 = to.normalized() * (to.length() + BAL_IN)
			var p: Dictionary = S.cards[i]["pose"]
			var o: Array = p.get("offset", [0, 0, 0])
			p["offset"] = [float(o[0]) + d.x, float(o[1]), float(o[2]) + d.y]
			S.pin_cards(B)
			if it == 0:
				bal_notes.append("%s (%.1f cm)" % [S.cards[i]["name"], -m * 100.0])
	if not bal_notes.is_empty():
		notes.append("hips moved over the feet (the card's offset, the feet re-pinned) where the re-planted feet left the centre of mass past them: " + ", ".join(bal_notes))
	grip = []
	var palm := []
	for c in S.cards:
		B.grip2 = {}
		B.from_dict(c["pose"])
		B.apply_grip()
		grip.append(B.grip_miss())
		palm.append(palm_off(B))
	# ... the timing: the weapon's row, speed words on the anticipation and recovery (Scene.retime)
	var sp: Array = SPEED_F.get(P["speed"], [1.0, 1.0])
	var rules: Array = AT.RULES[row]
	var retimes := {}
	if s >= 2:
		retimes["anticipation"] = _retime_to(S, 1, s - 1, _mid(rules[0]) * float(sp[0]))
	else:
		notes.append("the saved move has no wind-up card before the strike: its anticipation is inside the strike's move")
	var budget: float = float(rules[1]) / BUDGET_FPS
	if S.move_time(s) > budget + 1.0 / BUDGET_FPS:
		retimes["strike"] = _retime_to(S, s, s, budget + float(S.cards[s]["hold"]))
	if n - 1 > s:
		retimes["recovery"] = _retime_to(S, s + 1, n - 1, _mid(rules[2]) * float(sp[1]), true)
	if String(P["speed"]) == "heavy":
		S.cards[s]["ease"] = "in"
		notes.append("heavy: the strike's ease is \"in\" (it accelerates into the contact)")
	# ... then the same op on whichever part holds the trouble, until the peak is the strike's and under the cap and no
	# joint turns faster than in the source (HumanLimits JOINT SPEED): the anticipation (cards 1..s-1), the strike (s)
	# or after it (s+1..)
	var slowed := {"anticipation": [], "strike": [], "after the strike": []}
	var sm: Dictionary = Rulebook.sample(S, B)
	var pkv := _peak(sm, keys)
	var ts := S.times()
	var human := []   # read only once the tip is right (a replay each: HumanLimits.findings samples the scene itself)
	var human_read := false
	var part_of := func(t: float, tt: Array) -> String:   # tt: the times now (a lambda's capture is a copy)
		if t < float(tt[s][0]) - 1e-3 and s >= 2:
			return "anticipation"
		if t > float(tt[s][2]) + 1e-3 and n - 1 > s:
			return "after the strike"
		return "strike"
	var weapon_peak := func(f: Dictionary, smx: Dictionary) -> float:   # when the weapon turned fastest, as rule_sequence read it
		var fr := int(round(float(f["t"]) * Rulebook.FPS))
		var a := maxi(0, fr - int(Rulebook.SWING_LEAD * Rulebook.FPS))
		var b := mini((smx["w_weapon"] as Array).size() - 1, fr + 2)
		return float(smx["t"][Rulebook._argmax(smx["w_weapon"], a, b)])
	for it in LOOPS:
		var part := ""
		var why := ""
		var pct := 125.0
		if float(pkv[0]) > SAFE * cap:
			part = part_of.call(float(pkv[1]), ts)
			why = "the tip at %.1f m/s over %.0f%% of the cap" % [pkv[0], SAFE * 100.0]
			pct = clampf(float(pkv[0]) / (SAFE * cap) * 105.0, 110.0, 200.0)
		elif part_of.call(float(pkv[1]), ts) != "strike":
			part = part_of.call(float(pkv[1]), ts)
			why = "the peak was in it, not in the strike"
		else:
			human = HumanLimits.findings(S, B)
			human_read = true
			var trouble := _new(src_fs, Rulebook.check(S, B, sm), "FAIL").filter(func(f): return f["rule"] in RETIME_RULES)
			trouble += _new(src_human, human).filter(func(f): return f["rule"] == "JOINT SPEED" or f["rule"] == "BODY ACCEL")   # N031: a whole-body lurch the source did not have is retimed too
			for f in trouble:
				if f["rule"] == "SEQUENCE":
					# hips -> chest -> weapon: a timing matter only when the weapon's fastest turn is the wind-up's (sped
					# to the row) or the finding is a second strike the recovery makes; inside the strike's own move it
					# is the pose order, reported as it is
					var pf: String = part_of.call(float(f["t"]), ts)
					if pf != "strike":
						part = pf
						why = "a second strike in it (SEQUENCE)"
					elif s >= 2 and part_of.call(weapon_peak.call(f, sm), ts) == "anticipation":
						part = "anticipation"
						why = "the weapon turned fastest in the wind-up, not in the strike (SEQUENCE)"
					else:
						continue
				elif f["rule"] == "HEAD QUIET" and s >= 2:
					part = "anticipation"   # the head's travel in the 0.3 s before the peak: less of the wind-up in that window
					why = "%s (the Check), which the source did not have" % f["rule"]
				else:
					part = part_of.call(float(f["t"]), ts)
					if f.has("joint"):
						why = "%s turned %.0f°/s, faster than in the source" % [String(f["joint"]).replace("_", " "), f["v"]]
						pct = clampf(float(f["v"]) / float(HumanLimits.SPEED[String(f["joint"]).split("_")[0]]) * 105.0, 110.0, 200.0)
					elif f["rule"] == "BODY ACCEL":
						why = "the centre of mass %s at %.1f m/s^2, over the %.1f cap (BODY ACCEL)" % [f["kind"], f["accel"], f["cap"]]
						pct = BodyCaps.stretch(f)   # N031: as slow as the lurch needs (1 / T^2), not 125% a try
						part = part_of.call(float(f["peak_frame"]) / BodyCaps.FPS, ts)   # the part the lurch PEAKS in (its "t" is where it starts)
					else:
						why = "%s (the Check), which the source did not have" % f["rule"]
				break
			if part == "":
				break
		match part:
			"anticipation":
				S.retime(1, s - 1, pct)
			"strike":
				S.retime(s, s, pct)
			_:
				S.retime(s + 1, n - 1, pct)
		(slowed[part] as Array).append(why)
		human_read = false
		sm = Rulebook.sample(S, B)
		pkv = _peak(sm, keys)
		ts = S.times()
	if not human_read:
		human = HumanLimits.findings(S, B)
	var slow_words := []
	for part in slowed:
		var ws: Array = slowed[part]
		if not ws.is_empty():
			slow_words.append("%s x%d (%s)" % [part, ws.size(), ws[-1]])
	if not slow_words.is_empty():
		notes.append("then slowed again (retime) " + "; ".join(slow_words))
	var fs: Array = Rulebook.check(S, B, sm)
	var must_new := _new(src_fs, fs, "FAIL")
	var human_new := _new(src_human, human)
	var worst := 0.0
	for g in grip:
		worst = maxf(worst, float(g))
	var worst_palm := 0.0
	for g in palm:
		worst_palm = maxf(worst_palm, float(g))
	var status := "%s. %s" % [notes[0] if not notes.is_empty() else "", "; ".join(notes.slice(1))]
	if two:
		status += ". Second hand on the haft (locked, Lock both hands): its palm at worst %.1f cm off the shaft's axis, its wrist %.1f cm off its locked spot after the legs were re-planted" % [worst_palm * 100.0, worst * 100.0]
	if not must_new.is_empty():
		status += ". NEW must-fix vs the source: " + ", ".join(_words_of(must_new))
	if not human_new.is_empty():
		status += ". NEW human-limit finding vs the source: " + ", ".join(_words_of(human_new))
	var unk: Array = P["unknown"]
	if not unk.is_empty():
		status += ". Didn't understand: " + ", ".join(unk)
	var n_fail := func(a: Array) -> int: return a.filter(func(f): return f["sev"] == "FAIL").size()
	return {"ok": true, "scene": S, "source": e, "mirror": pk["mirror"], "roles": roles, "kind": kind, "shape": built_shape,
		"asked_shape": shape, "row": row, "cap": cap, "cap_name": cap_name, "findings": fs, "must_fix": n_fail.call(fs),
		"must_fix_new": _words_of(must_new), "src_must_fix": n_fail.call(src_fs), "human": human,
		"human_new": _words_of(human_new), "src_human": src_human.size(), "peak": pkv[0], "peak_t": pkv[1],
		"window": [float(ts[s][0]), float(ts[s][2])], "strike_card": s, "grip": grip, "worst_grip": worst, "palm": palm, "worst_palm": worst_palm,
		"aim": aim, "moved": moved, "two": two,
		"unknown": unk, "notes": notes, "status": status, "retimes": retimes, "slowed": slowed, "foot": P["foot"], "speed": P["speed"], "side": side}


## a file name from the words: "overhead axe strike, step in" -> "overhead_axe_strike_step_in"
static func slug(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.ends_with("_") and out != "":
			out += "_"
	while out.ends_with("_"):
		out = out.trim_suffix("_")
	return out if out != "" else "move"


## a path in dir that is not taken yet: slug.json, slug_2.json, ... (a blocking is never written over)
static func unique_path(dir: String, name: String) -> String:
	var path := "%s/%s.json" % [dir, name]
	var k := 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d.json" % [dir, name, k]
		k += 1
	return path


## the scene as the file the scene list reads (Scene.to_dict, the same writer as Save), its "plan" = the status
static func save(S: Scene, B: Body, path0: String, plan := "") -> bool:
	var path := UserPaths.w(path0)   # an exported build: res://scenes|... is read-only, the user's folder is written
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var d := S.to_dict(B)
	if plan != "":
		d["plan"] = plan
	f.store_string(JSON.stringify(d, " "))
	f.close()
	return true
