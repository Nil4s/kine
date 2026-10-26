## frame_memo.gd - INCREMENTAL SAMPLING for the realism score (ROADMAP I16 step 2).
## Check's samplers (Rulebook, HumanLimits, Feasible, ForceView) each play the scene at 60 fps and keep one record per frame. After a
## fix only a few cards changed, so only their frames are played again; every other frame's record comes from the last pass.
##   dirty frames = the window of every changed card (Fixer.window: the moves into/out of it, the pinned feet that carry on, a
##                  spline's reach), plus any card whose move time changed (an auto move reads its neighbours).
##   clean frames = the old record at the same place in the SAME card (old card start + the same time into it). When a timing fix moved a
##                  card, later frames land between two old frames: the nearest old frame is used (at most half a frame, 8 ms, of pose;
##                  the speeds read frame to frame, which still are 1/60 s apart).
##   I16d EXACT: a frame is taken from the last pass only when its shifted time lands within TOL (0.5 ms) of an old frame, or when it lies in a
##   HOLD (a card's rest after its move: the pose is the same at every time in it, checked frame by frame on combo3 and walk_bat), where any
##   old frame of the same card's hold is the same record. Everything else is played again, so incremental == cold (before: the nearest
##   frame, up to 8 ms off, gave a score 0.15 away from cold). A hold is also played ONCE per pass (pose and each judge's record).
## Used only while `on` (RealismUI.gather sets it) and only for a plain scene (no plants, props, clips, layers, drivers, constraints,
## IK, part keys, attributes, breathing): anything else plays in full, as before. `probe` reads the memo but does not replace it
## (scoring a fix on a copy must not make the next real score start from the copy).
class_name FrameMemo
extends RefCounted

static var on := false
static var probe := false
static var _mem := {}      # tag -> {"sid", "cards": [str], "ts": times, "recs", "n", "ctx"}
static var _win_key := ""
static var _win := []
static var _anch := []     # Scene._anchors of the cards the memo holds (the carry-forward stops where they come out as before)
static var _anch_key := ""
static var prof := {}      # stage -> ms, summed since the last `prof = {}` (the profile of one re-score; see tick)
static var played := 0     # frames played / re-used by the last call (for the report)
static var reused := 0
# TIME SLICING (checkhunt): a caller that awaits sets slice_ms > 0; a long loop then gives the frame back every slice_ms of main-thread time
# (progress shows the fraction done). 0 = never wait: every other caller runs the loop in one go, exactly as before.
static var slice_ms := 0.0
static var abort := false   # a newer click cancels the run: every loop stops at its next pump and the caller returns empty
static var progress := Callable()   # called with (done: float 0..1) at each pump
static var _slice_t := 0
static var waited_usec := 0   # time the slices spent giving the frame back (a Fix all step's own work = its wall time less this)

## the loops call this between steps: true = go on, false = cancelled
static func pump(done := -1.0) -> bool:
	if not slicing():
		return true
	if Time.get_ticks_usec() - _slice_t < int(slice_ms * 1000.0):
		return true
	if progress.is_valid() and done >= 0.0:
		progress.call(done)
	var w0 := Time.get_ticks_usec()
	await (Engine.get_main_loop() as SceneTree).process_frame
	waited_usec += Time.get_ticks_usec() - w0
	_slice_t = Time.get_ticks_usec()
	return not abort

## slicing is a main-thread thing: a worker thread (Fix all's bisection, the Polish pass) plays its loops in one go, never waits on a frame
static func slicing() -> bool:
	return slice_ms > 0.0 and OS.get_thread_caller_id() == OS.get_main_thread_id()

## a plain (non-awaiting) call of a *_co function: no slicing for its duration, on the main thread only (another thread must not touch it)
static func suspend_slicing() -> float:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return 0.0
	var k := slice_ms
	slice_ms = 0.0
	return k

static func resume_slicing(k: float) -> void:
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		slice_ms = k

static func slice_begin(ms: float, prog := Callable()) -> void:
	slice_ms = ms
	abort = false
	progress = prog
	_slice_t = Time.get_ticks_usec()

