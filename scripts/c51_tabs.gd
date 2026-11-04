class_name C51Tabs
extends RefCounted
## C51: a page tab in a narrow cell (the 72 px floor at 1024x600) drops its icon, trims its side margins and uses a smaller font so its NAME still fits
## (English and pt_BR); at 84 px and wider (1280x720, 1920x1080) nothing changes.
const NARROW_BELOW := 84.0

static func apply(p: String, b: Button, cell_w: float) -> void:
	var narrow := cell_w < NARROW_BELOW
	if narrow:
		b.icon = null
		var sb := b.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 3
			sb.content_margin_right = 3
			for st in ["normal", "hover", "pressed", "hover_pressed"]:
				var s2 := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
				if s2 != null:
					s2.content_margin_left = 3
					s2.content_margin_right = 3
					b.add_theme_stylebox_override(st, s2)
		b.add_theme_font_size_override("font_size", 11)
		b.set_meta("c51_narrow", true)
	else:
		if b.has_meta("c51_narrow") or b.has_meta("c56_fit"):
			b.remove_meta("c51_narrow")
			b.remove_meta("c56_fit")
			b.icon = Icons.tex("page_" + p.to_lower())
			for st in ["normal", "hover", "pressed", "hover_pressed"]:
				b.remove_theme_stylebox_override(st)
			b.remove_theme_font_size_override("font_size")
		# C56: at 84 px and wider a tab whose own icon + name is still wider than its cell (English ANIMATE 100 in 96, SURFACE 98 in 96)
		# first trims its side margins, then drops its icon; a tab that already fits is not touched (font size never changes)
		if b.get_minimum_size().x > cell_w + 0.5:
			_margins(b, 3)
			b.set_meta("c56_fit", true)
			if b.get_minimum_size().x > cell_w + 0.5:
				b.icon = null

static func _margins(b: Button, m: int) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var s2 := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		if s2 != null:
			s2.content_margin_left = m
			s2.content_margin_right = m
			b.add_theme_stylebox_override(st, s2)
