## ASSEMBLY STAGES (gap G33 of docs/CHALLENGE_FEEDBACK.md): the order an Assembly is built in. The record keeps two more OPTIONAL entries
## (a record without them is exactly as before):
##   "stages":     [{"name": "Walls", "parts": [part ids], "dur": 1.0 (s)}, ...] in build order. A part in no stage is there from the start
##                 (the site, the bench, the frame you build on): it is never checked and always shown.
##   "stage_opts": {"tol": mm (contact tolerance, default 0.1), "ground": mm (the ground plane's height, default 0; null = no ground),
##                  "drop": mm (each part slides down into place from this far above over its stage's time; default 0 = it just appears),
##                  "fps": frames per second of the staged video (default the animation's, 30)}
##   a part may carry "hang": [part ids]: an attachment the model does not draw (brackets, bolts, a crane hook). When the part touches
##   nothing, it still counts as held if every part it hangs from is built by its stage; the check lists it as held "by hang", never hides it.
## check(): each part added at stage k must TOUCH the ground or a part built at stages <= k (parts of the same stage hold each other only
## through a chain that reaches built parts or the ground). Touch is exact, on the posed solids (Part.replay keep, AssemblyMotion.place):
## two parts touch when they overlap, or when one moved by tol along any of the six axis directions overlaps the other more than before
## (a face within tol along an axis; a slanted face counts from tol / sqrt(3)). G45: with KineCAD 6 the touch test is ONE KCad.distance per
## solid pair instead (touching = the smallest distance <= tol, any direction), and the collision pass skips the boolean of a pair farther apart
## 0 (it cannot overlap: only d == 0, i.e. face contact, overlap or inside, needs the clash boolean); opts "touch": "overlap" keeps the seven-boolean test above (the equality check of tests/g45dist_test.gd).
## A box prefilter (KineCAD 6: each posed solid's exact-geometry box, KCad.bounds; the old path: a coarse tessellation grown by its chord error;
## both grown by tol) skips pairs that are far apart. The ground is a solid half-space under the plane. Every new part is also
## checked against the parts built before it and earlier in its stage: an overlap over Part.HIT_VOL (1 mm3) is a collision, listed in mm3.
## Time: stage k starts at the sum of the earlier stages' durations; its parts are shown from that time (pose_at); with "drop" they slide in
## over the stage's time (smooth ease). With an animation (AssemblyAnim) the drives' moves come first, the drop on top. video() films it
## through AssemblyRender (frames at (k + 1) / fps, k = 0 .. fps x total - 1: the last frame is the finished build).
class_name AssemblyStage
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const TOL_MM := 0.1
const DUR := 1.0
const DIRS := [Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
const REL_EPS := 1e-9    # a touch must add more overlap than this fraction of the smaller part's volume (the kernel's noise is far below)
const ABS_EPS := 1e-15   # m3
const BOX_DEFL := 20.0   # the prefilter's tessellation: this many times Part.fine_defl
const NEAR := 1e-6       # m (G45): only for the count: pairs apart by (0, NEAR] were asked a boolean before the d > 0 gate


static func stages(asm: Dictionary) -> Array:
	return asm["stages"] if asm.get("stages", null) is Array else []


static func has_stages(asm: Dictionary) -> bool:
	return not stages(asm).is_empty()


static func sopts(asm: Dictionary) -> Dictionary:
	return asm["stage_opts"] if asm.get("stage_opts", null) is Dictionary else {}


static func _opt(asm: Dictionary, opts: Dictionary, k: String, fallback: Variant) -> Variant:
	if opts.has(k):
		return opts[k]
	var so := sopts(asm)
	return so[k] if so.has(k) else fallback


static func tol_mm(asm: Dictionary, opts := {}) -> float:
	return maxf(0.0, float(_opt(asm, opts, "tol", TOL_MM)))


static func dur_of(st: Dictionary) -> float:
	return maxf(0.0, float(st.get("dur", DUR)))


## the stage index of a part, -1 when it is in no stage (there from the start)
static func stage_of(asm: Dictionary, id: String) -> int:
	var st := stages(asm)
	for i in st.size():
		if ((st[i] as Dictionary).get("parts", []) as Array).has(id):
			return i
	return -1


## each stage's start time (s)
static func starts(asm: Dictionary) -> Array:
	var out: Array = []
	var t := 0.0
	for s in stages(asm):
		out.append(t)
		t += dur_of(s)
	return out


static func total(asm: Dictionary) -> float:
	var t := 0.0
	for s in stages(asm):
		t += dur_of(s)
	return t


static func fps(asm: Dictionary) -> int:
	return maxi(1, int(_opt(asm, {}, "fps", AssemblyAnim.fps(asm))))


static func frame_count(asm: Dictionary) -> int:
	return int(round(total(asm) * fps(asm)))


## the staged video's frame times: (k + 1) / fps, so the last frame shows the finished build
static func frame_times(asm: Dictionary) -> Array:
	var out: Array = []
	var f := float(fps(asm))
	for k in frame_count(asm):
		out.append(float(k + 1) / f)
	return out


# ---------------------------------------------------------------- writes (the screen pushes its undo step first)

static func _ensure(asm: Dictionary) -> Array:
	if not (asm.get("stages", null) is Array):
		asm["stages"] = []
	return asm["stages"]


static func free_stage_name(asm: Dictionary) -> String:
	var taken := {}
	for s in stages(asm):
		taken[String((s as Dictionary).get("name", ""))] = true
	var i := stages(asm).size() + 1
	while taken.has("Stage %d" % i):
		i += 1
	return "Stage %d" % i


static func _take_out(asm: Dictionary, ids: Array) -> void:
	for s in stages(asm):
		var ps: Array = (s as Dictionary).get("parts", [])
		for id in ids:
			ps.erase(String(id))


## a new stage at the end with these parts (taken out of any other stage: a part is built once); answers its index
static func add_stage(asm: Dictionary, nm: String, ids: Array, dur := DUR) -> int:
	_take_out(asm, ids)
	var st := _ensure(asm)
	st.append({"name": nm if nm.strip_edges() != "" else free_stage_name(asm), "parts": ids.map(func(x): return String(x)), "dur": dur})
	return st.size() - 1


## part id joins stage i (leaving any other)
static func add_part_to(asm: Dictionary, i: int, id: String) -> bool:
	var st := stages(asm)
	if i < 0 or i >= st.size() or ((st[i] as Dictionary).get("parts", []) as Array).has(id):
		return false
	_take_out(asm, [id])
	((st[i] as Dictionary)["parts"] as Array).append(id)
	return true


## part id leaves its stage: it is there from the start
static func remove_part(asm: Dictionary, id: String) -> bool:
	if stage_of(asm, id) < 0:
		return false
	_take_out(asm, [id])
	return true


static func move_stage(asm: Dictionary, i: int, by: int) -> bool:
	var st := stages(asm)
	var j := i + by
	if i < 0 or i >= st.size() or j < 0 or j >= st.size():
		return false
	var s = st[i]
	st[i] = st[j]
	st[j] = s
	return true


static func rename_stage(asm: Dictionary, i: int, nm: String) -> bool:
	var st := stages(asm)
	if i < 0 or i >= st.size() or nm.strip_edges() == "" or String(st[i].get("name", "")) == nm.strip_edges():
		return false
	st[i]["name"] = nm.strip_edges()
	return true


static func set_dur(asm: Dictionary, i: int, s: float) -> bool:
	var st := stages(asm)
	if i < 0 or i >= st.size() or s <= 0.0 or is_equal_approx(dur_of(st[i]), s):
		return false
	st[i]["dur"] = s
	return true


## stage i goes (its parts are then there from the start); the last stage leaving takes "stages" with it, so the record is as it was
static func delete_stage(asm: Dictionary, i: int) -> bool:
	var st := stages(asm)
	if i < 0 or i >= st.size():
		return false
	st.remove_at(i)
	if st.is_empty():
		asm.erase("stages")
	return true


# ---------------------------------------------------------------- the support check

static func _box_of(sols: Array) -> AABB:
	var out := AABB()
	var first := true
	for s in sols:
		var d := BOX_DEFL * Part.fine_defl(int(s))
		var tm: ArrayMesh = KCad.tessellate(int(s), d, 0.5)
		if tm == null or tm.get_surface_count() == 0:
			continue
		var b := tm.get_aabb().grow(d)   # the chords lie within d of the surface
		out = b if first else out.merge(b)
		first = false
	return out


## G45: the same box from the kernel's exact geometry (KCad.bounds, no tessellation: the tessellated boxes took 172 of CH15's 177 s);
## a solid the kernel gives no box for falls back to _box_of
static func _bounds_of(sols: Array) -> AABB:
	var out := AABB()
	var first := true
	for s in sols:
		var b := KCad.bounds_aabb(int(s))
		if b.size == Vector3.ZERO:
			b = _box_of([s])
			if b.size == Vector3.ZERO:
				continue
		out = b if first else out.merge(b)
		first = false
	return out


static func _vol(a: Array, b: Array) -> Array:
	var v := 0.0
	var n := 0
	for sa in a:
		for sb in b:
			n += 1
			v += maxf(float(KCad.overlap_volume(int(sa), int(sb))), 0.0)
	return [v, n]


## the check (see the header): {"ok", "why", "tol_mm", "ground_mm", "placed" (parts in stages), "total" (parts), "unsupported": [{"id", "name",
## "stage", "stage_name", "why"}], "collisions": [{"id", "name", "with", "with_name", "stage", "stage_name", "mm3"}], "support": {id: {"by":
## "ground" | "contact" | "hang", "on": id | "", "stage"}}, "kernel_calls" (booleans + distances), "dist_calls", "gated" (collision booleans the
## distance made unnecessary), "skipped" (pairs the boxes ruled out), "touch" ("dist" | "overlap"), "ms"}.
## opts: "tol" (mm), "ground" (mm or null), "hit_mm3" (default Part.HIT_VOL's 1 mm3) override stage_opts; "touch": "overlap" = the old test
static func check(asm: Dictionary, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var tol := tol_mm(asm, opts) * Assembly.MM
	var gnd = _opt(asm, opts, "ground", 0.0)
	var out := {"ok": false, "why": "", "tol_mm": tol / Assembly.MM, "ground_mm": gnd, "placed": 0, "total": (asm.get("parts", []) as Array).size(), "unsupported": [],
		"collisions": [], "support": {}, "kernel_calls": 0, "skipped": 0, "ms": 0}
	var st := stages(asm)
	if st.is_empty():
		out["why"] = "no stages yet: make one from a selected part (Stages > New stage)"
		return out
	if not Part.available() or not ClassDB.class_exists("KineCAD") or not ClassDB.class_has_method("KineCAD", "overlap_volume"):
		out["why"] = "the CAD kernel with overlap_volume is missing"
		return out
	var hit := float(opts["hit_mm3"]) * 1e-9 if opts.has("hit_mm3") else Part.HIT_VOL
	var use_dist := String(opts.get("touch", "dist")) != "overlap" and KCad.has_distance()
	out["touch"] = "dist" if use_dist else "overlap"
	var pmap := {}
	var sol := {}     # id -> [posed solids]
	var box := {}     # id -> AABB (m, world)
	var vol := {}
	var shifted := {} # id -> [[solids moved by tol along DIRS[d]] per d]
	var all_box := AABB()
	var first := true
	for p in asm["parts"]:
		var id := String(p["id"])
		pmap[id] = p
		var ids: Array = Part.replay(p["rec"], -1, {"keep": true, "errors_only": true}).get("ids", [])
		sol[id] = AssemblyMotion._place_all64(ids, Assembly.xf64_of(p))
		Part.release_kept(ids)
		box[id] = _bounds_of(sol[id]) if use_dist else _box_of(sol[id])
		var v := 0.0
		for s in sol[id]:
			v += absf(KCad.volume(int(s)))
		vol[id] = v
		if (box[id] as AABB).size != Vector3.ZERO:
			all_box = box[id] if first else all_box.merge(box[id])
			first = false
	if gnd != null:   # the ground: a solid slab under the plane, wider than everything
		var g := float(gnd) * Assembly.MM
		var span := maxf(all_box.size.length(), 1.0)
		var w := all_box.size.x + 2.0 * span
		var d := all_box.size.z + 2.0 * span
		var gb: int = KCad.box(w, span, d)
		var c := all_box.get_center()
		var gs: int = KCad.translate(gb, Vector3(c.x, g - span * 0.5, c.z))
		KCad.release(gb)
		sol["_ground"] = [gs]
		box["_ground"] = AABB(Vector3(c.x - w * 0.5, g - span, c.z - d * 0.5), Vector3(w, span, d))
		vol["_ground"] = w * span * d
	var cnt := {"calls": 0, "skipped": 0, "dist_calls": 0, "gated": 0, "gated_near": 0, "bool_d0": 0}   # a lambda captures ints by value: the counts live in a Dictionary
	var memo := {}
	var ov := {}      # "a|b" (sorted) -> the overlap at rest (m3): the collision pass and the touch test share it
	var dist := {}    # G45: "a|b" (sorted) -> the smallest distance between the posed solids (m), -1 when the kernel refused a pair
	var gap := func(a: String, b: String) -> float:
		var pk := a + "|" + b if a < b else b + "|" + a
		if dist.has(pk):
			return dist[pk]
		var best := INF
		var bad := false
		for sa in sol[a]:
			for sb in sol[b]:
				cnt["dist_calls"] += 1
				var r: Dictionary = KCad.distance(int(sa), int(sb))
				if not bool(r.get("ok", false)):
					bad = true
					continue
				best = minf(best, float(r["d"]))
			if best <= 0.0:
				break
		var d := -1.0 if bad and best > 0.0 else best   # a refused solid pair: only a sure 0 stands, else the old test
		dist[pk] = d
		return d
	var touch := func(a: String, b: String) -> bool:
		var key := a + "|" + b
		if memo.has(key):
			return memo[key]
		var res := false
		if not (box[a] as AABB).grow(tol * 1.01 + 1e-9).intersects(box[b]):
			cnt["skipped"] += 1
		elif use_dist and gap.call(a, b) >= 0.0:
			res = float(gap.call(a, b)) <= tol   # touching or overlapping (an overlap over hit is also listed as a collision)
		else:
			var pk := a + "|" + b if a < b else b + "|" + a
			if not ov.has(pk):
				var r0 := _vol(sol[a], sol[b])
				cnt["calls"] += int(r0[1])
				ov[pk] = float(r0[0])
			var v0 := float(ov[pk])
			if v0 > hit:
				res = true
			else:
				var eps := maxf(ABS_EPS, REL_EPS * minf(float(vol[a]), float(vol[b])))
				if not shifted.has(a):
					shifted[a] = []
					for dv in DIRS:
						var sh: Array = []
						for s in sol[a]:
							sh.append(KCad.translate(int(s), (dv as Vector3) * tol))
						shifted[a].append(sh)
				for di in DIRS.size():
					var r := _vol(shifted[a][di], sol[b])
					cnt["calls"] += int(r[1])
					if float(r[0]) - v0 > eps:
						res = true
						break
		memo[key] = res
		return res
	var built: Array = []   # ids built so far (the parts in no stage first)
	for p in asm["parts"]:
		if stage_of(asm, String(p["id"])) < 0:
			built.append(String(p["id"]))
	var unsup: Array = []
	var coll: Array = []
	var support := {}
	var placed := 0
	for k in st.size():
		var nm := String((st[k] as Dictionary).get("name", "Stage %d" % (k + 1)))
		var now: Array = []
		for id in (st[k] as Dictionary).get("parts", []):
			if not pmap.has(String(id)):
				unsup.append({"id": String(id), "name": String(id), "stage": k, "stage_name": nm, "why": "is not in the assembly"})
				continue
			now.append(String(id))
		placed += now.size()
		# collisions: each new part against everything built before it, and the parts listed before it in its stage
		for i in now.size():
			var a := String(now[i])
			var others: Array = built + now.slice(0, i)
			for b in others:
				if not (box[a] as AABB).intersects(box[b]):
					cnt["skipped"] += 1
					continue
				var dg: float = float(gap.call(a, String(b))) if use_dist else -1.0
				if dg > 0.0:   # apart, even by less than tol: they cannot overlap, no boolean (clash volume 0)
					cnt["gated"] += 1
					cnt["gated_near"] += 1 if dg <= NEAR else 0
					ov[a + "|" + String(b) if a < String(b) else String(b) + "|" + a] = 0.0
					continue
				cnt["bool_d0"] += 1 if dg == 0.0 else 0
				var r := _vol(sol[a], sol[b])
				cnt["calls"] += int(r[1])
				ov[a + "|" + String(b) if a < String(b) else String(b) + "|" + a] = float(r[0])
				if float(r[0]) > hit:
					coll.append({"id": a, "name": String(pmap[a]["name"]), "with": String(b), "with_name": String(pmap[b]["name"]), "stage": k, "stage_name": nm, "mm3": float(r[0]) * 1e9})
		# support: a fixed point inside the stage (a chain must reach the ground or a built part)
		var held := {}
		var grew := true
		while grew:
			grew = false
			for a in now:
				if held.has(a):
					continue
				var why := {}
				if gnd != null and touch.call(a, "_ground"):
					why = {"by": "ground", "on": "", "stage": k}
				else:
					var cands: Array = built + held.keys()
					var bot := (box[a] as AABB).position.y
					cands.sort_custom(func(x, y): return absf((box[x] as AABB).end.y - bot) < absf((box[y] as AABB).end.y - bot))   # what it most likely rests on first
					for b in cands:
						if touch.call(a, String(b)):
							why = {"by": "contact", "on": String(b), "stage": k}
							break
				if why.is_empty():
					var hg: Array = pmap[a].get("hang", []) if pmap[a].get("hang", null) is Array else []
					var all_in := not hg.is_empty()
					for h in hg:
						all_in = all_in and (built.has(String(h)) or held.has(String(h)))
					if all_in:
						why = {"by": "hang", "on": String(hg[0]), "stage": k}
				if not why.is_empty():
					held[a] = true
					support[a] = why
					grew = true
		for a in now:
			if not held.has(a):
				unsup.append({"id": a, "name": String(pmap[a]["name"]), "stage": k, "stage_name": nm,
					"why": "touches no part built by then%s (tol %s mm)" % [" nor the ground" if gnd != null else "", AssemblyMotion._n(tol / Assembly.MM)]})
		built.append_array(now)   # an unsupported part is still placed: what rests on it later is judged against it
	for id in sol:
		for s in sol[id]:
			KCad.release(int(s))
	for id in shifted:
		for sh in shifted[id]:
			for s in sh:
				KCad.release(int(s))
	out["placed"] = placed
	out["unsupported"] = unsup
	out["collisions"] = coll
	out["support"] = support
	out["kernel_calls"] = cnt["calls"] + cnt["dist_calls"]
	out["dist_calls"] = cnt["dist_calls"]
	out["gated"] = cnt["gated"]
	out["gated_near"] = cnt["gated_near"]
	out["bool_d0"] = cnt["bool_d0"]
	out["skipped"] = cnt["skipped"]
	out["ok"] = unsup.is_empty() and coll.is_empty()
	out["ms"] = Time.get_ticks_msec() - t0
	return out


## one line per problem: "Roof (stage 2, Roof): touches no part built by then nor the ground (tol 0.1 mm)" / "Block x Base (stage 3, Block): 800.0 mm3"
static func words(res: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for u in res.get("unsupported", []):
		out.append("%s (stage %d, %s): %s" % [u["name"], int(u["stage"]) + 1, u["stage_name"], u["why"]])
	for c in res.get("collisions", []):
		out.append("%s x %s (stage %d, %s): overlap %.1f mm3" % [c["name"], c["with_name"], int(c["stage"]) + 1, c["stage_name"], float(c["mm3"])])
	return out


## the ids the last check flags (unsupported first, then the parts that collide)
static func flagged(res: Dictionary) -> Array:
	var out: Array = []
	for u in res.get("unsupported", []):
		if not out.has(String(u["id"])):
			out.append(String(u["id"]))
	for c in res.get("collisions", []):
		if not out.has(String(c["id"])):
			out.append(String(c["id"]))
	return out


# ---------------------------------------------------------------- time

static func _ease(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


## the build at time t: {"t", "visible": [ids shown], "moves": {id: Transform3D (m), the drives' and the drop's}, "states", "stage" (the
## stage being built at t, -1 before any / with no stages), "ok"}. opts "drop" (mm) overrides stage_opts
static func pose_at(asm: Dictionary, t: float, opts := {}) -> Dictionary:
	var base: Dictionary = AssemblyAnim.pose_at(asm, t) if AssemblyAnim.has_anim(asm) else {"ok": true, "moves": {}, "states": {}}
	var moves: Dictionary = (base["moves"] as Dictionary).duplicate()
	var out := {"t": t, "visible": [], "moves": moves, "states": base.get("states", {}), "stage": -1, "ok": bool(base.get("ok", true))}
	var st := stages(asm)
	var ss := starts(asm)
	var drop := float(_opt(asm, opts, "drop", 0.0)) * Assembly.MM
	for k in st.size():
		if t >= float(ss[k]) - 1e-9:
			out["stage"] = k
	for p in asm["parts"]:
		var id := String(p["id"])
		var k := stage_of(asm, id)
		if k < 0:
			out["visible"].append(id)
			continue
		var s0 := float(ss[k])
		if t < s0 - 1e-9:
			continue
		out["visible"].append(id)
		var d := dur_of(st[k])
		if drop > 0.0 and d > 0.0 and t < s0 + d:
			var u := clampf((t - s0) / d, 0.0, 1.0)
			var up := Transform3D(Basis.IDENTITY, Vector3(0.0, drop * (1.0 - _ease(u)), 0.0))
			moves[id] = up * (moves[id] as Transform3D) if moves.has(id) else up
	return out


## the frames for AssemblyRender: [{"t", "moves", "visible", "ok"}] at frame_times (or opts "times")
static func steps(asm: Dictionary, opts := {}) -> Array:
	var ts: Array = opts.get("times", [])
	if ts.is_empty():
		ts = frame_times(asm)
	var out: Array = []
	for t in ts:
		var po := pose_at(asm, float(t), opts)
		out.append({"t": float(t), "moves": po["moves"], "visible": po["visible"], "ok": po["ok"], "states": {}})
	return out


## films the build (await it): AssemblyRender.render with the stage frames; opts as AssemblyRender's ("dir", "width", "height", "camera",
## "view_dir", "cut", "only", "keep_images", "mp4", "sheet" ...) plus "times" and "drop". Default dir <exports>/<name>_stages_<stamp>
static func video(host: Node, asm: Dictionary, opts := {}) -> Dictionary:
	if not has_stages(asm):
		return {"ok": false, "why": "no stages yet: make one from a selected part (Stages > New stage)", "n": 0, "frames": [], "dir": "", "mp4": "", "sheet": ""}
	var o := opts.duplicate()
	o["steps"] = steps(asm, opts)
	o["fps"] = fps(asm)
	if not o.has("dir"):
		o["dir"] = "%s/%s_stages_%s" % [Assembly._out_dir(), Assembly._stem(asm), AssemblyRender._stamp()]
	return await AssemblyRender.render(host, asm, o)
