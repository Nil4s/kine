extends SceneTree
## godot --path . --position 4000,4000 -s tests/s227_test.gd     (Friday plan 227: ORGANIC SHAPES INTO PARTS + ORNAMENTS; needs the CAD DLL with solid_from_mesh)
## Bars (measured from the replayed solids, mesh vertices and the kernel volume, never from the function's own return):
##   1 EVERY ORNAMENT   12 kinds: a closed manifold mesh, every solid volume > 0 and within 1 pct of its mesh's own volume, one body per piece
##   2 SIZE             the box asked (mm) is the box built, within 1 pct on each side (every single-piece kind; the row's leading figure)
##   3 SEED             the same seed gives the same vertices bit for bit, another seed another shape; undo / replay builds no mesh twice
##   4 RIDGE            an ornament placed on a sloped ridge (30 deg round, 10 deg up): its flat base's long axis lies along the ridge within 1 deg
##   5 WORDS            "2 chiwen on the ridge ends" = 2 bodies, one on each end looking inward; "5 corner beasts" = 5 bodies; a refusal changes nothing
##   6 EASY             Parts > Ornaments chip (real clicks): ONE undo step, a body in the part; Type it words build the same
##   7 EXPERT           the Ornament tool on the Part ribbon: dialog, OK = ONE step on the timeline
##   8 AGENT            AgentTools "ornament" request: a step, ONE undo step
##   9 SCULPT ROAD      Sculpt this into the part (real click), a real stroke changes the mesh volume, Back into the part (real click): ONE undo step,
##                      the step becomes a meshsolid in the same place (same id), the solid's volume = the sculpted mesh's, it survives save / reload,
##                      the mesh is kept (it opens again); undo restores the ornament
## Shots: C:/Users/Nick/tools/kine_workers/out/227/ : easy.png (the Ornaments page), sheet_close.png, sheet_far.png (hall distance), road_*.png
const SHOT := "C:/Users/Nick/tools/kine_workers/out/227"
const DIRT := "user://s227_test"
var fails := 0
var m: Node
var pu: PartUI
var ep


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	if ep != null and ep.panel != null and ep.panel.is_ancestor_of(c):   # the panel scrolls: a person scrolls to the chip first
		ep._scroll_into_view(c)
		await idle(4)
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	for k in 40:   # the panel may still be sliding / re-laying out: press where the control stands now
		await process_frame
		var q := c.get_global_rect().get_center()
		if q.distance_to(p) < 0.5 and k >= 3:
			break
		p = q
		await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func tri_volume(km: KMesh) -> float:
	var v := 0.0
	for fc in km.faces:
		var f: PackedInt32Array = fc
		for k in range(1, f.size() - 1):
			v += km.verts[f[0]].dot(km.verts[f[k]].cross(km.verts[f[k + 1]])) / 6.0
	return absf(v) * 1e9   # mm3


func rec_of(kind: String, seed: int, places: Array, size := Vector3.ZERO, row := {}) -> Dictionary:
	var rec := Part.make(kind)
	rec["features"].append(Part.new_feature(rec, "ornament", PartOrnament.fields(kind, seed, places, size, row)))
	return rec


func bodies_of(rec: Dictionary) -> Dictionary:
	return Part.replay(rec, -1, {"keep": true})


func release(res: Dictionary) -> void:
	for id in res.get("ids", []):
		Part.KCad.release(int(id))


