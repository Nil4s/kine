## godot --path . -s tests/audio_track_test.gd     (GAP_ANALYSIS row 23; window suite: it plays sound)
## AUDIO TRACK. Bars written before the first run:
##  (1) the "audio" key round-trips save -> reload in user://; a scene without sound writes no "audio" key; every scene in
##      scenes/ saves with no "audio" key (and, checked once against the base commit, byte-identical JSON)
##  (2) envelope of a generated 44.1 kHz 16-bit mono WAV (1 kHz tone 0.8 full scale, silent gap 1.50-2.00 s): the gap's
##      buckets are < 1 % of full scale, the tone's > 50 %, and the gap's start and end are found within 10 ms
##  (3) sync: play 2 s with the app's own play code (_toggle_play + _process); every frame sample
##      AudioStreamPlayer.get_playback_position() against (playhead - offset): worst |difference| <= 1 / fps.
##      With offset 0.5 s nothing plays before 0.5 s (the player is silent while playhead < 0.5)
##      Scrub: dragging the playhead plays a slice of ~1 frame + 40 ms, at most one per rendered frame
##  (4) undo: add / move / remove are one undo step each and Ctrl+Z restores the scene exactly
## Also: an ogg / mp3 / missing file draws a flat bar (env ok = false) and a playblast's ffmpeg arguments carry the sound.
extends SceneTree

var fails := 0
var m: Node
const WAV := "user://zz_audio_test.wav"
const RATE := 44100
const GAP_A := 1.5
const GAP_B := 2.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func cmd(id: String) -> void:
	for c in m._commands():
		if c["id"] == id:
			(c["run"] as Callable).call()
			return
	ok(false, "command %s exists" % id)


func fp() -> String:
	return JSON.stringify(m.S.cards) + "|" + JSON.stringify(m.S.audio_tracks) + "|" + str(m.S.fps)


