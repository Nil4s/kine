## godot --path . -s tests/actors_view_test.gd     (round 50, GATES TC4; a window: real mouse events through the viewport)
## THE SECOND FIGHTER ON SCREEN. The active fighter stays at the world origin (main.skel, every pick and drag as before);
## the stage (floor, axes, lights, the other fighters' mannequins) carries the inverse of the active one's placement and
## the camera moves with it, so a switch moves nothing on screen. combo3 is opened read only; nothing is written to scenes/.
## Bars, written before measuring:
##   1 DRAWN WHERE IT STANDS: with a second fighter added the other mannequin exists, and each of its bones' world
##     positions = that fighter's Body.P transformed by its placement relative to the active one, within 1 mm, at 3
##     scrubbed playheads and 3 moments while playing (and the hero's mannequin the same once fighter 2 is active)
##   2 NO JUMP: switching the active fighter (the command both ways, a click both ways) moves the screen position of 5
##     landmarks (each fighter's head and pelvis, fighter 2's right hand) by less than 1 pixel
##   3 CLICK: 20 clicks at the projected centres of fighter 2's parts make it active and select that part, 100 %; 20
##     clicks on the active fighter's parts keep it active and select that part, 100 % (a part is a target when, by the
##     test's own ray test over both bodies, it is the nearest thing under its centre and the centre is in the 3D view)
##   4 DRAG: a press on fighter 2's lowerarm (it becomes active) dragged 10 steps turns every joint by the same angles,
##     within 0.5 deg, as the same drag on the hero in a one-actor session (same pose, same camera relative to the body)
##   5 ONE ACTOR UNCHANGED: with one actor the stage holds the nodes it held before (counted, again after add + remove);
##     the dummy works (on, drawn, its hits measured); a screenshot of the 3D view (UI hidden) at a fixed camera before
##     the add = after add + remove, 0 pixels differ; and, when tests/ is run with a base image (ZZ_TC4_BASE=1 on the
##     pre-TC4 tree writes user://zz_tc4_base.png), 0 pixels differ from the pre-TC4 build too
##   6 the dummy is off (and not drawn) with 2 fighters, back on (drawn) with 1
## Shot: user://zz_tc4_shot.png (the two-fighter view)
extends SceneTree

var fails := 0
var m: Node
const CAM := [30.0, -10.0, 5.0, Vector3(0, 0.95, 0.75)]   # the fixed one-actor camera (yaw, pitch, dist, target)
const BOTH := [70.0, -12.0, 4.6, Vector3(0, 0.95, 0.75)]  # both fighters side by side
const REL := [40.0, -10.0, 3.5]                            # the drag's camera, relative to the body dragged
const JD := "upperarm_r"
# the drag goes OUT and up, away from the chest: the old (90, -60) pushed the arm across the body, into the clavicle / trunk-skin contact stops,
# where it stops moves with float noise (0.85 deg between two identical drags). This test compares the two frames, not the contact solver.
const DRAGV := Vector2(-90, -60)


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


func click(p: Vector2) -> void:
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)


## a real drag: press at p, 10 moves of d / 10, release
func drag(p: Vector2, d: Vector2) -> void:
	await mouse(p, true)
	await idle(1)
	for k in 10:
		await move(p + d * (k + 1) / 10.0, d / 10.0)
	await mouse(p + d, false)
	await idle(2)


func cam(c: Array) -> void:
	m._turn_to(c[0], c[1], c[2], c[3], false)
	await idle(2)


func open_combo() -> void:
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 0.9
	m.playing = false
	m._ps().apply(m.B, m.playhead)
	m.sel = "head"
	m.hover_part = ""
	m._refresh()
	m.undo.clear()
	m.redo.clear()
	await m.dummy_settle()
	m._refresh()
	await idle(3)


## the 3D view alone (the UI hidden), at the fixed camera
func shot3d() -> Image:
	m.ui_root.visible = false
	await cam(CAM)
	await idle(6)
	var img := root.get_texture().get_image()
	m.ui_root.visible = true
	await idle(2)
	return img


