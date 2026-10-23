## godot --path . -s tests/modelcheck_test.gd     (ROADMAP_400 B30: model checks; needs a window)
## scripts/model_checks.gd (the grade) + scripts/model_checks_ui.gd (the page, MeshTools "op:model_checks"). Bars, written
## before the first run:
##  ARMS (a cylinder along X, r 4 cm, 8 sides, tri-fan caps at x = +-18 cm; hand-made segments upperarm_l (-35 -> 0 cm),
##  lowerarm_l (0 -> 35 cm), hand_l (35 -> 45 cm): the elbow at the origin, its bend zone +-6 cm)
##   (1) GOOD arm (rings every 3 cm, all quads): the surface is clean (KMeshValidate), the elbow zone holds verts
##       (instrument: > 0), >= 3 loops counted across the elbow, NO finding, score 100
##   (2) BAD arm (rings at -18 -9 0 9 18 cm; the two quads across the elbow ring at sector 0 merged into a hexagon, the
##       pair at sector 4 re-split along the other diagonal): EXACTLY three findings, all at elbow_l: "pole" with exactly
##       the 4 elbow-ring verts that lost an edge (the two 5-poles sit 9 cm out, outside the zone), "ngon" with exactly
##       the hexagon, "loops" counting exactly 1; its score is lower than the good arm's; the findings' points add up to
##       100 - score (the stated formula) within 1e-6
##   (3) THIN: a 10 x 10 cm plate 3 mm thick: every inner vert of its two big faces (18) is flagged, the thickness read
##       within 0.3 mm of 3 mm; CONTROL: the same plate 2 cm thick has no thin vert
##   (4) SURFACE: the good arm with one quad wound backwards: a "flipped" finding whose edges are exactly that quad's 4
##   (5) WEIGHTS: H01 channels with 3 verts left at no weight -> "unweighted" exactly those 3; G01 "skin:" channels with
##       5 bones on 2 verts -> "over4" exactly those 2; the unweighted good arm is "not skinned" (no weight finding)
##  APP (main.tscn)
##   (6) the bad arm open in the preview, the MeshTools line "op:model_checks" shows the page; Grade (the button, the
##       test's segments) lists the same 3 findings; each "Show me" leaves exactly the finding's elements selected in its
##       mode, and the elements' centre lands on the centre of the free view right of the panel (within 2 px)
##   (7) PLACEMENT: the panel lies inside the free view (nav_clear_rect), overlaps no other visible model panel or legend,
##       and after "Show me" every shown element projects inside the free view and outside the panel
##   (8) the mannequin (G01 "Model: edit the body mesh") is graded: a score 0-100, findings listed (printed: score + the
##       top 5), points add up; "Show me" on each of the top 5 selects exactly its elements; the placement bar again
extends SceneTree

var fails := 0
var m: Node
const N := 8
const R := 0.04


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func seg(bone: String, a: Vector3, b: Vector3) -> Dictionary:
	return {"bone": bone, "bi": KMeshBody.BONES.find(bone), "a": a, "b": b}


func arm_segs(xf := Transform3D.IDENTITY) -> Array:
	return [seg("upperarm_l", xf * Vector3(-0.35, 0, 0), xf * Vector3.ZERO), seg("lowerarm_l", xf * Vector3.ZERO, xf * Vector3(0.35, 0, 0)),
		seg("hand_l", xf * Vector3(0.35, 0, 0), xf * Vector3(0.45, 0, 0))]


func vid(i: int, k: int) -> int:
	return i * N + (k % N)