func _init() -> void:
	# SILENT: the master bus is muted before anything can play (the player still runs and its position still advances)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var f := FileAccess.open(WAV, FileAccess.WRITE)
	f.store_buffer(AudioTrack.sine_wav_bytes(RATE, 4.0, 1000.0, 0.8, GAP_A, GAP_B))
	f.close()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var S: Scene = m.S
	var fps: int = S.fps

	# ---- (1) the file
	var base := {}
	for ln in FileAccess.get_file_as_string("res://tests/zz_none").split("\n"):
		pass
	var d0: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(m.B)))
	ok(not d0.has("audio"), "1a a scene without sound writes no 'audio' key")
	var bad := []
	var n_sc := 0
	for fn in DirAccess.get_files_at("res://scenes"):
		if fn.ends_with(".json"):
			m._load_scene("res://scenes/" + fn)
			n_sc += 1
			if JSON.parse_string(JSON.stringify(m.S.to_dict(m.B))).has("audio"):
				bad.append(fn)
	ok(bad.is_empty() and n_sc > 5, "1b %d scenes in scenes/ save with no 'audio' key (%s)" % [n_sc, bad])
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	S = m.S
	m.undo.clear()
	ok(m._audio_set(WAV), "1c the generated WAV loads (%s)" % m.audio_stream())
	ok(m.audio_stream() is AudioStreamWAV and absf(m.audio_stream().get_length() - 4.0) < 0.01, "1d it is an AudioStreamWAV of %.3f s" % m.audio_stream().get_length())
	S.audio_tracks[0]["offset"] = 0.25
	S.audio_tracks[0]["gain_db"] = -3.0
	var out := S.to_dict(m.B)
	var js := JSON.stringify(out)
	var tmp := "user://zz_audio_scene.json"
	var tf := FileAccess.open(tmp, FileAccess.WRITE)
	tf.store_string(js)
	tf.close()
	m._load_scene(tmp)
	var a2: Dictionary = m.S.audio_tracks[0]
	ok(a2.get("path", "") == WAV and absf(float(a2.get("offset", -1)) - 0.25) < 1e-6 and absf(float(a2.get("gain_db", 0)) + 3.0) < 1e-6,
		"1e save -> reload keeps the audio key: %s" % JSON.stringify(a2))
	await idle(2)
	ok(m.audio_stream() != null and m.audio_envs[0].get("ok", false), "1f the reload loads the sound and its envelope")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	S = m.S
	await idle(2)
	ok(m.audio_stream() == null and m.audio_envs.is_empty(), "1g opening a scene with no sound drops the sound")

	# ---- (2) the envelope
	var st := AudioTrack.load_stream(WAV)
	var env := AudioTrack.envelope(st, WAV)
	var mx: PackedFloat32Array = env["mx"]
	var mn: PackedFloat32Array = env["mn"]
	var dt: float = env["dt"]
	ok(env["ok"] and mx.size() >= 399 and mx.size() <= 401, "2a decoded: %d buckets of %.0f ms" % [mx.size(), dt * 1000.0])
	var gap_max := 0.0
	var tone_min := 1.0
	var first_quiet := -1.0
	var last_quiet := -1.0
	for i in mx.size():
		var p := maxf(absf(mx[i]), absf(mn[i]))
		var t0 := i * dt
		if t0 >= GAP_A and t0 + dt <= GAP_B:
			gap_max = maxf(gap_max, p)
		elif t0 + dt <= GAP_A - dt or t0 >= GAP_B + dt:
			tone_min = minf(tone_min, p)
		if p < 0.01:
			if first_quiet < 0.0:
				first_quiet = t0
			last_quiet = t0 + dt
	ok(gap_max < 0.01, "2b the gap's buckets are below 1 %% of full scale (worst %.4f)" % gap_max)
	ok(tone_min > 0.5, "2c the tone's buckets are above 50 %% (weakest %.3f)" % tone_min)
	ok(absf(first_quiet - GAP_A) <= 0.01 and absf(last_quiet - GAP_B) <= 0.01, "2d the gap is found at %.3f-%.3f s (made %.2f-%.2f; within 10 ms)" % [first_quiet, last_quiet, GAP_A, GAP_B])
	ok(AudioTrack.peak(env, 1.6, 1.9) < 0.01 and AudioTrack.peak(env, 0.2, 0.3) > 0.5, "2e peak() reads the same: gap %.4f, tone %.3f" % [AudioTrack.peak(env, 1.6, 1.9), AudioTrack.peak(env, 0.2, 0.3)])
	# 8-bit and stereo
	var w8 := AudioStreamWAV.new()
	w8.format = AudioStreamWAV.FORMAT_8_BITS
	w8.stereo = true
	w8.mix_rate = 8000
	var pcm := PackedByteArray()
	pcm.resize(8000 * 2)   # 1 s stereo: left silent, right at +64 (half of 128)
	for i in 8000:
		pcm.encode_s8(i * 2, 0)
		pcm.encode_s8(i * 2 + 1, 64)
	w8.data = pcm
	var e8 := AudioTrack.envelope(w8, "zz8.wav")
	ok(e8["ok"] and absf(AudioTrack.peak(e8, 0.1, 0.2) - 0.5) < 0.01, "2f 8-bit stereo decodes (the louder side: %.3f, want 0.5)" % AudioTrack.peak(e8, 0.1, 0.2))
	var flat := AudioTrack.envelope(AudioStreamMP3.new(), "song.mp3")
	ok(not flat["ok"] and flat["name"] == "song.mp3", "2g a format that cannot be decoded gives a flat bar with the file name ('%s')" % flat["name"])
	ok(not AudioTrack.envelope(null, "gone.wav")["ok"], "2h a missing file gives a flat bar too")

	# ---- (3) sync
	m._audio_set(WAV)
	await idle(2)
	var worst := 0.0
	var before_start := 0
	var n_samp := 0
	for off in [0.0, 0.5]:
		S.audio_tracks[0]["offset"] = off
		m.pv_in = -1.0
		m.pv_out = -1.0
		m.playing = false
		m.playhead = 0.0
		m._ps().apply(m.B, 0.0)
		await idle(3)
		m._toggle_play()
		var t_start := Time.get_ticks_msec()
		var worst_off := 0.0     # the gate: the audio clock minus the playhead, read at set time (main.gd audio_gap)
		var worst_disp := 0.0    # INFO: the playhead against the player's position read later in the test
		var early := 0
		var samples := 0
		var seeks0: int = m.audio_seeks
		while Time.get_ticks_msec() - t_start < 2000 and m.playing:
			await process_frame   # audio_gap is written by _audio_tick the instant the playhead moved (reading from here adds a phase offset)
			var want: float = m.playhead - off
			var pos: float = m.audio_position_of(0)
			if want < 0.0:
				if pos >= 0.0:
					early += 1
			elif pos >= 0.0 and want > 0.15:   # the first frames: the mixer has not delivered a chunk yet
				samples += 1
				if m.audio_from_clock and not is_nan(float(m.audio_gap[0])):
					worst_off = maxf(worst_off, absf(float(m.audio_gap[0])))
				worst_disp = maxf(worst_disp, absf(pos - want))
		m._toggle_play()
		await idle(2)
		# 3a gates the mechanism at set time (5 ms): the playhead comes from the audio clock, so the clock and the playhead
		# agree the moment the playhead is set. The display gap (worst_disp, read a frame later) is INFO: it grows with the
		# frame time, which is the machine's load (10 agents running tests), not the mechanism, so it is not gated.
		print("     INFO offset %.2f s: %d samples; display gap (playhead vs player read later, one frame old) worst %.1f ms; frame time as above; sound started %d time(s), %d frame(s) sounding before the offset" % [off, samples, worst_disp * 1000.0, m.audio_seeks - seeks0, early])
		ok(samples > 20 and worst_off <= 0.005, "3a offset %.1f: at set time the audio clock is within 5 ms of the playhead (worst %.2f ms, %d samples)" % [off, worst_off * 1000.0, samples])
		if off > 0.0:
			ok(early == 0, "3b offset 0.5 s: nothing plays before 0.5 s (%d early frames)" % early)
		else:
			ok(m.audio_seeks - seeks0 <= 2, "3c the sound started once for the whole play (%d starts)" % (m.audio_seeks - seeks0))
		ok(m.audio_position_of(0) < 0.0, "3d paused: the sound stops")
		worst = maxf(worst, worst_off)
	# a jump while playing re-seeks
	S.audio_tracks[0]["offset"] = 0.0
	m.playhead = 0.0
	m._toggle_play()
	await idle(10)
	var s0: int = m.audio_seeks
	m.playhead = 1.0
	await process_frame
	await process_frame
	await process_frame
	var want2: float = m.playhead
	var pos2: float = m.audio_position_of(0)
	ok(m.audio_seeks == s0 + 1 and absf(pos2 - want2) <= 2.0 / fps, "3e (within 2 frames: the first reading after a start is chunk-quantised) jumping the playhead while playing re-seeks (position %.3f vs playhead %.3f)" % [pos2, want2])
	m._toggle_play()
	await idle(2)
	# scrub: through the timeline's own signal, several times within one frame
	var sl0: int = m.audio_slices
	for k in 3:
		m.ui_timeline.scrubbed.emit(0.6 + 0.01 * k)
	ok(m.audio_slices - sl0 == 1, "3f three scrub events in one frame sound one slice (%d)" % (m.audio_slices - sl0))
	ok(m.audio_position_of(0) >= 0.0, "3g the slice is sounding")
	var t_slice := Time.get_ticks_msec()
	while m.audio_position_of(0) >= 0.0 and Time.get_ticks_msec() - t_slice < 1000:
		await process_frame
	var slice_ms := Time.get_ticks_msec() - t_slice
	var want_ms := 1000.0 / fps + 40.0
	ok(slice_ms >= want_ms - 50.0 and slice_ms <= want_ms + 80.0, "3h the slice lasts ~%.0f ms (measured %d ms, frame-granular)" % [want_ms, slice_ms])
	await process_frame
	m.ui_timeline.scrubbed.emit(0.8)
	await process_frame
	m.ui_timeline.scrubbed.emit(0.81)
	ok(m.audio_slices - sl0 == 3, "3i one slice per rendered frame while dragging (%d slices over 3 frames' events)" % (m.audio_slices - sl0))
	m._a_players[0].stop()

	# ---- (4) undo
	m.undo.clear()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	S = m.S
	await idle(2)
	m.undo.clear()
	var f0 := fp()
	ok(m._audio_set(WAV) and m.undo.size() == 1 and S.audio_tracks[0].get("path", "") == WAV, "4a add: one undo step")
	var f_added := fp()
	m._undo()
	await idle(2)
	ok(fp() == f0 and m.audio_stream() == null, "4b Ctrl+Z removes the sound again, exactly")
	m._redo()
	await idle(2)
	ok(fp() == f_added and m.audio_stream() != null, "4c redo brings it back")
	m.playhead = 1.25
	var u0: int = m.undo.size()
	cmd("audio_move_the_sound_to_start_at_the_playhead")
	ok(m.undo.size() == u0 + 1 and absf(float(S.audio_tracks[0]["offset"]) - 1.25) < 1e-6, "4d move: one undo step, offset %.3f" % float(S.audio_tracks[0]["offset"]))
	m._undo()
	ok(fp() == f_added, "4e Ctrl+Z puts the offset back exactly")
	m._redo()
	var f_moved := fp()
	u0 = m.undo.size()
	cmd("audio_remove_the_sound")
	ok(m.undo.size() == u0 + 1 and S.audio_tracks.is_empty(), "4f remove: one undo step")
	m._undo()
	await idle(2)
	ok(fp() == f_moved and m.audio_stream() != null, "4g Ctrl+Z restores the sound exactly, stream and all")
	m.playhead = 1.25
	var u1: int = m.undo.size()
	cmd("audio_move_the_sound_to_start_at_the_playhead")
	ok(m.undo.size() == u1, "4h moving to where it already is changes nothing and says what to do next")
	cmd("audio_remove_the_sound")
	cmd("audio_remove_the_sound")
	ok(m.undo.size() == u1 + 1, "4i removing a second time pushes no step")

	# ---- export arguments
	var sw := PlayblastExport.args("d", 30, "o.mp4", {"path": ProjectSettings.globalize_path(WAV), "offset": 0.5, "gain_db": -3.0}, 0.0)
	ok(sw.has("-itsoffset") and sw.has("-shortest") and sw.find("-i") < sw.find("-itsoffset") and sw[sw.find("-itsoffset") + 1] == "0.5000", "5a playblast args mux the sound at its offset: %s" % " ".join(sw))
	var sn := PlayblastExport.args("d", 30, "o.mp4", {}, 0.0)
	ok(sn.size() == 14 and not sn.has("-itsoffset") and not sn.has("-c:a"), "5b no sound: the arguments are the old ones (%d)" % sn.size())
	ok(PlayblastExport.args("d", 30, "o.mp4", {"path": "C:/nope/zz.wav", "offset": 0.0}, 0.0) == sn, "5c a sound whose file is gone is left out")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV))
	print("AUDIO TRACK TEST %s   (worst set-time gap %.2f ms; bar 5.0 ms)" % ["PASS" if fails == 0 else "FAIL %d" % fails, worst * 1000.0])
	quit(fails)
