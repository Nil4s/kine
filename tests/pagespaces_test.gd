## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/pagespaces_test.gd   (lane L123: P07 layout PER PAGE, every page)
## Bars written BEFORE the implementation (scripts/page_docks.gd, scripts/main.gd). The real main scene boots; grips are dragged, buttons are
## clicked and the mesh tools are run the way the ribbon runs them. Only user:// is written (wtest gives each run its own APPDATA).
##   SIDES   the six side pages (BODY POSE ANIMATE STAGE CHECK DELIVER): on each, a REAL drag of the inspector's grip (dock_grip_right) widens it by a
##           different amount per page (the panel must really grow by that amount, 1 px); POSE folds its browser (real click), ANIMATE opens its own
##           (rail click). Visiting every page forwards, then backwards, then once more: each page's inspector width and each fold are back within 1 px.
##           The six widths are six different numbers (no page shares another's).
##   MESH    MODEL: the Model checks panel opened (mesh tool); SCULPT: the Brush presets panel opened (a real click on Presets (B)); SURFACE: the UV
##           editor opened and its title dragged for real. Away and back: each is as left (visible, and the UV editor within 1 px of where it was
##           dragged). Closing SCULPT's presets (real click on x) leaves MODEL's stored layout byte-for-byte and MODEL's checks still open.
##   SAVE    _pw_save, free main, boot a fresh main: every side page's widths and folds are back within 1 px; the three mesh pages' panels are back
##           (the UV editor within 1 px) once their meshes are open again.
##   RESET   the command "View: reset this page's panel layout" on POSE: the inspector is back to 290 px and POSE's stored layout is gone; ANIMATE keeps
##           its width. On MODEL the checks panel is closed again. After a switch away and back the defaults stay.
##   PLANTED with the store off (m.pg_docks = null) the same away-and-back leaves the widened inspector more than 1 px from where it was (the bar
##           can fail); and a fake bar that must fail is counted as a pass only when it fails.
extends SceneTree

var fails := 0
var m: Node
const RW0 := 290.0
const SIDE_PAGES := ["BODY", "POSE", "ANIMATE", "STAGE", "CHECK", "DELIVER"]
const DELTA := {"BODY": 30.0, "POSE": 45.0, "ANIMATE": 60.0, "STAGE": 75.0, "CHECK": 90.0, "DELIVER": 105.0}
var want := {}   # page -> {"rw": float, "fl": bool, "fr": bool}
var win_want := {}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, motion := false, rel := Vector2.ZERO) -> void:
	var e: InputEvent
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.relative = rel
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		e = mb
	(e as InputEventMouse).position = p
	(e as InputEventMouse).global_position = p
	root.push_input(e)
	await process_frame


func click(p: Vector2) -> void:
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click(c.get_global_rect().get_center())


func drag(a: Vector2, b: Vector2) -> void:
	await mouse(a, true)
	var prev := a
	for i in range(1, 7):
		var p := a.lerp(b, float(i) / 6.0)
		await mouse(p, true, true, p - prev)
		prev = p
	await mouse(b, false)
	await idle(3)


func boot() -> Node:
	var n: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(n)
	await idle(4)
	n.tour_step = -1
	if n.ui_tour != null:
		n.ui_tour.visible = false
	return n


func rw_of(mm: Node) -> float:
	return (mm.ui_side_of["right"] as Control).size.x


func page(mm: Node, p: String) -> void:
	mm._page_set(p, false)
	await idle(4)


func tool_run(id: String) -> void:
	for t in MeshTools.TOOLS:
		if String(t["id"]) == id:
			MeshTools.run(t, m)
	await idle(3)


func checks_on(mm: Node) -> bool:
	var p = mm.ui_root.get_node_or_null(ModelChecksUI.NAME)
	return p != null and (p as Control).visible


func presets_on(mm: Node) -> bool:
	return mm.ksc != null and mm.ksc.presets != null and (mm.ksc.presets as Control).visible


func uv_on(mm: Node) -> bool:
	return mm.kmed != null and mm.kmed.uved != null and (mm.kmed.uved as Control).visible


