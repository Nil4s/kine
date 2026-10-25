## godot --path . -s tests/easyhome_test.gd     (EASY HOME, "monkey brain easy": the empty scene's picture panel; needs a window)
## BARS (stated before measuring):
##  1. Easy with an empty scene shows the "What should he do?" panel (8 picture cards and the text box); Expert shows none.
##  2. Every card builds a non-empty clip that plays (walk, run, jump, punch, sit down, wave from templates/; kick = "roundhouse" by
##     TextBlocking). Fall builds too (the fall template: a backward breakfall).
##  3. The click -> the first frame the clip plays is under 2000 ms for each card that builds (the builder time is printed).
##  4. One Ctrl+Z after a card gives back the empty scene (one undo step per card).
##  5. Typing "jab then cross" builds 2 strikes (the cards are the two single strikes, in order).
##  5b. Typing "walk", "jump", "walk then wave", "jump then kick", "sit down then fall" in the box builds >= 2 cards, no "can't build".
##  5c. Typing "dance" builds nothing, and its sentence names the cards' moves (never one Kine cannot build).
##  6. The panel fits inside the window at 1280x720 (its rect is inside the visible viewport).
##  8. The Library opened over the empty scene hides the panel; Close brings it back.
##  7. Every card that builds: its click to the first moving frame is under 500 ms (the Kick card built live took 3.6 s; baked it is a file).
##  11. CHAIN: with a walk built, Change it and a card (Add after, the default) keeps the walk and adds the wave after it:
##     cards = walk + wave, the walk first; Undo takes the add back in one step; Start over replaces the clip.
##  14. SIT ON A CHAIR, VIEW BUTTONS: a placed chair shows "Sit on it"; the click or typed "sit on the chair" seats him on it; Front / Side / Back turn the view.
##  15. EDIT A PICKED CARD: a card picked on the strip, the body dragged: that card takes the pose (one undo step, "Change pose");
##      the count and the other cards stay; moving the pick off keeps the edit; Ctrl+Z puts the card's pose back.
##  16. HELP IN EASY: a visible Help button (the panel and the strip) opens the help text and the tour button; Help again hides it.
##  17. A typed question ('how do I make him jump') names the move to type, or gives the help line; never "doesn't know".
##  18. After a typed move is used the box is empty; a failed line keeps its words, and Change it selects them.
##  19-23. Slower on a 10.3 s clip; the saved video named after the clip; the saved-video message goes at the next action; the scene save says where; one Then row.
##  C. (the layout) At 1280x720 and at 1600x900 the home panel covers at most 15 % of the body's screen box (the body's capsule
##     ends projected with m.cam.unproject_position): the body is visible beside the panel, not under it.
##  24. HELD SWORD THROUGH A TYPED SWING (walk-through LP round, goal 2): a sword in the right hand, typed 'swing': every card
##      the build makes keeps the sword in the same hand (B.wep_on, wep_kind sword, wep_hand hand_r; each card's pose has a weapon).
##  25. BALL NEAR THE FOOT, THEN A KICK (walk-through LP round, goal 3): a football on the floor, typed 'kick': the kick's foot reaches
##      the ball (the closest toe is within 6 cm of its surface), the ball is not moved, and the say line says the ball doesn't fly yet.
##  26. LIBRARY NAMES ARE PLAIN (walk-through LP round, goal 3): no library tile is named with the old jargon (Step code, Stairs code,
##      Ramp15, Moving box, Door frame, Sword on the floor); the prop sword says (on the floor).
##  27. THE PROP BAR (walk-through round 6, goals 1 and 2): a prop placed through the Library, picked by a real click in the view,
##     shows Remove on the bar at the top right; Remove takes it out in one undo step; Ctrl+Z brings it back; the Delete key does the same;
##     Turn right turns it; no visible text in Easy says "SET"; Next object reaches a prop that is not picked.
##  28. From a video: a visible button on the empty panel and on the copied clip's strip, the same action as More > Copy a video.
##  29. Trim: Cut start / Cut end drop the cards before / after the picked card; one undo step each; Ctrl+Z restores; the clip plays.
##  30. Smoother: a visible button; mean per-frame hand acceleration goes down; one undo step; Ctrl+Z restores; the status says so.
##  31. No red contact tint (pick_touch) in Easy on a typed clip or a copied clip (Expert keeps it).
##  40. A SECOND COPY IS REFUSED ON SCREEN (walk-through friction 1): while one video is copied, a second copy's refusal is not
##      overwritten: one second after it, the bar's line reads "Still copying the first video: ..."
##  41. AN UNSAVED SCENE IS ASKED ABOUT (walk-through friction 2): a copy over built cards asks "Replace your clip?" first;
##      Cancel keeps the scene untouched (same cards, same file, no copy started); Add after keeps the cards and adds the copy's
##      after them (one undo step, the scene's file does not change). The question is screenshotted (easy_vid_ask.png).
##  42. COPIED CARDS ARE NAMED PLAINLY (walk-through friction 3): every card of a copy reads "Video <n>" in Easy (n = its place
##      in the copy's run); no "v<frame>", "Pose <n>" or "Move <n>" names for copied cards.
##  45. BIGGER / SMALLER / COLOUR (library walk-through goal 6): a picked chair in Easy: Bigger makes its box grow, Smaller shrinks it,
##      Colour sets its material colour and the status names it; each is one undo step; Ctrl+Z restores; the scene saves and reloads
##      with the size and the colour.
##  50. THE STRIP STAYS (walk-through round 7, goal 2): with a clip built, an unknown typed line leaves the strip on screen (the panel
##      stays shut) and the refusal goes to the status line.
##  51. STAND UP (round 7, goal 2): a sat-down body typed "stand up then wave" builds cards; the wave is last, the stand-up cards
##      come from the sit reversed: the body ends standing (pelvis back within 4 cm of its standing height), not seated.
##  52. THEN STAND UP: after a sit the Then row offers "Then stand up" first, and its press builds the stand-up move.
##  105. A REFUSED LINE IS SELECTED (round 8, friction 3): "dance" refused, the box selected; typed "punch" builds a punch, no "dance" in the cards.
##  106. THE REFUSAL OFFERS THE CLOSEST MOVES (round 8, friction 5): "sit dwn" refused; >= 3 try buttons, Sit down first; its press builds the sit down.
##  53. UNDO IN EASY: a 3-step sequence (Walk, Then wave, Bigger): each Undo changes the card list (count or the cards' poses), and
##      the status names the step it took back. Old code: the first Undo here took the same step, unnamed by the strip.
##  70. SIT AFTER A WALK (walk-through round 7, goal 1): a chair placed, a walk built, nothing picked (as after Library Close): the strip
##      offers ONE "Sit on the chair"; its press adds the sit after the walk (one undo step); the body ends seated (pelvis >= 0.2 m lower
##      than standing). Old code: no sit button on the strip unless a chair is picked.
##  71. THE PROP BAR, NOTHING PICKED (round 7, goal 4): a prop in the scene and none picked: the bar says how to pick it ("Click an object
##      to pick it", with Remove named), so a beginner sees how the chair comes out. Old code: "Nothing picked".
##  72. LIBRARY CAPTIONS (round 7, friction 3): the Furniture tab is one category: no tile repeats "Furniture" as a caption under or
##      over its name (the placeholder node stays: B14 of library_test needs it, with no text).
##  73. SIT AFTER A PICKED CARD (round 7, goal 1): a card picked in the middle of the walk, then "Sit on the chair": the sit still goes
##      after the LAST card (the clip's end), not after the picked card.
##  75. THE SCRUB (walk-through: "no scrubber in Easy"): an empty scene hides the slider "eh_scrub"; a built walk shows it in the strip.
##  76. DRAG TO THE MIDDLE: a real press at the slider's middle while the walk plays stops the play and poses the body at half the
##      clip (the pelvis is where _ps().apply(B, half) puts it, and not at the start).
##  77. PLAYING MOVES IT: while the clip plays the slider follows the playhead (its value moves, it matches the playhead).
##  78. THE LABEL: "eh_scrub_time" reads "<t> s / <len> s" (t follows the slider; len is the clip's length).
##  79. THE GRAB AREA: the slider is at least 28 px tall (global rect) at 1280x720.
##  85. WALK TO THE CHAIR AND SIT (round 8, goal 1): a walk built, a chair 2 m past where it ends, the strip's "Sit on the chair":
##      the root's horizontal path is continuous over the whole clip (no frame-to-frame jump > 0.15 m, sampled every 1/30 s).
##  86. the clip ends seated: the pelvis within 0.15 m of the seat horizontally and >= 0.2 m below standing.
##  87. one Undo takes the whole walk-and-sit back to the walk's card count.
## A screenshot of the panel goes to user://easyhome_panel.png (the path is printed).
extends SceneTree

var FIX: String = ProjectSettings.globalize_path("res://tests/data/see_video_crop_small.mp4")   # this checkout's own copy (a path into another worktree broke when it was removed)
const BUILDS := [0, 1, 2, 3, 4, 5, 6, 7]   # the cards that build: walk, run, jump, punch, kick, sit down, wave, fall
const BAR_MS := 2000
const FAST_MS := 500     # bar 7: every card's click to its first moving frame (a beginner thinks a slower one froze)

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## the clip plays: wait (up to a bound) until the body has moved from the start
func wait_playing(limit := 120) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


## the closest distance (m, on the floor) from either toe ball (the body's own solve, Scene.put on a scratch body) to the
## point p, over the cards; the bars of section 25 read it
func toe_gap(cards: Array, p: Vector3) -> float:
	var W := Body.new()
	W.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var best := INF
	for c in cards:
		Scene.put(W, Moves._flat(c["pose"]))
		W.fk()
		for sd in ["_l", "_r"]:
			var t: Vector3 = W.P["ball" + sd]
			best = minf(best, Vector2(t.x - p.x, t.z - p.z).length())
	return best


## the body's screen box: each capsule end (Turntable.points: the joints and their ends, the weapons) projected by m.cam, grown
## by its radius in px (the same px-per-metre as the Easy framing: 2 d tan(fov/2) / view height)
func body_box() -> Rect2:
	var cam: Camera3D = m.cam
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var mpp: float = 2.0 * float(m.dist) * tan(deg_to_rad(cam.fov * 0.5)) / vs.y
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in Turntable.points(m.B):
		if cam.is_position_behind(p[0]):
			continue
		var q := cam.unproject_position(p[0])
		var r: float = float(p[1]) / mpp
		lo = lo.min(q - Vector2(r, r))
		hi = hi.max(q + Vector2(r, r))
	return Rect2(lo, hi - lo) if lo.x < INF else Rect2()


## the picked prop (a chair) under the hips: [the pelvis's middle is over its seat, the hips' lowest surface over the seat minus
## the seat's top] (the same measure as use_set_test's sit: Body.SEAT_PARTS, Props._over)
func seat_gap() -> Array:
	var p: Dictionary = m.S.props[m.sel_prop]
	var sup: Dictionary = Props.supports(p)[0]
	var top: float = sup["y"]
	var B: Body = m.B
	var mid: Vector3 = (B.cap("pelvis")[0] + B.cap("pelvis")[1]) * 0.5
	var lo := INF
	for part in Body.SEAT_PARTS:
		var c = B.cap(part)
		for k in 41:
			var q: Vector3 = (c[0] as Vector3).lerp(c[1], k / 40.0)
			if Props._over(sup, q):
				lo = minf(lo, q.y - float(B.rad[part]))
	return [Props._over(sup, mid), lo - top]


## a wait by the clock (frames run in the window; a copy's tracker takes seconds)
func wait_ms(ms: int) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms:
		await process_frame


## wait while a copy runs (the copy's own flag), up to ms
func wait_busy(h: Node, ms: int) -> void:
	var t := Time.get_ticks_msec()
	while h._vid_busy and Time.get_ticks_msec() - t < ms:
		await process_frame


func card_btn(i: int) -> Button:
	return m.easy.home.panel.find_child("eh_card_%d" % i, true, false) as Button


## the strip's picture button of card i (0-based): the pick button inside its card's panel
func pick_btn(i: int) -> Control:
	var pc: Node = m.ui_cards.get_node_or_null("card_%d" % (i + 1))
	return pc.find_child("b_pick", true, false) as Control if pc != null else null


## a real click on a Control (the mouse goes down and up on its middle, through the viewport's input)
func click_ctl(c: Control) -> void:
	var at: Vector2 = c.get_global_rect().get_center()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle(1)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	root.push_input(u)
	await idle(4)


