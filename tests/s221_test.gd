extends SceneTree
## godot --path . --position 4000,4000 -s tests/s221_test.gd     (item 221 WARNING LEVELS: scripts/build/part_warn.gd + part_warn_ui.gd, agent_tools part_warn; builds on item 220; needs the CAD DLL)
## Every part has KNOWN answers: sizes in mm written here, expected numbers worked out by hand from the geometry or from a named standard.
##   1 LEVELS    every listed warning has a planted part; it fires at its level and at the ones above, NOT below; Off shows none; Look in Print in Engineering
##   2 CONTROL   a clean control part (a 3 degree tapered stand, named, one piece) fires nothing at Engineering
##   3 FITS      ISO 286-1/-2 (basic sizes over 18 up to 30 mm): IT6 = 13 um, IT7 = 21 um, fundamental deviations g = -7, h = 0, p = +22 um
##                 H7/g6: hole +0/+21, shaft -20/-7: clearance 0 - (-7) = 7 to 21 - (-20) = 41 um;  H7/h6: shaft -13/0: 0 to 34 um;
##                 H7/p6: shaft +22/+35: -35 to -1 um (interference). A 20 mm shaft in a 20.3 mm hole is no preferred fit.
##   4 BOLTS     an M6 bolt 10 mm into a tapped hole (engagement 10 mm, steel needs 1 x 6 = 6 mm; aluminium 1.5 x 6 = 9; wood 2 x 6 = 12), and one 3 mm in
##   5 TIPS      an L-shaped stand: foot 10 x 10 x 10 mm and an arm 80 x 20 x 10 mm: the centre of mass is 27.94 mm past the foot; weight 0.13345 kg of steel
##   6 BEAM      an aluminium bar 200 x 10 x 5 mm held at one end: stress P L / Z, bend P L^3 / (3 E I), worked out below
##   7 MUTES     per part, per warning, per kind; they survive Part.to_file / from_file; one undo step each; one undo takes them back
##   8 DOORS     agent_tools part_warn answers the same ids and texts as the panel; the panel in the real UI at each level (shots)
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/221"
const DIRT := "user://s221_test"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func add(rec: Dictionary, t: String, f: Dictionary, nm := "") -> String:
	var fields := f.duplicate()
	if nm != "":
		fields["name"] = nm
	var nf := Part.new_feature(rec, t, fields)
	(rec["features"] as Array).append(nf)
	return String(nf["id"])


