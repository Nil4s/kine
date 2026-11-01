extends RefCounted
## LIGHT / DARK for the Part page (Friday plan 109). The Easy Part boxes are drawn with their own dark literals (Color(0.1, 0.11, 0.14 ...)), so
## the app-wide Tok switch did not reach them. Dark is the current look EXACTLY: every box keeps its original colour (kept in the stylebox's
## meta "ep_orig", the label's "ep_font") and a switch back to Dark puts those back. Light maps each dark fill to the Light palette's panel / card /
## button tiers by its brightness, and light-on-dark text to the Light palette's text. Coloured fills (amber, sky, the colour chips) stay.
## EasyPart._style() calls map_fill() for every box it builds, and retint() walks the boxes already built when the choice changes.
const FONT_NAMES := ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]


static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## a dark fill c as it should look now: itself in Dark, the Light palette's tier for it in Light
static func map_fill(c: Color) -> Color:
	if Tok.dark:
		return c
	var l := _lum(c)
	if l > 0.45:
		return c   # a colour chip, the amber action or a sky link: kept
	var key := "panel" if l < 0.115 else ("card" if l < 0.15 else ("btn" if l < 0.21 else "btn_hover"))
	var t: Color = Tok.LIGHT[key]
	return Color(t.r, t.g, t.b, maxf(c.a, 0.92))


## light text on a dark box becomes the Light palette's text (a blue link its deep blue); dark text stays
static func map_font(c: Color) -> Color:
	if Tok.dark or _lum(c) < 0.45:
		return c
	if c.b > c.r + 0.15 and c.b > 0.7:
		return Tok.LIGHT["heading"]
	return Tok.LIGHT["text"]


## every box and label under n takes the colours for the palette now (Dark gives the originals back)
static func retint(n: Node) -> void:
	if n is Control:
		var ctl := n as Control
		for sn in ["panel", "normal", "hover", "pressed", "disabled", "focus", "hover_pressed", "fill", "background", "slider", "grabber_area", "grabber_area_highlight"]:
			if not ctl.has_theme_stylebox_override(sn):
				continue
			var sb := ctl.get_theme_stylebox(sn)
			if not (sb is StyleBoxFlat):
				continue
			var fl := sb as StyleBoxFlat
			if not fl.has_meta("ep_orig"):
				fl.set_meta("ep_orig", fl.bg_color)
			fl.bg_color = map_fill(fl.get_meta("ep_orig"))
		var pill := n is Label and ctl.has_theme_stylebox_override("normal") and ctl.get_theme_stylebox("normal") is StyleBoxFlat
		if pill:   # a text on its own box (the size line, a pill): the text colour follows the box it sits on, so it can never vanish into it
			if Tok.dark:
				if ctl.has_meta("ep_pill"):
					var pr: Dictionary = ctl.get_meta("ep_pill")
					if bool(pr["had"]):
						ctl.add_theme_color_override("font_color", pr["c"])
					else:
						ctl.remove_theme_color_override("font_color")
					ctl.remove_meta("ep_pill")
			else:
				if not ctl.has_meta("ep_pill"):
					ctl.set_meta("ep_pill", {"had": ctl.has_theme_color_override("font_color") and not ctl.has_meta("ep_lab"), "c": ctl.get_theme_color("font_color")})
				var bgc := (ctl.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
				ctl.add_theme_color_override("font_color", Tok.LIGHT["text"] if _lum(bgc) > 0.5 else Color(0.92, 0.94, 0.97))
				ctl.remove_meta("ep_lab") if ctl.has_meta("ep_lab") else null
		elif n is Label:
			if ctl.has_meta("ep_lab"):   # a colour this file gave (Light); Dark takes it away again
				if Tok.dark:
					ctl.remove_theme_color_override("font_color")
					ctl.remove_meta("ep_lab")
			elif not Tok.dark and not ctl.has_theme_color_override("font_color"):   # no colour of its own reads the app's default (white): the Light palette's text instead
				ctl.add_theme_color_override("font_color", Tok.LIGHT["text"])
				ctl.set_meta("ep_lab", true)
		var orig: Dictionary = ctl.get_meta("ep_font") if ctl.has_meta("ep_font") else {}
		for fn in FONT_NAMES:
			if pill or ctl.has_meta("ep_lab") or not ctl.has_theme_color_override(fn):
				continue
			if not orig.has(fn):
				orig[fn] = ctl.get_theme_color(fn)
			ctl.add_theme_color_override(fn, map_font(orig[fn]))
		if not orig.is_empty():
			ctl.set_meta("ep_font", orig)
	for c in n.get_children():
		retint(c)
