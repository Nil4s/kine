extends SceneTree
## godot --path . --position 4000,4000 -s tests/settings2_test.gd     (lane L115: the accessibility / units / pie features wired into Settings)
## Bars, written BEFORE the implementation and never moved after a run (scripts/access_prefs.gd, the rows in start_screen.gd Settings):
##   1 DEFAULT  a fresh profile (no prefs file): Access.scale 1.0, Access.cb false, Units.unit "cm", main.pie_on false;
##              the Settings title label reads font size 16
##   2 EXIST    Settings (real click on the gear) shows settings_font_scale (100% / 125% / 150%), settings_colourblind (check),
##              settings_unit (cm / m / in), settings_pie (check), all visible, set to the defaults
##   3 LIVE     real selection / click on each control changes the live state, read from the app:
##              font 125% -> title label font size 20 (round(16*1.25)), 150% -> 24, back to 100% -> 16;
##              colourblind on -> Tok.c("pick_sel") equals the Access colour (differs from the default), off -> default again;
##              unit m / in -> Units.suffix() "m" / "in" and Units.len(1.7) ends with that suffix; cm -> "cm";
##              pie on -> main.pie_on true, off -> false
##   4 SAVED    after choosing 150% / colourblind on / in / pie on, the prefs file on disk holds exactly those four values
##   5 RESTART  statics reset, main freed, a NEW main booted on the same prefs file: scale 1.5, cb true, unit "in", pie_on true,
##              the Settings controls show those choices, the Settings title label reads font size 24
##   6 PLANT    the same check fed a wrong expectation (title size 20 while scale is 1.5) must report FAIL (the check can fail)
## Isolation: KINE_ACCESS_FILE names a user:// file (wtest gives each run its own APPDATA); Nick's own files are never read or written.
var fails := 0
var m: Node
const CFG := "user://settings2_access.cfg"


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


func node(nm: String) -> Control:
	return root.find_child(nm, true, false) as Control


func title_size() -> int:
	var box := node("settings_box")
	if box == null:
		return -1
	for l in box.find_children("*", "Label", true, false):
		if (l as Label).text == "Settings":
			return (l as Label).get_theme_font_size("font_size")
	return -1


func pick(nm: String, idx: int) -> void:
	var o := node(nm) as OptionButton
	if o == null:
		return
	await click_ctl(o)
	o.get_popup().hide()
	o.select(idx)
	o.item_selected.emit(idx)
	await idle(6)


