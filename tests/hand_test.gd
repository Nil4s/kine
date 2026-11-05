extends SceneTree
## godot --path . -s tests/hand_test.gd     (lane HAND: gaps G23 and G38, scripts/hand_shape.gd)
## The hand collided as ONE capsule (r 4.7 cm). HandShape makes it a palm slab (a row of 6 capsules) + a capsule per
## phalanx, with palm_flat() (a palm laid on a surface, fingers along it or hooked over an edge) and close_on() (fingers
## closed round a rope). The right hand of the default body; every surface is placed relative to its shoulder.
## BARS (written and committed before the first run; each has a PLANTED control that must fail its bar):
##  a SIZE      the palm capsules as built, measured in the hand's frame: length, breadth and thickness within 5 % of the
##              cited ANSUR II palm length 11.6, hand breadth 8.8 and the derived thickness 3.15 cm, and the section's
##              stadium perimeter within 5 % of the cited hand circumference 21.2 cm.
##              PLANTED: the old capsule's thickness (2 x 4.7 cm) is more than 5 % off the cited thickness (flagged).
##  b FLAT      palm_flat on a horizontal box top and on a box turned 45 deg (the palm on an inclined face 7.5 cm from the
##              ridge): the deepest hand capsule (palm, fingers, thumb) <= 2 mm into the box, and the contact area (the
##              palm grid within 3 mm of the box) >= 50 % of the cited palm.
##              PLANTED: the old capsule at the same pose is more than 10 mm into the box (both boxes).
##  c HOOK      palm_flat with a hook over the end edge of a 0.6 m deep wall top: the palm on the top (0 <= gap <= 2 mm),
##              all four fingertips over the edge (past the end face) and >= 2 cm below the top, no finger more than 1 mm
##              inside the box, and >= 3 of 4 fingers within 5 mm of the end face (they hold it).
##              PLANTED: the same hand with its fingers straight: the fingertips are not 2 cm below the top (no hook).
##  d ROPE      a 10 mm rope (its own collision radius 5 mm, particles every 4 mm) across the distal palm (80 % of the palm
##              length, the power-grip line), 0.5 mm off the palm; close_on closes the fingers and the thumb round it.
##              No rope particle inside any palm or finger capsule (least gap >= -0.1 mm), and >= 3 of 4 fingers touch the
##              rope (gap <= 2 mm) on its outer half (the side away from the palm: palm and fingers hold it between them).
##              PLANTED: the old capsule at the same pose has a rope particle more than 10 mm inside it.
##  e TWIN      no native code changed in this lane (nothing to compare with C++). The twin here: HandShape.cap_gap (exact,
##              a golden-section search) and the app's own Props.depth (axis sampled every 1 cm) agree on every hand
##              capsule of poses b and c within 1 mm.  PLANTED: a capsule 5 mm too fat reads > 4 mm apart.
##  f OLD       HandShape.legacy = true gives Body.cap / Body.rad of the hand bit for bit, and Rulebook.prop_hits (the app's
##              THROUGH A PROP check) uses the new hand: the flat palm on the table reads no hit, the legacy capsule at the
##              same pose reads a hit (planted). The suites that used the hand capsule are run with this one (the doc lists them).
## Pictures (not bars): C:/Temp/claude/hand/flat45.png, hook.png, rope.png (the mannequin, the capsules, the box / rope).

var fails := 0
const OUT := "C:/Temp/claude/hand"
const H := "hand_r"
const R_ROPE := 0.005


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func pct(a: float, b: float) -> float:
	return 100.0 * absf(a - b) / b


## a Props-style box solid
func box(centre: Vector3, half: Vector3, bs := Basis.IDENTITY) -> Dictionary:
	return {"xf": Transform3D(bs, centre), "half": half}


var scenes := {}   # name -> {"B": Body, "solids": [...], "rope": PackedVector3Array}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	bar_a()
	bar_b()
	bar_c()
	bar_d()
	bar_e()
	bar_f()
	await pictures()
	print("hand: %d fail" % fails)
	quit(1 if fails > 0 else 0)


