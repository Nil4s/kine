## godot --path . -s tests/undo_audit_test.gd     (GATES O2, O3; needs a window: the real poser UI is built)
## EVERY command in the registry (main._commands()) is run on a loaded scene, from the same starting state each time.
##   marked "edits": if it changed the body or the scene, it pushed EXACTLY ONE undo step, and one Ctrl+Z puts the
##                   body and the whole scene (cards + settings) back to the byte.
##   not marked:     it must not change the body or the scene at all (else it is an edit nobody can undo).
## Commands that write files or open another scene (save / polish / mirror the scene / new scene) are listed as
## skipped with the reason, not passed. A marked command that changed nothing from this start is printed as VACUOUS
## and run again from a second start (no weapon, a card picked) so it is tested at least once.
## Registry checks: ids unique, every entry has a description.
extends SceneTree

const SKIP := {"undo": "is the undo", "redo": "is the redo", "save_pose": "writes poses/ (a file, not an edit)",
	"save_scene": "writes scenes/ (a file, not an edit)", "polish_the_scene_new_copy": "writes + opens a copy in scenes/_wip",
	"mirror_the_scene_left-handed_copy": "writes + opens a copy in scenes/_wip",
	"export_to_game": "writes exports/<scene>.json and .cs (a file, not an edit; round 31)",
	"export_animation_.glb": "writes exports/<scene>.glb (a file, not an edit; round 34)",
	"export_animation_.bvh": "writes exports/<scene>.bvh (a file, not an edit; round 34)",
	"save_a_version": "writes scenes/_versions/<scene>/ (a file, not an edit; round 29)",
	"new_empty_scene": "replaces the scene (the open one stays on disk); not an edit of it",
	"play_pause": "plays (the playhead moves the body by design); stopped at once below"}

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## everything an undo step must bring back: the body and the scene as it would be saved
func fp() -> String:
	# the body + what the scene IS (its cards and settings). Not S.to_dict: that POSES the body it is given (round 8:
	# the fingerprint moved with nothing done) and adds derived data (bad_frames) that re-plays the whole scene per call
	var sd := {"cards": m.S.cards, "name": m.S.name, "natural": m.S.natural, "spline": m.S.spline, "on_floor": m.S.on_floor,
		"floor_body": m.S.floor_body, "pin": m.S.pin, "fps": m.S.fps, "moving_holds": m.S.moving_holds,
		"part_keys": var_to_str(m.S.part_keys)}   # WW1
	return JSON.stringify(m.B.to_dict()) + "|" + JSON.stringify(sd)


## start A: combo3 open, card 3 picked (its pose on the body), the right forearm picked and bent off any snap step
## start B: the same with no weapon and the left hand picked (for weapon / finger commands that need another start)
## start "res://scenes/x.json": that scene, card 2 picked, the left hand picked (a command vacuous from A and B)
## start THROUGH: two clean right-arm poses whose straight in-between goes through the body (for "Fix moves through
##   the body"; found by a seeded random search over legal arm poses: my hand-made swing first went round the body)
func start(kind: String) -> void:
	m.playing = false
	if kind == "THROUGH":
		m.S = Scene.new()
		m._bat_remove()
		m._reset_all()
		m.B.set_ang_safe("upperarm_r", Vector3(69.90392, -57.37397, 40.73733))
		m.B.set_ang_safe("lowerarm_r", Vector3(130.7078, 0, 0))
		m.S.add("a", m.B.to_dict())
		m._reset_all()
		m.B.set_ang_safe("upperarm_r", Vector3(50.63533, -5.133659, -66.1005))
		m.B.set_ang_safe("lowerarm_r", Vector3(89.3162, 0, 0))
		m.S.add("b", m.B.to_dict())
		m.S.cards[1]["move"] = 0.4
		m._rebuild_cards()
		m._card_pick(0)
	elif kind.begins_with("res://"):
		m._load_scene(kind)
		m._rebuild_cards()
		m._card_pick(mini(1, m.S.cards.size() - 1))
		m.sel = "hand_l"
	else:
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(2)
		if kind == "B":
			m._do(m._bat_remove)
			m.sel = "hand_l"
		else:
			m.sel = "lowerarm_r"
			m.B.set_ang_safe("lowerarm_r", m.B.ang["lowerarm_r"] + Vector3(17.3333, 0, 0))   # off the files' 0.01-deg grid: a lossy keep/restore shows
	m._refresh()
	m.undo.clear()
	m.redo.clear()
	await process_frame


