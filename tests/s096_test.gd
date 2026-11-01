extends SceneTree
## s096 (Friday plan 96): Templates as recipes. Phone stand, Shelf bracket and Box with lid (What to build > Template) open as their STEPS: each step is
## named in the step list and changed from there (sizes in cm); Show me how plays them; Scrub the history replays from step 1.
## Real clicks at 1280 x 720 from the start screen; every number is measured from the BUILT result (the PartUI replay), expected values are plain arithmetic.
##   R1 phone stand: >= 3 NAMED steps in the step list (Base plate, Front lip, Back wedge), the list is on screen
##   R2 phone stand built: 1 body, box 100 x 100 x 80 mm (0.05), volume 247.52 cm3 (0.1 pct)
##   R3 Back wedge step opened, slid to 10 cm: bbox z grows by exactly the 20 mm (0.05), x and y unchanged, volume = +20 mm of the wedge section (0.1 pct)
##   R4 that change is an undo step; one Undo brings back the first box (0.05); a second change (Front lip) is its own undo step
##   R5 replay from step 1: Scrub to step 1 shows the base plate alone (48 cm3), Scrub to the end rebuilds the same volume (0.01 pct); a clean replay of the saved record agrees
##   R6 Show me how: Next walks the 3 named steps (words name them), Done leaves the model unchanged
##   R7 shelf bracket and box with lid: >= 3 named steps, bodies 1 / 2, volume 181.44 / 9609 cm3 (0.1 pct)
##   R8 no slider record (no "easy"): the recipe is only its steps
## shots: C:/Temp/claude/s096/phone.png, phone_edit.png, showhow.png, lid.png
const SHOT := "C:/Temp/claude/s096"
const DIRT := "user://s096_test"
var fails := 0
var m: Node


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
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## a real click on the slider's track at value v (the grabber centre sits at v; the track's ends keep half a grabber in)
func slide_to(sl: HSlider, v: float) -> void:
	if sl == null:
		fails += 1
		print("FAIL no slider to move")
		return
	var g := sl.get_theme_icon("grabber")
	var gw := float(g.get_width()) if g != null else 16.0
	var frac := (v - sl.min_value) / maxf(sl.max_value - sl.min_value, 0.0001)
	var lx := gw * 0.5 + frac * (sl.size.x - gw)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_move(p)
	await ev_mouse(p, false)
	await idle(12)


func mm(v: float) -> float:
	return v / Part.MM


## the built result the view shows: bodies, the box's size in mm, the volume in cm3 (from the replayed solids, not the code's numbers)
func built() -> Dictionary:
	var r: Dictionary = m.bld.part.res
	var bb: AABB = r.get("aabb", AABB())
	var vol := 0.0
	for v in r.get("volumes", []):
		vol += float(v)
	return {"bodies": int(r.get("bodies", 0)), "x": mm(bb.size.x), "y": mm(bb.size.y), "z": mm(bb.size.z), "cm3": vol / (Part.MM * Part.MM * Part.MM) / 1000.0}


## a real pick from What to build > Template: the card's Easy button opens the list, the list's item by its text (the same id the menu emits)
func pick(label: String) -> bool:
	var bc: BuildChoose = m.build_choose
	if not bc.open:
		var ob := find_named(m, "build_choose_open") as Control
		if ob != null and ob.is_visible_in_tree():
			await click_ctl(ob)
		else:
			bc.show_chooser()
		await idle(4)
	await click_ctl(bc.btns["template"]["easy"])
	await idle(4)
	var pm: PopupMenu = bc._starters
	if pm == null:
		return false
	for i in pm.item_count:
		if pm.get_item_text(i).begins_with(label):
			pm.id_pressed.emit(pm.get_item_id(i))
			await idle(30)
			return true
	return false


func step_rows() -> Array:
	var out := []
	var vb := find_named(m, "easypart_steps_list")
	if vb != null:
		for c in vb.get_children():
			if c is Button:
				out.append(c)
	return out


func named_rows(labels: Array) -> int:
	var n := 0
	for b in step_rows():
		for l in labels:
			if String((b as Button).text).begins_with(String(l) + ":"):
				n += 1
	return n


