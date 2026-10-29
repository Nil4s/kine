extends SceneTree
## FPIPE (Nick 2026-10-28): a beginner who never read a manual builds a bent pipe with a flange from the BUILDING card. Real clicks at 1280x720.
## Walk (Easy): BUILDING -> Draw shape (Round) + drag a disc -> Pull it up -> Cut a hole (the flange ring) -> Curvy line (an OPEN bent path)
##   -> Expert -> Create: Sweep (the pipe). The path of the pipe is a sweep; Easy has no sweep button, so the walk must say so.
## Bars (run on the old code before the change: the FAIL lines are the dead ends):
##   0 the BUILDING card, one click: page BUILD, Easy Part on, the part is empty
##   1 Draw shape with the Round chip: a real drag draws a round shape (a circle sketch)
##   2 Pull it up, then Cut a hole: one solid with a hole (the flange ring)
##   3 P1 an OPEN Curvy line says how to make a pipe (Sweep), not only "drag back to the start to close it"
##   4 Expert is one click from Easy, and its bar has a Sweep tool
##   5 the Sweep tool opens its dialog with the profile and path pickers listing the sketches
## shots: C:/Temp/claude/fpipe/
const SHOT := "C:/Temp/claude/fpipe"
const DIRT := "user://fpipe_test"

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

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(50)
	await shot("01_open")
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy,
		"0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)

	# 1 Draw shape with the Round chip, a real drag on the grid
	await click_ctl(pu().ep.make_btns["draw"])
	await click_ctl(pu().ep.shape_btns["round"])
	await drag_path([Vector2(860, 500), Vector2(930, 560)])
	await shot("02_round")
	var sk_round := false
	for f in pu()._ensure().get("features", []):
		if f.get("t", "") == "sketch":
			for e in f.get("ents", []):
				if String(e.get("k", "")) == "circle":
					sk_round = true
	ok(sk_round, "1 Round chip + a real drag draws a round shape (a circle sketch)")

	# 2 Pull it up, then Cut a hole: one solid with a hole
	await click_ctl(pu().ep.make_btns["pull"])
	await click_ctl(pu().ep.make_btns["hole"])
	await idle(20)
	await shot("03_ring")
	var nb: int = int(pu().res.get("bodies", 0))
	ok(nb == 1, "2 Pull it up, then Cut a hole: one solid (bodies %d)" % nb)

	# 3 P1 an open Curvy line names the pipe's next step
	await click_ctl(pu().ep.make_btns["curve"])
	await drag_path([Vector2(300, 560), Vector2(370, 520), Vector2(430, 600), Vector2(500, 540)])
	await idle(10)
	await shot("04_curve")
	var say: String = pu().ep.hint_l.text
	ok(say.find("pipe") >= 0 and say.find("Sweep") >= 0, "3 P1 an open Curvy line names the pipe step (%s)" % say)

	# 4 Expert is one click from Easy (4a); the CREATE caption's menu (a beginner finds it on the ribbon) holds Sweep (4b)
	await click_ctl(pu().ep.expert_btn)
	await idle(20)
	await shot("05_expert")
	ok(not pu().easy, "4a Expert is one click from Easy (Easy off: %s)" % (not pu().easy))
	var cap: MenuButton = null
	for lst in m.ui_caps.values():
		for pair in lst:
			var has := false
			for b in pair[1]:
				if (b as Node).name == "part_tool_sweep":
					has = true
			if has and (pair[0] as Control).is_visible_in_tree():
				cap = pair[0]
	var sw_idx := -1
	if cap != null:
		await click_ctl(cap)
		await idle(5)
		for i in cap.get_popup().item_count:
			if cap.get_popup().get_item_text(i) == "Sweep":
				sw_idx = i
	await shot("06_create_menu")
	ok(cap != null and sw_idx >= 0, "4b the CREATE caption's menu lists Sweep (caption %s, item %d)" % [cap != null, sw_idx])

	# 5 picking Sweep from the menu opens the sweep dialog with the pickers listing the sketches
	if sw_idx >= 0:
		cap.get_popup().id_pressed.emit(cap.get_popup().get_item_id(sw_idx))
		cap.get_popup().hide()   # the menu closes on a real pick
		await idle(10)
		await shot("07_sweep")
	var np: int = pu().f_sw_prof.item_count if sw_idx >= 0 else -1
	var na: int = pu().f_sw_path.item_count if sw_idx >= 0 else -1
	ok(np >= 2 and na >= 2, "5 the Sweep dialog lists the sketches in both pickers (profile %d, path %d)" % [np, na])

	# 6 the Sweep words are plain: no profile, normal, chain or closed / open sketch on screen (the dialog, the tip, the error)
	var seen: Array = []
	texts_under(m, seen)
	var bad: Array = []
	for t in seen:
		var low := String(t).to_lower()
		for w in ["profile", "normal", "chain", "closed sketch", "open sketch", "square to"]:
			if low.find(w) >= 0:
				bad.append(String(t))
	ok(bad.is_empty(), "6 the Sweep words are plain (no profile / normal / chain on screen: %s)" % str(bad.slice(0, 3)))

	print("fpipe: %d fail" % fails)
	quit(1 if fails > 0 else 0)
