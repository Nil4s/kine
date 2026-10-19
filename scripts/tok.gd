## THE UI'S LOOK IN ONE PLACE (round 9, GATES P2/P3): every colour of the chrome (panels, buttons, text, the 2D
## widgets that draw themselves) is a named token here, in two palettes. Tok.c("text") is the colour now;
## Tok.dim(a) is body text at a strength (0..1) that stays readable in both palettes. Switching the palette is
## Tok.set_dark(); main re-tints what it built and the widgets read Tok on every draw.
## Not here: the 3D scene's own materials (skin, weapon, dummy) and the overlays' motion colours: they are content.
class_name Tok
extends RefCounted

const DARK := {
	"text": Color(1, 1, 1), "heading": Color(0.6, 0.78, 1.0), "info": Color(0.75, 0.9, 1.0), "say": Color(1.0, 0.9, 0.55),
	"warn": Color(1.0, 0.86, 0.5), "fail": Color(1.0, 0.55, 0.5), "dummy": Color(1.0, 0.6, 0.5), "dummy_text": Color(1.0, 0.8, 0.75),
	"panel": Color(0.085, 0.09, 0.105, 0.94), "float": Color(0.09, 0.1, 0.12, 0.94), "say_bg": Color(0.05, 0.05, 0.07, 0.85),
	"btn": Color(0.19, 0.21, 0.25), "btn_hover": Color(0.26, 0.3, 0.37), "accent": Color(0.2, 0.42, 0.75), "on_accent": Color(1, 1, 1), "focus": Color(1.0, 0.78, 0.2),
	"btn_text": Color(0.875, 0.875, 0.875), "field": Color(0.1, 0.11, 0.13),
	"card": Color(0.16, 0.17, 0.2), "card_sel": Color(0.2, 0.36, 0.62), "card_passby": Color(0.25, 0.2, 0.12), "card_play": Color(0.95, 0.8, 0.3), "card_play_bg": Color(0.22, 0.25, 0.31),
	"graph_bg": Color(0.07, 0.08, 0.1, 0.9), "ink": Color(1, 1, 1), "hair": Color(0.42, 0.26, 0.13),
	"world": Color(0.11, 0.115, 0.13), "floor": Color(0.13, 0.135, 0.15), "grid": Color(0.19, 0.2, 0.23), "grid_major": Color(0.32, 0.33, 0.37),
	"tl_bg": Color(0.07, 0.08, 0.1), "s_tip": Color(1.0, 0.55, 0.3), "s_hips": Color(0.45, 0.75, 1.0), "s_head": Color(0.75, 0.9, 0.5),
	"cube": Color(0.55, 0.62, 0.75), "cube_edge": Color(0.9, 0.93, 1.0),
	"ch_x": Color(1.0, 0.42, 0.4), "ch_y": Color(0.45, 0.85, 0.45), "ch_z": Color(0.45, 0.65, 1.0),
	"beat_down": Color(1.0, 0.8, 0.35, 0.95), "vdiff": Color(0.85, 0.3, 0.95, 0.9),   # timeline: the downbeats, the compared version's differing frames
	"autokey": Color(1.0, 0.25, 0.22), "onion_past": Color(1.0, 0.62, 0.22), "onion_future": Color(0.35, 0.9, 0.85), "fd_startup": Color(0.3, 0.78, 0.38), "fd_active": Color(0.92, 0.28, 0.26), "fd_recovery": Color(0.3, 0.52, 0.95), "fd_ink": Color(0.05, 0.05, 0.07),   # the frame strip   # XX2 curve editor: bend / side / twist
	"kt_break": Color(1.0, 0.8, 0.35), "kt_between": Color(0.7, 0.85, 1.0),   # ROADMAP 66: part key types (breakdown, in-between)
	"pick_sel": Color(0.25, 0.55, 1.0), "pick_hover": Color(0.5, 0.75, 1.0), "pick_lock": Color(0.5, 0.5, 0.55),   # PRECISE PICK: a part's light on its own skin
	"pick_touch": Color(1.0, 0.25, 0.2), "pick_limit": Color(1.0, 0.82, 0.15),
	"mk_red": Color(0.95, 0.3, 0.25), "mk_green": Color(0.35, 0.75, 0.4), "mk_blue": Color(0.35, 0.65, 0.95), "mk_gold": Color(0.9, 0.8, 0.3),
	"mk_panel": Color(0.09, 0.095, 0.11, 1.0), "mk_border": Color(0.5, 0.56, 0.68, 1.0),
}
const LIGHT := {
	"text": Color(0.1, 0.11, 0.13), "heading": Color(0.08, 0.3, 0.68), "info": Color(0.12, 0.27, 0.5), "say": Color(0.42, 0.27, 0.0),
	"warn": Color(0.5, 0.32, 0.0), "fail": Color(0.7, 0.12, 0.08), "dummy": Color(0.62, 0.2, 0.12), "dummy_text": Color(0.5, 0.2, 0.15),
	"panel": Color(0.955, 0.957, 0.965, 0.96), "float": Color(0.97, 0.97, 0.975, 0.97), "say_bg": Color(1.0, 0.97, 0.88, 0.94),
	"btn": Color(0.87, 0.88, 0.9), "btn_hover": Color(0.8, 0.83, 0.88), "accent": Color(0.16, 0.4, 0.8), "on_accent": Color(1, 1, 1), "focus": Color(0.72, 0.3, 0.0),
	"btn_text": Color(0.1, 0.11, 0.13), "field": Color(1, 1, 1),
	"card": Color(0.9, 0.91, 0.93), "card_sel": Color(0.7, 0.8, 0.96), "card_passby": Color(0.95, 0.88, 0.75), "card_play": Color(0.75, 0.45, 0.0), "card_play_bg": Color(0.82, 0.86, 0.93),
	"graph_bg": Color(0.97, 0.97, 0.98, 0.94), "ink": Color(0.1, 0.11, 0.13), "hair": Color(0.3, 0.17, 0.08),
	"world": Color(0.72, 0.74, 0.77), "floor": Color(0.66, 0.68, 0.71), "grid": Color(0.6, 0.62, 0.65), "grid_major": Color(0.48, 0.5, 0.54),
	"tl_bg": Color(0.86, 0.87, 0.9), "s_tip": Color(0.8, 0.35, 0.05), "s_hips": Color(0.1, 0.38, 0.8), "s_head": Color(0.25, 0.5, 0.05),
	"cube": Color(0.8, 0.84, 0.9), "cube_edge": Color(0.25, 0.3, 0.4),
	"ch_x": Color(0.78, 0.12, 0.1), "ch_y": Color(0.1, 0.5, 0.12), "ch_z": Color(0.12, 0.3, 0.8),
	"beat_down": Color(0.78, 0.5, 0.0, 0.95), "vdiff": Color(0.62, 0.1, 0.72, 0.9),
	"autokey": Color(0.82, 0.08, 0.08), "onion_past": Color(0.85, 0.4, 0.05), "onion_future": Color(0.0, 0.5, 0.48), "fd_startup": Color(0.12, 0.55, 0.22), "fd_active": Color(0.8, 0.16, 0.14), "fd_recovery": Color(0.15, 0.38, 0.82), "fd_ink": Color(1, 1, 1),
	"kt_break": Color(0.75, 0.48, 0.0), "kt_between": Color(0.12, 0.36, 0.7),
	"pick_sel": Color(0.1, 0.4, 0.95), "pick_hover": Color(0.3, 0.6, 1.0), "pick_lock": Color(0.35, 0.35, 0.4),
	"pick_touch": Color(0.9, 0.12, 0.1), "pick_limit": Color(0.95, 0.68, 0.0),
	"mk_red": Color(0.8, 0.14, 0.1), "mk_green": Color(0.15, 0.55, 0.22), "mk_blue": Color(0.12, 0.4, 0.85), "mk_gold": Color(0.7, 0.55, 0.0),
	"mk_panel": Color(0.985, 0.985, 0.99, 1.0), "mk_border": Color(0.38, 0.42, 0.5, 1.0),
}

static var dark := true


static func c(name: String) -> Color:
	return (DARK if dark else LIGHT)[name]


## body text at strength a (1 = full, 0.6 = a side note): mixed toward the panel colour, not made transparent, and
## never past the point where it stops being readable (light text on light needs a smaller step than dark)
static func dim(a: float) -> Color:
	var t := c("text")
	var bg := c("panel")
	var k := maxf(clampf(a, 0.0, 1.0), 0.5) if dark else lerpf(0.72, 1.0, clampf(a, 0.0, 1.0))   # the floors: 4.5:1 (theme_test)
	return Color(bg.r + (t.r - bg.r) * k, bg.g + (t.g - bg.g) * k, bg.b + (t.b - bg.b) * k)


## a token name with an optional strength ("text:0.6") -> its colour now
static func of(tok: String) -> Color:
	var p := tok.split(":")
	if p.size() == 2:
		return dim(float(p[1])) if p[0] == "text" else Color(c(p[0]), float(p[1]))
	return c(tok)


static func set_dark(on: bool) -> void:
	dark = on


## WCAG contrast ratio of two opaque colours (>= 4.5 = readable body text)
static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _lum(x: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(x.r) + 0.7152 * f.call(x.g) + 0.0722 * f.call(x.b)
