## godot --path . -s tests/i24_test.gd     (ROADMAP I24: drag the balance, scripts/drag_balance.gd; needs a window)
## The mannequin stands at rest on the floor with the balance view on; the marker is dragged with REAL mouse events.
## Bars, written before measuring:
##  (1) drag the COM's floor point 8 cm toward the right foot: the COM's ground point within 1 cm of the target, both soles (ankle,
##      ball joint, toe tip) fixed < 2 mm, every joint inside its limits, head tilt change < 15 deg, trunk lean < 6 deg
##      REAL HUMANS (heuristic, no single table: lateral weight transfer onto one foot, stance of ~ hip width; Winter 1995, Gait & Posture
##      3:193 for the COM/COP excursion): the pelvis moves ~ 8-12 cm with little trunk lean. Bar: pelvis 6-14 cm sideways, trunk lean < 6 deg
##  (2) drag well outside the hull: the solve stops at the edge (COM within 5 mm of the polygon boundary), says so, the request's ring is
##      RED (BalanceView.RED) while held; a request 1 cm inside the edge is AMBER; soles still < 2 mm
##  (3) drag the COM ball down 10 cm: COM height drops 10 cm +- 1.5 cm, COM ground point within 1 cm of where it was, both knees bend by
##      > 10 deg, soles < 2 mm
##  (4) each drag is exactly one undo step; Ctrl+Z puts the body back bit for bit (B.state())
##  (5) placement: the marker's floor disc is drawn in the hull after a shift, inside the view, and its pixel is under the COM's ground point
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


## press at a, move to b in 8 steps, return what the solve said at the last step; release if `release`
func drag(a: Vector2, b: Vector2, release := true) -> Dictionary:
	await mouse(a, true)
	for k in 8:
		await move(a.lerp(b, float(k + 1) / 8.0), (b - a) / 8.0)
	var r: Dictionary = (m._dgb.get("r", {}) as Dictionary).duplicate()
	r["req"] = (m.bal.req as Dictionary).duplicate()
	if release:
		await mouse(b, false)
		await idle(2)
	return r


func soles() -> Dictionary:
	var out := {}
	for sd in ["_l", "_r"]:
		out["a" + sd] = m.B.P["foot" + sd]
		out["b" + sd] = m.B.P["ball" + sd]
		out["t" + sd] = m.B.E["ball" + sd]
	return out


func sole_err(a: Dictionary, b: Dictionary) -> float:
	var w := 0.0
	for k in a:
		w = maxf(w, ((a[k] as Vector3) - (b[k] as Vector3)).length())
	return w


func limits_ok() -> bool:
	for j in m.B.ang:
		if m.B.lim.has(j) and (m.B.clamp_ang(j, m.B.ang[j]) - (m.B.ang[j] as Vector3)).length() > 1e-3:
			return false
	return true


