extends SceneTree
## godot --path . --position 4000,4000 -s tests/c35_test.gd     (C35: complaint #804 follow-up, pt_BR text must FIT)
## Bars (written before any number was read):
##  1 FIT    with Portuguese on, at 1280x720 AND 1024x600, over every ribbon page, every ribbon popup (cap menus opened), the Export dialog
##           (every target), the scene panel and the right-hand joint panel: no visible Button / CheckBox / Label has Portuguese text wider than
##           its room while its English text fitted.  Count of such cut texts = 0 at both sizes.  CONTROL: the measurer flags a planted 80-letter label in a 50 px box
##  2 RESET  the pt_BR word for "Reset" is shorter than 'Reiniciar' (the 17 px overflow) and is not empty.  CONTROL: the checker flags 'Reiniciar'
##  3 REVIEW every msgstr this branch changed is listed in docs/PT_BR_REVIEW.md under "## C35 fit changes" (bullets with the new Portuguese)
##  4 WATCH  the test finishes inside 240 s (a watchdog quits with a failure otherwise)
## Screenshots C:/Temp/claude/c35/*.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/c35"
const PO := "res://data/i18n/pt_BR.po"
const REVIEW := "res://docs/PT_BR_REVIEW.md"
var t0 := 0


func ok(c: bool, w: String) -> void:
	print(("PASS " if c else "FAIL ") + w)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for _i in n:
		await process_frame


func shorter(w: String) -> bool:
	return w != "" and w.length() < "Reiniciar".length()


func words(n: Control) -> String:
	return n.atr(String(n.get("text")))


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
		if c is CheckBox or c is CheckButton:
			room -= 22.0
	elif c is Label:
		if (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			return -1.0
	else:
		return -1.0
	return w - room


## visible Button / Label now: path -> [english over, portuguese over, pt text]
func measure() -> Dictionary:
	var out := {}
	for c in root.find_children("*", "Control", true, false):
		if not (c is Button or c is Label) or c is OptionButton or c is MenuButton or not (c as Control).is_visible_in_tree():
			continue
		if (c as Control).size.x < 2.0:
			continue
		var en := String(c.get("text"))
		out[str(c.get_path())] = [over(c, en), over(c, words(c)), words(c), en]
	return out


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


var cut := {}   # "pt text" -> description (a text counted once)
var seen := 0


func sweep(where: String) -> void:
	var mm := measure()
	for k in mm:
		seen += 1
		var r: Array = mm[k]
		if float(r[1]) > 0.5 and float(r[0]) <= 0.5:
			cut["%s|%s" % [where, String(r[2])]] = "%s [%s] en '%s': %.0f px over" % [String(r[2]).substr(0, 40), k.get_file(), String(r[3]).substr(0, 30), float(r[1])]


func _init() -> void:
	t0 = Time.get_ticks_msec()
	create_timer(240.0).timeout.connect(func():
		print("FAIL 4 WATCH watchdog: test ran past 240 s")
		quit(1))
	# 2 RESET
	var text := FileAccess.get_file_as_string(PO)
	var rs := ""
	var idx := text.find("msgid \"Reset\"\r\nmsgstr \"")
	if idx < 0:
		idx = text.find("msgid \"Reset\"\nmsgstr \"")
	if idx >= 0:
		var a := text.find("msgstr \"", idx) + 8
		rs = text.substr(a, text.find("\"", a) - a)
	ok(rs != "" and shorter(rs), "2 RESET pt_BR 'Reset' is '%s'" % rs)
	ok(not shorter("Reiniciar"), "2 CONTROL the checker rejects 'Reiniciar' itself")
	# 3 REVIEW
	var rv := FileAccess.get_file_as_string(REVIEW)
	var sec := rv.find("## C35 fit changes")
	ok(sec >= 0 and rv.substr(sec).find("- `Reset`") > 0 and rv.substr(sec).find(rs) > 0, "3 REVIEW the C35 section lists Reset -> %s" % rs)
	# 1 FIT
	OS.set_environment("KINE_LANG_FILE", ProjectSettings.globalize_path("user://c35_lang_test.cfg"))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	if m.start_screen != null:
		m.start_screen.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var lab := Label.new()
	lab.text = "x".repeat(80)
	lab.clip_text = true
	lab.custom_minimum_size = Vector2(50, 20)
	lab.size = Vector2(50, 20)
	root.add_child(lab)
	await idle(2)
	ok(over(lab, lab.text) > 100.0, "1 CONTROL the measurer flags an 80-letter label in a 50 px box (%.0f px over)" % over(lab, lab.text))
	lab.queue_free()
	KineLang.use("pt_BR")
	for sz in [Vector2i(1280, 720), Vector2i(1024, 600)]:
		cut.clear()
		seen = 0
		root.content_scale_size = sz
		await idle(5)
		var tag := "%dx%d" % [sz.x, sz.y]
		for p in m.PAGES_ALL:
			m._page_set(p, false)
			await idle(4)
			await sweep("page " + p)
			for tab in m.RIBBON_ALL:
				if m.ui_caps.has(tab) and m.PAGE_ROW.get(p, "") == tab:
					for cp in m.ui_caps[tab]:
						var mb := cp[0] as MenuButton
						if mb != null and mb.is_visible_in_tree():
							mb.get_popup().popup(Rect2i(Vector2i(100, 100), Vector2i(10, 10)))
							await idle(3)
							await sweep("popup %s/%s" % [p, mb.text])
							mb.get_popup().hide()
			if p == "POSE":
				await shot("%s_pose" % tag)
		# scene panel / joint panel are part of every page's sweep; one more look with the scene menu open
		if m.ui_scene_btn != null and m.ui_scene_btn.is_visible_in_tree():
			m.ui_scene_btn.get_popup().popup(Rect2i(Vector2i(100, 100), Vector2i(10, 10)))
			await idle(3)
			await sweep("scene menu")
			await shot("%s_scenemenu" % tag)
			m.ui_scene_btn.get_popup().hide()
		# Export dialog, every target
		m._export_dialog_open()
		await idle(4)
		var nt: int = m.export_ui.ui_target.item_count
		for ti in nt:
			m.export_ui.ui_target.select(ti)
			m.export_ui._on_target(ti)
			await idle(3)
			await sweep("export %d" % ti)
			if ti == 0:
				await shot("%s_export" % tag)
		m.export_ui.dlg.hide()
		await idle(2)
		ok(cut.is_empty() and seen > 100, "1 FIT %s: %d Buttons/Labels measured, %d Portuguese texts cut off: %s" % [tag, seen, cut.size(), str(cut.values().slice(0, 12))])
		if not cut.is_empty():
			print("ALLCUT ", tag, " ", str(cut.values()))
	KineLang.use("en")
	print("c35: %d fails" % fails)
	quit(fails)
