## react_time.gd - REACTION AUTO-TIMING (L89 / L29). A defender's block is placed at human reaction time after the attacker's cue.
## CUE = the first frame (1/60 s steps) at which any joint of the attacker is more than COMMIT_DEG from its frame 0 pose (committed motion).
## BLOCK START = the start of the move into the defender's first card named like a block (FightRhythm.BLOCK_WORDS).
## RT = Counter.REACT 0.29 s: the MEASURED simple visual reaction time of elite karate athletes, 292 +- 45 ms (Liu, See, Chang et al. 2018,
## Arch Budo 14). A block that starts less than SUPERHUMAN (= mean - 2 SD = 0.20 s) after the cue is flagged: nobody reacts that fast.
## place() shifts the defender's block by changing the HOLD of the card before it; every move, pose and later hold stays as it was.
class_name ReactTime
extends RefCounted

const SUPERHUMAN := 0.20
const COMMIT_DEG := 2.0
const STEP := 1.0 / 60.0


## the cue time (s), or -1.0 when the attacker never moves
static func cue(A: Scene) -> float:
	if A.cards.size() < 2:
		return -1.0
	var a0: Dictionary = A.sample(0.0)["ang"]
	var n := int(A.length() / STEP)
	for f in range(1, n):
		var t := float(f) * STEP
		var a: Dictionary = A.sample(t)["ang"]
		for j in a:
			var d: Vector3 = ((a[j] as Vector3) - (a0.get(j, Vector3.ZERO) as Vector3)).abs()
			if maxf(d.x, maxf(d.y, d.z)) > COMMIT_DEG:
				return t
	return -1.0


## the defender's first block card (-1 = none)
static func block_card(D: Scene) -> int:
	for i in range(1, D.cards.size()):
		if FightRhythm._word(String(D.cards[i]["name"]).to_lower(), FightRhythm.BLOCK_WORDS) != "":
			return i
	return -1


## {"status": ok / superhuman / no cue / no block, "cue", "card", "onset", "gap", "target", "msg"}
static func read(A: Scene, D: Scene, rt := Counter.REACT) -> Dictionary:
	var c := cue(A)
	var bi := block_card(D)
	var out := {"status": "ok", "cue": c, "card": bi, "onset": -1.0, "gap": 0.0, "target": -1.0, "rt": rt, "msg": ""}
	if c < 0.0:
		out["status"] = "no cue"
		out["msg"] = "no cue: the attacker never makes a committed move, so there is nothing to react to (nothing is shifted)"
		return out
	if bi < 0:
		out["status"] = "no block"
		out["msg"] = "no block: the defender has no card named block / parry / slip / dodge ..., name the card first"
		return out
	var onset := float(D.times()[bi][0])
	out["onset"] = onset
	out["gap"] = onset - c
	out["target"] = c + rt
	if onset - c < SUPERHUMAN - 0.005:
		out["status"] = "superhuman"
		out["msg"] = "the block starts %.2f s after the cue: under %.2f s nobody reacts (human reaction time %.2f s)" % [onset - c, SUPERHUMAN, rt]
	else:
		out["msg"] = "the block starts %.2f s after the cue (human reaction time %.2f s)" % [onset - c, rt]
	return out


## shift D's block to cue + rt (in place when it works). {"ok", "msg", "delta", "onset"}
static func place(A: Scene, D: Scene, rt := Counter.REACT) -> Dictionary:
	var r := read(A, D, rt)
	if r["status"] == "no cue" or r["status"] == "no block":
		return {"ok": false, "msg": r["msg"], "delta": 0.0}
	var bi: int = r["card"]
	var delta: float = float(r["target"]) - float(r["onset"])
	var prev: float = float(D.cards[bi - 1]["hold"])
	if prev + delta < -1e-6:
		return {"ok": false, "msg": "the block cannot start that early: the card before it has only %.2f s of hold to give" % prev, "delta": delta}
	D.cards[bi - 1]["hold"] = snappedf(maxf(0.0, prev + delta), 0.001)
	return {"ok": true, "delta": delta, "onset": float(D.times()[bi][0]),
		"msg": "the block now starts %.2f s after the cue (shifted %+.2f s)" % [rt, delta]}
