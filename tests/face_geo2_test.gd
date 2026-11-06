## godot --path . -s tests/face_geo2_test.gd     (L18 FACE2: the polish of the face geometry after the reviewer LOOKed at the 3x3 AU sheet and the
## in-app shot of PR #231. Needs a window: :w. tests/face_geo_test.gd (40 bars) is untouched; this is a NEW file.)
## Bars written BEFORE the implementation and committed first (they fail on the base). Each has a PLANTED CONTROL: the same checker on a
## deliberately wrong input must say FAIL, so a checker that cannot fail cannot pass here.
##  R  RIM / BLEND (finding 1: "the mask reads as a separate bright plate with a stair-stepped rim"). Cause found: the mask's vertex
##     colours are in linear space by default in Godot, the head's albedo in sRGB, so the same number drew brighter on the mask.
##     R1 the mask material IS the head's (roughness, metallic, shading), vertex colours read as sRGB, and the vertex colour at the rim
##        is the head's colour. R2 RENDER: the colour difference (CIE76 dE, Lab) between the picture 5 mm outside and 5 mm inside the
##        rim, mean over the rim samples <= 3.0 and the 90th percentile <= 6.0 (dE 2.3 is one just-noticeable difference). The lower
##        rim is carried by the jaw and the head under it is cut away (cut_head), so only the samples that have head behind them count
##        (>= 40 % of the rim). R3 RIM CURVE: the turning angle between successive rim edges in the face plane: max <= 20 deg and the
##        95th percentile <= 8 deg (a circle of 55 mm sampled at 1 mm turns 1 deg; a lattice staircase turns 45-90 deg at each step).
##        R4 FEATHER: the mask's height above the head's real surface is 0 +- 0.6 mm at the rim and rises by at most 0.35 mm per
##        lattice layer (a smooth ramp, no step). CONTROLS: R1 vertex colours x1.3 (a bright plate); R2 the mask drawn with albedo x1.3;
##        R3 and R4 the same build with the staircase / no feather switched off (opts smooth_rim / feather = false).
##  M  MOUTH (finding 2: "AU26 is a hard black box with a flat upper edge"). Outline of the opening (the mouth boundary loop, front
##     view, AU26 = 1 and a 20 deg jaw): solidity = area / convex hull >= 0.93, area / bounding box <= 0.85 (a box is 1.0, a lens 0.67),
##     the upper edge arches >= 1.5 mm above its corners. RENDER (frontal, close): the black pixels (luma < 0.12) are <= 25 % of the
##     opening, upper teeth >= 40 px and lower teeth >= 40 px (toothy white), the tongue (pink) >= 120 px. CONTROLS: the same code with
##     lip_shape 0 (flat upper edge), a rectangle, a notched polygon; the old black unshaded cavity with no teeth; the teeth hidden;
##     the tongue hidden.
##  B  BLINK (finding 3: "white lumps, specks of the globe poke through"). At AU45 = 0.5 and 1 every mask vertex within the globe's
##     disc is >= 0.8 mm outside the globe sphere (lid thickness 1.2 mm), the paired upper / lower margin vertices close to within
##     0.15 mm in z and 0.05 mm in y at weight 1, and a RENDER with the globe drawn pure magenta shows 0 magenta pixels in the closed
##     eye (also with the eye pitched up 20 deg). CONTROLS: the open eye shows > 150 magenta px (the counter sees the globe); the same
##     closed render with the lid vertices pushed back 3 mm (the lid offset removed) shows > 0 and fails the 0.8 mm bar.
##  N  NOSE (finding 5): d["nose"]: height n-sn 53 mm, width al-al 35 mm, tip projection sn-prn 17 mm, each x s (Farkas 1994,
##     Anthropometry of the Head and Face, male adults; FROM MEMORY, not re-checked this run), within 15 % (projection 30 %); on the
##     midline (|mean x| <= 0.5 mm), its base 20 mm x s above the stomion (sn-sto, Farkas), its root within 12 mm of the eye line, the
##     tip standing >= 8 mm proud of the mask. CONTROLS: width x1.4, the nose moved 6 cm down.
##  G  GIZMO (finding 4): with the geometry on no joint dot is visible within 10 cm of the mouth; with it off one is (the control).
##  T  TOGGLE (finding 6): Expert BODY ribbon has a toggle for the face geometry, OFF by default; it turns it on and off. The mask,
##     the nose, the teeth and the tongue exist in the app and the oral cavity is lit (not UNSHADED, not near black).
##  V  VISEMES: FaceGeo.viseme_au("E") widens the mouth (AU12 > 0, the corners >= 2 mm out), "M" adds nothing. CONTROL: an unknown name.
##  S  FACE_GEO2_SHOT=<path.png>: the 3x3 AU contact sheet, <path>_app.png the in-app close shot, _mouth.png / _blink.png / _side.png.
extends SceneTree

var fails := 0
var m: Node
const MM := 1000.0
const SKIN0 := Color(0.80, 0.82, 0.88)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


# ---------------------------------------------------------------- independent checkers
## boundary loops of a triangle list, each IN WALK ORDER (Array of PackedInt32Array); non-manifold edges counted in out["nm"]
func ordered_loops(tris: PackedInt32Array) -> Array:
	var cnt := {}
	for t in range(0, tris.size() - 2, 3):
		for e in 3:
			var a := tris[t + e]
			var b := tris[t + (e + 1) % 3]
			var k := Vector2i(mini(a, b), maxi(a, b))
			cnt[k] = int(cnt.get(k, 0)) + 1
	var adj := {}
	for k in cnt:
		if int(cnt[k]) == 1:
			var kk: Vector2i = k
			if not adj.has(kk.x):
				adj[kk.x] = []
			if not adj.has(kk.y):
				adj[kk.y] = []
			(adj[kk.x] as Array).append(kk.y)
			(adj[kk.y] as Array).append(kk.x)
	var seen := {}
	var loops := []
	for s in adj:
		if seen.has(s):
			continue
		var lp := PackedInt32Array()
		var prev := -1
		var cur: int = s
		while true:
			seen[cur] = true
			lp.append(cur)
			var nxt := -1
			for n in adj[cur]:
				if int(n) != prev and not seen.has(int(n)):
					nxt = int(n)
					break
			if nxt < 0:
				break
			prev = cur
			cur = nxt
		loops.append(lp)
	return loops


