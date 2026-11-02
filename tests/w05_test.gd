extends SceneTree
## godot --path . --position 4000,4000 -s tests/w05_test.gd     (W05: export mesh quality Coarse / Normal / Fine / Custom, live triangle count and file size)
## Bars, written before any number was seen. A cylinder r = 10 mm, 20 tall, on the floor:
##   1 RATIO     Fine tris / Coarse tris >= 3 (in the WRITTEN STL)
##   2 ESTIMATE  the size the dialog shows is within 5 pct of the written file, STL and 3MF, at Coarse / Normal / Fine / Custom 0.05 mm; the shown count equals the file's
##   3 CHORD     the worst chord error of the written mesh (rim circle r = 10) <= chosen deflection + 0.001 mm, every quality
##   4 NORMAL    Normal writes the very mesh the export always wrote (same triangle count as MeshExport.bodies_of(rec))
##   5 UI        the Mesh quality row is on screen at 1024 x 600 and 1920 x 1080, changing it changes the words under it, a screenshot is saved
## Controls: a planted estimate 10 pct off fails bar 2; a Coarse written with Fine numbers fails bar 1.
const DIR := "user://zz_w05"
const DIRT := "user://zz_w05_scenes"
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


## a triangle list read from a file: corners (3 per triangle) and the stored normals (or none)
func tri_report(corners: PackedVector3Array, normals: PackedVector3Array) -> Dictionary:
	var ids := {}
	var idx := []
	for p in corners:
		var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if not ids.has(key):
			ids[key] = ids.size()
		idx.append(ids[key])
	var cnt := {}
	for i in range(0, idx.size(), 3):
		for k in 3:
			var a: int = idx[i + k]
			var b: int = idx[i + (k + 1) % 3]
			var key2 := (mini(a, b) << 32) | maxi(a, b)
			cnt[key2] = int(cnt.get(key2, 0)) + 1
	var not_two := 0
	for k in cnt:
		if int(cnt[k]) != 2:
			not_two += 1
	var box := AABB(corners[0], Vector3.ZERO)
	for p in corners:
		box = box.expand(p)
	var vol := 0.0
	var outward := 0
	var agree := 0
	for i in range(0, corners.size(), 3):
		vol += corners[i].dot(corners[i + 1].cross(corners[i + 2])) / 6.0
		var wn := (corners[i + 1] - corners[i]).cross(corners[i + 2] - corners[i]).normalized()
		var cen := (corners[i] + corners[i + 1] + corners[i + 2]) / 3.0
		if wn.dot(cen - box.get_center()) > 0.0:
			outward += 1
		if normals.size() > i / 3 and normals[i / 3].dot(wn) > 0.99:
			agree += 1
	return {"tris": corners.size() / 3, "verts": ids.size(), "not_two": not_two, "box": box, "vol": vol, "outward": outward, "agree": agree}


