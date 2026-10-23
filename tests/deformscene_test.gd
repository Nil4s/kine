## godot --path . -s tests/deformscene_test.gd     (ROADMAP_400 H17, deformation graded over the scene: scripts/deform_scene.gd +
## scripts/deform_scene_ui.gd; needs a window). Every frame of the scene skinned, each joint region graded against rest.
## Bars, written before measuring:
##  (1) REST: a scene of two rest cards: every region of every frame within 0 +- 0.5% volume, its triangles within 1 +- 0.005x
##      (stretch and squash); the frame count is the scene's rate x its length + 1 (30 Hz here, 60 Hz in (4))
##  (2) MONOTONIC: a scene that bends the LEFT elbow 0 -> 90 -> 150 deg (held at each) and back: the left elbow region's volume
##      loss at 150 > at 90 > at 0 (the 0 frame within 0.5%), and over every frame, ordered by the elbow's angle, the loss never
##      falls by more than 0.2% as the angle grows
##  (3) WORST FRAME: the first listed frame is a frame of maximum flexion (its elbow angle, read back from the scene, is the
##      scene's largest within 0.01 deg) and it names the left elbow. CONTROL: the right elbow's region stays within 0 +- 0.5%
##      on every frame (the measure is local)
##  (4) DETERMINISTIC: the same scene graded twice gives the same per-frame, per-region numbers (exactly) and the same list;
##      at 60 Hz the frame count doubles (rate x length + 1) and the worst frame is still a frame of maximum flexion
##  (5) UI STALL: the command run through the app's own per-frame tick (main thread slices + the worker thread) on combo3 and on
##      the elbow scene: the longest main-thread tick <= 16 ms (the window's frame gaps are printed, not barred: other agents
##      load this machine)
##  (6) PLACEMENT: after the command on the elbow scene the timeline's red lane holds one span; its left / right ends map back
##      (Timeline.t_of) to its first / last red frame within half a frame; on the screenshot the lane pixel at the max-flexion
##      frame is red (fd_active, within 0.15) and the one at frame 2 (elbow straight) is not; the span sits inside the timeline
##      on screen. Clicking list row 1 puts the playhead on the worst frame and stands the ghost there: the ghost's vertices
##      are the body's own skin at that frame (SkinPaint.refresh) pushed 3 mm out (every drawn vertex within 2.5..3.5 mm)
##  (7) reading changes nothing: the body's angles, the skeleton's bone rotations, the skin's weights and the undo list
## The worst 3 frames of combo3 are printed (COMBO3 WORST).
extends SceneTree

var fails := 0
var m: Node
const OUT := "user://deformscene.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func rest_dict() -> Dictionary:
	var B: Body = m.B
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	return B.to_dict()


func elbow_scene(fps: int) -> void:
	var B: Body = m.B
	var cards := []
	for k in [[0.0, -1.0, 0.3], [90.0, 0.5, 0.3], [150.0, 0.5, 0.3], [0.0, 0.5, 0.2]]:
		rest_dict()
		B.ang["lowerarm_l"] = Vector3(k[0], 0, 0)
		B.fk()
		cards.append({"name": "elbow %d" % k[0], "pose": B.to_dict(), "move": k[1], "hold": k[2]})
	m.S.from_dict({"scene": "zz_elbow", "fps": fps, "free_limits": true, "cards": cards})
	m._rebuild_cards()


## the left elbow's angle at every frame, read back from the scene on a body of its own
func elbow_angles(n: int, fps: float) -> PackedFloat32Array:
	var G := Body.new()
	G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var out := PackedFloat32Array()
	for f in n:
		m._ps().apply(G, float(f) / fps)
		out.append((G.ang["lowerarm_l"] as Vector3).x)
	return out


func reg(res: Dictionary, name: String) -> int:
	return (res["regions"] as Array).find(name)


func grade(restore: Callable) -> Dictionary:
	var job := DeformScene.new()
	return job.finish_now(m.wp, m.skel, m.bone_idx, m._ps(), restore)


