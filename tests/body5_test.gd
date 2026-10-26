## godot --path . -s tests/body5_test.gd     (ROADMAP_400 G13: body from 5 numbers; needs a window)
## Sources: Winter 2009 Fig. 4.1 segment fractions of stature; ANSUR II (Gordon et al. 2014) stature mean/sd; scripts/body_from_numbers.gd.
## BARS, written before measuring:
##  1 175 cm, 80 kg, man, 30 y, average: the predicted AND the measured (on the built skeleton) upper arm, forearm, thigh,
##    shank and foot are each within 5 % of Winter's fraction x 175 cm
##  2 160 cm vs 190 cm (same sex/build): every long bone (upper arm, forearm, thigh, shank, foot), predicted and measured,
##    is longer on the 190 body
##  3 the applied body's stature (head top to heel, T pose) is within 2 cm of the request for 160 / 175 / 190
##  4 body_from_numbers through main = exactly ONE undo step; Ctrl+Z gives back the scene JSON and the body state exactly
##  5 PLACEMENT (whole-body view): 160 cm woman and 190 cm heavy man, feet on the floor (soles within 1 cm of y = 0), head
##    and feet inside the view, the 190 drawn taller on screen. Screenshot: both side by side, one camera.
##  6 percentile readout: 175.6 cm man = 50th (+-1), 162.8 cm woman = 50th (+-1), 190 cm man ~ 98th (z = 2.09)
extends SceneTree

