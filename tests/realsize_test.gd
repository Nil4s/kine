## godot --path . -s tests/realsize_test.gd     (ROADMAP_400 B27; needs a window: the readout's placement is read back as pixels)
## Real-size sanity (scripts/real_size.gd, scripts/real_size_ui.gd). Bars, written before measuring:
##   1 SWORD 3 m (a 3.00 x 0.06 x 0.01 m box turned off every axis, named "Sword_3m"): guessed "sword" from the name,
##     measured 300.0 cm within 0.1 mm (the PCA box, not the axis box), verdict "wrong", the sentence names the arm and
##     this fighter's arm length (54.7 cm) and the range (60-98 cm)
##   2 SWORD 75 cm (same box, 0.75 m long, kind picked "sword"): "ok"; every Body.KINDS weapon at its own length lands
##     "ok" in the range of its kind (metal_bat -> bat, staff, long_hammer -> hammer, dagger, long_axe -> axe, sword,
##     longsword, katana, spear): the ranges hold the app's own weapons
##   3 HELMET: a 16 x 15 x 14 cm box (narrowest side 14 cm < the head breadth 17.3 cm) is "wrong" naming the head
##     breadth; 17.8 cm across (over the head, under head + 1 cm) is "suspicious"; a 26 x 24 x 22 cm helm is "ok"
##   4 UNITS: the 75 cm sword built 100x too big (75 m) is "wrong" with the hint "made in cm" and factor 0.01; rescaled
##     about its centre its long side is 75 cm within 1% (and the verdict "ok"); a 0.75 mm one (1000x too small) gets 1000
##   5 PROPORTIONS: a fighter with upper arm and forearm x1.2 (Proportions scale; the stature stays) has an arm 1.2x
##     within 0.1%, and the sword range's lo, hi and width (hi - lo) all 1.2x within 0.1%
##   6 GUESS: "Iron_Helmet" -> helmet, "GreatSword" -> longsword, "combat_knife" -> dagger, "body_01" -> prop (no "bo"),
##     a nameless mesh whose verts all carry the A18 region "head" within 5 cm of the bone -> helmet, the same at 40 cm
##     from the bone -> prop; findings() gives [{"id": "real_size", "level": "fail"}, {"id": "real_size_units"}] for 75 m
##   7 APP (the test cube, 0.6 m, a prop): the op "Model: real-size check" (MeshTools line mesh_realsize) shows the
##     readout and says "real size" in the status line; the readout lies inside the free view by PAD, does not overlap
##     the cube's screen box, sits beside it (its vertical middle within the box's span, the gap GAP +- 1 px on that
##     side), over no other visible panel; the pixel at its centre differs from the shot without it (> 0.1). The cube
##     scaled x100 (60 m, one undo step) is "wrong" with a "Rescale x0.01" button; one press makes the long side 60 cm
##     within 1% as ONE more undo step; Ctrl+Z brings back 60 m. The op again hides it. Shot -> user://realsize.png
extends SceneTree

