## godot --path . -s tests/animwalk_test.gd     (ANIMWALK: a beginner animates a punch in EASY, typed moves + the timeline; real clicks; 1280x720)
## Starts at the REAL start screen (no boot-skip): ANIMATION's Easy button (a real click), then only what Easy shows.
## 1 start   the start screen opens, its ANIMATION Easy button is clicked, Easy home shows the typed box and the move buttons
## 2 type    "punch with the right hand" typed + Enter: a clip is built; the RIGHT hand goes forward > 0.30 m, the left < half of it
## 3 scrub   the time slider (the Easy timeline, eh_scrub) dragged to the middle of the clip: the playhead follows it within 0.05 s,
##           and the body poses there (right hand within 2 cm of the sampled pose at that time)
## 4 type    "then punch with the left hand" after "Change it": the LEFT hand goes forward > 0.30 m in the new part, the right < half of it
## 5 undo    one Undo takes back the left punch only: the clip is back to the one-punch length and card count
## Prints PASS/FAIL per bar and FRICTION lines (what a beginner hit). Exit 0 if every bar passes, 1 otherwise.
## Shots: C:/Temp/claude/animwalk/animwalk_<n>.png. Only user:// is written (the video folder).
extends SceneTree

const OUT := "C:/Temp/claude/animwalk/"

var m: Node
var fails := 0
var clicks := 0
var notes: Array = []
var goal := ""


