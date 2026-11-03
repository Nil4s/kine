extends SceneTree
## godot --headless --path . -s tests/c06_test.gd     (C06 AGENT MATH FOR BUILDING + PICTURES: part_facts fields, frame_facts light fields, MCP round trip; needs the CAD DLL)
## The bars were written and committed BEFORE the numbers they judge were read. Parts have KNOWN answers (mm written here, never read back from the code under test).
##   1 DESK    a desk (two 60 x 720 mm panels and a 30 mm top, built from records): part_facts' box top is within 1 mm of what the kernel's own replay
##             measures (the number tests/fdesk_test.gd judges: Part.replay(part)["aabb"].end.y); a planted 5 mm wrong value must FAIL the same bar
##   2 FIELDS  two 20 mm cubes 10 mm apart: bodies carry volume 8000 mm3 + box, touching_pairs empty, {gap:[1,2]} = 10.000 mm; touching cubes: pair listed;
##             a 4 mm hole (cut circle) and a 2.5 mm fillet are listed with their radii; a step that cannot run is listed in failed_steps
##   3 LIGHT   three cubes, one set to white emissive: frame_facts names it the brightest piece; it is NOT touching the frame edge when centred and IS when its
##             top is placed at the top edge; a piece with no glow has glow_px 0 and the glowing one has glow_px > 0; the old keys of every piece are unchanged
##   4 OLD     the old part_facts / frame_facts keys are all still there
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func add(rec: Dictionary, t: String, f: Dictionary, nm := "") -> String:
	var fields := f.duplicate()
	if nm != "":
		fields["name"] = nm
	var nf := Part.new_feature(rec, t, fields)
	(rec["features"] as Array).append(nf)
	return String(nf["id"])


func rect_body(rec: Dictionary, x0: float, y0: float, x1: float, y1: float, dist: float, nm: String, op := "new") -> void:
	var sk := add(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []}, nm + " sketch")
	add(rec, "extrude", {"sketch": sk, "dist": dist, "both": false, "op": op}, nm)


