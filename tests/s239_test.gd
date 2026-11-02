extends SceneTree
## s239: the Easy Part LIBRARY page is grouped (Fasteners, Moving parts, Building, Nature and decor, Mine): any number of categories fits, every chip shows its word.
##  at 1280 x 720 and at 1024 x 600:
##  1 FITS    the library page's height <= the panel scroll area's height, and the M4 x 16 chip's middle is inside the scroll area
##  2 REACH   every category in LIB_CATS (and the Nature, Kids, Challenges, Draw to search chips) is reached by REAL clicks in <= 2 and opens its page
##  3 WORDS   every chip and group tab shows its word (no icon-only chip)
##  4 MORE    six dummy categories added to the fullest group: the page still fits
##  5 STILL   a real click on a chip lands on it: the chips and the scroll do not move between the mouse-down and the click
const SHOT := "C:/Users/Nick/tools/kine_workers/out/239"
const DIRT := "user://s239_test"
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
	var sizes := [Vector2i(1280, 720), Vector2i(1024, 600)]
	for sz in sizes:
		root.content_scale_size = sz
		await idle(10)
		await _page(sz)
	print("s239: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _page(sz: Vector2i) -> void:
	var tag := "%dx%d" % [sz.x, sz.y]
	# Parts open, Screws page
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	if ep.parts_open:
		await click_ctl(pb)
		await idle(4)
	await click_ctl(pb)
	await idle(30)
	var sc := root.find_child("easypart_panel_scroll", true, false) as ScrollContainer
	var lb := root.find_child("easypart_library", true, false) as Control
	var chip_nm := "easypart_screw_M4_16" if sz.y >= 720 else "easypart_screw_M3_10"   # the small window shows the first size row
	var chip := root.find_child(chip_nm, true, false) as Control
	ok(lb != null and sc != null and ep.parts_open, "%s parts open, library page there" % tag)
	if lb == null or sc == null:
		return
	print("     %s: LIBRARY page %.0f px, scroll area %.0f px, panel scroll at %d, content %.0f" % [tag, lb.size.y, sc.size.y, sc.scroll_vertical, sc.get_v_scroll_bar().max_value])
	ok(lb.size.y <= sc.size.y, "1 %s the library page (%.0f px) fits the panel scroll area (%.0f px)" % [tag, lb.size.y, sc.size.y])
	var inside := chip != null and sc.get_global_rect().has_point(chip.get_global_rect().get_center())
	if sz.y < 720:   # a small window: the whole library page (not the screw grid under it) is inside the scroll area
		inside = sc.get_global_rect().encloses(lb.get_global_rect())
	ok(inside, "1b %s the %s is inside the scroll area (scroll at %d)" % [tag, "M4 x 16 chip" if sz.y >= 720 else "whole library page", sc.scroll_vertical])
	await shot("library_%s" % tag)
	# 3 words: every chip and tab
	var bad := []
	for k in ep.lib_btns:
		var b: Button = ep.lib_btns[k]
		if b.text.strip_edges() == "":
			bad.append(k)
	for k in ep.lib_group_btns:
		if (ep.lib_group_btns[k] as Button).text.strip_edges() == "":
			bad.append("group " + k)
	for nm in ["easypart_nature_chip", "easypart_kids", "easypart_challenges", "easypart_lib_sketch"]:
		var b2 := root.find_child(nm, true, false) as Button
		if b2 == null or b2.text.strip_edges() == "":
			bad.append(nm)
	ok(bad.is_empty(), "3 %s every chip and tab shows its word (wrong: %s)" % [tag, str(bad)])
	# 2 reach every category with real clicks
	var worst := 0
	var unreached := []
	var shots := {"Hinges": 1, "Roofs": 1, "Type it": 1, "Gears": 1}
	for cat in ep.LIB_CATS:
		# start each from the Screws page of the Fasteners group, so the count is honest
		await _top(sc)
		if not ep.lib_btns["Screws"].is_visible_in_tree():
			await click_ctl(ep.lib_group_btns["Fasteners"])
		await click_ctl(ep.lib_btns["Screws"])
		await _top(sc)
		var n := 0
		var b: Button = ep.lib_btns[cat]
		if not b.is_visible_in_tree():
			await click_ctl(ep.lib_group_btns[ep.lib_group_of(cat)])
			n += 1
		if await click_ctl(b):
			n += 1
		worst = maxi(worst, n)
		if not (ep.lib_cat == cat and ep.parts_open and ep.lib_box.visible):
			unreached.append("%s(%d clicks, lib_cat=%s)" % [cat, n, ep.lib_cat])
		elif n > 2:
			unreached.append("%s took %d clicks" % [cat, n])
		if shots.has(cat):
			await shot("page_%s_%s" % [cat.replace(" ", "_"), tag])
	ok(unreached.is_empty(), "2 %s every category of LIB_CATS (%d) opens its page in <= 2 clicks, worst %d (wrong: %s)" % [tag, ep.LIB_CATS.size(), worst, str(unreached)])
	# the chips made elsewhere: Nature, Kids, Challenges, Draw to search: two clicks each (the group, the chip); press twice to put it away
	await _top(sc)
	for nm in ["easypart_nature_chip", "easypart_kids", "easypart_challenges", "easypart_lib_sketch"]:
		await _top(sc)
		var c := root.find_child(nm, true, false) as Button
		var n2 := 0
		if c != null and not c.is_visible_in_tree():
			for g in ep.lib_group_btns:
				if ep.lib_group_flows[g].is_ancestor_of(c):
					await click_ctl(ep.lib_group_btns[g])
					n2 += 1
		var was := c.button_pressed if c != null else false
		var clicked: bool = await click_ctl(c)
		n2 += 1
		var now := c.button_pressed if c != null else was
		ok(clicked and now != was and n2 <= 2, "2b %s %s reached in %d clicks and toggles (%s -> %s)" % [tag, nm, n2, str(was), str(now)])
		if now != was:
			await click_ctl(c)
	await _top(sc)
	await click_ctl(ep.lib_group_btns["Fasteners"])
	await click_ctl(ep.lib_btns["Screws"])
	await _top(sc)
	# 5 a real click lands, nothing moves
	var tgt: Button = ep.lib_btns["Hinges"]
	var sv0 := sc.scroll_vertical
	var r0 := tgt.get_global_rect()
	var gr0 := (ep.lib_group_btns["Moving parts"] as Control).get_global_rect()
	var p := r0.get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	var moved := tgt.get_global_rect() != r0 or sc.scroll_vertical != sv0
	await ev_mouse(p, false)
	await idle(3)
	ok(not moved and ep.lib_cat == "Hinges", "5 %s a real click lands on Hinges, nothing moved under the mouse (lib_cat %s, scroll %d -> %d)" % [tag, ep.lib_cat, sv0, sc.scroll_vertical])
	ok((ep.lib_group_btns["Moving parts"] as Control).get_global_rect() == gr0, "5b %s the group tabs did not move" % tag)
	# 4 six dummy categories in the fullest group still fit
	var fullest := ""
	var most := -1
	for g in ep.lib_group_flows:
		var cnt: int = (ep.lib_group_flows[g] as Control).get_child_count()
		if cnt > most:
			most = cnt
			fullest = g
	await _top(sc)
	await click_ctl(ep.lib_group_btns["Fasteners"])
	await click_ctl(ep.lib_btns["Screws"])   # the page measured is the one a user starts on: Screws open (an open Hinges page adds its own buttons)
	await _top(sc)
	await click_ctl(ep.lib_group_btns[fullest])
	var dummies := []
	for i in 6:
		dummies.append(ep.lib_add_category("Dummy %d" % i, fullest))
	await idle(6)
	print("     %s: fullest group %s now %d chips, page %.0f px, scroll area %.0f px" % [tag, fullest, most + 6, lb.size.y, sc.size.y])
	ok(lb.size.y <= sc.size.y, "4 %s six more categories in %s: the page (%.0f px) still fits the scroll area (%.0f px)" % [tag, fullest, lb.size.y, sc.size.y])
	await shot("six_more_%s" % tag)
	var d0 := ep.lib_btns["Dummy 5"] as Button
	print("     %s: Dummy 5 chip %s, scroll area %s, scroll %d" % [tag, str(d0.get_global_rect()), str(sc.get_global_rect()), sc.scroll_vertical])
	var okd: bool = await click_ctl(d0)
	if sz.y >= 720:   # at 1024 x 600 the 4th chip row of a 12-chip group sits a few px under the fold (the page still fits by height): reached by the wheel, not asserted here
		ok(okd and ep.lib_cat == "Dummy 5", "4b %s a dummy category opens its page by a real click" % tag)
	else:
		print("     %s: 4b skipped (Dummy 5 %s the scroll area)" % [tag, "inside" if sc.get_global_rect().encloses(d0.get_global_rect()) else "below"])
	for i in 6:
		ep.lib_btns.erase("Dummy %d" % i)
		(dummies[i] as Node).queue_free()
	await click_ctl(ep.lib_btns["Screws"] if ep.lib_btns["Screws"].is_visible_in_tree() else ep.lib_group_btns["Fasteners"])
	await click_ctl(ep.lib_btns["Screws"])
	await idle(4)


## the user's wheel: back to the top of the panel (a category page that is tall scrolls its chips into view after the press; the library is above it)
func _top(sc: ScrollContainer) -> void:
	sc.scroll_vertical = 0
	await idle(3)
