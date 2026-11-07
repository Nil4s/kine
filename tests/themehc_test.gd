## godot --path . -s tests/themehc_test.gd     (ROADMAP_400 P08; needs a window)
## Theme light / dark / HIGH CONTRAST through Tok. Bars (written before the implementation, never moved):
##  B1 the WCAG formula in this file reproduces black/white = 21:1 and Tok.contrast agrees (within 0.05)
##  B2 HC palette: every text/background pair in PAIRS >= 7:1 (W3C WCAG 2.2 SC 1.4.6 Contrast (Enhanced), normal text),
##     translucent fills composited over the HC world colour; the focus ring vs every surface >= 3:1 (SC 1.4.11)
##  B3 HC has exactly the tokens DARK has (a page asking for any token never gets a missing key)
##  B4 PLANTED FAIL: a copy of HC whose text is a 3:1 grey must be flagged by the same checker (and the checker is clean on HC)
##  B5 a real built page: the VIEW > High contrast button recolours >= 90 % of the tint labels, the Button theme
##     (font on normal / hover fill) reads >= 7:1 off the NODE theme, the rail panel fill is the HC one
##  B6 switching back (dark and light) restores every sampled colour byte-identical (to_html with alpha + exact ==)
##  B7 Tok.mode() names the three modes; no undo step; the choice is remembered ("hc") in the test's own cfg; the user's cfg untouched
## Source of the 7:1 / 3:1 thresholds: the W3C Recommendation WCAG 2.2 (a web standard, not a paper: no PMID).
extends SceneTree

