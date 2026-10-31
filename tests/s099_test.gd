extends SceneTree
## godot --path . --position 4000,4000 -s tests/s099_test.gd     (FRIDAY 99: Portuguese UI; scripts/kine_lang.gd, data/i18n/pt_BR.po, the Language row in the start screen's Settings)
## Bars (real clicks at 1280 x 720):
##   1 ENGLISH   by default the named buttons read English; Settings has the Language choice
##   2 SWITCH    Settings > Language > Portugues: N named buttons show their pt_BR words (page tabs, Easy Part chips, Parts library, Export dialog)
##   3 FIT       no visible Button / Label text is wider than its control in Portuguese where it fitted in English (text width vs room, px)
##   4 BACK      English again gives the English words
##   5 RESTART   the choice is in the file on disk, and a NEW process comes up Portuguese
## Shots: C:/Temp/claude/s099/settings.png, parts_pt.png, export_pt.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s099"
const CFG := "user://s099_lang_test.cfg"
const LIBS := ["Screws", "Gears", "Hinges", "Bearings", "Handles", "Wheels", "Brackets", "Clips and feet", "Boards", "Wood boards", "Type it", "Favourites"]
const PT_CHECK := {
	"tab_export": "ENTREGA", "tab_animate": "ANIMAR", "tab_body": "CORPO", "tab_set": "CENA", "tab_check": "CONFERIR",
	"easypart_chip_empty": "Vazio", "easypart_chip_parts": "Peças", "easypart_more_examples": "Exemplos",
	"easypart_chip_box": "Caixa", "easypart_chip_cylinder": "Cilindro",
	"easypart_lib_Screws": "Parafusos", "easypart_lib_Gears": "Engrenagens", "easypart_lib_Hinges": "Dobradiças", "easypart_lib_Favourites": "Favoritos",
}
var EN_CHECK := {}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func node(nm: String) -> Control:
	return root.find_child(nm, true, false) as Control


func words(n: Control) -> String:
	return n.atr(String(n.get("text")))


## "" when the text fits its control, else a description (px)
func overflow(c: Control) -> String:
	var t := words(c)
	if t == "":
		return ""
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
			return ""
	else:
		return ""
	return "" if w <= room + 0.5 else "%s '%s': text %.0f px > room %.0f px" % [c.name, t, w, room]


## every visible Button / Label now: path -> overflow text, and "_n" = how many were measured
func overflows() -> Dictionary:
	var out := {}
	var n := 0
	for c in root.find_children("*", "Control", true, false):
		if not (c is Button or c is Label) or c is OptionButton or c is MenuButton or not (c as Control).is_visible_in_tree():
			continue
		n += 1
		var o := overflow(c)
		if o != "":
			out[str(c.get_path())] = o
	out["_n"] = n
	return out


func sweep() -> Dictionary:
	var acc := {}
	var n := 0
	for cat in LIBS:
		var lb := node("easypart_lib_" + cat)
		if lb != null and lb.is_visible_in_tree():
			await click_ctl(lb)
			var o := overflows()
			n = maxi(n, int(o["_n"]))
			o.erase("_n")
			acc.merge(o)
	acc["_n"] = n
	return acc


