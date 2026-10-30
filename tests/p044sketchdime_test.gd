extends SceneTree
## p044sketchdime (Friday plan item 44: Sketch dimensions shown live while drawing). A beginner on the BUILDING card blank Easy Part, real mouse moves and clicks only.
## Draw shape: press on the grid and HOLD. While the box is still being dragged, every side shows its length in mm beside the side (4 small labels).
## The labels follow the corner as the mouse moves, and go away on release. Nothing is a step: the record does not change while holding.
## Measured from the built mesh (mm) and from the label text and the screen, never from the code own variables.
## Bars (written before the code: 0 to 9 FAIL on the old code, there are no labels):
##   0 before any press, no draft length label is visible
##   1 holding a 60 x 60 mm square on the grid: exactly 4 length labels are visible
##   2 the 4 labels read 60, 60, 60, 60 mm (each within 0.5 mm of the drawn side)
##   3 holding the corner out to 80 x 60 mm: the labels read two 80 mm and two 60 mm (each within 0.5 mm)
##   4 every side middle on screen has a label centre within 90 px, and every label is fully inside 1280 x 720
##   5 every label text is plain words: a number then " mm"
##   6 holding does not change the step count (the labels are not a step)
##   7 releasing the press hides all 4 labels
##   8 after Pull it up, the built X size equals the 80 mm label within 1 mm
##   9 after Pull it up, the built Z size equals the 60 mm label within 1 mm
## shots: C:/Temp/claude/p044sketchdime/s1/live.png (the labels while held)
const SHOT := "C:/Temp/claude/p044sketchdime/s1"
const DIRT := "user://p044sketchdime_test"

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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	if c == null:
		return   # a missing button: the bars that follow say so
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the solid corners as the built mesh has them (metres, world)
func verts() -> PackedVector3Array:
	var mesh: ArrayMesh = pu().part_mesh.mesh
	if mesh == null:
		return PackedVector3Array()
	return mesh.get_faces()


func bounds(vs: PackedVector3Array) -> AABB:
	var b := AABB()
	if vs.is_empty():
		return b
	b = AABB(vs[0], Vector3.ZERO)
	for v in vs:
		b = b.expand(v)
	return b


func labels() -> Array:
	return root.find_children("easypart_draft_dim_*", "Label", true, false)


func shown_labels() -> Array:
	var out := []
	for l in labels():
		if (l as Label).is_visible_in_tree():
			out.append(l)
	return out


func feats() -> int:
	return (pu().ep._rec().get("features", []) as Array).size()


## the numbers of the shown labels (mm), sorted; a label that is not a number reads as -1
func label_mm() -> Array:
	var out := []
	for l in shown_labels():
		var t := String((l as Label).text).strip_edges()
		out.append(float(t.replace("mm", "").strip_edges()) if t.replace("mm", "").strip_edges().is_valid_float() else -1.0)
	out.sort()
	return out


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
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 0 nothing drawn yet: no draft label
	await click_ctl(pu().ep.make_btns["draw"])
	await ev_move(scr(Vector3(0.1, 0.0, 0.1)))
	await idle(5)
	ok(shown_labels().is_empty(), "0 before any press, no draft length label is visible (%d)" % shown_labels().size())

	# the square: press at (-30, -30) mm, HOLD and drag to (30, 30) mm, the mouse still down
	var a := scr(Vector3(-0.03, 0.0, -0.03))
	var b := scr(Vector3(0.03, 0.0, 0.03))
	await ev_move(a)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0), true)
	await idle(5)
	var n0 := feats()
	var lm := label_mm()
	ok(shown_labels().size() == 4, "1 holding a 60 x 60 mm square: exactly 4 length labels are visible (%d)" % shown_labels().size())
	ok(lm.size() == 4 and absf(lm[0] - 60.0) <= 0.5 and absf(lm[3] - 60.0) <= 0.5, "2 the 4 labels read 60 mm (%s)" % str(lm))
	await shot("live")

	# the corner moves out to (50, 30) mm: an 80 x 60 mm box, still held
	var c := scr(Vector3(0.05, 0.0, 0.03))
	for i in range(1, 9):
		await ev_move(b.lerp(c, i / 8.0), true)
	await idle(5)
	lm = label_mm()
	ok(lm.size() == 4 and absf(lm[0] - 60.0) <= 0.5 and absf(lm[1] - 60.0) <= 0.5 and absf(lm[2] - 80.0) <= 0.5 and absf(lm[3] - 80.0) <= 0.5, "3 holding 80 x 60 mm: the labels read two 60 and two 80 mm (%s)" % str(lm))

	# 4 each side middle has a label near it, and every label is on screen
	var corners := [Vector3(-0.03, 0, -0.03), Vector3(0.05, 0, -0.03), Vector3(0.05, 0, 0.03), Vector3(-0.03, 0, 0.03)]
	var near := true
	for k in 4:
		var mid := scr((corners[k] + corners[(k + 1) % 4]) * 0.5)
		var best := INF
		for l in shown_labels():
			best = minf(best, ((l as Label).get_global_rect().get_center()).distance_to(mid))
		near = near and best <= 90.0
	var inside := true
	for l in shown_labels():
		var r := (l as Label).get_global_rect()
		inside = inside and r.position.x >= 0 and r.position.y >= 0 and r.end.x <= 1280 and r.end.y <= 720
	ok(near and inside, "4 every side has its label within 90 px of its middle, all labels inside 1280 x 720 (near %s, inside %s)" % [near, inside])

	# 5 plain words: a number then " mm"
	var plain := true
	for l in shown_labels():
		var t := String((l as Label).text)
		plain = plain and t.ends_with(" mm") and t.trim_suffix(" mm").is_valid_float()
	ok(plain, "5 every label reads like '80 mm'")

	# 6 holding is not a step
	ok(feats() == n0, "6 holding the press does not change the step count (%d -> %d)" % [n0, feats()])

	# 7 release: the labels go away
	await ev_mouse(c, false)
	await idle(5)
	ok(shown_labels().is_empty(), "7 releasing the press hides all 4 labels (%d still shown)" % shown_labels().size())

	# 8 and 9 the built box matches the labels
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	var bb := bounds(verts())
	ok(absf(bb.size.x * 1000.0 - 80.0) <= 1.0, "8 the built X size is the 80 mm label (%.2f mm)" % (bb.size.x * 1000.0))
	ok(absf(bb.size.z * 1000.0 - 60.0) <= 1.0, "9 the built Z size is the 60 mm label (%.2f mm)" % (bb.size.z * 1000.0))
	print("p044sketchdime: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
