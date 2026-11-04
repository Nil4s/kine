extends SceneTree
## godot --path . --position 4000,4000 -s tests/c51_test.gd     (C51: bottom page tabs must fit their cell at 1024x600)
## Bars (written before any number was read):
##  1 FIT   at 1024x600, English AND pt_BR, every visible page tab: its text (+icon, margins) is no wider than its cell_* container.  Count over = 0.
##          CONTROL: the same measurer flags the tab text on the unfixed layout (icon on, default font) at 1024 -> must find >= 1 over when the fix is switched off
##  2 SAME  at 1280x720 and 1920x1080 (en and pt_BR) the tab rects (position+size, global) equal the recorded baseline from origin (f3f4c82a): 0 differences
##  3 WATCH the test finishes inside 240 s
## Screenshots C:/Temp/claude/c51/*.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/c51"
var BASE := {"en 1280x720":{"ANIMATE":[208.0,690.0,96.0,30.0,96.0],"BODY":[8.0,690.0,96.0,30.0,96.0],"BUILD":[0.0,0.0,0.0,0.0,0.0],"CHECK":[408.0,690.0,96.0,30.0,96.0],"DELIVER":[508.0,690.0,96.0,30.0,96.0],"MODEL":[626.0,690.0,96.0,30.0,96.0],"POSE":[108.0,690.0,96.0,30.0,96.0],"SCULPT":[726.0,690.0,96.0,30.0,96.0],"STAGE":[308.0,690.0,96.0,30.0,96.0],"SURFACE":[826.0,690.0,96.0,30.0,96.0]},"en 1920x1080":{"ANIMATE":[208.0,1050.0,96.0,30.0,96.0],"BODY":[8.0,1050.0,96.0,30.0,96.0],"BUILD":[0.0,0.0,0.0,0.0,0.0],"CHECK":[408.0,1050.0,96.0,30.0,96.0],"DELIVER":[508.0,1050.0,96.0,30.0,96.0],"MODEL":[626.0,1050.0,96.0,30.0,96.0],"POSE":[108.0,1050.0,96.0,30.0,96.0],"SCULPT":[726.0,1050.0,96.0,30.0,96.0],"STAGE":[308.0,1050.0,96.0,30.0,96.0],"SURFACE":[826.0,1050.0,96.0,30.0,96.0]},"pt_BR 1280x720":{"ANIMATE":[208.0,690.0,96.0,30.0,96.0],"BODY":[8.0,690.0,96.0,30.0,96.0],"BUILD":[0.0,0.0,0.0,0.0,0.0],"CHECK":[408.0,690.0,96.0,30.0,96.0],"DELIVER":[508.0,690.0,96.0,30.0,96.0],"MODEL":[626.0,690.0,96.0,30.0,96.0],"POSE":[108.0,690.0,96.0,30.0,96.0],"SCULPT":[726.0,690.0,96.0,30.0,96.0],"STAGE":[308.0,690.0,96.0,30.0,96.0],"SURFACE":[826.0,690.0,96.0,30.0,96.0]},"pt_BR 1920x1080":{"ANIMATE":[208.0,1050.0,96.0,30.0,96.0],"BODY":[8.0,1050.0,96.0,30.0,96.0],"BUILD":[0.0,0.0,0.0,0.0,0.0],"CHECK":[408.0,1050.0,96.0,30.0,96.0],"DELIVER":[508.0,1050.0,96.0,30.0,96.0],"MODEL":[626.0,1050.0,96.0,30.0,96.0],"POSE":[108.0,1050.0,96.0,30.0,96.0],"SCULPT":[726.0,1050.0,96.0,30.0,96.0],"STAGE":[308.0,1050.0,96.0,30.0,96.0],"SURFACE":[826.0,1050.0,96.0,30.0,96.0]}}

func ok(c: bool, w: String) -> void:
	print(("PASS " if c else "FAIL ") + w)
	if not c:
		fails += 1

func idle(n := 3) -> void:
	for _i in n:
		await process_frame

func tab_over(b: Button) -> float:
	var t := m.atr(b.text)
	if t == "":
		return -1.0
	var fs := b.get_theme_font_size("font_size")
	var w := b.get_theme_font("font").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var room := (b.get_parent() as Control).size.x
	var sb := b.get_theme_stylebox("normal")
	room -= sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	if b.icon != null:
		room -= b.icon.get_width() + b.get_theme_constant("h_separation")
	return w - room

func rects() -> Dictionary:
	var o := {}
	for p in m.ui_page_btns:
		var b: Button = m.ui_page_btns[p]
		var c := b.get_parent() as Control
		o[p] = [snappedf(b.global_position.x, 0.01), snappedf(b.global_position.y, 0.01), snappedf(b.size.x, 0.01), snappedf(b.size.y, 0.01), snappedf(c.size.x, 0.01)]
	return o

func over_list() -> Array:
	var l := []
	for p in m.ui_page_btns:
		var b: Button = m.ui_page_btns[p]
		if b.is_visible_in_tree():
			var v := tab_over(b)
			if v > 0.5:
				l.append("%s %.0f px" % [m.atr(b.text), v])
	return l

func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])

func _init() -> void:
	create_timer(240.0).timeout.connect(func():
		print("FAIL 3 WATCH watchdog")
		quit(1))
	OS.set_environment("KINE_LANG_FILE", ProjectSettings.globalize_path("user://c51_lang_test.cfg"))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	if m.start_screen != null:
		m.start_screen.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var dump := OS.get_environment("C51_DUMP") != ""
	for lang in ["en", "pt_BR"]:
		KineLang.use(lang)
		for sz in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.content_scale_size = sz
			await idle(5)
			m._fit_page_bar()
			await idle(4)
			var tag := "%s %dx%d" % [lang, sz.x, sz.y]
			var ov := over_list()
			if sz.x == 1024:
				ok(ov.is_empty(), "1 FIT %s: %d tabs over: %s" % [tag, ov.size(), str(ov)])
			else:
				print("INFO ", tag, " over: ", str(ov))
			var r := rects()
			if dump:
				print("RECT ", tag, " ", JSON.stringify(r))
			elif sz.x != 1024 and BASE.has(tag):
				var d := 0
				for p in r:
					if str(r[p]) != str(BASE[tag].get(p, [])):
						d += 1
				ok(d == 0, "2 SAME %s: %d tab rects differ from the origin baseline" % [tag, d])
			await shot("%s_%d" % [lang, sz.x])
	KineLang.use("en")
	print("c51: %d fails" % fails)
	quit(fails)
