## godot --path . --position 4000,4000 --resolution 1280x720 -s tests/animcpu_test.gd [-- --profile] [-- --golden]     (needs a window)
## ANIMATE CPU: a playing 6-clip scene must stay cheap on the main thread, and the cheaper path must pose the body exactly as before.
## Bars: (1) the median main-thread script time of a playing frame (the app's whole _process, 300 frames, 6 clips) is within the budget,
## (2) 50 clips play at 40 fps or better (frame gaps, vsync off), (3) the poses at 30 sampled frames of 3 scenes are bit for bit the
## recorded ones (tests/animcpu_golden.json, made by --golden on the code before the speed-up). --profile prints the PerfDoc brackets.
## Nick's scene files and user:// scenes are never written; the scenes are copied to user://.
extends SceneTree

const GOLDEN := "res://tests/animcpu_golden.json"
const SCENES := ["combo3", "walk_bat", "thrust"]
const CLIP_SRC := ["scenes/walk_bat.json", "scenes/combo3.json", "scenes/thrust.json", "scenes/swing_back.json", "scenes/swing_fore.json", "scenes/dodge_side.json"]
const BUDGET_MS := 12.0
const FPS50 := 40.0

var fails := 0
var m: Node
var args := {}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2]) if not s.is_empty() else 0.0


func boot() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	m._as_wait = -1e9
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.undo.clear()
	m.redo.clear()
	await idle(10)


func clips_n(n: int) -> void:
	var cl := []
	for i in n:
		cl.append(Clips.make(CLIP_SRC[i % CLIP_SRC.size()], 0.4 * i, {"bin": 0.2, "bout": 0.2} if i % 2 == 0 else {}))
	m.S.clips = cl
	m._refresh()


## play n frames after a warm-up; returns [median script ms, median frame gap ms, PerfDoc rows]
func play_run(n: int, prof := false) -> Array:
	m.S.loop = true
	m.playhead = 0.0
	m.playing = true
	m._page_set("ANIMATE", false)
	await idle(30)
	PerfDoc.acc = {}
	PerfDoc.on = prof
	PerfDoc.probe = true
	var pu := []
	var gaps := []
	var rc := []
	var rg := []
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var last := Time.get_ticks_usec()
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		gaps.append((now - last) / 1000.0)
		last = now
		rc.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
		rg.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		pu.append(float(PerfDoc.proc_us) / 1000.0)
		PerfDoc.proc_us = 0
	PerfDoc.probe = false
	print("   render cpu %.2f ms, gpu %.2f ms (median)" % [med(rc), med(rg)])
	PerfDoc.on = false
	m.playing = false
	return [med(pu), med(gaps), PerfDoc.acc.duplicate()]


## a hash of the body's pose: angles, joint positions, the skeleton's bone poses
func pose_hash() -> Array:
	var b = m.B
	var arr := []
	for j in Body.ORDER:
		arr.append(b.ang[j] if b.ang.has(j) else null)
		arr.append(b.P[j] if b.P.has(j) else null)
	var sk: Skeleton3D = m.skel
	for i in sk.get_bone_count():
		arr.append(sk.get_bone_pose(i))
	return [arr.hash(), b.P["pelvis"] if b.P.has("pelvis") else Vector3.ZERO]


## a mix that touches every branch of the clip pass: mirror, add, masks, speed, repeat, hold, a warp
func mixed_clips() -> Array:
	return [Clips.make("scenes/walk_bat.json", 0.0, {"bin": 0.2, "bout": 0.2, "repeat": 2}),
		Clips.make("scenes/combo3.json", 0.3, {"mirror": true, "mask": "upper", "w": 0.7}),
		Clips.make("scenes/thrust.json", 0.5, {"type": "add", "mask": "arms", "w": 0.5, "speed": 1.3}),
		Clips.make("scenes/swing_back.json", 0.2, {"mask": "legs", "extra": "hold"}),
		Clips.make("scenes/dodge_side.json", 0.9, {"type": "add", "mirror": true, "w": 0.6, "warp": [[0.5, 0.25]]}),
		Clips.make("scenes/swing_fore.json", 1.1, {"mask": "arm_l", "bin": 0.1})]


func sample_scene(name: String, with_clips := false) -> Array:
	var src := "res://scenes/%s.json" % name
	var dst := "user://animcpu_%s.json" % name
	DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
	m._load_scene(dst)
	m._rebuild_cards()
	m.undo.clear()
	if with_clips:
		m.S.clips = mixed_clips()
		m._refresh()
	await idle(3)
	var ps = m._ps()
	var total: float = ps.length()
	total = maxf(total, 3.0)
	var out := []
	for k in 30:
		m.playhead = total * float(k) / 30.0
		var t: float = ps.play_t(m.playhead)
		ps.apply(m.B, t)
		m._refresh()
		out.append(pose_hash()[0])
	if with_clips:   # the same frames again, backwards and with the cache warm: what a loop does. Must equal the first pass
		for k in range(29, -1, -1):
			m.playhead = total * float(k) / 30.0
			ps.apply(m.B, ps.play_t(m.playhead))
			m._refresh()
			if pose_hash()[0] != out[k]:
				print("  second pass differs at frame ", k)
				out[k] = -1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dst))
	return out


