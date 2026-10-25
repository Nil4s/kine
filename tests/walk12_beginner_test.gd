## godot --path . -s tests/walk12_beginner_test.gd   (BEGINNER WALK-THROUGH, round 12: EASY mode, real clicks and drags only)
## The six goals a non-technical person would try with today's features:
## 1 My scenes -> the "Fight" chip -> open a Good-badged scene (badges may take up to 20 s);
## 2 star a scene, Close, My scenes again, "★ Favourites": the starred one is there;
## 3 Library -> Weapons -> sword (in his hand), pick the left hand, "Free left hand", drag it: it moves, the weapon does not follow;
## 4 "Flip blade": the blade's face turns to the other side (~180 deg; measured before/after);
## 5 drag the left elbow with "Only this part" on: nothing else on the body turns more than 1 deg;
## 6 Undo three times: each Undo changes the body or the weapon (never a no-op).
## Only what a beginner sees: buttons by their words, the view by a click or a drag at the part's screen point. Reads of state are
## for the checks and the numbers only. Prints "GOAL n: PASS|FRICTION - what happened (clicks k, s seconds)". Exits 0.
## Screenshots: C:/Temp/claude/w12/walk12_<n>.png.
extends SceneTree

const OUT := "C:/Temp/claude/w12/"

var video_dir := ""
var m: Node
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""
var notes: Array = []
var gbase := 0
var results: Array = []


func say(s: String) -> void:
	print(s)
	lines.append(s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):   # INTERNAL children too: a dialog's button row is internal
		walk(c, out)
	return out


## the visible CanvasItems under a node (the whole window when scope is the root)
func vis_under(scope: Node) -> Array:
	var out := []
	for n in walk(scope, []):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func labels_of(b: Button) -> Array:
	var out := [text_of(b)]
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges())
	return out


## the first visible button under scope that reads txt (prefix: begins with txt)
func btn_in(scope: Node, txt: String, prefix := false) -> Button:
	for n in vis_under(scope):
		if n is Button:
			for t in labels_of(n as Button):
				if t == txt or (prefix and String(t).begins_with(txt)):
					return n
	return null


func find_btn(txt: String, prefix := false) -> Button:
	return btn_in(root, txt, prefix)


func visible_words() -> String:
	var out := []
	for n in vis_under(root):
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges())
	return str(out)


func btn_names() -> String:
	var out := []
	for n in vis_under(root):
		if n is Button and text_of(n as Button) != "":
			out.append(text_of(n as Button))
	return str(out)


func mouse_btn(down: bool, p: Vector2, which := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = which
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


func hit_name() -> String:
	var h := get_root().get_viewport().gui_get_hovered_control()
	return "none" if h == null else str(h.name) + " (" + h.get_class() + ")"


## a real click on a Control: the mouse goes down and up on its middle
func click_ctl(c: Control) -> bool:
	var r := c.get_global_rect()
	var w := c.get_window()
	if w != null and w != get_root():
		r.position += Vector2(w.position)
	var p := r.get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		say("   COVERED: the click at %s lands on %s, not on the button" % [str(p), hit_name()])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return inside


## a click on the first visible button with these words (the words a beginner reads on it), anywhere or under scope
func click_text(txt: String, prefix := false, scope: Node = null) -> bool:
	var b: Button = btn_in(scope if scope != null else root, txt, prefix)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s'" % txt)
		return false
	clicks += 1
	say("   click '%s' (tooltip: '%s')" % [text_of(b), b.tooltip_text])
	return await click_ctl(b)


## a real press on a view point: down, up
func click_view(p: Vector2) -> void:
	clicks += 1
	await hover(p)
	say("   click in the view at %s (under the pointer: %s)" % [str(p), hit_name()])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(4)


## a real drag in the view: press at p, move in six steps by d, let go at p + d
func drag_view(p: Vector2, d: Vector2) -> void:
	clicks += 1
	await hover(p)
	say("   drag from %s by %s (under the pointer: %s)" % [str(p), str(d), hit_name()])
	var st := d / 6.0
	mouse_btn(true, p)
	await process_frame
	for k in 6:
		var q := p + st * float(k + 1)
		var mv := InputEventMouseMotion.new()
		mv.position = q
		mv.global_position = q
		mv.relative = st
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mv)
		await process_frame
	mouse_btn(false, p + d)
	await idle(4)


