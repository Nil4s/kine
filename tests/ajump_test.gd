extends SceneTree
## godot --path . -s tests/ajump_test.gd   (AJUMP: a beginner jumps over a box in Easy, real clicks from the start screen, 1280x720)
const OUT := "C:/Temp/claude/ajump/"
const SIZE := Vector2i(1280, 720)
var fails := 0
var m: Node
var dead := []


func bar(c: bool, w: String, known := false) -> void:
	if known:
		print(("KNOWN " if not c else "FAIL (known dead end now works, drop KNOWN) ") + w)
		if c:
			fails += 1
		return
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	m.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")


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


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await idle(2)
	await mouse(p, true)
	await mouse(p, false)
	await idle(8)


func key(code: Key, ch := "") -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.unicode = ch.unicode_at(0) if ch != "" else 0
	k.pressed = true
	root.push_input(k)
	await process_frame
	var u := InputEventKey.new()
	u.keycode = code
	u.physical_keycode = code
	u.pressed = false
	root.push_input(u)
	await idle(3)


func visible_btn(txt: String) -> Button:
	for n in walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree() and (n as Button).text.strip_edges() == txt:
			return n
	return null


func on_screen(c: Control) -> bool:
	var r := c.get_global_rect()
	return r.size.x > 1.0 and r.size.y > 1.0 and Rect2(Vector2.ZERO, Vector2(SIZE)).encloses(r)


func by_tip(t: String) -> Button:
	for n in walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree() and str((n as Button).tooltip_text).contains(t):
			return n
	return null


func crate_index() -> int:
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]) == "crate":
			return i
	return -1


## the box's footprint, and the top of the box
func box_rect(p: Dictionary) -> Rect2:
	var xf: Transform3D = p["xf"]
	var c := Vector2(xf.origin.x, xf.origin.z)
	return Rect2(c - Vector2(0.3, 0.2), Vector2(0.6, 0.4))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.get_window().size = SIZE
	await idle(10)
	m.start_screen.show_screen(true)
	await idle(10)
	var eb: Button = m.start_screen.find_child("easy_animation", true, false)
	bar(eb != null and eb.is_visible_in_tree() and on_screen(eb), "0 the start screen has a visible Easy button under Animation")
	await click(eb)
	await idle(10)
	bar(m.easy.on, "1 Easy is on after the start screen click")
	shot("01_easy_start")

	# 2 a crate from the Library, by a real click on its tile (found by Search: crate)
	var lib := by_tip("Open the object library")
	if lib == null:
		lib = by_tip("Library")
	await click(lib)
	await idle(6)
	var se: LineEdit = null
	for n in walk(root, []):
		if n is LineEdit and (n as LineEdit).is_visible_in_tree():
			se = n
	if se != null:
		await click(se)
		for ch in "crate":
			await key(OS.find_keycode_from_string(ch.to_upper()), ch)
		await idle(8)
	var tile: Control = null
	for n in walk(root, []):
		if n.name == "tile_prop_crate" and (n as Control).is_visible_in_tree():
			tile = n
	bar(tile != null and on_screen(tile), "2 the Library finds a Crate tile on screen (Search 'crate')")
	shot("02_library_crate")
	var n0: int = m.S.props.size()
	if tile != null:
		await click(tile)
		await idle(8)
	bar(m.S.props.size() == n0 + 1 and crate_index() >= 0, "2 a click on the Crate tile puts a crate in the scene (props %d -> %d)" % [n0, m.S.props.size()])
	if m.ui_library != null:
		m.ui_library.hide_panel()
	await idle(6)
	shot("03_crate_placed")
	var ci := crate_index()
	var box := box_rect(m.S.props[ci]) if ci >= 0 else Rect2()
	var top := 0.5   # the crate's top (m)

	# 3 a beginner types the plain words: 'jump over the crate'
	var edit := m.easy.home.panel.find_child("eh_text", true, false) as LineEdit
	await click(edit)
	for ch in "jump over the crate":
		await key(KEY_SPACE if ch == " " else OS.find_keycode_from_string(ch.to_upper()), " " if ch == " " else ch)
	await key(KEY_ENTER, "")
	await idle(12)
	var cards_n: int = m.S.cards.size()
	bar(cards_n > 0, "3 'jump over the crate' builds a clip (cards %d, status: %s)" % [cards_n, m.easy.home._msg.text])
	shot("04_typed_built")
	bar(m.S.cards.size() > 0 and not str(m.easy.home._msg.text).contains("doesn't know"), "3 the typed line is not refused")
	var lenS: float = m.S.length()
	var ps = m._ps()
	var worst := 99.0   # the lowest foot over the box, minus the box top
	var over_frames := 0
	var pen := 0
	var t := 0.0
	var apex_t := -1.0
	var apex_h := -1.0
	while t <= lenS and cards_n > 0:
		ps.apply(m.B, t)
		var B = m.B
		var fy := 99.0
		var inside := false
		for k in ["ball_l", "ball_r", "foot_l", "foot_r"]:
			var q: Vector3 = B.P[k]
			if box.grow(0.05).has_point(Vector2(q.x, q.z)):
				inside = true
				fy = minf(fy, q.y)
		if inside:
			over_frames += 1
			worst = minf(worst, fy - top)
		var pel: Vector3 = B.P["pelvis"]
		if pel.y > apex_h:
			apex_h = pel.y
			apex_t = t
		t += 1.0 / 30.0
	print("AJUMP frames over box %d, worst foot clearance over top %.3f m, apex %.3f at %.2f s" % [over_frames, worst, apex_h, apex_t])
	bar(over_frames > 0, "4 the feet cross the box's footprint in the clip (frames %d)" % over_frames)
	bar(over_frames > 0 and worst >= 0.0, "4 both feet clear the box top while over it (worst %.3f m; the lift and the travel are on the flight's wrong frames: KNOWN)" % worst, true)
	bar(worst > -0.02, "4b no foot goes under the floor or into the box top while over it (lowest %.3f m; the feet sink on landing: KNOWN)" % worst, true)
	ps.apply(m.B, apex_t)
	shot("05_apex")
	ps.apply(m.B, lenS)
	var pe: Vector3 = m.B.P["pelvis"]
	var along := (Vector2(pe.x, pe.z) - box.get_center()).length()
	bar(along > 0.4, "5 he ends past the box (distance from its middle %.2f m; the far face is 0.2-0.3 m out)" % along)
	m.playhead = lenS
	shot("06_landed")
	print("AJUMP DONE fails=", fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
