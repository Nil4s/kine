## godot --path . -s tests/themescale_test.gd     (ROADMAP 58; needs a window, 1366 x 728 = a laptop's screen less its taskbar)
## 1. THE FIRST-START SCALE: auto_scale picks 100 for 1366 x 768 and 1920 x 1080 (96 dpi), 150 for a 3840 x 2160 screen, and
##    at every pick the ribbon's top bar (751 px at its widest, measured) is inside the window at that scale.
## 2. LIVE: the window at 1366 x 728 gets the auto pick; the '? Help' button (the ribbon's last) ends inside the window and
##    nothing outside a scroll area is off the window. The pick is not saved to poser.cfg.
## 3. THE THEME: "follow the system" takes Windows' dark flag (a stub here), and a focus-in re-reads it.
## 4. RE-TINT: in each palette, a sample of pixels from the ribbon, the timeline, the browser, the status line and the
##    play-options panel: at least half of each panel's samples change colour between light and dark. A side-by-side
##    screenshot of both palettes at laptop size is written to user://themescale_side.png (THEMESCALE_SHOT overrides).
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func off_screen() -> Array:
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	var out := []
	for c in m.ui_root.find_children("*", "Control", true, false):
		var cc := c as Control
		if not cc.is_visible_in_tree() or _in_scroll(cc) or cc is ScrollContainer:
			continue
		var r := cc.get_global_rect()
		if r.size.x > 0 and (r.end.x > vr.end.x + 1 or r.end.y > vr.end.y + 1 or r.position.x < -1):
			out.append("%s '%s'" % [cc.get_class(), cc.get("text") if cc.get("text") != null else cc.name])
	return out


func frames(n: int) -> void:
	for k in n:
		await process_frame


## the panel's pixels: a 5 x 3 grid inside its rect, read from the rendered frame
func sample(img: Image, r: Rect2) -> Array:
	var out := []
	for fx in [0.1, 0.3, 0.5, 0.7, 0.9]:
		for fy in [0.2, 0.5, 0.8]:
			var x := clampi(int(r.position.x + r.size.x * fx), 0, img.get_width() - 1)
			var y := clampi(int(r.position.y + r.size.y * fy), 0, img.get_height() - 1)
			out.append(img.get_pixel(x, y))
	return out


