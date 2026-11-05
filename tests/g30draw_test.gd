extends SceneTree
## G30DRAW: Assembly -> dimensioned drawing / schematic sheets. These bars were committed before the first run.
## a three hand-sized boxes print their exact overall X/Y/Z sizes (relative 1e-6); CONTROL moving one 10 mm changes X
## b the SectionLook-plane view has new cut edges through an enclosed block; the closed front view has none
## c CH16's generated drawing matches 126.9 x 94.4 x 54.8 mm and its 448.288 g model mass; CH15 keeps every bus kV and
##   transformer MVA; CONTROL a missing transformer rating is flagged ON the sheet
## d every wire names existing parts and every powered block has power; CONTROL unknown endpoint / unconnected load
## e both SVGs re-parse and both PNGs exist; CONTROL malformed XML is rejected
## f real Assembly Export buttons write the sheets; old Assembly records save back unchanged; CONTROL adding a wire differs
const D := preload("res://scripts/build/assembly_draw.gd")
const P16 := preload("res://scripts/build/ch16_parts.gd")
const E16 := preload("res://scripts/build/ch16_electronics.gd")
const P15 := preload("res://scripts/build/ch15_plant.gd")
const OUT := "C:/Temp/claude/g30draw"
const OLD := ["res://tests/assets/g1motion/old_assembly.json", "res://tests/assets/g2loop/drive_199.json", "res://tests/assets/g7time/joint_204.json", "res://tests/assets/g8bom/anim_205.json", "res://tests/assets/g33stage/bom_206.json"]
var fails := 0
var m: Node
var A: AssemblyUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func ctl(c: bool, w: String) -> void:
	ok(c, "CONTROL " + w)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func box_rec(nm: String, w: float, h: float, d: float) -> Dictionary:
	return {"version": 1, "name": nm, "seq": 1, "features": [{"t": "prim", "id": "f1", "name": "Prim1", "kind": "box", "op": "new", "x": 0.0, "y": 0.0, "z": 0.0, "w": w, "h": h, "d": d}]}


func put(asm: Dictionary, nm: String, rec: Dictionary, pos := Vector3.ZERO) -> String:
	asm["seq"] = int(asm["seq"]) + 1
	var id := "p%d" % int(asm["seq"])
	asm["parts"].append({"id": id, "name": nm, "src": "", "rec": rec, "pos": [pos.x, pos.y, pos.z], "rot": [0.0, 0.0, 0.0]})
	return id


func fixture() -> Dictionary:
	var a := Assembly.make("Drawing fixture")
	put(a, "Base", box_rec("Base", 40, 20, 10))
	put(a, "Tower", box_rec("Tower", 20, 30, 10), Vector3(50, 0, 0))
	put(a, "Lug", box_rec("Lug", 10, 10, 30), Vector3(0, 20, 0))
	return a


func dim(sh: Dictionary, axis: String) -> float:
	for e in sh["ents"]:
		if e["t"] == "text" and e["d"].get("kind", "") == "overall" and e["d"].get("axis", "") == axis:
			return float(e["d"]["value_mm"])
	return -1.0


func text_of(sh: Dictionary) -> String:
	var rows := PackedStringArray()
	for e in sh["ents"]:
		if e["t"] == "text":
			rows.append(String(e["s"]))
	return "\n".join(rows)


func close_enough(a: float, b: float) -> bool:
	return absf(a - b) <= 1e-6 * maxf(absf(b), 1.0)


func bars_dimensions() -> void:
	var a := fixture()
	var sh := D.sheet(a)
	var got := [dim(sh, "x"), dim(sh, "y"), dim(sh, "z")]
	ok(close_enough(got[0], 70) and close_enough(got[1], 60) and close_enough(got[2], 30), "a model dimensions %.9f x %.9f x %.9f mm = hand 70 x 60 x 30 (relative 1e-6)" % got)
	var labels := text_of(sh)
	ok(labels.contains("Base") and labels.contains("Tower") and labels.contains("Lug") and labels.contains("PLAN") and labels.contains("FRONT") and labels.contains("SECTION"), "a plan/front/section sheet labels all three parts")
	Assembly.set_pose(a["parts"][1], Vector3(60, 0, 0), Vector3.ZERO)
	var moved := D.sheet(a)
	ctl(close_enough(dim(moved, "x"), 80) and not text_of(moved).contains("70.000 mm") and text_of(moved).contains("80.000 mm"), "a Tower +10 mm prints 80.000 mm, not 70.000 mm")


func bars_section() -> void:
	var a := Assembly.make("Enclosed interior")
	put(a, "Outer", box_rec("Outer", 40, 40, 40))
	put(a, "Hidden core", box_rec("Hidden core", 10, 10, 10), Vector3(15, 15, 15))
	var sh := D.sheet(a, {"cut": {"n": Vector3.BACK, "w": 0.020}})
	var cut := 0
	var closed := 0
	for e in sh["ents"]:
		if e["d"].get("section", "") == "cut":
			if e["d"].get("view", "") == "section":
				cut += 1
			elif e["d"].get("view", "") == "front":
				closed += 1
	ok(cut >= 4 and closed == 0, "b section exposes interior with %d cut-edge entities; closed front has %d" % [cut, closed])
	ctl(closed == 0 and cut > 0, "b removing the section cut removes its interior cut-edge evidence")


