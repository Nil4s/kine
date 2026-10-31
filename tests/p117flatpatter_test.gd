extends SceneTree
## p117flatpatter (Friday plan 117, Kine's own): Flat pattern. The plain box of Easy Part (the Box chip) unfolds into a flat sheet for
## laser cutting: six panels in a cross, each cut edge a row of finger joints (about the sheet's 3 mm thick, a tab sticks out by that, the
## slot is cut in by that). The chip is in the Cut a hole row (Box -> Cut a hole -> Flat pattern). Nothing in the model changes.
## godot --path . --position 4000,4000 -s tests/p117flatpatter_test.gd     (needs a window and the CAD DLL; Docker box only)
## Bars, written before coding (real clicks through root.push_input at 1280 x 720; measured from the built result: the mesh AABB, the
## drawn outlines in mm, the counts of drawn finger tips, frames, undo steps):
##   1 CHIP      the Cut a hole row has a Flat pattern chip with plain words (no key names), next to Magnet
##   2 WALK      Flat pattern opens the sheet within 2 frames of the press; no undo step added; the model's volume is unchanged (1e-12 m3)
##   3 SIX       the sheet draws six closed panels (outline of at least 4 points each)
##   4 SIZE      the front panel (a face with no finger joint) is drawn X x Y mm, the built box's size, within 0.05 mm
##   5 FINGERS   the drawn finger tips: as many outward tabs as inward slots, each count = the sum over the 7 cut edges of (n + 1) / 2 with
##               n odd and about 3 mm wide (n from the built box's edge lengths); each tip is 2.5 to 3.5 mm long
##   6 FIT       the whole cross fits inside the drawn sheet (px), and the sheet is on screen inside the Easy Part panel
##   7 CLOSE     Close hides the sheet
## Shots in C:/Temp/claude/p117flatpatter/ . Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p117flatpatter"
const DIRT := "user://p117flatpatter_test"
const T_MM := 3.0


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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func shot(nm: String) -> void:
	await idle(4)
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT))
	img.save_png(SHOT + "/" + nm + ".png")


## the finger tips of the drawn outlines: a segment that runs along a panel edge, exactly T outside (a tab) or T inside (a slot) the
## panel's flat face (its rect, mm), and whose length is one of the finger widths of the built box (L / n). The corner notch walls are
## T long too, so only a length that is a finger width counts. Returns [outward, inward]
func tips(pieces: Array, widths: Array) -> Array:
	var out := 0
	var inn := 0
	for p in pieces:
		var r: Rect2 = p["rect"]
		var pts: PackedVector2Array = p["pts"]
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var len := a.distance_to(b)
			var is_w := false
			for ww in widths:
				is_w = is_w or absf(len - float(ww)) < 0.02
			if not is_w:
				continue
			if absf(a.x - b.x) < 0.01 and a.y >= r.position.y - 0.01 and b.y <= r.end.y + 0.01 and a.y <= r.end.y + 0.01 and b.y >= r.position.y - 0.01:
				var x := a.x
				if absf(x - (r.position.x - T_MM)) < 0.02 or absf(x - (r.end.x + T_MM)) < 0.02:
					out += 1
				elif absf(x - (r.position.x + T_MM)) < 0.02 or absf(x - (r.end.x - T_MM)) < 0.02:
					inn += 1
			elif absf(a.y - b.y) < 0.01 and a.x >= r.position.x - 0.01 and b.x <= r.end.x + 0.01 and a.x <= r.end.x + 0.01 and b.x >= r.position.x - 0.01:
				var y := a.y
				if absf(y - (r.position.y - T_MM)) < 0.02 or absf(y - (r.end.y + T_MM)) < 0.02:
					out += 1
				elif absf(y - (r.position.y + T_MM)) < 0.02 or absf(y - (r.end.y - T_MM)) < 0.02:
					inn += 1
	return [out, inn]


