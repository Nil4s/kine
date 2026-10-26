## godot --headless --path . -s tests/beat_track_test.gd     (ROADMAP 32; headless: no window, no sound played)
## MUSIC BEATS. Bars written before the first run:
##  (1) a synthetic click track at 120 BPM (1 kHz bursts, written as a WAV in user://, every 4th click louder):
##      the tempo is 120 +- 1 BPM, every detected beat is within 15 ms of a click, nearly every click is found, and the
##      loud clicks come out as the bars' first beats
##  (2) the same at 97 BPM
##  (3) snap: each contact card (a card a hit marker sits on) lands within 1 frame of a beat, and no move changes by more
##      than 25 %. A beat that would need more is REFUSED with a message, and the scene is left as it was
##  (4) old scenes: every file in scenes/ loads, saves with no "beats_audio" key, and saves the same again after a reload
extends SceneTree

var fails := 0
const RATE := 44100
const WAV120 := "user://zz_beats_120.wav"
const WAV97 := "user://zz_beats_97.wav"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a 16-bit mono WAV of clicks: [PackedByteArray wav, Array of click onset times (s), Array of loud-click flags]
func click_wav(bpm: float, secs: float, lead: float) -> Array:
	var n := int(secs * RATE)
	var f := PackedFloat32Array()
	f.resize(n)
	var truth := []
	var loud := []
	var k := 0
	while true:
		var t := lead + k * 60.0 / bpm
		if t >= secs - 0.05:
			break
		var s0 := int(round(t * RATE))
		var amp := 1.0 if k % 4 == 0 else 0.5
		for i in int(0.008 * RATE):
			if s0 + i >= n:
				break
			f[s0 + i] += amp * exp(-float(i) / (0.002 * RATE)) * sin(TAU * 1000.0 * i / RATE)
		truth.append(float(s0) / RATE)
		loud.append(k % 4 == 0)
		k += 1
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		pcm.encode_s16(i * 2, int(round(clampf(f[i], -1.0, 1.0) * 32767.0)))
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)
	h.encode_u32(12, 0x20746d66)
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)
	h.encode_u16(22, 1)
	h.encode_u32(24, RATE)
	h.encode_u32(28, RATE * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)
	h.encode_u32(40, pcm.size())
	h.append_array(pcm)
	return [h, truth, loud]


## the detection checks for one tempo: returns [bpm, worst error (s) of the beats, share of clicks found, loud clicks marked]
func check_track(path: String, bpm_want: float, tag: String, truth: Array, loud: Array) -> void:
	var st := AudioTrack.load_stream(path)
	ok(st != null, "%s: the click WAV loads" % tag)
	var r := BeatTrack.analyze(st)
	ok(r["ok"], "%s: beats found (%s)" % [tag, r["msg"]])
	if not r["ok"]:
		return
	var bpm: float = r["bpm"]
	ok(absf(bpm - bpm_want) <= 1.0, "%s: tempo %.2f BPM, want %.1f +- 1" % [tag, bpm, bpm_want])
	var beats: Array = r["beats"]
	var worst := 0.0
	for b in beats:
		var best := INF
		for t in truth:
			best = minf(best, absf(float(b["t"]) - float(t)))
		worst = maxf(worst, best)
	ok(worst <= 0.015, "%s: every beat within 15 ms of a click (worst %.1f ms over %d beats)" % [tag, worst * 1000.0, beats.size()])
	# clicks found: a click counts when a beat sits within 15 ms of it (the first one and the last are not counted: edges)
	var found := 0
	var n_cnt := 0
	for i in range(1, truth.size() - 1):
		n_cnt += 1
		for b in beats:
			if absf(float(b["t"]) - float(truth[i])) <= 0.015:
				found += 1
				break
	var share := float(found) / maxf(n_cnt, 1)
	ok(share >= 0.95, "%s: %.0f%% of the clicks found as beats (bar 95%%)" % [tag, share * 100.0])
	# bars: the loud clicks are the downbeats
	var downs := 0
	var loud_hit := 0
	var n_loud := 0
	for i in range(1, truth.size() - 1):
		if loud[i]:
			n_loud += 1
			for b in beats:
				if b["down"] and absf(float(b["t"]) - float(truth[i])) <= 0.015:
					loud_hit += 1
					break
	for b in beats:
		if b["down"]:
			downs += 1
	ok(n_loud > 0 and float(loud_hit) / n_loud >= 0.9, "%s: the loud clicks are the bars' first beats (%d of %d; %d bars marked)" % [tag, loud_hit, n_loud, downs])


func load_scene(d: Dictionary) -> Scene:
	var sc := Scene.new()
	sc.from_dict(d)
	return sc


