## CLIPS (docs/GAP_ANALYSIS.md row 12; how Blender's NLA and Maya's Time Editor do it: docs/research/NLA.md).
## A scene can place CLIPS: another scene file (or a saved move / pose from moves/) used BY REFERENCE, placed as a strip
## on the timeline. The source file is never copied in and never written: edit the walk once, every scene that places it
## plays the new walk. Scene.clips = [clip, ...], each a Dictionary:
##   "src"     the source file, res-relative ("scenes/walk_bat.json", "moves/bo_guard.json")
##   "start"   s, where the strip begins on this scene's timeline
##   "repeat"  int >= 1, how many times the source plays back to back
##   "speed"   > 0, playback rate (2 = twice as fast: the strip is half as long). Blender's Playback Scale = 1 / speed
##   "bin", "bout"   blend in / out seconds (the influence ramps, linear, as Blender's)
##   "type"    "replace" (lerp(below, clip, w)) or "add" (below + w x clip)
##   "mask"    which parts it drives: all / legs / upper / arms / arm_l / arm_r (MASKS)
##   "extra"   extrapolation: "nothing" (no effect outside the strip), "hold" (first frame before, last after),
##             "hold_forward" (last frame after only)
##   "w"       influence 0..1;  "mirror" the source plays mirrored (Mirror the scene sets it);  "mute"
##   "warp"    CLIP WARPING (ROADMAP 83): the strip's time curve, interior knots [[x, y], ...] (x, y in 0..1, x increasing,
##             y non-decreasing; the ends (0,0) and (1,1) are fixed). It maps the strip's own progress p = (t - start) / D to
##             the source's progress q = warp(p): u = q x L x repeat, so the source plays at warp(p) of its length over
##             the whole strip. Monotone piecewise cubic (Fritsch-Butland): no overshoot, never runs backwards. Empty
##             (or every knot on the diagonal) = linear = no warp, bit for bit; the key is written only when there is one.
##             The strip's length D does not change: a warp moves the poses, not the bar
## TIMING (Blender's strip time, nla: action clip time): the source lasts L s; the strip lasts D = L x repeat / speed and
## ends at E = start + D. At t inside it: u = (t - start) x speed, cycle k = min(floor(u / L), repeat - 1), the source's
## own time lt = u - k L (so t = E gives lt = L of the last cycle, the source's last frame, not its first).
## WEIGHT: w(t) = influence x ramp_in x ramp_out, ramp_in = clamp((t - start) / bin, 0, 1) (1 when bin = 0),
## ramp_out = clamp((E - t) / bout, 0, 1). In a held region the weight is the strip edge's (0 there if that side blends).
## ROOT MOTION ("cycle with offset", Blender's Cycles modifier "Repeat with Offset", Maya's clip relocate): cycle k's hips
## are moved by k x (offset(L) - offset(0)) over the floor (x and z; the height is the source's own each cycle), so a
## walk repeated 3 times walks three cycles' distance instead of jumping back to its start.
## ORDER in Scene.apply: cards (with part keys, planting, the floor) -> CLIPS in list order -> layers -> breathing -> IK
## -> constraints. Why: a clip is BASE motion (what Blender's NLA strips are: actions under the tweaked one), the cards
## being the scene's own action; layers are adjustments on top of the base (Maya's animation layers sit over the
## clips), and IK and constraints correct the FINISHED pose (Blender runs them after the NLA). Later clips sit over
## earlier ones (Blender: upper tracks over lower).
## MATCH (ROADMAP 84, scripts/pose_match.gd): "match" = {"lt0", "pa", "pb", "yaw"}, written only on a clip that was matched to
## the clip before it. The source starts at its own time lt0 (the frame that matched the seam) and loops from there (the
## strip keeps its length; time past the source's end wraps, the cycles' root steps still count). Its root is moved so that
## its hips at lt0 (pb, the source's floor position there) sit at pa (the previous clip's hips at the seam), and its pelvis
## twist turns by yaw, the walk turning about pb with it (yaw_sign: which way a twist turns the walk). Replace clips only.
## Each source is played by its own Scene.apply on a scratch body (floor, pins, its own layers and IK included), so a
## clip at weight 1, mask all, plays the source exactly as opening the file would. The weapon stays the cards'.
class_name Clips
extends RefCounted

