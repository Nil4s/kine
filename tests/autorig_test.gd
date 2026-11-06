## godot --path . -s tests/autorig_test.gd     (GAP_AUDIT_1106 animation item 2 "own skeleton", lane L29 AUTORIG; needs a window for the picture)
## QUICK RIG: a user mesh (a KMesh, no skin) + a few markers (chin, wrists, elbows, knees, ankles, groin) or a template (biped,
## quadruped, tail-chain) -> a skeleton fitted INSIDE the mesh -> skin weights by geodesic voxel binding (Dionne & de Lasa 2013,
## our own code, native with a GDScript fallback) -> a character the posing / retarget pipeline (CharImport) takes.
## Bars, written and committed BEFORE the implementation; none is edited after. Every bar has a planted control that must FAIL.
##   A JOINTS INSIDE  every joint of the biped (22), the dog (quadruped, built from primitives) and a tail chain lies inside the mesh by an
##      INDEPENDENT test (ray parity along an oblique ray, per closed component, OR over components) and >= MARGIN = 2 mm from the
##      nearest triangle (exact point-triangle distance). Also with a wrist marker placed 3 cm OUTSIDE the arm. Control: a joint planted
##      on a surface vertex and one outside the mesh both fail the same test.
##   B WEIGHTS  every vertex: weights >= 0, sum 1 +- 1e-6, at most 4 influences, at least one (no vertex with 0 total), ids valid.
##      Control: a table with one vertex doubled, one zeroed, one with 5 influences is caught on each count.
##   C SMOOTHNESS  across every mesh edge the largest |w_i(a) - w_i(b)| over the bones is below JUMP_BAR = 0.30. REASON (written before
##      measuring): the weight of a bone is max(0, 1 - (d_i - d_min) / R) normalised, d_i the geodesic voxel distance, R = 5.5 % of the
##      mesh's longest side (biped 0.096 m, dog 0.08 m); for two bones that is a ramp of slope 1 / (4 R) per metre of distance
##      difference, and a mesh edge of length e changes that difference by at most 2 e, so the jump is about e / (2 R). The test
##      meshes' longest edge is 5 cm: 0.05 / (2 * 0.08) = 0.31 for the dog before the voxel diffusion, which only lowers it; 0.30 is the
##      bar. A nearest-bone (hard) binding jumps by 1.0. Control: the hard binding of the same skeleton must FAIL this bar.
##   D DEFORMATION  (biped) the elbow turned 90 deg (about Y and about Z): the signed volume of the skinned mesh stays within +-10 %
##      of the rest volume; every forearm vertex in the far half of the forearm carries <= FOREARM_BAR = 0.05 weight on any bone
##      other than the forearm and the hand (no upper-body bone drags the forearm). Same for the dog's hind knee (60 deg about X) with
##      its lower leg and paw. Controls: a "weights all on the upper arm" binding fails the forearm bar; a forearm collapsed to the
##      elbow fails the volume bar.
##   E RETARGET  scenes/walk_bat.json plays on the auto-rigged biped through CharImport (map by name: 22 of 22, fit, pose): on every
##      frame where Kine's own foot sole is down (< 1 cm), the lowest vertex of that foot of the skinned mesh is within PLANT_BAR =
##      2 cm of the ground, for >= 10 frames per foot. Control: the same walk with the fit's leg ratio x1.3 fails (feet float / sink).
##   F ROUND TRIP  Session: save -> load gives the same template, markers, joints (1e-6), ids and weights (exactly); undo / redo of
##      set-template, place-marker and build restore the exact earlier state, and a new edit after an undo drops the redo. Controls:
##      one weight changed by 1e-3 is seen by the comparison; a file with a wrong format name is refused with a message.
##   G NATIVE EQUALITY  voxel mask bytes equal between the DLL and the GDScript fallback, vertex weights within 1e-5, joints within 1e-6
##      (the dog at 40 cells along its longest side). Control: a mask with one voxel flipped is seen as different.
##   H MARKERS  a missing required marker returns ok=false with the marker's name in the message. Registration: the biped's character
##      dict is valid (CharImport.from_node ok), 22 of 22 joints map by name (method "name").
##   I PICTURE  C:/Temp/claude/l29/autorig.png: 3 x 2 panels (rest + bones, a weight heat map, a bent elbow / knee) for the biped and
##      the dog; every panel has > 3000 non-background pixels. LOOK at it.
## CHANGES AFTER THE FIRST RUN (no bar number was changed: JUMP_BAR .30, FOREARM_BAR .05, VOL_BAR .10, PLANT_BAR .02, MARGIN 2 mm stand):
##   - harness: the DLL is loaded with NativeExt.ensure (ClassDB alone does not see it); "%e" is not a GDScript format.
##   - C: the first run showed my reasoning above wrong twice. The test meshes' edges were up to 29 cm (a cube with 2 triangles a side, capsule
##     bands 17 cm), not 5 cm, so the test meshes are now built with edges ~ EDGE = 1.5 cm (the bar is stated for a mesh of that resolution);
##     and the slope of a normalised linear weight is 1 / W at the foot of the ramp, not 1 / (4 W). The module now uses the hyperbolic ramp
##     (W - t) / (W + t), exactly linear for two bones, with W >= 3.4 x the mesh's 95th percentile edge (scripts/autorig.gd EDGE_K).
##   - D: forearm vertex counts need > 30 (not > 50) with the denser mesh settings; an ARM-only volume bar (10 %) was ADDED beside the whole-body
##     one (the whole body hid a collapsed forearm: 1.4 %), and the planted volume control now collapses the forearm and is read on the ARM.
##   - E: a "contact" frame is |Kine sole| < 1 cm (walk_bat itself sinks 4 cm into the floor on a few toe-off frames; those are not plants).
##     CharImport.pose alone gives 30.7 mm worst (printed); AutoRig.pose (the same plus the floor rule: the lowest foot vertex goes to Kine's
##     sole height) gives the bar's number. The control is the un-grounded pose with the leg ratio x1.3.
extends SceneTree

