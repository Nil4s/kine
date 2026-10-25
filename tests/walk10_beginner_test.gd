## godot --path . -s tests/walk10_beginner_test.gd   (MONKEY TEST, round 10: EASY mode, real clicks only)
## A beginner who has never seen the app: 1 a character waves hello; 2 a chair from the Library, then he sits on it;
## 3 change his colour or look if Easy offers it; 4 play it back; 5 save the scene, then save a video.
## Only what is visible in Easy: buttons with words, the type box. Reads of state for the checks only.
## Prints "GOAL n: PASS|FRICTION - what happened". Exits 0 (frictions are findings). Screenshots: the scratchpad, walk10_<n>.png.
extends SceneTree

const OUT := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/"

var video_dir := ""
var made: Array = []
var m: Node
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""
var notes: Array = []
var gbase := 0
var results: Array = []
var n_shot := 0


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


## every visible label on a button (a Library tile has a caption label "Sports" AND its name label "Football")
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


func move(p: Vector2, rel: Vector2, mask := MOUSE_BUTTON_MASK_LEFT) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = mask
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


## a click on one row of a popup menu (Easy's More list, the Open list): the row's place in the list
func click_menu_item(menu: PopupMenu, txt: String) -> bool:
	if menu == null or not menu.visible:
		say("   NOT VISIBLE: the menu is not open (wanted '%s')" % txt)
		return false
	var idx := -1
	var items := []
	for i in menu.item_count:
		items.append(menu.get_item_text(i))
		if menu.get_item_text(i) == txt:
			idx = i
	if idx < 0:
		say("   NOT VISIBLE: the menu has %s, not '%s'" % [str(items), txt])
		return false
	clicks += 1
	var pos := Vector2(menu.position)
	var sz := Vector2(menu.size)
	var rowh := sz.y / float(menu.item_count)
	var p := Vector2(pos.x + sz.x * 0.5, pos.y + (idx + 0.5) * rowh)
	say("   click menu row '%s' (of %s)" % [txt, str(items)])
	await hover(p)
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return true


## a real drag on the Easy scrub slider (eh_scrub) to a fraction of its width: the beginner's way to find a moment
func scrub_to(frac: float) -> bool:
	var s := m.find_child("eh_scrub", true, false) as HSlider
	if s == null or not s.is_visible_in_tree():
		say("   NOT VISIBLE: no eh_scrub slider on screen")
		return false
	clicks += 1
	var r := s.get_global_rect()
	var p := Vector2(r.position.x + r.size.x * frac, r.get_center().y)
	say("   drag eh_scrub to %.0f%% (tooltip: '%s')" % [frac * 100.0, s.tooltip_text])
	await hover(p)
	mouse_btn(true, p)
	await process_frame
	for i in 4:
		move(p + Vector2(i, 0), Vector2(1, 0))
		await process_frame
	mouse_btn(false, p)
	await idle(6)
	return true


func body_on_screen() -> bool:
	var c: Array = m.B.cap("pelvis")
	var at: Vector3 = (c[0] + c[1]) * 0.5
	var vp := m.get_viewport().get_visible_rect()
	return not m.cam.is_position_behind(at) and vp.has_point(m.cam.unproject_position(at))


