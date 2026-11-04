class_name Ch1fSys
extends RefCounted
## CH1f: three building systems on the CH1 floor plan (9.754 x 7.620 m, eave 2.448 m) as 3D frames for Ch10Frame, plus the soil-structure assembly.
##   wood      the CH10 house (members.json, SDPWS shear panels), unchanged.
##   masonry   Brazilian confined masonry: 14 cm ceramic structural block piers (shear panels), RC tie columns at every pier end, RC tie beam (cinta) and baldrame.
##   lsf       light steel frame: Ue 90x40x12x0.95 studs at 400 mm, U tracks, 11.1 mm OSB one face (panel shear stiffness as the wood row, UNVERIFIED for screws).
## All masses of the two new systems are LUMPED from an explicit takeoff (members carry rho = 0), so the model mass is the takeoff and nothing is counted twice.
## Every constant has its source / UNVERIFIED flag in docs/CH1f_REFERENCE.md. Units N, m, kg, s.

const HO := preload("res://scripts/build/ch10_house.gd")
const FR := preload("res://scripts/build/ch10_frame.gd")
const SO := preload("res://scripts/build/ch1f_soil.gd")

const LX := 9.754
const LZ := 7.620
const H := 2.448          # eave axis (top of wall) as in CH10
const HW := 2.467         # wall height for areas
const CT := 0.07          # wall axis offset from the outer face (14 cm wall)
const G_ACC := 9.80665
const LB_IN := 175.1268

# masonry (NBR 15812-1 ceramic structural masonry; RC per NBR 6118)
const T_WALL := 0.14
const FPK := 3.0e6                # Pa, prism strength (block fbk 6 MPa x 0.5 prism efficiency: UNVERIFIED)
const E_MAS := 600.0 * FPK        # NBR 15812-1: 600 fpk (UNVERIFIED: read from secondary summaries only)
const G_MAS := 0.4 * E_MAS
const FVK := 0.15e6               # Pa, characteristic shear strength of the masonry (UNVERIFIED)
const WALL_KGM2 := 255.0          # 0.14 m hollow ceramic block wall + 2 x 2 cm render (see reference)
const E_RC := 24.15e9             # NBR 6118 Ecs, fck 25 MPa
const G_RC := 0.4 * 24.15e9
const RHO_RC := 2500.0
# light steel frame (NBR 15253; steel per NBR 6355 / 14762)
const E_ST := 200.0e9
const G_ST := 77.0e9
const RHO_ST := 7850.0
const GA_LSF_KIPS := 11.0         # UNVERIFIED: the wood OSB 6d row used as a stand-in for screwed OSB (AISI S400 table not read)
const T_STUD := 0.00095
# common
const SLAB_T := 0.10
const GYP_KGM2 := 10.7
const GLASS_KGM2 := 30.0
const PART_KGM2 := 30.0           # interior partitions as drywall on light studs, mass only
const GT_ROOF := 1000.0 * 7.5 * LB_IN   # roof diaphragm Ga 7.5 kips/in as CH10 (UNVERIFIED there)
const LINES := ["F", "B", "L", "R"]


class Acc:
	var nodes: Array = []
	var key := {}
	var beams := PackedFloat64Array()
	var springs := PackedFloat64Array()
	var lump := {}
	var panels: Array = []

	func node(p: Vector3) -> int:
		var k := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if key.has(k):
			return key[k]
		key[k] = nodes.size()
		nodes.append(p)
		return key[k]

	func beam(p: Vector3, q: Vector3, sec: Dictionary, E: float, G: float, e2: Vector3) -> void:
		var na := node(p)
		var nb := node(q)
		if na == nb:
			return
		beams.append_array([na, nb, sec["A"], sec["Iz"], sec["Iy"], sec["J"], E, G, 0.0, e2.x, e2.y, e2.z])

	func add_mass(i: int, kg: float) -> void:
		lump[i] = lump.get(i, 0.0) + kg


static func rect(bw: float, dp: float) -> Dictionary:
	var s := minf(bw, dp)
	var l := maxf(bw, dp)
	var j := l * s * s * s * (1.0 / 3.0 - 0.21 * (s / l) * (1.0 - pow(s, 4) / (12.0 * pow(l, 4))))
	return {"A": bw * dp, "Iz": bw * dp * dp * dp / 12.0, "Iy": dp * bw * bw * bw / 12.0, "J": j}


