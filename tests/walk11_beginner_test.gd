## godot --path . -s tests/walk11_beginner_test.gd   (MONKEY TEST, round 11: EASY mode, TYPED moves, real clicks only)
## A beginner types into Easy's box (not the pictures): 1 "jump twice" (the pelvis rises twice);
## 2 "then turn around" after it (the body faces the other way at the end); 3 "make it slower" (the clip gets longer;
## the Slower button if the typing does nothing); 4 "wlak forward" (a typo: forgiven and walked, or a helpful sentence);
## 5 "punch with the left hand" (the LEFT hand goes forward > 30 cm); 6 Undo twice (back to the clip before 4 and 5).
## Only what is visible in Easy: buttons with words, the type box. Reads of state for the checks only (poses are
## sampled with Scene.apply and restored with Body.state / set_state).
## Prints "GOAL n: PASS|FRICTION - what happened". Exits 0 (frictions are findings). Screenshots: the scratchpad, walk11_<n>.png.
extends SceneTree

const OUT := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/"

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


func find_btn(txt: String, prefix := false) -> Button:
	for b in visible_buttons():
		for t in labels_of(b):
			if t == txt or (prefix and t.begins_with(txt)):
				return b
	return null


func btn_names() -> String:
	var out := []
	for b in visible_buttons():
		var t := text_of(b)
		if t != "":
			out.append(t)
	return str(out)


func visible_words() -> String:
	var out := []
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges())
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


func hit_name(_p: Vector2) -> String:
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
		say("   COVERED: the click at %s lands on %s, not on the button" % [str(p), hit_name(p)])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return inside


## a click on the first visible button with these words (the words a beginner reads on it)
func click_text(txt: String, prefix := false) -> bool:
	var b := find_btn(txt, prefix)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s'" % txt)
		return false
	clicks += 1
	say("   click '%s' (tooltip: '%s')" % [text_of(b), b.tooltip_text])
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


func visible_line_edit(placeholder_start: String) -> LineEdit:
	for n in visible_nodes():
		if n is LineEdit and (n as LineEdit).placeholder_text.begins_with(placeholder_start):
			return n
	return null


func box() -> LineEdit:
	return visible_line_edit("or type")


## types a move into Easy's box and presses Enter. The panel comes back first with "Change it" when a clip is there.
## A beginner selects what is in the box and replaces it (the walk10 way).
func type_typed(s: String) -> bool:
	var bx := box()
	if bx == null:
		say("   the box is not on screen (a clip is there: the strip shows): click 'Change it'")
		if find_btn("Change it") == null:
			say("   NOT VISIBLE: no 'Change it' button either")
			return false
		clicks += 1
		await click_text("Change it")
		await idle(10)
		bx = box()
		if bx == null:
			say("   NOT VISIBLE: still no text box after 'Change it'")
			return false
	clicks += 1
	await click_ctl(bx)
	if bx.text != "":
		say("   the box still says '%s': select all and delete" % bx.text)
		await press_key(KEY_A, true)
		await press_key(KEY_BACKSPACE)
	say("   type '%s' + Enter" % s)
	await type_text(s, true)
	await idle(20)
	return true


func msg_now() -> String:
	var h = m.easy.home
	if h == null or h._msg == null:
		return ""
	return String(h._msg.text)


func toast_words() -> String:
	var h = m.easy.home
	if h == null or h._toast == null or not h._toast.visible:
		return "(no toast)"
	return "toast: '%s' [button '%s' tooltip '%s']" % [h._toast_text.text, h._toast_show.text, h._toast_show.tooltip_text]


func try_words() -> String:
	var h = m.easy.home
	if h == null or h._try_row == null or not h._try_row.visible:
		return "(no 'Or try' row)"
	var out := []
	for c in h._try_row.get_children():
		if c is Button:
			out.append((c as Button).text)
	return "'Or try' row: %s" % str(out)


