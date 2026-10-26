## blueprint_view.gd - paints a Blueprint sheet (its entity list, paper mm) at ppm pixels per mm: the sheet view on screen and the 300 dpi PNG export
class_name BlueprintView
extends Control

var sheet := {}
var ppm := 1.0


func _draw() -> void:
	if sheet.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(float(sheet["w"]), float(sheet["h"])) * ppm), Color.WHITE)
	var font := ThemeDB.fallback_font
	for e in sheet["ents"]:
		var cls := String(e["cls"])
		var st := Blueprint.style(cls)
		var col := Color.html(String(st.get("stroke", "#000000")))
		var wpx := maxf(1.0, float(st.get("w", 0.2)) * ppm)
		var dash := float(st.get("dash", 0.0)) * ppm
		match String(e["t"]):
			"line":
				_seg(e["a"] * ppm, e["b"] * ppm, col, wpx, dash)
			"poly":
				var pts := PackedVector2Array()
				for v in e["pts"]:
					pts.append(v * ppm)
				if st.has("fill") and pts.size() >= 3:
					if Geometry2D.triangulate_polygon(pts).size() >= 3:
						draw_colored_polygon(pts, Color.html(String(st["fill"])))
				for i in pts.size():
					_seg(pts[i], pts[(i + 1) % pts.size()], col, wpx, dash)
			"arc":
				var a0 := minf(float(e["a0"]), float(e["a1"]))
				var a1 := maxf(float(e["a0"]), float(e["a1"]))
				draw_arc((e["c"] as Vector2) * ppm, float(e["r"]) * ppm, a0, a1, 48, col, wpx, true)
			"text":
				var fs := maxi(int(round(float(e["h"]) * ppm)), 5)
				var s := String(e["s"])
				var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var dx := 0.0 if e["anc"] == "l" else (-w * 0.5 if e["anc"] == "m" else -w)
				draw_set_transform((e["p"] as Vector2) * ppm, deg_to_rad(float(e["rot"])))
				draw_string(font, Vector2(dx, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				draw_set_transform(Vector2.ZERO)


func _seg(a: Vector2, c: Vector2, col: Color, w: float, dash: float) -> void:
	if dash > 0.0:
		draw_dashed_line(a, c, col, w, dash, true, true)
	else:
		draw_line(a, c, col, w, true)
