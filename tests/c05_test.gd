## godot --path . -s tests/c05_test.gd     (C05: complaints #311 bad spots, #619 hand shape, #618 finger bleed; needs a window)
## Bars, written before the first run:
##  SPOTS (#311): the broken cube of kmesh_validate_test (vert 8 doubles 6, vert 9 loose, face 5 degenerate, top missing):
##   (1) spots() has a "doubled" spot whose items are exactly [8], a "loose" spot exactly [9], a "degenerate" spot exactly
##       [5] in FACE mode; CONTROL: the clean cube has 0 spots (so the bar can fail)
##   (2) marker_mesh of the doubled spot has 6 line verts (one 3-line cross) and no depth test; of the clean cube: empty
##  APP: the broken cube open in the preview (x0.3 m), MeshTools "op:mesh_spots":
##   (3) the panel is visible, lists >= 3 rows; Jump on the doubled row leaves exactly vert 8 selected, a red marker
##       child on the view, and the centre of the spot projects within 2 px of the centre of the free view region
##   (4) See-through on: the surface transparency is KMeshSpots.SEE_THROUGH (0.65); off: 0.0 (a control that reads 0 first)
##   (5) Next spot cycles: after Jump on row 0, next_spot() selects row 1's elements
##   (6) the panel lies inside the free view at 1280x720; screenshot saved for the eye
##   LAYOUT (lead, 11-02): at 1280x720 AND 1024x600, with the panel open and the spot list full (15 rows):
##   (15) the panel's rect intersects no other visible control's rect (PanelContainers, buttons, labels, outside it, none
##        wider than 40 % of the window); the Scan and Next spot buttons' rects intersect none either
##   (16) at 1280x720 the list shows >= 6 rows (its height / the first row's height)
##   (17) CONTROL: the old layout (top left of the free view, cl.position + 12) FAILS (15): the same check reports >= 1 overlap
##   (3) amended: the spot is centred in the free view LEFT of the panel (the panel now sits at the view's right end)
##  HAND (#619): a hand of 5 fingers (8-sided, 5 rings, 8 cm, radius 8 mm) on hand_l + finger bones
##   (7) the good hand has 0 findings and 5 fingers each with >= 6 verts; CONTROL for the others
##   (8) one middle-finger vert pulled 9 cm off the hand: findings kinds exactly ["spike", "stretched"], the spike items
##       exactly that vert
##   (9) the ring finger's verts removed (faces dropped, verts moved to the palm): exactly one "missing_finger" naming ring
##   (10) the pinky at radius 1 mm: exactly "thin_finger"; the index at radius 4 cm: exactly "fat_finger"
##   (11) ModelChecks.grade has no hand kind for the (8) hand (the old check does not see it): control
##  BLEED (#618): the same hand, finger k's verts on bone k at weight 1
##   (12) clean: 0 findings and every finger owns >= 6 verts; palm weight (40 % on hand) on 4 middle verts is NOT bleed
##   (13) 12 index verts at 0.7 index / 0.3 middle: exactly one finding, items exactly those 12, bleeding to middle_l
##   (14) after KMeshAutoWeights.bind on the hand: the flagged set equals an independent recount of every vert with more than
##        BLEED_MAX of its weight on another finger's bones (printed: count)
extends SceneTree

var fails := 0
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c05"
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func broken() -> KMesh:
	var v := PackedVector3Array(CV)
	v.append(Vector3(1, 1, 1))
	v.append(Vector3(5, 5, 5))
	var f := [[0,3,2,1], [4,5,8,7], [0,1,5,4], [1,2,6,5], [3,7,4,0], [0,1,1]]
	return KMesh.new().from_arrays(v, f)


func clean() -> KMesh:
	return KMesh.new().from_arrays(PackedVector3Array(CV), [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]])


func kinds(a: Array) -> Array:
	var o := a.map(func(f): return f["kind"])
	o.sort()
	return o


func same(a: Array, b: Array) -> bool:
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	return x == y


