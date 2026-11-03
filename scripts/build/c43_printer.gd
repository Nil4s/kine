## C43 (complaints #323, #365): PRINTER TRUTH in the Export dialog.
##   1 PRINTER ROW   a Printer choice in the 3D printing export (Any / the C03 presets): picking one writes the part's fit_mm and printer_preset (what holes, lids, fasteners and
##                   the print-in-place hinge already read) and is SAVED (user://c43_printer.cfg), so the next part opens with it. Any = nothing chosen = every default as before.
##   2 RE-READ       after an STL / 3MF export the written file is read back from disk and drawn as the preview: its triangle count, size and volume are set against the part
##                   (the same 0.5 pct tolerance C10Print.verify_file uses) and a mismatch is said in words.
## Pure helpers plus build() / refresh() / after_export() for the dialog (scripts/export_dialog.gd calls these; nothing else of it changes).
class_name C43Printer
extends RefCounted

const CFG := "user://c43_printer.cfg"
const C03 := preload("res://scripts/build/c03_tools.gd")
const TOL_PCT := 0.5   # the same tolerance as C10Print.OFF_PCT


# ---------------------------------------------------------------- saved choice

static func saved() -> String:
	var c := ConfigFile.new()
	if c.load(CFG) != OK:
		return ""
	return String(c.get_value("printer", "name", ""))


static func save(name: String) -> void:
	var c := ConfigFile.new()
	c.set_value("printer", "name", name)
	c.save(CFG)


## item index in the Printer picker for a part: 0 = Any, 1.. = C03Tools.PRESETS
static func item_of(rec: Dictionary) -> int:
	return C03.index_of(rec) + 1


## pick item i for the part (0 = Any): writes fit_mm + printer_preset through C03Tools.apply, or takes them off; remembers the choice
static func choose(rec: Dictionary, i: int) -> void:
	if i <= 0:
		if rec.has("printer_preset"):
			rec.erase("printer_preset")
			rec.erase("fit_mm")
		save("")
		return
	C03.apply(rec, i - 1)
	save(String(C03.PRESETS[i - 1]["name"]))


## on opening the dialog: a part with no printer and no fit of its own takes the saved printer (nothing saved = nothing changes)
static func adopt_saved(rec: Dictionary) -> bool:
	if rec.is_empty() or rec.has("fit_mm") or rec.has("printer_preset"):
		return false
	var nm := saved()
	for i in C03.PRESETS.size():
		if String(C03.PRESETS[i]["name"]) == nm:
			C03.apply(rec, i)
			return true
	return false


static func words(rec: Dictionary) -> String:
	var i := C03.index_of(rec)
	if i < 0:
		return "No printer chosen: holes, lids and hinges keep their usual gaps."
	return "%s: holes, lids, fasteners and hinges keep %s mm on each side. Saved for your next part." % [C03.PRESETS[i]["name"], str(C03.PRESETS[i]["clear"])]


# ---------------------------------------------------------------- re-read the written file

## {"ok", "tris", "v": triangle soup (mm, printer axes), "size": Vector3, "vol": mm3}
static func reread(path: String, fmt: String) -> Dictionary:
	var soup := PackedVector3Array()
	if fmt == "stl":
		var buf := FileAccess.get_file_as_bytes(path)
		if buf.size() < 84:
			return {"ok": false}
		var n := buf.decode_u32(80)
		if buf.size() < 84 + n * 50:
			return {"ok": false}
		for k in n:
			var o := 84 + k * 50 + 12
			for j in 3:
				soup.append(Vector3(buf.decode_float(o + j * 12), buf.decode_float(o + j * 12 + 4), buf.decode_float(o + j * 12 + 8)))
	else:
		var z := ZIPReader.new()
		if z.open(path) != OK:
			return {"ok": false}
		var xml := z.read_file("3D/3dmodel.model")
		z.close()
		var p := XMLParser.new()
		if p.open_buffer(xml) != OK:
			return {"ok": false}
		var v := PackedVector3Array()
		while p.read() == OK:
			if p.get_node_type() == XMLParser.NODE_ELEMENT_END and p.get_node_name() == "mesh":
				v = PackedVector3Array()
			elif p.get_node_type() == XMLParser.NODE_ELEMENT:
				var nm := p.get_node_name()
				if nm == "vertex":
					v.append(Vector3(float(p.get_named_attribute_value("x")), float(p.get_named_attribute_value("y")), float(p.get_named_attribute_value("z"))))
				elif nm == "triangle":
					for a in ["v1", "v2", "v3"]:
						soup.append(v[int(p.get_named_attribute_value(a))])
	if soup.size() < 3:
		return {"ok": false}
	var vol := 0.0
	var box := AABB(soup[0], Vector3.ZERO)
	for i in range(0, soup.size() - 2, 3):
		vol += soup[i].dot(soup[i + 1].cross(soup[i + 2])) / 6.0
		box = box.expand(soup[i]).expand(soup[i + 1]).expand(soup[i + 2])
	return {"ok": true, "tris": soup.size() / 3, "v": soup, "size": box.size, "vol": absf(vol)}


