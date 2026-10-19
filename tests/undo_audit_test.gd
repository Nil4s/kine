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
	"export_animation_.usda": "writes exports/<scene>.usda (a file, not an edit; round 42)",
	"export_playblast_video": "writes exports/playblast/ frame by frame over many frames (a file, not an edit; round 50 PL0: its own test checks the app is back after)",
	"save_a_version": "writes scenes/_versions/<scene>/ (a file, not an edit; round 29)",
	"new_empty_scene": "replaces the scene (the open one stays on disk); not an edit of it",
	"look_at_the_picked_prop": "needs a picked prop (no start picks one); the same _look_at path is audited by look_at_the_camera and its solve by look_at_test",
	"play_pause": "plays (the playhead moves the body by design); stopped at once below",
	"audio_add_a_sound_file_wav_ogg_mp3": "opens a file dialog (audio_track_test runs the add itself: one undo step)",
	"import_animation_fbx_glb_gltf_bvh_...": "opens a file dialog; the import writes + opens a NEW scene in scenes/_wip (anim_import_test runs it)"}

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
		"part_keys": var_to_str(m.S.part_keys), "markers": m.S.markers,   # WW1, WW5
		"breath": m.S.breath, "layer": var_to_str(m.S.layer), "layer_w": m.S.layer_w,   # YY6, YY9
		"layers": var_to_str(m.S.layers),   # NA1
		"audio": var_to_str(m.S.audio),   # the sound on the timeline
		"ik": var_to_str(m.S.ik),   # IK keys (limb_ik.gd)
		"cons": var_to_str(m.S.cons),   # constraints (round 51)
		"props": JSON.stringify(m.S.props.map(func(q): return Props.to_dict(q))),   # the set: keys, a door's swing (row 22)
		"camera": var_to_str(m.S.camera),   # the shot camera (shot_camera.gd)
		"sets": var_to_str(m.S.sets),   # selection / keying sets (part_sets.gd)
		"actors": m.S.actors.map(func(a): return [a["name"], a["xf"], (a["scene"] as Scene).cards]),   # TC3: the second fighter
		"body": var_to_str(m.S.body), "p0": var_to_str(m.B.p0)}   # PR1: the proportions and the skeleton they make
	return JSON.stringify(m.B.to_dict()) + "|" + JSON.stringify(sd)


