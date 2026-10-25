## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/graph_editor_test.gd   (round 51, GATES GE1-GE4; a window)
## GRAPH EDITOR DEPTH (scripts/graph_editor.gd, scripts/part_keys.gd "cycles" / noise offset + depth). A made scene (never a
## file of Nick's) with part keys on two parts, six channels whose value ranges are at least 5 deg apart.
##   1 CHANNELS: every visible channel's drawn line, read from the window's PIXELS (dots off), passes through each of its keys
##     within 1 px; a real click on a channel's row hides it (none of its colour left at its keys) and a second shows it
##   2 BOX + SCALE: a real box drag selects exactly the visible dots inside it (every dot checked); scale x2 about the 2D
##     cursor (0.5 s, 60 deg): t' = 0.5 + 2 (t - 0.5) and v' = 60 + 2 (v - 60) exactly, unselected keys untouched, one undo
##     step; Ctrl+Z gives the keys back bit for bit
##   3 NORMALIZE: each channel's drawn top / bottom pixels on the +1 / -1 rows within 1 px; the scene's save dict unchanged
##     byte for byte (on, drawn, off)
##   4 CYCLES (the registry command, one undo step): value at t + k P = value at t within 1e-6 for k = -2..3, and the
##     scene plays it (Scene.sample); offset / mirror / count rules; saved and loaded. NOISE: same seed -> identical
##     playback, strength 0 -> bit-identical to no modifier, |offset| <= strength / 2
## A screenshot of the channels view with a Cycles modifier: GE_SHOT (env) or %TEMP%/poser_shots/graph_editor.png.
extends SceneTree

var fails := 0
var m: Node
var ge: GraphEditor


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, motion := false, held := false, btn := MOUSE_BUTTON_LEFT) -> void:
	var e: InputEvent
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = btn
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		if down:
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mb
	root.push_input(e)
	await process_frame


func drag(a: Vector2, b: Vector2) -> void:
	await mouse(a, true)
	for i in range(1, 7):
		await mouse(a.lerp(b, float(i) / 6.0), false, true, true)
	await mouse(b, false)
	await idle(2)


func gp(local: Vector2) -> Vector2:
	return ge.get_global_transform_with_canvas() * local


func shot() -> Image:
	await idle(3)
	return root.get_texture().get_image()


func near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.12