func pelvis_y() -> float:
	return ((m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5).y


## the highest the pelvis gets during one play of the clip (from the start); NAN if it did not play
func play_peak() -> float:
	var ok := await wait_playing()
	if not ok:
		return NAN
	var top := -INF
	for i in 1200:
		if not m.playing:
			break
		top = maxf(top, pelvis_y())
		await process_frame
	return top


func toast_words() -> String:
	var h = m.easy.home
	if h == null or h._toast == null or not h._toast.visible:
		return "(no toast)"
	return "toast: '%s' [button '%s' tooltip '%s']" % [h._toast_text.text, h._toast_show.text, h._toast_show.tooltip_text]


func status_words() -> String:
	var out := []
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			var t := (n as Label).text.strip_edges()
			if t.length() > 3:
				out.append(t)
	return str(out.slice(0, 12))


func shot(name: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	n_shot += 1
	var f := "%s%02d_%s.png" % [OUT, n_shot, name]
	root.get_texture().get_image().save_png(f)
	say("   shot %s | body on screen: %s | cards: %d | props: %d | playing: %s" % [f, str(body_on_screen()), m.S.cards.size(), m.S.props.size(), str(m.playing)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())
	say("   " + toast_words())


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func end_goal(ok: bool, note_s: String) -> void:
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if not ok:
		say("FAIL " + goal)
	say("== END %s: done=%s clicks=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, secs, note_s])
	results.append([goal, ok, clicks, secs, note_s])


func note(s: String) -> void:
	notes.append("[%s] %s" % [goal.get_slice(" ", 0), s])
	say("   FRICTION: " + s)


func wait_playing(limit := 240) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


func wait_for(cond: Callable, limit: int) -> bool:
	for i in limit:
		if cond.call():
			return true
		await process_frame
	return false


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


func card_names() -> Array:
	var out := []
	for c in m.S.cards:
		out.append(str(c.get("name", "?")))
	return out


func has_card(word: String) -> bool:
	for s in card_names():
		if s.to_lower().contains(word):
			return true
	return false


func count_card(word: String) -> int:
	var k := 0
	for s in card_names():
		if s.to_lower().contains(word):
			k += 1
	return k


func words_say() -> String:
	var said := ""
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			said += " || " + (n as Label).text.strip_edges()
	return said


func box() -> LineEdit:
	return visible_line_edit("or type")


## types a move into the text box (the panel comes back first with Change it when a clip is there)
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


func type_move(words: String) -> bool:
	var bx := box()
	if bx == null:
		say("   NOT VISIBLE: no text box")
		return false
	await click_ctl(bx)
	clicks += 1
	# the box keeps the last words typed (a refused 'dance' stays): a beginner selects all and deletes first
	if bx.text != "":
		say("   the box still says '%s': select all and delete" % bx.text)
		await press_key(KEY_A, true)
		await press_key(KEY_BACKSPACE)
	await type_text(words, true)
	await idle(30)
	return true



func card_node(i: int) -> Control:
	return m.ui_cards.get_node_or_null("card_%d" % (i + 1)) as Control


## the furthest the playhead gets during one play (the play that runs now or starts at once); NAN if none starts
func play_top(limit := 1500) -> float:
	var ok := await wait_playing()
	if not ok:
		return NAN
	var top := 0.0
	for i in limit:
		if not m.playing:
			break
		top = maxf(top, m.playhead)
		await process_frame
	return top


## the highest the pelvis gets during one play, above base (metres); NAN if none starts
func peak_to_end(base: float, limit := 1500) -> float:
	var ok := await wait_playing()
	if not ok:
		return NAN
	var top := -INF
	for i in limit:
		if not m.playing:
			break
		top = maxf(top, pelvis_y())
		await process_frame
	return top - base




## the middle of a body part (its capsule's two ends averaged), world space
func mid(part: String) -> Vector3:
	var c: Array = m.B.cap(part)
	return (c[0] + c[1]) * 0.5 if c.size() >= 2 else Vector3.ZERO


## one play of the clip: the furthest each hand gets from its rest place, and the furthest the playhead gets
func play_hands(rest_l: Vector3, rest_r: Vector3, limit := 1500) -> Dictionary:
	var ok := await wait_playing()
	if not ok:
		return {"ok": false}
	var ml := 0.0
	var mr := 0.0
	var top := 0.0
	var pl_at := Vector3.ZERO
	var pr_at := Vector3.ZERO
	for i in limit:
		if not m.playing:
			break
		var dl := mid("hand_l").distance_to(rest_l)
		var dr := mid("hand_r").distance_to(rest_r)
		if dl > ml:
			ml = dl
			pl_at = mid("hand_l")
		if dr > mr:
			mr = dr
			pr_at = mid("hand_r")
		top = maxf(top, m.playhead)
		await process_frame
	say("   rest hands: left %s right %s | furthest hands: left %s right %s" % [str(rest_l), str(rest_r), str(pl_at), str(pr_at)])
	return {"ok": true, "l": ml, "r": mr, "top": top}


## one play of the clip to its last frame: the pelvis where the playhead is furthest (the clip's end pose while it plays)
func play_end_pelvis(limit := 1500) -> Dictionary:
	var ok := await wait_playing()
	if not ok:
		return {"ok": false}
	var top := 0.0
	var pel := Vector3.ZERO
	for i in limit:
		if not m.playing:
			break
		if m.playhead >= top:
			top = m.playhead
			pel = (m.B.cap("pelvis")[0] + m.B.cap("pelvis")[1]) * 0.5
		await process_frame
	return {"ok": true, "top": top, "pelvis": pel}


## the screenshot for a goal: walk10_<n>.png in the scratchpad
func snap(n: int, what: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	var f := OUT + "walk10_%d.png" % n
	root.get_texture().get_image().save_png(f)
	say("   screenshot %s (%s) | cards: %d | props: %d" % [f, what, m.S.cards.size(), m.S.props.size()])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())
	say("   " + toast_words())


## a goal's verdict: PASS when reached and nothing on the way was a friction; else FRICTION
func finish(n: int, ok: bool, what: String) -> void:
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var fr := (not ok) or notes.size() > gbase
	say("GOAL %d: %s - %s (clicks %d, %.1f s)" % [n, "FRICTION" if fr else "PASS", what, clicks, secs])
	results.append([n, not fr, clicks, secs])


func start_goal(n: int, s: String) -> void:
	begin_goal(s)
	gbase = notes.size()


func chair_index() -> int:
	var picked: int = m.sel_prop
	if picked >= 0 and picked < m.S.props.size() and String(m.S.props[picked]["kind"]) == "chair":
		return picked
	for j in m.S.props.size():
		if String(m.S.props[j]["kind"]) == "chair":
			return j
	return -1


func _init() -> void:
	EasyMode.start_fresh = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	video_dir = ProjectSettings.globalize_path("user://walk10_out_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(video_dir)
	m.easy.home.video_root = video_dir
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if not m.easy.on:
		m.easy.set_on(true)
		await idle(10)
		say("   forced Easy (set_on(true)) | Easy now: %s" % str(m.easy.on))
	say("start: home panel %s | words: %s" % [m.easy.home.shown(), visible_words()])
	say("start: buttons %s" % btn_names())

	# 1. A WAVE HELLO
	start_goal(1, "make him wave hello")
	var rest_l := mid("hand_l")
	var rest_r := mid("hand_r")
	var w1 := await click_text("Wave")
	var pw1: Dictionary = await play_hands(rest_l, rest_r)
	var ml1: float = pw1.get("l", 0.0)
	var mr1: float = pw1.get("r", 0.0)
	await snap(1, "after the wave")
	say("   hands moved: left %.3f m, right %.3f m, playhead reached %.2f s" % [ml1, mr1, float(pw1.get("top", 0.0))])
	var moved1 := maxf(ml1, mr1)
	var one_arm := moved1 > 0.15 and minf(ml1, mr1) < 0.5 * moved1
	if not w1:
		note("no 'Wave' picture on the first screen")
	elif moved1 <= 0.15:
		note("after Wave, no hand moves: the wave does nothing a beginner can see (left %.3f m, right %.3f m)" % [ml1, mr1])
	elif not one_arm:
		note("the wave moves both arms (left %.3f m, right %.3f m): not one hand waving" % [ml1, mr1])
	var which1 := "left arm" if ml1 > mr1 else "right arm"
	finish(1, w1 and one_arm, ("wave played, the %s waves (%.2f m)" % [which1, moved1]) if moved1 > 0.15 else "no arm waves")

	# 2. A CHAIR FROM THE LIBRARY, THEN HE SITS ON IT
	start_goal(2, "chair from the Library, then make him sit on it")
	var lib2 := await click_text("Library")
	var fur2 := await click_text("Furniture", true)
	var ch2 := await click_text("Chair")
	if not ch2:
		ch2 = await click_text("Chair", true)
	var cl2 := await click_text("Close")
	await snap(2, "chair added, Library closed")
	var ci := chair_index()
	var kinds := []
	for p in m.S.props:
		kinds.append(String(p["kind"]))
	say("   props in the scene: %s (chair index %d)" % [str(kinds), ci])
	var sit2 := false
	var sb := find_btn("Sit on", true)
	if sb != null:
		sit2 = await click_text(text_of(sb), false)
	else:
		note("after the chair is added, no button on screen says sit (visible: %s)" % btn_names())
	var end_gap := -1.0
	if sit2:
		var pe: Dictionary = await play_end_pelvis()
		var pk: float = pe.get("top", 0.0)
		var seat: Vector3 = Rise.seat_of(m.S.props[chair_index()]) if chair_index() >= 0 else Vector3.ZERO
		var pel: Vector3 = pe.get("pelvis", Vector3.ZERO)
		end_gap = Vector2(pel.x - seat.x, pel.z - seat.z).length()
		say("   sit: pelvis %.3f m from the seat point (horizontal), %.3f m vertical; played to %.2f s" % [end_gap, pel.y - seat.y, pk])
		await snap(2, "after the sit played")
		if end_gap > 0.10:
			note("the sit misses the chair: pelvis %.2f m from the seat point (wanted under 0.10 m)" % end_gap)
	finish(2, lib2 and fur2 and ch2 and cl2 and sit2 and ci >= 0 and end_gap >= 0.0 and end_gap <= 0.10, "chair from the Library, sit %s, %.2f m from the seat" % [str(sit2), end_gap])

	# 3. CHANGE HIS COLOUR OR LOOK
	start_goal(3, "change his colour or look")
	var look_words := ["colo", "look", "skin", "shirt", "cloth", "outfit", "dress", "appear", "wear"]
	var found3: Array = []
	for b in visible_buttons():
		for t in labels_of(b):
			if String(t).to_lower().contains("chair"):
				continue   # "Sit on the chair" is not a look (and "chair" holds "hair")
			for w in look_words:
				if String(t).to_lower().contains(w):
					found3.append(t)
	var more_items: Array = []
	var mn: PopupMenu = m.easy._more
	if mn != null:
		for i in mn.item_count:
			more_items.append(mn.get_item_text(i))
	say("   look words on screen: %s | More menu: %s" % [str(found3), str(more_items)])
	var colour_btn := find_btn("Colour")
	if colour_btn != null:
		note("the 'Colour' button recolours the picked object (the chair), not him: it is the only colour control on screen")
	else:
		note("no colour or look control for him in Easy: nothing on the bar, the strip or More says colour or look (More: %s)" % str(more_items))
	await snap(3, "looking for a colour or look")
	finish(3, false, "not reached: no way to change his colour or look in Easy" if found3.is_empty() else "look controls seen: %s" % str(found3))

	# 4. PLAY IT BACK
	start_goal(4, "play it back")
	var again4 := await click_text("Again")
	if not again4:
		again4 = await click_text("Play / Stop")
	var top4 := await play_top()
	var len4: float = m.S.length()
	await snap(4, "after playing")
	say("   played to %.2f s of %.2f s" % [top4, len4])
	finish(4, again4 and not is_nan(top4) and top4 >= len4 * 0.9, "played the whole clip (%.2f of %.2f s)" % [top4, len4])

	# 5. SAVE THE SCENE, THEN SAVE A VIDEO
	start_goal(5, "save the scene, then save a video")
	var had5 := Array(DirAccess.get_files_at("res://scenes"))
	var more5 := await click_text("More")
	var sv5 := await click_menu_item(m.easy._more, "Save the scene")
	await idle(20)
	if find_btn("Save as a new name") != null:   # a scene of this name exists: Easy asks first
		note("saving a second time asks 'Replace it' or 'Save as a new name' (the same name is already there): a beginner must choose")
		await click_text("Save as a new name")
		await idle(20)
	var saved5 := str(m.scene_path)
	say("   scene file: %s" % saved5)
	if saved5 != "" and (saved5.contains("_wip") or (saved5.begins_with("res://scenes/") and not saved5.get_file() in had5)):
		made.append(saved5)
	var vid5 := await click_text("Save video")
	var tw := Time.get_ticks_msec()
	while m.easy.home.last_video.is_empty() and Time.get_ticks_msec() - tw < 240000:
		await process_frame
	await idle(10)
	var mp4 := String(m.easy.home.last_video.get("mp4", ""))
	var size5 := 0
	if mp4 != "" and FileAccess.file_exists(mp4):
		var fh := FileAccess.open(mp4, FileAccess.READ)
		size5 = int(fh.get_length())
		fh.close()
	var toast5: bool = m.easy.home._toast.visible and m.easy.home._toast_show.visible
	await snap(5, "after Save video")
	say("   VIDEO FILE: %s (%d bytes) | toast: %s" % [mp4, size5, toast_words()])
	if not toast5:
		note("saved video: no message with an Open folder button on screen")
	finish(5, sv5 and vid5 and size5 > 0, "scene saved: %s; video %d bytes at %s" % [str(sv5), size5, mp4])

	# CLEANUP: only the scene files this run created (new names); the video stays in the run's user:// folder
	for p in made:   # made holds only scene files this save CREATED (a new name): removed wherever they sit
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		say("removed the run's scene file " + String(p))
	say("\nSUMMARY (goal | pass | clicks | seconds):")
	for r in results:
		say("  %d | %s | %d | %.1f" % [r[0], "PASS" if r[1] else "FRICTION", r[2], r[3]])
	var lf := FileAccess.open(OUT + "walk10_log.txt", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\n")
	lf.close()
	quit(0)
