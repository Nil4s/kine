## why.gd - THE WHY OF A CURVE (round 48, GATES DD5, UPGRADES_300 #251). The curve editor paints red the spans of time
## where a Check rule fires because of what this joint moves, and names the rule. No other curve editor says why a curve
## looks wrong. The spans are the RULES' OWN windows, rebuilt from Rulebook's sample (the same one Check reads):
##   HITCH      the rule tests a speed dip against the HITCH_SPAN frames on each side: the span is the finding's frame
##              +- HITCH_SPAN frames. Its parts are the ones the finding names (the weapon tip / right hand, hips, head)
##   TIP SPEED  the frames round the strike's peak where the tip is over the weapon's cap (AT.TIP_MAX), contiguous, each
##              frame +- half a frame (so a one-frame breach still has a width)
## A span belongs to a joint when its part is moved by that joint: the weapon tip or the right hand by the shoulders,
## arms, hands and fingers (and the spine that carries them); the hips by the pelvis and the legs; the head by the neck,
## the head and the spine. Other rules are not painted (they are not about a speed on a curve).
class_name Why
extends RefCounted

const RULES := ["HITCH", "TIP SPEED"]


## which parts a joint moves ("tip", "hips", "head")
static func parts_of(j: String) -> Array:
	var out := []
	if j.begins_with("spine") or j.begins_with("clavicle") or j.begins_with("upperarm") or j.begins_with("lowerarm") \
			or j.begins_with("hand") or j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") \
			or j.begins_with("ring") or j.begins_with("pinky"):
		out.append("tip")
	if j == "pelvis" or j.begins_with("thigh") or j.begins_with("calf") or j.begins_with("foot") or j.begins_with("ball"):
		out.append("hips")
	if j.begins_with("neck") or j == "head" or j.begins_with("spine"):
		out.append("head")
	return out


## every span the two rules give for scene S: [{"rule", "t0", "t1", "parts": [...], "msg"}] (sm: Rulebook.sample, or {})
static func spans(S: Scene, B: Body, sm := {}) -> Array:
	if S.cards.size() < 2:
		return []
	if sm.is_empty():
		sm = Rulebook.sample(S, B)
	var out := []
	var fs := Rulebook.check(S, B, sm)
	var ts: Array = sm["t"]
	var half := Rulebook.HITCH_SPAN / Rulebook.FPS
	for f in fs:
		if f["rule"] == "HITCH":
			var msg: String = f["msg"]
			var o := msg.find("(")   # "<first part>: a -> b -> c m/s within N ms (<the others> | alone). ..."
			var head := (msg.left(msg.find(":")) + " " + msg.substr(o, msg.find(")", o) - o)).to_lower()
			var parts := []
			if head.contains("weapon tip") or head.contains("right hand"):
				parts.append("tip")
			if head.contains("hips"):
				parts.append("hips")
			if head.contains("the head"):
				parts.append("head")
			out.append({"rule": "HITCH", "t0": float(f["t"]) - half, "t1": float(f["t"]) + half, "parts": parts, "msg": msg})
		elif f["rule"] == "TIP SPEED":
			var cap: float = Rulebook.AT.TIP_MAX.get(sm["kind"], 40.0)
			var pk := 0
			for i in ts.size():
				if absf(float(ts[i]) - float(f["t"])) < absf(float(ts[pk]) - float(f["t"])):
					pk = i
			var a := pk
			var b := pk
			while a > 0 and float(sm["tip"][a - 1]) > cap:
				a -= 1
			while b < ts.size() - 1 and float(sm["tip"][b + 1]) > cap:
				b += 1
			var hf := 0.5 / Rulebook.FPS   # each frame owns half a frame either side: a one-frame breach is still a span
			out.append({"rule": "TIP SPEED", "t0": float(ts[a]) - hf, "t1": float(ts[b]) + hf, "parts": ["tip"], "msg": f["msg"]})
	return out


## the spans that are joint j's business
static func for_joint(all: Array, j: String) -> Array:
	var mine := parts_of(j)
	return all.filter(func(s): return (s["parts"] as Array).any(func(p): return p in mine))
