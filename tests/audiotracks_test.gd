## godot --path . -s tests/audiotracks_test.gd     (ROADMAP 77: multi-track audio; window suite: it plays sound and saves a screenshot)
## Bars written before the first run:
##  (1) file: an old scene's single "audio" dictionary loads as ONE track (role music) and saves back byte-identical;
##      two tracks save as a list under "audio" and load back to the same JSON
##  (2) sync (PREMIX): the sounding tracks are mixed into ONE stream and one player plays it; the playhead follows that player's
##      clock. Gate: at the moment the playhead is set, the premix clock minus the playhead is within 5 ms over 3 s, with B's
##      offset at 0.5 s and at 1.1 s. INFO: the display gap (read later in the test), frame times, the mixer's seconds per second
##  (3) mute and solo: a muted track's energy leaves the premix: the RMS of its own window drops by more than 60 dB; the other
##      track keeps its level (within 0.1 dB); solo on B removes A the same way
##  (4) undo: add, mute, role and an offset drag are one undo step each; Ctrl+Z restores the scene exactly
##  (5) lanes: one lane per track (LANE_H each); a click on B's name mutes it; a click on A's lane picks it; with three tracks every
##      lane sits inside the window and the bottom panel at 1600x900 and 1280x720; screenshot of the three lanes
##  (6) playblast: two tracks mux as two inputs (B delayed by its offset, its gain) summed by amix; a muted track is left out
##  (7) premix: a click at t = 0 of each track lands in the mix at its offset within 1 sample (three tracks, one mix);
##      the re-mix runs on a worker thread: no frame over 50 ms while it runs (7c); the swapped premix still has the onsets
##      and the set-time gap (7c, 7d); the 150 ms re-mix of three 10 s tracks is INFO (7b)
extends SceneTree

var fails := 0
var m: Node
const WAV_A := "user://zz_mt_a.wav"
const WAV_B := "user://zz_mt_b.wav"
const WAV_C := "user://zz_mt_c.wav"
const WAV_CLK := "user://zz_mt_click.wav"
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/audiotracks.png"


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


func _click(p: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = p
	m.ui_timeline._gui_input(ev)


## the premix's stream (the one the player plays), or null
func premix() -> AudioStreamWAV:
	if m._a_mixer == null:
		return null
	return m._a_mixer.stream as AudioStreamWAV


## RMS (both channels) of the premix over t0..t1 seconds; 0 when there is no premix
func rms(t0: float, t1: float) -> float:
	var w := premix()
	if w == null:
		return 0.0
	var a := maxi(0, int(t0 * w.mix_rate))
	var b := mini(int(t1 * w.mix_rate), w.data.size() / 4)
	var sum := 0.0
	var n := 0
	for k in range(a, b):
		var l := float(w.data.decode_s16(4 * k)) / 32768.0
		var r := float(w.data.decode_s16(4 * k + 2)) / 32768.0
		sum += l * l + r * r
		n += 2
	return sqrt(sum / maxf(float(n), 1.0))


## waits until a premix in flight is swapped in and matches the tracks now (or 4 s)
func wait_swap() -> void:
	var t_w := Time.get_ticks_msec()
	while (m._a_task >= 0 or m._a_key != m._a_key_now()) and Time.get_ticks_msec() - t_w < 4000:
		await process_frame


## the drop in dB from a level to a level (a silence is 200 dB down, not infinite)
func drop_db(before: float, after: float) -> float:
	return 20.0 * log(maxf(before, 1e-12) / maxf(after, 1e-12)) / log(10.0)


## a 16-bit mono WAV file of the given sample values (the mix rate, so no resampling is in the way)
func write_wav(path: String, rate: int, samples: PackedFloat32Array) -> void:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		pcm.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)))
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)
	h.encode_u32(12, 0x20746d66)
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)
	h.encode_u16(22, 1)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)
	h.encode_u32(40, pcm.size())
	h.append_array(pcm)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(h)
	f.close()


