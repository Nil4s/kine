extends SceneTree
## godot --path . --position 4000,4000 -s tests/s222_test.gd     (item 222 WORDS FOR MORE THAN HOUSES: scripts/build/hall_words.gd + trade_words.gd; needs the CAD DLL)
## Every sentence is checked by numbers read back from the kernel (counts, sizes, positions, names), not by its own reply.
##   1 SENTENCES  platform, stair, hall + door, columns (row / bays / around), roofs, wall around, path, tube, repeat, paint
##   2 TRADE      2x4, 4x8 sheet, 3/4 ply, M6 x 16, 1/4-20, SC1 / SC4 / KW1, Brazilian lumber: the real spec, said back; unknown listed
##   3 CHECK      "check the pistons fit the bores" returns 221's ISO 286 verdict text; an assertion line returns 220's verdict
##   4 RULES      unknown words listed, a typo asks ("colums" -> did you mean columns?), BuildWords' typo list knows columns
##   5 HALL       a 15-sentence script on the main node: one undo step each, a recognisable hall; shot to out/222 (looked at by hand)
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/222"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func box_mm(rec: Dictionary) -> AABB:
	var r := Part.replay(rec)
	var bb: AABB = r["aabb"]
	return AABB(bb.position * 1000.0, bb.size * 1000.0)


func nbod(rec: Dictionary) -> int:
	return int(Part.replay(rec)["bodies"])


func say(rec: Dictionary, text: String) -> Dictionary:
	var r := HallWords.run_on(rec, text)
	print("   '%s' -> %s %s" % [text, "ok" if r["ok"] else "REFUSED", (String(r["say"]) if r["ok"] else String(r["error"])).left(260)])
	return r


func named_boxes(rec: Dictionary, sub: String) -> Array:
	var M := PartFacts.build(rec)
	var out := []
	for i in M.n:
		if String(M.labels[i]).to_lower().contains(sub.to_lower()):
			out.append(M.box(i))
	M.release()
	return out


func fit_part(shaft_d: float, hole_d: float) -> Dictionary:
	var rec := Part.make("fit")
	var f1 := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [40, 40]}], "dims": [], "name": "Bore block sketch"})
	(rec["features"] as Array).append(f1)
	(rec["features"] as Array).append(Part.new_feature(rec, "extrude", {"sketch": f1["id"], "dist": 20, "both": false, "op": "new", "name": "Bore block"}))
	var f2 := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": [20, 20], "r": hole_d * 0.5}], "dims": [], "name": "Hole sketch"})
	(rec["features"] as Array).append(f2)
	(rec["features"] as Array).append(Part.new_feature(rec, "extrude", {"sketch": f2["id"], "dist": 30, "both": false, "op": "cut", "name": "Hole"}))
	var f3 := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": [20, 20], "r": shaft_d * 0.5}], "dims": [], "name": "Piston sketch"})
	(rec["features"] as Array).append(f3)
	(rec["features"] as Array).append(Part.new_feature(rec, "extrude", {"sketch": f3["id"], "dist": 30, "both": false, "op": "new", "name": "Piston"}))
	return rec


func feats(rec: Dictionary, t: String) -> Array:
	return (rec["features"] as Array).filter(func(f): return String(f.get("t", "")) == t)


func _init() -> void:
	if not Part.available():
		print("FAIL no CAD DLL")
		quit(1)
		return
	await main_run()