## Ue 90x40x12 x 0.95 mm lipped channel from its rectangles. Iz: bending about the web-parallel... see below. Returns A, I_strong, I_weak, J.
static func cee_section(d := 0.090, b := 0.040, c := 0.012, t := T_STUD) -> Dictionary:
	var A := t * d + 2.0 * t * b + 2.0 * t * c
	var xc := (t * d * (t * 0.5) + 2.0 * t * b * (b * 0.5) + 2.0 * t * c * (b - t * 0.5)) / A
	var Is := t * d * d * d / 12.0 + 2.0 * (b * t * pow(0.5 * d - 0.5 * t, 2)) + 2.0 * (t * c * c * c / 12.0 + t * c * pow(0.5 * d - t - 0.5 * c, 2))
	var Iw := d * t * t * t / 12.0 + d * t * pow(xc - 0.5 * t, 2) + 2.0 * (t * b * b * b / 12.0 + b * t * pow(0.5 * b - xc, 2)) + 2.0 * (c * t * t * t / 12.0 + t * c * pow(b - 0.5 * t - xc, 2))
	var J := (d * t * t * t + 2.0 * b * t * t * t + 2.0 * c * t * t * t) / 3.0
	return {"A": A, "Iz": Is, "Iy": Iw, "J": J}


static func line_point(ln: String, s: float, y: float) -> Vector3:
	match ln:
		"F":
			return Vector3(s, y, CT)
		"B":
			return Vector3(s, y, LZ - CT)
		"L":
			return Vector3(CT, y, s)
	return Vector3(LX - CT, y, s)


static func line_len(ln: String) -> float:
	return LX if (ln == "F" or ln == "B") else LZ


## window / door boxes on a line: [{lo, hi, y0, y1, kind}] in metres along the line axis
static func openings(mj: Dictionary, ln: String) -> Array:
	var out: Array = []
	for m in mj["members"]:
		if m["kind"] != "window" and m["kind"] != "door":
			continue
		if str(m["name"]).split(".")[1] != ln:
			continue
		var b: Array = m["box_mm"]
		var al := 0 if (ln == "F" or ln == "B") else 2
		out.append({"lo": b[al] * 0.001, "hi": b[al + 3] * 0.001, "y0": b[1] * 0.001, "y1": b[4] * 0.001, "kind": m["kind"]})
	out.sort_custom(func(p, q): return p["lo"] < q["lo"])
	return out


## full-height piers [lo, hi] along the line axis between the openings
static func piers(mj: Dictionary, ln: String) -> Array:
	var lo := CT
	var hi := line_len(ln) - CT
	var res: Array = []
	var cur := lo
	for o in openings(mj, ln):
		if o["lo"] - cur > 0.05:
			res.append([cur, o["lo"]])
		cur = maxf(cur, o["hi"])
	if hi - cur > 0.05:
		res.append([cur, hi])
	return res


static func opening_area(mj: Dictionary) -> Dictionary:
	var win := 0.0
	var door := 0.0
	for ln in LINES:
		for o in openings(mj, ln):
			var a: float = (o["hi"] - o["lo"]) * (o["y1"] - o["y0"])
			if o["kind"] == "window":
				win += a
			else:
				door += a
	return {"window": win, "door": door}


static func roof_slope_area() -> float:
	return LX * (LZ + 2.0 * 0.406) * sqrt(1.0 + 1.0 / 9.0)


static func gable_area() -> float:
	return 2.0 * 0.5 * LZ * (3.95 - 2.467)


static func partition_area(mj: Dictionary) -> float:
	var a := 0.0
	for m in mj["members"]:
		if m["kind"] == "top_plate1":
			var ln: String = str(m["name"]).split(".")[1]
			if ln in LINES:
				continue
			var b: Array = m["box_mm"]
			a += maxf(b[3] - b[0], b[5] - b[2]) * 0.001 * HW
		elif m["kind"] == "idoor":
			var b2: Array = m["box_mm"]
			a -= maxf(b2[3] - b2[0], b2[5] - b2[2]) * 0.001 * (b2[4] - b2[1]) * 0.001
	return a


