extends RefCounted
## CH15: the plant ASSEMBLY (every Part of ch15_parts.gd at its place in the PLANT GRID: metres, origin the reactor centre at grade, +x along the turbine
## hall axis, +z to plant south, y up; Assembly poses are mm), the layout checks of bar 6 (built boxes against the reference table, KCad.overlap_volume of the
## posed exact solids, CH13 bar j style) and the construction stages with their support check (bar 7).
## Each assembly part carries, beside the Assembly fields: "bld" (the building it belongs to, "" for none), "eq" (primary equipment), "cut" (the plant z of its
## section plane, or null), "sup" (what it rests on: [[name, "on"|"in"|"hang"|"ground"], ...]).
const PT := preload("res://scripts/build/ch15_parts.gd")
const KCad := preload("res://scripts/kcad.gd")
const OV_EPS := 1e-6   # m3 = 1 cm3: below this two solids at a 600 m site share no volume (touching faces leave kernel noise)
const TOL := 0.02      # m: a bottom face resting on a top face
const GROUND_LEVELS := [0.0, PT.Y_PIT]

## the reference table of docs/CH15_REFERENCE.md section 6: name -> {w, d, h (m), src, pos [x, z]}
const REF := {
	"Reactor building": {"w": 71.5, "d": 71.5, "h": 60.0, "src": "SEEN sat / h ASSUMED", "pos": [0.0, 0.0]},
	"Turbine hall": {"w": 93.0, "d": 50.0, "h": 45.0, "src": "SEEN sat / h ASSUMED", "pos": [82.4, 30.4]},
	"Switchyard 500 kV": {"w": 280.0, "d": 190.0, "h": 30.0, "src": "SEEN sat / h ASSUMED", "pos": [173.0, -208.0]},
	"Seawater intake": {"w": 70.0, "d": 35.0, "h": 15.0, "src": "SEEN sat / h ASSUMED", "pos": [-90.0, 188.0]},
	"Auxiliary building": {"w": 60.0, "d": 45.0, "h": 30.0, "src": "pos SEEN / ASSUMED", "pos": [-24.0, 62.0]},
	"Switchgear building": {"w": 50.0, "d": 30.0, "h": 25.0, "src": "ASSUMED", "pos": [40.0, -60.0]},
	"Fuel building": {"w": 30.0, "d": 25.0, "h": 20.0, "src": "ASSUMED", "pos": [-60.0, -60.0]},
	"Diesel building 1": {"w": 40.0, "d": 20.0, "h": 15.0, "src": "ASSUMED", "pos": [-85.0, -15.0]},
	"Diesel building 2": {"w": 40.0, "d": 20.0, "h": 15.0, "src": "ASSUMED", "pos": [-85.0, 20.0]},
	"Emergency feedwater building": {"w": 30.0, "d": 30.0, "h": 20.0, "src": "ASSUMED", "pos": [-20.0, -110.0]},
	"Outfall structure": {"w": 30.0, "d": 20.0, "h": 8.0, "src": "ASSUMED", "pos": [60.0, 150.0]},
	"Transformer yard": {"w": 30.0, "d": 12.0, "h": 10.0, "src": "ASSUMED", "pos": [147.0, 30.4]},
}


## a part record built at PLANT scale: Part.replay tessellates every body at 0.3 mm (Part._tess_cached), which for a 56 m sphere or a 600 m ground slab
## is millions of triangles and minutes per part; here the replay defers the tessellation and the bodies are meshed at DEFL (1 cm) instead.
## {"mesh", "aabb" (m, own frame), "volume" (m3), "bodies"}; memo by record text
const DEFL := 0.01
static var _memo := {}


static func built(rec: Dictionary) -> Dictionary:
	var key := JSON.stringify(rec).hash()
	if _memo.has(key):
		return _memo[key]
	var out := {"mesh": null, "aabb": AABB(), "volume": 0.0, "bodies": 0}
	if Part.available():
		var res := Part.replay(rec, -1, {"defer_tess": true})
		var ids: Array = res.get("tess_ids", [])
		var lks: Array = res.get("tess_looks", [])
		var mesh := ArrayMesh.new()
		var looks := []
		for i in ids.size():
			var tm: ArrayMesh = KCad.tessellate(int(ids[i]), DEFL, 0.05)
			if tm != null and tm.get_surface_count() > 0:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tm.surface_get_arrays(0))
				looks.append(lks[i] if i < lks.size() else Part.look_at([], i))
			KCad.release(int(ids[i]))
		if mesh.get_surface_count() > 0:
			Part.paint(mesh, looks)
			out = {"mesh": mesh, "aabb": mesh.get_aabb(), "volume": float(res.get("volume", 0.0)), "bodies": int(res.get("bodies", 0))}
	_memo[key] = out
	return out


