## event_query.gd - N017 EVENT QUERY (docs/INNOVATIONS.md). A blind agent asks "when does the right foot leave the floor /
## when is the guard down / when is he off balance / when is the right fist fastest / when do the fighters touch" and gets
## the TIMES (spans or instants, in s and in frames) measured on the BODY over the sampled clip, never read off the keys:
## the scene is played (Scene.apply: cards, IK, plants, layers, what PLAYS) at every frame and each predicate is a number of
## that played body.
##
## THE GRAMMAR (small and fixed; an unknown phrase gets the KNOWN list back, never a guess):
##   query   := expr  |  instant ["while" expr]
##   expr    := term {"or" term} ["for at least" N ("s" | "ms" | "frames")]   (the duration applies to the whole expr at
##                                                                            its bracket level: use ( ) to bind it tighter)
##   term    := factor {"and" factor}
##   factor  := "not" factor | "(" expr ")" | predicate     (a "not" inside a phrase, "right foot not on the floor", also negates)
##   instant := "<part> fastest | slowest | highest | lowest | most bent | straightest", "<part> closest to | farthest from
##              <part>", "fighters closest | farthest", "most off balance"
## PREDICATES (per frame; each answer carries its rule and trust label, N020):
##   <foot> down / up        foot on the floor = balance.gd's footprint: a point of its foot or ball capsule within Balance.TOUCH
##                           (1 cm) of the floor (the same test the support polygon is built from, so "off balance" and "foot
##                           down" can never disagree). "leaves the floor" = the first frame of an UP span, "plants" = of a DOWN one
##   airborne / both feet down / single support
##   off balance             balance.gd per frame: a foot down and the COM's floor point past the support polygon by more than
##                           Balance.MARGIN_RES (2 cm, the model's resolution; the margin human_limits TIPPING uses). With no foot
##                           down he is airborne, not off balance (no polygon to be outside of)
##   guard down / up, <hand> down / up    the wrist (Body.P hand_x) against the chin: chin = the top of the head minus
##                           StylePrint.CHIN_BELOW_TOP (0.23 m, Winter 2009 Table 4.1, menton-vertex 0.130 x stature). A hand
##                           is DOWN when its wrist is more than GUARD_DROP under the chin. "guard down" = BOTH hands down
##   <part> faster / slower than N m/s   central difference over one frame either side (the formula `measure speed` uses)
##   <part> above / below N m | <part> above / below <part>     heights (y up, the floor is 0)
##   <part> within / farther than N m of <part>    3-D distance between the two points
##   <elbow|knee> angle above / below N, <elbow|knee> bent more / less than N   the interior angle at the joint (180 =
##                           straight; shoulder-elbow-wrist, hip-knee-ankle); "bent" = 180 - that
##   fighters touch          Body.cross_contacts between fighter 1 and 2 (any capsule, weapons included, in by > 1 mm)
##   fighters within / farther than N m    the smallest capsule-to-capsule gap between the two bodies
## PARTS: right / left + foot (ankle), heel (= the ankle), toe / ball, hand / fist / wrist, elbow, knee, hip, shoulder; head,
## head top, chin, pelvis / hips, chest, com (centre of mass), weapon tip / knob; a Body joint name (hand_r). "other" /
## "opponent" / "fighter N" before a part reads that fighter (positions are all in fighter 1's space).
##
## SAMPLING: frames 0..floor(L * fps) at the scene's fps (or the fps asked), t = frame / fps. Scene.apply costs 5-36 ms a
## frame (measured: combo3 7 ms, walk 36 ms, this machine), so a 4 s clip at 60 fps is 1.7-8.6 s of solving done one frame
## after another. The frames are split over WorkerThreadPool tasks, each on a CLONE of the scene and a body of its own (the
## way PoseBake bakes: its test shows a clone's pose is bit for bit the live one); a scene PoseBake cannot clone (constraints
## that read another fighter, clips) is sampled on the main thread. The sampled clip is kept (CACHE, keyed by each scene's
## PoseBake.signature + placement + fps), so the next question on the same clip is the predicate pass alone.
class_name EventQuery
extends RefCounted

const GUARD_DROP := 0.10   # m. HEURISTIC: a guard hand's wrist sits a little under the chin (the fist above it); 10 cm under it is down
const CACHE_MAX := 4
const CHUNKS := 16   # tasks: measured on combo3 at 60 fps (281 frames, 20 cores): 1 -> 1.6 s, 4 -> 0.52, 16 -> 0.50 (shared-state contention caps it near 3x)
## the stored points per fighter per frame, in this order: the body's joints, then these
const EXTRA := ["head_top", "chin", "com", "weapon_tip", "weapon_knob"]
const SIDED := {"foot": "foot", "ankle": "foot", "heel": "foot", "toe": "ball", "toes": "ball", "ball": "ball",
	"hand": "hand", "fist": "hand", "wrist": "hand", "elbow": "lowerarm", "forearm": "lowerarm", "knee": "calf", "shin": "calf",
	"hip": "thigh", "thigh": "thigh", "shoulder": "upperarm", "arm": "upperarm", "collarbone": "clavicle", "clavicle": "clavicle"}
const SINGLE := {"head": "head", "chin": "chin", "pelvis": "pelvis", "hips": "pelvis", "waist": "pelvis", "chest": "spine_03",
	"neck": "neck_01", "com": "com"}
const ANGLE := {"lowerarm": ["upperarm", "lowerarm", "hand"], "calf": ["thigh", "calf", "foot"]}
const FILLER := ["when", "what", "which", "does", "do", "did", "is", "are", "was", "the", "his", "her", "he", "she", "they",
	"it", "its", "a", "an", "times", "time", "frames", "frame", "has", "have", "him", "get", "gets", "goes", "go", "being"]

## the phrases this understands (the answer to any phrase it does not)
const KNOWN := [
	"<foot> down | on the floor | planted | plants | lands      e.g. \"right foot plants\"",
	"<foot> up | off the floor | leaves the floor | in the air  e.g. \"when does the left foot leave the floor\"",
	"airborne | both feet down | single support",
	"off balance | balanced                                     (balance.gd: COM past the feet by > 2 cm, a foot down)",
	"guard down | guard up | <hand> down | <hand> up            (wrist vs chin, 10 cm HEURISTIC)",
	"<part> faster than N m/s | slower than N m/s",
	"<part> above | below N m      <part> above | below <part>  e.g. \"right hand above head\"",
	"<part> within N m of <part> | farther than N m from <part>",
	"<elbow|knee> angle above | below N   <elbow|knee> bent more | less than N   (degrees)",
	"fighters touch | fighters within N m | fighters farther than N m   (two fighters)",
	"INSTANTS: <part> fastest | slowest | highest | lowest | most bent | straightest; <part> closest to | farthest from <part>; fighters closest | farthest; most off balance   (add \"while <expr>\")",
	"COMBINE: and, or, not, ( ), \"for at least N s\" (or ms / frames)",
	"PARTS: right/left foot, heel, toe, hand, fist, wrist, elbow, knee, hip, shoulder; head, head top, chin, pelvis, chest, com, weapon tip/knob, a joint name (hand_r); \"other\" / \"opponent\" / \"fighter N\" before a part = that fighter"]

