extends SceneTree
## godot --path . --position 4000,4000 -s tests/c23_test.gd     (C23: colour and units; needs the CAD DLL for part A)
## BARS, written before any number was read:
##  A  3MF COLOUR  a part with a red body and a blue body, written by the Export dialog and READ BACK from the zip: 2 objects, the distinct displaycolors are
##                 exactly #FF0000 and #0000FF, and each object's pindex resolves to its own body's colour. CONTROL: the same part unpainted reads back 0 colours.
##  A2 PICK        C23Colour.pick on the two-colour part = "3mf" with a why that says "2 colours"; an unpainted single body = "stl"; an explicit "stl" ask is honoured
##                 (CONTROL: that ask carries no why, so the "why says 2 colours" bar fails on it). The dialog's new third print format "auto" (the first two stay
##                 3mf, stl) writes a .3mf for the two-colour part and says why in the words; for the unpainted box it writes an .stl.
##                 The checklist for STL on the two-colour part carries a WARN naming 2 colours; for 3MF an OK; for the unpainted box neither.
##  B  FBX UNITS   combo3 as ASCII with a 1 m offset up (a rig at 1 m) under each preset: the root Null's translation x UnitScaleFactor / 100 reads 1.0 m within 1e-4;
##                 the offset lies on the declared up axis (Y for default/unity, Z for unreal/blender, header UpAxis 1 / 2). CONTROL: default's numbers read under
##                 unity's factor (100) read 100 m, not 1 m, so the 1 m bar fails on them. Default output = origin's (hash below, taken on origin before the edit).
##  C  GIF         a 480 x 64 gradient (60 levels a channel) encoded plain and dithered, decoded: the 4 x 4 box-mean error of the dithered is <= 0.5 x the plain one;
##                 the longest run of one colour on the middle row of the dithered is <= 1/3 of the plain one; the dithered file is <= 4 x the plain size.
##                 CONTROL: the plain file against itself fails both 0.5 and 1/3. Default (no dither) encode = origin's bytes (hash below).
##  D  UI          1280 x 720: the Smooth GIF button sits after Save GIF, hidden with no clip, inside the window with one; a real click writes <clip>_smooth.gif which decodes
##                 with every saved frame. Screenshot in out/c23/.
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c23"
const DIR := "user://zz_c23"
const HASH_FBX := "fe17b3f221bfb3a319e77f4c070e878880a679f67d87d0c7db48047d122fde0a"
const HASH_FBX2 := "da702891e67ff827d8ba4685beff48b083807fbe3a390e93d3f31bd493b8a89a"
const HASH_GIF := "18a8e2fdb79b1fd33a84007e3e8ece79122afd4cd21c41b9263c36a8925e834f"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _watchdog() -> void:   # an error after an await would leave the run hanging: say FAIL and leave
	await create_timer(600.0).timeout
	print("FAIL watchdog: the test did not finish in 600 s")
	quit(1)


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		if d:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(2)


func read_3mf(path: String) -> Dictionary:
	var out := {"objects": 0, "colors": [], "obj_pindex": [], "xml": ""}
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return out
	var model := z.read_file("3D/3dmodel.model")
	z.close()
	out["xml"] = model.get_string_from_utf8()
	var xp := XMLParser.new()
	xp.open_buffer(model)
	while xp.read() != ERR_FILE_EOF:
		if xp.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match xp.get_node_name():
			"object":
				out["objects"] += 1
				out["obj_pindex"].append(int(xp.get_named_attribute_value("pindex")) if xp.has_attribute("pindex") else -1)
			"base":
				out["colors"].append(xp.get_named_attribute_value_safe("displaycolor"))
	return out


func two_box(painted: bool) -> Dictionary:
	var rec := Part.make("Two boxes")
	var fs: Array = rec["features"]
	var s1 := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))])
	PartTemplates._ex(fs, s1, "extrude", 5.0, "new")
	var s2 := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(30, 0), Vector2(40, 10))])
	PartTemplates._ex(fs, s2, "extrude", 5.0, "new")
	if painted:
		fs.append({"t": "appear", "id": "f8", "name": "Paint1", "body": 0, "preset": "Paint", "color": [1.0, 0.0, 0.0], "rough": 0.5, "metal": 0.0, "alpha": 1.0})
		fs.append({"t": "appear", "id": "f9", "name": "Paint2", "body": 1, "preset": "Paint", "color": [0.0, 0.0, 1.0], "rough": 0.5, "metal": 0.0, "alpha": 1.0})
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


