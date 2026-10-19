## godot --path . -s tests/face_test.gd     (ROADMAP 74: the face rig. Needs a window for the shot: run it as :w)
## Bars written before the first run. Sources: jaw 25-30 deg of rotation at the hinge (Okeson, Management of
## Temporomandibular Disorders and Occlusion, ch. 2) and 40-55 mm of incisal opening (Agerberg 1974); eye yaw +-45 deg
## horizontal gaze (Leigh & Zee, The Neurology of Eye Movements, ch. 2); blink 0.1-0.4 s (Doughty 2001). Figures from memory of
## those sources, not re-checked against the papers here.
##  (1) jaw at 1.0 = 27.5 deg: within 2 deg of the cited 25-30 (|27.5 - the midpoint| <= 2 and 25 <= value <= 30)
##  (2) eye look clamps at the cited range: yaw 2.0 -> 45 deg, yaw -3.0 -> -45 deg, pitch 5.0 -> 30 deg; a KEY written at 3.0
##      reads back 45 deg (the clamp is at the key too)
##  (3) L/R mirror: mirror(mirror(face)) == face within 0.01 on every key of every channel (file form); one mirror swaps the
##      brows (brow_l of the mirror = brow_r of the original, within 0.01) and negates the eye yaw
##  (4) lip sync drives the jaw on a synthetic clip (16 kHz, 16 bit in memory, the LipSync pipeline): the middle of each
##      vowel opens the jaw > 10 deg for A and O, > 5 deg for E (E is a close vowel: LipSync's JAW_K 0.45 gives ~6.75 deg;
##      stated before the run, the bar for E was never 10), the middle of a silence (M, B, P: lips shut) < 3 deg, and the
##      visemes read A / O / E / M at those times
##  (5) one undo step: keying the face at the playhead pushes ONE undo step; Ctrl+Z takes the keys back (S.face empty again)
##  (6) the file: a keyed face saves under "face" and reads back (JSON round trip) within 1e-4; a scene with no face keys
##      writes no "face" key (old scenes byte-for-byte as before)
##  (7) a screenshot of four expressions (neutral, surprise, anger, vowel A) when FACE_SHOT is set (a path)
extends SceneTree

