extends SceneTree
## s229 AUTHORING SPEED + SAFETY (hall duel gaps 5, 9, 10 and "only 3 planes"): primitives by numbers, planes from 3 points / an angle, scoped intersect,
## a bow-tie sketch refused with the crossing point. Part A: the record API (Part.prim / Part.add_plane / Part.replay). Part B: the real UI (Expert Primitive
## dialog with typed fields, Easy "By numbers" row), one undo step, saved and reloaded.
## Bars: sizes in mm measured from the solids (a fine tessellation for round shapes), counts, volumes; shots in C:/Users/Nick/tools/kine_workers/out/229/.
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/229"
const DIRT := "user://s229_test"


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


## volumes: the kernel reports them to about 1e-7 relative
func vnear(a: float, b: float) -> bool:
	return absf(a - b) <= 5e-7 * maxf(absf(b), 1.0)


## the solids of a record, each with a FINE tessellation box (mm) and its exact centre (mm) and volume (mm3)
func solids(rec: Dictionary) -> Array:
	var r := Part.replay(rec, -1, {"keep": true})
	var out := []
	for id in r.get("ids", []):
		var mesh := KCad.tessellate(int(id), 0.000001, 0.02)
		var bb := mesh.get_aabb() if mesh != null else AABB()
		var mp := KCad.mass_properties(int(id))
		out.append({"pos": bb.position / Part.MM, "size": bb.size / Part.MM, "end": bb.end / Part.MM, "vol": KCad.volume(int(id)) * 1e9, "c": (mp["center"] as Vector3) / Part.MM})
	for id in r.get("ids", []):
		KCad.release(int(id))
	return out