static func _positions(prs: Array, mid := false) -> Array:
	var ps: Array = []
	for p in prs:
		ps.append(p[0])
		if mid:
			ps.append(0.5 * (p[0] + p[1]))
		ps.append(p[1])
	ps.sort()
	var u: Array = []
	for v in ps:
		if u.is_empty() or v - u[u.size() - 1] > 0.002:
			u.append(v)
	return u


static func _spread(a: Acc, idx: Array, kg: float) -> void:
	for i in idx:
		a.add_mass(i, kg / idx.size())


static func _panel(a: Acc, ln: String, lo: float, hi: float, kh: float) -> void:
	var n1 := a.node(line_point(ln, lo, 0.0))
	var n2 := a.node(line_point(ln, hi, H))
	var n3 := a.node(line_point(ln, hi, 0.0))
	var n4 := a.node(line_point(ln, lo, H))
	var dx := hi - lo
	var dl := sqrt(dx * dx + H * H)
	var kd := 0.5 * kh * dl * dl / (dx * dx)
	a.springs.append_array([n1, n2, kd, n3, n4, kd])
	a.panels.append({"a1": n1, "b1": n2, "a2": n3, "b2": n4, "kh": kh, "b": dx, "h": H, "dx": dx, "dl": dl, "line": ln})


static func _roof_diaphragm(a: Acc) -> void:
	var c00 := a.node(Vector3(CT, H, CT))
	var c10 := a.node(Vector3(LX - CT, H, CT))
	var c11 := a.node(Vector3(LX - CT, H, LZ - CT))
	var c01 := a.node(Vector3(CT, H, LZ - CT))
	var bx := LX - 2.0 * CT
	var bz := LZ - 2.0 * CT
	var d2 := bx * bx + bz * bz
	var kd := GT_ROOF * d2 / (2.0 * bx * bz)
	a.springs.append_array([c00, c11, kd, c10, c01, kd])


## roof mass, ceiling, partitions, glazing common to the new systems. returns the masses added to the base (kg)
static func _common_mass(a: Acc, mj: Dictionary, tops: Array, parts: Dictionary, roof_kgm2: float) -> float:
	var oa := opening_area(mj)
	var base := 0.0
	var glass: float = (oa["window"] + oa["door"]) * GLASS_KGM2
	_spread(a, tops, 0.5 * glass)
	base += 0.5 * glass
	parts["glazing"] = glass
	var part: float = partition_area(mj) * PART_KGM2
	_spread(a, tops, 0.5 * part)
	base += 0.5 * part
	parts["partitions"] = part
	parts["roof"] = roof_slope_area() * roof_kgm2
	_spread(a, tops, parts["roof"])
	parts["ceiling"] = LX * LZ * GYP_KGM2
	_spread(a, tops, parts["ceiling"])
	return base


static func _finish(a: Acc, base_mass: float, parts: Dictionary, name: String) -> Dictionary:
	var xyz := PackedFloat64Array()
	var mass := PackedFloat64Array()
	for i in a.nodes.size():
		xyz.append_array([a.nodes[i].x, a.nodes[i].y, a.nodes[i].z])
		mass.append(a.lump.get(i, 0.0))
	var base: Array = []
	var tops: Array = []
	for i in a.nodes.size():
		if a.nodes[i].y < 0.03:
			base.append(i)
		elif absf(a.nodes[i].y - H) < 0.004:
			tops.append(i)
	var tot := base_mass
	for v in mass:
		tot += v
	# rigid roof diaphragm in plan (ux, uz of every top node follow a master node at mid-plan), as in slab/ring-beam practice; replaces the Ga roof springs for these two systems
	var ties := PackedFloat64Array()
	var bms: PackedFloat64Array = a.beams
	var nt := tops.size()
	var master := a.nodes.size()
	xyz.append_array([LX * 0.5, H, LZ * 0.5])
	mass.append(0.0)
	for k in nt:
		var i: int = tops[k]
		var c := master + 1 + k
		xyz.append_array([a.nodes[i].x, a.nodes[i].y, a.nodes[i].z])
		mass.append(0.0)
		bms.append_array([master, c, 1.0, 1.0, 1.0, 2.0, 1e13, 1e13 / 2.6, 0.0, 0, 1, 0])
		ties.append_array([i * 6 + 0, c * 6 + 0, 1e12, i * 6 + 2, c * 6 + 2, 1e12])
	return {"name": name, "nodes": a.nodes, "model": {"xyz": xyz, "beams": bms, "springs": a.springs, "fixed": PackedInt32Array(), "mass": mass, "ties": ties},
		"base": PackedInt32Array(base), "top": PackedInt32Array(tops), "base_mass": base_mass, "mass_total": tot, "parts": parts, "panels": a.panels,
		"panel_mode": "own", "floaters": PackedInt32Array()}


