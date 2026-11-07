## godot --headless --path . -s tests/fpswave_test.gd     (L92: ROADMAP_400 L19 frame-rate conversion with sub-frame keys + L14 sound waveform in the graph editor)
## Bars written BEFORE the implementation (scripts/fps_convert.gd, scripts/fps_wave.gd, CurveEditor.wave_*, Timeline.lane_columns):
##  A  24 -> 30 fps: every part key keeps its time within 1e-9 s (sub-frame keys); the pose sampled at 100 random times matches within 1e-6 deg
##     (Scene.sample, every joint); 24 -> 30 -> 24 saves byte-identical (JSON of Scene.to_dict, and the keys' times exactly); also 24 -> 60 -> 24
##     and 30 -> 60 -> 30; the frame-indexed lists (notes "frame", boxes f0 / f1) follow the new rate (frame / old * new, rounded)
##  B  SNAP option: each key moves at most half a new frame (+1e-9), every moved key lands on a whole new frame, a key that would land on
##     its neighbour's frame stays where it is, the report names every move (what, joint, index, from, to) and its count equals the keys
##     that really changed; the fps changes; the same snap is idempotent (a second run reports 0 moves)
##  C  CONTROL: a naive conversion (frame N stays frame N: t' = (t * old) / new) must FAIL the time bar (> 1e-9) and the pose bar (> 1e-6 deg)
##  D  WAVEFORM: a 44.1 kHz tone (loud 0..1.5 s and 2.0..4.0 s of the file, offset 0.25 s => loud 0.25..1.75 and 2.25..4.25 on the timeline).
##     The graph editor's loud runs and the timeline lane's loud runs: centre times agree within 1 px at the EDITOR's zoom, and each is within
##     1 px of the true centre (1.0 s, 3.25 s). Control: the editor's columns moved 3 px FAIL that bar. Toggle off: wave_lines() is empty,
##     on: not empty, every segment inside the plot; no audio track: empty even when on
##  E  UNDO: convert and convert-with-snap are ONE undo step each (the step holds the state before); a refused convert (same rate, bad rate) none;
##     the waveform toggle changes the view only: none
##  F  TOOL "fps_wave" is in AgentTools.MCP_EXTRA and tools/mcp/poser_mcp.py (MATH_TOOLS and the table)
extends SceneTree

var fails := 0
const J := ["lowerarm_r", "upperarm_l", "thigh_r"]
const WAV := "user://zz_fpswave.wav"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func make_scene(B: Body, seed_: int) -> Scene:
	var S := Scene.new()
	for i in 3:
		S.add("c%d" % i, B.to_dict())
	S.fps = 24
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var pk := {}
	for j in J:
		var ks := []
		var t := 0.0
		for i in 8:
			t += 0.05 + rng.randf() * 0.4   # free floats: almost never on a frame
			ks.append({"t": t, "v": Vector3(rng.randf_range(-40, 40), rng.randf_range(-20, 20), rng.randf_range(-15, 15))})
		pk[j] = ks
	S.part_keys = pk
	S.notes = [{"frame": 0, "text": "a"}, {"frame": 7, "text": "b"}, {"frame": 31, "text": "c"}, {"frame": 90, "text": "d"}]
	S.markers = [{"t": 0.3333, "name": "m", "kind": "marker"}]
	S.boxes = [{"kind": "hit", "f0": 4, "f1": 9, "part": "hand_r", "a": [0, 0, 0], "b": [0, 0, 0], "r": 0.1}]
	return S


func key_times(S: Scene) -> Array:
	var o := []
	for j in J:
		for k in S.part_keys[j]:
			o.append(float(k["t"]))
	return o


