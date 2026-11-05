## ASSEMBLY MOTION (gap G1 of docs/CHALLENGE_FEEDBACK.md, the minimum of G2): drive a part of an Assembly through a range and find every pair of
## parts that passes through each other on the way. The record keeps two OPTIONAL lists (an assembly without them is exactly as before):
##   "drives": [{"name": "Lid", "part": "p2", "kind": "rotate" | "slide", "axis": [x, y, z], "origin": [mm], "range": [lo, hi]}]
##             rotate: degrees about axis through origin (right hand rule, the assembly frame); slide: mm along axis (origin unused)
##   "links":  [{"drive": "Lid", "part": "p3", "kind": "rotate" | "slide", "axis": [..], "origin": [mm], "gain": g}]
##             the follower moves by gain x the drive's value (a gear pair: gain = -z1 / z2; a rack on a pinion: gain = r_pitch x pi / 180 mm per deg)
## A driven or linked part moves from its record pose: world = motion(value) * Assembly.xf_of(part). Nothing here writes pos / rot.
## A link is open, one value in, one pose out. CLOSED loops (slider-crank, four-bar) are the optional "joints" list (G2LOOP,
## scripts/build/assembly_loop.gd): with joints, moves_at and check_motion pose the parts through the loop solver.
## check_motion() poses the parts' EXACT solids (Part.replay keep, KCad.rotate + translate) and asks KCad.overlap_volume (C70) for each pair whose
## boxes meet (1 mm grown). An overlap of Part.HIT_VOL (1 mm3) or less is contact, not a clash. Two parts that both stay still are checked once.
class_name AssemblyMotion
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const BOX_GROW := 1e-3   # m: a tessellated box can sit inside the exact solid by the chord error; 1 mm covers it


static func drives(asm: Dictionary) -> Array:
	return asm.get("drives", []) if asm.get("drives", null) is Array else []


static func links(asm: Dictionary) -> Array:
	return asm.get("links", []) if asm.get("links", null) is Array else []


static func drive_of(asm: Dictionary, nm: String) -> Dictionary:
	for d in drives(asm):
		if String((d as Dictionary).get("name", "")) == nm:
			return d
	return {}


static func make_drive(nm: String, part: String, kind: String, axis: Vector3, origin_mm: Vector3, lo: float, hi: float) -> Dictionary:
	return {"name": nm, "part": part, "kind": kind, "axis": [axis.x, axis.y, axis.z], "origin": [origin_mm.x, origin_mm.y, origin_mm.z], "range": [lo, hi]}


static func make_link(drive: String, part: String, kind: String, axis: Vector3, origin_mm: Vector3, gain: float) -> Dictionary:
	return {"drive": drive, "part": part, "kind": kind, "axis": [axis.x, axis.y, axis.z], "origin": [origin_mm.x, origin_mm.y, origin_mm.z], "gain": gain}


## put a drive in the record (the same name replaces); the only write this file makes
static func set_drive(asm: Dictionary, d: Dictionary) -> void:
	var ds: Array = drives(asm).duplicate()
	for i in ds.size():
		if String((ds[i] as Dictionary).get("name", "")) == String(d["name"]):
			ds[i] = d
			asm["drives"] = ds
			return
	ds.append(d)
	asm["drives"] = ds


static func free_drive_name(asm: Dictionary, base: String) -> String:
	if drive_of(asm, base).is_empty():
		return base
	var i := 2
	while not drive_of(asm, "%s %d" % [base, i]).is_empty():
		i += 1
	return "%s %d" % [base, i]


