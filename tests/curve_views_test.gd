## godot --path . -s tests/curve_views_test.gd     (round 48, GATES DD3, UPGRADES_300 #249; a window: real mouse events)
## NORMALIZED AND STACKED VIEWS in the curve editor (Maya's Graph Editor). Keys on the right forearm: bend 10 -> 70 -> 30,
## side -2 -> 4 -> 1, twist 0 -> 0.6 -> 0.2 (three very different ranges: 60, 6 and 0.6 deg).
##   1 NORMAL: every angle's drawn line spans the same rows: each angle's top and bottom within 1 px of the shared +1 / -1
##     rows (in degrees the twist would be a flat line on the bend's scale: its height in the plain view is reported)
##   2 STACKED: every point of angle c's line lies inside lane c; the three lanes are disjoint, in order X / Y / Z
##   3 in both, the drawn line maps back to PartKeys.value_at within 1 px worth of that angle's degrees
##   4 a REAL drag of the twist key 40 px up in the normal view changes the twist by 40 px of the TWIST's scale (not the
##     bend's), within 1.5 px, and nothing else; one undo step; Ctrl+Z exact
##   5 the same for the side key in the stacked view
##   6 the View button (real clicks) cycles degrees -> -1..1 -> lanes -> degrees; back in degrees the dots are where they
##     were before (the plain view untouched)
extends SceneTree

var fails := 0
var m: Node
var ce: CurveEditor


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, motion := false, held := false) -> void:
	var e: InputEvent
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		if down:
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mb
	root.push_input(e)
	await process_frame


func drag(a: Vector2, b: Vector2) -> void:
	await mouse(a, true)
	for i in range(1, 6):
		await mouse(a.lerp(b, float(i) / 5.0), false, true, true)
	await mouse(b, false)
	await idle(2)


func gp(local: Vector2) -> Vector2:
	return ce.get_global_rect().position + local


func ks() -> Array:
	return m.S.part_keys["lowerarm_r"]


func extent(c: int) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in ce.polyline(c):
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return Vector2(lo, hi)


func back_err(c: int) -> float:
	var w := 0.0
	for p in ce.polyline(c):
		var deg_px: float = absf(ce.cy_to_v(c, 0.0) - ce.cy_to_v(c, 1.0))
		w = maxf(w, absf(ce.cy_to_v(c, p.y) - PartKeys.value_at(ks(), ce.x_to_t(p.x))[c]) / maxf(deg_px, 1e-9))
	return w


