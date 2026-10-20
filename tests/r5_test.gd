## godot --path . -s tests/r5_test.gd     (ROADMAP round 2, R5: Render shots to video (mp4); needs a window: it renders)
## A 3-card scene at 30 fps with TWO shots (Wide from 0 s, Close cut at 1.2 s = frame 36). Output goes to user:// only.
## BARS (stated before measuring):
##   1 frame count: the PNGs, and ffprobe's counted frames of the .mp4, both = round(duration * fps); the mp4's duration is within
##     one frame time of the scene's length
##   2 the cut: in the DECODED mp4, the mean |pixel difference| between consecutive frames peaks at index 36 (frame 35 -> 36),
##     and that peak is >= 4x the median of all the other steps (the body moves a little every frame; a cut moves the whole picture)
##   3 shot order: frames before the cut equal the Wide camera's render, after it the Close camera's (checked on PNGs 35 and 36
##     against a look-through render by hand, 0 px differ), i.e. ShotRender.ranges = [0..35] shot 1, [36..N-1] shot 2
##   4 progress: while it runs the panel is visible, the bar rises (monotonic, ends > 90) and the label names frame and shot;
##     PLACEMENT: the panel lies whole inside the window, in its top third, centred; the DELIVER page's ribbon has the button
##     "Render shots (mp4)" with an icon; screenshot of the DELIVER page while running: env ZZ_R5_SHOT
##   5 cancel: pressing Cancel after ~8 frames stops it: fewer PNGs than N, no .mp4, panel hidden, playhead and body as before
##   6 no shots: refuses ({}), and the message names the next step
extends SceneTree

