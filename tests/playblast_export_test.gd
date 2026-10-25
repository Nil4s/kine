## godot --path . -s tests/playblast_export_test.gd     (the command "Export playblast (video)"; needs a window: it renders)
## A 3-card built-in scene (24 fps) is exported through the command's own function into user:// (never scenes/, poses/, data/).
## FRAME COUNT = round((b - a) * fps) + 1, with [a, b] the preview range or [0, scene length].
##   1 whole scene: that many PNGs, no more, each the viewport's size; 1b a preview range 0.2..0.6 s: 11 PNGs
##   2 anti-vacuity: the mean |pixel difference| (RGB, 0..1, whole frame) of the frame at the middle and at the end against
##     frame 0 is above DIFF_BAR (the body moves); determinism: two exports are pixel-identical frame by frame;
##     the middle frame equals what the viewport shows when scrubbed to that time by hand (same path as play/scrub)
##   3 ffmpeg on PATH (or POSER_FFMPEG): the .mp4 exists and ffprobe counts the frames; else the message says how to get it
##   4 the app comes back as it was (playhead, panels visible)
##   5 EASY SAVE VIDEO (Easy's strip, Save video), punch and walk templates, timed click -> "Video saved".
##     BASELINE (measured before the change, 1600x900): punch 3445 ms (42 frames), walk 13123 ms (149 frames).
##     BARS: punch <= 2067 ms and walk <= 7874 ms (at least 40 % faster); the frame count and the size (1600x900) are
##     identical to the baseline; the mp4's frames match the baseline's frames within a mean |diff| of 2/255 per
##     channel (the faster x264 preset may move pixels a little; this states how much).
##   6 progress: while the save runs, the big progress line reads "Saving video... k of N frames" and Cancel is shown.
##   7 cancel: a save cancelled part-way leaves no folder and no .mp4 behind, and Easy says it was cancelled.
extends SceneTree

var fails := 0
var m: Node
const DIFF_BAR := 0.0005   # mean abs difference of one 0..1 channel over the whole frame; the body is a few % of the window
var run_id := OS.get_process_id()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pngs(dir: String) -> Array:
	var l := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".png"))
	l.sort()
	return l


