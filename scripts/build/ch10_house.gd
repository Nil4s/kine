class_name Ch10House
extends RefCounted
## CH10: the CH1 house (out/ch1/members.json) as a 3D frame model for Ch10Frame (docs/CH10_REFERENCE.md has every number's source).
## Beams: studs, kings, jacks, cripples, plates, headers, sills, joists, ridge, rafters (Euler-Bernoulli, rigid joints, DF-L #2 E = 1.6e6 psi).
## Shear walls: every full-height OSB panel in a segment with h/b <= 3.5 becomes TWO crossed diagonal springs whose horizontal stiffness is
## K = 1000 Ga b / h (SDPWS 2015 Table 4.3A, 3/8 in OSB 6d at 6 in edge: Ga = 11 kips/in). Roof panels likewise with a diaphragm Ga.
## Units: N, m, kg, s. Member boxes are in mm, y is up, x along the 9.754 m ridge, z across (front wall z = 0, back wall z = 7.62 m).

const E_WOOD := 11.03e9            # 1.6e6 psi (NDS DF-L #2)
const G_WOOD := 0.69e9             # E / 16
const RHO_WOOD := 530.0            # kg/m3, DF-L at 15 percent MC
const LB_IN := 175.1268            # 1 lb/in in N/m
const GA_WALL_KIPS := 11.0         # SDPWS 2015 Table 4.3A, Structural sheathing 3/8 in OSB, 6d common, 6 in edge (the house's nail); 7/16 has no 6d row
const GA_ROOF_KIPS := 7.5          # roof diaphragm: Table 4.2A blocked 6d 3/8 OSB is 15 kips/in; halved for unblocked (Table 4.2C NOT read: UNVERIFIED)
const ASPECT_MAX := 3.5            # SDPWS 4.3.4 h/b limit for full stiffness
const BEAM_KINDS := ["stud", "king", "jack", "cripple", "corner", "nailer", "end", "gable_stud", "bottom_plate", "top_plate1", "top_plate2", "sill", "header", "joist", "ridge", "rafter", "rafter_pair", "gable_rafter"]
const VERT := ["stud", "king", "jack", "cripple", "corner", "nailer", "end"]
const HORIZ := ["bottom_plate", "top_plate1", "top_plate2", "sill", "header", "joist", "ridge"]
const RAFT := ["rafter", "rafter_pair", "gable_rafter"]
const ALLOW := {
	"stud": ["bottom_plate", "top_plate1", "header", "sill"], "king": ["bottom_plate", "top_plate1", "header", "sill"], "jack": ["bottom_plate", "top_plate1", "header", "sill"],
	"cripple": ["bottom_plate", "top_plate1", "header", "sill"], "corner": ["bottom_plate", "top_plate1"], "nailer": ["bottom_plate", "top_plate1"], "end": ["bottom_plate", "top_plate1"],
	"gable_stud": ["top_plate2"], "joist": ["top_plate2", "top_plate1"],
	"bottom_plate": ["bottom_plate"], "top_plate1": ["top_plate1"], "top_plate2": ["top_plate2"],
}
const HOST_PRI := {"jack": 0, "bottom_plate": 1, "top_plate1": 2, "top_plate2": 3, "header": 4, "king": 5, "sill": 6}
const WALL_H := 2.467
const RIDGE_Y := 3.703             # ridge axis (rafter underside line meets it); the real ridge centre is 0.12 m higher
const ZMID := 3.810
const GYP_KGM2 := 10.7             # 1/2 in gypsum, ASCE 7 Table C3.1-1: 2.2 psf


static func _bx(m: Dictionary) -> Array:
	var b: Array = m["box_mm"]
	return [b[0] * 0.001, b[1] * 0.001, b[2] * 0.001, b[3] * 0.001, b[4] * 0.001, b[5] * 0.001]


