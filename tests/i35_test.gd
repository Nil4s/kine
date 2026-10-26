## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i35_test.gd     (ROADMAP I35: sound cues, scripts/sound_cues.gd + sound_cues_ui.gd; needs a window)
## combo3 (read only) with a second fighter standing 1.2 m in front (as tests/i2_test.gd). Bars, written before measuring:
##  (1) HITS: every contact row the fighters' report finds has a hit cue within 1 frame (1/30 s) of its time, of the kind the struck part
##      names (head -> hit_head, a weapon -> hit_weapon, else hit_body); at least one contact exists
##  (2) WHOOSH: the hero's whoosh cues are exactly the speed peaks of the weapon tip above 8 m/s, counted here from WeaponTrail.sample's speeds
##      (local maxima, two of one swing merged when the dip stays above 60 % of the lower); each cue's frame is the peak's frame, its length >= 2 frames
##  (3) STRENGTH: strictly increasing with the peak speed over the whooshes, and with J over three synthetic hits (10 / 20 / 30 m/s) and over
##      the real combo3 hits measured here by HitPhysics.measure
##  (4) STEP: a 1-plant walk (t0 = 0.60 s) gets exactly one step cue, within 1 frame of t0; a scene with no plants gets touchdown cues
##      (a foot raised and put down) within 1 frame of the touchdown found here from the foot's height
##  (5) SHEET: the CSV has cues + 1 rows with the header time,frame,kind,strength,source; the JSON lists the same cues; written under
##      user://i35_<pid>/ only (nothing in exports/ or scenes/)
##  (6) KEEP: the scene JSON is byte-identical after deriving; Keep cues adds one 'sfx' marker per cue as ONE undo step; Ctrl+Z restores the
##      scene JSON byte for byte; apart from "markers" the JSON after Keep equals the one before
##  (7) SYNTH: each of the 5 kinds renders a finite, non-silent buffer (RMS > 0.01) with no sample outside -1..1; a stronger hit is louder;
##      the preview fires the cues the playhead passes (and none when muted)
##  (8) PLACEMENT: the cue lane is drawn inside the timeline: in the captured image a red hit disc and a blue whoosh mark sit in the lane band
##      at their cue's x; the picture is saved and looked at
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i35.png"
const D0 := 1.2
const FR := 1.0 / 30.0
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func stand_pose() -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


func still(pose: Dictionary, n := 2) -> Scene:
	var cards := []
	for i in n:
		cards.append({"name": "c%d" % i, "pose": pose, "move": -1.0 if i == 0 else 0.5, "hold": 2.0 if i == 0 else 3.0})
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": cards})
	return s


func sj(s: Scene) -> String:
	var d := s.to_dict(body())
	d.erase("actors")
	return JSON.stringify(d)


func sj_nomk(s: Scene) -> String:
	var d := s.to_dict(body())
	d.erase("actors")
	d.erase("markers")
	return JSON.stringify(d)


func ranks_agree(a: Array, b: Array) -> bool:   # a and b ordered the same way (strictly)
	for i in a.size():
		for j in a.size():
			if i != j and (a[i] < a[j]) != (b[i] < b[j]):
				return false
			if i != j and (a[i] == a[j] or b[i] == b[j]):
				return false
	return true


