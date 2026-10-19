## SNAP TO FLOOR (ROADMAP 46): the whole body moves straight up or down until its lowest contact touches the floor.
## Only the root (the card's "offset") changes: every joint angle stays as it is. The floors are the app's own (see
## Body.floor_shift): a sole stands on Body.ground()'s floor, a knee / hip / hand capsule on y = 0 (Body.ground_body()'s).
## So a standing pose snaps to exactly what Body.ground() gives it, and a kneeling pose rests on its knee surface.
## Props (ROADMAP 93): with a set, the soles stand on the surface under them (Body.floor_shift); a seat under a lifted body
## is still passed through (only the soles are measured against the set).
class_name FloorSnap


## the card pose d with its root raised or sunk so its lowest point is on the floor. Joints, weapons and contacts are
## copied as they are; only the offset's height changes. B is used as scratch (its pose is replaced)
## props (ROADMAP 93): the set the pose stands on; its soles land on the surfaces under them (a step's tread, a ramp)
static func snapped_pose(B: Body, d: Dictionary, props := []) -> Dictionary:
	if d.is_empty() or not d.has("joints"):
		return d
	B.from_dict(d)
	B.props = props
	var shift := B.floor_shift()
	var o: Array = d.get("offset", [0, 0, 0])
	var out := d.duplicate(true)
	out["offset"] = [float(o[0]), float(o[1]) - shift, float(o[2])]
	return out


## every card of the scene snapped to the floor (a new pose dictionary for each card, so the scene's pose cache stays
## right). Returns how many cards moved by more than 0.01 mm
static func snap_all(S: Scene, B: Body) -> int:
	var moved := 0
	for c in S.cards:
		var d: Dictionary = c["pose"]
		if d.is_empty() or not d.has("joints"):
			continue
		var nd := snapped_pose(B, d, S.solid_props())
		if absf(float((nd["offset"] as Array)[1]) - float((d["offset"] as Array)[1])) > 0.00001:
			moved += 1
		c["pose"] = nd
	return moved
