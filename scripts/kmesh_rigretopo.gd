class_name KMeshRigRetopo
extends RefCounted
## F10 ★ (docs/ROADMAP_400.md): RIG-AWARE RETOPO of the fighter's skin (G01, all triangles). Each arm and leg is rebuilt as
## a quad tube whose edge loops are placed from the SKELETON, not from the triangles: the joints are A18's bone segments
## (KMeshBody.segments_from_skeleton, the rest pose, taken into the mesh's space); the triangle layout only supplies the
## surface the loops are projected onto.
## PER LIMB (arm: upperarm -> lowerarm -> hand; leg: thigh -> calf -> foot), a chain J0 (shoulder / hip) -> J1 (elbow /
## knee) -> J2 (wrist / ankle), arc length s along it:
##   RADIAL RINGS round the shoulder / hip: RADIAL loops where the skin meets spheres centred on J0 (radii r0, r0 + step,
##     ...). A ring vertex per sector: in the half-plane through the limb axis at that sector's angle, the skin point at
##     distance r from J0 nearest the axis (smallest angle to it). r0 is the smallest radius (1 cm steps from r_start)
##     at which every sector finds the limb (angle <= ALPHA_MAX) AND the skin beyond the ring separates cleanly (below).
##   PLANE RINGS: perpendicular to the bone; the vertex of sector j is where the ray from the bone axis, in the ring's
##     plane, at angle 2 pi j / n, first meets the skin (the cross-section of the skin by the plane, so every vertex is ON
##     a skin triangle). In the bend zone (elbow +-6 cm, knee +-7 cm) ZONE_RINGS rings evenly over +-ZONE_FILL of the zone;
##     between the radial rings and the zone, and from the zone to the wrist / ankle end ring, rings evenly at ~"gap".
##     The plane's normal is the bone's direction; inside the zone it turns smoothly (smoothstep) from the upper bone's to
##     the lower's, so the rings never cross on the inside of a bent joint (the mannequin's rest bends are ~1 deg).
##   Quads between consecutive rings (n sectors: arms 12, legs 16): inside a tube every vertex has 4 edges and every face is
##     a quad, so the bend zones have no pole and no triangle.
## JUNCTIONS, honestly: the torso, head, hands and feet are NOT remeshed. They are the mannequin's own surface: the skin
##   triangles outside the tubes are kept as they are, then paired into quads by F06's rule (KMeshTopo.quadrangulate,
##   UV seams respected; ~90 % pair). Each tube is cut out of the skin: a skin face is the tube's when it lies past the
##   root sphere (not all corners inside r0 - MARGIN), before the end plane (not all corners past it + MARGIN), within
##   RAD_TOL x the tube's own radius of the axis there (so the torso / the other leg are never taken), connected to the
##   limb, plus any island the tube encloses. Its border must be exactly two loops, the root one wholly inside the r0
##   sphere and the end one wholly past the end plane (else r0 grows a cm and it tries again); each loop is joined to the
##   tube's end ring by one strip of triangles (a zipper, ordered by angle round the axis). Triangles and poles are
##   therefore only on those two junction strips per limb (armpit / groin side of the shoulder / hip, the wrist, above the
##   ankle) and in the kept surface; never in a bend zone.
## CARRIED: every input channel (A09) on the kept skin as it was; on a new vertex the "skin:<bone>" weights are the skin's
##   at that point (the vertex lies on a skin triangle: its corners' weights by barycentric position), snapped to 16-bit
##   steps that sum to exactly 1 (BaseBody.canon); "uv" the same way (seams are not respected inside a tube: a quad that
##   straddles the arm's UV seam blends across it); "surface" the hit triangle's. A face channel PART says what each face
##   is: 0 the kept skin, 1 a tube quad, 2 a junction triangle.

const PART := "retopo_part"
const W := "skin:"
const ZONE_RINGS := 5        # rings in a bend zone (spread evenly over +- ZONE_FILL of it)
const ZONE_FILL := 0.8
const RADIAL := 3            # radial rings round the shoulder / hip
const ALPHA_MAX := 70.0      # deg: a radial ring vertex further than this off the limb axis is not on the limb
const MARGIN := 0.003        # m
const RAD_TOL := 1.35        # a skin face is the tube's when within RAD_TOL x its radius (+ RAD_ADD) of the axis
const RAD_ADD := 0.01
const CAND_R := 0.3          # m: skin triangles further than this from the limb's bones are never looked at
const R_MAX := 0.3

## arms: 12 sectors, ~3.5 cm between rings, the elbow zone +-6 cm; legs: 16 sectors, ~4.5 cm, the knee zone +-7 cm.
## end_back: the end ring sits this far before the wrist / ankle joint (the hand / foot is kept skin)
const LIMBS := [
	{"name": "arm_l", "bones": ["upperarm_l", "lowerarm_l", "hand_l"], "joint": "elbow_l", "zone": 0.06, "n": 12, "gap": 0.035, "r_start": 0.07, "r_step": 0.02, "end_back": 0.02},
	{"name": "arm_r", "bones": ["upperarm_r", "lowerarm_r", "hand_r"], "joint": "elbow_r", "zone": 0.06, "n": 12, "gap": 0.035, "r_start": 0.07, "r_step": 0.02, "end_back": 0.02},
	{"name": "leg_l", "bones": ["thigh_l", "calf_l", "foot_l"], "joint": "knee_l", "zone": 0.07, "n": 16, "gap": 0.045, "r_start": 0.10, "r_step": 0.025, "end_back": 0.06},
	{"name": "leg_r", "bones": ["thigh_r", "calf_r", "foot_r"], "joint": "knee_r", "zone": 0.07, "n": 16, "gap": 0.045, "r_start": 0.10, "r_step": 0.025, "end_back": 0.06},
]

