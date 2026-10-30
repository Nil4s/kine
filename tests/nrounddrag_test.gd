extends SceneTree
## NROUNDDRAG (Friday plan item 11, Nick: "dragging an edge itself outward rounds it: the drag distance is the radius, the number
## rides beside the cursor, release = one undo step"): a beginner from the BUILDING card, Easy Part, real clicks and drags at 1280 x 720.
## The part: a box drawn on the floor (Draw shape, Box), Pull it up. Then the nearer top edge is dragged 4 mm outward.
## Bars (all measured from the BUILT result: Part.replay of the saved record, mm; never the code's own variables):
##   R0 the box is built: one body, x 38..42 mm, z 18..22 mm, volume within 10 pct of x*y*z
##   R1 the edge drag rounds that edge: radius from the removed volume (1 - pi/4) r^2 L, L = the built edge length, is 4 mm +- 0.6
##   R2 the number rides beside the cursor during the drag: a visible label reads an integer 3 or 4 or 5 and "mm"
##   R3 release is ONE undo step: the undo list grows by exactly 1, and Undo puts the box back (volume within 0.5 pct)
##   R4 the words during and after: plain (no sketch, extrude, loft, boolean, feature, body, fillet), and the line is not empty
##   R5 a drag that starts on a flat face (not an edge) rounds nothing and adds no undo step
## shots: C:/Temp/claude/nrounddrag/box.png, edge.png, rounded.png
const SHOT := "C:/Temp/claude/nrounddrag"
const DIRT := "user://nrounddrag_test"
const BAD := ["sketch", "extrude", "loft", "boolean", "feature", "body", "fillet"]
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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func say_now(ep) -> String:
	return String(ep.hint_l.text) + " | " + String(ep.msg)


func jargon(s: String) -> String:
	for w in BAD:
		if s.to_lower().find(w) >= 0:
			return w
	return ""


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
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# the box: Draw shape, Box, a 40 x 20 mm corner-to-corner drag on the floor, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.01)), scr(Vector3(0.02, 0.0, 0.01))])
	await click_ctl(ep.make_btns["pull"])
	await idle(15)
	var s0: Dictionary = Part.replay(m.S.part)
	var bb0: AABB = s0["aabb"]
	var v0 := vol_mm3(s0)
	var sx := bb0.size.x / Part.MM
	var sz := bb0.size.z / Part.MM
	var sy := bb0.size.y / Part.MM
	ok(int(s0["bodies"]) == 1 and absf(sx - 40.0) <= 2.0 and absf(sz - 20.0) <= 2.0 and absf(v0 - sx * sy * sz) <= 0.1 * sx * sy * sz,
		"R0 the box is built: one body, x %.1f z %.1f y %.1f mm, volume %.0f mm3" % [sx, sz, sy, v0])
	await shot("box")

	# the edge: the top edge nearer the camera (y = top, z = +-half depth), dragged 4 mm straight outward from the middle of the box
	var top := bb0.end.y
	var zh := bb0.size.z * 0.5
	var zs := zh if m.cam.global_position.z > 0.0 else -zh
	var mid := Vector3(0.0, top, zs)
	var ctr := Vector3(0.0, top * 0.5, 0.0)
	var outv := (scr(mid) - scr(ctr)).normalized()
	var px_mm := (scr(mid + (mid - ctr).normalized() * 0.001) - scr(mid)).length()
	var press := scr(mid)
	var n_before: int = m.undo.size()
	await ev_move(press, false)
	await ev_mouse(press, true)
	var steps := 12
	for i in range(1, steps + 1):
		await ev_move(press + outv * (4.0 * px_mm) * float(i) / steps)
	await idle(3)
	var num_txt := ""
	for l in root.find_children("EdgeNum", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			num_txt = (l as Label).text
	await shot("edge")
	await ev_mouse(press + outv * (4.0 * px_mm), false)
	await idle(15)
	var s1: Dictionary = Part.replay(m.S.part)
	var v1 := vol_mm3(s1)
	var bb1: AABB = s1["aabb"]
	var L := bb1.size.x / Part.MM
	var removed := v0 - v1
	var r_meas := sqrt(maxf(removed, 0.0) / ((1.0 - PI / 4.0) * L))
	ok(int(s1["bodies"]) == 1 and absf(r_meas - 4.0) <= 0.6,
		"R1 the edge drag rounds that edge: removed %.1f mm3 of %.0f, radius %.2f mm from the built result (4 mm +- 0.6), one body %s" % [removed, v0, r_meas, int(s1["bodies"]) == 1])
	var nums := num_txt.strip_edges()
	var num_ok := nums.ends_with("mm") and (nums.begins_with("3") or nums.begins_with("4") or nums.begins_with("5"))
	ok(num_ok, "R2 the number beside the cursor during the drag reads 3-5 mm (label text: '%s')" % nums)
	var n_after: int = m.undo.size()
	ok(n_after - n_before == 1, "R3a release is ONE undo step: the undo list grew by %d" % (n_after - n_before))
	var words := say_now(ep)
	var j := jargon(words)
	ok(j == "" and words.strip_edges().length() > 3, "R4 the words after the drag are plain and not empty (jargon [%s], words [%s])" % [j, words])
	await shot("rounded")
	m._undo()
	await idle(15)
	var vu := vol_mm3(Part.replay(m.S.part))
	ok(absf(vu - v0) <= 0.005 * v0, "R3b Undo puts the box back: volume %.0f mm3 (box %.0f, within 0.5 pct)" % [vu, v0])

	# R5: a drag on a flat face (the top's middle) rounds nothing and adds no undo step
	var n5: int = m.undo.size()
	var fp := scr(Vector3(0.0, top, 0.0))
	await drag_pts([fp, fp + Vector2(0, -40)])
	await idle(10)
	var v5 := vol_mm3(Part.replay(m.S.part))
	ok(absf(v5 - v0) <= 0.005 * v0 and m.undo.size() == n5,
		"R5 a drag on a flat face rounds nothing: volume %.0f (box %.0f), undo steps %d -> %d" % [v5, v0, n5, m.undo.size()])

	print("NROUNDDRAG %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