func bar(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		fails += 1


func say(s: String) -> void:
	print(s)


func note(s: String) -> void:
	notes.append("[%s] %s" % [goal, s])
	print("   FRICTION: " + s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func visible_nodes() -> Array:
	var out := []
	for n in walk(root, []):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in visible_nodes():
		if n is Button:
			out.append(n)
	return out


func btn_names() -> String:
	var out := []
	for b in visible_buttons():
		if (b as Button).text != "":
			out.append((b as Button).text)
	return str(out)


## a button by the words on it: its own text, or a Label inside it (Easy's buttons are a Button with a Label)
func find_btn(txt: String) -> Control:
	for b in visible_buttons():
		if (b as Button).text.strip_edges() == txt:
			return b
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() == txt:
			var p: Node = n
			while p != null and not (p is Button):
				p = p.get_parent()
			return p if p != null else n
	return null


func mouse_at(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


## a real click on a Control: hover, press, release at its centre; COVERED is noted if another control is on top
func click_ctl(c: Control) -> bool:
	var p := c.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame
	var under := root.get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		note("COVERED: the click on '%s' at %s lands on %s" % [str(c.name), str(p), str(under.name) if under != null else "nothing"])
	mouse_at(p, true)
	await process_frame
	mouse_at(p, false)
	await idle(3)
	return inside


func click_text(txt: String) -> bool:
	var b := find_btn(txt)
	if b == null:
		note("NOT VISIBLE: no button reads '%s' (visible: %s)" % [txt, btn_names()])
		return false
	clicks += 1
	say("   click '%s' (tooltip: '%s')" % [txt, b.tooltip_text if b is BaseButton else ""])
	return await click_ctl(b)


func press_key(kc: Key, ctrl := false) -> void:
	var kd := InputEventKey.new()
	kd.keycode = kc
	kd.physical_keycode = kc
	kd.ctrl_pressed = ctrl
	kd.pressed = true
	root.push_input(kd)
	await process_frame
	var ku := InputEventKey.new()
	ku.keycode = kc
	ku.physical_keycode = kc
	ku.ctrl_pressed = ctrl
	ku.pressed = false
	root.push_input(ku)
	await process_frame


func type_text(s: String, enter := false) -> void:
	for c in s:
		var kd := InputEventKey.new()
		kd.keycode = (KEY_SPACE if c == " " else c.to_upper().unicode_at(0)) as Key
		kd.unicode = c.unicode_at(0)
		kd.pressed = true
		root.push_input(kd)
		await process_frame
		var ku := InputEventKey.new()
		ku.keycode = kd.keycode
		ku.unicode = kd.unicode
		ku.pressed = false
		root.push_input(ku)
		await process_frame
	if enter:
		var ke := InputEventKey.new()
		ke.keycode = KEY_ENTER
		ke.pressed = true
		root.push_input(ke)
		await process_frame
		ke.pressed = false
		root.push_input(ke)
		await process_frame


func box() -> LineEdit:
	for n in visible_nodes():
		if n is LineEdit and (n as LineEdit).placeholder_text.begins_with("or type"):
			return n
	return null


## types a move into Easy's box and presses Enter. After a clip is built the box is hidden: "Change it" brings it back.
func type_move(s: String) -> bool:
	var bx := box()
	if bx == null:
		note("the typed box is hidden after the last move: the beginner must press 'Change it' first (visible: %s)" % btn_names())
		if not await click_text("Change it"):
			return false
		await idle(10)
		bx = box()
		if bx == null:
			note("NOT VISIBLE: no typed box after 'Change it'")
			return false
	clicks += 1
	await click_ctl(bx)
	if bx.text != "":
		note("the box still says '%s' after 'Change it': a beginner must select and delete it" % bx.text)
		await press_key(KEY_A, true)
		await press_key(KEY_BACKSPACE)
	say("   type '%s' + Enter" % s)
	await type_text(s, true)
	await idle(20)
	return true


func wait_for_cond(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await process_frame
	return false


func settle(limit := 2400) -> void:
	for i in 120:
		if m.playing and m.playhead > 0.0:
			break
		await process_frame
	for i in limit:
		if not m.playing:
			break
		await process_frame
	await idle(5)


func mid(part: String) -> Vector3:
	var c: Array = m.B.cap(part)
	return (c[0] + c[1]) * 0.5 if c.size() >= 2 else Vector3.ZERO


func face_now() -> Vector3:
	var f := Vector3.ZERO
	for part in ["foot_l", "foot_r"]:
		var c: Array = m.B.cap(part)
		var d: Vector3 = c[1] - c[0]
		d.y = 0.0
		f += d
	return f.normalized()


## the body at time t of the clip, read and put back exactly as it was
func pose_at(t: float) -> Dictionary:
	var keep: Dictionary = m.B.state()
	m._ps().apply(m.B, t)
	var r := {"hl": mid("hand_l"), "hr": mid("hand_r"), "face": face_now()}
	m.B.set_state(keep)
	return r


## how far a hand went forward (along the facing at t0) over [t0, t1]
func forward_reach(t0: float, t1: float, hand: String) -> float:
	var p0: Dictionary = pose_at(t0)
	var f: Vector3 = p0["face"]
	var h0: Vector3 = p0[hand]
	var best := -INF
	for i in 60:
		var q: Dictionary = pose_at(lerpf(t0, t1, float(i) / 59.0))
		best = maxf(best, ((q[hand] as Vector3) - h0).dot(f))
	return best


func shot(n: String) -> void:
	say("   shot %s begins (frame %d, clip %.2f s, %d cards, playing %s)" % [n, Engine.get_process_frames(), m.S.length(), m.S.cards.size(), str(m.playing)])
	await idle(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "animwalk_%s.png" % n)
	say("   screenshot %s (frame %d, clip %.2f s, %d cards, playing %s)" % [OUT + "animwalk_" + n + ".png", Engine.get_process_frames(), m.S.length(), m.S.cards.size(), str(m.playing)])
	say("   visible buttons: %s" % btn_names())


func start_goal(s: String) -> void:
	goal = s
	clicks = 0
	say("\n== %s ==" % s)


func finish(ok: bool, what: String) -> void:
	var fr := (not ok) or notes.size() > 0
	say("%s: %s - %s (clicks %d)" % [goal, "FRICTION" if fr else "PASS", what, clicks])
	bar(ok, "%s: %s" % [goal, what])
	notes.clear()


func _init() -> void:
	EasyMode.start_fresh = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.start_screen.show_screen(true)
	await idle(10)

	# 1. the real start screen: ANIMATION's Easy button (the first visible "Easy" is ANIMATION's; Modeling has no Easy)
	start_goal("GOAL 1: start screen -> ANIMATION Easy")
	var ss_up: bool = m.start_screen.visible
	await click_text("Easy")
	await idle(20)
	var on_home: bool = box() != null and find_btn("Walk") != null and find_btn("Punch") != null
	await shot("1_easy")
	finish(ss_up and on_home and not m.start_screen.visible, "start screen shown %s, Easy home with the typed box and 'Walk' %s" % [str(ss_up), str(on_home)])

	# 2. type a punch with the right hand
	start_goal("GOAL 2: type 'punch with the right hand'")
	var c2: int = m.S.cards.size()
	await type_move("punch with the right hand")
	var built2 := await wait_for_cond(func(): return m.S.cards.size() != c2, 400)
	await settle()
	var L2: float = m.S.length()
	var rr2 := forward_reach(0.0, L2, "hr") if built2 else 0.0
	var lr2 := forward_reach(0.0, L2, "hl") if built2 else 0.0
	say("   clip %.2f s, %d cards | right hand forward %.3f m, left %.3f m" % [L2, m.S.cards.size(), rr2, lr2])
	await shot("2_punch_right")
	if built2 and rr2 <= 0.30:
		note("the typed right punch takes the right hand forward only %.3f m" % rr2)
	finish(built2 and rr2 > 0.30 and lr2 < 0.5 * rr2, "right hand forward %.3f m, left %.3f m, clip %.2f s" % [rr2, lr2, L2])

	# 3. the time slider (the Easy timeline) to the middle of the punch
	start_goal("GOAL 3: drag the time slider to the middle of the clip")
	var sl: HSlider = null
	for n in walk(root, []):
		if n is HSlider and n.name == "eh_scrub" and (n as Control).is_visible_in_tree():
			sl = n
	var ok3 := false
	var why3 := "no visible time slider 'eh_scrub'"
	if sl != null:
		var r := sl.get_global_rect()
		var x0 := r.position.x + r.size.x * 0.02
		var x1 := r.position.x + r.size.x * 0.5
		say("   slider %s, value %.3f of %.3f, dragging to 50%%" % [str(r), sl.value, sl.max_value])
		mouse_at(Vector2(x0, r.get_center().y), true)
		await process_frame
		for i in 10:
			var hm := InputEventMouseMotion.new()
			hm.position = Vector2(lerpf(x0, x1, float(i + 1) / 10.0), r.get_center().y)
			hm.global_position = hm.position
			hm.button_mask = MOUSE_BUTTON_MASK_LEFT
			root.push_input(hm)
			await process_frame
		mouse_at(Vector2(x1, r.get_center().y), false)
		await idle(10)
		var t3: float = m.playhead
		var want: float = sl.value / maxf(sl.max_value, 0.001) * L2
		var P := pose_at(t3)
		var d3: float = (mid("hand_r") - (P["hr"] as Vector3)).length()
		say("   playhead %.3f s (slider says %.3f s) | right hand off the sampled pose by %.3f m" % [t3, want, d3])
		await shot("3_scrub")
		if absf(t3 - want) > 0.05:
			note("the slider reads %.2f s but the playhead is at %.2f s" % [want, t3])
		else:
			ok3 = d3 < 0.02
			why3 = "playhead %.3f s, hand off by %.3f m" % [t3, d3]
	else:
		note("no time slider on screen after the punch (visible: %s)" % btn_names())
	finish(ok3, why3)

	# 4. type the left punch after the right one
	start_goal("GOAL 4: type 'then punch with the left hand'")
	var L4pre: float = m.S.length()
	var c4: int = m.S.cards.size()
	await type_move("then punch with the left hand")
	var built4 := await wait_for_cond(func(): return m.S.cards.size() != c4, 400)
	await settle()
	var L4: float = m.S.length()
	var lf4 := forward_reach(L4pre, L4, "hl") if built4 else 0.0
	var rf4 := forward_reach(L4pre, L4, "hr") if built4 else 0.0
	say("   clip %.2f s -> %.2f s, %d cards | new part: left hand forward %.3f m, right %.3f m" % [L4pre, L4, m.S.cards.size(), lf4, rf4])
	await shot("4_punch_left")
	if built4 and lf4 <= 0.30:
		note("the new 'punch with the left hand' takes the left hand forward only %.3f m" % lf4)
	finish(built4 and lf4 > 0.30 and rf4 < 0.5 * lf4, "left hand forward %.3f m, right %.3f m, clip %.2f s -> %.2f s" % [lf4, rf4, L4pre, L4])

	# 5. one Undo takes back the left punch only
	start_goal("GOAL 5: Undo once takes back the left punch")
	await click_text("Undo")
	await settle()
	var L5: float = m.S.length()
	var c5: int = m.S.cards.size()
	say("   after one Undo: clip %.2f s, %d cards (before the left punch: %.2f s, %d cards)" % [L5, c5, L4pre, c4])
	await shot("5_undo")
	if absf(L5 - L4pre) > 0.02 or c5 != c4:
		note("one Undo gives %.2f s / %d cards, not the clip before the left punch (%.2f s / %d cards)" % [L5, c5, L4pre, c4])
	finish(absf(L5 - L4pre) <= 0.02 and c5 == c4, "one Undo: %.2f s / %d cards" % [L5, c5])

	print("\nANIMWALK: %s (%d failed bars)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)
