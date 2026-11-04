class_name Ch1eFast
extends RefCounted
## CH1e: the CH1 house with REAL fasteners. Nails, sheathing nails, anchor bolts + plate washers, H2.5A hurricane ties and HDU2 hold-downs become geometry (a head point, a
## direction, a length, the two members it joins), placed from the member list per IRC 2021 Table R602.3(1) (HouseCheck.FASTENERS) and R403.1.6. Every joint's capacity is then
## computed FROM the fasteners placed in it (count x per-fastener value x the adjustment factors); every per-fastener value and its source is in docs/CH1e_REFERENCE.md.
##   build(mj, opts)        out/ch1/members.json (parsed) -> F: solids, nails (structure of arrays), connections, hardware parts, findings
##   validate(F)            per nail: head gap to its first member, mm inside the first and the second member, uncovered holes, tip tail   (C++ KineFastenerNative or the GDScript twin)
##   capacity(F, ci, V)     one connection's T (tension / withdrawal / uplift) and V (shear) in lb at CD 1.0 (T10, V10) and CD 1.6 (T16, V16)
##   schedule_failures(F)   the connections that break the IRC row they were placed for
## Units: mm, Y up, x along the 9.754 m ridge, z across (front wall z = 0). Nothing here changes the house.

const IN := 25.4
const HW := 2467.0
const FRK := ["bottom_plate", "top_plate1", "top_plate2", "stud", "king", "jack", "cripple", "corner", "end", "nailer", "gable_stud", "header", "sill", "joist", "rafter", "rafter_pair", "rafter_layout", "gable_rafter", "ridge"]
const VERT := ["stud", "king", "jack", "cripple", "corner", "end", "nailer"]
const SHEATHK := ["wall_sheathing", "gable_sheathing", "roof_sheathing"]
const CONCK := ["slab", "footing"]
const OSB := 11.1
const STEP := 0.5
const TOL := 0.3
## nail dimensions (inches). Shank diameter x length: AWC Design Aid DA-2 (NDS) tables. Head diameter: ASTM F1667 from memory, drawn only, used by no capacity.
const TYPES := {
	"6d_com": {"D": 0.113, "L": 2.0, "HD": 0.266}, "8d_box": {"D": 0.113, "L": 2.5, "HD": 0.266}, "8d_com": {"D": 0.131, "L": 2.5, "HD": 0.281},
	"10d_box": {"D": 0.128, "L": 3.0, "HD": 0.297}, "16d_box": {"D": 0.135, "L": 3.5, "HD": 0.302}, "16d_com": {"D": 0.162, "L": 3.5, "HD": 0.344},
	"h25_nail": {"D": 0.131, "L": 1.5, "HD": 0.281}, "sds": {"D": 0.25, "L": 2.5, "HD": 0.40},
	"anchor_bolt": {"D": 0.5, "L": 216.0 / 25.4, "HD": 0.75}, "hd_rod": {"D": 0.625, "L": 309.5 / 25.4, "HD": 1.0},
}
## per-nail values, lb, CD 1.0 reference, [W withdrawal, Z lateral]. TOE: AWC DA-2 tables, Ctn already applied (0.67 / 0.83), by specific gravity.
const TOE_VAL := {0.50: {"8d_box": [28.0, 60.0], "16d_box": [48.0, 86.0]}, 0.42: {"8d_box": [18.0, 50.0], "16d_box": [31.0, 73.0]}}
## face nails: lateral = DA-2 toenail Z / 0.83 (the DA-2 tables carry Ctn = 0.83), by specific gravity
const FACE_Z := {0.50: {"16d_com": 117.0, "10d_box": 77.0, "8d_com": 80.0, "6d_com": 57.0}, 0.42: {"16d_com": 99.0, "10d_box": 65.0, "8d_com": 62.0, "6d_com": 44.0}}
const CTN_Z := 0.83
const SHEATH_V_160 := 100.0       # SDPWS 3/8 in OSB 6d common 6 in edge: ASD 200 plf / 2 nails per ft (docs/CH10_REFERENCE.md section 2), on the wind / seismic basis (CD 1.6)
const CD_WIND := 1.6
const H25A := {"DF": [625.0, 110.0], "SPF": [540.0, 110.0]}   # Simpson C-C-2021 p.277, 0.131x1.5 nails, uplift (160) and F1/F2 (160)
const HDU2 := {"DF": 3075.0, "SPF": 2215.0}                    # Simpson C-C-2021 p.52, HDU2-SDS2.5 (160)
const BOLT_V_160 := 1040.0        # 1/2 in anchor bolt shear parallel to grain, 2x sill, CD 1.6 (Clark County NV BD-CI-038 as quoted by a search summary: SECONDARY, see the reference)
const STRAP_T := 1.214            # 18 ga
const HDU_T := 1.9                # 14 ga
const SHEATH_EDGE_IN := 9.5
const SHEATH_EDGE_MM := 152.4
const SHEATH_FIELD_MM := 304.8
const FACE_PEN_FACTOR := 1380.0   # NDS withdrawal W = 1380 G^2.5 D lb per inch of penetration (as quoted in docs/CH11_REFERENCE.md; not opened here: flagged in the reference)

static var _nat: int = -1


static func native_ok() -> bool:
	if _nat < 0:
		_nat = 1 if NativeExt.ensure("kine_native", "KineFastenerNative") and OS.get_environment("KINE_NO_NATIVE") != "1" else 0
	return _nat == 1


static func _N():
	return load("res://scripts/build/ch1e_fast_native.gd")


static func wall_of(name: String) -> String:
	var p := name.split(".")
	return p[1] if p.size() > 1 else ""


# ================================================================== solids and geometry
static func make_solids(mj: Dictionary) -> Array:
	var out: Array = []
	for m in mj["members"]:
		var p = m["poly"]
		out.append({"name": m["name"], "kind": m["kind"], "b": (m["box_mm"] as Array).duplicate(), "poly": p if p != null else []})
	return out


static func _arrays(S: Array) -> Dictionary:
	var boxes := PackedFloat64Array()
	var off := PackedInt32Array([0])
	var pts := PackedFloat64Array()
	for s in S:
		for v in s["b"]:
			boxes.append(float(v))
		for q in s["poly"]:
			pts.append(float(q[0]))
			pts.append(float(q[1]))
		off.append(pts.size() / 2)
	return {"boxes": boxes, "off": off, "pts": pts}


static func _mask(S: Array, kinds: Array, no_poly := false) -> PackedInt32Array:
	var m := PackedInt32Array()
	for s in S:
		m.append(1 if (s["kind"] in kinds and not (no_poly and not s["poly"].is_empty())) else 0)
	return m


static func _pip(poly: Array, z: float, y: float) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for k in n:
		var zk: float = poly[k][0]
		var yk: float = poly[k][1]
		var zj: float = poly[j][0]
		var yj: float = poly[j][1]
		if ((yk > y) != (yj > y)) and (z < (zj - zk) * (y - yk) / (yj - yk) + zk):
			inside = not inside
		j = k
	return inside


static func _seg_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var l2 := dx * dx + dy * dy
	var t := ((px - ax) * dx + (py - ay) * dy) / l2 if l2 > 0.0 else 0.0
	t = maxf(0.0, minf(1.0, t))
	var cx := ax + t * dx - px
	var cy := ay + t * dy - py
	return sqrt(cx * cx + cy * cy)


static func _poly_edge_dist(poly: Array, z: float, y: float) -> float:
	var d := 1e30
	var n := poly.size()
	var j := n - 1
	for k in n:
		d = minf(d, _seg_dist(z, y, poly[j][0], poly[j][1], poly[k][0], poly[k][1]))
		j = k
	return d


static func inside(s: Dictionary, x: float, y: float, z: float, tol: float) -> bool:
	var b: Array = s["b"]
	if x < b[0] - tol or x > b[3] + tol or y < b[1] - tol or y > b[4] + tol or z < b[2] - tol or z > b[5] + tol:
		return false
	if s["poly"].is_empty():
		return true
	if _pip(s["poly"], z, y):
		return true
	return _poly_edge_dist(s["poly"], z, y) <= tol


static func surf_dist(s: Dictionary, x: float, y: float, z: float) -> float:
	var b: Array = s["b"]
	var dx := maxf(maxf(b[0] - x, x - b[3]), 0.0)
	if s["poly"].is_empty():
		var dy := maxf(maxf(b[1] - y, y - b[4]), 0.0)
		var dz := maxf(maxf(b[2] - z, z - b[5]), 0.0)
		if dx > 0.0 or dy > 0.0 or dz > 0.0:
			return sqrt(dx * dx + dy * dy + dz * dz)
		return minf(minf(minf(x - b[0], b[3] - x), minf(y - b[1], b[4] - y)), minf(z - b[2], b[5] - z))
	var inp := _pip(s["poly"], z, y)
	var ed := _poly_edge_dist(s["poly"], z, y)
	if dx > 0.0 or not inp:
		var d2 := 0.0 if inp else ed
		return sqrt(dx * dx + d2 * d2)
	return minf(minf(x - b[0], b[3] - x), ed)


