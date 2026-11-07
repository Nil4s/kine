## godot --path . -s tests/multiobj_test.gd     (LANE L120, ROADMAP_400 P10 Multi-object editing; needs a window; real clicks and drags)
## BEFORE THIS LANE: S.props had ONE pick (sel_prop); the outliner and the view picked one prop; no numeric transform panel
## existed for a prop (only Turn / Bigger / Delete buttons and the drag), so there was nothing to edit "several at once".
## THE FEATURE: Shift/Ctrl-click adds a prop to the selection; a small Transform panel (scripts/multi_panel.gd, logic in
## scripts/multi_edit.gd) edits every selected prop: an absolute value sets all of them, a drag on a field's label moves
## each by the same delta, a field whose values differ shows the mixed marker "—", and each edit is ONE undo step.
## BARS (written before the code; never moved after a run):
##  0 fixture: the screen point of each of the 4 props picks that prop.
##  1 three props picked by real clicks (plain, Shift, Ctrl): the selection is exactly those three, the fourth is not.
##  2 the panel shows "—" for X (three values) and for Rot (three yaws), a number for Y (all equal, 0.000).
##  3 X = 1.5 typed in the panel: all three origin.x == 1.5 EXACTLY; their y, z, yaw unchanged exactly; the fourth prop
##    byte-identical (var_to_str); exactly ONE undo step; the X field then shows 1.500, Z still "—".
##  4 one real Ctrl+Z restores all three (the whole prop list byte-identical to before: var_to_str).
##  5 a real drag of +10 px on the Rot label = +10 deg RELATIVE: each yaw is its own start + 10 (within 0.001 deg), the
##    three yaws keep their differences, fourth prop byte-identical, ONE undo step; Ctrl+Z byte-identical.
##  6 a real drag of +30 px on the X label = +0.30 m each (within 1e-5), the gaps between them kept; ONE step; undo exact.
##  7 SINGLE selection as before: a plain click selects one (the multi-selection clears), no field shows the marker,
##    X = 2.0 changes only that prop, and a real floor drag moves it by what the camera rays say (the old drag law, 1e-4),
##    one undo step, Ctrl+Z byte-identical.
##  8 PLANTED fake fails: (a) a set that reached only some of the three is told apart by the bar-3 check;
##    (b) a "relative" that gives every yaw start+10 of the FIRST prop (absolute in disguise) fails bar 5's differences check;
##    (c) a deliberately wrong expectation (X == 1.6) fails on the real result.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, shift := false, ctrl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func click(p: Vector2, shift := false, ctrl := false) -> void:
	mouse(p, true, shift, ctrl)
	await process_frame
	mouse(p, false, shift, ctrl)
	await idle(3)


func drag_px(a: Vector2, dx: float, steps: int) -> void:
	mouse(a, true)
	await idle(2)
	var p := a
	for k in steps:
		p += Vector2(dx / steps, 0)
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.relative = Vector2(dx / steps, 0)
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	mouse(p, false)
	await idle(3)


func drag_to(a: Vector2, b: Vector2) -> void:
	mouse(a, true)
	await idle(2)
	for k in range(1, 13):
		var mm := InputEventMouseMotion.new()
		mm.position = a.lerp(b, k / 12.0)
		mm.global_position = mm.position
		mm.relative = (b - a) / 12.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	mouse(b, false)
	await idle(3)


func ctrl_z() -> void:
	for d in [true, false]:
		var k := InputEventKey.new()
		k.keycode = KEY_Z
		k.physical_keycode = KEY_Z
		k.pressed = d
		k.ctrl_pressed = true
		root.push_input(k)
		await process_frame
	await idle(3)


func screen_of(i: int) -> Vector2:
	return m.cam.unproject_position((m.S.props[i]["xf"] as Transform3D).origin + Vector3(0, 0.25, 0))


func snap() -> String:
	return var_to_str(m.S.props)


func xs() -> Array:
	var o := []
	for i in 3:
		o.append((m.S.props[i]["xf"] as Transform3D).origin.x)
	return o


func yaws() -> Array:
	var o := []
	for i in 3:
		o.append(Props.yaw_of(m.S.props[i]["xf"]))
	return o


func typed(field: String, text: String) -> void:
	var le: LineEdit = m.multi_panel.edits[field]
	le.grab_focus()
	le.text = text
	le.text_submitted.emit(text)
	await idle(3)


## the check of bar 3 as a function of a prop list, so the planted fake runs through the same code
func all_x(props: Array, v: float) -> bool:
	for i in 3:
		if (props[i]["xf"] as Transform3D).origin.x != v:
			return false
	return true


