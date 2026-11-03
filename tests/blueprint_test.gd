extends SceneTree
## godot --path . --position 4000,4000 -s tests/blueprint_test.gd     (BUILD phase 1g: BLUEPRINTS; scripts/build/blueprint.gd, blueprint_ui.gd, blueprint_view.gd; needs a window)
## Bars, written before measuring (the 8 x 6 m, 2-floor house: 1 door, 4 windows, stairs, gable roof):
##   1 SVG      every tab's SVG parses (XMLParser, no error), 1 user unit = 1 mm, the paper size in mm
##   2 FIT      the scale is 1:50 or 1:100, the paper A3 or A4, and every sheet's drawing lies inside the border above the title block
##   3 WALLS    Floor 1 and 2: each wall's poche segments + its openings' widths = the record's wall length within 1 mm on the paper;
##              the wall is 0.2 m x scale thick; the door's gap is 0.9 m x scale
##   4 OPENINGS each of the 5 openings appears exactly ONCE across the plans with its width dimension (2 decimals); the overall
##              dimensions are 8.00 and 6.00; the chain segments of a front wall add up to its length
##   5 SYMBOLS  the door arc's radius = the door's width x scale and its leaf is that long; a window is three lines; stairs = 15 tread
##              outlines + an arrow + UP on Floor 1, dashed on Floor 2; the north arrow and the title block (name, scale, date, Kine)
##   6 ELEV     Front: 1 door + 2 windows, Side: 1 window; the roof silhouette's top = the roof solid's top; the overall height says so
##   7 DXF      re-read: the same number of LINE (polygons edges included) and ARC entities, TEXT present, R12 sections
##   8 UI       real clicks: Blueprint greyed with no rooms; with the house, a click opens the sheet, 4 tabs, a tab click switches the sheet,
##              Export SVG / DXF / PNG each write ONE file under user://blueprint_test; the PNG is 3508 x 2480 (A4, the paper this house fits at 1:50, 300 dpi), not blank;
##              Close hides the sheet
## Screenshots: C:/Temp/claude/build1g/plan.png and elev.png. Only user:// is written.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/build1g"
const DIRT := "user://blueprint_test"


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
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


## navigation only (5c735d53 freebuild: the BUILDING card opens a free Easy Part, so the house comes from the chooser, as in buildwords_test)
func to_house() -> void:
	await click_ctl(m.bld.part.reopen_btn)
	await idle(6)
	await click_ctl(m.build_choose.btns["house"]["expert"])
	m.bld.reset_view()
	await idle(10)


func house() -> Dictionary:
	var b := Building.make("Bay house")
	Building.add_room(b, 0, 0, 8, 6)
	Building.add_floor(b)
	Building.add_opening(b, "r1", "front", "door", 0.0)           # o1
	Building.add_opening(b, "r2", "front", "window", -2.0)        # o2
	Building.add_opening(b, "r2", "front", "window", 2.0)         # o3
	Building.add_opening(b, "r1", "left", "window", 0.0)          # o4
	Building.add_opening(b, "r1", "right", "window", 0.0)         # o5
	Building.set_roof(b, "gable")
	Building.add_piece(b, "stairs", 1.0, 3.0, 0.0, 0)
	return b


## the SVG's elements: [{"n": name, "a": {attr: value}, "text": String}]
func parse_svg(s: String) -> Dictionary:
	var xp := XMLParser.new()
	if xp.open_buffer(s.to_utf8_buffer()) != OK:
		return {"err": true, "els": []}
	var els := []
	var cur := {}
	var err := false
	while true:
		var r := xp.read()
		if r == ERR_FILE_EOF:
			break
		if r != OK:
			err = true
			break
		match xp.get_node_type():
			XMLParser.NODE_ELEMENT:
				var a := {}
				for i in xp.get_attribute_count():
					a[xp.get_attribute_name(i)] = xp.get_attribute_value(i)
				cur = {"n": xp.get_node_name(), "a": a, "text": ""}
				els.append(cur)
			XMLParser.NODE_TEXT:
				if not cur.is_empty():
					cur["text"] = String(cur["text"]) + xp.get_node_data()
	return {"err": err, "els": els}


func by_cls(P: Dictionary, cls: String) -> Array:
	return P["els"].filter(func(e): return String(e["a"].get("class", "")) == cls)


