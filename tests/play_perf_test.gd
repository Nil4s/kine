## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/play_perf_test.gd     (ROADMAP 20: real-time playback)
## A HEAVY SCENE played in the real app (main.tscn): combo3 opened read only, a second fighter added (Actor: add), and on
## both fighters: an IK pin on each hand, a track-to constraint on the head, a clip of scenes/walk_bat.json (legs), an
## additive layer, breathing, three keyed props, and a foot plant. Nothing is written to scenes/, poses/ or data/.
## The POSE CACHE (scripts/pose_cache.gd: the foot-plant references, keyed on every input they read) is switched off
## for the reference runs with PoseCache.enabled = false.
##   1 BIT FOR BIT: a long playback (300 frames at 30 Hz, looping; a card edit at frame 150 and a plant-start edit at
##     frame 200, made the same way in both runs): the hero's and the second fighter's full body state, every frame, is
##     byte-identical with the cache on and off. ANTI-VACUITY: the cache was hit more than 100 times and missed at least
##     three times (the first frame and the two edits), and the plant's reference moves at the plant edit (so the cache
##     holds what that edit changes).
##   2 NO STALE FRAME: the frames at the plant edit and right after it equal the uncached ones bit for bit.
##   3 FPS: 6 rounds of 4 s of playing on one app, cache off and on alternating (round 0 is warm-up, not counted); the
##     frame cost in units of one whole-body Body.penetration() timed beside it (load-proof, as tests/drag_speed_test.gd
##     does). BAR: the cache-on frame costs at most 95 % of the cache-off frame. The target of 60 fps is printed, not
##     gated: it is reported as met or not met.
extends SceneTree

var fails := 0
var m: Node
const FRAMES := 300
const PLANT_EDIT_AT := 200
const DT := 1.0 / 30.0
const SPEEDUP_BAR := 0.95


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


## the heavy scene: the same build on the hero's scene and on the second fighter's
func build(S: Scene) -> void:
	var L := S.length()
	var pt := Vector3(0.3, 1.0, 0.3)
	var pole := Vector3(-0.6, 1.0, -0.3)
	S.ik = {"hand_l": [{"t": 0.0, "target": pt, "pole": pole, "w": 1.0}, {"t": L, "target": pt + Vector3(0, 0.2, 0), "pole": pole, "w": 1.0}],
		"hand_r": [{"t": 0.0, "target": Vector3(-0.3, 1.0, 0.3), "pole": pole, "w": 1.0}, {"t": L, "target": Vector3(-0.3, 1.2, 0.4), "pole": pole, "w": 1.0}]}
	S.cons = [{"type": "track_to", "owner": "head", "target": {"kind": "point", "at": Vector3(0.2, 1.6, 1.5)}, "w": 1.0, "wk": []}]
	S.clips = [Clips.make("scenes/walk_bat.json", 0.0, {"mask": "legs"})]
	S.layer = {"spine_02": Vector3(8, 0, 0), "spine_03": Vector3(6, 0, 3), "head": Vector3(-5, 4, 0), "neck_01": Vector3(0, 0, 10)}
	S.layer_w = 0.75
	S.breath = 1.0
	var kinds := ["box", "chair", "table"]
	S.props = []
	for i in 3:
		var p := Props.make(kinds[i], Props.xf_at(Vector3(0.8 + 0.4 * i, 0, 0.6 + 0.3 * i), 10.0 * i))
		Props.key_at(p, 0.0, p["xf"], 0.0)
		Props.key_at(p, L * 0.5, Props.xf_at(Vector3(0.6 + 0.4 * i, 0, 0.9), 40.0), 0.0)
		Props.key_at(p, L, p["xf"], 0.0)
		S.props.append(p)
	S.plants = [{"foot": "foot_l", "t0": 0.2 * L, "t1": 0.4 * L}]
	S.loop = true


