extends SceneTree
## godot --headless --path . -s tests/ch1e_test.gd   (CH1e: the CH1 house with REAL fasteners: nails, sheathing nails, anchor bolts + washers, H2.5A ties, HDU2 hold-downs as geometry)
## Bars (written and committed before any number was read; every per-fastener value and its source is in docs/CH1e_REFERENCE.md):
##  S SCHEDULE   every connection the module places is checked against IRC 2021 Table R602.3(1) as stored in HouseCheck.FASTENERS (read by THIS test, not by the module):
##               - a per-connection row (toenails, laps, header-to-stud): the nails of the connection == the row's n, exactly;
##               - a spacing row (plate-to-plate 16 in, stud-to-stud 24 in, built-up header 16 in each edge, sheathing 6 in edge / 12 in field): no gap along the line is more than the
##                 row + 1/4 in (6.35 mm);
##               - every connection TYPE of HouseCheck.connections_of(meta.member_kinds) has at least one connection placed;
##               - every vertical member (stud, king, jack, cripple, corner, end, nailer) has BOTH its ends in a stud_to_plate connection (this test finds the ends from the member
##                 boxes, not from the module's contact list);
##               - anchor bolts: 1/2 in, embed >= 7 in, spacing <= 72 in and within 12 in (>= 3.5 in) of each plate end, a plate washer on each; H2.5A: one per rafter (count == meta ties.count == 34).
##  F FLOAT      no fastener floats: the shank start is within 1 mm (+ the connector's sheet thickness for tie and hold-down fasteners) of the surface of its first member; the shank has >= 3 mm
##               inside the first member and >= 3 mm inside the second; every sample of the shank is inside some framing / sheathing / concrete member except a tip tail of at most 16 mm
##               (a 3-1/2 in nail through 3 in of lumber, as the code row itself implies). CONTROL: one nail moved 20 mm sideways is caught.
##  C COUNT      total and per type printed; the nails of ONE wall (left gable wall L) equal a hand count made in this file:
##               toenails = 8 per vertical member (4 at each end), sheathing nails = per piece: edge intervals ceil(edge/152.4) around the 9.5 mm inset rectangle + field lines at the studs
##               (interior intervals ceil(h'/304.8), n-1 nails per line), king/jack face nails = per pair the equal-spacing rule at 24 in with 3 in ends.
##  K CAPACITY   5 sampled joints: capacity from placed fasteners == hand calc made here from docs/CH1e_REFERENCE.md values within 1 pct (the hand values are typed in this file).
##  P PLANTED    a copy of the house with every second sheathing nail of wall L removed: that wall's sheathing capacity is 0.5 +- 0.03 of the full one and the schedule bar FAILS for it
##               (and the full house does not fail).
##  R REPLACED   HouseCheck.TIES toenail3-8d == 3 x 28 x 1.6 lb (no longer UNVERIFIED) and docs/CH1e_REFERENCE.md names every replaced value.
##  N NATIVE     KineFastenerNative (C++) == GDScript on contacts, first-hit probes and the shank validation (same ids, max |diff| < 1e-6); skipped with a FAIL if the class is absent.
var fails := 0
const CF := preload("res://scripts/build/ch1e_fast.gd")
const HC := preload("res://scripts/build/house_check.gd")
const IN := 25.4


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func near(a: float, b: float, pct: float) -> bool:
	return absf(a - b) <= absf(b) * pct / 100.0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var F: Dictionary = CF.build(mj, {})
	print("build ms ", Time.get_ticks_msec() - t0, "  nails ", F["n"], "  connections ", F["conns"].size(), "  parts ", F["parts"].size())
	var V: Dictionary = CF.validate(F)
	_schedule(F, mj)
	_float(F, V)
	_count(F, mj)
	_capacity(F, V, mj)
	_planted(mj)
	_replaced()
	_native(F, mj)
	print("ch1e: %d fail" % fails)
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- S
func _row_n(key: String) -> int:
	return int(HC.FASTENERS[key]["n"])