static func _section(bw: float, dp: float) -> Dictionary:
	# bw: extent along e3, dp: extent along e2 (the depth); Iz = bw dp^3 / 12 (displacement along e2)
	var s := minf(bw, dp)
	var l := maxf(bw, dp)
	var j := l * s * s * s * (1.0 / 3.0 - 0.21 * (s / l) * (1.0 - pow(s, 4) / (12.0 * pow(l, 4))))
	return {"A": bw * dp, "Iz": bw * dp * dp * dp / 12.0, "Iy": dp * bw * bw * bw / 12.0, "J": j}


static func _beam_from_member(m: Dictionary) -> Dictionary:
	var k: String = m["kind"]
	var bb := _bx(m)
	var dx: float = bb[3] - bb[0]
	var dy: float = bb[4] - bb[1]
	var dz: float = bb[5] - bb[2]
	var cx: float = (bb[0] + bb[3]) * 0.5
	var cy: float = (bb[1] + bb[4]) * 0.5
	var cz: float = (bb[2] + bb[5]) * 0.5
	var p0 := Vector3.ZERO
	var p1 := Vector3.ZERO
	var e2 := Vector3.ZERO
	var bw := 0.0
	var dp := 0.0
	if k in VERT:
		p0 = Vector3(cx, bb[1], cz)
		p1 = Vector3(cx, bb[4], cz)
		if dx >= dz:
			e2 = Vector3.RIGHT
			dp = dx
			bw = dz
		else:
			e2 = Vector3.BACK
			dp = dz
			bw = dx
	elif k == "gable_stud":
		var poly: Array = m["poly"]
		var zs := 0.0
		var ytop := 0.0
		for pt in poly:
			zs += pt[0]
		zs = zs / poly.size() * 0.001
		var ys: Array = []
		for pt in poly:
			ys.append(pt[1])
		ys.sort()
		ytop = (ys[ys.size() - 1] + ys[ys.size() - 2]) * 0.5 * 0.001
		p0 = Vector3(cx, bb[1], zs)
		p1 = Vector3(cx, ytop, zs)
		e2 = Vector3.RIGHT
		dp = dx
		bw = (poly[1][0] - poly[0][0]) * 0.001
	elif k in HORIZ:
		if dx >= dy and dx >= dz:
			p0 = Vector3(bb[0], cy, cz)
			p1 = Vector3(bb[3], cy, cz)
			if dy >= dz:
				e2 = Vector3.UP
				dp = dy
				bw = dz
			else:
				e2 = Vector3.BACK
				dp = dz
				bw = dy
		elif dz >= dx and dz >= dy:
			p0 = Vector3(cx, cy, bb[2])
			p1 = Vector3(cx, cy, bb[5])
			if dy >= dx:
				e2 = Vector3.UP
				dp = dy
				bw = dx
			else:
				e2 = Vector3.RIGHT
				dp = dx
				bw = dy
		else:
			p0 = Vector3(cx, bb[1], cz)
			p1 = Vector3(cx, bb[4], cz)
			e2 = Vector3.RIGHT
			dp = dx
			bw = dz
		if k == "ridge":
			p0.y = RIDGE_Y
			p1.y = RIDGE_Y
	else: # rafters: axis along the slope 1/3 through the plate axis point, tail to ridge
		var front: bool = cz < ZMID
		var zb := 0.0445 if front else 7.620 - 0.0445
		var zt := -0.406 if front else 8.026
		var zr := ZMID
		var yb := 2.448
		var s := 1.0 / 3.0
		var ytail: float = yb + (zb - zt) * s * (-1.0 if front else 1.0) * (-1.0)
		# front: z grows toward the ridge, y = yb + (z - zb) s ; back: y = yb + (zb - z) s
		var yy := func(z: float) -> float:
			return yb + ((z - zb) * s if front else (zb - z) * s)
		p0 = Vector3(cx, yy.call(zt), zt)
		p1 = Vector3(cx, RIDGE_Y, zr)
		e2 = Vector3(0, 1, 0)
		# depth: plumb depth * cos(pitch); thickness along x
		dp = 0.235
		bw = dx
		ytail = 0.0
	var sec := _section(bw, dp)
	return {"name": m["name"], "kind": k, "p0": p0, "p1": p1, "e2": e2, "bw": bw, "dp": dp, "sec": sec, "box": bb, "pts": [], "end0": p0, "end1": p1, "has0": false, "has1": false}


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> Array:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var q := a + ab * t
	return [p.distance_to(q), t, q]


