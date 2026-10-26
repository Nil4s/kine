## godot --path . -s tests/faceword_test.gd     (ROADMAP I20: face from words)   FACEWORD_SHOT=<png> saves the 3-up
## BARS, stated before measuring:
##  1 "angry" equals Face.EXPR_AU["anger"] within 0.05 on brow / squint / widen / blink / press / jaw
##  2 "a little surprised" is 0.30-0.45 of "surprised" on brow, widen and jaw
##  3 "tired and angry": blink > 0.3 AND brow < -0.4
##  4 one Ctrl+Z restores the face exactly (S.face as saved), and the words box applied it as ONE step
##  5 "raise the right arm 90 and look angry" does both (the arm's side angle rises, the face is keyed), still one undo step
##  6 an unknown word names the words that are known; "but" weights the second part more ("smiling but in pain" is nearer pain than "pain but smiling")
##  7 PLACEMENT: in a head close-up the brow marker is lower on screen (pixel row) for "angry" than neutral, by >= 3 px
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mix(t: String) -> Dictionary:
	var r := FaceWords.parse(t)
	return r["mix"] if r["ok"] else {}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()

	# 1
	var a := mix("angry")
	var ex: Dictionary = Face.EXPR_AU["anger"]
	var worst := 0.0
	for ch in ["brow", "squint", "widen", "blink", "press", "jaw"]:
		worst = maxf(worst, absf(float(a[ch]) - float(ex[ch])))
	ok(worst <= 0.05 and a["shape"] == ex["shape"], "1 'angry' vs EXPR_AU anger: worst channel gap %.3f (<= 0.05), shape '%s' = '%s'" % [worst, a["shape"], ex["shape"]])
	for nm in [["surprised", "surprise"], ["pain", "pain"], ["effort", "effort"]]:
		var b := mix(nm[0])
		var w2 := 0.0
		for ch in ["brow", "squint", "widen", "blink", "press", "jaw"]:
			w2 = maxf(w2, absf(float(b[ch]) - float(Face.EXPR_AU[nm[1]][ch])))
		ok(w2 <= 0.05, "1 '%s' vs EXPR_AU %s: worst gap %.3f" % [nm[0], nm[1], w2])

	# 2
	var s := mix("surprised")
	var l := mix("a little surprised")
	var rs := []
	for ch in ["brow", "widen", "jaw"]:
		rs.append(float(l[ch]) / float(s[ch]))
	ok(rs.all(func(x): return x >= 0.3 and x <= 0.45), "2 'a little surprised' / 'surprised' brow %.2f widen %.2f jaw %.2f (0.30-0.45)" % [rs[0], rs[1], rs[2]])

	# 3
	var ta := mix("tired and angry")
	ok(float(ta["blink"]) > 0.3 and float(ta["brow"]) < -0.4, "3 'tired and angry': blink %.2f (> 0.3), brow %.2f (< -0.4)" % [ta["blink"], ta["brow"]])

	# 4
	var before := Face.to_file(m.S.face).duplicate(true)
	var n_undo_before: int = m.undo.size()
	var r: Dictionary = m._pose_words("tired and angry")
	ok(r["ok"] and not m.S.face.is_empty() and absf(Face.values_at(m.S.face, float(m.playhead))["blink"] - float(ta["blink"])) < 0.02,
		"4 the words box keyed the face at the playhead (blink %.2f)" % Face.values_at(m.S.face, float(m.playhead))["blink"])
	if n_undo_before >= 0:
		ok(m.undo.size() == n_undo_before + 1, "4 exactly one undo step (%d -> %d)" % [n_undo_before, m.undo.size()])
	m._undo()
	ok(str(Face.to_file(m.S.face)) == str(before), "4 one Ctrl+Z restores the face exactly")

	# 5
	var arm0: float = m.B.ang["upperarm_r"].y
	var n2: int = m.undo.size()
	var r5: Dictionary = m._pose_words("raise the right arm 90 and look angry")
	var arm1: float = m.B.ang["upperarm_r"].y
	var fv: Dictionary = Face.values_at(m.S.face, float(m.playhead))
	ok(r5["ok"] and absf(arm1 - arm0) > 5.0 and float(fv["brow_l"]) < -0.4, "5 mixed phrase: arm side %.1f -> %.1f, brow %.2f" % [arm0, arm1, fv["brow_l"]])
	if n2 >= 0:
		ok(m.undo.size() == n2 + 1, "5 one undo step for both")
	m._undo()
	ok(absf(m.B.ang["upperarm_r"].y - arm0) < 0.01 and str(Face.to_file(m.S.face)) == str(before), "5 one Ctrl+Z restores arm and face")

	# 6
	var bad := FaceWords.parse("grumpy")
	ok(not bad["ok"] and "tired" in String(bad["error"]) and "angry" in String(bad["error"]) and "try" in String(bad["error"]).to_lower(), "6 unknown word names the known words")
	var sp := mix("smiling but in pain")
	var ps := mix("in pain but smiling")
	var pain := mix("pain")
	var d1 := absf(float(sp["brow"]) - float(pain["brow"]))
	var d2 := absf(float(ps["brow"]) - float(pain["brow"]))
	ok(d1 < d2, "6 'but' weights the second: 'smiling but in pain' brow %.2f is nearer pain (%.2f) than 'in pain but smiling' %.2f" % [sp["brow"], pain["brow"], ps["brow"]])

	# 7 placement: the head close-up, neutral / angry / tired and angry
	m.S.face = {}
	m.playhead = 0.6
	Face.key(m.S.face, 0.6, {"brow_l": 0.0, "brow_r": 0.0})
	m._refresh()
	await idle(2)
	var hc: Vector3 = m.face_at(m.face_geo["eye_l"]) * 0.5 + m.face_at(m.face_geo["eye_r"]) * 0.5 - Vector3(0, 0.03, 0)
	if m.ui_toast != null:
		m.ui_toast.visible = false
	if m.dummy_on:
		m._dummy_toggle()
	m._turn_to(0.0, -5.0, 0.7, hc, false)
	await idle(40)   # the camera eases in
	var rows := []
	var tiles := []
	for ph in ["", "angry", "tired and angry"]:
		m.S.face = {}
		Face.key(m.S.face, 0.6, {"brow_l": 0.0, "brow_r": 0.0})
		if ph != "":
			Face.key(m.S.face, 0.6, FaceWords.values(mix(ph)))
		m._face_draw()
		await idle(4)
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var bp: Vector2 = m.cam.unproject_position((m.face_brow[0] as Node3D).global_position)
		rows.append(bp.y)
		# the pixel check: the darkest (ink) pixel row in a narrow column band at the brow marker
		var sp0: Vector2 = m.cam.unproject_position(hc)
		var r0 := Rect2i(int(sp0.x) - 150, int(sp0.y) - 150, 300, 300).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var tile := img.get_region(r0)
		tile.convert(Image.FORMAT_RGBA8)
		tiles.append(tile)
		print("   '%s': brow marker row %.1f px, blink lid scale %.2f" % [ph, bp.y, (m.face_eye[0] as Node3D).scale.y])
	ok(float(rows[1]) - float(rows[0]) >= 3.0 and float(rows[2]) - float(rows[0]) >= 3.0, "7 brow marker pixel row: neutral %.1f, angry %.1f, tired+angry %.1f (angry lower by >= 3 px)" % rows)
	var shot := OS.get_environment("FACEWORD_SHOT")
	if shot != "":
		var sheet := Image.create(300 * tiles.size(), 300, false, Image.FORMAT_RGBA8)
		for i in tiles.size():
			sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i(300 * i, 0))
		sheet.save_png(shot)
		print("shot saved ", shot)
	m.S.face = {}
	print("FACEWORD TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)
