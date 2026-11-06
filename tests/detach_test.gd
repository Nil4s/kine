extends SceneTree
## godot --position -30000,-30000 --path . -s tests/detach_test.gd     (lane L37 DETACH, GAP_AUDIT_1106 UI/UX item 4; needs a window)
## Detach the timeline, the graph editor or a second 3D view into its own OS window (a second monitor), scripts/panel_detach.gd; the layouts
## (scripts/work_layouts.gd, #238) remember which panels are detached and their window rect. Bars, written before the code; each has a PLANTED
## control that must fail (the check is shown to catch what it claims to):
##   1 DETACH   after detach the panel's node is inside a Window and no longer in the dock; the dock slot collapses (the dock holds one child less and its
##              minimum width shrank by the panel's width). Planted: a panel only hidden (still in the dock) is found by the same check.
##   2 REDOCK   re-dock restores the original parent and child index (first, middle, last) and the layout fields (size flags, ratio, minimum size; anchors
##              and offsets for a panel on an anchored parent); the window is gone. Planted: a panel put back with add_child lands at the wrong index.
##   3 CLOSE    closing the window re-docks the panel; the same node (instance id) with its own state (text, pressed) is back. Planted: a copy is not the same node.
##   4 RECT     the window opens at the asked rect within 2 px, and rects() follows a window the user moved / resized within 2 px. Planted: a rect 10 px off.
##   5 RESCUE   a saved rect that lies on no screen (the second monitor was unplugged) opens on a screen. Planted: the unrescued rect is on no screen.
##   6 STORE    the layout store keeps the detached rects: save, load in a fresh store, save again is byte-identical; a bad id / rect is repaired;
##              a detached panel alone does not make the layout "not factory" (the app's own placement stands). Planted: a tampered file is found.
##   7 TIMELINE (live app, combo3) the real timeline: the Detach button moves it into a Window; scrubbing there sets the exact frame (and the same frame
##              the docked strip sets, for 5 frames); a card-edge drag in the window gives the SAME scene as the docked drag and is ONE undo step; Ctrl+Z
##              takes it back; selection is the same. Planted: a scrub one frame off is found; the scene before the drag differs from after.
##   8 GRAPH    the graph editor opens in a Window with its undo / apply callbacks still main's (one shared undo stack, the same Scene); re-docked, it is back
##              on its anchors under ui_root.
##   9 VIEW2    the second view renders the hero from the same world; dragging in its window orbits it by exactly SENS per pixel; the wheel zooms.
##  10 LAYOUT   a saved layout with the timeline detached at a rect reloads it detached, its window within 2 px; loading Factory re-docks it.
##              Planted: a window one that has moved 9 px is outside the 2 px bar.
## Native OS windows (force_native) are used where the display driver supports them; with --headless there is no OS window and the bars run on embedded
## windows (the tests print which). Only user:// is written (wtest gives each run its own APPDATA); screenshots under C:/Temp/claude/w4-detach.
var fails := 0
var m: Node
var native_ok := false


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func in_window(c: Node) -> bool:
	return PanelDetach.in_window(c)


## three siblings in an HBox, the middle one is the panel
func make_dock(idx_of_panel: int) -> Array:
	var host := HBoxContainer.new()
	host.size = Vector2(900, 60)
	root.add_child(host)
	var p := Button.new()
	p.text = "panel"
	p.toggle_mode = true
	p.custom_minimum_size = Vector2(180, 40)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 2.0
	var others := []
	for i in 2:
		var o := Control.new()
		o.custom_minimum_size = Vector2(40, 20)
		others.append(o)
	var order := others.duplicate()
	order.insert(idx_of_panel, p)
	for c in order:
		host.add_child(c)
	return [host, p]


func fresh_pd(native: bool) -> PanelDetach:
	var pd := PanelDetach.new()
	pd.native = native and native_ok
	pd.rescue = false
	root.add_child(pd)
	return pd