## the part's box in the plant frame (m)
static func world_aabb(p: Dictionary) -> AABB:
	var b := built(p["rec"])
	if b["mesh"] == null:
		return AABB()
	return Assembly.xf_of(p) * (b["aabb"] as AABB)


static func _mm3(x: float, y: float, z: float) -> Array:
	return [snappedf(x * 1000.0, 0.001), snappedf(y * 1000.0, 0.001), snappedf(z * 1000.0, 0.001)]


static func _add(asm: Dictionary, nm: String, rec: Dictionary, pos: Vector3, bld: String, sup: Array, opts := {}) -> void:
	asm["seq"] = int(asm["seq"]) + 1
	var p := {"id": "p%d" % int(asm["seq"]), "name": nm, "src": "", "rec": rec, "pos": _mm3(pos.x, pos.y, pos.z), "rot": [0.0, float(opts.get("roty", 0.0)), 0.0],
		"bld": bld, "eq": bool(opts.get("eq", false)), "cut": opts.get("cut", null), "sup": sup}
	asm["parts"].append(p)


## the whole plant. opts th_into_rb: the planted control (the turbine hall's parts moved 60 m towards the reactor, into its building)
static func assembly(opts := {}) -> Dictionary:
	var asm := Assembly.make("Angra 2 class PWR plant (CH15)")
	_add(asm, "Site ground", PT.ground(), Vector3.ZERO, "", [])
	_add(asm, "Base mat", PT.base_mat(), Vector3.ZERO, "", [["", "ground"]], {"cut": 0.0})   # below grade: not part of the building's footprint
	_add(asm, "Sphere lower half", PT.sphere_half(false), Vector3.ZERO, "Reactor building", [["Base mat", "on"]], {"cut": 0.0})
	_add(asm, "Sphere upper half", PT.sphere_half(true), Vector3.ZERO, "Reactor building", [["Sphere lower half", "on"]], {"cut": 0.0})
	_add(asm, "Concrete fill", PT.fill(), Vector3.ZERO, "", [["Sphere lower half", "in"]], {"cut": 0.0, "eq_wall": true})
	_add(asm, "Internal concrete", PT.internals(), Vector3.ZERO, "", [["Concrete fill", "on"]], {"cut": 0.0})
	_add(asm, "Crane runway", PT.crane_runway(), Vector3.ZERO, "", [["Sphere upper half", "hang"]], {"cut": 0.0})
	_add(asm, "Polar crane", PT.polar_crane(), Vector3.ZERO, "", [["Crane runway", "on"]], {"cut": 0.0})
	_add(asm, "Reactor pressure vessel", PT.vessel(), Vector3.ZERO, "", [["Concrete fill", "on"], ["Polar crane", "hang"]], {"cut": 0.0, "eq": true})
	for k in 4:
		_add(asm, "Steam generator %d" % (k + 1), PT.steam_generator(k), Vector3.ZERO, "", [["Concrete fill", "on"], ["Polar crane", "hang"]], {"cut": 0.0, "eq": true})
	for k in 4:
		_add(asm, "Coolant pump %d" % (k + 1), PT.coolant_pump(k), Vector3.ZERO, "", [["Concrete fill", "on"], ["Polar crane", "hang"]], {"cut": 0.0, "eq": true})
	_add(asm, "Pressurizer", PT.pressurizer(), Vector3.ZERO, "", [["Concrete fill", "on"], ["Polar crane", "hang"]], {"cut": 0.0, "eq": true})
	# the loops: hot leg vessel -> SG at +11 m, crossover SG -> pump at +3 m, cold leg pump -> vessel at +8 m
	for k in 4:
		var az: float = PT.LOOP_AZ[k]
		var sg := PT.at_az(PT.R_SG, az)
		var rc := PT.at_az(PT.R_RCP, az + PT.RCP_DAZ)
		var legs := [["Hot leg %d" % (k + 1), Vector2.ZERO, sg, 11.0, "Steam generator %d" % (k + 1)], ["Crossover leg %d" % (k + 1), sg, rc, 3.0, "Coolant pump %d" % (k + 1)],
			["Cold leg %d" % (k + 1), rc, Vector2.ZERO, 8.0, "Coolant pump %d" % (k + 1)]]
		for lg in legs:
			var a: Vector2 = lg[1]
			var b: Vector2 = lg[2]
			var ends := ["Reactor pressure vessel", String(lg[4])] if String(lg[0]).begins_with("Hot") or String(lg[0]).begins_with("Cold") else ["Steam generator %d" % (k + 1), "Coolant pump %d" % (k + 1)]
			# stop at the equipment's outer wall, not its centre: centre-to-centre pipes ran into the vessel/SGs/pumps (33 overlaps found by G33)
			var rad := {"Reactor pressure vessel": 2.75, "Steam generator": 2.5, "Coolant pump": 1.5}
			var ra: float = rad["Reactor pressure vessel"] if ends[0] == "Reactor pressure vessel" else (rad["Steam generator"] if String(ends[0]).begins_with("Steam generator") else rad["Coolant pump"])
			var rb: float = rad["Reactor pressure vessel"] if ends[1] == "Reactor pressure vessel" else (rad["Steam generator"] if String(ends[1]).begins_with("Steam generator") else rad["Coolant pump"])
			var u := (b - a).normalized()
			var a2 := a + u * ra
			var b2 := b - u * rb
			var dv := b2 - a2
			_add(asm, String(lg[0]), PT.pipe(String(lg[0]) + " (0.75 m bore)", dv.length(), 20 + k), Vector3(a2.x, float(lg[3]), a2.y), "", [[ends[0], "hang"], [ends[1], "hang"]], {"roty": -rad_to_deg(atan2(dv.y, dv.x))})
	_add(asm, "Shield wall", PT.shield_wall(), Vector3.ZERO, "Reactor building", [["Base mat", "on"]], {"cut": 0.0})
	_add(asm, "Shield dome", PT.shield_dome(), Vector3.ZERO, "Reactor building", [["Shield wall", "on"]], {"cut": 0.0})
	# the turbine hall: its parts are built round the hall's centre
	var th0: Array = REF["Turbine hall"]["pos"]
	var thp := Vector3(float(th0[0]), 0.0, float(th0[1]))
	if bool(opts.get("th_into_rb", false)):
		thp.x -= 60.0
	var cz := thp.z
	_add(asm, "Turbine hall mat", PT.th_mat(), thp, "Turbine hall", [["", "ground"]], {"cut": cz})
	_add(asm, "Turbine table", PT.pedestal(), thp, "Turbine hall", [["Turbine hall mat", "on"]], {"cut": cz})
	for k in 3:
		_add(asm, "Condenser %d" % (k + 1), PT.condenser(k), thp, "Turbine hall", [["Turbine hall mat", "on"]], {"cut": cz})
	_add(asm, "HP turbine", PT.hp_turbine(), thp, "Turbine hall", [["Turbine table", "on"]], {"cut": cz})
	for k in 3:
		_add(asm, "LP turbine %d" % (k + 1), PT.lp_turbine(k), thp, "Turbine hall", [["Turbine table", "on"]], {"cut": cz})
	_add(asm, "Generator", PT.generator(), thp, "Turbine hall", [["Turbine table", "on"]], {"cut": cz})
	_add(asm, "Turbine hall building", PT.th_shell(), thp, "Turbine hall", [["Turbine hall mat", "on"]], {"cut": cz})
	var ty: Array = REF["Transformer yard"]["pos"]
	_add(asm, "Transformer yard", PT.transformer_yard(), Vector3(float(ty[0]), 0, float(ty[1])), "Transformer yard", [["", "ground"]])
	var sy: Array = REF["Switchyard 500 kV"]["pos"]
	_add(asm, "Switchyard 500 kV", PT.switchyard(), Vector3(float(sy[0]), 0, float(sy[1])), "Switchyard 500 kV", [["", "ground"]])
	var blocks := [["Auxiliary building", PT.CONC, 60], ["Switchgear building", PT.CONC_D, 61], ["Fuel building", PT.CONC, 62], ["Diesel building 1", PT.CONC_D, 63],
		["Diesel building 2", PT.CONC_D, 64], ["Emergency feedwater building", PT.CONC_D, 65], ["Seawater intake", PT.CONC, 66], ["Outfall structure", PT.CONC, 67]]
	for b in blocks:
		var rf: Dictionary = REF[b[0]]
		_add(asm, String(b[0]), PT.block(String(b[0]), rf["w"], rf["h"], rf["d"], b[1], b[2]), Vector3(float(rf["pos"][0]), 0, float(rf["pos"][1])), String(b[0]), [["", "ground"]])
	return asm


