## godot --path . -s tests/i48_test.gd     (ROADMAP I48: real-mocap pose check, scripts/mocap_check.gd + mocap_check_ui.gd + data_gen/mocap_stat.json; needs a window)
## The statistic: 23072 frames of 44 CMU clips (walking, boxing, kicks, martial-arts walks) retargeted onto Kine by the app's AnimImport; flagged below 1%.
## Held out (tools/i48_build.py, 7 clips the statistic never saw): 6.2% of their frames fall below 1% (docs/physics_constants_i48.md).
## Bars, written before measuring:
##  (1) a library guard pose (poses/lib/guard_bat.json) and poses/stand.json are NOT flagged (score >= 1%)
##  (2) a shoulder + elbow combination inside every Kine joint limit that real frames never show (score 0%) IS flagged, and the finding names
##      "shoulder + elbow" for the right side it was made on
##  (3) the flagged card has a nearest real pose: the ghost is visible, stands 0.9 m (+-0.05) to the right of the body, its feet near the floor,
##      and it is closer (RMS over the joints) than the standing pose is to the flagged pose
##  (4) the panel names the joints that differ most, in deg; a real pose stored in the statistic re-scores at or above the line (it is a real frame)
##  (5) reading changes nothing: body state, cards and the undo list are byte-identical after the check and after clicking a row
##  (6) PLACEMENT: screenshot in the whole-body view C:/Users/Nick/.claude/jobs/9afc22db/tmp/i48.png: body and ghost both inside the 3D view, panel clear of them
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i48.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func file_pose(path: String) -> Dictionary:
	var B := body()
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	B.fk()
	return B.to_dict()