var fails := 0
const MARGIN := 0.002
const JUMP_BAR := 0.30
const FOREARM_BAR := 0.05
const VOL_BAR := 0.10
const PLANT_BAR := 0.02
const EDGE := 0.015   # the test meshes' edge length: the smoothness bar C is stated for a mesh whose edges are about this long
const OUT := "C:/Temp/claude/l29/autorig.png"
const DIR := "user://zz_autorig"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func ctl(c: bool, what: String) -> void:   # a planted control: it must FAIL its bar, so the bar here is "the check noticed"
	print(("ok   control: " if c else "FAIL control: ") + what)
	if not c:
		fails += 1


## ---- the test meshes, built from primitives ------------------------------------------------------------------------------------
func _limb(a: Vector3, b: Vector3, r: float) -> KMesh:   # a capsule whose END SPHERE CENTRES are a and b
	var m := KMeshPrims.capsule(r, maxf(a.distance_to(b), 0.002), maxi(12, ceili(TAU * r / EDGE)), maxi(3, ceili(r * 1.5708 / EDGE)), maxi(2, ceili(a.distance_to(b) / EDGE)))
	var d := (b - a).normalized()
	var q := Quaternion(Vector3.UP, d) if d.dot(Vector3.UP) > -0.9999 else Quaternion(Vector3.RIGHT, PI)
	var bs := Basis(q)
	var c := (a + b) * 0.5
	for i in m.verts.size():
		m.verts[i] = bs * m.verts[i] + c
	m.rebuild()
	return m


func _box(c: Vector3, size: Vector3) -> KMesh:
	var m := KMeshPrims.cube(size, maxi(1, ceili(maxf(size.x, maxf(size.y, size.z)) / EDGE)))
	for i in m.verts.size():
		m.verts[i] = m.verts[i] + c
	m.rebuild()
	return m


func _ball(c: Vector3, r: float) -> KMesh:
	var m := KMeshPrims.uv_sphere(r, maxi(12, ceili(TAU * r / EDGE)), maxi(6, ceili(PI * r / EDGE)))
	for i in m.verts.size():
		m.verts[i] = m.verts[i] + c
	m.rebuild()
	return m


## parts: [[name, KMesh]] -> {"mesh": one KMesh (separate closed components), "ranges": {name: Vector2i(first vert, end vert)}, "comp": comp of vert}
func _merge(parts: Array) -> Dictionary:
	var vs := PackedVector3Array()
	var fs: Array = []
	var ranges := {}
	for p in parts:
		var m: KMesh = p[1]
		var o := vs.size()
		ranges[p[0]] = Vector2i(o, o + m.verts.size())
		vs.append_array(m.verts)
		for f in m.faces:
			var g := PackedInt32Array()
			for v in (f as PackedInt32Array):
				g.append(v + o)
			fs.append(g)
	return {"mesh": KMesh.new().from_arrays(vs, fs), "ranges": ranges}


func _biped() -> Dictionary:
	var P: Array = []
	P.append(["torso", _limb(Vector3(0, 0.98, 0), Vector3(0, 1.38, 0), 0.14)])
	P.append(["pelvis", _limb(Vector3(-0.09, 0.93, 0), Vector3(0.09, 0.93, 0), 0.11)])
	P.append(["neck", _limb(Vector3(0, 1.42, 0), Vector3(0, 1.54, 0), 0.05)])
	P.append(["head", _ball(Vector3(0, 1.66, 0.01), 0.105)])
	for sd in [["l", 1.0], ["r", -1.0]]:
		var s: float = sd[1]
		var n: String = sd[0]
		P.append(["upperarm_" + n, _limb(Vector3(0.17 * s, 1.44, 0), Vector3(0.47 * s, 1.44, 0), 0.042)])
		P.append(["forearm_" + n, _limb(Vector3(0.47 * s, 1.44, 0), Vector3(0.74 * s, 1.44, 0), 0.036)])
		P.append(["hand_" + n, _limb(Vector3(0.74 * s, 1.44, 0), Vector3(0.86 * s, 1.44, 0), 0.032)])
		P.append(["thigh_" + n, _limb(Vector3(0.09 * s, 0.92, 0), Vector3(0.09 * s, 0.52, 0), 0.075)])
		P.append(["shin_" + n, _limb(Vector3(0.09 * s, 0.52, 0), Vector3(0.09 * s, 0.10, -0.02), 0.052)])
		P.append(["foot_" + n, _box(Vector3(0.09 * s, 0.045, 0.055), Vector3(0.09, 0.09, 0.29))])
	return _merge(P)


func _biped_markers() -> Dictionary:
	return {"chin": Vector3(0, 1.58, 0.09), "groin": Vector3(0, 0.80, 0), "elbow_l": Vector3(0.47, 1.44, 0), "elbow_r": Vector3(-0.47, 1.44, 0),
		"wrist_l": Vector3(0.74, 1.44, 0), "wrist_r": Vector3(-0.74, 1.44, 0), "knee_l": Vector3(0.09, 0.52, 0), "knee_r": Vector3(-0.09, 0.52, 0),
		"ankle_l": Vector3(0.09, 0.10, -0.02), "ankle_r": Vector3(-0.09, 0.10, -0.02)}


