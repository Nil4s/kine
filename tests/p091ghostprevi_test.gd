extends SceneTree
## p091ghostprevi (Friday plan item 91: Ghost preview on hover, see the result before clicking). A beginner on the BUILDING card
## blank Easy Part, real mouse moves and clicks only. Hovering a shape chip of the "Start from" row (no press) shows a see-through
## ghost of the shape the chip would build, on the grid where the part sits. A click builds it (one undo step); the ghost is not
## shown for the shape that is already built. Measured from the ghost mesh and the built mesh (mm, counts), never from the code's own variables.
## Bars (written before the code: 1, 2, 4 and 6 FAIL on the old code, there is no ghost):
##   1 hovering the Sphere chip (no press) shows the ghost, visible and see-through (alpha under 1)
##   2 the ghost is the shape the click builds: its size is within 1 mm of the built part on each axis
##   3 hovering a chip does not change the record (the step count stays the same)
##   4 moving the pointer off the chip hides the ghost
##   5 hovering the Sphere chip after it is built shows no ghost (it is already the shape)
##   6 a real click on the Sphere chip builds it: built triangles above 0, one undo step
##   7 one Undo takes the sphere back: the template is gone and the step count is back to before the click
##   8 no jargon on the screen (kernel, mesh, manifold, replay, extrude, revolve)
## shots: C:/Temp/claude/p091ghostprevi/s1/hover.png (ghost up)
const SHOT := "C:/Temp/claude/p091ghostprevi/s1"
const DIRT := "user://p091ghostprevi_test"
const JARGON := ["kernel", "mesh", "manifold", "replay", "extrude", "revolve"]

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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
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


func ghost() -> MeshInstance3D:
	return m.find_child("easypart_tpl_ghost", true, false) as MeshInstance3D


func ghost_shown() -> bool:
	var g := ghost()
	return g != null and g.visible and g.mesh != null


## the size of a mesh in mm (its own box, no transform)
func size_mm(mesh: Mesh) -> Vector3:
	if mesh == null:
		return Vector3.ZERO
	return mesh.get_aabb().size * 1000.0


func feats() -> int:
	return (pu().ep._rec().get("features", []) as Array).size()


func chip(t: String) -> Button:
	return m.find_child("easypart_chip_" + t, true, false) as Button


func tris() -> int:
	var mesh: ArrayMesh = pu().part_mesh.mesh
	if mesh == null:
		return 0
	return mesh.get_faces().size() / 3


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

	var sph := chip("sphere")
	ok(sph != null and sph.is_visible_in_tree(), "setup: the Sphere chip is on the Start from row")
	if sph == null:
		print("p091ghostprevi: cannot continue")
		quit(1)
		return

	# 1 hover the Sphere chip, no press: the ghost shows
	var n0 := feats()
	var p := sph.get_global_rect().get_center()
	await ev_move(p)
	await ev_move(p + Vector2(1, 0))
	await idle(10)
	var g := ghost()
	var alpha := 1.0
	if g != null and g.material_override is StandardMaterial3D:
		alpha = (g.material_override as StandardMaterial3D).albedo_color.a
	ok(ghost_shown(), "1 hovering the Sphere chip shows the ghost (visible %s)" % ghost_shown())
	ok(ghost_shown() and alpha < 1.0, "1 the ghost is see-through (alpha %.2f)" % alpha)
	var gsize := size_mm(g.mesh) if g != null else Vector3.ZERO
	await shot("hover")

	# 3 the hover did not touch the record
	ok(feats() == n0, "3 hovering does not change the record (steps %d, was %d)" % [feats(), n0])

	# 4 the pointer leaves the chip: the ghost goes
	await ev_move(Vector2(4, 4))
	await idle(10)
	ok(not ghost_shown(), "4 moving off the chip hides the ghost")

	# 2 and 6: hover again, then a real click builds the sphere
	await ev_move(p)
	await idle(10)
	await click_ctl(sph)
	await idle(60)
	var bmesh := (pu().part_mesh as MeshInstance3D).mesh as ArrayMesh
	var bsize := bmesh.get_aabb().size * 1000.0 if bmesh != null else Vector3.ZERO
	var near := absf(gsize.x - bsize.x) <= 1.0 and absf(gsize.y - bsize.y) <= 1.0 and absf(gsize.z - bsize.z) <= 1.0
	ok(near, "2 the ghost matches the built sphere (ghost %.1f x %.1f x %.1f, built %.1f x %.1f x %.1f mm)" % [gsize.x, gsize.y, gsize.z, bsize.x, bsize.y, bsize.z])
	ok(tris() > 0 and feats() > n0, "6 a real click builds the sphere (triangles %d, steps %d)" % [tris(), feats()])

	# 5 the sphere is built: hovering its chip shows no ghost
	await ev_move(Vector2(4, 4))
	await idle(5)
	await ev_move(sph.get_global_rect().get_center())
	await idle(10)
	ok(not ghost_shown(), "5 hovering the Sphere chip after it is built shows no ghost")

	# 7 one Undo takes the sphere back
	var n1 := feats()
	await click_ctl(pu().ep.undo_btn)
	await idle(60)
	ok(feats() == n0 and feats() < n1, "7 one Undo takes the sphere back (steps %d, was %d)" % [feats(), n0])

	# 8 no jargon on screen
	var words: Array = []
	texts_under(m.ui_root, words)
	var bad := ""
	for w in words:
		for j in JARGON:
			if String(w).to_lower().find(j) >= 0:
				bad = String(w)
	ok(bad == "", "8 no jargon on screen (%s)" % (bad if bad != "" else "clean"))

	print("p091ghostprevi: %d failing" % fails)
	quit(1 if fails > 0 else 0)