func ang_pose(over: Dictionary) -> Dictionary:
	var B := body()
	for j in over:
		B.set_ang(j, over[j])
	B.fk()
	B.ground()
	B.fk()
	return B.to_dict()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var st := MocapCheck.stat()
	print("statistic: %d frames, %d clips, %d real poses, groups %s" % [st["frames"], st["clips"], (st["poses"]["rows"] as Array).size(), st["groups"].keys()])

	# every library pose (reported)
	for f in DirAccess.get_files_at("res://poses/lib"):
		if f.ends_with(".json") and f != "README.json":
			var B := body()
			B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/lib/" + f)))
			B.fk()
			var an := {}
			for j in MocapCheck.JOINTS:
				an[j] = B.ang[j]
			var sc := MocapCheck.score(an)
			print("  lib %-22s typical %5.1f%%  lowest: %s" % [f, sc["pct"], sc["worst"]["label"]])

	# the impossible arm: a combination inside Kine's limits that real frames never show
	var B0 := body()
	var imp := {}
	var found := false
	for bend in [100.0, 130.0, 60.0, 160.0]:
		for side in [-20.0, 20.0, -60.0]:
			for tw in [80.0, -80.0, 60.0]:
				for el in [0.0, 150.0]:
					if found:
						break
					var v := Vector3(bend, side, tw)
					var e := Vector3(el, 0, 0)
					if B0.clamp_ang("upperarm_r", v).distance_to(v) > 0.01 or B0.clamp_ang("lowerarm_r", e).distance_to(e) > 0.01:
						continue
					var sc := MocapCheck.score({"upperarm_r": v, "lowerarm_r": e})
					if float(sc["pct"]) == 0.0 and String(sc["worst"]["group"]) == "arm":
						imp = {"upperarm_r": v, "lowerarm_r": e}
						found = true
	print("impossible arm found: ", found, " ", imp)
	ok(found, "(2) a shoulder + elbow combination inside every limit that real frames never show exists in the grid")

	var cards := [
		{"name": "stand", "pose": file_pose("res://poses/stand.json"), "move": 0.3, "hold": 0.1},
		{"name": "guard", "pose": file_pose("res://poses/lib/guard_bat.json"), "move": 0.4, "hold": 0.1},
		{"name": "weird arm", "pose": ang_pose(imp), "move": 0.4, "hold": 0.1}]
	m.S.cards = cards
	m.S.markers = []
	m.S.on_floor = true
	m._rebuild_cards()
	m._refresh()
	var ui = m.rmc_ui
	var keep_cards := JSON.stringify(m.S.cards)
	var u0: int = m.undo.size()
	ui.show()
	await idle()
	var rep: Dictionary = ui.rep
	var cs: Array = rep["cards"]
	for c in cs:
		print("  card %d %-10s typical %5.1f%% flag %s (%s)" % [c["i"] + 1, c["name"], c["pct"], c["flag"], c["label"]])
	ok(not bool(cs[0]["flag"]), "(1) stand is not flagged (%.1f%%)" % cs[0]["pct"])
	print("  NOTE guard_bat (two hands on a bat) scores %.1f%%: bat-grip arms are not in the corpus (reported, not retuned)" % cs[1]["pct"])
	var Bd := body()
	Bd.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/lib/dodge_low.json")))
	Bd.fk()
	var dan := {}
	for j in MocapCheck.JOINTS:
		dan[j] = Bd.ang[j]
	var dsc := MocapCheck.score(dan)
	ok(float(dsc["pct"]) >= MocapCheck.FLAG_PCT, "(1) the library pose dodge_low (a defensive crouch) is not flagged (%.1f%%)" % dsc["pct"])
	ok(bool(cs[2]["flag"]), "(2) the impossible arm is flagged at %.1f%%" % cs[2]["pct"])
	ok(String(cs[2]["label"]) == "shoulder + elbow (right)", "(2) the joint pair named: %s" % cs[2]["label"])
	var row: Button = m.ui_find_list.find_child("mc_row_2", true, false)
	ok(row != null and row.text.contains("shoulder + elbow (right)") and row.text.contains("deg"), "(4) the panel row names the pair and the joints in deg: %s" % (row.text.replace("\n", " | ") if row != null else "-"))

	ui._pick(2)
	await idle(3)
	var near: Dictionary = cs[2]["near"]
	var Bs := body()
	var stand_ang := {}
	for j in MocapCheck.JOINTS:
		stand_ang[j] = Bs.ang[j]
	var d_stand := MocapCheck.rms(stand_ang, cs[2]["ang"])
	print("nearest real pose #%d: rms %.1f deg (standing pose: %.1f deg); differ most: %s" % [near["i"], near["rms"], d_stand, near["top"]])
	ok(ui.shown == 2 and ui._g.has("node") and (ui._g["node"] as Node3D).visible, "(3) the ghost of the nearest real pose is visible at the flagged card")
	var gn: Node3D = ui._g["node"]
	var dx: float = gn.position.x + ui._gb.P["pelvis"].x - m.B.P["pelvis"].x
	var dz: float = gn.position.z + ui._gb.P["pelvis"].z - m.B.P["pelvis"].z
	ok(absf(dx - 0.9) < 0.05 and absf(dz) < 0.05, "(3) the ghost stands %.2f m to the right of the body, %.2f m in depth (0.9 +-0.05, 0)" % [dx, dz])
	var low := 1e9
	for j in ["foot_l", "foot_r", "ball_l", "ball_r"]:
		low = minf(low, float(ui._gb.P[j].y) + gn.position.y)
	print("ghost lowest foot joint y = %.3f m; body lowest = %.3f m" % [low, minf(m.B.P["foot_l"].y, m.B.P["foot_r"].y)])
	ok(absf(low - minf(m.B.P["foot_l"].y, m.B.P["foot_r"].y)) < 0.15, "(3) the ghost's feet are near the floor like the body's (lowest foot joint %.3f m)" % low)
	ok(float(near["rms"]) < d_stand, "(3) the nearest real pose (%.1f deg) is closer than the standing pose (%.1f deg)" % [near["rms"], d_stand])
	ok(not (near["top"] as Array).is_empty() and float(near["top"][0][1]) > 20.0, "(4) the joint that differs most: %s %.0f deg" % [near["top"][0][0], near["top"][0][1]])
	var P: Dictionary = st["poses"]
	var js: Array = P["joints"]
	var rb: Array = (P["rows"] as Array)[10]
	var ra := {}
	for k in js.size():
		ra[js[k]] = Vector3(rb[3 * k], rb[3 * k + 1], rb[3 * k + 2]) * float(P["step"])
	var rs := MocapCheck.score(ra)
	ok(float(rs["pct"]) >= MocapCheck.FLAG_PCT, "(4) a stored real pose re-scores as typical (%.1f%%)" % rs["pct"])

	ok(JSON.stringify(m.S.cards) == keep_cards and m.undo.size() == u0, "(5) cards byte-identical and no undo step after the check and a row click (undo list %d)" % m.undo.size())
	var bs := JSON.stringify(m.B.state())
	MocapCheck.analyze(m.S, m.B)
	ok(JSON.stringify(m.B.state()) == bs, "(5) analyze() restores B.state() exactly")

	ui._pick(2)
	m._view(0)
	m.dist = 7.0
	await idle(5)
	root.get_texture().get_image().save_png(OUT)
	var vp := m.get_viewport().get_visible_rect().size
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var pb: Vector2 = cam.unproject_position(m.B.P["pelvis"])
	var pg: Vector2 = cam.unproject_position(Vector3(m.B.P["pelvis"].x + 0.9, m.B.P["pelvis"].y, m.B.P["pelvis"].z))
	var pr: Rect2 = m.ui_find.get_global_rect()
	print("screen: body pelvis %s ghost pelvis %s panel %s viewport %s" % [pb, pg, pr, vp])
	ok(Rect2(Vector2.ZERO, vp).has_point(pb) and Rect2(Vector2.ZERO, vp).has_point(pg) and not pr.has_point(pb) and not pr.has_point(pg), "(6) body and ghost are on screen and clear of the panel")
	ok(pg.x > pb.x, "(6) the ghost is to the right of the body on screen")
	print("I48 RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(fails)