const FN := ["thumb", "index", "middle", "ring", "pinky"]
const NR := 5
const NS := 8


## the hand: finger k = rings of NS verts along +x from 0.05 to 0.13 at z = (k-2) x 0.02; radius per finger
func hand(radius := {}) -> Dictionary:
	var verts := PackedVector3Array()
	var faces := []
	var fv := {}
	for k in 5:
		var r: float = radius.get(FN[k], 0.008)
		var base := verts.size()
		fv[k] = []
		for i in NR:
			for s in NS:
				var a := TAU * s / NS
				verts.append(Vector3(0.05 + 0.02 * i, r * cos(a), (k - 2) * 0.02 + r * sin(a)))
				fv[k].append(verts.size() - 1)
		for i in NR - 1:
			for s in NS:
				faces.append([base + i * NS + s, base + i * NS + (s + 1) % NS, base + (i + 1) * NS + (s + 1) % NS, base + (i + 1) * NS + s])
	var mesh := KMesh.new().from_arrays(verts, faces)
	return {"mesh": mesh, "fv": fv}


func bones() -> Array:
	var out := [{"name": "hand_l", "id": 0, "a": Vector3.ZERO, "ends": PackedVector3Array([Vector3(0.05, 0, 0)]), "parent": -1}]
	for k in 5:
		var z := (k - 2) * 0.02
		out.append({"name": "%s_01_l" % FN[k], "id": k + 1, "a": Vector3(0.05, 0, z), "ends": PackedVector3Array([Vector3(0.13, 0, z)]), "parent": 0})
	return out


func set_weights(mesh: KMesh, ids: Array, ws: Array) -> void:
	var nv := mesh.verts.size()
	var cb := PackedColorArray()
	var cw := PackedColorArray()
	cb.resize(nv)
	cw.resize(nv)
	for v in nv:
		cb[v] = Color(ids[v][0], ids[v][1], -1, -1)
		cw[v] = Color(ws[v][0], ws[v][1], 0, 0)
	for ch in [[KMeshAutoWeights.CH_BONES, cb, Color(-1, -1, -1, -1)], [KMeshAutoWeights.CH_WEIGHTS, cw, Color(0, 0, 0, 0)]]:
		mesh.add_attr(ch[0], KMesh.AD_VERT, TYPE_COLOR, ch[2])
		mesh.set_attr_data(ch[0], ch[1])


func finger_weights(h: Dictionary, bleed := {}) -> Array:
	var nv: int = (h["mesh"] as KMesh).verts.size()
	var ids := []
	var ws := []
	ids.resize(nv)
	ws.resize(nv)
	for k in 5:
		for v in h["fv"][k]:
			ids[v] = [k + 1, bleed.get(v, [-1, 0.0])[0]]
			var b: float = bleed.get(v, [-1, 0.0])[1]
			ws[v] = [1.0 - b, b]
	return [ids, ws]


