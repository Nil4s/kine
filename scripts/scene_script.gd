## SCENE LINES (Friday plan 135 + 136, s135): one typed line in plain words for the whole scene.
##   TWO CHARACTERS WITH TIMING WORDS (135): "A punches, then B falls" / "while A waves, B jumps" / "after 2 seconds, B sits"
##   CAMERA WORDS (136):                      "close up on A" / "wide shot" / "follow B" / "orbit slowly"
## A and B are the scene's characters in order (A = the hero, B = the second fighter, C = a third...); "hero" and "fighter 2" work too.
## parse() reads the words and plans() works the cards out; both are pure (they touch no scene). The panel is scene_script_ui.gd.
##
## TIMING (each clause is "<who> <move>"; a line replaces the cards of the characters it names and leaves the others alone):
##   then   = starts when everything before it has ended           "A punches, then B falls": B starts where A's punch ends
##   while  = starts with the clause it is joined to                "while A waves, B jumps": both start on the same frame
##   after N seconds = N seconds after the previous clause STARTED (the line's start, 0 s, for the first clause)
## A character that waits gets a first card "waits" (the pose it starts the move in) holding until its move starts; the move's
## first card starts on that frame exactly. A comma alone means then.
## CAMERA: writes ONE shot of the scene's shot list (at the playhead; a scene with no shot gets it at 0 s). The camera is in the
## hero's space, like Auto camera and Shot list.
##   close up on A  1.0 m in front of A's face (30 deg off), the lens 40 mm, aimed at the head: the head is the middle of the frame
##   wide shot      every character in frame for the whole scene, seen from the side of the line between them (28 mm)
##   follow B       a camera 4.5 m from B that keeps B's body in the middle of the frame as B moves (35 mm, a key every 0.25 s)
##   orbit slowly   goes round all the characters: slowly 10 deg/s, fast 60 deg/s, else 30 deg/s (35 mm, 5 m)
## Words it does not know: the plain sentence says which, and nothing changes.
class_name SceneScript
extends RefCounted

const MOVES := {"punch": "punch", "jab": "punch", "hit": "punch", "kick": "roundhouse", "wave": "wave", "jump": "jump", "hop": "jump",
	"sit": "sit_down", "fall": "fall", "collapse": "fall", "walk": "walk", "run": "run", "dance": "dance", "stand": "stand_up", "swing": "sword_swing"}
const JOIN_S := 0.3            # a later move of the same character blends in from where the earlier one stopped
const FIT_MARGIN := 0.05       # the wide shot keeps every point this far (a share of the frame) from the edge
const KEY_DT := 0.25           # s between the keys of a follow or an orbit
const CLOSE := {"f": 40.0, "d": 1.0, "theta": 30.0}
const WIDE_F := 28.0
const FOLLOW := {"f": 35.0, "d": 4.5}
const ORBIT_R := 5.0
const ORBIT_F := 35.0
const ORBIT_MIN_S := 3.0       # an orbit lasts the scene, but at least this long


static func _norm(text: String) -> PackedStringArray:
	var s := text.to_lower().strip_edges()
	while s.ends_with(".") or s.ends_with("!"):
		s = s.substr(0, s.length() - 1)
	s = s.replace(" and then ", " then ").replace(",", " , ").replace("-", " ")
	return s.split(" ", false)


## the character a word names: its index, or -1
static func actor_of(w: String) -> int:
	if w.length() == 1 and w >= "a" and w <= "z":
		return w.unicode_at(0) - 97
	if w == "hero":
		return 0
	return -1


static func _move_of(words: Array) -> String:
	for w in words:
		for stem in MOVES:
			if String(w).begins_with(stem):
				return String(MOVES[stem])
	return ""


