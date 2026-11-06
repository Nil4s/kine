## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/stretchskin_test.gd     (L33 STRETCH-SKIN)
## The skin follows the stretchy limbs and spline chains of L28 (#245), and the exports carry the stretch. Written and committed
## BEFORE the implementation (scripts/stretch_skin.gd); no bar of an existing suite is edited. Every bar has a PLANTED control: the same
## metric on a deliberately broken input must FAIL.
##   A  FIDELITY   stretch 1.3 on the arm (upper arm and forearm, no volume): the skin the viewport draws (CharImport.skin_points of the
##                 pieces, the app's own skeleton pose + mesh) is within 1 mm of the BONE-SCALED reference: every vertex blended from
##                 P_j + G_j * S_j * (v - p0_j) (S_j = the stretch in the bone's own axis, then the blend), computed here from Body's
##                 P / G / p0 and the mesh's weights. Forearm length of its pure-weighted vertices grows 1.3 +-1 %.
##                 CONTROL: the skin with the mesh pass off misses the reference by > 1 mm and its forearm stays 1.0 long.
##   B  VOLUME     the same with the cross scale 1/sqrt(1.3): the cross-section AREA (convex hull of the mid forearm's pure vertices
##                 projected across the bone) ratio is 1/1.3 +-3 %. CONTROL: stretch without the cross scale gives ratio 1.0.
##   C  DEFAULT OFF  the skin input (every bone pose + every piece's vertices) of each scene in scenes/ at 5 times equals the golden
##                 made on the BASE (tests/stretchskin_gen.gd). CONTROL: one digit changed differs; the same pose stretched differs.
##   D  SPINE      a spline chain drives spine_01 / 02 / 03 (SplineChain.drive_body). BAR REGISTERED BEFORE MEASURING: the 4 joints
##                 within 1 mm of the curve; every pure spine skin vertex keeps its distance to the chain: |dist(posed vertex, curve)
##                 - dist(rest vertex, rest bone polyline)| <= 10 mm (a bone is a chord; a 15 cm chord on a 0.5 m radius sags 5.6 mm).
##                 Stretch mode (tip on the last handle, volume on): spine skin within 1 mm of the bone-scaled reference.
##                 CONTROL: the rest skin against the bent curve breaks the 10 mm bar.
##   E  EXPORTS    a scene whose left arm stretches (IK key, stretch 1.5, volume) written as glTF, BVH and USD (per-joint scale keys +
##                 the child offsets), read back by Godot's GLTFDocument, BvhImport and pxr (headless Blender): the stretched bone's
##                 length within 1 mm of the app's, the scale keys decode to the stretch and cross scale (glTF 1e-3, BVH / USD 3e-3).
##                 CONTROL: the same scene exported with the stretch off decodes scale 1.0 and the bar fails.
extends SceneTree