func part_a() -> void:
	if not Part.available():
		ok(false, "A the CAD DLL is not loaded: part A cannot run")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var ex := ExportDialog.new(m)
	var rec := two_box(true)
	m.S.part = rec
	var fmts: Array = ExportDialog.target("print")["formats"]
	ok(fmts.size() == 3 and fmts[0]["run"] == "3mf" and fmts[1]["run"] == "stl" and fmts[2]["run"] == "auto", "A2 print formats: 3mf, stl kept first, auto added third (%s)" % str(fmts.map(func(f): return f["run"])))
	# A: the default 3MF road (index 0), read back
	var p := String(ex.export_now("print", 0, DIR))
	var r := read_3mf(ProjectSettings.globalize_path(p)) if p != "" else {"objects": 0, "colors": [], "obj_pindex": []}
	var cols: Array = r["colors"]
	var pi: Array = r["obj_pindex"]
	var map_ok: bool = pi.size() == 2 and pi[0] >= 0 and pi[1] >= 0 and cols[pi[0]] == "#FF0000" and cols[pi[1]] == "#0000FF"
	ok(int(r["objects"]) == 2 and cols.size() == 2 and cols.has("#FF0000") and cols.has("#0000FF") and map_ok, "A 3MF read back: %d objects, colours %s, object pindex %s -> body 1 red, body 2 blue" % [int(r["objects"]), str(cols), str(pi)])
	# control: the unpainted part has no colours
	m.S.part = two_box(false)
	var pu := String(ex.export_now("print", 0, DIR))
	var ru := read_3mf(ProjectSettings.globalize_path(pu)) if pu != "" else {"colors": [1]}
	ok(not ((ru["colors"] as Array).size() == 2), "A CONTROL: the unpainted part reads back %d colours, so the 2-colour bar fails on it" % (ru["colors"] as Array).size())
	# A2: the pick
	m.S.part = rec
	var pk := C23Colour.pick(rec, {}, "auto")
	ok(pk["fmt"] == "3mf" and String(pk["why"]).contains("2 colours") and int(pk["colours"]) == 2, "A2 two colours -> %s: [%s]" % [pk["fmt"], pk["why"]])
	var pk0 := C23Colour.pick(Part.make("x"), {}, "auto")   # nothing built: no bodies
	var single := Part.make("One box")
	var sf: Array = single["features"]
	PartTemplates._ex(sf, PartTemplates._sk(sf, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))]), "extrude", 5.0, "new")
	single["seq"] = sf.size()
	single["kept"] = true
	var pk1 := C23Colour.pick(single, {}, "auto")
	ok(pk1["fmt"] == "stl" and int(pk1["colours"]) == 0, "A2 one unpainted body -> %s, %d colours (pk0 on an empty part: %s)" % [pk1["fmt"], int(pk1["colours"]), pk0["fmt"]])
	var pks := C23Colour.pick(rec, {}, "stl")
	ok(pks["fmt"] == "stl", "A2 an explicit STL ask is honoured")
	ok(not String(pks["why"]).contains("2 colours"), "A2 CONTROL: the explicit STL ask carries no 'why', so the why bar fails on it")
	# the dialog's auto road writes the right file and says why
	var said := []
	var pa := String(ex.export_now("print", 2, DIR))
	ok(pa.ends_with(".3mf") and FileAccess.file_exists(ProjectSettings.globalize_path(pa)), "A2 dialog auto on the two-colour part wrote %s" % pa.get_file())
	m.S.part = single
	var pb := String(ex.export_now("print", 2, DIR))
	ok(pb.ends_with(".stl"), "A2 dialog auto on the unpainted box wrote %s" % pb.get_file())
	m.S.part = rec
	var l_stl := "\n".join(ex.checks("print", "stl"))
	var l_3mf := "\n".join(ex.checks("print", "3mf"))
	ok(l_stl.contains("WARN  this part has 2 colours and an STL holds none"), "A2 the STL checklist warns about 2 colours")
	ok(l_3mf.contains("OK    2 colours: the 3MF keeps"), "A2 the 3MF checklist says the colours are kept")
	m.S.part = single
	ok(not "\n".join(ex.checks("print", "stl")).contains("colours"), "A2 CONTROL: the unpainted box's checklist has no colour line")
	m.S.part = rec
	# picture of the dialog on the Best-for-my-part format
	ex.open()
	await idle(4)
	ex.ui_format.select(2)
	ex._refresh()
	await idle(6)
	root.get_texture().get_image().save_png(SHOT.path_join("dialog_1280x720.png"))
	var chk := ex.ui_checks.text
	ok(chk.contains("2 colours"), "A2 the open dialog on 'Best for my part' lists the colours in its checklist")
	ex.dlg.hide()
	m.S.part = {}


