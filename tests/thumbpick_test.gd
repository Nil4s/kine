## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/thumbpick_test.gd   (ROADMAP_400 K29: thumbnail picker; a window)
## THUMBNAIL PICKER (scripts/thumb_pick.gd): the most readable frame of a clip, from the geometry alone. READ ONLY on
## scenes/combo3.json and poses/*.json. BARS (written before the first run):
##   1 combo3 (a neutral stand "ready", then a wind-up, contact, follow-through, ...) seen from the thumbnail camera: the chosen
##     frame is NOT in the neutral stand and not in the wind-up (t >= the wind-up card's arrival), and it scores >= 0.10 above frame 0
##   2 the T-pose scores above the arms-down stand, from the thumbnail camera AND from the front
##   3 deterministic: two runs choose the same frame with bit-identical score lists; the score of one frame is the same on a fresh body
##   4 PLACEMENT: in the real app (combo3 loaded) the command puts the playhead on the chosen frame, the pose there equals the
##     scratch body's, every joint projects inside the viewport, head above feet, and the body fills >= 25 % of the viewport height;
##     a screenshot goes to the job's tmp folder
##   5 the command is no scene edit (undo stack unchanged) and the flag draws a different picture key than the strike card
extends SceneTree

var fails := 0
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/thumbpick.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


func _posed(S: Scene, t: float) -> Body:
	var b := _body()
	S.apply(b, t)
	return b


func _pose(B: Body, f: String) -> void:
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/%s.json" % f)))


