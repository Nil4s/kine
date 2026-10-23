## godot --headless --path . -s tests/dryrun_test.gd     (N003 DRY RUN ANY COMMAND; scripts/dry_run.gd)
## BARS, written before measuring:
##   1 UNTOUCHED: for 30+ edit commands of the registry (and 3 step lists), each dry-run on combo3 card 2, the scene file's
##     JSON bytes (Scene.to_dict without bad_frames: that key is Check's sampling of the rest of the file, ~1 s each on
##     combo3, so equal inputs give it equal), var_to_str(B.state()) and the undo / redo sizes read BY THIS TEST are identical
##     before and after, and the dry run's own proof says restored. Bar: every one, and at least 30 of them edit commands.
##   2 TRUE: the same command then run for real moves the SAME live-body joints (> 0.5 deg) as the dry report said, each
##     bend / side / twist within 0.01 deg, and SceneDiff of the real run equals the dry report's cards (changed / added /
##     removed). Bar: every command of 1.
##   3 SCORE: for 6 commands, the dry run's realism-score change equals the real run's (both read cold) within 0.1.
##   4 REFUSED: 12 file-writing / dialog steps (save_scene, save_pose, exports, packs, a physics= import, a "..." dialog) are
##     refused with a reason, nothing runs (no step result, the undo size the same); serve's `dry` answers -32602 for one.
##   5 NO FILE: md5 of every file under scenes/ poses/ moves/ data/ exports/ is the same at the end of 1-4 as at the start.
##   6 SERVE + CLI: `dry` through AgentTools.request answers a result (its undo_steps >= 1 for mirror + update, read with the
##     undo list at its 60 cap, where a size difference would say 0); `poser_cli run ... --dry --json` exits ok with
##     "dry": true and its scene file unchanged.
extends SceneTree

var fails := 0
var m: Node
var T: AgentTools

const SCENE := "scenes/combo3.json"
const EDITS := ["reset_the_part", "snap_the_part_to_90", "snap_the_part_to_45", "copy_right_side_to_left", "copy_left_side_to_right",
	"mirror_the_whole_pose", "point_the_right_hand", "hand_pose_fist", "arms_down_25", "reset_body",
	"fingers_right_fist", "weapon_bo_staff", "weapon_sword", "remove_the_weapon", "look_at_the_camera",
	"snap_to_floor", "blend_to_rest_pose", "blend_to_next_card", "breakdowner_50", "clip_this_pose_add_a_card",
	"slower_10", "faster_10", "ease_linear", "ease_strike", "add_an_in-between_card", "add_marker_at_the_playhead", "key_the_part_here",
	"snap_to_floor_all_cards", "mirror_in_place", "moving_holds_on_off", "loop_close_the_seam", "plant_the_left_foot_on_this_card",
	"cards_retime_the_selected_x2_slower", "body_95th_percentile_man", "breathing_on_off"]
const LISTS := [["card=3", "pose=raise the right arm 90", "update"], ["sel=lowerarm_r", "set=lowerarm_r:90,0,0", "update"], ["card=4", "delete"]]
const SCORED := ["mirror_the_whole_pose", "slower_10", "faster_10", "reset_body", "snap_the_part_to_90", "ease_linear"]
const WRITERS := ["save_scene", "save_pose", "export_animation_.glb", "export_animation_.bvh", "pack_scene_zip", "cape_export_its_vertices_json",
	"help_save_this_session_as_a_script", "mirror_the_scene_a_copy_in__wip", "new_from_template_walk", "save_a_version", "physics=x.bvh", "export..."]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func files_md5() -> Dictionary:
	var out := {}
	for d in ["res://scenes", "res://poses", "res://moves", "res://data", "res://exports"]:
		_walk(d, out)
	return out


