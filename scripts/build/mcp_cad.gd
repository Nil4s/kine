## MCPFAST: the CAD tools of the local Kine MCP, over the ONE live `poser_cli serve` session (docs/MCPFAST_FEEDBACK.md).
##   cad_part  {name, record|path} build / replay a Part record; cached by the record's hash (same record = no replay; a changed record = rebuilt)
##   cad_asm   {ops: [...]}       one call runs N steps on the live assembly: new, load, add, place, remove, joint, drive, drive_to
##   check_fit {near_mm, hit_mm3} every pair of placed parts: overlap volume (mm3) and distance (mm), exact solids
##   bom       {}                 the assembly's bill of materials
##   eval_gd   {code}             a short GDScript snippet in the live session (sandbox below)
##   cad_reset {cache, asm}
##   look4d    {level, part, t, since, image}  the live assembly as a zoomable digest (scripts/build/look4d.gd): level 0 one line, 1 parts + contacts, 2 one part, 3 a track, since = a delta
##   sweep     {drive|param, from, to, steps}  a drive or parameter sweep reduced to ONE summary (worst value, where, count over a threshold)
## Replies are terse by default (ids, not records; only what changed); detail: true gives everything. Numbers are rounded to prec decimals (3).
## Not in AgentTools.METHODS (the transcript's ready line); advertised by tools/mcp/poser_mcp.py with --cad.
##
## SANDBOX of eval_gd (best effort, for an agent testing its own idea, not a defence against a hostile one): the snippet is scanned and refused when
## it names OS / FileAccess / DirAccess / ResourceSaver / ClassDB / Engine / ... or a save* / store_* / write* / export* / ... call. Its one way to write
## is H.write(path, text), which accepts only res://scenes/_wip/ and the temp directory. Anything else is refused and eval_gd answers with the error.
class_name McpCad
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const OPS := ["new", "load", "add", "place", "remove", "joint", "drive", "drive_to"]
const BAN_WORDS := ["OS", "FileAccess", "DirAccess", "ResourceSaver", "ResourceLoader", "ClassDB", "Engine", "JavaClassWrapper", "JavaScriptBridge", "Expression",
	"GDScript", "Thread", "Mutex", "Semaphore", "ProjectSettings", "ConfigFile", "EditorInterface", "load", "call", "callv", "call_deferred", "Callable",
	"quit", "execute", "kill", "set_script", "get_tree", "move_to_trash", "create_process", "shell_open", "XMLParser", "HTTPRequest", "HTTPClient", "TCPServer",
	"StreamPeerTCP", "PacketPeerUDP", "UDPServer", "WebSocketPeer", "DisplayServer", "NativeExtension", "GDExtensionManager", "ZIPPacker", "ZIPReader"]
const BAN_RE := "\\b(?:save\\w*|store_\\w+|write\\w*|export\\w*|dump\\w*|make_dir\\w*|rename\\w*|copy\\w*|remove_dir\\w*|set_script|open\\w*|\\w*_file)\\b"

static var parts := {}        # name -> hash
static var cache := {}        # hash -> {"rec", "ids" (kept solids), "aabbs" (local, m), "sum"}
static var placed := {}       # "hash|pos|rot" -> solid id (a part at a place, built once)
static var asm := {}
static var pairs := {}        # "keyA|keyB|d" -> [overlap m3, distance m] (a part at a place = hash + transform)
static var last := {}         # part id -> [pos, rot] as the last reply told it (so the next reply gives only what moved)
static var pose := {}         # {"drive", "v"} set by drive_to
static var stat := {"replays": 0, "hits": 0, "kernel": 0}


