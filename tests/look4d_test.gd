extends SceneTree
## godot --path . -s tests/look4d_test.gd     (LOOK4D: the four formats of scripts/build/look4d.gd; docs/LOOK4D_DESIGN.md)
## Bars and planted controls committed BEFORE the first run:
##  1 VELOCITY  D velocities equal the finite differences of the posed transforms (every part of the engine, 3 sig figs); the crank turns 6.283 rad/s (360 deg/s);
##              a ball at a known v reads v. PLANTED: the same digest with a 10x dt must miss the finite differences on the accelerating engine.
##  2 OCCLUSION occluded flags on a planted fixture (front box hides the box behind it; a side box is clear; a far-left box is outside the picture: solo_px 0)
##              and the pixel counts equal an independent id render built on LookFacts primitives. CONTROL: the hidden box moved aside reads NOT occluded.
##  3 ARROW     C's arrow, read by yellow pixel positions in C.png, starts at the part centre and ends at the projection of centre + v * ARROW_T (camera.unproject_position,
##              not the module's own projection), for a sideways and a toward-the-camera velocity. PLANTED: the reversed arrow's tip is far from the real one (the check can fail).
##  4 PROJECTION Look4D.project_pt equals Camera3D.unproject_position within 0.6 px.
##  5 FORMATS   A, B, C are 768 x 432, D parses and every number is finite, each format on the engine is produced inside 5000 ms.
##  7 LABELS    in all six scenes no two mark boxes of C intersect and all lie inside the picture. PLANTED: the old layout (label at the projected centre, no declutter) must show intersecting boxes.
##  6 STIMULI   all six scenes produce A.png B.png C.png D.json truth_data.json timing.json under res://out/look4d/<scene>/; S6's digest has zero speed everywhere and the same
##              id list as S1; every scene's D carries one row per id.
const L4 := preload("res://scripts/build/look4d.gd")
const SCN := preload("res://scripts/build/look4d_scenes.gd")
const OUT := "C:/Temp/claude/look4d"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func ctl(c: bool, w: String) -> void:
	ok(c, "CONTROL " + w)


