## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i27_test.gd     (ROADMAP I27; a window)
## THROW AND CATCH (scripts/throw_catch.gd, throw_catch_ui.gd, the command "Throw to..."). Bars, written before measuring:
##   1 RELEASE: the plan's release velocity is the finite difference over ONE frame of the held prop (same number from props_at);
##     it points up and is within 0.6 m/s of the right wrist's own one-frame velocity (the grip is a few cm off the wrist).
##   2 ARC: a toss with a KNOWN release velocity (opts v): every key is on p0 + v t - g t^2 / 2 within 1 mm, at every frame, and the
##     prop's own curve (Props.posed) reproduces each key within 1 mm.
##   3 FLIGHT TIME: the catch frame's time matches the analytic time at the catch height, (vy + sqrt(vy^2 - 2 g dy)) / g, within 1 frame;
##     the SAME-HEIGHT return (a red plan's keys run to the floor) comes at 2 vy / g within 1 frame.
##   4 CATCH: with the plan written (a clone), the catching hand's wrist is within 1 cm of the prop at the catch frame; the prop
##     rests in that hand afterwards (stays within 1 mm of its catch place); before the release it is still in the right hand.
##   5 RED: an over-the-head toss far away -> why starts 'out of reach'; a 16 m/s toss through the reach -> 'too fast'; the red plan
##     writes nothing (Accept disabled).
##   6 UNDO: Preview and 20 ticks leave the scene JSON unchanged; Accept = ONE undo step; Ctrl+Z restores the JSON exactly; the JSON is untouched until Accept.
##   7 PLACEMENT: in the whole-body view the arc, its tick marks and the catch ring are drawn in the window, the ring on the catching hand
##     (within 40 px of the hand's screen place); the picture is saved.
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i27.png"
const FPS := 30


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func pose_of(arm: float) -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.set_ang("upperarm_r", Vector3(0, arm, 0))   # about the side axis: -70 hangs at the hip, +70 overhead
	b.ground()
	return b.to_dict()


