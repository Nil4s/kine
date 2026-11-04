class_name TooltipFit
extends Node
## TOOLTIPS THAT FIT (C69): Godot's own tooltip is one unwrapped line per paragraph, so a long hint ran past the right edge
## of a 1024 px window ("...View only: no undo s") and over the buttons beside it. The whole app is fixed here, once: the
## moment the mouse rests on a control, its tooltip is wrapped at word boundaries to MAX_W px (less in a narrow window), and
## the engine's own placement then keeps that narrower box inside the window. No word is changed or dropped. The control's
## unwrapped text is kept in meta "tip_src" (the status-line hint and anyone else read that); Godot shows what is in tooltip_text.
const MAX_W := 420.0
const MARGIN := 48.0   # a tooltip's own padding plus the gap to the window edge
var last: Control


## the width a tip may use in a window this wide
static func cap_for(win_w: float) -> float:
	return clampf(win_w - MARGIN, 120.0, MAX_W)


## text wrapped at word boundaries so no line is wider than max_w (a single word wider than that stays whole). Lines already
## in the text (a title, "\n") stay breaks
static func wrap_text(text: String, font: Font, fsize: int, max_w: float) -> String:
	var out: PackedStringArray = []
	for para in text.split("\n"):
		var line := ""
		for w in para.split(" ", false):
			var cand := w if line == "" else line + " " + w
			if line != "" and font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > max_w:
				out.append(line)
				line = w
			else:
				line = cand
		out.append(line)
	return "\n".join(out)


## the unwrapped words of a control's tooltip (what the author wrote)
static func source_of(c: Control) -> String:
	var cur: String = c.tooltip_text
	if c.has_meta("tip_wrapped") and cur == String(c.get_meta("tip_wrapped")):
		return String(c.get_meta("tip_src"))
	return cur


## wrap c's tooltip for a window win_w wide (idempotent; a changed window or a new text re-wraps from the source)
func fit(c: Control, win_w: float) -> void:
	if c.tooltip_text == "":
		return
	var src := source_of(c)
	var font: Font = c.get_theme_font("font", "TooltipLabel")
	var fsize: int = c.get_theme_font_size("font_size", "TooltipLabel")
	var w := wrap_text(src, font, fsize, cap_for(win_w))
	if w == src:
		c.remove_meta("tip_wrapped")
		c.remove_meta("tip_src")
		c.tooltip_text = src
		return
	c.set_meta("tip_src", src)
	c.set_meta("tip_wrapped", w)
	c.tooltip_text = w


func _process(_dt: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var h := vp.gui_get_hovered_control()
	if h != last:
		if last != null and is_instance_valid(last) and last.has_meta("tip_wrapped"):   # left: the author's own text goes back
			last.tooltip_text = String(last.get_meta("tip_src"))
			last.remove_meta("tip_wrapped")
			last.remove_meta("tip_src")
		last = h
	if h != null:
		fit(h, vp.get_visible_rect().size.x)
