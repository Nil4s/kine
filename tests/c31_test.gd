extends SceneTree
## godot --path . --position 4000,4000 -s tests/c31_test.gd     (C31: complaint #804, the 447 untranslated UI strings in data/i18n/pt_BR.po)
## Bars (written before any number was read):
##  1 SCAN    c11's scanner (I18nScan) reports 0 missing UI strings in scripts/*.gd.  CONTROL: the same call with a planted untranslated string reports exactly it
##  2 HOLES   every msgid of the .po has a non-empty msgstr, and no "#, fuzzy" flag anywhere.  CONTROL: a planted empty msgstr is caught by the same checker
##  3 PLACE   every entry has the same multiset of placeholders (%s %d %f ... and {name}) in msgstr as in msgid.  CONTROL: a planted pair that drops one is caught
##  4 CRLF    the .po has no bare LF (every LF is preceded by CR) and is not empty.  CONTROL: "a\nb" is flagged, "a\r\nb" is not
##  5 REVIEW  the last 447 msgids of the .po are each listed, with their Portuguese, in docs/PT_BR_REVIEW.md (447 bullets)
##  6 KEYS    key letters named in a string survive: for every new entry the tokens Shift / Ctrl / Alt / Esc / Enter / Tab / F6 / PageUp / PageDown / Kine
##            that are in the msgid are in the msgstr
##  7 FIT     with Portuguese on at 1280x720 (start screen, Settings, the ribbon tabs), no visible Button / Label has text wider than its room
##            that fitted in English (control: the measurer flags a planted 500 px label in a 50 px box).  Screenshots C:/Temp/claude/c31/*.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/c31"
const NEW := 447
const PO := "res://data/i18n/pt_BR.po"
const REVIEW := "res://docs/PT_BR_REVIEW.md"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## [[msgid, msgstr], ...] from the .po text; own parser (String ops, no RegEx), multi-line strings joined
func entries(text: String) -> Array:
	var out := []
	var cur := ["", ""]
	var which := -1
	var seen := false
	for raw in text.split("\n"):
		var ln: String = raw.strip_edges()
		if ln.begins_with("msgid "):
			if seen:
				out.append(cur)
			cur = ["", ""]
			which = 0
			seen = true
			cur[0] += unq(ln.substr(6))
		elif ln.begins_with("msgstr "):
			which = 1
			cur[1] += unq(ln.substr(7))
		elif ln.begins_with("\"") and which >= 0:
			cur[which] += unq(ln)
	if seen:
		out.append(cur)
	return out


func unq(s: String) -> String:
	s = s.strip_edges()
	if s.length() < 2 or not s.begins_with("\"") or not s.ends_with("\""):
		return ""
	s = s.substr(1, s.length() - 2)
	var o := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == "\\" and i + 1 < s.length():
			var n := s[i + 1]
			o += "\n" if n == "n" else ("\t" if n == "t" else n)
			i += 2
		else:
			o += c
			i += 1
	return o


## the placeholders of a string, sorted: %s %d %f %.2f %% and {name}
func holders(s: String) -> Array:
	var out := []
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == "%":
			var j := i + 1
			while j < s.length() and "-+ #0123456789.".find(s[j]) >= 0:
				j += 1
			if j < s.length() and "sdifxXc%".find(s[j]) >= 0:
				out.append(s.substr(i, j - i + 1))
				i = j + 1
				continue
		elif c == "{":
			var j2 := s.find("}", i)
			if j2 > i:
				out.append(s.substr(i, j2 - i + 1))
				i = j2 + 1
				continue
		i += 1
	out.sort()
	return out


func bad_holes(es: Array) -> int:
	var n := 0
	for e in es:
		if e[0] != "" and String(e[1]).strip_edges() == "":
			n += 1
	return n


func bad_place(es: Array) -> int:
	var n := 0
	for e in es:
		if e[0] != "" and holders(e[0]) != holders(e[1]):
			n += 1
	return n


func bare_lf(t: String) -> int:
	var n := 0
	for i in t.length():
		if t[i] == "\n" and (i == 0 or t[i - 1] != "\r"):
			n += 1
	return n


func words(n: Control) -> String:
	return n.atr(String(n.get("text")))