func front_hit(B: Body, striker_part: String, on: String, v: float) -> Dictionary:
	var a: Array = B.cap(on)
	var mid := ((a[0] as Vector3) + (a[1] as Vector3)) * 0.5
	return {"t": 1.0, "kind": "hit", "zone": "X", "part": striker_part, "on": on, "by": "hero", "vs": 1, "u": 0.6, "depth": 0.01, "speed": v,
		"at": mid + Vector3(0, 0, float(B.rad[on])), "vec": Vector3(0, 0, -v)}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still(stand_pose())})
	m._actors_sync()
	m._page_set("STAGE", false)
	m._refresh()
	await idle()
	var ui: SoundCuesUI = m.sc_ui
	var S: Scene = m.S
	var json0 := sj(S)
	var t_start := Time.get_ticks_msec()
	ui.compute()
	print("     derived %d cues in %.1f s: %s" % [ui.cues.size(), (Time.get_ticks_msec() - t_start) / 1000.0, ui.counts()])
	ok(sj(S) == json0, "(6) deriving the cues leaves the scene JSON byte-identical")

	# (1) HITS
	var hs: Scene = (m.actors_rt[0]["S"] as Scene).clone()
	var others := [{"name": "fighter 2", "S": (m.actors_rt[1]["S"] as Scene).clone(), "xf": m.actors_rt[1]["xf"]}]
	var rows: Array = m._fighters_measure(hs, others)["hits"]
	var hitc: Array = ui.cues.filter(func(c): return String(c["kind"]).begins_with("hit_"))
	var all_ok := not rows.is_empty()
	for r in rows:
		var want := SoundCues.hit_kind(r)
		var found := false
		for c in hitc:
			if absi(int(c["frame"]) - roundi(float(r["t"]) * 30.0)) <= 1 and c["kind"] == want and absf(float(c["t"]) - float(r["t"])) <= FR + 1e-4:
				found = true
		print("       contact %.3f s %s on %s (%s): cue %s" % [r["t"], r["part"], r["on"], r["kind"], "yes" if found else "NO"])
		all_ok = all_ok and found
	ok(all_ok and hitc.size() == rows.size(), "(1) %d contacts, %d hit cues, every contact has its cue within 1 frame with the kind its struck part names" % [rows.size(), hitc.size()])

	# (2) WHOOSH
	var tb := body()
	var smp := WeaponTrail.sample(hs, tb)
	var v: Array = smp["speed"]
	var raw := []
	for i in v.size():
		if v[i] >= 8.0 and v[i] >= (v[i - 1] if i > 0 else 0.0) and v[i] > (v[i + 1] if i + 1 < v.size() else 0.0):
			raw.append(i)
	var merged := []
	for i in raw:
		if not merged.is_empty():
			var j: int = merged[-1]
			var dip := 1e9
			for k in range(j, i + 1):
				dip = minf(dip, v[k])
			if dip >= 0.6 * minf(v[j], v[i]):
				if v[i] > v[j]:
					merged[-1] = i
				continue
		merged.append(i)
	var wc: Array = ui.cues.filter(func(c): return c["kind"] == "whoosh" and String(c["source"]).begins_with("hero"))
	var wf := wc.map(func(c): return int(c["frame"]))
	print("       tip speed peaks (>= 8 m/s): raw %d, merged %d at frames %s; cues at %s" % [raw.size(), merged.size(), merged, wf])
	print("       peak speeds %s, lengths (frames) %s" % [wc.map(func(c): return snappedf(c["speed"], 0.1)), wc.map(func(c): return roundi(c["len"] * 30.0))])
	ok(merged.size() >= 2 and wf == merged, "(2) %d hero whoosh cues = the %d speed peaks above 8 m/s, same frames" % [wc.size(), merged.size()])
	ok(wc.all(func(c): return c["len"] >= 2.0 * FR - 1e-6 and c["pitch"] > 300.0), "(2) every whoosh lasts >= 2 frames and has a pitch")
	var ws := wc.map(func(c): return float(c["speed"]))
	var wst := wc.map(func(c): return float(c["strength"]))
	var order_ok := true
	for i in ws.size():
		for j in ws.size():
			if ws[i] < ws[j] and not wst[i] < wst[j]:
				order_ok = false
	ok(order_ok, "(3) whoosh strength rises with the peak speed over %d whooshes" % ws.size())

	# (3) STRENGTH vs J
	var bb := body()
	bb.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	bb.ground()
	var sv := still(bb.to_dict())
	var acts := [{"S": still(bb.to_dict()), "B": body(), "xf": Transform3D.IDENTITY, "name": "a"}, {"S": sv, "B": bb, "xf": Transform3D.IDENTITY, "name": "b"}]
	var syn := [10.0, 20.0, 30.0].map(func(vv): return front_hit(bb, "hand_r", "head", vv))
	var sc3 := SoundCues.hits(syn, acts)
	var js := sc3.map(func(c): return float(c["J"]))
	var ss := sc3.map(func(c): return float(c["strength"]))
	print("       synthetic hits 10/20/30 m/s: J %s, strength %s" % [js.map(func(x): return snappedf(x, 0.1)), ss.map(func(x): return snappedf(x, 0.001))])
	ok(js[0] < js[1] and js[1] < js[2] and ss[0] < ss[1] and ss[1] < ss[2], "(3) three synthetic hits: strength rises with J")
	var Jr := []
	var Sr := []
	var aligned := SoundCues.hits(rows, m.actors_rt)   # one cue per row, in the rows' order
	for k in rows.size():
		var r: Dictionary = rows[k]
		if Body.is_wep(String(r["on"])):
			continue
		var vk: int = 0 if r["by"] == "other" else int(r["vs"])
		var sk: int = int(r["vs"]) if r["by"] == "other" else 0
		var bl := HitPhysics.measure(m.actors_rt[vk]["S"], m.actors_rt[vk]["B"], m.actors_rt[vk]["xf"], r, m.actors_rt[sk]["B"], m.actors_rt[sk]["S"])
		Jr.append((bl["J"] as Vector3).length())
		Sr.append(float(aligned[k]["strength"]))
		# and that cue is the one in the app's list
		if not hitc.any(func(c): return absf(float(c["strength"]) - float(aligned[k]["strength"])) < 1e-9 and c["kind"] == aligned[k]["kind"] and c["frame"] == aligned[k]["frame"]):
			Jr.append(-1.0)
			Sr.append(-1.0)
	ok(Jr.size() >= 1 and (Jr.size() < 2 or ranks_agree(Jr, Sr)), "(3) the %d combo3 body hits: strength ordered like J" % Jr.size())

	# (4) STEP
	var walk := still(bb.to_dict(), 3)
	walk.plants = [{"foot": "foot_l", "t0": 0.6, "t1": 1.0}]
	var wacts := [{"S": walk, "B": body(), "xf": Transform3D.IDENTITY, "name": "walker"}]
	var wcues := SoundCues.derive(wacts, [])
	var st: Array = wcues.filter(func(c): return c["kind"] == "step")
	ok(st.size() == 1 and absi(int(st[0]["frame"]) - 18) <= 1 and absf(float(st[0]["t"]) - 0.6) <= FR, "(4) a 1-plant walk gets one step cue at t0: %s" % [st.map(func(c): return [c["t"], c["frame"], c["strength"]])])
	# touchdowns: a foot lifted 0.15 m in card 2 and put down in card 3
	var b2 := body()
	b2.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b2.ground()
	var up := bb.to_dict()
	var bu := body()
	bu.from_dict(up)
	bu.ang["thigh_l"] = Vector3(70.0, 0.0, 0.0)   # the left thigh swung forward: the foot leaves the floor
	bu.fk()
	var lifted := bu.to_dict()
	var wk2 := Scene.new()
	wk2.from_dict({"scene": "zz_td", "fps": 30, "cards": [{"name": "a", "pose": up, "move": -1.0, "hold": 1.0}, {"name": "b", "pose": lifted, "move": 0.4, "hold": 0.3}, {"name": "c", "pose": up, "move": 0.3, "hold": 1.0}]})
	var tb2 := body()
	var tr := SoundCues.track(wk2, tb2)
	var low := 1e9
	for j in ["foot_l", "foot_r"]:
		for p in tr[j]:
			low = minf(low, (p as Vector3).y)
	var td_ref := []
	for j in ["foot_l", "foot_r"]:
		var upn := 0
		for i in (tr[j] as Array).size():
			var vv := 0.0 if i == 0 else ((tr[j][i] as Vector3) - (tr[j][i - 1] as Vector3)).length() * 30.0
			var dn: bool = (tr[j][i] as Vector3).y - low < 0.05 and vv < 0.6
			if dn and upn >= 3:
				td_ref.append(i)
			upn = 0 if dn else upn + 1
	print("       lifted foot_l y %.3f..%.3f, low %.3f" % [(tr["foot_l"] as Array).map(func(p): return p.y).min(), (tr["foot_l"] as Array).map(func(p): return p.y).max(), low])
	var tcs: Array = SoundCues.derive([{"S": wk2, "B": body(), "xf": Transform3D.IDENTITY, "name": "w2"}], []).filter(func(c): return c["kind"] == "step")
	print("       touchdowns found here at frames %s; cues at %s" % [td_ref, tcs.map(func(c): return c["frame"])])
	ok(tcs.size() == td_ref.size() and tcs.size() >= 1 and tcs.all(func(c): return td_ref.any(func(f): return absi(f - int(c["frame"])) <= 1)), "(4) a scene without plants: %d touchdown cues, each within 1 frame of the touchdown found from the foot's height" % tcs.size())

	# (5) SHEET
	var dir := "user://i35_%d" % OS.get_process_id()
	var exports_before := DirAccess.get_files_at("res://exports") if DirAccess.dir_exists_absolute("res://exports") else PackedStringArray()
	var res := ui.export_sheet(dir, "combo3")
	var lines := FileAccess.get_file_as_string(String(res.get("csv", dir + "/x"))).strip_edges().split("\n")
	var jd = JSON.parse_string(FileAccess.get_file_as_string(String(res.get("json", dir + "/x"))))
	ok(bool(res.get("ok", false)) and lines.size() == ui.cues.size() + 1 and lines[0] == "time,frame,kind,strength,source", "(5) the CSV has %d rows for %d cues (header: %s)" % [lines.size() - 1, ui.cues.size(), lines[0]])
	ok(jd is Dictionary and (jd["cues"] as Array).size() == ui.cues.size() and jd["format"] == SoundCues.FORMAT and int(jd["fps"]) == 30, "(5) the JSON lists the same %d cues" % [(jd["cues"] as Array).size() if jd is Dictionary else -1])
	var exports_after := DirAccess.get_files_at("res://exports") if DirAccess.dir_exists_absolute("res://exports") else PackedStringArray()
	ok(exports_before == exports_after, "(5) nothing was written in exports/")
	print("       first rows: ", lines.slice(0, 4))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))

	# (7) SYNTH + preview
	var loud := {}
	for k in SoundCues.KINDS:
		var buf := SoundCues.synth(k, 0.8, 900.0, 0.25)
		var fin := true
		var inr := true
		for x in buf:
			fin = fin and is_finite(x)
			inr = inr and absf(x) <= 1.0
		var r := SoundCues.rms(buf)
		loud[k] = r
		ok(buf.size() > 100 and fin and inr and r > 0.01, "(7) %s: %d samples, RMS %.3f" % [k, buf.size(), r])
	ok(SoundCues.rms(SoundCues.synth("hit_body", 0.9)) > SoundCues.rms(SoundCues.synth("hit_body", 0.2)), "(7) a stronger hit is louder")
	var n_before: int = ui.fired
	var t_end := S.length()
	var expect := ui.cues.size()
	ui.tick(-0.001, t_end, true)
	ok(ui.fired - n_before == expect, "(7) the preview fires every cue the playhead passes: %d of %d" % [ui.fired - n_before, expect])
	ui.muted = true
	var f2: int = ui.fired
	ui.tick(-0.001, t_end, true)
	ok(ui.fired == f2, "(7) muted: no cue fires")
	ui.muted = false
	ui._voices.clear()
	print("     audio player: %s" % ("running" if ui._pb != null else "none (no audio driver): the buffers above are checked instead"))

	# (6) KEEP
	var j_before := sj(S)
	var j_before_nomk := sj_nomk(S)
	var n_undo: int = m.undo.size()
	var nk := ui.keep()
	var kinds_ok: bool = S.markers.size() == nk and S.markers.all(func(mk): return mk["kind"] == "sfx")
	ok(nk == ui.cues.size() and kinds_ok and m.undo.size() == n_undo + 1, "(6) Keep cues: %d sfx markers, %d undo step" % [S.markers.size(), m.undo.size() - n_undo])
	ok(sj_nomk(S) == j_before_nomk, "(6) apart from the markers the scene JSON is untouched")
	m._undo()
	await idle()
	ok(sj(S) == j_before and S.markers.is_empty(), "(6) one Ctrl+Z restores the scene JSON byte for byte")
	ui.clear()
	ui.compute()
	await idle(3)

	# (8) PLACEMENT
	m.playhead = 0.84
	ui._panel()
	m._say("sound cues: " + ui.summary())
	m._refresh()
	await idle(5)
	var tl: Control = m.ui_timeline
	var img: Image = root.get_texture().get_image()
	var tr_ := Rect2(tl.global_position, tl.size)
	var vp := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	ok(vp.encloses(tr_) and tl.sc.size() == ui.cues.size(), "(8) the timeline is inside the window and carries %d marks" % tl.sc.size())
	var red: Color = Tok.c("mk_red")
	var blue: Color = Tok.c("mk_blue")
	var green: Color = Tok.c("mk_green")
	var found := {"hit": 0, "whoosh": 0, "all_hit": 0, "all_whoosh": 0}
	for c in ui.cues:
		var kk := String(c["kind"])
		if kk != "whoosh" and not kk.begins_with("hit_"):
			continue
		var px: float = tl.global_position.x + tl.x_of(float(c["t"]))
		var want: Color = blue if kk == "whoosh" else red
		var cnt := 0
		for y in range(int(tr_.position.y), int(tr_.end.y)):
			for x in range(int(px) - 1, int(px) + 2):
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					var p := img.get_pixel(x, y)
					if absf(p.r - want.r) < 0.06 and absf(p.g - want.g) < 0.06 and absf(p.b - want.b) < 0.06:
						cnt += 1
		found["all_whoosh" if kk == "whoosh" else "all_hit"] += 1
		if cnt >= 3:
			found["whoosh" if kk == "whoosh" else "hit"] += 1
	print("       lane marks found in the image: ", found)
	ok(found["all_hit"] >= 1 and found["hit"] == found["all_hit"] and found["all_whoosh"] >= 1 and found["whoosh"] == found["all_whoosh"], "(8) every hit disc (red) and whoosh mark (blue) is in the picture at its cue's x")
	img.save_png(SHOT)
	print("     screenshot: ", SHOT)
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
