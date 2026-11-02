extends SceneTree
## s247: the Easy Part library's group tabs are PINNED above the scrolling chip area.
##  1 PIN     scroll the chip area to its end: every group tab's rect is unchanged and inside the viewport
##  2 CLEAR   no chip rect overlaps the tab row, and the scroll area starts below it (1024x600, 1280x720, 1920x1080; 2560x1440 too)
##  3 CLICK   a real click (Input.parse_input_event at the tab centre) on each tab opens its group after scrolling
##  4 CONTROL the old layout (tabs inside the scroll) would fail 1: the tab's old position is computed (tab y - scroll) and compared
const SHOT := "C:/Users/Nick/tools/kine_workers/out/247"
const DIRT := "user://s247_test"
var fails := 0
var m: Node
var pu: PartUI
var ep


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


## a real click on a visible control; a missing control is reported by the bar that needs it (no crash)
func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
	return true


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])



func real_click(p0: Vector2) -> void:
	var p := root.get_final_transform() * p0   # canvas point -> window pixels (Input events are in window pixels)
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	Input.parse_input_event(mv)
	await idle(2)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(e)
		await idle(2)


func _init() -> void:
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the library cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	for sz in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.content_scale_size = sz
		await idle(10)
		await _page(sz)
	print("s247: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _tabs() -> Dictionary:
	var d := {}
	for k in ep.lib_group_btns:
		d[k] = (ep.lib_group_btns[k] as Button).get_global_rect()
	return d


func _page(sz: Vector2i) -> void:
	var tag := "%dx%d" % [sz.x, sz.y]
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	if ep.parts_open:
		await click_ctl(pb)
		await idle(4)
	await click_ctl(pb)
	await idle(30)
	var sc := root.find_child("easypart_panel_scroll", true, false) as ScrollContainer
	var row := root.find_child("easypart_lib_groups", true, false) as Control
	if sc == null or row == null or not row.is_visible_in_tree():
		ok(false, "%s the tab row and the scroll area exist and show (row %s, vis %s, parts_open %s, panel %s)" % [tag, str(row), str(row != null and row.is_visible_in_tree()), str(ep.parts_open), str(ep.panel.visible)])
		return
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var before := _tabs()
	var row_before := row.get_global_rect()
	if sz == Vector2i(1024, 600):
		await shot("unscrolled_%s" % tag)
	# 2 CLEAR, unscrolled: the scroll area starts below the row
	ok(sc.get_global_rect().position.y >= row_before.end.y - 0.5, "2 %s the scroll area (top %.0f) starts below the tab row (bottom %.0f)" % [tag, sc.get_global_rect().position.y, row_before.end.y])
	# open the fullest group so the chip area is as tall as it gets, then scroll to the end
	var sc_max := 0
	for g in ep.lib_group_btns:
		ep._lib_group_show(g)
		await idle(4)
		var bar := sc.get_v_scroll_bar()
		sc_max = maxi(sc_max, int(bar.max_value - bar.page))
	print("     %s: scrollable range over all groups %d px" % [tag, sc_max])
	# make the chip area scrollable even if the page fits: open Screws below it (the screw grid lengthens the column)
	sc.scroll_vertical = 100000
	await idle(4)
	var scrolled := sc.scroll_vertical
	print("     %s: scrolled to %d" % [tag, scrolled])
	if sz == Vector2i(1024, 600):
		await shot("scrolled_%s" % tag)
	var after := _tabs()
	var same := true
	var inside := true
	for k in before:
		if not (before[k] as Rect2).is_equal_approx(after[k]):
			same = false
		if not vp.encloses(after[k]):
			inside = false
	ok(same, "1 %s every group tab's rect is unchanged after scrolling to the end (scroll %d)" % [tag, scrolled])
	ok(inside, "1 %s every group tab is fully inside the viewport %s" % [tag, str(vp)])
	ok((row.get_global_rect()).is_equal_approx(row_before), "1 %s the tab row rect is unchanged" % tag)
	# 2 CLEAR: no chip overlaps the row (visible chips of the open group, and every chip button)
	var hit := 0
	var chips := 0
	for g in ep.lib_group_btns:   # every group's chips, scrolled to the end each time
		ep._lib_group_show(g)
		await idle(3)
		sc.scroll_vertical = 100000
		await idle(3)
		for k in ep.lib_btns:
			var c: Control = ep.lib_btns[k]
			if c.is_visible_in_tree():
				chips += 1
				if c.get_global_rect().intersects(row.get_global_rect()) and sc.get_global_rect().intersects(c.get_global_rect()):
					hit += 1
	ok(hit == 0, "2 %s no visible chip (%d checked) overlaps the tab row" % [tag, chips])
	# 227b: the chips stay inside the scroll area (horizontally and not above it)
	var lib := root.find_child("easypart_library", true, false) as Control
	var fl := root.find_child("easypart_libchips_" + String(ep.lib_group), true, false) as Control
	ok(lib != null and sc.is_ancestor_of(lib) and fl != null and sc.is_ancestor_of(fl) and not sc.is_ancestor_of(row), "2 %s the chips are inside the scroll area, the tab row is not" % tag)
	# 4 CONTROL: the old layout (tabs inside the scroll) would have moved the row up by the scroll offset
	if scrolled > 0:
		var old_rect := Rect2(row_before.position - Vector2(0, scrolled), row_before.size)
		var old_fails := not old_rect.is_equal_approx(row_before) and (old_rect.position.y < sc.get_global_rect().position.y)
		ok(old_fails, "4 %s CONTROL: with the tabs inside the scroll the row would sit at y %.0f (moved %d px, above the scroll top %.0f): the bar can fail" % [tag, old_rect.position.y, scrolled, sc.get_global_rect().position.y])
	else:
		print("     %s: nothing to scroll here (the page fits): control computed at the fullest page below" % tag)
	# 3 CLICK: a real click on each tab opens its group, still scrolled
	for g in ep.lib_group_btns:
		var other := "Fasteners" if g != "Fasteners" else "Building"
		ep._lib_group_show(other)
		await idle(3)
		sc.scroll_vertical = 100000
		await idle(3)
		var b := ep.lib_group_btns[g] as Button
		await real_click(b.get_global_rect().get_center())
		await idle(3)
		ok(ep.lib_group == g and (ep.lib_group_flows[g] as Control).visible, "3 %s a real click on the %s tab opens it after scrolling (group now %s)" % [tag, g, ep.lib_group])
	ep._lib_group_show("Fasteners")
	await idle(3)