func js(s: Scene) -> String:
	var d := s.to_dict(body())
	return JSON.stringify(d) + var_to_str(s.ik)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var s := Scene.new()
	s.from_dict({"scene": "zz_i27", "fps": FPS, "cards": [
		{"name": "a", "pose": pose_of(-70), "move": -1.0, "hold": 0.3},
		{"name": "b", "pose": pose_of(70), "move": 1.0, "hold": 1.5},
		{"name": "c", "pose": pose_of(-70), "move": 0.6, "hold": 1.0}]})
	m.S = s
	m._rebuild_cards()
	var B: Body = m.B
	s.apply(B, 0.3)
	var hand: Vector3 = B.P["hand_r"]
	# a table beside the hand, the ball on it (a prop rests on the floor or a top: it cannot float in the air)
	s.props = [Props.make("table", Props.xf_at(Vector3(hand.x - 0.25, 0, hand.z), 90.0)), Props.make("ball", Props.xf_at(Vector3(hand.x, 0.75, hand.z)))]
	s.cards[0]["take"] = {"prop": 1, "hands": ["_r"]}
	m._rebuild_cards()
	m._props_show()
	m.S.apply(B, 0.3)
	var ts: Array = s.times()
	print("card times ", ts)
	var t0 := snappedf(0.8, 1.0 / FPS)
	var catcher := {"S": s, "B": B, "hand": "hand_l"}
	var before := js(s)
	# 1 RELEASE
	var dt := 1.0 / FPS
	var st := ThrowCatch.release_state(s, B, 1, t0)
	var a := ThrowCatch.prop_xf(s, B, 1, t0 - dt).origin
	var b := ThrowCatch.prop_xf(s, B, 1, t0).origin
	s.apply(B, t0 - dt)
	var w_a: Vector3 = B.P["hand_r"]
	s.apply(B, t0)
	var w_b: Vector3 = B.P["hand_r"]
	var vw := (w_b - w_a) / dt
	var v0: Vector3 = st["v0"]
	print("release v0 ", v0, " wrist v ", vw, " w ", st["w"])
	var lever := b.distance_to(w_b)
	var wn := (st["w"] as Vector3).length()
	ok(v0.distance_to((b - a) / dt) < 1e-6 and v0.y > 0.5 and v0.distance_to(vw) < wn * lever * 1.3 + 0.1, "1 release velocity %s m/s = one-frame difference of the held prop; the wrist's is %s (diff %.2f; the prop is %.0f cm from the wrist and turns at %.1f rad/s: lever arm %.2f m/s, bar 1.3x + 0.1)" % [v0, vw, v0.distance_to(vw), lever * 100, wn, wn * lever])
	# 2 ARC with a known velocity
	s.apply(B, t0)
	var xs: float = (B.P["upperarm_l"] as Vector3).x
	var vk := Vector3((xs - b.x) / 0.49, 2.4, 0.0)   # aimed so that the descending arc comes down over the left shoulder
	var pl := ThrowCatch.plan(s, B, 1, t0, catcher, {"v": vk})
	print("plan ok ", pl["ok"], " why ", pl["why"], " catch_n ", pl.get("catch_n", -1), " arm ", pl["arm"])
	var p0: Vector3 = pl["p0"]
	var worst := 0.0
	var worst_c := 0.0
	var tmp := {"kind": "ball", "xf": Transform3D.IDENTITY, "keys": []}
	for k in pl["keys"]:
		var tau: float = float(k["t"]) - t0
		var an := p0 + vk * tau - Vector3(0, 9.81 * tau * tau / 2.0, 0)
		worst = maxf(worst, (k["pos"] as Vector3).distance_to(an))
		Props.key_at(tmp, float(k["t"]), Props.xf_at(k["pos"], float(k["yaw"])))
	for k in pl["keys"]:
		worst_c = maxf(worst_c, (Props.posed(tmp, float(k["t"]))["xf"] as Transform3D).origin.distance_to(k["pos"]))
	ok(worst < 1e-3 and worst_c < 1e-3 and (pl["keys"] as Array).size() > 5, "2 %d keys on the analytic arc: worst %.4f mm, the prop's own curve %.4f mm (bar 1 mm)" % [(pl["keys"] as Array).size(), worst * 1000, worst_c * 1000])
	# 3 FLIGHT TIME
	ok(bool(pl["ok"]), "3 the known toss is caught: frame %d (%s)" % [int(pl.get("catch_n", -1)), pl["why"]])
	var yc: float = (pl["catch_pos"] as Vector3).y if pl.has("catch_pos") else p0.y
	var tan := (vk.y + sqrt(vk.y * vk.y - 2.0 * 9.81 * (yc - p0.y))) / 9.81
	var tf: float = float(pl.get("t_catch", t0)) - t0
	ok(absf(tf - tan) <= dt, "3 flight time %.4f s vs analytic %.4f s at the catch height %.3f m (diff %.1f ms, bar %.1f ms)" % [tf, tan, yc, absf(tf - tan) * 1000, dt * 1000])
	var far := ThrowCatch.plan(s, B, 1, t0, catcher, {"v": Vector3(0, 2.4, 4.0)})
	var tsame := -1.0
	for k in far["keys"]:
		var tau2: float = float(k["t"]) - t0
		if tau2 > 2.4 / 9.81 and (k["pos"] as Vector3).y <= p0.y:
			tsame = tau2
			break
	ok(not bool(far["ok"]) and absf(tsame - 2.0 * 2.4 / 9.81) <= dt, "3 same-height return at %.4f s vs 2 vy / g = %.4f s (bar 1 frame = %.1f ms)" % [tsame, 4.8 / 9.81, dt * 1000])
	# 4 CATCH
	var cl := ThrowCatch.copy_scene(s)
	ThrowCatch.commit(cl, 1, pl, {"S": cl, "B": B, "hand": "hand_l"})
	var tc: float = pl.get("t_catch", t0)
	cl.apply(B, tc)
	var pp: Vector3 = (cl.props_at(tc, B)[1]["xf"] as Transform3D).origin
	var dh: float = (B.P["hand_l"] as Vector3).distance_to(pp)
	ok(dh < 0.01, "4 at the catch frame the left wrist is %.2f mm from the prop (bar 10 mm)" % (dh * 1000))
	var drift := 0.0
	for k in 10:
		var tt := tc + 0.1 * k
		cl.apply(B, tt)
		drift = maxf(drift, (cl.props_at(tt, B)[1]["xf"] as Transform3D).origin.distance_to(pp))
	ok(drift < 1e-3, "4 afterwards the prop stays in the caught place (max drift %.3f mm)" % (drift * 1000))
	cl.apply(B, t0 - 0.2)
	var pre: Vector3 = (cl.props_at(t0 - 0.2, B)[1]["xf"] as Transform3D).origin
	s.apply(B, t0 - 0.2)
	var pre0: Vector3 = (s.props_at(t0 - 0.2, B)[1]["xf"] as Transform3D).origin
	ok(pre.distance_to(pre0) < 1e-3, "4 before the release the prop is still in the right hand as it was (%.3f mm)" % (pre.distance_to(pre0) * 1000))
	# 5 RED
	ok(not bool(far["ok"]) and String(far["why"]).begins_with("out of reach"), "5 an over-the-head toss 4 m away: red '%s'" % String(far["why"]).left(150))
	var fast := ThrowCatch.plan(s, B, 1, t0, catcher, {"v": Vector3(0.2, 16.0, 0.0)})
	ok(not bool(fast["ok"]) and String(fast["why"]).begins_with("too fast"), "5 a 16 m/s toss: red '%s'" % String(fast["why"]).left(150))
	var jn := js(s)
	ok(jn == before, "5/6 planning wrote nothing: the scene JSON is the same")
	# 6 the app: the command, preview, accept, undo
	m.playhead = t0
	m.sel_prop = 1
	m.sel = "hand_l"
	m.S.apply(m.B, t0)
	m.tcat_ui.show()
	await idle(2)
	var up: Dictionary = m.tcat_ui.pl
	print("ui plan ok ", up.get("ok"), " why ", up.get("why"))
	var acc: Button = m.ui_find_list.find_child("tc_accept", true, false)
	ok(acc != null and (acc.disabled == (not bool(up.get("ok", false)))), "6 the panel shows Accept, disabled when red (this plan is %s)" % ("green" if bool(up.get("ok", false)) else "red"))
	m.tcat_ui.halt()
	# the hand-solved plan may be red or green; the known toss is used for the numbers below
	m.tcat_ui.pl = ThrowCatch.plan(m.S, m.B, 1, t0, m.tcat_ui.catcher, {"v": vk})
	m.S.apply(m.B, t0)
	m.tcat_ui._panel()
	m.tcat_ui.draw_arc(m.tcat_ui.pl)
	m.tcat_ui.preview()
	var js0 := js(m.S)
	for i in 20:
		m.tcat_ui.tick(0.03)
		await process_frame
	ok(js(m.S) == js0 and js0 == before, "6 Preview and its 20 ticks leave the scene JSON unchanged")
	m.tcat_ui.halt()
	var steps0: int = m.undo.size()
	var fixed := ThrowCatch.plan(m.S, m.B, 1, t0, m.tcat_ui.catcher, {"v": vk})
	m.tcat_ui.commit(fixed)
	await idle(2)
	var after := js(m.S)
	ok(m.undo.size() - steps0 == 1 and after != before, "6 Accept is exactly %d undo step and changes the scene" % (m.undo.size() - steps0))
	m.S.apply(m.B, tc)
	var pp2: Vector3 = (m.S.props_at(tc, m.B)[1]["xf"] as Transform3D).origin
	ok((m.B.P["hand_l"] as Vector3).distance_to(pp2) < 0.01, "4 in the app too: the wrist is %.2f mm from the prop at the catch frame" % (((m.B.P["hand_l"] as Vector3).distance_to(pp2)) * 1000))
	# the picture: whole body, the arc, the ticks, the ring on the hand
	m.playhead = tc
	m.S.apply(m.B, tc)
	m._props_pose()
	m._refresh()
	m.target = Vector3(-0.2, 1.3, 0.0)
	m.dist = 3.6
	m.yaw = 0.0
	m.pitch = 4.0
	m._cam()
	await idle(3)
	await RenderingServer.frame_post_draw
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var cpos: Vector3 = fixed["catch_pos"]
	var cpx: Vector2 = m.cam.unproject_position(cpos)
	var hpx: Vector2 = m.cam.unproject_position(m.B.P["hand_l"])
	var inside := 0
	for k in fixed["keys"]:
		if Rect2(Vector2.ZERO, vp).has_point(m.cam.unproject_position(k["pos"])):
			inside += 1
	ok(m.tcat_ui.arc != null and m.tcat_ui.verts > 100 and inside == (fixed["keys"] as Array).size() and cpx.distance_to(hpx) < 40.0,
		"7 placement: arc drawn (%d vertices), %d of %d frame ticks inside the %s window, the catch ring %.0f px from the catching hand" % [m.tcat_ui.verts, inside, (fixed["keys"] as Array).size(), vp, cpx.distance_to(hpx)])
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var img: Image = m.get_viewport().get_texture().get_image()
	ok(img.save_png(SHOT) == OK, "7 picture saved: %s" % SHOT)
	m._undo()
	await idle(2)
	ok(js(m.S) == before, "6 Ctrl+Z restores the scene JSON exactly (props and IK)")
	print("i27: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)