static func build_masonry(mj: Dictionary) -> Dictionary:
	var a := Acc.new()
	var sc := rect(T_WALL, T_WALL)
	var st := rect(T_WALL, 0.19)
	var sb := rect(T_WALL, 0.30)
	var parts := {}
	var cols := {}
	var tie_len := 0.0
	for ln in LINES:
		var prs := piers(mj, ln)
		var pos := _positions(prs)
		for i in pos.size() - 1:
			a.beam(line_point(ln, pos[i], H), line_point(ln, pos[i + 1], H), st, E_RC, G_RC, Vector3.UP)
			a.beam(line_point(ln, pos[i], 0.0), line_point(ln, pos[i + 1], 0.0), sb, E_RC, G_RC, Vector3.UP)
		tie_len += line_len(ln) - 2.0 * CT
		for s in pos:
			var p0 := line_point(ln, s, 0.0)
			var k := Vector3i(roundi(p0.x * 1000.0), 0, roundi(p0.z * 1000.0))
			if not cols.has(k):
				cols[k] = true
				a.beam(p0, line_point(ln, s, H), sc, E_RC, G_RC, Vector3.RIGHT)
		for p in prs:
			var b: float = p[1] - p[0]
			if HW / b <= HO.ASPECT_MAX:
				var Im := T_WALL * b * b * b / 12.0
				var Am := T_WALL * b
				var kh := 1.0 / (pow(H, 3) / (12.0 * E_MAS * Im) + 1.2 * H / (G_MAS * Am))
				_panel(a, ln, p[0], p[1], kh)
	var tops: Array = []
	for i in a.nodes.size():
		if absf(a.nodes[i].y - H) < 0.004:
			tops.append(i)
	var oa := opening_area(mj)
	var gross := 2.0 * (LX + LZ) * HW
	var net: float = gross - oa["window"] - oa["door"]
	var wall: float = net * WALL_KGM2
	parts["walls"] = wall
	var ncol := cols.size()
	var col: float = ncol * T_WALL * T_WALL * HW * RHO_RC
	parts["tie columns"] = col
	var tb: float = tie_len * T_WALL * 0.19 * RHO_RC
	parts["tie beam"] = tb
	var bb: float = tie_len * T_WALL * 0.30 * RHO_RC
	parts["baldrame"] = bb
	var gab: float = gable_area() * WALL_KGM2
	parts["gable masonry"] = gab
	var base := 0.5 * wall + 0.5 * col + bb
	_spread(a, tops, 0.5 * wall + 0.5 * col + tb + gab)
	base += _common_mass(a, mj, tops, parts, 15.0 + 45.0)    # timber roof 15 + ceramic tile 45 kg/m2 slope (UNVERIFIED, NBR 6120)
	return _finish(a, base, parts, "masonry")


static func lsf_counts(mj: Dictionary) -> Dictionary:
	var n_end := {}
	var n_int := 0
	for ln in LINES:
		for p in piers(mj, ln):
			for s in p:
				var q := line_point(ln, s, 0.0)
				n_end[Vector3i(roundi(q.x * 1000.0), 0, roundi(q.z * 1000.0))] = true
			n_int += maxi(0, int(floor((p[1] - p[0]) / 0.4)) - 1)
	return {"end": n_end.size(), "int": n_int}


