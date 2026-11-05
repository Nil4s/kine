extends SceneTree
## godot --path . -s tests/g1motion_test.gd     (G1MOTION: clash detection while a mechanism MOVES, gap G1 of docs/CHALLENGE_FEEDBACK.md;
## scripts/build/assembly_motion.gd + assembly_motion_ui.gd; needs the CAD DLL with overlap_volume). Bars committed before the first run:
##   a HINGE   a lid on a hinge (z axis through the origin) under a ceiling block: 0 to 70 deg in 10 steps. Lid 80 mm long: 0 clashes.
##             CONTROL: the lid 5 mm longer clashes with the ceiling (not the base); the first clash angle is within one step (7 deg) after the hand
##             angle asin(79 / hypot(85, 5)) - atan2(5, 85) = 64.73 deg, and none before it
##   b LINK    a rack linked to a pinion drive (gain r pi / 180 mm per deg, r 12) and a gear (gain -20/40): the commanded values equal the hand
##             arithmetic to 1e-9 (float64); the posed transforms (float32) to 1e-4 mm / deg. CONTROL: a part with no link does not move
##   c CONTACT a block sliding along the face of another (face to face) has 0 clashes at every one of 5 steps, each pair asked of the kernel.
##             CONTROL: the slider 0.5 mm into the face clashes at every step, 200 mm3 at s = 0 and 100 mm3 at s = -10 (hand: 0.5 x 20 x overlap)
##   d ONCE    5 parts, 1 moving, 10 steps (11 samples), no box prefilter: kernel calls = C(4,2) + 4 x 11 = 50; with the prefilter, calls + skipped = 50.
##             CONTROL: a gain-0 link makes one more part "moving": C(3,2) + (3 x 2 + 1) x 11 = 80
##   e SPEED   7 parts x 36 steps under 5 s. CONTROL: without the box prefilter the same sweep asks the kernel more often
##   f UI      the S box's "Assembly: check motion" opens the panel; Add drive (typed range) is one undo step; Run lists Lid and Ceiling at 70 deg,
##             colours both red (not the base); the slider moves the lid on screen (35 deg: clear; 70 deg: CLASH) while the record keeps its pose;
##             Ctrl+Z takes the drive away and the screen back. Shots C:/Temp/claude/g1motion/swept.png, undone.png
##   g OLD     tests/assets/g1motion/old_assembly.json (written by the code before drives existed) loads, opens, runs Check motion's panel and
##             saves back equal (keys sorted). CONTROL: the same record with a drive added does not compare equal
const KCad := preload("res://scripts/kcad.gd")
const AM := preload("res://scripts/build/assembly_motion.gd")
const SHOT := "C:/Temp/claude/g1motion"
const OLD := "res://tests/assets/g1motion/old_assembly.json"
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


