## ASSEMBLY ANIMATION (gap G7 of docs/CHALLENGE_FEEDBACK.md): the drives of an Assembly keyed on a timeline, played through G1MOTION's open
## links and G2LOOP's loop solver. The record keeps one more OPTIONAL entry next to "drives" / "links" / "joints" (a record without it is
## exactly as before):
##   "anim": {"fps": 30, "length": 2.0 (s), "tracks": [{"drive": "Crank", "keys": [[t (s), value (deg | mm), interp], ...]}]}
## A key's interp is how the curve LEAVES that key toward the next (PartKeys' convention): "linear"; "smooth" = Scene._ease's default ease,
## x x (3 - 2 x) (zero speed at both keys); "constant" holds the key's value until the next key. Before the first key and after the last the
## value is held (Curves.eval's "constant" extrapolation). A drive with no track stays at 0 (its record pose).
## Frames: frame k is at k / fps, both ends included, so 2 s at 30 fps is 61 frames (PartMotion's count).
## Playback: each track's drive moves its parts (AssemblyMotion.open_moves), or with joints the loop solver poses every part they tie to it
## (AssemblyLoop.sweep, each frame from the last one's pose). Two drives are solved one at a time (each with the others at 0) and their moves
## are put together; one loop moved by two drives at once is NOT solved as one system.
## check() runs AssemblyMotion.check_motion over the frames, so each clash has its TIME as well as the drive's value.
class_name AssemblyAnim
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const FPS := 30
const LENGTH := 2.0
const INTERPS := ["linear", "smooth", "constant"]


static func anim(asm: Dictionary) -> Dictionary:
	return asm["anim"] if asm.get("anim", null) is Dictionary else {}


static func tracks(asm: Dictionary) -> Array:
	var a := anim(asm)
	return a["tracks"] if a.get("tracks", null) is Array else []


static func has_anim(asm: Dictionary) -> bool:
	for tr in tracks(asm):
		if not ((tr as Dictionary).get("keys", []) as Array).is_empty():
			return true
	return false


static func fps(asm: Dictionary) -> int:
	return maxi(1, int(anim(asm).get("fps", FPS)))


static func length(asm: Dictionary) -> float:
	return maxf(0.0, float(anim(asm).get("length", LENGTH)))


static func track_of(asm: Dictionary, drive: String) -> Dictionary:
	for tr in tracks(asm):
		if String((tr as Dictionary).get("drive", "")) == drive:
			return tr
	return {}


## the drives that have keys, in track order
static func driven(asm: Dictionary) -> Array:
	var out: Array = []
	for tr in tracks(asm):
		if not ((tr as Dictionary).get("keys", []) as Array).is_empty() and not AssemblyMotion.drive_of(asm, String(tr["drive"])).is_empty():
			out.append(String(tr["drive"]))
	return out


static func frame_count(asm: Dictionary) -> int:
	return int(floor(length(asm) * fps(asm) + 1e-6)) + 1


static func time_of(asm: Dictionary, k: int) -> float:
	return minf(float(k) / float(fps(asm)), length(asm))


## every frame's time: 0, 1/fps, ..., length
static func times(asm: Dictionary) -> Array:
	var out: Array = []
	for k in frame_count(asm):
		out.append(time_of(asm, k))
	return out


## the progress 0..1 across a segment for interp kind at u (0..1)
static func ease_of(kind: String, u: float) -> float:
	match kind:
		"smooth":
			return u * u * (3.0 - 2.0 * u)
		"constant":
			return 1.0 if u >= 1.0 else 0.0
	return u


static func interp_of(key: Array) -> String:
	return String(key[2]) if key.size() >= 3 and INTERPS.has(String(key[2])) else "linear"


## a track's keys read at t (doubles); held outside the keys; 0 with no keys
static func eval_keys(keys: Array, t: float) -> float:
	if keys.is_empty():
		return 0.0
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	var last: Array = keys[keys.size() - 1]
	if t >= float(last[0]):
		return float(last[1])
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		var ta := float(a[0])
		var tb := float(b[0])
		if t >= ta and t < tb:
			var u := (t - ta) / (tb - ta) if tb > ta else 1.0
			return float(a[1]) + (float(b[1]) - float(a[1])) * ease_of(interp_of(a), u)
	return float(last[1])


