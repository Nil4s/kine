## throw_truth_strip.gd - the N040 picture, one row per clip: three lanes over the frames and the words under them.
##   lane 1 PARTNER: how far his extrapolated centre of mass is outside his feet (bar up, orange once past the 2 cm bar, grey below it)
##   lane 2 THROWER: his own centre of mass against his own feet (bar up = inside, green; bar down = outside, red once past -2 cm)
##   lane 3 VERDICT ribbon per frame: green throw works, yellow no kuzushi, red thrower falls, grey no contact; a white tick on the key frame
## Same family as scripts/reactable_strip.gd. Not wired into main.gd yet.
class_name ThrowTruthStrip
extends Control

const COL_WORKS := Color("3cb44b")
const COL_NOKZ := Color("ffe119")
const COL_FALLS := Color("e6194b")
const COL_NONE := Color("808080")
const COL_OUT := Color("f58231")
const COL_BG := Color("1e1e24")
const COL_LINE := Color("55555f")
const COL_TXT := Color("f5f5f5")
const ROW_H := 210.0
const X0 := 24.0
const PX_PER_F := 22.0
const Y_PER_M := 500.0   # px per metre in lanes 1 and 2

var rows: Array = []


static func color_of(verdict: String) -> Color:
	return {"throw works": COL_WORKS, "no kuzushi": COL_NOKZ, "thrower falls": COL_FALLS}.get(verdict, COL_NONE)


func set_rows(r: Array) -> void:
	rows = r
	queue_redraw()


func ribbon_rect(i: int, f: int) -> Rect2:
	return Rect2(X0 + f * PX_PER_F, 30.0 + i * ROW_H + 124.0, PX_PER_F - 1.0, 18.0)


## a pixel inside the verdict ribbon at frame f of row i (tests read the PNG here)
func verdict_pixel(i: int, f: int) -> Vector2i:
	return Vector2i(ribbon_rect(i, f).get_center())


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var font := ThemeDB.fallback_font
	for i in rows.size():
		var r: Dictionary = rows[i]["r"]
		var y := 30.0 + i * ROW_H
		draw_string(font, Vector2(X0, y - 8.0), String(rows[i]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_TXT)
		var base1 := y + 62.0   # lane 1 baseline (bars go up)
		var base2 := y + 112.0  # lane 2 baseline (+ up, - down)
		var fr: Array = r.get("frames", [])
		var xe := X0 + fr.size() * PX_PER_F
		draw_line(Vector2(X0, base1), Vector2(xe, base1), COL_LINE, 1.0)
		draw_line(Vector2(X0, base2 - 14.0), Vector2(xe, base2 - 14.0), COL_LINE, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(xe + 6.0, base1 + 4.0), "partner outside feet", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_OUT)
		draw_string(ThemeDB.fallback_font, Vector2(xe + 6.0, base2 - 10.0), "thrower inside feet", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_WORKS)
		var yk := base1 - Balance.MARGIN_RES * Y_PER_M
		draw_line(Vector2(X0, yk), Vector2(xe, yk), COL_OUT.darkened(0.4), 1.0)
		for q in fr:
			var x := X0 + int(q["f"]) * PX_PER_F
			var out := minf(float(q["partner"]["out"]), 0.1)
			if out > 0.0:
				draw_rect(Rect2(x, base1 - out * Y_PER_M, PX_PER_F - 1.0, out * Y_PER_M), COL_OUT if float(q["partner"]["out"]) > Balance.MARGIN_RES else COL_NONE)
			var m := clampf(float(q["thrower"]["margin"]), -0.1, 0.1)
			var mb := base2 - 14.0
			var hgt := m * Y_PER_M * 0.5
			draw_rect(Rect2(x, mb - maxf(hgt, 0.0), PX_PER_F - 1.0, absf(hgt)), COL_WORKS if m >= -Balance.MARGIN_RES else COL_FALLS)
			draw_rect(ribbon_rect(i, int(q["f"])), color_of(String(q["verdict"])))
		var kf := int(r.get("frame", -1))
		if kf >= 0 and not fr.is_empty():
			var rr := ribbon_rect(i, kf)
			draw_line(Vector2(rr.position.x + rr.size.x * 0.5, rr.position.y - 4.0), Vector2(rr.position.x + rr.size.x * 0.5, rr.end.y + 8.0), COL_TXT, 2.0)
		draw_multiline_string(font, Vector2(X0, y + 166.0), String(r.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, 840.0, 12, 3, color_of(String(r.get("verdict", ""))))
