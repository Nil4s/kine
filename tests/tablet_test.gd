## godot --path . -s tests/tablet_test.gd     (ROADMAP_400 P09: tablet pressure / tilt / eraser end on every brush page; needs a window)
## Synthetic InputEventMouseMotion (pressure, tilt, pen_inverted) pushed through the real viewport onto each page. A stroke is:
## a hover motion carrying the pen state, the press, 4 held motions carrying it, the release. Bars, written BEFORE the code:
##   SCULPT (test sphere), VERTEX PAINT (cube, ADD), WEIGHT PAINT (cube, ADD), TEXTURE PAINT (cube):
##   (S) pen_target "strength": the summed effect of a stroke at pressure 0.25 over the same stroke at 1.0 = 0.25 +- 0.02
##       (sculpt: signed radial displacement; vpaint: summed red change; wpaint: summed bone weight change; texture: summed byte change)
##   (R) pen_target "radius": the brush radius the stroke ends with / the UI radius = 0.25 +- 0.02, and the effect at 0.25 stays
##       below the effect at 1.0 (sculpt, vpaint, wpaint: the radius is read from the stroke's params; texture: changed texels < 0.5x)
##   (I) pen_inverted: the stroke does the OPPOSITE: sculpt digs (signed displacement < 0, ratio to the normal stroke -1 +- 0.05),
##       vpaint ADD -> subtract (-1 +- 0.05), wpaint ADD -> subtract (the weight sum falls by 1 +- 0.1 of what the add raised it)
##   (T) sculpt tilt (pen_tilt on): a tilt of (0.5, 0.5) rotates the stamp: the stroke's alpha_angle = 45 deg +- 1 over the UI's; pen_tilt
##       off or a mouse (tilt 0): alpha_angle stays the UI's own
##   (M) a MOUSE stroke (pressure 0, no pen) is BYTE-IDENTICAL to the baseline hash recorded in BASE from the code BEFORE this change,
##       with pen_target left at "strength" and also at "radius"; and a pen at pressure 1.0 gives the same bytes as the mouse
##   (P) planted: the checker rejects a ratio of 0.5 where 0.25 is wanted, and a baseline hash that is off by one character
## Pages NOT wired (no pen state read): curve draw (kmesh_curves_ui.gd) drags control points, it is not a brush.
## Run with the user arg "record" (or an empty BASE) to print the RECORD lines for BASE instead of comparing.
extends SceneTree

