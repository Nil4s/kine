## bake.gd - BAKE (round 48, GATES DD4, UPGRADES_300 #250; Blender's "Bake Action", Maya's "Bake Simulation").
## The scene's curves (cards, part keys and their modifier stacks) flattened into CARDS at a chosen rate: one card every
## 1/rate s, each the pose the scene really PLAYS at that time (Scene.apply: the card blend, the part keys and their
## modifiers, the floor, the planted feet, the layer, breathing, flights), moving LINEARLY into the next; then the part
## keys are gone. Blender calls this "visual keying": the baked keys hold what you SEE, not what drove it. For export and
## for agents that read cards only (an agent sees every joint's real angle on a card instead of a curve it does not read).
## Because the overlays are now INSIDE the cards, the baked scene turns them off (floor, pins, layer, breathing, the
## natural lag, spline, stepped, moving holds): left on, they would act a second time. The first try kept them on and
## baked only Scene.sample: the pins plant per CARD, so 70 baked cards planted the feet 70 times (Nick's swing_fore, a
## calf 63 deg off). The report names what was turned off. The last card lands on the scene's own end (its length).
class_name Bake
extends RefCounted


## bake S in place at `rate` cards a second (B: any loaded Body, posed as scratch). Returns {"cards": n, "was": old card
## count, "part_keys": joints that had keys, "off": the overlays turned off because they are baked in}. A scene with no
## cards is left alone ({"cards": 0}).
static func bake(S: Scene, B: Body, rate: float) -> Dictionary:
	if S.cards.is_empty():
		return {"cards": 0, "was": 0, "part_keys": 0}
	rate = clampf(rate, 1.0, 120.0)
	var L := S.length()
	var n := maxi(int(ceilf(L * rate - 1e-6)), 1)
	var ts := []
	for k in n:
		ts.append(float(k) / rate)
	ts.append(L)
	var poses := []
	for t in ts:
		S.apply(B, t)
		poses.append(B.to_dict())
	var was := S.cards.size()
	var had := S.part_keys.size()
	var cards := []
	for k in ts.size():
		var c := {"name": "bake %d" % k, "pose": poses[k], "move": 0.0 if k == 0 else float(ts[k]) - float(ts[k - 1]),
			"hold": 0.0, "ease": "linear"}
		cards.append(c)
	var off := []
	for f in ["on_floor", "pin", "spline", "stepped", "moving_holds", "natural", "floor_body"]:
		if bool(S.get(f)):
			off.append(f)
			S.set(f, false)
	if not S.layer.is_empty():
		off.append("layer")
		S.layer = {}
	if not S.layers.is_empty():
		off.append("layers")   # NA1: baked in, so they go
		S.layers = []
	if S.breath > 0.0:
		off.append("breath")
		S.breath = 0.0
	if not S.ik.is_empty():
		off.append("ik")   # the IK pass played into the baked cards: left on it would act a second time
		S.ik = {}
	if not S.cons.is_empty():
		off.append("constraints")   # round 51: played into the baked cards, the same reason
		S.cons = []
	if not S.clips.is_empty():
		off.append("clips")   # CLIPS: played into the baked cards, the same reason
		S.clips = []
	S.cards = cards
	S.part_keys = {}
	return {"cards": cards.size(), "was": was, "part_keys": had, "off": off}