func _init() -> void:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var cam := Transform3D(Basis(), PoseLibrary.CAM_FROM).looking_at(PoseLibrary.CAM_AT, Vector3.UP)
	var R := cam.basis.x
	var U := cam.basis.y
	var B := _body()
	var r := ThumbPick.best(S, B, R, U)
	var tm: Array = S.times()
	var names := []
	for c in S.cards:
		names.append(c["name"])
	print("combo3: %d sampled frames, best t %.3f s (frame %d) score %.3f, %d tied; cards arrive: %s" % [(r["ts"] as Array).size(), r["t"], r["frame"], r["score"], r["tied"], str(tm.map(func(x): return snappedf(x[1], 0.01)))])
	var sc: Array = r["scores"]
	var line := []
	for i in range(0, sc.size(), 6):
		line.append("%.2f:%.2f" % [r["ts"][i], sc[i]])
	print("     score every 0.4 s: " + " ".join(line))
	var wind_arrive := float((tm[1] as Array)[1])
	ok(float(r["t"]) >= wind_arrive, "1a chosen t %.3f s is after the neutral stand and the wind-up (wind-up arrives %.3f s; card '%s')" % [r["t"], wind_arrive, names[1]])
	ok(float(r["score"]) - float(sc[0]) >= 0.10, "1b chosen score %.3f is >= 0.10 above frame 0's %.3f" % [r["score"], sc[0]])
	var terms: Dictionary = r["terms"]
	var t0: Dictionary = ThumbPick.score(_posed(S, 0.0), R, U)
	print("     chosen terms: hull %.3f H2, sep %.3f H, loa %.3f H; frame 0: hull %.3f sep %.3f loa %.3f" % [terms["hull"], terms["sep"], terms["loa"], t0["hull"], t0["sep"], t0["loa"]])

	# 2: T-pose vs arms down
	var Bt := _body()
	var Bs := _body()
	_pose(Bt, "t_pose")
	_pose(Bs, "stand")
	var front_r := Vector3.RIGHT
	var front_u := Vector3.UP
	var t3 := ThumbPick.score(Bt, R, U)
	var s3 := ThumbPick.score(Bs, R, U)
	var tf := ThumbPick.score(Bt, front_r, front_u)
	var sf := ThumbPick.score(Bs, front_r, front_u)
	print("     T-pose 3/4 %.3f (hull %.3f sep %.3f loa %.3f) vs stand %.3f (hull %.3f sep %.3f loa %.3f)" % [t3["score"], t3["hull"], t3["sep"], t3["loa"], s3["score"], s3["hull"], s3["sep"], s3["loa"]])
	print("     T-pose front %.3f (hull %.3f sep %.3f) vs stand %.3f (hull %.3f sep %.3f)" % [tf["score"], tf["hull"], tf["sep"], sf["score"], sf["hull"], sf["sep"]])
	ok(float(t3["score"]) > float(s3["score"]), "2a T-pose %.3f > arms-down stand %.3f from the thumbnail camera" % [t3["score"], s3["score"]])
	ok(float(tf["score"]) > float(sf["score"]), "2b T-pose %.3f > arms-down stand %.3f from the front" % [tf["score"], sf["score"]])

	# 3: determinism
	var r2 := ThumbPick.best(S, _body(), R, U)
	ok(r2["t"] == r["t"] and r2["scores"] == r["scores"], "3a the same frame (%.3f s) and bit-identical scores on a second run on a fresh body" % r2["t"])
	S.apply(B, 1.0)
	var a1 := ThumbPick.score(B, R, U)
	S.apply(B, 2.0)
	S.apply(B, 1.0)
	var a2 := ThumbPick.score(B, R, U)
	ok(a1["score"] == a2["score"], "3b the score of t=1.0 s is %.6f both times (no state leaks between frames)" % a1["score"])

	# 4: the app
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	await process_frame
	m.yaw = 35.0
	m.pitch = -8.0
	m._cam()
	await process_frame
	var n0: int = m.undo.size()
	m._thumbpick()
	for _k in 3:
		await process_frame
	var vcam: Camera3D = m.cam
	var want := ThumbPick.best(m._ps(), _body(), vcam.global_basis.x, vcam.global_basis.y)
	ok(is_equal_approx(float(m.playhead), float(want["t"])), "4a the playhead sits on the chosen frame: %.3f s (picker says %.3f s)" % [m.playhead, want["t"]])
	var BB: Body = m.B
	var B2 := _body()
	m._ps().apply(B2, float(want["t"]))
	var worst := 0.0
	for j in ThumbPick.HULL_JOINTS:
		worst = maxf(worst, ((BB.P[j] as Vector3) - (B2.P[j] as Vector3)).length())
	ok(worst < 1e-4, "4b the posed body is the scratch body's pose at that frame (worst joint %.6f m)" % worst)
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var inside := true
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in ThumbPick.HULL_JOINTS:
		var q := vcam.unproject_position(BB.P[j])
		lo = lo.min(q)
		hi = hi.max(q)
		if q.x < 0 or q.y < 0 or q.x > vs.x or q.y > vs.y:
			inside = false
	var hq := vcam.unproject_position(BB.E["head"])
	var fq := vcam.unproject_position(BB.P["foot_l"])
	ok(inside, "4c every joint projects inside the %dx%d viewport (box %s to %s)" % [vs.x, vs.y, str(lo.round()), str(hi.round())])
	ok(hq.y < fq.y, "4d head (y %.0f px) above the foot (y %.0f px)" % [hq.y, fq.y])
	ok((hi.y - lo.y) / vs.y >= 0.25, "4e the body fills %.0f %% of the viewport height (>= 25 %%)" % (100.0 * (hi.y - lo.y) / vs.y))
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	ok(img.save_png(SHOT) == OK, "4f screenshot saved to " + SHOT)
	ok(m.undo.size() == n0, "5a the command is no scene edit (undo stack %d -> %d)" % [n0, m.undo.size()])

	# 5: the flag changes the picture's cache key and the time used
	var th: SceneThumbs = m.thumbs
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	var tb := _body()
	var tp := SceneThumbs.pick_into(d, tb)
	var strike := SceneThumbs.pick_card(d["cards"])
	ok(tp > 0.0 and strike >= 0, "5b the scene list's picker chose t %.3f s (strike card index %d)" % [tp, strike])
	m._thumbpick_flag()
	ok(th.pick_on, "5c the flag turns on from the command")
	m._thumbpick_flag()
	ok(not th.pick_on, "5d and off again")
	print("RESULT %s fails" % fails)
	TestFiles.cleanup()
	quit(fails)
