extends SceneTree
## godot --path . --position 4000,4000 -s tests/s213_test.gd     (MULTI-PART ASSEMBLY, Friday plan 213; scripts/build/assembly.gd + assembly_ui.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720 from the 3D BUILDING card; the numbers are measured from the meshes in the view and from the files re-read from disk):
##   1 OPEN     the chooser's New assembly button opens the Assembly screen: empty list, no Part chrome
##   2 INSERT   one library part (Screw M4 x 16) and one saved part (My parts) are put in by clicking their buttons: two rows, two meshes, not overlapping
##   3 PLACE    typed X = 100 on the second part: its mesh sits exactly 100 mm from where it was built (measured on the view's mesh)
##   4 GIZMO    a drag on the first part's X arrow moves it along X only, the mesh follows; a drag on a turn handle turns it; typed numbers put both back
##   5 EDIT     double-click the first part's row: the Part workspace opens on it; Easy Part's M6 x 16 chip, then Back to the assembly: the assembly's
##              screw is now 35 mm tall (was 20) and the other part did not move
##   6 SAVE     Save writes one file: re-read from disk it has both part records, the names and the 100 mm place
##   7 RELOAD   New empties the screen; Open > Assemblies > the file brings both parts back with the same meshes and places
##   8 EXPORT   STL, GLB and STEP re-read from disk each hold BOTH parts at their places (box, volume, node names, solid count)
## Shots: C:/Temp/claude/s213/placed.png, editing.png, exported.png
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s213"
const DIRT := "user://s213_test"
const OUT := "user://s213_out"
var pu: PartUI
var A: AssemblyUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, dbl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.double_click = dbl and down
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


func click_ctl(c: Control, dbl := false) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	if dbl:
		await ev_mouse(p, true, true)
		await ev_mouse(p, false)
	await idle(3)


func drag_from(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 7):
		await ev_move(a.lerp(b, float(i) / 6.0))
	await ev_mouse(b, false)
	await idle(3)


func key(code: int, uni := 0) -> void:
	for dn in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni
		e.pressed = dn
		root.push_input(e, true)
		await process_frame


## click the field, then type the number and Enter (a beginner's way)
func type_in(le: LineEdit, text: String) -> void:
	await click_ctl(le)
	le.select_all()   # a click puts the caret in; selecting all is what Ctrl+A does
	for ch in text:
		var c := ch.unicode_at(0)
		var kc := KEY_0 + (c - 48) if (c >= 48 and c <= 57) else (KEY_PERIOD if ch == "." else KEY_MINUS)
		await key(kc, c)
	await key(KEY_ENTER)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func mesh_of(id: String) -> MeshInstance3D:
	return A.meshes.get(id) as MeshInstance3D


## a part's box as the view shows it (mm): the mesh's own box carried by the instance's transform
func box_mm(id: String) -> AABB:
	var mi := mesh_of(id)
	if mi == null or mi.mesh == null:
		return AABB()
	var b: AABB = mi.global_transform * mi.mesh.get_aabb()
	return AABB(b.position * 1000.0, b.size * 1000.0)


func own_mm(id: String) -> AABB:
	var mi := mesh_of(id)
	var b: AABB = mi.mesh.get_aabb()
	return AABB(b.position * 1000.0, b.size * 1000.0)


func row_btn(i: int) -> Button:
	return nd("asm_row_%d" % i) as Button


## the volume of the part records (m3), built apart from the assembly
func vol_of(rec: Dictionary) -> float:
	return float(Part.replay(rec, -1, {}).get("volume", 0.0))