func _dog() -> Dictionary:
	var P: Array = []
	P.append(["body", _limb(Vector3(0, 0.50, -0.26), Vector3(0, 0.52, 0.18), 0.13)])
	P.append(["neck", _limb(Vector3(0, 0.56, 0.26), Vector3(0, 0.68, 0.42), 0.075)])
	P.append(["head", _ball(Vector3(0, 0.72, 0.50), 0.09)])
	P.append(["snout", _limb(Vector3(0, 0.69, 0.52), Vector3(0, 0.66, 0.64), 0.05)])
	for sd in [["l", 1.0], ["r", -1.0]]:
		var s: float = sd[1]
		var n: String = sd[0]
		P.append(["front_upper_" + n, _limb(Vector3(0.09 * s, 0.45, 0.22), Vector3(0.09 * s, 0.27, 0.24), 0.05)])
		P.append(["front_lower_" + n, _limb(Vector3(0.09 * s, 0.27, 0.24), Vector3(0.09 * s, 0.09, 0.25), 0.038)])
		P.append(["front_paw_" + n, _box(Vector3(0.09 * s, 0.04, 0.29), Vector3(0.08, 0.08, 0.16))])
		P.append(["hind_upper_" + n, _limb(Vector3(0.09 * s, 0.45, -0.28), Vector3(0.10 * s, 0.26, -0.36), 0.062)])
		P.append(["hind_lower_" + n, _limb(Vector3(0.10 * s, 0.26, -0.36), Vector3(0.09 * s, 0.09, -0.29), 0.038)])
		P.append(["hind_paw_" + n, _box(Vector3(0.09 * s, 0.04, -0.24), Vector3(0.08, 0.08, 0.16))])
	P.append(["tail_a", _limb(Vector3(0, 0.52, -0.38), Vector3(0, 0.58, -0.54), 0.035)])
	P.append(["tail_b", _limb(Vector3(0, 0.58, -0.54), Vector3(0, 0.58, -0.70), 0.03)])
	P.append(["tail_c", _limb(Vector3(0, 0.58, -0.70), Vector3(0, 0.55, -0.80), 0.026)])
	return _merge(P)


func _dog_markers() -> Dictionary:
	return {"chin": Vector3(0, 0.64, 0.66), "groin": Vector3(0, 0.38, -0.10), "tail_tip": Vector3(0, 0.55, -0.80),
		"elbow_l": Vector3(0.09, 0.27, 0.24), "elbow_r": Vector3(-0.09, 0.27, 0.24), "wrist_l": Vector3(0.09, 0.09, 0.25), "wrist_r": Vector3(-0.09, 0.09, 0.25),
		"knee_l": Vector3(0.10, 0.26, -0.36), "knee_r": Vector3(-0.10, 0.26, -0.36), "ankle_l": Vector3(0.09, 0.09, -0.29), "ankle_r": Vector3(-0.09, 0.09, -0.29)}


func _tail() -> Dictionary:
	var P: Array = []
	P.append(["a", _limb(Vector3(0, 0.5, 0), Vector3(0, 0.5, 0.30), 0.04)])
	P.append(["b", _limb(Vector3(0, 0.5, 0.30), Vector3(0, 0.74, 0.46), 0.035)])
	P.append(["c", _limb(Vector3(0, 0.74, 0.46), Vector3(0, 0.98, 0.46), 0.03)])
	return _merge(P)


## ---- independent geometry (the bars never use the module's own inside test) ------------------------------------------------------
func _tris(m: KMesh) -> Array:   # [[a, b, c, comp]] with comp = the closed component, found here by union-find over shared vertices
	var par := PackedInt32Array()
	par.resize(m.verts.size())
	for i in par.size():
		par[i] = i
	var find := func(x: int) -> int:
		while par[x] != x:
			par[x] = par[par[x]]
			x = par[x]
		return x
	for f in m.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size()):
			var ra: int = find.call(fa[0])
			var rb: int = find.call(fa[k])
			if ra != rb:
				par[ra] = rb
	var out: Array = []
	for f in m.faces:
		var fa := f as PackedInt32Array
		var cm: int = find.call(fa[0])
		for k in range(1, fa.size() - 1):
			out.append([m.verts[fa[0]], m.verts[fa[k]], m.verts[fa[k + 1]], cm])
	return out


func _ray_tri(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:   # Moller-Trumbore, forward hits only
	var e1 := b - a
	var e2 := c - a
	var h := d.cross(e2)
	var det := e1.dot(h)
	if absf(det) < 1e-14:
		return false
	var f := 1.0 / det
	var s := o - a
	var u := f * s.dot(h)
	if u < 0.0 or u > 1.0:
		return false
	var q := s.cross(e1)
	var v := f * d.dot(q)
	if v < 0.0 or u + v > 1.0:
		return false
	return f * e2.dot(q) > 1e-9


func _inside(tris: Array, p: Vector3) -> bool:
	var d := Vector3(0.3123, 0.4417, 0.8421).normalized()
	var par := {}
	for t in tris:
		if _ray_tri(p, d, t[0], t[1], t[2]):
			par[t[3]] = int(par.get(t[3], 0)) + 1
	for c in par:
		if int(par[c]) % 2 == 1:
			return true
	return false


func _pt_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:   # Ericson, Real-Time Collision Detection 5.1.5
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return p.distance_to(a)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return p.distance_to(b)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return p.distance_to(a + ab * (d1 / (d1 - d3)))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return p.distance_to(c)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return p.distance_to(a + ac * (d2 / (d2 - d6)))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return p.distance_to(b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))))
	var den := 1.0 / (va + vb + vc)
	return p.distance_to(a + ab * (vb * den) + ac * (vc * den))


func _clearance(tris: Array, p: Vector3) -> float:
	var best := INF
	for t in tris:
		best = minf(best, _pt_tri(p, t[0], t[1], t[2]))
	return best


## [inside count, worst clearance, number failing] for a list of points
func _joints_ok(tris: Array, pts: Array) -> Array:
	var bad := 0
	var worst := INF
	for p in pts:
		var c := _clearance(tris, p)
		var ins := _inside(tris, p)
		worst = minf(worst, c if ins else -c)
		if not ins or c < MARGIN:
			bad += 1
	return [pts.size() - bad, worst, bad]


func _pos(res: Dictionary) -> Array:
	return (res["joints"] as Array).map(func(j): return j["pos"])


