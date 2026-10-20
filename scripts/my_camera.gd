## MY CAMERA (ROADMAP I32). Reads the shot cameras Nick keyed in his OWN scenes (scenes/*.json, read only), measures his habits and
## frames a new shot the way he does. Two parts: FINGERPRINT (medians + spread + counts) and PLAN (a camera key from the fingerprint).
##
## WHAT IS MEASURED, once per camera key of every shot, with the hero posed at the key's time (AutoCam.fighters, private bodies):
##   f      lens, mm (ShotCam's 36 mm sensor)
##   h      camera height / the hero's eye height, both above his lowest sole. Eye = head top - EYE_BELOW_TOP (vertex to eye 0.12 m:
##          NASA-STD-3000 / Dreyfuss anthropometry, stature - eye height 0.11 .. 0.13 m for adults)
##   dist   flat distance from the hero's pelvis to the camera, in body heights (head top to lowest sole)
##   theta  angle between the way from the hero's pelvis to the camera and the way BEHIND him along the line of action (0 = over his
##          shoulder along the line, 90 = square on, 180 = in front); the line is the one AutoCam uses: the fighters' pelvis line,
##          or the single actor's facing. Same convention as AutoCam.SPEC
##   sx,sy  where his pelvis lands in the 16:9 frame, in frame widths / heights from the centre. sx is signed toward the way the
##          line of action points on screen (negative = room in front of him, the lead room)
##   cut    frames the cut comes BEFORE the nearest contact (a "hit" marker, else AutoCam's contact), within CUT_WINDOW; every
##          shot but the first (the first always starts at 0 s, so it is no choice)
## The fingerprint is cached in user:// keyed by the scenes' paths + modified times; a changed scene list recomputes it.
class_name MyCam
extends RefCounted

const FR := Rect2i(0, 0, 1280, 720)
const EYE_BELOW_TOP := 0.12     # m, vertex to eye (NASA-STD-3000 anthropometry)
const CUT_WINDOW := 1.0         # s: a cut farther than this from every contact is not "about" that contact
const MIN_LINE := 0.2           # |line . camera right| under this: the camera is on the line, sx has no sign
const HABITS := ["f", "h", "dist", "theta", "sx", "sy", "cut"]

static var dirs: Array = ["res://scenes"]       # tests point this at a temp folder
static var cache_path := "user://my_camera.json"   # tests use a user:// file with the process id


static func files() -> Array:
	var out := []
	for d in dirs:
		var da := DirAccess.open(String(d))
		if da == null:
			continue
		for fn in da.get_files():
			if fn.ends_with(".json"):
				out.append(String(d).path_join(fn))
	out.sort()
	return out


static func stamp(fs: Array) -> String:
	var parts := []
	for p in fs:
		parts.append("%s:%d" % [p, FileAccess.get_modified_time(String(p))])
	return ";".join(parts)


static func load_scene(path: String) -> Scene:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not (d as Dictionary).has("cards"):
		return null
	var S := Scene.new()
	S.from_dict(d)
	return S


static func line_dir(fs: Array) -> Vector3:
	var dir: Vector3 = fs[0]["face"]
	if fs.size() > 1:
		var d2: Vector3 = AutoCam._flat((fs[1]["pel"] as Vector3) - (fs[0]["pel"] as Vector3))
		if d2.length() > 0.2:
			dir = d2.normalized()
	return dir


## the hero's measures at t: {"lo" (lowest sole y), "H" (stature), "eye" (eye height above the sole), "A" (pelvis on the floor), "pel", "dir"}
static func read_hero(S: Scene, bodies: Array, t: float) -> Dictionary:
	var fs := AutoCam.fighters(S, bodies, clampf(t, 0.0, S.length()))
	var lo := 1e9
	for p in fs[0]["all"]:
		lo = minf(lo, (p as Vector3).y)
	var top: Vector3 = fs[0]["head"]
	return {"lo": lo, "H": top.y - lo, "eye": top.y - EYE_BELOW_TOP - lo, "A": AutoCam._flat(fs[0]["pel"]), "pel": fs[0]["pel"], "dir": line_dir(fs), "fs": fs}


## one camera key's habits ({} = not measurable)
static func measure_key(S: Scene, bodies: Array, key: Dictionary) -> Dictionary:
	var r := read_hero(S, bodies, float(key["t"]))
	if float(r["H"]) < 0.5 or float(r["eye"]) < 0.3:
		return {}
	var pos: Vector3 = key["pos"]
	var aim: Vector3 = key["aim"]
	var f := float(key["f"])
	var rel: Vector3 = AutoCam._flat(pos - (r["A"] as Vector3))
	if rel.length() < 0.05:
		return {}
	var dir: Vector3 = r["dir"]
	var out := {"f": f, "h": (pos.y - float(r["lo"])) / float(r["eye"]), "dist": rel.length() / float(r["H"]),
		"theta": rad_to_deg(acos(clampf((-dir).dot(rel.normalized()), -1.0, 1.0))), "side": signf(AutoCam.side_of(dir, rel))}
	var sp := ShotCam.project(pos, aim, f, FR, r["pel"])
	out["sy"] = (sp.y - FR.size.y * 0.5) / FR.size.y
	var rt: Vector3 = ShotCam.xf(pos, aim).basis.x
	var dr := dir.dot(rt)
	if absf(dr) >= MIN_LINE:
		out["sx"] = (sp.x - FR.size.x * 0.5) / FR.size.x * signf(dr)
	return out