## drag key 1's angle c by dy px; [the change of every angle, the expected change of c, deg per px of c, undo steps]
func drag_key(c: int, dy: float) -> Array:
	var v0: Vector3 = ks()[1]["v"]
	var t0: float = ks()[1]["t"]
	var deg_px: float = absf(ce.cy_to_v(c, 0.0) - ce.cy_to_v(c, 1.0))
	var u0: int = m.undo.size()
	var from := gp(ce.key_pos(c, 1))
	await drag(from, from + Vector2(0, -dy))
	var d: Vector3 = (ks()[1]["v"] as Vector3) - v0
	return [d, dy * deg_px, deg_px, m.undo.size() - u0, float(ks()[1]["t"]) - t0]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B0 := Body.new()
	B0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B0.fk()
	var S := Scene.new()
	S.name = "zz_curve_views"
	S.add("a", B0.to_dict())
	S.add("b", B0.to_dict())
	S.cards[1]["move"] = 1.0
	S.part_keys = {"lowerarm_r": [{"t": 0.0, "v": Vector3(10, -2, 0)}, {"t": 0.5, "v": Vector3(70, 4, 0.6)}, {"t": 1.0, "v": Vector3(30, 1, 0.2)}]}
	m.S = S
	m._rebuild_cards()
	m.sel = "lowerarm_r"
	m._refresh()
	await idle(2)
	for c in m._commands():
		if c["id"] == "curve_editor":
			c["run"].call()
	await idle(3)
	ce = m.ui_curve
	ce.limit = Callable()   # small made-up angles: keep the forearm's own limits out of the way
	ce.frame_all()
	await idle(2)
	var plain_dots := []
	for c in 3:
		plain_dots.append(ce.key_pos(c, 1))
	var plain_twist_h := extent(2).y - extent(2).x
	var before := JSON.stringify(PartKeys.to_file(S.part_keys))
	# 6 (part 1) the button, real clicks
	await mouse(ce._view_btn.get_global_rect().get_center(), true)
	await mouse(ce._view_btn.get_global_rect().get_center(), false)
	await idle(3)
	var v1: String = ce.view
	# 1 normal
	var top := ce.cv_to_y(0, ce._rng[0].y)
	var bot := ce.cv_to_y(0, ce._rng[0].x)
	var worst1 := 0.0
	var ext := []
	for c in 3:
		var e := extent(c)
		ext.append(e)
		worst1 = maxf(worst1, maxf(absf(e.x - top), absf(e.y - bot)))
	ok(v1 == "normal" and worst1 <= 1.0, "1 normal view (after one click on '%s'): each angle's line from row %s; the shared +1 / -1 rows %.1f / %.1f: worst %.3f px (bar 1); in degrees the twist was %.2f px tall" % [ce.VIEW_NAMES["plain"], ext, top, bot, worst1, plain_twist_h])
	var b3n := [back_err(0), back_err(1), back_err(2)]
	# 4 drag twist in normal
	var r4: Array = await drag_key(2, 40.0)
	var d4: Vector3 = r4[0]
	var e4 := absf(d4.z - float(r4[1])) / float(r4[2])
	ok(e4 <= 1.5 and d4.x == 0.0 and d4.y == 0.0 and absf(float(r4[4])) < 1e-6 and r4[3] == 1,
		"4 normal view: the twist key dragged 40 px up -> twist %+.4f deg (want %+.4f = 40 px x %.4f deg/px of the TWIST; error %.2f px, bar 1.5); bend %+.3f, side %+.3f, time %+.4f; undo steps %d" % [d4.z, r4[1], r4[2], e4, d4.x, d4.y, r4[4], r4[3]])
	m._undo()
	await idle(2)
	ok(absf((ks()[1]["v"] as Vector3).z - 0.6) < 1e-6, "  Ctrl+Z: the twist back to %.4f" % (ks()[1]["v"] as Vector3).z)
	# stacked
	await mouse(ce._view_btn.get_global_rect().get_center(), true)
	await mouse(ce._view_btn.get_global_rect().get_center(), false)
	await idle(3)
	var v2: String = ce.view
	var inside := true
	for c in 3:
		var r := ce.lane(c)
		for p in ce.polyline(c):
			inside = inside and p.y >= r.position.y - 0.01 and p.y <= r.end.y + 0.01
	var lanes_ok := ce.lane(0).end.y < ce.lane(1).position.y and ce.lane(1).end.y < ce.lane(2).position.y
	ok(v2 == "stacked" and inside and lanes_ok, "2 stacked view: every point of each angle's line inside its own lane %s; lanes %s / %s / %s disjoint and in order %s" % [inside, ce.lane(0), ce.lane(1), ce.lane(2), lanes_ok])
	var b3s := [back_err(0), back_err(1), back_err(2)]
	ok((b3n + b3s).max() <= 1.0, "3 the drawn lines map back to value_at: normal %s, stacked %s px (bar 1)" % [b3n.map(func(x): return snappedf(x, 0.001)), b3s.map(func(x): return snappedf(x, 0.001))])
	# 5 drag side in stacked
	var r5: Array = await drag_key(1, 30.0)
	var d5: Vector3 = r5[0]
	var e5 := absf(d5.y - float(r5[1])) / float(r5[2])
	ok(e5 <= 1.5 and d5.x == 0.0 and d5.z == 0.0 and r5[3] == 1, "5 stacked view: the side key dragged 30 px up -> side %+.4f deg (want %+.4f, %.4f deg/px of the SIDE; error %.2f px); bend %+.3f, twist %+.3f; undo steps %d" % [d5.y, r5[1], r5[2], e5, d5.x, d5.z, r5[3]])
	m._undo()
	await idle(2)
	# 6 back to degrees
	await mouse(ce._view_btn.get_global_rect().get_center(), true)
	await mouse(ce._view_btn.get_global_rect().get_center(), false)
	await idle(3)
	var same := true
	for c in 3:
		same = same and ce.key_pos(c, 1).distance_to(plain_dots[c]) < 0.01
	ok(ce.view == "plain" and same and JSON.stringify(PartKeys.to_file(S.part_keys)) == before, "6 three clicks: %s -> %s -> %s; back in degrees every dot where it was (%s); keys as before" % [v1, v2, ce.view, same])
	m.queue_free()
	print("CURVE VIEWS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
