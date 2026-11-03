extends SceneTree
## godot --headless --path . -s tests/c11_test.gd      (C11: complaints #804 pt_BR gaps check, #830 sticky keys, #19 bad GPU driver list)
## Bars (written before any number was read):
##  1 SCAN    the scanner reads >= 300 UI strings from scripts/ and >= 300 msgids from pt_BR.po
##  2 CONTROL a planted script line with an untranslated string is reported missing; a translated one ("BODY") is not (the check can fail)
##  3 REPORT  missing count is printed; with C11_STRICT=1 any missing string FAILS (the release gate); default only reports
##  4 STICKY  off: tap Shift then a key -> no shift. on: tap latches, next key has shift, the one after does not; tap twice unlatches;
##            Shift HELD across a key is a chord and latches nothing; Ctrl+Alt both latch; a click takes the latch; default is off
##  5 GPU     fixture list: matching vendor+version gives ONE line (no newline) naming the driver; other version / vendor gives "";
##            the shipped file parses with a "bad" array; a missing file gives []
##  6 UI      Settings has an UNCHECKED "Sticky keys" box (screenshot C:/Temp/claude/c11/settings.png at 1280x720)
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func key(k: int, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = down
	return e


func tap(sk: StickyKeys, k: int) -> void:
	sk.filter(key(k, true))
	sk.filter(key(k, false))


func _init() -> void:
	OS.set_environment("KINE_STICKY_FILE", ProjectSettings.globalize_path("user://c11_sticky_test.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://c11_sticky_test.cfg"))
	OS.set_environment("KINE_LANG_FILE", ProjectSettings.globalize_path("user://c11_lang_test.cfg"))
	var strs := I18nScan.all_strings()
	var ids := I18nScan.msgids()
	ok(strs.size() >= 300 and ids.size() >= 300, "1 SCAN %d UI strings, %d msgids" % [strs.size(), ids.size()])
	var planted := I18nScan.strings_in("b.text = \"Zzq planted words\"\nc.text = \"BODY\"\nd.text = \"x %d\"\n")
	var miss := I18nScan.missing({"Zzq planted words": true, "BODY": true}, ids)
	ok(planted == ["Zzq planted words", "BODY"] and miss == ["Zzq planted words"], "2 CONTROL planted untranslated string is the only one reported (%s)" % str(miss))
	var gaps := I18nScan.missing(strs, ids)
	print("pt_BR MISSING: %d of %d UI strings" % [gaps.size(), strs.size()])
	var f := FileAccess.open("user://c11_missing.txt", FileAccess.WRITE)
	f.store_string("\n".join(gaps))
	f.close()
	if OS.get_environment("C11_STRICT") == "1":
		ok(gaps.is_empty(), "3 STRICT every UI string has a pt_BR msgid (%d missing, see %s)" % [gaps.size(), ProjectSettings.globalize_path("user://c11_missing.txt")])
	else:
		ok(true, "3 REPORT %d missing (C11_STRICT=1 makes it a failure)" % gaps.size())
	# 4
	var sk := StickyKeys.new()
	ok(not sk.on and not StickyKeys.saved(), "4 off by default (object and file)")
	tap(sk, KEY_SHIFT)
	var a := key(KEY_A, true)
	sk.filter(a)
	ok(not a.shift_pressed, "4 off: tap Shift then A -> no shift")
	sk.set_on(true)
	tap(sk, KEY_SHIFT)
	ok(sk.label() == "Shift", "4 on: tap latches Shift (%s)" % sk.label())
	var b := key(KEY_A, true)
	sk.filter(b)
	var c := key(KEY_B, true)
	sk.filter(c)
	ok(b.shift_pressed and not c.shift_pressed and sk.label() == "", "4 next key has shift, the one after does not")
	tap(sk, KEY_SHIFT)
	tap(sk, KEY_SHIFT)
	ok(sk.label() == "", "4 two taps unlatch")
	sk.filter(key(KEY_SHIFT, true))
	sk.filter(key(KEY_A, true))
	sk.filter(key(KEY_A, false))
	sk.filter(key(KEY_SHIFT, false))
	ok(sk.label() == "", "4 Shift held across a key is a chord, latches nothing")
	tap(sk, KEY_CTRL)
	tap(sk, KEY_ALT)
	var d := key(KEY_Z, true)
	sk.filter(d)
	ok(d.ctrl_pressed and d.alt_pressed and not d.shift_pressed, "4 Ctrl+Alt both latch and apply")
	tap(sk, KEY_SHIFT)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	sk.filter(mb)
	ok(mb.shift_pressed and sk.label() == "", "4 a click takes the latch")
	# 5
	var list := [{"vendor": "nvidia|geforce", "versions": ["999.1"], "note": "crash at launch", "fix": "Roll back."}]
	var w := GpuDrivers.warning("NVIDIA GeForce RTX 3070", "999.15", list)
	ok(w != "" and w.find("\n") < 0 and w.find("999.15") >= 0 and w.find("Roll back.") >= 0, "5 match gives one line: %s" % w)
	ok(GpuDrivers.warning("NVIDIA GeForce RTX 3070", "555.0", list) == "" and GpuDrivers.warning("AMD Radeon", "999.15", list) == "", "5 other version / vendor: no warning")
	var shipped = JSON.parse_string(FileAccess.get_file_as_string(GpuDrivers.FILE))
	ok(shipped is Dictionary and shipped.get("bad") is Array, "5 shipped data/gpu_bad_drivers.json parses with a bad[] list")
	ok(GpuDrivers.rows("res://nope.json") == [], "5 a missing file gives [] and never blocks")
	# 6
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 8:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://c11_test"]
	ss.show_screen()
	for i in 4:
		await process_frame
	var gear := ss.find_child("settings_btn", true, false) as Button
	gear.pressed.emit()
	for i in 4:
		await process_frame
	var cb := ss.find_child("settings_sticky_keys", true, false) as CheckBox
	ok(cb != null and cb.is_visible_in_tree() and not cb.button_pressed and not m.sticky.on, "6 Settings shows Sticky keys, unchecked, off")
	if cb != null:
		cb.button_pressed = true
		ok(m.sticky.on and StickyKeys.saved(), "6 ticking it turns sticky on and remembers it")
		cb.button_pressed = false
		ok(not m.sticky.on and not StickyKeys.saved(), "6 unticking turns it off")
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/c11")
	root.get_texture().get_image().save_png("C:/Temp/claude/c11/settings.png")
	print("c11: %d fails" % fails)
	quit(fails)
