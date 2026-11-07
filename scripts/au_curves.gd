class_name AuCurves
extends RefCounted
## L94 (ROADMAP_400 L30): a face AU channel (Scene.face[ch], scripts/face.gd) as the graph editor draws it. The channel's keys are PartKeys
## keys (value in x), so weights, buffer curves and modifiers all work on them; the value read is the curve WITH its stack, clamped to the
## channel's own range (Face.range_of: 0..1, brows and eyes -1..1). Playback (Face.values_at) reads the same function, so graph == playback.
## Shape-key weights are not time-keyed on this base; a shape track that stores PartKeys keys can use these functions the same way.


static func range_of(ch: String) -> Vector2:
	return Face.range_of(ch)


static func value_at(face: Dictionary, ch: String, t: float) -> float:
	if not face.has(ch) or (face[ch] as Array).is_empty():
		return clampf(0.0, range_of(ch).x, range_of(ch).y)
	var r := range_of(ch)
	return clampf(PartKeys.value_at(face[ch], t).x, r.x, r.y)
