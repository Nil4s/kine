class_name ModelChecks
extends RefCounted
## B30 (docs/ROADMAP_400.md): MODEL CHECKS. One call grades a KMesh for animation against the fighter's skeleton and
## lists the problems worst first, each with the elements to select ("show me", scripts/model_checks_ui.gd) and a next
## step. The checks:
##  (a) POLES IN A BEND ZONE: a vertex whose valence is not 4 (KMeshTopo.heat's rule: interior 3 / 5 / 6+, a border
##      vertex counts one edge more) inside a joint's bend zone.
##  (b) N-GONS AND TRIANGLES IN A BEND ZONE: a face of 5+ corners / 3 corners whose centre is inside a bend zone.
##  (c) THIN PARTS: a vertex whose ray inward (along minus its normal) leaves the mesh again within THIN (the far side's
##      surface, a face that faces along the ray, not one of the vertex's own faces): the skin is thinner than THIN there.
##  (d) TOO FEW EDGE LOOPS ACROSS A HINGE (elbow, knee): the loops crossing the bend are counted on 16 half-planes round
##      the joint's axis (each through the axis, at 22.5 deg steps, offset so none lies on a regular edge column): an edge
##      of the joint's two bones crossing a half-plane inside the zone is one loop there; the joint's count is the
##      median over the 16. Under LOOPS_MIN (3) is a warning.
##  (e) BROKEN SURFACE: KMeshValidate.report (non-manifold edges, flipped neighbours, inside out, holes, doubled / loose
##      verts, faces with no area).
##  (f) WEIGHTS, when the mesh is skinned (G01's "skin:<bone>" channels or H01's skin_bones / skin_weights): a vertex
##      with no weight at all, or with more than 4 bones (the GPU keeps 4).
## BEND ZONE (A18 labels, KMeshBody): the joints are the shoulder (clavicle -> upperarm), elbow (upperarm -> lowerarm),
##   wrist (lowerarm -> hand), hip (pelvis -> thigh) and knee (thigh -> calf), each side; the joint point is the child
##   bone's start. A vertex is in a joint's zone when its nearest bone (KMeshBody's label) is one of the joint's two
##   bones and its distance from the joint point ALONG that bone is at most ZONE_CM of the joint. Everything is measured
##   in world space (the mesh through xf, the segments as KMeshBody.segments_from_skeleton gives them).
## SCORE (0-100) = 100 - the sum of the findings' points, each category capped:
##   poles      20 x min(1, 2 x poles in zones / verts in zones)
##   n-gons     20 x min(1, 2 x (n-gons + 0.5 x triangles in zones) / faces in zones)
##   loops      15 x mean over the hinges present of max(0, 3 - loops) / 3
##   thin       15 x min(1, 10 x thin verts / verts)
##   surface    20 x min(1, (non-manifold + flipped + hole edges + doubled + loose + degenerate) / (1 % of the edges));
##              inside out = the full 20
##   weights    10 x min(1, 5 x (unweighted + over-4 verts) / verts)      (skinned meshes only)
##   A category's points are shared among its findings by their counts (a joint with twice the poles costs twice as
##   much), so the findings' points add up to 100 - score exactly.

const ZONE_CM := {"shoulder": 8.0, "elbow": 6.0, "wrist": 4.0, "hip": 9.0, "knee": 7.0}
## joint -> [parent stem, child stem] (a stem + "_l" / "_r" is the bone; pelvis has no side)
const JOINTS := {"shoulder": ["clavicle", "upperarm"], "elbow": ["upperarm", "lowerarm"], "wrist": ["lowerarm", "hand"],
	"hip": ["pelvis", "thigh"], "knee": ["thigh", "calf"]}
const HINGES := ["elbow", "knee"]
const LOOPS_MIN := 3
const PLANES := 16
const PLANE_OFF := 0.1234   # rad: the half-planes' offset off the axis frame
const THIN := 0.005         # m: a part thinner than this is flagged
const THIN_EPS := 0.0001    # m: the ray starts this far inside (it must not hit the vertex's own surface)
const MAX_INFL := 4
const PTS := {"pole": 20.0, "ngon": 20.0, "loops": 15.0, "thin": 15.0, "surface": 20.0, "weights": 10.0}
## the order a tie of points is listed in
const KINDS := ["inside_out", "non_manifold", "flipped", "holes", "degenerate", "doubled", "loose", "pole", "ngon", "tri",
	"loops", "thin", "unweighted", "over4"]