const TYPES := ["replace", "add"]
## L79: the shape of a blend-in / blend-out ramp (x 0..1 -> 0..1, monotone, 0 and 1 fixed); linear is the old ramp
const CURVES := ["linear", "smooth", "ease_in", "ease_out"]
const EXTRA := ["nothing", "hold", "hold_forward"]
const MASK_NAMES := ["all", "legs", "upper", "arms", "arm_l", "arm_r"]
## the warp presets (the picked clip's knots); linear = none. Values read off the curve shapes they name
const WARP_PRESETS := {"linear": [], "ease_in": [[0.25, 0.0625], [0.5, 0.25], [0.75, 0.5625]],
	"ease_out": [[0.25, 0.4375], [0.5, 0.75], [0.75, 0.9375]], "slow_mid": [[0.25, 0.35], [0.5, 0.5], [0.75, 0.65]]}
const WARP_MAX := 6        # interior knots at most
const WARP_EPS := 0.001    # a drag keeps a knot this far (x) from its neighbours and from the ends
const WARP_KEEP := 0.000001   # the file keeps a knot only this far inside its neighbours (x): validity, not the drag's margin
const MAX_DEPTH := 3   # a source that places clips of its own plays them too, this deep at most (a loop stops here)

static var _cache := {}    # src path -> {"mt": modified time, "scene": Scene, "len": s, "d": {mirror: root step}}
static var _bodies := []   # scratch bodies, one per depth (a source's own clips use the next)
static var _depth := 0
## the scratch bodies, _depth and the cached source scenes are SHARED statics, and Scene.apply runs on worker threads
## (the dummy / fighters measure, the pose bake) as well as the main thread: two threads posing the same scratch body at
## once corrupted its dictionaries (undo_audit: "Invalid access to key on Dictionary" in Scene._toe_off_at). Every entry
## that touches them takes this lock (a Godot Mutex is recursive, so a source's own clips re-enter it)
static var _mu := Mutex.new()


## the joints a mask drives, and whether it drives the hips' position (root motion)
static func mask_joints(mask: String) -> Array:
	var out := []
	for j in Body.ORDER:
		var lv := Scene.level(j)
		var leg: bool = j == "pelvis" or j.begins_with("thigh") or j.begins_with("calf") or j.begins_with("foot") or j.begins_with("ball")
		var arm: bool = j.begins_with("clavicle") or j.begins_with("upperarm") or j.begins_with("lowerarm") or j.begins_with("hand") \
			or (lv == 6 and not leg)
		match mask:
			"legs":
				if leg:
					out.append(j)
			"upper":
				if not leg:
					out.append(j)
			"arms":
				if arm:
					out.append(j)
			"arm_l", "arm_r":
				if arm and j.ends_with(mask.substr(3)):
					out.append(j)
			_:
				out.append(j)
	return out


static func mask_root(mask: String) -> bool:
	return mask == "all" or mask == "legs"


static func mask_arms(mask: String) -> bool:
	return mask != "legs"


