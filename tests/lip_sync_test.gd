## godot --headless --path . -s tests/lip_sync_test.gd     (ROADMAP 31: lip-sync from the audio track)
## Bars written before the first run. Clips are generated into user:// (16 kHz, 16 bit, 3.0 s: 0.5 s silence, 2.0 s
## 200 Hz tone with an amplitude 0.5 (1 - cos(2 pi f_mod (t - 0.5))) envelope, 0.5 s silence):
##  (1) silence: in 0.15 s .. 0.35 s and 2.65 s .. 2.85 s the jaw is < 0.5 deg and the mouth shape is M (closed)
##  (2) jaw at 5 Hz: the local maxima of the jaw over the tone are EXACTLY the envelope's peaks (0.6 + 0.2 k, k = 0..9),
##      each within one frame (1 / 30 s), and there are 10 of them (no spurious opening)
##  (3) no change faster than 8 Hz: jaw extrema per second <= 16 (the 5 Hz clip gives 10). Control: the same clip with
##      a 20 Hz envelope has a jaw swing (peak to peak over the tone) < 0.25 of the 5 Hz one: the smoother takes 20 Hz out
##      mouth-shape changes inside the tone <= 8 per second
##  (4) old scenes: combo3 saves with NO "lip" key; a baked channel round-trips through the file form unchanged
##  (5) the command (Lip-sync: from the audio track) bakes S.lip from the sound on the timeline, is ONE undo step, and
##      Ctrl+Z puts the scene back exactly (the channel is gone). A wav that cannot be read bakes nothing and says why.
extends SceneTree

var fails := 0
var m: Node
const RATE := 16000
const FPS := 30
const WAV := "user://zz_lip_5hz.wav"
const WAV20 := "user://zz_lip_20hz.wav"
const BAD := "user://zz_lip_notes.ogg"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a 44-byte RIFF header + 16-bit mono PCM
func wav_bytes(samples: PackedFloat32Array) -> PackedByteArray:
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
	h.encode_u32(24, RATE)
	h.encode_u32(28, RATE * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)
	h.encode_u32(40, pcm.size())
	h.append_array(pcm)
	return h