## the root Null's translation and the header, from the ASCII text
func fbx_facts(t: String) -> Dictionary:
	var f := 0.0
	var up := -1
	for line in t.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("P: \"UnitScaleFactor\""):
			f = float(l.get_slice(",", l.get_slice_count(",") - 1))
		if l.begins_with("P: \"UpAxis\""):
			up = int(l.get_slice(",", l.get_slice_count(",") - 1))
	var i := t.find("Model::cube")
	var tr := Vector3.ZERO
	if i >= 0:
		var k := t.find("\"Lcl Translation\"", i)
		var seg := t.substr(k, t.find("\n", k) - k).split(",")
		tr = Vector3(float(seg[seg.size() - 3]), float(seg[seg.size() - 2]), float(seg[seg.size() - 1]))
	return {"factor": f, "up": up, "t": tr}


func part_b() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var plain := FbxExport.write(S, B, DIR + "/p.fbx", false, Transform3D.IDENTITY, "", true)["text"] as String
	var h1 := (plain.substr(0, plain.find("CreationTimeStamp")) + plain.substr(plain.find("Creator:"))).sha256_text()
	var t2 := FbxExport.write(S, B, DIR + "/p2.fbx", false, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), "cube", true)["text"] as String
	var h2 := (t2.substr(0, t2.find("CreationTimeStamp")) + t2.substr(t2.find("Creator:"))).sha256_text()
	ok(h1 == HASH_FBX and h2 == HASH_FBX2, "B default FBX output unchanged: %s / %s" % [h1.left(12), h2.left(12)])
	var plain_facts := {}
	for pr in ["default", "unity", "unreal", "blender"]:
		var r := FbxExport.write_preset(pr, S, B, "%s/%s.fbx" % [DIR, pr], false, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), "cube", true)
		var fa := fbx_facts(r["text"])
		var tv: Vector3 = fa["t"]
		var metres := tv.length() * float(fa["factor"]) / 100.0
		var zup: bool = PackedStringArray(["unreal", "blender"]).has(pr)
		var on_up: bool = (absf(tv.z) > 0.99 * tv.length() and absf(tv.x) + absf(tv.y) < 1e-3 * tv.length()) if zup else (absf(tv.y) > 0.99 * tv.length() and absf(tv.x) + absf(tv.z) < 1e-3 * tv.length())
		ok(r["err"] == OK and absf(metres - 1.0) < 1e-4 and on_up and int(fa["up"]) == (2 if zup else 1), "B %s: 1 m up reads %.5f m (translation %s x factor %s / 100), up axis %d" % [pr, metres, str(tv), str(fa["factor"]), int(fa["up"])])
		if pr == "default":
			plain_facts = fa
	var wrong := (plain_facts["t"] as Vector3).length() * 100.0 / 100.0   # default's numbers under unity's factor 100
	ok(not (absf(wrong - 1.0) < 1e-4), "B CONTROL: default's numbers read under unity's factor give %.1f m, so the 1 m bar fails" % wrong)
	var bad := FbxExport.write_preset("nope", S, B, DIR + "/n.fbx")
	ok(bad["err"] == ERR_INVALID_PARAMETER and FbxExport.unit_mult == 100.0 and not FbxExport.up_z, "B an unknown preset is refused and the statics stay at the old file's")


func gradient() -> Image:
	var im := Image.create(480, 64, false, Image.FORMAT_RGB8)
	for x in 480:
		var v := x / 8   # 0..59
		for y in 64:
			im.set_pixel(x, y, Color8(40 + v, 50 + v, 90 + v))
	return im


func box_err(src: Image, dec: PackedByteArray, w: int, h: int) -> float:
	var tot := 0.0
	var n := 0
	for by in range(0, h - 3, 4):
		for bx in range(0, w - 3, 4):
			for c in 3:
				var a := 0.0
				var b := 0.0
				for dy in 4:
					for dx in 4:
						a += src.get_pixel(bx + dx, by + dy)[c] * 255.0
						b += dec[((by + dy) * w + bx + dx) * 3 + c]
				tot += absf(a - b) / 16.0
				n += 1
	return tot / n


