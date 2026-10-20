## godot --path . -s tests/i1_test.gd   (window)  I1 "Make it physical" (scripts/make_physical*.gd, tools/physics/judge.py).
## Bars (written before measuring):
##  1 walk_bat (a calm walk) is <= 5 % red (judged by plain `python`, blocking, once)
##  2 an impossible jump (the body lifted 0.4 m for 1 s with the legs unchanged = a hover) is judged in the background through the app's
##    own command (OS.create_process + progress file): a red span with a reason that says "airborne", >= 0.6 s long, the worst frame
##    while it judges < 50 ms
##  3 the timeline lane carries the red block; its tooltip is the reason
##  4 the ghost (physical version) does NOT hover: at mid-span its pelvis is >= 0.15 m under the clip's; PLACEMENT: the ghost's head
##    projects inside the 3D view, above its feet
##  5 Accept span: cards outside the span are byte-identical, the cards inside are replaced (count changes to the card density), the
##    scene's length is kept (+-0.05 s), ONE undo step, and the undo restores the cards exactly
## Shot: C:/Users/Nick/.claude/jobs/9afc22db/tmp/i1.png
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


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	# 1. the calm walk, judged once by plain python
	var W := Scene.new()
	W.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var mw := MakePhysical.new()
	var keep: Dictionary = m.B.state()
	var clip := mw.clip_dict(W, m.B)
	m.B.set_state(keep)
	DirAccess.make_dir_recursive_absolute("user://make_physical")
	var cp := ProjectSettings.globalize_path("user://make_physical/walk_clip.json")
	var op := ProjectSettings.globalize_path("user://make_physical/walk_out.json")
	var f := FileAccess.open(cp, FileAccess.WRITE)
	f.store_string(JSON.stringify(clip))
	f.close()
	var out := []
	var code := OS.execute("python", [ProjectSettings.globalize_path("res://tools/physics/judge.py"), cp, op], out, true)
	print(String(out[0]).left(400) if out.size() > 0 else "no output")
	ok(code == 0 and mw.load_result(op), "0 python judged the walk (exit %d)" % code)
	ok(mw.red_pct() <= 5.0, "1 walk_bat is %.1f %% red (bar <= 5), spans %d, authored-slide notes %d" % [mw.red_pct(), mw.spans.size(), mw.notes.size()])
	# 2. the impossible jump through the app's command
	var B: Body = m.B
	var rest := B.to_dict()
	B.offset = Vector3(0, 0.4, 0)
	B.fk()
	var up := B.to_dict()
	B.offset = Vector3.ZERO
	B.fk()
	m.S.from_dict({"scene": "zz_hover", "fps": 30, "cards": [{"name": "stand", "pose": rest, "move": -1.0, "hold": 0.5},
		{"name": "up", "pose": up, "move": 0.1, "hold": 1.0}, {"name": "down", "pose": rest, "move": 0.1, "hold": 0.1}]})
	m._rebuild_cards()
	m._refresh()
	await idle(3)
	var ui: MakePhysicalUI = m.mp_ui
	ok(ui != null, "2a the app has the Make it physical command object")
	# the app grounds the body, so a hover cannot be authored in cards: the test lifts the sampled clip 0.4 m between 0.5 and 1.6 s
	ui.mp.tweak = func(frames: Array, offs: Array) -> void:
		for i in frames.size():
			var t: float = frames[i]["t"]
			var lift := 0.4 * clampf(minf((t - 0.5) / 0.1, (1.7 - t) / 0.1), 0.0, 1.0)
			frames[i]["pelvis"][1] += lift
			offs[i][0].y += lift
			offs[i][1].y += lift
	ui.run()
	ok(ui.mp.pid >= 0, "2b a child python process started (pid %d), the window is not blocked" % ui.mp.pid)
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	while not ui.mp.done and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
		var now := Time.get_ticks_usec()
		if not ui.mp.done:   # (the frame the result lands in loads nothing now, but is not 'while judging')
			worst = maxf(worst, float(now - last) / 1000.0)
		last = now
	await idle(3)
	ok(ui.mp.done and ui.mp.failed == "", "2c the judge finished in %.0f s (%s)" % [float(Time.get_ticks_msec() - t0) / 1000.0, ui.mp.failed])
	ok(worst < 50.0, "2d worst frame while judging %.1f ms (bar < 50)" % worst)
	var air := ui.mp.spans.filter(func(s): return s["kind"] == "airborne")
	ok(air.size() >= 1 and "airborne" in String(air[0]["reason"]) and float(air[0]["t1"]) - float(air[0]["t0"]) >= 0.6,
		"2e a red airborne span with a reason: %s" % (str(air[0]["t0"]).left(5) + "-" + str(air[0]["t1"]).left(5) + " " + String(air[0]["reason"]).left(90) if air.size() > 0 else "none: %s" % [ui.mp.spans]))
	# 3. the lane
	var tl: Timeline = m.ui_timeline
	ok(tl.ph.size() >= 1 and tl.ph_px() > 0.0, "3a the timeline lane has %d block(s)" % tl.ph.size())
	var tipx := tl.x_of((float(air[0]["t0"]) + float(air[0]["t1"])) * 0.5) if air.size() > 0 else 0.0
	var tip := tl._get_tooltip(Vector2(tipx, tl._ph_y() + 3.0))
	ok("airborne" in tip, "3b the tooltip on the block is the reason: %s" % tip.left(80))
	# 4. the ghost
	var mid := (float(air[0]["t0"]) + float(air[0]["t1"])) * 0.5 if air.size() > 0 else 1.0
	m.playhead = mid
	m._ps().apply(m.B, mid)
	m._refresh()
	await idle(4)
	ui.tick(0.016)
	var k := int(round(mid * ui.mp.fps))
	var clip_y: float = ui.mp.offs[k][0].y
	ui.mp.ghost_pose(ui.gbody, mid)
	var ph_y: float = ui.gbody.offset.y
	ok(ui.ghost != null and ui.ghost.visible, "4a the ghost body is on")
	ok(ph_y <= clip_y - 0.15, "4b the physical pelvis is %.2f m above rest, the clip's %.2f m (bar: >= 0.15 m lower: it does not hover)" % [ph_y, clip_y])
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var vr := root.get_visible_rect()
	var gh: Vector3 = ui.gskel.to_global(ui.gskel.get_bone_global_pose(ui.gidx["head"]).origin)
	var gf: Vector3 = ui.gskel.to_global(ui.gskel.get_bone_global_pose(ui.gidx["foot_l"]).origin)
	var ph := cam.unproject_position(gh)
	var pf := cam.unproject_position(gf)
	ok(vr.has_point(ph) and ph.y < pf.y, "4c PLACEMENT: ghost head at %s is in the view and above its foot %s" % [ph, pf])
	await idle(3)
	root.get_viewport().get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i1.png")
	# 5. accept
	var before: Array = m.S.cards.duplicate(true)
	var len0: float = m.S.length()
	var ts0: Array = m.S.times()
	var sp: Dictionary = ui.mp.spans[ui.mp.spans.find(air[0])]
	var inside := MakePhysical.cards_in(m.S, sp)
	var nundo: int = m.undo.size()
	ui.pick(ui.mp.spans.find(air[0]))
	ui.accept()
	var after: Array = m.S.cards
	var outside_same := true
	var ia := 0
	for i in before.size():
		if i in inside:
			continue
		var j := i if i < (inside[0] if inside.size() > 0 else 99) else i - inside.size() + (after.size() - before.size() + inside.size())
		if j >= after.size() or var_to_str(after[j]) != var_to_str(before[i]):
			outside_same = false
	ok(inside.size() >= 1, "5a %d card(s) lie inside the span" % inside.size())
	ok(outside_same, "5b the cards outside the span are identical")
	ok(after.size() != before.size() or var_to_str(after) != var_to_str(before), "5c the span's cards were replaced: %d cards -> %d" % [before.size(), after.size()])
	ok(absf(m.S.length() - len0) <= 0.05, "5d the length is kept: %.3f -> %.3f s" % [len0, m.S.length()])
	ok(m.undo.size() == nundo + 1, "5e one undo step (%d -> %d)" % [nundo, m.undo.size()])
	m._undo()
	await idle(2)
	ok(var_to_str(m.S.cards) == var_to_str(before), "5f the undo restores the cards exactly")
	ok(m.undo.size() == nundo, "5g and the step is gone (%d)" % m.undo.size())
	print("FAILS %d" % fails)
	quit(1 if fails > 0 else 0)