## the line -> {"ok": true, "kind": "scene", "clauses": [{"actor", "move", "mode": "first|then|par|after", "after": s}]}
##            or {"ok": true, "kind": "camera", "cam": "close|wide|follow|orbit", "who": index or -1, "speed": deg/s}
##            or {"ok": false, "error": the plain sentence}. n = how many characters the scene has
static func parse(text: String, n: int) -> Dictionary:
	var tk := _norm(text)
	if tk.is_empty():
		return {"ok": false, "error": "Type a line first, such as 'A punches, then B falls' or 'close up on A'."}
	var low := " ".join(tk)
	var timed: bool = tk.has("then") or tk.has("while") or tk.has("after")
	if not timed:
		var cam := _camera(tk, n)
		if cam.get("hit", false):
			return cam
	# the timing words: clauses
	var clauses := []
	var cur := []
	var st := {"mode": "first", "after": 0.0, "head": false}   # a lambda copies plain locals: the state lives in a Dictionary
	var flush := func() -> String:   # a clause done: "" or the error
		if cur.is_empty():
			return ""
		var who := actor_of(String(cur[0]))
		if who < 0:
			return "I could not tell who '%s' is. Start each part with a character letter: A, B..." % " ".join(PackedStringArray(cur))
		if who >= n:
			return "There is no character %s: the scene has %d. Add one first (Actor: add a second fighter)." % [String(cur[0]).to_upper(), n]
		var mv := _move_of(cur.slice(1))
		if mv == "":
			return "I do not know the move in '%s'. Try punch, kick, wave, jump, sit, fall, walk, run, dance or stand." % " ".join(PackedStringArray(cur))
		var md: String = st["mode"]
		clauses.append({"actor": who, "move": mv, "mode": md, "after": float(st["after"])})
		st["mode"] = "par" if st["head"] else "then"
		st["head"] = false
		st["after"] = 0.0
		cur.clear()
		return ""
	var i := 0
	while i < tk.size():
		var w: String = tk[i]
		if w == "then" or w == ",":
			var e: String = flush.call()
			if e != "":
				return {"ok": false, "error": e}
			if w == "then":
				st["mode"] = "then"
		elif w == "while" and cur.is_empty():
			st["head"] = true
		elif w == "after" and i + 2 < tk.size() and String(tk[i + 1]).is_valid_float() and String(tk[i + 2]).begins_with("s"):
			var e2: String = flush.call()
			if e2 != "":
				return {"ok": false, "error": e2}
			st["after"] = float(tk[i + 1])
			st["mode"] = "after"
			i += 2
		else:
			cur.append(w)
		i += 1
	var e3: String = flush.call()
	if e3 != "":
		return {"ok": false, "error": e3}
	if clauses.is_empty():
		return {"ok": false, "error": "I did not understand '%s'. Try 'A punches, then B falls', 'while A waves, B jumps', 'close up on A' or 'wide shot'." % low}
	return {"ok": true, "kind": "scene", "clauses": clauses}


static func _camera(tk: PackedStringArray, n: int) -> Dictionary:
	var low := " ".join(tk)
	var who := -1
	for w in tk:
		var a := actor_of(String(w))
		if a >= 0 and String(w) != "a":
			who = a
	if tk.size() >= 2:   # "a" is the article in "a wide shot", but a character in "close up on a": the last word decides
		var last: String = tk[tk.size() - 1]
		if last.length() == 1 and last >= "a" and last <= "z":
			who = actor_of(last)
	if who >= n:
		return {"hit": true, "ok": false, "error": "There is no character %s: the scene has %d. Add one first (Actor: add a second fighter)." % [char(65 + who), n]}
	if low.contains("orbit") or low.contains("circle") or low.contains("go round") or low.contains("turntable"):
		var sp := 30.0
		if low.contains("slow"):
			sp = 10.0
		elif low.contains("fast") or low.contains("quick"):
			sp = 60.0
		return {"hit": true, "ok": true, "kind": "camera", "cam": "orbit", "who": -1, "speed": sp}
	if low.contains("follow") or low.contains("track"):
		if who < 0:
			return {"hit": true, "ok": false, "error": "Follow who? Say 'follow A' or 'follow B'."}
		return {"hit": true, "ok": true, "kind": "camera", "cam": "follow", "who": who, "speed": 0.0}
	if low.contains("close up") or low.contains("closeup") or low.contains("close on"):
		return {"hit": true, "ok": true, "kind": "camera", "cam": "close", "who": maxi(who, 0), "speed": 0.0}
	if low.contains("wide") or low.contains("establishing"):
		return {"hit": true, "ok": true, "kind": "camera", "cam": "wide", "who": -1, "speed": 0.0}
	return {}


