## godot --path . -s tests/i41_test.gd     (ROADMAP I41: gaze director, scripts/gaze.gd + gaze_ui.gd; needs a window)
## The scene: the hero plays combo3's first seven cards; fighter 2 plays the same clip started 0.6 s later (so its strikes arrive between the
## hero's), 1.1 m away facing him. The gaze is the hero's.
## Bars, written before measuring:
##  (1) with the plan (telegraph on) the hero's gaze ray passes within 10 cm of the opponent's upper chest on >= 90 % of the frames (30 fps, whole clip)
##  (2) a telegraph glance (a strike whose target is within 15 cm of the chest point gets none: the gaze is there already): for each of the hero's strikes, the plan has a key at (arrival - 0.2 s) that is BEFORE the arrival, and halfway through the
##      glance the head's forward differs by >= 3 deg from the chest-only gaze (the same clip, telegraph off); with the telegraph OFF the plan has no
##      telegraph glance and the head's forward at those instants equals the chest-only gaze to 0.5 deg
##  (3) a weapon glance for each incoming strike of fighter 2, ending before it lands, with the gaze ray within 10 cm of the weapon tip at the glance's
##      middle (default habit)
##  (4) the neck and head are inside the body's limits at every frame (excess <= 1e-6 deg) and every written key is inside them too
##  (5) undo: show() and Preview leave the scenes and the hero body state byte-identical; Accept adds exactly one undo step and Ctrl+Z restores both
##      scenes' JSON exactly; Accept writes only the neck and head part keys (the cards are untouched)
##  (6) learn(): a scene with no head keys gives the default; the accepted scene (head keys glancing at the weapons) learns weapon = true from every
##      incoming strike; a scene whose head stares at the chest all the time learns weapon = false
##  (7) placement: the screenshot is a whole-body side view with the gaze rays drawn from the hero's eye; both heads, the opponent's chest and the
##      ray's end are inside the frame, the ray starts within 20 cm of the hero's head joint, and at the screenshot instant the ray ends within 10 cm of the chest
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


func xf() -> Transform3D:
	return (m.actors_rt[0]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[1]["xf"] as Transform3D)


func full_json() -> String:
	return var_to_str([m.actors_rt[0]["S"].cards, m.actors_rt[0]["S"].part_keys, m.actors_rt[1]["S"].cards, m.actors_rt[1]["S"].part_keys])


func cards_json() -> String:
	return JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards])