## true when another control sits on the button's middle (a hover, no click): the beginner cannot press it there
func covered(c: Control) -> bool:
	var r := c.get_global_rect()
	var w := c.get_window()
	if w != null and w != get_root():
		r.position += Vector2(w.position)
	var p := r.get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside:
		say("   COVERED: the button '%s' at %s: the pointer there is on %s" % [text_of(c as Button) if c is Button else c.name, str(p), hit_name()])
	return not inside


func status_now() -> String:
	var s := ""
	if m.ui_status != null:
		s = m.ui_status.text
	var h = m.easy.home
	var msg := ""
	if h != null and h._msg != null:
		msg = String(h._msg.text)
	return "status line: '%s' | Easy message: '%s'" % [s, msg]


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


func shot(n: int, what: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	var f := OUT + "walk12_%d.png" % n
	root.get_texture().get_image().save_png(f)
	say("   screenshot %s (%s) | cards: %d | clip %.2f s | playing: %s" % [f, what, m.S.cards.size(), m.S.length(), str(m.playing)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())
	say("   %s" % status_now())


func start_goal(n: int, s: String) -> void:
	goal = "GOAL %d" % n
	clicks = 0
	t0 = Time.get_ticks_msec()
	gbase = notes.size()
	say("\n== GOAL %d: %s ==" % [n, s])


func note(s: String) -> void:
	notes.append("[%s] %s" % [goal, s])
	say("   FRICTION: " + s)


func finish(n: int, ok: bool, what: String) -> void:
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var fr := (not ok) or notes.size() > gbase
	say("GOAL %d: %s - %s (clicks %d, %.1f s)" % [n, "FRICTION" if fr else "PASS", what, clicks, secs])
	results.append([n, not fr, clicks, secs])


func wait_for_cond(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await process_frame
	return false


## the clip plays by itself after a build or a load: wait until it has stopped (or never started)
func settle(limit := 1200) -> void:
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


## a body part's screen point (the middle of its capsule, projected by the camera)
func scr(part: String) -> Vector2:
	return m.cam.unproject_position(mid(part))


## the capsule direction of a part (ankle to toe, shoulder to elbow...), normalised; zero when missing
func dir_of(part: String) -> Vector3:
	var c: Array = m.B.cap(part)
	if c.size() < 2:
		return Vector3.ZERO
	return ((c[1] as Vector3) - (c[0] as Vector3)).normalized()


func angle_between(a: Vector3, b: Vector3) -> float:
	if a.length() < 1e-6 or b.length() < 1e-6:
		return 0.0
	return rad_to_deg(acos(clampf(a.dot(b), -1.0, 1.0)))


## the weapon: its knob (world) and its face direction (the blade's local +Z turned into the world)
func wep_knob() -> Vector3:
	return (m.B.wep_xform()[0] as Vector3)


func wep_face() -> Vector3:
	return (m.B.wep_xform()[1] as Quaternion) * Vector3(0, 0, 1)


func wep_axis() -> Vector3:
	return m.B.wep_axis()


func scenes_node() -> Node:
	return m.easy.scenes


## the chips row of My scenes (its chip words must not match a tile's name)
func chip_scope() -> Node:
	return scenes_node().find_child("easy_scenes_chips", true, false)


## a visible tile button (name tile_*) whose badge label reads Good, or null
func good_tile() -> Button:
	for n in vis_under(scenes_node()):
		if n is Label and (n as Label).name == "badge" and (n as Label).text == "Good":
			var p = (n as Node).get_parent()
			while p != null and not (p is Button and String(p.name).begins_with("tile_")):
				p = p.get_parent()
			if p != null:
				return p
	return null


## the big name label of a tile button (the scene's name)
func tile_name_of(b: Node) -> String:
	for n in walk(b, []):
		if n is Label and (n as Label).name == "name":
			return (n as Label).text
	return ""


func badges_now() -> String:
	var out := []
	for n in vis_under(scenes_node()):
		if n is Label and (n as Label).name == "badge":
			out.append((n as Label).text)
	return str(out)


func tile_buttons_shown() -> Array:
	var out := []
	for n in vis_under(scenes_node()):
		if n is Button and String((n as Button).name).begins_with("tile_"):
			out.append(n)
	return out


func shown_names() -> Array:
	var out := []
	for b in tile_buttons_shown():
		out.append(tile_name_of(b))
	return out


## the Library's tile whose name label holds a word (the Library's own buttons are named tile_*)
func lib_tile(word: String) -> Button:
	if m.ui_library == null:
		return null
	for n in vis_under(m.ui_library):
		if n is Button and String((n as Button).name).begins_with("tile_"):
			var nm := tile_name_of(n).to_lower()
			for t in labels_of(n as Button):
				if String(t).to_lower().contains(word):
					return n
			if nm.contains(word):
				return n
	return null


func fingerprint() -> String:
	return "%d|%s|%s|%s|%d" % [hash(str(m.B.state())), str(m.B.wep_on), str(m.B.wep_hand), str(wep_knob()), m.S.cards.size()]


func _init() -> void:
	EasyMode.start_fresh = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	video_dir = ProjectSettings.globalize_path("user://walk12_out_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(video_dir)
	m.easy.home.video_root = video_dir
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if not m.easy.on:
		m.easy.set_on(true)
		await idle(10)
		say("   forced Easy (set_on(true)) | Easy now: %s" % str(m.easy.on))
	say("start: cards %d | words: %s" % [m.S.cards.size(), visible_words()])
	say("start: buttons %s" % btn_names())

	# 1. MY SCENES -> FIGHT -> A GOOD SCENE
	start_goal(1, "My scenes, the Fight chip, open a Good-badged scene")
	var ms1: bool = await click_text("My scenes")
	await idle(20)
	var fight_ok := false
	if ms1 and scenes_node().visible:
		fight_ok = await click_text("Fight", true, chip_scope())
	await idle(10)
	say("   tiles shown after Fight: %s" % str(shown_names()))
	var gt: Button = null
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 20000:
		gt = good_tile()
		if gt != null:
			break
		await process_frame
	say("   badges after %.1f s: %s" % [(Time.get_ticks_msec() - t1) / 1000.0, badges_now()])
	var built1 := false
	var gname := ""
	if gt == null:
		note("no Good badge on any Fight scene after 20 s (badges on screen: %s); the Fight chip is %s" % [badges_now(), "pressed" if fight_ok else "not found"])
	else:
		gname = tile_name_of(gt)
		say("   the Good scene: '%s' (tooltip '%s')" % [gname, gt.tooltip_text])
		await shot(10, "My scenes, Fight, Good badge")
		await click_ctl(gt)
		clicks += 1
		built1 = await wait_for_cond(func(): return m.S.cards.size() >= 1 and String(m.scene_path).get_file().get_basename().replace("_", " ").to_lower() == gname.to_lower(), 600)
		await settle()
	await shot(1, "after the Good scene opened")
	if not built1 and gt != null:
		note("clicking the Good scene '%s' did not open it (scene file: '%s', cards %d)" % [gname, String(m.scene_path), m.S.cards.size()])
	finish(1, built1, "Fight chip %s; %s; opened '%s' with %d cards, clip %.2f s" % ["pressed" if fight_ok else "NOT found", "Good scene found" if gt != null else "no Good scene", gname, m.S.cards.size(), m.S.length()])

	# 2. STAR A SCENE, CLOSE, REOPEN, FAVOURITES
	start_goal(2, "star a scene, close My scenes, reopen, ★ Favourites")
	if not scenes_node().visible:
		await click_text("My scenes")
	await idle(20)
	await click_text("All", true, chip_scope())
	await idle(10)
	var star_btn: Button = null
	var starred := ""
	for b in tile_buttons_shown():
		for n in walk(b, []):
			if n is Button and (n as Button).name == "star":
				star_btn = n
				break
		if star_btn != null:
			starred = tile_name_of(b)
			break
	var star_ok: bool = false
	var star_clicked: bool = false
	if star_btn == null:
		note("no star button on any scene tile")
	else:
		say("   starring '%s' (its star reads '%s', tooltip '%s')" % [starred, star_btn.text, star_btn.tooltip_text])
		star_ok = await click_ctl(star_btn)
		star_clicked = star_ok
		clicks += 1
		await idle(5)
		if star_btn.text != "★":
			note("after the click the star still reads '%s' (not starred); status: %s" % [star_btn.text, status_now()])
	await shot(2, "scene starred")
	await click_text("Close", false, scenes_node())
	await idle(10)
	await click_text("My scenes")
	await idle(20)
	var fav_chip_ok: bool = await click_text("★ Favourites", true, chip_scope())
	await idle(10)
	var there: bool = false
	for nm in shown_names():
		if String(nm).to_lower() == starred.to_lower():
			there = true
	say("   after ★ Favourites, tiles shown: %s" % str(shown_names()))
	if not there and starred != "":
		note("the starred scene '%s' is not under ★ Favourites (shown: %s)" % [starred, str(shown_names())])
	await shot(3, "Favourites chip")
	finish(2, star_clicked and there and fav_chip_ok, "starred '%s' -> in ★ Favourites: %s" % [starred, str(there)])

	# 3. A WEAPON IN HIS HAND, FREE THE LEFT HAND, DRAG IT: THE WEAPON STAYS
	start_goal(3, "Library: a sword in his hand, pick the left hand, Free left hand, drag the hand")
	await click_text("Close", false, scenes_node())
	await idle(10)
	var lib_ok: bool = await click_text("Library")
	await idle(15)
	var wk: bool = await click_text("Weapons", true, m.ui_library)
	await idle(20)
	var sw := lib_tile("sword")
	var got3 := false
	if sw == null:
		note("no sword tile in Library > Weapons (tiles: %s)" % btn_names())
	else:
		say("   click the tile '%s'" % str(labels_of(sw)))
		clicks += 1
		await click_ctl(sw)
		await idle(15)
		got3 = m.B.wep_on
	say("   hand now: wep_on %s, kind %s, hand %s | '%s'" % [str(m.B.wep_on), str(m.B.wep_kind), str(m.B.wep_hand), status_now()])
	if not m.B.wep_on:
		note("the sword tile did not put a sword in his hand (%s)" % status_now())
	if lib_ok:
		await click_text("Library")   # the Library's bar button shuts the panel
		await idle(15)
	say("   words after the Library: %s" % visible_words())
	if m.B.wep_on and not visible_words().contains("In his hand"):
		note("the prop bar does not say 'In his hand' once the sword is in his hand (words: %s)" % visible_words())
	await shot(4, "sword in hand")
	# pick the left hand: a click on it in the view
	await idle(60)   # the view settles after the Library shuts (the hand's screen point moved while it did)
	var hl0: Vector3 = mid("hand_l")
	var hp: Vector2 = scr("hand_l")
	say("   hand_l before the pick: screen %s, world %s" % [str(hp), str(mid("hand_l"))])
	await click_view(hp)
	say("   hand_l after the pick: screen %s, world %s" % [str(scr("hand_l")), str(mid("hand_l"))])
	await idle(10)
	say("   picked: sel %s | hands panel visible %s" % [str(m.sel), str(m.ui_hands_panel.visible)])
	var fl := find_btn("Free left hand")
	var freed: bool = false
	var hand_moved := 0.0
	var knob_moved := 0.0
	var knob0: Vector3 = wep_knob()
	var hl_pre: Vector3 = mid("hand_l")
	if fl == null:
		note("no 'Free left hand' button after picking the left hand (hands panel visible: %s, sel %s)" % [str(m.ui_hands_panel.visible), str(m.sel)])
	else:
		freed = await click_text("Free left hand")
		await idle(10)
		say("   after Free left hand: grip %s, free_hand %s | '%s'" % [str(m.B.grip), str(m.B.free_hand), status_now()])
		if m.B.grip:
			note("'Free left hand' did nothing: the weapon is still held by both hands (grip on; %s)" % status_now())
	# drag the left hand 150 px to the left (outward in the view)
	var hp2: Vector2 = scr("hand_l")
	await drag_view(hp2, Vector2(-150, 0))
	await idle(10)
	hand_moved = mid("hand_l").distance_to(hl_pre) * 100.0
	knob_moved = wep_knob().distance_to(knob0) * 100.0
	say("   left hand moved %.1f cm | weapon knob moved %.2f cm | weapon hand: %s | free_hand %s" % [hand_moved, knob_moved, str(m.B.wep_hand), str(m.B.free_hand)])
	if hand_moved < 5.0:
		note("dragging the left hand moved it only %.1f cm" % hand_moved)
	if knob_moved >= 1.0:
		note("the weapon moved %.1f cm when the left hand was dragged (it should stay in the right hand)" % knob_moved)
	await shot(5, "left hand dragged, weapon stays")
	var ok3: bool = m.B.wep_on and freed and hand_moved >= 5.0 and knob_moved < 1.0
	finish(3, ok3, "sword in hand %s; left hand freed %s; left hand moved %.1f cm, weapon moved %.2f cm" % [str(m.B.wep_on), str(freed), hand_moved, knob_moved])

	# 4. FLIP BLADE: the head turns to the other side
	start_goal(4, "Flip blade: the blade's face turns about 180 deg")
	var face0: Vector3 = wep_face()
	var axis0: Vector3 = wep_axis()
	var fb := find_btn("Flip blade")
	var flip_turn := 0.0
	var axis_turn := 0.0
	if fb != null and await covered(fb):
		note("'Flip blade' is under the 'What should he do?' picker (the hands panel is behind it): the beginner cannot press it")
		await click_text("Walk")   # the beginner's way out: a move closes the picker
		await settle()   # the walk plays: measure only when it has stopped
		fb = find_btn("Flip blade")
		face0 = wep_face()
		axis0 = wep_axis()
	if fb == null:
		note("no 'Flip blade' button on screen (hands panel visible: %s, sel %s, words: %s)" % [str(m.ui_hands_panel.visible), str(m.sel), visible_words()])
	else:
		var turn0 := rad_to_deg(m.B.wep_turn)
		await click_text("Flip blade")
		var playing_after_flip: bool = m.playing
		var face_now_: Vector3 = wep_face()
		var tl := []
		for c in m.S.cards:
			var pw = c.get("pose", {}).get("wep", {})
			tl.append("%s:%s" % [str(c.get("name", "?")), str(rad_to_deg(float(pw.get("turn", 0.0))))] if pw is Dictionary else "?")
		say("   cards after the flip (name:stored blade turn deg): %s | playhead %.2f | card at playhead %d" % [str(tl), m.playhead, LimbIK.card_at(m.S, m.playhead)])
		say("   right after the flip: stored blade turn %.0f -> %.0f deg | face turned %.0f deg | playing: %s" % [turn0, rad_to_deg(m.B.wep_turn), angle_between(face0, face_now_), str(playing_after_flip)])
		flip_turn = angle_between(face0, face_now_)
		axis_turn = angle_between(axis0, wep_axis())
		await settle()   # then the clip plays on: what the beginner sees at the end
		say("   after the clip has played: stored turn %.0f deg | face turned %.0f deg" % [rad_to_deg(m.B.wep_turn), angle_between(face0, wep_face())])
		say("   blade face turned %.0f deg, handle axis turned %.1f deg | '%s'" % [flip_turn, axis_turn, status_now()])
	await shot(6, "after Flip blade")
	if fb != null and absf(flip_turn - 180.0) > 20.0:
		note("'Flip blade' turns the blade face %.0f deg, not about 180" % flip_turn)
	finish(4, fb != null and absf(flip_turn - 180.0) <= 20.0, "blade face turned %.0f deg (axis %.1f deg)" % [flip_turn, axis_turn])

	# 5. ONLY THIS PART: drag the left elbow; nothing else turns more than 1 deg
	start_goal(5, "Only this part (on): drag the left elbow, nothing else turns more than 1 deg")
	var ob := find_btn("Only this part")
	if ob != null and await covered(ob):
		note("'Only this part' is under the 'What should he do?' picker: the beginner cannot reach it there")
		await click_text("Walk")
		await settle()
		ob = find_btn("Only this part")
	var was_on := ob != null and ob.button_pressed
	say("   'Only this part' is %s" % ("on" if was_on else "off"))
	if ob == null:
		note("no 'Only this part' button on screen (hands panel: %s)" % str(m.ui_hands_panel.visible))
	elif not was_on:
		note("'Only this part' is off at the start (the beginner must turn it on)")
		await click_text("Only this part")
	var parts: Array = m.B.cap0.keys()
	var chain := []
	for p in parts:
		var ps := String(p)
		if ps.ends_with("_l") and (ps.contains("arm") or ps.contains("hand") or ps.contains("thumb") or ps.contains("index") or ps.contains("middle") or ps.contains("ring") or ps.contains("pinky") or ps.contains("little")):
			chain.append(ps)
	say("   parts: %s | the dragged arm (chain): %s" % [str(parts), str(chain)])
	if m.playing:
		say("   the clip is still playing: press Stop before the drag")
		await click_text("Stop")
	await settle()
	var before := {}
	for p in parts:
		before[p] = dir_of(String(p))
	await idle(30)   # control: nothing is dragged yet
	var drift := 0.0
	var drift_p := ""
	for p in parts:
		var dd := angle_between(before[p], dir_of(String(p)))
		if dd > drift:
			drift = dd
			drift_p = String(p)
	say("   control (no drag, 30 frames, playing %s): the largest turn of any part is %.2f deg (%s)" % [str(m.playing), drift, drift_p])
	before.clear()
	for p in parts:
		before[p] = dir_of(String(p))
	var wb: Vector3 = wep_face()
	var waxb: Vector3 = wep_axis()
	var ep: Vector2 = scr("lowerarm_l")
	var elbow0: Vector3 = mid("lowerarm_l")
	await drag_view(ep, Vector2(-110, 0))
	await idle(10)
	var worst := 0.0
	var worst_p := ""
	var moved_chain := 0.0
	for p in parts:
		var a: float = angle_between(before[p], dir_of(String(p)))
		if chain.has(String(p)):
			moved_chain = maxf(moved_chain, a)
			continue
		if a > worst:
			worst = a
			worst_p = String(p)
	var wdeg: float = angle_between(wb, wep_face())
	say("   dragged arm turned %.1f deg | the rest of the body: worst %.2f deg (%s) | weapon face turned %.2f deg" % [moved_chain, worst, worst_p, wdeg])
	if moved_chain < 5.0:
		note("the left arm barely moved (%.1f deg): the drag did not pose it" % moved_chain)
	if worst > 1.0:
		note("'Only this part' on: %s turns %.2f deg (more than 1 deg)" % [worst_p, worst])
	if wdeg > 1.0:
		note("the weapon turns %.2f deg when only the left arm is dragged" % wdeg)
	await shot(7, "left arm dragged, Only this part on")
	var ok5: bool = was_on and moved_chain >= 5.0 and worst <= 1.0 and wdeg <= 1.0
	finish(5, ok5, "rest of body worst %.2f deg (%s); dragged arm %.1f deg; weapon %.2f deg" % [worst, worst_p, moved_chain, wdeg])

	# 6. UNDO THREE TIMES: each one changes the body or the weapon
	start_goal(6, "Undo three times: each Undo goes back one visible step")
	var changed := 0
	var tips := []
	for i in 3:
		var ub := find_btn("Undo")
		var tip := ub.tooltip_text if ub != null else "(no Undo button)"
		say("   Undo %d: tooltip before '%s'" % [i + 1, tip])
		var f0: String = fingerprint()
		var fa0: Vector3 = wep_face()
		var ea0: Vector3 = dir_of("lowerarm_l")
		await click_text("Undo")
		await settle()
		var f1: String = fingerprint()
		say("   Undo %d: weapon face turned %.1f deg, left forearm turned %.1f deg" % [i + 1, angle_between(fa0, wep_face()), angle_between(ea0, dir_of("lowerarm_l"))])
		var did: bool = f0 != f1
		if did:
			changed += 1
		tips.append(tip)
		say("   Undo %d: body/weapon changed %s | %s" % [i + 1, str(did), status_now()])
		if not did:
			note("Undo %d changed nothing (no visible step taken back; tooltip '%s')" % [i + 1, tip])
	await shot(8, "after three Undos")
	finish(6, changed == 3, "%d of 3 Undos changed the body or weapon; tooltips: %s" % [changed, str(tips)])

	say("\nSUMMARY (goal | pass | clicks | seconds):")
	for r in results:
		say("  %d | %s | %d | %.1f" % [r[0], "PASS" if r[1] else "FRICTION", r[2], r[3]])
	var lf := FileAccess.open(OUT + "walk12_log.txt", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\n")
	lf.close()
	TestFiles.cleanup()
	quit(0)