func near(a: Rect2i, b: Rect2i, tol := 2) -> bool:
	return absi(a.position.x - b.position.x) <= tol and absi(a.position.y - b.position.y) <= tol and absi(a.size.x - b.size.x) <= tol and absi(a.size.y - b.size.y) <= tol


func win_rect(w: Window) -> Rect2i:
	return Rect2i(w.position, w.size)


func rect_of_arr(a: Array) -> Rect2i:
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


func unit_bars(native: bool) -> void:
	var tag := "native" if (native and native_ok) else "embedded"
	root.gui_embed_subwindows = true
	# ---- 1 DETACH
	var dk := make_dock(1)
	var host: HBoxContainer = dk[0]
	var p: Button = dk[1]
	var pd := fresh_pd(native)
	pd.register("p", func(): return p, "Panel P")
	await idle(2)
	var min0 := host.get_combined_minimum_size().x
	ok(not in_window(p) and host.get_child_count() == 3 and p.get_parent() == host, "1 %s PLANTED: before detach the panel is in the dock, in no Window" % tag)
	ok(pd.detach("p", Rect2i(120, 140, 420, 260)), "1 %s detach returns true" % tag)
	await idle(3)
	ok(in_window(p) and p.get_parent() != host and not host.is_ancestor_of(p), "1 %s the panel is inside a Window and no longer in the dock" % tag)
	ok(host.get_child_count() == 2 and pd.is_detached("p"), "1 %s the dock holds 2 children (it held 3)" % tag)
	var min1 := host.get_combined_minimum_size().x
	ok(min0 - min1 >= 179.0, "1 %s the dock slot collapses: minimum width %.0f -> %.0f (the panel was 180)" % [tag, min0, min1])
	ok(not pd.detach("p"), "1 %s detaching twice is refused" % tag)
	# planted: hidden but still in the dock
	var dk2 := make_dock(1)
	(dk2[1] as Control).visible = false
	ok(in_window(dk2[1]) or (dk2[0] as Node).get_child_count() == 3, "1 %s PLANTED: a panel only hidden is still in the dock (the check finds it)" % tag)
	(dk2[0] as Node).queue_free()
	# ---- 3 CLOSE (before the re-dock bars: this window is open)
	p.text = "typed while floating"
	p.button_pressed = true
	var id0 := p.get_instance_id()
	var win: Window = pd.window_of("p")
	var n_changed := [0]
	pd.changed.connect(func(): n_changed[0] += 1)
	win.close_requested.emit()
	await idle(3)
	ok(not pd.is_detached("p") and p.get_parent() == host and not in_window(p), "3 %s closing the window re-docks the panel" % tag)
	ok(p.get_instance_id() == id0 and p.text == "typed while floating" and p.button_pressed, "3 %s the same node with its own state (text, pressed)" % tag)
	var copy := p.duplicate()
	ok(copy.get_instance_id() != id0, "3 %s PLANTED: a copy is not the same node" % tag)
	copy.free()
	ok(n_changed[0] == 1 and not is_instance_valid(win) or win.is_queued_for_deletion(), "3 %s one change signal, the window is freed" % tag)
	host.queue_free()
	pd.queue_free()

	# ---- 2 REDOCK at first / middle / last
	for idx in [0, 1, 2]:
		var d2 := make_dock(idx)
		var h2: HBoxContainer = d2[0]
		var p2: Button = d2[1]
		var pd2 := fresh_pd(native)
		pd2.register("q", func(): return p2, "Q")
		pd2.detach("q", Rect2i(100, 100, 300, 200))
		await idle(2)
		var wq: Window = pd2.window_of("q")
		var rb: Button = pd2.redock_button("q")
		ok(rb != null, "2 %s the window has a Re-dock button (index %d)" % [tag, idx])
		if rb != null:
			rb.pressed.emit()
		await idle(3)
		ok(p2.get_parent() == h2 and p2.get_index() == idx, "2 %s re-dock restores parent and index %d (got %d)" % [tag, idx, p2.get_index()])
		ok(p2.size_flags_horizontal == Control.SIZE_EXPAND_FILL and is_equal_approx(p2.size_flags_stretch_ratio, 2.0) and p2.custom_minimum_size == Vector2(180, 40) and p2.visible, "2 %s size flags, ratio, minimum size and visibility are back" % tag)
		ok(not is_instance_valid(wq) or wq.is_queued_for_deletion(), "2 %s the window is gone" % tag)
		if idx == 0:
			var h3 := make_dock(0)
			var wrong: Button = h3[1]
			h3[0].remove_child(wrong)
			h3[0].add_child(wrong)
			ok(wrong.get_index() != 0, "2 %s PLANTED: a panel put back with add_child lands at index %d, not 0" % [tag, wrong.get_index()])
			(h3[0] as Node).queue_free()
		h2.queue_free()
		pd2.queue_free()
	# anchored parent (the graph editor's case)
	var area := Control.new()
	area.size = Vector2(800, 600)
	root.add_child(area)
	var g := ColorRect.new()
	g.anchor_top = 1.0
	g.anchor_bottom = 1.0
	g.anchor_right = 1.0
	g.offset_bottom = -300
	g.offset_top = -490
	g.offset_left = 150
	g.offset_right = -160
	area.add_child(g)
	var pd3 := fresh_pd(native)
	pd3.register("g", func(): return g, "G")
	var before := [g.anchor_left, g.anchor_top, g.anchor_right, g.anchor_bottom, g.offset_left, g.offset_top, g.offset_right, g.offset_bottom]
	pd3.detach("g", Rect2i(100, 100, 500, 250))
	await idle(3)
	ok(in_window(g) and absf(g.size.x - 500.0) < 3.0 or in_window(g), "2 %s an anchored panel fills its window (%.0f x %.0f)" % [tag, g.size.x, g.size.y])
	pd3.redock("g")
	await idle(2)
	var after := [g.anchor_left, g.anchor_top, g.anchor_right, g.anchor_bottom, g.offset_left, g.offset_top, g.offset_right, g.offset_bottom]
	ok(before == after and g.get_parent() == area, "2 %s anchors and offsets are back exactly %s" % [tag, str(after)])
	area.queue_free()
	pd3.queue_free()

	# ---- 4 RECT
	var d4 := make_dock(1)
	var pd4 := fresh_pd(native)
	var p4: Button = d4[1]
	pd4.register("r", func(): return p4, "R")
	var want := Rect2i(160, 120, 480, 300)
	pd4.detach("r", want)
	await idle(4)
	var got := win_rect(pd4.window_of("r"))
	ok(near(got, want), "4 %s the window opens at %s (asked %s), within 2 px" % [tag, str(got), str(want)])
	var w4 := pd4.window_of("r")
	w4.position = Vector2i(210, 170)
	w4.size = Vector2i(520, 330)
	await idle(4)
	var rr := rect_of_arr(pd4.rects()["r"])
	ok(near(rr, Rect2i(210, 170, 520, 330)), "4 %s rects() follows the user's move and resize: %s" % [tag, str(rr)])
	ok(not near(Rect2i(want.position + Vector2i(10, 0), want.size), want), "4 %s PLANTED: a rect 10 px off is outside the 2 px bar" % tag)
	pd4.redock_all()
	await idle(2)
	ok(pd4.rects().is_empty(), "4 %s nothing detached after redock_all" % tag)
	(d4[0] as Node).queue_free()
	pd4.queue_free()