var fails := 0
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]
const TURN := Vector3(0.4, 0.7, -0.3)   # radians: the boxes are turned off every axis (the axis box would be wrong)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func box(sx: float, sy: float, sz: float, turned := true) -> KMesh:
	var b := Basis.from_euler(TURN) if turned else Basis.IDENTITY
	var v := PackedVector3Array()
	for p in CV:
		v.append(b * (Vector3(p.x * sx, p.y * sy, p.z * sz) + Vector3(0.3, 1.0, -0.2)))
	return KMesh.new().from_arrays(v, CF)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func _init() -> void:
	var R := RealSize
	var rf := R.refs()
	# 1 the 3 m sword
	var s3 := R.check(box(3.0, 0.06, 0.01), "", null, "Sword_3m")
	var t3: String = s3["text"]
	ok(s3["kind"] == "sword" and absf(s3["measured"] - 3.0) < 1e-4 and s3["verdict"] == "wrong" and t3.contains("arm") and t3.contains("54.7 cm") and t3.contains("60-98 cm"),
		"(1) 3 m sword: kind %s (%s), measured %.5f m, %s: '%s'" % [s3["kind"], s3["kind_why"], s3["measured"], s3["verdict"], t3])
	# 2 the 75 cm sword; the app's own weapons
	var s75 := R.check(box(0.75, 0.06, 0.01), "sword")
	var as_kind := {"metal_bat": "bat", "staff": "staff", "long_hammer": "hammer", "dagger": "dagger", "long_axe": "axe", "sword": "sword", "longsword": "longsword", "katana": "katana", "spear": "spear"}
	var bad := []
	for k in Body.KINDS:
		var L: float = Body.KINDS[k]["len"]
		var c := R.check(box(L, 0.05, 0.02), as_kind.get(k, "prop"))
		if c["verdict"] != "ok":
			bad.append("%s %.2f m: %s" % [k, L, c["text"]])
	ok(s75["verdict"] == "ok" and absf(s75["measured"] - 0.75) < 1e-4 and bad.is_empty() and as_kind.size() == Body.KINDS.size(),
		"(2) 75 cm sword %s ('%s'); Body.KINDS out of their ranges: %s" % [s75["verdict"], s75["text"], str(bad)])
	# 3 helmets
	var hs := R.check(box(0.16, 0.15, 0.14), "helmet")
	var hm := R.check(box(0.20, 0.19, 0.178), "helmet")
	var hb := R.check(box(0.26, 0.24, 0.22), "helmet")
	ok(absf(rf["head_breadth"] - 0.1734) < 0.001 and hs["verdict"] == "wrong" and (hs["text"] as String).contains("head breadth") and (hs["text"] as String).contains("17.3 cm") and hm["verdict"] == "suspicious" and hb["verdict"] == "ok",
		"(3) helmet: head breadth %.1f cm; small %s '%s'; 17.8 cm %s; 22 cm %s" % [rf["head_breadth"] * 100.0, hs["verdict"], hs["text"], hm["verdict"], hb["verdict"]])
	# 4 units
	var big := box(75.0, 6.0, 1.0)
	var sb := R.check(big, "sword")
	var u: Dictionary = sb["units"]
	R.rescale(big, u.get("factor", 1.0), sb["box"]["center"])
	var after := R.check(big, "sword")
	var tiny := R.check(box(0.00075, 0.00006, 0.00001), "sword")
	ok(sb["verdict"] == "wrong" and (u.get("say", "") as String).contains("made in cm") and absf(u.get("factor", 0.0) - 0.01) < 1e-12 and absf(after["measured"] / 0.75 - 1.0) < 0.01 and after["verdict"] == "ok" and absf(tiny["units"].get("factor", 0.0) - 1000.0) < 1e-9,
		"(4) 75 m sword: %s, '%s'; rescaled %.4f m (%s, %.4f%% off); 0.75 mm sword factor %s" % [sb["verdict"], u.get("say", ""), after["measured"], after["verdict"], absf(after["measured"] / 0.75 - 1.0) * 100.0, str(tiny["units"].get("factor"))])
	# 5 proportions
	var B2 := Body.new()
	B2.body = {"scale": {"upper_arm": 1.2, "forearm": 1.2}}
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var rf2 := R.refs(B2)
	var r1 := R.range_of("sword", rf)
	var r2 := R.range_of("sword", rf2)
	var k_arm: float = rf2["arm"] / rf["arm"]
	var k_lo: float = r2["lo"] / r1["lo"]
	var k_hi: float = r2["hi"] / r1["hi"]
	var k_w: float = (r2["hi"] - r2["lo"]) / (r1["hi"] - r1["lo"])
	ok(absf(k_arm - 1.2) < 0.0012 and absf(k_lo - 1.2) < 0.0012 and absf(k_hi - 1.2) < 0.0012 and absf(k_w - 1.2) < 0.0012 and absf(rf2["stature"] - rf["stature"]) < 1e-6,
		"(5) arms x1.2: arm %.1f -> %.1f cm (x%.5f), sword range %s -> %s (lo x%.5f, hi x%.5f, width x%.5f)" % [rf["arm"] * 100.0, rf2["arm"] * 100.0, k_arm, R._fmt_range(r1["lo"], r1["hi"]), R._fmt_range(r2["lo"], r2["hi"]), k_lo, k_hi, k_w])
	# 6 the guess
	var g := box(0.25, 0.22, 0.24)
	var names := {"Iron_Helmet": "helmet", "GreatSword": "longsword", "combat_knife": "dagger", "body_01": "prop"}
	var wrong_g := []
	for nm in names:
		var kk: String = R.guess_kind(g, nm)["kind"]
		if kk != names[nm]:
			wrong_g.append("%s -> %s" % [nm, kk])
	KMeshBody.ensure(g)
	for v in g.vert_count():
		g.set_attr(KMeshBody.CH_REGION, v, float(KMeshBody.REGIONS.find("head")))
		g.set_attr(KMeshBody.CH_BONE, v, float(KMeshBody.BONES.find("head")))
		g.set_attr(KMeshBody.CH_CM, v, 5.0)
	var gw := R.guess_kind(g)
	for v in g.vert_count():
		g.set_attr(KMeshBody.CH_CM, v, 40.0)
	var gf := R.guess_kind(g)
	var fs := R.findings(box(75.0, 6.0, 1.0), "sword")
	ok(wrong_g.is_empty() and gw["kind"] == "helmet" and gf["kind"] == "prop" and fs.size() == 2 and fs[0]["id"] == "real_size" and fs[0]["level"] == "fail" and fs[1]["id"] == "real_size_units",
		"(6) guess: names wrong %s; on the head %s (%s); 40 cm off %s; findings %s" % [str(wrong_g), gw["kind"], gw["why"], gf["kind"], str(fs.map(func(f): return [f["id"], f["level"]]))])
	await _app()
	print("REAL SIZE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)


func _tool(id: String) -> Dictionary:
	for t in MeshTools.TOOLS:
		if t["id"] == id:
			return t
	return {}


func _app() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	var ui: KMeshEditUI = m.kmed
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.6, 0.25, 3.2, wc + Vector3(0, 0.1, 0), false)
	await idle(4)
	var img_off := await shot()
	MeshTools.run(_tool("mesh_realsize"), m)
	await idle(4)
	var rs := RealSizeUI.get_or_null(m)
	var img := await shot()
	img.save_png("user://realsize.png")
	var said := String(m.ui_status.text) if m.get("ui_status") != null else ""
	var r := rs.get_global_rect() if rs != null else Rect2()
	var b := rs.screen_box if rs != null else Rect2()
	var inner: Rect2 = m.nav_clear_rect().grow(-RealSizeUI.PAD + 0.5)
	var mid_y := r.get_center().y
	var gap_r := r.position.x - b.end.x
	var gap_l := b.position.x - r.end.x
	var beside := mid_y >= b.position.y and mid_y <= b.end.y and (absf(gap_r - RealSizeUI.GAP) <= 1.0 or absf(gap_l - RealSizeUI.GAP) <= 1.0)
	var over := []
	if rs != null:
		for a in rs.avoid_rects():
			if r.intersects(a):
				over.append(a)
	var k := Vector2(img.get_size()) / root.get_visible_rect().size
	var q := Vector2i((r.get_center() * k).round()).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE)
	var dpx := dist(img.get_pixelv(q), img_off.get_pixelv(q))
	ok(rs != null and rs.visible and said.contains("real size") and inner.encloses(r) and not r.intersects(b) and beside and over.is_empty() and dpx > 0.1 and rs.result.get("kind") == "prop" and rs.result.get("verdict") == "ok",
		"(7) readout %s beside the cube's box %s (gaps right %.1f / left %.1f, beside %s, inside %s %s, over panels %s of %s), pixel moved %.2f; %s %s; said '%s'" % [str(r), str(b), gap_r, gap_l, beside, inner.encloses(r), str(inner), str(over), str(rs.avoid_rects() if rs else []), dpx, rs.result.get("kind") if rs else "-", rs.result.get("verdict") if rs else "-", said])
	# x100, then the button
	ui.undo.begin(ui.mesh)
	RealSize.rescale(ui.mesh, 100.0, rs.result["box"]["center"])
	ui.undo.commit("test: x100")
	ui.view.mark_dirty()
	rs.recheck(false)
	await idle(3)
	var v100: String = rs.result["verdict"]
	var btn: Button = rs.get_node_or_null("VBoxContainer/btn_realsize_fix") if rs.get_node_or_null("VBoxContainer/btn_realsize_fix") != null else rs.find_child("btn_realsize_fix", true, false)
	var btn_ok := btn != null and btn.visible and btn.text.contains("x0.01")
	var n_steps := ui.undo.steps.size()
	if btn != null:
		btn.pressed.emit()
	await idle(3)
	var long1: float = RealSize.obb(ui.mesh)["size"][0]
	var steps1 := ui.undo.steps.size()
	ui.undo.undo()
	ui.view.mark_dirty()
	var long0: float = RealSize.obb(ui.mesh)["size"][0]
	ok(v100 == "wrong" and btn_ok and absf(long1 / 0.6 - 1.0) < 0.01 and steps1 == n_steps + 1 and absf(long0 - 60.0) < 0.01,
		"(7) x100: %s, button '%s'; pressed: long side %.4f m (%.4f%% off 0.6), undo steps %d -> %d; Ctrl+Z: %.3f m" % [v100, btn.text if btn else "-", long1, absf(long1 / 0.6 - 1.0) * 100.0, n_steps, steps1, long0])
	MeshTools.run(_tool("mesh_realsize"), m)
	await idle(2)
	ok(rs != null and not rs.visible, "(7) the op again hides the readout")
	print("  shot: ", ProjectSettings.globalize_path("user://realsize.png"))