static func slice_end() -> void:
	slice_ms = 0.0
	progress = Callable()


const TOL := 0.0005        # s: an old frame is re-used for a new time only if it was sampled this close to it
static var _holds := []    # [[from, to, card]]: the holds of the scene being judged, made on the first pose of a pass (cleared by new_pass)
static var _holds_sid := 0
static var _pc := {}       # t (in 10 us) -> the body's state after Scene.apply_true at t: the four judges pose each frame ONCE (cleared by new_pass)


static func tick(stage: String, t0: int) -> void:
	prof[stage] = float(prof.get(stage, 0.0)) + float(Time.get_ticks_usec() - t0) / 1000.0


static func new_pass() -> void:
	_pc = {}
	_holds = []
	_holds_sid = 0


## the holds of a plain scene as [from, to, card] (the rest of a card after its move, inside by 0.1 ms each side); [] when the pose could
## depend on the time within a hold (moving holds, a jump in the air)
static func hold_list(S: Scene) -> Array:
	var out := []
	if S.moving_holds or (S.on_floor and not S.flights().is_empty()):
		return out
	var ts: Array = S.times()
	for i in ts.size():
		if float(ts[i][2]) - float(ts[i][1]) > 0.0004:
			out.append([float(ts[i][1]) + 0.0001, float(ts[i][2]) - 0.0001, i])
	return out


## the card whose hold contains t, or -1
static func hold_at(holds: Array, t: float) -> int:
	for h in holds:
		if t >= float(h[0]) and t <= float(h[1]):
			return int(h[2])
	return -1


## Scene.apply_true(B, t), shared: the first judge to ask for a time plays it, the others put the same state on their body (a plain scene only:
## the pose is a function of the cards and t alone; anything else plays in full)
static func pose(S: Scene, B: Body, t: float) -> void:
	if not on or not plain(S):
		S.apply_true(B, t)
		return
	var k := roundi(t * 100000.0)
	if _holds_sid != S.get_instance_id():
		_holds = hold_list(S)
		_holds_sid = S.get_instance_id()
	var hc := hold_at(_holds, t)
	if hc >= 0:
		k = -1 - hc   # every time in a card's hold is the same pose: played once
	var st = _pc.get(k)
	if st != null:
		B._set_state0(st)
		return
	var tp := Time.get_ticks_usec()
	S.apply_true(B, t)
	tick("pose (apply_true)", tp)
	_pc[k] = B._state0()


static func reset() -> void:
	_mem = {}
	_win_key = ""
	_anch_key = ""


static func plain(S: Scene) -> bool:
	return S.plants.is_empty() and S.props.is_empty() and S.clips.is_empty() and S.layers.is_empty() and S.layer.is_empty() and S.drivers.is_empty() \
		and S.cons.is_empty() and S.ik.is_empty() and S.part_keys.is_empty() and S.attrs.is_empty() and is_zero_approx(S.breath) and not S.stepped


static func _ctx(S: Scene) -> String:
	return var_to_str([S.body, S.spline, S.pin, S.on_floor, S.floor_body, S.free_limits, S.natural, S.moving_holds, S.fps, S.loop, S.name])


## the records of frames 0..n-1 (time min(i/hz, length)); fn.call(i, t) plays one frame and returns its record
static func frames(tag: String, S: Scene, B: Body, n: int, hz: float, fn: Callable) -> Array:
	var keep := suspend_slicing()   # a plain call never waits for a frame
	var r: Array = frames_co.call(tag, S, B, n, hz, fn)
	resume_slicing(keep)
	return r


static func frames_co(tag: String, S: Scene, B: Body, n: int, hz: float, fn: Callable) -> Array:
	var tp := Time.get_ticks_usec()
	var r: Array = await _frames(tag, S, B, n, hz, fn)
	tick("play " + tag, tp)
	return r