static func _param(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	return clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)


## lo/hi gap test between two boxes (m): true if they touch or overlap within tol
static func _touch(a: Array, b: Array, tol: float) -> bool:
	for i in 3:
		if a[i] > b[i + 3] + tol or b[i] > a[i + 3] + tol:
			return false
	return true


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))


## opts: remove_line "" | "F" | "B" | "L" | "R" (planted under-braced house: that line's wall panels carry no shear stiffness)
static func build(mj: Dictionary, opts := {}) -> Dictionary:
	var members: Array = mj["members"]
	var beams: Array = []
	var byname := {}
	for m in members:
		if m["kind"] in BEAM_KINDS:
			var b := _beam_from_member(m)
			byname[b["name"]] = beams.size()
			beams.append(b)
	var nb := beams.size()
	# ---- contacts: each end of a vertical / horizontal beam finds the host it sits on or frames into
	for i in nb:
		var A: Dictionary = beams[i]
		var ak: String = A["kind"]
		if not ALLOW.has(ak):
			continue
		var allowed: Array = ALLOW[ak]
		var p0: Vector3 = A["p0"]
		var p1: Vector3 = A["p1"]
		var ax := (p1 - p0).normalized()
		var kax := 0 if absf(ax.x) > 0.7 else (1 if absf(ax.y) > 0.7 else 2)
		var ab: Array = A["box"]
		for endi in 2:
			var P: Vector3 = p0 if endi == 0 else p1
			var ecoord: float = P[kax]
			var best_j := -1
			var best_d := 1e9
			var best_q := Vector3.ZERO
			var best_pr := 99
			for j in nb:
				if j == i:
					continue
				var H: Dictionary = beams[j]
				if not (H["kind"] in allowed):
					continue
				var hb: Array = H["box"]
				if not _touch(ab, hb, 0.002):
					continue
				var o_lo := maxf(ab[kax], hb[kax])
				var o_hi := minf(ab[kax + 3], hb[kax + 3])
				if o_hi < o_lo - 0.002:
					continue
				if o_hi - o_lo > maxf(1.2 * A["dp"], 0.15):
					continue
				var dd := 0.0
				if ecoord < o_lo:
					dd = o_lo - ecoord
				elif ecoord > o_hi:
					dd = ecoord - o_hi
				if dd > 0.002:
					continue
				var sd := _seg_dist(P, H["p0"], H["p1"])
				var pr: int = HOST_PRI.get(H["kind"], 9)
				if sd[0] < best_d - 0.0005 or (absf(sd[0] - best_d) <= 0.0005 and pr < best_pr):
					best_d = sd[0]
					best_j = j
					best_q = sd[2]
					best_pr = pr
			if best_j >= 0:
				var Hh: Dictionary = beams[best_j]
				Hh["pts"].append(best_q)
				A["end0" if endi == 0 else "end1"] = best_q
				A["has0" if endi == 0 else "has1"] = true
	# gable studs: top frames into the nearest rafter axis
	for i in nb:
		var A: Dictionary = beams[i]
		if A["kind"] != "gable_stud":
			continue
		var P: Vector3 = A["p1"]
		var bj := -1
		var bd := 0.06
		var bq := Vector3.ZERO
		for j in nb:
			if beams[j]["kind"] in RAFT:
				var sd := _seg_dist(P, beams[j]["p0"], beams[j]["p1"])
				if sd[0] < bd:
					bd = sd[0]
					bj = j
					bq = sd[2]
		if bj >= 0:
			beams[bj]["pts"].append(bq)
			A["end1"] = bq
			A["has1"] = true
	# rafters: bearing on the top_plate2 and the ridge
	var rafter_free := 0
	for i in nb:
		var A: Dictionary = beams[i]
		if not (A["kind"] in RAFT):
			continue
		var cx: float = (A["p0"].x + A["p1"].x) * 0.5
		var front: bool = A["p0"].z < ZMID
		var zb := 0.0445 if front else 7.620 - 0.0445
		var yb := 2.448
		var Pb := Vector3(cx, yb, zb)
		var bj := -1
		var bd := 0.03
		var bq := Vector3.ZERO
		for j in nb:
			if beams[j]["kind"] == "top_plate2":
				var sd := _seg_dist(Pb, beams[j]["p0"], beams[j]["p1"])
				if sd[0] < bd:
					bd = sd[0]
					bj = j
					bq = sd[2]
		if bj >= 0:
			beams[bj]["pts"].append(bq)
			A["pts"].append(Pb)
		else:
			rafter_free += 1
		# ridge
		var Pr := Vector3(cx, RIDGE_Y, ZMID)
		for j in nb:
			if beams[j]["kind"] == "ridge":
				var sd2 := _seg_dist(Pr, beams[j]["p0"], beams[j]["p1"])
				beams[j]["pts"].append(sd2[2])
				A["end1"] = sd2[2]
				A["has1"] = true
	# ---- top_plate2 is tied to top_plate1 below it by stiff links at every top_plate1 node (nailed double plate)
	var links: Array = [] # [Vector3 a, Vector3 b]
	var t1s: Array = []
	var t2s: Array = []
	for i in nb:
		if beams[i]["kind"] == "top_plate1":
			t1s.append(i)
		elif beams[i]["kind"] == "top_plate2":
			t2s.append(i)
	for i1 in t1s:
		var T1: Dictionary = beams[i1]
		var pts1: Array = [T1["end0"], T1["end1"]]
		pts1.append_array(T1["pts"])
		# studs that sit under this plate add their nodes through their own end hosts (already in T1.pts)
		for q in pts1:
			for i2 in t2s:
				var T2: Dictionary = beams[i2]
				var qq: Vector3 = q + Vector3(0, 0.038, 0)
				var sd := _seg_dist(qq, T2["p0"], T2["p1"])
				if sd[0] < 0.012:
					var t: float = sd[1]
					if t > 0.0 and t < 1.0 or true:
						T2["pts"].append(sd[2])
						links.append([q, sd[2]])
						break
	# ---- panels
	var h := WALL_H
	var gt_wall: float = 1000.0 * GA_WALL_KIPS * LB_IN
	var gt_roof: float = 1000.0 * GA_ROOF_KIPS * LB_IN
	var panels: Array = []     # {line, x0, x1, b, kh, diag:[[Pa,Pb],[Pc,Pd]]}
	var roofs: Array = []
	var by_line := {}
	for m in members:
		if m["kind"] == "wall_sheathing":
			var bb := _bx(m)
			if bb[1] < 0.05 and bb[4] > h - 0.05:
				var ln: String = str(m["name"]).split(".")[1]
				if not by_line.has(ln):
					by_line[ln] = []
				var along := 0 if (ln == "F" or ln == "B") else 2
				by_line[ln].append({"name": m["name"], "lo": bb[along], "hi": bb[along + 3], "box": bb})
	var segments: Array = []
	for ln in by_line:
		var arr: Array = by_line[ln]
		arr.sort_custom(func(a, b): return a["lo"] < b["lo"])
		var cur: Array = []
		for p in arr:
			if cur.is_empty() or p["lo"] - cur[cur.size() - 1]["hi"] <= 0.015:
				cur.append(p)
			else:
				segments.append({"line": ln, "panels": cur})
				cur = [p]
		if not cur.is_empty():
			segments.append({"line": ln, "panels": cur})
	var removed: Array = opts.get("remove_lines", [])
	if opts.has("remove_line"):
		removed = [opts["remove_line"]]
	var eff_len := {}
	for sg in segments:
		var lo: float = sg["panels"][0]["lo"]
		var hi: float = sg["panels"][sg["panels"].size() - 1]["hi"]
		sg["width"] = hi - lo
		sg["ok"] = (h / (hi - lo)) <= ASPECT_MAX
		if sg["ok"]:
			eff_len[sg["line"]] = eff_len.get(sg["line"], 0.0) + (hi - lo)
	var _unused := 0
	for sg in segments:
		if not sg["ok"]:
			continue
		var ln: String = sg["line"]
		var fb := ln == "F" or ln == "B"
		for p in sg["panels"]:
			var bb: Array = p["box"]
			var zc: float = 0.0445 if (ln == "F") else (7.620 - 0.0445 if ln == "B" else 0.0)
			var xc: float = 0.0445 if ln == "L" else (9.754 - 0.0445 if ln == "R" else 0.0)
			var pts_b: Array = []
			for side in 2:
				var a: float = p["lo"] if side == 0 else p["hi"]
				var pb: Vector3 = Vector3(a, 0.019, zc) if fb else Vector3(xc, 0.019, a)
				var pt: Vector3 = Vector3(a, 2.448, zc) if fb else Vector3(xc, 2.448, a)
				pts_b.append([pb, pt])
			# snap to plate axes (requests)
			var sn: Array = []
			var okp := true
			for side in 2:
				var qb = _request(beams, pts_b[side][0], ["bottom_plate"], 0.15)
				var qt = _request(beams, pts_b[side][1], ["top_plate2"], 0.15)
				if qb == null or qt == null:
					okp = false
				sn.append([qb, qt])
			if not okp:
				continue
			var bpan: float = p["hi"] - p["lo"]
			var kh: float = gt_wall * bpan / h
			p["rec"] = {"line": ln, "lo": p["lo"], "hi": p["hi"], "b": bpan, "kh": kh, "seg_w": sg["width"], "diag": [[sn[0][0], sn[1][1]], [sn[1][0], sn[0][1]]], "active": not (ln in removed)}
			panels.append(p["rec"])
	for m in members:
		if m["kind"] != "roof_sheathing":
			continue
		var poly: Array = m["poly"]
		var bb := _bx(m)
		var pA := Vector3(bb[0], poly[0][1] * 0.001, poly[0][0] * 0.001)
		var pB := Vector3(bb[0], poly[1][1] * 0.001, poly[1][0] * 0.001)
		var pC := Vector3(bb[3], poly[1][1] * 0.001, poly[1][0] * 0.001)
		var pD := Vector3(bb[3], poly[0][1] * 0.001, poly[0][0] * 0.001)
		# panel plane corners (sheet outer face), pulled to the rafter axis line: lower the corners by the rafter depth + sheet (0.13 m)
		var corners: Array = [pA, pB, pC, pD]
		var sn2: Array = []
		var okr := true
		for c in corners:
			var cc: Vector3 = c + Vector3(0, -0.15, 0)
			var q = _request(beams, cc, RAFT, 0.35)
			if q == null:
				okr = false
			sn2.append(q)
		if not okr:
			continue
		var len_slope := pA.distance_to(pB)
		var wid := absf(bb[3] - bb[0])
		roofs.append({"name": m["name"], "b": wid, "h": len_slope, "k": gt_roof, "diag": [[sn2[0], sn2[2]], [sn2[1], sn2[3]]]})
	# ---- nodes and elements
	var nodes: Array = []
	var nkey := {}
	var node_of := func(p: Vector3) -> int:
		var k := _key(p)
		if nkey.has(k):
			return nkey[k]
		nkey[k] = nodes.size()
		nodes.append(p)
		return nkey[k]
	var elems: Array = [] # {n1, n2, beam, link}
	for i in nb:
		var B: Dictionary = beams[i]
		var p0: Vector3 = B["p0"]
		var p1: Vector3 = B["p1"]
		var L := p0.distance_to(p1)
		var ts: Array = [[0.0, B["end0"]], [1.0, B["end1"]]]
		for q in B["pts"]:
			ts.append([_param(q, p0, p1), q])
		ts.sort_custom(func(a, b): return a[0] < b[0])
		# merge points closer than 4 mm along the axis (keep the first; an end replaced by a host point wins over the raw end)
		var uniq: Array = []
		for t in ts:
			if uniq.is_empty() or (t[0] - uniq[uniq.size() - 1][0]) * L > 0.004:
				uniq.append(t)
			elif t[0] == 1.0 and uniq.size() > 1 and B["has1"]:
				uniq[uniq.size() - 1] = t
		for a in range(uniq.size() - 1):
			var na: int = node_of.call(uniq[a][1])
			var nbn: int = node_of.call(uniq[a + 1][1])
			if na != nbn:
				elems.append({"n1": na, "n2": nbn, "beam": i, "link": false})
	for lk in links:
		var na: int = node_of.call(lk[0])
		var nbn: int = node_of.call(lk[1])
		if na != nbn:
			elems.append({"n1": na, "n2": nbn, "beam": -1, "link": true})
	# ---- springs
	var springs: Array = []
	var panel_rec: Array = []
	for p in panels:
		var rec: Dictionary = p
		var d: Array = rec["diag"]
		var sp_idx: Array = []
		for dg in d:
			var a: int = node_of.call(dg[0])
			var b: int = node_of.call(dg[1])
			var dv: Vector3 = nodes[b] - nodes[a]
			var dxh := absf(dv.x) if (rec["line"] == "F" or rec["line"] == "B") else absf(dv.z)
			var dl := dv.length()
			if dxh < 0.05 or a == b:
				continue
			# each diagonal carries half of K_h: k_d (dx / d)^2 = K_h / 2
			var kd: float = 0.5 * rec["kh"] * (dl * dl) / (dxh * dxh)
			sp_idx.append(springs.size())
			springs.append([a, b, kd, rec["line"], rec["active"]])
		rec["spr"] = sp_idx
		panel_rec.append(rec)
	var roof_sp: Array = []
	for r in roofs:
		for dg in r["diag"]:
			var a: int = node_of.call(dg[0])
			var b: int = node_of.call(dg[1])
			if a == b:
				continue
			var dv: Vector3 = nodes[b] - nodes[a]
			var dl := dv.length()
			# crossed diagonals: k_d = Gt d^2 / (2 b h) for a panel of sides b x h
			var kd: float = r["k"] * dl * dl / (2.0 * r["b"] * r["h"])
			roof_sp.append(springs.size())
			springs.append([a, b, kd, "roof", true])
	return {"nodes": nodes, "elems": elems, "beams": beams, "springs": springs, "panels": panel_rec, "segments": segments, "roofs": roofs, "links": links,
			"eff_len": eff_len, "rafter_free": rafter_free, "members": members, "removed": removed}


