## godot --path . -s tests/judgerender_test.gd     (ROADMAP_400 K23, the command "Deliver: breakdown video (with the judges drawn)"; needs a window: it renders)
## A two-card clip (a stand, then a deep forward lean that puts the centre of mass past the toes) is delivered as a SIDE-BY-SIDE breakdown through
## the command's own function (1 s at 12 fps, 640x360, all four overlays) into user://breakdowns/. Bars, stated before measuring:
##   1 FRAME COUNT = length * fps (12 at 1 s x 12 fps; a 0.5 s run gives 6); the .avi exists, starts RIFF....AVI
##   2 in side-by-side the LEFT half has no overlay-colour pixel (the judge_force / judge_limit Tok colours and BalanceView's green / amber / red, tolerance 0.06 per
##     channel) and the RIGHT half has at least 30 of them in the frames where the body is drawn (all of them)
##   3 on a frame where the COM is outside the feet (Balance.read margin < 0) the caption text carries "off balance"; on the stand frame it does not
##   4 every overlay toggle equal before / after: bal.on, fd_boxes, force_on, fd_on, clean, big_view, show_caps, ui_root.visible, playing, playhead, dummy_on
##   5 PLACEMENT (whole-body frame): in the saved frame the projected COM lies inside the bounding box of the projected body points, and the COM's floor
##     marker (BalanceView disc) lies inside the support polygon's projected box when the COM is inside (checked on the stand frame)
##   6 the single-view option gives the full width to one picture with the overlays on (right-half logic: overlay pixels across the whole picture)
##   7 only user:// was written: the file counts of scenes/, poses/, data/ are unchanged
## Screenshot: one side-by-side frame (the lean) goes to OUT.
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/judgerender.png"
const TOL := 0.06


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func count_files(d: String) -> int:
	var tot := 0
	for f in DirAccess.get_files_at(d):
		tot += 1
	for sub in DirAccess.get_directories_at(d):
		tot += count_files(d + "/" + sub)
	return tot


func near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < TOL and absf(a.g - b.g) < TOL and absf(a.b - b.b) < TOL


## pixels of img within `rc` that match any overlay colour
func overlay_px(img: Image, rc: Rect2i) -> int:
	var cols := [Tok.c("judge_force"), Tok.c("judge_limit"), BalanceView.GREEN.linear_to_srgb(), BalanceView.AMBER.linear_to_srgb(), BalanceView.RED.linear_to_srgb()]   # BalanceView draws literal vertex colours (linear)
	var n := 0
	for y in range(rc.position.y, rc.position.y + rc.size.y):
		for x in range(rc.position.x, rc.position.x + rc.size.x):
			var p := img.get_pixel(x, y)
			for c in cols:
				if near(p, c):
					n += 1
					break
	return n


func toggles() -> Dictionary:
	return {"bal": m.bal.on, "fd_boxes": m.fd_boxes, "force_on": m.force_on, "fd_on": m.fd_on, "clean": m.clean, "big_view": m.big_view,
		"show_caps": m.show_caps, "ui": m.ui_root.visible, "playing": m.playing, "playhead": m.playhead, "dummy": m.dummy_on, "dummy_view": m.dummy_on}