func pixels_differ(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func count_under(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + count_under(ch)
	return c


## actor k's bone j in world space, as drawn: the main skeleton for the active fighter, its mannequin for the others
func bone_world(k: int, j: String) -> Vector3:
	var sk: Skeleton3D = m.skel if k == m.actor_on else m.actor_men[k]["skel"]
	var ix: int = m.bone_idx[j] if k == m.actor_on else m.actor_men[k]["idx"][j]
	return sk.global_transform * sk.get_bone_global_pose(ix).origin


## actor k's body space -> the world (the stage's transform, then its placement)
func body_to_world(k: int) -> Transform3D:
	return m.stage_root.global_transform * (m.actors_rt[k]["xf"] as Transform3D)


## the worst (mm) of |drawn bone - Body.P at its placement| over every joint of actor k that has a bone
func bone_err(k: int) -> float:
	var X := body_to_world(k)
	var b: Body = m.actors_rt[k]["B"]
	var w := 0.0
	for j in Body.ORDER:
		if int(m.bone_idx[j]) < 0:
			continue
		w = maxf(w, bone_world(k, j).distance_to(X * (b.P[j] as Vector3)))
	return w * 1000.0


const MARKS := [[0, "head"], [0, "pelvis"], [1, "head"], [1, "pelvis"], [1, "hand_r"]]


func marks() -> Array:
	return MARKS.map(func(mk): return m.cam.unproject_position(bone_world(mk[0], mk[1])))


func worst_px(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		w = maxf(w, (a[i] as Vector2).distance_to(b[i]))
	return w


## the test's own pick: [actor, part] of the nearest thing under screen point p over every fighter: a body part is its
## SKIN (PRECISE PICK: each fighter's SkinPick, the posed mesh; tests/precise_pick_test.gd checks it against a brute
## force), the active one's weapon its capsule (as _pick takes it), or [-1, ""]
func nearest(p: Vector2) -> Array:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var d: Vector3 = m.cam.project_ray_normal(p)
	var best := [-1, ""]
	var bt := INF
	for k in m.actors_rt.size():
		var b: Body = m.actors_rt[k]["B"]
		var X := body_to_world(k)
		var sp: SkinPick = m.skp if k == m.actor_on else m.actor_men[k]["skp"]
		var h: Array = sp.pick(o, d)
		if String(h[0]) != "" and float(h[1]) < bt:
			bt = float(h[1])
			best = [k, String(h[0])]
		for j in (Body.WEAPON if b.wep_on and k == m.actor_on else []):
			var c: Array = b.cap(j)
			var r: Vector2 = m._ray_seg(o, d, X * (c[0] as Vector3), X * (c[1] as Vector3))
			if r.y <= maxf(float(b.rad[j]) * 1.15, 0.014) and r.x < bt:
				bt = r.x
				best = [k, j]
	return best


func centre(k: int, j: String) -> Vector2:
	var c: Array = (m.actors_rt[k]["B"] as Body).cap(j)
	return m.cam.unproject_position(body_to_world(k) * (((c[0] as Vector3) + (c[1] as Vector3)) * 0.5))


func in_view(p: Vector2) -> bool:
	var vs: Vector2 = root.get_visible_rect().size
	return p.x > m.lw() + 4 and p.x < vs.x - m.rw() - 4 and p.y > m.TOP_H + 4 and p.y < vs.y - m.bottom_h - 4


func ang_of(b: Body) -> Dictionary:
	return b.ang.duplicate()


## the worst per-joint difference (deg) between two drags' changes
func delta_diff(a0: Dictionary, a1: Dictionary, b0: Dictionary, b1: Dictionary) -> Array:
	var w := 0.0
	var size := 0.0
	for j in Body.ORDER:
		var da: Vector3 = (a1[j] as Vector3) - (a0[j] as Vector3)
		var db: Vector3 = (b1[j] as Vector3) - (b0[j] as Vector3)
		w = maxf(w, (da - db).abs()[(da - db).abs().max_axis_index()])
		size = maxf(size, da.abs()[da.abs().max_axis_index()])
	return [w, size]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await open_combo()

	var shot_a := await shot3d()
	if OS.get_environment("ZZ_TC4_BASE") != "":   # the pre-TC4 tree: its picture, then out (it has none of the rest)
		shot_a.save_png("user://zz_tc4_base.png")
		print("base image written: %s" % ProjectSettings.globalize_path("user://zz_tc4_base.png"))
		quit(0)
		return

	# ---- (5) one actor, before: the stage's nodes, the dummy, the picture
	var n0 := count_under(m.stage_root)
	var dummy_ok: bool = m.dummy_on and m.dummy_node.visible and m.actor_men.is_empty() and m.stage_root.transform == Transform3D.IDENTITY
	ok(dummy_ok and n0 > 0, "5: one actor: %d nodes under the stage (floor, grid, axes, 3 letters, 2 lights), no fighters drawn, stage at the identity, the dummy on and drawn (%s)" % [n0, m.ui_dummy.text.get_slice("\n", 0)])
	if FileAccess.file_exists("user://zz_tc4_base.png"):
		var base := Image.load_from_file(ProjectSettings.globalize_path("user://zz_tc4_base.png"))
		var nb := pixels_differ(shot_a, base)
		ok(nb == 0, "5: one actor, this build vs the pre-TC4 build at the same camera: %d pixels differ (of %d)" % [nb, shot_a.get_width() * shot_a.get_height()])
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://zz_tc4_base.png"))
	else:
		print("     (no pre-TC4 base image: that comparison was not run this time)")

	# ---- (4) the one-actor drag on the hero, at REL around it
	var X0: Dictionary = m.B.state()
	await cam([REL[0], REL[1], REL[2], Vector3(0, 0.95, 0)])
	var p0: Vector2 = centre_one(JD)
	var a00 := ang_of(m.B)
	await drag(p0, DRAGV)
	var a01 := ang_of(m.B)
	var sel0: String = m.sel
	m._undo()
	m._refresh()
	await idle(2)
	ok(m.B.state() == X0 and sel0 == JD, "4: one actor: the drag on the hero's %s picked %s; Ctrl+Z put the pose back" % [JD, sel0])

	# ---- add a second fighter
	m._actor_add()
	await idle(3)
	ok(m.actors_rt.size() == 2 and m.actor_men.size() == 2 and (m.actor_men[1]["node"] as Node3D).visible and not (m.actor_men[0]["node"] as Node3D).visible,
		"1: added: 2 fighters, a mannequin for fighter 2 drawn (the hero's own hidden: skel draws the active one)")
	# (6)
	ok(not m.dummy_on and not m.dummy_node.visible, "6: two fighters: the dummy is off (%s) and not drawn" % m.ui_dummy.text.get_slice("\n", 0))

	# ---- (1) drawn where it stands: scrubbing, then playing
	var errs := []
	var L: float = m.S.length()
	for t in [0.3, L * 0.5, L * 0.85]:
		m.playhead = t
		m._ps().apply(m.B, t)
		m._refresh()
		await idle(1)
		errs.append(bone_err(1))
	var poses := {}
	m.playhead = 0.0
	m.playing = true
	for i in 3:
		await idle(7)
		errs.append(bone_err(1))
		poses[snappedf(m.playhead, 0.001)] = (m.actors_rt[1]["B"] as Body).state()
	m.playing = false
	await idle(2)
	ok(errs.max() <= 1.0 and poses.size() == 3, "1: fighter 2's bones = its Body.P at its placement: worst %s mm (bar 1) at 3 scrubbed playheads and 3 while playing (%s s)" % [errs.map(func(e): return snappedf(e, 0.0001)), poses.keys()])

	# ---- (2) no jump: command both ways
	await cam(BOTH)
	m.playhead = 1.1
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(2)
	var jumps := []
	var before := marks()
	m._actor_next()
	await idle(2)
	var after := marks()
	jumps.append(["command 1 -> 2", worst_px(before, after), m.actor_on == 1])
	var e1 := bone_err(0)
	ok(m.actor_on == 1 and e1 <= 1.0 and bone_err(1) <= 1.0, "1: fighter 2 active: the hero's mannequin = its Body.P at its placement relative to fighter 2 (%.4f mm), fighter 2 at the origin by skel (%.4f mm)" % [e1, bone_err(1)])
	before = after
	m._actor_next()
	await idle(2)
	after = marks()
	jumps.append(["command 2 -> 1", worst_px(before, after), m.actor_on == 0])

	# ---- (3) clicks; the first ones also measure (2) by click
	var t1 := []
	var t0 := []
	var skipped := []
	for j in Body.ORDER:
		var p := centre(1, j)
		var nn := nearest(p)
		if in_view(p) and nn == [1, j]:
			t1.append(j)
		else:
			skipped.append("2:" + j)
	for j in Body.ORDER:
		var p := centre(0, j)
		var nn := nearest(p)
		if in_view(p) and nn == [0, j]:
			t0.append(j)
		else:
			skipped.append("1:" + j)
	print("     click targets: fighter 2 %d, the active hero %d; not targets (hidden behind another part or out of the view): %s" % [t1.size(), t0.size(), skipped])
	var hit1 := 0
	var tried1 := 0
	var miss := []
	for j in t1.slice(0, 20):
		if m.actor_on != 0:
			m._actor_go(0)
			await idle(1)
		before = marks()
		await click(centre(1, j))
		tried1 += 1
		if m.actor_on == 1 and m.sel == j:
			hit1 += 1
		else:
			miss.append("%s -> actor %d %s" % [j, m.actor_on, m.sel])
		if tried1 == 1:
			jumps.append(["click on fighter 2", worst_px(before, marks()), m.actor_on == 1])
			# and back by a click on the hero (fighter 2 active now)
			var hj := ""
			for cj in t0:   # a hero part that is the nearest thing under its centre now
				if hj == "" and nearest(centre(0, cj)) == [0, cj]:
					hj = cj
			before = marks()
			await click(centre(0, hj))
			jumps.append(["click on the hero", worst_px(before, marks()), m.actor_on == 0 and m.sel == hj])
	ok(tried1 == 20 and hit1 == 20, "3: 20 clicks on fighter 2's parts (the hero active): %d of %d made it active with that part picked %s" % [hit1, tried1, miss])
	if m.actor_on != 0:
		m._actor_go(0)
		await idle(1)
	var hit0 := 0
	var tried0 := 0
	miss = []
	for j in t0.slice(0, 20):
		await click(centre(0, j))
		tried0 += 1
		# the foot's reverse-foot handles (ROADMAP 6, FootHandles): with a foot picked, its BALL handle sits on the toe joint,
		# so a click at the ball part's centre is a press on that handle, which keeps the FOOT picked (main._frh_press).
		var via_handle: bool = (j == "ball_l" or j == "ball_r") and m.sel == "foot" + j.right(2)
		if m.actor_on == 0 and (m.sel == j or via_handle):
			hit0 += 1
		else:
			miss.append("%s -> actor %d %s" % [j, m.actor_on, m.sel])
	ok(tried0 == 20 and hit0 == 20, "3: 20 clicks on the active hero's parts: %d of %d kept it active with that part picked %s" % [hit0, tried0, miss])
	var jw := 0.0
	var jok := true
	for jr in jumps:
		print("     switch %s: the 5 landmarks moved up to %.4f px (switched %s)" % jr)
		jw = maxf(jw, jr[1])
		jok = jok and jr[2]
	ok(jumps.size() == 4 and jok and jw < 1.0, "2: no jump: 4 switches (command both ways, click both ways), the 5 landmarks moved up to %.4f px (bar 1)" % jw)
	await cam(BOTH)
	await idle(4)
	root.get_texture().get_image().save_png("user://zz_tc4_shot.png")
	print("     shot: %s" % ProjectSettings.globalize_path("user://zz_tc4_shot.png"))

	# ---- (4) the drag on fighter 2, from a press on it (it becomes active), at REL around it
	var B1: Body = m.actors_rt[1]["B"]
	B1.set_state(X0)
	m.actors_rt[1]["t"] = m.playhead   # not re-posed at this playhead: it keeps X0, as an actor left does
	m._refresh()
	await idle(2)
	var xf1: Transform3D = m.actors_rt[1]["xf"]
	var yaw1 := rad_to_deg(atan2(xf1.basis.z.x, xf1.basis.z.z))
	await cam([wrapf(REL[0] + yaw1, -180.0, 180.0), REL[1], REL[2], xf1 * Vector3(0, 0.95, 0)])
	var p1 := centre(1, JD)
	var nn1 := nearest(p1)
	var a10 := ang_of(B1)
	await drag(p1, DRAGV)
	var a11 := ang_of(B1)
	var dd := delta_diff(a00, a01, a10, a11)
	ok(m.actor_on == 1 and m.sel == JD and nn1 == [1, JD] and dd[0] <= 0.5 and dd[1] > 5.0,
		"4: a press on fighter 2's %s made it active (%d, picked %s) and the drag turned its joints as on the hero alone: worst difference %.4f deg (bar 0.5) over changes up to %.1f deg; press at %s, the hero's at %s" % [JD, m.actor_on, m.sel, dd[0], dd[1], p1.round(), p0.round()])

	# ---- (5) + (6): back to one actor
	m._actor_remove()
	await idle(4)
	await m.dummy_settle()
	m._refresh()
	await idle(2)
	var n1 := count_under(m.stage_root)
	ok(m.actors_rt.is_empty() and n1 == n0 and m.actor_men.is_empty() and m.stage_root.transform == Transform3D.IDENTITY,
		"5: removed: one actor, %d nodes under the stage (was %d), the fighters' mannequins gone, stage at the identity" % [n1, n0])
	ok(m.dummy_on and m.dummy_node.visible and m.ui_dummy.text.begins_with("dummy"), "6: one fighter again: the dummy is back on and drawn (%s)" % m.ui_dummy.text.get_slice("\n", 0))
	m.playhead = 0.9
	m._ps().apply(m.B, m.playhead)
	m.sel = "head"
	m.hover_part = ""
	m._refresh()
	await idle(2)
	var shot_b := await shot3d()
	var nd := pixels_differ(shot_a, shot_b)
	ok(nd == 0, "5: one actor before the add vs after add + remove, same camera, 3D view: %d pixels differ" % nd)
	print("ACTORS VIEW %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func centre_one(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position(((c[0] as Vector3) + (c[1] as Vector3)) * 0.5)