func longest_run(dec: PackedByteArray, w: int, y: int) -> int:
	var best := 1
	var cur := 1
	for x in range(1, w):
		var i := (y * w + x) * 3
		var j := i - 3
		if dec[i] == dec[j] and dec[i + 1] == dec[j + 1] and dec[i + 2] == dec[j + 2]:
			cur += 1
			best = maxi(best, cur)
		else:
			cur = 1
	return best


func part_c() -> void:
	var g := gradient()
	var plain: PackedByteArray = await GifWriter.encode([g, g], 12)
	var dith: PackedByteArray = await GifWriter.encode([g, g], 12, 0, false, Callable(), true)
	var dp := GifWriter.decode(plain)
	var dd := GifWriter.decode(dith)
	ok(not dp.is_empty() and not dd.is_empty() and (dd["frames"] as Array).size() == 2, "C both decode, dithered has 2 frames")
	var ep := box_err(g, (dp["frames"] as Array)[0], 480, 64)
	var ed := box_err(g, (dd["frames"] as Array)[0], 480, 64)
	var rp := longest_run((dp["frames"] as Array)[0], 480, 32)
	var rd := longest_run((dd["frames"] as Array)[0], 480, 32)
	print("C box error plain %.3f dithered %.3f; longest run plain %d dithered %d; bytes %d / %d" % [ep, ed, rp, rd, plain.size(), dith.size()])
	ok(ed <= ep * 0.5, "C dithered 4x4 box-mean error %.3f <= half the plain %.3f" % [ed, ep])
	ok(rd * 3 <= rp, "C longest one-colour run on the middle row %d <= a third of the plain %d" % [rd, rp])
	ok(dith.size() <= plain.size() * 4, "C dithered file %d <= 4 x plain %d" % [dith.size(), plain.size()])
	ok(not (ep <= ep * 0.5) and not (rp * 3 <= rp), "C CONTROL: the plain file against itself fails both bars")
	var im := Image.create(96, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 96:
			im.set_pixel(x, y, Color8(40 + x / 2, 50 + x / 2 + y, 90 + x / 2))
	var gb: PackedByteArray = await GifWriter.encode([im, im], 12)
	ok(gb.hex_encode().sha256_text() == HASH_GIF, "C default GIF bytes unchanged from origin")


func part_d() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(10)
	m._new_scene()
	await idle(2)
	m.easy.set_on(true, false)
	await idle(3)
	var home: EasyHome = m.easy.home
	var sb: Button = m.easy.gif_smooth_button
	var gb: Button = m.easy.gif_button
	ok(sb != null and not sb.visible, "D no clip: Smooth GIF is hidden")
	ok(sb != null and gb != null and sb.get_index() == gb.get_index() + 1, "D Smooth GIF sits right after Save GIF")
	home.video_root = ProjectSettings.globalize_path("user://c23_ui")
	DirAccess.make_dir_recursive_absolute(home.video_root)
	var c0 := home.panel.find_child("eh_card_0", true, false) as Button
	c0.pressed.emit()
	await idle(6)
	ok(sb.visible and root.get_visible_rect().encloses(sb.get_global_rect()) and root.get_visible_rect().encloses(gb.get_global_rect()), "D with a clip both GIF buttons show inside 1280 x 720 (%s)" % str(sb.get_global_rect()))
	await idle(8)
	root.get_texture().get_image().save_png(SHOT.path_join("bar_1280x720.png"))
	await click(sb)
	var tries := 0
	while String(home.last_gif) == "" and tries < 1500:
		await idle(2)
		tries += 1
	var lg := String(home.last_gif)
	ok(lg.ends_with("_smooth.gif") and FileAccess.file_exists(lg), "D a click on Smooth GIF wrote %s" % lg.get_file())
	if lg != "":
		var d := GifWriter.decode(FileAccess.get_file_as_bytes(lg))
		var npng := 0
		for n in DirAccess.get_files_at(String(home.last_video["dir"])):
			if String(n).ends_with(".png"):
				npng += 1
		ok(not d.is_empty() and (d["frames"] as Array).size() == npng and npng > 1, "D the smooth GIF has every saved frame (%d of %d)" % [(d["frames"] as Array).size() if not d.is_empty() else 0, npng])
	home.video_root = ""


func _init() -> void:
	_watchdog()
	DirAccess.make_dir_recursive_absolute(SHOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	await part_a()
	part_b()
	await part_c()
	await part_d()
	print("C23 DONE fails=", fails)
	quit(1 if fails > 0 else 0)
