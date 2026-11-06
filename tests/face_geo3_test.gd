## godot --path . -s tests/face_geo3_test.gd     (L23 FACE3: the third round on the face geometry, after the reviewer LOOKed at the AU sheet of
## PR #237. Needs a window: :w. tests/face_geo_test.gd (40) and tests/face_geo2_test.gd (41-42) are untouched; this is a NEW file.)
## Bars written BEFORE the implementation and committed first (they fail on the base). Each has a PLANTED CONTROL: the same checker on a
## deliberately wrong input must say FAIL, so a checker that cannot fail cannot pass here.
##  O  OPEN MOUTH (finding 1: "the AU26 cavity is a huge red box reaching toward the chin, the teeth blocky white slabs with hard gaps").
##     State = AU25 + AU26 = 1 (lips part + jaw drop, as face_geo2 M1). O1 the lip aperture (height of the mouth opening, the mask's mouth
##     rim) lies in 40..50 mm (the jaw bar: incisal opening at 27.5 deg, Agerberg 1974 40-55 mm, the narrower band is the bar) and within
##     10 % of FaceGeo.incisal_mm(27.5). O2 the width stays near the 52 mm neutral (x s: within 10 %) and NARROWS a little when the jaw
##     drops: 0.80 .. 0.99 x the neutral width. O3 RENDER (frontal): with the cavity drawn pure magenta (unshaded) and the teeth and the
##     tongue hidden, the magenta bounding box in px / the px-per-mm of the lip plane = the aperture and the width of O1 / O2 within 10 %.
##     O4 RENDER: 0 background pixels inside the opening (the cavity covers it, no see-through). CONTROLS: O1/O2/O3 on a jaw driven to
##     36 deg (a bigger box); O3/O4 with the cavity hidden (the magenta box is empty, the background shows through).
##  T  TEETH (same finding). T1 ROUNDED CROWNS: the largest dihedral angle between the two faces at any shared edge of the upper and of
##     the lower row <= 55 deg (a box has 90). T2 NO GAP: frontal render of the upper row alone (white, unshaded, over a flat background):
##     along five scan lines through the middle of the crowns, no background run between two teeth is wider than 0.10 x the width of a
##     central incisor (8.5 mm x s), and the row spans >= 33 mm; same for the lower row. T3 GUM LINE: the row's vertex colours carry a
##     pink gum: 12 .. 45 % of the vertices, on the root side (above the crowns for the upper row, below for the lower). CONTROLS: a row
##     of BoxMesh slabs (T1), crowns shrunk to 0.8 of their width (T2), a row with no gum (T3).
##  V  VISEMES (finding 2: "only E drives a mouth AU"). V0 every AU the visemes use (AU10 16 18 20 22 23 24 28; AU25 is the lens of
##     posed()) is a blendshape of d["au"] with one delta per mask vertex, nonzero in the mouth zone and exactly zero 4 cm above the
##     mouth line. V1 for each of rest, A, E, I, O, U, MBP, FV, L, TH: the lip aperture HEIGHT, the mouth WIDTH and the lip PROTRUSION of
##     FaceGeo.viseme_pose(name) (mask mouth rim, mm / s) lie in the range of RANGES below. M/B/P: aperture <= 0.05 mm. O, U: protrude >=
##     4 / 6 mm and round (width <= 42 / 36 mm). F/V: the lower lip's rim within 3.5 mm of the upper incisors. L: the tongue tip rides up
##     behind the upper incisors. TH: the tongue tip between the teeth, at the lip plane. SOURCES, FROM MEMORY (not re-read this run):
##     Fromkin 1964 "Lip positions in American English vowels" (Language & Speech 7); Linker 1982 "Articulatory and acoustic correlates
##     of labial activity in vowels" (UCLA Working Papers in Phonetics 56): lip opening and protrusion of the English vowels (rounded
##     /u o/ protrude 5-10 mm and narrow, /a/ open, /i/ spread); Benguerel & Cowan 1974 (coarticulated lip rounding); Fisher 1968 and
##     Jeffers & Barley 1971 (the visemes: bilabial closure, labiodental contact, interdental tongue). The ranges are WIDER than those
##     papers' means +- 1 sd: they say "a plausible mouth", not a measured speaker. CONTROL for each: the pose of a different viseme must
##     break its range (rest <- A, A <- MBP, E <- O, I <- U, O <- I, U <- E, MBP <- A, FV <- rest, L <- rest, TH <- rest).
##  E  EARS (finding 3). d["ears"] = two simple ears, helix + antihelix + lobe, from anthropometry: E1 length (top to lobe) 60 mm x s
##     +- 8 %; E2 the top at brow level (+- 6 mm x s of the brow anchor); E3 the front edge 85 mm x s behind the eye (+- 15 mm), the width
##     33 mm x s +- 15 %; E4 on the head sides: the ear stands on the head's own side surface (>= 3 % of its vertices within 1.5 mm of
##     it, none buried more than 2.5 mm) and its farthest point stands 8 .. 28 mm out; E5 left and right mirror within 1.5 mm; E6 helix
##     AND antihelix: along a horizontal cut through the ear the standoff profile has >= 2 ridges (prominence >= 1 mm); E7 a lobe: the
##     lowest fifth of the ear stands >= 3 mm out and is >= 8 mm x s wide. CONTROLS: flat ear (E6), moved 4 cm down (E2), length x1.5
##     (E1), pushed 12 mm into the head (E4), moved 5 cm forward (E3), lobe flattened (E7).
##  C  CHIN (finding 4: "the hollow under the chin"). RENDER from a low camera (32 deg below, frontal and 3/4): the bare head's silhouette
##     (eroded by 2 px) contains 0 background pixels in the face-geometry render (cut head + mask + parts), at neutral, and with the
##     jaw open (27.5 deg and the 11 deg of an A) there are 0 enclosed background holes that the bare head does not have. CONTROLS: the
##     same render without the chin part (holes > 0); the jaw-open hole test with the chin part left at neutral.
##  P  THE APP: the toggle's root has the ears and the chin part, the viseme override reaches the mask (MBP closes it, O does not).
##  S  FACE_GEO3_SHOT=<prefix>: <prefix>_visemes.png (4x3 sheet), _jaw.png (open-jaw close-up), _ear.png (3/4 view), _chin.png (low angle).
extends SceneTree

var fails := 0
var m: Node
const MM := 1000.0
const SKIN0 := Color(0.80, 0.82, 0.88)
const BGC := Color(0.0, 1.0, 0.0)          # the render background: pure green, nothing lit by the studio is that colour
var FG: GDScript = load("res://scripts/face_geo.gd")

# mm at s = 1: [low, high] per viseme: aperture height h, width w, protrusion p (the upper lip's rim, forward of neutral)
const RANGES := {
	"rest": {"h": [0.0, 1.5], "w": [46.0, 58.0], "p": [-1.5, 1.5]},
	"A": {"h": [14.0, 26.0], "w": [40.0, 54.0], "p": [-4.0, 2.5]},
	"E": {"h": [6.0, 14.0], "w": [52.0, 66.0], "p": [-4.0, 2.5]},
	"I": {"h": [3.0, 10.0], "w": [56.0, 70.0], "p": [-4.0, 2.0]},
	"O": {"h": [8.0, 18.0], "w": [30.0, 42.0], "p": [4.0, 14.0]},
	"U": {"h": [3.0, 9.0], "w": [26.0, 36.0], "p": [6.0, 16.0]},
	"MBP": {"h": [0.0, 0.05], "w": [46.0, 58.0], "p": [-3.0, 2.0]},
	"FV": {"h": [1.0, 6.0], "w": [48.0, 60.0], "p": [-4.0, 2.0]},
	"L": {"h": [5.0, 14.0], "w": [46.0, 60.0], "p": [-4.0, 2.5]},
	"TH": {"h": [3.0, 9.0], "w": [48.0, 60.0], "p": [-4.0, 2.5]}}
