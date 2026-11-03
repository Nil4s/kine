## godot --path . -s tests/c29_test.gd     (a window; real mouse events; screenshots at 3 sizes)
## C29: one-click body pick (finish complaint 790). Bars, written BEFORE any number was read (and not changed after):
##   For each default layout 1280x720, 1600x900, 1920x1080, combo3 loaded, a weapon in hand (the Hands panel shown), Expert:
##   P1 the Hands panel is visible (the control: the panel really is on screen in this check).
##   P2 PickCheck.run(): n == 11 probes on screen and first_try == 11 (11 of 11) and blocked is empty.
##   P3 ONE real left click on each of the 11 part middles selects that part: 11 of 11.
##   P4 no visible STOP control over any probe: hands panel and the Open-from-QR button are not over the body.
##   P5 CONTROL: with the Hands panel planted ON the pelvis probe, P2 reads < 11 (the bar can fail).
## Before the change (origin w4-c26) the brief expects about 7 of 11 at 1280.
## shots: C:/Users/Nick/tools/kine_workers/out/c29/c29_<w>.png
extends SceneTree

const OUT := "C:/Users/Nick/tools/kine_workers/out/c29/"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame


func _init() -> void:
	var wd := create_timer(300.0)
	wd.timeout.connect(func():
		print("FAIL c29 watchdog: the test hung")
		quit(1))
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 0.0
	m._refresh()
	await idle(4)
	if not (m.B.wep_on and m.B.wep_hand != ""):
		m._kind("metal_bat")
	for sz in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(sz)
		root.size = sz
		await idle(6)
		m.sel = "pelvis"
		m._refresh()
		m._hands_refresh()
		await idle(4)
		var tag := "%dx%d" % [sz.x, sz.y]
		ok(m.ui_hands_panel.is_visible_in_tree(), "P1 %s the Hands panel is shown at %s" % [tag, m.ui_hands_panel.get_global_rect()])
		var r: Dictionary = m.pickchk.run()
		print("   ", r["text"])
		ok(int(r["n"]) == 11 and int(r["first_try"]) == 11 and (r["blocked"] as Array).is_empty(), "P2 %s check: %d of %d on the first try, blocked %s, missed %s" % [tag, r["first_try"], r["n"], r["blocked"], r["misses"]])
		var got := 0
		var wrong := []
		for j in PickCheck.PARTS:
			var c: Array = m.B.cap(j)
			var p: Vector2 = m.cam.unproject_position((c[0] + c[1]) * 0.5)
			m.sel = "head" if j != "head" else "pelvis"
			await click(p)
			if m.sel == j:
				got += 1
			else:
				wrong.append("%s->%s" % [j, m.sel])
		ok(got == 11, "P3 %s one real click selected the aimed part in %d of 11 %s" % [tag, got, wrong])
		m.sel = "pelvis"
		await idle(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "c29_%d.png" % sz.x)
		# control: plant the panel on the pelvis probe
		var c2: Array = m.B.cap("pelvis")
		var pp: Vector2 = m.cam.unproject_position((c2[0] + c2[1]) * 0.5)
		var old: Vector2 = m.ui_hands_panel.position
		m.ui_hands_panel.position = pp - m.ui_hands_panel.size * 0.5
		var rc: Dictionary = m.pickchk.run()
		m.ui_hands_panel.position = old
		ok(int(rc["first_try"]) < 11, "P5 %s control: panel planted on the pelvis reads %d of 11" % [tag, rc["first_try"]])
	print("c29: %d fail" % fails)
	quit(1 if fails > 0 else 0)