func pts_of(e: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for tok in String(e["a"]["points"]).split(" ", false):
		out.append(Vector2(float(tok.get_slice(",", 0)), float(tok.get_slice(",", 1))))
	return out


func span(e: Dictionary) -> Vector2:
	var p := pts_of(e)
	var lo := p[0]
	var hi := p[0]
	for v in p:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	return hi - lo


func texts(P: Dictionary, cls: String, data_key: String, data_val: String) -> Array:
	return by_cls(P, cls).filter(func(e): return String(e["a"].get("data-" + data_key, "")) == data_val)


func _init() -> void:
	Blueprint.dir = DIRT
	var b := house()
	var tabs := Blueprint.tabs(b)
	ok(tabs == ["Floor 1", "Floor 2", "Front", "Side"], "0 tabs: %s" % [tabs])
	var pick := Blueprint.choose(b)
	var svgs := {}
	var P := {}
	var sheets := {}
	for t in tabs:
		sheets[t] = Blueprint.sheet(b, t, pick)
		svgs[t] = Blueprint.to_svg(sheets[t])
		P[t] = parse_svg(svgs[t])
	# ---- 1 SVG
	var all_ok := true
	for t in tabs:
		var svg: Dictionary = P[t]["els"][0] if not P[t]["els"].is_empty() else {"a": {}}
		all_ok = all_ok and not P[t]["err"] and svg["a"].get("width", "") == "%smm" % Blueprint._n(sheets[t]["w"]) and svg["a"].get("viewBox", "") == "0 0 %s %s" % [Blueprint._n(sheets[t]["w"]), Blueprint._n(sheets[t]["h"])] and P[t]["els"].size() > 40
	ok(all_ok, "1 all 4 SVGs parse; width/height in mm = viewBox units (%d elements on Floor 1)" % P["Floor 1"]["els"].size())
	# ---- 2 FIT
	var k: float = sheets["Floor 1"]["k"]
	ok(int(pick["denom"]) in [50, 100] and String(pick["paper"]) in ["A3", "A4"], "2 scale 1:%d on %s" % [int(pick["denom"]), pick["paper"]])
	var fit := true
	for t in tabs:
		var content := Blueprint._bounds(sheets[t]["ents"].filter(func(e): return not (String(e["cls"]) in ["border", "title", "title-label", "title-text"])))
		var ar: Rect2 = sheets[t]["area"]
		fit = fit and ar.grow(0.01).encloses(content) and sheets[t]["paper"] == pick["paper"] and sheets[t]["denom"] == pick["denom"]
		print("     %s content %s inside %s" % [t, content, ar])
	ok(fit, "2 every sheet's drawing is inside the border, above the title block, one scale for the set")
	# ---- 3 WALLS
	var rec := {"r1": {"front": 8.0, "back": 8.0, "left": 5.6, "right": 5.6}, "r2": {"front": 8.0, "back": 8.0, "left": 5.6, "right": 5.6}}
	var walls_ok := true
	var thick_ok := true
	var gap_ok := true
	for t in ["Floor 1", "Floor 2"]:
		var storey := 0 if t == "Floor 1" else 1
		var rid := "r1" if storey == 0 else "r2"
		for wid in ["front", "back", "left", "right"]:
			var segs := by_cls(P[t], "wall").filter(func(e): return e["a"]["data-room"] == rid and e["a"]["data-wall"] == wid)
			var len_mm := 0.0
			for sgm in segs:
				var sp := span(sgm)
				len_mm += maxf(sp.x, sp.y)
				thick_ok = thick_ok and absf(minf(sp.x, sp.y) - 0.2 * k) < 0.01
			var open_mm := 0.0
			for o in b["openings"]:
				if o["room"] == rid and o["wall"] == wid:
					open_mm += Building.num(b, o["w"]) * k
			var want: float = rec[rid][wid] * k
			var okw := absf(len_mm + open_mm - want) <= 1.0
			walls_ok = walls_ok and okw
			if not okw:
				print("     %s %s: %.3f + %.3f vs %.3f mm" % [t, wid, len_mm, open_mm, want])
		var fw := by_cls(P[t], "wall").filter(func(e): return e["a"]["data-room"] == rid and e["a"]["data-wall"] == "front")
		if storey == 0:
			fw.sort_custom(func(p, q): return pts_of(p)[0].x < pts_of(q)[0].x)
			gap_ok = fw.size() == 2 and absf((pts_of(fw[1])[0].x - pts_of(fw[0])[1].x) - 0.9 * k) < 0.01
	ok(walls_ok, "3 every wall of both floors: segments + openings = the record's length, within 1 mm on the paper (scale %s mm per m)" % k)
	ok(thick_ok and gap_ok, "3 walls are 0.2 m x scale thick; the front door's gap is 0.9 m x scale (2 segments)")
	# ---- 4 OPENINGS
	var seen := {}
	var dims_ok := true
	for t in ["Floor 1", "Floor 2"]:
		for e in by_cls(P[t], "dim-text"):
			if e["a"].get("data-kind", "") == "width":
				var id: String = e["a"]["data-id"]
				seen[id] = int(seen.get(id, 0)) + 1
				var o: Dictionary = {}
				for oo in b["openings"]:
					if oo["id"] == id:
						o = oo
				dims_ok = dims_ok and e["text"] == "%.2f" % Building.num(b, o["w"])
	ok(seen.size() == 5 and seen.values().all(func(n): return n == 1), "4 each of the 5 openings has exactly one width dimension across the plans: %s" % [seen])
	ok(dims_ok, "4 every width dimension says the opening's width (door 0.90, windows 1.20)")
	var ov := by_cls(P["Floor 1"], "dim-text").filter(func(e): return e["a"].get("data-kind", "") == "overall").map(func(e): return e["text"])
	ok(ov == ["8.00", "6.00"], "4 overall dimensions: %s" % [ov])
	var chain := 0.0
	for e in by_cls(P["Floor 1"], "dim-text"):
		if e["a"].get("data-wall", "") == "front" and e["a"].get("data-kind", "") in ["width", "gap"]:
			chain += float(e["text"])
	ok(absf(chain - 8.0) < 0.02, "4 the front wall's dimension chain adds up to 8.00 (%.2f): corner, door, corner" % chain)
	# ---- 5 SYMBOLS
	var arcs := by_cls(P["Floor 1"], "door-arc")
	var leaf := by_cls(P["Floor 1"], "door-leaf")
	var arc_ok := arcs.size() == 1 and leaf.size() == 1 and absf(float(arcs[0]["a"]["data-r"]) - 0.9 * k) < 0.002
	if arc_ok:
		var d: String = arcs[0]["a"]["d"]   # M x y A r r 0 large sweep x y
		var tk := d.split(" ")
		var sp := Vector2(float(tk[1]), float(tk[2]))
		var ep := Vector2(float(tk[tk.size() - 2]), float(tk[tk.size() - 1]))
		var la: Dictionary = leaf[0]["a"]
		var l1 := Vector2(float(la["x1"]), float(la["y1"]))
		var l2 := Vector2(float(la["x2"]), float(la["y2"]))
		arc_ok = absf(l1.distance_to(l2) - 0.9 * k) < 0.002 and sp.distance_to(l2) < 0.01 and absf(sp.distance_to(ep) - 0.9 * k * sqrt(2.0)) < 0.01
	ok(arc_ok, "5 the door's swing arc has radius 0.9 m x scale = %.3f mm, a quarter turn, and its leaf is that long" % (0.9 * k))
	var wl_ok := true
	for id in ["o4", "o5"]:
		wl_ok = wl_ok and by_cls(P["Floor 1"], "window").filter(func(e): return e["a"]["data-id"] == id).size() == 3
	for id in ["o2", "o3"]:
		wl_ok = wl_ok and by_cls(P["Floor 2"], "window").filter(func(e): return e["a"]["data-id"] == id).size() == 3
	ok(wl_ok, "5 each window is three lines")
	var treads := by_cls(P["Floor 1"], "stairs").size()
	var arrow := by_cls(P["Floor 1"], "stairs-arrow").size()
	var up: int = P["Floor 1"]["els"].filter(func(e): return e["n"] == "text" and e["text"] == "UP").size()
	var dashed := by_cls(P["Floor 2"], "dashed").size()
	ok(treads == 15 and arrow == 3 and up == 1 and dashed == 4 and by_cls(P["Floor 2"], "stairs").is_empty(), "5 stairs: %d tread outlines, %d arrow lines, UP x%d on Floor 1; %d dashed lines (the stairwell) on Floor 2" % [treads, arrow, up, dashed])
	var tb: Array = P["Floor 1"]["els"].filter(func(e): return e["a"].get("class", "") == "title-text").map(func(e): return e["text"])
	ok(tb.has("Bay house") and tb.has("Floor 1 plan") and tb.has("1:%d" % int(pick["denom"])) and tb.has(Time.get_date_string_from_system()) and tb.has("Kine"), "5 title block: %s" % [tb])
	ok(by_cls(P["Floor 1"], "north-head").size() == 1 and P["Floor 1"]["els"].any(func(e): return e["n"] == "text" and e["text"] == "N"), "5 north arrow on the plan")
	ok(by_cls(P["Front"], "north-head").is_empty(), "5 and none on an elevation")
	# ---- 6 ELEV
	var fd := by_cls(P["Front"], "elev-door").size()
	var fw2 := by_cls(P["Front"], "elev-window").size()
	var sw := by_cls(P["Side"], "elev-window").size()
	ok(fd == 1 and fw2 == 2 and sw == 1 and by_cls(P["Side"], "elev-door").is_empty(), "6 Front: %d door + %d windows; Side: %d window" % [fd, fw2, sw])
	var rs := Building.roof_solid(b)
	var ytop := 0.0
	for v in rs["verts"]:
		ytop = maxf(ytop, v.y)
	var roof := by_cls(P["Front"], "roof")
	var rtop := 0.0
	if roof.size() == 1:
		rtop = INF
		for v in pts_of(roof[0]):
			rtop = minf(rtop, v.y)
	var ground := by_cls(P["Front"], "ground")
	var gy := float(ground[0]["a"]["y1"]) if ground.size() == 1 else 0.0
	ok(roof.size() == 1 and absf((gy - rtop) / k - ytop) < 0.001, "6 the roof silhouette's top is %.3f m above the ground line (the roof solid: %.3f)" % [(gy - rtop) / k, ytop])
	var hts := by_cls(P["Front"], "dim-text").filter(func(e): return e["a"].get("data-axis", "") == "y").map(func(e): return e["text"])
	var wts := by_cls(P["Front"], "dim-text").filter(func(e): return e["a"].get("data-axis", "") == "u").map(func(e): return e["text"])
	ok(hts == ["%.2f" % ytop] and wts == ["8.00"], "6 overall height %s and width %s on the front elevation" % [hts, wts])
	var wid_texts := by_cls(P["Front"], "dim-text").filter(func(e): return e["a"].get("data-kind", "") == "width").map(func(e): return e["a"]["data-id"] + "=" + e["text"])
	wid_texts.sort()
	ok(wid_texts == ["o1=0.90", "o2=1.20", "o3=1.20"], "6 each opening on the front says its width: %s" % [wid_texts])
	# ---- 7 DXF
	var dxf := Blueprint.to_dxf(sheets["Floor 1"])
	var lines := dxf.split("\n")
	var cnt := {"LINE": 0, "ARC": 0, "TEXT": 0}
	for i in range(0, lines.size() - 1, 2):
		if lines[i].strip_edges() == "0" and cnt.has(lines[i + 1].strip_edges()):
			cnt[lines[i + 1].strip_edges()] += 1
	var want_l := 0
	var want_a := 0
	var want_t := 0
	for e in sheets["Floor 1"]["ents"]:
		match e["t"]:
			"line": want_l += 1
			"poly": want_l += e["pts"].size()
			"arc": want_a += 1
			"text": want_t += 1
	ok(cnt["LINE"] == want_l and cnt["ARC"] == want_a and cnt["TEXT"] == want_t and want_a == 1 and dxf.contains("AC1009") and dxf.contains("ENTITIES") and dxf.ends_with("EOF\n"),
		"7 DXF re-read: %s LINE / ARC / TEXT = expected %d / %d / %d" % [cnt, want_l, want_a, want_t])
	# ---- 8 UI
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")   # unsaved work above: a new project asks first (startscreen bar 13)
	await idle(6)
	await to_house()
	var btn: Button = m.ui_ribbon["BUILD"].find_child("build_blueprint", true, false)
	ok(btn != null and btn.text == "Blueprint" and btn.icon != null and btn.disabled, "8 the Blueprint button is on the ribbon, greyed while there is no room")
	await click_ctl(btn)
	ok(not bld.bp.is_open(), "8 a click on the greyed button opens nothing")
	m.S.building = house()
	bld.sync()
	await idle(4)
	ok(not btn.disabled and m.ui_ribbon["BUILD"].get_child_count() > 0 and btn.get_global_rect().end.x <= 1280.0, "8 with the house the button is live and inside the 1280 px window")
	await click_ctl(btn)
	await idle(4)
	var bp: BlueprintUI = bld.bp
	var tab_btns := []
	for i in 6:
		var tb2 := bp.root.find_child("blueprint_tab_%d" % i, true, false)
		if tb2 != null:
			tab_btns.append(tb2)
	ok(bp.is_open() and tab_btns.size() == 4 and bp.tab == "Floor 1" and bp.sheet["tab"] == "Floor 1" and bp.view.size.x > 600.0, "8 a click on Blueprint opens the sheet: 4 tabs, Floor 1 first, the paper on screen %s" % bp.view.size)
	await shot("plan")
	await click_ctl(tab_btns[1])
	var t1: String = bp.tab
	await click_ctl(tab_btns[2])
	var t2: String = bp.tab
	await shot("elev")
	await click_ctl(tab_btns[3])
	var t3: String = bp.tab
	ok(t1 == "Floor 2" and t2 == "Front" and t3 == "Side" and bp.sheet["title"] == "Side elevation (right)" and bp.status.text.contains("Side elevation"), "8 tab clicks switch the sheet: %s, %s, %s" % [t1, t2, t3])
	await click_ctl(tab_btns[0])
	var d0 := DirAccess.get_files_at(DIRT).size()
	var sv: Button = bp.root.find_child("blueprint_export_svg", true, false)
	await click_ctl(sv)
	var f_svg := "%s/bay_house_floor1.svg" % DIRT
	var txt := FileAccess.get_file_as_string(f_svg)
	ok(FileAccess.file_exists(f_svg) and txt == svgs["Floor 1"].replace(Time.get_date_string_from_system(), Time.get_date_string_from_system()) and DirAccess.get_files_at(DIRT).size() == d0 + 1, "8 Export SVG wrote ONE file (%s, %d bytes), the same text as the sheet's SVG" % [f_svg, txt.length()])
	await click_ctl(bp.root.find_child("blueprint_export_dxf", true, false))
	var f_dxf := "%s/bay_house_floor1.dxf" % DIRT
	ok(FileAccess.file_exists(f_dxf) and FileAccess.get_file_as_string(f_dxf).contains("ENTITIES") and DirAccess.get_files_at(DIRT).size() == d0 + 2, "8 Export DXF wrote one more file")
	await click_ctl(bp.root.find_child("blueprint_export_png", true, false))
	var f_png := "%s/bay_house_floor1.png" % DIRT
	var tries := 0
	while not FileAccess.file_exists(f_png) and tries < 200:
		await idle(2)
		tries += 1
	await idle(4)
	var png := Image.load_from_file(ProjectSettings.globalize_path(f_png)) if FileAccess.file_exists(f_png) else null
	var want_px := Blueprint.png_size(sheets["Floor 1"])
	var dark := 0
	if png != null:
		for i in 4000:
			var px := png.get_pixel(int(randf() * png.get_width()) % png.get_width(), int(randf() * png.get_height()) % png.get_height())
			if px.r < 0.5:
				dark += 1
	ok(png != null and want_px == Vector2i(3508, 2480) and Vector2i(png.get_size()) == want_px, "8 Export PNG: %s px (%s at 300 dpi = %s)" % [Vector2i(png.get_size()) if png != null else "none", sheets["Floor 1"]["paper"], want_px])
	var big := FileAccess.get_file_as_bytes(f_png).size() if FileAccess.file_exists(f_png) else 0
	ok(big > 20000 and dark > 0 and DirAccess.get_files_at(DIRT).size() == d0 + 3, "8 the PNG is not blank (%d bytes, %d dark of 4000 samples); three exports = three files" % [big, dark])
	await click_ctl(bp.root.find_child("blueprint_close", true, false))
	ok(not bp.is_open() and bld.bp_btn.visible, "8 Close hides the sheet")
	# clean up only what this run wrote
	for f in DirAccess.get_files_at(DIRT):
		if f.begins_with("bay_house_floor1."):
			DirAccess.remove_absolute("%s/%s" % [DIRT, f])
	print("blueprint_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
