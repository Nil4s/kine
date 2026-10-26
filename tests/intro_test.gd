## godot --path . -s tests/intro_test.gd     (the opening intro, scripts/intro/intro.gd; Nick 10-23)
## Bars, written before measuring:
##   1 SKIPS UNDER TESTS: main.tscn started by a test script has no intro (main.intro null, no KineIntro in the tree);
##     wanted() is false for a test, headless, --shot, --tour, --no-intro and [intro] show = false, true for a plain start;
##     the concept comes from --intro X, else [intro] concept, else B (Nick's pick).
##   2 A KEY SKIPS WITHIN 1 FRAME: a key press pushed into the window hides it at once (the event is marked handled, so
##     the app never sees it) and it is gone from the tree one frame later; the same for a mouse click.
##   3 LENGTH: each concept, stepped at 60 fps until it frees itself, lasts 2.5 .. 4 s (and length() says the same).
##   4 PLACEMENT: at 1280 x 720 and 2560 x 1440 (a SubViewport of that size), in the end card's hold, the mark, the
##     wordmark and "Teschima Studios" are drawn whole inside the window with a 5 % margin, the studio line under the
##     lock-up, centred on it within 2 px, at least 11 px tall; the lock-up is centred in the window within 2 px.
##   5 COST: making it and its first frame take under 100 ms (it starts after the app has loaded: this is all it adds).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 1 -------------------------------------------------------------- skips under tests
	var m: Node = load("res://main.tscn").instantiate()
	root.add_child(m)
	await idle(4)
	var found := false
	for n in root.find_children("*", "CanvasLayer", true, false):
		if n is KineIntro:
			found = true
	ok(m.intro == null and not found, "1 a test's start of main has no intro (main.intro %s, one in the tree: %s)" % [m.intro, found])
	m.queue_free()
	await idle(2)
	var cf := ConfigFile.new()
	var none := PackedStringArray()
	ok(not KineIntro.wanted(cf, true, none), "1 not wanted under a test")
	var head := DisplayServer.get_name() == "headless"
	ok(KineIntro.wanted(cf, false, none) != head, "1 wanted on a plain start (display %s)" % DisplayServer.get_name())
	for a in ["--shot", "--tour", "--no-intro"]:
		ok(not KineIntro.wanted(cf, false, PackedStringArray([a, "x"])), "1 not wanted with " + a)
	var off := ConfigFile.new()
	off.set_value("intro", "show", false)
	ok(not KineIntro.wanted(off, false, none), "1 [intro] show = false turns it off")
	off.set_value("intro", "concept", "c")
	ok(KineIntro.concept_from(off, none) == "C" and KineIntro.concept_from(off, PackedStringArray(["--intro", "b"])) == "B"
		and KineIntro.concept_from(cf, none) == "B" and KineIntro.concept_from(cf, PackedStringArray(["--intro", "Z"])) == "B",
		"1 the concept: --intro, then [intro] concept, else B")

	# 5 -------------------------------------------------------------- cost
	var t0 := Time.get_ticks_usec()
	var k := KineIntro.make("A")
	root.add_child(k)
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	ok(ms < 100.0, "5 made and its first frame in %.1f ms (bar 100)" % ms)

	# 2 -------------------------------------------------------------- a key skips within one frame
	await idle(3)
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	root.push_input(ev)
	var hidden_now := not k.visible
	var handled := root.is_input_handled()
	await process_frame
	ok(hidden_now and handled, "2 a key hides it at once (hidden %s, the event handled %s)" % [hidden_now, handled])
	ok(not is_instance_valid(k), "2 ... and it is gone one frame later")
	var k2 := KineIntro.make("B")
	root.add_child(k2)
	await idle(3)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(200, 200)
	root.push_input(mb)
	var hidden2 := not k2.visible
	await process_frame
	ok(hidden2 and not is_instance_valid(k2), "2 a click does the same")
	var mm := InputEventMouseMotion.new()
	var k3 := KineIntro.make("C")
	root.add_child(k3)
	await idle(2)
	mm.position = Vector2(300, 300)
	root.push_input(mm)
	await process_frame
	ok(is_instance_valid(k3) and k3.visible, "2 moving the mouse does not skip it")
	k3.skip()
	await idle(1)

	# 3 -------------------------------------------------------------- length, stepped at 60 fps
	for c in KineIntro.CONCEPTS:
		var ki := KineIntro.make(c)
		ki.set_process(false)   # stepped by hand
		root.add_child(ki)
		var said := ki.length()
		var steps := 0
		while is_instance_valid(ki) and not ki._done and steps < 1000:
			ki._process(1.0 / 60.0)
			steps += 1
		var secs := steps / 60.0
		ok(secs >= 2.5 and secs <= 4.0 and absf(secs - said) < 0.05, "3 %s lasts %.2f s (bar 2.5 .. 4; length() %.2f)" % [c, secs, said])
		await idle(1)

	# 4 -------------------------------------------------------------- placement
	for sz in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		for c in KineIntro.CONCEPTS:
			var sv := SubViewport.new()
			sv.size = sz
			sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(sv)
			var ki := KineIntro.make(c)
			sv.add_child(ki)
			await process_frame
			ki.t = ki.mark_at() + KineIntro.BUILD + 0.05   # in the hold
			await idle(3)
			var last: Dictionary = ki.last
			var win := Rect2(Vector2.ZERO, Vector2(sz))
			var inner := win.grow(-0.05 * sz.y)
			var have := last.has("mark") and last.has("word") and last.has("studio")
			if not have:
				ok(false, "4 %s at %s: the end card drew %s" % [c, sz, last.keys()])
				sv.queue_free()
				continue
			var mark: Rect2 = last["mark"]
			var word: Rect2 = last["word"]
			var st: Rect2 = last["studio"]
			var lock := mark.merge(word)
			ok(inner.encloses(mark) and inner.encloses(word) and inner.encloses(st),
				"4 %s at %dx%d: mark %s, word %s, studio %s inside %s" % [c, sz.x, sz.y, mark, word, st, inner])
			ok(String(last.get("studio_text", "")) == "Teschima Studios" and st.position.y >= lock.end.y and st.size.y >= 11.0
				and absf(st.get_center().x - lock.get_center().x) <= 2.0,
				"4 %s at %dx%d: \"%s\" under the lock-up (top %.0f >= %.0f), %.0f px tall, centred on it (off %.1f px)" % [c, sz.x, sz.y,
				last.get("studio_text", ""), st.position.y, lock.end.y, st.size.y, st.get_center().x - lock.get_center().x])
			ok(absf(lock.get_center().x - sz.x * 0.5) <= 2.0, "4 %s at %dx%d: the lock-up centred (off %.1f px)" % [c, sz.x, sz.y,
				lock.get_center().x - sz.x * 0.5])
			sv.queue_free()
			await idle(1)

	print("intro: %d fail(s)" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
