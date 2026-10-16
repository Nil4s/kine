## godot --path . -s tests/icons_test.gd     (GATES P5; needs a window)
## Every ribbon tool button (each tab's, and Undo / Redo / Search / Help) has a code-drawn icon (scripts/icons.gd):
## the icon has ink but is not a filled square, no two icons are the same picture, every tab's buttons fit INSIDE the
## bar (bottom <= TOP_H) and on the screen, and the icon tint is the palette's in dark and in light.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var light0 := not Tok.dark
	if light0:
		m._set_light(false)
	var w: float = root.get_visible_rect().size.x
	var all := []
	var seen := {}
	var dup := []
	var thin := []
	for tab in m.RIBBON:
		m._ribbon(tab)
		await process_frame
		await process_frame
		var low := 0.0
		var right := 0.0
		var no_icon := []
		for b in m.ui_ribbon[tab].get_children():
			if not b is Button:
				continue
			all.append(b)
			if b.icon == null:
				no_icon.append(b.text)
				continue
			low = maxf(low, b.get_global_rect().end.y)
			right = maxf(right, b.get_global_rect().end.x)
		ok(no_icon.is_empty(), "%s: every tool button has an icon %s" % [tab, no_icon if not no_icon.is_empty() else ""])
		ok(low <= m.TOP_H and right <= w, "%s: the buttons end at y %.0f (bar %d) and x %.0f (screen %.0f)" % [tab, low, m.TOP_H, right, w])
	var help: Button = null
	for t in ["Undo (Ctrl+Z)", "Redo (Ctrl+Y)", "Search (S)", "? Help"]:
		for b in m.ui_root.get_child(0).get_child(0).get_children():
			if b is Button and b.text == t:
				all.append(b)
				help = b
	ok(all.size() >= 26, "%d ribbon buttons found (26 expected)" % all.size())
	for b in all:
		if b.icon == null:
			continue
		var img: Image = b.icon.get_image()
		var ink := 0.0
		var full := 0
		for y in img.get_height():
			for x in img.get_width():
				var a := img.get_pixel(x, y).a
				ink += a
				full += 1 if a > 0.5 else 0
		var share := float(full) / (img.get_width() * img.get_height())
		if ink < 15.0 or share > 0.6:
			thin.append("%s ink %.0f, %.0f%% solid" % [b.text, ink, share * 100.0])
		var key := img.get_data().hex_encode().sha256_text()
		if seen.has(key):
			dup.append("%s = %s" % [b.text, seen[key]])
		seen[key] = b.text
	ok(thin.is_empty(), "every icon has ink and is not a block %s" % [thin if not thin.is_empty() else ""])
	ok(dup.is_empty(), "%d distinct pictures %s" % [seen.size(), dup if not dup.is_empty() else ""])
	ok(help != null and help.get_global_rect().end.y <= m.TOP_H and help.get_global_rect().end.x <= w, "'? Help' inside the bar and on screen")
	for dark in [true, false]:
		m._set_light(not dark)
		await process_frame
		var b: Button = all[0]
		var got: Color = b.get_theme_color("icon_normal_color")
		ok(got == Tok.c("btn_text"), "%s: the icons are tinted the palette's button text %s" % ["dark" if dark else "light", got])
	m._set_light(light0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("ICONS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
