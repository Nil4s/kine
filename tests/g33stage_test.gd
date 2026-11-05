extends SceneTree
## godot --path . -s tests/g33stage_test.gd     (G33STAGE: construction / assembly STAGES in an Assembly, gap G33 of docs/CHALLENGE_FEEDBACK.md;
## scripts/build/assembly_stage.gd, assembly_stage_ui.gd, AssemblyRender "steps"). Bars committed before the first run; every bar has a
## planted control (a "CONTROL" line that must be caught):
##   a TOWER      a 3-stage block tower (base 100 x 20 x 100 mm on the ground; two walls 10 x 60 x 100; a roof 100 x 10 x 100) passes the
##                support check: 4 of 4 placed, nothing unsupported, no collision. Same stage: the roof in the walls' stage is held up through
##                the walls (a chain that reaches built parts). CONTROL: the roof stage before the walls reports the roof unsupported AT the
##                roof's stage (and nothing else); CONTROL: a stage of two stacked blocks floating 1 mm over the base reports BOTH
##   b FLOAT      a block 1 mm above the base (beyond the 0.1 mm tolerance) is unsupported; 0.05 mm above is supported (within tol); on the
##                SIDE of a wall: 0.05 mm away supported, 1 mm away unsupported (contact is any direction, not only from below)
##   c OVERLAP    a 20 mm cube sunk 2 mm into the base is flagged against the base with 800 mm3 (hand 20 x 20 x 2), relative 1e-4 (float32
##                poses, G4); it still counts as supported. CONTROL: the cube resting on the base (0 mm) and sunk 0.001 mm (0.4 mm3, under
##                Part.HIT_VOL's 1 mm3) are not flagged
##   d CH15       the CH15 plant (ch15_site.assembly) rebuilt as stages from its own records (ch15_site.stages names -> ids, its "hang"
##                supports -> part "hang" ids, tol 20 mm = ch15 TOL) gives ch15 bar 7's verdict: every one of the 53 parts supported, as
##                ch15_site.support_check says. CONTROL: the dome-before-walls order (ch15 stages dome_first) reports the Shield dome
##                unsupported at its stage
##   e VIDEO      the coloured tower (base blue, walls green, roof red; 1 s per stage, 4 fps, drop-in 60 mm) filmed by AssemblyStage.video:
##                frame count = fps x total duration = 12; in every frame each colour is on screen (>= 50 px) exactly when its stage has
##                started (t = (k + 1) / fps >= the stage's start) and absent (0 px) before; the drop-in at 2.5 s lifts the roof by
##                60 x (1 - s(0.5)) = 30 mm (hand, 1e-6 mm). The last frame with a section cut (z = 50 mm) shows >= 500 cap-colour
##                (interior) pixels, the same frame uncut 0. CONTROL: a frozen schedule (all parts in one stage) gives 12 identical frames
##                (0 px differ), while the real schedule's frames 2 and 3 differ
##   f UI         the tower in the Assembly screen: Stages opens the panel; New stage x3 (base; roof; walls) and + Part build 3 stages in 4
##                undo steps; Check lists the roof unsupported and colours it (CONTROL); Down moves the roof stage last and Check is clean;
##                rename (one step), delete (one step: the roof is then there from the start), the time slider at 0.5 s shows only the base,
##                Play runs to the end with everything shown; Ctrl+Z back through every step gives the identical record. CONTROL: before the
##                undo the record differs. Shot C:/Temp/claude/g33stage/stages_check.png (LOOKED at)
##   g OLD        tests/assets/g1motion/old_assembly.json, g2loop/drive_199.json (#199), g7time/joint_204.json (#204), g8bom/anim_205.json
##                (#205) and g33stage/bom_206.json (#206, written by the #206 code before this branch) open in the screen, the Stages panel
##                opens, checks (no stages: says so) and closes, and they save back equal; AssemblyStage.pose_at shows every part.
##                CONTROL: the #206 record with one stage added does not compare equal
const S15 := preload("res://scripts/build/ch15_site.gd")
const OUT := "C:/Temp/claude/g33stage"
const OLD := ["res://tests/assets/g1motion/old_assembly.json", "res://tests/assets/g2loop/drive_199.json", "res://tests/assets/g7time/joint_204.json", "res://tests/assets/g8bom/anim_205.json", "res://tests/assets/g33stage/bom_206.json"]
const BLUE := [0.1, 0.2, 0.9]
const GREEN := [0.1, 0.8, 0.15]
const RED := [0.9, 0.1, 0.08]
const GREY := [0.7, 0.7, 0.7]
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


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-300)