func shot(n: int, what: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	var f := OUT + "walk11_%d.png" % n
	root.get_texture().get_image().save_png(f)
	say("   screenshot %s (%s) | cards: %d | clip %.2f s | playing: %s" % [f, what, m.S.cards.size(), m.S.length(), str(m.playing)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())
	say("   message: '%s' | %s | %s" % [msg_now(), try_words(), toast_words()])


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


func wait_playing(limit := 240) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


## the clip plays by itself after a build: wait until it has stopped (or never started)
func settle(limit := 2400) -> void:
	await wait_playing(120)
	for i in limit:
		if not m.playing:
			break
		await process_frame
	await idle(5)


func wait_for_cond(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await process_frame
	return false


func mid(part: String) -> Vector3:
	var c: Array = m.B.cap(part)
	return (c[0] + c[1]) * 0.5 if c.size() >= 2 else Vector3.ZERO


## the body's facing, horizontal: the feet's capsules point ankle to toe, toward +Z at rest (data/skeleton.json: "+Z forward")
func face_now() -> Vector3:
	var f := Vector3.ZERO
	for part in ["foot_l", "foot_r"]:
		var c: Array = m.B.cap(part)
		var d: Vector3 = c[1] - c[0]
		d.y = 0.0
		f += d
	return f.normalized()


## the body at time t of the clip (Scene.apply), read and then put back exactly as it was
func pose_at(t: float) -> Dictionary:
	var keep: Dictionary = m.B.state()
	m._ps().apply(m.B, t)
	var r := {"pel": mid("pelvis"), "hl": mid("hand_l"), "hr": mid("hand_r"), "face": face_now()}
	m.B.set_state(keep)
	return r


func angle_between(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.dot(b), -1.0, 1.0)))


## the pelvis height over the whole clip: how many separate rises (a jump each) reach halfway up its range
func jumps_in_clip(L: float, n := 300) -> Dictionary:
	var ys: Array = []
	for i in n:
		var p: Dictionary = pose_at(L * float(i) / float(n - 1))
		ys.append((p["pel"] as Vector3).y)
	var lo: float = ys.min()
	var hi: float = ys.max()
	var span := hi - lo
	var count := 0
	var above := false
	for y in ys:
		if not above and float(y) > lo + 0.5 * span:
			count += 1
			above = true
		elif above and float(y) < lo + 0.25 * span:
			above = false
	return {"count": count, "span": span, "lo": lo, "hi": hi}


func _init() -> void:
	EasyMode.start_fresh = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	video_dir = ProjectSettings.globalize_path("user://walk11_out_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(video_dir)
	m.easy.home.video_root = video_dir
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if not m.easy.on:
		m.easy.set_on(true)
		await idle(10)
		say("   forced Easy (set_on(true)) | Easy now: %s" % str(m.easy.on))
	say("start: home panel %s | cards %d | words: %s" % [m.easy.home.shown(), m.S.cards.size(), visible_words()])
	say("start: buttons %s" % btn_names())

	# 1. TYPE "jump twice"
	start_goal(1, "type 'jump twice' into the box")
	var n1: int = m.S.cards.size()
	await type_typed("jump twice")
	var built1 := await wait_for_cond(func(): return m.S.cards.size() != n1, 400)
	await settle()
	var j1: Dictionary = {"count": 0, "span": 0.0, "lo": 0.0, "hi": 0.0}
	if built1:
		j1 = jumps_in_clip(m.S.length())
	say("   clip %.2f s, %d cards | pelvis range %.3f m (low %.3f, high %.3f) | separate jumps: %d" % [m.S.length(), m.S.cards.size(), float(j1["span"]), float(j1["lo"]), float(j1["hi"]), int(j1["count"])])
	await shot(1, "after 'jump twice'")
	if not built1:
		note("'jump twice' typed: no clip built. The box says: '%s'" % msg_now())
	elif int(j1["count"]) != 2:
		note("'jump twice' gives %d rise(s) of the pelvis, not 2 (range %.3f m)" % [int(j1["count"]), float(j1["span"])])
	finish(1, built1 and int(j1["count"]) == 2, "typed 'jump twice': %d pelvis rises, range %.3f m, clip %.2f s" % [int(j1["count"]), float(j1["span"]), m.S.length()])

	# 2. TYPE "then turn around" after it
	start_goal(2, "type 'then turn around' after the clip")
	var f2start: Vector3 = pose_at(0.0)["face"]
	var c2: int = m.S.cards.size()
	await type_typed("then turn around")
	var built2 := await wait_for_cond(func(): return m.S.cards.size() != c2, 400)
	await settle()
	var f2end: Vector3 = pose_at(m.S.length())["face"]
	var ang2 := angle_between(f2start, f2end)
	say("   facing at the start %s, at the end %s: turned %.0f deg | clip %.2f s, %d cards" % [str(f2start), str(f2end), ang2, m.S.length(), m.S.cards.size()])
	await shot(2, "after 'then turn around'")
	if not built2:
		note("'then turn around' typed: no move added. The box says: '%s' (%s)" % [msg_now(), try_words()])
	elif absf(ang2 - 180.0) > 30.0:
		note("'then turn around' turns him %.0f deg, not about 180" % ang2)
	finish(2, built2 and absf(ang2 - 180.0) <= 30.0, "typed 'then turn around': turned %.0f deg, clip %.2f s" % [ang2, m.S.length()])

	# 3. TYPE "make it slower" (the Slower button when typing does nothing)
	start_goal(3, "type 'make it slower' (or the Slower button)")
	var L3pre: float = m.S.length()
	await type_typed("make it slower")
	var longer3 := await wait_for_cond(func(): return m.S.length() > L3pre + 0.01, 300)
	await settle()
	if not longer3:
		note("typed 'make it slower' did not make the clip longer. The box says: '%s'" % msg_now())
		var sb3 := find_btn("Slower")
		if sb3 != null:
			say("   the Slower button is on screen: click it")
			await click_text("Slower")
			await settle()
		else:
			note("no Slower button on screen after the typed line (visible: %s)" % btn_names())
	var L3: float = m.S.length()
	say("   clip before %.2f s, after %.2f s (x%.2f)" % [L3pre, L3, L3 / maxf(L3pre, 0.001)])
	await shot(3, "after 'make it slower'")
	var slow_ok: bool = L3 >= L3pre * 1.15
	finish(3, slow_ok, "clip %.2f s -> %.2f s (x%.2f) | typed line longer: %s" % [L3pre, L3, L3 / maxf(L3pre, 0.001), str(longer3)])

	# 4. TYPE "wlak forward" (a typo)
	start_goal(4, "type 'wlak forward' (a typo)")
	var L4pre: float = m.S.length()
	var p4: Dictionary = pose_at(L4pre)
	var f4: Vector3 = p4["face"]
	var c4: int = m.S.cards.size()
	await type_typed("wlak forward")
	var built4 := await wait_for_cond(func(): return m.S.cards.size() != c4, 400)
	await settle()
	var msg4 := msg_now()
	var fwd4 := 0.0
	if built4:
		var p4e: Dictionary = pose_at(m.S.length())
		var d4: Vector3 = (p4e["pel"] as Vector3) - (p4["pel"] as Vector3)
		d4.y = 0.0
		fwd4 = d4.dot(f4.normalized())
	var helpful4 := msg4.to_lower().contains("walk") or try_words() != "(no 'Or try' row)"
	say("   typo result: built %s | forward %.2f m | message '%s' | %s" % [str(built4), fwd4, msg4, try_words()])
	await shot(4, "after 'wlak forward'")
	if built4 and fwd4 < 0.3:
		note("'wlak forward' was built but he moves only %.2f m forward" % fwd4)
	if not built4 and not helpful4:
		note("'wlak forward' refused and the message does not name a move: '%s'" % msg4)
	var ok4 := (built4 and fwd4 >= 0.3) or (not built4 and helpful4)
	finish(4, ok4, "typo 'wlak forward': %s (forward %.2f m); message '%s'" % ["built" if built4 else "refused", fwd4, msg4])

	# 5. TYPE "punch with the left hand"
	start_goal(5, "type 'punch with the left hand'")
	var L5pre: float = m.S.length()
	var c5: int = m.S.cards.size()
	await type_typed("punch with the left hand")
	var built5 := await wait_for_cond(func(): return m.S.cards.size() != c5, 400)
	await settle()
	var fl := 0.0
	var fr := 0.0
	var fwd_l := -INF
	var fwd_r := -INF
	if built5:
		var pt: Dictionary = pose_at(L5pre)
		var f5: Vector3 = pt["face"]
		var hl0: Vector3 = pt["hl"]
		var hr0: Vector3 = pt["hr"]
		var L5end: float = m.S.length()
		for i in 60:
			var t := lerpf(L5pre, L5end, float(i) / 59.0)
			var q: Dictionary = pose_at(t)
			fwd_l = maxf(fwd_l, ((q["hl"] as Vector3) - hl0).dot(f5))
			fwd_r = maxf(fwd_r, ((q["hr"] as Vector3) - hr0).dot(f5))
		fl = fwd_l
		fr = fwd_r
	say("   punch from %.2f s: LEFT hand forward %.3f m, RIGHT hand forward %.3f m | clip %.2f s" % [L5pre, fl, fr, m.S.length()])
	await shot(5, "after 'punch with the left hand'")
	if not built5:
		note("'punch with the left hand' typed: no move added. The box says: '%s' (%s)" % [msg_now(), try_words()])
	elif fl <= 0.30:
		note("the left hand goes forward only %.3f m (wanted over 0.30 m)" % fl)
	elif fr >= 0.5 * fl:
		note("the right hand also goes forward %.3f m: not only the left" % fr)
	finish(5, built5 and fl > 0.30 and fr < 0.5 * fl, "left hand forward %.3f m, right %.3f m" % [fl, fr])

	# 6. UNDO TWICE: back to the clip before step 5 and 4
	start_goal(6, "Undo twice")
	var Lbefore6: float = m.S.length()
	var cards6: int = m.S.cards.size()
	var ub := find_btn("Undo")
	if ub != null:
		say("   Undo tooltip before: '%s'" % ub.tooltip_text)
	await click_text("Undo")
	await settle()
	var ub2 := find_btn("Undo")
	if ub2 != null:
		say("   Undo tooltip after the first press: '%s'" % ub2.tooltip_text)
	await click_text("Undo")
	await settle()
	var L6: float = m.S.length()
	var c6: int = m.S.cards.size()
	say("   clip before the undos %.2f s (%d cards) | after two: %.2f s (%d cards) | before step 4: %.2f s (%d cards) | after step 3 (Slower): %.2f s" % [Lbefore6, cards6, L6, c6, L4pre, c4, L3])
	await shot(6, "after Undo twice")
	var ok6: bool = absf(L6 - L4pre) < 0.02 and c6 == c4
	if not ok6:
		if absf(L6 - L3) < 0.02:
			note("two Undos went past step 4: the clip is back to after 'make it slower' (%.2f s), not before 'wlak forward' (%.2f s)" % [L6, L4pre])
		else:
			note("two Undos give %.2f s (%d cards): not the clip before step 4 (%.2f s, %d cards)" % [L6, c6, L4pre, c4])
	finish(6, ok6, "two Undos: %.2f s / %d cards; before step 4: %.2f s / %d cards" % [L6, c6, L4pre, c4])

	say("\nSUMMARY (goal | pass | clicks | seconds):")
	for r in results:
		say("  %d | %s | %d | %.1f" % [r[0], "PASS" if r[1] else "FRICTION", r[2], r[3]])
	var lf := FileAccess.open(OUT + "walk11_log.txt", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\n")
	lf.close()
	quit(0)