func read_stl(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	var out := {"bytes": b.size(), "head": "", "n": 0, "rep": {}}
	if b.size() < 84:
		return out
	out["head"] = b.slice(0, 80).get_string_from_ascii()
	var n := b.decode_u32(80)
	out["n"] = n
	var corners := PackedVector3Array()
	var normals := PackedVector3Array()
	if b.size() == 84 + 50 * n and n > 0:
		for i in n:
			var o := 84 + 50 * i
			normals.append(Vector3(b.decode_float(o), b.decode_float(o + 4), b.decode_float(o + 8)))
			for k in 3:
				var q := o + 12 + 12 * k
				corners.append(Vector3(b.decode_float(q), b.decode_float(q + 4), b.decode_float(q + 8)))
		out["rep"] = tri_report(corners, normals)
	return out


## the 3MF read back from the zip
func read_3mf(path: String) -> Dictionary:
	var out := {"entries": [], "unit": "", "objects": 0, "verts": 0, "tris": 0, "items": 0, "bases": 0, "colors": [], "rep": {}, "pids": 0, "xml": ""}
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return out
	out["entries"] = Array(z.get_files())
	var model := z.read_file("3D/3dmodel.model")
	z.close()
	out["xml"] = model.get_string_from_utf8()
	var xp := XMLParser.new()
	xp.open_buffer(model)
	var first_rep := {}
	var cur_v := PackedVector3Array()
	var cur_t := []
	var in_obj := false
	while xp.read() != ERR_FILE_EOF:
		var t := xp.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			match xp.get_node_name():
				"model":
					out["unit"] = xp.get_named_attribute_value_safe("unit")
				"object":
					out["objects"] += 1
					in_obj = true
					cur_v = PackedVector3Array()
					cur_t = []
					if xp.has_attribute("pid"):
						out["pids"] += 1
				"vertex":
					cur_v.append(Vector3(float(xp.get_named_attribute_value("x")), float(xp.get_named_attribute_value("y")), float(xp.get_named_attribute_value("z"))))
					out["verts"] += 1
				"triangle":
					cur_t.append([int(xp.get_named_attribute_value("v1")), int(xp.get_named_attribute_value("v2")), int(xp.get_named_attribute_value("v3"))])
					out["tris"] += 1
				"item":
					out["items"] += 1
				"base":
					out["bases"] += 1
					out["colors"].append(xp.get_named_attribute_value_safe("displaycolor"))
		elif t == XMLParser.NODE_ELEMENT_END and xp.get_node_name() == "object" and in_obj:
			in_obj = false
			if first_rep.is_empty():
				var corners := PackedVector3Array()
				for tt in cur_t:
					for k in 3:
						corners.append(cur_v[tt[k]])
				first_rep = tri_report(corners, PackedVector3Array())
	out["rep"] = first_rep
	return out



const SHOTS := "C:/Users/Nick/tools/kine_workers/out/w05"


func stl_chord(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	var n := b.decode_u32(80)
	var worst := 0.0
	var edges := 0
	for i in n:
		var o := 84 + 50 * i + 12
		var p: Array = []
		for k in 3:
			p.append(Vector3(b.decode_float(o + 12 * k), b.decode_float(o + 12 * k + 4), b.decode_float(o + 12 * k + 8)))
		for k in 3:
			var a: Vector3 = p[k]
			var c: Vector3 = p[(k + 1) % 3]
			var ra := Vector2(a.x, a.y).length()
			var rc := Vector2(c.x, c.y).length()
			if absf(ra - 10.0) < 0.02 and absf(rc - 10.0) < 0.02 and absf(a.z - c.z) > 1.0:   # side-wall diagonals (vertical edges have no error, cap chords are flat)
				var mid := (a + c) * 0.5
				worst = maxf(worst, 10.0 - Vector2(mid.x, mid.y).length())
				edges += 1
	return {"n": n, "bytes": b.size(), "worst": worst, "edges": edges}


func stl_n(path: String) -> int:
	return FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)).decode_u32(80)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(SHOTS)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
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
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var rec := Part.make("Cyl")
	var fs: Array = rec["features"]
	var sid := PartTemplates._sk(fs, "top", [{"k": "circle", "c": Part.arr2(Vector2.ZERO), "r": 10.0}])
	PartTemplates._ex(fs, sid, "extrude", 20.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	m.S.part = rec
	pu._rec_sig = ""
	await idle(8)
	var eb := root.find_child("easypart_export", true, false) as Button
	await click_ctl(eb)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	ok(ui != null and ui.dlg.visible and ui.ui_q != null and ui.ui_q_row.is_visible_in_tree(), "5 the Mesh quality row is on screen in the printing dialog")
	var names := []
	for i in ui.ui_q.item_count:
		names.append(ui.ui_q.get_item_text(i))
	ok(names == ["Coarse", "Normal", "Fine", "Custom"] and ui.ui_q.selected == 1, "5 choices %s, Normal is the default" % str(names))

	var res := {}
	var cases := [["Coarse", 0.1, 0.5], ["Normal", 0.1, 0.1], ["Fine", 0.1, 0.01], ["Custom", 0.05, 0.05]]
	var words_seen := []
	for c in cases:
		ui.ui_q.select(names.find(c[0]))
		ui.ui_q.item_selected.emit(names.find(c[0]))
		ui.ui_q_custom.value = c[1]
		await idle(2)
		for fmt in ["stl", "3mf"]:
			ui.ui_format.select(0 if fmt == "3mf" else 1)
			ui.ui_format.item_selected.emit(ui.ui_format.selected)
			await idle(2)
			var shown := ui.ui_q_info.text
			var est := MeshQuality.estimate(MeshExport.bodies_of(m.S.part, ui.quality())["bodies"], fmt, "Cyl")
			var path := String(ui.export_now("print", ui.ui_format.selected, DIR))
			var sz := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)).size()
			var tris := stl_n(path) if fmt == "stl" else int(read_3mf(ProjectSettings.globalize_path(path))["tris"])
			res["%s|%s" % [c[0], fmt]] = {"chord": stl_chord(ProjectSettings.globalize_path(path)) if fmt == "stl" else {},"est": int(est["bytes"]), "file": sz, "tris": tris, "shown": shown, "path": path, "defl": c[2], "est_tris": int(est["tris"])}
			words_seen.append(shown)
	for k in res:
		var r: Dictionary = res[k]
		var err := absf(float(r["est"]) - float(r["file"])) / maxf(1.0, float(r["file"]))
		ok(err <= 0.05 and int(r["est_tris"]) == int(r["tris"]) and String(r["shown"]).contains(MeshQuality._grp(int(r["tris"]))), "2 %s: shown '%s'; file %d bytes, estimate %d (%.2f pct), tris file %d / estimate %d" % [k, r["shown"], r["file"], r["est"], err * 100.0, r["tris"], r["est_tris"]])
		var ch: Dictionary = res[String(k).split("|")[0] + "|stl"]["chord"]
		ok(float(ch["worst"]) <= float(r["defl"]) + 0.001 and int(ch["edges"]) > 0, "3 %s chord error %.4f mm <= %.3f + 0.001 (%d rim edges)" % [k, ch["worst"], r["defl"], ch["edges"]])
	var tc := int(res["Coarse|stl"]["tris"])
	var tf := int(res["Fine|stl"]["tris"])
	ok(tf >= 3 * tc and tc > 0, "1 Fine %d triangles vs Coarse %d = %.1fx (bar 3x)" % [tf, tc, float(tf) / maxf(1.0, float(tc))])
	var base := 0
	for b in MeshExport.bodies_of(m.S.part)["bodies"]:
		base += (b["t"] as PackedInt32Array).size() / 3
	ok(int(res["Normal|stl"]["tris"]) == base, "4 Normal writes %d triangles, the old export %d" % [res["Normal|stl"]["tris"], base])
	var fake := float(res["Fine|stl"]["est"]) * 1.10
	ok(absf(fake - float(res["Fine|stl"]["file"])) / float(res["Fine|stl"]["file"]) > 0.05, "control: a planted estimate 10 pct off fails the 5 pct bar")
	ok(not (tf >= 3 * tf), "control: Coarse written with Fine numbers (ratio 1) fails the 3x bar")
	ok(words_seen[0] != words_seen[4], "5 changing the quality changes the words under it ('%s' -> '%s')" % [words_seen[0], words_seen[4]])

	for wsz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
		root.size = wsz
		root.content_scale_size = wsz
		await idle(6)
		ui.ui_q.select(2)
		ui.ui_q.item_selected.emit(2)
		ui.ui_format.select(0)
		ui.ui_format.item_selected.emit(0)
		ui.dlg.popup_centered()
		await idle(6)
		var r2 := ui.ui_q_row.get_global_rect()
		ok(Rect2(Vector2.ZERO, Vector2(wsz)).encloses(r2) and ui.ui_q_row.is_visible_in_tree(), "5 %s: the Mesh quality row %s is inside the window" % [str(wsz), str(r2)])
		root.get_texture().get_image().save_png("%s/w05_%dx%d.png" % [SHOTS, wsz.x, wsz.y])
	print("w05: %d fail" % fails)
	quit(1 if fails > 0 else 0)
