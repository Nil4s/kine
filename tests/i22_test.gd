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
##  (8) STEP 2, Check on the written scene: 0 must-fix TIP SPEED / SEQUENCE items (and the planning took under 5 s, uncached)
##  (9) the fighters keep apart: no body-on-body overlap ("touch") in the 30 Hz frames of the plan, and DistanceKeeper finds every strike in range
##  (10) every quiet bar holds a circling step card on the attacker and on the defender (a "circle" card arriving inside the bar)
##  (7) placement: the timeline holds the energy strip (one column per beat) and one contact mark per strike, both heads are inside the window
##      at the loudest downbeat; the picture is saved
extends SceneTree

const FRAME := 1.0 / 30.0
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i22c.png"
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
	var tp0 := Time.get_ticks_msec()
	m.cg_ui.show()
	var plan_s := float(Time.get_ticks_msec() - tp0) / 1000.0
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
	var tips := []
	for i in A.cards.size():
		if String(A.cards[i]["name"]).begins_with("STRIKE"):
			var arr: float = ts[i][1]
			contacts.append(arr)
			worst = maxf(worst, dist_to(beat_t, arr))
			var rg := BeatFight.strike_range(A, B, i)
			var mv := A.move_time(i)
			# the fist range, or slower than its slow end ONLY where the weapon's tip bar made it so (tip peak >= 75 % of the cap)
			var tipv := Choreograph._tip_v(A, B, float(ts[i][1]) - mv - 0.05, float(ts[i][1]) + 0.02)
			tips.append(tipv)
			var inside: bool = mv >= float(rg[0]) - 0.005 and (mv <= float(rg[1]) + 0.005 or (tipv >= 0.75 * Choreograph.tip_cap(B) and mv <= 1.35 * float(rg[1])))
			if not inside:
				bad_rg += 1
			print("       STRIKE card %d lands %.3f s  move %.3f s  coach range %.3f - %.3f s  %s" % [i + 1, arr, mv, rg[0], rg[1], "ok" if inside else "OUTSIDE"])
	ok(contacts.size() == strikes.size() and worst <= fr + 1e-6, "(3) %d contacts, the worst %.1f ms from a beat (<= %.1f ms)" % [contacts.size(), worst * 1000.0, fr * 1000.0])
	ok(bad_rg == 0, "(4) every strike move is inside the timing coach's range (%d outside)" % bad_rg)

	# (8) Check: no must-fix TIP SPEED / SEQUENCE
	var bad_rules := 0
	for f in m.findings:
		if f["sev"] == "FAIL" and (f["rule"] == "TIP SPEED" or f["rule"] == "SEQUENCE"):
			bad_rules += 1
	var tip_max := 0.0
	for v in tips:
		tip_max = maxf(tip_max, float(v))
	ok(bad_rules == 0 and plan_s < 5.0, "(8) Check: %d must-fix TIP SPEED / SEQUENCE (tip peak %.1f m/s, cap %.0f); planning took %.1f s (< 5 s)" % [bad_rules, tip_max, Choreograph.tip_cap(B), plan_s])

	# (9) bodies apart, every strike in range
	var DD: Scene = A.actors[0]["scene"]
	var rel := Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), Vector3(0.0, 0.0, Choreograph.DEF_DIST))
	var BA := body()
	var BD := body()
	var touch := 0
	var deepest := 0.0
	var tt := 0.0
	while tt < A.length():
		A.apply(BA, tt)
		DD.apply(BD, tt)
		for c in BA.cross_contacts(BD, rel):
			if c[3] == "touch":
				touch += 1
				deepest = maxf(deepest, float(c[2]))
		tt += FRAME
	var rep := DistanceKeeper.analyze(A, DD, rel)
	var min_root := INF
	for sp in rep["spans"]:
		min_root = minf(min_root, float(sp["root_gap"]))
	ok(touch == 0 and rep["flagged"] == 0, "(9) %d body-on-body overlap frames (deepest %.1f cm); keeper: %s; the nearest the bodies' centres get at a strike start %.2f m" % [touch, deepest * 100.0, rep["msg"], min_root])

	# (10) circling in the quiet bars
	var circ_ok := true
	var quiet_n := 0
	for k in bars.size():
		if int(bars[k]["n"]) != 0:
			continue
		quiet_n += 1
		for S2 in [A, DD]:
			var t2: Array = S2.times()
			var found := false
			for i in S2.cards.size():
				if String(S2.cards[i]["name"]).begins_with("circle") and float(t2[i][1]) >= float(bars[k]["t0"]) - 1e-6 and float(t2[i][1]) <= float(bars[k]["t1"]) + 1e-6:
					found = true
			circ_ok = circ_ok and found
	ok(quiet_n >= 1 and circ_ok, "(10) each of the %d quiet bars has a circling step card on both fighters" % quiet_n)

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
	# the picture: the choreography panel closed, the side panels away ("clean"), then the camera frames BOTH fighters side-on
	m.ui_find.visible = false
	m.clean = true
	await idle(3)
	var pts: Array = []   # world points: each fighter's head top, both feet on the floor, both hands
	for k in m.actors_rt.size():
		var xf: Transform3D = m._stage_xf() * (m.actors_rt[k]["xf"] as Transform3D)
		var Bk: Body = m.actors_rt[k]["B"]
		var hd: Vector3 = Bk.P["head"]
		pts.append(xf * (hd + Vector3(0, 0.14, 0)))
		for f in ["foot_l", "foot_r"]:
			var fp: Vector3 = Bk.P[f]
			pts.append(xf * Vector3(fp.x, 0.0, fp.z))
		for h in ["hand_l", "hand_r"]:
			pts.append(xf * (Bk.P[h] as Vector3))
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	# the free viewport: no open side panel (clean hides them), the bottom panel and status line reserved
	var free := Rect2(Vector2(0, m.TOP_H), Vector2(vp.x, vp.y - m.TOP_H - m.bottom_h - m.LINE_H - 6))
	for k in m.ui_side_of:
		if (m.ui_side_of[k] as Control).visible:
			var r: Rect2 = (m.ui_side_of[k] as Control).get_global_rect()
			free = free.intersection(Rect2(Vector2(r.end.x if k == "left" else 0.0, free.position.y), Vector2(vp.x - (r.size.x if k == "left" else r.size.x), free.size.y)))
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var ctr := (lo + hi) * 0.5
	var fit := free.grow(-24.0)
	var d_fit := 2.0
	while d_fit < 12.0:
		m._turn_to(-90.0, -8.0, d_fit, ctr, false)   # from the right, side-on: the two fighters apart, not one behind the other
		var all_in := true
		for q in pts:
			all_in = all_in and not m.cam.is_position_behind(q) and fit.has_point(m.cam.unproject_position(q))
		if all_in:
			break
		d_fit += 0.1
	await idle(4)
	await RenderingServer.frame_post_draw
	var tl = m.ui_timeline
	var inside_all := true
	for k in m.actors_rt.size():
		var xf2: Transform3D = m._stage_xf() * (m.actors_rt[k]["xf"] as Transform3D)
		var Bk2: Body = m.actors_rt[k]["B"]
		var hd2: Vector3 = Bk2.P["head"]
		var fl: Vector3 = Bk2.P["foot_l"]
		var fr2: Vector3 = Bk2.P["foot_r"]
		for q in [xf2 * (hd2 + Vector3(0, 0.14, 0)), xf2 * Vector3(fl.x, 0.0, fl.z), xf2 * Vector3(fr2.x, 0.0, fr2.z)]:
			var sp: Vector2 = m.cam.unproject_position(q)
			inside_all = inside_all and free.has_point(sp)
			if not free.has_point(sp):
				print("       fighter %d point at %s is OUTSIDE the free view %s" % [k + 1, sp, free])
		print("       fighter %d head on screen at %s (free view %s, camera %.1f m)" % [k + 1, m.cam.unproject_position(xf2 * (hd2 + Vector3(0, 0.14, 0))), free, d_fit])
	ok(m.actors_rt.size() == 2 and inside_all, "(7a) PLACEMENT: both fighters' head tops and both feet are inside the free viewport (no open panel over them) at the loudest downbeat")
	ok(tl.cg.size() == 32 and tl.bf.size() == strikes.size() and absf(tl.cg_peak - loud_t) <= fr, "(7b) the timeline holds the energy strip (%d columns) and %d contact marks, BIG at %.2f s" % [tl.cg.size(), tl.bf.size(), tl.cg_peak])
	var img: Image = m.get_viewport().get_texture().get_image()
	ok(img.save_png(SHOT) == OK, "(7c) picture saved: " + SHOT)
	DirAccess.remove_absolute(wav)
	for f in DirAccess.get_files_at(out_dir):
		DirAccess.remove_absolute(out_dir + "/" + f)
	DirAccess.remove_absolute(out_dir)
	print("i22: ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
