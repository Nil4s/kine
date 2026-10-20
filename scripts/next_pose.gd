## next_pose.gd - NEXT-POSE SUGGESTIONS (ROADMAP R27, Nick's idea). While a card is current, up to three poses that may
## come NEXT, from three sources, no network, no model. Read only: scenes/, moves/ and poses/ are read, never written; the
## only file this writes is its own index cache (user://next_pose_index.json, or a test's).
##   1 YOUR HABITS     every scene file is read as card -> next-card pairs. For the current pose the K = 12 nearest cards
##                     that have a next card (and are within MAXD of it) vote; their next poses are grouped (two next poses
##                     within CLUSTER deg are one pose) and the biggest group wins: "seen 7 times after a pose like this".
##   2 REAL MOTION     the frame database of scripts/motion_match.gd (MotionMatch.build, read only) is searched for the frame
##                     nearest the pose (joint angles; a still pose has no velocity for MotionMatch's own feature vector);
##                     the proposal is the pose of that clip about the current card's move time later.
##   3 MOVE PHASE      the card's name reads wind-up / contact / follow-through / recover / ready: the next phase is
##                     wind-up -> contact -> follow-through -> recover -> ready. The candidates are the pose library
##                     (poses/lib, poses, moves) and the cards of your scenes whose NAME matches that phase; the one nearest
##                     the current pose wins.
## DISTANCE between two poses = the mean over 20 key joints of the three angle differences (deg, wrapped), each joint
## weighted by sqrt(its mass in Balance.MASS): "big joints count more" without letting a thigh swamp a hand. 0 = identical.
## SCORE (0..1, for the ranking and the tooltip):
##   habit   share x confidence, share = the group's weight / all votes, confidence = 1 - exp(-count / 2)
##   motion  0.9 x (1 - cost / MOTION_MAXCOST), cost = distance / 10 deg (so cost 1.0 = 10 deg of mean joint error)
##   phase   0.6 - 0.4 x min(distance / PHASE_MAXD, 1)
## I10 YOUR TIMING (ROADMAP I10, "your moves learn you"): the same index also keeps every card's move and hold time, so a
## TRANSITION (card before -> card) is a row: the two poses and the seconds Nick gave it (only explicit moves; an automatic
## move is the app's guess, not his). usual() = the median move and hold of the T_K nearest transitions to a new card and the
## card before it, where "near" = the larger of the two pose distances (plus T_PHASE_PEN deg when both card names read a move
## phase and it differs) and the bar is T_MAXD deg; fewer than T_MIN transitions inside the bar = no answer (the app's own default).
## between() = the card Nick usually puts between pose A and pose C: triples (A', X, C') with A' within T_MAXD of A and C'
## within T_MAXD of C; X grouped like the habits; a group seen BETWEEN_MIN times or more is offered.
## The index (every card of every scene, as joint angles) is cached and brought up to date by modified time; update_file
## re-reads ONE scene (main calls it when a scene is saved).
class_name NextPose
extends RefCounted

const CACHE := "user://next_pose_index.json"
const KEYJ := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "clavicle_r", "upperarm_l", "lowerarm_l",
	"upperarm_r", "lowerarm_r", "hand_l", "hand_r", "thigh_l", "calf_l", "thigh_r", "calf_r", "foot_l", "foot_r"]