func api_tests() -> void:
	# 1 BOX by numbers: ONE feature, exact box
	var rec := Part.make("t")
	var id1 := Part.prim(rec, "box", {"x": 10.0, "y": 20.0, "z": 30.0, "w": 100.0, "h": 50.0, "d": 25.0})
	var s := solids(rec)
	var r1 := Part.replay(rec)
	ok((rec["features"] as Array).size() == 1 and r1["errors"].is_empty() and r1["bodies"] == 1, "1a BOX one feature, one body, no error (%d feature)" % (rec["features"] as Array).size())
	var b: Dictionary = s[0]
	ok(near(b["pos"].x, 10, 0.001) and near(b["pos"].y, 20, 0.001) and near(b["pos"].z, 30, 0.001) and near(b["size"].x, 100, 0.001) and near(b["size"].y, 50, 0.001) and near(b["size"].z, 25, 0.001),
		"1b BOX bbox exact: pos %s size %s (want 10,20,30 / 100,50,25)" % [b["pos"], b["size"]])
	ok(vnear(b["vol"], 100.0 * 50.0 * 25.0), "1c BOX volume %.4f mm3 (want 125000)" % b["vol"])
	var rc := Part.make("t")
	Part.prim(rc, "box", {"x": 0.0, "y": 0.0, "z": 0.0, "w": 40.0, "h": 20.0, "d": 10.0, "centre": true})
	var sc := solids(rc)
	ok(near(sc[0]["c"].x, 0, 0.001) and near(sc[0]["pos"].x, -20, 0.001) and near(sc[0]["pos"].z, -5, 0.001), "1d BOX centred on the origin: pos %s" % sc[0]["pos"])

	# 2 CYLINDER axis / r / length exact (all three axes), tube, cone, sphere, wedge
	for ax in ["x", "y", "z"]:
		var rcy := Part.make("t")
		Part.prim(rcy, "cylinder", {"x": 5.0, "y": 6.0, "z": 7.0, "axis": ax, "r": 20.0, "len": 150.0})
		var cy: Dictionary = solids(rcy)[0]
		var ai: int = "xyz".find(ax)
		var o3 := Vector3(5, 6, 7)
		var want_pos := o3 - Vector3(20, 20, 20)
		want_pos[ai] = o3[ai]
		var want_size := Vector3(40, 40, 40)
		want_size[ai] = 150.0
		var pos_ok := true
		var size_ok := true
		for k in 3:
			pos_ok = pos_ok and near(cy["pos"][k], want_pos[k], 0.003)
			size_ok = size_ok and near(cy["size"][k], want_size[k], 0.003)
		ok(pos_ok and size_ok and vnear(cy["vol"], PI * 400.0 * 150.0), "2a CYLINDER axis %s: pos %s size %s vol %.3f (want %s %s %.3f)" % [ax, cy["pos"], cy["size"], cy["vol"], want_pos, want_size, PI * 400.0 * 150.0])
	var rt := Part.make("t")
	Part.prim(rt, "tube", {"axis": "y", "r": 30.0, "r_in": 20.0, "len": 80.0})
	Part.prim(rt, "cone", {"x": 200.0, "axis": "z", "r": 30.0, "r2": 0.0, "len": 90.0})
	Part.prim(rt, "sphere", {"x": 400.0, "r": 25.0})
	Part.prim(rt, "wedge", {"x": 600.0, "w": 60.0, "h": 40.0, "d": 30.0})
	var ts := solids(rt)
	ok(ts.size() == 4 and vnear(ts[0]["vol"], PI * (900.0 - 400.0) * 80.0), "2b TUBE volume %.3f (want %.3f)" % [ts[0]["vol"], PI * 500.0 * 80.0])
	ok(vnear(ts[1]["vol"], PI / 3.0 * 900.0 * 90.0) and near(ts[1]["size"].z, 90, 0.003), "2c CONE volume %.3f (want %.3f), length %.4f" % [ts[1]["vol"], PI / 3.0 * 900.0 * 90.0, ts[1]["size"].z])
	ok(vnear(ts[2]["vol"], 4.0 / 3.0 * PI * 25.0 * 25.0 * 25.0) and near(ts[2]["c"].x, 400, 0.001), "2d SPHERE volume %.3f centre x %.4f" % [ts[2]["vol"], ts[2]["c"].x])
	ok(vnear(ts[3]["vol"], 60.0 * 40.0 * 30.0 / 2.0) and near(ts[3]["size"].x, 60, 0.001) and near(ts[3]["size"].y, 40, 0.001) and near(ts[3]["size"].z, 30, 0.001) and near(ts[3]["pos"].x, 600, 0.001),
		"2e WEDGE volume %.3f (want 36000), size %s" % [ts[3]["vol"], ts[3]["size"]])
	var bad := Part.make("t")
	var idb := Part.prim(bad, "box", {"w": 0.0, "h": 10.0, "d": 10.0})
	ok(String(Part.replay(bad)["errors"].get(idb, "")) != "", "2f BAD numbers (width 0) say why: %s" % Part.replay(bad)["errors"].get(idb, ""))

	# 3 PLANE by 3 points: the normal exact, a sketch on it extrudes along the normal
	var rp := Part.make("t")
	var pid := Part.add_plane(rp, "pts", {"p": [[0, 0, 0], [100, 0, 0], [0, 100, 100]]})
	var pl := Part.resolve_plane(rp, pid)
	var want_n := Vector3(0, -1, 1).normalized()
	ok((pl["n"] as Vector3).distance_to(want_n) < 1e-9 and (pl["o"] as Vector3).length() < 1e-12, "3a PLANE 3 points: normal %s (want %s)" % [pl["n"], want_n])
	var sk := Part.new_feature(rp, "sketch", {"plane": pid, "ents": [{"k": "rect", "a": [0, 0], "b": [20, 30]}], "dims": []})
	(rp["features"] as Array).append(sk)
	var ex := Part.new_feature(rp, "extrude", {"sketch": sk["id"], "dist": 10.0, "both": false, "op": "new"})
	(rp["features"] as Array).append(ex)
	var rr := Part.replay(rp)
	var sp := solids(rp)
	var cen: Vector3 = sp[0]["c"]
	var o_mm := (pl["o"] as Vector3) / Part.MM
	var want_c := o_mm + (pl["x"] as Vector3) * 10.0 + (pl["y"] as Vector3) * 15.0 + (pl["n"] as Vector3) * 5.0
	ok(rr["errors"].is_empty() and vnear(sp[0]["vol"], 6000.0) and cen.distance_to(want_c) < 0.001, "3b PLANE sketch 20x30 extruded 10 along the normal: vol %.3f, centre %s (want %s)" % [sp[0]["vol"], cen, want_c])
	var fcol := Part.make("t")
	var pc := Part.add_plane(fcol, "pts", {"p": [[0, 0, 0], [100, 0, 0], [200, 0, 0]]})
	var skc := Part.new_feature(fcol, "sketch", {"plane": pc, "ents": [{"k": "rect", "a": [0, 0], "b": [5, 5]}], "dims": []})
	(fcol["features"] as Array).append(skc)
	var rcl := Part.replay(fcol)
	ok(String(rcl["errors"].get(pc, "")) != "" and String(rcl["errors"].get(skc["id"], "")) != "", "3c PLANE 3 points in a line: refused: %s" % rcl["errors"].get(pc, ""))

	# 4 ANGLED plane 30 deg about the base plane's x axis, and about a given edge, and through an edge
	var ra := Part.make("t")
	var a1 := Part.add_plane(ra, "angle", {"base": "front", "edge": "x", "deg": 30.0})
	var a2 := Part.add_plane(ra, "angle", {"base": "top", "edge": [[0, 0, 0], [0, 0, 100]], "deg": 30.0, "mm": 0.0})
	var a3 := Part.add_plane(ra, "edge", {"a": [0, 0, 0], "b": [100, 0, 0], "deg": 30.0})
	var a4 := Part.add_plane(ra, "angle", {"base": a1, "edge": "x", "deg": 30.0})
	var n_front := Part.plane("front")["n"] as Vector3
	var n_top := Part.plane("top")["n"] as Vector3
	var d1 := rad_to_deg((Part.resolve_plane(ra, a1)["n"] as Vector3).angle_to(n_front))
	var d2 := rad_to_deg((Part.resolve_plane(ra, a2)["n"] as Vector3).angle_to(n_top))
	var pe := Part.resolve_plane(ra, a3)
	var d3 := rad_to_deg((pe["n"] as Vector3).angle_to(Part.plane("right")["n"] as Vector3))   # the 0 deg half plane holds the x edge and straight up: the Front plane (normal +Z)
	var d3b := rad_to_deg((pe["n"] as Vector3).angle_to(n_front))
	var d4 := rad_to_deg((Part.resolve_plane(ra, a4)["n"] as Vector3).angle_to(n_front))
	ok(near(d1, 30.0, 0.01) and near(d2, 30.0, 0.01) and near(d3b, 30.0, 0.01) and near(d4, 60.0, 0.01),
		"4a ANGLE front/x 30 deg: %.4f; top about an edge 30 deg: %.4f; through an edge 30 deg from the vertical plane: %.4f; plane of a plane +30 = %.4f deg" % [d1, d2, d3b, d4])
	ok(d3 > 0.0 and (pe["x"] as Vector3).distance_to(Vector3.RIGHT) < 1e-9 and absf((pe["n"] as Vector3).dot(pe["x"] as Vector3)) < 1e-9, "4b EDGE plane: x runs along the edge, normal square to it")
	var fn := Part.add_plane(ra, "face", {"o": [10, 20, 30], "n": [0, 0, 5]})
	var fp := Part.resolve_plane(ra, fn)
	ok((fp["n"] as Vector3).distance_to(Vector3.BACK) < 1e-9 and (fp["o"] as Vector3).distance_to(Vector3(0.01, 0.02, 0.03)) < 1e-7, "4c FACE plane: origin and normal kept")
	ok(Part.plane_words(ra, a1).find("30") >= 0 and Part.plane_words(ra, pid.replace(pid, a2)).find("30") >= 0, "4d the browser words say the angle: %s" % Part.plane_words(ra, a1))

	# 5 SAFETY: intersect leaves C alone
	var ri := Part.make("t")
	Part.prim(ri, "box", {"x": 0.0, "y": 0.0, "z": 0.0, "w": 100.0, "h": 100.0, "d": 100.0, "name": "A"})
	Part.prim(ri, "box", {"x": 50.0, "y": 0.0, "z": 0.0, "w": 100.0, "h": 100.0, "d": 100.0, "name": "B"})
	Part.prim(ri, "box", {"x": 500.0, "y": 0.0, "z": 0.0, "w": 10.0, "h": 10.0, "d": 10.0, "name": "C"})
	var rcb := ri.duplicate(true)
	var cf := Part.new_feature(rcb, "combine", {"target": 0, "tools": [1], "op": "intersect", "keep": false})
	(rcb["features"] as Array).append(cf)
	var sci := solids(rcb)
	ok(sci.size() == 2 and vnear(sci[0]["vol"], 50.0 * 100.0 * 100.0) and vnear(sci[1]["vol"], 1000.0), "5a COMBINE intersect A with B: A = %.3f (want 500000), C untouched %.4f (want 1000), %d bodies" % [sci[0]["vol"], sci[1]["vol"], sci.size()])
	var rx := ri.duplicate(true)
	var sx := Part.new_feature(rx, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [-10, -200], "b": [80, 200]}], "dims": []})
	(rx["features"] as Array).append(sx)
	var xe := Part.new_feature(rx, "extrude", {"sketch": sx["id"], "dist": 100.0, "both": false, "op": "intersect"})
	(rx["features"] as Array).append(xe)
	var rxr := Part.replay(rx)
	var sxs := solids(rx)
	ok(rxr["errors"].is_empty() and sxs.size() == 3 and vnear(sxs[2]["vol"], 1000.0) and vnear(sxs[0]["vol"], 80.0 * 100.0 * 100.0),
		"5b EXTRUDE intersect keeps C: %d bodies, C %.4f, A trimmed %.3f (want 800000), warning: %s" % [sxs.size(), sxs[2]["vol"] if sxs.size() > 2 else -1.0, sxs[0]["vol"], rxr["warnings"].get(xe["id"], "(none)")])
	ok(String(rxr["warnings"].get(xe["id"], "")).find("stay") >= 0, "5c EXTRUDE intersect says how many bodies stayed")
	var ry := rx.duplicate(true)
	ry["features"][-1]["scope"] = "all"
	var ryr := Part.replay(ry)
	ok(int(ryr["bodies"]) == 2 and String(ryr["warnings"].get(xe["id"], "")).find("removed 1") >= 0, "5d scope all (old behaviour) removes C and SAYS so: %d bodies, %s" % [ryr["bodies"], ryr["warnings"].get(xe["id"], "")])
	var rz := rx.duplicate(true)
	rz["features"][-1]["targets"] = [1]
	var rzs := solids(rz)
	ok(rzs.size() == 3 and vnear(rzs[0]["vol"], 1000000.0) and vnear(rzs[1]["vol"], 30.0 * 100.0 * 100.0), "5e a target list [B]: A %.1f untouched, B trimmed %.1f (want 1000000 / 300000)" % [rzs[0]["vol"], rzs[1]["vol"]])
	var rm := ri.duplicate(true)
	var sm := Part.new_feature(rm, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [900, 900], "b": [950, 950]}], "dims": []})
	(rm["features"] as Array).append(sm)
	(rm["features"] as Array).append(Part.new_feature(rm, "extrude", {"sketch": sm["id"], "dist": 10.0, "both": false, "op": "intersect"}))
	var rmr := Part.replay(rm)
	ok(int(rmr["bodies"]) == 3 and not rmr["errors"].is_empty(), "5f an intersect that misses everything is an error and changes nothing: %d bodies, %s" % [rmr["bodies"], rmr["errors"].values()])

	# 6 BOW-TIE
	var rb := Part.make("t")
	var bt := Part.new_feature(rb, "sketch", {"plane": "front", "dims": [], "ents": [
		{"k": "line", "a": [0, 0], "b": [100, 100]}, {"k": "line", "a": [100, 100], "b": [100, 0]}, {"k": "line", "a": [100, 0], "b": [0, 100]}, {"k": "line", "a": [0, 100], "b": [0, 0]}]})
	(rb["features"] as Array).append(bt)
	(rb["features"] as Array).append(Part.new_feature(rb, "extrude", {"sketch": bt["id"], "dist": 10.0, "both": false, "op": "new"}))
	var rbr := Part.replay(rb)
	var msg := String(rbr["errors"].get(bt["id"], ""))
	ok(msg.find("(50, 50)") >= 0 and int(rbr["bodies"]) == 0, "6a BOW-TIE refused at the sketch with the crossing point: %s" % msg)
	ok(String(rbr["errors"].get(rb["features"][1]["id"], "")) == msg, "6b the extrude of it says the same thing (not a late kernel error)")
	var rg := Part.make("t")
	var gs := Part.new_feature(rg, "sketch", {"plane": "front", "dims": [], "ents": [
		{"k": "line", "a": [0, 0], "b": [100, 0]}, {"k": "line", "a": [100, 0], "b": [100, 100]}, {"k": "line", "a": [100, 100], "b": [0, 100]}, {"k": "line", "a": [0, 100], "b": [0, 0]}]})
	(rg["features"] as Array).append(gs)
	(rg["features"] as Array).append(Part.new_feature(rg, "extrude", {"sketch": gs["id"], "dist": 10.0, "both": false, "op": "new"}))
	var rgr := Part.replay(rg)
	ok(rgr["errors"].is_empty() and int(rgr["bodies"]) == 1, "6c a good square is not refused; an open chain is never refused")

	# 7 MEASURE: the hall's platform + 9 stair steps + 16 columns, the same 26 solids, before (plane + sketch + extrude each) and after (one prim each)
	var before := Part.make("hall_before")
	var after := Part.make("hall_after")
	var jobs: Array = [["box", {"x": -2100.0, "y": 0.0, "z": -1500.0, "w": 4200.0, "h": 1300.0, "d": 3000.0}]]
	for i in 9:
		jobs.append(["box", {"x": -2100.0, "y": 144.0 * i, "z": 1500.0 + 300.0 * (8 - i), "w": 4200.0, "h": 144.0, "d": 300.0}])
	for i in 16:
		jobs.append(["cylinder", {"x": -1800.0 + 240.0 * i, "y": 1300.0, "z": 0.0, "axis": "y", "r": 250.0, "len": 3000.0}])
	for j in jobs:
		var jf: Dictionary = j[1]
		var kind: String = j[0]
		if kind == "box":
			var offp := Part.new_feature(before, "plane", {"from": "top", "mm": jf["y"]})
			(before["features"] as Array).append(offp)
			var skb := Part.new_feature(before, "sketch", {"plane": offp["id"], "dims": [], "ents": [{"k": "rect", "a": [jf["x"], -(jf["z"] + jf["d"])], "b": [jf["x"] + jf["w"], -jf["z"]]}]})
			(before["features"] as Array).append(skb)
			(before["features"] as Array).append(Part.new_feature(before, "extrude", {"sketch": skb["id"], "dist": jf["h"], "both": false, "op": "new"}))
		else:
			var offc := Part.new_feature(before, "plane", {"from": "top", "mm": jf["y"]})
			(before["features"] as Array).append(offc)
			var skc2 := Part.new_feature(before, "sketch", {"plane": offc["id"], "dims": [], "ents": [{"k": "circle", "c": [jf["x"], -jf["z"]], "r": jf["r"]}]})
			(before["features"] as Array).append(skc2)
			(before["features"] as Array).append(Part.new_feature(before, "extrude", {"sketch": skc2["id"], "dist": jf["len"], "both": false, "op": "new"}))
		Part.prim(after, kind, jf)
	var nb := (before["features"] as Array).size()
	var na := (after["features"] as Array).size()
	var vb := 0.0
	var va := 0.0
	for q in solids(before):
		vb += q["vol"]
	var sa := solids(after)
	for q in sa:
		va += q["vol"]
	ok(vnear(vb, va) and sa.size() == 26, "7a MEASURE the hall's platform + stairs + 16 columns (26 solids): before %d features, after %d features; volume before %.1f after %.1f mm3 (%d bodies)" % [nb, na, vb, va, sa.size()])
	ok(na * 3 == nb, "7b MEASURE ratio: %d -> %d features (3.0x fewer)" % [nb, na])

	# 12 OLD PARTS replay unchanged: the Anzani radial engine record (219 features) with the new sketch / plane checks on and off
	var ejs: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s229_engine_part.json"))
	var eng := Part.from_file(ejs)
	Part.PPRIM.checks_off = true
	var e_off := Part.replay(eng)
	Part.PPRIM.checks_off = false
	var e_on := Part.replay(eng)
	ok((eng["features"] as Array).size() == 219 and int(e_on["bodies"]) == 49 and int(e_off["bodies"]) == 49 and e_on["errors"].size() == e_off["errors"].size() and e_on["warnings"].is_empty(),
		"12a OLD the engine record: %d features, %d bodies (checks off: %d), %d failed steps (off: %d), %d warnings" % [(eng["features"] as Array).size(), e_on["bodies"], e_off["bodies"], e_on["errors"].size(), e_off["errors"].size(), e_on["warnings"].size()])
	ok(near(float(e_on["volume"]), float(e_off["volume"]), 1e-12) and float(e_on["volume"]) > 0.0, "12b OLD the engine volume is the same with the new checks on: %.9f vs %.9f m3" % [e_on["volume"], e_off["volume"]])


