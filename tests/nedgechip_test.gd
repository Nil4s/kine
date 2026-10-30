extends SceneTree
## NEDGECHIP (Friday plan item 10: Smart edge chip). A beginner on the BUILDING card blank Easy Part, real mouse moves and clicks only.
## A box is drawn and pulled up 2 cm. Hovering an edge of the BUILT solid (no press) shows ONE small chip with what that edge can do
## (Round, Bevel) and a see-through ghost of the result. Clicking a chip makes that one edge rounded or bevelled: one undo step each.
## Measured from the built mesh (mm, px), never from the code own variables.
## Bars (run before the code: 1 to 12 FAIL on the old code, there is no chip):
##   1 hovering the top edge along Z (no press) shows the chip with a Round button
##   2 the chip sits on screen within 120 px of that edge middle, fully inside 1280 x 720
##   3 each chip button is at least 40 px tall, and the chip holds Round and Bevel
##   4 the ghost shows: visible, transparent, and its edge corner is rounded (nearest vertex 0.2 to 2.0 mm from the sharp corner line)
##   5 the built solid before the press is still sharp (nearest vertex 0 mm from the corner line)
##   6 a real click on the Round chip: the built edge is rounded (nearest vertex 0.2 to 2.0 mm), one fillet step in the record
##   7 one Undo takes the round back: the record has one step less and the edge is sharp again (0 mm)
##   8 hovering the top edge along X shows a Bevel button; a real click on it: built edge cut flat (nearest vertex 0.5 to 2.0 mm)
##   9 one Undo takes the bevel back, the solid is sharp again
##  10 hovering empty grid hides the chip; hovering an edge while Draw shape is armed shows no chip
##  11 no jargon on screen (fillet, chamfer, kernel, mesh, manifold, extrude, revolve)
##  12 an edge hover does not change the record (the step count stays the same after hovering)
## shots: C:/Temp/claude/nedgechip/s1/hover.png (chip and ghost), bevel.png (after the bevel)
const SHOT := "C:/Temp/claude/nedgechip/s1"
const DIRT := "user://nedgechip_test"
const JARGON := ["fillet", "chamfer", "kernel", "mesh", "manifold", "extrude", "revolve"]

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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0), true)
	await ev_mouse(b, false)
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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the solid corners as the built mesh has them (metres, world)
func verts() -> PackedVector3Array:
	var mesh: ArrayMesh = pu().part_mesh.mesh
	if mesh == null:
		return PackedVector3Array()
	return mesh.get_faces()   # the triangle corners that are drawn (an unused vertex in the array is not part of the solid)


func bounds(vs: PackedVector3Array) -> AABB:
	var b := AABB()
	if vs.is_empty():
		return b
	b = AABB(vs[0], Vector3.ZERO)
	for v in vs:
		b = b.expand(v)
	return b


## the nearest vertex to the sharp edge line, in mm. axis 2 (Z edge): the line x = a, y = b; axis 0 (X edge): y = a, z = b.
## every built vertex counts: a box has its corners only at the ends, a rounded or bevelled edge has its new vertices along the length
func nearest_mm(vs: PackedVector3Array, axis: int, a: float, b: float) -> float:
	var best := INF
	for v in vs:
		var d := Vector2.ZERO
		if axis == 2:
			d = Vector2(v.x - a, v.y - b)
		else:
			d = Vector2(v.y - a, v.z - b)
		best = minf(best, d.length() * 1000.0)
	return best if best < INF else -1.0


func chip() -> Control:
	return m.find_child("easypart_edge_chip", true, false) as Control


func chip_btn(w: String) -> Button:
	var c := chip()
	if c == null:
		return null
	for b in c.find_children("*", "Button", true, false):
		if (b as Button).text == w and (b as Button).is_visible_in_tree():
			return b
	return null


func chip_shown() -> bool:
	var c := chip()
	return c != null and c.is_visible_in_tree()


func ghost() -> MeshInstance3D:
	return m.find_child("easypart_edge_ghost", true, false) as MeshInstance3D


