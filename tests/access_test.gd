extends SceneTree
## godot --path . -s tests/access_test.gd     (lane L111, ROADMAP_400 P16: font scaling + colour-blind-safe selection colours; needs a window)
## Bars, written BEFORE the implementation (scripts/access.gd, class Access) and never moved after a run:
##   F1 SCALE   a real page (the app after boot, 1920x1080): Access.set_font_scale(main, 1.5) makes the font size READ FROM EVERY visible
##              Label / Button / LineEdit with text equal round(base * 1.5) (+-1 px), over at least 40 controls.
##              Setting 1.0 afterwards gives the base sizes back.   Planted: an unscaled size is rejected by the same check.
##   F2 CLIP    no text control that did NOT clip at 1.0 clips at 1.5: measured text width (font.get_string_size) <= the control's width
##              + 0.5 px (autowrap labels are skipped; their height is not measured here). The absolute counts at 1.0 and 1.5 are printed.
##              Planted: a 40 px wide clip_text Label holding a long text is found.
##   C0 MATRIX  the three Machado matrices keep white white (each row sums to 1 +-1e-4): a typo in a coefficient shows here.
##   C1 PLANT   the pair red (0.8,0.2,0.1) / green (0.45,0.55,0.1) is told apart by normal vision and tritanopia (dE >= 15) and FAILS
##              under deuteranopia (dE < 15): the checker must say so.
##   C2 DEFAULT the default palette's dE for the selection sets is REPORTED (min per set and view); not a bar.
##   C3 CB MODE with Access.set_colourblind(true), in the dark and the light palette, for each set below, every pair is at CIE76 dE >= 15
##              under normal vision, deuteranopia, protanopia and tritanopia (Machado et al. 2009, severity 1.0). 15 is stated here,
##              before any run: dE76 about 2.3 is a just-noticeable difference, 15 is a clearly different colour at a glance.
##              Sets: PICK {pick_sel, pick_hover, body_clay} (the part's light on its skin: selected / hovered / not),
##                    CARD {card, card_sel, card_passby} (timeline cards: plain / selected / passed-by),
##                    BTN  {btn, btn_hover, accent} (a button: rest / hover / pressed).
##   C4 OFF     set_colourblind(false) gives the default colours back exactly.
## Matrices: Machado, Oliveira, Fernandes, "A Physiologically-based Model for Simulation of Color Vision Deficiency", IEEE TVCG 2009,
## DOI 10.1109/TVCG.2009.113 (DOI from the lane brief). The 27 coefficients below were typed from memory: UNVERIFIED against the paper;
## C0 (row sums) is the only check on them. Nothing is written to disk.
const THRESH := 15.0
const MODES := ["normal", "prot", "deut", "trit"]
const MATS := {
	"prot": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
	"deut": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
	"trit": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}
const SETS := {
	"PICK": ["pick_sel", "pick_hover", "body_clay"],
	"CARD": ["card", "card_sel", "card_passby"],
	"BTN": ["btn", "btn_hover", "accent"],
}
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


