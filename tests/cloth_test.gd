## godot --headless --path . -s tests/cloth_test.gd     (ROADMAP 86, CLOTH ON A CAPE; scripts/cloth.gd)
## A window picture (the cape in a whole-body view during the turn): CLOTH_SHOT=<path.png> with a window
##   godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/cloth_test.gd
## Bars, written before measuring:
##   1 REST: a 3 s hold (the cape settles one second before frame 0). The pins stay within 0.1 mm of the shoulders at
##     (+-0.15, 1.44, -0.17) m (spine_03 frame, the back) at every frame. The lowest row ends below the pelvis joint
##     (0.917 m). Structural edges within 5 % of rest at every frame.
##   2 WALK (scenes/walk_bat.json, 3.5 s): no cloth vertex inside any body capsule by more than 5 mm at any frame; the
##     pins follow spine_03 within 0.1 mm at every frame; structural edges within 5 % of rest.
##   3 QUICK TURN: the pelvis turns 90 deg in 0.25 s from 0.75 s (smootherstep), then holds. The tip's LAG is its swing from
##     straight down (deg): a cape hangs along gravity, so the lag behind the turn shows as the swing. It peaks at 10 deg or
##     more, after the turn starts (peak time >= 1.0 s), and by 3.0 s is under half its peak (it swings back, does not ring).
##     Structural edges within 5 % of rest through the turn.
##   4 SCRUB: two bakes of the same path are identical (string of every frame, var_to_str); a frame read back in any order
##     gives the same vertices.
##   5 EXPORT: the export has one frame per baked frame, 192 vertices each, 990 face indices (330 triangles); the JSON
##     written under user:// reads back to the same frame count; the scene file form round-trips to 1e-6 m.
##   6 PLACEMENT: at the peak lag, in the pelvis frame, the cape's mean z is behind the body (below -0.10 m: its back is
##     at z -0.16), its mean |x| is under 0.12 m (centred on the spine), its mean height is between 0.6 and 1.45 m.
## Numbers print next to each bar. FAIL lines count into the final verdict.
extends SceneTree

var fails := 0
const SHOT_YAW := 180.0   # the camera's yaw for the picture (deg): 180 = from behind the hero


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func scene_of(path: String) -> Scene:
	var sc := Scene.new()
	sc.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return sc