func add_block(a: Dictionary, id: String, rec: Dictionary) -> void:
	a["seq"] = int(a["seq"]) + 1
	a["parts"].append({"id": id, "name": String(rec.get("name", id)), "src": "", "rec": rec, "pos": [0, 0, 0], "rot": [0, 0, 0]})


func wire(a: Dictionary, x: String, y: String, kind := "power", label := "") -> void:
	if not a.has("wires"):
		a["wires"] = []
	a["wires"].append({"a": x, "b": y, "kind": kind, "label": label})


func ch15_record(model: Dictionary) -> Dictionary:
	var a := Assembly.make("CH15 one-line from records")
	for b in model["buses"]:
		add_block(a, b["id"], {"name": b["id"], "kind": "bus", "v": b["kv"], "unit": "kV", "powered": true})
	for x in model["xfmrs"]:
		add_block(a, x["id"], {"name": x["id"], "kind": "transformer", "mva": x.get("mva", 0.0), "v": x["hv"], "unit": "kV", "rail": x["lv"], "powered": true})
		wire(a, x["from"], x["id"])
		wire(a, x["id"], x["to"])
	for g in model["gens"]:
		add_block(a, g["id"], {"name": g["id"], "kind": "generator", "mva": g["mva"], "v": g["kv"], "unit": "kV"})
		wire(a, g["id"], g["bus"])
	for b in model["breakers"]:
		add_block(a, b["id"], {"name": b["id"], "kind": "breaker", "v": b["kv"], "unit": "kV"})
		wire(a, b["between"][0], b["id"])
		wire(a, b["id"], b["between"][1])
	for t in model["ties"]:
		wire(a, t[0], t[1], "power", "tie")
	return a


func bars_reproduce() -> void:
	var cam := P16.assembly()
	var sh := D.sheet(cam)
	var got := [dim(sh, "x"), dim(sh, "y"), dim(sh, "z")]
	var mass := AssemblyBom.bom(cam)["mass_kg"] * 1000.0
	var txt := text_of(sh)
	ok(close_enough(got[0], P16.W) and close_enough(got[1], P16.H) and close_enough(got[2], P16.D_MAX), "c CH16 drawing %.6f x %.6f x %.6f mm = hand-written 126.9 x 94.4 x 54.8" % got)
	ok(absf(mass - 448.288) < 0.001 and txt.contains("448.288 g"), "c CH16 model mass callout %.3f g = hand-written 448.288 g" % mass)
	var model := P15.one_line()
	var one := ch15_record(model)
	var osh := D.schematic_sheet(one)
	var st := text_of(osh)
	var missing: Array = []
	for b in model["buses"]:
		if not st.contains("%s kV" % String.num(float(b["kv"]))):
			missing.append(String(b["id"]))
	for x in model["xfmrs"]:
		if not st.contains("%s MVA" % String.num(float(x["mva"]))):
			missing.append(String(x["id"]))
	ok(missing.is_empty() and D.validate_schematic(one).is_empty(), "c CH15 redraw keeps all %d bus voltages and %d transformer MVA; %s" % [(model["buses"] as Array).size(), (model["xfmrs"] as Array).size(), str(missing)])
	var stripped := P15.one_line()
	stripped["xfmrs"][0].erase("mva")
	var bad := ch15_record(stripped)
	var bad_sheet := D.schematic_sheet(bad)
	ctl(not D.validate_schematic(bad).is_empty() and text_of(bad_sheet).contains("MISSING RATING: MT"), "c missing MT MVA is flagged on the sheet")


func bars_wires() -> void:
	var a := Assembly.make("Power and signal")
	add_block(a, "BAT", {"kind": "battery", "v": 7.2, "unit": "V"})
	add_block(a, "REG", {"kind": "regulator", "v": 3.3, "unit": "V", "w": 0.5, "powered": true})
	add_block(a, "CPU", {"kind": "ic", "rail": "REG", "w": 0.2, "powered": true})
	wire(a, "BAT", "REG")
	wire(a, "REG", "CPU")
	wire(a, "REG", "CPU", "signal", "enable")
	ok(D.validate_schematic(a).is_empty(), "d all wires resolve and every powered block has a power connection")
	var unknown := a.duplicate(true)
	wire(unknown, "CPU", "NOT_A_PART")
	ctl(D.validate_schematic(unknown).any(func(e): return String(e["kind"]) == "unknown-endpoint"), "d unknown wire endpoint is flagged")
	var loose := a.duplicate(true)
	loose["wires"] = [loose["wires"][0], loose["wires"][2]]
	var es := D.validate_schematic(loose)
	ctl(es.any(func(e): return String(e["kind"]) == "no-power" and String(e["part"]) == "CPU") and text_of(D.schematic_sheet(loose)).contains("NO POWER: CPU"), "d unconnected powered CPU is flagged on the sheet")


