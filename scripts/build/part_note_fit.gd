class_name PartNoteFit
extends RefCounted
## W02b: the status line of the Part workspace ("Sketch1: closed profile, 2 dimensions, 2 free") must be readable whole. It sits top-left,
## right of the browser; the Look/Print (Warnings) panel and the side panel stand to its right. fit() gives the label the width that is
## left before the first of them (and the window edge), wraps the text there, and if even that is too narrow puts the line under them.

const MARGIN := 8.0
const MIN_W := 220.0


static func fit(note: Control, label: Label, view: Vector2, obstacles: Array) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 0.0
	note.reset_size()
	var pad := note.get_combined_minimum_size().x - label.get_combined_minimum_size().x
	var natural := label.get_combined_minimum_size().x
	var right := view.x - MARGIN
	var rects: Array = []
	for o in obstacles:
		if o is Control and (o as Control).is_visible_in_tree():
			rects.append(Rect2((o as Control).position, (o as Control).size))
	var y_lo := note.position.y
	for r in rects:   # an obstacle that starts above where this line could end (its text wraps to a few rows at most)
		if r.end.y > y_lo and r.position.y < y_lo + 90.0 and r.position.x > note.position.x:
			right = minf(right, r.position.x - MARGIN)
	var room := right - note.position.x - pad
	if room < MIN_W:   # no room beside them: go under the one in the way
		var low := y_lo
		for r in rects:
			if r.end.y > y_lo and r.position.y < y_lo + 90.0 and r.position.x > note.position.x:
				low = maxf(low, r.end.y + MARGIN)
		note.position.y = low
		room = view.x - MARGIN - note.position.x - pad
	if natural > room:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = maxf(room, 60.0)
	note.reset_size()
