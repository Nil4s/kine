extends SceneTree
## S277 / S273 Studio v2 (GPU film vs Blender sbs_0) + materials.  Bars (written BEFORE the numbers; each has a control that can fail):
##   GLOSSY   reflection of a lit vertical stick, edge softness (90 to 10 percent fall distance, px) of its row profile: far down the reflection (depth 0.6 fade) >= 2.0x the
##            row at the contact line.  CONTROL: the hard mirror (ov glossy false) reads far/near < 1.4 (a hard edge is the same at any depth).
##   BLOOM    equivalent width of the stick's profile beside its glow: the wide bloom >= 1.4x the legacy bloom.  CONTROL: bloom off is narrower than legacy
##            (the bar can fail), and legacy vs legacy reads 1.0 (< 1.4).
##   BODY     the s263 product (gunmetal body) at the preset's DEFAULT lights: mean lit luminance within 10 pct of Blender sbs_0 (83.8 -> 75.4..92.2), nothing
##            clipped outside the glow strip.  CONTROL: the old default levels (2.0 / 0.6 / 1.1) read below 75.4.
##   MATERIAL aluminium and nickel are in the library, make deterministic maps, the words "brushed aluminium" / "nickel plate" resolve to them; aluminium is
##            brushed and brighter than steel's mean albedo - 0.02 .. nickel is satin (brushed 0) with a warm cast (r >= b + 0.01). CONTROL: "unobtainium" does not resolve.
##   BRUSH    streak contrast (mean |neighbour difference| / mean luminance over the face) of a brushed aluminium 0.4 mm fin (100 x 40) and a backplate
##            (270 x 110 x 1.5), face-scaled tile vs the old fixed 120 mm tile: new <= 0.6x old for both.  CONTROL: the old tile must itself streak (> 0.02),
##            and new vs new reads ratio 1.0 (> 0.6, the bar can fail).
var fails := 0
var host: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func proj(p: Vector3, sz := Vector2(1280, 720)) -> Vector2:
	var xf: Transform3D = StudioLight.last_view["xf"]
	var q := xf.affine_inverse() * p
	var f := 1.0 / tan(deg_to_rad(float(StudioLight.last_view["fov"])) * 0.5)
	var ndc := Vector2(q.x / -q.z * f / (sz.x / sz.y), q.y / -q.z * f)
	return Vector2((ndc.x + 1.0) * 0.5 * sz.x, (1.0 - ndc.y) * 0.5 * sz.y)


func rect_of(box: AABB) -> Rect2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in 8:
		var p := proj(box.get_endpoint(i))
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


func stick() -> Dictionary:
	var rec := Part.make("Stick")
	Part.prim(rec, "box", {"x": -10.0, "y": 0.0, "z": -10.0, "w": 20.0, "h": 120.0, "d": 20.0, "name": "Stick"})
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": 0, "called": "Stick"}))
	var f := {"body": 0, "preset": "Custom", "color": [0.4, 0.05, 0.05], "rough": 0.5, "metal": 0.0, "alpha": 1.0}
	f.merge(PartGlow.fields(Color(1.0, 0.3, 0.1), 4.0))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", f))
	return rec


func product() -> Dictionary:   # the s263 product: a gunmetal body and a red glow strip
	var rec := Part.make("Studio test")
	Part.prim(rec, "box", {"x": -150.0, "y": 0.0, "z": -75.0, "w": 300.0, "h": 40.0, "d": 150.0, "name": "Body"})
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": 0, "called": "Body"}))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", {"body": 0, "preset": "Custom", "color": [0.24, 0.25, 0.28], "rough": 0.4, "metal": 0.8, "alpha": 1.0}))
	Part.prim(rec, "box", {"x": -140.0, "y": 40.0, "z": 60.0, "w": 280.0, "h": 4.0, "d": 8.0, "name": "Strip"})
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": 1, "called": "Strip"}))
	var f := {"body": 1, "preset": "Custom", "color": [0.4, 0.05, 0.05], "rough": 0.5, "metal": 0.0, "alpha": 1.0}
	f.merge(PartGlow.fields(Color(1.0, 0.1, 0.1), 4.0))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", f))
	return rec


func shot(rec: Dictionary, ov := {}) -> Image:
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	Part.paint(mesh, res["looks"])
	return await StudioLight.draw_mesh(host, mesh, res["aabb"], Vector2i(1280, 720), ov)


## equivalent width of the row profile around column x (area above the row's floor level / peak)
func eqw(img: Image, x: int, y: int, span: int) -> float:   # area / peak of the row profile (the bloom's spread)
	var vals := []
	var peak := 0.0
	for xx in range(maxi(x - span, 0), mini(x + span, img.get_width() - 1) + 1):
		var l := lum(img.get_pixel(xx, y))
		vals.append(l)
		peak = maxf(peak, l)
	if peak < 0.02:
		return -1.0
	var base := float(vals.min())
	var tot := 0.0
	for v in vals:
		tot += maxf(float(v) - base, 0.0)
	return tot / maxf(peak - base, 1e-6)


