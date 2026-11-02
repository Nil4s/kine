extends SceneTree
## godot --path . --position 4000,4000 -s tests/s234_test.gd     (ITEM 234 PART TEXT AND NAMING; needs the CAD DLL)
## Bars (geometry, mm / mm3 from the kernel):
##   1 HOLES   a 40x40 square with a 20x20 hole in ONE sketch, one extrude of 10 = 12000 mm3 exactly; a ring r20 / r10 = pi (400-100) h
##   2 ISLAND  square in a hole in a square: two bodies (the frame and the island), volume exact
##   3 CROSS   two loops that truly cross: refused, the crossing point named
##   4 TEXT    the bundled OFL font draws any script it covers: the three characters 大雄殿 are ONE sketch + ONE extrude, one solid with volume > 0 and holes
##             (counters of 殿 ...); the volume of the solid = (outer area - hole area) * depth by the polygons
##   5 NAMES   a prim / extrude called "Column" in a temple style gets the column lacquer; the same pieces in a plain style keep the default look
##   6 SHOTS   the text part and a ring: C:/Users/Nick/tools/kine_workers/out/234/
const KCad := preload("res://scripts/kcad.gd")
const PText := preload("res://scripts/build/part_text.gd")
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/234"
const DIRT := "user://s234_test"


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
	await idle(3)


func pu() -> PartUI:
	return m.bld.part


func rect(a: Vector2, b: Vector2) -> Array:
	var ents := []
	var c := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
	for i in 4:
		ents.append({"k": "line", "a": Part.arr2(c[i]), "b": Part.arr2(c[(i + 1) % 4])})
	return ents


func circ(c: Vector2, r: float) -> Dictionary:
	return {"k": "circle", "c": Part.arr2(c), "r": r}


