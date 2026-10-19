## godot --path . -s tests/video_ui_test.gd     (round 45, GATES AA2; windowed: the app itself)
## "ANIMATION FROM VIDEO" IN THE APP:
##   1 the ANIMATE tab has "From video" (its icon drawn) and the search finds "Animation from video" by "video" and "mp4"
##   2 a pose file (the tracker's output: refs/video/walk_bat_track.json, walk_bat as the app renders it, tracked by
##     MediaPipe) dropped on the window opens as a NEW scene in scenes/_wip: SPARSE cards (at most half the frames, at
##     least one in 8; it plays as long as the video), the feet planted (cards with a plant > 0, and thinning adds at most
##     0.5 cm to the planted ball's slide of the same file imported a card per frame), its plan names the source and the tracker; removed again here
##   3 a missing video, and a tracker that will not start, are refused with a sentence; the open scene does not change
##   4 the tracker's process is polled, not waited on: a finished process with no output says so on the status line
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the worst slide on the floor of a planted ball, 30 times a second, from where its contact started: the card being
## moved to holds the foot planted (Scene._planted)
func slide_of(S: Scene, B: Body) -> float:
	var ct: Array = S.times()
	var anc := {}
	var worst := 0.0
	var tt := 0.0
	while tt <= S.length():
		var k := 0
		while k < S.cards.size() - 1 and float(ct[k][1]) < tt - 1e-6:
			k += 1
		S.apply(B, tt)
		var pl: Array = S.cards[k].get("plant", [])
		for sd in ["_l", "_r"]:
			var b: Vector3 = B.P["ball" + sd]
			if sd in pl:
				if not anc.has(sd):
					anc[sd] = b
				worst = maxf(worst, Vector2(b.x - anc[sd].x, b.z - anc[sd].z).length())
			else:
				anc.erase(sd)
		tt += 1.0 / 30.0
	return worst