static func serve(m: Node, method: String, p: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var r: Dictionary
	match method:
		"cad_part":
			r = cad_part(p)
		"cad_asm":
			r = cad_asm(p)
		"check_fit":
			r = check_fit(p)
		"bom":
			r = bom(p)
		"eval_gd":
			r = eval_gd(m, p)
		"cad_reset":
			r = reset(p)
		_:
			r = {"ok": false, "error": "no cad method '%s'" % method}
	if r["ok"] and bool(p.get("detail", false)):
		r["result"]["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
		r["result"]["stats"] = stat.duplicate()
	if r["ok"]:
		r["result"] = rnd(r["result"], int(p.get("prec", 3)))
	return r


static func fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


static func good(d: Dictionary) -> Dictionary:
	return {"ok": true, "result": d}


## numbers rounded to prec decimals, all the way down; Vector3 / AABB become arrays
static func rnd(v: Variant, prec: int) -> Variant:
	if v is float:
		return snappedf(v, pow(10.0, -prec)) if absf(v) < 1e15 else v
	if v is Array:
		var o := []
		for x in v:
			o.append(rnd(x, prec))
		return o
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = rnd(v[k], prec)
		return d
	if v is Vector3:
		return rnd([v.x, v.y, v.z], prec)
	return v


static func rec_hash(rec: Dictionary) -> String:
	return JSON.stringify(rec, "", true).md5_text().left(12)


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path if path.begins_with("res://") or path.is_absolute_path() else "res://" + path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else null


# ---------------------------------------------------------------- parts

static func _drop(h: String) -> void:
	if not cache.has(h):
		return
	for k in placed.keys():
		if String(k).begins_with(h + "|"):
			KCad.release(int(placed[k]))
			placed.erase(k)
	for b in cache[h]["ids"]:
		KCad.release(int(b))
	cache.erase(h)


## the part in the cache for this record: {"hit": bool, "hash"}; builds (and keeps the exact solids) when not there
static func ensure(rec: Dictionary) -> Dictionary:
	var h := rec_hash(rec)
	if cache.has(h):
		stat["hits"] += 1
		return {"hit": true, "hash": h}
	if not Part.available():
		return {"hash": "", "error": Part.why_not()}
	stat["replays"] += 1
	var res := Part.replay(rec, -1, {"keep": true, "defer_tess": true})   # no tessellation: the exact solids are all this needs
	var ids: Array = res.get("ids", [])
	var aabbs: Array = []
	var vols: Array = []
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var vol := 0.0
	for b in ids:
		var bb: AABB = KCad.bounds_aabb(int(b))
		aabbs.append(bb)
		lo = lo.min(bb.position)
		hi = hi.max(bb.end)
		var v: float = KCad.volume(int(b))
		vols.append(v / (MM * MM * MM))
		vol += v
	var errs: Dictionary = res.get("errors", {})
	var sum := {"bodies": ids.size(), "volume_mm3": vol / (MM * MM * MM), "size_mm": (hi - lo) / MM if not ids.is_empty() else Vector3.ZERO,
		"min_mm": lo / MM if not ids.is_empty() else Vector3.ZERO, "errors": errs, "vols": vols, "steps": (rec.get("features", []) as Array).size()}
	cache[h] = {"rec": rec, "ids": ids, "aabbs": aabbs, "sum": sum}
	return {"hit": false, "hash": h}


static func cad_part(p: Dictionary) -> Dictionary:
	var nm := String(p.get("name", ""))
	var rec: Dictionary = {}
	if p.get("record") is Dictionary:
		rec = p["record"]
	elif p.has("path"):
		var j: Variant = _read_json(String(p["path"]))
		if j is Dictionary:
			rec = j
		else:
			return fail("cannot read a Part record from '%s'" % p["path"])
	elif nm != "" and parts.has(nm) and cache.has(parts[nm]):
		rec = cache[parts[nm]]["rec"]
	else:
		return fail("cad_part needs {name, record: {features: [...]}} or {name, path}; or a name already built")
	if nm == "":
		nm = String(rec.get("name", "Part"))
	var old := String(parts.get(nm, ""))
	var e := ensure(rec)
	if e.has("error"):
		return fail(String(e["error"]))
	var h := String(e["hash"])
	var changed := old != "" and old != h
	if changed:   # the name now has another record: the old one goes unless another name still uses it
		var used := false
		for k in parts:
			if k != nm and parts[k] == old:
				used = true
		if not used:
			_drop(old)
	parts[nm] = h
	var s: Dictionary = cache[h]["sum"]
	var out := {"name": nm, "hash": h, "cached": bool(e["hit"]), "bodies": s["bodies"], "volume_mm3": s["volume_mm3"], "size_mm": s["size_mm"]}
	if changed:
		out["replaced"] = old
	if not (s["errors"] as Dictionary).is_empty():
		out["errors"] = s["errors"]
	if bool(p.get("detail", false)):
		out["min_mm"] = s["min_mm"]
		out["volumes_mm3"] = s["vols"]
		out["steps"] = s["steps"]
	return good(out)


# ---------------------------------------------------------------- assembly

static func _arr3(v: Variant, dflt: Array) -> Array:
	if v is Array and (v as Array).size() >= 3:
		return [float(v[0]), float(v[1]), float(v[2])]
	return dflt


static func _snap_pose() -> Dictionary:
	var o := {}
	for q in asm.get("parts", []):
		o[String(q["id"])] = [(q["pos"] as Array).duplicate(), (q["rot"] as Array).duplicate()]
	return o


static func cad_asm(p: Dictionary) -> Dictionary:
	if not (p.get("ops") is Array) or (p["ops"] as Array).is_empty():
		return fail("cad_asm needs {ops: [{op: %s, ...}]}: new {name} | load {assembly} | add {part, id?, name?, pos?, rot?} | place {id, pos?, rot?} | remove {id} | joint {kind, a, b, axis, origin, origin_b?, name?} | drive {name, part, kind, axis, origin, range} | drive_to {drive, value}" % "|".join(OPS))
	if asm.is_empty():
		asm = Assembly.make("Assembly")
	var added := []
	var notes := []
	var n := 0
	for op in p["ops"]:
		n += 1
		if not (op is Dictionary):
			return fail("op %d is not an object" % n)
		var kind := String(op.get("op", ""))
		match kind:
			"new":
				asm = Assembly.make(String(op.get("name", "Assembly")))
				last = {}
				pose = {}
			"load":
				if not (op.get("assembly") is Dictionary) or not Assembly.is_assembly(op["assembly"]):
					return fail("op %d: load needs {assembly: <an assembly record>}" % n)
				asm = (op["assembly"] as Dictionary).duplicate(true)
				last = {}
				pose = {}
				for q in asm["parts"]:   # its records go in the cache by hash: the same record twice is built once
					var e := ensure(q["rec"])
					if e.has("error"):
						return fail("op %d: %s" % [n, e["error"]])
					parts[String(q["name"])] = String(e["hash"])
					added.append([q["id"], q["name"]])
			"add":
				var pn := String(op.get("part", ""))
				if not parts.has(pn) or not cache.has(parts[pn]):
					return fail("op %d: no built part '%s' (cad_part first); built: %s" % [n, pn, ", ".join(parts.keys())])
				asm["seq"] = int(asm["seq"]) + 1
				var id := String(op.get("id", "p%d" % int(asm["seq"])))
				if Assembly.index_of(asm, id) >= 0:
					return fail("op %d: the id '%s' is taken" % [n, id])
				var nm := Assembly.free_name(asm, String(op.get("name", pn)))
				(asm["parts"] as Array).append({"id": id, "name": nm, "src": "", "rec": cache[parts[pn]]["rec"], "pos": _arr3(op.get("pos"), [0.0, 0.0, 0.0]), "rot": _arr3(op.get("rot"), [0.0, 0.0, 0.0])})
				added.append([id, nm])
			"place":
				var i := Assembly.index_of(asm, String(op.get("id", "")))
				if i < 0:
					return fail("op %d: no part with id '%s'" % [n, op.get("id", "")])
				var q: Dictionary = asm["parts"][i]
				q["pos"] = _arr3(op.get("pos"), q["pos"])
				q["rot"] = _arr3(op.get("rot"), q["rot"])
			"remove":
				if not Assembly.remove_part(asm, String(op.get("id", ""))):
					return fail("op %d: no part with id '%s'" % [n, op.get("id", "")])
			"joint":
				for k in ["kind", "a", "b", "axis", "origin"]:
					if not op.has(k):
						return fail("op %d: joint needs kind (revolute|fixed|slider|...), a, b (a part id or ground), axis [x,y,z], origin [x,y,z] in a's frame" % n)
				AssemblyLoop.add_joint(asm, AssemblyLoop.make_joint(String(op["kind"]), String(op["a"]), String(op["b"]), op["axis"], op["origin"], op.get("origin_b", []), String(op.get("name", ""))))
			"drive":
				var rg: Array = op.get("range", [0.0, 360.0])
				AssemblyMotion.set_drive(asm, AssemblyMotion.make_drive(String(op.get("name", "Drive")), String(op.get("part", "")), String(op.get("kind", "rotate")),
					Vector3(_arr3(op.get("axis"), [0.0, 0.0, 1.0])[0], _arr3(op.get("axis"), [0.0, 0.0, 1.0])[1], _arr3(op.get("axis"), [0.0, 0.0, 1.0])[2]),
					Vector3(_arr3(op.get("origin"), [0.0, 0.0, 0.0])[0], _arr3(op.get("origin"), [0.0, 0.0, 0.0])[1], _arr3(op.get("origin"), [0.0, 0.0, 0.0])[2]), float(rg[0]), float(rg[1])))
			"drive_to":
				var dn := String(op.get("drive", ""))
				if AssemblyMotion.drive_of(asm, dn).is_empty():
					return fail("op %d: no drive '%s'" % [n, dn])
				pose = {"drive": dn, "v": float(op.get("value", 0.0))}
				if AssemblyLoop.has_joints(asm):
					var sv := AssemblyLoop.solve(asm, dn, float(pose["v"]))
					if not bool(sv["ok"]):
						notes.append("drive_to: the loop has no pose here: %s" % sv["why"])
			_:
				return fail("op %d: no op '%s'; the ops are %s" % [n, kind, ", ".join(OPS)])
	# the reply: ids and names of what was added, and only the places that changed since the last reply
	var now := _poses()
	var chg := {}
	for id in now:
		if not last.has(id) or JSON.stringify(last[id]) != JSON.stringify(now[id]):
			chg[id] = now[id]
	last = now.duplicate(true)
	var out := {"asm": asm["name"], "n": (asm["parts"] as Array).size(), "added": added, "moved": chg, "joints": AssemblyLoop.joints(asm).size(), "drives": AssemblyMotion.drives(asm).size()}
	if not notes.is_empty():
		out["notes"] = notes
	if bool(p.get("detail", false)):
		var names := {}
		for q in asm["parts"]:
			names[q["id"]] = q["name"]
		out["names"] = names
		out["all"] = now
		out["pose"] = pose
	return good(out)


## part id -> [pos mm, rot deg] as placed now (with the drive at its value, when drive_to set one)
static func _poses() -> Dictionary:
	var o := {}
	for q in asm.get("parts", []):
		var xf := _xf(q)
		if pose.is_empty():
			o[String(q["id"])] = [(q["pos"] as Array).duplicate(), (q["rot"] as Array).duplicate()]
		else:
			var e := xf.basis.get_euler()
			o[String(q["id"])] = [[xf.origin.x / MM, xf.origin.y / MM, xf.origin.z / MM], [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)]]
	return o


static var _moves_key := ""
static var _moves := {}


static func _xf(q: Dictionary) -> Transform3D:
	if pose.is_empty():
		return Assembly.xf_of(q)
	var key := JSON.stringify([pose, asm.get("joints", []), asm.get("drives", []), asm.get("links", []), _poses_raw()])
	if key != _moves_key:
		_moves = AssemblyMotion.moves_at(asm, String(pose["drive"]), float(pose["v"]))
		_moves_key = key
	var x0 := Assembly.xf_of(q)
	return (_moves[String(q["id"])] as Transform3D) * x0 if _moves.has(String(q["id"])) else x0


static func _poses_raw() -> Array:
	var o := []
	for q in asm.get("parts", []):
		o.append([q["id"], q["pos"], q["rot"]])
	return o


# ---------------------------------------------------------------- check_fit

static func _world_box(local: AABB, xf: Transform3D) -> AABB:
	var b := AABB(xf * local.position, Vector3.ZERO)
	for i in 8:
		b = b.expand(xf * local.get_endpoint(i))
	return b


static func _box_gap(a: AABB, b: AABB) -> float:   # the distance between two boxes (m): a lower bound of the distance between what is inside them
	var d := Vector3(maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x)), maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y)), maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z)))
	return d.length()