static func _v3(a: Variant, fallback := Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## the world move of a motion (metres): rotate deg about axis through origin_mm, or slide mm along axis
static func motion_xf(kind: String, axis: Vector3, origin_mm: Vector3, value: float) -> Transform3D:
	var ax := axis.normalized() if axis.length() > 1e-12 else Vector3.BACK
	if kind == "slide":
		return Transform3D(Basis.IDENTITY, ax * value * Assembly.MM)
	var o := origin_mm * Assembly.MM
	var b := Basis(ax, deg_to_rad(value))
	return Transform3D(b, o - b * o)


## the drive's values at steps + 1 samples, both ends included: lo + (hi - lo) k / steps
static func values(d: Dictionary, steps: int) -> Array:
	var r: Array = d.get("range", [0.0, 0.0])
	var lo := float(r[0])
	var hi := float(r[1])
	var n := maxi(steps, 1)
	var out: Array = []
	for k in n + 1:
		out.append(lo + (hi - lo) * float(k) / float(n))
	return out


## the value (deg or mm, float64) that part pid is moved by when the drive is at v: v for the driven part, gain x v for a link, 0 otherwise
static func value_of(asm: Dictionary, drive_name: String, v: float, pid: String) -> float:
	var d := drive_of(asm, drive_name)
	if d.is_empty():
		return 0.0
	if String(d["part"]) == pid:
		return v
	for l in links(asm):
		if String((l as Dictionary).get("drive", "")) == drive_name and String(l["part"]) == pid:
			return float(l.get("gain", 1.0)) * v
	return 0.0


## part id -> its world move at the drive's value v (only the parts the drive moves). With "joints" (G2LOOP) the loop solver poses every part
## the joints tie to the drive (scripts/build/assembly_loop.gd); when it finds no pose, only the driven part and its links move
static func moves_at(asm: Dictionary, drive_name: String, v: float) -> Dictionary:
	if AssemblyLoop.has_joints(asm):
		return AssemblyLoop.solve(asm, drive_name, v)["moves"]
	return open_moves(asm, drive_name, v)


## the open chain (G1MOTION): the driven part and its links only
static func open_moves(asm: Dictionary, drive_name: String, v: float) -> Dictionary:
	var out := {}
	var d := drive_of(asm, drive_name)
	if d.is_empty():
		return out
	out[String(d["part"])] = motion_xf(String(d.get("kind", "rotate")), _v3(d.get("axis"), Vector3.BACK), _v3(d.get("origin")), v)
	for l in links(asm):
		if String((l as Dictionary).get("drive", "")) != drive_name:
			continue
		var pid := String(l["part"])
		var mv := motion_xf(String(l.get("kind", "rotate")), _v3(l.get("axis"), Vector3.BACK), _v3(l.get("origin")), float(l.get("gain", 1.0)) * v)
		out[pid] = mv * out[pid] if out.has(pid) else mv
	return out


## a part's place (metres) with the drive at v
static func xf_at(asm: Dictionary, drive_name: String, v: float, p: Dictionary) -> Transform3D:
	var mv: Dictionary = moves_at(asm, drive_name, v)
	var x0 := Assembly.xf_of(p)
	return (mv[String(p["id"])] as Transform3D) * x0 if mv.has(String(p["id"])) else x0


## a NEW solid: src (its own frame, metres) carried by the rigid transform xf: one turn about the origin, then one move
static func place(src: int, xf: Transform3D) -> int:
	var q := xf.basis.orthonormalized().get_rotation_quaternion()
	var s := src
	var ang := q.get_angle()
	if absf(ang) > 1e-12:
		var ax := q.get_axis()
		if ax.length() > 1e-9:
			s = KCad.rotate(src, ax.normalized(), ang)
			if s == 0:
				return 0
	var m: int = KCad.translate(s, xf.origin)
	if s != src:
		KCad.release(s)
	return m


static func _pk(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## the sweep. {"ok", "why", "clashes": [{"a", "b" (names), "ida", "idb", "at" (drive value), "mm3", "static"}], "by_pair": {"ida|idb": {"a", "b", "first", "worst_at", "worst_mm3", "n"}},
## "pairs" (pairs looked at), "kernel_calls" (overlap_volume calls), "skipped" (pair checks the boxes ruled out), "steps", "values", "moving" (ids), "ms"}
## opts: "prefilter" (default true): false asks the kernel about every pair (a test counts the calls by hand); "hit_mm3": the overlap that counts
## as a clash (default Part.HIT_VOL, 1 mm3). With "joints" (G2LOOP) the parts follow the loop solver's sweep (AssemblyLoop.sweep, each step from
## the last); a step with no pose is not checked, and "loop" = {"locks", "unsolved", "iters_total", "iters_max", "ms"}
static func check_motion(asm: Dictionary, drive_name: String, steps: int, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var out := {"ok": false, "why": "", "clashes": [], "by_pair": {}, "pairs": 0, "kernel_calls": 0, "skipped": 0, "steps": steps, "values": [], "moving": [], "ms": 0}
	var d := drive_of(asm, drive_name)
	if d.is_empty():
		out["why"] = "the assembly has no drive called '%s'" % drive_name
		return out
	if not Part.available() or not ClassDB.class_exists("KineCAD") or not ClassDB.class_has_method("KineCAD", "overlap_volume"):
		out["why"] = "the CAD kernel with overlap_volume is missing"
		return out
	var prefilter := bool(opts.get("prefilter", true))
	var hit_vol := float(opts["hit_mm3"]) * 1e-9 if opts.has("hit_mm3") else Part.HIT_VOL
	var ps: Array = asm["parts"]
	var vals := values(d, steps)
	out["values"] = vals
	var track: Array = []   # G2LOOP: the moves at each value (null: no pose)
	var tstates: Array = [] # and the solver's planar states (doubles), which place the solids without float32 (G4)
	var moving: Array = []
	if AssemblyLoop.has_joints(asm):
		var sw := AssemblyLoop.sweep(asm, drive_name, vals)
		if int(sw["n"]) == 0 and not bool(sw["ok"]) and (sw["steps"] as Array).is_empty():
			out["why"] = String(sw["why"])
			return out
		out["loop"] = {"locks": sw["locks"], "unsolved": sw["unsolved"], "iters_total": sw["iters_total"], "iters_max": sw["iters_max"], "ms": sw["ms"], "why": sw["why"]}
		for st in sw["steps"]:
			track.append(st["moves"] if bool(st["ok"]) else null)
			tstates.append(st["states"] if bool(st["ok"]) else {})
			if bool(st["ok"]):
				for id in st["moves"]:
					if not moving.has(id):
						moving.append(id)
		if moving.is_empty():
			out["why"] = "the loop solver found no pose at any step: " + String(sw["why"])
			return out
	else:
		moving = moves_at(asm, drive_name, float(vals[0])).keys()
	out["moving"] = moving
	var local := {}    # id -> [solid ids] in the part's own frame
	var box := {}      # id -> AABB, own frame (m)
	var kept: Array = []
	for p in ps:
		var id := String(p["id"])
		var ids: Array = Part.replay(p["rec"], -1, {"keep": true}).get("ids", [])
		local[id] = ids
		kept.append_array(ids)
		box[id] = Assembly.built(p["rec"])["aabb"]
	var frame: Dictionary = {}
	for s in tstates:
		if (s as Dictionary).has("_n"):
			frame = s
			break
	var placed_static := {}
	for p in ps:
		var id := String(p["id"])
		if not moving.has(id):
			placed_static[id] = _place_all_state(local[id], p, [0.0, 0.0, 0.0, 0.0], frame) if not frame.is_empty() else _place_all(local[id], Assembly.xf_of(p))
	var by_pair := {}
	var clashes: Array = []
	var calls := 0
	var skipped := 0
	var bad := false
	var first_k := -1   # the first step with a pose: two still parts are checked there
	for k in vals.size():
		var v := float(vals[k])
		if not track.is_empty() and track[k] == null:
			continue
		if first_k < 0:
			first_k = k
		var mv: Dictionary = track[k] if not track.is_empty() else open_moves(asm, drive_name, v)
		var placed := placed_static.duplicate()
		var wbox := {}
		for p in ps:
			var id := String(p["id"])
			var xf: Transform3D = (mv[id] as Transform3D) * Assembly.xf_of(p) if mv.has(id) else Assembly.xf_of(p)
			wbox[id] = (xf * (box[id] as AABB)).grow(BOX_GROW)
			if mv.has(id):
				var sk: Dictionary = tstates[k] if not tstates.is_empty() else {}
				placed[id] = _place_all_state(local[id], p, sk[id], sk) if sk.has(id) and sk[id] != null else _place_all(local[id], xf)
		for i in ps.size():
			for j in range(i + 1, ps.size()):
				var a: Dictionary = ps[i]
				var b: Dictionary = ps[j]
				var ia := String(a["id"])
				var ib := String(b["id"])
				var still := not mv.has(ia) and not mv.has(ib)
				if still and k > first_k:
					continue   # two parts that never move: once is enough
				var key := _pk(ia, ib)
				if not by_pair.has(key):
					by_pair[key] = {"a": String(a["name"]), "b": String(b["name"]), "first": null, "worst_at": null, "worst_mm3": 0.0, "n": 0}
				var vol := 0.0
				if prefilter and not (wbox[ia] as AABB).intersects(wbox[ib]):
					skipped += 1
				else:
					for sa in placed[ia]:
						for sb in placed[ib]:
							calls += 1
							var o: float = KCad.overlap_volume(int(sa), int(sb))
							if o < 0.0:
								bad = true
							vol += maxf(o, 0.0)
				if vol > hit_vol:
					var row: Dictionary = by_pair[key]
					row["n"] = int(row["n"]) + 1
					if row["first"] == null:
						row["first"] = v
					if vol * 1e9 > float(row["worst_mm3"]):
						row["worst_mm3"] = vol * 1e9
						row["worst_at"] = v
					clashes.append({"a": String(a["name"]), "b": String(b["name"]), "ida": ia, "idb": ib, "at": v, "mm3": vol * 1e9, "static": still})
		for id in mv:
			for s in placed[id]:
				KCad.release(int(s))
	for id in placed_static:
		for s in placed_static[id]:
			KCad.release(int(s))
	Part.release_kept(kept)
	out["clashes"] = clashes
	out["by_pair"] = by_pair
	out["pairs"] = by_pair.size()
	out["kernel_calls"] = calls
	out["skipped"] = skipped
	out["ok"] = not bad
	out["why"] = "the kernel refused an overlap" if bad else ""
	out["ms"] = Time.get_ticks_msec() - t0
	return out


## G2LOOP: a NEW solid placed in doubles: the record's turn as Basis.from_euler does it (z, then x, then y), the loop state's turn phi about
## the common axis, then one move computed in doubles (only the final Vector3 is float32, ~1e-5 mm at 100 mm, as ch13_parts.place)
static func place_state(src: int, p: Dictionary, s: Array, frame: Dictionary) -> int:
	var rot: Array = p["rot"]
	var cur := src
	var n: Array = frame["_n"]
	for step in [[Vector3.BACK, deg_to_rad(float(rot[2]))], [Vector3.RIGHT, deg_to_rad(float(rot[0]))], [Vector3.UP, deg_to_rad(float(rot[1]))], [Vector3(n[0], n[1], n[2]), float(s[2])]]:
		if absf(float(step[1])) > 1e-15:
			var t: int = KCad.rotate(cur, step[0], float(step[1]))
			if cur != src:
				KCad.release(cur)
			cur = t
			if cur == 0:
				return 0
	var T := AssemblyLoop.apply_state(AssemblyLoop._arr(p["pos"]), s, frame)
	var m: int = KCad.translate(cur, Vector3(T[0], T[1], T[2]) * Assembly.MM)
	if cur != src:
		KCad.release(cur)
	return m


static func _place_all_state(ids: Array, p: Dictionary, s: Array, frame: Dictionary) -> Array:
	var out: Array = []
	for sid in ids:
		var n := place_state(int(sid), p, s, frame)
		if n != 0:
			out.append(n)
	return out


static func _place_all(ids: Array, xf: Transform3D) -> Array:
	var out: Array = []
	for s in ids:
		var n := place(int(s), xf)
		if n != 0:
			out.append(n)
	return out


## the pairs that clash at the sample nearest v: [[ida, idb], ...]
static func clashing_at(res: Dictionary, v: float) -> Array:
	var vals: Array = res.get("values", [])
	if vals.is_empty():
		return []
	var best := float(vals[0])
	for x in vals:
		if absf(float(x) - v) < absf(best - v):
			best = float(x)
	var out: Array = []
	for c in res.get("clashes", []):
		if bool(c["static"]) or is_equal_approx(float(c["at"]), best):
			out.append([String(c["ida"]), String(c["idb"])])
	return out


## one line per clashing pair: "Lid and Wall: from 70 deg, worst 207.1 mm3 at 70 deg"
static func words(asm: Dictionary, drive_name: String, res: Dictionary) -> PackedStringArray:
	var d := drive_of(asm, drive_name)
	var u := "deg" if String(d.get("kind", "rotate")) == "rotate" else "mm"
	var out := PackedStringArray()
	var bp: Dictionary = res.get("by_pair", {})
	for key in bp:
		var r: Dictionary = bp[key]
		if int(r["n"]) == 0:
			continue
		out.append("%s and %s: from %s %s, worst %.1f mm3 at %s %s" % [r["a"], r["b"], _n(float(r["first"])), u, float(r["worst_mm3"]), _n(float(r["worst_at"])), u])
	return out


static func _n(v: float) -> String:
	return String.num(v, 2).rstrip("0").rstrip(".") if absf(v - roundf(v)) > 1e-6 else str(int(roundf(v)))
