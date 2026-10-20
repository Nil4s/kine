## godot --path . -s tests/bodypage_test.gd     (docs/PAGES_PLAN.md step 2: the BODY page; needs a window)
## Sources: ANSUR II (Gordon et al. 2014, NATICK/TR-15/007) via docs/research/PROPORTIONS.md; the sliders: scripts/body_model.gd.
## BARS, written before measuring:
##  1 STATURE: the stature slider at the 5th / 95th percentile (men and women) gives a standing height, measured on the
##    skeleton (top of the head to the heel), within 1 % of the ANSUR II table (men 1648 / 1870 mm, women 1525 / 1740 mm)
##  2 ARM SPAN: fingertip to fingertip / height is 1.00-1.06 (ANSUR II: arm span a little over stature) at the 5th, 50th
##    and 95th, both sexes
##  3 ONE UNDO STEP PER DRAG: drag_started, 12 value changes, drag_ended = exactly 1 undo step; during the drag the history
##    is untouched and the live body changes; Ctrl+Z gives back the scene (JSON bytes) and the body (state) EXACTLY, and
##    Ctrl+Y gives the dragged body again
##  4 NOTHING WRITTEN: data/skeleton.json bytes identical before and after
##  5 PLACEMENT (whole-body view): at the 5th and the 95th the head top and the soles are inside the view (not under the
##    panels or the bars), the soles are on the floor within 5 mm, the 95th is taller on screen than the 5th, and the
##    BODY panel stands left of the body
##  6 the readout says "5th percentile man" / "95th percentile man"; the sliders follow an undo
## Screenshot: the 5th (right) and the 95th (left) side by side, one camera: jobs/9afc22db/tmp/bodypage.png
extends SceneTree

var m: Node
var fails := 0
const TABLE := {"male_5": 1.648, "male_95": 1.870, "male_50": 1.755, "female_5": 1.525, "female_95": 1.740, "female_50": 1.626}
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/bodypage.png"


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


## drag a slider the way a hand does: press, twelve moves, release
func drag(key: String, to: float) -> void:
	var sl: HSlider = m.ui_body.sliders[key]
	var from := sl.value
	sl.drag_started.emit()
	for i in 12:
		sl.value = lerpf(from, to, float(i + 1) / 12.0)
	sl.drag_ended.emit(true)
	await idle()


func screen_box() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in Body.ORDER:
		var q: Vector2 = m.cam.unproject_position(m.B.P[j])
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