static func _placed(h: String, k: int, src: int, xf: Transform3D) -> int:
	var key := "%s|%d|%s" % [h, k, var_to_str(xf)]
	if placed.has(key):
		return int(placed[key])
	if placed.size() > 400:
		for v in placed.values():
			KCad.release(int(v))
		placed.clear()
	var s := AssemblyMotion.place(src, xf)
	placed[key] = s
	return s


static func check_fit(p: Dictionary) -> Dictionary:
	if asm.is_empty() or (asm["parts"] as Array).is_empty():
		return fail("no assembly: cad_asm first")
	if not ClassDB.class_exists("KineCAD") or not ClassDB.class_has_method("KineCAD", "overlap_volume"):
		return fail("the CAD kernel with overlap_volume is missing")
	var near_mm := float(p.get("near_mm", 2.0))
	var hit := float(p.get("hit_mm3", 1.0))
	if p.has("drive") and p.has("value"):
		pose = {"drive": String(p["drive"]), "v": float(p["value"])}
	var items := []   # {id, box, solids: [placed ids]}
	for q in asm["parts"]:
		var pn := String(q["name"])
		var h := rec_hash(q["rec"])
		if not cache.has(h):
			var e := ensure(q["rec"])
			if e.has("error"):
				return fail(String(e["error"]))
		var c: Dictionary = cache[h]
		var xf := _xf(q)
		var sol := []
		var box := AABB()
		for k in (c["ids"] as Array).size():
			sol.append(_placed(h, k, int(c["ids"][k]), xf))
			var wb := _world_box(c["aabbs"][k], xf)
			box = wb if k == 0 else box.merge(wb)
		items.append({"id": String(q["id"]), "box": box, "sol": sol, "key": "%s@%s" % [h, var_to_str(xf)]})
	var all := []
	var overlaps := []
	var near := []
	var kernel := 0
	var skipped := 0
	var total := 0.0
	var has_d := KCad.has_distance() and bool(p.get("distance", p.get("detail", false)))   # the exact distance is the slow call (OCCT, 0.1-0.3 s a pair); overlaps are 1-10 ms
	var prof := [0, 0, 0]   # distance us, overlap us, overlap calls
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			if _box_gap(a["box"], b["box"]) > near_mm * MM:
				skipped += 1
				all.append([a["id"], b["id"], 0.0, null])
				continue
			var pk := "%s|%s|%d" % [a["key"], b["key"], 1 if has_d else 0]
			var ov := 0.0
			var dm := INF
			if pairs.has(pk):   # the same two parts at the same two places: the answer is the same, no kernel call
				ov = pairs[pk][0]
				dm = pairs[pk][1]
			else:
				for sa in a["sol"]:
					for sb in b["sol"]:
						kernel += 1
						var tk := Time.get_ticks_usec()
						var dd: Dictionary = KCad.distance(int(sa), int(sb)) if has_d else {}
						prof[0] += Time.get_ticks_usec() - tk
						if bool(dd.get("ok", false)):
							dm = minf(dm, float(dd["d"]))
							if float(dd["d"]) > 0.0 and not bool(dd.get("inner", false)):
								continue   # apart: no volume in common (one distance, no boolean: the G45 route)
						tk = Time.get_ticks_usec()
						ov += maxf(0.0, KCad.overlap_volume(int(sa), int(sb)))
						prof[1] += Time.get_ticks_usec() - tk
						prof[2] += 1
				if pairs.size() > 4000:
					pairs.clear()
				pairs[pk] = [ov, dm]
			var ovm := ov / (MM * MM * MM)
			var dmm: Variant = dm / MM if dm < INF else null
			all.append([a["id"], b["id"], ovm, dmm])
			total += ovm
			if ovm >= hit:
				overlaps.append([a["id"], b["id"], ovm])
			elif dmm != null and float(dmm) <= near_mm:
				near.append([a["id"], b["id"], dmm])
	stat["kernel"] += kernel
	near.sort_custom(func(x, y): return float(x[2]) < float(y[2]))
	var cap := int(p.get("cap", 8))
	var out := {"parts": items.size(), "pairs": all.size(), "skipped": skipped, "overlaps": overlaps, "overlap_total_mm3": total,
		"near": near.slice(0, cap), "near_more": maxi(0, near.size() - cap), "box_near": all.size() - skipped}
	if not has_d:
		out.erase("near")
		out.erase("near_more")
		out["distance"] = "not computed: pass distance: true (slow, exact) or detail: true"
	if bool(p.get("detail", false)):
		out["all"] = all
		out["near"] = near
		out["near_more"] = 0
		out["kernel_calls"] = kernel
		out["dist_ms"] = prof[0] / 1000.0
		out["overlap_ms"] = prof[1] / 1000.0
		out["overlap_calls"] = prof[2]
		out["near_mm"] = near_mm
	return good(out)