const K := 12            # nearest cards that vote
const MAXD := 22.0       # deg: a card further than this from the pose is not "a pose like this"
const CLUSTER := 6.0     # deg: two next poses closer than this are the same suggestion
const NOOP := 3.0        # deg: a suggestion this close to the current pose is a hold, not a next pose
const MOTION_MAXCOST := 1.6
const COST_DEG := 10.0   # deg of mean joint error per unit of motion cost
const PHASE_MAXD := 45.0
const LIB_DIRS := ["res://poses/lib", "res://poses", "res://moves"]
const MAX_N := 3
const T_MAXD := 10.0     # deg: a stored transition is "like this pair" inside this (both ends)
const T_K := 5           # nearest transitions whose median is "your usual"
const T_MIN := 2         # fewer than this many inside the bar: no guess
const T_PHASE_PEN := 3.0 # deg added to a transition whose move phase differs from the new card's
const BETWEEN_MIN := 3   # an in-between used this often is offered
const SRC_WORDS := {"habit": "your habits", "motion": "real motion", "phase": "the move phase", "between": "your in-betweens"}
## phases: name -> [words that read as it, the next phase, its label]
const PHASES := {
	"follow": [["follow"], "recover", "follow-through"],
	"recover": [["recover", "return", "reset", "back to"], "ready", "recover"],
	"contact": [["contact", "impact", "strike", "thrust", "hit"], "follow", "contact"],
	"windup": [["wind", "coil", "load", "anticip", "cock", "chamber"], "contact", "wind-up"],
	"ready": [["ready", "guard", "stance", "rest", "idle", "stand"], "windup", "ready"],
}
const PHASE_ORDER := ["follow", "recover", "contact", "windup", "ready"]
const LABEL_OF := {"follow": "follow-through", "recover": "recover", "contact": "contact", "windup": "wind-up", "ready": "ready"}

var dirs: Array = ["res://scenes/"]
var cache_path := CACHE
var files := {}          # path -> {"mt", "cards": [{"n", "mv", "hd", "a": PackedFloat32Array (3 per Body.ORDER joint), "o": Vector3}]}
var last_ms := 0.0       # how long the last suggest() took
var reparsed := 0        # scene files read by the last refresh()
var _oi := {}            # joint -> index in Body.ORDER
var _kidx := PackedInt32Array()
var _kw := PackedFloat32Array()
var _wsum := 0.0
var _cards: Array = []   # flat: {"f": path, "c": card}
var _nk := PackedFloat32Array()    # the key vector of every flat card
var _next := PackedInt32Array()    # the flat index of the next card in its file, or -1
var _prev := PackedInt32Array()    # the flat index of the card before in its file, or -1 (I10)
var _lib: Array = []     # the pose library: {"name", "path", "a", "o", "k"}
var _lib_done := false
var db: Dictionary = {}  # MotionMatch's database, or {}
var _mk := PackedFloat32Array()    # the key vector of every database frame
var loaded := false


func _init() -> void:
	for i in Body.ORDER.size():
		_oi[Body.ORDER[i]] = i
	_kw.resize(KEYJ.size())
	for i in KEYJ.size():
		_kidx.append(int(_oi[KEYJ[i]]))
		_kw[i] = sqrt(float(Balance.MASS.get(KEYJ[i], 1.5)))
		_wsum += _kw[i]


# ---- vectors ------------------------------------------------------------------------------------------------------

