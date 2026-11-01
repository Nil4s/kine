extends SceneTree
## godot --path . --position 4000,4000 -s tests/s155_test.gd     (Friday plan 155: Sculpt page "Make it a solid part": a sculpt becomes a solid of Easy Part; needs the CAD DLL with solid_from_mesh)
## Bars, from the BUILDING card (real clicks at 1280 x 720). Volumes are read from the kernel result; the mesh volume is summed by this test from the sculpt's own triangles.
##   1 BUTTON  "Make it a solid part" is on the Sculpt page, visible, on screen, nothing drawn over it
##   2 OPEN    a sculpt with a hole in its skin: plain words say it is not closed, no undo step, the part is unchanged
##   3 SOLID   a r 20 mm sculpted sphere (after a real stroke) becomes ONE body in Easy Part: volume within 2 pct of the mesh volume, ONE undo step
##   4 DRILL   Cut a hole (real click), made 5 mm across: the volume falls by pi*2.5^2*40 within 5 pct
##   5 UNDO    undoing the hole and then the conversion takes the part back to empty (0 bodies)
## Shots: C:/Temp/claude/s155/sculpt.png (the button), solid.png (the solid in Easy Part), drilled.png
const SHOT := "C:/Temp/claude/s155"
const DIRT := "user://s155_test"
var fails := 0
var m: Node
var pu: PartUI
var ep


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])




func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func tri_volume(km: KMesh) -> float:
	var v := 0.0
	for fc in km.faces:
		var f: PackedInt32Array = fc
		for k in range(1, f.size() - 1):
			v += km.verts[f[0]].dot(km.verts[f[k]].cross(km.verts[f[k + 1]])) / 6.0
	return absf(v) * 1e9   # mm3


