extends RefCounted
## CH13: the seven engine parts as Kine Part records (OCCT), and the posed assembly. mm. Every fit-critical diameter is the mid-zone of its ISO 286 limits (Grgic's rule), from ch13_engine.gd.
## Local frames: every part has its axis along +z, sketch plane at z = 0 (the piston, cylinder and head are turned -90 deg about x in the assembly so their axes point up).
## Assembly frame: crank axis = z through (0, 0); cylinder axis = y at z = ZC; crank angle theta from TDC, clockwise seen from +z.
## G2LOOP asset: scripts/build/ch13_parts.gd as of 9a9522ca (CH13 bar j's FIRST run, before its geometry fixes), so tests/g2loop_test.gd bar d can sweep
## the geometry bar j found its faults in. Changed only so it parses today: the KCad preload and two typed vars. Do not use outside that test.
const E := preload("res://scripts/build/ch13_engine.gd")
const KCad := preload("res://scripts/kcad.gd")
const NAMES := ["crankcase", "crankshaft", "rod", "piston", "pin", "cylinder", "head"]
const R := 20.7            # crank radius (stroke 41.4, Honda C50)
const L := 80.0            # rod centres (ASSUMED)
const ZC := 39.15          # cylinder / rod / crank-pin centre plane (case cavity 10..68.3, centre 39.15)
const Z_CRANK0 := 10.15    # case z of the crank's left thrust face (nominal end-float 0.30 mm, centred)
const DECK := 111.2        # crank axis to the cylinder top face
const PIN_Z := 34.0        # pin axis height above the piston's skirt edge
const PISTON_H := 44.0     # skirt edge to crown
const CYL_H := 71.2        # cylinder from the case top (y = 40) to the deck
static var _m_recip := -1.0


static func dims() -> Dictionary:
	var f_pin := E.shaft("h", 5, 13.0)
	var f_bush := E.hole("G", 6, 13.0)
	var f_boss := E.hole("JS", 6, 13.0)
	var f_skirt := E.shaft("e", 7, 39.0)
	var f_bore := E.hole("H", 7, 39.0)
	var f_jour := E.shaft("f", 7, 20.0)
	var f_bear := E.hole("H", 7, 20.0)
	var f_cp := E.shaft("f", 7, 18.0)
	var f_be := E.hole("H", 7, 18.0)
	return {"pin_d": E.mid_shaft(13.0, f_pin), "bush_d": E.mid_hole(13.0, f_bush), "boss_d": E.mid_hole(13.0, f_boss), "skirt_d": E.mid_shaft(39.0, f_skirt), "bore_d": E.mid_hole(39.0, f_bore),
		"journal_d": E.mid_shaft(20.0, f_jour), "bearing_d": E.mid_hole(20.0, f_bear), "crankpin_d": E.mid_shaft(18.0, f_cp), "bigend_d": E.mid_hole(18.0, f_be)}


# ------------------------------------------------------------------ feature helpers
static func _circle(c: Array, r: float) -> Dictionary:
	return {"k": "circle", "c": c, "r": r}


static func _sk(fs: Array, plane: String, ents: Array) -> String:
	var id := "f%d" % (fs.size() + 1)
	fs.append({"t": "sketch", "id": id, "name": "Sketch%d" % (fs.size() + 1), "plane": plane, "ents": ents, "dims": []})
	return id


static func _ex(fs: Array, sk: String, dist: float, op: String, both := false) -> void:
	fs.append({"t": "extrude", "id": "f%d" % (fs.size() + 1), "name": "Extrude%d" % (fs.size() + 1), "sketch": sk, "dist": dist, "both": both, "op": op})


## a plane `mm` along the normal of base ("front" = z, "top" = y); returns its id
static func _plane(fs: Array, base: String, mm: float) -> String:
	if mm == 0.0:
		return base
	var id := "f%d" % (fs.size() + 1)
	fs.append({"t": "plane", "id": id, "name": "Plane%d" % (fs.size() + 1), "from": base, "mm": mm})
	return id


## a cylinder of radius r about the z axis through (cx, cy), from z0 to z0 + len
static func _cyl(fs: Array, cx: float, cy: float, r: float, z0: float, len: float, op: String) -> void:
	var pl := _plane(fs, "front", z0)
	_ex(fs, _sk(fs, pl, [_circle([cx, cy], r)]), len, op)


static func _paint(fs: Array, col: Array, metal: float, rough: float, alpha := 1.0, nm := "") -> void:
	fs.append({"t": "appear", "id": "f%d" % (fs.size() + 1), "name": "Paint", "body": 0, "preset": "Custom", "color": col, "metal": metal, "rough": rough, "alpha": alpha})
	if nm != "":
		fs.append({"t": "bname", "id": "f%d" % (fs.size() + 1), "name": "Name", "body": 0, "called": nm})