## a tool of the Part ribbon: a real click when it is on the bar, else (the bar at 1280 wide folds its last tools into More) More's menu entry
func press_tool(nm: String, label: String) -> bool:
	var b: Button = root.find_child("part_tool_" + nm, true, false) as Button
	if b != null and b.is_visible_in_tree():
		await click_ctl(b)
		return true
	if b != null and (nm in ["offset_plane", "primitive"]):   # the rarer tools live under the CREATE caption's menu: the same pick as that menu's (main.gd _run_tool)
		m._run_tool(b, m.ui_more)
		await idle(6)
		return false
	await click_ctl(m.ui_more)
	var pm: PopupMenu = m.ui_more.get_popup()
	for i in pm.item_count:
		if pm.get_item_text(i) == label:
			pm.id_pressed.emit(pm.get_item_id(i))
			await idle(6)
			return false
	var have := []
	for i in pm.item_count:
		have.append(pm.get_item_text(i))
	print("press_tool: no '%s' in More: %s; bar button %s" % [label, have, b])
	return false


func pu() -> PartUI:
	return m.bld.part


func setf(le: LineEdit, v: Variant) -> void:
	le.text = str(v)
	le.text_changed.emit(le.text)


func nprim(rec: Dictionary) -> int:
	return Part.count_of(rec, "prim")


