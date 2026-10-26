## godot --path . -s tests/uvshade_test.gd     (ROADMAP_400 D05; needs a window: real key events, pixels read back)
## "Model: edit a test cube (preview)", camera on the cube's front axis 2.4 m away, UI hidden for the shots. Bars:
##   1 U (a real key event) on a mesh without UVs unwraps it (seams by angle: 48 seam edges, 6 islands) and shows the
##     checker: the shading is "uv_checker", and along a horizontal line across the front face the pixel luminance
##     changes from light to dark and back at least 4 times (the cells of the checker; plain shading: 0 times, wire lines
##     aside, sampled between them)
##   2 U again: "uv_stretch". The cube's LSCM unwrap has no stretch, so the front face centre pixel is blue (b > r + 0.2,
##     b > g); moving one front vertex 0.3 m out turns the faces around it green to red (the centre pixel of one of them:
##     g > b or r > b) and the worst face's angle distortion is over 1.5
##   3 PLACEMENT: the view still sits at the stage position (1.0, 0.3, 0) within 1 mm, its centre pixel differs from the
##     same pixel with the cube hidden; U a third time is plain shading again (the stage colour of the cube)
##   shot -> /tmp/claude-0/sp/uvshade_checker.png and uvshade_stretch.png when that folder exists
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshEditUI


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	await process_frame
	e = InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = false
	root.push_input(e)
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func scr(wp: Vector3) -> Vector2:
	return m.cam.unproject_position(wp)


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


## light / dark switches along y = row across the front face (x from -0.28 to 0.28 m), sampled at 4 points per cell
## away from the wire (cells are 0.15 m; checker cells are smaller)
func switches(img: Image, wc: Vector3) -> int:
	var n := 0
	var prev := -1
	for k in 113:
		var x := -0.28 + 0.56 * k / 112.0
		var p := scr(wc + Vector3(x, 0.04, 0.3))
		var l := img.get_pixel(int(p.x), int(p.y)).get_luminance()
		var s := 1 if l > 0.45 else (0 if l < 0.3 else prev)
		if prev != -1 and s != prev:
			n += 1
		prev = s
	return n


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)
	await idle(4)
	m.ui_root.visible = false
	var plain := await shot()
	var sw0 := switches(plain, wc)

	# ---- 1
	m.ui_root.visible = true
	await key(KEY_U)
	var nseam := 0
	for v in ui.mesh.attr_data(KMeshUV.SEAM):
		nseam += 1 if v > 0.5 else 0
	var top := KMeshUV.topology(ui.mesh)
	m.ui_root.visible = false
	var chk := await shot()
	var sw1 := switches(chk, wc)
	ok(ui.view.shading == "uv_checker" and ui.mesh.has_attr(KMeshUV.UV) and nseam == 48 and top["islands"] == 6,
		"1: U unwraps (%d seam edges, %d islands) and shows the checker (shading '%s')" % [nseam, top["islands"], ui.view.shading])
	ok(sw1 >= 4 and sw0 == 0, "1: light / dark switches across the front face: %d with the checker (bar >= 4), %d plain (bar 0)" % [sw1, sw0])
	if DirAccess.dir_exists_absolute("/tmp/claude-0/sp"):
		chk.save_png("/tmp/claude-0/sp/uvshade_checker.png")

	# ---- 2
	m.ui_root.visible = true
	await key(KEY_U)
	m.ui_root.visible = false
	var st := await shot()
	var pc := scr(wc + Vector3(0.075, 0.075, 0.3))
	var cc := st.get_pixel(int(pc.x), int(pc.y))
	ok(ui.view.shading == "uv_stretch" and cc.b > cc.r + 0.2 and cc.b > cc.g, "2: U again is the stretch map; the unstretched front face is blue: %s" % cc.to_html(false))
	# pull the front-face vertex at (0, 0, 0.3) (local) out by 0.3 m: its four faces stretch
	var vi := -1
	for v in ui.mesh.vert_count():
		if ui.mesh.verts[v].distance_to(Vector3(0, 0, 0.3)) < 1e-5:
			vi = v
	ui.mesh.verts[vi] += Vector3(0, 0, 0.3)
	ui.mesh.rebuild()
	ui.view.mark_dirty()
	var st2 := await shot()
	var fq := -1
	for f in ui.mesh.vert_faces(vi):
		var fcn := ui.mesh.face_center(f)
		if fcn.x > 0.0 and fcn.y > 0.0:
			fq = f
	var pw := scr(ui.view.global_transform * ui.mesh.face_center(fq))
	var cw := st2.get_pixel(int(pw.x), int(pw.y))
	var worst: float = ui.view.stretch.get("angle_max", 0.0)
	ok((cw.g > cw.b or cw.r > cw.b) and worst > 1.5, "2: a vertex pulled out 0.3 m warms the face beside it: %s (worst face angle distortion %.2f)" % [cw.to_html(false), worst])
	if DirAccess.dir_exists_absolute("/tmp/claude-0/sp"):
		st2.save_png("/tmp/claude-0/sp/uvshade_stretch.png")
	ui.mesh.verts[vi] -= Vector3(0, 0, 0.3)
	ui.mesh.rebuild()
	ui.view.mark_dirty()

	# ---- 3
	var wpos: Vector3 = ui.view.global_position
	ok(wpos.distance_to(m.stage_root.global_transform * Vector3(1.0, 0.3, 0.0)) < 1e-3, "3: the view is at the stage position (got %s)" % wpos)
	var with := await shot()
	ui.view.visible = false
	var without := await shot()
	ui.view.visible = true
	var cp := scr(wpos)
	var a := with.get_pixel(int(cp.x), int(cp.y))
	var b := without.get_pixel(int(cp.x), int(cp.y))
	ok(dist(a, b) > 0.05, "3: the centre pixel %s with the cube, %s without" % [a.to_html(false), b.to_html(false)])
	m.ui_root.visible = true
	await key(KEY_U)
	m.ui_root.visible = false
	var back := await shot()
	var pl := plain.get_pixel(int(pc.x), int(pc.y))
	var bk := back.get_pixel(int(pc.x), int(pc.y))
	ok(ui.view.shading == "" and dist(pl, bk) < 0.05, "3: U a third time is plain again: %s (plain %s)" % [bk.to_html(false), pl.to_html(false)])
	m.ui_root.visible = true

	print("RESULT: ", "FAIL (%d)" % fails if fails > 0 else "PASS")
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