var fails := 0
var m: Node
const SHOT_DIR := "user://"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a clip in memory: silence / vowel segments (mono, 16 kHz). Each segment: [seconds, freq Hz (0 = silence)]
func segments(rate: int, segs: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for sg in segs:
		var n := int(round(float(sg[0]) * rate))
		var f := float(sg[1])
		for i in n:
			var v := 0.0
			if f > 0.0:
				v = 0.6 * sin(TAU * f * float(i) / rate)
			out.append(v)
	return out


## the time of the middle of segment k (s), from the segment list
func mid_of(segs: Array, k: int) -> float:
	var t := 0.0
	for i in k:
		t += float(segs[i][0])
	return t + float(segs[k][0]) * 0.5


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()   # the commands (and the face panel) are built

	# (1) the jaw at full
	var p1 := Face.pose({"jaw": 1.0})
	ok(absf(float(p1["jaw_deg"]) - 27.5) <= 2.0 and float(p1["jaw_deg"]) >= 25.0 and float(p1["jaw_deg"]) <= 30.0,
		"1 jaw 100 %% = %.2f deg (cited 25-30; within 2 of 27.5)" % float(p1["jaw_deg"]))
	ok(absf(float(Face.pose({"jaw": 0.5})["jaw_deg"]) - 13.75) < 0.01, "1 jaw 50 %% = half of it (%.2f deg)" % float(Face.pose({"jaw": 0.5})["jaw_deg"]))

	# (2) eye look clamps
	var yaw_hi := float(Face.pose({"eye_yaw": 2.0})["eye_yaw_deg"])
	var yaw_lo := float(Face.pose({"eye_yaw": -3.0})["eye_yaw_deg"])
	var pitch_hi := float(Face.pose({"eye_pitch": 5.0})["eye_pitch_deg"])
	ok(absf(yaw_hi - 45.0) < 0.01 and absf(yaw_lo + 45.0) < 0.01 and absf(pitch_hi - 30.0) < 0.01,
		"2 eye look clamps: yaw 2.0 -> %.2f, yaw -3.0 -> %.2f (45 cited), pitch 5.0 -> %.2f (30)" % [yaw_hi, yaw_lo, pitch_hi])
	var kf := {}
	Face.key(kf, 0.0, {"eye_yaw": 3.0})
	ok(absf(float(Face.at(kf, {}, 0.0)["eye_yaw_deg"]) - 45.0) < 0.01, "2 a key written at 3.0 reads back at 45 deg (the clamp holds in the key)")

	# (3) L/R mirror round trip on the file form
	var f3 := {}
	Face.key(f3, 0.2, {"brow_l": 0.8, "brow_r": -0.3, "eye_yaw": 0.6, "eye_pitch": -0.4, "jaw": 0.25, "blink": 0.1, "vis_A": 0.7})
	Face.key(f3, 1.1, {"brow_l": -0.9, "brow_r": 0.5, "eye_yaw": -1.0, "eye_pitch": 0.2, "jaw": 0.0, "blink": 1.0, "vis_O": 1.0})
	var file3 := Face.to_file(f3)
	var mm := Face.mirror_file(Face.mirror_file(file3))
	var rt_err := 0.0
	for ch in file3:
		var a: Array = file3[ch]
		var b: Array = mm.get(ch, [])
		for k in a.size():
			for i in 3:
				rt_err = maxf(rt_err, absf(float((a[k]["v"] as Array)[i]) - float((b[k]["v"] as Array)[i])))
	ok(rt_err <= 0.01 and mm.keys().size() == file3.keys().size(), "3 mirror twice == the face (largest key error %.4f, bar 0.01)" % rt_err)
	var once := Face.mirror_file(file3)
	var brow_ok := absf(float(once["brow_l"][0]["v"][0]) - (-0.3)) < 0.01 and absf(float(once["brow_r"][0]["v"][0]) - 0.8) < 0.01
	var yaw_neg := absf(float(once["eye_yaw"][0]["v"][0]) + 0.6) < 0.01
	ok(brow_ok and yaw_neg, "3 one mirror: brow_l takes brow_r's value (-0.3), brow_r takes brow_l's (0.8), eye yaw negated (-0.6)")

	# (4) lip sync drives the jaw and the visemes on a test clip
	var rate := 16000
	var segs := [[0.3, 0.0], [0.8, 220.0], [0.3, 0.0], [0.8, 120.0], [0.3, 0.0], [0.8, 1000.0], [0.3, 0.0]]
	var mono := segments(rate, segs)
	var A := LipSync.analyse(LipSync.windows(mono, rate))
	var total := float(mono.size()) / rate
	var lip := LipSync.bake(A, 60, 0.0, total)
	var mid_a := mid_of(segs, 1)
	var mid_o := mid_of(segs, 3)
	var mid_e := mid_of(segs, 5)
	var mid_m := mid_of(segs, 2)
	var pa := Face.pose({}, lip, mid_a)
	var po := Face.pose({}, lip, mid_o)
	var pe := Face.pose({}, lip, mid_e)
	var pm := Face.pose({}, lip, mid_m)
	var pm0 := Face.pose({}, lip, mid_of(segs, 0))
	ok(float(pa["jaw_deg"]) > 10.0, "4 vowel A (220 Hz) opens the jaw %.2f deg (bar > 10)" % float(pa["jaw_deg"]))
	ok(float(po["jaw_deg"]) > 10.0, "4 vowel O (120 Hz) opens the jaw %.2f deg (bar > 10)" % float(po["jaw_deg"]))
	ok(float(pe["jaw_deg"]) > 5.0, "4 vowel E (1000 Hz) opens the jaw %.2f deg (bar > 5: E is a close vowel)" % float(pe["jaw_deg"]))
	ok(float(pm["jaw_deg"]) < 3.0 and float(pm0["jaw_deg"]) < 3.0, "4 silence (M, B, P) keeps the jaw %.2f / %.2f deg (bar < 3)" % [float(pm["jaw_deg"]), float(pm0["jaw_deg"])])
	ok(pa["mouth"] == "A" and po["mouth"] == "O" and pe["mouth"] == "E" and pm["mouth"] == "M",
		"4 visemes read A, O, E, M at those times (got %s %s %s %s)" % [pa["mouth"], po["mouth"], pe["mouth"], pm["mouth"]])
	ok(float(pa["vis"]["A"]) == 1.0 and float(pa["vis"]["O"]) == 0.0, "4 the lip sync sets the viseme weights (A = 1, the rest 0)")

	# (5) one undo step, Ctrl+Z takes the keys back
	m.S.face = {}
	m.playhead = 0.6
	var u0: int = m.undo.size()
	m.face_ui.key(0.6, {"brow_l": 0.5, "brow_r": 0.5, "jaw": 1.0, "eye_yaw": 0.3, "eye_pitch": 0.0, "blink": 0.0,
		"vis_M": 0.0, "vis_A": 0.0, "vis_O": 0.0, "vis_E": 0.0})
	await idle(2)
	var keyed: bool = not (m.S.face as Dictionary).is_empty() and absf(float(Face.at(m.S.face, {}, 0.6)["jaw_deg"]) - 27.5) < 0.01
	ok(keyed and m.undo.size() == u0 + 1, "5 keying the face at the playhead: one undo step (%d), jaw reads 27.5 deg at 0.6 s" % (m.undo.size() - u0))
	m._undo()
	await idle(2)
	ok(m.S.face.is_empty(), "5 Ctrl+Z takes the face keys back (S.face empty)")
	m._redo()
	await idle(2)
	ok(not m.S.face.is_empty(), "5 Ctrl+Y puts them back")

	# (6) the file form
	m.S.face = {}
	m.face_ui.key(0.6, {"brow_l": 0.5, "jaw": 0.4, "eye_yaw": -0.25})
	var d: Dictionary = m.S.to_dict(m.B)
	var back := Face.from_file(JSON.parse_string(JSON.stringify(d.get("face", {}))))
	var same: bool = back.keys().size() == m.S.face.keys().size()
	for ch in m.S.face:
		for k in (m.S.face[ch] as Array).size():
			same = same and absf(float(back[ch][k]["t"]) - float(m.S.face[ch][k]["t"])) < 1e-4 and absf((back[ch][k]["v"] as Vector3).x - (m.S.face[ch][k]["v"] as Vector3).x) < 1e-4
	ok(d.has("face") and same, "6 a keyed face saves under \"face\" and reads back within 1e-4")
	m.S.face = {}
	ok(not (m.S.to_dict(m.B)).has("face"), "6 a scene with no face keys writes no \"face\" key")

	# (7) the shot: four expressions, cropped round the head (only with FACE_SHOT set; the run needs a window)
	var shot := OS.get_environment("FACE_SHOT")
	if shot != "":
		m.playhead = 0.6
		m._face_draw()
		m._turn_to(0.0, -5.0, 0.55, m.mouth_mi.global_position, false)   # the hero faces +Z: look at the face from the front
		await idle(2)
		var exps := [
			{"name": "neutral", "v": {}},
			{"name": "surprise", "v": {"brow_l": 1.0, "brow_r": 1.0, "jaw": 0.6, "eye_pitch": 0.5}},
			{"name": "anger", "v": {"brow_l": -1.0, "brow_r": -1.0, "eye_yaw": 0.5, "jaw": 0.1}},
			{"name": "vowel A", "v": {"vis_A": 1.0, "jaw": 0.0, "blink": 0.0}},
		]
		var tiles := []
		for e in exps:
			m.S.face = {}
			var vals := {"brow_l": 0.0, "brow_r": 0.0, "jaw": 0.0, "eye_yaw": 0.0, "eye_pitch": 0.0, "blink": 0.0,
				"vis_M": 0.0, "vis_A": 0.0, "vis_O": 0.0, "vis_E": 0.0}
			for k in e["v"]:
				vals[k] = e["v"][k]
			Face.key(m.S.face, 0.6, vals)
			m.playhead = 0.6
			m._face_draw()
			await idle(2)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var c: Vector3 = m.mouth_mi.global_position   # the head (face_root sits at the origin: its parts carry the head space)
			var sp: Vector2 = m.cam.unproject_position(c) + Vector2(0, -95)   # above the mouth: the brows are in the frame
			var r := Rect2i(int(sp.x) - 120, int(sp.y) - 120, 240, 240).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			var tile := img.get_region(r)
			tile.convert(Image.FORMAT_RGBA8)
			tiles.append(tile)
			print("shot %s at %s" % [e["name"], sp])
		var sheet := Image.create(240 * tiles.size(), 240, false, Image.FORMAT_RGBA8)
		for i in tiles.size():
			sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i(240 * i, 0))
		sheet.save_png(shot)
		ok(FileAccess.file_exists(shot), "7 the four expressions saved to %s" % shot)
	m.S.face = {}
	print("FACE TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	quit(fails)
