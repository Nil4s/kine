class_name MouseHint
extends Control
## ROADMAP_400 P05: "what do the mouse buttons do NOW", a compact strip just above the status line (Blender's bottom hint
## bar). Every text is read off the input paths it describes (main.gd _unhandled_input / _drag_joint / _wp_input /
## _sk_input, kmesh_edit_ui.gd input, timeline.gd _gui_input and hit); nothing here is a binding of its own.
## context(m, pos, over) says which situation the mouse is in, items(m, ctx) the [button, words] list for it, in
## priority order: when the strip is too narrow the LAST items are dropped, never clipped mid-word.

const H := 22
const GLYPH_W := 14
const GAP := 10
const FS := 12

var m: Node
var ctx := ""
var box: HBoxContainer
var _items: Array = []
var _sig := ""
var _t := 0.0
var _last_pos := Vector2(-1, -1)


## one mouse glyph: a rounded body, the named button lit ("L", "R", "M" wheel/middle), nothing lit for a key hint
class Glyph:
	extends Control
	var btn := ""

	func _init(b: String) -> void:
		btn = b
		custom_minimum_size = Vector2(GLYPH_W, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink := Tok.of("text:0.7")
		var lit := Tok.c("pick_hover")
		var r := Rect2(1, 1, GLYPH_W - 2, 16)
		var half := r.size.x * 0.5
		if btn == "L":
			draw_rect(Rect2(r.position.x, r.position.y, half, 7), lit, true)
		elif btn == "R":
			draw_rect(Rect2(r.position.x + half, r.position.y, half, 7), lit, true)
		elif btn == "M":
			draw_rect(Rect2(r.position.x + half - 1.5, r.position.y + 1, 3, 6), lit, true)
		draw_rect(r, ink, false, 1.0)
		draw_line(Vector2(r.position.x + half, r.position.y), Vector2(r.position.x + half, r.position.y + 7), ink, 1.0)
		draw_line(Vector2(r.position.x, r.position.y + 7), Vector2(r.end.x, r.position.y + 7), ink, 1.0)


func _init() -> void:
	name = "mouse_hint"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	box = HBoxContainer.new()
	box.name = "items"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", GAP)
	add_child(box)
	visible = false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tok.of("say_bg:0.55"), true)


## the throttle: at most one look at the mouse per 50 ms (main calls this from _process)
func tick(dt: float) -> void:
	_t += dt
	if _t < 0.05:
		return
	_t = 0.0
	refresh()


## look at the mouse now: the context under it, the strip updated (only when it changed)
func refresh(over_override: Variant = null, pos_override: Variant = null) -> void:
	if m == null:
		return
	var vp: Viewport = get_viewport()
	var pos: Vector2 = vp.get_mouse_position() if pos_override == null else pos_override
	var over: Control = vp.gui_get_hovered_control() if over_override == null else over_override
	show_ctx(context(m, pos, over))


func show_ctx(c: String) -> void:
	var its := items(m, c)
	var sig := c + "|" + str(its) + "|" + str(Tok.dark) + "|" + str(int(size.x))
	if sig == _sig:
		return
	_sig = sig
	ctx = c
	_items = its
	_rebuild()


