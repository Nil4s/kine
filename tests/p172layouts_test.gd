extends SceneTree
## p172layouts (Friday plan 172): the layout from 1024 x 600 to 3840 x 2160. Real clicks from the BUILDING card: Easy Part with a
## box (draw, drag, pull), then at each window size: the Easy Part panel, the Parts page, the Export dialog and the Pose page.
## Checks with numbers, at every size and state:
##  - no visible Button / LineEdit / Slider is outside the window, or cut by a ScrollContainer (or clipping parent) by more than 2 px
##  - no two visible clickable controls overlap by more than 4 px in both directions (both names are printed)
##  - the ViewCube covers no visible clickable control (more than 2 px in both directions)
## One screenshot per size: user://p172/<w>x<h>.png (the Easy Part state).
## Sizes are set like fmobile: the canvas is w x h logical pixels (embedded window cannot be resized).
const SIZES := [[1024, 600], [1280, 720], [1920, 1080], [2560, 1440], [3840, 2160]]
const DIRT := "user://p172layouts_test"
const SHOT_DIR := "user://p172"
const CLIP_TOL := 2.0
const OVER_TOL := 4.0
const CUBE_TOL := 2.0

var fails := 0
var issues_total := 0
var m: Node


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


func clickable(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button or n is LineEdit or n is Slider:
		if (n as Control).get_global_rect().size.x >= 1.0 and (n as Control).get_global_rect().size.y >= 1.0:
			out.append(n)
	for c in n.get_children():
		clickable(c, out)


func is_anc(a: Node, b: Node) -> bool:
	var p := b
	while p != null:
		if p == a:
			return true
		p = p.get_parent()
	return false


## the part of a control that can be seen: its rect cut by the window and by every clipping ancestor (ScrollContainer, clip_contents).
## scroll = false leaves the ScrollContainers out (the window and the other clipping parents only)
func clip_of(c: Control, scroll := true) -> Rect2:
	var r := root.get_visible_rect()
	var p := c.get_parent()
	while p != null:
		if p is Control and ((scroll and p is ScrollContainer) or ((p as Control).clip_contents and not p is ScrollContainer)):
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


## the name of the clipping ancestor (or the window) that cuts the control
func clipper(c: Control) -> String:
	var r := root.get_visible_rect()
	var who := "window"
	var p := c.get_parent()
	while p != null:
		if p is Control and ((p is ScrollContainer) or (p as Control).clip_contents):
			var nr := r.intersection((p as Control).get_global_rect())
			if nr != r:
				who = "%s %s" % [p.name, (p as Control).get_global_rect()]
			r = nr
		p = p.get_parent()
	return who


func in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func nm(c: Node) -> String:
	var t := ""
	if c is Button or c is Label:
		t = String(c.text)
	if t == "":
		t = String(c.name)
	return t.left(28)


## the layout problems under scope: one string per problem
func issues(scope: Node, cube: Control) -> Array:
	var out := []
	var cs := []
	clickable(scope, cs)
	var vis := []
	for c in cs:
		var ctl := c as Control
		var r := ctl.get_global_rect()
		var clip := clip_of(ctl)            # window, clipping parents and the ScrollContainers
		var wclip := clip_of(ctl, false)    # window and the other clipping parents
		# a control scrolled out of its ScrollContainer is not on screen: that is what a scroll is for
		var seen := clip.intersection(r)
		if in_scroll(ctl) and (seen.size.x < 1.0 or seen.size.y < 1.0):
			continue
		# cut by the window or a clipping parent (more than CLIP_TOL, either axis), or cut sideways by a ScrollContainer.
		# A row cut across by a ScrollContainer's bottom edge is the scroll itself (the rest is one wheel turn away): not counted
		var cut := Vector2(
			maxf(0.0, wclip.position.x - r.position.x) + maxf(0.0, r.end.x - wclip.end.x),
			maxf(0.0, wclip.position.y - r.position.y) + maxf(0.0, r.end.y - wclip.end.y))
		var cut_s := maxf(0.0, clip.position.x - r.position.x) + maxf(0.0, r.end.x - clip.end.x)
		if cut.x > CLIP_TOL or cut.y > CLIP_TOL or cut_s > CLIP_TOL:
			out.append("CUT %s %s cut %.0fx%.0f px by %s" % [nm(c), r, maxf(cut.x, cut_s), cut.y, clipper(ctl)])
		vis.append([c, seen])
	for i in vis.size():
		for j in range(i + 1, vis.size()):
			var a = vis[i][0]
			var b = vis[j][0]
			if is_anc(a, b) or is_anc(b, a):
				continue
			var ov: Rect2 = (vis[i][1] as Rect2).intersection(vis[j][1] as Rect2)
			if ov.size.x > OVER_TOL and ov.size.y > OVER_TOL:
				out.append("OVERLAP %s / %s (%.0fx%.0f px)" % [nm(a), nm(b), ov.size.x, ov.size.y])
	if cube != null and cube.is_visible_in_tree():
		var cr := cube.get_global_rect()
		for v in vis:
			var ctl = v[0]
			if ctl is Control and cube.is_ancestor_of(ctl):
				continue
			var ov2: Rect2 = (v[1] as Rect2).intersection(cr)
			if ov2.size.x > CUBE_TOL and ov2.size.y > CUBE_TOL:
				out.append("CUBE covers %s (%.0fx%.0f px)" % [nm(ctl), ov2.size.x, ov2.size.y])
	return out


## one state at one size: prints the problems (first 12), one ok/FAIL line
func check(state: String, sz: Array, scope: Node) -> void:
	var iss := issues(scope, m.ui_cube)
	issues_total += iss.size()
	ok(iss.is_empty(), "P172 %s %dx%d no cut-off, overlapping or cube-covered control (%d issues)" % [state, sz[0], sz[1], iss.size()])
	for s in iss.slice(0, 12):
		print("     ISSUE %s %dx%d: %s" % [state, sz[0], sz[1], s])


func shot(sz: Array) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%dx%d.png" % [SHOT_DIR, sz[0], sz[1]]))


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
	var ok_easy: bool = m.cur_page == "BUILD" and m.bld.part.on and m.bld.part.easy
	ok(ok_easy, "0 BUILDING card one click -> Easy Part on (page %s)" % m.cur_page)
	if not ok_easy:
		quit(1)
		return

	var ep = m.bld.part.ep
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	# a box: draw, drag on the floor, pull up
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)

	for sz in SIZES:
		await size_to(sz[0], sz[1])
		# 1 Easy Part with the box
		if ep.lib_box != null and ep.lib_box.is_visible_in_tree():
			await click_ctl(ep.parts_btn)   # close the Parts page left open by the last size
			await idle(5)
		check("easy", sz, m)
		await shot(sz)
		# 2 the Parts page
		await click_ctl(ep.parts_btn)
		await idle(5)
		check("parts", sz, m)
		# 3 the Export dialog (a window of its own: only its controls are checked)
		m._export_dialog_open()
		await idle(10)
		check("export", sz, m.export_ui.dlg)
		m.export_ui.dlg.hide()
		await idle(5)
		# 4 the Pose page (leaves Easy Part; Easy comes back for the next size)
		m.easy.set_on(false, false)
		m._page_set("POSE")
		await idle(12)
		check("pose", sz, m)
		m.easy.set_on(true, false)
		await idle(12)

	await size_to(1280, 720)
	print("p172layouts: %d issues in all, %d fail" % [issues_total, fails])
	quit(1 if fails > 0 else 0)