func feats() -> int:
	return (pu().ep._rec().get("features", []) as Array).size()


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


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

	# a 6 cm square drawn on the grid and pulled up 2 cm (real clicks)
	var draw = pu().ep.make_btns["draw"]
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	var bb := bounds(verts())
	ok(bb.size.y > 0.015 and bb.size.x > 0.05, "setup: a box is built (%.1f x %.1f x %.1f mm)" % [bb.size.x * 1000, bb.size.y * 1000, bb.size.z * 1000])
	if bb.size.y <= 0.015:
		print("nedgechip: cannot continue")
		quit(1)
		return

	# the top edge along Z at the +X side, and the top edge along X at the +Z side (both from the built mesh)
	var xmax := bb.end.x
	var ymax := bb.end.y
	var zmax := bb.end.z
	var zmid := (bb.position.z + bb.end.z) * 0.5
	var xmid := (bb.position.x + bb.end.x) * 0.5
	var pz := scr(Vector3(xmax, ymax, zmid))
	var px := scr(Vector3(xmid, ymax, zmax))
	ok(nearest_mm(verts(), 2, xmax, ymax) == 0.0 and nearest_mm(verts(), 0, ymax, zmax) == 0.0, "setup: the box corners are sharp before any chip")

	var n0 := feats()
	# 1 hover the top edge along Z (real move, no press)
	await ev_move(pz)
	await ev_move(pz + Vector2(1, 0))
	await idle(10)
	var rb := chip_btn("Round")
	ok(chip_shown() and rb != null, "1 hovering the top edge shows the chip with a Round button (chip %s)" % chip_shown())
	await shot("hover")

	# 2 on screen, near the edge
	var cr := chip().get_global_rect() if chip() != null else Rect2()
	var near := cr.get_center().distance_to(pz)
	ok(cr.size.x > 0 and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(cr) and near <= 120.0, "2 the chip is on screen, %.0f px from the edge middle at %s" % [near, pz])

	# 3 button size and words
	var words := []
	var small := 0
	if chip() != null:
		for b in chip().find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree():
				words.append((b as Button).text)
				if (b as Button).get_global_rect().size.y < 40.0:
					small += 1
	ok(small == 0 and words.has("Round") and words.has("Bevel"), "3 every chip button is 40 px or taller (%d short), words %s" % [small, words])

	# 4 the ghost: visible, see-through, its edge corner rounded (measured from its own mesh)
	var g := ghost()
	var gv := PackedVector3Array()
	if g != null and g.mesh != null:
		gv = g.mesh.get_faces()
	var gd := nearest_mm(gv, 2, xmax, ymax)
	var see := g != null and g.is_visible_in_tree() and g.material_override != null and (g.material_override as BaseMaterial3D).albedo_color.a < 0.7
	ok(see and gd >= 0.2 and gd <= 2.0, "4 the ghost is see-through and its edge is rounded: %.2f mm from the sharp corner" % gd)
	ok(nearest_mm(verts(), 2, xmax, ymax) == 0.0, "5 the built solid is still sharp before the press")
	var fb := feats()
	ok(fb == n0, "12 hovering changed nothing (steps %d -> %d)" % [n0, fb])

	# 6 a real click on Round
	await click_ctl(rb)
	await idle(30)
	var rd := nearest_mm(verts(), 2, xmax, ymax)
	ok(feats() == n0 + 1 and rd >= 0.2 and rd <= 2.0, "6 a click on Round rounds that edge: %.2f mm from the sharp corner, steps %d -> %d" % [rd, n0, feats()])
	await shot("rounded")

	# 7 one Undo takes it back
	await click_ctl(pu().ep.undo_btn)
	await idle(30)
	var ud := nearest_mm(verts(), 2, xmax, ymax)
	ok(feats() == n0 and ud == 0.0, "7 one Undo takes the round back: steps %d, %.2f mm" % [feats(), ud])

	# 8 the top edge along X: a Bevel button, a click cuts it flat
	await ev_move(px)
	await ev_move(px + Vector2(1, 0))
	await idle(10)
	var bev := chip_btn("Bevel")
	ok(chip_shown() and bev != null, "8a hovering the top edge along X shows a Bevel button")
	if bev != null:
		await click_ctl(bev)
		await idle(30)
		var bd := nearest_mm(verts(), 0, ymax, zmax)
		ok(feats() == n0 + 1 and bd >= 0.5 and bd <= 2.0, "8 a click on Bevel cuts that edge flat: %.2f mm from the sharp corner, steps %d -> %d" % [bd, n0, feats()])
		await shot("bevel")
		# 9 one Undo takes the bevel back
		await click_ctl(pu().ep.undo_btn)
		await idle(30)
		var bu := nearest_mm(verts(), 0, ymax, zmax)
		ok(feats() == n0 and bu == 0.0, "9 one Undo takes the bevel back: steps %d, %.2f mm" % [feats(), bu])
	else:
		ok(false, "9 (no bevel to undo)")

	# 10 empty grid hides the chip; an armed Draw shape shows no chip on an edge
	await ev_move(scr(Vector3(0.3, 0.0, 0.3)))
	await idle(6)
	ok(not chip_shown(), "10a hovering empty grid hides the chip")
	await click_ctl(draw)
	await ev_move(pz)
	await ev_move(pz + Vector2(1, 0))
	await idle(6)
	ok(not chip_shown(), "10b with Draw shape armed, an edge shows no chip")
	await click_ctl(draw)
	await idle(4)

	# 11 words: no jargon on screen
	var texts: Array = []
	texts_under(m, texts)
	var jw := []
	for t in texts:
		for j in JARGON:
			if String(t).to_lower().find(j) >= 0:
				jw.append(String(t))
	ok(jw.is_empty(), "11 no jargon on screen %s" % [jw])

	print("nedgechip: %d fail" % fails)
	quit(1 if fails > 0 else 0)
