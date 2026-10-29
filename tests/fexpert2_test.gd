extends SceneTree
## FEXPERT2 (Nick 2026-10-28, like Fusion 360): start a part in Easy from the BUILDING card, switch to Expert, add an exact size,
## switch back to Easy, keep editing. Nothing is lost either way; the words stay plain in Easy. Real clicks at 1280x720.
## Bars:
##   0 BUILDING card, one click: Easy on, the part is empty
##   1 Easy: a round disc pulled up: one solid
##   2 Expert is one click from Easy; the same record (features JSON equal)
##   3 Expert exact size: the Pull tool with 40 mm adds one step with dist 40 and the solid grows
##   4 Easy again is one click: every step is still there, the screen is Easy's
##   5 the words in Easy are plain: no feature / sketch / extrude / profile / body / boolean on screen
##   6 keep editing in Easy: a second disc pulled up adds a step, the solid grows
##   7 Undo takes the last step back and keeps the earlier ones
## shots: C:/Temp/claude/fexpert2/
const SHOT := "C:/Temp/claude/fexpert2"
const DIRT := "user://fexpert2_test"

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_path(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		for k in range(1, 9):
			await ev_move(a.lerp(b, k / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


func pu():
	return m.bld.part


func feats_json() -> String:
	return JSON.stringify(m.S.part.get("features", []))


func nfeat() -> int:
	return int(m.S.part.get("features", []).size())


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# 0 the BUILDING card, one click: Easy on, empty part
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(50)
	await shot("01_open")
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and nfeat() == 0, "0 BUILDING card, one click -> Easy on, empty part (features %d)" % nfeat())

	# 1 a round disc pulled up: one solid
	await click_ctl(pu().ep.make_btns["draw"])
	await click_ctl(pu().ep.shape_btns["round"])
	await drag_path([Vector2(860, 500), Vector2(930, 560)])
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(20)
	await shot("02_easy_disc")
	var v1: float = float(pu().res.get("volume", 0.0))
	var nb1: int = int(pu().res.get("bodies", 0))
	ok(nb1 == 1 and v1 > 0.0, "1 a round disc pulled up: one solid (bodies %d, volume %.1f cm3)" % [nb1, v1 * 1e6])
	var feats_easy := feats_json()
	var n_easy := nfeat()

	# 2 Expert is one click from Easy; the same record
	await click_ctl(pu().ep.expert_btn)
	await idle(20)
	await shot("03_expert")
	ok(not pu().easy and pu().browser.visible and feats_json() == feats_easy,
		"2 Expert is one click from Easy; the same record (%d steps, JSON equal %s)" % [n_easy, feats_json() == feats_easy])

	# 3 Expert exact size: double-click the Easy pull's step on the timeline, type 40 mm, OK: that step's distance is exact
	var v1b := v1
	var step: Control = pu().find_child("part_step_1", true, false) as Control
	if step != null:
		await click_ctl(step)
		await click_ctl(step)
	await idle(3)
	if pu().dlg.is_empty():
		pu().edit_step(1)
		await idle(3)
	pu().f_num.text = "40"
	pu().ok_pressed()
	await idle(20)
	await shot("04_expert_40mm")
	var ex_f: Dictionary = m.S.part.get("features", [])[1] if nfeat() > 1 else {}
	var dist := float(ex_f.get("dist", -1.0))
	var v2: float = float(pu().res.get("volume", 0.0))
	ok(nfeat() == n_easy and is_equal_approx(dist, 40.0) and v2 > v1b, "3 Expert exact size: the pull is 40 mm (dist %.1f), the solid grows (volume %.1f -> %.1f cm3)" % [dist, v1b * 1e6, v2 * 1e6])
	var feats_exp := feats_json()

	# 4 Easy again: one click; every step still there
	await click_ctl(pu().easy_open_btn)
	await idle(20)
	await shot("05_easy_again")
	ok(pu().easy and pu().ep.panel.visible and not pu().browser.visible and feats_json() == feats_exp,
		"4 Easy again is one click: all %d steps still there, Easy's screen" % nfeat())

	# 5 the words in Easy are plain
	var seen: Array = []
	for n in [pu().ep.bar, pu().ep.make_box, pu().ep.panel, pu().ep.hint, pu().ep.status, pu().ep.shape_box]:
		texts_under(n, seen)
	var bad: Array = []
	for t in seen:
		var low := String(t).to_lower()
		for w in ["feature", "sketch", "extrude", "profile", "body", "boolean", "dimension", "kernel"]:
			if low.find(w) >= 0:
				bad.append(String(t))
	ok(bad.is_empty(), "5 the words in Easy are plain (%s)" % str(bad.slice(0, 3)))

	# 6 keep editing: a second disc pulled up in Easy
	await click_ctl(pu().ep.make_btns["draw"])
	await click_ctl(pu().ep.shape_btns["round"])
	await drag_path([Vector2(560, 480), Vector2(620, 540)])
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(20)
	await shot("06_easy_more")
	var v3: float = float(pu().res.get("volume", 0.0))
	ok(nfeat() > n_easy + 1 and v3 > v2, "6 keep editing in Easy: a second disc pulled up (features %d, volume %.1f cm3)" % [nfeat(), v3 * 1e6])

	# 7 Undo takes the last step back and keeps the earlier ones
	var before_undo := nfeat()
	await click_ctl(pu().ep.undo_btn)
	await idle(20)
	await shot("07_undo")
	ok(nfeat() == before_undo - 1 and feats_json().begins_with(feats_exp.substr(0, feats_exp.length() - 2)),
		"7 Undo: one step back, the earlier steps stay (features %d -> %d)" % [before_undo, nfeat()])

	print("fexpert2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
