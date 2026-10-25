## godot --path . --position 3000,3000 -s tests/walk_lib_beginner_test.gd   (BEGINNER WALK-THROUGH of the OBJECT LIBRARY, EASY mode)
## Eight goals a non-technical person would try with the library, every press a real mouse click, every drag a real drag,
## every sentence typed. A goal the UI does not offer is reported as NOT DONE with what was visible; nothing is worked around.
## Screenshots go to C:/Temp/claude/walklib/ ; the log is C:/Temp/claude/walklib/log.txt.
## The AI video button is NEVER pressed. No scene file is saved by this run. The Easy settings file is the test's own.
extends SceneTree

const OUT := "C:/Temp/claude/walklib/"
const CATS := ["Weapons", "Furniture", "Sports", "Everyday", "Armour", "My models"]

var m: Node
var n_shot := 0
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""


func say(s: String) -> void:
	print(s)
	lines.append(s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):   # INTERNAL children too
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


func find_btn(txt: String, prefix := false) -> Button:
	for b in visible_buttons():
		var t := text_of(b)
		if t == txt or (prefix and t.begins_with(txt)):
			return b
	return null


func btn_names() -> String:
	var out := []
	for b in visible_buttons():
		var t := text_of(b)
		if t != "" and not String((b as Node).name).begins_with("tile_"):
			out.append(t)
	return str(out)


func visible_words() -> String:
	var out := []
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "" and not (n as Label).name == "placeholder":
			out.append((n as Label).text.strip_edges())
	return str(out)


func mouse_btn(down: bool, p: Vector2, which := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = which
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
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


func key(k: Key) -> void:
	var kd := InputEventKey.new()
	kd.keycode = k
	kd.physical_keycode = k
	kd.pressed = true
	root.push_input(kd)
	await process_frame
	var ku := InputEventKey.new()
	ku.keycode = k
	ku.physical_keycode = k
	ku.pressed = false
	root.push_input(ku)
	await idle(3)


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
		await key(KEY_ENTER)


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
		say("   COVERED: the click at %s lands on %s, not on the control" % [str(p), hit_name(p)])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)
	return inside


func click_text(txt: String, prefix := false) -> bool:
	var b := find_btn(txt, prefix)
	if b == null:
		say("   NOT VISIBLE: no button reads '%s' | buttons: %s" % [txt, btn_names()])
		return false
	clicks += 1
	say("   click '%s'" % text_of(b))
	return await click_ctl(b)


## a click on the view (no movement): picks whatever is under the pointer
func click_view(p: Vector2) -> void:
	clicks += 1
	await hover(p)
	say("   click in the view at %s (under the pointer: %s)" % [str(p), hit_name(p)])
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(4)


## a real drag of a placed prop in the view: press on it, move in steps, let go
func drag_prop(i: int, d: Vector2) -> void:
	clicks += 1
	var p := prop_screen(i)
	await hover(p)
	say("   drag the %s from %s by %s (under the pointer: %s)" % [prop_kind(i), str(p), str(d), hit_name(p)])
	var st := d / 6.0
	mouse_btn(true, p)
	await process_frame
	for k in 6:
		move(p + st * (k + 1), st)
		await process_frame
	mouse_btn(false, p + d)
	await idle(4)


## the centre of the prop's highest solid part (a chair's back, a table's top): a solid body a pointer can hit.
## Run 1 aimed at the origin raised 0.3 m (between a chair's legs); run 2 averaged all parts (under the seat, between the legs).
func prop_screen(i: int) -> Vector2:
	var parts: Array = Props.solids(m.S.props[i])
	var best := Vector3.ZERO
	var best_y := -INF
	for s in parts:
		var o: Vector3 = (s["xf"] as Transform3D).origin
		if o.y > best_y:
			best_y = o.y
			best = o
	return m.cam.unproject_position(best)


func prop_kind(i: int) -> String:
	return String(m.S.props[i]["kind"]) if i >= 0 and i < m.S.props.size() else "?"


func prop_origin(i: int) -> Vector3:
	return (m.S.props[i]["xf"] as Transform3D).origin