func floor_px(c: Vector3) -> Vector2:
	return m.cam.unproject_position(Vector3(c.x, 0.0, c.z))


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
	for j in m.B.ang:
		m.B.ang[j] = Vector3.ZERO
	m.B.offset = Vector3.ZERO
	m.B.fk()
	m.B.ground()
	m.B.fk()
	m.bal.on = true
	m.sel = "spine_03"
	m.hover_part = ""
	m._refresh()
	m._turn_to(0.0, -22.0, 3.2, Vector3(0, 0.85, 0), false)
	await idle(5)
	var st0 := DragBalance.begin(m.B)
	var c0: Vector3 = st0["com0"]
	var side := signf((m.B.P["foot_r"] as Vector3).x - c0.x)
	print("rest: COM (%.3f %.3f %.3f), foot_r x %.3f, support down %s, hull %d pts" % [c0.x, c0.y, c0.z, (m.B.P["foot_r"] as Vector3).x, st0["down"], (st0["poly"] as PackedVector2Array).size()])
	var s0 := soles()
	var state0: Dictionary = m.B.state()
	var off0: Vector3 = m.B.offset
	var u0: int = m.undo.size()

	# ---- 1 the 8 cm shift toward the right foot
	var tg := Vector3(c0.x + side * 0.08, 0.0, c0.z)
	var t1 := Time.get_ticks_msec()
	var r1 := await drag(floor_px(c0), floor_px(tg))
	var ms := Time.get_ticks_msec() - t1
	var c1 := Balance.com(m.B)
	var miss := Vector2(c1.x - tg.x, c1.z - tg.z).length()
	var se := sole_err(s0, soles())
	var pel: Vector3 = m.B.offset - off0
	var head := rad_to_deg(((m.B.G["head"] as Quaternion) * Vector3.UP).angle_to(st0["head_up0"]))
	var lean: float = float(r1.get("lean", 99.0))
	print("shift 8 cm: COM miss %.2f mm, soles %.3f mm, pelvis %.1f cm sideways %.1f cm fwd %.1f cm up, trunk lean %.2f deg, head tilt %.2f deg, knees %.1f/%.1f deg (%d ms for the whole drag)" % [
		miss * 1000.0, se * 1000.0, pel.x * side * 100.0, pel.z * 100.0, pel.y * 100.0, lean, head, m.B.ang["calf_l"].x, m.B.ang["calf_r"].x, ms])
	print("       vs real people (heuristic: ~ 8-12 cm pelvis shift, little trunk lean): ours %.1f cm, lean %.2f deg" % [pel.x * side * 100.0, lean])
	ok(miss <= 0.01, "1 the COM's ground point is within 1 cm of the 8 cm target (%.2f mm)" % (miss * 1000.0))
	ok(se < 0.002, "1 both soles fixed < 2 mm (%.3f mm)" % (se * 1000.0))
	ok(limits_ok(), "1 every joint inside its limits")
	ok(head < 15.0 and lean < 6.0, "1 head upright (%.2f deg) and little trunk lean (%.2f deg)" % [head, lean])
	ok(absf(pel.x) >= 0.06 and absf(pel.x) <= 0.14, "1 pelvis shift %.1f cm in the 6-14 cm band for a person" % (pel.x * side * 100.0))
	ok(m.undo.size() == u0 + 1, "4 the drag added exactly one undo step (%d)" % (m.undo.size() - u0))
	# placement: the disc is under the COM's ground point, inside the hull and the view
	var bl: Dictionary = m.bal.last
	var inside := Balance.signed_dist(bl["poly"], Vector2(c1.x, c1.z)) > 0.0
	var px := floor_px(c1)
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var hull_px := Rect2(floor_px(Vector3((bl["poly"][0] as Vector2).x, 0, (bl["poly"][0] as Vector2).y)), Vector2.ZERO)
	for q in bl["poly"]:
		hull_px = hull_px.expand(floor_px(Vector3(q.x, 0, q.y)))
	ok(m.bal.on and bl["state"] != "air" and inside and Rect2(Vector2.ZERO, vp).has_point(px) and hull_px.grow(2.0).has_point(px) and (bl["foot"] as Vector2).distance_to(Vector2(c1.x, c1.z)) < 0.001, "5 the marker's disc is drawn under the COM's ground point (px %.0f,%.0f), inside the hull's pixels and the view" % [px.x, px.y])
	# the picture: no panels (clean hides them), the camera in FRONT of the whole body, the support polygon on the floor in view
	m.clean = true
	var free := Rect2(Vector2(0, m.TOP_H), Vector2(vp.x, vp.y - m.TOP_H - m.bottom_h - m.LINE_H - 6))
	var pts: Array = [(m.B.P["head"] as Vector3) + Vector3(0, 0.14, 0)]
	for f in ["foot_l", "foot_r"]:
		pts.append(Vector3((m.B.P[f] as Vector3).x, 0.0, (m.B.P[f] as Vector3).z))
	for q in bl["poly"]:
		pts.append(Vector3(q.x, 0.0, q.y))
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var d_fit := 1.5
	while d_fit < 12.0:
		m._turn_to(0.0, -8.0, d_fit, (lo + hi) * 0.5, false)
		var all_in := true
		for q in pts:
			all_in = all_in and not m.cam.is_position_behind(q) and free.grow(-30.0).has_point(m.cam.unproject_position(q))
		if all_in:
			break
		d_fit += 0.1
	await idle(6)
	m._refresh()
	await idle(3)
	var placed := true
	for q in pts:
		placed = placed and free.has_point(m.cam.unproject_position(q))
	print("picture: camera %.1f m from the body's centre, head top at %s, feet at %s / %s, free view %s" % [d_fit, m.cam.unproject_position(pts[0]), m.cam.unproject_position(pts[1]), m.cam.unproject_position(pts[2]), free])
	ok(placed and m.cam.global_position.distance_to((lo + hi) * 0.5) > 1.2, "5b PLACEMENT: head top, both feet and every support-polygon corner are inside the free viewport, camera outside the body (%.1f m)" % d_fit)
	DirAccess.make_dir_recursive_absolute("C:/Users/Nick/.claude/jobs/9afc22db/tmp")
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i24b.png")
	m.clean = false
	m._turn_to(0.0, -22.0, 3.2, Vector3(0, 0.85, 0), false)
	await idle(3)
	m._undo()
	await idle(3)
	ok(m.B.state() == state0 and m.undo.size() == u0, "4 Ctrl+Z puts the body back bit for bit")

	# ---- 2 outside the hull: stops at the edge, red; just inside the edge: amber
	var u2: int = m.undo.size()
	var far := Vector3(c0.x + side * 0.30, 0.0, c0.z)
	var r2 := await drag(floor_px(c0), floor_px(far), false)
	var c2 := Balance.com(m.B)
	var edge_d := Balance.signed_dist(st0["poly"], Vector2(c2.x, c2.z))
	var req2: Dictionary = r2.get("req", {})
	print("outside: stopped '%s' (%s), COM %.1f mm from the edge, ring state %s, soles %.3f mm" % [r2.get("stopped", ""), r2.get("why", ""), edge_d * 1000.0, req2.get("state", ""), sole_err(s0, soles()) * 1000.0])
	ok(r2.get("stopped", "") == "edge" and absf(edge_d) <= 0.005, "2 outside the hull the solve stops at the edge (%.1f mm) and says so" % (edge_d * 1000.0))
	ok(req2.get("state", "") == "outside" and BalanceView.colour("outside") == BalanceView.RED and String(r2.get("why", "")) != "", "2 the ring is RED while held, with words")
	ok(sole_err(s0, soles()) < 0.002 and limits_ok(), "2 soles fixed < 2 mm at the edge, joints inside limits")
	await mouse(floor_px(far), false)
	await idle(2)
	ok(m.undo.size() == u2 + 1, "4 the edge drag is one undo step")
	m._undo()
	await idle(3)
	ok(m.B.state() == state0, "4 Ctrl+Z after the edge drag is exact")
	var near_edge := DragBalance.edge_point(st0["poly"], Vector2(c0.x + side * 0.3, c0.z))
	var amber_q := near_edge - Vector2(side * 0.01, 0.0)
	ok(DragBalance.state_of(st0, amber_q) == "edge" and BalanceView.colour("edge") == BalanceView.AMBER, "2 a request 1 cm inside the edge is AMBER")

	# ---- 3 drag the COM ball down 10 cm
	var u3: int = m.undo.size()
	var ball0: Vector3 = Balance.com(m.B)
	var r3 := await drag(m.cam.unproject_position(ball0), m.cam.unproject_position(ball0 - Vector3(0, 0.10, 0)))
	var c3 := Balance.com(m.B)
	var dy := c0.y - c3.y
	var knees := [float(m.B.ang["calf_l"].x), float(m.B.ang["calf_r"].x)]
	var kmin := minf(absf(knees[0]), absf(knees[1]))
	print("down 10 cm: COM dropped %.1f cm, ground point moved %.1f mm, knees %.1f / %.1f deg, soles %.3f mm, head %.2f deg" % [dy * 100.0, Vector2(c3.x - c0.x, c3.z - c0.z).length() * 1000.0, knees[0], knees[1], sole_err(s0, soles()) * 1000.0, float(r3.get("head", 0.0))])
	ok(absf(dy - 0.10) <= 0.015, "3 the COM came down 10 cm (%.1f cm)" % (dy * 100.0))
	ok(Vector2(c3.x - c0.x, c3.z - c0.z).length() <= 0.01, "3 the COM's ground point stayed within 1 cm")
	ok(kmin > 10.0, "3 both knees bend (%.1f / %.1f deg)" % [knees[0], knees[1]])
	ok(sole_err(s0, soles()) < 0.002 and limits_ok(), "3 soles fixed < 2 mm, joints inside limits")
	ok(m.undo.size() == u3 + 1, "4 the squat is one undo step")
	m._undo()
	await idle(3)
	ok(m.B.state() == state0, "4 Ctrl+Z after the squat is exact")
	print("I24: %d failures" % fails)
	quit(1 if fails > 0 else 0)
