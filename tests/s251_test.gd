extends SceneTree
## s251 TOOL LABELS AND THE TOP BAR at 1024 x 600 .. 2560 x 1440, Easy and Expert: no label breaks inside a word ("Stick togeth / er"),
## no top-bar button is cut with an ellipsis ("Save and ...", "Give to a c..."). A button's room is its box less its stylebox margins (and a side icon);
## a wrapped label breaks only at spaces, so every WORD must fit that room; a one-line label must fit whole and may not be clipped or hold "..." / the ellipsis.
## A short label keeps the full name in its tooltip. Real clicks: Undo, Redo, Fix it, Library still fire.
## CONTROL: the old layout (14 px "together" in the 12-button row's room at 1024; "Save and use in a scene" trimmed in 96 px) is run through the same check and must fail.
## Shots: C:/Users/Nick/tools/kine_workers/out/251/
var fails := 0
var m: Node
var pu
var ep
const SHOT := "C:/Users/Nick/tools/kine_workers/out/251"
const DIRT := "user://s251_test"
const SIZES := [[1024, 600], [1280, 720], [1920, 1080], [2560, 1440]]


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


## the room a button's words have: its box less the stylebox margins and a side icon
func room_of(b: Button) -> float:
	var r := b.size.x - b.get_theme_stylebox("normal").get_minimum_size().x
	if b.icon != null and b.vertical_icon_alignment != VERTICAL_ALIGNMENT_TOP and b.text != "":
		r -= b.icon.get_size().x + b.get_theme_constant("h_separation")
	return r


## verdict for text t at font size fs in a room of rm px: "" when fine, else the reason (a word split / a clipped or ellipsised line)
func verdict(f: Font, t: String, fs: int, rm: float, wrap: bool, clip: bool) -> String:
	if t.contains("\u2026") or t.contains("..."):
		return "has an ellipsis"
	if wrap:
		for w in t.split(" ", false):
			var ww := f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if ww > rm + 0.5:
				var cut := maxi(1, int(w.length() * rm / ww))
				return "word \"%s\" is %.0f px in a %.0f px room: it breaks inside the word (%s/%s)" % [w, ww, rm, w.left(cut), w.substr(cut)]
		return ""
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > rm + 6.0 or (clip and tw > rm + 0.5):   # an unclipped one-line button grows to its text (the window-edge bar catches a row that grows too far)
		return "\"%s\" is %.0f px in a %.0f px room (%s)" % [t, tw, rm, "clipped / ellipsised" if clip else "overflows"]
	return ""


func btn_verdict(b: Button) -> String:
	return verdict(b.get_theme_font("font"), b.text, b.get_theme_font_size("font_size"), room_of(b), b.autowrap_mode != TextServer.AUTOWRAP_OFF, b.clip_text)


func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).text != "":
		var r := (n as Control).get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0 and (n as CanvasItem).modulate.a > 0.05:
			out.append(n)
	for ch in n.get_children():
		_collect(ch, out)


## the buttons under test: the top bar (bottom edge within the bar's height) and the tool buttons (Easy: the MAKE row; Expert: the Part toolbar)
func under_test(expert: bool) -> Array:
	var all := []
	_collect(root, all)
	var out := []
	var bar_h: float = float(m.TOP_H) + 6.0
	for b in all:
		var r := (b as Control).get_global_rect()
		var is_bar: bool = r.end.y <= bar_h
		var is_tool: bool = String(b.name).begins_with("easypart_make_") or (expert and pu != null and pu.part_give != null and b.get_parent() == pu.part_give.get_parent())
		if is_bar or is_tool:
			out.append(b)
	return out


func check(tag: String, expert: bool) -> int:
	var n := 0
	var vr := root.get_visible_rect()
	var bad := []
	for b in under_test(expert):
		n += 1
		var v := btn_verdict(b)
		var r := (b as Control).get_global_rect()
		if v != "":
			bad.append("%s '%s': %s" % [b.name, b.text, v])
		if not vr.grow(1.0).encloses(r):
			bad.append("%s '%s' rect %s outside the window %s" % [b.name, b.text, r, vr])
	ok(bad.is_empty() and n > 5, "%s %d buttons: no word split, no ellipsis, all inside the window %s" % [tag, n, str(bad)])
	return n