func centroid2(vs: PackedVector3Array, ix: PackedInt32Array) -> Vector2:
	var c := Vector2.ZERO
	for i in ix:
		c += Vector2(vs[i].x, vs[i].y)
	return c / maxf(float(ix.size()), 1.0)


## the loop whose neutral centroid is nearest (x, y); with `far` the loop FARTHEST from the origin (the outer rim)
func loop_at(d: Dictionary, loops: Array, p: Vector2) -> PackedInt32Array:
	var best := PackedInt32Array()
	var bd := 9.0
	for l in loops:
		var dd := centroid2(d["verts"], l).distance_to(p)
		if dd < bd:
			bd = dd
			best = l
	return best


func outer_loop(d: Dictionary, loops: Array) -> PackedInt32Array:
	var best := PackedInt32Array()
	var ba := -1.0
	for l in loops:
		var mn := Vector2(9, 9)
		var mx := Vector2(-9, -9)
		for i in l:
			var v: Vector3 = (d["verts"] as PackedVector3Array)[i]
			mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
			mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
		var a := (mx.x - mn.x) * (mx.y - mn.y)
		if a > ba:
			ba = a
			best = l
	return best


func poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) * 0.5


func hull_area(p: PackedVector2Array) -> float:
	return poly_area(Geometry2D.convex_hull(p))


