## godot --path . -s tests/clipwarp_test.gd [-- --shot=C:/x.png]     (ROADMAP 83 CLIP WARPING; needs a window: the timeline)
## A strip's time curve (scripts/clips.gd warp_*): input = the strip's progress, output = the source's progress.
## BARS, stated before the numbers were read:
##   1 linear: no warp, warp [] (the linear preset) and knots on the diagonal give the SAME pose bytes (var_to_str of
##     B.state() and the offset) at 10 sampled times in the strip. Bar: 0 of 10 differ
##   2 ease in: at strip progress 0.25 the source time is f(0.25) x L with f from the curve, within 1e-6 (playback, not
##     only the formula); its pose is the source's at that time (< 0.01 deg, as clips_test 1). Bar: f(0.25) = 0.0625 +- 1e-9
##   3 monotone: 500 random drags (illegal ones too, seed 7) and random adds keep x strictly inside (0,1) and increasing,
##     y non-decreasing in 0..1, and warp_f non-decreasing on 201 samples. Bar: 0 violations
##   4 length unchanged: Clips.length_of before and after any warp, and the bar's width on the timeline. Bar: equal
##   5 the app: preset, drag a knot, add a knot by a click, right-click a knot out: each ONE undo step; Ctrl+Z restores
##     the curve exactly. Bar: +1 undo each, the curve back bit for bit
##   6 old files: a clip with no curve writes exactly the 12 keys it wrote before, no "warp"; a curve round trips
##     through JSON to the same knots. Bar: 12 keys, 0 "warp" keys in linear clips
##   7 playback and scrubbing both sample the warp: the same pose from Scene.apply at the same time twice. Bar: equal
extends SceneTree

const SRC := "scenes/walk_bat.json"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


## two cards, no weapon (the same target as clips_test)
func target() -> Scene:
	var R := body()
	R.wep_on = false
	R.set_ang("upperarm_r", Vector3(0, 0, 40))
	R.set_ang("thigh_l", Vector3(20, 0, 0))
	R.fk()
	var S := Scene.new()
	S.add("a", R.to_dict())
	R.set_ang("upperarm_l", Vector3(0, 0, -30))
	R.set_ang("spine_02", Vector3(10, 0, 0))
	R.fk()
	S.add("b", R.to_dict())
	S.cards[1]["move"] = 0.8
	S.cards[1]["hold"] = 12.0
	return S


func src_scene() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + SRC)))
	return S