var fails := 0
var m: Node
const BAR := 1e-3
const GEN := "res://tests/stretchskin_gen.gd"
const DIR := "user://zz_stretchskin"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func ctl(c: bool, what: String) -> void:
	print(("ok   control: " if c else "FAIL control: ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


# ------------------------------------------------------------------ the app's skin, read
func joint_map() -> Dictionary:
	var sk: Skeleton3D = m.skel
	var of := {}
	for j in Body.ORDER:
		var bi := sk.find_bone("Head" if j == "head" else j)
		if bi >= 0:
			of[bi] = j
	var out := {}
	for b in sk.get_bone_count():
		var c := b
		while c >= 0 and not of.has(c):
			c = sk.get_bone_parent(c)
		out[b] = of[c] if c >= 0 else "pelvis"
	return out


## per surface, per vertex {Kine joint: weight}
func kine_rows(mi: MeshInstance3D) -> Array:
	var jm := joint_map()
	var out := []
	for surf in CharImport.weights_of(m.skel, mi):
		var rows := []
		for row in surf:
			var d := {}
			for bn in row:
				var j: String = jm[m.skel.find_bone(String(bn))]
				d[j] = float(d.get(j, 0.0)) + float(row[bn])
			rows.append(d)
		out.append(rows)
	return out


var _src: Array = []


## the rest vertices of the piece's surface si: the hidden source mesh's surface with the same bone array
func rest_of(mi: MeshInstance3D, si: int) -> PackedVector3Array:
	if _src.is_empty():
		for x in m.man_root.find_children("*", "MeshInstance3D", true, false):
			var xi := x as MeshInstance3D
			if xi.skin != null and xi.mesh is ArrayMesh and not xi.visible and not String(xi.name).begins_with("piece_"):
				for s2 in (xi.mesh as ArrayMesh).get_surface_count():
					_src.append((xi.mesh as ArrayMesh).surface_get_arrays(s2))
	var bo: PackedInt32Array = (mi.mesh as ArrayMesh).surface_get_arrays(si)[Mesh.ARRAY_BONES]
	for a in _src:
		if (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() == bo.size():   # (the engine re-packs a piece's bone array: the influence count is the key)
			return a[Mesh.ARRAY_VERTEX]
	return PackedVector3Array()


func used_of(mi: MeshInstance3D, si: int) -> Dictionary:
	var idx = (mi.mesh as ArrayMesh).surface_get_arrays(si)[Mesh.ARRAY_INDEX]
	var u := {}
	for v in (idx as PackedInt32Array):
		u[v] = true
	return u


## the bone-scaled reference, written here from Body's P / G / p0: p = sum w_j (P_j + G_j S_j (v - p0_j)), S_j the stretch along the
## bone's own axis (to the stretched child) c across it. scaled = false: S = identity (the plain blend)
func ref_pts(mi: MeshInstance3D, si: int, rows: Array, scaled: bool) -> PackedVector3Array:
	var B: Body = m.B
	var rest := rest_of(mi, si)
	var sc := {}
	if scaled:
		for k in B.stretch:
			var b: String = B.parent[k]
			sc[b] = [((B.p0[k] as Vector3) - (B.p0[b] as Vector3)).normalized(), float(B.stretch[k]), float(B.stretch_cross.get(k, 1.0))]
	var out := PackedVector3Array()
	out.resize(rest.size())
	for i in rest.size():
		var p := Vector3.ZERO
		for j in rows[i]:
			var x: Vector3 = rest[i] - (B.p0[j] as Vector3)
			if sc.has(j):
				var a: Vector3 = sc[j][0]
				x = x * float(sc[j][2]) + a * (a.dot(x) * (float(sc[j][1]) - float(sc[j][2])))
			p += ((B.P[j] as Vector3) + (B.G[j] as Quaternion) * x) * float(rows[i][j])
		out[i] = p
	return out


func worst(parts: Array, scaled: bool) -> float:
	var w := 0.0
	for part in parts:
		var mi: MeshInstance3D = m.pieces[part]
		var rows := kine_rows(mi)
		var got := CharImport.skin_points(m.skel, mi)
		for si in got.size():
			var ref := ref_pts(mi, si, rows[si], scaled)
			var used := used_of(mi, si)
			for v in used:
				w = maxf(w, (got[si][v] as Vector3).distance_to(ref[v]))
	return w


## the pure vertices (weight on `joint` >= thr; the spine bar uses 0.5, the bone that weighs most: no spine vertex weighs 0.8 on one bone) of a piece: [[posed point, rest point] ...]
func pure(part: String, joint: String, thr := 0.999) -> Array:
	var mi: MeshInstance3D = m.pieces[part]
	var rows := kine_rows(mi)
	var got := CharImport.skin_points(m.skel, mi)
	var out := []
	for si in got.size():
		var rest := rest_of(mi, si)
		var used := used_of(mi, si)
		for v in used:
			if float(rows[si][v].get(joint, 0.0)) >= thr:
				out.append([got[si][v], rest[v]])
	return out


## the dominant vertices of a joint over the torso pieces (the triangles of the back are split between several pieces)
func pure_any(joint: String, thr: float) -> Array:
	var out := []
	for part in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "clavicle_l", "clavicle_r"]:
		if m.pieces.has(part):
			out.append_array(pure(part, joint, thr))
	return out


func extent(prs: Array, axis: Vector3) -> float:
	var lo := INF
	var hi := -INF
	for pr in prs:
		var d: float = (pr[0] as Vector3).dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return hi - lo


func area(prs: Array, axis: Vector3, t0: float, t1: float, j: String) -> float:
	var B: Body = m.B
	var a0 := ((B.p0[B.CHILD[j]] as Vector3) - (B.p0[j] as Vector3))
	var L := a0.length()
	var u := a0 / L
	var e1 := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := axis.cross(e1)
	var pts := PackedVector2Array()
	for pr in prs:
		var t: float = ((pr[1] as Vector3) - (B.p0[j] as Vector3)).dot(u) / L
		if t >= t0 and t <= t1:
			pts.append(Vector2((pr[0] as Vector3).dot(e1), (pr[0] as Vector3).dot(e2)))
	var h := Geometry2D.convex_hull(pts)
	var A := 0.0
	for i in h.size() - 1:
		A += h[i].x * h[i + 1].y - h[i + 1].x * h[i].y
	return absf(A) * 0.5


func pose_zero() -> void:
	var B: Body = m.B
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO   # the pelvis at its rest place: a body chain's handles are in the pelvis's rest space
	B.set_stretch({}, {})
	B.fk()
	m._refresh()


func stretch_arm(s: float, vol: bool) -> void:
	var c := 1.0 / sqrt(s)
	m.B.set_stretch({"lowerarm_l": s, "hand_l": s}, {"lowerarm_l": c, "hand_l": c} if vol else {})
	m.B.fk()
	m._refresh()


# ------------------------------------------------------------------ the curve (the test's own evaluator, as splineik_test)
func _bez(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var ab := a.lerp(b, t)
	var bc := b.lerp(c, t)
	var cd := c.lerp(d, t)
	return ab.lerp(bc, t).lerp(bc.lerp(cd, t), t)


func ref_poly(ctrl: Array, n_per := 400) -> PackedVector3Array:
	var out := PackedVector3Array()
	var k := ctrl.size()
	for s in k - 1:
		var p0: Vector3 = ctrl[s]
		var p1: Vector3 = ctrl[s + 1]
		var m0: Vector3 = (ctrl[1] - ctrl[0]) if s == 0 else (ctrl[s + 1] - ctrl[s - 1]) * 0.5
		var m1: Vector3 = (ctrl[k - 1] - ctrl[k - 2]) if s == k - 2 else (ctrl[s + 2] - ctrl[s]) * 0.5
		for i in n_per + (1 if s == k - 2 else 0):
			out.append(_bez(p0, p0 + m0 / 3.0, p1 - m1 / 3.0, p1, float(i) / n_per))
	return out


func dist_poly(p: PackedVector3Array, q: Vector3) -> float:
	var best := INF
	for i in p.size() - 1:
		best = minf(best, Geometry3D.get_closest_point_to_segment(q, p[i], p[i + 1]).distance_to(q))
	return best


# ------------------------------------------------------------------ main
func _init() -> void:
	_main()


func _main() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	var G = load(GEN)
	# C DEFAULT OFF (first: the scenes are loaded here)
	var gold := {}
	for line in FileAccess.get_file_as_string("res://tests/stretchskin_golden.txt").split("\n"):
		var p := line.split(" ")
		if p.size() == 2:
			gold[p[0]] = p[1]
	var now: Dictionary = await G.golden(m, self)
	var diff := 0
	for k in gold:
		if not now.has(k) or now[k] != gold[k]:
			diff += 1
			print("   differs: " + k)
	ok(gold.size() >= 50 and diff == 0, "C default OFF: %d skin-input hashes (bones + piece vertices, scenes x5 times) equal the base golden (%d differ)" % [gold.size(), diff])
	var k0: String = gold.keys()[0]
	var h0: String = gold[k0]
	var h1 := h0.substr(0, 5) + ("0" if h0[5] != "0" else "1") + h0.substr(6)
	ctl(h1 != now[k0], "C a golden with one digit changed differs from the real hash")
	# the first scene at its first time, with the arm stretched, must hash differently
	m._load_scene(G.scene_files()[0])
	await idle(3)
	m.playhead = 0.0
	m.S.apply(m.B, 0.0)
	m.B.fk()
	stretch_arm(1.3, false)
	ctl(G.skin_hash(m) != gold[G.scene_files()[0].get_file() + "@0"], "C the same pose with the arm stretched hashes differently, so the hash can see a stretch")
	# A / B on the plain body
	m.S.ik = {}
	m.S.clips = []
	var parts := ["upperarm_l", "lowerarm_l", "hand_l"]
	pose_zero()
	var e0 := worst(parts, false)
	print("   (info) baseline, no stretch: viewport skin vs the Kine reference: worst %.4f mm" % (e0 * 1000.0))
	ok(e0 < BAR, "A the reference agrees with the unstretched viewport skin within 1 mm (%.4f mm), so the 1 mm bar means something" % (e0 * 1000.0))
	var pf0 := pure("lowerarm_l", "lowerarm_l")
	var u0: Vector3 = ((m.B.P["hand_l"] as Vector3) - (m.B.P["lowerarm_l"] as Vector3)).normalized()
	var len0 := extent(pf0, u0)
	var area0 := area(pf0, u0, 0.35, 0.65, "lowerarm_l")
	stretch_arm(1.3, false)
	var e1 := worst(parts, true)
	ok(e1 <= BAR, "A stretch 1.3: skin within 1 mm of the bone-scaled rest positions (worst %.4f mm)" % (e1 * 1000.0))
	var u1: Vector3 = ((m.B.P["hand_l"] as Vector3) - (m.B.P["lowerarm_l"] as Vector3)).normalized()
	var r_len := extent(pure("lowerarm_l", "lowerarm_l"), u1) / len0
	ok(absf(r_len - 1.3) <= 0.013, "A the skin's forearm is %.4f x its length (want 1.3 +-1 %%, %d pure vertices)" % [r_len, pf0.size()])
	var r_nov := area(pure("lowerarm_l", "lowerarm_l"), u1, 0.35, 0.65, "lowerarm_l") / area0
	ctl(absf(r_nov - 1.0) <= 0.03 and absf(r_nov - 1.0 / 1.3) > 0.03, "B stretch without the cross scale leaves the area ratio at %.3f, not 1/1.3" % r_nov)
	m.stretch_skin.on = false
	m._refresh()
	var e_off := worst(parts, true)
	var r_off := extent(pure("lowerarm_l", "lowerarm_l"), u1) / len0
	ctl(e_off > BAR, "A the mesh pass off misses the bone-scaled reference by %.1f mm (> 1 mm)" % (e_off * 1000.0))
	ctl(absf(r_off - 1.3) > 0.013, "A the mesh pass off leaves the forearm %.3f x long, so the 1.3 bar can fail" % r_off)
	m.stretch_skin.on = true
	stretch_arm(1.3, true)
	var e2 := worst(parts, true)
	ok(e2 <= BAR, "B volume on: skin within 1 mm of the bone-scaled reference (worst %.4f mm)" % (e2 * 1000.0))
	var r_area := area(pure("lowerarm_l", "lowerarm_l"), u1, 0.35, 0.65, "lowerarm_l") / area0
	ok(absf(r_area * 1.3 - 1.0) <= 0.03, "B volume: the forearm's cross-section area is %.4f x (want 1/1.3 = %.4f +-3 %%)" % [r_area, 1.0 / 1.3])
	# D SPINE
	pose_zero()
	var B: Body = m.B
	var joints := ["spine_01", "spine_02", "spine_03", "neck_01"]
	var rest_poly := PackedVector3Array()
	for j in joints:
		rest_poly.append(B.p0[j])
	var ch: Dictionary = SplineChain.make_body(B, joints, 4)
	var ctrl: Array = ch["ctrl"]
	ctrl[1] = (ctrl[1] as Vector3) + Vector3(0, 0, 0.07)
	ctrl[2] = (ctrl[2] as Vector3) + Vector3(0, 0, 0.10)
	ctrl[3] = (ctrl[3] as Vector3) + Vector3(0, 0, 0.04)
	var r := SplineChain.drive_body(B, ch)
	m._refresh()
	var poly := ref_poly(ctrl)
	var wj := 0.0
	for j in joints:
		wj = maxf(wj, dist_poly(poly, B.P[j]))
	ok(wj < BAR, "D spine joints on the curve: worst %.3f mm (bar 1 mm)" % (wj * 1000.0))
	var wd := 0.0
	var wc := 0.0
	var n_pure := 0
	for j in ["spine_01", "spine_02", "spine_03"]:
		for pr in pure_any(j, 0.5):
			n_pure += 1
			var dr := dist_poly(rest_poly, pr[1])
			wd = maxf(wd, absf(dist_poly(poly, pr[0]) - dr))
			wc = maxf(wc, absf(dist_poly(poly, pr[1]) - dr))
	ok(n_pure > 50 and wd <= 0.010, "D spine skin follows the curve: %d pure vertices keep their distance to it within %.2f mm (registered bar 10 mm)" % [n_pure, wd * 1000.0])
	ctl(wc > 0.010, "D the rest skin against the bent curve misses by %.1f mm, so the 10 mm bar can fail" % (wc * 1000.0))
	# stretch mode with volume: the tip on the last handle
	ch["mode"] = "stretch"
	ch["volume"] = true
	ctrl[3] = (ctrl[3] as Vector3) + Vector3(0, 0.05, 0)
	SplineChain.drive_body(B, ch)
	m._refresh()
	var tipd := (B.P["neck_01"] as Vector3).distance_to(ctrl[3])
	var e_sp := worst(["spine_01", "spine_02", "spine_03"], true)
	ok(tipd < BAR and not B.stretch.is_empty(), "D stretch mode: the neck joint is %.3f mm from the last handle, scales %s" % [tipd * 1000.0, str(B.stretch)])
	ok(e_sp <= BAR, "D stretch mode + volume: spine skin within 1 mm of the bone-scaled reference (worst %.4f mm)" % (e_sp * 1000.0))
	m.stretch_skin.on = false
	m._refresh()
	ctl(worst(["spine_01", "spine_02", "spine_03"], true) > BAR, "D the mesh pass off misses the spine reference by > 1 mm")
	m.stretch_skin.on = true
	pose_zero()
	# E EXPORTS
	await _exports()
	print("stretchskin: %d fail" % fails)
	quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ E
func stretch_scene(stretch_on: bool) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	S.ik = {}
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S.apply(B, 0.0)
	var sh: Vector3 = B.P["upperarm_l"]
	var reach: float = ((B.p0["lowerarm_l"] as Vector3) - (B.p0["upperarm_l"] as Vector3)).length() + ((B.p0["hand_l"] as Vector3) - (B.p0["lowerarm_l"] as Vector3)).length()
	var tgt: Vector3 = sh + ((B.P["hand_l"] as Vector3) - sh).normalized() * reach * 1.2
	var key := {"t": 0.0, "target": tgt, "pole": tgt + Vector3(0, 0, 1), "w": 1.0}
	if stretch_on:
		key["stretch"] = 1.5
		key["vol"] = true
	S.ik = {"hand_l": [key]}
	return S


func truth(S: Scene, frames: Array) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var out := {}
	for f in frames:
		S.apply(B, minf(float(f) / float(S.fps), S.length()))
		B.fk()
		var d := {}
		for k in B.stretch:
			d[k] = {"s": float(B.stretch[k]), "c": float(B.stretch_cross.get(k, 1.0)), "len": ((B.P[k] as Vector3) - (B.P[B.parent[k]] as Vector3)).length(),
				"rest": ((B.p0[k] as Vector3) - (B.p0[B.parent[k]] as Vector3))}
		out[f] = d
	return out


## decode (s, c) from a bone's own diagonal scale d (world-rest axes) and the bone's length ratio, for BVH / USD
func decode_world(d: Vector3, ratio: float, a: Vector3) -> Vector2:
	var best := 0
	var av := [absf(a.x), absf(a.y), absf(a.z)]
	for i in 3:
		if av[i] < av[best]:
			best = i
	var a2: float = av[best] * av[best]
	return Vector2(ratio, (d[best] - ratio * a2) / (1.0 - a2))


func _exports() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var frames := [0]
	var Sn := stretch_scene(true)
	var Sf := stretch_scene(false)
	var tn := truth(Sn, frames)
	var tf := truth(Sf, frames)
	ok(not (tn[0] as Dictionary).is_empty() and float(tn[0]["hand_l"]["s"]) > 1.05, "E the test scene stretches the left arm: %s" % str(tn[0].keys()))
	ok((tf[0] as Dictionary).is_empty(), "E the same scene without the stretch key stretches nothing")
	var Bx := Body.new()
	Bx.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	# ---- glTF, read by Godot's GLTFDocument
	for case in [["glTF", true], ["glTF off", false]]:
		var S2: Scene = Sn if case[1] else Sf
		var path := "%s/st_%s.glb" % [DIR, "on" if case[1] else "off"]
		var err := GltfExport.write(S2, Bx, path)
		var res := read_glb(ProjectSettings.globalize_path(path), frames[0], float(S2.fps), tn[0])
		if case[1]:
			ok(err == OK and res["worst_len"] <= BAR and res["worst_s"] <= 1e-3 and res["worst_c"] <= 1e-3 and res["n"] > 0, "E glTF: stretched bone lengths within %.3f mm, scale keys decode s within %.5f, c within %.5f (%d stretched bones)" % [res["worst_len"] * 1000.0, res["worst_s"], res["worst_c"], res["n"]])
		else:
			ctl(res["worst_s"] > 1e-3, "E glTF exported with the stretch off decodes s off by %.3f (bar 1e-3)" % res["worst_s"])
	# ---- BVH, read by BvhImport.parse (the existing importer) and walked here
	for case in [["BVH", true], ["BVH off", false]]:
		var S2: Scene = Sn if case[1] else Sf
		var txt: String = BvhExport.text(S2, Bx)[0]
		var res := read_bvh(txt, frames[0], tn[0])
		if case[1]:
			ok(res["ok"] and res["worst_len"] <= BAR and res["worst_s"] <= 3e-3 and res["worst_c"] <= 3e-3 and res["n"] > 0, "E BVH: stretched bone lengths within %.3f mm, scale channels decode s within %.5f, c within %.5f (%d bones)" % [res["worst_len"] * 1000.0, res["worst_s"], res["worst_c"], res["n"]])
		else:
			ctl(res["worst_s"] > 3e-3 or not res["ok"], "E BVH exported with the stretch off decodes s off by %.3f (bar 3e-3)" % res["worst_s"])
	# ---- USD, read by pxr inside headless Blender
	var bl := find_blender()
	if bl == "":
		ok(false, "E USD: no Blender found (KINE_BLENDER or Program Files) to run the pxr reader")
		return
	var cases := []
	for on in [true, false]:
		var S2: Scene = Sn if on else Sf
		var up := "%s/st_%s.usda" % [DIR, "on" if on else "off"]
		UsdExport.write(S2, Bx, up)
		cases.append({"name": "on" if on else "off", "usda": ProjectSettings.globalize_path(up), "frames": frames, "fps": S2.fps})
	var cf := FileAccess.open(ProjectSettings.globalize_path(DIR + "/cases.json"), FileAccess.WRITE)
	cf.store_string(JSON.stringify(cases))
	cf.close()
	var out := []
	OS.execute(bl, ["-b", "--factory-startup", "--python", ProjectSettings.globalize_path("res://tools/usdstretch_check.py"), "--", ProjectSettings.globalize_path(DIR)], out, true)
	var rep = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(DIR + "/report.json")))
	if rep == null:
		ok(false, "E USD: the pxr reader wrote no report: " + str(out).substr(0, 400))
		return
	for nm in ["on", "off"]:
		var res := read_usd(rep[nm], frames[0], tn[0])
		if nm == "on":
			ok(res["worst_len"] <= BAR and res["worst_s"] <= 3e-3 and res["worst_c"] <= 3e-3 and res["n"] > 0, "E USD (pxr): stretched bone lengths within %.3f mm, scale keys decode s within %.5f, c within %.5f (%d bones)" % [res["worst_len"] * 1000.0, res["worst_s"], res["worst_c"], res["n"]])
		else:
			ctl(res["worst_s"] > 3e-3, "E USD exported with the stretch off decodes s off by %.3f (bar 3e-3)" % res["worst_s"])


func find_blender() -> String:
	var e := OS.get_environment("KINE_BLENDER")
	if e != "" and FileAccess.file_exists(e):
		return e
	var base := "C:/Program Files/Blender Foundation"
	if DirAccess.dir_exists_absolute(base):
		for d in DirAccess.get_directories_at(base):
			var p := "%s/%s/blender.exe" % [base, d]
			if FileAccess.file_exists(p):
				return p
	return ""


func _gworld(sk: Skeleton3D, pos: Dictionary, rot: Dictionary, scl: Dictionary, b: int) -> Transform3D:
	var chain := []
	var c := b
	while c >= 0:
		chain.push_front(c)
		c = sk.get_bone_parent(c)
	var x := Transform3D.IDENTITY
	var cum := Vector3.ONE
	for i in chain:
		var rest := sk.get_bone_rest(i)
		var p: Vector3 = pos.get(i, rest.origin)
		var q: Quaternion = rot.get(i, rest.basis.get_rotation_quaternion())
		var s: Vector3 = scl.get(i, rest.basis.get_scale())
		x = x * Transform3D(Basis(q) * Basis.from_scale(s), p)
	return x


func read_glb(abs: String, frame: int, fps: float, truth_f: Dictionary) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var res := {"worst_len": 9.0, "worst_s": 9.0, "worst_c": 9.0, "n": 0}
	if doc.append_from_file(abs, st) != OK:
		return res
	var node := doc.generate_scene(st)
	var sk: Skeleton3D = node.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
	var anim := ap.get_animation(ap.get_animation_list()[0])
	var t := float(frame) / fps
	var pos := {}
	var rot := {}
	var scl := {}
	for tr in anim.get_track_count():
		var np := String(anim.track_get_path(tr))
		if not ":" in np:
			continue
		var bi := sk.find_bone(np.get_slice(":", 1))
		if bi < 0 or anim.track_get_key_count(tr) == 0:
			continue
		var ki := anim.track_find_key(tr, t, Animation.FIND_MODE_NEAREST)
		var v = anim.track_get_key_value(tr, ki)
		match anim.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				pos[bi] = v
			Animation.TYPE_ROTATION_3D:
				rot[bi] = v
			Animation.TYPE_SCALE_3D:
				scl[bi] = v
	var wl := 0.0
	var ws := 0.0
	var wc := 0.0
	for k in truth_f:
		var kb := sk.find_bone("Head" if k == "head" else k)
		var pb := sk.get_bone_parent(kb)
		var L := (_gworld(sk, pos, rot, scl, kb).origin - _gworld(sk, pos, rot, scl, pb).origin).length()
		wl = maxf(wl, absf(L - float(truth_f[k]["len"])))
		var cum := Vector3.ONE
		var c := pb
		while c >= 0:
			cum *= scl.get(c, Vector3.ONE)
			c = sk.get_bone_parent(c)
		ws = maxf(ws, absf(cum.y - float(truth_f[k]["s"])))
		wc = maxf(wc, absf(cum.x - float(truth_f[k]["c"])))
		res["n"] += 1
	res["worst_len"] = wl
	res["worst_s"] = ws
	res["worst_c"] = wc
	node.free()
	return res


func read_bvh(txt: String, frame: int, truth_f: Dictionary) -> Dictionary:
	var res := {"ok": false, "worst_len": 9.0, "worst_s": 9.0, "worst_c": 9.0, "n": 0}
	var pr := BvhImport.parse(txt)
	if not pr["ok"]:
		return res
	var js: Array = pr["joints"]
	var row: PackedFloat64Array = pr["frames"][frame]
	var idx := {}
	for i in js.size():
		idx[js[i]["name"]] = i
	var W := []
	var Rg := []
	for i in js.size():
		var j: Dictionary = js[i]
		var q := BvhImport.rotation(j, row)
		var off: Vector3 = (j["offset"] as Vector3) + BvhImport.position(j, row)
		if j["parent"] < 0:
			W.append(BvhImport.position(j, row))
			Rg.append(q)
		else:
			W.append((W[j["parent"]] as Vector3) + (Rg[j["parent"]] as Quaternion) * off)
			Rg.append((Rg[j["parent"]] as Quaternion) * q)
	var wl := 0.0
	var ws := 0.0
	var wc := 0.0
	for k in truth_f:
		var ki: int = idx[k]
		var pi: int = js[ki]["parent"]
		var L: float = ((W[ki] as Vector3) - (W[pi] as Vector3)).length()
		wl = maxf(wl, absf(L - float(truth_f[k]["len"])))
		var d := Vector3.ONE
		var chn: Array = js[pi]["channels"]
		for ax in 3:
			var nm: String = ["Xscale", "Yscale", "Zscale"][ax]
			if nm in chn:
				d[ax] = row[int(js[pi]["start"]) + chn.find(nm)]
		var rest: Vector3 = truth_f[k]["rest"]
		var sc := decode_world(d, L / rest.length(), rest.normalized())
		ws = maxf(ws, absf(sc.x - float(truth_f[k]["s"])))
		wc = maxf(wc, absf(sc.y - float(truth_f[k]["c"])))
		res["n"] += 1
	res["ok"] = true
	res["worst_len"] = wl
	res["worst_s"] = ws
	res["worst_c"] = wc
	return res


func read_usd(rep: Dictionary, frame: int, truth_f: Dictionary) -> Dictionary:
	var res := {"worst_len": 9.0, "worst_s": 9.0, "worst_c": 9.0, "n": 0}
	var fr: Dictionary = rep["frames"][str(frame)]
	var names: Array = rep["joints"]
	var par: Array = rep["parents"]
	var pos := {}
	for i in names.size():
		pos[names[i]] = Vector3(fr["pos"][i][0], fr["pos"][i][1], fr["pos"][i][2])
	var wl := 0.0
	var ws := 0.0
	var wc := 0.0
	for k in truth_f:
		var ki := names.find(k)
		var pi: int = par[ki]
		var L: float = (pos[k] as Vector3).distance_to(pos[names[pi]])
		wl = maxf(wl, absf(L - float(truth_f[k]["len"])))
		var cum := Vector3.ONE
		var c := pi
		while c >= 0:
			cum *= Vector3(fr["scale"][c][0], fr["scale"][c][1], fr["scale"][c][2])
			c = par[c]
		var rest: Vector3 = truth_f[k]["rest"]
		var sc := decode_world(cum, L / rest.length(), rest.normalized())
		ws = maxf(ws, absf(sc.x - float(truth_f[k]["s"])))
		wc = maxf(wc, absf(sc.y - float(truth_f[k]["c"])))
		res["n"] += 1
	res["worst_len"] = wl
	res["worst_s"] = ws
	res["worst_c"] = wc
	return res
