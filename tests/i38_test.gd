## godot --path . -s tests/i38_test.gd     (ROADMAP I38: my best take, scripts/best_take.gd + best_take_ui.gd; needs a window)
## Synthetic clips with KNOWN features, written under user://i38_<pid>/ (the real scenes/ are only hashed): 5 peers and an open clip share one
## timing and one guard; the STARRED clip differs on exactly two features: the wind-up hold (0.05 s -> 0.20 s) and the guard height (hands raised
## by +35 deg of upper-arm bend on the guard card). Bars, written before measuring:
##  (1) rank: the two known features are rows 1 and 2 (either order), each with |effect| >= 3 spreads; every other row has |effect| < 1.5; 5 rows shown
##  (2) words: the wind-up row says "longer" with the starred 0.20 s and the usual 0.05 s (within 0.01 s); every row has a number with a unit
##  (3) the nudge on the open clip: wind-up hold ends within 0.01 s of the starred value; guard height within 1 cm of the starred height;
##      every other feature moves less than half its FLOOR
##  (4) the analysis is read only: the body state (B.state) and the scene JSON are identical after My best take and after planning
##  (5) Preview plays to its end and leaves the scene JSON byte-identical; Accept is ONE undo step; Ctrl+Z restores cards and JSON exactly
##  (6) the star lives in user:// (toggle on / off), never in scenes/: the real scenes/, poses/, data/ hash the same before and after
##  (7) PLACEMENT: in the screenshot the panel is on screen with 5 rows, each bar sits inside the panel directly under its sentence (its top within
##      6 px below the sentence's bottom, its left edge on the sentence's), and the open body's head is drawn inside the 3D view, not under the panel
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i38.png"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func hashes() -> Dictionary:
	var out := {}
	for dir in ["res://scenes/", "res://poses/", "res://data/"]:
		var stack := [dir]
		while not stack.is_empty():
			var d: String = stack.pop_back()
			for fn in DirAccess.get_files_at(d):
				out[d + fn] = FileAccess.get_md5(d + fn)
			for sub in DirAccess.get_directories_at(d):
				stack.append(d + sub + "/")
	return out


func write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


## a clip: [name, pose key, move, hold] per card; guard_up = extra upper-arm bend on the guard card
func clip(nm: String, poses: Dictionary, wu_hold: float, strike_mv: float, guard_up: float) -> Dictionary:
	var rows := [["guard ready", "ready", -1.0, 0.25], ["wind-up", "chamber", 0.30, wu_hold], ["strike", "thrust", strike_mv, 0.10],
		["recover", "ready", 0.50, 0.20], ["step forward", "ready", 0.40, 0.15]]
	var cs := []
	for k in rows.size():
		var c: Array = rows[k]
		var pose: Dictionary = (poses[c[1]] as Dictionary).duplicate(true)
		if k == 0 and guard_up != 0.0:
			for j in ["upperarm_l", "upperarm_r"]:
				pose["joints"][j]["bend"] = float(pose["joints"][j]["bend"]) + guard_up
		cs.append({"name": c[0], "pose": pose, "move": c[2], "hold": c[3]})
	return {"scene": nm, "fps": 30, "cards": cs}