func _init() -> void:
	# ---- SPOTS
	var sp := KMeshSpots.spots(broken())
	var by := {}
	for s in sp:
		by[s["kind"]] = s
	print("  spots: ", sp.map(func(s): return "%s %s" % [s["kind"], str(s["items"])]))
	ok(by.has("doubled") and same(by["doubled"]["items"], [8]) and by.has("loose") and same(by["loose"]["items"], [9]) and by.has("degenerate") and same(by["degenerate"]["items"], [5]) and by["degenerate"]["mode"] == 2, "(1) broken cube spots: doubled [8], loose [9], degenerate face [5]")
	ok(KMeshSpots.spots(clean()).is_empty(), "(1) CONTROL: the clean cube has 0 spots")
	var mk := KMeshSpots.marker_mesh(broken(), by["doubled"])
	var nvm := (mk.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if mk.get_surface_count() > 0 else -1
	ok(nvm == 6 and (mk.surface_get_material(0) as StandardMaterial3D).no_depth_test and KMeshSpots.marker_mesh(clean(), {"mode": 0, "items": []}).get_surface_count() == 0, "(2) marker: %d line verts, no depth test; empty spot -> empty" % nvm)
	# ---- HAND
	var good := hand()
	var g := HandShapeCheck.check(good["mesh"], bones(), "l")
	var minv := 99
	for f in g["fingers"]:
		minv = mini(minv, (g["fingers"][f]["verts"] as Array).size())
	ok(g["findings"].is_empty() and g["fingers"].size() == 5 and minv >= 6, "(7) good hand: %d findings, 5 fingers, fewest verts %d (region %d)" % [g["findings"].size(), minv, g["region"]])
	var bad := hand()
	var pv: int = bad["fv"][2][12]
	(bad["mesh"] as KMesh).verts[pv] = Vector3(0.09, 0.09, 0.0)
	var rb := HandShapeCheck.check(bad["mesh"], bones(), "l")
	var sk = rb["findings"].filter(func(f): return f["kind"] == "spike")
	ok(kinds(rb["findings"]) == ["spike", "stretched"] and sk.size() == 1 and same(sk[0]["items"], [pv]), "(8) warped hand: %s, spike %s (vert %d)" % [str(kinds(rb["findings"])), str(sk[0]["items"]) if sk.size() else "-", pv])
	var miss := hand()
	for v in miss["fv"][3]:
		(miss["mesh"] as KMesh).verts[v] = Vector3(0.0, 0.0, 0.0)
	var rm := HandShapeCheck.check(miss["mesh"], bones(), "l")
	var mf = rm["findings"].filter(func(f): return f["kind"] == "missing_finger")
	ok(mf.size() == 1 and String(mf[0]["title"]).contains("ring"), "(9) ring finger gone: %s" % str(rm["findings"].map(func(f): return f["title"])))
	var rt := HandShapeCheck.check(hand({"pinky": 0.001})["mesh"], bones(), "l")
	var rf := HandShapeCheck.check(hand({"index": 0.04})["mesh"], bones(), "l")
	ok(kinds(rt["findings"]) == ["thin_finger"] and kinds(rf["findings"]).has("fat_finger"), "(10) thin pinky %s; fat index %s" % [str(kinds(rt["findings"])), str(kinds(rf["findings"]))])
	var segs := [{"bone": "hand_l", "bi": KMeshBody.BONES.find("hand_l"), "a": Vector3.ZERO, "b": Vector3(0.05, 0, 0)}]
	var old := ModelChecks.grade(bad["mesh"], segs)
	ok(not old["findings"].any(func(f): return ["spike", "stretched", "missing_finger"].has(f["kind"])), "(11) CONTROL: the old grade on the warped hand: %s" % str(old["findings"].map(func(f): return f["kind"])))
	# ---- BLEED
	var hc := hand()
	var fwc := finger_weights(hc)
	var mid_palm := {}
	for i in 4:
		mid_palm[hc["fv"][2][i]] = [0, 0.4]
	var fw0 := finger_weights(hc, mid_palm)
	set_weights(hc["mesh"], fw0[0], fw0[1])
	var c0 := FingerBleedCheck.check(hc["mesh"], bones())
	var minown := 99
	for k in c0["fingers"]:
		minown = mini(minown, c0["fingers"][k]["owned"])
	ok(c0["skinned"] and c0["findings"].is_empty() and minown >= 6, "(12) clean + palm weight: %d findings, fewest owned %d" % [c0["findings"].size(), minown])
	var hb := hand()
	var bl := {}
	var want := []
	for i in 12:
		var v: int = hb["fv"][1][i]
		bl[v] = [3, 0.3]
		want.append(v)
	var fw1 := finger_weights(hb, bl)
	set_weights(hb["mesh"], fw1[0], fw1[1])
	var c1 := FingerBleedCheck.check(hb["mesh"], bones())
	ok(c1["findings"].size() == 1 and same(c1["findings"][0]["items"], want) and (c1["fingers"]["index_l"]["to"] as Dictionary).keys() == ["middle_l"], "(13) index bleeds 12 verts into middle: %s" % str(c1["findings"].map(func(f): return f["title"])))
	var ha := hand()
	var br := KMeshAutoWeights.bind(ha["mesh"], bones())
	var c2 := FingerBleedCheck.check(ha["mesh"], bones())
	var flagged := []
	for k in c2["fingers"]:
		flagged.append_array(c2["fingers"][k]["bleeding"])
	var rd := KMeshAutoWeights.read(ha["mesh"])
	var kid := {}
	for b in bones():
		kid[b["id"]] = FingerBleedCheck.key_of(b["name"])
	var rec := []
	for v in ha["mesh"].verts.size():
		var by2 := {}
		var tot := 0.0
		for q in 4:
			var wt: float = rd["w"][v * 4 + q]
			if wt > 0.0:
				tot += wt
				var kk: String = kid.get(rd["ids"][v * 4 + q], "")
				if kk != "":
					by2[kk] = by2.get(kk, 0.0) + wt
		var own := ""
		var on := 0.0
		for kk in by2:
			on += by2[kk]
			if own == "" or by2[kk] > by2[own]:
				own = kk
		if own != "" and on / tot >= FingerBleedCheck.OWN_MIN and (on - by2[own]) / tot > FingerBleedCheck.BLEED_MAX:
			rec.append(v)
	ok(br["error"] == "" and same(flagged, rec), "(14) autoweights on the hand: flagged %d verts, independent recount %d; say(): %s" % [flagged.size(), rec.size(), FingerBleedCheck.say(ha["mesh"], bones())])
	await app()
	print("C05 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func app() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	if m.kmed == null:
		m.kmed = KMeshEditUI.new()
		m.add_child(m.kmed)
		m.kmed.setup(m)
	var src := broken()
	for i in src.verts.size():
		src.verts[i] = (src.verts[i] - Vector3(0.5, 0.5, 0.5)) * 0.3
	src.verts[9] = Vector3(0.6, 0.4, 0.3)
	m.kmed.source = func(): return {"mesh": src, "at": Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, 0.0))}
	m._kmesh_edit_start()
	await idle(2)
	var line: Dictionary = MeshTools.TOOLS.filter(func(t): return t["id"] == "mesh_spots")[0]
	MeshTools.run(line, m)
	await idle(2)
	var ui := KMeshSpotsUI.of(m)
	ok(ui.visible and ui.spots.size() >= 3, "(3) panel open with %d spots" % ui.spots.size())
	var di := -1
	for i in ui.spots.size():
		if ui.spots[i]["kind"] == "doubled":
			di = i
	(ui.find_child("btn_sp_jump_%d" % di, true, false) as Button).pressed.emit()
	await idle(3)
	var ed = m.kmed
	var selv: Array = ed.sel.verts.keys()
	var cam: Camera3D = m.cam
	var wp: Vector3 = ed.view.global_transform * ed.mesh.verts[8]
	var sc := cam.unproject_position(wp)
	var reg: Rect2 = ui.view_region()
	ok(same(selv, [8]) and ui._marks != null and ui._marks.get_parent() == ed.view and sc.distance_to(reg.get_center()) <= 2.0, "(3) Jump selects exactly vert 8, red marker on the view, spot %.1f px from the view centre" % sc.distance_to(reg.get_center()))
	var surf = ed.view.get("_surf")
	var t0: float = surf.transparency
	(ui.find_child("chk_sp_see", true, false) as CheckButton).button_pressed = true
	await idle(2)
	var t1: float = surf.transparency
	(ui.find_child("chk_sp_see", true, false) as CheckButton).button_pressed = false
	await idle(2)
	ok(t0 == 0.0 and absf(t1 - KMeshSpots.SEE_THROUGH) < 1e-6 and surf.transparency == 0.0, "(4) see-through %.2f -> %.2f -> %.2f" % [t0, t1, surf.transparency])
	(ui.find_child("chk_sp_see", true, false) as CheckButton).button_pressed = true
	await idle(2)
	ui.jump(0)
	ui.next_spot()
	await idle(2)
	var want: Array = ui.spots[1]["items"]
	var got: Array = ed.sel.verts.keys() if ui.spots[1]["mode"] == 0 else (ed.sel.faces.keys() if ui.spots[1]["mode"] == 2 else ed.sel.edges.keys())
	ok(ui.cur == 1 and same(got, want), "(5) next_spot goes to row 1 (%s), selection %s" % [ui.spots[1]["kind"], str(got)])
	m.get_viewport().get_texture().get_image().save_png(SHOT + "/spots_1280x720.png")
	await layout("1280x720", true)
	root.min_size = Vector2i(0, 0)
	root.size = Vector2i(1024, 600)
	root.content_scale_size = Vector2i(1024, 600)
	await idle(8)
	ui.place()
	await idle(2)
	await layout("1024x600", false)
	TestFiles.cleanup()


