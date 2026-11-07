class_name PoseBake
extends RefCounted
## ROADMAP 99 (4 fighters at 60 fps): THE APPLIED POSE, BAKED. Playback evaluates the same scene at the same times over and
## over; Scene.apply (the cards, the walk's leg solver, IK, plants, layers) costs 5-20 ms a call for a walk. This bakes what
## apply leaves in the body (the lossless pose state AND the fk result G / P / E, plus the scene's per-apply reports) at
## every GRID time k / GRID_FPS on a WorkerThreadPool task, on a CLONE of the scene and a body of its own, and Scene.apply
## serves an entry back instead of solving when it is asked for exactly that time. EXACT: the entry IS what apply left,
## so a served frame is bit for bit the live one (tests/perf4_test.gd compares every Body and Scene variable).
## - The GRID is the scene's fps raised to a multiple that reaches 60 Hz (30 fps -> 60); a time that is not exactly k / GRID
##   (a scrub between frames) is solved live, as is any entry not baked yet (a partial table serves what it has).
## - The KEY is the scene's content (var_to_bytes of every field apply reads, compared whole: no hash to collide). Anything
##   that changes it drops the table and a new bake starts, from the playhead's frame on. The app polls it (sig_changed).
## - Not baked: a scene whose pose reads another fighter (constraints / actor targets: cons non-empty) or one with clips (Clips' static scratch bodies) or a co-edit peer.
## - Playback (Scene.play_t) snaps the evaluated time to the grid, live or cached alike, so the two cannot differ.

const SKEL := "res://data/skeleton.json"
const LIMS := "res://data/body_limits.json"
const MAX_ENTRIES := 7200   # 2 minutes at 60: a longer scene bakes its first two minutes (the rest solves live)

var scene: Scene = null
var grid := 60
## the table answers Scene.apply only while the scene PLAYS (main._process sets it): an edit makes the table stale until the next
## _bake_poll, and anything that reads the scene between the edit and that poll (a drag solving against the cards it just moved, a
## trail key drag, a grader) would get the poses of the cards as they WERE. Not playing, apply solves live: always the cards as they are
static var serving := false
var n := 0
var sig := PackedByteArray()
var buf: Array = []
var filled := 0          # entries published (read under mu)
var mu := Mutex.new()
var task := -1
var cancel := [false]
var hz := 0.0            # seconds the table covers
var hits := 0
var misses := 0

## every baker with a task in flight (main thread only). A scene that is swapped out (File > New, Open, a test's m.S = ...)
## takes its baker with it, and that baker's worker was still running at quit: the exit crashed (0xC0000005) in the
## engine tearing down the objects the worker read. main stops these at quit and when their scene leaves play.
static var running: Array = []


static func stop_all() -> void:
	for b in running.duplicate():
		(b as PoseBake).stop()


## stop every baker whose scene is not among `live` (its scene was replaced)
static func reap(live: Array) -> void:
	for b in running.duplicate():
		if not live.has((b as PoseBake).scene):
			(b as PoseBake).stop()


## the fields apply reads, as bytes (compared whole). A live Scene's runtime memos are not content and are left out.
static func signature(S: Scene) -> PackedByteArray:
	return var_to_bytes([S.cards, S.face, S.props, S.part_keys, S.attrs, S.ik, S.sets, S.clips, S.plants, S.drivers, S.secondary,
		S.cons, S.layer, S.layer_w, S.layers, S.breath, S.fitness, S.spline, S.natural, S.on_floor, S.floor_body, S.free_limits, S.pin, S.fps,
		S.moving_holds, S.sway, S.sway_seed, S.stepped, S.loop, S.body, S.markers, S.lip, S.boxes, S.shots, S.cape, S.hair, S.rigx])


static func grid_for(fps: int) -> int:
	var f := maxi(fps, 1)
	return f * maxi(1, ceili(60.0 / float(f) - 0.000001))


static func eligible(S: Scene) -> bool:
	# clips play on Clips' static scratch bodies, which a second thread must not share: not baked
	return S.cons.is_empty() and S.clips.is_empty() and S.cards.size() >= 1