## the turning angles (deg) between successive edges of a closed loop in the xy plane
func turning(vs: PackedVector3Array, lp: PackedInt32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := lp.size()
	for i in n:
		var a := Vector2(vs[lp[i]].x, vs[lp[i]].y)
		var b := Vector2(vs[lp[(i + 1) % n]].x, vs[lp[(i + 1) % n]].y)
		var c := Vector2(vs[lp[(i + 2) % n]].x, vs[lp[(i + 2) % n]].y)
		var e1 := b - a
		var e2 := c - b
		if e1.length() < 1.0e-9 or e2.length() < 1.0e-9:
			continue
		out.append(rad_to_deg(absf(e1.angle_to(e2))))
	return out


func pct(a: PackedFloat32Array, q: float) -> float:
	var s := Array(a)
	s.sort()
	if s.is_empty():
		return 0.0
	return float(s[mini(int(q * s.size()), s.size() - 1)])


func lab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var x := (0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.95047
	var y := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
	var z := (0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	return Vector3(116.0 * float(f.call(y)) - 16.0, 500.0 * (float(f.call(x)) - float(f.call(y))), 200.0 * (float(f.call(y)) - float(f.call(z))))


func dE(a: Color, b: Color) -> float:
	return lab(a).distance_to(lab(b))


## the topmost z of a triangle soup at (x, y) (corners, three per triangle); -1e9 when nothing is there
func z_at(tris: PackedVector3Array, bb: PackedFloat32Array, x: float, y: float) -> float:
	var best := -1.0e9
	for t in range(0, tris.size() - 2, 3):
		var k := (t / 3) * 4
		if x < bb[k] or x > bb[k + 1] or y < bb[k + 2] or y > bb[k + 3]:
			continue
		var h: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, y, 1.0), Vector3(0, 0, -1), tris[t], tris[t + 1], tris[t + 2])
		if h != null:
			best = maxf(best, (h as Vector3).z)
	return best


func bboxes(tris: PackedVector3Array) -> PackedFloat32Array:
	var bb := PackedFloat32Array()
	for t in range(0, tris.size() - 2, 3):
		bb.append(minf(tris[t].x, minf(tris[t + 1].x, tris[t + 2].x)))
		bb.append(maxf(tris[t].x, maxf(tris[t + 1].x, tris[t + 2].x)))
		bb.append(minf(tris[t].y, minf(tris[t + 1].y, tris[t + 2].y)))
		bb.append(maxf(tris[t].y, maxf(tris[t + 1].y, tris[t + 2].y)))
	return bb


func mask_tris(d: Dictionary, verts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ix: PackedInt32Array = d["tris"]
	for i in ix:
		out.append(verts[i])
	return out


func P(d: Dictionary, au := {}, jaw := 0.0, pitch := 0.0, extra := {}) -> PackedVector3Array:
	var st := {"au": au, "jaw_deg": jaw, "eye_pitch_deg": pitch, "eye_yaw_deg": 0.0}
	for k in extra:
		st[k] = extra[k]
	return FaceGeo.posed(d, st)


# ---- R
## the rim colour / material bar as a function: "" when it holds
func rim_colour_why(d: Dictionary, hm: StandardMaterial3D, mat: StandardMaterial3D, scale: float) -> String:
	if not (is_equal_approx(mat.roughness, hm.roughness) and is_equal_approx(mat.metallic, hm.metallic) and mat.shading_mode == hm.shading_mode):
		return "the mask material is not the head's (roughness %.2f vs %.2f)" % [mat.roughness, hm.roughness]
	if not (mat.vertex_color_use_as_albedo and mat.vertex_color_is_srgb):
		return "vertex colours are not read as sRGB albedo"
	var mesh: ArrayMesh = FaceGeo.mask_mesh(d, d["verts"], hm.albedo_color)
	var col: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lp := outer_loop(d, ordered_loops(d["tris"]))
	var worst := 0.0
	for i in lp:
		var c := col[i]
		worst = maxf(worst, maxf(absf(c.r * scale - hm.albedo_color.r), maxf(absf(c.g * scale - hm.albedo_color.g), absf(c.b * scale - hm.albedo_color.b))))
	if worst > 0.004:
		return "the rim vertex colour differs from the head's by %.3f" % worst
	return ""


func rim_curve_stats(d: Dictionary) -> Vector2:
	var lp := outer_loop(d, ordered_loops(d["tris"]))
	var tn := turning(d["verts"], lp)
	var mx := 0.0
	for a in tn:
		mx = maxf(mx, a)
	return Vector2(mx, pct(tn, 0.95))


## the mask's height above the head's real surface per BFS layer from the outer rim: [layer0 mean, max step between layers]
func feather_stats(d: Dictionary, head: PackedVector3Array, hbb: PackedFloat32Array) -> Vector2:
	var vs: PackedVector3Array = d["verts"]
	var ix: PackedInt32Array = d["tris"]
	var adj := {}
	for t in range(0, ix.size() - 2, 3):
		for e in 3:
			var a := ix[t + e]
			var b := ix[t + (e + 1) % 3]
			if not adj.has(a):
				adj[a] = []
			if not adj.has(b):
				adj[b] = []
			(adj[a] as Array).append(b)
			(adj[b] as Array).append(a)
	var lp := outer_loop(d, ordered_loops(ix))
	var depth := {}
	var q := []
	for i in lp:
		depth[int(i)] = 0
		q.append(int(i))
	var qh := 0
	while qh < q.size():
		var v: int = q[qh]
		qh += 1
		for n in adj[v]:
			if not depth.has(int(n)):
				depth[int(n)] = int(depth[v]) + 1
				q.append(int(n))
	var sum := PackedFloat32Array()
	var cnt := PackedInt32Array()
	sum.resize(16)
	cnt.resize(16)
	var k := 0
	for v in q:
		var dp: int = depth[v]
		if dp >= 16 or (k % 5) != 0:
			k += 1
			continue
		k += 1
		var p := vs[v]
		var zh := z_at(head, hbb, p.x, p.y)
		if zh < -1.0e8:
			continue
		sum[dp] += p.z - zh
		cnt[dp] += 1
	var means := PackedFloat32Array()
	for i in 16:
		means.append(sum[i] / maxf(float(cnt[i]), 1.0))
	var step := 0.0
	for i in range(1, 16):
		step = maxf(step, means[i] - means[i - 1])
	return Vector2(means[0], step)


# ---- M
## the mouth opening's outline: the boundary loop at the mouth, ordered, in the face plane
func mouth_outline(d: Dictionary, verts: PackedVector3Array, loops: Array) -> PackedVector2Array:
	var an: Dictionary = d["anchors"]
	var lp := loop_at(d, loops, Vector2(0.0, float((an["mouth"] as Vector3).y)))
	var out := PackedVector2Array()
	for i in lp:
		out.append(Vector2(verts[i].x, verts[i].y))
	return out


## [solidity, fill of the bounding box, the upper edge's arch (m)]
func outline_stats(p: PackedVector2Array) -> Vector3:
	var mn := Vector2(9, 9)
	var mx := Vector2(-9, -9)
	for v in p:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	var ar := poly_area(p)
	var solid := ar / maxf(hull_area(p), 1.0e-12)
	var fill := ar / maxf((mx.x - mn.x) * (mx.y - mn.y), 1.0e-12)
	# the upper edge: the highest y among points in the middle fifth of the width, against the highest y of the outer fifths
	var w := mx.x - mn.x
	var mid := -9.0
	var edge := -9.0
	for v in p:
		var u := (v.x - mn.x) / w
		if u > 0.4 and u < 0.6:
			mid = maxf(mid, v.y)
		if u < 0.12 or u > 0.88:
			edge = maxf(edge, v.y)
	return Vector3(solid, fill, mid - edge)


func outline_why(s: Vector3) -> String:
	if s.x < 0.93:
		return "solidity %.3f < 0.93" % s.x
	if s.y > 0.85:
		return "fills %.2f of its bounding box (> 0.85: a box)" % s.y
	if s.z < 0.0015:
		return "the upper edge arches only %.2f mm (< 1.5)" % (s.z * MM)
	return ""


# ---- B
## the globe bar as a function over a vertex array: the smallest (distance to the globe centre - globe radius) over the mask vertices
## whose xy lie within the globe's disc, mm
func globe_clear_mm(d: Dictionary, verts: PackedVector3Array) -> float:
	var best := 1.0e9
	var gr := float(d["eye_r"])
	for e in d["eyes"]:
		var c: Vector3 = e["c"]
		for v in verts:
			if (v.x - c.x) * (v.x - c.x) + (v.y - c.y) * (v.y - c.y) < gr * gr * 0.98:
				best = minf(best, (v - c).length() - gr)
	return best * MM


## the closed margins of a side: the worst (|dz|, |dy|) between each upper margin vertex and the lower margin vertex of the same column
func margin_mismatch(d: Dictionary, verts: PackedVector3Array, side: String) -> Vector2:
	var rg: PackedInt32Array = d["region"]
	var rim: PackedByteArray = d["rim"]
	var up := []
	var lo := []
	for i in verts.size():
		if rim[i] != (1 if side == "l" else 2):
			continue
		if rg[i] == int(FaceGeo.REGION["lid_up_" + side]):
			up.append(i)
		elif rg[i] == int(FaceGeo.REGION["lid_lo_" + side]):
			lo.append(i)
	var wz := 0.0
	var wy := 0.0
	var pairs := 0
	for a in up:
		for b in lo:
			if absf(verts[a].x - verts[b].x) < 1.0e-6:
				wz = maxf(wz, absf(verts[a].z - verts[b].z))
				wy = maxf(wy, absf(verts[a].y - verts[b].y))
				pairs += 1
	return Vector2(wz, wy) if pairs > 10 else Vector2(9, 9)


# ---- renders
func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func is_magenta(c: Color) -> bool:
	return c.r > 0.8 and c.b > 0.8 and c.g < 0.25


## the pixels inside a screen polygon: Array of Vector2i
func pixels_in(poly: PackedVector2Array, size: Vector2i) -> Array:
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for v in poly:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	var out := []
	for y in range(maxi(int(mn.y), 0), mini(int(mx.y) + 1, size.y)):
		for x in range(maxi(int(mn.x), 0), mini(int(mx.x) + 1, size.x)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				out.append(Vector2i(x, y))
	return out


## a clean studio: head (smooth normals, one material), mask (FaceGeo.mask_material of it), eyes, oral parts, nose; own camera
func make_studio(d: Dictionary, head_pts: PackedVector3Array, o := {}) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.31, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.70)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, 20, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 21.0
	vp.add_child(cam)
	cam.current = true
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in head_pts:
		sm.add_vertex(v)
	sm.index()
	sm.generate_normals()
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = FaceGeo.cut_head(sm.commit(), d)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = SKIN0
	hmat.roughness = 0.85
	head_mi.material_override = hmat
	vp.add_child(head_mi)
	var mask_mi := MeshInstance3D.new()
	var mmat: StandardMaterial3D = FaceGeo.mask_material(hmat)
	if o.has("albedo_scale"):
		mmat.albedo_color = Color(1, 1, 1) * float(o["albedo_scale"])
	mask_mi.material_override = mmat
	vp.add_child(mask_mi)
	var eye_nodes := []
	for e in d["eyes"]:
		var en := MeshInstance3D.new()
		en.mesh = FaceGeo.eye_mesh(float(e["r"]))
		var emat: Material
		if o.get("magenta", false):
			var mm := StandardMaterial3D.new()
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mm.albedo_color = Color(1, 0, 1)
			emat = mm
		else:
			emat = FaceGeo.eye_material()
		en.material_override = emat
		vp.add_child(en)
		eye_nodes.append(en)
	var parts := {}
	var cav := MeshInstance3D.new()
	cav.mesh = FaceGeo.cavity_mesh(d)
	if o.get("old_cavity", false):
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.08, 0.03, 0.03)
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cav.material_override = cmat
	else:
		cav.material_override = FaceGeo.cavity_material()
	vp.add_child(cav)
	parts["cavity"] = cav
	for nm in ["teeth_up", "teeth_lo", "tongue", "nose"]:
		var mi := MeshInstance3D.new()
		match nm:
			"teeth_up":
				mi.mesh = FaceGeo.teeth_mesh(d, true)
				mi.material_override = FaceGeo.tooth_material()
			"teeth_lo":
				mi.mesh = FaceGeo.teeth_mesh(d, false)
				mi.material_override = FaceGeo.tooth_material()
			"tongue":
				mi.mesh = FaceGeo.tongue_mesh(d)
				mi.material_override = FaceGeo.tongue_material()
			"nose":
				mi.mesh = FaceGeo.nose_mesh(d, SKIN0)
				mi.material_override = FaceGeo.mask_material(hmat)
		if o.get("no_" + nm, false):
			mi.visible = false
		vp.add_child(mi)
		parts[nm] = mi
	return {"vp": vp, "cam": cam, "mask": mask_mi, "eyes": eye_nodes, "parts": parts}


func frame(st: Dictionary, centre: Vector3, dist: float, fov: float, yaw_deg := 0.0) -> void:
	var cam: Camera3D = st["cam"]
	cam.fov = fov
	var dirv := Vector3(sin(deg_to_rad(yaw_deg)), 0.0, cos(deg_to_rad(yaw_deg)))
	cam.position = centre + dirv * dist
	cam.look_at(centre, Vector3.UP)


## pose the studio and return its image. `lid_back`: push the lid-zone mask vertices back this many metres (the control).
func shot(st: Dictionary, d: Dictionary, state: Dictionary, lid_back := 0.0) -> Image:
	var vs := FaceGeo.posed(d, state)
	if lid_back != 0.0:
		var rg: PackedInt32Array = d["region"]
		for i in vs.size():
			var r := rg[i]
			if r >= int(FaceGeo.REGION["lid_up_l"]) and r <= int(FaceGeo.REGION["lid_lo_r"]):
				vs[i] = Vector3(vs[i].x, vs[i].y, vs[i].z - lid_back)
	(st["mask"] as MeshInstance3D).mesh = FaceGeo.mask_mesh(d, vs, SKIN0)
	var tf := FaceGeo.eye_transforms(d, state)
	for i in 2:
		(st["eyes"][i] as MeshInstance3D).transform = tf[i]
	var jx: Transform3D = FaceGeo.jaw_transform(d, state)
	(st["parts"]["teeth_lo"] as MeshInstance3D).transform = jx
	(st["parts"]["tongue"] as MeshInstance3D).transform = jx
	await idle(3)
	await RenderingServer.frame_post_draw
	return (st["vp"] as SubViewport).get_texture().get_image()


func screen(st: Dictionary, p: Vector3) -> Vector2:
	return (st["cam"] as Camera3D).unproject_position(p)


## the screen polygon of the mouth opening for a pose
func mouth_poly(st: Dictionary, d: Dictionary, state: Dictionary) -> PackedVector2Array:
	var vs := FaceGeo.posed(d, state)
	var an: Dictionary = d["anchors"]
	var lp := loop_at(d, ordered_loops(d["tris"]), Vector2(0.0, float((an["mouth"] as Vector3).y)))
	var out := PackedVector2Array()
	for i in lp:
		out.append(screen(st, vs[i]))
	return out


## counts inside the opening: [pixels, black, teeth_upper, teeth_lower, pink]
func mouth_counts(img: Image, poly: PackedVector2Array) -> Array:
	var px := pixels_in(poly, img.get_size())
	var cy := 0.0
	for v in poly:
		cy += v.y
	cy /= maxf(float(poly.size()), 1.0)
	var black := 0
	var tu := 0
	var tl := 0
	var pink := 0
	for p in px:
		var c := img.get_pixel((p as Vector2i).x, (p as Vector2i).y)
		if lum(c) < 0.12:
			black += 1
		var mxc := maxf(c.r, maxf(c.g, c.b))
		var mnc := minf(c.r, minf(c.g, c.b))
		if mnc > 0.70 and (mxc - mnc) < 0.22:
			if float((p as Vector2i).y) < cy:
				tu += 1
			else:
				tl += 1
		if c.r > 0.50 and c.r - c.g > 0.22 and c.r - c.b > 0.10:
			pink += 1
	return [px.size(), black, tu, tl, pink]


func magenta_in(img: Image, centre: Vector2, rad: float) -> int:
	var n := 0
	for y in range(maxi(int(centre.y - rad), 0), mini(int(centre.y + rad), img.get_height())):
		for x in range(maxi(int(centre.x - rad), 0), mini(int(centre.x + rad), img.get_width())):
			if Vector2(x, y).distance_to(centre) <= rad and is_magenta(img.get_pixel(x, y)):
				n += 1
	return n


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()
	var head_pts: PackedVector3Array = m.call("_head_pts")
	var d := FaceGeo.build(head_pts)
	var an: Dictionary = d["anchors"]
	var s := float(an["top"]) / 1.754
	var vs0: PackedVector3Array = d["verts"]
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = SKIN0
	hmat.roughness = 0.85
	print("scale s = %.4f, mask %d vertices" % [s, vs0.size()])

	# ---------------- R: rim / blend
	var mat: StandardMaterial3D = FaceGeo.mask_material(hmat)
	var why := rim_colour_why(d, hmat, mat, 1.0)
	ok(why == "", "R1 the mask is the head's material and colour at the rim (sRGB vertex colours) %s" % why)
	var why_c := rim_colour_why(d, hmat, mat, 1.3)
	ok(why_c != "", "R1 CONTROL vertex colours x1.3 (a bright plate) are caught: %s" % why_c)
	var cs := rim_curve_stats(d)
	ok(cs.x <= 20.0 and cs.y <= 8.0, "R3 the rim curve is smooth: largest turn %.1f deg (<= 20), 95th percentile %.1f deg (<= 8)" % [cs.x, cs.y])
	var d_stair := FaceGeo.build(head_pts, {}, {"smooth_rim": false, "feather": false})
	var cs0 := rim_curve_stats(d_stair)
	ok(not (cs0.x <= 20.0 and cs0.y <= 8.0), "R3 CONTROL the staircase rim turns %.1f deg at most, 95th percentile %.1f deg: caught" % [cs0.x, cs0.y])
	var hbb := bboxes(head_pts)
	var fs := feather_stats(d, head_pts, hbb)
	ok(absf(fs.x) <= 0.6 * 0.001 and fs.y <= 0.35 * 0.001, "R4 the rim lies on the head skin (%+.2f mm, bar +-0.6) and the mask rises by at most %.2f mm per layer (bar 0.35)" % [fs.x * MM, fs.y * MM])
	var fs0 := feather_stats(d_stair, head_pts, hbb)
	ok(not (absf(fs0.x) <= 0.6 * 0.001 and fs0.y <= 0.35 * 0.001), "R4 CONTROL no feather: rim %+.2f mm, step %.2f mm per layer: caught" % [fs0.x * MM, fs0.y * MM])

	# R2 the render: dE 5 mm either side of the rim
	var studio := await make_studio(d, head_pts)
	var studio_b := await make_studio(d, head_pts, {"albedo_scale": 1.3})
	var fc := Vector3(0, float(an["chin"]) + 0.46 * float(an["H"]), 0.12)
	frame(studio, fc, 0.52, 21.0)
	frame(studio_b, fc, 0.52, 21.0)
	var neutral := {"au": {}, "jaw_deg": 0.0, "eye_pitch_deg": 0.0, "eye_yaw_deg": 0.0}
	var img_n: Image = await shot(studio, d, neutral)
	var img_b: Image = await shot(studio_b, d, neutral)
	var lp := outer_loop(d, ordered_loops(d["tris"]))
	var mtr := mask_tris(d, vs0)
	var mbb := bboxes(mtr)
	var de_a := rim_de(studio, img_n, d, lp, head_pts, hbb, mtr, mbb)
	var de_b := rim_de(studio_b, img_b, d, lp, head_pts, hbb, mtr, mbb)
	var enough: bool = int(de_a[2]) >= int(lp.size() * 0.4 / 6.0)
	ok(enough and float(de_a[0]) <= 3.0 and float(de_a[1]) <= 6.0, "R2 render: dE across the rim mean %.2f (<= 3.0), p90 %.2f (<= 6.0), %d samples with head behind" % [de_a[0], de_a[1], de_a[2]])
	ok(float(de_b[0]) > 3.0, "R2 CONTROL the mask drawn with albedo x1.3: mean dE %.2f > 3.0, caught" % float(de_b[0]))

	# ---------------- M: mouth
	var loops := ordered_loops(d["tris"])
	var o26 := outline_stats(mouth_outline(d, P(d, {"AU26": 1.0}), loops))
	ok(outline_why(o26) == "", "M1 AU26 outline: solidity %.3f, fill %.2f, upper arch %.2f mm %s" % [o26.x, o26.y, o26.z * MM, outline_why(o26)])
	var oj := outline_stats(mouth_outline(d, P(d, {}, 20.0), loops))
	ok(outline_why(oj) == "", "M1 jaw 20 deg outline: solidity %.3f, fill %.2f, upper arch %.2f mm %s" % [oj.x, oj.y, oj.z * MM, outline_why(oj)])
	var o_flat := outline_stats(mouth_outline(d, P(d, {"AU26": 1.0}, 0.0, 0.0, {"lip_shape": 0.0}), loops))
	ok(outline_why(o_flat) != "", "M1 CONTROL lip_shape 0 (the flat upper edge): %s" % outline_why(o_flat))
	var rect := PackedVector2Array([Vector2(-0.025, 0), Vector2(0.025, 0), Vector2(0.025, -0.04), Vector2(-0.025, -0.04)])
	ok(outline_why(outline_stats(rect)) != "", "M1 CONTROL a rectangle (the old black box): %s" % outline_why(outline_stats(rect)))
	var notch := PackedVector2Array([Vector2(-0.025, 0), Vector2(0, -0.03), Vector2(0.025, 0), Vector2(0.02, -0.04), Vector2(-0.02, -0.04)])
	ok(outline_why(outline_stats(notch)) != "", "M1 CONTROL a notched polygon: %s" % outline_why(outline_stats(notch)))

	var mc := Vector3(0, float((an["mouth"] as Vector3).y) - 0.016, 0.12)
	var open := {"au": {"AU26": 1.0}, "jaw_deg": 0.0, "eye_pitch_deg": 0.0, "eye_yaw_deg": 0.0}
	frame(studio, mc, 0.40, 9.0)
	var img_o: Image = await shot(studio, d, open)
	var poly := mouth_poly(studio, d, open)
	var cnt := mouth_counts(img_o, poly)
	var bf := float(cnt[1]) / maxf(float(cnt[0]), 1.0)
	ok(int(cnt[0]) > 2000 and bf <= 0.25, "M2 open jaw, frontal: opening %d px, black fraction %.3f (<= 0.25)" % [cnt[0], bf])
	ok(int(cnt[2]) >= 40 and int(cnt[3]) >= 40, "M2 teeth visible: upper %d px, lower %d px (>= 40 each)" % [cnt[2], cnt[3]])
	ok(int(cnt[4]) >= 120, "M2 the tongue shows: %d pink px (>= 120)" % cnt[4])
	var studio_old := await make_studio(d, head_pts, {"old_cavity": true, "no_teeth_up": true, "no_teeth_lo": true, "no_tongue": true})
	frame(studio_old, mc, 0.40, 9.0)
	var img_old: Image = await shot(studio_old, d, open)
	var cnt_old := mouth_counts(img_old, mouth_poly(studio_old, d, open))
	var bf_old := float(cnt_old[1]) / maxf(float(cnt_old[0]), 1.0)
	ok(bf_old > 0.25, "M2 CONTROL the old black cavity, no teeth: black fraction %.3f > 0.25, caught" % bf_old)
	var studio_nt := await make_studio(d, head_pts, {"no_teeth_up": true, "no_teeth_lo": true, "no_tongue": true})
	frame(studio_nt, mc, 0.40, 9.0)
	var img_nt: Image = await shot(studio_nt, d, open)
	var cnt_nt := mouth_counts(img_nt, mouth_poly(studio_nt, d, open))
	ok(int(cnt_nt[2]) < 40 and int(cnt_nt[3]) < 40, "M2 CONTROL teeth hidden: upper %d, lower %d px (< 40), caught" % [cnt_nt[2], cnt_nt[3]])
	ok(int(cnt_nt[4]) < 120, "M2 CONTROL tongue hidden: %d pink px (< 120), caught" % cnt_nt[4])

	# ---------------- B: blink
	var closed := {"au": {"AU45": 1.0}, "jaw_deg": 0.0, "eye_pitch_deg": 0.0, "eye_yaw_deg": 0.0}
	var half := {"au": {"AU45": 0.5}, "jaw_deg": 0.0, "eye_pitch_deg": 0.0, "eye_yaw_deg": 0.0}
	var gc1 := globe_clear_mm(d, FaceGeo.posed(d, closed))
	var gc5 := globe_clear_mm(d, FaceGeo.posed(d, half))
	var gc0 := globe_clear_mm(d, vs0)
	ok(gc1 >= 0.8 and gc5 >= 0.8 and gc0 >= 0.8, "B1 the lids ride the globe: clearance open %.2f, half %.2f, closed %.2f mm (>= 0.8)" % [gc0, gc5, gc1])
	var lowered := FaceGeo.posed(d, closed)
	var rg: PackedInt32Array = d["region"]
	for i in lowered.size():
		if rg[i] >= int(FaceGeo.REGION["lid_up_l"]) and rg[i] <= int(FaceGeo.REGION["lid_lo_r"]):
			lowered[i] = Vector3(lowered[i].x, lowered[i].y, lowered[i].z - 0.003)
	var gcl := globe_clear_mm(d, lowered)
	ok(gcl < 0.8, "B1 CONTROL the lid offset removed (3 mm back): clearance %.2f mm < 0.8, caught" % gcl)
	var mmv := margin_mismatch(d, FaceGeo.posed(d, closed), "l")
	var mmr := margin_mismatch(d, FaceGeo.posed(d, closed), "r")
	ok(mmv.x <= 0.00015 and mmv.y <= 0.00005 and mmr.x <= 0.00015 and mmr.y <= 0.00005, "B2 closed margins meet: left dz %.3f dy %.3f mm, right dz %.3f dy %.3f mm (bar 0.15 / 0.05)" % [mmv.x * MM, mmv.y * MM, mmr.x * MM, mmr.y * MM])
	var studio_m := await make_studio(d, head_pts, {"magenta": true})
	var ec: Vector3 = (d["eyes"][0] as Dictionary)["c"]
	var ec2: Vector3 = (d["eyes"][1] as Dictionary)["c"]
	frame(studio_m, Vector3(0, ec.y, ec.z), 0.40, 12.0)
	var rad := 0.020 * s / 0.0003   # px: 20 mm; refined below from the projection
	var p0 := screen(studio_m, ec)
	var p1 := screen(studio_m, ec + Vector3(0.020, 0, 0))
	rad = p0.distance_to(p1)
	var img_open: Image = await shot(studio_m, d, neutral)
	var mg_open := magenta_in(img_open, p0, rad) + magenta_in(img_open, screen(studio_m, ec2), rad)
	var img_cl: Image = await shot(studio_m, d, closed)
	var mg_cl := magenta_in(img_cl, p0, rad) + magenta_in(img_cl, screen(studio_m, ec2), rad)
	var closed_up := {"au": {"AU45": 1.0}, "jaw_deg": 0.0, "eye_pitch_deg": 20.0, "eye_yaw_deg": 0.0}
	var img_cu: Image = await shot(studio_m, d, closed_up)
	var mg_cu := magenta_in(img_cu, p0, rad) + magenta_in(img_cu, screen(studio_m, ec2), rad)
	ok(mg_cl == 0 and mg_cu == 0, "B3 render: globe pixels in the closed eye %d (pitch 20 deg: %d), bar 0" % [mg_cl, mg_cu])
	ok(mg_open > 150, "B3 CONTROL the open eye shows %d magenta globe px (> 150): the counter sees the globe" % mg_open)
	var img_lb: Image = await shot(studio_m, d, closed, 0.003)
	var mg_lb := magenta_in(img_lb, p0, rad) + magenta_in(img_lb, screen(studio_m, ec2), rad)
	ok(mg_lb > 0, "B3 CONTROL closed with the lid offset removed shows %d globe px (> 0), caught" % mg_lb)

	# ---------------- N: nose
	var nose: Dictionary = d.get("nose", {})
	ok(not nose.is_empty(), "N0 d[nose] exists")
	if not nose.is_empty():
		var nws := nose_why(d, nose, s)
		ok(nws == "", "N1 nose %s" % nws)
		var nw: Dictionary = nose.duplicate(true)
		var nv: PackedVector3Array = (nw["verts"] as PackedVector3Array).duplicate()
		for i in nv.size():
			nv[i] = Vector3(nv[i].x * 1.4, nv[i].y, nv[i].z)
		nw["verts"] = nv
		ok(nose_why(d, nw, s) != "", "N1 CONTROL width x1.4: %s" % nose_why(d, nw, s))
		var nd: Dictionary = nose.duplicate(true)
		var nv2: PackedVector3Array = (nd["verts"] as PackedVector3Array).duplicate()
		for i in nv2.size():
			nv2[i] = Vector3(nv2[i].x, nv2[i].y - 0.06, nv2[i].z)
		nd["verts"] = nv2
		ok(nose_why(d, nd, s) != "", "N1 CONTROL moved 6 cm down: %s" % nose_why(d, nd, s))

	# ---------------- V: visemes
	var ve := FaceGeo.viseme_au("E")
	var vm := FaceGeo.viseme_au("M")
	var base := P(d)
	var wide := P(d, ve)
	var out_mm := 0.0
	for i in base.size():
		if rg[i] == int(FaceGeo.REGION["lip_up"]) or rg[i] == int(FaceGeo.REGION["lip_lo"]):
			if base[i].x > 0.015:
				out_mm = maxf(out_mm, (wide[i].x - base[i].x) * MM)
	ok(float(ve.get("AU12", 0.0)) > 0.0 and out_mm >= 2.0, "V1 viseme E: AU12 %.2f, the right-hand corner goes %.2f mm out (>= 2)" % [float(ve.get("AU12", 0.0)), out_mm])
	ok(vm.is_empty() and FaceGeo.viseme_au("Q").is_empty(), "V1 viseme M adds no AU; CONTROL an unknown name adds none")

	# ---------------- the app: G gizmo, T toggle, in-app parts
	ok(not bool(m.face_geo_on), "T1 the face geometry is OFF by default")
	var tgl: Button = null
	for tg in m.ui_toggles:
		var b: Button = tg[0]
		if b.text.findn("face geometry") >= 0:
			tgl = b
	ok(tgl != null, "T1 the Expert BODY ribbon has a face geometry toggle")
	var mouth_w: Vector3 = m.face_at(an["mouth"])
	var near_off := dots_near(mouth_w, 0.10)
	ok(near_off > 0, "G1 CONTROL geometry off: %d joint dot(s) visible within 10 cm of the mouth (the gizmo exists)" % near_off)
	if tgl != null:
		tgl.button_pressed = true
		tgl.pressed.emit()
	else:
		m._face_geo_set(true)
	await idle(3)
	ok(bool(m.face_geo_on) and m.face_geo_root != null and m.face_geo_root.visible, "T2 the toggle turns the geometry on")
	var names := []
	for ch in m.face_geo_root.get_children():
		names.append(String(ch.name))
	var want_parts := ["teeth_up", "teeth_lo", "tongue", "nose"]
	var miss := []
	for w in want_parts:
		if not names.has(w):
			miss.append(w)
	ok(miss.is_empty(), "T3 the app has the nose, the teeth and the tongue (missing %s)" % str(miss))
	var cavn: MeshInstance3D = m.face_geo_root.find_child("cavity", false, false)
	var cavm: StandardMaterial3D = cavn.material_override if cavn != null else null
	ok(cavm != null and cavm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and lum(cavm.albedo_color) > 0.05 or (cavm != null and cavm.vertex_color_use_as_albedo and cavm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED), "T3 the oral cavity is lit, not an unshaded black box")
	var near_on := dots_near(mouth_w, 0.10)
	ok(near_on == 0, "G1 geometry on: %d joint dots visible within 10 cm of the mouth (0 wanted)" % near_on)
	var mmat: Material = m.face_geo_mask.material_override
	var hmat_app: Material = (m.pieces["head"] as MeshInstance3D).material_override
	ok(mmat is StandardMaterial3D and (mmat as StandardMaterial3D).vertex_color_is_srgb, "T4 the mask in the app reads its vertex colours as sRGB")
	if hmat_app is StandardMaterial3D and mmat is StandardMaterial3D:
		ok(is_equal_approx((mmat as StandardMaterial3D).roughness, (hmat_app as StandardMaterial3D).roughness), "T4 the mask's roughness is the head's in the app (%.2f)" % (mmat as StandardMaterial3D).roughness)

	# ---------------- S: the renders to LOOK at
	var shotp := OS.get_environment("FACE_GEO2_SHOT")
	if shotp != "":
		var tiles := []
		var jw := FaceGeo.preset("joy")
		var pn := FaceGeo.preset("pain")
		var states := [{}, {"AU1": 1.0}, {"AU4": 1.0}, {"AU6": 1.0}, {"AU12": 1.0}, {"AU26": 1.0}, {"AU45": 1.0}, jw, pn]
		var labels := ["neutral", "AU1", "AU4", "AU6", "AU12", "AU26", "AU45", "joy", "pain"]
		frame(studio, fc, 0.52, 21.0)
		for k in states.size():
			tiles.append(await shot(studio, d, {"au": states[k], "jaw_deg": 0.0, "eye_pitch_deg": 0.0, "eye_yaw_deg": 0.0}))
		var tw: int = (tiles[0] as Image).get_width()
		var sheet := Image.create(tw * 3, tw * 3, false, Image.FORMAT_RGBA8)
		for k in tiles.size():
			(tiles[k] as Image).convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(tiles[k], Rect2i(Vector2i.ZERO, (tiles[k] as Image).get_size()), Vector2i(tw * (k % 3), tw * (k / 3)))
		sheet.save_png(shotp)
		frame(studio, mc, 0.40, 9.0)
		(await shot(studio, d, open)).save_png(shotp.get_basename() + "_mouth.png")
		frame(studio_m, Vector3(0, ec.y, ec.z), 0.40, 12.0)
		(await shot(studio, d, closed)).save_png(shotp.get_basename() + "_blink.png")
		frame(studio, Vector3(0, float((an["mouth"] as Vector3).y) + 0.04, 0.12), 0.45, 15.0, 70.0)
		(await shot(studio, d, neutral)).save_png(shotp.get_basename() + "_side.png")
		print("labels ", labels)
		if m.ui_toast != null:
			m.ui_toast.visible = false
		if m.dummy_on:
			m._dummy_toggle()
		var hc: Vector3 = m.face_at(an["eye_l"]) * 0.5 + m.face_at(an["eye_r"]) * 0.5 - Vector3(0, 0.03, 0)
		m._turn_to(0.0, -5.0, 0.7, hc, false)
		await idle(3)
		await RenderingServer.frame_post_draw
		var ai := root.get_texture().get_image()
		var sp: Vector2 = m.cam.unproject_position(hc)
		var r := Rect2i(int(sp.x) - 200, int(sp.y) - 200, 400, 400).intersection(Rect2i(Vector2i.ZERO, ai.get_size()))
		ai.get_region(r).save_png(shotp.get_basename() + "_app.png")
		ok(FileAccess.file_exists(shotp), "S the contact sheet saved to %s" % shotp)
	m._face_geo_set(false)
	print("FACE GEO2 TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	print("face_geo2: %d fail" % fails)
	TestFiles.cleanup()
	quit(fails)


## joint dots visible within r of a world point
func dots_near(p: Vector3, r: float) -> int:
	var n := 0
	for j in m.dots:
		var dn: Node3D = m.dots[j]
		if dn.visible and dn.global_position.distance_to(p) < r:
			n += 1
	return n


## [mean dE, p90 dE, samples] across the rim: the picture 5 mm outside vs 5 mm inside, where the head is behind the rim
func rim_de(st: Dictionary, img: Image, d: Dictionary, lp: PackedInt32Array, head: PackedVector3Array, hbb: PackedFloat32Array, mtr: PackedVector3Array, mbb: PackedFloat32Array) -> Array:
	var vs: PackedVector3Array = d["verts"]
	var c := centroid2(vs, lp)
	var n := lp.size()
	var des := PackedFloat32Array()
	var i := 0
	while i < n:
		var a := vs[lp[(i + n - 2) % n]]
		var b := vs[lp[(i + 2) % n]]
		var t := Vector2(b.x - a.x, b.y - a.y).normalized()
		var nrm := Vector2(t.y, -t.x)
		var v := vs[lp[i]]
		if nrm.dot(Vector2(v.x, v.y) - c) < 0.0:
			nrm = -nrm
		var po := Vector2(v.x, v.y) + nrm * 0.005
		var pi := Vector2(v.x, v.y) - nrm * 0.005
		var zo := z_at(head, hbb, po.x, po.y)
		var zi := z_at(mtr, mbb, pi.x, pi.y)
		# head behind the rim: the head's surface within 6 mm of the mask's at the rim
		var zr := z_at(head, hbb, v.x, v.y)
		if zo > -1.0e8 and zi > -1.0e8 and zr > -1.0e8 and absf(zr - v.z) < 0.006:
			var so := screen(st, Vector3(po.x, po.y, zo))
			var si := screen(st, Vector3(pi.x, pi.y, zi))
			des.append(dE(patch(img, so), patch(img, si)))
		i += 6
	var sum := 0.0
	for e in des:
		sum += e
	return [sum / maxf(float(des.size()), 1.0), pct(des, 0.9), des.size()]


func patch(img: Image, p: Vector2) -> Color:
	var acc := Color(0, 0, 0, 0)
	var k := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := clampi(int(p.x) + dx, 0, img.get_width() - 1)
			var y := clampi(int(p.y) + dy, 0, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			acc += c
			k += 1
	return Color(acc.r / k, acc.g / k, acc.b / k, 1.0)


## the nose bar as a function: "" when it holds
func nose_why(d: Dictionary, nose: Dictionary, s: float) -> String:
	var v: PackedVector3Array = nose["verts"]
	var an: Dictionary = d["anchors"]
	var my := float((an["mouth"] as Vector3).y)
	var cy := float((an["eye_l"] as Vector3).y)
	var mn := Vector3(9, 9, 9)
	var mx := Vector3(-9, -9, -9)
	var mean_x := 0.0
	for p in v:
		mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
		mean_x += p.x
	mean_x /= maxf(float(v.size()), 1.0)
	var h := (mx.y - mn.y) * MM
	# the width: the widest x extent among rows whose height above the mask is >= 3 mm (the alae, not the flat skirt)
	var wid := 0.0
	var zs: PackedVector3Array = d["verts"]
	var tip := mx
	var tip_proud := 0.0
	for p in v:
		if p.z >= mx.z - 1.0e-6:
			tip = p
	# projection: the tip's z over the mask surface under it (nearest mask vertex in xy)
	var best := 9.0
	for q in zs:
		var dd := Vector2(q.x - tip.x, q.y - tip.y).length()
		if dd < best:
			best = dd
			tip_proud = tip.z - q.z
	var rows := {}
	for p in v:
		var key := int(round(p.y * 1000.0))
		if not rows.has(key):
			rows[key] = Vector2(9, -9)
		var r: Vector2 = rows[key]
		rows[key] = Vector2(minf(r.x, p.x), maxf(r.y, p.x))
	var base_y: float = float(nose.get("base_y", mn.y))
	for key in rows:
		var r: Vector2 = rows[key]
		if float(key) * 0.001 <= base_y + 0.012 * s and float(key) * 0.001 >= base_y:
			wid = maxf(wid, (r.y - r.x) * MM)
	if absf(h - 53.0 * s) > 0.15 * 53.0 * s:
		return "height %.1f mm vs %.1f (+-15 %%)" % [h, 53.0 * s]
	if absf(wid - 35.0 * s) > 0.15 * 35.0 * s:
		return "width %.1f mm vs %.1f (+-15 %%)" % [wid, 35.0 * s]
	if absf(tip_proud * MM - 17.0 * s) > 0.30 * 17.0 * s:
		return "projection %.1f mm vs %.1f (+-30 %%)" % [tip_proud * MM, 17.0 * s]
	if absf(mean_x) > 0.0005:
		return "off the midline by %.2f mm" % (mean_x * MM)
	if absf(mn.y - (my + 0.020 * s)) > 0.006:
		return "base %.1f mm from sn = stomion + 20 s" % ((mn.y - (my + 0.020 * s)) * MM)
	if absf(mx.y - cy) > 0.012 + 0.012 * s:
		return "root %.1f mm from the eye line" % ((mx.y - cy) * MM)
	if tip_proud < 0.008:
		return "the tip stands only %.1f mm proud (>= 8)" % (tip_proud * MM)
	return ""