static var last := {}


# ---------------------------------------------------------------- the skeleton

## the joints (each bone's own joint, A18's segment start) in the mesh's space: {UE5 bone name: Vector3}.
## xf: the mesh's space -> the segments' space (the skinned pieces' global transform)
static func joints_from_segs(segs: Array, xf := Transform3D.IDENTITY) -> Dictionary:
	var inv := xf.affine_inverse()
	var out := {}
	for s in segs:
		out[s["bone"]] = inv * (s["a"] as Vector3)
	return out


## the fighter's rest joints in the body mesh's space (main: m.skel, the skinned pieces)
static func joints_of(m: Node) -> Dictionary:
	if m.get("skel") == null or m.skel == null:
		return {}
	var xf := Transform3D.IDENTITY
	if m.get("pieces") != null and not m.pieces.is_empty():
		xf = (m.pieces.values()[0] as MeshInstance3D).global_transform
	return joints_from_segs(KMeshBody.segments_from_skeleton(m.skel, false), xf)


static func _chain(J: Dictionary, lb: Dictionary) -> Dictionary:
	var b: Array = lb["bones"]
	if not (J.has(b[0]) and J.has(b[1]) and J.has(b[2])):
		return {}
	var j0: Vector3 = J[b[0]]
	var j1: Vector3 = J[b[1]]
	var j2: Vector3 = J[b[2]]
	var l1 := j0.distance_to(j1)
	var l2 := j1.distance_to(j2)
	if l1 < 1e-4 or l2 < 1e-4:
		return {}
	var du := (j1 - j0) / l1
	var dl := (j2 - j1) / l2
	var up := Vector3.UP if absf(du.dot(Vector3.UP)) < 0.9 else Vector3.BACK
	return {"j0": j0, "j1": j1, "j2": j2, "l1": l1, "l2": l2, "du": du, "dl": dl, "e1": (up - du * up.dot(du)).normalized(),
		"zone": float(lb["zone"]), "n": int(lb["n"])}


## the point on the chain at arc length s (past either end: on along the end bone)
static func _c_at(ch: Dictionary, s: float) -> Vector3:
	if s <= ch["l1"]:
		return ch["j0"] + ch["du"] * s
	return ch["j1"] + ch["dl"] * (s - ch["l1"])


## the ring plane's normal at s: the bone's direction, turning smoothly across the bend zone
static func _d_at(ch: Dictionary, s: float) -> Vector3:
	var z: float = ch["zone"]
	var l1: float = ch["l1"]
	if s <= l1 - z:
		return ch["du"]
	if s >= l1 + z:
		return ch["dl"]
	var t := smoothstep(l1 - z, l1 + z, s)
	return (ch["du"] as Vector3).slerp(ch["dl"], t).normalized()


## [e1, e2] round the normal d (e1 the chain's reference direction made perpendicular to d)
static func _frame(ch: Dictionary, d: Vector3) -> Array:
	var e1: Vector3 = ch["e1"]
	e1 = (e1 - d * e1.dot(d)).normalized()
	return [e1, d.cross(e1)]


## where p is along the chain: [s, distance from the axis, angle round it (0..TAU)]
static func _where(ch: Dictionary, p: Vector3) -> Array:
	var j0: Vector3 = ch["j0"]
	var j1: Vector3 = ch["j1"]
	var du: Vector3 = ch["du"]
	var dl: Vector3 = ch["dl"]
	var t1 := clampf((p - j0).dot(du), -0.5, ch["l1"])
	var q1 := j0 + du * t1
	var t2 := clampf((p - j1).dot(dl), 0.0, float(ch["l2"]) + 0.5)
	var q2 := j1 + dl * t2
	var s: float
	var r: Vector3
	var d: Vector3
	if p.distance_squared_to(q1) <= p.distance_squared_to(q2):
		s = t1
		r = p - q1
		d = du
	else:
		s = float(ch["l1"]) + t2
		r = p - q2
		d = dl
	var fr := _frame(ch, d)
	var phi := atan2(r.dot(fr[1]), r.dot(fr[0]))
	if phi < 0.0:
		phi += TAU
	return [s, r.length(), phi]


# ---------------------------------------------------------------- rings

class _Skin:
	var P: PackedVector3Array
	var T := PackedInt32Array()    # 3 verts per triangle (the faces fanned)
	var TF := PackedInt32Array()   # the face of each triangle
	var TC := PackedInt32Array()   # 3 corners per triangle (the face's corner index, A09 corner domain)

	func _init(k: KMesh) -> void:
		P = k.verts
		var he0 := k.face_he0
		for fi in k.faces.size():
			var f: PackedInt32Array = k.faces[fi]
			for i in range(1, f.size() - 1):
				T.append_array([f[0], f[i], f[i + 1]])
				TC.append_array([he0[fi], he0[fi] + i, he0[fi] + i + 1])
				TF.append(fi)


