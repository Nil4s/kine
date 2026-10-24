## The user story: bend an arm WITHOUT keying it, run a read-only check, and the bent arm is still there.
## The three read-only checks (silhouette sheet, will this deform?, twinning) must not discard an unkeyed pose.
## Each check runs from the same start; after it returns and two frames pass, the body (B.to_dict) and the bent
## forearm's angle must be exactly what they were before the check.
## godot --path . -s tests/readpose_test.gd     (needs a window: the real poser UI is built)
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var cmds: Array = m._commands()
	var checks := {}
	for c in cmds:
		for pre in ["Check: silhouette sheet", "Check: will this deform?", "Check: twinning"]:
			if String(c["name"]).begins_with(pre):
				checks[pre] = c
	ok(checks.size() == 3, "the three read-only checks are in the registry (%d found)" % checks.size())
	for pre in ["Check: silhouette sheet", "Check: will this deform?", "Check: twinning"]:
		if not checks.has(pre):
			continue
		# a fresh start for each check: combo3, card 3 picked, the right forearm bent WITHOUT a key
		m.playing = false
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(2)
		m.sel = "lowerarm_r"
		m.B.set_ang_safe("lowerarm_r", Vector3(90, 0, 0))
		m.B.fk()
		var bent: Vector3 = m.B.ang["lowerarm_r"]
		var before := JSON.stringify(m.B.to_dict())
		var u0: int = m.undo.size()
		(checks[pre]["run"] as Callable).call()
		await process_frame
		await process_frame
		var after := JSON.stringify(m.B.to_dict())
		ok(after == before, "%-28s the body is unchanged after the check" % pre)
		ok(m.B.ang["lowerarm_r"].distance_to(bent) < 0.01, "%-28s the unkeyed bend is still there (lowerarm_r %s)" % [pre, m.B.ang["lowerarm_r"]])
		ok(m.undo.size() == u0, "%-28s a read-only check pushes no undo step" % pre)
	print("READPOSE %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