func rect_body(rec: Dictionary, x0: float, y0: float, x1: float, y1: float, dist: float, nm: String, op := "new", plane := "front") -> void:
	var sk := add(rec, "sketch", {"plane": plane, "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []}, nm + " sketch")
	add(rec, "extrude", {"sketch": sk, "dist": dist, "both": false, "op": op}, nm)


func disc_body(rec: Dictionary, cx: float, cy: float, r: float, dist: float, nm: String, op := "new", plane := "front") -> void:
	var sk := add(rec, "sketch", {"plane": plane, "ents": [{"k": "circle", "c": [cx, cy], "r": r}], "dims": []}, nm + " sketch")
	add(rec, "extrude", {"sketch": sk, "dist": dist, "both": false, "op": op}, nm)


func ids_of(r: Dictionary) -> Array:
	return (r["warnings"] as Array).map(func(w): return String(w["id"]))


func has(r: Dictionary, code: String) -> bool:
	return code in ids_of(r)


# ------------------------------------------------------------------ planted parts, one per warning
func p_broken() -> Dictionary:
	var rec := Part.make("broken")
	rect_body(rec, 0, 0, 20, 20, 20, "Cube")
	add(rec, "extrude", {"sketch": "f999", "dist": 5.0, "both": false, "op": "join"}, "Bad pull")   # a sketch that does not exist
	return rec


func p_floating() -> Dictionary:
	var rec := Part.make("floating")
	rect_body(rec, 0, 0, 40, 40, 20, "Block")
	rect_body(rec, 10, 60, 30, 80, 20, "Ball")   # 20 mm above the block's top: touches nothing, not on the floor
	return rec


func p_hidden() -> Dictionary:
	var rec := Part.make("hidden")
	rect_body(rec, 0, 0, 20, 20, 20, "Cube A")
	rect_body(rec, 5, 5, 10, 10, 5, "Tiny")   # a 5 mm cube wholly inside A: 125 mm3
	return rec


func p_noname() -> Dictionary:
	var rec := Part.make("noname")
	rect_body(rec, 0, 0, 20, 20, 20, "Cube")
	rect_body(rec, 30, 0, 50, 20, 20, "")      # keeps the automatic name Extrude2
	return rec


func p_dark() -> Dictionary:
	var rec := Part.make("dark")
	rect_body(rec, 0, 0, 20, 20, 20, "Cube")
	add(rec, "appear", {"body": 0, "preset": "Paint", "color": [0.01, 0.01, 0.01]}, "Paint it black")
	return rec


func p_thin() -> Dictionary:
	var rec := Part.make("thin")
	rect_body(rec, 0, 0, 40, 40, 0.5, "Plate")   # 0.5 mm thick: under the 0.8 mm wall rule
	return rec


func p_overhang() -> Dictionary:
	var rec := Part.make("overhang")
	rect_body(rec, 0, 0, 10, 20, 10, "Tee")                # the post
	rect_body(rec, -30, 20, 40, 30, 10, "Arm", "join")     # the arm: 30 mm each side of the post, its underside faces down
	return rec


func p_speck() -> Dictionary:
	var rec := Part.make("speck")
	rect_body(rec, 0, 0, 40, 40, 20, "Block")
	rect_body(rec, 15, 40, 15.6, 40.6, 0.6, "Speck")   # 0.6 mm cube sitting on the block
	return rec


func open_cube() -> Dictionary:
	# a cube of 10 mm with its top face missing: 10 triangles, 4 open edges
	var v := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 10, 0), Vector3(0, 0, 10), Vector3(10, 0, 10), Vector3(10, 10, 10), Vector3(0, 10, 10)])
	var t := PackedInt32Array([0, 2, 1, 0, 3, 2, 0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7])
	return {"v": v, "t": t, "name": "Open cube", "color": null}


func fit_part(shaft_d: float, hole_d: float) -> Dictionary:
	var rec := Part.make("fit")
	rect_body(rec, 0, 0, 40, 40, 20, "Block")
	disc_body(rec, 20, 20, hole_d * 0.5, 30, "Hole", "cut")
	disc_body(rec, 20, 20, shaft_d * 0.5, 30, "Peg")
	return rec


func bolt_part(bolt_end_z: float, mat := "steel") -> Dictionary:
	var rec := Part.make("bolted")
	rec["material"] = mat
	rect_body(rec, 0, 0, 40, 40, 20, "Block")                      # z 0 .. 20
	disc_body(rec, 20, 20, 2.5, 10.0, "Tap", "cut")                # M6 tap drill 5.0 mm, 10 mm deep (z 0 .. 10)
	var pl := add(rec, "plane", {"from": "front", "mm": -20.0}, "bolt start")
	disc_body(rec, 20, 20, 3.0, bolt_end_z + 20.0, "Bolt M6", "new", pl)   # 6 mm shank from z -20 to bolt_end_z
	return rec


func tips_part() -> Dictionary:
	var rec := Part.make("lstand")
	rect_body(rec, 0, 0, 10, 10, 10, "Foot")
	rect_body(rec, 0, 10, 80, 30, 10, "Arm", "join")
	return rec


func stable_part() -> Dictionary:
	var rec := Part.make("stool")
	rect_body(rec, 0, 0, 60, 10, 20, "Base")
	rect_body(rec, 20, 10, 40, 40, 20, "Post", "join")
	return rec


func beam_part(load_n: float, mat := "aluminium") -> Dictionary:
	var rec := Part.make("beam")
	rec["material"] = mat
	rec["load_n"] = load_n
	rect_body(rec, 0, 0, 200, 10, 5, "Bar")   # 200 long, 10 wide, 5 thick (the load bends it about the thin side)
	return rec