# ---------------------------------------------------------------- the cards

## the clauses -> {"ok": true, "cards": {actor index: Array of cards}, "spans": [{"actor", "t0", "t1"}]} or {"ok": false, "error"}.
## Nothing in `scenes` (one Scene per character, in order) is changed
static func plan(clauses: Array, scenes: Array, fps: int) -> Dictionary:
	var mine := {}      # actor -> the Scene being built (cards only)
	var spans := []
	var max_end := 0.0
	var prev_start := 0.0
	for c in clauses:
		var who: int = c["actor"]
		var t: float
		match String(c["mode"]):
			"then":
				t = max_end
			"par":
				t = prev_start
			"after":
				t = (prev_start if not spans.is_empty() else 0.0) + float(c["after"])
			_:
				t = 0.0 if spans.is_empty() else max_end
		var d := Templates.read(String(c["move"]))
		if d.is_empty():
			return {"ok": false, "error": "The %s move is not available (its template file is missing)." % String(c["move"]).replace("_", " ")}
		var T := Scene.new()
		T.from_dict(d)
		if T.cards.is_empty():
			return {"ok": false, "error": "The %s move has no cards." % String(c["move"]).replace("_", " ")}
		var sc: Scene
		if mine.has(who):
			sc = mine[who]
		else:
			sc = Scene.new()
			sc.fps = fps
			sc.name = (scenes[who] as Scene).name
			mine[who] = sc
		var cards: Array = T.cards
		if sc.cards.is_empty():   # the first move: a lead card in the move's start pose, holding until the move starts
			var lead: Dictionary = (cards[0] as Dictionary).duplicate(true)
			lead["move"] = 0.0
			lead["hold"] = t
			lead["name"] = "waits" if t > 0.0 else String(lead["name"])
			var rest := cards.slice(1)
			sc.cards = [lead]
			sc.cards.append_array(rest)
		else:
			var end := sc.length()
			if t < end - 1e-6:
				return {"ok": false, "error": "%s is still busy at %.2f s (its move ends at %.2f s): put 'then' between the two moves." % [char(65 + who), t, end]}
			var e := sc.sample(end)
			EasyHome.place_after(cards, e["offset"], e["ang"]["pelvis"] if (e["ang"] as Dictionary).has("pelvis") else Vector3.ZERO)
			if t > end + 1e-6:
				var last: Dictionary = sc.cards[-1]
				last["hold"] = float(last["hold"]) + (t - end)
			var first: Dictionary = cards[0]
			first["move"] = JOIN_S
			first["hold"] = 0.0
			sc.cards.append_array(cards)
		spans.append({"actor": who, "t0": t, "t1": sc.length()})
		max_end = maxf(max_end, sc.length())
		prev_start = t
	var out := {}
	for k in mine:
		out[k] = (mine[k] as Scene).cards
	return {"ok": true, "cards": out, "spans": spans}


# ---------------------------------------------------------------- the camera

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## every character's points at the times given: [per time [per character: {"all", "pel", "head", "face"}]]
static func _people(H: Scene, times: Array) -> Array:
	var bodies := AutoCam.bodies_for(H)
	var out := []
	for t in times:
		out.append(AutoCam.fighters(H, bodies, float(t)))
	return out


static func _span(H: Scene, t0: float) -> float:
	var len := H.length()
	for a in H.actors:
		len = maxf(len, (a["scene"] as Scene).length())
	return maxf(len - t0, 0.0)


## the side of the line between the characters (the way a camera sees them both): a flat unit vector from the middle to the camera
static func _side(ppl: Array) -> Vector3:
	if ppl.size() < 2:
		return (Basis(Vector3.UP, deg_to_rad(15.0)) * (ppl[0]["face"] as Vector3)).normalized()
	var l := _flat((ppl[1]["pel"] as Vector3) - (ppl[0]["pel"] as Vector3))
	if l.length() < 1e-4:
		return Vector3(1, 0, 0)
	return Vector3(-l.z, 0.0, l.x).normalized()


