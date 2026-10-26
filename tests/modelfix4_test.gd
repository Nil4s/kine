extends SceneTree
## MODEL FIX ROUND 4 (walk-through 4 of the expert MODEL page, driver tests/walk_model4_test.gd). Bars, stated before measuring:
##   a the S box runs a command and Ctrl+Z (real key events) takes that step back: the mesh's undo steps drop by 1
##   b Ctrl+Z after the material library opened (its search box holds the keyboard): the step still undoes (the walk's goal 6)
##   c clicking in the 3D view releases a focused text box (the library search)
##   d SURFACE has a visible Paint button, and pressing it turns vertex paint on (the S box's vpaint op)
## Each bar fails on the round-3 code (git show HEAD:<file> in place): the FAIL lines are in the report.
## Script errors are checked by the runner's log scan (a SCRIPT ERROR line fails the suite).
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1

func idle(n := 3) -> void:
	for i in n:
		await process_frame

func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame

func hover(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame
	await idle(2)

func click(p: Vector2) -> void:
	await hover(p)
	await mouse(p, true)
	await mouse(p, false)
	await idle(3)

func key(k: Key, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = down
		root.push_input(ev, true)
		await process_frame
	await idle(3)

## typed letters, one key down / up per character, with their unicode (the way the S box's line takes them)
func typed(s: String) -> void:
	for c in s:
		var code: int = c.to_upper().unicode_at(0)
		for down in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = code as Key
			ev.physical_keycode = code as Key
			ev.unicode = c.unicode_at(0)
			ev.pressed = down
			root.push_input(ev, true)
			await process_frame
	await idle(4)

## the on-screen rect of the edit mesh (its vertices projected); a zero rect when none is in view
func mesh_rect(m: Node) -> Rect2:
	var v: KMeshView = m.kmed.view
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in m.kmed.mesh.vert_count():
		var s: Variant = v._screen(m.cam, v._to_world(i))
		if s == null:
			continue
		lo = lo.min(s)
		hi = hi.max(s)
	return Rect2(lo, hi - lo)

func visible_button(txt: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.text == txt and bt.is_visible_in_tree():
			return bt
	return null

func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	await idle(2)
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(3)
	m._kmesh_edit_start()
	await idle(4)
	var kmed = m.kmed
	var fo_name := func() -> String:
		var fo: Control = m.get_viewport().gui_get_focus_owner()
		return "nothing" if fo == null else str(fo.name)

	# a: an S box command, then Ctrl+Z
	var s0: int = kmed.undo.steps.size()
	m.ui_cmd.open()
	await idle(2)
	await typed("subdivide")
	await key(KEY_ENTER)
	await idle(4)
	var s1: int = kmed.undo.steps.size()
	ok(s1 == s0 + 1, "a1 the S box runs 'subdivide': the mesh has one more undo step (%d -> %d)" % [s0, s1])
	await key(KEY_Z, true)
	var s2: int = kmed.undo.steps.size()
	ok(s2 == s1 - 1, "a2 Ctrl+Z after the S box command takes it back: undo steps %d -> %d (focus: %s)" % [s1, s2, fo_name.call()])

	# b: Ctrl+Z after the library opened (its search box has the keyboard)
	await key(KEY_1, true)
	var s3: int = kmed.undo.steps.size()
	var lib_btn: Button = visible_button("Library...")
	ok(lib_btn != null, "b0 the Materials panel's Library... button is visible")
	if lib_btn != null:
		await click(lib_btn.get_global_rect().get_center())
	await idle(4)
	var fo_lib: String = fo_name.call()
	ok(fo_lib == "matlib_search", "b1 Library... opens with its search box focused (focus: %s)" % fo_lib)
	await key(KEY_Z, true)
	var s4: int = kmed.undo.steps.size()
	ok(s4 == s3 - 1, "b2 Ctrl+Z with the library open undoes the mesh: steps %d -> %d (focus: %s)" % [s3, s4, fo_name.call()])

	# c: a click in the 3D view releases the focused text box
	await key(KEY_1, true)
	await idle(2)
	var lib_btn2: Button = visible_button("Library...")
	if lib_btn2 != null:
		await click(lib_btn2.get_global_rect().get_center())
	await idle(3)
	var mr := mesh_rect(m)
	var spot: Vector2 = mr.get_center()
	await click(spot)
	await idle(3)
	var fo_view: String = fo_name.call()
	ok(fo_view == "nothing" or fo_view != "matlib_search", "c a click in the 3D view (%s) releases the text box (focus: %s)" % [str(spot), fo_view])

	# d: SURFACE's Paint button turns vertex paint on
	m.ui_page_btns["SURFACE"].pressed.emit()
	await idle(4)
	var pb: Button = visible_button("Paint")
	ok(pb != null, "d1 SURFACE shows a visible Paint button")
	var vp = KMeshVPaintUI.of(m)
	var was_on: bool = vp.on
	if pb != null:
		await click(pb.get_global_rect().get_center())
	await idle(4)
	ok(not was_on and KMeshVPaintUI.of(m).on, "d2 pressing Paint turns vertex paint on (was %s, now %s)" % [str(was_on), str(KMeshVPaintUI.of(m).on)])

	print("modelfix4: %d failing" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