const CONTROL := {"rest": "A", "A": "MBP", "E": "O", "I": "U", "O": "I", "U": "E", "MBP": "A", "FV": "rest", "L": "rest", "TH": "rest"}
const VIS_AUS := ["AU10", "AU16", "AU18", "AU20", "AU22", "AU23", "AU24", "AU28"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


# ---------------------------------------------------------------- state helpers
func st(au := {}, jaw := 0.0) -> Dictionary:
	return {"au": au, "jaw_deg": jaw, "eye_pitch_deg": 0.0, "eye_yaw_deg": 0.0}


func vst(name: String) -> Dictionary:
	if FG.has_method("viseme_pose"):
		var s: Dictionary = FG.call("viseme_pose", name)
		var o := st(s.get("au", {}), float(s.get("jaw_deg", 0.0)))
		o["viseme"] = name
		return o
	return st()


func arity(name: String) -> int:
	for md in FG.get_script_method_list():
		if String(md["name"]) == name:
			return (md["args"] as Array).size()
	return -1


func teeth(d: Dictionary, upper: bool, o := {}) -> ArrayMesh:
	if not o.is_empty() and arity("teeth_mesh") >= 3:
		return FG.call("teeth_mesh", d, upper, o)
	return FaceGeo.teeth_mesh(d, upper)


func tongue_tf(d: Dictionary, s: Dictionary) -> Transform3D:
	if FG.has_method("tongue_transform"):
		return FG.call("tongue_transform", d, s)
	return FaceGeo.jaw_transform(d, s)


# ---------------------------------------------------------------- mouth measurements (the mask's mouth rim, rim == 3)
## {"h": the largest upper-lower gap over the rim columns, "w": the rim's x extent, "pz": the upper lip's central rim z, "lo": the lower lip's
## central rim points} in metres
func mouth_rim(d: Dictionary, vs: PackedVector3Array) -> Dictionary:
	var rim: PackedByteArray = d["rim"]
	var rg: PackedInt32Array = d["region"]
	var up := {}
	var lo := {}
	var xmin := 9.0
	var xmax := -9.0
	var pzs := 0.0
	var pzn := 0
	var lop := []
	for i in vs.size():
		if rim[i] != 3:
			continue
		var key := int(round((d["verts"] as PackedVector3Array)[i].x * 100000.0))
		xmin = minf(xmin, vs[i].x)
		xmax = maxf(xmax, vs[i].x)
		var x0: float = (d["verts"] as PackedVector3Array)[i].x
		if rg[i] == int(FaceGeo.REGION["lip_up"]):
			up[key] = vs[i].y
			if absf(x0) <= 0.010:
				pzs += vs[i].z
				pzn += 1
		else:
			lo[key] = vs[i].y
			if absf(x0) <= 0.008:
				lop.append(vs[i])
	var h := 0.0
	for k in up:
		if lo.has(k):
			h = maxf(h, float(up[k]) - float(lo[k]))
	return {"h": h, "w": xmax - xmin, "pz": pzs / maxf(float(pzn), 1.0), "lo": lop}


func viseme_why(d: Dictionary, shown: String, want: String) -> String:
	var s := float(d["scale"])
	var r: Dictionary = RANGES[want]
	var base := mouth_rim(d, d["verts"])
	var mr := mouth_rim(d, FaceGeo.posed(d, vst(shown)))
	var h := float(mr["h"]) * MM / s
	var w := float(mr["w"]) * MM / s
	var p := (float(mr["pz"]) - float(base["pz"])) * MM / s
	var msgs := []
	if h < float(r["h"][0]) or h > float(r["h"][1]):
		msgs.append("aperture %.2f mm outside %s" % [h, str(r["h"])])
	if w < float(r["w"][0]) or w > float(r["w"][1]):
		msgs.append("width %.1f mm outside %s" % [w, str(r["w"])])
	if p < float(r["p"][0]) or p > float(r["p"][1]):
		msgs.append("protrusion %+.1f mm outside %s" % [p, str(r["p"])])
	var extra := viseme_extra_why(d, shown, want)
	if extra != "":
		msgs.append(extra)
	return "; ".join(msgs)


## the viseme-specific contact bars: F/V lip to incisors, L / TH tongue tip
func viseme_extra_why(d: Dictionary, shown: String, want: String) -> String:
	var s := float(d["scale"])
	var tu: Vector3 = d["teeth_up"]
	var vs := FaceGeo.posed(d, vst(shown))
	var mr := mouth_rim(d, vs)
	if want == "FV":
		# the upper incisors' lower edge points: the upper row's vertices lowest in y within the central 12 mm
		var tv: PackedVector3Array = teeth(d, true).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lowest := 9.0
		for v in tv:
			if absf(v.x) < 0.012:
				lowest = minf(lowest, v.y)
		var best := 9.0
		for q in (mr["lo"] as Array):
			for v in tv:
				if absf(v.x) < 0.012 and v.y < lowest + 0.0025:
					best = minf(best, (q as Vector3).distance_to(v))
		if best * MM > 3.5:
			return "the lower lip rim is %.1f mm from the upper incisors (> 3.5)" % (best * MM)
	elif want == "L" or want == "TH":
		var tip := tongue_tip(d, vst(shown))
		var iy_up := tu.y + 0.0004
		if want == "L":
			var front_z := tu.z + 0.006
			var back_z := tu.z + 0.006 - 0.0070 * s
			if tip.y < iy_up - 0.001:
				return "the tongue tip is %.1f mm below the upper incisal edge (it must ride up to it)" % ((iy_up - tip.y) * MM)
			if tip.z > front_z + 0.0005 or tip.z < back_z - 0.004:
				return "the tongue tip z %.1f mm is not behind the upper incisors (%.1f .. %.1f)" % [tip.z * MM, (back_z - 0.004) * MM, front_z * MM]
		else:
			var lipz := float(mouth_rim(d, d["verts"])["pz"])
			if tip.z < lipz - 0.002:
				return "the tongue tip is %.1f mm behind the lip plane (it must reach it)" % ((lipz - tip.z) * MM)
			var jt := FaceGeo.jaw_transform(d, vst(shown))
			var lo_edge: Vector3 = jt * (d["teeth_lo"] as Vector3)
			if tip.y > iy_up + 0.003 or tip.y < lo_edge.y - 0.002:
				return "the tongue tip y %.1f mm is not between the teeth (%.1f .. %.1f)" % [tip.y * MM, (lo_edge.y - 0.002) * MM, (iy_up + 0.003) * MM]
	return ""


## the tongue's front-most point (|x| < 4 mm) in head space for a state
func tongue_tip(d: Dictionary, s: Dictionary) -> Vector3:
	var tv: PackedVector3Array = FaceGeo.tongue_mesh(d).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tf := tongue_tf(d, s)
	var best := Vector3(0, 0, -9)
	for v in tv:
		var q := tf * v
		if absf(q.x) < 0.004 and q.z > best.z:
			best = q
	return best


# ---------------------------------------------------------------- teeth checkers
func weld_key(v: Vector3) -> Vector3i:
	return Vector3i(int(round(v.x * 200000.0)), int(round(v.y * 200000.0)), int(round(v.z * 200000.0)))


## the largest dihedral angle (deg) over edges shared by exactly two triangles, vertices welded by position
func max_dihedral(vs: PackedVector3Array, ix: PackedInt32Array) -> float:
	var edges := {}
	var fn := []
	for t in range(0, ix.size() - 2, 3):
		var a := vs[ix[t]]
		var b := vs[ix[t + 1]]
		var c := vs[ix[t + 2]]
		var n := (b - a).cross(c - a)
		fn.append(n.normalized() if n.length() > 1.0e-14 else Vector3.ZERO)
		for e in 3:
			var k1 := weld_key(vs[ix[t + e]])
			var k2 := weld_key(vs[ix[t + (e + 1) % 3]])
			var key := [k1, k2] if (k1.x < k2.x or (k1.x == k2.x and (k1.y < k2.y or (k1.y == k2.y and k1.z < k2.z)))) else [k2, k1]
			if not edges.has(key):
				edges[key] = []
			(edges[key] as Array).append(t / 3)
	var mx := 0.0
	for key in edges:
		var fl: Array = edges[key]
		if fl.size() != 2:
			continue
		var n1: Vector3 = fn[fl[0]]
		var n2: Vector3 = fn[fl[1]]
		if n1 == Vector3.ZERO or n2 == Vector3.ZERO:
			continue
		mx = maxf(mx, rad_to_deg(acos(clampf(n1.dot(n2), -1.0, 1.0))))
	return mx


## a row of boxes the way the L18 teeth were: six slabs along an arch
func box_row_arrays(d: Dictionary) -> Array:
	var vs := PackedVector3Array()
	var ix := PackedInt32Array()
	var tu: Vector3 = d["teeth_up"]
	var s := float(d["scale"])
	for k in 6:
		var x := (float(k) - 2.5) * 0.0075 * s
		var bm := BoxMesh.new()
		bm.size = Vector3(0.0072 * s, 0.0095 * s, 0.0070 * s)
		var ar := bm.get_mesh_arrays()
		var base := vs.size()
		for v in (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			vs.append(v + Vector3(x, tu.y + 0.005, tu.z))
		for i in (ar[Mesh.ARRAY_INDEX] as PackedInt32Array):
			ix.append(base + i)
	return [vs, ix]


func mesh_arrays(am: ArrayMesh) -> Array:
	var vs := PackedVector3Array()
	var ix := PackedInt32Array()
	var col := PackedColorArray()
	for si in am.get_surface_count():
		var ar := am.surface_get_arrays(si)
		var base := vs.size()
		vs.append_array(ar[Mesh.ARRAY_VERTEX])
		var cl: Variant = ar[Mesh.ARRAY_COLOR]
		if cl != null and (cl as PackedColorArray).size() == (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			col.append_array(cl)
		else:
			for i in (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				col.append(Color(0.94, 0.92, 0.85))
		var ixs: Variant = ar[Mesh.ARRAY_INDEX]
		if ixs != null and (ixs as PackedInt32Array).size() > 0:
			for i in (ixs as PackedInt32Array):
				ix.append(base + i)
		else:
			for i in (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				ix.append(base + i)
	return [vs, ix, col]


func is_pink(c: Color) -> bool:
	return c.r - c.g > 0.22 and c.r - c.b > 0.18


## "" when the gum bar holds: the pink fraction and the side it is on
func gum_why(am: ArrayMesh, upper: bool) -> String:
	var a := mesh_arrays(am)
	var vs: PackedVector3Array = a[0]
	var col: PackedColorArray = a[2]
	var np := 0
	var yp := 0.0
	var yc := 0.0
	var nc := 0
	for i in vs.size():
		if is_pink(col[i]):
			np += 1
			yp += vs[i].y
		else:
			nc += 1
			yc += vs[i].y
	var fr := float(np) / maxf(float(vs.size()), 1.0)
	if fr < 0.12 or fr > 0.45:
		return "pink fraction %.2f outside 0.12 .. 0.45" % fr
	var side := yp / float(np) - yc / maxf(float(nc), 1.0)
	if (side <= 0.0) if upper else (side >= 0.0):
		return "the gum is on the wrong side of the crowns (%+.1f mm)" % (side * MM)
	return ""


# ---------------------------------------------------------------- the studio
func make_studio(d: Dictionary, head_pts: PackedVector3Array, o := {}) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(o.get("size", 512)), int(o.get("size", 512)))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BGC
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
	vp.add_child(cam)
	cam.current = true
	var hide: Array = o.get("hide", [])
	var parts := {}
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = SKIN0
	hmat.roughness = 0.85
	if o.get("full_head", false):
		var sm0 := SurfaceTool.new()
		sm0.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in head_pts:
			sm0.add_vertex(v)
		sm0.index()
		sm0.generate_normals()
		var hf := MeshInstance3D.new()
		hf.mesh = sm0.commit()
		var um := StandardMaterial3D.new()
		um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		um.albedo_color = Color(1, 1, 1)
		hf.material_override = um
		vp.add_child(hf)
		return {"vp": vp, "cam": cam, "parts": parts}
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in head_pts:
		sm.add_vertex(v)
	sm.index()
	sm.generate_normals()
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = FaceGeo.cut_head(sm.commit(), d)
	head_mi.material_override = hmat
	vp.add_child(head_mi)
	var mask_mi := MeshInstance3D.new()
	mask_mi.material_override = FaceGeo.mask_material(hmat)
	vp.add_child(mask_mi)
	var eye_nodes := []
	for e in d["eyes"]:
		var en := MeshInstance3D.new()
		en.mesh = FaceGeo.eye_mesh(float(e["r"]))
		en.material_override = FaceGeo.eye_material()
		vp.add_child(en)
		eye_nodes.append(en)
	var cav := MeshInstance3D.new()
	cav.mesh = FaceGeo.cavity_mesh(d)
	if o.get("cav_magenta", false):
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color(1, 0, 1)
		mm.cull_mode = BaseMaterial3D.CULL_FRONT   # as the real cavity material: the inside of the vault
		cav.material_override = mm
	else:
		cav.material_override = FaceGeo.cavity_material()
	cav.visible = not hide.has("cavity")
	vp.add_child(cav)
	parts["cavity"] = cav
	for nm in ["teeth_up", "teeth_lo", "tongue", "nose"]:
		var mi := MeshInstance3D.new()
		match nm:
			"teeth_up":
				mi.mesh = teeth(d, true)
				mi.material_override = FaceGeo.tooth_material()
			"teeth_lo":
				mi.mesh = teeth(d, false)
				mi.material_override = FaceGeo.tooth_material()
			"tongue":
				mi.mesh = FaceGeo.tongue_mesh(d)
				mi.material_override = FaceGeo.tongue_material()
			"nose":
				mi.mesh = FaceGeo.nose_mesh(d, SKIN0)
				mi.material_override = FaceGeo.mask_material(hmat)
		mi.visible = not hide.has(nm)
		vp.add_child(mi)
		parts[nm] = mi
	if FG.has_method("head_parts"):
		for pd in FG.call("head_parts", d, SKIN0):
			var mi2 := MeshInstance3D.new()
			mi2.mesh = pd["mesh"]
			mi2.material_override = FaceGeo.mask_material(hmat)
			mi2.visible = not hide.has(String(pd["name"]))
			mi2.name = String(pd["name"])
			vp.add_child(mi2)
			parts[String(pd["name"])] = mi2
	if FG.has_method("chin_mesh"):
		var cm := MeshInstance3D.new()
		cm.name = "chin"
		cm.material_override = FaceGeo.mask_material(hmat)
		cm.visible = not hide.has("chin")
		vp.add_child(cm)
		parts["chin"] = cm
	if o.get("teeth_white", false):
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.albedo_color = Color(1, 1, 1)
		(parts["teeth_up"] as MeshInstance3D).material_override = wm
		(parts["teeth_lo"] as MeshInstance3D).material_override = wm
	if o.get("only_teeth", false):
		head_mi.visible = false
		mask_mi.visible = false
		cav.visible = false
		(parts["tongue"] as MeshInstance3D).visible = false
		(parts["nose"] as MeshInstance3D).visible = false
		for en in eye_nodes:
			(en as MeshInstance3D).visible = false
	return {"vp": vp, "cam": cam, "mask": mask_mi, "eyes": eye_nodes, "parts": parts, "head": head_mi}


func frame(s: Dictionary, centre: Vector3, dist: float, fov: float, yaw_deg := 0.0, pitch_deg := 0.0) -> void:
	var cam: Camera3D = s["cam"]
	cam.fov = fov
	var cp := cos(deg_to_rad(pitch_deg))
	var dirv := Vector3(sin(deg_to_rad(yaw_deg)) * cp, sin(deg_to_rad(pitch_deg)), cos(deg_to_rad(yaw_deg)) * cp)
	cam.position = centre + dirv * dist
	cam.look_at(centre, Vector3.UP)


func shot(s: Dictionary, d: Dictionary, state: Dictionary) -> Image:
	if s.has("mask"):
		var vs := FaceGeo.posed(d, state)
		(s["mask"] as MeshInstance3D).mesh = FaceGeo.mask_mesh(d, vs, SKIN0)
		var tf := FaceGeo.eye_transforms(d, state)
		for i in 2:
			(s["eyes"][i] as MeshInstance3D).transform = tf[i]
		var jx: Transform3D = FaceGeo.jaw_transform(d, state)
		(s["parts"]["teeth_lo"] as MeshInstance3D).transform = jx
		(s["parts"]["tongue"] as MeshInstance3D).transform = tongue_tf(d, state)
		if s["parts"].has("chin"):
			(s["parts"]["chin"] as MeshInstance3D).mesh = FG.call("chin_mesh", d, state, SKIN0)
	await idle(3)
	await RenderingServer.frame_post_draw
	return (s["vp"] as SubViewport).get_texture().get_image()


func screen(s: Dictionary, p: Vector3) -> Vector2:
	return (s["cam"] as Camera3D).unproject_position(p)


func is_bg(c: Color) -> bool:
	return c.g > 0.95 and c.r < 0.06 and c.b < 0.06


func is_magenta(c: Color) -> bool:
	return c.r > 0.9 and c.b > 0.9 and c.g < 0.1


func is_white(c: Color) -> bool:
	return c.r > 0.95 and c.g > 0.95 and c.b > 0.95


## the bounding box (Rect2i) of the magenta pixels, or an empty rect
func magenta_box(img: Image) -> Rect2i:
	var mn := Vector2i(1 << 20, 1 << 20)
	var mx := Vector2i(-1, -1)
	for y in img.get_height():
		for x in img.get_width():
			if is_magenta(img.get_pixel(x, y)):
				mn = Vector2i(mini(mn.x, x), mini(mn.y, y))
				mx = Vector2i(maxi(mx.x, x), maxi(mx.y, y))
	if mx.x < 0:
		return Rect2i()
	return Rect2i(mn, mx - mn + Vector2i.ONE)


func bg_in_poly(img: Image, poly: PackedVector2Array) -> int:
	var inner := Geometry2D.offset_polygon(poly, -2.0)
	if inner.is_empty():
		return 0
	var pl: PackedVector2Array = inner[0]
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for v in pl:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	var n := 0
	for y in range(maxi(int(mn.y), 0), mini(int(mx.y) + 1, img.get_height())):
		for x in range(maxi(int(mn.x), 0), mini(int(mx.x) + 1, img.get_width())):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pl) and is_bg(img.get_pixel(x, y)):
				n += 1
	return n


## the screen polygon (px) of the mouth rim loop for a state
func mouth_poly(s: Dictionary, d: Dictionary, state: Dictionary) -> PackedVector2Array:
	var vs := FaceGeo.posed(d, state)
	var rim: PackedByteArray = d["rim"]
	var pts := PackedVector2Array()
	var list := []
	for i in vs.size():
		if rim[i] == 3:
			list.append(i)
	# order by angle round the centroid (the rim is a convex-ish lens)
	var c := Vector2.ZERO
	for i in list:
		c += screen(s, vs[i])
	c /= maxf(float(list.size()), 1.0)
	list.sort_custom(func(a, b): return (screen(s, vs[a]) - c).angle() < (screen(s, vs[b]) - c).angle())
	for i in list:
		pts.append(screen(s, vs[i]))
	return pts


# ---------------------------------------------------------------- silhouette holes
func erode_bg_count(full: Image, geo: Image) -> int:
	hole_c = Vector2.ZERO
	var w := full.get_width()
	var h := full.get_height()
	var n := 0
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			if is_bg(geo.get_pixel(x, y)) and not is_bg(full.get_pixel(x, y)):
				var inside := true
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						if is_bg(full.get_pixel(x + dx, y + dy)):
							inside = false
							break
					if not inside:
						break
				if inside:
					n += 1
					hole_c += Vector2(x, y)
	hole_c /= maxf(float(n), 1.0)
	return n


## the pixels of enclosed background holes (background not 4-connected to the border): a boolean grid as PackedByteArray
func holes_of(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var bg := PackedByteArray()
	bg.resize(w * h)
	for y in h:
		for x in w:
			bg[y * w + x] = 1 if is_bg(img.get_pixel(x, y)) else 0
	var reach := PackedByteArray()
	reach.resize(w * h)
	var q := PackedInt32Array()
	for x in w:
		for yy in [0, h - 1]:
			if bg[yy * w + x] == 1 and reach[yy * w + x] == 0:
				reach[yy * w + x] = 1
				q.append(yy * w + x)
	for y in h:
		for xx in [0, w - 1]:
			if bg[y * w + xx] == 1 and reach[y * w + xx] == 0:
				reach[y * w + xx] = 1
				q.append(y * w + xx)
	var qh := 0
	while qh < q.size():
		var p := q[qh]
		qh += 1
		var px := p % w
		var py := p / w
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := px + (dd as Vector2i).x
			var ny := py + (dd as Vector2i).y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni := ny * w + nx
			if bg[ni] == 1 and reach[ni] == 0:
				reach[ni] = 1
				q.append(ni)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 1 if (bg[i] == 1 and reach[i] == 0) else 0
	return out


## enclosed holes of `geo` that lie farther than 3 px from any enclosed hole of the bare head
var hole_c := Vector2.ZERO


func extra_holes(geo: Image, full: Image) -> int:
	hole_c = Vector2.ZERO
	var w := geo.get_width()
	var hg := holes_of(geo)
	var hf := holes_of(full)
	var n := 0
	for y in range(3, geo.get_height() - 3):
		for x in range(3, w - 3):
			if hg[y * w + x] == 1:
				var near := false
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						if hf[(y + dy) * w + x + dx] == 1:
							near = true
							break
					if near:
						break
				if not near:
					n += 1
					hole_c += Vector2(x, y)
	hole_c /= maxf(float(n), 1.0)
	return n


# ---------------------------------------------------------------- ears
## the head's side x at (y, z): the topmost x of the triangle soup swizzled to (z, y, side * x); -1e9 off the head
func side_pts(head_pts: PackedVector3Array, sgn: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in head_pts:
		out.append(Vector3(v.z, v.y, sgn * v.x))
	return out


func z_at(tris: PackedVector3Array, bb: PackedFloat32Array, x: float, y: float) -> float:
	var best := -1.0e9
	for t in range(0, tris.size() - 2, 3):
		var k := (t / 3) * 4
		if x < bb[k] or x > bb[k + 1] or y < bb[k + 2] or y > bb[k + 3]:
			continue
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1.0e-14:
			continue
		var l1 := ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / den
		var l2 := ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / den
		var l3 := 1.0 - l1 - l2
		if l1 >= -1.0e-6 and l2 >= -1.0e-6 and l3 >= -1.0e-6:
			best = maxf(best, l1 * a.z + l2 * b.z + l3 * c.z)
	return best


func bboxes(tris: PackedVector3Array) -> PackedFloat32Array:
	var bb := PackedFloat32Array()
	for t in range(0, tris.size() - 2, 3):
		bb.append(minf(tris[t].x, minf(tris[t + 1].x, tris[t + 2].x)))
		bb.append(maxf(tris[t].x, maxf(tris[t + 1].x, tris[t + 2].x)))
		bb.append(minf(tris[t].y, minf(tris[t + 1].y, tris[t + 2].y)))
		bb.append(maxf(tris[t].y, maxf(tris[t + 1].y, tris[t + 2].y)))
	return bb


## the ear bars as a function over an ear's vertex array (head space) for the side `sd` (+1 left = +x): "" when they hold
## sp / sbb: the swizzled side soup of the head for that side
func ear_why(d: Dictionary, vs: PackedVector3Array, sd: float, sp: PackedVector3Array, sbb: PackedFloat32Array, which: String) -> String:
	var s := float(d["scale"])
	var an: Dictionary = d["anchors"]
	var ymin := 9.0
	var ymax := -9.0
	var zmin := 9.0
	var zmax := -9.0
	for v in vs:
		ymin = minf(ymin, v.y)
		ymax = maxf(ymax, v.y)
		zmin = minf(zmin, v.z)
		zmax = maxf(zmax, v.z)
	var len_mm := (ymax - ymin) * MM
	var wid_mm := (zmax - zmin) * MM
	var by := float((an["brow_l"] as Vector3).y)
	var ez := float((an["eye_l"] as Vector3).z)
	var msgs := []
	if which == "all" or which == "E1":
		if absf(len_mm - 60.0 * s) > 0.08 * 60.0 * s:
			msgs.append("E1 length %.1f mm (60 x s = %.1f +- 8 %%)" % [len_mm, 60.0 * s])
	if which == "all" or which == "E2":
		if absf(ymax - by) > 0.006 * s:
			msgs.append("E2 the top is %+.1f mm from the brow line" % ((ymax - by) * MM))
	if which == "all" or which == "E3":
		var fz := ez - zmax
		if absf(fz * MM - 85.0 * s) > 15.0:
			msgs.append("E3 the front edge is %.1f mm behind the eye (85 x s +- 15)" % (fz * MM))
		if absf(wid_mm - 33.0 * s) > 0.15 * 33.0 * s:
			msgs.append("E3 width %.1f mm (33 x s +- 15 %%)" % wid_mm)
	var stand := PackedFloat32Array()
	if which == "all" or which == "E4" or which == "E6" or which == "E7":
		for v in vs:
			var hx := z_at(sp, sbb, v.z, v.y)
			stand.append(sd * v.x - hx if hx > -1.0e8 else 9.0)
	if which == "all" or which == "E4":
		var near := 0
		var buried := 0.0
		var far := -9.0
		for q in stand:
			if absf(q) <= 0.0015:
				near += 1
			buried = minf(buried, q)
			if q < 8.0:
				far = maxf(far, q)
		if float(near) / maxf(float(vs.size()), 1.0) < 0.03:
			msgs.append("E4 only %d of %d vertices touch the head" % [near, vs.size()])
		if buried < -0.0025:
			msgs.append("E4 buried %.1f mm in the head" % (-buried * MM))
		if far * MM < 8.0 or far * MM > 28.0:
			msgs.append("E4 farthest point %.1f mm out (8 .. 28)" % (far * MM))
	if which == "all" or which == "E6":
		var y0 := ymax - 0.55 * (ymax - ymin)
		var nb := int(ceil((zmax - zmin) / 0.001)) + 1
		var prof := PackedFloat32Array()
		prof.resize(nb)
		prof.fill(-1.0)
		for i in vs.size():
			if absf(vs[i].y - y0) < 0.0015:
				var bi := int((vs[i].z - zmin) / 0.001)
				prof[bi] = maxf(prof[bi], stand[i])
		# fill holes in the profile by neighbours, then count ridges with prominence >= 1 mm
		for i in nb:
			if prof[i] < -0.5:
				var a := i - 1
				while a >= 0 and prof[a] < -0.5:
					a -= 1
				var b := i + 1
				while b < nb and prof[b] < -0.5:
					b += 1
				prof[i] = prof[a] if a >= 0 and b >= nb else (prof[b] if a < 0 and b < nb else (lerpf(prof[a], prof[b], float(i - a) / float(b - a)) if a >= 0 and b < nb else 0.0))
		var ridges := 0
		for i in range(1, nb - 1):
			if prof[i] >= prof[i - 1] and prof[i] > prof[i + 1]:
				var lmin := prof[i]
				for j in range(i - 1, -1, -1):
					lmin = minf(lmin, prof[j])
					if prof[j] > prof[i]:
						break
				var rmin := prof[i]
				for j in range(i + 1, nb):
					rmin = minf(rmin, prof[j])
					if prof[j] > prof[i]:
						break
				if prof[i] - maxf(lmin, rmin) >= 0.001:
					ridges += 1
		if ridges < 2:
			msgs.append("E6 %d ridge(s) across the ear (helix + antihelix = 2 wanted)" % ridges)
	if which == "all" or which == "E7":
		var lim := ymin + 0.20 * (ymax - ymin)
		var sum := 0.0
		var n := 0
		var lz0 := 9.0
		var lz1 := -9.0
		for i in vs.size():
			if vs[i].y <= lim:
				sum += stand[i]
				n += 1
				if stand[i] > 0.002:
					lz0 = minf(lz0, vs[i].z)
					lz1 = maxf(lz1, vs[i].z)
		if n == 0 or sum / float(n) < 0.003 or (lz1 - lz0) * MM < 8.0 * s:
			msgs.append("E7 the lobe: mean standoff %.1f mm, width %.1f mm" % [(sum / maxf(float(n), 1.0)) * MM, maxf(lz1 - lz0, 0.0) * MM])
	return "; ".join(msgs)


# ---------------------------------------------------------------- the run
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
	var s := float(d["scale"])
	var my := float((an["mouth"] as Vector3).y)
	print("scale s = %.4f, mask %d vertices" % [s, (d["verts"] as PackedVector3Array).size()])

	# ---------------- O: the open mouth
	var open_au := {"AU25": 1.0, "AU26": 1.0}
	var vs0: PackedVector3Array = d["verts"]
	var r0 := mouth_rim(d, vs0)
	var r1 := mouth_rim(d, FaceGeo.posed(d, st(open_au)))
	var inc := FaceGeo.incisal_mm(d, FaceGeo.JAW_MAX_DEG)
	var h1 := float(r1["h"]) * MM
	var w0 := float(r0["w"]) * MM
	var w1 := float(r1["w"]) * MM
	ok(h1 >= 40.0 and h1 <= 50.0 and absf(h1 - inc) <= 0.10 * inc, "O1 the open mouth's lip aperture is %.1f mm (40 .. 50) and within 10 %% of the incisal opening %.1f mm" % [h1, inc])
	ok(absf(w0 - 52.0 * s) <= 0.10 * 52.0 * s and w1 >= 0.80 * w0 and w1 <= 0.99 * w0, "O2 the neutral width %.1f mm is near 52 x s = %.1f and the open mouth narrows to %.1f mm (%.2f of it, bar 0.80 .. 0.99)" % [w0, 52.0 * s, w1, w1 / w0])
	var r36 := mouth_rim(d, FaceGeo.posed(d, st({"AU25": 1.0}, 36.0)))
	var h36 := float(r36["h"]) * MM
	ok(not (h36 >= 40.0 and h36 <= 50.0 and absf(h36 - inc) <= 0.10 * inc), "O1 CONTROL the jaw driven to 36 deg opens %.1f mm: outside the band, caught" % h36)

	# the renders: frontal close view of the open mouth
	var s_mag := await make_studio(d, head_pts, {"cav_magenta": true, "hide": ["teeth_up", "teeth_lo", "tongue"]})
	var s_nocav := await make_studio(d, head_pts, {"cav_magenta": true, "hide": ["teeth_up", "teeth_lo", "tongue", "cavity"]})
	var s_lit := await make_studio(d, head_pts, {})
	var s_lit_nc := await make_studio(d, head_pts, {"hide": ["cavity"]})
	var mc := Vector3(0, my - 0.020, 0.12)
	for ss in [s_mag, s_nocav, s_lit, s_lit_nc]:
		frame(ss, mc, 0.45, 12.0)
	var open := st(open_au)
	var img_m: Image = await shot(s_mag, d, open)
	var lip_z := float(r1["pz"])
	var p_a := screen(s_mag, Vector3(-0.02, my, lip_z))
	var p_b := screen(s_mag, Vector3(0.02, my, lip_z))
	var pxmm := p_a.distance_to(p_b) / 40.0
	var box := magenta_box(img_m)
	if OS.get_environment("FACE_GEO3_SHOT") != "":
		img_m.save_png(OS.get_environment("FACE_GEO3_SHOT") + "_mag.png")
	var hmm := float(box.size.y) / pxmm
	var wmm := float(box.size.x) / pxmm
	ok(box.size.x > 0 and absf(hmm - h1) <= 0.10 * h1 and absf(wmm - w1) <= 0.10 * w1, "O3 render: the cavity box is %.1f x %.1f mm (%d x %d px at %.2f px/mm), the opening %.1f x %.1f mm: within 10 %%" % [wmm, hmm, box.size.x, box.size.y, pxmm, w1, h1])
	var img_nc: Image = await shot(s_nocav, d, open)
	var box_nc := magenta_box(img_nc)
	ok(not (box_nc.size.x > 0 and absf(float(box_nc.size.y) / pxmm - h1) <= 0.10 * h1), "O3 CONTROL the cavity hidden: the magenta box is %d x %d px, caught" % [box_nc.size.x, box_nc.size.y])
	var img_36: Image = await shot(s_mag, d, st({"AU25": 1.0}, 36.0))
	var box36 := magenta_box(img_36)
	ok(not (absf(float(box36.size.y) / pxmm - h1) <= 0.10 * h1), "O3 CONTROL the jaw at 36 deg: the box is %.1f mm high against the %.1f mm opening, caught" % [float(box36.size.y) / pxmm, h1])
	var img_l: Image = await shot(s_lit, d, open)
	var poly := mouth_poly(s_lit, d, open)
	var bgn := bg_in_poly(img_l, poly)
	ok(bgn == 0, "O4 render: %d background pixels inside the open mouth (0 wanted)" % bgn)
	var img_lnc: Image = await shot(s_lit_nc, d, open)
	var bgn_nc := bg_in_poly(img_lnc, mouth_poly(s_lit_nc, d, open))
	ok(bgn_nc > 0, "O4 CONTROL the cavity hidden: %d background pixels inside the opening, caught" % bgn_nc)

	# ---------------- T: teeth
	for up in [true, false]:
		var nm := "upper" if up else "lower"
		var a := mesh_arrays(teeth(d, up))
		var dh := max_dihedral(a[0], a[1])
		ok(dh <= 55.0, "T1 the %s row's crowns are rounded: largest dihedral angle %.1f deg (<= 55)" % [nm, dh])
	var boxes := box_row_arrays(d)
	var dh_box := max_dihedral(boxes[0], boxes[1])
	ok(dh_box > 55.0, "T1 CONTROL a row of box slabs has a %.1f deg edge: caught" % dh_box)
	var s_t := await make_studio(d, head_pts, {"only_teeth": true, "teeth_white": true})
	for up in [true, false]:
		var nm2 := "upper" if up else "lower"
		var tu: Vector3 = d["teeth_up"]
		var cz := tu.z + 0.006
		var edge_y := (tu.y + 0.0004) if up else (tu.y - 0.0006)
		var sgn := 1.0 if up else -1.0
		var cen := Vector3(0, edge_y + sgn * 0.005, cz)
		frame(s_t, cen, 0.30, 14.0)
		(s_t["parts"]["teeth_up"] as MeshInstance3D).visible = up
		(s_t["parts"]["teeth_lo"] as MeshInstance3D).visible = not up
		var img_t: Image = await shot(s_t, d, st())
		var gm := teeth_gap_stats(s_t, img_t, edge_y, sgn, cz, s)
		ok(float(gm["span"]) >= 33.0 and float(gm["gap"]) <= 0.10 * 8.5 * s, "T2 render: the %s row spans %.1f mm and its widest gap between teeth is %.2f mm (<= %.2f = 0.10 x a central incisor)" % [nm2, gm["span"], gm["gap"], 0.10 * 8.5 * s])
		# CONTROL: the crowns shrunk to 0.8 of their width
		if arity("teeth_mesh") >= 3:
			(s_t["parts"]["teeth_up" if up else "teeth_lo"] as MeshInstance3D).mesh = teeth(d, up, {"crown_w": 0.80})
			var img_tn: Image = await shot(s_t, d, st())
			var gn := teeth_gap_stats(s_t, img_tn, edge_y, sgn, cz, s)
			ok(not (float(gn["span"]) >= 33.0 and float(gn["gap"]) <= 0.10 * 8.5 * s), "T2 CONTROL the %s crowns at 0.8 of their width: gap %.2f mm, caught" % [nm2, gn["gap"]])
			(s_t["parts"]["teeth_up" if up else "teeth_lo"] as MeshInstance3D).mesh = teeth(d, up)
		else:
			ok(false, "T2 CONTROL needs teeth_mesh(d, upper, opts) with opts crown_w")
		var gw := gum_why(teeth(d, up), up)
		ok(gw == "", "T3 the %s row has its gum line %s" % [nm2, gw])
		if arity("teeth_mesh") >= 3:
			var gw0 := gum_why(teeth(d, up, {"gum": false}), up)
			ok(gw0 != "", "T3 CONTROL the %s row with no gum: %s" % [nm2, gw0])
		else:
			ok(false, "T3 CONTROL needs teeth_mesh(d, upper, opts) with opts gum")

	# ---------------- V: visemes
	var tab: Dictionary = d["au"]
	var vmiss := []
	var vbad := []
	for k in VIS_AUS:
		if not tab.has(k):
			vmiss.append(k)
			continue
		var dl: PackedVector3Array = tab[k]
		var mouth_max := 0.0
		var far_max := 0.0
		for i in dl.size():
			var dy := vs0[i].y - my
			if absf(dy) < 0.02:
				mouth_max = maxf(mouth_max, dl[i].length())
			if dy > 0.04:
				far_max = maxf(far_max, dl[i].length())
		if dl.size() != vs0.size() or mouth_max < 0.0008 or far_max > 0.0:
			vbad.append("%s (n %d, mouth max %.2f mm, far max %.3f mm)" % [k, dl.size(), mouth_max * MM, far_max * MM])
	ok(vmiss.is_empty() and vbad.is_empty(), "V0 the viseme AUs are blendshapes, nonzero in the mouth zone and zero 4 cm above it (missing %s, bad %s)" % [str(vmiss), str(vbad)])
	var tab_c := tab.duplicate()
	tab_c["AU18"] = PackedVector3Array()
	ok(tab_c.has("AU18") and (tab_c["AU18"] as PackedVector3Array).size() != vs0.size(), "V0 CONTROL an empty blendshape has the wrong size: caught")
	var names := ["rest", "A", "E", "I", "O", "U", "MBP", "FV", "L", "TH"]
	for nm3 in names:
		var why: String = viseme_why(d, nm3, nm3)
		ok(why == "", "V1 %s: aperture, width, protrusion in the cited range %s" % [nm3, why])
		var ctl: String = CONTROL[nm3]
		var why_c: String = viseme_why(d, ctl, nm3)
		ok(why_c != "", "V1 CONTROL the %s pose against the %s range: %s" % [ctl, nm3, why_c])
	var ok_alias := true
	if FG.has_method("viseme_pose"):
		for al in ["M", "B", "P", "F", "V", "S"]:
			var pz: Dictionary = FG.call("viseme_pose", al)
			if pz.is_empty() or not pz.has("au"):
				ok_alias = false
		ok_alias = ok_alias and (FG.call("viseme_pose", "Q") as Dictionary).is_empty()
	else:
		ok_alias = false
	ok(ok_alias, "V2 the lip-sync letters M B P F V S map to a pose, an unknown name does not")

	# ---------------- E: ears
	var ears: Array = d.get("ears", [])
	ok(ears.size() == 2, "E0 d[ears] has the two ears (%d)" % ears.size())
	if ears.size() == 2:
		var sps := [side_pts(head_pts, 1.0), side_pts(head_pts, -1.0)]
		var sbbs := [bboxes(sps[0]), bboxes(sps[1])]
		for k in 2:
			var e: Dictionary = ears[k]
			var sd := 1.0 if String(e["side"]) == "l" else -1.0
			var ev: PackedVector3Array = e["verts"]
			var kk := 0 if sd > 0.0 else 1
			var why_e := ear_why(d, ev, sd, sps[kk], sbbs[kk], "all")
			ok(why_e == "", "E1-E7 the %s ear: %s" % [e["side"], why_e if why_e != "" else "length, brow level, front edge, head side, helix + antihelix, lobe all hold"])
		var e0: Dictionary = ears[0]
		var ev0: PackedVector3Array = e0["verts"]
		var sp0: PackedVector3Array = sps[0]
		var bb0: PackedFloat32Array = sbbs[0]
		# E5 mirror
		var ev1: PackedVector3Array = (ears[1] as Dictionary)["verts"]
		var mirror_err := 0.0
		if ev0.size() == ev1.size():
			for i in ev0.size():
				mirror_err = maxf(mirror_err, maxf(absf(ev0[i].x + ev1[i].x), maxf(absf(ev0[i].y - ev1[i].y), absf(ev0[i].z - ev1[i].z))))
		else:
			mirror_err = 9.0
		ok(mirror_err <= 0.0015, "E5 the two ears mirror: worst vertex mismatch %.2f mm (<= 1.5)" % (mirror_err * MM))
		var mir_bad := ev0.duplicate()
		for i in mir_bad.size():
			mir_bad[i] = mir_bad[i] + Vector3(0.0, 0.0, 0.004)
		var me2 := 0.0
		if ev0.size() == ev1.size():
			for i in ev0.size():
				me2 = maxf(me2, maxf(absf(mir_bad[i].x + ev1[i].x), maxf(absf(mir_bad[i].y - ev1[i].y), absf(mir_bad[i].z - ev1[i].z))))
		ok(me2 > 0.0015, "E5 CONTROL one ear shifted 4 mm: mismatch %.2f mm, caught" % (me2 * MM))
		# controls on the left ear
		var flat := ev0.duplicate()
		for i in flat.size():
			var hx := z_at(sp0, bb0, flat[i].z, flat[i].y)
			flat[i] = Vector3((hx if hx > -1.0e8 else flat[i].x) + 0.012, flat[i].y, flat[i].z)
		ok(ear_why(d, flat, 1.0, sp0, bb0, "E6") != "", "E6 CONTROL a flat ear (every vertex 12 mm out): %s" % ear_why(d, flat, 1.0, sp0, bb0, "E6"))
		var down := ev0.duplicate()
		var longer := ev0.duplicate()
		var buried := ev0.duplicate()
		var fwd := ev0.duplicate()
		var cy0 := 0.0
		for v in ev0:
			cy0 += v.y
		cy0 /= float(ev0.size())
		for i in ev0.size():
			down[i] = ev0[i] + Vector3(0, -0.04, 0)
			longer[i] = Vector3(ev0[i].x, cy0 + (ev0[i].y - cy0) * 1.5, ev0[i].z)
			fwd[i] = ev0[i] + Vector3(0, 0, 0.05)
			var hx2 := z_at(sp0, bb0, ev0[i].z, ev0[i].y)
			buried[i] = ev0[i] + Vector3(-0.012, 0, 0)
		ok(ear_why(d, down, 1.0, sp0, bb0, "E2") != "", "E2 CONTROL the ear 4 cm down: %s" % ear_why(d, down, 1.0, sp0, bb0, "E2"))
		ok(ear_why(d, longer, 1.0, sp0, bb0, "E1") != "", "E1 CONTROL the ear 1.5 x as long: %s" % ear_why(d, longer, 1.0, sp0, bb0, "E1"))
		ok(ear_why(d, buried, 1.0, sp0, bb0, "E4") != "", "E4 CONTROL the ear pushed 12 mm into the head: %s" % ear_why(d, buried, 1.0, sp0, bb0, "E4"))
		ok(ear_why(d, fwd, 1.0, sp0, bb0, "E3") != "", "E3 CONTROL the ear 5 cm forward: %s" % ear_why(d, fwd, 1.0, sp0, bb0, "E3"))
		var ymn := 9.0
		var ymx := -9.0
		for v in ev0:
			ymn = minf(ymn, v.y)
			ymx = maxf(ymx, v.y)
		var nolobe := ev0.duplicate()
		for i in nolobe.size():
			if nolobe[i].y <= ymn + 0.20 * (ymx - ymn):
				var hx3 := z_at(sp0, bb0, nolobe[i].z, nolobe[i].y)
				nolobe[i] = Vector3((hx3 if hx3 > -1.0e8 else nolobe[i].x) + 0.0005, nolobe[i].y, nolobe[i].z)
		ok(ear_why(d, nolobe, 1.0, sp0, bb0, "E7") != "", "E7 CONTROL the lobe flattened to the skin: %s" % ear_why(d, nolobe, 1.0, sp0, bb0, "E7"))

	# ---------------- C: the chin
	var s_full := await make_studio(d, head_pts, {"full_head": true, "size": 384})
	var s_geo := await make_studio(d, head_pts, {"size": 384})
	var s_nochin := await make_studio(d, head_pts, {"size": 384, "hide": ["chin"]})
	var cc := Vector3(0, float(an["chin"]) + 0.03, 0.05)
	for yaw in [0.0, 35.0]:
		for ss in [s_full, s_geo, s_nochin]:
			frame(ss, cc, 0.45, 26.0, yaw, -32.0)
		var img_f: Image = await shot(s_full, d, st())
		var img_g: Image = await shot(s_geo, d, st())
		var holes := erode_bg_count(img_f, img_g)
		ok(holes == 0, "C1 low camera (32 deg below, yaw %d): %d background pixels inside the bare head's silhouette (0 wanted; at %s)" % [int(yaw), holes, str(hole_c)])
		if holes > 0 and OS.get_environment("FACE_GEO3_SHOT") != "":
			img_g.save_png(OS.get_environment("FACE_GEO3_SHOT") + "_c1_%d.png" % int(yaw))
		var img_nc2: Image = await shot(s_nochin, d, st())
		var holes_nc := erode_bg_count(img_f, img_nc2)
		ok(holes_nc > 0, "C1 CONTROL (yaw %d) without the chin part: %d background pixels inside the silhouette, caught" % [int(yaw), holes_nc])
	for jaw_s in [st({"AU25": 1.0, "AU26": 1.0}), st({}, 11.0)]:
		for ss in [s_full, s_geo]:
			frame(ss, cc, 0.45, 26.0, 0.0, -32.0)
		var img_f2: Image = await shot(s_full, d, st())
		var img_g2: Image = await shot(s_geo, d, jaw_s)
		var xh := extra_holes(img_g2, img_f2)
		ok(xh == 0, "C2 low camera, jaw %.1f deg + AU26 %.1f: %d enclosed background pixels the bare head does not have (0 wanted; centroid %s)" % [float(jaw_s["jaw_deg"]), float((jaw_s["au"] as Dictionary).get("AU26", 0.0)), xh, str(hole_c)])
		if xh > 0 and OS.get_environment("FACE_GEO3_SHOT") != "":
			img_g2.save_png(OS.get_environment("FACE_GEO3_SHOT") + "_hole%d.png" % int(float(jaw_s["jaw_deg"])))
	# C3 the seam: the chin part follows the mask's jaw. The mask's lowest vertex of each column (|x| < 30 mm) and the nearest vertex of
	# the chin part stay within 15 mm of each other with the jaw open; CONTROL the chin part left at neutral (40+ mm apart)
	if FG.has_method("chin_mesh"):
		var st_open := st({"AU25": 1.0, "AU26": 1.0})
		var mv_open := FaceGeo.posed(d, st_open)
		var low := {}
		for i in mv_open.size():
			var x0: float = vs0[i].x
			if absf(x0) < 0.03:
				var key := int(round(x0 * 1000.0))
				if not low.has(key) or mv_open[i].y < (low[key] as Vector3).y:
					low[key] = mv_open[i]
		var seam_ok := {}
		for which in ["follows", "neutral"]:
			var cm: ArrayMesh = FG.call("chin_mesh", d, st_open if which == "follows" else st(), SKIN0)
			var cv: PackedVector3Array = cm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var worst := 0.0
			for key in low:
				var best := 9.0
				for q in cv:
					best = minf(best, (low[key] as Vector3).distance_to(q))
				worst = maxf(worst, best)
			seam_ok[which] = worst * MM
		ok(float(seam_ok["follows"]) <= 15.0, "C3 the chin part follows the jaw: the mask's lower rim is %.1f mm from it with the jaw open (<= 15)" % float(seam_ok["follows"]))
		ok(float(seam_ok["neutral"]) > 15.0, "C3 CONTROL the chin part left at neutral: %.1f mm apart (> 15), caught" % float(seam_ok["neutral"]))
	else:
		ok(false, "C3 needs the chin part")

	# ---------------- P: the app
	var tgl_ok := true
	m._face_geo_set(true)
	await idle(3)
	var root_names := []
	for ch in m.face_geo_root.get_children():
		root_names.append(String(ch.name))
	var need := ["ear_l", "ear_r", "chin"]
	var miss2 := []
	for w in need:
		if not root_names.has(w):
			miss2.append(w)
	ok(miss2.is_empty(), "P1 the app's face geometry has the ears and the chin part (missing %s)" % str(miss2))
	if "face_geo_viseme" in m:
		var mk := {}
		for vn in ["MBP", "O", "rest"]:
			m.face_geo_viseme = vn
			m.face_geo_key = ""
			m._refresh()
			await idle(3)
			var mesh := m.face_geo_mask.mesh as ArrayMesh
			var mv: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			mk[vn] = float(mouth_rim(d, mv)["h"]) * MM
		ok(float(mk.get("MBP", 9.0)) <= 0.05 and float(mk.get("O", 0.0)) >= 8.0, "P2 the app's viseme override reaches the mask: MBP aperture %.2f mm, O %.1f mm, rest %.2f mm" % [float(mk.get("MBP", 9.0)), float(mk.get("O", 0.0)), float(mk.get("rest", 0.0))])
		m.face_geo_viseme = ""
	else:
		ok(false, "P2 main.gd has no face_geo_viseme override")
	m._face_geo_set(false)

	# ---------------- S: the pictures
	var shotp := OS.get_environment("FACE_GEO3_SHOT")
	if shotp != "":
		var s_pic := await make_studio(d, head_pts, {})
		var fc2 := Vector3(0, my - 0.012, 0.12)
		frame(s_pic, fc2, 0.40, 17.0)
		var tiles := []
		var plist := ["rest", "A", "E", "I", "O", "U", "MBP", "FV", "L", "TH"]
		for pn in plist:
			tiles.append(await shot(s_pic, d, vst(pn)))
		tiles.append(await shot(s_pic, d, st({"AU25": 1.0, "AU26": 1.0})))
		tiles.append(await shot(s_pic, d, st(FaceGeo.preset("joy"))))
		var tw: int = (tiles[0] as Image).get_width()
		var sheet := Image.create(tw * 4, tw * 3, false, Image.FORMAT_RGBA8)
		for k in tiles.size():
			(tiles[k] as Image).convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(tiles[k], Rect2i(Vector2i.ZERO, (tiles[k] as Image).get_size()), Vector2i(tw * (k % 4), tw * (k / 4)))
		sheet.save_png(shotp + "_visemes.png")
		print("sheet order: ", plist, " + AU25+26 max, joy")
		frame(s_pic, Vector3(0, my - 0.020, 0.12), 0.40, 10.0)
		(await shot(s_pic, d, st({"AU25": 1.0, "AU26": 1.0}))).save_png(shotp + "_jaw.png")
		var ec: Vector3 = ((ears[0] as Dictionary)["verts"] as PackedVector3Array)[0] if ears.size() == 2 else Vector3(0.08, float((an["brow_l"] as Vector3).y) - 0.03, 0.0)
		frame(s_pic, Vector3(0.08, float((an["brow_l"] as Vector3).y) - 0.035, 0.0), 0.50, 22.0, 62.0, 4.0)
		(await shot(s_pic, d, st())).save_png(shotp + "_ear.png")
		frame(s_pic, cc, 0.45, 26.0, 20.0, -32.0)
		(await shot(s_pic, d, st())).save_png(shotp + "_chin.png")
		ok(FileAccess.file_exists(shotp + "_visemes.png"), "S the pictures are saved with prefix %s" % shotp)
	print("FACE GEO3 TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	print("face_geo3: %d fail" % fails)
	TestFiles.cleanup()
	quit(fails)


## widest background run between teeth and the row's span, over five scan lines through the middle of the crowns (mm)
func teeth_gap_stats(sc: Dictionary, img: Image, edge_y: float, sgn: float, cz: float, scale_s: float) -> Dictionary:
	var pa := screen(sc, Vector3(-0.01, edge_y, cz))
	var pb := screen(sc, Vector3(0.01, edge_y, cz))
	var pxmm := pa.distance_to(pb) / 20.0
	var worst := 0.0
	var span := 1.0e9
	for k in 5:
		var fy := 0.35 + 0.075 * float(k)
		var yw := edge_y + sgn * fy * 0.0095 * scale_s
		var py := int(round(screen(sc, Vector3(0, yw, cz)).y))
		var first := -1
		var last := -1
		for x in img.get_width():
			if is_white(img.get_pixel(x, py)):
				if first < 0:
					first = x
				last = x
		if first < 0:
			return {"gap": 99.0, "span": 0.0}
		var run := 0
		var mx := 0
		for x in range(first, last + 1):
			if is_white(img.get_pixel(x, py)):
				mx = maxi(mx, run)
				run = 0
			else:
				run += 1
		worst = maxf(worst, float(mx) / pxmm)
		span = minf(span, float(last - first + 1) / pxmm)
	return {"gap": worst, "span": span}
