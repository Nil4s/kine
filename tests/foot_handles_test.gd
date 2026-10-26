## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/foot_handles_test.gd     (ROADMAP 6; a window: real mouse events)
## REVERSE-FOOT HANDLES (scripts/foot_handles.gd, main.gd _frh_*): a picked foot shows three handles, the heel (sole under the
## ankle), the ball (toe joint) and the toe tip; a press on one and a drag up rolls the foot about that point. Release keys.
## Bars, written before measuring:
##   1 the three handles on the picked foot: a press on each handle's projected point takes that handle (3 of 3)
##   2 a drag on each handle (10 mouse steps, 60 px up): the pivot stays within 1 mm of its start place at EVERY step
##   3 the right way: heel drag = toe tip rises, heel fixed; ball drag = heel rises, ball joint fixed; tip drag = heel rises,
##     tip fixed (the rise is > 1 cm and the fixed point moves < 1 mm)
##   4 one undo step per drag; Ctrl+Z puts the body and the keys back bit for bit
##   5 release keys the leg and the toe joint at the playhead: the keys hold the posed angles (within 1e-4)
##   6 a press on a handle with no move leaves no undo step
## FOOTH_SHOT=<path.png>: a picture of the foot with its three handles is saved there (before the drags)
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


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


## a real drag of the handle at p, `up` px up, in 10 steps. Returns the largest pivot error (m) over the steps, and the steps
func drag_up(p: Vector2, up: float, kind: String, pv0: Vector3) -> Dictionary:
	var worst := 0.0
	var steps := 0
	await mouse(p, true)
	for k in 10:
		var q := p + Vector2(0, -up * float(k + 1) / 10.0)
		await move(q, Vector2(0, -up / 10.0))
		if m._frh_drag.is_empty():
			continue
		steps += 1
		worst = maxf(worst, (FootHandles.pivot(m.B, "_l", kind) - pv0).length())
	await mouse(p + Vector2(0, -up), false)
	await idle(2)
	return {"worst": worst, "steps": steps}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playing = false
	m.playhead = float(m.S.times()[1][1])
	m._ps().apply(m.B, m.playhead)
	m.sel = "foot_l"
	m.hover_part = ""
	m._refresh()
	var tg: Vector3 = (m.B.P["ball_l"] + m.B.P["foot_l"]) * 0.5
	m._turn_to(20.0, -12.0, 1.3, tg, false)
	await idle(4)

	var shot := OS.get_environment("FOOTH_SHOT")
	if shot != "":
		m._turn_to(20.0, -12.0, 0.75, tg, false)   # closer, for the picture
		await idle(3)
		DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
		await idle(2)
		root.get_texture().get_image().save_png(shot)
		print("saved %s" % shot)

	# ---- 1 the three handles, each under its own point
	var pts := FootHandles.points(m.B, "_l")
	var pxs := {}
	var hit_ok := 0
	for k in FootHandles.KINDS:
		var px: Vector2 = m.cam.unproject_position(pts[k])
		pxs[k] = px
		if FootHandles.hit(m.cam, px, m.B, "_l") == k:
			hit_ok += 1
	ok(hit_ok == 3 and m._frh_active() == "_l", "1 the three handles on the picked foot: a press on each point takes that handle (%d of 3)" % hit_ok)

	# ---- 2-5 each handle: a real drag, then Ctrl+Z
	var worst_all := 0.0
	for kind in FootHandles.KINDS:
		var before: Dictionary = m.B.state()
		var keys0: Dictionary = m.S.part_keys.duplicate(true)
		var u0: int = m.undo.size()
		var pv0 := FootHandles.pivot(m.B, "_l", kind)
		var snap := FootHandles.snapshot(m.B)
		var dbg := FootHandles.drag(m.B, "_l", kind, snap, 60.0)   # the roll 60 px asks for, and what the leg reaches
		FootHandles.restore(m.B, snap)
		var reach_s := "asked %.1f deg, reached %.1f deg%s (ankle %.1f, toe %.1f)" % [float(dbg["asked"]), float(dbg["roll"]), " (stopped: the leg cannot turn it further)" if dbg["stopped"] else "", float(dbg["ankle"]) if dbg.has("ankle") else 0.0, float(dbg["toe"]) if dbg.has("toe") else 0.0]
		var h0 := FootRoll.heel_point(m.B, "_l")
		var e0: Vector3 = m.B.E["ball_l"]
		var b0: Vector3 = m.B.P["ball_l"]
		var rec := await drag_up(pxs[kind], 60.0, kind, pv0)
		var h1 := FootRoll.heel_point(m.B, "_l")
		var e1: Vector3 = m.B.E["ball_l"]
		var b1: Vector3 = m.B.P["ball_l"]
		var err := (FootHandles.pivot(m.B, "_l", kind) - pv0).length()
		worst_all = maxf(worst_all, float(rec["worst"]))
		var rise := 0.0
		var fixed := 0.0
		var named := ""
		match kind:
			"heel":
				rise = e1.y - e0.y
				fixed = (h1 - h0).length()
				named = "toe tip rises, heel fixed"
			"ball":
				rise = h1.y - h0.y
				fixed = (b1 - b0).length()
				named = "heel rises, ball joint fixed"
			_:
				rise = h1.y - h0.y
				fixed = (e1 - e0).length()
				named = "heel rises, toe tip fixed"
		var right := rise > 0.01 and fixed < 0.001
		print("%s: %d steps, pivot error worst %.4f mm, end %.4f mm; rise %.1f cm (%s); %s" % [kind, rec["steps"], float(rec["worst"]) * 1000.0, err * 1000.0, rise * 100.0, named, reach_s])
		ok(int(rec["steps"]) == 10 and float(rec["worst"]) <= 0.001 and err <= 0.001, "2 %s drag: the pivot within 1 mm at every step (worst %.4f mm)" % [kind, float(rec["worst"]) * 1000.0])
		ok(right, "3 %s drag rolls the right way: %s (rise %.1f cm, fixed point moved %.2f mm)" % [kind, named, rise * 100.0, fixed * 1000.0])
		ok(m.undo.size() == u0 + 1, "4 %s drag: one undo step (%d added)" % [kind, m.undo.size() - u0])
		var t: float = m.playhead
		var keyed := true
		for j in FootHandles.keys_of(m.B, "_l"):
			var v: Vector3 = PartKeys.at(m.S.part_keys.get(j, []), t)
			if (v - (m.B.ang[j] as Vector3)).length() > 1e-4:
				keyed = false
		ok(keyed, "5 %s drag keyed: the leg and the toe joint hold their angles at %.2f s" % [kind, t])
		m._undo()
		await idle(2)
		var back: bool = m.B.state() == before and m.S.part_keys == keys0
		ok(back, "4b %s: Ctrl+Z puts the body and the keys back bit for bit" % kind)

	ok(worst_all <= 0.001, "2b the largest pivot error over the three drags %.4f mm" % (worst_all * 1000.0))

	# ---- 6 a press with no move: no undo step
	var u6: int = m.undo.size()
	await mouse(pxs["ball"], true)
	await mouse(pxs["ball"], false)
	await idle(2)
	ok(m.undo.size() == u6, "6 a press on a handle with no move left no undo step (%d -> %d)" % [u6, m.undo.size()])

	print("FOOT HANDLES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