## bar 5's differences check: the gaps a->b and b->c between three yaws are the same before and after
func gaps_kept(y0: Array, y1: Array) -> bool:
	for i in 2:
		var g0 := angle_difference(deg_to_rad(y0[i]), deg_to_rad(y0[i + 1]))
		var g1 := angle_difference(deg_to_rad(y1[i]), deg_to_rad(y1[i + 1]))
		if absf(angle_difference(g0, g1)) > deg_to_rad(0.001):
			return false
	return true


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.name = "zz_multiobj_test"
	m._view_dir(Vector3(0.0, 0.7, 1.0), false)
	m.dist = 10.0
	m._cam()
	var S: Scene = m.S
	S.props = []
	S.outl = {}
	var yaw0 := [0.0, 20.0, 45.0, 10.0]
	var px := [0.0, 1.2, 2.4, 3.5]   # the first run (x -3..1, z 3..4) clicked into nothing: those screen points are under the left UI; the 4th prop (3.5, 6) always picked
	var pz := [6.0, 6.0, 6.0, 6.0]
	for i in 4:
		S.props.append(Props.make("box", Props.xf_at(Vector3(px[i], 0, pz[i]), yaw0[i])))
	m.sel_prop = -1
	m._props_show()
	await idle(4)

	# ---- 0 / 1 selection by real clicks
	for i in 4:
		var hit: Array = m._pick_prop(screen_of(i))
		ok(int(hit[0]) == i, "0 fixture: the point on screen of prop %d picks prop %d (got %d)" % [i, i, int(hit[0])])
	await click(screen_of(0))
	await click(screen_of(1), true, false)
	await click(screen_of(2), false, true)
	var sel: Array = m._msel()
	sel.sort()
	ok(sel == [0, 1, 2], "1 plain + Shift + Ctrl clicks select exactly props 0,1,2 (got %s)" % [sel])
	ok(m.multi_panel != null and m.multi_panel.visible, "1 the Transform panel is shown")
	if m.multi_panel == null:
		print("RESULT multiobj fails=%d (no panel)" % fails)
		quit(1)
		return

	# ---- 2 mixed marker
	var mp = m.multi_panel
	ok(mp.edits["x"].text == "—", "2 X is mixed: shows the marker (got '%s')" % mp.edits["x"].text)
	ok(mp.edits["rot"].text == "—", "2 Rot is mixed: shows the marker (got '%s')" % mp.edits["rot"].text)
	ok(mp.edits["y"].text == "0.000", "2 Y is equal in all three: a number (got '%s')" % mp.edits["y"].text)

	# ---- 3 absolute set
	var before := snap()
	var rec: Array = []
	for i in 4:
		var xf: Transform3D = S.props[i]["xf"]
		rec.append([xf.origin.y, xf.origin.z, Props.yaw_of(xf)])
	var other_before := var_to_str(S.props[3])
	var n_undo: int = m.undo.size()
	await typed("x", "1.5")
	ok(all_x(S.props, 1.5), "3 X = 1.5 typed: all three origin.x == 1.5 exactly (%s)" % [xs()])
	var same := true
	for i in 3:
		var xf: Transform3D = S.props[i]["xf"]
		same = same and xf.origin.y == rec[i][0] and xf.origin.z == rec[i][1] and absf(Props.yaw_of(xf) - rec[i][2]) < 1e-9
	ok(same, "3 y, z and yaw of the three are unchanged")
	ok(var_to_str(S.props[3]) == other_before, "3 the fourth prop is byte-identical")
	ok(m.undo.size() == n_undo + 1, "3 exactly ONE undo step (%d -> %d)" % [n_undo, m.undo.size()])
	ok(mp.edits["x"].text == "1.500" and mp.edits["z"].text == "—", "3 X now shows 1.500, Z is still mixed (X '%s', Z '%s')" % [mp.edits["x"].text, mp.edits["z"].text])
	var fake: Array = []
	for p in S.props:
		fake.append(p.duplicate(true))
	var fx: Transform3D = fake[1]["xf"]
	fx.origin.x = 99.0
	fake[1]["xf"] = fx
	ok(not all_x(fake, 1.5), "8a PLANTED: a set that reached only some of the three is told apart")
	ok(not all_x(S.props, 1.6), "8c PLANTED: a wrong expectation (X == 1.6) fails on the real result")

	# ---- 4 one Ctrl+Z
	await ctrl_z()
	ok(snap() == before, "4 one Ctrl+Z restores the whole prop list byte-identical")

	# ---- 5 relative rotate (the selection survives the undo; set again so the bar does not depend on that)
	m.sel_props = [0, 1, 2]
	m.sel_prop = 2
	m._props_show()
	await idle(3)
	var y0 := yaws()
	var other5 := var_to_str(S.props[3])
	n_undo = m.undo.size()
	var lab: Label = mp.scrubs["rot"]
	await drag_px(lab.get_global_rect().get_center(), 10.0, 10)
	var y1 := yaws()
	var good := true
	for i in 3:
		good = good and absf(angle_difference(deg_to_rad(y0[i]), deg_to_rad(y1[i])) - deg_to_rad(10.0)) < deg_to_rad(0.001)
	ok(good, "5 relative +10 deg: each yaw = its own start + 10 (%s -> %s)" % [y0, y1])
	ok(gaps_kept(y0, y1), "5 the differences between the three yaws are kept")
	var disguise := [y0[0] + 10.0, y0[0] + 10.0, y0[0] + 10.0]
	ok(not gaps_kept(y0, disguise), "8b PLANTED: an absolute-in-disguise 'relative' fails the differences check")
	ok(var_to_str(S.props[3]) == other5, "5 the fourth prop is byte-identical")
	ok(m.undo.size() == n_undo + 1, "5 exactly ONE undo step (%d -> %d)" % [n_undo, m.undo.size()])
	await ctrl_z()
	ok(snap() == before, "5 Ctrl+Z restores byte-identical")

	# ---- 6 relative move
	m.sel_props = [0, 1, 2]
	m.sel_prop = 2
	m._props_show()
	await idle(3)
	var x0 := xs()
	n_undo = m.undo.size()
	lab = mp.scrubs["x"]
	await drag_px(lab.get_global_rect().get_center(), 30.0, 10)
	var x1 := xs()
	var good6 := true
	for i in 3:
		good6 = good6 and absf((x1[i] - x0[i]) - 0.30) < 1e-5
	ok(good6, "6 relative +30 px on X: each moved +0.30 m (%s -> %s)" % [x0, x1])
	ok(absf((x1[1] - x1[0]) - (x0[1] - x0[0])) < 1e-5 and absf((x1[2] - x1[1]) - (x0[2] - x0[1])) < 1e-5, "6 the gaps between them are kept")
	ok(m.undo.size() == n_undo + 1, "6 exactly ONE undo step (%d -> %d)" % [n_undo, m.undo.size()])
	await ctrl_z()
	ok(snap() == before, "6 Ctrl+Z restores byte-identical")

	# ---- 7 single selection as before
	await click(screen_of(3))
	ok(m._msel() == [3] and m.sel_prop == 3, "7 a plain click selects one prop and clears the multi-selection (got %s)" % [m._msel()])
	ok(mp.edits["x"].text != "—" and mp.edits["rot"].text != "—" and mp.edits["z"].text != "—", "7 one prop selected: no field shows the marker")
	var b7 := snap()
	n_undo = m.undo.size()
	await typed("x", "2.0")
	ok((S.props[3]["xf"] as Transform3D).origin.x == 2.0, "7 X = 2.0 sets the one prop")
	var others_same := true
	var b7_arr: Array = str_to_var(b7)
	for i in 3:
		others_same = others_same and var_to_str(S.props[i]) == var_to_str(b7_arr[i])
	ok(others_same, "7 the other three props are byte-identical")
	ok(m.undo.size() == n_undo + 1, "7 one undo step")
	await ctrl_z()
	ok(snap() == b7, "7 Ctrl+Z byte-identical")
	# the old drag law: the origin moves by (ray hit at the end - ray hit at the start) on the plane of the first hit
	var o3: Vector3 = (S.props[3]["xf"] as Transform3D).origin
	var a: Vector2 = m.cam.unproject_position(o3 + Vector3(0, 0.25, 0))
	var b: Vector2 = a + Vector2(60, 25)
	var ra: Vector3 = m.cam.project_ray_origin(a)
	var da: Vector3 = m.cam.project_ray_normal(a)
	var pick: Array = m._pick_prop(a)
	var hp0 := ra + da * float(pick[1])
	var rb: Vector3 = m.cam.project_ray_origin(b)
	var db: Vector3 = m.cam.project_ray_normal(b)
	var pb := rb + db * ((hp0.y - rb.y) / db.y)
	var expect_xz := Vector2(o3.x + pb.x - hp0.x, o3.z + pb.z - hp0.z)
	n_undo = m.undo.size()
	await drag_to(a, b)
	var o3b: Vector3 = (S.props[3]["xf"] as Transform3D).origin
	ok(Vector2(o3b.x, o3b.z).distance_to(expect_xz) < 1e-4, "7 a real floor drag follows the old drag law (got %.4f,%.4f want %.4f,%.4f)" % [o3b.x, o3b.z, expect_xz.x, expect_xz.y])
	ok(Vector2(o3b.x - o3.x, o3b.z - o3.z).length() > 0.05, "7 and it really moved")
	ok(m.undo.size() == n_undo + 1, "7 the drag is ONE undo step")
	await ctrl_z()
	ok(snap() == b7, "7 Ctrl+Z byte-identical after the drag")
	print("RESULT multiobj fails=%d" % fails)
	quit(1 if fails > 0 else 0)
