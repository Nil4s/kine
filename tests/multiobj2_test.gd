## godot --path . -s tests/multiobj2_test.gd     (LANE L125, follow-up to P10 multiobj; needs a window; real clicks and keys)
## BEFORE THIS LANE: the Outliner rows picked ONE prop (a Ctrl / Shift-click was a plain pick), and Delete, Turn left / right and
## Bigger / Smaller (Size) acted only on the last-picked prop, even with three picked in the view.
## THE FEATURE: Ctrl / Shift-click on Outliner prop rows adds / takes out props exactly as in the view (one selection, both ways;
## the picked rows are lit); Delete removes every picked prop in ONE undo step; Turn rotates each about its own origin by the
## same step; Size scales each by the same factor about its own origin. A single pick behaves as before.
## BARS (written before the code; never moved after a run):
##  0 fixture: 4 props, 4 Outliner rows, each row click point is inside the tree.
##  S baseline (single pick, recorded here from the CURRENT code before the change): picking prop i alone and turning 15 deg
##    changes only prop i, yaw +15 (1e-4 deg), origin identical; Size 1.15 changes only prop i, scale = old*1.15 snapped to 1e-4,
##    origin identical; Delete removes only prop i; each is ONE undo step and Ctrl+Z is byte-identical. The per-prop results
##    (var_to_str) are kept as the reference for the multi bars.
##  1 plain-click row 0, Ctrl-click rows 1 and 2: _msel() is exactly [0,1,2] in the viewport, the 4th is not picked, and the lit
##    rows are prop:0,1,2. Ctrl-click row 1 again takes it out (both sides: [0,2]); Shift-click puts it back.
##  2 the reverse: plain click prop 3 in the view, Ctrl-click props 1 and 2 in the view: the lit Outliner rows are prop:3,1,2.
##  3 Delete key with 0,1,2 picked: exactly 1 prop left, equal byte-for-byte to the old 4th; ONE undo step; Ctrl+Z restores the
##    whole prop list byte-identical.
##  4 Turn right with 0,1,2 picked: each prop byte-identical to the SAME prop turned alone (reference S), yaw +15 (1e-4 deg),
##    origins identical to the bit, the 4th byte-identical, ONE undo step, Ctrl+Z byte-identical.
##  5 Size (Bigger 1.15) with 0,1,2 picked: each byte-identical to the same prop sized alone, scale = old*1.15 snapped, origins
##    identical to the bit, the 4th byte-identical, ONE undo step, Ctrl+Z byte-identical.
##  6 PLANTED fakes: (a) a turn that reached only the last-picked prop fails bar 4's check; (b) a delete of only the last-picked
##    prop fails bar 3's count check; (c) a wrong expectation (yaw +16) fails on the real result.
extends SceneTree

var fails := 0
var m: Node
var br


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


func key(code: int, ctrl := false) -> void:
	for d in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = d
		k.ctrl_pressed = ctrl
		root.push_input(k)
		await process_frame
	await idle(3)


func orow(i: int) -> TreeItem:
	return br._outl_find("prop:%d" % i)


func row_pos(i: int) -> Vector2:
	var it := orow(i)
	br.scroll_to_item(it)
	await idle(2)
	var r: Rect2 = br.get_item_area_rect(it)
	return br.get_global_transform() * (r.position + Vector2(40.0, r.size.y * 0.5))


func screen_of(i: int) -> Vector2:
	return m.cam.unproject_position((m.S.props[i]["xf"] as Transform3D).origin + Vector3(0, 0.25, 0))


func snap() -> String:
	return var_to_str(m.S.props)


func sorted_msel() -> Array:
	var s: Array = m._msel().duplicate()
	s.sort()
	return s


func lit() -> Array:
	var s: Array = br.outl_lit_ids().duplicate()
	s.sort()
	return s


func pick_rows(ids: Array) -> void:
	await click(await row_pos(ids[0]))
	for k in range(1, ids.size()):
		await click(await row_pos(ids[k]), false, true)