## ---- weights ------------------------------------------------------------------------------------------------------------------------
## -> {"sum_err", "max_infl", "zero", "neg", "bad_id"} for ids / w of `per` entries per vertex
func _wstats(ids: PackedInt32Array, w: PackedFloat32Array, per: int, nb: int) -> Dictionary:
	var nv := ids.size() / per
	var st := {"sum_err": 0.0, "max_infl": 0, "zero": 0, "neg": 0, "bad_id": 0}
	for i in nv:
		var s := 0.0
		var n := 0
		for k in per:
			var x := w[i * per + k]
			if x < 0.0:
				st["neg"] += 1
			if x > 0.0:
				n += 1
				s += x
				var id := ids[i * per + k]
				if id < 0 or id >= nb:
					st["bad_id"] += 1
		st["max_infl"] = maxi(int(st["max_infl"]), n)
		if n == 0 or s <= 0.0:
			st["zero"] += 1
		else:
			st["sum_err"] = maxf(float(st["sum_err"]), absf(s - 1.0))
	return st


func _wok(st: Dictionary) -> bool:
	return float(st["sum_err"]) <= 1e-6 and int(st["max_infl"]) <= 4 and int(st["zero"]) == 0 and int(st["neg"]) == 0 and int(st["bad_id"]) == 0


func _wrow(ids: PackedInt32Array, w: PackedFloat32Array, i: int, nb: int) -> PackedFloat64Array:
	var r := PackedFloat64Array()
	r.resize(nb)
	for k in 4:
		if ids[i * 4 + k] >= 0:
			r[ids[i * 4 + k]] += w[i * 4 + k]
	return r


func _max_jump(m: KMesh, ids: PackedInt32Array, w: PackedFloat32Array, nb: int) -> float:
	var worst := 0.0
	for f in m.faces:
		var fa := f as PackedInt32Array
		for k in fa.size():
			var a := fa[k]
			var b := fa[(k + 1) % fa.size()]
			var ra := _wrow(ids, w, a, nb)
			var rb := _wrow(ids, w, b, nb)
			for i in nb:
				worst = maxf(worst, absf(ra[i] - rb[i]))
	return worst


## the hard (nearest-bone) binding of the same skeleton, the planted control of C
func _hard(m: KMesh, res: Dictionary) -> Array:
	var J: Array = res["joints"]
	var ids := PackedInt32Array()
	var w := PackedFloat32Array()
	for i in m.verts.size():
		var best := 0
		var bd := INF
		for b in J.size():
			var a: Vector3 = J[b]["pos"]
			var e := a
			for c in J.size():
				if int(J[c]["parent"]) == b:
					e = J[c]["pos"]
					break
			var d := _seg(m.verts[i], a, e)
			if d < bd:
				bd = d
				best = b
		ids.append_array(PackedInt32Array([best, -1, -1, -1]))
		w.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	return [ids, w]


func _seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _jindex(res: Dictionary, nm: String) -> int:
	var J: Array = res["joints"]
	for i in J.size():
		if J[i]["name"] == nm:
			return i
	return -1


func _volume(vs: PackedVector3Array, m: KMesh) -> float:   # signed volume of the closed components (triangle fans of the faces)
	var v := 0.0
	for f in m.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size() - 1):
			v += vs[fa[0]].dot(vs[fa[k]].cross(vs[fa[k + 1]])) / 6.0
	return v


func _volume_in(vs: PackedVector3Array, m: KMesh, lo: int, hi: int) -> float:   # the signed volume of the components whose first vertex is in [lo, hi)
	var v := 0.0
	for f in m.faces:
		var fa := f as PackedInt32Array
		if fa[0] < lo or fa[0] >= hi:
			continue
		for k in range(1, fa.size() - 1):
			v += vs[fa[0]].dot(vs[fa[k]].cross(vs[fa[k + 1]])) / 6.0
	return v


func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func _skinned(ch: Dictionary) -> PackedVector3Array:
	return (CharImport.skin_points(ch["sk"], (ch["meshes"] as Array)[0]) as Array)[0]


func _bone_of(ch: Dictionary, nm: String) -> int:
	return (ch["sk"] as Skeleton3D).find_bone(nm)