## closest point on the axis of a beam of the given kinds within tol, registered as a split point there; null if none
static func _request(beams: Array, p: Vector3, kinds: Array, tol: float):
	var bj := -1
	var bd := tol
	var bq := Vector3.ZERO
	for j in beams.size():
		var B: Dictionary = beams[j]
		if not (B["kind"] in kinds):
			continue
		var sd := _seg_dist(p, B["p0"], B["p1"])
		if sd[0] < bd:
			bd = sd[0]
			bj = j
			bq = sd[2]
	if bj < 0:
		return null
	beams[bj]["pts"].append(bq)
	return bq


## the frame-solver model from build(): connectivity check, drop floating pieces, masses, supports.
static func to_model(bld: Dictionary) -> Dictionary:
	var nodes: Array = bld["nodes"]
	var n := nodes.size()
	var beams: Array = bld["beams"]
	var elems: Array = bld["elems"]
	var springs: Array = bld["springs"]
	# union-find over elements and springs
	var par := PackedInt32Array()
	par.resize(n)
	for i in n:
		par[i] = i
	var find := func(x: int) -> int:
		while par[x] != x:
			par[x] = par[par[x]]
			x = par[x]
		return x
	for e in elems:
		par[find.call(e["n1"])] = find.call(e["n2"])
	var fixed := PackedInt32Array()
	var base_nodes := PackedInt32Array()
	for i in n:
		var p: Vector3 = nodes[i]
		if p.y < 0.03:
			base_nodes.append(i)
	var root: int = find.call(base_nodes[0]) if base_nodes.size() > 0 else 0
	# the main component is the one with the most base nodes
	var cnt := {}
	for b in base_nodes:
		var r: int = find.call(b)
		cnt[r] = cnt.get(r, 0) + 1
	var bestc := -1
	for r in cnt:
		if bestc < 0 or cnt[r] > cnt[bestc]:
			bestc = r
	root = bestc
	var keep := PackedInt32Array()
	keep.resize(n)
	var kept := 0
	for i in n:
		if find.call(i) == root:
			keep[i] = 1
			kept += 1
	for b in base_nodes:
		if keep[b] == 1:
			for d in 3:
				fixed.append(b * 6 + d)
	for i in n:    # nodes outside the main component carry no element: pin all six dofs so they do not make K singular
		if keep[i] == 0:
			for d in 6:
				fixed.append(i * 6 + d)
	var xyz := PackedFloat64Array()
	xyz.resize(n * 3)
	for i in n:
		xyz[i * 3] = nodes[i].x
		xyz[i * 3 + 1] = nodes[i].y
		xyz[i * 3 + 2] = nodes[i].z
	var bm := PackedFloat64Array()
	var dropped := 0
	for e in elems:
		if keep[e["n1"]] == 0:
			dropped += 1
			continue
		if e["link"]:
			bm.append_array([e["n1"], e["n2"], 0.02, 2e-5, 2e-5, 4e-5, E_WOOD * 10.0, G_WOOD * 10.0, 0.0, 0, 0, 1])
			# a link between two plates one above the other is along y: e2 = x
			var ln := bm.size()
			var d: Vector3 = nodes[e["n2"]] - nodes[e["n1"]]
			if absf(d.normalized().x) > 0.7:
				bm[ln - 3] = 0
				bm[ln - 2] = 1
				bm[ln - 1] = 0
			continue
		var B: Dictionary = beams[e["beam"]]
		var s: Dictionary = B["sec"]
		var e2: Vector3 = B["e2"]
		var ax: Vector3 = (nodes[e["n2"]] - nodes[e["n1"]]).normalized()
		if absf(ax.dot(e2)) > 0.999:    # a short piece cut along its section's reference axis: any perpendicular will do
			e2 = Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
		bm.append_array([e["n1"], e["n2"], s["A"], s["Iz"], s["Iy"], s["J"], E_WOOD, G_WOOD, RHO_WOOD, e2.x, e2.y, e2.z])
	var sp := PackedFloat64Array()
	for s in springs:
		if keep[s[0]] == 0 or not s[4]:
			continue
		sp.append_array([s[0], s[1], s[2]])
	return {"model": {"xyz": xyz, "beams": bm, "springs": sp, "fixed": fixed, "mass": PackedFloat64Array()}, "keep": keep, "kept": kept, "n": n, "dropped_elems": dropped}