## the skin's cross-section by the plane (c, d) over the triangles `cand`, then n rays from c at the sector angles:
## {"pts", "tri", "bary", "ok"} (ok = every sector hit)
static func _plane_ring(sk: _Skin, cand: PackedInt32Array, c: Vector3, d: Vector3, fr: Array, n: int) -> Dictionary:
	var sa := PackedVector3Array()
	var sb := PackedVector3Array()
	var st := PackedInt32Array()
	for t in cand:
		var vs := [sk.P[sk.T[3 * t]], sk.P[sk.T[3 * t + 1]], sk.P[sk.T[3 * t + 2]]]
		var ds := [(vs[0] - c).dot(d), (vs[1] - c).dot(d), (vs[2] - c).dot(d)]
		var cut := PackedVector3Array()
		for e in 3:
			var x: float = ds[e]
			var y: float = ds[(e + 1) % 3]
			if (x >= 0.0) != (y >= 0.0):
				cut.append(vs[e] + (vs[(e + 1) % 3] - vs[e]) * (x / (x - y)))
		if cut.size() == 2:
			sa.append(cut[0])
			sb.append(cut[1])
			st.append(t)
	return _cast(sk, sa, sb, st, c, d, fr, n)


static func _cast(sk: _Skin, sa: PackedVector3Array, sb: PackedVector3Array, st: PackedInt32Array, c: Vector3, d: Vector3, fr: Array, n: int) -> Dictionary:
	var pts := PackedVector3Array()
	var tri := PackedInt32Array()
	var ok := true
	for j in n:
		var a := TAU * j / n
		var u: Vector3 = fr[0] * cos(a) + fr[1] * sin(a)
		var w := d.cross(u)
		var best := INF
		var hit := Vector3.ZERO
		var ht := -1
		for k in sa.size():
			var pa := sa[k] - c
			var pb := sb[k] - c
			var wa := pa.dot(w)
			var wb := pb.dot(w)
			if (wa > 0.0 and wb > 0.0) or (wa < 0.0 and wb < 0.0) or wa == wb:
				continue
			var x := pa + (pb - pa) * (wa / (wa - wb))
			var lam := x.dot(u)
			if lam > 1e-6 and lam < best:
				best = lam
				hit = c + x
				ht = st[k]
		if ht < 0:
			ok = false
		pts.append(hit)
		tri.append(ht)
	return {"pts": pts, "tri": tri, "ok": ok}


## the radial ring of radius r round J0: per sector, the skin point at distance r in the half-plane through the axis
## nearest the axis. {"pts", "tri", "ok", "alpha" (the largest angle off the axis, deg)}
static func _sphere_ring(sk: _Skin, cand: PackedInt32Array, cd: PackedFloat32Array, ch: Dictionary, r: float) -> Dictionary:
	var j0: Vector3 = ch["j0"]
	var a: Vector3 = ch["du"]
	var fr := _frame(ch, a)
	var n: int = ch["n"]
	var near := PackedInt32Array()   # the triangles the sphere can cut
	for i in cand.size():
		if cd[2 * i] - 0.03 <= r and cd[2 * i + 1] >= r:
			near.append(cand[i])
	var pts := PackedVector3Array()
	var tri := PackedInt32Array()
	var ok := true
	var amax := 0.0
	for j in n:
		var ang := TAU * j / n
		var u: Vector3 = fr[0] * cos(ang) + fr[1] * sin(ang)
		var w := a.cross(u)
		var best := INF
		var hit := Vector3.ZERO
		var ht := -1
		for t in near:
			var vs := [sk.P[sk.T[3 * t]] - j0, sk.P[sk.T[3 * t + 1]] - j0, sk.P[sk.T[3 * t + 2]] - j0]
			var ds := [(vs[0] as Vector3).dot(w), (vs[1] as Vector3).dot(w), (vs[2] as Vector3).dot(w)]
			var cut := PackedVector3Array()
			for e in 3:
				var x: float = ds[e]
				var y: float = ds[(e + 1) % 3]
				if (x >= 0.0) != (y >= 0.0):
					cut.append(vs[e] + (vs[(e + 1) % 3] - vs[e]) * (x / (x - y)))
			if cut.size() != 2:
				continue
			var P0 := cut[0]
			var D := cut[1] - cut[0]
			var qa := D.length_squared()
			if qa < 1e-14:
				continue
			var qb := 2.0 * P0.dot(D)
			var qc := P0.length_squared() - r * r
			var disc := qb * qb - 4.0 * qa * qc
			if disc < 0.0:
				continue
			var sq := sqrt(disc)
			for mu in [(-qb - sq) / (2.0 * qa), (-qb + sq) / (2.0 * qa)]:
				if mu < 0.0 or mu > 1.0:
					continue
				var x: Vector3 = P0 + D * mu
				if x.dot(u) <= 0.0:
					continue
				var al := acos(clampf(x.dot(a) / r, -1.0, 1.0))
				if al < best:
					best = al
					hit = j0 + x
					ht = t
		if ht < 0 or rad_to_deg(best) > ALPHA_MAX:
			ok = false
		else:
			amax = maxf(amax, rad_to_deg(best))
		pts.append(hit)
		tri.append(ht)
	return {"pts": pts, "tri": tri, "ok": ok, "alpha": amax}


