class_name PullTouch
extends RefCounted
## W10c: after a pull that stands as its own piece because joining left more pieces (W10b), which earlier body does the new one touch
## ONLY along a line or at a point? Returns that body's index (the new piece is the last body), or -1 (a gap, or no touch at all).
## Face contact would have joined, so a touch that survives a failed join is a line / point touch.

const WORDS := "it only touches the solid along a line, so it stayed a separate piece: press Nudge 0.01 mm and retry to stick it on"


static func line_touch(rec: Dictionary, part: Object) -> int:
	var faces: Array = part.body_faces(rec, -1)
	if faces.size() < 2:
		return -1
	var n := faces.size() - 1
	for i in n:
		if part.tris_touch(faces[i], faces[n], 0.00005):
			return i
	return -1