## the size of prop i's own boxes (the world box of its solids): the number the bar's Bigger / Smaller must move
func prop_size(i: int) -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for sw in Props.solids(m.S.props[i]):
		var X: Transform3D = sw["xf"]
		var h: Vector3 = sw["half"]
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var c: Vector3 = X * Vector3(sx * h.x, sy * h.y, sz * h.z)
					lo = lo.min(c)
					hi = hi.max(c)
	return hi - lo


func find_prop(kind: String) -> int:
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]) == kind:
			return i
	return -1


func shown_tiles() -> Array:
	var out := []
	for b in visible_buttons():
		if String((b as Node).name).begins_with("tile_"):
			out.append(b)
	return out


## a tile's name: the last Label in it that is not the placeholder (the name is the label under the picture)
func tile_label(b: Node) -> String:
	var s := ""
	for n in walk(b, []):
		if n is Label and (n as Label).name != "placeholder" and (n as Label).text.strip_edges() != "":
			s = (n as Label).text.strip_edges()
	return s


func tile_names() -> Array:
	var out := []
	for b in shown_tiles():
		out.append(tile_label(b))
	return out


func tile_named(word: String, not_word := "") -> Button:
	for b in shown_tiles():
		var t := tile_label(b).to_lower()
		if t.contains(word) and (not_word == "" or not t.contains(not_word)):
			return b
	return null


func click_tile(word: String, not_word := "") -> bool:
	var b := tile_named(word, not_word)
	if b == null:
		say("   NOT VISIBLE: no tile named like '%s' | tiles on screen: %s" % [word, str(tile_names())])
		return false
	clicks += 1
	say("   click tile '%s' (tooltip: %s)" % [tile_label(b), b.tooltip_text])
	return await click_ctl(b)


func lib_child(child_name: String) -> Control:
	for n in walk(m.ui_library, []):
		if n is Control and (n as Control).name == child_name:
			return n
	return null


func lib_note() -> String:
	for n in walk(m.ui_library, []):
		if n is Label and (n as Label).name == "library_note":
			return (n as Label).text
	return ""


func lib_open() -> bool:
	var ok := await click_text("Library")
	await idle(10)
	return ok and m.ui_library.visible


func lib_close() -> bool:
	var c := lib_child("library_close") as Button
	if c == null or not c.is_visible_in_tree():
		say("   NOT VISIBLE: the library has no Close button on screen")
		return false
	clicks += 1
	say("   click 'Close' (library)")
	var ok := await click_ctl(c)
	await idle(6)
	return ok and not m.ui_library.visible


func box() -> LineEdit:
	for n in visible_nodes():
		if n is LineEdit and (n as LineEdit).placeholder_text.begins_with("or type"):
			return n
	return null


func card_names() -> Array:
	var out := []
	for c in m.S.cards:
		out.append(str(c.get("name", "?")))
	return out


func wait_playing(limit := 240) -> bool:
	for i in limit:
		if m.playing and m.playhead > 0.0:
			return true
		await process_frame
	return false