## a pose dictionary's joint angles, 3 per Body.ORDER joint (bend, side, twist)
static func full_of_pose(pose: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(Body.ORDER.size() * 3)
	var js: Dictionary = pose.get("joints", {})
	for i in Body.ORDER.size():
		var x: Variant = js.get(Body.ORDER[i])
		if x is Dictionary:
			out[i * 3] = float(x.get("bend", 0.0))
			out[i * 3 + 1] = float(x.get("side", 0.0))
			out[i * 3 + 2] = float(x.get("twist", 0.0))
	return out


static func full_of_body(B: Body) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(Body.ORDER.size() * 3)
	for i in Body.ORDER.size():
		var a: Vector3 = B.ang.get(Body.ORDER[i], Vector3.ZERO)
		out[i * 3] = a.x
		out[i * 3 + 1] = a.y
		out[i * 3 + 2] = a.z
	return out


func key_of(full: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_kidx.size() * 3)
	for i in _kidx.size():
		var s := _kidx[i] * 3
		out[i * 3] = full[s]
		out[i * 3 + 1] = full[s + 1]
		out[i * 3 + 2] = full[s + 2]
	return out


static func _wrap(d: float) -> float:
	d = absf(d)
	return 360.0 - d if d > 180.0 else d


## the pose distance (deg, see the header) between key vector a at offset ao and b at bo; stops (returns > limit) as soon as it is past limit
func kdist(a: PackedFloat32Array, ao: int, b: PackedFloat32Array, bo: int, limit := INF) -> float:
	var cap := limit * _wsum * 3.0
	var s := 0.0
	for j in _kw.size():
		var p := j * 3
		s += _kw[j] * (_wrap(a[ao + p] - b[bo + p]) + _wrap(a[ao + p + 1] - b[bo + p + 1]) + _wrap(a[ao + p + 2] - b[bo + p + 2]))
		if s > cap:
			return limit + 1.0
	return s / (_wsum * 3.0)


# ---- the index ----------------------------------------------------------------------------------------------------

## the cards of one scene file as index rows; [] when it has none (a move, a pose, a plan)
static func read_file(path: String) -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out := []
	if not (d is Dictionary):
		return out
	for c in (d as Dictionary).get("cards", []):
		if not (c is Dictionary) or not (c.get("pose") is Dictionary) or not ((c["pose"] as Dictionary).get("joints") is Dictionary):
			continue
		var o: Array = c["pose"].get("offset", [0, 0, 0])
		out.append({"n": String(c.get("name", "")), "mv": float(c.get("move", -1.0)), "hd": float(c.get("hold", 0.3)),
			"a": full_of_pose(c["pose"]), "o": Vector3(float(o[0]), float(o[1]), float(o[2]))})
	return out


## load the cache, read the scene files that are new or changed (by modified time), forget the ones that are gone, write the
## cache back when anything changed. Returns how many files were read
func refresh() -> int:
	if not loaded:
		_load_cache()
	var seen := {}
	var n := 0
	for dir in dirs:
		for fn in DirAccess.get_files_at(dir):
			if not fn.ends_with(".json"):
				continue
			var path: String = String(dir) + fn
			seen[path] = true
			var mt := int(FileAccess.get_modified_time(path))
			if files.has(path) and int(files[path]["mt"]) == mt:
				continue
			files[path] = {"mt": mt, "cards": read_file(path)}
			n += 1
	for path in files.keys():
		if not seen.has(path) and _in_dirs(path):
			files.erase(path)
			n += 1
	reparsed = n
	_flatten()
	if n > 0:
		_save_cache()
	return n


func _in_dirs(path: String) -> bool:
	for dir in dirs:
		if path.begins_with(String(dir)) and not path.substr(String(dir).length()).contains("/"):
			return true
	return false


## a scene was saved: read that one file again (main calls this from its save)
func update_file(path: String) -> void:
	if not loaded:
		_load_cache()
	if not FileAccess.file_exists(path):
		return
	files[path] = {"mt": int(FileAccess.get_modified_time(path)), "cards": read_file(path)}
	reparsed = 1
	_flatten()
	_save_cache()


func _load_cache() -> void:
	loaded = true
	files = {}
	if not FileAccess.file_exists(cache_path):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
	if not (d is Dictionary) or int((d as Dictionary).get("joints", 0)) != Body.ORDER.size():
		return   # an index from another skeleton is read again
	for path in (d as Dictionary).get("files", {}):
		var e: Dictionary = d["files"][path]
		var cs := []
		for c in e.get("cards", []):
			var a := PackedFloat32Array()
			a.append_array(c["a"])
			var o: Array = c["o"]
			cs.append({"n": String(c["n"]), "mv": float(c["mv"]), "hd": float(c["hd"]), "a": a, "o": Vector3(o[0], o[1], o[2])})
		files[path] = {"mt": int(e.get("mt", 0)), "cards": cs}


func _save_cache() -> void:
	var fs := {}
	for path in files:
		var cs := []
		for c in files[path]["cards"]:
			var a := []
			for v in (c["a"] as PackedFloat32Array):
				a.append(snappedf(v, 0.1))
			var o: Vector3 = c["o"]
			cs.append({"n": c["n"], "mv": c["mv"], "hd": c["hd"], "a": a, "o": [snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(o.z, 0.001)]})
		fs[path] = {"mt": files[path]["mt"], "cards": cs}
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"joints": Body.ORDER.size(), "files": fs}))


func _flatten() -> void:
	_cards = []
	_nk = PackedFloat32Array()
	_next = PackedInt32Array()
	_prev = PackedInt32Array()
	var paths := files.keys()
	paths.sort()
	for path in paths:
		var cs: Array = files[path]["cards"]
		for i in cs.size():
			_cards.append({"f": path, "c": cs[i]})
			_nk.append_array(key_of(cs[i]["a"]))
			_next.append(_cards.size() if i + 1 < cs.size() else -1)
			_prev.append(_cards.size() - 2 if i > 0 else -1)


