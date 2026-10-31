extends SceneTree
## p152sculptbrus (Friday plan item 152: sculpt brush Size and Strength sliders with plain words). A beginner on the SCULPT page
## with REAL clicks, drags and keys only: Test sphere, then two sliders under the readout, Size (the brush's radius) and Strength
## (the metres a dab moves, shown in mm). Every number is measured from the sphere's mesh after a stroke, never from the code's
## own variables. Bars (written before the code):
##   1 SLIDERS  after Test sphere: a Size and a Strength slider are on screen (inside the 1280 x 720 view), labelled "Size" and
##              "Strength", not on the SCULPT ribbon row and not over the readout line
##   2 SMALL    Size dragged to its smallest (10 mm), one Inflate stroke: >= 1 vert moves and the moved verts span <= 50 mm
##   3 BIG      Size dragged to about 200 mm, one Inflate stroke at the same spot: the moved verts span >= 150 mm and >= 3x SMALL
##   4 STRENGTH Strength 1 mm, then 10 mm, the same stroke at size 80 mm: the biggest move of a vert from 1 mm to 10 mm is >= 3x
##   5 UNDO     the slider drags add NO undo step; each stroke adds exactly one; Ctrl+Z puts the stroke's verts back exactly
##   6 KEYS     ] (radius bigger) moves the Size slider up by >= 10 %; the Size slider reads small at 10 mm, big at 200 mm
##   7 WORDS    Strength reads soft at 1 mm and firm at 10 mm
##   8 ESC      Esc leaves the sphere: both sliders are hidden
## Screenshots: C:/Temp/claude/p152sculptbrus/ (01_sliders.png, 02_big_stroke.png). Test runs on its own settings file (user://).
const SHOT := "C:/Temp/claude/p152sculptbrus/"

var fails := 0
var m: Node
var ui
var cs := Vector2.ZERO


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree():
			out.append(n)
	return out


## a visible button by the words on it (the ribbon's icon buttons carry their name in label_of)
func find_btn(txt: String) -> Button:
	for b in visible_buttons():
		if m.label_of(b) == txt or (b as Button).text.strip_edges() == txt:
			return b
	return null


func click_text(txt: String) -> bool:
	var b := find_btn(txt)
	if b == null:
		print("   NOT VISIBLE: no button reads '%s'" % txt)
		return false
	var c: Vector2 = b.get_global_rect().get_center()
	await hover(c)
	await mouse(c, true)
	await mouse(c, false)
	await idle(4)
	return true


