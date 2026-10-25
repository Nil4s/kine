## godot --path . -s tests/modelfix5_test.gd   (MODEL FIX ROUND 5, from walk-through 5, friction 1)
## Bars, stated before measuring:
##   a F3 (the search box), type "decimate to half", Enter: the test cube's triangles halve (192 -> ~96, within 10 %)
##     (the top row is the Model row that names it; Enter must run what the list shows first, not the typed words)
##   b GUARD: a pose phrase with no matching row ("raise the right arm 90") still goes to the words command (first row Pose:)
## Each bar fails on the walk-5 code (git show HEAD:scripts/command_search.gd in place): the FAIL line is in the report.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: Key, shift := false) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.shift_pressed = shift
		ev.pressed = down
		root.push_input(ev, true)
		await process_frame
	await idle(3)


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


func button(txt: String) -> void:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.text.strip_edges() == txt:
			var c: Vector2 = b.get_global_rect().get_center()
			for down in [true, false]:
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = down
				e.position = c
				e.global_position = c
				if down:
					e.button_mask = MOUSE_BUTTON_MASK_LEFT
				root.push_input(e, true)
				await process_frame
			await idle(10)
			return
	print("   no visible button '%s'" % txt)


## triangles of the edit mesh (a quad is two): what decimate counts
func tris(kmed) -> int:
	var n := 0
	for f in kmed.mesh.faces:
		n += f.size() - 2
	return n


func _init() -> void:
	get_root().size = Vector2i(1280, 720)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	if m.easy.on:
		await button("Switch to Expert")
		await idle(10)
	await button("MODEL")
	await button("Test cube")
	await idle(10)
	var kmed = m.kmed
	if kmed == null or not kmed.on:
		ok(false, "the test cube opened")
		quit(1)
		return
	var f0: int = tris(kmed)

	# a: F3, the phrase, Enter
	await key(KEY_F3)
	var opened: bool = m.ui_cmd != null and m.ui_cmd.visible
	ok(opened, "F3 opens the search box")
	await typed("decimate to half")
	await key(KEY_ENTER)
	await idle(20)
	var f1: int = tris(kmed)
	print("   triangles %d -> %d; status: %s" % [f0, f1, str(m.ui_status.text)])
	ok(f0 == 192 and f1 >= 86 and f1 <= 106, "a: decimate to half halves the triangles (%d -> %d, want 86..106: half of 192 +-10 %%)" % [f0, f1])

	# b: a guard, a phrase no row names still reaches the words command
	await key(KEY_F3)
	await typed("raise the right arm 90")
	await idle(4)
	var rows_now: Array = []
	for c in m.ui_cmd.shown:
		rows_now.append(String(c["name"]))
	await key(KEY_ENTER)
	await idle(10)
	var st := str(m.ui_status.text)
	print("   rows for the pose phrase: %s" % str(rows_now.slice(0, 3)))
	print("   status: %s" % st)
	ok(rows_now.size() > 0 and rows_now[0].begins_with("Pose: ") and st != "" and st.findn("decimated") < 0, "b: a phrase with no matching row goes to the words command (first row Pose:, status changed)")

	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
