## shot_frame.gd - LOOK THROUGH THE SHOT CAMERA: the 16:9 frame (scripts/shot_camera.gd). Outside the frame the view is
## darkened (Blender's passepartout, alpha 0.5), a thin line just OUTSIDE it marks the edge, a caption in its top-left
## corner names the lens (the playblast and a clean view hide all of it). Never takes the mouse.
class_name ShotFrame
extends Control

const PASSEPARTOUT := 0.5   # Blender's default passepartout alpha (docs/research/SHOT_CAMERA.md)
var rect := Rect2i()
var caption := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_rect(r: Rect2i, text: String) -> void:
	if r != rect or text != caption:
		rect = r
		caption = text
		queue_redraw()


func _draw() -> void:
	if rect.size.x <= 0:
		return
	var W := size.x
	var H := size.y
	var r := Rect2(rect)
	var scrim := Color(0, 0, 0, PASSEPARTOUT)   # darkens whatever is outside the frame, in both themes
	draw_rect(Rect2(0, 0, W, r.position.y), scrim)
	draw_rect(Rect2(0, r.end.y, W, H - r.end.y), scrim)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), scrim)
	draw_rect(Rect2(r.end.x, r.position.y, W - r.end.x, r.size.y), scrim)
	draw_rect(r.grow(1.0), Tok.c("focus"), false, 1.0)
	var font := get_theme_default_font()
	draw_string(font, r.position + Vector2(8, 18), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tok.c("focus"))
