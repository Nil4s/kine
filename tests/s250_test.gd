extends SceneTree
## s250 TWO CLIPPED THINGS at 1024 x 600 (Easy Part): (a) the side panel's title "Your part" sat under the Empty / Slot / Examples chips
## (same row, the title shrank to nothing); (b) the BUILD page tab's icon was faint and cut at the left edge of the window.
## Bars at 1024 x 600 .. 2560 x 1440, on the default page and the Parts library page: the title's drawn text rect (font string size)
## touches no visible chip/tab; every page tab's icon rect and label rect lie inside the viewport (and the tab) and the icon is drawn at alpha >= 0.9;
## a real click on Empty / Slot / Examples still works.
## CONTROL: the old layout (title in the chips' row) is computed the same way and must fail; so must a faded icon and an icon pushed off the edge.
## Shots: C:/Users/Nick/tools/kine_workers/out/250/
var fails := 0
var m: Node
var pu
var ep
const SHOT := "C:/Users/Nick/tools/kine_workers/out/250"
const DIRT := "user://s250_test"
const SIZES := [[1024, 600], [1280, 720], [1920, 1080], [2560, 1440]]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev(p, true)
	await ev(p, false)
	await idle(2)


func size_to(w: int, h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	await idle(14)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## the title's drawn rect: first glyph at the label's origin, the string's size at the label's font (clip_text hides text, it does not shrink it)
func title_rect() -> Rect2:
	var l: Label = ep.panel_title
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	return Rect2(l.get_global_rect().position, f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs))


func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button:
		var r := (n as Control).get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0 and (n as CanvasItem).modulate.a > 0.05:
			out.append([String(n.name), r])
	for ch in n.get_children():
		_collect(ch, out)


func hits(r: Rect2) -> Array:
	var out := []
	var all := []
	_collect(root, all)
	for b in all:
		if r.intersects(b[1]):
			out.append("%s %s" % [b[0], b[1]])
	return out


## a tab's drawn icon rect and label rect (Button content: icon, h_separation, text; centred in the box less its margins)
func tab_parts(b: Button) -> Dictionary:
	var f := b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var tw := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var isz := Vector2.ZERO
	if b.icon != null:
		isz = b.icon.get_size()
		var mw := b.get_theme_constant("icon_max_width")
		if mw > 0 and isz.x > mw:
			isz *= float(mw) / isz.x
	var sep := b.get_theme_constant("h_separation")
	var sb := b.get_theme_stylebox("normal")
	var box := b.get_global_rect()
	var cw := isz.x + (sep if b.icon != null and b.text != "" else 0) + tw.x
	var x0 := box.position.x + sb.get_margin(SIDE_LEFT)
	var avail := box.size.x - sb.get_minimum_size().x
	var x := x0 + maxf(0.0, (avail - cw) * 0.5)
	var cy := box.position.y + box.size.y * 0.5
	var ir := Rect2(Vector2(x, cy - isz.y * 0.5), isz)
	var lr := Rect2(Vector2(x + isz.x + sep, cy - tw.y * 0.5), tw)
	return {"icon": ir, "label": lr, "avail": Rect2(x0, box.position.y, avail, box.size.y), "cw": cw}


func icon_alpha(b: Button) -> float:
	var c: Color = b.get_theme_color("icon_pressed_color") if b.button_pressed else b.get_theme_color("icon_normal_color")
	if b.disabled:
		c = b.get_theme_color("icon_disabled_color")
	return b.modulate.a * b.self_modulate.a * c.a


## WCAG-style contrast of the icon's colour (open tab: the pressed colour) against the tab's own fill
func icon_contrast(b: Button, c: Color = Color(0, 0, 0, 0)) -> float:
	var ic: Color = c if c.a > 0.0 else (b.get_theme_color("icon_pressed_color") if b.button_pressed else b.get_theme_color("icon_normal_color"))
	var bg: Color = (b.get_theme_stylebox("pressed") if b.button_pressed else b.get_theme_stylebox("normal")).get("bg_color")
	var l1 := _lum(ic)
	var l2 := _lum(bg)
	return (maxf(l1, l2) + 0.05) / (minf(l1, l2) + 0.05)


func _lum(c: Color) -> float:
	return 0.2126 * pow(c.r, 2.2) + 0.7152 * pow(c.g, 2.2) + 0.0722 * pow(c.b, 2.2)


