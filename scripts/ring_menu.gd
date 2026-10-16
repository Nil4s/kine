## MARKING MENU (round 7, Fusion 360's right-click ring). Right-CLICK a body part (right-DRAG still turns the view):
## a ring of actions around the mouse, each in its own direction, so the hand learns "reset = up" and stops reading.
## Click a wedge to run it; click the middle, outside, or Esc to cancel. Godot's PopupMenu is a list; a ring is the point.
class_name RingMenu
extends Control

const R_IN := 26.0    # the dead middle (cancel)
const R_OUT := 118.0  # past this = outside (cancel)
const R_TXT := 82.0

## each: {"name": String, "run": Callable}; item 0 is straight up, then clockwise
var items: Array = []
var at := Vector2.ZERO
var title := ""
var hover := -1


func _ready() -> void:
	# AND offsets: set_anchors_preset alone keeps the size it had (0 x 0): it drew, but no click could reach it
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL   # Esc reaches a Control only with the keyboard on it
	visible = false


## top: keep the ring (and its title above it) below this many pixels from the screen's top (the top bar)
var top_margin := 0.0


func open(p: Vector2, head: String, its: Array) -> void:
	# near an edge the ring moves in, so all of it and its title are on screen (a part high up opened it on the top bar)
	var vs := get_viewport_rect().size
	at = Vector2(clampf(p.x, R_OUT + 6.0, vs.x - R_OUT - 6.0), clampf(p.y, top_margin + R_OUT + 30.0, vs.y - R_OUT - 6.0))
	title = head
	items = its
	hover = -1
	visible = true
	grab_focus()
	queue_redraw()


func close() -> void:
	visible = false
	release_focus()


## the wedge under p (-1 = the middle or outside)
func wedge(p: Vector2) -> int:
	var d := p - at
	if d.length() < R_IN or d.length() > R_OUT or items.is_empty():
		return -1
	var a := fposmod(atan2(d.x, -d.y) + PI / items.size(), TAU)   # 0 = up, clockwise
	return int(a / (TAU / items.size())) % items.size()


## the direction of wedge i's middle (0 = up, clockwise)
func dir(i: int) -> Vector2:
	var a := TAU * i / items.size()
	return Vector2(sin(a), -cos(a))


func _draw() -> void:
	var n := items.size()
	draw_circle(at, R_OUT, Color(Tok.c("float"), 0.97))   # near-opaque: the 3D part label showed through
	for i in n:
		var a0 := TAU * (i - 0.5) / n - PI / 2.0
		var pts := PackedVector2Array()
		for k in 17:
			var a := a0 + TAU / n * k / 16.0
			pts.append(at + Vector2(cos(a), sin(a)) * (R_OUT - 4.0))
		for k in 17:
			var a := a0 + TAU / n * (16 - k) / 16.0
			pts.append(at + Vector2(cos(a), sin(a)) * (R_IN + 4.0))
		draw_colored_polygon(pts, Tok.c("accent") if i == hover else Tok.c("btn"))
	draw_arc(at, R_IN, 0.0, TAU, 32, Tok.of("ink:0.5"), 1.5, true)
	var font := get_theme_default_font()
	for i in n:
		var t: String = items[i]["name"]
		var lines := t.split("\n")
		var c := at + dir(i) * R_TXT
		for li in lines.size():
			var w := font.get_string_size(lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, c + Vector2(-w * 0.5, 5.0 + (li - (lines.size() - 1) * 0.5) * 16.0), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tok.c("on_accent") if i == hover else Tok.c("btn_text"))
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, at + Vector2(-tw * 0.5, -R_OUT - 10.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Tok.c("heading"))


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := wedge((ev as InputEventMouseMotion).position)
		if h != hover:
			hover = h
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed:
		var i := wedge((ev as InputEventMouseButton).position) if (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT else -1
		close()
		accept_event()
		if i >= 0:
			(items[i]["run"] as Callable).call()
	elif ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		close()
		accept_event()