func _gaps_ok(F: Dictionary, c: Dictionary, nominal_in: float) -> Array:
	## positions of the nails of connection c along the axis of its line, sorted; returns [max gap mm, count]
	var ids: Array = c["nails"]
	if ids.size() < 2:
		return [0.0, ids.size()]
	var h: PackedVector3Array = F["head"]
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for i in ids:
		var p: Vector3 = h[i]
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var ext := hi - lo
	var ax := 0
	if ext.y > ext[ax]:
		ax = 1
	if ext.z > ext[ax]:
		ax = 2
	var pos: Array = []
	for i in ids:
		pos.append(float(h[i][ax]))
	pos.sort()
	var mg := 0.0
	for k in range(1, pos.size()):
		mg = maxf(mg, pos[k] - pos[k - 1])
	return [mg, pos.size()]


func _schedule(F: Dictionary, mj: Dictionary) -> void:
	var keys := {}
	var bad_n: Array = []
	var bad_gap: Array = []
	var worst := 0.0
	for c in F["conns"]:
		keys[c["key"]] = int(keys.get(c["key"], 0)) + 1
		var k: String = c["key"]
		if HC.FASTENERS.has(k):
			var row: Dictionary = HC.FASTENERS[k]
			if float(row["spacing_in"]) <= 0.0:
				if c["nails"].size() != _row_n(k):
					bad_n.append("%s %s has %d, row says %d" % [k, c["label"], c["nails"].size(), _row_n(k)])
			else:
				var g: Array = _gaps_ok(F, c, float(row["spacing_in"]))
				worst = maxf(worst, g[0] - float(row["spacing_in"]) * IN)
				if g[0] > float(row["spacing_in"]) * IN + 6.35 or g[1] < 2:
					bad_gap.append("%s %s gap %.1f mm over %d nails (limit %.1f)" % [k, c["label"], g[0], g[1], float(row["spacing_in"]) * IN + 6.35])
	ok(bad_n.is_empty(), "S1 per-connection rows: every connection has exactly the row's nail count (%d bad: %s)" % [bad_n.size(), str(bad_n.slice(0, 3))])
	ok(bad_gap.is_empty(), "S2 spacing rows: no gap over row + 1/4 in (%d bad: %s; worst excess %.2f mm)" % [bad_gap.size(), str(bad_gap.slice(0, 3)), worst])
	var want: Array = HC.connections_of(mj["meta"]["member_kinds"])
	var miss: Array = []
	for k in want:
		if not keys.has(k):
			miss.append(k)
	ok(miss.is_empty(), "S3 every schedule type has fasteners placed (%s; missing %s)" % [str(keys), str(miss)])
	# S4: every vertical member end is in a stud_to_plate connection (ends found here from the boxes)
	var idx := {}
	for i in mj["members"].size():
		idx[mj["members"][i]["name"]] = i
	var in_conn := {}
	for c in F["conns"]:
		if c["key"] == "stud_to_plate":
			in_conn["%s|%s" % [F["names"][c["a"]], c["end"]]] = true
	var vert := ["stud", "king", "jack", "cripple", "corner", "end", "nailer"]
	var nv := 0
	var missing_end: Array = []
	for m in mj["members"]:
		if m["kind"] in vert:
			nv += 1
			for e in ["bot", "top"]:
				if not in_conn.has("%s|%s" % [m["name"], e]):
					missing_end.append("%s %s" % [m["name"], e])
	ok(missing_end.is_empty(), "S4 both ends of all %d vertical members are nailed (%d missing: %s)" % [nv, missing_end.size(), str(missing_end.slice(0, 5))])
	# S5 bolts and ties
	var bolts := 0
	var wash := 0
	var bolt_bad: Array = []
	var ties := 0
	var hdu := 0
	for p in F["parts"]:
		match p["kind"]:
			"anchor_bolt":
				bolts += 1
				if absf(float(p["dia_in"]) - 0.5) > 1e-6 or float(p["embed_in"]) < 7.0 - 0.01:
					bolt_bad.append(p["name"])
			"plate_washer":
				wash += 1
			"h25a":
				ties += 1
			"hdu2":
				hdu += 1
	ok(bolts > 0 and bolt_bad.is_empty() and wash == bolts, "S5a %d anchor bolts, each 1/2 in dia, embed >= 7 in, %d plate washers (bad %s)" % [bolts, wash, str(bolt_bad)])
	var sp: Dictionary = F["bolt_layout"]
	ok(float(sp["max_gap_in"]) <= 72.0 + 1e-6 and float(sp["max_end_in"]) <= 12.0 + 1e-6 and float(sp["min_end_in"]) >= 3.5 - 1e-6, "S5b bolt layout per plate: max gap %.2f in <= 72, ends %.2f..%.2f in within 3.5..12 (R403.1.6)" % [sp["max_gap_in"], sp["min_end_in"], sp["max_end_in"]])
	ok(ties == int(mj["meta"]["ties"]["count"]), "S5c one H2.5A per rafter: %d == meta %d" % [ties, mj["meta"]["ties"]["count"]])
	ok(hdu > 0, "S5d hold-downs at shear-wall ends: %d HDU2 placed (segments with h/b <= 3.5 and a doubled king + jack post)" % hdu)


