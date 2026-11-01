extends SceneTree
## godot --path . -s tests/s134_test.gd   (AJUMP: a beginner jumps over a box in Easy, real clicks from the start screen, 1280x720)
const OUT := "C:/Temp/claude/s134/"
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



func type_line(s: String) -> void:
	var edit := m.easy.home.panel.find_child("eh_text", true, false) as LineEdit
	await click(edit)
	edit.text = ""
	for ch in s:
		await key(KEY_SPACE if ch == " " else OS.find_keycode_from_string(ch.to_upper()), " " if ch == " " else ch)
	await key(KEY_ENTER, "")
	await idle(14)


func prop_idx(kind: String) -> int:
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]) == kind:
			return i
	return -1


func card_time(k: int) -> float:
	return float(m.S.times()[k][1])


func at(t: float) -> void:
	m._ps().apply(m.B, t)


func clear_scene() -> void:
	while m.undo.size() > 0:
		m._undo()
		await idle(2)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.get_window().size = SIZE
	await idle(10)
	m.start_screen.show_screen(true)
	await idle(10)
	var eb: Button = m.start_screen.find_child("easy_animation", true, false)
	await click(eb)
	await idle(10)
	bar(m.easy.on, "0 Easy is on")

	# ---- pick up the box
	m._prop_add("box", Vector3(0.3, 0.0, 1.6))
	await idle(6)
	var bi := prop_idx("box")
	var box0: Vector3 = (m.S.props[bi]["xf"] as Transform3D).origin
	var u0: int = m.undo.size()
	await type_line("pick up the box")
	bar(m.S.cards.size() >= 4, "1 'pick up the box' builds a clip (cards %d; status: %s)" % [m.S.cards.size(), m.ui_status.text])
	bar(m.undo.size() == u0 + 1, "1b one undo step for the typed move (undo %d -> %d)" % [u0, m.undo.size()])
	shot("01_pick_built")
	var tk := -1
	for k in m.S.cards.size():
		if m.S.cards[k].has("take"):
			tk = k
	bar(tk >= 0, "2 a card makes the hand take hold of the box (card %d)" % tk)
	var tg := card_time(tk) if tk >= 0 else 0.0
	at(tg)
	var gp: Dictionary = PropMove.grip_point(m.S.props[bi], Vector3(0, 0, 0))
	var hand: Vector3 = m.B.P["hand_r"]
	var dg := hand.distance_to(gp["pt"])
	bar(dg <= 0.03, "3 at the grip frame the right hand is %.1f mm from the box's grip point (bar 30 mm)" % (dg * 1000.0))
	var surf := 9.0
	for sw in Props.solids(m.S.props[bi]):
		surf = minf(surf, Props._sd(sw, hand))
	bar(surf < 0.05, "3b independent: the wrist is %.1f cm from the box's surface (bar 5 cm)" % (surf * 100.0))
	shot("02_grip")
	# the box follows the hand: distance constant over the next 10 frames (and to the end)
	var d0 := -1.0
	var worst := 0.0
	var tt := tg + 0.0001
	var nfr := 0
	while tt <= m.S.length() + 0.001:
		at(tt)
		var pa: Array = m.S.props_at(tt, m.B)
		var d: float = (pa[bi]["xf"] as Transform3D).origin.distance_to(m.B.P["hand_r"])
		if d0 < 0.0:
			d0 = d
		worst = maxf(worst, absf(d - d0))
		nfr += 1
		tt += 1.0 / 30.0
	bar(nfr >= 10 and worst <= 0.01, "4 the box stays %.1f cm from the hand over %d frames to the end of the clip (drift %.2f mm, bar 10 mm)" % [d0 * 100.0, nfr, worst * 1000.0])
	at(m.S.length())
	var boxend: Vector3 = (m.S.props_at(m.S.length(), m.B)[bi]["xf"] as Transform3D).origin
	bar(boxend.y - box0.y > 0.4, "5 the box is lifted %.0f cm off the floor-spot by the end" % ((boxend.y - box0.y) * 100.0))
	shot("03_lifted")
	var n_after: int = m.S.cards.size()
	m._undo()
	await idle(4)
	bar(m.S.cards.size() == 0 and m.undo.size() == u0, "6 one Undo takes the whole typed move back (cards %d, undo %d)" % [m.S.cards.size(), m.undo.size()])

	# ---- missing / unknown props
	var c0: int = m.S.cards.size()
	var u1: int = m.undo.size()
	await type_line("pick up the banana")
	bar(m.S.cards.size() == c0 and m.undo.size() == u1 and str(m.ui_status.text).contains("no banana"), "7 'pick up the banana': plain words, no cards (said: %s)" % m.ui_status.text)
	await type_line("throw the ball")
	bar(m.S.cards.size() == c0 and m.undo.size() == u1 and str(m.ui_status.text).contains("no ball"), "7b 'throw the ball' with no ball: plain words, no cards (said: %s)" % m.ui_status.text)
	await type_line("pick up the sword")
	bar(m.S.cards.size() == c0 and str(m.ui_status.text).contains("no sword"), "7c 'pick up the sword' with none: said (%s)" % m.ui_status.text)

	# ---- throw the ball
	m._prop_add("ball", Vector3(-0.4, 0.0, 1.3))
	await idle(6)
	var li := prop_idx("ball")
	var u2: int = m.undo.size()
	await type_line("throw the ball")
	bar(m.S.cards.size() >= 5 and m.undo.size() == u2 + 1, "8 'throw the ball' builds a clip in one undo step (cards %d, undo %d -> %d; %s)" % [m.S.cards.size(), u2, m.undo.size(), m.ui_status.text])
	var dk := -1
	for k in m.S.cards.size():
		if String(m.S.cards[k]["name"]).begins_with("let go"):
			dk = k
	bar(dk >= 0 and Props.animated(m.S.props[li]), "9 a card lets go of the ball (card %d) and the ball is keyed in flight (%d keys)" % [dk, (m.S.props[li].get("keys", []) as Array).size()])
	if dk >= 0:
		var td := card_time(dk)
		at(td)
		var hand_rel: Vector3 = m.B.P["hand_r"]
		var ball_t0: Vector3 = (m.S.props_at(td - 0.0001, m.B)[li]["xf"] as Transform3D).origin
		print("S134 hand at release ", hand_rel, " ball just before ", ball_t0)
		var le: float = m.S.length()
		at(le)
		var ball_e: Vector3 = (m.S.props_at(le, m.B)[li]["xf"] as Transform3D).origin
		var travel := Vector2(ball_e.x - hand_rel.x, ball_e.z - hand_rel.z).length()
		bar(travel >= 1.0, "10 the ball leaves the hand and ends %.2f m away on the floor (bar 1 m; ends at %s)" % [travel, ball_e])
		shot("04_thrown")
	await clear_scene()

	# ---- open the door
	m._prop_add("door", Vector3(-0.3, 0.0, 2.2))
	await idle(6)
	var di := prop_idx("door")
	var u3: int = m.undo.size()
	await type_line("open the door")
	bar(m.S.cards.size() >= 3 and m.undo.size() == u3 + 1, "11 'open the door' builds a clip in one undo step (cards %d; %s)" % [m.S.cards.size(), m.ui_status.text])
	var le2: float = m.S.length()
	at(le2)
	var pd: Dictionary = Props.posed(m.S.props[di], le2)
	var sw_end := float(pd.get("swing", 0.0))
	var hp: Vector3 = PropMove.grip_point(pd, Vector3(0, 0, 0))["pt"]
	var dh: float = (m.B.P["hand_r"] as Vector3).distance_to(hp)
	bar(absf(sw_end) >= 20.0, "12 the door is open %.0f degrees at the end (bar 20)" % sw_end)
	bar(dh <= 0.03, "13 the right hand is %.1f mm from the open door's handle at the end (bar 30 mm)" % (dh * 1000.0))
	shot("05_door")
	print("s134: %d fail" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