## the plane rings' arc lengths for root radius r_last: [s list (in order), the zone's first index]
static func _plane_s(ch: Dictionary, lb: Dictionary, r_last: float) -> Array:
	var z: float = ch["zone"]
	var l1: float = ch["l1"]
	var gap: float = lb["gap"]
	var out := []
	var sz0 := l1 - z * ZONE_FILL
	var sz1 := l1 + z * ZONE_FILL
	var sa := r_last + maxf(0.015, gap * 0.75)
	if sz0 - sa > gap * 0.5:
		var nn := maxi(1, roundi((sz0 - sa) / gap))
		for i in nn:
			out.append(sa + (sz0 - sa) * i / nn)
	var zi := out.size()
	for i in ZONE_RINGS:
		out.append(sz0 + (sz1 - sz0) * i / (ZONE_RINGS - 1))
	var se: float = l1 + float(ch["l2"]) - float(lb["end_back"])
	var nn2 := maxi(1, roundi((se - sz1) / gap))
	for i in range(1, nn2 + 1):
		out.append(sz1 + (se - sz1) * i / nn2)
	return [out, zi]


# ---------------------------------------------------------------- one limb

## the skin triangles near the chain, with their verts' [min, max] distance to J0 and [min, max] s
static func _cands(sk: _Skin, ch: Dictionary) -> Dictionary:
	var cand := PackedInt32Array()
	var cd := PackedFloat32Array()
	var cs := PackedFloat32Array()
	var j0: Vector3 = ch["j0"]
	var ws := {}
	for t in sk.T.size() / 3:
		var c := (sk.P[sk.T[3 * t]] + sk.P[sk.T[3 * t + 1]] + sk.P[sk.T[3 * t + 2]]) / 3.0
		if float(_where(ch, c)[1]) > CAND_R:
			continue
		cand.append(t)
		var dmin := INF
		var dmax := 0.0
		var smin := INF
		var smax := -INF
		for q in 3:
			var v := sk.T[3 * t + q]
			var p := sk.P[v]
			dmin = minf(dmin, p.distance_to(j0))
			dmax = maxf(dmax, p.distance_to(j0))
			if not ws.has(v):
				ws[v] = float(_where(ch, p)[0])
			smin = minf(smin, ws[v])
			smax = maxf(smax, ws[v])
		cd.append_array([dmin, dmax])
		cs.append_array([smin, smax])
	return {"cand": cand, "cd": cd, "cs": cs}