## a real click at a point of the view (the 3D pick: the press and the release go through the viewport's input)
func click_at(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle(1)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	root.push_input(u)
	await idle(4)


## a key press (with Ctrl or not) through the viewport's input
func key_press(code: int, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	root.push_input(e)
	await idle(4)


## the text of every visible Label and Button under a node (the tooltips too)
func visible_texts(n: Node, out: Array) -> Array:
	if n is Control and not (n as Control).is_visible_in_tree():
		return out
	if n is Label or n is Button:
		out.append(String((n as Object).get("text")))
		out.append(String((n as Control).tooltip_text))
	for c in n.get_children():
		visible_texts(c, out)
	return out


## a real drag of one part on the body: the pointer goes to the part, down, six moves, up at the end of d
func drag_part(j: String, d: Vector2) -> void:
	var c: Array = m.B.cap(j)
	var p: Vector2 = m.cam.unproject_position(c[0].lerp(c[1], 0.75))
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await idle(2)
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.position = p
	dn.global_position = p
	dn.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(dn)
	await process_frame
	var st := d / 6.0
	for i in 6:
		var mm := InputEventMouseMotion.new()
		mm.position = p + st * (i + 1)
		mm.global_position = mm.position
		mm.relative = st
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p + d
	up.global_position = p + d
	root.push_input(up)
	await idle(3)



## the mean per-frame acceleration of both hands (m/frame^2) over the built clip at 30 frames a second (the walk driver's sampling)
func hand_accel() -> float:
	var ps = m._ps()
	var n := int(ceil(m.S.length() * 30.0))
	var hp: Array = []
	for i in n + 1:
		m.playhead = float(i) / 30.0
		ps.apply(m.B, ps.play_t(m.playhead))
		await idle(1)
		var hr: Array = m.B.cap("hand_r")
		var hl: Array = m.B.cap("hand_l")
		hp.append([(hr[0] + hr[1]) * 0.5, (hl[0] + hl[1]) * 0.5])
	var tot := 0.0
	var cnt := 0
	for i in range(2, hp.size()):
		for h in 2:
			tot += ((hp[i][h] - 2.0 * hp[i - 1][h] + hp[i - 2][h]) as Vector3).length()
			cnt += 1
	return tot / maxf(1.0, float(cnt))


## frames (of 6 across the clip) on which a body part is drawn in the contact (touch) red
func red_frames() -> int:
	var ps = m._ps()
	var L: float = m.S.length()
	var hits := 0
	for k in 6:
		m.playhead = L * (float(k) + 0.5) / 6.0
		ps.apply(m.B, ps.play_t(m.playhead))
		m._refresh()
		await idle(3)
		if _has_red():
			hits += 1
	return hits


func _has_red() -> bool:
	for j in Body.ORDER:
		var c: Color = m.skin_col(j)
		if c.a > 0.05 and c.r > 0.9 and c.g < 0.45 and c.b < 0.45:
			return true
	return false


## red_frames for a copied clip (the scene is played from its start, the samples read as it goes)
func red_while_playing() -> int:
	var hits := 0
	for k in 6:
		m.playhead = m.S.length() * (float(k) + 0.5) / 6.0
		m._refresh()
		await idle(3)
		if _has_red():
			hits += 1
	return hits


## the copy runs in the background: wait (up to a bound) until Easy says it is over
## the world box of a prop's solids (its own boxes, corners through each solid's transform): the size the bars read
func prop_box(p: Dictionary) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for sw in Props.solids(p):
		var X: Transform3D = sw["xf"]
		var h: Vector3 = sw["half"]
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var c: Vector3 = X * Vector3(sx * h.x, sy * h.y, sz * h.z)
					lo = lo.min(c)
					hi = hi.max(c)
	return AABB(lo, hi - lo)


func wait_copy(limit := 3000) -> bool:
	# a CLOCK limit (limit frames at 60 fps, at least 3 minutes): headless frames run unthrottled, so 4000 frames could end before a
	# 14 s tracker read + 7 s fit (bars 28-30 failed with 0 cards whenever the frames ran fast)
	var seen := false
	var t0 := Time.get_ticks_msec()
	var cap: int = maxi(limit * 1000 / 60, 180000)
	while Time.get_ticks_msec() - t0 < cap:
		if String(m.ui_status.text).contains("%"):
			seen = true
		if not m.easy.home._vid_busy:
			return seen
		await process_frame
	return seen


## the pelvis height (m): the middle of the pelvis capsule (walk7's measure)
func pelvis_y() -> float:
	return ((m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5).y


## the cards as one string: the count and every card's pose (an Undo that changes a pose or a card changes this)
func _cards_key() -> String:
	var parts := [str(m.S.cards.size())]
	for c in m.S.cards:
		parts.append(JSON.stringify(c.get("pose", {})))
	return "|".join(parts)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	# the 2D layout at 1280x720 (the suite's window is embedded and keeps its host's size, so the layout size is set)
	var was_size: Vector2i = root.content_scale_size
	var was_mode: int = root.content_scale_mode
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(8)
	var home: EasyHome = m.easy.home

	# 1. Expert: no panel; Easy with an empty scene: the panel, with 8 cards and the text box
	m._new_scene()
	await idle()
	m.easy.set_on(false, false)
	await idle()
	ok(home.shown() == "hidden", "1. Expert shows no Easy home panel (shown: %s)" % home.shown())
	m.easy.set_on(true, false)
	await idle()
	ok(home.shown() == "panel", "1. Easy with an empty scene shows the panel (shown: %s)" % home.shown())
	var titles: Array = home.panel.find_children("eh_title", "Label", true, false)
	ok(titles.size() == 1 and (titles[0] as Label).text == "What should he do?", "1. the panel's title is 'What should he do?'")
	var cards := 0
	for i in 8:
		if card_btn(i) != null:
			cards += 1
	ok(cards == 8, "1. the panel has the 8 picture cards (%d)" % cards)
	var edit := home.panel.find_child("eh_text", true, false) as LineEdit
	ok(edit != null and edit.placeholder_text.begins_with("or type a move: 'jab then cross'"), "1. the text box says 'or type a move: ...'")

	# 2 and 3. every card: builds (or says why not), plays, times the click to the first played frame
	var times := []
	var fast_ms := []
	for i in 8:
		m.playing = false
		m._new_scene()
		await idle(2)
		var before: int = m.undo.size()
		var t0 := Time.get_ticks_msec()
		card_btn(i).pressed.emit()
		var played := await wait_playing()
		var ms := Time.get_ticks_msec() - t0
		var name := String(card_btn(i).get_meta("label"))
		if i in BUILDS:
			ok(m.S.cards.size() >= 2 and played, "2. %s builds a clip of %d cards and plays it" % [name, m.S.cards.size()])
			ok(m.undo.size() == before + 1, "4. %s is one undo step" % name)
			# the bar is per card, except where the builder alone is slower: then the builder's time is reported and the
			# rest of the click (the scene load, the redraw, the start of play) must still fit the bar
			var rest := home.last_ms - home.last_build_ms
			if home.last_build_ms >= BAR_MS:
				ok(home.last_ms >= 0 and rest < BAR_MS, "3. %s: the builder alone takes %d ms (over the bar: reported); click to the first played frame %d ms, the rest after the build %d ms" % [name, home.last_build_ms, home.last_ms, rest])
			else:
				ok(home.last_ms >= 0 and home.last_ms < BAR_MS, "3. %s: click to the first played frame %d ms (builder %d ms; bar %d ms)" % [name, home.last_ms, home.last_build_ms, BAR_MS])
			times.append([name, home.last_build_ms, home.last_ms])
			# 7. the beginner's wait: every card's click to its first moving frame under 500 ms (the Kick card was 3.6 s live)
			ok(home.last_ms >= 0 and home.last_ms < FAST_MS, "7. %s: click to the first moving frame %d ms (bar %d ms)" % [name, home.last_ms, FAST_MS])
			fast_ms.append("%s %d" % [name, home.last_ms])
		else:
			ok(m.S.cards.is_empty() and home.shown() == "panel" and home.panel.find_child("eh_msg", true, false).text != "",
				"2. %s has no builder yet: the scene stays empty and one plain sentence says why: '%s'" % [name, (home.panel.find_child("eh_msg", true, false) as Label).text])

	# 4. one Ctrl+Z after a card gives back the empty scene
	m.playing = false
	m._new_scene()
	await idle(2)
	card_btn(0).pressed.emit()
	await idle(2)
	ok(not m.S.cards.is_empty(), "4. a card built a clip before the undo check")
	var n_undo: int = m.undo.size()
	var k := InputEventKey.new()
	k.keycode = KEY_Z
	k.physical_keycode = KEY_Z
	k.ctrl_pressed = true
	k.pressed = true
	root.push_input(k)
	await idle(3)
	print("diag ctrl+z: undo steps %d -> %d, cards %d, focus %s" % [n_undo, m.undo.size(), m.S.cards.size(), str(root.gui_get_focus_owner())])
	ok(m.S.cards.is_empty(), "4. one Ctrl+Z after Walk gives back the empty scene (%d cards)" % m.S.cards.size())
	ok(home.shown() == "panel", "4. the panel comes back for the empty scene (shown: %s)" % home.shown())

	# 5. "jab then cross" = two strikes
	var two: Dictionary = home._words_dict("jab then cross")
	var jab: Dictionary = home._words_dict("jab")
	var cross: Dictionary = home._words_dict("cross")
	ok(two["ok"] and two["strikes"] == 2, "5. 'jab then cross' builds 2 strikes")
	ok(two["ok"] and (two["dict"]["cards"] as Array).size() == (jab["dict"]["cards"] as Array).size() + (cross["dict"]["cards"] as Array).size(),
		"5. its cards are the jab's cards then the cross's")
	m._new_scene()
	await idle(2)
	edit.text = "jab then cross"
	edit.text_submitted.emit("jab then cross")
	await idle(2)
	ok(not m.S.cards.is_empty() and home.shown() == "strip", "5. typed 'jab then cross' builds a clip and the panel shrinks to the strip (shown: %s)" % home.shown())
	ok(home.strip.find_child("eh_again", true, false) != null and home.strip.find_child("eh_change", true, false) != null and home.strip.find_child("eh_save", true, false) == null,
		"the strip has Again and Change it; Save video is on the Easy bar only (one button per label)")

	# 5b. the typed box builds a card's word alone or in a chain ("walk then wave"), the same moves as the cards: no "can't build"
	for t in ["walk", "jump", "walk then wave", "jump then kick", "sit down then fall"]:
		m._new_scene()
		await idle(2)
		edit.text = t
		edit.text_submitted.emit(t)
		await idle(2)
		var said: String = m.ui_status.text + " " + (home.panel.find_child("eh_msg", true, false) as Label).text
		ok(m.S.cards.size() >= 2 and not "can't build" in said,
			"5b. typed '%s' builds %d cards and never says \"can't build\" (says: '%s')" % [t, m.S.cards.size(), said.strip_edges()])
	# 5c. a word Kine cannot build builds nothing, and its sentence names only what Kine accepts (the cards' words, then strikes)
	m._new_scene()
	await idle(2)
	edit.text = "dance"
	edit.text_submitted.emit("dance")
	await idle(2)
	var why := (home.panel.find_child("eh_msg", true, false) as Label).text
	var try_names := []
	for n in ["walk", "punch", "kick", "wave"]:
		try_names.append(home.panel.find_child("eh_try_%s" % n, true, false) as Button)
	ok(m.S.cards.is_empty() and why == "Kine doesn't know 'dance' yet." and home._try_row.visible and not try_names.has(null),
		"5c. typed 'dance' builds nothing, says one short line, and offers the Or-try moves (says: '%s')" % why)

	# 6. the panel fits the window at 1280x720 (the empty scene's panel)
	m._new_scene()
	await idle(3)
	var vis := m.get_viewport().get_visible_rect()
	var r: Rect2 = home.panel.get_global_rect()
	ok(vis.size == Vector2(1280, 720) and vis.encloses(r), "6. the panel fits inside the 1280x720 window (panel %s in %s)" % [str(r), str(vis)])
	ok(home.shown() == "panel", "6. the empty-scene panel is up for the screenshot (shown: %s)" % home.shown())
	edit.text = ""   # the box shows its hint in the picture
	await idle(2)
	var img: Image = m.get_viewport().get_texture().get_image()
	var shot := "user://easyhome_panel.png"
	img.save_png(shot)
	print("screenshot %s" % ProjectSettings.globalize_path(shot))
	# C. the body is visible beside the panel: its screen box (every capsule end projected by m.cam, with its radius) is covered
	# by the panel by at most 15 % of its area. Measured at 1280x720 (the bar) and at 1600x900 (the window the beginner had)
	for sz in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.content_scale_size = sz
		await idle(6)
		m._cam()
		await idle(2)
		var pr: Rect2 = home.panel.get_global_rect()
		var br := body_box()
		var frac := pr.intersection(br).get_area() / maxf(br.get_area(), 1.0)
		ok(home.shown() == "panel" and br.get_area() > 0.0 and frac <= 0.15,
			"C. at %dx%d the panel covers %.1f %% of the body's screen box (panel %s, body %s; bar 15 %%)" % [sz.x, sz.y, frac * 100.0, str(pr), str(br)])
	root.content_scale_size = was_size   # back to the window's own size
	root.content_scale_mode = was_mode
	await idle(4)

	# 8. the Library opened over an empty Easy scene: the panel steps aside (the library covered its left half), and comes back on Close
	m._new_scene()
	await idle()
	m._library_toggle()
	await idle()
	ok(not home.panel.visible and m.ui_library.visible, "8. the open Library hides the home panel (no half-covered cards)")
	var lr: Rect2 = m.ui_library.get_global_rect()
	ok(lr.end.y <= m.get_viewport().get_visible_rect().size.y + 0.5, "8. the Library ends inside the window (bottom %.0f px, window %.0f; it once grew to 1572 px over the cards)" % [lr.end.y, m.get_viewport().get_visible_rect().size.y])
	m._library_toggle()
	await idle()
	ok(home.panel.visible, "8. closing the Library brings the home panel back")

	# 9. a built clip's strip (Again, Change it, Faster...) steps aside while the Library is open (it covered them), and comes back on Close
	m._new_scene()
	await idle()
	home.card(0)
	await idle(8)
	ok(home.shown() == "strip", "9. a built clip shows the strip (shown: %s)" % home.shown())
	m._library_toggle()
	await idle()
	ok(home.shown() == "hidden" and m.ui_library.visible, "9. the open Library hides the strip too (shown: %s)" % home.shown())
	m._library_toggle()
	await idle()
	ok(home.shown() == "strip", "9. closing the Library brings the strip back (shown: %s)" % home.shown())

	# 10. the say line names the clip just built, not the last one's words (a typed 'wave' after a walk said 'the walk')
	m._new_scene()
	await idle()
	home.card(0)
	await idle(4)
	ok(m.ui_status.text.begins_with("Made the walk"), "10. the say line names the built card (says: '%s')" % m.ui_status.text)
	home.card(6)
	await idle(4)
	ok(m.ui_status.text.begins_with("Made the wave"), "10. the say line follows the next card (says: '%s')" % m.ui_status.text)

	# 11. CHAIN: "walk, then wave" from the cards. With a clip built, the picker's "Then:" row (Add after is the default) keeps
	# the walk and adds the wave's cards after it (one undo step); Start over replaces it (today's behaviour). Undo takes the add back.
	m._new_scene()
	await idle(2)
	ok(home.panel.find_child("eh_then", true, false).visible == false, "11. the Then: row is hidden on an empty scene (nothing to add after)")
	home.card(0)
	await idle(4)
	var walk_n: int = m.S.cards.size()
	var walk_len: float = m.S.length()
	var walk_names: Array = []
	for c in m.S.cards:
		walk_names.append(c["name"])
	m._new_scene()
	await idle(2)
	home.card(6)
	await idle(4)
	var wave_n: int = m.S.cards.size()
	var wave_name: String = String(m.S.cards[0]["name"])
	var add_btn := home.panel.find_child("eh_then_add", true, false) as Button
	var start_btn := home.panel.find_child("eh_then_start", true, false) as Button
	m._new_scene()
	await idle(2)
	home.card(0)
	await idle(4)
	home._change()   # Change it: the picker comes back over the walk, with the Then: row
	await idle(4)
	ok(home.shown() == "panel" and add_btn != null and add_btn.button_pressed and home.panel.find_child("eh_then", true, false).visible,
		"11. with a walk built, Change it shows the picker with the Then: row and Add after chosen (shown: %s)" % home.shown())
	var before_u: int = m.undo.size()
	var chain_img: Image = m.get_viewport().get_texture().get_image()
	chain_img.save_png("user://easy_chain_picker.png")
	print("chain screenshot %s" % ProjectSettings.globalize_path("user://easy_chain_picker.png"))
	card_btn(6).pressed.emit()
	await idle(4)
	var names_now: Array = []
	for c in m.S.cards:
		names_now.append(c["name"])
	ok(m.S.cards.size() == walk_n + wave_n, "11. Walk, then Wave by cards: %d cards = the walk's %d + the wave's %d (%d)" % [m.S.cards.size(), walk_n, wave_n, m.S.cards.size()])
	ok(names_now.slice(0, walk_n) == walk_names and String(names_now[walk_n]) == wave_name,
		"11. the walk's cards come first, then the wave's (the card at %d is '%s')" % [walk_n, String(names_now[walk_n]) if names_now.size() > walk_n else ""])
	ok(m.S.length() > walk_len + 0.4 and home.shown() == "strip", "11. the clip runs past the walk's end (%.2f s after %.2f s); the strip shows (shown: %s)" % [m.S.length(), walk_len, home.shown()])
	ok(m.undo.size() == before_u + 1, "11. the add is one undo step (%d -> %d)" % [before_u, m.undo.size()])
	ok(m.ui_status.text.begins_with("Made the wave") and m.ui_status.text.contains("added after the walk"), "11. the say line says the wave was added after the walk (says: '%s')" % m.ui_status.text)
	m._undo()
	await idle(4)
	var back_names: Array = []
	for c in m.S.cards:
		back_names.append(c["name"])
	ok(back_names == walk_names, "11. Undo takes the add back: the walk's cards only (%d cards)" % m.S.cards.size())
	# Start over: the same two moves, the wave replaces the walk (today's behaviour)
	home._change()
	await idle(4)
	start_btn.button_pressed = true   # the click: the group turns Add after off and this one on (toggled sets the choice)
	await idle(1)
	card_btn(6).pressed.emit()
	await idle(4)
	ok(m.S.cards.size() == wave_n and String(m.S.cards[0]["name"]) == wave_name, "11. Start over: the wave replaces the walk (%d cards, the wave's %d)" % [m.S.cards.size(), wave_n])

	# 12. THE SAVED-VIDEO MESSAGE IS ABOUT THAT CLIP (walk-through round 4): it stays while nothing changes, goes when the save
	# question comes up or the clip changes (New scene), and the save question's words are not repeated in Easy's status line
	m._new_scene()
	await idle(4)
	card_btn(3).pressed.emit()   # Punch
	await idle(4)
	m.playing = false
	home._show_toast("Your video is saved: test.mp4", "C:/nowhere/test.mp4")
	await idle(3)
	var sv: Control = home._toast
	ok(sv.visible, "12. the saved-video message shows while the clip is unchanged")
	var st0: String = m.ui_status.text
	m._ask_save("this scene", func(): pass)
	await idle(3)
	ok(not sv.visible, "12. the save question takes the saved-video message down")
	ok(m.ui_status.text == st0 and not m.ui_status.text.contains("Don't save throws"), "12. Easy: the status line does not repeat the save question ('%s')" % m.ui_status.text)
	m._save_ask_choose("cancel")
	await idle(2)
	home._show_toast("Your video is saved: test.mp4", "C:/nowhere/test.mp4")
	await idle(2)
	m.S.cards.clear()
	await idle(3)
	ok(not sv.visible, "12. the clip changing takes the saved-video message down")
	home._show_toast("Nothing here yet", "")   # a message with no file (the empty-scene hint) is not a saved-video message: it stays
	await idle(3)
	ok(sv.visible, "12. a message with no file is left alone")
	sv.visible = false
	m._new_scene()
	await idle(4)

	# 13. A WORD KINE CANNOT BUILD IS SAID ONCE (walk-through round 4): the panel says it, the status line doesn't repeat it
	m._new_scene()
	await idle(4)
	edit.text = "backflip"
	edit.text_submitted.emit("backflip")
	await idle(4)
	var said13: String = (home.panel.find_child("eh_msg", true, false) as Label).text
	ok(said13.contains("backflip") and not m.ui_status.text.contains("backflip"), "13. 'backflip' is said in the panel only (panel '%s', status '%s')" % [said13, m.ui_status.text])
	m._new_scene()
	await idle(4)

	# 14. SIT ON A CHAIR, AND VIEW BUTTONS (walk-through round 5, goals 4 and 7). A chair placed in Easy shows "Sit on it" in the
	# panel; the click seats him on it (SET's own sit: main._prop_sit); typed "sit on the chair" does the same. Front, Side and
	# Back turn the camera 0 / 90 / 180 deg; Front returns it exactly
	m._new_scene()
	await idle(4)
	var sit_btn := home.panel.find_child("eh_sit", true, false) as Button
	ok(sit_btn != null and not sit_btn.visible, "14. no chair picked: no 'Sit on it' button in the panel")
	m._prop_add("chair")
	await idle(4)
	sit_btn = home.panel.find_child("eh_sit", true, false) as Button
	ok(sit_btn != null and sit_btn.visible and not sit_btn.disabled, "14. a chair placed: 'Sit on it' is visible in the panel and live")
	if sit_btn != null:
		sit_btn.pressed.emit()
	await idle(6)
	var g14: Array = seat_gap()
	ok(m.S.cards.size() == 1 and String(m.S.cards[0]["name"]).begins_with("sit on the chair"), "14. Sit on it builds the chair's sit card (%d cards)" % m.S.cards.size())
	ok(bool(g14[0]), "14. click: the hips are over the chair's seat")
	ok(float(g14[1]) > -0.005 and float(g14[1]) < 0.15, "14. click: the hips end %.3f m above the seat's top (within 0.15)" % float(g14[1]))
	m._new_scene()
	await idle(4)
	m._prop_add("chair")
	await idle(4)
	var n14: int = m.S.cards.size()
	edit.text = "sit on the chair"
	edit.text_submitted.emit("sit on the chair")
	await idle(6)
	ok(m.S.cards.size() == n14 + 1 and String(m.S.cards[m.sel_card]["name"]).begins_with("sit on the chair"), "14. typed 'sit on the chair' adds the chair's sit card (%d cards)" % m.S.cards.size())
	g14 = seat_gap()
	ok(bool(g14[0]), "14. typed: the hips are over the chair's seat")
	ok(float(g14[1]) > -0.005 and float(g14[1]) < 0.15, "14. typed: the hips end %.3f m above the seat's top (within 0.15)" % float(g14[1]))
	m._new_scene()
	await idle(4)
	home.card(0)   # a clip first (round 5 placed the chair after building moves): the panel is hidden, the strip shows
	await idle(6)
	m.playing = false
	m._prop_add("chair")
	await idle(4)
	var sit_s := home.strip.find_child("eh_sit_strip", true, false) as Button
	ok(home.strip.visible and sit_s != null and sit_s.visible and sit_s.is_visible_in_tree(), "14. a clip built, then a chair placed: 'Sit on it' is on the strip (the panel is hidden)")
	var n14s: int = m.S.cards.size()
	if sit_s != null:
		sit_s.pressed.emit()
	await idle(6)
	m.playing = false   # the clip plays from its start (the walk): look at the sit card itself
	var k14s: int = m.sel_card
	m._card_pick(k14s)
	await idle(3)
	g14 = seat_gap()
	ok(String(m.S.cards[k14s]["name"]).begins_with("sit on the chair") and k14s == m.S.cards.size() - 1, "14. the sit card comes after the clip (card %d of %d: '%s')" % [k14s + 1, m.S.cards.size(), String(m.S.cards[k14s]["name"])])
	ok(home.clip_name().ends_with("_then_sit_on_the_chair"), "14. the clip's name takes the sit after the walk ('%s')" % home.clip_name())
	ok(m.S.cards.size() > n14s and bool(g14[0]) and float(g14[1]) > -0.005 and float(g14[1]) < 0.15, "14. the strip's Sit on it seats him on the chair after the clip (%d -> %d cards, %.3f m above the seat)" % [n14s, m.S.cards.size(), float(g14[1])])
	m._new_scene()
	await idle(4)
	var front := m.easy.views.find_child("easy_view_front", true, false) as Button
	var side := m.easy.views.find_child("easy_view_side", true, false) as Button
	var back := m.easy.views.find_child("easy_view_back", true, false) as Button
	var reset := m.easy.views.find_child("easy_view_reset", true, false) as Button
	ok(front != null and side != null and back != null and reset != null and m.easy.views.visible and front.visible, "14. Easy shows the view buttons Front, Side, Back, Reset view")
	m._turn_to(37.0, -8.0, m.dist, m.target, false)   # the camera starts off the front: Front must do the turn itself
	await idle(2)
	if front != null:
		front.pressed.emit()
		await create_timer(0.6).timeout
	var yf0: float = wrapf(m.yaw, -180.0, 180.0)
	ok(absf(yf0) < 0.01, "14. Front: the camera faces the front (yaw %.2f)" % m.yaw)
	if side != null:
		side.pressed.emit()
		await create_timer(0.6).timeout
	ok(absf(absf(wrapf(m.yaw, -180.0, 180.0)) - 90.0) < 0.5, "14. Side turns the camera 90 deg (yaw %.2f)" % m.yaw)
	if back != null:
		back.pressed.emit()
		await create_timer(0.6).timeout
	ok(absf(absf(wrapf(m.yaw, -180.0, 180.0)) - 180.0) < 0.5, "14. Back turns the camera 180 deg (yaw %.2f)" % m.yaw)
	if front != null:
		front.pressed.emit()
		await create_timer(0.6).timeout
	ok(absf(wrapf(m.yaw, -180.0, 180.0)) < 0.01, "14. Front returns the camera exactly (yaw %.3f)" % m.yaw)
	m._new_scene()
	await idle(4)

	# 15. EDIT A PICKED CARD (walk-through round 5, goal 3): a beginner picks the middle card, drags the arm, and THAT card takes
	# the new pose in place: one undo step ("Change pose"), the card count and the other cards unchanged; moving the timeline off
	# the card keeps the edit; Ctrl+Z puts the card's pose back. Real mouse: the card's picture is clicked, the arm dragged on the body.
	m._new_scene()
	await idle(2)
	home.card(0)   # the walk: several cards
	await idle(6)
	m.playing = false
	var n15: int = m.S.cards.size()
	var k15: int = n15 / 2
	ok(n15 >= 3, "15. the walk has %d cards: a middle one to pick" % n15)
	await click_ctl(pick_btn(k15))
	ok(m.sel_card == k15, "15. a real click picks the middle card %d (picked: %d)" % [k15 + 1, m.sel_card + 1])
	var before15: Dictionary = m.S.cards[k15]["pose"].duplicate(true)
	var others15: Array = []
	for i in n15:
		if i != k15:
			others15.append(m.S.cards[i]["pose"].duplicate(true))
	var undo15: int = m.undo.size()
	await drag_part("hand_r", Vector2(-70, -30))
	m.playing = false
	ok(m.S.cards.size() == n15, "15. the drag keeps the card count (%d -> %d)" % [n15, m.S.cards.size()])
	ok(not EasyMode.same_pose(m.S.cards[k15]["pose"], before15), "15. the picked card's pose changed (the arm is dragged)")
	ok(EasyMode.same_pose(m.S.cards[k15]["pose"], m.B.to_dict()), "15. the picked card holds the body's pose now (in place, no new card)")
	var others_same := true
	var oi := 0
	for i in n15:
		if i != k15:
			if not EasyMode.same_pose(m.S.cards[i]["pose"], others15[oi]):
				others_same = false
			oi += 1
	ok(others_same, "15. the other cards' poses are unchanged")
	ok(m.undo.size() == undo15 + 1 and String(m.undo[-1].get("easy", "")) == "Change pose",
		"15. the drag is one undo step named 'Change pose' (%d -> %d, '%s')" % [undo15, m.undo.size(), String(m.undo[-1].get("easy", ""))])
	var changed15: Dictionary = m.S.cards[k15]["pose"].duplicate(true)
	# moving the timeline off the card: the edit stays on that card
	var other15: int = k15 + 1 if k15 + 1 < n15 else k15 - 1
	await click_ctl(pick_btn(other15))
	ok(m.sel_card == other15, "15. a click on another card moves the pick (picked: %d)" % (m.sel_card + 1))
	ok(EasyMode.same_pose(m.S.cards[k15]["pose"], changed15), "15. moving the timeline off the card keeps the edit on it")
	# Ctrl+Z (repeated until the card is back: the pick is an undo step of its own) puts the card's pose back
	for z in 4:
		if EasyMode.same_pose(m.S.cards[k15]["pose"], before15):
			break
		var kz := InputEventKey.new()
		kz.keycode = KEY_Z
		kz.physical_keycode = KEY_Z
		kz.ctrl_pressed = true
		kz.pressed = true
		root.push_input(kz)
		await idle(3)
	ok(EasyMode.same_pose(m.S.cards[k15]["pose"], before15), "15. Ctrl+Z restores the picked card's pose")
	ok(m.S.cards.size() == n15, "15. the card count after the undo is the walk's %d (%d)" % [n15, m.S.cards.size()])
	m._new_scene()
	await idle(4)

	# 16. HELP IN EASY (walk-through round 5): a visible Help button on the panel opens the help (what Easy can do, and the tour);
	#     the strip after a clip has Help too; Show the tour is there
	m._new_scene()
	await idle(4)
	var help_btn := home.panel.find_child("eh_help", true, false) as Button
	ok(help_btn != null and help_btn.is_visible_in_tree(), "16. the panel has a visible Help button in Easy")
	var help_lbl := home.panel.find_child("eh_help_text", true, false) as Label
	ok(help_lbl != null and not help_lbl.visible, "16. the help text is hidden until Help is pressed")
	if help_btn != null:
		help_btn.pressed.emit()
		await idle(3)
	ok(help_lbl != null and help_lbl.is_visible_in_tree() and help_lbl.text.contains("Then") and help_lbl.text.contains("Library"),
		"16. Help opens the help text (what Easy can do: cards, typing, Then, Slower, Library, save video)")
	ok(card_btn(0) != null and not card_btn(0).is_visible_in_tree(), "16. the help text takes the picture cards' place while it is on")
	var tour_btn := home.panel.find_child("eh_help_tour", true, false) as Button
	ok(tour_btn != null and tour_btn.is_visible_in_tree(), "16. the help has a Show the tour button (the existing tour)")
	if help_btn != null:
		help_btn.pressed.emit()   # Help again: the cards come back
		await idle(3)
	ok(card_btn(0) != null and card_btn(0).is_visible_in_tree(), "16. Help again brings the picture cards back")
	m._new_scene()
	await idle(3)
	home.card(0)   # a walk built: the strip shows, with its own Help
	await idle(8)
	var strip_help := home.strip.find_child("eh_help_strip", true, false) as Button
	ok(strip_help != null and strip_help.is_visible_in_tree(), "16. the strip after a clip has a visible Help button")
	if strip_help != null:
		strip_help.pressed.emit()
		await idle(4)
	ok(home.shown() == "panel" and help_lbl != null and help_lbl.is_visible_in_tree(), "16. the strip's Help brings the panel up with the help text")
	m._new_scene()
	await idle(4)

	# 17. A TYPED QUESTION IS ANSWERED WITH HELP (walk-through round 5): "how do I make him jump" names the move to type, never "doesn't know"
	m._new_scene()
	await idle(4)
	edit.text = "how do I make him jump"
	edit.text_submitted.emit(edit.text)
	await idle(4)
	var msg17 := (home.panel.find_child("eh_msg", true, false) as Label).text
	ok(msg17.contains("'jump'") and not msg17.contains("doesn't know") and not m.S.cards.size() > 0,
		"17. 'how do I make him jump' says to type 'jump' (panel '%s')" % msg17)
	ok(not m.ui_status.text.contains("doesn't know"), "17. the question is not refused in the status line either (status '%s')" % m.ui_status.text)
	edit.text = "how to make him dance"
	edit.text_submitted.emit(edit.text)
	await idle(4)
	var msg15b := (home.panel.find_child("eh_msg", true, false) as Label).text
	ok(msg15b.contains("Type a move") and not msg15b.contains("doesn't know"), "17. a how-to with no known move gives the help line ('%s')" % msg15b)
	m._new_scene()
	await idle(4)

	# 18. THE TYPED BOX CLEARS AFTER A MOVE IS USED, AND A CLICK SELECTS WHAT IS LEFT (walk-through round 5)
	m._new_scene()
	await idle(4)
	edit.text = "walk"
	edit.text_submitted.emit("walk")
	await idle(6)
	ok(m.S.cards.size() > 0, "18. typed 'walk' built a clip (cards %d)" % m.S.cards.size())
	ok(edit.text == "", "18. after a typed move is used, the box is empty (box '%s')" % edit.text)
	edit.text = "backflip"
	edit.text_submitted.emit("backflip")
	await idle(4)
	ok(edit.text == "backflip", "18. a line Kine cannot build keeps its words, for editing (box '%s')" % edit.text)
	home._change()
	await idle(4)
	ok(edit.has_selection() and edit.get_selected_text() == "backflip", "18. Change it selects the box's words, so typing replaces them (selected '%s')" % edit.get_selected_text())
	m._new_scene()
	await idle(4)

	# 19. SLOWER ON A LONG CLIP (walk-through round 5): a walk then a sit down is 10.3 s; the old 10 s cap refused Slower on it with
	# "That's as slow as it goes." The cap is 20 s: Slower takes the 10.3 s clip to ~12.9 s. Over the cap the sentence says the length
	# and the way out (no false "as slow as it goes").
	m._new_scene()
	await idle(2)
	home.card(0)
	await idle(4)
	home.card(5)   # Sit down: added after the walk (Add after is the default)
	await idle(4)
	var l0: float = m.S.length()
	m.retime(0, m.S.cards.size() - 1, 10.3 / maxf(l0, 0.01) * 100.0)   # the clip at 10.3 s, as the walk-through had it
	await idle(2)
	var l1: float = m.S.length()
	home.tweak("slower")
	await idle(4)
	ok(absf(l1 - 10.3) < 0.15 and m.S.length() > l1 * 1.2 and m.ui_status.text.begins_with("Slower"),
		"19. Slower works on a %.2f s clip: it takes %.2f s (says: '%s')" % [l1, m.S.length(), m.ui_status.text])
	m.retime(0, m.S.cards.size() - 1, 19.0 / maxf(m.S.length(), 0.01) * 100.0)
	await idle(2)
	var l2: float = m.S.length()
	home.tweak("slower")
	await idle(3)
	var said19: String = m.ui_status.text
	ok(said19.contains("already") and said19.contains("%.1f s" % l2) and said19.contains("Remove a step") and not said19.contains("as slow as it goes"),
		"19. at the cap Slower says the length and the way out (says: '%s')" % said19)
	m._new_scene()
	await idle(4)

	# 20. THE SAVED FILE IS NAMED AFTER THE CLIP AS IT IS NOW (walk-through round 5): walk, then wave added after it: the name is
	# walk_then_wave; Undo takes the wave's words back (walk); a start-over names the new move alone
	m._new_scene()
	await idle(2)
	(home.panel.find_child("eh_then_add", true, false) as Button).button_pressed = true   # Add after (section 11 left Start over on)
	home.card(0)
	await idle(4)
	home.card(6)   # Wave, added after the walk
	await idle(4)
	var nm20: String = home.clip_name() if home.has_method("clip_name") else "(no clip_name)"
	ok(nm20 == "walk_then_wave", "20. the clip's name is 'walk_then_wave' after walk then wave (got '%s')" % nm20)
	m._undo()
	await idle(4)
	var nm15b: String = home.clip_name() if home.has_method("clip_name") else "(no clip_name)"
	ok(nm15b == "walk", "20. Undo takes the wave's words back: the name is 'walk' (got '%s')" % nm15b)
	home.video_root = ProjectSettings.globalize_path("user://easyhome_name20")
	DirAccess.make_dir_recursive_absolute(home.video_root)
	card_btn(6).pressed.emit()   # wave again: the clip is walk then wave
	await idle(4)
	await home.save_video()
	await idle(2)
	var vdir := String(home.last_video.get("dir", "")).get_file()
	ok(vdir.begins_with("walk_then_wave_"), "20. the saved folder and file are named after the clip: '%s'" % vdir)
	home.video_root = ""
	m._new_scene()
	await idle(4)

	# 21. THE SAVED-VIDEO MESSAGE GOES AT THE NEXT ACTION (walk-through round 5): a typed line that Kine cannot build changes neither the
	# cards nor the undo steps, so only the action itself can take the message down; it also goes when its few seconds are up and
	# when the help opens
	m._new_scene()
	await idle(4)
	home.card(3)   # Punch: a clip is on screen
	await idle(4)
	home._show_toast("Your video is saved: test.mp4", "C:/nowhere/test.mp4")
	await idle(2)
	var sv21: Control = home._toast
	home._edit.text = "backflip"
	home._edit.text_changed.emit("backflip")
	home._words("backflip")
	await idle(3)
	ok(sv21.visible == false, "21. typing a line takes the saved-video message down (the message is %s)" % ("still up" if sv21.visible else "gone"))
	home._show_toast("Your video is saved: test.mp4", "C:/nowhere/test.mp4")
	if "_toast_left" in home:   # its few seconds are up: the next frame takes it down (an old build has no such timer: the bar fails)
		home._toast_left = 0.0
	await idle(2)
	var left21: float = home._toast_left if "_toast_left" in home else -1.0
	ok(sv21.visible == false, "21. the saved-video message goes after its few seconds (left %.2f s, shown %s)" % [left21, sv21.visible])
	home._show_toast("Your video is saved: test.mp4", "C:/nowhere/test.mp4")
	m.ui_help.visible = true
	await idle(3)
	ok(sv21.visible == false, "21. opening the help takes the saved-video message down")
	m.ui_help.visible = false
	m._new_scene()
	await idle(4)

	# 22. THE SCENE SAVE SAYS WHERE IT WENT (walk-through round 5): the toast names the file and its folder (the status line keeps its words)
	m._new_scene()
	await idle(4)
	home.card(0)
	await idle(4)
	m._save_scene_now("zz_toast_22")
	await idle(3)
	var t22 := String(m.ui_toast.text) if m.ui_toast != null else ""
	ok(m.ui_toast != null and m.ui_toast.visible and t22.begins_with("Saved as zz_toast_22 in ") and t22.contains("scenes"),
		"22. the save toast says the file and its folder: '%s'" % t22)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(UserPaths.w("res://scenes/zz_toast_22.json")))
	m._new_scene()
	await idle(4)

	# 23. ONE "THEN" ROW ON SCREEN (walk-through round 5, screens 11 and 15): the picker's Then: row (Add after / Start over) and the
	# strip's "Then <move>" row are never on screen together, in each state a beginner reaches: a built clip (the strip), Change it
	# (the picker over the clip), a typed line Kine cannot build, and a reopened scene (the picker over cards). Counted with
	# is_visible_in_tree, so a hidden parent counts as hidden.
	m._new_scene()
	await idle(4)
	home.card(0)
	await idle(4)
	var rows23 := func() -> int:
		var n := 0
		if (home.panel.find_child("eh_then", true, false) as Control).is_visible_in_tree():
			n += 1
		if home._next_row.is_visible_in_tree():
			n += 1
		return n
	var r_strip: int = rows23.call()
	home._change()
	await idle(4)
	var r_picker: int = rows23.call()
	home._edit.text = "sit on the chair"
	home._words("sit on the chair")
	await idle(4)
	var r_typed: int = rows23.call()
	ok(r_strip <= 1 and r_picker <= 1 and r_typed <= 1,
		"23. at most one 'Then' row on screen: strip %d, picker over a clip %d, typed line kine cannot build %d" % [r_strip, r_picker, r_typed])
	m._new_scene()
	await idle(4)

	# 24. A HELD SWORD SURVIVES A TYPED SWING (walk-through LP round, goal 2): the sword goes into the right hand (as a library
	# click does), then "swing" is typed: the cards it builds keep the sword in that hand, every card carries it.
	m._new_scene()
	await idle(4)
	m._kind("sword")
	await idle(2)
	ok(m.B.wep_on and m.B.wep_kind == "sword" and m.B.wep_hand == "hand_r", "24. the sword is in the right hand before the swing (on %s, kind %s, hand %s)" % [str(m.B.wep_on), m.B.wep_kind, m.B.wep_hand])
	home._words("swing")
	await idle(10)
	var n24: int = m.S.cards.size()
	var armed24 := 0
	for c in m.S.cards:
		if not (c["pose"] as Dictionary).get("weapon", {}).is_empty():
			armed24 += 1
	ok(n24 > 0 and armed24 == n24, "24. the typed swing built %d cards and %d of them carry the sword" % [n24, armed24])
	ok(m.B.wep_on and m.B.wep_kind == "sword" and m.B.wep_hand == "hand_r", "24. after the swing the sword is still in his right hand (on %s, kind %s, hand %s)" % [str(m.B.wep_on), m.B.wep_kind, m.B.wep_hand])
	m._new_scene()
	await idle(4)

	# 25. THE KICK REACHES A BALL ON THE FLOOR, AND SAYS IT DOES NOT FLY (walk-through LP round, goal 3): the football is put
	# on the floor in front of him, the kick is typed. The kick's closest toe (both feet, every card, the body's own solve) is
	# within 6 cm of the ball's surface; the ball does not move (nothing makes a ball fly yet); the line says so.
	m._new_scene()
	await idle(4)
	m._prop_add("ball")
	await idle(2)
	var bi25 := -1
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]) == "ball":
			bi25 = i
	var bc25 := Vector3.ZERO
	var br25 := 0.0
	if bi25 >= 0:
		var sp25: Array = Props.kind_of("ball")["spheres"][0]
		bc25 = (m.S.props[bi25]["xf"] as Transform3D) * Vector3(sp25[0])
		br25 = float(sp25[1])
	var p25_0 := bc25
	home._words("kick")
	await idle(10)
	var gap25 := toe_gap(m.S.cards, bc25) - br25 if bi25 >= 0 else INF
	var moved25 := 0.0
	if bi25 >= 0 and bi25 < m.S.props.size():
		moved25 = ((m.S.props[bi25]["xf"] as Transform3D).origin - p25_0).length()
	ok(bi25 >= 0 and m.S.cards.size() > 0, "25. a ball is on the floor and the kick built (cards %d, ball %d)" % [m.S.cards.size(), bi25])
	ok(gap25 <= 0.06, "25. the kick's closest toe is %.1f cm from the ball's surface (bar 6 cm)" % (gap25 * 100.0))
	ok(moved25 == 0.0 or moved25 > 0.5, "25. the ball moved %.2f m (a kick that flies it moves it > 0.5 m; the honest line is the other branch)" % moved25)
	var line25: String = m.ui_status.text if m.ui_status != null else ""
	ok(line25.contains("doesn't fly yet") or line25.contains("does not fly yet"), "25. the say line says the ball does not fly yet (line: '%s')" % line25)
	m._new_scene()
	await idle(4)

	# 26. LIBRARY NAMES (walk-through LP round, goal 3): the old jargon is gone from every tile; a weapon says it is in the hand,
	# a prop says it is on the floor (the sword's two tiles tell apart)
	var old26 := ["Step code", "Stairs code", "Ramp15", "Moving box", "Door frame", "Sword on the floor"]
	var bad26 := []
	var nm26 := []
	for it in m.ui_library.inventory():
		nm26.append(String(it["name"]))
		if old26.has(String(it["name"])):
			bad26.append(String(it["name"]))
	ok(bad26.is_empty(), "26. no library tile has an old jargon name (found: %s)" % str(bad26))
	ok(nm26.has("Sword") and nm26.has("Sword (on the floor)"), "26. the sword tile reads 'Sword' and the prop 'Sword (on the floor)' (names: %s)" % str(nm26))

	# 27. THE PROP BAR (walk-through round 6, goals 1 and 2): a chair placed through the Library is picked by a real click in the
	# view; the bar at the top right shows Remove; Remove is one undo step; Ctrl+Z brings it back; the Delete key removes it too
	m._new_scene()
	await idle(4)
	m._library_toggle()
	await idle(4)
	var srch := m.ui_library.find_child("library_search", true, false) as LineEdit
	if srch != null:
		srch.text = "chair"
		srch.text_changed.emit("chair")
	await idle(4)
	var tile27 := m.ui_library.find_child("tile_*chair*", true, false) as Control
	ok(tile27 != null, "27. the Library lists a chair for the search 'chair'")
	if tile27 != null:
		await click_ctl(tile27)
	await idle(6)
	m._library_toggle()   # the Library closes: the chair is in the view
	await idle(4)
	var bar27 := m.find_child("easy_prop_bar", true, false) as Control
	var rm27 := m.find_child("eh_prop_remove", true, false) as Button
	ok(m.S.props.size() == 1 and String(m.S.props[0]["kind"]) == "chair", "27. the Library placed one chair (%d props)" % m.S.props.size())
	m.sel_prop = -1
	m._props_show()
	await idle(4)
	ok(bar27 != null and bar27.visible and rm27 != null and not rm27.visible, "27. a prop in the scene, none picked: the bar shows (Next prop) and no Remove")
	var sp27 := Vector2(-1, -1)
	if not m.S.props.is_empty():
		sp27 = m.cam.unproject_position((m.S.props[0]["xf"] as Transform3D).origin + Vector3(0, 0.5, 0))
	for hh in [0.0, 0.2, 0.5, 0.8]:
		var pp: Vector2 = m.cam.unproject_position((m.S.props[0]["xf"] as Transform3D).origin + Vector3(0, hh, 0))
	await click_at(sp27)
	ok(m.sel_prop == 0, "27. a real click on the chair in the view picks it (sel_prop %d, at %s)" % [m.sel_prop, str(sp27)])
	ok(rm27 != null and rm27.is_visible_in_tree(), "27. picked: Remove is visible on the bar")
	var pb27 := (home._pbar as Control).get_global_rect()
	var hit27 := []
	for j27 in Body.BODY:
		if true:
			var q27: Vector2 = m.cam.unproject_position(m.B.cap(j27)[0].lerp(m.B.cap(j27)[1], 0.5))
			if pb27.has_point(q27):
				hit27.append(j27)
	ok(hit27.is_empty(), "27. the prop bar %s covers none of his body (covered: %s)" % [str(pb27), str(hit27)])
	# no visible Easy text names SET, read right after the real click (the press's own line: "... are in SET" in the old code)
	var bad27 := []
	for tx27 in visible_texts(m, []):
		if String(tx27).contains("SET"):
			bad27.append(tx27)
	ok(bad27.is_empty(), "27. no visible Easy text says 'SET' after a pick (%s)" % str(bad27))
	var yaw0: float = Props.yaw_of(m.S.props[0]["xf"]) if not m.S.props.is_empty() else 0.0
	var tr27 := m.find_child("eh_prop_turn_r", true, false) as Button
	if tr27 != null and tr27.is_visible_in_tree():
		await click_ctl(tr27)
	await idle(2)
	var dy: float = wrapf(Props.yaw_of(m.S.props[0]["xf"]) - yaw0, -180.0, 180.0) if not m.S.props.is_empty() else 0.0
	ok(absf(dy - 15.0) < 0.5, "27. Turn right turns the picked chair 15 deg (turned %.2f)" % dy)
	var u27: int = m.undo.size()
	if rm27 != null:
		await click_ctl(rm27)
	await idle(4)
	ok(m.S.props.is_empty(), "27. Remove takes the chair out of the scene (%d props)" % m.S.props.size())
	ok(m.undo.size() == u27 + 1, "27. Remove is one undo step (%d -> %d)" % [u27, m.undo.size()])
	await key_press(KEY_Z, true)
	ok(m.S.props.size() == 1 and not m.S.props.is_empty() and String(m.S.props[0]["kind"]) == "chair", "27. Ctrl+Z brings the chair back (%d props)" % m.S.props.size())
	if not m.S.props.is_empty():
		await click_at(m.cam.unproject_position((m.S.props[0]["xf"] as Transform3D).origin + Vector3(0, 0.5, 0)))
	ok(m.sel_prop == 0, "27. the chair is picked again by a real click")
	await key_press(KEY_DELETE)
	ok(m.S.props.is_empty(), "27. the Delete key removes the picked chair (%d props)" % m.S.props.size())
	await key_press(KEY_Z, true)
	ok(m.S.props.size() == 1, "27. Ctrl+Z after the Delete key brings it back")
	# Next object reaches every prop: a table added, then Next prop twice from none picked: the chair, then the table
	m._prop_add("table")
	await idle(4)
	m.sel_prop = -1
	m._props_show()
	await idle(2)
	var nx27 := m.find_child("eh_prop_next", true, false) as Button
	var reach: Array = []
	for kk27 in 2:
		if nx27 != null:
			await click_ctl(nx27)
		reach.append(String(m._prop_name(m.sel_prop)))
	ok(reach == ["chair", "table"], "27. Next object reaches the chair, then the table (%s)" % str(reach))
	# 28. FROM A VIDEO ON EASY'S OWN SURFACE (video walk-through round 6, goal 1): the empty scene's panel and a built clip's strip each
	# have a visible "From a video" button whose press is the same action as More > Copy a video (home.copy_video)
	m._new_scene()
	await idle(4)
	var fv_panel := home.panel.find_child("eh_from_video", true, false) as Button
	var fv_strip := home.strip.find_child("eh_from_video_strip", true, false) as Button
	ok(fv_panel != null and fv_panel.is_visible_in_tree(), "28. the empty scene's panel shows a 'From a video' button")
	ok(fv_panel != null and fv_panel.pressed.get_connections().size() > 0 and fv_panel.pressed.get_connections()[0]["callable"] == Callable(home, "copy_video"),
		"28. 'From a video' (panel) calls the same action as More > Copy a video")
	home.copy_video_file(FIX)
	await wait_copy(4000)
	await idle(6)
	fv_strip = home.strip.find_child("eh_from_video_strip", true, false) as Button
	ok(fv_strip != null and fv_strip.is_visible_in_tree(), "28. the copied clip's strip shows a 'From a video' button")
	ok(fv_strip != null and fv_strip.pressed.get_connections().size() > 0 and fv_strip.pressed.get_connections()[0]["callable"] == Callable(home, "copy_video"),
		"28. 'From a video' (strip) calls the same action as More > Copy a video")

	# 29. TRIM (goal 4): the picked card is where the good part starts: Cut start drops the cards before it; Cut end drops the
	# cards after it. One undo step each; Ctrl+Z (undo) gives the cards back; the clip still plays from its new start
	var n29: int = m.S.cards.size()
	ok(n29 >= 4, "29. the copied clip has 4+ cards to trim (%d)" % n29)
	await click_ctl(pick_btn(2))
	await idle(2)
	var u29: int = m.undo.size()   # after the pick: a pick is an undo step of its own
	var cut_s := home.strip.find_child("eh_cut_start", true, false) as Button
	ok(cut_s != null and cut_s.is_visible_in_tree(), "29. a visible 'Cut start' button on the strip")
	if cut_s != null:
		await click_ctl(cut_s)
	await idle(6)
	ok(m.S.cards.size() == n29 - 2, "29. Cut start (picked card 3) leaves %d cards, was %d: %d" % [n29 - 2, n29, m.S.cards.size()])
	ok(m.undo.size() == u29 + 1, "29. Cut start is one undo step (undo %d -> %d)" % [u29, m.undo.size()])
	home._play()
	ok(await wait_playing(), "29. the trimmed clip plays from its new start")
	m._undo()
	await idle(6)
	ok(m.S.cards.size() == n29, "29. Ctrl+Z gives back the cut cards (%d)" % m.S.cards.size())
	await click_ctl(pick_btn(2))
	await idle(2)
	u29 = m.undo.size()
	var cut_e := home.strip.find_child("eh_cut_end", true, false) as Button
	ok(cut_e != null and cut_e.is_visible_in_tree(), "29. a visible 'Cut end' button on the strip")
	if cut_e != null:
		await click_ctl(cut_e)
	await idle(6)
	ok(m.S.cards.size() == 3, "29. Cut end (picked card 3) leaves 3 cards: %d" % m.S.cards.size())
	ok(m.undo.size() == u29 + 1, "29. Cut end is one undo step too")
	m._undo()
	await idle(6)
	ok(m.S.cards.size() == n29, "29. Ctrl+Z after Cut end gives the cards back")

	# 30. SMOOTHER (goal 5): each press smooths the copied motion one step: the mean per-frame hand acceleration goes down, one undo step,
	# and the status line says what changed
	var a0: float = await hand_accel()
	var u30: int = m.undo.size()
	var sm := home.strip.find_child("eh_smoother", true, false) as Button
	ok(sm != null and sm.is_visible_in_tree(), "30. a visible 'Smoother' button on the strip")
	if sm != null:
		await click_ctl(sm)
	await idle(6)
	var a1: float = await hand_accel()
	print("   hand acceleration mean: %.5f -> %.5f m/frame^2" % [a0, a1])
	ok(a1 < a0 * 0.98, "30. Smoother lowers the mean hand acceleration (%.5f -> %.5f)" % [a0, a1])
	ok(m.undo.size() == u30 + 1, "30. Smoother is one undo step")
	ok("smooth" in String(m.ui_status.text).to_lower(), "30. the status line says what Smoother did: '%s'" % m.ui_status.text)
	m._undo()
	await idle(6)
	var a2: float = await hand_accel()
	ok(absf(a2 - a0) < 0.0005, "30. Ctrl+Z puts the motion back (%.5f, was %.5f)" % [a2, a0])

	# 31. NO RED TINT IN EASY (goal 9): the red on torso and thighs is the contact warning (pick_touch). Easy does not show it, on a
	# copied clip or on a typed clip; Expert keeps it (checked on the same clip)
	m._new_scene()
	await idle(4)
	home._edit.text = "swing"
	home._words("swing")
	await idle(6)
	var red_typed: int = await red_frames()
	ok(red_typed == 0, "31. a typed 'swing' in Easy: no red contact tint on the body (%d of 6 frames with red)" % red_typed)
	m._new_scene()
	await idle(4)
	home.copy_video_file(FIX)
	await wait_copy(4000)
	await idle(6)
	var red31: int = await red_while_playing()
	ok(red31 == 0, "31. a copied clip in Easy: no red contact tint while it plays (%d samples with red)" % red31)
	m._new_scene()
	await idle(4)

	# 45. BIGGER / SMALLER / COLOUR (library walk-through goal 6): the picked chair's own box grows and shrinks; its colour changes and the
	# status names it; each is one undo step (Ctrl+Z restores); the scene saves and reloads with the size and the colour
	m._new_scene()
	await idle(4)
	m.easy.set_on(true, false)
	await idle(2)
	m._prop_add("chair")
	await idle(4)
	m.sel_prop = 0
	m._props_show()
	await idle(4)
	var bg45 := m.find_child("eh_prop_bigger", true, false) as Button
	var sm45 := m.find_child("eh_prop_smaller", true, false) as Button
	var cl45 := m.find_child("eh_prop_colour", true, false) as Button
	ok(bg45 != null and bg45.is_visible_in_tree() and sm45 != null and sm45.is_visible_in_tree() and cl45 != null and cl45.is_visible_in_tree(),
		"45. the prop bar shows Bigger, Smaller and Colour for the picked chair")
	var b45 := prop_box(m.S.props[0]).size
	var u45: int = m.undo.size()
	if bg45 != null:
		await click_ctl(bg45)
	await idle(4)
	var b45a := prop_box(m.S.props[0]).size
	ok(b45a.x > b45.x * 1.1 and b45a.y > b45.y * 1.1 and b45a.z > b45.z * 1.1, "45. Bigger: the picked chair's box grows (%s -> %s)" % [str(b45), str(b45a)])
	ok(m.undo.size() == u45 + 1, "45. Bigger is one undo step (%d -> %d)" % [u45, m.undo.size()])
	ok("bigger" in String(m.ui_status.text).to_lower(), "45. the status says the chair is bigger: '%s'" % m.ui_status.text)
	await key_press(KEY_Z, true)
	await idle(4)
	var b45u := prop_box(m.S.props[0]).size
	ok(b45u.distance_to(b45) < 0.001, "45. Ctrl+Z gives the chair back its size (%s, was %s)" % [str(b45u), str(b45)])
	if sm45 != null:
		await click_ctl(sm45)
	await idle(4)
	var b45s := prop_box(m.S.props[0]).size
	ok(b45s.x < b45.x * 0.9 and b45s.y < b45.y * 0.9 and b45s.z < b45.z * 0.9, "45. Smaller: the picked chair's box shrinks (%s -> %s)" % [str(b45), str(b45s)])
	await key_press(KEY_Z, true)
	await idle(4)
	if cl45 != null:
		await click_ctl(cl45)
	await idle(4)
	ok(Props.colour_of(m.S.props[0]) == "blue", "45. Colour makes the picked chair blue (%s)" % Props.colour_of(m.S.props[0]))
	ok("blue" in String(m.ui_status.text).to_lower() and "chair" in String(m.ui_status.text), "45. the status names the colour: '%s'" % m.ui_status.text)
	var mi45: Node = m.ui_props_root.find_child("prop_0", true, false)
	var col45 := Color(0, 0, 0)
	if mi45 != null:
		var mis: Array = mi45.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			var mat45 := (mis[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
			if mat45 != null:
				col45 = mat45.albedo_color
	ok(Vector3(col45.r, col45.g, col45.b).distance_to(Vector3(Props.COLOURS["blue"].r, Props.COLOURS["blue"].g, Props.COLOURS["blue"].b)) < 0.01,
		"45. the chair's material is blue in the view (%s)" % str(col45))
	await key_press(KEY_Z, true)
	await idle(4)
	ok(Props.colour_of(m.S.props[0]) == "grey", "45. Ctrl+Z gives the chair its colour back (%s)" % Props.colour_of(m.S.props[0]))
	# the size and the colour go into the scene file and come back on a reload
	if bg45 != null:
		await click_ctl(bg45)
	if cl45 != null:
		await click_ctl(cl45)
	await idle(4)
	var big45 := prop_box(m.S.props[0]).size
	m._save_scene_now("_wip_es45")
	await idle(4)
	var path45: String = m.scene_path
	m._new_scene()
	await idle(4)
	m._load_scene(path45)
	await idle(8)
	var r45: bool = m.S.props.size() == 1 and Props.colour_of(m.S.props[0]) == "blue" and absf(Props.scale_of(m.S.props[0]) - 1.15) < 0.001
	ok(r45, "45. the scene reloads with the chair bigger (x%.3f) and blue (%d props)" % [Props.scale_of(m.S.props[0]) if not m.S.props.is_empty() else 0.0, m.S.props.size()])
	if not m.S.props.is_empty():
		ok(prop_box(m.S.props[0]).size.distance_to(big45) < 0.001, "45. the reloaded chair's box is the saved size (%s, was %s)" % [str(prop_box(m.S.props[0]).size), str(big45)])
	if path45 != "" and FileAccess.file_exists(path45):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path45))   # the test's own _wip scene
	# 40-42. COPY A VIDEO IN EASY (walk-through round, friction 1-3): the refusal stays on the bar, an unsaved scene is asked about
	# first, and the copied cards are named plainly
	var fx := ProjectSettings.globalize_path("res://tests/data/see_video_crop_small.mp4")
	var shot_dir := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad"
	m._new_scene()
	await idle(4)
	ok(FileAccess.file_exists(fx), "40. the fixture is there (%s)" % fx)
	home.copy_video_file(fx)
	await wait_ms(1000)
	var busy40 := home._vid_busy
	home.copy_video_file(fx)   # the second, while the first reads the video: refused
	await wait_ms(1000)
	var line40: String = m.ui_status.text if m.ui_status != null else ""
	ok(busy40 and line40.contains("Still copying the first video"), "40. one second after a second copy the bar says the first is still going (line: '%s')" % line40)
	await wait_busy(home, 300000)
	ok(not home._vid_busy and m.S.cards.size() > 0, "40. the first copy finished with cards (%d)" % m.S.cards.size())

	# 41. the unsaved scene (the copy above, untouched since): a copy asks first
	var n41: int = m.S.cards.size()
	var path41 := String(m.scene_path)
	ok(m._unsaved(), "41. the copied scene counts as unsaved (the question's case)")
	home.copy_video_file(fx)
	await idle(6)
	var ask41: Node = m.find_child("CopyAsk", true, false)   # (the new question's node; the old code has none: the copy just starts)
	ok(ask41 != null and (ask41 as Window).visible, "41. a copy over unsaved cards asks 'Replace your clip?' first")
	if ask41 != null and (ask41 as Window).visible:
		var img41 := get_root().get_texture().get_image()
		img41.save_png(shot_dir + "/easy_vid_ask.png")
	ok(not home._vid_busy and m.S.cards.size() == n41 and String(m.scene_path) == path41, "41. while the question is up nothing is copied (cards %d, file the same)" % m.S.cards.size())
	home.call("copy_choose", "cancel")
	await idle(10)
	ok(not home._vid_busy and m._video_pid < 0 and m.S.cards.size() == n41 and String(m.scene_path) == path41,
		"41. Cancel keeps the scene untouched (cards %d -> %d, file %s)" % [n41, m.S.cards.size(), "same" if String(m.scene_path) == path41 else "CHANGED"])
	home.copy_video_file(fx)
	await idle(4)
	home.call("copy_choose", "add")
	await wait_busy(home, 300000)
	await idle(4)
	var n41b: int = m.S.cards.size()
	ok(n41b > n41, "41. Add after adds the copy's cards after the scene's (%d -> %d cards)" % [n41, n41b])
	ok(String(m.scene_path) == path41, "41. Add after keeps the scene's file (no new scene opened)")

	# 42. the copied cards' names, every card of the scene (the copy's run and the added run): "Video <n>", no jargon
	var bad42 := []
	var names42 := []
	for i in m.S.cards.size():
		var en := String(m._easy_card_name(String(m.S.cards[i]["name"]), i))
		names42.append(en)
		var jargon := en.begins_with("Pose ") or en.begins_with("Move ") or en.begins_with("v") or en.begins_with("pose ")
		if not en.begins_with("Video ") or jargon:
			bad42.append(en)
	ok(bad42.is_empty(), "42. every copied card reads 'Video <n>' in Easy (not: %s; names %s)" % [str(bad42), str(names42.slice(0, 4))])
	ok(names42.size() > 0 and names42[0] == "Video 1" and names42[-1] == "Video %d" % names42.size(), "42. the run is numbered 1..%d (first %s, last %s)" % [names42.size(), names42[0] if names42.size() > 0 else "-", names42[-1] if names42.size() > 0 else "-"])
	m._new_scene()
	await idle(4)

	# 55. THE COPY'S PROGRESS BAR (walk-through round, friction 6: no time left): while a copy runs, Easy shows a ProgressBar
	# (eh_copy_bar) whose value rises; "about N s left" (eh_copy_left) shows only once 10 % is done; the bar and its line go when
	# the copy finishes, and when the import bar's Cancel stops it
	m._new_scene()
	await idle(4)
	var bar55 := m.find_child("eh_copy_bar", true, false) as ProgressBar
	ok(bar55 != null, "55. Easy has the copy's progress bar (eh_copy_bar)")
	var vals55 := []
	var left_early := 0      # a frame with the 'left' line up below 10 %
	var left_seen := 0       # frames with the line up
	var two55 := 0           # frames with two progress figures (the copy's bar and main's step bar / percent)
	home.copy_video_file(fx)
	var t55 := Time.get_ticks_msec()
	while home._vid_busy and Time.get_ticks_msec() - t55 < 300000:
		await process_frame
		var b := m.find_child("eh_copy_bar", true, false) as ProgressBar
		var lf := m.find_child("eh_copy_left", true, false) as Label
		if b != null and b.is_visible_in_tree():
			vals55.append(b.value)
			var ib := m.find_child("import_bar", true, false) as ProgressBar
			var pct55 := RegEx.create_from_string("(\\d+)\\s*%").search(String(m.ui_status.text))
			if (ib != null and ib.is_visible_in_tree()) or (pct55 != null and absf(float(pct55.get_string(1)) - b.value) > 2.0):
				two55 += 1   # a second figure on screen: main's step bar, or words with another percent than the bar
			if lf != null and lf.is_visible_in_tree():
				left_seen += 1
				if b.value < 10.0:
					left_early += 1
				if left_seen == 3:   # mid-copy, the bar and the time left on screen (the walk-through's look)
					await process_frame
					get_root().get_texture().get_image().save_png(shot_dir + "/easy_vid_progress.png")
					print("55. screenshot mid-copy: %s (bar %.0f %%, %s)" % [shot_dir + "/easy_vid_progress.png", b.value, lf.text])
	var rises55 := vals55.size() > 2 and float(vals55[-1]) > float(vals55[0])
	var mono55 := true
	for i in range(1, vals55.size()):
		if float(vals55[i]) < float(vals55[i - 1]) - 0.001:
			mono55 = false
	ok(vals55.size() > 0, "55. the bar is visible while the copy runs (%d frames)" % vals55.size())
	ok(rises55 and mono55, "55. the bar's value rises (first %.1f, last %.1f, never back: %s)" % [float(vals55[0]) if vals55.size() > 0 else -1.0, float(vals55[-1]) if vals55.size() > 0 else -1.0, str(mono55)])
	ok(vals55.size() > 0 and two55 <= 2, "55. one progress figure on screen: main's step bar and percent stay hidden in Easy (%d of %d frames showed two)" % [two55, vals55.size()])
	ok(left_seen > 0, "55. 'about N s left' shows during the copy (%d frames)" % left_seen)
	ok(left_early == 0, "55. no 'left' line below 10 %% (%d frames early)" % left_early)
	await idle(8)
	var b55f := m.find_child("eh_copy_bar", true, false) as ProgressBar
	ok(b55f == null or not b55f.is_visible_in_tree(), "55. the bar is gone after the copy finished")
	# the cancel: a copy stopped by its Cancel takes the bar away too
	home.copy_video_file(fx)   # the scene has the copied cards, unsaved: the question comes first (section 41), Replace starts the copy
	await wait_ms(600)
	home.call("copy_choose", "replace")
	await wait_ms(1500)
	var cn55: Button = m._imp_cancel_btn   # the one Cancel on screen during a copy: main's import bar's (Easy's bar has none: easyvid test 10)
	var up55: bool = cn55 != null and cn55.is_visible_in_tree()
	ok(up55, "55. the copy's Cancel (the import bar's) is on screen while it runs")
	if up55:
		await click_ctl(cn55)
	var tc55 := Time.get_ticks_msec()
	while home._vid_busy and Time.get_ticks_msec() - tc55 < 60000:
		await process_frame
	await idle(8)
	var b55c := m.find_child("eh_copy_bar", true, false) as ProgressBar
	ok(not home._vid_busy and (b55c == null or not b55c.is_visible_in_tree()), "55. Cancel stops the copy and takes the bar away")
	m._new_scene()
	await idle(4)

	# 60. SAVE THE SCENE NAMES IT AFTER THE CLIP (walk-through round 7, goal 7): Walk, then Wave added after it, Save the scene from
	# Easy's More: the file is walk_then_wave (as its video is), not the first card's "walk"
	m._new_scene()
	await idle(2)
	home.card(0)
	await idle(4)
	home._change()   # Change it: the picker over the walk, Add after chosen (as section 11)
	await idle(4)
	home._then_add = true
	home.card(6)
	await idle(4)
	var had60 := FileAccess.file_exists(UserPaths.w("res://scenes/walk_then_wave.json"))
	home.save_scene()   # what More > Save the scene calls (easy_mode.gd)
	await idle(3)
	var f60 := String(m.scene_path).get_file()
	ok(f60 == "walk_then_wave.json", "60. Easy's Save the scene names the file after the clip (%s, clip '%s')" % [f60, home.clip_name()])
	ok(m.undo.size() == 60, "60. the undo stack is at its 60-step cap here (%d), so the names survive a full stack" % m.undo.size())
	if not had60 and f60 == "walk_then_wave.json":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(m.scene_path))
	m._new_scene()
	await idle(2)
	# 50. THE STRIP STAYS: a built clip, then an unknown typed line: the strip is on screen, the panel is not, and the status says why
	m._new_scene()
	await idle(4)
	await click_ctl(card_btn(0))
	await idle(6)
	ok(m.S.cards.size() == 8 and home.strip.visible and not home.panel.visible, "50. a walk is built: the strip shows, the panel is shut (cards %d)" % m.S.cards.size())
	home._words("jumping jack")
	await idle(6)
	ok(home.strip.visible and not home.panel.visible, "50. an unknown typed line keeps the strip (strip %s, panel %s)" % [str(home.strip.visible), str(home.panel.visible)])
	ok("doesn't know" in String(m.ui_status.text) and m.S.cards.size() == 8, "50. the refusal is in the status line, the clip unchanged (status '%s', cards %d)" % [m.ui_status.text, m.S.cards.size()])
	var keep_shot := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/easy_strip_kept.png"
	await RenderingServer.frame_post_draw
	var strip_img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(keep_shot.get_base_dir())
	if strip_img != null:
		strip_img.save_png(keep_shot)
		print("   strip screenshot: " + keep_shot)
	# Esc takes an open panel back to the strip (Change it opens it; Esc and a second Change it close it)
	home._change()
	await idle(4)
	ok(home.panel.visible, "50. Change it opens the panel over the built clip")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await idle(4)
	ok(not home.panel.visible and home.strip.visible, "50. Esc puts the strip back (panel %s, strip %s)" % [str(home.panel.visible), str(home.strip.visible)])
	home._change()
	await idle(4)
	home._change()
	await idle(4)
	ok(not home.panel.visible and home.strip.visible, "50. a second Change it puts the strip back")

	# 51. STAND UP: sit on a chair (the body seated), then typed "stand up then wave": cards are added; he ends standing
	m._new_scene()
	await idle(4)
	var stand0 := pelvis_y()
	m._prop_add("chair")
	await idle(4)
	var sit51 := home.panel.find_child("eh_sit", true, false) as Button
	if sit51 != null:
		sit51.pressed.emit()
	await idle(6)
	var seated51 := pelvis_y()
	var n51: int = m.S.cards.size()
	ok(n51 == 1 and seated51 < stand0 - 0.2, "51. seated on the chair: one sit card, pelvis %.3f m (standing %.3f m)" % [seated51, stand0])
	home._words("stand up then wave")
	await idle(8)
	var names51 := []
	for c in m.S.cards:
		names51.append(String(c.get("from", "")).split("|")[0])
	ok(m.S.cards.size() > n51 + 2 and (names51.has("stand up") or names51.has("stand_up")) and names51.back() == "wave", "51. 'stand up then wave' builds stand-up cards then the wave (cards %d, tags %s)" % [m.S.cards.size(), str(names51.slice(-1))])
	ok("doesn't know" not in String(m.ui_status.text), "51. no 'doesn't know' for stand up (status '%s')" % m.ui_status.text)
	# the clip's last card is the standing card: the playhead at the clip's end
	if m.playing:
		m._toggle_play()
	m.playhead = m.S.length()
	m._ps().apply(m.B, m.playhead)   # as a scrub does (the playhead alone does not pose the body)
	m._refresh()
	await idle(2)
	var stood51 := pelvis_y()
	print("   pelvis: standing %.3f, seated %.3f, after stand up %.3f" % [stand0, seated51, stood51])
	ok(absf(stood51 - stand0) < 0.04, "51. after the stand-up cards he is standing: pelvis %.3f, standing %.3f (within 4 cm)" % [stood51, stand0])

	# 52. THEN STAND UP: after the sit, the Then row's first button is "Then stand up"; its press builds the move
	m._new_scene()
	await idle(4)
	m._prop_add("chair")
	await idle(4)
	sit51 = home.panel.find_child("eh_sit", true, false) as Button
	if sit51 != null:
		sit51.pressed.emit()
	await idle(6)
	var then52 := home.strip.find_child("eh_next_0", true, false) as Button
	ok(then52 != null and then52.visible and then52.text == "Then stand up", "52. after a sit the Then row's first button reads 'Then stand up' (%s)" % (then52.text if then52 else "none"))
	var n52: int = m.S.cards.size()
	if then52 != null:
		await click_ctl(then52)
	await idle(8)
	ok(m.S.cards.size() > n52 and String(m.S.cards.back().get("from", "")).begins_with("stand_up|"), "52. 'Then stand up' adds the stand-up cards (%d -> %d)" % [n52, m.S.cards.size()])

	# 53. UNDO IN EASY: Walk, Then wave, Bigger; three Undos; each changes the cards (count or poses), the status names the step
	m._new_scene()
	await idle(4)
	await click_ctl(card_btn(0))
	await idle(6)
	home._words("wave")
	await idle(6)
	var eb53 := home.strip.find_child("eh_bigger", true, false) as Button
	if eb53 != null:
		await click_ctl(eb53)
	await idle(6)
	var states53 := [_cards_key()]
	var names53 := []
	for i in 3:
		var ub: Button = m.easy.button("Undo")
		if ub != null:
			await click_ctl(ub)
		await idle(6)
		states53.append(_cards_key())
		names53.append(String(m.ui_status.text))
	var moved := true
	for i in range(1, states53.size()):
		if states53[i] == states53[i - 1]:
			moved = false
	print("   undo states: %s" % str(names53))
	ok(moved, "53. each of the three Undos changes the cards (count or poses)")
	ok("took back" in String(names53[0]).to_lower() and "bigger" in String(names53[0]).to_lower(), "53. the first Undo names Bigger in the status: '%s'" % names53[0])
	ok("wave" in String(names53[1]).to_lower(), "53. the second Undo names the wave: '%s'" % names53[1])
	ok("walk" in String(names53[2]).to_lower(), "53. the third Undo names the walk: '%s'" % names53[2])

	# 70. SIT AFTER A WALK: a chair placed, a walk built, nothing picked: the strip offers one "Sit on the chair"; its press adds the sit
	# after the walk in one undo step, and the body ends seated (pelvis at least 0.2 m below standing)
	m._new_scene()
	await idle(4)
	m._prop_add("chair")
	await idle(4)
	m.sel_prop = -1
	m._props_show()
	await idle(2)
	home.card(0)
	await idle(6)
	if m.playing:
		m._toggle_play()
	m.playhead = 0.0   # the walk's first frame is standing: the reference height
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(2)
	var stand70 := pelvis_y()
	m.sel_prop = -1
	m._props_show()
	await idle(4)
	var sb70 := home.strip.find_child("eh_sit_strip", true, false) as Button
	var on70 := 0
	for b in home.strip.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and (b as Button).text.begins_with("Sit on"):
			on70 += 1
	var t70 := sb70.text if sb70 != null else "none"
	ok(home.strip.visible and sb70 != null and sb70.is_visible_in_tree() and t70 == "Sit on the chair" and on70 == 1, "70. a walk built, a chair placed, nothing picked: the strip offers one 'Sit on the chair' (strip %s, text '%s', sit buttons %d)" % [str(home.strip.visible), t70, on70])
	var n70: int = m.S.cards.size()
	var u70: int = m.undo.size()
	if sb70 != null:
		await click_ctl(sb70)
	await idle(8)
	ok(m.S.cards.size() > n70 and String(m.S.cards.back()["name"]).begins_with("sit on the chair"), "70. the press adds the sit after the walk (%d -> %d cards; last '%s')" % [n70, m.S.cards.size(), String(m.S.cards.back()["name"]) if not m.S.cards.is_empty() else ""])
	ok(m.undo.size() == u70 + 1, "70. the press is one undo step (undo stack %d -> %d)" % [u70, m.undo.size()])
	m.playing = false
	m.playhead = m.S.length()
	m._ps().apply(m.B, m.playhead)   # as a scrub does (the playhead alone does not pose the body)
	m._refresh()
	await idle(2)
	var seat70 := pelvis_y()
	ok(seat70 < stand70 - 0.2, "70. the body ends seated on the chair: pelvis %.3f m, standing %.3f m (drop %.3f m, at least 0.2)" % [seat70, stand70, stand70 - seat70])

	# 71. THE PROP BAR WITH NOTHING PICKED: a prop in the scene and none picked: the bar says how to pick it and names Remove
	m._new_scene()
	await idle(4)
	m._prop_add("chair")
	await idle(4)
	m.sel_prop = -1
	m._props_show()
	await idle(4)
	var bar71 := m.find_child("easy_prop_bar", true, false) as Control
	var name71 := m.find_child("eh_prop_name", true, false) as Label
	var t71 := name71.text if name71 != null else "none"
	ok(bar71 != null and bar71.visible and t71.contains("Click an object to pick it") and t71.contains("Remove"), "71. a prop in the scene, none picked: the bar reads how to pick it and names Remove ('%s')" % t71)

	# 72. LIBRARY CAPTIONS: the Furniture tab is one category: no tile repeats "Furniture" as a caption
	m._new_scene()
	await idle(2)
	m._library_toggle()
	await idle(4)
	var lib72 = m.ui_library
	lib72._search.text = ""   # the search of section 27 ("chair") is still in the box: the tab shows its own category
	lib72._on_search("")
	lib72.tab = ObjectLibrary.CATS.find("Furniture")
	lib72._rebuild()
	await idle(3)
	var tiles72 := 0
	var rep72 := 0
	var ph72 := 0
	for b in lib72._grid.get_children():
		if b is Button and b.has_meta("item"):
			tiles72 += 1
			for l in (b as Button).find_children("*", "Label", true, false):
				if (l as Label).text == "Furniture":
					rep72 += 1
				if l.name == "placeholder":
					ph72 += 1
	ok(tiles72 >= 4 and rep72 == 0, "72. the Furniture tab (%d tiles, %d still pending a picture): no tile repeats 'Furniture' (%d labels)" % [tiles72, ph72, rep72])
	m._library_toggle()
	await idle(4)

	# 73. SIT AFTER A PICKED CARD: a card picked in the middle of the walk, then "Sit on the chair": the sit goes after the last card
	m._new_scene()
	await idle(4)
	m._prop_add("chair")
	await idle(4)
	m.sel_prop = -1
	m._props_show()
	home.card(0)
	await idle(6)
	if m.playing:
		m._toggle_play()
	m._card_pick(0)
	await idle(3)
	m.sel_prop = -1
	m._props_show()
	await idle(4)
	var sb73 := home.strip.find_child("eh_sit_strip", true, false) as Button
	var n73: int = m.S.cards.size()
	if sb73 != null:
		await click_ctl(sb73)
	await idle(8)
	ok(sb73 != null and m.S.cards.size() > n73 and String(m.S.cards.back()["name"]).begins_with("sit on the chair") and m.sel_card == m.S.cards.size() - 1, "73. a card picked at the walk's start: the sit is still the last card (%d -> %d; picked %d)" % [n73, m.S.cards.size(), m.sel_card])
	# 75-79. THE SCRUB: a slider in the strip, hidden on an empty scene, shown once a clip is built
	m._new_scene()
	await idle(4)
	var sc75 := home.strip.find_child("eh_scrub", true, false) as HSlider
	ok(sc75 != null and not sc75.is_visible_in_tree(), "75. the scrub is hidden on an empty scene (slider %s)" % ("none" if sc75 == null else str(sc75.is_visible_in_tree())))
	await click_ctl(card_btn(0))
	await idle(6)
	sc75 = home.strip.find_child("eh_scrub", true, false) as HSlider
	var len75: float = m._ps().length()
	ok(sc75 != null and sc75.is_visible_in_tree() and home.strip.visible, "75. after a walk the scrub shows in the strip (slider %s)" % ("none" if sc75 == null else str(sc75.is_visible_in_tree())))
	if sc75 != null:
		ok(sc75.get_global_rect().size.y >= 28.0, "79. the slider is at least 28 px tall (%.0f px)" % sc75.get_global_rect().size.y)
	else:
		ok(false, "79. the slider is at least 28 px tall (no slider)")
	# 76. a real press at the slider's middle while the walk plays: the play stops, the body poses at half the clip
	if not m.playing:
		m._toggle_play()
	var played76 := await wait_playing()
	if sc75 != null and played76:
		var r76 := sc75.get_global_rect()
		await click_at(Vector2(r76.position.x + r76.size.x * 0.5, r76.get_center().y))
		await idle(4)
		var v76: float = sc75.value
		await RenderingServer.frame_post_draw
		var shot76 := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/easy_scrub.png"
		DirAccess.make_dir_recursive_absolute(shot76.get_base_dir())
		var img76 := root.get_texture().get_image()
		if img76 != null:
			img76.save_png(shot76)
			print("   scrub screenshot: " + shot76)
		ok(not m.playing and absf(v76 - len75 * 0.5) < 0.03 * len75, "76. a press at the middle stops the play and sets the time to half the clip (%.2f s of %.2f s; playing %s)" % [v76, len75, str(m.playing)])
		var got76: Vector3 = (m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5
		m._ps().apply(m.B, v76)   # the same pose a scrub to that time gives
		var want76: Vector3 = (m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5
		m._ps().apply(m.B, 0.0)
		var start76: Vector3 = (m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5
		ok(got76.distance_to(want76) < 0.005 and got76.distance_to(start76) > 0.01, "76. the body stands at that time: pelvis %s, the pose at %.2f s %s, the start %s" % [str(got76), v76, str(want76), str(start76)])
		m._ps().apply(m.B, v76)
		m._refresh()
	else:
		ok(false, "76. a press at the middle stops the play and sets the time to half the clip (no slider or no play)")
		ok(false, "76. the body stands at that time (no slider or no play)")
	# 77. playing moves the slider (its value follows the playhead)
	if sc75 != null:
		if not m.playing:
			m._toggle_play()
		await wait_playing()
		var va77: float = sc75.value
		await idle(20)
		var vb77: float = sc75.value
		ok(vb77 > va77 + 0.05 and absf(vb77 - clampf(m.playhead, 0.0, len75)) < 0.05, "77. while playing the slider moves with the playhead (%.2f -> %.2f s, playhead %.2f s)" % [va77, vb77, m.playhead])
		if m.playing:
			m._toggle_play()
		# 78. the label: "t s / len s"
		var lbl78 := home.strip.find_child("eh_scrub_time", true, false) as Label
		var parts78 := lbl78.text.split(" s / ") if lbl78 != null else PackedStringArray()
		ok(parts78.size() == 2 and absf(float(parts78[0]) - sc75.value) < 0.1 and lbl78.text.ends_with("%.1f s" % len75), "78. the label reads 'time s / length s': '%s' (slider %.2f, length %.2f)" % [lbl78.text if lbl78 != null else "none", sc75.value, len75])
	else:
		ok(false, "77. while playing the slider moves with the playhead (no slider)")
		ok(false, "78. the label reads 'time s / length s' (no slider)")

	# 80. THE TOAST CLEARS THE SLIDER: a walk, Undo ('Took back: Walk' toast), a new walk at once: no toast covers the scrub row; the
	# slider's track is drawn (its own 'slider' style, not the panel colour)
	m._new_scene()
	await idle(2)
	home.card(0)
	await idle(4)
	m._undo()   # 'Took back: Walk': the toast is up, the strip and its slider gone
	await idle(2)
	home.card(0)   # a new walk while the toast is still up: the strip and the slider come back under it (the screenshot's case)
	await idle(4)
	var row80 := home._scrub_row.get_global_rect()
	var toast80: Rect2 = m.ui_toast.get_global_rect() if m.ui_toast != null and m.ui_toast.visible else Rect2()
	var hit80 := row80.intersection(toast80)
	ok(home._scrub_row.is_visible_in_tree() and (hit80.size.x < 1.0 or hit80.size.y < 1.0),
		"80. no toast ('%s' at %s) covers the scrub row (%s)" % [m.ui_toast.text if m.ui_toast != null else "", str(toast80), str(row80)])
	ok(home._scrub.has_theme_stylebox_override("slider"), "80. the slider's whole track is drawn (a 'slider' style of its own)")
	m._new_scene()
	await idle(2)

	# 85-87. WALK TO THE CHAIR AND SIT (round 8, goal 1): a walk built, a chair 2 m past where the walk ends (its front faces the
	# walk's end), the strip's "Sit on the chair" pressed. The body walks to the stand point in front of the chair, then sits.
	m._new_scene()
	await idle(4)
	home.card(0)
	await idle(6)
	if m.playing:
		m._toggle_play()
	m.playhead = 0.0
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(2)
	var stand85 := pelvis_y()
	m.playhead = m.S.length()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(2)
	var end85: Vector3 = m.B.P["pelvis"]
	m._prop_add("chair")
	await idle(4)
	var pc85: Dictionary = m.S.props[m.sel_prop]
	var xf85: Transform3D = pc85["xf"]
	xf85.basis = Basis(Vector3.UP, -PI * 0.5)   # the chair's front (+Z) turned to face back along -X, toward the walker
	xf85.origin = Vector3(end85.x + 2.0, xf85.origin.y, end85.z)
	pc85["xf"] = xf85
	m._refresh()
	await idle(4)
	var sb85 := home.strip.find_child("eh_sit_strip", true, false) as Button
	var n85: int = m.S.cards.size()
	var u85: int = m.undo.size() + m.undo_dropped   # the depth (the stack stops at 60 steps)
	if sb85 != null:
		await click_ctl(sb85)
	await idle(8)
	ok(sb85 != null and m.S.cards.size() > n85 + 1, "85. the press adds the walk to the chair and the sit (%d -> %d cards)" % [n85, m.S.cards.size()])
	ok(m.undo.size() + m.undo_dropped == u85 + 1, "85. the press is one undo step (undo depth %d -> %d)" % [u85, m.undo.size() + m.undo_dropped])
	# (a) the root's horizontal path, sampled as the app scrubs it every 1/30 s: no frame-to-frame jump above 0.15 m
	var L85: float = m.S.length()
	var worst85 := 0.0
	var prev85 := Vector2.ZERO
	var t85 := 0.0
	var first85 := true
	var t0_85: float = float(m.S.times()[n85 - 1][1])   # the walk's end: from here he goes to the chair
	var path85 := 0.0
	var feet85 := {}      # the previous frame's ball positions
	var glide85 := []     # per moving frame: the slower foot's horizontal speed / the hips' (walking: a planted foot, ~0; gliding: ~1)
	m.playing = false
	while t85 <= L85 + 1e-6:
		m.playhead = t85
		m._ps().apply(m.B, t85)
		m._refresh()
		var pp85: Vector3 = m.B.P["pelvis"]
		var xz85 := Vector2(pp85.x, pp85.z)
		if not first85:
			worst85 = maxf(worst85, xz85.distance_to(prev85))
			if t85 > t0_85:
				path85 += xz85.distance_to(prev85)
		if t85 > t0_85 and not first85 and feet85.size() == 2:
			var hip_d: float = xz85.distance_to(prev85)
			if hip_d * 30.0 > 0.3:   # the hips moving faster than 0.3 m/s
				var fd := []
				for bk in ["ball_l", "ball_r"]:
					var bp: Vector3 = m.B.P[bk]
					fd.append(Vector2(bp.x, bp.z).distance_to(feet85[bk]))
				glide85.append(minf(fd[0], fd[1]) / hip_d)
		for bk in ["ball_l", "ball_r"]:
			var bq: Vector3 = m.B.P[bk]
			feet85[bk] = Vector2(bq.x, bq.z)
		first85 = false
		prev85 = xz85
		t85 += 1.0 / 30.0
	ok(worst85 <= 0.15, "85. the root's horizontal path is continuous: the largest jump between frames is %.3f m over %.1f s (at most 0.15)" % [worst85, L85])
	var g85 := 0.0
	for g in glide85:
		g85 += float(g)
	g85 = g85 / maxf(1.0, float(glide85.size()))
	ok(path85 >= 0.5 and glide85.size() >= 10 and g85 < 0.5, "85. he WALKS to the chair, not glides: hips travel %.2f m after the walk; the slower foot moves %.2f x the hips on average over %d moving frames (under 0.5: a foot is planted; a glide is ~1)" % [path85, g85, glide85.size()])
	# (b) the clip's end: seated on the chair
	m.playhead = L85
	m._ps().apply(m.B, L85)
	m._refresh()
	await idle(2)
	var pe85: Vector3 = m.B.P["pelvis"]
	var seat85 := Rise.seat_of(m.S.props[m.sel_prop])
	var dh85 := Vector2(pe85.x - seat85.x, pe85.z - seat85.z).length()
	var drop85 := stand85 - pelvis_y()
	ok(dh85 <= 0.15 and drop85 >= 0.2, "86. the end is seated: the pelvis %.3f m from the seat (at most 0.15), %.3f m below standing (at least 0.2)" % [dh85, drop85])
	# (c) one Undo gives back the walk's cards
	m._undo()
	await idle(4)
	ok(m.S.cards.size() == n85, "87. one Undo returns to the walk's card count (%d, was %d before the press)" % [m.S.cards.size(), n85])
	m._new_scene()
	await idle(2)

	# 105. A REFUSED LINE IS SELECTED, NOT GLUED (walk-through round 8, friction 3): "dance" is refused and the box keeps its word,
	# selected, so the next keystrokes replace it. "punch" typed after it builds a punch, and no card name says "dance".
	# Old code: the refused word stayed unselected, so the insertion glued on ("dancepunch").
	m._new_scene()
	await idle(3)
	home._change()
	await idle(2)
	edit.text = "dance"
	edit.text_submitted.emit("dance")
	await idle(3)
	var sel105 := edit.has_selection() and edit.get_selected_text() == "dance"
	if edit.has_selection():   # a keystroke over a selection deletes it first (insert_text_at_caret does not), then goes at the caret
		var f105 := edit.get_selection_from_column()
		edit.text = edit.text.substr(0, f105) + edit.text.substr(edit.get_selection_to_column())
		edit.caret_column = f105
	edit.insert_text_at_caret("punch")   # the keystrokes of "punch" in the box
	var typed105 := edit.text
	edit.text_submitted.emit(typed105)
	await idle(4)
	var dance105 := false
	for c in m.S.cards:
		if "dance" in String(c["name"]).to_lower():
			dance105 = true
	ok(sel105 and typed105 == "punch" and not m.S.cards.is_empty() and not dance105,
		"105. after 'dance' is refused its word is selected (%s), typing 'punch' gives box '%s' and builds %d card(s), none named dance (%s)"
		% [sel105, typed105, m.S.cards.size(), str(m.S.cards.map(func(c): return c["name"]))])

	# 106. THE REFUSAL OFFERS THE CLOSEST MOVES (round 8, friction 5): "sit dwn" is refused; at least three try buttons show, the first is
	# "Sit down" (the card word closest to what was typed), and its press builds the sit down (one undo step).
	# Old code: the same four buttons (Punch, Kick, Wave, Walk) for every refusal, and no Sit down button at all.
	m._new_scene()
	await idle(3)
	home._change()
	await idle(2)
	edit.text = "sit dwn"
	edit.text_submitted.emit("sit dwn")
	await idle(3)
	var why106 := (home.panel.find_child("eh_msg", true, false) as Label).text
	var shown106: Array = []
	for c in home._try_row.get_children():
		if c is Button and (c as Button).visible:
			shown106.append(c)
	var names106 := []
	for b in shown106:
		names106.append((b as Button).text)
	var c106: int = m.S.cards.size()
	var u106: int = m.undo.size()
	var shot106 := "user://easy_refusal.png"   # the refusal with its try buttons, for the report (before the press)
	m.get_viewport().get_texture().get_image().save_png(shot106)
	print("screenshot %s" % ProjectSettings.globalize_path(shot106))
	var pressed106 := false
	if shown106.size() > 0:
		(shown106[0] as Button).pressed.emit()
		pressed106 = true
	await idle(3)
	ok(why106 == "Kine doesn't know 'sit dwn' yet." and shown106.size() >= 3 and names106[0] == "Sit down",
		"106. the refusal shows >= 3 try buttons, the closest first (sentence '%s', buttons %s)" % [why106, str(names106)])
	ok(pressed106 and m.S.cards.size() > c106 and m.undo.size() == mini(u106 + 1, 60) and m.S.cards.any(func(c): return "seated" in String(c["name"]).to_lower()),
		"106. pressing the first try button builds its move: cards %d -> %d, undo %d -> %d, names %s, pressed %s" % [c106, m.S.cards.size(), u106, m.undo.size(), str(m.S.cards.map(func(c): return c["name"])), pressed106])
	m._new_scene()
	await idle(2)

	# the end: Expert puts it all back
	m.easy.set_on(false, false)
	await idle()
	ok(home.shown() == "hidden", "Expert hides the panel and strip again")
	print("timings: " + str(times))
	print("card ms (click -> first moving frame): " + ", ".join(fast_ms))
	print("EASYHOME TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