## lumped masses (kg) per node from the non-structural pieces and finishes: returns {mass: PackedFloat64Array, total_kg, parts}
static func masses(bld: Dictionary) -> Dictionary:
	var nodes: Array = bld["nodes"]
	var n := nodes.size()
	var mass := PackedFloat64Array()
	mass.resize(n)
	var top: Array = []   # node indices at the wall top (t1/t2 level)
	var roofn: Array = [] # nodes above the plate
	var ceil_n: Array = []
	for i in n:
		var p: Vector3 = nodes[i]
		if p.y > 2.38 and p.y < 2.47:
			top.append(i)
		if p.y > 2.5:
			roofn.append(i)
		if p.y > 2.38:
			ceil_n.append(i)
	var parts := {}
	var add := func(p: Vector3, m: float, pool: Array, tag: String) -> void:
		parts[tag] = parts.get(tag, 0.0) + m
		var cand: Array = []
		for i in pool:
			cand.append([p.distance_squared_to(nodes[i]), i])
		cand.sort_custom(func(a, b): return a[0] < b[0])
		var k := mini(3, cand.size())
		var wsum := 0.0
		for q in k:
			wsum += 1.0 / (cand[q][0] + 1e-4)
		for q in k:
			mass[cand[q][1]] += m * (1.0 / (cand[q][0] + 1e-4)) / wsum
	for m in bld["members"]:
		var kd: String = m["kind"]
		var bb := _bx(m)
		var c := Vector3((bb[0] + bb[3]) * 0.5, (bb[1] + bb[4]) * 0.5, (bb[2] + bb[5]) * 0.5)
		var dx: float = bb[3] - bb[0]
		var dy: float = bb[4] - bb[1]
		var dz: float = bb[5] - bb[2]
		if kd == "wall_sheathing":
			var area := maxf(dx * dy, maxf(dy * dz, dx * dz))
			add.call(c, 0.5 * area * 7.1, top, "wall sheathing (upper half)")
		elif kd == "siding":
			var area := maxf(dx * dy, maxf(dy * dz, dx * dz))
			add.call(c, 0.5 * area * 9.5, top, "siding (upper half)")
		elif kd == "window" or kd == "door":
			var area := maxf(dx * dy, maxf(dy * dz, dx * dz))
			add.call(c, 0.5 * area * 30.0, top, "windows and doors (upper half)")
		elif kd == "roof_sheathing":
			var poly: Array = m["poly"]
			var sl := Vector2(poly[0][0], poly[0][1]).distance_to(Vector2(poly[1][0], poly[1][1])) * 0.001
			add.call(c, dx * sl * 7.1, roofn, "roof sheathing")
		elif kd == "shingle":
			var poly: Array = m["poly"]
			var sl := Vector2(poly[0][0], poly[0][1]).distance_to(Vector2(poly[1][0], poly[1][1])) * 0.001
			# asphalt shingles 2 psf (ASCE 7 Table C3.1-1) = 9.8 kg/m2, one piece per slope, spread along the slope
			var mm: float = dx * sl * 9.8
			for q in 8:
				var cc := c + Vector3(-dx * 0.5 + dx * (q + 0.5) / 8.0, 0, 0) - Vector3(c.x, 0, 0) + Vector3(c.x, 0, 0)
				add.call(Vector3(dx * (q + 0.5) / 8.0, c.y, c.z), mm / 8.0, roofn, "shingles")
		elif kd == "gable_sheathing":
			var poly: Array = m["poly"]
			var a2 := 0.0
			for i in poly.size():
				var p := Vector2(poly[i][0], poly[i][1])
				var q := Vector2(poly[(i + 1) % poly.size()][0], poly[(i + 1) % poly.size()][1])
				a2 += p.x * q.y - q.x * p.y
			add.call(c, absf(a2) * 0.5e-6 * 7.1, roofn, "gable sheathing")
		elif kd == "joist":
			# ceiling gypsum 1/2 in over the joist's tributary strip (16 in)
			var L := maxf(dx, maxf(dy, dz))
			add.call(c, L * 0.4064 * GYP_KGM2, ceil_n, "ceiling gypsum")
	# interior gypsum: exterior walls one face, partitions two, over the wall height, upper half at the plate level
	for m in bld["members"]:
		if m["kind"] == "top_plate1":
			var bb := _bx(m)
			var L := maxf(bb[3] - bb[0], bb[5] - bb[2])
			var ln: String = str(m["name"]).split(".")[1]
			var faces := 1.0 if (ln == "F" or ln == "B" or ln == "L" or ln == "R") else 2.0
			var c := Vector3((bb[0] + bb[3]) * 0.5, 2.41, (bb[2] + bb[5]) * 0.5)
			add.call(c, 0.5 * L * WALL_H * GYP_KGM2 * faces, top, "wall gypsum (upper half)")
	var tot := 0.0
	for v in mass:
		tot += v
	return {"mass": mass, "total_kg": tot, "parts": parts}