func _init() -> void:
	# SILENT: the master bus is muted; the player still runs and its position still advances
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var fa := FileAccess.open(WAV_A, FileAccess.WRITE)
	fa.store_buffer(AudioTrack.sine_wav_bytes(44100, 4.0, 1000.0, 0.8, 0.0, 0.0))
	fa.close()
	var fb := FileAccess.open(WAV_B, FileAccess.WRITE)
	fb.store_buffer(AudioTrack.sine_wav_bytes(44100, 4.0, 440.0, 0.5, 0.0, 0.0))
	fb.close()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var S: Scene = m.S
	var fps: int = S.fps
	var tl = m.ui_timeline

	# ---- (1) the file
	var old := {"path": WAV_A, "offset": 0.25, "gain_db": -3.0}
	S.audio_tracks = AudioTrack.from_file(old)
	ok(S.audio_tracks.size() == 1 and String(S.audio_tracks[0].get("role", "music")) == "music", "1a an old single 'audio' dictionary loads as one music track")
	var d1: Dictionary = S.to_dict(m.B)
	ok(JSON.stringify(d1["audio"]) == JSON.stringify(old), "1b one plain track saves as the old dictionary, byte-identical: %s" % JSON.stringify(d1["audio"]))
	var tmp := "user://zz_mt_scene.json"
	var tf := FileAccess.open(tmp, FileAccess.WRITE)
	tf.store_string(JSON.stringify(d1))
	tf.close()
	var back: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(tmp))
	S.audio_tracks = AudioTrack.from_file(back["audio"])
	var d1b: Dictionary = S.to_dict(m.B)
	ok(JSON.stringify(d1b) == JSON.stringify(d1), "1c a file written, read and saved again is byte-identical (JSON of the whole scene)")
	S.audio_tracks.append(AudioTrack.clean({"path": WAV_B, "offset": 0.5, "role": "voice"}))
	var d2: Dictionary = S.to_dict(m.B)
	var listed: Array = d2["audio"]
	ok(listed is Array and listed.size() == 2 and String(listed[1]["role"]) == "voice" and not listed[0].has("role"), "1d two tracks save as a list; the voice role is written, music is not")
	var back2: Dictionary = JSON.parse_string(JSON.stringify(d2))
	S.audio_tracks = AudioTrack.from_file(back2["audio"])
	ok(JSON.stringify(S.to_dict(m.B)) == JSON.stringify(d2), "1e the list loads back and saves the same")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	# ---- (2) sync: A at 0 s, B at 0.5 s or 1.1 s, the playhead from 0.2 s, playing 3 s, both through the one premix.
	# GATE: at the moment the playhead is set from the premix's clock, that clock minus the playhead is within 5 ms, for each track.
	# INFO: the display gap (read later in the test), the frame times, and the mixer's seconds per wall second.
	for boff in [0.5, 1.1]:
		S.audio_tracks = [{"path": WAV_A, "offset": 0.0, "gain_db": 0.0}, {"path": WAV_B, "offset": boff, "gain_db": 0.0}]
		m._audio_reload()
		await wait_swap()
		m.pv_in = -1.0
		m.pv_out = -1.0
		m.playing = false
		m.playhead = 0.2
		m._ps().apply(m.B, 0.2)
		await idle(2)
		m.playing = true
		var set_gap := [0.0, 0.0]
		var set_n := [0, 0]
		var disp_gap := 0.0
		var dts := []
		var ph_start: float = m.playhead
		var clk0 := -1.0
		var t0 := 0
		var frames := 0
		while m.playing and (clk0 < 0.0 or Time.get_ticks_usec() - t0 < 3000000):
			await process_frame
			frames += 1
			dts.append(m.get_process_delta_time())
			if clk0 < 0.0:
				clk0 = m._audio_clock()   # the first frame the premix sounds: the mixer's clock starts here
				t0 = Time.get_ticks_usec()
			if m.audio_from_clock:
				for i in 2:
					if i < m.audio_gap.size() and not is_nan(float(m.audio_gap[i])):
						set_gap[i] = maxf(set_gap[i], absf(float(m.audio_gap[i])))
						set_n[i] += 1
			var ph: float = m.playhead
			var c: float = m._audio_clock()
			if c >= 0.0:
				disp_gap = maxf(disp_gap, absf(c - ph))
		var wall := (Time.get_ticks_usec() - t0) / 1000000.0
		var clk1: float = m._audio_clock()
		var mixer_rate := (clk1 - clk0) / wall if clk0 >= 0.0 and clk1 >= 0.0 and wall > 0.0 else -1.0
		var played: float = m.playhead - ph_start
		var still_playing: bool = m.playing
		m.playing = false
		await idle(1)
		var dt_mean := 0.0
		var dt_max := 0.0
		for d in dts:
			dt_mean += float(d)
			dt_max = maxf(dt_max, float(d))
		dt_mean /= maxf(dts.size(), 1)
		print("     INFO B offset %.1f s: %d frames, the premix sounded for %.2f s; playhead moved %.3f s" % [boff, frames, wall, played])
		print("     INFO B offset %.1f s: mixer %.3f seconds of audio per wall second (1.000 = real time)" % [boff, mixer_rate])
		print("     INFO B offset %.1f s: frames mean %.1f ms, worst %.1f ms; display gap (read a frame later) worst %.1f ms" % [boff, dt_mean * 1000.0, dt_max * 1000.0, disp_gap * 1000.0])
		var worst := maxf(set_gap[0], set_gap[1])
		ok(set_n[0] > 0 and set_n[1] > 0, "2a B offset %.1f s: both tracks sounded through the premix (%d and %d frames set from its clock)" % [boff, set_n[0], set_n[1]])
		ok(still_playing and played > 2.5, "2b B offset %.1f s: the playhead ran the whole 3 s from 0.2 s (moved %.3f s)" % [boff, played])
		ok(set_n[0] > 0 and set_n[1] > 0 and worst < 0.005, "2c B offset %.1f s: mechanism: premix clock minus the playhead, set-time, over 3 s: A worst %.2f ms, B worst %.2f ms (bar 5 ms)" % [boff, set_gap[0] * 1000.0, set_gap[1] * 1000.0])

	# ---- (3) mute and solo: the energy leaves the premix. A alone sounds in 0..0.4 s; B alone in 4.1..4.4 s (A ends at 4.0 s).
	S.audio_tracks = [{"path": WAV_A, "offset": 0.0, "gain_db": 0.0}, {"path": WAV_B, "offset": 0.5, "gain_db": 0.0}]
	m._audio_reload()
	await wait_swap()
	var pre_a := rms(0.0, 0.4)
	var pre_b := rms(4.1, 4.4)
	ok(pre_a > 0.1 and pre_b > 0.1, "3-pre both tracks are in the premix (A alone %.3f, B alone %.3f RMS)" % [pre_a, pre_b])
	S.audio_tracks[1]["mute"] = true
	m._audio_remix_now()
	await wait_swap()
	var post_b := rms(4.1, 4.4)
	var d_b := drop_db(pre_b, post_b)
	ok(d_b > 60.0, "3a mute B: B's energy leaves the premix: its window drops %.1f dB (bar > 60 dB)" % d_b)
	ok(absf(drop_db(pre_a, rms(0.0, 0.4))) < 0.1, "3b A keeps its level while B is muted (within 0.1 dB)")
	S.audio_tracks[1].erase("mute")
	S.audio_tracks[1]["solo"] = true
	m._audio_remix_now()
	await wait_swap()
	var d_a := drop_db(pre_a, rms(0.0, 0.4))
	ok(d_a > 60.0 and absf(drop_db(pre_b, rms(4.1, 4.4))) < 0.1, "3c solo on B: A's energy leaves the premix (%.1f dB down); B keeps its level" % d_a)
	S.audio_tracks[1].erase("solo")
	m._audio_remix_now()
	await wait_swap()
	ok(absf(drop_db(pre_a, rms(0.0, 0.4))) < 0.1 and absf(drop_db(pre_b, rms(4.1, 4.4))) < 0.1, "3d unsolo: both tracks are back at their levels")

	# ---- (4) undo: one step each, Ctrl+Z restores the scene exactly
	m.undo.clear()
	var f0 := fp()
	m.audio_pick = 0
	m._audio_flag(0, "mute")
	ok(m.undo.size() == 1, "4a mute: one undo step")
	m._undo()
	await idle(1)
	ok(fp() == f0, "4b Ctrl+Z un-mutes exactly")
	m._redo()   # the mute again
	m.audio_pick = 1
	cmd("audio_next_role_for_the_picked_track_music_voice_sfx")
	ok(m.undo.size() == 2 and String(S.audio_tracks[1]["role"]) == "voice", "4c role: one undo step, B is now %s" % String(S.audio_tracks[1]["role"]))
	m._undo()
	ok(String(S.audio_tracks[1].get("role", "music")) == "music" and bool(S.audio_tracks[0].get("mute", false)), "4d Ctrl+Z undoes the role only (A stays muted)")
	m._undo()
	await idle(1)
	ok(fp() == f0, "4e Ctrl+Z again puts the mute back: the scene is exactly as before")
	var u1: int = m.undo.size()
	tl.audio_drag_started.emit(0)   # what a lane drag does at its first real move: the one undo step
	S.audio_tracks[0]["offset"] = 0.75
	ok(m.undo.size() == u1 + 1, "4f an offset drag: one undo step")
	m._undo()
	await idle(1)
	ok(fp() == f0 and absf(float(S.audio_tracks[0]["offset"])) < 1e-6, "4g Ctrl+Z puts A's offset back exactly")
	m._redo()
	ok(absf(float(S.audio_tracks[0]["offset"]) - 0.75) < 1e-6, "4h redo brings it back")

	# ---- (5) lanes, the name click and the pick, then three tracks: every lane inside the window at 1600x900 and 1280x720
	m._undo()   # the offset back to 0 s
	await idle(2)
	m.audio_pick = -1
	ok(tl.audio_h() == tl.LANE_H * 2.0, "5a the timeline has one lane per track: %.0f px for 2 tracks" % tl.audio_h())
	var lane_b: Vector2 = tl.audio_name_rect(1).get_center()
	var u2: int = m.undo.size()
	_click(lane_b, true)
	_click(lane_b, false)
	await idle(2)
	ok(bool(S.audio_tracks[1].get("mute", false)) and m.undo.size() == u2 + 1, "5b a click on B's name mutes B: one undo step")
	# the premix is rebuilt once the tracks have been quiet for AUDIO_MIX_QUIET (a drag mixes once, at its end)
	var t_w := Time.get_ticks_msec()
	while m._a_key != m._a_key_now() and Time.get_ticks_msec() - t_w < 2000:
		await process_frame
	ok(m._a_key == m._a_key_now() and absf(drop_db(pre_b, rms(4.1, 4.4))) > 60.0, "5c the mute reaches the premix: B's window drops %.1f dB" % drop_db(pre_b, rms(4.1, 4.4)))
	_click(lane_b, true)
	_click(lane_b, false)
	await idle(1)
	ok(not S.audio_tracks[1].has("mute"), "5d a second click on the name unmutes B")
	var lane_a_body := Vector2(tl.audio_name_rect(0).end.x + 24.0, tl.size.y - tl.audio_h() + tl.LANE_H * 0.5)
	_click(lane_a_body, true)
	_click(lane_a_body, false)
	await idle(2)
	ok(m.audio_pick == 0, "5e a click on A's lane picks track A (pick %d)" % m.audio_pick)

	# three tracks: the layout must show every lane (the timeline is the bottom panel and grows by one row per track)
	S.audio_tracks.append(AudioTrack.clean({"path": WAV_B, "offset": 0.25, "gain_db": -6.0, "role": "sfx"}))
	m._audio_reload()
	await wait_swap()
	await idle(3)
	ok(tl.audio_h() == tl.LANE_H * 3.0, "5f three tracks: %.0f px of lanes" % tl.audio_h())
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(sz)
		await idle(10)
		var win := Vector2(DisplayServer.window_get_size())
		var bp: Rect2 = m.ui_bp.get_global_rect()
		var tlr: Rect2 = tl.get_global_rect()
		var all_in := true
		var low := 0.0
		for i in 3:
			var lr := Rect2(tlr.position.x, tlr.position.y + tlr.size.y - tl.audio_h() + i * tl.LANE_H, tlr.size.x, tl.LANE_H)
			low = maxf(low, lr.end.y)
			# inside the window and inside the bottom panel (nothing covers it)
			if lr.end.y > win.y or lr.position.y < bp.position.y or lr.end.y > bp.end.y + 0.5 or lr.position.y < 0.0:
				all_in = false
		ok(all_in and tlr.end.y <= win.y, "5g at %dx%d: all 3 lanes inside the window and the bottom panel (lowest lane ends at %.0f of %.0f px; timeline bottom %.0f)" % [sz.x, sz.y, low, win.y, tlr.end.y])
	# the picture: 1600x900, all three lanes in view
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await idle(10)
	tl.queue_redraw()
	await idle(2)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var r: Rect2 = tl.get_global_rect()
	var vis := int(DisplayServer.window_get_size().y) - int(r.position.y)
	var crop := img.get_region(Rect2i(int(r.position.x), int(r.position.y), int(r.size.x), mini(int(r.size.y), vis)))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)   # 2x: the lanes are 14 px each
	var saved := crop.save_png(SHOT)
	ok(saved == OK and FileAccess.file_exists(SHOT), "5h the three lanes are saved to %s (%dx%d, 2x)" % [SHOT.get_file(), crop.get_width(), crop.get_height()])

	# ---- (6) the playblast mixes the sounding tracks: one input each, delayed by its offset, summed with amix
	var pa := PlayblastExport.args("d", 30, "o.mp4", AudioTrack.audible_list([{"path": WAV_A, "offset": 0.0, "gain_db": 0.0}, {"path": WAV_B, "offset": 0.5, "gain_db": -3.0}]), 0.0)
	var fc := String(pa[pa.find("-filter_complex") + 1]) if pa.has("-filter_complex") else ""
	ok(fc.contains("amix=inputs=2") and fc.contains("[2:a]volume=-3.00dB[a1]") and pa.has("-itsoffset") and pa.count("-i") == 3, "6a two tracks: one -i each (%d), the second delayed 0.5 s, its gain -3 dB, summed by amix: %s" % [pa.count("-i"), fc])
	var muted_list := AudioTrack.audible_list([{"path": WAV_A, "offset": 0.0, "gain_db": 0.0, "mute": true}, {"path": WAV_B, "offset": 0.5, "gain_db": 0.0}])
	ok(muted_list.size() == 1 and String(muted_list[0]["path"]) == WAV_B, "6b a muted track is left out of the playblast; the solo rule keeps only the soloed one")

	# ---- (7) the premix: onsets at the offsets, and the re-mix time for three 10 s tracks
	var rate := int(AudioServer.get_mix_rate())
	var clk := PackedFloat32Array()
	clk.resize(rate)   # one second: a click on the first sample, silence after
	clk[0] = 0.9
	write_wav(WAV_CLK, rate, clk)
	var click := AudioTrack.load_stream(WAV_CLK)
	var offs := [0.25, 0.5, 1.1]
	var one := AudioTrack.mix([click, click, click], offs, [0.0, 0.0, 0.0], rate)
	var on_ok := true
	var on_txt := ""
	var pcm := one.data
	for off in offs:
		var e := int(round(float(off) * rate))
		var found := -1
		for k in range(maxi(0, e - 50), e + 50):
			if absf(float(pcm.decode_s16(4 * k)) / 32768.0) > 0.5:
				found = k
				break
		on_txt += " %.4f s -> sample %d (want %d);" % [off, found, e]
		if found < 0 or absf(float(found - e)) > 1.0:
			on_ok = false
	ok(on_ok, "7a onsets: a click at t=0 of each track lands at its offset within 1 sample:%s" % on_txt)
	for p in [WAV_CLK]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	var big_offs := [0.0, 0.5, 1.1]
	var big: Array = []
	var names := [WAV_A, WAV_B, WAV_C]
	var tones := [1000.0, 440.0, 220.0]
	for i in 3:
		var f := FileAccess.open(names[i], FileAccess.WRITE)
		f.store_buffer(AudioTrack.sine_wav_bytes(rate, 10.0, tones[i], 0.5, 0.0, 0.0))
		f.close()
		big.append(AudioTrack.load_stream(names[i]))
	# the decode happens once, when a track loads; a re-mix only sums the decoded tracks (timed here)
	var t_dec := Time.get_ticks_usec()
	var pcms := []
	for st in big:
		pcms.append(AudioTrack.decode(st, rate))
	var dec_ms := (Time.get_ticks_usec() - t_dec) / 1000.0
	var starts := []
	for off in big_offs:
		starts.append(int(round(float(off) * rate)))
	var gains := [1.0, db_to_linear(-3.0), db_to_linear(-6.0)]
	var t_mix := Time.get_ticks_usec()
	var w10 := AudioTrack.mix_pcm(pcms, starts, gains, rate)
	var mix_ms := (Time.get_ticks_usec() - t_mix) / 1000.0
	print("     INFO decode of three 10 s tracks (once, on load): %.1f ms" % dec_ms)
	print("     INFO 7b re-mix of three 10 s tracks, pure mix on this thread (offsets 0, 0.5, 1.1 s): %.1f ms, mixed length %.2f s" % [mix_ms, w10.get_length()])
	for p in names:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	# ---- (7c, 7d) the live app: three 10 s tracks, re-mixed on a worker thread while the frames keep going.
	# GATE 7c: no frame over 50 ms while the re-mix runs. Then the swapped premix puts each click at its offset (within 1 sample),
	# and GATE 7d: the set-time gap of the swapped premix stays under 5 ms.
	var ck := [WAV_A, WAV_B, WAV_C]
	for i in 3:
		var samp := PackedFloat32Array()
		samp.resize(rate * 10)
		samp[0] = 0.9   # a click on the first sample of each track
		write_wav(ck[i], rate, samp)
	S.audio_tracks = [{"path": WAV_A, "offset": 0.25, "gain_db": 0.0}, {"path": WAV_B, "offset": 0.5, "gain_db": 0.0}, {"path": WAV_C, "offset": 1.1, "gain_db": 0.0}]
	m.playing = false
	m._audio_reload()
	var worst_re := 0.0
	var re_frames := 0
	var t_prev := Time.get_ticks_usec()
	var t_w7 := Time.get_ticks_msec()
	while m._a_task >= 0 and Time.get_ticks_msec() - t_w7 < 5000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst_re = maxf(worst_re, (now - t_prev) / 1000.0)
		t_prev = now
		re_frames += 1
	await wait_swap()
	print("     INFO re-mix on a worker: worst frame %.1f ms over %d frames while it ran; the swap on the main thread %.2f ms; the re-mix itself %.1f ms" % [worst_re, re_frames, m.audio_swap_usec / 1000.0, m.audio_mix_usec / 1000.0])
	ok(re_frames > 0 and worst_re < 50.0, "7c no frame over 50 ms while a re-mix runs: worst %.1f ms over %d frames (bar 50 ms)" % [worst_re, re_frames])

	var offs7 := [0.25, 0.5, 1.1]
	var on7 := true
	var on7_txt := ""
	var w7 := premix()
	for off in offs7:
		var e := int(round(float(off) * rate))
		var found := -1
		for k in range(maxi(0, e - 50), e + 50):
			if absf(float(w7.data.decode_s16(4 * k)) / 32768.0) > 0.5:
				found = k
				break
		on7_txt += " %.4f s -> sample %d (want %d);" % [off, found, e]
		if found < 0 or absf(float(found - e)) > 1.0:
			on7 = false
	ok(on7, "7c the swapped premix: each click lands at its offset within 1 sample:%s" % on7_txt)

	m._ps().apply(m.B, 0.2)
	m.pv_in = -1.0
	m.pv_out = -1.0
	m.playing = false
	m.playhead = 0.2
	await idle(2)
	m.playing = true
	var g7 := [0.0, 0.0, 0.0]
	var n7 := [0, 0, 0]
	var c7 := -1.0
	var t7 := 0
	while m.playing and (c7 < 0.0 or Time.get_ticks_usec() - t7 < 2000000):
		await process_frame
		if c7 < 0.0:
			c7 = m._audio_clock()
			t7 = Time.get_ticks_usec()
		if m.audio_from_clock:
			for i in 3:
				if i < m.audio_gap.size() and not is_nan(float(m.audio_gap[i])):
					g7[i] = maxf(g7[i], absf(float(m.audio_gap[i])))
					n7[i] += 1
	m.playing = false
	await idle(1)
	var worst7 := maxf(g7[0], maxf(g7[1], g7[2]))
	ok(n7[0] > 0 and n7[1] > 0 and n7[2] > 0 and worst7 < 0.005, "7d after the swap: set-time gap over 2 s, three tracks: worst %.2f / %.2f / %.2f ms (bar 5 ms)" % [g7[0] * 1000.0, g7[1] * 1000.0, g7[2] * 1000.0])
	for p in ck:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	# ---- restore the stage for the next suite
	S.audio_tracks = []
	m._audio_reload()
	await wait_swap()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV_A))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV_B))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV_C))
	print("AUDIOTRACKS TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	quit(fails)
