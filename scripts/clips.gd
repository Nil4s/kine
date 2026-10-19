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
## Each source is played by its own Scene.apply on a scratch body (floor, pins, its own layers and IK included), so a
## clip at weight 1, mask all, plays the source exactly as opening the file would. The weapon stays the cards'.
class_name Clips
extends RefCounted

const TYPES := ["replace", "add"]
const EXTRA := ["nothing", "hold", "hold_forward"]
const MASK_NAMES := ["all", "legs", "upper", "arms", "arm_l", "arm_r"]
const MAX_DEPTH := 3   # a source that places clips of its own plays them too, this deep at most (a loop stops here)

static var _cache := {}    # src path -> {"mt": modified time, "scene": Scene, "len": s, "d": {mirror: root step}}
static var _bodies := []   # scratch bodies, one per depth (a source's own clips use the next)
static var _depth := 0


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


## the hips' step one cycle makes over the floor: offset(L) - offset(0), y dropped
static func root_step(e: Dictionary, mirror: bool) -> Vector3:
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
	if t < s0:
		if c["extra"] != "hold":
			return {}
		return {"lt": 0.0, "k": 0, "w": inf * (0.0 if bi > 0.0 else 1.0)}
	if t > E:
		if c["extra"] == "nothing":
			return {}
		return {"lt": L, "k": r - 1, "w": inf * (0.0 if bo > 0.0 else 1.0)}
	var u := (t - s0) * v
	var k := mini(int(floor(u / L)), r - 1)
	var lt := clampf(u - k * L, 0.0, L)
	var w := inf
	if bi > 0.0:
		w *= clampf((t - s0) / bi, 0.0, 1.0)
	if bo > 0.0:
		w *= clampf((E - t) / bo, 0.0, 1.0)
	return {"lt": lt, "k": k, "w": w}


# ---------------------------------------------------------------- playback

## Scene.apply's clip pass: every clip in list order over the body as the cards left it. No clip with weight: the body
## is not touched (byte for byte)
static func play(S: Scene, B: Body, t: float) -> void:
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
			_pose_src(e, 0.0, mirror, Q)
			o0 = Q.offset
		_pose_src(e, float(a["lt"]), mirror, Q)
		var off := Q.offset + step * int(a["k"])
		for j in mask_joints(c["mask"]):
			if not B.ang.has(j) or not Q.ang.has(j):
				continue
			var x: Vector3 = B.ang[j]
			var y: Vector3 = Q.ang[j]
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


## a clip's words for the timeline and the status line
static func label(c: Dictionary) -> String:
	var s := String(c["src"]).get_file().get_basename()
	if int(c["repeat"]) > 1:
		s += " x%d" % int(c["repeat"])
	if absf(float(c["speed"]) - 1.0) > 1e-4:
		s += " @%.2gx" % float(c["speed"])
	if c["mask"] != "all":
		s += " [%s]" % c["mask"]
	if c["type"] == "add":
		s += " +add"
	if bool(c.get("mirror", false)):
		s += " (mirrored)"
	return s
