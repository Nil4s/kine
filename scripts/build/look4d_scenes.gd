extends RefCounted
## LOOK4D scenes (docs/LOOK4D_DESIGN.md section 3): each returns the Dictionary scripts/build/look4d.gd expects.
## S1 engine, S2 arm + cans, S3 walk, S4 falling rod + balls + wall, S5 camera with a planted overlap, S6 = S1 frozen; plus two test fixtures.
const P13 := preload("res://scripts/build/ch13_parts.gd")
const P16 := preload("res://scripts/build/ch16_parts.gd")
const SC14 := preload("res://scripts/build/ch14_scene.gd")
const N14 := preload("res://scripts/build/ch14_anim.gd")
const AN := preload("res://scripts/build/assembly_anim.gd")
const KCad := preload("res://scripts/kcad.gd")
const SCENES := ["s1_engine", "s2_arm", "s3_walk", "s4_fall", "s5_camera", "s6_null"]
const GRAV := 9.81


static func by_name(nm: String) -> Dictionary:
	match nm:
		"s1_engine": return engine(false)
		"s2_arm": return arm()
		"s3_walk": return walk()
		"s4_fall": return fall()
		"s5_camera": return camera()
		"s6_null": return engine(true)
	return {}


static func mat(c: Color, metal := 0.0, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


static func nominal_mass(mi: MeshInstance3D, density := 2700.0, fill := 0.3) -> float:
	var s := mi.mesh.get_aabb().size
	return fill * s.x * s.y * s.z * density


# ---------------------------------------------------------------- Assembly scenes
static func _id(p: Dictionary) -> String:
	return String(p.get("name", p["id"])).strip_edges().replace(" ", "_").to_lower()


## pairs of an assembly's parts at the poses xfs {part id: Transform3D}: [{a, b, gap_mm, pen_mm3}] for every pair within 2 mm (exact solids, KCad.distance and overlap_volume)
static func asm_contacts(asm: Dictionary, xfs: Dictionary) -> Array:
	var sol := {}
	var boxes := {}
	for p in asm["parts"]:
		var pid := String(p["id"])
		var ids: Array = Part.replay(p["rec"], -1, {"keep": true, "errors_only": true}).get("ids", [])
		sol[pid] = AssemblyMotion._place_all(ids, xfs[pid])
		Part.release_kept(ids)
		var first := true
		var box := AABB()
		for s in sol[pid]:
			var b := KCad.bounds_aabb(int(s))
			box = b if first else box.merge(b)
			first = false
		boxes[pid] = box.grow(0.002)
	var out: Array = []
	var ps: Array = asm["parts"]
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			var a := String(ps[i]["id"])
			var b := String(ps[j]["id"])
			if not (boxes[a] as AABB).intersects(boxes[b]):
				continue
			var dmin := INF
			var ov := 0.0
			for sa in sol[a]:
				for sb in sol[b]:
					var d: Dictionary = KCad.distance(int(sa), int(sb))
					if bool(d.get("ok", false)):
						dmin = minf(dmin, float(d["d"]))
					ov += maxf(0.0, float(KCad.overlap_volume(int(sa), int(sb))))
			if dmin * 1000.0 <= 2.0 or ov > 1e-12:
				out.append({"a": _id(ps[i]), "b": _id(ps[j]), "gap_mm": (0.0 if dmin == INF else dmin * 1000.0), "pen_mm3": ov * 1e9})
	for pid in sol:
		for s in sol[pid]:
			KCad.release(int(s))
	return out


static func _asm_scene(nm: String, asm: Dictionary, posefn: Callable, cam: Dictionary, t0: float, h: float, extra := {}) -> Dictionary:
	var cur := {}
	var sc := {"name": nm, "ids": [], "t0": t0, "h": h, "camera": cam}
	for p in asm["parts"]:
		(sc["ids"] as Array).append(_id(p))
	sc["build"] = func(world: Node3D) -> void:
		var i := 0
		for p in asm["parts"]:
			var mi := MeshInstance3D.new()
			mi.name = _id(p)
			mi.mesh = Assembly.built(p["rec"])["mesh"]
			world.add_child(mi)
			(sc["nodes"] as Dictionary)[_id(p)] = mi
			(sc["mass"] as Dictionary)[_id(p)] = nominal_mass(mi)
			i += 1
	sc["set_time"] = func(t: float) -> void:
		var r: Dictionary = posefn.call(t)
		cur.clear()
		cur.merge(r)
		for p in asm["parts"]:
			((sc["nodes"] as Dictionary)[_id(p)] as MeshInstance3D).transform = cur[String(p["id"])]
	sc["contacts"] = func() -> Array:
		return asm_contacts(asm, cur)
	for k in extra:
		sc[k] = extra[k]
	return sc


static func engine(frozen: bool) -> Dictionary:
	var asm := P13.loop_assembly()
	AN.set_key(asm, "Crank", 0.0, 0.0, "linear")
	AN.set_key(asm, "Crank", 2.0, 720.0, "linear")
	asm["anim"]["fps"] = 30
	var t0 := 0.6
	var posefn := func(t: float) -> Dictionary:
		var tt := t0 if frozen else clampf(t, 0.0, 2.0)
		var pa: Dictionary = AN.pose_at(asm, tt)
		var mv: Dictionary = pa["moves"]
		var out := {}
		for p in asm["parts"]:
			var pid := String(p["id"])
			out[pid] = (mv[pid] as Transform3D) * Assembly.xf_of(p) if mv.has(pid) else Assembly.xf_of(p)
		return out
	var cam := {"pos": Vector3(0.45, 0.35, 0.55), "look": Vector3(0.0, 0.05, 0.04), "fov": 38.0}
	return _asm_scene("s6_null" if frozen else "s1_engine", asm, posefn, cam, t0, 0.06, {"kind": "null" if frozen else "motion"})


static func camera() -> Dictionary:
	var asm := P16.assembly({"pcb_into_shell": true})
	var posefn := func(_t: float) -> Dictionary:
		var out := {}
		for p in asm["parts"]:
			out[String(p["id"])] = Assembly.xf_of(p)
		return out
	var cam := {"pos": Vector3(0.14, 0.09, 0.2), "look": Vector3(0.0, 0.0, 0.0), "fov": 34.0}
	return _asm_scene("s5_camera", asm, posefn, cam, 0.0, 0.1, {"kind": "static"})


# ---------------------------------------------------------------- S2 the arm
static func arm() -> Dictionary:
	var holder := {}
	var sc := {"name": "s2_arm", "ids": [], "camera": {"pos": Vector3(0.55, 0.45, 0.75), "look": Vector3(0.1, 0.12, 0.0), "fov": 38.0}, "h": 0.25, "t0": 1.0, "own_env": true, "kind": "motion"}
	sc["build"] = func(world: Node3D) -> void:
		var s14: Dictionary = SC14.build(world)
		holder["s"] = s14
		var seen := {}
		var stack: Array = [s14["root"]]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var nm := String(n.name)
				var k := 2
				var base := nm
				while seen.has(nm):
					nm = "%s_%d" % [base, k]
					k += 1
				seen[nm] = true
				(sc["nodes"] as Dictionary)[nm] = n
				(sc["mass"] as Dictionary)[nm] = nominal_mass(n as MeshInstance3D)
				(sc["ids"] as Array).append(nm)
		# t0: the instant a can is held and the turntable turns fastest
		var d: Dictionary = s14["d"]
		var best := -1.0
		var tb := 1.0
		var tt := 0.0
		while tt < N14.t_end(s14) - 0.1:
			var a: Dictionary = N14.state(d, s14["wp"], tt)
			var b: Dictionary = N14.state(d, s14["wp"], tt + 0.1)
			if int(a["held"]) >= 0:
				var sp := absf(float(b["yaw"]) - float(a["yaw"])) + absf(float(b["th1"]) - float(a["th1"])) if a.has("th1") and b.has("th1") else 0.0
				if sp > best:
					best = sp
					tb = tt
			tt += 0.1
		sc["t0"] = tb + 0.05
	sc["set_time"] = func(t: float) -> void:
		SC14.pose(holder["s"], clampf(t, 0.0, N14.t_end(holder["s"])))
	sc["contacts"] = func() -> Array:
		return box_contacts(sc)
	return sc


## world-box gap between every pair of nodes (S2 has no solids at the node level): pairs within 2 mm
static func box_contacts(sc: Dictionary) -> Array:
	var out: Array = []
	var ids_a: Array = sc["ids"]
	var bx := {}
	for id in ids_a:
		var n := sc["nodes"][id] as MeshInstance3D
		if n.is_visible_in_tree():
			bx[id] = n.global_transform * n.mesh.get_aabb()
	var ks: Array = bx.keys()
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			var g := box_gap(bx[ks[i]], bx[ks[j]])
			if g <= 0.002:
				out.append({"a": ks[i], "b": ks[j], "gap_mm": maxf(g, 0.0) * 1000.0, "pen_mm3": 0.0})
	return out


static func box_gap(a: AABB, b: AABB) -> float:
	var s := 0.0
	var inside := true
	var pen := INF
	for ax in 3:
		var lo := maxf(a.position[ax], b.position[ax])
		var hi := minf(a.end[ax], b.end[ax])
		if lo > hi:
			s += (lo - hi) * (lo - hi)
			inside = false
		else:
			pen = minf(pen, hi - lo)
	return sqrt(s) if not inside else -pen


# ---------------------------------------------------------------- S3 the walk
static func walk() -> Dictionary:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var B := EventQuery._new_body()
	var holder := {"caps": {}}
	var sc := {"name": "s3_walk", "ids": [], "camera": {"pos": Vector3(2.2, 1.1, 2.6), "look": Vector3(0.0, 0.8, 0.0), "fov": 36.0}, "h": 0.1, "t0": 1.0, "kind": "motion"}
	S.apply(B, 0.0)
	var parts: Array = []
	for part in B.rad.keys():
		if String(part).begins_with("wep2"):
			continue
		var c: Variant = B.cap(String(part))
		if c is Array and (c as Array).size() == 2 and (c[0] as Vector3).is_finite() and (c[1] as Vector3).is_finite():
			parts.append(String(part))
	parts.sort()
	sc["ids"] = parts.duplicate()
	(sc["ids"] as Array).append("floor")
	# t0: two frames after the first heel strike after 0.3 s
	var prev := false
	var tt := 0.3
	var t0 := 1.0
	while tt < S.length():
		S.apply(B, tt)
		var bits := (1 if EventQuery.foot_down(B, "_l") else 0) | (2 if EventQuery.foot_down(B, "_r") else 0)
		if bits != 0 and not prev and tt > 0.5:
			t0 = tt + 2.0 / 30.0
			break
		prev = bits != 0
		tt += 1.0 / 30.0
	sc["t0"] = t0
	sc["build"] = func(world: Node3D) -> void:
		S.apply(B, 0.0)
		for part in parts:
			var c: Array = B.cap(part)
			var r: float = B.rad[part]
			var ln := ((c[1] as Vector3) - (c[0] as Vector3)).length()
			var mesh := CapsuleMesh.new()
			mesh.radius = r
			mesh.height = maxf(ln + 2.0 * r, 2.0 * r + 1e-4)
			var col := Color(0.35, 0.55, 0.9) if part.ends_with("_l") else (Color(0.95, 0.55, 0.2) if part.ends_with("_r") else Color(0.7, 0.7, 0.72))
			mesh.material = mat(col)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = part
			world.add_child(mi)
			(sc["nodes"] as Dictionary)[part] = mi
			(sc["mass"] as Dictionary)[part] = 1000.0 * (PI * r * r * ln + 4.0 / 3.0 * PI * r * r * r)
		var fl := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(8.0, 0.02, 8.0)
		bm.material = mat(Color(0.82, 0.8, 0.76))
		fl.mesh = bm
		fl.position = Vector3(0, -0.01, 0)
		fl.name = "floor"
		world.add_child(fl)
		(sc["nodes"] as Dictionary)["floor"] = fl
		(sc["mass"] as Dictionary)["floor"] = 1000.0
	sc["set_time"] = func(t: float) -> void:
		S.apply(B, clampf(t, 0.0, S.length()))
		for part in parts:
			var c: Array = B.cap(part)
			var a: Vector3 = c[0]
			var b: Vector3 = c[1]
			var mi := (sc["nodes"] as Dictionary)[part] as MeshInstance3D
			var d := b - a
			var basis := Basis()
			if d.length() > 1e-6:
				basis = Basis(Quaternion(Vector3.UP, d.normalized()))
			mi.transform = Transform3D(basis, (a + b) * 0.5)
			(holder["caps"] as Dictionary)[part] = [a, b, float(B.rad[part])]
	sc["shapes"] = func() -> Dictionary:
		var o := {}
		for part in parts:
			var c: Array = holder["caps"][part]
			o[part] = {"k": "capsule", "a": [c[0].x, c[0].y, c[0].z], "b": [c[1].x, c[1].y, c[1].z], "r": c[2]}
		o["floor"] = {"k": "aabb", "min": [-4.0, -0.02, -4.0], "max": [4.0, 0.0, 4.0]}
		return o
	sc["contacts"] = func() -> Array:
		var out: Array = []
		for part in parts:
			var c: Array = holder["caps"][part]
			var low := minf((c[0] as Vector3).y, (c[1] as Vector3).y) - float(c[2])
			if low <= 0.01:
				out.append({"a": part, "b": "floor", "gap_mm": maxf(low, 0.0) * 1000.0, "pen_mm3": 0.0})
		return out
	return sc


# ---------------------------------------------------------------- S4 the fall
static func _ball_track(p0: Vector3, v0: Vector3, r: float, e: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var p := p0
	var v := v0
	var dt := 1.0 / 240.0
	for i in 720:
		out.append(p)
		v.y -= GRAV * dt
		p += v * dt
		if p.y < r:
			p.y = r
			v.y = -v.y * e
	return out


static func fall() -> Dictionary:
	var body := RigidDrop.sword_body()
	var sim := RigidDrop.simulate(Vector3(-0.35, 1.0, 0.0), Quaternion(Vector3(0, 0, 1), deg_to_rad(25.0)), Vector3(0.5, 0.0, 0.35), Vector3(0.0, 0.0, 2.0), body)
	var tracks := {
		"ball_a": _ball_track(Vector3(-0.9, 0.35, -1.6), Vector3(0.55, 1.6, 1.9), 0.1, 0.6),
		"ball_b": _ball_track(Vector3(0.75, 0.25, 0.9), Vector3(-0.2, 1.4, -1.1), 0.08, 0.6)}
	var rad := {"ball_a": 0.1, "ball_b": 0.08}
	var statics := {"wall": [Vector3(0.45, 0.35, 0.1), Vector3(0.8, 0.7, 0.08)], "crate": [Vector3(-0.7, 0.14, 0.45), Vector3(0.28, 0.28, 0.28)], "floor": [Vector3(0, -0.01, 0), Vector3(8, 0.02, 8)]}
	var cur := {}
	var sc := {"name": "s4_fall", "ids": ["rod", "ball_a", "ball_b", "wall", "crate", "floor"], "t0": 0.55, "h": 0.05, "kind": "motion",
		"camera": {"pos": Vector3(0.5, 0.95, 2.6), "look": Vector3(0.0, 0.4, 0.0), "fov": 40.0}}
	sc["build"] = func(world: Node3D) -> void:
		var rod := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = float(body["R"])
		cm.height = float(body["L"])
		cm.material = mat(Color(0.75, 0.2, 0.2), 0.3, 0.4)
		rod.mesh = cm
		world.add_child(rod)
		(sc["nodes"] as Dictionary)["rod"] = rod
		(sc["mass"] as Dictionary)["rod"] = float(body["m"])
		var cols := {"ball_a": Color(0.2, 0.5, 0.9), "ball_b": Color(0.2, 0.75, 0.35)}
		for nm in rad:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = float(rad[nm])
			sm.height = 2.0 * float(rad[nm])
			sm.material = mat(cols[nm])
			mi.mesh = sm
			world.add_child(mi)
			(sc["nodes"] as Dictionary)[nm] = mi
			(sc["mass"] as Dictionary)[nm] = 4.0 / 3.0 * PI * pow(float(rad[nm]), 3) * 800.0
		var scol := {"wall": Color(0.55, 0.5, 0.45), "crate": Color(0.7, 0.55, 0.3), "floor": Color(0.85, 0.83, 0.8)}
		for nm in statics:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = statics[nm][1]
			bm.material = mat(scol[nm])
			mi.mesh = bm
			mi.position = statics[nm][0]
			world.add_child(mi)
			(sc["nodes"] as Dictionary)[nm] = mi
			(sc["mass"] as Dictionary)[nm] = 1000.0 * bm.size.x * bm.size.y * bm.size.z * 0.1
	sc["set_time"] = func(t: float) -> void:
		var tc := clampf(t, 0.0, 2.9)
		var xf := RigidDrop.pose_at(sim["poses"], tc)
		((sc["nodes"] as Dictionary)["rod"] as MeshInstance3D).transform = Transform3D(xf.basis * Basis(Vector3(0, 0, 1), PI / 2.0), xf.origin)
		cur["rod"] = xf
		for nm in tracks:
			var tr: PackedVector3Array = tracks[nm]
			var f := clampf(tc * 240.0, 0.0, 718.0)
			var k := int(floor(f))
			var p := tr[k].lerp(tr[k + 1], f - float(k))
			((sc["nodes"] as Dictionary)[nm] as MeshInstance3D).position = p
			cur[nm] = p
	sc["shapes"] = func() -> Dictionary:
		var o := {}
		var xf: Transform3D = cur["rod"]
		var ax := xf.basis.x.normalized()
		var half := float(body["L"]) * 0.5 - float(body["R"])
		var a := xf.origin - ax * half
		var b := xf.origin + ax * half
		o["rod"] = {"k": "capsule", "a": [a.x, a.y, a.z], "b": [b.x, b.y, b.z], "r": float(body["R"])}
		for nm in rad:
			var p: Vector3 = cur[nm]
			o[nm] = {"k": "sphere", "c": [p.x, p.y, p.z], "r": float(rad[nm])}
		for nm in statics:
			var c: Vector3 = statics[nm][0]
			var s: Vector3 = statics[nm][1]
			var lo := c - s * 0.5
			var hi := c + s * 0.5
			o[nm] = {"k": "aabb", "min": [lo.x, lo.y, lo.z], "max": [hi.x, hi.y, hi.z]}
		return o
	sc["contacts"] = func() -> Array:
		var out: Array = []
		var sh: Dictionary = (sc["shapes"] as Callable).call()
		var ids_a: Array = sc["ids"]
		for i in ids_a.size():
			for j in range(i + 1, ids_a.size()):
				var g := shape_gap(sh[ids_a[i]], sh[ids_a[j]])
				if g <= 0.005 and not (statics.has(ids_a[i]) and statics.has(ids_a[j])):
					out.append({"a": ids_a[i], "b": ids_a[j], "gap_mm": maxf(g, 0.0) * 1000.0, "pen_mm3": 0.0})
		return out
	return sc


# ---------------------------------------------------------------- shape gaps (metres; negative = overlapping)
static func _v(a: Variant) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _seg_pt(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


static func _pt_box(p: Vector3, lo: Vector3, hi: Vector3) -> float:
	var q := Vector3(maxf(maxf(lo.x - p.x, 0.0), p.x - hi.x), maxf(maxf(lo.y - p.y, 0.0), p.y - hi.y), maxf(maxf(lo.z - p.z, 0.0), p.z - hi.z))
	return q.length()


static func shape_gap(a: Dictionary, b: Dictionary) -> float:
	var ka := String(a["k"])
	var kb := String(b["k"])
	if ka == "aabb" and kb == "aabb":
		return box_gap(AABB(_v(a["min"]), _v(a["max"]) - _v(a["min"])), AABB(_v(b["min"]), _v(b["max"]) - _v(b["min"])))
	if kb == "aabb" and ka != "aabb":
		return shape_gap(b, a)
	if ka == "aabb":
		var lo := _v(a["min"])
		var hi := _v(a["max"])
		if kb == "sphere":
			return _pt_box(_v(b["c"]), lo, hi) - float(b["r"])
		var best := INF
		for i in 21:
			best = minf(best, _pt_box(_v(b["a"]).lerp(_v(b["b"]), i / 20.0), lo, hi))
		return best - float(b["r"])
	if ka == "sphere" and kb == "sphere":
		return (_v(a["c"]) - _v(b["c"])).length() - float(a["r"]) - float(b["r"])
	if ka == "sphere":
		return (_v(a["c"]) - _seg_pt(_v(b["a"]), _v(b["b"]), _v(a["c"]))).length() - float(a["r"]) - float(b["r"])
	if kb == "sphere":
		return shape_gap(b, a)
	var best2 := INF
	for i in 21:
		var p := _v(a["a"]).lerp(_v(a["b"]), i / 20.0)
		best2 = minf(best2, (p - _seg_pt(_v(b["a"]), _v(b["b"]), p)).length())
	return best2 - float(a["r"]) - float(b["r"])


# ---------------------------------------------------------------- test fixtures
## one sphere (radius 0.1) moving at the constant velocity v from x0: pose x0 + v t. Optional second still sphere
static func ball(x0: Vector3, v: Vector3, cam_pos := Vector3(0, 0.3, 3.0)) -> Dictionary:
	var sc := {"name": "fixture_ball", "ids": ["ball"], "t0": 1.0, "h": 0.1, "kind": "motion", "camera": {"pos": cam_pos, "look": Vector3(0, 0, 0), "fov": 40.0}}
	sc["build"] = func(world: Node3D) -> void:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		sm.material = mat(Color(0.2, 0.5, 0.9))
		mi.mesh = sm
		world.add_child(mi)
		(sc["nodes"] as Dictionary)["ball"] = mi
		(sc["mass"] as Dictionary)["ball"] = 2.0
	sc["set_time"] = func(t: float) -> void:
		((sc["nodes"] as Dictionary)["ball"] as MeshInstance3D).position = x0 + v * t
	sc["contacts"] = func() -> Array:
		return []
	return sc


## boxes: "front" (0.5 cube at the origin, nearest the camera), "behind" (0.2 cube straight behind it: fully hidden), "side" (0.2 cube, visible, to the right),
## "gone" (0.2 cube far to the left, outside the picture)
static func occl() -> Dictionary:
	var spec := {"front": [Vector3(0, 0, 0.5), Vector3(0.5, 0.5, 0.5)], "behind": [Vector3(0, 0, -0.6), Vector3(0.2, 0.2, 0.2)], "side": [Vector3(0.9, 0, 0), Vector3(0.2, 0.2, 0.2)], "gone": [Vector3(-9.0, 0, 0), Vector3(0.2, 0.2, 0.2)]}
	var sc := {"name": "fixture_occl", "ids": spec.keys(), "t0": 0.0, "h": 0.1, "kind": "static", "camera": {"pos": Vector3(0, 0, 4.0), "look": Vector3(0, 0, 0), "fov": 40.0}}
	sc["build"] = func(world: Node3D) -> void:
		for nm in spec:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = spec[nm][1]
			bm.material = mat(Color(0.6, 0.6, 0.65))
			mi.mesh = bm
			mi.position = spec[nm][0]
			world.add_child(mi)
			(sc["nodes"] as Dictionary)[nm] = mi
			(sc["mass"] as Dictionary)[nm] = 1.0
	sc["set_time"] = func(_t: float) -> void:
		pass
	sc["contacts"] = func() -> Array:
		return []
	return sc
