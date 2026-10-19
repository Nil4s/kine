## godot --path . -s tests/trail_edit_test.gd     (ROADMAP 69, EDITABLE MOTION TRAILS; a window: real mouse events)
## The key dots on a pinned part's trail are handles. combo3 is opened read only.
## Bars, written before measuring:
##   1 a press on a card's key dot (9 px) takes the drag, for a limb tip (hand_l, IK route) and for a joint part (head,
##     joint route)
##   2 a 40 px drag of that dot (10 mouse steps): the part's world position at that card's time moves by the matching
##     world distance (the mouse's two points on the dot's view plane, 40 px at its depth) within 1 cm, in the same
##     direction within 1 cm; the trail's dot follows (within 1 cm of the part)
##   3 every other card's world position of that part: within 1 mm of what it was before the drag
##   4 one undo step per drag; Ctrl+Z puts the scene back bit for bit (var_to_str of to_dict)
## TRAIL_SHOT=<path.png>: a picture of the head's trail after its drag is saved there
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


## the part's world point at every card's time, read on a body of the test's own
func points(X: Body, part: String) -> Array:
	var out := []
	var ts: Array = m.S.times()
	for i in m.S.cards.size():
		m.S.apply(X, float(ts[i][1]))
		out.append(Overlays.part_point(X, part))
	return out


func run_case(part: String, card: int, dpx: Vector2) -> Dictionary:
	var X := Body.new()
	X.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	m.sel = part
	if not (part in m.ov.pins):
		m.ov.toggle_pin(part)
	m._refresh()
	await idle(3)
	var before := points(X, part)
	var st0 := var_to_str(m.S.to_dict(m.B))
	var u0: int = m.undo.size()
	var dots: Array = m.trail_edit.dots(m.S, m.ov.pins).filter(func(d): return d["part"] == part and int(d["card"]) == card)
	var d: Dictionary = dots[0]
	var q: Vector2 = m.cam.unproject_position(d["p"])
	var p0: Vector3 = d["p"]
	var n: Vector3 = m.cam.global_basis.z
	var a: Vector3 = TrailEdit.plane_hit(m.cam.project_ray_origin(q), m.cam.project_ray_normal(q), p0, n)
	await mouse(q, true)
	var took: bool = m.dragging == "trail_key"
	for k in 10:
		await move(q + dpx * (k + 1) / 10.0, dpx / 10.0)
	var end := q + dpx
	var b: Vector3 = TrailEdit.plane_hit(m.cam.project_ray_origin(end), m.cam.project_ray_normal(end), p0, n)
	await mouse(end, false)
	await idle(3)
	var after := points(X, part)
	var want: Vector3 = (b as Vector3) - (a as Vector3)
	var got: Vector3 = (after[card] as Vector3) - (before[card] as Vector3)
	var err := (got - want).length()
	var other := 0.0
	for i in before.size():
		if i != card:
			other = maxf(other, ((after[i] as Vector3) - (before[i] as Vector3)).length())
	var u1: int = m.undo.size()
	m._undo()
	await idle(2)
	var back := var_to_str(m.S.to_dict(m.B)) == st0
	return {"took": took, "want": want.length(), "got": got.length(), "err": err, "dir": got.normalized().dot(want.normalized()) if got.length() > 1e-6 else 0.0,
		"other": other, "steps": u1 - u0, "back": back}


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
	m.sel = "head"
	m.hover_part = ""
	m._refresh()
	m._turn_to(25.0, -8.0, 3.2, Vector3(0, 0.75, 0), false)
	await idle(3)
	var k := 1
	var r_head: Dictionary = await run_case("head", k, Vector2(-40, 0))
	ok(r_head["took"], "1 a press on the head's key dot (card %d) took the drag (joint route)" % (k + 1))
	var r_arm: Dictionary = await run_case("lowerarm_r", k, Vector2(-40, 0))
	ok(r_arm["took"], "1 a press on the right forearm's key dot (card %d) took the drag (joint route, elbow and shoulder chain)" % (k + 1))
	var r_hand: Dictionary = await run_case("hand_l", k, Vector2(-40, 0))
	ok(r_hand["took"], "1 a press on the left hand's key dot (card %d) took the drag (IK route)" % (k + 1))
	for nm in [["head", r_head], ["lowerarm_r", r_arm], ["hand_l", r_hand]]:
		var r: Dictionary = nm[1]
		ok(float(r["err"]) <= 0.01 and float(r["dir"]) >= 0.99 and float(r["got"]) > 0.005,
			"2 %s: 40 px drag -> %.2f cm moved at card %d, matching %.2f cm (error %.2f mm, bar 10 mm), direction cos %.4f" % [nm[0], float(r["got"]) * 100.0, k + 1, float(r["want"]) * 100.0, float(r["err"]) * 1000.0, float(r["dir"])])
		ok(float(r["other"]) <= 0.001, "3 %s: the other cards' positions moved by at most %.4f mm (bar 1 mm)" % [nm[0], float(r["other"]) * 1000.0])
		ok(int(r["steps"]) == 1 and bool(r["back"]), "4 %s: one undo step per drag (%d), Ctrl+Z back bit for bit: %s" % [nm[0], int(r["steps"]), bool(r["back"])])
	if OS.get_environment("TRAIL_SHOT") != "":
		await run_case_shot()
	print("TRAIL EDIT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


## the head's trail after a drag, for the picture: pinned on the head, its key dragged, then saved
func run_case_shot() -> void:
	m.sel = "head"
	m._refresh()
	var dots: Array = m.trail_edit.dots(m.S, m.ov.pins).filter(func(d): return d["part"] == "head" and int(d["card"]) == 1)
	var q: Vector2 = m.cam.unproject_position(dots[0]["p"])
	await mouse(q, true)
	for k in 10:
		await move(q + Vector2(-40, 0) * (k + 1) / 10.0, Vector2(-4, 0))
	await mouse(q + Vector2(-40, 0), false)
	await idle(6)
	m.get_viewport().get_texture().get_image().save_png(OS.get_environment("TRAIL_SHOT"))
	print("     shot: %s" % OS.get_environment("TRAIL_SHOT"))
	m._undo()
	await idle(2)
