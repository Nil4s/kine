## godot --path . -s tests/pbrmat_test.gd     (ROADMAP_400 E01; needs a window: frames are read back from the screen)
## PBR materials on the model preview's test cube (98 verts, 96 faces): a slot list on the mesh (KMesh.materials), a face
## attribute "mat" for the slot of each face, one view surface per slot (scripts/kmesh_material.gd), the Materials panel
## (scripts/kmesh_material_ui.gd). Bars, stated before measuring:
##   1 ASSIGN: two slots added through the panel; the faces whose centre has x < 0 (local) assigned to slot 0, x > 0 to
##     slot 1: the slot counts are exactly [48, 48]
##   2 SURFACES: the view's surface mesh has exactly 2 surfaces, 96 triangles each (48 quads), named after the slots, each
##     with a StandardMaterial3D whose albedo / metallic / roughness are the slot's; a slot with every field set builds a
##     material with normal_enabled + normal_texture, ao_enabled + ao_texture + ao_light_affect, emission_enabled +
##     emission + energy, subsurf_scatter_enabled + strength + texture, and a metallic / roughness / albedo map
##   3 ROUND TRIP: every field of a slot set to non-round values and all 7 maps pointed at files; save -> load gives the
##     slot list back EQUAL (==, every float, colour and path) and the "mat" channel equal; a damaged materials block is an
##     error with a next step (load returns null)
##   4 PIXELS (UI hidden, front view): the centre pixel of a front cell of the red-rough slot has r > 2 g and r > 2 b and
##     r > 0.15; the same pixel with the cube hidden differs (the instrument can move); a cell of slot 1 changes by a colour
##     distance > 0.05 when slot 1 goes from metallic 0 to 1 (same light, same camera) while the red cell stays within 0.02
##   5 UNDO: assigning 8 selected faces to slot 1 is ONE step; Ctrl+Z (a real key) restores the "mat" channel exactly, redo
##     puts the assignment back; a slider drag (drag_started, 5 values, drag_ended on the panel's own slider) is ONE step
##     and its undo puts the roughness back exactly; Select gives the faces of a slot (count = its count)
##   6 E15: from_photo points albedo / roughness / normal maps at user://materials/<name>/{albedo,rough,normal}.png
##   7 PLACEMENT: with the UI shown the panel is visible, wholly inside the window and inside the clear view rect (or docked
##     in the right column, wholly right of it: Nick 2026-10-24), and its
##     rect does not overlap the Add primitive panel's rect (nor the heat legend's when it is on); the S search box
##     (opened over the view) draws on top of it
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshEditUI
var pan: KMeshMaterialPanel
const DIR := "user://pbrmat_test"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func key(k: int, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		root.push_input(e)
		await process_frame
	await idle(2)


## a real left click in the middle of a button, the way a mouse presses it
func press_button(b: Button) -> void:
	var c: Vector2 = b.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = c
		e.global_position = c
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(3)


func fc(fi: int) -> Vector2:
	return m.cam.unproject_position(ui.view.global_transform * ui.mesh.face_center(fi))


func front_faces() -> Array:
	var out := []
	for fi in ui.mesh.face_count():
		var wc: Vector3 = ui.view.global_transform * ui.mesh.face_center(fi)
		if ui.mesh.face_normals[fi].dot(m.cam.global_position - wc) > 1e-6 and ui.mesh.face_normals[fi].z > 0.9:
			out.append(fi)
	return out


func png(path: String, c: Color) -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.fill(c)
	img.save_png(path)


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
	pan = ui.mat_panel
	var mesh: KMesh = ui.mesh
	ok(ui.on and mesh.face_count() == 96 and pan != null and pan.visible, "the cube is open (%d faces) and the Materials panel shows" % mesh.face_count())

	# 1 ASSIGN
	var s0 := pan.add_slot({"name": "Red rough", "albedo": Color(0.8, 0.05, 0.05), "roughness": 1.0, "metallic": 0.0})
	var s1 := pan.add_slot({"name": "Grey", "albedo": Color(0.7, 0.7, 0.7), "roughness": 0.35, "metallic": 0.0})
	var left := []
	var right := []
	for fi in mesh.face_count():
		(left if mesh.face_center(fi).x < 0.0 else right).append(fi)
	KMeshMaterial.assign(mesh, left, s0)
	KMeshMaterial.assign(mesh, right, s1)
	ui.view.mark_dirty()
	await idle(3)
	var cnt := KMeshMaterial.counts(mesh)
	ok(s0 == 0 and s1 == 1 and cnt == PackedInt32Array([48, 48]), "1 two slots (%d, %d), halves assigned: counts %s (bar [48, 48])" % [s0, s1, cnt])

	# 2 SURFACES
	var sm: Mesh = (ui.view.get_node("surf") as MeshInstance3D).mesh
	var tris := []
	var mats_ok := true
	for i in sm.get_surface_count():
		tris.append((sm.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		var mt := sm.surface_get_material(i) as StandardMaterial3D
		var sl: Dictionary = mesh.materials[i]
		mats_ok = mats_ok and mt != null and mt.albedo_color.is_equal_approx(sl["albedo"]) and is_equal_approx(mt.metallic, sl["metallic"]) and is_equal_approx(mt.roughness, sl["roughness"]) and (sm as ArrayMesh).surface_get_name(i) == sl["name"]
	ok(sm.get_surface_count() == 2 and tris == [96, 96], "2a the view has %d surfaces with %s triangles (bar 2 x 96 = 48 quads each)" % [sm.get_surface_count(), tris])
	ok(mats_ok and (ui.view.get_node("surf") as MeshInstance3D).material_override == null, "2b each surface wears its slot's StandardMaterial3D (albedo, metallic, roughness, name); no override on top")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var maps := {}
	for k in KMeshMaterial.TEX_KEYS:
		maps[k] = "%s/%s.png" % [DIR, k]
		png(maps[k], Color(0.5, 0.5, 1.0) if k == "normal_tex" else Color(0.6, 0.6, 0.6))
	var full := KMeshMaterial.clean(maps.merged({"name": "Full", "albedo": Color(0.31, 0.47, 0.73, 1.0), "metallic": 0.37, "roughness": 0.61,
		"normal_scale": 1.33, "ao": 0.42, "emission": Color(0.9, 0.2, 0.1, 1.0), "emission_energy": 2.7, "sss": 0.55}))
	var fm := KMeshMaterial.material(full)
	ok(fm.normal_enabled and fm.normal_texture != null and is_equal_approx(fm.normal_scale, 1.33) and fm.ao_enabled and fm.ao_texture != null and is_equal_approx(fm.ao_light_affect, 0.42)
		and fm.emission_enabled and fm.emission.is_equal_approx(Color(0.9, 0.2, 0.1)) and is_equal_approx(fm.emission_energy_multiplier, 2.7)
		and fm.subsurf_scatter_enabled and is_equal_approx(fm.subsurf_scatter_strength, 0.55) and fm.subsurf_scatter_texture != null
		and fm.metallic_texture != null and fm.roughness_texture != null and fm.albedo_texture != null and is_equal_approx(fm.metallic, 0.37),
		"2c every field reaches StandardMaterial3D: normal map + scale, AO map + light affect, emission + energy, SSS strength + map, metal / rough / albedo maps")

	# 3 ROUND TRIP
	var keep: Dictionary = mesh.materials[1].duplicate()
	mesh.materials.append(full)
	var path := DIR + "/rt.kmesh"
	ok(mesh.save(path) == OK, "3a saved %s" % path)
	var back := KMesh.load_file(path)
	ok(back != null and back.materials == mesh.materials and back.has_attr(KMeshMaterial.ATTR) and back.attr_data(KMeshMaterial.ATTR) == mesh.attr_data(KMeshMaterial.ATTR),
		"3b load gives the 3 slots back equal, every field (%s) and the mat channel" % ("same" if back != null and back.materials == mesh.materials else "DIFFERENT: %s" % (back.materials if back != null else KMesh.last_error)))
	ok(back != null and back.materials[2]["normal_tex"] == maps["normal_tex"] and back.materials[2]["sss_tex"] == maps["sss_tex"] and back.materials[2]["metallic"] == full["metallic"],
		"3c the map paths survive: %s" % (back.materials[2]["normal_tex"] if back != null else "-"))
	var dd := mesh.to_dict()
	dd["materials"] = [{"name": "x", "albedo": "red"}]
	ok(KMesh.new().from_dict(dd) == null and KMesh.last_error.contains("restore a backup"), "3d a damaged slot is an error with a next step: '%s'" % KMesh.last_error)
	mesh.materials.remove_at(2)
	ok(mesh.materials[1] == keep, "3e (the third slot was only for the file test: gone again)")
	ui.view.mark_dirty()

	# 4 PIXELS
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)
	await idle(4)
	var ff := front_faces()
	var red_f := -1
	var grey_f := -1
	for fi in ff:
		var c := mesh.face_center(fi)
		if c.y > -0.2 and c.y < 0.0:
			if c.x < -0.05 and c.x > -0.2 and red_f < 0:
				red_f = fi
			elif c.x > 0.05 and c.x < 0.2 and grey_f < 0:
				grey_f = fi
	ok(ff.size() == 16 and red_f >= 0 and grey_f >= 0 and KMeshMaterial.face_slot(mesh, red_f) == 0 and KMeshMaterial.face_slot(mesh, grey_f) == 1,
		"4a front view: %d front cells, a red-slot cell %d and a grey-slot cell %d" % [ff.size(), red_f, grey_f])
	m.ui_root.visible = false
	var pr := fc(red_f)
	var pg := fc(grey_f)
	var img := await shot()
	var cr := img.get_pixelv(Vector2i(pr))
	var cg0 := img.get_pixelv(Vector2i(pg))
	ok(cr.r > 2.0 * cr.g and cr.r > 2.0 * cr.b and cr.r > 0.15, "4b the red-rough cell reads red: %s (bar r > 2g, r > 2b, r > 0.15)" % cr)
	ui.view.visible = false
	var img_off := await shot()
	ui.view.visible = true
	ok(dist(img_off.get_pixelv(Vector2i(pr)), cr) > 0.1, "4c the instrument can move: with the cube hidden that pixel is %s (distance %.3f > 0.1)" % [img_off.get_pixelv(Vector2i(pr)), dist(img_off.get_pixelv(Vector2i(pr)), cr)])
	pan.set_field(1, "metallic", 1.0)
	var img2 := await shot()
	var cg1 := img2.get_pixelv(Vector2i(pg))
	var cr1 := img2.get_pixelv(Vector2i(pr))
	ok(dist(cg0, cg1) > 0.05, "4d metallic 0 -> 1 under the same light: the grey cell %s -> %s (distance %.3f > 0.05)" % [cg0, cg1, dist(cg0, cg1)])
	ok(dist(cr, cr1) < 0.02, "4e the red cell did not move meanwhile (%.4f < 0.02): same light, same camera" % dist(cr, cr1))
	pan.set_field(1, "metallic", 0.0)
	img.save_png(OS.get_environment("TMP").path_join("pbrmat.png") if OS.get_environment("TMP") != "" else DIR + "/pbrmat.png")
	m.ui_root.visible = true

	# 5 UNDO
	ui.sel.set_mode(KMeshSelect.FACE)
	ui.sel.clear()
	var eight := []
	for fi in ff:
		if mesh.face_center(fi).x < 0.0:
			eight.append(fi)
			ui.sel.faces[fi] = true
	var before: PackedFloat32Array = mesh.attr_data(KMeshMaterial.ATTR).duplicate()
	var n0: int = ui.undo.steps.size()
	pan.cur = 1
	var nch := pan.assign_selection()
	var after: PackedFloat32Array = mesh.attr_data(KMeshMaterial.ATTR).duplicate()
	ok(nch == 8 and eight.size() == 8 and ui.undo.steps.size() == n0 + 1 and KMeshMaterial.counts(mesh) == PackedInt32Array([40, 56]), "5a Assign: %d faces changed, %d step(s), counts %s" % [nch, ui.undo.steps.size() - n0, KMeshMaterial.counts(mesh)])
	await key(KEY_Z, true)
	ok(mesh.attr_data(KMeshMaterial.ATTR) == before and ui.undo.steps.size() == n0, "5b Ctrl+Z restores the mat channel exactly (%s)" % KMeshMaterial.counts(mesh))
	await key(KEY_Z, true, true)
	ok(mesh.attr_data(KMeshMaterial.ATTR) == after, "5c Ctrl+Shift+Z puts the assignment back (%s)" % KMeshMaterial.counts(mesh))
	await idle(3)
	pan.cur = 1
	pan.refresh()
	var r0: float = mesh.materials[1]["roughness"]
	var sl: HSlider = pan.fields["roughness"]
	var n1: int = ui.undo.steps.size()
	sl.drag_started.emit()
	for v in [0.5, 0.6, 0.7, 0.8, 0.9]:
		sl.value = v
		await process_frame
	sl.drag_ended.emit(true)
	await idle(2)
	ok(ui.undo.steps.size() == n1 + 1 and is_equal_approx(mesh.materials[1]["roughness"], 0.9), "5d a roughness drag over 5 values is %d step (roughness now %.2f)" % [ui.undo.steps.size() - n1, mesh.materials[1]["roughness"]])
	await key(KEY_Z, true)
	ok(mesh.materials[1]["roughness"] == r0, "5e its undo puts the roughness back exactly (%.4f, was %.4f)" % [mesh.materials[1]["roughness"], r0])
	var ns := pan.select_by(0)
	ok(ns == KMeshMaterial.counts(mesh)[0] and ui.sel.mode == KMeshSelect.FACE, "5f Select by slot 0: %d faces (its count %d)" % [ns, KMeshMaterial.counts(mesh)[0]])

	# 5R REAL BUTTONS: two faces picked on the cube, a new slot by a real press on Add, then a real press on Assign:
	# exactly the two picked faces are on the new slot, and the Assign is one undo step
	m.ui_root.visible = true
	ui.sel.clear()
	ui.sel.set_mode(KMeshSelect.FACE)
	ui.sel.faces[5] = true
	ui.sel.faces[60] = true
	ui.view.mark_dirty()
	await idle(3)
	var add_b := pan.find_child("btn_mat_add", true, false) as Button
	var assign_b := pan.find_child("btn_mat_assign", true, false) as Button
	ok(add_b != null and assign_b != null and add_b.is_visible_in_tree() and assign_b.is_visible_in_tree(), "5R0 the Materials panel's Add and Assign buttons are on screen")
	var nslot0 := mesh.materials.size()
	await press_button(add_b)
	ok(mesh.materials.size() == nslot0 + 1 and pan.cur == nslot0, "5R1 a real press on Add makes slot %d (%d slots) and picks it" % [nslot0, mesh.materials.size()])
	var n5r := ui.undo.steps.size()
	await press_button(assign_b)
	var got: Array = Array(KMeshMaterial.faces_of(mesh, nslot0))
	got.sort()
	ok(got == [5, 60], "5R2 a real press on Assign: slot %d holds exactly the picked faces (%s, want [5, 60])" % [nslot0, str(got)])
	ok(ui.undo.steps.size() == n5r + 1, "5R3 the Assign is one undo step (%d -> %d)" % [n5r, ui.undo.steps.size()])

	# 6 E15
	var ph := KMeshMaterial.from_photo(mesh.materials[0], "bricks")
	ok(ph["albedo_tex"] == "user://materials/bricks/albedo.png" and ph["roughness_tex"] == "user://materials/bricks/rough.png" and ph["normal_tex"] == "user://materials/bricks/normal.png" and ph["name"] == "Red rough",
		"6 a photo material feeds a slot: %s, %s, %s" % [ph["albedo_tex"], ph["roughness_tex"], ph["normal_tex"]])

	# 7 PLACEMENT
	ui.topo("heat")
	await idle(6)
	var vr := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var pr_r := pan.get_global_rect()
	var pp_r := ui.prim_panel.get_global_rect()
	var lg_r := ui.legend.get_global_rect() if ui.legend != null and ui.legend.visible else Rect2()
	var cl: Rect2 = m.nav_clear_rect()
	# Nick 2026-10-24: the panel may sit inside the clear view OR docked in the right column (wholly right of the clear
	# view, covering none of it)
	var docked := pr_r.position.x >= cl.end.x - 1.0
	ok(pan.visible and pan.is_visible_in_tree() and vr.encloses(pr_r) and (cl.grow(1.0).encloses(pr_r) or docked) and pr_r.size.x > 100 and pr_r.size.y > 100,
		"7a the panel is on screen %s, inside the window %s and inside the clear view %s or docked right of it (%s)" % [pr_r, vr, cl, docked])
	ok(ui.prim_panel.visible and not pr_r.intersects(pp_r) and (lg_r.size == Vector2.ZERO or not pr_r.intersects(lg_r)),
		"7b it does not overlap the Add primitive panel %s (nor the heat legend %s)" % [pp_r, lg_r])
	(await shot()).save_png(OS.get_environment("TMP").path_join("pbrmat_ui.png") if OS.get_environment("TMP") != "" else DIR + "/pbrmat_ui.png")
	ui.topo("heat")
	var lb := pan.list.get_item_text(0)
	ok(lb.begins_with("Red rough") and lb.contains("faces"), "7c the slot list reads '%s'" % lb)
	ok(pan.get_parent() == m.ui_cmd.get_parent() and pan.get_index() < m.ui_cmd.get_index(), "7e the S search box draws over the panel (panel index %d < search box %d in the same parent)" % [pan.get_index(), m.ui_cmd.get_index()])
	ui.stop()
	await idle(3)
	ok(not pan.visible, "7d leaving the cube hides the panel")

	print("PBRMAT: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	# ---- round 2 bar: Add material with faces selected gives the new slot those faces only
	if not ui.on or ui.view == null:   # the cube may be stopped by an earlier bar: open it again
		m._kmesh_edit_start()
		await idle(3)
		ui = m.kmed
		pan = ui.mat_panel
	var sel_fs := [3, 4, 5]
	ui.sel.set_mode(KMeshSelect.FACE)
	ui.sel.clear()
	for fi in sel_fs:
		ui.sel.faces[fi] = true
	var new_i: int = pan.add_slot({"name": "Round2 sel"})
	var got := Array(KMeshMaterial.faces_of(ui.mesh, new_i))
	got.sort()
	ok(got == sel_fs, "R2 Add material with faces %s selected: the new slot holds %s (bar: exactly those faces)" % [str(sel_fs), str(got)])

	quit(1 if fails > 0 else 0)