func mean_diff(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	if da.size() != db.size():
		return 1.0
	var tot := 0
	for i in da.size():
		tot += absi(int(da[i]) - int(db[i]))
	return float(tot) / float(da.size()) / 255.0


func same(a: Image, b: Image) -> bool:
	return a.get_size() == b.get_size() and a.get_data() == b.get_data()


func pose(thigh: float, arm: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.set_ang("upperarm_r", Vector3(0, 0, arm))
	R.fk()
	return R.to_dict()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_playblast_export"
	S.fps = 24
	var poses := [pose(0, 0), pose(70, 80), pose(-25, -40)]
	for i in 3:
		S.add("c%d" % i, poses[i])
		S.cards[i]["move"] = 0.4
		S.cards[i]["hold"] = 0.1 if i < 2 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.3
	m._refresh()
	await idle(3)
	var slen := S.length()
	var want := roundi(slen * S.fps) + 1
	print("     scene length %.4f s at %d fps: want round(%.4f * %d) + 1 = %d frames" % [slen, S.fps, slen, S.fps, want])
	var base := "user://zz_pb_%d" % run_id
	var vp := Vector2i(root.get_viewport().get_visible_rect().size)

	# 1 whole scene
	var r1: Dictionary = await m._export_playblast(base + "_a", "")
	var d1: String = r1.get("dir", "")
	var l1 := pngs(d1) if d1 != "" else []
	var img0 := Image.load_from_file(d1 + "/" + l1[0]) if not l1.is_empty() else null
	var sized := not l1.is_empty() and img0.get_size() == vp
	for f in l1:
		if sized and Image.load_from_file(d1 + "/" + f).get_size() != vp:
			sized = false
	ok(l1.size() == want and r1.get("frames", -1) == want and DirAccess.get_files_at(d1).size() >= want, "1 the whole scene: %d PNGs (want %d), the folder %s" % [l1.size(), want, d1.get_base_dir().get_file() + "/" + d1.get_file()])
	ok(sized, "  every frame is the viewport's size %s" % [vp])
	ok(d1.get_file().begins_with("zz_playblast_export_"), "  the folder is <scene name>_<timestamp>: %s" % d1.get_file())

	# 2 movement + determinism + same path as the viewport
	var mid := want / 2
	var imid := Image.load_from_file("%s/frame_%04d.png" % [d1, mid])
	var iend := Image.load_from_file("%s/frame_%04d.png" % [d1, want - 1])
	var dm := mean_diff(img0, imid) if imid != null else 0.0
	var de := mean_diff(img0, iend) if iend != null else 0.0
	ok(dm > DIFF_BAR and de > DIFF_BAR, "2 the body moves: mean |diff| of frame %d vs 0 = %.5f, of the last frame vs 0 = %.5f (bar > %.4f)" % [mid, dm, de, DIFF_BAR])
	var r2: Dictionary = await m._export_playblast(base + "_b", "")
	var d2: String = r2.get("dir", "")
	var l2 := pngs(d2) if d2 != "" else []
	var identical := l2.size() == l1.size() and not l1.is_empty()
	var worst := 0.0
	if identical:
		for k in l1.size():
			var a := Image.load_from_file("%s/%s" % [d1, l1[k]])
			var b := Image.load_from_file("%s/%s" % [d2, l2[k]])
			if not same(a, b):
				identical = false
				worst = maxf(worst, mean_diff(a, b))
	ok(identical, "  two exports of the same scene are pixel-identical on all %d frames (worst mean diff %.6f)" % [l1.size(), worst])
	# by hand: scrub to frame `mid`'s time, UI hidden, capture
	var t_mid := float(mid) / S.fps   # independent of the exporter
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	m.playhead = t_mid
	m._ps().apply(m.B, t_mid)
	m._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	var hand: Image = root.get_viewport().get_texture().get_image()
	m.ui_root.visible = true
	m.clean = false
	m._sides_apply()
	ok(imid != null and same(hand, imid), "  frame %d (t = %.4f s) equals the viewport scrubbed there by hand (mean diff %.6f)" % [mid, t_mid, mean_diff(hand, imid) if imid != null else -1.0])

	m.playhead = 0.3
	m._refresh()
	# 1b preview range
	m.pv_in = 0.2
	m.pv_out = 0.6
	var want_b := roundi((0.6 - 0.2) * S.fps) + 1
	var r3: Dictionary = await m._export_playblast(base + "_c", "")
	var l3 := pngs(r3.get("dir", "")) if r3.has("dir") else []
	ok(l3.size() == want_b, "1b preview range 0.2..0.6 s: %d PNGs (want round(0.4 * %d) + 1 = %d)" % [l3.size(), S.fps, want_b])
	m.pv_in = -1.0
	m.pv_out = -1.0

	# 3 ffmpeg
	var ff := PlayblastExport.find_ffmpeg()
	var said: String = m.ui_status.text
	if ff != "":
		print("     BRANCH: ffmpeg found at %s" % ff)
		var mp4: String = r1.get("mp4", "")
		var r4: Dictionary = await m._export_playblast(base + "_d", "")
		mp4 = r4.get("mp4", "")
		var probe := ff.get_base_dir() + "/ffprobe" + (".exe" if OS.get_name() == "Windows" else "")
		var out := []
		var n := -1
		if mp4 != "" and FileAccess.file_exists(mp4):
			OS.execute(probe if FileAccess.file_exists(probe) else "ffprobe", ["-v", "error", "-count_frames", "-select_streams", "v:0",
				"-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", mp4], out, true)
			n = int(String(out[0]).strip_edges()) if not out.is_empty() else -1
		ok(mp4 != "" and FileAccess.file_exists(mp4) and n == want, "3 the .mp4 exists (%s) and ffprobe counts %d frames (want %d)" % [mp4.get_file(), n, want])
		# 3b THE SOUND IS IN THE VIDEO, AT ITS PLACE. A test tone with a gap (sound time: tone 0-0.5 s, quiet 0.5-1.0, tone
		# 1.0-3.0) placed at offset 0.3 s: on the scene's clock the tone runs 0.3-0.8 s. Read back from the .mp4 by decoding
		# its audio (ffmpeg) and finding the loud 10 ms windows: whole scene -> starts 0.3, stops 0.8; preview range
		# 0.5-1.0 (the sound cut with -ss) -> loud from 0, stops 0.3. Bar: 1 frame (1/fps) on each edge
		var wavp := ProjectSettings.globalize_path(base + "_tone.wav")
		_tone_wav(wavp)
		S.audio_tracks = [{"path": wavp, "offset": 0.3, "gain_db": 0.0}]
		var fr := 1.0 / S.fps
		var r6: Dictionary = await m._export_playblast(base + "_f", "")
		var e6 := _edges(ff, probe, r6.get("mp4", ""), ProjectSettings.globalize_path(base + "_f.raw"))
		print("     AUDIO whole scene: stream start %.4f, loud from %.4f to %.4f s (want 0.3 to 0.8)" % e6)
		ok(absf(e6[1] - 0.3) <= fr and absf(e6[2] - 0.8) <= fr, "3b the sound is muxed at its offset: loud from %.3f s to %.3f s (want 0.300 / 0.800, bar 1 frame = %.1f ms)" % [e6[1], e6[2], fr * 1000])
		m.pv_in = 0.5
		m.pv_out = 1.0
		var r7: Dictionary = await m._export_playblast(base + "_g", "")
		var e7 := _edges(ff, probe, r7.get("mp4", ""), ProjectSettings.globalize_path(base + "_g.raw"))
		print("     AUDIO preview 0.5-1.0: stream start %.4f, loud from %.4f to %.4f s (want 0.0 to 0.3)" % e7)
		ok(absf(e7[1]) <= fr and absf(e7[2] - 0.3) <= fr, "3b preview range 0.5-1.0: the sound is cut to the range: loud from %.3f s to %.3f s (want 0.000 / 0.300)" % [e7[1], e7[2]])
		m.pv_in = -1.0
		m.pv_out = -1.0
		S.audio_tracks = []
		for f in [wavp, ProjectSettings.globalize_path(base + "_f.raw"), ProjectSettings.globalize_path(base + "_g.raw")]:
			DirAccess.remove_absolute(f)
	else:
		print("     BRANCH: ffmpeg NOT found (PATH and POSER_FFMPEG): PNG only")
		ok(r1.get("mp4", "x") == "" and said.contains("ffmpeg") and said.contains("install") and said.contains("No .mp4"), "3 no ffmpeg: no .mp4, and the message says how to get it: %s" % said.right(150))
		ok(PlayblastExport.find_ffmpeg("C:/zz_no_such/ffmpeg.exe") == "", "  a configured path that does not exist is not used")

	# 4 refusal + the app is back
	ok(absf(m.playhead - 0.3) < 1e-6 and m.ui_root.visible and not m.clean, "4 after exporting: playhead back at 0.30 (%.2f), panels visible, not in clean mode" % m.playhead)
	var S0: Scene = m.S
	m.S = Scene.new()
	var r5: Dictionary = await m._export_playblast(base + "_e", "")
	ok(r5.is_empty() and m.ui_status.text.contains("NOT NOW") and m.ui_status.text.contains("press Enter"), "  an empty scene is refused and says what to do: %s" % m.ui_status.text.left(90))
	m.S = S0

	# 5 EASY SAVE VIDEO (Easy's Save video) on the punch and walk templates: timed, frame count and size from the .mp4, pixels
	# against the Expert export's PNG frames of the same scene (every 10th frame, decoded from the .mp4)
	m.easy.set_on(true, false)
	await idle(3)
	var home: EasyHome = m.easy.home
	var ff5 := PlayblastExport.find_ffmpeg()
	var probe5 := ff5.get_base_dir() + "/ffprobe" + (".exe" if OS.get_name() == "Windows" else "")
	var ms_of := {}
	for card_i in [3, 0]:
		var nm5 := "punch" if card_i == 3 else "walk"
		m._new_scene()
		await idle(2)
		home.card(card_i)
		var tw := Time.get_ticks_msec()
		while not m.playing and Time.get_ticks_msec() - tw < 60000:
			await process_frame
		await idle(3)
		home.video_root = base + "_easy_" + nm5
		var t0 := Time.get_ticks_msec()
		await home.save_video()
		var ms := Time.get_ticks_msec() - t0
		ms_of[nm5] = ms
		var mp4 := String(home.last_video.get("mp4", ""))
		var want5 := 0
		var n_frames := -1
		var wh := "-"
		if ff5 != "" and mp4 != "" and FileAccess.file_exists(mp4):
			var out := []
			OS.execute(probe5 if FileAccess.file_exists(probe5) else "ffprobe", ["-v", "error", "-count_frames", "-select_streams", "v:0",
				"-show_entries", "stream=width,height,nb_read_frames", "-of", "csv=p=0", mp4], out, true)
			var parts := String(out[0]).strip_edges().split(",") if not out.is_empty() else PackedStringArray()
			if parts.size() == 3:
				wh = "%sx%s" % [parts[0], parts[1]]
				n_frames = int(parts[2])
		print("EASY SAVE %s: %d ms, frames %d, size %s, mp4 %s" % [nm5, ms, n_frames, wh, mp4.get_file()])
		# the reference: the Expert export's PNGs of the same scene (the same renderer, no encoder in between)
		var ref: Dictionary = await m._export_playblast(base + "_ref_" + nm5, "")
		var refl := pngs(ref.get("dir", "")) if ref.has("dir") else []
		var fix := n_frames == refl.size() and n_frames > 0 and wh == "1600x900"
		ok(ms_of[nm5] >= 0 and n_frames == refl.size() and n_frames > 0, "5 %s: the .mp4 has %d frames, the Expert export %d (identical)" % [nm5, n_frames, refl.size()])
		ok(wh == "1600x900" and Image.load_from_file(ref["dir"] + "/" + refl[0]).get_size() == Vector2i(1600, 900), "5 %s: %s, the same size as the viewport's frames" % [nm5, wh])
		var worst5 := 0.0
		var sum := 0.0
		var cnt := 0
		if fix and mp4 != "":
			var raw := ProjectSettings.globalize_path(base + "_" + nm5 + ".raw")
			OS.execute(ff5, ["-y", "-v", "error", "-i", mp4, "-vf", "select=not(mod(n\\,10))", "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", raw], [], true)
			var rb := FileAccess.get_file_as_bytes(raw)
			var fsz := 1600 * 900 * 3
			var k := 0
			for j in range(0, refl.size(), 10):
				if (k + 1) * fsz > rb.size():
					break
				var refi := Image.load_from_file(ref["dir"] + "/" + refl[j])
				refi.convert(Image.FORMAT_RGB8)
				var rd := refi.get_data()
				var tot := 0
				for i in fsz:
					tot += absi(int(rd[i]) - int(rb[k * fsz + i]))
				var md := float(tot) / fsz / 255.0
				sum += md
				worst5 = maxf(worst5, md)
				cnt += 1
				k += 1
			DirAccess.remove_absolute(raw)
		var mean_md := sum / maxf(cnt, 1)
		ok(cnt > 0 and mean_md <= 2.0 / 255.0, "5 %s: pixels match the Expert export: mean |diff| %.5f over %d sampled frames, worst frame %.5f (bar: mean <= 2/255 = %.5f)" % [nm5, mean_md, cnt, worst5, 2.0 / 255.0])
		_rm(ProjectSettings.globalize_path(base + "_easy_" + nm5))
		_rm(ProjectSettings.globalize_path(base + "_ref_" + nm5))
	var base_punch: int = ms_of["punch"]
	var base_walk: int = ms_of["walk"]
	ok(base_punch <= 2067, "5 punch: click to 'Video saved' %d ms (bar <= 2067 = 40 %% faster than the 3445 ms baseline)" % base_punch)
	ok(base_walk <= 7874, "5 walk: click to 'Video saved' %d ms (bar <= 7874 = 40 %% faster than the 13123 ms baseline)" % base_walk)
	print("SPEED: punch %d -> %d ms, walk %d -> %d ms" % [3445, base_punch, 13123, base_walk])

	# 6 progress: "Saving video... k of N frames" shows while it saves, with a Cancel button
	m._new_scene()
	await idle(2)
	home.card(3)
	var tw6 := Time.get_ticks_msec()
	while not m.playing and Time.get_ticks_msec() - tw6 < 60000:
		await process_frame
	await idle(3)
	home.video_root = base + "_cancel"
	home.last_video = {}
	home.save_video()   # not awaited: it runs beside this loop
	var seen := ""
	var cancel_seen := false
	var tp := Time.get_ticks_msec()
	while m._pb_busy and Time.get_ticks_msec() - tp < 120000:
		if m._pb_layer != null and m._pb_layer.visible:
			var txt: String = m._pb_label.text
			if txt.begins_with("Saving video... ") and txt.contains(" of ") and txt.ends_with(" frames"):
				seen = txt
			if m._pb_cancel_btn != null and m._pb_cancel_btn.is_visible_in_tree():
				cancel_seen = true
		if seen != "" and cancel_seen and not m._pb_cancel and not m._pb_label.text.is_empty():
			var k6 := int(seen.split(" ")[2])
			if k6 >= 3:
				m._pb_cancel_btn.pressed.emit()   # 7: Cancel pressed part-way
		await process_frame
	ok(seen != "" and cancel_seen, "6 while saving, the progress line reads 'Saving video... k of N frames' with a Cancel button (last seen: '%s')" % seen)

	# 7 cancel: no folder, no .mp4 left, and the app says it was cancelled
	var left := DirAccess.get_directories_at(base + "_cancel").size() + DirAccess.get_files_at(base + "_cancel").size() if DirAccess.dir_exists_absolute(base + "_cancel") else 0
	var names7 := (Array(DirAccess.get_directories_at(base + "_cancel")) + Array(DirAccess.get_files_at(base + "_cancel"))) if DirAccess.dir_exists_absolute(base + "_cancel") else []
	ok(left == 0 and home.last_video.is_empty() and m.ui_status.text.contains("cancelled"), "7 cancel leaves no file or folder (%d entries left: %s) and says it was cancelled: %s" % [left, str(names7), m.ui_status.text.left(70)])
	ok(absf(m.playhead - 0.3) < 1e-6 or m.ui_root.visible, "7 after cancel the app is back: panels visible (%s)" % str(m.ui_root.visible))
	_rm(ProjectSettings.globalize_path(base + "_cancel"))
	m.easy.set_on(false, false)

	for b in ["_a", "_b", "_c", "_d", "_e", "_f", "_g"]:
		_rm(ProjectSettings.globalize_path(base + b))
	print("PLAYBLAST EXPORT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)


func _rm(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	for d in DirAccess.get_directories_at(p):
		_rm(p + "/" + d)
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p + "/" + f)
	DirAccess.remove_absolute(p)


## 8 kHz mono 16-bit: a 1 kHz tone at half scale over [0, 0.5) and [1.0, 3.0) s, quiet between
func _tone_wav(p: String) -> void:
	var sr := 8000
	var n := sr * 3
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(sr)
	f.store_32(sr * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 2)
	for i in n:
		var t := float(i) / sr
		var v := 0.5 * sin(TAU * 1000.0 * t) if (t < 0.5 or t >= 1.0) else 0.0
		f.store_16(int(round(v * 32767.0)) & 0xFFFF)
	f.close()


## [stream start, first loud time, end of that first loud run] in the .mp4's audio, on the video's clock. Loud = a 10 ms
## window with RMS above 10 % of full scale. [-1, -1, -1] = no audio stream
func _edges(ff: String, probe: String, mp4: String, raw: String) -> Array:
	if mp4 == "" or not FileAccess.file_exists(mp4):
		return [-1.0, -1.0, -1.0]
	var out := []
	OS.execute(probe if FileAccess.file_exists(probe) else "ffprobe", ["-v", "error", "-select_streams", "a:0", "-show_entries",
		"stream=start_time", "-of", "csv=p=0", mp4], out, true)
	var st_s := String(out[0]).strip_edges() if not out.is_empty() else ""
	if st_s == "" or not st_s.is_valid_float():
		return [-1.0, -1.0, -1.0]
	var st := float(st_s)
	OS.execute(ff, ["-y", "-v", "error", "-i", mp4, "-map", "0:a:0", "-ac", "1", "-ar", "8000", "-f", "s16le", raw], [], true)
	var b := FileAccess.get_file_as_bytes(raw)
	var w := 80
	var on := -1.0
	var off := -1.0
	for k in range(0, b.size() / 2 - w, w):
		var acc := 0.0
		for i in w:
			var v := b.decode_s16((k + i) * 2) / 32768.0
			acc += v * v
		var loud := sqrt(acc / w) > 0.1
		var t := st + float(k) / 8000.0
		if loud and on < 0.0:
			on = t
		elif not loud and on >= 0.0:
			off = t
			break
	if on >= 0.0 and off < 0.0:
		off = st + float(b.size() / 2) / 8000.0
	return [st, on, off]