func shot() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	# ---- 1. the pure pick, with injected sizes
	var ribbon := 751.0   # the top bar's width at its widest tab, at 100 % (measured in the probe, tests/probe_ribbon_w.gd)
	var pick_1366: int = m.auto_scale(Vector2(1366, 728), Vector2(1366, 768), 96.0, ribbon)
	var pick_1920: int = m.auto_scale(Vector2(1920, 1040), Vector2(1920, 1080), 96.0, ribbon)
	var pick_4k: int = m.auto_scale(Vector2(3840, 2080), Vector2(3840, 2160), 144.0, ribbon)
	var pick_4k96: int = m.auto_scale(Vector2(3840, 2080), Vector2(3840, 2160), 96.0, ribbon)
	ok(pick_1366 == 100, "1366 x 768 laptop picks %d %% (the ribbon %.0f px fits 1366 at it)" % [pick_1366, ribbon])
	ok(pick_1920 == 100, "1920 x 1080 picks %d %%" % pick_1920)
	ok(pick_4k == 150 and pick_4k96 == 150, "3840 x 2160 picks %d %% (144 dpi) and %d %% (96 dpi): 1.5" % [pick_4k, pick_4k96])
	var fit := true
	for c in [[Vector2(1366, 728), pick_1366], [Vector2(1920, 1040), pick_1920], [Vector2(3840, 2080), pick_4k]]:
		var p: int = c[1]
		fit = fit and ribbon <= (c[0] as Vector2).x / (p / 100.0) and (c[0] as Vector2).y / (p / 100.0) >= m.MIN_ROOM.y - 1.0
	ok(fit, "at each pick the top bar is inside the window (its right edge <= the window's width at that scale)")
	var small: int = m.auto_scale(Vector2(1024, 600), Vector2(1024, 768), 96.0, ribbon)
	ok(small == 90 or small == 100, "a 1024 x 600 window still gets a size (%d %%); the window's own min size stops it smaller" % small)
	var hidpi: int = m.auto_scale(Vector2(1920, 1040), Vector2(1920, 1080), 120.0, ribbon)
	ok(hidpi == 125, "1920 x 1080 at 120 dpi (Windows 125 %%) picks %d %%" % hidpi)

	# ---- 2. live, at the laptop size, from a fresh test settings file
	m.get_window().size = Vector2i(1366, 728)
	await frames(3)
	m.scale_auto = true
	m._auto_scale_now()
	await frames(4)
	var vw: float = m.get_viewport().get_visible_rect().size.x
	var help: Control = m.ui_top_right[-1]
	ok(m.ui_scale == 100 and is_equal_approx(m.get_window().content_scale_factor, 1.0), "live: the window at 1366 x 728 got %d %%" % m.ui_scale)
	ok(help.get_global_rect().end.x <= vw and m.ui_top_bar.get_global_rect().end.x <= vw, "live: '? Help' ends at %.0f, the top bar at %.0f, of %.0f" % [help.get_global_rect().end.x, m.ui_top_bar.get_global_rect().end.x, vw])
	var off := off_screen()
	ok(off.is_empty(), "live: nothing off the 1366 x 728 window %s" % [off])
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(not cf.has_section_key("look", "scale"), "the auto pick is not saved (poser.cfg has no look/scale until the user picks)")

	# ---- 3. follow the system: a stubbed dark flag
	var dark_flag := [true]
	m.sys_dark_probe = Callable(func(): return dark_flag[0])
	m._set_theme_system(true)
	await frames(2)
	ok(m.theme_pref == "system" and Tok.dark, "follow system, Windows dark: the palette is dark")
	dark_flag[0] = false
	m._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await frames(2)
	ok(not Tok.dark, "Windows switched to light, the window regains focus: the palette is light")
	dark_flag[0] = true
	m._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	ok(Tok.dark, "and back to dark on the next focus")
	m._set_light(true)
	await frames(2)
	ok(m.theme_pref == "light" and not Tok.dark, "an explicit Light choice: follow system is off, light stays whatever Windows says")
	dark_flag[0] = false
	m._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	ok(not Tok.dark, "explicit light ignores the system flag")
	cf.load(m.settings)
	ok(cf.get_value("look", "theme", "") == "light" and cf.get_value("look", "light", false) == true, "saved: look/theme = light, look/light = true")
	m._set_theme_system(true)
	await frames(2)
	cf.load(m.settings)
	ok(cf.get_value("look", "theme", "") == "system", "follow system on again is saved (look/theme = system)")

	# ---- 4. re-tint audit: every panel's pixels change between the palettes
	m._ribbon("POSE")
	m._gear_open()   # the play-options panel (a popup on the UI)
	await frames(3)
	var panels := {"ribbon": m.ui_top_bar, "timeline": m.ui_timeline, "browser": m.ui_browser, "status bar": m.ui_status, "popup": m.ui_gear}
	var rects := {}
	for k in panels:
		rects[k] = (panels[k] as Control).get_global_rect()
	var imgs := {}
	for want_dark in [true, false]:
		m._set_light(not want_dark)
		await frames(3)
		imgs[want_dark] = await shot()
	var bad := []
	for k in panels:
		var a := sample(imgs[true], rects[k])
		var b := sample(imgs[false], rects[k])
		var changed := 0
		for i in a.size():
			var d: float = absf(a[i].r - b[i].r) + absf(a[i].g - b[i].g) + absf(a[i].b - b[i].b)
			if d > 0.12:
				changed += 1
		var frac := float(changed) / a.size()
		ok(frac >= 0.5, "re-tint %-10s: %d of %d samples changed (dark %s, light %s)" % [k, changed, a.size(), a[0], b[0]])
		if frac < 0.5:
			bad.append(k)
	# the side-by-side at laptop size: dark on the left, light on the right
	var w: int = imgs[true].get_width()
	var h: int = imgs[true].get_height()
	var side := Image.create(w * 2 + 16, h, false, Image.FORMAT_RGB8)
	side.fill(Color(0.5, 0.5, 0.5))
	side.blit_rect(imgs[true], Rect2i(0, 0, w, h), Vector2i(0, 0))
	side.blit_rect(imgs[false], Rect2i(0, 0, w, h), Vector2i(w + 16, 0))
	var path := OS.get_environment("THEMESCALE_SHOT")
	if path == "":
		path = "user://themescale_side.png"
	var err := side.save_png(path)
	print("shot: %s (%d x %d per palette)" % [ProjectSettings.globalize_path(path) if path.begins_with("user://") else path, w, h])
	ok(err == OK, "the side-by-side screenshot is written (%s)" % err)

	# ---- restore: the test's own file goes; the user's poser.cfg is never touched
	m._set_light(true)
	m._set_theme_system(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("THEMESCALE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)