## the timeline's pixels while it plays (only the playhead's layer redrawn) against the same instant redrawn in full
## (stopped on that playhead): the number of differing pixels over `samples` instants
func tl_diff(samples: int) -> int:
	m.S.loop = true
	m.playhead = 0.0
	m.playing = true
	m._page_set("ANIMATE", false)
	await idle(40)
	var tl: Control = m.ui_timeline
	var bad := 0
	for k in samples:
		await idle(9 + k * 4)
		var a := root.get_texture().get_image()
		var p0: float = m.playhead
		m.playing = false
		await idle(3)
		var b := root.get_texture().get_image()
		var r := Rect2i(tl.get_global_rect())
		r = r.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
		var ca := a.get_region(r)
		var cb := b.get_region(r)
		var da := ca.get_data()
		var db := cb.get_data()
		var n := 0
		for i in da.size():
			if da[i] != db[i]:
				n += 1
		bad += n
		print("   instant %d at %.3f s: %d bytes differ of %d (%s)" % [k, p0, n, da.size(), str(r)])
		m.playing = true
	m.playing = false
	return bad


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	await boot()
	# poses first: the 3 scenes, 30 frames each
	var cur := {}
	for s in SCENES:
		cur[s] = await sample_scene(s)
		cur[s + "+clips"] = await sample_scene(s, true)
	if args.has("golden"):
		var f := FileAccess.open(ProjectSettings.globalize_path(GOLDEN), FileAccess.WRITE)
		f.store_string(JSON.stringify(cur))
		f.close()
		print("golden written")
	else:
		var gold: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
		for s in cur:
			var same := true
			for k in 30:
				if int(gold[s][k]) != int(cur[s][k]):
					same = false
					print("  pose differs: %s frame %d" % [s, k])
					break
			ok(same, "poses identical at 30 sampled frames: " + s)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle(5)
	clips_n(6)
	var bad: int = await tl_diff(6)
	ok(bad == 0, "the timeline drawn while playing equals a full redraw of the same instant (%d bytes differ)" % bad)
	var r: Array = await play_run(300, args.has("profile"))
	var rb: Array = await play_run(300)
	print("6 clips, 2nd run (warm caches): script %.2f ms, frame gap %.2f ms" % [rb[0], rb[1]])
	print("6 clips: script %.2f ms, frame gap %.2f ms" % [r[0], r[1]])
	if args.has("profile"):
		var rows := []
		for k in r[2]:
			rows.append([float(r[2][k]) / 300.0 / 1000.0, k])
		rows.sort()
		rows.reverse()
		for row in rows:
			print("   %-10s %.3f ms/frame" % [row[1], row[0]])
	ok(r[0] <= BUDGET_MS, "6 clips: median script time %.2f ms <= %.0f ms" % [r[0], BUDGET_MS])
	clips_n(50)
	if args.has("nodes"):   # switch each processing node off in turn: the frame gap it gives back is its cost
		m.S.loop = true
		m.playing = true
		await idle(30)
		var base := 0.0
		var res := []
		var nodes := [m]
		nodes.append_array(m.find_children("*", "", true, false))
		for n in nodes:
			if not (n.is_processing() and n.get_script() != null):
				continue
			var gp := []
			var l2 := Time.get_ticks_usec()
			for i in 60:
				await process_frame
				var n2 := Time.get_ticks_usec()
				gp.append((n2 - l2) / 1000.0)
				l2 = n2
			var with := med(gp)
			n.set_process(false)
			gp = []
			for i in 60:
				await process_frame
				var n3 := Time.get_ticks_usec()
				gp.append((n3 - l2) / 1000.0)
				l2 = n3
			n.set_process(true)
			res.append([with - med(gp), String(m.get_path_to(n)) + " " + String(n.get_script().resource_path.get_file())])
		res.sort()
		res.reverse()
		for row in res.slice(0, 15):
			print("   gives back %.2f ms  %s" % row)
	var draws := {}
	if args.has("profile"):   # which controls redraw while it plays (their _draw time is outside _process)
		for ci in m.find_children("*", "CanvasItem", true, false):
			var nm := String(m.get_path_to(ci))
			ci.draw.connect(func(): draws[nm] = int(draws.get(nm, 0)) + 1)
	var r2: Array = await play_run(300, args.has("profile"))
	if args.has("profile"):
		var dr := []
		for k in draws:
			dr.append([draws[k], k])
		dr.sort()
		dr.reverse()
		for row in dr.slice(0, 12):
			print("   redraws %4d  %s" % row)
	var fps: float = 1000.0 / maxf(r2[1], 0.001)
	print("50 clips: script %.2f ms, frame gap %.2f ms = %.1f fps" % [r2[0], r2[1], fps])
	ok(fps >= FPS50, "50 clips: %.1f fps >= %.0f" % [fps, FPS50])
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