## the drive's value at t (its track; 0 = the record pose when it has none)
static func value_at(asm: Dictionary, drive: String, t: float) -> float:
	var tr := track_of(asm, drive)
	return eval_keys(tr.get("keys", []), t) if not tr.is_empty() else 0.0


static func values_at(asm: Dictionary, t: float) -> Dictionary:
	var out := {}
	for d in driven(asm):
		out[d] = value_at(asm, d, t)
	return out


# ---------------------------------------------------------------- writes (the screen pushes its undo step first)

static func ensure(asm: Dictionary) -> Dictionary:
	if not (asm.get("anim", null) is Dictionary):
		asm["anim"] = {"fps": FPS, "length": LENGTH, "tracks": []}
	var a: Dictionary = asm["anim"]
	if not (a.get("tracks", null) is Array):
		a["tracks"] = []
	return a


## a key on drive's track at t (a key within half a frame of t is replaced); keys stay in time order
static func set_key(asm: Dictionary, drive: String, t: float, v: float, interp := "linear") -> void:
	var a := ensure(asm)
	var tr := track_of(asm, drive)
	if tr.is_empty():
		tr = {"drive": drive, "keys": []}
		(a["tracks"] as Array).append(tr)
	var keys: Array = tr["keys"]
	var half := 0.5 / float(fps(asm))
	for i in keys.size():
		if absf(float(keys[i][0]) - t) < half:
			keys[i] = [t, v, interp]
			return
	keys.append([t, v, interp])
	keys.sort_custom(func(x, y): return float(x[0]) < float(y[0]))


## take out drive's key within half a frame of t; an emptied track goes, and an emptied "anim" goes (the record is as it was). false: no key there
static func delete_key(asm: Dictionary, drive: String, t: float) -> bool:
	var tr := track_of(asm, drive)
	if tr.is_empty():
		return false
	var keys: Array = tr["keys"]
	var half := 0.5 / float(fps(asm))
	var hit := -1
	for i in keys.size():
		if absf(float(keys[i][0]) - t) < half and (hit < 0 or absf(float(keys[i][0]) - t) < absf(float(keys[hit][0]) - t)):
			hit = i
	if hit < 0:
		return false
	keys.remove_at(hit)
	if keys.is_empty():
		(anim(asm)["tracks"] as Array).erase(tr)
	if tracks(asm).is_empty():
		asm.erase("anim")
	return true


## the key of drive's track within half a frame of t, or []
static func key_at(asm: Dictionary, drive: String, t: float) -> Array:
	var half := 0.5 / float(fps(asm))
	for k in track_of(asm, drive).get("keys", []):
		if absf(float(k[0]) - t) < half:
			return k
	return []


static func set_length(asm: Dictionary, s: float) -> void:
	ensure(asm)["length"] = maxf(1.0 / float(fps(asm)), s)


# ---------------------------------------------------------------- playback

static func _merge(out: Dictionary, mv: Dictionary) -> void:
	for id in mv:
		out[id] = (mv[id] as Transform3D) * (out[id] as Transform3D) if out.has(id) else mv[id]


## the pose at time t, solved from the record (stateless): {"ok", "why", "moves" (part id -> Transform3D, m), "states" (the first loop's
## doubles, AssemblyLoop.world_mm reads them), "values" (drive -> value)}
static func pose_at(asm: Dictionary, t: float) -> Dictionary:
	var out := {"ok": true, "why": "", "moves": {}, "states": {}, "values": values_at(asm, t)}
	for d in driven(asm):
		var v := float(out["values"][d])
		if AssemblyLoop.has_joints(asm):
			var s := AssemblyLoop.solve(asm, d, v)
			if not bool(s["ok"]):
				out["ok"] = false
				out["why"] = "%s at %s: %s" % [d, String.num(v, 2), String(s["why"])]
			elif (out["states"] as Dictionary).is_empty():
				out["states"] = s["states"]
			_merge(out["moves"], s["moves"])
		else:
			_merge(out["moves"], AssemblyMotion.open_moves(asm, d, v))
	return out