var fails := 0
var m: Node
var run_id := OS.get_process_id()
var shot_img: Image
var shot_path := ""
var frames_seen := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pose(thigh: float, arm: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.set_ang("upperarm_r", Vector3(0, 0, arm))
	R.fk()
	return R.to_dict()


func key(t: float, p: Vector3, a: Vector3, f: float) -> Dictionary:
	return {"t": t, "pos": p, "aim": a, "f": f}


func mean_diff(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	if da.size() != db.size():
		return 1.0
	var tot := 0
	for i in da.size():
		tot += absi(int(da[i]) - int(db[i]))
	return float(tot) / float(da.size()) / 255.0


func ndiff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var da := a.get_data()
	var db := b.get_data()
	if da == db:
		return 0
	var n := 0
	var st := 3 if a.get_format() == Image.FORMAT_RGB8 else 4
	for i in range(0, da.size(), st):
		if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2]:
			n += 1
	return n


func pngs(dir: String) -> Array:
	var l := Array(DirAccess.get_files_at(dir)).filter(func(f): return String(f).ends_with(".png"))
	l.sort()
	return l


## the frame-post-draw hook: the first draw where the panel AND the UI are both showing is the screenshot
func _on_drawn() -> void:
	frames_seen += 1
	if shot_img == null and m._sr_busy and m._sr_layer != null and m._sr_layer.visible and m.ui_root.visible and m._sr_bar.value > 20.0:
		shot_img = root.get_viewport().get_texture().get_image()
		if shot_path != "":
			shot_img.save_png(shot_path)


func _init() -> void:
	shot_path = OS.get_environment("ZZ_R5_SHOT")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_r5"
	S.fps = 30
	var poses := [pose(0, 0), pose(70, 80), pose(-25, -40)]
	for i in 3:
		S.add("c%d" % i, poses[i])
		S.cards[i]["move"] = 0.8
		S.cards[i]["hold"] = 0.6 if i < 2 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.5
	m._refresh()
	await idle(3)
	var L: float = m._ps().length()
	var N := roundi(L * S.fps)
	var base := "user://zz_r5_%d" % run_id
	var PA := Vector3(2.8, 1.3, -1.2)
	var PB := Vector3(-2.0, 1.5, 1.8)
	S.shots = [
		{"t": 0.0, "name": "Wide", "keys": [key(0.0, PA, Vector3(0, 1.0, 0), 50.0)]},
		{"t": 1.2, "name": "Close", "keys": [key(1.2, PB, Vector3(0.4, 1.1, 0.1), 35.0)]},
	]
	var CUT := 36
	print("     scene %.4f s at %d fps: N = round(%.4f * %d) = %d frames; cut at frame %d" % [L, S.fps, L, S.fps, N, CUT])

	# 6 no shots (checked first, on a copy of the list)
	var keep_shots: Array = S.shots
	S.shots = []
	var r0: Dictionary = await m._render_shots(base + "_none", "")
	ok(r0.is_empty() and m.ui_status.text.contains("no shots") and m.ui_status.text.contains("Shots: add"), "6 no shots: refused with a next step: '%s'" % m.ui_status.text.left(90))
	S.shots = keep_shots

	# the DELIVER page: the button
	m._page_set("DELIVER")
	await idle(3)
	var btn: Button = null
	for d in m.ui_ribbon["EXPORT"].find_children("*", "Button", true, false):
		if m.label_of(d) == "Render shots (mp4)":
			btn = d
	if btn == null:
		for d in m.ui_ribbon["EXPORT"].find_children("*", "Button", true, false):
			print("     ribbon button: '%s'" % m.label_of(d))
	ok(btn != null, "4 the DELIVER page has the button 'Render shots (mp4)'")
	ok(btn != null and btn.icon != null, "  and it has an icon")
	var cmd_found := false
	for e in m._commands():
		if String(e["name"]) == "Render shots to video (mp4)":
			cmd_found = true
	ok(cmd_found, "  the command 'Render shots to video (mp4)' is in the command list")

	# the ranges
	var rg := ShotRender.ranges(S.shots, L, S.fps)
	ok(rg.size() == 2 and rg[0]["first"] == 0 and rg[0]["count"] == CUT and rg[1]["first"] == CUT and rg[1]["count"] == N - CUT, "3 ranges: shot 1 = frames 0..%d, shot 2 = %d..%d: %s" % [CUT - 1, CUT, N - 1, rg])

	# look-through references for frames 35 and 36
	var by_hand := func(f: int) -> Image:
		m.clean = true
		m._sides_apply()
		m.ui_root.visible = false
		await process_frame
		var sb: Dictionary = m._shot_blast_begin()
		m.playhead = float(f) / S.fps
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		m._shot_blast_frame(sb)
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = m._shot_blast_image(sb, root.get_viewport().get_texture().get_image())
		m._shot_blast_end(sb)
		m.ui_root.visible = true
		m.clean = false
		m._sides_apply()
		return img
	var ref35: Image = await by_hand.call(CUT - 1)
	var ref36: Image = await by_hand.call(CUT)
	m.playhead = 0.5
	m._refresh()
	await idle(2)

	# run 1: the whole render, sampling the progress each frame
	RenderingServer.frame_post_draw.connect(_on_drawn)
	var t_before: float = m.playhead
	var vals := []
	var labels := []
	var panel_rect := Rect2()
	m._render_shots(base + "_a", "")
	var guard := 0
	while m._sr_busy and guard < 6000:
		await process_frame
		guard += 1
		if m._sr_layer != null and m._sr_layer.visible:
			vals.append(m._sr_bar.value)
			labels.append(m._sr_label.text)
			if panel_rect.size == Vector2.ZERO:
				panel_rect = (m._sr_layer.get_node("panel") as Control).get_global_rect()
	RenderingServer.frame_post_draw.disconnect(_on_drawn)
	await idle(2)
	var dir := ""
	var mp4 := ""
	# the result comes from the signal; find the folder by scanning user://
	var da := DirAccess.open("user://")
	for d in da.get_directories():
		if d == "zz_r5_%d_a" % run_id:
			dir = ProjectSettings.globalize_path("user://" + d)
	var sub := ""
	if dir != "":
		for d in DirAccess.get_directories_at(dir):
			sub = dir + "/" + d
	var l1 := pngs(sub) if sub != "" else []
	var ff := PlayblastExport.find_ffmpeg("")
	var fp := ShotRender.ffprobe_of(ff)
	mp4 = sub + "/zz_r5.mp4"
	ok(ff != "" and fp != "" and FileAccess.file_exists(mp4), "  ffmpeg %s, ffprobe found, the mp4 exists: %s" % [ff.get_file(), mp4.get_file()])

	# 1 frame count
	var out := []
	OS.execute(fp, ["-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", mp4], out, true)
	var nb := int(String(out[0]).strip_edges()) if not out.is_empty() else -1
	out = []
	OS.execute(fp, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", mp4], out, true)
	var dur := float(String(out[0]).strip_edges()) if not out.is_empty() else -1.0
	ok(l1.size() == N and nb == N, "1 frame count: %d PNGs, ffprobe counts %d frames in the mp4 (want round(%.4f s * %d fps) = %d)" % [l1.size(), nb, L, S.fps, N])
	ok(absf(dur - L) <= 1.0 / S.fps + 0.001, "  the mp4 lasts %.4f s; the scene %.4f s (within one frame, %.4f s)" % [dur, L, 1.0 / S.fps])

	# 2 the cut in the decoded video
	var dec := "user://zz_r5_%d_dec" % run_id
	DirAccess.make_dir_recursive_absolute(dec)
	var gdec := ProjectSettings.globalize_path(dec)
	OS.execute(ff, ["-y", "-loglevel", "error", "-i", mp4, gdec + "/d_%04d.png"], [], true)
	var diffs := []   # diffs[k] = difference of decoded frame k-1 and k (k >= 1)
	var prev: Image = Image.load_from_file(gdec + "/d_0001.png")
	diffs.append(0.0)
	for k in range(1, N):
		var cur: Image = Image.load_from_file("%s/d_%04d.png" % [gdec, k + 1])
		diffs.append(mean_diff(prev, cur) if prev != null and cur != null else -1.0)
		prev = cur
	var best := 1
	for k in range(1, N):
		if diffs[k] > diffs[best]:
			best = k
	var rest := []
	for k in range(1, N):
		if k != best:
			rest.append(diffs[k])
	rest.sort()
	var med: float = rest[rest.size() / 2] if not rest.is_empty() else 0.0
	ok(best == CUT and diffs[best] >= 4.0 * med, "2 the cut: the frame-to-frame difference of the mp4 peaks at frame %d (want %d): %.5f, the median of the others %.5f (ratio %.1f, bar >= 4)" % [best, CUT, diffs[best], med, diffs[best] / maxf(med, 1e-9)])

	# 3 the PNGs are the two cameras' renders
	var f35 := Image.load_from_file("%s/frame_%04d.png" % [sub, CUT - 1])
	var f36 := Image.load_from_file("%s/frame_%04d.png" % [sub, CUT])
	var n35 := ndiff(f35, ref35)
	var n36 := ndiff(f36, ref36)
	if n35 != 0 or n36 != 0:
		ref35.save_png("user://zz_r5_ref35.png")
		f35.save_png("user://zz_r5_f35.png")
		print("     saved ", ProjectSettings.globalize_path("user://zz_r5_f35.png"))
	ok(n35 == 0 and n36 == 0, "3 frame 35 = the Wide camera's render (%d px differ), frame 36 = the Close camera's (%d px differ)" % [n35, n36])

	# 4 progress
	var mono := vals.size() > 5
	for k in range(1, vals.size()):
		if vals[k] < vals[k - 1] - 1e-6:
			mono = false
	var top: float = vals.max() if not vals.is_empty() else 0.0
	ok(mono and top > 90.0, "4 the bar rose monotonically over %d samples to %.1f%%" % [vals.size(), top])
	var lab_ok := not labels.is_empty() and String(labels[0]).contains("of %d" % N)
	var saw_close := false
	for t in labels:
		if String(t).contains("Close"):
			saw_close = true
	ok(lab_ok and saw_close, "  the label names the frame and shot: '%s' ... saw the Close shot: %s" % [labels[0] if not labels.is_empty() else "", saw_close])
	var vp := Rect2(Vector2.ZERO, Vector2(root.get_viewport().get_visible_rect().size))
	var cx := panel_rect.get_center().x
	ok(vp.encloses(panel_rect) and panel_rect.end.y < vp.size.y / 3.0 and absf(cx - vp.size.x / 2.0) < 2.0, "  PLACEMENT: the panel %s is inside the window %s, in its top third, centred (centre x %.1f)" % [panel_rect, vp.size, cx])
	print("     post-draw hook fired %d times" % frames_seen)
	ok(shot_img != null, "  a screenshot of the DELIVER page with the render running was taken: %s" % shot_path)
	ok(m.playhead == t_before and not m._sr_layer.visible and m.ui_root.visible, "  afterwards the playhead is back (%.3f), the panel hidden, the UI shown" % m.playhead)

	# 5 cancel
	m.playhead = 0.5
	var body_before: Dictionary = m.B.state()
	var cres := []
	m.shots_render_done.connect(func(r): cres.append(r))
	m._render_shots(base + "_b", "")
	guard = 0
	while m._sr_busy and m._sr_bar.value < 7.0 / N * 100.0 and guard < 2000:
		await process_frame
		guard += 1
	(m._sr_layer.find_child("cancel", true, false) as Button).pressed.emit()
	guard = 0
	while m._sr_busy and guard < 600:
		await process_frame
		guard += 1
	await idle(2)
	var cr: Dictionary = cres[0] if not cres.is_empty() else {}
	var made := int(cr.get("frames", -1))
	ok(cr.get("cancelled", false) and made > 0 and made < N and cr.get("mp4", "x") == "", "5 cancel: stopped after %d of %d frames, cancelled = %s, no mp4 (%s)" % [made, N, cr.get("cancelled", false), cr.get("mp4", "?")])
	var cdir := String(cr.get("dir", ""))
	ok(cdir != "" and pngs(cdir).size() == made and not FileAccess.file_exists(cdir + "/zz_r5.mp4"), "  the folder holds exactly the %d frames made and no mp4" % made)
	ok(m.playhead == 0.5 and not m._sr_layer.visible and m.ui_root.visible and m.B.state() == body_before and not m._sr_busy, "  the app is back: playhead 0.5, panel hidden, UI shown, body unchanged, not busy; status: '%s'" % m.ui_status.text.left(60))

	# clean up (user:// only)
	for p in [base + "_a", base + "_b", base + "_none", dec]:
		_rm(ProjectSettings.globalize_path(p) if p.begins_with("user://") else p)
	print("R5 %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + f)
	for d in DirAccess.get_directories_at(path):
		_rm(path + "/" + d)
	DirAccess.remove_absolute(path)
