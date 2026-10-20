## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i22_test.gd     (ROADMAP I22: choreograph to the song, scripts/choreograph.gd + choreograph_ui.gd; needs a window)
## A synthetic 120 bpm track, 8 bars of 2 s: 4 quiet bars (tone burst amplitude 0.1), then 4 loud bars (0.5, 0.6, 0.7, 0.8; the downbeat
## burst 1.0 x the bar's amplitude, the other beats 0.8 x), so the loudest downbeat is the first beat of bar 8 (14.0 s). Bars, written before measuring:
##  (1) loud bars get >= 2 strikes each, quiet bars <= 1, and the loud bars' total is >= 2x the quiet bars' total
##  (2) the strike with the biggest J (J = (1+e) mu v: the same striker and target mass, so J follows the fist's peak speed, measured here on
##      the written scene in the 0.25 s before each contact at 60 Hz) is on the loudest downbeat, within 1 frame
##  (3) every contact (the STRIKE cards' arrivals) is within 1 frame (1/30 s) of a beat
##  (4) every strike move is inside the timing coach's range for that strike (BeatFight.strike_range of the written scene, 5 ms tolerance)
##  (5) the open scene's JSON is byte-identical after Preview, its file on disk is untouched, and the new scene exists only after Accept
##  (6) Accept writes the NEW file (its name is not the open scene's) with two fighters in it; Check ran on it and its summary is printed
##  (7) placement: the timeline holds the energy strip (one column per beat) and one contact mark per strike, both heads are inside the window
##      at the loudest downbeat; the picture is saved
extends SceneTree

