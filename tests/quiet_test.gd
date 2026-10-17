## godot --path . -s tests/quiet_test.gd     (GATES RR5; needs a window)
## QUIET WORDS: one status line, small and grey (at most 13 px; a STOP reason in amber), the readout on it at most 12
## px; the camera bar on the same line; the 3D part tag at most 18 px (Label3D fixed-size: its font size is its height
## on screen). The yellow teaching strip (the welcome) shows on a FIRST start only: a fresh settings file shows it; the
## first pick says something else and ends it for good (the settings record it); a second start on the same settings
## shows no strip.
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


func boot() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false


func fs(l: Label) -> int:
	return l.get_theme_font_size("font_size")


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://poser_test_%d.cfg" % OS.get_process_id()))   # a first start
	await boot()
	var cf := ConfigFile.new()
	ok(m.ui_status.text == m.WELCOME and m.ui_status.is_visible_in_tree() and fs(m.ui_status) == 16 and m.ui_status.get_theme_stylebox("normal") == m.ui_say_box,
		"first start: the yellow teaching strip shows the welcome (%d px, its box)" % fs(m.ui_status))
	# the first pick: a real click on the head
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._view_home(false)
	await idle(4)
	var p: Vector2 = m.cam.unproject_position((m.B.cap("head")[0] + m.B.cap("head")[1]) * 0.5)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(3)
	cf.load(m.settings)
	var line: Rect2 = m.ui_status.get_global_rect()
	var bar: Rect2 = m.ui_bar.get_global_rect()
	var nav: Rect2 = m.ui_nav.get_global_rect()
	ok(m.sel == "head" and m.ui_status.text != m.WELCOME and cf.get_value("look", "taught", false) == true, "the first pick (head, a real click): the welcome is gone ('%s'), the settings say taught" % m.ui_status.text.left(40))
	m._say("something said after the pick")   # the line's look is read from a message
	await idle()
	ok(fs(m.ui_status) <= 13 and m.ui_status.get_theme_stylebox("normal") is StyleBoxEmpty and fs(m.ui_bar) <= 12, "the line: messages %d px with no box, the readout %d px" % [fs(m.ui_status), fs(m.ui_bar)])
	var grey: Color = m.ui_status.get_theme_color("font_color")
	ok(grey.is_equal_approx(Tok.of("text:0.7")), "  a message is grey %s" % grey)
	ok(absf(line.get_center().y - nav.get_center().y) < 4.0 and absf(bar.get_center().y - nav.get_center().y) < 4.0 and not line.intersects(nav) and not bar.intersects(nav) and not line.intersects(bar),
		"  ONE line: the messages %s, the readout %s and the camera bar %s on one row, apart" % [line, bar, nav])
	m._say("rotated the left elbow     STOPPED: the left elbow / forearm is at its limit, bend 150 (its range 0 to 150)")
	await idle()
	ok(m.ui_status.get_theme_color("font_color").is_equal_approx(Tok.c("warn")), "  a STOP reason is amber %s" % m.ui_status.get_theme_color("font_color"))
	ok(m.tag.font_size <= 18 and m.hit_tag.font_size <= 18 and m.tag.fixed_size, "the 3D part tag %d px, the hit tag %d px (at most 18)" % [m.tag.font_size, m.hit_tag.font_size])
	# a second start, the same settings: no strip
	var path: String = m.settings
	var kept := FileAccess.get_file_as_string(path)
	m.queue_free()
	await idle(3)
	# a test's own settings file is removed on exit (the harness's clean-up, not the app's): put it back, as a real
	# start finds its settings
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_string(kept)
	w.close()
	await boot()
	ok(m.settings == path and m.ui_status.text != m.WELCOME and not m._teach_pending, "a second start on the same settings: no teaching strip ('%s')" % m.ui_status.text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("QUIET TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