## a box w x h x d mm with its low corner at the part's origin, one colour
func box_rec(nm: String, w: float, h: float, d: float, col: Array) -> Dictionary:
	return {"version": 1, "name": nm, "seq": 2, "features": [
		{"t": "prim", "id": "f1", "name": "Prim1", "kind": "box", "op": "new", "x": 0.0, "y": 0.0, "z": 0.0, "w": w, "h": h, "d": d},
		{"t": "appear", "id": "f2", "name": "Appear2", "body": 0.0, "color": col, "metal": 0.0, "rough": 0.8, "preset": "Custom"}]}


func put(asm: Dictionary, nm: String, rec: Dictionary, pos: Vector3) -> String:
	asm["seq"] = int(asm["seq"]) + 1
	var id := "p%d" % int(asm["seq"])
	asm["parts"].append({"id": id, "name": nm, "src": "", "rec": rec, "pos": [pos.x, pos.y, pos.z], "rot": [0.0, 0.0, 0.0]})
	return id


## base p1, wall A p2, wall B p3, roof p4 (mm); coloured when col
func tower(col := false) -> Dictionary:
	var asm := Assembly.make("Block tower")
	put(asm, "Base", box_rec("Base", 100, 20, 100, BLUE if col else GREY), Vector3.ZERO)
	put(asm, "Wall A", box_rec("Wall A", 10, 60, 100, GREEN if col else GREY), Vector3(0, 20, 0))
	put(asm, "Wall B", box_rec("Wall B", 10, 60, 100, GREEN if col else GREY), Vector3(90, 20, 0))
	put(asm, "Roof", box_rec("Roof", 100, 10, 100, RED if col else GREY), Vector3(0, 80, 0))
	return asm


func staged(asm: Dictionary, st: Array) -> Dictionary:
	var c := asm.duplicate(true)
	c["stages"] = []
	for s in st:
		(c["stages"] as Array).append({"name": s[0], "parts": s[1], "dur": 1.0})
	return c


func names_of(rows: Array) -> Array:
	return rows.map(func(r): return String(r["name"]))


# ------------------------------------------------------------------ a
func bars_tower() -> void:
	var t := tower()
	var good := staged(t, [["Base", ["p1"]], ["Walls", ["p2", "p3"]], ["Roof", ["p4"]]])
	var r := AssemblyStage.check(good)
	ok(bool(r["ok"]) and int(r["placed"]) == 4 and (r["unsupported"] as Array).is_empty() and (r["collisions"] as Array).is_empty(), "a tower base / walls / roof: %d of 4 placed, unsupported %s, collisions %s (%d kernel calls, %d ms)" % [int(r["placed"]), str(names_of(r["unsupported"])), str(names_of(r["collisions"])), int(r["kernel_calls"]), int(r["ms"])])
	var chain := AssemblyStage.check(staged(t, [["Base", ["p1"]], ["Walls and roof", ["p4", "p2", "p3"]]]))
	ok(bool(chain["ok"]) and (chain["unsupported"] as Array).is_empty(), "a the roof in the walls' stage (listed first) is held up through the walls: unsupported %s" % str(names_of(chain["unsupported"])))
	var bad := AssemblyStage.check(staged(t, [["Base", ["p1"]], ["Roof", ["p4"]], ["Walls", ["p2", "p3"]]]))
	var u: Array = bad["unsupported"]
	ctl(u.size() == 1 and String(u[0]["id"]) == "p4" and int(u[0]["stage"]) == 1 and String(u[0]["stage_name"]) == "Roof", "a roof before the walls: unsupported %s" % str(u.map(func(x): return "%s at stage %d %s" % [x["name"], int(x["stage"]), x["stage_name"]])))
	var fl := tower()
	put(fl, "Low", box_rec("Low", 20, 10, 20, GREY), Vector3(40, 21, 40))
	put(fl, "High", box_rec("High", 20, 10, 20, GREY), Vector3(40, 31, 40))
	var fr := AssemblyStage.check(staged(fl, [["Base", ["p1"]], ["Pair", ["p5", "p6"]]]))
	ctl((fr["unsupported"] as Array).size() == 2 and names_of(fr["unsupported"]).has("Low") and names_of(fr["unsupported"]).has("High"), "a two stacked blocks floating 1 mm over the base: unsupported %s" % str(names_of(fr["unsupported"])))