func _init() -> void:
	var skel0 := FileAccess.get_file_as_bytes("res://data/skeleton.json")
	# ---- 1 / 2: the model, every sex x percentile
	for sex in [["male", 1.0], ["female", 0.0]]:
		for p in [5, 50, 95]:
			var pr := BodyModel.DEFAULT.duplicate()
			pr["blend"] = sex[1]
			pr["stat"] = float(p)
			var d := BodyModel.body_for(pr)
			var me := BodyModel.measures(fresh(d))
			var want: float = TABLE["%s_%d" % [sex[0], p]]
			var err: float = (float(me["stature"]) - want) / want * 100.0
			ok(absf(err) < 1.0, "1 %s %dth: standing height %.1f mm vs ANSUR II %.0f mm (%+.2f %%)" % [sex[0], p, float(me["stature"]) * 1000.0, want * 1000.0, err])
			var ratio: float = float(me["span"]) / float(me["stature"])
			ok(ratio >= 1.0 and ratio <= 1.06, "2 %s %dth: arm span %.1f cm / height %.1f cm = %.3f (bar 1.00-1.06)" % [sex[0], p, float(me["span"]) * 100.0, float(me["stature"]) * 100.0, ratio])
	# ---- the page, through the real panel
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._page_set("BODY", false)
	await idle(4)
	var P: BodyPanel = m.ui_body
	ok(P.visible and m.cur_page == "BODY" and not m.ui_side_of["left"].visible, "BODY page: the panel is shown where the browser stood (browser hidden)")
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var scene0 := JSON.stringify(m.S.to_dict(m.B))
	var state0 := JSON.stringify(m.B.state())
	var u0: int = m.undo.size()
	# ---- 3: one undo step per drag (the 5th man)
	var u1: int = m.undo.size()
	var sl: HSlider = P.sliders["stat"]
	sl.drag_started.emit()
	var mid_ok := true
	var tall0 := float(BodyModel.measures(m.B)["stature"])
	for i in 12:
		sl.value = lerpf(50.0, 5.0, float(i + 1) / 12.0)
		mid_ok = mid_ok and m.undo.size() == u1
	var tall_mid := float(BodyModel.measures(m.B)["stature"])
	ok(mid_ok and m.S.body.is_empty() and absf(tall_mid - tall0) > 0.05, "3 during the drag: history untouched (%d), the scene's body unchanged, the live body %.3f -> %.3f m" % [m.undo.size(), tall0, tall_mid])
	sl.drag_ended.emit(true)
	await idle()
	ok(m.undo.size() == u1 + 1, "3 drag_ended = exactly ONE undo step (%d -> %d)" % [u1, m.undo.size()])
	var me5 := BodyModel.measures(m.B)
	var err5: float = (float(me5["stature"]) - 1.648) / 1.648 * 100.0
	ok(absf(err5) < 1.0 and absf(float(m.S.body["stature"]) - float(m.B.body["stature"])) < 1e-9, "1 through the slider: 5th man stands %.1f mm (ANSUR 1648, %+.2f %%), scene body == live body" % [float(me5["stature"]) * 1000.0, err5])
	ok(P.head_lab.text == "5th percentile man", "6 the readout: '%s'" % P.head_lab.text)
	# ---- 5 placement, 5th
	await m._view(1)
	await idle(6)
	var views := {}
	var shots := {}
	var boxes := {}
	for tag in ["p5"]:
		views[tag] = true
	var lo5: float = m.B.sole_low()
	var bx := screen_box()
	var top5: Vector2 = m.cam.unproject_position(Proportions.head_top(m.B))
	var view_r := Rect2(m.lw(), 60.0, vs.x - m.lw() - m.rw(), vs.y - m.bottom_h - 60.0)
	ok(view_r.has_point(top5) and view_r.has_point(bx.end) and absf(lo5) < 0.005, "5 5th: head top at (%.0f,%.0f), soles %.1f mm off the floor, body box %s inside the view %s" % [top5.x, top5.y, lo5 * 1000.0, bx, view_r])
	ok(P.get_global_rect().end.x <= bx.position.x, "5 5th: the BODY panel ends at x=%.0f, the body starts at x=%.0f" % [P.get_global_rect().end.x, bx.position.x])
	await RenderingServer.frame_post_draw
	shots["p5"] = m.get_viewport().get_texture().get_image()
	(shots["p5"] as Image).save_png(OUT.replace(".png", "_5th.png"))
	boxes["p5"] = bx
	var h5: float = bx.size.y
	# ---- 4 / 3: undo, redo
	m._undo()
	await idle()
	if JSON.stringify(m.S.to_dict(m.B)) != scene0:
		print("SCENE0 ", scene0, "
NOW    ", JSON.stringify(m.S.to_dict(m.B)))
	if JSON.stringify(m.B.state()) != state0:
		var a: Dictionary = JSON.parse_string(state0)
		var b: Dictionary = JSON.parse_string(JSON.stringify(m.B.state()))
		for k in a:
			if JSON.stringify(a[k]) != JSON.stringify(b.get(k)):
				if a[k] is Dictionary:
					for k2 in a[k]:
						if JSON.stringify(a[k][k2]) != JSON.stringify(b[k].get(k2)):
							print("DIFF ", k, ".", k2, " ", a[k][k2], " -> ", b[k].get(k2))
				else:
					print("DIFF ", k, " ", a[k], " -> ", b.get(k))
	ok(JSON.stringify(m.S.to_dict(m.B)) == scene0 and JSON.stringify(m.B.state()) == state0 and m.undo.size() == u1, "3 Ctrl+Z: scene JSON and body state identical to before the drag (%d bytes)" % scene0.length())
	ok(P.head_lab.text != "5th percentile man", "6 the panel follows the undo: '%s'" % P.head_lab.text)
	m._redo()
	await idle()
	ok(absf(float(BodyModel.measures(m.B)["stature"]) - float(me5["stature"])) < 1e-6, "3 Ctrl+Y: the dragged body again")
	# ---- the 95th
	await drag("stat", 95.0)
	var me95 := BodyModel.measures(m.B)
	var err95: float = (float(me95["stature"]) - 1.870) / 1.870 * 100.0
	ok(absf(err95) < 1.0, "1 through the slider: 95th man stands %.1f mm (ANSUR 1870, %+.2f %%)" % [float(me95["stature"]) * 1000.0, err95])
	await m._view(1)
	await idle(6)
	var lo95: float = m.B.sole_low()
	var bx2 := screen_box()
	var top95: Vector2 = m.cam.unproject_position(Proportions.head_top(m.B))
	ok(view_r.has_point(top95) and view_r.has_point(bx2.end) and absf(lo95) < 0.005, "5 95th: head top at (%.0f,%.0f), soles %.1f mm off the floor, body box %s inside the view" % [top95.x, top95.y, lo95 * 1000.0, bx2])
	ok(bx2.size.y > h5 * 1.08 and P.head_lab.text == "95th percentile man", "5 the 95th is taller on screen: %.0f px vs %.0f px; readout '%s'" % [bx2.size.y, h5, P.head_lab.text])
	# side by side: arms relaxed (a narrow body), no selection, no dummy; the same camera and floor for both shots, then each
	# body's band (its own columns of the picture) set left and right of the middle over the 95th's picture
	if m.dummy_on:
		m._dummy_toggle()
	m.sel = "pelvis"
	m._do(func(): m._arms_relaxed())
	var pic := {}
	for q in [5, 95]:
		P._quick(float(q))
		await idle(3)
		m._view(1)
		await idle(6)
		await RenderingServer.frame_post_draw
		pic[q] = m.get_viewport().get_texture().get_image()
		var bb := screen_box()
		boxes[q] = bb
		print("     %dth in the whole-body view: head top y %.0f, soles y %.0f (px), height %.0f px, soles %.1f mm off the floor" % [q, bb.position.y, bb.end.y, bb.size.y, m.B.sole_low() * 1000.0])
	var sc: float = float((pic[95] as Image).get_width()) / vs.x
	var cx := int(((boxes[95] as Rect2).get_center().x) * sc)
	var half := int(215.0 * sc)
	var out: Image = (pic[95] as Image).duplicate()
	var gap := int(230.0 * sc)
	var y0 := int(60.0 * sc)
	var hh := int((vs.y - m.bottom_h - 60.0) * sc)
	for pair in [[95, cx - gap - half], [5, cx + gap - half]]:
		var cxq := int(((boxes[pair[0]] as Rect2).get_center().x) * sc)
		out.blit_rect(pic[pair[0]], Rect2i(cxq - half, y0, 2 * half, hh), Vector2i(pair[1], y0))
	out.save_png(OUT)
	print("     screenshot: %s (%dx%d): the 95th (left) and the 5th (right), one camera" % [OUT, out.get_width(), out.get_height()])
	# ---- 4 nothing written
	ok(FileAccess.get_file_as_bytes("res://data/skeleton.json") == skel0, "4 data/skeleton.json is byte-identical")
	# leave the 95th undone, then mid-blend + proportions go through the same single step
	var uu: int = m.undo.size()
	await drag("arm", 90.0)
	await drag("blend", 40.0)
	var ar := BodyModel.measures(m.B)
	ok(m.undo.size() == uu + 2 and m.S.body.get("sex", "") == "female", "3 two more drags = two more steps (%d), the blend at 40 %% reads as a woman's table" % (m.undo.size() - uu))
	print("BODYPAGE %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
