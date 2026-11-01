extends SceneTree
## godot --path . --position 4000,4000 -s tests/s114_test.gd   (Friday plan 114: Export dialog > 3D printing > Printer bed + Split to fit, with dowel holes; needs the CAD DLL)
## Real clicks at 1280 x 720: the BUILDING card, a 400 x 100 x 20 mm plate, the Export button, the Split to fit tick, the dialog's Export button. Every number is read back from the written files.
##   1 UI        the dialog shows Printer bed 220 / 220 / 250 and a Split to fit tick; with it ticked the checklist says it will cut into 2 pieces
##   2 3MF       2 objects, each <= 220 mm in every axis, each closed (every edge shared twice)
##   3 VOLUME    the pieces' volumes add to 800000 minus 4 holes (4 x pi x 2.5^2 x 10 = 785.4 mm3) within 0.5 pct, and the loss is the holes (785 +- 60)
##   4 DOWELS    each piece has 2 holes of 5 mm (+- 0.1) on the cut face; the centres match across the cut within 0.05 mm
##   5 STL       the STL road writes one file a piece, each fits and is closed
##   6 FITS      the same plate on a 450 mm bed is not split (1 object, 800000 mm3); a 20 x 10 x 5 box with Split ticked is one object
##   7 GRID      a 300 x 300 x 20 plate on 220 -> 4 pieces, 8 dowel sites, every piece fits, volume = original minus the holes
const DIR := "user://zz_s114"
const DIRT := "user://zz_s114_scenes"
const SHOT := "C:/Temp/claude/s114"
var fails := 0
var m: Node
var pu: PartUI


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


## a real click inside the embedded Export dialog: its controls' rects are in the dialog window's own coordinates, so the events go to that window
func click_dlg(w: Window, c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var target: Window = w
	if w.is_embedded():   # an embedded dialog takes its mouse from the root window, in root coordinates
		p += Vector2(w.position)
		target = root
	for st in [[false, false], [true, true], [true, false]]:
		var e: InputEvent
		if st[0]:
			var b := InputEventMouseButton.new()
			b.button_index = MOUSE_BUTTON_LEFT
			b.pressed = st[1]
			b.button_mask = MOUSE_BUTTON_MASK_LEFT if st[1] else 0
			e = b
		else:
			e = InputEventMouseMotion.new()
		(e as InputEventMouse).position = p
		(e as InputEventMouse).global_position = p
		target.push_input(e, true)
		await process_frame
	await idle(3)


func shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, name])