func row_for(label: String) -> Button:
	for b in step_rows():
		if String((b as Button).text).begins_with(label + ": pulled"):
			return b
	return null


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
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(20)
	var pu: PartUI = m.bld.part
	var ep = pu.ep

	# R1 / R2 the phone stand
	var picked := await pick("Part: Phone stand")
	await idle(20)
	var names3 := ["Base plate", "Front lip", "Back wedge"]
	var b1 := built()
	var box := find_named(m, "easypart_steps") as Control
	ok(picked and named_rows(names3) >= 3 and box != null and box.is_visible_in_tree(),
		"R1 phone stand opens with %d named steps in the step list (want >= 3), rows %s, list visible %s" % [named_rows(names3), str(step_rows().map(func(b): return (b as Button).text)), str(box != null and box.is_visible_in_tree())])
	var v0 := 247.52
	ok(b1["bodies"] == 1 and absf(b1["x"] - 100.0) <= 0.05 and absf(b1["y"] - 100.0) <= 0.05 and absf(b1["z"] - 80.0) <= 0.05 and absf(b1["cm3"] - v0) <= v0 * 0.001,
		"R2 phone stand built: %d body, box %.3f x %.3f x %.3f mm (want 100 x 100 x 80), volume %.3f cm3 (want %.2f)" % [b1["bodies"], b1["x"], b1["y"], b1["z"], b1["cm3"], v0])
	await shot("phone")

	# R3 / R4 open the Back wedge step, slide its How far to 10 cm: z grows by 20 mm; an undo step
	var u0: int = m.undo.size()
	await click_ctl(row_for("Back wedge"))
	var sl := find_named(m, "easypart_slider_last") as HSlider
	await slide_to(sl, 10.0)
	var b3 := built()
	var u1: int = m.undo.size()
	var wedge_area := 0.5 * 50.0 * 94.0   # mm2 of the wedge section (50 wide at the base, 94 tall above the plate)
	var want_v := v0 + wedge_area * 20.0 / 1000.0
	ok(b3["bodies"] == 1 and absf(b3["z"] - b1["z"] - 20.0) <= 0.05 and absf(b3["x"] - b1["x"]) <= 0.05 and absf(b3["y"] - b1["y"]) <= 0.05 and absf(b3["cm3"] - want_v) <= want_v * 0.001,
		"R3 Back wedge to 10 cm: z %.3f -> %.3f mm (want +20.000), x %.3f y %.3f unchanged, volume %.3f cm3 (want %.3f)" % [b1["z"], b3["z"], b3["x"], b3["y"], b3["cm3"], want_v])
	await shot("phone_edit")
	m._undo()
	await idle(20)
	var b4 := built()
	ok(u1 - u0 >= 1 and absf(b4["z"] - b1["z"]) <= 0.05 and absf(b4["cm3"] - v0) <= v0 * 0.001,
		"R4 the change took %d undo step(s); one Undo: z %.3f mm (want %.3f), volume %.3f cm3 (want %.2f)" % [u1 - u0, b4["z"], b1["z"], b4["cm3"], v0])
	var u_a: int = m.undo.size()
	await click_ctl(row_for("Front lip"))
	await slide_to(find_named(m, "easypart_slider_last") as HSlider, 3.0)
	var b4b := built()
	var u_b: int = m.undo.size()
	m._undo()
	await idle(20)
	var b4c := built()
	ok(u_b - u_a >= 1 and absf(b4b["cm3"] - v0) > 1.0 and absf(b4c["cm3"] - v0) <= v0 * 0.001,
		"R4b Front lip to 3 cm is its own undo step (%d): volume %.3f -> %.3f cm3, undo back to %.3f (want %.2f)" % [u_b - u_a, v0, b4b["cm3"], b4c["cm3"], v0])

	# R5 replay: scrub to step 1 (the base plate alone: 100 x 80 x 6 = 48 cm3), then to the end; a clean replay of the saved record agrees
	var n := int((m.S.part["features"] as Array).size())
	var rec_json := JSON.stringify(m.S.part)
	ep.scrub_sl.value = 2   # scrub position 2 = the base plate drawn AND pulled (position 1 is its bare sketch)
	await idle(20)
	var s1 := built()
	var nb := int((m.S.part["features"] as Array).size())
	ep.scrub_sl.value = ep.scrub_sl.max_value
	await idle(20)
	var s2 := built()
	var clean := Part.replay(JSON.parse_string(rec_json))
	var cv := 0.0
	for v in clean.get("volumes", []):
		cv += float(v)
	cv = cv / (Part.MM * Part.MM * Part.MM) / 1000.0
	ok(absf(s1["cm3"] - 48.0) <= 0.48 and nb == n and absf(s2["cm3"] - b4c["cm3"]) <= b4c["cm3"] * 0.0001 and absf(cv - b4c["cm3"]) <= b4c["cm3"] * 0.0001,
		"R5 scrub back to the first recipe step (Base plate): %.3f cm3 (want 48), record still %d steps; scrub to the end %.4f cm3 vs %.4f before (0.01 pct); clean replay of the saved record %.4f" % [s1["cm3"], nb, s2["cm3"], b4c["cm3"], cv])

	# R6 Show me how: Next walks the named steps; Done leaves the model unchanged
	var before := JSON.stringify(m.S.part)
	await click_ctl(find_named(m, "easypart_show_how") as Control)
	var dw := find_named(m, "easypart_demo_words") as Label
	var texts := []
	for i in 3:
		await click_ctl(find_named(m, "easypart_demo_next") as Control)
		texts.append(dw.text)
	await shot("showhow")
	await click_ctl(find_named(m, "easypart_demo_done") as Control)
	var same := JSON.stringify(m.S.part) == before
	ok(String(texts[0]).contains("Step 1 of 3: Base plate") and String(texts[1]).contains("Step 2 of 3: Front lip") and String(texts[2]).contains("Step 3 of 3: Back wedge") and same,
		"R6 Show me how names the 3 steps in order: [%s | %s | %s]; the model is unchanged after Done: %s" % [String(texts[0]).split("\n")[0], String(texts[1]).split("\n")[0], String(texts[2]).split("\n")[0], str(same)])

	# R8 no slider record
	ok(not (m.S.part as Dictionary).has("easy") and find_named(m, "easypart_slider_width") == null,
		"R8 the recipe is only its steps: easy key %s, template slider on the panel %s" % [str((m.S.part as Dictionary).has("easy")), str(find_named(m, "easypart_slider_width") != null)])

	# R7 the other two recipes
	picked = await pick("Part: Shelf bracket")
	await idle(20)
	var b7 := built()
	var vs := 181.44
	ok(picked and named_rows(["Shelf plate", "Upright", "Brace"]) >= 3 and b7["bodies"] == 1 and absf(b7["x"] - 200.0) <= 0.05 and absf(b7["y"] - 150.0) <= 0.05 and absf(b7["z"] - 40.0) <= 0.05 and absf(b7["cm3"] - vs) <= vs * 0.001,
		"R7a shelf bracket: %d named steps, %d body, box %.3f x %.3f x %.3f mm (want 200 x 150 x 40), volume %.3f cm3 (want %.2f)" % [named_rows(["Shelf plate", "Upright", "Brace"]), b7["bodies"], b7["x"], b7["y"], b7["z"], b7["cm3"], vs])
	picked = await pick("Part: Box with lid")
	await idle(20)
	var b8 := built()
	var vl := 9609.0
	ok(picked and named_rows(["Box", "Lid", "Lid handle"]) >= 3 and b8["bodies"] == 2 and absf(b8["x"] - 610.0) <= 0.05 and absf(b8["y"] - 150.0) <= 0.05 and absf(b8["z"] - 200.0) <= 0.05 and absf(b8["cm3"] - vl) <= vl * 0.001,
		"R7b box with lid: %d named steps, %d bodies, box %.3f x %.3f x %.3f mm (want 610 x 150 x 200), volume %.2f cm3 (want %.0f)" % [named_rows(["Box", "Lid", "Lid handle"]), b8["bodies"], b8["x"], b8["y"], b8["z"], b8["cm3"], vl])
	await shot("lid")

	print("s096: %d fail" % fails)
	quit(1 if fails > 0 else 0)