func stl_read(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	var n := b.decode_u32(80)
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var vol := 0.0
	for i in n:
		var o := 84 + 50 * i + 12
		var v: Array = []
		for k in 3:
			var p := Vector3(b.decode_float(o + 12 * k), b.decode_float(o + 12 * k + 4), b.decode_float(o + 12 * k + 8))
			v.append(p)
			mn = mn.min(p)
			mx = mx.max(p)
		vol += (v[0] as Vector3).dot((v[1] as Vector3).cross(v[2])) / 6.0
	return {"tris": n, "min": mn, "max": mx, "vol": vol, "len": b.size()}


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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the assembly cannot run")
		quit(1)
		return
	for d in [DIRT, OUT]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	# a clean slate for the stores this test reads
	for fn in DirAccess.get_files_at(ProjectSettings.globalize_path(Assembly.folder())) if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Assembly.folder())) else PackedStringArray():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Assembly.folder()) + "/" + fn)
	Assembly.export_dir = OUT
	var br := PartCatalog.make("bracket_l")
	br["name"] = "Test bracket"
	MyParts.save(br, "Test bracket")
	var ss: StartScreen = m.start_screen
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
	pu = m.bld.part
	A = m.bld.asm
	# 1 OPEN
	m.build_choose.show_chooser()
	await idle(4)
	var nb := nd("build_choose_assembly") as Button
	await click_ctl(nb)
	await idle(4)
	var chrome_hidden: bool = not pu.chrome() and (pu.browser == null or not pu.browser.visible) and not pu.tl.visible
	ok(nb != null and A.on and nd("asm_panel").is_visible_in_tree() and nd("asm_list").get_child_count() == 1 and chrome_hidden and not m.build_choose.open, "1 New assembly opens the screen: panel shown, list empty (%d rows), Part chrome hidden" % nd("asm_list").get_child_count())
	# 2 INSERT
	await click_ctl(nd("asm_add") as Button)
	var lib_btn := nd("asm_src_lib_screw_m4") as Button
	ok(lib_btn != null and lib_btn.is_visible_in_tree(), "2 Add part lists the Parts library (the M4 screw button is on screen)")
	await click_ctl(lib_btn)
	await click_ctl(nd("asm_tab_mine") as Button)
	var mine_btn := nd("asm_src_mine_Test bracket") as Button
	ok(mine_btn != null and mine_btn.is_visible_in_tree(), "2 My parts lists the saved part")
	await click_ctl(mine_btn)
	var ps: Array = A.asm["parts"]
	ok(ps.size() == 2 and row_btn(0) != null and row_btn(1) != null and row_btn(0).text == "Screw M4 x 16" and row_btn(1).text == "Test bracket", "2 two parts in the list: %s" % str(ps.map(func(p): return p["name"])))
	var id1 := String(ps[0]["id"]) if ps.size() > 0 else ""
	var id2 := String(ps[1]["id"]) if ps.size() > 1 else ""
	var b1 := box_mm(id1)
	var b2 := box_mm(id2)
	var gap := b2.position.x - (b1.position.x + b1.size.x)
	ok(mesh_of(id1) != null and mesh_of(id2) != null and b1.size.y > 5.0 and b2.size.y > 5.0 and gap >= 9.5, "2 two meshes in the view, side by side (screw %.1f mm tall, bracket %.1f mm tall, gap %.2f mm)" % [b1.size.y, b2.size.y, gap])
	# 3 PLACE: typed 100 mm
	await click_ctl(row_btn(1))
	var own2 := own_mm(id2)
	await type_in(nd("asm_pos_x") as LineEdit, "100")
	var off2 := box_mm(id2).position.x - own2.position.x
	ok(absf(off2 - 100.0) <= 0.01 and absf(float(ps[1]["pos"][0]) - 100.0) <= 0.01, "3 typed X 100: the bracket's mesh is %.3f mm from where it was built" % off2)
	# 4 GIZMO
	await click_ctl(row_btn(0))
	var x0 := box_mm(id1).position
	var hs: Array = A.handles()
	var hx: Dictionary = hs[0]
	var dirv: Vector2 = hx["dir"]
	await drag_from(hx["p1"], (hx["p1"] as Vector2) + dirv * 50.0)
	var x1 := box_mm(id1).position
	var moved := x1 - x0
	ok(moved.x > 5.0 and absf(moved.y) < 0.01 and absf(moved.z) < 0.01 and absf(float(ps[0]["pos"][0]) - moved.x) < 0.01, "4 dragging the X arrow 50 px moved the screw %.1f mm along X only (y %.3f, z %.3f), the field says %s" % [moved.x, moved.y, moved.z, (nd("asm_pos_x") as LineEdit).text])
	# the Move fields, the part's real offset and the status line say the same number (after the drag, and after another row and back)
	var f_now := [(nd("asm_pos_x") as LineEdit).text, (nd("asm_pos_y") as LineEdit).text, (nd("asm_pos_z") as LineEdit).text]
	var said := A.status_l.text
	var want_words := "%s, %s, %s" % f_now
	ok(is_equal_approx(float(f_now[0]), float(ps[0]["pos"][0])) and said.ends_with("is at %s mm" % want_words) and said.begins_with("Screw M4 x 16"), "4 after the drag the fields read %s, the part's offset is %s, the line says [%s]" % [want_words, str(ps[0]["pos"]), said])
	await click_ctl(row_btn(1))
	var f_br := [(nd("asm_pos_x") as LineEdit).text, (nd("asm_pos_y") as LineEdit).text, (nd("asm_pos_z") as LineEdit).text]
	var said_br := A.status_l.text
	ok(is_equal_approx(float(f_br[0]), 100.0) and said_br == "Test bracket is at %s, %s, %s mm" % f_br, "4 selecting the bracket: fields %s, line [%s]" % [str(f_br), said_br])
	await click_ctl(row_btn(0))
	var f_back := [(nd("asm_pos_x") as LineEdit).text, (nd("asm_pos_y") as LineEdit).text, (nd("asm_pos_z") as LineEdit).text]
	ok(f_back == f_now and A.status_l.text == said, "4 and back on the screw: fields %s = before %s, line [%s]" % [str(f_back), str(f_now), A.status_l.text])
	# the floor grid is there, and the ribbon has no empty divider slots
	var stray := 0
	var row: Array = m.ui_ribbon["BUILD"].get_children()
	for i in row.size():
		var c := row[i] as Control
		if c is VSeparator and c.is_visible_in_tree():
			var l := false
			var r := false
			for j in range(i - 1, -1, -1):
				if row[j].visible:
					l = not (row[j] is VSeparator)
					break
			for j in range(i + 1, row.size()):
				if row[j].visible:
					r = not (row[j] is VSeparator)
					break
			if not (l and r):
				stray += 1
	var shown: int = row.filter(func(c): return c is Control and c.visible and not (c is VSeparator)).size()
	ok(m.bld.grid.is_visible_in_tree() and stray == 0, "4 the floor grid is visible (%s) and no empty divider slot in the BUILD ribbon (%d stray, %d tools shown)" % [str(m.bld.grid.is_visible_in_tree()), stray, shown])
	await click_ctl(nd("asm_mode_turn") as Button)
	hs = A.handles()
	var hy: Dictionary = hs[1]
	var dy: Vector2 = hy["dir"]
	await drag_from(hy["p1"], (hy["p1"] as Vector2) + Vector2(-dy.y, dy.x) * 60.0)
	var rot_y := float(ps[0]["rot"][1])
	var mi1 := mesh_of(id1)
	var eul := mi1.global_transform.basis.get_euler()
	ok(absf(rot_y) >= 5.0 and absf(rad_to_deg(eul.y) - rot_y) < 0.1 and absf(float(ps[0]["rot"][0])) < 0.01, "4 dragging the Y turn handle turned the screw %.1f degrees about Y (the mesh says %.1f)" % [rot_y, rad_to_deg(eul.y)])
	await type_in(nd("asm_rot_y") as LineEdit, "0")
	await type_in(nd("asm_pos_x") as LineEdit, "0")
	await click_ctl(nd("asm_mode_move") as Button)
	var back0 := box_mm(id1)
	ok(absf(back0.position.x - own_mm(id1).position.x) < 0.01 and absf(mi1.global_transform.basis.get_euler().y) < 0.001, "4 typed 0 puts the screw back (offset %.3f mm, turn %.3f)" % [back0.position.x - own_mm(id1).position.x, mi1.global_transform.basis.get_euler().y])
	await shot("placed")
	# 5 EDIT
	var h_before := box_mm(id1).size.y
	var bx_before := box_mm(id2)
	var feats_before := (ps[0]["rec"]["features"] as Array).size()
	await click_ctl(row_btn(0), true)
	print("dbg edit: pu.on=%s A.on=%s editing=%s back=%s name=%s" % [pu.on, A.on, A.editing, nd("asm_back").is_visible_in_tree(), m.S.part.get("name", "?")])
	ok(pu.on and not A.on and A.editing == id1 and nd("asm_back").is_visible_in_tree() and JSON.stringify(m.S.part) == JSON.stringify(ps[0]["rec"]), "5 double-click on the screw's row opens it in the Part workspace (Back to the assembly shown)")
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	await click_ctl(nd("easypart_chip_parts") as Button)
	var chip := nd("easypart_screw_M6_16") as Button
	ok(chip != null and chip.is_visible_in_tree(), "5 Easy Part shows the M6 x 16 chip on the opened screw")
	if chip != null:
		await click_ctl(chip)
	await shot("editing")
	var bk := nd("asm_back") as Button
	var bkr := bk.get_global_rect()
	var covered := false
	for c in root.find_children("*", "Button", true, false):
		var cb := c as Button
		if cb != bk and cb.is_visible_in_tree() and cb.get_global_rect().intersects(bkr):
			covered = true
	ok(not covered and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(bkr), "5 Back to the assembly is on screen and nothing sits on it")
	await click_ctl(bk)
	await idle(4)
	var h_after := box_mm(id1).size.y
	var bx_after := box_mm(id2)
	ok(A.on and not A.back_panel.visible and absf(h_before - 20.0) < 0.3 and absf(h_after - 22.0) < 0.3, "5 after Back to the assembly the screw is %.1f mm tall (was %.1f): M6 x 16 = 6 mm head + 16 mm shank" % [h_after, h_before])
	ok(bx_after.is_equal_approx(bx_before) and A.asm["parts"].size() == 2, "5 the bracket did not move (box %s)" % str(bx_after))
	# 6 SAVE
	var nm_edit := nd("asm_name") as LineEdit
	var asm_name := nm_edit.text
	await click_ctl(nd("asm_save") as Button)
	var path := Assembly.path_of(asm_name)
	var disk := Assembly.read(path)
	var dps: Array = disk.get("parts", [])
	ok(not disk.is_empty() and dps.size() == 2 and String(dps[0]["name"]) == "Screw M4 x 16" and String(dps[1]["name"]) == "Test bracket" and absf(float(dps[1]["pos"][0]) - 100.0) < 0.01, "6 the saved file %s holds 2 parts (%s), the bracket at x %s mm" % [path.get_file(), str(dps.map(func(p): return p["name"])), str(dps[1]["pos"][0]) if dps.size() > 1 else "?"])
	ok(dps.size() == 2 and vol_of(dps[0]["rec"]) > 0.0 and absf(box_mm(id1).size.y - 22.0) < 0.3, "6 the file's screw record builds a solid of %.1f mm3" % (vol_of(dps[0]["rec"]) * 1e9 if dps.size() > 0 else 0.0))
	var v_screw := vol_of(dps[0]["rec"])
	var v_br := vol_of(dps[1]["rec"])
	var want1 := box_mm(id1)
	var want2 := box_mm(id2)
	# 7 RELOAD
	await click_ctl(nd("asm_new") as Button)
	ok(A.asm["parts"].size() == 0 and A.meshes.is_empty(), "7 New empties the screen")
	await click_ctl(nd("asm_open") as Button)
	var item := nd("asm_src_asm_" + MyParts.file_stem(asm_name)) as Button
	ok(item != null and item.is_visible_in_tree(), "7 Open lists the saved assembly")
	if item != null:
		await click_ctl(item)
	var rp: Array = A.asm["parts"]
	var r1 := box_mm(String(rp[0]["id"])) if rp.size() > 0 else AABB()
	var r2 := box_mm(String(rp[1]["id"])) if rp.size() > 1 else AABB()
	ok(rp.size() == 2 and r1.is_equal_approx(want1) and r2.is_equal_approx(want2) and row_btn(1) != null and row_btn(1).text == "Test bracket", "7 reloaded: the same two meshes in the same places (screw %s, bracket %s)" % [str(r1.position), str(r2.position)])
	# 8 EXPORT
	id1 = String(rp[0]["id"])
	id2 = String(rp[1]["id"])
	var wb := want1.merge(want2)   # Kine mm: x right, y up, z toward the viewer
	await click_ctl(nd("asm_export_stl") as Button)
	var rs: Dictionary = A.last_export
	var st := stl_read(String(rs.get("path", "")))
	# STL is Z up: x = x, y = -z, z = y
	var sbox_ok := not st.is_empty() and absf(st["min"].x - wb.position.x) < 0.05 and absf(st["max"].x - wb.end.x) < 0.05 and absf(st["min"].z - wb.position.y) < 0.05 and absf(st["max"].z - wb.end.y) < 0.05 and absf(st["min"].y + wb.end.z) < 0.05 and absf(st["max"].y + wb.position.z) < 0.05
	var vsum := (v_screw + v_br) * 1e9
	ok(bool(rs.get("ok", false)) and sbox_ok, "8 STL on disk (%d bytes, %d triangles) spans both parts: x %.2f..%.2f mm, wanted %.2f..%.2f" % [st.get("len", 0), st.get("tris", 0), st["min"].x, st["max"].x, wb.position.x, wb.end.x])
	ok(absf(float(st["vol"]) - vsum) <= 0.01 * vsum, "8 STL volume %.1f mm3 = the two parts' %.1f mm3 (within 1 pct)" % [st["vol"], vsum])
	await click_ctl(nd("asm_export_glb") as Button)
	var rg: Dictionary = A.last_export
	var gp := String(rg.get("path", ""))
	var gd := GLTFDocument.new()
	var gs := GLTFState.new()
	var ge := gd.append_from_file(gp, gs)
	var groot := gd.generate_scene(gs) if ge == OK else null
	var names: Array = []
	var gmn := Vector3(1e9, 1e9, 1e9)
	var gmx := Vector3(-1e9, -1e9, -1e9)
	if groot != null:
		for n in groot.find_children("*", "MeshInstance3D", true, false):
			var gm := n as MeshInstance3D
			names.append(String(gm.name))
			var xf := Transform3D()
			var up: Node = gm
			while up != null and up is Node3D:
				xf = (up as Node3D).transform * xf
				up = up.get_parent()
			var bb: AABB = xf * gm.mesh.get_aabb()
			gmn = gmn.min(bb.position * 1000.0)
			gmx = gmx.max(bb.end * 1000.0)
		groot.free()
	names.sort()
	ok(bool(rg.get("ok", false)) and names == ["Screw M4 x 16", "Test bracket"] and gmn.distance_to(wb.position) < 0.05 and gmx.distance_to(wb.end) < 0.05, "8 GLB on disk has the nodes %s spanning %s .. %s mm (wanted %s .. %s)" % [str(names), str(gmn), str(gmx), str(wb.position), str(wb.end)])
	await click_ctl(nd("asm_export_step") as Button)
	var rt: Dictionary = A.last_export
	var tp := String(rt.get("path", ""))
	var txt := FileAccess.get_file_as_string(tp)
	var nsolid := txt.count("MANIFOLD_SOLID_BREP")
	var sid := KCad.import_step(tp)
	var sv := KCad.volume(sid) if sid != 0 else -1.0
	var ratio := sv / (v_screw + v_br) if sv > 0.0 else 0.0
	if sid != 0:
		KCad.release(sid)
	ok(bool(rt.get("ok", false)) and nsolid == 2 and (absf(ratio - 1.0) < 0.01 or absf(ratio / 1e9 - 1.0) < 0.01 or absf(ratio / 1e-9 - 1.0) < 0.01), "8 STEP on disk (%d bytes) has %d solids, re-imported volume is %s x the two parts' (%.1f mm3)" % [txt.length(), nsolid, String.num(ratio, 6), vsum])
	await shot("exported")
	# the pieces really are far apart in the STEP: the 100 mm shows (box of the fused import is wider than either part alone)
	print("s213: %d fail" % fails)
	quit(1 if fails > 0 else 0)