const FRAME := 1.0 / 30.0
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i22.png"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func dist_to(ts: Array, t: float) -> float:
	var best := INF
	for b in ts:
		best = minf(best, absf(float(b) - t))
	return best


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func make_wav(path: String) -> void:
	var rate := 22050
	var amps := [0.1, 0.1, 0.1, 0.1, 0.5, 0.6, 0.7, 0.8]
	var n := rate * 16
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var beat := int(t / 0.5)
		var ph := t - beat * 0.5
		var a: float = float(amps[beat / 4]) * (1.0 if beat % 4 == 0 else 0.8)
		pcm.encode_s16(i * 2, int((a * sin(TAU * 440.0 * t) if ph < 0.12 else 0.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = pcm
	w.save_to_wav(path)


func scene_files() -> String:
	var l := []
	for dir in ["res://scenes", "res://scenes/_wip"]:
		for f in DirAccess.get_files_at(dir):
			l.append(dir + "/" + f + ":" + str(FileAccess.get_size(dir + "/" + f)))
	l.sort()
	return "\n".join(l)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var wav := "user://zz_i22_%d.wav" % OS.get_process_id()
	make_wav(wav)
	var out_dir := "user://zz_i22_out_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(out_dir)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var beats := []
	for k in 32:
		beats.append({"t": 0.5 * k, "down": k % 4 == 0})
	m.S.beats_audio = beats
	m.S.audio_tracks = [AudioTrack.clean({"path": wav, "offset": 0.0, "gain_db": 0.0, "role": "music"})]
	m.cg_ui.out_dir = out_dir
	m.cg_ui.paths = ["res://scenes/combo3.json"]
	var disk0 := FileAccess.get_file_as_string("res://scenes/combo3.json")
	var listing0 := scene_files()
	var open_name: String = m.S.name
	var open_json0 := JSON.stringify(m._scene_dict())

	# PLAN + PREVIEW
	m.cg_ui.show()
	await idle(2)
	var res: Dictionary = m.cg_ui.res
	ok(res.get("ok", false), "the plan is made: %s" % res.get("msg", ""))
	var bars: Array = res.get("bars", [])
	var loud := 0
	var quiet := 0
	var loud_min := 99
	var quiet_max := 0
	var per_bar := []
	var strikes: Array = res.get("strikes", [])
	for k in bars.size():
		var n := 0
		for s in strikes:
			if int(s["bar"]) == k:
				n += 1
		per_bar.append(n)
		if k < 4:
			quiet += n
			quiet_max = maxi(quiet_max, n)
		else:
			loud += n
			loud_min = mini(loud_min, n)
	print("     strikes per bar: ", per_bar)
	ok(bars.size() == 8 and loud_min >= 2 and quiet_max <= 1 and loud >= 2 * quiet, "(1) loud bars %d strikes (each >= 2: min %d), quiet bars %d (each <= 1: max %d), loud >= 2x quiet" % [loud, loud_min, quiet, quiet_max])
	m.cg_ui.preview()
	await idle(3)
	m.cg_ui.halt()
	ok(JSON.stringify(m._scene_dict()) == open_json0 and not FileAccess.file_exists(out_dir + "/combo3_song.json") and DirAccess.get_files_at(out_dir).is_empty(),
		"(5a) after Preview the open scene's JSON is byte-identical (%d chars) and no new scene exists yet" % open_json0.length())

	# ACCEPT
	var path: String = m.cg_ui.accept()
	await idle(3)
	var A: Scene = m.S
	var ts := A.times()
	var fr := 1.0 / float(A.fps)
	ok(path != "" and FileAccess.file_exists(path) and path.get_file().get_basename() != open_name and A.actors.size() == 1,
		"(6) Accept wrote %s, opened with %d fighters; the open scene was '%s'" % [path.get_file(), A.actors.size() + 1, open_name])
	ok(FileAccess.get_file_as_string("res://scenes/combo3.json") == disk0 and scene_files() == listing0,
		"(5b) the open scene's file and the scenes/ folders are untouched (%d files listed)" % listing0.split("\n").size())
	print("     CHECK: ", m.cg_ui.summary)
	for f in m.findings:
		print("       ", f["sev"], " ", f["rule"], " card ", int(f["card"]) + 1, ": ", String(f["msg"]).left(110))
	ok(m.cg_ui.summary.begins_with(path.get_file()), "(6b) Check ran on the written scene and its summary is shown")

	# (3) every contact within 1 frame of a beat; (4) every strike in the coach's range
	var beat_t := []
	for b in beats:
		beat_t.append(float(b["t"]))
	var B := body()
	var worst := 0.0
	var bad_rg := 0
	var contacts := []
	for i in A.cards.size():
		if String(A.cards[i]["name"]).begins_with("STRIKE"):
			var arr: float = ts[i][1]
			contacts.append(arr)
			worst = maxf(worst, dist_to(beat_t, arr))
			var rg := BeatFight.strike_range(A, B, i)
			var mv := A.move_time(i)
			var inside: bool = mv >= float(rg[0]) - 0.005 and mv <= float(rg[1]) + 0.005
			if not inside:
				bad_rg += 1
			print("       STRIKE card %d lands %.3f s  move %.3f s  coach range %.3f - %.3f s  %s" % [i + 1, arr, mv, rg[0], rg[1], "ok" if inside else "OUTSIDE"])
	ok(contacts.size() == strikes.size() and worst <= fr + 1e-6, "(3) %d contacts, the worst %.1f ms from a beat (<= %.1f ms)" % [contacts.size(), worst * 1000.0, fr * 1000.0])
	ok(bad_rg == 0, "(4) every strike move is inside the timing coach's range (%d outside)" % bad_rg)

	# (2) the biggest J on the loudest downbeat: the fist's peak speed in the 0.25 s before each contact
	var best_v := 0.0
	var best_t := -1.0
	for c in contacts:
		var v := 0.0
		var prev := {}
		var k := int(floor((float(c) - 0.25) * 60.0))
		while k <= int(round(float(c) * 60.0)):
			A.apply(B, maxf(0.0, float(k) / 60.0))
			for h in ["hand_l", "hand_r"]:
				var p: Vector3 = B.palm_point(h)
				if prev.has(h):
					v = maxf(v, p.distance_to(prev[h]) * 60.0)
				prev[h] = p
			k += 1
		print("       contact %.2f s  fist peak %.2f m/s" % [c, v])
		if v > best_v:
			best_v = v
			best_t = float(c)
	# the loudest downbeat, from the track itself
	var en := Choreograph.energy(AudioTrack.load_stream(wav), beats)
	var loud_t := 0.0
	var loud_v := 0.0
	for k in range(0, 32, 4):
		if float(en["rms"][k]) > loud_v:
			loud_v = float(en["rms"][k])
			loud_t = 0.5 * k
	ok(absf(best_t - loud_t) <= fr + 1e-6, "(2) the biggest strike (%.2f m/s) lands at %.3f s, the loudest downbeat is at %.3f s" % [best_v, best_t, loud_t])

	# (7) placement
	m._page_set("STAGE", false)
	m.playhead = loud_t
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(3)
	await RenderingServer.frame_post_draw
	var tl = m.ui_timeline
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var inside_all := true
	for k in m.actors_rt.size():
		var W: Vector3 = m._stage_xf() * (m.actors_rt[k]["xf"] as Transform3D) * ((m.actors_rt[k]["B"] as Body).P["head"] as Vector3)
		var sp: Vector2 = m.cam.unproject_position(W)
		print("       fighter %d head on screen at %s" % [k + 1, sp])
		inside_all = inside_all and Rect2(Vector2.ZERO, vp).has_point(sp)
	ok(m.actors_rt.size() == 2 and inside_all, "(7a) both fighters' heads are inside the window at the loudest downbeat")
	ok(tl.cg.size() == 32 and tl.bf.size() == strikes.size() and absf(tl.cg_peak - loud_t) <= fr, "(7b) the timeline holds the energy strip (%d columns) and %d contact marks, BIG at %.2f s" % [tl.cg.size(), tl.bf.size(), tl.cg_peak])
	var img: Image = m.get_viewport().get_texture().get_image()
	ok(img.save_png(SHOT) == OK, "(7c) picture saved: " + SHOT)
	DirAccess.remove_absolute(wav)
	for f in DirAccess.get_files_at(out_dir):
		DirAccess.remove_absolute(out_dir + "/" + f)
	DirAccess.remove_absolute(out_dir)
	print("i22: ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