var fails := 0
var m: Node
var recording := false
# hashes of a mouse stroke on the UNCHANGED code (filled by the record run before the implementation)
var BASE := {"sculpt": "1262233245", "vpaint": "3944612707", "vpaint_r": "3944612707", "tex": "330585316", "tex_r": "330585316", "wpaint": "1136876736", "wpaint_r": "1136876736"}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func btn(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func pen(p: Vector2, pr: float, inv: bool, tilt: Vector2, held: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.pressure = pr
	e.pen_inverted = inv
	e.tilt = tilt
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


## pr 0 = a mouse (no pen)
func stroke(a: Vector2, b: Vector2, pr := 0.0, inv := false, tilt := Vector2.ZERO) -> void:
	await pen(a, pr, inv, tilt, false)
	await btn(a, true)
	for k in 4:
		await pen(a.lerp(b, (k + 1) / 4.0), pr, inv, tilt, true)
	await btn(b, false)
	await idle(2)


## ONE dab: the hover that carries the pen state, a press, the release (no motion, so no second dab)
func dab1(a: Vector2, pr := 0.0, inv := false) -> void:
	await pen(a, pr, inv, Vector2.ZERO, false)
	await btn(a, true)
	await btn(a, false)
	await idle(2)


func hsh(x) -> String:
	return str(var_to_bytes(x).hex_encode().hash())


func base_ok(key: String, h: String) -> bool:
	if recording:
		print("RECORD %s %s" % [key, h])
		return true
	return BASE.has(key) and BASE[key] == h


func fresh() -> void:
	if m != null:
		root.remove_child(m)
		m.free()
		await idle(3)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false


# ---------------------------------------------------------------- sculpt

func sculpt_part() -> void:
	await fresh()
	m._sculpt_start()
	await idle(3)
	var ui: KMeshSculptUI = m.ksc
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cs: Vector2 = m.cam.unproject_position(wc)
	var a := cs + Vector2(-30, 0)
	var b := cs + Vector2(30, 0)
	var v0 := ui.mesh.verts.duplicate()
	var res := {}
	var cases := {"mouse": [0.0, false], "p1": [1.0, false], "p025": [0.25, false], "inv": [1.0, true]}
	for target in ["strength", "radius"]:
		ui.set("pen_target", target)
		for k in cases:
			ui.mesh.verts = v0.duplicate()
			ui.set("_seed", 0)
			ui.view.rebuild()
			await idle(2)
			await stroke(a, b, cases[k][0], cases[k][1])
			var s := 0.0
			var n := 0
			for i in v0.size():
				var d := ui.mesh.verts[i] - v0[i]
				s += d.dot(v0[i].normalized())
				if d.length() > 1e-9:
					n += 1
			res[target + k] = {"s": s, "n": n, "r": float(ui.sculpt.p["radius"]), "h": hsh(ui.mesh.verts)}
	var s1: float = res["strengthp1"]["s"]
	var r_s: float = res["strengthp025"]["s"] / s1 if s1 != 0.0 else -9.0
	ok(s1 > 0.0 and near(r_s, 0.25, 0.02), "(S) sculpt strength mode: effect(0.25)/effect(1.0) = %.4f (bar 0.25 +- 0.02), effect(1.0) = %.6f" % [r_s, s1])
	var rr: float = res["radiusp025"]["r"] / ui.radius
	ok(near(rr, 0.25, 0.02) and near(float(res["radiusp1"]["r"]) / ui.radius, 1.0, 0.02) and res["radiusp025"]["n"] < res["radiusp1"]["n"],
		"(R) sculpt radius mode: radius ratio %.4f (bar 0.25 +- 0.02), at 1.0 %.4f; verts moved %d < %d" % [rr, float(res["radiusp1"]["r"]) / ui.radius, res["radiusp025"]["n"], res["radiusp1"]["n"]])
	var ri: float = res["strengthinv"]["s"] / s1 if s1 != 0.0 else 9.0
	ok(res["strengthinv"]["s"] < 0.0 and near(ri, -1.0, 0.05), "(I) sculpt pen_inverted digs: signed displacement %.6f vs raised %.6f, ratio %.4f (bar -1 +- 0.05)" % [res["strengthinv"]["s"], s1, ri])
	# (M) the sculpt strokes above drift with the stroke order (cached state), so the byte bar uses a FRESH app per stroke
	var hm := await sculpt_hash("strength", 0.0)
	var hr := await sculpt_hash("radius", 0.0)
	var hp := await sculpt_hash("strength", 1.0)
	ok(base_ok("sculpt", hm) and hr == hm and hp == hm,
		"(M) sculpt (fresh app per stroke): a mouse stroke is byte-identical to the baseline; with pen_target radius: %s; a pen at 1.0: %s" % [hr == hm, hp == hm])
	ok(recording or BASE.get("sculpt", "") != hm + "0", "(P) planted: a baseline hash off by a character does not match")
	await fresh()
	m._sculpt_start()
	await idle(3)
	ui = m.ksc
	m._turn_to(0.0, 0.0, 1.6, ui.view.global_position, false)
	await idle(6)
	# tilt
	ui.set("pen_target", "strength")
	var base_ang := deg_to_rad(ui.alpha_angle)
	ui.set("pen_tilt", true)
	ui.mesh.verts = v0.duplicate()
	await stroke(a, b, 1.0, false, Vector2(0.5, 0.5))
	var ang_on := float(ui.sculpt.p["alpha_angle"])
	ui.mesh.verts = v0.duplicate()
	await stroke(a, b, 0.0, false, Vector2.ZERO)
	var ang_mouse := float(ui.sculpt.p["alpha_angle"])
	ui.set("pen_tilt", false)
	ui.mesh.verts = v0.duplicate()
	await stroke(a, b, 1.0, false, Vector2(0.5, 0.5))
	var ang_off := float(ui.sculpt.p["alpha_angle"])
	ok(near(rad_to_deg(ang_on - base_ang), 45.0, 1.0) and near(ang_mouse, base_ang, 1e-6) and near(ang_off, base_ang, 1e-6),
		"(T) sculpt tilt: tilt on -> %.2f deg over the UI angle (bar 45 +- 1); mouse -> unchanged %s; tilt off -> unchanged %s" % [rad_to_deg(ang_on - base_ang), near(ang_mouse, base_ang, 1e-6), near(ang_off, base_ang, 1e-6)])
	plant(res)


func sculpt_hash(target: String, pr: float) -> String:
	await fresh()
	m._sculpt_start()
	await idle(3)
	var ui: KMeshSculptUI = m.ksc
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cs: Vector2 = m.cam.unproject_position(wc)
	ui.set("pen_target", target)
	await stroke(cs + Vector2(-30, 0), cs + Vector2(30, 0), pr)
	return hsh(ui.mesh.verts)


func plant(res: Dictionary) -> void:
	var bad: float = res["strengthp025"]["s"] / res["strengthp1"]["s"] * 2.0
	ok(not near(bad, 0.25, 0.02), "(P) planted: a ratio of %.3f is rejected where 0.25 is wanted" % bad)


# ---------------------------------------------------------------- vertex paint

func cube_view() -> void:
	var ed = m.kmed
	var wc: Vector3 = ed.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)


func face_pts() -> Array:
	var ed = m.kmed
	var cam: Camera3D = m.cam
	return [cam.unproject_position(ed.view.global_transform * Vector3(-0.15, 0.0, 0.3)), cam.unproject_position(ed.view.global_transform * Vector3(0.15, 0.0, 0.3))]


func vpaint_part() -> void:
	await fresh()
	m._kmesh_edit_start()
	await idle(3)
	var pu := KMeshVPaintUI.of(m)
	pu.start()
	await idle(3)
	cube_view()
	await idle(4)
	var mesh: KMesh = pu.mesh
	var d0: PackedColorArray = mesh.attr_data(KMeshVPaint.CH).duplicate()
	d0.fill(Color(0.5, 0.5, 0.5, 1.0))
	pu.mode = KMeshVPaint.ADD
	pu.color = Color(0.2, 0.0, 0.0, 1.0)
	pu.strength = 0.5
	pu.radius = 0.45
	pu.softness = 1.0
	var pts := face_pts()
	var res := {}
	var cases := {"mouse": [0.0, false], "p1": [1.0, false], "p025": [0.25, false], "inv": [1.0, true]}
	for target in ["strength", "radius"]:
		pu.set("pen_target", target)
		for k in cases:
			mesh.set_attr_data(KMeshVPaint.CH, d0.duplicate())
			pu.view.mark_dirty()
			await stroke(pts[0], pts[1], cases[k][0], cases[k][1])
			var d: PackedColorArray = mesh.attr_data(KMeshVPaint.CH)
			var s := 0.0
			var n := 0
			for i in d.size():
				s += d[i].r - d0[i].r
				if d[i] != d0[i]:
					n += 1
			res[target + k] = {"s": s, "n": n, "r": float(pu.vp.p["radius"]), "h": hsh(d)}
	var s1: float = res["strengthp1"]["s"]
	var r_s: float = res["strengthp025"]["s"] / s1 if s1 != 0.0 else -9.0
	ok(s1 > 0.0 and near(r_s, 0.25, 0.02), "(S) vpaint strength mode: paint(0.25)/paint(1.0) = %.4f (bar 0.25 +- 0.02), paint(1.0) = %.5f" % [r_s, s1])
	var rr: float = res["radiusp025"]["r"] / pu.radius
	ok(near(rr, 0.25, 0.02) and res["radiusp025"]["s"] < res["radiusp1"]["s"], "(R) vpaint radius mode: radius ratio %.4f (bar 0.25 +- 0.02); paint %.5f < %.5f" % [rr, res["radiusp025"]["s"], res["radiusp1"]["s"]])
	var ri: float = res["strengthinv"]["s"] / s1 if s1 != 0.0 else 9.0
	ok(res["strengthinv"]["s"] < 0.0 and near(ri, -1.0, 0.05), "(I) vpaint pen_inverted subtracts: ratio %.4f (bar -1 +- 0.05)" % ri)
	ok(base_ok("vpaint", res["strengthmouse"]["h"]) and base_ok("vpaint_r", res["radiusmouse"]["h"]) and res["strengthp1"]["h"] == res["strengthmouse"]["h"],
		"(M) vpaint: a mouse stroke is byte-identical to the baseline (both targets); a pen at 1.0 = the mouse: %s" % (res["strengthp1"]["h"] == res["strengthmouse"]["h"]))
	# texture paint
	pu.set_tex_mode(true)
	await idle(3)
	pu.color = Color(1, 0, 0, 1)
	pu.strength = 0.6
	pu.radius = 0.2
	var t0: PackedByteArray = pu.tp.data().duplicate()
	var tres := {}
	for target in ["strength", "radius"]:
		pu.set("pen_target", target)
		for k in cases:
			pu.tp.set_data(t0.duplicate())
			await stroke(pts[0], pts[1], cases[k][0], cases[k][1])
			var td: PackedByteArray = pu.tp.data()
			var s := 0
			var n := 0
			for i in td.size():
				var dd := absi(int(td[i]) - int(t0[i]))
				s += dd
				if dd != 0:
					n += 1
			tres[target + k] = {"s": float(s), "n": n, "h": hsh(td)}
	# (S)/(I) on ONE dab at a low strength: a stroke stacks dabs (1-(1-w)^n), which is not linear in the pressure
	pu.set("pen_target", "strength")
	pu.strength = 0.3
	var dres := {}
	var sat := false
	for k in ["p1", "p025", "inv"]:
		pu.tp.set_data(t0.duplicate())
		await dab1(pts[0].lerp(pts[1], 0.5), cases[k][0], cases[k][1])
		var td1: PackedByteArray = pu.tp.data()
		var s := 0.0
		var g := 0.0
		for i in td1.size():
			s += absf(float(td1[i]) - float(t0[i]))
			if i % 4 == 1:
				g += float(td1[i]) - float(t0[i])
			if td1[i] == 255 and t0[i] != 255 and i % 4 != 3:
				sat = true
		dres[k] = {"s": s, "g": g}
	var ts1: float = dres["p1"]["s"]
	var tr: float = dres["p025"]["s"] / ts1 if ts1 != 0.0 else -9.0
	ok(ts1 > 0.0 and near(tr, 0.25, 0.02), "(S) texture strength mode, one dab at 0.3: texel change(0.25)/(1.0) = %.4f (bar 0.25 +- 0.02), a texel saturated %s" % [tr, sat])
	ok(dres["inv"]["g"] > dres["p1"]["g"] + 1.0, "(I) texture pen_inverted erases toward white: green change %.0f vs %.0f for the normal red dab" % [dres["inv"]["g"], dres["p1"]["g"]])
	ok(tres["radiusp025"]["n"] < 0.5 * tres["radiusp1"]["n"], "(R) texture radius mode: changed texels %d at 0.25 < half of %d at 1.0" % [tres["radiusp025"]["n"], tres["radiusp1"]["n"]])
	ok(base_ok("tex", tres["strengthmouse"]["h"]) and base_ok("tex_r", tres["radiusmouse"]["h"]) and tres["strengthp1"]["h"] == tres["strengthmouse"]["h"],
		"(M) texture: a mouse stroke is byte-identical to the baseline (both targets); a pen at 1.0 = the mouse")


# ---------------------------------------------------------------- weight paint

func wsum(mesh: KMesh, bone: int) -> float:
	var s := 0.0
	for v in mesh.verts.size():
		s += KMeshWPaint.weight_of(mesh, v, bone)
	return s


func wpaint_part() -> void:
	await fresh()
	m.wp_key = "tablet_test"
	m._kmesh_edit_start()
	await idle(2)
	var ed = m.kmed
	KMeshAutoWeights.preview_bind(m)
	cube_view()
	await idle(4)
	var line = null
	for t in MeshTools.TOOLS:
		if t["do"] == "op:wpaint":
			line = t
	if line == null:
		ok(false, "wpaint line missing")
		return
	MeshTools.run(line, m)
	await idle(3)
	var ui := KMeshWPaintUI.of(m)
	ui.set_bone(ui._strongest())
	ui.brush = KMeshWPaint.ADD
	ui.strength = 0.3
	ui.radius = 0.45
	var B := ui.bone
	var mesh: KMesh = ed.mesh
	var cb0: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_BONES).duplicate()
	var cw0: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_WEIGHTS).duplicate()
	var w0 := wsum(mesh, B)
	var pts := face_pts()
	var res := {}
	var cases := {"mouse": [0.0, false], "p1": [1.0, false], "p025": [0.25, false], "inv": [1.0, true]}
	for target in ["strength", "radius"]:
		ui.set("pen_target", target)
		for k in cases:
			mesh.set_attr_data(KMeshWPaint.CH_BONES, cb0.duplicate())
			mesh.set_attr_data(KMeshWPaint.CH_WEIGHTS, cw0.duplicate())
			if k == "inv":   # the eraser end subtracts: start from the weights an add stroke leaves
				await stroke(pts[0], pts[1], 1.0, false)
				res["added"] = wsum(mesh, B)
			var before := wsum(mesh, B)
			await stroke(pts[0], pts[1], cases[k][0], cases[k][1])
			res[target + k] = {"s": wsum(mesh, B) - before, "r": float(ui.wp.p["radius"]), "h": hsh([mesh.attr_data(KMeshWPaint.CH_BONES), mesh.attr_data(KMeshWPaint.CH_WEIGHTS)])}
	# (S)/(I) on ONE dab at a low strength where nothing clamps (a stroke saturates the weights at 1 and renormalises)
	ui.set("pen_target", "strength")
	ui.strength = 0.05
	var one := {}
	var maxw := 0.0
	var pc: Vector2 = pts[0].lerp(pts[1], 0.5)
	for k in ["w0", "p1", "p025", "add", "inv"]:
		mesh.set_attr_data(KMeshWPaint.CH_BONES, cb0.duplicate())
		mesh.set_attr_data(KMeshWPaint.CH_WEIGHTS, cw0.duplicate())
		if k == "inv":
			await dab1(pc, 1.0, false)
			one["add"] = wsum(mesh, B)
		var bef := wsum(mesh, B)
		if k != "w0" and k != "add":
			await dab1(pc, cases[k][0], cases[k][1])
		one[k] = wsum(mesh, B) - bef
		for v in mesh.verts.size():
			maxw = maxf(maxw, KMeshWPaint.weight_of(mesh, v, B))
	var s1: float = one["p1"]
	var r_s: float = one["p025"] / s1 if s1 != 0.0 else -9.0
	ok(s1 > 0.0 and maxw < 0.999 and near(r_s, 0.25, 0.02), "(S) wpaint strength mode, one dab at 0.05: weight added(0.25)/(1.0) = %.4f (bar 0.25 +- 0.02), added(1.0) = %.5f, largest bone weight seen %.3f (no clamp < 0.999)" % [r_s, s1, maxw])
	var rr: float = res["radiusp025"]["r"] / ui.radius
	ok(near(rr, 0.25, 0.02) and res["radiusp025"]["s"] < res["radiusp1"]["s"], "(R) wpaint radius mode: radius ratio %.4f (bar 0.25 +- 0.02); added %.5f < %.5f" % [rr, res["radiusp025"]["s"], res["radiusp1"]["s"]])
	var raised: float = one["p1"]
	var ri: float = one["inv"] / raised if raised != 0.0 else 9.0
	ok(raised > 0.0 and one["inv"] < 0.0 and near(ri, -1.0, 0.1), "(I) wpaint pen_inverted subtracts, one dab: weight change %.5f after an add dab raised it %.5f, ratio %.4f (bar -1 +- 0.1)" % [one["inv"], raised, ri])
	ok(base_ok("wpaint", res["strengthmouse"]["h"]) and base_ok("wpaint_r", res["radiusmouse"]["h"]) and res["strengthp1"]["h"] == res["strengthmouse"]["h"],
		"(M) wpaint: a mouse stroke is byte-identical to the baseline (both targets); a pen at 1.0 = the mouse: %s" % (res["strengthp1"]["h"] == res["strengthmouse"]["h"]))


func _init() -> void:
	recording = OS.get_cmdline_user_args().has("record")
	await sculpt_part()
	await vpaint_part()
	await wpaint_part()
	print("TABLET TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