# ------------------------------------------------ a
func bar_a() -> void:
	var B := body()
	var f := HandShape.frame0(B, H)
	var pc := HandShape.palm_caps(B, H)
	var g: Quaternion = B.G[H]
	var w: Vector3 = B.P[H]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for c in pc:
		var r := float(c[2])
		for e in [c[0], c[1]]:
			var d: Vector3 = (e as Vector3) - w
			var q := Vector3(d.dot(g * (f["ax"] as Vector3)), d.dot(g * (f["br"] as Vector3)), d.dot(g * (f["nr"] as Vector3)))
			lo = lo.min(q - Vector3(r, r, r))
			hi = hi.max(q + Vector3(r, r, r))
	var L := hi.x - lo.x
	var Bw := hi.y - lo.y
	var T := hi.z - lo.z
	var per := 2.0 * (Bw - T) + PI * T
	var t_src := HandShape.palm_thickness()
	print("     palm as built: length %.2f cm (ANSUR %.1f), breadth %.2f cm (%.1f), thickness %.2f cm (derived %.2f), perimeter %.2f cm (%.1f); %d rows" % [
		L * 100, HandShape.PALM_LENGTH * 100, Bw * 100, HandShape.HAND_BREADTH * 100, T * 100, t_src * 100, per * 100, HandShape.HAND_CIRC * 100, pc.size()])
	print("     fingers r %.2f cm (FAA index breadth 2.1 cm), wrist r %.2f cm (ANSUR wrist circumference 17.6 cm); the palm face %.1f cm palm-side of the bone line (tools/hand_mesh.gd)" % [
		HandShape.FINGER_R * 100, HandShape.wrist_r() * 100, HandShape.PALM_SKIN * 100])
	ok(pct(L, HandShape.PALM_LENGTH) <= 5.0 and pct(Bw, HandShape.HAND_BREADTH) <= 5.0 and pct(T, t_src) <= 5.0 and pct(per, HandShape.HAND_CIRC) <= 5.0,
		"a palm %.2f x %.2f x %.2f cm vs cited 11.6 x 8.8 x %.2f: %.1f / %.1f / %.1f %% off, perimeter %.1f %% off (bar 5 %%)" % [L * 100, Bw * 100, T * 100, t_src * 100,
		pct(L, HandShape.PALM_LENGTH), pct(Bw, HandShape.HAND_BREADTH), pct(T, t_src), pct(per, HandShape.HAND_CIRC)])
	var old_t := 2.0 * float(B.rad[H])
	ok(pct(old_t, t_src) > 5.0, "a PLANTED the old capsule is %.1f cm thick, %.0f %% off the cited %.2f cm: flagged" % [old_t * 100, pct(old_t, t_src), t_src * 100])


# ------------------------------------------------ b
## palm_flat at c on the solids, then the measures with the new hand and the legacy capsule at the SAME pose
func flat_case(name: String, c: Vector3, n: Vector3, fdir: Vector3, solids: Array) -> void:
	var B := body()
	var r := HandShape.palm_flat(B, H, c, n, {"fdir": fdir, "solids": solids})
	var pen: Dictionary = HandShape.deepest(HandShape.caps(B, H), solids)
	var area := HandShape.contact_area(B, H, solids)
	HandShape.legacy = true
	var old: Dictionary = HandShape.deepest(HandShape.caps(B, H), solids)
	var old_area := HandShape.contact_area(B, H, solids)
	HandShape.legacy = false
	print("     %s: wrist miss %.1f mm, clamped %s, heading turned %.0f deg, palm tilt %.1f deg, palm gap %.2f mm, forearm gap (wrist capsule) %.1f mm, wrist angles %s" % [name, float(r["miss"]) * 1000, r["clamped"], float(r["turn"]), float(r["tilt"]), float(r["palm_gap"]) * 1000, float(r["forearm_gap"]) * 1000, B.ang[H]])
	print("     %s: new hand deepest %.2f mm (%s), contact %.0f %%; old capsule deepest %.1f mm, contact %.0f %%" % [name, float(pen["d"]) * 1000, pen["part"], area * 100, float(old["d"]) * 1000, old_area * 100])
	ok(float(pen["d"]) <= 0.002 and area >= 0.5, "b %s: deepest hand capsule %.2f mm (bar 2), palm contact %.0f %% (bar 50)" % [name, float(pen["d"]) * 1000, area * 100])
	ok(float(old["d"]) > 0.010, "b PLANTED %s: the old capsule at the same pose is %.1f mm into the box (> 10)" % [name, float(old["d"]) * 1000])
	scenes[name] = {"B": B, "solids": solids}


