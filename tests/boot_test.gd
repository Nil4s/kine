## godot --path . -s tests/boot_test.gd     (the start-up bench: needs a window; the child launches are windowed off-screen)
## THE BOOT BAR. BARS (written before the speed-up; the baseline is measured by this test on the code before it):
##  1 a fresh start's FIRST USABLE FRAME (the body built and the Easy home panel on screen; main's _boot_watch, timed by
##    BootProfile): the median of 3 child launches (--easy --boot-profile --boot-quit, windowed at --position 3000,3000) is
##    at least 30 % under the baseline BASE_MS below (0.7 x BASE_MS or less)
##  2 Easy home visible on a fresh start: EasyMode.start_fresh (no settings file = Easy), the scene empty, the picture panel
##    on screen and the body built, after the frames the app takes to settle
##  3 every Expert page opens and shows its controls on the first switch from Easy (the pages suite's way: the page's
##    button, a real click): its ribbon row is the only one shown, its button is the only one lit, a control is visible
## BASE_MS: the median first-usable time of this test's own launches on the pre-change code (measured 10-23, poser-ui-rounds
## code plus the profile marks only; see the commit message for the numbers).
extends SceneTree

const BASE_MS := 11343.0   # measured by this test on the pre-change code (10-23): launches 11283, 11381, 11343 ms, median 11343
const RUNS := 3

var m: Node
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
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
	await idle()


## bar 1: the child launches. Each is the real app (a window, off-screen), fresh to the profile's eye, and reports the
## frame its body and Easy home panel are on screen
func launches() -> Array:
	var times := []
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	for i in RUNS:
		var out := []
		OS.execute(exe, ["--path", proj, "--position", "3000,3000", "--", "--easy", "--boot-profile", "--boot-quit"], out, true)
		var t := -1.0
		for line in "\n".join(out).split("\n"):
			if line.begins_with("BOOT usable_at_ms "):
				t = float(line.get_slice(" ", 2))
		print("launch %d: first usable at %d ms" % [i + 1, t])
		times.append(t)
	times.sort()
	return times


func _init() -> void:
	var times := launches()
	var med: float = times[RUNS / 2]
	ok(med > 0.0 and med <= 0.7 * BASE_MS, "1 first usable frame: median %d ms over %d launches (baseline %d ms; the bar is 30 %% under it: %d ms)" % [med, RUNS, BASE_MS, 0.7 * BASE_MS])

	# bars 2 and 3 in this process: a fresh install (no settings file) opens in Easy
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	var n := 0
	while n < 600 and not (m.easy != null and m.easy.on and m.easy.home != null and m.easy.home.panel.is_visible_in_tree() and m.skel != null):
		await process_frame
		n += 1
	await idle(3)
	var home_on: bool = m.easy != null and m.easy.on and m.easy.home != null and m.easy.home.panel.is_visible_in_tree()
	ok(home_on and m.skel != null and not m.pieces.is_empty(), "2 Easy home on a fresh start: the panel is on screen and the body is built (after %d frames)" % n)

	# 3 the Expert pages, from Easy, by their buttons
	m.easy.set_on(false)
	await idle()
	for p in m.PAGES:
		await click(m.ui_page_btns[p])
		var rows: Array = m.RIBBON.filter(func(k): return m.ui_ribbon[k].visible)
		var lit: Array = m.PAGES.filter(func(k): return m.ui_page_btns[k].button_pressed)
		var shown := false
		for b in m.ui_ribbon[m.PAGE_ROW[p]].find_children("*", "Button", true, false):
			if b.is_visible_in_tree():
				shown = true
				break
		ok(rows == [m.PAGE_ROW[p]] and lit == [p] and shown, "3 %s opens: row %s, lit %s, a control shown: %s" % [p, rows, lit, shown])

	print("boot_test: %d failed" % fails)
	quit(fails)