func _init() -> void:
	var before_files := hashes()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B
	var th: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/thrust.json"))
	var poses := {"ready": th["cards"][0]["pose"], "chamber": th["cards"][6]["pose"], "thrust": th["cards"][9]["pose"]}
	var tmp := "user://i38_%d/" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(tmp)
	var holds := [0.04, 0.05, 0.05, 0.06, 0.05]
	var mvs := [0.10, 0.11, 0.10, 0.11, 0.10]
	var peer_paths := []
	for k in 5:
		var p := tmp + "peer%d.json" % k
		write(p, clip("peer%d" % k, poses, holds[k], mvs[k], 0.0))
		peer_paths.append(p)
	var star_path := tmp + "best.json"
	var open_path := tmp + "open.json"
	write(star_path, clip("best", poses, 0.20, 0.10, 35.0))
	write(open_path, clip("open", poses, 0.05, 0.10, 0.0))
	m.bt_ui.dirs = [tmp]
	m.bt_ui.stars_path = tmp + "stars.json"

	# (6) the star, from the open clip's own path
	m._load_scene(open_path)
	m._rebuild_cards()
	await idle()
	m.scene_path = star_path
	m.bt_ui.star()
	ok(BestTake.load_stars(m.bt_ui.stars_path) == [star_path] and FileAccess.file_exists(m.bt_ui.stars_path), "(6) starring writes the star to %s" % m.bt_ui.stars_path)
	m.scene_path = open_path
	m._load_scene(open_path)
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	var json0 := JSON.stringify(S.to_dict(B, false))
	var cards0 := JSON.stringify(S.cards)
	var state0 := JSON.stringify(B.state())

	# (1)(2)(4) the analysis
	m.bt_ui.show()
	await idle()
	var res: Dictionary = m.bt_ui.res
	ok(not res.has("error"), "(1) the analysis ran: %s" % [res.get("error", "%d peers" % int(res.get("peers", 0)))])
	var rows: Array = res.get("rows", [])
	var summary := []
	for r in rows:
		summary.append("%s %+.1f (%.3f vs %.3f)" % [r["feat"], r["effect"], r["star"], r["usual"]])
	print("     rows: %s  (%.0f ms)" % [summary, m.bt_ui.ms])
	var top2 := [String(rows[0]["feat"]), String(rows[1]["feat"])] if rows.size() >= 2 else []
	ok(rows.size() == 5 and top2.has("windup_hold") and top2.has("guard_h"), "(1) rows 1 and 2 are the two known features: %s" % [top2])
	ok(rows.size() >= 2 and absf(float(rows[0]["effect"])) >= 3.0 and absf(float(rows[1]["effect"])) >= 3.0, "(1) their effect sizes are %.1f and %.1f spreads (>= 3)" % [rows[0]["effect"], rows[1]["effect"]])
	var worst3 := 0.0
	for k in range(2, rows.size()):
		worst3 = maxf(worst3, absf(float(rows[k]["effect"])))
	ok(worst3 < 1.5, "(1) every other row is below 1.5 spreads (largest %.2f)" % worst3)
	var wu_row := {}
	for r in rows:
		if r["feat"] == "windup_hold":
			wu_row = r
	var wtxt := BestTake.words(wu_row) if not wu_row.is_empty() else ""
	print("     \"%s\"" % wtxt)
	ok(wtxt.contains("longer") and wtxt.contains("0.15 s") and wtxt.contains("usual 0.05 s") and absf(float(wu_row.get("star", 0.0)) - 0.20) < 0.01 and absf(float(wu_row.get("usual", 0.0)) - 0.05) < 0.01,
		"(2) wind-up sentence: longer, starred 0.20 s, usual 0.05 s")
	var re := RegEx.new()
	re.compile("[0-9.]+ ?(s|cm|m/s|%|×)")
	var all_units := true
	for r in rows:
		all_units = all_units and re.search(BestTake.words(r)) != null
	ok(all_units, "(2) every sentence carries a number with a unit")
	for r in rows:
		print("     - " + BestTake.words(r))
	ok(JSON.stringify(B.state()) == state0 and JSON.stringify(S.to_dict(B, false)) == json0, "(4) My best take left the body state and the scene JSON as they were")

	# (7) placement, with the panel open on the analysis
	await idle(3)
	var img: Image = root.get_texture().get_image()
	var panel: Control = m.ui_find
	var pr: Rect2 = panel.get_global_rect()
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	var placed := panel.visible and vp.encloses(pr)
	var sentences := 0
	var bars_ok := true
	for k in 5:
		var lb: Label = m.ui_find_list.find_child("bt_row_%d" % k, true, false) as Label
		var br: ProgressBar = m.ui_find_list.find_child("bt_bar_%d" % k, true, false) as ProgressBar
		if lb == null or br == null:
			bars_ok = false
			continue
		sentences += 1
		var lr := lb.get_global_rect()
		var brr := br.get_global_rect()
		var gap := brr.position.y - (lr.position.y + lr.size.y)
		bars_ok = bars_ok and gap >= -1.0 and gap <= 6.0 and absf(brr.position.x - lr.position.x) < 2.0 and pr.encloses(brr)
		if k < 2:
			print("     row %d: sentence %s bar %s gap %.1f px" % [k, lr, brr, gap])
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var head: Vector2 = cam.unproject_position(B.P["head"]) if cam != null else Vector2.ZERO
	ok(placed and sentences == 5 and bars_ok, "(7) panel %s inside the window %s with 5 sentences, each bar directly under its sentence" % [pr, vp])
	ok(vp.has_point(head) and head.length() > 20.0 and not pr.has_point(head), "(7) the body's head is drawn at %s: inside the window, not under the panel" % [head])
	img.save_png(SHOT)
	print("     picture: " + SHOT)

	# (3)(4) the nudge
	var star_f: Dictionary = res["feats"]
	var before := BestTake.features(S, B)
	state0 = JSON.stringify(B.state())   # the test's own measuring posed the body: the planning must put THIS back
	m.bt_ui.make_like()
	await idle()
	var plan: Dictionary = m.bt_ui.plan
	var after := BestTake.features(plan["scene"], B)
	var star_h := float(star_f["guard_h"])
	print("     before %s" % [before])
	print("     after  %s" % [after])
	print("     starred %s" % [star_f])
	ok(absf(float(after["windup_hold"]) - 0.20) <= 0.01, "(3) wind-up hold %.3f s -> %.3f s (starred 0.200 s)" % [before["windup_hold"], after["windup_hold"]])
	ok(absf(float(after["guard_h"]) - star_h) <= 1.0, "(3) guard height %.1f cm -> %.1f cm (starred %.1f cm)" % [before["guard_h"], after["guard_h"], star_h])
	var quiet := true
	for f in ["anticipation", "strike_move", "follow", "stance"]:
		var d := absf(float(after[f]) - float(before[f]))
		quiet = quiet and d < 0.5 * float(BestTake.FLOOR[f])
		print("     %s moved by %.4f (limit %.4f)" % [f, d, 0.5 * float(BestTake.FLOOR[f])])
	ok(quiet, "(3) the other features moved less than half their floor")
	ok(JSON.stringify(B.state()) == state0 and JSON.stringify(S.to_dict(B, false)) == json0 and JSON.stringify(S.cards) == cards0, "(4) planning left the body state, the scene JSON and the cards as they were")

	# (5) preview, accept, undo
	m.bt_ui.preview()
	var guard := 0
	while m.bt_ui.pv != null and guard < 600:
		await process_frame
		guard += 1
	ok(m.bt_ui.pv == null and JSON.stringify(S.to_dict(B, false)) == json0, "(5) Preview played to its end (%d frames) and the scene JSON is byte-identical" % guard)
	var u0: int = m.undo.size()
	m.bt_ui.accept()
	await idle()
	var acc := BestTake.features(m.S, B)
	ok(m.undo.size() == u0 + 1 and absf(float(acc["windup_hold"]) - 0.20) <= 0.01 and absf(float(acc["guard_h"]) - star_h) <= 1.0,
		"(5) Accept is ONE undo step (%d -> %d) and the open clip now has hold %.3f s, guard %.1f cm" % [u0, m.undo.size(), acc["windup_hold"], acc["guard_h"]])
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(B, false)) == json0, "(5) Ctrl+Z restores the cards and the scene JSON exactly")

	# (6) unstar, and the files
	m.scene_path = star_path
	m.bt_ui.star()
	ok(BestTake.load_stars(m.bt_ui.stars_path).is_empty(), "(6) starring again takes the star off")
	var after_files := hashes()
	var same := before_files.size() == after_files.size()
	for k in before_files:
		same = same and after_files.get(k, "") == before_files[k]
	ok(same, "(6) the real scenes/, poses/ and data/ hash the same (%d files)" % before_files.size())
	DirAccess.remove_absolute(m.bt_ui.stars_path)

	print("I38 MY BEST TAKE %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