## the Part record of one engine part. opts (planted controls and the plain variant): boss_override (piston pin bore dia), no_bores / small_override (rod)
static func record(nm: String, opts := {}) -> Dictionary:
	var d := dims()
	var fs: Array = []
	match nm:
		"piston":
			var dp: float = d["skirt_d"]
			_cyl(fs, 0, 0, dp / 2.0, 0.0, PISTON_H, "new")
			_cyl(fs, 0, 0, 17.0, 0.0, 22.0, "cut")
			var bd: float = float(opts.get("boss_override", d["boss_d"]))
			# the pin bore: axis along y (the "top" plane: sketch (u, v) = (x, -z)), through the whole piston
			_ex(fs, _sk(fs, "top", [_circle([0.0, -PIN_Z], bd / 2.0)]), 60.0, "cut", true)
			_paint(fs, [0.86, 0.87, 0.92], 0.15, 0.45, 1.0, "Piston")
		"pin":
			_cyl(fs, 0, 0, float(d["pin_d"]) / 2.0, 0.0, 33.0, "new")
			_paint(fs, [0.95, 0.80, 0.30], 0.15, 0.4, 1.0, "Piston pin")
		"cylinder":
			_cyl(fs, 0, 0, 28.0, 0.0, CYL_H, "new")
			for zc in [20.0, 30.0, 40.0, 50.0, 60.0]:
				_cyl(fs, 0, 0, 35.0, zc - 1.0, 2.0, "join")
			_cyl(fs, 0, 0, float(d["bore_d"]) / 2.0, 0.0, CYL_H, "cut")
			_paint(fs, [0.35, 0.42, 0.55], 0.1, 0.5, 0.35, "Cylinder")
		"head":
			_cyl(fs, 0, 0, 35.0, 0.0, 30.0, "new")
			_cyl(fs, 0, 0, 19.5, 0.0, 4.6, "cut")
			_cyl(fs, 0, 0, 7.0, 4.6, 25.4, "cut")
			_paint(fs, [0.70, 0.35, 0.25], 0.1, 0.5, 1.0, "Head")
		"crankcase":
			var sk := _sk(fs, "front", [{"k": "rect", "a": [-45.0, -50.0], "b": [45.0, 40.0]}])
			_ex(fs, sk, 78.3, "new")
			var pl := _plane(fs, "front", 10.0)
			_ex(fs, _sk(fs, pl, [{"k": "rect", "a": [-40.0, -45.0], "b": [40.0, 35.0]}]), 58.3, "cut")
			_cyl(fs, 0, 0, float(d["bearing_d"]) / 2.0, 0.0, 78.3, "cut")
			var ty := _plane(fs, "top", 35.0)
			_ex(fs, _sk(fs, ty, [_circle([0.0, -ZC], 22.0)]), 5.0, "cut")
			_paint(fs, [0.55, 0.60, 0.68], 0.1, 0.5, 0.28, "Crankcase")
		"crankshaft":
			var jr: float = float(d["journal_d"]) / 2.0
			_cyl(fs, 0, 0, jr, -20.0, 29.0, "new")
			_cyl(fs, 0, 0, 14.0, 0.0, 9.0, "join")
			for z0 in [9.0, 41.0]:
				_cyl(fs, 0, 0, 22.0, z0, 8.0, "join")
				_cyl(fs, 0, R, 14.0, z0, 8.0, "join")
			_cyl(fs, 0, R, float(d["crankpin_d"]) / 2.0, 17.0, 24.0, "join")
			_cyl(fs, 0, 0, 14.0, 49.0, 9.0, "join")
			_cyl(fs, 0, 0, jr, 49.0, 29.0, "join")
			_paint(fs, [0.95, 0.55, 0.12], 0.15, 0.4, 1.0, "Crankshaft")
		"rod":
			var sbd: float = float(opts.get("small_override", d["bush_d"]))
			var rl: float = float(opts.get("rod_len", L))
			_cyl(fs, 0, 0, 15.0, 0.0, 20.0, "new")
			_cyl(fs, 0, rl, 10.0, 0.0, 20.0, "join")
			var shank := [[-8.0, 12.0], [8.0, 12.0], [5.0, rl - 12.0], [-5.0, rl - 12.0]]
			var ents := []
			for i in 4:
				ents.append({"k": "line", "a": shank[i], "b": shank[(i + 1) % 4]})
			_ex(fs, _sk(fs, "front", ents), 20.0, "join")
			if not bool(opts.get("no_bores", false)):
				_cyl(fs, 0, 0, float(d["bigend_d"]) / 2.0, 0.0, 20.0, "cut")
				_cyl(fs, 0, rl, sbd / 2.0, 0.0, 20.0, "cut")
			_paint(fs, [0.55, 0.70, 0.90], 0.15, 0.4, 1.0, "Connecting rod")
	var rec := Part.make("Engine " + nm)
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


