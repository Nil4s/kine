extends SceneTree
## godot --path . --position 4000,4000 -s tests/c12_test.gd     (C12: drawing sheets, complaints #423 callouts, #432 dim style presets, #441 custom sheets; needs a window)
## Bars, written and committed BEFORE the first run:
##   1 DEFAULTS  PAPERS is still {A4, A3}, TRIES has 7 entries, the Default preset is gap 1.5 / over 1.5 / tgap 0.8 / no background, the house still
##               picks A4 1:50, and a default sheet's SVG has no dim-bg / callout / leader element
##   2 PRESETS   a dimension a=(0,0) c=(50,0) n=(0,1) off=10 under each preset: its first extension line starts at y = gap and ends at y = 10 + over,
##               its text sits at y = 10 - tgap, and a dim-bg box exists exactly when bg is on and contains the text anchor. Tight differs from Default
##               (control: Default's gap 1.5 is not Tight's 0.5), an unknown name is refused, a saved user set is selectable and reproduces its numbers
##   3 CUSTOM    custom_pick(10000, 8000, 1): the SVG is 10000mm x 8000mm, data-denom 1, 1000 mm per m; the house's overall 8.00 dimension line is
##               8000 mm long on the paper (+-0.01) and the drawing lies inside the border; 50 x 50 and 30000 x 30000 are refused; the PNG is
##               118110 x 94488 px at 300 dpi; choose() still says A4 1:50. Control: the same house at 1:1 on a 300 x 200 mm sheet does NOT fit
##   4 CALLOUT   callout("B", (100,100), (150,60)): the leader's start lies ON the letter box's edge (<0.001 mm), the box encloses the letter and the start
##               is not the letter's centre (control: a leader planted from the centre fails the same check), the leader is collinear with the target,
##               a target straight right starts at the box's right edge; clean_letter("") = "A", "bc" -> "BC"; rename changes the sheet's letter; next_letter = C
##   5 UI        1280x720, real clicks: the second row is on screen inside the window; selecting Boxed puts dim-bg on the open sheet; the Custom 1:1
##               check box makes the sheet "Custom 10000x8000" at 1:1; Add callout + two clicks on the sheet adds letter B with its leader start on the box edge
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c12"


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


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func house() -> Dictionary:
	var b := Building.make("Bay house")
	Building.add_room(b, 0, 0, 8, 6)
	Building.add_floor(b)
	Building.add_opening(b, "r1", "front", "door", 0.0)
	Building.add_opening(b, "r2", "front", "window", -2.0)
	Building.add_opening(b, "r2", "front", "window", 2.0)
	Building.add_opening(b, "r1", "left", "window", 0.0)
	Building.add_opening(b, "r1", "right", "window", 0.0)
	Building.set_roof(b, "gable")
	Building.add_piece(b, "stairs", 1.0, 3.0, 0.0, 0)
	return b


func cls_of(ents: Array, cls: String) -> Array:
	return ents.filter(func(e): return String(e["cls"]) == cls)


## distance from p to the boundary of r (999 when p is outside r)
func edge_dist(r: Rect2, p: Vector2) -> float:
	var dx := minf(absf(p.x - r.position.x), absf(p.x - r.end.x))
	var dy := minf(absf(p.y - r.position.y), absf(p.y - r.end.y))
	var inx := p.x >= r.position.x - 0.001 and p.x <= r.end.x + 0.001
	var iny := p.y >= r.position.y - 0.001 and p.y <= r.end.y + 0.001
	if inx and iny:
		return minf(dx, dy)
	return 999.0


func box_of(ent: Dictionary) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in ent["pts"]:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	return Rect2(mn, mx - mn)


