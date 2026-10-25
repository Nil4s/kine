class_name EasyTweak
extends RefCounted
## EASY TWEAK (monkey brain easy): the strip's four buttons under a built clip, in plain words. Faster / Slower scale the
## clip's timing (each card's move and hold) by 0.8 / 1.25; Bigger / Smaller exaggerate or tone down the motion: each
## card's pose moves from the first card (the rest pose) by 1.2 / 0.8 of its own travel. The math lives here; the strip,
## the undo step and the say line live in easy_home.gd. Nothing here writes the scene: exaggerated() returns the new poses.


const FASTER := 0.8
const SLOWER := 1.25
const BIGGER := 1.2
const SMALLER := 0.8
## the sane limits (HEURISTIC, mine): the whole clip may not go under MIN_LEN (a punch in 0.3 s is already a flick) nor over
## MAX_LEN; a move is not cut under Scene.retime's own floor (MIN_MOVE: a shorter one would not scale by k); a move over
## SLOW_MAX_MOVE drags and a hold over SLOW_MAX_HOLD is a freeze
const MIN_LEN := 0.3          # s
## MAX_LEN was 10 s: a walk then a sit down is 10.3 s, so Slower could never touch a clip that a beginner made by chaining
## two moves (walk-through round 5). 20 s: a clip still reads whole in the strip, and the per-move and hold limits below
## still stop a drag; the Slower refusal names the length and the way out.
const MAX_LEN := 20.0         # s
const MIN_MOVE := 0.04        # s: Scene.retime's floor
const SLOW_MAX_MOVE := 3.0    # s
const SLOW_MAX_HOLD := 6.0    # s
const STAND_M := 0.01         # m: a card whose lowest sole is this close to the floor is standing on it (FloorSnap's rule)
const FAST_STOP := "That's as fast as it goes."
const SLOW_MOVE_STOP := "One move would pass %.0f s and drag: remove a step or pick Faster."
const SLOW_LEN_STOP := "This clip is already %.1f s, the longest Easy makes is %.0f s. Remove a step to slow the rest."


## "" when the timing can move by factor k, else the one sentence why not (the press then changes nothing, no undo step)
static func timing_stop(S: Scene, k: float) -> String:
	if k < 1.0:
		if S.length() * k < MIN_LEN:
			return FAST_STOP
		for i in range(1, S.cards.size()):
			if S.move_time(i) * k < MIN_MOVE:
				return FAST_STOP
	else:
		if S.length() * k > MAX_LEN:
			return SLOW_LEN_STOP % [S.length(), MAX_LEN]
		for i in range(1, S.cards.size()):
			if S.move_time(i) * k > SLOW_MAX_MOVE:
				return SLOW_MOVE_STOP % SLOW_MAX_MOVE
		for c in S.cards:
			if float(c["hold"]) * k > SLOW_MAX_HOLD:
				return "One hold would pass %.0f s and freeze the body: pick Faster or remove a hold." % SLOW_MAX_HOLD
	return ""


## EXAGGERATE (none existed in scripts/: grep for exaggerat / amplif / intensity / strength found nothing for a pose).
## Each card after the first: every joint's bend, side and twist, and the root's offset, move from the first card's value
## by k of their own difference (k 1.2 = 20 % further, 0.8 = 20 % less). Joint limits hold (Body.from_dict clamps).
## FEET: a card whose lowest sole stands on the floor is put back on it with FloorSnap's own rule (its root moves, the
## joints do not); a card in the air keeps its height. B is scratch: its pose is replaced.
## Returns {card index: the new pose}; {} when the clip has no rest pose to move from.
static func exaggerated(S: Scene, B: Body, k: float) -> Dictionary:
	var out := {}
	if S.cards.size() < 2:
		return out
	var rest: Dictionary = S.cards[0]["pose"]
	if rest.is_empty() or not rest.has("joints"):
		return out
	var props := S.solid_props()
	var ro: Array = rest.get("offset", [0, 0, 0])
	for i in range(1, S.cards.size()):
		var d: Dictionary = S.cards[i]["pose"]
		if d.is_empty() or not d.has("joints"):
			continue
		var nd := d.duplicate(true)
		var o: Array = d.get("offset", [0, 0, 0])
		nd["offset"] = [_mix(float(ro[0]), float(o[0]), k), _mix(float(ro[1]), float(o[1]), k), _mix(float(ro[2]), float(o[2]), k)]
		for j in nd["joints"]:
			if not rest["joints"].has(j):
				continue
			var x: Dictionary = nd["joints"][j]
			var r: Dictionary = rest["joints"][j]
			for ax in ["bend", "side", "twist"]:
				x[ax] = _mix(float(r[ax]), float(x[ax]), k)
		B.from_dict(d)
		var standing := absf(B.floor_shift()) < STAND_M   # read on the card as it was
		B.from_dict(nd)
		nd = B.to_dict()   # limits clamped, the joints' cached fields refreshed
		if standing:
			nd = FloorSnap.snapped_pose(B, nd, props)
		out[i] = nd
	return out


## the travel of one value from the rest value by factor k
static func _mix(rest: float, v: float, k: float) -> float:
	return rest + k * (v - rest)