func boot() -> void:
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://settings2_test"))
	ss.dirs_override = ["user://settings2_test"]
	ss.show_screen()
	await idle(4)
	await click_ctl(ss.find_child("settings_btn", true, false) as Button)
	await idle(6)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	OS.set_environment("KINE_ACCESS_FILE", ProjectSettings.globalize_path(CFG))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	await boot()
	# 1 DEFAULT
	ok(Access.scale == 1.0 and not Access.cb and Units.unit == "cm" and not m.pie_on, "1 defaults: scale %s, colourblind %s, unit %s, pie %s" % [Access.scale, Access.cb, Units.unit, m.pie_on])
	ok(title_size() == 16, "1 Settings title font size is 16 (%d)" % title_size())
	# 2 EXIST
	var fs := node("settings_font_scale") as OptionButton
	var cbx := node("settings_colourblind") as CheckBox
	var un := node("settings_unit") as OptionButton
	var pie := node("settings_pie") as CheckBox
	var found := fs != null and cbx != null and un != null and pie != null
	ok(found, "2 the four controls exist in Settings")
	if not found:
		print("settings2: %d fails (controls missing)" % (fails + 1))
		quit(fails + 1)
		return
	ok(fs.is_visible_in_tree() and cbx.is_visible_in_tree() and un.is_visible_in_tree() and pie.is_visible_in_tree(), "2 all four visible")
	ok(fs.item_count == 3 and fs.get_item_text(0).begins_with("100") and fs.get_item_text(1).begins_with("125") and fs.get_item_text(2).begins_with("150") and fs.selected == 0, "2 font scale offers 100 / 125 / 150, set to 100")
	ok(un.item_count == 3 and un.get_item_text(0) == "cm" and un.get_item_text(1) == "m" and un.get_item_text(2) == "in" and un.selected == 0, "2 unit offers cm / m / in, set to cm")
	ok(not cbx.button_pressed and not pie.button_pressed, "2 colourblind and pie unchecked")
	# 3 LIVE
	var dflt := Tok.c("pick_sel")
	await pick("settings_font_scale", 1)
	ok(Access.scale == 1.25 and title_size() == 20, "3 font 125% -> scale %s, title size %d (want 20)" % [Access.scale, title_size()])
	await pick("settings_font_scale", 2)
	ok(Access.scale == 1.5 and title_size() == 24, "3 font 150% -> scale %s, title size %d (want 24)" % [Access.scale, title_size()])
	await pick("settings_font_scale", 0)
	ok(Access.scale == 1.0 and title_size() == 16, "3 font 100% -> title size %d (want 16)" % title_size())
	await pick("settings_font_scale", 2)   # left at 150 for the save bar
	await click_ctl(cbx)
	var want: Color = Access.CB_DARK["pick_sel"] if Tok.c("pick_sel").is_equal_approx(Access.CB_DARK["pick_sel"]) else Access.CB_LIGHT["pick_sel"]
	ok(Access.cb and cbx.button_pressed and not Tok.c("pick_sel").is_equal_approx(dflt) and Tok.c("pick_sel").is_equal_approx(want), "3 colourblind click -> on, pick_sel changed")
	await click_ctl(cbx)
	ok(not Access.cb and Tok.c("pick_sel").is_equal_approx(dflt), "3 colourblind click again -> off, pick_sel back")
	await click_ctl(cbx)   # on for the save bar
	await pick("settings_unit", 1)
	ok(Units.unit == "m" and Units.suffix() == "m" and Units.len(1.7).ends_with("m") and not Units.len(1.7).ends_with("cm"), "3 unit m -> suffix %s, 1.7 reads %s" % [Units.suffix(), Units.len(1.7)])
	await pick("settings_unit", 0)
	ok(Units.unit == "cm" and Units.len(1.7).ends_with("cm"), "3 unit cm -> 1.7 reads %s" % Units.len(1.7))
	await pick("settings_unit", 2)
	ok(Units.unit == "in" and Units.suffix() == "in" and Units.len(1.7).ends_with("in"), "3 unit in -> 1.7 reads %s" % Units.len(1.7))
	await click_ctl(pie)
	ok(m.pie_on and pie.button_pressed, "3 pie click -> main.pie_on true")
	await click_ctl(pie)
	ok(not m.pie_on, "3 pie click again -> false")
	await click_ctl(pie)
	# 4 SAVED
	var cf := ConfigFile.new()
	var lr := cf.load(CFG)
	var sec := "access"
	ok(lr == OK and is_equal_approx(float(cf.get_value(sec, "font_scale", -1)), 1.5) and bool(cf.get_value(sec, "colourblind", false)) and String(cf.get_value(sec, "unit", "")) == "in" and bool(cf.get_value(sec, "pie", false)), "4 prefs file holds 1.5 / colourblind / in / pie (load %d)" % lr)
	# 5 RESTART
	m.queue_free()
	await idle(6)
	Access.set_colourblind(false)
	Access.scale = 1.0
	Units.unit = "cm"
	await boot()
	ok(is_equal_approx(Access.scale, 1.5) and Access.cb and Units.unit == "in" and m.pie_on, "5 restart: scale %s, cb %s, unit %s, pie %s" % [Access.scale, Access.cb, Units.unit, m.pie_on])
	fs = node("settings_font_scale") as OptionButton
	cbx = node("settings_colourblind") as CheckBox
	un = node("settings_unit") as OptionButton
	pie = node("settings_pie") as CheckBox
	ok(fs != null and fs.selected == 2 and cbx.button_pressed and un.selected == 2 and pie.button_pressed, "5 restart: Settings controls show the saved choices")
	await idle(6)
	ok(title_size() == 24, "5 restart: Settings title size %d (want 24)" % title_size())
	# 6 PLANT
	var planted := title_size() == 20
	ok(not planted, "6 PLANT: a wrong expectation (20 at scale 1.5) is rejected")
	print("settings2: %d fails" % fails)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	quit(fails)