## the multi-turn check of bar 4 as a function of the prop lists, so the planted fake runs through the same code
func turned_ok(props: Array, ref: Dictionary, n: int) -> bool:
	for i in n:
		if var_to_str(props[i]) != ref[i]:
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
	m.S.name = "zz_multiobj2_test"
	m._view_dir(Vector3(0.0, 0.7, 1.0), false)
	m.dist = 10.0
	m._cam()
	var S: Scene = m.S
	S.props = []
	S.outl = {}
	var yaw0 := [0.0, 20.0, 45.0, 10.0]
	var px := [0.0, 1.2, 2.4, 3.5]
	var pz := [5.6, 6.0, 6.4, 6.8]
	for i in 4:
		S.props.append(Props.make("box", Props.xf_at(Vector3(px[i], 0, pz[i]), yaw0[i])))
	m.sel_prop = -1
	m._props_show()
	await idle(4)
	br = m.ui_browser
	br._outl_root.collapsed = false
	br.set_outl_filter_all(true)
	br.set_outl_query("")
	br.refresh()
	await idle(4)

	# ---- 0 fixture
	var all_rows := true
	var inside := true
	for i in 4:
		all_rows = all_rows and orow(i) != null
		if orow(i) != null:
			var pp: Vector2 = await row_pos(i)
			inside = inside and br.get_global_rect().has_point(pp)
	ok(all_rows, "0 fixture: the Outliner has a row for each of the 4 props")
	ok(inside, "0 fixture: each row click point is inside the tree")
	if not all_rows:
		print("RESULT multiobj2 fails=%d (no rows)" % fails)
		quit(1)
		return

	# ---- S baseline: single pick, current behaviour, recorded per prop
	var before := snap()
	var ref_turn := {}
	var ref_size := {}
	var base_ok := true
	for i in 3:
		m._prop_select(i)
		await idle(2)
		var yb := Props.yaw_of(S.props[i]["xf"])
		var sb := Props.scale_of(S.props[i])
		var ob: Vector3 = (S.props[i]["xf"] as Transform3D).origin
		var n_undo: int = m.undo.size()
		m._prop_turn(15.0)
		await idle(2)
		var dy := absf(angle_difference(deg_to_rad(yb), deg_to_rad(Props.yaw_of(S.props[i]["xf"]))) + deg_to_rad(15.0))
		base_ok = base_ok and dy < deg_to_rad(1e-4) and (S.props[i]["xf"] as Transform3D).origin == ob and m.undo.size() == n_undo + 1
		for j in 4:
			if j != i:
				base_ok = base_ok and var_to_str(S.props[j]) == var_to_str((str_to_var(before) as Array)[j])
		ref_turn[i] = var_to_str(S.props[i])
		await key(KEY_Z, true)
		base_ok = base_ok and snap() == before
		m._prop_select(i)
		await idle(2)
		m._prop_resize(1.15)
		await idle(2)
		base_ok = base_ok and absf(Props.scale_of(S.props[i]) - snappedf(sb * 1.15, 0.0001)) < 1e-9 and (S.props[i]["xf"] as Transform3D).origin == ob
		ref_size[i] = var_to_str(S.props[i])
		await key(KEY_Z, true)
		base_ok = base_ok and snap() == before
	ok(base_ok, "S baseline: single pick, Turn 15 and Size 1.15 touch only that prop, one step each, undo byte-identical")
	m._prop_select(1)
	await idle(2)
	var n_u: int = m.undo.size()
	m._prop_del()
	await idle(2)
	ok(S.props.size() == 3 and m.undo.size() == n_u + 1, "S baseline: single Delete removes exactly one prop, one step (%d props)" % S.props.size())
	await key(KEY_Z, true)
	ok(snap() == before, "S baseline: Ctrl+Z after the single Delete is byte-identical")

	# ---- 1 outliner multi-pick -> viewport
	m.sel_prop = -1
	m.sel_props = []
	m._props_show()
	await idle(3)
	await pick_rows([0, 1, 2])
	ok(sorted_msel() == [0, 1, 2], "1 plain + Ctrl-click on rows 0,1,2: the viewport selection is exactly [0,1,2] (got %s)" % [sorted_msel()])
	ok(not m._msel().has(3), "1 the 4th prop is not picked")
	ok(lit() == ["prop:0", "prop:1", "prop:2"], "1 the lit rows are prop:0,1,2 (got %s)" % [lit()])
	await click(await row_pos(1), false, true)
	ok(sorted_msel() == [0, 2] and lit() == ["prop:0", "prop:2"], "1 Ctrl-click row 1 again takes it out, both sides: %s / %s" % [sorted_msel(), lit()])
	await click(await row_pos(1), true, false)
	ok(sorted_msel() == [0, 1, 2] and lit() == ["prop:0", "prop:1", "prop:2"], "1 Shift-click puts it back: %s / %s" % [sorted_msel(), lit()])

	# ---- 2 viewport multi-pick -> outliner
	m.sel_prop = -1
	m.sel_props = []
	m._props_show()
	await idle(3)
	await click(screen_of(3))
	await click(screen_of(1), false, true)
	await click(screen_of(2), false, true)
	ok(sorted_msel() == [1, 2, 3] and lit() == ["prop:1", "prop:2", "prop:3"], "2 view picks 3, 1, 2: the lit rows are prop:1,2,3 (msel %s, lit %s)" % [sorted_msel(), lit()])

	# ---- 4 Turn
	await pick_rows([0, 1, 2])
	var other := var_to_str(S.props[3])
	var org := []
	for i in 3:
		org.append((S.props[i]["xf"] as Transform3D).origin)
	var y0 := []
	for i in 3:
		y0.append(Props.yaw_of(S.props[i]["xf"]))
	var nu: int = m.undo.size()
	m.ui_prop_btns["Turn right"].pressed.emit()
	await idle(3)
	ok(turned_ok(S.props, ref_turn, 3), "4 Turn right with 3 picked: each prop is byte-identical to the same prop turned alone")
	var yok := true
	var ook := true
	for i in 3:
		yok = yok and absf(angle_difference(deg_to_rad(y0[i]), deg_to_rad(Props.yaw_of(S.props[i]["xf"]))) + deg_to_rad(15.0)) < deg_to_rad(1e-4)
		ook = ook and (S.props[i]["xf"] as Transform3D).origin == org[i]
	ok(yok, "4 each yaw moved by the same 15 deg step (1e-4 deg)")
	ok(ook, "4 positions unchanged to the bit")
	ok(var_to_str(S.props[3]) == other, "4 the 4th prop is byte-identical")
	ok(m.undo.size() == nu + 1, "4 exactly ONE undo step (%d -> %d)" % [nu, m.undo.size()])
	var fake: Array = str_to_var(before)
	fake[2] = S.props[2].duplicate(true)
	ok(not turned_ok(fake, ref_turn, 3), "6a PLANTED: a turn that reached only the last-picked prop is told apart")
	ok(absf(angle_difference(deg_to_rad(y0[0]), deg_to_rad(Props.yaw_of(S.props[0]["xf"]))) + deg_to_rad(16.0)) > deg_to_rad(0.5), "6c PLANTED: a wrong expectation (+16 deg) fails on the real result")
	await key(KEY_Z, true)
	ok(snap() == before, "4 Ctrl+Z byte-identical")

	# ---- 5 Size
	await pick_rows([0, 1, 2])
	nu = m.undo.size()
	var sc0 := []
	for i in 3:
		sc0.append(Props.scale_of(S.props[i]))
	m._prop_resize(1.15)
	await idle(3)
	ok(turned_ok(S.props, ref_size, 3), "5 Size 1.15 with 3 picked: each prop is byte-identical to the same prop sized alone")
	var sok := true
	ook = true
	for i in 3:
		sok = sok and absf(Props.scale_of(S.props[i]) - snappedf(sc0[i] * 1.15, 0.0001)) < 1e-9
		ook = ook and (S.props[i]["xf"] as Transform3D).origin == org[i]
	ok(sok, "5 each scale = its own old x 1.15 (snapped 1e-4)")
	ok(ook, "5 positions unchanged to the bit")
	ok(var_to_str(S.props[3]) == other, "5 the 4th prop is byte-identical")
	ok(m.undo.size() == nu + 1, "5 exactly ONE undo step (%d -> %d)" % [nu, m.undo.size()])
	await key(KEY_Z, true)
	ok(snap() == before, "5 Ctrl+Z byte-identical")

	# ---- 3 Delete
	await pick_rows([0, 1, 2])
	nu = m.undo.size()
	await key(KEY_DELETE)
	ok(S.props.size() == 1, "3 Delete with 3 picked leaves exactly 1 prop (got %d)" % S.props.size())
	ok(S.props.size() == 1 and var_to_str(S.props[0]) == other, "3 and it is the 4th, byte-identical")
	ok(m.undo.size() == nu + 1, "3 exactly ONE undo step (%d -> %d)" % [nu, m.undo.size()])
	ok(S.props.size() != 3, "6b PLANTED: a delete of only the last-picked prop would leave 3, which the count check rejects")
	await key(KEY_Z, true)
	ok(snap() == before, "3 one Ctrl+Z restores the whole prop list byte-identical")
	print("RESULT multiobj2 fails=%d" % fails)
	quit(1 if fails > 0 else 0)
