## THE UI'S LOOK IN ONE PLACE (round 9, GATES P2/P3): every colour of the chrome (panels, buttons, text, the 2D
## widgets that draw themselves) is a named token here, in two palettes. Tok.c("text") is the colour now;
## Tok.dim(a) is body text at a strength (0..1) that stays readable in both palettes. Switching the palette is
## Tok.set_dark(); main re-tints what it built and the widgets read Tok on every draw.
## Not here: the 3D scene's own materials (skin, weapon, dummy) and the overlays' motion colours: they are content.
class_name Tok
extends RefCounted

const DARK := {
	"text": Color(0.925, 0.937, 0.957), "heading": Color(1.0, 0.78, 0.2), "info": Color(0.77, 0.8, 0.85), "say": Color(1.0, 0.85, 0.42),
	"ok": Color(0.48, 0.85, 0.55),   # N064 ouch meter: inside the comfortable range (with warn / fail)
	"warn": Color(1.0, 0.78, 0.2), "fail": Color(1.0, 0.48, 0.42), "dummy": Color(1.0, 0.6, 0.5), "dummy_text": Color(1.0, 0.8, 0.75),
	"panel": Color(0.086, 0.09, 0.106, 0.94), "float": Color(0.118, 0.125, 0.149, 0.94), "say_bg": Color(0.055, 0.06, 0.07, 0.85),
	"btn": Color(0.165, 0.176, 0.212), "btn_hover": Color(0.23, 0.245, 0.29), "main": Color(1.0, 0.78, 0.2), "accent": Color(1.0, 0.78, 0.2), "on_accent": Color(0.102, 0.11, 0.129), "focus": Color(0.45, 0.75, 1.0),
	"btn_text": Color(0.925, 0.937, 0.957), "field": Color(0.059, 0.063, 0.078),
	"card": Color(0.118, 0.125, 0.149), "card_sel": Color(0.12, 0.23, 0.32), "card_passby": Color(0.23, 0.17, 0.06), "card_play": Color(1.0, 0.78, 0.2), "card_multi": Color(1.0, 0.62, 0.11), "card_play_bg": Color(0.165, 0.176, 0.212),
	"graph_bg": Color(0.07, 0.08, 0.1, 0.9), "ink": Color(0.925, 0.937, 0.957), "hair": Color(0.35, 0.25, 0.08),
	"world": Color(0.11, 0.115, 0.13), "floor": Color(0.13, 0.135, 0.15), "grid": Color(0.19, 0.2, 0.23), "grid_major": Color(0.32, 0.33, 0.37),
	"tl_bg": Color(0.07, 0.08, 0.1), "s_tip": Color(1.0, 0.55, 0.3), "s_hips": Color(0.45, 0.75, 1.0), "s_head": Color(0.75, 0.9, 0.5),
	"cube": Color(0.55, 0.62, 0.75), "cube_edge": Color(0.9, 0.93, 1.0),
	"ch_x": Color(1.0, 0.42, 0.4), "ch_y": Color(0.45, 0.85, 0.45), "ch_z": Color(0.45, 0.65, 1.0),
	"beat_down": Color(1.0, 0.8, 0.35, 0.95), "vdiff": Color(0.85, 0.3, 0.95, 0.9),
	"sg_habit": Color(1.0, 0.82, 0.2), "sg_motion": Color(0.62, 0.52, 1.0), "sg_phase": Color(1.0, 0.45, 0.62), "sg_between": Color(0.4, 0.9, 0.55), "card_usual": Color(0.45, 0.9, 0.7),   # R27 next-pose ghosts: your habit (gold), real motion (violet), move phase (rose)   # timeline: the downbeats, the compared version's differing frames
	"autokey": Color(1.0, 0.25, 0.22), "onion_past": Color(1.0, 0.62, 0.22), "onion_future": Color(0.35, 0.9, 0.85), "fd_startup": Color(0.3, 0.78, 0.38), "fd_active": Color(0.92, 0.28, 0.26), "fd_recovery": Color(0.3, 0.52, 0.95), "fd_ink": Color(0.05, 0.05, 0.07), "fd_tint": Color(0.66, 0.28, 0.28),   # the frame strip (fd_tint: the wash of a multi-hit span's gaps, POL1106b)   # XX2 curve editor: bend / side / twist
	"kt_break": Color(1.0, 0.8, 0.35), "kt_between": Color(0.7, 0.85, 1.0),   # ROADMAP 66: part key types (breakdown, in-between)
	"pick_sel": Color(0.25, 0.55, 1.0), "pick_hover": Color(0.5, 0.75, 1.0), "pick_lock": Color(0.5, 0.5, 0.55),   # PRECISE PICK: a part's light on its own skin
	"pick_touch": Color(1.0, 0.25, 0.2), "pick_limit": Color(1.0, 0.82, 0.15),
	"judge_force": Color(1.0, 0.2, 0.85), "judge_limit": Color(1.0, 0.08, 0.08),   # K23 breakdown video: the ground-force arrow, the joint-limit markers
	"fv_ok": Color(0.3, 0.8, 0.4), "fv_mid": Color(0.98, 0.8, 0.2), "fv_hot": Color(0.95, 0.25, 0.2),   # FORCE VIEW (I8): torque / strong-human limit
	"mk_red": Color(0.95, 0.3, 0.25), "mk_green": Color(0.35, 0.75, 0.4), "mk_blue": Color(0.35, 0.65, 0.95), "mk_gold": Color(0.9, 0.8, 0.3),
	"fp_1": Color(0.95, 0.62, 0.25), "fp_2": Color(0.4, 0.7, 1.0), "fp_3": Color(0.5, 0.88, 0.55), "fp_4": Color(0.95, 0.5, 0.75),   # I42 floor plan: one colour per fighter
	"mk_panel": Color(0.09, 0.095, 0.11, 1.0), "mk_border": Color(0.5, 0.56, 0.68, 1.0),
	"body_clay": Color("D8DCE3"), "body_outline": Color("73BFFF"),   # THE BODY LOOK (matte clay + a thin sky outline); the clay is BODY_COLOURS[0]
}
const LIGHT := {
	"text": Color(0.1, 0.11, 0.13), "heading": Color(0.08, 0.3, 0.68), "info": Color(0.12, 0.27, 0.5), "say": Color(0.42, 0.27, 0.0),
	"ok": Color(0.08, 0.45, 0.16),
	"warn": Color(0.5, 0.32, 0.0), "fail": Color(0.7, 0.12, 0.08), "dummy": Color(0.62, 0.2, 0.12), "dummy_text": Color(0.5, 0.2, 0.15),
	"panel": Color(0.955, 0.957, 0.965, 0.96), "float": Color(0.97, 0.97, 0.975, 0.97), "say_bg": Color(1.0, 0.97, 0.88, 0.94),
	"btn": Color(0.87, 0.88, 0.9), "btn_hover": Color(0.8, 0.83, 0.88), "main": Color(0.87, 0.88, 0.9), "accent": Color(0.16, 0.4, 0.8), "on_accent": Color(1, 1, 1), "focus": Color(0.72, 0.3, 0.0),
	"btn_text": Color(0.1, 0.11, 0.13), "field": Color(1, 1, 1),
	"card": Color(0.9, 0.91, 0.93), "card_sel": Color(0.7, 0.8, 0.96), "card_passby": Color(0.95, 0.88, 0.75), "card_play": Color(0.75, 0.45, 0.0), "card_multi": Color(0.9, 0.35, 0.0), "card_play_bg": Color(0.82, 0.86, 0.93),
	"graph_bg": Color(0.97, 0.97, 0.98, 0.94), "ink": Color(0.1, 0.11, 0.13), "hair": Color(0.3, 0.17, 0.08),
	"world": Color(0.72, 0.74, 0.77), "floor": Color(0.66, 0.68, 0.71), "grid": Color(0.6, 0.62, 0.65), "grid_major": Color(0.48, 0.5, 0.54),
	"tl_bg": Color(0.86, 0.87, 0.9), "s_tip": Color(0.8, 0.35, 0.05), "s_hips": Color(0.1, 0.38, 0.8), "s_head": Color(0.25, 0.5, 0.05),
	"cube": Color(0.8, 0.84, 0.9), "cube_edge": Color(0.25, 0.3, 0.4),
	"ch_x": Color(0.78, 0.12, 0.1), "ch_y": Color(0.1, 0.5, 0.12), "ch_z": Color(0.12, 0.3, 0.8),
	"beat_down": Color(0.78, 0.5, 0.0, 0.95), "vdiff": Color(0.62, 0.1, 0.72, 0.9),
	"sg_habit": Color(0.72, 0.5, 0.0), "sg_motion": Color(0.38, 0.28, 0.85), "sg_phase": Color(0.82, 0.18, 0.4), "sg_between": Color(0.1, 0.55, 0.25), "card_usual": Color(0.05, 0.5, 0.4),
	"autokey": Color(0.82, 0.08, 0.08), "onion_past": Color(0.85, 0.4, 0.05), "onion_future": Color(0.0, 0.5, 0.48), "fd_startup": Color(0.12, 0.55, 0.22), "fd_active": Color(0.8, 0.16, 0.14), "fd_recovery": Color(0.15, 0.38, 0.82), "fd_ink": Color(1, 1, 1), "fd_tint": Color(0.847, 0.714, 0.733),
	"kt_break": Color(0.75, 0.48, 0.0), "kt_between": Color(0.12, 0.36, 0.7),
	"pick_sel": Color(0.1, 0.4, 0.95), "pick_hover": Color(0.3, 0.6, 1.0), "pick_lock": Color(0.35, 0.35, 0.4),
	"pick_touch": Color(0.9, 0.12, 0.1), "pick_limit": Color(0.95, 0.68, 0.0),
	"judge_force": Color(0.85, 0.1, 0.7), "judge_limit": Color(0.9, 0.05, 0.05),
	"fv_ok": Color(0.12, 0.6, 0.25), "fv_mid": Color(0.85, 0.6, 0.0), "fv_hot": Color(0.82, 0.12, 0.1),
	"mk_red": Color(0.8, 0.14, 0.1), "mk_green": Color(0.15, 0.55, 0.22), "mk_blue": Color(0.12, 0.4, 0.85), "mk_gold": Color(0.7, 0.55, 0.0),
	"fp_1": Color(0.8, 0.4, 0.05), "fp_2": Color(0.1, 0.4, 0.8), "fp_3": Color(0.1, 0.5, 0.2), "fp_4": Color(0.75, 0.2, 0.5),
	"mk_panel": Color(0.985, 0.985, 0.99, 1.0), "mk_border": Color(0.38, 0.42, 0.5, 1.0),
	"body_clay": Color("D8DCE3"), "body_outline": Color(0.16, 0.45, 0.85),   # a deeper blue: the sky one vanishes on the light floor
}