## the quick turn: stand 1.0 s, then the pelvis turns 90 deg in 0.25 s, then holds 2 s
func turn_scene() -> Scene:
	var S := Scene.new()
	S.fps = 30
	var rest := {}
	for j in Body.ORDER:
		rest[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}   # every joint named: a card's missing joint keeps the last pose
	S.add("stand", {"joints": rest.duplicate(true), "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["hold"] = 1.0
	var turned := rest.duplicate(true)
	(turned["pelvis"] as Dictionary)["twist"] = 90.0
	S.add("turn", {"joints": turned, "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["move"] = 0.25
	(S.cards[-1] as Dictionary)["hold"] = 2.0
	return S


## the largest depth (m) any cape vertex sits inside any body capsule at this frame (negative = clear)
func depth_now(B: Body, verts: PackedVector3Array, names: Array) -> float:
	var worst := -INF
	for n in names:
		var c: Array = B.cap(n)
		var a: Vector3 = c[0]
		var b: Vector3 = c[1]
		var r := float(B.rad[n])
		var ab := b - a
		var L2 := maxf(ab.length_squared(), 1e-12)
		for v in verts:
			var t := clampf((v - a).dot(ab) / L2, 0.0, 1.0)
			worst = maxf(worst, r - (v - (a + ab * t)).length())
	return worst


## the largest relative stretch of the structural edges (row and column neighbours) against the rest lengths (frame 0)
func stretch(frames: Array) -> float:
	var E := Cloth.topology()["edges"] as PackedInt32Array
	var ns: int = Cloth.topology()["n_struct"]
	var r0: PackedVector3Array = frames[0]
	var worst := 0.0
	for f in frames:
		var v: PackedVector3Array = f
		for k in ns:
			var i := E[2 * k]
			var j := E[2 * k + 1]
			var L0 := r0[i].distance_to(r0[j])
			worst = maxf(worst, absf(v[i].distance_to(v[j]) / L0 - 1.0))
	return worst


## the worst gap (m) between the pinned row and the spine_03 shoulder anchors at the pose the scene sets, frame by frame
func pin_error(S: Scene, B: Body, cape: Dictionary) -> float:
	var worst := 0.0
	var fps := int(cape["fps"])
	var fr: Array = cape["frames"]
	for k in fr.size():
		S.apply(B, float(k) / float(fps))
		var A := Cloth.anchors(B)
		var v: PackedVector3Array = fr[k]
		for c in Cloth.COLS:
			worst = maxf(worst, A[c].distance_to(v[c]))
	return worst


func _init() -> void:
	var B := body()
	var S := Scene.new()
	# ---- 1 REST
	var rest_cape := Cloth.bake(B, 90, 30, func(_t: float) -> void: pass)
	var fr: Array = rest_cape["frames"]
	var pe := 0.0
	var A0 := Cloth.anchors(B)
	for f in fr:
		var v: PackedVector3Array = f
		for c in Cloth.COLS:
			pe = maxf(pe, A0[c].distance_to(v[c]))
	var sh_l := Vector3(-0.15, 1.44, -0.17)
	var sh_r := Vector3(0.15, 1.44, -0.17)
	var sh_err := maxf((fr[-1] as PackedVector3Array)[0].distance_to(sh_l), (fr[-1] as PackedVector3Array)[Cloth.COLS - 1].distance_to(sh_r))
	print("1 REST: pins off their anchors by %.4f mm; top corners off the shoulders (+-0.15, 1.44, -0.17) by %.4f mm" % [pe * 1000.0, sh_err * 1000.0])
	ok(pe < 1e-4 and sh_err < 1e-4, "1a the pinned row stays within 0.1 mm of the shoulders at every frame")
	var low := 0.0
	for c in Cloth.COLS:
		low += (fr[-1] as PackedVector3Array)[(Cloth.ROWS - 1) * Cloth.COLS + c].y
	low /= float(Cloth.COLS)
	var pelvis_y: float = (B.P["pelvis"] as Vector3).y
	print("   lowest row mean height %.3f m, pelvis joint %.3f m" % [low, pelvis_y])
	ok(low < pelvis_y, "1b the cape hangs: its lowest row is below the hips (%.3f < %.3f m)" % [low, pelvis_y])
	var st := stretch(fr)
	print("   worst structural edge stretch %.3f %%" % [st * 100.0])
	ok(st < 0.05, "1c structural edges within 5 %% of rest at rest")
	var names: Array = B.cap0.keys()
	var dpt := depth_now(B, fr[-1], names)
	print("   deepest vertex inside a capsule at rest: %.2f mm (negative = clear)" % [dpt * 1000.0])

	# ---- 2 WALK
	var W := scene_of("res://scenes/walk_bat.json")
	var wcape := Cloth.bake_scene(W, B)
	var wfr: Array = wcape["frames"]
	var wdep := -INF
	var wpe := 0.0
	var wfps := int(wcape["fps"])
	for k in wfr.size():
		W.apply(B, minf(float(k) / float(wfps), W.length()))
		var A := Cloth.anchors(B)
		var v: PackedVector3Array = wfr[k]
		for c in Cloth.COLS:
			wpe = maxf(wpe, A[c].distance_to(v[c]))
		wdep = maxf(wdep, depth_now(B, v, names))
	var wst := stretch(wfr)
	print("2 WALK: %d frames (%.2f s); deepest vertex inside a capsule %.2f mm; pins off spine_03 by %.4f mm; edges stretch %.3f %%" % [wfr.size(), W.length(), wdep * 1000.0, wpe * 1000.0, wst * 100.0])
	ok(wdep < 0.005, "2a no cape vertex inside a body capsule by more than 5 mm over the walk")
	ok(wpe < 1e-4, "2b the pinned row follows spine_03 within 0.1 mm over the walk")
	ok(wst < 0.05, "2c structural edges within 5 %% of rest over the walk")

	# ---- 3 QUICK TURN
	var T := turn_scene()
	var tcape := Cloth.bake_scene(T, B)
	var tfr: Array = tcape["frames"]
	var tfps := int(tcape["fps"])
	var peak := -1.0
	var peak_t := 0.0
	var lag_end := 0.0
	var lags := []
	for k in tfr.size():
		var t := float(k) / float(tfps)
		T.apply(B, minf(t, T.length()))
		var lg := Cloth.tip_lag_deg(tfr[k])
		lags.append(lg)
		if lg > peak:
			peak = lg
			peak_t = t
		lag_end = lg
	var tst := stretch(tfr)
	print("3 TURN: tip lag (swing from straight down) peaks at %.1f deg, at %.2f s (turn 1.00-1.25 s); at 3.0 s it is %.1f deg; edges stretch %.3f %%" % [peak, peak_t, lag_end, tst * 100.0])
	ok(peak >= 10.0, "3a the tip swings out: lag %.1f deg from straight down (bar 10)" % peak)
	ok(peak_t >= 1.0, "3b the swing comes after the turn starts (peak at %.2f s)" % peak_t)
	ok(lag_end < 0.5 * peak, "3c it swings back: %.1f deg at 3.0 s, under half its peak" % lag_end)
	ok(tst < 0.05, "3d structural edges within 5 %% of rest through the turn")

	# ---- 4 SCRUB
	var tcape2 := Cloth.bake_scene(turn_scene(), B)
	ok(var_to_str(tcape2["frames"]) == var_to_str(tcape["frames"]), "4a two bakes of the same path are identical")
	var a1 := Cloth.verts_at(tcape, 1.4)
	var a2 := Cloth.verts_at(tcape, 0.2)
	var a3 := Cloth.verts_at(tcape, 1.4)
	ok(var_to_str(a1) == var_to_str(a3) and a1 != a2, "4b a frame read back after another frame is the same shape")

	# ---- 5 EXPORT
	var ex := Cloth.export_dict(tcape)
	var nv: int = (ex["frames"][0] as Array).size()
	var nf: int = (ex["frames"] as Array).size()
	ok(nf == tfr.size() and nv == Cloth.COLS * Cloth.ROWS, "5a export: %d frames of %d vertices" % [nf, nv])
	ok((ex["faces"] as Array).size() == 990, "5b export: %d face indices (330 triangles)" % (ex["faces"] as Array).size())
	var path := Cloth.save_json(tcape, "cloth_test_cape.json")
	var back = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok(path != "" and back is Dictionary and (back["frames"] as Array).size() == nf, "5c the JSON under user:// reads back with %d frames" % nf)
	var fx := Cloth.from_file(Cloth.to_file(tcape))
	var fd := 0.0
	for k in (fx["frames"] as Array).size():
		for i in Cloth.COLS * Cloth.ROWS:
			fd = maxf(fd, (fx["frames"][k] as PackedVector3Array)[i].distance_to((tfr[k] as PackedVector3Array)[i]))
	ok(fd < 1e-6, "5d the scene form round-trips (worst gap %.3f mm)" % (fd * 1000.0))

	# ---- 6 PLACEMENT (at the peak lag, in the pelvis frame)
	var pk: PackedVector3Array = tfr[int(round(peak_t * float(tfps)))]
	T.apply(B, minf(peak_t, T.length()))
	var inv := (B.G["pelvis"] as Quaternion).inverse()
	var pp: Vector3 = B.P["pelvis"]
	var mz := 0.0
	var mx := 0.0
	var my := 0.0
	for v in pk:
		var l := inv * (v - pp)
		mz += l.z
		mx += l.x
		my += v.y
	var nn := float(pk.size())
	mz /= nn
	mx /= nn
	my /= nn
	print("6 PLACEMENT: at %.2f s, pelvis frame: mean z %.3f m (back), mean x %.3f m, mean height %.3f m" % [peak_t, mz, mx, my])
	ok(mz < -0.10, "6a the cape is on the back: mean z %.3f m behind the pelvis (bar -0.10)" % mz)
	ok(absf(mx) < 0.12, "6b it is centred on the spine: mean |x| %.3f m" % absf(mx))
	ok(my > 0.6 and my < 1.45, "6c it hangs from the shoulders down: mean height %.3f m" % my)

	print("cloth: %d failures" % fails)
	var shot := OS.get_environment("CLOTH_SHOT")
	if shot != "":
		await _shot(shot, turn_scene(), peak_t)
	quit(1 if fails > 0 else 0)


## the picture: the turn scene in the app with the cape baked, the playhead at the peak lag, the view from behind
func _shot(shot: String, T: Scene, t: float) -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute("user://")
	var tmp := "user://cloth_turn_shot.json"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	fa.store_string(JSON.stringify(T.to_dict(m.B)))
	fa.close()
	m._load_scene(tmp)
	m._rebuild_cards()
	m.playing = false
	m._cape_add()
	m.playhead = t
	m._ps().apply(m.B, t)
	m._turn_to(SHOT_YAW, -4.0, 3.6, Vector3(0.0, 1.0, -0.05), false)
	m._refresh()
	for i in 3:
		await process_frame
	DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
	await process_frame
	root.get_texture().get_image().save_png(shot)
	print("   picture at %.2f s (cape tip lag %.1f deg, camera yaw %.0f) -> %s" % [t, Cloth.tip_lag_deg(m.S.cape["frames"][int(round(t * 30.0))]), SHOT_YAW, shot])