## where two fingerprints first differ (printed under a failure, so the failure says WHAT did not come back)
func where(a: String, b: String) -> String:
	var i := 0
	while i < mini(a.length(), b.length()) and a[i] == b[i]:
		i += 1
	return "     first difference at char %d: ...%s...  vs  ...%s..." % [i, a.substr(maxi(0, i - 60), 90), b.substr(maxi(0, i - 60), 90)]


## run one command from a start; returns "changed" / "same" and records the failures
func trial(c: Dictionary, kind: String) -> String:
	await start(kind)
	var f0 := fp()
	var u0: int = m.undo.size()
	(c["run"] as Callable).call()
	await process_frame
	await process_frame
	m.playing = false
	var f1 := fp()
	var steps: int = m.undo.size() - u0
	if f1 == f0:
		if not c["edits"]:
			ok(steps == 0, "%-38s not an edit: changed nothing, %d undo steps" % [c["id"], steps])
		return "same"
	if not c["edits"]:
		ok(false, "%-38s NOT marked edits but CHANGED the body/scene (%d undo steps)" % [c["id"], steps])
		return "changed"
	m._undo()
	await process_frame
	var f2 := fp()
	var back := f2 == f0
	if not back:
		print(where(f0, f2))
	ok(steps == 1 and back, "%-38s [%s] %d undo step(s); one Ctrl+Z puts it back exactly: %s" % [c["id"], kind, steps, back])
	return "changed"


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var cmds: Array = m._commands()
	var ids := {}
	var nodesc := []
	for c in cmds:
		ids[c["id"]] = ids.get(c["id"], 0) + 1
		if String(c.get("desc", "")).strip_edges() == "":
			nodesc.append(c["id"])
	ok(ids.size() == cmds.size(), "registry: %d commands, %d unique ids" % [cmds.size(), ids.size()])
	ok(nodesc.is_empty(), "registry: every command has a one-line description %s" % ("" if nodesc.is_empty() else str(nodesc)))
	# CONTROL: the fingerprint holds still with no command (the first version posed the body while reading the
	# scene, and every command, the camera views too, read as a change)
	await start("A")
	var still := fp()
	await process_frame
	await process_frame
	ok(fp() == still, "control: with no command the body + scene fingerprint does not move over 2 frames")
	var more := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json") and f != "combo3.json":
			more.append("res://scenes/" + f)
	var n_edit := 0
	var tested := 0
	var vacuous := []
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	for c in cmds:
		if only != "" and c["id"] != only:
			continue
		if SKIP.has(c["id"]):
			print("skip %-38s %s" % [c["id"], SKIP[c["id"]]])
			continue
		if c["edits"]:
			n_edit += 1
		var r := await trial(c, "A")
		if r == "same" and c["edits"]:
			for k in ["B", "THROUGH"] + more:
				r = await trial(c, k)
				if r != "same":
					break
			if r == "same":
				vacuous.append(c["id"])
				print("VACUOUS %s: changed nothing from either start" % c["id"])
				continue
		if c["edits"]:
			tested += 1
	ok(vacuous.is_empty(), "every edit command was seen to change something (%d of %d tested; vacuous: %s)" % [tested, n_edit, vacuous])
	# a pass that keeps the live body aside and puts it back (Fix moves through the body; Save / Polish / Mirror do
	# the same) must put it back EXACTLY: it went through the rounded file format before round 8
	await start("A")
	var kb := JSON.stringify(m.B.state())
	m._clear_scene()
	await process_frame
	ok(JSON.stringify(m.B.state()) == kb and m.undo.is_empty(), "a pass that adds nothing (combo3 is clear) leaves the live body bit-exact and no undo step")
	# the card row's own buttons (not in the registry: they take a card): add / update / delete / move / retime
	await start("A")
	var f0 := fp()
	m.B.set_ang_safe("head", Vector3(20, 10, 0))
	for step in [func(): m._card_update(4), func(): m._card_del(5), func(): m._card_move(1, 1), func(): m._card_add()]:
		var f := fp()
		var u0: int = m.undo.size()
		step.call()
		await process_frame
		var changed := fp() != f
		m._undo()
		await process_frame
		ok(changed and m.undo.size() == u0 and fp() == f, "card button: changed %s, one Ctrl+Z puts it back exactly: %s" % [changed, fp() == f])
	print("UNDO AUDIT %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
