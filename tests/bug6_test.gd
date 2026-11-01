extends SceneTree
## godot --path . -s tests/bug6_test.gd     (BUG 6: animation-only UI never shows in 3D BUILDING; no empty buttons; the top rows do not overlap)
## Bars (real start-screen clicks):
##   1 LEAK   in building (fresh, and after ANIMATION -> back): no visible grip panel / hands row, no facing label / figure node
##   2 EMPTY  zero visible Buttons with no text and no icon in the whole tree (building, both modes, 3 sizes)
##   3 TOP    no two visible top-bar controls overlap and all are inside the window at 1280x720, 1600x900, 1920x1080
##   4 STAGE  the grip panel still shows on STAGE when a weapon is held
## Shots: C:/Temp/claude/bug6/
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/bug6"
const DIRT := "user://bug6_test"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var tag := "after"


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [SHOT, nm, tag])


func resize(s: Vector2i) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = s
	await idle(6)


func all_vis(n: Node, out: Array) -> void:
	if n is Window and n != root:
		return
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		out.append(n)
	for c in n.get_children():
		all_vis(c, out)


func vis_controls() -> Array:
	var out := []
	all_vis(m, out)
	return out.filter(func(c): return (c as Control).is_visible_in_tree())


func empty_buttons() -> Array:
	var bad := []
	for c in vis_controls():
		if c is Button and (c as Button).text.strip_edges() == "" and (c as Button).icon == null and not has_caption(c):
			var b := c as Button
			bad.append("%s %s %s par=%s tip=%s" % [b.name, b.get_class(), b.get_global_rect(), b.get_parent().name, b.tooltip_text.left(40)])
	return bad


## a big tile button draws its words in a child Label / its picture in a child TextureRect: that is a caption too
func has_caption(n: Node) -> bool:
	for c in n.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		if c is Label and (c as Label).text.strip_edges() != "":
			return true
		if c is TextureRect and (c as TextureRect).texture != null:
			return true
		if has_caption(c):
			return true
	return false


## dividers of a tool row: a visible divider next to another one, or first / last in its row, is a thin empty bar
func stray_dividers() -> Array:
	var bad := []
	var rows := {}
	for c in vis_controls():
		if c is VSeparator and c.get_parent() is HBoxContainer:
			rows[c.get_parent()] = true
	for row in rows:
		var prev_sep := true   # the row's start counts as a divider: a divider first in the row is stray
		var last: Control = null
		for c in row.get_children():
			if not (c as Control).visible:
				continue
			if c is VSeparator:
				if prev_sep:
					bad.append("%s %s (row %s)" % [c.name, (c as Control).get_global_rect(), row.name])
				prev_sep = true
			else:
				prev_sep = false
			last = c
		if last is VSeparator and not bad.has("%s %s (row %s)" % [last.name, last.get_global_rect(), row.name]):
			bad.append("%s %s last in row %s" % [last.name, last.get_global_rect(), row.name])
	return bad


func start(kind: String, easy: bool) -> void:
	var ss: StartScreen = m.start_screen
	ss.show_screen()
	await idle(3)
	var eb := ss.find_child(("easy_" if easy else "expert_") + kind, true, false)
	if eb != null:
		await click_ctl(eb)
	await click_ctl(ss._cards[kind])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)


## grip panel / hands row / facing label / figure pieces that show
func leaks() -> Array:
	var bad := []
	if m.man_root != null and m.man_root.is_visible_in_tree():
		bad.append("man_root")
	if m.ui_hands_panel != null and m.ui_hands_panel.is_visible_in_tree():
		bad.append("ui_hands_panel")
	for at in m.axis_tags:
		if (at as Node3D).is_visible_in_tree():
			bad.append("axis_tag " + String(at.name))
	for sm in m.stage_marks:
		if is_instance_valid(sm) and (sm as Node3D).is_visible_in_tree() and sm is Label3D:
			bad.append("stage_mark " + String(sm.name))
	for c in vis_controls():
		if c is Button and (c as Button).text in ["Both hands", "Free left hand", "Free right hand", "Weapon in hand", "Turn blade 90°", "Flip blade"]:
			bad.append("btn " + (c as Button).text)
		if c is Label and (c as Label).text.contains("holds the"):
			bad.append("lbl " + (c as Label).text.left(30))
	return bad