static func build_lsf(mj: Dictionary) -> Dictionary:
	var a := Acc.new()
	var cs := cee_section()
	var trk := {"A": (0.090 + 2.0 * 0.040) * T_STUD, "Iz": 0.090 * 0.090 * 0.090 * T_STUD / 12.0, "Iy": 2.0 * T_STUD * pow(0.040, 3) / 12.0, "J": (0.090 + 0.08) * pow(T_STUD, 3) / 3.0}
	var parts := {}
	var done := {}
	var gt: float = 1000.0 * GA_LSF_KIPS * LB_IN
	var stud_total := 0
	var track_len := 0.0
	for ln in LINES:
		var prs := piers(mj, ln)
		var pos := _positions(prs, true)
		var door_gaps: Array = []
		for o in openings(mj, ln):
			if o["kind"] == "door":
				door_gaps.append([o["lo"], o["hi"]])
		for i in pos.size() - 1:
			a.beam(line_point(ln, pos[i], H), line_point(ln, pos[i + 1], H), trk, E_ST, G_ST, Vector3.UP)
			var mid: float = 0.5 * (pos[i] + pos[i + 1])
			var in_door := false
			for g in door_gaps:
				if mid > g[0] and mid < g[1]:
					in_door = true
			if not in_door:
				a.beam(line_point(ln, pos[i], 0.0), line_point(ln, pos[i + 1], 0.0), trk, E_ST, G_ST, Vector3.UP)
		track_len += 2.0 * (line_len(ln) - 2.0 * CT)
		var out_e2 := Vector3(0, 0, 1) if (ln == "F" or ln == "B") else Vector3(1, 0, 0)    # wall thickness direction: the web depth runs out of plane
		for p in prs:
			var b: float = p[1] - p[0]
			for s in p:
				var q := line_point(ln, s, 0.0)
				var k := Vector3i(roundi(q.x * 1000.0), 0, roundi(q.z * 1000.0))
				if not done.has(k):
					done[k] = true
					var sec2 := {"A": 2.0 * cs["A"], "Iz": 2.0 * cs["Iz"], "Iy": 2.0 * cs["Iy"], "J": 2.0 * cs["J"]}
					a.beam(q, line_point(ln, s, H), sec2, E_ST, G_ST, out_e2)
			var ni := maxi(0, int(floor(b / 0.4)) - 1)
			if ni > 0:
				var sm: float = 0.5 * (p[0] + p[1])
				var secn := {"A": ni * cs["A"], "Iz": ni * cs["Iz"], "Iy": ni * cs["Iy"], "J": ni * cs["J"]}
				a.beam(line_point(ln, sm, 0.0), line_point(ln, sm, H), secn, E_ST, G_ST, out_e2)
			if HW / b <= HO.ASPECT_MAX:
				_panel(a, ln, p[0], p[1], gt * b / H)
	var tops: Array = []
	for i in a.nodes.size():
		if absf(a.nodes[i].y - H) < 0.004:
			tops.append(i)
	var oa := opening_area(mj)
	var net: float = 2.0 * (LX + LZ) * HW - oa["window"] - oa["door"]
	# all studs of the real wall (every 400 mm plus doubled at each opening), not only the modelled pier columns: lumped
	var nst := 0
	var nop := 0
	for ln in LINES:
		nst += int(ceil((line_len(ln) - 2.0 * CT) / 0.4)) + 1
		nop += openings(mj, ln).size()
	nst += 2 * nop
	stud_total = nst
	var steel: float = nst * cs["A"] * HW * RHO_ST + 2.0 * 2.0 * (LX + LZ - 4.0 * CT) * trk["A"] * RHO_ST
	parts["studs and tracks"] = steel
	var skins: float = net * (7.1 + 11.0 + GYP_KGM2)    # OSB 11.1 mm + cement board cladding 11 kg/m2 (UNVERIFIED) + gypsum
	parts["wall skins"] = skins
	var gab: float = gable_area() * 25.0
	parts["gable"] = gab
	var base := 0.5 * (steel + skins)
	_spread(a, tops, 0.5 * (steel + skins) + gab)
	base += _common_mass(a, mj, tops, parts, 8.0 + 7.1 + 9.8)   # steel truss 8 + OSB 7.1 + asphalt shingle 9.8 kg/m2 slope
	var r := _finish(a, base, parts, "lsf")
	r["studs"] = stud_total
	return r