func _init() -> void:
	await process_frame
	await run()
	print("look4d: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func rel_ok(d: Vector3, fd: Vector3) -> bool:
	for i in 3:
		if absf(d[i] - fd[i]) > 0.0051 * absf(fd[i]) + 1e-9:
			return false
	return true


func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await bars_velocity()
	await bars_occlusion()
	await bars_arrow()
	await bars_formats()
	await bars_stimuli()


# ------------------------------------------------------------------ 1
func bars_velocity() -> void:
	var sc := SCN.engine(false)
	var ctx := L4.open(root, sc)
	await L4.frames(2)
	var t0 := float(sc["t0"])
	var kin := L4.kinematics(ctx, t0)
	var meas := await L4.measure(ctx)
	var dg := L4.digest(ctx, t0, kin, meas, [])
	# independent finite differences straight from the posed nodes
	var worst := 0.0
	var bad := 0
	var wmax := 0.0
	var rws := L4.rows(dg)
	for id in rws:
		var row: Dictionary = rws[id]
		var n := sc["nodes"][id] as MeshInstance3D
		L4.at(ctx, t0 + L4.DT)
		var cb := n.global_transform * n.mesh.get_aabb().get_center()
		L4.at(ctx, t0 - L4.DT)
		var ca := n.global_transform * n.mesh.get_aabb().get_center()
		var fd := (cb - ca) / (2.0 * L4.DT)
		if not rel_ok(row["vel"], fd):
			bad += 1
		worst = maxf(worst, ((row["vel"] as Vector3) - fd).length())
		wmax = maxf(wmax, (row["angvel"] as Vector3).length())
	ok(bad == 0 and rws.size() == (sc["ids"] as Array).size(), "1 engine D velocity of %d parts equals the posed finite difference (worst |dv| %s m/s, bar 0.5%% per component)" % [rws.size(), String.num_scientific(worst)])
	ok(absf(wmax - TAU) < 0.02 * TAU, "1 the fastest angular velocity is the crank's 360 deg/s = %.4f rad/s (got %.4f)" % [TAU, wmax])
	var kin_bad := L4.kinematics(ctx, t0, L4.DT * 10.0)
	var dg_bad := L4.digest(ctx, t0, kin_bad, meas, [])
	var miss := 0
	var rws_bad := L4.rows(dg_bad)
	for id in rws_bad:
		var row: Dictionary = rws_bad[id]
		var n := sc["nodes"][id] as MeshInstance3D
		L4.at(ctx, t0 + L4.DT)
		var cb := n.global_transform * n.mesh.get_aabb().get_center()
		L4.at(ctx, t0 - L4.DT)
		var ca := n.global_transform * n.mesh.get_aabb().get_center()
		if not rel_ok(row["vel"], (cb - ca) / (2.0 * L4.DT)):
			miss += 1
	ctl(miss > 0, "1 PLANTED dt x 10 misses the finite differences on %d engine parts" % miss)
	L4.close(ctx)
	# a ball at a known velocity
	var vk := Vector3(0.3, -0.2, 0.5)
	var scb := SCN.ball(Vector3(-0.2, 0.1, -0.3), vk)
	var cb2 := L4.open(root, scb)
	await L4.frames(2)
	var kb := L4.kinematics(cb2, 1.0)
	var db := L4.digest(cb2, 1.0, kb, await L4.measure(cb2), [])
	var rb: Dictionary = L4.rows(db)["ball"]
	var vb: Vector3 = rb["vel"]
	ok(rel_ok(vb, vk) and absf(float(rb["speed"]) - vk.length()) < 0.006 * vk.length(), "1 a ball at v = %s reads %s, speed %.4f (hand %.4f)" % [str(vk), str(vb), float(rb["speed"]), vk.length()])
	ok(L4.round_sig(0.123456) == 0.123 and L4.round_sig(1234.56) == 1230.0 and L4.round_sig(-0.0049876) == -0.00499, "1 round_sig keeps 3 significant figures")
	L4.close(cb2)


# ------------------------------------------------------------------ 2
func bars_occlusion() -> void:
	var sc := SCN.occl()
	var ctx := L4.open(root, sc)
	await L4.frames(3)
	L4.at(ctx, 0.0)
	var m := await L4.measure(ctx)
	ok(L4.occluded(m["behind"]) and float(m["behind"]["frac"]) < 0.01 and String(m["behind"]["by"]) == "front", "2 the box behind the front box is occluded by 'front' (frac %.3f, by %s)" % [float(m["behind"]["frac"]), m["behind"]["by"]])
	ok(not L4.occluded(m["front"]) and not L4.occluded(m["side"]), "2 the front and side boxes are not occluded (frac %.2f, %.2f)" % [float(m["front"]["frac"]), float(m["side"]["frac"])])
	ok(int(m["gone"]["solo_px"]) == 0 and not L4.occluded(m["gone"]), "2 the far-left box has an empty silhouette in the picture (solo_px %d): out of view, not occluded" % int(m["gone"]["solo_px"]))
	# an independent id render: own viewport, LookFacts.id_color / _flat / decode_ids, own node copies
	var vp := SubViewport.new()
	vp.size = Vector2i(L4.W, L4.H)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_debanding = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.transform = (ctx["cam"] as Camera3D).global_transform
	cam.fov = (ctx["cam"] as Camera3D).fov
	vp.add_child(cam)
	var colors := {"front": 40, "behind": 41, "side": 42, "gone": 43}
	for id in colors:
		var mi := MeshInstance3D.new()
		mi.mesh = (sc["nodes"][id] as MeshInstance3D).mesh
		mi.material_override = LookFacts._flat(LookFacts.id_color(int(colors[id])))
		vp.add_child(mi)
		mi.global_transform = (sc["nodes"][id] as MeshInstance3D).global_transform
	root.add_child(vp)
	cam.current = true
	await L4.frames(3)
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var map := LookFacts.decode_ids(img)
	var cnt := {}
	for p in map.size():
		if map[p] > 0:
			cnt[map[p]] = int(cnt.get(map[p], 0)) + 1
	var same := true
	for id in colors:
		if int(cnt.get(int(colors[id]), 0)) != int(m[id]["vis_px"]):
			same = false
	ok(same, "2 vis_px of all four boxes equals an independent LookFacts.decode_ids count (front %d / %d, side %d / %d)" % [int(m["front"]["vis_px"]), int(cnt.get(40, 0)), int(m["side"]["vis_px"]), int(cnt.get(42, 0))])
	vp.queue_free()
	L4.close(ctx)
	# control: the hidden box moved aside
	var sc2 := SCN.occl()
	var ctx2 := L4.open(root, sc2)
	(sc2["nodes"]["behind"] as MeshInstance3D).position = Vector3(-0.9, 0, -0.6)
	await L4.frames(3)
	var m2 := await L4.measure(ctx2)
	ctl(not L4.occluded(m2["behind"]) and int(m2["behind"]["solo_px"]) > 0, "2 the same box moved aside reads NOT occluded (frac %.2f)" % float(m2["behind"]["frac"]))
	L4.close(ctx2)


# ------------------------------------------------------------------ 3 and 4
func yellow_pixels(img: Image) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d := img.get_data()
	for p in img.get_width() * img.get_height():
		var r := int(d[p * 3])
		var g := int(d[p * 3 + 1])
		var b := int(d[p * 3 + 2])
		if r > 235 and g > 190 and g < 235 and b < 40:
			out.append(Vector2(p % img.get_width(), p / img.get_width()))
	return out


func arrow_case(label: String, v: Vector3) -> void:
	var x0 := Vector3(-0.2, 0.0, -0.3)
	var sc := SCN.ball(x0, v)
	var r := await L4.produce(root, sc, OUT + "/arrow_" + label)
	var ctx: Dictionary = r["ctx"]
	var cam: Camera3D = ctx["cam"]
	var t0 := float(sc["t0"])
	var c: Vector3 = x0 + v * t0
	var tail := cam.unproject_position(c) * L4.CS
	var tip := cam.unproject_position(c + v * L4.ARROW_T) * L4.CS
	var img := Image.load_from_file(OUT + "/arrow_" + label + "/C.png")
	var ys := yellow_pixels(img)
	var far := tail
	var near := Vector2(1e9, 1e9)
	for p in ys:
		if p.distance_to(tail) > far.distance_to(tail):
			far = p
		if p.distance_to(tail) < near.distance_to(tail):
			near = p
	var rev := cam.unproject_position(c - v * L4.ARROW_T) * L4.CS
	ok(ys.size() > 10 and far.distance_to(tip) <= 6.0 and near.distance_to(tail) <= 4.0, "3 %s arrow: %d yellow px, tail read %s vs centre %s, tip read %s vs projected %s" % [label, ys.size(), str(near), str(tail), str(far), str(tip)])
	ctl(far.distance_to(rev) > 8.0, "3 %s PLANTED the reversed arrow's tip %s is %.0f px from the one read" % [label, str(rev), far.distance_to(rev)])
	var p1 := L4.project_pt(ctx, c)
	var p2 := L4.project_pt(ctx, c + v * L4.ARROW_T)
	var u1 := cam.unproject_position(c)
	var u2 := cam.unproject_position(c + v * L4.ARROW_T)
	ok((p1["px"] as Vector2).distance_to(u1) < 0.6 and (p2["px"] as Vector2).distance_to(u2) < 0.6, "4 %s project_pt equals Camera3D.unproject_position (%.3f px, %.3f px)" % [label, (p1["px"] as Vector2).distance_to(u1), (p2["px"] as Vector2).distance_to(u2)])
	L4.close(ctx)


func bars_arrow() -> void:
	await arrow_case("side", Vector3(0.6, 0.1, 0.0))
	await arrow_case("toward", Vector3(0.4, 0.2, 1.5))


# ------------------------------------------------------------------ 5
func bars_formats() -> void:
	var sc := SCN.engine(false)
	var r := await L4.produce(root, sc, OUT + "/engine")
	for k in ["A", "B", "C"]:
		var im: Image = r[k]
		ok(im.get_width() == 768 and im.get_height() == 432, "5 %s is %d x %d" % [k, im.get_width(), im.get_height()])
	var ms: Dictionary = r["ms"]
	for k in ["A", "B", "C", "D"]:
		ok(float(ms[k]) < 5000.0, "5 %s produced in %.0f ms (budget 5000)" % [k, float(ms[k])])
	var dg = JSON.parse_string(r["d_text"])
	var fin := dg is Dictionary
	var nrows := 0
	if fin:
		var rr := L4.rows(dg)
		nrows = rr.size()
		for id in rr:
			for kk in ["pos", "vel", "angvel", "momentum"]:
				for i in 3:
					fin = fin and is_finite((rr[id][kk] as Vector3)[i])
	ok(fin and nrows == (sc["ids"] as Array).size(), "5 D parses, every number finite, %d rows for %d ids, %d bytes (~%d tokens vs %d for an image)" % [nrows, (sc["ids"] as Array).size(), (r["d_text"] as String).length(), (r["d_text"] as String).length() / 4, int(round(768 * 432 / 750.0))])
	L4.close(r["ctx"])


# ------------------------------------------------------------------ 6
func bars_stimuli() -> void:
	var s1ids: Array = []
	var s6ids: Array = []
	var s6speed := 0.0
	var naive_total := 0
	for nm in SCN.SCENES:
		var sc := SCN.by_name(nm)
		var dir := ProjectSettings.globalize_path("res://out/look4d/" + nm)
		var r := await L4.produce(root, sc, dir)
		var files_ok := true
		for f in ["A.png", "B.png", "C.png", "D.json", "truth_data.json", "timing.json"]:
			files_ok = files_ok and FileAccess.file_exists(dir + "/" + f)
		var sizes_ok := true
		for k in ["A", "B", "C"]:
			var im: Image = r[k]
			sizes_ok = sizes_ok and im.get_width() == 768 and im.get_height() == 432
		var ms: Dictionary = r["ms"]
		ok(files_ok and sizes_ok and L4.rows(r["digest"]).size() == L4.named(r["ctx"]).size(), "6 %s: six files, 768 x 432, %d D rows; ms A %.0f B %.0f C %.0f D %.0f; D ~%d tokens; t0 %.2f" % [nm, L4.rows(r["digest"]).size(), float(ms["A"]), float(ms["B"]), float(ms["C"]), float(ms["D"]), (r["d_text"] as String).length() / 4, float(sc["t0"])])
		var nvis := 0
		var nocc := 0
		for id in L4.named(r["ctx"]):
			if int(r["meas"][id]["solo_px"]) > 0:
				nvis += 1
			if L4.occluded(r["meas"][id]):
				nocc += 1
		var mrects: Array = []
		var inside := true
		for mk in r["plan"]["marks"]:
			mrects.append(mk["rect"])
			inside = inside and Rect2(0, 0, L4.IMG_W, L4.IMG_H).encloses(mk["rect"])
		var hit := L4.boxes_intersect(mrects)
		ok(hit == 0 and inside and mrects.size() == nvis, "7 %s: %d mark boxes for %d parts in the picture, none intersect, all inside the picture" % [nm, mrects.size(), nvis])
		naive_total += L4.boxes_intersect(L4.naive_boxes(r["ctx"], r["kin"], r["meas"]))
		print("      %s: %d ids (%d named), %d in the picture, %d occluded, %d contacts; D ~%d tokens vs A %d" % [nm, (sc["ids"] as Array).size(), L4.named(r["ctx"]).size(), nvis, nocc, (r["contacts"] as Array).size(), (r["d_text"] as String).length() / 4, int(round(768 * 432 / 750.0))])
		if nm == "s1_engine":
			s1ids = (sc["ids"] as Array).duplicate()
		if nm == "s6_null":
			s6ids = (sc["ids"] as Array).duplicate()
			for o in L4.rows(r["digest"]).values():
				s6speed = maxf(s6speed, float(o["speed"]))
		L4.close(r["ctx"])
	ok(s1ids == s6ids and s6speed < 1e-6, "6 S6 has S1's ids and zero speed everywhere (max %s)" % String.num_scientific(s6speed))
	ctl(naive_total > 0, "7 PLANTED the old layout (label at the projected centre, no declutter) has %d intersecting label-box pairs over the six scenes" % naive_total)