func bodies() -> Dictionary:
	return Part.replay(m.S.part)


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
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	if not Part.available() or not Part.KCad.has_mesh_solid():
		print("FAIL: the CAD library with solid_from_mesh is not loaded")
		print("s155: 1 fail")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(8)
	ep = pu.ep
	var ub0: int = m.undo.size()

	# open the sculpt (a 20 mm sphere on the Sculpt page, the way Test sphere opens one) with a hole in its skin first
	var holed: KMesh = KMeshSculptUI.make_sphere(0.02, 12)
	holed.faces.remove_at(10)
	holed.rebuild()
	m.ksc = load("res://scripts/kmesh_sculpt_ui.gd").new()
	m.add_child(m.ksc)
	m.ksc.setup(m)
	m.easy.set_on(false)
	m.ksc.source = func(): return {"mesh": holed, "at": Transform3D(Basis(), Vector3(1.0, 0.02, 0.0))}
	m._sculpt_start()
	m.ksc.source = Callable()
	await idle(10)
	var bt: Button = null
	for b in m.ui_ribbon["SCULPT"].get_children():
		if b is Button and (b as Button).text == "Make it a solid part":
			bt = b
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	ok(bt != null and bt.is_visible_in_tree() and vp.encloses(Rect2(bt.global_position, bt.size)), "1 the button is on the Sculpt page and on the 1280 x 720 screen (%s)" % (str(bt.get_global_rect()) if bt != null else "missing"))
	await shot("sculpt")
	var ub1: int = m.undo.size()
	var feats0: int = (m.S.part.get("features", []) as Array).size()
	if bt != null:
		await click_ctl(bt)
	await idle(6)
	var said := String(m.ui_status.text) if m.ui_status != null else ""
	var feats1: int = (m.S.part.get("features", []) as Array).size()
	ok(m.undo.size() == ub1 and feats1 == feats0 and said.to_lower().find("not closed") >= 0 and m.ksc.on, "2 an open sculpt is refused in plain words, no undo step, part unchanged (%d steps, said: %s)" % [feats1, said])
	m.ksc.stop()
	await idle(6)

	# a closed sphere, one real stroke on it
	var km: KMesh = KMeshSculptUI.make_sphere(0.02, 12)
	m.ksc.source = func(): return {"mesh": km, "at": Transform3D(Basis(), Vector3(1.0, 0.02, 0.0))}
	m._sculpt_start()
	m.ksc.source = Callable()
	await idle(10)
	m.target = Vector3(1.0, 0.02, 0.0)
	m.dist = 0.12
	m._cam()
	await idle(20)
	var before := km.verts.duplicate()
	var mid: Vector2 = m.cam.unproject_position(Vector3(1.0, 0.02, 0.0))
	await drag_pts([mid + Vector2(-20.0, 0.0), mid, mid + Vector2(20.0, 0.0)])
	var moved := 0.0
	for i in before.size():
		moved = maxf(moved, km.verts[i].distance_to(before[i]) * 1000.0)
	var mesh_vol := tri_volume(km)
	print("     sculpt stroke moved up to %.2f mm; mesh volume %.1f mm3 (closed %s)" % [moved, mesh_vol, str(km.is_closed())])
	ub1 = m.undo.size()
	await click_ctl(bt)
	await idle(20)
	var r := bodies()
	var vol := float(r["volume"]) * 1e9
	ok(int(r["bodies"]) == 1 and absf(vol - mesh_vol) <= 0.02 * mesh_vol and m.undo.size() == ub1 + 1 and not m.ksc.on,
		"3 the sculpt is ONE solid: %d body, %.1f mm3 vs mesh %.1f (%.2f pct), undo %d -> %d, sculpt closed %s" % [int(r["bodies"]), vol, mesh_vol, 100.0 * absf(vol - mesh_vol) / mesh_vol, ub1, m.undo.size(), str(not m.ksc.on)])
	ok(pu.easy and ep.root.is_visible_in_tree() if "root" in ep else pu.easy, "3 Easy Part is open on it")
	var bb: AABB = r["aabb"]
	print("     solid box %.1f x %.1f x %.1f mm, status: %s" % [bb.size.x * 1000.0, bb.size.y * 1000.0, bb.size.z * 1000.0, String(m.ui_status.text)])
	m.target = Vector3(0.0, 0.02, 0.0)
	m.dist = 0.15
	m._cam()
	await idle(30)
	await shot("solid")

	# 4 DRILL: Cut a hole (real click), then 5 mm across
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var hb: Button = ep.hole_btns.get("through", null)
	var cuts := 0
	for f in m.S.part["features"]:
		if String(f.get("t", "")) == "extrude" and String(f.get("op", "")) == "cut":
			cuts += 1
	if cuts == 0 and hb != null:
		await click_ctl(hb)
		await idle(10)
	for f in m.S.part["features"]:
		if String(f.get("t", "")) == "sketch":
			for e in f["ents"]:
				if String(e.get("k", "")) == "circle":
					e["r"] = 2.5
	var r2 := bodies()
	var vol2 := float(r2["volume"]) * 1e9
	var want := PI * 2.5 * 2.5 * 40.0
	var got := vol - vol2
	ok(int(r2["bodies"]) == 1 and absf(got - want) <= 0.05 * want, "4 a 5 mm hole through the solid takes %.1f mm3 (want pi*2.5^2*40 = %.1f, %.1f pct off), %d body" % [got, want, 100.0 * absf(got - want) / want, int(r2["bodies"])])
	pu.sync()
	await idle(20)
	await shot("drilled")

	# 5 UNDO back
	var n := 0
	while m.undo.size() > ub0 and n < 8:
		m._undo()
		await idle(6)
		n += 1
	var r3 := bodies()
	ok(int(r3["bodies"]) == 0, "5 undoing the hole and the conversion empties the part again (%d undos, %d bodies)" % [n, int(r3["bodies"])])
	print("s155: %d fail" % fails)
	quit(1 if fails > 0 else 0)