static func part_named(asm: Dictionary, nm: String) -> Dictionary:
	for p in asm["parts"]:
		if String(p["name"]) == nm:
			return p
	return {}


## the buildings of bar 6: [{name, parts, ref}], one entry per building (a building may be several parts)
static func buildings(asm: Dictionary) -> Array:
	var by := {}
	var order := []
	for p in asm["parts"]:
		var b := String(p.get("bld", ""))
		if b == "":
			continue
		if not by.has(b):
			by[b] = []
			order.append(b)
		by[b].append(p)
	var out := []
	for b in order:
		var rf: Dictionary = REF[b].duplicate()
		out.append({"name": b, "parts": by[b], "ref": rf})
	return out


## the primary equipment and the concrete round it, one entry per part (bar 6's second overlap check)
static func equipment(asm: Dictionary) -> Array:
	var out := []
	for p in asm["parts"]:
		if bool(p.get("eq", false)) or String(p["name"]) in ["Internal concrete", "Concrete fill"]:
			out.append({"name": p["name"], "parts": [p], "ref": {}})
	return out


static func _box_of(parts: Array) -> AABB:
	var bb := world_aabb(parts[0])
	for i in range(1, parts.size()):
		bb = bb.merge(world_aabb(parts[i]))
	return bb


## the built footprint (x by z) and the height above grade of a building entry (m)
static func footprint(b: Dictionary) -> Dictionary:
	var bb := _box_of(b["parts"])
	return {"w": bb.size.x, "d": bb.size.z, "h": bb.end.y, "box": bb}