# ------------------------------------------------------------------ b
func one_block(pos: Vector3, sz := Vector3(20, 10, 20)) -> Dictionary:
	var t := tower()
	put(t, "Block", box_rec("Block", sz.x, sz.y, sz.z, GREY), pos)
	return AssemblyStage.check(staged(t, [["Base", ["p1"]], ["Walls", ["p2", "p3"]], ["Block", ["p5"]]]))


func bars_float() -> void:
	var gap := one_block(Vector3(40, 21, 40))
	var near := one_block(Vector3(40, 20.05, 40))
	ok(names_of(gap["unsupported"]) == ["Block"], "b block 1 mm above the base (tol %.2f mm): unsupported %s" % [float(gap.get("tol_mm", -1)), str(names_of(gap["unsupported"]))])
	ok(bool(near["ok"]) and (near["unsupported"] as Array).is_empty(), "b block 0.05 mm above the base: supported (unsupported %s)" % str(names_of(near["unsupported"])))
	var side := one_block(Vector3(100.05, 40, 40), Vector3(10, 10, 10))
	var sfar := one_block(Vector3(101, 40, 40), Vector3(10, 10, 10))
	ok(bool(side["ok"]) and names_of(sfar["unsupported"]) == ["Block"], "b on the side of wall B: 0.05 mm away supported (%s), 1 mm away unsupported (%s)" % [str(names_of(side["unsupported"])), str(names_of(sfar["unsupported"]))])


# ------------------------------------------------------------------ c
func bars_overlap() -> void:
	var sunk := one_block(Vector3(40, 18, 40), Vector3(20, 20, 20))
	var c: Array = sunk["collisions"]
	var mm3 := float(c[0]["mm3"]) if c.size() == 1 else -1.0
	ok(c.size() == 1 and String(c[0]["with"]) == "p1" and rel(mm3, 800.0) < 1e-4 and (sunk["unsupported"] as Array).is_empty(), "c cube sunk 2 mm into the base: %s with %s, %.6f mm3 vs hand 800 (rel %s); supported %s" % [c[0]["name"] if c.size() > 0 else "-", c[0]["with_name"] if c.size() > 0 else "-", mm3, str(rel(mm3, 800.0)), str((sunk["unsupported"] as Array).is_empty())])
	var rest := one_block(Vector3(40, 20, 40), Vector3(20, 20, 20))
	var tiny := one_block(Vector3(40, 19.999, 40), Vector3(20, 20, 20))
	ctl((rest["collisions"] as Array).is_empty() and (tiny["collisions"] as Array).is_empty() and bool(rest["ok"]) and bool(tiny["ok"]), "c resting (0 mm) and sunk 0.001 mm (0.4 mm3 < 1 mm3): collisions %s / %s" % [str(names_of(rest["collisions"])), str(names_of(tiny["collisions"]))])


# ------------------------------------------------------------------ d
func ch15_staged(dome_first: bool) -> Dictionary:
	var asm := S15.assembly()
	var by_name := {}
	for p in asm["parts"]:
		by_name[String(p["name"])] = String(p["id"])
	for p in asm["parts"]:
		var h: Array = []
		for sp in p["sup"]:
			if String(sp[1]) == "hang" and by_name.has(String(sp[0])):
				h.append(by_name[String(sp[0])])
		if not h.is_empty():
			p["hang"] = h
	asm["stages"] = []
	for s in S15.stages({"dome_first": dome_first}):
		(asm["stages"] as Array).append({"name": s["name"], "parts": (s["parts"] as Array).map(func(n): return by_name.get(String(n), "?" + String(n))), "dur": 1.0})
	asm["stage_opts"] = {"tol": S15.TOL * 1000.0, "ground": 0.0}
	return asm