## the distance (px) from y to the nearest pixel of colour col in column x within +-r rows (INF when none)
func col_dist(img: Image, x: float, y: float, col: Color, r := 4) -> float:
	var best := INF
	var px := int(floorf(x))
	for yy in range(int(floorf(y)) - r, int(floorf(y)) + r + 1):
		if yy >= 0 and yy < img.get_height() and px >= 0 and px < img.get_width() and near(img.get_pixel(px, yy), col):
			best = minf(best, absf(float(yy) + 0.5 - y))
	return best


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B0 := Body.new()
	B0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B0.fk()
	var S := Scene.new()
	S.name = "zz_graph_editor"
	S.fps = 24
	for n in ["a", "b", "c", "d", "e", "f"]:
		S.add(n, B0.to_dict())
	for c in S.cards:
		c["move"] = 0.6
		c["hold"] = 0.0
	S.part_keys = {
		"upperarm_r": [{"t": 0.2, "v": Vector3(60, 30, 0)}, {"t": 0.6, "v": Vector3(90, 45, 10)}, {"t": 1.0, "v": Vector3(70, 35, 5)}],
		"upperarm_l": [{"t": 0.0, "v": Vector3(-40, 15, -10)}, {"t": 0.5, "v": Vector3(-20, 20, -5)}, {"t": 1.2, "v": Vector3(-30, 18, -15)}]}
	m.S = S
	m._rebuild_cards()
	m.sel = "upperarm_r"
	m.sel_card = 0
	m.playhead = 0.5
	m._refresh()
	await idle(2)
	for c in m._commands():
		if c["id"] == "graph_editor_every_keyed_part_channels":
			c["run"].call()
	await idle(4)
	ge = m.ui_curve as GraphEditor
	ok(ge != null and ge.multi and ge.visible and ge.chans().size() == 6, "0 the command opened the graph editor with channels: %d channels %s" % [ge.chans().size() if ge else 0, ge.chans() if ge else []])
	print("     panel %s, plot %s, t %.2f..%.2f, v %.1f..%.1f" % [ge.get_global_rect(), ge.plot(), ge.t0, ge.t1, ge.v0, ge.v1])

	# ---- 1 channels: pixels through the keys
	ge.dots = false
	ge.queue_redraw()
	var img := await shot()
	var worst := 0.0
	var n1 := 0
	var miss := []
	for ch in ge.chans():
		var ks: Array = S.part_keys[ch[0]]
		for i in ks.size():
			var g := gp(ge.dot_pos(ch[0], ch[1], i))
			var d := col_dist(img, g.x, g.y, ge.ch_col(ch[0], ch[1]))
			n1 += 1
			if not is_finite(d):
				miss.append("%s:%d:%d" % [ch[0], ch[1], i])
			else:
				worst = maxf(worst, d)
	ok(miss.is_empty() and worst <= 1.0 and n1 == 18, "1 every channel's drawn line passes through its keys: %d keys read from pixels, worst %.2f px (bar 1), missing %s" % [n1, worst, miss])
	var row := ge.row_of("upperarm_r", 1)
	await mouse(gp(row.get_center()), true)
	await mouse(gp(row.get_center()), false)
	ge.queue_redraw()
	img = await shot()
	var left := 0
	for i in 3:
		var g := gp(ge.dot_pos("upperarm_r", 1, i))
		if is_finite(col_dist(img, g.x, g.y, ge.ch_col("upperarm_r", 1), 3)):
			left += 1
	var others := 0.0
	for i in 3:
		var g := gp(ge.dot_pos("upperarm_r", 0, i))
		others = maxf(others, col_dist(img, g.x, g.y, ge.ch_col("upperarm_r", 0)))
	var hid: bool = ge.is_hidden("upperarm_r", 1)
	await mouse(gp(row.get_center()), true)
	await mouse(gp(row.get_center()), false)
	ok(hid and left == 0 and others <= 1.0 and not ge.is_hidden("upperarm_r", 1), "   a real click on 'upperarm_r Y' hides it (%s): its colour at %d of 3 keys (bar 0), its neighbour X still within %.2f px; a second click shows it" % [hid, left, others])
	ge.dots = true

	# ---- 2 box select + scale about the 2D cursor
	ge.queue_redraw()
	await idle(2)
	var a := Vector2(ge.t_to_x(0.4), ge.v_to_y(95.0))
	var b := Vector2(ge.t_to_x(1.1), ge.v_to_y(25.0))
	await drag(gp(a), gp(b))
	var box := Rect2(a, b - a).abs()
	var want := []
	var total := 0
	for ch in ge.chans():
		for i in (S.part_keys[ch[0]] as Array).size():
			total += 1
			if box.has_point(ge.dot_pos(ch[0], ch[1], i)):
				want.append("%s:%d:%d" % [ch[0], ch[1], i])
	var got: Array = ge.msel.map(func(q): return "%s:%d:%d" % q)
	want.sort()
	got.sort()
	ok(got == want and want.size() == 4, "2 a real box drag selects exactly the dots inside it: %s (brute force over all %d dots: %s)" % [got, total, want])
	var before := var_to_str(S.part_keys)
	var snap := {}
	for j in S.part_keys:
		snap[j] = (S.part_keys[j] as Array).map(func(k): return [float(k["t"]), k["v"]])
	m.playhead = 0.5
	m._curve_sync()
	ge.pivot_mode = "cursor"
	ge.cursor_v = 60.0
	var u0: int = m.undo.size()
	var r: Dictionary = ge.scale_sel(2.0, 2.0)
	var terr := 0.0
	var verr := 0.0
	var still := true
	var sk: Dictionary = ge.sel_keys()
	for j in S.part_keys:
		for i in (S.part_keys[j] as Array).size():
			var t := float(S.part_keys[j][i]["t"])
			var v: Vector3 = S.part_keys[j][i]["v"]
			if sk.has(j) and (sk[j] as Array).has(i):
				terr = maxf(terr, absf(t - (0.5 + 2.0 * (float(snap[j][i][0]) - 0.5))))
				for c in 3:
					var w: float = (snap[j][i][1] as Vector3)[c]
					if ge.is_msel(j, c, i):
						w = 60.0 + 2.0 * (w - 60.0)
					verr = maxf(verr, absf(v[c] - w))
			else:
				still = still and t == float(snap[j][i][0]) and v == snap[j][i][1]
	ok(r["ok"] and terr == 0.0 and verr == 0.0 and still and r["clamped"] == 0 and m.undo.size() == u0 + 1,
		"   scale x2 about the 2D cursor (0.5 s, 60): time error %.9f, value error %.9f (bar exactly 0), unselected keys untouched %s, clamped %d, undo steps +%d; upperarm_r times now %s" % [terr, verr, still, r["clamped"], m.undo.size() - u0, (S.part_keys["upperarm_r"] as Array).map(func(k): return k["t"])])
	var refused: Dictionary = ge.scale_sel(-1.0, 1.0)
	ok(not refused["ok"] and m.undo.size() == u0 + 1, "   a scale that would swap keys is refused whole (%s), no undo step" % refused["why"])
	m._undo()
	await idle(2)
	ok(var_to_str(m.S.part_keys) == before, "   Ctrl+Z (main._undo) gives the keys back bit for bit (%d chars)" % before.length())
	S = m.S
	ge.msel = []

	# ---- 3 normalize: display only
	var file0 := JSON.stringify(m._scene_dict())
	for c in m._commands():
		if c["id"] == "graph_editor_normalize":
			c["run"].call()
	ge.dots = false
	var p: Rect2 = ge.plot()
	var yt := gp(Vector2(0, p.position.y + GraphEditor.NM)).y
	var yb := gp(Vector2(0, p.end.y - GraphEditor.NM)).y
	var x0 := int(gp(p.position).x) + 1
	var x1 := int(gp(p.end).x) - 1
	var w3 := 0.0
	var rep := []
	for ch in ge.chans():
		for o in ge.chans():   # one channel at a time (the eye toggles): in -1..1 every line crosses the others
			ge.set_hidden(o[0], o[1], not (o[0] == ch[0] and o[1] == ch[1]))
		img = await shot()
		var col: Color = ge.ch_col(ch[0], ch[1])
		var top := INF
		var bot := -INF
		for x in range(x0, x1):
			for y in range(int(yt) - 6, int(yb) + 7):
				if near(img.get_pixel(x, y), col):
					top = minf(top, y + 0.5)
					bot = maxf(bot, y + 0.5)
		w3 = maxf(w3, maxf(absf(top - yt), absf(bot - yb)))
		rep.append("%s%s %.1f/%.1f" % [ch[0].left(5), ["X", "Y", "Z"][ch[1]], top - yt, bot - yb])
	ge.off_ch = {}
	ge.queue_redraw()
	img = await shot()
	img.save_png(OS.get_environment("TEMP").replace("\\", "/") + "/poser_shots/graph_editor_normalized.png")
	var file1 := JSON.stringify(m._scene_dict())
	for c in m._commands():
		if c["id"] == "graph_editor_normalize":
			c["run"].call()
	await idle(2)
	var file2 := JSON.stringify(m._scene_dict())
	ok(ge.normalize == false and w3 <= 1.0, "3 normalized: each channel's drawn top / bottom pixel on the +1 / -1 rows, worst %.2f px (bar 1): %s" % [w3, rep])
	ok(file0 == file1 and file1 == file2, "   the scene's save dict byte for byte the same before, while drawn normalized and after (%d bytes)" % file0.length())
	ge.dots = true

	# ---- 4 cycles (the registry command) and noise
	var u1: int = m.undo.size()
	for c in m._commands():
		if c["id"] == "part_keys_add_cycles_modifier":
			c["run"].call()
	await idle(2)
	S = m.S
	var ks: Array = S.part_keys["upperarm_r"]
	var ms := PartKeys.mods_of(ks)
	ok(m.undo.size() == u1 + 1 and ms.size() == 1 and ms[0]["type"] == "cycles", "4 'Part keys: add Cycles modifier': one undo step (+%d), stack %s" % [m.undo.size() - u1, ms])
	var P := float(ks[-1]["t"]) - float(ks[0]["t"])
	var w4 := 0.0
	var wp := 0.0
	var np := 0
	for t in [0.25, 0.4, 0.55, 0.7, 0.85, 0.95]:
		var v0 := PartKeys.value_at(ks, t)
		for k in range(-2, 4):
			var tk: float = t + k * P
			w4 = maxf(w4, (PartKeys.value_at(ks, tk) - v0).length())
			if tk >= 0.0 and tk <= S.length():
				var sv: Vector3 = S.sample(tk)["ang"]["upperarm_r"]
				wp = maxf(wp, (sv - v0).length())
				np += 1
	ok(w4 <= 1e-6 and wp <= 1e-6 and np >= 12, "   repeat, P = %.2f s: value at t + kP vs t for k = -2..3 at 6 times, worst %.9f (bar 1e-6); Scene.sample (playback) at %d of them, worst %.9f" % [P, w4, np, wp])
	var kk := ks.duplicate(true)
	kk[0]["mods"] = [{"type": "cycles", "before": "mirror", "after": "offset", "before_n": 0, "after_n": 1, "ch": -1, "mix": 1.0}]
	var tf := float(kk[0]["t"])
	var tl := float(kk[-1]["t"])
	var e_off := (PartKeys.value_at(kk, 0.5 + P) - PartKeys.value_at(kk, 0.5) - (PartKeys.at(kk, tl) - PartKeys.at(kk, tf))).length()
	var e_cnt := (PartKeys.value_at(kk, tl + 1.5 * P) - (PartKeys.at(kk, tl) + (PartKeys.at(kk, tl) - PartKeys.at(kk, tf)))).length()
	var e_mir := (PartKeys.value_at(kk, tf - 0.13) - PartKeys.at(kk, tf + 0.13)).length()
	var back := PartKeys.from_file(PartKeys.to_file({"upperarm_r": kk}))
	var same_file: bool = var_to_str(PartKeys.mods_of(back["upperarm_r"])) == var_to_str(kk[0]["mods"])
	ok(e_off <= 1e-6 and e_cnt <= 1e-6 and e_mir <= 1e-6 and same_file, "   offset: one lap later = + (last - first) %.9f; after_n 1: past the copy the end is held %.9f; mirror before %.9f; saved and loaded the same %s" % [e_off, e_cnt, e_mir, same_file])
	var base := [{"t": 0.0, "v": Vector3(10, 0, 0)}, {"t": 0.5, "v": Vector3(40, 5, 3)}, {"t": 1.0, "v": Vector3(20, 2, 1)}]
	var nz := {"type": "noise", "ch": -1, "strength": 6.0, "scale": 0.3, "phase": 0.2, "offset": 0.1, "depth": 2, "seed": 5, "mix": 1.0}
	var A := base.duplicate(true)
	A[0]["mods"] = [nz.duplicate()]
	var A2 := base.duplicate(true)
	A2[0]["mods"] = [nz.duplicate()]
	var Z := base.duplicate(true)
	var z0 := nz.duplicate()
	z0["strength"] = 0.0
	Z[0]["mods"] = [z0]
	var C := base.duplicate(true)
	var c2 := nz.duplicate()
	c2["seed"] = 6
	C[0]["mods"] = [c2]
	var same := true
	var zero := true
	var amp := 0.0
	var diff := 0.0
	for i in 2001:
		var t := -0.5 + i * 0.001
		same = same and PartKeys.value_at(A, t) == PartKeys.value_at(A2, t)
		zero = zero and PartKeys.value_at(Z, t) == PartKeys.at(base, t)
		var d := PartKeys.value_at(A, t) - PartKeys.at(base, t)
		amp = maxf(amp, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
		diff = maxf(diff, (PartKeys.value_at(C, t) - PartKeys.value_at(A, t)).length())
	var S2 := S.clone()
	S2.part_keys = {"upperarm_r": A}
	var S3 := S.clone()
	S3.part_keys = {"upperarm_r": A2}
	var play_same := true
	for i in 60:
		play_same = play_same and var_to_str(S2.sample(i / 24.0)) == var_to_str(S3.sample(i / 24.0))
	ok(same and play_same and zero and amp <= 3.0 and amp > 1.0 and diff > 0.5, "   noise (strength 6, depth 2, offset 0.1): same seed identical at 2001 times %s and in playback %s; strength 0 bit-identical to no modifier %s; largest offset %.3f (bar <= 3 = strength / 2); seed 6 differs by up to %.2f" % [same, play_same, zero, amp, diff])

	# ---- the screenshot: channels view with the Cycles modifier
	ge.dots = true
	ge.t0 = -0.9
	ge.t1 = 2.4
	ge.queue_redraw()
	var im := await shot()
	var out := OS.get_environment("GE_SHOT")
	if out == "":
		var shots := OS.get_environment("TEMP").replace("\\", "/") + "/poser_shots"
		DirAccess.make_dir_recursive_absolute(shots)
		out = shots + "/graph_editor.png"
	im.save_png(out)
	print("     screenshot %s" % out)
	print("GRAPH EDITOR: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
