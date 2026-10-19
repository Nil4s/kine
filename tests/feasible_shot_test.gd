## godot --path . -s tests/feasible_shot_test.gd   (window) "Is this clip physically possible?" in the Check panel.
## Bars (before measuring): a clip leaning ~15 cm out over one foot gives the verdict FIX in the panel (a FEASIBLE finding and the
## verdict line); clicking it moves the playhead to a frame inside the lean; PLACEMENT: at that frame the COM point and the whole
## support polygon (BalanceView) project inside the 3D view, the COM's floor point is outside the polygon, and the head is above
## the feet on screen. Shot: C:/Users/Nick/.claude/jobs/9afc22db/tmp/feasible.png
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
	var B: Body = m.B
	var rest := B.to_dict()
	B.set_ang("thigh_l", Vector3(80, 0, 0))
	B.set_ang("calf_l", Vector3(100, 0, 0))
	B.offset = Vector3(0.16, 0, 0)
	B.fk()
	var lean := B.to_dict()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	m.S.from_dict({"scene": "zz_feasible", "fps": 30, "cards": [{"name": "stand", "pose": rest, "move": -1.0, "hold": 0.3},
		{"name": "lean out", "pose": lean, "move": 0.3, "hold": 0.5, "plant": ["_r"]}, {"name": "back", "pose": rest, "move": 0.3, "hold": 0.2}]})
	m._rebuild_cards()
	m._feasible_check()
	await idle(3)
	var vf: Array = m.findings.filter(func(f): return f["rule"] == "FEASIBLE")
	ok(vf.size() == 1 and String(vf[0]["msg"]).begins_with("FIX"), "1 the panel's verdict is FIX: %s" % (String(vf[0]["msg"]).left(120) if vf.size() > 0 else "none"))
	var vl = m.ui_find_list.find_child("verdict", true, false)
	ok(vl != null and "FIX" in (vl as Label).text, "2 the verdict line shows FIX: %s" % ((vl as Label).text if vl != null else "none"))
	if vf.size() > 0:
		m._goto_finding(vf[0])
	await idle(3)
	var t: float = m.playhead
	var tl: Array = m.S.times()
	ok(t >= float(tl[1][0]) and t <= float(tl[1][2]) + 0.05, "3 the click jumped to t=%.2f s, inside the lean [%.2f, %.2f]" % [t, tl[1][0], tl[1][2]])
	m.S.apply(m.B, tl[1][2] - 0.02)
	m.playhead = tl[1][2] - 0.02
	m.bal.on = true
	m._turn_to(25.0, -8.0, 4.4, Vector3(0, 0.9, 0), false)
	m._refresh()
	await idle(6)
	m._refresh()
	await idle(4)
	var r := Balance.read(m.B)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var vr := root.get_visible_rect()
	var c: Vector3 = r["com"]
	var pc := cam.unproject_position(Vector3(c.x, 0.0, c.z))
	var ph := cam.unproject_position(m.B.P["head"])
	var pf := cam.unproject_position(m.B.P["foot_r"])
	var poly: PackedVector2Array = r["poly"]
	var all_in := poly.size() >= 3
	for v in poly:
		all_in = all_in and vr.has_point(cam.unproject_position(Vector3(v.x, 0.0, v.y)))
	ok(vr.has_point(pc) and all_in and vr.has_point(ph), "4 PLACEMENT: COM floor point %s, head %s, all %d polygon points on screen" % [pc, ph, poly.size()])
	ok(float(r["margin"]) < -0.10 and ph.y < pf.y, "5 COM %.0f cm outside the polygon, head above the foot on screen" % (-float(r["margin"]) * 100.0))
	DirAccess.make_dir_recursive_absolute("C:/Users/Nick/.claude/jobs/9afc22db/tmp")
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/feasible.png")
	print("FEASIBLE SHOT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