## a fresh app with the heavy scene, idle (its _process is driven by the test where it matters)
func boot() -> void:
	if m != null:
		m.queue_free()
		await idle(3)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._actor_add()
	await idle()
	build(m.S)
	for k in m.actors_rt.size():
		if k != 0:
			build(m.actors_rt[k]["S"])
	m._refresh()
	m.playhead = 0.0
	m.playing = false


## the card edit in every run (frame EDIT_AT): the card under the plant's start is moved 30 cm sideways (its pelvis offset),
## one undo step. A planted foot is solved back onto its place, so the reference point does not move for this edit: it
## is checked for frame equality only. The edit that MOVES the reference is the plant's own start (PLANT_EDIT_AT): 0.1 s later.
func edit(ci: int) -> void:
	m._do(func():
		var p: Dictionary = (m.S.cards[ci]["pose"] as Dictionary).duplicate(true)
		var o: Array = p["offset"]
		p["offset"] = [float(o[0]) + 0.3, float(o[1]), float(o[2])]
		m.S.cards[ci]["pose"] = p)


func move_plant() -> void:
	m._do(func():
		var p: Dictionary = m.S.plants[0]
		p["t0"] = float(p["t0"]) + 0.1)


## the bytes of the hero's and the second fighter's whole body (exact: var_to_bytes keeps every float bit)
func states() -> Array:
	return [var_to_bytes(m.B.state()), var_to_bytes((m.actors_rt[1]["B"] as Body).state())]


## one playing frame exactly as the app runs it: _process driven by the test with a fixed dt
func frame() -> void:
	m.playing = true
	m._process(DT)


## the run: FRAMES frames; the edit before frame EDIT_AT; returns the per-frame states and the reference point at EDIT_AT
func run(cached: bool) -> Dictionary:
	await boot()
	m.set_process(false)   # only the test's frames run _process: the two runs take the same steps
	m.S.loop = true
	PoseCache.enabled = cached
	PoseCache.hits = 0
	PoseCache.misses = 0
	var t0 := m.S.plants[0]["t0"] as float
	var ci: int = m.S.span(t0)
	var edit_at := int(FRAMES * 0.5)
	var seq := []
	var pt_before := []
	var pt_after := []
	for f in FRAMES:
		if f == edit_at:
			edit(ci)
		if f == PLANT_EDIT_AT:
			pt_before = plant_point()
			move_plant()
			pt_after = plant_point()
		frame()
		seq.append(states())
	PoseCache.enabled = true
	return {"seq": seq, "hits": PoseCache.hits, "misses": PoseCache.misses, "before": pt_before, "after": pt_after, "edit_at": edit_at, "plant_at": PLANT_EDIT_AT}


## plant 0's reference as the UNCACHED code computes it: [ankle, pole, foot turn, ball turn] (a scratch body)
func plant_point() -> Array:
	var Q := Body.new()
	Q.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	Q.fk()
	var p: Dictionary = m.S.plants[0]
	var foot := String(p["foot"])
	var r: Dictionary = PoseCache._compute(m.S, Q, 0, foot, "ball" + foot.right(2), p)
	return [r["P"], r["pole"], r["G"], r["Gb"]]


## how far two plant references differ: the ankle and the pole in metres, the two turns in degrees
func ref_gap(a: Array, b: Array) -> float:
	return maxf(((a[0] as Vector3) - (b[0] as Vector3)).length() + ((a[1] as Vector3) - (b[1] as Vector3)).length(),
		maxf(rad_to_deg((a[2] as Quaternion).angle_to(b[2] as Quaternion)), rad_to_deg((a[3] as Quaternion).angle_to(b[3] as Quaternion))) * 0.001)