func bars_ch15() -> void:
	var asm := ch15_staged(false)
	var n := (asm["parts"] as Array).size()
	var theirs := S15.support_check(S15.assembly(), S15.stages())
	var r := AssemblyStage.check(asm)
	var by := {}
	for id in r["support"]:
		var k := String(r["support"][id]["by"])
		by[k] = int(by.get(k, 0)) + 1
	print("     ch15 support by: %s; collisions with built parts: %d %s" % [str(by), (r["collisions"] as Array).size(), str((r["collisions"] as Array).slice(0, 8).map(func(c): return "%s x %s %.3f m3" % [c["name"], c["with_name"], float(c["mm3"]) * 1e-9]))])
	ok((r["unsupported"] as Array).is_empty() and int(r["placed"]) == n and n == 53 and bool(theirs["ok"]) and int(theirs["placed"]) == n, "d CH15 plant as stages: %d of %d supported (ch15 bar 7: %d of %d, ok %s); unsupported %s (%d ms)" % [int(r["placed"]) - (r["unsupported"] as Array).size(), n, int(theirs["placed"]), n, str(theirs["ok"]), str((r["unsupported"] as Array).map(func(x): return "%s at %s" % [x["name"], x["stage_name"]])), int(r["ms"])])
	var b := AssemblyStage.check(ch15_staged(true))
	var dome := (b["unsupported"] as Array).filter(func(x): return String(x["name"]) == "Shield dome")
	ctl(dome.size() == 1 and String(dome[0]["stage_name"]) == "Shield dome" and not bool(S15.support_check(S15.assembly(), S15.stages({"dome_first": true}))["ok"]), "d dome before the walls: unsupported %s" % str((b["unsupported"] as Array).map(func(x): return "%s at stage %d %s" % [x["name"], int(x["stage"]), x["stage_name"]])))


# ------------------------------------------------------------------ e
func col_px(img: Image, which: String) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var hit := false
			match which:
				"red":
					hit = c.r > c.g + 0.25 and c.r > c.b + 0.25
				"green":
					hit = c.g > c.r + 0.15 and c.g > c.b + 0.15
				"blue":
					hit = c.b > c.r + 0.2 and c.b > c.g + 0.1
			if hit:
				n += 1
	return n