# ---------------------------------------------------------------- F
func _float(F: Dictionary, V: Dictionary) -> void:
	var n: int = F["n"]
	var bad: Array = []
	var mg := 0.0
	var ma := 1e9
	var mb := 1e9
	var mt := 0.0
	var mh := 0.0
	for i in n:
		var st: float = F["stand"][i]
		var hg: float = V["head_gap"][i] - st
		mg = maxf(mg, hg)
		ma = minf(ma, V["len_a"][i])
		mb = minf(mb, V["len_b"][i])
		mt = maxf(mt, V["tail"][i])
		mh = maxf(mh, V["holes"][i])
		if hg > 1.0 or V["len_a"][i] < 3.0 or V["len_b"][i] < 3.0 or V["tail"][i] > 16.0 or V["holes"][i] > 0.5:
			bad.append(i)
	ok(bad.is_empty(), "F1 no fastener floats: %d of %d fail (worst head gap %.2f mm, min in first member %.1f mm, min in second %.1f mm, max tail %.1f mm, max hole %.2f mm)" % [bad.size(), n, mg, ma, mb, mt, mh])
	if not bad.is_empty():
		var f: Array = []
		for i in bad.slice(0, 5):
			f.append("%d %s %s/%s gap %.2f a %.1f b %.1f tail %.1f hole %.2f" % [i, F["tname"][i], F["names"][F["a"][i]], F["names"][F["b"][i]], V["head_gap"][i] - F["stand"][i], V["len_a"][i], V["len_b"][i], V["tail"][i], V["holes"][i]])
		print("   first failing: ", f)
	# CONTROL: move one nail 20 mm along z and x, the check must flag it
	var G: Dictionary = F.duplicate()
	var hh: PackedVector3Array = F["head"].duplicate()
	hh[100] += Vector3(20, 0, 20)
	G["head"] = hh
	var V2: Dictionary = CF.validate(G, false, [100])
	var st100: float = F["stand"][100]
	var flagged: bool = (V2["head_gap"][100] - st100 > 1.0) or V2["len_a"][100] < 3.0 or V2["len_b"][100] < 3.0 or V2["tail"][100] > 16.0 or V2["holes"][100] > 0.5
	ok(flagged, "F2 control: nail 100 moved 20 mm is caught (gap %.2f a %.1f b %.1f tail %.1f hole %.2f)" % [V2["head_gap"][100] - st100, V2["len_a"][100], V2["len_b"][100], V2["tail"][100], V2["holes"][100]])