static var dark := true
## THE DEFAULT DARK PALETTE is graphite + amber (Nick picked it): the DARK dict below. --kine-palette=b|c (only when given)
## overrides: b = graphite + sky (amber kept for the main action and warnings), c = light (amber accent, sky selection).
const PALETTES := {
	"b": {
		"text": Color(0.925, 0.937, 0.957), "heading": Color(0.45, 0.75, 1.0), "info": Color(0.77, 0.8, 0.85),
		"say": Color(0.62, 0.84, 1.0), "ok": Color(0.48, 0.85, 0.55), "warn": Color(1.0, 0.78, 0.2), "fail": Color(1.0, 0.48, 0.42),
		"panel": Color(0.086, 0.09, 0.106, 0.94), "float": Color(0.118, 0.125, 0.149, 0.94), "say_bg": Color(0.055, 0.06, 0.07, 0.85),
		"btn": Color(0.165, 0.176, 0.212), "btn_hover": Color(0.23, 0.245, 0.29), "main": Color(1.0, 0.78, 0.2), "accent": Color(0.45, 0.75, 1.0), "on_accent": Color(0.102, 0.11, 0.129), "focus": Color(0.925, 0.937, 0.957),
		"btn_text": Color(0.925, 0.937, 0.957), "field": Color(0.059, 0.063, 0.078),
		"card": Color(0.118, 0.125, 0.149), "card_sel": Color(0.15, 0.28, 0.4), "card_passby": Color(0.11, 0.17, 0.23), "card_play": Color(1.0, 0.78, 0.2), "card_multi": Color(0.45, 0.75, 1.0), "card_play_bg": Color(0.165, 0.176, 0.212),
		"ink": Color(0.925, 0.937, 0.957), "hair": Color(0.2, 0.3, 0.4),
	},
	"c": {
		"text": Color(0.102, 0.11, 0.129), "heading": Color(0.102, 0.11, 0.129), "info": Color(0.23, 0.26, 0.32),
		"say": Color(0.42, 0.27, 0.0), "ok": Color(0.12, 0.45, 0.22), "warn": Color(0.5, 0.32, 0.0), "fail": Color(0.7, 0.12, 0.08),
		"panel": Color(0.925, 0.937, 0.957, 0.96), "float": Color(0.97, 0.975, 0.98, 0.97), "say_bg": Color(1.0, 0.96, 0.86, 0.94),
		"btn": Color(0.85, 0.87, 0.91), "btn_hover": Color(0.78, 0.81, 0.87), "main": Color(0.949, 0.678, 0.0), "accent": Color(0.949, 0.678, 0.0), "on_accent": Color(0.102, 0.11, 0.129), "focus": Color(0.102, 0.11, 0.129),
		"btn_text": Color(0.102, 0.11, 0.129), "field": Color(1, 1, 1),
		"card": Color(0.86, 0.885, 0.92), "card_sel": Color(0.451, 0.749, 1.0), "card_passby": Color(0.96, 0.9, 0.72), "card_play": Color(0.949, 0.678, 0.0), "card_multi": Color(0.78, 0.47, 0.0), "card_play_bg": Color(0.8, 0.84, 0.9),
		"ink": Color(0.102, 0.11, 0.129), "hair": Color(0.55, 0.36, 0.05),
	},
}
static var _dk: Dictionary = DARK.duplicate()
static var _lt: Dictionary = LIGHT.duplicate()


static func c(name: String) -> Color:
	return (_dk if dark else _lt)[name]


## the palette the command line asks for ("b" or "c"), or "" when none is given (the app's own colours)
static func palette_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kine-palette="):
			var p := a.trim_prefix("--kine-palette=").to_lower()
			return p if PALETTES.has(p) else ""
	return ""


## lays a named palette over the dark (a, b) or light (c) dict; "" changes nothing
static func apply_palette(p: String) -> void:
	if not PALETTES.has(p):
		return
	var o: Dictionary = PALETTES[p]
	var tgt := _lt if p == "c" else _dk
	for k in o:
		tgt[k] = o[k]
	dark = p != "c"


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
