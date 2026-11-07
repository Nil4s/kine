## ACCESSIBILITY (ROADMAP_400 P16, lane L111): a font scale for every text control, and a colour-blind-safe set of selection colours.
##  Access.set_font_scale(root, 1.5): every Label / Button / LineEdit / CheckBox under root (and any added later) gets round(base * f) as its
##    font size; a text control that would then be wider than itself gets a minimum width that fits its text (so nothing clips). 1.0 undoes it.
##  Access.set_colourblind(true): the selection / hover / card / button-state colours become ones that differ in LIGHTNESS and in the blue-orange
##    axis (the axis all three common colour-vision deficiencies keep), so selected / hovered / plain stay apart without telling red from green.
##    Laid over Tok's two palettes (tok.gd is not edited); false puts the originals back. Checked by tests/access_test.gd.
class_name Access
extends RefCounted

const CB_DARK := {
	"pick_sel": Color(0.0, 0.35, 0.7), "pick_hover": Color(0.9, 0.6, 0.0),
	"card_sel": Color(0.0, 0.35, 0.7), "card_passby": Color(0.62, 0.4, 0.0),
	"btn_hover": Color(0.42, 0.44, 0.52),
}
const CB_LIGHT := {
	"pick_sel": Color(0.0, 0.3, 0.65), "pick_hover": Color(0.9, 0.55, 0.0),
	"card_sel": Color(0.4, 0.58, 0.88), "card_passby": Color(0.95, 0.78, 0.4),
	"btn_hover": Color(0.62, 0.66, 0.74),
}
static var scale := 1.0
static var cb := false
static var _saved_dk := {}
static var _saved_lt := {}
static var _root: Node = null
static var _hooked := false


static func set_colourblind(on: bool) -> void:
	if on == cb:
		return
	if on:
		for k in CB_DARK:
			_saved_dk[k] = Tok._dk[k]
			Tok._dk[k] = CB_DARK[k]
		for k in CB_LIGHT:
			_saved_lt[k] = Tok._lt[k]
			Tok._lt[k] = CB_LIGHT[k]
	else:
		for k in _saved_dk:
			Tok._dk[k] = _saved_dk[k]
		for k in _saved_lt:
			Tok._lt[k] = _saved_lt[k]
		_saved_dk = {}
		_saved_lt = {}
	cb = on


static func _is_text(c: Node) -> bool:
	return c is Label or c is Button or c is LineEdit


static func _apply_one(c: Control, f: float) -> void:
	if not c.has_meta("_acc_base"):
		c.set_meta("_acc_base", c.get_theme_font_size("font_size"))
		c.set_meta("_acc_had", c.has_theme_font_size_override("font_size"))
		c.set_meta("_acc_minx", c.custom_minimum_size.x)
	var base: int = c.get_meta("_acc_base")
	if absf(f - 1.0) < 1e-6:
		if c.get_meta("_acc_had"):
			c.add_theme_font_size_override("font_size", base)
		else:
			c.remove_theme_font_size_override("font_size")
		c.custom_minimum_size.x = c.get_meta("_acc_minx")
		return
	c.add_theme_font_size_override("font_size", int(round(base * f)))


static func _text_w(c: Control) -> float:
	return c.get_theme_font("font").get_string_size(String(c.get("text")), HORIZONTAL_ALIGNMENT_LEFT, -1, c.get_theme_font_size("font_size")).x


## widens (a minimum width) any single-line text control whose text is wider than the control
static func _guard(root: Node) -> void:
	for c in root.find_children("*", "Control", true, false):
		var cc := c as Control
		if not _is_text(cc) or String(cc.get("text")) == "" or not cc.is_visible_in_tree():
			continue
		if cc is Label and (cc as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			continue
		var w := _text_w(cc)
		if w > cc.size.x + 0.5:
			var pad := 0.0
			if cc is Button:
				var sb := cc.get_theme_stylebox("normal")
				pad = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
			cc.custom_minimum_size.x = maxf(cc.custom_minimum_size.x, ceil(w + pad + 2.0))
			if cc is Label:
				(cc as Label).clip_text = false
				(cc as Label).text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			elif cc is Button:
				(cc as Button).clip_text = false


static func set_font_scale(root: Node, f: float) -> void:
	scale = clampf(f, 0.5, 3.0)
	_root = root
	for c in root.find_children("*", "Control", true, false):
		if _is_text(c):
			_apply_one(c as Control, scale)
	if not _hooked:
		_hooked = true
		root.get_tree().node_added.connect(_on_added)
	if absf(scale - 1.0) < 1e-6:
		return
	var tree := root.get_tree()
	for i in 3:   # let the containers lay out at the new size, then widen what still does not fit (twice: widening moves its neighbours)
		await tree.process_frame
		if is_instance_valid(root):
			_guard(root)


static func _on_added(n: Node) -> void:
	if _root != null and is_instance_valid(_root) and _is_text(n) and absf(scale - 1.0) > 1e-6 and _root.is_ancestor_of(n):
		_apply_one.call_deferred(n as Control, scale)