## the part's own numbers (from the bodies that were written) against the re-read file
static func compare(bodies: Array, got: Dictionary) -> Dictionary:
	if not bool(got.get("ok", false)):
		return {"match": false, "text": "The file could not be read back. Open it in your slicer before you print."}
	var tp := 0
	var vol := 0.0
	var box := AABB()
	var first := true
	for b in bodies:
		var v: PackedVector3Array = b["v"]
		var t: PackedInt32Array = b["t"]
		tp += t.size() / 3
		for i in range(0, t.size() - 2, 3):
			vol += v[t[i]].dot(v[t[i + 1]].cross(v[t[i + 2]])) / 6.0
		for p in v:
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	vol = absf(vol)
	var vp := absf(float(got["vol"]) - vol) / maxf(vol, 1e-9) * 100.0
	var sp := 0.0
	for k in 3:
		sp = maxf(sp, absf((got["size"] as Vector3)[k] - box.size[k]) / maxf(box.size[k], 1e-3) * 100.0)
	var ok := tp == int(got["tris"]) and vp <= TOL_PCT and sp <= TOL_PCT
	var sz: Vector3 = got["size"]
	var txt := "From the file on disk: %d triangles, %.1f x %.1f x %.1f mm, %.0f mm3. " % [int(got["tris"]), sz.x, sz.y, sz.z, float(got["vol"])]
	if ok:
		txt += "It matches the part (same triangles; size and volume within %.1f %%)." % TOL_PCT
	else:
		txt += "It does NOT match the part: %d triangles in the file against %d, volume %.1f %% off, size %.1f %% off (allowed %.1f %%). Export again before you print." % [int(got["tris"]), tp, vp, sp, TOL_PCT]
	return {"match": ok, "text": txt, "tris_part": tp, "tris_file": int(got["tris"]), "vol_pct": vp, "size_pct": sp}


# ---------------------------------------------------------------- the preview picture

static func mesh_of(soup: PackedVector3Array) -> ArrayMesh:
	var n := PackedVector3Array()
	var vs := PackedVector3Array()
	for i in range(0, soup.size() - 2, 3):
		var a := _g(soup[i])
		var b := _g(soup[i + 1])
		var c := _g(soup[i + 2])
		var nn := (b - a).cross(c - a).normalized()
		vs.append(a)
		vs.append(b)
		vs.append(c)
		n.append(nn)
		n.append(nn)
		n.append(nn)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## printer axes (mm, Z up) -> the preview world (Y up)
static func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


# ---------------------------------------------------------------- the dialog's part

## builds the Printer row, its words, and the re-read preview into v; returns the controls
static func build(dlg: Object, v: VBoxContainer) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = "export_printer_row"
	var l := Label.new()
	l.text = "Printer"
	row.add_child(l)
	var opt := OptionButton.new()
	opt.name = "opt_export_printer"
	opt.add_item("Any printer (usual gaps)")
	for p in C03.PRESETS:
		opt.add_item("%s  %s mm" % [p["name"], str(p["clear"])])
	opt.tooltip_text = "Your printer: the gap on each side that holes, lids, fasteners and print-in-place hinges keep. Saved for your next part."
	row.add_child(opt)
	row.visible = false
	v.add_child(row)
	var info := Label.new()
	info.name = "export_printer_info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	info.visible = false
	v.add_child(info)
	var box := VBoxContainer.new()
	box.name = "export_reread_box"
	var say := Label.new()
	say.name = "export_reread_text"
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.custom_minimum_size = Vector2(300, 0)
	box.add_child(say)
	var svc := SubViewportContainer.new()
	svc.name = "export_reread_preview"
	svc.stretch = true
	svc.custom_minimum_size = Vector2(320, 180)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.size = Vector2i(320, 180)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	box.add_child(svc)
	box.visible = false
	v.add_child(box)
	opt.item_selected.connect(func(i: int):
		var rec: Dictionary = dlg.m.S.part
		if not rec.is_empty() or i == 0:
			choose(rec, i)
		info.text = words(rec))
	return {"row": row, "opt": opt, "info": info, "box": box, "say": say, "sv": sv}


static func refresh(dlg: Object, c: Dictionary) -> void:
	if c.is_empty():
		return
	var on: bool = dlg._cur_id() == "print"
	(c["row"] as Control).visible = on
	(c["info"] as Control).visible = on
	if not on:
		(c["box"] as Control).visible = false
		return
	var rec: Dictionary = dlg.m.S.part
	(c["opt"] as OptionButton).select(item_of(rec))
	(c["info"] as Label).text = words(rec)


## called by the dialog when it opens
static func on_open(dlg: Object, c: Dictionary) -> void:
	if c.is_empty():
		return
	adopt_saved(dlg.m.S.part)
	(c["box"] as Control).visible = false


## after a print export: read the written file back, compare and draw it. r = the export's answer; bodies = the ones written
static func after_export(c: Dictionary, r: Dictionary, bodies: Array) -> Dictionary:
	if c.is_empty() or not bool(r.get("ok", false)):
		return {}
	var path := String(r["path"])
	var fmt := path.get_extension()
	if fmt != "stl" and fmt != "3mf":
		return {}
	var got := reread(path, fmt)
	var cmp := compare(bodies, got)
	(c["say"] as Label).text = String(cmp["text"])
	var sv := c["sv"] as SubViewport
	for ch in sv.get_children():
		sv.remove_child(ch)
		ch.queue_free()
	if bool(got.get("ok", false)):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh_of(got["v"])
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.78, 0.82, 0.9)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		sv.add_child(mi)
		var bb := mi.get_aabb()
		var ctr := bb.get_center()
		var rad := maxf(bb.size.length() * 0.5, 0.001)
		var cam := Camera3D.new()
		sv.add_child(cam)
		cam.look_at_from_position(ctr + Vector3(0.7, 0.6, 1.0).normalized() * rad * 2.6, ctr)
		var lt := DirectionalLight3D.new()
		sv.add_child(lt)
		lt.rotation_degrees = Vector3(-45, 35, 0)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.16, 0.17, 0.2)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.6, 0.65)
		var we := WorldEnvironment.new()
		we.environment = env
		sv.add_child(we)
	(c["box"] as Control).visible = true
	return cmp