func bar_b() -> void:
	var B := body()
	var S: Vector3 = B.P["upperarm_r"]
	# horizontal: a box top 25 cm under the shoulder, the palm 40 cm out to his right and 15 cm in front, fingers out (-x)
	var c := S + Vector3(-0.40, -0.25, 0.15)
	flat_case("flat", c, Vector3.UP, Vector3(-1, 0, 0), [box(c - Vector3(0, 0.15, 0), Vector3(0.25, 0.15, 0.25))])
	# 45 deg: a box turned 45 deg about z, a ridge up; the palm on the face whose normal is (-1, 1, 0)/sqrt2, 7.5 cm from
	# the ridge, fingers down the slope
	var n45 := Vector3(-1, 1, 0).normalized()
	var n2 := Vector3(1, 1, 0).normalized()
	var down := Vector3(-1, -1, 0).normalized()
	var ridge := S + Vector3(-0.30, -0.18, 0.15)
	var cen := ridge - n45 * 0.15 - n2 * 0.15
	flat_case("flat45", ridge + down * 0.075, n45, down, [box(cen, Vector3(0.15, 0.15, 0.20), Basis(n2, n45, Vector3(0, 0, 1)))])


# ------------------------------------------------ c
func bar_c() -> void:
	var B := body()
	var S: Vector3 = B.P["upperarm_r"]
	var top := S.y - 0.30
	var xe := S.x - 0.42   # the wall's end face (its outward normal -x, out to his right)
	var wall := box(Vector3(xe + 0.5, top - 0.6, S.z + 0.45), Vector3(0.5, 0.6, 0.30))   # 1 m long, 1.2 m high, 0.6 m deep
	var edge := Vector3(xe, top, S.z + 0.25)
	var on := Vector3(-1, 0, 0)
	var r := HandShape.palm_flat(B, H, edge + Vector3(0.07, 0, 0), Vector3.UP, {"fdir": on, "solids": [wall], "hook": {"edge": edge, "over_n": on}})
	var sd := H.substr(4)
	var below := 0
	var past := 0
	var hold := 0
	var tips := []
	for fg in HandShape.FINGERS4:
		var tip: Vector3 = B.E["%s_03%s" % [fg, sd]]
		tips.append("%s (%.1f, %.1f) cm" % [fg, (xe - tip.x) * 100, (top - tip.y) * 100])
		if tip.y <= top - 0.02:
			below += 1
		if tip.x < xe:
			past += 1
		var fc: Array = HandShape._finger(B, H, fg)
		if HandShape.deepest(fc, [wall])["gap"] <= 0.005:
			hold += 1
	var fpen: Dictionary = HandShape.deepest(HandShape.finger_caps(B, H), [wall])
	print("     hook: wrist miss %.1f mm, clamped %s, heading turned %.0f deg, palm gap %.2f mm, forearm gap %.1f mm; tips past the face / below the top: %s; finger angles %s %s %s" % [
		float(r["miss"]) * 1000, r["clamped"], float(r["turn"]), float(r["palm_gap"]) * 1000, float(r["forearm_gap"]) * 1000, ", ".join(tips), B.ang["middle_01" + sd], B.ang["middle_02" + sd], B.ang["middle_03" + sd]])
	ok(float(r["palm_gap"]) >= -1e-6 and float(r["palm_gap"]) <= 0.002 and below == 4 and past == 4 and float(fpen["d"]) <= 0.001 and hold >= 3,
		"c hook over the 0.6 m wall top: palm gap %.2f mm, %d/4 tips 2 cm below the top, %d/4 past the face, deepest finger %.2f mm (%s), %d/4 fingers within 5 mm of the face" % [
		float(r["palm_gap"]) * 1000, below, past, float(fpen["d"]) * 1000, fpen["part"], hold])
	scenes["hook"] = {"B": B, "solids": [wall]}
	# planted: the fingers straight at the same placement
	var B2 := body()
	for j in B.ang:
		B2.ang[j] = B.ang[j]
	for fg in HandShape.FINGERS4:
		for k in 3:
			B2.ang["%s_0%d%s" % [fg, k + 1, sd]] = Vector3.ZERO
	B2.fk()
	var below2 := 0
	for fg in HandShape.FINGERS4:
		if (B2.E["%s_03%s" % [fg, sd]] as Vector3).y <= top - 0.02:
			below2 += 1
	ok(below2 < 4, "c PLANTED fingers straight at the same placement: %d/4 tips 2 cm below the top (no hook)" % below2)


