class_name PartPosDim
extends RefCounted
## W02c: the Dimension tool on a rectangle's corner gives its distance from the origin: x, then y (typed with units through LengthParse).

const PICK_PX := 9.0


## the corner of a rectangle within PICK_PX of a screen point: {"ent", "kind": "x", "a", "b", "then_y": true} or {}
static func corner_pick(ents: Array, p: Vector2, scr: Callable) -> Dictionary:
	var best := {}
	var best_d := PICK_PX
	for i in ents.size():
		var e: Dictionary = ents[i]
		if String(e.get("k", "")) != "rect":
			continue
		var a := Part.v2(e["a"])
		var b := Part.v2(e["b"])
		for c in [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]:
			var d := p.distance_to(scr.call(c))
			if d < best_d:
				best_d = d
				var own := Part.v2(e["a"])
				best = {"ent": i, "kind": "x", "a": own, "b": own, "then_y": true}
	return best


## the second prompt: the same corner's y
static func next_y(sk: Dictionary, ent: int, _scr: Callable) -> Dictionary:
	var a := Part.v2((sk["ents"] as Array)[ent]["a"])
	return {"ent": ent, "kind": "y", "a": a, "b": a}