func _rebuild() -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	var shown_any := false
	var font := get_theme_default_font()
	var used := 0.0
	var avail := maxf(size.x - 8.0, 0.0)
	for it in _items:
		var tw := font.get_string_size(String(it["t"]), HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x + 2.0
		var gw := GLYPH_W + 4.0 if String(it["b"]) != "" else 0.0
		var need := gw + tw + (GAP if shown_any else 0)
		var l := Label.new()
		l.text = String(it["t"])
		l.add_theme_font_size_override("font_size", FS)
		l.add_theme_color_override("font_color", Tok.of("text:0.85"))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if used + need > avail:
			if shown_any:
				l.free()
				break   # the rest does not fit: dropped, in priority order
			l.clip_text = true   # even the first one is wider than the strip: it is clipped, never wider
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.custom_minimum_size.x = maxf(avail - gw, 0.0)
			need = avail
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.name = "item_%d" % box.get_child_count()
		if String(it["b"]) != "":
			cell.add_child(Glyph.new(String(it["b"])))
		cell.add_child(l)
		box.add_child(cell)
		used += need
		shown_any = true
	visible = shown_any and (m.get("hints_on") != false) and not (m.ui_status != null and m.ui_status.text == m.WELCOME and m.ui_status.visible)
	queue_redraw()


## the words as shown (the test reads this)
func shown_text() -> String:
	var parts: Array = []
	for cell in box.get_children():
		for ch in cell.get_children():
			if ch is Label:
				parts.append((ch as Label).text)
	return "  ·  ".join(parts)


func fits() -> bool:
	return box.get_combined_minimum_size().x <= size.x + 0.5


# ---- which situation -------------------------------------------------------------------------------------------

static func _within(c: Control, root: Control) -> bool:
	return c != null and root != null and (c == root or root.is_ancestor_of(c))


## the situation id for the mouse at pos with `over` the GUI control under it (null = the 3D view)
static func context(m: Node, pos: Vector2, over: Control) -> String:
	var d: String = m.dragging
	if d != "":
		return "drag_" + d if d in ["joint", "orbit", "pan", "loa"] else "drag_other"
	var tl: Control = m.ui_timeline
	if tl != null and not (tl.get("_drag") as Dictionary).is_empty():
		return "tl_drag"
	var km = m.get("kmed")
	if km != null and km.on and km._drag:
		return "kmesh_drag"
	if m.sk.on:
		return "sketch"
	if over != null:
		if _within(over, tl):
			var h: Dictionary = (tl as Timeline).hit(pos - tl.get_global_rect().position)
			var kind := String(h.get("kind", ""))
			return "tl_" + (kind if kind in ["ruler", "block", "move", "hold", "edge0", "clip", "warp"] else "ruler")
		if _within(over, m.ui_card_row):
			return "cards"
		return ""
	if m.nav_tool != "":
		return "nav_" + String(m.nav_tool)
	if m.loa.armed:
		return "loa"
	if m.wp_on:
		return "weight" if m.wp_bind >= 0 else "weight_nobone"
	if km != null and km.on:
		return "kmesh_" + km.armed if km.armed != "" else "kmesh"
	var j: String = m._pick(pos)
	if j == "":
		return "pose_empty"
	m.set_meta("mh_part", j)
	if m.locked_parts.has(j):
		return "pose_locked"
	if j in Body.WEAPON:
		return "pose_weapon"
	if j in ["hand_r", "hand_l", "foot_r", "foot_l"]:
		return "pose_tip"
	if j == "pelvis":
		return "pose_pelvis"
	return "pose_part"


static func _i(b: String, t: String) -> Dictionary:
	return {"b": b, "t": t}


## the [button, words] list of one situation, most useful first
static func items(m: Node, c: String) -> Array:
	var part := String(m.get_meta("mh_part", "")) if m != null else ""
	var nm: String = m.nice(part) if part != "" else "part"
	var view := [_i("R", "Right: orbit"), _i("M", "Wheel: zoom"), _i("M", "Middle: pan")]
	match c:
		"pose_part":
			return [_i("L", "Left: drag to turn the %s" % nm), _i("R", "Right: orbit (a click: the part's menu)"), _i("M", "Wheel: zoom"),
				_i("L", "Shift+Left: roll it"), _i("L", "Ctrl+Left: add to the selection"), _i("M", "Middle: pan")]
		"pose_tip":
			var bend := "elbow" if part.begins_with("hand") else "knee"
			return [_i("L", "Left: drag to reach with the %s" % nm), _i("R", "Right: orbit (a click: the part's menu)"), _i("M", "Wheel: zoom"),
				_i("L", "Ctrl+Left: swing the %s" % bend), _i("M", "Middle: pan")]
		"pose_pelvis":
			return [_i("L", "Left: drag to turn the pelvis"), _i("R", "Right: orbit (a click: the part's menu)"), _i("M", "Wheel: zoom"),
				_i("L", "Ctrl+Left: move the whole body"), _i("M", "Middle: pan")]
		"pose_weapon":
			return [_i("L", "Left: drag to swing the %s" % nm), _i("R", "Right: orbit (a click: the part's menu)"), _i("M", "Wheel: zoom"), _i("M", "Middle: pan")]
		"pose_locked":
			return [_i("L", "Left: picks the %s (it is locked, it will not turn)" % nm), _i("R", "Right: orbit (a click: Unlock)"), _i("M", "Wheel: zoom")]
		"pose_empty":
			return [_i("L", "Left: nothing here, press a part to pick it"), _i("R", "Right: orbit"), _i("M", "Wheel: zoom"), _i("M", "Middle: pan")]
		"nav_orbit":
			return [_i("L", "Left: drag to orbit the view"), _i("M", "Wheel: zoom"), _i("", "Esc: back to posing")]
		"nav_pan":
			return [_i("L", "Left: drag to pan the view"), _i("M", "Wheel: zoom"), _i("", "Esc: back to posing")]
		"loa":
			return [_i("L", "Left: drag a line of action over the figure"), _i("R", "Right: cancel the line"), _i("M", "Wheel: zoom")]
		"weight":
			return [_i("L", "Left: drag over the body to paint (%s)" % String(m.wp_mode)), _i("R", "Right: orbit"), _i("M", "Wheel: zoom"), _i("M", "Middle: pan")]
		"weight_nobone":
			return [_i("L", "Left: pick a bone first (the Bone list)"), _i("R", "Right: orbit"), _i("M", "Wheel: zoom")]
		"kmesh":
			return [_i("L", "Left: click an element to select, drag from empty space for a box"), _i("L", "Shift+Left: add"), _i("R", "Right: orbit"), _i("M", "Wheel: zoom"), _i("M", "Middle: pan")]
		"kmesh_box":
			return [_i("L", "Left: drag a rectangle to box select"), _i("L", "Shift+Left: add"), _i("", "Esc: cancel"), _i("R", "Right: orbit")]
		"kmesh_lasso":
			return [_i("L", "Left: drag a loop to lasso select"), _i("L", "Shift+Left: add"), _i("", "Esc: cancel"), _i("R", "Right: orbit")]
		"kmesh_drag":
			return [_i("L", "Release: select what is inside"), _i("", "Esc: cancel")]
		"sketch":
			return [_i("L", "Left: drag to draw a stroke"), _i("", "Enter: fit the body"), _i("", "Backspace: last stroke"), _i("", "Esc: leave")]
		"drag_joint":
			return [_i("L", "Release: keep the pose"), _i("", "Esc: cancel the drag"), _i("", "Type a number: exact angle (Tab: next axis, Enter: keep)")]
		"drag_orbit":
			return [_i("R", "Release: stop turning (a click without moving opens the menu)"), _i("M", "Wheel: zoom")]
		"drag_pan":
			return [_i("M", "Release: stop sliding the view"), _i("M", "Wheel: zoom")]
		"drag_loa":
			return [_i("L", "Release: bend the body to the line (Shift: mirrored)")]
		"drag_other":
			return [_i("L", "Release: drop it here")]
		"tl_ruler":
			return [_i("L", "Left: click or drag to scrub"), _i("L", "Shift+Left: set the range start"), _i("L", "Alt+Left: set the range end")]
		"tl_block":
			return [_i("L", "Left: pick this card")]
		"tl_move":
			return [_i("L", "Left: drag to retime the move into this card"), _i("L", "Shift: fine steps"), _i("L", "Alt: move only the gap")]
		"tl_hold":
			return [_i("L", "Left: drag to change this card's hold"), _i("L", "Shift: fine steps"), _i("L", "Alt: move only the gap")]
		"tl_edge0":
			return [_i("L", "Left: drag right to pull out a hold, left to shorten the move"), _i("L", "Shift: fine steps")]
		"tl_clip":
			return [_i("L", "Left: drag the clip"), _i("L", "Shift: fine steps")]
		"tl_warp":
			return [_i("L", "Left: drag a knot of the time curve"), _i("R", "Right: take the knot out")]
		"tl_drag":
			return [_i("L", "Release: set it here"), _i("L", "Shift: fine steps")]
		"cards":
			return [_i("L", "Left: show the card, drag to move it, double-click to rename"), _i("R", "Right: more")]
	return []
