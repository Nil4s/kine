## lock_panel.gd - the "Lock check" panel (N041 wired): the verdict of LockTruth.judge over the open two-body scene, one coloured cell per frame
## (red past limit: injury, yellow at limit, green lock not on, grey no contact; a white tick on the key frame), the key frame's joint and margin in
## degrees, a tooltip per cell, and a click on a cell asks the app to jump the timeline there (frame_picked). With one body it says why it is empty.
class_name LockPanel
extends Control

signal frame_picked(f: int)

const H := 92.0
const W := 560.0
const PAD := 10.0
const CELL_Y := 52.0
const CELL_H := 16.0
const COL_BG := Color(0.12, 0.12, 0.15, 0.94)
const COL_TXT := Color("f5f5f5")

var res: Dictionary = {}
var empty_reason := "Lock check is off"


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_result(r: Dictionary) -> void:
	res = r
	empty_reason = ""
	if not bool(r.get("ok", false)) or (r.get("frames", []) as Array).is_empty():
		res = {}
		empty_reason = "Lock check needs two bodies: this scene has one fighter. Add a second fighter to judge a lock."
	queue_redraw()


static func deg(x: float) -> String:
	return "%.1f deg" % x


static func color_of(v: String) -> Color:
	return {"past limit: injury": Color("d94a4a"), "at limit": Color("e0c040"), "lock not on": Color("4fae6a")}.get(v, Color("707078"))


func readout() -> String:
	if res.is_empty():
		return empty_reason
	var k: int = res["frame"]
	var v := String(res["verdict"])
	if v == "no contact":
		return "%s at f %d: the locker never touches his arm (closest %.1f cm)" % [v.to_upper(), k, float(res["min_gap"]) * 100.0]
	return "%s at f %d | his %s %s %s | margin %s" % [v.to_upper(), k, res["side"], res["joint"], res["axis"], deg(float(res["margin_deg"]))]


func tip_for(f: int) -> String:
	if res.is_empty() or f < 0 or f >= (res["frames"] as Array).size():
		return ""
	var fr: Dictionary = res["frames"][f]
	if not bool(fr["contact"]):
		return "frame %d (%.2f s): no contact" % [f, float(fr["t"])]
	return "frame %d (%.2f s): %s | his %s %s %s | margin %s" % [f, float(fr["t"]), fr["verdict"], fr["side"], fr["joint"], fr["axis"], deg(float(fr["margin_deg"]))]


func _cw() -> float:
	var n := 1 if res.is_empty() else (res["frames"] as Array).size()
	return (size.x - 2.0 * PAD) / float(maxi(n, 1))


func x_of_frame(f: int) -> float:
	return PAD + (float(f) + 0.5) * _cw()


func cell_y() -> float:
	return CELL_Y + CELL_H * 0.5


func frame_at(x: float) -> int:
	if res.is_empty():
		return -1
	var f := int(floor((x - PAD) / _cw()))
	return f if f >= 0 and f < (res["frames"] as Array).size() else -1


func _gui_input(ev: InputEvent) -> void:
	if res.is_empty():
		return
	if (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed) or (ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		var f := frame_at(ev.position.x)
		if f >= 0:
			frame_picked.emit(f)
			accept_event()


func _get_tooltip(at: Vector2) -> String:
	var f := frame_at(at.x)
	return tip_for(f) if f >= 0 else readout()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(PAD, 16), "Lock check", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TXT.darkened(0.3))
	if res.is_empty():
		draw_multiline_string(font, Vector2(PAD, 36), empty_reason, HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * PAD, 13, 3, COL_TXT)
		return
	var v := String(res["verdict"])
	draw_string(font, Vector2(PAD, 36), readout(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * PAD, 13, color_of(v).lightened(0.25))
	var cw := _cw()
	var fr: Array = res["frames"]
	for i in fr.size():
		draw_rect(Rect2(PAD + i * cw, CELL_Y, maxf(cw - 1.0, 1.0), CELL_H), color_of(String(fr[i]["verdict"])))
	var kx := x_of_frame(int(res["frame"]))
	draw_line(Vector2(kx, CELL_Y - 6.0), Vector2(kx, CELL_Y - 1.0), COL_TXT, 2.0)
	draw_line(Vector2(kx, CELL_Y + CELL_H + 1.0), Vector2(kx, CELL_Y + CELL_H + 6.0), COL_TXT, 2.0)
	draw_string(font, Vector2(PAD, CELL_Y + CELL_H + 20.0), "click a frame to jump there   |   red past limit  yellow at limit  green lock not on  grey no contact", HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * PAD, 10, COL_TXT.darkened(0.3))