func _walk(d: String, out: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(d):
		return
	for f in DirAccess.get_files_at(d):
		out[d + "/" + f] = FileAccess.get_md5(d + "/" + f)
	for s in DirAccess.get_directories_at(d):
		_walk(d + "/" + s, out)


func fresh() -> void:
	await T.request(1, "open", {"path": SCENE})
	await T.step("card=2")


func now() -> Dictionary:
	return {"scene": JSON.stringify(DryRun._file(m)), "body": var_to_str(m.B.state()), "undo": m.undo.size(), "redo": m.redo.size()}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	T = AgentTools.new(m)
	var md0 := files_md5()
	print("     %d files watched" % md0.size())

	# 1 + 2
	var n_edit := 0
	var bad1 := []
	var bad2 := []
	var ms := []
	for cmd in EDITS + LISTS:
		var steps: Array = cmd if cmd is Array else [cmd]
		var label := " ".join(steps)
		await fresh()
		var w0 := now()
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = await DryRun.run(T, steps, false)
		ms.append(Time.get_ticks_msec() - t0)
		var w1 := now()
		var same: bool = w0 == w1 and bool(r.get("restored", false))
		if not same:
			bad1.append("%s (scene %s body %s undo %d->%d redo %d->%d proof %s %s)" % [label, w0["scene"] == w1["scene"], w0["body"] == w1["body"], w0["undo"], w1["undo"],
				w0["redo"], w1["redo"], r.get("proof"), r.get("refused", r.get("error", ""))])
		elif cmd is String and r["ok"]:
			n_edit += 1
		if not r.get("ok", false):
			print("     %s: dry not ok: %s" % [label, r.get("refused", r.get("error", ""))])
			continue
		# the real run, from the same state
		var a0: Dictionary = (m.B.ang as Dictionary).duplicate()
		var sd0 := DryRun._file(m)
		var real_ok := true
		for s in steps:
			real_ok = real_ok and (await T.step(s))["ok"]
		var moved := DryRun.body_moved(a0, m.B.ang)
		var d := SceneDiff.diff(sd0, DryRun._file(m))
		var pm: Array = r["parts_moved"]
		var match_j := moved.size() == pm.size()
		if match_j:
			for i in moved.size():
				var x: Dictionary = moved[i]
				var y: Variant = pm.filter(func(q): return q["joint"] == x["joint"])
				if y.is_empty():
					match_j = false
					break
				for k in 3:
					if absf(float(x["d"][k]) - float(y[0]["d"][k])) > 0.01:
						match_j = false
		var match_c := JSON.stringify([d["cards"], d["added"], d["removed"]]) == JSON.stringify([r["cards"]["changed"], r["cards"]["added"], r["cards"]["removed"]])
		if not (real_ok and match_j and match_c):
			bad2.append("%s (real ok %s, joints %s: dry %s real %s, cards %s)" % [label, real_ok, match_j, pm.map(func(q): return q["joint"]), moved.map(func(q): return q["joint"]), match_c])
		print("     %-40s %4d ms  parts %2d  cards changed %d  keys %s  undo +%d  findings %d->%d" % [label.left(40), ms[-1], pm.size(), r["cards"]["changed"].size(),
			r["keys_touched"], r["undo_steps"], r["findings"]["before"], r["findings"]["after"]])
	ms.sort()
	ok(bad1.is_empty() and n_edit >= 30, "1 untouched: %d of %d edit commands + %d step lists dry-run with the scene JSON, B.state() and undo / redo identical (median %d ms)%s" % [
		n_edit, EDITS.size(), LISTS.size(), ms[ms.size() / 2], "" if bad1.is_empty() else ": " + "; ".join(bad1)])
	ok(bad2.is_empty(), "2 true: the real run moves the same joints within 0.01 deg and the same cards as the dry report said%s" % ("" if bad2.is_empty() else ": " + "; ".join(bad2)))

	# 3
	var worst := 0.0
	var rows := []
	for cmd in SCORED:
		await fresh()
		var r: Dictionary = await DryRun.run(T, [cmd], true)
		var s0: Variant = DryRun.cold_score(m)
		await T.step(cmd)
		var s1: Variant = DryRun.cold_score(m)
		var real := float(s1) - float(s0)
		var dd := absf(real - float(r["score"]["delta"]))
		worst = maxf(worst, dd)
		rows.append("%s %+.2f/%+.2f" % [cmd, float(r["score"]["delta"]), real])
	ok(worst <= 0.1, "3 score: the dry change equals the real one within 0.1 (worst %.3f): %s" % [worst, ", ".join(rows)])

	# 4
	await fresh()
	var u0: int = m.undo.size()
	var nref := 0
	var why := []
	for w in WRITERS:
		var r: Dictionary = await DryRun.run(T, ["card=3", w], false)
		if r.has("refused") and not r.has("steps") and m.undo.size() == u0 and String(r["refused"][0]["why"]) != "":
			nref += 1
			why.append("%s: %s" % [w, String(r["refused"][0]["why"]).left(60)])
		else:
			print("     NOT refused: ", w, " ", r.keys())
	var se: Dictionary = await T.request(9, "dry", {"steps": ["save_scene"]})
	ok(nref == WRITERS.size() and se.has("error") and int(se["error"]["code"]) == -32602, "4 refused: %d of %d file-writing / dialog steps, nothing ran; serve's dry error %s" % [
		nref, WRITERS.size(), se.get("error", {}).get("code")])
	for x in why:
		print("     ", x)

	# 6 (before 5: the CLI must not write either)
	await fresh()
	var w2 := now()
	var sr: Dictionary = await T.request(10, "dry", {"steps": ["mirror_the_whole_pose", "update"], "score": false})
	var sok: bool = sr.has("result") and sr["result"]["dry"] and sr["result"]["restored"] and now() == w2 and sr["result"]["parts_moved"].size() > 0 and int(sr["result"]["undo_steps"]) >= 1
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/poser_cli.gd", "--",
		"run", SCENE, "card=2", "mirror_the_whole_pose", "update", "--dry", "--json"], out, true)
	var last := ""
	for l in String("".join(out)).split("\n"):
		if l.begins_with("{\"") and l.contains("\"dry\""):
			last = l
	var cj: Variant = JSON.parse_string(last) if last != "" else null
	var cok: bool = code == 0 and cj is Dictionary and cj["dry"] and cj["restored"] and cj["ok"] and (cj["cards"]["changed"] as Array).size() > 0
	ok(sok and cok, "6 serve dry: result, restored, %d parts moved, undo_steps %s (undo list %d); CLI run --dry: exit %d, dry %s, restored %s, score %s" % [
		sr.get("result", {}).get("parts_moved", []).size(), sr.get("result", {}).get("undo_steps"), m.undo.size(), code, cj.get("dry") if cj is Dictionary else null, cj.get("restored") if cj is Dictionary else null,
		cj.get("score", {}).get("delta") if cj is Dictionary else null])

	# 5
	var md1 := files_md5()
	var diff := []
	for k in md0.keys() + md1.keys():
		if md0.get(k, "") != md1.get(k, "") and not diff.has(k):
			diff.append(k)
	ok(diff.is_empty(), "5 no file: %d files under scenes/ poses/ moves/ data/ exports/ hash the same%s" % [md0.size(), "" if diff.is_empty() else ": changed " + str(diff)])

	print("DRYRUN: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