## the CH10 wood house wrapped in the same dictionary shape. Floating pieces stay pinned; base translation fixity is dropped (the footing replaces it)
static func build_wood(mj: Dictionary) -> Dictionary:
	var bld := HO.build(mj, {})
	var mm := HO.to_model(bld)
	var ms := HO.masses(bld)
	var model: Dictionary = (mm["model"] as Dictionary).duplicate()
	var keep: PackedInt32Array = mm["keep"]
	var base := PackedInt32Array()
	var fl := PackedInt32Array()
	for i in bld["nodes"].size():
		if keep[i] == 0:
			fl.append(i)
		elif bld["nodes"][i].y < 0.03:
			base.append(i)
	var top := PackedInt32Array()
	for i in bld["nodes"].size():
		if keep[i] == 1 and absf(bld["nodes"][i].y - 2.448) < 0.004:
			top.append(i)
	model["mass"] = ms["mass"]
	var fixed := PackedInt32Array()
	for i in fl:
		for d in 6:
			fixed.append(i * 6 + d)
	model["fixed"] = fixed
	var base_mass := 0.0
	for k in ms["parts"]:
		if "upper half" in k:
			base_mass += ms["parts"][k]
	var panels: Array = []
	for p in bld["panels"]:
		if not p["active"] or p["spr"].size() < 2:
			continue
		var s1: Array = bld["springs"][p["spr"][0]]
		var s2: Array = bld["springs"][p["spr"][1]]
		var dl: float = (bld["nodes"][s1[1]] - bld["nodes"][s1[0]]).length()
		var dxx: float = absf((bld["nodes"][s1[1]] - bld["nodes"][s1[0]])[0 if (p["line"] == "F" or p["line"] == "B") else 2])
		panels.append({"a1": s1[0], "b1": s1[1], "a2": s2[0], "b2": s2[1], "kh": p["kh"], "b": p["b"], "h": HO.WALL_H, "dx": dxx, "dl": dl, "line": p["line"]})
	var total := 0.0
	var bm: PackedFloat64Array = model["beams"]
	var xyz: PackedFloat64Array = model["xyz"]
	for b in range(0, bm.size(), 12):
		var n1 := int(bm[b])
		var n2 := int(bm[b + 1])
		var L := Vector3(xyz[n1 * 3], xyz[n1 * 3 + 1], xyz[n1 * 3 + 2]).distance_to(Vector3(xyz[n2 * 3], xyz[n2 * 3 + 1], xyz[n2 * 3 + 2]))
		total += bm[b + 8] * bm[b + 2] * L
	for v in ms["mass"]:
		total += v
	return {"name": "wood", "nodes": bld["nodes"], "model": model, "base": base, "top": top, "base_mass": base_mass, "mass_total": total + base_mass, "parts": ms["parts"], "panels": panels,
		"panel_mode": "own", "floaters": fl, "bld": bld}


static func build(system: String, mj: Dictionary) -> Dictionary:
	match system:
		"masonry":
			return build_masonry(mj)
		"lsf":
			return build_lsf(mj)
	return build_wood(mj)


# ---------------------------------------------------------------------------------------------------------------- assembly
## total mass of a model dict (beams rho A L + nodal mass), kg
static func model_mass(model: Dictionary) -> float:
	var t := 0.0
	var bm: PackedFloat64Array = model["beams"]
	var xyz: PackedFloat64Array = model["xyz"]
	for b in range(0, bm.size(), 12):
		var n1 := int(bm[b])
		var n2 := int(bm[b + 1])
		t += bm[b + 8] * bm[b + 2] * Vector3(xyz[n1 * 3], xyz[n1 * 3 + 1], xyz[n1 * 3 + 2]).distance_to(Vector3(xyz[n2 * 3], xyz[n2 * 3 + 1], xyz[n2 * 3 + 2]))
	for v in model.get("mass", PackedFloat64Array()):
		t += v
	return t