# ------------------------------------------------------------------ contacts / probes / validation: native or twin
static func contacts(S: Array, native := true) -> Array:
	var A := _arrays(S)
	var mask := _mask(S, FRK, true)
	var raw: PackedInt32Array
	if native and native_ok():
		raw = _N().contacts(A["boxes"], mask, 0.5, 1.0)
	else:
		raw = PackedInt32Array()
		var n := S.size()
		for i in n:
			if mask[i] == 0:
				continue
			var bi: Array = S[i]["b"]
			for j in range(i + 1, n):
				if mask[j] == 0:
					continue
				var bj: Array = S[j]["b"]
				for ax in 3:
					var o1 := (ax + 1) % 3
					var o2 := (ax + 2) % 3
					var ov1: float = minf(bi[o1 + 3], bj[o1 + 3]) - maxf(bi[o1], bj[o1])
					var ov2: float = minf(bi[o2 + 3], bj[o2 + 3]) - maxf(bi[o2], bj[o2])
					if ov1 <= 1.0 or ov2 <= 1.0:
						continue
					if absf(bi[ax + 3] - bj[ax]) <= 0.5:
						raw.append_array(PackedInt32Array([i, j, ax, 1]))
					if absf(bj[ax + 3] - bi[ax]) <= 0.5:
						raw.append_array(PackedInt32Array([i, j, ax, -1]))
	var out: Array = []
	for k in range(0, raw.size(), 4):
		out.append([raw[k], raw[k + 1], raw[k + 2], raw[k + 3]])
	return out


static func first_hits(S: Array, pts: PackedVector3Array, native := true, kinds := FRK) -> PackedInt32Array:
	var mask := _mask(S, kinds)
	return _fh(S, _arrays(S), mask, pts, native)


static func _fh(S: Array, A: Dictionary, mask: PackedInt32Array, pts: PackedVector3Array, native := true) -> PackedInt32Array:
	var q := PackedFloat64Array()
	for p in pts:
		q.append(p.x)
		q.append(p.y)
		q.append(p.z)
	if native and native_ok():
		return _N().first_hits(A["boxes"], A["off"], A["pts"], mask, q, 0.25)
	var out := PackedInt32Array()
	for k in pts.size():
		var hit := -1
		for i in S.size():
			if mask[i] == 1 and inside(S[i], q[3 * k], q[3 * k + 1], q[3 * k + 2], 0.25):
				hit = i
				break
		out.append(hit)
	return out


static func validate(F: Dictionary, native := true, only := []) -> Dictionary:
	var S: Array = F["solids"]
	var A: Dictionary = F["arr"]
	var ids: Array = only if not only.is_empty() else range(F["n"])
	var heads := PackedFloat64Array()
	var dirs := PackedFloat64Array()
	var lens := PackedFloat64Array()
	var aa := PackedInt32Array()
	var bb := PackedInt32Array()
	for i in ids:
		var h: Vector3 = F["head"][i]
		var d: Vector3 = F["dir"][i]
		var sd: float = F["stand"][i]
		h += d * sd     # CH1e: the head stands off the wood by the strap / washer / nut thickness; the shank is only checked from the wood face on (head_gap gets the stand added back below)
		heads.append_array(PackedFloat64Array([h.x, h.y, h.z]))
		dirs.append_array(PackedFloat64Array([d.x, d.y, d.z]))
		lens.append(F["len"][i] - sd)
		aa.append(F["a"][i])
		bb.append(F["b"][i])
	var raw: PackedFloat64Array
	if native and native_ok():
		raw = _N().validate(A["boxes"], A["off"], A["pts"], F["m_cover"], heads, dirs, lens, aa, bb)
	else:
		raw = _validate_gd(S, F["m_cover"], heads, dirs, lens, aa, bb)
	var n: int = F["n"]
	var keys := ["head_gap", "len_a", "len_b", "tail", "holes"]
	var cols := []
	for c in 5:
		var arr := PackedFloat64Array()
		arr.resize(n)
		for q in ids.size():
			arr[ids[q]] = raw[5 * q + c]
		cols.append(arr)
	for q in ids.size():
		cols[0][ids[q]] += F["stand"][ids[q]]
	var out := {}
	for c in 5:
		out[keys[c]] = cols[c]
	return out