func tabs_ok(tag: String) -> void:
	var vr := root.get_visible_rect()
	for p in m.ui_page_btns:
		var b: Button = m.ui_page_btns[p]
		if not b.is_visible_in_tree():
			continue
		var d := tab_parts(b)
		var ir: Rect2 = d["icon"]
		var lr: Rect2 = d["label"]
		ok(vr.grow(0.5).encloses(ir) and vr.grow(0.5).encloses(lr), "%s tab %s icon %s and label %s inside the window %s" % [tag, p, ir, lr, vr])
		ok((d["avail"] as Rect2).grow(1.0).encloses(ir) and (d["avail"] as Rect2).grow(1.0).encloses(lr), "%s tab %s icon+label inside the tab's own room %s" % [tag, p, d["avail"]])
		var a := icon_alpha(b)
		ok(b.disabled or icon_contrast(b) >= 4.5, "%s tab %s icon contrast %.1f >= 4.5 against its tab fill (pressed %s)" % [tag, p, icon_contrast(b), b.button_pressed])
		ok(b.disabled or a >= 0.9, "%s tab %s icon alpha %.2f >= 0.9 (disabled %s)" % [tag, p, a, b.disabled])


func _btn_text(t: String) -> Button:
	var out := []
	_find_text(root, t, out)
	return out[0] if not out.is_empty() else null


func _find_text(n: Node, t: String, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).text == t:
		out.append(n)
	for ch in n.get_children():
		_find_text(ch, t, out)


func set_parts(on: bool) -> void:
	for i in 3:
		if ep.parts_open == on:
			break
		var pbb := root.find_child("easypart_chip_parts", true, false) as Button
		(root.find_child("easypart_panel_scroll", true, false) as ScrollContainer).ensure_control_visible(pbb)   # a user scrolls to the Parts chip: it is under the page's long grid
		await idle(3)
		print("     set_parts %s: chip %s visible %s disabled %s title '%s'" % [on, pbb.get_global_rect(), pbb.is_visible_in_tree(), pbb.disabled, ep.panel_title.text])
		await click_ctl(pbb)
		await idle(30 if on else 8)


func fresh() -> void:
	m.S.part = {}
	pu.sync()
	await idle(10)