## a part of one sketch (top plane) and one extrude (op new) of dist mm
func pull(ents: Array, dist: float) -> Dictionary:
	var rec := Part.make("T")
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": ents, "dims": []})
	rec["features"].append(sk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": dist, "both": false, "op": "new"}))
	return rec


## [volumes in mm3 of the bodies, the replay result]
func vols(rec: Dictionary) -> Array:
	var r := Part.replay(rec, -1, {"keep": true})
	var out := []
	for id in r.get("ids", []):
		out.append(KCad.volume(int(id)) * 1e9)
	for id in r.get("ids", []):
		KCad.release(int(id))
	return [out, r]


func vnear(a: float, b: float) -> bool:
	return absf(a - b) <= 5e-7 * maxf(absf(b), 1.0)


func v0(a: Array) -> float:
	return a[0] if a.size() > 0 else -1.0


func poly_area(p: PackedVector2Array) -> float:
	return absf(PText.signed_area(p))


func api_bars() -> void:
	var ents := rect(Vector2(-20, -20), Vector2(20, 20)) + rect(Vector2(-10, -10), Vector2(10, 10))
	var v := vols(pull(ents, 10.0))
	var r1: Dictionary = v[1]
	ok(r1["errors"].is_empty() and int(r1["bodies"]) == 1 and vnear(v0(v[0]), 12000.0), "1a 40x40 square with a 20x20 hole, one sketch, extrude 10: %d body, %.4f mm3 (want 12000), errors %s" % [r1["bodies"], v0(v[0]), str(r1["errors"])])
	var v2 := vols(pull([circ(Vector2.ZERO, 20.0), circ(Vector2.ZERO, 10.0)], 7.0))
	var want := PI * (400.0 - 100.0) * 7.0
	ok(v2[1]["errors"].is_empty() and int(v2[1]["bodies"]) == 1 and vnear(v0(v2[0]), want), "1b ring r20 / r10, h 7: %d body, %.4f mm3 (want %.4f)" % [v2[1]["bodies"], v0(v2[0]), want])
	var v3 := vols(pull([circ(Vector2.ZERO, 20.0), circ(Vector2(3, 0), 5.0), circ(Vector2(60, 0), 8.0)], 4.0))
	var want3 := (PI * (400.0 - 25.0) + PI * 64.0) * 4.0
	var sum3 := 0.0
	for x in v3[0]:
		sum3 += x
	ok(int(v3[1]["bodies"]) == 2 and vnear(sum3, want3), "1c a washer with an off-centre hole and a disc beside it: %d bodies, %.3f mm3 (want %.3f)" % [v3[1]["bodies"], sum3, want3])
	var ents2 := rect(Vector2(-30, -30), Vector2(30, 30)) + rect(Vector2(-20, -20), Vector2(20, 20)) + rect(Vector2(-10, -10), Vector2(10, 10))
	var v4 := vols(pull(ents2, 5.0))
	var vs: Array = v4[0]
	vs.sort()
	ok(v4[1]["errors"].is_empty() and int(v4[1]["bodies"]) == 2 and vs.size() == 2 and vnear(vs[0], 20.0 * 20.0 * 5.0) and vnear(vs[1], (3600.0 - 1600.0) * 5.0),
		"2 square in a hole in a square: %d bodies (the frame and the island, kept apart), volumes %s (want [2000, 10000])" % [v4[1]["bodies"], str(vs)])
	var rc := pull(rect(Vector2(-20, -20), Vector2(20, 20)) + rect(Vector2(0, 0), Vector2(40, 40)), 10.0)
	var rr := Part.replay(rc)
	var msg := ""
	for k in rr["errors"]:
		msg = String(rr["errors"][k])
	ok(not rr["errors"].is_empty() and msg.contains("cross at (20, 0) mm") and int(rr["bodies"]) == 0, "3a two squares that cross: refused, body count %d, says: %s" % [rr["bodies"], msg])
	var rd := Part.replay(pull([circ(Vector2.ZERO, 20.0), circ(Vector2(25, 0), 10.0)], 10.0))
	var msg2 := ""
	for k in rd["errors"]:
		msg2 = String(rd["errors"][k])
	ok(not rd["errors"].is_empty() and msg2.contains("cross at"), "3b two circles that cross: refused, says: %s" % msg2)
	var rn := Part.replay(pull(rect(Vector2(0, 0), Vector2(10, 10)) + rect(Vector2(20, 0), Vector2(30, 10)), 10.0))
	ok(rn["errors"].is_empty() and int(rn["bodies"]) == 2, "3c control: two separate squares still make two bodies (%d)" % rn["bodies"])


func text_bars() -> void:
	var han := load("res://assets/fonts/KineHanSubset.otf") as Font
	ok(han != null, "4a the bundled font loads (%s, %d bytes)" % [han.get_font_name() if han != null else "none", FileAccess.get_file_as_bytes("res://assets/fonts/KineHanSubset.otf").size()])
	var t0 := Time.get_ticks_msec()
	var d := PText.part_record("大雄殿", 60.0, 8.0)
	ok(bool(d["ok"]), "4b the text lays out: %s" % String(d.get("why", "")))
	if not bool(d["ok"]):
		return
	var rec: Dictionary = d["rec"]
	var feats: Array = rec["features"]
	var nsk := feats.filter(func(f): return f["t"] == "sketch").size()
	var nex := feats.filter(func(f): return f["t"] == "extrude").size()
	ok(nsk == 1 and nex == 1 and feats.size() == 2, "4c ONE text feature: %d sketch + %d extrude, %d outer loops and %d hole loops" % [nsk, nex, d["outers"], d["holes"]])
	var nest := Part.loop_nest(Part.loops_of(feats[0]["ents"]))
	var holes_n := 0
	for dd in nest["depth"]:
		holes_n += 1 if int(dd) % 2 == 1 else 0
	var v := vols(rec)
	var r: Dictionary = v[1]
	var rw := PText.raw("大雄殿")
	var bb: Rect2 = rw["bb"]
	var rg := PText.rings(rw, 60.0 / bb.size.y, bb.get_center(), Vector2.ZERO, false)
	var area := 0.0
	var fill := 0.0
	for p in rg[0]:
		area += poly_area(p)
		fill += poly_area(p)
	for p in rg[1]:
		area -= poly_area(p)
	var total := 0.0
	for x in v[0]:
		total += x
	ok(r["errors"].is_empty() and int(r["bodies"]) >= 1 and total > 0.0, "4d the text part replays with no error: %d bodies, volume %.1f mm3, %d hole loops, %d ms (errors %s)" % [r["bodies"], total, holes_n, Time.get_ticks_msec() - t0, str(r["errors"])])
	ok(holes_n >= 3 and absf(total - area * 8.0) <= 0.002 * area * 8.0, "4e the solid has the glyphs' holes: %d hole loops; volume %.2f mm3 vs polygon area %.2f mm2 x 8 = %.2f (kernel and outlines within 0.2 %%)" % [holes_n, total, area, area * 8.0])
	ok(total < fill * 8.0 * 0.999, "4f the holes are really empty: %.1f mm3 < filled outlines %.1f mm3" % [total, fill * 8.0])
	var lat := PText.part_record("KINE", 30.0, 5.0)
	ok(bool(lat["ok"]), "4g Latin text still works (KINE: %d outer loops)" % lat["outers"])
	var bad := PText.raw("A\u0e01")
	ok(not bool(bad["ok"]) and String(bad["why"]).contains("no letter"), "4h a script the font does not cover is refused in words: %s" % String(bad["why"]))
	var kana := PText.raw("ひらがなカタカナ")
	ok(bool(kana["ok"]), "4i kana draws (%d outlines)" % (kana["outers"] as Array).size())


func tmp(name: String) -> Dictionary:
	var rec := Part.make(name)
	Part.prim(rec, "box", {"x": 0.0, "y": 0.0, "z": 0.0, "w": 400.0, "h": 2400.0, "d": 400.0})
	Part.prim(rec, "box", {"x": 1000.0, "y": 0.0, "z": 0.0, "w": 3000.0, "h": 300.0, "d": 3000.0})
	(rec["features"][0] as Dictionary)["name"] = "Column"
	(rec["features"][1] as Dictionary)["name"] = "Platform"
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": rect(Vector2(5000, 0), Vector2(5400, 400)), "dims": []})
	rec["features"].append(sk)
	var ex := Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": 2000.0, "both": false, "op": "new"})
	ex["name"] = "Pillar"
	rec["features"].append(ex)
	var sk2 := Part.new_feature(rec, "sketch", {"plane": "top", "ents": rect(Vector2(6000, 0), Vector2(6400, 400)), "dims": []})
	rec["features"].append(sk2)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk2["id"], "dist": 1000.0, "both": false, "op": "new"}))
	return rec


