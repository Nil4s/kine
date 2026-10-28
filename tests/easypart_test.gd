extends SceneTree
## godot --path . --position 4000,4000 -s tests/easypart_test.gd     (EASY PART: scripts/easy_part.gd + scripts/build/part_templates.gd on the Part record of scripts/build/part.gd; needs a window and the CAD DLL)
## Bars, written before measuring (real clicks / drags through root.push_input at 1280 x 720; a 3D BUILDING project; Expert's Part button, then its Easy button):
##   1 TEMPLATES  each of sword, axe, shield, chair, crate (chip clicks) builds ONE closed solid: volume > 0, one body, no failed step, the tessellation watertight
##   2 SLIDER     sword Blade length dragged 76 -> 90 cm: the solid is 14 cm longer within 1 mm, the volume grows; ONE undo step per release (undo = 76 again, redo = 90)
##                while held: at most one rebuild per 100 ms (+2) and the worst frame < 100 ms
##   3 EXPERT     "Exact sizes? Use Expert" opens the same record in Expert: the same features (JSON equal), the Expert browser and timeline show
##   4 WORDS      no key name in any Easy text (labels, tooltips, hints, status): ctrl shift alt esc enter tab delete backspace F1..F12
##   5 LAYOUT     at 1280 x 720 the MAKE row, the panel, the hint, the shape choice and the status overlap nothing and stay inside the clear view
##   6 BUTTONS    Round the edges, Cut a hole, Mirror that, Draw shape (a box dragged on the grid), Pull it up (+ its slider), Spin it round: each ONE undo step, the volumes move the
##                right way; a refusal (Pull it up with no new shape) says why and leaves no step
##   7 DOTS       an amber dot dragged with the mouse changes its number (sword tip: Blade length) as the slider does, one undo step
##   8 NO DLL     Part.force_off: the buttons and sliders greyed with the reason, nothing changes
##   10 PARTFLOW (w4-partflow)  the sword's whole length under the sliders follows the blade slider; the Cut a hole default is a hole (2-10 cm across,
##                not 0.3 cm); "Use in a scene" on the Easy Part bar puts the part in the set as its own prop (page STAGE, ONE undo step); the Expert
##                strip's "Use in a scene" does the same for an Expert part
##   9 POLISH     axe head face > 2500 px2 from the default camera, its edge thinner than its eye; every template framed 3/4; Expert toast clear of timeline/browser/side panel; no group caption on the Easy buttons
##  11 PART FILE the Part props of the set saved to a file and reopened: each is there, its mesh has the same vertex count
## Shots in C:/Temp/claude/easypart/ (each template, a slider mid-drag). Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/easypart"
const DIRT := "user://easypart_test"


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
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## [holes (an edge without its reverse), triangles] of a mesh, vertices welded at 0.01 mm
func watertight(msh: ArrayMesh) -> Array:
	var a := msh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var key := {}
	var wid := PackedInt32Array()
	wid.resize(v.size())
	for i in v.size():
		var k := Vector3i((v[i] * 100000.0).round())
		if not key.has(k):
			key[k] = key.size()
		wid[i] = key[k]
	var edges := {}
	for t in ix.size() / 3:
		var a0 := wid[ix[t * 3]]
		var a1 := wid[ix[t * 3 + 1]]
		var a2 := wid[ix[t * 3 + 2]]
		if a0 == a1 or a1 == a2 or a0 == a2:
			continue
		for e in [[a0, a1], [a1, a2], [a2, a0]]:
			var k2: int = e[0] * 1000003 + e[1]
			edges[k2] = int(edges.get(k2, 0)) + 1
	var bad := 0
	for k2 in edges:
		var u: int = k2 / 1000003
		var w: int = k2 % 1000003
		if edges[k2] != 1 or int(edges.get(w * 1000003 + u, 0)) != 1:
			bad += 1
	return [bad, ix.size() / 3]