func worst_deg(a: Body, b: Body) -> float:
	var w := 0.0
	for j in Body.ORDER:
		var d: Vector3 = Scene._d(b.ang[j], a.ang[j], j)
		w = maxf(w, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
	return w


## the knots are a legal curve: x strictly increasing inside (0,1), y non-decreasing in 0..1, at most WARP_MAX
func legal(ks: Array) -> bool:
	var px := 0.0
	var py := 0.0
	for k in ks:
		var x := float(k[0])
		var y := float(k[1])
		if not (x > px and x < 1.0 and y >= py and y <= 1.0):
			return false
		px = x
		py = y
	return ks.size() <= Clips.WARP_MAX


func _init() -> void:
	var B := body()
	var R := body()
	var src := src_scene()
	var L := src.length()
	var e := Clips.source(SRC)
	var s0 := 0.7

	# 1
	var base := target()
	base.clips = [Clips.make(SRC, s0)]
	var lin := target()
	lin.clips = [Clips.make(SRC, s0, {"warp": Clips.WARP_PRESETS["linear"]})]
	var diag := target()
	diag.clips = [Clips.make(SRC, s0, {"warp": [[0.25, 0.25], [0.6, 0.6]]})]
	var D := Clips.length_of(base.clips[0], L)
	var diff := 0
	for i in 10:
		var t := s0 + (i + 0.5) / 10.0 * D
		base.apply(B, t)
		var sb := var_to_str(B.state()) + var_to_str(B.offset)
		lin.apply(B, t)
		var sl := var_to_str(B.state()) + var_to_str(B.offset)
		diag.apply(B, t)
		var sd := var_to_str(B.state()) + var_to_str(B.offset)
		if sb != sl or sb != sd:
			diff += 1
	ok(diff == 0,
		"1 linear: no warp, the linear preset and diagonal knots give the same pose bytes at 10 times: %d of 10 differ" % diff)

	# 2
	var ease := Clips.WARP_PRESETS["ease_in"]
	var f := Clips.warp_f(ease, 0.25)
	var c2 := Clips.make(SRC, s0, {"warp": ease})
	var a2 := Clips.at(c2, L, s0 + 0.25 * D)
	ok(absf(f - 0.0625) < 1e-9 and absf(float(a2["lt"]) / L - f) < 1e-6,
		"2 ease in at strip progress 0.25: f = %.9f (bar 0.0625), playback source time / L = %.9f, within 1e-6" % [f, float(a2["lt"]) / L])
	var S2 := target()
	S2.clips = [c2]
	S2.apply(B, s0 + 0.25 * D)
	src.apply(R, float(a2["lt"]))
	ok(worst_deg(B, R) < 0.01, "2 the body at that time is the source's pose at f(0.25) x L: %.6f deg" % worst_deg(B, R))

	# 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ks: Array = []
	var bad := 0
	var clamped := 0
	for n in 500:
		if ks.is_empty() or rng.randf() < 0.3:
			var nk := Clips.warp_add(ks, rng.randf(), rng.randf())
			if nk.size() != ks.size():
				ks = nk
		else:
			var j := rng.randi() % ks.size()
			var x := rng.randf_range(-0.2, 1.2)
			var y := rng.randf_range(-0.2, 1.2)
			var nk2 := Clips.warp_set(ks, j, x, y)
			if absf(float(nk2[j][0]) - x) > 1e-9 or absf(float(nk2[j][1]) - y) > 1e-9:
				clamped += 1
			ks = nk2
		if not legal(ks):
			bad += 1
		var prev := -1.0
		for i in 201:
			var v := Clips.warp_f(ks, i / 200.0)
			if v < prev - 1e-12:
				bad += 1
			prev = v
	ok(bad == 0 and clamped > 0, "3 monotone after 500 random drags and adds (%d drags clamped): %d violations" % [clamped, bad])
	var lo := Clips.warp_set([[0.25, 0.0625], [0.5, 0.25]], 0, 0.9, 0.1)
	ok(absf(float(lo[0][0]) - 0.499) < 1e-9 and absf(float(lo[0][1]) - 0.1) < 1e-9,
		"3 a knot dragged past its neighbour clamps: x 0.9 -> %.3f (before 0.5 - 0.001), y 0.1 kept (below 0.25)" % float(lo[0][0]))
	var lo2 := Clips.warp_set([[0.25, 0.0625], [0.5, 0.25]], 1, 0.6, 0.0)
	ok(absf(float(lo2[1][1]) - 0.0625) < 1e-9, "3 a knot dragged below its lower neighbour clamps to it: y %.4f (bar 0.0625)" % float(lo2[1][1]))

	# 4
	var c4 := Clips.make(SRC, s0, {"warp": ease, "repeat": 2, "speed": 1.5})
	var c4n := Clips.make(SRC, s0, {"repeat": 2, "speed": 1.5})
	ok(Clips.length_of(c4, L) == Clips.length_of(c4n, L) and Clips.length_of(c4, L) == L * 2.0 / 1.5,
		"4 length unchanged by a warp: %.4f s with and without (L x 2 / 1.5)" % Clips.length_of(c4, L))

	# 6 (the file side, before the app part)
	var plain := Clips.make(SRC, s0, {"repeat": 2})
	var fk: Dictionary = Clips.to_file([plain])[0]
	var lin6: Dictionary = Clips.to_file([Clips.make(SRC, s0, {"warp": Clips.WARP_PRESETS["linear"]})])[0]
	ok((fk as Dictionary).keys().size() == 12 and not fk.has("warp") and not lin6.has("warp"),
		"6 a clip with no curve writes its 12 keys and no \"warp\"; a linear preset writes none (%d keys)" % (fk as Dictionary).keys().size())
	var wc := Clips.make(SRC, s0, {"warp": ease})
	var sw := target()
	sw.clips = [wc]
	var txt := JSON.stringify(sw.to_dict(B, false))
	var sw2 := Scene.new()
	sw2.from_dict(JSON.parse_string(txt))
	ok(var_to_str(sw2.clips[0]["warp"]) == var_to_str(ease) and JSON.stringify(sw2.to_dict(B, false)) == txt,
		"6 a curve round trips through the file to the same knots, the file written again byte-identical")

	# 7
	sw.clips = [Clips.make(SRC, s0, {"warp": ease})]
	sw.apply(B, 1.9)
	var first := var_to_str(B.state())
	sw.apply(B, 0.3)
	sw.apply(B, 1.9)
	ok(var_to_str(B.state()) == first, "7 the same time gives the same pose again (playback and scrubbing sample one function)")

	await app_part()
	print("CLIPWARP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)


# 5 and the picture
func app_part() -> void:
	var L: float = float(Clips.source(SRC)["len"])
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	m.S = target()
	m.scene_path = ""
	m._rebuild_cards()
	m._card_pick(0)
	m.playhead = 0.4
	m.undo.clear()
	var u0: int = m.undo.size()
	var k: int = m.clips_ui.place(SRC, 0.2, {"repeat": 1})
	var k2: int = m.clips_ui.place(SRC, 2.4, {"mask": "legs"})
	m.clips_ui.sel = 0
	m.clips_ui.warp_preset("ease_in")
	ok(k == 0 and m.S.clips[0]["warp"] == Clips.WARP_PRESETS["ease_in"] and m.undo.size() == u0 + 3,
		"5 place, place, the ease-in preset: each ONE undo step (%d), the curve is ease in" % (m.undo.size() - u0))
	m._undo()
	ok(not m.S.clips[0].has("warp") and m.undo.size() == u0 + 2, "5 Ctrl+Z takes the preset back: the curve is linear again")
	m._redo()   # the preset is back: the drag below starts from it
	var ease_knots: Array = (m.S.clips[0]["warp"] as Array).duplicate(true)
	var tl: Timeline = m.ui_timeline
	for i in 4:
		await process_frame
	var kn := tl.warp_px(0, Vector2(0.25, 0.0625))
	var u1: int = m.undo.size()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = kn
	tl._gui_input(press)
	var goal := Vector2(kn.x + 40.0, kn.y - 30.0)
	for step in 4:
		var mv := InputEventMouseMotion.new()
		mv.position = kn.lerp(goal, float(step + 1) / 4.0)
		tl._gui_input(mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = goal
	tl._gui_input(rel)
	var moved: Array = m.S.clips[0]["warp"]
	var want := tl.warp_norm_of(0, goal)
	var kx := float(moved[0][0])
	var ky := float(moved[0][1])
	ok(absf(kx - clampf(want.x, Clips.WARP_EPS, 0.5 - Clips.WARP_EPS)) < 1e-6 and absf(ky - clampf(want.y, 0.0, 0.25)) < 1e-6 and legal(moved),
		"5 a drag moves the knot to (%.4f, %.4f), clamped to its neighbours: ONE undo step (%d), still a legal curve" % [kx, ky, m.undo.size() - u1])
	m._undo()
	ok(var_to_str(m.S.clips[0]["warp"]) == var_to_str(ease_knots), "5 Ctrl+Z puts the preset's knots back bit for bit")
	m._redo()
	var u2: int = m.undo.size()
	var pa := tl.warp_px(0, Vector2(0.9, 0.9))
	var ap := InputEventMouseButton.new()
	ap.button_index = MOUSE_BUTTON_LEFT
	ap.pressed = true
	ap.position = pa
	tl._gui_input(ap)
	var ar := InputEventMouseButton.new()
	ar.button_index = MOUSE_BUTTON_LEFT
	ar.pressed = false
	ar.position = pa
	tl._gui_input(ar)
	ok((m.S.clips[0]["warp"] as Array).size() == 4 and m.undo.size() == u2 + 1 and legal(m.S.clips[0]["warp"]),
		"5 a click in the empty panel adds a knot: 4 knots, ONE undo step (%d)" % (m.undo.size() - u2))
	var u3: int = m.undo.size()
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	rc.position = tl.warp_px(0, Vector2(0.9, 0.9))
	tl._gui_input(rc)
	ok((m.S.clips[0]["warp"] as Array).size() == 3 and m.undo.size() == u3 + 1,
		"5 right-click on that knot takes it out: 3 knots, ONE undo step (%d)" % (m.undo.size() - u3))
	m.clips_ui.sel = 1
	m.clips_ui.remove()
	m.clips_ui.sel = 0
	var lens := [Clips.length_of(m.S.clips[0], L)]   # the strip's length before the slow-mo curve
	for i in 3:
		await process_frame
	var bar_w := tl.clip_rect(0).size.x
	m.clips_ui.warp_preset("slow_mid")
	for i in 3:
		await process_frame
	ok(absf(tl.clip_rect(0).size.x - bar_w) < 1e-6 and Clips.length_of(m.S.clips[0], L) == lens[0],
		"4 the strip's bar is as wide with the slow-mo curve (%.1f px) and its length is the same (%.4f s)" % [bar_w, lens[0]])
	m._undo()
	m.clips_ui.warp_preset("linear")
	ok(not m.S.clips[0].has("warp"), "5 the linear preset leaves no curve in the file's clip")
	m.clips_ui.sel = 0
	m.clips_ui.warp_preset("ease_in")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.save_png(a.substr(7))
			print("     shot: %s" % a.substr(7))
	m.queue_free()
	await process_frame