## the same for the scene's foot plants (scripts/foot_plant.gd; the phone-video cleanup records its plants there, not
## as cards' "plant"): the worst the ball moves on the floor within a plant, from where it stood at the plant's t0
func slide_plants(S: Scene, B: Body) -> float:
	var worst := 0.0
	for p in S.plants:
		var bn := "ball" + String(p["foot"]).trim_prefix("foot")
		S.apply(B, float(p["t0"]))
		var a: Vector3 = B.P[bn]
		var tt: float = float(p["t0"])
		while tt <= minf(float(p["t1"]), S.length()):
			S.apply(B, tt)
			var b: Vector3 = B.P[bn]
			worst = maxf(worst, Vector2(b.x - a.x, b.z - a.z).length())
			tt += 1.0 / 30.0
	return worst


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	# 1 the button and the search
	var found := false
	for b in (m.ui_ribbon["ANIMATE"] as Node).find_children("*", "Button", true, false):   # grouped under captions (RR1)
		if String((b as Button).text).contains("From video") or String((b as Button).tooltip_text).begins_with("From video"):   # the ribbon keeps the label as the tooltip
			found = true
	var names := []
	for c in m.ui_cmd.commands:
		names.append(c["name"])
	var by_video := false
	var by_mp4 := false
	for c in m.ui_cmd.commands:
		var hay := (String(c["name"]) + " " + String(c.get("also", ""))).to_lower()
		if c["name"] == "Animation from video":
			by_video = "video" in hay
			by_mp4 = "mp4" in hay
	ok(found and m.ICON_OF.get("From video", "") == "video" and Icons.DRAW.has("video") and by_video and by_mp4,
		"1 ANIMATE has From video (icon %s), the search has Animation from video (video %s, mp4 %s)" % [m.ICON_OF.get("From video", "-"), by_video, by_mp4])
	# 2 a dropped pose file
	var P := VideoImport.load_file("res://refs/video/walk_bat_track.json")
	m._on_drop(PackedStringArray([ProjectSettings.globalize_path("res://refs/video/walk_bat_track.json")]))
	var wp: String = m.scene_path
	var d = JSON.parse_string(FileAccess.get_file_as_string(wp)) if FileAccess.file_exists(wp) else {}
	var locked := 0
	for c in m.S.cards:
		if not (c.get("plant", []) as Array).is_empty():
			locked += 1
	# the cleanup (on by default) plants feet in the scene's "plants" (time ranges), the raw path in cards' "plant":
	# count both, and measure the slide of both
	locked += m.S.plants.size()
	var nf: int = P["frames"].size()
	var dur: float = float(P["frames"][-1]["t"]) - float(P["frames"][0]["t"])
	var nc: int = m.S.cards.size()
	var B1 := Body.new()
	B1.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var slide := maxf(slide_of(m.S, B1), slide_plants(m.S, B1))
	# the control: the same pose file as one card per frame, MocapClean'd, measured the same way (the 1.5 cm bar first
	# registered here came from sampling at card times only; at 30 a second the DENSE scene itself reads 1.56 cm)
	var D := VideoImport.to_scene(B1, VideoImport.solve(B1, P["frames"]), P["fps"], 1, "zz")
	MocapClean.clean(D, B1, {})
	var slide_d := slide_of(D, B1)
	ok(wp.begins_with("res://scenes/_wip/walk_bat_track") and nc <= nf / 2 and nc >= nf / 8 and absf(m.S.length() - dur) < 0.05
		and locked > 0 and slide <= slide_d + 0.005 and String(d.get("plan", "")).contains("MediaPipe"),
		"2 the pose file opened as %s: %d cards for %d frames (bar %d..%d), %.2f s long (video %.2f), %d with a planted foot, planted ball slides %.4f m (bar: dense %.4f + 0.005); plan: %s" % [wp, nc, nf, nf / 8, nf / 2, m.S.length(), dur, locked, slide, slide_d, String(d.get("plan", "")).left(100)])
	print("   status: " + String(m.ui_status.text))
	# 2b UPRIGHT (registered 10-18 after the first real import came out hunched, head dropped, before these numbers): the
	# imported trunk's lean from vertical (pelvis -> neck) and the head's pitch (its bone from vertical) against walk_bat's
	# own at the same moment: trunk mean abs difference <= 5 deg, head <= 10 deg
	var W := Scene.new()
	W.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var B2 := Body.new()
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var tr := 0.0
	var hd := 0.0
	var nn := 0
	for i in nf:
		var t: float = float(P["frames"][i]["t"]) - float(P["frames"][0]["t"])
		m.S.apply(B2, minf(t, m.S.length()))
		var lean_v := rad_to_deg(((B2.P["neck_01"] as Vector3) - (B2.P["pelvis"] as Vector3)).angle_to(Vector3.UP))
		var head_v := rad_to_deg(((B2.E["head"] as Vector3) - (B2.P["head"] as Vector3)).angle_to(Vector3.UP))
		W.apply(B2, minf(t, W.length()))
		var lean_w := rad_to_deg(((B2.P["neck_01"] as Vector3) - (B2.P["pelvis"] as Vector3)).angle_to(Vector3.UP))
		var head_w := rad_to_deg(((B2.E["head"] as Vector3) - (B2.P["head"] as Vector3)).angle_to(Vector3.UP))
		tr += absf(lean_v - lean_w)
		hd += absf(head_v - head_w)
		nn += 1
	ok(tr / nn <= 5.0 and hd / nn <= 10.0, "2b upright: the trunk's lean %.1f deg from walk_bat's on average (bar 5), the head's pitch %.1f (bar 10)" % [tr / nn, hd / nn])
	# 3 refusals
	m._import_video("C:/zz_no_such_video.mp4")
	var s1: String = m.ui_status.text
	var keep_py: String = m.video_python
	m.video_python = "zz_no_python_here"
	var vid := ProjectSettings.globalize_path("res://refs/video/zz_fake.mp4")
	FileAccess.open(vid, FileAccess.WRITE).store_string("not a video")
	m._import_video(vid)
	var s2: String = m.ui_status.text
	ok(s1.contains("no such file") and s2.contains("did not start") and m.scene_path == wp, "3 refused: \"%s\" | \"%s\"" % [s1, s2])
	# 4 a tracker that runs and finds nobody (python on a file that is not a video): polled, then said
	m.video_python = keep_py
	m._import_video(vid)
	var started: bool = m._video_pid >= 0
	var t := 0
	while m._video_pid >= 0 and t < 1200:
		await process_frame
		t += 1
	var s3: String = m.ui_status.text
	ok(started and m._video_pid < 0 and s3.contains("could not track") and m.scene_path == wp, "4 the tracker polled (%d frames), then: \"%s\"" % [t, s3])
	DirAccess.remove_absolute(vid)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(wp))
	m.queue_free()
	print("VIDEO UI TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