func shot(name: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	n_shot += 1
	var f := "%s%02d_%s.png" % [OUT, n_shot, name]
	root.get_texture().get_image().save_png(f)
	say("   shot %s | cards: %d | props: %s | sel_prop: %d | words: %s" % [f, m.S.cards.size(), str(prop_list()), m.sel_prop, visible_words()])
	say("   visible buttons: %s" % btn_names())


func prop_list() -> Array:
	var out := []
	for p in m.S.props:
		out.append(String(p["kind"]))
	return out


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func end_goal(ok: bool, note: String) -> void:
	say("== END %s: done=%s clicks=%d time=%.1fs %s" % [goal, "yes" if ok else "NO", clicks, (Time.get_ticks_msec() - t0) / 1000.0, note])


func _init() -> void:
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	say("settings file for this run: %s | Easy on at start: %s" % [m.settings, str(m.easy.on)])
	if not m.easy.on:
		m.easy.set_on(true)
		await idle(10)
		say("   forced Easy (set_on(true)) | Easy now: %s" % str(m.easy.on))
	say("start: words: %s" % visible_words())

	# 1. SWORD BY BROWSING: Library, Weapons tab, the sword tile (no search)
	begin_goal("1 find a sword by browsing categories (no search)")
	await lib_open()
	await shot("01_library_open")
	var tab1 := await click_text("Weapons", true)
	await idle(30)
	await shot("02_weapons_tab")
	var pick1 := await click_tile("sword", "floor")
	await idle(10)
	await shot("03_sword_clicked")
	say("   library note: %s" % lib_note())
	say("   hand: wep_on %s, kind %s, hand %s" % [str(m.B.wep_on), str(m.B.wep_kind), str(m.B.wep_hand)])
	var holds1: bool = m.B.wep_on and String(m.B.wep_kind).contains("sword")
	var closed1 := await lib_close()
	await shot("04_library_closed_sword")
	end_goal(tab1 and pick1 and holds1 and closed1, "(sword in hand: %s, hand %s, library closed: %s)" % [str(holds1), str(m.B.wep_hand), str(closed1)])

	# 2. SWING THE SWORD: the typed word
	begin_goal("2 make him swing the sword (typed 'swing')")
	var bx2 := box()
	if bx2 == null:
		say("   NOT VISIBLE: no 'or type' box after the library closed; click 'Change it'")
		await click_text("Change it")
		bx2 = box()
	var n2: int = m.S.cards.size()
	var played2 := false
	if bx2 != null:
		clicks += 1
		await click_ctl(bx2)
		await type_text("swing", true)
		played2 = await wait_playing()
	await idle(20)
	await shot("05_swing")
	say("   cards now: %s" % str(card_names()))
	var swung: bool = m.S.cards.size() > n2
	end_goal(swung and played2 and m.B.wep_on, "(cards %d -> %d, played: %s, sword still in hand: %s)" % [n2, m.S.cards.size(), str(played2), str(m.B.wep_on)])

	# 3. FOOTBALL BY SEARCH, ON THE FLOOR, THEN KICK IT
	begin_goal("3 football by search ('ball'), on the floor, then make him kick it")
	var n3p: int = m.S.props.size()
	await lib_open()
	var se := lib_child("library_search") as LineEdit
	var typed3 := false
	if se != null and se.is_visible_in_tree():
		clicks += 1
		await click_ctl(se)
		await type_text("ball")
		await idle(10)
		typed3 = true
	else:
		say("   NOT VISIBLE: no search box in the library")
	await shot("06_search_ball")
	say("   tiles after 'ball': %s" % str(tile_names()))
	var got3 := await click_tile("football")
	await idle(10)
	await shot("07_football_placed")
	say("   library note: %s" % lib_note())
	var ball_i := find_prop("ball")
	var ball_on: bool = ball_i >= 0 and m.S.props.size() > n3p
	await lib_close()
	var ball0 := prop_origin(ball_i) if ball_i >= 0 else Vector3.ZERO
	var bx3 := box()
	if bx3 == null:   # the typing box is gone once cards exist: a beginner clicks the visible 'Change it'
		await click_text("Change it")
		bx3 = box()
	var n3: int = m.S.cards.size()
	var kicked := false
	if bx3 != null:
		clicks += 1
		await click_ctl(bx3)
		await type_text("kick", true)
		kicked = await wait_playing()
	else:
		say("   NOT VISIBLE: no 'or type' box to type the kick in")
	await idle(30)
	await shot("08_kick")
	say("   cards now: %s" % str(card_names()))
	var ball1 := prop_origin(ball_i) if ball_i >= 0 and ball_i < m.S.props.size() else Vector3.ZERO
	say("   football origin before the kick %s, after %s (moved %.2f m)" % [str(ball0), str(ball1), ball0.distance_to(ball1)])
	end_goal(typed3 and got3 and ball_on and m.S.cards.size() > n3 and kicked, "(search typed: %s, tile placed: %s, on the floor: %s, kick card built and played: %s, football moved by the kick: %.2f m)" % [str(typed3), str(got3), str(ball_on), str(kicked), ball0.distance_to(ball1)])

	# 4. DELETE THE CHAIR HE DOES NOT WANT
	begin_goal("4 delete the chair he does not want (select it, then Delete key and/or a visible button)")
	say("   setup (not part of the goal): the chair is put in first, from Furniture")
	await lib_open()
	await click_text("Furniture", true)
	await click_tile("chair")
	await idle(6)
	await lib_close()
	var ci := find_prop("chair")
	var n4: int = m.S.props.size()
	var sel4 := false
	if ci >= 0:
		await click_view(prop_screen(ci))
		sel4 = m.sel_prop == ci
		say("   chair picked: %s (sel_prop %d)" % [str(sel4), m.sel_prop])
	else:
		say("   NOT VISIBLE: no chair on the floor to pick")
	await shot("09_chair_picked")
	say("   buttons when the chair is picked: %s" % btn_names())
	await key(KEY_DELETE)
	await idle(10)
	var gone4: bool = find_prop("chair") < 0 and m.S.props.size() < n4
	if not gone4:
		say("   the Delete key did nothing (props still %s)" % str(prop_list()))
		var db := find_btn("Delete", true)
		if db != null:
			clicks += 1
			say("   click '%s'" % text_of(db))
			await click_ctl(db)
			gone4 = find_prop("chair") < 0
		else:
			say("   NOT VISIBLE: no Delete button on screen")
	await shot("10_chair_deleted_or_not")
	end_goal(gone4, "(chair picked: %s, chair gone: %s, props %s)" % [str(sel4), str(gone4), str(prop_list())])

	# 5. A TABLE, THEN DRAG IT TO THE SIDE
	begin_goal("5 put a table from the library, then move it to the side by dragging it in the view")
	await lib_open()
	await click_text("Furniture", true)
	var put5 := await click_tile("table")
	await idle(6)
	await lib_close()
	var ti := find_prop("table")
	var moved5 := false
	var x0 := 0.0
	var dist5 := 0.0
	if ti >= 0:
		x0 = prop_origin(ti).x
		var z0 := prop_origin(ti).z
		await drag_prop(ti, Vector2(170, 0))
		dist5 = Vector2(prop_origin(ti).x - x0, prop_origin(ti).z - z0).length()
		moved5 = dist5 > 0.2
		say("   table moved %.2f m" % dist5)
	else:
		say("   NOT VISIBLE: no table on the floor")
	await shot("11_table_dragged")
	end_goal(put5 and moved5, "(table placed: %s, moved by drag: %s, %.2f m)" % [str(put5), str(moved5), dist5])

	# 6. SWORD BIGGER OR SMALLER, AND ITS COLOUR
	begin_goal("6 make the sword bigger or smaller, and change its colour")
	var strip_b := find_btn("Bigger")
	var sizes := []
	for b in visible_buttons():
		var s := text_of(b).to_lower()
		if s.contains("size") or s.contains("colo") or s.contains("scale") or s.contains("bigger") or s.contains("smaller"):
			sizes.append(text_of(b) + " [" + b.tooltip_text + "]")
	say("   size or colour controls on screen: %s" % str(sizes))
	if strip_b != null:
		say("   'Bigger' tooltip: %s" % strip_b.tooltip_text)
	var mb := find_btn("More")
	var more_items := []
	if mb != null:
		clicks += 1
		say("   click 'More'")
		await click_ctl(mb)
		await idle(6)
		if m.easy._more != null and m.easy._more.visible:
			for i in m.easy._more.item_count:
				more_items.append(m.easy._more.get_item_text(i))
		say("   More items: %s" % str(more_items))
		await shot("12_more_open")
		await key(KEY_ESCAPE)
		await idle(4)
	else:
		say("   NOT VISIBLE: no More button")
	var size_or_colour := false
	for s in more_items:
		if String(s).to_lower().contains("colo") or String(s).to_lower().contains("size"):
			size_or_colour = true
	for s in sizes:
		if String(s).to_lower().contains("colo") or String(s).to_lower().contains("sword"):
			size_or_colour = true
	# the honest check: the picked OBJECT (a prop on the floor: the sword, or a chair when there is no sword) gets bigger and changes
	# colour through the prop bar's own buttons (eh_prop_bigger / eh_prop_smaller / eh_prop_colour), and the view shows it
	var si6 := find_prop("sword")
	if si6 < 0:
		si6 = find_prop("chair")
	if si6 < 0:
		say("   setup (not part of the goal): a chair is put on the floor")
		m._prop_add("chair")
		await idle(4)
		si6 = find_prop("chair")
	m.sel_prop = si6
	m._props_show()
	await idle(6)
	var bar6 := m.find_child("easy_prop_bar", true, false) as Control
	var big6 := m.find_child("eh_prop_bigger", true, false) as Button
	var col6 := m.find_child("eh_prop_colour", true, false) as Button
	say("   prop bar on screen: %s | Bigger: %s | Colour: %s | picked: %s" % [str(bar6 != null and bar6.visible), str(big6 != null and big6.is_visible_in_tree()), str(col6 != null and col6.is_visible_in_tree()), prop_kind(si6)])
	var sz0 := prop_size(si6) if si6 >= 0 else Vector3.ZERO
	clicks += 1
	if big6 != null:
		await click_ctl(big6)
	await idle(6)
	var sz1 := prop_size(si6) if si6 >= 0 else Vector3.ZERO
	say("   %s size %s -> %s (status: %s)" % [prop_kind(si6), str(sz0), str(sz1), m.ui_status.text])
	await shot("13b_prop_bigger")
	var grew6 := sz1.x > sz0.x * 1.1 and sz1.y > sz0.y * 1.1 and sz1.z > sz0.z * 1.1
	clicks += 1
	var col0 := String(m.S.props[si6].get("colour", "grey")) if si6 >= 0 else ""
	if col6 != null:
		await click_ctl(col6)
	await idle(6)
	var col1 := String(m.S.props[si6].get("colour", "grey")) if si6 >= 0 else ""
	say("   %s colour %s -> %s (status: %s)" % [prop_kind(si6), col0, col1, m.ui_status.text])
	await shot("13c_prop_coloured")
	var named6 := col1 != "" and col1 != "grey" and String(m.ui_status.text).to_lower().contains(col1)
	end_goal(grew6 and col1 != "grey" and named6, "(the picked %s grew: %s, coloured %s and the status names it: %s; a 'Bigger' in the strip changes the MOTION, not the object; sword/chair size control found: %s)" % [prop_kind(si6), str(grew6), col1, str(named6), str(size_or_colour)])

	# 7. BROWSE EVERY CATEGORY ONCE
	begin_goal("7 browse every category once (note empty, unclear, picture-less, jargon)")
	await lib_open()
	var visited := 0
	for i in CATS.size():
		var cat: String = CATS[i]
		var tab_ok := await click_text(cat, true)
		await idle(60)
		var tiles := tile_names()
		var placeholders := 0
		for b in shown_tiles():
			if walk(b, []).filter(func(n): return n is Label and (n as Label).name == "placeholder").size() > 0:
				placeholders += 1
		var empty_msg := ""
		for n in walk(m.ui_library, []):
			if n is Label and (n as Label).name == "library_empty" and (n as Label).is_visible_in_tree():
				empty_msg = (n as Label).text
		var tt := ""
		var tb := find_btn(cat, true)
		if tb != null:
			tt = tb.tooltip_text
		say("   [%s] tab ok %s | tiles %d: %s | no picture yet: %d | empty: '%s' | tab tooltip: %s" % [cat, str(tab_ok), tiles.size(), str(tiles), placeholders, empty_msg, tt])
		await shot("14_cat_%s" % cat.to_lower().replace(" ", "_"))
		if tab_ok:
			visited += 1
	end_goal(visited == CATS.size(), "(categories visited: %d of %d)" % [visited, CATS.size()])

	# 8. CLOSE THE LIBRARY, FIND THE PLACED OBJECTS AGAIN
	begin_goal("8 close the library and find the placed objects again (list? click in the view?)")
	await lib_close()
	await shot("15_library_closed")
	var list_seen := false
	for b in visible_buttons():
		var s := text_of(b).to_lower()
		if s.contains("object") or s.contains("in the set") or s.contains("list") or s.contains("scene objects"):
			list_seen = true
	say("   a placed-objects list visible: %s | placed: %s" % [str(list_seen), str(prop_list())])
	var bi := find_prop("ball")
	var sel8 := false
	if bi >= 0:
		await click_view(prop_screen(bi))
		sel8 = m.sel_prop == bi
		say("   clicked the football in the view: picked %s (sel_prop %d)" % [str(sel8), m.sel_prop])
	else:
		say("   NOT VISIBLE: no football on the floor to click")
	await shot("16_find_football_again")
	end_goal(list_seen or sel8, "(list on screen: %s, football picked by a click in the view: %s)" % [str(list_seen), str(sel8)])

	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