func control_part() -> Dictionary:
	var rec := Part.make("control")
	rect_body(rec, -20, -20, 20, 20, 30, "Stand", "new", "top")   # a 40 x 40 mm base, 30 mm tall, pulled up from the floor; tapered 3 degrees below
	(rec["features"][1] as Dictionary)["taper"] = 3.0
	return rec


func showcase() -> Dictionary:
	var rec := Part.make("Showcase")
	rect_body(rec, 0, 0, 10, 20, 10, "Tee")
	rect_body(rec, -30, 20, 40, 30, 10, "Arm", "join")
	rect_body(rec, 60, 0, 100, 40, 0.5, "Plate")
	rect_body(rec, 0, 60, 10, 70, 10, "")
	add(rec, "appear", {"body": 0, "preset": "Paint", "color": [0.01, 0.01, 0.01]}, "Paint it black")
	return rec


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the parts cannot be built")
		quit(1)
		return
	# ------------------------------------------------------------------ 1 LEVELS
	var plant := [
		["look.broken_solid", p_broken(), {}], ["look.floating", p_floating(), {}], ["look.hidden_overlap", p_hidden(), {}], ["look.no_name", p_noname(), {}],
		["look.dark_material", p_dark(), {}], ["print.thin_wall", p_thin(), {}], ["print.overhang", p_overhang(), {}], ["print.small_detail", p_speck(), {}],
		["print.not_watertight", p_hidden(), {"bodies": [open_cube()]}],
		["eng.fit", fit_part(20.0, 20.3), {}], ["eng.bolt", bolt_part(3.0), {}], ["eng.tips", tips_part(), {}],
		["eng.stress", beam_part(60.0), {}], ["eng.deflection", beam_part(20.0), {}], ["eng.draft", p_hidden(), {}]]
	for pl in plant:
		var code: String = pl[0]
		var rank_need := PartWarn.rank(String(PartWarn.CODES[code]))
		var seen := []
		var good := true
		for lv in PartWarn.LEVELS:
			var o: Dictionary = (pl[2] as Dictionary).duplicate()
			o["level"] = lv
			var r := PartWarn.report(pl[1], o)
			var f := has(r, code)
			seen.append("%s:%s" % [lv, "yes" if f else "no"])
			good = good and (f == (PartWarn.rank(lv) >= rank_need and lv != "off"))
			if lv == "off":
				good = good and r["warnings"].is_empty() and r["lines"].is_empty()
		ok(good, "1 %s fires at %s and above, not below: %s" % [code, PartWarn.CODES[code], " ".join(seen)])
	# a level shows only its own and the lower levels' warnings
	var sc := showcase()
	var sub_ok := true
	var counts := []
	for lv in PartWarn.LEVELS:
		var r := PartWarn.report(sc, {"level": lv})
		counts.append(r["warnings"].size())
		for w in r["warnings"]:
			sub_ok = sub_ok and PartWarn.rank(String(w["level"])) <= PartWarn.rank(lv) and PartWarn.rank(String(w["level"])) > 0
	var s0 := PartWarn.report(sc, {"level": "look"})
	var s1 := PartWarn.report(sc, {"level": "print"})
	var s2 := PartWarn.report(sc, {"level": "engineering"})
	var sub2 := true
	for w in s0["warnings"]:
		sub2 = sub2 and w["key"] in s1["warnings"].map(func(x): return x["key"])
	for w in s1["warnings"]:
		sub2 = sub2 and w["key"] in s2["warnings"].map(func(x): return x["key"])
	ok(sub_ok and sub2 and counts[0] == 0 and counts[1] >= 2 and counts[2] > counts[1] and counts[3] > counts[2], "1 the showcase: Off %d, Look %d, Print %d, Engineering %d warnings; each level only its own and the ones below; Look in Print in Engineering" % [counts[0], counts[1], counts[2], counts[3]])
	# ------------------------------------------------------------------ 2 CONTROL
	var rcn := control_part()
	var allc := true
	var said := []
	for lv in PartWarn.LEVELS:
		var rr := PartWarn.report(rcn, {"level": lv})
		allc = allc and rr["ok"] and rr["warnings"].is_empty()
		said.append("%s:%d" % [lv, rr["warnings"].size()])
	var rce := PartWarn.report(rcn, {"level": "engineering"})
	ok(allc and float(rce["numbers"].get("weight_kg", 0.0)) > 0.1, "2 the clean control (named stand, 3 degree taper, one piece) fires nothing: %s; %s" % [" ".join(said), str(rce["warnings"])])
	var rcl := PartWarn.report(rcn, {"level": "engineering", "bodies": [open_cube()]})
	ok(has(rcl, "print.not_watertight"), "2 ...and the same control fires the watertight warning when it is handed an open skin (the rule can still fire on it)")
	# ------------------------------------------------------------------ 3 FITS (hand-worked from ISO 286)
	var fz := [["H7/g6", 19.9865, 20.0105, 7.0, 41.0, "sliding"], ["H7/h6", 19.9935, 20.0105, 0.0, 34.0, "locational clearance"], ["H7/p6", 20.0285, 20.0105, -35.0, -1.0, "locational interference"]]
	for z in fz:
		var rf := PartWarn.report(fit_part(z[1], z[2]), {"level": "engineering"})
		var fl: Array = rf["fits"]
		var f0: Dictionary = fl[0] if fl.size() == 1 else {}
		ok(fl.size() == 1 and String(f0.get("class", "")) == z[0] and near(float(f0.get("cmin_um", 99)), z[3], 0.001) and near(float(f0.get("cmax_um", 99)), z[4], 0.001) and int(f0.get("nominal", 0)) == 20 and String(f0.get("name", "")) == z[5] and not has(rf, "eng.fit"),
			"3 shaft %s in hole %s mm: %s, clearance %s to %s um (wanted %s, %s to %s); measured %s / %s mm, %s um; %s" % [str(z[1]), str(z[2]), f0.get("class"), f0.get("cmin_um"), f0.get("cmax_um"), z[0], z[3], z[4], f0.get("shaft_mm"), f0.get("hole_mm"), f0.get("clearance_um"), f0.get("text", "")])
	var rl := PartWarn.report(fit_part(20.0, 20.3), {"level": "engineering"})
	var rfl: Array = rl["fits"]
	ok(rfl.size() == 1 and String(rfl[0]["class"]) == "" and has(rl, "eng.fit") and near(float(rfl[0]["clearance_um"]), 300.0, 3.0), "3 a 20 mm shaft in a 20.3 mm hole: no preferred fit, clearance %s um (wanted 300): %s" % [str(rfl[0].get("clearance_um")), str(rl["warnings"][0]["text"] if not rl["warnings"].is_empty() else "")])
	ok(PartWarn.band(true, "H", 7, 4) == [0.0, 21.0] and PartWarn.band(false, "g", 6, 4) == [-20.0, -7.0] and PartWarn.band(false, "h", 6, 4) == [-13.0, 0.0] and PartWarn.band(false, "p", 6, 4) == [22.0, 35.0] and PartWarn.band(false, "f", 7, 4) == [-41.0, -20.0],
		"3 the table at 18-30 mm: H7 0/+21, g6 -20/-7, h6 -13/0, p6 +22/+35, f7 -41/-20 um (ISO 286-2)")
	# ------------------------------------------------------------------ 4 BOLTS
	var rb1 := PartWarn.report(bolt_part(10.0), {"level": "engineering"})
	var b1: Dictionary = (rb1["numbers"].get("bolts", [{}]) as Array)[0]
	ok(near(float(b1.get("engaged_mm", 0)), 10.0, 0.4) and near(float(b1.get("needed_mm", 0)), 6.0, 0.001) and not has(rb1, "eng.bolt"), "4 M6 bolt 10 mm into the tapped hole in steel: engaged %s mm (wanted 10), needs %s mm (1 x 6), no warning" % [str(b1.get("engaged_mm")), str(b1.get("needed_mm"))])
	var rb2 := PartWarn.report(bolt_part(3.0), {"level": "engineering"})
	var b2: Dictionary = (rb2["numbers"].get("bolts", [{}]) as Array)[0]
	ok(near(float(b2.get("engaged_mm", 0)), 3.0, 0.4) and has(rb2, "eng.bolt"), "4 the same bolt only 3 mm in: engaged %s mm (wanted 3) is under 6 mm: %s" % [str(b2.get("engaged_mm")), str(rb2["warnings"][0]["text"] if not rb2["warnings"].is_empty() else "")])
	var rb3 := PartWarn.report(bolt_part(10.0, "aluminium"), {"level": "engineering"})
	var rb4 := PartWarn.report(bolt_part(10.0, "wood"), {"level": "engineering"})
	ok(not has(rb3, "eng.bolt") and has(rb4, "eng.bolt") and near(float(rb4["numbers"]["bolts"][0]["needed_mm"]), 12.0, 0.001), "4 10 mm engaged is enough in aluminium (needs 9) and short in wood (needs 12)")
	# ------------------------------------------------------------------ 5 TIPS
	var rt := PartWarn.report(tips_part(), {"level": "engineering"})
	var mg := float(rt["numbers"].get("margin_mm", 0.0))
	ok(has(rt, "eng.tips") and near(mg, -27.94, 0.15) and near(float(rt["numbers"]["weight_kg"]), 0.13345, 0.0005), "5 L stand: centre of mass %s mm past the foot (wanted -27.94: (1000 x 5 + 16000 x 40) / 17000 = 37.94, foot ends at 10), weight %s kg (wanted 0.13345 = 17000 mm3 x 7850 kg/m3)" % [str(mg), str(rt["numbers"]["weight_kg"])])
	var rs := PartWarn.report(stable_part(), {"level": "engineering"})
	ok(not has(rs, "eng.tips") and float(rs["numbers"].get("margin_mm", -99.0)) > 5.0, "5 stool (base 60 wide, post in the middle): stable, margin %s mm" % str(rs["numbers"].get("margin_mm")))
	# ------------------------------------------------------------------ 6 BEAM
	# aluminium E = 69 GPa, yield 240 MPa / 1.5 = 160 MPa. Z = b h^2 / 6 = 10 x 25 / 6 = 41.667 mm3, I = b h^3 / 12 = 104.167 mm4, L = 200 mm
	var rba := PartWarn.report(beam_part(20.0), {"level": "engineering"})
	var bm: Dictionary = (rba["numbers"].get("beams", [{}]) as Array)[0]
	ok(near(float(bm.get("sigma_mpa", 0)), 96.0, 0.2) and near(float(bm.get("deflection_mm", 0)), 7.42, 0.03) and has(rba, "eng.deflection") and not has(rba, "eng.stress"),
		"6 20 N at the tip: stress %s MPa (wanted 20 x 200 / 41.667 = 96.0, under 160), bend %s mm (wanted 20 x 200^3 / (3 x 69000 x 104.167) = 7.42, over 200 / 100 = 2)" % [str(bm.get("sigma_mpa")), str(bm.get("deflection_mm"))])
	var rbb := PartWarn.report(beam_part(60.0), {"level": "engineering"})
	var bm2: Dictionary = (rbb["numbers"].get("beams", [{}]) as Array)[0]
	ok(near(float(bm2.get("sigma_mpa", 0)), 288.0, 0.5) and has(rbb, "eng.stress") and has(rbb, "eng.deflection"), "6 60 N: stress %s MPa (wanted 288, over 160) and bend %s mm (wanted 22.3): both warn" % [str(bm2.get("sigma_mpa")), str(bm2.get("deflection_mm"))])
	var rbc := PartWarn.report(beam_part(5.0), {"level": "engineering"})
	ok(not has(rbc, "eng.stress") and not has(rbc, "eng.deflection") and near(float(rbc["numbers"]["beams"][0]["deflection_mm"]), 1.855, 0.01), "6 5 N: bend %s mm (wanted 1.855, under 2): no beam warning" % str(rbc["numbers"]["beams"][0]["deflection_mm"]))
	# ------------------------------------------------------------------ 7 MUTES (record level)
	var rm := showcase()
	PartWarn.set_level(rm, "engineering")
	var base := PartWarn.report(rm)
	var w0: Dictionary = base["warnings"][0]
	PartWarn.set_mute(rm, String(w0["key"]), true)
	var r_a := PartWarn.report(rm)
	ok(r_a["warnings"].size() == base["warnings"].size() - 1 and r_a["muted"].size() == 1 and not (w0["key"] in r_a["warnings"].map(func(x): return x["key"])), "7 muting %s hides that one warning on that part (%d -> %d) and lists it as muted" % [w0["key"], base["warnings"].size(), r_a["warnings"].size()])
	var parts_n: int = base["warnings"].filter(func(x): return x["part"] == "Plate").size()
	PartWarn.set_mute(rm, "*@Plate", true)
	var r_b := PartWarn.report(rm)
	ok(r_b["warnings"].filter(func(x): return x["part"] == "Plate").is_empty() and parts_n >= 2 and r_b["warnings"].size() < r_a["warnings"].size(), "7 muting the part Plate hides all %d of its warnings" % parts_n)
	PartWarn.set_mute(rm, "eng.draft@*", true)
	var r_c := PartWarn.report(rm)
	ok(not has(r_c, "eng.draft") and has(base, "eng.draft"), "7 muting a kind (eng.draft@*) hides it on every part")
	var txt := JSON.stringify(Part.to_file(rm))
	var back := Part.from_file(JSON.parse_string(txt))
	var r_d := PartWarn.report(back)
	ok(back.get("warn_level") == "engineering" and (back.get("warn_mute") as Array) == (rm["warn_mute"] as Array) and ids_of(r_d) == ids_of(r_c) and (r_d["warnings"] as Array).map(func(x): return x["text"]) == (r_c["warnings"] as Array).map(func(x): return x["text"]),
		"7 level and mutes survive save + reload: %s, the same %d warnings" % [str(back.get("warn_mute")), r_d["warnings"].size()])
	ok(not PartWarn.set_mute(rm, "nonsense", true) and not PartWarn.set_mute(rm, "look.bogus@x", true) and not PartWarn.set_level(rm, "loud"), "7 a bad mute or level is refused")
	# ------------------------------------------------------------------ 8 DOORS: the real UI, agent_tools
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	var card: Control = ss._cards["building"]
	await click(card)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)
	var pu: PartUI = m.bld.part
	pu.set_on(false)
	m.S.part = {}
	await idle(4)
	await click(pu.part_btn)
	await idle(4)
	if not pu.on:
		pu.set_on(true)
		await idle(4)
	m.S.part = showcase()
	m.bld.sync()
	await idle(20)
	var wu: PartWarnUI = pu.warn_ui
	var T := AgentTools.new(m)
	var vr := wu.get_viewport_rect().intersection(wu.get_global_rect())
	ok(wu != null and wu.visible and vr.size.is_equal_approx(wu.get_global_rect().size), "8 the Warnings panel is on screen with the Part workspace (rect %s)" % str(wu.get_global_rect()))
	var shot_n := 0
	for lv in PartWarn.LEVELS:
		var u_before: int = m.undo.size()
		var cur := PartWarn.level_of(m.S.part)
		if cur != lv:
			await click(wu.lv_btns[lv])
		await idle(6)
		wu.refresh(true)
		await idle(4)
		var changed: bool = cur != lv
		ok(PartWarn.level_of(m.S.part) == lv and m.undo.size() == u_before + (1 if changed else 0), "8 click %s: the record's level is %s, one undo step (%d -> %d)" % [lv, PartWarn.level_of(m.S.part), u_before, m.undo.size()])
		var pn: Dictionary = wu.shown
		var q: Dictionary = await T.request(10 + shot_n, "part_warn", {})
		var ar: Dictionary = q.get("result", {})
		var same := (ar.get("warnings", []) as Array).size() == (pn["warnings"] as Array).size()
		for i in (pn["warnings"] as Array).size():
			if same:
				same = same and String(ar["warnings"][i]["id"]) == String(pn["warnings"][i]["id"]) and String(ar["warnings"][i]["text"]) == String(pn["warnings"][i]["text"])
		var rows := wu.rows_box.get_child_count()
		var shown_texts := []
		for i in rows:
			shown_texts.append((wu.rows_box.get_child(i).find_child("partwarn_text_%d" % i, true, false) as Label).text)
		var panel_texts: Array = (pn["warnings"] as Array).map(func(x): return String(x["text"]))
		ok(same and q.has("result") and rows == (pn["warnings"] as Array).size() and shown_texts == panel_texts, "8 %s: agent_tools part_warn gives the panel's %d warnings, same ids and texts; the panel draws %d rows with those texts" % [lv, (pn["warnings"] as Array).size(), rows])
		root.get_texture().get_image().save_png("%s/panel_%d_%s.png" % [SHOT, shot_n, lv])
		if lv in ["print", "engineering"]:   # the list scrolls: the same panel scrolled to its last rows shows the higher levels' badges
			wu.scroll.scroll_vertical = 100000
			await idle(4)
			root.get_texture().get_image().save_png("%s/panel_%d_%s_end.png" % [SHOT, shot_n, lv])
			wu.scroll.scroll_vertical = 0
			await idle(2)
		shot_n += 1
	# mutes and undo through the real buttons
	var u1: int = m.undo.size()
	var n_eng: int = (wu.shown["warnings"] as Array).size()
	await click(wu.rows_box.find_child("partwarn_mute_0_0", true, false))
	await idle(4)
	ok(m.undo.size() == u1 + 1 and (wu.shown["warnings"] as Array).size() == n_eng - 1 and (m.S.part.get("warn_mute", []) as Array).size() == 1, "8 click Mute: one undo step (%d -> %d), %d -> %d warnings, mutes %s" % [u1, m.undo.size(), n_eng, (wu.shown["warnings"] as Array).size(), str(m.S.part.get("warn_mute"))])
	var muted_key := String(m.S.part["warn_mute"][0]) if m.S.part.has("warn_mute") else ""
	m._undo()
	await idle(4)
	wu.refresh(true)
	ok(not m.S.part.has("warn_mute") and (wu.shown["warnings"] as Array).size() == n_eng and m.undo.size() == u1, "8 one undo takes the mute back (%s): %d warnings again, level still %s" % [muted_key, (wu.shown["warnings"] as Array).size(), PartWarn.level_of(m.S.part)])
	var qm: Dictionary = await T.request(40, "part_warn", {"mute": ["look.no_name@*", "*@Plate"]})
	ok(qm.has("result") and (m.S.part.get("warn_mute", []) as Array).size() == 2 and m.undo.size() == u1 + 1 and not has(qm.get("result", {"warnings": []}), "look.no_name") and qm["result"]["warnings"].filter(func(x): return x["part"] == "Plate").is_empty(), "8 agent mute of two keys in ONE undo step (%d -> %d); the answer hides them" % [u1, m.undo.size()])
	wu.refresh(true)
	await idle(4)
	root.get_texture().get_image().save_png("%s/panel_4_muted.png" % SHOT)
	m._undo()
	await idle(3)
	var ql: Dictionary = await T.request(41, "part_warn", {"level": "print"})
	ok(ql.has("result") and PartWarn.level_of(m.S.part) == "print" and m.undo.size() == u1 + 1 and ql["result"]["level"] == "print", "8 agent sets the level to print in one undo step")
	var qbad: Dictionary = await T.request(42, "part_warn", {"mute": "bogus"})
	ok(qbad.has("error"), "8 a mute that is not <id>@<part> is refused with the shape")
	print("s221: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for dn in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = dn
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		await process_frame
	await idle(2)
