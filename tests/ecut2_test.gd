extends SceneTree
## godot --path . --position 4000,4000 -s tests/ecut2_test.gd     (ECUT2: Easy Part Cut in two keeps ONE half: scripts/easy_part.gd + the split step's "keep" field in scripts/build/part.gd; needs the CAD DLL)
## Monkey-brain direction: a sword from the start screen, Cut in two across the blade, then pick which half stays. Real clicks at 1280 x 720.
## Bars:
##   1 CUT     Cut in two on the sword: two bodies, ONE undo step (the old behaviour, kept)
##   2 UPPER   Keep the upper half (the tip side of the blade): ONE body, its box runs from the cut to the old far end, ONE undo step (FAILED on the old code: no keep chips)
##   3 SWITCH  Keep the lower half (switch the kept half): ONE body, its box runs from the old near end to the cut, ONE undo step
##   4 UNDO    Undo after the switch: the two halves are back (two bodies), one step back
##   5 BOTH    Keep both halves: two bodies again, the volume is the cut's volume (within 1 pct), ONE undo step
##   6 SLIDER  the slider still moves the cut with the keep chip on: the kept half's near end follows it (within 3 mm), ONE undo step
## Shot: C:/Temp/claude/ecut2/keep.png
const SHOT := "C:/Temp/claude/ecut2"
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
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func aabb_mm(pu) -> Array:
	var bb: AABB = pu.res.get("aabb", AABB())
	return [bb.position.x / 0.001, bb.end.x / 0.001]


## Nick 2026-10-28 (7089ca07): Easy Part opens EMPTY now; the weapons and props are not chips (only Box .. Plate are). A bar
## that needs one picks it itself, as a beginner does: the chip if it is shown, else More examples -> From a template -> the item.
## The panel scroll goes back to its top (the picked part's sliders sit at the top, as after a chip click)
func pick_part(t: String) -> void:
	var chip := root.find_child("easypart_chip_" + t, true, false) as Button
	if chip != null and chip.is_visible_in_tree():
		await click_ctl(chip)
		await idle(3)
		return
	await click_ctl(root.find_child("easypart_more_examples", true, false) as Control)
	await idle(10)
	var bc: BuildChoose = m.build_choose
	await click_ctl(bc.btns["template"]["easy"])
	await idle(4)
	bc._starters.id_pressed.emit(1000 + PartTemplates.ORDER.find(t))
	await idle(20)
	var sc := root.find_child("easypart_panel_scroll", true, false) as ScrollContainer
	if sc != null:
		sc.scroll_vertical = 0
		await idle(3)

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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ecut2_test"))
	ss.dirs_override = ["user://ecut2_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, Cut in two cannot run")
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	# Nick 2026-10-28 (7089ca07): the sword is not a chip any more; navigation only, the bar is not about the pick
	await pick_part("sword")
	await idle(4)
	var vol0 := float(pu.res.get("volume", 0.0))
	var ub: int = m.undo.size()
	# 1 CUT
	await click_ctl(ep.make_btns["split"])
	var sp := last_of(m.S.part, "split")
	var at_mm := float(sp.get("at", 0.0))
	var vol1 := float(pu.res.get("volume", 0.0))
	ok(int(pu.res.get("bodies", 0)) == 2 and m.undo.size() == ub + 1 and absf(vol1 - vol0) < 0.01 * vol0,
		"1 Cut in two on the sword: two bodies, volume kept, ONE undo step (%d -> %d) [%s]" % [ub, m.undo.size(), ep.hint_l.text])
	# 2 UPPER
	var ub2: int = m.undo.size()
	var up: Control = root.find_child("easypart_split_upper", true, false)
	if up != null:
		await click_ctl(up)
	var bb2 := aabb_mm(pu)
	ok(up != null and int(pu.res.get("bodies", 0)) == 1 and m.undo.size() == ub2 + 1 and absf(float(bb2[0]) - at_mm) < 3.0 and absf(float(bb2[1]) - aabb_mm(pu)[1]) < 3.0 and float(pu.res.get("volume", 0.0)) < vol1 - 0.01 * vol0 and float(pu.res.get("volume", 0.0)) > 0.0,
		"2 Keep the upper half: ONE body from the cut (%.0f mm) to the far end (%.0f..%.0f mm), ONE undo step (%d -> %d) [%s]" % [at_mm, bb2[0], bb2[1], ub2, m.undo.size(), ep.hint_l.text])
	# 3 SWITCH
	var ub3: int = m.undo.size()
	var lo: Control = root.find_child("easypart_split_lower", true, false)
	if lo != null:
		await click_ctl(lo)
	var bb3 := aabb_mm(pu)
	ok(lo != null and int(pu.res.get("bodies", 0)) == 1 and m.undo.size() == ub3 + 1 and absf(float(bb3[1]) - at_mm) < 3.0 and float(bb3[0]) < float(bb2[0]) - 100.0,
		"3 Switch to the lower half: ONE body from the near end (%.0f mm) to the cut (%.0f mm), ONE undo step (%d -> %d)" % [bb3[0], bb3[1], ub3, m.undo.size()])
	await shot("keep")
	# 4 UNDO
	await click_ctl(ep.undo_btn)
	await idle(3)
	var ok4: bool = int(pu.res.get("bodies", 0)) == 1 and m.undo.size() == ub3
	ok(ok4, "4 Undo after the switch: the upper half is back (%d body), one step back (%d -> %d)" % [int(pu.res.get("bodies", 0)), ub3 + 1, m.undo.size()])
	# 5 BOTH
	var ub5: int = m.undo.size()
	var both: Control = root.find_child("easypart_split_both", true, false)
	if both != null:
		await click_ctl(both)
	var vol5 := float(pu.res.get("volume", 0.0))
	ok(both != null and int(pu.res.get("bodies", 0)) == 2 and absf(vol5 - vol1) < 0.01 * vol1 and m.undo.size() == ub5 + 1,
		"5 Keep both halves: two bodies, volume %.2f cm3 (cut %.2f), ONE undo step (%d -> %d)" % [vol5 * 1e6, vol1 * 1e6, ub5, m.undo.size()])
	# 6 SLIDER
	var up6: Control = root.find_child("easypart_split_upper", true, false)
	if up6 != null:
		await click_ctl(up6)
	var row: Dictionary = {}
	for rw in ep.rows:
		if rw["kind"] == "tweak":
			row = rw
	var sl: HSlider = row.get("slider", null)
	var ub6: int = m.undo.size()
	var at6 := float(last_of(m.S.part, "split").get("at", 0.0))
	if sl != null:
		await drag_slider(sl, sl.value + (sl.max_value - sl.min_value) * 0.25)
	var at6b := float(last_of(m.S.part, "split").get("at", 0.0))
	var bb6 := aabb_mm(pu)
	ok(sl != null and up6 != null and absf(at6b - at6) > 5.0 and absf(float(bb6[0]) - at6b) < 3.0 and int(pu.res.get("bodies", 0)) == 1 and m.undo.size() == ub6 + 1,
		"6 The slider moves the cut with the upper half kept: %.0f -> %.0f mm, the kept piece starts there (%.0f mm), ONE undo step" % [at6, at6b, bb6[0]])
	print("ecut2: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func last_of(rec: Dictionary, t: String) -> Dictionary:
	var out := {}
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			out = f
	return out