func two_cubes(gap_x: float) -> Dictionary:
	var rec := Part.make("two cubes")
	rect_body(rec, 0, 0, 20, 20, 20, "Cube A")
	rect_body(rec, 20.0 + gap_x, 0, 40.0 + gap_x, 20, 20, "Cube B")
	return rec


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL, the parts cannot be built")
		quit(1)
		return
	# ------------------------------------------------------------------ 1 DESK
	var desk := Part.make("desk")
	rect_body(desk, -580, 0, -520, 720, 600, "Left panel")
	rect_body(desk, 520, 0, 580, 720, 600, "Right panel")
	rect_body(desk, -580, 720, 580, 750, 600, "Top", "new")
	var res := Part.replay(desk)
	var fdesk_top_mm: float = (res["aabb"] as AABB).end.y * 1000.0   # what tests/fdesk_test.gd measures: bb.end.y of Part.replay(...)
	var fd := PartFacts.facts(desk)
	ok(bool(fd["ok"]) and fd.has("box_mm"), "1a part_facts carries a whole-part box_mm")
	var top_pf := -1e9
	if fd.has("box_mm"):
		top_pf = float(fd["box_mm"]["max"][1])
	ok(absf(top_pf - fdesk_top_mm) <= 1.0, "1b desk top: part_facts %.3f mm vs the replay's %.3f mm (bar 1 mm)" % [top_pf, fdesk_top_mm])
	ok(not (absf(top_pf - (fdesk_top_mm + 5.0)) <= 1.0), "1c control: a planted wrong top (+5 mm) FAILS the same bar")
	ok(absf(fdesk_top_mm - 750.0) <= 1.0, "1d the replay's top is the 750 mm I drew (%.3f)" % fdesk_top_mm)
	# ------------------------------------------------------------------ 2 FIELDS
	var tc := two_cubes(10.0)
	var f2 := PartFacts.facts(tc, {"gap": [1, 2]})
	ok(bool(f2["ok"]) and f2.has("bodies_math") and (f2["bodies_math"] as Array).size() == 2, "2a two cubes: bodies_math lists 2 bodies")
	if f2.has("bodies_math") and (f2["bodies_math"] as Array).size() == 2:
		var b0: Dictionary = f2["bodies_math"][0]
		ok(absf(float(b0["volume_mm3"]) - 8000.0) <= 0.5 and absf(float(b0["box_max"][0]) - 20.0) <= 0.01, "2b cube volume %s (want 8000) and box max x %s (want 20)" % [str(b0["volume_mm3"]), str(b0["box_max"][0])])
	ok((f2.get("touching_pairs", [1]) as Array).is_empty(), "2c 10 mm apart: no touching pairs")
	ok(f2.has("gap") and absf(float(f2["gap"]["gap_mm"]) - 10.0) <= 0.01, "2d gap between body 1 and 2 = %s mm (want 10.000)" % str(f2.get("gap", {}).get("gap_mm")))
	var tt := PartFacts.facts(two_cubes(0.0))
	ok((tt.get("touching_pairs", []) as Array).size() == 1, "2e cubes face to face: one touching pair (%s)" % str(tt.get("touching_pairs")))
	var hp := Part.make("holed")
	rect_body(hp, 0, 0, 40, 40, 20, "Block")
	var hs := add(hp, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": [20, 20], "r": 4.0}], "dims": []}, "Hole sketch")
	add(hp, "extrude", {"sketch": hs, "dist": 20, "both": false, "op": "cut"}, "Hole")
	add(hp, "fillet", {"body": 0, "r": 2.5, "edges": [{"p": [0, 0, 10], "q": [0, 0, 0.5], "d": [0, 0, 1]}]}, "Round")
	add(hp, "extrude", {"sketch": "nosuchsketch", "dist": 5, "both": false, "op": "join"}, "Broken")
	var fh := PartFacts.facts(hp)
	var holes: Array = fh.get("holes", [])
	ok(holes.size() == 1 and absf(float(holes[0]["radius_mm"]) - 4.0) <= 0.001, "2f hole radius listed: %s (want one of 4.0)" % str(holes))
	var fl: Array = fh.get("fillets", [])
	ok(fl.size() == 1 and absf(float(fl[0]["radius_mm"]) - 2.5) <= 0.001, "2g fillet radius listed: %s (want one of 2.5)" % str(fl))
	var fs: Array = fh.get("failed_steps", [])
	var named := false
	for q in fs:
		if String(q.get("name", "")) == "Broken":
			named = true
	ok(named, "2h the step that cannot run is in failed_steps by name: %s" % str(fs))
	ok((PartFacts.facts(tc).get("failed_steps", [1]) as Array).is_empty(), "2i control: a clean part has no failed steps")
	# ------------------------------------------------------------------ 3 LIGHT
	var cam := {"pos": [0.0, 0.5, 3.0], "target": [0.0, 0.5, 0.0], "fov": 45.0}
	var mid := _lamps(500)
	var r_mid := _frame(mid, cam)
	var r_top := _frame(_lamps(1600), cam)
	ok(bool(r_mid.get("ok", false)) and r_mid.has("light"), "3a frame_facts carries a light block")
	ok(String(r_mid.get("light", {}).get("brightest_piece", "")) == "Lamp", "3b brightest piece is the white emissive one: '%s'" % str(r_mid.get("light", {}).get("brightest_piece")))
	var pm: Dictionary = r_mid.get("light", {}).get("pieces", {})
	ok(pm.has("Lamp") and pm.has("Wall") and float(pm["Lamp"]["peak_luminance"]) > float(pm["Wall"]["peak_luminance"]) + 1.0 and float(pm["Lamp"]["emission"]) > 0.0 and float(pm["Wall"]["emission"]) == 0.0,
		"3c peak luminance and emission: lamp %s vs wall %s" % [str(pm.get("Lamp")), str(pm.get("Wall"))])
	ok(float(pm["Lamp"]["glow_px"]) > 0.0 and float(pm["Wall"]["glow_px"]) == 0.0, "3d glow px: lamp %s, wall %s" % [str(pm["Lamp"]["glow_px"]), str(pm["Wall"]["glow_px"])])
	ok(not (r_mid["light"]["touching_frame_edge"] as Array).has("Lamp"), "3e centred: the lamp is NOT touching the frame edge")
	ok((r_top["light"]["touching_frame_edge"] as Array).has("Lamp") and bool(r_top["light"]["pieces"]["Lamp"]["edge"]["top"]), "3f placed at the top edge: the lamp touches the frame edge (top): %s" % str(r_top["light"]["pieces"]["Lamp"].get("edge")))
	ok(String(r_top["light"]["brightest_piece"]) == "Lamp", "3g still the brightest at the top edge")
	# ------------------------------------------------------------------ 4 OLD
	var oldp := ["visible", "bbox_px", "share_w", "share_h", "visible_px", "cut", "centre_offset_px", "top_row", "bottom_row", "aabb_bbox_px"]
	var all_old := true
	for k in oldp:
		if not (r_mid["scene"] as Dictionary).has(k):
			all_old = false
	ok(all_old and r_mid.has("camera") and r_mid.has("pieces") and r_mid.has("ms"), "4a every old frame_facts key is still there")
	var oldk := ["ok", "bodies", "lines", "volume_mm3", "pieces", "repeats", "overlaps", "apart_pairs", "data", "errors", "floats"]
	var all_old2 := true
	for k in oldk:
		if not fd.has(k):
			all_old2 = false
	ok(all_old2, "4b every old part_facts key is still there")
	print("c06: %d fail" % fails)
	quit(fails)


## three 200 mm cubes: a wall behind-left, a post right, and a lamp (white emissive) whose bottom is at y_mm
func _lamps(y_mm: float) -> Dictionary:
	var rec := Part.make("lamps")
	rect_body(rec, -700, 300, -300, 700, 200, "A")
	rect_body(rec, 300, 300, 700, 700, 200, "B")
	rect_body(rec, -100, y_mm, 100, y_mm + 200, 200, "C")
	add(rec, "bname", {"body": 0, "called": "Wall"})
	add(rec, "bname", {"body": 1, "called": "Post"})
	add(rec, "bname", {"body": 2, "called": "Lamp"})
	var gf := PartGlow.fields(Color(1, 1, 1), 8.0)
	var ap := {"body": 2, "preset": "Custom", "color": [1.0, 1.0, 1.0], "rough": 0.5, "metal": 0.0, "alpha": 1.0}
	ap.merge(gf, true)
	add(rec, "appear", ap)
	var ap2 := {"body": 0, "preset": "Custom", "color": [0.3, 0.3, 0.35], "rough": 0.9, "metal": 0.0, "alpha": 1.0}
	add(rec, "appear", ap2)
	return rec


func _frame(rec: Dictionary, cam: Dictionary) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var r := FrameFacts.serve(host, {"part": rec, "camera": cam, "w": 1280, "h": 720})
	host.queue_free()
	return r