const FORMULA := "score = 100 - points: poles 20 x min(1, 2 x share of bend-zone verts), n-gons/tris 20 x min(1, 2 x (n-gons + tris/2) share of bend-zone faces), loops 15 x mean (3 - loops)/3 at elbows/knees, thin 15 x min(1, 10 x share of verts under 5 mm), surface 20 x min(1, bad elements / 1% of edges), weights 10 x min(1, 5 x share of bad verts)"
const SEL_VERT := 0   # KMeshSelect.VERT / EDGE / FACE
const SEL_EDGE := 1
const SEL_FACE := 2


## the joints the skeleton has: [{"name" ("elbow_l"), "kind" ("elbow"), "at" (world), "u" (the child bone's direction),
## "bones" ({BONES index: segment index}), "zone" (m)}]
static func joints_of(segs: Array) -> Array:
	var by := {}
	for i in segs.size():
		by[String(segs[i]["bone"])] = i
	var out := []
	for kind in JOINTS:
		for side in ["_l", "_r"]:
			var pa: String = JOINTS[kind][0] + ("" if JOINTS[kind][0] == "pelvis" else side)
			var ch: String = JOINTS[kind][1] + side
			if not by.has(ch):
				continue
			var cs: Dictionary = segs[by[ch]]
			var u: Vector3 = (cs["b"] - cs["a"])
			if u.length() < 1e-6:
				continue
			var bones := {int(cs["bi"]): by[ch]}
			if by.has(pa):
				bones[int(segs[by[pa]]["bi"])] = by[pa]
			out.append({"name": kind + side, "kind": kind, "at": cs["a"], "u": u.normalized(), "bones": bones,
				"zone": float(ZONE_CM[kind]) / 100.0})
	return out


## the joint whose zone holds world point p for a vertex labelled with BONES index bi (-1 = none). The nearer joint
## point wins when two zones hold it (the pelvis is in both hips' zones, a short forearm in the elbow's and the wrist's)
static func _zone_at(p: Vector3, bi: int, joints: Array, segs: Array) -> int:
	var best := -1
	var bd := INF
	for j in joints.size():
		var jt: Dictionary = joints[j]
		if not (jt["bones"] as Dictionary).has(bi):
			continue
		var s: Dictionary = segs[jt["bones"][bi]]
		var d: Vector3 = s["b"] - s["a"]
		if d.length() < 1e-9:
			continue
		var ax := absf((p - (jt["at"] as Vector3)).dot(d.normalized()))
		var near := p.distance_to(jt["at"])   # between two zones (the pelvis's: both hips) the nearer joint point wins
		if ax <= float(jt["zone"]) + 1e-9 and near < bd:
			bd = near
			best = j
	return best