func cap_px(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			for k in SectionLook.CAPS:
				if absf(c.r - k.r) < 0.03 and absf(c.g - k.g) < 0.03 and absf(c.b - k.b) < 0.03:
					n += 1
					break
	return n


func px_diff(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func bars_video() -> void:
	if DisplayServer.get_name() == "headless":
		ok(false, "e needs a screen (run windowed)")
		return
	var t := staged(tower(true), [["Base", ["p1"]], ["Walls", ["p2", "p3"]], ["Roof", ["p4"]]])
	t["stage_opts"] = {"fps": 4, "drop": 60.0}
	var r: Dictionary = await AssemblyStage.video(root, t, {"dir": OUT + "/e_stages", "width": 320, "height": 240, "keep_images": true})
	var imgs: Array = r.get("images", [])
	var want_n := int(round(4 * AssemblyStage.total(t)))
	ok(bool(r["ok"]) and int(r["n"]) == 12 and want_n == 12 and imgs.size() == 12, "e %d frames = 4 fps x %.1f s (%s; sheet %s, mp4 '%s')" % [int(r.get("n", 0)), AssemblyStage.total(t), String(r.get("why", "")), String(r.get("sheet", "")).get_file(), String(r.get("mp4", "")).get_file()])
	var sched_ok := imgs.size() == 12
	var rows: Array = []
	var starts := AssemblyStage.starts(t)
	for k in imgs.size():
		var tk := float(k + 1) / 4.0
		var line := "%d:" % k
		for pr in [["blue", 0], ["green", 1], ["red", 2]]:
			var n := col_px(imgs[k], String(pr[0]))
			var want := tk >= float(starts[int(pr[1])]) - 1e-9
			sched_ok = sched_ok and ((n >= 50) if want else (n == 0))
			line += " %s %d%s" % [String(pr[0]).left(1), n, "" if want else "(off)"]
		rows.append(line)
	ok(sched_ok, "e each stage's colour is on screen exactly from its start: " + " |".join(PackedStringArray(rows)))
	var po := AssemblyStage.pose_at(t, 2.5)
	var dy := ((po["moves"]["p4"] as Transform3D).origin.y / Assembly.MM) if (po["moves"] as Dictionary).has("p4") else -1.0
	var po3 := AssemblyStage.pose_at(t, 3.0)
	var dy3 := ((po3["moves"]["p4"] as Transform3D).origin.y / Assembly.MM) if (po3["moves"] as Dictionary).has("p4") else 0.0
	ok(absf(dy - 30.0) < 1e-6 and absf(dy3) < 1e-6, "e drop-in: the roof at 2.5 s is %.9f mm up (hand 60 x (1 - s(0.5)) = 30), at 3 s %.9f" % [dy, dy3])
	var cut: Dictionary = await AssemblyStage.video(root, t, {"dir": OUT + "/e_cut", "width": 320, "height": 240, "times": [3.0], "cut": {"n": Vector3(0, 0, 1), "w": 0.05}, "keep_images": true, "mp4": false, "sheet": false})
	var whole: Dictionary = await AssemblyStage.video(root, t, {"dir": OUT + "/e_whole", "width": 320, "height": 240, "times": [3.0], "keep_images": true, "mp4": false, "sheet": false})
	var cp := cap_px(cut["images"][0]) if (cut.get("images", []) as Array).size() == 1 else -1
	var wp := cap_px(whole["images"][0]) if (whole.get("images", []) as Array).size() == 1 else -1
	ok(cp >= 500 and wp == 0, "e section cut at z = 50 mm: %d interior (cap) px; the closed tower %d" % [cp, wp])
	var fz := t.duplicate(true)
	fz["stages"] = [{"name": "All", "parts": ["p1", "p2", "p3", "p4"], "dur": 3.0}]
	fz["stage_opts"] = {"fps": 4}
	var f: Dictionary = await AssemblyStage.video(root, fz, {"dir": OUT + "/e_frozen", "width": 320, "height": 240, "keep_images": true, "mp4": false})
	var fi: Array = f.get("images", [])
	var worst := -1
	if fi.size() == 12:
		worst = 0
		for k in range(1, 12):
			worst = maxi(worst, px_diff(fi[0], fi[k]))
	var d23 := px_diff(imgs[2], imgs[3]) if imgs.size() == 12 else -1
	ctl(fi.size() == 12 and worst == 0 and d23 > 100, "e frozen schedule: %d frames, worst %d px differ from frame 0; the real schedule's frames 2 / 3 differ in %d px" % [fi.size(), worst, d23])


# ------------------------------------------------------------------ f
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
	if c == null:
		print("     (no control to click)")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click(nm: String) -> void:
	await click_ctl(nd(nm) as Control)


func key(code: int, uni := 0, ctrl := false) -> void:
	for dn in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni
		e.ctrl_pressed = ctrl
		e.pressed = dn
		root.push_input(e, true)
		await process_frame


func shot(nm: String) -> void:
	await idle(4)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func open_screen() -> void:
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://g33stage_test"]
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


func stage_names() -> Array:
	return AssemblyStage.stages(A.asm).map(func(s): return String(s["name"]))


func bars_ui() -> void:
	await open_screen()
	A.open_record(tower(true))
	await idle(6)
	var before := JSON.stringify(A.asm, "", true)
	await click("asm_stages")
	ok(A.stages.is_open(), "f the Assembly panel's Stages button opens the panel")
	A.select("p1")
	await click("asm_stage_new")
	A.select("p4")
	await click("asm_stage_new")
	A.select("p2")
	await click("asm_stage_new")
	A.select("p3")
	await click("asm_stage_addpart")
	var st := AssemblyStage.stages(A.asm)
	var parts := st.map(func(s): return s["parts"])
	ok(st.size() == 3 and str(parts) == str([["p1"], ["p4"], ["p2", "p3"]]) and A.asm_undo.size() == 4, "f New stage x3 + Part: stages %s parts %s in %d undo steps" % [str(stage_names()), str(parts), A.asm_undo.size()])
	await click("asm_stage_check")
	var pl := (nd("asm_stage_problems") as Label).text
	ctl(pl.contains("Roof") and A.stages.bad_ids == ["p4"] and (A.meshes["p4"] as MeshInstance3D).material_overlay != null and (A.meshes["p1"] as MeshInstance3D).material_overlay == null, "f Check with the roof before the walls: '%s', coloured %s" % [pl.left(120), str(A.stages.bad_ids)])
	await shot("stages_check")
	await click("asm_stage_row_1")
	await click("asm_stage_down")
	await click("asm_stage_check")
	var pl2 := (nd("asm_stage_problems") as Label).text
	ok(str(AssemblyStage.stages(A.asm).map(func(s): return s["parts"])) == str([["p1"], ["p2", "p3"], ["p4"]]) and A.stages.bad_ids.is_empty() and A.asm_undo.size() == 5 and (A.meshes["p4"] as MeshInstance3D).material_overlay == null, "f Down moves the roof stage last (5 steps); Check: '%s'" % pl2.left(120))
	await click("asm_stage_row_2")
	var ne := nd("asm_stage_name") as LineEdit
	ne.text = "Roof"
	ne.text_submitted.emit("Roof")
	await idle(3)
	ok(stage_names()[2] == "Roof" and A.asm_undo.size() == 6, "f rename: %s (%d steps)" % [str(stage_names()), A.asm_undo.size()])
	var hs := nd("asm_stage_time") as HSlider
	hs.value = 0.5
	await idle(3)
	var vis := ["p1", "p2", "p3", "p4"].map(func(id): return (A.meshes[id] as MeshInstance3D).visible)
	ok(vis == [true, false, false, false], "f the time slider at 0.5 s shows only the base: %s" % str(vis))
	await click("asm_stage_play")
	var frames := 0
	while A.stages.playing and frames < 1200:
		await process_frame
		frames += 1
	await idle(2)
	var vis2 := ["p1", "p2", "p3", "p4"].map(func(id): return (A.meshes[id] as MeshInstance3D).visible)
	ok(not A.stages.playing and absf(A.stages.time - AssemblyStage.total(A.asm)) < 1e-6 and vis2 == [true, true, true, true], "f Play ran %d frames to %.2f s of %.2f; all shown %s" % [frames, A.stages.time, AssemblyStage.total(A.asm), str(vis2)])
	await click("asm_stage_row_2")
	await click("asm_stage_delete")
	ok(AssemblyStage.stages(A.asm).size() == 2 and AssemblyStage.stage_of(A.asm, "p4") == -1 and A.asm_undo.size() == 7, "f delete the roof stage: %d stages, the roof there from the start (%d steps)" % [AssemblyStage.stages(A.asm).size(), A.asm_undo.size()])
	var after := JSON.stringify(A.asm, "", true)
	ctl(after != before, "f before the undo the record differs")
	m.get_viewport().gui_release_focus()
	var n := A.asm_undo.size()
	for i in n:
		await key(KEY_Z, 0, true)
		await idle(2)
	var undone := JSON.stringify(A.asm, "", true)
	ok(undone == before and A.asm_undo.is_empty(), "f %d x Ctrl+Z: the record is identical to before (%s)" % [n, str(undone == before)])
	await click("asm_stage_close")


# ------------------------------------------------------------------ g
func sorted_json(path: String) -> String:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	return JSON.stringify(j, "", true) if j != null else ""


func through_screen(path: String) -> String:
	var rec := Assembly.read(path)
	if rec.is_empty():
		return ""
	A.open_record(rec)
	await idle(4)
	A.stages.open()
	await idle(3)
	A.stages.run_check()
	await idle(2)
	A.stages.close()
	await idle(2)
	return Assembly.save(A.asm)


func bars_old() -> void:
	var keep := Assembly.dir
	Assembly.dir = "user://g33stage_old"
	var rows: Array = []
	var all_ok := true
	for p in OLD:
		var saved: String = await through_screen(p)
		var eq := saved != "" and sorted_json(saved) == sorted_json(p)
		var j := Assembly.read(p)
		var po := AssemblyStage.pose_at(j, 0.0)
		var every := (po["visible"] as Array).size() == (j.get("parts", []) as Array).size() and not AssemblyStage.has_stages(j)
		all_ok = all_ok and eq and every
		rows.append("%s %s%s" % [String(p).get_file(), "equal" if eq else "DIFFERENT", "" if every else " (pose_at hides parts)"])
	ok(all_ok, "g old records through the screen (Stages opened, checked, closed) save back: %s" % ", ".join(PackedStringArray(rows)))
	var j := Assembly.read(OLD[4])
	AssemblyStage.add_stage(j, "Stage 1", [String(j["parts"][0]["id"])])
	var pk := Assembly.save(j)
	ctl(sorted_json(pk) != sorted_json(OLD[4]), "g the #206 record with one stage added does not compare equal")
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
		print("g33stage: %d fail" % fails)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	bars_tower()
	bars_float()
	bars_overlap()
	bars_ch15()
	await bars_video()
	await bars_ui()
	await bars_old()
	print("g33stage: %d fail" % fails)
	quit(1 if fails > 0 else 0)