const PAIRS := [   # [foreground token, background token]
	["text", "panel"], ["text", "float"], ["text", "btn"], ["text", "btn_hover"], ["text", "field"], ["text", "card"],
	["text", "card_sel"], ["text", "card_play_bg"], ["text", "graph_bg"], ["text", "tl_bg"], ["text", "mk_panel"],
	["heading", "panel"], ["heading", "float"], ["info", "panel"], ["info", "float"], ["say", "say_bg"],
	["ok", "panel"], ["warn", "panel"], ["fail", "panel"], ["dummy_text", "panel"],
	["btn_text", "btn"], ["btn_text", "btn_hover"], ["on_accent", "accent"], ["on_accent", "main"],
	["ink", "graph_bg"], ["ink", "panel"],
]
const FOCUS_ON := ["panel", "float", "btn", "field", "card"]

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func lum(x: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(x.r) + 0.7152 * f.call(x.g) + 0.0722 * f.call(x.b)


func wcag(a: Color, b: Color) -> float:
	var la := lum(a)
	var lb := lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func over(fg: Color, bg: Color) -> Color:
	return Color(bg.r + (fg.r - bg.r) * fg.a, bg.g + (fg.g - bg.g) * fg.a, bg.b + (fg.b - bg.b) * fg.a)


## the pairs of palette p below `need`:1 (fills composited over the palette's world colour), as "fg/bg ratio"
func below(p: Dictionary, need: float, focus_need: float) -> Array:
	var out := []
	var base: Color = p["world"]
	for pr in PAIRS:
		var bg := over(p[pr[1]], base)
		var r := wcag(over(p[pr[0]], bg), bg)
		if r < need:
			out.append("%s/%s %.2f" % [pr[0], pr[1], r])
	for b in FOCUS_ON:
		var bg2 := over(p[b], base)
		var r2 := wcag(over(p["focus"], bg2), bg2)
		if r2 < focus_need:
			out.append("focus/%s %.2f" % [b, r2])
	return out


func worst(p: Dictionary) -> float:
	var w := 99.0
	var base: Color = p["world"]
	for pr in PAIRS:
		var bg := over(p[pr[1]], base)
		w = minf(w, wcag(over(p[pr[0]], bg), bg))
	return w


## colours read off a real page: every tint label, the Button theme, a rail's panel fill
func sample() -> Dictionary:
	var s := {"labels": [], "theme": {}}
	for x in m.ui_tinted:
		if is_instance_valid(x[0]):
			s["labels"].append((x[0] as Label).get_theme_color("font_color"))
	var th: Theme = m.ui_root.theme
	s["theme"]["btn_font"] = th.get_color("font_color", "Button")
	s["theme"]["btn_normal"] = (th.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color
	s["theme"]["btn_hover"] = (th.get_stylebox("hover", "Button") as StyleBoxFlat).bg_color
	s["theme"]["btn_hover_font"] = th.get_color("font_hover_color", "Button")
	var rails: Array = m.ui_rails.values()
	s["theme"]["rail"] = (rails[0].get_theme_stylebox("panel") as StyleBoxFlat).bg_color
	s["theme"]["world"] = m.world_env.background_color
	return s


func same(a: Dictionary, b: Dictionary) -> bool:
	if a["labels"].size() != b["labels"].size():
		return false
	for i in a["labels"].size():
		if a["labels"][i] != b["labels"][i] or (a["labels"][i] as Color).to_html(true) != (b["labels"][i] as Color).to_html(true):
			return false
	for k in a["theme"]:
		if a["theme"][k] != b["theme"][k] or (a["theme"][k] as Color).to_html(true) != (b["theme"][k] as Color).to_html(true):
			return false
	return true


func click(btn: Button) -> void:
	var p := btn.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		root.push_input(e)


func _init() -> void:
	var real := FileAccess.get_file_as_string("user://poser.cfg")
	# B1
	var bw := wcag(Color.WHITE, Color.BLACK)
	ok(absf(bw - 21.0) < 0.01 and absf(Tok.contrast(Color.WHITE, Color.BLACK) - bw) < 0.05 and absf(Tok.contrast(Color(0.5, 0.5, 0.5), Color.BLACK) - wcag(Color(0.5, 0.5, 0.5), Color.BLACK)) < 0.05, "B1 WCAG formula: black/white %.2f, Tok.contrast agrees" % bw)
	# B2 B3
	var hc: Dictionary = Tok.palette("hc")
	var low := below(hc, 7.0, 3.0)
	ok(low.is_empty(), "B2 HC: all %d text pairs >= 7:1 and focus >= 3:1 (worst text pair %.2f) %s" % [PAIRS.size(), worst(hc), low])
	ok(hc.size() == Tok.DARK.size() and Tok.DARK.keys().all(func(k): return hc.has(k)), "B3 HC carries all %d tokens of DARK" % Tok.DARK.size())
	ok(hc["text"] != Tok.DARK["text"] and hc["panel"] != Tok.DARK["panel"] and hc["accent"] != Tok.DARK["accent"], "B3b HC is its own palette (text, panel, accent differ from DARK)")
	# B4 planted fail
	var fake := hc.duplicate()
	var lo := 0.0
	var hi := 1.0
	for _i in 40:   # the grey that is exactly 3:1 against the HC panel
		var mid := (lo + hi) / 2.0
		if wcag(Color(mid, mid, mid), over(fake["panel"], fake["world"])) < 3.0:
			lo = mid
		else:
			hi = mid
	fake["text"] = Color(hi, hi, hi)
	var flagged := below(fake, 7.0, 3.0)
	var r3 := wcag(Color(hi, hi, hi), over(fake["panel"], fake["world"]))
	ok(absf(r3 - 3.0) < 0.05 and flagged.size() >= 5 and flagged.any(func(s): return String(s).begins_with("text/panel")), "B4 planted 3:1 text (%.2f) is flagged by the checker (%d pairs: %s ...)" % [r3, flagged.size(), flagged.slice(0, 2)])
	ok(Tok.palette("dark").size() > 0 and Tok.palette("light").size() > 0, "B4b palette() serves dark and light too (dark worst text pair %.2f, light %.2f: reported, not barred)" % [worst(Tok.palette("dark")), worst(Tok.palette("light"))])
	# B5..B7 on the real page
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	ok(Tok.mode() == "dark", "B7 boots in mode dark (%s)" % Tok.mode())
	var u0: int = m.undo.size()
	var dark0 := sample()
	m._ribbon("VIEW")
	await process_frame
	var hc_btn: Button = null
	for b in m.ui_ribbon["VIEW"].get_children():
		if b is Button and m.label_of(b) == "High contrast":
			hc_btn = b
	ok(hc_btn != null and hc_btn.is_visible_in_tree(), "B5 VIEW tab has a 'High contrast' button on screen")
	if hc_btn == null:
		print("THEMEHC TEST FAIL")
		quit(1)
		return
	click(hc_btn)
	await process_frame
	await process_frame
	var hs := sample()
	ok(Tok.mode() == "hc" and Tok.dark, "B7 click: mode hc (Tok.dark stays true for the dark-branch code)")
	var changed := 0
	for i in hs["labels"].size():
		if i < dark0["labels"].size() and hs["labels"][i] != dark0["labels"][i]:
			changed += 1
	var frac := float(changed) / maxf(1.0, float(hs["labels"].size()))
	ok(hs["labels"].size() >= 10 and frac >= 0.9, "B5 tint labels recoloured: %d of %d (%.0f %%)" % [changed, hs["labels"].size(), frac * 100.0])
	var t: Dictionary = hs["theme"]
	var rb := wcag(t["btn_font"], t["btn_normal"])
	var rh := wcag(t["btn_hover_font"], t["btn_hover"])
	ok(rb >= 7.0 and rh >= 7.0, "B5 node theme: Button font/normal %.2f, hover %.2f (>= 7)" % [rb, rh])
	ok(t["rail"] == Tok.c("panel") and t["rail"] == hc["panel"] and t["world"] == hc["world"], "B5 rail fill and 3D background took the HC palette")
	var lab_ratio := 99.0
	for x in m.ui_tinted:
		if is_instance_valid(x[0]) and x[1] in ["text", "heading", "info", "say"]:
			lab_ratio = minf(lab_ratio, wcag((x[0] as Label).get_theme_color("font_color"), over(t["rail"], t["world"])))
	ok(lab_ratio >= 7.0, "B5 real labels (text/heading/info/say tints) vs the rail fill: worst %.2f" % lab_ratio)
	ok(m.undo.size() == u0, "B7 no undo step")
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(cf.get_value("look", "theme", "") == "hc", "B7 remembered: look/theme = %s" % cf.get_value("look", "theme", ""))
	# B6 back to dark, then light round trip
	m._set_light(false)
	await process_frame
	ok(Tok.mode() == "dark" and same(sample(), dark0), "B6 hc -> dark: every sampled colour byte-identical (%d labels + theme)" % dark0["labels"].size())
	m._set_light(true)
	await process_frame
	var light0 := sample()
	ok(Tok.mode() == "light", "B7 light mode named")
	click(hc_btn)
	await process_frame
	await process_frame
	ok(Tok.mode() == "hc", "B5 hc from light")
	m._set_light(true)
	await process_frame
	ok(Tok.mode() == "light" and same(sample(), light0), "B6 hc -> light: every sampled colour byte-identical")
	click(hc_btn)   # toggle on, then the same button off -> back to the mode it came from
	await process_frame
	click(hc_btn)
	await process_frame
	await process_frame
	ok(Tok.mode() == "light" and same(sample(), light0), "B6 button on, button off: back to light, identical")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	ok(FileAccess.get_file_as_string("user://poser.cfg") == real, "B7 the user's user://poser.cfg untouched")
	print("THEMEHC TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