var m: Node
var fails := 0
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/body5.png"
const LONG := ["upper_arm", "forearm", "thigh", "shank", "foot"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func fresh(d: Dictionary) -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.set_proportions(d)
	return b


func screen_box() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in Body.ORDER:
		var q: Vector2 = m.cam.unproject_position(m.B.P[j])
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


func _init() -> void:
	# ---- 1
	var p175 := BodyFromNumbers.predict(175.0, 80.0, "male", 30.0, "average")
	var b175 := fresh(BodyFromNumbers.body_for(175.0, 80.0, "male", 30.0, "average"))
	var ms175 := Proportions.lengths(b175)
	for s in LONG:
		var want: float = float(BodyFromNumbers.WINTER[s]) * 1.75
		var e1: float = (float(p175["lengths"][s]) - want) / want * 100.0
		var e2: float = (float(ms175[s]) - want) / want * 100.0
		ok(absf(e1) < 5.0 and absf(e2) < 5.0, "1 %s: Winter %.1f cm, predicted %.1f cm (%+.1f %%), measured on the skeleton %.1f cm (%+.1f %%)" % [s, want * 100.0, float(p175["lengths"][s]) * 100.0, e1, float(ms175[s]) * 100.0, e2])
	print("     hand measured %.1f cm (Winter %.1f), trunk %.1f cm, head %.1f cm (reported)" % [float(ms175["hand"]) * 100.0, 0.108 * 175.0, float(ms175["trunk"]) * 100.0, float(ms175["head"]) * 100.0])
	# ---- 2 / 3
	var meas := {}
	for h in [160, 175, 190]:
		var b := fresh(BodyFromNumbers.body_for(float(h), 75.0, "male", 30.0, "average"))
		meas[h] = Proportions.lengths(b)
		var st := float(BodyModel.measures(b)["stature"])
		ok(absf(st - h / 100.0) <= 0.02, "3 request %d cm: the built body stands %.2f cm (%+.2f cm)" % [h, st * 100.0, st * 100.0 - h])
	var pl := BodyFromNumbers.predict(160.0, 75.0, "male", 30.0, "average")
	var ph := BodyFromNumbers.predict(190.0, 75.0, "male", 30.0, "average")
	for s in LONG:
		ok(float(ph["lengths"][s]) > float(pl["lengths"][s]) and float(meas[190][s]) > float(meas[175][s]) and float(meas[175][s]) > float(meas[160][s]),
			"2 %s grows 160 -> 175 -> 190: measured %.1f / %.1f / %.1f cm" % [s, float(meas[160][s]) * 100.0, float(meas[175][s]) * 100.0, float(meas[190][s]) * 100.0])
	# ---- 6 readout
	var pm := BodyFromNumbers.predict(175.6, 80.0, "male", 30.0, "average")
	var pw := BodyFromNumbers.predict(162.8, 62.0, "female", 30.0, "average")
	var pt := BodyFromNumbers.predict(190.0, 95.0, "male", 30.0, "heavy")
	ok(absf(float(pm["height_pct"]) - 50.0) <= 1.0 and absf(float(pw["height_pct"]) - 50.0) <= 1.0 and absf(float(pt["height_pct"]) - 98.1) <= 1.0,
		"6 percentiles: 175.6 cm man %.1f, 162.8 cm woman %.1f, 190 cm man %.1f" % [pm["height_pct"], pw["height_pct"], pt["height_pct"]])
	print("     ", BodyFromNumbers.readout(pt))
	# ---- the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._page_set("BODY", false)
	await idle(4)
	var scene0 := JSON.stringify(m.S.to_dict(m.B))
	var state0 := JSON.stringify(m.B.state())
	var u0: int = m.undo.size()
	m.body_from_numbers([160.0, 55.0, "female", 30.0, "average"])
	await idle(3)
	ok(m.undo.size() == u0 + 1 and absf(float(BodyModel.measures(m.B)["stature"]) - 1.60) <= 0.02 and m.S.body.get("sex", "") == "female",
		"4 one undo step (%d -> %d), the live body stands %.1f cm, scene body is a woman" % [u0, m.undo.size(), float(BodyModel.measures(m.B)["stature"]) * 100.0])
	m._undo()
	await idle(3)
	ok(JSON.stringify(m.S.to_dict(m.B)) == scene0 and JSON.stringify(m.B.state()) == state0 and m.undo.size() == u0, "4 Ctrl+Z: scene JSON and body state identical")
	# ---- 5 placement
	if m.dummy_on:
		m._dummy_toggle()
	m.sel = "pelvis"
	m._do(func(): m._arms_relaxed())
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var view_r := Rect2(m.lw(), 60.0, vs.x - m.lw() - m.rw(), vs.y - m.bottom_h - 60.0)
	var pic := {}
	var boxes := {}
	var cases := {"w160": [160.0, 55.0, "female", 30.0, "average"], "m190": [190.0, 110.0, "male", 30.0, "heavy"]}
	for k in cases:
		m.body_from_numbers(cases[k])
		await idle(3)
		m._view(1)
		await idle(6)
		if m.ui_toast != null:
			m.ui_toast.visible = false
		await idle(2)
		await RenderingServer.frame_post_draw
		pic[k] = m.get_viewport().get_texture().get_image()
		var bb := screen_box()
		boxes[k] = bb
		var top: Vector2 = m.cam.unproject_position(Proportions.head_top(m.B))
		var heel_y: float = Proportions.heel(m.B, "_l").y
		var lo: float = m.B.sole_low()
		ok(absf(lo) <= 0.01 and absf(heel_y) <= 0.05 and view_r.has_point(top) and view_r.has_point(bb.end),
			"5 %s: soles %.1f mm off the floor, left heel y %.1f mm, head top (%.0f,%.0f) and box %s inside the view %s" % [k, lo * 1000.0, heel_y * 1000.0, top.x, top.y, bb, view_r])
	ok((boxes["m190"] as Rect2).size.y > (boxes["w160"] as Rect2).size.y * 1.12,
		"5 the 190 cm man is taller on screen: %.0f px vs %.0f px (ratio %.2f, 190/160 = 1.19)" % [(boxes["m190"] as Rect2).size.y, (boxes["w160"] as Rect2).size.y, (boxes["m190"] as Rect2).size.y / (boxes["w160"] as Rect2).size.y])
	var sc: float = float((pic["m190"] as Image).get_width()) / vs.x
	var half := int(215.0 * sc)
	var gap := int(230.0 * sc)
	var y0 := int(60.0 * sc)
	var hh := int((vs.y - m.bottom_h - 60.0) * sc)
	var out: Image = Image.create(4 * half, hh, false, (pic["m190"] as Image).get_format())
	out.fill(Color(0.08, 0.09, 0.11))
	for pair in [["w160", 0], ["m190", 2 * half]]:
		var cxq := int(((boxes[pair[0]] as Rect2).get_center().x) * sc)
		out.blit_rect(pic[pair[0]], Rect2i(cxq - half, y0, 2 * half, hh), Vector2i(pair[1], 0))
	out.save_png(OUT)
	print("     screenshot: %s: 160 cm woman (left) and 190 cm heavy man (right), one camera" % OUT)
	print("BODY5 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