## the leader check: starts on the box edge (not inside it, not at its centre)
func leader_ok(box: Rect2, start: Vector2) -> bool:
	return edge_dist(box, start) < 0.001 and start.distance_to(box.get_center()) > box.size.y * 0.4


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var b := house()
	# ---- 1 DEFAULTS
	var dp: Dictionary = BlueprintExt.DIM_PRESETS["Default"]
	var d0 := Blueprint.sheet(b, "Floor 1")
	var sv0 := Blueprint.to_svg(d0)
	ok(Blueprint.PAPERS.keys() == ["A4", "A3"] and Blueprint.TRIES.size() == 7 and Blueprint.STYLE["dim"]["w"] == 0.13 and Blueprint.STYLE["wall"]["fill"] == "#1b1b1b",
		"1 PAPERS / TRIES / STYLE values unchanged")
	ok(dp["gap"] == 1.5 and dp["over"] == 1.5 and dp["tgap"] == 0.8 and dp["bg"] == false and BlueprintExt.active == "Default", "1 the Default preset is the old fixed numbers")
	var ch0 := Blueprint.choose(b)
	ok(ch0["paper"] == "A4" and ch0["denom"] == 50 and not sv0.contains("dim-bg") and not sv0.contains("callout") and not sv0.contains("leader"), "1 the house still picks A4 1:50, no new element in a default SVG")
	# ---- 2 PRESETS
	var res := {}
	for nm in ["Default", "Tight", "Airy", "Boxed"]:
		BlueprintExt.use_preset(nm)
		var es: Array = Blueprint._dim(Vector2(0, 0), Vector2(50, 0), Vector2(0, 1), 10.0, "5.00")
		var p: Dictionary = BlueprintExt.DIM_PRESETS[nm]
		var lines := cls_of(es, "dim").filter(func(e): return e["t"] == "line")
		var ext: Dictionary = lines[0]
		var txt: Dictionary = cls_of(es, "dim-text")[0]
		var bgs := cls_of(es, "dim-bg")
		var bg_ok: bool = (bgs.size() == 1 and box_of(bgs[0]).has_point(txt["p"])) if p["bg"] else bgs.is_empty()
		ok(is_equal_approx(ext["a"].y, p["gap"]) and is_equal_approx(ext["b"].y, 10.0 + p["over"]) and is_equal_approx(txt["p"].y, 10.0 - p["tgap"]) and bg_ok,
			"2 %s: extension %.2f -> %.2f, text at y %.2f, background %s" % [nm, ext["a"].y, ext["b"].y, txt["p"].y, bgs.size()])
		res[nm] = ext["a"].y
	ok(res["Default"] == 1.5 and res["Tight"] == 0.5 and res["Default"] != res["Tight"], "2 control: Tight's gap (0.5) is not Default's (1.5)")
	ok(not BlueprintExt.use_preset("Nope") and BlueprintExt.active == "Boxed", "2 an unknown preset is refused and the active one stays")
	ok(BlueprintExt.save_preset("Mine", 2.0, 0.0, 1.0, true) and not BlueprintExt.save_preset("", 1, 1, 1, false) and not BlueprintExt.save_preset("Tight", 1, 1, 1, false) and BlueprintExt.preset_names().has("Mine"), "2 a user set saves under a new name only")
	BlueprintExt.use_preset("Mine")
	var me: Array = Blueprint._dim(Vector2(0, 0), Vector2(50, 0), Vector2(0, 1), 10.0, "5.00")
	var ml: Dictionary = cls_of(me, "dim").filter(func(e): return e["t"] == "line")[0]
	ok(is_equal_approx(ml["a"].y, 2.0) and is_equal_approx(ml["b"].y, 10.0) and cls_of(me, "dim-bg").size() == 1, "2 the saved set reproduces its numbers (gap 2, over 0, background)")
	var shb := Blueprint.sheet(b, "Floor 1")
	var sb := Blueprint.to_svg(shb)
	var n_txt := cls_of(shb["ents"], "dim-text").size()
	ok(sb.count("class=\"dim-bg\"") == n_txt and n_txt > 0, "2 the SVG has one dim-bg per dimension text (%d)" % n_txt)
	BlueprintExt.use_preset("Default")
	var dat := Time.get_date_string_from_system()
	ok(Blueprint.to_svg(Blueprint.sheet(b, "Floor 1")).replace(dat, "D") == sv0.replace(dat, "D"), "2 back on Default the sheet is identical to the first one")
	# ---- 3 CUSTOM
	var pk := BlueprintExt.custom_pick(10000, 8000, 1)
	var cs := Blueprint.sheet(b, "Floor 1", pk)
	var svg := Blueprint.to_svg(cs)
	ok(pk["paper"] == "Custom 10000x8000" and svg.contains("width=\"10000mm\"") and svg.contains("height=\"8000mm\"") and svg.contains("data-denom=\"1\"") and svg.contains("data-mm-per-m=\"1000\""),
		"3 the SVG is 10000mm x 8000mm at 1:1, 1000 mm per metre")
	var has_overall := false
	for e in cls_of(cs["ents"], "dim"):
		if e["t"] == "line" and absf(e["a"].distance_to(e["b"]) - 8000.0) < 0.01:
			has_overall = true
	var area: Rect2 = cs["area"]
	var inside := true
	for e in cs["ents"]:
		if String(e["cls"]) in ["border", "title", "title-label", "title-text"]:
			continue
		if e["t"] == "line":
			inside = inside and area.grow(1.0).has_point(e["a"]) and area.grow(1.0).has_point(e["b"])
	ok(has_overall and inside, "3 the overall dimension is a 8000 mm line on the paper and the drawing is inside the border")
	ok(BlueprintExt.custom_pick(50, 50).is_empty() and BlueprintExt.custom_pick(30000, 30000).is_empty() and BlueprintExt.custom_pick(500, 500, 0).is_empty(), "3 sizes out of range (50, 30000) and scale 1:0 are refused")
	ok(Blueprint.png_size(cs) == Vector2i(118110, 94488) and Blueprint.choose(b)["paper"] == "A4", "3 the PNG is %s px at 300 dpi; choose() still says A4" % Blueprint.png_size(cs))
	var tiny := Blueprint.sheet(b, "Floor 1", BlueprintExt.custom_pick(300, 200, 1))
	var tb := Blueprint._bounds(tiny["ents"].filter(func(e): return not (String(e["cls"]) in ["border", "title", "title-label", "title-text"])))
	var tarea: Rect2 = tiny["area"]
	ok(tb.size.x > tarea.size.x, "3 control: the house at 1:1 on 300 x 200 mm does not fit (%.0f > %.0f)" % [tb.size.x, tarea.size.x])
	# ---- 4 CALLOUT
	var ents := BlueprintExt.callout("B", Vector2(100, 100), Vector2(150, 60))
	var box := box_of(cls_of(ents, "callout")[0])
	var ld: Dictionary = cls_of(ents, "leader").filter(func(e): return e["t"] == "line")[0]
	var tx: Dictionary = cls_of(ents, "callout-text")[0]
	var dir: Vector2 = (ld["b"] - box.get_center()).normalized()
	var col: float = absf((ld["a"] - box.get_center()).normalized().cross(dir))
	ok(tx["s"] == "B" and box.has_point(tx["p"]) and leader_ok(box, ld["a"]) and col < 0.0001 and ld["b"] == Vector2(150, 60), "4 the leader starts on the letter box's edge (%.4f mm) and runs to the target" % edge_dist(box, ld["a"]))
	ok(not leader_ok(box, box.get_center()), "4 control: a leader planted from the letter's centre fails the edge check")
	var e2 := BlueprintExt.callout("C", Vector2(100, 100), Vector2(300, 100))
	var b2 := box_of(cls_of(e2, "callout")[0])
	var l2: Dictionary = cls_of(e2, "leader").filter(func(e): return e["t"] == "line")[0]
	ok(is_equal_approx(l2["a"].x, b2.end.x) and is_equal_approx(l2["a"].y, b2.get_center().y), "4 a target straight to the right starts at the box's right edge")
	ok(BlueprintExt.clean_letter("") == "A" and BlueprintExt.clean_letter("bc") == "BC" and BlueprintExt.clean_letter("abcdef") == "ABC", "4 the letter is cleaned: '' -> A, bc -> BC, 3 characters at most")
	var lst := [{"letter": "A", "p": Vector2(50, 50), "t": Vector2(80, 80)}, {"letter": "B", "p": Vector2(60, 50), "t": Vector2(90, 80)}]
	ok(BlueprintExt.next_letter(lst) == "C" and BlueprintExt.rename_callout(lst, "B", "d") and lst[1]["letter"] == "D" and not BlueprintExt.rename_callout(lst, "Q", "Z"), "4 next letter C; rename B -> D works, an unknown letter is refused")
	var sh4 := Blueprint.sheet(b, "Floor 1")
	var n_before: int = sh4["ents"].size()
	BlueprintExt.apply_callouts(sh4, lst)
	var s4 := Blueprint.to_svg(sh4)
	ok(sh4["ents"].size() == n_before + 8 and s4.contains(">D</text>") and s4.contains("class=\"leader\"") and Blueprint.to_dxf(sh4).contains("LEADER"), "4 the sheet carries both callouts in SVG and DXF (8 entities)")
	# ---- 5 UI
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c12_test"))
	ss.dirs_override = ["user://c12_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")
	await idle(6)
	m.S.building = house()
	bld.sync()
	await idle(4)
	var btn: Button = m.ui_ribbon["BUILD"].find_child("build_blueprint", true, false)
	await click_ctl(btn)
	await idle(4)
	var bp: BlueprintUI = bld.bp
	var row: Control = bp.root.find_child("blueprint_ext_row", true, false)
	ok(bp.is_open() and row != null and row.get_global_rect().end.x <= 1280.0 and row.get_global_rect().end.y <= 720.0 and bp.sheet["paper"] == "A4", "5 the second row is on screen inside 1280x720")
	var op: OptionButton = bp.root.find_child("blueprint_dim_preset", true, false)
	var bi := 0
	for i in op.item_count:
		if op.get_item_text(i) == "Boxed":
			bi = i
	op.select(bi)
	op.item_selected.emit(bi)
	await idle(3)
	ok(cls_of(bp.sheet["ents"], "dim-bg").size() > 0 and BlueprintExt.active == "Boxed", "5 picking Boxed puts the text backgrounds on the open sheet")
	op.select(0)
	op.item_selected.emit(0)
	await idle(3)
	var cw: SpinBox = bp.root.find_child("blueprint_sheet_w", true, false)
	var chh: SpinBox = bp.root.find_child("blueprint_sheet_h", true, false)
	cw.value = 10000
	chh.value = 8000
	await click_ctl(bp.root.find_child("blueprint_custom_on", true, false))
	await idle(3)
	ok(bp.sheet["paper"] == "Custom 10000x8000" and int(bp.sheet["denom"]) == 1 and bp.status.text.contains("1:1"), "5 the Custom 1:1 check box gives a %s sheet at 1:%d" % [bp.sheet["paper"], int(bp.sheet["denom"])])
	await click_ctl(bp.root.find_child("blueprint_custom_on", true, false))
	await idle(3)
	ok(bp.sheet["paper"] == "A4", "5 unticking it goes back to A4")
	bp.ext.letter.text = "B"
	await click_ctl(bp.root.find_child("blueprint_callout_add", true, false))
	var o: Vector2 = bp.view.get_global_rect().position
	await click_at(o + Vector2(60, 40) * bp.view.ppm)
	await click_at(o + Vector2(140, 90) * bp.view.ppm)
	var cb := cls_of(bp.sheet["ents"], "callout")
	var okc := false
	if cb.size() == 1:
		var bx := box_of(cb[0])
		var lead: Dictionary = cls_of(bp.sheet["ents"], "leader").filter(func(e): return e["t"] == "line")[0]
		okc = leader_ok(bx, lead["a"]) and cls_of(bp.sheet["ents"], "callout-text")[0]["s"] == "B"
	ok(okc, "5 Add callout + two clicks on the sheet adds letter B with its leader starting on the box edge")
	DirAccess.make_dir_recursive_absolute(SHOT)
	await idle(3)
	root.get_texture().get_image().save_png(SHOT + "/c12_ui_1280.png")
	print("c12_test: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