# ------------------------------------------------ d
func bar_d() -> void:
	var B := body()
	var d := HandShape.dims(B, H)
	var pf := HandShape.palm_face(B, H)
	var n: Vector3 = pf["n"]
	var u := 0.8 * float(d["length"])
	var axis_c := HandShape._pose(B, H, HandShape._palm_rest(B, H, u, 0.0, float(d["rho"]))) + n * (R_ROPE + HandShape.GAP)
	var along: Vector3 = pf["br"]
	var pts := PackedVector3Array()
	for i in 61:
		pts.append(axis_c + along * (-0.12 + 0.004 * i))
	var segs := []
	for i in pts.size() - 1:
		segs.append([pts[i], pts[i + 1], R_ROPE])
	var cl := HandShape.close_on(B, H, segs)
	var hc := HandShape.caps(B, H)
	var worst := INF
	for p in pts:
		worst = minf(worst, HandShape.point_gap(hc, p, R_ROPE))
	var touch := 0
	var outer := 0
	var rows := []
	for fg in HandShape.FINGERS4:
		var fc: Array = HandShape._finger(B, H, fg)
		var g := HandShape.caps_gap(fc, segs)
		# the finger's contact: the point of its capsules nearest the rope's axis
		var best := INF
		var cp := Vector3.ZERO
		for c in fc:
			for i in range(0, pts.size(), 2):
				var q := HandShape.seg_point(c[0], c[1], pts[i])
				var dd := q.distance_to(HandShape.seg_point(pts[0], pts[pts.size() - 1], q))
				if dd < best:
					best = dd
					cp = q
		var ax_pt := HandShape.seg_point(pts[0], pts[pts.size() - 1], cp)
		var side := n.dot(cp - ax_pt)
		rows.append("%s curl %.2f gap %.2f mm side %+.1f mm" % [fg, float(cl[fg][0]), g * 1000, side * 1000])
		if g <= 0.002:
			touch += 1
			if side > 0.0:
				outer += 1
	rows.append("thumb curl %.2f gap %.2f mm" % [float(cl["thumb"][0]), float(cl["thumb"][1]) * 1000])
	print("     rope: " + "; ".join(rows))
	ok(worst >= -0.0001 and touch >= 3 and outer >= 3, "d closed on a 10 mm rope: least rope-hand gap %.3f mm (bar >= -0.1), %d/4 fingers touch, %d/4 on the rope's outer half" % [worst * 1000, touch, outer])
	HandShape.legacy = true
	var oc := HandShape.caps(B, H)
	HandShape.legacy = false
	var ow := INF
	for p in pts:
		ow = minf(ow, HandShape.point_gap(oc, p, R_ROPE))
	ok(ow < -0.010, "d PLANTED the old capsule at the same pose: a rope particle %.1f mm inside it (> 10)" % (-ow * 1000))
	scenes["rope"] = {"B": B, "solids": [], "rope": pts}


# ------------------------------------------------ e
func bar_e() -> void:
	var worst := 0.0
	var worst_fat := 0.0
	var n := 0
	for nm in ["flat", "flat45", "hook"]:
		var sc: Dictionary = scenes[nm]
		var B: Body = sc["B"]
		var sw: Dictionary = sc["solids"][0]
		for c in HandShape.caps(B, H):
			var exact := maxf(0.0, -HandShape.cap_gap(c, sw))
			var sampled := _props_depth(sw, c)
			worst = maxf(worst, absf(exact - sampled))
			var fat := [c[0], c[1], float(c[2]) + 0.005]
			worst_fat = maxf(worst_fat, absf(maxf(0.0, -HandShape.cap_gap(fat, sw)) - sampled))
			n += 1
	ok(worst <= 0.001, "e HandShape.cap_gap (exact) = Props.depth's sampling of the same %d capsules within %.3f mm (bar 1 mm) on poses flat / flat45 / hook; no native code changed" % [n, worst * 1000])
	ok(worst_fat > 0.004, "e PLANTED a capsule 5 mm too fat reads %.2f mm apart (> 4)" % (worst_fat * 1000))


## Props.depth's own arithmetic (the axis sampled every Props.STEP, r - Props._sd) on one solid
func _props_depth(sw: Dictionary, c: Array) -> float:
	var worst := 0.0
	for pt in Props._samples(c[0], c[1]):
		worst = maxf(worst, float(c[2]) - Props._sd(sw, pt))
	return worst