## the cylinder: rings at xs, quads wound outward, tri-fan caps. bad: the hexagon at sector 0 and the re-split at
## sector 4 across ring `mid` -> {"mesh", "hex" (face id), "poles" (vert ids)}
func arm(xs: Array, bad := false) -> Dictionary:
	var vs := PackedVector3Array()
	for x in xs:
		for k in N:
			var a := TAU * k / N
			vs.append(Vector3(x, R * cos(a), R * sin(a)))
	var c0 := vs.size()
	vs.append(Vector3(xs[0], 0, 0))
	vs.append(Vector3(xs[xs.size() - 1], 0, 0))
	var fs: Array = []
	var mid := xs.find(0.0)
	var hex := -1
	for i in xs.size() - 1:
		for k in N:
			if bad and i == mid - 1 and (k == 0 or k == 4):
				continue   # made below, across the elbow ring
			if bad and i == mid and (k == 0 or k == 4):
				continue
			fs.append([vid(i, k), vid(i, k + 1), vid(i + 1, k + 1), vid(i + 1, k)])
	if bad:
		hex = fs.size()
		fs.append([vid(mid - 1, 0), vid(mid - 1, 1), vid(mid, 1), vid(mid + 1, 1), vid(mid + 1, 0), vid(mid, 0)])
		fs.append([vid(mid - 1, 4), vid(mid - 1, 5), vid(mid + 1, 4), vid(mid, 4)])
		fs.append([vid(mid - 1, 5), vid(mid, 5), vid(mid + 1, 5), vid(mid + 1, 4)])
	var last := xs.size() - 1
	for k in N:
		fs.append([c0, vid(0, k + 1), vid(0, k)])
		fs.append([c0 + 1, vid(last, k), vid(last, k + 1)])
	var km := KMesh.new().from_arrays(vs, fs)
	var poles := [vid(mid, 0), vid(mid, 1), vid(mid, 4), vid(mid, 5)] if bad else []
	return {"mesh": km, "hex": hex, "poles": poles}


func good_xs() -> Array:
	var xs := []
	for i in 13:
		xs.append(snappedf(-0.18 + 0.03 * i, 1e-9))
	xs[6] = 0.0
	return xs


func kinds(r: Dictionary) -> Array:
	var out := []
	for f in r["findings"]:
		out.append("%s@%s" % [f["kind"], f["joint"]])
	out.sort()
	return out


func find(r: Dictionary, kind: String) -> Dictionary:
	for f in r["findings"]:
		if f["kind"] == kind:
			return f
	return {}


func as_set(a: Array) -> Dictionary:
	var d := {}
	for x in a:
		d[x] = true
	return d


func same_set(a: Array, b: Array) -> bool:
	return a.size() == b.size() and as_set(a).size() == as_set(b).size() and as_set(a).keys().all(func(x): return as_set(b).has(x))


func sum_ok(r: Dictionary) -> bool:
	var s := 0.0
	for f in r["findings"]:
		s += float(f["pts"])
	return absf(s - (100.0 - float(r["points"]))) < 1e-6


func plate(th: float) -> KMesh:
	var c := KMeshView.make_cube(1.0, 4)
	for v in c.verts.size():
		var p := c.verts[v]
		c.verts[v] = Vector3(p.x * 0.1, p.y * th, p.z * 0.1)
	c.rebuild()
	return c