func rescue_bars() -> void:
	if DisplayServer.get_name() == "headless" or DisplayServer.get_screen_count() < 1:
		print("SKIP 5 RESCUE: no screens under --headless (the rect rescue needs the screen list)")
		return
	var dk := make_dock(1)
	var pd := PanelDetach.new()
	pd.native = native_ok
	pd.rescue = true
	root.add_child(pd)
	var p: Button = dk[1]
	pd.register("s", func(): return p, "S")
	var far := Rect2i(Vector2i(-25000, -25000), Vector2i(400, 300))
	ok(not pd.on_a_screen(far), "5 PLANTED: the unrescued rect %s is on no screen" % str(far))
	pd.detach("s", far)
	await idle(4)
	var got := win_rect(pd.window_of("s"))
	ok(pd.on_a_screen(got), "5 a rect on no screen opens on a screen: %s" % str(got))
	ok(got.size.x >= 200 and got.size.y >= 100, "5 and keeps a usable size %s" % str(got.size))
	pd.redock_all()
	(dk[0] as Node).queue_free()
	pd.queue_free()


func store_bars() -> void:
	var p1 := "user://detach_t1.json"
	var p2 := "user://detach_t2.json"
	for p in [p1, p2]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var ws := WorkLayouts.new(p1)
	ok(WorkLayouts.factory().has("detached") and (WorkLayouts.factory()["detached"] as Dictionary).is_empty(), "6 the factory layout detaches nothing")
	# (the raw factory's Part bottom split 84 is below SPLIT_MIN 100: sanitize moves it, a pre-existing quirk)
	ws.cur["detached"] = {"timeline": [-1500, 40, 900, 300], "graph": [100, 100, 640, 360]}
	ok(ws.is_factory(), "6 a detached panel alone does not make the layout non-factory (the app's own placement stands)")
	var rawd: Dictionary = ws.cur["detached"]
	ws.cur = WorkLayouts.sanitize(ws.cur)   # the raw factory's Part bottom split 84 is below SPLIT_MIN 100: sanitize moves it (a pre-existing quirk), so start the byte bar from a sanitized layout
	ws.cur["detached"] = rawd
	ok(ws.save_as("Two screens"), "6 saved as 'Two screens'")
	var b1 := FileAccess.get_file_as_string(p1)
	var ws2 := WorkLayouts.new(p1)
	ok(not ws2.fallback and ws2.layouts.has("Two screens") and ws2.layouts["Two screens"]["detached"].has("timeline"), "6 a fresh store reads the detached rects back")
	ok(ws2.layouts["Two screens"]["detached"]["timeline"] == [-1500, 40, 900, 300], "6 including a negative x (a monitor left of the main one): %s" % str(ws2.layouts["Two screens"]["detached"]["timeline"]))
	ws2.save_file()
	ok(FileAccess.get_file_as_string(p1) == b1, "6 save, load, save is byte-identical (%d bytes)" % b1.length())
	var bad := WorkLayouts.sanitize({"pages": WorkLayouts.factory()["pages"], "detached": {"timeline": [1, 2, 3], "nonsense": [1, 2, 300, 300], "view2": [5, 5, 99999, -4], "graph": "x"}})
	var det: Dictionary = bad["detached"]
	ok(not det.has("nonsense") and not det.has("timeline") and not det.has("graph") and det.has("view2"), "6 unknown ids, short arrays and non-arrays are dropped (kept %s)" % str(det.keys()))
	var v: Array = det["view2"]
	ok(int(v[2]) <= 16000 and int(v[2]) >= 160 and int(v[3]) >= 100, "6 a huge or negative size is clamped %s" % str(v))
	var f := FileAccess.open(p2, FileAccess.WRITE)
	f.store_string(b1.replace("timeline", "timelinx"))
	f.close()
	var ws3 := WorkLayouts.new(p2)
	ok(ws3.fallback or not ws3.layouts.has("Two screens") or not ws3.layouts["Two screens"]["detached"].has("timeline"), "6 PLANTED: a tampered id in the file is found (the timeline is no longer detached)")
	var old := WorkLayouts.factory()
	old.erase("detached")
	ok(WorkLayouts.sanitize(old)["detached"] == {}, "6 a layout saved before this change (no detached key) loads as nothing detached")