# ------------------------------------------------ f
func bar_f() -> void:
	var B: Body = scenes["flat"]["B"]
	HandShape.legacy = true
	var lc: Array = HandShape.caps(B, H)
	HandShape.legacy = false
	var bc: Array = B.cap(H)
	ok(lc.size() == 1 and lc[0][0] == bc[0] and lc[0][1] == bc[1] and float(lc[0][2]) == float(B.rad[H]), "f HandShape.legacy gives Body.cap / Body.rad of the hand bit for bit")
	var sw: Dictionary = scenes["flat"]["solids"][0]
	var hs: Vector3 = sw["half"]
	Props.register_solids("hand_test:table", {"solids": [[Vector3(0, hs.y, 0), hs * 2.0]], "supports": []})
	var table := Props.make("hand_test:table", Transform3D(Basis.IDENTITY, (sw["xf"] as Transform3D).origin - Vector3(0, hs.y, 0)))
	var nb := Props.solids(table)
	var same: bool = nb.size() == 1 and ((nb[0]["xf"] as Transform3D).origin - (sw["xf"] as Transform3D).origin).length() < 1e-5 and ((nb[0]["half"] as Vector3) - hs).length() < 1e-6
	var hits := Rulebook.prop_hits([table], B).filter(func(x): return String(x[0]) == H)
	HandShape.legacy = true
	var old_hits := Rulebook.prop_hits([table], B).filter(func(x): return String(x[0]) == H)
	HandShape.legacy = false
	ok(same and hits.is_empty(), "f Rulebook.prop_hits uses the new hand: the flat palm on the table reads %d hits (the prop is the bar-b box: %s)" % [hits.size(), same])
	ok(not old_hits.is_empty(), "f PLANTED the legacy capsule at the same pose reads %d hit(s) (%.1f mm)" % [old_hits.size(), float(old_hits[0][2]) * 1000 if not old_hits.is_empty() else 0.0])


# ------------------------------------------------ pictures
func grab() -> Image:
	for i in 6:
		await process_frame
	var im: Image = root.get_texture().get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


func mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func capsule_node(a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = a.distance_to(b) + 2.0 * r
	cm.radial_segments = 24
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = m
	var y := (b - a).normalized() if a.distance_to(b) > 1e-6 else Vector3.UP
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	return mi


func pictures() -> void:
	if DisplayServer.get_name() == "headless":
		print("     pictures skipped (headless)")
		return
	for nm in ["flat45", "hook", "rope"]:
		var sc: Dictionary = scenes[nm]
		var B: Body = sc["B"]
		var w := Node3D.new()
		root.add_child(w)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.85, 0.87, 0.9)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
		w.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -30, 0)
		w.add_child(sun)
		var man: Array = Overlays.mannequin(w, mat(Color(0.95, 0.8, 0.65, 0.55)))
		Overlays.pose_skeleton(man[1], man[2], B)
		for c in HandShape.palm_caps(B, H):
			w.add_child(capsule_node(c[0], c[1], float(c[2]), mat(Color(0.1, 0.7, 0.2, 0.75))))
		for c in HandShape.finger_caps(B, H):
			w.add_child(capsule_node(c[0], c[1], float(c[2]), mat(Color(0.95, 0.75, 0.1, 0.85))))
		for c in HandShape.forearm_caps(B, H):
			w.add_child(capsule_node(c[0], c[1], float(c[2]), mat(Color(0.2, 0.4, 0.9, 0.35))))
		for sw in sc["solids"]:
			var bm := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = (sw["half"] as Vector3) * 2.0
			bm.mesh = bx
			bm.material_override = mat(Color(0.55, 0.55, 0.6))
			bm.transform = sw["xf"]
			w.add_child(bm)
		if sc.has("rope"):
			var pts: PackedVector3Array = sc["rope"]
			for i in pts.size() - 1:
				w.add_child(capsule_node(pts[i], pts[i + 1], R_ROPE, mat(Color(0.85, 0.1, 0.1))))
		var focus: Vector3 = HandShape.palm_face(B, H)["o"]
		var cam := Camera3D.new()
		cam.fov = 30.0
		w.add_child(cam)
		cam.look_at_from_position(focus + Vector3(-0.25, 0.22, 0.45), focus, Vector3.UP)
		cam.current = true
		var im: Image = await grab()
		cam.look_at_from_position(focus + Vector3(-0.05, -0.02, 0.5), focus, Vector3.UP)
		var im2: Image = await grab()
		var sheet := Image.create(im.get_width() * 2, im.get_height(), false, Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i.ZERO)
		sheet.blit_rect(im2, Rect2i(Vector2i.ZERO, im2.get_size()), Vector2i(im.get_width(), 0))
		sheet.save_png("%s/%s.png" % [OUT, nm])
		print("     picture %s/%s.png" % [OUT, nm])
		w.queue_free()
		await process_frame