## the contact times of a scene: its "hit" markers, else AutoCam's contact of the strike ([] = none)
static func contacts_of(S: Scene, bodies: Array) -> Array:
	var out := []
	for mk in S.markers:
		if String(mk["kind"]) == "hit":
			out.append(float(mk["t"]))
	if out.is_empty():
		var bt := AutoCam.beats(S, bodies)
		if not bt.is_empty():
			out.append(float(bt["tc"]))
	return out


## every sample of a scene's shots: [{"f","h","dist","theta","sy","sx"?,"cut"?}]
static func measure_scene(S: Scene) -> Array:
	var out := []
	if S.shots.is_empty() or S.cards.is_empty():
		return out
	var bodies := AutoCam.bodies_for(S)
	var fps := float(maxi(S.fps, 1))
	var cons := contacts_of(S, bodies) if S.shots.size() > 1 else []
	for si in S.shots.size():
		var sh: Dictionary = S.shots[si]
		var cutv := {}
		if si > 0 and not cons.is_empty():
			var best := 1e9
			var cut_t := float(sh["t"])
			for tc in cons:
				if absf(float(tc) - cut_t) < absf(best):
					best = float(tc) - cut_t
			if absf(best) <= CUT_WINDOW:
				cutv = {"cut": float(roundi(best * fps))}
		var first := true
		for k in sh["keys"]:
			var mk := measure_key(S, bodies, k)
			if mk.is_empty():
				continue
			if first:
				mk.merge(cutv)   # the cut belongs to the shot: counted once, on its first key
				first = false
			out.append(mk)
	return out


static func _q(a: Array, p: float) -> float:
	var s := a.duplicate()
	s.sort()
	var x := p * float(s.size() - 1)
	var i := int(floor(x))
	var j := mini(i + 1, s.size() - 1)
	return lerpf(float(s[i]), float(s[j]), x - float(i))


static func stat(vals: Array) -> Dictionary:
	if vals.is_empty():
		return {"n": 0, "med": 0.0, "q1": 0.0, "q3": 0.0}
	return {"n": vals.size(), "med": _q(vals, 0.5), "q1": _q(vals, 0.25), "q3": _q(vals, 0.75)}


## THE FINGERPRINT: {"stamp", "scenes" (with shots), "read" (scenes read), "shots", "keys", "stats": {habit: {n, med, q1, q3}}, "cached"}
static func compute(force := false) -> Dictionary:
	var fs := files()
	var st := stamp(fs)
	if not force and FileAccess.file_exists(cache_path):
		var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
		if c is Dictionary and String((c as Dictionary).get("stamp", "")) == st and (c as Dictionary).has("stats"):
			(c as Dictionary)["cached"] = true
			return c
	var vals := {}
	for h in HABITS:
		vals[h] = []
	var fp := {"stamp": st, "scenes": 0, "read": 0, "shots": 0, "keys": 0, "cached": false}
	for p in fs:
		var S := load_scene(String(p))
		if S == null:
			continue
		fp["read"] += 1
		if S.shots.is_empty():
			continue
		fp["scenes"] += 1
		fp["shots"] += S.shots.size()
		for mk in measure_scene(S):
			fp["keys"] += 1
			for h in HABITS:
				if mk.has(h):
					vals[h].append(float(mk[h]))
	var stats := {}
	for h in HABITS:
		stats[h] = stat(vals[h])
	fp["stats"] = stats
	_save_cache(fp)
	return fp


static func _save_cache(fp: Dictionary) -> void:
	var f := FileAccess.open(cache_path, FileAccess.WRITE)   # user:// only (a cache, never a scene)
	if f != null:
		f.store_string(JSON.stringify(fp))


# ---------------------------------------------------------------- Frame it my way

static func _med(fp: Dictionary, h: String, d: float) -> float:
	var s: Dictionary = fp["stats"][h]
	return float(s["med"]) if int(s["n"]) > 0 else d