func worst_dt(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		w = maxf(w, absf(float(a[i]) - float(b[i])))
	return w


## the worst joint angle difference (deg) between two scenes over the given times
func worst_pose(A: Scene, C: Scene, times: Array) -> float:
	var w := 0.0
	for t in times:
		var a: Dictionary = A.sample(t)["ang"]
		var c: Dictionary = C.sample(t)["ang"]
		for j in a:
			if a[j] is Vector3 and c.has(j):
				var d: Vector3 = (a[j] as Vector3) - (c[j] as Vector3)
				w = maxf(w, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
	return w


func file_of(S: Scene, B: Body) -> String:
	return JSON.stringify(S.to_dict(B))


func naive(S: Scene, new_fps: int) -> void:
	var old := S.fps
	for j in S.part_keys:
		for k in S.part_keys[j]:
			k["t"] = (float(k["t"]) * old) / new_fps   # frame N stays frame N
	S.fps = new_fps


## loud runs of a column list [(x, peak)] as [[x0, x1)]; the threshold is half of full scale
func runs(cols: PackedVector2Array) -> Array:
	var out := []
	var start := -1.0
	var last := -1.0
	for c in cols:
		if c.y > 0.5:
			if start < 0.0:
				start = c.x
			last = c.x
		elif start >= 0.0:
			out.append([start, last + 1.0])
			start = -1.0
	if start >= 0.0:
		out.append([start, last + 1.0])
	return out


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var stub_src := "extends Node\nvar S\nvar undo := []\nvar audio_envs := []\nvar audio_pick := -1\nvar ui_curve = null\nvar graph_wave := false\nfunc _push_undo() -> void:\n\tundo.append(var_to_str(S.fps) + '|' + var_to_str(S.part_keys))\n"
	var gs := GDScript.new()
	gs.source_code = stub_src
	gs.reload()

	# ---- A  24 -> 30 -> 24
	var S := make_scene(B, 92)
	var base_file := file_of(S, B)
	var t_before := key_times(S)
	var ref := make_scene(B, 92)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var times := []
	for i in 100:
		times.append(rng.randf() * 4.0)
	var r := FpsConvert.convert(S, 30, false)
	var dt := worst_dt(t_before, key_times(S))
	ok(bool(r.get("ok", false)) and S.fps == 30 and dt <= 1e-9, "A1 24 -> 30: fps %d, 24 keys, worst key time change %.12f s (<= 1e-9)" % [S.fps, dt])
	var subframe := 0
	for t in key_times(S):
		if absf(t * 30.0 - roundf(t * 30.0)) > 1e-6:
			subframe += 1
	ok(subframe >= 20, "A2 the keys are real sub-frame keys at 30 fps: %d of 24 sit between frames (>= 20)" % subframe)
	var wp := worst_pose(ref, S, times)
	ok(wp <= 1e-6, "A3 pose at 100 random times, worst joint difference %.9f deg (<= 1e-6)" % wp)
	ok(S.notes[1]["frame"] == 9 and S.notes[2]["frame"] == 39 and S.notes[3]["frame"] == 112 and S.boxes[0]["f0"] == 5 and S.boxes[0]["f1"] == 11, "A4 notes / boxes frames follow the rate: 7 -> %d, 31 -> %d, 90 -> %d, box 4..9 -> %d..%d" % [S.notes[1]["frame"], S.notes[2]["frame"], S.notes[3]["frame"], S.boxes[0]["f0"], S.boxes[0]["f1"]])
	FpsConvert.convert(S, 24, false)
	var back := file_of(S, B)
	ok(back == base_file and var_to_str(key_times(S)) == var_to_str(t_before), "A5 24 -> 30 -> 24 is byte-identical (%d chars of JSON, key times exact)" % back.length())
	for pair in [[24, 60], [30, 60]]:
		var S2 := make_scene(B, 5)
		S2.fps = pair[0]
		var f0 := file_of(S2, B)
		var tb2 := key_times(S2)
		FpsConvert.convert(S2, pair[1], false)
		var d2 := worst_dt(tb2, key_times(S2))
		FpsConvert.convert(S2, pair[0], false)
		ok(d2 <= 1e-9 and file_of(S2, B) == f0, "A6 %d -> %d -> %d: key times within %.12f, saves byte-identical" % [pair[0], pair[1], pair[0], d2])

	# ---- B  snap
	var Sn := make_scene(B, 92)
	var tb := key_times(Sn)
	var rep := FpsConvert.convert(Sn, 30, true)
	var ta := key_times(Sn)
	var half := 0.5 / 30.0
	var mx := 0.0
	var changed := 0
	var off_grid := 0
	var moves: Array = rep.get("moves", [])
	var named := 0
	for i in ta.size():
		var d := absf(ta[i] - tb[i])
		mx = maxf(mx, d)
		if d > 1e-12:
			changed += 1
	for mv in moves:
		if mv is Dictionary and mv.has("joint") and mv.has("i") and mv.has("from") and mv.has("to") and mv.has("what"):
			named += 1
	var kept := int(rep.get("kept", 0))
	for t in ta:
		if absf(t * 30.0 - roundf(t * 30.0)) > 1e-6:
			off_grid += 1
	ok(bool(rep.get("ok", false)) and Sn.fps == 30 and mx <= half + 1e-9, "B1 snap to 30 fps: fps %d, largest key move %.6f s (<= half a frame %.6f)" % [Sn.fps, mx, half])
	ok(moves.size() == changed and named == moves.size() and changed > 0, "B2 the report names every move: %d moves reported, %d keys really changed, %d fully described" % [moves.size(), changed, named])
	ok(off_grid == kept, "B3 every key is on a whole frame except the %d kept in place (reported kept = %d)" % [off_grid, kept])
	var rep2 := FpsConvert.convert(Sn, 30, true)
	ok((rep2.get("moves", [1]) as Array).size() == 0, "B4 a second snap at the same rate moves nothing (%d moves)" % (rep2.get("moves", [1]) as Array).size())
	var Sm := make_scene(B, 92)
	FpsConvert.convert(Sm, 60, true)
	var mx60 := worst_dt(tb, key_times(Sm))
	ok(mx60 <= 0.5 / 60.0 + 1e-9, "B5 snap to 60 fps: largest move %.6f s (<= %.6f)" % [mx60, 0.5 / 60.0])
	# two keys that would share a frame: neither is lost, the second stays
	var Sc := make_scene(B, 1)
	Sc.part_keys = {J[0]: [{"t": 0.500, "v": Vector3(1, 2, 3)}, {"t": 0.505, "v": Vector3(4, 5, 6)}]}
	FpsConvert.convert(Sc, 30, true)
	var cks: Array = Sc.part_keys[J[0]]
	ok(cks.size() == 2 and float(cks[0]["t"]) < float(cks[1]["t"]), "B6 two keys in one frame: both kept, in order (%.4f, %.4f)" % [cks[0]["t"], cks[1]["t"]])

	# ---- C  control: naive
	var Sx := make_scene(B, 92)
	naive(Sx, 30)
	var ndt := worst_dt(t_before, key_times(Sx))
	var npose := worst_pose(ref, Sx, times)
	ok(ndt > 1e-9, "C1 CONTROL naive frame-index conversion fails the time bar: worst key time change %.6f s (> 1e-9 = the bar fails, as it must)" % ndt)
	ok(npose > 1e-6, "C2 CONTROL naive conversion fails the pose bar: worst difference %.4f deg (> 1e-6)" % npose)

	# ---- D  waveform
	var f := FileAccess.open(WAV, FileAccess.WRITE)
	f.store_buffer(AudioTrack.sine_wav_bytes(44100, 4.0, 1000.0, 0.8, 1.5, 2.0))
	f.close()
	var env := AudioTrack.envelope(AudioTrack.load_stream(WAV), WAV)
	ok(bool(env.get("ok", false)), "D0 the test tone decodes (envelope ok)")
	var Sw := make_scene(B, 3)
	Sw.audio_tracks = [{"path": WAV, "offset": 0.25, "gain_db": 0.0}]
	var wm: Node = gs.new()
	wm.S = Sw
	wm.audio_envs = [env]
	var ed := CurveEditor.new()
	ed.size = Vector2(400, 200)
	ed.scene = Sw
	ed.joint = J[0]
	ed.t0 = 0.0
	ed.t1 = 5.0
	ed.wave_envs = [env]
	ed.wave_on = true
	var tl := Timeline.new()
	tl.m = wm
	tl.size = Vector2(1000, 120)
	var eruns := runs(ed.wave_columns())
	var truns := runs(tl.lane_columns(Sw, 0, env))
	ok(eruns.size() == 2 and truns.size() == 2, "D1 two loud runs in the editor (%d) and on the timeline (%d)" % [eruns.size(), truns.size()])
	if eruns.size() == 2 and truns.size() == 2:
		var truth := [1.0, 3.25]
		var worst_cross := 0.0
		var worst_true := 0.0
		for k in 2:
			var ec := ed.x_to_t((float(eruns[k][0]) + float(eruns[k][1])) * 0.5)
			var tc := tl.t_of((float(truns[k][0]) + float(truns[k][1])) * 0.5)
			worst_cross = maxf(worst_cross, absf(ed.t_to_x(ec) - ed.t_to_x(tc)))
			worst_true = maxf(worst_true, absf(ed.t_to_x(ec) - ed.t_to_x(truth[k])))
		ok(worst_cross <= 1.0, "D2 run centres, editor vs timeline: worst %.3f px at the editor's zoom (%.1f px/s) (<= 1)" % [worst_cross, ed.plot().size.x / (ed.t1 - ed.t0)])
		ok(worst_true <= 1.0, "D3 run centres, editor vs the true 1.00 s / 3.25 s: worst %.3f px (<= 1)" % worst_true)
		# control: the editor's columns shifted 3 px must fail the 1 px bar
		var shifted := PackedVector2Array()
		for c in ed.wave_columns():
			shifted.append(Vector2(c.x + 3.0, c.y))
		var sr := runs(shifted)
		var sw := 0.0
		for k in 2:
			var ec := ed.x_to_t((float(sr[k][0]) + float(sr[k][1])) * 0.5)
			var tc := tl.t_of((float(truns[k][0]) + float(truns[k][1])) * 0.5)
			sw = maxf(sw, absf(ed.t_to_x(ec) - ed.t_to_x(tc)))
		ok(sw > 1.0, "D4 CONTROL columns moved 3 px fail the bar: worst %.3f px (> 1 = fails, as it must)" % sw)
	var lines := ed.wave_lines()
	var inside := true
	var pl := ed.plot()
	for p in lines:
		inside = inside and p.x >= pl.position.x - 0.01 and p.x <= pl.end.x + 0.01 and p.y >= pl.position.y - 0.01 and p.y <= pl.end.y + 0.01
	ok(lines.size() > 0 and lines.size() % 2 == 0 and inside, "D5 toggle on: %d segment ends, all inside the plot" % lines.size())
	ed.wave_on = false
	ok(ed.wave_lines().size() == 0 and ed.wave_columns().size() == 0, "D6 toggle off draws nothing (%d segment ends)" % ed.wave_lines().size())
	ed.wave_on = true
	var Sno := make_scene(B, 3)
	ed.scene = Sno
	ok(ed.wave_lines().size() == 0, "D7 no audio track: nothing drawn even when on")
	ed.free()
	tl.free()

	# ---- E  undo
	var m: Node = gs.new()
	var Su := make_scene(B, 92)
	m.S = Su
	var u0: int = m.undo.size()
	var q := FpsWave.serve(m, {"action": "convert", "fps": 30})
	ok(bool(q.get("ok", false)) and m.undo.size() == u0 + 1 and String(m.undo[-1]).begins_with("24|") and Su.fps == 30, "E1 convert = ONE undo step holding the state before (steps %d -> %d, fps now %d)" % [u0, m.undo.size(), Su.fps])
	u0 = m.undo.size()
	q = FpsWave.serve(m, {"action": "convert", "fps": 60, "snap": true})
	ok(bool(q.get("ok", false)) and m.undo.size() == u0 + 1 and Su.fps == 60, "E2 convert with snap = ONE undo step (steps %d -> %d)" % [u0, m.undo.size()])
	u0 = m.undo.size()
	var q1 := FpsWave.serve(m, {"action": "convert", "fps": 60})
	var q2 := FpsWave.serve(m, {"action": "convert", "fps": 0})
	var q3 := FpsWave.serve(m, {"action": "convert", "fps": 5000})
	ok(not bool(q1.get("ok", true)) and not bool(q2.get("ok", true)) and not bool(q3.get("ok", true)) and m.undo.size() == u0, "E3 same rate / bad rates refused, no undo step")
	var qw := FpsWave.serve(m, {"action": "wave", "on": true})
	var qw2 := FpsWave.serve(m, {"action": "wave", "on": false})
	ok(bool(qw.get("ok", false)) and bool(qw2.get("ok", false)) and m.undo.size() == u0 and m.graph_wave == false, "E4 the waveform toggle adds no undo step (view only)")

	# ---- F  tool
	var at := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	ok(at.find("\"fps_wave\"") >= 0 and py.find("\"fps_wave\"") >= 0 and py.count("fps_wave") >= 2, "F1 fps_wave is in MCP_EXTRA, MATH_TOOLS and the table")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WAV))
	print("fpswave: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
