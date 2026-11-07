class_name SpacingStrip
extends Control
## L96: the classic spacing chart strip. Two rows of ticks along one line, 0..1 of the move: the reference's frames on top, the clip's below.
## set_data(SpacingChart.compare(..)); ticks() gives each tick's row and rect (the same rects _draw paints), so a test reads placement as numbers.

const TICK_W := 3.0
var _ref: Array = []
var _clip: Array = []


func set_data(cmp: Dictionary) -> void:
	_ref = cmp.get("ticks_ref", [])
	_clip = cmp.get("ticks_clip", [])
	queue_redraw()


func ticks() -> Array:
	var o := []
	var h := size.y
	for row in [["ref", _ref, 0.15], ["clip", _clip, 0.55]]:
		for x in row[1]:
			var cx := clampf(float(x) * size.x - TICK_W * 0.5, 0.0, size.x - TICK_W)
			o.append({"row": row[0], "rect": Rect2(cx, h * float(row[2]), TICK_W, h * 0.3)})
	return o


func _draw() -> void:
	draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), Color(1, 1, 1, 0.2))
	for t in ticks():
		draw_rect(t["rect"], Color(0.95, 0.7, 0.2) if t["row"] == "ref" else Color(0.3, 0.8, 1.0))