func fwd_at(S: Scene, D: Scene, t: float) -> Vector3:
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	S.apply(BA, t)
	D.apply(BD, t)
	return LookAt.head_forward(BA)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.cards = m.S.cards.slice(0, 7)
	m._rebuild_cards()
	var sb := DistanceKeeper.new_body()
	sb.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	sb.ground()
	var d2: Scene
	d2 = m.S.clone()
	d2.cards[0]["hold"] = float(d2.cards[0].get("hold", 0.0)) + 0.6
	d2.part_keys = {}
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": d2})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m._fighters_on() and m.actor_on == 0, "two fighters, the hero looks")
	var ui = m.gz_ui
	var A: Scene = m.actors_rt[0]["S"]
	var D: Scene = m.actors_rt[1]["S"]
	var X := xf()
	var j0 := full_json()
	var c0 := cards_json()
	var u0: int = m.undo.size()
	var st0: Dictionary = (m.actors_rt[0]["B"] as Body).state()

	# the analysis is read only
	ui.show()
	await idle()
	ok(full_json() == j0 and m.undo.size() == u0 and JSON.stringify((m.actors_rt[0]["B"] as Body).state()) == JSON.stringify(st0), "(5) show() changed nothing: scenes, undo stack and the hero body state are identical")
	var plan: Dictionary = ui.plan
	var ev: Dictionary = plan["ev"]
	print("       %s; habit %s; chest share now %.1f %%, with the plan %.1f %%" % [plan["msg"], ui.habit["source"], ui.share_now * 100.0, ui.share_new * 100.0])
	for w in ev["tele"]:
		print("       telegraph card %d: %.2f-%.2f s at the %s, strike lands %.2f s" % [int(w["card"]), w["t0"], w["t1"], w["part"], w["arrive"]])
	for w in ev["weap"]:
		print("       weapon card %d: %.2f-%.2f s at the %s, strike lands %.2f s" % [int(w["card"]), w["t0"], w["t1"], w["tip"], w["arrive"]])

	# (1) the chest share
	var withp := Gaze.applied(A, plan)
	var me := Gaze.measure(withp, D, X, 30)
	var m0 := Gaze.measure(A, D, X, 30)
	print("       frames %d: on the chest %.1f %% with the plan (before: %.1f %%), worst %.1f cm" % [me["frames"], me["on_chest"] * 100.0, m0["on_chest"] * 100.0, float(me["worst"]) * 100.0])
	var offs := []
	for f in me["frames"]:
		if float(me["miss"][f]) > Gaze.ON_CHEST:
			offs.append("%.2f:%.0f" % [float(f) / 30.0, float(me["miss"][f]) * 100.0])
	print("       off-chest frames (s:cm): " + " ".join(offs))
	ok(float(me["on_chest"]) >= 0.90, "(1) the gaze ray is within 10 cm of the opponent's chest on %.1f %% of %d frames (bar 90 %%)" % [me["on_chest"] * 100.0, me["frames"]])

	# (2) the telegraph glance
	var off := Gaze.compute(A, D, X, false, ui.habit, 30)
	var base := Gaze.compute(A, D, X, false, {"weapon": false, "source": "t", "n": 0}, 30)   # chest only
	var offA := Gaze.applied(A, off)
	var baseA := Gaze.applied(A, base)
	ok(ev["tele"].size() >= 1 and off["ev"]["tele"].is_empty(), "(2) %d telegraph glances with the switch on, %d with it off" % [ev["tele"].size(), off["ev"]["tele"].size()])
	var all_before := true
	var min_on := INF
	var max_off := 0.0
	for w in ev["tele"]:
		var tm := (float(w["t0"]) + float(w["t1"])) * 0.5
		all_before = all_before and float(w["t0"]) < float(w["arrive"]) and absf(float(w["arrive"]) - float(w["t0"]) - Gaze.TELEGRAPH_LEAD) < 1e-6 or float(w["t0"]) == 0.0
		var f_on := fwd_at(withp, D, tm)
		var f_base := fwd_at(baseA, D, tm)
		var f_off := fwd_at(offA, D, tm)
		min_on = minf(min_on, rad_to_deg(f_on.angle_to(f_base)))
		max_off = maxf(max_off, rad_to_deg(f_off.angle_to(f_base)))
		print("       strike lands %.2f s: glance at %.2f s moves the head %.1f deg off the chest gaze; with the switch off %.2f deg" % [w["arrive"], tm, rad_to_deg(f_on.angle_to(f_base)), rad_to_deg(f_off.angle_to(f_base))])
	ok(all_before and min_on >= 3.0, "(2) every telegraph glance starts %.1f s before its strike and turns the head >= 3 deg (smallest %.1f deg)" % [Gaze.TELEGRAPH_LEAD, min_on])
	ok(max_off <= 0.5, "(2) with the telegraph off the head stays on the chest gaze at those instants (largest difference %.2f deg)" % max_off)

	# (3) the weapon glance
	var wok: bool = ev["weap"].size() >= 2
	var wmax := 0.0
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	for w in ev["weap"]:
		var tm := (float(w["t0"]) + float(w["t1"])) * 0.5
		withp.apply(BA, tm)
		D.apply(BD, tm)
		var mm := Gaze.ray_miss(BA, X * (DistanceKeeper.tips(BD)[w["tip"]] as Vector3))
		wmax = maxf(wmax, mm)
		wok = wok and float(w["t1"]) < float(w["arrive"]) and mm <= 0.10
	ok(wok, "(3) %d weapon glances end before the strike lands, the ray is within %.1f cm of the weapon tip at the middle (bar 10 cm)" % [ev["weap"].size(), wmax * 100.0])

	# (4) limits
	var ex := Gaze.limit_excess(withp, 30)
	var kex := 0.0
	var BL := DistanceKeeper.new_body()
	for j in Gaze.JOINTS:
		for k in plan["keys"][j]:
			var v: Vector3 = k["v"]
			var c: Vector3 = BL.clamp_ang(j, v)
			kex = maxf(kex, maxf(absf(v.x - c.x), maxf(absf(v.y - c.y), absf(v.z - c.z))))
	ok(ex <= 1e-6 and kex <= 1e-6, "(4) neck and head inside the limits at every frame (excess %.6f deg) and in every key (%.6f deg), %d keys per joint" % [ex, kex, plan["n"]])

	# (5) preview and accept
	ui.preview()
	var ticks := 0
	while ui.pv and ticks < 900:
		await process_frame
		ticks += 1
	ok(not ui.pv and ticks > 5 and full_json() == j0 and m.undo.size() == u0, "(5) Preview played %d frames and the scenes are byte-identical" % ticks)
	ui.accept()
	await idle()
	ok(m.undo.size() == u0 + 1 and cards_json() == c0 and A.part_keys.has("head") and A.part_keys.has("neck_01") and full_json() != j0 and not D.part_keys.has("head"),
		"(5) Accept is one undo step (%d -> %d), the cards untouched, only the hero's neck and head keyed" % [u0, m.undo.size()])
	A = m.actors_rt[0]["S"]
	var me2 := Gaze.measure(A, D, X, 30)
	ok(absf(float(me2["on_chest"]) - float(me["on_chest"])) < 1e-9, "(5) the accepted scene plays the plan exactly (chest share %.1f %%)" % [me2["on_chest"] * 100.0])

	# (6) learn
	var l0 := Gaze.learn(Gaze.bare(A), D, X, 30)
	var l1 := Gaze.learn(A, D, X, 30)
	var stare := Gaze.applied(A, base)
	var l2 := Gaze.learn(stare, D, X, 30)
	print("       learn: no keys -> %s; glancing -> %s share %.2f of %d; staring -> %s share %.2f" % [l0["source"], l1["source"], l1["weapon_share"], l1["n"], l2["source"], l2["weapon_share"]])
	ok(l0["source"] == "default" and l1["source"] == "learned" and l1["weapon"] and l1["n"] == ev["weap"].size() and float(l1["weapon_share"]) >= 0.99 and l2["source"] == "learned" and not l2["weapon"],
		"(6) learn: default without head keys; weapon glances learned from glancing keys (%.0f %% of %d strikes); not learned from a fixed stare" % [l1["weapon_share"] * 100.0, l1["n"]])

	# (7) the screenshot, with the rays drawn
	m.playhead = 0.4   # a chest-gaze instant, before the first glance
	m._ps().apply(m.B, m.playhead)
	m._close_findings()
	m.yaw = 90.0
	m.pitch = -4.0
	m.dist = 5.2
	m.target = Vector3(0.0, 1.0, 0.55)
	m._cam()
	m._refresh()
	await idle(4)
	var BH: Body = m.actors_rt[0]["B"]
	var BO: Body = m.actors_rt[1]["B"]
	m.actors_rt[0]["S"].apply(BH, m.playhead)
	m.actors_rt[1]["S"].apply(BO, m.playhead)
	BH.fk()
	var sx: Transform3D = m._stage_xf()
	var wx0: Transform3D = sx * (m.actors_rt[0]["xf"] as Transform3D)
	var wx1: Transform3D = sx * (m.actors_rt[1]["xf"] as Transform3D)
	var eye := LookAt.eye_point(BH)
	var fw := LookAt.head_forward(BH)
	var ch := Gaze.chest(BO, X)
	var tl := (ch - eye).length()
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mi.material_override = mat
	m.cam.get_parent().add_child(mi)   # the 3D world of the view (the window root is another world)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var tip: Vector3 = wx0 * (eye + fw * tl)
	im.surface_set_color(Color(1.0, 0.85, 0.1))
	im.surface_add_vertex(wx0 * eye)
	im.surface_set_color(Color(1.0, 0.85, 0.1))
	im.surface_add_vertex(tip)
	var chw: Vector3 = wx1 * ch.lerp(ch, 1.0)   # the chest in the opponent's own frame is X * local; drawn in stage space below
	chw = wx0 * ch
	for d in [Vector3(0.06, 0, 0), Vector3(0, 0.06, 0), Vector3(0, 0, 0.06)]:
		im.surface_set_color(Color(0.2, 0.9, 1.0))
		im.surface_add_vertex(chw - d)
		im.surface_set_color(Color(0.2, 0.9, 1.0))
		im.surface_add_vertex(chw + d)
	im.surface_end()
	# the opponent's gaze for the picture: a second ray (it looks at the hero's chest by the same rule)
	await idle(4)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i41.png")
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	var pts := [wx0 * (BH.P["head"] as Vector3), wx0 * (X * (BO.P["head"] as Vector3)), chw, tip]
	var inside := true
	for p in pts:
		var sp: Vector2 = m.cam.unproject_position(p)
		inside = inside and vp.has_point(sp) and not m.cam.is_position_behind(p)
		print("       screen point (%.0f, %.0f)" % [sp.x, sp.y])
	var start_d := (eye - (BH.P["head"] as Vector3)).length()
	var end_miss := Gaze.ray_miss(BH, ch)
	ok(inside and start_d < 0.20 and end_miss <= 0.10, "(7) screenshot: both heads, the chest and the ray end are in the frame; the ray starts %.1f cm from the head joint and passes %.1f cm from the chest" % [start_d * 100.0, end_miss * 100.0])
	mi.queue_free()

	# (5) undo
	m._undo()
	await idle()
	m._actors_sync()
	ok(full_json() == j0 and m.undo.size() == u0, "(5) Ctrl+Z: both scenes' JSON is exact again")

	# the switch in the panel
	ui.show()
	await idle()
	ui.set_tele(false)
	ok(ui.plan["ev"]["tele"].is_empty() and ui.plan["ev"]["weap"].size() == ev["weap"].size() and m.undo.size() == u0, "(2) the panel's telegraph switch off: no telegraph glance, the weapon glances stay, nothing written")

	print("I41 GAZE DIRECTOR %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


func bare_of(S: Scene) -> Scene:
	return Gaze.bare(S)
