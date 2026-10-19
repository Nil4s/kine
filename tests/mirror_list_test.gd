## godot --headless --path . -s tests/mirror_list_test.gd     (GATES Z1, UPGRADES #3)
## MIRROR'S LIST: every key the scene files hold and to_dict writes (with every optional field on) is on
## Scene.MIRROR_SCENE / MIRROR_CARD - a key not on it fails here, so whoever adds one must decide its side. Then Mirror
## the scene (the window's own command) on combo3 with a planted foot, a step, an ease, a lift, a flow card, loop and
## moving holds: the planted "_l" plants "_r", the step changes side with its x negated, every side-free field is
## byte-identical, the file's bad_frames are the mirrored motion's own; mirrored twice, the scene comes back.
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


func read(p: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(p))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1

	# the scene under test: every optional field on
	m._load_scene("res://scenes/combo3.json")
	m.S.name = "_wip/zz_z1"
	m.S.cards[2]["plant"] = ["_l"]
	m.S.cards[3]["steps"] = {"_l": [0.12, 0.0, 0.2]}
	m.S.cards[3]["lift"] = 0.07
	m.S.cards[4]["ease"] = "in"
	m.S.cards[5]["flow"] = true
	m.S.moving_holds = true
	m.S.loop = true
	m._rebuild_cards()
	m.S.apply(m.B, float(m.S.times()[2][1]))
	LimbIK.pin(m.S, m.B, "hand_l", float(m.S.times()[2][1]))   # IK keys (limb_ik.gd): the left hand pinned at card 3
	var keep: Dictionary = m.B.state()
	var orig: Dictionary = JSON.parse_string(JSON.stringify(m.S.to_dict(m.B)))
	m.B.set_state(keep)

	# 1 every key on the list
	var sk := {}
	var ck := {}
	var files := Array(DirAccess.get_files_at("res://scenes")).map(func(f): return "res://scenes/" + f) + Array(DirAccess.get_files_at("res://scenes/_wip")).map(func(f): return "res://scenes/_wip/" + f)
	for p in files.filter(func(f): return f.ends_with(".json")) + ["<to_dict>"]:
		var d: Dictionary = orig if p == "<to_dict>" else read(p)
		for k in d:
			sk[k] = true
		for c in d.get("cards", []):
			for k in c:
				ck[k] = true
	var off := sk.keys().filter(func(k): return not Scene.MIRROR_SCENE.has(k)) + ck.keys().filter(func(k): return not Scene.MIRROR_CARD.has(k))
	ok(off.is_empty() and ck.has("plant") and ck.has("steps") and sk.has("loop") and sk.has("ik"),
		"1 every key written is on mirror's list: %d scene keys, %d card keys over %d files and to_dict (off the list: %s)" % [sk.size(), ck.size(), files.size(), off])

	# mirror through the window's command
	m._mirror_scene()
	await idle()
	var mp := "res://scenes/_wip/zz_z1_mirrored.json"
	var mir := read(mp)
	ok(mir["cards"][2].get("plant", []) == ["_r"], "2 the card that planted the left foot plants the right (%s)" % [mir["cards"][2].get("plant", [])])
	var st: Dictionary = mir["cards"][3].get("steps", {})
	ok(st.keys() == ["_r"] and absf(float(st["_r"][0]) + 0.12) < 1e-6 and absf(float(st["_r"][2]) - 0.2) < 1e-6, "3 the left step is the right step, its sideways x negated (%s; to_dict keeps steps as float32)" % [st])
	var diff := []
	for k in Scene.MIRROR_SCENE:
		if Scene.MIRROR_SCENE[k] == "free" and JSON.stringify(orig.get(k)) != JSON.stringify(mir.get(k)):
			diff.append([k, orig.get(k), mir.get(k)])
	for i in orig["cards"].size():
		for k in Scene.MIRROR_CARD:
			if Scene.MIRROR_CARD[k] == "free" and JSON.stringify(orig["cards"][i].get(k)) != JSON.stringify(mir["cards"][i].get(k)):
				diff.append([i + 1, k, orig["cards"][i].get(k), mir["cards"][i].get(k)])
	var oik: Array = orig["ik"]["hand_l"]
	var mik: Array = mir.get("ik", {}).get("hand_r", [])
	var ik_ok: bool = mir.get("ik", {}).keys() == ["hand_r"] and mik.size() == oik.size()
	for i in mini(oik.size(), mik.size()):
		for f in ["target", "pole"]:
			ik_ok = ik_ok and absf(float(mik[i][f][0]) + float(oik[i][f][0])) < 1e-6 and absf(float(mik[i][f][1]) - float(oik[i][f][1])) < 1e-6 and absf(float(mik[i][f][2]) - float(oik[i][f][2])) < 1e-6
		ik_ok = ik_ok and float(mik[i]["t"]) == float(oik[i]["t"]) and float(mik[i]["w"]) == float(oik[i]["w"])
	ok(ik_ok, "4b the IK keys: the left hand's %d keys are the right hand's, target and pole x negated, times and weights as they were (%s)" % [oik.size(), mir.get("ik", {}).keys()])
	ok(diff.is_empty(), "4 every side-free field byte-identical, the scene's and each of %d cards' (differ: %s)" % [orig["cards"].size(), diff])
	var S2 := Scene.new()
	S2.from_dict(mir)
	var B2 := Body.new()
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var fresh: Dictionary = JSON.parse_string(JSON.stringify(S2.to_dict(B2)))
	var parts := {}
	for bf in orig["bad_frames"]:
		for pr in bf[2]:
			parts[pr[0] + "|" + pr[1]] = true
	ok(JSON.stringify(mir["bad_frames"]) == JSON.stringify(fresh["bad_frames"]) and JSON.stringify(mir["bad_frames"]) != JSON.stringify(orig["bad_frames"]),
		"5 the file's bad_frames are the mirrored motion's own (%d frames; the original's %d, touching %s, were the other side)" % [mir["bad_frames"].size(), orig["bad_frames"].size(), parts.keys().slice(0, 4)])

	# twice
	m._mirror_scene()
	await idle()
	var back := read("res://scenes/_wip/zz_z1.json")
	var worst := 0.0
	for i in orig["cards"].size():
		var a := Moves._flat(orig["cards"][i]["pose"])
		var b := Moves._flat(back["cards"][i]["pose"])
		for j in a["ang"]:
			var dv: Vector3 = ((a["ang"][j] as Vector3) - (b["ang"][j] as Vector3)).abs()
			worst = maxf(worst, maxf(dv.x, maxf(dv.y, dv.z)))
	ok(worst < 0.01 and JSON.stringify(back["cards"][2].get("plant")) == JSON.stringify(orig["cards"][2]["plant"]) and JSON.stringify(back["cards"][3]["steps"]) == JSON.stringify(orig["cards"][3]["steps"]) and JSON.stringify(back.get("ik")) == JSON.stringify(orig["ik"]),
		"6 mirrored twice: the scene back (the poses within %.4f deg, the plant, the step and the IK keys as they were)" % worst)
	for p in [mp, "res://scenes/_wip/zz_z1.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("MIRROR LIST: %d failed" % fails)
	quit(1 if fails > 0 else 0)
