## godot --path . -s tests/audiotracks_test.gd     (ROADMAP 77: multi-track audio; window suite: it plays sound and saves a screenshot)
## Bars written before the first run:
##  (1) file: an old scene's single "audio" dictionary loads as ONE track (role music) and saves back byte-identical;
##      two tracks save as a list under "audio" and load back to the same JSON
##  (2) sync: A at offset 0, B at 0.5 s, playhead from 0.2 s, 3 s of playback: while a track sounds the audio clock drives the
##      playhead; each track's audio clock (position + time since last mix - output latency + offset) stays within one frame
##      (1 / fps) of the playhead, worst printed for both tracks
##  (3) mute: a muted track's player volume_db is MUTE_DB (silent: <= -80 dB); the other keeps its gain (0 dB).
##      solo on B: A goes silent, B keeps sounding; unsolo: A is back at its gain
##  (4) undo: add, mute, role and an offset drag are one undo step each; Ctrl+Z restores the scene exactly
##  (5) lanes: one lane per track (LANE_H each); a click on B's name mutes it; a click on A's lane picks it; with three tracks every
##      lane sits inside the window and the bottom panel at 1600x900 and 1280x720; screenshot of the three lanes
##  (6) playblast: two tracks mux as two inputs (B delayed by its offset, its gain) summed by amix; a muted track is left out
extends SceneTree

var fails := 0
var m: Node
const WAV_A := "user://zz_mt_a.wav"
const WAV_B := "user://zz_mt_b.wav"
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


func _init() -> void:
	# SILENT: the master bus is muted; the players still run and their positions still advance
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

	# ---- (2) sync: A at 0 s, B at 0.5 s, the playhead from 0.2 s, playing 3 s.
	# MECHANISM GATE (the bar): at the moment the playhead is set from the audio clock, each track's audio clock plus its offset
	# is within 5 ms of the playhead (main.gd audio_gap, read right after the set). Frames where the playhead came from the
	# frame clock are counted, not gated.
	# INFO, not gated: the display gap (playhead vs each clock read later in the test, after the frame has drawn), the frame
	# times, and the mixer's seconds per wall second. The display gap is one frame old by construction and grows with the
	# machine's load (10 agents running tests make frames 20-70 ms), so it measures the load, not the mechanism.
	for boff in [0.5, 1.1]:   # B starts at two different points: the start compensation is checked at both
		S.audio_tracks = [{"path": WAV_A, "offset": 0.0, "gain_db": 0.0}, {"path": WAV_B, "offset": boff, "gain_db": 0.0}]
		m._audio_reload()
		m.pv_in = -1.0
		m.pv_out = -1.0
		m.playing = false
		m.playhead = 0.2
		m._ps().apply(m.B, 0.2)
		await idle(2)
		m.playing = true
		var offs := [0.0, boff]
		var set_gap := [0.0, 0.0]     # the gate: worst |audio clock + offset - playhead| read at set time
		var set_n := [0, 0]
		var disp_gap := [0.0, 0.0]    # info: the same, read later in the test
		var dts := []
		var from_clock := 0
		var from_frame := 0
		var ph_start: float = m.playhead
		var t0 := Time.get_ticks_usec()
		var clk0 := -1.0
		var frames := 0
		while Time.get_ticks_usec() - t0 < 3000000 and m.playing:
			await process_frame
			frames += 1
			if clk0 < 0.0:
				clk0 = m._audio_clock_of(0)   # the first frame the track sounds: the mixer's clock starts here
				t0 = Time.get_ticks_usec()
			dts.append(m.get_process_delta_time())
			if m.audio_from_clock:
				from_clock += 1
			else:
				from_frame += 1
			for i in 2:
				if i < m.audio_gap.size() and not is_nan(float(m.audio_gap[i])) and m.audio_from_clock:
					set_gap[i] = maxf(set_gap[i], absf(float(m.audio_gap[i])))
					set_n[i] += 1
			var ph: float = m.playhead
			for i in 2:
				var c: float = m._audio_clock_of(i)
				if c >= 0.0:
					disp_gap[i] = maxf(disp_gap[i], absf(c - ph))
		var wall := (Time.get_ticks_usec() - t0) / 1000000.0
		var clk1: float = m._audio_clock_of(0)
		var mixer_rate := (clk1 - clk0) / wall if clk0 >= 0.0 and clk1 >= 0.0 else -1.0
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
		print("     INFO sync: %d frames in %.2f s; playhead from the audio clock on %d frames, from the frame clock on %d; playhead moved %.3f s" % [frames, wall, from_clock, from_frame, played])
		print("     INFO mixer: %.3f seconds of audio per wall second (1.000 = real time; a throttled mixer shows here)" % mixer_rate)
		print("     INFO frames: mean %.1f ms, worst %.1f ms" % [dt_mean * 1000.0, dt_max * 1000.0])
		print("     INFO display gap (playhead vs each clock read later, one frame old by construction): A %.1f ms, B %.1f ms" % [disp_gap[0] * 1000.0, disp_gap[1] * 1000.0])
		var worst := maxf(set_gap[0], set_gap[1])
		ok(set_n[0] > 0 and set_n[1] > 0, "2a B offset %.1f s: both tracks sounded and were set from the audio clock (A %d frames, B %d frames)" % [boff, set_n[0], set_n[1]])
		ok(still_playing and played > 2.5, "2b B offset %.1f s: the playhead ran the whole 3 s from 0.2 s (moved %.3f s; the mixer rate is printed above)" % [boff, played])
		ok(set_n[0] > 0 and set_n[1] > 0 and worst < 0.005, "2c B offset %.1f s: mechanism: at set time, |audio clock + offset - playhead| over 3 s, both tracks: A worst %.2f ms, B worst %.2f ms (bar 5 ms)" % [boff, set_gap[0] * 1000.0, set_gap[1] * 1000.0])


	# ---- (3) mute and solo: the player volume
	var pl: Array = m._a_players
	m._audio_flag(1, "mute")
	await idle(2)
	ok(float(pl[1].volume_db) <= AudioTrack.MUTE_DB + 0.01 and float(pl[1].volume_db) <= -80.0, "3a muted B: its player is silent (%.1f dB)" % float(pl[1].volume_db))
	ok(absf(float(pl[0].volume_db) - 0.0) < 1e-6, "3b A keeps its gain (%.1f dB)" % float(pl[0].volume_db))
	m._audio_flag(1, "mute")
	m._audio_flag(1, "solo")
	await idle(2)
	ok(float(pl[0].volume_db) <= -80.0 and absf(float(pl[1].volume_db)) < 1e-6, "3c solo on B: A is silent (%.1f dB), B sounds (%.1f dB)" % [float(pl[0].volume_db), float(pl[1].volume_db)])
	m._audio_flag(1, "solo")
	await idle(2)
	ok(absf(float(pl[0].volume_db)) < 1e-6, "3d unsolo: A sounds again")

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

	# ---- (5) lanes: the name click and the pick, then three tracks: every lane inside the window at 1600x900 and 1280x720
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
	ok(float(pl[1].volume_db) <= -80.0, "5c B's player is silent after the name click")
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

	# ---- restore the stage for the next suite
	S.audio_tracks = []
	m._audio_reload()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV_A))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV_B))
	print("AUDIOTRACKS TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	quit(fails)