func main_run() -> void:
	# ------------------------------------------------------------------ 1 SENTENCES
	var rec := {}
	var r := say(rec, "a platform 21 x 14 m, 1.3 m high")
	rec = r["rec"]
	var bb := box_mm(rec)
	ok(bool(r["ok"]) and nbod(rec) == 1 and near(bb.size.x, 21000, 1) and near(bb.size.y, 1300, 1) and near(bb.size.z, 14000, 1) and near(bb.position.x, -10500, 1) and near(bb.position.y, 0, 1),
		"1 platform: 1 body, %s x %s x %s mm at x %s y %s" % [bb.size.x, bb.size.y, bb.size.z, bb.position.x, bb.position.y])
	r = say(rec, "a stair of 9 steps up the front, 4 m wide")
	rec = r["rec"]
	var sb := named_boxes(rec, "stair")
	var s0 := (sb[0] as AABB) if not sb.is_empty() else AABB()
	ok(bool(r["ok"]) and nbod(rec) == 2 and sb.size() == 1 and near(s0.size.x, 4000, 1) and near(s0.size.z, 2700, 1) and near(s0.size.y, 1300, 1) and near(s0.position.z, 7000, 1),
		"1 stair: one body, %s wide, %s deep, %s high, starts at z %s (9 steps of 300 at the platform front z 7000)" % [s0.size.x, s0.size.z, s0.size.y, s0.position.z])
	var hr := say(rec, "a hall 18 x 10 m, 5 m tall with a door 2.4 m wide")
	var rec_hall: Dictionary = hr["rec"]
	var hb := named_boxes(rec_hall, "hall")
	var h0 := (hb[0] as AABB) if not hb.is_empty() else AABB()
	var res_h := Part.replay(rec_hall)
	var hall_vol: float = float(res_h["volume"]) - (21.0 * 14.0 * 1.3)   # m3, platform taken off (stair is a little more)
	ok(bool(hr["ok"]) and nbod(rec_hall) == 3 and hb.size() == 1 and near(h0.size.x, 18000, 1) and near(h0.size.y, 5000, 1) and near(h0.position.y, 1300, 1) and hall_vol < 18.0 * 10.0 * 5.0 * 0.25 + 6.0,
		"1 hall: one body %s x %s x %s mm standing at y %s (on the platform), hollow (stair + hall %.1f m3 against %.1f solid)" % [h0.size.x, h0.size.z, h0.size.y, h0.position.y, hall_vol, 900.0])
	rec = hr["rec"]
	r = say(rec, "6 red columns 0.5 wide along the front")
	var rec_c: Dictionary = r["rec"]
	var cb := named_boxes(rec_c, "column")
	var xs := cb.map(func(b): return (b as AABB).position.x + (b as AABB).size.x * 0.5)
	xs.sort()
	var gaps := []
	for i in range(1, xs.size()):
		gaps.append(xs[i] - xs[i - 1])
	var even: bool = not gaps.is_empty() and gaps.all(func(g): return near(g, gaps[0], 0.5))
	var apps := feats(rec_c, "appear").size()
	var c0 := (cb[0] as AABB) if not cb.is_empty() else AABB()
	ok(bool(r["ok"]) and cb.size() == 6 and near(c0.size.x, 500, 1) and near(c0.size.y, 5000, 1) and even and apps >= 6 and near(c0.position.z + 250.0, 5000.0 + 300.0 + 250.0, 1),
		"1 columns: %d bodies, %s wide, %s tall, even gaps %s, %d paint steps, centre z %s" % [cb.size(), c0.size.x, c0.size.y, str(gaps), apps, c0.position.z + 250.0])
	r = say({}, "5 bays of 3.6 m with columns 0.4 wide, 4 m tall")
	cb = named_boxes(r["rec"], "column")
	xs = cb.map(func(b): return (b as AABB).position.x + (b as AABB).size.x * 0.5)
	xs.sort()
	ok(bool(r["ok"]) and cb.size() == 6 and near(xs[1] - xs[0], 3600, 1) and near(xs[5] - xs[0], 18000, 1) and near((cb[0] as AABB).size.x, 400, 1) and near((cb[0] as AABB).size.y, 4000, 1),
		"1 bays: 5 bays of 3.6 m = 6 columns, span %s mm" % (xs[5] - xs[0]))
	r = say(rec_hall, "16 columns around the hall")
	cb = named_boxes(r["rec"], "column")
	ok(bool(r["ok"]) and cb.size() == 16, "1 columns around: %d column bodies (wanted 16)" % cb.size())
	var rr := say(rec_hall, "a double roof with upturned corners")
	var rec_r: Dictionary = rr["rec"]
	var roofs := feats(rec_r, "roof")
	var bbr := box_mm(rec_r)
	ok(bool(rr["ok"]) and roofs.size() == 2 and (roofs[0] as Dictionary)["type"] == "hip" and (roofs[1] as Dictionary)["type"] == "xieshan" and float((roofs[0] as Dictionary)["lift"]) > 0.0 and (roofs[0] as Dictionary)["hole"] is Array
		and bbr.end.y > 6300.0 + 3000.0 and bbr.size.x > 18000.0 and nbod(rec_r) >= 5,
		"1 double roof: 2 roof steps (%s over %s), corner lift %s, top y %s, width %s" % [(roofs[0] as Dictionary)["type"], (roofs[1] as Dictionary)["type"], (roofs[0] as Dictionary)["lift"], bbr.end.y, bbr.size.x])
	var rg := say(rec_hall, "a gable roof")
	var gr := feats(rg["rec"], "roof")
	ok(bool(rg["ok"]) and gr.size() == 1 and (gr[0] as Dictionary)["type"] == "gable" and near(float((gr[0] as Dictionary)["w"]), 18000, 1), "1 gable roof: one roof step, type gable, width 18000")
	var rw := say(rec_hall, "a wall around the platform, 2 m high, 0.3 m thick")
	var wb := named_boxes(rw["rec"], "compound wall")
	var w0 := (wb[0] as AABB) if not wb.is_empty() else AABB()
	ok(bool(rw["ok"]) and wb.size() == 1 and near(w0.size.x, 21000 + 8000, 1) and near(w0.size.z, 14000 + 8000, 1) and near(w0.size.y, 2000, 1), "1 wall around: one body %s x %s x %s" % [w0.size.x, w0.size.z, w0.size.y])
	var rp := say(rec_hall, "a path 3 m wide, 20 m long")
	var pb := named_boxes(rp["rec"], "path")
	var p0 := (pb[0] as AABB) if not pb.is_empty() else AABB()
	ok(bool(rp["ok"]) and pb.size() == 1 and near(p0.size.x, 3000, 1) and near(p0.size.z, 20000, 1) and near(p0.position.z, 9700, 1), "1 path: %s x %s starting at z %s (after the stair)" % [p0.size.x, p0.size.z, p0.position.z])
	var rt := say({}, "a tube 30 mm through 0,0,0 then 0,0,500 then 300,0,500")
	var tb := named_boxes(rt["rec"], "tube")
	var t0 := (tb[0] as AABB) if not tb.is_empty() else AABB()
	ok(bool(rt["ok"]) and tb.size() == 1 and t0.size.y >= 30.0 and t0.size.z > 480.0 and t0.size.x > 250.0, "1 tube: 1 body, box %s x %s x %s" % [t0.size.x, t0.size.y, t0.size.z])
	var rtp := say({}, "a tube 30 mm through these points")
	ok(not bool(rtp["ok"]) and String(rtp["error"]).contains("Which points"), "1 'through these points' with none picked asks which points")
	var rtq := HallWords.run_on({}, "a tube 30 mm through these points", {"points": [[0, 0, 0], [0, 0, 400]]})
	ok(bool(rtq["ok"]) and nbod(rtq["rec"]) == 1, "1 'through these points' uses the picked points")
	var rcol := say({}, "a column 0.5 wide, 4 m tall")
	rcol = say(rcol["rec"], "repeat it 12 times around")
	ok(bool(rcol["ok"]) and nbod(rcol["rec"]) == 12, "1 repeat it 12 times around: %d bodies (wanted 12 in all)" % nbod(rcol["rec"]))
	var rlin := say(say({}, "a column 0.5 wide, 4 m tall")["rec"], "repeat it 5 times along x 2000 mm apart")
	var xl := named_boxes(rlin["rec"], "column").map(func(b): return (b as AABB).position.x)
	xl.sort()
	ok(bool(rlin["ok"]) and xl.size() == 5 and near(xl[4] - xl[0], 8000, 1), "1 repeat along x: 5 bodies, span %s" % (xl[4] - xl[0] if xl.size() == 5 else -1.0))
	var rpt := say(rec_hall, "paint the roof green")
	ok(not bool(rpt["ok"]), "1 paint a roof that is not there is refused: %s" % rpt["error"])
	var rpt2 := say(rr["rec"], "make the roof green")
	ok(bool(rpt2["ok"]) and String(rpt2["say"]).contains("green"), "1 make the roof green: %s" % rpt2["say"])
	# ------------------------------------------------------------------ 2 TRADE
	var t24 := say({}, "a 2x4 1.2 m long")
	var b24 := box_mm(t24["rec"])
	ok(bool(t24["ok"]) and near(b24.size.x, 38.1, 0.2) and near(b24.size.z, 88.9, 0.2) and near(b24.size.y, 1200, 0.5) and String(t24["say"]).contains("38 x 89 mm"), "2 2x4 1.2 m long: %s x %s x %s mm, said '%s'" % [b24.size.x, b24.size.z, b24.size.y, String(t24["say"]).left(80)])
	var tsh := say({}, "a 4x8 sheet of 3/4 ply")
	var bsh := box_mm(tsh["rec"])
	ok(bool(tsh["ok"]) and near(bsh.size.x, 1219.2, 0.2) and near(bsh.size.z, 2438.4, 0.2) and near(bsh.size.y, 18.3, 0.1) and nbod(tsh["rec"]) == 1, "2 4x8 sheet of 3/4 ply: %s x %s x %s mm" % [bsh.size.x, bsh.size.z, bsh.size.y])
	var tb6 := say({}, "an M6 x 16 bolt")
	var bb6 := box_mm(tb6["rec"])
	ok(bool(tb6["ok"]) and near(bb6.size.y, 20.0, 0.1) and near(bb6.size.x, 10.0, 0.1) and String(tb6["say"]).contains("pitch 1 mm"), "2 M6 x 16: shank 16 + head 4 high = %s, head %s wide, pitch said" % [bb6.size.y, bb6.size.x])
	var tq := say({}, "a 1/4-20 bolt")
	ok(bool(tq["ok"]) and String(tq["say"]).contains("20 threads per inch") and String(tq["say"]).contains("6.35"), "2 1/4-20: 6.35 mm, 20 per inch, UNC")
	ok(TradeWords.meaning("SC1").contains("Schlage") and TradeWords.meaning("SC4").contains("Schlage") and TradeWords.meaning("KW1").contains("Kwikset"), "2 SC1 / SC4 (Schlage) and KW1 (Kwikset) are named")
	var tk := say({}, "a KW1 key")
	ok(bool(tk["ok"]) and String(tk["say"]).contains("Kwikset"), "2 'a KW1 key' says Kwikset: %s" % String(tk["say"]).left(80))
	for nm in ["caibro", "ripa", "sarrafo", "viga", "pontalete"]:
		var tbr := say({}, "a %s 2 m long" % nm)
		var bbr2 := box_mm(tbr["rec"]) if bool(tbr["ok"]) else AABB()
		var want: Dictionary = TradeWords.BR[nm]
		ok(bool(tbr["ok"]) and near(bbr2.size.x, float(want["t"]), 0.1) and near(bbr2.size.z, float(want["w"]), 0.1) and near(bbr2.size.y, 2000, 0.5), "2 %s 2 m long: %s x %s mm section" % [nm, bbr2.size.x, bbr2.size.z])
	var tu := say({}, "a 3x7 1 m long")
	ok(not bool(tu["ok"]) and String(tu["error"]).contains("3x7") and String(tu["error"]).contains("not guessed"), "2 an unknown trade size (3x7) is listed, not guessed: %s" % String(tu.get("error", "")).left(70))
	var tk2 := say({}, "a SC9 key")
	ok(not bool(tk2["ok"]) and String(tk2["error"]).to_lower().contains("sc9"), "2 an unknown key (SC9) is listed")
	# ------------------------------------------------------------------ 3 CHECK
	var fr := fit_part(19.9865, 20.0105)
	var cr := HallWords.run_on(fr, "check the pistons fit the bores")
	print("   ", cr.get("say", cr.get("error")))
	ok(bool(cr["ok"]) and String(cr["kind"]) == "check" and String(cr["say"]).contains("H7/g6") and String(cr["say"]).contains("sliding") and bool(cr.get("pass", false)), "3 check the pistons fit the bores: %s" % String(cr["say"]).left(200))
	var cr2 := HallWords.run_on(fit_part(20.0, 20.3), "check the pistons fit the bores")
	ok(bool(cr2["ok"]) and String(cr2["say"]).contains("not a standard") and not bool(cr2.get("pass", true)), "3 a 20 in 20.3 mm: no standard fit: %s" % String(cr2["say"]).left(120))
	var cr3 := HallWords.run_on(fr, "check the pistons fit the gears")
	ok(bool(cr3["ok"]) and String(cr3["say"]).contains("No round"), "3 no such hole: said plainly")
	var cr4 := HallWords.run_on(rec_c, "check count bodies like column = 6")
	print("   ", cr4.get("say", cr4.get("error")))
	ok(bool(cr4["ok"]) and bool(cr4.get("pass", false)), "3 check count: %s" % String(cr4.get("say", cr4.get("error", ""))).left(120))
	var cr5 := HallWords.run_on(rec_c, "check count bodies like column = 9")
	ok(bool(cr5["ok"]) and not bool(cr5.get("pass", true)), "3 a false count fails: %s" % String(cr5.get("say", cr5.get("error", ""))).left(120))
	var cr6 := HallWords.run_on(rec_c, "check the part")
	ok(bool(cr6["ok"]) and String(cr6["kind"]) == "check" and cr6.has("pass"), "3 check the part gives the Print-level warnings: %s" % String(cr6.get("say", cr6.get("error", ""))).left(100))
	# ------------------------------------------------------------------ 4 RULES
	var ty := HallWords.run_on({}, "6 red colums 0.5 wide")
	ok(not bool(ty["ok"]) and String(ty["error"]).contains("did you mean columns?"), "4 typo asks: %s" % ty["error"])
	var ty2 := BuildWords.parse("6 colums in a house 8 x 6 m")
	ok(not bool(ty2["ok"]) and String(ty2["error"]).contains("columns"), "4 BuildWords' typo list knows columns: %s" % String(ty2["error"]).left(90))
	var uw := say({}, "a platform 21 x 14 m, 1 m high, blorp zonk")
	ok(bool(uw["ok"]) and (uw["ignored"] as Array).has("blorp") and (uw["ignored"] as Array).has("zonk") and nbod(uw["rec"]) == 1, "4 unknown words are listed, the rest is built: %s" % str(uw["ignored"]))
	var un := say({}, "frobnicate the thing")
	ok(not bool(un["ok"]) and String(un["error"]).contains("frobnicate"), "4 a sentence of nothing known is refused with the words listed")
	ok(HallWords.claims("6 red columns", {}) and HallWords.claims("check the fit", {}) and not HallWords.claims("a 2-floor house 8 x 6 m with a door and 4 windows", {}), "4 claims(): hall words yes, a house no")
	ok(bool(BuildWords.parse("a 2-floor house 8 x 6 m with a door and 4 windows")["ok"]), "4 a plain house sentence still builds in BuildWords")
	# ------------------------------------------------------------------ 5 on the main node
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	var pu = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s222_test"))
	ss.dirs_override = ["user://s222_test"]
	ss.show_screen()
	await idle(3)
	m.build_choose.auto = true
	var card: Control = ss._cards["building"]
	var pt := card.get_global_rect().get_center()
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = pt
		e.global_position = pt
		root.push_input(e, true)
		await process_frame
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	var q: Vector2 = pu.part_btn.get_global_rect().get_center()
	for d in [true, false]:
		var e2 := InputEventMouseButton.new()
		e2.button_index = MOUSE_BUTTON_LEFT
		e2.pressed = d
		e2.position = q
		e2.global_position = q
		root.push_input(e2, true)
		await process_frame
	await idle(4)
	if not pu.on:
		pu.set_on(true)
		await idle(4)
	m.S.part = Part.make("Chinese hall temple")
	m.bld.sync()
	await idle(6)
	pu.browser.visible = false
	pu.tl.visible = false
	var script := [
		"a ground 120 x 120 m",
		"a platform 21 x 14 m, 1.3 m high",
		"a stair of 9 steps up the front, 4 m wide",
		"a hall 18 x 10 m, 5 m tall with a door 2.4 m wide",
		"6 red columns 0.5 wide along the front",
		"a double roof with upturned corners",
		"2 chiwen on the ridge ends",
		"paint the roof green",
		"paint the platform grey",
		"a wall around the platform, 2 m high, 0.4 m thick",
		"a path 3 m wide, 20 m long",
		"2 ginkgo trees 13 m tall at x -19 z 8",
		"a box hedge 0.8 m high along the path",
		"light it at 4 pm",
		"check the part"]
	var undo_ok := true
	var n_changed := 0
	for sent in script:
		var u0: int = m.undo.size()
		var f0: int = (m.S.part.get("features", []) as Array).size()
		var rs := HallWords.run(m, sent)
		await idle(2)
		var du: int = m.undo.size() - u0
		var changed: bool = (m.S.part.get("features", []) as Array).size() != f0 or String(rs.get("kind", "")) == "nature"
		print("   [%d undo] '%s' -> %s" % [du, sent, String(rs.get("say", rs.get("error", ""))).left(150)])
		if not bool(rs["ok"]):
			ok(false, "5 hall script sentence refused: '%s' %s" % [sent, rs.get("error", "")])
			continue
		if String(rs["kind"]) in ["check", "light"]:
			undo_ok = undo_ok and du == 0
		else:
			undo_ok = undo_ok and du == 1 and changed
			n_changed += 1
	ok(undo_ok and n_changed == 13, "5 each of the 13 building sentences is ONE undo step; the check and the light make none (%d changed)" % n_changed)
	var res := Part.replay(m.S.part)
	var bh: AABB = res["aabb"]
	ok(int(res["bodies"]) > 12 and (res["errors"] as Dictionary).is_empty() and (m.S.building.get("nature", []) as Array).size() >= 2, "5 the hall: %d bodies, %s x %s x %s m, %d nature items, no step errors" % [int(res["bodies"]), bh.size.x, bh.size.y, bh.size.z, (m.S.building.get("nature", []) as Array).size()])
	DirAccess.make_dir_recursive_absolute(SHOT)
	var tools := AgentTools.new(m)
	await tools.request(1, "temple_light", {"on": true, "time": 15.0, "sun_az": -50.0, "clouds": 0.4, "camera": {"pos": [0.0, 7.0, 42.0], "target": [0.0, 5.0, 0.0], "fov": 50.0}})
	await tools.request(2, "final_shot", {"out": SHOT + "/hall_front.png", "w": 1024, "h": 768, "camera": {"pos": [0.0, 7.0, 42.0], "target": [0.0, 5.0, 0.0], "fov": 50.0}})
	await tools.request(3, "final_shot", {"out": SHOT + "/hall_3q.png", "w": 1024, "h": 768, "camera": {"pos": [30.0, 14.0, 34.0], "target": [0.0, 4.0, 0.0], "fov": 50.0}})
	ok(FileAccess.file_exists(SHOT + "/hall_front.png"), "5 shot written to " + SHOT)
	var nf: int = (m.S.part["features"] as Array).size()
	var nn: int = (m.S.building.get("nature", []) as Array).size()
	m._undo()
	await idle(2)
	ok((m.S.part["features"] as Array).size() < nf or (m.S.building.get("nature", []) as Array).size() < nn, "5 one undo takes the last sentence back")
	print("s222: %d fail" % fails)
	quit(1 if fails > 0 else 0)
