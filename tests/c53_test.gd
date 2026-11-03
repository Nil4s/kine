extends SceneTree
## godot --path . --position 4000,4000 -s tests/c53_test.gd     (C53, M #220: File > Import 2D, an SVG or DXF into a Part sketch)
## Bars (written and committed BEFORE the parser existed; fixtures in tests/fixtures/c53/):
##  1 SVG COUNT   shapes.svg (rect, circle, path with a line + a half-circle arc + Z, one <text>): 4 sketch entities (rect, circle, line, arc);
##                the <text> is LISTED as unsupported (1 entry naming "text"), never dropped silently
##  2 SVG SIZE    (viewBox in mm, 1 unit = 1 mm, y flipped to the sketch's up): rect a=(10,40) b=(30,50); circle c=(50,30) r=8; arc ends (90,20) and (70,20) and
##                a middle 10 mm from their midpoint; all within 0.01 mm
##  3 SVG EXTRUDE the 3 closed loops extruded 5 mm: volume = (200 + pi*64 + pi*50) * 5 mm3 within 0.1 pct
##  4 SVG PX      px.svg has no size: its 96 x 48 px rect is 25.4 x 12.7 mm (96 dpi) within 0.01, and the units line says px at 96 dpi
##  5 DXF COUNT   shapes.dxf (LINE, ARC, CIRCLE, closed LWPOLYLINE of 4 points, TEXT): 7 sketch entities (1+1+1+4), 4 source entities read, TEXT listed as unsupported
##  6 DXF SIZE    line (0,0)-(20,0); arc ends (20,0),(0,0), middle (10,10); circle c=(50,10) r=6; polyline square 70..100 x 0..30; all within 0.01 mm
##  7 DXF EXTRUDE the line + arc half disc, the circle and the square extruded 3 mm: (pi*50 + pi*36 + 900) * 3 mm3 within 0.1 pct
##  8 DXF UNITS   $INSUNITS 1 (inches): a 1 in LINE is 25.4 mm within 0.01
##  9 UNDO        through PartUI: import = ONE undo step (undo size +1; still +1 after Finish sketch); one undo removes the sketch; a file with nothing drawable
##                adds NO step and says why
## 10 UI          the Import 2D button (part_import2d) and its plane menu (3 items) exist; at 1280x720 the button is on the bar inside the viewport or listed under More; screenshot of an imported sketch
## CONTROLS: a checker that must reject a value 0.02 mm off; a file with only <text> imports 0 entities (bars 1 and 9 can fail); the same extrude without the
##   import (empty record) has volume 0 (bar 3/7 can fail).
const SI := preload("res://scripts/build/sketch_import.gd")
const SIUI := preload("res://scripts/build/sketch_import_ui.gd")
const FIX := "res://tests/fixtures/c53/"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c53"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func near(a: Variant, x: float, y: float, tol := 0.01) -> bool:
	return absf(float(a[0]) - x) <= tol and absf(float(a[1]) - y) <= tol


func ents_of(ents: Array, k: String) -> Array:
	return ents.filter(func(e): return String(e["k"]) == k)


func vol_mm3(ents: Array, dist: float) -> float:
	var rec := Part.make("c53")
	var f := Part.new_feature(rec, "sketch", {"plane": "front", "ents": ents, "dims": []})
	rec["features"].append(f)
	var x := Part.new_feature(rec, "extrude", {"sketch": f["id"], "dist": dist, "both": false, "op": "new"})
	rec["features"].append(x)
	return float(Part.replay(rec)["volume"]) * 1e9


func rel(v: float, want: float) -> bool:
	return absf(v - want) <= 0.001 * want