func _init() -> void:
	# ---------------------------------------------------------------- (1) good arm
	var segs := arm_segs()
	var g := arm(good_xs())
	var gm: KMesh = g["mesh"]
	ok(KMeshValidate.report(gm)["ok"], "(1) the good arm's surface is clean (KMeshValidate)")
	var rg := ModelChecks.grade(gm, segs)
	var gj := {}
	for j in rg["joints"]:
		if j["name"] == "elbow_l":
			gj = j
	ok(not gj.is_empty() and int(gj["verts"]) > 0, "(1) instrument: the elbow zone holds %s verts (bar > 0)" % str(gj.get("verts", 0)))
	ok(int(gj.get("loops", -1)) >= 3, "(1) loops across the good elbow: %d (bar >= 3)" % int(gj.get("loops", -1)))
	ok(rg["findings"].is_empty() and int(rg["score"]) == 100, "(1) the good arm: %d findings %s, score %d (bar: none, 100)" % [rg["findings"].size(), kinds(rg), int(rg["score"])])
	# ---------------------------------------------------------------- (2) bad arm
	var b := arm([-0.18, -0.09, 0.0, 0.09, 0.18], true)
	var bm: KMesh = b["mesh"]
	var rb := ModelChecks.grade(bm, segs)
	print("     bad arm: score %d, %.1f ms: %s" % [int(rb["score"]), float(rb["ms"]), ", ".join(rb["findings"].map(func(f): return "%s %.2f pts" % [f["title"], f["pts"]]))])
	ok(kinds(rb) == ["loops@elbow_l", "ngon@elbow_l", "pole@elbow_l"], "(2) the bad arm's findings are exactly pole, n-gon, loops at elbow_l: %s" % [kinds(rb)])
	var fp := find(rb, "pole")
	ok(not fp.is_empty() and same_set(fp["items"], b["poles"]), "(2) the pole finding holds exactly the 4 elbow-ring verts %s: %s" % [b["poles"], fp.get("items", [])])
	var fn := find(rb, "ngon")
	ok(not fn.is_empty() and fn["items"] == [b["hex"]], "(2) the n-gon finding is exactly the hexagon (face %d): %s" % [b["hex"], fn.get("items", [])])
	var fl := find(rb, "loops")
	ok(not fl.is_empty() and int(fl["loops"]) == 1, "(2) loops across the bad elbow: %s (bar exactly 1)" % str(fl.get("loops", "-")))
	ok(int(rb["score"]) < int(rg["score"]), "(2) the bad arm scores lower: %d < %d" % [int(rb["score"]), int(rg["score"])])
	ok(sum_ok(rb) and sum_ok(rg), "(2) the findings' points add up to 100 - score (bad: %.4f lost)" % (100.0 - float(rb["points"])))
	# ---------------------------------------------------------------- (3) thin
	var p3 := plate(0.003)
	var r3 := ModelChecks.grade(p3, [])
	var th := ModelChecks.thin_verts(p3, p3.verts, ModelChecks.THIN)
	var inner := []
	for v in p3.verts.size():
		var q := p3.verts[v]
		if absf(absf(q.x) - 0.05) > 1e-6 and absf(absf(q.z) - 0.05) > 1e-6:
			inner.append(v)
	var tset := as_set(Array(th["verts"]))
	var worst := 0.0
	for k in (th["verts"] as PackedInt32Array).size():
		if inner.has(th["verts"][k]):
			worst = maxf(worst, absf(float(th["mm"][k]) - 3.0))
	ok(inner.size() == 18 and inner.all(func(v): return tset.has(v)) and worst <= 0.3, "(3) the 3 mm plate: %d / %d inner verts flagged, thickness off 3 mm by at most %.3f mm (bar 0.3); %d flagged in all" % [inner.filter(func(v): return tset.has(v)).size(), inner.size(), worst, tset.size()])
	ok(not find(r3, "thin").is_empty(), "(3) the grade lists it: %s" % find(r3, "thin").get("title", "-"))
	var p20 := plate(0.02)
	var r20 := ModelChecks.thin_verts(p20, p20.verts, ModelChecks.THIN)
	ok((r20["verts"] as PackedInt32Array).is_empty() and int(r20["rays"]) > 0, "(3) control: the 2 cm plate has %d thin verts (%d rays cast)" % [(r20["verts"] as PackedInt32Array).size(), int(r20["rays"])])
	# ---------------------------------------------------------------- (4) flipped
	var g4: KMesh = arm(good_xs())["mesh"]
	var ff := PackedInt32Array(g4.faces[20])
	ff.reverse()
	g4.faces[20] = ff
	g4.rebuild()
	var r4 := ModelChecks.grade(g4, segs)
	var want4 := []
	for i in 4:
		want4.append(Vector2i(mini(ff[i], ff[(i + 1) % 4]), maxi(ff[i], ff[(i + 1) % 4])))
	var f4 := find(r4, "flipped")
	ok(not f4.is_empty() and same_set(f4["items"], want4) and int(f4["mode"]) == ModelChecks.SEL_EDGE, "(4) a reversed quad: 'flipped' with exactly its 4 edges %s: %s" % [want4, f4.get("items", [])])
	# ---------------------------------------------------------------- (5) weights
	var g5: KMesh = arm(good_xs())["mesh"]
	ok(not ModelChecks.weight_problems(g5)["skinned"] and find(ModelChecks.grade(g5, segs), "unweighted").is_empty(), "(5) the unweighted arm is not skinned: no weight finding")
	KMeshWPaint.ensure_channels(g5)
	var cb := PackedColorArray()
	var cw := PackedColorArray()
	var none := [3, 40, 77]
	for v in g5.verts.size():
		cb.append(Color(0, -1, -1, -1))
		cw.append(Color(0.0 if none.has(v) else 1.0, 0, 0, 0))
	g5.set_attr_data(KMeshAutoWeights.CH_BONES, cb)
	g5.set_attr_data(KMeshAutoWeights.CH_WEIGHTS, cw)
	var r5 := ModelChecks.grade(g5, segs)
	ok(same_set(find(r5, "unweighted").get("items", []), none) and find(r5, "over4").is_empty(), "(5) H01 weights: 'unweighted' is exactly %s: %s" % [none, find(r5, "unweighted").get("items", [])])
	var g6: KMesh = arm(good_xs())["mesh"]
	var many := [10, 50]
	for q in 6:
		var col := PackedFloat32Array()
		for v in g6.verts.size():
			col.append((0.2 if q < 5 else 0.0) if many.has(v) else (1.0 if q == 0 else 0.0))
		g6.add_attr(BaseBody.W + "b%d" % q, KMesh.AD_VERT, TYPE_FLOAT, 0.0)
		g6.set_attr_data(BaseBody.W + "b%d" % q, col)
	var r6 := ModelChecks.grade(g6, segs)
	ok(same_set(find(r6, "over4").get("items", []), many) and find(r6, "unweighted").is_empty(), "(5) G01 weights: 'over4' is exactly %s: %s" % [many, find(r6, "over4").get("items", [])])
	# ---------------------------------------------------------------- APP
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	if m.kmed == null:
		m.kmed = KMeshEditUI.new()
		m.add_child(m.kmed)
		m.kmed.setup(m)
	var bad_app: KMesh = arm([-0.18, -0.09, 0.0, 0.09, 0.18], true)["mesh"]
	m.kmed.source = func(): return {"mesh": bad_app, "at": Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, 0.0))}
	m._kmesh_edit_start()
	await idle(2)
	var line: Dictionary = MeshTools.TOOLS.filter(func(t): return t["id"] == "mesh_model_checks")[0]
	MeshTools.run(line, m)
	await idle(2)
	var ui := ModelChecksUI.of(m)
	ok(ui.visible and m.kmed.on, "(6) the MeshTools line opens the page: '%s'" % m.ui_status.text)
	var xf: Transform3D = m.kmed.view.global_transform
	ui.segs_override = arm_segs(xf)
	(ui.get_node("vb").get_child(0).get_node("btn_mc_grade") as Button).pressed.emit()
	await idle(2)
	ok(kinds(ui.res) == ["loops@elbow_l", "ngon@elbow_l", "pole@elbow_l"], "(6) Grade in the app (the arm moved to %s): %s, score %d" % [xf.origin, kinds(ui.res), int(ui.res["score"])])
	await show_all(ui, ui.res["findings"].size(), "(6) bad arm")
	# ---------------------------------------------------------------- (8) the mannequin
	m.kmed.stop()
	await idle(2)
	ok(not ui.visible, "(6) leaving the preview hides the page")
	ui.segs_override = null
	cmd("Model: edit the body mesh")
	await idle(3)
	ok(BaseBody.is_open(m), "(8) the fighter's body is open in the preview (%d verts)" % m.kmed.mesh.verts.size())
	MeshTools.op("model_checks", m)
	await idle(3)
	var rm: Dictionary = ui.res
	var fs: Array = rm["findings"]
	print("     MANNEQUIN: score %d / 100 (%.0f ms, %d findings, %d thin rays)" % [int(rm["score"]), float(rm["ms"]), fs.size(), int(rm["thin_rays"])])
	for i in fs.size():
		print("       %d. -%.2f  %s  [%d elements]  next: %s" % [i + 1, float(fs[i]["pts"]), fs[i]["title"], int(fs[i]["count"]), fs[i]["next"]])
	for j in rm["joints"]:
		print("       zone %s: %d verts, %d faces%s" % [j["name"], int(j["verts"]), int(j["faces"]), (", %d loops" % int(j["loops"])) if int(j["loops"]) >= 0 else ""])
	ok(ui.visible and int(rm["score"]) >= 0 and int(rm["score"]) <= 100 and not fs.is_empty() and sum_ok(rm), "(8) the mannequin is graded: %d / 100, %d findings, points add up" % [int(rm["score"]), fs.size()])
	ok(rm["joints"].size() >= 8, "(8) instrument: %d bend zones found on the body (bar >= 8 of the 10)" % rm["joints"].size())
	await show_all(ui, mini(5, fs.size()), "(8) mannequin")
	quit(1 if fails > 0 else 0)