static var _cache := {}
static var _cache_order: Array = []
static var _rx: Array = []


static func point_names() -> Array:
	var a: Array = Body.BODY.duplicate()
	a.append_array(EXTRA)
	return a


# ---------------------------------------------------------------- sampling

## the points of one fighter now, in point_names() order, in the hero's space (xf)
static func _points(B: Body, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for j in Body.BODY:
		out.append(xf * (B.P[j] as Vector3))
	var top: Vector3 = B.E["head"]
	out.append(xf * top)
	var hd: Vector3 = B.P["head"]
	out.append(xf * Vector3(hd.x, top.y - StylePrint.CHIN_BELOW_TOP, hd.z))
	out.append(xf * Balance.com(B))
	var nan := Vector3(NAN, NAN, NAN)
	out.append(xf * B.wep_point(B.wep_len) if B.wep_on else nan)
	out.append(xf * B.wep_point(0.0) if B.wep_on else nan)
	return out


## is this foot on the floor: balance.gd's footprint test exactly (Balance.footprint: any of the 9 points along the foot or
## ball capsule's axis whose underside is within Balance.TOUCH of the floor, or of the top it stands on), without building the
## footprint's ring of points (Balance.read costs ~2 ms a frame, measured: a third of a frame's sampling)
static func foot_down(B: Body, side: String) -> bool:
	for part in Balance.FEET[side]:
		var c: Array = B.cap(part)
		var r: float = B.rad[part]
		for k in 9:
			var p: Vector3 = (c[0] as Vector3).lerp(c[1], k / 8.0)
			if p.y - r - (0.0 if B.props.is_empty() else B.surface_at(p, r)) <= Balance.TOUCH:
				return true
	return false


## one frame of every fighter (already posed): [pts per fighter, margin per fighter (NAN unless needs.bal), down bits per
## fighter, touch, gap]
static func _read(bodies: Array, xfs: Array, needs: Dictionary) -> Array:
	var pts := []
	var mg := []
	var dn := []
	for k in bodies.size():
		var B: Body = bodies[k]
		pts.append(_points(B, xfs[k]))
		if needs.get("bal", false):
			var b := Balance.read(B)
			mg.append(float(b["margin"]))
			dn.append((1 if "_l" in b["down"] else 0) | (2 if "_r" in b["down"] else 0))
		else:
			mg.append(NAN)
			dn.append((1 if foot_down(B, "_l") else 0) | (2 if foot_down(B, "_r") else 0))
	var touch := false
	var gap := INF
	if needs.get("cross", false) and bodies.size() >= 2:
		var A: Body = bodies[0]
		var O: Body = bodies[1]
		var rel: Transform3D = (xfs[0] as Transform3D).affine_inverse() * (xfs[1] as Transform3D)
		touch = not A.cross_contacts(O, rel).is_empty()
		var ca: Array = A.cross_caps()
		var cb: Array = O.cross_caps(rel)
		for p in ca:
			for q in cb:
				gap = minf(gap, Body.seg_seg(p[1], p[2], q[1], q[2]) - float(p[3]) - float(q[3]))
	return [pts, mg, dn, touch, gap]


static func _new_body() -> Body:
	var b := Body.new()
	b.load_files(PoseBake.SKEL, PoseBake.LIMS)
	b.fk()
	return b


## the clip: every frame of every fighter. fighters = [{"S": Scene (what plays), "B": Body (its live body), "xf": Transform3D,
## "name"}]; fighter 0's scene sets the length. serial = on the live scenes, one frame after another (the reference the test
## holds the parallel clip to; never cached). Bodies are left as they were. {"fps", "n", "L", "names", "pts": [k][f],
## "margin": [k][f], "down": [k][f], "touch": [f], "gap": [f], "sampled": "parallel" / "serial", "cached": bool, "ms"}
static func sample(fighters: Array, fps: float, needs := {"cross": true, "bal": true}, serial := false) -> Dictionary:
	var keep := FrameMemo.slice_ms   # a plain call never waits for a frame
	FrameMemo.slice_ms = 0.0
	var r: Dictionary = sample_co.call(fighters, fps, needs, serial)
	FrameMemo.slice_ms = keep
	return r


## sample() that, inside a time-sliced run (FrameMemo.slice_begin), leaves the main thread free while the worker threads play the frames,
## and plays a serial clip a slice at a time; {} = cancelled
static func sample_co(fighters: Array, fps: float, needs := {"cross": true, "bal": true}, serial := false) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var L: float = (fighters[0]["S"] as Scene).length()
	var n := int(floor(L * fps + 1e-6)) + 1
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	for f in fighters:
		hc.update(PoseBake.signature(f["S"]))
		hc.update(var_to_bytes([f["xf"], (f["S"] as Scene).actors.size()]))
	hc.update(var_to_bytes([fps, needs.get("cross", false), needs.get("bal", false), n]))
	var key := hc.finish().hex_encode()
	if _cache.has(key) and not serial:
		var c: Dictionary = _cache[key]
		c["cached"] = true
		c["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		return c
	var xfs := fighters.map(func(f): return f["xf"])
	var par := not serial and fighters.all(func(f): return PoseBake.eligible(f["S"])) and n >= 8
	var rows := []
	rows.resize(n)
	if par:
		var k := mini(CHUNKS, n)
		var outs := []
		var srcs := fighters.map(func(f): return f["S"])
		for c in k:
			outs.append({})
		var job := func(c: int) -> void:
			var bodies := []
			var clones := []
			for q in srcs.size():   # each task its own clone and body (the clone reads the scene: nothing writes it meanwhile)
				bodies.append(_new_body())
				var cl: Scene = (srcs[q] as Scene).clone()
				cl.baker = null
				clones.append(cl)
			var o: Dictionary = outs[c]
			var i := c
			while i < n:   # interleaved frames: every chunk gets an even share of the clip's hard and easy parts
				for q in bodies.size():
					(clones[q] as Scene).apply(bodies[q], float(i) / fps)
				o[i] = _read(bodies, xfs, needs)
				i += k
		var gid := WorkerThreadPool.add_group_task(job, k, -1, true, "EventQuery sample")
		if FrameMemo.slice_ms > 0.0:
			while not WorkerThreadPool.is_group_task_completed(gid):
				await (Engine.get_main_loop() as SceneTree).process_frame
		WorkerThreadPool.wait_for_group_task_completion(gid)
		if FrameMemo.slice_ms > 0.0 and FrameMemo.abort:
			return {}
		for o in outs:
			for i in o:
				rows[i] = o[i]
	else:
		var keep := fighters.map(func(f): return (f["B"] as Body).state())
		var bodies := fighters.map(func(f): return f["B"])
		for i in n:
			for q in bodies.size():
				(fighters[q]["S"] as Scene).apply(bodies[q], float(i) / fps)
			rows[i] = _read(bodies, xfs, needs)
			if FrameMemo.slice_ms > 0.0 and not await FrameMemo.pump(float(i) / float(n)):
				for q in bodies.size():
					(bodies[q] as Body).set_state(keep[q])
				return {}
		for q in bodies.size():
			(bodies[q] as Body).set_state(keep[q])
	var clip := {"fps": fps, "n": n, "L": L, "names": fighters.map(func(f): return String(f.get("name", ""))),
		"pts": [], "margin": [], "down": [], "touch": PackedByteArray(), "gap": PackedFloat32Array(),
		"sampled": "parallel" if par else "serial", "cached": false}
	for q in fighters.size():
		var pa := []
		var ma := PackedFloat32Array()
		var da := PackedByteArray()
		for i in n:
			pa.append(rows[i][0][q])
			ma.append(rows[i][1][q])
			da.append(rows[i][2][q])
		clip["pts"].append(pa)
		clip["margin"].append(ma)
		clip["down"].append(da)
	for i in n:
		clip["touch"].append(1 if rows[i][3] else 0)
		clip["gap"].append(rows[i][4])
	if not serial:
		_cache[key] = clip
		_cache_order.append(key)
		while _cache_order.size() > CACHE_MAX:
			_cache.erase(_cache_order.pop_front())
	clip["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return clip


static func clear_cache() -> void:
	_cache = {}
	_cache_order = []


# ---------------------------------------------------------------- parsing

static func _norm(q: String) -> PackedStringArray:
	var s := " " + q.to_lower().strip_edges() + " "
	for pr in [["’", "'"], ["centre of mass", "com"], ["center of mass", "com"], ["isn't", "is not"], ["doesn't", "does not"],
			["aren't", "are not"], ["don't", "do not"], ["n't", " not"], ["'s", ""], ["s'", "s"], ["?", " "], [",", " "], ["!", " "],
			["(", " ( "], [")", " ) "], ["°", " deg "], ["m/s", " m/s "], ["head top", "head_top"], ["top of head", "head_top"],
			["weapon tip", "weapon_tip"], ["blade tip", "weapon_tip"], ["tip of weapon", "weapon_tip"], ["weapon knob", "weapon_knob"],
			["the floor", "floor"], ["the ground", "ground"]]:
		s = s.replace(pr[0], pr[1])
	var out := PackedStringArray()
	for w in s.split(" ", false):
		if not w in FILLER:
			out.append(w)
	return out


## a number token (with its unit, if the next word is one): [value, unit, words used] or []
static func _number(ws: PackedStringArray, i: int) -> Array:
	var w := ws[i]
	var unit := ""
	for u in ["m/s", "cm", "mm", "ms", "deg", "m", "s"]:   # glued: "0.3m", "90deg", "200ms"
		if w.ends_with(u) and w.trim_suffix(u).is_valid_float():
			unit = u
			w = w.trim_suffix(u)
			break
	if not w.is_valid_float():
		return []
	var used := 1
	if unit == "" and i + 1 < ws.size():
		var nx := ws[i + 1]
		var units := {"m/s": "m/s", "mps": "m/s", "m": "m", "metre": "m", "metres": "m", "meter": "m", "meters": "m", "cm": "cm",
			"mm": "mm", "s": "s", "sec": "s", "secs": "s", "second": "s", "seconds": "s", "ms": "ms", "deg": "deg", "degree": "deg",
			"degrees": "deg", "frame": "frames", "frames": "frames"}
		if units.has(nx):
			unit = units[nx]
			used = 2
	return [float(w), unit, used]


## the tokens: words, with numbers as {"num", "unit"}
static func _tokens(q: String) -> Array:
	var ws := _norm(q)
	var out := []
	var i := 0
	while i < ws.size():
		var nb := _number(ws, i)
		if not nb.is_empty():
			out.append({"num": nb[0], "unit": nb[1]})
			i += int(nb[2])
		else:
			out.append(ws[i])
			i += 1
	return out


static func _err(msg: String, phrase := "") -> Dictionary:
	return {"ok": false, "error": msg, "unknown": phrase, "known": KNOWN}


## a phrase's words -> its skeleton ("@0 faster than #0") + the parts and numbers it names, or {"error"}
static func _skeleton(ws: Array) -> Dictionary:
	var sk := []
	var parts := []
	var nums := []
	var i := 0
	while i < ws.size():
		var w: Variant = ws[i]
		if w is Dictionary:
			sk.append("#%d" % nums.size())
			nums.append(w)
			i += 1
			continue
		var who: Variant = "self"
		var j := i
		if w in ["other", "opponent", "enemy", "defender"]:
			who = "other"
			j += 1
			if j < ws.size() and ws[j] is String and ws[j] in ["fighter", "one", "guy", "man"]:
				j += 1   # "the other fighter's head"
		elif w == "fighter" and j + 1 < ws.size() and ws[j + 1] is Dictionary:
			who = int(ws[j + 1]["num"]) - 1
			j += 2
		var side := ""
		if j < ws.size() and ws[j] is String and ws[j] in ["right", "left", "r", "l"]:
			side = "_r" if ws[j] in ["right", "r"] else "_l"
			j += 1
		var nw: Variant = ws[j] if j < ws.size() else null
		var pt := ""
		if nw is String:
			if SIDED.has(nw) and side != "":
				pt = SIDED[nw] + side
			elif SIDED.has(nw) and side == "":
				return {"error": "which %s, right or left? say \"right %s\" or \"left %s\"" % [nw, nw, nw]}
			elif side == "" and SINGLE.has(nw):
				pt = SINGLE[nw]
			elif side == "" and (nw in Body.BODY or nw in EXTRA):
				pt = nw
		if pt == "":
			if who is int or (who == "other" and side != ""):
				return {"error": "'%s' is not a part I know" % " ".join(ws.slice(i, j + 1).map(func(x): return str(x)))}
			if side != "":
				return {"error": "'%s %s' is not a part I know" % [ws[i], str(nw)]}
			if who == "other":   # "other" alone: a word, not a part
				sk.append(w)
				i += 1
				continue
			sk.append(w)
			i += 1
			continue
		sk.append("@%d" % parts.size())
		parts.append({"who": who, "pt": pt})
		i = j + 1
	return {"sk": " ".join(sk.map(func(x): return str(x))), "parts": parts, "nums": nums}


const SPAN_FORMS := [
	["^@0 (down|on floor|on ground|planted|plants|plant|lands|land|landing|touches down|touch down|grounded|drops|dropped|low|lowered)$", "down"],
	["^@0 (up|off floor|off ground|leaves floor|leave floor|leaves ground|leave ground|leaving floor|in air|lifted|lifts|lift|raised|off|high)$", "up"],
	["^(airborne|in air|both feet up|both feet off floor|both feet off ground|flight|jumping)$", "air"],
	["^(both feet down|both feet on floor|both feet on ground|double support)$", "both"],
	["^(single support|one foot down|on one foot|on one leg|standing on one leg|standing on one foot)$", "single"],
	["^(off balance|unbalanced|out of balance|losing balance|tipping)$", "offbal"],
	["^(balanced|on balance|in balance)$", "bal"],
	["^(guard down|guard dropped|guard drops|guard open|guard low|hands down|both hands down|drops guard|dropping guard|dropped guard)$", "gdown"],
	["^(guard up|hands up|both hands up|guarding|guard high|guard on)$", "gup"],
	["^@0 (faster than|speed above|speed over|speed more than|moving faster than|quicker than|speed >) #0$", "faster"],
	["^@0 (slower than|speed below|speed under|speed less than|moving slower than|speed <) #0$", "slower"],
	["^@0 (above|higher than|over|height above|height over|>) #0$", "higher"],
	["^@0 (below|lower than|under|height below|height under|<) #0$", "lower"],
	["^@0 (above|higher than|over) @1$", "above"],
	["^@0 (below|lower than|under) @1$", "below"],
	["^@0 (within|closer than|nearer than|less than) #0 (of|to|from) @1$", "near"],
	["^@0 (farther than|further than|more than) #0 (from|of|to) @1$", "far"],
	["^@0 angle (above|over|more than|greater than|>) #0$", "ang_gt"],
	["^@0 angle (below|under|less than|<) #0$", "ang_lt"],
	["^@0 bent (more than|past|over|beyond|above) #0$", "flex_gt"],
	["^@0 bent (less than|under|below) #0$", "flex_lt"],
	["^fighters (touch|touching|in contact|make contact|contact|collide|meet|clash)$", "touch"],
	["^fighters (within|closer than|nearer than|less than) #0( apart)?$", "fnear"],
	["^fighters (farther than|further than|more than) #0( apart)?$", "ffar"]]
const INSTANT_FORMS := [
	["^(@0 fastest|fastest @0|@0 moving fastest|@0 at fastest|@0 peak speed|peak speed @0|@0 speed peaks)$", "speed", 1],
	["^(@0 slowest|slowest @0)$", "speed", -1],
	["^(@0 highest|highest @0)$", "height", 1],
	["^(@0 lowest|lowest @0)$", "height", -1],
	["^(@0 most bent|most bent @0)$", "angle", -1],
	["^(@0 straightest|straightest @0|@0 most straight|@0 least bent)$", "angle", 1],
	["^(@0 closest (to|from) @1|closest @0 (to|from) @1|@0 nearest @1|@0 nearest to @1)$", "dist", -1],
	["^(@0 farthest from @1|@0 furthest from @1|farthest @0 from @1)$", "dist", 1],
	["^(fighters closest|closest fighters|fighters nearest|fighters closest together)$", "gap", -1],
	["^(fighters farthest|fighters furthest|fighters farthest apart|fighters furthest apart)$", "gap", 1],
	["^(most off balance|furthest off balance|farthest off balance|worst balance)$", "margin", -1]]


static func _forms(list: Array) -> Array:
	var out := []
	for f in list:
		var r := RegEx.new()
		r.compile(f[0])
		out.append([r, f])
	return out


static func _unit(nm: Dictionary, want: String, phrase: String) -> Variant:
	var v := float(nm["num"])
	var u := String(nm["unit"])
	match want:
		"m":
			if u in ["", "m"]:
				return v
			if u == "cm":
				return v / 100.0
			if u == "mm":
				return v / 1000.0
		"m/s":
			if u in ["", "m/s"]:
				return v
		"deg":
			if u in ["", "deg"]:
				return v
	return {"error": "'%s': %s %s is not a %s" % [phrase, str(v), u, {"m": "distance (m, cm)", "m/s": "speed (m/s)", "deg": "angle (deg)"}[want]]}


## one predicate phrase (a list of tokens) -> a node, or {"error"}
static func _atom(ws: Array) -> Dictionary:
	var phrase := " ".join(ws.map(func(x): return str(x["num"]) + (" " + x["unit"] if x["unit"] != "" else "") if x is Dictionary else str(x)))
	var neg := false
	var keep := []
	for w in ws:
		if w is String and w in ["not", "never", "no"]:
			neg = not neg
		else:
			keep.append(w)
	var s := _skeleton(keep)
	if s.has("error"):
		return _err("'%s': %s" % [phrase, s["error"]], phrase)
	if _rx.is_empty():
		_rx = [_forms(SPAN_FORMS), _forms(INSTANT_FORMS)]
	for e in _rx[0]:
		if (e[0] as RegEx).search(s["sk"]) == null:
			continue
		var kind: String = e[1][1]
		var parts: Array = s["parts"]
		var nums: Array = s["nums"]
		var nd := {"op": "pred", "kind": kind, "parts": parts, "text": phrase}
		if kind in ["down", "up"]:
			var pt: String = parts[0]["pt"]
			if pt.begins_with("foot") or pt.begins_with("ball"):
				nd["kind"] = "foot_down" if kind == "down" else "foot_up"
				var w0 := String(s["sk"]).split(" ")[1] if String(s["sk"]).split(" ").size() > 1 else ""
				if w0 in ["drops", "dropped", "low", "lowered", "high", "raised"]:
					return _err("'%s': say \"down\" / \"on the floor\" or \"up\" / \"off the floor\" for a foot" % phrase, phrase)
			elif pt.begins_with("hand"):
				nd["kind"] = "hand_down" if kind == "down" else "hand_up"
			else:
				return _err("'%s': \"down\" / \"up\" is for a foot (on the floor) or a hand (the guard, against the chin)" % phrase, phrase)
		elif kind in ["faster", "slower"]:
			var v: Variant = _unit(nums[0], "m/s", phrase)
			if v is Dictionary:
				return _err(v["error"], phrase)
			nd["v"] = v
		elif kind in ["higher", "lower", "near", "far", "fnear", "ffar"]:
			var v: Variant = _unit(nums[0], "m", phrase)
			if v is Dictionary:
				return _err(v["error"], phrase)
			nd["v"] = v
		elif kind in ["ang_gt", "ang_lt", "flex_gt", "flex_lt"]:
			var v: Variant = _unit(nums[0], "deg", phrase)
			if v is Dictionary:
				return _err(v["error"], phrase)
			var base: String = String(parts[0]["pt"]).left(-2)
			if not ANGLE.has(base):
				return _err("'%s': the angle is read at an elbow or a knee" % phrase, phrase)
			nd["v"] = v
		if neg:
			return {"op": "not", "a": nd}
		return nd
	return _err("'%s' is not a phrase I know (the known ones are listed; nothing was guessed)" % phrase, phrase)


## the query -> {"ok", "node"} (spans) or {"ok", "instant": {...}, "node": the "while" expr or null}, or {"ok": false, "error", "known"}
static func parse(q: String) -> Dictionary:
	if q.strip_edges() == "":
		return _err("ask a question, e.g. \"when does the right foot leave the floor\"")
	var toks := _tokens(q)
	if _rx.is_empty():
		_rx = [_forms(SPAN_FORMS), _forms(INSTANT_FORMS)]
	var wi := toks.find("while")
	var head: Array = toks if wi < 0 else toks.slice(0, wi)
	var s := _skeleton(head)
	if not s.has("error"):
		for e in _rx[1]:
			if (e[0] as RegEx).search(s["sk"]) != null:
				var inst := {"what": e[1][1], "dir": e[1][2], "parts": s["parts"], "text": " ".join(head.map(func(x): return str(x)))}
				if inst["what"] == "angle":
					var base: String = String(s["parts"][0]["pt"]).left(-2)
					if not ANGLE.has(base):
						return _err("'%s': the angle is read at an elbow or a knee" % inst["text"])
				var cond: Variant = null
				if wi >= 0:
					var pr := _expr(toks.slice(wi + 1), [0])
					if not pr["ok"]:
						return pr
					cond = pr["node"]
				return {"ok": true, "instant": inst, "node": cond}
	if wi >= 0:
		return _err("'while' follows an instant (\"right hand fastest while right foot down\"); for two states at once say \"and\"")
	var pos := [0]
	var r := _expr(toks, pos)
	if not r["ok"]:
		return r
	if pos[0] < toks.size():
		return _err("'%s' was left over: a closing bracket without an opening one?" % " ".join(toks.slice(pos[0]).map(func(x): return str(x))))
	return r


static func _is_kw(t: Variant, kws: Array) -> bool:
	return t is String and t in kws


## expr := term {or term} [for at least N]
static func _expr(toks: Array, pos: Array) -> Dictionary:
	var a := _term(toks, pos)
	if not a["ok"]:
		return a
	var node: Dictionary = a["node"]
	while pos[0] < toks.size() and _is_kw(toks[pos[0]], ["or"]):
		pos[0] += 1
		var b := _term(toks, pos)
		if not b["ok"]:
			return b
		node = {"op": "or", "a": node, "b": b["node"]}
	if pos[0] + 3 < toks.size() and _is_kw(toks[pos[0]], ["for"]) and _is_kw(toks[pos[0] + 1], ["at"]) and _is_kw(toks[pos[0] + 2], ["least"]):
		var nm: Variant = toks[pos[0] + 3]
		if not nm is Dictionary:
			return _err("\"for at least\" needs a number: \"for at least 0.2 s\"")
		var u := String(nm["unit"])
		var sec: float
		var frames := -1
		if u in ["", "s"]:
			sec = float(nm["num"])
		elif u == "ms":
			sec = float(nm["num"]) / 1000.0
		elif u == "frames":
			frames = int(nm["num"])
			sec = NAN
		else:
			return _err("\"for at least %s %s\": a time, in s, ms or frames" % [str(nm["num"]), u])
		pos[0] += 4
		node = {"op": "min", "a": node, "s": sec, "frames": frames}
	elif pos[0] < toks.size() and _is_kw(toks[pos[0]], ["for"]):
		return _err("say \"for at least N s\" (the one duration form)")
	return {"ok": true, "node": node}


static func _term(toks: Array, pos: Array) -> Dictionary:
	var a := _factor(toks, pos)
	if not a["ok"]:
		return a
	var node: Dictionary = a["node"]
	while pos[0] < toks.size() and _is_kw(toks[pos[0]], ["and"]):
		pos[0] += 1
		var b := _factor(toks, pos)
		if not b["ok"]:
			return b
		node = {"op": "and", "a": node, "b": b["node"]}
	return {"ok": true, "node": node}


static func _factor(toks: Array, pos: Array) -> Dictionary:
	if pos[0] >= toks.size():
		return _err("the question ends where a state was expected (after and / or / not / \"(\")")
	var t: Variant = toks[pos[0]]
	if _is_kw(t, ["not"]):
		pos[0] += 1
		var a := _factor(toks, pos)
		if not a["ok"]:
			return a
		return {"ok": true, "node": {"op": "not", "a": a["node"]}}
	if _is_kw(t, ["("]):
		pos[0] += 1
		var e := _expr(toks, pos)
		if not e["ok"]:
			return e
		if pos[0] >= toks.size() or not _is_kw(toks[pos[0]], [")"]):
			return _err("a \"(\" without its \")\"")
		pos[0] += 1
		return e
	var ws := []
	while pos[0] < toks.size():
		var w: Variant = toks[pos[0]]
		if _is_kw(w, ["and", "or", "(", ")"]):
			break
		if _is_kw(w, ["for"]) and pos[0] + 2 < toks.size() and _is_kw(toks[pos[0] + 1], ["at"]):
			break
		ws.append(w)
		pos[0] += 1
	if ws.is_empty():
		return _err("a state was expected here (e.g. \"right foot down\")")
	var nd := _atom(ws)
	if nd.has("ok") and not nd["ok"]:
		return nd
	return {"ok": true, "node": nd}


## the parsed query back as text (what was understood)
static func canon(n: Variant) -> String:
	if n == null:
		return ""
	match String(n["op"]):
		"and":
			return "(%s and %s)" % [canon(n["a"]), canon(n["b"])]
		"or":
			return "(%s or %s)" % [canon(n["a"]), canon(n["b"])]
		"not":
			return "not " + canon(n["a"])
		"min":
			return "(%s for at least %s)" % [canon(n["a"]), ("%d frames" % n["frames"]) if int(n["frames"]) >= 0 else ("%s s" % str(n["s"]))]
	var pp := (n["parts"] as Array).map(func(p): return ("" if str(p["who"]) == "self" else ("other " if str(p["who"]) == "other" else "fighter %d " % (int(p["who"]) + 1))) + String(p["pt"]))
	return "%s%s%s" % [n["kind"], "(" + ", ".join(pp) + ")" if not pp.is_empty() else "", (" " + str(n["v"])) if n.has("v") else ""]


# ---------------------------------------------------------------- evaluation

## the fighter index a part reads
static func _who(p: Dictionary, me: int, nf: int) -> Variant:
	var w: Variant = p["who"]
	if str(w) == "self":
		return me
	if str(w) == "other":
		if nf != 2:
			return {"error": "\"other\" needs exactly two fighters (the scene has %d)" % nf}
		return 1 - me
	if int(w) < 0 or int(w) >= nf:
		return {"error": "no fighter %d (the scene has %d)" % [int(w) + 1, nf]}
	return int(w)


static func _pidx(pt: String) -> int:
	return point_names().find(pt)


## a point's series [Vector3 per frame]
static func _pos(clip: Dictionary, k: int, pt: String) -> Array:
	var ix := _pidx(pt)
	return (clip["pts"][k] as Array).map(func(v): return (v as PackedVector3Array)[ix])


## |dp/dt| per frame: the central difference over one frame either side, one-sided at the ends (measure's speed formula)
static func speed_series(clip: Dictionary, k: int, pt: String) -> PackedFloat32Array:
	var p := _pos(clip, k, pt)
	var n: int = clip["n"]
	var fps: float = clip["fps"]
	var out := PackedFloat32Array()
	for i in n:
		var a := maxi(i - 1, 0)
		var b := mini(i + 1, n - 1)
		out.append(((p[b] as Vector3) - p[a]).length() / maxf(float(b - a) / fps, 1e-9) if b > a else 0.0)
	return out


static func angle_series(clip: Dictionary, k: int, joint: String) -> PackedFloat32Array:
	var sd := joint.right(2)
	var ch: Array = ANGLE[joint.left(-2)]
	var a := _pos(clip, k, ch[0] + sd)
	var b := _pos(clip, k, ch[1] + sd)
	var c := _pos(clip, k, ch[2] + sd)
	var out := PackedFloat32Array()
	for i in a.size():
		out.append(rad_to_deg(((a[i] as Vector3) - b[i]).angle_to((c[i] as Vector3) - b[i])))
	return out


## a node -> {"on": PackedByteArray per frame, "rules": [...]} or {"error"}
static func eval_node(n: Dictionary, clip: Dictionary, me: int) -> Dictionary:
	var N: int = clip["n"]
	var nf: int = (clip["pts"] as Array).size()
	match String(n["op"]):
		"and", "or":
			var a := eval_node(n["a"], clip, me)
			if a.has("error"):
				return a
			var b := eval_node(n["b"], clip, me)
			if b.has("error"):
				return b
			var o := PackedByteArray()
			o.resize(N)
			for i in N:
				o[i] = (1 if (a["on"][i] and b["on"][i]) else 0) if n["op"] == "and" else (1 if (a["on"][i] or b["on"][i]) else 0)
			return {"on": o, "rules": _merge(a["rules"], b["rules"])}
		"not":
			var a := eval_node(n["a"], clip, me)
			if a.has("error"):
				return a
			var o := PackedByteArray()
			for i in N:
				o.append(0 if a["on"][i] else 1)
			return {"on": o, "rules": a["rules"]}
		"min":
			var a := eval_node(n["a"], clip, me)
			if a.has("error"):
				return a
			var k := int(n["frames"]) if int(n["frames"]) >= 0 else int(ceil(float(n["s"]) * float(clip["fps"]) - 1e-6))
			var o: PackedByteArray = (a["on"] as PackedByteArray).duplicate()
			for r in runs(o):
				if r[1] - r[0] + 1 < k:
					for i in range(r[0], r[1] + 1):
						o[i] = 0
			return {"on": o, "rules": _merge(a["rules"], ["for at least: a span of k frames lasts k / fps s; kept when k >= %d (%s at %s fps)" % [k, str(n["s"]) + " s" if int(n["frames"]) < 0 else "%d frames" % k, str(clip["fps"])]])}
	return _pred(n, clip, me)


static func _merge(a: Array, b: Array) -> Array:
	var o := a.duplicate()
	for x in b:
		if not x in o:
			o.append(x)
	return o


const RULE_FOOT := "foot down (MEASURED, balance.gd): a point of the foot or ball capsule within 1 cm (Balance.TOUCH) of the floor, the support polygon's own test"
const RULE_BAL := "off balance (MEASURED, balance.gd): a foot down and the centre of mass past the support polygon by more than 2 cm (Balance.MARGIN_RES); de Leva 1996 masses"
const RULE_GUARD := "hand down (HEURISTIC 10 cm): the wrist more than 0.10 m under the chin; chin = head top - 0.23 m (Winter 2009 Table 4.1, StylePrint.CHIN_BELOW_TOP)"
const RULE_SPEED := "speed (MEASURED from the played body): |p(f+1) - p(f-1)| / (2 / fps), one-sided at the clip's ends, as `measure speed`"
const RULE_TOUCH := "fighters touch (MEASURED, Body.cross_contacts): a capsule of one in a capsule of the other by more than 1 mm, weapons included"
const RULE_GAP := "fighters' gap (MEASURED): the smallest capsule-to-capsule surface distance between the two bodies (weapons included)"
const RULE_ANGLE := "joint angle (MEASURED): the interior angle at the elbow (shoulder-elbow-wrist) or knee (hip-knee-ankle), 180 = straight; bent = 180 - it"


static func _pred(n: Dictionary, clip: Dictionary, me: int) -> Dictionary:
	var N: int = clip["n"]
	var nf: int = (clip["pts"] as Array).size()
	var ks := []
	for p in n["parts"]:
		var w: Variant = _who(p, me, nf)
		if w is Dictionary:
			return w
		ks.append(w)
	var o := PackedByteArray()
	o.resize(N)
	var kind: String = n["kind"]
	var rules := []
	match kind:
		"foot_down", "foot_up":
			var bit := 1 if String(n["parts"][0]["pt"]).ends_with("_l") else 2
			var dn: PackedByteArray = clip["down"][ks[0]]
			for i in N:
				o[i] = 1 if (((dn[i] & bit) != 0) == (kind == "foot_down")) else 0
			rules = [RULE_FOOT]
		"air", "both", "single":
			var dn: PackedByteArray = clip["down"][me]
			for i in N:
				var c := (dn[i] & 1) + ((dn[i] >> 1) & 1)
				o[i] = 1 if c == {"air": 0, "both": 2, "single": 1}[kind] else 0
			rules = [RULE_FOOT]
		"offbal", "bal":
			var dn: PackedByteArray = clip["down"][me]
			var mg: PackedFloat32Array = clip["margin"][me]
			for i in N:
				var off := dn[i] != 0 and mg[i] < -Balance.MARGIN_RES
				o[i] = 1 if (off if kind == "offbal" else (dn[i] != 0 and not off)) else 0
			rules = [RULE_BAL]
		"hand_down", "hand_up", "gdown", "gup":
			var chin := _pos(clip, me if ks.is_empty() else ks[0], "chin")
			var hs: Array = [String(n["parts"][0]["pt"])] if not ks.is_empty() else ["hand_l", "hand_r"]
			var hp := hs.map(func(h): return _pos(clip, me if ks.is_empty() else ks[0], h))
			for i in N:
				var downs := 0
				for h in hp:
					if (h[i] as Vector3).y < (chin[i] as Vector3).y - GUARD_DROP:
						downs += 1
				var down := downs == hs.size()
				var up := downs == 0
				o[i] = 1 if ((kind in ["hand_down", "gdown"] and down) or (kind in ["hand_up", "gup"] and up)) else 0
			rules = [RULE_GUARD]
		"faster", "slower":
			var sp := speed_series(clip, ks[0], n["parts"][0]["pt"])
			for i in N:
				o[i] = 1 if ((sp[i] > float(n["v"])) if kind == "faster" else (sp[i] < float(n["v"]))) else 0
			rules = [RULE_SPEED]
		"higher", "lower":
			var p := _pos(clip, ks[0], n["parts"][0]["pt"])
			for i in N:
				o[i] = 1 if (((p[i] as Vector3).y > float(n["v"])) if kind == "higher" else ((p[i] as Vector3).y < float(n["v"]))) else 0
			rules = ["height (MEASURED): the point's y, the floor at 0"]
		"above", "below":
			var p := _pos(clip, ks[0], n["parts"][0]["pt"])
			var q := _pos(clip, ks[1], n["parts"][1]["pt"])
			for i in N:
				o[i] = 1 if (((p[i] as Vector3).y > (q[i] as Vector3).y) if kind == "above" else ((p[i] as Vector3).y < (q[i] as Vector3).y)) else 0
			rules = ["above / below (MEASURED): one point's y against the other's"]
		"near", "far":
			var p := _pos(clip, ks[0], n["parts"][0]["pt"])
			var q := _pos(clip, ks[1], n["parts"][1]["pt"])
			for i in N:
				var d := (p[i] as Vector3).distance_to(q[i])
				o[i] = 1 if ((d < float(n["v"])) if kind == "near" else (d > float(n["v"]))) else 0
			rules = ["distance (MEASURED): the 3-D distance between the two points (joint centres)"]
		"ang_gt", "ang_lt", "flex_gt", "flex_lt":
			var a := angle_series(clip, ks[0], n["parts"][0]["pt"])
			for i in N:
				var v: float = a[i] if kind.begins_with("ang") else 180.0 - a[i]
				o[i] = 1 if ((v > float(n["v"])) if kind.ends_with("gt") else (v < float(n["v"]))) else 0
			rules = [RULE_ANGLE]
		"touch", "fnear", "ffar":
			if nf < 2:
				return {"error": "'%s' needs two fighters (the scene has one: Actor: add a second fighter)" % n["text"]}
			for i in N:
				if kind == "touch":
					o[i] = clip["touch"][i]
				else:
					o[i] = 1 if ((clip["gap"][i] < float(n["v"])) if kind == "fnear" else (clip["gap"][i] > float(n["v"]))) else 0
			rules = [RULE_TOUCH if kind == "touch" else RULE_GAP]
		_:
			return {"error": "no predicate '%s'" % kind}
	return {"on": o, "rules": rules}


static func runs(on: PackedByteArray) -> Array:
	var out := []
	var i := 0
	while i < on.size():
		if on[i] == 0:
			i += 1
			continue
		var a := i
		while i < on.size() and on[i] != 0:
			i += 1
		out.append([a, i - 1])
	return out


## what a parse reads beyond the points and the feet: "cross" = the two fighters against each other, "bal" = the support
## polygon's margin (only then is Balance.read run per frame)
static func needs_of(pq: Dictionary) -> Dictionary:
	var nd := {"cross": false, "bal": false}
	var inst: Variant = pq.get("instant")
	if inst != null:
		nd["cross"] = String(inst["what"]) == "gap"
		nd["bal"] = String(inst["what"]) == "margin"
	_needs(pq["node"], nd)
	return nd


static func _needs(n: Variant, nd: Dictionary) -> void:
	if n == null:
		return
	if String(n["op"]) == "pred":
		if String(n["kind"]) in ["touch", "fnear", "ffar"]:
			nd["cross"] = true
		if String(n["kind"]) in ["offbal", "bal"]:
			nd["bal"] = true
		return
	_needs(n.get("a"), nd)
	_needs(n.get("b"), nd)


## a parsed query on a sampled clip, for fighter `me` (0 = the first) -> the answer
static func answer(pq: Dictionary, clip: Dictionary, me: int) -> Dictionary:
	var fps: float = clip["fps"]
	var N: int = clip["n"]
	var head := {"ok": true, "fighter": me + 1, "fps": fps, "frames": N, "length_s": snappedf(float(clip["L"]), 0.001),
		"measured": "from the body: the scene played (Scene.apply, what plays) at every frame 0..%d, t = frame / %s" % [N - 1, str(fps)]}
	var cond: Variant = null
	if pq["node"] != null:
		cond = eval_node(pq["node"], clip, me)
		if cond.has("error"):
			return _err(cond["error"])
	if pq.has("instant"):
		var inst: Dictionary = pq["instant"]
		var nf: int = (clip["pts"] as Array).size()
		var ks := []
		for p in inst["parts"]:
			var w: Variant = _who(p, me, nf)
			if w is Dictionary:
				return _err(w["error"])
			ks.append(w)
		var vals := PackedFloat32Array()
		var unit := ""
		var rule := ""
		var ok := PackedByteArray()
		ok.resize(N)
		ok.fill(1)
		match String(inst["what"]):
			"speed":
				vals = speed_series(clip, ks[0], inst["parts"][0]["pt"])
				unit = "m/s"
				rule = RULE_SPEED
			"height":
				for v in _pos(clip, ks[0], inst["parts"][0]["pt"]):
					vals.append((v as Vector3).y)
				unit = "m"
				rule = "height (MEASURED): the point's y, the floor at 0"
			"angle":
				vals = angle_series(clip, ks[0], inst["parts"][0]["pt"])
				unit = "deg"
				rule = RULE_ANGLE
			"dist":
				var p := _pos(clip, ks[0], inst["parts"][0]["pt"])
				var q := _pos(clip, ks[1], inst["parts"][1]["pt"])
				for i in N:
					vals.append((p[i] as Vector3).distance_to(q[i]))
				unit = "m"
				rule = "distance (MEASURED): the 3-D distance between the two points"
			"gap":
				if nf < 2:
					return _err("'%s' needs two fighters (the scene has one)" % inst["text"])
				vals = clip["gap"]
				unit = "m"
				rule = RULE_GAP
			"margin":
				vals = clip["margin"][me]
				var dn: PackedByteArray = clip["down"][me]
				for i in N:
					ok[i] = 1 if dn[i] != 0 else 0
				unit = "m"
				rule = RULE_BAL + " (the margin: + inside the feet, - past them; frames with no foot down are not read)"
		var best := -1
		for i in N:
			if ok[i] == 0 or (cond != null and cond["on"][i] == 0) or is_nan(vals[i]):
				continue
			if best < 0 or (vals[i] > vals[best] if int(inst["dir"]) > 0 else vals[i] < vals[best]):
				best = i   # the FIRST frame of the extreme, on a tie
		head["kind"] = "instant"
		head["parsed"] = "%s %s%s" % ["max" if int(inst["dir"]) > 0 else "min", inst["what"], (" while " + canon(pq["node"])) if pq["node"] != null else ""]
		head["rules"] = _merge([rule], cond["rules"] if cond != null else [])
		if best < 0:
			head["found"] = false
			head["t"] = null
			head["frame"] = null
			head["text"] = "never: no frame where %s" % ("that holds" if cond != null else "it can be read")
			return head
		head["found"] = true
		head["frame"] = best
		head["t"] = snappedf(best / fps, 0.0001)
		head["value"] = snappedf(vals[best], 0.0001)
		head["unit"] = unit
		head["text"] = "%s: frame %d, %.3f s (%.3f %s)" % [inst["text"], best, best / fps, vals[best], unit]
		return head
	var on: PackedByteArray = cond["on"]
	var spans := []
	var tot := 0.0
	for r in runs(on):
		var dur := float(r[1] - r[0] + 1) / fps
		tot += dur
		spans.append({"f0": r[0], "f1": r[1], "t0": snappedf(r[0] / fps, 0.0001), "t1": snappedf(r[1] / fps, 0.0001), "dur_s": snappedf(dur, 0.0001)})
	head["kind"] = "spans"
	head["parsed"] = canon(pq["node"])
	head["spans"] = spans
	head["count"] = spans.size()
	head["total_s"] = snappedf(tot, 0.0001)
	head["starts_s"] = spans.map(func(s): return s["t0"])
	head["rules"] = cond["rules"]
	var said := []
	for sp in spans:
		said.append(("%.3f s (frame %d)" % [sp["t0"], sp["f0"]]) if sp["f0"] == sp["f1"] else ("%.3f-%.3f s (%d-%d f)" % [sp["t0"], sp["t1"], sp["f0"], sp["f1"]]))
	head["text"] = ("never (0-%.2f s)" % float(clip["L"])) if spans.is_empty() else "; ".join(said)
	return head


## query + clip in one: parse, then answer
static func ask(q: String, clip: Dictionary, me := 0) -> Dictionary:
	var pq := parse(q)
	if not pq["ok"]:
		return pq
	var a := answer(pq, clip, me)
	a["query"] = q
	return a


# ---------------------------------------------------------------- the live app (AgentTools / CLI)

## the fighters of the live poser: what plays for each, in the hero's space
static func fighters_of(m: Node) -> Array:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		return [{"S": m._ps(), "B": m.B, "xf": Transform3D.IDENTITY, "name": String(m.S.name)}]
	var out := []
	for k in m.actors_rt.size():
		var a: Dictionary = m.actors_rt[k]
		out.append({"S": a["S"], "B": a["B"], "xf": a["xf"], "name": String(a["name"])})
	return out


## serve's `events {q, fighter?, fps?}` on the live poser -> {"ok", ...} or {"ok": false, "error", "known"?}
static func run(m: Node, p: Dictionary) -> Dictionary:
	var q := String(p.get("q", p.get("text", "")))
	var pq := parse(q)
	if not pq["ok"]:
		return pq
	if m.S.cards.size() < 2:
		return _err("events needs a scene of 2+ cards: open one first")
	var fs := fighters_of(m)
	if fs.size() == 1:
		await m.dummy_settle()   # one fighter: what plays may be the scene landed on the dummy (measure waits the same way)
		fs = fighters_of(m)      # (two or more: the dummy is away and each fighter's own scene plays)
	var me := int(p.get("fighter", 1)) - 1
	if me < 0 or me >= fs.size():
		return _err("no fighter %d (the scene has %d)" % [me + 1, fs.size()])
	var fps := float(p.get("fps", (fs[0]["S"] as Scene).fps))
	if fps <= 0.0 or fps > 240.0:
		return _err("fps between 1 and 240")
	var t0 := Time.get_ticks_usec()
	var clip := sample(fs, fps, needs_of(pq))
	var a := answer(pq, clip, me)
	a["query"] = q
	a["sampled"] = clip["sampled"] + (" (cached)" if clip["cached"] else "")
	a["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	return a