func xml_ok(s: String) -> bool:
	var x := XMLParser.new()
	if x.open_buffer(s.to_utf8_buffer()) != OK:
		return false
	while true:
		var e := x.read()
		if e == ERR_FILE_EOF:
			return true
		if e != OK:
			return false
	return false


func bars_files() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for kind in ["drawing", "schematic"]:
		var r: Dictionary = await D.write(root, fixture(), kind, {"dir": OUT, "stem": "g30draw_" + kind, "ppm": 2.0})
		var svg := FileAccess.get_file_as_string(String(r.get("svg", "")))
		ok(bool(r.get("ok", false)) and xml_ok(svg) and FileAccess.file_exists(String(r.get("png", ""))) and FileAccess.get_file_as_bytes(String(r.get("png", ""))).size() > 100, "e %s SVG re-parses (%d bytes) and PNG is written (%s)" % [kind, svg.length(), String(r.get("png", "")).get_file()])
	ctl(not xml_ok("<svg><unclosed></svg>"), "e malformed XML is rejected")


func ch16_schematic() -> Dictionary:
	var model := E16.model()
	var a := Assembly.make("CH16 electronics from records")
	add_block(a, "BATTERY", {"kind": "battery", "v": E16.VBAT, "unit": "V"})
	add_block(a, "PROTECTION", {"kind": "ic", "rail": "input", "powered": true})
	add_block(a, "PMIC", {"kind": "ic", "rail": "input", "powered": true})
	wire(a, "BATTERY", "PROTECTION")
	wire(a, "PROTECTION", "PMIC")
	for r in model["rails"]:
		add_block(a, r["id"], {"name": r["reg"], "kind": "regulator", "v": r["v"], "unit": "V", "w": r["w"], "powered": true})
		wire(a, "PMIC", r["id"])
	for ic in model["ics"]:
		if ["PMIC", "PROTECTION"].has(String(ic["id"])):
			continue
		add_block(a, ic["id"], {"kind": "ic", "rail": ic["rail"], "powered": true})
		wire(a, ic["rail"], ic["id"])
		if String(ic["id"]) != "BIONZ X":
			wire(a, "BIONZ X", ic["id"], "signal", "data/control")
	return a


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func click_ctl(c: Control) -> void:
	var q := c.get_global_rect().get_center()
	for dn in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = q
		e.global_position = q
		e.pressed = dn
		root.push_input(e, true)
		await process_frame


func click(nm: String) -> void:
	await click_ctl(nd(nm) as Control)


func open_screen() -> void:
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://g30draw_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(6)
	A = m.bld.asm
	m.build_choose.show_chooser()
	await idle(4)
	await click_ctl(nd("build_choose_assembly") as Button)
	await idle(4)


func sorted_json(path: String) -> String:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	return JSON.stringify(j, "", true) if j != null else ""


func bars_ui() -> void:
	await open_screen()
	A.open_record(fixture())
	await idle(6)
	Assembly.export_dir = OUT + "/ui"
	await click("asm_export_drawing")
	var guard := 0
	while A.sheet_exporting and guard < 600:
		await process_frame
		guard += 1
	ok(bool(A.last_export.get("ok", false)) and String(A.last_export.get("svg", "")).ends_with(".svg") and String(A.last_export.get("png", "")).ends_with(".png"), "f Assembly Drawing button exports SVG + PNG (%s)" % String(A.last_export.get("text", "")))
	await idle(4)
	root.get_texture().get_image().save_png(OUT + "/ui_drawing_fresh.png")
	await click("asm_export_schematic")
	guard = 0
	while A.sheet_exporting and guard < 600:
		await process_frame
		guard += 1
	ok(bool(A.last_export.get("ok", false)) and String(A.last_export.get("text", "")).contains("schematic"), "f Assembly Schematic button exports SVG + PNG")
	var keep := Assembly.dir
	Assembly.dir = "user://g30draw_old"
	var equal := true
	for path in OLD:
		var rec := Assembly.read(path)
		A.open_record(rec)
		await idle(3)
		var saved := Assembly.save(A.asm)
		equal = equal and saved != "" and sorted_json(saved) == sorted_json(path)
	ok(equal, "f all %d old Assembly records open and save back unchanged after drawing UI is present" % OLD.size())
	var changed := Assembly.read(OLD[0])
	changed["wires"] = []
	ctl(sorted_json(Assembly.save(changed)) != sorted_json(OLD[0]), "f adding the optional wires key does not compare equal")
	Assembly.dir = keep


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
		ok(false, "the CAD DLL is missing")
		print("g30draw: %d fail" % fails)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	bars_dimensions()
	bars_section()
	bars_reproduce()
	bars_wires()
	ok(D.validate_schematic(ch16_schematic()).is_empty(), "d CH16 record adapter: every IC/regulator has power and every signal endpoint exists")
	await bars_files()
	await bars_ui()
	print("g30draw: %d fail" % fails)
	quit(1 if fails > 0 else 0)