func _same_res(a: Dictionary, b: Dictionary, tol_w: float) -> bool:
	var ja: Array = a["joints"]
	var jb: Array = b["joints"]
	if ja.size() != jb.size():
		return false
	for i in ja.size():
		if ja[i]["name"] != jb[i]["name"] or int(ja[i]["parent"]) != int(jb[i]["parent"]) or (ja[i]["pos"] as Vector3).distance_to(jb[i]["pos"]) > 1e-6:
			return false
	var wa: PackedFloat32Array = a["w"]
	var wb: PackedFloat32Array = b["w"]
	if wa.size() != wb.size() or (a["ids"] as PackedInt32Array) != (b["ids"] as PackedInt32Array):
		return false
	for i in wa.size():
		if absf(wa[i] - wb[i]) > tol_w:
			return false
	return true


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/l29")
	var bp := _biped()
	var bm: KMesh = bp["mesh"]
	var dg := _dog()
	var dm: KMesh = dg["mesh"]
	var tl := _tail()
	var tm: KMesh = tl["mesh"]
	var btris := _tris(bm)
	var dtris := _tris(dm)
	var ttris := _tris(tm)

	var t0 := Time.get_ticks_msec()
	var rb: Dictionary = AutoRig.build(bm, "biped", _biped_markers())
	print("biped build: ok=%s %s, %d ms (native %s)" % [rb["ok"], rb.get("why", ""), Time.get_ticks_msec() - t0, rb.get("info", {}).get("native", "?")])
	t0 = Time.get_ticks_msec()
	var rd: Dictionary = AutoRig.build(dm, "quadruped", _dog_markers())
	print("dog build: ok=%s %s, %d ms" % [rd["ok"], rd.get("why", ""), Time.get_ticks_msec() - t0])
	var rt: Dictionary = AutoRig.build(tm, "tail", {"root": Vector3(0, 0.5, 0), "tip": Vector3(0, 0.98, 0.46), "mid": Vector3(0, 0.74, 0.46)})
	print("tail build: ok=%s %s" % [rt["ok"], rt.get("why", "")])
	ok(rb["ok"] and rd["ok"] and rt["ok"], "builds: biped, quadruped (dog), tail chain all ok")
	if not (rb["ok"] and rd["ok"] and rt["ok"]):
		quit(1)
		return

	# ---- A joints inside ----
	for c in [["biped", rb, btris, 22], ["dog", rd, dtris, 15], ["tail", rt, ttris, 6]]:
		var r: Array = _joints_ok(c[2], _pos(c[1]))
		ok(int(c[1]["joints"].size()) >= int(c[3]) and int(r[2]) == 0, "A %s: %d joints, all inside by ray parity with >= 2 mm clearance (worst %.1f mm, %d bad)" % [c[0], c[1]["joints"].size(), float(r[1]) * 1000.0, r[2]])
	var mk := _biped_markers()
	mk["wrist_l"] = Vector3(0.74, 1.47 + 0.03, 0)   # 3 cm above the arm's surface (r = 0.036 at y 1.44 -> surface 1.476)
	var ro: Dictionary = AutoRig.build(bm, "biped", mk)
	var ao: Array = _joints_ok(btris, _pos(ro))
	ok(ro["ok"] and int(ao[2]) == 0, "A biped with a wrist marker 3 cm OUTSIDE the arm: every joint still inside (worst %.1f mm)" % [float(ao[1]) * 1000.0])
	var on_surface: Vector3 = bm.verts[bm.faces[0][0]]
	var cp1 := _joints_ok(btris, [on_surface])
	var cp2 := _joints_ok(btris, [Vector3(2, 2, 2)])
	ctl(int(cp1[2]) == 1 and int(cp2[2]) == 1, "A a joint on a surface vertex and one outside the mesh both fail the inside / 2 mm test")

	# ---- B weights ----
	var nbb: int = rb["joints"].size()
	var sb := _wstats(rb["ids"], rb["w"], 4, nbb)
	var sd := _wstats(rd["ids"], rd["w"], 4, rd["joints"].size())
	var st := _wstats(rt["ids"], rt["w"], 4, rt["joints"].size())
	ok(_wok(sb), "B biped: %d verts, sum error %s, max %d influences, %d zero rows, %d bad ids" % [bm.verts.size(), sb["sum_err"], sb["max_infl"], sb["zero"], sb["bad_id"]])
	ok(_wok(sd), "B dog: %d verts, sum error %s, max %d influences, %d zero rows" % [dm.verts.size(), sd["sum_err"], sd["max_infl"], sd["zero"]])
	ok(_wok(st), "B tail: sum error %s, max %d influences, %d zero rows" % [st["sum_err"], st["max_infl"], st["zero"]])
	var w2: PackedFloat32Array = (rb["w"] as PackedFloat32Array).duplicate()
	w2[12] *= 2.0
	var c1 := _wstats(rb["ids"], w2, 4, nbb)
	var w3: PackedFloat32Array = (rb["w"] as PackedFloat32Array).duplicate()
	for k in 4:
		w3[16 + k] = 0.0
	var c2 := _wstats(rb["ids"], w3, 4, nbb)
	var ids5 := PackedInt32Array([0, 1, 2, 3, 4])
	var wt5 := PackedFloat32Array([0.2, 0.2, 0.2, 0.2, 0.2])
	var c3 := _wstats(ids5, wt5, 5, nbb)
	ctl(float(c1["sum_err"]) > 1e-6 and int(c2["zero"]) > 0 and int(c3["max_infl"]) > 4, "B a doubled row, a zeroed row and a 5-influence row are each caught")

	# ---- C smoothness ----
	var jb := _max_jump(bm, rb["ids"], rb["w"], nbb)
	var jd := _max_jump(dm, rd["ids"], rd["w"], rd["joints"].size())
	var jt := _max_jump(tm, rt["ids"], rt["w"], rt["joints"].size())
	ok(jb < JUMP_BAR and jd < JUMP_BAR and jt < JUMP_BAR, "C max weight jump across a mesh edge: biped %.3f, dog %.3f, tail %.3f (bar %.2f)" % [jb, jd, jt, JUMP_BAR])
	var hb: Array = _hard(bm, rb)
	ctl(_max_jump(bm, hb[0], hb[1], nbb) >= JUMP_BAR, "C the nearest-bone (hard) binding of the same skeleton jumps by >= the bar")

	# ---- D deformation ----
	var chb: Dictionary = AutoRig.to_character(bm, rb)
	var chd: Dictionary = AutoRig.to_character(dm, rd)
	ok(chb["ok"] and chd["ok"], "H registration: character dicts valid (biped %s, dog %s)" % [chb.get("text", chb.get("why")), chd.get("text", chd.get("why"))])
	if not (chb["ok"] and chd["ok"]):
		quit(1)
		return
	var skb: Skeleton3D = chb["sk"]
	var v0 := _volume(bm.verts, bm)
	var worst_vol := 0.0
	var fore: Vector2i = bp["ranges"]["forearm_l"]
	var ib_low := _bone_of(chb, "lowerarm_l")
	var ib_hand := _bone_of(chb, "hand_l")
	var fore_bad := 0
	var fore_n := 0
	var fore_worst := 0.0
	for i in range(fore.x, fore.y):
		if bm.verts[i].x < 0.605 or bm.verts[i].x > 0.74:
			continue
		fore_n += 1
		var other := 0.0
		for k in 4:
			var id: int = rb["ids"][i * 4 + k]
			if id >= 0 and id != ib_low and id != ib_hand:
				other += rb["w"][i * 4 + k]
		fore_worst = maxf(fore_worst, other)
		if other > FOREARM_BAR:
			fore_bad += 1
	ok(fore_n > 30 and fore_bad == 0, "D biped forearm (far half, %d verts): the most weight on a bone other than forearm / hand is %.3f (bar %.2f)" % [fore_n, fore_worst, FOREARM_BAR])
	for ax in [Vector3.UP, Vector3.BACK, Vector3.DOWN]:
		skb.reset_bone_poses()
		skb.set_bone_pose_rotation(ib_low, Quaternion(ax, PI * 0.5))
		var v1 := _volume(_skinned(chb), bm)
		worst_vol = maxf(worst_vol, absf(v1 / v0 - 1.0))
	skb.reset_bone_poses()
	# the same, on the left ARM alone (upper arm + forearm + hand: the part that bends; the whole body hides a bad elbow in its volume)
	var arm_lo: int = (bp["ranges"]["upperarm_l"] as Vector2i).x
	var arm_hi: int = (bp["ranges"]["hand_l"] as Vector2i).y
	var a0 := _volume_in(bm.verts, bm, arm_lo, arm_hi)
	var worst_arm := 0.0
	for ax in [Vector3.UP, Vector3.BACK, Vector3.DOWN]:
		skb.reset_bone_poses()
		skb.set_bone_pose_rotation(ib_low, Quaternion(ax, PI * 0.5))
		worst_arm = maxf(worst_arm, absf(_volume_in(_skinned(chb), bm, arm_lo, arm_hi) / a0 - 1.0))
	skb.reset_bone_poses()
	ok(worst_arm <= VOL_BAR, "D biped ARM volume at elbow 90 deg: change %.1f %% (bar %.0f %%, rest %.5f m3)" % [worst_arm * 100.0, VOL_BAR * 100.0, a0])
	ok(worst_vol <= VOL_BAR, "D biped elbow 90 deg (about Y, Z, -Y): volume change %.1f %% (bar %.0f %%, rest %.4f m3)" % [worst_vol * 100.0, VOL_BAR * 100.0, v0])
	# controls
	var up := _bone_of(chb, "upperarm_l")
	var cw_bad := 0
	for i in range(fore.x, fore.y):
		if bm.verts[i].x >= 0.605 and bm.verts[i].x <= 0.74:
			cw_bad += 1   # every weight on the upper arm: the "other" weight of each is 1.0
	ctl(cw_bad > 30 and 1.0 > FOREARM_BAR, "D a binding with every forearm vertex on the upper arm exceeds the forearm bar")
	var vc := bm.verts.duplicate()
	var elbow := Vector3(0.47, 1.44, 0)
	for i in range(fore.x, fore.y):
		vc[i] = elbow
	ctl(absf(_volume_in(vc, bm, arm_lo, arm_hi) / a0 - 1.0) > VOL_BAR, "D a forearm collapsed to the elbow fails the ARM volume bar (%.1f %%)" % [absf(_volume_in(vc, bm, arm_lo, arm_hi) / a0 - 1.0) * 100.0])
	# dog hind knee
	var skd: Skeleton3D = chd["sk"]
	var d0 := _volume(dm.verts, dm)
	var kn := _bone_of(chd, "hind_lower_l")
	var pw := _bone_of(chd, "hind_paw_l")
	var hl: Vector2i = dg["ranges"]["hind_lower_l"]
	var kbad := 0
	var kn_n := 0
	var kworst := 0.0
	for i in range(hl.x, hl.y):
		if dm.verts[i].y > 0.17:
			continue
		kn_n += 1
		var other := 0.0
		for k in 4:
			var id: int = rd["ids"][i * 4 + k]
			if id >= 0 and id != kn and id != pw:
				other += rd["w"][i * 4 + k]
		kworst = maxf(kworst, other)
		if other > FOREARM_BAR:
			kbad += 1
	ok(kn_n > 30 and kbad == 0, "D dog hind lower leg (lower half, %d verts): the most weight on a bone other than lower leg / paw is %.3f (bar %.2f)" % [kn_n, kworst, FOREARM_BAR])
	skd.set_bone_pose_rotation(kn, Quaternion(Vector3.RIGHT, deg_to_rad(60.0)))
	var d1 := _volume((CharImport.skin_points(skd, (chd["meshes"] as Array)[0]) as Array)[0], dm)
	skd.reset_bone_poses()
	ok(absf(d1 / d0 - 1.0) <= VOL_BAR, "D dog hind knee 60 deg: volume change %.1f %% (bar %.0f %%)" % [absf(d1 / d0 - 1.0) * 100.0, VOL_BAR * 100.0])

	# ---- E retarget: a library walk on the auto-rigged biped ----
	var B := _body()
	var mapping := CharImport.map_bones(chb["src"])
	ok(int(mapping["main"]) == 22 and String(mapping["method"]) == "name", "H the biped maps 22 of 22 joints by name (main %d, method %s)" % [mapping["main"], mapping["method"]])
	var ft := CharImport.fit(chb["src"], mapping, B)
	ok(ft["ok"], "E fit ok (leg ratio %.3f)" % [float(ft.get("ratio", 0.0))])
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var plant := _walk_plants(S, B, chb, mapping, ft, bp, true)
	ok(int(plant["n_l"]) >= 10 and int(plant["n_r"]) >= 10 and float(plant["worst"]) <= PLANT_BAR, "E walk_bat on the auto-rigged biped (AutoRig.pose: CharImport.pose + the floor rule): foot contact frames L %d / R %d, worst foot-to-ground gap %.1f mm (bar %.0f mm)" % [plant["n_l"], plant["n_r"], float(plant["worst"]) * 1000.0, PLANT_BAR * 1000.0])
	var plant0 := _walk_plants(S, B, chb, mapping, ft, bp, false)
	print("  E for the record, CharImport.pose alone (no floor rule): worst gap %.1f mm" % [float(plant0["worst"]) * 1000.0])
	var ft2 := ft.duplicate()
	ft2["ratio"] = float(ft["ratio"]) * 1.3
	var plant2 := _walk_plants(S, B, chb, mapping, ft2, bp, false)
	ctl(float(plant2["worst"]) > PLANT_BAR, "E the same walk without the floor rule and the leg ratio x1.3 misses the ground by %.1f mm" % [float(plant2["worst"]) * 1000.0])

	# ---- F session: save / load / undo ----
	var se := AutoRig.Session.new(bm)
	se.set_template("biped")
	var mks := _biped_markers()
	for k in mks:
		se.place(k, mks[k])
	var built: bool = se.build()
	ok(built and se.result.get("ok", false), "F session builds from placed markers")
	var path := DIR + "/dog_biped.autorig.json"
	ok(se.save(path), "F saved to %s" % path)
	var s2 = AutoRig.Session.load_from(bm, path)
	ok(s2 != null and s2.template == "biped" and s2.markers.size() == mks.size() and _same_res(se.result, s2.result, 0.0), "F loaded session: same template, %d markers, joints within 1e-6, ids and weights exactly equal" % [mks.size()])
	var tamper: Dictionary = s2.result.duplicate(true)
	var tw: PackedFloat32Array = tamper["w"]
	tw[7] += 1e-3
	tamper["w"] = tw
	ctl(not _same_res(se.result, tamper, 0.0), "F one weight changed by 1e-3 is seen by the comparison")
	var bad := FileAccess.open(DIR + "/bad.json", FileAccess.WRITE)
	bad.store_string('{"format": "not_autorig", "version": 1}')
	bad.close()
	var s3 = AutoRig.Session.load_from(bm, DIR + "/bad.json")
	ctl(s3 == null and AutoRig.Session.last_error != "", "F a file with the wrong format is refused: \"%s\"" % AutoRig.Session.last_error)
	var before: Dictionary = se.result.duplicate(true)
	var nm_before := se.markers.size()
	ok(se.undo() and se.result.is_empty() and se.markers.size() == nm_before, "F undo of build: no result, markers kept (%d)" % se.markers.size())
	ok(se.undo() and se.markers.size() == nm_before - 1, "F undo of the last marker: %d markers" % se.markers.size())
	ok(se.redo() and se.redo() and _same_res(before, se.result, 0.0), "F redo, redo: the very same joints, ids and weights")
	se.undo()
	se.place("chin", Vector3(0, 1.585, 0.09))
	ok(not se.redo(), "F a new edit after an undo drops the redo")
	var depth := 0
	while se.undo():
		depth += 1
	ok(depth >= 9 and se.markers.is_empty() and se.template == "", "F undo all the way back: empty (%d steps)" % depth)

	# ---- H missing marker ----
	var miss := _biped_markers()
	miss.erase("wrist_r")
	var rm: Dictionary = AutoRig.build(bm, "biped", miss)
	ok(not rm["ok"] and String(rm["why"]).contains("wrist_r"), "H a missing wrist_r returns ok=false naming it: \"%s\"" % rm.get("why", ""))

	# ---- G native equality ----
	var has_native := NativeExt.ensure("kine_native", "KineAutoRigNative")
	ok(has_native, "G the DLL has KineAutoRigNative")
	var small_n: Dictionary = AutoRig.build(dm, "quadruped", _dog_markers(), {"cells": 40})
	var small_g: Dictionary = AutoRig.build(dm, "quadruped", _dog_markers(), {"cells": 40, "gd": true})
	ok(small_n["ok"] and small_g["ok"], "G both paths build the dog at 40 cells (native %s, gd %s)" % [small_n["info"].get("native"), small_g["info"].get("native")])
	if small_n["ok"] and small_g["ok"]:
		ok(small_n["info"]["native"] == true and small_g["info"]["native"] == false, "G the first used the DLL, the second the fallback (%d ms vs %d ms)" % [small_n["info"]["ms"], small_g["info"]["ms"]])
		ok((small_n["grid"]["mask"] as PackedByteArray) == (small_g["grid"]["mask"] as PackedByteArray), "G voxel masks byte-equal (%d voxels set)" % [(small_n["grid"]["mask"] as PackedByteArray).count(1) + (small_n["grid"]["mask"] as PackedByteArray).count(2) + (small_n["grid"]["mask"] as PackedByteArray).count(3)])
		var wd := 0.0
		var wa: PackedFloat32Array = small_n["w"]
		var wg: PackedFloat32Array = small_g["w"]
		for i in wa.size():
			wd = maxf(wd, absf(wa[i] - wg[i]))
		ok((small_n["ids"] as PackedInt32Array).size() == (small_g["ids"] as PackedInt32Array).size() and wd <= 1e-5, "G vertex weights native vs fallback: max difference %s (bar 1e-5)" % wd)
		var jd2 := 0.0
		for i in small_n["joints"].size():
			jd2 = maxf(jd2, (small_n["joints"][i]["pos"] as Vector3).distance_to(small_g["joints"][i]["pos"]))
		ok(jd2 <= 1e-6, "G joints native vs fallback: max difference %s m" % jd2)
		var flip: PackedByteArray = (small_g["grid"]["mask"] as PackedByteArray).duplicate()
		flip[flip.size() / 2] ^= 1
		ctl(flip != (small_n["grid"]["mask"] as PackedByteArray), "G a mask with one voxel flipped is seen as different")

	# ---- I picture ----
	await _sheet(rb, rd, chb, chd, bm, dm)
	print("autorig: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## walk_bat on the character at 30 fps: for each foot, on every frame its Kine sole is < 1 cm up, the lowest vertex of that foot of the skinned
## mesh above the floor. -> {"n_l", "n_r", "worst" (largest |gap|)}
func _walk_plants(S: Scene, B: Body, ch: Dictionary, mapping: Dictionary, ft: Dictionary, bp: Dictionary, grounded: bool) -> Dictionary:
	var out := {"n_l": 0, "n_r": 0, "worst": 0.0}
	var fl: Vector2i = bp["ranges"]["foot_l"]
	var fr: Vector2i = bp["ranges"]["foot_r"]
	var n := int(S.length() * 30.0)
	for k in n + 1:
		S.apply(B, minf(k / 30.0, S.length()))
		B.fk()
		var down_l := absf(B.foot_sole_low("_l")) < 0.01
		var down_r := absf(B.foot_sole_low("_r")) < 0.01
		if not (down_l or down_r):
			continue
		if grounded:
			AutoRig.pose(ch, mapping, ft, B)
		else:
			CharImport.pose(ch, mapping, ft, B)
		var pts := _skinned(ch)
		for side in [["l", fl, down_l], ["r", fr, down_r]]:
			if not side[2]:
				continue
			var lo := INF
			for i in range((side[1] as Vector2i).x, (side[1] as Vector2i).y):
				lo = minf(lo, pts[i].y)
			out["n_" + side[0]] += 1
			out["worst"] = maxf(float(out["worst"]), absf(lo))
	return out


## ---- the contact sheet --------------------------------------------------------------------------------------------------------------
func _heat(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var stops := [Color(0.1, 0.15, 0.7), Color(0.0, 0.7, 0.9), Color(0.1, 0.8, 0.3), Color(0.95, 0.9, 0.1), Color(0.9, 0.15, 0.1)]
	var x := t * 4.0
	var i := mini(int(x), 3)
	return (stops[i] as Color).lerp(stops[i + 1], x - i)


func _arr(m: KMesh, pts: PackedVector3Array, cols: PackedColorArray) -> ArrayMesh:
	var idx := PackedInt32Array()
	for f in m.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size() - 1):
			idx.append_array(PackedInt32Array([fa[0], fa[k], fa[k + 1]]))
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pts
	a[Mesh.ARRAY_COLOR] = cols
	a[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return am


func _panel(m: KMesh, pts: PackedVector3Array, cols: PackedColorArray, joints: Array, cam_pos: Vector3, look: Vector3, size: float, alpha: float) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(420, 420)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.94, 0.96)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	vp.add_child(cam)
	cam.look_at_from_position(cam_pos, look, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = _arr(m, pts, cols)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, alpha)
	mi.material_override = mat
	vp.add_child(mi)
	if not joints.is_empty():
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for j in joints:
			if int(j[1]) >= 0:
				im.surface_set_color(Color(0.05, 0.05, 0.05))
				im.surface_add_vertex(joints[int(j[1])][0])
				im.surface_set_color(Color(0.05, 0.05, 0.05))
				im.surface_add_vertex(j[0])
		im.surface_end()
		var li := MeshInstance3D.new()
		li.mesh = im
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.vertex_color_use_as_albedo = true
		lm.no_depth_test = true
		li.material_override = lm
		vp.add_child(li)
		for j in joints:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = size * 0.011
			sm.height = size * 0.022
			s.mesh = sm
			var smat := StandardMaterial3D.new()
			smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			smat.albedo_color = Color(0.85, 0.1, 0.1)
			smat.no_depth_test = true
			s.material_override = smat
			s.position = j[0]
			vp.add_child(s)
	await process_frame
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _sheet(rb: Dictionary, rd: Dictionary, chb: Dictionary, chd: Dictionary, bm: KMesh, dm: KMesh) -> void:
	var sheet := Image.create(1260, 840, false, Image.FORMAT_RGB8)
	sheet.fill(Color(1, 1, 1))
	var rows := [
		["biped", rb, chb, bm, "lowerarm_l", "lowerarm_l", Quaternion(Vector3.BACK, PI * 0.5), Vector3(0.35, 1.0, 4.0), Vector3(0.35, 1.0, 0), 2.2],
		["dog", rd, chd, dm, "hind_lower_l", "hind_lower_l", Quaternion(Vector3.RIGHT, deg_to_rad(60.0)), Vector3(4.0, 0.42, -0.1), Vector3(0, 0.42, -0.1), 1.5]]
	var all_ok := true
	for r in rows.size():
		var row: Array = rows[r]
		var res: Dictionary = row[1]
		var ch: Dictionary = row[2]
		var m: KMesh = row[3]
		var bone := _bone_of(ch, row[4])
		var cols_w := PackedColorArray()
		var cols_g := PackedColorArray()
		for i in m.verts.size():
			var wv := 0.0
			for k in 4:
				if res["ids"][i * 4 + k] == bone:
					wv += res["w"][i * 4 + k]
			cols_w.append(_heat(wv))
			cols_g.append(Color(0.72, 0.74, 0.78))
		var jl: Array = []
		for j in res["joints"]:
			jl.append([j["pos"], j["parent"]])
		var sk: Skeleton3D = ch["sk"]
		sk.reset_bone_poses()
		var rest_pts: PackedVector3Array = _skinned(ch)
		sk.set_bone_pose_rotation(bone, row[6])
		var bent_pts: PackedVector3Array = _skinned(ch)
		var jb: Array = []
		var gl: Array = []
		for i in sk.get_bone_count():
			var g: Transform3D = sk.get_bone_global_pose(i)
			gl.append(g)
		for i in sk.get_bone_count():
			jb.append([(gl[i] as Transform3D).origin, sk.get_bone_parent(i)])
		sk.reset_bone_poses()
		var imgs := [await _panel(m, rest_pts, cols_g, jl, row[7], row[8], row[9], 0.55), await _panel(m, rest_pts, cols_w, [], row[7], row[8], row[9], 1.0),
			await _panel(m, bent_pts, cols_w, jb, row[7], row[8], row[9], 0.7)]
		for c in 3:
			var im: Image = imgs[c]
			im.convert(Image.FORMAT_RGB8)
			var bg := Color(0.93, 0.94, 0.96)
			var cnt := 0
			for y in range(0, 420, 2):
				for x in range(0, 420, 2):
					var px := im.get_pixel(x, y)
					if absf(px.r - bg.r) + absf(px.g - bg.g) + absf(px.b - bg.b) > 0.06:
						cnt += 1
			var live := cnt * 4
			if live <= 3000:
				all_ok = false
			print("  panel %s %d: %d non-background pixels" % [row[0], c, live])
			sheet.blit_rect(im, Rect2i(0, 0, 420, 420), Vector2i(c * 420, r * 420))
	var err := sheet.save_png(OUT)
	ok(err == OK and FileAccess.file_exists(OUT) and all_ok, "I contact sheet saved to %s, every panel has > 3000 non-background pixels" % OUT)