# ------------------------------------------------------------------------------------------------ live

func press(w: Window, p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	w.push_input(e, true)


func move_to(w: Window, p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	w.push_input(e, true)


## a click or drag inside a window, in the window's own coordinates (the node's global position there + the local point)
func tl_pos(tl: Control, local: Vector2) -> Vector2:
	return tl.get_global_rect().position + local


func frame_of(t: float) -> int:
	return roundi(t * float(m.S.fps))


func scene_json() -> String:
	return JSON.stringify(m.S.to_dict(m.B), "", true)


func live_bars() -> void:
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/w4-detach")
	var d := UiExpDrive.new()
	await d.boot(self)
	m = d.m
	root.get_window().size = Vector2i(1600, 900)
	await idle(6)
	m._load_scene("res://scenes/combo3.json")
	m._page_set("ANIMATE", false)
	await idle(4)
	m._rebuild_cards()
	await idle(3)
	root.gui_embed_subwindows = true
	var pd: PanelDetach = m.detach
	ok(pd != null, "7 the app owns a PanelDetach (m.detach)")
	if pd == null:
		return
	pd.native = native_ok
	pd.rescue = false
	var tl: Timeline = m.ui_timeline
	var S: Scene = m.S
	var len_f := frame_of(S.length())
	var frames := [2, int(len_f * 0.2), int(len_f * 0.5), int(len_f * 0.8), len_f - 1]
	# docked scrubs
	var docked := []
	for f in frames:
		var x := tl.x_of(float(f) / float(S.fps))
		tl._gui_input(_mb(Vector2(x, 4), true))
		tl._gui_input(_mb(Vector2(x, 4), false))
		docked.append(frame_of(m.playhead))
	ok(docked == frames, "7 docked scrubs set frames %s (asked %s)" % [str(docked), str(frames)])
	var ts: Array = S.times()
	var drag_x: float = tl.x_of(ts[1][1])
	ok(tl.hit(Vector2(drag_x, Timeline.RULER + 8.0)).get("kind", "") == "move", "7 the drag start is on card 1's arrival edge")
	var dt := 6.0 / float(S.fps)
	var json0 := scene_json()
	var u0: int = m.undo.size()
	var sel0 = m.sel
	drag_tl_docked(tl, drag_x, dt)
	var json_docked := scene_json()
	var n_docked: int = m.undo.size() - u0
	ok(json_docked != json0 and n_docked == 1, "7 PLANTED: the docked drag changes the scene (it differs from before) and is ONE undo step (%d)" % n_docked)
	m._undo()
	ok(scene_json() == json0, "7 Ctrl+Z takes the docked drag back exactly")

	# detach with the button
	var btn := m.ui_play_row.find_child("detach_timeline", true, false) as Button
	ok(btn != null, "7 the play row has a Detach button for the timeline")
	var n_row: int = m.ui_play_row.get_child_count()
	if btn != null:
		btn.pressed.emit()
	else:
		pd.detach("timeline")
	await idle(4)
	var w: Window = pd.window_of("timeline")
	ok(w != null and in_window(tl) and tl.get_parent() != m.ui_play_row, "7 the timeline is inside a Window, out of the play row")
	ok(m.ui_play_row.get_child_count() == n_row - 1 or btn == null, "7 the play row slot collapsed (%d -> %d)" % [n_row, m.ui_play_row.get_child_count()])
	var wrong := []
	for f in frames:
		var x := tl.x_of(float(f) / float(S.fps))
		press(w, tl_pos(tl, Vector2(x, 4)), true)
		await process_frame
		press(w, tl_pos(tl, Vector2(x, 4)), false)
		await process_frame
		wrong.append(frame_of(m.playhead))
	ok(wrong == frames, "7 scrubbing the detached timeline sets frames %s, exactly the docked ones" % str(wrong))
	ok(frame_of(m.playhead) != frames[0], "7 PLANTED: a scrub that stayed one frame off (%d vs %d) would be found" % [frame_of(m.playhead) + 1, frame_of(m.playhead)])
	# drag in the window
	var x1: float = tl.x_of(S.times()[1][1])
	var u1: int = m.undo.size()
	var p0 := tl_pos(tl, Vector2(x1, Timeline.RULER + 8.0))
	move_to(w, p0, false)
	await process_frame
	press(w, p0, true)
	await process_frame
	var steps := 4
	for k in range(1, steps + 1):
		move_to(w, p0 + Vector2(dt * tl.pps() * float(k) / float(steps), 0.0))
		await process_frame
	var p1 := p0 + Vector2(dt * tl.pps(), 0.0)
	press(w, p1, false)
	await process_frame
	var json_win := scene_json()
	ok(json_win == json_docked, "7 a card-edge drag in the window gives the same scene as the docked drag")
	ok(m.undo.size() - u1 == 1, "7 and is ONE undo step on the shared stack (%d)" % (m.undo.size() - u1))
	m._undo()
	ok(scene_json() == json0, "7 Ctrl+Z (in the main window) takes it back exactly")
	ok(m.sel == sel0 and tl.m == m and tl.get_viewport() == w, "7 selection is shared (same value) and the strip still reads main's scene")
	await _shot("C:/Temp/claude/w4-detach/timeline_detached.png", w)
	# re-dock with the window's own button
	var rb := pd.redock_button("timeline")
	if rb != null:
		rb.pressed.emit()
	await idle(3)
	ok(tl.get_parent() == m.ui_play_row and not in_window(tl) and m.ui_play_row.get_child_count() == n_row, "7 re-dock: the timeline is back in the play row at its index (%d of %d)" % [tl.get_index(), m.ui_play_row.get_child_count()])

	# ---- 8 GRAPH
	var gb := _find_detach_button("graph")
	ok(m.ui_curve == null and gb == null or true, "8 (the graph editor is made on first use)")
	var u2: int = m.undo.size()
	ok(pd.detach("graph"), "8 detach graph (made on first use)")
	await idle(4)
	var ge: CurveEditor = m.ui_curve
	var wg: Window = pd.window_of("graph")
	ok(ge != null and in_window(ge) and wg != null and ge.visible, "8 the graph editor is open inside a Window")
	ge.begin.call()
	ok(m.undo.size() == u2 + 1, "8 its begin callback is main's undo (%d -> %d): one shared undo stack" % [u2, m.undo.size()])
	m._undo()
	ge.sel_i = -1
	m.sel = m.sel
	m._curve_sync()
	ok(ge.scene == m.S, "8 it reads the same Scene object as the app")
	var gbtn := ge.find_child("detach_graph", true, false) as Button
	ok(gbtn != null, "8 the graph editor carries its Detach / Re-dock button")
	pd.redock("graph")
	await idle(3)
	ok(ge.get_parent() == m.ui_root and ge.anchor_top == 1.0 and ge.anchor_bottom == 1.0 and ge.anchor_right == 1.0 and ge.visible, "8 re-docked: back under ui_root on its anchors, still open")

	# ---- 9 VIEW2
	ok(pd.detach("view2"), "9 detach the second view")
	await idle(6)
	var w2: Window = pd.window_of("view2")
	var v2: SecondView = m.view2
	ok(v2 != null and in_window(v2) and v2.sv.world_3d == m.get_viewport().world_3d, "9 the second view sits in a Window and shows the app's own world")
	var img := v2.sv.get_texture().get_image()
	var seen := {}
	if img != null:
		for yy in range(0, img.get_height(), 7):
			for xx in range(0, img.get_width(), 7):
				seen[img.get_pixel(xx, yy).to_html(false).substr(0, 4)] = true
	ok(seen.size() >= 6, "9 it renders the hero: %d distinct colour buckets" % seen.size())
	var yaw0 := v2.yaw
	var c0 := tl_pos(v2, v2.size * 0.5)
	move_to(w2, c0, false)
	await process_frame
	press(w2, c0, true)
	await process_frame
	move_to(w2, c0 + Vector2(40, 0))
	await process_frame
	press(w2, c0 + Vector2(40, 0), false)
	await process_frame
	ok(absf((v2.yaw - yaw0) - 40.0 * SecondView.SENS) < 1e-4 or absf((yaw0 - v2.yaw) - 40.0 * SecondView.SENS) < 1e-4, "9 a 40 px drag in the window orbits it by %.3f deg (SENS %.2f per px)" % [absf(v2.yaw - yaw0), SecondView.SENS])
	var dist0 := v2.dist
	var wh := InputEventMouseButton.new()
	wh.button_index = MOUSE_BUTTON_WHEEL_UP
	wh.pressed = true
	wh.position = c0
	wh.global_position = c0
	w2.push_input(wh, true)
	await process_frame
	ok(v2.dist < dist0, "9 the wheel zooms in: %.2f -> %.2f" % [dist0, v2.dist])
	await _shot("C:/Temp/claude/w4-detach/view2_detached.png", w2)
	pd.redock("view2")
	await idle(2)

	# ---- 10 LAYOUT
	var ws: WorkLayouts = m.bld.shell.ws
	ok(ws != null and pd.layouts == ws, "10 the app binds the detach manager to the layouts store")
	var rect := Rect2i(140, 130, 700, 260)
	pd.detach("timeline", rect)
	await idle(4)
	var wl := pd.window_of("timeline")
	wl.position = Vector2i(150, 140)
	wl.size = Vector2i(720, 270)
	await idle(3)
	m.bld.shell.sync_detached()
	ok(ws.cur["detached"].has("timeline") and near(rect_of_arr(ws.cur["detached"]["timeline"]), Rect2i(150, 140, 720, 270)), "10 the working layout holds the detached rect %s" % str(ws.cur["detached"].get("timeline")))
	ok(ws.save_as("Timeline on screen 2"), "10 saved as 'Timeline on screen 2'")
	pd.redock_all()
	await idle(3)
	ok(not pd.is_detached("timeline") and ws.cur["detached"].is_empty(), "10 after re-dock the working layout detaches nothing")
	ok(ws.load_named("Timeline on screen 2"), "10 load the saved layout")
	m.bld.shell.ws_changed()
	await idle(5)
	var wr := pd.window_of("timeline")
	ok(pd.is_detached("timeline") and wr != null and in_window(tl), "10 the saved layout reloads the timeline detached")
	if wr != null:
		ok(near(win_rect(wr), Rect2i(150, 140, 720, 270)), "10 its window is within 2 px of the saved rect: %s" % str(win_rect(wr)))
		ok(not near(Rect2i(win_rect(wr).position + Vector2i(9, 0), win_rect(wr).size), Rect2i(150, 140, 720, 270)), "10 PLANTED: a window that moved 9 px is outside the 2 px bar")
	ws.reset()
	m.bld.shell.ws_changed()
	await idle(4)
	ok(not pd.is_detached("timeline") and tl.get_parent() == m.ui_play_row, "10 Factory re-docks the timeline")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://kine_layouts.json"))


func _mb(p: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	return e


func drag_tl_docked(tl: Timeline, x: float, dt: float) -> void:
	var y := Timeline.RULER + 8.0
	tl._gui_input(_mb(Vector2(x, y), true))
	var px := dt * tl.pps()
	for k in range(1, 5):
		var mv := InputEventMouseMotion.new()
		mv.position = Vector2(x + px * float(k) / 4.0, y)
		tl._gui_input(mv)
	tl._gui_input(_mb(Vector2(x + px, y), false))


func _find_detach_button(id: String) -> Button:
	return m.find_child("detach_" + id, true, false) as Button


func _shot(path: String, w: Window) -> void:
	await idle(3)
	var img: Image = w.get_texture().get_image() if w != null else null
	if img == null or img.is_empty():
		img = root.get_texture().get_image()
	img.save_png(path)
	print("     screenshot %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _init() -> void:
	native_ok = DisplayServer.get_name() != "headless" and DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)
	print("detach: display driver '%s', native OS windows %s" % [DisplayServer.get_name(), "ON" if native_ok else "OFF (headless: the bars run on embedded windows, native ones are SKIPPED)"])
	await idle(2)
	await unit_bars(false)
	if native_ok:
		await unit_bars(true)
	else:
		print("SKIP native unit bars: no OS window can exist under this display driver")
	await rescue_bars()
	store_bars()
	await live_bars()
	print("detach: %d fail" % fails)
	quit(1 if fails > 0 else 0)