## text width minus room, px; <= 0 fits
func over(c: Control, t: String) -> float:
	if t == "":
		return -1.0
	var fs := c.get_theme_font_size("font_size")
	var font := c.get_theme_font("font")
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var room := c.size.x
	if c is Button:
		var sb := c.get_theme_stylebox("normal")
		room -= sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
		if (c as Button).icon != null:
			room -= (c as Button).icon.get_width() + 4.0
	elif c is Label:
		if (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			return -1.0
	else:
		return -1.0
	return w - room


## visible Button / Label now: path -> [english over, portuguese over, text]
func measure() -> Dictionary:
	var out := {}
	for c in root.find_children("*", "Control", true, false):
		if not (c is Button or c is Label) or c is OptionButton or c is MenuButton or not (c as Control).is_visible_in_tree():
			continue
		var en := String(c.get("text"))
		out[str(c.get_path())] = [over(c, en), over(c, words(c)), words(c), en]
	return out


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func _init() -> void:
	# 1 SCAN
	var strs := I18nScan.all_strings()
	var ids := I18nScan.msgids()
	var gaps := I18nScan.missing(strs, ids)
	ok(gaps.is_empty(), "1 SCAN %d UI strings, %d missing a pt_BR msgid %s" % [strs.size(), gaps.size(), str(gaps.slice(0, 5))])
	var planted := strs.duplicate()
	planted["Zzq planted untranslated words"] = true
	var pg := I18nScan.missing(planted, ids)
	ok(pg.size() == 1 and pg[0] == "Zzq planted untranslated words", "1 CONTROL a planted string is reported alone (%d)" % pg.size())
	# 2 HOLES
	var text := FileAccess.get_file_as_string(PO)
	var es := entries(text)
	ok(es.size() > 700 and bad_holes(es) == 0 and text.find("fuzzy") < 0, "2 HOLES %d entries, empty msgstr %d, 'fuzzy' found at %d" % [es.size(), bad_holes(es), text.find("fuzzy")])
	ok(bad_holes(es + [["Zzq", ""]]) == 1, "2 CONTROL a planted empty msgstr is caught")
	# 3 PLACE
	ok(bad_place(es) == 0, "3 PLACE placeholder sets differ in %d of %d entries" % [bad_place(es), es.size()])
	ok(bad_place(es + [["Hit %s for %d", "Bate %s"]]) == 1 and bad_place(es + [["Move {name}", "Mover {nome}"]]) == 1 and bad_place([["Hit %s for %d", "Bate %d em %s"]]) == 0, "3 CONTROL a dropped %d and a renamed {name} are caught; a reordered pair is not")
	# 4 CRLF
	ok(text.length() > 1000 and bare_lf(text) == 0 and text.find("\r\n") > 0, "4 CRLF bare LF in the .po: %d" % bare_lf(text))
	ok(bare_lf("a\nb") == 1 and bare_lf("a\r\nb") == 0, "4 CONTROL the counter flags a bare LF and passes CRLF")
	# 5 REVIEW
	var rv := FileAccess.get_file_as_string(REVIEW).split("\n")
	var bullets := []
	var tails := []
	for i in rv.size():
		if rv[i].begins_with("- `"):
			bullets.append(rv[i])
			tails.append(rv[i + 1] if i + 1 < rv.size() else "")
	var newest := es.slice(es.size() - NEW)
	var listed := 0
	for i in newest.size():
		var src: String = newest[i][0]
		var key := "- `%s`" % src.strip_edges().replace("`", "'").replace("\n", " ").substr(0, 400)
		if i < bullets.size() and bullets[i] == key and tails[i].strip_edges() == "- " + String(newest[i][1]).strip_edges().replace("\n", " "):
			listed += 1
	ok(bullets.size() == NEW and listed == NEW, "5 REVIEW %d bullets, %d of the last %d entries listed with their Portuguese" % [bullets.size(), listed, NEW])
	# 6 KEYS
	var lost := []
	for e in newest:
		for tok in ["Shift", "Ctrl", "Alt", "Esc", "Enter", "Tab", "F6", "PageUp", "PageDown", "Kine"]:
			if String(e[0]).find(tok) >= 0 and String(e[1]).find(tok) < 0:
				lost.append("%s in '%s'" % [tok, String(e[0]).substr(0, 30)])
	ok(lost.is_empty(), "6 KEYS key names lost: %s" % str(lost))
	# 7 FIT
	OS.set_environment("KINE_LANG_FILE", ProjectSettings.globalize_path("user://c31_lang_test.cfg"))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var lab := Label.new()
	lab.text = "x".repeat(80)
	lab.clip_text = true
	lab.custom_minimum_size = Vector2(50, 20)
	lab.size = Vector2(50, 20)
	root.add_child(lab)
	await idle(2)
	ok(over(lab, lab.text) > 100.0, "7 CONTROL the measurer flags an 80-letter label in a 50 px box (%.0f px over)" % over(lab, lab.text))
	lab.queue_free()
	KineLang.use("pt_BR")
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c31_test"))
	ss.dirs_override = ["user://c31_test"]
	ss.show_screen()
	await idle(4)
	var worst := {}
	var n_seen := 0
	var n_pt := 0
	var cut := []
	var old_cut := []
	var newset := {}
	for e in newest:
		newset[String(e[0])] = true
	var gear := ss.find_child("settings_btn", true, false) as Button
	for stage in ["start", "settings", "ribbon"]:
		if stage == "settings" and gear != null:
			gear.pressed.emit()
			await idle(4)
		elif stage == "ribbon":
			ss._close()
			await idle(4)
		var mm := measure()
		for k in mm:
			n_seen += 1
			var r: Array = mm[k]
			if String(r[2]) != String((root.get_node(NodePath(k)) as Control).get("text")):
				n_pt += 1
			if float(r[1]) > 0.5 and float(r[0]) <= 0.5 and not newset.has(String(r[3])):
				old_cut.append("%s [%s]: %.0f px over" % [String(r[2]).substr(0, 40), k.get_file(), float(r[1])])
			elif float(r[1]) > 0.5 and float(r[0]) <= 0.5:
				cut.append("%s [%s]: %.0f px over" % [String(r[2]).substr(0, 40), k.get_file(), float(r[1])])
		await shot(stage)
	ok(cut.is_empty() and n_seen > 20, "7 FIT %d visible Buttons/Labels measured, %d drawn in Portuguese, %d of the NEW strings cut off: %s" % [n_seen, n_pt, cut.size(), str(cut.slice(0, 8))])
	print("REPORT older translations cut off (not part of the 447): ", str(old_cut))
	KineLang.use("en")
	print("c31: %d fails" % fails)
	quit(fails)