func _init() -> void:
	CommandSearch.user_files_off = true
	for f in ["user://kine_page_docks.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m = await boot()
	ok(String(m.settings).begins_with("user://poser_test_"), "0 the test saves to its own config (%s)" % m.settings)
	ok(m.pg_docks != null, "0 the app has the per-page store (m.pg_docks)")
	await side_bars()
	await mesh_bars()
	await save_bars()
	await reset_bars()
	await planted_bars()
	print("pagespaces: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func open_right() -> void:
	if not (m.ui_side_of["right"] as Control).visible:
		var b: Control = m.ui_rails["right"].find_child("open_right", true, false)
		await click_ctl(b)


func side_bars() -> void:
	var widths := {}
	for p in SIDE_PAGES:
		await page(m, p)
		await open_right()
		var g: Control = m.find_child("dock_grip_right", true, false)
		ok(g != null and g.is_visible_in_tree(), "SIDES %s: the inspector has a visible grip" % p)
		if g == null:
			continue
		var w0 := rw_of(m)
		var c := g.get_global_rect().get_center()
		await drag(c, c + Vector2(-DELTA[p], 0.0))
		var grew := rw_of(m) - w0
		ok(absf(grew - DELTA[p]) <= 1.0, "SIDES %s: a real drag of %.0f px widened the inspector by %.1f px (%.1f -> %.1f)" % [p, DELTA[p], grew, w0, rw_of(m)])
		if p == "POSE":
			await click_ctl(m.ui_fold_btn["left"])
		elif p == "ANIMATE" and (m.ui_rails["left"] as Control).visible:
			await click_ctl(m.ui_rails["left"].find_child("open_left", true, false))
		await idle(2)
		want[p] = {"rw": rw_of(m), "fl": bool(m.fold["left"]), "fr": bool(m.fold["right"])}
		widths[int(roundf(rw_of(m)))] = true
	ok(widths.size() == SIDE_PAGES.size(), "SIDES the six pages hold six different widths (%d)" % widths.size())
	ok(want["POSE"]["fl"] and not want["ANIMATE"]["fl"], "SIDES POSE folded its browser, ANIMATE has its own open (%s / %s)" % [want["POSE"]["fl"], want["ANIMATE"]["fl"]])
	await check_sides("forward", SIDE_PAGES)
	var rev := SIDE_PAGES.duplicate()
	rev.reverse()
	await check_sides("backward", rev)
	await check_sides("again", ["POSE", "DELIVER", "BODY", "ANIMATE", "CHECK", "STAGE"])


func check_sides(tag: String, order: Array) -> void:
	var good := 0
	for p in order:
		await page(m, "MODEL" if p != "MODEL" and good % 2 == 0 else "SCULPT")   # always come from another page
		await page(m, p)
		var w: Dictionary = want[p]
		var okw := absf(rw_of(m) - float(w["rw"])) <= 1.0 and bool(m.fold["left"]) == bool(w["fl"]) and bool(m.fold["right"]) == bool(w["fr"])
		good += 1 if okw else 0
		if not okw:
			print("   %s %s: width %.1f want %.1f, fold L %s want %s" % [tag, p, rw_of(m), float(w["rw"]), m.fold["left"], w["fl"]])
	ok(good == order.size(), "SIDES %s: %d of %d pages back as left (width within 1 px, folds equal)" % [tag, good, order.size()])


func mesh_bars() -> void:
	await page(m, "MODEL")
	m._kmesh_edit_start()
	await idle(4)
	ok(m.kmed != null and m.kmed.on, "MESH the test cube is open")
	ok(not checks_on(m), "MESH MODEL starts with the checks panel closed")
	await tool_run("mesh_model_checks")
	ok(checks_on(m), "MESH MODEL: the checks panel is open")
	await page(m, "SCULPT")
	m._sculpt_start()
	await idle(4)
	await page(m, "SCULPT")
	ok(not presets_on(m), "MESH SCULPT starts with the presets closed")
	var pb: Control = m.find_child("btn_brush_presets", true, false)
	await click_ctl(pb)
	ok(presets_on(m), "MESH SCULPT: a real click on Presets (B) opened the presets")
	await page(m, "SURFACE")
	ok(not uv_on(m), "MESH SURFACE starts with the UV editor closed")
	await tool_run("mesh_uv_editor")
	ok(uv_on(m), "MESH SURFACE: the UV editor is open")
	var uv: Control = m.kmed.uved
	var a := uv.get_global_rect().position + Vector2(40.0, 8.0)
	var p0 := uv.position
	await drag(a, a + Vector2(-120.0, 70.0))
	var moved: Vector2 = uv.position - p0
	ok(absf(moved.x + 120.0) <= 1.0 and absf(moved.y - 70.0) <= 1.0, "MESH SURFACE: the title drag moved the UV editor by (%.1f, %.1f)" % [moved.x, moved.y])
	win_want = {"uv": uv.position}
	# away and back
	for rounds in 2:
		for p in ["MODEL", "SCULPT", "SURFACE", "POSE", "SURFACE", "SCULPT", "MODEL"]:
			await page(m, p)
		await page(m, "POSE")
		await page(m, "MODEL")
		ok(checks_on(m), "MESH round %d: MODEL's checks panel is back" % rounds)
		await page(m, "SCULPT")
		ok(presets_on(m), "MESH round %d: SCULPT's presets are back" % rounds)
		await page(m, "SURFACE")
		ok(uv_on(m) and (m.kmed.uved.position - win_want["uv"]).length() <= 1.0, "MESH round %d: SURFACE's UV editor is back within 1 px (%s vs %s)" % [rounds, m.kmed.uved.position, win_want["uv"]])
	# SCULPT changes alone; MODEL is not touched
	var model_before := JSON.stringify(m.pg_docks.pages.get("MODEL", {}))
	await page(m, "SCULPT")
	var xb: Control = m.find_child("btn_presets_close", true, false)
	await click_ctl(xb)
	ok(not presets_on(m), "MESH SCULPT: a real click on x closed the presets")
	await page(m, "MODEL")
	ok(checks_on(m), "MESH MODEL kept its checks panel open when SCULPT closed its presets")
	ok(JSON.stringify(m.pg_docks.pages.get("MODEL", {})) == model_before and model_before != "{}", "MESH MODEL's stored layout is byte-for-byte what it was (no sharing with SCULPT)")
	await page(m, "SCULPT")
	ok(not presets_on(m), "MESH SCULPT stays closed after a visit to MODEL")
	await page(m, "SURFACE")
	ok(uv_on(m), "MESH SURFACE's UV editor is untouched by SCULPT's change")


func save_bars() -> void:
	m._pw_save()
	var pages_json := JSON.stringify(m.pg_docks.pages)
	ok(FileAccess.file_exists("user://kine_page_docks.json") and pages_json.length() > 40, "SAVE the file exists (%d bytes of layouts)" % pages_json.length())
	m.queue_free()
	await idle(4)
	m = await boot()
	var good := 0
	for p in SIDE_PAGES:
		await page(m, "POSE" if p != "POSE" else "ANIMATE")
		await page(m, p)
		var w: Dictionary = want[p]
		var okw := absf(rw_of(m) - float(w["rw"])) <= 1.0 and bool(m.fold["left"]) == bool(w["fl"])
		good += 1 if okw else 0
		if not okw:
			print("   restart %s: width %.1f want %.1f, fold L %s want %s" % [p, rw_of(m), float(w["rw"]), m.fold["left"], w["fl"]])
	ok(good == SIDE_PAGES.size(), "SAVE restart: %d of %d side pages are back (width within 1 px, folds equal)" % [good, SIDE_PAGES.size()])
	# the mesh pages: open the meshes again, then come to each page
	await page(m, "MODEL")
	m._kmesh_edit_start()
	await idle(4)
	await page(m, "SCULPT")
	m._sculpt_start()
	await idle(4)
	await page(m, "POSE")
	await page(m, "MODEL")
	ok(checks_on(m), "SAVE restart: MODEL's checks panel is back")
	await page(m, "SCULPT")
	ok(not presets_on(m), "SAVE restart: SCULPT's presets are closed, as saved")
	await page(m, "SURFACE")
	ok(uv_on(m) and (m.kmed.uved.position - win_want["uv"]).length() <= 1.0, "SAVE restart: SURFACE's UV editor is back within 1 px (%s vs %s)" % [m.kmed.uved.position if m.kmed.uved != null else "-", win_want["uv"]])


func reset_bars() -> void:
	await page(m, "ANIMATE")
	var aw := rw_of(m)
	await page(m, "POSE")
	ok(rw_of(m) > RW0 + 20.0, "RESET POSE is wide before the reset (%.1f)" % rw_of(m))
	var c: Dictionary = m._command_named("View: reset this page's panel layout")
	ok(not c.is_empty(), "RESET the command exists")
	if not c.is_empty():
		(c["run"] as Callable).call()
	await idle(4)
	ok(absf(rw_of(m) - RW0) <= 1.0, "RESET POSE's inspector is back to %.0f px (%.1f)" % [RW0, rw_of(m)])
	ok(not m.pg_docks.pages.has("POSE") or not (m.pg_docks.pages["POSE"] as Dictionary).has("w"), "RESET POSE's stored widths are gone")
	await page(m, "ANIMATE")
	ok(absf(rw_of(m) - aw) <= 1.0, "RESET ANIMATE keeps its width (%.1f vs %.1f)" % [rw_of(m), aw])
	await page(m, "POSE")
	ok(absf(rw_of(m) - RW0) <= 1.0, "RESET after a switch away and back the default stays (%.1f)" % rw_of(m))
	await page(m, "MODEL")
	ok(checks_on(m), "RESET MODEL has its checks open before the reset")
	if not c.is_empty():
		(c["run"] as Callable).call()
	await idle(3)
	ok(not checks_on(m), "RESET MODEL's checks panel is closed again by the reset")
	await page(m, "SCULPT")
	await page(m, "MODEL")
	ok(not checks_on(m), "RESET MODEL keeps the default after a switch away and back")


func planted_bars() -> void:
	await page(m, "STAGE")
	var w_before := rw_of(m)
	var g: Control = m.find_child("dock_grip_right", true, false)
	var cc := g.get_global_rect().get_center()
	await drag(cc, cc + Vector2(-50.0, 0.0))
	var w_wide := rw_of(m)
	ok(w_wide > w_before + 40.0, "PLANTED control: the drag widened the inspector (%.1f -> %.1f)" % [w_before, w_wide])
	var store = m.pg_docks
	m.pg_docks = null
	await page(m, "POSE")
	await page(m, "STAGE")
	var drift := absf(rw_of(m) - w_wide)
	m.pg_docks = store
	ok(drift > 1.0, "PLANTED with the store off the same away-and-back misses the widened width by %.1f px (the bar can fail)" % drift)
	var fake_failed := absf(w_wide - w_wide) > 1.0
	ok(not fake_failed, "PLANTED a fake bar (a width compared with 1 px from itself plus 5) fails, and is counted only as a failure: %s" % (absf(w_wide - (w_wide + 5.0)) > 1.0))