func hover(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await process_frame


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func drag(a: Vector2, b: Vector2, steps := 8) -> void:
	await mouse(a, true)
	for k in steps:
		await move(a.lerp(b, (k + 1) / float(steps)))
	await mouse(b, false)
	await idle(3)


func key(k: int, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(3)


## the x on a slider for a value (a click or a drag to it moves the knob there)
func slider_x(sl: HSlider, v: float) -> float:
	var r := sl.get_global_rect()
	var f := (v - sl.min_value) / (sl.max_value - sl.min_value)
	return r.position.x + 8.0 + f * (r.size.x - 16.0)


func set_slider(sl: HSlider, v: float) -> void:
	var r := sl.get_global_rect()
	var c := Vector2(slider_x(sl, sl.value), r.get_center().y)
	await drag(c, Vector2(slider_x(sl, v), r.get_center().y), 4)


## the mesh's verts as they are now (a copy), and the ones that moved since v0
func moved(v0: PackedVector3Array) -> Array:
	var out := []
	var v1: PackedVector3Array = ui.mesh.verts
	for i in mini(v0.size(), v1.size()):
		if v0[i].distance_to(v1[i]) > 1e-6:
			out.append(i)
	return out


## the widest span of the moved verts (metres): the largest distance between two of them
func span_of(v0: PackedVector3Array, idx: Array) -> float:
	var best := 0.0
	var v1: PackedVector3Array = ui.mesh.verts
	for a in idx:
		for b in idx:
			best = maxf(best, v1[a].distance_to(v1[b]))
	return best


func max_move(v0: PackedVector3Array, idx: Array) -> float:
	var best := 0.0
	for i in idx:
		best = maxf(best, v0[i].distance_to(ui.mesh.verts[i]))
	return best


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://p152sculptbrus_test"))
	DirAccess.make_dir_recursive_absolute(SHOT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	if m.easy.on:
		await click_text("Switch to Expert")
		await idle(10)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await click_text("SCULPT")
	await idle(6)
	await click_text("Test sphere")
	await idle(10)
	ui = m.ksc
	if ui == null or not ui.on:
		print("SCULPT P152SCULPTBRUS FAIL: the test sphere did not open")
		quit(1)
		return
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	cs = m.cam.unproject_position(wc)
	var sl_size := ui._ov.find_child("sculpt_size", true, false) as HSlider   # the overlay holds the sliders (not the UI node)
	var sl_str := ui._ov.find_child("sculpt_strength", true, false) as HSlider
	var view_r := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var rib: Rect2 = m.ui_ribbon["SCULPT"].get_global_rect()
	var rd: Rect2 = ui.readout.get_global_rect()
	var lab_ok := false
	if sl_size != null and sl_str != null:
		var txt := ""
		for n in walk(ui._ov, []):
			if n is Label and (n as Label).visible:
				txt += (n as Label).text + " | "
		lab_ok = txt.contains("Size") and txt.contains("Strength")
	var clear := sl_size != null and sl_str != null and sl_size.is_visible_in_tree() and sl_str.is_visible_in_tree()
	if clear:
		for s in [sl_size, sl_str]:
			var r: Rect2 = s.get_global_rect()
			clear = clear and view_r.encloses(r) and not r.intersects(rib) and not r.intersects(rd)
	await shot("01_sliders")
	print("   diag: viewport %s, slider found %s/%s, labels ok %s, ribbon %s, readout %s" % [str(view_r), str(sl_size != null), str(sl_str != null), str(lab_ok), str(rib), str(rd)])
	if sl_size != null:
		print("   diag: size slider rect %s visible %s; strength slider rect %s visible %s" % [str(sl_size.get_global_rect()), str(sl_size.is_visible_in_tree()), str(sl_str.get_global_rect()), str(sl_str.is_visible_in_tree())])
	ok(clear and lab_ok, "(1) SLIDERS: Size and Strength on screen %s, labelled %s, clear of the ribbon row and the readout %s" % [str(clear), str(lab_ok), str(clear)])
	if not clear:
		print("P152SCULPTBRUS FAIL %d" % fails)
		quit(1)
		return

	# 2 SMALL: Size to 10 mm (the smallest), Inflate by its key, one stroke
	var s0: int = ui.undo.steps.size()
	await set_slider(sl_size, 10.0)
	var s1: int = ui.undo.steps.size()
	await set_slider(sl_str, 1.0)
	var s2: int = ui.undo.steps.size()
	var v0: PackedVector3Array = ui.mesh.verts.duplicate()
	await key(KEY_I)
	# a longer sweep: the test sphere's cells are ~25 mm, so a 10 mm brush needs a path that crosses a vert
	await drag(cs + Vector2(-60, 0), cs + Vector2(60, 0), 12)
	var idx_s: Array = moved(v0)
	var span_s := span_of(v0, idx_s)
	ok(idx_s.size() >= 1 and span_s <= 0.05,
		"(2) SMALL: Size at 10 mm, one Inflate stroke: %d verts moved, span %.1f mm (must be >= 1 vert and <= 50 mm)" % [idx_s.size(), span_s * 1000.0])
	var s3: int = ui.undo.steps.size()
	# 5 UNDO: the slider drags added no step; the stroke added one; Ctrl+Z puts the verts back exactly
	await key(KEY_Z, true)
	await idle(3)
	var back := true
	for i in v0.size():
		if ui.mesh.verts[i] != v0[i]:
			back = false
			break
	ok(s1 == s0 and s2 == s1 and s3 == s2 + 1 and back,
		"(5) UNDO: slider drags added %d + %d steps (must be 0), the stroke %d (must be 1); Ctrl+Z restores every vert %s" % [s1 - s0, s2 - s1, s3 - s2, str(back)])

	# 3 BIG: Size to about 200 mm, the same stroke
	await set_slider(sl_size, 200.0)
	var v1: PackedVector3Array = ui.mesh.verts.duplicate()
	await drag(cs + Vector2(-20, 0), cs + Vector2(20, 0), 6)
	var idx_b: Array = moved(v1)
	var span_b := span_of(v1, idx_b)
	await shot("02_big_stroke")
	ok(span_b >= 0.15 and span_b >= 3.0 * maxf(span_s, 1e-6),
		"(3) BIG: Size about 200 mm, one stroke: %d verts moved, span %.1f mm (must be >= 150 mm and >= 3x the small %.1f mm)" % [idx_b.size(), span_b * 1000.0, span_s * 1000.0])
	await key(KEY_Z, true)
	await idle(3)

	# 4 STRENGTH: 1 mm then 10 mm, the same stroke at size 80 mm
	await set_slider(sl_size, 80.0)
	await set_slider(sl_str, 1.0)
	var v2: PackedVector3Array = ui.mesh.verts.duplicate()
	await drag(cs + Vector2(-20, 0), cs + Vector2(20, 0), 6)
	var d1 := max_move(v2, moved(v2))
	await key(KEY_Z, true)
	await idle(3)
	await set_slider(sl_str, 10.0)
	var v3: PackedVector3Array = ui.mesh.verts.duplicate()
	await drag(cs + Vector2(-20, 0), cs + Vector2(20, 0), 6)
	var d10 := max_move(v3, moved(v3))
	ok(d1 > 0.0 and d10 >= 3.0 * d1,
		"(4) STRENGTH: the biggest move of a vert: %.2f mm at 1 mm strength, %.2f mm at 10 mm (must be >= 3x)" % [d1 * 1000.0, d10 * 1000.0])
	await key(KEY_Z, true)
	await idle(3)

	# 6 KEYS: ] makes the radius bigger; the Size slider follows it up
	await set_slider(sl_size, 100.0)
	var before_v: float = sl_size.value
	await key(KEY_BRACKETRIGHT)
	await idle(3)
	var after_v: float = sl_size.value
	ok(after_v >= before_v * 1.1, "(6) KEYS: ] moves the Size slider up: %.0f mm -> %.0f mm (must be >= 10 %% more)" % [before_v, after_v])

	# 7 WORDS: small / big, soft / firm
	await set_slider(sl_size, 10.0)
	var w_small := _word(sl_size)
	await set_slider(sl_size, 200.0)
	var w_big := _word(sl_size)
	await set_slider(sl_str, 1.0)
	var w_soft := _word(sl_str)
	await set_slider(sl_str, 10.0)
	var w_firm := _word(sl_str)
	ok(w_small.contains("small") and w_big.contains("big") and w_soft.contains("soft") and w_firm.contains("firm"),
		"(7) WORDS: size reads '%s' then '%s'; strength reads '%s' then '%s'" % [w_small, w_big, w_soft, w_firm])

	# 8 ESC: leaves; the sliders are hidden with the sphere
	await key(KEY_ESCAPE)
	await idle(3)
	ok(not sl_size.is_visible_in_tree() and not sl_str.is_visible_in_tree(),
		"(8) ESC: both sliders hidden after leaving the sphere (size %s, strength %s)" % [str(sl_size.is_visible_in_tree()), str(sl_str.is_visible_in_tree())])
	print("P152SCULPTBRUS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)


## the word the Size or Strength label shows (the label beside the slider)
func _word(sl: HSlider) -> String:
	var p := sl.get_parent()
	var lab := p.get_child(sl.get_index() - 1)   # each slider sits under its own label
	return (lab as Label).text if lab is Label else ""


func shot(name: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SHOT + name + ".png")