func proj(r: Dictionary, p: Vector3) -> Vector2:
	m.cam.transform = r["cam"]
	m.cam.h_offset = 0.0
	m.cam.v_offset = 0.0
	var rc: Rect2i = r["crop"]
	var s: Vector2 = m.cam.unproject_position(p)
	var ar: Vector2i = r["area"]
	return Vector2((s.x - rc.position.x) / rc.size.x * ar.x, (s.y - rc.position.y) / rc.size.y * ar.y)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.fk()
	var stand: Dictionary = R.to_dict()
	# the lean: find the smallest forward bend of the trunk + hips that puts the COM outside the feet
	var lean_dict := {}
	var lean_margin := 1.0
	for a in range(10, 60, 5):
		var L := Body.new()
		L.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		L.set_ang("spine_01", Vector3(a * 0.4, 0, 0))
		L.set_ang("spine_02", Vector3(a * 0.3, 0, 0))
		L.set_ang("spine_03", Vector3(a * 0.3, 0, 0))
		L.set_ang("thigh_l", Vector3(a * 0.5, 0, 0))
		L.set_ang("thigh_r", Vector3(a * 0.5, 0, 0))
		L.fk()
		L.ground()
		var mg: float = Balance.read(L)["margin"]
		if mg < -0.03 and not (Balance.read(L)["down"] as Array).is_empty():
			lean_dict = L.to_dict()
			lean_margin = mg
			print("     lean %d deg: COM %.1f cm outside the feet" % [a, -mg * 100.0])
			break
	ok(not lean_dict.is_empty(), "0 a lean that puts the COM outside the feet was found (margin %.3f)" % lean_margin)
	if lean_dict.is_empty():
		quit(1)
		return
	var S := Scene.new()
	S.name = "zz_judgerender"
	S.fps = 12
	S.add("stand", stand)
	S.add("lean", lean_dict)
	S.cards[1]["move"] = 0.5
	S.cards[1]["hold"] = 0.5
	m.yaw = 90.0   # side on: the lean shows
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	await idle(3)
	print("     scene length %.2f s, times %s" % [S.length(), S.times()])
	var counts0 := [count_files("res://scenes"), count_files("res://poses"), count_files("res://data")]
	var tg0 := toggles()
	var n_want := roundi(S.length() * 12.0)

	# 1-5 the side-by-side run
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await m._export_judge_render(true, JudgeRender.ALL, 0, Vector2i(640, 360), JudgeRender.ROOT, "", [0, n_want - 1, n_want / 2])
	print("     render took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var n: int = r.get("frames", 0)
	ok(n == n_want and n > 1 and (r.get("captions", []) as Array).size() == n, "1 frame count = length x fps = %.2f x 12 = %d (got %d, %d captions)" % [S.length(), n_want, n, (r.get("captions", []) as Array).size()])
	if n == 0:
		quit(1)
		return
	var avi: String = r.get("avi", "")
	var fa := FileAccess.open(avi, FileAccess.READ) if avi != "" else null
	var hb := fa.get_buffer(12) if fa != null else PackedByteArray()
	var head4 := (hb.slice(0, 4).get_string_from_ascii() + hb.slice(8, 12).get_string_from_ascii()) if hb.size() == 12 else ""
	ok(fa != null and fa.get_length() > 0 and head4 == "RIFFAVI ", "1 the video %s is %d bytes, header '%s'" % [avi.get_file(), fa.get_length() if fa != null else 0, head4])
	var rs: Dictionary = await m._export_judge_render(true, ["balance"], 0, Vector2i(320, 240))
	ok(rs.get("frames", -1) == n_want, "1 a second run with one overlay also gives %d frames (%d)" % [n_want, rs.get("frames", -1)])

	var imgs: Dictionary = r["images"]
	var ar: Vector2i = r["area"]
	var worst_left := 0
	var least_right := 1 << 30
	for k in imgs:
		var im: Image = imgs[k]
		var lc := overlay_px(im, Rect2i(0, 0, ar.x, ar.y))
		var rc := overlay_px(im, Rect2i(ar.x, 0, ar.x, ar.y))
		print("     frame %d: overlay-colour pixels left %d, right %d" % [k, lc, rc])
		worst_left = maxi(worst_left, lc)
		least_right = mini(least_right, rc)
	ok(worst_left == 0, "2 the left (clean) half has %d overlay-colour pixels in the %d sampled frames (bar 0)" % [worst_left, imgs.size()])
	ok(least_right >= 30, "2 the right half has at least %d overlay-colour pixels in every sampled frame (bar 30)" % least_right)

	# 3 the caption of the lean frame (and none on the stand frame)
	var caps: Array = r["captions"]
	var vds: Array = r["verdicts"]
	var lean_k := -1
	for k in n:
		if (vds[k] as Array).any(func(s): return String(s).begins_with("off balance")):
			lean_k = k
			break
	print("     caption 0: %s" % caps[0])
	print("     caption %d: %s" % [n - 1, caps[n - 1]])
	var Bt: Body = m.B
	m._ps().apply(Bt, JudgeRender.time_of(n - 1, 12))
	var mg_last: float = Balance.read(Bt)["margin"]
	ok(mg_last < 0.0, "3 the last frame is really off balance (margin %.3f m)" % mg_last)
	ok(lean_k >= 0 and String(caps[lean_k]).contains("off balance") and String(caps[n - 1]).contains("off balance"), "3 the caption of frame %d (and of the last frame) says off balance" % lean_k)
	ok(not String(caps[0]).contains("off balance") and String(caps[0]).contains("card 1"), "3 the stand frame's caption does not (and names card 1)")

	# 4 toggles
	var tg1 := toggles()
	ok(tg0 == tg1, "4 every overlay toggle equal before / after: %s" % [tg1 if tg0 == tg1 else [tg0, tg1]])

	# 5 placement in the saved lean frame
	m._ps().apply(Bt, JudgeRender.time_of(n - 1, 12))
	var com: Vector3 = Balance.read(Bt)["com"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in Turntable.points(Bt):
		var q := proj(r, p[0])
		lo = lo.min(q)
		hi = hi.max(q)
	var qc := proj(r, com)
	print("     body box (%.0f,%.0f)-(%.0f,%.0f), COM at (%.0f,%.0f) in the %dx%d half" % [lo.x, lo.y, hi.x, hi.y, qc.x, qc.y, ar.x, ar.y])
	ok(qc.x >= lo.x and qc.x <= hi.x and qc.y >= lo.y and qc.y <= hi.y, "5 the projected COM is inside the body's bounding box")
	ok(lo.x >= 0 and lo.y >= 0 and hi.x <= ar.x and hi.y <= ar.y, "5 the whole body is inside the half (box within 0..%d x 0..%d)" % [ar.x, ar.y])
	# the BalanceView disc (state colour at the COM's floor point) is drawn in the right half
	var im_l: Image = imgs[n - 1]
	var fl := proj(r, Vector3(com.x, 0.0, com.z))
	var hit := 0
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var px := int(fl.x) + ar.x + dx
			var py := int(fl.y) + dy
			if px >= ar.x and px < 2 * ar.x and py >= 0 and py < ar.y and ([BalanceView.RED, BalanceView.AMBER, BalanceView.GREEN].any(func(c): return near(im_l.get_pixel(px, py), c.linear_to_srgb()))):
				hit += 1
	ok(hit > 0, "5 the COM's floor marker (%d balance-coloured pixels within 6 px of its projected place (%.0f,%.0f))" % [hit, fl.x, fl.y])
	im_l.save_png(OUT)
	print("     screenshot saved: %s" % OUT)

	# 6 the single view
	var r1: Dictionary = await m._export_judge_render(false, JudgeRender.ALL, 0, Vector2i(640, 360), JudgeRender.ROOT, "", [n - 1])
	var i1: Image = (r1["images"] as Dictionary).get(n - 1)
	var a1: Vector2i = r1.get("area", Vector2i.ZERO)
	ok(i1 != null and a1.x == 640 and overlay_px(i1, Rect2i(0, 0, a1.x, a1.y)) >= 30, "6 the single view is %s wide with %d overlay-colour pixels" % [a1.x, overlay_px(i1, Rect2i(0, 0, a1.x, a1.y)) if i1 != null else -1])

	# 7 files
	ok(avi.begins_with("user://breakdowns/"), "7 written under user://breakdowns/ (%s)" % avi.get_base_dir())
	var counts1 := [count_files("res://scenes"), count_files("res://poses"), count_files("res://data")]
	ok(counts0 == counts1, "7 file counts of scenes/, poses/, data/ unchanged: %s -> %s" % [counts0, counts1])
	ok(toggles() == tg0, "4 toggles still equal after the other runs")
	print("JUDGERENDER: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