func card_count() -> int:
	return _cards.size()


func pair_count() -> int:
	var n := 0
	for v in _next:
		if v >= 0:
			n += 1
	return n


# ---- source 1: your habits ------------------------------------------------------------------------------------------

## [{"full", "off", "n", "mv", "hd", "count", "score", "src": "habit", ...}] best first. qk = the current pose's key vector
func habits(qk: PackedFloat32Array, cur_off: Vector3, exclude := "") -> Array:
	var near: Array = []   # [d, flat index], ascending, at most K
	var NK := _kidx.size() * 3
	for ci in _cards.size():
		if _next[ci] < 0 or _cards[ci]["f"] == exclude:
			continue
		var lim := MAXD if near.size() < K else float((near[near.size() - 1] as Array)[0])
		var d := kdist(_nk, ci * NK, qk, 0, lim)
		if d > lim:
			continue
		var at := near.size()
		while at > 0 and float((near[at - 1] as Array)[0]) > d:
			at -= 1
		near.insert(at, [d, ci])
		if near.size() > K:
			near.pop_back()
	if near.is_empty():
		return []
	var groups: Array = []   # {"rep": flat index of the next card, "w", "count", "dsum", "src": flat index of the nearest source}
	var total := 0.0
	for nb in near:
		var ci: int = nb[1]
		var ni: int = _next[ci]
		var w := 1.0 / (1.0 + float(nb[0]) / 4.0)
		total += w
		var hit := -1
		for g in groups.size():
			if kdist(_nk, int(groups[g]["rep"]) * NK, _nk, ni * NK, CLUSTER) <= CLUSTER:
				hit = g
				break
		if hit < 0:
			groups.append({"rep": ni, "w": w, "count": 1, "dsum": float(nb[0]), "src": ci})
		else:
			groups[hit]["w"] += w
			groups[hit]["count"] += 1
			groups[hit]["dsum"] += float(nb[0])
	var out := []
	for g in groups:
		var ni: int = g["rep"]
		if kdist(_nk, ni * NK, qk, 0, NOOP) <= NOOP:
			continue   # the next pose is the pose it follows: a hold
		var cnt: int = g["count"]
		var share: float = float(g["w"]) / total
		var nc: Dictionary = _cards[ni]["c"]
		var sc: Dictionary = _cards[int(g["src"])]["c"]
		var dx: Vector3 = Vector3((nc["o"] as Vector3).x - (sc["o"] as Vector3).x, 0.0, (nc["o"] as Vector3).z - (sc["o"] as Vector3).z)
		if dx.length() > 1.5:
			dx = Vector3.ZERO
		var mean_d: float = float(g["dsum"]) / cnt
		out.append({"src": "habit", "label": "your usual next", "score": share * (1.0 - exp(-cnt / 2.0)), "count": cnt,
			"full": nc["a"], "off": Vector3(cur_off.x + dx.x, (nc["o"] as Vector3).y, cur_off.z + dx.z), "name": nc["n"],
			"mv": nc["mv"], "hd": nc["hd"], "dist": mean_d, "from": String(_cards[ni]["f"]).get_file().get_basename(),
			"tip": "seen %d time%s after a pose like this (%d of the %d nearest cards; they differ by %.0f deg on average): '%s' in %s" % [
				cnt, "" if cnt == 1 else "s", cnt, near.size(), mean_d, nc["n"], String(_cards[ni]["f"]).get_file().get_basename()]})
	out.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	return out


# ---- source 2: real motion ------------------------------------------------------------------------------------------

## the database from MotionMatch.build, and the key vector of each of its frames (the slow part: do it off the main thread)
static func motion_bank(np: NextPose, database: Dictionary) -> PackedFloat32Array:
	var ang: PackedVector3Array = database.get("ang", PackedVector3Array())
	var J: int = Body.ORDER.size()
	var n: int = int(database.get("n", 0))
	var out := PackedFloat32Array()
	out.resize(n * np._kidx.size() * 3)
	var NK: int = np._kidx.size() * 3
	for g in n:
		for i in np._kidx.size():
			var v: Vector3 = ang[g * J + np._kidx[i]]
			var o := g * NK + i * 3
			out[o] = v.x
			out[o + 1] = v.y
			out[o + 2] = v.z
	return out