## every frame (or the times ts), each loop frame from the last one's pose: {"ok", "why", "times", "steps": [{"t", "values", "ok", "moves",
## "states"}], "locks" [{"drive", "at", "toward", "rank"}], "unsolved" [t], "ms"}
static func frames(asm: Dictionary, ts: Array = []) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var tl: Array = ts if not ts.is_empty() else times(asm)
	var steps: Array = []
	for t in tl:
		steps.append({"t": float(t), "values": {}, "ok": true, "moves": {}, "states": {}, "why": ""})
	var out := {"ok": true, "why": "", "times": tl, "steps": steps, "locks": [], "unsolved": [], "ms": 0.0}
	for d in driven(asm):
		var vals: Array = []
		for t in tl:
			vals.append(value_at(asm, d, float(t)))
		if AssemblyLoop.has_joints(asm):
			var sw := AssemblyLoop.sweep(asm, d, vals)
			var sts: Array = sw["steps"]
			if sts.size() != tl.size():
				out["ok"] = false
				out["why"] = "%s: %s" % [d, String(sw["why"])]
				for k in tl.size():
					steps[k]["values"][d] = vals[k]
					steps[k]["ok"] = false
					_merge(steps[k]["moves"], AssemblyMotion.open_moves(asm, d, float(vals[k])))
				continue
			for l in sw["locks"]:
				(out["locks"] as Array).append({"drive": d, "at": l["at"], "toward": l["toward"], "rank": l["rank"]})
			for k in tl.size():
				var st: Dictionary = sts[k]
				steps[k]["values"][d] = vals[k]
				if not bool(st["ok"]):
					steps[k]["ok"] = false
					steps[k]["why"] = String(st.get("why", ""))
				elif (steps[k]["states"] as Dictionary).is_empty():
					steps[k]["states"] = st["states"]
				_merge(steps[k]["moves"], st["moves"])
		else:
			for k in tl.size():
				steps[k]["values"][d] = vals[k]
				_merge(steps[k]["moves"], AssemblyMotion.open_moves(asm, d, float(vals[k])))
	for st in steps:
		if not bool(st["ok"]):
			(out["unsolved"] as Array).append(st["t"])
	if not (out["unsolved"] as Array).is_empty() and String(out["why"]) == "":
		out["why"] = "%d of %d frames have no pose" % [(out["unsolved"] as Array).size(), tl.size()]
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## Check motion along the animation: every frame's poses go to AssemblyMotion.check_motion. Each clash gets "t" (s) next to "at" (the
## drive's value; drive = opts "drive", else the first keyed drive). opts "hit_mm3" as check_motion. Adds "times", "drive", "frames" (the
## frames() result without its moves) and per pair "first_t" / "worst_t". opts "refine" (default true): each pair's first clash time is
## bisected between the last clear frame and the first clashing one (_refine)
static func check(asm: Dictionary, opts := {}) -> Dictionary:
	var dl := driven(asm)
	if dl.is_empty():
		return {"ok": false, "why": "the animation has no keys: key a drive on the timeline first", "clashes": [], "by_pair": {}}
	var drive := String(opts.get("drive", dl[0]))
	if not dl.has(drive):
		drive = String(dl[0])
	var fr := frames(asm)
	var mv: Array = []
	var stt: Array = []
	var vals: Array = []
	for st in fr["steps"]:
		mv.append(st["moves"] if bool(st["ok"]) else null)
		stt.append(st["states"] if bool(st["ok"]) else {})
		vals.append(float(st["values"].get(drive, 0.0)))
	var o := {"moves": mv, "states": stt, "values": vals}
	if opts.has("hit_mm3"):
		o["hit_mm3"] = opts["hit_mm3"]
	var res := AssemblyMotion.check_motion(asm, drive, vals.size() - 1, o)
	var ts: Array = fr["times"]
	res["times"] = ts
	res["drive"] = drive
	res["frames"] = {"locks": fr["locks"], "unsolved": fr["unsolved"], "why": fr["why"], "ms": fr["ms"]}
	if AssemblyLoop.has_joints(asm):
		res["loop"] = {"locks": fr["locks"], "unsolved": fr["unsolved"]}   # AssemblyLoop.lock_words reads it
	for c in res.get("clashes", []):
		c["t"] = float(ts[int(c["k"])])
	for key in res.get("by_pair", {}):
		var r: Dictionary = res["by_pair"][key]
		r["first_t"] = null
		r["worst_t"] = null
		var worst := -1.0
		for c in res["clashes"]:
			if AssemblyMotion._pk(String(c["ida"]), String(c["idb"])) != key:
				continue
			if r["first_t"] == null:
				r["first_t"] = c["t"]
			if float(c["mm3"]) > worst:
				worst = float(c["mm3"])
				r["worst_t"] = c["t"]
	if bool(opts.get("refine", true)) and bool(res.get("ok", false)):
		_refine(asm, res, mv, drive, float(opts["hit_mm3"]) * 1e-9 if opts.has("hit_mm3") else Part.HIT_VOL)
	return res