func _init() -> void:
	# ---- (1) and (2): 120 BPM and 97 BPM click tracks
	var c120 := click_wav(120.0, 24.0, 0.4)
	var f := FileAccess.open(WAV120, FileAccess.WRITE)
	f.store_buffer(c120[0])
	f.close()
	check_track(WAV120, 120.0, "120 BPM", c120[1], c120[2])
	var c97 := click_wav(97.0, 24.0, 0.4)
	f = FileAccess.open(WAV97, FileAccess.WRITE)
	f.store_buffer(c97[0])
	f.close()
	check_track(WAV97, 97.0, "97 BPM", c97[1], c97[2])

	# ---- (3) snap: a real scene (combo3, read only), a hit marker on two of its cards, beats a little off each arrival
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	var S := load_scene(d)
	var B := Choreo._body()
	var ts: Array = S.times()
	ok(S.cards.size() >= 6, "snap: combo3 has %d cards (need 6)" % S.cards.size())
	if S.cards.size() >= 6:
		var a3 := float(ts[3][1])
		var a5 := float(ts[5][1])
		var m3 := S.move_time(3)
		var m5 := S.move_time(5)
		S.markers = [{"t": a3, "name": "hit a", "kind": "hit"}, {"t": a5, "name": "hit b", "kind": "hit"}]
		var d3 := 0.1 * m3
		var d5 := 0.1 * m5
		var beats := [{"t": a3 + d3, "down": false}, {"t": a5 + d3 + d5, "down": false}]   # a fraction of a move off each arrival
		var before := JSON.stringify(S.cards)
		var trial := S.clone()
		var r := BeatTrack.snap(trial, beats, 0.0)
		ok(r["ok"] and int(r["contacts"]) == 2, "snap: two contact cards snapped (%s)" % r["msg"])
		var frame := 1.0 / S.fps
		var nts: Array = trial.times()
		var a3n := float(nts[3][1])
		var a5n := float(nts[5][1])
		ok(absf(a3n - (a3 + d3)) <= frame and absf(a5n - (a5 + d3 + d5)) <= frame, "snap: contacts land within 1 frame of their beats (%.1f ms, %.1f ms)" % [absf(a3n - (a3 + d3)) * 1000.0, absf(a5n - (a5 + d3 + d5)) * 1000.0])
		var capped := true
		for mv in r["moves"]:
			var i := int(mv[0])
			if absf(float(mv[1])) > 0.25 * S.move_time(i) + 1e-6:
				capped = false
		ok(capped, "snap: no move changed by more than 25 %")
		ok(JSON.stringify(S.cards) == before, "snap: the real scene is not touched by the snap (it runs on a clone)")
		# refusal: a beat half a move away from card 3 must be refused, the message says why, nothing moves
		var far := [{"t": a3 + 0.5 * m3, "down": false}]
		var t2 := S.clone()
		var r2 := BeatTrack.snap(t2, far, 0.0)
		ok(not r2["ok"] and String(r2["msg"]).begins_with("refused"), "snap: a 50 %% retime is refused with a message (%s)" % r2["msg"])
		ok(JSON.stringify(t2.cards) == before, "snap: a refused snap leaves the cards as they were")
		# the saved scene keeps the beats: only when there are any
		S.beats_audio = BeatTrack.clean_list([{"t": 0.5, "down": true}, {"t": 0.25, "down": false}])
		var out := S.to_dict(B, false)
		ok(out.has("beats_audio") and out["beats_audio"].size() == 2 and float(out["beats_audio"][0]["t"]) == 0.25, "snap: beats_audio saves sorted")
		var back := load_scene(JSON.parse_string(JSON.stringify(out)))
		ok(back.beats_audio.size() == 2 and bool(back.beats_audio[1]["down"]), "snap: beats_audio reloads")

	# ---- (4) old scenes: no beats_audio key, and the same bytes again after a reload
	var dir := DirAccess.open("res://scenes")
	var names := []
	if dir != null:
		for fn in dir.get_files():
			if fn.ends_with(".json"):
				names.append(fn)
	names.sort()
	var checked := 0
	var bad := 0
	for fn in names:
		var dd: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + fn))
		if not (dd is Dictionary) or not dd.has("cards"):
			continue
		var s1 := load_scene(dd)
		var txt1 := JSON.stringify(s1.to_dict(B, false))
		var txt2 := JSON.stringify(load_scene(JSON.parse_string(txt1)).to_dict(B, false))
		if txt1.contains("\"beats_audio\"") or txt1 != txt2:
			bad += 1
		checked += 1
	ok(checked > 0 and bad == 0, "old scenes: %d scene files load, save with no beats_audio key and save the same again (%d bad)" % [checked, bad])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV120))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV97))
	print("BEAT TRACK TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