func set_motion(database: Dictionary, bank: PackedFloat32Array = PackedFloat32Array()) -> void:
	db = database
	_mk = bank if not bank.is_empty() else motion_bank(self, database)


func has_motion() -> bool:
	return int(db.get("n", 0)) > 0


## the proposal from the clip frame nearest the pose, dt seconds on. exclude = the open scene's file (its own next card is not "real motion")
func motion(qk: PackedFloat32Array, cur_off: Vector3, dt: float, exclude := "") -> Array:
	if not has_motion():
		return []
	var NK := _kidx.size() * 3
	var n: int = db["n"]
	var clip_of: PackedInt32Array = db["clip_of"]
	var infos: Array = db["clips"]
	var best := COST_DEG * MOTION_MAXCOST
	var bg := -1
	for g in n:
		var d := kdist(_mk, g * NK, qk, 0, best)
		if d < best and String((infos[clip_of[g]] as Dictionary)["path"]) != exclude:
			best = d
			bg = g
	if bg < 0:
		return []
	var info: Dictionary = infos[clip_of[bg]]
	var first: int = info["first"]
	var fr: int = bg - first
	var fps: float = info["fps"]
	var to: int = mini(fr + int(roundf(maxf(dt, 0.05) * fps)), int(info["n"]) - 1)
	if to <= fr:
		return []
	var gt := first + to
	if kdist(_mk, gt * NK, qk, 0, NOOP) <= NOOP:
		return []
	var J: int = Body.ORDER.size()
	var ang: PackedVector3Array = db["ang"]
	var full := PackedFloat32Array()
	full.resize(J * 3)
	for i in J:
		var v: Vector3 = ang[gt * J + i]
		full[i * 3] = v.x
		full[i * 3 + 1] = v.y
		full[i * 3 + 2] = v.z
	var offs: PackedVector3Array = db["off"]
	var cost := best / COST_DEG
	var secs := float(to - fr) / fps
	return [{"src": "motion", "label": "from real motion", "score": 0.9 * (1.0 - cost / MOTION_MAXCOST), "cost": cost, "full": full,
		"off": Vector3(cur_off.x, offs[gt].y, cur_off.z), "name": "%s +%.1fs" % [info["name"], secs], "mv": secs, "hd": 0.0, "dist": best,
		"from": String(info["name"]),
		"tip": "real clip '%s' %.1f s later, cost %.1f (the nearest frame is %.0f deg away on average)" % [info["name"], secs, cost, best]}]


# ---- source 3: move phase ---------------------------------------------------------------------------------------------

## "windup" ... "ready" for a card's name, or "" when it names no phase
static func phase_of(card_name: String) -> String:
	var nm := card_name.to_lower()
	for ph in PHASE_ORDER:
		for w in PHASES[ph][0]:
			if nm.contains(String(w)):
				return ph
	return ""


func _ensure_lib() -> void:
	if _lib_done:
		return
	_lib_done = true
	_lib = []
	for dir in LIB_DIRS:
		for fn in DirAccess.get_files_at(dir):
			if not fn.ends_with(".json"):
				continue
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(dir) + "/" + fn))
			if not (d is Dictionary) or not ((d as Dictionary).get("joints") is Dictionary) or (d as Dictionary).has("cards"):
				continue
			var a := full_of_pose(d)
			var o: Array = d.get("offset", [0, 0, 0])
			_lib.append({"name": fn.get_basename().replace("_", " "), "path": String(dir) + "/" + fn, "a": a,
				"o": Vector3(float(o[0]), float(o[1]), float(o[2])), "k": key_of(a)})