# ---------------------------------------------------------------- C
func _count(F: Dictionary, mj: Dictionary) -> void:
	var by := {}
	for i in F["n"]:
		by[F["tname"][i]] = int(by.get(F["tname"][i], 0)) + 1
	print("   nails total %d  by type %s  (+ %d bolts, %d washers, %d H2.5A, %d HDU2 as parts)" % [F["n"], str(by), _pk(F, "anchor_bolt"), _pk(F, "plate_washer"), _pk(F, "h25a"), _pk(F, "hdu2")])
	var bk := {}
	for c in F["conns"]:
		bk[c["key"]] = int(bk.get(c["key"], 0)) + int(c["nails"].size())
	print("   nails per schedule row ", bk)
	ok(F["n"] >= 5000, "C1 thousands of fasteners placed: %d" % F["n"])
	# hand count of wall L
	var members: Array = mj["members"]
	var nv := 0
	for m in members:
		if String(m["name"]).split(".").size() > 1 and String(m["name"]).split(".")[1] == "L" and m["kind"] in ["stud", "king", "jack", "cripple", "corner", "end", "nailer"]:
			nv += 1
	var toe_got := 0
	for c in F["conns"]:
		if c["key"] == "stud_to_plate" and c["wall"] == "L":
			toe_got += c["nails"].size()
	ok(toe_got == 8 * nv, "C2 wall L toenails: placed %d == hand count 8 x %d vertical members = %d" % [toe_got, nv, 8 * nv])
	# sheathing of wall L: each piece
	var sh_got := 0
	for c in F["conns"]:
		if c["key"] == "sheathing" and c["wall"] == "L":
			sh_got += c["nails"].size()
	var sh_hand := 0
	var studs_l: Array = []
	for m in members:
		var p := String(m["name"]).split(".")
		if p.size() > 1 and p[1] == "L" and m["kind"] in ["stud", "king", "jack", "cripple"]:
			studs_l.append(m)
	for m in members:
		if m["kind"] == "wall_sheathing" and String(m["name"]).begins_with("sheathing.L."):
			var b: Array = m["box_mm"]
			var u0: float = b[2]
			var u1: float = b[5]
			var y0: float = b[1]
			var y1: float = b[4]
			var w := (u1 - u0) - 19.0
			var h := (y1 - y0) - 19.0
			sh_hand += 2 * (int(ceil(w / 152.4 - 1e-9)) + int(ceil(h / 152.4 - 1e-9)))
			var m_int := int(ceil(h / 304.8 - 1e-9))
			for s in studs_l:
				var sb: Array = s["box_mm"]
				var uc: float = 0.5 * (float(sb[2]) + float(sb[5]))
				# a field line: a supporting member whose centre is >= 30 mm from the two side edges, and that is behind the piece for the whole height
				if uc > u0 + 30.0 and uc < u1 - 30.0 and float(sb[1]) <= y0 + 40.0 + 1e-6 and float(sb[4]) >= y1 - 40.0 - 1e-6:
					sh_hand += m_int - 1
	print("   wall L sheathing nails placed %d, hand count (full-height lines) %d" % [sh_got, sh_hand])
	ok(sh_got >= sh_hand, "C3 wall L sheathing: placed %d >= hand count %d of the full-height field lines + perimeters (partial lines beside the openings add the rest)" % [sh_got, sh_hand])


func _pk(F: Dictionary, k: String) -> int:
	var n := 0
	for p in F["parts"]:
		if p["kind"] == k:
			n += 1
	return n