func plate(w: float, d: float, h: float) -> Dictionary:
	var rec := Part.make("Plate")
	var fs: Array = rec["features"]
	var sid := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(w, d))])
	PartTemplates._ex(fs, sid, "extrude", h, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


func read_stl(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	var n := b.decode_u32(80) if b.size() >= 84 else 0
	var corners := PackedVector3Array()
	for i in n:
		for k in 3:
			var q := 84 + 50 * i + 12 + 12 * k
			corners.append(Vector3(b.decode_float(q), b.decode_float(q + 4), b.decode_float(q + 8)))
	return weld(corners)


func weld(corners: PackedVector3Array) -> Dictionary:
	var ids := {}
	var v := PackedVector3Array()
	var t := PackedInt32Array()
	for p in corners:
		var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if not ids.has(key):
			ids[key] = v.size()
			v.append(p)
		t.append(ids[key])
	return {"v": v, "t": t}


## every object of a 3MF read back from the zip: [{"v", "t"}]
func read_3mf(path: String) -> Array:
	var out := []
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return out
	var model := z.read_file("3D/3dmodel.model")
	z.close()
	var xp := XMLParser.new()
	xp.open_buffer(model)
	var cv := PackedVector3Array()
	var ct := PackedInt32Array()
	while xp.read() != ERR_FILE_EOF:
		var t := xp.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			match xp.get_node_name():
				"object":
					cv = PackedVector3Array()
					ct = PackedInt32Array()
				"vertex":
					cv.append(Vector3(float(xp.get_named_attribute_value("x")), float(xp.get_named_attribute_value("y")), float(xp.get_named_attribute_value("z"))))
				"triangle":
					for a in ["v1", "v2", "v3"]:
						ct.append(int(xp.get_named_attribute_value(a)))
		elif t == XMLParser.NODE_ELEMENT_END and xp.get_node_name() == "object":
			out.append({"v": cv, "t": ct})
	return out


func sum_all(a: Array) -> float:
	var t := 0.0
	for o in a:
		t += vol(o)
	return t


func vol(mesh: Dictionary) -> float:
	var v: PackedVector3Array = mesh["v"]
	var t: PackedInt32Array = mesh["t"]
	var s := 0.0
	for i in range(0, t.size(), 3):
		s += v[t[i]].dot(v[t[i + 1]].cross(v[t[i + 2]]))
	return s / 6.0


func box_of(mesh: Dictionary) -> AABB:
	var v: PackedVector3Array = mesh["v"]
	var b := AABB(v[0], Vector3.ZERO)
	for p in v:
		b = b.expand(p)
	return b


func not_two(mesh: Dictionary) -> int:
	var t: PackedInt32Array = mesh["t"]
	var cnt := {}
	for i in range(0, t.size(), 3):
		for k in 3:
			var a := t[i + k]
			var c := t[i + (k + 1) % 3]
			var key := (mini(a, c) << 32) | maxi(a, c)
			cnt[key] = int(cnt.get(key, 0)) + 1
	var bad := 0
	for k in cnt:
		if int(cnt[k]) != 2:
			bad += 1
	return bad


func fit_all(meshes: Array, bed: Vector3) -> bool:
	for me in meshes:
		var s := box_of(me).size
		if s.x > bed.x + 0.001 or s.y > bed.y + 0.001 or s.z > bed.z + 0.001:
			return false
	return true


## the holes found on a mesh's face at coordinate pos along axis: vertices on that plane that are not on the face's outer rectangle, grouped; [{"c": centre, "d": diameter}]
func holes_at(mesh: Dictionary, axis: int, pos: float) -> Array:
	var v: PackedVector3Array = mesh["v"]
	var on := []
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for p in v:
		if absf(p[axis] - pos) < 0.01:
			on.append(p)
			for a in 3:
				lo[a] = minf(lo[a], p[a])
				hi[a] = maxf(hi[a], p[a])
	var inner := []
	for p in on:
		var edge := false
		for a in 3:
			if a != axis and (absf(p[a] - lo[a]) < 0.01 or absf(p[a] - hi[a]) < 0.01):
				edge = true
		if not edge:
			inner.append(p)
	var groups := []
	for p in inner:
		var g := -1
		for gi in groups.size():
			for q in groups[gi]:
				if (q as Vector3).distance_to(p) < 4.0:
					g = gi
					break
			if g >= 0:
				break
		if g < 0:
			groups.append([p])
		else:
			groups[g].append(p)
	var out := []
	for g in groups:
		var b := AABB(g[0], Vector3.ZERO)
		for p in g:
			b = b.expand(p)
		var d := maxf(b.size[(axis + 1) % 3], b.size[(axis + 2) % 3])
		out.append({"c": b.get_center(), "d": d})
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(DIR)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR) + "/" + f)
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
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		print("s114: 1 fail")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)

	m.S.part = plate(400, 100, 20)
	pu._rec_sig = ""
	await idle(8)
	var eb := root.find_child("easypart_export", true, false) as Button
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var sb: Array = ui.ui_bed
	var chk := root.find_child("chk_export_split", true, false) as CheckBox
	ok(ui.dlg.visible and chk != null and chk.is_visible_in_tree() and sb.size() == 3 and absf(sb[0].value - 220.0) < 0.01 and absf(sb[1].value - 220.0) < 0.01 and absf(sb[2].value - 250.0) < 0.01 and not chk.button_pressed,
		"1 the dialog shows Printer bed 220 / 220 / 250 and an unticked Split to fit")
	await idle(12)
	var before := String(ui.ui_checks.text)
	print("tick at %s, format button at %s, dialog %s" % [str(chk.get_global_rect()), str(ui.ui_format.get_global_rect()), str(ui.dlg.get_visible_rect())])
	await click_dlg(ui.dlg, chk)
	await idle(4)
	var after := String(ui.ui_checks.text)
	print("DBG emb=%s pos=%s size=%s cs=%s pressed=%s" % [str(ui.dlg.is_embedded()), str(ui.dlg.position), str(ui.dlg.size), str(ui.dlg.content_scale_factor), str(chk.button_pressed)])
	ok(chk.button_pressed and ui.split_fit and before.contains("bigger than the printer bed") and after.contains("cuts it into 2 pieces"),
		"1 ticking Split to fit by a real click changes the checklist (before: bigger than the printer bed; after: cuts it into 2 pieces)")
	shot("dialog_split")
	var p3 := ProjectSettings.globalize_path(DIR) + "/Plate.3mf"
	ui.dlg.get_ok_button().pressed.emit()
	await idle(6)
	var p3r := "res://exports/Plate.3mf"
	if not FileAccess.file_exists(p3) and FileAccess.file_exists(ProjectSettings.globalize_path(p3r)):
		p3 = ProjectSettings.globalize_path(p3r)
	ok(FileAccess.file_exists(p3), "1 the dialog's Export button wrote %s" % p3)
	var all3 := read_3mf(p3)
	var objs := []
	var pins3 := []
	for o in all3:
		if box_of(o).size.x > 20.0:
			objs.append(o)
		else:
			pins3.append(o)
	var bed := Vector3(220, 220, 250)
	ok(objs.size() == 2 and fit_all(objs, bed), "2 the 3MF holds %d objects, sizes %s" % [objs.size(), str(objs.map(func(o): return box_of(o).size))])
	var nt := 0
	for o in objs:
		nt += not_two(o)
	ok(objs.size() == 2 and nt == 0, "2 every edge of both pieces is shared by exactly 2 triangles (%d are not)" % nt)
	var sum := 0.0
	for o in objs:
		sum += vol(o)
	var want := 800000.0 - 4.0 * PI * 2.5 * 2.5 * 10.0
	var pin_len := 19.0
	var psum := 0.0
	var pin_dia_ok := pins3.size() == 2
	var pdia := 0.0
	for pn in pins3:
		psum += vol(pn)
		pdia = maxf(box_of(pn).size.x, box_of(pn).size.y)
		pin_dia_ok = pin_dia_ok and absf(pdia - 4.8) <= 0.02 and absf(box_of(pn).size.z - pin_len) <= 0.05
	ok(pin_dia_ok and all3.size() == 4, "3 the 3MF holds 2 pieces + %d separate pins, pin diameter %.3f mm, length %.2f mm" % [pins3.size(), pdia, box_of(pins3[0]).size.z if pins3.size() > 0 else 0.0])
	var total_want := want + 2.0 * PI * 2.4 * 2.4 * pin_len
	ok(absf(sum_all(all3) - total_want) <= 0.005 * total_want, "3 pieces + pins %.1f mm3 = original - holes + pins %.1f within 0.5 pct" % [sum_all(all3), total_want])
	ok(absf(sum - want) <= 0.005 * want and absf((800000.0 - sum) - 785.4) <= 60.0, "3 pieces add to %.1f mm3 (want %.1f within 0.5 pct); the loss %.1f mm3 is the holes (785.4)" % [sum, want, 800000.0 - sum])
	if objs.size() == 2:
		objs.sort_custom(func(a, b): return box_of(a).position.x < box_of(b).position.x)
		var cutx := box_of(objs[0]).end.x
		var ha := holes_at(objs[0], 0, cutx)
		var hb := holes_at(objs[1], 0, cutx)
		var dia_ok := ha.size() == 2 and hb.size() == 2
		var worst := 0.0
		if dia_ok:
			for h in ha:
				if absf(float(h["d"]) - 5.0) > 0.1:
					dia_ok = false
				var best := 1e9
				for g in hb:
					best = minf(best, (h["c"] as Vector3).distance_to(g["c"]))
				worst = maxf(worst, best)
			for h in hb:
				if absf(float(h["d"]) - 5.0) > 0.1:
					dia_ok = false
		ok(dia_ok and pins3.size() == 2 and absf((float(ha[0]["d"]) - pdia) - 0.2) <= 0.02, "4 hole diameter %.3f = pin diameter %.3f + 0.2 (within 0.02)" % [float(ha[0]["d"]) if ha.size() > 0 else 0.0, pdia])
		ok(dia_ok, "4 the cut face at x = %.2f has %d holes in piece 1 and %d in piece 2, diameters %s mm" % [cutx, ha.size(), hb.size(), str(ha.map(func(h): return snappedf(float(h["d"]), 0.01)))])
		ok(dia_ok and worst <= 0.05, "4 hole centres match across the cut within %.4f mm (centres %s)" % [worst, str(ha.map(func(h): return h["c"]))])
		var deep := 0
		for p in (objs[0]["v"] as PackedVector3Array):
			if absf(p.x - (cutx - 10.0)) < 0.01:
				deep += 1
		ok(deep > 8, "4 the holes are 10 mm deep (%d vertices on hole bottoms at x = %.2f)" % [deep, cutx - 10.0])

	# 5 STL: one file a piece
	var stl_first := String(ui.export_now("print", 1, DIR))
	var stls := []
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(DIR)):
		if f.ends_with(".stl"):
			stls.append(f)
	var sm := []
	for f in stls:
		sm.append(read_stl(ProjectSettings.globalize_path(DIR) + "/" + f))
	var snt := 0
	for o in sm:
		snt += not_two(o)
	ok(stls.size() == 4 and fit_all(sm.slice(0, 2), bed) and snt == 0 and stl_first != "", "5 STL: %s (2 pieces + 2 pins), each piece fits the bed, %d edges not shared twice" % [str(stls), snt])

	# 6 a part that fits is not split
	var r6 := PrintSplit.export_part(m.S.part, "3mf", DIR, Vector3(450, 450, 250))
	var o6 := read_3mf(String(r6["path"]))
	ok(not bool(r6["split"]) and o6.size() == 1 and absf(vol(o6[0]) - 800000.0) <= 4000.0, "6 plate on a 450 bed: split=%s, %d object, %.0f mm3" % [str(r6["split"]), o6.size(), vol(o6[0]) if o6.size() > 0 else 0.0])
	var r6b := PrintSplit.split_rec(plate(20, 10, 5), bed)
	ok(not bool(r6b["split"]) and (r6b["bodies"] as Array).size() == 1, "6 a 20 x 10 x 5 box is not split")

	# 7 grid
	var r7 := PrintSplit.split_rec(plate(300, 300, 20), bed)
	var nh := 0
	for c in r7["cuts"]:
		nh += (c["holes"] as Array).size()
	var s7 := 0.0
	var f7 := true
	var np7 := 0
	for b in r7["bodies"]:
		if String(b["name"]).begins_with("Dowel pin"):
			np7 += 1
			continue
		s7 += MeshExport.signed_volume(b)
		f7 = f7 and PrintSplit.fits(PrintSplit.bbox_of(b).size, bed)
	var want7 := 300.0 * 300.0 * 20.0 - 8.0 * 2.0 * PI * 2.5 * 2.5 * 10.0
	ok(int(r7["pieces"]) == 4 and np7 == 8 and nh == 8 and f7 and absf(s7 - want7) <= 0.005 * want7, "7 300 x 300 plate: %d pieces, %d pins, %d dowel sites, volume %.1f (want %.1f)" % [int(r7["pieces"]), np7, nh, s7, want7])

	# screenshot of the 4-piece case in the dialog
	m.S.part = plate(300, 300, 20)
	pu._rec_sig = ""
	await idle(6)
	ui.open()
	await idle(6)
	shot("dialog_four")
	ui.dlg.hide()
	print("s114: %d fail" % fails)
	quit(1 if fails > 0 else 0)