# ---------------------------------------------------------------- exact overlap (KCad), as CH13 bar j
static func _solid(rec: Dictionary) -> int:
	var ids: Array = Part.replay(rec, -1, {"keep": true, "errors_only": true}).get("ids", [])
	if ids.size() == 1:
		return int(ids[0])
	Part.release_kept(ids)
	return 0


static func _place(src: int, p: Dictionary) -> int:
	var s := src
	var rot: Array = p["rot"]
	for step in [[Vector3.BACK, float(rot[2])], [Vector3.RIGHT, float(rot[0])], [Vector3.UP, float(rot[1])]]:
		if absf(float(step[1])) > 1e-12:
			var t: int = KCad.rotate(s, step[0], deg_to_rad(float(step[1])))
			if s != src:
				KCad.release(s)
			s = t
			if s == 0:
				return 0
	var pos: Array = p["pos"]
	var m: int = KCad.translate(s, Vector3(float(pos[0]), float(pos[1]), float(pos[2])) * Assembly.MM)
	if s != src:
		KCad.release(s)
	return m


## every pair of parts that belong to DIFFERENT entries: {"pairs": n checked exactly, "hits": [[a, b, m3]], "skipped": n (boxes apart)}
static func clashes(entries: Array) -> Dictionary:
	var solids := {}
	var hits := []
	var pairs := 0
	var skipped := 0
	for i in entries.size():
		for j in range(i + 1, entries.size()):
			for a in entries[i]["parts"]:
				for b in entries[j]["parts"]:
					for p in [a, b]:
						if not solids.has(p["id"]):
							var s0 := _solid(p["rec"])
							solids[p["id"]] = _place(s0, p) if s0 != 0 else 0
							if s0 != 0:
								KCad.release(s0)
					var sa: int = solids[a["id"]]
					var sb: int = solids[b["id"]]
					pairs += 1
					if sa == 0 or sb == 0:
						hits.append([a["name"], b["name"], "no solid"])
						continue
					var v: float = KCad.overlap_volume(sa, sb)
					if v > OV_EPS:
						hits.append([a["name"], b["name"], snappedf(v, 0.001)])
	for k in solids:
		if int(solids[k]) != 0:
			KCad.release(int(solids[k]))
	return {"pairs": pairs, "hits": hits, "skipped": skipped}


