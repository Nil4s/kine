## godot --headless --path . -s tests/sets_test.gd     (GAP_ANALYSIS rows 9 and 6; scripts/part_sets.gd)
## SELECTION SETS and KEYING SETS on the real poser:
##   1 a selection set made from the selection selects EXACTLY its parts (no more, no fewer, the first one shown),
##     and each edit (new, add, remove, rename, delete) is one undo step that one Ctrl+Z puts back exactly
##   2 K with an active keying set keys exactly its body parts at the playhead, each at the angle the body shows,
##     ONE undo step that takes all of them back; with none active K keys only the picked part, as before
##   3 the scene file round-trips the sets (to_dict -> JSON -> from_dict), and the browser lists them
##   4 mirror: parts to twins, "_l" names to "_r", the active keying set follows
##   5 a scene with no set is unchanged: every scene in scenes/ loads with no sets and saves with no "sets" key
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func browser_texts() -> Array:
	var out := []
	var it: TreeItem = m.ui_browser.get_root()
	while it != null:
		out.append(it.get_text(0))
		it = it.get_next_in_tree()
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m.tour_step = -1
	var P := PartSets.of(m)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._card_pick(2)
	await idle()
	m.undo.clear()

	# 1 selection sets
	var arm := ["upperarm_l", "lowerarm_l", "hand_l"]
	m._select_set(arm)
	var u0: int = m.undo.size()
	P.make("select")
	ok(m.S.sets.get("select", {}).get("set 1_l", []) == arm and m.undo.size() == u0 + 1,
		"1 new selection set from 3 left-arm parts: named 'set 1_l', holds exactly them, %d undo step" % (m.undo.size() - u0))
	m._select_set(["head"])
	P.pick("select", "set 1_l")
	ok(m.group() == arm and m.sel == "upperarm_l", "1 picking it selects exactly its parts %s (shown: %s)" % [m.group(), m.sel])
	m._select_set(["spine_01", "neck_01"])
	P.make("select")
	P.pick("select", "set 1_l")
	ok(m.group() == arm, "1 a second set made, picking the first again selects exactly the first's parts")
	P.pick("select", "set 2")
	ok(m.group() == ["spine_01", "neck_01"], "1 the middle set has no side in its name ('set 2') and selects %s" % [m.group()])
	# the edits, each one undo step, each put back exactly by one Ctrl+Z
	var steps := [
		["add the shown hand", func(): m._select_set(["hand_r"]); P.cur = {"kind": "select", "name": "set 2"}; P.add_parts(),
			func(): return m.S.sets["select"]["set 2"] == ["spine_01", "neck_01", "hand_r"]],
		["remove neck", func(): m._select_set(["neck_01"]); P.cur = {"kind": "select", "name": "set 2"}; P.remove_parts(),
			func(): return m.S.sets["select"]["set 2"] == ["spine_01"]],
		["rename", func(): P.rename("select", "set 2", "back"),
			func(): return m.S.sets["select"].keys() == ["set 1_l", "back"] and P.cur["name"] == "back"],
		["delete", func(): P.cur = {"kind": "select", "name": "set 2"}; P.delete_cur(),
			func(): return not m.S.sets["select"].has("set 2") and m.S.sets["select"].has("set 1_l")],
		["mirror", func(): P.cur = {"kind": "select", "name": "set 1_l"}; P.mirror_cur(),
			func(): return m.S.sets["select"].get("set 1_r", []) == ["upperarm_r", "lowerarm_r", "hand_r"]]]
	for st in steps:
		var before := var_to_str(m.S.sets)
		var u1: int = m.undo.size()
		(st[1] as Callable).call()
		var did: bool = (st[2] as Callable).call()
		var n: int = m.undo.size() - u1
		m._undo()
		ok(did and n == 1 and var_to_str(m.S.sets) == before, "1 %s: did it %s, %d undo step, one Ctrl+Z puts the sets back exactly %s" % [st[0], did, n, var_to_str(m.S.sets) == before])
	# a refusal (nothing to add) changes nothing and pushes nothing
	var b0 := var_to_str(m.S.sets)
	var u2: int = m.undo.size()
	m._select_set(["spine_01"])
	P.cur = {"kind": "select", "name": "set 2"}
	P.add_parts()
	ok(var_to_str(m.S.sets) == b0 and m.undo.size() == u2, "1 adding a part already in the set is refused: no change, no undo step")
	# undoing the very first set leaves the scene with none (the file key goes)
	var only := Scene.new()
	only.sets = PartSets.clean({"select": {"x": []}, "keying": {"y": ["sword"]}, "active": "z"})
	ok(only.sets.is_empty(), "1 clean() drops an empty set, a part that is not a body part, an active name with no keying set")

	# 2 keying sets
	m.S.part_keys = {}
	m.playhead = float(m.S.times()[3][1]) - 0.07
	m.S.apply(m.B, m.playhead)
	m._select_set(["spine_01", "spine_03", "head", "index_02_r"])   # a finger rides along in the set but is not keyed
	P.make("keying")
	var kn := "keys 1"
	ok(P.active() == kn and m.S.sets["keying"][kn] == ["spine_01", "spine_03", "head", "index_02_r"], "2 new keying set '%s' is the active one" % P.active())
	m._select_set(["lowerarm_r"])
	m.B.set_ang_safe("spine_03", m.B.ang["spine_03"] + Vector3(6, 0, 0))   # the body off the cards: the key must take what it shows
	var want := {}
	for j in ["spine_01", "spine_03", "head"]:
		want[j] = m.B.ang[j]
	var u3: int = m.undo.size()
	var pk0 := var_to_str(m.S.part_keys)
	m._key_part()
	var t := clampf(m.playhead, 0.0, m.S.length())
	var keyed: Array = m.S.part_keys.keys()
	keyed.sort()
	var exact := keyed == ["head", "spine_01", "spine_03"]
	for j in want:
		var ks: Array = m.S.part_keys.get(j, [])
		exact = exact and ks.size() == 1 and absf(float(ks[0]["t"]) - t) < 1e-6 and (ks[0]["v"] as Vector3).is_equal_approx(want[j])
	ok(exact, "2 K with keying set active keys exactly %s at %.3f s at the angles shown (picked part lowerarm_r and the finger NOT keyed)" % [keyed, t])
	ok(m.undo.size() == u3 + 1, "2 that K is ONE undo step (%d)" % (m.undo.size() - u3))
	m._undo()
	ok(var_to_str(m.S.part_keys) == pk0, "2 one Ctrl+Z takes all 3 keys back")
	P.use_none()
	ok(P.active() == "" and m.S.sets.get("keying", {}).has(kn), "2 'none' leaves the keying set but no active one")
	m._key_part()
	keyed = m.S.part_keys.keys()
	ok(keyed == ["lowerarm_r"] and m.S.part_keys["lowerarm_r"].size() == 1, "2 with none active K keys only the picked part, as before: %s" % [keyed])
	m._undo()
	P.cur = {"kind": "keying", "name": kn}
	P.use_cur()
	ok(P.active() == kn, "2 'use the picked set for K' makes it active again")
	P.rename("keying", kn, "torso_l")
	ok(P.active() == "torso_l", "2 renaming the active keying set keeps it active under the new name")

	# 3 the file and the browser
	m.ui_browser.refresh()
	await idle(3)
	var tx := browser_texts()
	ok(tx.has("Selection sets  (2)") and tx.has("set 2  (2)") and tx.has("set 1_l  (3)") and tx.has("Keying sets  (1)") and tx.has("torso_l   K  (4)"),
		"3 the browser lists the sets under Sets (the active keying set marked K): %s" % [tx.filter(func(x): return x.contains("set") or x.contains("torso"))])
	var keep: Dictionary = m.B.state()
	var d: Dictionary = JSON.parse_string(JSON.stringify(m.S.to_dict(m.B, false)))
	m.B.set_state(keep)
	ok(d.get("sets") == {"select": {"set 1_l": arm, "set 2": ["spine_01", "neck_01"]}, "keying": {"torso_l": ["spine_01", "spine_03", "head", "index_02_r"]}, "active": "torso_l"},
		"3 the file holds the sets: %s" % JSON.stringify(d.get("sets")))
	var S2 := Scene.new()
	S2.from_dict(d)
	ok(var_to_str(S2.sets) == var_to_str(m.S.sets), "3 file -> scene round trip: the same sets back")
	var d2: Dictionary = JSON.parse_string(JSON.stringify(S2.to_dict(m.B, false)))
	ok(JSON.stringify(d2.get("sets")) == JSON.stringify(d["sets"]), "3 and saving it again writes the same \"sets\"")
	m.B.set_state(keep)

	# 4 mirror
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var mf := Scene.mirror_file(d, M)
	ok(mf.get("sets") == {"select": {"set 1_r": ["upperarm_r", "lowerarm_r", "hand_r"], "set 2": ["spine_01", "neck_01"]}, "keying": {"torso_r": ["spine_01", "spine_03", "head", "index_02_l"]}, "active": "torso_r"},
		"4 mirrored file: %s" % JSON.stringify(mf.get("sets")))
	ok(PartSets.mirror_file(PartSets.mirror_file(m.S.sets)) == m.S.sets, "4 mirrored twice: the sets come back")
	ok(PartSets.mirror_file({"select": {"arm_l": ["hand_l"], "arm_r": ["hand_r", "foot_r"]}}) == {"select": {"arm_r": ["hand_r"], "arm_l": ["hand_l", "foot_l"]}},
		"4 'arm_l' and 'arm_r' trade places, never collide")

	# 5 scenes without sets
	var bad := []
	var n := 0
	for f in DirAccess.get_files_at("res://scenes"):
		if not f.ends_with(".json"):
			continue
		var fd = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f))
		if not fd is Dictionary or not fd.has("cards"):
			continue
		n += 1
		var S3 := Scene.new()
		S3.from_dict(fd)
		var o := S3.to_dict(m.B, false)
		if fd.has("sets") or not S3.sets.is_empty() or o.has("sets"):
			bad.append(f)
	m.B.set_state(keep)
	ok(n > 5 and bad.is_empty(), "5 %d scenes in scenes/ load with no sets and save with no \"sets\" key %s" % [n, bad])
	m._new_scene()
	await idle()
	ok(m.S.sets.is_empty() and not m.S.to_dict(m.B, false).has("sets"), "5 a new scene has no sets")
	P.cur = {}
	var u4: int = m.undo.size()
	P.select_cur()
	P.delete_cur()
	ok(m.undo.size() == u4, "5 set commands with no set picked refuse and push no undo step")

	print("SETS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