## the new shot from the fingerprint, for scene S (the hero's) with the playhead at `playhead`:
## {"why"} when it cannot be made, else {"key", "cut" (s), "frame", "replace" (index of the shot on that frame, -1 = insert),
## "text" (the status line), "used" [habit names], "side"}.
static func plan(S: Scene, fp: Dictionary, playhead: float) -> Dictionary:
	if S.cards.size() < 2:
		return {"why": "Frame it my way needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below"}
	var st: Dictionary = fp["stats"]
	var bodies := AutoCam.bodies_for(S)
	var cons := contacts_of(S, bodies)
	if cons.is_empty():
		return {"why": "Frame it my way found no contact to cut on: put a 'hit' marker on the timeline (Markers), or name a card 'contact', then run it again"}
	var tc: float = cons[0]
	for c in cons:
		if absf(float(c) - playhead) < absf(tc - playhead):
			tc = float(c)
	var fps := maxi(S.fps, 1)
	var off := roundi(_med(fp, "cut", 0.0))
	var fr := maxi(0, roundi(tc * fps) - off)
	if S.shots.is_empty():
		fr = 0
	var cut_t := float(fr) / float(fps)
	var replace := -1
	for i in S.shots.size():
		if roundi(float(S.shots[i]["t"]) * fps) == fr:
			replace = i
	var r := read_hero(S, bodies, cut_t)
	var A: Vector3 = r["A"]
	var dir: Vector3 = r["dir"]
	# the 180-degree rule: the side of the shot before this one, else the side of the striking hand (AutoCam's choice)
	var side := 0.0
	var prev := (replace - 1) if replace >= 0 else ShotCam.shot_index(S.shots, cut_t - 0.0005)
	if prev >= 0 and prev < S.shots.size():
		var pc := ShotCam.sample(S.shots[prev]["keys"], cut_t)
		if not pc.is_empty():
			var sv := AutoCam.side_of(dir, AutoCam._flat((pc["pos"] as Vector3) - A))
			if absf(sv) > 0.1:
				side = signf(sv)
	var from_prev := side != 0.0
	if side == 0.0:
		side = 1.0
		var bt := AutoCam.beats(S, bodies)
		if not bt.is_empty():
			var hand: Vector3 = AutoCam.fighters(S, bodies, tc)[0]["h" + String(bt["strike"]["hand"])]
			side = 1.0 if AutoCam.side_of(dir, AutoCam._flat(hand - (r["pel"] as Vector3))) >= 0.0 else -1.0
	var theta := _med(fp, "theta", 45.0)
	var dist := _med(fp, "dist", 3.0)
	var f := _med(fp, "f", 35.0)
	var hr := _med(fp, "h", 1.0)
	var dirv := Basis(Vector3.UP, -side * deg_to_rad(theta)) * (-dir)
	var pos: Vector3 = A + dirv * dist * float(r["H"])
	pos.y = maxf(float(r["lo"]) + hr * float(r["eye"]), AutoCam.MIN_CAM_Y)
	var sxr := _med(fp, "sx", 0.0)
	var syv := _med(fp, "sy", 0.0)
	var pel: Vector3 = r["pel"]
	var aim := pel
	var k := FR.size.y * 0.5 / tan(deg_to_rad(ShotCam.fov_v(f)) * 0.5)
	for i in 12:   # aim the lens so his pelvis lands where Nick puts it (the camera itself stays where the habits put it)
		var xf := ShotCam.xf(pos, aim)
		var sl := signf(dir.dot(xf.basis.x))
		if sl == 0.0:
			sl = 1.0
		var target := Vector2(FR.size.x * (0.5 + sxr * sl), FR.size.y * (0.5 + syv))
		var err := ShotCam.project(pos, aim, f, FR, pel) - target
		if err.length() < 0.02:
			break
		var q: Vector3 = xf.affine_inverse() * pel
		var sc := -q.z / k
		aim += xf.basis.x * (err.x * sc) - xf.basis.y * (err.y * sc)
	var shot_key := {"t": cut_t, "pos": pos, "aim": aim, "f": f}
	var cutw := "on the contact" if off == 0 else ("%d f %s contact" % [absi(off), "before" if off > 0 else "after"])
	var used := ["lens", "height", "distance", "angle", "thirds"]
	if int(st["cut"]["n"]) > 0:
		used.append("cut")
	var text := "Frame it my way: your %.0f mm, %.1f body heights, %d deg off the line, cut %s (camera at %.2f x eye height, subject %+.2f of the frame from centre; from %d shots in %d scenes; %s side of the line%s)" % [
		f, dist, roundi(theta), cutw, hr, sxr, int(fp["shots"]), int(fp["scenes"]), "left" if side < 0 else "right",
		", as your shot before" if from_prev else ", the striking hand's"]
	if S.shots.is_empty():
		text += "; the scene's first shot starts at 0 s, so the cut offset could not apply"
	return {"key": shot_key, "cut": cut_t, "frame": fr, "replace": replace, "text": text, "used": used, "side": side, "tc": tc}


## write the plan into the shot list (inside an edit's undo step): replaces the keys of the shot on that frame, else inserts a shot
static func write(shots: Array, pl: Dictionary) -> void:
	var key: Dictionary = (pl["key"] as Dictionary).duplicate()
	if int(pl["replace"]) >= 0:
		shots[int(pl["replace"])]["keys"] = [key]
	else:
		shots.insert(ShotCam.insert_index(shots, float(pl["cut"])), {"t": float(pl["cut"]), "name": "My camera", "keys": [key]})
