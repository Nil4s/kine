class_name Ch10Sim
extends RefCounted
## CH10: the house under wind and El Centro. Wind per ASCE 7-16 Ch. 26-27 (directional MWFRS, walls only; roof components omitted and said so),
## the quake as base acceleration through Newmark average acceleration. Every constant has its source in docs/CH10_REFERENCE.md.

const H := preload("res://scripts/build/house_check.gd")
const SITE_ID := "levittown_ny"
const DT_RECORD := 0.02
const PSF := 47.88026    # N/m2 per psf
const MPH := 0.44704     # m/s per mph
const ELCENTRO := "res://data/ch10/elcentro_NS.dat"
const G := 9.80665
const DRIFT_ALLOWABLE := 0.020   # ASCE 7-16 Table 12.12-1, all other structures, Risk Category II (0.025 only if partitions are designed to accommodate drift)


## velocity pressure coefficient Kz, ASCE 7-16 Eq. 26.10-1, z in ft (z < 15 ft uses 15 ft)
static func kz(z_ft: float, exposure: String) -> float:
	var alpha := 7.0
	var zg := 1200.0
	if exposure == "C":
		alpha = 9.5
		zg = 900.0
	elif exposure == "D":
		alpha = 11.5
		zg = 700.0
	return 2.01 * pow(maxf(z_ft, 15.0) / zg, 2.0 / alpha)


## wind on the frame in direction dir (0 = +x, along the ridge, hits the gable end; 2 = +z, hits the eave wall F).
## returns {loads (6n), F (N total), q (Pa), p_w, p_l (Pa), cp_l, kz, detail}
static func wind(bld: Dictionary, n_nodes: int, dir: int, site_id := SITE_ID) -> Dictionary:
	var site: Dictionary = H.SITES[site_id]
	var V: float = float(site["wind_mph"])
	var expo: String = site["exposure"]
	var hmean_ft := (2.467 + 3.95) * 0.5 / 0.3048
	var kzv := kz(hmean_ft, expo)
	var q_psf := 0.00256 * kzv * 1.0 * 0.85 * V * V    # Kzt = 1, Kd = 0.85 (buildings, MWFRS), Ke = 1
	var q := q_psf * PSF
	var gust := 0.85
	var Lx := 9.754
	var Lz := 7.620
	var cp_w := 0.8
	# leeward Cp, ASCE 7-16 Fig. 27.3-1: L/B <= 1: -0.5, L/B = 2: -0.3, L/B >= 4: -0.2 (linear between)
	var LB := (Lx / Lz) if dir == 0 else (Lz / Lx)   # L = dimension parallel to the wind, B = normal to it
	var cp_l := -0.5
	if LB > 1.0:
		cp_l = -0.5 + 0.2 * (minf(LB, 2.0) - 1.0)
	var pw := q * gust * cp_w
	var pl := q * gust * cp_l
	var nodes: Array = bld["nodes"]
	# top-plate (t2) nodes of the windward and leeward wall lines
	var wind_line := "F" if dir == 2 else "L"
	var lee_line := "B" if dir == 2 else "R"
	var loads := PackedFloat64Array()
	loads.resize(n_nodes * 6)
	var total := 0.0
	var detail := {}
	for pass_i in 2:
		var pick: Array = []
		var line := wind_line if pass_i == 0 else lee_line
		for i in n_nodes:
			var p: Vector3 = nodes[i]
			if absf(p.y - 2.448) > 0.004:
				continue
			var on := false
			match line:
				"F": on = p.z < 0.06
				"B": on = p.z > 7.62 - 0.06
				"L": on = p.x < 0.06
				"R": on = p.x > 9.754 - 0.06
			if on:
				pick.append(i)
		var key := 0 if (line == "F" or line == "B") else 2
		pick.sort_custom(func(a, b): return nodes[a][key] < nodes[b][key])
		var length := Lx if key == 0 else Lz
		# area per unit length: half the wall height, plus the gable triangle on the gable end walls
		var a_per_len := 0.5 * 2.467
		if dir == 0:
			a_per_len = 0.5 * 2.467 + (0.5 * Lz * (3.95 - 2.467)) / Lz   # + the gable triangle (7.62 m base, 1.483 m rise), spread over the wall length
		var p_use := pw if pass_i == 0 else -pl     # leeward suction pulls the leeward wall downwind: same direction as the push
		for a in pick.size():
			var lo: float = nodes[pick[a]][key] if a == 0 else 0.5 * (nodes[pick[a - 1]][key] + nodes[pick[a]][key])
			var hi: float = nodes[pick[a]][key] if a == pick.size() - 1 else 0.5 * (nodes[pick[a]][key] + nodes[pick[a + 1]][key])
			if a == 0:
				lo = 0.0
			if a == pick.size() - 1:
				hi = length
			var f: float = p_use * a_per_len * (hi - lo)
			loads[pick[a] * 6 + dir] += f
			total += f
		detail[line] = {"nodes": pick.size(), "p": p_use, "a_per_len": a_per_len}
	return {"loads": loads, "F": total, "q": q, "p_w": pw, "p_l": pl, "cp_l": cp_l, "kz": kzv, "q_psf": q_psf, "V": V, "exposure": expo, "detail": detail}


static func load_record() -> PackedFloat64Array:
	## the El Centro 1940 NS record resampled to dt by linear interpolation: returns [t0.., a (m/s2)] as the acceleration series at the record's 0.02 s
	var f := FileAccess.open(ELCENTRO, FileAccess.READ)
	var out := PackedFloat64Array()
	while not f.eof_reached():
		var l := f.get_line().strip_edges()
		if l == "":
			continue
		var parts := l.split(" ", false)
		if parts.size() < 2:
			parts = l.split("\t", false)
		out.append(float(parts[1]) * G)
	return out


## the record at step dt (s): linear interpolation of the 0.02 s samples, scaled
static func resample(rec: PackedFloat64Array, dt: float, scale := 1.0, seconds := -1.0) -> PackedFloat64Array:
	var dur: float = (rec.size() - 1) * DT_RECORD if seconds < 0.0 else seconds
	var n := int(floor(dur / dt))
	var a := PackedFloat64Array()
	a.resize(n + 1)
	for i in n + 1:
		var t := i * dt / DT_RECORD
		var k := mini(int(floor(t)), rec.size() - 2)
		var w := t - k
		a[i] = scale * (rec[k] * (1.0 - w) + rec[k + 1] * w)
	return a


static func top_nodes(bld: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var nodes: Array = bld["nodes"]
	for i in nodes.size():
		var p: Vector3 = nodes[i]
		if absf(p.y - 2.448) < 0.004:
			out.append(i)
	return out


## Ta = Ct hn^x, ASCE 7-16 Table 12.8-2 all other systems Ct = 0.02, x = 0.75 (hn in ft)
static func ta(hn_ft: float) -> float:
	return 0.02 * pow(hn_ft, 0.75)
