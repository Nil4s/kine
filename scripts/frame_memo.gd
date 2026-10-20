## frame_memo.gd - INCREMENTAL SAMPLING for the realism score (ROADMAP I16 step 2).
## Check's samplers (Rulebook, HumanLimits, Feasible, ForceView) each play the scene at 60 fps and keep one record per frame. After a
## fix only a few cards changed, so only their frames are played again; every other frame's record comes from the last pass.
##   dirty frames = the window of every changed card (Fixer.window: the moves into/out of it, the pinned feet that carry on, a
##                  spline's reach), plus any card whose move time changed (an auto move reads its neighbours).
##   clean frames = the old record at the same place in the SAME card (old card start + the same time into it). When a timing fix moved a
##                  card, later frames land between two old frames: the nearest old frame is used (at most half a frame, 8 ms, of pose;
##                  the speeds read frame to frame, which still are 1/60 s apart).
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
static var played := 0     # frames played / re-used by the last call (for the report)
static var reused := 0


static var _pc := {}       # t (in 10 us) -> the body's state after Scene.apply_true at t: the four judges pose each frame ONCE (cleared by new_pass)


static func new_pass() -> void:
	_pc = {}


## Scene.apply_true(B, t), shared: the first judge to ask for a time plays it, the others put the same state on their body (a plain scene only:
## the pose is a function of the cards and t alone; anything else plays in full)
static func pose(S: Scene, B: Body, t: float) -> void:
	if not on or not plain(S):
		S.apply_true(B, t)
		return
	var k := roundi(t * 100000.0)
	var st = _pc.get(k)
	if st != null:
		B._set_state0(st)
		return
	S.apply_true(B, t)
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
	var L := S.length()
	var sigs := []
	for c in S.cards:
		sigs.append(var_to_str(c))
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
	if dirty_all:
		for i in n:
			recs[i] = fn.call(i, minf(i / hz, L))
			played += 1
	else:
		var ots2: Array = m["ts"]
		var orecs: Array = m["recs"]
		var on_ := int(m["n"])
		for i in n:
			var t := minf(i / hz, L)
			var dirty := false
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
				j = clampi(roundi(ot * hz), 0, on_ - 1)
				if ot < -1e-6 or ot > float(ots2[-1][2]) + 1e-6:
					j = -1
			if j >= 0:
				recs[i] = orecs[j]
				reused += 1
			else:
				recs[i] = fn.call(i, t)
				played += 1
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
