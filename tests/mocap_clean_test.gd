## godot --headless --path . -s tests/mocap_clean_test.gd     (GATES XX7)
## MOCAP FOOT LOCK + CLEANUP REPORT (scripts/mocap_clean.gd). Input: walk_bat -> BvhExport -> parsed, then in memory:
## a slide (the hips drift 4.2 cm/s sideways and forward, so every standing foot creeps) + noise (1 mm on the hips, seeded),
## a POP seeded at frame POP_AT (one joint +60 deg for one frame) and a FLIP at FLIP_AT (a channel +360 deg from that row on).
## Bars: the clean walk finds no pop and no flip; the seeded pop and flip are found at their frames (+-1) and nothing else is;
## FOOT SLIDE (Check's rule) is printed before and after and falls; during each detected contact the planted foot slides
## under 1 cm (and, as a control, more than that before the lock); the repair puts the popped frame back between its neighbours;
## a scene that is only analysed is byte for byte the same; a limb seeded through the body is found.
extends SceneTree

var fails := 0
const DIR := "user://zz_mocap_clean"
const POP_AT := 40
const FLIP_AT := 70
const POP_JOINT := "upperarm_l"
const FLIP_JOINT := "spine_02"
const DRIFT := 0.03    # m/s on x and z each (4.2 cm/s): a stance of 0.9 s creeps 3.5 cm, over Check's 2.5 cm; much more and a fully stretched leg runs out of reach, and a foot faster than CONTACT_V is not a contact


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func joint_of(bv: Dictionary, nm: String) -> Dictionary:
	for j in bv["joints"]:
		if j["name"] == nm:
			return j
	return {}


## add `v` to column `col` of rows from..to
func bump(bv: Dictionary, col: int, v: float, from: int, to: int) -> void:
	var rows: Array = bv["frames"]
	for i in range(from, to + 1):
		var row: PackedFloat64Array = rows[i]
		row[col] += v
		rows[i] = row