func phase(qk: PackedFloat32Array, cur_off: Vector3, card_name: String, exclude := "", phase_hint := "") -> Array:
	var ph := phase_hint if phase_hint != "" else phase_of(card_name)
	if ph == "" or not PHASES.has(ph):
		return []
	_ensure_lib()
	var nxt: String = PHASES[ph][1]
	var words: Array = PHASES[nxt][0]
	var NK := _kidx.size() * 3
	var best := PHASE_MAXD
	var pick: Dictionary = {}
	for e in _lib:
		if _name_has(String(e["name"]), words):
			var d := kdist(e["k"], 0, qk, 0, best)
			if d < best and kdist(e["k"], 0, qk, 0, NOOP) > NOOP:
				best = d
				pick = {"name": e["name"], "a": e["a"], "o": e["o"], "mv": -1.0, "hd": 0.3, "from": "the pose library: " + String(e["path"]).get_file().get_basename()}
	for ci in _cards.size():
		var c: Dictionary = _cards[ci]["c"]
		if _cards[ci]["f"] == exclude or not _name_has(String(c["n"]), words):
			continue
		var d := kdist(_nk, ci * NK, qk, 0, best)
		if d < best and kdist(_nk, ci * NK, qk, 0, NOOP) > NOOP:
			best = d
			pick = {"name": c["n"], "a": c["a"], "o": c["o"], "mv": c["mv"], "hd": c["hd"], "from": "'%s' in %s" % [c["n"], String(_cards[ci]["f"]).get_file().get_basename()]}
	if pick.is_empty():
		return []
	var o: Vector3 = pick["o"]
	return [{"src": "phase", "label": LABEL_OF[nxt], "score": 0.6 - 0.4 * minf(best / PHASE_MAXD, 1.0), "full": pick["a"],
		"off": Vector3(cur_off.x, o.y, cur_off.z), "name": pick["name"], "mv": pick["mv"], "hd": pick["hd"], "dist": best, "from": pick["from"],
		"tip": "move phase: '%s' reads as %s, so %s comes next; the nearest %s to this pose is %s (%.0f deg away)" % [
			card_name, LABEL_OF[ph], LABEL_OF[nxt], LABEL_OF[nxt], pick["from"], best]}]


static func _name_has(nm: String, words: Array) -> bool:
	var l := nm.to_lower()
	for w in words:
		if l.contains(String(w)):
			return true
	return false


# ---- I10: your timing and your in-betweens -------------------------------------------------------------------------------

static func _median(v: Array) -> float:
	v.sort()
	var n := v.size()
	return float(v[n / 2]) if n % 2 == 1 else 0.5 * (float(v[n / 2 - 1]) + float(v[n / 2]))


## "your usual" for a card newly put after prev: {"mv", "hd", "n", "dist"} or {} (no transition near enough, or fewer than T_MIN)
func usual(prev: Dictionary, cur: Dictionary, card_name := "") -> Dictionary:
	if not loaded:
		refresh()
	var NK := _kidx.size() * 3
	var pk := key_of(full_of_pose(prev))
	var ck := key_of(full_of_pose(cur))
	var ph := phase_of(card_name)
	var near: Array = []   # [d, flat index], ascending, at most T_K
	for ci in _cards.size():
		var pi: int = _prev[ci]
		if pi < 0 or float(_cards[ci]["c"]["mv"]) <= 0.0:
			continue
		var pen := 0.0
		var cph := phase_of(String(_cards[ci]["c"]["n"]))
		if ph != "" and cph != "" and ph != cph:
			pen = T_PHASE_PEN
		var lim := T_MAXD - pen
		var d1 := kdist(_nk, pi * NK, pk, 0, lim)
		if d1 > lim:
			continue
		var d2 := kdist(_nk, ci * NK, ck, 0, lim)
		if d2 > lim:
			continue
		var d := maxf(d1, d2) + pen
		var at := near.size()
		while at > 0 and float((near[at - 1] as Array)[0]) > d:
			at -= 1
		near.insert(at, [d, ci])
		if near.size() > T_K:
			near.pop_back()
	if near.size() < T_MIN:
		return {}
	var mvs := []
	var hds := []
	var dsum := 0.0
	for nb in near:
		var c: Dictionary = _cards[int(nb[1])]["c"]
		mvs.append(float(c["mv"]))
		hds.append(float(c["hd"]))
		dsum += float(nb[0])
	return {"mv": snappedf(_median(mvs), 0.001), "hd": snappedf(_median(hds), 0.001), "n": near.size(), "dist": dsum / near.size()}