static func _validate_gd(S: Array, cover: PackedInt32Array, heads: PackedFloat64Array, dirs: PackedFloat64Array, lens: PackedFloat64Array, aa: PackedInt32Array, bb: PackedInt32Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var nn := lens.size()
	for k in nn:
		var hx := heads[3 * k]
		var hy := heads[3 * k + 1]
		var hz := heads[3 * k + 2]
		var dx := dirs[3 * k]
		var dy := dirs[3 * k + 1]
		var dz := dirs[3 * k + 2]
		var L := lens[k]
		var a := aa[k]
		var b := bb[k]
		var lo := [minf(hx, hx + dx * L) - TOL, minf(hy, hy + dy * L) - TOL, minf(hz, hz + dz * L) - TOL]
		var hi := [maxf(hx, hx + dx * L) + TOL, maxf(hy, hy + dy * L) + TOL, maxf(hz, hz + dz * L) + TOL]
		var cand: Array = []
		for i in S.size():
			if cover[i] == 0 and i != a and i != b:
				continue
			var bx: Array = S[i]["b"]
			if bx[0] > hi[0] or bx[3] < lo[0] or bx[1] > hi[1] or bx[4] < lo[1] or bx[2] > hi[2] or bx[5] < lo[2]:
				continue
			cand.append(i)
		var ns := int(floor(L / STEP + 1e-9))
		var covered := PackedByteArray()
		covered.resize(ns + 1)
		var n_a := 0
		var n_b := 0
		var last := -1
		for s in ns + 1:
			var t := s * STEP
			var x := hx + dx * t
			var y := hy + dy * t
			var z := hz + dz * t
			var ina: bool = a >= 0 and inside(S[a], x, y, z, TOL)
			var inb: bool = b >= 0 and inside(S[b], x, y, z, TOL)
			var anyc: bool = ina or inb
			if not anyc:
				for c in cand:
					if cover[c] == 1 and inside(S[c], x, y, z, TOL):
						anyc = true
						break
			if ina:
				n_a += 1
			if inb:
				n_b += 1
			if anyc:
				last = s
				covered[s] = 1
		var holes := 0
		for s in range(0, last + 1):
			if covered[s] == 0:
				holes += 1
		var len_a := n_a * STEP
		var len_b := n_b * STEP
		if a == b:
			len_b = maxf(0.0, len_a - 51.0)
		var tail := L if last < 0 else maxf(0.0, L - last * STEP)
		var gap := surf_dist(S[a], hx, hy, hz) if a >= 0 else 0.0
		out.append_array(PackedFloat64Array([gap, len_a, len_b, tail, holes * STEP]))
	return out


# ================================================================== state
static func _new_state(mj: Dictionary) -> Dictionary:
	var S := make_solids(mj)
	var F := {"solids": S, "n": 0, "tname": PackedStringArray(), "head": PackedVector3Array(), "dir": PackedVector3Array(), "len": PackedFloat64Array(), "a": PackedInt32Array(), "b": PackedInt32Array(),
		"stand": PackedFloat64Array(), "cn": PackedInt32Array(), "role": PackedInt32Array(), "need_b": PackedInt32Array(), "penb": PackedFloat64Array(),
		"conns": [], "parts": [], "findings": [], "miss_list": [], "names": [], "idx": {}, "meta": mj.get("meta", {})}
	for i in S.size():
		F["names"].append(S[i]["name"])
		F["idx"][S[i]["name"]] = i
	F["arr"] = _arrays(S)
	F["m_fr"] = _mask(S, FRK)
	F["m_cover"] = _mask(S, FRK + SHEATHK + CONCK)
	F["m_conc"] = _mask(S, CONCK)
	return F


static func _nail(F: Dictionary, tname: String, head: Vector3, dir: Vector3, a: int, b: int, cn: int, stand := 0.0, role := 2, need_b := 1, penb := -1.0, length_mm := -1.0) -> int:
	var L: float = length_mm if length_mm > 0.0 else float(TYPES[tname]["L"]) * IN
	var id: int = F["n"]
	F["tname"].append(tname)
	F["head"].append(head)
	F["dir"].append(dir.normalized())
	F["len"].append(L)
	F["a"].append(a)
	F["b"].append(b)
	F["stand"].append(stand)
	F["cn"].append(cn)
	F["role"].append(role)
	F["need_b"].append(need_b)
	F["penb"].append(penb)
	F["n"] = id + 1
	if cn >= 0:
		F["conns"][cn]["nails"].append(id)
	return id


static func _conn(F: Dictionary, key: String, fam: String, a: int, b: int, end := "", label := "", spacing := 0.0) -> int:
	var id: int = F["conns"].size()
	var wall := wall_of(F["names"][a]) if a >= 0 else ""
	F["conns"].append({"id": id, "key": key, "fam": fam, "a": a, "b": b, "end": end, "wall": wall, "label": label if label != "" else "%s %s" % [key, F["names"][a] if a >= 0 else ""], "nails": [], "spacing": spacing, "miss": 0, "total": 0})
	return id


static func _probe(F: Dictionary, p: Vector3, mask_key := "m_fr") -> int:
	return _fh(F["solids"], F["arr"], F[mask_key], PackedVector3Array([p]))[0]


static func _ext(s: Dictionary, ax: int) -> float:
	return float(s["b"][ax + 3]) - float(s["b"][ax])


# ================================================================== toenails
## a toenail group: A's end face (normal axis n, B on side ns) nailed into B from A's two thin faces. pattern = [count on the + side, count on the - side]
static func _toe(F: Dictionary, cn: int, ntype: String, A: int, B: int, n: int, ns: int, pattern: Array, ang_deg := 30.0, w_lo := NAN, w_hi := NAN, c_iface := NAN) -> void:
	var sa: Dictionary = F["solids"][A]
	var sb: Dictionary = F["solids"][B]
	var ab: Array = sa["b"]
	var bb: Array = sb["b"]
	var L: float = float(TYPES[ntype]["L"]) * IN
	var t := -1
	var w := -1
	var ex := []
	for ax in 3:
		if ax != n:
			ex.append(ax)
	if _ext(sa, ex[0]) <= _ext(sa, ex[1]):
		t = ex[0]
		w = ex[1]
	else:
		t = ex[1]
		w = ex[0]
	var c: float = c_iface if not is_nan(c_iface) else (float(ab[n + 3]) if ns > 0 else float(ab[n]))
	var lo: float = w_lo if not is_nan(w_lo) else maxf(float(ab[w]), float(bb[w])) + 4.0
	var hi: float = w_hi if not is_nan(w_hi) else minf(float(ab[w + 3]), float(bb[w + 3])) - 4.0
	if hi < lo:
		lo = (lo + hi) * 0.5
		hi = lo
	var ang := deg_to_rad(ang_deg)
	var ls := L / 3.0
	# which sides are free (nothing else touching the face where the nail goes in)
	var mid := Vector3.ZERO
	mid[n] = c - ns * ls
	mid[w] = (lo + hi) * 0.5
	var free := {}
	for s in [1, -1]:
		var p := mid
		p[t] = (float(ab[t + 3]) if s > 0 else float(ab[t])) + s * 1.5
		var h := _probe(F, p)
		free[s] = (h < 0 or h == A)
	var cnt := {1: int(pattern[0]), -1: int(pattern[1])}
	var total: int = cnt[1] + cnt[-1]
	if free[1] and not free[-1]:
		cnt = {1: total, -1: 0}
	elif free[-1] and not free[1]:
		cnt = {1: 0, -1: total}
	for s in [1, -1]:
		var m: int = cnt[s]
		for j in m:
			var wp: float = lo + (hi - lo) * (float(j) + 0.5) / float(m)
			var head := Vector3.ZERO
			head[n] = c - ns * ls
			head[t] = float(ab[t + 3]) if s > 0 else float(ab[t])
			head[w] = wp
			var dir := Vector3.ZERO
			dir[n] = ns * cos(ang)
			dir[t] = -s * sin(ang)
			var pen := maxf(0.0, L * cos(ang) - ls)
			_nail(F, ntype, head, dir, A, B, cn, 0.0, 2, 1, pen)


static func _plate_stack_overlap(a: Array, b: Array, ax: int) -> float:
	return minf(a[ax + 3], b[ax + 3]) - maxf(a[ax], b[ax])


# ================================================================== the framing nails
static func _place_frame(F: Dictionary) -> void:
	var S: Array = F["solids"]
	var C := contacts(S)
	F["contacts"] = C
	var kinds_h := ["bottom_plate", "top_plate1", "header", "sill"]
	# ---- stud_to_plate: every vertical member end that meets a horizontal member
	var best := {}
	for c in C:
		if c[2] != 1:
			continue
		var i: int = c[0]
		var j: int = c[1]
		var ki: String = S[i]["kind"]
		var kj: String = S[j]["kind"]
		var v := -1
		var h := -1
		var end := ""
		if c[3] == 1:      # j above i
			if ki in VERT and kj in kinds_h:
				v = i; h = j; end = "top"
			elif kj in VERT and ki in kinds_h:
				continue
		else:               # j below i
			if ki in VERT and kj in kinds_h:
				v = i; h = j; end = "bot"
		if v < 0:
			continue
		var ov: float = _plate_stack_overlap(S[v]["b"], S[h]["b"], 0) * _plate_stack_overlap(S[v]["b"], S[h]["b"], 2)
		var key := "%d|%s" % [v, end]
		if not best.has(key) or ov > best[key][2]:
			best[key] = [v, h, ov, end]
	# the pairs found with i below j and i vertical are "bot" of j: handle the reverse orientation
	for c in C:
		if c[2] != 1:
			continue
		var i: int = c[0]
		var j: int = c[1]
		var ki: String = S[i]["kind"]
		var kj: String = S[j]["kind"]
		# c[3] == 1: j sits above i (i.hi == j.lo). A vertical j on a horizontal i: its bottom end
		if c[3] == 1 and kj in VERT and ki in kinds_h:
			var ov2: float = _plate_stack_overlap(S[j]["b"], S[i]["b"], 0) * _plate_stack_overlap(S[j]["b"], S[i]["b"], 2)
			var key2 := "%d|bot" % j
			if not best.has(key2) or ov2 > best[key2][2]:
				best[key2] = [j, i, ov2, "bot"]
		# c[3] == -1: j sits below i. A vertical j under a horizontal i: its top end
		if c[3] == -1 and kj in VERT and ki in kinds_h:
			var ov3: float = _plate_stack_overlap(S[j]["b"], S[i]["b"], 0) * _plate_stack_overlap(S[j]["b"], S[i]["b"], 2)
			var key3 := "%d|top" % j
			if not best.has(key3) or ov3 > best[key3][2]:
				best[key3] = [j, i, ov3, "top"]
	var keys := best.keys()
	keys.sort()
	for k in keys:
		var e: Array = best[k]
		var cn := _conn(F, "stud_to_plate", "toe", e[0], e[1], e[3])
		_toe(F, cn, "8d_box", e[0], e[1], 1, 1 if e[3] == "top" else -1, [2, 2])
	# gable studs (polygon members): their bottom end on the L / R top plate
	for i in S.size():
		if S[i]["kind"] != "gable_stud":
			continue
		var b: Array = S[i]["b"]
		var p := Vector3((b[0] + b[3]) * 0.5, HW - 1.0, (b[2] + b[5]) * 0.5)
		var pl := _probe_kind(F, p, "top_plate2")
		if pl >= 0:
			var cn2 := _conn(F, "stud_to_plate", "toe", i, pl, "bot")
			_toe(F, cn2, "8d_box", i, pl, 1, -1, [2, 2], 30.0, NAN, NAN, HW)
		else:
			F["findings"].append("gable stud %s: no top plate under it" % S[i]["name"])
	# ---- joist_to_plate: a joist bearing on a top plate
	for c in C:
		if c[2] != 1:
			continue
		var i2: int = c[0]
		var j2: int = c[1]
		var a2 := -1
		var b2 := -1
		if c[3] == 1 and S[j2]["kind"] == "joist" and S[i2]["kind"] == "top_plate2":
			a2 = j2; b2 = i2
		elif c[3] == -1 and S[i2]["kind"] == "joist" and S[j2]["kind"] == "top_plate2":
			a2 = i2; b2 = j2
		if a2 < 0:
			continue
		if _plate_stack_overlap(S[a2]["b"], S[b2]["b"], 2) < 30.0 and _plate_stack_overlap(S[a2]["b"], S[b2]["b"], 0) < 30.0:
			continue
		var cn3 := _conn(F, "joist_to_plate", "toe", a2, b2)
		_toe(F, cn3, "8d_box", a2, b2, 1, -1, [2, 2])
	# ---- plate_to_plate (same wall) and plate_lap (two walls): a top_plate2 on a top_plate1
	for c in C:
		if c[2] != 1:
			continue
		var i3: int = c[0]
		var j3: int = c[1]
		var up := -1
		var dn := -1
		if c[3] == 1 and S[i3]["kind"] == "top_plate1" and S[j3]["kind"] == "top_plate2":
			dn = i3; up = j3
		elif c[3] == -1 and S[i3]["kind"] == "top_plate2" and S[j3]["kind"] == "top_plate1":
			up = i3; dn = j3
		if up < 0:
			continue
		var bu: Array = S[up]["b"]
		var bd: Array = S[dn]["b"]
		var ox := _plate_stack_overlap(bu, bd, 0)
		var oz := _plate_stack_overlap(bu, bd, 2)
		var same := wall_of(S[up]["name"]) == wall_of(S[dn]["name"])
		if same:
			# nails along the wall at 16 in, down through the upper plate into the lower and the stud under it
			var la := 0 if _ext(S[up], 0) >= _ext(S[up], 2) else 2
			var dp := 2 if la == 0 else 0
			var lo: float = maxf(bu[la], bd[la])
			var hi: float = minf(bu[la + 3], bd[la + 3])
			var cn4 := _conn(F, "plate_to_plate", "face", up, dn, "", "", 16.0 * IN)
			var depth_mid: float = (maxf(bu[dp], bd[dp]) + minf(bu[dp + 3], bd[dp + 3])) * 0.5
			_face_line(F, cn4, "16d_com", up, dn, 1, -1, la, lo, hi, 16.0 * IN, 50.0, _vec(1, bu[4], dp, depth_mid), 38.0 + 38.0)
		else:
			if ox < 30.0 or oz < 30.0:
				continue
			var cn5 := _conn(F, "plate_lap", "face", up, dn)
			var cx0: float = maxf(bu[0], bd[0])
			var cx1: float = minf(bu[3], bd[3])
			var cz0: float = maxf(bu[2], bd[2])
			var cz1: float = minf(bu[5], bd[5])
			var fr := [[0.25, 0.25], [0.75, 0.25], [0.5, 0.75]]
			for f in fr:
				var hd := Vector3(cx0 + (cx1 - cx0) * f[0], bu[4], cz0 + (cz1 - cz0) * f[1])
				_nail(F, "10d_box", hd, Vector3(0, -1, 0), up, dn, cn5, 0.0, 2, 1, 38.0)
	# ---- stud_to_stud: built-up posts (king + jack, nailers, corners) face-nailed at 24 in
	var seen := {}
	for c in C:
		if c[2] == 1:
			continue
		var i4: int = c[0]
		var j4: int = c[1]
		var ki4: String = S[i4]["kind"]
		var kj4: String = S[j4]["kind"]
		if not (ki4 in VERT and kj4 in VERT):
			continue
		var special := ["king", "jack", "nailer", "corner", "end"]
		if not (ki4 in special or kj4 in special):
			continue
		var bi: Array = S[i4]["b"]
		var bj: Array = S[j4]["b"]
		var oy: float = _plate_stack_overlap(bi, bj, 1)
		var w3 := 2 if c[2] == 0 else 0
		var ow: float = _plate_stack_overlap(bi, bj, w3)
		if oy < 200.0 or ow < 30.0:
			continue
		var pk := "%d|%d" % [i4, j4]
		if seen.has(pk):
			continue
		seen[pk] = true
		var ax: int = c[2]
		var dirs: int = c[3]      # j on the + side of i when 1
		var lo2: float = maxf(bi[1], bj[1])
		var hi2: float = minf(bi[4], bj[4])
		var wmid: float = (maxf(bi[w3], bj[w3]) + minf(bi[w3 + 3], bj[w3 + 3])) * 0.5
		# A = the member whose far face is free
		var a4 := i4
		var b4 := j4
		var nd := dirs      # nail direction along ax: from A towards B
		var far_i := Vector3.ZERO
		far_i[ax] = (bi[ax] if dirs > 0 else bi[ax + 3]) - dirs * 1.5
		far_i[1] = (lo2 + hi2) * 0.5
		far_i[w3] = wmid
		var hi_hit := _probe(F, far_i)
		if hi_hit >= 0 and hi_hit != i4:
			var far_j := Vector3.ZERO
			far_j[ax] = (bj[ax + 3] if dirs > 0 else bj[ax]) + dirs * 1.5
			far_j[1] = far_i[1]
			far_j[w3] = wmid
			var hj_hit := _probe(F, far_j)
			if hj_hit < 0 or hj_hit == j4:
				a4 = j4; b4 = i4; nd = -dirs
		# CH1e fix: a 16d common (88.9 mm) cannot start through a member 89 mm thick and still reach the next: drive it from the thinner member's free face
		var l16: float = float(TYPES["16d_com"]["L"]) * IN
		if _ext(S[a4], ax) > l16 - 6.0 and _ext(S[b4], ax) <= l16 - 6.0:
			var t4 := a4
			a4 = b4
			b4 = t4
			nd = -nd
		var ba: Array = S[a4]["b"]
		var bbx: Array = S[b4]["b"]
		var face_c: float = (ba[ax] if nd > 0 else ba[ax + 3])
		var fixed := Vector3.ZERO
		fixed[ax] = face_c
		fixed[w3] = wmid
		var cn6 := _conn(F, "stud_to_stud", "face", a4, b4, "", "", 24.0 * IN)
		_face_line(F, cn6, "16d_com", a4, b4, ax, nd, 1, lo2, hi2, 24.0 * IN, 76.2, fixed, _ext(S[a4], ax) + _ext(S[b4], ax))
	# ---- header: built-up (16d at 16 in o.c. each edge) and its ends toed into the king studs
	for i in S.size():
		if S[i]["kind"] != "header":
			continue
		var hb: Array = S[i]["b"]
		var la2 := 0 if _ext(S[i], 0) >= _ext(S[i], 2) else 2
		var dp2 := 2 if la2 == 0 else 0
		var is2x8: bool = _ext(S[i], 1) > 100.0
		if is2x8:
			for row in 2:
				var yy: float = hb[1] + 38.1 if row == 0 else hb[4] - 38.1
				var cn7 := _conn(F, "header_built_up", "face", i, i, "", "%s %s edge" % [S[i]["name"], "bottom" if row == 0 else "top"], 16.0 * IN)
				var fixed2 := Vector3.ZERO
				fixed2[1] = yy
				# nails go in from the face that looks into the house (centre of the plan is x 4877, z 3810)
				var cen := 4877.0 if dp2 == 0 else 3810.0
				var inner_is_hi: bool = ((hb[dp2] + hb[dp2 + 3]) * 0.5) < cen
				fixed2[dp2] = hb[dp2 + 3] if inner_is_hi else hb[dp2]
				_face_line(F, cn7, "16d_com", i, i, dp2, -1 if inner_is_hi else 1, la2, hb[la2], hb[la2 + 3], 16.0 * IN, 50.0, fixed2, 88.9, true)
		# ends: the header end faces the king
		for c in C:
			if c[2] == 1:
				continue
		for end_s in [-1, 1]:
			var kj := -1
			for c in C:
				if c[2] != la2:
					continue
				var o: int = -1
				if c[0] == i and S[c[1]]["kind"] == "king" and c[3] == end_s:
					o = c[1]
				elif c[1] == i and S[c[0]]["kind"] == "king" and c[3] == -end_s:
					o = c[0]
				if o >= 0:
					kj = o
			if kj < 0:
				continue
			var cn8 := _conn(F, "header_to_stud", "toe", i, kj, "")
			_toe(F, cn8, "8d_box", i, kj, la2, end_s, [3, 2])


static func _vec(a1: int, v1: float, a2: int, v2: float) -> Vector3:
	var v := Vector3.ZERO
	v[a1] = v1
	v[a2] = v2
	return v


static func _probe_kind(F: Dictionary, p: Vector3, kind: String) -> int:
	var mk := _mask(F["solids"], [kind])
	return _fh(F["solids"], F["arr"], mk, PackedVector3Array([p]))[0]


## face nails along one line: nails every <= spacing from lo+endd to hi-endd, head on A's face (coordinate in `fixed` on axis n), driven along n * ds
static func _face_line(F: Dictionary, cn: int, ntype: String, A: int, B: int, n: int, ds: int, la: int, lo: float, hi: float, spacing: float, endd: float, fixed: Vector3, stack_mm: float, same_member := false) -> void:
	var L: float = float(TYPES[ntype]["L"]) * IN
	var span := maxf(hi - lo - 2.0 * endd, 0.0)
	var cnt := maxi(2, int(ceil(span / spacing - 1e-9)) + 1)
	var penb := minf(L - (stack_mm if not same_member else 0.0), stack_mm) if not same_member else 38.0
	for k in cnt:
		var p := fixed
		p[la] = lo + endd + span * float(k) / float(cnt - 1)
		var d := Vector3.ZERO
		d[n] = ds
		var pen: float = penb
		if not same_member:
			# penetration into B = the nail length left after A's thickness, up to B's thickness
			var ta: float = _ext(F["solids"][A], n)
			var tb: float = _ext(F["solids"][B], n)
			pen = minf(maxf(L - ta, 0.0), tb)
		_nail(F, ntype, p, d, A, B, cn, 0.0, 2, 1, pen)


# ================================================================== rafters: toenails, ridge, H2.5A
static func _place_roof(F: Dictionary) -> void:
	var S: Array = F["solids"]
	var ridge := -1
	for i in S.size():
		if S[i]["kind"] == "ridge":
			ridge = i
	var nties := 0
	for i in S.size():
		var k: String = S[i]["kind"]
		if not (k in ["rafter", "rafter_pair", "gable_rafter"]):
			continue
		var rb: Array = S[i]["b"]
		var poly: Array = S[i]["poly"]
		var xc: float = (rb[0] + rb[3]) * 0.5
		var front: bool = String(S[i]["name"]).contains("front")
		var zseat: float = 44.5 if front else 7620.0 - 44.5
		var pl := _probe_kind(F, Vector3(xc, HW - 1.0, zseat), "top_plate2")
		if pl < 0:
			F["findings"].append("rafter %s: no top plate under its seat" % S[i]["name"])
			continue
		var pb: Array = S[pl]["b"]
		var cn := _conn(F, "rafter_to_plate", "toe", i, pl)
		_toe(F, cn, "16d_box", i, pl, 1, -1, [2, 1], 22.0, maxf(pb[2], zseat - 40.5), minf(pb[5], zseat + 40.5), HW)     # CH1e: only where the rafter bears on the plate (a gable rafter sits on the side plate, which runs the whole depth)
		# ridge
		if ridge >= 0:
			var zr: float = 3791.0 if front else 3829.0
			var ymin := 1e9
			var ymax := -1e9
			for q in poly:
				if absf(q[0] - zr) < 0.01:
					ymin = minf(ymin, q[1])
					ymax = maxf(ymax, q[1])
			var cn2 := _conn(F, "rafter_to_ridge", "toe", i, ridge)
			_toe(F, cn2, "16d_box", i, ridge, 2, 1 if front else -1, [2, 2], 22.0, ymin + 4.0, ymax - 12.0, zr)
		# H2.5A
		_tie(F, i, pl, front)
		nties += 1


## CH1e layout rafters: bear on the ceiling joist (2-8d box toenails through the rafter's underside) and are face-nailed to the rafter_pair beside them, 16d common at 24 in o.c. (R602.3(1) built-up member)
static func _place_layout(F: Dictionary) -> void:
	var S: Array = F["solids"]
	for i in S.size():
		if S[i]["kind"] != "rafter_layout":
			continue
		var b: Array = S[i]["b"]
		var poly: Array = S[i]["poly"]
		var front: bool = String(S[i]["name"]).contains("front")
		var xc: float = (b[0] + b[3]) * 0.5
		var zc: float = poly[0][0]
		var zin: float = zc + (1.0 if front else -1.0) * 30.0
		var joist := _probe_kind(F, Vector3(xc, 2640.0, zin), "joist")
		if joist >= 0:
			var cn := _conn(F, "rafter_bearing", "toe", i, joist, "", "layout rafter on joist %s" % S[i]["name"])
			# the underside rises 1 in 3 from the heel point, so the rafter touches the joist only at the heel: the toenails go in within 2.4 mm of it, where the wedge is under the 0.6 mm the checker covers
			var lo: float = minf(zc + (0.6 if front else -0.6), zc + (2.4 if front else -2.4))
			var hi: float = maxf(zc + (0.6 if front else -0.6), zc + (2.4 if front else -2.4))
			_toe(F, cn, "8d_box", i, joist, 1, -1, [2, 2], 30.0, lo, hi, float(b[1]))
		else:
			F["findings"].append("layout rafter %s: no joist under its heel" % S[i]["name"])
		# the pair beside it (x face)
		var pair := -1
		for j in S.size():
			if S[j]["kind"] == "rafter_pair" and absf(float(S[j]["b"][0]) - float(b[3])) < 0.6 or S[j]["kind"] == "rafter_pair" and absf(float(S[j]["b"][3]) - float(b[0])) < 0.6:
				if absf(float(S[j]["b"][2]) - float(b[2])) < 1000.0 and String(S[j]["name"]).contains("front") == front:
					pair = j
					break
		if pair < 0:
			F["findings"].append("layout rafter %s: no rafter pair beside it" % S[i]["name"])
			continue
		var side: float = -1.0 if float(S[pair]["b"][0]) > float(b[0]) else 1.0     # the pair is on +x when side = -1: nails enter from the layout rafter's free face
		var xf: float = float(b[0]) if side < 0 else float(b[3])
		var pa: Array = poly[0]
		var pb: Array = poly[1]
		var depth: float = float(poly[3][1]) - float(pa[1])
		var cn2 := _conn(F, "rafter_sister", "face", i, pair, "", "layout rafter %s to %s" % [S[i]["name"], S[pair]["name"]], 24.0 * IN)
		var za: float = float(pa[0])
		var zb: float = float(pb[0])
		var span: float = absf(zb - za) - 2.0 * 90.0
		var cnt := maxi(2, int(ceil(span / (24.0 * IN) - 1e-9)) + 1)
		var zsign: float = 1.0 if zb > za else -1.0
		for k in cnt:
			var z: float = za + zsign * (90.0 + span * float(k) / float(cnt - 1))
			var y: float = float(pa[1]) + (z - za) * (float(pb[1]) - float(pa[1])) / (zb - za) + depth * 0.5
			_nail(F, "16d_com", Vector3(xf, y, z), Vector3(-side, 0, 0), i, pair, cn2, 0.0, 2, 1, minf(float(TYPES["16d_com"]["L"]) * IN - 38.0, 38.0))


static func _tie(F: Dictionary, r: int, pl: int, front: bool) -> void:
	var S: Array = F["solids"]
	var rb: Array = S[r]["b"]
	var si := 1.0 if front else -1.0
	var zi: float = 89.0 if front else 7620.0 - 89.0
	var t := STRAP_T
	# pick the x side of the rafter that is free
	var sx := 1.0
	var okside := {}
	for s in [1.0, -1.0]:
		var xf: float = rb[3] if s > 0 else rb[0]
		var blocked := false
		for pp in [Vector3(xf + s * 4.0, 2510.0, zi + si * 20.0), Vector3(xf + s * 4.0, 2430.0, zi + si * 3.0), Vector3(xf + s * 15.0, 2430.0, zi + si * 3.0)]:
			var h := _probe(F, pp)
			if h >= 0 and h != r:
				blocked = true
		okside[s] = not blocked
	if not okside[1.0] and okside[-1.0]:
		sx = -1.0
	var xf2: float = rb[3] if sx > 0 else rb[0]
	var cn := _conn(F, "h25a", "tie", r, pl, "", "H2.5A on %s" % S[r]["name"])
	F["conns"][cn]["species_note"] = "0.131x1.5 in nails"
	# rafter flange: 5 nails through the strap into the rafter
	var zz := [8.0, 20.0, 32.0, 14.0, 26.0]
	var yy := [2498.0, 2498.0, 2498.0, 2514.0, 2514.0]
	for k in 5:
		var head := Vector3(xf2 + sx * t, yy[k], zi + si * zz[k])
		_nail(F, "h25_nail", head, Vector3(-sx, 0, 0), r, r, cn, t, 2, 0, 38.0 - t)
	# plate flange: 5 nails through the strap into the top plates
	var py := [2402.0, 2415.0, 2428.0, 2441.0, 2454.0]
	for k in 5:
		var xx: float = xf2 - sx * (8.0 if k % 2 == 0 else 20.0)
		var hp := Vector3(xx, py[k], zi + si * t)
		var plate := _probe(F, Vector3(xx, py[k], zi - si * 10.0))
		if plate < 0:
			plate = pl
		_nail(F, "h25_nail", hp, Vector3(0, 0, -si), plate, plate, cn, t, 2, 0, 38.0 - t)
	F["parts"].append({"kind": "h25a", "name": "H2.5A.%s" % S[r]["name"], "conn": cn, "boxes": [
		[minf(xf2, xf2 + sx * t), 2490.0, minf(zi + si * 4.0, zi + si * 44.0), maxf(xf2, xf2 + sx * t), 2525.0, maxf(zi + si * 4.0, zi + si * 44.0)],
		[minf(xf2, xf2 + sx * t), 2463.0, minf(zi, zi + si * 6.0), maxf(xf2, xf2 + sx * t), 2525.0, maxf(zi, zi + si * 6.0)],
		[minf(xf2 + sx * t, xf2 - sx * 30.0), 2395.0, minf(zi, zi + si * t), maxf(xf2 + sx * t, xf2 - sx * 30.0), 2463.0, maxf(zi, zi + si * t)]]})


# ================================================================== anchor bolts, hold-downs
static func _place_anchors(F: Dictionary) -> void:
	var S: Array = F["solids"]
	var ab: Dictionary = F["meta"].get("anchor_bolts", {})
	var pos: Dictionary = ab.get("positions_mm", {})
	var gaps_max := 0.0
	var end_max := 0.0
	var end_min := 1e9
	var skipped: Array = []
	for pname in pos:
		var pi: int = F["idx"].get(pname, -1)
		if pi < 0:
			continue
		var pb: Array = S[pi]["b"]
		var la := 0 if (pb[3] - pb[0]) > (pb[5] - pb[2]) else 2
		var dp := 2 if la == 0 else 0
		var dmid: float = (pb[dp] + pb[dp + 3]) * 0.5
		var plist: Array = []
		var wall := wall_of(pname)
		for u in pos[pname]:
			var p := Vector3(0, -150.0, 0)
			p[la] = float(u)
			p[dp] = dmid
			var ft := _probe_kind(F, p, "footing")
			if ft < 0:
				plist.append(null)
				continue
			plist.append(ft)
		var placed: Array = []
		for k in plist.size():
			if plist[k] == null:
				continue
			placed.append(float(pos[pname][k]))
		if placed.is_empty():
			skipped.append(pname)
			continue
		for k in plist.size():
			if plist[k] == null:
				continue
			var u: float = float(pos[pname][k])
			var head := Vector3(0, 38.0, 0)
			head[la] = u
			head[dp] = dmid
			var cn := _conn(F, "anchor_bolt", "bolt", pi, plist[k], "", "anchor bolt %s @%.0f" % [pname, u])
			_nail(F, "anchor_bolt", head, Vector3(0, -1, 0), pi, plist[k], cn, 0.0, 2, 1, 178.0)
			var c3 := Vector3(0, 0, 0)
			c3[la] = u
			c3[dp] = dmid
			F["parts"].append({"kind": "anchor_bolt", "name": "bolt %s @%.0f" % [pname, u], "conn": cn, "x": c3.x, "z": c3.z, "dia_in": 0.5, "embed_in": 178.0 / IN, "la": la})
			F["parts"].append({"kind": "plate_washer", "name": "washer %s @%.0f" % [pname, u], "conn": cn, "x": c3.x, "z": c3.z, "size_in": 3.0, "t_in": 0.229})
		# layout numbers per plate piece, in inches, from the piece's own ends
		var lo: float = pb[la]
		var hi: float = pb[la + 3]
		placed.sort()
		for k in range(1, placed.size()):
			gaps_max = maxf(gaps_max, (placed[k] - placed[k - 1]) / IN)
		end_max = maxf(end_max, maxf((placed[0] - lo) / IN, (hi - placed[placed.size() - 1]) / IN))
		end_min = minf(end_min, minf((placed[0] - lo) / IN, (hi - placed[placed.size() - 1]) / IN))
		if placed.size() < plist.size():
			F["findings"].append("%s: %d of %d listed bolt positions have no footing under them (embed 7 in impossible in the 4 in slab)" % [pname, plist.size() - placed.size(), plist.size()])
	for pname in skipped:
		F["findings"].append("%s: no bolt placed (no footing: partition sole plate, IRC R403.1.6 covers exterior and bearing walls)" % pname)
	F["bolt_layout"] = {"max_gap_in": gaps_max, "max_end_in": end_max, "min_end_in": end_min if end_min < 1e8 else 0.0}


static func _place_hdu(F: Dictionary) -> void:
	var S: Array = F["solids"]
	var idx: Dictionary = F["idx"]
	var specs := {"F": [0, 2, 1.0], "B": [0, 2, -1.0], "L": [2, 0, 1.0], "R": [2, 0, -1.0]}
	for w in ["F", "B", "L", "R"]:
		var la: int = specs[w][0]
		var dp: int = specs[w][1]
		var si: float = specs[w][2]
		var wlen := 9754.0 if la == 0 else 7620.0
		# opening zones: king a outer face .. king b outer face
		var zones: Array = []
		var k := 0
		while idx.has("king.%s.%da" % [w, k]):
			var ka: Dictionary = S[idx["king.%s.%da" % [w, k]]]
			var kb: Dictionary = S[idx["king.%s.%db" % [w, k]]]
			zones.append([float(ka["b"][la]), float(kb["b"][la + 3]), k])
			k += 1
		zones.sort_custom(func(p, q): return p[0] < q[0])
		var prev := 0.0
		for zi in zones.size() + 1:
			var seg_lo: float = prev
			var seg_hi: float = wlen if zi == zones.size() else zones[zi][0]
			if zi < zones.size():
				prev = zones[zi][1]
			if seg_hi - seg_lo < HW / 3.5:
				continue
			# the segment's two ends: a doubled king + jack post exists where the segment meets an opening
			if zi > 0:
				_hdu(F, w, zones[zi - 1][2], "b", la, dp, si)
			if zi < zones.size():
				_hdu(F, w, zones[zi][2], "a", la, dp, si)


static func _hdu(F: Dictionary, w: String, k: int, side: String, la: int, dp: int, si: float) -> void:
	var S: Array = F["solids"]
	var idx: Dictionary = F["idx"]
	var ki: int = idx["king.%s.%d%s" % [w, k, side]]
	var ji: int = idx["jack.%s.%d%s" % [w, k, side]]
	var kb: Array = S[ki]["b"]
	var jb: Array = S[ji]["b"]
	var u0: float = minf(kb[la], jb[la])
	var u1: float = maxf(kb[la + 3], jb[la + 3])
	var uc := (u0 + u1) * 0.5
	var zface: float = 89.0 if si > 0 else (7620.0 - 89.0 if dp == 2 else 9754.0 - 89.0)
	var cn := _conn(F, "hdu", "hold-down", ki, ji, "", "HDU2 on %s %d%s" % [w, k, side])
	# six SDS screws: two columns (king, jack) x three rows
	for col in 2:
		var u: float = uc + (-19.05 if col == 0 else 19.05)
		var mem: int = ki if (kb[la] <= u and u <= kb[la + 3]) else ji
		for y in [80.0, 130.0, 180.0]:
			var head := Vector3.ZERO
			head[la] = u
			head[1] = y
			head[dp] = zface + si * HDU_T
			var d := Vector3.ZERO
			d[dp] = -si
			_nail(F, "sds", head, d, mem, mem, cn, HDU_T, 2, 0, 61.6)
	# 5/8 in anchor rod: from the seat top (y 9.5) 12 in down into slab + footing
	var hr := Vector3.ZERO
	hr[la] = uc
	hr[1] = 9.5
	hr[dp] = zface + si * 33.3
	var slab := -1
	var foot := _probe_kind(F, Vector3(hr.x, -150.0, hr.z), "footing")
	for i in S.size():
		if S[i]["kind"] == "slab":
			slab = i
	if foot < 0:
		F["findings"].append("HDU %s %d%s: no footing under the rod" % [w, k, side])
		foot = slab
	_nail(F, "hd_rod", hr, Vector3(0, -1, 0), slab, foot, cn, 9.5, 2, 1, 200.0, 309.5)
	var seat_lo := Vector3.ZERO
	var bx0 := Vector3.ZERO
	var bx1 := Vector3.ZERO
	bx0[la] = uc - 38.1
	bx1[la] = uc + 38.1
	bx0[1] = 0.0
	bx1[1] = 221.0
	bx0[dp] = minf(zface, zface + si * HDU_T)
	bx1[dp] = maxf(zface, zface + si * HDU_T)
	var sx0 := bx0
	var sx1 := bx1
	sx1[1] = 9.5
	sx0[dp] = minf(zface, zface + si * 82.6)
	sx1[dp] = maxf(zface, zface + si * 82.6)
	F["parts"].append({"kind": "hdu2", "name": "HDU2-SDS2.5 %s %d%s" % [w, k, side], "conn": cn, "boxes": [[bx0.x, bx0.y, bx0.z, bx1.x, bx1.y, bx1.z], [sx0.x, sx0.y, sx0.z, sx1.x, sx1.y, sx1.z]]})


# ================================================================== sheathing nails
static func _inset_poly(P: Array, d: float) -> Array:
	## P: convex polygon, Vector2 list. Returns the polygon moved inwards by d, counter-clockwise.
	var n := P.size()
	var area := 0.0
	for i in n:
		var a: Vector2 = P[i]
		var b: Vector2 = P[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var Q: Array = P.duplicate()
	if area < 0.0:
		Q.reverse()
	var lines: Array = []
	for i in n:
		var a2: Vector2 = Q[i]
		var b2: Vector2 = Q[(i + 1) % n]
		var e := (b2 - a2).normalized()
		var nn := Vector2(-e.y, e.x)
		lines.append([a2 + nn * d, e])
	var out: Array = []
	for i in n:
		var l1: Array = lines[(i - 1 + n) % n]
		var l2: Array = lines[i]
		var p1: Vector2 = l1[0]
		var e1: Vector2 = l1[1]
		var p2: Vector2 = l2[0]
		var e2: Vector2 = l2[1]
		var den: float = e1.x * e2.y - e1.y * e2.x
		var t: float = ((p2.x - p1.x) * e2.y - (p2.y - p1.y) * e2.x) / den
		out.append(p1 + e1 * t)
	return out


static func _panels(F: Dictionary) -> Array:
	var S: Array = F["solids"]
	var out: Array = []
	var W := 9754.0
	var DP := 7620.0
	for i in S.size():
		var k: String = S[i]["kind"]
		if not (k in SHEATHK):
			continue
		var b: Array = S[i]["b"]
		var p := {"solid": i, "name": S[i]["name"], "kind": k, "wall": wall_of(S[i]["name"])}
		if k == "wall_sheathing":
			var tax := 2 if (p["wall"] == "F" or p["wall"] == "B") else 0     # CH1e: from the wall name; a 0.4 mm sliver of a front sheet is thin in x too and had been taken for a side-wall sheet
			var uax := 2 if tax == 0 else 0
			var cen := 4877.0 if tax == 0 else 3810.0
			var low: bool = (b[tax] + b[tax + 3]) * 0.5 < cen
			var origin := Vector3.ZERO
			origin[tax] = b[tax] if low else b[tax + 3]
			origin[uax] = b[uax]
			origin[1] = b[1]
			var U := Vector3.ZERO
			U[uax] = 1.0
			var N := Vector3.ZERO
			N[tax] = 1.0 if low else -1.0
			p["origin"] = origin
			p["U"] = U
			p["V"] = Vector3(0, 1, 0)
			p["N"] = N
			p["poly"] = [Vector2(0, 0), Vector2(b[uax + 3] - b[uax], 0), Vector2(b[uax + 3] - b[uax], b[4] - b[1]), Vector2(0, b[4] - b[1])]
			p["u0"] = b[uax]
			p["uax"] = uax
		elif k == "gable_sheathing":
			var low2: bool = (b[0] + b[3]) * 0.5 < W * 0.5
			var origin2 := Vector3(b[0] if low2 else b[3], 0, 0)
			var pl: Array = []
			for q in S[i]["poly"]:
				pl.append(Vector2(q[0], q[1] - HW))
			origin2.y = HW
			p["origin"] = origin2
			p["U"] = Vector3(0, 0, 1)
			p["V"] = Vector3(0, 1, 0)
			p["N"] = Vector3(1 if low2 else -1, 0, 0)
			p["poly"] = pl
			p["u0"] = 0.0
			p["uax"] = 2
		else:
			var pts: Array = S[i]["poly"]
			var p0 := Vector2(pts[0][0], pts[0][1])
			var p2 := Vector2(pts[2][0], pts[2][1])
			var p3 := Vector2(pts[3][0], pts[3][1])
			var along := (p2 - p3)
			var Lr := along.length()
			var vdir := along.normalized()
			var nin := -(p3 - p0).normalized()
			p["origin"] = Vector3(b[0], p3.y, p3.x)
			p["U"] = Vector3(1, 0, 0)
			p["V"] = Vector3(0, vdir.y, vdir.x)
			p["N"] = Vector3(0, nin.y, nin.x)
			p["poly"] = [Vector2(0, 0), Vector2(b[3] - b[0], 0), Vector2(b[3] - b[0], Lr), Vector2(0, Lr)]
			p["u0"] = b[0]
			p["uax"] = 0
			p["front"] = String(S[i]["name"]).contains("front")
		out.append(p)
	return out


static func _poly_vrange(poly: Array, u: float) -> Vector2:
	var lo := 1e30
	var hi := -1e30
	var n := poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		if (a.x - u) * (b.x - u) <= 0.0 and absf(b.x - a.x) > 1e-9:
			var t := (u - a.x) / (b.x - a.x)
			var v := a.y + t * (b.y - a.y)
			lo = minf(lo, v)
			hi = maxf(hi, v)
	return Vector2(lo, hi)



## A wall "piece" is a fragment of a 1219.2 mm sheet that was cut around an opening: the line between two fragments of one sheet is not a panel edge, so it carries no edge nails.
## The nails of the remaining (true) edges stay at the code spacing and 9.5 mm inset.
static func _drop_shared_edges(F: Dictionary, p: Dictionary, cands: Array) -> Array:
	var S: Array = F["solids"]
	var me: Dictionary = S[p["solid"]]
	var uax: int = p["uax"]
	var mb: Array = me["b"]
	var col := int(floor((float(mb[uax]) + 0.5) / 1219.2))
	var sibs: Array = []
	for j in S.size():
		if j == p["solid"] or S[j]["kind"] != "wall_sheathing" or wall_of(S[j]["name"]) != p["wall"]:
			continue
		var sb: Array = S[j]["b"]
		if int(floor((float(sb[uax]) + 0.5) / 1219.2)) == col:
			sibs.append(sb)
	if sibs.is_empty():
		return cands
	var u0: float = mb[uax]
	var u1: float = mb[uax + 3]
	var y0: float = mb[1]
	var y1: float = mb[4]
	var out: Array = []
	for c in cands:
		if int(c[3]) < 0:
			out.append(c)
			continue
		var uv: Vector2 = c[0]
		var uw := u0 + uv.x
		var yw := y0 + uv.y
		var shared := false
		for sb in sibs:
			match int(c[3]):
				0:  # bottom edge: a sibling whose top is at y0 and that spans uw
					shared = absf(float(sb[4]) - y0) < 0.5 and uw >= float(sb[uax]) - 0.5 and uw <= float(sb[uax + 3]) + 0.5
				1:  # right edge
					shared = absf(float(sb[uax]) - u1) < 0.5 and yw >= float(sb[1]) - 0.5 and yw <= float(sb[4]) + 0.5
				2:  # top edge
					shared = absf(float(sb[1]) - y1) < 0.5 and uw >= float(sb[uax]) - 0.5 and uw <= float(sb[uax + 3]) + 0.5
				3:  # left edge
					shared = absf(float(sb[uax + 3]) - u0) < 0.5 and yw >= float(sb[1]) - 0.5 and yw <= float(sb[4]) + 0.5
			if shared:
				break
		if not shared:
			out.append(c)
	return out


static func _place_sheathing(F: Dictionary, opts: Dictionary) -> void:
	var S: Array = F["solids"]
	var panels := _panels(F)
	var L: float = float(TYPES["6d_com"]["L"]) * IN
	var support_kinds := {"wall_sheathing": ["stud", "king", "jack", "cripple"], "gable_sheathing": ["gable_stud"], "roof_sheathing": ["rafter", "rafter_pair", "rafter_layout", "gable_rafter"]}
	for p in panels:
		var pw := 0.0
		for q0 in p["poly"]:
			pw = maxf(pw, (q0 as Vector2).x)
		if p["kind"] == "wall_sheathing" and pw < 25.0:
			F["findings"].append("%s: %.1f mm wide, a cut-off sliver of the sheet beside it (builder rounding at the wall end), not a nailable piece" % [p["name"], pw])
			continue
		var cn := _conn(F, "sheathing", "sheath", p["solid"], -1, "", "OSB %s" % p["name"])
		var origin: Vector3 = p["origin"]
		var U: Vector3 = p["U"]
		var V: Vector3 = p["V"]
		var N: Vector3 = p["N"]
		var poly: Array = p["poly"]
		var ins := _inset_poly(poly, SHEATH_EDGE_IN)
		var cands: Array = []     # [Vector2 (u,v), role, inward normal Vector2]
		var n := ins.size()
		for e in n:
			var a: Vector2 = ins[e]
			var b: Vector2 = ins[(e + 1) % n]
			var len := a.distance_to(b)
			var m := maxi(1, int(ceil(len / SHEATH_EDGE_MM - 1e-9)))
			var ed := (b - a).normalized()
			var inn := Vector2(-ed.y, ed.x)
			for k in m:
				cands.append([a.lerp(b, float(k) / float(m)), 0, inn, e])
		# field lines on the supports behind the panel
		var hv: Vector2 = Vector2(0, 0)
		for q in poly:
			hv = Vector2(maxf(hv.x, q.x), maxf(hv.y, q.y))
		var kinds: Array = support_kinds[p["kind"]]
		var u0: float = p["u0"]
		var uax: int = p["uax"]
		for j in S.size():
			if not (S[j]["kind"] in kinds):
				continue
			var sb: Array = S[j]["b"]
			if p["kind"] == "wall_sheathing" and wall_of(S[j]["name"]) != p["wall"]:
				continue
			if p["kind"] == "roof_sheathing":
				var fr: bool = String(S[j]["name"]).contains("front")
				if fr != bool(p["front"]):
					continue
			var uc: float = (sb[uax] + sb[uax + 3]) * 0.5 - u0
			if p["kind"] == "gable_sheathing":
				if (sb[0] + sb[3]) * 0.5 > 9754.0 * 0.5 != (origin.x > 4877.0):
					continue
			var vr := _poly_vrange(poly, uc)
			if vr.y < vr.x or uc < 30.0 or uc > hv.x - 30.0:
				continue
			var vlo := vr.x + SHEATH_EDGE_IN
			var vhi := vr.y - SHEATH_EDGE_IN
			var full := true
			if p["kind"] == "wall_sheathing":
				var oy0: float = origin.y
				var y0 := oy0
				var y1 := oy0 + hv.y
				full = float(sb[1]) <= y0 + 40.0 and float(sb[4]) >= y1 - 80.0
				if not full:
					vlo = maxf(vlo, float(sb[1]) - oy0)
					vhi = minf(vhi, float(sb[4]) - oy0)
					if vhi - vlo < 10.0:
						continue
			var m2 := maxi(1, int(ceil((vhi - vlo) / SHEATH_FIELD_MM - 1e-9)))
			for k in range(0, m2 + 1):
				var edge_end: bool = (k == 0 and (full or vlo <= vr.x + SHEATH_EDGE_IN + 1e-6)) or (k == m2 and (full or vhi >= vr.y - SHEATH_EDGE_IN - 1e-6))
				if edge_end:
					continue
				cands.append([Vector2(uc, vlo + (vhi - vlo) * float(k) / float(m2)), 1, Vector2.ZERO, -1])
		if p["kind"] == "wall_sheathing":
			cands = _drop_shared_edges(F, p, cands)
		# relocate edge nails inwards (up to 30 mm from the edge) when nothing is behind them; batch probe
		var offs := [0.0, 5.5, 10.5, 15.5, 20.5]
		var best_c: Array = []
		for c in cands:
			best_c.append(-1)
		var chosen_pos: Array = []
		for c in cands:
			chosen_pos.append(c[0])
		var chosen_b := PackedInt32Array()
		chosen_b.resize(cands.size())
		for q in cands.size():
			chosen_b[q] = -1
		for oi in offs.size():
			var pts := PackedVector3Array()
			var which: Array = []
			for q in cands.size():
				if chosen_b[q] >= 0:
					continue
				var c: Array = cands[q]
				if oi > 0 and c[1] != 0:
					continue
				var uv: Vector2 = c[0] + (c[2] as Vector2) * offs[oi]
				var pt := origin + U * uv.x + V * uv.y + N * 30.0
				pts.append(pt)
				which.append([q, uv])
			if pts.is_empty():
				break
			var hits := _fh(S, F["arr"], F["m_fr"], pts)
			for r in which.size():
				if hits[r] >= 0:
					chosen_b[which[r][0]] = hits[r]
					chosen_pos[which[r][0]] = which[r][1]
		var decim: int = int(opts.get("decimate", 0))
		for q in cands.size():
			F["conns"][cn]["total"] += 1
			if chosen_b[q] < 0:
				F["conns"][cn]["miss"] += 1
				F["miss_list"].append("%s role %d at u=%.0f v=%.0f (panel %.0f x %.0f)" % [p["name"], cands[q][1], (chosen_pos[q] as Vector2).x, (chosen_pos[q] as Vector2).y, hv.x, hv.y])
				continue
			var uv2: Vector2 = chosen_pos[q]
			var head := origin + U * uv2.x + V * uv2.y
			_nail(F, "6d_com", head, N, p["solid"], chosen_b[q], cn, 0.0, cands[q][1], 1, L - OSB)
		if F["conns"][cn]["miss"] > 0:
			F["findings"].append("%s: %d of %d sheathing nails have no framing behind them" % [p["name"], F["conns"][cn]["miss"], F["conns"][cn]["total"]])


# ================================================================== build
static func build(mj: Dictionary, opts := {}) -> Dictionary:
	var F := _new_state(mj)
	_place_frame(F)
	_place_roof(F)
	_place_layout(F)
	_place_anchors(F)
	_place_hdu(F)
	_place_sheathing(F, opts)
	return F


## a copy of F without every second sheathing nail of one wall (the planted control)
static func decimate(F: Dictionary, wall: String) -> Dictionary:
	var drop := {}
	for c in F["conns"]:
		if c["key"] == "sheathing" and c["wall"] == wall:
			for role in [0, 1]:
				var k := 0
				for id in c["nails"]:
					if F["role"][id] == role:
						if k % 2 == 1:
							drop[id] = true
						k += 1
	var G: Dictionary = F.duplicate()
	var remap := {}
	for k in ["tname", "head", "dir", "len", "a", "b", "stand", "cn", "role", "need_b", "penb"]:
		G[k] = F[k].duplicate()
		G[k].clear() if false else null
	var keys := ["tname", "head", "dir", "len", "a", "b", "stand", "cn", "role", "need_b", "penb"]
	for k in keys:
		G[k] = (F[k] as Variant).duplicate()
		G[k].resize(0)
	var m := 0
	for i in F["n"]:
		if drop.has(i):
			continue
		remap[i] = m
		for k in keys:
			G[k].append(F[k][i])
		m += 1
	G["n"] = m
	G["conns"] = []
	for c in F["conns"]:
		var d: Dictionary = c.duplicate()
		var nl: Array = []
		for id in c["nails"]:
			if remap.has(id):
				nl.append(remap[id])
		d["nails"] = nl
		G["conns"].append(d)
	for i in m:
		G["cn"][i] = G["cn"][i]
	# nail -> connection ids stay valid (connections keep their ids)
	return G


# ================================================================== capacity
static func _species(F: Dictionary) -> Dictionary:
	var sp: String = String(F["meta"].get("species", "DF-L#2"))
	if sp.begins_with("SPF"):
		return {"G": 0.42, "tie": "SPF"}
	return {"G": 0.50, "tie": "DF"}


static func capacity(F: Dictionary, ci: int, V: Dictionary) -> Dictionary:
	var c: Dictionary = F["conns"][ci]
	var sp := _species(F)
	var G: float = sp["G"]
	var T10 := 0.0
	var V10 := 0.0
	var T16 := -1.0
	var V16 := -1.0
	var src := ""
	match c["fam"]:
		"toe":
			for id in c["nails"]:
				var tv: Array = TOE_VAL[G][F["tname"][id]]
				T10 += tv[0]
				V10 += tv[1]
			src = "AWC DA-2 toenail W (Ctn 0.67) and Z (Ctn 0.83), G %.2f" % G
		"face":
			for id in c["nails"]:
				var nt: String = F["tname"][id]
				V10 += float(FACE_Z[G][nt]) / CTN_Z
				T10 += FACE_PEN_FACTOR * pow(G, 2.5) * float(TYPES[nt]["D"]) * float(F["penb"][id]) / IN
			src = "face nail Z = DA-2 Z / 0.83; W = 1380 G^2.5 D x measured penetration"
		"sheath":
			for id in c["nails"]:
				V10 += SHEATH_V_160 / CD_WIND
				T10 += FACE_PEN_FACTOR * pow(G, 2.5) * float(TYPES["6d_com"]["D"]) * float(F["penb"][id]) / IN
			src = "6d common: SDPWS ASD 100 lb per nail (CD 1.6 basis); W = 1380 G^2.5 D x (nail - OSB)"
		"tie":
			var tv2: Array = H25A[sp["tie"]]
			T16 = tv2[0]
			V16 = tv2[1]
			T10 = T16 / CD_WIND
			V10 = V16 / CD_WIND
			src = "Simpson C-C-2021 p.277 H2.5A, 0.131x1.5 nails, (160)"
		"hold-down":
			T16 = HDU2[sp["tie"]]
			T10 = T16 / CD_WIND
			src = "Simpson C-C-2021 p.52 HDU2-SDS2.5, (160)"
		"bolt":
			T10 = HouseCheck.anchor_capacity(0.5, 178.0 / IN)
			T16 = T10
			V16 = BOLT_V_160
			V10 = V16 / CD_WIND
			src = "tension: house_check ACI/A307 hand calc (UNVERIFIED); shear 1040 lb (160) secondary"
	if T16 < 0.0:
		T16 = T10 * CD_WIND
	if V16 < 0.0:
		V16 = V10 * CD_WIND
	return {"T10": T10, "V10": V10, "T16": T16, "V16": V16, "src": src}


# ================================================================== schedule
static func schedule_failures(F: Dictionary) -> Array:
	var out: Array = []
	var HCs := HouseCheck.FASTENERS
	for c in F["conns"]:
		var key: String = c["key"]
		var ids: Array = c["nails"]
		if HCs.has(key):
			var row: Dictionary = HCs[key]
			if float(row["spacing_in"]) <= 0.0:
				if ids.size() != int(row["n"]):
					out.append("%s %s: %d nails, row says %d" % [key, c["label"], ids.size(), int(row["n"])])
			else:
				var g := _max_gap(F, ids)
				if g > float(row["spacing_in"]) * IN + 6.35 or ids.size() < 2:
					out.append("%s %s: gap %.1f mm over the row's %.1f" % [key, c["label"], g, float(row["spacing_in"]) * IN])
		elif key == "sheathing":
			var kind: String = F["solids"][c["a"]]["kind"]
			var ge := _nn_gap(F, ids, 0)
			var gf := _nn_gap(F, ids, 1)
			var bad: bool = ge > SHEATH_EDGE_MM + 6.35 or gf > SHEATH_FIELD_MM + 6.35
			if kind == "wall_sheathing":
				if bad or c["miss"] > 0:
					out.append("%s: edge gap %.1f mm (limit 158.75), field gap %.1f mm (limit 311.15), %d unsupported" % [c["label"], ge, gf, c["miss"]])
	return out


static func _max_gap(F: Dictionary, ids: Array) -> float:
	if ids.size() < 2:
		return 0.0
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for i in ids:
		var p: Vector3 = F["head"][i]
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
		pos.append(float(F["head"][i][ax]))
	pos.sort()
	var mg := 0.0
	for k in range(1, pos.size()):
		mg = maxf(mg, pos[k] - pos[k - 1])
	return mg


## the largest distance from a nail of the given role (0 edge, 1 field) to its nearest neighbour of the same role in the same connection
static func _nn_gap(F: Dictionary, ids: Array, role: int) -> float:
	var pts: Array = []
	for i in ids:
		if F["role"][i] == role:
			pts.append(F["head"][i])
	if pts.size() < 2:
		return 0.0
	var worst := 0.0
	for a in pts.size():
		var best := 1e30
		for b in pts.size():
			if a != b:
				best = minf(best, (pts[a] as Vector3).distance_to(pts[b]))
		worst = maxf(worst, best)
	return worst