# ---------------------------------------------------------------- bom

static func bom(p: Dictionary) -> Dictionary:
	if asm.is_empty() or (asm["parts"] as Array).is_empty():
		return fail("no assembly: cad_asm first")
	var b := AssemblyBom.bom(asm)
	var lines := []
	for ln in b["lines"]:
		lines.append([ln["part"], ln["count"], ln["line_mass_kg"], ln["line_cost"]] if not bool(p.get("detail", false)) else
			[ln["part"], ln["count"], ln["material"], ln["volume_m3"] * 1e9, ln["line_mass_kg"], ln["line_cost"], ln["ids"]])
	var out := {"cols": ["part", "count", "mass_kg", "cost"] if not bool(p.get("detail", false)) else ["part", "count", "material", "mm3_each", "mass_kg", "cost", "ids"],
		"lines": lines, "cost": b["cost"], "mass_kg": b["mass_kg"], "parts": b["parts"], "unpriced": b["unpriced"], "currency": b["currency"]}
	if bool(p.get("detail", false)):
		out["warnings"] = b["warnings"]
	return good(out)


# ---------------------------------------------------------------- reset

# ---------------------------------------------------------------- L1 AI-COST: look4d and sweep
## look4d {level 0|1|2|3, part, t, since, t1, step, ids, parts, cam {pos, look, fov}, h, image}: the live assembly as the zoomable digest of scripts/build/look4d.gd.
## level 0 (about 30 tokens) is the default way to look; 1 = parts + contacts; 2 = one part in full; 3 = a track; since = only what changed. Positions are the assembly's (m).
## Poses come from the assembly's animation keys when it has them (t in s), else from the drive set by drive_to. Visible share by rays (the session has no renderer).
## image: true returns the path of the annotated image C when the session has a renderer, else says it has none.
static func serve_async(m: Node, method: String, p: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var r: Dictionary
	match method:
		"look4d":
			r = await look4d(m, p)
		"sweep":
			r = sweep(p)
		_:
			r = {"ok": false, "error": "no async cad method '%s'" % method}
	if r["ok"] and bool(p.get("detail", false)):
		r["result"]["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	if r["ok"] and method != "look4d":
		r["result"] = rnd(r["result"], int(p.get("prec", 3)))
	return r


static func _auto_cam() -> Dictionary:
	var box := AABB()
	var first := true
	for q in asm["parts"]:
		var hh := rec_hash(q["rec"])
		if not cache.has(hh) and ensure(q["rec"]).has("error"):
			continue
		var cc: Dictionary = cache[hh]
		var xf := _xf(q)
		for k in (cc["aabbs"] as Array).size():
			var wb := _world_box(cc["aabbs"][k], xf)
			box = wb if first else box.merge(wb)
			first = false
	var ctr := box.get_center()
	var rad := maxf(box.size.length() * 0.5, 0.01)
	return {"pos": ctr + Vector3(0.6, 0.45, 1.0).normalized() * rad * 3.2, "look": ctr, "fov": 30.0}


static func live_scene(p: Dictionary) -> Dictionary:
	var scn: Script = load("res://scripts/build/look4d_scenes.gd")
	var cam: Dictionary = _auto_cam()
	if p.get("cam") is Dictionary:
		var cd: Dictionary = p["cam"]
		cam = {"pos": Vector3(cd["pos"][0], cd["pos"][1], cd["pos"][2]), "look": Vector3(cd["look"][0], cd["look"][1], cd["look"][2]), "fov": float(cd.get("fov", 30.0))}
	var t0 := float(p.get("t", 0.0))
	var h := float(p.get("h", 0.1))
	var sc: Dictionary
	if not AssemblyAnim.driven(asm).is_empty():
		var tmax := float(asm.get("anim", {}).get("length", 2.0))
		sc = scn.live(asm, cam, t0, h, "live", maxf(tmax, 2.0))
	else:
		var posefn := func(_t: float) -> Dictionary:
			var o := {}
			for q in asm["parts"]:
				o[String(q["id"])] = _xf(q)
			return o
		sc = scn._asm_scene("live", asm, posefn, cam, t0, h, {})
	if p.get("parts") is Array and not (p["parts"] as Array).is_empty():
		sc["named"] = (p["parts"] as Array).duplicate()
	return sc


static func look4d(m: Node, p: Dictionary) -> Dictionary:
	if asm.is_empty() or (asm["parts"] as Array).is_empty():
		return fail("no assembly: cad_asm first")
	if not ClassDB.class_exists("KineCAD"):
		return fail("the CAD kernel is missing")
	for q in asm["parts"]:
		if not cache.has(rec_hash(q["rec"])):
			var e := ensure(q["rec"])
			if e.has("error"):
				return fail(String(e["error"]))
	var sc := live_scene(p)
	var pp := p.duplicate()
	pp["render"] = false
	if not pp.has("t"):
		pp["t"] = float(sc["t0"])
	if bool(p.get("image", false)):
		var dir := OS.get_temp_dir().path_join("look4d_mcp")
		DirAccess.make_dir_recursive_absolute(dir)
		if DisplayServer.get_name() == "headless":
			var ctx0 := Look4D.open(m, sc)
			var r0 := Look4D.view_sync(ctx0, pp)
			Look4D.close(ctx0)
			if not bool(r0["ok"]):
				return fail(String(r0["error"]))
			var res0: Dictionary = r0["result"]
			res0["image"] = null
			res0["image_note"] = "this session has no renderer; start poser_mcp with a display to get the annotated image C"
			return good(res0)
		var sc2 := live_scene(p)
		sc2["t0"] = float(pp["t"])
		var pr: Dictionary = await Look4D.produce(m, sc2, dir)
		var res1: Dictionary = Look4D.view_sync(pr["ctx"], pp)["result"]
		Look4D.close(pr["ctx"])
		res1["image"] = dir + "/C.png"
		return good(res1)
	var ctx := Look4D.open(m, sc)
	var r := Look4D.view_sync(ctx, pp)
	Look4D.close(ctx)
	if not bool(r["ok"]):
		return fail(String(r["error"]))
	var out: Dictionary = r["result"]
	if bool(p.get("tokens", false)):
		out["tokens"] = r["tokens"]
	return good(out)


## sweep {drive, from, to, steps | values} or {param: {id, field: pos|rot, axis: 0..2}, from, to, steps}: one summary instead of every step.
## metric overlap_mm3 (default: total overlap volume of all pairs; worst = the largest), n_overlaps (pairs overlapping), min_gap_mm (exact distance, slow; worst = the smallest).
## threshold: overlap_mm3 / n_overlaps default 1 mm3 (hit_mm3), min_gap_mm default near_mm; over = steps beyond it (above for overlaps, below for the gap).
## Returns {metric, by, n, worst: {value, at, pair}, threshold, over, over_at (first 8), min, max}.
static func sweep(p: Dictionary) -> Dictionary:
	if asm.is_empty() or (asm["parts"] as Array).is_empty():
		return fail("no assembly: cad_asm first")
	var vals: Array = []
	if p.get("values") is Array and not (p["values"] as Array).is_empty():
		vals = (p["values"] as Array).duplicate()
	elif p.has("from") and p.has("to"):
		var n := clampi(int(p.get("steps", 36)), 1, 721)
		for i in n:
			vals.append(float(p["from"]) + (float(p["to"]) - float(p["from"])) * (float(i) / float(maxi(n - 1, 1))))
	else:
		return fail("sweep needs {drive | param: {id, field, axis}, from, to, steps} or values")
	var metric := String(p.get("metric", "overlap_mm3"))
	if not ["overlap_mm3", "n_overlaps", "min_gap_mm"].has(metric):
		return fail("metric is overlap_mm3, n_overlaps or min_gap_mm")
	var near_mm := float(p.get("near_mm", 2.0))
	var hit := float(p.get("hit_mm3", 1.0))
	var thr := float(p.get("threshold", near_mm if metric == "min_gap_mm" else hit))
	var by := ""
	var saved_pose := pose.duplicate()
	var part_ref: Dictionary = {}
	var saved_field: Array = []
	var axis := int(p.get("param", {}).get("axis", 0)) if p.get("param") is Dictionary else 0
	if p.has("drive"):
		by = "drive " + String(p["drive"])
	elif p.get("param") is Dictionary:
		var pr: Dictionary = p["param"]
		for q in asm["parts"]:
			if String(q["id"]) == String(pr.get("id", "")):
				part_ref = q
		if part_ref.is_empty():
			return fail("param.id '%s' is not a placed part" % String(pr.get("id", "")))
		var fld := String(pr.get("field", "pos"))
		if not ["pos", "rot"].has(fld):
			return fail("param.field is pos or rot")
		saved_field = (part_ref[fld] as Array).duplicate()
		by = "%s.%s[%d]" % [pr["id"], fld, axis]
	else:
		return fail("sweep needs drive or param")
	var series: Array = []
	var worst_v := NAN
	var worst_at := 0.0
	var worst_pair: Variant = null
	var over := 0
	var over_at: Array = []
	var lo := INF
	var hi := -INF
	for v in vals:
		var sub := {"near_mm": near_mm, "hit_mm3": hit, "cap": 64}
		if p.has("drive"):
			sub["drive"] = String(p["drive"])
			sub["value"] = float(v)
		else:
			var arr: Array = part_ref[String(p["param"].get("field", "pos"))]
			arr[axis] = float(v)
		if metric == "min_gap_mm":
			sub["distance"] = true
		var r := check_fit(sub)
		if not bool(r["ok"]):
			pose = saved_pose
			if not part_ref.is_empty():
				part_ref[String(p["param"].get("field", "pos"))] = saved_field
			return r
		var res: Dictionary = r["result"]
		var val := 0.0
		var pair: Variant = null
		match metric:
			"overlap_mm3":
				val = float(res["overlap_total_mm3"])
				var bo := -1.0
				for o in res["overlaps"]:
					if float(o[2]) > bo:
						bo = float(o[2])
						pair = [o[0], o[1]]
			"n_overlaps":
				val = float((res["overlaps"] as Array).size())
				if val > 0.0:
					pair = [res["overlaps"][0][0], res["overlaps"][0][1]]
			"min_gap_mm":
				val = near_mm
				for nr in res.get("near", []):
					if float(nr[2]) < val:
						val = float(nr[2])
						pair = [nr[0], nr[1]]
				for o in res["overlaps"]:
					val = 0.0
					pair = [o[0], o[1]]
		series.append(val)
		lo = minf(lo, val)
		hi = maxf(hi, val)
		var better := is_nan(worst_v) or (val < worst_v if metric == "min_gap_mm" else val > worst_v)
		if better:
			worst_v = val
			worst_at = float(v)
			worst_pair = pair
		var beyond := val < thr if metric == "min_gap_mm" else val > thr
		if beyond:
			over += 1
			if over_at.size() < 8:
				over_at.append(float(v))
	pose = saved_pose
	if not part_ref.is_empty():
		part_ref[String(p["param"].get("field", "pos"))] = saved_field
	return good({"metric": metric, "by": by, "n": vals.size(), "worst": {"value": worst_v, "at": worst_at, "pair": worst_pair}, "threshold": thr, "over": over, "over_at": over_at, "min": lo, "max": hi})


static func reset(p: Dictionary) -> Dictionary:
	var dropped := 0
	if bool(p.get("cache", true)):
		for h in cache.keys():
			_drop(h)
			dropped += 1
		parts = {}
		pairs = {}
		stat = {"replays": 0, "hits": 0, "kernel": 0}
	if bool(p.get("asm", true)):
		asm = {}
		last = {}
		pose = {}
	return good({"dropped": dropped})


# ---------------------------------------------------------------- eval_gd

## the paths eval_gd may write: res://scenes/_wip/ and the temp directory
static func write_allowed(path: String) -> bool:
	var g := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if path.begins_with("user://") or g.contains("..") or g.begins_with("res:"):
		return false
	g = g.replace("\\", "/").simplify_path()
	var wip := ProjectSettings.globalize_path("res://scenes/_wip/").replace("\\", "/").simplify_path()
	var tmp := OS.get_temp_dir().replace("\\", "/").simplify_path()
	for root in [wip, tmp, "C:/Temp/claude"]:
		if g.to_lower().begins_with(String(root).to_lower() + "/") and not g.ends_with("/"):
			return true
	return false


class Helper:
	extends RefCounted
	var m: Node
	var refusals: Array = []
	var log: Array = []

	## the one way a snippet writes: only res://scenes/_wip/ and the temp directory
	func write(path: String, text: String) -> bool:
		if not McpCad.write_allowed(path):
			refusals.append("a write to '%s' is refused: eval_gd writes only under res://scenes/_wip/ and the temp directory" % path)
			return false
		DirAccess.make_dir_recursive_absolute((ProjectSettings.globalize_path(path) if path.begins_with("res://") else path).get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			refusals.append("cannot open '%s'" % path)
			return false
		f.store_string(text)
		return true

	func note(x: Variant) -> void:
		log.append(McpCad.jsonable(x))

	func part(nm: String) -> Dictionary:   # a built part's record
		return McpCad.cache[McpCad.parts[nm]]["rec"] if McpCad.parts.has(nm) else {}

	func solids(nm: String) -> Array:   # a built part's exact solids (do not release)
		return McpCad.cache[McpCad.parts[nm]]["ids"] if McpCad.parts.has(nm) else []

	func assembly() -> Dictionary:
		return McpCad.asm


static func scan(code: String) -> String:
	var re := RegEx.new()
	re.compile("\\b(?:%s)\\b" % "|".join(BAN_WORDS))
	var hit := re.search(code)
	if hit != null:
		return "'%s' is not allowed in eval_gd (files, processes, the engine's internals): use H.write(path, text) for a file under scenes/_wip or the temp directory" % hit.get_string()
	var re2 := RegEx.new()
	re2.compile(BAN_RE)
	hit = re2.search(code)
	if hit != null:
		return "'%s' is not allowed in eval_gd: use H.write(path, text) for a file under scenes/_wip or the temp directory" % hit.get_string()
	return ""


static func jsonable(v: Variant) -> Variant:
	if v is Vector2 or v is Vector3 or v is AABB or v is Transform3D or v is Basis or v is Quaternion or v is Color or v is Vector2i or v is Vector3i:
		return jsonable(Array(str(v).replace("(", "").replace(")", "").split(",")).map(func(s): return float(s)))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = jsonable(v[k])
		return d
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array or v is PackedInt32Array or v is PackedStringArray or v is PackedVector3Array:
		var o := []
		for x in v:
			o.append(jsonable(x))
		return o
	if v == null or v is bool or v is int or v is float or v is String:
		return v
	return str(v)


static func eval_gd(m: Node, p: Dictionary) -> Dictionary:
	var code := String(p.get("code", ""))
	if code.strip_edges() == "":
		return fail("eval_gd needs {code}: GDScript, the body of a function; `return x` gives x (one expression line returns itself). H.write(path, text), H.part(name), H.solids(name), H.assembly(), H.note(x), m (the live scene) and KCad are there.")
	var why := scan(code.replace("H.write(", "H_ok("))   # H.write is the sanctioned writer; everything else named write* is refused
	if why != "":
		return fail(why)
	var lines := code.split("\n")
	if lines.size() == 1 and not code.strip_edges().begins_with("return") and not code.contains(";") and not code.strip_edges().begins_with("var ") and not code.strip_edges().contains(" = "):
		lines = PackedStringArray(["return " + code.strip_edges()])
	var body := ""
	for l in lines:
		body += "\t" + l + "\n"
	var src := "extends RefCounted\nconst KCad := preload(\"res://scripts/kcad.gd\")\nvar H\nvar m\nfunc run():\n" + body
	var gd := GDScript.new()
	gd.source_code = src
	var err := gd.reload()
	if err != OK:
		return fail("the snippet does not compile (error %d). Write it as the body of a function, one statement per line; the engine's message is on the session's stderr" % err)
	var h := Helper.new()
	h.m = m
	var o = gd.new()
	o.H = h
	o.m = m
	var t0 := Time.get_ticks_usec()
	var r = o.run()
	if not h.refusals.is_empty():
		return fail("; ".join(h.refusals))
	var out := {"value": jsonable(r)}
	if not h.log.is_empty():
		out["log"] = h.log
	if bool(p.get("detail", false)):
		out["snippet_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return good(out)
