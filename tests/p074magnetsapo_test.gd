extends SceneTree
## p074magnetsapo (Friday plan 74, Kine's own): Magnet pocket. A round pocket cut for a round magnet on the top face of the solid, sized to the real magnet
## (6 mm across and 3 mm thick by default; the Magnet size slider moves it through the real sizes), 0.1 mm clearance each side, 0.2 mm deeper than
## the magnet. Lives under Cut a hole (the chip row), so a beginner walks: Crate -> Cut a hole -> Magnet. One undo step.
## godot --path . --position 4000,4000 -s tests/p074magnetsapo_test.gd     (needs a window and the CAD DLL; Docker box only)
## Bars, written before coding (real clicks through root.push_input at 1280 x 720; a 3D building project; Expert's Part, then its Easy button):
##   1 CHIP      the Cut a hole row has a Magnet chip with a plain word ("Magnet"), and no key name in the row's texts
##   2 POCKET    crate: Cut a hole, then Magnet: still ONE closed solid; the volume falls by 96.6 mm3 (a 6.2 mm round pocket, 3.2 mm deep) within 15 %
##   3 DEPTH     the pocket floor is 3.2 mm under the top face (measured on the built mesh within 0.1 mm); the crate's outside box is unchanged (0.01 mm)
##   4 WATERTIGHT the built mesh has no open edge
##   5 UNDO      one undo step takes the magnet away (volume back to the crate before the press, within 1e-9 m3); redo is not checked
## Shots in C:/Temp/claude/p074magnetsapo/ . Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p074magnetsapo"
const DIRT := "user://p074magnetsapo_test"
const MAGNET_POCKET_MM3 := 96.6   # pi * 3.1 ^ 2 * 3.2: a 6 mm x 3 mm magnet, 0.1 mm clearance each side, 0.2 mm deeper


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
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Button:
		out.append((n as Button).text)
	if n is Label:
		out.append((n as Label).text)
	if n is Control:
		out.append((n as Control).tooltip_text)
	for c in n.get_children():
		texts(c, out)


## [holes (an edge without its reverse), triangles] of a mesh, vertices welded at 0.01 mm
func watertight(msh: ArrayMesh) -> Array:
	var a := msh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var key := {}
	var wid := PackedInt32Array()
	wid.resize(v.size())
	for i in v.size():
		var k := Vector3i((v[i] * 100000.0).round())
		if not key.has(k):
			key[k] = key.size()
		wid[i] = key[k]
	var edges := {}
	for t in ix.size() / 3:
		var a0 := wid[ix[t * 3]]
		var a1 := wid[ix[t * 3 + 1]]
		var a2 := wid[ix[t * 3 + 2]]
		if a0 == a1 or a1 == a2 or a0 == a2:
			continue
		for e in [[a0, a1], [a1, a2], [a2, a0]]:
			var k2: int = e[0] * 1000003 + e[1]
			edges[k2] = int(edges.get(k2, 0)) + 1
	var bad := 0
	for k2 in edges:
		var u: int = k2 / 1000003
		var w: int = k2 % 1000003
		if edges[k2] != 1 or int(edges.get(w * 1000003 + u, 0)) != 1:
			bad += 1
	return [bad, ix.size() / 3]


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
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep

	# the walk: a crate from the Easy chips, then Cut a hole, then Magnet
	await click_ctl(ep.chips["crate"])
	await idle(3)
	var before_rec: Dictionary = m.S.part.duplicate(true)
	var v0 := float(Part.replay(before_rec)["volume"])
	var aabb0: AABB = Part.replay(before_rec)["aabb"]
	var n_undo: int = m.undo.size()
	await click_ctl(ep.make_btns["hole"])
	await idle(3)
	ok(ep.hole_box.visible and ep.hole_btns.has("magnet"), "1 CHIP: Cut a hole shows its chip row with a Magnet chip")
	var words := []
	texts(ep.hole_box, words)
	var bad_words := []
	for w in words:
		for bw in ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]:
			if String(w).to_lower().contains(bw):
				bad_words.append(String(w))
	ok(bad_words.is_empty() and ep.hole_btns.has("magnet") and String(ep.hole_btns["magnet"].text).to_lower().contains("magnet"), "1 CHIP: the row's words are plain (none of %s)" % str(bad_words))

	var v_hole := float(Part.replay(m.S.part)["volume"])
	var undo_hole: int = m.undo.size()
	await click_ctl(ep.hole_btns["magnet"])
	await idle(4)
	var rec: Dictionary = m.S.part
	var r := Part.replay(rec)
	var dv_mm3 := (v_hole - float(r["volume"])) * 1e9
	ok(int(r["bodies"]) == 1 and r["errors"].is_empty() and dv_mm3 > MAGNET_POCKET_MM3 * 0.85 and dv_mm3 < MAGNET_POCKET_MM3 * 1.15,
		"2 POCKET: one closed solid, failed steps %d, the volume falls by %.1f mm3 (want %.1f within 15 %%)" % [r["errors"].size(), dv_mm3, MAGNET_POCKET_MM3])

	# 3 DEPTH: measured on the built mesh; the pocket sits at the crate's centre on its top face
	var bb: AABB = r["aabb"]
	var top_mm := bb.end.z / Part.MM
	var cx := bb.get_center().x / Part.MM
	var cy := bb.get_center().y / Part.MM
	var floor_mm := INF
	var verts: PackedVector3Array = (r["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if r["mesh"] != null else PackedVector3Array()
	for v in verts:
		var q := v / Part.MM
		if Vector2(q.x - cx, q.y - cy).length() < 2.0:
			floor_mm = minf(floor_mm, q.z)
	var depth_mm := top_mm - floor_mm
	var same_box := bb.position.distance_to(aabb0.position) < 0.00001 and bb.end.distance_to(aabb0.end) < 0.00001
	ok(absf(depth_mm - 3.2) < 0.1 and same_box, "3 DEPTH: the pocket floor is %.2f mm under the top (want 3.2); the outside box %s" % [depth_mm, "unchanged" if same_box else "CHANGED"])

	# 4 WATERTIGHT
	var w: Array = watertight(r["mesh"]) if r["mesh"] != null else [-1, 0]
	ok(w[0] == 0 and w[1] > 0, "4 WATERTIGHT: %d open edges of %d triangles" % [w[0], w[1]])
	await shot("magnet_pocket")

	# 5 UNDO: the Undo button takes the magnet away: the volume is the hole step's again, one step
	var before_undo: int = m.undo.size()
	await click_ctl(ep.undo_btn)
	await idle(4)
	var v_back := float(Part.replay(m.S.part)["volume"])
	ok(absf(v_back - v_hole) < 1e-9 and m.undo.size() == before_undo - 1, "5 UNDO: one step back, the volume %.9f m3 (the hole step's %.9f)" % [v_back, v_hole])

	print("p074magnetsapo: %d fail" % fails)
	quit(1 if fails > 0 else 0)
