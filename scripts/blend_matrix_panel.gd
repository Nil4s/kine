## blend_matrix_panel.gd - the HEAT GRID of the blend matrix (N084; the maths: scripts/blend_matrix.gd). Row = the clip that ends, column = the clip that
## starts. A cell is green (ok), amber (warn) or red (bad), the red deeper the further past its bar; a click on a cell emits picked(i, j) and the app
## previews that blend on the body. Hovering a cell says why in words. The diagonal (a clip into itself, its loop point) has a thin outline.
class_name BlendMatrixPanel
extends Control

signal picked(i: int, j: int)

const CELL := 30.0
const LABEL_W := 104.0
const TOP_H := 22.0
const GAP := 2.0

var M: Dictionary = {}
var sel := Vector2i(-1, -1)


func set_matrix(m: Dictionary) -> void:
	M = m
	sel = Vector2i(-1, -1)
	var n := int(m.get("n", 0))
	custom_minimum_size = Vector2(LABEL_W + float(n) * CELL + 6.0, TOP_H + float(n) * CELL + 6.0)
	queue_redraw()


func count() -> int:
	return int(M.get("n", 0))


## the cell under a point in this control's own coordinates: (row, column) or (-1, -1)
func cell_at(p: Vector2) -> Vector2i:
	var n := count()
	var x := p.x - LABEL_W
	var y := p.y - TOP_H
	if n == 0 or x < 0.0 or y < 0.0:
		return Vector2i(-1, -1)
	var j := int(x / CELL)
	var i := int(y / CELL)
	if i >= n or j >= n:
		return Vector2i(-1, -1)
	return Vector2i(i, j)


func cell_rect(i: int, j: int) -> Rect2:
	return Rect2(LABEL_W + float(j) * CELL, TOP_H + float(i) * CELL, CELL, CELL)


## the colour of a cell from its verdict and how far past its bar it is
static func colour_of(c: Dictionary) -> Color:
	var v := String(c.get("verdict", "ok"))
	if v == "ok":
		return Tok.c("ok").lerp(Tok.c("graph_bg"), 0.45)
	if v == "warn":
		return Tok.c("warn")
	var over := clampf((float(c.get("score", 1.0)) - 1.0) / 3.0, 0.0, 1.0)
	return Tok.c("warn").lerp(Tok.c("fail"), 0.5 + 0.5 * over)


func cell_color(i: int, j: int) -> Color:
	return colour_of(M["cells"][i][j])


func _draw() -> void:
	var n := count()
	var f := get_theme_default_font()
	var fs := 11
	if n == 0:
		draw_string(f, Vector2(6, 16), "no matrix yet", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tok.c("ink"))
		return
	var ink: Color = Tok.c("ink")
	var names: Array = M["names"]
	for i in n:
		draw_string(f, Vector2(4, TOP_H + float(i) * CELL + CELL * 0.62), "%d %s" % [i + 1, String(names[i]).left(12)], HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 6.0, fs, ink)
		draw_string(f, Vector2(LABEL_W + float(i) * CELL + CELL * 0.35, TOP_H - 6.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	for i in n:
		for j in n:
			var r := cell_rect(i, j).grow(-GAP * 0.5)
			var c: Dictionary = M["cells"][i][j]
			draw_rect(r, colour_of(c))
			if i == j:
				draw_rect(r, ink, false, 1.0)
			if sel == Vector2i(i, j):
				draw_rect(cell_rect(i, j), ink, false, 2.0)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		click(e.position)


## a click at a point (the tests call this too)
func click(p: Vector2) -> Vector2i:
	var ij := cell_at(p)
	if ij.x >= 0:
		sel = ij
		queue_redraw()
		picked.emit(ij.x, ij.y)
	return ij


func cell_words(i: int, j: int) -> String:
	var c: Dictionary = M["cells"][i][j]
	return "%s -> %s: %s (%s). limit %.1f deg, clash %.1f mm, skate %.1f mm, seam %.0f" % [c["a"], c["b"], c["verdict"], c["why"], c["limit_deg"], c["clash_mm"], c["skate_mm"], c["seam"]]


func _get_tooltip(at_position: Vector2) -> String:
	var ij := cell_at(at_position)
	return cell_words(ij.x, ij.y) if ij.x >= 0 else ""