func overlaps(names: Array) -> Array:
	var bad := []
	var cl: Rect2 = m.nav_clear_rect()
	var rs := []
	for c in names:
		var ctl: Control = c
		if ctl.visible:
			rs.append([ctl.name, Rect2(ctl.global_position, ctl.size)])
	for i in rs.size():
		var r: Rect2 = rs[i][1]
		if r.position.x < cl.position.x - 1.0 or r.end.x > cl.end.x + 1.0 or r.position.y < cl.position.y - 1.0 or r.end.y > cl.end.y + 1.0:
			bad.append("%s outside the clear view %s (clear %s)" % [rs[i][0], r, cl])
		for j in range(i + 1, rs.size()):
			if r.intersects(rs[j][1]):
				bad.append("%s overlaps %s" % [rs[i][0], rs[j][0]])
	return bad


func texts(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Button:
		out.append((n as Button).text)
	if n is Label:
		out.append((n as Label).text)
	if n is Control:
		out.append((n as Control).tooltip_text)
	for c in n.get_children():
		texts(c, out)


func slider_x(s: HSlider, v: float) -> float:
	var r := s.get_global_rect()
	var gw := 24.0
	return r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)


## a real drag of the slider's knob to value v (held with the left button, in 24 mouse steps); the worst frame (ms), the rebuilds made and the time held
func drag_slider(s: HSlider, v: float, mid_shot := "") -> Dictionary:
	var y := s.get_global_rect().get_center().y
	var p0 := Vector2(slider_x(s, s.value), y)
	var ep: EasyPart = m.bld.part.ep
	var f0 := ep.flushes
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	var t_start := Time.get_ticks_msec()
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var x1 := slider_x(s, v)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		if i == 12 and mid_shot != "":
			await shot(mid_shot)
			last = Time.get_ticks_usec()
	var held_ms := Time.get_ticks_msec() - t_start
	var flushes_held := ep.flushes - f0
	await ev_mouse(Vector2(x1, y), false)
	await idle(2)
	return {"worst": worst, "flushes": flushes_held, "ms": held_ms}


func solid(rec: Dictionary) -> Dictionary:
	return Part.replay(rec)


