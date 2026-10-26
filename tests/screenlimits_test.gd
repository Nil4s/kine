## godot --path . -s tests/screenlimits_test.gd     (a real window; the layout is pinned to 1280 x 720, 1024 x 600 and 1024 x 576)
## SCREEN LIMITS: on each page (BODY, POSE, ANIMATE, STAGE, CHECK, DELIVER) and each panel that can outgrow the screen
## (the Help panel, the page bar with its next-tool chips, the POSE weight-paint row, the play row, the ANIMATE row),
## every VISIBLE Control's global rect lies inside the viewport (1 px tolerance). Controls inside a ScrollContainer are
## checked only as far as the scroll area itself (they scroll into view). The Help panel's "Got it" is clicked for real and
## must close it. Screenshots go to SL_SHOTS (default C:/Temp/claude/sl), named by SL_TAG (before / after).
extends SceneTree

const SIZES := [Vector2i(1280, 720), Vector2i(1024, 600), Vector2i(1024, 576)]   # 1024 x 576 = a 1280 x 720 window at UI size 125 %
const PAGES_CHECKED := ["BODY", "POSE", "ANIMATE", "STAGE", "CHECK", "DELIVER"]
const TOL := 1.0
const LONG_CHIPS := ["Fix moves through the body", "Choreograph to the song", "What I learned from you"]

var fails := 0
var m: Node
var shots := ""
var tag := ""
var checked := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func inside(r: Rect2, vp: Rect2) -> bool:
	return r.position.x >= vp.position.x - TOL and r.position.y >= vp.position.y - TOL \
		and r.end.x <= vp.end.x + TOL and r.end.y <= vp.end.y + TOL


## every shown Control in the main window whose global rect is outside the viewport: [path, rect] pairs
func outside(n: Node, vp: Rect2, out: Array) -> void:
	for c in n.get_children():
		if c is Window:
			continue   # a popup or a dialog: its own window and viewport
		if c is Control:
			var ctl := c as Control
			if not ctl.is_visible_in_tree():
				continue
			var r := ctl.get_global_rect()
			if r.size.x > 0 and r.size.y > 0:
				checked += 1
				if not inside(r, vp):
					out.append([str(m.get_path_to(ctl)), r])
			if not (ctl is ScrollContainer):   # the scroll area's content is clipped and scrolls: its own rects are not the screen's
				outside(ctl, vp, out)
		elif c is CanvasLayer or (c is CanvasItem and (c as CanvasItem).visible):
			outside(c, vp, out)


func check_screen(size: Vector2i, label: String) -> void:
	var vp := Rect2(Vector2.ZERO, Vector2(size))
	var out := []
	checked = 0
	outside(m, vp, out)
	for o in out:
		print("     out: %s  rect %s  (viewport %dx%d)" % [o[0], str(o[1]), size.x, size.y])
	ok(out.is_empty(), "%dx%d %s: every visible control inside the viewport (%d checked, %d outside)" % [size.x, size.y, label, checked, out.size()])


func find_named(nm: String) -> Control:
	return m.find_child(nm, true, false) as Control


## a real press + release at the control's centre (the clicks test's way): false if it is not shown
func click(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := root.get_final_transform() * c.get_global_rect().get_center()   # the window's pixels: the layout is scaled to them
	var mv := InputEventMouseMotion.new()   # the pointer comes to the control first, as a person's does
	mv.position = p
	mv.global_position = p
	root.push_input(mv)
	await idle(2)
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
	await idle(3)
	return true


func button_text(n: Node, text: String) -> Button:
	for c in n.find_children("*", "Button", true, false):
		if (c as Button).text == text:
			return c
	return null


func shot(name: String) -> void:
	m.get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [shots, tag, name])


func _init() -> void:
	shots = OS.get_environment("SL_SHOTS")
	if shots == "":
		shots = "C:/Temp/claude/sl"
	tag = OS.get_environment("SL_TAG")
	if tag == "":
		tag = "run"
	DirAccess.make_dir_recursive_absolute(shots)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")   # a scene with its clips: the play row and the cards carry real content
	m._rebuild_cards()
	await idle(4)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for size in SIZES:
		root.content_scale_size = size
		await idle(8)
		var vp := m.get_viewport().get_visible_rect()
		ok(vp.size == Vector2(size), "layout pinned to %dx%d (the viewport is %s)" % [size.x, size.y, str(vp.size)])
		for p in PAGES_CHECKED:
			m._page_set(p, false)   # save=false: the page remembered in the user's settings is not written
			await idle(6)
			# the next-tool chips at their widest: three, with the longest command names (the seed's habits fill them at random)
			for i in m.ui_nt_box.get_child_count():
				var ch := m.ui_nt_box.get_child(i) as Button
				ch.text = LONG_CHIPS[i]
				ch.visible = true
			await idle(4)
			check_screen(size, "page %s, three chips" % p)
			for folded in [false, true]:   # the scene panel (the clips, the play row) open, then folded to the timeline
				m._fold("bottom", folded, false)   # save=false: the user's own fold setting is not written
				await idle(4)
				check_screen(size, "page %s%s" % [p, ", scene panel folded" if folded else ""])
			m._fold("bottom", false, false)
			await idle(4)
			shot("%dx%d_%s" % [size.x, size.y, p.to_lower()])
			if p == "POSE":
				m._wp_toggle()   # Weight paint on: its row shows
				await idle(6)
				check_screen(size, "page POSE, Weight paint on")
				shot("%dx%d_pose_weights" % [size.x, size.y])
				var brush := find_named("weight_paint_brush")   # the Brush popover: a real press opens the Bone / Brush / size / strength row
				var pressed := await click(brush)
				await idle(4)
				ok(pressed and m.wp_pop.visible, "%dx%d POSE: the Brush button opens the Weight paint popover" % [size.x, size.y])
				shot("%dx%d_pose_brush_popover" % [size.x, size.y])
				m.wp_pop.hide()
				await idle(2)
				m._wp_toggle()
				await idle(4)
			# the Help panel: opened by its own button (a real press), then Got it (a real press) closes it
			var hb := find_named("b_help")
			if m.ui_help.visible:
				m.ui_help.visible = false
			var opened := await click(hb)
			await idle(4)
			ok(opened and m.ui_help.visible, "%dx%d %s: the ? Help button is on screen and opens the panel" % [size.x, size.y, p])
			if m.ui_help.visible:
				check_screen(size, "page %s, Help open" % p)
				shot("%dx%d_%s_help" % [size.x, size.y, p.to_lower()])
				var got := button_text(m.ui_help, "Got it")
				var gvp := m.get_viewport().get_visible_rect()
				ok(got != null and got.is_visible_in_tree() and inside(got.get_global_rect(), gvp),
					"%dx%d %s: Got it is inside the viewport (%s)" % [size.x, size.y, p, str(got.get_global_rect()) if got != null else "missing"])
				var clicked := await click(got)
				ok(clicked and not m.ui_help.visible, "%dx%d %s: a real click on Got it closes the Help panel" % [size.x, size.y, p])
			else:
				m.ui_help.visible = false
	print("SCREENLIMITS: %d FAIL line(s)" % fails)
	quit(1 if fails > 0 else 0)