func _init() -> void:
	OS.set_environment("KINE_LANG_FILE", ProjectSettings.globalize_path(CFG))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s099_test"))
	ss.dirs_override = ["user://s099_test"]
	ss.show_screen()
	await idle(3)
	# 1 ENGLISH
	var en_ok := KineLang.current() == "en"
	for k in PT_CHECK:
		var b := node(k)
		if b != null:
			EN_CHECK[k] = String(b.get("text"))
			en_ok = en_ok and words(b) == String(b.get("text"))
	ok(en_ok and EN_CHECK.has("tab_animate"), "1 default is English (locale %s), tab_pose reads %s" % [TranslationServer.get_locale(), EN_CHECK.get("tab_animate", "?")])
	var gear := ss.find_child("settings_btn", true, false) as Button
	await click_ctl(gear)
	var pick := ss.find_child("settings_language", true, false) as OptionButton
	ok(pick != null and pick.is_visible_in_tree() and pick.get_item_text(0) == "English" and pick.get_item_text(1) == "Português" and pick.get_item_text(pick.selected) == "English", "1 Settings (real click on the gear) shows Language: English / Português, set to English")
	await shot("settings")
	await click_ctl(pick)
	var pop := pick.get_popup()
	pick.select(1)
	pick.item_selected.emit(1)
	pop.hide()
	await idle(3)
	ok(KineLang.current() == "pt_BR", "2 picking Português sets the locale (%s)" % TranslationServer.get_locale())
	ss._close()
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	var pu: PartUI = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	await click_ctl(node("easypart_chip_parts"))
	var over_pt := await sweep()
	await click_ctl(node("easypart_lib_Screws"))
	await shot("parts_pt")
	var changed := 0
	var wrong := []
	for k in PT_CHECK:
		var b := node(k)
		if b == null:
			wrong.append(k + " missing")
		elif words(b) == PT_CHECK[k] and String(b.get("text")) != PT_CHECK[k]:
			changed += 1
		else:
			wrong.append("%s=%s" % [k, words(b)])
	ok(wrong.is_empty() and changed == PT_CHECK.size(), "2 %d of %d named buttons show their pt_BR words (page tabs, Easy Part chips, Parts library) %s" % [changed, PT_CHECK.size(), str(wrong)])
	var bar_want := {"Undo": "Desfazer", "Export": "Exportar"}
	var seen_bar := 0
	var bar_ok := true
	for c in root.find_children("*", "Button", true, false):
		var t := String(c.text)
		if bar_want.has(t) and c.is_visible_in_tree():
			seen_bar += 1
			bar_ok = bar_ok and words(c) == bar_want[t]
	ok(seen_bar >= 1 and bar_ok, "2 Easy Part Undo / Export read Desfazer / Exportar (%d seen)" % seen_bar)
	m._export_dialog_open()
	await idle(4)
	var d: ConfirmationDialog = m.export_ui.dlg
	var okb := d.get_ok_button()
	var lbls := []
	for c in d.find_children("*", "Label", true, false):
		lbls.append(words(c))
	ok(d.atr(d.title) == "Exportar" and okb.atr(okb.text) == "Exportar" and "Destino" in lbls and "Formato" in lbls and "O que exportar" in lbls, "2 Export dialog: title and button Exportar, labels Destino / Formato / O que exportar %s" % str(lbls.slice(0, 4)))
	ok(m.export_ui.ui_info.text.find("Precisa:") >= 0 and m.export_ui.ui_checks.text.begins_with("Lista de conferência"), "2 Export dialog texts are Portuguese (%s)" % m.export_ui.ui_info.text.substr(0, 50).replace("\n", " "))
	ok(m.export_ui.ui_blur.atr(m.export_ui.ui_blur.text).begins_with("Vídeo de prévia"), "2 Export dialog motion-blur checkbox is Portuguese")
	var oe := overflows()
	var pt_n: int = maxi(int(oe["_n"]), int(over_pt["_n"]))
	oe.erase("_n")
	over_pt.erase("_n")
	over_pt.merge(oe)
	await shot("export_pt")
	d.hide()
	# 3 FIT: against the same controls in English
	KineLang.set_lang("en")
	await idle(3)
	var en_over := await sweep()
	m._export_dialog_open()
	await idle(4)
	en_over.merge(overflows())
	d.hide()
	var new_bad := []
	for k in over_pt:
		if not en_over.has(k):
			new_bad.append(over_pt[k])
	ok(pt_n > 60 and new_bad.is_empty(), "3 no text cut off in Portuguese at 1280 x 720: %d controls measured, %d wider than their room only in Portuguese %s" % [pt_n, new_bad.size(), str(new_bad.slice(0, 12))])
	# 4 BACK
	var back_ok := KineLang.current() == "en"
	var back_bad := []
	for k in PT_CHECK:
		var b := node(k)
		if b == null or words(b) != String(b.get("text")):
			back_ok = false
			back_bad.append(k)
	m._export_dialog_open()
	await idle(3)
	ok(back_ok and m.export_ui.ui_info.text.find("Needs:") >= 0 and m.export_ui.dlg.get_ok_button().atr("Export") == "Export", "4 back to English: the same buttons and the Export dialog read English again (locale %s, bad %s, info '%s')" % [KineLang.current(), str(back_bad), m.export_ui.ui_info.text.substr(0, 40).replace("\n", " ")])
	d.hide()
	# 5 RESTART
	KineLang.set_lang("pt_BR")
	var cf := ConfigFile.new()
	var on_disk := cf.load(CFG) == OK and String(cf.get_value("lang", "code", "")) == "pt_BR"
	ok(on_disk, "5 the choice is on disk (%s: lang/code = %s)" % [CFG, cf.get_value("lang", "code", "")])
	var outp := ProjectSettings.globalize_path("user://s099_boot_out.txt")
	DirAccess.remove_absolute(outp)
	OS.set_environment("KINE_BOOT_OUT", outp)
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--position", "-30000,-30000", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"), "-s", "tests/s099boot.gd"]))
	var t0 := Time.get_ticks_msec()
	while not FileAccess.file_exists(outp) and Time.get_ticks_msec() - t0 < 240000:
		await create_timer(1.0).timeout
	await create_timer(1.0).timeout
	OS.kill(pid)
	var line := ""
	if FileAccess.file_exists(outp):
		line = FileAccess.get_file_as_string(outp).strip_edges()
	ok(line.begins_with("pt_BR|ANIMATE|ANIMAR"), "5 a new process comes up Portuguese: [%s]" % line)
	KineLang.set_lang("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	print("s099: %d fail" % fails)
	quit()