func _init() -> void:
	# ---- (1) and (2): the cached run against the uncached run, frame by frame, with the edit in the middle
	var off := await run(false)
	var on := await run(true)
	var same := true
	var first_diff := -1
	for f in FRAMES:
		if off["seq"][f] != on["seq"][f]:
			same = false
			if first_diff < 0:
				first_diff = f
	ok(same, "1 bit for bit: %d frames x 2 fighters, cache on vs off (first difference frame %d, -1 = none); cache hits %d, misses %d (the first frame and the edit at frame %d)"
		% [FRAMES, first_diff, on["hits"], on["misses"], on["edit_at"]])
	ok(int(on["hits"]) > 100 and int(on["misses"]) >= 3, "1 anti-vacuity: the cache was hit %d times and missed %d times (the first frame, the card edit, the plant edit)" % [on["hits"], on["misses"]])
	var moved := ref_gap(off["before"], off["after"])
	ok(moved > 0.001, "1 anti-vacuity: the plant plays from its new start and its reference moves (%.1f mm / deg-equivalent): the cache holds what the edit changes" % (moved * 1000.0))
	var e := int(on["plant_at"])
	ok(on["seq"][e + 1] == off["seq"][e + 1] and on["seq"][e] == off["seq"][e],
		"2 no stale frame: the frames at the plant edit and right after it (%d, %d) equal the uncached ones bit for bit" % [e, e + 1])
	# ---- (3) FPS: 6 rounds of 4 s of playing, cache off and on alternating (load drift hits both alike); round 0 is warm-up
	var rows := {false: [], true: []}
	var fps_sum := {false: 0.0, true: 0.0}
	await boot()   # one app for all rounds: a fresh app per round changed the frame cost (measured), so the rounds share it
	m.set_process(true)
	m.S.loop = true
	for r in 6:
		var mode: bool = r % 2 == 1
		PoseCache.enabled = mode
		m.playhead = 0.0
		m.playing = true
		var pen_t := 0.0
		var pen_n := 0
		var frames := 0
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 4000:
			await process_frame
			if m.playing:
				frames += 1
			var tp := Time.get_ticks_usec()
			m.B.penetration()
			pen_t += Time.get_ticks_usec() - tp
			pen_n += 1
		m.playing = false
		var fps := frames / 4.0
		var pen_ms := pen_t / 1000.0 / maxi(pen_n, 1)
		var frame_ms := 1000.0 / maxf(fps, 0.001)
		if r > 0:   # round 0 is the warm-up (shaders, first loads): printed, not counted
			rows[mode].append(frame_ms / maxf(pen_ms, 0.0001))
			fps_sum[mode] += fps
		print("     FPS round %d, cache %s: %.1f fps (%d playing frames in 4 s); %.2f ms a frame; penetration() %.2f ms beside it" % [r, "on " if mode else "off", fps, frames, frame_ms, pen_ms])
	var rows_mean := {}
	for mode in [false, true]:
		var sm := 0.0
		for x in rows[mode]:
			sm += float(x)
		rows_mean[mode] = sm / rows[mode].size()
	var fps_off: float = fps_sum[false] / 2.0   # rounds 2 and 4
	var fps_on: float = fps_sum[true] / 3.0     # rounds 1, 3 and 5
	rows = {false: {"fps": fps_off, "ratio": rows_mean[false]}, true: {"fps": fps_on, "ratio": rows_mean[true]}}
	var r_off: float = rows[false]["ratio"]
	var r_on: float = rows[true]["ratio"]
	ok(r_on <= SPEEDUP_BAR * r_off, "3 frame cost, cache on = %.1f penetrations vs %.1f off (%.0f %%; bar <= %.0f %%): mean %.1f fps off -> %.1f fps on over the counted rounds"
		% [r_on, r_off, 100.0 * r_on / r_off, 100.0 * SPEEDUP_BAR, rows[false]["fps"], rows[true]["fps"]])
	print("     TARGET 60 fps on the heavy scene: %s (measured %.1f fps with the cache on)" % ["MET" if rows[true]["fps"] >= 60.0 else "NOT MET", rows[true]["fps"]])
	print("PLAY PERF TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