# ------------------------------------------------------------------ the pose
static func rod_angle(th: float, rl := L) -> float:
	return atan2(R * sin(th), E.piston_x(th, R, rl) - R * cos(th))


## each part's {"pos": mm, "rot": deg} for the crank angle th_deg. opts skip_rod_turn: the planted control (the rod keeps its upright pose); rod_len: another rod (bar j's control)
static func pose_of(th_deg: float, opts := {}) -> Dictionary:
	var th := deg_to_rad(th_deg)
	var rl: float = float(opts.get("rod_len", L))
	var x := E.piston_x(th, R, rl)
	var psi := 0.0 if bool(opts.get("skip_rod_turn", false)) else rod_angle(th, rl)
	return {
		"crankcase": {"pos": [0.0, 0.0, 0.0], "rot": [0.0, 0.0, 0.0]},
		"crankshaft": {"pos": [0.0, 0.0, Z_CRANK0], "rot": [0.0, 0.0, -th_deg]},
		"rod": {"pos": [R * sin(th), R * cos(th), ZC - 10.0], "rot": [0.0, 0.0, rad_to_deg(psi)]},
		"piston": {"pos": [0.0, x - PIN_Z, ZC], "rot": [-90.0, 0.0, 0.0]},
		"pin": {"pos": [0.0, x, ZC - 16.5], "rot": [0.0, 0.0, 0.0]},
		"cylinder": {"pos": [0.0, 40.0, ZC], "rot": [-90.0, 0.0, 0.0]},
		"head": {"pos": [0.0, DECK, ZC], "rot": [-90.0, 0.0, 0.0]},
	}


static func _at(p: Dictionary, local: Vector3) -> Vector3:
	var xf := Assembly.xf_of(p)
	return (xf * (local * Assembly.MM)) / Assembly.MM


## the four joints through the placed parts' own transforms: {"crankpin", "rod_big", "rod_small", "pin"} (mm)
static func points(th_deg: float, opts := {}) -> Dictionary:
	var po := pose_of(th_deg, opts)
	return {"crankpin": _at(po["crankshaft"], Vector3(0, R, 29.0)), "rod_big": _at(po["rod"], Vector3(0, 0, 10.0)), "rod_small": _at(po["rod"], Vector3(0, L, 10.0)), "pin": _at(po["pin"], Vector3(0, 0, 16.5))}


## an Assembly record (the Friday-213 engine) at crank angle th_deg
static func assembly(th_deg: float) -> Dictionary:
	var asm := Assembly.make("Single-cylinder engine (CH13)")
	var po := pose_of(th_deg)
	var i := 0
	for nm in NAMES:
		i += 1
		asm["parts"].append({"id": "p%d" % i, "name": String(nm).capitalize(), "src": "", "rec": record(nm), "pos": po[nm]["pos"], "rot": po[nm]["rot"]})
	asm["seq"] = i
	return asm


## bar j: the exact solid of a record in its own frame (metres); 0 unless it builds ONE body. The caller releases it (KCad.release)
static func solid(rec: Dictionary) -> int:
	var ids: Array = Part.replay(rec, -1, {"keep": true}).get("ids", [])
	if ids.size() == 1:
		return int(ids[0])
	Part.release_kept(ids)
	return 0


## bar j: a NEW solid, src moved to the part's place p ({"pos": mm, "rot": deg}) the way Assembly.xf_of places its mesh
## (Basis.from_euler, order YXZ: z turns first, then x, then y). src stays valid; the caller releases both
static func place(src: int, p: Dictionary) -> int:
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


## bar j: a plain cylinder record (a gauge): radius r about the part-local z axis through (cx, cy), z0 .. z0 + len (mm)
static func gauge(cx: float, cy: float, r: float, z0: float, len: float) -> Dictionary:
	var fs: Array = []
	_cyl(fs, cx, cy, r, z0, len, "new")
	var rec := Part.make("CH13 gauge")
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


## reciprocating mass (kg) from the CAD volumes: piston (Al 2700), pin (steel 7850), rings (12 g, ASSUMED), one third of the rod (steel)
static func m_recip() -> float:
	if _m_recip > 0.0:
		return _m_recip
	var vp: float = float(Assembly.built(record("piston"))["volume"])
	var vpin: float = float(Assembly.built(record("pin"))["volume"])
	var vrod: float = float(Assembly.built(record("rod"))["volume"])
	_m_recip = 2700.0 * vp + 7850.0 * vpin + 0.012 + 7850.0 * vrod / 3.0
	return _m_recip
