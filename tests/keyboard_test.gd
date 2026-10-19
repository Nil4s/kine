## godot --path . -s tests/keyboard_test.gd     (GATES U4, item 83; needs a window)
## KEYBOARD ONLY, by real key presses (pushed into the window as a keyboard sends them):
##   before F6 the keys are the view's (Tab = big view; no control can take focus)
##   F6: the first control has focus; Tab walks every panel in reading order and comes back round (no trap: focus is
##   never lost, never stuck); Shift+Tab steps back; Enter and Space press what has focus; a press that rebuilds its
##   row keeps the focus on the same control; Esc gives the keys back (Space plays again)
##   the focus ring: its pixels measured on the screen against the panel behind it: contrast >= 3:1 (WCAG 1.4.11)
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


func key(k: Key, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame


func owner_path() -> String:
	var f := root.gui_get_focus_owner()
	return "" if f == null else String(m.get_path_to(f)) if m.is_ancestor_of(f) else "(outside) " + String(f.name)


func short(p: String) -> String:   # the address the way an agent writes it: the named parts only
	return "/".join(Array(p.split("/")).filter(func(x): return not x.begins_with("@")))


## WCAG relative luminance and contrast
func lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func contrast(a: Color, b: Color) -> float:
	var x := lum(a)
	var y := lum(b)
	return (maxf(x, y) + 0.05) / (minf(x, y) + 0.05)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")   # read only; then the row, as the Open button does
	m._rebuild_cards()
	m._check()   # the CHECK panel open: its rows are on the walk too
	await m.dummy_settle()
	await idle()

	# before F6: the view's keys
	var bv0: bool = m.big_view
	await key(KEY_TAB)
	ok(m.big_view != bv0 and root.gui_get_focus_owner() == null, "before F6: Tab is big view (%s -> %s), no control took focus" % [bv0, m.big_view])
	await key(KEY_TAB)
	await idle()

	# F6: in. The POSE tab is a page-bar button since round 6 (the pages moved from the top strip to the bar along the bottom): F6 still lands on it
	await key(KEY_F6)
	ok(m.kb_nav and short(owner_path()) == "page_bar/tab_pose", "F6: keyboard mode, the first control has focus (%s)" % short(owner_path()))

	# Tab round the whole window
	var seen := [short(owner_path())]
	var lost := 0
	var stuck := 0
	var back_at := -1
	for i in 400:
		var before := owner_path()
		await key(KEY_TAB)
		var now := owner_path()
		if now == "":
			lost += 1
		elif now == before:
			stuck += 1
		if short(now) == seen[0] and i > 0:
			back_at = i + 1
			break
		seen.append(short(now))
	print("     the walk (%d stops): %s ... %s" % [seen.size(), ", ".join(seen.slice(0, 14)), ", ".join(seen.slice(-8))])
	var wf := FileAccess.open(OS.get_environment("TMP") + "/kb_walk.txt", FileAccess.WRITE)
	wf.store_string("
".join(seen))
	wf.close()
	ok(lost == 0 and stuck == 0, "Tab never loses focus (%d) and never sticks (%d)" % [lost, stuck])
	ok(back_at > 0, "Tab comes back round to the first control after %d presses: no trap" % back_at)
	var reach := {"top bar": seen.any(func(x): return x.begins_with("tab_") or x.begins_with("ribbon_") or x in ["b_undo", "b_search"]),
		"left panel": seen.any(func(x): return x.contains("b_save_pose") or x.contains("edit_name")),
		"right panel": seen.any(func(x): return x.contains("slider_bend")),
		"scene row": seen.any(func(x): return x.begins_with("card_") or x.contains("play_row")),
		"CHECK panel": seen.any(func(x): return x.begins_with("check_panel"))}
	ok(reach.values().all(func(v): return v), "the walk reaches every panel: %s" % reach)
	var ci: int = seen.find(seen.filter(func(x): return x.begins_with("card_"))[0]) if seen.any(func(x): return x.begins_with("card_")) else -1
	var ki: int = seen.find(seen.filter(func(x): return x.begins_with("check_panel"))[0]) if seen.any(func(x): return x.begins_with("check_panel")) else -1
	var li: int = seen.find(seen.filter(func(x): return x.contains("b_save_pose"))[0]) if reach["left panel"] else -1
	ok(0 < li and li < ci and ci < ki, "  in reading order: top bar, then the left panel (%d), the scene row (%d), CHECK (%d)" % [li, ci, ki])

	# Shift+Tab steps back
	await key(KEY_TAB)
	await key(KEY_TAB)
	var two := short(owner_path())
	await key(KEY_TAB, true)
	ok(short(owner_path()) == seen[1], "Shift+Tab steps back (%s -> %s)" % [two, short(owner_path())])

	# Enter / Space press what has focus: walk to b_trail by Tab, Enter; to card_2/b_pick, Space
	var target := func(want: String) -> bool:
		for i in 400:
			if short(owner_path()).ends_with(want):
				return true
			await key(KEY_TAB)
		return false
	var got: bool = await target.call("tab_animate")
	await key(KEY_ENTER)   # the ANIMATE tab, by keyboard: its tools show (the trail is one)
	await idle()
	got = got and await target.call("b_trail")
	var tr0: bool = m.ov.trail_on
	await key(KEY_ENTER)
	ok(got and m.ov.trail_on != tr0, "Tab to b_trail, Enter: the trail turned %s" % ("on" if m.ov.trail_on else "off"))
	got = await target.call("card_2/b_pick")
	await key(KEY_SPACE)
	await idle()
	ok(got and m.sel_card == 1, "Tab to card_2/b_pick, Space: card 2 picked (sel %d)" % (m.sel_card + 1))
	ok(short(owner_path()) == "card_2/b_pick", "  the row was rebuilt, the focus is back on card_2/b_pick (%s)" % short(owner_path()))

	# the ring, measured on the screen, dark and light: focus on b_trail (pressed: the trail is on, its fill is the accent)
	got = await target.call("b_trail")
	for light in [false, true]:
		m._set_light(light)
		await idle()
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var f: Control = root.gui_get_focus_owner()
		if not got or f == null:   # nothing to measure: say so and stop (a test that hangs reports nothing)
			ok(false, "the ring: no control has focus to measure (the walk to b_trail found it: %s)" % got)
			print("KEYBOARD: %d failed" % fails)
			quit(1)
			return
		var r := f.get_global_rect()
		var x0 := int(r.position.x)
		var x1 := int(r.end.x)   # the right edge (the left one has the ribbon's separator 6 px out)
		var y := int(r.get_center().y)
		var gap := img.get_pixel(x1, y)          # expand margin 4, border 2: px 0-1 out are the gap (the bar)
		var ring := img.get_pixel(x1 + 2, y)     # px 2-3 out: the ring
		var behind := img.get_pixel(x1 + 5, y)   # px 4-5 out: the bar again (the next button starts 6 out)
		var fill := img.get_pixel(x1 - 5, y)     # the button's own fill
		print("     %s: ring %s, gap %s, behind %s, the button %s" % ["light" if light else "dark", ring.to_html(false), gap.to_html(false), behind.to_html(false), fill.to_html(false)])
		ok(contrast(ring, behind) >= 3.0 and contrast(ring, gap) >= 3.0, "%s: the ring reads against the bar on both sides: %.1f:1 outside, %.1f:1 in the gap (WCAG 1.4.11 asks 3:1)" % ["light" if light else "dark", contrast(ring, behind), contrast(ring, gap)])
		ok(contrast(gap, behind) < 1.2 and contrast(gap, fill) > 1.1, "  the gap is the bar's colour (%.2f:1), not the button's: the ring never sits on the fill" % contrast(gap, behind))
		var crop := img.get_region(Rect2i(x0 - 40, int(r.position.y) - 24, int(r.size.x) + 80, int(r.size.y) + 48))
		crop.save_png(OS.get_environment("TMP") + "/focus_ring_%s.png" % ("light" if light else "dark"))
	m._set_light(false)
	await idle()

	# Esc: the keys go back to the view
	await key(KEY_ESCAPE)
	ok(not m.kb_nav and root.gui_get_focus_owner() == null, "Esc: keyboard mode off, nothing has focus")
	var tb: Control = m.find_child("b_trail", true, false)
	ok(tb.focus_mode == Control.FOCUS_NONE, "  the controls are back to not taking focus (a click won't eat Space)")
	var pl: bool = m.playing
	await key(KEY_SPACE)
	ok(m.playing != pl, "  Space plays again (%s -> %s)" % [pl, m.playing])
	print("KEYBOARD: %d failed" % fails)
	quit(1 if fails > 0 else 0)