static func ramp(curve: String, x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	match curve:
		"smooth":
			return x * x * (3.0 - 2.0 * x)
		"ease_in":
			return x * x
		"ease_out":
			return 1.0 - (1.0 - x) * (1.0 - x)
	return x


## a clip with every field, from what a caller or a file gives
static func make(src: String, start: float, opts := {}) -> Dictionary:
	var c := {"src": src, "start": maxf(0.0, start), "repeat": 1, "speed": 1.0, "bin": 0.0, "bout": 0.0, "type": "replace",
		"mask": "all", "extra": "nothing", "w": 1.0, "mirror": false, "mute": false}
	for k in opts:
		c[k] = opts[k]
	return clean(c)


static func clean(c: Dictionary) -> Dictionary:
	var out := {"src": String(c.get("src", "")).trim_prefix("res://"), "start": maxf(0.0, float(c.get("start", 0.0))),
		"repeat": maxi(1, int(c.get("repeat", 1))), "speed": clampf(float(c.get("speed", 1.0)), 0.05, 20.0),
		"bin": maxf(0.0, float(c.get("bin", 0.0))), "bout": maxf(0.0, float(c.get("bout", 0.0))),
		"type": String(c.get("type", "replace")), "mask": String(c.get("mask", "all")), "extra": String(c.get("extra", "nothing")),
		"w": clampf(float(c.get("w", 1.0)), 0.0, 1.0), "mirror": bool(c.get("mirror", false)), "mute": bool(c.get("mute", false))}
	var wp := warp_norm(c.get("warp", []))
	if not wp.is_empty():
		out["warp"] = wp
	var mt := match_norm(c.get("match", {}))
	if not mt.is_empty():
		out["match"] = mt
	if String(c.get("curve", "linear")) in CURVES and String(c.get("curve", "linear")) != "linear":
		out["curve"] = String(c["curve"])   # L79: written only when not linear
	if bool(c.get("inplace", false)):
		out["inplace"] = true   # W08: IN PLACE, the hips' floor travel taken out (written only when on)
	if not out["type"] in TYPES:
		out["type"] = "replace"
	if not out["mask"] in MASK_NAMES:
		out["mask"] = "all"
	if not out["extra"] in EXTRA:
		out["extra"] = "nothing"
	return out


# ---------------------------------------------------------------- files

static func to_file(clips: Array) -> Array:
	return clips.map(func(c):
		var d := clean(c)
		d["start"] = snappedf(d["start"], 0.0001)
		d["speed"] = snappedf(d["speed"], 0.0001)
		d["bin"] = snappedf(d["bin"], 0.0001)
		d["bout"] = snappedf(d["bout"], 0.0001)
		d["w"] = snappedf(d["w"], 0.0001)
		if d.has("warp"):
			d["warp"] = warp_norm((d["warp"] as Array).map(func(k): return [snappedf(k[0], 0.0001), snappedf(k[1], 0.0001)]))
		return d)


static func from_file(a) -> Array:
	var out := []
	if a is Array:
		for c in a:
			if c is Dictionary and String(c.get("src", "")) != "":
				out.append(clean(c))
	return out


## MIRROR_SCENE "clips": the source plays mirrored (the flag toggles: twice = the original), a one-arm mask to the other arm
static func mirror_file(a: Array) -> Array:
	return a.map(func(c):
		var d: Dictionary = (c as Dictionary).duplicate(true)
		d["mirror"] = not bool(d.get("mirror", false))
		var mk := String(d.get("mask", "all"))
		if mk == "arm_l" or mk == "arm_r":
			d["mask"] = "arm_r" if mk == "arm_l" else "arm_l"
		return d)


# ---------------------------------------------------------------- sources

## the source file as a Scene: a scene file as is; a pose (moves/ "joints") as one card held 1 s; a keyed move ("keys")
## as cards at its key times with Moves' own ease (plain smoothstep, no hold). {} when it cannot be read
static func scene_of(d: Dictionary) -> Scene:
	var S := Scene.new()
	if d.has("cards"):
		S.from_dict(d)
	elif d.has("joints"):
		S.add("pose", d)
		S.cards[0]["hold"] = 1.0
	elif d.get("keys") is Array and not (d["keys"] as Array).is_empty():
		S.natural = false
		var ks: Array = (d["keys"] as Array).duplicate()
		ks.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
		for i in ks.size():
			S.add("key %d" % (i + 1), ks[i]["pose"])
			S.cards[i]["hold"] = 0.0
			if i > 0:
				S.cards[i]["move"] = maxf(0.001, float(ks[i]["t"]) - float(ks[i - 1]["t"]))
	else:
		return null
	return S if not S.cards.is_empty() else null


static func source(src: String) -> Dictionary:
	_mu.lock()
	var e := _source(src)
	_mu.unlock()
	return e


static func _source(src: String) -> Dictionary:
	var path := "res://" + src.trim_prefix("res://")
	if not FileAccess.file_exists(path):
		return {}
	var mt := FileAccess.get_modified_time(path)
	var e: Dictionary = _cache.get(path, {})
	if not e.is_empty() and int(e["mt"]) == mt:
		return e
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return {}
	var S := scene_of(d)
	if S == null:
		return {}
	e = {"mt": mt, "scene": S, "len": maxf(S.length(), 0.001), "d": {}}
	_cache[path] = e
	return e


static func _body(depth: int) -> Body:
	while _bodies.size() <= depth:
		var b := Body.new()
		b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		b.fk()
		_bodies.append(b)
	return _bodies[depth]


## the source posed at its own time lt on scratch body Q (mirrored if asked)
static func _pose_src(e: Dictionary, lt: float, mirror: bool, Q: Body) -> void:
	_depth += 1
	(e["scene"] as Scene).apply(Q, lt)
	_depth -= 1
	if mirror:
		Q.mirror_pose()


const POSE_CACHE_MAX := 2000   # entries one source keeps (a few hundred cover a loop of a clip at 60 Hz); past it the table starts over


## the source posed at its own time lt, as a cached [angles, hips offset] (mirrored if asked). A source posed at the same lt gives the
## same body, so a loop, a repeat, or the 2nd to 50th use of one file costs a lookup, not a Scene.apply. The table lives in the source's
## cache entry (a file that changed is reloaded with a fresh one) and is keyed by the nesting depth too (MAX_DEPTH cuts a chain short).
static func _pose_of(e: Dictionary, lt: float, mirror: bool, Q: Body) -> Array:
	var pc: Dictionary = e.get("pc", {})
	var side := _depth * 2 + (1 if mirror else 0)
	var tab: Dictionary = pc.get(side, {})
	var hit = tab.get(lt)
	if hit != null:
		return hit
	_pose_src(e, lt, mirror, Q)
	if e.get("pn", 0) >= POSE_CACHE_MAX:
		pc = {}
		e["pn"] = 0
		tab = {}
	var ent := [Q.ang.duplicate(), Q.offset]
	tab[lt] = ent
	pc[side] = tab
	e["pc"] = pc
	e["pn"] = int(e.get("pn", 0)) + 1
	return ent


## the hips' step one cycle makes over the floor: offset(L) - offset(0), y dropped
static func root_step(e: Dictionary, mirror: bool) -> Vector3:
	_mu.lock()
	var v := _root_step(e, mirror)
	_mu.unlock()
	return v


static func _root_step(e: Dictionary, mirror: bool) -> Vector3:
	if (e["d"] as Dictionary).has(mirror):
		return e["d"][mirror]
	var Q := _body(_depth)
	_pose_src(e, 0.0, mirror, Q)
	var a := Q.offset
	_pose_src(e, float(e["len"]), mirror, Q)
	var v := Q.offset - a
	v.y = 0.0
	e["d"][mirror] = v
	return v


# ---------------------------------------------------------------- warp (ROADMAP 83)

## the knots as they are kept while a drag runs: [x, y] pairs inside (0, 1), x strictly increasing, y non-decreasing in 0..1,
## at most WARP_MAX. Invalid entries are dropped; a knot on the diagonal stays (a drag may pass over it)
static func warp_clean(a) -> Array:
	var pts := []
	if a is Array:
		for k in a:
			if k is Array and (k as Array).size() >= 2:
				pts.append([clampf(float(k[0]), 0.0, 1.0), clampf(float(k[1]), 0.0, 1.0)])
	pts.sort_custom(func(p, q): return p[0] < q[0])
	var out := []
	var last_x := 0.0
	var last_y := 0.0
	for p in pts:
		if p[0] <= last_x + WARP_KEEP or p[0] >= 1.0 - WARP_KEEP or p[1] < last_y:
			continue
		out.append([p[0], maxf(p[1], last_y)])
		last_x = p[0]
		last_y = p[1]
		if out.size() >= WARP_MAX:
			break
	return out


## the knots as the file keeps them: warp_clean, and [] when every knot is on the diagonal (linear = no warp)
static func warp_norm(a) -> Array:
	var o := warp_clean(a)
	for p in o:
		if p[0] != p[1]:
			return o
	return []


## the warp curve at p in 0..1: monotone cubic Hermite through (0,0), the knots and (1,1)
static func warp_f(knots: Array, p: float) -> float:
	if knots.is_empty():
		return clampf(p, 0.0, 1.0)
	var xs := [0.0]
	var ys := [0.0]
	for k in knots:
		xs.append(float(k[0]))
		ys.append(float(k[1]))
	xs.append(1.0)
	ys.append(1.0)
	var n := xs.size()
	var dl := []   # the secant of each interval
	var h := []
	for i in n - 1:
		h.append(float(xs[i + 1]) - float(xs[i]))
		dl.append((float(ys[i + 1]) - float(ys[i])) / float(h[i]))
	var m := []    # the tangent at each point (Fritsch-Butland: a harmonic mean, zero where the secants change sign)
	m.append(float(dl[0]))
	for i in range(1, n - 1):
		var d0: float = dl[i - 1]
		var d1: float = dl[i]
		if d0 * d1 <= 0.0:
			m.append(0.0)
		else:
			var w1: float = 2.0 * float(h[i]) + float(h[i - 1])
			var w2: float = float(h[i]) + 2.0 * float(h[i - 1])
			m.append((w1 + w2) / (w1 / d0 + w2 / d1))
	m.append(float(dl[n - 2]))
	var x := clampf(p, 0.0, 1.0)
	for i in n - 1:
		if x <= float(xs[i + 1]) or i == n - 2:
			var s := (x - float(xs[i])) / float(h[i])
			var s2 := s * s
			var s3 := s2 * s
			var hh: float = h[i]
			return (2 * s3 - 3 * s2 + 1) * float(ys[i]) + (s3 - 2 * s2 + s) * hh * float(m[i]) 				+ (-2 * s3 + 3 * s2) * float(ys[i + 1]) + (s3 - s2) * hh * float(m[i + 1])
	return 1.0


## knot i moved to (x, y): clamped between its neighbours (x strictly between, y between theirs and 0..1), so the curve
## stays monotone whatever the drag. Returns the new knots (warp_clean'd)
static func warp_set(knots: Array, i: int, x: float, y: float) -> Array:
	var ks: Array = warp_clean(knots).duplicate(true)
	if i < 0 or i >= ks.size():
		return ks
	var prev := float(ks[i - 1][0]) if i > 0 else 0.0
	var next := float(ks[i + 1][0]) if i < ks.size() - 1 else 1.0
	var yl := float(ks[i - 1][1]) if i > 0 else 0.0
	var yr := float(ks[i + 1][1]) if i < ks.size() - 1 else 1.0
	var nx := clampf(x, prev + WARP_EPS, next - WARP_EPS) if next - prev >= 2.0 * WARP_EPS else (prev + next) * 0.5
	ks[i] = [nx, clampf(y, yl, yr)]
	return warp_clean(ks)


## a knot added at (x, y), its place in x order; refused (the knots unchanged) when there are WARP_MAX or x is too near an end or a knot
static func warp_add(knots: Array, x: float, y: float) -> Array:
	var ks: Array = warp_clean(knots).duplicate(true)
	if ks.size() >= WARP_MAX:
		return ks
	var j := 0
	while j < ks.size() and float(ks[j][0]) < x:
		j += 1
	var prev := float(ks[j - 1][0]) if j > 0 else 0.0
	var next := float(ks[j][0]) if j < ks.size() else 1.0
	if x < prev + WARP_EPS or x > next - WARP_EPS:
		return ks
	var yl := float(ks[j - 1][1]) if j > 0 else 0.0
	var yr := float(ks[j][1]) if j < ks.size() else 1.0
	ks.insert(j, [x, clampf(y, yl, yr)])
	return warp_clean(ks)


# ---------------------------------------------------------------- match (ROADMAP 84)

## a stored match as the file keeps it: {"lt0" >= 0 s, "pa" [x, z], "pb" [x, z] (m), "yaw" deg in -180..180}; {} when invalid
static func match_norm(a) -> Dictionary:
	if not a is Dictionary or not (a as Dictionary).has("lt0") or not (a as Dictionary).has("pa") or not (a as Dictionary).has("pb"):
		return {}
	var pa = a["pa"]
	var pb = a["pb"]
	if not (pa is Array and (pa as Array).size() >= 2 and pb is Array and (pb as Array).size() >= 2):
		return {}
	var q := func(x: float) -> float: return snappedf(x, 0.0001)
	return {"lt0": q.call(maxf(0.0, float(a["lt0"]))), "pa": [q.call(float(pa[0])), q.call(float(pa[1]))],
		"pb": [q.call(float(pb[0])), q.call(float(pb[1]))], "yaw": q.call(wrapf(float(a.get("yaw", 0.0)), -180.0, 180.0))}


## which way a pelvis twist turns the walk: +1 or -1, read off the body (the pelvis's facing turned by +10 deg of twist),
## so the walk turns WITH the body whatever the joint's axis convention is. Measured once
static var _yaw_sign := 0.0
static func yaw_sign() -> float:
	if _yaw_sign == 0.0:
		var Q := Body.new()
		Q.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		Q.fk()
		var f0 := _fwd(Q)
		Q.ang["pelvis"] = Vector3(0, 0, 10)
		Q.fk()
		var f1 := _fwd(Q)
		var plus := Basis(Vector3.UP, deg_to_rad(10.0)) * f0
		_yaw_sign = 1.0 if plus.distance_to(f1) <= (Basis(Vector3.UP, deg_to_rad(-10.0)) * f0).distance_to(f1) else -1.0
	return _yaw_sign


static func _fwd(Q: Body) -> Vector3:
	var f: Vector3 = Q.G["pelvis"] * Vector3.RIGHT
	f.y = 0.0
	return f.normalized()


## the hips' floor place off (source space, cycles counted) moved by a match: pa + R (off - pb), R the walk's turn by yaw
static func align(off: Vector3, mt: Dictionary) -> Vector3:
	var pa: Array = mt["pa"]
	var pb: Array = mt["pb"]
	var d := Vector3(off.x - float(pb[0]), 0.0, off.z - float(pb[1]))
	var r := Basis(Vector3.UP, deg_to_rad(yaw_sign() * float(mt["yaw"]))) * d
	return Vector3(float(pa[0]) + r.x, off.y, float(pa[1]) + r.z)


# ---------------------------------------------------------------- timing

static func length_of(c: Dictionary, L: float) -> float:
	return L * int(c["repeat"]) / float(c["speed"])


## where the strip is at t: {"lt": the source's own time, "k": cycle, "w": weight} or {} = no effect
static func at(c: Dictionary, L: float, t: float) -> Dictionary:
	var s0 := float(c["start"])
	var r := int(c["repeat"])
	var v := float(c["speed"])
	var E := s0 + L * r / v
	var bi := float(c["bin"])
	var bo := float(c["bout"])
	var inf := float(c["w"])
	var mt: Dictionary = c.get("match", {})   # ROADMAP 84: a matched clip starts at lt0 and loops (see the header)
	var lt0 := float(mt["lt0"]) if not mt.is_empty() else 0.0
	if t < s0:
		if c["extra"] != "hold":
			return {}
		return {"lt": lt0, "k": 0, "w": inf * (0.0 if bi > 0.0 else 1.0)}
	if t > E:
		if c["extra"] == "nothing":
			return {}
		if not mt.is_empty():   # the loop's last frame: the same place lt0 on the cycle after the last
			return {"lt": lt0, "k": r, "w": inf * (0.0 if bo > 0.0 else 1.0)}
		return {"lt": L, "k": r - 1, "w": inf * (0.0 if bo > 0.0 else 1.0)}
	var u := (t - s0) * v
	var wk := warp_norm(c.get("warp", []))
	if not wk.is_empty():
		u = warp_f(wk, clampf((t - s0) / (L * r / v), 0.0, 1.0)) * L * r   # the strip's progress through the curve
	var k: int
	var lt: float
	if mt.is_empty():
		k = mini(int(floor(u / L)), r - 1)
		lt = clampf(u - k * L, 0.0, L)
	else:
		u += lt0
		k = int(floor(u / L))
		lt = fposmod(u, L)
	var w := inf
	if bi > 0.0:
		w *= ramp(String(c.get("curve", "linear")), (t - s0) / bi)
	if bo > 0.0:
		w *= ramp(String(c.get("curve", "linear")), (E - t) / bo)
	return {"lt": lt, "k": k, "w": w}


# ---------------------------------------------------------------- playback

## Scene.apply's clip pass: every clip in list order over the body as the cards left it. No clip with weight: the body
## is not touched (byte for byte)
static func play(S: Scene, B: Body, t: float) -> void:
	_mu.lock()
	_play(S, B, t)
	_mu.unlock()


static func _play(S: Scene, B: Body, t: float) -> void:
	if _depth >= MAX_DEPTH:
		return
	var touched := false
	var arms := false
	for c in S.clips:
		if bool(c.get("mute", false)):
			continue
		var e := source(String(c["src"]))
		if e.is_empty():
			continue
		var a := at(c, float(e["len"]), t)
		if a.is_empty() or float(a["w"]) <= 0.0:
			continue
		var w := float(a["w"])
		var mirror := bool(c.get("mirror", false))
		var step := root_step(e, mirror) if int(a["k"]) > 0 or c["type"] == "add" else Vector3.ZERO
		var Q := _body(_depth)
		var o0 := Vector3.ZERO
		if c["type"] == "add" and mask_root(c["mask"]):
			o0 = (_pose_of(e, 0.0, mirror, Q) as Array)[1]
		var qp := _pose_of(e, float(a["lt"]), mirror, Q)
		var qa: Dictionary = qp[0]
		var off: Vector3 = (qp[1] as Vector3) + step * int(a["k"])
		var mt: Dictionary = c.get("match", {}) if c["type"] == "replace" else {}   # ROADMAP 84
		var cl := {}   # L79 SEAM CLOSURE: a source whose last pose misses its first by a hair (< CLOSE_TOL) is trimmed to close
		if int(a["k"]) < int(c["repeat"]) - 1 and mt.is_empty():
			cl = _closure(e, mirror, Q)
			if not cl.is_empty():
				off.y += float(cl["y"]) * float(a["lt"]) / float(e["len"])
		if not mt.is_empty() and mask_root(c["mask"]):
			off = align(off, mt)
		if bool(c.get("inplace", false)) and mask_root(c["mask"]):
			# W08 IN PLACE: the hips stay over the floor spot the source starts on (x and z); the height and every joint are the source's own
			var b0: Vector3 = (_pose_of(e, 0.0, mirror, Q) as Array)[1]
			if not mt.is_empty():
				b0 = align(b0, mt)
			off.x = b0.x
			off.z = b0.z
		for j in mask_joints(c["mask"]):
			if not B.ang.has(j) or not qa.has(j):
				continue
			var x: Vector3 = B.ang[j]
			var y: Vector3 = qa[j]
			if not cl.is_empty() and (cl["ang"] as Dictionary).has(j):
				y += (cl["ang"][j] as Vector3) * float(a["lt"]) / float(e["len"])
			if j == "pelvis" and not mt.is_empty():
				y.z += float(mt["yaw"])   # the walk turned as the match says
			var r := x + y * w if c["type"] == "add" else x + Scene._d(x, y, j) * w
			if j == "pelvis":
				r.z = wrapf(r.z, -180.0, 180.0)
			B.ang[j] = B.clamp_ang(j, r)
		if mask_root(c["mask"]):
			B.offset = B.offset + (off - o0) * w if c["type"] == "add" else B.offset.lerp(off, w)
		touched = true
		arms = arms or mask_arms(c["mask"])
	if touched:
		B.fk()
		if arms:
			B.apply_grip()   # a clip that moves the arms: the second hand back onto the weapon (a legs clip leaves the arms alone)


## L79 SEAM CLOSURE (repeat > 1): the source's pose at its end vs at its start. Cyclic sources close only to the solver's noise
## (the floor and the planted feet moved a calf 0.0044 deg between the first and last arrival of a three-card loop); that
## residual is a visible-never but measurable jump at every loop boundary. When every joint misses by under CLOSE_TOL deg
## (and the hips' height by under CLOSE_TOL_Y m), each cycle but the last is trimmed by residual x (lt / L), so the cycle ends
## exactly on the next cycle's first pose. A source that really is not a loop (a walk: degrees off) is left as it is.
## Returns {} (not closable / already closed) or {"ang": {joint: first - last}, "y": metres}
const CLOSE_TOL := 0.05
const CLOSE_TOL_Y := 0.002


static func _closure(e: Dictionary, mirror: bool, Q: Body) -> Dictionary:
	var cache: Dictionary = e.get("cl", {})
	if cache.has(mirror):
		return cache[mirror]
	var p0 := _pose_of(e, 0.0, mirror, Q)
	var d0: Dictionary = (p0[0] as Dictionary).duplicate()
	var o0: Vector3 = p0[1]
	var pL := _pose_of(e, float(e["len"]), mirror, Q)
	var out := {"ang": {}, "y": (o0.y - (pL[1] as Vector3).y)}
	var worst := 0.0
	for j in d0:
		if not (pL[0] as Dictionary).has(j):
			continue
		var d: Vector3 = (d0[j] as Vector3) - ((pL[0] as Dictionary)[j] as Vector3)
		worst = maxf(worst, d.length())
		out["ang"][j] = d
	if worst >= CLOSE_TOL or absf(float(out["y"])) >= CLOSE_TOL_Y or worst + absf(float(out["y"])) == 0.0:
		out = {}
	cache[mirror] = out
	e["cl"] = cache
	return out


## a clip's words for the timeline and the status line
static func label(c: Dictionary) -> String:
	var s := String(c["src"]).get_file().get_basename()
	if int(c["repeat"]) > 1:
		s += " x%d" % int(c["repeat"])
	if absf(float(c["speed"]) - 1.0) > 1e-4:
		s += " @%sx" % str(snappedf(float(c["speed"]), 0.01))   # (Godot has no %g: the old format failed on any speed but 1)
	if c["mask"] != "all":
		s += " [%s]" % c["mask"]
	if c["type"] == "add":
		s += " +add"
	if bool(c.get("inplace", false)):
		s += " (in place)"
	if bool(c.get("mirror", false)):
		s += " (mirrored)"
	return s