func name_bars() -> void:
	var rt := tmp("Chinese hall")
	var res := Part.replay(rt)
	var ks: Array = res["body_kinds"]
	var names: Array = res["body_names"]
	ok(int(res["bodies"]) == 4 and ks[0] == "column" and ks[1] == "platform" and ks[2] == "column", "5a the step names reach the piece kind: bodies %s named %s" % [str(ks), str(names)])
	ok(names[0] == "Column" and names[1] == "Platform" and names[2] == "Pillar" and names[3] == "Body4", "5b the body names are the step names (an auto name 'Extrude2' says nothing, stays Body4): %s" % str(names))
	var bl: Array = res["body_looks"]
	var mat_col: Variant = (bl[0] as Dictionary).get("mat", null)
	var mat_plat: Variant = (bl[1] as Dictionary).get("mat", null)
	ok(mat_col is Dictionary and not (mat_col as Dictionary).is_empty() and mat_plat is Dictionary and not (mat_plat as Dictionary).is_empty() and JSON.stringify(mat_col) != JSON.stringify(mat_plat),
		"5c in a temple style the Column and the Platform wear different made materials (column colour %s, platform %s)" % [str((bl[0] as Dictionary).get("c")), str((bl[1] as Dictionary).get("c"))])
	var rp := tmp("Garden shed")
	var resp := Part.replay(rp)
	var plain := true
	for l in resp["body_looks"]:
		var mm: Variant = (l as Dictionary).get("mat", null)
		if mm is Dictionary and not (mm as Dictionary).is_empty():
			plain = false
	ok(PieceLook.style_of(rp) == "" and plain and resp["body_names"][0] == "Column", "5d a plain style (Garden shed): bodies keep the default look (no made material), the name is still carried (%s)" % str(resp["body_names"]))
	var rt2 := tmp("Garden shed")
	rt2["style"] = "temple"
	var rest := Part.replay(rt2)
	ok(PieceLook.plain_count(rest) == 0, "5e the same part with the temple style set by hand: plain bodies %d" % PieceLook.plain_count(rest))
	var rj := Part.make("Chinese hall")
	Part.prim(rj, "box", {"x": 0.0, "y": 0.0, "z": 0.0, "w": 100.0, "h": 100.0, "d": 100.0})
	var res_j := Part.replay(rj)
	ok(res_j["body_names"][0] == "Box1", "5f an auto-named prim (%s) is not renamed by the step name rule (kernel prim names it Box1 as before): %s" % [rj["features"][0]["name"], str(res_j["body_names"])])


func shots() -> void:
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	ok(m.cur_page == "BUILD" and pu().on, "6a Easy Part is on")
	var d := PText.part_record("大雄殿", 60.0, 8.0)
	m.S.part = d["rec"]
	pu().upto = -1
	pu().sync()
	await idle(40)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(SHOT + "/text_daxiongdian.png")
	ok(int(pu().res.get("bodies", 0)) >= 1, "6b the text part is on screen: %d body, volume %.1f mm3" % [pu().res.get("bodies", 0), float(pu().res.get("volume", 0.0)) * 1e9])
	m.S.part = pull([circ(Vector2.ZERO, 20.0), circ(Vector2.ZERO, 10.0)], 7.0)
	pu().upto = -1
	pu().sync()
	await idle(40)
	root.get_texture().get_image().save_png(SHOT + "/ring.png")
	ok(int(pu().res.get("bodies", 0)) == 1, "6c the ring is on screen: %d body" % pu().res.get("bodies", 0))
	m.S.part = pull(rect(Vector2(-30, -30), Vector2(30, 30)) + rect(Vector2(-20, -20), Vector2(20, 20)) + rect(Vector2(-10, -10), Vector2(10, 10)), 5.0)
	pu().upto = -1
	pu().sync()
	await idle(40)
	root.get_texture().get_image().save_png(SHOT + "/island.png")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	api_bars()
	text_bars()
	name_bars()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	await shots()
	print("s234: %d fail" % fails)
	quit(0 if fails == 0 else 1)