static func _near_s(cc: Dictionary, s: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cand: PackedInt32Array = cc["cand"]
	var cs: PackedFloat32Array = cc["cs"]
	for i in cand.size():
		if cs[2 * i] - 0.02 <= s and cs[2 * i + 1] + 0.02 >= s:
			out.append(cand[i])
	return out


## build one limb's tube; -> {"ok", "why", "rings": [{"kind", "r" or "s", "pts", "tri"}], "zone_first", "r0", "C" (skin
## faces it replaces), "loops": [root loop, end loop] (skin verts, in the covered faces' winding)}
static func _limb(k: KMesh, sk: _Skin, ch: Dictionary, lb: Dictionary) -> Dictionary:
	var cc := _cands(sk, ch)
	var n: int = ch["n"]
	var memo := {}
	var why := "no radius up to %.0f cm separates the limb" % (R_MAX * 100.0)
	var r0: float = lb["r_start"]
	while r0 <= R_MAX + 1e-6:
		var rings := []
		var good := true
		for q in RADIAL:
			var r: float = r0 + float(lb["r_step"]) * q
			var rr: Dictionary = _sphere_ring(sk, cc["cand"], cc["cd"], ch, r)
			if not rr["ok"]:
				good = false
				break
			rings.append({"kind": "radial", "r": r, "pts": rr["pts"], "tri": rr["tri"]})
		if not good:
			r0 += 0.01
			continue
		var ps := _plane_s(ch, lb, r0 + float(lb["r_step"]) * (RADIAL - 1))
		for s in ps[0]:
			var key := snappedf(s, 1e-6)
			if not memo.has(key):
				var d := _d_at(ch, s)
				memo[key] = _plane_ring(sk, _near_s(cc, s), _c_at(ch, s), d, _frame(ch, d), n)
			var pr: Dictionary = memo[key]
			if not pr["ok"]:
				good = false
				why = "a ring at %.1f cm along the limb found no skin in some direction" % (s * 100.0)
				break
			rings.append({"kind": "plane", "s": s, "pts": pr["pts"], "tri": pr["tri"]})
		if not good:
			break
		var cov := _cover(k, sk, ch, rings, r0, ps[0][ps[0].size() - 1], cc)
		if cov["ok"]:
			return {"ok": true, "why": "", "rings": rings, "zone_first": RADIAL + int(ps[1]), "r0": r0, "C": cov["C"], "loops": cov["loops"]}
		why = cov["why"]
		r0 += 0.01
	return {"ok": false, "why": why}


## the skin faces the tube replaces (see the header) and their two border loops
static func _cover(k: KMesh, sk: _Skin, ch: Dictionary, rings: Array, r0: float, s_end: float, cc: Dictionary) -> Dictionary:
	var n: int = ch["n"]
	var j0: Vector3 = ch["j0"]
	var ce := _c_at(ch, s_end)
	var de := _d_at(ch, s_end)
	# the tube's radius per sector along s: [s, radius] per ring
	var prof := []
	for j in n:
		var row := []
		for rg in rings:
			var w := _where(ch, (rg["pts"] as PackedVector3Array)[j])
			row.append([w[0], w[1]])
		row.sort_custom(func(x, y): return x[0] < y[0])
		prof.append(row)
	var rad_at := func(s: float, j: int) -> float:
		var row: Array = prof[j]
		if s <= row[0][0]:
			return row[0][1]
		for i in range(1, row.size()):
			if s <= row[i][0]:
				var t: float = (s - row[i - 1][0]) / maxf(1e-9, row[i][0] - row[i - 1][0])
				return lerpf(row[i - 1][1], row[i][1], t)
		return row[row.size() - 1][1]
	var faces := {}
	for t in (cc["cand"] as PackedInt32Array):
		faces[sk.TF[t]] = true
	var cover := {}
	var span_kept := {}
	for fi in faces:
		var f: PackedInt32Array = k.faces[fi]
		var in_root := true
		var past_end := true
		for v in f:
			if k.verts[v].distance_to(j0) >= r0 - MARGIN:
				in_root = false
			if (k.verts[v] - ce).dot(de) <= MARGIN:
				past_end = false
		if in_root or past_end:
			span_kept[fi] = true
			continue
		var c := k.face_center(fi)
		if (c - j0).dot(ch["du"]) <= 0.0:
			continue
		var w := _where(ch, c)
		if float(w[0]) > s_end + 0.05:
			continue
		var sec := float(w[2]) / (TAU / n)
		var ja := floori(sec) % n
		var rad := maxf(rad_at.call(w[0], ja), rad_at.call(w[0], (ja + 1) % n))
		if float(w[1]) <= RAD_TOL * rad + RAD_ADD:
			cover[fi] = true
	if cover.is_empty():
		return {"ok": false, "why": "no skin along the limb"}
	# flood from the face nearest the middle joint
	var seed := -1
	var sd := INF
	for fi in cover:
		var d := k.face_center(fi).distance_to(ch["j1"])
		if d < sd:
			sd = d
			seed = fi
	var tw := k.he_twin
	var hf := k.he_face
	var he0 := k.face_he0
	var C := {seed: true}
	var stack := [seed]
	while not stack.is_empty():
		var fi: int = stack.pop_back()
		for i in (k.faces[fi] as PackedInt32Array).size():
			var t: int = tw[he0[fi] + i]
			if t < 0:
				continue
			var g: int = hf[t]
			if cover.has(g) and not C.has(g):
				C[g] = true
				stack.append(g)
	# islands the tube encloses: an uncovered component with no span-kept face and nothing far from the limb
	var flag := {}   # face -> true (absorbed) / false (stays)
	for fi in C.keys():
		for i in (k.faces[fi] as PackedInt32Array).size():
			var t: int = tw[he0[fi] + i]
			if t < 0:
				continue
			var g0: int = hf[t]
			if C.has(g0) or flag.has(g0):
				continue
			var comp := [g0]
			var seen := {g0: true}
			var stays := false
			var at := 0
			while at < comp.size() and not stays:
				var g: int = comp[at]
				at += 1
				if span_kept.has(g) or not faces.has(g) or flag.has(g) and flag[g] == false or comp.size() > 4000:
					stays = true
					break
				for q in (k.faces[g] as PackedInt32Array).size():
					var t2: int = tw[he0[g] + q]
					if t2 < 0:
						continue
					var h: int = hf[t2]
					if not C.has(h) and not seen.has(h):
						seen[h] = true
						comp.append(h)
			for g in comp:
				flag[g] = not stays
	for g in flag:
		if flag[g]:
			C[g] = true
	# the border loops
	var out_h := {}   # origin vert -> half-edge on C's border
	var hv := k.he_vert
	var hn := k.he_next
	for fi in C:
		for i in (k.faces[fi] as PackedInt32Array).size():
			var h: int = he0[fi] + i
			if tw[h] >= 0 and C.has(hf[tw[h]]):
				continue
			if out_h.has(hv[h]):
				return {"ok": false, "why": "the cut is pinched at a vertex (r0 %.0f cm)" % (r0 * 100.0)}
			out_h[hv[h]] = h
	var loops := []
	var used := {}
	for v0 in out_h:
		if used.has(v0):
			continue
		var lp := PackedInt32Array()
		var v: int = v0
		while not used.has(v):
			used[v] = true
			lp.append(v)
			if not out_h.has(hv[hn[out_h[v]]]):
				return {"ok": false, "why": "an open border"}
			v = hv[hn[out_h[v]]]
		loops.append(lp)
	if loops.size() != 2:
		return {"ok": false, "why": "the cut has %d border loops, not 2 (r0 %.0f cm)" % [loops.size(), r0 * 100.0]}
	var md := []
	for lp in loops:
		var s := 0.0
		for v in lp:
			s += k.verts[v].distance_to(j0)
		md.append(s / lp.size())
	if md[1] < md[0]:
		loops.reverse()
	for v in loops[0]:
		if k.verts[v].distance_to(j0) >= r0:
			return {"ok": false, "why": "the root cut reaches past the radial ring (r0 %.0f cm)" % (r0 * 100.0)}
	for v in loops[1]:
		if (k.verts[v] - ce).dot(de) <= 0.0:
			return {"ok": false, "why": "the end cut is not past the end ring"}
	return {"ok": true, "C": C, "loops": loops}


# ---------------------------------------------------------------- the whole body

## Rebuild the skin k (a KMesh with "skin:" channels, G01) with quad tubes on the limbs. J: joints in k's space
## (joints_of / joints_from_segs). opts: {"only": [limb names]} to build some limbs. k is not changed.
## -> {"mesh": KMesh, "ms", "limbs": [{"name", "ok", "why", "r0", "rings": [{"kind", "r"/"s", "verts" (output ids)}],
##     "zone_first", "joint", "axis", "zone", "j0"}], "verts", "faces", "quads"}
static func build(k: KMesh, J: Dictionary, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var sk := _Skin.new(k)
	var only: Array = opts.get("only", [])
	var limbs := []
	var taken := {}   # skin face -> limb name
	for lb in LIMBS:
		if not only.is_empty() and not only.has(lb["name"]):
			continue
		var ch := _chain(J, lb)
		if ch.is_empty():
			limbs.append({"name": lb["name"], "ok": false, "why": "the skeleton lacks its bones"})
			continue
		var r := _limb(k, sk, ch, lb)
		r["name"] = lb["name"]
		r["ch"] = ch
		if r["ok"]:
			for fi in r["C"]:
				if taken.has(fi):
					r["ok"] = false
					r["why"] = "its cut overlaps %s's" % taken[fi]
					break
			if r["ok"]:
				for fi in r["C"]:
					taken[fi] = lb["name"]
		limbs.append(r)
	var res := _assemble(k, sk, limbs)
	var out: KMesh = res["mesh"]
	var q := 0
	for f in out.faces:
		q += 1 if (f as PackedInt32Array).size() == 4 else 0
	var info := []
	for L in limbs:
		var ch: Dictionary = L.get("ch", {})
		var li := {"name": L["name"], "ok": L["ok"], "why": L.get("why", "")}
		if L["ok"]:
			li["r0"] = L["r0"]
			li["zone_first"] = L["zone_first"]
			li["rings"] = L["out_rings"]
			li["j0"] = ch["j0"]
			li["joint"] = ch["j1"]
			li["j2"] = ch["j2"]
			li["axis"] = ((ch["du"] as Vector3) + (ch["dl"] as Vector3)).normalized()
			li["zone"] = ch["zone"]
		info.append(li)
	last = {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "limbs": info, "verts": out.verts.size(), "faces": out.faces.size(), "quads": q,
		"paired": res["paired"]}
	var ret := last.duplicate()
	ret["mesh"] = out
	return ret


## the barycentric weights of p in triangle t
static func _bary(sk: _Skin, t: int, p: Vector3) -> Vector3:
	var a := sk.P[sk.T[3 * t]]
	var b := sk.P[sk.T[3 * t + 1]]
	var c := sk.P[sk.T[3 * t + 2]]
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-18:
		return Vector3(1, 0, 0)
	var v := (d11 * d20 - d01 * d21) / den
	var w := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - v - w, v, w)


static func _assemble(k: KMesh, sk: _Skin, limbs: Array) -> Dictionary:
	var C := {}
	for L in limbs:
		if L["ok"]:
			for fi in L["C"]:
				C[fi] = true
	# the kept skin
	var vmap := PackedInt32Array()
	vmap.resize(k.verts.size())
	vmap.fill(-1)
	var pos := PackedVector3Array()
	var vsrc := PackedInt32Array()
	var faces := []
	var fsrc := PackedInt32Array()
	var csrc := PackedInt32Array()
	var part := PackedFloat32Array()
	var he0 := k.face_he0
	var vuv := {}   # skin vert -> a uv it has on a kept face
	var has_uv: bool = k.has_attr("uv") and k.attr_info("uv")["domain"] == KMesh.AD_CORNER
	for fi in k.faces.size():
		if C.has(fi):
			continue
		var f: PackedInt32Array = k.faces[fi]
		var nf := PackedInt32Array()
		for i in f.size():
			var v := f[i]
			if vmap[v] < 0:
				vmap[v] = pos.size()
				pos.append(k.verts[v])
				vsrc.append(v)
			nf.append(vmap[v])
			csrc.append(he0[fi] + i)
			if has_uv and not vuv.has(v):
				vuv[v] = k.get_attr("uv", he0[fi] + i)
		faces.append(nf)
		fsrc.append(fi)
		part.append(0.0)
	var kept_n := faces.size()
	# the tubes: new verts (on skin triangles), quads, zippers
	var nvt := []   # per new vert: [tri, bary]
	var fuv := []   # per new face: its corners' uvs (null = skin vert uv lookup done here)
	var fsurf := PackedFloat32Array()
	var has_surf: bool = k.has_attr("surface") and k.attr_info("surface")["domain"] == KMesh.AD_FACE
	for L in limbs:
		if not L["ok"]:
			continue
		var ch: Dictionary = L["ch"]
		var n: int = ch["n"]
		var ids := []
		for rg in L["rings"]:
			var row := PackedInt32Array()
			for j in n:
				var p: Vector3 = (rg["pts"] as PackedVector3Array)[j]
				var t: int = (rg["tri"] as PackedInt32Array)[j]
				row.append(pos.size())
				pos.append(p)
				vsrc.append(-1)
				nvt.append([t, _bary(sk, t, p)])
			ids.append(row)
		# quads, outward
		var flip := false
		var r1: PackedInt32Array = ids[1]
		var r0i: PackedInt32Array = ids[0]
		var qa := pos[r0i[0]]
		var qb := pos[r0i[1]]
		var qc := pos[r1[1]]
		var nrm := (qb - qa).cross(qc - qa)
		var cen := (qa + qb + qc) / 3.0
		var w0 := _where(ch, cen)
		var axis_pt := _c_at(ch, w0[0])
		# wind the tube the way the skin winds (its faces round the elbow / knee, which the tube replaces)
		var skin_out := 0.0
		for fi in L["C"]:
			var fc := k.face_center(fi)
			if fc.distance_to(ch["j1"]) < 0.15:
				skin_out += signf(k.face_normals[fi].dot(fc - _c_at(ch, _where(ch, fc)[0])))
		if (nrm.dot(cen - axis_pt) < 0.0) != (skin_out < 0.0):
			flip = true
		var out_rings := []
		for i in ids.size():
			out_rings.append({"kind": L["rings"][i]["kind"], "r": L["rings"][i].get("r", -1.0), "s": L["rings"][i].get("s", -1.0), "verts": ids[i]})
		L["out_rings"] = out_rings
		for i in ids.size() - 1:
			var A: PackedInt32Array = ids[i]
			var B: PackedInt32Array = ids[i + 1]
			for j in n:
				var jn := (j + 1) % n
				var f := PackedInt32Array([A[j], A[jn], B[jn], B[j]])
				if flip:
					f = PackedInt32Array([A[j], B[j], B[jn], A[jn]])
				faces.append(f)
				part.append(1.0)
		# zippers: the root loop to ring 0 (axis du through J0), the end loop to the last ring (its plane's axis)
		var s_last: float = L["rings"][ids.size() - 1]["s"]
		_zip(faces, part, pos, k, vmap, L["loops"][0], ids[0], ch["j0"], ch["du"], ch)
		_zip(faces, part, pos, k, vmap, L["loops"][1], ids[ids.size() - 1], _c_at(ch, s_last), _d_at(ch, s_last), ch)
	var out := KMesh.new().from_arrays(pos, faces)
	# channels: the kept items' own values; the new verts' weights and uvs from their skin triangle
	var nk := vsrc.size()
	var obase := PackedInt32Array()
	var acc := 0
	for f in out.faces:
		obase.append(acc)
		acc += (f as PackedInt32Array).size()
	for nm in k.list_attrs():
		var inf := k.attr_info(nm)
		out.add_attr(nm, inf["domain"], inf["type"], inf["default"])
		var src = k.attr_data(nm)
		var dst = out.attr_data(nm)
		var dom := String(inf["domain"])
		if dom == KMesh.AD_VERT:
			for v in nk:
				if vsrc[v] >= 0:
					dst[v] = src[vsrc[v]]
		elif dom == KMesh.AD_FACE:
			for fi in kept_n:
				dst[fi] = src[fsrc[fi]]
		elif dom == KMesh.AD_CORNER:
			for c in csrc.size():
				dst[c] = src[csrc[c]]
		else:
			var es: Array = out.edges()
			for e in es.size():
				var a: int = vsrc[(es[e] as Vector2i).x]
				var b: int = vsrc[(es[e] as Vector2i).y]
				if a >= 0 and b >= 0:
					var ei := k.edge_index(a, b)
					if ei >= 0:
						dst[e] = src[ei]
		out.set_attr_data(nm, dst)
	# weights of the new verts: barycentric on their skin triangle, then whole 16-bit steps summing to 1
	var chans := []
	for nm in k.list_attrs():
		if String(nm).begins_with(W) and k.attr_info(nm)["domain"] == KMesh.AD_VERT:
			chans.append(nm)
	var cdata := []
	var odata := []
	for nm in chans:
		cdata.append(k.attr_data(nm))
		odata.append(out.attr_data(nm))
	var first_new := 0
	while first_new < nk and vsrc[first_new] >= 0:
		first_new += 1
	for v in range(first_new, nk):
		var t: int = nvt[v - first_new][0]
		var bc: Vector3 = nvt[v - first_new][1]
		var d := {}
		for ci in chans.size():
			var col: PackedFloat32Array = cdata[ci]
			var x := bc.x * col[sk.T[3 * t]] + bc.y * col[sk.T[3 * t + 1]] + bc.z * col[sk.T[3 * t + 2]]
			if x > 1e-7:
				d[ci] = x
		d = BaseBody.canon(d)
		for ci in d:
			var col2: PackedFloat32Array = odata[ci]   # packed arrays are values: write the copy, put it back
			col2[v] = float(d[ci])
			odata[ci] = col2
	for ci in chans.size():
		out.set_attr_data(chans[ci], odata[ci])
	# surface + uv on the new faces
	if has_surf or has_uv:
		var sd = out.attr_data("surface") if has_surf else null
		var ud = out.attr_data("uv") if has_uv else null
		var ksurf = k.attr_data("surface") if has_surf else null
		var nuv := {}
		for fi in range(kept_n, out.faces.size()):
			var f: PackedInt32Array = out.faces[fi]
			var surf := 0.0
			for i in f.size():
				var v := f[i]
				var uv := Vector2.ZERO
				if vsrc[v] >= 0:
					uv = vuv.get(vsrc[v], Vector2.ZERO)
				else:
					var t: int = nvt[v - first_new][0]
					var bc: Vector3 = nvt[v - first_new][1]
					if has_uv:
						if not nuv.has(v):
							nuv[v] = bc.x * (k.get_attr("uv", sk.TC[3 * t]) as Vector2) + bc.y * (k.get_attr("uv", sk.TC[3 * t + 1]) as Vector2) + bc.z * (k.get_attr("uv", sk.TC[3 * t + 2]) as Vector2)
						uv = nuv[v]
					if has_surf:
						surf = ksurf[sk.TF[t]]
				if has_uv:
					ud[obase[fi] + i] = uv
			if has_surf:
				sd[fi] = surf
		if has_surf:
			out.set_attr_data("surface", sd)
		if has_uv:
			out.set_attr_data("uv", ud)
	out.add_attr(PART, KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	out.set_attr_data(PART, part)
	# the kept skin's triangles paired into quads (F06's rule; uv seams kept)
	var kept_ids := []
	for fi in kept_n:
		kept_ids.append(fi)
	var qr := KMeshTopo.quadrangulate(out, kept_ids)
	return {"mesh": out, "paired": qr.get("quads", 0)}


## one strip of triangles between a skin border loop B (in the covered faces' winding: the new faces keep it) and a tube
## ring A, merged by angle round the axis (c, d)
static func _zip(faces: Array, part: PackedFloat32Array, pos: PackedVector3Array, k: KMesh, vmap: PackedInt32Array, B: PackedInt32Array, A: PackedInt32Array, c: Vector3, d: Vector3, ch: Dictionary) -> void:
	var fr := _frame(ch, d)
	var ang := func(p: Vector3) -> float:
		var r := p - c
		return atan2(r.dot(fr[1]), r.dot(fr[0]))
	var wrap := func(x: float) -> float:
		return fposmod(x + PI, TAU) - PI
	var M := B.size()
	var N := A.size()
	# B's cumulative angle, its turning sense
	var tb := PackedFloat32Array([0.0])
	for i in range(1, M + 1):
		tb.append(tb[i - 1] + wrap.call(ang.call(k.verts[B[i % M]]) - ang.call(k.verts[B[i - 1]])))
	var sense := 1.0 if tb[M] >= 0.0 else -1.0
	# A in the same sense, starting at the vertex nearest B[0]'s angle
	var a_seq := PackedInt32Array()
	var b0: float = ang.call(k.verts[B[0]])
	var st := 0
	var bd := INF
	for j in N:
		var dd := absf(wrap.call(ang.call(pos[A[j]]) - b0))
		if dd < bd:
			bd = dd
			st = j
	for i in N:
		a_seq.append(A[posmod(st + int(sense) * i, N)])
	var ta := PackedFloat32Array([sense * wrap.call(ang.call(pos[a_seq[0]]) - b0)])
	for i in range(1, N + 1):
		ta.append(ta[i - 1] + sense * wrap.call(ang.call(pos[a_seq[i % N]]) - ang.call(pos[a_seq[i - 1]])))
	for i in tb.size():
		tb[i] *= sense
	var ib := 0
	var ia := 0
	while ib < M or ia < N:
		var adv_b := ia >= N or (ib < M and tb[ib + 1] <= ta[ia + 1])
		var b := vmap[B[ib % M]]
		var a := a_seq[ia % N]
		if adv_b:
			faces.append(PackedInt32Array([b, vmap[B[(ib + 1) % M]], a]))
			ib += 1
		else:
			faces.append(PackedInt32Array([b, a_seq[(ia + 1) % N], a]))
			ia += 1
		part.append(2.0)


# ---------------------------------------------------------------- the model preview

## MeshTools op "rigretopo": the open body mesh rebuilt, one KMeshUndo step; returns what to say
static func op(m) -> String:
	var ui = m.kmed
	if ui == null or ui.mesh == null or not ui.on:
		return "Model: open the body first (Search \"Model: edit the body mesh\")"
	var has_w := false
	for nm in ui.mesh.list_attrs():
		has_w = has_w or String(nm).begins_with(W)
	if not has_w:
		return "Model: rig-aware retopo needs the fighter's skin (Search \"Model: edit the body mesh\"): this mesh has no skin weights"
	var J := joints_of(m)
	if J.is_empty():
		return "Model: no skeleton to place the loops from"
	var r := build(ui.mesh, J)
	var out: KMesh = r["mesh"]
	var done := []
	var bad := []
	for L in r["limbs"]:
		if L["ok"]:
			done.append(L["name"])
		else:
			bad.append("%s (%s)" % [L["name"], L["why"]])
	if done.is_empty():
		return "Model: rig-aware retopo found no limb to rebuild: " + "; ".join(bad)
	var mesh: KMesh = ui.mesh
	ui.undo.begin(mesh)
	mesh.attrs = {}
	mesh.custom_normals = []
	mesh.from_arrays(out.verts, out.faces)
	mesh.attrs = out.attrs
	ui.undo.commit("rig-aware retopo")
	ui._after_topo()
	return "Model: rig-aware retopo: %d verts, %d faces (%d quads); %s rebuilt as quad tubes, %d loops across each elbow / knee, radial rings at the shoulders / hips; torso, hands, feet, head kept (triangles paired); %.1f s. Ctrl+Z undoes%s" % [
		r["verts"], r["faces"], r["quads"], ", ".join(done), ZONE_RINGS, float(r["ms"]) / 1000.0, ("" if bad.is_empty() else ". Not rebuilt: " + "; ".join(bad))]
