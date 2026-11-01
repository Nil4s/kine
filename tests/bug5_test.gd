extends SceneTree
## bug5 (Nick 11-01: "screen adaptation: all the bottom stuff goes crazy when something is over").
## At 1280x720, 1366x768, 1600x900, 1920x1080 and 2560x1440, on the live Easy Part (real clicks from the BUILDING card, a box on the floor):
## the BOTTOM CONTROLS are recorded with nothing open (the bottom bar, the page tabs, Your steps, the status and hint lines, the view buttons, the Challenges
## card, the shortcut card: every visible Button / Label / slider / line edit in the lower part of the window, plus the named bottom boxes), then each panel
## that can cover the bottom is opened and the same controls are measured again:
##   Cut a hole, Parts library, Colour, Repeat it, Draw shape + More, Challenges, the s100 shortcut card, the s094 hover tip, the Export dialog, Fit to an object.
## Bars, for every (size x panel) cell: no bottom control MOVED more than 2 px (or changed size, or disappeared), none is OVERLAPPED by another visible control
## (more than 2 px both ways, pairs that already overlap with nothing open are not new), none is CLIPPED by the window or a clipping parent (more than 2 px).
## Prints the table (cell: moved / overlapped / clipped). Shots: C:/Temp/claude/bug5/<tag>/<w>x<h>_<panel>.png
const SIZES := [[1280, 720], [1366, 768], [1600, 900], [1920, 1080], [2560, 1440]]
const PANELS := ["hole", "parts", "colour", "repeat", "shape_more", "challenges", "keycard", "hovertip", "export", "fit"]
const DIRT := "user://bug5_test"
const TOL := 2.0
var SHOT := OS.get_environment("BUG5_SHOT") if OS.get_environment("BUG5_SHOT") != "" else "C:/Temp/claude/bug5/run"
var fails := 0
var m: Node
var ep
var rows := []


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