func cmd(name: String) -> void:
	for c in m._commands():
		if c["name"] == name:
			(c["run"] as Callable).call()
			return
	ok(false, "command '%s' is in the registry" % name)


## the free view (between the side panels, under the top bars, above the status line)
func free_rect() -> Rect2:
	return m.nav_clear_rect()


func others() -> Array:
	var out := []
	var ed = m.kmed
	for c in [ed.prim_panel, ed.mat_panel, ed.legend, ed.mods.panel if ed.mods != null else null, ed.body.legend if ed.body != null else null,
			ed.anat.legend if ed.anat != null else null]:
		if c != null and is_instance_valid(c) and (c as Control).is_visible_in_tree():
			out.append(c)
	return out


func show_all(ui: ModelChecksUI, n: int, tag: String) -> void:
	var cl := free_rect()
	var pr := ui.get_global_rect()
	var clash := []
	for o in others():
		if (o as Control).get_global_rect().intersects(pr):
			clash.append(String((o as Control).name))
	ok(cl.encloses(pr) and clash.is_empty() and pr.size.x >= 300.0, "(7) %s: the panel %s lies inside the free view %s and overlaps no other panel %s" % [tag, pr, cl, clash])
	for i in n:
		var f: Dictionary = ui.res["findings"][i]
		var btn := ui.find_child("btn_mc_show_%d" % i, true, false) as Button
		if btn == null:
			ok(false, "%s: row %d has a Show me button" % [tag, i])
			continue
		btn.pressed.emit()
		await idle(2)
		var sel: KMeshSelect = m.kmed.sel
		var live: Dictionary = [sel.verts, sel.edges, sel.faces][int(f["mode"])]
		ok(sel.mode == int(f["mode"]) and same_set(live.keys(), f["items"]), "(6) %s Show me %d '%s': %d selected in mode %d, exactly its %d elements" % [tag, i + 1, f["title"], live.size(), sel.mode, int(f["count"])])
		var pts := ModelChecks.points_of(m.kmed.mesh, f, m.kmed.view.global_transform)
		var lo := pts[0]
		var hi := pts[0]
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		var cam: Camera3D = m.cam
		var off := cam.unproject_position((lo + hi) * 0.5).distance_to(ui.view_region().get_center())
		ok(off <= 2.0, "(6) %s the elements' centre lands on the centre of the view right of the panel (off by %.2f px, bar 2)" % [tag, off])
		var outside := 0
		var under := 0
		for p in pts:
			var s := cam.unproject_position(p)
			if cam.is_position_behind(p) or not cl.has_point(s):
				outside += 1
			elif ui.get_global_rect().has_point(s):
				under += 1
		ok(outside == 0 and under == 0, "(7) %s finding %d: of its %d element points, %d fall outside the free view, %d under the panel (bar 0, 0)" % [tag, i + 1, pts.size(), outside, under])