func ready() -> bool:
	return task >= 0 and not (cancel[0] as bool)


## (re)bake `S` from the playhead's frame on; any bake in flight is cancelled first
var held_at := {}   # the weapon state the table was baked from (start's held): a change re-bakes, as a content change does
## held: the live body's weapon state (Body._state0's wep_* / grip keys) the worker body starts from: a card without a "weapon"
## leaves the body's weapon as it is when the scene plays live, so the table must start from the same one (a sword picked
## during play was dropped by every baked frame: the worker body held no weapon)
func start(S: Scene, from_t: float, horizon := 0.0, held := {}) -> void:
	stop()
	scene = S
	sig = signature(S)
	grid = grid_for(S.fps)
	hz = maxf(S.length(), horizon)   # the longest scene that plays beside it: past its own end it holds its last pose
	n = clampi(ceili(hz * grid) + 1, 1, MAX_ENTRIES)
	buf = []
	buf.resize(n)
	filled = 0
	hits = 0
	misses = 0
	if not eligible(S):
		task = -1
		return
	held_at = held.duplicate(true)
	var wk := held.duplicate(true)
	var cl := S.clone()
	cl.baker = null
	var k0 := clampi(roundi(from_t * grid), 0, n - 1)
	var out := buf
	var cc := cancel
	var m := mu
	var g := grid
	var nn := n
	if not running.has(self):
		running.append(self)
	task = WorkerThreadPool.add_task(func():
		var BB := Body.new()
		BB.load_files(SKEL, LIMS)
		if not wk.is_empty():
			var s0 := BB._state0()
			s0.merge(wk, true)
			BB._set_state0(s0, false)
		BB.fk()
		for i in nn:
			if cc[0]:
				return
			var k := (k0 + i) % nn
			cl.apply(BB, float(k) / float(g))
			var e := capture(cl, BB)
			m.lock()
			out[k] = e
			m.unlock())


## stop the bake in flight (it ends at its next frame) and wait for it: a task is always waited for
func stop() -> void:
	if task >= 0:
		cancel[0] = true
		WorkerThreadPool.wait_for_task_completion(task)
	task = -1
	running.erase(self)
	cancel = [false]
	buf = []
	n = 0
	scene = null


func done() -> bool:
	return task >= 0 and WorkerThreadPool.is_task_completed(task)


## the weapon keys of a body's state: what start(held) takes
static func held_of(B: Body) -> Dictionary:
	var out := {}
	for k in B._state0():
		if String(k).begins_with("wep") or String(k).begins_with("grip"):
			out[k] = B._state0()[k]
	return out


static func capture(S: Scene, B: Body) -> Dictionary:
	return {"s": B._state0(), "G": B.G.duplicate(), "P": B.P.duplicate(), "E": B.E.duplicate(),
		"ik": S.ik_last.duplicate(true), "pl": S.plant_last.duplicate(true), "cn": S.cons_last.duplicate(true), "pr": B.props}


## the entry for time t, or null (not on the grid, not baked yet, no table)
func entry(t: float):
	if task < 0 or n == 0:
		return null
	var k := roundi(t * grid)
	if k < 0 or k >= n or float(k) / float(grid) != t:
		return null
	mu.lock()
	var e = buf[k]
	mu.unlock()
	return e


## put an entry into the body and the scene's reports: what apply would have left
func restore(S: Scene, B: Body, e: Dictionary) -> void:
	B._set_state0(e["s"], false)
	B.G = (e["G"] as Dictionary).duplicate()
	B.P = (e["P"] as Dictionary).duplicate()
	B.E = (e["E"] as Dictionary).duplicate()
	B.props = e["pr"]
	B._fk_a = B.ang.duplicate()   # G / P / E are for exactly these angles: the next fk() recomputes only what changes
	B._fk_off = B.offset
	S.ik_last = (e["ik"] as Dictionary).duplicate(true)
	S.plant_last = (e["pl"] as Dictionary).duplicate(true)
	S.cons_last = (e["cn"] as Array).duplicate(true)