## the visible controls outside the panel that count as "another panel": not mouse-transparent, under 40 % of the window wide
func others(ui: Control) -> Array:
	var out := []
	var vs := Vector2(root.size)
	for c in m.ui_root.find_children("*", "Control", true, false):
		var ct := c as Control
		if ct == ui or ui.is_ancestor_of(ct) or ct.is_ancestor_of(ui) or not ct.is_visible_in_tree():
			continue
		if ct.mouse_filter == Control.MOUSE_FILTER_IGNORE and not (ct is PanelContainer):
			continue
		var r := ct.get_global_rect()
		if r.size.x < 8 or r.size.y < 8 or r.size.x > 0.4 * vs.x or r.size.y > 0.8 * vs.y:
			continue
		out.append(ct)
	return out


func hits(ui: Control, r: Rect2) -> Array:
	return others(ui).filter(func(c): return c.get_global_rect().intersects(r)).map(func(c): return "%s %s" % [c.name, str(c.get_global_rect())])


func layout(tag: String, rows_bar: bool) -> void:
	var ui := KMeshSpotsUI.of(m)
	var pr := ui.get_global_rect()
	var h := hits(ui, pr)
	var nb := ui.find_child("btn_sp_next", true, false) as Button
	var sb := ui.find_child("btn_sp_scan", true, false) as Button
	var bh := hits(ui, nb.get_global_rect()) + hits(ui, sb.get_global_rect())
	var cl: Rect2 = m.nav_clear_rect()
	print("     window %s viewport %s" % [str(root.size), str(m.get_viewport().get_visible_rect().size)])
	ok(h.is_empty() and bh.is_empty() and cl.encloses(pr), "(15) %s: panel %s overlaps %s, buttons covered by %s, inside free view %s" % [tag, str(pr), str(h), str(bh), str(cl)])
	var row0: Control = ui._rows.get_child(0)
	var rows := ui._scroll.size.y / maxf(1.0, row0.size.y + KMeshSpotsUI.ROW_GAP)
	if rows_bar:
		ok(rows >= 6.0, "(16) %s: the list shows %.1f rows (list %.0f px, row %.0f px)" % [tag, rows, ui._scroll.size.y, row0.size.y])
	else:
		print("     %s: list shows %.1f rows" % [tag, rows])
	m.get_viewport().get_texture().get_image().save_png(SHOT + "/spots_%s.png" % tag)
	if rows_bar:
		var old := Vector2(cl.position.x + 12.0, cl.position.y + 12.0)
		var save := ui.position
		ui.position = old
		await idle(2)
		var oh := hits(ui, ui.get_global_rect()) + hits(ui, nb.get_global_rect())
		ok(not oh.is_empty(), "(17) CONTROL: the old top-left layout overlaps %d control(s): %s" % [oh.size(), str(oh)])
		ui.position = save
		await idle(2)