func _init() -> void:
	create_timer(420.0).timeout.connect(func():
		print("FAIL watchdog: the test ran over 420 s")
		quit(2))
	DirAccess.make_dir_recursive_absolute(SHOT)
	var svg := FileAccess.get_file_as_string(FIX + "shapes.svg")
	var dxf := FileAccess.get_file_as_string(FIX + "shapes.dxf")
	# controls first
	ok(not near([10.02, 40.0], 10.0, 40.0), "control: the 0.01 mm checker rejects a value 0.02 mm off")
	var only_text: Dictionary = SI.parse("svg", "<svg xmlns='http://www.w3.org/2000/svg'><text x='1' y='1'>a</text></svg>")
	ok((only_text["ents"] as Array).size() == 0 and (only_text["unsupported"] as Array).size() == 1, "control: a file with only <text> imports 0 entities and lists 1 unsupported")
	ok(vol_mm3([], 5.0) < 1e-6, "control: the extrude of an empty import has volume 0")

	var r: Dictionary = SI.parse("svg", svg)
	var e: Array = r["ents"]
	ok(e.size() == 4 and ents_of(e, "rect").size() == 1 and ents_of(e, "circle").size() == 1 and ents_of(e, "line").size() == 1 and ents_of(e, "arc").size() == 1, "1 SVG count: %d entities (rect %d, circle %d, line %d, arc %d)" % [e.size(), ents_of(e, "rect").size(), ents_of(e, "circle").size(), ents_of(e, "line").size(), ents_of(e, "arc").size()])
	var un: Array = r["unsupported"]
	ok(un.size() == 1 and String(un[0]).contains("text"), "1 SVG unsupported listed: %s" % [un])
	if e.size() == 4:
		var rc: Dictionary = ents_of(e, "rect")[0]
		var ci: Dictionary = ents_of(e, "circle")[0]
		var ar: Dictionary = ents_of(e, "arc")[0]
		var ra: Array = rc["a"]
		var rb: Array = rc["b"]
		var lo := Vector2(minf(ra[0], rb[0]), minf(ra[1], rb[1]))
		var hi := Vector2(maxf(ra[0], rb[0]), maxf(ra[1], rb[1]))
		ok(near(lo, 10.0, 40.0) and near(hi, 30.0, 50.0), "2 SVG rect %s .. %s (want 10,40 .. 30,50)" % [lo, hi])
		ok(near(ci["c"], 50.0, 30.0) and absf(float(ci["r"]) - 8.0) <= 0.01, "2 SVG circle c %s r %s (want 50,30 r 8)" % [ci["c"], ci["r"]])
		var a := Part.v2(ar["a"])
		var b := Part.v2(ar["b"])
		var mid := Part.v2(ar["m"])
		var ends_ok := (near(a, 90.0, 20.0) and near(b, 70.0, 20.0)) or (near(a, 70.0, 20.0) and near(b, 90.0, 20.0))
		ok(ends_ok and absf(mid.distance_to((a + b) * 0.5) - 10.0) <= 0.01, "2 SVG arc ends %s %s, middle %.3f from their midpoint (want 10)" % [a, b, mid.distance_to((a + b) * 0.5)])
	var want_svg := (200.0 + PI * 64.0 + PI * 50.0) * 5.0
	var v := vol_mm3(e, 5.0)
	ok(rel(v, want_svg), "3 SVG extrude volume %.2f mm3 (want %.2f within 0.1 pct)" % [v, want_svg])

	var px: Dictionary = SI.parse("svg", FileAccess.get_file_as_string(FIX + "px.svg"))
	var pe: Array = px["ents"]
	if pe.size() == 1:
		var pa: Array = pe[0]["a"]
		var pb: Array = pe[0]["b"]
		ok(absf(absf(float(pb[0]) - float(pa[0])) - 25.4) <= 0.01 and absf(absf(float(pb[1]) - float(pa[1])) - 12.7) <= 0.01, "4 SVG px: %.3f x %.3f mm (want 25.4 x 12.7)" % [absf(float(pb[0]) - float(pa[0])), absf(float(pb[1]) - float(pa[1]))])
	else:
		ok(false, "4 SVG px: %d entities, wanted 1" % pe.size())
	ok(String(px.get("units", "")).contains("96"), "4 SVG px units line says 96 dpi: '%s'" % px.get("units", ""))

	var d: Dictionary = SI.parse("dxf", dxf)
	var de: Array = d["ents"]
	ok(de.size() == 7 and int(d.get("source_count", -1)) == 4, "5 DXF count: %d entities, %s source entities (want 7 and 4)" % [de.size(), d.get("source_count", "?")])
	var du: Array = d["unsupported"]
	ok(du.size() == 1 and String(du[0]).contains("TEXT"), "5 DXF unsupported listed: %s" % [du])
	if de.size() == 7:
		var lines := ents_of(de, "line")
		var ln: Dictionary = {}
		for l in lines:
			if near(l["a"], 0.0, 0.0) or near(l["b"], 0.0, 0.0):
				ln = l
		ok(not ln.is_empty() and ((near(ln["a"], 0.0, 0.0) and near(ln["b"], 20.0, 0.0)) or (near(ln["b"], 0.0, 0.0) and near(ln["a"], 20.0, 0.0))), "6 DXF line (0,0)-(20,0): %s" % [ln])
		var ar2: Dictionary = ents_of(de, "arc")[0]
		var a2 := Part.v2(ar2["a"])
		var b2 := Part.v2(ar2["b"])
		var m2 := Part.v2(ar2["m"])
		ok(((near(a2, 20.0, 0.0) and near(b2, 0.0, 0.0)) or (near(b2, 20.0, 0.0) and near(a2, 0.0, 0.0))) and near(m2, 10.0, 10.0), "6 DXF arc %s %s mid %s" % [a2, b2, m2])
		var c2: Dictionary = ents_of(de, "circle")[0]
		ok(near(c2["c"], 50.0, 10.0) and absf(float(c2["r"]) - 6.0) <= 0.01, "6 DXF circle c %s r %s" % [c2["c"], c2["r"]])
		var xs := []
		var ys := []
		for l in lines:
			if l == ln:
				continue
			for k in ["a", "b"]:
				xs.append(float(l[k][0]))
				ys.append(float(l[k][1]))
		ok(xs.size() == 8 and xs.min() >= 69.99 and xs.max() <= 100.01 and ys.min() >= -0.01 and ys.max() <= 30.01 and absf(xs.max() - xs.min() - 30.0) <= 0.01 and absf(ys.max() - ys.min() - 30.0) <= 0.01, "6 DXF polyline square: x %s..%s y %s..%s" % [xs.min() if xs.size() else "?", xs.max() if xs.size() else "?", ys.min() if ys.size() else "?", ys.max() if ys.size() else "?"])
	var want_dxf := (PI * 50.0 + PI * 36.0 + 900.0) * 3.0
	var v2d := vol_mm3(de, 3.0)
	ok(rel(v2d, want_dxf), "7 DXF extrude volume %.2f mm3 (want %.2f within 0.1 pct)" % [v2d, want_dxf])
	var inch := "  0\r\nSECTION\r\n  2\r\nHEADER\r\n  9\r\n$INSUNITS\r\n 70\r\n1\r\n  0\r\nENDSEC\r\n  0\r\nSECTION\r\n  2\r\nENTITIES\r\n  0\r\nLINE\r\n 10\r\n0\r\n 20\r\n0\r\n 11\r\n1\r\n 21\r\n0\r\n  0\r\nENDSEC\r\n  0\r\nEOF\r\n"
	var ir: Dictionary = SI.parse("dxf", inch)
	var ie: Array = ir["ents"]
	ok(ie.size() == 1 and absf(Part.v2(ie[0]["a"]).distance_to(Part.v2(ie[0]["b"])) - 25.4) <= 0.01, "8 DXF inches: line %s mm (want 25.4)" % [Part.v2(ie[0]["a"]).distance_to(Part.v2(ie[0]["b"])) if ie.size() == 1 else "?"])

	# UI
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
	var DIRT := "user://c53_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	var card: Control = ss._cards["building"]
	var cp := card.get_global_rect().get_center()
	for down in [true, false]:
		var me := InputEventMouseButton.new()
		me.button_index = MOUSE_BUTTON_LEFT
		me.pressed = down
		me.position = cp
		me.global_position = cp
		root.push_input(me, true)
		await process_frame
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not pu.on:
		pu.part_btn.button_pressed = true
		await idle(4)
	var n0: int = m.undo.size()
	var rep: Dictionary = SIUI.import_text(pu, "svg", svg, "front")
	await idle(3)
	var n1: int = m.undo.size()
	var feats: Array = m.S.part.get("features", [])
	ok(bool(rep.get("ok", false)) and n1 == n0 + 1 and feats.size() == 1 and (feats[0]["ents"] as Array).size() == 4, "9 UNDO import: ok %s, undo %d -> %d, %d feature(s), %d entities" % [rep.get("ok"), n0, n1, feats.size(), (feats[0]["ents"] as Array).size() if feats.size() else -1])
	await idle(2)
	var shot_img := root.get_texture().get_image()
	shot_img.save_png(SHOT + "/c53_sketch_1280x720.png")
	pu.finish_sketch()
	await idle(2)
	ok(m.undo.size() == n0 + 1 and (m.S.part.get("features", []) as Array).size() == 1, "9 UNDO still one step after Finish sketch (undo %d, want %d)" % [m.undo.size(), n0 + 1])
	m._undo()
	await idle(3)
	ok((m.S.part.get("features", []) as Array).size() == 0, "9 UNDO one undo removes the whole imported sketch (%d features left)" % (m.S.part.get("features", []) as Array).size())
	var n2: int = m.undo.size()
	var bad: Dictionary = SIUI.import_text(pu, "svg", "<svg xmlns='http://www.w3.org/2000/svg'><text x='1' y='1'>a</text></svg>", "front")
	ok(not bool(bad.get("ok", true)) and m.undo.size() == n2 and String(bad.get("words", "")).length() > 5, "9 UNDO a file with nothing drawable: no step, says '%s'" % bad.get("words", ""))
	var rep2: Dictionary = SIUI.import_text(pu, "dxf", dxf, "top")
	await idle(3)
	ok(bool(rep2.get("ok", false)) and String(m.S.part["features"][0].get("plane", "")) == "top" and (m.S.part["features"][0]["ents"] as Array).size() == 7 and (rep2.get("unsupported", []) as Array).size() == 1, "9 DXF onto the Top plane: plane %s, %d entities, unsupported %s" % [m.S.part["features"][0].get("plane", ""), (m.S.part["features"][0]["ents"] as Array).size(), rep2.get("unsupported", [])])
	m._undo()
	await idle(2)
	var rep3: Dictionary = SIUI.import_text(pu, "svg", svg, "front")
	await idle(4)
	var btn: Button = pu.get("import2d_btn")
	var pl: PopupMenu = pu.get("import2d_menu")
	var vp := root.get_visible_rect()
	var in_view: bool = btn != null and btn.is_visible_in_tree() and vp.encloses(btn.get_global_rect())
	var in_more: bool = btn != null and m._more_tools.has(btn) and m.ui_more.visible
	ok(btn != null and (in_view or in_more) and pl != null and pl.item_count == 3 and btn.text != "", "10 UI Import 2D button reachable (on the bar %s, under More %s, rect %s) and its plane menu has %d items" % [in_view, in_more, btn.get_global_rect() if btn else "none", pl.item_count if pl else -1])
	root.get_texture().get_image().save_png(SHOT + "/c53_ui_1280x720.png")
	print("c53: %d fail" % fails)
	quit(1 if fails > 0 else 0)