func ui_tests() -> void:
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
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.S.part = {}
	pu().set_on(false)
	await idle(4)
	await click_ctl(pu().part_btn)   # the Expert Part workspace
	await idle(10)

	# 8 EXPERT Primitive dialog: typed fields, ONE step, ONE undo
	var u0: int = m.undo.size()
	var on_bar := await press_tool("primitive", "Primitive")
	ok(root.find_child("part_prim_kind", true, false) != null, "8a EXPERT the Primitive tool opens its dialog (%s)" % ("on the ribbon" if on_bar else "from the More menu: the 1280 px bar folds its last tools there, like Extrude and Combine"))
	await idle(6)
	var kind_o: OptionButton = root.find_child("part_prim_kind", true, false) as OptionButton
	ok(kind_o != null and kind_o.is_visible_in_tree(), "8b EXPERT the dialog shows a Shape list and typed fields")
	setf(root.find_child("part_prim_x", true, false), 10)
	setf(root.find_child("part_prim_y", true, false), 20)
	setf(root.find_child("part_prim_z", true, false), 30)
	setf(root.find_child("part_prim_w", true, false), 100)
	setf(root.find_child("part_prim_h", true, false), 50)
	setf(root.find_child("part_prim_d", true, false), 25)
	setf(root.find_child("part_prim_name", true, false), "Plinth")
	await idle(4)
	await shot("expert_primitive_dialog")
	await click_ctl(root.find_child("part_ok", true, false) as Button)
	await idle(20)
	var rec: Dictionary = m.S.part
	var bb: AABB = pu().res.get("aabb", AABB())
	ok(nprim(rec) == 1 and (rec["features"] as Array).size() == 1 and m.undo.size() == u0 + 1, "8c EXPERT one OK = one feature (%d) and one undo step (%d)" % [(rec["features"] as Array).size(), m.undo.size() - u0])
	ok(near(bb.position.x / Part.MM, 10, 0.001) and near(bb.position.y / Part.MM, 20, 0.001) and near(bb.position.z / Part.MM, 30, 0.001) and near(bb.size.x / Part.MM, 100, 0.001) and near(bb.size.y / Part.MM, 50, 0.001) and near(bb.size.z / Part.MM, 25, 0.001) and String(rec["features"][0]["name"]) == "Plinth",
		"8d EXPERT the box typed in the dialog: bbox pos %s size %s mm, named %s" % [bb.position / Part.MM, bb.size / Part.MM, rec["features"][0]["name"]])
	# a cylinder along Y from the same dialog
	await press_tool("primitive", "Primitive")
	await idle(6)
	kind_o = root.find_child("part_prim_kind", true, false) as OptionButton
	kind_o.select(1)
	kind_o.item_selected.emit(1)
	await idle(4)
	setf(root.find_child("part_prim_x", true, false), 300)
	setf(root.find_child("part_prim_y", true, false), 0)
	setf(root.find_child("part_prim_z", true, false), 0)
	setf(root.find_child("part_prim_r", true, false), 20)
	setf(root.find_child("part_prim_len", true, false), 150)
	await idle(4)
	await click_ctl(root.find_child("part_ok", true, false) as Button)
	await idle(20)
	rec = m.S.part
	var cyl := solids(rec)
	ok(nprim(rec) == 2 and cyl.size() == 2 and vnear(cyl[1]["vol"], PI * 400.0 * 150.0) and near(cyl[1]["size"].y, 150.0, 0.003) and near(cyl[1]["pos"].y, 0.0, 0.003), "8e EXPERT cylinder axis Y r 20 len 150: vol %.3f size %s" % [cyl[1]["vol"], cyl[1]["size"]])
	await shot("expert_two_primitives")
	m._undo()
	await idle(10)
	ok(nprim(m.S.part) == 1, "8f EXPERT one undo takes the last primitive away (%d left)" % nprim(m.S.part))
	m._redo()
	await idle(10)
	ok(nprim(m.S.part) == 2, "8g EXPERT redo brings it back")
	var file := Part.to_file(m.S.part)
	var js: Variant = JSON.parse_string(JSON.stringify(file))
	var back := Part.from_file(js)
	var v1 := float(Part.replay(m.S.part)["volume"])
	var v2 := float(Part.replay(back)["volume"])
	ok(nprim(back) == 2 and near(v1, v2, 1e-12) and v1 > 0.0, "8h SAVED the part file (JSON round trip) replays the same: %d prim steps, volume %.9f vs %.9f m3" % [nprim(back), v1, v2])

	# 9 EXPERT plane through 3 points (dialog), listed in the browser, a sketch on it
	var n0: int = Part.count_of(m.S.part, "plane")
	var u1: int = m.undo.size()
	await press_tool("offset_plane", "Offset plane")
	await idle(6)
	var mo: OptionButton = root.find_child("part_plane_mode", true, false) as OptionButton
	ok(mo != null and mo.item_count == 5, "9a PLANE the dialog offers %d ways to make a plane" % (mo.item_count if mo != null else 0))
	mo.select(1)
	mo.item_selected.emit(1)
	await idle(4)
	var pts := [[0, 0, 0], [100, 0, 0], [0, 100, 100]]
	for i in 3:
		for k in 3:
			setf(root.find_child("part_plane_p%d_%s" % [i + 1, "xyz"[k]], true, false), pts[i][k])
	await idle(4)
	await shot("expert_plane_3pts_dialog")
	await click_ctl(root.find_child("part_ok", true, false) as Button)
	await idle(12)
	var planes: Array = (m.S.part["features"] as Array).filter(func(f): return f["t"] == "plane")
	ok(planes.size() == n0 + 1 and m.undo.size() == u1 + 1, "9b PLANE one OK = one plane feature, one undo step")
	var plid := String(planes[-1]["id"])
	var pln := Part.resolve_plane(m.S.part, plid)
	ok((pln["n"] as Vector3).distance_to(Vector3(0, -1, 1).normalized()) < 1e-9, "9c PLANE normal exact %s" % pln["n"])
	var pb: Button = root.find_child("part_plane_" + plid, true, false) as Button
	ok(pb != null and pb.is_visible_in_tree(), "9d PLANE listed in the browser as a button (%s)" % (pb.text if pb != null else "missing"))
	await click_ctl(pb)
	await idle(8)
	ok(pu().sk != "" and (pu()._plane()["n"] as Vector3).distance_to(pln["n"]) < 1e-9, "9e PLANE a click on it starts a sketch ON that plane")
	# 10 BOW-TIE drawn with real clicks: the closing line is refused, red, with the place
	await click_ctl(pu().finish_btn)   # a fresh sketch on the Front plane: face-on, so the clicks land where the numbers say
	await idle(6)
	await click_ctl(root.find_child("part_plane_front", true, false) as Button)
	await idle(8)
	await click_ctl(root.find_child("part_tool_line", true, false) as Button)
	await idle(4)
	var corners := [Vector2(0, 0), Vector2(80, 80), Vector2(80, 0), Vector2(0, 80), Vector2(0, 0)]
	for c in corners:
		var sp: Vector2 = pu().scr(c)
		await ev_move(sp, false)
		await ev_mouse(sp, true)
		await ev_mouse(sp, false)
		await idle(2)
	var ents: Array = pu()._sk()["ents"]
	var cm: Dictionary = pu().cross_mark
	ok(ents.size() == 3 and not cm.is_empty() and near(float(cm["at"][0]), 40.0, 0.01) and near(float(cm["at"][1]), 40.0, 0.01), "10a BOW-TIE the closing line is refused: %d lines kept, crossing at %s" % [ents.size(), cm.get("at", "none")])
	await shot("bowtie_refused_red")
	pu().finish_sketch()
	await idle(4)

	# 11 EASY: By numbers on the Parts > Type it page
	m.S.part = {}
	pu().set_on(false)
	await idle(4)
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(30)
	await click_ctl(root.find_child("easypart_chip_parts", true, false) as Button)
	await idle(6)
	await open_group_of(root.find_child("easypart_lib_Type it", true, false) as Button)
	await click_ctl(root.find_child("easypart_lib_Type it", true, false) as Button)
	await idle(10)
	var nb: Button = root.find_child("easypart_num_kind_box", true, false) as Button
	ok(nb != null and nb.is_visible_in_tree(), "11a EASY the By numbers row shows on the Type it page")
	var e0: int = m.undo.size()
	setf(root.find_child("easypart_num_x", true, false), 0)
	setf(root.find_child("easypart_num_y", true, false), 0)
	setf(root.find_child("easypart_num_z", true, false), 0)
	setf(root.find_child("easypart_num_w", true, false), 120)
	setf(root.find_child("easypart_num_h", true, false), 40)
	setf(root.find_child("easypart_num_d", true, false), 60)
	var scr: Node = root.find_child("easypart_num_add", true, false)
	while scr != null and not scr is ScrollContainer:
		scr = scr.get_parent()
	if scr != null:   # the page scrolls (the panel is full at 1280 x 720): bring the row into view like the user does
		(scr as ScrollContainer).ensure_control_visible(root.find_child("easypart_num_add", true, false) as Control)
	await idle(6)
	await shot("easy_by_numbers_box")
	await click_ctl(root.find_child("easypart_num_add", true, false) as Button)
	await idle(25)
	rec = m.S.part
	bb = pu().res.get("aabb", AABB())
	ok(nprim(rec) == 1 and m.undo.size() == e0 + 1 and near(bb.size.x / Part.MM, 120, 0.001) and near(bb.size.y / Part.MM, 40, 0.001) and near(bb.size.z / Part.MM, 60, 0.001),
		"11b EASY Add it: one prim step, one undo step (%d), box %s mm" % [m.undo.size() - e0, bb.size / Part.MM])
	await click_ctl(root.find_child("easypart_num_kind_cylinder", true, false) as Button)
	await idle(4)
	setf(root.find_child("easypart_num_x", true, false), 300)
	setf(root.find_child("easypart_num_r", true, false), 25)
	setf(root.find_child("easypart_num_len", true, false), 90)
	await click_ctl(root.find_child("easypart_num_add", true, false) as Button)
	await idle(25)
	rec = m.S.part
	var es := solids(rec)
	ok(nprim(rec) == 2 and es.size() == 2 and vnear(es[1]["vol"], PI * 625.0 * 90.0) and near(es[1]["size"].y, 90.0, 0.003) and near(es[1]["pos"].x, 275.0, 0.003),
		"11c EASY typed cylinder: vol %.3f, size %s, pos %s" % [es[1]["vol"], es[1]["size"], es[1]["pos"]])
	await shot("easy_by_numbers_two")


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	api_tests()
	await ui_tests()
	print("s229: %d fail" % fails)
	quit(0 if fails == 0 else 1)

## item 239 grouped the library chips under group tabs: open the tab that holds a chip before a real click on it (navigation only)
func open_group_of(c: Control) -> void:
	if c == null or c.is_visible_in_tree():
		return
	for g in root.find_children("easypart_libgroup_*", "Button", true, false):
		var fl := root.find_child("easypart_libchips_" + (g as Button).text, true, false)
		if fl != null and fl.is_ancestor_of(c):
			await click_ctl(g)
			return