# ---------------------------------------------------------------- construction (bar 7)
const STAGES := [
	["Excavation and base mat", ["Site ground", "Base mat"]],
	["Steel sphere, lower half", ["Sphere lower half"]],
	["Steel sphere, upper half", ["Sphere upper half"]],
	["Internal concrete", ["Concrete fill", "Internal concrete"]],
	["Polar crane", ["Crane runway", "Polar crane"]],
	["Vessel and steam generator lift-in", ["Reactor pressure vessel", "Steam generator 1", "Steam generator 2", "Steam generator 3", "Steam generator 4",
		"Coolant pump 1", "Coolant pump 2", "Coolant pump 3", "Coolant pump 4", "Pressurizer", "LOOPS"]],
	["Shield wall", ["Shield wall"]],
	["Shield dome", ["Shield dome"]],
	["Turbine hall", ["Turbine hall mat", "Turbine table", "Condenser 1", "Condenser 2", "Condenser 3", "HP turbine", "LP turbine 1", "LP turbine 2", "LP turbine 3",
		"Generator", "Turbine hall building", "Transformer yard"]],
	["Auxiliary buildings, switchyard, intake", ["Auxiliary building", "Switchgear building", "Fuel building", "Diesel building 1", "Diesel building 2",
		"Emergency feedwater building", "Switchyard 500 kV", "Seawater intake", "Outfall structure"]],
]


## [{name, parts: [names]}] in build order. opts dome_first: the planted control (the dome stage before the wall)
static func stages(opts := {}) -> Array:
	var out := []
	for s in STAGES:
		var names := []
		for n in s[1]:
			if n == "LOOPS":
				for k in 4:
					names.append_array(["Hot leg %d" % (k + 1), "Crossover leg %d" % (k + 1), "Cold leg %d" % (k + 1)])
			else:
				names.append(n)
		out.append({"name": s[0], "parts": names})
	if bool(opts.get("dome_first", false)):
		var w: Dictionary = out[6]
		out[6] = out[7]
		out[7] = w
	return out


static func _xz_overlap(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x - TOL and b.position.x < a.end.x - TOL and a.position.z < b.end.z - TOL and b.position.z < a.end.z - TOL


## each part, in stage order, must rest on parts already built: {"ok", "placed": n, "bad": [why]}
static func support_check(asm: Dictionary, st: Array) -> Dictionary:
	var built := {}
	var bad := []
	var placed := 0
	for s in st:
		for nm in s["parts"]:
			var p := part_named(asm, nm)
			if p.is_empty():
				bad.append("%s: not in the assembly" % nm)
				continue
			var bb := world_aabb(p)
			for sp in p["sup"]:
				var mode := String(sp[1])
				if mode == "ground":
					var lv_ok := false
					for lv in GROUND_LEVELS:
						lv_ok = lv_ok or absf(bb.position.y - float(lv)) < TOL
					if not (built.has("Site ground") and lv_ok):
						bad.append("%s: not on the ground (bottom %.2f m)" % [nm, bb.position.y])
					continue
				var sn := String(sp[0])
				if not built.has(sn):
					bad.append("%s: %s is not built yet" % [nm, sn])
					continue
				var sb: AABB = built[sn]
				match mode:
					"on":
						if absf(bb.position.y - sb.end.y) >= TOL or not _xz_overlap(bb, sb):
							bad.append("%s: bottom %.2f m does not rest on %s (top %.2f m)" % [nm, bb.position.y, sn, sb.end.y])
					"in":
						if not sb.grow(TOL).encloses(bb) or absf(bb.position.y - sb.position.y) > 0.1:
							bad.append("%s: not seated in %s" % [nm, sn])
					"hang":
						pass
			built[nm] = bb
			placed += 1
	return {"ok": bad.is_empty(), "placed": placed, "bad": bad}