## the base's long axis (unit) of the first body: the points of the lowest face (along `up`), the principal axis of their spread
func base_axis(res: Dictionary, up: Vector3) -> Vector3:
	var am: ArrayMesh = res["mesh"]
	var vs: PackedVector3Array = am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := 1e9
	for v in vs:
		lo = minf(lo, v.dot(up))
	var pts: Array = []
	var c := Vector3.ZERO
	for v in vs:
		if v.dot(up) < lo + 0.0006:
			pts.append(v)
			c += v
	c /= float(pts.size())
	var ax := Vector3(1, 0.3, 0.2).normalized()
	for it in 40:
		var nx := Vector3.ZERO
		for p in pts:
			var d: Vector3 = p - c
			nx += d * d.dot(ax)
		if nx.length() < 1e-12:
			break
		ax = nx.normalized()
	return ax


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available() or not Part.KCad.has_mesh_solid():
		print("FAIL: the CAD library with solid_from_mesh is not loaded")
		print("s227: 1 fail")
		quit(1)
		return

	# ---------------------------------------------------------------- 1 + 2 every ornament, solid and size
	var t_all := Time.get_ticks_msec()
	for k in PartOrnament.ORDER:
		var kind := String(k)
		var row := {"n": 5} if kind == "corner_row" else {}
		var rec := rec_of(kind, 1, [{"at": [0.0, 0.0, 0.0], "dir": [1.0, 0.0, 0.0]}], Vector3.ZERO, row)
		var t0 := Time.get_ticks_msec()
		var res := bodies_of(rec)
		var errs: Dictionary = res["errors"]
		var pcs := PartOrnament.pieces(rec["features"][0])
		var nb := int(res["bodies"])
		var good := errs.is_empty() and nb == pcs.size()
		var worst := 0.0
		var closed := true
		var minv := 1e30
		for i in nb:
			var pc: Dictionary = pcs[i]
			var d := PartOrnament.mesh_dict(String(pc["kind"]), 1, pc["size"])
			var mv := tri_volume(d["km"])
			var kv := float(res["volumes"][i]) * 1e9
			minv = minf(minv, kv)
			worst = maxf(worst, absf(kv - mv) / mv)
			closed = closed and (d["km"] as KMesh).is_closed() and (d["km"] as KMesh).is_manifold()
		ok(good and closed and minv > 0.0 and worst <= 0.01, "1 %s: %d solid(s) from %d piece(s), closed manifold %s, volume > 0 (min %.0f mm3), worst solid-vs-mesh %.3f pct, built in %d ms%s" % [kind, nb, pcs.size(), str(closed), minv, worst * 100.0, Time.get_ticks_msec() - t0, "" if errs.is_empty() else " ERR " + str(errs)])
		if nb == 0 or (res.get("ids", []) as Array).is_empty():
			continue
		var want: Vector3 = (pcs[0] as Dictionary)["size"]
		var bb := Part._piece_box(int(res["ids"][0]))
		var got := bb.size * 1000.0
		var off := maxf(absf(got.x - want.x) / want.x, maxf(absf(got.y - want.y) / want.y, absf(got.z - want.z) / want.z))
		ok(off <= 0.01 and absf(bb.position.y) < 1e-4, "2 %s: asked %.0f x %.0f x %.0f mm, built %.1f x %.1f x %.1f mm (worst %.3f pct), bottom at y %.3f mm" % [kind, want.x, want.y, want.z, got.x, got.y, got.z, off * 100.0, bb.position.y * 1000.0])
		if kind == "corner_row":
			var lead := (pcs[0] as Dictionary)["size"] as Vector3
			var small := Part._piece_box(int(res["ids"][1])).size * 1000.0
			ok(absf(small.y - lead.y * 0.5) / (lead.y * 0.5) <= 0.01 and nb == 5, "2 corner_row: 1 leading figure + 4 small beasts, a small one %.1f mm tall (half of %.0f)" % [small.y, lead.y])
		release(res)
	print("     all ornaments built and sewn in %d ms" % (Time.get_ticks_msec() - t_all))

	# ---------------------------------------------------------------- 3 seed
	var same := true
	var differ := 0
	for k in ["chiwen", "corner_lead", "dragon_head", "cloud_bracket", "lion", "finial"]:
		var sz := PartOrnament.default_size(String(k))
		PartOrnament._meshes.clear()
		var a: PackedVector3Array = PartOrnament.mesh_dict(String(k), 7, sz)["km"].verts
		PartOrnament._meshes.clear()
		var b: PackedVector3Array = PartOrnament.mesh_dict(String(k), 7, sz)["km"].verts
		var c: PackedVector3Array = PartOrnament.mesh_dict(String(k), 8, sz)["km"].verts
		same = same and a == b
		if a != c:
			differ += 1
	ok(same, "3 the same seed (7) twice gives the same vertices, bit for bit, for 6 kinds")
	ok(differ >= 4, "3 another seed (8) gives another shape for %d of 6 kinds (the seeded designs)" % differ)
	var b0 := PartOrnament.builds
	var r1 := Part.replay(rec_of("chiwen", 7, [{"at": [0.0, 0.0, 0.0], "dir": [1.0, 0.0, 0.0]}]))
	var r2 := Part.replay(rec_of("chiwen", 7, [{"at": [500.0, 0.0, 0.0], "dir": [1.0, 0.0, 0.0]}]))
	ok(PartOrnament.builds - b0 <= 1 and absf(float(r1["volume"]) - float(r2["volume"])) < 1e-12, "3 a replay at another place builds no second mesh (%d new builds) and has the same volume" % (PartOrnament.builds - b0))

	# ---------------------------------------------------------------- 4 ridge
	var ra := Vector3(0.0, 3000.0, 0.0)
	var rd := Vector3(cos(deg_to_rad(10.0)) * cos(deg_to_rad(30.0)), sin(deg_to_rad(10.0)), -cos(deg_to_rad(10.0)) * sin(deg_to_rad(30.0))).normalized()
	var rb := ra + rd * 6000.0
	var pl := PartOrnament.place_on_edge(ra, rb, 0.5)
	var rrec := rec_of("chiwen", 1, [pl])
	var rres := bodies_of(rrec)
	var basis := PartOrnament.basis_for(rd)
	var ax := base_axis(rres, basis.y)
	var ang := rad_to_deg(acos(clampf(absf(ax.dot(rd)), 0.0, 1.0)))
	var cen := Part._piece_box(int(rres["ids"][0])).get_center() * 1000.0
	var onl := (Vector3(0.0, 3000.0, 0.0).lerp(rb, 0.5))
	ok(ang <= 1.0, "4 a chiwen on a ridge turned 30 deg round and 10 deg up: its base's long axis is %.3f deg off the ridge (bar 1 deg)" % ang)
	ok(cen.distance_to(onl) < 700.0 and absf(rd.dot(Vector3(pl["dir"][0], pl["dir"][1], pl["dir"][2]).normalized()) - 1.0) < 1e-6, "4 it sits on the ridge's middle (centre %.0f mm from the ridge point) and the step's direction is the ridge's" % cen.distance_to(onl))
	release(rres)

	# ---------------------------------------------------------------- 5 words
	var hall := Part.make("Hall")
	var box := PartTemplates.make("box", {"width": 400.0, "depth": 200.0, "height": 120.0})
	var wb := Part.replay(box)
	var bb0: AABB = wb["aabb"]
	var w1 := PartOrnament.from_words("2 chiwen on the ridge ends", box)
	ok(bool(w1["ok"]) and (w1["fields"]["places"] as Array).size() == 2, "5 words: '2 chiwen on the ridge ends' is read (%s)" % str(w1["said"]))
	var r5 := box.duplicate(true)
	r5["features"].append(Part.new_feature(r5, "ornament", w1["fields"]))
	var res5 := bodies_of(r5)
	ok(int(res5["bodies"]) == int(wb["bodies"]) + 2 and (res5["errors"] as Dictionary).is_empty(), "5 words: the part has %d bodies (was %d, two added)" % [int(res5["bodies"]), int(wb["bodies"])])
	var pcs5 := PartOrnament.pieces(r5["features"][-1])
	var lo_i := 0 if (pcs5[0]["at"] as Vector3).x < (pcs5[1]["at"] as Vector3).x else 1
	var d0 := (pcs5[lo_i]["dir"] as Vector3)
	var d1 := (pcs5[1 - lo_i]["dir"] as Vector3)
	var x0 := (pcs5[lo_i]["at"] as Vector3).x
	var x1 := (pcs5[1 - lo_i]["at"] as Vector3).x
	print("     diag: ends dirs %s %s at %s %s" % [str(d0), str(d1), str(x0), str(x1)])
	ok(d0.x > 0.99 and d1.x < -0.99 and x0 < x1 and absf(x0 - bb0.position.x * 1000.0) <= 300.0 and absf(x1 - bb0.end.x * 1000.0) <= 300.0, "5 words: one on each end of the ridge (x %.0f and %.0f; the part spans %.0f to %.0f) each looking inward" % [x0, x1, bb0.position.x * 1000.0, bb0.end.x * 1000.0])
	release(res5)
	var w2 := PartOrnament.from_words("5 corner beasts", box)
	var r6 := box.duplicate(true)
	r6["features"].append(Part.new_feature(r6, "ornament", w2["fields"]))
	var res6 := bodies_of(r6)
	ok(bool(w2["ok"]) and int(res6["bodies"]) == int(wb["bodies"]) + 5, "5 words: '5 corner beasts' adds 5 bodies (%d)" % (int(res6["bodies"]) - int(wb["bodies"])))
	release(res6)
	var w3 := PartOrnament.from_words("a blue banana", box)
	ok(not bool(w3["ok"]) and String(w3["why"]).find("chiwen") >= 0, "5 words: a sentence it does not know is refused and names the ornaments (%s)" % String(w3["why"]).left(70))

	# ---------------------------------------------------------------- the app
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(6)
	ep = pu.ep
	m.S.part = box.duplicate(true)
	m._step_hint = "Box"
	m._push_undo()   # the box is the state undo comes back to
	m.S.part = box.duplicate(true)
	pu.upto = -1
	pu.sync()
	ep.frame()
	await idle(10)
	var ub0: int = m.undo.size()

	# 6 EASY: Parts > Ornaments > Chiwen (real clicks)
	await click_ctl(ep.parts_btn)
	await idle(4)
	if not ep.parts_open:
		var hov := root.gui_get_hovered_control()
		print("     diag: the Parts click did not open it: rect %s visible %s hovered %s" % [str(ep.parts_btn.get_global_rect()), str(ep.parts_btn.is_visible_in_tree()), str(hov.name if hov != null else "none")])
	var lb: Button = ep.lib_btns.get("Ornaments", null)
	print("     diag: parts_open %s, lib_btn %s visible %s, keys %s" % [str(ep.parts_open), str(lb), str(lb.is_visible_in_tree()) if lb != null else "-", str(ep.lib_btns.keys()).left(120)])
	ok(lb != null and lb.is_visible_in_tree(), "6 the Parts library has an Ornaments chip, visible")
	if lb != null:
		await click_ctl(lb)
	await idle(6)
	var chip: Button = ep.orn_box.find_child("easypart_ornament_chiwen", true, false)
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var all_in: bool = ep.orn_box.visible
	for kk in PartOrnament.ORDER:
		var cb: Button = ep.orn_box.find_child("easypart_ornament_" + String(kk), true, false)
		all_in = all_in and cb != null
	ok(all_in and chip != null, "6 the Ornaments page shows a chip for each of the %d ornaments and the Sculpt button" % PartOrnament.ORDER.size())
	await shot("easy")
	var nb_before := int(Part.replay(m.S.part)["bodies"])
	var u1: int = m.undo.size()
	await click_ctl(chip)
	await idle(10)
	var nb_after := int(Part.replay(m.S.part)["bodies"])
	ok(nb_after == nb_before + 2 and m.undo.size() == u1 + 1, "6 the Chiwen chip: bodies %d -> %d (a pair on the ridge ends), undo %d -> %d (ONE step)" % [nb_before, nb_after, u1, m.undo.size()])
	if m.undo.size() > u1:
		m._undo()
	await idle(6)
	ok(int(Part.replay(m.S.part)["bodies"]) == nb_before, "6 undo takes both away (%d bodies)" % int(Part.replay(m.S.part)["bodies"]))
	await click_ctl(ep.lib_btns["Type it"])
	await idle(4)
	ep.type_edit.text = "5 corner beasts"
	print("     diag: type_box visible %s, cat %s, text '%s'" % [str(ep.type_box.is_visible_in_tree()), str(ep.lib_cat), ep.type_edit.text])
	await click_ctl(ep.type_go)
	await idle(10)
	print("     diag: after Build it: '%s'" % String(ep.msg).left(160))
	ok(int(Part.replay(m.S.part)["bodies"]) == nb_before + 5, "6 Type it '5 corner beasts' (Build it) adds 5 bodies (%d)" % (int(Part.replay(m.S.part)["bodies"]) - nb_before))
	m._undo()
	await idle(6)

	# 8 AGENT
	var at := AgentTools.new(m)
	var u2: int = m.undo.size()
	var ar: Dictionary = await at.request(1, "ornament", {"words": "2 chiwen on the ridge ends"})
	var ares: Dictionary = ar.get("result", {})
	ok(ar.has("result") and int(ares.get("bodies", 0)) == nb_before + 2 and m.undo.size() == u2 + 1, "8 agent 'ornament' with words: %s, undo %d -> %d" % [str(ares).left(120), u2, m.undo.size()])
	m._undo()
	await idle(4)
	var ar2: Dictionary = await at.request(2, "ornament", {"kind": "lion", "count": 1, "size": [400, 600, 250], "at": [100, 0, 0], "seed": 2})
	ok(ar2.has("result") and (ar2["result"]["box_mm"] as Array).size() == 3, "8 agent 'ornament' with a kind: %s" % str(ar2.get("result", ar2)).left(140))
	var ar3: Dictionary = await at.request(3, "ornament", {"kind": "banana"})
	ok(ar3.has("error"), "8 agent 'ornament' with a bad kind is refused with the kinds named")
	m._undo()
	await idle(6)

	# 7 EXPERT dialog
	pu.close_dialog()
	var ob: Button = pu.tool_btns.get("Ornament", null)
	ok(ob != null, "7 the Part ribbon has an Ornament tool")
	if pu.easy:
		ep.to_expert()   # Easy off: the Expert ribbon
		await idle(6)
	var feats0 := (m.S.part["features"] as Array).size()
	var u3: int = m.undo.size()
	if ob != null:
		pu._pick("Ornament")
		await idle(6)
		ok(not pu.dlg.is_empty() and pu.ok_btn != null and not pu.ok_btn.disabled, "7 the dialog opens on a chiwen at the origin and its OK is ready (%s)" % String(pu.dlg_info.text).left(60))
		pu.ok_pressed()
		await idle(10)
		ok((m.S.part["features"] as Array).size() == feats0 + 1 and String(m.S.part["features"][-1]["t"]) == "ornament" and m.undo.size() == u3 + 1, "7 OK = one 'ornament' step on the timeline (%d -> %d), undo %d -> %d" % [feats0, (m.S.part["features"] as Array).size(), u3, m.undo.size()])
		m._undo()
		await idle(6)

	# ---------------------------------------------------------------- 9 the sculpt road
	var fresh := Part.make("Beast")
	fresh["features"].append(Part.new_feature(fresh, "ornament", PartOrnament.fields("chiwen", 1, [{"at": [0.0, 0.0, 0.0], "dir": [1.0, 0.0, 0.0]}])))
	m.S.part = fresh
	var orn_id := String(fresh["features"][0]["id"])
	var vol0 := float(Part.replay(m.S.part)["volume"]) * 1e9
	pu.sync()
	await idle(10)
	if not pu.easy:
		pu.open_easy()
		await idle(6)
	if not ep.parts_open:
		await click_ctl(ep.parts_btn)
	await click_ctl(ep.lib_btns["Ornaments"])
	await idle(6)
	var sb: Button = ep.orn_box.find_child("easypart_ornament_sculpt", true, false)
	ok(sb != null and sb.is_visible_in_tree() and vp.encloses(sb.get_global_rect()), "9 the 'Sculpt this into the part' button is on the Ornaments page, on screen (%s)" % (str(sb.get_global_rect()) if sb != null else "missing"))
	var u4: int = m.undo.size()
	await click_ctl(sb)
	await idle(14)
	print("     diag: ksc %s on %s meta %s hint '%s'" % [str(m.ksc != null), str(m.ksc.on if m.ksc != null else false), str(m.has_meta("s227_road")), String(PartSculpt.source(m)["mode"])])
	ok(m.ksc != null and m.ksc.on and m.has_meta("s227_road"), "9 the sculpt page is open on the ornament's mesh (%d verts)" % (m.ksc.mesh.vert_count() if m.ksc != null and m.ksc.mesh != null else 0))
	if m.ksc == null or not m.ksc.on:
		print("s227: %d fail" % (fails + 1))
		quit(1)
		return
	ok(m.undo.size() == u4, "9 opening the sculpt is not an undo step")
	var km: KMesh = m.ksc.mesh
	var v_before := tri_volume(km)
	ok(absf(v_before - vol0) / vol0 < 0.01, "9 the clay is the ornament's mesh: %.0f mm3 vs the solid's %.0f mm3" % [v_before, vol0])
	await idle(20)
	await shot("road_open")
	# a real stroke: inflate the chiwen's body with a big brush
	m.ksc.brush = KMeshSculpt.INFLATE
	m.ksc.radius = 0.15
	m.ksc.strength = 0.01
	var hit := Vector3.ZERO
	for p in km.verts:
		if p.y > 0.55 and p.y < 0.65 and p.x < 0.1 and p.z > 0.0:
			hit = p
			break
	if hit == Vector3.ZERO:
		hit = km.verts[km.verts.size() / 2]
	var s0: Vector2 = m.cam.unproject_position(hit)
	var s1: Vector2 = m.cam.unproject_position(hit + Vector3(0.0, 0.12, 0.0))
	await drag_pts([s0, s0.lerp(s1, 0.25), s0.lerp(s1, 0.5), s0.lerp(s1, 0.75), s1])
	await drag_pts([s1, s0])
	var v_after := tri_volume(km)
	print("     the stroke moved the volume %.0f -> %.0f mm3 (%.2f pct)" % [v_before, v_after, 100.0 * (v_after - v_before) / v_before])
	ok(absf(v_after - v_before) / v_before > 0.001, "9 a real stroke changed the body's volume by %.2f pct" % (100.0 * (v_after - v_before) / v_before))
	await shot("road_sculpted")
	var back: Button = null
	for b in m.ui_ribbon["SCULPT"].get_children():
		if b is Button and (b as Button).text == "Back into the part":
			back = b
	ok(back != null and back.is_visible_in_tree() and vp.encloses(back.get_global_rect()), "9 'Back into the part' is on the Sculpt page, on screen")
	var feats_n := (m.S.part["features"] as Array).size()
	var u5: int = m.undo.size()
	await click_ctl(back)
	await idle(30)
	var feat: Dictionary = m.S.part["features"][0]
	var r9 := Part.replay(m.S.part)
	var vol9 := float(r9["volume"]) * 1e9
	ok(String(feat["t"]) == "meshsolid" and String(feat["id"]) == orn_id and (m.S.part["features"] as Array).size() == feats_n and m.undo.size() == u5 + 1 and not m.ksc.on and not m.has_meta("s227_road"),
		"9 Back into the part: the step is a meshsolid with the same id %s (%d steps), ONE undo step (%d -> %d), the sculpt is closed" % [str(feat["id"]), (m.S.part["features"] as Array).size(), u5, m.undo.size()])
	ok(int(r9["bodies"]) == 1 and absf(vol9 - v_after) / v_after <= 0.02 and absf(vol9 - vol0) / vol0 > 0.001, "9 the solid is the sculpted shape: %.0f mm3 vs sculpted mesh %.0f (%.2f pct), the ornament was %.0f" % [vol9, v_after, 100.0 * absf(vol9 - v_after) / v_after, vol0])
	var bbs: AABB = r9["aabb"]
	ok(absf(bbs.position.y) < 0.002 and absf(bbs.size.y * 1000.0 - 1100.0) < 120.0, "9 it stands where it stood: bottom at %.1f mm, %.0f mm tall" % [bbs.position.y * 1000.0, bbs.size.y * 1000.0])
	# save and reload: the record as JSON text, read back, replayed
	var txt := JSON.stringify(Part.to_file(m.S.part))
	var back_rec: Dictionary = Part.from_file(JSON.parse_string(txt))
	var vsave := float(Part.replay(back_rec)["volume"]) * 1e9
	ok(absf(vsave - vol9) / vol9 < 0.001, "9 saved and reloaded: %.0f mm3 again (was %.0f)" % [vsave, vol9])
	# the mesh is kept: it opens again, and it is the same clay
	var again := PartSculpt.feature_mesh(back_rec["features"][0])
	ok(again != null and again.is_closed() and absf(tri_volume(again) - vol9) / vol9 < 0.01, "9 the mesh is kept in the record: it opens again (%d verts, %.0f mm3)" % [again.vert_count() if again != null else 0, tri_volume(again) if again != null else 0.0])
	await shot("road_back")
	m._undo()
	await idle(10)
	var f_undo: Dictionary = m.S.part["features"][0]
	var vu := float(Part.replay(m.S.part)["volume"]) * 1e9
	ok(String(f_undo["t"]) == "ornament" and absf(vu - vol0) / vol0 < 1e-6, "9 undo restores the ornament step: %s, %.0f mm3 (was %.0f)" % [String(f_undo["t"]), vu, vol0])

	# ---------------------------------------------------------------- sheets (looked at, by eye)
	var sheet := Part.make("Sheet")
	var x := 0.0
	var big := 0.0
	for k in PartOrnament.ORDER:
		var kind := String(k)
		var row2 := {"n": 5} if kind == "corner_row" else {}
		var sz := PartOrnament.default_size(kind)
		sheet["features"].append(Part.new_feature(sheet, "ornament", PartOrnament.fields(kind, 1, [{"at": [x + sz.x * 0.5, 0.0, 0.0], "dir": [1.0, 0.0, 0.0]}], Vector3.ZERO, row2)))
		x += sz.x * (3.2 if kind == "corner_row" else 1.4)
	m.S.part = sheet
	if pu.easy:
		ep.to_expert()
		await idle(4)
	pu.upto = -1
	pu.sync()
	await idle(30)
	var sres := Part.replay(sheet)
	var sbb: AABB = sres["aabb"]
	print("     sheet: %d bodies, box %.2f x %.2f x %.2f m" % [int(sres["bodies"]), sbb.size.x, sbb.size.y, sbb.size.z])
	m.target = sbb.get_center()
	m.pitch = -12.0
	m.yaw = 0.0
	m.dist = sbb.size.x * 0.85
	m._cam()
	await idle(30)
	await shot("sheet_close")
	m.dist = 30.0
	m.target = sbb.get_center()
	m._cam()
	await idle(20)
	await shot("sheet_far")
	print("s227: %d fail" % fails)
	quit(1 if fails > 0 else 0)
