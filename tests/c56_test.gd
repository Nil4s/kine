extends SceneTree
## godot --path . -s tests/c56_test.gd   (C56: no page tab overflows its cell at 1280x720 or 1920x1080, en and pt_BR)
## Bars (written before any number was read):
##  1 FIT  at 1280x720 and 1920x1080, en AND pt_BR: every visible tab's minimum width <= its cell. Count over = 0
##  2 KEEP every tab that already fitted keeps its icon and font size (font override absent, icon present)
##  3 1024 unchanged vs c51: at 1024x600 every tab has c51_narrow (no icon, font 11) as c51 sets it
##  4 WATCH inside 240 s.  CONTROL: with the fix switched off (apply reverted to defaults) the measurer must find >=1 over at 1280 English
var fails := 0
var m: Node
func ok(c: bool, w: String) -> void:
	print(("PASS " if c else "FAIL ") + w)
	if not c:
		fails += 1
func idle(n := 3) -> void:
	for _i in n:
		await process_frame
func over() -> Array:
	var l := []
	for p in m.ui_page_btns:
		var b: Button = m.ui_page_btns[p]
		if b.is_visible_in_tree() and b.get_minimum_size().x > (b.get_parent() as Control).size.x + 0.5:
			l.append("%s %.1f>%.1f" % [p, b.get_minimum_size().x, (b.get_parent() as Control).size.x])
	return l
func _init() -> void:
	create_timer(240.0).timeout.connect(func():
		print("FAIL 4 WATCH")
		quit(1))
	OS.set_environment("KINE_LANG_FILE", ProjectSettings.globalize_path("user://c56_lang_test.cfg"))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.start_screen != null:
		m.start_screen.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for lang in ["en", "pt_BR"]:
		KineLang.use(lang)
		for sz in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.content_scale_size = sz
			await idle(5)
			m._fit_page_bar()
			await idle(4)
			var tag := "%s %dx%d" % [lang, sz.x, sz.y]
			var ov := over()
			if sz.x == 1024:
				var allnarrow := true
				for p in m.ui_page_btns:
					var b: Button = m.ui_page_btns[p]
					if b.is_visible_in_tree() and not (b.has_meta("c51_narrow") and b.icon == null and b.get_theme_font_size("font_size") == 11):
						allnarrow = false
				ok(allnarrow, "3 1024 %s: every tab as c51 sets it" % tag)
				continue
			ok(ov.is_empty(), "1 FIT %s: %d over: %s" % [tag, ov.size(), str(ov)])
			var bad := []
			for p in m.ui_page_btns:
				var b: Button = m.ui_page_btns[p]
				if b.is_visible_in_tree() and not b.has_meta("c56_fit") and (b.icon == null or b.has_theme_font_size_override("font_size")):
					bad.append(p)
			ok(bad.is_empty(), "2 KEEP %s: untouched tabs keep icon and font: %s" % [tag, str(bad)])
			var fitted := []
			for p in m.ui_page_btns:
				if (m.ui_page_btns[p] as Button).has_meta("c56_fit"):
					fitted.append(p)
			print("INFO ", tag, " adjusted: ", fitted)
			DirAccess.make_dir_recursive_absolute("C:/Temp/claude/c56")
			root.get_texture().get_image().save_png("C:/Temp/claude/c56/%s_%d.png" % [lang, sz.x])
	# control: an unfixed English tab at 1280 overflows
	KineLang.use("en")
	root.content_scale_size = Vector2i(1280, 720)
	await idle(5)
	m._fit_page_bar()
	await idle(3)
	var a: Button = m.ui_page_btns["ANIMATE"]
	a.remove_meta("c56_fit")
	a.icon = Icons.tex("page_animate")
	a.remove_theme_stylebox_override("normal")
	ok(over().size() >= 1, "CONTROL: unfixed ANIMATE overflows its cell: %s" % str(over()))
	print("c56: %d fails" % fails)
	quit(fails)