## the grade. segs: KMeshBody.segments_from_skeleton (world); xf: the mesh's local -> world. opts: {"thin": m}
## -> {"score" (int), "points" (float, 100 - sum), "findings": [finding, worst first], "formula", "joints": [{name,
## verts, faces, loops (hinges)}], "skinned", "ms"}. A finding: {"kind", "joint" ("" = not a joint's), "count", "pts",
## "title", "next", "mode" (SEL_*), "items" (vert ids / Vector2i edges / face ids), plus kind-specific numbers}
static func grade(mesh: KMesh, segs: Array, xf := Transform3D.IDENTITY, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var nv := mesh.verts.size()
	var wp := PackedVector3Array()
	wp.resize(nv)
	for v in nv:
		wp[v] = xf * mesh.verts[v]
	var joints := joints_of(segs)
	var vz := PackedInt32Array()
	vz.resize(nv)
	vz.fill(-1)
	var fz := PackedInt32Array()
	fz.resize(mesh.faces.size())
	fz.fill(-1)
	var lab := PackedFloat32Array()
	if not segs.is_empty():
		KMeshBody.refresh(mesh, segs, xf)   # A18: the labels, fresh (derived data: not an undo step)
		lab = mesh.attr_data(KMeshBody.CH_BONE)
		for v in nv:
			vz[v] = _zone_at(wp[v], int(lab[v]), joints, segs)
		for fi in mesh.faces.size():
			var f: PackedInt32Array = mesh.faces[fi]
			var c := Vector3.ZERO
			for v in f:
				c += wp[v]
			c /= maxf(1.0, f.size())
			var tried := {}
			for v in f:
				var bi := int(lab[v])
				if tried.has(bi):
					continue
				tried[bi] = true
				var j := _zone_at(c, bi, joints, segs)
				if j >= 0:
					fz[fi] = j
					break
	var jinfo := []
	for jt in joints:
		jinfo.append({"name": jt["name"], "verts": 0, "faces": 0, "poles": [], "ngons": [], "tris": [], "zone_faces": []})
	for v in nv:
		if vz[v] >= 0:
			jinfo[vz[v]]["verts"] += 1
	for fi in fz.size():
		if fz[fi] >= 0:
			jinfo[fz[fi]]["faces"] += 1
			(jinfo[fz[fi]]["zone_faces"] as Array).append(fi)
	var findings := []
	# (a) + (b)
	var h := KMeshTopo.heat(mesh)
	var vk: PackedInt32Array = h["vert"]
	var fk: PackedInt32Array = h["face"]
	var zv := 0
	var zf := 0
	var npole := 0
	var nbad := 0.0
	for v in nv:
		if vz[v] >= 0 and vk[v] != KMeshTopo.V_OK:
			(jinfo[vz[v]]["poles"] as Array).append(v)
			npole += 1
	for fi in fz.size():
		if fz[fi] < 0:
			continue
		var n := (mesh.faces[fi] as PackedInt32Array).size()
		if n >= 5:
			(jinfo[fz[fi]]["ngons"] as Array).append(fi)
			nbad += 1.0
		elif n == 3:
			(jinfo[fz[fi]]["tris"] as Array).append(fi)
			nbad += 0.5
	for ji in jinfo:
		zv += int(ji["verts"])
		zf += int(ji["faces"])
	var pole_pts := PTS["pole"] * minf(1.0, 2.0 * npole / maxf(1.0, zv))
	var ngon_pts := PTS["ngon"] * minf(1.0, 2.0 * nbad / maxf(1.0, zf))
	for ji in jinfo:
		var pl: Array = ji["poles"]
		if not pl.is_empty():
			findings.append(_f("pole", ji["name"], pl, SEL_VERT, pole_pts * pl.size() / float(npole),
				"%s: %d pole%s (valence not 4) in the bend zone" % [ji["name"], pl.size(), "" if pl.size() == 1 else "s"],
				"move the pole%s off the bend, a loop or two up the limb (rotate or dissolve the edge): the crease folds cleanly only through valence-4 verts" % ("" if pl.size() == 1 else "s")))
		var ng: Array = ji["ngons"]
		if not ng.is_empty():
			findings.append(_f("ngon", ji["name"], ng, SEL_FACE, ngon_pts * ng.size() / nbad,
				"%s: %d n-gon%s on the bend" % [ji["name"], ng.size(), "" if ng.size() == 1 else "s"],
				"cut %s into quads (knife Shift+K, or a loop cut Ctrl+R across it) so the bend folds along edges" % ("it" if ng.size() == 1 else "them")))
		var tr: Array = ji["tris"]
		if not tr.is_empty():
			findings.append(_f("tri", ji["name"], tr, SEL_FACE, ngon_pts * 0.5 * tr.size() / nbad,
				"%s: %d triangle%s on the bend" % [ji["name"], tr.size(), "" if tr.size() == 1 else "s"],
				"join them into quads (Alt+J, tris to quads) or reroute the loop so the bend is all quads"))
	# (d) loops across the hinges
	var hinge_n := 0
	var miss := 0.0
	var loop_rows := []
	for j in joints.size():
		var jt: Dictionary = joints[j]
		if not HINGES.has(jt["kind"]) or int(jinfo[j]["verts"]) == 0:
			continue
		hinge_n += 1
		var lc := loops_across(mesh, wp, lab, jt)
		jinfo[j]["loops"] = lc
		if lc < LOOPS_MIN:
			miss += float(LOOPS_MIN - lc) / LOOPS_MIN
			loop_rows.append([j, lc])
	for r in loop_rows:
		var ji: Dictionary = jinfo[r[0]]
		var lc: int = r[1]
		var f := _f("loops", ji["name"], ji["zone_faces"], SEL_FACE, PTS["loops"] * (float(LOOPS_MIN - lc) / LOOPS_MIN) / maxf(1.0, hinge_n),
			"%s: %d edge loop%s across the bend (want %d or more)" % [ji["name"], lc, "" if lc == 1 else "s", LOOPS_MIN],
			"add loops across the joint with a loop cut (Ctrl+R): one on the crease and one each side, so it bends round, not folds")
		f["loops"] = lc
		findings.append(f)
	# (c) thin parts
	var thin: Dictionary = thin_verts(mesh, wp, float(opts.get("thin", THIN)))
	var tv: PackedInt32Array = thin["verts"]
	if not tv.is_empty():
		var tpts := PTS["thin"] * minf(1.0, 10.0 * tv.size() / maxf(1.0, nv))
		var groups := {}
		var reg: PackedFloat32Array = mesh.attr_data(KMeshBody.CH_REGION) if mesh.has_attr(KMeshBody.CH_REGION) and not segs.is_empty() else PackedFloat32Array()
		var dmin := {}
		for k in tv.size():
			var v := tv[k]
			var g := "the mesh"
			if not reg.is_empty() and reg[v] >= 0.0:
				g = KMeshBody.REGIONS[int(reg[v])]
			if not groups.has(g):
				groups[g] = []
				dmin[g] = INF
			(groups[g] as Array).append(v)
			dmin[g] = minf(dmin[g], (thin["mm"] as PackedFloat32Array)[k])
		for g in groups:
			var it: Array = groups[g]
			var f := _f("thin", "", it, SEL_VERT, tpts * it.size() / float(tv.size()),
				"%s: %d vert%s on a part thinner than %.0f mm (thinnest %.1f mm)" % [g, it.size(), "" if it.size() == 1 else "s", float(opts.get("thin", THIN)) * 1000.0, dmin[g]],
				"thicken it (a Solidify in the modifier stack, or move the sides apart): a shell this thin pinches through itself when it bends")
			f["region"] = g
			f["min_mm"] = dmin[g]
			findings.append(f)
	# (e) the surface (KMeshValidate)
	var rep := KMeshValidate.report(mesh)
	var srows := []
	var sbad := 0.0
	var inside_out := false
	for p in rep["problems"]:
		var kind := String(p["kind"])
		var items: Array = []
		var mode := SEL_VERT
		match kind:
			"non_manifold":
				mode = SEL_EDGE
				for e in p["items"]:
					items.append(Vector2i(mini(e[0], e[1]), maxi(e[0], e[1])))
			"flipped":
				mode = SEL_EDGE
				items = flipped_edges(mesh)
			"holes":
				mode = SEL_EDGE
				for loop in p["items"]:
					var l: Array = loop
					for i in l.size():
						items.append(Vector2i(mini(l[i], l[(i + 1) % l.size()]), maxi(l[i], l[(i + 1) % l.size()])))
			"degenerate":
				mode = SEL_FACE
				items = (p["items"] as Array).duplicate()
			"inside_out":
				mode = SEL_FACE
				inside_out = true
				for fi in mesh.faces.size():
					items.append(fi)
			_:
				items = (p["items"] as Array).duplicate()
		if kind != "inside_out":
			sbad += items.size()
		srows.append([kind, items, mode, String(p["fix"])])
	var ne := maxf(1.0, mesh.edge_count())
	var spts := PTS["surface"] if inside_out else PTS["surface"] * minf(1.0, sbad / maxf(1.0, 0.01 * ne))
	for r in srows:
		var share: float = 1.0 if inside_out and r[0] == "inside_out" else (0.0 if inside_out else float((r[1] as Array).size()) / maxf(1.0, sbad))
		findings.append(_f(r[0], "", r[1], r[2], spts * share, _surface_title(r[0], (r[1] as Array).size()), r[3]))
	# (f) weights
	var wr := weight_problems(mesh)
	if wr["skinned"]:
		var un: Array = wr["unweighted"]
		var o4: Array = wr["over4"]
		var nb := un.size() + o4.size()
		var wpts := PTS["weights"] * minf(1.0, 5.0 * nb / maxf(1.0, nv))
		if not un.is_empty():
			findings.append(_f("unweighted", "", un, SEL_VERT, wpts * un.size() / float(nb),
				"%d vert%s with no skin weight (they stay behind when the body moves)" % [un.size(), "" if un.size() == 1 else "s"],
				"bind to the skeleton again (auto weights) or weight paint them (Model: weight paint)"))
		if not o4.is_empty():
			findings.append(_f("over4", "", o4, SEL_VERT, wpts * o4.size() / float(nb),
				"%d vert%s weighted to more than %d bones (the GPU keeps %d: the rest is dropped)" % [o4.size(), "" if o4.size() == 1 else "s", MAX_INFL, MAX_INFL],
				"weight paint them down to 4 bones (smooth, then lock and subtract the smallest), or bind again"))
	findings.sort_custom(func(a, b):
		if absf(float(a["pts"]) - float(b["pts"])) > 1e-9:
			return float(a["pts"]) > float(b["pts"])
		if a["kind"] != b["kind"]:
			return KINDS.find(a["kind"]) < KINDS.find(b["kind"])
		return String(a["joint"]) + String(a.get("region", "")) < String(b["joint"]) + String(b.get("region", "")))
	var lost := 0.0
	for f in findings:
		lost += float(f["pts"])
	var jout := []
	for j in jinfo.size():
		if int(jinfo[j]["verts"]) > 0 or int(jinfo[j]["faces"]) > 0:
			jout.append({"name": jinfo[j]["name"], "verts": jinfo[j]["verts"], "faces": jinfo[j]["faces"], "loops": jinfo[j].get("loops", -1)})
	return {"score": clampi(roundi(100.0 - lost), 0, 100), "points": 100.0 - lost, "findings": findings, "formula": FORMULA,
		"joints": jout, "skinned": wr["skinned"], "thin_rays": thin["rays"], "ms": (Time.get_ticks_usec() - t0) / 1000.0}


static func _f(kind: String, joint: String, items: Array, mode: int, pts: float, title: String, next: String) -> Dictionary:
	return {"kind": kind, "joint": joint, "count": items.size(), "items": items, "mode": mode, "pts": pts, "title": title, "next": next}


static func _surface_title(kind: String, n: int) -> String:
	match kind:
		"non_manifold":
			return "%d non-manifold edge%s (3 or more faces on one edge)" % [n, "" if n == 1 else "s"]
		"flipped":
			return "%d edge%s between faces that wind opposite ways (flipped normals)" % [n, "" if n == 1 else "s"]
		"holes":
			return "%d open border edge%s (holes)" % [n, "" if n == 1 else "s"]
		"degenerate":
			return "%d face%s with no area" % [n, "" if n == 1 else "s"]
		"doubled":
			return "%d doubled vert%s (on top of another)" % [n, "" if n == 1 else "s"]
		"loose":
			return "%d loose vert%s (in no face)" % [n, "" if n == 1 else "s"]
		"inside_out":
			return "the mesh is inside out (its normals point in)"
	return "%d %s" % [n, kind]


## the edges walked the same way by both their faces (KMeshValidate's "flipped" rule, as edges)
static func flipped_edges(mesh: KMesh) -> Array:
	var nv := mesh.verts.size()
	var dirc := {}
	var und := {}
	for f in mesh.faces:
		var ff: PackedInt32Array = f
		for i in ff.size():
			var a := ff[i]
			var b := ff[(i + 1) % ff.size()]
			if a == b:
				continue
			dirc[a * nv + b] = int(dirc.get(a * nv + b, 0)) + 1
			var k := mini(a, b) * nv + maxi(a, b)
			und[k] = int(und.get(k, 0)) + 1
	var out := {}
	for k in dirc:
		var a: int = k / nv
		var b: int = k % nv
		if int(dirc[k]) > 1 and int(und[mini(a, b) * nv + maxi(a, b)]) == 2:
			out[Vector2i(mini(a, b), maxi(a, b))] = true
	return out.keys()


## (d) the loops crossing joint jt's bend: the median, over PLANES half-planes through the axis, of the edges of the
## joint's bones that cross the half-plane inside the zone
static func loops_across(mesh: KMesh, wp: PackedVector3Array, lab: PackedFloat32Array, jt: Dictionary) -> int:
	var u: Vector3 = jt["u"]
	var J: Vector3 = jt["at"]
	var zone: float = jt["zone"]
	var e1 := u.cross(Vector3.UP)
	if e1.length() < 0.1:
		e1 = u.cross(Vector3.FORWARD)
	e1 = e1.normalized()
	var e2 := u.cross(e1)
	var bones: Dictionary = jt["bones"]
	var counts := PackedInt32Array()
	counts.resize(PLANES)
	for e in mesh.edges():
		var a: int = e.x
		var b: int = e.y
		if not (bones.has(int(lab[a])) and bones.has(int(lab[b]))):
			continue
		var pa: Vector3 = wp[a] - J
		var pb: Vector3 = wp[b] - J
		var aa := pa.dot(u)
		var ab := pb.dot(u)
		if minf(aa, ab) > zone or maxf(aa, ab) < -zone:
			continue
		var ra := pa - u * aa
		var rb := pb - u * ab
		if ra.length() < 1e-5 or rb.length() < 1e-5:
			continue
		var fa := atan2(ra.dot(e2), ra.dot(e1))
		var dphi := wrapf(atan2(rb.dot(e2), rb.dot(e1)) - fa, -PI, PI)
		if absf(dphi) < 1e-7:
			continue
		for k in PLANES:
			var th := TAU * k / PLANES + PLANE_OFF
			var dl := wrapf(th - fa, -PI, PI)
			var t := dl / dphi
			if t < 0.0 or t > 1.0:
				continue
			var ax := aa + (ab - aa) * t
			if absf(ax) <= zone:
				counts[k] += 1
	var s := Array(counts)
	s.sort()
	return int(s[PLANES / 2 - 1] + s[PLANES / 2]) / 2 if PLANES % 2 == 0 else int(s[PLANES / 2])


## (c) the verts whose inward ray meets the far side within `thick` m: {"verts", "mm" (each one's thickness), "rays"}
static func thin_verts(mesh: KMesh, wp: PackedVector3Array, thick: float) -> Dictionary:
	var tri := PackedInt32Array()   # fan triangles of every face, + the face id
	var tf := PackedInt32Array()
	for fi in mesh.faces.size():
		var f: PackedInt32Array = mesh.faces[fi]
		for i in range(1, f.size() - 1):
			tri.append_array([f[0], f[i], f[i + 1]])
			tf.append(fi)
	var cell := maxf(thick * 2.0, 1e-4)
	var inv := 1.0 / cell
	var grid := {}
	for t in tf.size():
		var a: Vector3 = wp[tri[3 * t]]
		var b: Vector3 = wp[tri[3 * t + 1]]
		var c: Vector3 = wp[tri[3 * t + 2]]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		var i0 := Vector3i(floori(lo.x * inv), floori(lo.y * inv), floori(lo.z * inv))
		var i1 := Vector3i(floori(hi.x * inv), floori(hi.y * inv), floori(hi.z * inv))
		if (i1 - i0).x * (i1 - i0).y * (i1 - i0).z > 4096:
			continue   # a huge triangle (a cap of a big plane): bucketed by its corners' cells only
		for x in range(i0.x, i1.x + 1):
			for y in range(i0.y, i1.y + 1):
				for z in range(i0.z, i1.z + 1):
					var key := Vector3i(x, y, z)
					if grid.has(key):
						(grid[key] as PackedInt32Array).append(t)
					else:
						grid[key] = PackedInt32Array([t])
	var nrm := mesh.vert_normals
	var out := PackedInt32Array()
	var mm := PackedFloat32Array()
	var rays := 0
	for v in mesh.verts.size():
		if mesh.vert_faces(v).is_empty():
			continue
		var n: Vector3 = nrm[v]
		if n.length() < 0.5:
			continue
		var own := {}
		for fi in mesh.vert_faces(v):
			own[fi] = true
		rays += 1
		var wn: Vector3 = _world_normal(mesh, wp, v, n)
		var o: Vector3 = wp[v] - wn * THIN_EPS
		var e: Vector3 = o - wn * thick
		var lo := o.min(e)
		var hi := o.max(e)
		var best := INF
		var seen := {}
		for x in range(floori(lo.x * inv), floori(hi.x * inv) + 1):
			for y in range(floori(lo.y * inv), floori(hi.y * inv) + 1):
				for z in range(floori(lo.z * inv), floori(hi.z * inv) + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key):
						continue
					for t in (grid[key] as PackedInt32Array):
						if seen.has(t) or own.has(tf[t]):
							continue
						seen[t] = true
						var a: Vector3 = wp[tri[3 * t]]
						var b: Vector3 = wp[tri[3 * t + 1]]
						var c: Vector3 = wp[tri[3 * t + 2]]
						var tn := (b - a).cross(c - a)
						if tn.dot(-wn) <= 0.0:
							continue   # faces the ray: not the far side's inside
						# the ray, not the segment: segment_intersects_triangle misses at millimetre scale (its epsilon)
						var hit = SkinPick.ray_tri_mm(o, -wn, a, b, c)
						if hit != null and (hit as Vector3).distance_to(o) <= thick:
							best = minf(best, (hit as Vector3).distance_to(wp[v]))
		if best <= thick:
			out.append(v)
			mm.append(best * 1000.0)
	return {"verts": out, "mm": mm, "rays": rays}


## a vertex normal through the mesh's placement: the world-space corner positions' own normal (Newell over the faces
## round it), so a scaled or turned mesh is measured the way it stands
static func _world_normal(mesh: KMesh, wp: PackedVector3Array, v: int, fallback: Vector3) -> Vector3:
	var acc := Vector3.ZERO
	for fi in mesh.vert_faces(v):
		var f: PackedInt32Array = mesh.faces[fi]
		var n := Vector3.ZERO
		for i in f.size():
			var p: Vector3 = wp[f[i]]
			var q: Vector3 = wp[f[(i + 1) % f.size()]]
			n += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
		if n.length() > 1e-20:
			acc += n.normalized()
	return acc.normalized() if acc.length() > 1e-9 else fallback


## (f): {"skinned", "unweighted": [verts], "over4": [verts]}
static func weight_problems(mesh: KMesh) -> Dictionary:
	var nv := mesh.verts.size()
	var chans := []
	for nm in mesh.list_attrs():
		if String(nm).begins_with(BaseBody.W):
			chans.append(mesh.attr_data(nm))
	var h01: bool = mesh.has_attr(KMeshAutoWeights.CH_BONES) and mesh.has_attr(KMeshAutoWeights.CH_WEIGHTS)
	if chans.is_empty() and not h01:
		return {"skinned": false, "unweighted": [], "over4": []}
	var un := []
	var o4 := []
	var cb: PackedColorArray = mesh.attr_data(KMeshAutoWeights.CH_BONES) if h01 else PackedColorArray()
	var cw: PackedColorArray = mesh.attr_data(KMeshAutoWeights.CH_WEIGHTS) if h01 else PackedColorArray()
	for v in nv:
		var n := 0
		var s := 0.0
		for c in chans:
			var w: float = (c as PackedFloat32Array)[v]
			if w > 0.0:
				n += 1
				s += w
		if h01:
			for q in 4:
				if roundi(cb[v][q]) >= 0 and cw[v][q] > 0.0:
					n += 1
					s += cw[v][q]
		if s <= 1e-6:
			un.append(v)
		elif n > MAX_INFL:
			o4.append(v)
	return {"skinned": true, "unweighted": un, "over4": o4}


## the world points of a finding's elements (for framing)
static func points_of(mesh: KMesh, f: Dictionary, xf: Transform3D) -> PackedVector3Array:
	var vs := {}
	for it in f["items"]:
		match int(f["mode"]):
			SEL_VERT:
				vs[int(it)] = true
			SEL_EDGE:
				vs[(it as Vector2i).x] = true
				vs[(it as Vector2i).y] = true
			SEL_FACE:
				for v in (mesh.faces[int(it)] as PackedInt32Array):
					vs[v] = true
	var out := PackedVector3Array()
	for v in vs:
		out.append(xf * mesh.verts[v])
	return out