# ------------------------------------------------------------------ records
## a box part: x0..x1, y0..y1 on the front plane, z0..z1 (mm, its own frame)
func box_rec(nm: String, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> Dictionary:
	var fs: Array = []
	var pl := "front"
	if z0 != 0.0:
		fs.append({"t": "plane", "id": "f1", "name": "Plane1", "from": "front", "mm": z0})
		pl = "f1"
	var sk := "f%d" % (fs.size() + 1)
	fs.append({"t": "sketch", "id": sk, "name": "Sketch", "plane": pl, "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []})
	fs.append({"t": "extrude", "id": "f%d" % (fs.size() + 1), "name": "Extrude", "sketch": sk, "dist": z1 - z0, "both": false, "op": "new"})
	var rec := Part.make(nm)
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


func part(id: String, nm: String, rec: Dictionary, pos := [0.0, 0.0, 0.0]) -> Dictionary:
	return {"id": id, "name": nm, "src": "", "rec": rec, "pos": pos, "rot": [0.0, 0.0, 0.0]}


func asm_of(nm: String, parts: Array) -> Dictionary:
	var a := Assembly.make(nm)
	a["parts"] = parts
	a["seq"] = parts.size()
	return a


func hinge(lid_len: float, with_drive := true) -> Dictionary:
	var a := asm_of("Hinge %.0f" % lid_len, [
		part("p1", "Base", box_rec("Base", -10, -20, 0, 90, 0, 20)),
		part("p2", "Lid", box_rec("Lid", 0, 0, 0, lid_len, 5, 20)),
		part("p3", "Ceiling", box_rec("Ceiling", -20, 79, 0, 100, 89, 20))])
	if with_drive:
		AM.set_drive(a, AM.make_drive("Lid", "p2", "rotate", Vector3.BACK, Vector3.ZERO, 0.0, 70.0))
	return a


func pair_of(c: Dictionary) -> String:
	var s := [String(c["a"]), String(c["b"])]
	s.sort()
	return "%s|%s" % s


# ------------------------------------------------------------------ a
func bars_hinge() -> void:
	var b0: AABB = Assembly.built(box_rec("Lid", 0, 0, 0, 80, 5, 20))["aabb"]
	ok(b0.position.distance_to(Vector3.ZERO) < 1e-6 and b0.size.distance_to(Vector3(0.08, 0.005, 0.02)) < 1e-6, "a the lid record is the box 0..80 x 0..5 x 0..20 mm (built box %s m)" % str(b0))
	var r := AM.check_motion(hinge(80.0), "Lid", 10)
	ok(bool(r["ok"]) and (r["clashes"] as Array).is_empty() and int(r["pairs"]) == 3 and int(r["kernel_calls"]) > 0, "a lid 80 mm over 0..70 deg (11 samples): %d clashes, %d pairs, %d kernel calls, %d skipped, %d ms" % [(r["clashes"] as Array).size(), int(r["pairs"]), int(r["kernel_calls"]), int(r["skipped"]), int(r["ms"])])
	var rc := AM.check_motion(hinge(85.0), "Lid", 10)
	var th_hand := rad_to_deg(asin(79.0 / sqrt(85.0 * 85.0 + 25.0)) - atan2(5.0, 85.0))
	var first := INF
	var only_ceiling := true
	for c in rc["clashes"]:
		first = minf(first, float(c["at"]))
		only_ceiling = only_ceiling and pair_of(c) == "Ceiling|Lid"
	ctl(not (rc["clashes"] as Array).is_empty() and only_ceiling and first >= th_hand and first <= th_hand + 7.0, "a the lid 5 mm longer clashes with the ceiling only, first at %.1f deg (hand %.2f deg, one step 7 deg): %s" % [first, th_hand, AM.words(hinge(85.0), "Lid", rc)])


# ------------------------------------------------------------------ b
func bars_link() -> void:
	var r_p := 12.0
	var g_rack := r_p * PI / 180.0
	var a := asm_of("Rack and gears", [
		part("p1", "Pinion", box_rec("Pinion", -12, -12, 0, 12, 12, 10)),
		part("p2", "Rack", box_rec("Rack", -50, 12, 0, 50, 20, 10)),
		part("p3", "Gear", box_rec("Gear", -24, -24, 0, 24, 24, 10), [36.0, -40.0, 0.0]),
		part("p4", "Frame", box_rec("Frame", -60, -60, -10, 60, -50, 0))])
	AM.set_drive(a, AM.make_drive("Pinion", "p1", "rotate", Vector3.BACK, Vector3.ZERO, 0.0, 90.0))
	a["links"] = [AM.make_link("Pinion", "p2", "slide", Vector3.RIGHT, Vector3.ZERO, g_rack), AM.make_link("Pinion", "p3", "rotate", Vector3.BACK, Vector3(36, -40, 0), -20.0 / 40.0)]
	var v := 90.0
	var want_rack := 12.0 * PI / 2.0      # r x 90 deg in radians
	var want_gear := -45.0
	var got_rack := AM.value_of(a, "Pinion", v, "p2")
	var got_gear := AM.value_of(a, "Pinion", v, "p3")
	ok(absf(got_rack - want_rack) < 1e-9 and absf(got_gear - want_gear) < 1e-9, "b at 90 deg the rack moves %.12f mm (hand 12 pi / 2 = %.12f) and the gear turns %.12f deg (hand -45)" % [got_rack, want_rack, got_gear])
	var ps: Array = a["parts"]
	var dx := (AM.xf_at(a, "Pinion", v, ps[1]).origin - Assembly.xf_of(ps[1]).origin) / Assembly.MM
	var gx := AM.xf_at(a, "Pinion", v, ps[2])
	var g_ang := rad_to_deg(gx.basis.get_euler().z)
	var g_org := gx.origin / Assembly.MM
	ok(absf(dx.x - want_rack) < 1e-4 and Vector2(dx.y, dx.z).length() < 1e-4 and absf(g_ang - want_gear) < 1e-4 and g_org.distance_to(Vector3(36, -40, 0)) < 1e-4, "b posed: the rack slid %s mm, the gear turned %.6f deg about its own axis, its origin stayed at %s mm" % [str(dx), g_ang, str(g_org)])
	var fr := AM.xf_at(a, "Pinion", v, ps[3])
	ctl(fr.is_equal_approx(Assembly.xf_of(ps[3])) and AM.value_of(a, "Pinion", v, "p4") == 0.0, "b the frame (no link) stays put at 90 deg")


# ------------------------------------------------------------------ c
func slide_pair(y0: float) -> Dictionary:
	var a := asm_of("Slide", [part("p1", "Bed", box_rec("Bed", 0, 0, 0, 20, 10, 20)), part("p2", "Slider", box_rec("Slider", 0, y0, 0, 20, y0 + 10, 20))])
	AM.set_drive(a, AM.make_drive("Slide", "p2", "slide", Vector3.RIGHT, Vector3.ZERO, -10.0, 10.0))
	return a


func bars_contact() -> void:
	var r := AM.check_motion(slide_pair(10.0), "Slide", 4)
	ok(bool(r["ok"]) and (r["clashes"] as Array).is_empty() and int(r["kernel_calls"]) == 5 and int(r["skipped"]) == 0, "c face to face over 5 steps: %d clashes, %d kernel calls (every step asked), %d skipped" % [(r["clashes"] as Array).size(), int(r["kernel_calls"]), int(r["skipped"])])
	var rc := AM.check_motion(slide_pair(9.5), "Slide", 4)
	var at := {}
	for c in rc["clashes"]:
		at[snappedf(float(c["at"]), 0.001)] = float(c["mm3"])
	ctl(at.size() == 5 and absf(float(at.get(0.0, -1.0)) - 200.0) < 0.01 and absf(float(at.get(-10.0, -1.0)) - 100.0) < 0.01, "c 0.5 mm into the face clashes at all %d steps: %.4f mm3 at 0 (hand 200), %.4f mm3 at -10 (hand 100)" % [at.size(), float(at.get(0.0, -1.0)), float(at.get(-10.0, -1.0))])


# ------------------------------------------------------------------ d
func five(link_static: bool) -> Dictionary:
	var ps: Array = []
	for i in 4:
		ps.append(part("p%d" % (i + 1), "Post %d" % (i + 1), box_rec("Post", 0, 0, 0, 10, 10, 10), [30.0 * i, 0.0, 0.0]))
	ps.append(part("p5", "Arm", box_rec("Arm", 0, 0, 0, 10, 10, 10), [0.0, 40.0, 0.0]))
	var a := asm_of("Five", ps)
	AM.set_drive(a, AM.make_drive("Arm", "p5", "slide", Vector3.RIGHT, Vector3.ZERO, 0.0, 100.0))
	if link_static:
		a["links"] = [AM.make_link("Arm", "p4", "slide", Vector3.RIGHT, Vector3.ZERO, 0.0)]
	return a


func bars_once() -> void:
	var r0 := AM.check_motion(five(false), "Arm", 10, {"prefilter": false})
	var r1 := AM.check_motion(five(false), "Arm", 10)
	ok(int(r0["kernel_calls"]) == 50 and int(r0["skipped"]) == 0 and int(r1["kernel_calls"]) + int(r1["skipped"]) == 50 and int(r1["skipped"]) > 0, "d 4 still + 1 moving, 11 samples: %d kernel calls without the prefilter (hand 6 + 44 = 50); with it %d + %d skipped" % [int(r0["kernel_calls"]), int(r1["kernel_calls"]), int(r1["skipped"])])
	var rc := AM.check_motion(five(true), "Arm", 10, {"prefilter": false})
	ctl(int(rc["kernel_calls"]) == 80, "d a gain-0 link makes a post moving: %d calls (hand 3 + 7 x 11 = 80)" % int(rc["kernel_calls"]))


# ------------------------------------------------------------------ e
func seven() -> Dictionary:
	var a := hinge(85.0)
	var ps: Array = a["parts"]
	ps.append(part("p4", "Post A", box_rec("Post A", 0, 0, 0, 8, 60, 8), [60.0, 0.0, 22.0]))
	ps.append(part("p5", "Post B", box_rec("Post B", 0, 0, 0, 8, 60, 8), [20.0, 0.0, 22.0]))
	ps.append(part("p6", "Stop", box_rec("Stop", 0, 0, 0, 10, 10, 20), [-30.0, 40.0, 0.0]))
	ps.append(part("p7", "Peg", box_rec("Peg", 0, 0, 0, 6, 6, 30), [40.0, 30.0, -5.0]))
	a["seq"] = 7
	return a


func bars_speed() -> void:
	var r := AM.check_motion(seven(), "Lid", 36)
	ok(bool(r["ok"]) and (r["values"] as Array).size() == 37 and int(r["pairs"]) == 21 and int(r["ms"]) < 5000, "e 7 parts x 36 steps: %d ms (< 5000), %d pairs, %d kernel calls, %d skipped, %d clashes" % [int(r["ms"]), int(r["pairs"]), int(r["kernel_calls"]), int(r["skipped"]), (r["clashes"] as Array).size()])
	var rn := AM.check_motion(seven(), "Lid", 36, {"prefilter": false})
	ctl(int(rn["kernel_calls"]) > int(r["kernel_calls"]) and (rn["clashes"] as Array).size() == (r["clashes"] as Array).size(), "e without the box prefilter: %d kernel calls (> %d), %d ms, the same %d clashes" % [int(rn["kernel_calls"]), int(r["kernel_calls"]), int(rn["ms"]), (rn["clashes"] as Array).size()])


# ------------------------------------------------------------------ f (the screen)
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


func type_in(le: LineEdit, text: String) -> void:
	await click_ctl(le)
	le.select_all()
	for ch in text:
		var c := ch.unicode_at(0)
		var kc := KEY_0 + (c - 48) if (c >= 48 and c <= 57) else (KEY_PERIOD if ch == "." else KEY_MINUS)
		await key(kc, c)
	await key(KEY_ENTER)
	await idle(2)


func shot(nm: String) -> void:
	await idle(4)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func turn_deg(mi: MeshInstance3D) -> float:
	return rad_to_deg(mi.transform.basis.get_euler().z)


func bars_ui() -> void:
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://g1motion_test"]
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
	A.open_record(hinge(85.0, false))
	await idle(6)
	var before := JSON.stringify(A.asm, "", true)
	m.ui_cmd.open_with("check motion")
	await idle(3)
	var top := String(m.ui_cmd.shown[0]["name"]) if not m.ui_cmd.shown.is_empty() else ""
	await key(KEY_ENTER)
	await idle(4)
	var pnl := nd("asm_motion_panel") as Control
	ok(top == "Assembly: check motion" and pnl != null and pnl.is_visible_in_tree(), "f the S box finds '%s' first; Enter opens the Check motion panel (%s)" % [top, str(pnl != null and pnl.is_visible_in_tree())])
	await click_ctl(nd("asm_row_1") as Button)
	await type_in(nd("asm_motion_lo") as LineEdit, "0")
	await type_in(nd("asm_motion_hi") as LineEdit, "70")
	await type_in(nd("asm_motion_steps") as LineEdit, "10")
	await click_ctl(nd("asm_motion_add") as Button)
	var d := AM.drive_of(A.asm, "Lid")
	ok(not d.is_empty() and String(d["part"]) == "p2" and String(d["kind"]) == "rotate" and Vector3(d["axis"][0], d["axis"][1], d["axis"][2]) == Vector3.BACK and float(d["range"][1]) == 70.0 and A.asm_undo.size() == 1, "f Add drive on the selected Lid: %s, %d undo step" % [JSON.stringify(d), A.asm_undo.size()])
	await click_ctl(nd("asm_motion_run") as Button)
	await idle(3)
	var row := nd("asm_motion_row_0") as Label
	var rt := row.text if row != null else ""
	var red: Array = A.motion.red_ids()
	red.sort()
	ok(row != null and rt.contains("Lid") and rt.contains("Ceiling") and rt.contains("from 70 deg") and nd("asm_motion_row_1") == null, "f Run lists one pair: '%s'" % rt)
	ok(red == ["p2", "p3"] and A.meshes["p2"].material_overlay != null and A.meshes["p1"].material_overlay == null, "f the lid and the ceiling are red, the base is not (red: %s)" % str(red))
	var sl := nd("asm_motion_scrub") as HSlider
	sl.value = 35.0
	await idle(3)
	var at35 := (nd("asm_motion_at") as Label).text
	var lid35 := turn_deg(A.meshes["p2"])
	sl.value = 70.0
	await idle(3)
	var at70 := (nd("asm_motion_at") as Label).text
	var lid70 := turn_deg(A.meshes["p2"])
	var rec_rot: Array = A.asm["parts"][1]["rot"]
	ok(absf(lid35 - 35.0) < 1e-3 and absf(lid70 - 70.0) < 1e-3 and at35.ends_with("clear") and at70.contains("CLASH") and rec_rot == [0.0, 0.0, 0.0], "f the slider turns the lid on screen: %.3f deg ('%s'), %.3f deg ('%s'); the record's turn stays %s" % [lid35, at35, lid70, at70, str(rec_rot)])
	await shot("swept")
	m.get_viewport().gui_release_focus()
	await key(KEY_Z, 0, true)
	await idle(4)
	var after := JSON.stringify(A.asm, "", true)
	ok(after == before and not A.asm.has("drives") and A.meshes["p2"].material_overlay == null and absf(turn_deg(A.meshes["p2"])) < 1e-6 and nd("asm_motion_row_0") == null, "f Ctrl+Z: the record is as before (%s), no drive, no red, the lid back at %.4f deg" % [str(after == before), turn_deg(A.meshes["p2"])])
	await shot("undone")


# ------------------------------------------------------------------ g
func bars_old() -> void:
	var src := FileAccess.get_file_as_string(OLD)
	var rec := Assembly.read(OLD)
	var np := (rec["parts"] as Array).size() if not rec.is_empty() else 0
	ok(np == 2 and not rec.has("drives") and AM.drives(rec).is_empty() and Assembly.built(rec["parts"][0]["rec"])["mesh"] != null, "g the old record reads: %d parts, no drives, it builds" % np)
	var r := AM.check_motion(rec, "anything", 10)
	ok(not bool(r["ok"]) and String(r["why"]).contains("no drive"), "g Check motion on it says: %s" % String(r["why"]))
	if A != null:
		A.open_record(rec)
		await idle(4)
		A.motion.open()
		await idle(3)
		A.motion.close()
		await idle(2)
	var keep := Assembly.dir
	Assembly.dir = "user://g1motion_old"
	var path := Assembly.save(A.asm if A != null else rec)
	var saved := FileAccess.get_file_as_string(path)
	var j0 = JSON.parse_string(src)
	var j1 = JSON.parse_string(saved)
	ok(j0 != null and j1 != null and JSON.stringify(j0, "", true) == JSON.stringify(j1, "", true), "g saved back from the screen it is equal to the file (%d -> %d bytes, keys sorted)" % [src.length(), saved.length()])
	var dr: Dictionary = (j0 as Dictionary).duplicate(true)
	AM.set_drive(dr, AM.make_drive("Bracket", "p2", "rotate", Vector3.UP, Vector3.ZERO, 0.0, 10.0))
	Assembly.save(dr)
	var j2 = JSON.parse_string(FileAccess.get_file_as_string(path))
	ctl(JSON.stringify(j0, "", true) != JSON.stringify(j2, "", true) and (j2 as Dictionary).has("drives"), "g the same record with a drive saved does not compare equal")
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
	if not Part.available() or not ClassDB.class_has_method("KineCAD", "overlap_volume"):
		ok(false, "the CAD DLL with overlap_volume is missing")
		print("g1motion: %d fail" % fails)
		quit(1)
		return
	bars_hinge()
	bars_link()
	bars_contact()
	bars_once()
	bars_speed()
	await bars_ui()
	await bars_old()
	print("g1motion: %d fail" % fails)
	quit(1 if fails > 0 else 0)