# ---------------------------------------------------------------- colour maths (the test's own, independent of Access)
static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _gam(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


static func sim(c: Color, mode: String) -> Color:
	if mode == "normal":
		return c
	var M: Array = MATS[mode]
	var l := [_lin(c.r), _lin(c.g), _lin(c.b)]
	var o := []
	for r in 3:
		o.append(_gam(M[r][0] * l[0] + M[r][1] * l[1] + M[r][2] * l[2]))
	return Color(o[0], o[1], o[2])


static func _f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 216.0 / 24389.0 else (24389.0 / 27.0 * t + 16.0) / 116.0


static func lab(c: Color) -> Vector3:
	var r := _lin(c.r)
	var g := _lin(c.g)
	var b := _lin(c.b)
	var x := (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
	var y := 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
	var z := (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
	var fx := _f(x)
	var fy := _f(y)
	var fz := _f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func de(a: Color, b: Color, mode: String) -> float:
	return lab(sim(a, mode)).distance_to(lab(sim(b, mode)))


## the least dE over the pairs of a set, in one view
func set_min(names: Array, mode: String) -> float:
	var worst := 1e9
	for i in names.size():
		for j in range(i + 1, names.size()):
			worst = minf(worst, de(Tok.c(names[i]), Tok.c(names[j]), mode))
	return worst


func report_sets(tag: String, gate: bool) -> void:
	for dark in [true, false]:
		Tok.set_dark(dark)
		for sname in SETS:
			var line := ""
			var all_ok := true
			for mode in MODES:
				var v := set_min(SETS[sname], mode)
				line += " %s=%.1f" % [mode, v]
				all_ok = all_ok and v >= THRESH
			var pal := "dark" if dark else "light"
			if gate:
				ok(all_ok, "C3 %s %s %s: every pair dE >= %.0f (min per view:%s)" % [tag, pal, sname, THRESH, line])
			else:
				print("info C2 %s %s %s: min dE per view:%s%s" % [tag, pal, sname, line, "" if all_ok else "   (below %.0f somewhere)" % THRESH])


# ---------------------------------------------------------------- text controls
func texts(rt: Node) -> Array:
	var out := []
	for c in rt.find_children("*", "Control", true, false):
		var cc := c as Control
		if not cc.is_visible_in_tree() or cc.size.x <= 0.0:
			continue
		if (cc is Label or cc is Button or cc is LineEdit) and String(cc.get("text")) != "":
			out.append(cc)
	return out


static func fsize(c: Control) -> int:
	return c.get_theme_font_size("font_size")


static func clips(c: Control) -> bool:
	if c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
		return false
	var s := fsize(c)
	var w := c.get_theme_font("font").get_string_size(String(c.get("text")), HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	return w > c.size.x + 0.5


static func scaled_ok(base: int, now: int, f: float) -> bool:
	return absi(now - int(round(base * f))) <= 1


func _init() -> void:
	# ---- C0 / C1: the checker itself
	var sums_ok := true
	for k in MATS:
		for r in MATS[k]:
			sums_ok = sums_ok and absf(r[0] + r[1] + r[2] - 1.0) < 1e-4
	ok(sums_ok, "C0 Machado matrices: every row sums to 1 (white stays white)")
	var red := Color(0.8, 0.2, 0.1)
	var green := Color(0.45, 0.55, 0.1)
	var pn := de(red, green, "normal")
	var pd := de(red, green, "deut")
	var pt := de(red, green, "trit")
	ok(pn >= THRESH and pt >= THRESH and pd < THRESH, "C1 PLANTED red/green: normal %.1f, tritanopia %.1f pass; deuteranopia %.1f FAILS (< %.0f) as it must" % [pn, pt, pd, THRESH])
	# ---- C2: the default palette, reported
	report_sets("default", false)
	# ---- C3 / C4: the colour-blind mode
	var before := {}
	for d in [true, false]:
		Tok.set_dark(d)
		for s in SETS:
			for n in SETS[s]:
				before["%s%s" % [d, n]] = Tok.c(n)
	Access.set_colourblind(true)
	report_sets("CB mode", true)
	Access.set_colourblind(false)
	var same := true
	for d in [true, false]:
		Tok.set_dark(d)
		for s in SETS:
			for n in SETS[s]:
				same = same and before["%s%s" % [d, n]] == Tok.c(n)
	ok(same, "C4 set_colourblind(false) gives the default colours back exactly")
	Tok.set_dark(true)
	# ---- F: the font scale on a real page
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 10:
		await process_frame
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	for i in 10:
		await process_frame
	var ctl := texts(m)
	var base := []
	var clip0 := []
	for c in ctl:
		base.append(fsize(c))
		if clips(c):
			clip0.append(c)
	Access.set_font_scale(m, 1.5)
	for i in 10:
		await process_frame
	var bad := 0
	var n_checked := 0
	var newclip := []
	var clip1 := 0
	for i in ctl.size():
		var c: Control = ctl[i]
		if not is_instance_valid(c) or not c.is_visible_in_tree():
			continue
		n_checked += 1
		if not scaled_ok(base[i], fsize(c), 1.5):
			bad += 1
			if bad <= 5:
				print("     size: %s '%s' %d -> %d" % [c.get_class(), String(c.get("text")).left(24), base[i], fsize(c)])
		if clips(c):
			clip1 += 1
			if not clip0.has(c):
				newclip.append(c)
	ok(n_checked >= 40 and bad == 0, "F1 font scale 1.5: %d text controls read round(base*1.5) from the node, %d wrong" % [n_checked, bad])
	ok(not scaled_ok(14, 14, 1.5) and scaled_ok(14, 21, 1.5), "F1 PLANTED: an unscaled 14 px label is rejected by the size check, 21 accepted")
	for c in newclip.slice(0, 8):
		print("     new clip: %s '%s' w=%.0f font %d" % [c.get_class(), String(c.get("text")).left(30), c.size.x, fsize(c)])
	ok(newclip.is_empty(), "F2 no NEW text clipping at 1.5 (clipping controls: %d at 1.0, %d at 1.5, %d new)" % [clip0.size(), clip1, newclip.size()])
	var probe := Label.new()
	probe.text = "a rather long label that cannot fit forty pixels"
	probe.clip_text = true
	probe.custom_minimum_size = Vector2(40, 0)
	probe.size = Vector2(40, 20)
	m.add_child(probe)
	ok(clips(probe), "F2 PLANTED: a 40 px wide Label with a long text is found clipping")
	probe.queue_free()
	Access.set_font_scale(m, 1.0)
	for i in 10:
		await process_frame
	var back := 0
	for i in ctl.size():
		if is_instance_valid(ctl[i]) and ctl[i].is_visible_in_tree() and fsize(ctl[i]) != base[i]:
			back += 1
	ok(back == 0, "F1 scale 1.0 restores the base sizes (%d differ)" % back)
	print("access_test: %d fails" % fails)
	quit(1 if fails > 0 else 0)
