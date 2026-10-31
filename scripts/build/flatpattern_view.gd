class_name FlatPatternView
extends Control
## p117flatpatter: draws a FlatPattern.net() on the sheet. The panels are kept in mm (pieces) so a test reads what is on the screen
## in the same units the box was measured in. The drawing is scaled to fit the view and centred

var pieces := []          # the drawn panels: {name, pts (mm), rect (mm)}
var sheet := Vector2.ONE  # the cross's size without tabs (mm)
var px_per_mm := 1.0      # the scale of the last draw


func show_net(net: Dictionary) -> void:
	pieces = net["pieces"]
	sheet = net["sheet"]
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tok.c("info").darkened(0.6))
	if pieces.is_empty() or sheet.x <= 0.0:
		return
	px_per_mm = minf((size.x - 24.0) / sheet.x, (size.y - 24.0) / sheet.y)
	var off := (size - sheet * px_per_mm) / 2.0
	var font := get_theme_default_font()
	for p in pieces:
		var q := PackedVector2Array()
		for v in p["pts"]:
			q.append(off + (v as Vector2) * px_per_mm)
		draw_colored_polygon(q, Tok.c("info").darkened(0.2))
		q.append(q[0])
		draw_polyline(q, Tok.c("pick_sel"), 2.0)
		var r: Rect2 = p["rect"]
		var at := off + r.get_center() * px_per_mm
		draw_string(font, at - Vector2(24, -5), String(p["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tok.c("say"))