func bbox(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		r = r.expand(v)
	return r


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep

	# the walk: the Box chip, then Cut a hole, then Flat pattern
	await click_ctl(ep.chips["box"])
	await idle(3)
	var aabb0: AABB = Part.replay(m.S.part)["aabb"]
	var size_mm := aabb0.size / Part.MM
	var v0 := float(Part.replay(m.S.part)["volume"])
	await click_ctl(ep.make_btns["hole"])
	await idle(3)
	var flat_btn: Button = ep.hole_box.find_child("easypart_hole_flat", true, false)
	var words := String(flat_btn.text).to_lower() if flat_btn != null else ""
	var bad := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace"]
	var bad_hit := []
	for w in bad:
		if words.contains(w):
			bad_hit.append(w)
	ok(flat_btn != null and ep.hole_box.visible and words == "flat pattern" and bad_hit.is_empty() and ep.hole_btns.has("magnet"),
		"1 CHIP: the Cut a hole row has a \"Flat pattern\" chip (plain words; key names: %s)" % str(bad_hit))

	var undo_before: int = m.undo.size()
	var v_before := float(Part.replay(m.S.part)["volume"])
	var sheet: PanelContainer = ep.hole_box.get_parent().find_child("easypart_flat_sheet", true, false)
	ok(sheet == null or not sheet.visible, "2 WALK: no sheet before the press")
	var host: Node = ep.hole_box.get_parent()   # the sheet lives beside the hole row (the Easy Part panel), not under the EasyPart object
	var fp := flat_btn.get_global_rect().get_center()
	var f0 := Engine.get_process_frames()
	await ev_move(fp)
	await ev_mouse(fp, true)
	await ev_mouse(fp, false)   # a Button fires on release: the press and the release are the two frames counted
	var frames := Engine.get_process_frames() - f0
	await idle(2)
	sheet = host.find_child("easypart_flat_sheet", true, false)
	var v_after := float(Part.replay(m.S.part)["volume"])
	ok(sheet != null and sheet.visible and frames <= 2 and m.undo.size() == undo_before and absf(v_after - v_before) < 1e-12,
		"2 WALK: the sheet opens in %d frames; undo steps %d -> %d; volume %.9f -> %.9f m3" % [frames, undo_before, m.undo.size(), v_before, v_after])
	await shot("flat_sheet")

	var view: FlatPatternView = host.find_child("easypart_flat_view", true, false)
	var pieces: Array = view.pieces if view != null else []
	var closed := true
	for p in pieces:
		closed = closed and (p["pts"] as PackedVector2Array).size() >= 4
	ok(pieces.size() == 6 and closed, "3 SIX: the sheet draws %d panels, each an outline of 4 or more points" % pieces.size())

	var front := {}
	for p in pieces:
		if String(p["name"]) == "front":
			front = p
	var fb := bbox(front["pts"]) if not front.is_empty() else Rect2()
	ok(not front.is_empty() and absf(fb.size.x - size_mm.x) < 0.05 and absf(fb.size.y - size_mm.y) < 0.05,
		"4 SIZE: the front panel %.2f x %.2f mm, the built box %.2f x %.2f mm (within 0.05)" % [fb.size.x, fb.size.y, size_mm.x, size_mm.y])

	var want := 0
	var widths := []
	# the 7 cut edges, by length: Top-Left Z, Top-Right Z, Top-Back X, Bottom-Left Z, Bottom-Right Z, Bottom-Back X, Back-Left Y
	for L in [size_mm.z, size_mm.z, size_mm.x, size_mm.z, size_mm.z, size_mm.x, size_mm.y]:
		var n := 2 * int(floor(float(L) / (2.0 * T_MM))) + 1
		want += (n + 1) / 2
		widths.append(float(L) / n)
	var t := tips(pieces, widths)
	var w_ok := true
	for ww in widths:
		w_ok = w_ok and float(ww) >= 2.5 and float(ww) <= 3.5
	ok(int(t[0]) == int(t[1]) and int(t[0]) == want and w_ok and want > 0,
		"5 FINGERS: %d outward tabs, %d inward slots (want %d each); finger widths %s mm (2.5 to 3.5)" % [t[0], t[1], want, str(widths)])

	var fit := true
	if view != null:
		var sheet_px := view.sheet * view.px_per_mm
		fit = sheet_px.x <= view.size.x + 0.5 and sheet_px.y <= view.size.y + 0.5 and view.get_global_rect().intersects(ep.hole_box.get_parent().get_global_rect())
	ok(fit and sheet != null and sheet.get_global_rect().size.x > 0,
		"6 FIT: the cross fits the drawn sheet, the sheet is on screen at %s" % str(sheet.get_global_rect() if sheet != null else Rect2()))

	await click_ctl(sheet.find_child("easypart_flat_close", true, false))
	await idle(2)
	ok(not sheet.visible, "7 CLOSE: Close hides the sheet")

	print("p117flatpatter: %d fail" % fails)
	quit(1 if fails > 0 else 0)