func clip(mod_hz: float) -> PackedFloat32Array:
	var n := int(3.0 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		if t >= 0.5 and t < 2.5:
			var env := 0.5 * (1.0 - cos(TAU * mod_hz * (t - 0.5)))
			s[i] = 0.5 * env * sin(TAU * 200.0 * t)
	return s


func write_bytes(path: String, b: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


## the jaw curve on the frame grid over [0, 3] s, from a clip (the same path as the command)
func bake_clip(path: String) -> Dictionary:
	var r := LipSync.read_wav(path)
	if not r["ok"]:
		return {}
	var A := LipSync.analyse(LipSync.windows(r["mono"], int(r["rate"])))
	return LipSync.bake(A, FPS, 0.0, 3.0)


func jaw_series(lip: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(3.0 * FPS) + 1
	for f in n:
		out.append(LipSync.jaw_at(lip, float(f) / FPS))
	return out


func extrema(v: PackedFloat32Array) -> int:
	var c := 0
	for i in range(1, v.size() - 1):
		var a := v[i] - v[i - 1]
		var b := v[i + 1] - v[i]
		if absf(a) > 1e-3 and absf(b) > 1e-3 and (a > 0.0) != (b > 0.0):
			c += 1
	return c


func _init() -> void:
	write_bytes(WAV, wav_bytes(clip(5.0)))
	write_bytes(WAV20, wav_bytes(clip(20.0)))
	var lip := bake_clip(WAV)
	ok(lip.has("jaw") and lip["jaw"].size() == int(3.0 * FPS) + 1, "0 a 16 kHz wav reads and bakes one jaw key per frame (%d)" % lip.get("jaw", []).size())

	# (1) silence
	var quiet := true
	var worst := 0.0
	for t in [0.15, 0.2, 0.25, 0.3, 0.35, 2.65, 2.7, 2.75, 2.8, 2.85]:
		var j := LipSync.jaw_at(lip, t)
		worst = maxf(worst, j)
		quiet = quiet and j < 0.5 and LipSync.shape_at(lip, t) == "M"
	ok(quiet, "1 silence: jaw < 0.5 deg and shape M in both silences (worst %.3f deg)" % worst)

	# (2) peaks at 5 Hz
	var js := jaw_series(lip)
	var mx := 0.0
	for v in js:
		mx = maxf(mx, v)
	var peaks := []
	for i in range(1, js.size() - 1):
		if js[i] > js[i - 1] and js[i] >= js[i + 1] and js[i] > 0.3 * mx:
			peaks.append(float(i) / FPS)
	var expect := []
	for k in 10:
		expect.append(0.6 + 0.2 * k)
	var within := peaks.size() == expect.size()
	var dev := 0.0
	if within:
		for k in expect.size():
			dev = maxf(dev, absf(float(peaks[k]) - float(expect[k])))
			within = within and absf(float(peaks[k]) - float(expect[k])) <= 1.0 / FPS + 1e-6
	ok(within, "2 jaw opens at 5 Hz: %d peaks, worst offset %.4f s (bar 1 frame = %.4f s), peak %.1f deg" % [peaks.size(), dev, 1.0 / FPS, mx])

	# (3) no change faster than 8 Hz, and the control
	var ex := extrema(js)
	var ok8 := float(ex) / 3.0 <= 16.0
	ok(ok8, "3a jaw extrema %d in 3 s = %.1f per second (bar 16 = 2 x 8 Hz; the 5 Hz clip gives 10)" % [ex, float(ex) / 3.0])
	var lip20 := bake_clip(WAV20)
	var js20 := jaw_series(lip20)
	var p2p5 := 0.0
	var p2p20 := 0.0
	for f in range(int(0.6 * FPS), int(2.4 * FPS) + 1):
		p2p5 = maxf(p2p5, js[f])
		p2p20 = maxf(p2p20, js20[f])
	var lo5 := 99.0
	var lo20 := 99.0
	for f in range(int(0.6 * FPS), int(2.4 * FPS) + 1):
		lo5 = minf(lo5, js[f])
		lo20 = minf(lo20, js20[f])
	var sw5 := p2p5 - lo5
	var sw20 := p2p20 - lo20
	ok(sw20 < 0.25 * sw5, "3b control: 20 Hz swing %.2f deg < 0.25 x the 5 Hz swing %.2f deg (the smoother removes it)" % [sw20, sw5])
	var changes := 0
	for k in lip["mouth"]:
		if float(k["t"]) > 0.5 and float(k["t"]) < 2.5:
			changes += 1
	ok(float(changes) / 2.0 <= 8.0, "3c mouth-shape changes inside the tone: %d in 2 s (bar 8 per second)" % changes)

	# (4) scenes: no key on old scenes; the file form round-trips
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	var d: Dictionary = m.S.to_dict(m.B)
	ok(not d.has("lip"), "4a combo3 (no lip-sync) saves with no \"lip\" key")
	var back := LipSync.from_file(LipSync.to_file(lip))
	var same: bool = back["jaw"].size() == lip["jaw"].size() and back["mouth"].size() == lip["mouth"].size()
	if same:
		for k in lip["jaw"].size():
			same = same and absf(float(back["jaw"][k]["t"]) - float(lip["jaw"][k]["t"])) < 1e-4 and absf((back["jaw"][k]["v"] as Vector3).x - (lip["jaw"][k]["v"] as Vector3).x) < 1e-4
	ok(same, "4b the baked channel survives the file form (%d jaw keys, %d mouth keys)" % [back["jaw"].size(), back["mouth"].size()])

	# (5) the command, its undo, and a file it cannot read
	m._audio_set(ProjectSettings.globalize_path(WAV))
	await idle(2)
	var before := JSON.stringify(m.S.to_dict(m.B))
	var u0: int = m.undo.size()
	m._lip_from_audio()
	await idle(2)
	ok(m.S.lip.has("jaw") and not (m.S.lip["jaw"] as Array).is_empty() and m.undo.size() == u0 + 1, "5a the command bakes S.lip and pushes ONE undo step")
	var baked: Dictionary = m.S.to_dict(m.B)
	ok(baked.has("lip") and baked["lip"]["jaw"].size() > 100, "5b the scene saves the channel under \"lip\"")
	m._undo()
	await idle(2)
	ok(m.S.lip.is_empty() and JSON.stringify(m.S.to_dict(m.B)) == before, "5c Ctrl+Z (undo) removes the channel: the scene saves exactly as before")
	write_bytes(BAD, PackedByteArray([79, 103, 103, 83]))
	m.S.audio_tracks = [{"path": ProjectSettings.globalize_path(BAD), "offset": 0.0, "gain_db": 0.0}]   # an .ogg that is not one: _audio_set would refuse it
	m.S.lip = {}
	m._lip_from_audio()
	ok(m.S.lip.is_empty(), "5d a sound that is not a readable wav bakes nothing")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV20))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BAD))
	print("LIP SYNC TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	quit(fails)