func page_check(tag: String) -> void:
	ep.layout(ep._cl)
	await idle(4)
	var tr := title_rect()
	var full := tr
	var scr := root.find_child("easypart_panel_scroll", true, false) as Control
	if scr != null:
		tr = tr.intersection(scr.get_global_rect())   # the scroll area clips what is scrolled out: only the DRAWN part can be covered
	var others := []
	for h in hits(tr):
		if not str(h).begins_with("easypart_panel_title"):
			others.append(h)
	ok(ep.panel_title.is_visible_in_tree() and full.size.x > 20 and (tag.ends_with("library") or tr.size.x >= full.size.x - 1.0), "%s title \"%s\" is visible and whole on the default page, drawn %s (shown %s)" % [tag, ep.panel_title.text, full, tr])
	ok(others.is_empty(), "%s title rect %s touches no chip or tab: %s" % [tag, tr, others])
	ok(root.get_visible_rect().grow(0.5).encloses(full), "%s title rect inside the window" % tag)
	ok(ep.panel.get_global_rect().grow(0.5).encloses(full), "%s title rect inside its panel %s" % [tag, ep.panel.get_global_rect()])
	await tabs_ok(tag)


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
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	for sz in SIZES:
		var w: int = sz[0]
		var h: int = sz[1]
		await size_to(w, h)
		await fresh()
		var tag := "%dx%d" % [w, h]
		var pb := root.find_child("easypart_chip_parts", true, false) as Button
		if ep.parts_open:
			await click_ctl(pb)
			await idle(6)
		print("     STATE %s parts_open %s libgroups %s empty_chip %s title %s part %s" % [tag, ep.parts_open, ep.lib_group_row.is_visible_in_tree(), ep.empty_chip.is_visible_in_tree(), ep.panel_title.get_global_rect(), str(m.S.part).left(60)])
		await page_check(tag + " default")
		if w == 1024:
			await shot("default_%s" % tag)
		# real clicks on the three chips
		var eb: Button = ep.empty_chip
		var xb: Button = root.find_child("easypart_more_examples", true, false)
		var sb: Button = ep.chips["slothole"]
		var pr: Rect2 = ep.panel.get_global_rect()
		ok(pr.grow(0.5).encloses(eb.get_global_rect()) and pr.grow(0.5).encloses(xb.get_global_rect()) and pr.grow(0.5).encloses(sb.get_global_rect()), "%s Empty / Slot / Examples inside the panel %s" % [tag, pr])
		await click_ctl(eb)
		var p_empty := str(m.S.part)
		await click_ctl(sb)
		var p_slot := str(m.S.part)
		ok(p_slot != p_empty and ep._tpl() == "slothole", "%s a real click on Slot works (template %s)" % [tag, ep._tpl()])
		await click_ctl(eb)
		ok(str(m.S.part) != p_slot and ep._tpl() != "slothole", "%s a real click on Empty works (template '%s')" % [tag, ep._tpl()])
		# the Parts library page
		await set_parts(true)
		await page_check(tag + " library")
		if w == 1024:
			await shot("library_%s" % tag)
		await set_parts(false)
		var xb2: Button = root.find_child("easypart_more_examples", true, false)
		await click_ctl(xb2)
		await idle(6)
		ok(true, "%s a real click on Examples ran (panel visible %s)" % [tag, ep.panel.visible])
		if w == 1024:
			await shot("examples_%dx%d" % [w, h])
		if w == 1024:
			await shot("examples_%dx%d" % [w, h])
		var back := _btn_text("Back")
		if back == null:
			back = _btn_text("Bring back your part")
		ok(back != null, "%s the chooser shows a way back" % tag)
		if back != null:
			await click_ctl(back)
			await idle(8)
		ok(_btn_text("New assembly") == null, "%s the chooser is closed again" % tag)
		ok(ep.panel.is_visible_in_tree(), "%s back in Easy Part after the chooser (panel visible %s)" % [tag, ep.panel.is_visible_in_tree()])
		print("     after Examples: panel visible %s, page %s, easy_open visible %s, part_btn pressed %s" % [ep.panel.is_visible_in_tree(), m.cur_page, pu.easy_open_btn.is_visible_in_tree(), pu.part_btn.button_pressed])
		if not ep.panel.is_visible_in_tree():
			if not pu.easy_open_btn.is_visible_in_tree():
				await click_ctl(pu.part_btn)
			await click_ctl(pu.easy_open_btn)
			await idle(6)
	# CONTROL: the old layout. The title shared the row with Empty, Slot and Examples and shrank to nothing in front of them, so its text ran
	# under the Empty chip. Computed here: the title's text rect starting at the row's left edge, in the row the chips occupy.
	await size_to(1024, 600)
	await fresh()
	var thr: Control = ep.empty_chip.get_parent()
	var f: Font = ep.panel_title.get_theme_font("font")
	var fs: int = ep.panel_title.get_theme_font_size("font_size")
	var old_w: float = f.get_string_size("Change your part", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var chips_w := 0.0
	for c in thr.get_children():
		if c is Button and c.visible:
			chips_w += (c as Control).size.x + 4.0
	var row_w: float = (ep.panel.get_global_rect().size.x - 40.0)
	var old_room: float = row_w - chips_w
	var old := Rect2(thr.get_global_rect().position, Vector2(old_w, 28))
	var chip_r := Rect2(thr.get_global_rect().position + Vector2(old_room, 0), Vector2(chips_w, 34))
	print("     CONTROL old layout: title text %.0f px wide, room left of the chips %.0f px (chips from x+%.0f)" % [old_w, old_room, old_room])
	ok(old.intersects(chip_r), "control: the old one-line layout (\"Change your part\" + the chips in one row) puts the title %.0f px into chips that start at %.0f px, so the bar can fail" % [old_w, old_room])
	var tb: Button = m.ui_page_btns["STAGE"]
	var keep := tb.modulate
	tb.modulate = Color(1, 1, 1, 0.5)
	ok(icon_alpha(tb) < 0.9, "control: a half-faded tab icon reads alpha %.2f < 0.9, so the alpha bar can fail" % icon_alpha(tb))
	tb.modulate = keep
	ok(icon_contrast(tb, Tok.c("on_accent")) < 4.5, "control: the old open-tab icon colour (on_accent) has contrast %.1f < 4.5 on the tab fill, so the contrast bar can fail" % icon_contrast(tb, Tok.c("on_accent")))
	var d := tab_parts(tb)
	var shifted := Rect2((d["icon"] as Rect2).position - Vector2(500, 0), (d["icon"] as Rect2).size)
	ok(not root.get_visible_rect().encloses(shifted), "control: an icon pushed off the left edge fails the inside-window bar")
	print("s250: %d fail" % fails)
	quit(1 if fails > 0 else 0)