## the shot for a camera word at time t0: {"t", "name", "keys"} (keys at absolute scene times) or {} (no such character)
static func shot_for(p: Dictionary, H: Scene, t0: float, text: String) -> Dictionary:
	var cam := String(p["cam"])
	var who: int = p["who"]
	var span := _span(H, t0)
	var keys := []
	match cam:
		"close":
			var f0: Array = AutoCam.fighters(H, AutoCam.bodies_for(H), t0)
			if who >= f0.size():
				return {}
			var ppl: Dictionary = f0[who]
			var head: Vector3 = ppl["head"] - Vector3(0, 0.13, 0)   # the head joint (the list has the head top)
			var fwd: Vector3 = (Basis(Vector3.UP, deg_to_rad(float(CLOSE["theta"]))) * (ppl["face"] as Vector3)).normalized()
			var aim := head + Vector3(0, 0.05, 0)
			var pos := aim + fwd * float(CLOSE["d"])
			keys.append({"t": t0, "pos": pos, "aim": aim, "f": float(CLOSE["f"])})
		"wide":
			var ts := _times(t0, span)
			var ppl2 := _people(H, ts)
			var pts := []
			for row in ppl2:
				for q in row:
					pts.append_array(q["all"])
			var centre: Vector3 = AutoCam._bbox_centre(pts)
			var k: Dictionary = AutoCam._fit(centre, _side(ppl2[0]), WIDE_F, 0.0, centre, 0.0, pts, FIT_MARGIN)
			keys.append({"t": t0, "pos": k["pos"], "aim": k["aim"], "f": WIDE_F})
		"follow":
			var ts2 := _times(t0, span, KEY_DT)
			var ppl3 := _people(H, ts2)
			if who >= (ppl3[0] as Array).size():
				return {}
			var side := _side(ppl3[0])
			for i in ts2.size():
				var pts2: Array = ppl3[i][who]["all"]
				var c: Vector3 = AutoCam._bbox_centre(pts2)
				keys.append({"t": ts2[i], "pos": c + side * float(FOLLOW["d"]), "aim": c, "f": float(FOLLOW["f"])})
		"orbit":
			var dur := maxf(span, ORBIT_MIN_S)
			var ts3 := _times(t0, dur, KEY_DT)
			var pts3 := []
			for row in _people(H, [t0]):
				for q in row:
					pts3.append_array(q["all"])
			var c0: Vector3 = AutoCam._bbox_centre(pts3)
			var az0 := atan2(_side(_people(H, [t0])[0]).z, _side(_people(H, [t0])[0]).x)
			for t in ts3:
				var az := az0 + deg_to_rad(float(p["speed"]) * (float(t) - t0))
				var pos3 := c0 + Vector3(cos(az), 0.0, sin(az)) * ORBIT_R + Vector3(0, 0.4, 0)
				keys.append({"t": t, "pos": pos3, "aim": c0, "f": ORBIT_F})
	return {"t": t0, "name": "Scene line: %s" % text.strip_edges(), "keys": keys}


static func _times(t0: float, span: float, dt := -1.0) -> Array:
	var out := []
	if dt <= 0.0:   # seven looks through the span (Auto camera's SAMPLES)
		for i in AutoCam.SAMPLES:
			out.append(t0 + span * float(i) / float(AutoCam.SAMPLES - 1))
		return out
	var n := maxi(ceili(span / dt), 1)
	for i in n + 1:
		out.append(t0 + minf(float(i) * dt, span))
	return out


## the shot into the scene's shot list: replaces the shot that starts on the same frame, else inserts it in order
static func write_shot(shots: Array, shot: Dictionary, fps: int) -> void:
	var fr := roundi(float(shot["t"]) * float(fps))
	for i in shots.size():
		if roundi(float(shots[i]["t"]) * float(fps)) == fr:
			shots[i] = shot
			return
	shots.insert(ShotCam.insert_index(shots, float(shot["t"])), shot)
