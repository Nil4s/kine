extends SceneTree
## s248 STATUS LINE vs THE PAGE BAR. Easy Part's one-sentence status ("Nothing here yet") sat under the BUILD tab at 1024 x 600 (the narrow
## layout put it at the window's bottom edge). The drawn text rect (the font's wrapped string size, not the control rect) must touch no
## visible button, nor the page bar, at 1024 x 600 .. 2560 x 1440, with the longest status strings (and a Portuguese and a CJK one).
## CONTROL: the origin layout (status at vp bottom - 6, the old _low_end) is computed the same way and must fail the bar.
## Shots: C:/Users/Nick/tools/kine_workers/out/248/
var fails := 0
var m: Node
var pu
var ep
const SHOT := "C:/Users/Nick/tools/kine_workers/out/248"
const DIRT := "user://s248_test"
const SIZES := [[1024, 600], [1280, 720], [1920, 1080], [2560, 1440]]
const LONG := [
	"Greyed out: this tool is not in this copy of Kine",
	"One step could not follow the new sizes. Undo takes it back",
	"12 pieces that do not touch: Stick together joins them",
	"Restart Kine first; if this stays, reinstall KineCAD: the part tools did not load",
	"Nada aqui ainda. Aperte Desenhar forma e arraste na grade para comecar uma peca nova, depois puxe para cima e arredonde as quinas",
	"ここにはまだ何もありません。図形を描くを押して、グリッドの上をドラッグして新しいパーツを作り始め、上に引き上げて角を丸くします",
]


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


## the status text's drawn rect: where its first glyph starts, the wrapped string's size at the label's width
func text_rect() -> Rect2:
	var l: Label = ep.status_l
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var w := l.size.x if l.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
	var sz := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE | TextServer.BREAK_MANDATORY)
	return Rect2(l.get_global_rect().position, sz)


## every visible button (and the page bar panel) that is not part of the status pill
func blockers() -> Array:
	var out := []
	_collect(root, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and not ep.status.is_ancestor_of(n):
		var r := (n as Control).get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0 and (n as CanvasItem).modulate.a > 0.05:
			out.append([String(n.name), r])
	if n == m.ui_page_bar:
		out.append(["page_bar", (n as Control).get_global_rect()])
	for ch in n.get_children():
		_collect(ch, out)


func hits(r: Rect2) -> Array:
	var out := []
	for b in blockers():
		if r.intersects(b[1]):
			out.append("%s %s" % [b[0], b[1]])
	return out


func say(text: String) -> void:
	ep.status_l.text = text
	ep.layout(ep._cl)
	await idle(3)
	ep.layout(ep._cl)
	await idle(2)


func check(tag: String, text: String) -> void:
	await say(text)
	var tr := text_rect()
	var pill: Rect2 = ep.status.get_global_rect()
	var vr := root.get_visible_rect()
	var h := hits(tr)
	ok(h.is_empty(), "%s text rect %s touches no button or bar: %s" % [tag, tr, h])
	ok(vr.grow(0.5).encloses(tr), "%s text rect %s is inside the window" % [tag, tr])
	ok(pill.grow(0.5).encloses(tr), "%s text rect is inside its own pill %s" % [tag, pill])
	ok(not Rect2(pill.position, pill.size).intersects(ep.panel.get_global_rect()), "%s pill clear of the side panel" % tag)


func fresh() -> void:
	m.S.part = {}
	pu.sync()
	await idle(10)


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
		ok(ep.status_l.text == "Nothing here yet" or ep.status_l.text != "", "%s status shows: %s" % [tag, ep.status_l.text])
		await check(tag + " real", ep.status_l.text)
		if w == 1024:
			await shot("real_%s" % tag)
		var i := 0
		for t in LONG:
			await check("%s long#%d" % [tag, i], t)
			if w == 1024 and (i == 3 or i == 4 or i == 5):
				await shot("long%d_%s" % [i, tag])
			i += 1
		# a real click at the BUILD tab centre still opens build (leave to STAGE first at 1024 only)
		if w == 1024:
			await fresh()
			var tb: Button = m.ui_page_btns["BUILD"]
			var c := tb.get_global_rect().get_center()
			var top := root.gui_get_hovered_control() if false else null
			ok(tb.is_visible_in_tree(), "%s the BUILD tab is visible" % tag)
			var before: String = m.cur_page
			m._page_set("STAGE")
			await idle(4)
			ok(m.cur_page == "STAGE", "%s went to STAGE" % tag)
			var tb2: Button = m.ui_page_btns["BUILD"]
			await click_at(tb2.get_global_rect().get_center())
			ok(m.cur_page == "BUILD", "%s a real click at the BUILD tab centre opens BUILD (page %s, was %s)" % [tag, m.cur_page, before])
			await idle(6)
	# CONTROL: the origin layout puts the sentence at the window's bottom edge (vp bottom - 6) on a narrow window: it must fail the same bar
	await size_to(1024, 600)
	await fresh()
	await say("Nothing here yet")
	var pill: Rect2 = ep.status.get_global_rect()
	var old_pos := Vector2(pill.position.x, root.get_visible_rect().end.y - 6.0 - pill.size.y)
	var old_text := Rect2(old_pos + (text_rect().position - pill.position), text_rect().size)
	var oh := hits(old_text)
	print("     CONTROL origin text rect %s hits %s" % [old_text, oh])
	ok(not oh.is_empty() and str(oh).contains("tab_build"), "control: the origin layout's text rect hits the BUILD tab, so the bar can fail")
	print("s248: %d fail" % fails)
	quit(1 if fails > 0 else 0)