## the onset of each pair's first clash, between the last clear frame and the first clashing one, by bisection in time (REFINE_STEPS halvings
## of one frame): "first_t" / "first" become the earliest time (and drive value) found with an overlap over hit; "first_frame_t" keeps the
## frame's. A pair that clashes from the first frame, or after a frame with no pose, keeps its frame time
const REFINE_STEPS := 14


static func _refine(asm: Dictionary, res: Dictionary, mv: Array, drive: String, hit: float) -> void:
	var ts: Array = res["times"]
	for key in res.get("by_pair", {}):
		var r: Dictionary = res["by_pair"][key]
		r["first_frame_t"] = r.get("first_t")
		var c0: Dictionary = {}
		for c in res["clashes"]:
			if AssemblyMotion._pk(String(c["ida"]), String(c["idb"])) == key:
				c0 = c
				break
		if c0.is_empty() or bool(c0["static"]) or int(c0["k"]) == 0 or mv[int(c0["k"]) - 1] == null:
			continue
		var pa: Dictionary = asm["parts"][Assembly.index_of(asm, String(c0["ida"]))]
		var pb: Dictionary = asm["parts"][Assembly.index_of(asm, String(c0["idb"]))]
		var la: Array = Part.replay(pa["rec"], -1, {"keep": true}).get("ids", [])
		var lb: Array = Part.replay(pb["rec"], -1, {"keep": true}).get("ids", [])
		var lo := float(ts[int(c0["k"]) - 1])
		var hi := float(ts[int(c0["k"])])
		for i in REFINE_STEPS:
			var mid := (lo + hi) * 0.5
			var po := pose_at(asm, mid)
			if not bool(po["ok"]):
				break
			if _pair_vol(pa, pb, la, lb, po) > hit:
				hi = mid
			else:
				lo = mid
		Part.release_kept(la)
		Part.release_kept(lb)
		r["first_t"] = hi
		r["first"] = value_at(asm, drive, hi)


## the overlap (m3) of two parts posed by pose (pose_at's result)
static func _pair_vol(pa: Dictionary, pb: Dictionary, la: Array, lb: Array, pose: Dictionary) -> float:
	var st: Dictionary = pose["states"]
	var placed: Array = []
	for pr in [[pa, la], [pb, lb]]:
		var p: Dictionary = pr[0]
		var id := String(p["id"])
		var mvs: Dictionary = pose["moves"]
		if st.has(id) and st[id] != null and st.has("_n"):
			placed.append(AssemblyMotion._place_all_state(pr[1], p, st[id], st))
		else:
			placed.append(AssemblyMotion._place_all(pr[1], (mvs[id] as Transform3D) * Assembly.xf_of(p) if mvs.has(id) else Assembly.xf_of(p)))
	var vol := 0.0
	for sa in placed[0]:
		for sb in placed[1]:
			vol += maxf(float(KCad.overlap_volume(int(sa), int(sb))), 0.0)
	for side in placed:
		for s in side:
			KCad.release(int(s))
	return vol


## one line per clashing pair: "Lid and Ceiling: from 1.87 s (65.33 deg), worst 184.0 mm3 at 2 s (70 deg)"
static func words(asm: Dictionary, res: Dictionary) -> PackedStringArray:
	var d := AssemblyMotion.drive_of(asm, String(res.get("drive", "")))
	var u := "deg" if String(d.get("kind", "rotate")) == "rotate" else "mm"
	var out := PackedStringArray()
	var bp: Dictionary = res.get("by_pair", {})
	for key in bp:
		var r: Dictionary = bp[key]
		if int(r.get("n", 0)) == 0 or r.get("first_t") == null:
			continue
		out.append("%s and %s: from %s s (%s %s), worst %.1f mm3 at %s s (%s %s)" % [r["a"], r["b"], AssemblyMotion._n(float(r["first_t"])), AssemblyMotion._n(float(r["first"])), u,
			float(r["worst_mm3"]), AssemblyMotion._n(float(r["worst_t"])), AssemblyMotion._n(float(r["worst_at"])), u])
	return out