static func _frames(tag: String, S: Scene, B: Body, n: int, hz: float, fn: Callable) -> Array:
	var L := S.length()
	var sigs := []
	for c in S.cards:
		sigs.append(c.hash())   # var_to_str of 156 cards was 0.3 s of one frame; the hash of a card is as good a signature
	var ts: Array = S.times()
	var usable := on and plain(S)
	var ctx := _ctx(S)
	var recs := []
	recs.resize(n)
	var m: Dictionary = _mem.get(tag, {})
	var dirty_all := true
	var wins := []
	if usable and not m.is_empty() and m["sid"] == S.get_instance_id() and m["ctx"] == ctx and (m["cards"] as Array).size() == sigs.size() \
			and int(m["n"]) > 0 and is_equal_approx(float(m["hz"]), hz):
		var changed := []
		var timed := false
		var ots: Array = m["ts"]
		for i in sigs.size():
			var move_changed: bool = absf((float(ts[i][1]) - float(ts[i][0])) - (float(ots[i][1]) - float(ots[i][0]))) > 1e-6
			timed = timed or move_changed
			if sigs[i] != m["cards"][i] or move_changed:
				changed.append(i)
		if changed.size() * 2 <= sigs.size():
			dirty_all = false
			var wk := var_to_str(changed) + str(sigs.hash()) + str(hash(var_to_str(ts)))
			if wk != _win_key:
				_win = []
				for c in changed:
					_win.append(Fixer.window(S, c, B, [] if timed else m.get("anch", [])))   # a timing edit keeps the full carry: cold != narrowed on combo3 (cards 4, 7)
				_win_key = wk
			wins = _win
	played = 0
	reused = 0
	var holds: Array = hold_list(S) if usable else []
	var hrec := {}   # card -> the record of its hold, played once per call
	var ots2: Array = m.get("ts", [])
	var orecs: Array = m.get("recs", [])
	var on_ := int(m.get("n", 0))
	for i in n:
		var t := minf(i / hz, L)
		var hc := hold_at(holds, t)
		var dirty := dirty_all
		if not dirty_all:
			for w in wins:
				if t >= (w as Vector2).x and t <= (w as Vector2).y:
					dirty = true
					break
		var j := -1
		if not dirty:
			var c := 0
			for q in ts.size():
				if float(ts[q][0]) <= t + 1e-9:
					c = q
			c = mini(c, ots2.size() - 1)
			var ot: float = float(ots2[c][0]) + (t - float(ts[c][0]))
			if hc >= 0 and hc < ots2.size():
				# a hold: every old frame inside the same card's hold is the record of this one, wherever the shift put it
				var lo := ceili((float(ots2[hc][1]) + 0.0001) * hz - 1e-9)
				var hi := floori((float(ots2[hc][2]) - 0.0001) * hz + 1e-9)
				if lo <= hi and hi < on_:
					j = clampi(roundi(ot * hz), lo, hi)
			if j < 0 and ot >= -1e-6 and ot <= float(ots2[-1][2]) + 1e-6:
				var jr := clampi(roundi(ot * hz), 0, on_ - 1)
				if absf(ot - jr / hz) <= TOL:   # I16d: only a frame sampled within 0.5 ms of this time; the others are played
					j = jr
		if j >= 0:
			recs[i] = orecs[j]
			reused += 1
		elif hc >= 0 and hrec.has(hc):
			recs[i] = hrec[hc]
			reused += 1
		else:
			recs[i] = fn.call(i, t)
			played += 1
			if hc >= 0:
				hrec[hc] = recs[i]
			if slicing() and not await pump(float(i) / float(n)):
				return []
	if usable and not probe:
		var anch := []
		if S.pin:
			var ak := str(sigs.hash()) + ctx
			if ak != _anch_key:   # the four judges share one
				var keep := B.state()
				_anch = S._anchors(B)
				B.set_state(keep)
				B.fk()
				_anch_key = ak
			anch = _anch
		_mem[tag] = {"anch": anch, "sid": S.get_instance_id(), "cards": sigs, "ts": ts, "recs": recs, "n": n, "hz": hz, "ctx": ctx}
	return recs