## the frame model for system sys on soil s (a Ch1fSoil.soil dict) or fixed (s == null: base translations fixed, the CH10 convention).
## opts: foot_mass (kg at the footing node, default slab + the system's lower wall half), tie_rot (also tie rotations), pdelta (default true), footprint [lx, lz]
static func assemble(sys: Dictionary, s, opts := {}) -> Dictionary:
	var src: Dictionary = sys["model"]
	var model := {"xyz": (src["xyz"] as PackedFloat64Array).duplicate(), "beams": (src["beams"] as PackedFloat64Array).duplicate(), "springs": src["springs"],
		"mass": (src["mass"] as PackedFloat64Array).duplicate(), "fixed": (src["fixed"] as PackedInt32Array).duplicate()}
	if src.has("ties"):
		model["ties"] = (src["ties"] as PackedFloat64Array).duplicate()
	var n0: int = (model["xyz"] as PackedFloat64Array).size() / 3
	var base: PackedInt32Array = sys["base"]
	var out := {"model": model, "n0": n0, "f": -1}
	if s == null:
		var fx: PackedInt32Array = model["fixed"]
		for b in base:
			for d in 3:
				fx.append(b * 6 + d)
		model["fixed"] = fx
		if opts.get("pdelta", true):
			model["axial"] = gravity_axial(model)
		return out
	var lx: float = opts.get("lx", LX)
	var lz: float = opts.get("lz", LZ)
	var g := SO.gazetas(s, lx, lz)
	var F := n0
	var xyz: PackedFloat64Array = model["xyz"]
	xyz.append_array([lx * 0.5, 0.0, lz * 0.5])
	var mass: PackedFloat64Array = model["mass"]
	mass.append(opts.get("foot_mass", lx * lz * SLAB_T * RHO_RC + sys["base_mass"]))
	var bm: PackedFloat64Array = model["beams"]
	var ties: PackedFloat64Array = model.get("ties", PackedFloat64Array())
	var ktie: float = opts.get("ktie", 1e12)
	var nb0 := bm.size() / 12
	var k := 0
	for b in base:
		var c := n0 + 1 + k
		k += 1
		var p := Vector3(xyz[b * 3], xyz[b * 3 + 1], xyz[b * 3 + 2])
		xyz.append_array([p.x, p.y, p.z])
		mass.append(0.0)
		var d := p - Vector3(lx * 0.5, 0.0, lz * 0.5)
		var e2 := Vector3.UP
		if absf(d.normalized().dot(e2)) > 0.999:
			e2 = Vector3.RIGHT
		bm.append_array([F, c, 1.0, 1.0, 1.0, 2.0, 1e13, 1e13 / 2.6, 0.0, e2.x, e2.y, e2.z])
		for dd in 3:
			ties.append_array([b * 6 + dd, c * 6 + dd, ktie])
		if opts.get("tie_rot", false):
			for dd in range(3, 6):
				ties.append_array([b * 6 + dd, c * 6 + dd, ktie])
	model["xyz"] = xyz
	model["mass"] = mass
	model["beams"] = bm
	model["ties"] = ties
	model["dofk"] = SO.dofk_for(g, F)
	model["dofc"] = SO.dofc_for(g, F)
	out["f"] = F
	out["g"] = g
	out["nbeams_struct"] = nb0
	if opts.get("pdelta", true):
		var N := gravity_axial(model)
		var bmm: PackedFloat64Array = model["beams"]
		for i in N.size():
			if i >= nb0 or bmm[i * 12 + 6] >= 1e12:
				N[i] = 0.0
		model["axial"] = N
	return out


## per-beam axial force (tension +) under self weight: nodal weights from node mass and half of each beam's own mass on each end
static func gravity_axial(model: Dictionary) -> PackedFloat64Array:
	var xyz: PackedFloat64Array = model["xyz"]
	var n := xyz.size() / 3
	var w := PackedFloat64Array()
	w.resize(n * 6)
	var mass: PackedFloat64Array = model["mass"]
	for i in n:
		w[i * 6 + 1] = -G_ACC * mass[i]
	var bm: PackedFloat64Array = model["beams"]
	for b in range(0, bm.size(), 12):
		var n1 := int(bm[b])
		var n2 := int(bm[b + 1])
		var L := Vector3(xyz[n1 * 3], xyz[n1 * 3 + 1], xyz[n1 * 3 + 2]).distance_to(Vector3(xyz[n2 * 3], xyz[n2 * 3 + 1], xyz[n2 * 3 + 2]))
		var half: float = 0.5 * bm[b + 8] * bm[b + 2] * L * G_ACC
		w[n1 * 6 + 1] -= half
		w[n2 * 6 + 1] -= half
	var m2 := model.duplicate()
	m2.erase("axial")
	var st := FR.solve(m2, {"type": "static", "loads": w})
	if st.has("error"):
		return PackedFloat64Array()
	var ax := FR.solve(m2, {"type": "axial", "u": st["u"]})
	return ax["N"]
