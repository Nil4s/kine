## godot --headless --path . -s tests/type_scale_test.gd     (GATES FF3, UPGRADES #40)
## ONE TYPE SCALE: the properties panel (the selected part's), in 4 states (the right upper arm, the hips, the metal bat
## free, the bat locked in the hand). Every visible Label / Button / OptionButton there is read for the font size and
## the font it actually resolves: two sizes only (22 = the part's name and nothing else; 15 = the rest) and two fonts
## at most (weights). Every value row shown reads label dim, value bright (the value's colour brighter and more opaque
## than its name's), the hint dim, and its value is the slider's value.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func lum(c: Color) -> float:
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * c.a


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var panel: Node = m.ui_title.get_parent()
	while panel != null and not (panel is ScrollContainer):
		panel = panel.get_parent()
	var sizes := {}
	var fonts := {}
	var big_bad := []
	var row_bad := []
	var rows_seen := 0
	for st in ["upperarm_r", "pelvis", "bat free", "bat locked"]:
		if st.begins_with("bat"):
			m.B.wep_on = true
			if (st == "bat locked") != (m.B.wep_hand != ""):
				m._bat_lock()
			m.sel = "bat_handle"
		else:
			m.sel = st
		m._refresh()
		await idle(2)
		for c in panel.find_children("*", "Control", true, false):
			if not (c as Control).is_visible_in_tree() or not (c is Label or c is Button):
				continue
			var fs: int = c.get_theme_font_size("font_size")
			sizes[fs] = sizes.get(fs, 0) + 1
			fonts[c.get_theme_font("font").get_instance_id()] = true
			if fs == m.PROP_BIG and c != m.ui_title:
				big_bad.append([st, String(c.text).left(20)])
		var all_rows: Array = []
		for k in m.ui_rows:
			if (m.ui_rows[k]["box"] as Control).is_visible_in_tree():
				all_rows.append([m.ui_rows[k]["label"], m.ui_rows[k]["slider"], " deg"])
		for h in m.ui_hips:
			if (h[0] as Control).is_visible_in_tree():
				all_rows.append([h[1], h[0], " m"])
		for r in all_rows:
			rows_seen += 1
			var n: Label = r[0][0]
			var v: Label = r[0][1]
			var hint: Label = r[0][2]
			var cn: Color = n.get_theme_color("font_color")
			var cv: Color = v.get_theme_color("font_color")
			var ch: Color = hint.get_theme_color("font_color")
			var num := float(v.text.get_slice(" ", 0))
			var digits := v.text.get_slice(" ", 0)
			var dec: int = digits.length() - digits.find(".") - 1 if "." in digits else 0   # get_slice gives the whole string when there is no "."
			# the text rounds the true value to its last digit; the slider snaps it to its step: both within half of each
			var tol: float = 0.5 * pow(10.0, -dec) + 0.5 * (r[1] as Range).step + 1e-6
			if not (lum(cv) > lum(cn) + 0.15 and lum(ch) < lum(cv) and v.text.ends_with(r[2]) and absf(num - (r[1] as Range).value) <= tol and n.text != ""):
				row_bad.append([st, n.text, v.text, cn, cv, (r[1] as Range).value])
	ok(sizes.keys().size() == 2 and sizes.has(m.PROP_BIG) and sizes.has(m.PROP_TXT) and big_bad.is_empty(),
		"1 4 states: font sizes rendered %s (want only %d and %d); %d used for the part's name only (else: %s)" % [sizes, m.PROP_BIG, m.PROP_TXT, m.PROP_BIG, big_bad])
	ok(fonts.size() <= 2, "2 fonts (weights) rendered: %d" % fonts.size())
	ok(rows_seen >= 12 and row_bad.is_empty(), "3 %d value rows: each name dim, value bright (and its slider's value), hint dim (bad: %s)" % [rows_seen, row_bad.slice(0, 2)])
	print("TYPE SCALE: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