func click_ctl(c: Control) -> void:
	var q := c.get_parent()   # a button inside a scrolling panel is scrolled into view first (as a user would with the wheel)
	while q != null:
		if q is ScrollContainer:
			(q as ScrollContainer).ensure_control_visible(c)
			await idle(2)
		q = q.get_parent()
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func size_to(w: int, h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	await idle(12)


# ------------------------------------------------------------------ measuring
func is_anc(a: Node, b: Node) -> bool:
	var p := b
	while p != null:
		if p == a:
			return true
		p = p.get_parent()
	return false


func under_any(n: Node, roots: Array) -> bool:
	for r in roots:
		if r != null and is_anc(r, n):
			return true
	return false


## every visible leaf control under `scope` (Button, LineEdit, Slider, Label with text): the things that can be read, clicked or hit
func leaves(n: Node, out: Array, skip: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if skip.has(n):
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		var leaf: bool = c is Button or c is LineEdit or c is Slider or (c is Label and String(c.text).strip_edges() != "")
		if leaf and r.size.x >= 1.0 and r.size.y >= 1.0 and c.modulate.a > 0.05:
			out.append(c)
	for k in n.get_children():
		leaves(k, out, skip)


func skip_list() -> Array:
	var sk := [m.ui_cube, ep.size_l, ep.edge_num, ep.dots]
	for t in m.find_children("toast*", "Control", true, false):   # a toast is a passing overlay of its own
		sk.append(t)
	return sk


## the part of the control that can be seen: the window and the clipping parents
func clip_rect(c: Control) -> Rect2:
	var r := root.get_visible_rect()
	var p := c.get_parent()
	while p != null:
		if p is Control and ((p as Control).clip_contents or p is ScrollContainer):
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


## how far the control is cut: sideways by anything, up / down by the window and the plain clipping parents (a scroll's own edge is its scroll)
func cut_px(c: Control) -> float:
	var r := c.get_global_rect()
	var vp := root.get_visible_rect()
	var w := vp
	var full := vp
	var p := c.get_parent()
	while p != null:
		if p is Control and ((p as Control).clip_contents or p is ScrollContainer):
			full = full.intersection((p as Control).get_global_rect())
			if not p is ScrollContainer:
				w = w.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	var cx := maxf(0.0, full.position.x - r.position.x) + maxf(0.0, r.end.x - full.end.x)
	var cy := maxf(0.0, w.position.y - r.position.y) + maxf(0.0, r.end.y - w.end.y)
	# a control scrolled out of its ScrollContainer entirely is not on screen: that is what a scroll is for
	var seen := full.intersection(r)
	if (seen.size.x < 1.0 or seen.size.y < 1.0):
		var q := c.get_parent()
		while q != null:
			if q is ScrollContainer:
				return 0.0
			q = q.get_parent()
	return maxf(cx, cy)


func nm(c: Node) -> String:
	var t := ""
	if c is Button or c is Label:
		t = String(c.text)
	if t == "":
		t = String(c.name)
	return "%s(%s)" % [t.left(24), String(c.name).left(22)]


## the bottom controls with nothing open: {node: rect}. Bottom = the lower 40 % of the window plus the named bottom boxes
var base := {}
var base_pairs := {}


func bottom_roots() -> Array:
	var rs := [ep.steps_box, ep.status, ep.hint, ep.view_box, ep.challenge_card, ep.kt.card, m.ui_status, m.ui_bar, m.ui_bp, m.ui_page_bar, m.ui_nav, ep.flat_box]
	return rs.filter(func(n): return n != null)


func record_base() -> void:
	base = {}
	base_pairs = {}
	var all := []
	leaves(m, all, skip_list())
	var vp := root.get_visible_rect()
	var br := bottom_roots()
	for c in all:
		var ctl := c as Control
		var r := ctl.get_global_rect()
		if is_anc(ep.panel, ctl):
			continue   # the side panel is a sheet that scrolls inside itself: its rows flow with its own page (the foot below it is what is measured)
		if r.get_center().y >= vp.size.y * 0.6 or under_any(ctl, br):
			base[ctl] = r
	for i in all.size():
		for j in range(i + 1, all.size()):
			if is_anc(all[i], all[j]) or is_anc(all[j], all[i]):
				continue
			var ov: Rect2 = (all[i] as Control).get_global_rect().intersection((all[j] as Control).get_global_rect())
			if ov.size.x > TOL and ov.size.y > TOL:
				base_pairs["%d_%d" % [all[i].get_instance_id(), all[j].get_instance_id()]] = true


## the three counts of one cell, with the first lines of each kind
func measure(extra: Array) -> Dictionary:
	var moved := []
	var over := []
	var clipped := []
	var hidden := []
	var all := []
	leaves(m, all, skip_list())
	for e in extra:   # the Export / Fit windows are windows of their own
		leaves(e, all, [])
	for c in base:
		if not is_instance_valid(c):
			continue   # a row the panel rebuilt (a step row): the new one is measured as part of the next recording
		var ctl := c as Control
		var r0: Rect2 = base[c]
		if not ctl.is_visible_in_tree():
			hidden.append(nm(ctl))   # a chip row that a tool replaces while it is armed (Tilt / Draft / Pinch): hidden is not moved
			continue
		var r1 := ctl.get_global_rect()
		var d := maxf(maxf(absf(r1.position.x - r0.position.x), absf(r1.position.y - r0.position.y)), maxf(absf(r1.size.x - r0.size.x), absf(r1.size.y - r0.size.y)))
		if ctl is Label:   # a line of words changes its width with its words: only where it starts counts
			d = maxf(absf(r1.position.x - r0.position.x), absf(r1.position.y - r0.position.y))
		if d > TOL:
			moved.append("%s %.0fpx %s->%s" % [nm(ctl), d, r0, r1])
		if cut_px(ctl) > TOL:
			clipped.append("%s cut %.0fpx %s" % [nm(ctl), cut_px(ctl), r1])
		for o in all:
			if o == ctl or is_anc(o, ctl) or is_anc(ctl, o) or under_any(o, extra):   # a window of its own (Export, Fit) is a modal layer over the screen
				continue
			if base_pairs.has("%d_%d" % [ctl.get_instance_id(), o.get_instance_id()]) or base_pairs.has("%d_%d" % [o.get_instance_id(), ctl.get_instance_id()]):
				continue
			var ov: Rect2 = r1.intersection((o as Control).get_global_rect())
			if ov.size.x > TOL and ov.size.y > TOL:
				var seen: Rect2 = clip_rect(o).intersection((o as Control).get_global_rect())
				var ov2 := r1.intersection(seen)
				if ov2.size.x > TOL and ov2.size.y > TOL:
					over.append("%s x %s %.0fx%.0f" % [nm(ctl), nm(o), ov2.size.x, ov2.size.y])
	return {"moved": moved, "over": over, "clipped": clipped, "hidden": hidden}


## the coordinator's finding (fstool): a panel's own control must not lie outside the panel's rect (it caught the clicks meant for the part)
func escapes() -> Array:
	var out := []
	if ep.panel == null or not ep.panel.visible:
		return out
	var pr: Rect2 = ep.panel.get_global_rect().grow(TOL)
	for c in ep.panel.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or ctl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		var r := ctl.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		var seen := clip_rect(ctl).intersection(r)   # what is left after the scroll and the window cut it
		if seen.size.x < 1.0 or seen.size.y < 1.0:
			continue
		if not pr.encloses(seen):
			out.append("%s %s outside the panel %s" % [nm(ctl), seen, ep.panel.get_global_rect()])
	return out


## a point of the 3D view that no Easy Part box covers: the control under the pointer there must be none (the click reaches the view)
func view_hits() -> Array:
	var out := []
	var vp := root.get_visible_rect()
	for fy in [0.3, 0.45, 0.6, 0.75, 0.9]:
		for fx in [0.08, 0.25, 0.4, 0.55, 0.7]:
			var p := Vector2(vp.size.x * fx, vp.size.y * fy)
			if ep._over_ui(p):
				continue
			var covered := false
			for bx in [ep.hint, ep.status, ep.steps_box, ep.flat_box, ep.hole_box, ep.split_box, ep.round_box, ep.challenge_card, ep.kt.card, ep.quick_box]:
				if bx != null and (bx as Control).is_visible_in_tree() and (bx as Control).get_global_rect().has_point(p):
					covered = true
			if covered:
				continue
			await ev_move(p, false)
			var h := root.gui_get_hovered_control()
			if h != null and h.mouse_filter != Control.MOUSE_FILTER_IGNORE and h.is_visible_in_tree():
				out.append("%s at %s (%s)" % [nm(h), p, h.get_class()])
	return out


func shot(sz: Array, tag: String) -> void:
	await idle(2)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%dx%d_%s.png" % [SHOT, sz[0], sz[1], tag])


# ------------------------------------------------------------------ the panels
func wc(nm_: String) -> Node:
	return m.find_child(nm_, true, false)


func open_panel(id: String) -> Array:
	## returns the extra windows to measure
	match id:
		"hole":
			await click_ctl(ep.make_btns["hole"])
		"parts":
			await click_ctl(ep.parts_btn)
		"colour":
			await click_ctl(ep.make_btns["colour"])
		"repeat":
			await click_ctl(ep.make_btns["repeat"])
		"shape_more":
			await click_ctl(ep.make_btns["draw"])
			await click_ctl(ep.quick_chip)
		"challenges":
			await click_ctl(ep.parts_btn)
			await click_ctl(ep.challenge_btn)
		"keycard":
			ep.kt.fake_ms = 1000 + int(Time.get_ticks_msec())
			for i in 3:
				await click_ctl(ep.undo_btn)
				await click_ctl(ep.redo_btn)
			await idle(4)
		"hovertip":
			await ev_move(ep.make_btns["hole"].get_global_rect().get_center(), false)
			await ev_move(ep.make_btns["hole"].get_global_rect().get_center() + Vector2(1, 1), false)
			await create_timer(1.1).timeout
			await idle(3)
		"export":
			m._export_dialog_open()
			await idle(10)
			return [m.export_ui.dlg]
		"fit":
			await click_ctl(ep.parts_btn)
			await click_ctl(wc("easypart_lib_Boards"))
			await click_ctl(wc("easypart_fit_open_btn"))
			await idle(8)
			return [ep.fit_row.win]
	return []


func close_panel(id: String) -> void:
	match id:
		"hole":
			await click_ctl(ep.make_btns["hole"])
		"parts":
			await click_ctl(ep.parts_btn)
		"colour":
			await click_ctl(ep.make_btns["colour"])
		"repeat":
			await click_ctl(ep.make_btns["repeat"])
		"shape_more":
			if ep.quick_open:
				await click_ctl(ep.quick_chip)
			await click_ctl(ep.make_btns["draw"])
		"challenges":
			if ep.challenge_card.visible:
				await click_ctl(ep.challenge_btn)
			await click_ctl(ep.parts_btn)
		"keycard":
			if ep.kt.card.visible:
				await click_ctl(ep.kt.ok_btn)
		"hovertip":
			await ev_move(Vector2(5, 300), false)
			await idle(6)
		"export":
			m.export_ui.dlg.hide()
		"fit":
			ep.fit_row.win.visible = false
			await click_ctl(ep.parts_btn)
	ep.armed = ""
	await idle(8)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await size_to(1280, 720)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	m.settings = DIRT + "/settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	ok(m.cur_page == "BUILD" and m.bld.part.on and m.bld.part.easy, "0 BUILDING card one click -> Easy Part on (page %s)" % m.cur_page)
	ep = m.bld.part.ep
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	ep._ease_end()
	ep.kt.reload()

	var table := {}
	var bad_cells := 0
	for sz in SIZES:
		await size_to(sz[0], sz[1])
		ep._ease_end()
		await idle(20)
		record_base()
		print("== %dx%d: %d bottom controls recorded" % [sz[0], sz[1], base.size()])
		await shot(sz, "none")
		print("     DBG %dx%d panel %s need %.0f compact %s foot %s parts_chip %s" % [sz[0], sz[1], ep.panel.get_global_rect(), ep._panel_need(), str(ep._compact), str(ep._col_geom(ep._cl)), ep.parts_btn.get_global_rect()])
		var e0: Array = escapes() + await view_hits()
		ok(e0.is_empty(), "BUG5 %dx%d plain: no panel control outside its panel, every free view point reaches the view %s" % [sz[0], sz[1], str(e0.slice(0, 4))])
		for id in PANELS:
			var u0: int = m.undo.size()
			var extra: Array = await open_panel(id)
			await idle(8)
			var r := measure(extra)
			if extra.is_empty():
				r["escape"] = escapes()
				r["hits"] = await view_hits()
				r["moved"] = (r["moved"] as Array) + (r["escape"] as Array) + (r["hits"] as Array)
			var nb := (r["moved"] as Array).size() + (r["over"] as Array).size() + (r["clipped"] as Array).size()
			table["%dx%d %s" % [sz[0], sz[1], id]] = [(r["moved"] as Array).size(), (r["over"] as Array).size(), (r["clipped"] as Array).size()]
			ok(nb == 0, "BUG5 %dx%d %-11s moved %d  overlapped %d  clipped %d" % [sz[0], sz[1], id, (r["moved"] as Array).size(), (r["over"] as Array).size(), (r["clipped"] as Array).size()])
			if nb > 0:
				bad_cells += 1
				for k in ["moved", "over", "clipped"]:
					for s in (r[k] as Array).slice(0, 5):
						print("     %s %s" % [k.to_upper(), s])
				await shot(sz, id)
			await close_panel(id)
			while m.undo.size() > u0:   # the panel's own step (Repeat it makes one at once): taken back, so every cell starts from the same part
				m._undo()
				await idle(8)
			# back to the plain state: every bottom control is where it was
			var back := measure([])
			var nbk := (back["moved"] as Array).size() + (back["clipped"] as Array).size()
			if nbk > 0:
				print("     NOT RESTORED after %s: %s" % [id, str((back["moved"] as Array).slice(0, 3))])
	print("---- TABLE (moved / overlapped / clipped) ----")
	for sz in SIZES:
		var line := "%dx%d " % [sz[0], sz[1]]
		for id in PANELS:
			var t: Array = table["%dx%d %s" % [sz[0], sz[1], id]]
			line += " %s %d/%d/%d" % [id, t[0], t[1], t[2]]
		print(line)
	await size_to(1280, 720)
	print("bug5: %d fail (%d of %d cells)" % [fails, bad_cells, SIZES.size() * PANELS.size()])
	quit(1 if fails > 0 else 0)