## the command through the app's own tick; -> [longest tick ms, longest frame gap ms, frames waited]
func run_ui() -> Array:
	m.ds_ui.run()
	var gap := 0.0
	var n := 0
	var last := Time.get_ticks_usec()
	while m.ds_ui.job.running() and n < 3000:
		await process_frame
		var now := Time.get_ticks_usec()
		gap = maxf(gap, float(now - last) / 1000.0)
		last = now
		n += 1
	var tk: Array = m.ds_ui.tick_ms
	var mid := 0.0
	for k in range(1, tk.size() - 1):
		mid = maxf(mid, float(tk[k]))
	print("  main-thread ms: start %.2f, longest slice %.2f, landing (lane + list) %.2f" % [tk[0], mid, tk[-1]])
	return [m.ds_ui.longest_tick(), gap, n]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle()
	var skel: Skeleton3D = m.skel
	var restore := func(): Overlays.pose_skeleton(skel, m.bone_idx, m.B)
	ok(not m.wp.is_empty() and m.ds_ui != null, "the mannequin has a skin and the app has the H17 panel object")

	# (1) rest
	var rd := rest_dict()
	m.S.from_dict({"scene": "zz_rest", "fps": 30, "cards": [{"name": "a", "pose": rd, "move": -1.0, "hold": 0.5}, {"name": "b", "pose": rd, "move": 0.3, "hold": 0.2}]})
	m._rebuild_cards()
	var rr := grade(restore)
	var wv := 0.0
	var ws := 0.0
	for g in rr["per"]:
		for x in g:
			wv = maxf(wv, absf(float(x["vol"])))
			ws = maxf(ws, maxf(float(x["smax"]) - 1.0, 1.0 - float(x["smin"])))
	print("rest: %d frames, %d regions, %d triangles in %d ms; worst |volume| %.5f%%, worst |stretch-1| %.6f" % [rr["frames"].size(), rr["regions"].size(), rr["tris"], rr["ms"], wv * 100.0, ws])
	ok(rr["regions"].size() == 12, "(1) 12 joint regions graded (%s)" % ", ".join(PackedStringArray(rr["regions"])))
	ok(rr["frames"].size() == roundi(m.S.length() * 30.0) + 1, "(1) %d frames = 30 Hz x %.2f s + 1" % [rr["frames"].size(), m.S.length()])
	ok(wv <= 0.005, "(1) REST every region of every frame within 0 +- 0.5%% volume (worst %.4f%%)" % (wv * 100.0))
	ok(ws <= 0.005, "(1) REST every triangle within 1 +- 0.005x stretch / squash (worst %.6f)" % ws)

	elbow_scene(30)
	# (2) (3) the elbow scene
	var r1 := grade(restore)
	var nf: int = r1["frames"].size()
	var angs := elbow_angles(nf, 30.0)
	var le := reg(r1, "left elbow")
	var re := reg(r1, "right elbow")
	var loss := PackedFloat32Array()
	for f in nf:
		loss.append(-float(r1["per"][f][le]["vol"]))
	var amax := 0.0
	for a in angs:
		amax = maxf(amax, a)
	var at := func(deg: float) -> int:
		var best := -1
		for f in nf:
			if absf(angs[f] - deg) < 0.01 and (best < 0 or f > best):
				best = f
		return best
	var f0: int = at.call(0.0)
	var f90: int = at.call(90.0)
	var f150: int = at.call(150.0)
	for f in [f0, f90, f150]:
		if f >= 0:
			var g: Dictionary = r1["per"][f][le]
			print("  frame %d elbow %.1f deg: volume %+.2f%%, stretch %.2fx, squash %.2fx" % [f, angs[f], 100.0 * float(g["vol"]), g["smax"], g["smin"]])
	ok(f0 >= 0 and f90 >= 0 and f150 >= 0, "(2) the scene holds the elbow at 0, 90 and 150 deg (frames %d, %d, %d; max %.2f)" % [f0, f90, f150, amax])
	if f0 >= 0 and f90 >= 0 and f150 >= 0:
		ok(loss[f150] > loss[f90] and loss[f90] > loss[f0] and absf(loss[f0]) <= 0.005, "(2) MONOTONIC left elbow volume loss %.2f%% at 150 > %.2f%% at 90 > %.3f%% at 0 (within 0.5%%)" % [loss[f150] * 100.0, loss[f90] * 100.0, loss[f0] * 100.0])
	var order := range(nf)
	order.sort_custom(func(a, b): return angs[a] < angs[b] or (angs[a] == angs[b] and a < b))
	var drop := 0.0
	for k in range(1, order.size()):
		if angs[order[k]] - angs[order[k - 1]] > 0.5:
			drop = maxf(drop, loss[order[k - 1]] - loss[order[k]])
	ok(drop <= 0.002, "(2) over all %d frames ordered by elbow angle the loss never falls by more than 0.2%% (largest fall %.3f%%)" % [nf, drop * 100.0])
	var w1: Dictionary = r1["worst"][0]
	print("elbow scene worst: ", ", ".join(PackedStringArray(r1["worst"].map(func(x): return x["text"]))))
	ok(absf(angs[int(w1["frame"])] - amax) <= 0.01, "(3) WORST FRAME %d is a frame of maximum flexion (%.2f deg, max %.2f): %s" % [w1["frame"], angs[int(w1["frame"])], amax, w1["text"]])
	ok(int(w1["r"]) == le and "left elbow" in str(w1["text"]), "(3) it names the left elbow")
	for k in r1["regions"].size():
		var g: Dictionary = r1["per"][int(w1["frame"])][k]
		print("  at frame %d %s: volume %+.2f%%, stretch %.2fx, squash %.2fx, grade %.2f" % [w1["frame"], r1["regions"][k], 100.0 * float(g["vol"]), g["smax"], g["smin"], g["sev"]])
	var rv := 0.0
	for f in nf:
		rv = maxf(rv, absf(float(r1["per"][f][re]["vol"])))
	ok(rv <= 0.005, "(3) CONTROL the right elbow stays within 0 +- 0.5%% on every frame (worst %.4f%%)" % (rv * 100.0))

	# (4) deterministic, and 60 Hz
	var r2 := grade(restore)
	var same: bool = r2["frames"].size() == nf
	if same:
		for f in nf:
			for k in r1["per"][f].size():
				var a: Dictionary = r1["per"][f][k]
				var b: Dictionary = r2["per"][f][k]
				for key in ["vol", "smax", "smin", "smax_b", "smin_b"]:
					same = same and a[key] == b[key]
	var t1: Array = r1["worst"].map(func(x): return x["text"])
	var t2: Array = r2["worst"].map(func(x): return x["text"])
	ok(same and t1 == t2, "(4) DETERMINISTIC two runs: every frame's numbers identical, same list of %d" % t1.size())
	elbow_scene(60)
	var r6 := grade(restore)
	var a6 := elbow_angles(r6["frames"].size(), 60.0)
	var m6 := 0.0
	for a in a6:
		m6 = maxf(m6, a)
	ok(r6["frames"].size() == roundi(m.S.length() * 60.0) + 1 and r6["frames"].size() > 2 * nf - 3, "(4) 60 Hz: %d frames = 60 x %.2f s + 1 (30 Hz: %d)" % [r6["frames"].size(), m.S.length(), nf])
	ok(absf(a6[int(r6["worst"][0]["frame"])] - m6) <= 0.01, "(4) 60 Hz worst frame %d is at maximum flexion (%.2f deg): %s" % [r6["worst"][0]["frame"], a6[int(r6["worst"][0]["frame"])], r6["worst"][0]["text"]])

	# (5) the command on combo3 through the app's tick
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	var st: Array = await run_ui()
	var rc: Dictionary = m.ds_ui.res
	print("combo3: %d frames at %d Hz, %d ms on the worker; longest main-thread tick %.2f ms over %d frames (longest window frame gap %.1f ms)" % [rc["frames"].size(), rc["fps"], rc["ms"], st[0], m.ds_ui.tick_ms.size(), st[1]])
	var red := 0
	for f in rc["frames"]:
		if float(f["sev"]) >= 1.0:
			red += 1
	print("combo3: %d of %d frames red" % [red, rc["frames"].size()])
	for k in mini(3, rc["worst"].size()):
		print("COMBO3 WORST %d: %s  (grade %.2f)" % [k + 1, rc["worst"][k]["text"], rc["worst"][k]["sev"]])
	ok(rc["frames"].size() == roundi(m.S.length() * m.S.fps) + 1 and rc["worst"].size() >= 3, "(5) combo3 graded: %d frames, %d worst moments listed" % [rc["frames"].size(), rc["worst"].size()])
	ok(st[0] <= 16.0, "(5) UI STALL combo3: longest main-thread tick %.2f ms (<= 16)" % st[0])

	# (6) the elbow scene through the command, on screen
	elbow_scene(30)
	m.playhead = 0.0
	m._ps().apply(m.B, 0.0)
	m._refresh()
	m._turn_to(0.0, -8.0, 5.0, Vector3(-0.8, 0.95, 0), false)
	await idle(3)
	# what reading must not change
	var ang0: Dictionary = m.B.ang.duplicate()
	var rot0 := []
	for b in skel.get_bone_count():
		rot0.append(skel.get_bone_pose_rotation(b))
	var w0 := []
	for s in m.wp["surfs"]:
		w0.append([(s["bones"] as PackedInt32Array).duplicate(), (s["w"] as PackedFloat32Array).duplicate()])
	var u0: int = m.undo.size()
	var se: Array = await run_ui()
	print("elbow scene: longest main-thread tick %.2f ms (window frame gap %.1f ms)" % [se[0], se[1]])
	ok(se[0] <= 16.0, "(5) UI STALL elbow scene: longest main-thread tick %.2f ms (<= 16)" % se[0])
	# (7) nothing read was changed
	var same_rot := true
	for b in skel.get_bone_count():
		same_rot = same_rot and (skel.get_bone_pose_rotation(b) as Quaternion).is_equal_approx(rot0[b])
	var same_w := true
	for si in m.wp["surfs"].size():
		var s: Dictionary = m.wp["surfs"][si]
		same_w = same_w and s["bones"] == w0[si][0] and s["w"] == w0[si][1]
	ok(m.B.ang == ang0 and same_rot and same_w and m.undo.size() == u0, "(7) body angles, bone rotations, the skin's weights and the undo list unchanged")
	await idle(4)
	var re2: Dictionary = m.ds_ui.res
	var tl: Timeline = m.ui_timeline
	var spans: Array = re2["spans"]
	ok(spans.size() == 1 and tl.ph == m.ds_ui.lane and not tl.ph.is_empty(), "(6) the timeline's red lane holds the scene's red span (%d span(s))" % spans.size())
	var img := root.get_texture().get_image()
	if spans.size() >= 1:
		var sp: Dictionary = spans[0]
		var fps := float(re2["fps"])
		var x0 := tl.x_of(float(sp["t0"]))
		var x1 := tl.x_of(float(sp["t1"]))
		var g0 := tl.t_of(x0) * fps
		var g1 := tl.t_of(x1) * fps
		print("  span frames %d..%d (worst %d), x %.1f..%.1f on the timeline" % [sp["f0"], sp["f1"], sp["frame"], x0, x1])
		var first_red := -1
		var last_red := -1
		for f in re2["frames"].size():
			if float(re2["frames"][f]["sev"]) >= 1.0:
				last_red = f
				if first_red < 0:
					first_red = f
		ok(absf(g0 - first_red) <= 0.5 and absf(g1 - last_red) <= 0.5, "(6) PLACEMENT the span's ends map back to frames %.2f / %.2f (first / last red frame %d / %d, within 0.5)" % [g0, g1, first_red, last_red])
		var xf := tl.get_global_transform_with_canvas()
		var ly := tl._ph_y() + Timeline.PH_H * 0.5 - 1.0
		var pmax: Vector2 = xf * Vector2(tl.x_of(float(w1["frame"]) / fps), ly)
		var pstr: Vector2 = xf * Vector2(tl.x_of(2.0 / fps), ly)
		var vr := Rect2(Vector2.ZERO, Vector2(img.get_width(), img.get_height()))
		var red_c := Tok.c("fd_active")
		var cmax := img.get_pixelv(Vector2i(pmax)) if vr.has_point(pmax) else Color.BLACK
		var cstr := img.get_pixelv(Vector2i(pstr)) if vr.has_point(pstr) else Color.BLACK
		var dmax := Vector3(cmax.r - red_c.r, cmax.g - red_c.g, cmax.b - red_c.b).length()
		var dstr := Vector3(cstr.r - red_c.r, cstr.g - red_c.g, cstr.b - red_c.b).length()
		print("  lane pixel at the max-flexion frame %s = %s (%.3f from red); at frame 2 %s = %s (%.3f)" % [pmax, cmax, dmax, pstr, cstr, dstr])
		ok(dmax <= 0.15 and dstr > 0.15, "(6) PLACEMENT on screen: red at the max-flexion frame (%.3f), not red at frame 2 (%.3f)" % [dmax, dstr])
		ok(tl.get_global_rect().has_point(pmax) and vr.has_point(pmax), "(6) the span is on screen inside the timeline (%s in %s)" % [pmax, tl.get_global_rect()])
	# the list, a click, the ghost
	var b1: Button = m.ui_find_list.find_child("dscene_1", true, false)
	ok(m.ui_find.visible and b1 != null, "(6) the panel lists the worst frames (row 1: %s)" % (b1.text if b1 != null else "none"))
	if b1 != null:
		b1.pressed.emit()
		await idle(4)
		var wf: int = re2["worst"][0]["frame"]
		ok(absf(m.playhead - float(wf) / float(re2["fps"])) < 1e-6 and m.ds_ui.ghost != null and m.ds_ui.ghost.visible and m.ds_ui.ghost_frame == wf, "(6) clicking row 1 puts the playhead on frame %d and stands its ghost" % wf)
		SkinPaint.refresh(m.wp)
		var body := PackedVector3Array()
		for s in m.wp["surfs"]:
			body.append_array(s["pos"])
		var gp: PackedVector3Array = re2["ghosts"][wf]["pos"]
		var drawn := PackedByteArray()   # the vertices a triangle uses (the only ones drawn; a loose one has no normal to push along)
		drawn.resize(gp.size())
		for t in (re2["T"] as PackedInt32Array):
			drawn[t] = 1
		var dlo := INF
		var dhi := 0.0
		for i in mini(body.size(), gp.size()):
			if drawn[i] == 0:
				continue
			var d := body[i].distance_to(gp[i])
			dlo = minf(dlo, d)
			dhi = maxf(dhi, d)
		ok(body.size() == gp.size() and dlo >= 0.0025 and dhi <= 0.0035, "(6) the ghost is the body's skin at frame %d pushed out: every vertex %.2f..%.2f mm off (2.5..3.5), %d vertices" % [wf, dlo * 1000.0, dhi * 1000.0, gp.size()])
		var nred := 0
		var sv: PackedFloat32Array = re2["ghosts"][wf]["sev"]
		for x in sv:
			if x >= 1.0:
				nred += 1
		ok(nred > 50, "(6) the ghost tints the elbow region red at that frame (%d vertices past a bar)" % nred)
	m._close_findings()
	if m.ds_ui.res.has("ghosts"):
		m.ds_ui.show_ghost(int(m.ds_ui.res["worst"][0]["frame"]))
	m._turn_to(35.0, -20.0, 1.3, m.B.P["lowerarm_l"], false)   # the left elbow at its worst, close
	await idle(30)
	var shot := root.get_texture().get_image()
	shot.save_png(OUT)
	print("screenshot: ", ProjectSettings.globalize_path(OUT))
	m._close_findings()
	ok(not m.ds_ui.ghost.visible, "(6) closing the panel hides the ghost")
	m.ds_ui.clear()
	ok(tl.ph.is_empty(), "(6) 'off' takes the lane away")
	print("DEFORMSCENE RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(fails)