func pnum(k: String) -> float:
	return float(m.S.part["easy"]["p"][k])


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
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	# Nick 2026-10-28: free 3D building, no forced house. The BUILDING card now opens a blank part on Part; this bar opens the
	# Part itself from BUILD, as it did before, so it starts from the same state (Part off, no part) it always did
	pu.set_on(false)
	m.S.part = {}
	await idle(8)   # the ribbon moves once Part is off: let it settle before a click
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and bld.on and not m.easy.on, "0 a BUILDING project on BUILD in Expert (page %s, kind %s, easy %s)" % [m.cur_page, m.S.kind, m.easy.on])
	var ep: EasyPart = pu.ep
	if not Part.available():
		print("SKIP: no KineCAD DLL; only the no-DLL bar can run")
		await click_ctl(pu.part_btn)
		pu.open_easy()
		await idle(4)
		var g := true
		for k in ep.make_btns:
			g = g and (ep.make_btns[k] as Button).disabled
		ok(pu.easy and g, "8 no DLL: the Easy buttons are greyed")
		print("easypart: %d fail (DLL missing: bars 1-7 skipped)" % fails)
		quit(1 if fails > 0 else 0)
		return
	await click_ctl(pu.part_btn)
	ok(pu.on and not pu.easy and pu.easy_open_btn.visible, "0 Part button: Expert's Part workspace with its Easy button")
	var n_undo: int = m.undo.size()
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ok(pu.easy and ep.bar.visible and ep.panel.visible and ep.make_box.visible and not pu.browser.visible and not pu.tl.visible, "0 Easy button: Easy's screen (bar, MAKE row, panel), Expert's browser and timeline away")
	ok(m.S.part.get("easy", {}).get("t", "") == "sword" and m.undo.size() == n_undo + 1, "0 a sword to begin with, ONE undo step (%d -> %d)" % [n_undo, m.undo.size()])

	# 1 TEMPLATES
	DirAccess.make_dir_recursive_absolute(SHOT)
	for t in PartTemplates.ORDER:
		var before: int = m.undo.size()
		await click_ctl(ep.chips[t])
		await idle(3)
		var rec: Dictionary = m.S.part
		var r := solid(rec)
		var w: Array = watertight(r["mesh"]) if r["mesh"] != null else [-1, 0]
		ok(rec.get("easy", {}).get("t", "") == t and int(r["bodies"]) == 1 and float(r["volume"]) > 0.0 and r["errors"].is_empty() and w[0] == 0 and w[1] > 0,
			"1 %s: one closed solid: bodies %d, volume %.1f cm3, failed steps %d, tessellation holes %d of %d triangles, undo +%d" % [t, int(r["bodies"]), float(r["volume"]) * 1e6, r["errors"].size(), w[0], w[1], m.undo.size() - before])
		ok(ep.rows.size() >= 3 and ep.rows.size() <= 5 and pu.part_mesh.visible and pu.part_mesh.mesh != null, "1 %s: %d sliders, the model shows" % [t, ep.rows.size()])
		await shot("template_" + t)

	# 9 POLISH (w4-partpolish): the axe has a real head seen from the default camera, every template is framed 3/4, no caption sits on the big buttons
	await click_ctl(ep.chips["axe"])
	await idle(3)
	var ax: Dictionary = m.S.part
	var axr := solid(ax)
	var hs: Dictionary = ax["features"][2]   # the head sketch
	var hpts := []
	for e in hs["ents"]:
		hpts.append(m.cam.unproject_position(Part.to_world(Part.plane("front"), Part.v2(e["a"]))))
	var area := 0.0
	for i in hpts.size():
		var q: Vector2 = hpts[i]
		var q2: Vector2 = hpts[(i + 1) % hpts.size()]
		area += q.x * q2.y - q2.x * q.y
	area = absf(area) * 0.5
	ok(area > 2500.0, "9 axe: the head's face seen from the default camera covers %.0f px2 (> 2500)" % area)
	var Hh := pnum("handle_length")
	var zmin_edge := INF
	var zmax_edge := -INF
	var zmin_eye := INF
	var zmax_eye := -INF
	for v in (axr["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if v.x > (Hh + 100.0) * 0.001:
			zmin_edge = minf(zmin_edge, v.z)
			zmax_edge = maxf(zmax_edge, v.z)
		if v.x > (Hh - 45.0) * 0.001 and v.x < (Hh + 5.0) * 0.001 and absf(v.y) > 0.018:
			zmin_eye = minf(zmin_eye, v.z)
			zmax_eye = maxf(zmax_eye, v.z)
	ok((zmax_edge - zmin_edge) < (zmax_eye - zmin_eye) * 0.5 and zmax_edge > zmin_edge, "9 axe: the blade edge (%.1f mm) is thinner than the eye (%.1f mm)" % [(zmax_edge - zmin_edge) * 1000.0, (zmax_eye - zmin_eye) * 1000.0])
	ok(absf(float(axr["aabb"].size.y) - pnum("head_width") * 0.001) < 0.002, "9 axe: the head is the Blade width tall (%.0f mm)" % (float(axr["aabb"].size.y) * 1000.0))
	await shot("axe_head")
	for t in PartTemplates.ORDER:
		await click_ctl(ep.chips[t])
		await idle(3)
		var yw := absf(wrapf(float(m.yaw), -180.0, 180.0))
		var pt := float(m.pitch)
		var bb: AABB = solid(m.S.part)["aabb"]
		var sc := Rect2()
		for c in 8:
			var pp: Vector2 = m.cam.unproject_position(bb.get_endpoint(c))
			sc = sc.expand(pp) if c > 0 else Rect2(pp, Vector2.ZERO)
		ok(yw > 15.0 and yw < 75.0 and absf(pt) > 8.0 and absf(pt) < 45.0 and sc.size.x > 90.0 and sc.size.y > 40.0, "9 %s: the default camera is 3/4 (yaw %.0f, pitch %.0f) and the part spans %.0f x %.0f px" % [t, yw, pt, sc.size.x, sc.size.y])
		await shot("view_" + t)
	var capclash := 0
	var mk: Rect2 = ep.make_box.get_global_rect()
	for t in m.ui_caps:
		for pr in m.ui_caps[t]:
			var cp: Control = pr[0]
			if cp.is_visible_in_tree() and cp.get_global_rect().intersects(mk):
				capclash += 1
	ok(capclash == 0, "9 no group caption (DRAW, ADD ...) sits on the Easy buttons (%d do)" % capclash)

	# 2 SLIDER: sword Blade length 76 -> 90 cm
	await click_ctl(ep.chips["sword"])
	await idle(3)
	var row: Dictionary = ep.rows[0]
	var sl: HSlider = row["slider"]
	ok(row["key"] == "blade_length" and is_equal_approx(sl.value, 76.0), "2 sword: the first slider is Blade length at 76 cm (%s %s)" % [row["key"], sl.value])
	var len0: float = solid(m.S.part)["aabb"].size.x
	var vol0: float = solid(m.S.part)["volume"]
	var u0: int = m.undo.size()
	var dr := await drag_slider(sl, 90.0, "slider_mid_drag")
	await idle(3)
	var r2 := solid(m.S.part)
	var d_mm: float = (float(r2["aabb"].size.x) - len0) * 1000.0
	ok(is_equal_approx(sl.value, 90.0) and is_equal_approx(pnum("blade_length"), 900.0), "2 the slider reads 90 cm and the record 900 mm (slider %s, record %s)" % [sl.value, pnum("blade_length")])
	ok(absf(d_mm - 140.0) <= 1.0, "2 the solid is 14 cm longer within 1 mm: +%.3f mm" % d_mm)
	ok(float(r2["volume"]) > vol0, "2 the volume grows: %.2f -> %.2f cm3" % [vol0 * 1e6, float(r2["volume"]) * 1e6])
	ok(m.undo.size() == u0 + 1, "2 ONE undo step per release (%d -> %d)" % [u0, m.undo.size()])
	ok(pu.part_mesh.mesh != null and absf(pu.part_mesh.mesh.get_aabb().size.x - r2["aabb"].size.x) < 1e-5, "2 the model on screen is the rebuilt one")
	ok(float(dr["flushes"]) <= float(dr["ms"]) / 100.0 + 2.0, "2 throttle: %d rebuilds in %d ms of dragging (at most one per 100 ms + 2)" % [dr["flushes"], dr["ms"]])
	ok(float(dr["worst"]) < 100.0, "2 slider drag: worst frame %.1f ms < 100 ms" % dr["worst"])
	await shot("sword_90")
	await click_ctl(ep.undo_btn)
	ok(is_equal_approx(pnum("blade_length"), 760.0), "2 Undo: the blade is 76 cm again (%s mm)" % pnum("blade_length"))
	await idle(3)
	var sl_now: HSlider = ep.rows[0]["slider"]
	ok(is_equal_approx(sl_now.value, 76.0), "2 Undo: the slider follows (%s)" % sl_now.value)
	await click_ctl(ep.redo_btn)
	ok(is_equal_approx(pnum("blade_length"), 900.0), "2 Redo: 90 cm again (%s mm)" % pnum("blade_length"))

	# 7 DOTS: the sword's tip dot, dragged towards the hilt
	ep.frame()
	await idle(3)
	var dot := ep.dot_screen("blade_length")
	var u1: int = m.undo.size()
	await ev_move(dot, false)
	await ev_mouse(dot, true)
	var axis_px: Vector2 = m.cam.unproject_position(Vector3(1.0, 0, 0)) - m.cam.unproject_position(Vector3(0.9, 0, 0))
	var step := axis_px.normalized() * -6.0
	var pp := dot
	for i in 10:
		pp += step
		await ev_move(pp)
	await shot("dot_mid_drag")
	await ev_mouse(pp, false)
	await idle(3)
	var bl_after := pnum("blade_length")
	ok(bl_after < 900.0 and m.undo.size() == u1 + 1, "7 an amber dot dragged: blade length %.0f mm (< 900), ONE undo step (%d -> %d)" % [bl_after, u1, m.undo.size()])
	await click_ctl(ep.undo_btn)
	ok(is_equal_approx(pnum("blade_length"), 900.0), "7 Undo: back to 900 mm")

	# 3 EXPERT
	var feats_easy := JSON.stringify(m.S.part["features"])
	var easy_t := String(m.S.part["easy"]["t"])
	var n_feats: int = m.S.part["features"].size()
	await click_ctl(ep.use_btn)
	await idle(4)
	ok(not pu.easy and pu.on and pu.browser.visible and pu.tl.visible and not ep.panel.visible, "3 Exact sizes? Use Expert: Expert's browser and timeline show, Easy's screen is away")
	ok(JSON.stringify(m.S.part["features"]) == feats_easy and m.S.part["easy"]["t"] == easy_t, "3 the same record: the same %d features, JSON equal" % n_feats)
	ok(pu.tl_btns.size() >= n_feats, "3 the timeline shows the steps (%d buttons for %d features)" % [pu.tl_btns.size(), n_feats])
	await shot("expert_same_part")
	m._toast("Undid: Change Blade length")
	await idle(4)
	var tr: Rect2 = m.ui_toast.get_global_rect()
	ok(m.ui_toast.visible and not tr.intersects(pu.tl.get_global_rect()) and not tr.intersects(pu.browser.get_global_rect()) and not tr.intersects(pu.side.get_global_rect() if pu.side.visible else Rect2()),
		"9 Expert: the Undid toast %s clears the timeline %s, the browser and the side panel" % [tr, pu.tl.get_global_rect()])
	await shot("expert_toast")
	await click_ctl(pu.easy_open_btn)
	await idle(3)
	ok(pu.easy and ep.panel.visible and JSON.stringify(m.S.part["features"]) == feats_easy, "3 Easy again: the same record")
	await click_ctl(ep.expert_btn)
	await idle(3)
	ok(not pu.easy and pu.browser.visible, "3 the Expert button in the bar does the same")
	await click_ctl(pu.easy_open_btn)
	await idle(3)

	# 4 WORDS + 5 LAYOUT
	await click_ctl(ep.make_btns["draw"])
	var all := []
	for n in [ep.bar, ep.make_box, ep.panel, ep.hint, ep.shape_box, ep.status]:
		texts(n, all)
	var bad_words := ["ctrl", "control", "shift", "alt", "esc", "escape", "enter", "return", "tab", "delete", "backspace", "space", "spacebar", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "key", "keys", "keyboard", "hotkey"]
	var hit := []
	var seen := 0
	for t in all:
		if String(t).strip_edges() != "":
			seen += 1
		for tok in String(t).to_lower().split(" ", false):
			var w := String(tok).strip_edges().trim_suffix(".").trim_suffix(",").trim_suffix(":").trim_suffix("?")
			if w in bad_words or w.contains("+"):
				hit.append("%s in '%s'" % [w, t])
	ok(hit.is_empty() and seen > 20, "4 no key names in %d Easy texts %s" % [seen, hit])
	var lay := overlaps([ep.make_box, ep.panel, ep.hint, ep.shape_box, ep.status])
	ok(lay.is_empty(), "5 layout at 1280x720, Draw shape armed: no overlap, all inside the clear view %s (clear %s)" % [lay, m.nav_clear_rect()])
	await shot("layout_draw_armed")
	await click_ctl(ep.make_btns["draw"])
	lay = overlaps([ep.make_box, ep.panel, ep.hint, ep.shape_box, ep.status])
	ok(lay.is_empty(), "5 layout again, nothing armed %s" % [lay])

	# 6 BUTTONS: a crate, then a drawn box
	await click_ctl(ep.chips["crate"])
	var vol_c: float = solid(m.S.part)["volume"]
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["round"])
	await idle(3)
	var rr := solid(m.S.part)
	var fil: Array = m.S.part["features"].filter(func(f): return f["t"] == "fillet")
	ok(m.undo.size() == ub + 1 and fil.size() == 1 and float(rr["volume"]) < vol_c and rr["errors"].is_empty() and int(rr["bodies"]) == 1, "6 Round the edges: a fillet of %d edges, volume %.1f -> %.1f cm3, ONE undo step (%d -> %d) [%s]" % [fil[0]["edges"].size() if not fil.is_empty() else 0, vol_c * 1e6, float(rr["volume"]) * 1e6, ub, m.undo.size(), ep.hint_l.text])
	await shot("button_round")
	ub = m.undo.size()
	var vol_r := float(rr["volume"])
	await click_ctl(ep.make_btns["hole"])
	await idle(3)
	var rh := solid(m.S.part)
	ok(m.undo.size() == ub + 1 and float(rh["volume"]) < vol_r and rh["errors"].is_empty(), "6 Cut a hole: volume %.1f -> %.1f cm3, ONE undo step" % [vol_r * 1e6, float(rh["volume"]) * 1e6])
	await shot("button_hole")
	ub = m.undo.size()
	var vol_h := float(rh["volume"])
	await click_ctl(ep.make_btns["mirror"])
	await idle(3)
	var rm := solid(m.S.part)
	ok(m.undo.size() == ub + 1 and float(rm["volume"]) > vol_h * 1.5 and rm["errors"].is_empty(), "6 Mirror that: volume %.1f -> %.1f cm3, ONE undo step" % [vol_h * 1e6, float(rm["volume"]) * 1e6])
	ub = m.undo.size()
	var rec_s := JSON.stringify(m.S.part)
	await click_ctl(ep.make_btns["pull"])
	await idle(2)
	ok(m.undo.size() == ub and JSON.stringify(m.S.part) == rec_s and ep.hint_l.text.contains("Draw a shape first"), "6 Pull it up with no new shape: says why, no undo step, nothing changed (%s)" % ep.hint_l.text)
	# draw a box on the grid, then pull it up
	await click_ctl(ep.make_btns["draw"])
	ub = m.undo.size()
	var cam: Camera3D = m.cam
	var s0 := cam.unproject_position(Vector3(1.4, 0.0, 0.0))
	var s1 := cam.unproject_position(Vector3(1.5, 0.1, 0.0))
	await ev_move(s0, false)
	await ev_mouse(s0, true)
	await ev_move((s0 + s1) * 0.5)
	await ev_move(s1)
	await shot("button_draw_drag")
	await ev_mouse(s1, false)
	await idle(3)
	var sks: Array = m.S.part["features"].filter(func(f): return f["t"] == "sketch")
	ok(m.undo.size() == ub + 1 and sks.size() >= 4 and sks[-1]["ents"][0]["k"] == "rect", "6 Draw shape: a box sketch from the drag on the grid, ONE undo step (%d -> %d)" % [ub, m.undo.size()])
	var vol_d := float(solid(m.S.part)["volume"])
	ub = m.undo.size()
	await click_ctl(ep.make_btns["pull"])
	await idle(3)
	var rp := solid(m.S.part)
	ok(m.undo.size() == ub + 1 and float(rp["volume"]) > vol_d and rp["errors"].is_empty() and not ep.tweak.is_empty(), "6 Pull it up: the drawn box becomes a solid (%.1f -> %.1f cm3), ONE undo step, a How far slider (%s)" % [vol_d * 1e6, float(rp["volume"]) * 1e6, ep.hint_l.text])
	var tw: Dictionary = ep.rows[-1]
	var vol_p := float(rp["volume"])
	ub = m.undo.size()
	await drag_slider(tw["slider"], 8.0)
	await idle(2)
	ok(m.undo.size() == ub + 1 and float(solid(m.S.part)["volume"]) > vol_p, "6 the How far slider moves the pulled part: ONE undo step, volume grows")
	await shot("button_pull")
	await click_ctl(ep.make_btns["draw"])
	var b0 := cam.unproject_position(Vector3(0.0, 0.05, 0.0))
	var b1 := cam.unproject_position(Vector3(0.08, 0.1, 0.0))
	ub = m.undo.size()
	await ev_move(b0, false)
	await ev_mouse(b0, true)
	await ev_move(b1)
	await ev_mouse(b1, false)
	await idle(3)
	var vol_s := float(solid(m.S.part)["volume"])
	await click_ctl(ep.make_btns["spin"])
	await idle(3)
	var rs := solid(m.S.part)
	var last_t := String(m.S.part["features"][-1]["t"])
	ok(m.undo.size() == ub + 2 and last_t == "revolve" and rs["errors"].is_empty(), "6 Draw shape + Spin it round: a revolve, two steps in all (%d -> %d), last %s, failed %s, volume %.1f -> %.1f" % [ub, m.undo.size(), last_t, rs["errors"], vol_s * 1e6, float(rs["volume"]) * 1e6])

	# 10 PARTFLOW: the whole length, the hole's size (the crate, its default hole)
	await click_ctl(ep.chips["sword"])
	await idle(3)
	var pf_sw := solid(m.S.part)
	var pf_cm := roundi(float(pf_sw["aabb"].size.x) * 100.0)
	ok(ep.whole_l.visible and pf_cm > 0 and ep.whole_l.text == "Whole sword: %d cm" % pf_cm, "10 whole length: under the sliders, '%s' (the solid is %d cm long)" % [ep.whole_l.text, pf_cm])
	await drag_slider(ep.rows[0]["slider"], 90.0)
	await idle(2)
	var pf_sw2 := solid(m.S.part)
	ok(float(pf_sw2["aabb"].size.x) > float(pf_sw["aabb"].size.x) and ep.whole_l.text == "Whole sword: %d cm" % roundi(float(pf_sw2["aabb"].size.x) * 100.0), "10 whole length follows the blade slider: '%s'" % ep.whole_l.text)
	await click_ctl(ep.chips["crate"])
	await idle(3)
	var pf_v0 := float(solid(m.S.part)["volume"])
	await click_ctl(ep.make_btns["hole"])
	await idle(3)
	var pf_hole := ep.rows[-1]["slider"] as HSlider
	var pf_r := solid(m.S.part)
	ok(String(ep.tweak.get("label", "")) == "Hole size" and pf_hole.value >= 2.0 and pf_hole.value <= 10.0 and pf_hole.value != 0.3, "10 hole: the default Hole size reads %.1f cm across (2 to 10 cm, not 0.3)" % pf_hole.value)
	ok(float(pf_r["volume"]) < pf_v0 and pf_r["errors"].is_empty() and int(pf_r["bodies"]) == 1, "10 hole: the default cuts the crate (volume %.1f -> %.1f cm3, failed steps %d)" % [pf_v0 * 1e6, float(pf_r["volume"]) * 1e6, pf_r["errors"].size()])

	# 8 NO DLL
	var snap := JSON.stringify(m.S.part)
	ub = m.undo.size()
	Part.force_off = true
	pu.sync()
	ep._sig = ""
	await idle(3)
	var grey := true
	for k in ep.make_btns:
		grey = grey and (ep.make_btns[k] as Button).disabled and (ep.make_btns[k] as Button).tooltip_text.contains("KineCAD")
	var sl_grey := true
	for r in ep.rows:
		sl_grey = sl_grey and not (r["slider"] as HSlider).editable
	ok(grey and sl_grey and ep.hint_l.text.contains("KineCAD"), "8 no DLL: the six buttons and the sliders greyed with the reason (hint: %s)" % ep.hint_l.text)
	await click_ctl(ep.make_btns["round"])
	ok(m.undo.size() == ub and JSON.stringify(m.S.part) == snap, "8 no DLL: pressing a greyed button changes nothing")
	await shot("no_dll")
	Part.force_off = false
	await idle(3)
	# 10 USE IN A SCENE: the Easy Part bar, then the Expert part's strip button (BuildUI.use_part: the part is a prop of its own)
	var pf_bld: BuildUI = m.bld
	ok(ep.use_scene_btn.visible and not ep.use_scene_btn.disabled, "10 Use in a scene is on the Easy Part bar, enabled with a solid")
	var pf_ub: int = m.undo.size()
	await click_ctl(ep.use_scene_btn)
	await idle(8)
	var pf_parts := 0
	for p in m.S.props:
		if String(p["kind"]).begins_with("part:"):
			pf_parts += 1
	var pf_node: Node3D = Props.mesh(m.S.props[-1]) if not m.S.props.is_empty() else null
	var pf_has_mesh: bool = pf_node != null and pf_node.find_children("*", "MeshInstance3D", true, false).size() == 1
	ok(m.cur_page == "STAGE" and pf_parts == 1 and m.undo.size() == pf_ub + 1 and pf_has_mesh, "10 Easy Use in a scene: the part is a prop of the set (page %s, part props %d, undo +%d, its own mesh %s)" % [m.cur_page, pf_parts, m.undo.size() - pf_ub, str(pf_has_mesh)])
	await shot("use_in_scene_part")
	m._page_set("BUILD")
	await idle(6)
	ep.to_expert()
	await idle(6)
	ok(pf_bld.part.on and not pf_bld.part.easy and pf_bld.part_ready(), "10 Expert part with a solid: the Expert strip's Use in a scene is live")
	pf_ub = m.undo.size()
	await click_ctl(pf_bld.use_btn)
	await idle(8)
	pf_parts = 0
	for p in m.S.props:
		if String(p["kind"]).begins_with("part:"):
			pf_parts += 1
	ok(m.cur_page == "STAGE" and pf_parts == 2 and m.undo.size() == pf_ub + 1, "10 Expert Use in a scene: a second part prop (page %s, part props %d, undo +%d)" % [m.cur_page, pf_parts, m.undo.size() - pf_ub])
	# 11 PART PROP FILE: the Part props in the set are saved with their record; reopened, each one is there with the same vertex count
	var pv_before := _part_props()
	var pv_n := pv_before.map(func(p): return _verts(p))
	var pv_path := DIRT + "/part_props.json"
	var pv_f := FileAccess.open(pv_path, FileAccess.WRITE)
	pv_f.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	pv_f.close()
	m._new_scene()
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(2)
	m._load_scene(pv_path)
	await idle(6)
	var pv_after := _part_props()
	var pv_m := pv_after.map(func(p): return _verts(p))
	ok(pv_before.size() >= 1 and pv_after.size() == pv_before.size() and pv_m == pv_n, "11 Part props saved and reopened: %d prop(s), vertices %s (before %s)" % [pv_after.size(), str(pv_m), str(pv_n)])
	print("easypart: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## the Part props of the open scene
func _part_props() -> Array:
	return m.S.props.filter(func(p): return String(p["kind"]).begins_with("part:"))


## the vertex count of a prop's meshes (what it draws)
func _verts(p: Dictionary) -> int:
	var n := Props.mesh(p)
	var c := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var msh: ArrayMesh = (mi as MeshInstance3D).mesh
		for s in msh.get_surface_count():
			c += (msh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	n.free()
	return c