# ---------------------------------------------------------------- K
func _capacity(F: Dictionary, V: Dictionary, mj: Dictionary) -> void:
	# hand values (docs/CH1e_REFERENCE.md): AWC DA-2 toenails G 0.50 DF-L: 8d box W 28 / Z 60 lb; Simpson C-C-2021 p.277 H2.5A 625 lb uplift (160, 0.131x1.5 nails), F1 = F2 = 110 lb (160);
	# 16d common face nail Z = 117 / 0.83 = 140.96 lb, withdrawal 1380 G^2.5 D per inch; sheathing nail 100 lb at CD 1.6; HDU2-SDS2.5 3075 lb (160); anchor bolt shear 1040 lb (160)
	var G := 0.5
	var wpi16 := 1380.0 * pow(G, 2.5) * 0.162
	var cases: Array = []
	var c1 := _find(F, "stud_to_plate", "stud.L.0.0", "bot")
	var c2 := _find(F, "h25a", "rafter.front.0", "")
	var c3 := _find(F, "stud_to_stud", "king.L.0a", "")
	var c4 := _find_sheath(F, "sheathing.L.0")
	var c5 := _find(F, "hdu", "", "")
	cases.append([c1, 4.0 * 28.0, 4.0 * 60.0, "4-8d box toenail: T 4x28, V 4x60"])
	cases.append([c2, 625.0 / 1.6, 110.0 / 1.6, "H2.5A: T 625/1.6, V F1 110/1.6"])
	var nn: int = F["conns"][c3]["nails"].size() if c3 >= 0 else 0
	cases.append([c3, nn * wpi16 * (38.0 / IN), nn * (117.0 / 0.83), "king/jack face nails %d x 16d common: T 1380G^2.5 D x 38 mm, V 117/0.83" % nn])
	var ns: int = F["conns"][c4]["nails"].size() if c4 >= 0 else 0
	var wps := 1380.0 * pow(G, 2.5) * 0.113 * ((2.0 * IN - 11.1) / IN)
	cases.append([c4, ns * wps, ns * 100.0 / 1.6, "sheathing piece %d x 6d common: T 1380G^2.5 D x (2 in - 11.1 mm), V 100/1.6" % ns])
	cases.append([c5, 3075.0 / 1.6, -1.0, "HDU2-SDS2.5: T 3075/1.6"])
	var good := 0
	for cs in cases:
		var ci: int = cs[0]
		if ci < 0:
			ok(false, "K connection not found for: " + str(cs[3]))
			continue
		var cap: Dictionary = CF.capacity(F, ci, V)
		var okT := near(cap["T10"], cs[1], 1.0)
		var okV: bool = cs[2] < 0.0 or near(cap["V10"], cs[2], 1.0)
		ok(okT and okV, "K %s: computed T %.2f V %.2f lb against hand %.2f / %.2f" % [cs[3], cap["T10"], cap["V10"], cs[1], cs[2]])
		good += 1 if (okT and okV) else 0
	# anchor bolt: hand calc of HouseCheck.anchor_capacity by arithmetic here
	var dd := 0.5 - 0.9743 / 8.0
	var ase := 0.7854 * dd * dd
	var steel := 0.75 * 60000.0 * ase * 0.75 / 1.6
	var nb := 24.0 * sqrt(2500.0) * pow(7.0, 1.5)
	var conc := nb * 0.5 * 0.65 / 1.6
	var cb := _find(F, "anchor_bolt", "", "")
	if cb >= 0:
		var capb: Dictionary = CF.capacity(F, cb, V)
		ok(near(capb["T10"], minf(steel, conc), 1.0) and near(capb["V16"], 1040.0, 1.0), "K anchor bolt: T %.1f vs hand %.1f, V(160) %.1f vs 1040" % [capb["T10"], minf(steel, conc), capb["V16"]])
	else:
		ok(false, "K no anchor bolt connection")


func _find(F: Dictionary, key: String, member: String, end: String) -> int:
	for c in F["conns"]:
		if c["key"] != key:
			continue
		if member == "" or F["names"][c["a"]] == member:
			if end == "" or c["end"] == end:
				return int(c["id"])
	return -1


func _find_sheath(F: Dictionary, piece: String) -> int:
	for c in F["conns"]:
		if c["key"] == "sheathing" and F["names"][c["a"]] == piece:
			return int(c["id"])
	return -1