## the in-between Nick usually puts between pose a and pose c: [{"src": "between", "label": "your usual in-between", ...}] best first
func between(a: Dictionary, c: Dictionary, cur_off: Vector3, exclude := "") -> Array:
	if not loaded:
		refresh()
	var NK := _kidx.size() * 3
	var ak := key_of(full_of_pose(a))
	var ck := key_of(full_of_pose(c))
	var groups: Array = []   # {"rep": flat index of X, "idx": [flat indices]}
	var total := 0
	for xi in _cards.size():
		var pi: int = _prev[xi]
		var ni: int = _next[xi]
		if pi < 0 or ni < 0 or _cards[xi]["f"] == exclude:
			continue
		if kdist(_nk, pi * NK, ak, 0, T_MAXD) > T_MAXD or kdist(_nk, ni * NK, ck, 0, T_MAXD) > T_MAXD:
			continue
		if kdist(_nk, xi * NK, ak, 0, NOOP) <= NOOP or kdist(_nk, xi * NK, ck, 0, NOOP) <= NOOP:
			continue   # X is A or C again: a hold, not an in-between
		total += 1
		var hit := -1
		for g in groups.size():
			if kdist(_nk, int(groups[g]["rep"]) * NK, _nk, xi * NK, CLUSTER) <= CLUSTER:
				hit = g
				break
		if hit < 0:
			groups.append({"rep": xi, "idx": [xi]})
		else:
			groups[hit]["idx"].append(xi)
	var out := []
	for g in groups:
		var cnt: int = (g["idx"] as Array).size()
		if cnt < BETWEEN_MIN:
			continue
		var mvs := []
		var hds := []
		for xi in g["idx"]:
			var xc: Dictionary = _cards[int(xi)]["c"]
			if float(xc["mv"]) > 0.0:
				mvs.append(float(xc["mv"]))
			hds.append(float(xc["hd"]))
		var rc: Dictionary = _cards[int(g["rep"])]["c"]
		var rf := String(_cards[int(g["rep"])]["f"]).get_file().get_basename()
		var share := float(cnt) / float(total)
		out.append({"src": "between", "label": "your usual in-between", "score": minf(1.0, 0.25 + share * (1.0 - exp(-cnt / 2.0))), "count": cnt,
			"full": rc["a"], "off": Vector3(cur_off.x, (rc["o"] as Vector3).y, cur_off.z), "name": rc["n"],
			"mv": snappedf(_median(mvs), 0.001) if not mvs.is_empty() else -1.0, "hd": snappedf(_median(hds), 0.001), "dist": 0.0, "from": rf,
			"tip": "your usual in-between: %d time%s you put a pose like this between a pose like the current card and the next one (of %d such pairs), e.g. '%s' in %s" % [
				cnt, "" if cnt == 1 else "s", total, rc["n"], rf]})
	out.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	return out


# ---- all three ---------------------------------------------------------------------------------------------------------

## up to MAX_N suggestions, best score first, near-duplicates (within CLUSTER deg) kept once.
## cur = the current card's pose dictionary; dt = the current card's move time (s); exclude = the open scene's file
func suggest(cur: Dictionary, card_name: String, dt: float, exclude := "", hint := "", nxt := {}) -> Array:
	var t0 := Time.get_ticks_usec()
	if not loaded:
		refresh()
	var qf := full_of_pose(cur)
	var qk := key_of(qf)
	var o: Array = cur.get("offset", [0, 0, 0])
	var off := Vector3(float(o[0]), float(o[1]), float(o[2]))
	var all: Array = habits(qk, off, exclude)
	if not nxt.is_empty():
		all.append_array(between(cur, nxt, off, exclude))   # I10: only when the card has a card after it
	all.append_array(motion(qk, off, dt, exclude))
	all.append_array(phase(qk, off, card_name, exclude, hint))
	all.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var out: Array = []
	for s in all:
		var sk := key_of(s["full"])
		var dup := false
		for t in out:
			if kdist(sk, 0, key_of(t["full"]), 0, CLUSTER) <= CLUSTER:
				dup = true   # the same pose from a second source: one ghost, and it says so
				t["also"] = t.get("also", []) + [s["src"]]
				t["tip"] = String(t["tip"]) + ".  Also proposed by %s: %s" % [SRC_WORDS[s["src"]], s["tip"]]
				break
		if not dup and out.size() < MAX_N:
			out.append(s)
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return out