func shortened_ok(tag: String) -> void:
	var full := {"use_scene_btn": "Save and use in a scene", "give_btn": "Give to a character", "restore_btn": "Bring back your part"}
	for k in full:
		var b: Button = ep.get(k)
		if b == null or not b.is_visible_in_tree():
			continue
		ok(b.text == full[k] or b.tooltip_text.begins_with(String(full[k])), "%s %s shows '%s' and its tooltip names '%s' (%s)" % [tag, k, b.text, full[k], b.tooltip_text.left(40)])
	for k in ep.make_btns:
		var b: Button = ep.make_btns[k]
		if not b.is_visible_in_tree():
			continue
		var fn := ""
		for mk in ep.MAKES:
			if mk[0] == k:
				fn = String(mk[1])
		ok(b.text == fn or b.tooltip_text.begins_with(fn), "%s make %s shows '%s', full name '%s' in the tooltip" % [tag, k, b.text, fn])


func fresh() -> void:
	m.S.part = {}
	pu.sync()
	await idle(10)


func clicks(tag: String) -> void:
	for pair in [[ep.undo_btn, "Undo"], [ep.redo_btn, "Redo"], [ep.fix_btn, "Fix it"]]:
		var b: Button = pair[0]
		var cnt := [0]
		var cb := func(): cnt[0] += 1
		b.pressed.connect(cb)
		await click_ctl(b)
		b.pressed.disconnect(cb)
		ok(cnt[0] == 1, "%s a real click on '%s' (shown '%s') presses it once (%d)" % [tag, pair[1], b.text, cnt[0]])
	var lb: Button = ep.lib_bar_btn
	var before: bool = ep.parts_open
	await click_ctl(lb)
	await idle(8)
	ok(ep.parts_open != before, "%s a real click on Library toggles the Parts page (%s -> %s)" % [tag, before, ep.parts_open])
	await click_ctl(lb)
	await idle(8)


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
		var pb := root.find_child("easypart_chip_parts", true, false) as Button
		if ep.parts_open:
			await click_ctl(pb)
			await idle(6)
		ep.layout(ep._cl)
		await idle(4)
		await check(tag + " Easy", false)
		shortened_ok(tag + " Easy")
		if w == 1024:
			await shot("easy_%s" % tag)
		await clicks(tag + " Easy")
		# a saved part brings the Bring back button onto the bar
		ep.restore_btn.visible = true
		ep.layout(ep._cl)
		await idle(4)
		if w >= 99999:
			for b in under_test(false):
				if b.get_global_rect().end.y <= 80.0:
					print("     BAR ", b.name, " '", b.text, "' ", b.get_global_rect(), " min ", b.get_combined_minimum_size())
		await check(tag + " Easy+restore", false)
		shortened_ok(tag + " Easy+restore")
		if w == 1024:
			await shot("easy_restore_%s" % tag)
		ep.restore_btn.visible = false
		# Expert
		ep.to_expert()
		await idle(10)
		await check(tag + " Expert", true)
		if w == 1024:
			await shot("expert_%s" % tag)
		if not ep.panel.is_visible_in_tree():
			if not pu.easy_open_btn.is_visible_in_tree():
				await click_ctl(pu.part_btn)
			await click_ctl(pu.easy_open_btn)
			await idle(8)
	# CONTROL: the old layout through the same check. "Stick together" at 14 px in the 12-button row's room at 1024 (80 px box); the old bar words in 96 px.
	var f14: Font = ep.make_btns["stick"].get_theme_font("font")
	var old_make := verdict(f14, "Stick together", 14, 64.0 - 16.0, true, false)
	print("     CONTROL old Stick together: ", old_make)
	ok(old_make.contains("togeth/er"), "control: the old 14 px 'Stick together' in a 64 px button (the 1024 row: (1024 - 88) / 12 less margins) is reported split (togeth/er): %s" % old_make)
	var fb: Font = ep.undo_btn.get_theme_font("font")
	var old_bar := verdict(fb, "Save and use in a scene", 16, 96.0 - 16.0, false, true)   # old: clip_text on, 96 px
	ok(old_bar != "", "control: the old 'Save and use in a scene' trimmed in a 96 px button is reported clipped: %s" % old_bar)
	ok(verdict(fb, "Save and ...", 16, 300.0, false, true) == "has an ellipsis", "control: 'Save and ...' is reported as an ellipsis")
	print("s251: %d fail" % fails)
	quit(1 if fails > 0 else 0)
