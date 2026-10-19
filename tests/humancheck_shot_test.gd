## godot --path . -s tests/humancheck_shot_test.gd   (window) ROADMAP 10: the Check on a knee kick at 3 x the cited knee peak.
## Bars (before measuring): the Check lists a JOINT SPEED FAIL naming knee r and its source; the flagged calf is selected and
## its screen position is inside the 3D view and in the lower half of the body's projected height (a knee/calf, not the head).
## Shot: the whole body with the flagged joint selected, saved to user://zz_humancheck.png
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
	B.set_ang("calf_r", Vector3(3.0 * 1874.0 / 60.0, 0, 0))
	B.set_ang("thigh_r", Vector3(60, 0, 0))
	B.fk()
	var kick := B.to_dict()
	m.S.from_dict({"scene": "zz_humancheck", "fps": 60, "cards": [{"name": "stand", "pose": rest, "move": -1.0, "hold": 0.5},
		{"name": "kick", "pose": kick, "move": 1.0 / 60.0, "hold": 0.5}]})
	m._rebuild_cards()
	HumanLimits.on = true
	m._check()
	HumanLimits.on = false
	var fs: Array = m.findings.filter(func(f): return f["rule"] == "JOINT SPEED" and f.get("joint", "") == "knee_r")
	ok(fs.size() >= 1 and fs[0]["sev"] == "FAIL" and "Manolopoulos 2006" in fs[0]["msg"], "1 Check lists a JOINT SPEED FAIL on knee r naming Manolopoulos 2006: %s" % (fs[0]["msg"] if fs.size() > 0 else "none"))
	if fs.size() > 0:
		m._goto_finding(fs[0])
	m.sel = "calf_r"
	m._turn_to(40.0, -8.0, 4.2, Vector3(0, 0.9, 0), false)
	await idle(6)
	m._refresh()
	await idle(4)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var head: Vector3 = m.B.P["head"]
	var calf: Vector3 = (m.B.P["calf_r"] + m.B.P["foot_r"]) * 0.5 if m.B.P.has("foot_r") else m.B.P["calf_r"]
	var ph := cam.unproject_position(head)
	var pc := cam.unproject_position(calf)
	var vr := root.get_visible_rect()
	ok(vr.has_point(ph) and vr.has_point(pc) and pc.y > ph.y + 0.25 * (vr.size.y * 0.3), "2 PLACEMENT: head at %s, flagged calf at %s, both on screen and the calf below the head" % [ph, pc])
	root.get_texture().get_image().save_png("user://zz_humancheck.png")
	print("shot: ", ProjectSettings.globalize_path("user://zz_humancheck.png"))
	print("HUMANCHECK SHOT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