## the visible controls of the top bar (the strip, the tools row, Easy's bar): leaves only (a container is not a thing to overlap)
func top_leaves() -> Array:
	var out := []
	for c in vis_controls():
		var ctl := c as Control
		if ctl is Container or ctl is PanelContainer or ctl is ScrollContainer or ctl is Panel:
			continue
		if ctl is VSeparator or ctl is HSeparator:
			continue
		var r := ctl.get_global_rect()
		if r.position.y >= 120.0 or r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if not (ctl is Button or ctl is LineEdit or ctl is Label):
			continue
		out.append(ctl)
	return out


func top_problems(sz: Vector2i) -> Array:
	var bad := []
	var win := Rect2(Vector2.ZERO, Vector2(sz))
	var ls := top_leaves()
	for c in ls:
		var r := (c as Control).get_global_rect()
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > win.end.x + 0.5 or r.end.y > win.end.y + 0.5:
			bad.append("OFF %s %s %s" % [c.name, r, (c as Control).get_class()])
	for i in ls.size():
		for j in range(i + 1, ls.size()):
			var a := ls[i] as Control
			var b := ls[j] as Control
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ov := a.get_global_rect().intersection(b.get_global_rect())
			if ov.size.x > 1.0 and ov.size.y > 1.0:
				bad.append("OVERLAP %s %s  vs  %s %s" % [a.name, a.get_global_rect(), b.name, b.get_global_rect()])
	return bad


func house() -> void:
	if m.bld != null and m.bld.part != null and m.bld.part.on:
		m.bld.part.set_on(false)
	await idle(6)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	m.start_screen.dirs_override = [DIRT]
	for mode in ["easy", "easy_part", "expert", "after_anim"]:
		if mode == "after_anim":
			await start("animation", true)
			m.B.wep_on = true   # the fighter holds the metal bat in the right hand (as a fighter scene does), a hand picked
			m.B.wep_hand = "hand_r"
			m.sel = "hand_r"
			m._refresh()
			await idle(4)
			ok(m.ui_hands_panel.visible, "0 control: on ANIMATION the grip panel shows with the bat held")
		await start("building", mode.begins_with("easy"))
		if mode != "easy_part":
			await house()
		for sz in SIZES:
			await resize(sz)
			m._fit_top()
			await idle(4)
			var lk := leaks()
			if not lk.is_empty():
				print("     diag easy.on %s kind %s page %s hides_figure %s" % [m.easy.on, m.S.kind, m.cur_page, m._hides("figure")])
			ok(lk.is_empty(), "1 %s %s: no grip panel / facing label / figure %s" % [mode, sz, lk])
			var eb := empty_buttons()
			ok(eb.is_empty(), "2 %s %s: no visible Button without text and icon %s" % [mode, sz, eb])
			var nh := 0
			for hb in m.find_children("home_btn", "Button", true, false):
				if (hb as Button).is_visible_in_tree():
					nh += 1
			ok(nh == 1, "2 %s %s: exactly one visible Home button (%d)" % [mode, sz, nh])
			var sd := stray_dividers()
			ok(sd.is_empty(), "2 %s %s: no stray divider bars (doubled, first or last in a row) %s" % [mode, sz, sd])
			var tp := top_problems(sz)
			ok(tp.is_empty(), "3 %s %s: top bar controls inside the window, none overlapping %s" % [mode, sz, tp])
			var nsep := 0
			for c in vis_controls():
				if c is VSeparator and (c as Control).get_global_rect().position.y < 120.0:
					nsep += 1
			print("     %s %s: %d top controls, %d separators, page %s" % [mode, sz, top_leaves().size(), nsep, m.cur_page])
			if sz == SIZES[1]:
				await shot(mode)
	# STAGE: the grip panel still shows with the bat held
	await start("animation", false)
	m.B.wep_on = true
	m.B.wep_hand = "hand_r"
	m._refresh()
	await idle(4)
	ok(m.ui_hands_panel.visible and m.ui_hands_panel.is_visible_in_tree(), "4 ANIMATION with the bat in hand: the grip panel shows (page %s)" % m.cur_page)
	m._page_set("STAGE")
	await idle(6)
	ok(m.cur_page == "STAGE" and m.ui_hands_panel.is_visible_in_tree(), "4 STAGE with the bat in hand: the grip panel still shows (page %s, panel %s)" % [m.cur_page, m.ui_hands_panel.is_visible_in_tree()])
	await shot("stage")
	print("bug6: %d fail" % fails)
	quit()