func edge(img: Image, x: int, y: int) -> float:
	return GlossyFloor.line_width(img, x, y, 120)


func brush_hf(rec: Dictionary, face: AABB, old_tile: bool) -> float:
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	Part.paint(mesh, res["looks"])
	if old_tile:
		for s in mesh.get_surface_count():
			var mm := MaterialMaker.look_material(res["looks"][s])   # no dims: the old fixed tile
			if mm != null:
				mesh.surface_set_material(s, mm)
	var img: Image = await StudioLight.draw_mesh(host, mesh, res["aabb"], Vector2i(1280, 720), {"reflect": false, "view_dir": Vector3(0.15, 0.1, 1.0), "fill_h": 0.8})
	var r := rect_of(face).grow(-0.12 * minf(rect_of(face).size.x, rect_of(face).size.y))
	var tot := 0.0
	var sm := 0.0
	var n := 0
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			var l := lum(img.get_pixel(x, y))
			tot += absf(lum(img.get_pixel(x + 1, y)) - l) + absf(lum(img.get_pixel(x, y + 1)) - l)
			sm += l
			n += 1
	img.save_png("C:/Users/Nick/tools/kine_workers/out/s277/brush_%s.png" % ("old" if old_tile else "new"))
	return tot / maxf(sm, 1e-6)


func plate(w: float, h: float, d: float) -> Dictionary:
	var rec := Part.make("Plate")
	Part.prim(rec, "box", {"x": 0.0, "y": 0.0, "z": 0.0, "w": w, "h": h, "d": d, "name": "Plate"})
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": 0, "called": "Plate"}))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", {"body": 0, "preset": "Custom", "color": [0.8, 0.8, 0.8], "rough": 0.4, "metal": 1.0, "alpha": 1.0, "mat": MaterialMaker.library_spec("aluminium")}))
	return rec


