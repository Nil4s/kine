## reactable_strip.gd - the N082 picture: one row per clip, a frame line with the TELL (green = reactable, red = not),
## the needed frames as a white tick before the first active frame, and the active frame as a dark block. Not wired into main.gd yet.
class_name ReactableStrip
extends Control

const COL_OK := Color("3cb44b")
const COL_NO := Color("e6194b")
const COL_BG := Color("1e1e24")
const COL_LINE := Color("55555f")
const COL_ACT := Color("f5f5f5")
const ROW_H := 100.0
const X0 := 20.0
const PX_PER_F := 6.0

var rows: Array = []


func set_rows(r: Array) -> void:
	rows = r
	queue_redraw()


func _bar(i: int, f0: int, f1: int) -> Rect2:
	return Rect2(X0 + f0 * PX_PER_F, 40.0 + i * ROW_H, maxf(1.0, (f1 - f0) * PX_PER_F), 24.0)


func tell_center(i: int) -> Vector2i:
	var run: Dictionary = (rows[i]["r"]["runs"] as Array)[0]
	var b := _bar(i, int(run["readable"]), int(run["first_active"]))
	return Vector2i(b.get_center())


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var font := ThemeDB.fallback_font
	for i in rows.size():
		var r: Dictionary = rows[i]["r"]
		var y := 40.0 + i * ROW_H
		draw_string(font, Vector2(X0, y - 18.0), String(rows[i]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_ACT)
		draw_line(Vector2(X0, y + 12.0), Vector2(X0 + 140 * PX_PER_F, y + 12.0), COL_LINE, 2.0)
		var runs: Array = r.get("runs", [])
		if runs.is_empty():
			continue
		var run: Dictionary = runs[0]
		var col := COL_OK if run["status"] == "reactable" else COL_NO
		draw_rect(_bar(i, int(run["readable"]), int(run["first_active"])), col)
		draw_rect(_bar(i, int(run["first_active"]), int(run["first_active"]) + 3), COL_BG.lightened(0.0).inverted())
		var tx := maxf(X0 + 1.0, X0 + (int(run["first_active"]) - int(run["need_f"])) * PX_PER_F)   # clamped at the clip start when the need reaches before it
		draw_line(Vector2(tx, y - 6.0), Vector2(tx, y + 30.0), COL_ACT, 2.0)
		draw_string(font, Vector2(X0, y + 52.0), String(run["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