# ---------------------------------------------------------------- P
func _planted(mj: Dictionary) -> void:
	var F: Dictionary = CF.build(mj, {})
	var V: Dictionary = CF.validate(F)
	var full := _wall_sheath_cap(F, V, "L")
	var P: Dictionary = CF.decimate(F, "L")
	var VP: Dictionary = CF.validate(P)
	var half := _wall_sheath_cap(P, VP, "L")
	var r := half / full if full > 0.0 else 0.0
	ok(absf(r - 0.5) <= 0.03, "P1 half the sheathing nails on wall L -> sheathing V capacity %.1f of %.1f lb = %.3f (0.5 +- 0.03)" % [half, full, r])
	var f_full: Array = CF.schedule_failures(F)
	var f_half: Array = CF.schedule_failures(P)
	ok(f_full.is_empty() and not f_half.is_empty(), "P2 the schedule bar passes the full house (%d failures) and fails the planted one (%d failures, e.g. %s)" % [f_full.size(), f_half.size(), str(f_half.slice(0, 1))])


func _wall_sheath_cap(F: Dictionary, V: Dictionary, wall: String) -> float:
	var t := 0.0
	for c in F["conns"]:
		if c["key"] == "sheathing" and c["wall"] == wall:
			t += float(CF.capacity(F, int(c["id"]), V)["V10"])
	return t


# ---------------------------------------------------------------- R
func _replaced() -> void:
	ok(near(HC.TIES["toenail3-8d"], 3.0 * 28.0 * 1.6, 0.01) and HC.TIES_UNVERIFIED.is_empty(), "R1 house_check toenail3-8d = %.1f lb (3 x 28 x 1.6) and the UNVERIFIED flag is gone" % HC.TIES["toenail3-8d"])
	var doc := FileAccess.get_file_as_string("res://docs/CH1e_REFERENCE.md")
	var need := ["toenail3-8d", "H2.5A", "TOE_8D_W_LB", "TOE_8D_Z_LB", "TOE_16D_W", "TOE_16D_Z_LB", "FACE_16D_Z_LB", "H25A_V_LB", "ANCHOR_V_LB", "ANCHOR_T_LB", "Simpson Strong-Tie", "DA-2", "R602.3(1)"]
	var miss: Array = []
	for k in need:
		if not doc.contains(k):
			miss.append(k)
	ok(miss.is_empty(), "R2 docs/CH1e_REFERENCE.md names every replaced value and its source (missing %s)" % str(miss))


# ---------------------------------------------------------------- N
func _native(F: Dictionary, mj: Dictionary) -> void:
	var has: bool = NativeExt.ensure("kine_native", "KineFastenerNative")
	ok(has, "N0 KineFastenerNative loaded")
	if not has:
		return
	var a: Dictionary = CF.validate(F, false)
	var b: Dictionary = CF.validate(F, true)
	var md := 0.0
	for k in ["head_gap", "len_a", "len_b", "tail", "holes"]:
		for i in F["n"]:
			md = maxf(md, absf(float(a[k][i]) - float(b[k][i])))
	ok(md < 1e-6, "N1 validate: C++ == GDScript on %d nails, max |diff| %.2e" % [F["n"], md])
	var ca: Array = CF.contacts(F["solids"], false)
	var cb: Array = CF.contacts(F["solids"], true)
	ok(ca == cb and ca.size() > 100, "N2 contacts: C++ == GDScript (%d vs %d contacts)" % [ca.size(), cb.size()])
	var pts := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 3000:
		pts.append(Vector3(rng.randf_range(-500, 10300), rng.randf_range(-200, 4000), rng.randf_range(-500, 8200)))
	var ha: PackedInt32Array = CF.first_hits(F["solids"], pts, false)
	var hb: PackedInt32Array = CF.first_hits(F["solids"], pts, true)
	ok(ha == hb, "N3 first-hit probes: C++ == GDScript on 3000 random points")
	var t1 := Time.get_ticks_msec()
	CF.validate(F, false)
	var t2 := Time.get_ticks_msec()
	CF.validate(F, true)
	var t3 := Time.get_ticks_msec()
	print("   validate %d nails: GDScript %d ms, C++ %d ms" % [F["n"], t2 - t1, t3 - t2])