func seeded(B: Body, sn: String, drift := DRIFT) -> Dictionary:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sn)))
	BvhExport.write(S, B, DIR + "/in.bvh")
	var bv := BvhImport.load_file(DIR + "/in.bvh")
	var clean := BvhImport.load_file(DIR + "/in.bvh")
	var rows: Array = bv["frames"]
	var root := joint_of(bv, "pelvis")
	var rs := int(root["start"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in rows.size():
		var row: PackedFloat64Array = rows[i]
		for k in (root["channels"] as Array).size():
			var ch := String(root["channels"][k])
			if ch.ends_with("position"):
				row[rs + k] += rng.randfn(0.0, 0.001)
				if ch == "Xposition" or ch == "Zposition":
					row[rs + k] += drift * i * float(bv["dt"])
		rows[i] = row
	var pj := joint_of(bv, POP_JOINT)
	var fj := joint_of(bv, FLIP_JOINT)
	var pcol := -1
	for k in (pj["channels"] as Array).size():
		if String(pj["channels"][k]) == "Xrotation":
			pcol = int(pj["start"]) + k
	bump(bv, pcol, 60.0, POP_AT, POP_AT)
	var fcol := int(fj["start"]) + (fj["channels"] as Array).size() - 1   # the last rotation channel
	bump(bv, fcol, 360.0, FLIP_AT, rows.size() - 1)
	return {"bv": bv, "clean": clean}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	# 1 the clean walk
	var s0 := seeded(B, "walk_bat")
	var cl: Dictionary = s0["clean"]
	var Sc: Scene = BvhImport.to_scene(cl, B)["scene"]
	var json0 := JSON.stringify(Sc.to_dict(B))
	var a0 := MocapClean.analyse(Sc, B, cl)
	ok(a0["pops"].is_empty() and a0["flips"].is_empty(), "1 clean walk_bat (%d frames): %d pops, %d flips (bar 0, 0); %d foot contacts; %s" % [Sc.cards.size(), a0["pops"].size(), a0["flips"].size(), a0["contacts"].size(), a0["text"]])
	var mx := 0.0
	for i in range(1, a0["frames"]["n"]):
		for j in Body.ORDER:
			mx = maxf(mx, MocapClean._step(a0["frames"], j, i - 1, i) / (float(a0["frames"]["t"][i]) - float(a0["frames"]["t"][i - 1])))
	ok(mx < MocapClean.POP_SPEED * 0.5, "1b the clean walk's fastest joint turns %.0f deg/s (the pop bar is %.0f: half or less)" % [mx, MocapClean.POP_SPEED])
	ok(JSON.stringify(Sc.to_dict(B)) == json0, "2 old scenes byte for byte: analysing changed nothing (%d chars)" % json0.length())
	ok(not json0.contains("\"plant\""), "2b a scene that was only analysed has no plant key")
	# 2 the seeded input
	var bv: Dictionary = s0["bv"]
	var r := BvhImport.to_scene(bv, B)
	var S: Scene = r["scene"]
	var rep := MocapClean.analyse(S, B, bv)
	print(rep["text"])
	for k in ["pops", "flips", "through"]:
		for f in rep[k]:
			print("   ", f["kind"], " frame ", f["frame"], " ", f["joint"], " size ", snappedf(f["size"], 0.1), "  fix: ", f["fix"].left(150))
	var pp: Array = rep["pops"]
	ok(pp.size() == 1 and absi(int(pp[0]["frame"]) - POP_AT) <= 1 and pp[0]["joint"] == POP_JOINT, "3 the seeded pop: %d pop findings (bar 1), at frame %s (bar %d +-1), joint %s (bar %s), size %.0f deg" % [pp.size(), str(pp[0]["frame"]) if not pp.is_empty() else "-", POP_AT, str(pp[0]["joint"]) if not pp.is_empty() else "-", POP_JOINT, pp[0]["size"] if not pp.is_empty() else 0.0])
	var fl: Array = rep["flips"]
	ok(fl.size() == 1 and absi(int(fl[0]["frame"]) - FLIP_AT) <= 1 and fl[0]["joint"] == FLIP_JOINT, "4 the seeded flip: %d flip findings (bar 1), at frame %s (bar %d +-1), joint %s (bar %s), size %.0f deg" % [fl.size(), str(fl[0]["frame"]) if not fl.is_empty() else "-", FLIP_AT, str(fl[0]["joint"]) if not fl.is_empty() else "-", FLIP_JOINT, fl[0]["size"] if not fl.is_empty() else 0.0])
	ok(not pp.is_empty() and pp[0]["fix"].length() > 20 and not fl.is_empty() and fl[0]["fix"].length() > 20, "4b each finding carries a suggested fix")
	# 3 the foot lock
	var cons: Array = rep["contacts"]
	var fr: Dictionary = rep["frames"]
	var sl0 := MocapClean.slide_of(S, B)
	var cs0 := MocapClean.contact_slide(S, B, cons, fr)
	var w0 := 0.0
	for e in cs0:
		w0 = maxf(w0, e[1])
	ok(cons.size() >= 4 and w0 > 0.02, "5 before the lock: %d contacts, the worst creeps %.1f cm (control: bar > 2 cm, so the lock has something to do); Check FOOT SLIDE %d findings, worst %.1f cm" % [cons.size(), w0 * 100.0, sl0["n"], sl0["worst"] * 100.0])
	var cr := MocapClean.clean(S, B, bv)
	var cs1 := MocapClean.contact_slide(S, B, cons, fr)
	var w1 := 0.0
	for e in cs1:
		w1 = maxf(w1, e[1])
		print("   contact ", e[0]["foot"], " cards ", e[0]["a"], "-", e[0]["b"], " creep before ", snappedf(cs0[cs1.find(e)][1] * 100.0, 0.1), " cm after ", snappedf(e[1] * 100.0, 0.1), " cm")
	ok(w1 < 0.01, "6 during every detected contact the planted foot slides %.2f cm at most (bar < 1.00; %d contacts, %d cards marked)" % [w1 * 100.0, cons.size(), cr["locked"]])
	ok(cr["slide1"]["n"] < cr["slide0"]["n"] and cr["slide1"]["worst"] < cr["slide0"]["worst"], "7 FOOT SLIDE before %d findings / worst %.1f cm -> after %d / %.1f cm (bar: fewer findings and a smaller worst)" % [cr["slide0"]["n"], cr["slide0"]["worst"] * 100.0, cr["slide1"]["n"], cr["slide1"]["worst"] * 100.0])
	ok(cr["slide1"]["worst"] < 0.025, "7b after the lock the worst FOOT SLIDE is %.2f cm (Check's bar 2.5 cm)" % (cr["slide1"]["worst"] * 100.0))
	print("   release: the creep the lock moves to the step where a foot is let go: %.1f cm in one frame (the worst)" % (cr["release"] * 100.0))
	ok(cr["release"] < 0.12, "7c a released foot jumps %.1f cm in its first free frame (a foot drifting 4.2 cm/s for 0.9 s = about 3.5 cm; bar < 12 cm)" % (cr["release"] * 100.0))
	ok(cr["unheld"].is_empty(), "6b at the test drift every contact is held: %d reported as not held (bar 0)" % cr["unheld"].size())
	# 4 the pop repair
	ok(cr["repaired"] == 1, "8 the repair touched %d joint (bar 1)" % cr["repaired"])
	var again := MocapClean.pops(MocapClean.frames(S, B, false))
	ok(again.is_empty(), "8b after the repair the scene has %d pops (bar 0)" % again.size())
	var fr2 := MocapClean.frames(S, B, false)
	var stp := MocapClean._step(fr2, POP_JOINT, POP_AT - 1, POP_AT)
	ok(stp < 20.0, "8c the repaired frame is %.1f deg from the frame before (it was about 60; bar < 20)" % stp)
	# 5 a scene that is not touched keeps its bytes; clean on the clean walk plants
	var Sc2: Scene = BvhImport.to_scene(cl, B)["scene"]
	var cc := MocapClean.clean(Sc2, B, cl)
	ok(cc["repaired"] == 0 and cc["locked"] > 0 and cc["slide1"]["n"] <= cc["slide0"]["n"], "9 clean walk_bat: nothing repaired (%d), %d cards planted; FOOT SLIDE %d -> %d findings" % [cc["repaired"], cc["locked"], cc["slide0"]["n"], cc["slide1"]["n"]])
	var plant_json := JSON.stringify(Sc2.to_dict(B))
	var S3 := Scene.new()
	S3.from_dict(JSON.parse_string(plant_json))
	var same_plants := true
	var nplants := 0
	for i in Sc2.cards.size():
		same_plants = same_plants and Sc2.cards[i].get("plant", []) == S3.cards[i].get("plant", [])
		nplants += Sc2.cards[i].get("plant", []).size()
	ok(same_plants and nplants > 0, "9b the planted scene saves and loads back with the same plants (%d foot marks on %d cards)" % [nplants, Sc2.cards.size()])
	# 6 a scene-level flip: a rotation number that jumps 360 for the same rotation
	var Sf: Scene = BvhImport.to_scene(cl, B)["scene"]
	for i in range(60, Sf.cards.size()):
		Sf.cards[i]["pose"]["joints"]["head"]["twist"] = float(Sf.cards[i]["pose"]["joints"]["head"].get("twist", 0.0)) + 360.0
	var sf := MocapClean.scene_flips(Sf, B)
	ok(sf.size() >= 1 and absi(int(sf[0]["frame"]) - 60) <= 1, "10 a scene whose head twist numbers jump 360 at card 60: %d flip findings, first at frame %s (bar 60 +-1)" % [sf.size(), str(sf[0]["frame"]) if not sf.is_empty() else "-"])
	# 7 a limb through the body
	var bt := BvhImport.load_file(DIR + "/in.bvh")
	var tj := joint_of(bt, POP_JOINT)
	for k in (tj["channels"] as Array).size():
		if String(tj["channels"][k]) == "Xrotation":
			bump(bt, int(tj["start"]) + k, 60.0, 38, 42)   # the same joint turned 60 deg for five frames: it goes into the hips
	var St: Scene = BvhImport.to_scene(bt, B)["scene"]
	var th := MocapClean.through(MocapClean.frames(St, B))
	var thf := th.filter(func(f): return f["frame"] >= 38 and f["frame"] <= 42)
	print("   through-body candidates: ", th.size(), " ", th.slice(0, 3).map(func(f): return "%d %s %.0f mm" % [f["frame"], f["joint"], f["size"]]))
	ok(not thf.is_empty(), "11 an upper arm turned 60 deg into the hips at frames 38-42: %d finding(s) in that range (bar >= 1), deepest %.0f mm" % [thf.size(), thf[0]["size"] if not thf.is_empty() else 0.0])
	ok(a0["through"].is_empty(), "11b the clean walk has %d limbs through the body (bar 0)" % a0["through"].size())
	# 8 the registry command: one undo step, a status line with the report, a short scene refused with no step
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var ids: Array = m._commands().map(func(c): return c["id"])
	ok("clean_up_mocap" in ids or ids.any(func(i): return "mocap" in String(i)), "12 the registry has the command: %s" % str(ids.filter(func(i): return "mocap" in String(i))))
	m.S = BvhImport.to_scene(bv, B)["scene"]
	m._rebuild_cards()
	m.undo.clear()
	var before := JSON.stringify(m.S.cards)
	m._mocap_clean()
	var after := JSON.stringify(m.S.cards)
	ok(m.undo.size() == 1 and after != before and after.contains("plant"), "12b Clean up mocap: %d undo step (bar 1), cards changed %s, plants written %s" % [m.undo.size(), after != before, after.contains("plant")])
	m._undo()
	ok(JSON.stringify(m.S.cards) == before, "12c one Ctrl+Z puts every card back exactly (%d chars)" % before.length())
	var Sh := Scene.new()
	Sh.add("a", {"joints": {}, "offset": [0, 0, 0]})
	Sh.add("b", {"joints": {}, "offset": [0, 0, 0]})
	m.S = Sh
	m.undo.clear()
	m._mocap_clean()
	ok(m.undo.size() == 0, "12d a 2-card scene is refused with no undo step (%d steps, bar 0)" % m.undo.size())
	m.queue_free()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	print("MOCAP CLEAN TEST %s %d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