## start A: combo3 open, card 3 picked (its pose on the body), the right forearm picked and bent off any snap step
## start B: the same with no weapon and the left hand picked (for weapon / finger commands that need another start)
## start "res://scenes/x.json": that scene, card 2 picked, the left hand picked (a command vacuous from A and B)
## start LAYER: combo3 0.13 s before card 3 arrives, with a layer (spine_03 +5 at weight 0.5): for Block and the layer commands
## start STEPPED: the same, already blocking (the stepped view on): for "Spline and check"
## start IK: combo3 on card 3 with the left hand pinned at card 1 (for IK release and the two snaps)
## start CONS: combo3 on card 3, the left hand held to the right hand and the head on the weapon (round 51 constraints)
## start CAMERA: combo3 on card 3 with two shot-camera keys, one under the playhead (lens / remove the key here)
## start BODY: combo3 on the 5th-percentile woman's proportions (PR1: for the command back to the mannequin's own)
## start ACTORS: combo3 with a second fighter added, switched to it (TC3: for "Actor: remove this fighter")
## start THROUGH: two clean right-arm poses whose straight in-between goes through the body (for "Fix moves through
##   the body"; found by a seeded random search over legal arm poses: my hand-made swing first went round the body)
func start(kind: String) -> void:
	m.playing = false
	m.stepped_view = false   # a VIEW (never undone): a Block trial left it on, and every later start then began blocking
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
	elif kind == "SLIDE":
		# YY2: a stand whose whole body creeps 15 cm over 2 s, so "Plant every sliding foot" has slides to plant
		m.S = Scene.new()
		m._reset_all()
		m.S.add("stand", m.B.to_dict())
		m.B.offset.z += 0.15
		m.B.fk()
		m.S.add("crept", m.B.to_dict())
		m.S.cards[1]["move"] = 2.0
		m.S.cards[1]["hold"] = 0.5
		m._rebuild_cards()
		m._card_pick(0)
	elif kind.begins_with("KEYS"):
		# XX1: the right forearm has two part keys, the first under the playhead, set so that every interpolation / handle /
		# infinity command has a different value to change to from one of the two starts (KEYS_A or KEYS_B)
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(2)
		m.sel = "lowerarm_r"
		PartKeys.put(m.S.part_keys, "lowerarm_r", m.playhead, Vector3(20, 0, 0))
		PartKeys.put(m.S.part_keys, "lowerarm_r", m.playhead + 0.5, Vector3(60, 0, 0))
		if kind == "KEYS_A":
			PartKeys.set_interp(m.S.part_keys, "lowerarm_r", 0, "constant")
			PartKeys.set_handle_type(m.S.part_keys, "lowerarm_r", 0, "auto")
			PartKeys.set_inf(m.S.part_keys, "lowerarm_r", "cycle")
		else:
			PartKeys.set_interp(m.S.part_keys, "lowerarm_r", 0, "linear")
			PartKeys.set_handle_type(m.S.part_keys, "lowerarm_r", 0, "free")
			PartKeys.set_inf(m.S.part_keys, "lowerarm_r", "linear")
	elif kind == "LAYER" or kind == "STEPPED":
		# YY8 / YY9: combo3 between two cards (so the stepped hold differs from the in-between) with a small layer on
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(2)
		m.S.layer = {"spine_03": Vector3(5, 0, 0)}
		m.S.layer_w = 0.5
		m.S.layers = [{"name": "Layer 2", "mode": "over", "w": 0.5, "wk": [], "mute": false, "solo": false, "lock": false, "v": {"head": Vector3(10, 0, 0)}}]   # NA1
		m.layer_on = 0
		m.playhead = float(m.S.times()[2][1]) - 0.13
		m.stepped_view = kind == "STEPPED"   # STEPPED: already blocking, for "Spline and check"
		m._ps().apply(m.B, m.playhead)
		m.sel = "lowerarm_r"
	elif kind == "AUDIO":
		# the sound commands need a sound on the timeline (a path with no file: the scene still holds it and the commands edit it)
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(2)
		m.S.audio = {"path": "res://zz_no_such_sound.wav", "offset": 0.3, "gain_db": 0.0}
		m.sel = "lowerarm_r"
	elif kind == "IK":
		# IK: combo3 on card 3 (its arrival under the playhead) with the left hand pinned at card 1, so release and the
		# two snaps have something to change
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(0)
		m.S.apply(m.B, m.playhead)
		LimbIK.pin(m.S, m.B, "hand_l", m.playhead)
		m._card_pick(2)
		m.S.apply(m.B, m.playhead)
		m.sel = "hand_l"
	elif kind.begins_with("CONS"):
		# round 51: combo3 on card 3 with the left hand held to the right hand from card 1 and the head looking at the
		# weapon, the left hand picked (fade / release / remove need a constraint)
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(0)
		m.S.apply(m.B, m.playhead)
		Constraints.add_child_of(m.S, m.B, "hand_l", {"kind": "part", "part": "hand_r"}, m.playhead)
		Constraints.add_track_to(m.S, m.B, {"kind": "weapon"}, m.playhead)
		m._card_pick(2)
		m.S.apply(m.B, m.playhead)
		m.sel = "foot_l" if kind == "CONS_FOOT" else "hand_l"   # CONS_FOOT: a foot picked (the floor constraint)
	elif kind == "CAMERA":
		# the shot camera: combo3 on card 3 with two camera keys, one under the playhead (for its lens / remove commands)
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(2)
		ShotCam.put(m.S.camera, {"t": m.playhead, "pos": Vector3(2.5, 1.4, 3.0), "aim": Vector3(0, 1, 0), "f": 40.0})
		ShotCam.put(m.S.camera, {"t": 0.0, "pos": Vector3(-2.5, 1.2, 3.0), "aim": Vector3(0, 0.9, 0), "f": 35.0})
	elif kind.begins_with("SETS"):
		# selection / keying sets (part_sets.gd): a selection set "arm_l", a keying set "swing" (active in SETS_B); SETS picks
		# the keying set with a member selected (remove / delete / mirror / use for K), SETS_B the selection set with a
		# part outside it selected (add) and "swing" active (none)
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(2)
		m.S.sets = {"select": {"arm_l": ["upperarm_l", "lowerarm_l", "hand_l"]}, "keying": {"swing": ["upperarm_r", "lowerarm_r", "hand_r"]}}
		m.sel = "lowerarm_r"
		m.sel_more = []
		PartSets.of(m).cur = {"kind": "keying", "name": "swing"}
		if kind == "SETS_B":
			m.S.sets["active"] = "swing"
			PartSets.of(m).cur = {"kind": "select", "name": "arm_l"}
	elif kind == "PROPS":   # row 22: a keyed door picked, the playhead between its keys (Prop / Door commands)
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		var dr := Props.make("door", Props.xf_at(Vector3(1.2, 0.0, 0.8), 0.0))
		Props.key_at(dr, 0.0, dr["xf"], 0.0)
		Props.key_at(dr, 1.0, dr["xf"], 30.0)
		m.S.props = [dr]
		m.sel_prop = 0
		m.playhead = 0.5
		m._props_show()
	elif kind == "BODY":   # PR1: a scene on a 5th-percentile woman (for "Body: the mannequin's own proportions")
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m.proportions_set(Proportions.preset("female_5"))
		m._card_pick(2)
		m.sel = "lowerarm_r"
	elif kind == "ACTORS":
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._actor_add()
		m._actor_next()
		m._card_pick(2)
		m.sel = "lowerarm_r"
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
	Markers.add(m.S.markers, m.playhead, "zz")   # WW5: a marker under the playhead, so Delete marker has something to delete
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
			for k in ["B", "THROUGH", "KEYS_A", "KEYS_B", "SLIDE", "LAYER", "STEPPED", "IK", "CONS", "CONS_FOOT", "ACTORS", "AUDIO", "CAMERA", "BODY", "SETS", "SETS_B"] + more:
			for k in ["B", "THROUGH", "KEYS_A", "KEYS_B", "SLIDE", "LAYER", "STEPPED", "IK", "CONS", "CONS_FOOT", "ACTORS", "AUDIO", "CAMERA", "BODY", "PROPS"] + more:
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