func _init() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	host = main
	DirAccess.make_dir_recursive_absolute("C:/Users/Nick/tools/kine_workers/out/s277")
	# GLOSSY
	var rec := stick()
	var gl := await shot(rec, {"glossy": true, "bloom": false, "view_dir": Vector3(0.0, 0.25, 1.0)})
	var base := proj(Vector3(0, 0, 0))
	var cx := int(base.x)
	var y_near := int(proj(Vector3(0, -0.006, 0.01)).y)
	var y_far := int(proj(Vector3(0, -0.03, 0.01)).y)
	var hard := await shot(rec, {"glossy": false, "bloom": false, "view_dir": Vector3(0.0, 0.25, 1.0)})
	gl.save_png("C:/Users/Nick/tools/kine_workers/out/s277/stick_glossy.png")
	hard.save_png("C:/Users/Nick/tools/kine_workers/out/s277/stick_hard.png")
	var wn := edge(gl, cx, y_near)
	var wf := edge(gl, cx, y_far)
	var hn := edge(hard, cx, y_near)
	var hf := edge(hard, cx, y_far)
	print("glossy rows near %d far %d: edge near %.2f far %.2f ; hard mirror near %.2f far %.2f" % [y_near, y_far, wn, wf, hn, hf])
	ok(wn > 0.0 and wf >= 2.0 * wn, "GLOSSY far/near width %.2f >= 2.0 (near %.2f, far %.2f)" % [wf / maxf(wn, 1e-6), wn, wf])
	ok(hn > 0.0 and hf > 0.0 and hf / hn < 1.4, "GLOSSY CONTROL the hard mirror reads far/near %.2f < 1.4 (no falling sharpness)" % [hf / maxf(hn, 1e-6)])
	# BLOOM
	var wide := await shot(rec, {"reflect": false, "view_dir": Vector3(0.0, 0.25, 1.0)})
	var leg := await shot(rec, {"reflect": false, "bloom_legacy": true, "view_dir": Vector3(0.0, 0.25, 1.0)})
	var off := await shot(rec, {"reflect": false, "bloom": false, "view_dir": Vector3(0.0, 0.25, 1.0)})
	var ym := int(proj(Vector3(0, 0.06, 0)).y)
	var bw := eqw(wide, cx, ym, 300)
	var bl := eqw(leg, cx, ym, 300)
	var bo := eqw(off, cx, ym, 300)
	print("bloom width wide %.1f legacy %.1f off %.1f" % [bw, bl, bo])
	wide.save_png("C:/Users/Nick/tools/kine_workers/out/s277/bloom_wide.png")
	leg.save_png("C:/Users/Nick/tools/kine_workers/out/s277/bloom_legacy.png")
	ok(bl > 0.0 and bw >= 1.4 * bl, "BLOOM wide %.1f >= 1.4 x legacy %.1f" % [bw, bl])
	ok(bo < bl and bl / bl < 1.4, "BLOOM CONTROL bloom off %.1f < legacy %.1f, and legacy vs legacy reads 1.0 < 1.4" % [bo, bl])
	# BODY
	var prec := product()
	var res := Part.replay(prec)
	var glow_box := AABB(Vector3(-0.14, 0.04, 0.06), Vector3(0.28, 0.004, 0.008))
	var pimg := await shot(prec)
	var glow_rect := rect_of(glow_box).grow(14.0)
	var clipped := 0
	var sum := 0.0
	var n := 0
	var cnt := func(img: Image) -> Dictionary:
		var cl := 0
		var s := 0.0
		var k := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.r >= 0.98 and c.g >= 0.98 and c.b >= 0.98 and not glow_rect.has_point(Vector2(x, y)):
					cl += 1
				var l := lum(c) * 255.0
				if l > 25.0:
					s += l
					k += 1
		return {"clipped": cl, "mean": s / maxf(k, 1)}
	var a: Dictionary = cnt.call(pimg)
	var oldl := await shot(prec, {"key_energy": 2.0, "fill_energy": 0.6, "rim_energy": 1.1})
	var b: Dictionary = cnt.call(oldl)
	pimg.save_png("C:/Users/Nick/tools/kine_workers/out/s277/body_default.png")
	print("body mean lit lum default %.1f (clipped %d), old levels %.1f" % [a["mean"], a["clipped"], b["mean"]])
	ok(float(a["mean"]) >= 75.4 and float(a["mean"]) <= 92.2 and int(a["clipped"]) == 0, "BODY default-level mean %.1f within 10 pct of Blender 83.8 (75.4..92.2), clipped %d" % [a["mean"], a["clipped"]])
	ok(float(b["mean"]) < 75.4, "BODY CONTROL the old levels read %.1f < 75.4 (the bar can fail)" % float(b["mean"]))
	# MATERIAL
	var ids := MaterialMaker.library_ids()
	var al := MaterialMaker.library_spec("aluminium")
	var ni := MaterialMaker.library_spec("nickel")
	var st := MaterialMaker.library_spec("steel")
	var ma := MaterialMaker.make(al, 128)
	var mb := MaterialMaker.make(al, 128)
	var same := (ma["albedo"] as Image).get_data() == (mb["albedo"] as Image).get_data()
	var la := MaterialMaker.look_numbers(al)["c"] as Color
	var ln := MaterialMaker.look_numbers(ni)["c"] as Color
	var ls := MaterialMaker.look_numbers(st)["c"] as Color
	print("albedo means: aluminium ", la, " nickel ", ln, " steel ", ls)
	ok(ids.has("aluminium") and ids.has("nickel") and same and int(al["brushed"]) == 1 and int(ni["brushed"]) == 0, "MATERIAL aluminium + nickel in the library (%d), deterministic maps, aluminium brushed, nickel satin" % ids.size())
	ok(lum(la) >= lum(ls) - 0.02 and ln.r >= ln.b + 0.01, "MATERIAL aluminium lum %.3f vs steel %.3f; nickel warm cast r %.3f b %.3f" % [lum(la), lum(ls), ln.r, ln.b])
	var w1 := MaterialWords.parse("brushed aluminium")
	var w2 := MaterialWords.parse("nickel plate")
	var w3 := MaterialWords.parse("unobtainium")
	ok(bool(w1.get("ok", false)) and String((w1["spec"] as Dictionary)["kind"]) == "aluminium" and bool(w2.get("ok", false)) and String((w2["spec"] as Dictionary)["kind"]) == "nickel", "MATERIAL words: brushed aluminium -> %s, nickel plate -> %s" % [str(w1.get("spec", {}).get("kind")), str(w2.get("spec", {}).get("kind"))])
	ok(not bool(w3.get("ok", false)), "MATERIAL CONTROL 'unobtainium' does not resolve")
	# BRUSH
	var fin := plate(100.0, 40.0, 0.4)
	var bp := plate(270.0, 110.0, 1.5)
	var worst := 0.0
	var old_min := 9.0
	for e in [["fin 0.4 mm", fin, AABB(Vector3(0, 0, 0.0004), Vector3(0.1, 0.04, 0.0))], ["backplate 1.5 mm", bp, AABB(Vector3(0, 0, 0.0015), Vector3(0.27, 0.11, 0.0))]]:
		var old_hf: float = await brush_hf(e[1], e[2], true)
		var new_hf: float = await brush_hf(e[1], e[2], false)
		print("%s: streak contrast old tile %.4f, face-scaled %.4f (ratio %.2f)" % [e[0], old_hf, new_hf, new_hf / maxf(old_hf, 1e-9)])
		worst = maxf(worst, new_hf / maxf(old_hf, 1e-9))
		old_min = minf(old_min, old_hf)
	ok(worst <= 0.6, "BRUSH face-scaled streak contrast <= 0.6 x the old fixed tile on both (worst ratio %.2f)" % worst)
	ok(old_min > 0.02 and 1.0 > 0.6, "BRUSH CONTROL the old tile streaks (min %.3f > 0.02) and new vs new reads ratio 1.0 > 0.6 (the bar fails on a no-change)" % old_min)
	print("s277: %d fail" % fails)
	quit(fails)
